#!/usr/bin/env bash
# event-sweep.sh (WSL): the check run at each event-wait BACKSTOP (every 10 min). Read-only. One line per problem:
#   SWEEP QUEUE <rig> empty            no list in queue\<rig>\ or queue\any\, and no fresh "none: <reason>" in queue\<rig>.next
#   SWEEP ALERT <file> ...             an ALERT-*.txt is present (rig runner / watchdog / TDR)
#   SWEEP INBOX n unread               messages still in inbox\coordinator\ (read them, then move them to read\)
#   SWEEP STATUS <name> bad format     agent status file whose first line is not "<name> | STATE | yyyy-mm-dd hh:mm"
#   SWEEP STATUS <name> RUNNING <n>m   a RUNNING agent with no status update for 60 min (dead or silent)
#   SWEEP MARKER <name> <why>          an inflight marker (touched in the last 6 h) whose out dir is missing, empty, or already DONE
# Prints "SWEEP CLEAN" when nothing is found. Exit 0 clean, 1 problems. Lanes are not checked here: lane-waker.sh does that.
# Test switch: KAH_RUNS (root, default /mnt/c/KenshiTestRuns).
set -u
R=${KAH_RUNS:-/mnt/c/KenshiTestRuns}; bad=0; now=$(date +%s)
say() { echo "SWEEP $*"; bad=1; }
for rig in 5090 4080; do
  n=$(find "$R/queue/any" "$R/queue/$rig" -maxdepth 1 -name '*.list' -type f 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then
    q="$R/queue/$rig.next"
    if ! { [ -f "$q" ] && find "$q" -mmin -360 2>/dev/null | grep -q . && head -1 "$q" | tr -d '\r' | grep -q '^none:'; }; then
      say "QUEUE $rig empty (no list, no fresh none: <reason>)"
    fi
  fi
done
for a in "$R"/ALERT-*.txt; do [ -f "$a" ] && say "ALERT $(basename "$a") $(head -c 120 "$a" | tr -d '\r\n')"; done
u=$(find "$R/inbox/coordinator" -maxdepth 1 -type f 2>/dev/null | wc -l)
[ "$u" -gt 0 ] && say "INBOX $u undelivered in inbox/coordinator (arrived after the wait ended; read them, then move to delivered\\)"
for f in "$R"/agents/*.status; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .status); l=$(head -1 "$f" | tr -d '\r')
  if ! [[ $l =~ ^[^|]+[|][[:space:]]*(RUNNING|DONE|FAILED|STOPPED-CONTEXT)[[:space:]]*[|][[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
    say "STATUS $n bad format"; continue
  fi
  if [[ $l == *"| RUNNING |"* ]]; then
    age=$(( (now - $(stat -c %Y "$f")) / 60 )); [ "$age" -ge 60 ] && say "STATUS $n RUNNING ${age}m"
  fi
done
for m in "$R"/inflight/*; do
  [ -f "$m" ] || continue
  [ -n "$(find "$m" -mmin -360 2>/dev/null)" ] || continue
  n=$(basename "$m"); d=$(head -1 "$m" | tr -d '\r')
  if [ -z "$d" ]; then say "MARKER $n no out dir in marker"; continue; fi
  p=$(wslpath -u "$d" 2>/dev/null || echo "$d")
  if [ ! -d "$p" ]; then say "MARKER $n out dir missing: $d"
  elif [ -f "$p/DONE" ]; then say "MARKER $n already DONE, still marked: $d"; fi
done
[ "$bad" -eq 0 ] && echo "SWEEP CLEAN"
exit "$bad"
