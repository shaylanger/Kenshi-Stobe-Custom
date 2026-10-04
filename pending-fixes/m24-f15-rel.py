#!/usr/bin/env python3
"""m24 fixer 15: REL SR09 witness readiness + B55 bleed wake setup (test files only).

usage: python3 m24-f15-rel.py <StobeServer tree root>

SR09 (REL-p3-06 + rel-m18.sh): m22 H take had Rel Wren (FOLLOW_WHILE_TALKING, 14 m off) with sees_actor,
  sees_target and hears_actor all false: her AI never listed Malzin. She now idles 3 m from the body (as Rel Tess
  in p5-03, who saw the take) and the take waits until her AI sees Malzin (harness `senses`, KAH 2758ee7).
  rel-m18.sh: SETUP FAIL when that poll failed (instead of a product FAIL).
B55 bleed (rel-b55.sh): m22 H Rel Vex stayed KO the whole window: the leg cuts from fightko bleed, the watchdog only
  topped blood to 40 % (below the game's collapse point), so he could never wake. Blood is now kept above the
  collapse point (+15 %, reported by `blood`); the deep arm wound (-70 %) alone makes him near death on waking.
  Still KO after the window = SETUP FAIL with blood/collapse numbers.
"""
import sys, os

root = sys.argv[1]
d = os.path.join(root, 'tests/social_relationship/ingame')


def patch(name, pairs):
    p = os.path.join(d, name)
    s = open(p, newline='').read()
    for a, b in pairs:
        if b in s:
            continue  # already applied
        assert s.count(a) == 1, (name, a[:80], s.count(a))
        s = s.replace(a, b)
    open(p, 'w', newline='').write(s)
    print('patched', p)


OLD_P306 = """# M24_F12: a teleport leaves her senses stale (m22 F: 3 m away, sees_actor=false): she follows Malzin (faces her) 2 s first
order ${W} FOLLOW_WHILE_TALKING target Malzin
speed 1
@sleep 2
speed 0
where ${W}
transfer ${V} Malzin "Iron Plates"
"""
NEW_P306 = """# M24_F15: FOLLOW_WHILE_TALKING walked her 14 m off and her AI never listed Malzin (m22 H: sees_actor, sees_target,
# hears_actor all false). She idles (as Rel Tess in p5-03, who saw the take); the take waits until her AI sees Malzin.
# A failed poll here is a SETUP failure (rel-m18.sh reports it), not a product FAIL.
order ${W} IDLE
speed 1
@until 30 senses ${W} Malzin ~ sees=1
speed 0
senses ${W} Malzin
where ${W}
transfer ${V} Malzin "Iron Plates"
"""

patch('REL-p3-06-ko-loot-witnessed.txt', [(OLD_P306, NEW_P306)])

OLD_M18 = """insp --pair-effects --incidents 10 --interpret-log 60 --log-filter "$V" --check-shadow > "$O/p3-06.inspect.txt" 2>&1
if grep -q"""
NEW_M18 = """insp --pair-effects --incidents 10 --interpret-log 60 --log-filter "$V" --check-shadow > "$O/p3-06.inspect.txt" 2>&1
# M24_F15: the witness's AI must see Malzin before the take (harness senses poll); else the row is a SETUP failure
if grep -q '^FAIL .*senses .* Malzin' "$O/REL-p3-06-ko-loot-witnessed.out"; then v "SR09: SETUP FAIL witness never saw Malzin before the take ($(grep -m1 '^FAIL .*senses' "$O/REL-p3-06-ko-loot-witnessed.out" | cut -c1-160))"
elif grep -q"""
patch('rel-m18.sh', [(OLD_M18, NEW_M18),
                     ('then v "SR09: known thief recorded (check', 'then v "SR09: PASS known thief recorded (check')])

OLD_B1 = "#   bleed  KO + blood 25 % + deep wound, wake: critical_harm row (-55..-65 band)                         (item 7)"
NEW_B1 = "#   bleed  KO + deep arm wound (-70 %), blood kept above collapse, wake: critical_harm row (-55..-65 band) (item 7)"
OLD_B2 = """  stobe-say speed 3 >/dev/null
  for i in $(seq 1 80); do hl=$(stobe-auto hp "$h"); echo "$hl" | grep -q ' KO' || break
    bf=$(echo "$hl" | grep -o 'blood=[0-9.]*/[0-9.]*' | head -1 | awk -F'[=/]' '{ if ($3 > 0) printf "%d", 100 * $2 / $3 }')
    if [ -n "$bf" ] && [ "$bf" -lt 30 ]; then stobe-auto blood "$h" 40% >/dev/null; echo "watchdog: blood $bf% -> 40%" >> "$O/bleed.setup.txt"; fi
    sleep 2; done
  sleep 10; stobe-auto speed 0 >/dev/null
"""
NEW_B2 = """  # M24_F15: m22 H he never woke: the fightko leg cuts bleed and 40 % blood is below the game's collapse point, so the
  # KO never ended. Blood stays above collapse (+15 %); near death on waking comes from the -70 % arm alone.
  bl=$(stobe-auto blood "$h" 100%); echo "$bl" >> "$O/bleed.setup.txt"
  col=$(echo "$bl" | grep -o 'blood [-0-9.]* -> [0-9.]*/[0-9.]* (collapse below [0-9.]*' | awk '{ split($4, m, "/"); if (m[2] > 0) printf "%d", 100 * $NF / m[2] }')
  [ -n "$col" ] || col=60
  floor=$((col + 15))
  stobe-say speed 3 >/dev/null; bf=""
  for i in $(seq 1 80); do hl=$(stobe-auto hp "$h"); echo "$hl" | grep -q ' KO' || break
    bf=$(echo "$hl" | grep -o 'blood=[0-9.]*/[0-9.]*' | head -1 | awk -F'[=/]' '{ if ($3 > 0) printf "%d", 100 * $2 / $3 }')
    if [ -n "$bf" ] && [ "$bf" -lt "$floor" ]; then stobe-auto blood "$h" 100% >/dev/null; echo "watchdog: blood $bf% -> 100% (collapse $col%)" >> "$O/bleed.setup.txt"; fi
    sleep 2; done
  stillko=0; stobe-auto where "$h" | grep -q ' KO' && stillko=1
  sleep 10; stobe-auto speed 0 >/dev/null
"""
OLD_B3 = """  elif ! grep -q '"known"' "$O/bleed.stobe.txt"; then v "bleed: FAIL no recovered fact"""
NEW_B3 = """  elif [ "$stillko" = 1 ]; then v "bleed: SETUP FAIL Rel Vex still KO after the window (blood ${bf:-?}%, collapse ${col}%; bleed.setup.txt)"
  elif ! grep -q '"known"' "$O/bleed.stobe.txt"; then v "bleed: FAIL no recovered fact"""
patch('rel-b55.sh', [(OLD_B1, NEW_B1), (OLD_B2, NEW_B2), (OLD_B3, NEW_B3)])
