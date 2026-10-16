#!/usr/bin/env python3
"""patch27a_tests.py <NPC_IMMERSION_26_TESTS.md>   row 27-a wording after the recipe fix (verdict stays FAIL until the live rerun). Idempotent, anchors asserted."""
import sys

p = sys.argv[1]
t = open(p, encoding='utf-8', newline='').read()
if '27A-FIX' in t:
    print('patch27a_tests: already applied')
    sys.exit(0)
R = [("harness contract + Shay teleported 80 u away and held (speed 3) before and after the load",
      "harness contract + Shay teleported 200 u away (RW_AWAY_BG) and held (speed 3): a no-contract control chase before the hire, then again before and after the load"),
     ("NPC closes the distance before and after. FAIL = the order is LOST on load",
      "pass = `end <= 100 u after Shay moved 200 u` (RW_BG_NEAR; the native Bodyguard package keeps a 50-67 u stand-off) before and after the load, contract hours_left reduced after the load, and the no-contract control NPC does not approach (end >= 0.8 x start, else SETUP-FAIL). FAIL = the order is LOST on load"),
     ("native/harness question for the bodyguard owner, not a recipe issue",
      "27A-FIX re-diagnosed 2026-10-16 (agents/out/imm26-inv-27a/latest.md): recipe/assertion defect, NOT a product defect (35 u limit never fits the 50-67 u stand-off; pre sample taken after the NPC already closed 20-40 u); fix = limit 100 u, Shay moved 200 u, negative control (pending-fixes/27a-recipe); row stays FAIL until the live rerun")]
for old, new in R:
    assert t.count(old) == 1, 'anchor not found exactly once: ' + old[:60]
for old, new in R:
    t = t.replace(old, new)
open(p, 'w', encoding='utf-8', newline='').write(t)
print('patch27a_tests: patched', p)
