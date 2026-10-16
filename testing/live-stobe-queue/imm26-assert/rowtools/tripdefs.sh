#!/usr/bin/env bash
# tripdefs.sh: trip-family row definitions for go-row.sh (sourced at the end of rowdefs.sh; see rowtools/README_TRIP.md).
#   New rows : rd_13b rd_20a rd_20b rd_23a rd_23c rd_23d rd_24a   (checks: rowcheck_trip.py)
#   Wrapped  : rd_19a rd_23b rd_24b = the existing definitions behind tr_prep (db clean + haff 60 + quiet scene) -> same rowcheck.py checks.
# One-call entry (reload ready save + preflight + go-row): rowtools/trip-run.sh <ROW> <lane> [opts]; 13-b: rowtools/ko13b.sh <lane>.
# Env knobs: TRIP_DEST (Squin) TRIP_ALT (the Stumble Inn) TRIP_SAVE TRIP_GATE "x y z" TRIP_ACCEPT TRIP_FOLLOW (60 s) TRIP_QUIET=0
#   TRIP_TRAP "x y z" (20-b) TRIP_FORCE_WAIT (25 s) TRIP_PARTNER (Malzin) TRIP_LEAVER ("Cind [Hungry Bandit]") TRIP_LEAVE_DIST (108)
#   TRIP_N2_WAIT (90 s) TRIP_CTRL_WAIT (60 s) TRIP_SE_TRIES (15 x 3 s).  Every row writes only evidence files below $EV.
# Lessons baked in (handoffs i3op3/i3op4/i4op32): full name "Cind [Hungry Bandit]" (plain Cind may resolve to an HNO Cind); haff Cind->Shay 60
#   platonic; delete leftover travel_agreement/region_plan/situated_event/situated_remark_claim rows; NEVER give Cind a harness order after a
#   trip accept except where the row forces a failure (20-b); teleport Cind to the destination gate right after the accept and keep Shay on
#   her (speed 3, teleport Shay onto Cind every 6 s); Squin/Shek/the Hub KO Shay (rl_prep_player wakes him before each say).
TD_NPC="Cind [Hungry Bandit]"

