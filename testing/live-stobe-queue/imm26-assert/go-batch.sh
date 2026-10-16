#!/usr/bin/env bash
# go-batch.sh [--fg] <lane> ROW1 ROW2 ...   run several rows on ONE lane as a detached job; one RESULT line per row in a results file.
#   Prints once: `BATCH started id=<id> rows=<n> results=<path>` and returns at once (use --fg to wait, e.g. in selftests).
#   Results file (append-only, one line per row, in order): <KenshiTestRuns>/<lane-dir>/batch/<id>/results.txt ; `DONE` file + `summary.txt`
#   (counts PASS/FAIL/SETUP-FAIL/GATED) when finished; per-row logs/evidence stay in rows/<ROW>/ (open it only for a FAIL, see its `excerpt`
#   = the RESULT text). If a row fails preflight because the lane is down the remaining rows are written as SETUP-FAIL without retries.
#   Rows whose last attempt FAILED are not re-run (PI-06): their results line is `ROW-NEEDS-FIXER <ROW> <lane> cause=...`; one reason for
#   all rows: --allow-retry "<reason>" (logged). See go-row.sh. Every row also appends to row-timing.log (PI-09).
#   Env KAH_AGENT_NAME: every finished row updates that agent's status `latest` (heartbeat) via go-row.sh.
#   Wait for it with: until [ -f <dir>/DONE ]; do sleep 20; done   (or event-wait.sh --batch <dir>)
GB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$GB_HERE/rowtools/lane.sh"
fg=""; child=""; allow=()
while :; do case "${1:-}" in
  --fg) fg=1; shift;;
  --child) child="$2"; shift 2;;
  --allow-retry) [ -n "${2:-}" ] || { echo "usage: --allow-retry needs a reason string" >&2; exit 2; }; allow=(--allow-retry "$2"); shift 2;;
  *) break;; esac; done
lane="${1:-}"; shift
[ -n "$lane" ] && [ $# -ge 1 ] || { echo "usage: go-batch.sh [--fg] [--allow-retry "<reason>"] <lane: $(lt_lanes)> ROW1 [ROW2 ...]" >&2; exit 2; }
lt_load "$lane" >/dev/null || exit 2
if [ -z "$child" ]; then
  id="b$(date +%Y%m%d-%H%M%S)-$$"; dir="$LT_BASE/$LT_DIR/batch/$id"; mkdir -p "$dir"; : > "$dir/results.txt"
  echo "$lane $*" > "$dir/rows.txt"
  if [ -n "$fg" ]; then bash "$GB_HERE/go-batch.sh" --child "$dir" "${allow[@]}" "$lane" "$@" > "$dir/batch.log" 2>&1
  else nohup bash "$GB_HERE/go-batch.sh" --child "$dir" "${allow[@]}" "$lane" "$@" > "$dir/batch.log" 2>&1 < /dev/null & disown 2>/dev/null; fi
  echo "BATCH started id=$id rows=$# results=$dir/results.txt"
  exit 0
fi
dir="$child"; down=""
for r in "$@"; do
  if [ -n "$down" ]; then echo "RESULT $r SETUP-FAIL skipped: $down" >> "$dir/results.txt"; continue; fi
  line=$(bash "$GB_HERE/go-row.sh" "${allow[@]}" "$r" "$lane" 2>>"$dir/batch.log" | tail -1)
  [ -n "$line" ] || line="RESULT $r SETUP-FAIL go-row.sh printed nothing (see $dir/batch.log)"
  echo "$line" >> "$dir/results.txt"
  case "$line" in *PREFLIGHT-FAIL*"down"*) down="lane down: $(echo "$line" | cut -c1-140)";; esac
done
{ for k in PASS FAIL SETUP-FAIL GATED; do echo "$k=$(grep -c "^RESULT [^ ]* $k" "$dir/results.txt")"; done; echo "NEEDS-FIXER=$(grep -c "^ROW-NEEDS-FIXER" "$dir/results.txt")"; } > "$dir/summary.txt"
touch "$dir/DONE"
