#!/usr/bin/env bash
# inflight-claims.sh [runs-dir]: names of inflight markers (touched < 6 h ago) that claim 5090 game work, one per line.
# Skips 4080-* markers (4080 work) and agent-name markers (a name that equals agents\<name>.status: written by agent-status.ps1 while
# the AGENT runs; it is work claimed for the waker rule, not a Kenshi batch, so "Kenshi gone" must not read it as a RIG STALL;
# a false stall happened 2026-10-15 with marker imm26-resume). Used by rig-health.sh. Selftest: agent-guard-selftest.ps1.
R=${1:-${KAH_RUNS:-/mnt/c/KenshiTestRuns}}; [ -d "$R" ] || R=/c/KenshiTestRuns
find "$R/inflight" -maxdepth 1 -type f -mmin -360 -printf '%f\n' 2>/dev/null | while IFS= read -r n; do
  case "$n" in 4080-*) continue;; esac
  [ -f "$R/agents/$n.status" ] && continue
  printf '%s\n' "$n"
done
