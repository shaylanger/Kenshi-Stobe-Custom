#!/usr/bin/env bash
# rig-health.sh (WSL or Git Bash): ONE line about this rig for the <=120 s check-in when no batch is running
# (Shay 2026-10-08: the coordinator sat "waiting" on subagents with no waker, missed peer messages, and left the 5090 idle).
#   RIG BUSY kenshi=yes lock=<owner> inflight=<markers>          something runs: start the next wait
#   RIG IDLE kenshi=no lock=free idle_reason=<text|none>         5090 free: launch the next batch or record a reason
#   RIG IDLE-GAME 5090: ...                                       Kenshi open/lock held but every marked batch has DONE > 3 min (rig5090-state.ps1)
#   RIG STALL ...                                                 lock held / markers present but Kenshi is gone
# Use: sleep 120; bash tools/automation/rig-health.sh    (Bash run_in_background; restart it every time it wakes you)
# Markers: touch C:\KenshiTestRuns\inflight\<name> when starting a subagent / rig job / detached batch; delete when done.
set -u
R=/mnt/c/KenshiTestRuns; [ -d "$R" ] || R=/c/KenshiTestRuns
# Rig-runner alerts (rig-runner.ps1: a rig idle >= 2 min with an empty queue, a stuck/killed row, a dead batch) come first
for a in "$R"/ALERT-*.txt; do [ -f "$a" ] && { tr -d '\r' < "$a"; al=1; }; done; [ -n "${al:-}" ] && exit 1
if tasklist.exe </dev/null 2>/dev/null | grep -qi kenshi_x64; then k=yes; else k=no; fi
lock=free; [ -f "$R/game.lock" ] && lock=$(head -1 "$R/game.lock" | tr -d '\r')
mk=$(find "$R/inflight" -maxdepth 1 -type f -mmin -360 -printf '%f,' 2>/dev/null | sed 's/,$//'); mk=${mk:-none}
reason=none; [ -f "$R/rig5090.idle" ] && [ -n "$(find "$R/rig5090.idle" -mmin -60 2>/dev/null)" ] && reason=$(tr -d '\r\n' < "$R/rig5090.idle")
# 4080 (Shay 2026-10-10: it sat idle a whole day unnoticed): BUSY|IDLE|IDLE-OK|UNREACHABLE from rig4080-state.ps1 (cached 3 min)
r4=$(powershell.exe -NoProfile -File 'C:\KenshiModding\tools\automation\rig4080-state.ps1' </dev/null 2>/dev/null | tr -d '\r' | head -1 | tr ' ' '_'); r4=${r4:-unknown}
case "$r4" in IDLE_*|IDLE-GAME*) echo "RIG4080 IDLE ($r4): start a 4080 job now or record kenshi-ctl.ps1 idle4080 \"<reason>\""; exit 1;; esac
# Game slot really working? (Shay 2026-10-10: Kenshi open + lock + a marker pointing at a DONE batch read as BUSY for 5 min)
g=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\rig5090-state.ps1' </dev/null 2>/dev/null | tr -d '\r' | head -1)
case "$g" in IDLE-GAME*) echo "RIG IDLE-GAME 5090: ${g#IDLE-GAME } 4080=$r4"; exit 1;; esac
if [ "$k" = yes ]; then echo "RIG BUSY kenshi=yes lock=$lock inflight=$mk 4080=$r4"; exit 0; fi
if [ "$lock" != free ] || [ "$mk" != none ]; then echo "RIG STALL kenshi=no lock=$lock inflight=$mk 4080=$r4 (Kenshi gone while work is claimed: check the batch/agent, release or relaunch)"; exit 2; fi
echo "RIG IDLE kenshi=no lock=free idle_reason=$reason 4080=$r4"; [ "$reason" = none ] && exit 1 || exit 0
