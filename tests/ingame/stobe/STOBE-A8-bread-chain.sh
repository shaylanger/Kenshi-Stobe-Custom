#!/usr/bin/env bash
# id: STOBE-A8-bread-chain
# covers: STOBE A8 (was 69/70): "Malzin, make 2 bread" at Home: water only from the well (never out of the oven),
#         wheat -> Grain Silo, flour -> Bread Oven, COMPLETE 2/2; "Waiting for Wheat Farm ... to grow" while growing
# fixture: auto-home
# reset: fresh (run `bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh` first)
# needs: KenshiFP E64B1BD5+, Stobe EF62563B+, harness 12F5CE0B (`power <building> supply`, KAH 10)
# m14/m15 blocker: the Grain Silo and Well III had no power supply at Home (no battery/generator) -> every powered
# building in the chain gets `power ... supply` now.
# verify (VERDICT line + by hand):
#   - stobe_work_goal.status: the bread goal ends COMPLETE (2/2); never BLOCKED "... has no power";
#   - KenshiFP.log for that goal: `Waiting for Wheat Farm ... to grow` while growing is fine; Water steps name the
#     Well, never the Bread Oven (`grep -a "<goal id>" KenshiFP.log | grep -i water`);
#   - `inv Malzin` (or the oven output) holds the bread at the end.
#   A dry farm blocking after ~60 s is the designed outcome when there is no water at all (not expected here).
# reliability: medium-high (no LLM choice beyond accepting the goal; long: up to 10 min at 20x)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
trap 'stobe-auto speed 0 >/dev/null 2>&1' EXIT
ST=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_work_goal.status
BASE_K=$(grep -a -c "" "$KFP" 2>/dev/null || echo 0)
log "A8: setup"
stobe-auto speed 0 >/dev/null; stobe-auto select ${PLAYER} >/dev/null
stobe-auto hunger ${MATE} 280 >/dev/null; stobe-auto hunger ${PLAYER} 280 >/dev/null; stobe-auto health ${MATE} 100 >/dev/null
# REAL_POWER=1 (Full-Base): no supply cheat; the base's own power must run the chain.
if [ "${REAL_POWER:-0}" = 1 ]; then
  for b in "Grain Silo" "${WELL:-Well}" "Bread Oven"; do
    log "power $b: $(stobe-auto building "$b" radius 1000 2>&1 | grep -oE 'has_power=[0-9]|out_of_power=[0-9.]+|current_power=[0-9.]+' | tr '\n' ' ')"
  done
  stobe-auto building "Grain Silo" radius 1000 | grep -q "out_of_power=0" || { verdict A8 "SETUP FAIL Grain Silo has no real power: $(stobe-auto building "Grain Silo" radius 1000 | cut -c1-200)"; exit 1; }
else
for b in "Grain Silo" "${WELL:-Well III}" "Bread Oven"; do
  r=$(stobe-auto power "$b" supply radius 1000 2>&1 | cut -c1-200); log "supply $b: $r"
done
fi
stobe-auto building "Grain Silo" radius 1000 | grep -oE "out_of_power=[0-9.]+|supplied=[0-9]" | tr '\n' ' '; echo
stobe-auto buildings 300 Wheat near ${MATE} | cut -c1-200
before=$(cut -f1 "$ST" 2>/dev/null | sort)
stobe-say speed 1 >/dev/null
stobe-say say ${MATE} "${MATE}, make 2 bread." --wait 15 >/dev/null 2>&1 || log "say failed"
id=""
for i in $(seq 1 15); do
  id=$(comm -13 <(echo "$before") <(cut -f1 "$ST" 2>/dev/null | sort) | head -1)
  [ -z "$id" ] && id=$(grep -a -P '\tBread\t' "$ST" | grep -v -E 'COMPLETE|CANCELLED|BLOCKED' | head -1 | cut -f1)
  [ -n "$id" ] && break; sleep 2
done
[ -n "$id" ] || { verdict A8 "FAIL no bread goal: $(tail -n +"$BASE_K" "$KFP" | grep -a WORK_GOAL | tail -2)"; exit 1; }
log "goal $id"
stobe-auto speed "${SPEED:-20}" >/dev/null
s=""
for i in $(seq 1 150); do
  sleep 4
  s=$(grep -a "^$id" "$ST" | cut -f3,6,8,9 | tr '\t' '|')
  echo "$s" | grep -q -E "COMPLETE|BLOCKED|CANCEL" && break
  stobe-auto where ${PLAYER} | grep -q " KO" && { log "${PLAYER} KO: paused"; break; }
  # goal-watch safety (tools/stobe-goal-watch.sh logic, any squad names): squad attacked or knocked out -> pause
  alert=$(since_stobe | grep -a -E "\[EVENT\] (combat: .* -> (${PLAYER}|${MATE}) |knockout: (${PLAYER}|${MATE}) )" | tail -1)
  if [ -n "$alert" ]; then stobe-auto speed 0 >/dev/null; verdict A8 "ALERT at ${SPEED:-20}x: $(echo "$alert" | cut -c1-200)"; exit 3; fi
done
stobe-auto speed 0 >/dev/null
log "end: $s"
tail -n +"$BASE_K" "$KFP" | grep -a -F "$id" | grep -a -i -E "water|power|grow|blocked|complete" | tail -12 | cut -c1-220
oven_water=$(tail -n +"$BASE_K" "$KFP" | grep -a -F "$id" | grep -a -i "water" | grep -a -c -i "oven")
stobe-auto inv ${MATE} | grep -o '"name":"[^"]*Bread[^"]*","count":[0-9]*' | head -3
if echo "$s" | grep -q COMPLETE && [ "$oven_water" -eq 0 ]; then verdict A8 "PASS bread COMPLETE, water never from the oven"
elif echo "$s" | grep -q -i "power"; then verdict A8 "FAIL still a power block: $s"
else verdict A8 "FAIL $s (oven water lines: $oven_water)"; fi
