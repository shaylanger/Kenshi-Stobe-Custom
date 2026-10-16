#!/usr/bin/env bash
# tripdefs_sfk.sh: imm26-sfK2 recipe v2 for row 23-a (FX-TRAVEL: complete an agreed trip). Sourced by unblockrun_sfk.sh; tripdefs.sh / unblockdefs_f.sh / rowcheck_trip.py are NOT edited
# (queued scripts): this file REDEFINES tr_cfg (wrapper) and rd_23a only inside that process. The verdict is still rowcheck_trip.c_23a (rowcheck.py, unchanged, not weakened).
# Why v1 (rd_23a in tripdefs.sh) could not pass - two recipe defects (evidence C:\KenshiTestRuns\imm26-5090-i3\rows\23-a, 23-a.prev; lane stobe.log 10:58-10:59):
#   1. The hard-coded Squin gate "-62380 330 16250" (tripdefs.sh tr_cfg) is not a landing point: after `teleport Cind <gate>` + `teleport Shay <Cind>` the actor sits ~600 u above the
#      requested y (y=954 / 907), drops into the Squin shop guards (combat: Grost [Shop Guard Panlo] -> Shay (Initiated attack), knockout: Shay ... Battle Club from Vera, carry: Grost
#      picked up Shay) and when s3 runs the native speaker resolver (ChatBox.cpp ResolveSelectedOrConfiguredPlayerSpeaker: override/selected must be !isDead && !isUnconcious &&
#      !isDown) picks Malzin (resolved_speaker=Malzin dist 14779) -> SETUP-FAIL. The agreement's own destination_point (-62461 328.779 16346.8, source visited_location) keeps the actors
#      at y 324-328 with no combat (19-d, 23-a attempt #4). v2 prefers the NEWEST AGREEMENT'S destination_point (an explicit TRIP_GATE / --gate still wins) and defaults tr_cfg's Squin gate to it.
#   2. v1 teleported the NPC onto the goal while the native travel order was live: ~17 s later NATIVE_TRAVEL_ORDER_ENDED planar=147.2 near16=0 -> phase=failed
#      reason=native_order_ended_before_goal (agreement FAILED, attempt #4). v2 stages the NPC SFK_23A_BACK (400) u short of the gate with Shay on her and lets her WALK the leg with no harness
#      order (uf_walk_stage = the 13-c recipe of unblockdefs_f.sh), then waits for the native arrival line, sends ctxpush + the arrival line (ONE turn, s3) and polls for COMPLETED.
#   3. Availability guard before the arrival line: if Shay was knocked out / is still being attacked at the destination, he is healed, the guard waits SFK_KO_WAIT s and re-checks the lane
#      stobe.log; if attackers are still on him the row is a SETUP-FAIL BEFORE the say (so no Malzin line, no wasted turn), naming the cause.
# Env: SFK_SQUIN_GATE ("-62461 328.779 16346.8") SFK_23A_BACK(400) SFK_23A_SPEED(1) SFK_23A_TRIES(30 x ~8 s) SFK_KO_WAIT(25) SFK_23A_WAIT(60 s poll after the arrival turn) TRIP_GATE.
SFK_T_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F uf_walk_stage >/dev/null || . "$SFK_T_HERE/unblockdefs_f.sh"

