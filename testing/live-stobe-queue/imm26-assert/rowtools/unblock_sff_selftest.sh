#!/usr/bin/env bash
# unblock_sff_selftest.sh: OFFLINE self-test of row 03-b, sff variant (unblockdefs_sff.sh / unblockcheck_sff.py / unblockrun_sff.sh / unblockpy_sff.sh / sharehook.php, imm26-sfFixA): forced witness line.
# Lanes are simulated by unblockfake_sff.py (-> sfz -> d2 -> d -> ... -> fakelane.py). FAST: run in WSL:
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_sff_selftest.sh
# The last check runs sharehook_selftest.php (real PHP + the disposable stobe_test DB) when /root/imm26/compose exists; SFF_SKIP_PHP=1 skips it.
# Prints `SELFTEST unblocksff-<name> PASS|FAIL` and `SELFTEST UNBLOCK-SFF ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 RW_SAY_WAIT=0 U03B_ATTACK_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST U03B_B U03B_TRIES U03B_MAX_ROWS U03B_NO_ATTACK U03B_DEMOTE SZ_MAX_SPOKEN SFF_REAL_TRIES SFF_TEXT SFF_SUBJECT SFF_VICTIM
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblocksff-$1 PASS ${3:-}"; else echo "SELFTEST unblocksff-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/unblockdefs_d.sh"; . "$ST_HERE/unblockdefs_d2.sh"; . "$ST_HERE/unblockdefs_sfz.sh"; . "$ST_HERE/unblockdefs_sff.sh"
PY="$ST_HERE/unblockpy_sff.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sff.py" "$@"; }
L=4080-i4; EV3="$KAH_ROWS_BASE/imm26-4080-i4/rows/03-b"; F="$KAH_ROW_FAKE_LOG"
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub" "$FAKE_STATE.ud"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockfake_sff.py" --scen "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; rm -rf "$EV3"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
lastl() { grep -n -- "$1" "$F" | tail -1 | cut -d: -f1; }
cnt() { grep -c -- "$1" "$F"; }
# the hook command is built with printf %q, so names/lines carry backslash escapes; compare through the same quoting
q() { printf '%q' "$1"; }

[ "$SFF_REAL_TRIES" = 0 ] && chk default-no-real-tries ok || chk default-no-real-tries bad "$SFF_REAL_TRIES"
declare -F sz_gossip_loop_real >/dev/null && chk sfz-loop-kept-as-real ok || chk sfz-loop-kept-as-real bad

scen sf-pass; r=$(run 03-b $L); case "$r" in "RESULT 03-b PASS"*"seed=forced-line"*) chk forced-line-passes-and-says-so ok;; *) chk forced-line-passes-and-says-so bad "$(echo "$r" | cut -c1-400)";; esac
[ "$(cnt 'u3:stream')" = 0 ] && chk no-llm-pair-request-by-default ok || chk no-llm-pair-request-by-default bad "$(cnt 'u3:stream')"
[ "$(cnt 'sff:share')" = 1 ] && chk hook-called-once ok || chk hook-called-once bad "$(cnt 'sff:share')"
sh=$(fl 'sff:share'); at=$(fl 'stobe-auto hit')
[ -n "$sh" ] && [ -n "$at" ] && [ "$at" -lt "$sh" ] && chk hook-runs-after-the-real-attack ok || chk hook-runs-after-the-real-attack bad "attack@$at share@$sh"
grep -q 'KAH_LANE_ROOT=' "$F" && grep -q 'KAH_LANE_DB=' "$F" && grep -q 'sharehook.php' "$F" && grep -qF "$(q 'Cind [Hungry Bandit]')" "$F" && chk hook-command-has-lane-guard-script-and-speaker ok || chk hook-command-has-lane-guard-script-and-speaker bad "$(grep -m1 sff:share "$F" | cut -c1-300)"
grep -qF "$(q 'I saw Shay attack Malzin with my own eyes')" "$F" && chk default-line-names-subject-and-victim ok || chk default-line-names-subject-and-victim bad "$(grep -m1 sff:share "$F" | cut -c1-300)"
[ "$(cat "$EV3/seed_mode.txt" 2>/dev/null)" = forced-line ] && grep -q '^ok forced-line' "$EV3/gossip_ok.txt" && grep -q '^## forced-line' "$EV3/gossip_all.txt" && chk evidence-files ok || chk evidence-files bad
rs=$(lastl 'u3:sznpcrest'); [ -n "$rs" ] && [ -n "$sh" ] && [ "$rs" -gt "$sh" ] && chk chance-seam-restored-after-hook ok || chk chance-seam-restored-after-hook bad "rest@$rs share@$sh"

scen sf-norow; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"did not seed hearsay"*"eligible=0"*) chk no-eligible-row-setupfail-names-eligible ok;; *) chk no-eligible-row-setupfail-names-eligible bad "$(echo "$r" | cut -c1-400)";; esac
[ -n "$(lastl 'u3:sznpcrest')" ] && chk seam-restored-after-failure ok || chk seam-restored-after-failure bad
scen sf-unnamed; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"does not name the subject"*) chk unnamed-line-setupfail ok;; *) chk unnamed-line-setupfail bad "$(echo "$r" | cut -c1-400)";; esac
scen sf-php127; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"rc=127"*) chk php-missing-setupfail ok;; *) chk php-missing-setupfail bad "$(echo "$r" | cut -c1-400)";; esac
scen sf-nohearsay; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*stobeKnowledgeHearsayFor*) chk nohearsay-setupfail ok;; *) chk nohearsay-setupfail bad "$(echo "$r" | cut -c1-300)";; esac
! grep -q 'sff:share' "$F" && ! grep -q 'stobe-auto hit' "$F" && chk nohearsay-takes-no-action ok || chk nohearsay-takes-no-action bad

