#!/usr/bin/env bash
# hx-selftest_02bd.sh (imm26-rr02): OFFLINE self-test of the 02-bx / 02-dx row runners (hxdefs_02bd.sh, hxcheck_02bd.py, pywrap_02bd.sh, hxrun_02bd.sh).  No game, ssh or DB: the lane is
# simulated by hxfake_02bd.py (-> hxfake_a.py -> hxfake.py -> fakelane.py), assert_principle.py by a logging stub (exact argv), and the REAL v2 assert_principle.py is run over
# the stored 5090 evidence of the two rows (C:/KenshiTestRuns/imm26-5090-hx/02-bx|02-dx, skipped when absent).  Existing scripts are only READ.
# Prints `SELFTEST 02bd-<name> PASS|FAIL` and `SELFTEST 02BD ALL PASS|FAIL n/m`.  Usage: bash rowtools/hx-selftest_02bd.sh
ST_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; A="$ST_HERE/.."
PYB=$(command -v python3 || command -v python); export PYB
T=$(mktemp -d); command -v cygpath >/dev/null && T=$(cygpath -m "$T")
export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 KAH_PF_LLM=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 STUB_LOG="$T/assert.log"
rm -f "$FAKE_STATE".b; unset KAH_AGENT_NAME KAH_ROW_DRY HX_OUT HX_SAVE HX_SAVE2 HX_PRELOADED HX_NATIVE HX_ASSERT_DIR HX02B_FACTION HX02B_VICTIM
mkdir -p "$KAH_ROWS_BASE" "$T/stubs"
printf '%s\n' 'import os, sys' "open(os.environ['STUB_LOG'], 'a').write(' '.join(sys.argv[1:]) + chr(10))" "print('RESULT %s %s stub-evidence' % (sys.argv[1], os.environ.get('STUB_KIND', 'PASS')))" > "$T/stubs/assert_principle.py"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST 02bd-$1 PASS ${3:-}"; else echo "SELFTEST 02bd-$1 FAIL ${3:-}"; fi; }
for f in hxdefs_02bd.sh hxrun_02bd.sh pywrap_02bd.sh; do bash -n "$ST_HERE/$f" && chk "bash-n-$f" ok || chk "bash-n-$f" bad; done
"$PYB" -I -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$ST_HERE/hxcheck_02bd.py" && chk py-syntax ok || chk py-syntax bad

. "$A/go-row.sh"; . "$ST_HERE/hxdefs.sh"; . "$ST_HERE/hxdefs_a.sh"; . "$ST_HERE/hxdefs_02bd.sh"
PY="$ST_HERE/pywrap_02bd.sh"
lt_fake() { "$PYB" "$ST_HERE/hxfake_02bd.py" "$@"; }
scen() { rm -f "$FAKE_STATE" "$FAKE_STATE.hx" "$FAKE_STATE.hxa" "$FAKE_STATE.b" "$STUB_LOG"; export FAKE_SCEN="$T/scen.json"; "$PYB" "$ST_HERE/hxscen_a.py" "$1" > "$FAKE_SCEN"; : > "$KAH_ROW_FAKE_LOG"; }
run() { gr_main --allow-retry "selftest" "$@" 2>/dev/null; }
L=5090-i3; EVD="$KAH_ROWS_BASE/imm26-5090-i3/rows"
export HX_ASSERT_DIR="$T/stubs" HX_SAVE=save-A HX_SAVE2=save-B
logn() { grep -c -- "$1" "$KAH_ROW_FAKE_LOG"; }
argv1() { tr '\\' '/' < "$STUB_LOG" 2>/dev/null | sed -E 's#[^ ]*/##g' | head -1; }

