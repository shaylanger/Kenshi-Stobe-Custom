#!/usr/bin/env bash
# inject-travel-runners-selftest.sh (imm26-sfTrav): OFFLINE selftest of tripdefs_sftrav.sh / reload-run-sftrav.sh (20-d) / unblockrun_sftrav.sh (08-d): the lane is armed
# (inject-travel.sh, one-shot marker) right before the s1 trip ask, disarmed once s1 is PROPOSED, the verdict checkers are unchanged. No game, ssh, WSL-only tools or DB (fake transport as
# reload-sfo-selftest.sh / unblock_sfs_selftest.sh). Prints `SELFTEST sftrav-<name> PASS|FAIL` and `SELFTEST SFTRAV ALL PASS|FAIL n/m`. Usage: bash rowtools/inject-travel-runners-selftest.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python); export REAL_PY
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 TRIP_SE_TRIES=2 RW_SAY_WAIT=0 ROW_RESUME_WAIT=0 TRIP_WALK_TRIES=2
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST TRIP_ACCEPT TRIP_ALT RW_ALT RW_SAVE_NAME U08D_NEG TRIP_WALK_BACK TRIP_WALK_SPEED U_BORED_TRIES U_BORED_ATTN SFT_INJECT SFT_TTL SFT_KEEP_TEXT
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST sftrav-$1 PASS ${3:-}"; else echo "SELFTEST sftrav-$1 FAIL ${3:-}"; fi; }
F="$KAH_ROW_FAKE_LOG"
scen_j() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.sj"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/reloadscen_sfj.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
scen_s() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sfs.py" "$1" > "$FAKE_SCEN"; : > "$F"; }
cli_j() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$REAL_PY\" '$ST_HERE/reloadfake_sfj.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/reload-run-sftrav.sh' \"\$@\"" _ "$@" 2>/dev/null; }
cli_s() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$REAL_PY\" '$ST_HERE/unblockfake_sfs.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/unblockrun_sftrav.sh' \"\$@\"" _ "$@" 2>/dev/null; }
lineno() { grep -n -- "$1" "$F" | head -"${2:-1}" | tail -1 | cut -d: -f1; }
before() { local a b; a=$(lineno "$1" "${3:-1}"); b=$(lineno "$2" "${4:-1}"); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }

# 0. nothing queued was edited
BAD=""; for f in tripdefs.sh reloaddefs_a.sh reloaddefs_sfj.sh reload-run-sfj.sh unblockdefs_a.sh unblockdefs_sfs.sh unblockrun_sfs.sh inject-propose.sh rowcheck_trip.py; do
  git -C "$ST_HERE" diff --quiet HEAD -- "$f" 2>/dev/null || BAD="$BAD $f"; done
[ -z "$BAD" ] && chk originals-untouched ok || chk originals-untouched bad "differs from HEAD:$BAD"

# 1. 20-d: PASS unchanged, armed once before the s1 ask, disarmed after s1 PROPOSED and before the accept say
scen_j sj20d-pass; o=$(cli_j 20-d 5090-i3 --no-reload --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 20-d PASS' && [ $rc = 0 ] && [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && chk 20d-pass-one-result ok || chk 20d-pass-one-result bad "rc=$rc $(echo "$o" | cut -c1-300)"
[ "$(grep -c 'STOBE_TEST_TRAVEL_INJECT_V1' "$F")" = 1 ] && chk 20d-armed-once ok || chk 20d-armed-once bad "$(grep -c STOBE_TEST_TRAVEL_INJECT_V1 "$F")"
before 'STOBE_TEST_TRAVEL_INJECT_V1' 'Take me to Squin' && chk 20d-arm-before-s1-ask ok || chk 20d-arm-before-s1-ask bad
before 'Take me to Squin' 'rm -f .*test-inject-travel.json' && before 'rm -f .*test-inject-travel.json' "fine. Yes, let" && chk 20d-disarm-between-s1-and-accept ok || chk 20d-disarm-between-s1-and-accept bad
grep -q "'Squin'" "$F" && grep -q "'20-d'" "$F" && grep -q "'Cind" "$F" && chk 20d-marker-dest-row-npc ok || chk 20d-marker-dest-row-npc bad
# 2. SFT_INJECT=0: byte-identical flow, nothing armed
scen_j sj20d-pass; o=$(SFT_INJECT=0 cli_j 20-d 5090-i3 --no-reload --allow-retry selftest)
echo "$o" | tail -1 | grep -q '^RESULT 20-d PASS' && ! grep -q 'STOBE_TEST_TRAVEL_INJECT_V1' "$F" && ! grep -q 'test-inject-travel' "$F" && chk 20d-inject-off-nothing-armed ok || chk 20d-inject-off-nothing-armed bad "$(echo "$o" | cut -c1-200)"
# 3. arm refused (destination with a bad character): SETUP-FAIL, the trip ask is never said
scen_j sj20d-pass; o=$(cli_j 20-d 5090-i3 --no-reload --dest 'a;b' --allow-retry selftest); rc=$?
echo "$o" | grep -q 'SETUP-FAIL' && ! grep -q 'Take me to' "$F" && chk 20d-arm-refused-setup-fail ok || chk 20d-arm-refused-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-250)"
# 4. 08-d via unblockrun_sftrav.sh: PASS unchanged, armed before the s1 ask
scen_s sfs-pass; o=$(cli_s 08-d 4080-i4 --no-reload --allow-retry selftest); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 08-d PASS' && [ $rc = 0 ] && [ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && chk 08d-pass-one-result ok || chk 08d-pass-one-result bad "rc=$rc $(echo "$o" | cut -c1-300)"
[ "$(grep -c 'STOBE_TEST_TRAVEL_INJECT_V1' "$F")" = 1 ] && before 'STOBE_TEST_TRAVEL_INJECT_V1' 'Take me to Squin' && chk 08d-armed-once-before-s1 ok || chk 08d-armed-once-before-s1 bad "$(grep -c STOBE_TEST_TRAVEL_INJECT_V1 "$F")"
scen_s sfs-open; o=$(cli_s 08-d 4080-i4 --no-reload --allow-retry selftest)
echo "$o" | tail -1 | grep -q '^RESULT 08-d FAIL' && chk 08d-verdict-checker-unchanged-still-fails-open-topic ok || chk 08d-verdict-checker-unchanged-still-fails-open-topic bad "$(echo "$o" | cut -c1-250)"
# 5. other rows refused (each runner keeps to its row)
o=$(cli_j 23-e 5090-i3); echo "$o" | grep -q 'RESULT 23-e SETUP-FAIL reload-run-sftrav.sh runs 20-d only' && chk 20d-runner-refuses-23e ok || chk 20d-runner-refuses-23e bad "$o"
o=$(cli_s 11-b 4080-i4); echo "$o" | grep -q 'RESULT 11-b SETUP-FAIL unblockrun_sftrav.sh runs 08-d only' && chk 08d-runner-refuses-11b ok || chk 08d-runner-refuses-11b bad "$o"
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST SFTRAV ALL PASS $ok/$n"; exit 0; else echo "SELFTEST SFTRAV ALL FAIL $ok/$n"; exit 1; fi
