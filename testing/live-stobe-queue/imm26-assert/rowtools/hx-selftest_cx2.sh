#!/usr/bin/env bash
# hx-selftest_cx2.sh: OFFLINE self-test of 05-cx v2 (hxdefs_cx2.sh / hxrun_cx2.sh, imm26-sfS). No game, ssh or DB (hxfake.py + fakelane.py, scenarios hxscen_cx2.py).
# Prints `SELFTEST hxcx2-<name> PASS|FAIL` and `SELFTEST HXCX2 ALL PASS|FAIL n/m`.  Usage: bash rowtools/hx-selftest_cx2.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log"
unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX13_RUNS HX_KEEP HX_PRELOADED HX_NATIVE HX05_NAMES HX05_NOPIN HX05_NSPAWN
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_principle.py"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST hxcx2-$1 PASS ${3:-}"; else echo "SELFTEST hxcx2-$1 FAIL ${3:-}"; fi; }
. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$ST_HERE/hxdefs_b.sh"; . "$ST_HERE/hxdefs_cx2.sh"
PY="$ST_HERE/pywrap_hx.sh"
lt_fake() { "$PYB" "$ST_HERE/hxfake.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.hx" "$STUB_LOG"; export FAKE_SCEN="$T/scen.json"; "$PYB" "$ST_HERE/hxscen_cx2.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry "selftest" "$@" 2>/dev/null; }
L=5090-i3; EVD="$KAH_ROWS_BASE/imm26-5090-i3/rows"; D="$EVD/05-cx"
# --- the existing files this ticket must not touch
BADORIG=""; for f in hxdefs_b.sh unblockdefs_a.sh unblockrun_a.sh hxdefs.sh hxrun.sh hxcheck_b.py; do
  git -C "$ST_HERE" diff --quiet HEAD -- "$f" 2>/dev/null || BADORIG="$BADORIG $f"; done
[ -z "$BADORIG" ] && chk originals-untouched ok || chk originals-untouched bad "differs from HEAD:$BADORIG"
# --- PASS path with the stub assert
export HX_ASSERT_DIR="$T/stubs"
scen base; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx PASS"*) chk pass-stub ok;; *) chk pass-stub bad "$r";; esac
got=$(tail -1 "$STUB_LOG" 2>/dev/null | sed -E 's#[^ ]*/##g'); want="05-cx --target E1 E2 E3 --ctl N1 N2 N3 --hidden H1 H2 H3"
[ "$got" = "$want" ] && chk assert-argv-unchanged ok || chk assert-argv-unchanged bad "got '$got' want '$want'"
sn=$(grep -c 'stobe-auto setname' "$KAH_ROW_FAKE_LOG"); un=$(grep 'stobe-auto setname' "$KAH_ROW_FAKE_LOG" | grep -oE "setname '[^']*' '[^']*'" | awk '{print $3}' | sort -u | wc -l)
[ "$sn" = 4 ] && [ "$un" = 4 ] && grep -q "setname '#[0-9]*/1' 'Hollin'" "$KAH_ROW_FAKE_LOG" && chk distinct-names ok || chk distinct-names bad "setname=$sn distinct=$un"
[ "$(wc -l < "$D/visible.txt")" = 3 ] && [ "$(awk '{print $1}' "$D/visible.txt" | sort -u | wc -l)" = 3 ] && grep -q 'Hollin' "$D/sleeper.txt" && chk visible-and-sleeper-files ok || chk visible-and-sleeper-files bad "$(cat "$D/visible.txt" 2>&1 | tr '\n' ' ')"
np=$(grep -c "stobe-auto pin 'Malzin' at" "$KAH_ROW_FAKE_LOG"); nv=$(grep -cE "stobe-auto pin '#[0-9]+/1' </dev/null" "$KAH_ROW_FAKE_LOG"); no=$(grep -c "pin '.*' off" "$KAH_ROW_FAKE_LOG")
[ "$np" = 2 ] && [ "$nv" = 3 ] && [ "$no" -ge 4 ] && chk pins ok || chk pins bad "malzin-far=$np visible=$nv off=$no"
grep -q "stobe-auto sleep '#[0-9]*/1'" "$KAH_ROW_FAKE_LOG" && chk sleeper-by-handle ok || chk sleeper-by-handle bad
{ [ -f "$D/E1/infonpc_people.txt" ] && [ -f "$D/H1/infonpc_people.txt" ] && [ -f "$D/N1/infonpc_people.txt" ] && grep -q "type='infonpc' order by rowid desc limit 5" "$KAH_ROW_FAKE_LOG" && grep -q "coalesce(people" "$KAH_ROW_FAKE_LOG" && [ -f "$D/scene_H_native.txt" ]; } && chk infonpc-people-in-bundle ok || chk infonpc-people-in-bundle bad
[ "$(grep -c 'E sample E' "$D/phases.txt")" = 3 ] && chk E-extras-before-each-sample ok || chk E-extras-before-each-sample bad "$(grep -c 'E sample E' "$D/phases.txt" 2>&1)"
# roster helper: run the REAL command text against a stub stobe-auto (the old printf+sed form failed with 'unterminated s')
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "Shay #1/1 [Nameless] pos=1,1,1 | Malzin #77/1 [Drifters] pos=2,2,2 | Hollin #5/1 [Hungry Bandit] pos=3,3,3"\n' > "$T/bin/stobe-auto"; chmod +x "$T/bin/stobe-auto"
( HXD="$T/rost"; EV="$T/rost"; mkdir -p "$HXD"; lt_h() { PATH="$T/bin:$PATH" bash; }; hx05_roster E; cp "$HXD/scene_E_roster.txt" "$T/rost.out" )
[ "$(grep -c '#[0-9]*/[0-9]' "$T/rost.out")" = 3 ] && ! grep -qi 'unterminated\|sed:' "$T/rost.out" && chk roster-helper-sed-fixed ok || chk roster-helper-sed-fixed bad "$(head -3 "$T/rost.out")"
# --- the REAL assert on the simulated bundles
unset HX_ASSERT_DIR
scen base; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx PASS"*) chk real-assert-pass ok;; *) chk real-assert-pass bad "$r";; esac
scen absolute; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx FAIL"*) chk real-assert-absolute-claim-still-fails ok;; *) chk real-assert-absolute-claim-still-fails bad "$r";; esac
scen norosterN; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx FAIL"*) chk real-assert-small-N-roster-still-fails ok;; *) chk real-assert-small-N-roster-still-fails bad "$r";; esac
export HX_ASSERT_DIR="$T/stubs"
# --- conditional hedge: a non-empty roster at E2 is SETUP-FAIL naming E2 (the first run was a FAIL on invalid data)
scen e2back; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx SETUP-FAIL"*"E scene is not empty at E2"*"Malzin"*) chk E2-nonempty-setup-fail ok;; *) chk E2-nonempty-setup-fail bad "$r";; esac
scen nonempty; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx SETUP-FAIL"*"E scene is not empty at E1"*"Jetha"*) chk E1-nonempty-setup-fail ok;; *) chk E1-nonempty-setup-fail bad "$r";; esac
scen extras; r=$(run 05-cx $L); case "$r" in "RESULT 05-cx SETUP-FAIL"*"still within 60 u"*) chk extras-left-setup-fail ok;; *) chk extras-left-setup-fail bad "$r";; esac
scen base; r=$(STUB_KIND=FAIL run 05-cx $L); case "$r" in "RESULT 05-cx FAIL"*) chk assert-fail-passes-through ok;; *) chk assert-fail-passes-through bad "$r";; esac
scen base; HX05_NOPIN=1 run 05-cx $L >/dev/null; ! grep -q 'stobe-auto pin' "$KAH_ROW_FAKE_LOG" && chk no-pin-switch ok || chk no-pin-switch bad
# --- CLI
cli() { bash -c ". '$ST_HERE/lane.sh'; lt_fake() { \"\$PYB\" '$ST_HERE/hxfake.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/hxrun_cx2.sh' \"\$@\"" _ "$@" 2>/dev/null; }
scen base; o=$(cli 05-cx $L --allow-retry selftest --names "Aa Bb Cc Dd"); rc=$?
[ "$(echo "$o" | grep -c '^RESULT ')" = 1 ] && echo "$o" | tail -1 | grep -q '^RESULT 05-cx PASS' && [ $rc = 0 ] && grep -q "'Cc'" "$KAH_ROW_FAKE_LOG" && chk cli-run-and-names ok || chk cli-run-and-names bad "rc=$rc $o"
echo "$o" | grep -q '^EVIDENCE 05-cx phases.txt' && chk cli-evidence-lines ok || chk cli-evidence-lines bad "$o"
grep -q 'stobe-auto load kah-imm26-5090-hxA' "$KAH_ROW_FAKE_LOG" && chk cli-reload-base-save ok || chk cli-reload-base-save bad
scen base; o=$(cli 05-cx $L --dry); echo "$o" | grep -q '^RESULT 05-cx DRY-RUN' && chk cli-dry-run ok || chk cli-dry-run bad "$o"
o=$(cli 17-bx $L); echo "$o" | grep -q 'RESULT 17-bx SETUP-FAIL hxrun_cx2.sh runs 05-cx only' && chk cli-other-row-refused ok || chk cli-other-row-refused bad "$o"
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST HXCX2 ALL PASS $ok/$n"; exit 0; else echo "SELFTEST HXCX2 ALL FAIL $ok/$n"; exit 1; fi
