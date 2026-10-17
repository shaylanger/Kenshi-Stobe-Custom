#!/usr/bin/env bash
# unblock_sffb4_selftest.sh (imm26-fix11b): OFFLINE self-test of the 11-b recipe v4 (unblockdefs_sffb4.sh / unblockrun_sffb4.sh; checker unchanged: unblockcheck_a.py via unblockpy_a.sh).
# No game, ssh, WSL or DB: a lane is simulated by unblockfake_sffb4.py with scenarios from unblockscen_sffb4.py. Asserts the four v4 fixes (quiet spot + far dump, people as Name|serial with
# vacuity guards, strays cleared + events aged out before the post-combat tick, eventlog combat proof + unprotect before KO), the MUTATION checks (a claim that exists must FAIL the no-claim checks;
# a missing claim must FAIL the after-combat check) and replays the real 5090-i3 / 4080-i4 11-b evidence dirs (C:/KenshiTestRuns/imm26-*/rows/11-b) through the checker and the tick guard.
# Run in WSL: wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_sffb4_selftest.sh
# Prints `SELFTEST sffb4-<name> PASS|FAIL` lines and `SELFTEST SFFB4 ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 U11B_CALM_TRIES=2 SFK_KO_WAIT=1
unset KAH_AGENT_NAME KAH_ROW_DRY KAH_PF_ISOLATION TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT U11B_FACTION U11B_DIST U11B_END U11B_RECALL_DIST U11B_SPOT U11B_DUMP U11B_QUIET_MAX_S TR_SCENE
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sffb4-$1 PASS ${3:-}"; else echo "SELFTEST sffb4-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/tripdefs_sfk.sh"; . "$ST_HERE/unblockdefs_sfk.sh"; . "$ST_HERE/unblockdefs_sffb.sh"; . "$ST_HERE/unblockdefs_sffb4.sh"
PY="$ST_HERE/unblockpy_a.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sffb4.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sffb4.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4
EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"
F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
bad_set() {   # names of the failing checks of the checker for an evidence dir
  "$REAL_PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import unblockcheck_a as c
c.rc.V.emit = lambda s, e: print("BAD", ",".join(sorted(b.split("=")[0] for b in s.bad))) or 0
c.main(["x", sys.argv[2], sys.argv[3]])' "$ST_HERE" "$1" "$2" 2>&1 | sed -n 's/^BAD //p'
}
# expect <name> <scenario> <RESULT prefix> [substring of the RESULT line]
expect() {
  local name="$1" sc="$2" pre="$3" want="${4-}" r
  scen "$sc"; r=$(run 11-b "$L")
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return;; esac
  if [ -n "$want" ]; then echo "$r" | grep -q -- "$want" && chk "$name" ok || chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-300)"; else chk "$name" ok; fi
}
# expect_fail <name> <scenario> <exact failing-check set>: a FAIL verdict with exactly these checks failing (mutation tests)
expect_fail() {
  local name="$1" sc="$2" want="$3" r ev got
  scen "$sc"; r=$(run 11-b "$L")
  case "$r" in "RESULT 11-b FAIL"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-300)"; return;; esac
  ev=$(echo "$r" | sed -n 's/.*\[evidence=\([^]]*\)\].*/\1/p'); got=$(bad_set 11-b "$ev")
  [ "$got" = "$want" ] && chk "$name" ok "failing=$got" || chk "$name" bad "failing='$got' wanted '$want'"
}

