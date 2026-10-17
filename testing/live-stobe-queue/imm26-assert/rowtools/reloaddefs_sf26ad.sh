#!/usr/bin/env bash
# reloaddefs_sf26ad.sh (imm26-fix26ad, SETUP-FAIL ticket 26-d): sourced AFTER reloaddefs_sf26bd.sh. NEW file; no queued script is edited. Fixes the 26-d RECIPE (not the checker):
#   the continuation record appears LATER than the check. After the s3 turn ("Are we still on that job?") the old record only reaches resume.state=pending ("restarts as soon as the target
#   is observed again": the post-load goats are not observed yet); the new accepted record (resume.continuedAs, NATIVE_TRAVEL_START) came ~100 s after the say, but reloadcheck_a.py was
#   fed the dump taken right after the say. This file REPLACES si_job (26-d run / 26-dx nc) and rl_say in that shell only:
#   1. si_job, mode run: after the s3 say POLL (RW_RESUME_POLL 150 s, every RW_RESUME_POLL_STEP 10 s) act_post.txt until the old accepted record is superseded AND a record with
#      resume.of = old id has status accepted|completed and resume.state resumed; THEN dump act_post / out_post / act_log_post / state_post exactly as before and let the unchanged
#      reloadcheck_a.py judge. NOTHING is relaxed: a continuation that never appears inside the window is still a FAIL (resume_state / continuation_record_exists checks), and every
#      check of the checker (same agreement, new world, exactly one active record, grant re-emitted, no 'start rejected') still runs on the final dump. Evidence: resume_poll.txt.
#      mode nc (26-dx) is unchanged (a cancelled Hunt is NOT resumed: nothing to wait for).
#   2. rl_say: the s3 say "Are we still..." also gets the Shay-to-NPC teleport inside its harness body (as the cancel say already has in sf26bd), because the people= guard needs the NPC
#      within TalkRadius at the moment of the say (scratch defs-sf26bd-tp.sh proved it: dist 32.7, guard OK). RW_RESUME_TELEPORT=0 disables.
# Env: RW_RESUME_POLL (150) RW_RESUME_POLL_STEP (10) RW_RESUME_TELEPORT (1) + every knob of sfi/sf26bd.
[ "$(type -t si_job)" = function ] && [ "$(type -t sb_say_orig)" = function ] || { echo "reloaddefs_sf26ad.sh: source reloaddefs_sfi.sh and reloaddefs_sf26bd.sh first" >&2; return 2 2>/dev/null || exit 2; }

rl_say() {   # rl_say <N> "text" [wait_s]   (sf26bd rl_say; the teleport also for "Are we still...")
  local rc iscancel=0
  case "${2:-}" in Cancel*|cancel*) [ "${RW_CANCEL_TELEPORT:-1}" = 1 ] && iscancel=1;; "Are we still"*) [ "${RW_RESUME_TELEPORT:-1}" = 1 ] && iscancel=1;; esac
  SB_PRE_SAY=""
  if [ $iscancel = 1 ]; then
    [ -n "${RL_NPC_ID:-}" ] || rl_resolve >/dev/null 2>&1 || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} before the say (stobe-auto where)"; return 3; }
    echo "say step $1 ('${2:0:24}'): $RL_NPC_FULL dist=${RL_DIST:-?} before the teleport" >> "$EV/cancel_teleport.txt"
    if [ "$SB_PATCH_OK" = 1 ]; then
      SB_PRE_SAY="stobe-auto teleport Shay $(rl_q "$RL_NPC_FULL") </dev/null | head -1 | cut -c1-160"$'
'"sleep ${RW_CANCEL_TP_WAIT:-0.5}"
    else
      sb_teleport_shay || return $?
    fi
  fi
  sb_say_orig "$@"; rc=$?
  SB_PRE_SAY=""
  [ $rc = 0 ] || return $rc
  sb_people_guard "$1" || return 3
  return 0
}

