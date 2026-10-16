#!/usr/bin/env bash
# reload-sfo-selftest.sh (imm26-sfO): OFFLINE selftest of reloaddefs_sfo.sh / reload-run-sfo.sh (--inject arms inject-propose.sh before the s1 offer say). No game, ssh, WSL or DB
# (fake transport as reload-sfi-selftest.sh). Prints `SELFTEST sfo-<name> PASS|FAIL` and `SELFTEST SFO ALL PASS|FAIL n/m`. Usage: bash rowtools/reload-sfo-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_COMPLETE RW_SPAWN_CMD RW_OFFER RW_ACCEPT RW_KIND RW_SAVE_NAME RW_FACTION RW_REFACTION RW_APOLOGY RW_GOATS RW_PIN_GOATS RW_OFFER2 RW_INJECT_PROPOSE RW_INJECT_TARGET RW_INJECT_TTL
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sfo-$1 PASS ${3:-}"; else echo "SELFTEST sfo-$1 FAIL ${3:-}"; fi; }
L=5090-i3; F="$KAH_ROW_FAKE_LOG"
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sfi"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sfi.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
cli() {
  local script="$1"; shift
  bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/reloadfake_sfi.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null
}
lineno() { grep -n -- "$1" "$F" | head -"${2:-1}" | tail -1 | cut -d: -f1; }
before() { local a b; a=$(lineno "$1" "${3:-1}"); b=$(lineno "$2" "${4:-1}"); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }

# 1. with --inject Hunt: PASS unchanged, arm body before the s1 offer say, once, with the row / kind / NPC
scen 26d-pass; o=$(cli reload-run-sfo.sh 26-d $L --inject Hunt --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && [ $rc = 0 ] && [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && chk inject-26d-pass ok || chk inject-26d-pass bad "rc=$rc $(echo "$o" | cut -c1-300)"
grep -q 'STOBE_TEST_ACTIVITY_INJECT_V1' "$F" && chk arm-body-logged ok || chk arm-body-logged bad
before 'STOBE_TEST_ACTIVITY_INJECT_V1' 'Look at all these goats' && chk arm-before-s1-say ok || chk arm-before-s1-say bad
before 'stobe-auto senses' 'STOBE_TEST_ACTIVITY_INJECT_V1' && chk arm-after-scene-senses ok || chk arm-after-scene-senses bad
[ "$(grep -c 'STOBE_TEST_ACTIVITY_INJECT_V1' "$F")" = 1 ] && chk armed-once ok || chk armed-once bad "$(grep -c STOBE_TEST_ACTIVITY_INJECT_V1 "$F")"
grep -q "'Hunt'" "$F" && grep -q "'26-d'" "$F" && grep -q "'Cind" "$F" && chk arm-kind-row-npc ok || chk arm-kind-row-npc bad
# 2. no --inject: byte-identical behaviour, nothing armed
scen 26d-pass; o=$(cli reload-run-sfo.sh 26-d $L --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 26-d PASS' && ! grep -q 'STOBE_TEST_ACTIVITY_INJECT_V1' "$F" && chk no-inject-nothing-armed ok || chk no-inject-nothing-armed bad "rc=$rc"
# 3. 26-dx / 26-e also arm; --inject-target reaches the marker body
for r in 26-dx 26-e; do
  case $r in 26-dx) sc=26dx-pass;; *) sc=26e-pass;; esac
  scen $sc; o=$(cli reload-run-sfo.sh $r $L --inject Hunt --allow-retry selftest); rc=$?
  echo "$o" | tail -1 | grep -q "^RESULT $r PASS" && grep -q 'STOBE_TEST_ACTIVITY_INJECT_V1' "$F" && chk inject-$r-pass ok || chk inject-$r-pass bad "rc=$rc $(echo "$o" | cut -c1-200)"
done
scen 26d-pass; cli reload-run-sfo.sh 26-d $L --inject Hunt --inject-target goat --allow-retry selftest >/dev/null
grep -q "'goat'" "$F" && chk inject-target-passed ok || chk inject-target-passed bad
# 4. bad kind: arm refused -> SETUP-FAIL exit 2, the offer is never said
scen 26d-pass; o=$(cli reload-run-sfo.sh 26-d $L --inject Bogus --allow-retry selftest); rc=$?
[ $rc = 2 ] && echo "$o" | grep -q 'SETUP-FAIL' && ! grep -q 'Look at all these goats' "$F" && chk bad-kind-setup-fail ok || chk bad-kind-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-200)"
# 5. sfi script untouched and not hooked; other rows still refused
o=$(cli reload-run-sfo.sh 26-f $L); echo "$o" | grep -q 'RESULT 26-f SETUP-FAIL not a hunt reload row' && chk other-rows-refused ok || chk other-rows-refused bad
grep -q 'reloaddefs_sfo\|reload-run-sfo' "$ST_HERE/reloaddefs_sfi.sh" "$ST_HERE/reload-run-sfi.sh" "$ST_HERE/reload-run.sh" "$ST_HERE/reloaddefs_a.sh" && chk sfi-not-hooked bad || chk sfi-not-hooked ok
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFO ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFO ALL FAIL $ok/$n"; exit 1; fi
