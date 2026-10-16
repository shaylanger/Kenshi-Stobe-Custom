#!/usr/bin/env bash
# unblock_b_selftest.sh: OFFLINE self-test of the imm26-u-rowsB rows (unblockdefs_b.sh / unblockcheck_b.py / unblockrun_b.sh / pywrap_ub.sh): 13-c 13-c-neg 10-e 10-e-inproc 27-a.
# No game, ssh, WSL or DB (lane simulated by unblockfake_b.py -> reloadfake_b.py / reloadfake.py -> tripfake.py -> fakelane.py; scenarios from unblockscen_b.py).
# Prints `SELFTEST ub-<name> PASS|FAIL` lines and `SELFTEST UNBLOCK-B ALL PASS|FAIL n/m`.  Usage: bash rowtools/unblock_b_selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
P=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json" UNBLOCK_B_DEBUG=1
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 UB_10E_WAIT=3 TRIP_13C_TRIES=3
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_13C_NEG TRIP_13C_STAGE RW_BG_ARGS
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST ub-$1 PASS ${3:-}"; else echo "SELFTEST ub-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_b.sh"
PY="$ST_HERE/pywrap_ub.sh"
lt_fake() { "$P" "$ST_HERE/unblockfake_b.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$P" "$ST_HERE/unblockscen_b.py" "$1" > "$FAKE_SCEN" || echo "SCENARIO ERROR $1" >&2; : > "$KAH_ROW_FAKE_LOG"; }
L=4080-i4
run() { gr_main --no-preflight --allow-retry selftest "$@" 2>/dev/null; }
# expect <name> <scenario> <row> <RESULT kind> <substring of the result line>
expect() { local name="$1" sc="$2" row="$3" kind="$4" has="$5" r; scen "$sc"; r=$(run "$row" $L)
  case "$r" in "RESULT $row $kind"*) if echo "$r" | grep -qF -- "$has"; then chk "$name" ok; else chk "$name" bad "missing '$has': $r"; fi;; *) chk "$name" bad "$r";; esac; }

# ---- 13-c
expect 13-c-pass 13c-pass 13-c PASS "sharedexp_kept_promise_row"
expect 13-c-neg-pass 13c-neg-pass 13-c-neg PASS "no_sharedexp_row_when_shay_far"
expect 13-c-uid-fail 13c-uid 13-c FAIL "empty_instance_uid_actor"
expect 13-c-unqualified 13c-unqualified 13-c SETUP-FAIL "the walk did not qualify"
expect 13-c-arrival-defect ub13c-failed 13-c SETUP-FAIL "arrival defect"
grep -q 'I lead' /dev/null; r=$(cat "$KAH_ROWS_BASE/imm26-4080-i4/rows/13-c/arrival.txt" 2>/dev/null); case "$r" in "end=FAILED"*) chk 13-c-arrival-file-end-failed ok;; *) chk 13-c-arrival-file-end-failed bad "$r";; esac
scen 13c-pass; run 13-c $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
[ "$(grep -c "teleport Shay 'Cind \[Hungry Bandit\]'" "$F")" -ge 2 ] && grep -q 'sleep 1.5' "$F" && chk 13-c-shay-follows-cind ok || chk 13-c-shay-follows-cind bad
grep -q "order 'Cind \[Hungry Bandit\]'" "$F" && chk 13-c-no-harness-order-on-cind bad || chk 13-c-no-harness-order-on-cind ok
grep -q "teleport 'Cind \[Hungry Bandit\]' -62380 330 16250 dist 400" "$F" && chk 13-c-stages-400-short ok || chk 13-c-stages-400-short bad
[ -s "$KAH_ROWS_BASE/imm26-4080-i4/rows/13-c/walk_progress.txt" ] && chk 13-c-walk-progress-recorded ok || chk 13-c-walk-progress-recorded bad
scen 13c-neg-pass; run 13-c-neg $L >/dev/null; grep -q "teleport Shay -62380 330 16250 dist 550" "$KAH_ROW_FAKE_LOG" && ! grep -q 'sleep 1.5' "$KAH_ROW_FAKE_LOG" && chk 13-c-neg-leaves-shay-behind ok || chk 13-c-neg-leaves-shay-behind bad

