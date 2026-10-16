#!/usr/bin/env bash
# unblockdefs_f.sh: imm26-sfF one-call recipes for rows 13-c and 13-c-neg with NC18 (native-owned travel completion). Sourced by unblockrun_f.sh AFTER unblockdefs_b.sh
# (NEW file only; unblockdefs_b.sh is not edited: rd_13c / rd_13cneg below shadow the b versions inside the unblockrun_f.sh process only).
# Why: the server reconciles a native travel receipt only while it BUILDS A CONVERSATION PROMPT with a fresh (< 120 s) native snapshot (stobeCommitmentReconcileNative,
#   lib/commitment_native_bridge.php). The b recipe only polled the eventlog, so the agreement stayed ACCEPTED. Here, after the walk:
#   1. walk loop (same staging as ub_walk_stage: Shay on Cind 5 x 1.5 s per cycle in the positive leg, Shay held TRIP_13C_NEG_GAP u behind in the negative leg, NO harness
#      order on Cind) ends at the first of: agreement COMPLETED / FAILED, or a native end line in the lane stobe.log (NATIVE_TRAVEL_FINISH, NATIVE_TRAVEL phase=completed|failed,
#      NATIVE_TRAVEL_ORDER_ENDED) = UB_WALK_END=ARRIVED, or the tries run out = TIMEOUT.
#   2. ARRIVED: stobe_ctxpush (rl_say with ROW_NATIVE) + the line "We're here. Thanks for the walk." (step s3; ONE retry s3b when the agreement is still not terminal).
#      Positive leg: Shay is first teleported onto Cind. TIMEOUT: no turn is sent (a "We're here" without an arrival would be a lie); the checker names the cause.
#   3. poll the eventlog (UF_WAIT s, default 60): travel_agreement COMPLETED/FAILED + sharedexp rows (se_before/se_after as rd_13c).
#   Evidence added: native_travel.txt (NATIVE_TRAVEL START/FINISH/phase/ORDER_ENDED lines of the walk + the last 2 OBS lines), s3/ (the arrival turn); arrival.txt keeps the
#   `end=... gate=... last_progress=... agr_final_head=...` prefix the checker parses and appends native_start= native_finish=.
# Env knobs: as unblockdefs_b.sh (TRIP_13C_*), UF_WAIT (poll seconds after the arrival turn, 60).
UF_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F ub_sleep >/dev/null || . "$UF_HERE/unblockdefs_b.sh"
UF_ARRIVE_RE='NATIVE_TRAVEL_FINISH|NATIVE_TRAVEL phase=(completed|failed)|NATIVE_TRAVEL_ORDER_ENDED'

