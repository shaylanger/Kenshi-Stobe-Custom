#!/usr/bin/env bash
# event-stream.sh [--me <name>] [--batch <out-dir>] [--backstop <sec>] [--poll <sec>] [--no-health] [--as <token>]   (WSL)
# STREAMING waker (Shay 2026-10-15, order #1). Loops around event-wait.sh (NOT modified): every wake of event-wait.sh is turned into one stdout line per
# event and the loop keeps running, so the coordinator attaches the Claude Code Monitor tool to this script once (each stdout line = one notification)
# instead of restarting a background event-wait.sh after every wake-up.
# Launch (from Git Bash; the Monitor tool command):
#   MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/event-stream.sh --as event-wait [--batch /mnt/c/<out-dir>]
# '--as <token>' is ignored by the script; it only puts the token (event-wait) into the wsl.exe command line, which is what kenshi-waker-guard.ps1 greps
# ('batch-health|rig-health|lane-waker|event-wait'), so the Stop hook sees a running waker with NO hook edit. (Hook change that would make it native: add |event-stream to that regex.)
# Semantics are inherited from event-wait.sh (urgent = at once, DONE/INFO batched EW_BATCH_SEC, default 90 s; quiet STALL filter; inbox files moved to delivered\).
# Added here:
#   - one line per event: "EVENT <kind> <detail>" (the 'EVENT BATCH n events over Ns' summary lines are dropped, every item already has its own line)
#   - de-duplication: an identical non-INBOX/non-STATUS line is printed again only after ES_DEDUP_SEC (default 600); BACKSTOP prints only SWEEP lines that are
#     new or older than ES_REPEAT_SEC (default 1800) - a quiet system prints nothing at all (no per-10-minute "BACKSTOP" noise)
#   - health (batch-health, rig-health, lane-idle) runs in a background ticker every EW_HEALTH_EVERY/EW_LANE_EVERY s, so a slow check never delays an inbox/status event;
#     an unhealthy result is printed once, then again only after ES_REPEAT_SEC while it persists
#   - gap scan: a status rewritten to DONE/FAILED/STOPPED-CONTEXT between two event-wait runs (the few ms in which no waker holds its start mark) is still reported
#   - a failing event-wait run (crash, rc != 0, no output) never ends the loop: one 'EVENT STREAM child rc=N ...' line, then retry with back-off (2..60 s)
#   - exits 0 cleanly when the stop file appears ($KAH_RUNS/event-stream.stop; removed at start; --stop-file <path> overrides) or on TERM/INT
# Test seams: KAH_RUNS, ES_CHILD (script to loop instead of event-wait.sh), ES_STOP_FILE, ES_TICK (stop-file check interval, default 1 s).
set -u
ME=coordinator; BATCH=""; BACK=${ES_BACKSTOP:-600}; POLL=5; HEALTH=1; STOPF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --me) ME="$2"; shift 2;;
    --batch) BATCH="$2"; shift 2;;
    --backstop) BACK="$2"; shift 2;;
    --poll) POLL="$2"; shift 2;;
    --no-health) HEALTH=0; shift;;
    --stop-file) STOPF="$2"; shift 2;;
    --as) shift 2;;
    *) echo "usage: event-stream.sh [--me name] [--batch out-dir] [--backstop sec] [--poll sec] [--no-health] [--stop-file path] [--as token]" >&2; exit 2;;
  esac