scen sf-real; r=$(SFF_REAL_TRIES=2 run 03-b $L); case "$r" in "RESULT 03-b PASS"*) chk real-llm-line-wins-passes ok;; *) chk real-llm-line-wins-passes bad "$(echo "$r" | cut -c1-400)";; esac
case "$r" in *seed=forced-line*) chk real-llm-line-not-labelled-forced bad;; *) chk real-llm-line-not-labelled-forced ok;; esac
[ "$(cnt 'sff:share')" = 0 ] && [ "$(cat "$EV3/seed_mode.txt" 2>/dev/null)" = llm-line ] && chk real-line-skips-hook ok || chk real-line-skips-hook bad "share=$(cnt 'sff:share') mode=$(cat "$EV3/seed_mode.txt" 2>/dev/null)"
scen sf-realfail; r=$(SFF_REAL_TRIES=2 run 03-b $L); case "$r" in "RESULT 03-b PASS"*"seed=forced-line"*) chk real-tries-fail-then-forced-passes ok;; *) chk real-tries-fail-then-forced-passes bad "$(echo "$r" | cut -c1-400)";; esac
[ "$(cnt 'u3:stream')" = 2 ] && [ "$(cnt 'sff:share')" = 1 ] && chk real-tries-bounded-then-one-hook ok || chk real-tries-bounded-then-one-hook bad "stream=$(cnt 'u3:stream') share=$(cnt 'sff:share')"
[ "${U03B_TRIES:-24}" = 24 ] && [ "${SZ_MAX_SPOKEN:-12}" = 12 ] && chk loop-budgets-restored ok || chk loop-budgets-restored bad "$U03B_TRIES/$SZ_MAX_SPOKEN"
scen sf-pass; r=$(SFF_TEXT="Shay hurt Malzin, I swear it." run 03-b $L); grep -qF "$(q 'Shay hurt Malzin, I swear it.')" "$F" && chk text-option-reaches-hook ok || chk text-option-reaches-hook bad
scen sf-pass; r=$(U03B_B="Stavna [X]" run 03-b $L); ! grep -q 'u3:chars' "$F" && grep -qF "$(q 'Stavna [X]')" "$F" && chk forced-b-reaches-hook ok || chk forced-b-reaches-hook bad "$(grep -m1 sff:share "$F" | cut -c1-300)"

# ---- CLI: unblockrun_sff.sh as a separate process
cli() { local script="$1"; shift; bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_sff.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null; }
scen sf-pass; o=$(cli unblockrun_sff.sh 03-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 03-b PASS.*seed=forced-line' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
echo "$o" | grep -q '^EVIDENCE 03-b seed_mode.txt forced-line' && chk cli-evidence-seed-mode ok || chk cli-evidence-seed-mode bad "$(echo "$o" | grep EVIDENCE | cut -c1-200 | head -3)"
scen sf-realfail; o=$(cli unblockrun_sff.sh 03-b $L --allow-retry selftest --real-tries 2); [ "$(grep -c 'u3:stream' "$F")" = 2 ] && chk cli-real-tries-option ok || chk cli-real-tries-option bad "stream=$(grep -c 'u3:stream' "$F")"
scen sf-pass; o=$(cli unblockrun_sff.sh 03-b $L --allow-retry selftest --text "Shay struck Malzin."); grep -qF "$(q 'Shay struck Malzin.')" "$F" && chk cli-text-option ok || chk cli-text-option bad
scen sf-norow; o=$(cli unblockrun_sff.sh 03-b $L --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 03-b SETUP-FAIL' && [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc $(echo "$o" | tail -1 | cut -c1-200)"
scen sf-pass; o=$(cli unblockrun_sff.sh 03-b $L --dry); echo "$o" | grep -q '^RESULT 03-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
o=$(cli unblockrun_sff.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
"$ST_HERE/unblockpy_sff.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad

# ---- hygiene
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_d.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_d2.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_sfz.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockrun_sfz.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_sfz.py 2>/dev/null && chk library-files-unedited ok || chk library-files-unedited bad
for f in unblockdefs_sff.sh unblockrun_sff.sh unblockpy_sff.sh unblock_sff_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
"$REAL_PY" -m py_compile "$ST_HERE/unblockcheck_sff.py" "$ST_HERE/unblockfake_sff.py" 2>/dev/null && chk py-compile ok || chk py-compile bad
if [ -z "${SFF_SKIP_PHP:-}" ] && [ -d /root/imm26/compose ] && command -v php >/dev/null; then
  po=$(cd /root/imm26/compose && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test php "$ST_HERE/sharehook_selftest.php" /root/imm26/compose 2>&1 | tail -1)
  case "$po" in "SELFTEST SHAREHOOK ALL PASS"*) chk sharehook-php-selftest ok "$po";; *) chk sharehook-php-selftest bad "$po";; esac
fi

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST UNBLOCK-SFF ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-SFF ALL FAIL $ok/$n"; exit 1; fi
