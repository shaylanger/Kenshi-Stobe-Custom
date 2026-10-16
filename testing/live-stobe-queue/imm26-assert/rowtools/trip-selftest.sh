#!/usr/bin/env bash
# trip-selftest.sh: OFFLINE self-test of the trip-family rows (tripdefs.sh / rowcheck_trip.py / trip-run.sh / ko13b.sh). No game, ssh, WSL or DB:
# lanes are simulated by tripfake.py (+ fakelane.py) with synthetic scenarios from tripscen.py. Prints `SELFTEST trip-<name> PASS|FAIL` lines and
# `SELFTEST TRIP ALL PASS|FAIL n/m`.  Usage: bash rowtools/trip-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST trip-$1 PASS ${3:-}"; else echo "SELFTEST trip-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"
lt_fake() { "$PY" "$ST_HERE/tripfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip"; export FAKE_SCEN="$T/scen.json"; "$PY" "$ST_HERE/tripscen.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry "selftest" "$@" 2>/dev/null; }
L=5090-i3
# expect <check-name> <scenario> <row> <lane> <RESULT prefix> [must-contain]
expect() {
  local name="$1" sc="$2" row="$3" lane="$4" pre="$5" has="${6:-}" r
  scen "$sc"; r=$(run "$row" "$lane")
  case "$r" in
    "$pre"*) if [ -z "$has" ] || echo "$r" | grep -q -- "$has"; then chk "$name" ok; else chk "$name" bad "missing '$has' in: $r"; fi;;
    *) chk "$name" bad "$r";;
  esac
}

# --- new rows: PASS and the defect variants (each assertion can fail alone)
expect 23-a-pass 23a-pass 23-a $L "RESULT 23-a PASS" "one_completion_acknowledgement=n=1"
expect 23-a-fail 23a-fail 23-a $L "RESULT 23-a FAIL" "agreement_COMPLETED=FAILED"
expect 23-a-controller-left 23a-fail 23-a $L "RESULT 23-a FAIL" "no_follow_or_travel_controller"
expect 23-a-setup-fail-no-accept 23a-noaccept 23-a $L "RESULT 23-a SETUP-FAIL no ACCEPTED travel_agreement"
expect 23-a-lead-the-way-leg 23a-lead 23-a $L "RESULT 23-a PASS"
grep -q 'Lead the way\.' "$KAH_ROWS_BASE/imm26-5090-i3/rows/23-a/s2b/utterance.txt" 2>/dev/null && chk 23-a-s2b-said-lead-the-way ok || chk 23-a-s2b-said-lead-the-way bad
expect 23-a-fallback-wording 23a-fallback 23-a $L "RESULT 23-a PASS"
grep -q 'Would you lead me to Squin' "$KAH_ROWS_BASE/imm26-5090-i3/rows/23-a/s1b/utterance.txt" 2>/dev/null && chk 23-a-s1b-fallback-wording ok || chk 23-a-s1b-fallback-wording bad
expect 20-a-pass 20a-pass 20-a $L "RESULT 20-a PASS" "after_confirm_old_row_ended_or_replaced"
expect 20-a-fail 20a-fail 20-a $L "RESULT 20-a FAIL" "after_confirm_old_row_ended_or_replaced"
expect 20-a-s4b-second-confirm-pass 20a-s4b-pass 20-a $L "RESULT 20-a PASS" "after_confirm_old_row_ended_or_replaced"
grep -q 'Take me to the Stumble Inn' "$KAH_ROWS_BASE/imm26-5090-i3/rows/20-a/s4b/utterance.txt" 2>/dev/null && chk 20-a-s4b-said-second-confirm ok || chk 20-a-s4b-said-second-confirm bad
scen 20a-pass; run 20-a $L >/dev/null; [ -d "$KAH_ROWS_BASE/imm26-5090-i3/rows/20-a/s4b" ] && chk 20-a-no-s4b-when-s4-ended bad || chk 20-a-no-s4b-when-s4-ended ok
grep -q 'stobe_drawn sheathe Shay' "$KAH_ROW_FAKE_LOG" && chk quiet-sheathes-shay ok || chk quiet-sheathes-shay bad
expect 20-b-gated-order-replace 20b-gated 20-b $L "RESULT 20-b GATED" "native_order_identity_changed"
expect 20-b-pass-real-path-failure 20b-pass 20-b $L "RESULT 20-b PASS" "row_FAILED_after_forced_failure=FAILED"
expect 20-b-fail-no-failed-row 20b-nofail 20-b $L "RESULT 20-b FAIL" "row_FAILED_after_forced_failure"
expect 23-c-pass 23c-pass 23-c $L "RESULT 23-c PASS" "leave_to_squad_member_works"
expect 23-c-fail 23c-fail 23-c $L "RESULT 23-c FAIL" "leave_to_squad_member_works"
expect 23-d-pass 23d-pass 23-d $L "RESULT 23-d PASS" "unrelated_job_intact"
expect 23-d-fail-job-lost 23d-nojob 23-d $L "RESULT 23-d FAIL" "unrelated_job_intact"
expect 24-a-pass 24a-pass 24-a $L "RESULT 24-a PASS" "no_trip_row_for_mood_question"
expect 24-a-fail-trip-row 24a-fail 24-a $L "RESULT 24-a FAIL" "no_trip_row_for_mood_question"
expect 13-b-pass 13b-pass 13-b $L "RESULT 13-b PASS" "armed_N2_ABANDON_logged"
expect 13-b-fail-not-fired 13b-nofire 13-b $L "RESULT 13-b FAIL" "armed_N2_ABANDON_logged"
expect 13-b-fail-control-fired 13b-ctlfire 13-b $L "RESULT 13-b FAIL" "control_healthy_partner_no_N2_ABANDON"
expect 13-b-setup-fail-no-n2-watch 13b-noN2 13-b $L "RESULT 13-b SETUP-FAIL no N2_PROXIMITY"

