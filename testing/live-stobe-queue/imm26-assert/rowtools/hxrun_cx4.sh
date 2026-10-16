#!/usr/bin/env bash
# hxrun_cx4.sh 05-cx <lane> [options]   ONE call: 05-cx v2 (imm26-sfS; distinct NPC names, pinned Malzin/NPCs, conditional empty-roster hedge check, fixed roster helper, infonpc people evidence).
#   v3 (imm26-fix15bx05cx): keep-regex fix, Cind-near assert, infonpc purge (hxdefs_cx3.sh, still sourced first).
#   v4 (imm26-fix15bx05cx3): same options; hxdefs_cx4.sh (H sleeper KO'd + gated instead of `sleep`), verdict assert_principle_cx4.py via pywrap_cx4.sh/hxcheck_cx4.py (hedge vocabulary,
#   'if you meant just us, no' is not an alone claim), and the base save must EXIST (default per lane: hx4lib.sh hx4_lane_save; a missing save is a SETUP-FAIL 'SAVE-MISSING', never a silent load of the open world).
#   Same shape as hxrun.sh (reload the lane's base save -> preflight -> go-row attempt guard -> rd_05cx from hxdefs_cx4.sh -> verdict hxcheck_cx4.py/assert_principle_cx4.py 05-cx
#   -> up to 6 `EVIDENCE 05-cx ...` lines -> exactly ONE `RESULT 05-cx PASS|FAIL|SETUP-FAIL ...` line).  hxrun.sh / hxdefs_b.sh are NOT edited (a running operator may use them).
#   Options: --save <name> (base save, must exist; defaults: i3 kah-imm26-5090-ready, i4 kah-imm26-i4-hx0, i5 kah-imm26-i5)  --save2 <name>  --out <dir> (bundles to <dir>/05-cx/<label>, e.g. C:/KenshiTestRuns/imm26-5090-hx)
#            --no-reload  --dry  --allow-retry "<why>" (REQUIRED after a FAIL/SETUP-FAIL of 05-cx on the lane)  --native (ctxpush before every say)
#            --nspawn <n> (3)  --names "A B C D" (distinct names; 4th = the sleeper)  --faction <f> (Drifters)  --spot "x y z"  --no-pin
#   Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.  Selftest: rowtools/hx-selftest_cx4.sh.
HX4R_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HX4R_HERE/../go-row.sh"
. "$HX4R_HERE/hxdefs.sh"
. "$HX4R_HERE/hxdefs_b.sh"
. "$HX4R_HERE/hxdefs_cx3.sh"        # hx05_* helpers
. "$HX4R_HERE/hxdefs_cx4.sh"        # redefines hxd_lane_save hx05_samples rd_05cx (+ sources hx4lib.sh)
PY="$HX4R_HERE/pywrap_cx4.sh"
hx4_usage() { echo "usage: hxrun_cx4.sh 05-cx <lane: $(lt_lanes)> [--save S] [--save2 S] [--out DIR] [--no-reload] [--dry] [--allow-retry 'why'] [--native] [--nspawn N] [--names 'A B C D'] [--faction F] [--spot 'x y z'] [--no-pin]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export HX_SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;; --native) export HX_NATIVE=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --nspawn) export HX05_NSPAWN="$2"; shift 2;; --names) export HX05_NAMES="$2"; shift 2;; --faction) export HX05_FACTION="$2"; shift 2;;
  --spot) export HX_SPOT="$2"; shift 2;; --no-pin) export HX05_NOPIN=1; shift;;
  -h|--help) hx4_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; hx4_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { hx4_usage; exit 2; }
norm="${ROW#IMM-}"
[ "$norm" = 05-cx ] || { echo "RESULT $ROW SETUP-FAIL hxrun_cx4.sh runs 05-cx only"; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
ROW_NPC="${ROW_NPC:-$HX_NPC_DEF}"; export ROW_NPC
FIRST="${HX_SAVE:-$(hxd_lane_save)}"; export HX_SAVE="$FIRST"
for _sv in "$FIRST" "${HX_SAVE2:-}"; do   # a missing save makes `stobe-auto load` keep the loaded world silently (5090-i3 had no kah-imm26-5090-hxA): fail loudly instead
  [ -n "$_sv" ] || continue
  hx4_save_check "$_sv" || { echo "RESULT $ROW SETUP-FAIL SAVE-MISSING $HX4_WHY"; exit 2; }
  [ -z "$HX4_WHY" ] || echo "NOTE $ROW $HX4_WHY" >&2
done
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
