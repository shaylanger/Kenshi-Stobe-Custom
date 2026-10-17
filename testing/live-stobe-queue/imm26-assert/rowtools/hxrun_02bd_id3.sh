#!/usr/bin/env bash
# hxrun_02bd_id3.sh (imm26-fix02bx): hxrun_02bd_id.sh unchanged except the assert dir = v3 (v3/assert_principle.py 02-bx skips an echo of the request and reads the reply to the player). New file; the id runner a list may use is not edited.
# hxrun_02bd.sh <02-bx|02-dx> <lane> [options]   (imm26-rr02) ONE call per row, same shape as hxrun.sh / hxrun_v2.sh: reload the base save (tr_reload) -> preflight -> go-row
#   attempt guard + timing log -> rd_02bx / rd_02dx (hxdefs_02bd.sh) -> verdict hxcheck_02bd.py (v2 assert_principle.py 02-bx / 02-dx) -> up to 6 EVIDENCE lines + ONE RESULT line.
#   Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 needs a fixer.   Writes bundles to <--out>/<ROW>/<label> (or the evidence dir).
#   Options: --save <save A>   (02-bx: Cind target, 02-dx: H-AFF +60)   --save2 <save B>   (02-bx: spawned control, 02-dx: H-AFF 0; default = --save)
#            --out DIR  --no-reload  --dry  --allow-retry "<why>"  --native  --faction F (02-bx control faction, default "Slave Traders")  --victim NPC (02-bx state_after, Malzin)
#            --spot "x y z"   Base saves: i3 kah-imm26-5090-hxA, i4 kah-imm26-i4-hx0, other lanes need --save (and should use two DIFFERENT fresh saves for --save2).
#   Env: see hxdefs_02bd.sh.  Selftest: bash rowtools/hx-selftest_02bd.sh.   Details: rowtools/README_02BD.md.
HX_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HX_HERE/../go-row.sh"
. "$HX_HERE/hxdefs.sh"
[ -f "$HX_HERE/hxdefs_a.sh" ] && . "$HX_HERE/hxdefs_a.sh"   # hxa02_prin_on/off/rows/md5, hxa_sq
. "$HX_HERE/hxdefs_02bd.sh"
. "$HX_HERE/hxdefs_02bd_id.sh"
export HX_ASSERT_DIR="${HX_ASSERT_DIR:-$(cd "$HX_HERE/../v3" && pwd)}"   # v3 asserters (imm26-fix02bx: 02-bx echo-aware first sentence; other rows = v2 logic)
PY="$HX_HERE/pywrap_02bd.sh"
hx_usage() { echo "usage: hxrun_02bd.sh <02-bx|02-dx> <lane: $(lt_lanes)> [--save A] [--save2 B] [--out DIR] [--no-reload] [--dry] [--allow-retry 'why'] [--native] [--faction F] [--victim NPC] [--spot 'x y z']" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export HX_SAVE="$2"; shift 2;; --save2) export HX_SAVE2="$2"; shift 2;; --out) export HX_OUT="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;; --native) export HX_NATIVE=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --faction) export HX02B_FACTION="$2"; shift 2;; --victim) export HX02B_VICTIM="$2"; shift 2;; --spot) export HX_SPOT="$2"; shift 2;;
  -h|--help) hx_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; hx_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { hx_usage; exit 2; }
norm="${ROW#IMM-}"
case " $HX02BD_ROWS " in *" $norm "*) ;; *) echo "RESULT $ROW SETUP-FAIL not a 02-bx/02-dx row (others: hxrun.sh / hxrun_v2.sh)"; exit 2;; esac
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
ROW_NPC="${ROW_NPC:-$HX_NPC_DEF}"; export ROW_NPC
FIRST="${HX_SAVE:-$(hxd_lane_save)}"
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  [ -n "$FIRST" ] || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL no base save known for lane $LANE (use --save S [--save2 S2])"; exit 2; }
  TRIP_SAVE="$FIRST" tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
  export HX_PRELOADED=1
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
n=0; for f in phases.txt target_npc.txt ctl_npc.txt spawn.txt profile_md5_original.txt profile_md5_restored.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && [ $n -lt 6 ] && { echo "EVIDENCE $ROW $f: $(tail -${HX_EVLINES:-5} "$LT_OUT/$ROW/$f" | tr '\n' ' ' | cut -c1-300)"; n=$((n+1)); }
done
echo "$out" | head -1
exit $rc
