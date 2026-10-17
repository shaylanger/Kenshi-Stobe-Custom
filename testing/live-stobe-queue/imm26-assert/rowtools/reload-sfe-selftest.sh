#!/usr/bin/env bash
# reload-sfe-selftest.sh (imm26-sfE2): OFFLINE self-test of reloaddefs_sfe.sh / reloadcheck_sfe.py / seed24c.py / reload-run-sfe.sh / reload-py-sfe.sh.
# No game, ssh, WSL or DB: lanes are simulated by reloadfake_sfe.py (-> reloadfake.py -> tripfake.py -> fakelane.py) with scenarios from reloadscen_sfe.py. Every defect scenario
# asserts the EXACT set of failing checks. Prints `SELFTEST sfe-<name> PASS|FAIL` and `SELFTEST SFE ALL PASS|FAIL n/m`.  Usage: bash rowtools/reload-sfe-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RS_REGION RW_FACTION RW_REFACTION RW_BANDITS
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfe-$1 PASS ${3:-}"; else echo "SELFTEST sfe-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_sfe.sh"
PY="$ST_HERE/reload-py-sfe.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/reloadfake_sfe.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sfe.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=5090-i3
EVB="$KAH_ROWS_BASE/imm26-5090-i3/rows"
bad_set() {   # comma-joined sorted failing check names (checker in-process, V.emit replaced)
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import reloadcheck_sfe as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.SeededV.emit = c.rc.V.emit
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
expect() {   # expect <name> <scenario> <row> <RESULT prefix> [exact failing set | substring]
  local name="$1" sc="$2" row="$3" pre="$4" want="${5-}" r ev got
  scen "$sc"; r=$(run "$row" "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [[ "$pre" == *" FAIL" ]]; then
    ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set "$row" "$ev")
    [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
  elif [ -n "$want" ]; then
    echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"
  else chk "$name" ok; fi
}

# --- seed24c.py against REAL server data (plan_hash recompute must reproduce the stored hash)
real=0; realok=0
for f in /c/KenshiTestRuns/*/rows/19-*/agr_pre.txt /mnt/c/KenshiTestRuns/*/rows/19-*/agr_pre.txt; do
  [ -s "$f" ] || continue; real=$((real+1))
  "$REAL_PY" -I "$ST_HERE/seed24c.py" "$f" "$T/seedreal" 2>/dev/null | grep -q '^SEED-OK' && realok=$((realok+1))
done
if [ "$real" = 0 ]; then chk seed-real-rows-hash-recompute ok "skipped: no real 19-* agr_pre.txt on this machine"
elif [ "$realok" = "$real" ]; then chk seed-real-rows-hash-recompute ok "$realok/$real real rows"
else chk seed-real-rows-hash-recompute bad "$realok/$real real rows"; fi

# --- 24-c recipe A (SEEDED)
expect 24-c-pass a24c-pass 24-c "RESULT 24-c PASS" "SEEDED regional_goal (resume leg only; row stays PARTIAL"
expect 24-c-pass-has-checks a24c-pass 24-c "RESULT 24-c PASS" "post_load_regional_goal_kept"
expect 24-c-pass-seeded-newest a24c-pass 24-c "RESULT 24-c PASS" "seeded_row_is_newest_pre_load"
expect 24-c-regional-goal-dropped a24c-goalgone 24-c "RESULT 24-c FAIL" "post_load_regional_goal_kept"
expect 24-c-trip-lost a24c-lost 24-c "RESULT 24-c FAIL" "exactly_one_post_load_OWNED_TRAVEL_accepted,phase_interrupted_by_load,phase_requested_after_interrupt,post_load_no_PROPOSED_FAILED_ENDED,post_s5_first_order_MOVE_CUS_ORDERED"
expect 24-c-hash-mismatch-refuses-seed a24c-hashbad 24-c "RESULT 24-c SETUP-FAIL" "plan_hash recompute mismatch"
expect 24-c-no-native-trip-setup-fail a24c-noown 24-c "RESULT 24-c SETUP-FAIL" "regional_goal seed missing"
expect 24-c-insert-failed-setup-fail a24c-insertfail 24-c "RESULT 24-c SETUP-FAIL" "regional_goal seed missing"
scen a24c-pass; r=$(run 24-c $L)
echo "$r" | grep -q '^RESULT 24-c [A-Z-]* SEEDED' && chk 24-c-seeded-marker-first ok || chk 24-c-seeded-marker-first bad "$(echo "$r" | cut -c1-160)"
scen a24c-hashbad; r=$(run 24-c $L); echo "$r" | grep -q '^RESULT 24-c SETUP-FAIL SEEDED' && chk 24-c-seeded-marker-on-setup-fail ok || chk 24-c-seeded-marker-on-setup-fail bad "$(echo "$r" | cut -c1-160)"
F="$KAH_ROW_FAKE_LOG"
scen a24c-pass; run 24-c $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
grep -q "insert into eventlog(type,data,sess,gamets,localts,ts,people,location,geo,utterance_id,delivery_state) select type,\$imm26seed\$travel-v1:1:2:" "$F" && chk 24-c-insert-clones-newest-row ok || chk 24-c-insert-clones-newest-row bad
grep -q 'where rowid=95 and' "$F" && chk 24-c-insert-source-is-newest-trip-row ok || chk 24-c-insert-source-is-newest-trip-row bad
grep -q '"kind":"same_route"' "$F" && grep -q '"seeded":true' "$F" && chk 24-c-insert-has-kind-and-seeded ok || chk 24-c-insert-has-kind-and-seeded bad
[ "$(grep -n 'insert into eventlog' "$F" | head -1 | cut -d: -f1)" -lt "$(grep -n 'stobe-auto save kah-imm26-rw-area' "$F" | head -1 | cut -d: -f1)" ] && chk 24-c-seed-before-save ok || chk 24-c-seed-before-save bad
grep -q 'stobe-auto save kah-imm26-rw-area-5090-i3' "$F" && grep -q 'stobe-auto load kah-imm26-rw-area-5090-i3' "$F" && chk 24-c-save-then-load ok || chk 24-c-save-then-load bad
grep -q "Where were we going" "$EVB/24-c/s4/utterance.txt" && grep -q "right behind you" "$EVB/24-c/s5/utterance.txt" && chk 24-c-resume-wording ok || chk 24-c-resume-wording bad
grep -q "Walk with me to Stumble Inn" "$EVB/24-c/s1/utterance.txt" && ! grep -rqi "toward Vain\|consider Vain" "$EVB/24-c"/s*/utterance.txt && chk 24-c-no-region-chat-utterances ok || chk 24-c-no-region-chat-utterances bad
scen a24c-pass; RS_REGION="Rust Plains" run 24-c $L >/dev/null; grep -q '"region":"Rust Plains"' "$KAH_ROW_FAKE_LOG" && chk 24-c-region-env ok || chk 24-c-region-env bad

# --- 26-f ClearGroup one-call
RW_KIND= expect 26-f-pass f26-pass 26-f "RESULT 26-f PASS" "continuation_world_is_new_epoch"
expect 26-f-retry-second-wording f26-retry 26-f "RESULT 26-f PASS" "terms_identical"
expect 26-f-no-offer-setup-fail f26-nooffer 26-f "RESULT 26-f SETUP-FAIL" "no ClearGroup proposal"
expect 26-f-scene-bad-setup-fail f26-scenebad 26-f "RESULT 26-f SETUP-FAIL" "ClearGroup scene not ready"
expect 26-f-no-camp-setup-fail f26-nocamp 26-f "RESULT 26-f SETUP-FAIL" "campZone.candidateId"
expect 26-f-accept-rejected-setup-fail f26-reject 26-f "RESULT 26-f SETUP-FAIL" "requester_now_hostile"
expect 26-f-targets-changed f26-targets-changed 26-f "RESULT 26-f FAIL" "terms_identical"
expect 26-f-continuation-lost f26-lost 26-f "RESULT 26-f FAIL" "continuation_record_exists,old_record_superseded"
# fix26fcamp: the continuation carries a NEW world-scoped camp zone; the old zone kept = FAIL, zone dropped = FAIL, scene lost across the load = SETUP-FAIL (never a product result)
expect 26-f-zone-not-rebound f26-zone-same 26-f "RESULT 26-f FAIL" "camp_zone_rebound"
expect 26-f-zone-dropped f26-zone-dropped 26-f "RESULT 26-f FAIL" "camp_zone_rebound,terms_identical"
expect 26-f-scene-lost-setup-fail f26-scenelost 26-f "RESULT 26-f SETUP-FAIL" "scene lost across the save/load"
scen f26-pass; run 26-f $L >/dev/null; RS="$EVB/26-f/reseat.txt"
grep -q '^probe chars600:' "$RS" && grep -q '^probe relation .* -100:' "$RS" && [ "$(grep -c '^probe where ' "$RS")" = 4 ] && tail -1 "$RS" | grep -q '^RESEAT-OK 4 of 4' && chk 26-f-probe-evidence-reseat-ok ok || chk 26-f-probe-evidence-reseat-ok bad "$(tail -3 "$RS" 2>/dev/null | cut -c1-200)"
scen f26-scenelost; run 26-f $L >/dev/null; tail -1 "$EVB/26-f/reseat.txt" | grep -q '^SCENE-LOST only 1 of 4' && chk 26-f-probe-scene-lost-line ok || chk 26-f-probe-scene-lost-line bad "$(tail -1 "$EVB/26-f/reseat.txt" | cut -c1-200)"
scen f26-pass; run 26-f $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
grep -q 'stobe-auto faction' "$F" && chk 26-f-cind-into-player-faction ok || chk 26-f-cind-into-player-faction bad
grep -q 'stobe-auto spawn "Dust Bandit" "Dust Bandits" at -47335 725 -55640 count 4' "$F" && ! grep -q 'Bandit Raiders' "$F" && chk 26-f-plain-dust-bandits-not-raiders ok || chk 26-f-plain-dust-bandits-not-raiders bad
! grep -q -- '-53200 957 4893' "$F" && chk 26-f-no-quiet-scene-teleport-away ok || chk 26-f-no-quiet-scene-teleport-away bad
grep -q 'teleport "#3000000001/1" -47341 725 -55624' "$F" && grep -q 'teleport "#3000000004/1" -47329 725 -55624' "$F" && chk 26-f-bandits-north-of-wall-spread ok || chk 26-f-bandits-north-of-wall-spread bad
[ "$(grep -c 'pin "#3000000001/1"$\|pin "#3000000001/1" </dev/null | head -1$' "$F")" -ge 1 ] && chk 26-f-bandits-pinned ok || chk 26-f-bandits-pinned bad
[ "$(grep -c 'teleport "#3000000001/7" -47341 725 -55624' "$F")" -ge 1 ] && chk 26-f-same-serials-reseated-after-load ok || chk 26-f-same-serials-reseated-after-load bad
grep -q 'stobe-auto relation .*-100' "$F" && grep -q 'stobe-auto relation .* 100 ' "$F" && chk 26-f-relations-set ok || chk 26-f-relations-set bad
grep -q "clear out the bandits you can see" "$EVB/26-f/s1/utterance.txt" && ! grep -rqi "Hunt the 5 bandits\|Clear the bandit camp" "$EVB/26-f"/s*/utterance.txt && chk 26-f-offer-wording ok || chk 26-f-offer-wording bad
[ "$(grep -n 'stobe-auto save' "$F" | head -1 | cut -d: -f1)" -lt "$(grep -n 'stobe-auto load' "$F" | head -1 | cut -d: -f1)" ] && chk 26-f-save-before-load ok || chk 26-f-save-before-load bad
scen f26-pass; RW_REFACTION=0 RW_BANDITS=3 run 26-f $L >/dev/null; ! grep -q 'stobe-auto faction' "$KAH_ROW_FAKE_LOG" && grep -q 'count 3 ' "$KAH_ROW_FAKE_LOG" && chk 26-f-env-overrides ok || chk 26-f-env-overrides bad
# fix26f2 inject seam (sfO ClearGroup arm before the first offer say; disarm after the offer loop; opt-out; arm failure = SETUP-FAIL)
scen f26-pass; run 26-f $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
[ "$(grep -c 'printf .*STOBE_TEST_ACTIVITY_INJECT_V1' "$F")" = 1 ] && grep 'printf .*STOBE_TEST_ACTIVITY_INJECT_V1' "$F" | grep -q "'ClearGroup'" && chk 26-f-inject-armed-once-cleargroup ok || chk 26-f-inject-armed-once-cleargroup bad "arms=$(grep -c 'printf .*STOBE_TEST_ACTIVITY_INJECT_V1' "$F")"
la=$(grep -n 'printf .*STOBE_TEST_ACTIVITY_INJECT_V1' "$F" | head -1 | cut -d: -f1); ls1=$(grep -n 'stobe_say' "$F" | head -1 | cut -d: -f1)
lsn=$(grep -n "stobe-auto senses" "$F" | awk -F: -v a="${la:-0}" '$1<a{x=$1} END{print x+0}'); lyes=$(grep -n "stobe_say .*Yes" "$F" | head -1 | cut -d: -f1); ldis=$(grep -n 'rm -f ".*test-inject-activity.json"' "$F" | head -1 | cut -d: -f1); lall=$(grep -n 'rm -f ".*test-inject-activity.json"' "$F" | tail -1 | cut -d: -f1); llast=$(grep -n 'stobe_say' "$F" | tail -1 | cut -d: -f1)
[ -n "$la" ] && [ -n "$ls1" ] && [ "$la" -lt "$ls1" ] && [ "$lsn" -gt 0 ] && [ "$lsn" -lt "$la" ] && chk 26-f-inject-armed-after-scene-before-first-say ok || chk 26-f-inject-armed-after-scene-before-first-say bad "scene=$lsn arm=$la say=$ls1"
[ -n "$ldis" ] && [ -n "$ls1" ] && [ "$ldis" -gt "$ls1" ] && [ "$ldis" -lt "${lyes:-0}" ] && chk 26-f-inject-disarmed-after-offer-before-accept ok || chk 26-f-inject-disarmed-after-offer-before-accept bad "disarm=$ldis say=$ls1 yes=$lyes"
[ "$(grep -c 'rm -f ".*test-inject-activity.json"' "$F")" = 2 ] && chk 26-f-inject-disarmed-twice-propose-then-all ok || chk 26-f-inject-disarmed-twice-propose-then-all bad "rm lines=$(grep -c 'rm -f ".*test-inject-activity.json"' "$F")"
# fix26f4: availability bypass flag on the arm; the mid-row --disarm keeps the phase-2 accept marker (grep "phase":"accept" guard); --disarm-all runs after the LAST say; evidence inject_end.txt
grep 'printf .*STOBE_TEST_ACTIVITY_INJECT_V1' "$F" | grep -q '"bypass_availability":true' && grep -q '"phase":"accept"' "$F" && chk 26-f-inject-bypass-flag-and-phase2-kept ok || chk 26-f-inject-bypass-flag-and-phase2-kept bad
[ -n "$lall" ] && [ -n "$llast" ] && [ "$lall" -gt "$llast" ] && [ -f "$EVB/26-f/inject_end.txt" ] && chk 26-f-inject-disarm-all-after-last-say-evidence ok || chk 26-f-inject-disarm-all-after-last-say-evidence bad "all=$lall lastsay=$llast"
[ -s "$EVB/26-f/inject_arm.txt" ] && [ -f "$EVB/26-f/inject_status.txt" ] && chk 26-f-inject-evidence-files ok || chk 26-f-inject-evidence-files bad
[ -s "$EVB/26-f/delivery_1.txt" ] && [ -s "$EVB/26-f/resume_poll.txt" ] && grep -q RESUMED "$EVB/26-f/resume_poll.txt" && chk 26-f-delivery-and-resume-poll-evidence ok || chk 26-f-delivery-and-resume-poll-evidence bad
scen f26-pass; RW_INJECT_PROPOSE=0 run 26-f $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
! grep -q 'STOBE_TEST_ACTIVITY_INJECT_V1\|inject-activity' "$F" && grep -q 'RW_INJECT_PROPOSE=0' "$EVB/26-f/inject_arm.txt" && chk 26-f-inject-optout-arms-nothing ok || chk 26-f-inject-optout-arms-nothing bad
scen f26-pass; RW_INJECT_BYPASS=0 run 26-f $L >/dev/null; F="$KAH_ROW_FAKE_LOG"
! grep 'printf .*STOBE_TEST_ACTIVITY_INJECT_V1' "$F" | grep -q '"bypass_availability":true' && grep -q 'STOBE_TEST_ACTIVITY_INJECT_V1' "$F" && chk 26-f-inject-bypass-optout ok || chk 26-f-inject-bypass-optout bad
scen f26-pass; mkdir -p "$T/stubrt" && cp -r "$ST_HERE"/. "$T/stubrt/" && echo 'echo "SEAM-MISSING stub"; exit 4' > "$T/stubrt/inject-propose.sh"
r=$( RS_HERE="$T/stubrt"; run 26-f $L ); echo "$r" | grep -q '^RESULT 26-f SETUP-FAIL' && echo "$r" | grep -q 'inject-propose arm failed rc=4' && ! grep -q 'stobe_say' "$KAH_ROW_FAKE_LOG" && chk 26-f-inject-arm-refused-setup-fail-no-say ok || chk 26-f-inject-arm-refused-setup-fail-no-say bad "$(echo "$r" | cut -c1-300)"

# --- CLI: reload-run-sfe.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sfe.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen a24c-pass; o=$(cli reload-run-sfe.sh 24-c $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 24-c PASS SEEDED' && [ $rc = 0 ] && chk cli-24c ok || chk cli-24c bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen f26-pass; o=$(cli reload-run-sfe.sh 26-f $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 26-f PASS' && [ $rc = 0 ] && chk cli-26f ok || chk cli-26f bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen f26-nooffer; o=$(cli reload-run-sfe.sh 26-f $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen a24c-lost; o=$(cli reload-run-sfe.sh 24-c $L --allow-retry selftest); rc=$?; [ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
o=$(cli reload-run-sfe.sh 26-d $L); echo "$o" | grep -q 'RESULT 26-d SETUP-FAIL not a reload row' && chk cli-other-rows-refused ok || chk cli-other-rows-refused bad "$o"
scen a24c-pass; o=$(cli reload-run-sfe.sh 24-c $L --dry); echo "$o" | grep -q '^RESULT 24-c DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
scen a24c-pass; cli reload-run-sfe.sh 24-c $L --save my-save --allow-retry selftest >/dev/null; grep -q 'load my-save' "$KAH_ROW_FAKE_LOG" && chk cli-save-option ok || chk cli-save-option bad

# --- shim: other rows still go to the set-A checker; untouched originals
"$ST_HERE/reload-py-sfe.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
grep -q 'reloaddefs_sfe\|reloadcheck_sfe' "$ST_HERE/reloaddefs_a.sh" "$ST_HERE/reload-run.sh" "$ST_HERE/reload-py.sh" "$ST_HERE/reloadcheck_a.py" "$ST_HERE/rowdefs.sh" "$ST_HERE/tripdefs.sh" 2>/dev/null && chk originals-not-hooked bad || chk originals-not-hooked ok

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFE ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFE ALL FAIL $ok/$n"; exit 1; fi
