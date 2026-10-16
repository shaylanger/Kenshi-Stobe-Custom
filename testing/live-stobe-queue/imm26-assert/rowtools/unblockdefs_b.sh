#!/usr/bin/env bash
# unblockdefs_b.sh: imm26-u-rowsB one-call recipes for the three SETUP-FAIL rows 13-c, 10-e, 27-a (4080-i4 operator). Sourced by unblockrun_b.sh AFTER go-row.sh,
# reloaddefs_a.sh and reloaddefs_b.sh. NEW file only: rowdefs.sh / tripdefs.sh / hxdefs.sh / hunt26a-scene.sh / reloaddefs_*.sh are not edited; the rd_ functions
# below are defined only inside the unblockrun_b.sh process (they shadow the same-named originals there, nowhere else).
#   rd_13c      13-c   REAL walk-together to the gate (ub_walk_stage): like tripdefs.sh rd_13c, but the walk loop stops at COMPLETED/FAILED and records the arrival
#               (arrival.txt, walk_progress.txt) so the verdict names an arrival defect (native_order_ended_before_goal) instead of a silent timeout.
#   rd_13cneg   13-c-neg  negative leg (Shay held TRIP_13C_NEG_GAP u behind): no sharedexp row expected.
#   rd_10e      10-e   restitution scope across a REAL game restart (save -> rig_stop -> rig_launch -> wait-world -> poll until native_session_id changes).
#   rd_10einproc 10-e-inproc  same probes across an in-process save+load: RECORD-ONLY (what the server does when the epoch is up and the session is the same).
#   rd_27a      27-a   BODYGUARD order across a reload: harness-DLL gate (`unknown command` = install eeed8c93, install-harness-4080-i4.ps1), several status read-back
#               forms (status_forms.txt), the same evidence files as reloaddefs_a.sh rd_27a so reloadcheck_a.c_27a decides.
# Env knobs: TRIP_13C_* (as tripdefs.sh: BACK 400, STAGE, NEG_GAP 150, SPEED 1, TRIES 30, AWARD_WAIT 30)  UB_10E_WAIT (poll tries for the new session, 14)  RW_BG_ARGS ("hours 24 own")
#   RW_AWAY / RW_CHASE_S (rw_chase).  Evidence only below $EV.
UB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UB_PROBE="$UB_HERE/repairprobe.php"
ub_sleep() { [ -n "${KAH_ROW_FAKE:-}" ] || sleep "$1"; }

# ------------------------------------------------------------------ 13-c: walk-together stage + loop
# ub_walk_stage <npc-quoted> <gate "x y z"> <back> <neg 0|1> <gap> <speed> <tries>: Cind staged <back> u short of the gate, Shay on her (positive) or <gap> u behind (negative);
# speed <speed>; per cycle (~8 s real) Shay is teleported onto Cind 5 x 1.5 s (positive leg: separation stays far below 35 u, per-sample jump small), Cind walks natively
# (NO harness order on her); the loop ends at the first COMPLETED or FAILED travel_agreement. Sets UB_WALK_END=COMPLETED|FAILED|TIMEOUT. walk_progress.txt: "k|where-line|dist_to_gate|completed|failed".
ub_walk_stage() {
  local n="$1" g="$2" back="$3" neg="$4" gap="$5" spd="$6" tries="$7" k c f w d stage nstage
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
    c=$(lt_sql "select count(*) from eventlog where type='travel_agreement' and data like '%\"status\":\"COMPLETED\"%'" | head -1 | tr -dc 0-9)
    f=$(lt_sql "select count(*) from eventlog where type='travel_agreement' and data like '%\"status\":\"FAILED\"%'" | head -1 | tr -dc 0-9)
    echo "$k|$(echo "$w" | cut -c1-100)|${d:-?}|${c:-0}|${f:-0}" >> "$EV/walk_progress.txt"
    [ "${c:-0}" -gt 0 ] && { UB_WALK_END=COMPLETED; break; }
    [ "${f:-0}" -gt 0 ] && { UB_WALK_END=FAILED; break; }
  done
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed 0.5 </dev/null | head -1
EOT
}
rd_13c() {
  tr_prep || return $?
  local n g back neg s0 n0 k mk gap
  n=$(rl_q "$RL_NPC_FULL"); neg="${TRIP_13C_NEG:-0}"; back="${TRIP_13C_BACK:-400}"; gap="${TRIP_13C_NEG_GAP:-150}"
  tr_trip_setup || return $?
  g=$(tr_gate); [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"; echo "neg=$neg back=$back gap=$gap speed=${TRIP_13C_SPEED:-1}" > "$EV/neg.txt"
  rd13c_sx se_before.txt
  mk=$(rl_mark); set -- $mk; s0=${4:-0}
  n0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); n0=${n0:-0}
  ub_walk_stage "$n" "$g" "$back" "$neg" "$gap" "${TRIP_13C_SPEED:-1}" "${TRIP_13C_TRIES:-30}"
  for k in $(seq 1 "$(( ${TRIP_13C_AWARD_WAIT:-30} / 5 ))"); do
    rd13c_sx se_after.txt
    [ "$UB_WALK_END" != COMPLETED ] && break
    [ "$(grep -c 'sharedexp:' "$EV/se_after.txt" 2>/dev/null)" -gt "$(grep -c 'sharedexp:' "$EV/se_before.txt" 2>/dev/null)" ] && break
    ub_sleep 5
  done
  rd13c_sx se_after.txt
  tr_agr agr_final.txt 8
  printf 'end=%s gate=%s last_progress=%s agr_final_head=%s\n' "$UB_WALK_END" "$g" "$(tail -1 "$EV/walk_progress.txt" 2>/dev/null)" "$(head -1 "$EV/agr_final.txt" 2>/dev/null)" > "$EV/arrival.txt"
  printf 'tail -n +%s %s 2>/dev/null | grep -a "Participation award" | cut -c1-700 | tail -6\n' "$(( s0 + 1 ))" "$LT_SRVLOG" | lt_w > "$EV/award.txt" 2>&1
  printf 'tail -n +%s %s | grep -a -i -E "participation|PLAYTHROUGH" | cut -c1-300 | tail -12\n' "$(( n0 + 1 ))" "$LT_STOBELOG" | lt_h > "$EV/native.txt" 2>&1
}
rd_13cneg() { TRIP_13C_NEG=1 rd_13c; }

