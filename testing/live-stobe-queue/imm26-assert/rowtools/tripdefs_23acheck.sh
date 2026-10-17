#!/usr/bin/env bash
# tripdefs_23acheck.sh (imm26-fix23acheck, Shay 2026-10-16 option A): wraps the sfK2 rd_23a (tripdefs_sfk.sh, UNEDITED) with the two extra evidence captures the
# new c_23a needs: (1) s3/plugin_out.txt = output_to_plugin.log ScriptQueue lines since before the row's chat turns (request_id per sentence chunk, so one LLM reply split
# into chunks counts once), (2) s4 = a neutral FOLLOWING turn after the usual state/agreement captures; c_23a fails if s4 re-acknowledges the arrival and is SETUP-FAIL if s4 is missing.
# Sourced only by unblockrun_23acheck.sh (after tripdefs_sfk.sh); nothing queued uses it. Needs rowcheck_trip.py with the c_23a candidate23a swapped in.
declare -F rd_23a >/dev/null || { echo "tripdefs_23acheck.sh: source tripdefs_sfk.sh first" >&2; return 1 2>/dev/null || exit 1; }
if ! declare -F rd_23a_sfk >/dev/null; then eval "$(declare -f rd_23a | sed '1s/^rd_23a /rd_23a_sfk /')"; fi
rd_23a() {
  local pl pn0=0 rc
  pl="$(dirname "$LT_SRVLOG")/output_to_plugin.log"
  [ -n "${KAH_ROW_FAKE:-}" ] || { pn0=$(printf 'wc -l < %s 2>/dev/null || echo 0\n' "$pl" | lt_w | tail -1 | tr -dc 0-9); pn0=${pn0:-0}; }
  rd_23a_sfk; rc=$?
  [ $rc = 0 ] || return $rc
  mkdir -p "$EV/s3"
  [ -n "${KAH_ROW_FAKE:-}" ] || printf "tail -n +%s %s 2>/dev/null | grep -a '\"action\":\"ScriptQueue\"' | cut -c1-900 | tail -80\n" "$((pn0 + 1))" "$pl" | lt_w > "$EV/s3/plugin_out.txt" 2>&1
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${TRIP_23A_SETTLE:-15}"      # late s3 chunks are spoken up to ~10 s after the first one
  rl_say 4 "What do you make of this place?" || return $?
}