# --- 08-d: topic first, trip, claim trigger
expect 08-d-pass 08d-pass 08-d $L "RESULT 08-d PASS" "topic_closed_outcome_completed"
expect 08-d-s0b-fallback 08d-s0b 08-d $L "RESULT 08-d PASS" "topic_closed_outcome_completed"
grep -q 'I want to sell my furs in Squin before winter\.' "$KAH_ROWS_BASE/imm26-5090-i3/rows/08-d/s0b/utterance.txt" 2>/dev/null && chk 08-d-s0b-wording ok || chk 08-d-s0b-wording bad
expect 08-d-fail-topic-still-open 08d-open 08-d $L "RESULT 08-d FAIL" "topic_closed_outcome_completed"
expect 08-d-fail-claim-row 08d-claim 08-d $L "RESULT 08-d FAIL" "no_situated_remark_claim_for_closed_topic"
expect 08-d-setup-fail-no-topic 08d-notopic 08-d $L "RESULT 08-d SETUP-FAIL no open personal_plan"
expect 08-d-setup-fail-no-claim-turn 08d-noticks 08-d $L "RESULT 08-d SETUP-FAIL trip COMPLETED and topic open, but no claim turn"
expect 08-d-setup-fail-trip-not-completed 08d-notrip 08-d $L "RESULT 08-d SETUP-FAIL the trip did not reach COMPLETED"
scen 08d-pass; run 08-d $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
n_s0=$(grep -n "stobe_say .* 'I need to sell my furs in Squin before winter\.'" "$F" | head -1 | cut -d: -f1); n_s1=$(grep -n "stobe_say .* 'Take me to Squin\.'" "$F" | head -1 | cut -d: -f1)
[ -n "$n_s0" ] && [ -n "$n_s1" ] && [ "$n_s0" -lt "$n_s1" ] && chk 08-d-topic-sentence-before-trip ok || chk 08-d-topic-sentence-before-trip bad "s0=$n_s0 s1=$n_s1"
grep -q 'stream.php' "$F" && chk 08-d-no-stream-by-default bad || chk 08-d-no-stream-by-default ok
scen 08d-pass; TRIP_08D_STREAM=1 run 08-d $L >/dev/null; grep -q 'stream.php?DATA=' "$KAH_ROW_FAKE_LOG" && grep -q 'optional=1' "$KAH_ROW_FAKE_LOG" && chk 08-d-stream-trigger-option ok || chk 08-d-stream-trigger-option bad

