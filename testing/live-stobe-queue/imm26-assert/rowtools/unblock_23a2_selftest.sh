#!/usr/bin/env bash
# unblock_23a2_selftest.sh (imm26-fix23arecipe): OFFLINE self-test of the 23-a recipe v3 (tripdefs_23a2.sh + unblockrun_23a2.sh) on a simulated lane (unblockfake_23a2.py, scenarios unblockscen_23a2.py).
# Asserts for every op35 defect (a1 order cleared, a2 stage from the quiet spot / in the air, a3 PROPOSED forever, Cind not moved by the hand teleport) the exact SETUP-FAIL reason AND that nothing
# was staged / no walk happened, then MUTATES each guard of tripdefs_23a2.sh (deleted / weakened in a temp copy) and requires the scenario that needs it to change (result, say count or stage).
# Run in WSL: wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_23a2_selftest.sh
# Prints `SELFTEST a2-<name> PASS|FAIL` lines and `SELFTEST A2 ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 SFK_23A_TRIES=3 SFK_KO_WAIT=1 SFK_23A_WAIT=10 TRIP_23A_SETTLE=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT SFK_23A_BACK SFK_23A_SPEED SFK_SQUIN_GATE TRIP_HUB TRIP_A2_ACCEPT_TRIES A2_ANCHOR A2_NATIVE_TRIES A2_STAGE_DY A2_HUB_DY
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST a2-$1 PASS ${3:-}"; else echo "SELFTEST a2-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/reloaddefs_b.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/tripdefs_sfk.sh"; . "$ST_HERE/unblockdefs_sfk.sh"; . "$ST_HERE/tripdefs_23acheck.sh"; . "$ST_HERE/tripdefs_23a2.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_23a2.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE".*; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_23a2.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4; EVB="$KAH_ROWS_BASE/imm26-4080-i4/rows"; F="$KAH_ROW_FAKE_LOG"
says() { grep -c 'stobe_say' "$F"; }
staged() { grep -c 'dist 400' "$F"; }
walked() { grep -c 'sleep 1.5' "$F"; }
sig() { local r; r=$(run 23-a $L); echo "$(echo "$r" | cut -c1-120)|says=$(says)|stage=$(staged)|walk=$(walked)"; }
# expect <name> <scenario> <RESULT prefix> [substring that must occur in the RESULT line]
expect() {
  local name="$1" sc="$2" pre="$3" want="${4-}" r
  scen "$sc"; r=$(run 23-a $L)
  case "$r" in "$pre"*) ;; *) chk "$name" bad "$(echo "$r" | cut -c1-400)"; return 1;; esac
  if [ -n "$want" ] && ! echo "$r" | grep -qF -- "$want"; then chk "$name" bad "missing '$want' in: $(echo "$r" | cut -c1-400)"; return 1; fi
  chk "$name" ok; return 0
}

