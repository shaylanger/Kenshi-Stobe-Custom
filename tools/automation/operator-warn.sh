#!/bin/bash
# operator-warn.sh: thin WSL/Git-Bash wrapper around operator-warn.ps1 (lane-operator WARN-120k detector).
# Prints one line per NEW warn ("OPERATOR WARN <name> lane <lane> successor=<new> | brief: ... | prompt: ... | register: ..."),
# nothing otherwise; de-duplicated by <runs>\operator-warn.state.json. Cheap pre-check: no powershell start unless a
# <runs>/agents/*.warn marker is newer than the state file. Usage: operator-warn.sh [--force] [operator-warn.ps1 args]
# For event-wait.sh / event-stream.sh: call it in the poll loop; a non-empty output is an URGENT event.
# event-wait.sh hook (insert before the "# BACKSTOP: nothing else" block; applied at a waker restart, never mid-run):
#   ow=$(KAH_RUNS="$R" bash "$HERE/operator-warn.sh" 2>/dev/null)
#   if [ -n "$ow" ]; then wake "EVENT $(printf '%s\n' "$ow" | head -3 | tr '\n' ' ')"; fi
R=${KAH_RUNS:-/mnt/c/KenshiTestRuns}
HERE=$(cd "$(dirname "$0")" && pwd)
if [ "${1:-}" = --force ]; then shift; else
  st="$R/operator-warn.state.json"
  if [ -f "$st" ]; then [ -n "$(find "$R/agents" -maxdepth 1 -name '*.warn' -newer "$st" 2>/dev/null | head -1)" ] || exit 0
  else ls "$R"/agents/*.warn >/dev/null 2>&1 || exit 0; fi
fi
ps1=$(wslpath -w "$HERE/operator-warn.ps1" 2>/dev/null || cygpath -w "$HERE/operator-warn.ps1" 2>/dev/null || echo 'C:\KenshiModding\tools\automation\operator-warn.ps1')
timeout 60 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" "$@" < /dev/null | tr -d '\r'
