#!/usr/bin/env python3
"""Item 64: negotiation_engine 'unpaid -> BREACHED_PLAYER' backdated only wall time, but hostile deals
expire when BOTH clocks run out (bug 41: real time AND game time). The test now also backdates
game time. Usage: item64_test_backdate_gametime.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / 'tests/negotiation_engine_regression.php'
s = p.read_text(encoding='utf-8')

def rep(old, new):
    global s
    if new in s:
        print('already patched:', new.splitlines()[0][:60]); return
    assert s.count(old) == 1, f'anchor found {s.count(old)} times: {old[:60]}'
    s = s.replace(old, new)

rep('''function status(string $id): string { return strval(stobeNegFetchDeal($id)['status']); }''',
'''/** Item 64: move the deal's game-time deadline back and make sure the game clock is seen at the deal's start time. */
function backdateGame(string $id, int $gamets): int {
    $d = stobeNegFetchDeal($id);
    $GLOBALS['db']->exec("UPDATE stobe_social_contract SET deadline_gamets=GREATEST(1, deadline_gamets-$2) WHERE contract_id=$1", [$id, $gamets]);
    $start = max(1, intval($d['deadline_gamets'] ?? 0) - STOBE_NEG_PAY_WINDOW_GAMETS);
    $GLOBALS['db']->exec("INSERT INTO eventlog (type, ts, gamets, data, sess, localts, people, location) VALUES ('info',$1,$2,'NegTest game clock','pending',$1,'','')",
        [time(), $start]);
    return $start;
}
function status(string $id): string { return strval(stobeNegFetchDeal($id)['status']); }''')

rep('''backdate($id, 61);
stobeNegTick();
check('unpaid -> BREACHED_PLAYER', status($id) === 'BREACHED_PLAYER', status($id));''',
'''// Item 64: past the pay window AND the truce watch (120 s since bug 90; the breach waits for NPC terms in flight),
// and past the game-time pay window (hostile deals expire on game time too, bug 41).
backdate($id, max(61, STOBE_NEG_TRUCE_OBSERVE_SECONDS + 1));
backdateGame($id, STOBE_NEG_PAY_WINDOW_GAMETS + 1);
stobeNegTick();
check('unpaid -> BREACHED_PLAYER', status($id) === 'BREACHED_PLAYER', status($id));
$db->exec("DELETE FROM eventlog WHERE data='NegTest game clock'");''')

p.write_text(s, encoding='utf-8')
print('tests/negotiation_engine_regression.php: patched')