uf_native_end() {   # uf_native_end : 0 when the lane stobe.log has a native travel end line after UF_N0
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "%s" | head -1 | cut -c1-200 # uf:nend\n' "$(( ${UF_N0:-0} + 1 ))" "$LT_STOBELOG" "$UF_ARRIVE_RE" | lt_h 2>&1 | grep -q 'NATIVE_TRAVEL'
}
uf_native_dump() {  # uf_native_dump <file> : START/FINISH/phase/ORDER_ENDED lines of this walk + the last 2 OBS lines
  lt_h <<EOT > "$EV/$1" 2>&1
tail -n +$(( ${UF_N0:-0} + 1 )) $LT_STOBELOG 2>/dev/null | grep -a NATIVE_TRAVEL | grep -av NATIVE_TRAVEL_OBS | cut -c1-320 | head -14 # uf:ndump
tail -n +$(( ${UF_N0:-0} + 1 )) $LT_STOBELOG 2>/dev/null | grep -a NATIVE_TRAVEL_OBS | cut -c1-320 | tail -2 # uf:nobs
EOT
}
uf_terminal() {     # uf_terminal : prints COMPLETED / FAILED / "" from the eventlog counts
  local c f
  c=$(lt_sql "select count(*) from eventlog where type='travel_agreement' and data like '%\"status\":\"COMPLETED\"%'" | head -1 | tr -dc 0-9)
  f=$(lt_sql "select count(*) from eventlog where type='travel_agreement' and data like '%\"status\":\"FAILED\"%'" | head -1 | tr -dc 0-9)
  [ "${c:-0}" -gt 0 ] && { echo COMPLETED; return 0; }
  [ "${f:-0}" -gt 0 ] && { echo FAILED; return 0; }
  echo ""
}
uf_walk_stage() {   # uf_walk_stage <npc-quoted> <gate> <back> <neg 0|1> <gap> <speed> <tries>  (ub_walk_stage + the native-end exit)
  local n="$1" g="$2" back="$3" neg="$4" gap="$5" spd="$6" tries="$7" k c f w d stage nstage t
  if [ -n "${TRIP_13C_STAGE:-}" ]; then stage="${TRIP_13C_STAGE} dist 0"; nstage="${TRIP_13C_STAGE} dist $gap"; else stage="$g dist $back"; nstage="$g dist $(( back + gap ))"; fi
  echo "$stage" > "$EV/stage.txt"
  lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport $n $stage </dev/null | head -1 | cut -c1-120
EOT
  if [ "$neg" = 1 ]; then
    lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport Shay $nstage </dev/null | head -1 | cut -c1-120
EOT
  else
    lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  fi
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed $spd </dev/null | head -1
EOT
  UB_WALK_END=TIMEOUT; : > "$EV/walk_progress.txt"
  for k in $(seq 1 "$tries"); do
    if [ "$neg" = 1 ]; then ub_sleep 8; w=$(printf 'stobe-auto where %s </dev/null | head -1 | cut -c1-140\n' "$n" | lt_h 2>&1 | head -1)
    else
      w=$(lt_h <<EOT 2>&1 | tail -1
for i in 1 2 3 4 5; do stobe-auto teleport Shay $n </dev/null >/dev/null; sleep 1.5; done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
)
    fi
    d=$(echo "$w" | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \3/p' | head -1 | awk -v g="$g" 'BEGIN{}{split(g,a," "); dx=$1-a[1]; dz=$2-a[3]; printf "%.0f", sqrt(dx*dx+dz*dz)}')
    t=$(uf_terminal)
    c=0; f=0; [ "$t" = COMPLETED ] && c=1; [ "$t" = FAILED ] && f=1
    echo "$k|$(echo "$w" | cut -c1-100)|${d:-?}|${c}|${f}" >> "$EV/walk_progress.txt"
    [ "$c" = 1 ] && { UB_WALK_END=COMPLETED; break; }
    [ "$f" = 1 ] && { UB_WALK_END=FAILED; break; }
    uf_native_end && { UB_WALK_END=ARRIVED; break; }
  done
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed 0.5 </dev/null | head -1
EOT
}
rd_13c() {
  tr_prep || return $?
  local n g back neg s0 k mk gap t i waited
  n=$(rl_q "$RL_NPC_FULL"); neg="${TRIP_13C_NEG:-0}"; back="${TRIP_13C_BACK:-400}"; gap="${TRIP_13C_NEG_GAP:-150}"
  tr_trip_setup || return $?
  g=$(tr_gate); [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"; echo "neg=$neg back=$back gap=$gap speed=${TRIP_13C_SPEED:-1}" > "$EV/neg.txt"
  rd13c_sx se_before.txt
  mk=$(rl_mark); set -- $mk; s0=${4:-0}
  UF_N0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); UF_N0=${UF_N0:-0}
  uf_walk_stage "$n" "$g" "$back" "$neg" "$gap" "${TRIP_13C_SPEED:-1}" "${TRIP_13C_TRIES:-30}"
  if [ "$UB_WALK_END" = ARRIVED ]; then   # the server reconciles the receipt only on a prompt build with a fresh native snapshot: ctxpush (ROW_NATIVE) + the arrival line
    if [ "$neg" != 1 ]; then
      lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
    fi
    rl_say 3 "We're here. Thanks for the walk." || return $?
    waited=0
    for i in $(seq 1 "$(( ${UF_WAIT:-60} / 5 ))"); do
      rd13c_sx se_after.txt; t=$(uf_terminal)
      if [ "$neg" = 1 ]; then
        [ -n "$t" ] && [ "$waited" -ge 10 ] && break
        [ -n "$t" ] && waited=$(( waited + 5 ))
      else
        [ "$(grep -c 'sharedexp:' "$EV/se_after.txt" 2>/dev/null)" -gt "$(grep -c 'sharedexp:' "$EV/se_before.txt" 2>/dev/null)" ] && break
      fi
      ub_sleep 5
    done
    if [ -z "$(uf_terminal)" ]; then   # still ACCEPTED after the first turn: one more turn with a fresh snapshot
      rl_say 3b "We're here. The walk is done." || return $?
      for i in 1 2 3 4 5 6; do t=$(uf_terminal); [ -n "$t" ] && break; ub_sleep 5; done
    fi
  fi
  for k in $(seq 1 "$(( ${TRIP_13C_AWARD_WAIT:-30} / 5 ))"); do
    rd13c_sx se_after.txt
    { [ "$UB_WALK_END" = TIMEOUT ] || [ "$UB_WALK_END" = FAILED ]; } && break
    [ "$(grep -c 'sharedexp:' "$EV/se_after.txt" 2>/dev/null)" -gt "$(grep -c 'sharedexp:' "$EV/se_before.txt" 2>/dev/null)" ] && break
    [ "$neg" = 1 ] && break
    ub_sleep 5
  done
  rd13c_sx se_after.txt
  tr_agr agr_final.txt 8
  uf_native_dump native_travel.txt
  printf 'end=%s gate=%s last_progress=%s agr_final_head=%s native_start=%s native_finish=%s\n' "$UB_WALK_END" "$g" "$(tail -1 "$EV/walk_progress.txt" 2>/dev/null)" "$(head -1 "$EV/agr_final.txt" 2>/dev/null)" \
    "$(grep -a -m1 'NATIVE_TRAVEL_START' "$EV/native_travel.txt" 2>/dev/null | cut -c1-120 | tr ' ' '_')" "$(grep -a -m1 -E 'NATIVE_TRAVEL_FINISH|NATIVE_TRAVEL phase=' "$EV/native_travel.txt" 2>/dev/null | cut -c1-120 | tr ' ' '_')" > "$EV/arrival.txt"
  printf 'tail -n +%s %s 2>/dev/null | grep -a "Participation award" | cut -c1-700 | tail -6\n' "$(( s0 + 1 ))" "$LT_SRVLOG" | lt_w > "$EV/award.txt" 2>&1
  printf 'tail -n +%s %s | grep -a -i -E "participation|PLAYTHROUGH" | cut -c1-300 | tail -12\n' "$(( UF_N0 + 1 ))" "$LT_STOBELOG" | lt_h > "$EV/native.txt" 2>&1
}
rd_13cneg() { TRIP_13C_NEG=1 rd_13c; }