tr_cfg() {  # sets ROW_NPC TR_DEST TR_ALT TR_SAVE TR_GATE for the loaded lane (lt_load must have run)
  ROW_NPC="${ROW_NPC:-$TD_NPC}"; TR_DEST="${TRIP_DEST:-Squin}"; TR_ALT="${TRIP_ALT:-the Stumble Inn}"
  local s g
  case "${LT_LANE:-}" in 5090-i3) s=kah-imm26-5090-ready;; 5090-i4) s=kah-imm26-i4-trip2;; *) s="";; esac
  case "$TR_DEST" in Squin) g="-62380 330 16250";; *) g="";; esac
  TR_SAVE="${TRIP_SAVE:-$s}"; TR_GATE="${TRIP_GATE:-$g}"
}
tr_has() {  # tr_has <step> <STATUS>: the step's ev_full holds a travel_agreement row with that status
  grep -q "\"status\":\"$2\"" "$EV/$1/ev_full.txt" 2>/dev/null
}
tr_clean_db() {
  lt_sqlx "delete from eventlog where type in ('travel_agreement','region_plan','situated_event','situated_remark_claim')" >> "$EV/clean.txt" 2>&1
}
tr_quiet() {  # squad to Shay, every non-squad character within 400 moved away, squad healed (port of imm26-5090-i3/clear-hub.sh)
  local n; n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/quiet.txt" 2>&1
[ -n "${TR_SCENE:-}" ] && stobe-auto teleport Shay ${TR_SCENE:-0 0 0} </dev/null | head -1
stobe-auto teleport $n Shay </dev/null | head -1
stobe-auto teleport Malzin Shay </dev/null | head -1
for pass in 1 2; do
  stobe-auto chars 400 </dev/null 2>&1 | sed 's/ | /\n/g' | grep -v -E "Shay #|${RL_NPC_FULL%% *} \[|Malzin #" | grep -E "#[0-9]+/[0-9]+" | sed -E 's/.*#([0-9]+\/[0-9]+).*/\1/' | sort -u > /tmp/tr-ids.txt
  while read id; do stobe-auto teleport "#\$id" -53200 957 4893 </dev/null >/dev/null 2>&1; done < /tmp/tr-ids.txt
done
for nm in Shay $n Malzin; do stobe-auto health "\$nm" 100 </dev/null >/dev/null 2>&1; done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
}
tr_prep() {  # common start of every trip row: resolve, db clean, haff 60 platonic, quiet scene; sets RL_NPC_FULL/RL_NPC_ID, writes npc.txt
  unset ROW_NATIVE; tr_cfg
  rd_need_npc || return 3
  echo "$RL_NPC_FULL" > "$EV/npc.txt"
  tr_clean_db; rd_aff 60 platonic haff
  [ "${TRIP_QUIET:-1}" = 0 ] || tr_quiet
  unset TR_SCENE; rl_resolve "$ROW_NPC" >/dev/null 2>&1
  return 0
}
tr_state() {  # tr_state <file> <npc>  : stobe_state JSON head
  printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 2500\n' "$(rl_q "$2")" | lt_h > "$EV/$1" 2>&1
}
tr_agr() {  # tr_agr <file> [n] : newest-first rows "rowid|status|phase|reason|owned_work_released|agreement_id|destination"
  lt_sql "select rowid||'|'||coalesce(j->>'status','')||'|'||coalesce(j->'execution'->>'phase','')||'|'||coalesce(j->'execution'->>'reason','')||'|'||coalesce(j->'execution'->>'owned_work_released','')||'|'||coalesce(j->>'agreement_id','')||'|'||coalesce(j->>'destination','') from (select rowid, substring(data from position('{' in data))::json as j from eventlog where type='travel_agreement' order by rowid desc limit ${2:-8}) t order by rowid desc" > "$EV/$1" 2>&1
}
tr_trip_setup() {  # s1 propose (+s1b fallback wording), s2 accept (+s2b "Lead the way." when no native start is logged); native context pushed per say
  ROW_NATIVE=1
  rl_say 1 "Take me to $TR_DEST." || return $?
  tr_has s1 PROPOSED || { rl_say 1b "Would you lead me to $TR_DEST?" || return $?; }
  rl_say 2 "${TRIP_ACCEPT:-I'm fine. Yes, let's go.}" || return $?
  if tr_has s2 ACCEPTED && ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" 2>/dev/null; then
    rl_say 2b "Lead the way." || return $?
  fi
  tr_agr agr_trip.txt 4
  return 0
}
tr_gate() {  # echoes "x y z": TRIP_GATE / destination table, else the newest agreement's destination_point
  [ -n "${TR_GATE:-}" ] && { echo "$TR_GATE"; return; }
  lt_sql "select data from eventlog where type='travel_agreement' order by rowid desc limit 1" | sed -nE 's/.*"destination_point":\{"x":(-?[0-9.]+),"y":(-?[0-9.]+),"z":(-?[0-9.]+).*/\1 \2 \3/p' | head -1
}
tr_follow() {  # tr_follow <seconds>: speed 3, keep Shay on the NPC every 6 s, speed back to 0.5
  local n; n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/follow.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
for k in \$(seq 1 $(( ${1:-60} / 6 ))); do sleep 6; stobe-auto teleport Shay $n </dev/null >/dev/null; stobe-auto where $n </dev/null | head -1 | cut -c1-120; done
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
}
tr_arrive() {  # teleport the NPC to the destination gate, Shay onto her, follow
  local g n; g=$(tr_gate); [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"; n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/arrive.txt" 2>&1
stobe-auto teleport $n $g </dev/null | head -1 | cut -c1-100
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-100
EOT
  tr_follow "${TRIP_FOLLOW:-60}"
}
tr_target() {  # tr_target <name>: make <name> the say target; rc 3 when it cannot be resolved
  rl_resolve "$1" || { RL_REASON="cannot resolve '$1' (stobe-auto where)"; return 3; }
}

# ------------------------------------------------------------------ rows
rd_23a() {  # FX-TRAVEL: complete an agreed trip: propose, accept, teleport to the gate with Shay, arrival line, one ack, COMPLETED
  tr_prep || return $?; tr_trip_setup || return $?
  tr_arrive || return $?
  tr_state state_shay.txt Shay
  rl_say 3 "We're here. Thanks for guiding me." || return $?
  tr_state state_after.txt "$RL_NPC_FULL"; tr_agr agr_final.txt 8
}
rd_20a() {  # ACCEPTED trip; change request must not move the row; confirm must end/replace it
  tr_prep || return $?; tr_trip_setup || return $?
  echo "$TR_ALT" > "$EV/alt.txt"
  rl_say 3 "Actually, go to $TR_ALT instead." || return $?
  rl_say 4 "Yes, I mean it. I am sure, change it to $TR_ALT." || return $?
  tr_agr agr_final.txt 8
}
rd_20b() {  # force a failure mid-trip (TRIP_TRAP unreachable spot = real path failure; default = replace the native order), ask why
  tr_prep || return $?; tr_trip_setup || return $?
  local n; n=$(rl_q "$RL_NPC_FULL")
  if [ -n "${TRIP_TRAP:-}" ]; then echo "method=trap $TRIP_TRAP" > "$EV/forced.txt"
    lt_h <<EOT >> "$EV/force.txt" 2>&1
stobe-auto teleport $n ${TRIP_TRAP} </dev/null | head -1 | cut -c1-100
EOT
  else echo "method=order-replace (harness IDLE replaces the native order; reason expected native_order_identity_changed)" > "$EV/forced.txt"
    lt_h <<EOT >> "$EV/force.txt" 2>&1
stobe-auto order $n IDLE </dev/null | head -1 | cut -c1-100
EOT
  fi
  lt_h <<EOT >> "$EV/force.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
sleep ${TRIP_FORCE_WAIT:-25}
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
  tr_agr agr_after.txt 8
  [ -n "${TRIP_TRAP:-}" ] && lt_h <<EOT >> "$EV/force.txt" 2>&1
stobe-auto teleport $n Shay </dev/null | head -1 | cut -c1-100
EOT
  rl_say 3 "Why did we stop?" || return $?
}
rd_23c() {  # squad member Malzin + temporary companion Cind on a native trip: "Leave." to each, then END to the temporary one
  tr_prep || return $?
  local cn="$RL_NPC_FULL"; tr_target Malzin || return 3; local mn="$RL_NPC_FULL"
  tr_target "$cn" || return 3
  tr_trip_setup || return $?
  tr_state state_cind_before.txt "$cn"; tr_state state_malzin_before.txt "$mn"
  rl_say 3 "Leave." || return $?
  tr_state state_cind_after_leave.txt "$cn"; tr_agr agr_s3.txt 8
  tr_target "$mn" || return 3
  rl_say 4 "Leave." || return $?
  tr_state state_malzin_after_leave.txt "$mn"
  tr_target "$cn" || return 3
  rl_say 5 "Let's call off the trip. I'll go on my own." || return $?
  tr_state state_malzin_after_end.txt "$mn"; tr_agr agr_final.txt 8
}
rd_23d() {  # active trip + unrelated job on the NPC (Copper Mine V): withdraw mid-trip, only the owned order goes
  TR_SCENE="${TR_SCENE:--54260 627 5890}"
  tr_prep || return $?
  local n; n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/scene.txt" 2>&1
stobe-auto clearjobs </dev/null | head -1 | cut -c1-100
EOT
  tr_trip_setup || return $?
  lt_h <<EOT > "$EV/job_set.txt" 2>&1
stobe-auto job $n "Copper Mine V" task OPERATE_MACHINERY radius 2500 </dev/null | head -2 | cut -c1-200
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-100
EOT
  rl_say 3 "Actually, forget the trip. I'll go on my own." || return $?
  tr_state state_after.txt "$RL_NPC_FULL"; tr_agr agr_final.txt 8
}
rd_24a() {  # mood question gets a grounded named place and NO trip row; control "What is Vain like?" makes no region_plan
  tr_prep || return $?; ROW_NATIVE=1
  rl_say 1 "Where would you take me to find some peace?" || return $?
  rl_say 2 "What is Vain like?" || return $?
}

# 13-b abandon: partner (Malzin) KO'd within 25 u for >= one 2 s real scan BEFORE the leaver (Cind) is moved away (NC6 observation-gap fix);
# phase 1 armed + KO, phase 2 control with a healthy partner. Evidence: n2_armed/n2_control (N2_* log lines), se_* (abandoned_in_danger rows).
tr_n2_log() {  # tr_n2_log <file> <n0> : N2 lines of stobe.log after line n0
  printf 'tail -n +%s %s | grep -E "N2_ABANDON|N2_PROXIMITY" | cut -c1-300 | tail -40\n' "$(( $2 + 1 ))" "$LT_STOBELOG" | lt_h > "$EV/$1" 2>&1
}
tr_se() {  # tr_se <file>: social_effect rows mentioning abandoned_in_danger
  lt_sql "select se::text from social_effect se where se::text like '%abandoned_in_danger%' order by 1" > "$EV/$1" 2>&1
}
tr_n2_move() {  # leaver armed next to the partner for ~8 s real, then teleported TRIP_LEAVE_DIST units away; polls for N2_ABANDON when $1=poll
  local pn="$1" ln="$2" mode="$3" wait_s="$4" n0="$5" ko="$6"
  lt_h <<EOT >> "$EV/phase-$mode.txt" 2>&1
stobe-auto teleport $ln $pn </dev/null | head -1 | cut -c1-100
stobe-auto teleport Shay $pn </dev/null | head -1 | cut -c1-100
stobe-auto order $ln HOLD_POSITION keep </dev/null | head -1 | cut -c1-80
sleep 6
if [ "$ko" = 1 ]; then stobe-auto protect $pn off </dev/null | head -1; stobe-auto order $pn IDLE </dev/null | head -1; stobe-auto ko $pn 300 </dev/null | head -1; fi
sleep 8
pos=\$(stobe-auto where $pn </dev/null | head -1 | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p'); set -- \$pos
x=\$(awk -v a="\$1" 'BEGIN{printf "%d", a+${TRIP_LEAVE_DIST:-108}}'); echo "leaver -> \$x \$2 \$3"
stobe-auto teleport $ln \$x \$2 \$3 </dev/null | head -1 | cut -c1-100
stobe-auto order $ln HOLD_POSITION keep </dev/null | head -1 | cut -c1-80
end=\$((SECONDS+$wait_s))
while [ \$SECONDS -lt \$end ]; do sleep 3; [ "$mode" = poll ] && tail -n +$((n0 + 1)) $LT_STOBELOG | grep -q N2_ABANDON && break; done
EOT
}
rd_13b() {
  unset ROW_NATIVE; tr_cfg
  local pa="${TRIP_PARTNER:-Malzin}" le="${TRIP_LEAVER:-$TD_NPC}" pn ln n0 k c
  tr_target "$pa" || return 3; pn=$(rl_q "$RL_NPC_FULL"); echo "$RL_NPC_FULL" > "$EV/partner.txt"
  tr_target "$le" || return 3; ln=$(rl_q "$RL_NPC_FULL"); echo "$RL_NPC_FULL" > "$EV/leaver.txt"; echo "$RL_NPC_FULL" > "$EV/npc.txt"
  [ "${TRIP_QUIET:-1}" = 0 ] || tr_quiet
  # phase 1: armed + partner KO
  tr_se se_base.txt
  n0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); n0=${n0:-0}
  tr_n2_move "$pn" "$ln" poll "${TRIP_N2_WAIT:-90}" "$n0" 1
  tr_n2_log n2_armed.txt "$n0"
  lt_h <<EOT >> "$EV/phase-poll.txt" 2>&1
stobe-auto wake $pn </dev/null | head -1
stobe-auto health $pn 100 </dev/null | head -1
EOT
  for k in $(seq 1 "${TRIP_SE_TRIES:-15}"); do
    c=$(lt_sql "select count(*) from social_effect se where se::text like '%abandoned_in_danger%'" | head -1 | tr -dc 0-9)
    [ "${c:-0}" -gt "$(grep -c . "$EV/se_base.txt" 2>/dev/null)" ] && break
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep 3
  done
  tr_se se_armed.txt
  # phase 2: control, healthy partner (same moves, no KO, fixed wait)
  lt_h <<EOT >> "$EV/phase-ctl.txt" 2>&1
stobe-auto protect $pn on </dev/null | head -1
stobe-auto teleport $ln $pn </dev/null | head -1 | cut -c1-100
EOT
  n0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); n0=${n0:-0}
  tr_n2_move "$pn" "$ln" ctl "${TRIP_CTRL_WAIT:-60}" "$n0" 0
  tr_n2_log n2_control.txt "$n0"; tr_se se_control.txt
  lt_h <<EOT >> "$EV/phase-ctl.txt" 2>&1
stobe-auto teleport $ln $pn </dev/null | head -1 | cut -c1-100
EOT
  echo "armed: KO within 25u then leaver moved ${TRIP_LEAVE_DIST:-108}u, poll<=${TRIP_N2_WAIT:-90}s; control: healthy partner, fixed ${TRIP_CTRL_WAIT:-60}s" > "$EV/phases.txt"
}

