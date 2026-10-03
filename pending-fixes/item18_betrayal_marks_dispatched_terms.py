#!/usr/bin/env python3
"""STOBE 18 (m17 Full-Base): an executed betrayal marks the NPC's in-flight terms too.

The betrayal path marked only WAITING_FOR_PLAYER terms as BETRAYED/intentional_betrayal. In a
"pay now" combat deal the NPC's STOP_ATTACK is dispatched at once (not waiting), so a forced
betrayal ended BREACHED_NPC with no intentional marker on any term. Now the NPC's terms still in
flight (PENDING/DISPATCHED/REISSUE_QUEUED) get the same marker.

Usage: item18_betrayal_marks_dispatched_terms.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

patch("lib/negotiation_engine.php",
"""            foreach ($waiting as $idx) {
                $state[$idx]['status'] = 'BETRAYED';
                $state[$idx]['evidence'][] = ['at'=>$now, 'note'=>'intentional_betrayal'];
            }
            $betrayal['executed'] = $now;
""",
"""            foreach ($waiting as $idx) {
                $state[$idx]['status'] = 'BETRAYED';
                $state[$idx]['evidence'][] = ['at'=>$now, 'note'=>'intentional_betrayal'];
            }
            // STOBE 18: a "pay now" deal has the NPC's STOP_ATTACK already dispatched; it is betrayed too.
            foreach ($state as $idx => $term) {
                if (($term['by'] ?? '') === 'npc' && in_array($term['status'] ?? '', ['PENDING','DISPATCHED','REISSUE_QUEUED'], true)) {
                    $state[$idx]['status'] = 'BETRAYED';
                    $state[$idx]['evidence'][] = ['at'=>$now, 'note'=>'intentional_betrayal'];
                }
            }
            $betrayal['executed'] = $now;
""")

patch("tests/negotiation_engine_regression.php",
"""check('STOBE 18: forced betrayal -> BREACHED_NPC', status($id) === 'BREACHED_NPC', status($id));
""",
"""check('STOBE 18: forced betrayal -> BREACHED_NPC', status($id) === 'BREACHED_NPC', status($id));
check('STOBE 18: pay-now deal: the dispatched STOP_ATTACK is marked intentional_betrayal', termStatus($id, 1) === 'BETRAYED'
    && str_contains(json_encode(stobeNegFetchDeal($id)['term_state']), 'intentional_betrayal'), termStatus($id, 1));
""")

# m18: with a player SPARE term the betrayal fires after the 120 s truce watch, when the NPC's STOP_ATTACK is
# already VERIFIED; the betrayal breaks that truce, so it is marked as well (not other verified terms).
patch("lib/negotiation_engine.php",
"""                if (($term['by'] ?? '') === 'npc' && in_array($term['status'] ?? '', ['PENDING','DISPATCHED','REISSUE_QUEUED'], true)) {""",
"""                $keptTruce = ($term['status'] ?? '') === 'VERIFIED' && in_array($term['kind'] ?? '', ['STOP_ATTACK','SPARE'], true);
                if (($term['by'] ?? '') === 'npc' && ($keptTruce || in_array($term['status'] ?? '', ['PENDING','DISPATCHED','REISSUE_QUEUED'], true))) {""")

patch("tests/negotiation_engine_regression.php",
"""// ---------------------------------------------------------------- Item 107:""",
"""// STOBE 18 m18: a verified truce (player SPARE watched 120 s first) is marked betrayed too.
$db->exec("DELETE FROM general_settings WHERE id='NEG_TEST_FORCE_BETRAYAL'");
$db->exec("INSERT INTO general_settings (id, value) VALUES ('NEG_TEST_FORCE_BETRAYAL', 'true')");
$id = makeDeal('NegTestTrader', [['kind'=>'GIVE_CATS','by'=>'player','to'=>'npc','amount'=>42], ['kind'=>'STOP_ATTACK','by'=>'npc','target'=>'player']]);
stobeNegBeginPerformance($id, ['STOP_ATTACK@' . $player], $player, 1000, '');
$st18 = stobeNegDecode(stobeNegFetchDeal($id)['term_state']);
$st18[1]['status'] = 'VERIFIED';
$db->exec("UPDATE stobe_social_contract SET term_state=$2::jsonb, performance_started_unix = performance_started_unix - 25 WHERE contract_id=$1", [$id, json_encode($st18)]);
stobeLine("ACTION_EXEC: GIVE_CATS actor=$player recipient=NegTestTrader amount=42", time());
stobeNegTick();
check('STOBE 18 m18: a verified STOP_ATTACK is marked intentional_betrayal', status($id) === 'BREACHED_NPC' && termStatus($id, 1) === 'BETRAYED', [status($id), termStatus($id, 1)]);
$db->exec("DELETE FROM general_settings WHERE id='NEG_TEST_FORCE_BETRAYAL'");
$db->exec("DELETE FROM stobe_negotiation_directive");

// ---------------------------------------------------------------- Item 107:""")
