#!/usr/bin/env bash
# reload-selftest.sh: OFFLINE self-test of the save+load resume rows, set A (reloaddefs_a.sh / reloadcheck_a.py / reload-run.sh / reload-cycle.sh / reload-py.sh).
# No game, ssh, WSL or DB: lanes are simulated by reloadfake.py (-> tripfake.py -> fakelane.py) with synthetic scenarios from reloadscen.py. For every defect scenario
# the EXACT set of failing checks is asserted (so each assertion is proven to fail alone). Prints `SELFTEST reload-<name> PASS|FAIL` lines and
# `SELFTEST RELOAD ALL PASS|FAIL n/m`.  Usage: bash rowtools/reload-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_20D_RESUME_FIRST RW_BG_ARGS
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST reload-$1 PASS ${3:-}"; else echo "SELFTEST reload-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"
PY="$ST_HERE/reload-py.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/reloadfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EVB="$KAH_ROWS_BASE/imm26-5090-i3/rows"
# bad_set <row> <evidence dir>: comma-joined sorted names of the failing checks (the checker run in-process with V.emit replaced)
bad_set() {
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import reloadcheck_a as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
# expect <name> <scenario> <row> <RESULT prefix> [FAIL: exact failing-check set (comma separated, sorted) | other: substring that must occur in the line]
expect() {
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in
    "$pre"*) ;;
    *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;;
  esac
  if [ "$pre" = "RESULT $row FAIL" ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}

# --- 26-d accepted Hunt
expect 26-d-pass 26d-pass 26-d "RESULT 26-d PASS" "continuation_world_is_new_epoch=epoch-1->epoch-2"
expect 26-d-old-record-not-superseded 26d-old 26-d "RESULT 26-d FAIL" "continuation_record_exists,old_record_superseded"
expect 26-d-same-world-id 26d-samewid 26-d "RESULT 26-d FAIL" "continuation_world_is_new_epoch"
expect 26-d-accept-rejected-setup-fail 26d-reject 26-d "RESULT 26-d SETUP-FAIL" "requester_now_hostile"
expect 26-d-no-offer-setup-fail 26d-nooffer 26-d "RESULT 26-d SETUP-FAIL" "no Hunt proposal"
export RW_COMPLETE=1
expect 26-d-complete-pass 26d-complete 26-d "RESULT 26-d PASS" "hand_over_completed=completed"
expect 26-d-complete-not-completed 26d-nocomplete 26-d "RESULT 26-d FAIL" "hand_over_completed"
unset RW_COMPLETE
# --- 26-dx cancelled stays cancelled
expect 26-dx-pass 26dx-pass 26-dx "RESULT 26-dx PASS" "no_new_grant_in_outbox"
expect 26-dx-continuation-of-cancelled 26dx-bad 26-dx "RESULT 26-dx FAIL" "no_active_record_after_reload,no_continuation_of_cancelled"
# --- 26-e proposal
expect 26-e-pass 26e-pass 26-e "RESULT 26-e PASS" "yes_accepts_after_repropose"
expect 26-e-not-rebound 26e-notrebound 26-e "RESULT 26-e FAIL" "no_orphan_proposal_in_old_world,rebound_to_new_world,resume_state_recorded,yes_accepts_after_repropose"
expect 26-e-accept-rejected-setup-fail 26e-reject 26-e "RESULT 26-e SETUP-FAIL" "requester_now_hostile"
# --- 26-f ClearGroup (camp variant shares the checker)
RW_KIND=ClearGroup expect 26-f-pass 26f-pass 26-f "RESULT 26-f PASS" "continuation_world_is_new_epoch"
# --- 24-c area-goal trip
expect 24-c-pass 24c-pass 24-c "RESULT 24-c PASS" "post_load_regional_goal_kept"
expect 24-c-no-region-setup-fail 24c-noregion 24-c "RESULT 24-c SETUP-FAIL" "regional_goal"
expect 24-c-trip-lost 24c-lost 24-c "RESULT 24-c FAIL" "exactly_one_post_load_OWNED_TRAVEL_accepted,phase_interrupted_by_load,phase_requested_after_interrupt,post_load_no_PROPOSED_FAILED_ENDED,post_s5_first_order_MOVE_CUS_ORDERED"
expect 24-c-regional-goal-dropped 24c-goalgone 24-c "RESULT 24-c FAIL" "post_load_regional_goal_kept"
# --- 23-e legacy follow
expect 23-e-pass 23e-pass 23-e "RESULT 23-e PASS" "follow_ticks_after_load"
expect 23-e-follow-lost 23e-lost 23-e "RESULT 23-e FAIL" "follow_ticks_after_load,post_load_follower_closes_distance"
expect 23-e-no-follow-setup-fail 23e-nopre 23-e "RESULT 23-e SETUP-FAIL" "FOLLOW target resolved"
# --- 27-a bodyguard
expect 27-a-pass 27a-pass 27-a "RESULT 27-a PASS" "order_present_after_load"
expect 27-a-order-lost 27a-lost 27-a "RESULT 27-a FAIL" "order_present_after_load,post_load_bodyguard_closes_distance"
expect 27-a-no-order-setup-fail 27a-noorder 27-a "RESULT 27-a SETUP-FAIL" "no BODYGUARD"
expect 27-a-status-error-hire-proof-passes 27a-statuserr 27-a "RESULT 27-a PASS" "order_present_after_load"
expect 27-a-status-error-and-no-chase-fails 27a-statuserr-lost 27-a "RESULT 27-a FAIL" "order_present_after_load,post_load_bodyguard_closes_distance"
# 27A-FIX: bodyguard stand-off 50-67 u passes (<= RW_BG_NEAR 100), control chase + 200 u away
expect 27-a-control-approaches-setup-fail 27a-ctrl-approaches 27-a "RESULT 27-a SETUP-FAIL" "without a contract"
expect 27-a-pre-leg-never-closes 27a-pre-wander 27-a "RESULT 27-a FAIL" "pre_load_bodyguard_follows"
expect 27-a-standoff-edge-passes 27a-post-standoff-edge 27-a "RESULT 27-a PASS" "order_present_after_load"
scen 27a-pass; r=$(RW_BG_NEAR=35 run 27-a $L); case "$r" in "RESULT 27-a FAIL"*) chk 27-a-old-limit-35-fails-the-stand-off ok;; *) chk 27-a-old-limit-35-fails-the-stand-off bad "$r";; esac
scen 27a-pass; run 27-a $L >/dev/null
[ "$(grep -c 'teleport Shay -50770 ' "$KAH_ROW_FAKE_LOG")" -ge 3 ] && chk 27-a-three-chases-200u-away ok || chk 27-a-three-chases-200u-away bad "$(grep -c 'teleport Shay' "$KAH_ROW_FAKE_LOG")"
[ "$(grep -n 'teleport Shay -' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n 'contract-bodyguard .* Shay hours' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" ] && chk 27-a-control-chase-before-hire ok || chk 27-a-control-chase-before-hire bad
[ -s "$EVB/27-a/chase_ctrl.txt" ] && chk 27-a-chase-ctrl-written ok || chk 27-a-chase-ctrl-written bad
scen 27a-pass; r=$(RW_AWAY_BG=150 run 27-a $L >/dev/null; grep -c 'teleport Shay -50820 ' "$KAH_ROW_FAKE_LOG"); [ "$r" -ge 3 ] && chk 27-a-away-env-override ok || chk 27-a-away-env-override bad "$r"
# --- 08-e follow-up topic
expect 08-e-pass 08e-pass 08-e "RESULT 08-e PASS" "claimed_once_after_reload"
expect 08-e-topic-lost 08e-lost 08-e "RESULT 08-e FAIL" "topic_survives_load"
expect 08-e-no-claim-setup-fail 08e-noclaim 08-e "RESULT 08-e SETUP-FAIL" "no bored tick claimed"
expect 08-e-no-claim-no-speaker-ticks 08e-noclaim-noticks 08-e "RESULT 08-e SETUP-FAIL" "NO tick with the NPC as speaker"
expect 08-e-claimed-twice 08e-double 08-e "RESULT 08-e FAIL" "claimed_once_after_reload"
# --- 20-d pending plan change
expect 20-d-pass 20d-pass 20-d "RESULT 20-d PASS" "pending_change_survives_load"
expect 20-d-no-pending-setup-fail 20d-nopending 20-d "RESULT 20-d SETUP-FAIL" "pending plan change"
expect 20-d-pending-lost 20d-lost 20-d "RESULT 20-d FAIL" "bare_yes_after_reload_ends_old_or_replaces,pending_change_survives_load"