# ------------------------------------------------------------------ baseline pass + (1) scene
expect pass pass "RESULT 11-b PASS" "exactly_one_claim_after_combat"
grep -q "teleport Shay -48000 1500 2960" "$F" && [ "$(fl 'teleport Shay -48000 1500 2960')" -lt "$(fl 'stobe-auto spawn')" ] && chk quiet-spot-default-before-spawn ok || chk quiet-spot-default-before-spawn bad "$(grep -m1 'teleport Shay' "$F" | cut -c1-100)"
! grep -q -- '-53200 957 4893' "$F" && grep -q 'stobe-auto teleport "#\$id" -62030 330 16250' "$F" && chk strays-go-to-far-dump-never-the-save-spot ok || chk strays-go-to-far-dump-never-the-save-spot bad "$(grep -m2 -- '-53200' "$F" | cut -c1-100)"
grep -q '^spot=-48000 1500 2960 dump=-62030 330 16250' "$EVB/11-b/scene_cfg.txt" && chk scene-cfg-evidence ok || chk scene-cfg-evidence bad "$(cat "$EVB/11-b/scene_cfg.txt" 2>/dev/null)"
scen pass; U11B_SPOT="-1 2 3" U11B_DUMP="9 8 7" run 11-b $L >/dev/null
grep -q "teleport Shay -1 2 3" "$F" && grep -q 'stobe-auto teleport "#\$id" 9 8 7' "$F" && ! grep -q -- '-48000 1500 2960' "$F" && chk spot-dump-env-respected ok || chk spot-dump-env-respected bad
scen pass; TR_SCENE="-5 6 7" run 11-b $L >/dev/null
grep -q "teleport Shay -5 6 7" "$F" && chk tr-scene-env-overrides-default ok || chk tr-scene-env-overrides-default bad

# ------------------------------------------------------------------ (2) people as Name|serial, vacuity guards
scen pass; run 11-b $L >/dev/null
grep -q '^people=Cind|[0-9]*,Shay|[0-9]*' "$EVB/11-b/bored_people.txt" && [ "$(grep -c '^people=' "$EVB/11-b/bored_people.txt")" = 3 ] && chk all-three-ticks-send-serials ok || chk all-three-ticks-send-serials bad "$(cat "$EVB/11-b/bored_people.txt" 2>/dev/null)"
expect no-scope-log-is-setup-fail no-scope "RESULT 11-b SETUP-FAIL" "no_social_scope"
[ "$(grep -c 'u:stream' "$F")" -le 1 ] && chk vacuous-run-stops-at-first-bad-tick ok || chk vacuous-run-stops-at-first-bad-tick bad "$(grep -c 'u:stream' "$F") ticks"
expect plain-people-is-setup-fail plain-people "RESULT 11-b SETUP-FAIL" "plain names"
expect no-claim-path-in-log-is-setup-fail no-path "RESULT 11-b SETUP-FAIL" "no follow-up claim attempt"