# ------------------------------------------------------------------ recipe behaviour
expect pass-from-quiet-spot a2-pass "RESULT 23-a PASS"
[ "$(grep -c 'teleport Shay -53200 960 4860' "$F")" = 1 ] && grep -q "teleport 'Cind \[Hungry Bandit\]' Shay" "$F" && chk anchor-hand-teleports-shay-then-cind-onto-shay ok || chk anchor-hand-teleports-shay-then-cind-onto-shay bad "$(grep -c 'teleport Shay -53200' "$F")"
[ "$(grep -n -m1 'teleport Shay -53200 960 4860' "$F" | cut -d: -f1)" -lt "$(grep -n -m1 'stobe_say' "$F" | cut -d: -f1)" ] && chk anchor-before-first-say ok || chk anchor-before-first-say bad
[ "$(grep -n -m1 'teleport Shay -53200 960 4860' "$F" | cut -d: -f1)" -lt "$(grep -n -m1 'dist 400' "$F" | cut -d: -f1)" ] && chk stage-after-hub-anchor ok || chk stage-after-hub-anchor bad
grep -q 'anchor OK' "$EVB/23-a/a2_setup.txt" && grep -q 'native live \[setup\]' "$EVB/23-a/a2_setup.txt" && grep -q 'native live \[prestage\]' "$EVB/23-a/a2_setup.txt" && chk setup-evidence ok || chk setup-evidence bad "$(cut -c1-200 "$EVB/23-a/a2_setup.txt" 2>/dev/null)"
[ "$(says)" = 4 ] && chk pass-says-exactly-s1-s2-s3-s4 ok || chk pass-says-exactly-s1-s2-s3-s4 bad "says=$(says)"
expect pass-from-hub a2-hub-pass "RESULT 23-a PASS"
! grep -q 'teleport Shay -53200 960 4860' "$F" && chk hub-start-no-extra-teleport ok || chk hub-start-no-extra-teleport bad
expect reaccept-when-proposed a2-reaccept "RESULT 23-a PASS"
grep -q "Yes, I accept. Please lead the way to Squin now." "$F" && chk reaccept-line-said ok || chk reaccept-line-said bad
[ -s "$EVB/23-a/s2b/reply.txt" ] && grep -q '"status":"ACCEPTED"' "$EVB/23-a/s2b/ev_full.txt" && chk reaccept-evidence-step-s2b-has-the-accepted-row ok || chk reaccept-evidence-step-s2b-has-the-accepted-row bad
expect reaccept-third-attempt-mirrored-for-the-checker a2-reaccept3 "RESULT 23-a PASS"
grep -q "I accept your offer" "$F" && grep -q 'mirrored from s2c' "$EVB/23-a/s2b/ev_full.txt" && chk third-attempt-line-said-and-mirrored ok || chk third-attempt-line-said-and-mirrored bad
expect lead-the-way-when-no-native-start a2-lead "RESULT 23-a PASS"
grep -q 'Lead the way' "$F" && [ -s "$EVB/23-a/s2d/reply.txt" ] && chk s2d-lead-the-way-said ok || chk s2d-lead-the-way-said bad
expect proposed-forever-setup-fail-early a2-proposed-forever "RESULT 23-a SETUP-FAIL" "agreement is PROPOSED"
[ "$(staged)" = 0 ] && [ "$(walked)" = 0 ] && chk proposed-forever-no-stage-no-walk ok || chk proposed-forever-no-stage-no-walk bad "stage=$(staged) walk=$(walked)"
[ "$(says)" -le 6 ] && grep -q "I accept your offer" "$F" && chk proposed-forever-bounded-retries ok "(says=$(says))" || chk proposed-forever-bounded-retries bad "says=$(says)"
expect not-anchored-setup-fail-before-s1 a2-notanchored "RESULT 23-a SETUP-FAIL" "squad is not on the Hub origin"
[ "$(says)" = 0 ] && [ "$(staged)" = 0 ] && chk not-anchored-nothing-said-nothing-staged ok || chk not-anchored-nothing-said-nothing-staged bad "says=$(says) stage=$(staged)"
expect pre-stage-height-setup-fail a2-ypre "RESULT 23-a SETUP-FAIL" "before the stage teleport, not the Hub band"
[ "$(staged)" = 0 ] && chk ypre-not-staged ok || chk ypre-not-staged bad
expect a1-native-order-cleared-setup-fail a2-cleared "RESULT 23-a SETUP-FAIL" "cleared by the game before the stage teleport"
[ "$(staged)" = 0 ] && [ "$(walked)" = 0 ] && chk a1-cleared-no-stage-no-walk ok || chk a1-cleared-no-stage-no-walk bad "stage=$(staged) walk=$(walked)"
expect a1-order-dropped-between-accept-and-stage a2-late-drop "RESULT 23-a SETUP-FAIL" "[prestage]"
[ "$(staged)" = 0 ] && chk late-drop-not-staged ok || chk late-drop-not-staged bad
expect no-native-start-setup-fail a2-nostart "RESULT 23-a SETUP-FAIL" "no NATIVE_TRAVEL_START"
grep -q 'Lead the way' "$F" && [ "$(staged)" = 0 ] && chk nostart-tries-lead-the-way-then-fails-unstaged ok || chk nostart-tries-lead-the-way-then-fails-unstaged bad
expect obs-orders-0-setup-fail a2-obs0 "RESULT 23-a SETUP-FAIL" "no NATIVE_TRAVEL_OBS with orders>=1"
expect a2-stage-in-the-air-setup-fail a2-air "RESULT 23-a SETUP-FAIL" "left Cind in the air"
[ "$(walked)" = 0 ] && chk air-no-walk-cycles ok || chk air-no-walk-cycles bad "walk=$(walked)"
expect agreement-failed-is-still-a-real-fail a2-failed "RESULT 23-a FAIL" "agreement_COMPLETED=FAILED"
scen a2-pass; TRIP_HUB="-1 970 2" run 23-a $L >/dev/null
grep -q 'teleport Shay -1 970 2' "$F" && chk hub-env-override ok || chk hub-env-override bad
scen a2-reaccept; r=$(TRIP_A2_ACCEPT_TRIES=1 run 23-a $L)
echo "$r" | grep -q 'SETUP-FAIL.*agreement is PROPOSED' && chk accept-tries-env-1 ok || chk accept-tries-env-1 bad "$(echo "$r" | cut -c1-200)"
scen a2-pass; A2_ANCHOR=0 run 23-a $L >/dev/null
! grep -q 'teleport Shay -53200' "$F" && chk no-anchor-env ok || chk no-anchor-env bad

