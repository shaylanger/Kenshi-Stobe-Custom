#!/usr/bin/env python3
"""Plan item 46, part 2: the player's STOP_ATTACK on the NPC is a SPARE.

Run 12: "Hesk, you're beaten. You give me 100 cats and I let you go." -> ACCEPT,
terms [npc GIVE_CATS 100 -> player, {"kind":"STOP_ATTACK","by":"player","target":"npc"}]
-> "wrong_performer" (STOP_ATTACK is the NPC's term), nothing recorded.
Now STOP_ATTACK by the player against the NPC becomes SPARE (the player's term).
Log: `Negotiation term fixed: the player's STOP_ATTACK is SPARE (item 46)`.

Usage: patch_r24_player_stop_attack_is_spare.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, anchor, new, marker, before=True):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(anchor)
    assert n == 1, f'{rel}: anchor found {n}x: {anchor[:60]!r}'
    s = s.replace(anchor, new + anchor if before else anchor + new)
    f.write_text(s, encoding='utf-8')
    print('patched', rel)

patch('lib/negotiation_phase1.php',
      "        if (!in_array($kind, ['STOP_ATTACK','FIRST_AID','SAFE_PASSAGE','SPARE','PROTECT'], true)) continue;\n",
      """        if ($kind === 'STOP_ATTACK' && ($t['by'] ?? '') === 'player'
            && in_array(strval($t['target'] ?? ($t['to'] ?? 'npc')), ['npc',''], true)) {
            $terms[$i] = ['kind'=>'SPARE', 'by'=>'player', 'target'=>'npc'];
            stobeDealLog('info', "Negotiation term fixed: the player's STOP_ATTACK is SPARE (item 46)", []);
            continue;
        }
""", "the player's STOP_ATTACK is SPARE", before=True)

TEST = r'''$t46c = stobeDealFixTargetField([
    ['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>100],
    ['kind'=>'STOP_ATTACK','by'=>'player','target'=>'npc'],
]);
check("item 46: the player's STOP_ATTACK becomes SPARE", ($t46c[1]['kind'] ?? '') === 'SPARE' && ($t46c[1]['target'] ?? '') === 'npc', $t46c);
check('item 46: that deal validates', stobeDealValidate(['parties'=>['npc'=>'a','player'=>'b'],'terms'=>$t46c])['ok'] === true);

'''
patch('tests/negotiation_engine_regression.php',
      "// ---------------------------------------------------------------- 13. toggles",
      TEST, "STOP_ATTACK becomes SPARE")
