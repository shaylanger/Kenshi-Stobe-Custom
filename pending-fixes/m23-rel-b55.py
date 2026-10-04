#!/usr/bin/env python3
"""m23 rel-b55.sh test fixes (fixer 9). Usage: m23-rel-b55.py <tree root>  (edits tests/social_relationship/ingame/rel-b55.sh in place;
run it on a copy and mv when the live script may be running).
- fightko: Shay attacks again right after the teleport and the KO follows at once (10 s recent-attacker window; m23 squad KO
  seq=11867 came 14 s after the attack -> attribution none, only aggression; same as SR07 1e15790).
- bandit: reset the bandit's entries for Shay/Malzin to 0 (names are reused across runs; m23 fade: Rel Fenn kept -15 from an
  earlier run, so the faded value returned to -15, not 0); SETUP FAIL when the baseline is not 0.
- wild: no player-allied faction for Bek (Traders Guild made Shay defend him), the pair fights 200 m away, Malzin stays at
  Shay's side; SETUP FAIL when Shay/Malzin appear in wild.log.txt.
- chat: the stance block reaches the model as markdown ("## Memory"), never "<memory>"; rule 4 uses the evaluator injection
  switch SOCIAL_TEST_INJECT_DIALOGUE_GAIN=3 (the live evaluator gave -4: nothing to block) and requires the injection log line.
"""
import sys
p = sys.argv[1].rstrip('/') + '/tests/social_relationship/ingame/rel-b55.sh'
s = open(p, encoding='utf-8').read()
def rep(old, new, count=1):
    global s
    n = s.count(old)
    if n != count: sys.exit(f'anchor count {n} != {count}: {old[:70]!r}')
    s = s.replace(old, new)

rep("off(){ for s in SOCIAL_GRUDGE_FADE_DAYS SOCIAL_TEST_FORCE_FIRST_STRIKE; do",
    "off(){ for s in SOCIAL_GRUDGE_FADE_DAYS SOCIAL_TEST_FORCE_FIRST_STRIKE SOCIAL_TEST_INJECT_DIALOGUE_GAIN; do")
rep("""  for i in $(seq 1 15); do insp --relation "$name" Shay 2>/dev/null | grep -q 'observer not found' || break; sleep 2; done
  stobe-auto speed 0 >/dev/null
  echo "$h"; }""",
"""  for i in $(seq 1 15); do insp --relation "$name" Shay 2>/dev/null | grep -q 'observer not found' || break; sleep 2; done
  stobe-auto speed 0 >/dev/null
  # m23: names are reused across runs and a spawned NPC's stored entries can outlive a reload (Rel Fenn kept -15): start at 0
  insp --set-relation "$name" Shay 0 >/dev/null 2>&1; insp --set-relation "$name" Malzin 0 >/dev/null 2>&1
  [ "$(aff "$name" Shay)" = 0 ] || { echo "SETUP baseline $name -> Shay is '$(aff "$name" Shay)', not 0" >&2; return 2; }
  echo "$h"; }""")
rep("""  stobe-auto attack Shay "$h" >/dev/null; stobe-say speed 1 >/dev/null; sleep 6
  stobe-auto teleport "$h" Shay dist 4 >/dev/null; stobe-auto ko "$h" "${2:-60}" >/dev/null""",
"""  stobe-auto attack Shay "$h" >/dev/null; stobe-say speed 1 >/dev/null; sleep 6
  # m23: the KO must land inside the 10 s recent-attacker window (14 s after the attack = attribution none): attack again, KO at once
  stobe-auto teleport "$h" Shay dist 2 >/dev/null; stobe-auto attack Shay "$h" >/dev/null; sleep 1; stobe-auto ko "$h" "${2:-60}" >/dev/null""")
