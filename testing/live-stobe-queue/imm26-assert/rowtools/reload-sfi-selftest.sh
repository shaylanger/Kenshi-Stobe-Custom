#!/usr/bin/env bash
# reload-sfi-selftest.sh (imm26-sfI): OFFLINE self-test of reloaddefs_sfi.sh / reload-run-sfi.sh (rows 26-d 26-dx 26-e on the hunt26a-scene ground). No game, ssh, WSL or DB: lanes are
# simulated by reloadfake_sfi.py (-> reloadfake.py -> tripfake.py -> fakelane.py) with scenarios from reloadscen_sfi.py (= reloadscen.py + the apology step). The checker is the unchanged
# reloadcheck_a.py, so every defect scenario asserts the EXACT failing-check set as in reload-selftest.sh. Prints `SELFTEST sfi-<name> PASS|FAIL` and `SELFTEST SFI ALL PASS|FAIL n/m`.
# Usage: bash rowtools/reload-sfi-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_FACTION RW_REFACTION RW_APOLOGY RW_GOATS RW_PIN_GOATS RW_OFFER2
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfi-$1 PASS ${3:-}"; else echo "SELFTEST sfi-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_sfi.sh"
PY="$ST_HERE/reload-py.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/reloadfake_sfi.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sfi"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sfi.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EVB="$KAH_ROWS_BASE/imm26-5090-i3/rows"
bad_set() {
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import reloadcheck_a as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
expect() {   # expect <name> <scenario> <row> <RESULT prefix> [FAIL: exact failing set | other: substring]
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ "$pre" = "RESULT $row FAIL" ]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}
lineno() { grep -n -- "$1" "$KAH_ROW_FAKE_LOG" | head -"${2:-1}" | tail -1 | cut -d: -f1; }
before() { local a b; a=$(lineno "$1" "${3:-1}"); b=$(lineno "$2" "${4:-1}"); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }

# --- verdicts: the same defect set as reload-selftest.sh, now through the hunt-scene recipes
expect 26-d-pass 26d-pass 26-d "RESULT 26-d PASS" "continuation_world_is_new_epoch=epoch-1->epoch-2"
expect 26-d-old-record-not-superseded 26d-old 26-d "RESULT 26-d FAIL" "continuation_record_exists,old_record_superseded"
expect 26-d-same-world-id 26d-samewid 26-d "RESULT 26-d FAIL" "continuation_world_is_new_epoch"
expect 26-d-accept-rejected-setup-fail 26d-reject 26-d "RESULT 26-d SETUP-FAIL" "requester_now_hostile"
expect 26-d-no-offer-setup-fail 26d-nooffer 26-d "RESULT 26-d SETUP-FAIL" "no Hunt proposal"
export RW_COMPLETE=1
expect 26-d-complete-pass 26d-complete 26-d "RESULT 26-d PASS" "hand_over_completed=completed"
expect 26-d-complete-not-completed 26d-nocomplete 26-d "RESULT 26-d FAIL" "hand_over_completed"
unset RW_COMPLETE
expect 26-dx-pass 26dx-pass 26-dx "RESULT 26-dx PASS" "no_new_grant_in_outbox"
expect 26-dx-continuation-of-cancelled 26dx-bad 26-dx "RESULT 26-dx FAIL" "no_active_record_after_reload,no_continuation_of_cancelled"
expect 26-e-pass 26e-pass 26-e "RESULT 26-e PASS" "yes_accepts_after_repropose"
expect 26-e-not-rebound 26e-notrebound 26-e "RESULT 26-e FAIL" "no_orphan_proposal_in_old_world,rebound_to_new_world,resume_state_recorded,yes_accepts_after_repropose"
expect 26-e-accept-rejected-setup-fail 26e-reject 26-e "RESULT 26-e SETUP-FAIL" "requester_now_hostile"

# --- scene gate: a blind NPC is SETUP-FAIL (never FAIL), one blind try is retried, no goats is SETUP-FAIL
expect scene-blind-setup-fail 26d-blind 26-d "RESULT 26-d SETUP-FAIL" "SCENE-BAD"
expect scene-blind-names-the-cause 26d-blind 26-d "RESULT 26-d SETUP-FAIL" "sees=0 for every goat"
expect scene-blind-then-sees-pass 26d-blind-then-sees 26-d "RESULT 26-d PASS" "continuation_world_is_new_epoch"
expect scene-no-goats-setup-fail 26d-nogoats 26-d "RESULT 26-d SETUP-FAIL" "no goats found"
scen 26d-blind; run 26-d $L >/dev/null; ! grep -q 'Look at all these goats' "$KAH_ROW_FAKE_LOG" && chk scene-blind-never-says-the-offer ok || chk scene-blind-never-says-the-offer bad
expect offer-fallback-wording 26d-fallback 26-d "RESULT 26-d PASS" "continuation_world_is_new_epoch"
scen 26d-fallback; run 26-d $L >/dev/null
grep -q "split the meat evenly" "$EVB/26-d/s1b/utterance.txt" 2>/dev/null && chk offer-fallback-used-once ok || chk offer-fallback-used-once bad

