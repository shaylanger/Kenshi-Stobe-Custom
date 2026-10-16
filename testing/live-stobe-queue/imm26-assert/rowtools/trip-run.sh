#!/usr/bin/env bash
# trip-run.sh <ROW> <lane> [options]   ONE call per trip-family row: reload the ready save -> preflight -> go-row (row steps + rowcheck) ->
#   `AGREEMENTS` lines + the RESULT line.  Rows: 13-b 19-a 20-a 20-b 23-a 23-b 23-c 23-d 24-a 24-b (any ported row works; 13-b also via ko13b.sh).
#   Does: tr_reload (load $save, wait for the world, Shay HOLD, speed 0.5, NPC to Shay, NPC NULL_TASK; never IDLE) -> pf_run (PLAYER_NAME, deals,
#   dist<80, isolation) -> gr_main --no-preflight (attempt guard + timing log of go-row apply) which runs the row: db clean (travel_agreement,
#   region_plan, situated_event, situated_remark_claim), haff NPC->Shay 60 platonic, quiet scene, propose, accept, teleport to the gate with Shay
#   following, arrival ctxpush+say, agreement rows, rowcheck.
#   Options: --dest <town> (Squin)  --alt <other place> (20-a)  --save <name>  --gate "x y z"  --no-reload  --dry (KAH_ROW_DRY)
#            --allow-retry "<reason>" (go-row override after a FAIL)  --accept "<text>"  --trap "x y z" (20-b real path failure)
#   Stdout: up to 6 `AGREEMENTS <ROW> rowid status phase reason released destination` lines, then exactly ONE `RESULT <ROW> ...` line (or the
#   go-row `ROW-NEEDS-FIXER ...` line); exit codes as go-row.sh (0 PASS 1 FAIL 2 SETUP-FAIL 3 GATED 4 needs fixer). Details: rowtools/README_TRIP.md.
TR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TR_HERE/../go-row.sh"
tr_usage() { echo "usage: trip-run.sh <ROW> <lane: $(lt_lanes)> [--dest T] [--alt P] [--save S] [--gate 'x y z'] [--no-reload] [--dry] [--allow-retry 'why'] [--accept 'text'] [--trap 'x y z']" >&2; }
ROW=""; LANE=""; RELOAD=1; ALLOW=()
while [ $# -gt 0 ]; do case "$1" in
  --dest) export TRIP_DEST="$2"; shift 2;; --alt) export TRIP_ALT="$2"; shift 2;; --save) export TRIP_SAVE="$2"; shift 2;;
  --gate) export TRIP_GATE="$2"; shift 2;; --accept) export TRIP_ACCEPT="$2"; shift 2;; --trap) export TRIP_TRAP="$2"; shift 2;;
  --no-reload) RELOAD=0; shift;; --dry) export KAH_ROW_DRY=1; shift;;
  --allow-retry) ALLOW=(--allow-retry "$2"); shift 2;;
  -h|--help) tr_usage; exit 0;;
  *) if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$LANE" ]; then LANE="$1"; else echo "unexpected argument '$1'" >&2; tr_usage; exit 2; fi; shift;;
esac; done
[ -n "$ROW" ] && [ -n "$LANE" ] || { tr_usage; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RESULT $ROW SETUP-FAIL PREFLIGHT-FAIL unknown lane '$LANE'"; exit 2; }
tr_cfg; export ROW_NPC; norm="${ROW#IMM-}"
if ! declare -F "rd_${norm//-/}" >/dev/null; then echo "RESULT $ROW SETUP-FAIL row not ported to go-row.sh"; exit 2; fi
mkdir -p "$LT_OUT"; RLOG="$LT_OUT/$ROW.reload.log"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
if [ "$RELOAD" = 1 ] && [ -z "${KAH_ROW_DRY:-}" ]; then
  tr_reload > "$RLOG" 2>&1 || { echo "RESULT $ROW SETUP-FAIL RELOAD-FAIL $(tail -1 "$RLOG" | cut -c1-200)"; exit 2; }
fi
pf=$(pf_run "$LANE" "$ROW_NPC" 2>&1); prc=$?
if [ $prc != 0 ]; then echo "RESULT $ROW SETUP-FAIL $(echo "$pf" | grep -m1 PREFLIGHT-FAIL || echo "PREFLIGHT-FAIL $pf" | head -1)"; exit 2; fi
out=$(gr_main --no-preflight "${ALLOW[@]}" "$ROW" "$LANE"); rc=$?
for f in agr_final.txt agr_after.txt agr_trip.txt; do
  [ -s "$LT_OUT/$ROW/$f" ] && { head -6 "$LT_OUT/$ROW/$f" | sed "s/^/AGREEMENTS $ROW /"; break; }
done
echo "$out" | head -1
exit $rc
