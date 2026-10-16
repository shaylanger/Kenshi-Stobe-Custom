#!/usr/bin/env bash
# hx-selftest_b.sh: OFFLINE self-test of the family-B hardening row 05-cx (hxdefs_b.sh / hxcheck_b.py via hxrun.sh). No game, ssh or DB (hxfake.py + fakelane.py, scenarios hxscen_b.py).
# Prints `SELFTEST hxb-<name> PASS|FAIL` and `SELFTEST HXB ALL PASS|FAIL n/m`.  Usage: bash rowtools/hx-selftest_b.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log"
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX13_RUNS HX_KEEP HX_PRELOADED HX_NATIVE
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_principle.py"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hxb-$1 PASS ${3:-}"; else echo "SELFTEST hxb-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$ST_HERE/hxdefs_b.sh"
PY="$ST_HERE/pywrap_hx.sh"
lt_fake() { "$PYB" "$ST_HERE/hxfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.hx" "$STUB_LOG"; export FAKE_SCEN="$T/scen.json"; "$PYB" "$ST_HERE/hxscen_b.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry "selftest" "$@" 2>/dev/null; }
L=5090-i3; EVD="$KAH_ROWS_BASE/imm26-5090-i3/rows"
echo "$HXB_ROWS" | grep -q '05-cx' && chk rows-registered ok || chk rows-registered bad "$HXB_ROWS"
# --- PASS path with the stub assert: exact command line
export HX_ASSERT_DIR="$T/stubs"
scen base; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx PASS"*) chk pass-stub ok;; *) chk pass-stub bad "$r";; esac
got=$(tail -1 "$STUB_LOG" 2>/dev/null | sed -E 's#[^ ]*/##g'); want="05-cx --target E1 E2 E3 --ctl N1 N2 N3 --hidden H1 H2 H3"
[ "$got" = "$want" ] && chk assert-argv ok || chk assert-argv bad "got '$got' want '$want'"
D="$EVD/05-cx"
{ [ -f "$D/E1/utterance.txt" ] && [ -f "$D/H3/effects_full.txt" ] && [ -f "$D/N2/prompt.txt" ] && [ "$(cat "$D/E1/utterance.txt")" = "Are we alone?" ] && [ "$(cat "$D/E2/utterance.txt")" = "Is anyone else around here?" ] && [ "$(cat "$D/E3/utterance.txt")" = "Can anyone hear us?" ] && [ "$(cat "$D/N3/utterance.txt")" = "Can anyone hear us?" ]; } && chk bundles-and-3-questions ok || chk bundles-and-3-questions bad "$(ls "$D" 2>&1 | tr '\n' ' ')"
grep -q 'Dorn' "$D/sleeper.txt" && grep -q 'stobe-auto sleep' "$KAH_ROW_FAKE_LOG" && [ "$(wc -l < "$D/visible.txt")" = 3 ] && [ -f "$D/scene_E_roster.txt" ] && [ -f "$D/scene_N_roster.txt" ] && chk scene-files ok || chk scene-files bad
[ "$(grep -c 'stobe-auto load' "$KAH_ROW_FAKE_LOG")" = 2 ] && chk two-loads ok || chk two-loads bad "$(grep -c 'stobe-auto load' "$KAH_ROW_FAKE_LOG")"
grep -q 'chars 60' "$KAH_ROW_FAKE_LOG" && grep -q 'teleport Malzin' "$KAH_ROW_FAKE_LOG" && chk extras60-and-malzin-away ok || chk extras60-and-malzin-away bad
# --- the REAL assert on the simulated bundles: PASS (hedged replies, roster E empty, N >= 3, H lists the sleeper)
unset HX_ASSERT_DIR
scen base; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx PASS"*) chk real-assert-pass ok;; *) chk real-assert-pass bad "$r";; esac
scen absolute; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx FAIL"*) chk real-assert-absolute-claim-fails ok;; *) chk real-assert-absolute-claim-fails bad "$r";; esac
scen norosterN; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx FAIL"*) chk real-assert-small-N-roster-fails ok;; *) chk real-assert-small-N-roster-fails bad "$r";; esac
export HX_ASSERT_DIR="$T/stubs"
# --- SETUP-FAIL variants
scen nonempty; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx SETUP-FAIL"*"E scene is not empty"*"Jetha"*) chk E-not-empty-setup-fail ok;; *) chk E-not-empty-setup-fail bad "$r";; esac
scen extras; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx SETUP-FAIL"*"still within 60 u"*) chk E-extras-left-setup-fail ok;; *) chk E-extras-left-setup-fail bad "$r";; esac
scen base; r=$(STUB_KIND=FAIL run 05-cx $L); case "$r" in "RESULT 05-cx FAIL"*) chk assert-fail-passes-through ok;; *) chk assert-fail-passes-through bad "$r";; esac
E="$T/empty"; mkdir -p "$E"; r=$("$PYB" "$ST_HERE/hxcheck_b.py" 05-cx "$E"); case "$r" in "RESULT 05-cx SETUP-FAIL bundle dirs missing"*) chk missing-bundle-dir ok;; *) chk missing-bundle-dir bad "$r";; esac
# --- CLI hxrun.sh: ONE RESULT line, dry run, unknown row, old rows still routed to hxcheck.py
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$PYB\" '$ST_HERE/hxfake.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/hxrun.sh' \"\$@\"" _ "$@" 2>/dev/null; }
scen base; o=$(cli 05-cx $L --allow-retry selftest); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 05-cx PASS' && [ $rc = 0 ] && chk cli-hxrun ok || chk cli-hxrun bad "rc=$rc $o"
grep -q 'stobe-auto load kah-imm26-5090-hxA' "$KAH_ROW_FAKE_LOG" && chk cli-reload-base-save ok || chk cli-reload-base-save bad "$(grep 'stobe-auto load' "$KAH_ROW_FAKE_LOG" | head -2)"
scen base; o=$(cli 05-cx $L --dry); echo "$o" | grep -q '^RESULT 05-cx DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
scen base; o=$(cli IMM-05-cx $L --dry 2>&1); echo "$o" | grep -q '^RESULT IMM-05-cx DRY-RUN' && chk cli-dry-run-imm-prefix ok || chk cli-dry-run-imm-prefix bad "$o"
o=$(cli 99-z $L); echo "$o" | grep -q 'RESULT 99-z SETUP-FAIL not a hardening row' && chk cli-unknown-row ok || chk cli-unknown-row bad "$o"
scen base; o=$(cli 17-bx $L --dry); echo "$o" | grep -q '^RESULT 17-bx DRY-RUN' && chk cli-old-row-still-works ok || chk cli-old-row-still-works bad "$o"
"$PYB" "$ST_HERE/hxcheck_b.py" --has 17-bx && chk has-only-own-rows bad || chk has-only-own-rows ok
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST HXB ALL PASS $ok/$n"; exit 0; else echo "SELFTEST HXB ALL FAIL $ok/$n"; exit 1; fi