# ---- 10-e
expect 10-e-restart-pass 10e-restart-pass 10-e PASS "real_later_load_same_campaign"
scen 10e-restart-pass; run 10-e $L >/dev/null
grep -q 'rig_stop' "$KAH_ROW_FAKE_LOG" && grep -q 'rig_launch kah-imm26-10e-4080-i4' "$KAH_ROW_FAKE_LOG" && chk 10-e-stops-then-launches-the-save ok || chk 10-e-stops-then-launches-the-save bad
grep -n -E 'rig_stop|rig_launch|repairprobe' "$KAH_ROW_FAKE_LOG" | head -4 | grep -q 'repairprobe' && chk 10-e-probe-before-restart ok || chk 10-e-probe-before-restart bad
grep -a -E 'repairprobe.php' "$KAH_ROW_FAKE_LOG" | grep -q -E 'INSERT|UPDATE|DELETE' && chk 10-e-probe-no-write bad || chk 10-e-probe-no-write ok
expect 10-e-restart-epoch-down-load-seq-up 10e-restart-epochdown 10-e PASS "load_seq 4->5"
expect 10-e-restart-epoch-down-no-seq-setupfail 10e-restart-epochdown-noseq 10-e SETUP-FAIL "no later load of the same campaign observed"
expect 10-e-session-never-changes 10e-restart-samesession 10-e SETUP-FAIL "no later load of the same campaign observed"
expect 10-e-launch-failed 10e-restart-launchfail 10-e SETUP-FAIL "launch did not return"
expect 10-e-scope-changed-still-fails 10e-restart-scopechanged 10-e FAIL "later_load_same_campaign_keeps_term_alive"
expect 10-e-inproc-record-only 10e-inproc-same 10-e-inproc SETUP-FAIL "RECORD-ONLY"
scen 10e-inproc-same; run 10-e-inproc $L >/dev/null; grep -q 'rig_stop' "$KAH_ROW_FAKE_LOG" && chk 10-e-inproc-never-restarts bad || chk 10-e-inproc-never-restarts ok
scen 10e-restart-pass; r=$(gr_main --no-preflight --allow-retry selftest 10-e 5090-i3 2>/dev/null); case "$r" in *"4080 lanes only"*) chk 10-e-restart-refused-on-5090 ok;; *) chk 10-e-restart-refused-on-5090 bad "$r";; esac

# ---- 27-a
expect 27-a-pass 27a-pass 27-a PASS "order_present_after_load"
expect 27-a-status-form-fallback 27a-formfallback 27-a PASS "first form"
expect 27-a-all-status-forms-fail-chase-proves 27a-allforms-fail 27-a PASS "order_present_after_load"
expect 27-a-order-lost 27a-lost 27-a FAIL "order_present_after_load"
expect 27-a-old-dll-honest-setup-fail 27a-nodll 27-a SETUP-FAIL "no contract-bodyguard"
expect 27-a-no-order 27a-noorder 27-a SETUP-FAIL "no BODYGUARD"
scen 27a-formfallback; run 27-a $L >/dev/null; [ "$(grep -c 'status_forms' /dev/null)" = 0 ]; [ "$(wc -l < "$KAH_ROWS_BASE/imm26-4080-i4/rows/27-a/status_forms.txt")" -ge 4 ] && chk 27-a-status-forms-logged ok || chk 27-a-status-forms-logged bad

# ---- runner + hygiene
bash "$ST_HERE/unblockrun_b.sh" 99-z 4080-i4 2>/dev/null | grep -q 'not a row of the u-rowsB set' && chk runner-rejects-unknown-row ok || chk runner-rejects-unknown-row bad
cd "$A/.." && dd=$(git diff --name-only -- testing/live-stobe-queue/imm26-assert/rowtools/rowdefs.sh testing/live-stobe-queue/imm26-assert/rowtools/tripdefs.sh testing/live-stobe-queue/imm26-assert/rowtools/reloaddefs_a.sh testing/live-stobe-queue/imm26-assert/rowtools/reloaddefs_b.sh 2>/dev/null)
[ -z "$dd" ] && chk existing-defs-untouched-by-u-rowsB ok || chk existing-defs-untouched-by-u-rowsB bad "$dd"
if [ "$ok" = "$n" ]; then echo "SELFTEST UNBLOCK-B ALL PASS $ok/$n"; else echo "SELFTEST UNBLOCK-B ALL FAIL $ok/$n"; fi
rm -rf "$T"