rep("""  b=$(bandit "Rel Bek" 25) || { v "wild: FAIL no 2nd bandit"; continue; }
  stobe-auto faction "$b" "Traders Guild" >/dev/null
  a="Rel Arn"; b="Rel Bek"   # m22: names; the re-resolved handle came back empty and Shay was teleported instead
  w0=$(lines $WL)
  stobe-auto teleport "$a" Shay dist 60 >/dev/null; stobe-auto teleport "$b" "$a" dist 3 >/dev/null""",
"""  b=$(bandit "Rel Bek" 25) || { v "wild: FAIL no 2nd bandit"; continue; }
  # m23: not a player-allied faction (Traders Guild made Shay defend Bek -> squad involved); Dust Bandits so Arn fights him
  stobe-auto faction "$b" "Dust Bandits" >/dev/null
  a="Rel Arn"; b="Rel Bek"   # m22: names; the re-resolved handle came back empty and Shay was teleported instead
  stobe-auto teleport Malzin Shay dist 2 >/dev/null   # the squad stays together, far from the pair
  w0=$(lines $WL)
  stobe-auto teleport "$a" Shay dist 200 >/dev/null; stobe-auto teleport "$b" "$a" dist 3 >/dev/null""")
rep("""  if grep -q '"ignored"' "$O/wild.log.txt" && [ "${e1:-0}" = 0 ] && [ "${e2:-0}" = 0 ]; then v "wild: PASS ignored, no entries\"""",
"""  if grep -a -q -e '"actor":"Shay"' -e '"target":"Shay"' -e '"actor":"Malzin"' -e '"target":"Malzin"' "$O/wild.log.txt"; then
    v "wild: SETUP FAIL the squad joined the fight (Shay/Malzin in wild.log.txt): not a wild fight"
  elif grep -q '"ignored"' "$O/wild.log.txt" && [ "${e1:-0}" = 0 ] && [ "${e2:-0}" = 0 ]; then v "wild: PASS ignored, no entries\"""")
rep("""  w0=$(lines $WL); s0=$(lines $SL); c0=$(lines $CL)
  stobe-say say "Rel Mira\"""",
"""  # rule 4 is mechanical: inject a +3 evaluator gain before the fight filter (the live model gave -4 in m23: nothing to block)
  insp --set-switch SOCIAL_TEST_INJECT_DIALOGUE_GAIN 3 > "$O/chat.setup.txt" 2>&1
  w0=$(lines $WL); s0=$(lines $SL); c0=$(lines $CL)
  stobe-say say "Rel Mira\"""")
rep("""  { since $WL $w0; since $SL $s0; } | grep -a "SOCIAL_DIALOGUE filtered" | grep -a "Rel Mira" > "$O/chat.filtered.txt"
  since $CL $c0 | grep -a -o "<memory>[^<]*</memory>" | head -3 > "$O/chat.memory.txt"
  m="memory line: $(grep -c . "$O/chat.memory.txt")"
  if grep -q "fight_cooldown" "$O/chat.filtered.txt"; then v "chat: PASS chat gain blocked (fight_cooldown), $m"
  elif [ -s "$O/chat.memory.txt" ]; then v "chat: INCONCLUSIVE no positive evaluator delta to block; $m (PASS item 6 memory)"
  else v "chat: FAIL no cooldown filter and no <memory> line (chat.*.txt)"; fi""",
"""  insp --set-switch SOCIAL_TEST_INJECT_DIALOGUE_GAIN off >> "$O/chat.setup.txt" 2>&1
  { since $WL $w0; since $SL $s0; } | grep -a -e "SOCIAL_DIALOGUE filtered" -e "SOCIAL_TEST_INJECT_DIALOGUE_GAIN" | grep -a "Rel Mira" > "$O/chat.filtered.txt"
  # the stance block is sent as markdown (prompt_formatting.php): "## Memory" + the line; the raw <memory> form is kept as a fallback
  since $CL $c0 | grep -a -A2 -e '^## Memory' -e '<memory>' | grep -a -e "Shay .* in a fight (day" | head -3 > "$O/chat.memory.txt"
  m="memory line: $(grep -c . "$O/chat.memory.txt")"
  inj=$(grep -a -c "SOCIAL_TEST_INJECT_DIALOGUE_GAIN" "$O/chat.filtered.txt")
  if [ "$inj" = 0 ]; then v "chat: SETUP FAIL the injected +3 never reached the evaluator path (no injection log line; chat.setup.txt, chat.say.txt), $m"
  elif grep -q "fight_cooldown" "$O/chat.filtered.txt" && [ -s "$O/chat.memory.txt" ]; then v "chat: PASS injected +3 blocked (fight_cooldown), $m"
  else v "chat: FAIL cooldown filter $(grep -c fight_cooldown "$O/chat.filtered.txt"), $m (chat.filtered.txt, chat.memory.txt)"; fi""")
open(p, 'w', encoding='utf-8').write(s)
print('ok', p)