# --- recipe statements (fake-lane transcript of 26-d)
scen 26d-pass; run 26-d $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
grep -q 'delete from stobe_activity_record' "$F" && grep -q 'delete from stobe_activity_outbox' "$F" && chk activity-tables-cleaned ok || chk activity-tables-cleaned bad
grep -q "delete from eventlog where type in ('travel_agreement'" "$F" && chk trip-rows-cleaned ok || chk trip-rows-cleaned bad
! grep -q 'stobe-auto teleport .* -53200 957 4893' "$F" && chk no-quiet-scene-teleport-away ok || chk no-quiet-scene-teleport-away bad
grep -q 'teleport Shay -49400 1660 3625' "$F" && grep -q 'teleport "#2529907200/2" -49422 1661 3643' "$F" && chk e-ground-teleports ok || chk e-ground-teleports bad
grep -q 'stobe-auto relation "#2529907200/2" 50' "$F" && chk relation-50 ok || chk relation-50 bad
grep -q ' 60 friend' "$F" && chk haff-friend-60 ok || chk haff-friend-60 bad
grep -q 'stobe-auto spawn "wild goats" Herbivore at -49405 1664 3645 count 8 size 0.2' "$F" && ! grep -q 'near .* dist 7' "$F" && chk goats-spawned-at-not-near-dist7 ok || chk goats-spawned-at-not-near-dist7 bad
grep -q 'stobe-auto pin "#1840332032/3"' "$F" && grep -q 'stobe-auto pin "#3750854400/3"' "$F" && chk goats-pinned ok || chk goats-pinned bad
grep -q 'stobe-auto faction .#2529907200/2. .Traders Guild.' "$F" && chk npc-refactioned-traders-guild ok || chk npc-refactioned-traders-guild bad
grep -q 'It was a mistake, I' "$F" && chk apology-sent ok || chk apology-sent bad
before 'pin "#1840332032/3"' 'stobe-auto senses' && chk pin-before-senses ok || chk pin-before-senses bad
before 'stobe-auto faction' 'stobe-auto senses' && chk faction-before-senses ok || chk faction-before-senses bad
before 'stobe-auto senses' 'Look at all these goats' && chk senses-before-offer ok || chk senses-before-offer bad
before 'Look at all these goats' 'RECHAT_TIMING' && before 'RECHAT_TIMING' "Yes, let" && chk delivery-wait-between-offer-and-accept ok || chk delivery-wait-between-offer-and-accept bad
[ "$(grep -c 'stobe-auto spawn "wild goats"' "$F")" = 2 ] && chk goats-respawned-after-load ok || chk goats-respawned-after-load bad "$(grep -c 'wild goats' "$F")"
before 'stobe-auto save kah-imm26-rw-job-5090-i3' 'stobe-auto load kah-imm26-rw-job-5090-i3' && chk save-before-load ok || chk save-before-load bad
[ "$(grep -c 'teleport Shay -49400 1660 3625' "$F")" -ge 2 ] && chk shay-back-on-ground-after-load ok || chk shay-back-on-ground-after-load bad
before 'stobe-auto load kah-imm26-rw-job' 'stobe-auto spawn "wild goats"' 1 2 && before 'stobe-auto spawn "wild goats"' 'Are we still on that job' 2 1 && chk post-load-goats-before-resume-say ok || chk post-load-goats-before-resume-say bad
[ "$(grep -c 'stobe-auto faction' "$F")" = 1 ] && chk refaction-only-before-load ok || chk refaction-only-before-load bad
grep -q "Look at all these goats" "$EVB/26-d/s1/utterance.txt" && grep -q "Yes, let" "$EVB/26-d/s2/utterance.txt" && grep -q "Are we still on that job" "$EVB/26-d/s3/utterance.txt" && chk default-wording ok || chk default-wording bad
tail -1 "$EVB/26-d/scene_pre.txt" | grep -q '^SCENE-OK' && tail -1 "$EVB/26-d/scene_post.txt" | grep -q '^SCENE-OK' && chk scene-evidence-files ok || chk scene-evidence-files bad
# 26-dx / 26-e transcripts
scen 26dx-pass; run 26-dx $L >/dev/null
grep -q "Cancel that" "$EVB/26-dx/s2c/utterance.txt" && before 'Cancel that' 'stobe-auto save' && grep -q 'teleport "#2529907200/2" -49422 1661 3643' "$KAH_ROW_FAKE_LOG" && chk 26-dx-cancel-then-save-on-hunt-ground ok || chk 26-dx-cancel-then-save-on-hunt-ground bad
scen 26e-pass; run 26-e $L >/dev/null
before 'stobe-auto senses' 'Look at all these goats' && [ "$(grep -c 'stobe-auto spawn "wild goats"' "$KAH_ROW_FAKE_LOG")" = 2 ] && before 'RECHAT_TIMING' "Yes, let" && chk 26-e-hunt-ground-and-delivery ok || chk 26-e-hunt-ground-and-delivery bad
# env knobs
scen 26d-pass; RW_FACTION=Nameless run 26-d $L >/dev/null; grep -q 'stobe-auto faction .#2529907200/2. .Nameless.' "$KAH_ROW_FAKE_LOG" && chk env-faction-nameless ok || chk env-faction-nameless bad
scen 26d-pass; RW_REFACTION=0 run 26-d $L >/dev/null; ! grep -q 'stobe-auto faction' "$KAH_ROW_FAKE_LOG" && chk env-no-refaction ok || chk env-no-refaction bad
scen 26d-pass; RW_APOLOGY=0 run 26-d $L >/dev/null; ! grep -q 'mistake' "$KAH_ROW_FAKE_LOG" && chk env-no-apology ok || chk env-no-apology bad
scen 26d-pass; RW_GOATS=3 RW_PIN_GOATS=0 run 26-d $L >/dev/null; grep -q 'count 3 size 0.2' "$KAH_ROW_FAKE_LOG" && ! grep -q 'stobe-auto pin "#1840' "$KAH_ROW_FAKE_LOG" && chk env-goats-and-nopin ok || chk env-goats-and-nopin bad
scen 26d-pass; RW_EG_SHAY="1 2 3" RW_EG_NPC="4 5 6" RW_EG_GOAT="7 8 9" run 26-d $L >/dev/null; grep -q 'teleport Shay 1 2 3' "$KAH_ROW_FAKE_LOG" && grep -q 'at 7 8 9 count' "$KAH_ROW_FAKE_LOG" && chk env-ground-override ok || chk env-ground-override bad

