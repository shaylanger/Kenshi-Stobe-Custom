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