if ! declare -F sfk_tr_cfg_orig >/dev/null; then eval "$(declare -f tr_cfg | sed '1s/^tr_cfg/sfk_tr_cfg_orig/')"; fi
tr_cfg() {   # original tr_cfg, then the Squin gate = the agreement's destination point (not the y=330 table value that launches the actor)
  sfk_tr_cfg_orig
  [ -n "${TRIP_GATE:-}" ] || [ "${TR_DEST:-}" != Squin ] || TR_GATE="${SFK_SQUIN_GATE:--62461 328.779 16346.8}"
}
sfk_gate() {   # sfk_gate: explicit TRIP_GATE, else the newest agreement's destination_point, else tr_gate
  local g
  [ -n "${TRIP_GATE:-}" ] && { echo "$TRIP_GATE"; return; }
  g=$(lt_sql "select data from eventlog where type='travel_agreement' order by rowid desc limit 1" | sed -nE 's/.*"destination_point":\{"x":(-?[0-9.]+),"y":(-?[0-9.]+),"z":(-?[0-9.]+).*/\1 \2 \3/p' | head -1)
  if [ -n "$g" ]; then echo "$g"; else tr_gate; fi
}
sfk_shay_events() {   # sfk_shay_events: count of stobe.log lines since UF_N0 where Shay was knocked out or attacked
  printf 'tail -n +%s %s 2>/dev/null | grep -a -c -E "knockout: Shay|combat: .* -> Shay" # sfk:ko\n' "$(( ${UF_N0:-0} + 1 ))" "$LT_STOBELOG" | lt_h 2>&1 | tail -1 | tr -dc 0-9
}
sfk_shay_guard() {   # rc 0 = Shay usable as the speaker; rc 3 = SETUP-FAIL reason in RL_REASON. Evidence shay_guard.txt
  local a b
  a=$(sfk_shay_events); a=${a:-0}
  echo "events_since_walk_start=$a" > "$EV/shay_guard.txt"
  [ "$a" -gt 0 ] || return 0
  lt_h <<EOT >> "$EV/shay_guard.txt" 2>&1
stobe-auto health Shay 100 </dev/null | head -1
stobe-auto teleport Shay $(rl_q "$RL_NPC_FULL") </dev/null | head -1 | cut -c1-120
EOT
  rw_sleep "${SFK_KO_WAIT:-25}"
  lt_h <<EOT >> "$EV/shay_guard.txt" 2>&1
stobe-auto health Shay 100 </dev/null | head -1
EOT
  b=$(sfk_shay_events); b=${b:-0}
  echo "after_wait=$b" >> "$EV/shay_guard.txt"
  if [ "$b" -gt "$a" ]; then
    RL_REASON="Shay is still being attacked / knocked out at the destination (stobe.log knockout|combat -> Shay lines $a -> $b in ${SFK_KO_WAIT:-25} s): the say would resolve Malzin as speaker; needs: recipe (other gate / TRIP_DEST, see shay_guard.txt)"
    return 3
  fi
  return 0
}

rd_23a() {   # FX-TRAVEL: complete an agreed trip, REAL walk to the gate (native arrival), then one arrival line
  tr_prep || return $?; tr_trip_setup || return $?
  local n g i t waited=0
  n=$(rl_q "$RL_NPC_FULL"); g=$(sfk_gate)
  [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"
  UF_N0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); UF_N0=${UF_N0:-0}
  uf_walk_stage "$n" "$g" "${SFK_23A_BACK:-400}" 0 150 "${SFK_23A_SPEED:-1}" "${SFK_23A_TRIES:-30}"
  uf_native_dump native_travel.txt
  printf 'end=%s gate=%s last_progress=%s\n' "$UB_WALK_END" "$g" "$(tail -1 "$EV/walk_progress.txt" 2>/dev/null)" > "$EV/arrival.txt"
  if [ "$UB_WALK_END" = TIMEOUT ]; then
    RL_REASON="no native arrival within ${SFK_23A_TRIES:-30} walk cycles (walk_progress.txt: $(tail -1 "$EV/walk_progress.txt" 2>/dev/null | cut -c1-120)); needs: recipe (raise SFK_23A_TRIES / lower SFK_23A_BACK) or native (no NATIVE_TRAVEL line = old DLL)"
    return 3
  fi
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  sfk_shay_guard || return 3
  tr_state state_shay.txt Shay
  rl_say 3 "We're here. Thanks for guiding me." || return $?
  for i in $(seq 1 "$(( ${SFK_23A_WAIT:-60} / 5 ))"); do
    t=$(uf_terminal); [ -n "$t" ] && break
    ub_sleep 5
  done
  tr_state state_after.txt "$RL_NPC_FULL"; tr_agr agr_final.txt 8
}
