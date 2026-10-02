#!/usr/bin/env python3
"""Plan item 47: an action target by a shared name can resolve to a corpse.

Run 12 (gang of spawned raiders, the extra squad members killed next to the fight):
Shay's voice payment "Deal, 300. Here are your cats." went out as
GIVE_CATS@Dust Bandit@300; resolveActionTargetHand matched every "<name> [Dust Bandit]"
by substring (180) and the nearest one won: Doran, DEAD. The give fell back to Shay
herself and was blocked (reason=self_transfer); the deal stayed AWAITING_PLAYER.
Now a dead candidate scores 1 after all bonuses unless its serial was asked for, so
any living NPC with the name wins; a corpse is only picked when nobody alive matches.

Usage: patch_dll_r24_target_prefers_living.py <STOBE-src root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'src' / 'main.cpp'
s = f.read_text(encoding='utf-8')
if 'item 47: a corpse' in s:
    print('already patched'); sys.exit(0)

# the scoring loop of resolveActionTargetHand: its best-score update (with the
# serial early exit) is unique
old = """                if (score > bestScore) {
                  bestScore = score;
                  bestMatch = candidate;
                  if (score == 1000) {
                    break;"""
new = """                if (score > 1 && !(hasSerial && candidateSerial == wantedSerial)) {
                  // item 47: a corpse with the same name must not win over the living
                  try {
                    if (candidate->isDead())
                      score = 1;
                  } catch (...) {
                  }
                }
""" + old
n = s.count(old)
assert n == 1, f'anchor found {n}x'
s = s.replace(old, new)
f.write_text(s, encoding='utf-8')
print('patched', f)
