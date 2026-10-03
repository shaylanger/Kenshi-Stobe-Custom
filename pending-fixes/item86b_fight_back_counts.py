#!/usr/bin/env python3
"""Item 86 (part 2): negotiation_review F6 ("player restarts the fight" = the player attacks and the
NPC attacks back) must still be the player's breach. Real evidence of a restarted fight = harm to the
NPC from the player side OR the NPC attacking the player side right after (item 86's m8 case had
neither: the game only re-reported the player's 'Initiated attack' while the truce held).
Usage: item86b_fight_back_counts.py <tree root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / 'lib/negotiation_engine.php'
s = p.read_text(encoding='utf-8')
old = r'''            "SELECT type, data FROM eventlog WHERE type IN ('major_damage','knockout','death')
               AND localts >= $1 AND localts <= $2 AND data LIKE $3 ORDER BY localts LIMIT 40",'''
new = r'''            "SELECT type, data FROM eventlog WHERE type IN ('major_damage','knockout','death','combat')
               AND localts >= $1 AND localts <= $2 AND data LIKE $3 ORDER BY localts LIMIT 40",'''
add_old = r'''        if ($row['type'] === 'death') return true;'''
add_new = r'''        if ($row['type'] === 'death') return true;
        // item 86b: he fights back right after (a restarted fight, not a re-reported attack)
        if ($row['type'] === 'combat' && preg_match('/:\s*Initiated attack\s*\(talking to:\s*(.+?)\)\s*$/', $data, $m)
            && stobeNegIsPlayerSide(trim($m[1]), $player)) return true;'''
if add_new in s:
    print('lib already patched')
else:
    assert s.count(old) == 1 and s.count(add_old) == 1
    s = s.replace(old, new).replace(add_old, add_new)
    p.write_text(s, encoding='utf-8')
    print('lib patched')
t = root / 'tests/negotiation_engine_regression.php'
ts = t.read_text(encoding='utf-8')
told = r'''backdate($id, 7);
storeEvent('combat', time(), 1000, "$player: Initiated attack (talking to: NegTestBandit)");
stobeNegTick();
// Item 86 (run m8)'''
tnew = r'''backdate($id, 7);
$db->exec("DELETE FROM eventlog WHERE data LIKE 'NegTestBandit: Initiated attack%'"); // item 86b: he doesn't fight back here (m8)
storeEvent('combat', time(), 1000, "$player: Initiated attack (talking to: NegTestBandit)");
stobeNegTick();
// Item 86 (run m8)'''
if tnew not in ts:
    assert ts.count(told) == 1
    t.write_text(ts.replace(told, tnew), encoding='utf-8')
    print('test patched')
