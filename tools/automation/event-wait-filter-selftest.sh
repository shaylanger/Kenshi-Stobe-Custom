#!/usr/bin/env bash
# event-wait-filter-selftest.sh : selftest of the quiet-waker filter (AGENT STALL / ORPHANED suppression) in event-wait.sh(.new).
# Uses a sandbox KAH_RUNS and a fake roll call (EW_ROLLCALL_CMD). Prints SELFTEST PASS n/n. WSL/bash.
HERE=$(cd "$(dirname "$0")" && pwd)
EW="${1:-$HERE/event-wait.sh.candidate}"; [ -f "$EW" ] || EW="$HERE/event-wait.sh"
[ -n "${EW_SCRIPT:-}" ] && EW="$EW_SCRIPT"
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/agents" "$BOX/inbox/coordinator"
RC="$BOX/rollcall.txt"
cat > "$RC" <<'R'
ROLLCALL busy kind=INDEPENDENT proc=alive status_age=15m log_age=2m latest=working
ROLLCALL quiet kind=INDEPENDENT proc=alive status_age=15m log_age=14m latest=idle
ROLLCALL nolog kind=INDEPENDENT proc=alive status_age=15m log_age=- latest=idle
ROLLCALL gone kind=INDEPENDENT proc=DEAD status_age=15m log_age=1m latest=x
ROLLCALL inprocfresh kind=INPROC proc=n/a status_age=15m log_age=3m latest=x
ROLLCALL inprocquiet kind=INPROC proc=n/a status_age=15m log_age=- latest=x
R
export EW_ROLLCALL_CMD="cat $RC" KAH_RUNS="$BOX"
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (got '$2', want '$3')"; fi; }
# run <message>: drop it in the inbox, run the waker; prints "woke" or "quiet"
run() {
  rm -f "$BOX"/inbox/coordinator/*.msg; printf '%s' "$1" > "$BOX/inbox/coordinator/m.msg"
  o=$(timeout 20 bash "$EW" --no-health --poll 1 --backstop 3 2>&1)
  case "$o" in *"EVENT INBOX"*) echo woke;; *"EVENT BACKSTOP"*) echo quiet;; *) echo "other:$o";; esac
}
ck 'STALL, busy agent (alive, log 2m): suppressed' "$(run 'AGENT STALL busy : 15 min with no status heartbeat')" quiet
ck 'suppressed message moved to delivered/suppressed' "$(ls "$BOX/inbox/coordinator/delivered/suppressed" 2>/dev/null | wc -l | tr -d ' ')" 1
ck 'STALL, truly quiet agent (14m): wakes' "$(run 'AGENT STALL quiet : 15 min')" woke
ck 'STALL, no log and old status: wakes' "$(run 'AGENT STALL nolog : 15 min')" woke
ck 'STALL, dead process: wakes' "$(run 'AGENT STALL gone : 15 min')" woke
ck 'STALL, agent no longer RUNNING: suppressed' "$(run 'AGENT STALL finished : 15 min')" quiet
ck 'ORPHANED, INPROC with fresh evidence: suppressed' "$(run 'AGENT ORPHANED inprocfresh : silent')" quiet
ck 'ORPHANED, INPROC quiet: wakes' "$(run 'AGENT ORPHANED inprocquiet : silent')" woke
ck 'AGENT KILLED always wakes (busy name)' "$(run 'AGENT KILLED busy : stalled')" woke
ck 'AGENT DEAD always wakes' "$(run 'AGENT DEAD busy : process gone')" woke
ck 'AGENT WALL-CLOCK always wakes' "$(run 'AGENT WALL-CLOCK busy : ran 100 min')" woke
ck 'peer / question message always wakes' "$(run 'Shay asks: STALL busy question')" woke
EW_ROLLCALL_CMD="echo nothing useful" ck 'roll call unusable: fails open (wakes)' "$(EW_ROLLCALL_CMD='echo broken' run 'AGENT STALL busy : 15 min')" woke
if [ "$fail" -gt 0 ]; then echo "SELFTEST FAIL $fail (pass $pass)"; exit 1; fi
echo "SELFTEST PASS $pass/$pass"