# --- 13-c: real walk -> sharedexp kept_promise row (identity/qualification outcomes named, negative leg)
expect 13-c-pass 13c-pass 13-c $L "RESULT 13-c PASS" "sharedexp_kept_promise_row"
expect 13-c-setup-fail-no-award-line 13c-noaward 13-c $L "RESULT 13-c SETUP-FAIL trip COMPLETED but no \"Participation award\""
expect 13-c-fail-empty-uid 13c-uid 13-c $L "RESULT 13-c FAIL" "empty_instance_uid_actor"
expect 13-c-setup-fail-unqualified-walk 13c-unqualified 13-c $L "RESULT 13-c SETUP-FAIL the walk did not qualify"
expect 13-c-setup-fail-trip-not-completed 13c-notcompleted 13-c $L "RESULT 13-c SETUP-FAIL the walked trip did not reach COMPLETED"
scen 13c-neg-pass; r=$(TRIP_13C_NEG=1 run 13-c $L); case "$r" in "RESULT 13-c PASS"*no_sharedexp_row_when_shay_far*) chk 13-c-neg-pass ok;; *) chk 13-c-neg-pass bad "$r";; esac
scen 13c-neg-fail; r=$(TRIP_13C_NEG=1 run 13-c $L); case "$r" in "RESULT 13-c FAIL"*no_sharedexp_row_when_shay_far*) chk 13-c-neg-fail ok;; *) chk 13-c-neg-fail bad "$r";; esac
scen 13c-pass; run 13-c $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
grep -q "teleport 'Cind \[Hungry Bandit\]' -62380 330 16250 dist 400" "$F" && chk 13-c-stages-cind-400-short-of-gate ok || chk 13-c-stages-cind-400-short-of-gate bad "$(grep -m3 'teleport' "$F")"
[ "$(grep -c "teleport Shay 'Cind \[Hungry Bandit\]'" "$F")" -ge 2 ] && grep -q 'sleep 1.5' "$F" && chk 13-c-shay-follows-cind ok || chk 13-c-shay-follows-cind bad
grep -q "order 'Cind \[Hungry Bandit\]'" "$F" && chk 13-c-no-harness-order-on-cind bad || chk 13-c-no-harness-order-on-cind ok
scen 13c-neg-pass; TRIP_13C_NEG=1 run 13-c $L >/dev/null; grep -q "teleport Shay -62380 330 16250 dist 550" "$KAH_ROW_FAKE_LOG" && ! grep -q 'sleep 1.5' "$KAH_ROW_FAKE_LOG" && chk 13-c-neg-leaves-shay-behind ok || chk 13-c-neg-leaves-shay-behind bad

# --- recipe statements: db clean, haff 60, quiet scene, KO sequence, never an IDLE order on the NPC outside 20-b
IDLE_CIND="order 'Cind \[Hungry Bandit\]' IDLE"
scen 23a-pass; run 23-a $L >/dev/null
F="$KAH_ROW_FAKE_LOG"
grep -q "delete from eventlog where type in ('travel_agreement','region_plan','situated_event','situated_remark_claim')" "$F" && chk db-clean-statement ok || chk db-clean-statement bad
grep -q 'haff.php' "$F" && grep -q ' 60 platonic' "$F" && chk haff-60-platonic ok || chk haff-60-platonic bad "$(grep -m2 haff "$F")"
grep -q 'stobe_ctxpush' "$F" && chk native-ctxpush ok || chk native-ctxpush bad
grep -q "teleport 'Cind \[Hungry Bandit\]' -62380 330 16250" "$F" && grep -q 'speed 3' "$F" && chk gate-teleport-and-follow ok || chk gate-teleport-and-follow bad
grep -q "$IDLE_CIND" "$F" && chk never-idle-cind-before-trip bad || chk never-idle-cind-before-trip ok
scen 20b-gated; run 20-b $L >/dev/null; grep -q "$IDLE_CIND" "$KAH_ROW_FAKE_LOG" && chk 20-b-forces-by-order-replace ok || chk 20-b-forces-by-order-replace bad
scen 20b-pass; TRIP_TRAP="1 2 3" run 20-b $L >/dev/null; grep -q "teleport 'Cind \[Hungry Bandit\]' 1 2 3" "$KAH_ROW_FAKE_LOG" && ! grep -q "$IDLE_CIND" "$KAH_ROW_FAKE_LOG" && chk 20-b-trap-method ok || chk 20-b-trap-method bad
scen 23d-pass; run 23-d $L >/dev/null; grep -q "job 'Cind \[Hungry Bandit\]' \"Copper Mine V\" task OPERATE_MACHINERY radius 2500" "$KAH_ROW_FAKE_LOG" && grep -q 'teleport Shay -54260 627 5890' "$KAH_ROW_FAKE_LOG" && chk 23-d-scene-and-job ok || chk 23-d-scene-and-job bad
scen 13b-pass; run 13-b $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
M="'Malzin[^']*'"
grep -q "protect $M off" "$F" && grep -q "ko $M 300" "$F" && grep -q "order $M IDLE" "$F" && grep -q "wake $M" "$F" && grep -q "protect $M on" "$F" && chk 13-b-ko-sequence ok || chk 13-b-ko-sequence bad
grep -q "$IDLE_CIND" "$F" && chk 13-b-leaver-never-idle bad || chk 13-b-leaver-never-idle ok

