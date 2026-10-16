#!/usr/bin/env bash
# reloaddefs_sfj.sh (imm26-sfJ): recipe fixes for the SETUP-FAIL tickets 23-e and 20-d (5090-i3 op20, 2026-10-16). Source it AFTER go-row.sh and reloaddefs_a.sh (reload-run-sfj.sh does);
# it REPLACES rd_23e and rd_20d in that shell only and adds sj_* helpers. reloaddefs_a.sh / reloadcheck_a.py / reload-run.sh stay untouched (queued lists use them).
#
# 23-e (legacy FOLLOW): the set-A row judged the chase with `end <= 35 u` after Shay was teleported 80 u away for 30 s. Real run: 79.7 u teleport -> 57.1 u two seconds later -> 43.5 u after
# 30 s at speed 3, FOLLOW_TICK present = the follower works but keeps a stand-off of about 40-60 u (like the native Bodyguard package, 27-a). Fix (same shape as the 27-a recipe): Shay goes
# RW_AWAY_F (120) u away, the chase window is RW_CHASE_S (45) s sampled every 5 s (chase_<tag>.series), a NEGATIVE CONTROL chase runs BEFORE "Follow me." (an NPC without the order must stay
# away: chase_ctrl.txt) and the checker (reloadcheck_sfj.py) uses `end <= RW_FOLLOW_NEAR (70)` instead of 35. The FOLLOW log of each chase window is kept (follow_log_chase_<tag>.txt).
#
# 20-d (pending plan change): travel_alternatives.pending_change is written only when the NPC answers a change request with travel_decision=REPLACE (lib/travel_companionship.php
# `if ($isReplace)` -> stobeImm26PendingChangeWrite). On the FIRST request ("Actually, go to the Stumble Inn instead.") the NPC did NOT say REPLACE in 20-a or in 20-d: both answered with a
# counter-question ("Which is it ..." / "If you're set on the Inn, say so"); 20-a recorded pending_change one turn LATER, on the insistence turn "Yes, I mean it. I am sure, change it to the Stumble
# Inn." (events.txt of 20-a/s4: travel_alternatives row 22446). So 20-d now sends that insistence turn (up to 3 wordings, stop at the first travel_alternatives row with pending_change), keeps the NPC
# beside Shay (teleport near + calm/protect before every turn: in 20-a the NPC walked to 326 u away and the place catalogue was empty, destination_candidate_counts places=0) and only then
# saves + loads. Rest of the row (save+load, bare "Yes.", s4 evidence, checker c_20d) is unchanged.
# Env: RW_AWAY_F (120) RW_CHASE_S (45) RW_FOLLOW_NEAR (70, checker) RW_AWAY_DIR (x; x|-x|z|-z) RW_20D_CONFIRM1/2/3 (insistence wordings) RW_ALT / TRIP_ALT (the Stumble Inn) RW_20D_RESUME_FIRST=1.

sj_calm() {   # Shay sheathed + held off, Shay and the NPC protected (Hub outlaws KO'd Shay mid-row in earlier runs)
  local n; n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/calm.txt" 2>&1
stobe-auto stobe_drawn hold Shay off </dev/null 2>&1 | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null 2>&1 | head -1
stobe-auto protect Shay on </dev/null 2>&1 | head -1
stobe-auto protect $n on </dev/null 2>&1 | head -1
EOT
}
sj_alt() {   # sj_alt <file>: newest 4 travel_alternatives rows
  lt_sql "select rowid||'|'||type||'|'||left(data,2500) from eventlog where type='travel_alternatives' order by rowid desc limit 4" > "$EV/$1" 2>&1
}
rw_chase_sfj() {   # rw_chase_sfj <tag>: Shay teleported RW_AWAY_F (120) u away and held; speed 3 for RW_CHASE_S (45) s, distance sampled every 5 s; chase_<tag>.txt = "dist_before|dist_after", chase_<tag>.series
  local tag="$1" pos n d0 d1 k steps dd x y z away="${RW_AWAY_F:-120}" ser
  n=$(rl_q "$RL_NPC_FULL")
  pos=$(echo 'stobe-auto where Shay </dev/null | head -1' | lt_h 2>&1 | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p' | head -1)
  [ -n "$pos" ] || { RL_REASON="cannot read Shay's position (stobe-auto where Shay)"; return 3; }
  set -- $pos; x=$1; y=$2; z=$3
  case "${RW_AWAY_DIR:-x}" in
    -x) x=$(awk -v v="$x" -v d="$away" 'BEGIN{printf "%.0f", v-d}');; z) z=$(awk -v v="$z" -v d="$away" 'BEGIN{printf "%.0f", v+d}');; -z) z=$(awk -v v="$z" -v d="$away" 'BEGIN{printf "%.0f", v-d}');;
    *) x=$(awk -v v="$x" -v d="$away" 'BEGIN{printf "%.0f", v+d}');;
  esac
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto protect Shay on </dev/null | head -1
stobe-auto teleport Shay $x $y $z </dev/null | head -1 | cut -c1-100
stobe-auto order Shay HOLD_POSITION keep </dev/null | head -1 | cut -c1-80
EOT
  rw_sleep 2; d0=$(rw_dist); ser="$d0"
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
EOT
  steps=$(( ${RW_CHASE_S:-45} / 5 )); [ "$steps" -ge 1 ] || steps=1
  for k in $(seq 1 "$steps"); do
    lt_h <<EOT >> "$EV/chase.txt" 2>&1
