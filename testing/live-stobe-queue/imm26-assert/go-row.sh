#!/usr/bin/env bash
# go-row.sh [--no-preflight] <ROW> <lane>   one imm26 test row = one command (COORDINATOR_IMPROVEMENTS items 1/2).
#   lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4.   rows: 04-c 06-c 08-a 12-a 12-b 12-d 14-a 19-a 23-b 24-b (IMM- prefix optional)
# Does: preflight.sh (PLAYER_NAME, clean deals/agreements/anchor, lane isolation, FAIL FAST if dist >= 80 or lane down) -> row setup +
# say steps (rowdefs.sh) -> evidence dump -> rowcheck.py assertions. STDOUT = exactly ONE line:
#   RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]          (exit 0 PASS, 1 FAIL, 2 SETUP-FAIL, 3 GATED)
# Everything else goes to <dir>/run.log. Evidence dir: C:\KenshiTestRuns\<lane-dir>\rows\<ROW>\ (previous run kept as <ROW>.prev) with
# s<N>/ bundles, social_effect.txt (select * ...), haff-*.txt, inv_*.txt, distance.txt, deals.txt, agreements.txt, result.txt.
# Heartbeat: when env KAH_AGENT_NAME is set, the agent's status `latest` is set to the RESULT line after every row (agent-status.ps1).
# Open an evidence file only for a FAIL. Never run on a lane an operator is using unless you are that operator.
# Test switches: KAH_ROW_FAKE=1 (+ lt_fake) / KAH_ROW_DRY=1 (prints `RESULT <ROW> DRY-RUN ...`), KAH_ROWS_BASE, KAH_RUNS_DIR (see lane.sh, heartbeat.sh).
GR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$GR_HERE/rowtools/rowlib.sh"; . "$GR_HERE/rowtools/rowdefs.sh"; . "$GR_HERE/rowtools/heartbeat.sh"; . "$GR_HERE/preflight.sh"
PY=$(command -v python3 || command -v python)

gr_default_fake() {  # DRY-RUN simulator: plausible answers, no verdicts
  local kind="$1" body="$2"
  case "$kind" in
    h) case "$body" in *"status"*) echo "phase=world speed=0.5 paused=0 save=dry";; *"where "*) echo "Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist=9.0";;
         *unconscious*) echo '"unconscious":false';; *"wc -l"*) echo 0;; esac ;;
    w) case "$body" in *curl*) echo '{"status":"ok"}';; *"stat -c"*|*"wc -l"*) echo 0;; esac ;;
    sql) case "$body" in *"general_settings where id='PLAYER_NAME'"*) echo Shay;; *"stobe_social_contract where status"*) echo "0/0";;
         *"count("*|*"max(rowid)"*) echo 0;; esac ;;
  esac
}
gr_result() {  # gr_result <ROW> <KIND> <text>  -> the one stdout line, result.txt, heartbeat; returns the exit code
  local line="RESULT $1 $2 $3" rc
  case "$2" in PASS) rc=0;; FAIL) rc=1;; SETUP-FAIL) rc=2;; *) rc=3;; esac
  echo "$line" | tee "${EV:-/dev/null}/result.txt" 2>/dev/null | cut -c1-1900
  hb_update "$line" "${EV:-$LT_OUT}"
  return $rc
}
gr_main() {
  local nopf="" row lane norm fn rc out
  [ "${1:-}" = "--no-preflight" ] && { nopf=1; shift; }
  row="${1:-}"; lane="${2:-}"
  [ -n "$row" ] && [ -n "$lane" ] || { echo "usage: go-row.sh [--no-preflight] <ROW> <lane: $(lt_lanes)>" >&2; return 2; }
  lt_load "$lane" >/dev/null || { echo "RESULT $row SETUP-FAIL PREFLIGHT-FAIL unknown lane '$lane'"; return 2; }
  norm="${row#IMM-}"; fn="rd_${norm//-/}"
  rl_begin "$row"
  if ! declare -F "$fn" >/dev/null; then gr_result "$row" SETUP-FAIL "row not ported to go-row.sh (ported: 04-c 06-c 08-a 12-a 12-b 12-d 14-a 19-a 23-b 24-b)"; return 2; fi
  if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
  if [ -z "$nopf" ]; then
    out=$(pf_run "$lane" "${ROW_NPC:-Cind}" 2>&1); rc=$?; echo "$out" > "$EV/preflight.txt"
    if [ $rc != 0 ]; then gr_result "$row" SETUP-FAIL "$(echo "$out" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $out" | head -1)"; return 2; fi
  fi
  lt_load "$lane" >/dev/null
  "$fn" >> "$EV/run.log" 2>&1; rc=$?
  case $rc in
    3) gr_result "$row" SETUP-FAIL "${RL_REASON:-setup failed (see $EV/run.log)}"; return 2;;
    4) gr_result "$row" GATED "${RL_REASON:-gated}"; return 3;;
    0) ;;
    *) gr_result "$row" SETUP-FAIL "row script rc=$rc (see $EV/run.log)"; return 2;;
  esac
  rl_final_dump >> "$EV/run.log" 2>&1
  if [ -n "${KAH_ROW_DRY:-}" ]; then
    gr_result "$row" DRY-RUN "planned lane=$lane steps=$(ls -d "$EV"/s[0-9]* 2>/dev/null | wc -l) transcript=${KAH_ROW_FAKE_LOG:-none} evidence=$EV"; return 0
  fi
  out=$("$PY" "$GR_HERE/rowtools/rowcheck.py" "$row" "$EV" 2>>"$EV/run.log" | tail -1); rc=$?
  [ -n "$out" ] || { gr_result "$row" FAIL "rowcheck.py produced no result (see $EV/run.log)"; return 1; }
  echo "$out" | tee "$EV/result.txt" | cut -c1-1900
  hb_update "$out" "$EV"
  case "$out" in "RESULT $row PASS"*) return 0;; "RESULT $row SETUP-FAIL"*) return 2;; "RESULT $row GATED"*) return 3;; *) return 1;; esac
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then gr_main "$@"; exit $?; fi
