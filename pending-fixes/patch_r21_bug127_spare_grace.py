#!/usr/bin/env python3
"""Bug 127: the squad's follow-through right after a truce breaks SPARE.

Run 9 (test 19): Shay accepted Vorl's surrender; 5 s later Shay's own combat
AI was still swinging (and Malzin at +9 s), and the SPARE term went UNMET
("player_side_attacked_after_sparing"). The truce side already gives the
player's squad 10 s to stop ("call them off"); SPARE only allowed 3 s. Same
10 s grace for SPARE now.

Usage: patch_r21_bug127_spare_grace.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'negotiation_engine.php'
text = path.read_text(encoding='utf-8')
old = """    } elseif ($kind === 'SPARE') {
        foreach (stobeNegCombatEvents($start + 3, $npc) as $ev) {
            if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)) {"""
new = """    } elseif ($kind === 'SPARE') {
        foreach (stobeNegCombatEvents($start + 3, $npc) as $ev) {
            // Bug 127: the same 10 s as the truce for the squad to stop swinging.
            if (intval($ev['ts'] ?? 0) < $start + 10) continue;
            if (stobeNegCharMatches($ev['target'], $npc) && stobeNegIsPlayerSide($ev['attacker'], $player)) {"""
if 'Bug 127' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
