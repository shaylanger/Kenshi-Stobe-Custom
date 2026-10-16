#!/usr/bin/env bash
# unblock_sfz_selftest.sh: OFFLINE self-test of row 03-b, sfz variant (unblockdefs_sfz.sh / unblockcheck_sfz.py / unblockrun_sfz.sh / unblockpy_sfz.sh, imm26-sfZ): per-NPC chance seam + bounded retry loop.
# Lanes are simulated by unblockfake_sfz.py (-> d2 -> d -> ... -> fakelane.py) with scenarios from unblockscen_sfz.py. FAST: run in WSL:
#   wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/unblock_sfz_selftest.sh
# Prints `SELFTEST unblocksfz-<name> PASS|FAIL` and `SELFTEST UNBLOCK-SFZ ALL PASS|FAIL n/m`.
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 RW_SAY_WAIT=0 U03B_ATTACK_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY TRIP_TRAP TRIP_GATE TRIP_SAVE TRIP_DEST U03B_B U03B_TRIES U03B_MAX_ROWS U03B_NO_ATTACK U03B_DEMOTE SZ_MAX_SPOKEN
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST unblocksfz-$1 PASS ${3:-}"; else echo "SELFTEST unblocksfz-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/reloaddefs_a.sh"; . "$ST_HERE/unblockdefs_a.sh"; . "$ST_HERE/unblockdefs_d.sh"; . "$ST_HERE/unblockdefs_d2.sh"; . "$ST_HERE/unblockdefs_sfz.sh"
PY="$ST_HERE/unblockpy_sfz.sh"
lt_fake() { "$REAL_PY" "$ST_HERE/unblockfake_sfz.py" "$@"; }
L=4080-i4; EV3="$KAH_ROWS_BASE/imm26-4080-i4/rows/03-b"; F="$KAH_ROW_FAKE_LOG"
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.trip" "$FAKE_STATE.rw" "$FAKE_STATE.ub" "$FAKE_STATE.ud"; export FAKE_SCEN="$T/scen.json"; "$REAL_PY" "$ST_HERE/unblockscen_sfz.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; rm -rf "$EV3"; }
run() { gr_main --allow-retry selftest "$@" 2>/dev/null; }
fl() { grep -n -m1 -- "$1" "$F" | cut -d: -f1; }
lastl() { grep -n -- "$1" "$F" | tail -1 | cut -d: -f1; }

[ "$U03B_TRIES" = 24 ] && [ "$SZ_MAX_SPOKEN" = 12 ] && chk defaults-24-tries-12-spoken ok || chk defaults-24-tries-12-spoken bad "$U03B_TRIES/$SZ_MAX_SPOKEN"
scen sz-pass; r=$(run 03-b $L); case "$r" in "RESULT 03-b PASS"*) chk gossip-on-tick-5-passes ok;; *) chk gossip-on-tick-5-passes bad "$(echo "$r" | cut -c1-300)";; esac
[ "$(cat "$EV3/gossip_ok.txt" 2>/dev/null)" = "ok tick=5 gated=2 spoken=3" ] && chk counts-recorded ok || chk counts-recorded bad "$(cat "$EV3/gossip_ok.txt" 2>/dev/null)"
[ "$(wc -l < "$EV3/gossip_tries.txt" 2>/dev/null)" = 5 ] && [ ! -e "$EV3/gossip_g6.res" ] && chk stops-at-first-fire ok || chk stops-at-first-fire bad "$(tr '\n' ';' < "$EV3/gossip_tries.txt" 2>/dev/null)"
[ "$(grep -c 'gate=1' "$EV3/gossip_tries.txt")" = 2 ] && grep -q 'tick 1 res=no_gossip gate=1 chance=100' "$EV3/gossip_tries.txt" && chk gate-ticks-flagged ok || chk gate-ticks-flagged bad
s=$(fl 'u3:sznpcset'); st=$(fl 'u3:stream'); rs=$(lastl 'u3:sznpcrest'); ls=$(lastl 'u3:stream')
[ -n "$s" ] && [ -n "$st" ] && [ "$s" -lt "$st" ] && chk npc-seam-set-before-first-pair-request ok || chk npc-seam-set-before-first-pair-request bad "set@$s stream@$st"
[ -n "$rs" ] && [ -n "$ls" ] && [ "$rs" -gt "$ls" ] && chk npc-seam-restored-after-last-request ok || chk npc-seam-restored-after-last-request bad "rest@$rs last@$ls"
grep -qF '"BORED_EVENT_CHANCE":100' "$F" && grep -q "setting_overrides" "$F" && grep -q "update general_settings set value='100'" "$F" && chk seam-writes-npc-layer-and-global ok || chk seam-writes-npc-layer-and-global bad
grep -qF "extended_data #- '{setting_overrides,BORED_EVENT_CHANCE}'" "$F" && chk unset-restored-by-removing-key ok || chk unset-restored-by-removing-key bad
scen sz-npcold; run 03-b $L >/dev/null; grep -qF "jsonb_set(extended_data,'{setting_overrides,BORED_EVENT_CHANCE}','\"70\"'::jsonb)" "$F" && chk old-npc-override-restored ok || chk old-npc-override-restored bad
scen sz-never; r=$(SZ_MAX_SPOKEN=4 run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"0 chance-gated"*"4 reached the speech"*) chk never-setupfail-names-counts ok;; *) chk never-setupfail-names-counts bad "$(echo "$r" | cut -c1-400)";; esac
[ "$(cat "$EV3/gossip_ok.txt")" = "none tries=4 gated=0 spoken=4" ] && chk spoken-budget-bounds-the-loop ok || chk spoken-budget-bounds-the-loop bad "$(cat "$EV3/gossip_ok.txt")"
[ -n "$(lastl 'u3:sznpcrest')" ] && chk seam-restored-after-failure ok || chk seam-restored-after-failure bad
scen sz-gateonly; r=$(U03B_TRIES=5 SZ_MAX_SPOKEN=1 run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"5 tries, 5 chance-gated"*"0 reached the speech"*) chk gate-skips-are-free-and-capped-by-tries ok;; *) chk gate-skips-are-free-and-capped-by-tries bad "$(echo "$r" | cut -c1-400)";; esac
case "$r" in *"SEAM NOT APPLIED"*) chk gate-100-not-flagged bad;; *) chk gate-100-not-flagged ok;; esac
scen sz-seamlow; r=$(U03B_TRIES=3 run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"CHANCE SEAM NOT APPLIED"*"chance=85"*) chk seam-not-applied-flagged ok;; *) chk seam-not-applied-flagged bad "$(echo "$r" | cut -c1-400)";; esac
scen sz-http; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*"every targeted pair request failed"*) chk http-err-setupfail ok;; *) chk http-err-setupfail bad "$(echo "$r" | cut -c1-300)";; esac
[ "$(cat "$EV3/gossip_ok.txt")" = "none tries=2 gated=0 spoken=0" ] && chk http-err-stops-after-2-ticks ok || chk http-err-stops-after-2-ticks bad "$(cat "$EV3/gossip_ok.txt")"
scen sz-nohearsay; r=$(run 03-b $L); case "$r" in "RESULT 03-b SETUP-FAIL"*stobeKnowledgeHearsayFor*) chk nohearsay-setupfail ok;; *) chk nohearsay-setupfail bad "$(echo "$r" | cut -c1-300)";; esac
! grep -q 'u3:sznpcset' "$F" && ! grep -q 'stobe-auto hit' "$F" && chk nohearsay-takes-no-action ok || chk nohearsay-takes-no-action bad

