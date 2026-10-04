#!/usr/bin/env python3
"""STOBE A12: "I'm not going to heal you" breaks a heal-for-item deal like "I'm not paying" breaks a paid one.

stobeNegPlayerRefusal only knew pay/give/hand verbs, so after she handed her rags over first (heal deal: player
FIRST_AID after_npc), Shay's "Thanks. I'm not going to heal you, though." left the FIRST_AID term AWAITING_PLAYER
until its deadline instead of UNMET -> BREACHED_PLAYER at once. Now heal/bandage/patch/treat count too.

Usage: itemA12_refusing_to_heal_is_a_refusal.py <tree root>
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
"""            if (preg_match("/\\\\b(not|never|won'?t|wont|ain'?t|no way|refuse to)\\\\b[^.!?]{0,25}\\\\b(pay|paying|give|giving|hand|handing)\\\\b/", $sentence)""",
"""            // A12: refusing the heal of a heal-for-item deal is a refusal too.
            if (preg_match("/\\\\b(not|never|won'?t|wont|ain'?t|no way|refuse to)\\\\b[^.!?]{0,25}\\\\b(pay|paying|give|giving|hand|handing|heal|healing|bandage|bandaging|patch|patching|treat|treating)\\\\b/", $sentence)""")

patch("tests/negotiation_engine_regression.php",
"""// ---------------------------------------------------------------- cleanup
""",
"""// ---------------------------------------------------------------- STOBE A12: refusing to heal breaks a heal deal
fixtureNpc('NegTestSenlinA12', ['money'=>20, 'money_observed_at'=>time()], 'Rag Loincloth x1 value 10', 'Calm.');
$idA12 = makeDeal('NegTestSenlinA12', [['kind'=>'FIRST_AID', 'by'=>'player', 'target'=>'npc', 'when'=>'after_npc'],
    ['kind'=>'GIVE_ITEM', 'by'=>'npc', 'to'=>'player', 'item'=>'Rag Loincloth']], 'social');
stobeNegBeginPerformance($idA12, ['GIVE_ITEM@' . $player . '@Rag Loincloth@1'], $player, 1000, '');
$noteA12 = stobeNegPlayerRefusal('NegTestSenlinA12', $player, "Thanks. I'm not going to heal you, though.");
check('A12: "not going to heal you" is a refusal of the heal term', $noteA12 !== '' && termStatus($idA12, 0) === 'UNMET', [$noteA12, termStatus($idA12, 0)]);
$db->exec("DELETE FROM core_npc_master WHERE name='NegTestSenlinA12'");

// ---------------------------------------------------------------- cleanup
""")