# ---- 02-bx
scen base; r=$(run 02-bx $L); D="$EVD/02-bx"
case "$r" in "RESULT 02-bx PASS"*) chk 02-bx-pass ok;; *) chk 02-bx-pass bad "$r";; esac
[ "$(argv1)" = "02-bx --target T1 T2 T3 --ctl S1 S2 S3 --principle slavery --voice-min 3" ] && chk 02-bx-assert-argv ok || chk 02-bx-assert-argv bad "$(cat "$STUB_LOG")"
ok3=1; for d in T1 T2 T3; do for f in principle_rows.txt state_after.txt server_log.txt effects_full.txt utterance.txt; do [ -f "$D/$d/$f" ] || { ok3=0; echo "missing $d/$f"; }; done; done
[ "$ok3" = 1 ] && grep -q 'slavery|opposed|firm' "$D/T1/principle_rows.txt" && chk 02-bx-target-bundle-files ok || chk 02-bx-target-bundle-files bad
[ "$(grep -c IMM26_PRINCIPLE_VOICED "$D/T1/server_log.txt")" -ge 3 ] && cmp -s "$D/T1/server_log.txt" "$D/T3/server_log.txt" && chk 02-bx-server-log-in-all-T-dirs ok || chk 02-bx-server-log-in-all-T-dirs bad
[ "$(cat "$D/T1/utterance.txt")" = "Help me take that captive and put him in shackles." ] && [ "$(cat "$D/T2/utterance.txt")" = "Chain up this prisoner for me, I will pay you." ] && [ "$(cat "$D/T3/utterance.txt")" = "Grab the rope, he is coming with us as a slave." ] && [ "$(cat "$D/S2/utterance.txt")" = "$(cat "$D/T2/utterance.txt")" ] && chk 02-bx-requests-verbatim-same-for-control ok || chk 02-bx-requests-verbatim-same-for-control bad
[ -f "$D/S1/reply.txt" ] && [ -f "$D/S3/effects_full.txt" ] && grep -q 'spawn "Hungry Bandit" .Slave Traders.' "$KAH_ROW_FAKE_LOG" && chk 02-bx-control-spawned-slaver-faction ok || chk 02-bx-control-spawned-slaver-faction bad
[ "$(logn 'stobe-auto load save-A')" -ge 1 ] && [ "$(logn 'stobe-auto load save-B')" -ge 1 ] && chk 02-bx-two-saves ok || chk 02-bx-two-saves bad "A=$(logn 'stobe-auto load save-A') B=$(logn 'stobe-auto load save-B')"
grep -q "personality||" "$KAH_ROW_FAKE_LOG" && grep -q "replace(personality" "$KAH_ROW_FAKE_LOG" && cmp -s "$D/profile_md5_original.txt" "$D/profile_md5_restored.txt" && chk 02-bx-profile-set-then-restored ok || chk 02-bx-profile-set-then-restored bad
[ "$(logn "delete from imm26_npc_principle where npc_name='Cind")" -ge 1 ] && chk 02-bx-fresh-principle-rows ok || chk 02-bx-fresh-principle-rows bad
[ "$(cat "$D/principle.txt")" = slavery ] && chk 02-bx-principle-file ok || chk 02-bx-principle-file bad
# sentence already in the text -> profile md5 unchanged -> SETUP-FAIL, never a silent pass
scen base; export HX02C_TEXT=" Proud and stubborn"; r=$(run 02-bx $L); unset HX02C_TEXT
case "$r" in "RESULT 02-bx SETUP-FAIL"*"did not change the profile"*) chk 02-bx-sentence-not-applied-setup-fail ok;; *) chk 02-bx-sentence-not-applied-setup-fail bad "$r";; esac
# spawn fails -> SETUP-FAIL, and the profile is still restored
scen base; "$PYB" -c "import json,os;p=os.environ['FAKE_SCEN'];s=json.load(open(p));s['spawn_fail']=True;json.dump(s,open(p,'w'))"
r=$(run 02-bx $L); case "$r" in "RESULT 02-bx SETUP-FAIL"*spawn*) chk 02-bx-spawn-fail-setup-fail ok;; *) chk 02-bx-spawn-fail-setup-fail bad "$r";; esac
cmp -s "$EVD/02-bx/profile_md5_original.txt" "$EVD/02-bx/profile_md5_restored.txt" && chk 02-bx-restore-on-failure ok || chk 02-bx-restore-on-failure bad
# stub FAIL propagates
scen base; r=$(STUB_KIND=FAIL run 02-bx $L); case "$r" in "RESULT 02-bx FAIL"*) chk 02-bx-fail-propagates ok;; *) chk 02-bx-fail-propagates bad "$r";; esac

# ---- 02-dx
scen base; r=$(run 02-dx $L); D="$EVD/02-dx"
case "$r" in "RESULT 02-dx PASS"*) chk 02-dx-pass ok;; *) chk 02-dx-pass bad "$r";; esac
[ "$(argv1)" = "02-dx --target T1 T2 T3 --ctl C1 C2 C3 --principle slavery" ] && chk 02-dx-assert-argv ok || chk 02-dx-assert-argv bad "$(cat "$STUB_LOG")"
grep -q '"aff":60' "$D/T1/haff.txt" && grep -q '"aff":0' "$D/C1/haff.txt" && [ -f "$D/T3/haff.txt" ] && [ -f "$D/C3/effects_full.txt" ] && chk 02-dx-haff-60-and-0 ok || chk 02-dx-haff-60-and-0 bad "$(head -c 200 "$D/C1/haff.txt" 2>&1)"
[ "$(cat "$D/T3/utterance.txt")" = "I will pay you 500 cats to shackle that captive." ] && [ "$(cat "$D/C3/utterance.txt")" = "$(cat "$D/T3/utterance.txt")" ] && [ "$(cat "$D/C2/utterance.txt")" = "Chain up this prisoner for me." ] && chk 02-dx-requests ok || chk 02-dx-requests bad
[ "$(logn 'delete from imm26_npc_principle')" -ge 2 ] && cmp -s "$D/profile_md5_original.txt" "$D/profile_md5_restored.txt" && chk 02-dx-fresh-rows-per-phase-and-restore ok || chk 02-dx-fresh-rows-per-phase-and-restore bad
[ "$(logn 'personality||')" -ge 2 ] && chk 02-dx-principle-set-in-both-phases ok || chk 02-dx-principle-set-in-both-phases bad "$(logn 'personality||')"

