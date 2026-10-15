#!/usr/bin/env bash
# event-wait.sh [--me <name>] [--batch <out-dir>] [--backstop <sec>] [--poll <sec>] [--no-health]   (WSL; start it in the background)
# Event-driven wait (Shay 2026-10-14; replaces the fixed 2-minute check-in, which woke the coordinator for every HEALTH OK).
# The script ends, and so wakes the session, only when one of these happens:
#   INBOX     a file appears in C:\KenshiTestRuns\inbox\<me>\ (a sender drops it next to its SendMessage); the wait prints it and moves it to delivered\ so a re-armed wait does not wake again on the same file
#             QUIET FILTER: an 'AGENT STALL <n>' / 'AGENT ORPHANED <n>' message (agent-host monitor, possibly an older daemon) is re-checked with agent-rollcall.ps1 first:
#             process alive (STALL) AND newest of status/log/outputs-dir evidence < EW_STALL_FRESH_MIN (default 10 min), or the agent is no longer RUNNING => moved to delivered/suppressed/, no wake.
#             DEAD / KILLED / WALL-CLOCK / FAILED / DONE / STOPPED / questions / peer messages always wake. Fails open. Test seam: EW_ROLLCALL_CMD (command printing ROLLCALL lines).
#   STATUS    an agent status file in C:\KenshiTestRuns\agents\ is rewritten to DONE, FAILED or STOPPED-CONTEXT (the latter two end with: respawn fresh <task> from <handoff path>)
#   BATCH     batch-health.sh <out-dir> (--batch) is not HEALTH OK (HEALTH DONE or HEALTH STALL)
#   RIG       rig-health.sh exits non-zero (stall, alert, idle with no reason)
#   BACKSTOP  none of the above for --backstop s (default 600): runs event-sweep.sh and prints its lines after the header
# Inbox and status are checked every --poll s (default 5); batch and rig health every 300 s (EW_HEALTH_EVERY), silently (no model turn).
# Output: "EVENT <kind> <detail>" then exit 0. Test switches: KAH_RUNS (root, default /mnt/c/KenshiTestRuns), --no-health.
# kenshi-waker-guard counts this script as a waker (its name is in the command line).
set -u
ME=coordinator; BATCH=""; BACK=600; POLL=5; HEALTH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --me) ME="$2"; shift 2;;
    --batch) BATCH="$2"; shift 2;;
    --backstop) BACK="$2"; shift 2;;
    --poll) POLL="$2"; shift 2;;
    --no-health) HEALTH=0; shift;;
    *) echo "usage: event-wait.sh [--me name] [--batch out-dir] [--backstop sec] [--poll sec] [--no-health]" >&2; exit 2;;
  esac
