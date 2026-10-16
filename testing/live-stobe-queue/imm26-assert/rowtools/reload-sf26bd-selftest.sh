#!/usr/bin/env bash
# reload-sf26bd-selftest.sh (imm26-sf26bd): OFFLINE selftest of reloaddefs_sf26bd.sh / reload-run-sf26bd.sh / reload-cycle-sf26bd.sh / hunt26b-cancel.sh. No game, ssh, WSL or DB (fake transport as
# reload-sfo-selftest.sh). Proves: Shay is teleported before the cancel say (same harness body, only before the cancel), ROW_NPC=Malzin is used by the reload cycle and regroup.txt names her,
# the people= guard turns a missing NPC into SETUP-FAIL, originals untouched. Prints `SELFTEST sf26bd-<name> PASS|FAIL` and `SELFTEST SF26BD ALL PASS|FAIL n/m`. Usage: bash rowtools/reload-sf26bd-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_FACTION RW_REFACTION RW_APOLOGY RW_GOATS RW_PIN_GOATS RW_OFFER2 RW_INJECT_PROPOSE RW_INJECT_TARGET RW_INJECT_TTL ROW_NPC RW_REQUIRE_NPC RW_PEOPLE_GUARD RW_REGROUP_GUARD RW_CANCEL_TELEPORT
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sf26bd-$1 PASS ${3:-}"; else echo "SELFTEST sf26bd-$1 FAIL ${3:-}"; fi; }
L=5090-i3; F="$KAH_ROW_FAKE_LOG"
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sfi" "$FAKE_STATE.sb"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sf26bd.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sf26bd.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
lineno() { grep -n -- "$1" "$F" | head -"${2:-1}" | tail -1 | cut -d: -f1; }
before() { local a b; a=$(lineno "$1" "${3:-1}"); b=$(lineno "$2" "${4:-1}"); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }
TP="stobe-auto teleport Shay 'Malzin'"
SAYC="stobe_say .* 'Cancel that.'"

# 0. the sfp rl_say anchor was found (teleport can be inserted in the say's own body)
o=$(bash -c ". '$ST_HERE/lane.sh'; . '$A/go-row.sh'; . '$ST_HERE/reloaddefs_a.sh'; . '$ST_HERE/reloaddefs_sfp.sh'; . '$ST_HERE/reloaddefs_sf26bd.sh'; echo PATCH=\$SB_PATCH_OK; declare -f sb_say_orig | grep -c SB_PRE_SAY" 2>/dev/null | tr '\n' ' ')
echo "$o" | grep -q 'PATCH=1 1' && chk anchor-patched ok || chk anchor-patched bad "$o"

