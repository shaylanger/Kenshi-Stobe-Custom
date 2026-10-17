#!/usr/bin/env bash
# unblockrun_23acheck.sh = unblockrun_sfk.sh + tripdefs_23acheck.sh (rd_23a also captures s3/plugin_out.txt and a following turn s4); verdict: rowcheck_trip.py c_23a (candidate23a swapped in). Original header: unblockrun_sfk.sh <ROW> <lane> [options]   ONE call per row (imm26-sfK2): 23-a (real-walk trip completion) and 11-b (no follow-up claim in combat) with the recipe-v2 definitions
#   (tripdefs_sfk.sh rd_23a, unblockdefs_sfk.sh rd_11b). Optional reload of the lane's ready save -> preflight -> go-row (row steps) -> `EVIDENCE` lines -> exactly ONE
#   `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh. Verdicts: rowcheck.py (23-a, unchanged) / unblockcheck_a.py (11-b, unchanged) via unblockpy_a.sh.
#   Options: --save <name>  --no-reload  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of the same row: go-row refuses to rerun it otherwise)
#            23-a : --gate "x y z" (default: the agreement's destination point)  --back <u> (400)  --speed <1-3> (1)  --tries <n> (30 walk cycles ~8 s each)  --dest <town>
#            11-b : --faction "<enemy faction>" (Dust Bandits)  --calm-tries <n> (8, 15 s each)
#   Details: rowtools/tripdefs_sfk.sh and rowtools/unblockdefs_sfk.sh headers; operator note inbox\operators\sfK.txt. Selftest: rowtools/unblock_sfk_selftest.sh.
US_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$US_HERE/../go-row.sh"
. "$US_HERE/reloaddefs_a.sh"
. "$US_HERE/reloaddefs_b.sh"
. "$US_HERE/unblockdefs_a.sh"
. "$US_HERE/tripdefs_sfk.sh"
. "$US_HERE/unblockdefs_sfk.sh"
. "$US_HERE/tripdefs_23acheck.sh"   # imm26-fix23acheck: s3/plugin_out.txt + s4 following turn
PY="$US_HERE/unblockpy_a.sh"
us_usage() { echo "usage: unblockrun_23acheck.sh <ROW: 23-a 11-b> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--gate 'x y z'] [--back U] [--speed N] [--tries N] [--dest T] [--faction F] [--calm-tries N]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --gate) export TRIP_GATE="$2"; shift 2;; --back) export SFK_23A_BACK="$2"; shift 2;;
  --speed) export SFK_23A_SPEED="$2"; shift 2;; --tries) export SFK_23A_TRIES="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;;
  --faction) export U11B_FACTION="$2"; shift 2;; --calm-tries) export U11B_CALM_TRIES="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) us_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; us_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { us_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "$LANE" = 4080-i4 ] && : "${TRIP_SAVE:=kah-imm26-4080-i4h}" && export TRIP_SAVE
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
case "$norm" in 23-a|11-b) ;; *) echo "RESULT $ROW SETUP-FAIL not an sfK row (23-a 11-b)"; exit 2;; esac
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in arrival.txt shay_guard.txt calm_poll.txt scene_pre.txt.n enemy.txt claimable.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -3 "$LT_OUT/$ROW/$f" | cut -c1-240 | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
