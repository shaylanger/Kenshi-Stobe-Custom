#!/usr/bin/env bash
# unblockrun_b.sh <ROW> <lane> [options]   ONE call per row of the imm26-u-rowsB set: 13-c 13-c-neg 10-e 10-e-inproc 27-a (IMM- prefix optional).
#   Does: reload the lane's ready save (tr_reload) -> preflight -> go-row (attempt guard + timing log) running the rd_ function of unblockdefs_b.sh -> verdict by
#   unblockcheck_b.py (via pywrap_ub.sh; rowcheck.py/rowdefs.sh/go-row.sh are NOT edited) -> up to 6 `EVIDENCE` lines -> exactly ONE `RESULT <ROW> ...` line (or
#   `ROW-NEEDS-FIXER ...`). Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.
#   13-c      real walk-together to the gate (positive leg);  13-c-neg  negative leg (Shay left behind);
#   10-e      restitution scope across a REAL game restart (4080 lanes);  10-e-inproc  same probes after an in-process load: RECORD-ONLY (never PASS/FAIL);
#   27-a      BODYGUARD across a reload (needs harness DLL eeed8c93 on the lane: tools install-harness-4080-i4.ps1).
#   Options: --save <name> (ready save; i4: kah-imm26-4080-i4h)  --no-reload  --dry  --allow-retry "<why>"  --back <u> (13-c, default 400)  --stage "x y z" (13-c)
#            --gate "x y z"  --tries <n> (13-c walk cycles, default 30)  --dest <town>  --wait <n> (10-e: polls for the new session id, default 14)
#   4080-i4 needs KAH_PF_ISOLATION=0 in front (as reload-run.sh). Never run on a lane an operator is using unless you are that operator.
UB_RUN_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$UB_RUN_HERE/../go-row.sh"
. "$UB_RUN_HERE/reloaddefs_a.sh"
. "$UB_RUN_HERE/reloaddefs_b.sh"
. "$UB_RUN_HERE/unblockdefs_b.sh"
PY="$UB_RUN_HERE/pywrap_ub.sh"
ub_usage() { echo "usage: unblockrun_b.sh <13-c|13-c-neg|10-e|10-e-inproc|27-a> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--back u] [--stage 'x y z'] [--gate 'x y z'] [--tries n] [--dest T] [--wait n]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --back) export TRIP_13C_BACK="$2"; shift 2;; --stage) export TRIP_13C_STAGE="$2"; shift 2;; --gate) export TRIP_GATE="$2"; shift 2;;
  --tries) export TRIP_13C_TRIES="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;; --wait) export UB_10E_WAIT="$2"; shift 2;;
  -h|--help) ub_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; ub_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { ub_usage; exit 2; }
case "${ROW#IMM-}" in 13-c|13-c-neg|10-e|10-e-inproc|27-a) ;; *) echo "RESULT $ROW SETUP-FAIL not a row of the u-rowsB set (13-c 13-c-neg 10-e 10-e-inproc 27-a)"; exit 2;; esac
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
tr_cfg; export ROW_NPC
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
n=0; for f in "$LT_OUT/$ROW"/arrival.txt "$LT_OUT/$ROW"/award.txt "$LT_OUT/$ROW"/restart.txt "$LT_OUT/$ROW"/session_poll.txt "$LT_OUT/$ROW"/probe_eval.json \
              "$LT_OUT/$ROW"/dll_gate.txt "$LT_OUT/$ROW"/status_forms.txt "$LT_OUT/$ROW"/bg_set.txt; do
  [ -s "$f" ] && [ $n -lt 6 ] && { echo "EVIDENCE $ROW $(basename "$f"): $(tail -1 "$f" | cut -c1-240)"; n=$((n+1)); }
done
echo "$out" | head -1
exit $rc
