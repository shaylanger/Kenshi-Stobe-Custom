#!/usr/bin/env bash
# event-wait-digest-selftest.sh [candidate-script] : selftest of the PI-40 digest in event-wait.sh (wake only for actionable events; the rest goes to a digest + logs).
# Default target: event-wait.sh.candidate, else event-wait.sh. Sandbox KAH_RUNS, --no-health, fake guard-lib open list (EW_OPEN_CMD). Prints SELFTEST PASS n/n. WSL/bash.
HERE=$(cd "$(dirname "$0")" && pwd)
EW="${1:-$HERE/event-wait.sh.candidate}"; [ -f "$EW" ] || EW="$HERE/event-wait.sh"
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
OPENF="$BOX/open.txt"
export KAH_RUNS="$BOX" EW_BATCH_SEC=6 EW_DIGEST=1 EW_QUIET_DONE=1 EW_OPEN_CMD="echo OPENCHECK-OK; cat $OPENF" \
  EW_ROLLCALL_CMD="echo ROLLCALL x kind=INPROC proc=n/a status_age=15m log_age=- latest=x"
IN="$BOX/inbox/coordinator"; mkdir -p "$BOX/agents" "$IN" "$BOX/setupfail"
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (got '$2', want '$3')"; fi; }
status() { printf '2026-10-16 12:00 | %s | x\ntask: %s task\nstep: s\n' "$2" "$1" > "$BOX/agents/$1.status"; }
msg() { printf '%s' "$2" > "$IN/$1.msg"; }
reset() { rm -f "$BOX"/agents/*.status "$IN"/*.msg "$BOX"/waker-*.tsv "$BOX"/waker-*.log "$BOX"/setupfail/*; rm -rf "$IN/delivered"; : > "$OPENF"; }
run_bg() { bash "$EW" --no-health --poll 1 --backstop "${BACK:-40}" > "$1" 2>&1 & WP=$!; sleep 1.5; }
secs() { echo $(( $(date +%s) - T0 )); }
alive() { kill -0 $WP 2>/dev/null && echo waiting || echo woke; }
stopbg() { kill $WP 2>/dev/null; wait $WP 2>/dev/null; }
RELAY_HDR='report: C:\x'
# wakes_now <label> <starter...>: the starter runs after the waker start; the waker must end within 4 s and print an EVENT line
wakes_now() { local lbl=$1; shift; reset; run_bg "$BOX/u"; T0=$(date +%s); "$@"; wait $WP; local t; t=$(secs); ck "wakes at once: $lbl" "$([ "$t" -lt 4 ] && grep -q '^EVENT' "$BOX/u" && echo now || echo "late:$t")" now; }

# 1. every urgent kind still wakes at once (digest on)
wakes_now 'AGENT DEAD' msg m 'AGENT DEAD x : process gone'
wakes_now 'AGENT KILLED' msg m 'AGENT KILLED x : stalled'
wakes_now 'AGENT WALL-CLOCK' msg m 'AGENT WALL-CLOCK x : ran 100 min'
wakes_now 'AGENT ORPHANED (quiet filter does not apply)' msg m 'AGENT ORPHANED x : silent'
wakes_now 'AGENT STALL (not alive)' msg m 'AGENT STALL x : 15 min'
wakes_now 'question' msg m 'imm26-q DONE but should I merge it?'
wakes_now 'unknown peer message' msg m 'some peer message with no known format'
wakes_now 'LANE NO-OPERATOR message' msg m 'LANE NO-OPERATOR 4080-i3 no operator running'
wakes_now 'LANE IDLE message' msg m 'LANE IDLE 5090-i4 idle 8 min'
wakes_now 'HEALTH STALL message' msg m 'HEALTH STALL batch out/x'
wakes_now 'pilot escalate (unknown format)' msg m 'PILOT-ESCALATE 00-ask lane=5090-i4 operator_verdict=ESCALATE'
st_stop() { echo f1 > "$OPENF"; status f1 STOPPED-CONTEXT; }
wakes_now 'STATUS STOPPED-CONTEXT, no successor' st_stop
st_fail() { echo f1 > "$OPENF"; status f1 FAILED; }
wakes_now 'STATUS FAILED, no successor' st_fail
rl_fail() { echo f1 > "$OPENF"; status f1 FAILED; msg r "TAIL-RELAY f1 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR
STATUS STOPPED-CONTEXT: f1 stopped"; }
wakes_now 'TAIL-RELAY FAILED, no successor (guard lib lists it open)' rl_fail
rl_stop() { echo f1 > "$OPENF"; status f1 STOPPED-CONTEXT; msg r 'f1 STOPPED-CONTEXT: cut'; }
wakes_now 'plain "x STOPPED-CONTEXT" message, no successor' rl_stop
wakes_now 'FAILED message for an agent with no status file (fail open)' msg m 'ghost FAILED: x'

# 2. DONE statuses / DONE relays / INFO never wake; they ride in a digest in front of the next wake
reset; run_bg "$BOX/d1"
status a1 DONE; msg d1 'TAIL-RELAY a1 DONE 2026-10-16T12:00:00 report: x'; msg d2 'imm26-a2 DONE: report C:/a'; msg d3 'INFO rowtool ok'; sleep 9
ck 'DONE status + relay + x DONE + INFO: no wake after 9 s (> batch window)' "$(alive)" waiting
msg u 'AGENT DEAD d9 : process gone'; wait $WP
ck 'digest block printed in front of the urgent wake' "$(grep -c '^EVENT DIGEST 4 items' "$BOX/d1")" 1
ck 'digest carries the DONE items' "$(grep -c '^  - DONE:' "$BOX/d1")" 3
ck 'digest carries the INFO item' "$(grep -c '^  - INFO:' "$BOX/d1")" 1
ck 'urgent line is last' "$(tail -1 "$BOX/d1" | grep -c 'AGENT DEAD d9')" 1
ck 'suppressed log has the 4 items' "$(wc -l < "$BOX/waker-suppressed.log" | tr -d ' ')" 4
ck 'wake log has one wake' "$(wc -l < "$BOX/waker-wakes.log" | tr -d ' ')" 1

# 3. duplicate relays do not wake (also across a restarted waker: the seen-set is persisted)
reset; echo f2 > "$OPENF"; status f2 STOPPED-CONTEXT
run_bg "$BOX/e1"; T0=$(date +%s); msg r1 "TAIL-RELAY f2 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR"; wait $WP; t=$(secs)
ck 'first relay for f2 wakes' "$([ "$t" -lt 4 ] && echo now || echo "late:$t")" now
run_bg "$BOX/e2"; msg r2 "TAIL-RELAY f2 FAILED 2026-10-16T12:31:09-06:00
$RELAY_HDR"; sleep 4
ck 'duplicate relay (same agent+state, restarted waker): no wake' "$(alive)" waiting
msg r3 "TAIL-RELAY f2 STOPPED-CONTEXT 2026-10-16T12:31:17-06:00
$RELAY_HDR"; sleep 3
ck 'third relay (state name differs, same outcome class): no wake' "$(alive)" waiting
msg u 'AGENT DEAD d9 : x'; wait $WP
ck 'duplicates listed in the digest as DUP' "$(grep -c '^  - DUP:' "$BOX/e2")" 2
reset; run_bg "$BOX/e3"
msg r1 'TAIL-RELAY g1 DONE 2026-10-16T12:00:00 report: x'; msg r2 'TAIL-RELAY g1 DONE 2026-10-16T12:00:05 report: x'; sleep 4
ck 'duplicate DONE relay: no wake' "$(alive)" waiting
msg u 'AGENT DEAD d9 : x'; wait $WP
ck 'duplicate DONE relay: one DONE + one DUP in digest' "$(grep -c '^  - DONE:' "$BOX/e3")/$(grep -c '^  - DUP:' "$BOX/e3")" 1/1

# 4. FAILED / STOPPED-CONTEXT relay for an agent that already has a successor does not wake
reset; echo h1 > "$OPENF"; status h1 STOPPED-CONTEXT; sleep 1; status h12 RUNNING
run_bg "$BOX/s1"; msg r "TAIL-RELAY h1 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR"; sleep 4
ck 'relay with running successor h12 (name rule): no wake' "$(alive)" waiting
stopbg
reset; echo k1 > "$OPENF"; status k1 FAILED; sleep 1; printf '2026-10-16 12:05 | RUNNING | x\ntask: carry on\nstep: resumed from k1 handoff\n' > "$BOX/agents/zz-other.status"
run_bg "$BOX/s1"; msg r "TAIL-RELAY k1 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR"; sleep 4
ck 'relay with a RUNNING status naming k1 (text rule): no wake' "$(alive)" waiting
stopbg
reset; status m1 STOPPED-CONTEXT; : > "$OPENF"                  # not in the guard-lib open list (ledger/lane successor or abandoned)
run_bg "$BOX/s1"; msg r "TAIL-RELAY m1 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR"; sleep 4
ck 'relay for an agent the guard lib no longer lists open: no wake' "$(alive)" waiting
stopbg
reset; echo n1 > "$OPENF"; status n1 STOPPED-CONTEXT
run_bg "$BOX/s1"; msg r "TAIL-RELAY n1 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR"; sleep 4
ck 'same relay but the guard lib lists n1 open: wakes' "$(alive)" woke
stopbg
# the STATUS-file path: a successor is already running when the stop status is seen
reset; status p1 RUNNING; run_bg "$BOX/s2"; sleep 1; status p1 STOPPED-CONTEXT; status p1b RUNNING; sleep 4
ck 'STATUS STOPPED-CONTEXT with running successor p1b: no wake' "$(alive)" waiting
stopbg

# 5. SETUP-FAIL notices: stale (ticket ready) are digested with the newest note; others wake
reset; printf '{"row":"03-b","state":"ready","notes":["a","2026-10-16T12:46:40 ready: sfZ recipe pushed"]}' > "$BOX/setupfail/03-b.json"
printf '{"row":"08-d","state":"open","notes":[]}' > "$BOX/setupfail/08-d.json"
run_bg "$BOX/f1"; msg a 'SETUP-FAIL 03-b needs unblock plan: recipe
lane=4080-i3 reason: x'; sleep 4
ck 'SETUP-FAIL for a ready ticket: no wake' "$(alive)" waiting
msg b 'SETUP-FAIL 08-d needs unblock plan: recipe
lane=4080-i4 reason: y'; wait $WP
ck 'SETUP-FAIL for an open ticket: wakes' "$(grep -c 'EVENT INBOX.*SETUP-FAIL 08-d' "$BOX/f1")" 1
ck 'ready notice shown in the digest with the newest note' "$(grep -c '^  - SETUP-FAIL-READY: 03-b .*sfZ recipe pushed' "$BOX/f1")" 1
wakes_now 'SETUP-FAIL for a row with no ticket at all' msg a 'SETUP-FAIL 99-z needs unblock plan: native'

# 6. switches: EW_DIGEST=0 restores the old behaviour
reset; echo h1 > "$OPENF"; status h1 STOPPED-CONTEXT; sleep 1; status h12 RUNNING
EW_DIGEST=0 run_bg "$BOX/o1"; T0=$(date +%s); msg r "TAIL-RELAY h1 FAILED 2026-10-16T12:31:06-06:00
$RELAY_HDR"; wait $WP; t=$(secs)
ck 'EW_DIGEST=0: relay with a successor wakes again' "$([ "$t" -lt 4 ] && echo now || echo "late:$t")" now
reset; EW_DIGEST=0 EW_QUIET_DONE=1 run_bg "$BOX/o2"; msg q1 'TAIL-RELAY q1 DONE 2026-10-16T12:00:00 report: x'; sleep 2; msg u 'AGENT DEAD d9 : x'; wait $WP
ck 'EW_DIGEST=0: old EVENT DONE(quiet) lines, no digest block' "$(grep -c 'EVENT DONE(quiet)' "$BOX/o2")/$(grep -c 'EVENT DIGEST' "$BOX/o2")" 1/0

# 7. backstop flushes the digest; stats script reads the logs
reset; BACK=6 run_bg "$BOX/b1"; status z1 DONE; wait $WP
ck 'backstop prints the digest' "$(grep -c 'EVENT DIGEST 1 items' "$BOX/b1")" 1
out=$(KAH_RUNS="$BOX" bash "$HERE/waker-stats.sh" 24 2>&1)
ck 'waker-stats.sh prints wakes/hour and suppressed/hour' "$(printf '%s' "$out" | grep -c 'wakes/hour\|suppressed/hour')" 2
if [ "$fail" -gt 0 ]; then echo "SELFTEST FAIL $fail (pass $pass)"; exit 1; fi
echo "SELFTEST PASS $pass/$pass"