sleep 5
EOT
    dd=$(rw_dist); ser="$ser $dd"
  done
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
  d1=$(rw_dist); echo "$d0|$d1" > "$EV/chase_$tag.txt"; echo "$ser" > "$EV/chase_$tag.series"
  return 0
}

# ------------------------------------------------------------------ 23-e (recipe sfJ): legacy FOLLOW across a reload, with a negative-control chase and a longer, far chase
rd_23e() {
  local l n1 n0
  rw_prep || return $?
  sj_calm
  rw_chase_sfj ctrl || return $?                                  # control: NO follow order, Shay 120 u away for the same time -> the NPC must stay away
  rd19_place near || return $?                                    # bring the NPC back to Shay (teleport when > 70 u) before the chat line
  sj_calm
  rl_say 1 "Follow me." || return $?
  l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$EV/s1/meta.txt" | head -1); l=${l:-0}
  echo "$RL_NPC_ID" > "$EV/follow_npc.txt"
  rw_log follow_log_pre.txt "$l" 'FOLLOW'
  grep -q 'FOLLOW target resolved' "$EV/follow_log_pre.txt" || return 0                           # checker: SETUP-FAIL (follow never started)
  n0=$(rw_logn)
  rw_chase_sfj pre || return $?
  rw_log follow_log_chase_pre.txt "${n0:-0}" 'FOLLOW'
  rw_save_load follow near || return $?
  n1=$(rw_logn)
  rw_chase_sfj post || return $?
  rw_log follow_log_post.txt "${n1:-0}" 'FOLLOW'
  tr_state state_post.txt "$RL_NPC_FULL"
}

# ------------------------------------------------------------------ 20-d (recipe sfJ): pending plan change; the pending_change only exists after the insistence turn
rd_20d() {
  local k=0 w
  tr_prep || return $?
  TR_ALT="${RW_ALT:-${TRIP_ALT:-the Stumble Inn}}"; echo "$TR_ALT" > "$EV/alt.txt"
  tr_trip_setup || return $?
  rd19_place near; sj_calm
  rl_say 3 "Actually, go to $TR_ALT instead." || return $?
  sj_alt alt_s3.txt                                               # evidence only: expected NO pending_change yet (the NPC asks "which is it")
  for w in "${RW_20D_CONFIRM1:-Yes, I mean it. I am sure, change it to $TR_ALT.}" \
           "${RW_20D_CONFIRM2:-Yes. Drop the Squin trip and take me to $TR_ALT instead.}" \
           "${RW_20D_CONFIRM3:-I want $TR_ALT instead of Squin. Please change the plan to $TR_ALT.}"; do
    k=$((k+1)); rd19_place near; sj_calm
    rl_say "3c$k" "$w" || return $?
    sj_alt alt_pre.txt
    grep -q 'pending_change' "$EV/alt_pre.txt" && break
  done
  echo "$k" > "$EV/insist_turns.txt"
  rd19_dump agr_pre.txt
  grep -q 'pending_change' "$EV/alt_pre.txt" || return 0                                          # checker: SETUP-FAIL (change never offered)
  rw_save_load plan || return $?
  sj_alt alt_post.txt
  if [ -n "${RW_20D_RESUME_FIRST:-}" ]; then rl_say 4a "Where were we going?" || return $?; rw_sleep 6; fi
  rl_say 4 "Yes." || return $?
  rw_sleep 6
  sj_alt alt_after_yes.txt
  tr_agr agr_final.txt 8; rd19_dump agr_all.txt
}
