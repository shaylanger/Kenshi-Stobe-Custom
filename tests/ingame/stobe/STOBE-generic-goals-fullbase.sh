#!/usr/bin/env bash
# id: STOBE-generic-goals-fullbase
# covers: generic regression with another squad (no Shay/Malzin anywhere): a hand-over, a fetch goal and a work goal,
#         plus a scan of the game logs for "Shay"/"Malzin" (any hit from mod code = hard-coding bug)
# fixture: Testing-Save-Full-Base (copy kah-fullbase); squad Beaks + Avarek
# reset: fresh load of the copy
# needs: Stobe EF62563B+, KenshiFP E64B1BD5+, harness 12F5CE0B+, server live
# usage: [PLAYER=Beaks] [MATE=Avarek] [WORK_ITEM="building materials"] [WORK_QTY=2] STOBE-generic-goals-fullbase.sh
# verify (VERDICT lines; each part independent):
#   hand-over: "<mate>, give me one of your bread." -> <player>'s Bread +1 (`inv`), stobe.log GIVE_ITEM;
#   fetch:     "<mate>, fetch me the dried meat from the storage chest." (3 Dried Meat stashed, she has none) ->
#              a task goal for Dried Meat ends COMPLETE (stobe_task_goal.status) and <player> or <mate> holds it;
#   work:      "<mate>, make <WORK_QTY> <WORK_ITEM>." -> work goal accepted, then COMPLETE within 6 min at 10x
#              (BLOCKED with a reason is reported; a power/missing-building reason means pick another WORK_ITEM);
#   names:     stobe.log + KenshiFP.log since the start have no line with "Shay"/"Malzin" (printed if any).
# reliability: hand-over/fetch high; work goal depends on the base having the chain (stone mine + processor)
set -u
export PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}"   # before the lib (its defaults are Shay/Malzin)
. "$(dirname "$0")/stobe-fight-lib.sh"
WORK_ITEM="${WORK_ITEM:-building materials}"; WORK_QTY="${WORK_QTY:-2}"
STK=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_task_goal.status
STW=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_work_goal.status
BASE_K=$(grep -a -c "" "$KFP" 2>/dev/null || echo 0)
trap 'raid_guard_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
count_of() { stobe-auto inv "$1" | grep -oE "\"name\":\"$2\",\"count\":[0-9]+" | grep -oE '[0-9]+$' | awk '{s+=$1} END{print s+0}'; }
# m48 (dec-5090-1): a Band of Bones raid aborted the work part; world raiders are swept by raid_guard and their
# events skipped here (raid_event); any other attack on the squad still ends the row
alert() { since_stobe | grep -a -E "\[EVENT\] (combat: .* -> (${PLAYER}|${MATE}) |knockout: (${PLAYER}|${MATE}) )" |
  while IFS= read -r l; do raid_event "$l" || echo "$l"; done | tail -1; }
log "generic: squad ${PLAYER} + ${MATE}"
stobe-auto speed 0 >/dev/null; stobe-auto select "${PLAYER}" >/dev/null
stobe-auto chars 60 | cut -c1-200
stobe-auto hunger "${PLAYER}" 280 >/dev/null; stobe-auto hunger "${MATE}" 280 >/dev/null
stobe-say ping | head -2
bash "$(dirname "$0")/fullbase-guard.sh"
raid_guard_start

# --- 1. hand-over
stobe-auto give "${MATE}" "Bread" 2 | cut -c1-120
b0=$(count_of "${PLAYER}" Bread); mark=$(grep -a -c "" "$L")
stobe-say speed 1 >/dev/null
stobe-say say "${MATE}" "${MATE}, give me one of your bread." --wait 25 >/dev/null 2>&1 || log "say failed"
sleep 10
b1=$(count_of "${PLAYER}" Bread)
gi=$(tail -n +"$mark" "$L" | grep -a -c "GIVE_ITEM")
if [ "$((b1 - b0))" -ge 1 ]; then verdict generic-handover "PASS ${PLAYER} Bread $b0 -> $b1 (GIVE_ITEM lines: $gi)"
else verdict generic-handover "FAIL ${PLAYER} Bread $b0 -> $b1 (GIVE_ITEM lines: $gi)"; fi

# --- 2. fetch goal
stobe-auto stash "Dried Meat" 3 near "${MATE}" | cut -c1-140
m0=$(( $(count_of "${PLAYER}" "Dried Meat") + $(count_of "${MATE}" "Dried Meat") ))
before=$(cut -f1 "$STK" 2>/dev/null | sort)
stobe-say say "${MATE}" "${MATE}, fetch me the dried meat from the storage chest." --wait 25 >/dev/null 2>&1 || log "say failed"
stobe-auto speed 5 >/dev/null
row=""
for i in $(seq 1 45); do
  sleep 4
  id=$(comm -13 <(echo "$before") <(cut -f1 "$STK" 2>/dev/null | sort) | head -1)
  [ -n "$id" ] && row=$(grep -a "^$id" "$STK" | tr '\t' '|' | cut -c1-220)
  echo "$row" | grep -q -E "COMPLETE|BLOCKED|CANCELLED" && break
  [ -n "$(alert)" ] && { stobe-auto speed 0 >/dev/null; verdict generic "ALERT $(alert | cut -c1-200)"; exit 3; }
done
stobe-auto speed 0 >/dev/null
m1=$(( $(count_of "${PLAYER}" "Dried Meat") + $(count_of "${MATE}" "Dried Meat") ))
if echo "$row" | grep -q COMPLETE && [ "$m1" -gt "$m0" ]; then verdict generic-fetch "PASS $row (squad Dried Meat $m0 -> $m1)"
else verdict generic-fetch "FAIL ${row:-no task goal} (squad Dried Meat $m0 -> $m1)"; fi

# --- 3. work goal
before=$(cut -f1 "$STW" 2>/dev/null | sort)
stobe-say speed 1 >/dev/null
stobe-say say "${MATE}" "${MATE}, make ${WORK_QTY} ${WORK_ITEM}." --wait 25 >/dev/null 2>&1 || log "say failed"
stobe-auto speed 10 >/dev/null
row=""
for i in $(seq 1 90); do
  sleep 4
  id=$(comm -13 <(echo "$before") <(cut -f1 "$STW" 2>/dev/null | sort) | head -1)
  [ -n "$id" ] && row=$(grep -a "^$id" "$STW" | tr '\t' '|' | cut -c1-220)
  echo "$row" | grep -q -E "COMPLETE|BLOCKED|CANCELLED" && break
  [ -n "$(alert)" ] && { stobe-auto speed 0 >/dev/null; verdict generic "ALERT $(alert | cut -c1-200)"; exit 3; }
done
stobe-auto speed 0 >/dev/null
tail -n +"$BASE_K" "$KFP" | grep -a -E "WORK_GOAL (accepted|blocked|complete)" | tail -3 | cut -c1-220
if echo "$row" | grep -q COMPLETE; then verdict generic-work "PASS $row"; else verdict generic-work "FAIL ${row:-no work goal}"; fi

# --- 4. hard-coded names
hits=$( { since_stobe; tail -n +"$BASE_K" "$KFP"; } | grep -a -E "\b(Shay|Malzin)\b")
if [ -z "$hits" ]; then verdict generic-names "PASS no Shay/Malzin in stobe.log/KenshiFP.log"
else verdict generic-names "FAIL $(echo "$hits" | wc -l) line(s) name Shay/Malzin:"; echo "$hits" | head -10 | cut -c1-220; fi
