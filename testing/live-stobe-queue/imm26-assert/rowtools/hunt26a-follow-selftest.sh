#!/usr/bin/env bash
# hunt26a-follow-selftest.sh (imm26-fix26a): OFFLINE selftest of hunt26a-run.sh.candidate (v2: continuous Shay follow, Katana grep, native evidence). No game, ssh, WSL or DB.
# The candidate is staged as hunt26a-run.sh in a TEMP COPY of imm26-assert (the live hunt26a-run.sh is never touched). Reuses hunt26afake.py / hunt26ascen.py / the stubs.
# Prints `SELFTEST fix26a-<name> PASS|FAIL` and `SELFTEST FIX26A ALL PASS|FAIL n/m`. Usage: bash rowtools/hunt26a-follow-selftest.sh   (about 10 s)
ST_REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PY=$(command -v python3 || command -v python)
T=$(mktemp -d); cp -r "$ST_REAL/.." "$T/a" && rm -rf "$T/a/__pycache__" "$T/a/rowtools/__pycache__"
ST_HERE="$T/a/rowtools"
cp "$ST_REAL/hunt26a-run.sh.candidate" "$ST_HERE/hunt26a-run.sh"
export KAH_ROWS_BASE="$T/runs" KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG="$T/fake.log" KAH_PF_ISOLATION=0 FAKE_STATE="$T/state.json"
export ROW_SETTLE=0 ROW_WAIT=1 RW_SAY_WAIT=0
unset KAH_AGENT_NAME KAH_ROW_DRY RW_HUNT_SPEED RW_FOLLOW_STEP RW_FOLLOW_N RW_HUNT_WAIT RW_ACCEPT_WAIT RW_FIGHT_TRIES
mkdir -p "$KAH_ROWS_BASE"
n=0; ok=0
chk() { n=$((n+1)); if [ "$2" = ok ]; then ok=$((ok+1)); echo "SELFTEST fix26a-$1 PASS ${3:-}"; else echo "SELFTEST fix26a-$1 FAIL ${3:-}"; fi; }
F="$KAH_ROW_FAKE_LOG"
OFFER_OK="Shall we travel to hunt one goat together?"
a_scen() {   # a_scen <hunt26ascen name> [python snippet editing S]
  rm -f "$FAKE_STATE" "$FAKE_STATE".* "$T/stubcount"; export FAKE_SCEN="$T/scen_a.json"
  "$REAL_PY" "$ST_HERE/hunt26ascen.py" "$1" > "$FAKE_SCEN"
  if [ -n "${2:-}" ]; then "$REAL_PY" - "$FAKE_SCEN" "$2" <<'PYEOF'
import json, sys
p, code = sys.argv[1], sys.argv[2]
S = json.load(open(p)); exec(code); json.dump(S, open(p, 'w'))
PYEOF
  fi
  : > "$F"
}
a_run() {   # a_run <outdir> [VAR=value...]
  local od="$1"; shift
  env STUB_COUNT="$T/stubcount" HUNT26A_SCENE="$ST_HERE/hunt26a-scene-stub.sh" HUNT26A_INJECT="$ST_HERE/hunt26a-inject-stub.sh" "$@" \
    bash -c ". '$ST_HERE/lane.sh'; lt_fake() { '$REAL_PY' '$ST_HERE/hunt26afake.py' \"\$@\"; }; export -f lt_fake; exec bash '$ST_HERE/hunt26a-run.sh' '$od'" 2>/dev/null
}