# 1. 26-dx PASS path: Shay teleported inside the cancel say's body, BEFORE stobe_say "Cancel that.", and only there
scen 26dx-pass; o=$(cli reload-run-sf26bd.sh 26-dx $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-dx PASS' && [ $rc = 0 ] && [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && chk 26dx-pass ok || chk 26dx-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
tl=$(lineno "$TP"); sl=$(lineno "$SAYC")
[ -n "$tl" ] && [ -n "$sl" ] && [ "$tl" -lt "$sl" ] && [ $((sl-tl)) -le 3 ] && chk teleport-before-cancel-say ok "tp@$tl say@$sl" || chk teleport-before-cancel-say bad "tp=$tl say=$sl"
[ "$(grep -c "$TP" "$F")" = 1 ] && chk teleport-only-for-cancel ok || chk teleport-only-for-cancel bad "$(grep -c "$TP" "$F")"
grep -q "Cancel the hunt" "$F" && chk literal-cancel-text bad || chk literal-cancel-text ok
# 2. ROW_NPC=Malzin by default: where/teleport use Malzin, Cind never resolved or teleported
grep -q "stobe-auto where 'Malzin'" "$F" && ! grep -q "where 'Cind\|teleport 'Cind" "$F" && chk row-npc-malzin ok || chk row-npc-malzin bad
# 3. people= guard evidence on PASS
d=$(find "$KAH_ROWS_BASE" -type d -name 26-dx | head -1)
[ -s "$d/people_guard.txt" ] && grep -q 'OK: Malzin in people=' "$d/people_guard.txt" && chk people-guard-ok-evidence ok || chk people-guard-ok-evidence bad "$d"
# 4. Malzin missing from people= : SETUP-FAIL with the artefact text, exit 2, never a FAIL
scen 26dx-nopeople; o=$(cli reload-run-sf26bd.sh 26-dx $L --allow-retry selftest); rc=$?
echo "$o" | grep -q '^RESULT 26-dx SETUP-FAIL test artefact: NPC outside TalkRadius, see imm26-inv26' && [ $rc = 2 ] && chk people-missing-setup-fail ok || chk people-missing-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
echo "$o" | grep -q 'Malzin missing from people=' && chk people-missing-names-npc ok || chk people-missing-names-npc bad
# 5. no dispatched inputtext line at all = cannot prove it: SETUP-FAIL
scen 26dx-nodispatch; o=$(cli reload-run-sf26bd.sh 26-dx $L --allow-retry selftest); rc=$?
echo "$o" | grep -q '^RESULT 26-dx SETUP-FAIL test artefact' && [ $rc = 2 ] && chk no-dispatch-setup-fail ok || chk no-dispatch-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
# 6. guard off switch keeps the original behaviour
scen 26dx-nopeople; o=$(RW_PEOPLE_GUARD=0 cli reload-run-sf26bd.sh 26-dx $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-dx PASS' && chk guard-switch-off ok || chk guard-switch-off bad "rc=$rc $(echo "$o" | cut -c1-200)"
# 7. 26-d: after the load the far NPC is re-placed: regroup.txt names Malzin, row PASS
scen 26d-far; o=$(cli reload-run-sf26bd.sh 26-d $L --allow-retry selftest); rc=$?
d=$(find "$KAH_ROWS_BASE" -type d -name 26-d | head -1)
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && grep -q '^teleported: Malzin ' "$d/regroup.txt" && chk 26d-regroup-names-malzin ok || chk 26d-regroup-names-malzin bad "rc=$rc $(echo "$o" | cut -c1-200)"
grep -q "teleport 'Malzin' Shay" "$F" && ! grep -q "teleport 'Cind" "$F" && chk 26d-regroup-teleports-malzin ok || chk 26d-regroup-teleports-malzin bad
# 8. regroup that re-placed another NPC = SETUP-FAIL
scen 26d-wrongtp; o=$(cli reload-run-sf26bd.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | grep -q '^RESULT 26-d SETUP-FAIL test artefact: NPC outside TalkRadius.*regroup.txt re-placed another NPC' && [ $rc = 2 ] && chk regroup-wrong-npc-setup-fail ok || chk regroup-wrong-npc-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
# 9. explicit ROW_NPC=Cind with the runner default requirement = SETUP-FAIL (the old default-Cind trap)
scen 26d-far; o=$(ROW_NPC=Cind cli reload-run-sf26bd.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | grep -q "SETUP-FAIL.*ROW_NPC is 'Cind' but this row needs Malzin" && [ $rc = 2 ] && ! grep -q 'stobe_say' "$F" && chk default-cind-trap-setup-fail ok || chk default-cind-trap-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
# 10. reload-cycle-sf26bd.sh: ROW_NPC=Malzin by default, regroup.txt names Malzin
scen 26d-far; o=$(cli reload-cycle-sf26bd.sh $L my-cycle); rc=$?
echo "$o" | tail -1 | grep -q '^RELOAD-CYCLE-SF26BD 5090-i3 PASS regroup.txt names Malzin' && [ $rc = 0 ] && chk cycle-pass ok || chk cycle-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q "stobe-auto where 'Malzin'" "$F" && grep -q "teleport 'Malzin' Shay" "$F" && ! grep -q "where 'Cind\|teleport 'Cind" "$F" && chk cycle-uses-malzin ok || chk cycle-uses-malzin bad
scen 26d-wrongtp; o=$(cli reload-cycle-sf26bd.sh $L my-cycle); rc=$?
echo "$o" | tail -1 | grep -q '^RELOAD-CYCLE-SF26BD 5090-i3 SETUP-FAIL test artefact: regroup.txt does not name Malzin' && [ $rc = 2 ] && chk cycle-wrong-npc-setup-fail ok || chk cycle-wrong-npc-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
# 11. hunt26b-cancel.sh: teleport before the literal cancel, PASS on a cancelled record, FAIL on a failed one, SETUP-FAIL when the NPC is not in people=
scen cancel-pass; o=$(cli hunt26b-cancel.sh $L --wait 0); rc=$?
echo "$o" | tail -1 | grep -q '^HUNT26B-CANCEL 5090-i3 PASS' && [ $rc = 0 ] && chk cancel-script-pass ok || chk cancel-script-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
before "$TP" "$SAYC" && chk cancel-script-teleport-first ok || chk cancel-script-teleport-first bad
scen cancel-fail; o=$(cli hunt26b-cancel.sh $L --wait 0); rc=$?
echo "$o" | tail -1 | grep -q '^HUNT26B-CANCEL 5090-i3 FAIL' && [ $rc = 1 ] && chk cancel-script-fail ok || chk cancel-script-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen cancel-nopeople; o=$(cli hunt26b-cancel.sh $L --wait 0); rc=$?
echo "$o" | tail -1 | grep -q '^HUNT26B-CANCEL 5090-i3 SETUP-FAIL test artefact: NPC outside TalkRadius, see imm26-inv26' && [ $rc = 2 ] && chk cancel-script-people-missing-setup-fail ok || chk cancel-script-people-missing-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-300)"
# 12. operator originals are untouched and do not source the new files; scripts parse
R=testing/live-stobe-queue/imm26-assert/rowtools
if git -C "$A/../../.." diff --quiet -- $R/hunt26a-scene.sh $R/reload-cycle.sh $R/rowdefs.sh $R/reloaddefs_sfo.sh $R/reloaddefs_sfp.sh $R/reload-run-sfo.sh $R/reload-run-sfp.sh 2>/dev/null; then chk originals-unmodified ok; else chk originals-unmodified bad; fi
grep -l 'sf26bd' "$ST_HERE/hunt26a-scene.sh" "$ST_HERE/reload-cycle.sh" "$ST_HERE/rowdefs.sh" "$ST_HERE/reloaddefs_sfo.sh" "$ST_HERE/reloaddefs_sfp.sh" "$ST_HERE/reload-run-sfo.sh" "$ST_HERE/reload-run-sfp.sh" 2>/dev/null | grep -q . && chk originals-not-hooked bad || chk originals-not-hooked ok
bad=0; for f in reloaddefs_sf26bd.sh reload-run-sf26bd.sh reload-cycle-sf26bd.sh hunt26b-cancel.sh hunt26b-run.sh reload-sf26bd-selftest.sh; do bash -n "$ST_HERE/$f" || bad=1; done
[ $bad = 0 ] && chk bash-syntax ok || chk bash-syntax bad
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SF26BD ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SF26BD ALL FAIL $ok/$n"; exit 1; fi