done
R=${KAH_RUNS:-/mnt/c/KenshiTestRuns}
HERE=$(cd "$(dirname "$0")" && pwd)
INBOX="$R/inbox/$ME"; mkdir -p "$INBOX"
# stall_suppress <message text>: exit 0 = the message is an AGENT STALL/ORPHANED about an agent that is in fact working (or gone): do not wake. Fails open (exit 1) on any doubt.
stall_suppress() {
  local msg=$1 kind an out line proc sa la rc
  [[ $msg =~ ^AGENT[[:space:]]+(STALL|ORPHANED)[[:space:]]+([A-Za-z0-9._-]+) ]] || return 1
  kind=${BASH_REMATCH[1]}; an=${BASH_REMATCH[2]}
  if [ -n "${EW_ROLLCALL_CMD:-}" ]; then out=$(eval "$EW_ROLLCALL_CMD" 2>/dev/null)
  else
    rc=$(wslpath -w "$HERE/agent-rollcall.ps1" 2>/dev/null) || rc='C:\KenshiModding\tools\automation\agent-rollcall.ps1'
    out=$(timeout 60 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$rc" 2>/dev/null < /dev/null | tr -d '\r')
  fi
  case "$out" in *ROLLCALL*) ;; *) return 1;; esac
  line=$(printf '%s\n' "$out" | grep -m1 "^ROLLCALL $an ")
  [ -z "$line" ] && return 0                      # no longer RUNNING: terminal statuses wake on their own
  proc=$(printf '%s' "$line" | sed -n 's/.* proc=\([A-Za-z/]*\).*/\1/p')
  sa=$(printf '%s' "$line" | sed -n 's/.* status_age=\([0-9.]*\)m.*/\1/p')
  la=$(printf '%s' "$line" | sed -n 's/.* log_age=\([0-9.]*\)m.*/\1/p')
  [ "$proc" = DEAD ] && return 1
  [ "$kind" = STALL ] && [ "$proc" != alive ] && return 1
  [ -z "$sa" ] && return 1
  awk -v s="$sa" -v l="${la:-$sa}" -v f="${EW_STALL_FRESH_MIN:-10}" 'BEGIN{m=(l+0<s+0)?l:s; exit !(m+0<f+0)}'
}
MARK=$(mktemp); trap 'rm -f "$MARK"' EXIT   # created now: status files rewritten after this point are "new"
start=$(date +%s); last_health=0
while :; do
  now=$(date +%s)
  # INBOX: a message file waiting directly in the inbox
  m=$(find "$INBOX" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | head -1)
  if [ -n "$m" ] && stall_suppress "$(head -c 400 "$INBOX/$m" | tr -d '\r' | tr '\n' ' ')"; then
    mkdir -p "$INBOX/delivered/suppressed"; mv "$INBOX/$m" "$INBOX/delivered/suppressed/"; m=""   # quiet filter: working/gone agent, no wake
  fi
  if [ -n "$m" ]; then echo "EVENT INBOX $m: $(head -c 300 "$INBOX/$m" | tr -d '\r' | tr '\n' ' ')"; mkdir -p "$INBOX/delivered"; mv "$INBOX/$m" "$INBOX/delivered/"; exit 0; fi
  # STATUS: an agent status file rewritten since this wait started, now DONE / FAILED / STOPPED-CONTEXT
  while IFS= read -r f; do
    l=$(head -1 "$f" | tr -d '\r')
    if [[ $l =~ ^[^|]*[|][[:space:]]*(DONE|FAILED|STOPPED-CONTEXT)[[:space:]]*[|] ]]; then
      n=$(basename "$f" .status); st=${BASH_REMATCH[1]}; task=$(sed -n 2p "$f" | tr -d '\r' | cut -c1-200)
      rs=""
      if [ "$st" != DONE ]; then   # work is not finished: say how to pick it up (a fresh agent, never SendMessage the old one)
        h="$R/agents/$n.handoff.md"; [ -f "$h" ] || h="$f"
        case "$h" in /mnt/c/*|/c/*) h="C:\$(printf '%s' "${h#/mnt}" | sed 's|^/c/||; s|/|\|g')";; esac
        rs=" | respawn fresh ${task#task: } from $h (unless a successor such as ${n}2 or ${n}b already runs)"
      fi
      echo "EVENT STATUS $n $st: $task$rs"; exit 0
    fi
  done < <(find "$R/agents" -maxdepth 1 -name '*.status' -newer "$MARK" 2>/dev/null)
  # AGENT-HOST: the hidden daemon that owns the independent agents writes agent-queue/host.state.json every ~2 s; stale > 120 s while it had agents/jobs = restart it hidden and wake
  hs="$R/agent-queue/host.state.json"
  if [ -f "$hs" ] && [ $(( now - $(stat -c %Y "$hs") )) -gt "${EW_HOST_STALE:-120}" ] && grep -Eq '"(live|queued)": *[1-9]' "$hs"; then
    powershell.exe -NoProfile -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\KenshiModding\tools\automation\agent-host.ps1'" < /dev/null >/dev/null 2>&1
    touch "$hs"
    echo "EVENT STALL agent-host: heartbeat was > ${EW_HOST_STALE:-120}s old with live/queued agents; restarted it hidden (check agent-rollcall.ps1 and the agents' pids)"; exit 0
  fi
  # BATCH + RIG: silent health checks every 300 s (EW_HEALTH_EVERY); anything not healthy wakes the session
  if [ "$HEALTH" = 1 ] && [ $(( now - last_health )) -ge "${EW_HEALTH_EVERY:-300}" ]; then
    last_health=$now
    if [ -n "$BATCH" ]; then
      b=$(timeout 120 bash "$HERE/batch-health.sh" "$BATCH" 2>&1 | tail -1)
      case "$b" in "HEALTH OK"*) ;; *) echo "EVENT BATCH ${b:-no output from batch-health}"; exit 0;; esac
    fi
    rg=$(timeout 150 bash "$HERE/rig-health.sh" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then echo "EVENT RIG rc=$rc $(printf '%s\n' "$rg" | tail -1)"; exit 0; fi
  fi
  # LANES: per-lane activity check (lane-idle.ps1: operator RUNNING + status/evidence younger than 6 min); wakes on LANE IDLE / LANE NO-OPERATOR
  if [ "$HEALTH" = 1 ] && [ $(( now - ${last_lane:-0} )) -ge "${EW_LANE_EVERY:-90}" ]; then
    last_lane=$now
    li=$(timeout 60 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\lane-idle.ps1' 2>&1 < /dev/null | tr -d '\r')
    case "$li" in *"LANE IDLE"*|*"LANE NO-OPERATOR"*) echo "EVENT LANE $(printf '%s\n' "$li" | grep -E 'LANE (IDLE|NO-OPERATOR)' | head -5 | tr '\n' ' ')"; exit 0;; esac
  fi
  # BACKSTOP: nothing else happened for --backstop seconds; the sweep catches what no sender reported
  if [ $(( now - start )) -ge "$BACK" ]; then
    echo "EVENT BACKSTOP after $(( now - start ))s"; bash "$HERE/event-sweep.sh" 2>&1; exit 0
  fi
  sleep "$POLL"
done
