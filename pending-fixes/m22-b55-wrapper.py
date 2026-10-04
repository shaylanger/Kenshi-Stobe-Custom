#!/usr/bin/env python3
"""m22 rel-b55.sh wrapper fixes (squad/bleed/chat KO credit, bleed death, fade/accident paused waits, accident KO
strength + log-delta check, treat waits for the aid fact, wild by names near Shay, deal Shay strikes first).
Usage: m22-b55-wrapper.py <tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]); d = root / 'tests/social_relationship/ingame'
def patch(f, pairs):
    if not f.exists(): print('skip (absent)', f); return
    s = f.read_text()
    for old, new in pairs:
        if new in s: continue
        assert s.count(old) == 1, (f.name, old[:70])
        s = s.replace(old, new)
    f.write_text(s)
patch(d / 'rel-b55.sh', [
 # Malzin far away: she joined the fights and took the KO credit (squad/bleed/chat)
 ('  stobe-auto teleport Malzin Shay dist 25 >/dev/null; }',
  '  stobe-auto teleport Malzin Shay dist 300 >/dev/null; }   # m22: at 25 m she joined and took the KO credit'),
 ('Block "bleed" also needs Stobe built with pending-fixes/b55_recovered_vitals_native.py (vitals on waking).',
  'Block "bleed" reads the vitals Stobe sends with the recovered fact (b55_recovered_vitals_native.py, built in).'),
 # wild: by names (the handle changes with the faction), 60 m from Shay (300 m fights are not captured)
 ('  b=$(stobe-auto chars 80 | tr \'|\' \'\\n\' | grep \'Rel Bek\' | grep -o \'#[0-9]*/[0-9]*\' | head -1)\n',
  '  a="Rel Arn"; b="Rel Bek"   # m22: names; the re-resolved handle came back empty and Shay was teleported instead\n'),
 ('  stobe-auto teleport "$a" Shay dist 300 >/dev/null; stobe-auto teleport "$b" "$a" dist 3 >/dev/null',
  '  stobe-auto teleport "$a" Shay dist 60 >/dev/null; stobe-auto teleport "$b" "$a" dist 3 >/dev/null'),
 # treat: wait for the aid fact, not the first bandage tick; move Shay (a KO body cannot be teleported)
 ('  sleep 10; stobe-auto teleport "$h" Shay dist 40 >/dev/null; stobe-say speed 1 >/dev/null; sleep 10; stobe-auto speed 0 >/dev/null\n',
  '  for i in $(seq 1 90); do since $WL $w0 | grep -a "SOCIAL_INTERPRET" | grep -a "Rel Tam" | grep -a -q -e \'"kind":"aid"\' -e treated_relief && break; sleep 2; done\n'
  '  stobe-auto teleport Shay "$h" dist 40 >/dev/null; stobe-say speed 1 >/dev/null; sleep 10; stobe-auto speed 0 >/dev/null\n'),
 # fade: the wait ran paused (speed 0) -> no game time passed
 ('  stobe-auto wait-game 90 > "$O/fade.wait.txt" 2>&1\n',
  '  stobe-say speed 3 >/dev/null; stobe-auto wait-game 90 > "$O/fade.wait.txt" 2>&1; stobe-auto speed 0 >/dev/null\n'),
 ('  stobe-auto wait-game 90 > "$O/accident.wait.txt" 2>&1\n',
  '  stobe-say speed 3 >/dev/null; stobe-auto wait-game 90 > "$O/accident.wait.txt" 2>&1; stobe-auto speed 0 >/dev/null\n'),
 # bleed: lighter wounds (he died at chest 160 + blood 25%), death = INCONCLUSIVE, honest message
 ('  stobe-auto damage "$h" chest 160 >/dev/null; stobe-auto blood "$h" 25% >/dev/null\n  stobe-say speed 1 >/dev/null\n',
  '  stobe-auto damage "$h" chest 100 >/dev/null; stobe-auto blood "$h" 30% >/dev/null\n  stobe-say speed 3 >/dev/null\n'),
 ('  elif ! grep -q \'"known"\' "$O/bleed.stobe.txt"; then v "bleed: FAIL recovered fact without vitals: Stobe without b55_recovered_vitals_native.py? (bleed.stobe.txt)"',
  '  elif grep -a -q -e \'"level":"death"\' -e \'"kind":"death"\' "$O/bleed.log.txt" || stobe-auto where "$h" | grep -q \' DEAD\'; then v "bleed: INCONCLUSIVE Rel Vex died before waking (bleed.log.txt)"\n'
  '  elif ! grep -q \'"known"\' "$O/bleed.stobe.txt"; then v "bleed: FAIL no recovered fact with vitals in stobe.log after the KO: he never woke in the window? (bleed.stobe.txt)"'),
 # accident KO: 80 left head at 19.9 (no KO)
 ('  stobe-auto hit Shay Malzin head 80 > "$O/accident.hit.txt" 2>&1',
  '  stobe-auto hit Shay Malzin head 130 > "$O/accident.hit.txt" 2>&1   # m22: 80 left head 19.9, no KO'),
 # accident: judge the accident effect itself (the stored value also moves with dialogue during the fight)
 ('  p1=$(aff Malzin Shay); p1=${p1:-0}; d=$((p1 - p0))\n',
  '  p1=$(aff Malzin Shay); p1=${p1:-0}; da=$((p1 - p0))\n'),
 ('  ko=$(grep -o \'ko=[a-z]*\' "$O/accident.hit.txt" | head -1)\n',
  '  ko=$(grep -o \'ko=[a-z]*\' "$O/accident.hit.txt" | head -1)\n'
  '  d=$(grep -a \'"component":"accident"\' "$O/accident.log.txt" | grep -a -o \'"delta":-\?[0-9]*\' | grep -o -- \'-\?[0-9]*$\' | awk \'{s+=$1} END{print s+0}\')\n'),
 ('    v "accident KO: PASS Malzin -> Shay $p0 -> $p1 (d=$d in $lo..$hi',
  '    v "accident KO: PASS Malzin -> Shay $p0 -> $p1 (accident d=$d in $lo..$hi, stored $da'),
 ('  q1=$(aff Malzin Shay); q1=${q1:-0}; d2=$((q1 - q0))\n',
  '  q1=$(aff Malzin Shay); q1=${q1:-0}\n'),
 ('  since $WL $w0 | grep -a "SOCIAL_INTERPRET" | grep -a "Malzin" > "$O/accident.log2.txt"\n',
  '  since $WL $w0 | grep -a "SOCIAL_INTERPRET" | grep -a "Malzin" > "$O/accident.log2.txt"\n'
  '  # m22: d=-9 stored vs accident delta -7: Malzin\'s fight dialogue moved the stored value too; judge the accident effect\n'
  '  d2=$(grep -a \'"component":"accident"\' "$O/accident.log2.txt" | grep -a -o \'"delta":-\?[0-9]*\' | grep -o -- \'-\?[0-9]*$\' | awk \'{s+=$1} END{print s+0}\')\n'),
 ('    v "accident injury: PASS in a real fight, Malzin -> Shay $q0 -> $q1 (d=$d2 in $lo2..-1',
  '    v "accident injury: PASS in a real fight, Malzin -> Shay $q0 -> $q1 (accident d=$d2 in $lo2..-1'),
 # deal: the raider struck first, so Shay's blows were defence and there was no penalty to forgive
 ('  bash "$I/rel-surrender.sh" kept "$O" > "$O/deal.surrender.txt" 2>&1\n',
  '  SHAY_FIRST=1 bash "$I/rel-surrender.sh" kept "$O" > "$O/deal.surrender.txt" 2>&1\n'),
 ('  elif grep -q "nothing_to_forgive" "$O/deal.log.txt"; then',
  '  elif ! grep -a \'"observer":"Rel Krag"\' "$O/deal.log.txt" | grep -a -q \'"status":"fights"\'; then v "deal: INCONCLUSIVE Rel Krag holds no fight penalty toward Shay (Shay\'s blows were defence; $last)"\n'
  '  elif grep -q "nothing_to_forgive" "$O/deal.log.txt"; then'),
])
patch(d / 'rel-surrender.sh', [
 ('    stobe-auto attack "$r" Shay >/dev/null; stobe-auto attack Shay "$r" >/dev/null\n',
  '    if [ "${SHAY_FIRST:-0}" = 1 ]; then stobe-auto attack Shay "$r" >/dev/null; sleep 2; stobe-auto attack "$r" Shay >/dev/null   # B55 deal: Shay strikes first\n'
  '    else stobe-auto attack "$r" Shay >/dev/null; stobe-auto attack Shay "$r" >/dev/null; fi\n'),
])
print('ok', root)