# ---- CLI: unblockrun_sfz.sh as a separate process
cli() { local script="$1"; shift; bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/unblockfake_sfz.py' \"\$@\"; }; export -f lt_fake; export REAL_PY; exec bash '$ST_HERE/$script' \"\$@\"" _ "$@" 2>/dev/null; }
scen sz-pass; o=$(cli unblockrun_sfz.sh 03-b $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 03-b PASS' && [ $rc = 0 ] && chk cli-one-result-line ok || chk cli-one-result-line bad "rc=$rc $(echo "$o" | cut -c1-300)"
scen sz-gateonly; o=$(cli unblockrun_sfz.sh 03-b $L --allow-retry selftest --tries 3 --max-spoken 1); rc=$?
echo "$o" | tail -1 | grep -q '^RESULT 03-b SETUP-FAIL.*3 tries, 3 chance-gated' && [ $rc = 2 ] && chk cli-tries-option-setup-fail-exit-2 ok || chk cli-tries-option-setup-fail-exit-2 bad "rc=$rc $(echo "$o" | tail -1 | cut -c1-300)"
scen sz-never; o=$(cli unblockrun_sfz.sh 03-b $L --allow-retry selftest --max-spoken 2); echo "$o" | tail -1 | grep -q '2 reached the speech' && chk cli-max-spoken-option ok || chk cli-max-spoken-option bad "$(echo "$o" | tail -1 | cut -c1-300)"
scen sz-pass; o=$(cli unblockrun_sfz.sh 03-b $L --dry); echo "$o" | grep -q '^RESULT 03-b DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$(echo "$o" | cut -c1-300)"
o=$(cli unblockrun_sfz.sh 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
"$ST_HERE/unblockpy_sfz.sh" -c 'print(1)' | grep -q 1 && chk shim-passthrough ok || chk shim-passthrough bad
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_d.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_d2.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockrun_d2.sh testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_d.py testing/live-stobe-queue/imm26-assert/rowtools/unblockcheck_d2.py 2>/dev/null && chk d-and-d2-files-untouched ok || chk d-and-d2-files-untouched bad
for f in unblockdefs_sfz.sh unblockrun_sfz.sh unblockpy_sfz.sh unblock_sfz_selftest.sh; do bash -n "$ST_HERE/$f" 2>/dev/null && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
"$REAL_PY" -m py_compile "$ST_HERE/unblockcheck_sfz.py" "$ST_HERE/unblockfake_sfz.py" "$ST_HERE/unblockscen_sfz.py" 2>/dev/null && chk py-compile ok || chk py-compile bad

rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST UNBLOCK-SFZ ALL PASS $ok/$n"; exit 0; else echo "SELFTEST UNBLOCK-SFZ ALL FAIL $ok/$n"; exit 1; fi
