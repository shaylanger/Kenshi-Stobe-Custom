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
# reliability: medium-high (no LLM choice beyond accepting the goal). Default stashes 20 Wheatstraw (farm growth takes game
#   days); GROW=1 [SPEED=50] runs the real farm chain with a 40-min budget.
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
  # m16 next: an idle silo (no operator) asks for no power and reads out_of_power=1.0 on a full grid, so the
  # setup checks the GRID (grid_power or grid_battery > 0); the silo must draw power later, while she works it.
  g=$(stobe-auto building "Grain Silo" radius 1000)
  gp=$(echo "$g" | grep -oE "grid_power=[0-9.]+" | cut -d= -f2 | cut -d. -f1); gb=$(echo "$g" | grep -oE "grid_battery=[0-9.]+" | cut -d= -f2 | cut -d. -f1)
  log "silo grid: $(echo "$g" | grep -oE 'grid="[^"]*"|grid_power=[^ ]+|grid_battery=[^ ]+|operators=[^ ]+|needs_power_now=[^ ]+' | tr '\n' ' ')"
  [ "${gp:-0}" -gt 0 ] || [ "${gb:-0}" -gt 0 ] || { verdict A8 "SETUP FAIL the Grain Silo grid has no power: $(echo "$g" | cut -c1-220)"; exit 1; }
else
for b in "Grain Silo" "${WELL:-Well III}" "Bread Oven"; do
  r=$(stobe-auto power "$b" supply radius 1000 2>&1 | cut -c1-200); log "supply $b: $r"
done
fi
stobe-auto building "Grain Silo" radius 1000 | grep -oE "out_of_power=[0-9.]+|supplied=[0-9]" | tr '\n' ' '; echo
stobe-auto buildings 300 Wheat near ${MATE} | cut -c1-200
# m16 next: the wheat farm needs game days to grow (12 min at 20x ended at "Obtaining Wheatstraw for Strawflour").
# Default: 20 Wheatstraw (10 per Strawflour, 2 breads) go into the base storage, so the chain runs
# chest -> Grain Silo -> Bread Oven now. GROW=1 tests the full farm chain instead (50x, up to 40 min).
if [ "${GROW:-0}" != 1 ]; then
  log "stash 20 Wheatstraw: $(stobe-auto stash Wheatstraw 20 near ${MATE} 2>&1 | cut -c1-140)"
else
  SPEED="${SPEED:-50}"; log "GROW=1: full farm chain at ${SPEED}x, budget 40 min"
fi
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
for i in $(seq 1 $([ "${GROW:-0}" = 1 ] && echo 600 || echo 150)); do
  sleep 4
  # REAL_POWER: does the silo draw power while she works it? (sampled every poll, ~4 s; at 50x her silo step is short)
  if [ "${REAL_POWER:-0}" = 1 ]; then
    cp=$(stobe-auto building "Grain Silo" radius 1000 | grep -oE "current_power=[0-9.]+" | cut -d= -f2)
    awk -v c="${cp:-0}" -v m="${silo_max:-0}" 'BEGIN{exit !(c>m)}' && silo_max="$cp"
  fi
  s=$(grep -a "^$id" "$ST" | cut -f3,6,8,9 | tr '\t' '|')
  echo "$s" | grep -q -E "COMPLETE|BLOCKED|CANCEL" && break
  stobe-auto where ${PLAYER} | grep -q " KO" && { log "${PLAYER} KO: paused"; break; }
  # goal-watch safety (tools/stobe-goal-watch.sh logic, any squad names): squad attacked or knocked out -> pause
  # RAID_CALM=1 (Full-Base, squad protected): knock out world raiders every ~40 s and don't stop on their attacks
  # (m22 batch D: Kral's Chosen raid ended A8 at 50x); a knockout of the squad still stops the test
  if [ "${RAID_CALM:-0}" = 1 ] && [ $((i % 10)) = 0 ]; then calm_raiders 1500 >/dev/null; fi
  raid_re='\((Band of Bones|Kral.s Chosen|Dust Bandits|Hungry Bandits|Starving Bandits)\) ->'
  [ "${RAID_CALM:-0}" = 1 ] || raid_re='^$x'
  alert=$(since_stobe | grep -a -E "\[EVENT\] (combat: .* -> (${PLAYER}|${MATE}) |knockout: (${PLAYER}|${MATE}) )" | grep -a -v -E "combat: .*$raid_re" | tail -1)
  if [ -n "$alert" ]; then stobe-auto speed 0 >/dev/null; verdict A8 "ALERT at ${SPEED:-20}x: $(echo "$alert" | cut -c1-200)"; exit 3; fi
done
stobe-auto speed 0 >/dev/null
log "end: $s"
tail -n +"$BASE_K" "$KFP" | grep -a -F "$id" | grep -a -i -E "water|power|grow|blocked|complete" | tail -12 | cut -c1-220
oven_water=$(tail -n +"$BASE_K" "$KFP" | grep -a -F "$id" | grep -a -i "picked.*water.*from .*oven" | grep -a -c .)  # water taken OUT of the oven (loading water into it is the recipe)
stobe-auto inv ${MATE} | grep -o '"name":"[^"]*Bread[^"]*","count":[0-9]*' | head -3
silo_ok=1; [ "${REAL_POWER:-0}" = 1 ] && ! awk -v m="${silo_max:-0}" 'BEGIN{exit !(m>0)}' && silo_ok=0
log "silo current_power max while working: ${silo_max:-0} (real power: ${REAL_POWER:-0})"
if echo "$s" | grep -q COMPLETE && [ "$oven_water" -eq 0 ] && [ "$silo_ok" = 1 ]; then verdict A8 "PASS bread COMPLETE, water never from the oven, silo drew power (max ${silo_max:-n/a})"
elif echo "$s" | grep -q COMPLETE && [ "$silo_ok" = 0 ]; then verdict A8 "FAIL COMPLETE but the silo never showed current_power>0 (sampled every poll, ~4 s; at 50x her silo step is short)"
elif echo "$s" | grep -q -i "power"; then verdict A8 "FAIL still a power block: $s"
else verdict A8 "FAIL $s (oven water lines: $oven_water)"; fi
