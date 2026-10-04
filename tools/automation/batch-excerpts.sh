#!/usr/bin/env bash
# batch-excerpts.sh <out-dir> <test-name> (WSL): writes <out-dir>/excerpts/<test-name>.txt, a short excerpt of
# what happened during one failed batch test, so the coordinator never has to open the full logs:
#   - the test's own output: VERDICT/RESULT/error lines + its last 15 lines
#   - stobe.log, KenshiFP.log, harness.log, stobeserver.log, php_error.log: only the bytes written while the test
#     ran (offsets recorded by run-batch.sh in <out-dir>/ranges.tsv), filtered to error/warning/goal/deal lines,
#     last 25 per log (with the total count, so you know when it was cut)
# Prints the excerpt path. run-batch.sh calls it for every failed test; it can also be run by hand afterwards.
set -u
O="${1:?usage: batch-excerpts.sh <out-dir> <test-name>}"; N="${2:?test name}"
R="$O/ranges.tsv"; X="$O/excerpts"; mkdir -p "$X"; E="$X/$N.txt"
row=$(awk -F'\t' -v n="$N" '$1 == n' "$R" 2>/dev/null | tail -1)
[ -n "$row" ] || { echo "no range for '$N' in $R" >&2; exit 1; }

# log name | path | filter
LOGS="stobe|/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log|ERROR|Error|WARN|FAIL|BLOCK|REFUS|CANCEL|xception|crash|goal|deal
kenshifp|/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log|ERROR|Error|WARN|FAIL|BLOCK|xception|crash|goal
harness|/mnt/d/Steam/steamapps/common/Kenshi/mods/AutomationHarness/harness.log|ERROR|Error|error|WARN|FAIL|xception
server|/var/www/html/StobeServer/log/stobeserver.log|ERROR|WARN|Fatal|xception|guard|refus|BLOCK|FAIL
php|/var/www/html/StobeServer/log/php_error.log|."
# routine lines that match the filters but never explain a failure
NOISE='Unhandled event type stored only'

{
  echo "== $N  ($(awk -F'\t' '{print $2}' <<<"$row"))"
  out="$O/$N.txt"
  if [ -f "$out" ]; then
    echo "-- test output ($out): verdict/error lines"
    grep -a -E '^(RESULT|VERDICT)|ERROR|FAIL|ALERT|xception|timed out|no answer' "$out" | tail -20 | cut -c1-300
    echo "-- test output: last 15 lines"
    tail -15 "$out" | cut -c1-300
  fi
  i=3   # ranges.tsv: name, label, then start/end byte offsets per log, in LOGS order
  while IFS='|' read -r name path filter; do
    s=$(awk -F'\t' -v c=$i '{print $c}' <<<"$row"); e=$(awk -F'\t' -v c=$((i + 1)) '{print $c}' <<<"$row"); i=$((i + 2))
    [ -f "$path" ] && [ -n "$s" ] && [ -n "$e" ] || continue
    [ "$e" -lt "$s" ] && s=0          # log rotated/reset during the test: take everything up to the end mark
    [ "$e" -gt "$s" ] || continue
    hits=$(tail -c +"$((s + 1))" "$path" | head -c "$((e - s))" | grep -a -E "$filter" | grep -a -v -E "$NOISE")
    n=$(printf '%s' "$hits" | grep -c .)
    [ "$n" -gt 0 ] || continue
    echo "-- $name ($n matching lines while the test ran, last 25)"
    printf '%s\n' "$hits" | tail -25 | cut -c1-300
  done <<<"$LOGS"
} > "$E"
echo "$E"
