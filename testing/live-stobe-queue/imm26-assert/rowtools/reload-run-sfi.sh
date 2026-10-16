#!/usr/bin/env bash
# reload-run-sfi.sh <26-d|26-dx|26-e> <lane> [options]   (imm26-sfI) copy of reload-run.sh for the Hunt resume rows on the hunt26a-scene ground (reloaddefs_sfi.sh: E-of-Hub teleport, goats
#   `at` + pinned + senses go/no-go, friend 60, apology, faction re-serial, offer->delivery->accept). Checker unchanged (reloadcheck_a.py via reload-py.sh). Same options, exit codes and the
#   one `RESULT` line as reload-run.sh; a bad scene is SETUP-FAIL. Extra options: --faction "<name>" (RW_FACTION; Nameless = player faction, NC17) --no-refaction --no-apology --goats N.
#   Offline: bash rowtools/reload-sfi-selftest.sh. Details: rowtools/README_RELOAD_SFI.md.
#   Options: --save <name> (ready save to reload first; i3 kah-imm26-5090-ready, i4 kah-imm26-i4-trip2, other lanes need --save)  --no-reload  --dry  --allow-retry "<why>"
#            --complete (26-d: wait for the hand-over, RW_COMPLETE=1)  --offer "<text>"  --accept "<text>"   (--spawn/--kind are accepted but ignored here: the goats are fixed by the scene)
RR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RR_HERE/../go-row.sh"
. "$RR_HERE/reloaddefs_a.sh"
. "$RR_HERE/reloaddefs_sfi.sh"   # imm26-sfI: overrides rd_26d / rd_26dx / rd_26e (hunt26a-scene ground)
PY="$RR_HERE/reload-py.sh"
export ROW_SETTLE="${ROW_SETTLE:-1}"   # accept must follow the delivered offer quickly (op8: > ~20 s = "not a workable option")
rr_usage() { echo "usage: reload-run.sh <ROW: 26-d 26-dx 26-e> <lane: $(lt_lanes)> [--save S] [--no-reload] [--dry] [--allow-retry 'why'] [--complete] [--spawn 'body'] [--offer T] [--accept T] [--kind K] [--alt P] [--faction F] [--no-refaction] [--no-apology] [--goats N]" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --save) export TRIP_SAVE="$2"; shift 2;; --alt) export TRIP_ALT="$2"; shift 2;; --dest) export TRIP_DEST="$2"; shift 2;; --gate) export TRIP_GATE="$2"; shift 2;;
  --faction) export RW_FACTION="$2"; shift 2;; --no-refaction) export RW_REFACTION=0; shift;; --no-apology) export RW_APOLOGY=0; shift;; --goats) export RW_GOATS="$2"; shift 2;;
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
case "$norm" in 26-d|26-dx|26-e) ;; *) echo "RESULT $ROW SETUP-FAIL not a hunt reload row (reload-run-sfi.sh handles 26-d 26-dx 26-e only; 26-f: reload-run-sfe.sh, others: reload-run.sh)"; exit 2;; esac
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