done
R=${KAH_RUNS:-/mnt/c/KenshiTestRuns}
HERE=$(cd "$(dirname "$0")" && pwd)
CHILD=${ES_CHILD:-$HERE/event-wait.sh}
STOPF=${STOPF:-${ES_STOP_FILE:-$R/event-stream.stop}}
TICK=${ES_TICK:-1}; DEDUP=${ES_DEDUP_SEC:-600}; REPEAT=${ES_REPEAT_SEC:-1800}
TMP=$(mktemp -d); HP=""; CP=""
cleanup() { [ -n "$CP" ] && kill "$CP" 2>/dev/null; [ -n "$HP" ] && kill "$HP" 2>/dev/null; rm -rf "$TMP"; }
trap 'cleanup; exit 0' TERM INT
trap cleanup EXIT
rm -f "$STOPF"
declare -A LAST   # line key -> epoch of last print
# emit <line> [window]: print one line (cut to 400 chars) unless the same key was printed less than <window> s ago (window 0 = always print)
emit() {
  local l=${1:0:400} w=${2:-0} now k
  now=$(date +%s); k=$(printf '%s' "$l" | tr -d '0-9')
  if [ "$w" -gt 0 ] && [ -n "${LAST[$k]:-}" ] && [ $(( now - LAST[$k] )) -lt "$w" ]; then return 0; fi
  LAST[$k]=$now; printf '%s\n' "$l"
}
# ---- health ticker (background subshell; own dedupe state; prints atomically) ----
health_loop() {
  local last_h=0 last_l=0 now b rg rc li msg
  declare -A HL
  hp() { local l=${1:0:400} k; k=$(printf '%s' "$l" | tr -d '0-9'); now=$(date +%s)
         if [ -n "${HL[$k]:-}" ] && [ $(( now - HL[$k] )) -lt "$REPEAT" ]; then return 0; fi; HL[$k]=$now; printf '%s\n' "$l"; }
  while [ ! -e "$STOPF" ]; do
    now=$(date +%s)
    if [ $(( now - last_h )) -ge "${EW_HEALTH_EVERY:-300}" ]; then
      last_h=$now
      if [ -n "$BATCH" ]; then
        b=$(timeout 120 bash "$HERE/batch-health.sh" "$BATCH" 2>&1 | tail -1)
        case "$b" in "HEALTH OK"*) ;; *) hp "EVENT BATCH ${b:-no output from batch-health}";; esac
      fi
      rg=$(timeout 150 bash "$HERE/rig-health.sh" 2>&1); rc=$?
      [ "$rc" -ne 0 ] && hp "EVENT RIG rc=$rc $(printf '%s\n' "$rg" | tail -1)"
    fi
    if [ $(( now - last_l )) -ge "${EW_LANE_EVERY:-90}" ]; then
      last_l=$now
      li=$(timeout 60 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\lane-idle.ps1' 2>&1 < /dev/null | tr -d '\r')
      case "$li" in *"LANE IDLE"*|*"LANE NO-OPERATOR"*) hp "EVENT LANE $(printf '%s\n' "$li" | grep -E 'LANE (IDLE|NO-OPERATOR)' | head -5 | tr '\n' ' ')";; esac
    fi
    sleep 5
  done
}
if [ "$HEALTH" = 1 ]; then health_loop & HP=$!; fi
# process_output <file>: turn one event-wait wake into stream lines
process_output() {
  local f=$1 line inback=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
      "") ;;
      "EVENT BATCH "*" events over "*) ;;                         # summary of a batched wake: items already printed
      "EVENT BACKSTOP "*) inback=1;;                             # the sweep lines follow; a quiet backstop prints nothing
      "SWEEP CLEAN"*) ;;
      "SWEEP "*) emit "EVENT $line" "$REPEAT";;
      "ROLLCALL "*) ;;                                           # informational roll call of the sweep: not an event
      "EVENT INBOX "*|"EVENT STATUS "*) emit "$line" 0;;         # distinct by file name / agent; never suppress
      "EVENT "*) emit "$line" "$DEDUP";;
      *) [ "$inback" = 1 ] || emit "EVENT RAW $line" "$DEDUP";;
    esac
  done < "$f"
}
# gap_scan <marker> <output-file>: terminal status files rewritten since <marker> that the run's output does not mention
gap_scan() {
  local mk=$1 out=$2 f l n st task h rs
  [ -d "$R/agents" ] || return 0
  while IFS= read -r f; do
    l=$(head -1 "$f" | tr -d '\r')
    if [[ $l =~ ^[^|]*[|][[:space:]]*(DONE|FAILED|STOPPED-CONTEXT)[[:space:]]*[|] ]]; then
      n=$(basename "$f" .status); st=${BASH_REMATCH[1]}
      grep -q "EVENT STATUS $n $st" "$out" 2>/dev/null && continue
      task=$(sed -n 2p "$f" | tr -d '\r' | cut -c1-200); rs=""
      if [ "$st" != DONE ]; then h="$R/agents/$n.handoff.md"; [ -f "$h" ] || h="$f"; rs=" | respawn fresh ${task#task: } from $h (unless a successor such as ${n}2 or ${n}b already runs)"; fi
      emit "EVENT STATUS $n $st: $task$rs" 0
    fi
  done < <(find "$R/agents" -maxdepth 1 -name '*.status' -newer "$mk" 2>/dev/null)
}
args=(--me "$ME" --backstop "$BACK" --poll "$POLL" --no-health)   # health is the ticker's job
[ -n "$BATCH" ] && args+=(--batch "$BATCH")
fails=0; back=2; lastfail=0
while [ ! -e "$STOPF" ]; do
  OUT="$TMP/out.$$"; MK="$TMP/mark"; : > "$OUT"; touch "$MK"
  bash "$CHILD" "${args[@]}" > "$OUT" 2>&1 < /dev/null & CP=$!
  while kill -0 "$CP" 2>/dev/null; do
    if [ -e "$STOPF" ]; then kill "$CP" 2>/dev/null; wait "$CP" 2>/dev/null; CP=""; break 2; fi
    sleep "$TICK"
  done
  wait "$CP" 2>/dev/null; rc=$?; CP=""
  if [ -s "$OUT" ]; then process_output "$OUT"; fi
  gap_scan "$MK" "$OUT"
  if [ "$rc" -ne 0 ] || [ ! -s "$OUT" ]; then
    fails=$((fails + 1)); now=$(date +%s)
    if [ "$fails" -eq 1 ] || [ $(( now - lastfail )) -ge 600 ]; then
      lastfail=$now; printf 'EVENT STREAM child rc=%s %s; retrying in %ss (loop keeps running)\n' "$rc" "$( [ -s "$OUT" ] && head -c 150 "$OUT" | tr '\n' ' ' || echo 'no output')" "$back"
    fi
    i=0; while [ "$i" -lt "$back" ] && [ ! -e "$STOPF" ]; do sleep 1; i=$((i + 1)); done
    back=$(( back * 2 > 60 ? 60 : back * 2 ))
  else
    fails=0; back=2
  fi
done
exit 0
