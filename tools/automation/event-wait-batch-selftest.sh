#!/usr/bin/env bash
# event-wait-batch-selftest.sh [candidate-script] : selftest of PI-10 waker batching (non-urgent events collected into one wake, urgent never delayed).
# Sandbox KAH_RUNS, --no-health. Default target: event-wait.sh.candidate, else event-wait.sh. Prints SELFTEST PASS n/n. WSL/bash.
HERE=$(cd "$(dirname "$0")" && pwd)
EW="${1:-$HERE/event-wait.sh.candidate}"; [ -f "$EW" ] || EW="$HERE/event-wait.sh"
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
export KAH_RUNS="$BOX" EW_BATCH_SEC=6 EW_QUIET_DONE=0 EW_DIGEST=0 EW_ROLLCALL_CMD="echo ROLLCALL x kind=INPROC proc=n/a status_age=15m log_age=- latest=x"
IN="$BOX/inbox/coordinator"; mkdir -p "$BOX/agents" "$IN"
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (got '$2', want '$3')"; fi; }
status() { printf '2026-10-15 18:00 | %s | x\ntask: %s task\nstep: s\n' "$2" "$1" > "$BOX/agents/$1.status"; }
msg() { printf '%s' "$2" > "$IN/$1.msg"; }
reset() { rm -f "$BOX"/agents/*.status "$IN"/*.msg; rm -rf "$IN/delivered"; }
# run_bg <out>: start the waker in the background, wait for its start mark
run_bg() { bash "$EW" --no-health --poll 1 --backstop 40 > "$1" 2>&1 & WP=$!; sleep 1.5; }
secs() { echo $(( $(date +%s) - T0 )); }
lines() { grep -c '^EVENT' "$1"; }

# 1. a burst of 3 DONE events (spread over ~2 s) is printed in ONE wake, after the window
reset; run_bg "$BOX/o1"; T0=$(date +%s)
status a1 DONE; sleep 1; status a2 DONE; sleep 1; status a3 DONE
sleep 2; ck 'DONE burst: still waiting inside the window' "$(kill -0 $WP 2>/dev/null && echo waiting || echo woke)" waiting
wait $WP; t=$(secs)
ck 'DONE burst: all 3 DONE in one wake' "$(grep -c 'EVENT STATUS a. DONE' "$BOX/o1")" 3
ck 'DONE burst: summary line says 3 events' "$(grep -c 'EVENT BATCH 3 events' "$BOX/o1")" 1
ck 'DONE burst: woke after the window (>= 6 s), before backstop' "$([ "$t" -ge 6 ] && [ "$t" -lt 20 ] && echo yes || echo "no:$t")" yes

# 2. urgent events wake at once (< 4 s, far inside the 6 s window), alone and with no buffered items
for u in 'AGENT DEAD x : process gone' 'AGENT KILLED x : stalled' 'AGENT WALL-CLOCK x : ran 100 min' 'AGENT ORPHANED x : silent' 'Shay asks: how now?' 'x STOPPED-CONTEXT: cut' 'some peer message with no known format'; do
  reset; run_bg "$BOX/o2"; T0=$(date +%s); msg m "$u"; wait $WP; t=$(secs)
  ck "urgent not delayed: $u" "$([ "$t" -lt 4 ] && grep -q 'EVENT INBOX' "$BOX/o2" && echo now || echo "late:$t")" now
done
reset; run_bg "$BOX/o3"; T0=$(date +%s); status f1 FAILED; wait $WP; t=$(secs)
ck 'urgent status FAILED not delayed' "$([ "$t" -lt 4 ] && grep -q 'EVENT STATUS f1 FAILED' "$BOX/o3" && echo now || echo "late:$t")" now
reset; run_bg "$BOX/o3"; T0=$(date +%s); status s1 STOPPED-CONTEXT; wait $WP; t=$(secs)
ck 'urgent status STOPPED-CONTEXT not delayed' "$([ "$t" -lt 4 ] && grep -q 'EVENT STATUS s1 STOPPED-CONTEXT' "$BOX/o3" && echo now || echo "late:$t")" now

# 3. flush on urgent arrival: two buffered DONE/INFO events come out in front of the urgent one, at once
reset; run_bg "$BOX/o4"; T0=$(date +%s)
status d1 DONE; msg i1 'INFO rowtool lane idle note'; sleep 2.5; msg u1 'AGENT DEAD d9 : process gone'; wait $WP; t=$(secs)
ck 'flush on urgent: woke before the window ended' "$([ "$t" -lt 6 ] && echo yes || echo "no:$t")" yes
ck 'flush on urgent: buffered DONE + INFO + urgent DEAD all printed' "$(grep -c -E 'EVENT STATUS d1 DONE|EVENT INBOX .*INFO rowtool|EVENT INBOX .*AGENT DEAD d9' "$BOX/o4")" 3
ck 'flush on urgent: urgent line is last (before the summary)' "$(grep -E '^EVENT' "$BOX/o4" | tail -1 | grep -c 'EVENT BATCH 2 events\|AGENT DEAD')" 1

# 4. non-urgent inbox forms are batched: 'x DONE:', 'INFO', 'ROWTOOL', 'x interim:'
reset; run_bg "$BOX/o5"; T0=$(date +%s)
msg m1 'imm26-x DONE: report C:/a'; msg m2 'INFO lane 4080 idle info'; msg m3 'ROWTOOL ok'; msg m4 'imm26-y interim: step 3'
wait $WP; t=$(secs)
ck 'inbox INFO/DONE/interim: 4 items in one wake after the window' "$([ "$t" -ge 6 ] && grep -c 'EVENT BATCH 4 events' "$BOX/o5" | grep -qx 1 && echo ok || echo "no:$t")" ok
ck 'batched inbox files still moved to delivered' "$(ls "$IN/delivered" | wc -l | tr -d ' ')" 4

# 5. a DONE status is not re-reported by a second pass inside the same wait
reset; run_bg "$BOX/o6"; status r1 DONE; wait $WP
ck 'one DONE reported once' "$(grep -c 'EVENT STATUS r1 DONE' "$BOX/o6")" 1

# 6. EW_BATCH_SEC=0 restores the old behaviour (DONE wakes at once)
reset; EW_BATCH_SEC=0 run_bg "$BOX/o7"; T0=$(date +%s); status z1 DONE; wait $WP; t=$(secs)
ck 'EW_BATCH_SEC=0: DONE wakes at once' "$([ "$t" -lt 4 ] && grep -q 'EVENT STATUS z1 DONE' "$BOX/o7" && echo now || echo "late:$t")" now

# 7. PI-40 quiet DONE (EW_QUIET_DONE=1, the default): DONE status / 'x DONE' / TAIL-RELAY DONE never wake alone; they ride in front of the next wake
reset; EW_QUIET_DONE=1 run_bg "$BOX/o8"; status q1 DONE; msg q2 'TAIL-RELAY imm26-q2 DONE 2026-10-16T12:00:00 report: x'; msg q3 'imm26-q3 DONE: report C:/a'; sleep 9
ck 'quiet DONE: no wake after 9 s (> batch window)' "$(kill -0 $WP 2>/dev/null && echo waiting || echo woke)" waiting
msg u9 'AGENT DEAD d9 : process gone'; wait $WP
ck 'quiet DONE: urgent wake carries the 3 quiet lines' "$(grep -c 'EVENT DONE(quiet)' "$BOX/o8")" 3
ck 'quiet DONE: urgent line present' "$(grep -c 'AGENT DEAD d9' "$BOX/o8")" 1
reset; EW_QUIET_DONE=1 run_bg "$BOX/o9"; T0=$(date +%s); msg r1 'TAIL-RELAY imm26-r1 FAILED 2026-10-16T12:00:00 report: x'; wait $WP; t=$(secs)
ck 'quiet mode: TAIL-RELAY FAILED still wakes at once' "$([ "$t" -lt 4 ] && grep -q 'FAILED' "$BOX/o9" && echo now || echo "late:$t")" now
reset; EW_QUIET_DONE=1 run_bg "$BOX/o10"; T0=$(date +%s); status f2 STOPPED-CONTEXT; wait $WP; t=$(secs)
ck 'quiet mode: STOPPED-CONTEXT still wakes at once' "$([ "$t" -lt 4 ] && grep -q 'STOPPED-CONTEXT' "$BOX/o10" && echo now || echo "late:$t")" now
reset; EW_QUIET_DONE=1 bash "$EW" --no-health --poll 1 --backstop 6 > "$BOX/o11" 2>&1 & WP=$!; sleep 1.5; status b1 DONE; wait $WP
ck 'quiet DONE: backstop flushes it' "$(grep -c 'EVENT DONE(quiet) STATUS b1 DONE' "$BOX/o11")" 1
if [ "$fail" -gt 0 ]; then echo "SELFTEST FAIL $fail (pass $pass)"; exit 1; fi
echo "SELFTEST PASS $pass/$pass"
