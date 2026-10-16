#!/usr/bin/env bash
# unblock_f_selftest.sh: OFFLINE self-test of the imm26-sfF rows 13-c / 13-c-neg (unblockdefs_f.sh / unblockcheck_f.py / unblockrun_f.sh / pywrap_uf.sh).
# No game, ssh, WSL or DB (lane simulated by unblockfake_f.py -> unblockfake_b.py -> ...; scenarios from unblockscen_f.py).
# Prints `SELFTEST uf-<name> PASS|FAIL` lines and `SELFTEST UNBLOCK-F ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_f_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
P=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json" UNBLOCK_B_DEBUG=1
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 TRIP_13C_TRIES=3
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_13C_NEG TRIP_13C_STAGE
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST uf-$1 PASS ${3:-}"; else echo "SELFTEST uf-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_b.sh"; . "$ST_HERE/unblockdefs_f.sh"
PY="$ST_HERE/pywrap_uf.sh"
lt_fake() { "$P" "$ST_HERE/unblockfake_f.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$P" "$ST_HERE/unblockscen_f.py" "$1" > "$FAKE_SCEN" || echo "SCENARIO ERROR $1" >&2; : > "$KAH_ROW_FAKE_LOG"; }
L=4080-i4
run() { gr_main --no-preflight --allow-retry selftest "$@" 2>/dev/null; }
# expect <name> <scenario> <row> <RESULT kind> <substring of the result line>
expect() { local name="$1" sc="$2" row="$3" kind="$4" has="$5" r; scen "$sc"; r=$(run "$row" $L)
  case "$r" in "RESULT $row $kind"*) if echo "$r" | grep -qF -- "$has"; then chk "$name" ok; else chk "$name" bad "missing '$has': $r"; fi;; *) chk "$name" bad "$r";; esac; }

# ---- 13-c (positive)
expect 13-c-pass f13c-pass 13-c PASS "sharedexp_kept_promise_row"
expect 13-c-pass-names-native-lines f13c-pass 13-c PASS "native: start=[10:00:00]_NATIVE_TRAVEL_START"
scen f13c-pass; run 13-c $L >/dev/null; F="$KAH_ROW_FAKE_LOG"; D="$KAH_ROWS_BASE/imm26-4080-i4/rows/13-c"
grep -q 're here. Thanks for the walk' "$F" && chk 13-c-sends-arrival-line ok || chk 13-c-sends-arrival-line bad
[ "$(grep -n -E 'stobe_ctxpush|re here' "$F" | tail -2 | head -1 | grep -c ctxpush)" = 1 ] && chk 13-c-ctxpush-right-before-arrival-line ok || chk 13-c-ctxpush-right-before-arrival-line bad
grep -q "order 'Cind \[Hungry Bandit\]'" "$F" && chk 13-c-no-harness-order-on-cind bad || chk 13-c-no-harness-order-on-cind ok
grep -q 'NATIVE_TRAVEL_START' "$D/native_travel.txt" 2>/dev/null && grep -q 'NATIVE_TRAVEL_FINISH' "$D/native_travel.txt" && chk 13-c-evidence-native_travel-start-finish ok || chk 13-c-evidence-native_travel-start-finish bad
grep -q '^end=ARRIVED ' "$D/arrival.txt" 2>/dev/null && chk 13-c-arrival-end-ARRIVED ok || chk 13-c-arrival-end-ARRIVED bad "$(cat "$D/arrival.txt" 2>/dev/null)"
expect 13-c-timeout-old-dll f13c-timeout-old-dll 13-c SETUP-FAIL "NC18 Stobe.dll"
scen f13c-timeout-old-dll; run 13-c $L >/dev/null; grep -q 're here' "$KAH_ROW_FAKE_LOG" && chk 13-c-timeout-sends-no-arrival-line bad || chk 13-c-timeout-sends-no-arrival-line ok
expect 13-c-timeout-with-native-lines f13c-timeout-native 13-c SETUP-FAIL "no native arrival"
expect 13-c-never-reconciled f13c-notreconciled 13-c SETUP-FAIL "did not reach COMPLETED"
scen f13c-notreconciled; run 13-c $L >/dev/null; [ "$(grep -c 're here' "$KAH_ROW_FAKE_LOG")" -ge 2 ] && chk 13-c-retries-one-more-turn ok || chk 13-c-retries-one-more-turn bad
expect 13-c-arrival-defect f13c-failed-defect 13-c SETUP-FAIL "arrival defect"

# ---- 13-c-neg
expect 13-c-neg-completed-no-row f13cneg-completed-pass 13-c-neg PASS "no_sharedexp_row_when_shay_far"
expect 13-c-neg-failed-no-row-is-setupfail f13cneg-failed-pass 13-c-neg SETUP-FAIL "negative award path was not exercised"
expect 13-c-neg-failed-but-row-is-FAIL f13cneg-failed-row 13-c-neg FAIL "no_sharedexp_row_when_trip_not_completed"
expect 13-c-neg-never-reconciled f13cneg-notreconciled 13-c-neg SETUP-FAIL "still ACCEPTED"
expect 13-c-neg-arrival-defect-not-a-disproof f13cneg-failed-defect 13-c-neg SETUP-FAIL "arrival defect"
scen f13cneg-failed-pass; run 13-c-neg $L >/dev/null; D="$KAH_ROWS_BASE/imm26-4080-i4/rows/13-c-neg"
grep -q "teleport Shay -62380 330 16250 dist 550" "$KAH_ROW_FAKE_LOG" && ! grep -q 'sleep 1.5' "$KAH_ROW_FAKE_LOG" && chk 13-c-neg-leaves-shay-behind ok || chk 13-c-neg-leaves-shay-behind bad
[ "$(grep -c "teleport Shay 'Cind" "$KAH_ROW_FAKE_LOG")" = 0 ] && chk 13-c-neg-never-moves-shay-onto-cind ok || chk 13-c-neg-never-moves-shay-onto-cind bad
grep -q 're here' "$KAH_ROW_FAKE_LOG" && chk 13-c-neg-sends-arrival-turn ok || chk 13-c-neg-sends-arrival-turn bad

# ---- runner + hygiene
bash "$ST_HERE/unblockrun_f.sh" 99-z 4080-i4 2>/dev/null | grep -q 'not a row of the sfF set' && chk runner-rejects-unknown-row ok || chk runner-rejects-unknown-row bad
bash "$ST_HERE/unblockrun_f.sh" 10-e 4080-i4 2>/dev/null | grep -q 'not a row of the sfF set' && chk runner-rejects-b-only-row ok || chk runner-rejects-b-only-row bad
cd "$A/.." && dd=$(git diff --name-only -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_b.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_b.py testing/live-stobe-queue/imm26-assert/rowtools/unblockrun_b.sh testing/live-stobe-queue/imm26-assert/rowtools/tripdefs.sh testing/live-stobe-queue/imm26-assert/rowtools/rowdefs.sh 2>/dev/null)
[ -z "$dd" ] && chk existing-files-untouched-by-sfF ok || chk existing-files-untouched-by-sfF bad "$dd"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-F ALL PASS $ok/$n"; else echo "SELFTEST UNBLOCK-F ALL FAIL $ok/$n"; fi
rm -rf "$T"
