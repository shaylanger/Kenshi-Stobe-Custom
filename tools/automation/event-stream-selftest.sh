#!/usr/bin/env bash
# event-stream-selftest.sh : selftest of event-stream.sh (streaming waker). Sandbox KAH_RUNS, --no-health. WSL/bash. Prints SELFTEST PASS n/n.
# Covers: real event-wait.sh behind the loop (urgent now, batched DONE burst as separate lines without summary, loop keeps running across wakes),
# fake children (failing iteration survives, de-duplication, backstop dedupe, gap scan) and the clean exit on the stop file.
HERE=$(cd "$(dirname "$0")" && pwd)
ES="$HERE/event-stream.sh"
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
export KAH_RUNS="$BOX" EW_BATCH_SEC=4 ES_TICK=0.5 EW_ROLLCALL_CMD="echo ROLLCALL x kind=INPROC proc=n/a status_age=15m log_age=- latest=x"
IN="$BOX/inbox/coordinator"; mkdir -p "$BOX/agents" "$IN"
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (got '$2', want '$3')"; fi; }
status() { printf '2026-10-15 18:00 | %s | x\ntask: %s task\nstep: s\n' "$2" "$1" > "$BOX/agents/$1.status"; }
msg() { printf '%s' "$2" > "$IN/$1.msg"; }
reset() { rm -f "$BOX"/agents/*.status "$IN"/*.msg "$BOX/event-stream.stop"; rm -rf "$IN/delivered"; }
# start <out> [env...]: run the stream in the background
start() { local o=$1; shift; env "$@" bash "$ES" --no-health --poll 1 --backstop 40 --as event-wait > "$o" 2>&1 & SP=$!; sleep 2; }
stop() { touch "$BOX/event-stream.stop"; local i=0; while kill -0 "$SP" 2>/dev/null && [ $i -lt 12 ]; do sleep 1; i=$((i+1)); done
         if kill -0 "$SP" 2>/dev/null; then kill "$SP"; RC=stuck; else wait "$SP"; RC="rc$?"; fi; }
waitfor() { local f=$1 pat=$2 n=${3:-1} i=0; while [ "$(grep -c -E "$pat" "$f")" -lt "$n" ] && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done; }

# 1. real event-wait: urgent message streams at once, loop keeps running, a second wake streams again, no BATCH summary lines
reset; start "$BOX/o1"
T0=$(date +%s); msg a 'AGENT DEAD x : process gone'; waitfor "$BOX/o1" 'EVENT INBOX a.msg' 1; t=$(( $(date +%s) - T0 ))
ck 'urgent inbox streamed at once' "$([ "$t" -lt 6 ] && grep -q 'EVENT INBOX a.msg: AGENT DEAD x' "$BOX/o1" && echo now || echo "late:$t")" now
ck 'still running after the first wake' "$(kill -0 $SP 2>/dev/null && echo yes || echo no)" yes
msg b 'x FAILED to start?'; waitfor "$BOX/o1" 'EVENT INBOX b.msg' 1
ck 'second wake streamed by the same process' "$(grep -c 'EVENT INBOX b.msg' "$BOX/o1")" 1
status f1 FAILED; waitfor "$BOX/o1" 'EVENT STATUS f1 FAILED' 1
ck 'urgent FAILED status streamed with respawn hint' "$(grep -c 'EVENT STATUS f1 FAILED.*respawn fresh' "$BOX/o1")" 1
# 2. DONE burst: 3 DONE -> 3 lines after the window, one batch, no summary line, no repeats
status d1 DONE; sleep 1; status d2 DONE; sleep 1; status d3 DONE; sleep 1
ck 'DONE burst waits inside the window (nothing yet)' "$(grep -c 'EVENT STATUS d. DONE' "$BOX/o1")" 0
waitfor "$BOX/o1" 'EVENT STATUS d3 DONE' 1; sleep 1
ck 'DONE burst: 3 lines' "$(grep -c 'EVENT STATUS d. DONE' "$BOX/o1")" 3
ck 'no EVENT BATCH summary line' "$(grep -c 'EVENT BATCH' "$BOX/o1")" 0
sleep 7
ck 'DONE not repeated by later loops' "$(grep -c 'EVENT STATUS d. DONE' "$BOX/o1")" 3
stop; ck 'clean exit on stop file (rc 0)' "$RC" rc0
ck 'no leftover event-wait child' "$(pgrep -f "event-wait.sh --me coordinator --backstop 40" | wc -l | tr -d ' ')" 0

# 3. failing iterations never end the loop; dedupe; gap scan; backstop dedupe (fake child)
cat > "$BOX/fake.sh" <<'F'
#!/usr/bin/env bash
c=$(cat "$KAH_RUNS/count" 2>/dev/null || echo 0); c=$((c+1)); echo $c > "$KAH_RUNS/count"
case $c in
  1) exit 3;;                                                     # silent crash
  2) echo "boom"; exit 1;;                                        # crash with output
  3) echo "EVENT RIG rc=1 stall 12"; echo "EVENT BATCH 1 events over 0s"; exit 0;;
  4) echo "EVENT RIG rc=1 stall 99"; exit 0;;                     # same line modulo digits -> deduped
  5) sleep 1; printf '2026-10-15 18:00 | DONE | x\ntask: g1 task\n' > "$KAH_RUNS/agents/g1.status"; echo "EVENT INBOX z.msg: INFO later"; exit 0;;   # g1 DONE written during the run, not in the output -> gap scan
  6) printf 'EVENT BACKSTOP after 600s\nSWEEP QUEUE 5090 empty\nROLLCALL a x\n'; exit 0;;
  7) printf 'EVENT BACKSTOP after 600s\nSWEEP QUEUE 5090 empty\nROLLCALL a x\n'; exit 0;;   # same sweep line -> deduped
  8) printf 'EVENT BACKSTOP after 600s\nSWEEP CLEAN\n'; exit 0;;      # clean backstop -> silent
  *) sleep 600;;
esac
F
reset; rm -f "$BOX/count"; start "$BOX/o2" ES_CHILD="$BOX/fake.sh"; waitfor "$BOX/o2" 'EVENT STATUS g1 DONE' 1 ; sleep 14
ck 'failing iteration: loop survived (reached run >= 9)' "$([ "$(cat "$BOX/count")" -ge 9 ] && echo yes || echo "no:$(cat "$BOX/count")")" yes
ck 'failure announced once, not per retry' "$(grep -c 'EVENT STREAM child rc=' "$BOX/o2")" 1
ck 'RIG line printed once (duplicate suppressed)' "$(grep -c 'EVENT RIG' "$BOX/o2")" 1
ck 'BATCH summary dropped' "$(grep -c 'EVENT BATCH' "$BOX/o2")" 0
ck 'gap scan reports the status written during a run' "$(grep -c 'EVENT STATUS g1 DONE: task: g1 task' "$BOX/o2")" 1
ck 'child inbox line passed through' "$(grep -c 'EVENT INBOX z.msg' "$BOX/o2")" 1
ck 'backstop sweep line printed once' "$(grep -c 'EVENT SWEEP QUEUE 5090 empty' "$BOX/o2")" 1
ck 'ROLLCALL / SWEEP CLEAN / BACKSTOP header never printed' "$(grep -c -E 'ROLLCALL|SWEEP CLEAN|BACKSTOP' "$BOX/o2")" 0
stop; ck 'exit on stop file while the child sleeps' "$RC" rc0
ck 'no leftover fake child' "$(pgrep -f "$BOX/fake.sh" | wc -l | tr -d ' ')" 0
if [ "$fail" -gt 0 ]; then [ -n "${ES_DEBUG:-}" ] && { echo ---o2; cat "$BOX/o2"; }; echo "SELFTEST FAIL $fail (pass $pass)"; exit 1; fi
echo "SELFTEST PASS $pass/$pass"
