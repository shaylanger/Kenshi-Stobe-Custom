#!/usr/bin/env bash
# reload-run.sh <ROW> <lane> [options]   ONE call per save+load RESUME row (set A): optional reload of the lane's ready save -> preflight -> go-row (row steps +
#   reloadcheck_a.py) -> `RECORDS` lines -> exactly ONE `RESULT <ROW> ...` line. Rows: 26-d 26-dx 26-e 26-f 24-c 23-e 27-a 08-e 20-d. Exit codes as go-row.sh
#   (0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 ROW-NEEDS-FIXER). Same lane rules as trip-run.sh (isolated lane, never Shay's live install). Details: rowtools/README_RELOAD_A.md.
#   Options: --save <name> (ready save to reload first; i3 kah-imm26-5090-ready, i4 kah-imm26-i4-trip2, other lanes need --save)  --no-reload  --dry  --allow-retry "<why>"
#            --complete (26-d/26-f: wait for the hand-over, RW_COMPLETE=1)  --spawn "<harness body>" (RW_SPAWN_CMD)  --offer "<text>"  --accept "<text>"  --kind Hunt|ClearGroup
#            --dest/--alt/--gate/--trap (trip knobs, 20-d uses --alt)
RR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RR_HERE/../go-row.sh"
. "$RR_HERE/reloaddefs_a.sh"
PY="$RR_HERE/reload-py.sh"
rr_usage() { echo "usage: reload-run.sh <ROW: 26-d 26-dx 26-e 26-f 24-c 23-e 27-a 08-e 20-d> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--complete] [--spawn 'body'] [--offer T] [--accept T] [--kind K] [--alt P]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --alt) export TRIP_ALT="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;; --gate) export TRIP_GATE="$2"; shift 2;;
  --trap) export TRIP_TRAP="$2"; shift 2;; --complete) export RW_COMPLETE=1; shift;; --spawn) export RW_SPAWN_CMD="$2"; shift 2;;
  --offer) export RW_OFFER="$2"; shift 2;; --accept) export RW_ACCEPT="$2"; shift 2;; --kind) export RW_KIND="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) rr_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; rr_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { rr_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
case "$norm" in 26-d|26-dx|26-e|26-f|24-c|23-e|27-a|08-e|20-d) ;; *) echo "RESULT $ROW SETUP-FAIL not a reload row of set A (see reload-run.sh --help)"; exit 2;; esac
declare -F "rd_${norm//-/}" >/dev/null || { echo "RESULT $ROW SETUP-FAIL row definition missing (reloaddefs_a.sh)"; exit 2; }
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in act_post.txt act_post_s3.txt agr_all.txt chase_post.txt fu_final.txt bg_post.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && { head -6 "$LT_OUT/$ROW/$f" | sed "s/^/RECORDS $ROW $f /"; break; }
done
echo "$out" | head -1
exit $rc
