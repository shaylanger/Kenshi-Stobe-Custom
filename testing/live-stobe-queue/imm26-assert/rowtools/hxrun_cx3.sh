#!/usr/bin/env bash
# hxrun_cx3.sh 05-cx <lane> [options]   ONE call: 05-cx v2 (imm26-sfS; distinct NPC names, pinned Malzin/NPCs, conditional empty-roster hedge check, fixed roster helper, infonpc people evidence).
#   v3 (imm26-fix15bx05cx): same options; runs hxdefs_cx3.sh (keep-regex fix, Cind-near assert, infonpc purge). Selftest: rowtools/hx-selftest_cx3.sh.
#   Same shape as hxrun.sh (reload the lane's base save -> preflight -> go-row attempt guard -> rd_05cx from hxdefs_cx3.sh -> verdict hxcheck_b.py/assert_principle.py 05-cx, unchanged
#   -> up to 6 `EVIDENCE 05-cx ...` lines -> exactly ONE `RESULT 05-cx PASS|FAIL|SETUP-FAIL ...` line).  hxrun.sh / hxdefs_b.sh are NOT edited (a running operator may use them).
#   Options: --save <name> (base save; i3 kah-imm26-5090-hxA, i4 kah-imm26-i4-hx0)  --save2 <name>  --out <dir> (bundles to <dir>/05-cx/<label>, e.g. C:/KenshiTestRuns/imm26-5090-hx)
#            --no-reload  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of 05-cx on the lane)  --native (ctxpush before every say)
#            --nspawn <n> (3)  --names "A B C D" (distinct names; 4th = the sleeper)  --faction <f> (Drifters)  --spot "x y z"  --no-pin
#   Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.  Selftest: rowtools/hx-selftest_cx3.sh.
HX3R_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HX3R_HERE/../go-row.sh"
. "$HX3R_HERE/hxdefs.sh"
. "$HX3R_HERE/hxdefs_b.sh"
. "$HX3R_HERE/hxdefs_cx3.sh"        # redefines hx05_* and rd_05cx
PY="$HX3R_HERE/pywrap_hx.sh"
hx3_usage() { echo "usage: hxrun_cx3.sh 05-cx <lane: $(lt_lanes)> [--save S] [--save2 S] [--out DIR] [--no-reload] [--dry] [--allow-retry 'why'] [--native] [--nspawn N] [--names 'A B C D'] [--faction F] [--spot 'x y z'] [--no-pin]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export HX_SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;; --native) export HX_NATIVE=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --nspawn) export HX05_NSPAWN="$2"; shift 2;; --names) export HX05_NAMES="$2"; shift 2;; --faction) export HX05_FACTION="$2"; shift 2;;
  --spot) export HX_SPOT="$2"; shift 2;; --no-pin) export HX05_NOPIN=1; shift;;
  -h|--help) hx3_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; hx3_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { hx3_usage; exit 2; }
norm="${ROW#IMM-}"
[ "$norm" = 05-cx ] || { echo "RESULT $ROW SETUP-FAIL hxrun_cx3.sh runs 05-cx only"; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
ROW_NPC="${ROW_NPC:-$HX_NPC_DEF}"; export ROW_NPC
FIRST="${HX_SAVE:-$(hxd_lane_save)}"
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  [ -n "$FIRST" ] || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL no base save known for lane $LANE (use --save S)"; exit 2; }
  TRIP_SAVE="$FIRST" tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
  export HX_PRELOADED=1
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
HXD_SHOW="${HX_OUT:+$HX_OUT/$ROW}"; HXD_SHOW="${HXD_SHOW:-$LT_OUT/$ROW}"
n=0; for f in phases.txt names.txt pin.txt spawn.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && [ $n -lt 4 ] && { echo "EVIDENCE $ROW $f: $(tail -5 "$LT_OUT/$ROW/$f" | tr '\n' ' ' | cut -c1-300)"; n=$((n+1)); }
done
for f in scene_E_names.txt scene_H_names.txt scene_N_names.txt scene_E_native.txt scene_H_native.txt scene_N_native.txt; do
  [ -s "$HXD_SHOW/$f" ] && echo "EVIDENCE $ROW $f: $(tr '\n' ' ' < "$HXD_SHOW/$f" | cut -c1-200)"
done
echo "$out" | head -1
exit $rc
