#!/usr/bin/env bash
# rig-health.sh (WSL or Git Bash): ONE line about this rig for the <=120 s check-in when no batch is running
# (Shay 2026-10-08: the coordinator sat "waiting" on subagents with no waker, missed peer messages, and left the 5090 idle).
#   RIG BUSY kenshi=yes lock=<owner> inflight=<markers>          something runs: start the next wait
#   RIG IDLE kenshi=no lock=free idle_reason=<text|none>         5090 free: launch the next batch or record a reason
#   RIG IDLE-GAME 5090: ...                                       Kenshi open/lock held but every marked batch has DONE > 3 min (rig5090-state.ps1)
#   RIG STALL ...                                                 lock held / markers present but Kenshi is gone
#   RIG STALL <5090|4080>: <why> held <n> min ...                 a rig-runner stuck condition (harness silent, game time
#                                                                 frozen, ...) held >= max(limit, 5 min), even if the row still writes
# Use: sleep 120; bash tools/automation/rig-health.sh    (Bash run_in_background; restart it every time it wakes you)
# Markers: touch C:\KenshiTestRuns\inflight\<name> when starting a subagent / rig job / detached batch; delete when done.
set -u
R=/mnt/c/KenshiTestRuns; [ -d "$R" ] || R=/c/KenshiTestRuns
# Always-on TDR watch (m103 2026-10-11: two 5090 nvlddmkm 153 at 16:59 raised no alert, no batch was running): new GPU
# driver events on either rig since the last check -> ALERT-<rig>-tdr.txt + tdr-<time>-<rig>-evidence\ (tdr-watch.ps1)
timeout 90 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\tdr-watch.ps1' </dev/null >/dev/null 2>&1
# WSL GPU-PV allocation failures (dmesg dxgkio_create_allocation / establish_gpadl: TDR/BSOD precursor, gpu-native
# 2026-10-11): one DXG-WARN line before the RIG line when new ones appeared (dxgerr-scan.sh); a warning only, never a stop
timeout 30 bash "$(dirname "$0")/dxgerr-scan.sh" check 2>/dev/null
# Rig-runner alerts (rig-runner.ps1: a rig idle >= 2 min with an empty queue, a stuck/killed row, a dead batch) come first
for a in "$R"/ALERT-*.txt; do [ -f "$a" ] && { tr -d '\r' < "$a"; al=1; }; done; [ -n "${al:-}" ] && exit 1
# Rig-runner state (both rigs' loops run here): a stuck condition held >= max(limit, 5 min) = STALL even while the row keeps
# writing its log (2026-10-11 4080 R11: Kenshi frozen 12+ min read as RIG BUSY). Line: "HH:mm running ... COND(<held>m/<lim>m): <why>"
for s in "$R"/runner/5090.state "$R"/runner/4080.state; do
  [ -n "$(find "$s" -mmin -5 2>/dev/null)" ] || continue
  l=$(tail -1 "$s" | tr -d '\r')
  if [[ $l =~ COND\(([0-9]+)m/([0-9]+)m\):\ (.*)$ ]]; then
    h=${BASH_REMATCH[1]}; lim=${BASH_REMATCH[2]}; [ "$lim" -lt 5 ] && lim=5
    [ "$h" -ge "$lim" ] && { echo "RIG STALL $(basename "$s" .state): ${BASH_REMATCH[3]} held $h min (runner: ${l#* })"; exit 2; }
  fi
done
# ONE powershell.exe for the Kenshi check + both rig states (res-wait 2026-10-10: was tasklist.exe + 2 powershell.exe per call)
st=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'if (Get-Process kenshi_x64 -EA 0 | ? { $_.Path -notlike "D:\KenshiInst\*" }) { "K yes" } else { "K no" }; "4 " + [string](& "C:\KenshiModding\tools\automation\rig4080-state.ps1" 2>$null | Select-Object -First 1); "5 " + [string](& "C:\KenshiModding\tools\automation\rig5090-state.ps1" 2>$null | Select-Object -First 1)' </dev/null 2>/dev/null | tr -d '\r')
k=$(sed -n 's/^K //p' <<<"$st"); k=${k:-no}
lock=free; [ -f "$R/game.lock" ] && lock=$(head -1 "$R/game.lock" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
mk=$(find "$R/inflight" -maxdepth 1 -type f -mmin -360 -printf '%f,' 2>/dev/null | sed 's/,$//'); mk=${mk:-none}
reason=none; [ -f "$R/rig5090.idle" ] && [ -n "$(find "$R/rig5090.idle" -mmin -60 2>/dev/null)" ] && reason=$(tr -d '\r\n' < "$R/rig5090.idle")
# 4080 (Shay 2026-10-10: it sat idle a whole day unnoticed): BUSY|IDLE|IDLE-OK|UNREACHABLE from rig4080-state.ps1 (cached 3 min)
r4=$(sed -n 's/^4 //p' <<<"$st" | head -1 | tr ' ' '_'); r4=${r4:-unknown}
case "$r4" in IDLE_*|IDLE-GAME*) echo "RIG4080 IDLE ($r4): start a 4080 job now or record kenshi-ctl.ps1 idle4080 \"<reason>\""; exit 1;; esac
# Game slot really working? (Shay 2026-10-10: Kenshi open + lock + a marker pointing at a DONE batch read as BUSY for 5 min)
g=$(sed -n 's/^5 //p' <<<"$st" | head -1)
case "$g" in IDLE-GAME*) echo "RIG IDLE-GAME 5090: ${g#IDLE-GAME } 4080=$r4"; exit 1;; esac
if [ "$k" = yes ]; then echo "RIG BUSY kenshi=yes lock=$lock inflight=$mk 4080=$r4"; exit 0; fi
# 5090 parked on purpose (kenshi-ctl.ps1 idle, e.g. the 2026-10-11 BSOD) + lock free: markers are lab/4080 work, not a stall
if [ "$lock" = free ] && [ "$reason" != none ]; then echo "RIG IDLE kenshi=no lock=free idle_reason=$reason inflight=$mk 4080=$r4"; exit 0; fi
# 4080-* markers are 4080 work (2026-10-15: 4080-imm26 read as a 5090 stall with the 5090 held free on Shay's order); agent-name
# markers (agents\<name>.status exists) count as work for the waker rule but are no Kenshi-gone stall (inflight-claims.sh)
mk5=$(bash "$(dirname "$0")/inflight-claims.sh" "$R" | paste -sd, -); mk5=${mk5:-none}
if [ "$lock" != free ] || [ "$mk5" != none ]; then echo "RIG STALL kenshi=no lock=$lock inflight=$mk 4080=$r4 (Kenshi gone while work is claimed: check the batch/agent, release or relaunch)"; exit 2; fi
# rig-runner's own "no changed work" (filler unchanged since its last PASS, nothing real queued) = allowed idle, not a block
case "$reason" in "no changed work"*) echo "RIG IDLE-OK no changed work (rig-runner) 4080=$r4"; exit 0;; esac
echo "RIG IDLE kenshi=no lock=free idle_reason=$reason 4080=$r4"; [ "$reason" = none ] && exit 1 || exit 0