# --- wrapped existing rows keep their checks and gain the clean scene
scen 24a-pass; r=$(run 24-b $L); case "$r" in "RESULT 24-b FAIL"*region_plan_row*) chk 24-b-wrapped-still-checks ok;; *) chk 24-b-wrapped-still-checks bad "$r";; esac
grep -q "delete from eventlog where type in" "$KAH_ROW_FAKE_LOG" && grep -q ' 60 platonic' "$KAH_ROW_FAKE_LOG" && chk 24-b-wrapped-prep ok || chk 24-b-wrapped-prep bad
scen 23a-pass; r=$(run 19-a $L); case "$r" in "RESULT 19-a GATED reload leg"*|"RESULT 19-a FAIL"*|"RESULT 19-a PASS"*) chk 19-a-wrapped-runs ok;; *) chk 19-a-wrapped-runs bad "$r";; esac
declare -F _orig_rd_19a >/dev/null && chk wrap-keeps-original ok || chk wrap-keeps-original bad
. "$A/rowtools/tripdefs.sh"; scen 24a-pass; r=$(run 24-b $L); case "$r" in "RESULT 24-b FAIL"*) chk resource-no-recursion ok;; *) chk resource-no-recursion bad "$r";; esac

# --- CLI: trip-run.sh / ko13b.sh as separate processes (reload, preflight, agreements lines, ONE RESULT line, exit codes)
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$PY' '$ST_HERE/tripfake.py' \"\$@\"; }; export -f lt_fake; export PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen 23a-pass; o=$(cli trip-run.sh 23-a $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | grep -q '^AGREEMENTS 23-a 7009|COMPLETED' && echo "$o" | tail -1 | grep -q '^RESULT 23-a PASS' && [ $rc = 0 ] && chk cli-trip-run ok || chk cli-trip-run bad "rc=$rc $o"
grep -q "load kah-imm26-5090-ready" "$KAH_ROW_FAKE_LOG" && grep -q "order 'Cind \[Hungry Bandit\]' NULL_TASK" "$KAH_ROW_FAKE_LOG" && chk cli-reload-ready-save ok || chk cli-reload-ready-save bad
scen 23a-pass; o=$(cli trip-run.sh 23-a 5090-i4 --no-reload --allow-retry selftest); ! grep -q "stobe-auto load" "$KAH_ROW_FAKE_LOG" && chk cli-no-reload ok || chk cli-no-reload bad
scen 23a-pass; o=$(cli trip-run.sh 23-a 4080-i4 --allow-retry selftest); echo "$o" | grep -q 'RESULT 23-a SETUP-FAIL RELOAD-FAIL no ready save known' && chk cli-unknown-save-setup-fail ok || chk cli-unknown-save-setup-fail bad "$o"
scen 13b-pass; o=$(cli ko13b.sh $L --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 13-b PASS' && [ $rc = 0 ] && chk cli-ko13b ok || chk cli-ko13b bad "rc=$rc $o"
o=$(cli trip-run.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL row not ported' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
scen 23a-pass; o=$(cli trip-run.sh 23-a $L --dry); echo "$o" | grep -q '^RESULT 23-a DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
scen 23a-pass; cli trip-run.sh 23-a $L --dest Squin --gate "1 2 3" --accept "Sure, go on." --allow-retry selftest >/dev/null; grep -q "teleport 'Cind \[Hungry Bandit\]' 1 2 3" "$KAH_ROW_FAKE_LOG" && chk cli-options-pass-through ok || chk cli-options-pass-through bad

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST TRIP ALL PASS $ok/$n"; exit 0; else echo "SELFTEST TRIP ALL FAIL $ok/$n"; exit 1; fi