# ------------------------------------------------------------------ 10-e: restitution scope across a REAL restart
ub_probe() {   # ub_probe scope|eval [scope-json]  (repairprobe.php, read-only; tag rb:probe is what reloadfake_b.py answers)
  local npc="${RL_NPC_FULL%% \[*}"
  printf 'cd %s/site; KAH_LANE_ROOT=%s KAH_LANE_DB=%s php %s %s %s %s 2>&1 | head -c 8000 # rb:probe\n' "$LT_ROOT" "$LT_ROOT" "$LT_DB" "$(rl_wsl_path "$UB_PROBE")" "$1" "$(rl_q "${2:-}")" "$(rl_q "$npc")" | lt_w
}
ub_world_wait() {   # ub_world_wait <tries> : phase=world within <tries> x 5 s (the lane game was just relaunched)
  local k o
  for k in $(seq 1 "$1"); do
    o=$(echo 'stobe-auto status </dev/null | head -1' | lt_h 2>&1 | head -1)
    echo "$o" | grep -q 'phase=world' && return 0
    ub_sleep 5
  done
  RL_REASON="not in the world after the restart ($o)"; return 3
}
ub_restart() {   # ub_restart <save>: save, stop the lane's game, relaunch from the save, wait for the world, NPC next to Shay. 4080 lanes only (rig_stop / rig_launch route).
  local sv="$1"
  [ "$LT_RIG" = 4080 ] || { RL_REASON="restart variant: 4080 lanes only (5090 sessions are paused; 5090 route not wired)"; return 3; }
  printf 'stobe-auto save %s </dev/null | head -1\n' "$sv" | lt_h > "$EV/save.txt" 2>&1
  ub_sleep 6
  echo "$sv" > "$EV/save_name.txt"
  lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9 > "$EV/load_rowid.txt"
  lt_h <<EOT > "$EV/restart.txt" 2>&1
echo "restart: stop"; rig_stop 2>&1 | tail -3
echo "restart: stopped rc=\$?"
EOT
  ub_sleep 8
  printf 'echo "restart: launch %s"; rig_launch %s 2>&1 | tail -4\necho "restart: launched"\n' "$sv" "$sv" | lt_h >> "$EV/restart.txt" 2>&1
  grep -q 'restart: launched' "$EV/restart.txt" || { RL_REASON="restart: launch did not return (see restart.txt)"; return 3; }
  ub_sleep 20
  ub_world_wait 40 || return 3
  ub_sleep 8
  echo 'stobe-auto speed 0.5 </dev/null | head -1' | lt_h >> "$EV/restart.txt" 2>&1
  echo "restart=ok" >> "$EV/restart.txt"
  rd19_place near || return 3
}
ub_wait_new_session() {   # ub_wait_new_session <old-session-id>: poke ctxpush, poll the live scope until native_session_id differs (UB_10E_WAIT x ~10 s); writes probe_post.json
  local k old="$1" cur n
  n=$(rl_q "$RL_NPC_FULL")
  for k in $(seq 1 "${UB_10E_WAIT:-14}"); do
    printf 'stobe-auto stobe_ctxpush %s </dev/null 2>&1 | head -1 | cut -c1-120\n' "$n" | lt_h >> "$EV/ctxpush.txt" 2>&1
    ub_sleep 10
    ub_probe scope > "$EV/probe_post.json" 2>&1
    cur=$(sed -nE 's/.*"native_session_id":"?([^",}]*).*/\1/p' "$EV/probe_post.json" | head -1)
    echo "$k|$cur" >> "$EV/session_poll.txt"
    [ -n "$cur" ] && [ "$cur" != "$old" ] && return 0
  done
  return 0
}
rd_10e() {
  rb_cfg; rd_need_npc || return 3; echo "$RL_NPC_FULL" > "$EV/npc.txt"
  local r old
  ub_probe scope > "$EV/probe_pre.json" 2>&1
  old=$(sed -nE 's/.*"native_session_id":"?([^",}]*).*/\1/p' "$EV/probe_pre.json" | head -1)
  ub_restart "kah-imm26-10e-$LT_LANE" || return 3
  ub_wait_new_session "$old"
  r=$(head -1 "$EV/probe_pre.json")
  ub_probe eval "$r" > "$EV/probe_eval.json" 2>&1
}
rd_10einproc() {   # record-only: same probes across an in-process save+load (the session id is expected to stay)
  rb_cfg; rd_need_npc || return 3; echo "$RL_NPC_FULL" > "$EV/npc.txt"
  local r
  ub_probe scope > "$EV/probe_pre.json" 2>&1
  rb_saveload "kah-imm26-10e-$LT_LANE" || return 3
  r=$(head -1 "$EV/probe_pre.json")
  ub_probe eval "$r" > "$EV/probe_eval.json" 2>&1
  ub_probe scope > "$EV/probe_post.json" 2>&1
}

