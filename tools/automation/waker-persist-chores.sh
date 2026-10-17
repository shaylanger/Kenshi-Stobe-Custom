#!/usr/bin/env bash
# waker-persist-chores.sh (Shay 2026-10-16: "take the model out of the mechanical wake-ups")   WSL.
#   waker-persist-chores.sh watch [same options as waker-persist.sh watch]
# Hand THIS to the Monitor tool instead of `waker-persist.sh watch`. It is waker-persist.sh (UNCHANGED: daemon, events.log, quiet filter, backstop)
# piped through coord-chores.ps1 stream: deterministic events (DONE statuses, dups, wind-down lane alerts, sweep noise, ...) are handled by
# script at zero tokens and only a quiet 'CHORES: n auto (...) | ATTENTION: m' line + the events that need judgment are printed (each printed
# line = one Monitor notification = one model wake). An auto-only period prints nothing (one liveness line per hour). Rules: coord-chores.rules.json.
# Swap (one step, no waker downtime that matters): stop the Monitor running `waker-persist.sh watch`, then start a Monitor on
#   MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/waker-persist-chores.sh watch
# (the daemon keeps running across the swap; add --replay N to re-show old lines, they are deduped by hash). Stop = stop the Monitor.
# Env: KAH_RUNS_DIR (Windows path, default C:\KenshiTestRuns) is passed to coord-chores.ps1.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WDIR="$(wslpath -w "$DIR" 2>/dev/null || echo 'C:\KenshiModding\tools\automation')"
PS="$(command -v powershell.exe || echo /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)"
CMD=${1:-watch}
case "$CMD" in
  watch)
    shift
    bash "$DIR/waker-persist.sh" watch "$@" | "$PS" -NoProfile -ExecutionPolicy Bypass -File "$WDIR\coord-chores.ps1" stream
    ;;
  status)
    "$PS" -NoProfile -ExecutionPolicy Bypass -File "$WDIR\coord-chores.ps1" status
    ;;
  *)
    echo "usage: waker-persist-chores.sh watch [waker-persist.sh watch options] | status" >&2; exit 2;;
esac
