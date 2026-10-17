#!/usr/bin/env bash
# waker-persist-selftest.sh (PI-51): offline selftest of waker-persist.sh (WSL). Temp KAH_RUNS, a fake event-wait (WP_EVENTWAIT) plus one real event-wait.sh run (--no-health).
# Usage: bash tools/automation/waker-persist-selftest.sh      -> prints SELFTEST PASS/FAIL lines and 'SELFTEST waker-persist n pass / m fail'
set -u
HERE=$(cd "$(dirname "$0")" && pwd); WP="$HERE/waker-persist.sh"
T=$(mktemp -d); export KAH_RUNS="$T"; mkdir -p "$T/fq" "$T/inbox/coordinator" "$T/agents"
export WP_HB_EVERY=1
pass=0; fail=0
ok() { if [ "$1" = 0 ]; then pass=$((pass+1)); echo "SELFTEST PASS $2"; else fail=$((fail+1)); echo "SELFTEST FAIL $2"; fi; }
cat > "$T/fake-ew.sh" <<'FEW'
#!/usr/bin/env bash
# fake event-wait: log args, print + consume the oldest file in $KAH_RUNS/fq, else wait for one
echo "$*" >> "$KAH_RUNS/fake-args.log"
for _ in $(seq 1 300); do
  f=$(ls "$KAH_RUNS/fq" 2>/dev/null | sort | head -1)
  if [ -n "$f" ]; then cat "$KAH_RUNS/fq/$f"; rm -f "$KAH_RUNS/fq/$f"; [ "$f" = crash ] && exit 7; exit 0; fi
  sleep 0.3