# --- CLI: reload-run-sfi.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sfi.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
for r in 26-d 26-dx 26-e; do
  case $r in 26-d) sc=26d-pass;; 26-dx) sc=26dx-pass;; *) sc=26e-pass;; esac
  scen $sc; o=$(cli reload-run-sfi.sh $r $L --allow-retry selftest); rc=$?
  [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q "^RESULT $r PASS" && [ $rc = 0 ] && chk cli-$r ok || chk cli-$r bad "rc=$rc $(echo "$o" | cut -c1-300)"
done
scen 26d-nooffer; o=$(cli reload-run-sfi.sh 26-d $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen 26d-old; o=$(cli reload-run-sfi.sh 26-d $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
scen 26d-blind; o=$(cli reload-run-sfi.sh 26-d $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && echo "$o" | grep -q 'SCENE-BAD' && chk cli-scene-bad-exit-2 ok || chk cli-scene-bad-exit-2 bad "rc=$rc $(echo "$o" | cut -c1-200)"
o=$(cli reload-run-sfi.sh 26-f $L); echo "$o" | grep -q 'RESULT 26-f SETUP-FAIL not a hunt reload row' && chk cli-other-rows-refused ok || chk cli-other-rows-refused bad "$o"
scen 26d-pass; o=$(cli reload-run-sfi.sh 26-d $L --dry); echo "$o" | grep -q '^RESULT 26-d DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
scen 26d-pass; cli reload-run-sfi.sh 26-d $L --save my-save --allow-retry selftest >/dev/null; grep -q 'load my-save' "$KAH_ROW_FAKE_LOG" && chk cli-save-option ok || chk cli-save-option bad
scen 26d-pass; cli reload-run-sfi.sh 26-d $L --faction Nameless --no-apology --goats 4 --allow-retry selftest >/dev/null
grep -q 'faction .#2529907200/2. .Nameless.' "$KAH_ROW_FAKE_LOG" && ! grep -q mistake "$KAH_ROW_FAKE_LOG" && grep -q 'count 4 size' "$KAH_ROW_FAKE_LOG" && chk cli-scene-options ok || chk cli-scene-options bad

# --- originals untouched / not hooked
grep -q 'reloaddefs_sfi\|reload-run-sfi' "$ST_HERE/reloaddefs_a.sh" "$ST_HERE/reload-run.sh" "$ST_HERE/reload-py.sh" "$ST_HERE/reloadcheck_a.py" "$ST_HERE/reloaddefs_sfe.sh" "$ST_HERE/reload-run-sfe.sh" "$ST_HERE/reloaddefs_a2.sh" 2>/dev/null && chk originals-not-hooked bad || chk originals-not-hooked ok

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFI ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFI ALL FAIL $ok/$n"; exit 1; fi
