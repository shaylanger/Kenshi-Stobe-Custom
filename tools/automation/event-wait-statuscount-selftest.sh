#!/usr/bin/env bash
# event-wait-statuscount-selftest.sh [candidate-script] : selftest of the status-count wake in event-wait.sh(.candidate) (WSL/bash).
# Sandbox KAH_RUNS with a pilot-1 shaped ledger; a status with the REAL first-pilot false counts must wake with `EVENT STATUS-COUNT`, a correct one must not
# (the wait ends on the backstop), and the same mismatch is reported once (seen-keyed). Prints SELFTEST PASS n/n.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EW="${1:-$HERE/event-wait.sh.candidate}"; [ -f "$EW" ] || EW="$HERE/event-wait.sh"
PYT="$HERE/status-count-check.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; total=0
ok() { total=$((total+1)); if [ "$2" = 1 ]; then pass=$((pass+1)); echo "ok   $1"; else echo "FAIL $1"; fi; }
run_ew() { KAH_RUNS="$T" EW_COUNT_EVERY=1 EW_QUIET_DONE=1 timeout 60 bash "$EW" --no-health --poll 1 --backstop 6 2>&1 | tr '\n' ' '; }
python3 -I "$PYT" --make-fixture "$T" BAD >/dev/null
sleep 1
out=$(run_ew)
case "$out" in *"EVENT STATUS-COUNT"*MISMATCH*"2 PASS"*) ok "false counts (2 PASS / 1 escalated) wake with EVENT STATUS-COUNT" 1;; *) ok "false counts wake: got [$out]" 0;; esac
out=$(run_ew)
case "$out" in *"EVENT STATUS-COUNT"*) ok "same mismatch not reported twice (seen-keyed)" 0;; *EVENT\ BACKSTOP*) ok "same mismatch not reported twice (seen-keyed)" 1;; *) ok "second run: got [$out]" 0;; esac
rm -f "$T/waker-seen.tsv"
python3 -I "$PYT" --make-fixture "$T" GOOD >/dev/null
sleep 1
out=$(run_ew)
case "$out" in *"STATUS-COUNT"*) ok "correct counts do not wake" 0;; *EVENT\ BACKSTOP*) ok "correct counts do not wake (backstop only)" 1;; *) ok "good run: got [$out]" 0;; esac
out=$(KAH_RUNS="$T" EW_COUNTCHECK=0 EW_COUNT_EVERY=1 timeout 60 bash "$EW" --no-health --poll 1 --backstop 4 2>&1 | tr '\n' ' ')
python3 -I "$PYT" --make-fixture "$T" BAD >/dev/null; rm -f "$T/waker-seen.tsv"; sleep 1
out=$(KAH_RUNS="$T" EW_COUNTCHECK=0 EW_COUNT_EVERY=1 timeout 60 bash "$EW" --no-health --poll 1 --backstop 4 2>&1 | tr '\n' ' ')
case "$out" in *"STATUS-COUNT"*) ok "EW_COUNTCHECK=0 switches the check off" 0;; *) ok "EW_COUNTCHECK=0 switches the check off" 1;; esac
echo "SELFTEST $([ $pass = $total ] && echo PASS || echo FAIL) $pass/$total"
[ $pass = $total ]