# ------------------------------------------------------------------ wrappers for rows that already exist (same rowcheck.py checks)
tr_wrap() {  # tr_wrap <fn>: rd_<fn> = tr_prep + the previous definition (re-sourcing keeps the first original)
  local f="rd_$1" o="_orig_rd_$1"
  declare -F "$o" >/dev/null || eval "$o() $(declare -f "$f" | tail -n +2)"
  eval "$f() { tr_prep || return \$?; $o; }"
}
for _r in 19a 23b 24b; do declare -F "rd_$_r" >/dev/null && tr_wrap "$_r"; done; unset _r

# reload the ready save (used by trip-run.sh before preflight; the rows themselves never reload): load, wait for the world, regroup, speed 0.5.
tr_reload() {
  tr_cfg; [ -n "$TR_SAVE" ] || { echo "no ready save known for lane $LT_LANE (use --save or TRIP_SAVE)"; return 3; }
  local o k n; n=$(rl_q "${ROW_NPC}")
  lt_h <<EOT | head -3
stobe-auto load $TR_SAVE </dev/null | head -1
EOT
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 20
  for k in $(seq 1 24); do
    o=$(echo 'stobe-auto status </dev/null | head -1' | lt_h 2>&1 | head -1)
    echo "$o" | grep -q 'phase=world' && break
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep 5
  done
  echo "$o" | grep -q 'phase=world' || { echo "reload: not in world after loading $TR_SAVE ($o)"; return 3; }
  lt_h <<EOT | head -5
stobe-auto order Shay HOLD_POSITION keep </dev/null | head -1
stobe-auto speed 0.5 </dev/null | head -1
stobe-auto teleport $n Shay </dev/null | head -1
stobe-auto order $n NULL_TASK </dev/null | head -1
EOT
}