# ------------------------------------------------------------------ 27-a: BODYGUARD across a reload
ub_bg_status() {   # ub_bg_status <file> <npc-quoted>: try the status forms in order (status_forms.txt keeps every answer); <file> = the first answer holding has_contract=, else the errors
  local f="$1" nq="$2" form ans got=""
  : > "$EV/$f"
  for form in "$nq Shay status" "$nq status" "$nq @player status" "$nq hirer Shay status"; do
    ans=$(printf 'stobe-auto contract-bodyguard %s </dev/null 2>&1 | head -3 | cut -c1-300 # ub:bgstatus\n' "$form" | lt_h 2>&1 | head -3)
    printf '%s %s => %s\n' "$f" "$form" "$(echo "$ans" | tr '\n' ' ')" >> "$EV/status_forms.txt"
    if echo "$ans" | grep -q 'has_contract='; then echo "$ans" | grep -m1 'has_contract=' > "$EV/$f"; got=1; break; fi
    echo "$ans" >> "$EV/$f"
  done
  [ -n "$got" ]
}
rd_27a() {
  local nq RW_AWAY="${RW_AWAY_BG:-200}"   # 27A-FIX: 200 u (not the 80 u default): a follower ends <= ~70 u, a non-follower stays >= ~200 u; rw_chase reads RW_AWAY (dynamic scope)
  rw_prep || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT > "$EV/dll_gate.txt" 2>&1
stobe-auto contract-bodyguard $nq status </dev/null 2>&1 | head -2 | cut -c1-200
EOT
  if grep -qi 'unknown command' "$EV/dll_gate.txt"; then
    RL_REASON="harness DLL on $LT_LANE has no contract-bodyguard (answer: $(head -1 "$EV/dll_gate.txt" | cut -c1-60)): stop the lane game, powershell -File install-harness-4080-i4.ps1 -Action Apply on the 4080 (eeed8c93), relaunch from the row save (needs: harness install)"
    return 3
  fi
  # 27A-FIX negative control: the same chase BEFORE the hire (no contract) -> chase_ctrl.txt; the checker needs it to NOT approach. Then the NPC is put back next to Shay.
  rw_chase ctrl || return $?
  rd19_place near || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT > "$EV/bg_set.txt" 2>&1
stobe-auto contract-bodyguard $nq Shay ${RW_BG_ARGS:-hours 24 own} </dev/null 2>&1 | head -3 | cut -c1-300
EOT
  ub_sleep 3
  ub_bg_status bg_pre.txt "$nq"
  tr_state state_pre.txt "$RL_NPC_FULL"
  cat "$EV/bg_set.txt" "$EV/bg_pre.txt" "$EV/state_pre.txt" 2>/dev/null | grep -iE 'BODYGUARD|has_contract=1' | grep -qviE 'ERROR|unknown command|no character named' || return 0   # checker: SETUP-FAIL (no order)
  rw_chase pre || return $?
  rw_save_load bodyguard near || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  ub_bg_status bg_post.txt "$nq"
  printf 'stobe-auto stobe_ctxpush %s </dev/null 2>&1 | head -2 | cut -c1-200\n' "$nq" | lt_h > "$EV/ctxpush_post.txt" 2>&1
  tr_state state_post.txt "$RL_NPC_FULL"
  rw_chase post || return $?
  tr_state state_after_chase.txt "$RL_NPC_FULL"
}
