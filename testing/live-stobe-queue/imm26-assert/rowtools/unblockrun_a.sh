#!/usr/bin/env bash
# unblockrun_a.sh <ROW> <lane> [options]   ONE call per unblock row (imm26-u-rowsA): optional reload of the lane's ready save -> preflight -> go-row (row steps + unblockcheck_a.py)
#   -> `EVIDENCE` lines -> exactly ONE `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ...` line; exit 0/1/2/3/4 as go-row.sh. Rows: 08-e 08-d 11-b.
#   Options: --save <name> (ready save to reload first; default for 4080-i4: kah-imm26-4080-i4h)  --no-reload  --dry  --allow-retry "<why>"
#            --neg (08-d negative control: no walk, topic must stay open)  --back <u> --speed <1-3> (08-d real-walk staging, defaults 350 / 2)  --tries <n> (08-e tick tries, 3)
#   Details: rowtools/unblockdefs_a.sh header; operator note inbox\operators\u-rowsA.txt.
UR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$UR_HERE/../go-row.sh"
. "$UR_HERE/reloaddefs_a.sh"
. "$UR_HERE/unblockdefs_a.sh"
PY="$UR_HERE/unblockpy_a.sh"
ur_usage() { echo "usage: unblockrun_a.sh <ROW: 08-e 08-d 11-b> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--neg] [--back U] [--speed N] [--tries N]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --neg) export U08D_NEG=1; shift;; --back) export TRIP_WALK_BACK="$2"; shift 2;;
  --speed) export TRIP_WALK_SPEED="$2"; shift 2;; --tries) export U_BORED_TRIES="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) ur_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; ur_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { ur_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
[ "$LANE" = 4080-i4 ] && : "${TRIP_SAVE:=kah-imm26-4080-i4h}" && export TRIP_SAVE
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
case "$norm" in 08-e|08-d|11-b) ;; *) echo "RESULT $ROW SETUP-FAIL not an unblock row (08-e 08-d 11-b)"; exit 2;; esac
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in walk_done.txt bored_ticks.txt state_combat.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && head -3 "$LT_OUT/$ROW/$f" | sed "s/^/EVIDENCE $ROW $f /"
done
echo "$out" | head -1
exit $rc