# 1. pass: the unchanged verdict logic still PASSes on a completed, delivered hunt
a_scen pass; o=$(a_run "$T/o1" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 PASS' && [ $rc = 0 ] && chk pass ok || chk pass bad "rc=$rc $(echo "$o" | cut -c1-300)"

# 2. follow: ONE harness call per poll = N jumps, each preceded by a where and followed by sleep 1 (about 1.5 s real per jump); no 4 s step
c=$(grep -c 'for i in $(seq 1 5); do stobe-auto where .*stobe-auto teleport Shay .*sleep 1; done' "$F")
[ "$c" -ge 3 ] && chk follow-5-jumps-per-call-sleep-1 ok "calls=$c" || chk follow-5-jumps-per-call-sleep-1 bad "calls=$c"
grep -q 'sleep 4' "$F" && chk no-4s-step bad || chk no-4s-step ok
a_scen pass; o=$(a_run "$T/o1b" "STUB_TEXT_SEQ=$OFFER_OK" RW_FOLLOW_N=3 RW_FOLLOW_STEP=0.5)
grep -q 'seq 1 3); do .*sleep 0.5; done' "$F" && chk follow-knobs ok || chk follow-knobs bad

# 3. speed: default 1 during the follow, restored to 0.5 at the end (also on FAIL)
a_scen pass; o=$(a_run "$T/o2" "STUB_TEXT_SEQ=$OFFER_OK")
l1=$(grep -n 'stobe-auto speed 1 ' "$F" | head -1 | cut -d: -f1); l2=$(grep -n 'stobe-auto speed 0.5 ' "$F" | tail -1 | cut -d: -f1); lf=$(grep -n 'for i in' "$F" | head -1 | cut -d: -f1)
[ -n "$l1" ] && [ -n "$l2" ] && [ -n "$lf" ] && [ "$l1" -lt "$lf" ] && [ "$lf" -lt "$l2" ] && chk speed-1-then-restored ok || chk speed-1-then-restored bad "l1=$l1 lf=$lf l2=$l2"
a_scen failed; o=$(a_run "$T/o2b" "STUB_TEXT_SEQ=$OFFER_OK"); grep -q 'stobe-auto speed 0.5 ' "$F" && chk speed-restored-on-fail ok || chk speed-restored-on-fail bad

# 4. separation evidence: every jump's pre-jump separation is logged; > 35 is flagged (evidence only, the verdict still comes from the real record)
a_scen pass 'S["seps"]=["dist=8.0\ndist=12.5\ndist=20.1\ndist=9.0\ndist=11.0"]'; o=$(a_run "$T/o3" "STUB_TEXT_SEQ=$OFFER_OK")
grep -q 'sep_before=\[8.0,12.5,20.1,9.0,11.0\]$' "$T/o3/follow.log" && ! grep -q 'SEP>35' "$T/o3/follow.log" && chk sep-logged-clean ok || chk sep-logged-clean bad "$(head -2 "$T/o3/follow.log" | cut -c1-200)"
a_scen pass 'S["seps"]=["dist=8.0\ndist=34.9\ndist=35.6\ndist=9.0\ndist=51.0"]'; o=$(a_run "$T/o3b" "STUB_TEXT_SEQ=$OFFER_OK")
grep -q 'SEP>35 x2' "$T/o3b/follow.log" && chk sep-over-35-flagged ok || chk sep-over-35-flagged bad "$(head -1 "$T/o3b/follow.log" | cut -c1-200)"

# 5. Katana: the real inventory names it "Chisa Katana" -> no second give (v1 grepped "name":"Katana and re-gave it every run)
a_scen pass 'S["inv"]=["{\"items\":[{\"name\":\"Chisa Katana\"}]}","{\"items\":[{\"name\":\"Chisa Katana\"}]}","{\"items\":[{\"name\":\"Chisa Katana\"},{\"name\":\"Raw Meat\",\"count\":2}]}"]'
o=$(a_run "$T/o4" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
grep -q 'stobe-auto give' "$F" && chk chisa-katana-no-give bad || chk chisa-katana-no-give ok
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 PASS' && grep -q 'Raw Meat' "$T/o4/inv_after.txt" && ! grep -qi katana "$T/o4/inv_after.txt" && chk chisa-katana-excluded-from-delta ok || chk chisa-katana-excluded-from-delta bad "rc=$rc $(cat "$T/o4/inv_after.txt" 2>/dev/null | tr '\n' ,)"
a_scen pass; o=$(a_run "$T/o4b" "STUB_TEXT_SEQ=$OFFER_OK"); grep -q 'stobe-auto give .*Katana' "$F" && chk katana-given-when-absent ok || chk katana-given-when-absent bad

# 6. nothing weakened: a failed/timeout record, no inventory gain, no participation and a Yes that never lands are still not PASS
a_scen failed; o=$(a_run "$T/o5" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?
echo "$o" | grep -q "^HUNT26A-RUN 5090-i5 FAIL.*ended 'failed' reason='timeout'" && [ $rc = 1 ] && chk failed-record-is-fail ok || chk failed-record-is-fail bad "rc=$rc $(echo "$o" | cut -c1-200)"
a_scen noinv; o=$(a_run "$T/o6" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?; echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 FAIL' && [ $rc = 1 ] && chk no-inventory-delta-not-pass ok || chk no-inventory-delta-not-pass bad
a_scen nopart; o=$(a_run "$T/o7" "STUB_TEXT_SEQ=$OFFER_OK"); rc=$?; echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 FAIL' && [ $rc = 1 ] && chk no-participation-not-pass ok || chk no-participation-not-pass bad
a_scen proposed; o=$(a_run "$T/o8" "STUB_TEXT_SEQ=$OFFER_OK" RW_ACCEPT_WAIT=8); rc=$?
echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 SETUP-FAIL the Yes did not move the Hunt record' && [ $rc = 2 ] && chk accept-not-landed-setup-fail ok || chk accept-not-landed-setup-fail bad "rc=$rc $(echo "$o" | cut -c1-200)"
a_scen pass; o=$(a_run "$T/o9" "STUB_TEXT_SEQ=BAD"); rc=$?; echo "$o" | grep -q '^HUNT26A-RUN 5090-i5 SETUP-FAIL scene not ok' && [ $rc = 2 ] && chk bad-scene-setup-fail ok || chk bad-scene-setup-fail bad
# timeout of the follow itself (record stays accepted): FAIL, not PASS
a_scen pass 'S["rec"]=["activity-new1|2|accepted|||1866-gamedata.base|1"]'; o=$(a_run "$T/o10" "STUB_TEXT_SEQ=$OFFER_OK" RW_HUNT_WAIT=20); rc=$?
echo "$o" | grep -q "^HUNT26A-RUN 5090-i5 FAIL.*still 'accepted'" && [ $rc = 1 ] && chk follow-timeout-is-fail ok || chk follow-timeout-is-fail bad "rc=$rc $(echo "$o" | cut -c1-200)"

# 7. evidence files, originals, syntax
[ -s "$T/o1/follow.log" ] && [ -s "$T/o1/verdict.txt" ] && [ -e "$T/o1/native.txt" ] && chk evidence-files-incl-native-txt ok || chk evidence-files-incl-native-txt bad "$(ls "$T/o1" | tr '\n' ' ')"
grep -q 'participation|NATIVE_TRAVEL|ACTIVITY_END_DIAG' "$F" && chk native-lines-captured ok || chk native-lines-captured bad
if git -C "$ST_REAL" diff --quiet -- hunt26a-scene.sh reloadcheck_a.py reloaddefs_a.sh hunt26ascen.py hunt26a-scene-stub.sh hunt26a-inject-stub.sh 2>/dev/null; then chk originals-unmodified ok; else chk originals-unmodified bad; fi
bad=0; for f in hunt26a-run.sh hunt26a-follow-selftest.sh; do if [ "$f" = hunt26a-run.sh ]; then bash -n "$ST_REAL/hunt26a-run.sh.candidate" || bad=1; else bash -n "$ST_REAL/$f" || bad=1; fi; done
[ $bad = 0 ] && chk bash-syntax ok || chk bash-syntax bad
rm -rf "$T"
if [ $ok = $n ]; then echo "SELFTEST FIX26A ALL PASS $ok/$n"; exit 0; else echo "SELFTEST FIX26A ALL FAIL $ok/$n"; exit 1; fi
