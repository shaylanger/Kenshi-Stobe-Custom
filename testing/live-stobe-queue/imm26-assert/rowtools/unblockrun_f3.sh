#!/usr/bin/env bash
# unblockrun_f3.sh <ROW> <lane> [options]   ONE call per row: 13-c 13-c-neg (IMM- prefix optional) with the NC18 arrival turn (imm26-sfF) AND a participation-qualified walk (imm26-sfFixB).
#   = unblockrun_f.sh + unblockdefs_f3.sh (positive leg: sfr22b_keep.sh keeper at game speed TRIP_13C_SPEED, default 0.5) + unblockcheck_f3.py (names an unbound / unqualified native
#   participation proof as SETUP-FAIL; 13-c-neg PASS needs bound=1 AND qualified=0). Needs a lane DLL with NC21 or newer (NC28/NC30/NC31): `participation_bound=1` in NATIVE_TRAVEL_START.
#   Env: TRIP_13C_SPEED (0.5) UF3_KEEP_CALLS (8 keeper calls of ~60-80 s, positive leg) SFK_KEEP_N/SFK_KEEP_SLEEP (80 / 0.5) TRIP_13C_TRIES (neg leg hop cycles, 30) TRIP_13C_NEG_GAP (150).
#   Existing unblockrun_f.sh / unblockdefs_f.sh / unblockcheck_f.py are untouched. Original header of unblockrun_f.sh follows.
#   Same as unblockrun_b.sh (reload ready save -> preflight -> go-row running rd_13c/rd_13cneg of unblockdefs_f.sh -> verdict by unblockcheck_f.py via pywrap_uf3.sh),
#   but after the walk it waits for the native arrival (NATIVE_TRAVEL_FINISH in the lane stobe.log), sends ctxpush + "We're here. Thanks for the walk." and polls the eventlog
#   for travel_agreement COMPLETED and the sharedexp row (13-c) / no sharedexp row (13-c-neg). Prints up to 6 `EVIDENCE` lines (native_travel.txt first) and ONE `RESULT <ROW> ...` line.
#   Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.   Needs the NC18 Stobe.dll (D54D0268) on the lane.
#   Options: --save <name> (i4: kah-imm26-4080-i4h)  --no-reload  --dry  --allow-retry "<why>"  --back <u>  --stage "x y z"  --gate "x y z"  --tries <n>  --dest <town>
#   4080-i4 needs KAH_PF_ISOLATION=0 in front (as reload-run.sh). Never run on a lane an operator is using unless you are that operator.
UB_RUN_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$UB_RUN_HERE/../go-row.sh"
. "$UB_RUN_HERE/reloaddefs_a.sh"
. "$UB_RUN_HERE/reloaddefs_b.sh"
. "$UB_RUN_HERE/unblockdefs_f.sh"
. "$UB_RUN_HERE/unblockdefs_f3.sh"
PY="$UB_RUN_HERE/pywrap_uf3.sh"
: "${TRIP_13C_SPEED:=0.5}"; export TRIP_13C_SPEED
ub_usage() { echo "usage: unblockrun_f3.sh <13-c|13-c-neg> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--back u] [--stage 'x y z'] [--gate 'x y z'] [--tries n] [--dest T]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --back) export TRIP_13C_BACK="$2"; shift 2;; --stage) export TRIP_13C_STAGE="$2"; shift 2;; --gate) export TRIP_GATE="$2"; shift 2;;
  --tries) export TRIP_13C_TRIES="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;;
  -h|--help) ub_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; ub_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { ub_usage; exit 2; }
case "${ROW#IMM-}" in 13-c|13-c-neg) ;; *) echo "RESULT $ROW SETUP-FAIL not a row of the sfF set (13-c 13-c-neg)"; exit 2;; esac
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
n=0; for f in "$LT_OUT/$ROW"/native_travel.txt "$LT_OUT/$ROW"/arrival.txt "$LT_OUT/$ROW"/agr_final.txt "$LT_OUT/$ROW"/award.txt "$LT_OUT/$ROW"/se_after.txt; do
  [ -s "$f" ] && [ $n -lt 6 ] && { case "$f" in *native_travel.txt) ev=$(grep -a -E 'NATIVE_TRAVEL_(START|FINISH|ORDER_ENDED)|NATIVE_TRAVEL[: ].*terminal=1' "$f" | head -3 | cut -c1-420 | tr '
' '|');; *) ev=$(tail -1 "$f" | cut -c1-240);; esac; echo "EVIDENCE $ROW $(basename "$f"): $ev"; n=$((n+1)); }
done
echo "$out" | head -1
exit $rc
