#!/usr/bin/env python3
"""m23 fixer 10: rel-b55 accident block setup.
KO: the hit landed 7 s after the load, before Stobe's first post-load NPC world event sweep (45 s warmup after world stable),
so Malzin was first seen already KO and no knockout was reported -> fresh() now waits for 'NPC world event sweep complete'.
Injury: Malzin never woke from head -30.6 -> `protect` wakes her after the KO measurement; the injury block requires her
conscious (SETUP FAIL otherwise) and the bandit still under his name.
Usage: m23-rel-b55-accident.py <file rel-b55.sh>  (writes <file>.new; mv it into place)"""
import sys
src = sys.argv[1]; s = open(src).read()
def sub(old, new):
    global s
    assert s.count(old) == 1, f"anchor: {old[:70]!r}"
    s = s.replace(old, new)
sub("""fresh(){ stobe-auto load auto-home >/dev/null; sleep 12; stobe-auto wait-world 240 >/dev/null; sleep 8
""", """fresh(){ local m; m=$(lines $L); FRESH_SWEEP=0
  stobe-auto load auto-home >/dev/null; sleep 12; stobe-auto wait-world 240 >/dev/null; sleep 8
  # m23: Stobe's NPC event sweep starts 45 s (wall clock) after the world is stable; a KO before it is never reported
  for i in $(seq 1 45); do since $L $m | grep -a -q "HOOK_LOAD_PROBE: NPC world event sweep complete" && { FRESH_SWEEP=1; break; }; sleep 2; done
""")
sub("""  fresh
  insp --set-switch SOCIAL_GRUDGE_FADE_DAYS 0.05 > "$O/accident.setup.txt" 2>&1""",
"""  fresh
  if [ "$FRESH_SWEEP" != 1 ]; then v "accident KO: SETUP FAIL no 'NPC world event sweep complete' in stobe.log 90 s after the load"
    v "accident injury: SETUP FAIL (no post-load event sweep)"; continue; fi
  insp --set-switch SOCIAL_GRUDGE_FADE_DAYS 0.05 > "$O/accident.setup.txt" 2>&1""")
sub("""  # wake Shay, then fade check: 90 game min (> 0.05 game days) + a fight as ingest tick: the accidental KO must stay
  for i in $(seq 1 60); do stobe-auto where Malzin | grep -q ' KO' || break; stobe-say speed 1 >/dev/null; sleep 2; done
  stobe-auto speed 0 >/dev/null""",
"""  # wake Malzin (m23: head -30.6 kept her down for the whole block): protect heals + clears the KO, then off again;
  # then fade check: 90 game min (> 0.05 game days) + a fight as ingest tick: the accidental KO must stay
  stobe-auto protect Malzin on >/dev/null; stobe-say speed 1 >/dev/null
  for i in $(seq 1 20); do stobe-auto where Malzin | grep -q ' KO' || break; sleep 2; done
  stobe-auto protect Malzin off >/dev/null; stobe-auto speed 0 >/dev/null""")
sub("""  b=$(bandit "Rel Brawl") || { v "accident injury: FAIL no bandit"; continue; }""",
"""  b=$(bandit "Rel Brawl") || { v "accident injury: SETUP FAIL no bandit"; continue; }
  if stobe-auto where Malzin | grep -q ' KO'; then v "accident injury: SETUP FAIL Malzin still KO after protect (no fight possible)"; away "$b"; continue; fi
  stobe-auto chars 80 | tr '|' '\\n' | grep -q "Rel Brawl" || { v "accident injury: SETUP FAIL bandit lost the name Rel Brawl (renamed)"; away "$b"; continue; }""")
sub("""  elif [ ! -s "$O/accident.log2.txt" ]; then v "accident injury: INCONCLUSIVE no harm event for the hit (Stobe emits injury only with combat evidence; accident.hit2.txt)\"""",
"""  elif [ ! -s "$O/accident.log2.txt" ]; then v "accident injury: FAIL no harm event for a hit inside a real fight (Malzin was up and fighting; accident.hit2.txt)\"""")
open(src + '.new', 'w').write(s); print("wrote", src + '.new')