# --- recipe statements (fake-lane transcript)
scen 26d-pass; run 26-d $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
grep -q 'delete from stobe_activity_record' "$F" && grep -q 'delete from stobe_activity_outbox' "$F" && chk activity-tables-cleaned-first ok || chk activity-tables-cleaned-first bad
grep -q "delete from eventlog where type in ('travel_agreement'" "$F" && chk trip-rows-cleaned ok || chk trip-rows-cleaned bad
grep -q ' 60 platonic' "$F" && chk haff-60-platonic ok || chk haff-60-platonic bad
grep -q 'stobe-auto spawn "wild goats" "Herbivore" near' "$F" && chk goat-fixture-spawned ok || chk goat-fixture-spawned bad
[ "$(grep -c 'stobe-auto spawn "wild goats"' "$F")" = 2 ] && chk goats-respawned-before-post-load-say ok || chk goats-respawned-before-post-load-say bad "$(grep -c 'wild goats' "$F")"
grep -q 'stobe-auto save kah-imm26-rw-job-5090-i3' "$F" && grep -q 'stobe-auto load kah-imm26-rw-job-5090-i3' "$F" && chk save-then-load-same-name ok || chk save-then-load-same-name bad
[ "$(grep -n 'stobe-auto save' "$F" | head -1 | cut -d: -f1)" -lt "$(grep -n 'stobe-auto load' "$F" | head -1 | cut -d: -f1)" ] && chk save-before-load ok || chk save-before-load bad
grep -q "Let's hunt for raw meat" "$EVB/26-d/s1/utterance.txt" && grep -q "Yes, let's do it" "$EVB/26-d/s2/utterance.txt" && chk default-offer-accept-wording ok || chk default-offer-accept-wording bad
scen 26d-pass; RW_OFFER="Hunt them." RW_ACCEPT="Go." run 26-d $L >/dev/null
grep -q 'Hunt them\.' "$EVB/26-d/s1/utterance.txt" && grep -q '^Go\.' "$EVB/26-d/s2/utterance.txt" && chk env-offer-accept-override ok || chk env-offer-accept-override bad
scen 26f-pass; RW_KIND=ClearGroup run 26-f $L >/dev/null
grep -q 'Bandit Raiders (weakened) 1' "$KAH_ROW_FAKE_LOG" && chk 26-f-camp-fixture-spawned ok || chk 26-f-camp-fixture-spawned bad
scen 26d-pass; RW_SPAWN_CMD='stobe-auto spawn custom here' run 26-d $L >/dev/null
grep -q 'stobe-auto spawn custom here' "$KAH_ROW_FAKE_LOG" && ! grep -q 'wild goats' "$KAH_ROW_FAKE_LOG" && chk spawn-cmd-override ok || chk spawn-cmd-override bad
scen 23e-pass; run 23-e $L >/dev/null
[ "$(grep -c 'stobe-auto teleport Shay -\?[0-9]' "$KAH_ROW_FAKE_LOG")" -ge 2 ] && grep -q 'order Shay HOLD_POSITION' "$KAH_ROW_FAKE_LOG" && chk 23-e-shay-moved-away-twice ok || chk 23-e-shay-moved-away-twice bad
scen 27a-pass; run 27-a $L >/dev/null
grep -q 'contract-bodyguard .* Shay hours 24 own' "$KAH_ROW_FAKE_LOG" && chk 27-a-contract-command ok || chk 27-a-contract-command bad
scen 27a-pass; RW_BG_ARGS="hours 6" run 27-a $L >/dev/null
grep -q 'Shay hours 6' "$KAH_ROW_FAKE_LOG" && chk 27-a-bg-args-override ok || chk 27-a-bg-args-override bad

