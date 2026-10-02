#!/usr/bin/env python3
"""Plan item 46, part 3: the player's SAFE_PASSAGE for the NPC is a SPARE, too.

Run 12, after part 2: "you give me 100 cats and I let you go. Deal?" -> ACCEPT with
{"kind":"SAFE_PASSAGE","by":"player","to":"npc"} -> wrong_performer, nothing recorded.
Part 2's rule (player STOP_ATTACK -> SPARE) now covers SAFE_PASSAGE by the player.
Run after patch_r24_player_stop_attack_is_spare.py.

Usage: patch_r24_player_safe_passage_is_spare.py <StobeServer tree>  (idempotent)
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])

def patch(rel, old, new, marker):
    f = root / rel
    s = f.read_text(encoding='utf-8')
    if marker in s:
        print('already patched', rel); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n}x: {old[:60]!r}'
    f.write_text(s.replace(old, new), encoding='utf-8')
    print('patched', rel)

patch('lib/negotiation_phase1.php',
      "        if ($kind === 'STOP_ATTACK' && ($t['by'] ?? '') === 'player'\n",
      "        if (in_array($kind, ['STOP_ATTACK','SAFE_PASSAGE'], true) && ($t['by'] ?? '') === 'player' // item 46\n",
      "['STOP_ATTACK','SAFE_PASSAGE'], true) && ($t['by'] ?? '') === 'player' // item 46")
patch('lib/negotiation_phase1.php',
      """"Negotiation term fixed: the player's STOP_ATTACK is SPARE (item 46)", []);""",
      """"Negotiation term fixed: the player's STOP_ATTACK/SAFE_PASSAGE is SPARE (item 46)", ['kind'=>$kind]);""",
      "STOP_ATTACK/SAFE_PASSAGE is SPARE")

f = root / 'tests/negotiation_engine_regression.php'
s = f.read_text(encoding='utf-8')
if 'SAFE_PASSAGE becomes SPARE' not in s:
    anchor = "// ---------------------------------------------------------------- 13. toggles"
    assert s.count(anchor) == 1
    s = s.replace(anchor, r'''$t46d = stobeDealFixTargetField([['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>100], ['kind'=>'SAFE_PASSAGE','by'=>'player','to'=>'npc']]);
check("item 46: the player's SAFE_PASSAGE becomes SPARE", ($t46d[1]['kind'] ?? '') === 'SPARE' && stobeDealValidate(['parties'=>['npc'=>'a','player'=>'b'],'terms'=>$t46d])['ok'] === true, $t46d);

''' + anchor)
    f.write_text(s, encoding='utf-8'); print('patched tests')