done
FEW
export WP_EVENTWAIT="$T/fake-ew.sh"
EV="$T/waker/events.log"
waitfor() { local i; for i in $(seq 1 ${3:-40}); do grep -q -- "$2" "$1" 2>/dev/null && return 0; sleep 0.5; done; return 1; }
cleanup() { bash "$WP" stop >/dev/null 2>&1; pkill -f "$T/fake-ew.sh" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

# 1. start, heartbeat, status
bash "$WP" start >"$T/s1.txt" 2>&1; rc=$?
ok $rc "start returns 0 and daemon is up ($(head -c 100 "$T/s1.txt" | tr '\n' ' '))"
bash "$WP" status | grep -q 'RUNNING.*pid=' ; ok $? "status says RUNNING with a pid"
p1=$(cat "$T/waker/coordinator.pid")
# 2. second start = no second daemon
bash "$WP" start >"$T/s2.txt" 2>&1
p2=$(cat "$T/waker/coordinator.pid"); [ "$p1" = "$p2" ] && grep -q 'already running' "$T/s2.txt"; ok $? "second start does not start a second daemon (pid $p1 == $p2)"
n=$(pgrep -f "waker-persist.sh run --me coordinator" | wc -l); [ "$n" -le 1 ]; ok $? "exactly one daemon process (found $n)"
# 3. direct second 'run' loses the flock and exits at once
timeout 10 bash "$WP" run >"$T/r2.txt" 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'holds' "$T/r2.txt"; ok $? "a second 'run' exits at once (flock single instance)"
bash "$WP" status | grep -q "pid=$p1"; ok $? "first daemon unaffected by the duplicate attempt"
# 4. events appended one per line with a timestamp, no restart needed
printf 'EVENT STATUS a FAILED: t | respawn fresh x\n' > "$T/fq/001"
waitfor "$EV" 'EVENT STATUS a FAILED' ; ok $? "event 1 appended"
printf 'EVENT LANE LANE IDLE 5090-i3 \n' > "$T/fq/002"
waitfor "$EV" 'LANE IDLE 5090-i3'; ok $? "event 2 appended by the same daemon (no re-arm)"
grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} EVENT ' "$EV" | wc -l | grep -q '^2$'; ok $? "every event line has an iso timestamp prefix"
[ "$(cat "$T/waker/coordinator.pid")" = "$p1" ]; ok $? "same pid after two events (persistent)"
# 5. digest folding: header + items = ONE line
printf 'EVENT DIGEST 2 items\n  - DONE: STATUS x DONE: t\n  - INFO: INBOX m\nEVENT INBOX q?: question\n' > "$T/fq/003"
waitfor "$EV" 'INBOX q?'; ok $? "multi-line wake appended"
grep -q 'EVENT DIGEST 2 items ;; DONE: STATUS x DONE: t ;; INFO: INBOX m$' "$EV"; ok $? "digest items folded into the DIGEST line"
# 6. clean backstop is quiet, a backstop with a SWEEP problem is an event
printf 'EVENT BACKSTOP after 600s\nSWEEP CLEAN\n' > "$T/fq/004"
printf 'EVENT BACKSTOP after 600s\nSWEEP QUEUE 4080 empty\n' > "$T/fq/005"
waitfor "$EV" 'SWEEP QUEUE 4080 empty'; ok $? "backstop with a problem line is appended"
! grep -q 'SWEEP CLEAN' "$EV" && grep -q 'clean backstop' "$T/waker/quiet.log"; ok $? "clean backstop goes to quiet.log, not events.log"
# 7. set-batch restarts the inner wait with --batch
bash "$WP" set-batch /tmp/bb >/dev/null
waitfor "$T/fake-args.log" '--batch /tmp/bb' 20; ok $? "set-batch: inner wait restarted with --batch /tmp/bb"
waitfor "$EV" 'batch changed'; ok $? "batch change is logged as an event line"
bash "$WP" set-batch none >/dev/null; sleep 4
tail -1 "$T/fake-args.log" | grep -q -- '--batch' ; [ $? = 1 ]; ok $? "set-batch none: --batch dropped again"
# 8. crash backoff: 3 crashes without output -> WAKER-ERROR event, daemon stays alive
for i in 1 2 3 4; do : > "$T/fq/crash"; sleep 3.5; done
waitfor "$EV" 'WAKER-ERROR' 30; ok $? "repeated inner crash is reported as WAKER-ERROR"
bash "$WP" status >/dev/null; ok $? "daemon survives inner crashes"
# 9. stale heartbeat reads as NOT-RUNNING (what the hook relies on)
bash "$WP" stop >/dev/null
bash "$WP" status >/dev/null; [ $? = 1 ]; ok $? "after stop: NOT-RUNNING and heartbeat removed"
printf 'pid=1 epoch=%s me=coordinator child=0 started=0\n' "$(( $(date +%s) - 400 ))" > "$T/waker/coordinator.hb"
bash "$WP" status >/dev/null; [ $? = 1 ]; ok $? "heartbeat 400 s old = NOT-RUNNING"
rm -f "$T/waker/coordinator.hb"
# 10. restart after stop works and history stays in the same file
bash "$WP" start >/dev/null 2>&1; bash "$WP" status >/dev/null; ok $? "restart after stop works"
bash "$WP" stop >/dev/null
# 11. REAL event-wait.sh through the daemon: a question in the inbox becomes an events.log line (detection reused, not copied)
unset WP_EVENTWAIT
printf 'ping from a peer: is the lane ok?\n' > "$T/inbox/coordinator/msg1.txt"
WP_FORCE=1 bash "$WP" start --poll 1 --no-health >/dev/null 2>&1
waitfor "$EV" 'EVENT INBOX msg1.txt: ping from a peer' 40; ok $? "real event-wait.sh: inbox question appended to events.log"
printf 'second: still there?\n' > "$T/inbox/coordinator/msg2.txt"
waitfor "$EV" 'EVENT INBOX msg2.txt' 40; ok $? "real event-wait.sh: next event arrives with no re-arm"
bash "$WP" stop >/dev/null
# 12. watch streams new lines (this is what Monitor reads)
export WP_EVENTWAIT="$T/fake-ew.sh"
( timeout 12 bash "$WP" watch > "$T/watch.out" 2>/dev/null & ) ; sleep 3
printf 'EVENT STATUS w FAILED: t\n' > "$T/fq/010"
waitfor "$T/watch.out" 'EVENT STATUS w FAILED' 20; ok $? "watch streams the new event line to stdout"
sleep 10; bash "$WP" stop >/dev/null
echo "SELFTEST waker-persist $pass pass / $fail fail"
[ "$fail" = 0 ]