# ---- checker on missing dirs + real v2 assert over stored evidence
E="$T/empty"; mkdir -p "$E"
for rw in 02-bx 02-dx; do r=$("$PYB" -I "$ST_HERE/hxcheck_02bd.py" $rw "$E"); case "$r" in "RESULT $rw SETUP-FAIL bundle dirs missing"*) chk "check-missing-dirs-$rw" ok;; *) chk "check-missing-dirs-$rw" bad "$r";; esac; done
"$PYB" -I "$ST_HERE/hxcheck_02bd.py" 02-ax "$E" >/dev/null 2>&1; [ $? = 2 ] && chk check-refuses-other-rows ok || chk check-refuses-other-rows bad
SB=C:/KenshiTestRuns/imm26-5090-hx/02-bx; SD=C:/KenshiTestRuns/imm26-5090-hx/02-dx
if [ -d "$SB/T1" ] && [ -d "$SD/T1" ]; then
  mkdir -p "$T/rb" "$T/rd"; echo "$SB" > "$T/rb/bundle_dir.txt"; echo "$SD" > "$T/rd/bundle_dir.txt"
  r=$(env -u HX_ASSERT_DIR "$PYB" -I "$ST_HERE/hxcheck_02bd.py" 02-bx "$T/rb"); case "$r" in "RESULT 02-bx FAIL T2:touches_principle_line!"*) chk real-v2-assert-02bx-stored-evidence-fails-only-T2-regex ok;; *) chk real-v2-assert-02bx-stored-evidence-fails-only-T2-regex bad "${r:0:200}";; esac
  r=$(env -u HX_ASSERT_DIR "$PYB" -I "$ST_HERE/hxcheck_02bd.py" 02-dx "$T/rd"); case "$r" in "RESULT 02-dx PASS"*) chk real-v2-assert-02dx-stored-evidence-pass ok;; *) chk real-v2-assert-02dx-stored-evidence-pass bad "${r:0:200}";; esac
else echo "SELFTEST 02bd-real-v2-assert SKIP (stored 5090 evidence absent)"; fi

# ---- hxrun_02bd.sh
r=$(bash "$ST_HERE/hxrun_02bd.sh" 02-ax $L --dry 2>&1 | tail -1); echo "$r" | grep -q '^RESULT 02-ax SETUP-FAIL not a 02-bx/02-dx row' && chk run-refuses-other-rows ok || chk run-refuses-other-rows bad "$r"
for row in 02-bx 02-dx; do
  scen base
  r=$(env KAH_ROW_DRY=1 HX_ASSERT_DIR="$T/stubs" bash "$ST_HERE/hxrun_02bd.sh" $row $L --dry --no-reload --save s1 --save2 s2 --allow-retry selftest 2>&1 | grep -c "^RESULT $row ")
  [ "$r" = 1 ] && chk "run-dry-$row-one-result" ok || chk "run-dry-$row-one-result" bad "lines=$r"
done
grep -q 'HX_ASSERT_DIR="${HX_ASSERT_DIR:-$(cd "$HX_HERE/../v2" && pwd)}"' "$ST_HERE/hxrun_02bd.sh" && chk run-defaults-to-v2-asserters ok || chk run-defaults-to-v2-asserters bad
git -C "$A/../../.." diff --quiet -- testing/live-stobe-queue/imm26-assert/rowtools/hxdefs.sh testing/live-stobe-queue/imm26-assert/rowtools/hxdefs_a.sh testing/live-stobe-queue/imm26-assert/rowtools/hxrun.sh testing/live-stobe-queue/imm26-assert/rowtools/hxrun_v2.sh testing/live-stobe-queue/imm26-assert/rowtools/hxcheck.py testing/live-stobe-queue/imm26-assert/rowtools/hxcheck_a.py testing/live-stobe-queue/imm26-assert/go-row.sh 2>/dev/null && chk existing-files-untouched ok || chk existing-files-untouched bad modified
rm -rf "$T"
if [ "$ok" = "$n" ]; then echo "SELFTEST 02BD ALL PASS $ok/$n"; exit 0; else echo "SELFTEST 02BD ALL FAIL $ok/$n"; exit 1; fi
