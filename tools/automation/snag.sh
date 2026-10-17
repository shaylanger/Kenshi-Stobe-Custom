#!/usr/bin/env bash
# snag.sh (PI-49): bash twin of snag.ps1 for lane scripts (no PowerShell start-up).
#   bash snag.sh <operator> <script:line> "<symptom>" "<workaround>"
# Appends: SNAG <script:line> op=<operator> <symptom> | workaround: <workaround>   to <runs>/snags/snags.log
# Runs dir: $KAH_RUNS_DIR (unix path) else /mnt/c/KenshiTestRuns (WSL) or /c/KenshiTestRuns (Git Bash). Exit 2 on bad usage, never writes then.
op=${1:-}; sl=${2:-}; sym=${3:-}; wk=${4:-}
clean() { printf '%s' "$1" | tr '\r\n\t|' '   /' | sed -e 's/^ *//' -e 's/ *$//' | cut -c1-"$2"; }
op=$(clean "$op" 40 | tr ' ' '_'); sl=$(clean "$sl" 80 | tr -d ' '); sym=$(clean "$sym" 200); wk=$(clean "$wk" 200)
[ -n "$wk" ] || wk=none
if [ -z "$op" ] || [ -z "$sym" ] || ! printf '%s' "$sl" | grep -Eq '^[^:[:space:]]+:[^:[:space:]]+$'; then
  echo 'usage: snag.sh <operator> <script:line> "<symptom>" "<workaround>"  (script:line like hxdefs.sh:30)' >&2; exit 2
fi
runs=${KAH_RUNS_DIR:-}
if [ -z "$runs" ]; then if [ -d /mnt/c/KenshiTestRuns ]; then runs=/mnt/c/KenshiTestRuns; else runs=/c/KenshiTestRuns; fi; fi
mkdir -p "$runs/snags" 2>/dev/null
printf 'SNAG %s op=%s %s | workaround: %s\n' "$sl" "$op" "$sym" "$wk" >> "$runs/snags/snags.log" && echo "snag recorded: $sl by $op"
