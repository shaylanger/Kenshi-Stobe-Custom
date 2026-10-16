#!/usr/bin/env bash
# pilot-mark.sh <agent> <ROW> <START|PASS|FAIL|SETUP-FAIL|GATED|ESCALATE> ["<evidence>"] [--evidence-file <path|dir>] [--lane 5090-i4] [--next "<step>"] [--task "<task>"] [--no-status]
# SHADOW verdict marking for the Haiku-vs-Sonnet operator pilot (replaces claims mkdir / mark-row.py / status-mark.sh / setupfail for the pilot operator).
# Logic and rules: pilot-mark.py (PASS/FAIL only if the evidence file holds the matching `RESULT <row> PASS|FAIL` checker line; anything else = ESCALATE
# -> inbox\coordinator\<ts>-pilot-escalate-<row>.msg and the operator stops on that row). Ledger: C:\KenshiTestRuns\pilot\haiku-i4\verdicts.csv.
# Then ONE agent-status.ps1 update (task text = line 2 of agents\<agent>.status unless --task). Never edits TESTS, claims, tickets; never commits.
# Exit: 0 accepted/started, 2 usage, 3 refused (checker disagrees), 4 escalated / row closed (do not retry). Env: KAH_RUNS_DIR KAH_PILOT_DIR PILOT_MODEL.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
[ $# -ge 3 ] || { sed -n 2,2p "$0" | cut -c1-260; exit 2; }
AGENT="$1"; ROW="$2"; V="$(printf '%s' "$3" | tr a-z A-Z)"; ARGS=("$@"); NEXT=""; TASK=""; DO_STATUS=1
set -- "${ARGS[@]:3}"
while [ $# -gt 0 ]; do case "$1" in --next) NEXT="$2"; shift 2;; --task) TASK="$2"; shift 2;; --no-status) DO_STATUS=0; shift;; *) shift;; esac; done
OUT="$("$PY" -I "$HERE/pilot-mark.py" "${ARGS[@]}" 2>&1)"; RC=$?
echo "$OUT" | cut -c1-700
RUNS="${KAH_RUNS_DIR:-}"; if [ -z "$RUNS" ]; then for c in /c/KenshiTestRuns /mnt/c/KenshiTestRuns; do [ -d "$c" ] && RUNS="$c" && break; done; fi
if [ $DO_STATUS = 1 ] && [ -n "$RUNS" ]; then
  SF="$RUNS/agents/$AGENT.status"
  [ -z "$TASK" ] && [ -f "$SF" ] && TASK="$(sed -n 2p "$SF" | sed 's/^task: \{0,1\}//')"
  if [ -n "$TASK" ]; then
    SUM="$(printf '%s' "$OUT" | head -1 | tr '\n\r' '  ' | cut -c1-200)"
    PSF="$HERE/agent-status.ps1"; command -v cygpath >/dev/null 2>&1 && PSF="$(cygpath -w "$PSF")"; command -v wslpath >/dev/null 2>&1 && PSF="$(wslpath -w "$PSF")"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSF" "$AGENT" RUNNING "$TASK" "$ROW $V rc=$RC: $SUM" "$SUM" "${NEXT:-next row of rows-i4.txt}" >/dev/null 2>&1 \
      && echo "status: $AGENT RUNNING ($ROW $V)" || echo "status: FAILED (agent-status.ps1)"
  else echo "status: SKIPPED (no task line in $SF; pass --task)"; fi
fi
exit $RC