sa_resumed_ok() {   # sa_resumed_ok <actdump> <old id>: old record superseded AND a continuation (resume.of = old) accepted|completed with resume.state resumed (dump columns as rw_act_dump)
  awk -F'|' -v o="$2" '$1==o && $6=="superseded"{s=1} $11==o && $1!=o && ($6=="accepted"||$6=="completed") && $10=="resumed"{c=1} END{exit !(s&&c)}' "$EV/$1" 2>/dev/null
}
sa_poll_resume() {   # sa_poll_resume: after the s3 say; sets nothing, writes act_post.txt (final dump) + resume_poll.txt; rc 0 always (the checker judges the final dump)
  local old t=0 max="${RW_RESUME_POLL:-150}" step="${RW_RESUME_POLL_STEP:-10}" ok=0
  old=$(awk -F'|' '$6=="accepted"{id=$1} END{print id}' "$EV/act_pre.txt" 2>/dev/null)
  : > "$EV/resume_poll.txt"; echo "old=$old max=${max}s step=${step}s" >> "$EV/resume_poll.txt"
  while :; do
    rw_act_dump act_post.txt
    if [ -n "$old" ] && sa_resumed_ok act_post.txt "$old"; then ok=1; echo "t=${t}s RESUMED (superseded + continuation accepted|completed, resume.state resumed)" >> "$EV/resume_poll.txt"; break; fi
    echo "t=${t}s waiting: $(awk -F'|' '{printf "%s:%s/%s ", substr($1,1,17), $6, $10}' "$EV/act_post.txt" 2>/dev/null)" >> "$EV/resume_poll.txt"
    [ "$t" -ge "$max" ] && break
    rw_sleep "$step"; t=$((t+step))
  done
  [ $ok = 1 ] || echo "t=${t}s NOT RESUMED inside the window: the checker will judge this final dump (a FAIL, not a SETUP-FAIL)" >> "$EV/resume_poll.txt"
  return 0
}

si_job() {   # si_job run|nc  (26-d / 26-dx), sfi si_job + the bounded poll before the post-load dump (mode run)
  local mode="$1" accept rsay n0 n1
  echo Hunt > "$EV/kind.txt"; echo "$mode" > "$EV/mode.txt"
  si_start || return $?
  accept="${RW_ACCEPT:-$RW_ACCEPT_DEF}"; rsay="${RW_RESUME_SAY:-Are we still on that job?}"
  n0=$(rw_logn)
  si_offer act_s1.txt || return $?
  rw_has_status act_s1.txt proposed || { rw_log act_log_pre.txt "${n0:-0}"; return 0; }          # checker: SETUP-FAIL (no offer)
  si_wait_delivery "$SI_OFFER_STEP"
  rl_say 2 "$accept" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  if [ "$mode" = nc ]; then rl_say 2c "Cancel that." || return $?; rw_sleep 4; fi
  rw_act_dump act_pre.txt; rw_out_dump out_pre.txt; rw_log act_log_pre.txt "${n0:-0}"
  if [ "$mode" = run ]; then rw_has_status act_pre.txt accepted || return 0; fi                  # checker: SETUP-FAIL (accept did not land)
  tr_state state_pre.txt "$RL_NPC_FULL"
  rw_save_load job || return $?
  n1=$(rw_logn); si_goats post || return $?
  rl_say 3 "$rsay" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  if [ "$mode" = run ]; then sa_poll_resume; else rw_act_dump act_post.txt; fi
  rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  tr_state state_post.txt "$RL_NPC_FULL"
  if [ "$mode" = run ] && [ -n "${RW_COMPLETE:-}" ]; then
    lt_h <<EOT >> "$EV/complete.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
sleep ${RW_HUNT_WAIT:-180}
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
    rw_act_dump act_final.txt; rw_out_dump out_final.txt
  fi
  return 0
}