# ------------------------------------------------------------------ (3) strays after the fight, events aged out
expect strays-cleared-after-fight-passes strays-cleared "RESULT 11-b PASS"
[ "$(tail -n +"$(fl 'stobe-auto spawn')" "$F" | grep -c 'stobe-auto teleport "#\$id" -62030 330 16250')" = 2 ] && chk post-fight-clear-twice-with-far-dump ok || chk post-fight-clear-twice-with-far-dump bad "$(tail -n +"$(fl 'stobe-auto spawn')" "$F" | grep -c 'teleport "#')"
[ "$(cat "$EVB/11-b/scene_calm.txt.n")" = 0 ] && chk scene-calm-empty-before-c2 ok || chk scene-calm-empty-before-c2 bad "$(head -2 "$EVB/11-b/scene_calm.txt" 2>/dev/null)"
expect strays-stay-setup-fail strays-stay "RESULT 11-b SETUP-FAIL" "third parties near the squad after the fight"
! grep -qx c2 "$EVB/11-b/bored_ticks.txt" && chk no-c2-tick-while-strays-near ok || chk no-c2-tick-while-strays-near bad "$(cat "$EVB/11-b/bored_ticks.txt")"
expect events-age-out-waits-then-passes events-age-out "RESULT 11-b PASS"
[ "$(wc -l < "$EVB/11-b/quiet_wait.txt")" = 3 ] && grep -q 'event_age=130' "$EVB/11-b/quiet_wait.txt" && chk quiet-wait-polls-until-125s ok || chk quiet-wait-polls-until-125s bad "$(cat "$EVB/11-b/quiet_wait.txt")"
U11B_QUIET_MAX_S=30 expect events-keep-arriving-setup-fail events-fresh "RESULT 11-b SETUP-FAIL" "situated events keep arriving"
grep -q 'kind threat' "$EVB/11-b/result.txt" && chk events-fail-names-the-kind ok || chk events-fail-names-the-kind bad "$(cat "$EVB/11-b/result.txt" 2>/dev/null | cut -c1-200)"
expect claim-cooldown-waits-for-185s claim-cooldown "RESULT 11-b PASS"
grep -q 'claim_age=190' "$EVB/11-b/quiet_wait.txt" && [ "$(wc -l < "$EVB/11-b/quiet_wait.txt")" = 3 ] && chk claim-cooldown-polled ok || chk claim-cooldown-polled bad "$(cat "$EVB/11-b/quiet_wait.txt")"

# ------------------------------------------------------------------ (4) combat proof from the eventlog, unprotect before the KO
expect native-false-with-fresh-combat-rows-is-proven native-false-eventlog-true "RESULT 11-b PASS"
grep -q 'in_combat=true (source=eventlog' "$EVB/11-b/state_combat.txt" && grep -q 'in_combat=true (source=eventlog' "$EVB/11-b/state_combat_pre.txt" && grep -q 'in_combat=false' "$EVB/11-b/state_calm.txt" && chk eventlog-source-recorded ok || chk eventlog-source-recorded bad "$(cat "$EVB/11-b/state_combat.txt" "$EVB/11-b/state_calm.txt" 2>/dev/null)"
expect native-false-without-combat-rows-is-not-proven native-false-no-rows "RESULT 11-b SETUP-FAIL" "not in proven combat"
expect calm-needs-combat-rows-to-stop calm-eventlog-fresh "RESULT 11-b SETUP-FAIL" "combat did not end"
expect unprotect-failure-is-setup-fail unprotect-fail "RESULT 11-b SETUP-FAIL" "protect off of the spawned enemy"
scen pass; run 11-b $L >/dev/null
[ "$(grep -c 'sffb4:unprotect' "$F")" = 1 ] && grep -q "protect '#77/1' off" "$F" && [ "$(fl 'sffb4:unprotect')" -lt "$(fl 'sffb:ko')" ] && [ "$(fl "protect '#77/1' on")" -lt "$(fl 'sffb4:unprotect')" ] && chk enemy-unprotected-once-before-the-ko ok || chk enemy-unprotected-once-before-the-ko bad "unprot=$(fl 'sffb4:unprotect') ko=$(fl 'sffb:ko')"
! grep -q -- "teleport '#77/1'" "$F" && ! grep -q 'NULL_TASK' "$F" && chk ko-path-keeps-v3-no-teleport ok || chk ko-path-keeps-v3-no-teleport bad
scen pass; U11B_END=far run 11-b $L >/dev/null
! grep -q 'sffb4:unprotect' "$F" && grep -q "teleport '#77/1' -53200 957 4893" "$F" && chk end-far-skips-unprotect-keeps-old-end ok || chk end-far-skips-unprotect-keeps-old-end bad

# ------------------------------------------------------------------ MUTATION: the checker's no-claim checks are not vacuous (a claim that exists must FAIL them)
expect_fail mutation-claim-without-snapshot-fails mut-claim-nosnap "ask_count_unchanged_in_combat,no_claim_in_combat_without_snapshot"
expect_fail mutation-claim-with-snapshot-fails mut-claim-snap "ask_count_unchanged_in_combat,no_claim_in_combat_with_fresh_snapshot"
expect_fail mutation-missing-claim-after-combat-fails mut-no-claim-after "ask_count_plus_1_after_claim,exactly_one_claim_after_combat"
scen mut-claim-nosnap; r=$(run 11-b $L); echo "$r" | grep -q '^RESULT 11-b PASS' && chk mutation-never-passes bad || chk mutation-never-passes ok

# ------------------------------------------------------------------ REAL evidence replay (skipped when the dir is absent)
RUNS=/mnt/c/KenshiTestRuns; [ -d "$RUNS" ] || RUNS=/c/KenshiTestRuns
E5="$RUNS/imm26-5090-i3/rows/11-b"; E4="$RUNS/imm26-4080-i4/rows/11-b"
guard_rc() {   # guard_rc <evdir> <tag> <need>: sffb4_tick_guard against a recorded evidence dir
  ( EV="$1"; sffb4_tick_guard "$2" "$3" >/dev/null 2>&1; echo $? )
}
if [ -s "$E4/bored_c1a_log.txt" ]; then
  [ "$(guard_rc "$E4" c1a 1)" = 3 ] && [ "$(guard_rc "$E4" c1b 1)" = 3 ] && [ "$(guard_rc "$E4" c2 0)" = 3 ] && chk evidence-4080-plain-names-run-is-caught-as-vacuous ok || chk evidence-4080-plain-names-run-is-caught-as-vacuous bad "c1a=$(guard_rc "$E4" c1a 1)"
  grep -q 'pos=-48000.0,1500.0,2960.0' "$E4/quiet.txt" && [ "$(tr -dc 0-9 < "$E4/scene_pre.txt.n")" = 0 ] && chk evidence-4080-quiet-spot-valid-scene-empty ok || chk evidence-4080-quiet-spot-valid-scene-empty bad
  r=$(bash "$ST_HERE/unblockpy_a.sh" "$ST_HERE/rowcheck.py" 11-b "$E4" 2>&1 | head -1 | cut -c1-90)
  echo "$r" | grep -q 'SETUP-FAIL' && chk evidence-4080-checker-still-says-setup-fail-not-proven ok "$r" || chk evidence-4080-checker-still-says-setup-fail-not-proven bad "$r"
else chk evidence-4080-skipped ok "(no evidence dir)"; fi
if [ -s "$E5/bored_c1a_log.txt" ]; then
  [ "$(guard_rc "$E5" c1a 1)" = 0 ] && chk evidence-5090-serial-tick-passes-guard ok || chk evidence-5090-serial-tick-passes-guard bad "rc=$(guard_rc "$E5" c1a 1)"
  grep -q 'pos=-480\|pos=-479' "$E5/quiet.txt" && [ "$(tr -dc 0-9 < "$E5/scene_pre.txt.n")" = 0 ] && chk evidence-5090-quiet-spot-valid-scene-empty ok || chk evidence-5090-quiet-spot-valid-scene-empty bad
  [ "$(tr -dc 0-9 < "$E5/scene_calm.txt.n")" -gt "${SFK_SCENE_MAX:-0}" ] && grep -q 'Holy Nation Outlaws' "$E5/scene_calm.txt" && chk evidence-5090-run-would-be-stopped-by-scene-calm-guard ok || chk evidence-5090-run-would-be-stopped-by-scene-calm-guard bad
else chk evidence-5090-skipped ok "(no evidence dir)"; fi

# ------------------------------------------------------------------ CLI: unblockrun_sffb4.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_sffb4.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen pass; o=$(cli unblockrun_sffb4.sh 11-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 11-b PASS' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
echo "$o" | grep -q '^EVIDENCE 11-b scene_cfg.txt ' && echo "$o" | grep -q '^EVIDENCE 11-b quiet_wait.txt ' && echo "$o" | grep -q '^EVIDENCE 11-b unprotect.txt ' && chk cli-evidence-lines ok || chk cli-evidence-lines bad
scen pass; o=$(KAH_PF_ISOLATION=0 cli unblockrun_sffb4.sh 11-b $L --allow-retry selftest); rc=$?
[ $rc = 2 ] && echo "$o" | grep -q 'ISOLATION=0 is not allowed' && [ ! -s "$F" ] && chk cli-refuses-isolation-off ok || chk cli-refuses-isolation-off bad "rc=$rc $o"
scen pass; o=$(cli unblockrun_sffb4.sh 11-b 5090-i3 --allow-retry selftest); rc=$?
grep -q 'stobe-auto load kah-imm26-5090' "$F" && chk cli-5090-i3-configured-save-default ok || chk cli-5090-i3-configured-save-default bad "$(grep -m1 'stobe-auto load' "$F")"
scen pass; o=$(cli unblockrun_sffb4.sh 11-b $L --no-reload --spot "1 2 3" --dump "4 5 6" --quiet-max 50 --allow-retry selftest)
grep -q 'teleport Shay 1 2 3' "$F" && grep -q 'teleport "#\$id" 4 5 6' "$F" && ! grep -q 'stobe-auto load' "$F" && chk cli-spot-dump-options ok || chk cli-spot-dump-options bad
scen pass; o=$(cli unblockrun_sffb4.sh 11-b $L --no-reload --end bogus --allow-retry selftest); rc=$?
[ $rc = 2 ] && echo "$o" | grep -q -- '--end must be ko or far' && chk cli-bad-end-refused ok || chk cli-bad-end-refused bad "rc=$rc $o"
scen no-scope; o=$(cli unblockrun_sffb4.sh 11-b $L --allow-retry selftest); rc=$?; [ $rc = 2 ] && echo "$o" | tail -1 | grep -q 'SETUP-FAIL' && chk cli-vacuous-run-exit-2 ok || chk cli-vacuous-run-exit-2 bad "rc=$rc"
scen pass; o=$(cli unblockrun_sffb4.sh 11-b $L --dry); echo "$o" | grep -q '^RESULT 11-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
o=$(cli unblockrun_sffb4.sh 23-a $L); echo "$o" | grep -q 'RESULT 23-a SETUP-FAIL not an sffb4 row' && chk cli-other-row-refused ok || chk cli-other-row-refused bad "$o"

# ------------------------------------------------------------------ hygiene
for f in unblockdefs_sffb4.sh unblockrun_sffb4.sh unblock_sffb4_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
"$REAL_PY" -m py_compile "$ST_HERE/unblockfake_sffb4.py" "$ST_HERE/unblockscen_sffb4.py" 2>/dev/null && chk py-compile ok || chk py-compile bad
grep -q 'unblockdefs_sffb4' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/unblockdefs_a.sh" "$ST_HERE/unblockdefs_sfk.sh" "$ST_HERE/unblockdefs_sffb.sh" "$ST_HERE/unblockcheck_a.py" "$ST_HERE/reloaddefs_a.sh" 2>/dev/null && chk originals-not-hooked bad || chk originals-not-hooked ok
grep -h 'KAH_PF_ISOLATION=0' "$ST_HERE/unblockdefs_sffb4.sh" "$ST_HERE/unblockrun_sffb4.sh" | grep -v 'is not allowed\|NEVER' | grep -q . && chk no-isolation-off-in-new-files bad || chk no-isolation-off-in-new-files ok
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- tripdefs.sh unblockdefs_a.sh unblockdefs_sfk.sh unblockdefs_sffb.sh unblockrun_sffb.sh unblock_sffb_selftest.sh unblockfake_sffb.py unblockscen_sffb.py unblockcheck_a.py unblockrun_a.sh unblockrun_sfk.sh unblockpy_a.sh rowdefs.sh && chk v3-and-queued-scripts-unmodified ok || chk v3-and-queued-scripts-unmodified bad "git diff shows an edit"
fi

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFFB4 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFFB4 ALL FAIL $ok/$n"; exit 1; fi
