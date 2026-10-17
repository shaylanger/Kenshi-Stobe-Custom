#!/usr/bin/env bash
# reloadrun-b_fc.sh (imm26-sfFixC): reloadrun-b.sh + tripdefs_sffc.sh sourced last (19-e/19-a/19-f: prompt guard, third opener, deterministic PROPOSE fallback). reloadrun-b.sh is untouched; sffc_selftest.sh asserts this file = reloadrun-b.sh + that one line.
# reloadrun-b.sh <ROW> <lane> [options]   ONE call per save/load resume row of set B: 14-e 13-f 13-g 10-e 19-e 19-f (IMM- prefix optional).
#   Does: reload the lane's ready save (tr_reload, as trip-run.sh) -> preflight -> go-row (attempt guard + timing log) running the rd_ function of
#   reloaddefs_b.sh -> verdict by reloadcheck_b.py (via pywrap_b.sh; rowcheck.py/rowdefs.sh/go-row.sh are NOT edited) -> `EVIDENCE <ROW> ...` lines
#   (deal_*.txt / agr dumps, <= 6) and exactly ONE `RESULT <ROW> ...` line (or `ROW-NEEDS-FIXER ...`). Exit codes as go-row.sh: 0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 fixer.
#   Options: --save <name> (ready save for lanes other than 5090-i3/i4)  --no-reload  --dry  --allow-retry "<reason>"
#            --backdate <s> (14-e, default 540)  --n <reloads> (19-f, default 4)  --mode target|cap (19-f)  --cap <n> (19-f: setting STOBE_TRIP_RESUME_MAX_COUNT for the run)
#            --dest <town> (19-e/19-f, default Squin)  --wait <s> (19-e quiet control window, default 30)
# Details and the row -> command -> evidence table: rowtools/README_RELOAD_B.md.
RB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RB_HERE/../go-row.sh"
. "$RB_HERE/reloaddefs_b.sh"
. "$RB_HERE/tripdefs_sffc.sh"   # sfFixC: rd19_trip guard + fallback
PY="$RB_HERE/pywrap_b.sh"
rr_usage() { echo "usage: reloadrun-b.sh <14-e|13-f|13-g|10-e|19-e|19-f> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--backdate s] [--n k] [--mode target|cap] [--cap n] [--dest T] [--wait s]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  --backdate) export ROW_BACKDATE_S="$2"; shift 2;; --n) export ROW_19F_N="$2"; shift 2;; --mode) export ROW_19F_MODE="$2"; shift 2;;
  --cap) export ROW_19F_CAP="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;; --wait) export ROW_19E_QUIET_S="$2"; shift 2;;
  -h|--help) rr_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; rr_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { rr_usage; exit 2; }
case "${ROW#IMM-}" in 14-e|13-f|13-g|10-e|19-e|19-f) ;; *) echo "RESULT $ROW SETUP-FAIL not a set-B reload row (14-e 13-f 13-g 10-e 19-e 19-f)"; exit 2;; esac
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
n=0; for f in "$LT_OUT/$ROW"/deal_*.txt "$LT_OUT/$ROW"/probe_eval.json "$LT_OUT/$ROW"/agr_r*.txt "$LT_OUT/$ROW"/silent_poll.txt "$LT_OUT/$ROW"/effects_deal.txt; do
  [ -s "$f" ] && [ $n -lt 6 ] && { echo "EVIDENCE $ROW $(basename "$f"): $(tail -1 "$f" | cut -c1-240)"; n=$((n+1)); }
done
echo "$out" | head -1
exit $rc