# --- CLI: reload-run.sh / reload-cycle.sh as separate processes
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen 26d-pass; o=$(cli reload-run.sh 26-d $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && echo "$o" | grep -q '^RECORDS 26-d act_post.txt ' && [ $rc = 0 ] && chk cli-reload-run ok || chk cli-reload-run bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q "load kah-imm26-5090-ready" "$KAH_ROW_FAKE_LOG" && chk cli-reload-ready-save ok || chk cli-reload-ready-save bad
scen 26d-pass; o=$(cli reload-run.sh 26-d $L --no-reload --allow-retry selftest); ! grep -q "kah-imm26-5090-ready" "$KAH_ROW_FAKE_LOG" && chk cli-no-reload ok || chk cli-no-reload bad
scen 26d-pass; o=$(cli reload-run.sh 26-d 4080-i4 --allow-retry selftest); echo "$o" | grep -q 'RESULT 26-d SETUP-FAIL RELOAD-FAIL' && chk cli-unknown-save-setup-fail ok || chk cli-unknown-save-setup-fail bad "$(echo "$o" | cut -c1-300)"
scen 26d-pass; o=$(cli reload-run.sh 26-d $L --dry); echo "$o" | grep -q '^RESULT 26-d DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
scen 26d-reject; o=$(cli reload-run.sh 26-d $L --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 26-d SETUP-FAIL' && [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen 26d-old; o=$(cli reload-run.sh 26-d $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
o=$(cli reload-run.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not a reload row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
scen 26d-complete; o=$(cli reload-run.sh 26-d $L --complete --allow-retry selftest); echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS.*hand_over_completed' && chk cli-complete-flag ok || chk cli-complete-flag bad "$(echo "$o" | tail -1 | cut -c1-300)"
scen 26e-pass; o=$(cli reload-run.sh 26-e $L --save my-save --allow-retry selftest); grep -q 'load my-save' "$KAH_ROW_FAKE_LOG" && chk cli-save-option ok || chk cli-save-option bad
scen 20d-pass; o=$(cli reload-run.sh 20-d $L --alt "Squin Hub" --allow-retry selftest); echo "$o" | tail -1 | grep -q 'RESULT 20-d' && chk cli-20d-alt-option ok || chk cli-20d-alt-option bad
scen 26d-pass; o=$(cli reload-cycle.sh $L my-cycle); rc=$?; echo "$o" | tail -1 | grep -q '^RELOAD-CYCLE 5090-i3 my-cycle PASS' && [ $rc = 0 ] && chk cli-reload-cycle ok || chk cli-reload-cycle bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'stobe-auto save my-cycle' "$KAH_ROW_FAKE_LOG" && grep -q 'stobe-auto load my-cycle' "$KAH_ROW_FAKE_LOG" && chk cli-reload-cycle-save-load ok || chk cli-reload-cycle-save-load bad
o=$(cli reload-cycle.sh nolane); echo "$o" | grep -q 'RELOAD-CYCLE nolane - FAIL' && chk cli-reload-cycle-unknown-lane ok || chk cli-reload-cycle-unknown-lane bad "$o"

# --- the shim passes other commands through; rowdefs.sh / tripdefs.sh are not hooked to this set
"$ST_HERE/reload-py.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
grep -q 'rd_26d\|reloaddefs' "$ST_HERE/rowdefs.sh" "$ST_HERE/tripdefs.sh" 2>/dev/null && chk originals-not-hooked bad "rowdefs/tripdefs reference reloaddefs" || chk originals-not-hooked ok

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST RELOAD ALL PASS $ok/$n"; exit 0; else echo "SELFTEST RELOAD ALL FAIL $ok/$n"; exit 1; fi