# ------------------------------------------------------------------ mutation tests: each guard removed/weakened in a temp copy must change the outcome of the scenario that needs it
SRC="$ST_HERE/tripdefs_23a2.sh"
mutant() {   # mutant <name> <scenario> <sed-expr>
  local name="$1" sc="$2" ex="$3" base got M
  M="$T/mut_$name.sh"; sed -e "$ex" "$SRC" > "$M"
  if cmp -s "$M" "$SRC"; then chk "mutant-$name-applies" bad "sed expression changed nothing"; return; fi
  bash -n "$M" || { chk "mutant-$name-syntax" bad; return; }
  scen "$sc"; base=$(sig)
  got=$( . "$M"; scen "$sc"; sig )
  if [ "$base" != "$got" ]; then chk "mutant-$name-killed" ok; else chk "mutant-$name-killed" bad "SURVIVED: same outcome: $base"; fi
}
mutant anchor-removed a2-notanchored '/# a2:guard-anchor$/s/.*/  :/'
mutant ypre-removed a2-ypre '/# a2:guard-ypre$/s/.*/    :/'
mutant native-ended-ignored a2-cleared '/# a2:guard-native-ended$/s/.*/    if false; then/'
mutant native-orders-ignored a2-obs0 '/# a2:guard-native-orders$/s/ \&\& printf .%s. "\$obs" | grep -qE .orders=\[1-9\].//'
mutant prestage-probe-removed a2-late-drop '/# a2:guard-native-pre-stage$/s/.*/  :/'
mutant air-check-removed a2-air '/# a2:guard-air$/s/ if .*; then   #/  if false; then   #/'
mutant resay-no-break-on-accepted a2-pass '/# a2:guard-resay$/s/.*/    :/'
mutant accepted-assert-removed a2-proposed-forever '/# a2:guard-accepted$/s/.*/    *) ;;/'
mutant accept-tries-1 a2-reaccept 's/TRIP_A2_ACCEPT_TRIES:-3/TRIP_A2_ACCEPT_TRIES:-1/'

# ------------------------------------------------------------------ CLI: unblockrun_23a2.sh as a separate process
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_23a2.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
scen a2-pass; o=$(cli unblockrun_23a2.sh 23-a $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 23-a PASS' && [ $rc = 0 ] && chk cli-23a-one-result-line ok || chk cli-23a-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
echo "$o" | grep -q '^EVIDENCE 23-a a2_setup.txt ' && chk cli-evidence-a2-setup ok || chk cli-evidence-a2-setup bad
scen a2-pass; o=$(cli unblockrun_23a2.sh 23-a $L --no-reload --hub "-1 970 2" --accept-tries 2 --allow-retry selftest)
grep -q 'teleport Shay -1 970 2' "$F" && ! grep -q 'stobe-auto load' "$F" && chk cli-options-hub-no-reload ok || chk cli-options-hub-no-reload bad
scen a2-pass; o=$(cli unblockrun_23a2.sh 23-a $L --no-reload --no-anchor --allow-retry selftest)
echo "$o" | tail -1 | grep -q '^RESULT 23-a' && ! grep -q 'teleport Shay -53200' "$F" && chk cli-no-anchor ok || chk cli-no-anchor bad
scen a2-cleared; o=$(cli unblockrun_23a2.sh 23-a $L --no-reload --allow-retry selftest); rc=$?
[ $rc = 2 ] && echo "$o" | tail -1 | grep -q 'SETUP-FAIL' && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen a2-failed; o=$(cli unblockrun_23a2.sh 23-a $L --no-reload --allow-retry selftest); rc=$?
[ $rc = 1 ] && chk cli-fail-exit-1 ok || chk cli-fail-exit-1 bad "rc=$rc"
scen a2-pass; o=$(cli unblockrun_23a2.sh 23-a $L --dry)
echo "$o" | grep -q '^RESULT 23-a DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"

# ------------------------------------------------------------------ nothing existing is edited
for f in tripdefs_23a2.sh unblockrun_23a2.sh unblock_23a2_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
grep -q 'tripdefs_23a2\|unblockrun_23a2' "$ST_HERE/rowdefs.sh" "$ST_HERE/hxdefs.sh" "$ST_HERE/tripdefs.sh" "$ST_HERE/tripdefs_sfk.sh" "$ST_HERE/tripdefs_23acheck.sh" "$ST_HERE/unblockrun_23acheck.sh" "$ST_HERE/unblockrun_sfk.sh" "$ST_HERE/rowcheck_trip.py" 2>/dev/null && chk originals-not-hooked bad "an existing file references the a2 files" || chk originals-not-hooked ok
if git -C "$ST_HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ST_HERE" diff --quiet -- tripdefs.sh tripdefs_sfk.sh tripdefs_23acheck.sh unblockrun_23acheck.sh unblockrun_sfk.sh rowcheck_trip.py tripscen.py && chk checker-and-existing-recipes-unmodified ok || chk checker-and-existing-recipes-unmodified bad "git diff shows an edit"
fi

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST A2 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST A2 ALL FAIL $ok/$n"; exit 1; fi
