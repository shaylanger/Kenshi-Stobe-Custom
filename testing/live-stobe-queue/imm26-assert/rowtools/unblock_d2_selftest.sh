#!/usr/bin/env bash
# unblock_d2_selftest.sh: OFFLINE self-test of row 03-b, d2 variant (unblockdefs_d2.sh / unblockcheck_d2.py / unblockrun_d2.sh / unblockpy_d2.sh, imm26-sfD2).
# Lanes are simulated by unblockfake_d2.py (-> unblockfake_d.py -> ... -> fakelane.py) with scenarios from unblockscen_d2.py. FAST: run in WSL (python3 there is ~10x faster):
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_d2_selftest.sh
# Prints `SELFTEST unblockd2-<name> PASS|FAIL` and `SELFTEST UNBLOCK-D2 ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 RW_SAY_WAIT=0 U03B_ATTACK_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST U03B_B U03B_TRIES U03B_MAX_ROWS U03B_NO_ATTACK U03B_DEMOTE
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblockd2-$1 PASS ${3:-}"; else echo "SELFTEST unblockd2-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/unblockdefs_d.sh"; . "$ST_HERE/unblockdefs_d2.sh"
PY="$ST_HERE/unblockpy_d2.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_d2.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub" "$FAKE_STATE.ud"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_d2.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
L=4080-i4; EV3="$KAH_ROWS_BASE/imm26-4080-i4/rows/03-b"; F="$KAH_ROW_FAKE_LOG"
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }

[ "${U03B_MAX_ROWS}" = 999 ] && chk default-max-rows-999 ok || chk default-max-rows-999 bad "$U03B_MAX_ROWS"
scen d2-hub; r=$(run 03-b $L); case "$r" in "RESULT 03-b PASS"*) chk hub-all-busy-passes ok;; *) chk hub-all-busy-passes bad "$(echo "$r" | cut -c1-300)";; esac
[ "$(cat "$EV3/b.txt" 2>/dev/null)" = "Wren [Trader]" ] && chk fewest-rows-candidate-picked ok || chk fewest-rows-candidate-picked bad "$(cat "$EV3/b.txt" 2>/dev/null)"
[ "$(head -1 "$EV3/b_candidates.txt" 2>/dev/null)" = "30|1|Wren [Trader]" ] && chk candidates-sorted-by-count-first ok || chk candidates-sorted-by-count-first bad "$(tr '\n' ' ' < "$EV3/b_candidates.txt" 2>/dev/null)"
q=$(fl 'teleport Shay -48000 1500 2960'); a=$(fl 'stobe-auto hit Shay Malzin'); f=$(fl "teleport 'Wren \[Trader\]' -53200")
[ -n "$q" ] && [ -n "$a" ] && [ "$q" -lt "$a" ] && chk scene-at-quiet-spot-before-the-attack ok || chk scene-at-quiet-spot-before-the-attack bad "quiet@$q attack@$a"
p=$(fl "teleport 'Wren \[Trader\]' Shay")
[ -n "$p" ] && [ -n "$f" ] && [ "$p" -lt "$f" ] && chk B-pulled-to-spot-then-sent-far ok || chk B-pulled-to-spot-then-sent-far bad "pull@$p far@$f"
h=$(fl 'stobeKnowledgeHearsayFor'); c=$(fl 'BORED_EVENT_CHANCE')
[ -n "$h" ] && [ -n "$c" ] && [ "$h" -lt "$c" ] && chk hearsay-check-before-any-change ok || chk hearsay-check-before-any-change bad "check@$h chance@$c"
grep -q "mode=autochat" "$F" && ! grep -q 'optional=1' "$F" && chk pair-request-unchanged ok || chk pair-request-unchanged bad
scen d2-nohearsay; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*stobeKnowledgeHearsayFor*imm26-install/hearsay/deploy.sh*) chk nohearsay-setupfail-with-deploy-hint ok;; *) chk nohearsay-setupfail-with-deploy-hint bad "$(echo "$r" | cut -c1-300)";; esac
! grep -q 'stobe-auto hit' "$F" && ! grep -q "update general_settings set value='100'" "$F" && chk nohearsay-takes-no-game-action ok || chk nohearsay-takes-no-game-action bad
scen d2-nob; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"no candidate B"*) chk no-candidate-setupfail ok;; *) chk no-candidate-setupfail bad "$(echo "$r" | cut -c1-300)";; esac
scen d2-noprompt; r=$(run 03-b $L); case "$r" in "RESULT 03-b FAIL"*prompt_shows_hearsay*) chk prompt-without-hearsay-still-FAIL ok;; *) chk prompt-without-hearsay-still-FAIL bad "$(echo "$r" | cut -c1-300)";; esac
scen d2-hub; U03B_B="Stavna [X]" run 03-b $L >/dev/null; ! grep -q 'u3:chars' "$F" && grep -q '"Cind \[Hungry Bandit\]" "Stavna \[X\]"' "$F" && chk forced-b-skips-search ok || chk forced-b-skips-search bad
scen d2-hub; U03B_MAX_ROWS=10 run 03-b $L >/dev/null; r=$(cat "$EV3/b.txt"); [ "$r" = none ] && chk max-rows-limit-still-honoured ok || chk max-rows-limit-still-honoured bad "$r"
export U03B_MAX_ROWS=999

# ---- CLI: unblockrun_d2.sh as a separate process
cli() { local script="$1"; shift; bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_d2.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null; }
scen d2-hub; o=$(cli unblockrun_d2.sh 03-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 03-b PASS' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen d2-nohearsay; o=$(cli unblockrun_d2.sh 03-b $L --allow-retry selftest); rc=$?; echo "$o" | tail -1 | grep -q '^RESULT 03-b SETUP-FAIL' && [ $rc = 2 ] && chk cli-setup-fail-exit-2 ok || chk cli-setup-fail-exit-2 bad "rc=$rc"
scen d2-hub; o=$(cli unblockrun_d2.sh 03-b $L --dry); echo "$o" | grep -q '^RESULT 03-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
o=$(cli unblockrun_d2.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
"$ST_HERE/unblockpy_d2.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_d.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockrun_d.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_d.py 2>/dev/null && chk d-files-untouched ok || chk d-files-untouched bad "modified"
for f in unblockdefs_d2.sh unblockrun_d2.sh unblockpy_d2.sh unblock_d2_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST UNBLOCK-D2 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-D2 ALL FAIL $ok/$n"; exit 1; fi
