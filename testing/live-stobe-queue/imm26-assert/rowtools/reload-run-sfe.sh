#!/usr/bin/env bash
# reload-run-sfe.sh <24-c|26-f> <lane> [options]   (imm26-sfE2) copy of reload-run.sh for the two corrected recipes in reloaddefs_sfe.sh (rd_24c SEEDED resume leg, rd_26f ClearGroup
#   one-call) + reloadcheck_sfe.py via reload-py-sfe.sh. Same options, exit codes, one `RESULT` line as reload-run.sh; every 24-c RESULT starts with SEEDED (row stays PARTIAL).
#   Offline: bash rowtools/reload-sfe-selftest.sh. Details: rowtools/README_RELOAD_SFE.md.
#   Options: --save <name> (ready save to reload first; i3 kah-imm26-5090-ready, i4 kah-imm26-i4-trip2, other lanes need --save)  --no-reload  --dry  --allow-retry "<why>"
#            --complete (26-d/26-f: wait for the hand-over, RW_COMPLETE=1)  --spawn "<harness body>" (RW_SPAWN_CMD)  --offer "<text>"  --accept "<text>"  --kind Hunt|ClearGroup
#            --dest/--alt/--gate/--trap (trip knobs, 20-d uses --alt)
RR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RR_HERE/../go-row.sh"
. "$RR_HERE/reloaddefs_a.sh"
. "$RR_HERE/reloaddefs_sfe.sh"   # imm26-sfE2: overrides rd_24c (SEEDED resume recipe) and rd_26f (ClearGroup one-call)
PY="$RR_HERE/reload-py-sfe.sh"
rr_usage() { echo "usage: reload-run.sh <ROW: 24-c 26-f> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--complete] [--spawn 'body'] [--offer T] [--accept T] [--kind K] [--alt P]" >&2; }
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
case "$norm" in 26-f|24-c) ;; *) echo "RESULT $ROW SETUP-FAIL not a reload row of set A (reload-run-sfe.sh handles 24-c and 26-f only; others: reload-run.sh)"; exit 2;; esac
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
