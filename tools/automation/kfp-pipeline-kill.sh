#!/bin/bash
# kfp-pipeline-kill.sh <run dir> "<reason>" -- stop ONE kfp-pipeline run completely (WSL root): every process whose
# command line or environment names the run dir (pipeline copy, labnice wrapper, gate.sh, and the regress.sh / animlab
# children that only carry it in their env O=/T=/NS=), then appends "PIPELINE FAIL killed by build-line: <reason>" to its
# pipeline.log and removes its inflight marker. Matches <run>/... and <run> exactly, never <run>-x1 (a rerun).
# Why (2026-10-11): pkill -f "<run>/" left run-bl-1011-1802-x1's regress.sh orphans (env-only) holding lab slots, so the
# next run waited in labnice.
# Selftest: kfp-pipeline-kill.sh --selftest
set -u
match_pids() { local R=${1%/} p
  for p in $(ls /proc | grep -E '^[0-9]+$'); do [ "$p" = $$ ] && continue; [ "$p" = "$PPID" ] && continue
    { tr '\0' '\n' < /proc/$p/cmdline; tr '\0' '\n' < /proc/$p/environ; } 2>/dev/null | tr ' =' '\n\n' \
      | awk -v r="$R" '$0 == r || index($0, r "/") == 1 {f=1} END {exit !f}' || continue
    tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -q 'kfp-pipeline-kill\.sh' && continue   # this script's own subshells
    echo "$p"; done; }
if [ "${1:-}" = --selftest ]; then
  T=$(mktemp -d /tmp/kfpkill.XXXX); mkdir -p "$T/run-a" "$T/run-a-x1"
  O=$T/run-a/gate-all setsid sleep 300 & a=$!
  O=$T/run-a-x1/gate-all setsid sleep 301 & b=$!; sleep 0.3
  bash "$0" "$T/run-a" selftest > /dev/null; sleep 0.5
  ok=1; kill -0 $a 2>/dev/null && { echo "FAIL env-only child of run-a still alive"; ok=0; }
  kill -0 $b 2>/dev/null || { echo "FAIL run-a-x1 process was killed"; ok=0; }
  grep -q 'PIPELINE FAIL killed by build-line: selftest' "$T/run-a/pipeline.log" || { echo "FAIL no PIPELINE line"; ok=0; }
  kill $b 2>/dev/null; rm -rf "$T"; [ $ok = 1 ] && echo "SELFTEST PASS kfp-pipeline-kill" && exit 0; exit 1; fi
R=${1:?run dir}; R=${R%/}; WHY=${2:-killed by hand}
for round in 1 2 3; do ps=$(match_pids "$R"); [ -z "$ps" ] && break; kill -TERM $ps 2>/dev/null; sleep 2; done
ps=$(match_pids "$R"); [ -n "$ps" ] && { kill -KILL $ps 2>/dev/null; sleep 1; }
left=$(match_pids "$R" | wc -l)
mkdir -p "$R"; echo "PIPELINE FAIL killed by build-line: $WHY" >> "$R/pipeline.log"
rm -f "/mnt/c/KenshiTestRuns/inflight/kfp-pipeline-$(basename "$R")"
echo "kfp-pipeline-kill: $R stopped (left=$left)"
