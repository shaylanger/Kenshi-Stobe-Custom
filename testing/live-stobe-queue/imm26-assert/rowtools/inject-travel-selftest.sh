#!/usr/bin/env bash
# inject-travel-selftest.sh (imm26-sfTrav): OFFLINE selftest of the travel PROPOSE test seam + inject-travel.sh + inject-travel-deploy.sh. No lane, no game, no live tree.
# Needs WSL (php, the stobe_test database on the local postgres); re-executes itself through wsl.exe when started from Git Bash. ~1-2 min.
#   A  unpatched tree  -> the seam test must FAIL (it fails before the seam exists)
#   B  patched tree    -> apply.py (anchor, idempotent, php -l, wired right before the ordinary stobeTravelCapture), lane mode test PASS (armed -> real PROPOSED trip
#                         through stobeTravelCapture, one-shot, other NPC / expiry / ungrounded / accepted-trip filters, product refusal, the player's Yes accepts),
#                         notlane mode PASS (inert outside /tmp/stobe-*/site), existing travel regressions still pass
#   C  inject-travel.sh argument checks and marker format; the marker it writes is accepted by the server seam (armed mode)
#   D  lane-table mode (fake transport) and the deploy script body replayed against a local lane copy
# Env: SFTRAV_BASE (unpatched server tree, default /root/imm26/compose). Prints SELFTEST-RESULT PASS|FAIL <n checks>.
set -u
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  exec env MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash "/mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/inject-travel-selftest.sh" "$@"
fi
RT=/mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools
FIX=/mnt/c/KenshiModding/pending-fixes/imm26-sfTrav
BASE=${SFTRAV_BASE:-/root/imm26/compose}
W=/tmp/stobe-sftrav-selftest-$$
N=/tmp/sftrav-selftest-notlane-$$
fails=0; checks=0
ck() { checks=$((checks+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: ${3:-}"; fails=$((fails+1)); fi; }
SOCATS=""
cleanup() { [ -z "$SOCATS" ] || kill $SOCATS 2>/dev/null; rm -rf "$W" "$W-a" "$W-n" "$W-d" "$N"; }
trap cleanup EXIT
mk_lane() { # <lane root> <tree> : real copy of every code dir (data/ symlinked), private socket dir inside the lane root
  local r=$1 t=$2 e b
  rm -rf "$r"; mkdir -p "$r/site/log" "$r/socket"
  socat UNIX-LISTEN:"$r/socket/.s.PGSQL.5432",fork,mode=777 TCP:127.0.0.1:5432 &
  SOCATS="$SOCATS $!"; sleep 0.4
  for e in "$t"/* "$t"/.[!.]*; do [ -e "$e" ] || continue; b=$(basename "$e")
    case $b in data) ln -s "$e" "$r/site/$b" ;; log|.git) ;; *) cp -a "$e" "$r/site/$b" ;; esac; done
  cp "$FIX/imm26_sfTrav_inject_travel.php" "$r/site/tests/"
}
runphp() { # <lane root> <mode and args...>
  local r=$1; shift
  ( cd "$r/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$r/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_sfTrav_inject_travel.php "$@" 2>&1 )
}
[ -f "$BASE/processor/chat.php" ] || { echo "SELFTEST-RESULT FAIL base tree $BASE missing"; exit 1; }
python3 "$FIX/apply.py" "$BASE" --check >/dev/null 2>&1 && echo "NOTE base tree $BASE already has the seam: stage A (fails-before) is skipped" && HAVE_SEAM=1 || HAVE_SEAM=0

# A. fails before
if [ "$HAVE_SEAM" = 0 ]; then
  mk_lane "$W-a" "$BASE"
  out=$(runphp "$W-a" lane); rc=$?
  ck "A: unpatched tree: the seam test FAILS (exit != 0, B1 not satisfied)" $([ $rc -ne 0 ] && echo "$out" | grep -q '^FAIL B1' && echo 0 || echo 1) "rc=$rc $(echo "$out" | grep -m1 FAIL)"
  rm -rf "$W-a"
fi

# B. patched
mk_lane "$W" "$BASE"
out=$(python3 "$FIX/apply.py" "$W/site" 2>&1); ck "B0: apply.py installs the seam" $([ $? = 0 ] && echo "$out" | grep -q 'installed' && echo 0 || echo 1) "$out"
out=$(python3 "$FIX/apply.py" "$W/site" 2>&1); ck "B0b: apply.py is idempotent" $(echo "$out" | grep -q 'already has' && echo 0 || echo 1) "$out"
python3 "$FIX/apply.py" "$W/site" --check >/dev/null 2>&1; ck "B0c: apply.py --check sees the seam" $?
php -l "$W/site/processor/chat.php" >/dev/null && php -l "$W/site/lib/imm26_travel_test_inject.php" >/dev/null; ck "B0d: php -l chat.php + imm26_travel_test_inject.php" $?
python3 - "$W/site/processor/chat.php" <<'EOP'; ck "B0e: the seam call sits right before the ordinary stobeTravelCapture, inside the travelConsentTurn block, once" $?
import sys,re
s=open(sys.argv[1],encoding='utf-8').read().replace('\r\n','\n')
assert s.count('imm26-sfTrav TEST SEAM')==1 and s.count('stobeTravelTestInjectApply(')==1
i=s.index('imm26-sfTrav TEST SEAM'); j=s.index('stobeTravelCapture($imm26TravelRaw')
assert 0<j-i<900, (i,j)
k=s.rfind('if ($travelConsentTurn && !$regionPlanHandled', 0, i)
assert k>0 and i-k<1800, 'not inside the travel consent block'
assert 'imm26C2PlanNoticeFilter' in s[k:i], 'must run after the plan-notice filter'
EOP
out=$(runphp "$W" lane); rc=$?
echo "$out" | grep -E '^(FAIL|imm26_sfTrav)' ; ck "B: lane mode: all seam checks pass" $rc "rc=$rc $(echo "$out" | grep -m3 FAIL)"
for t in imm26_20a_deferred_confirm_regression imm26_batch4_travel_regression imm26_trip_resume_regression; do
  [ -f "$W/site/tests/$t.php" ] || continue
  out=$(cd "$W/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$W/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 180 php tests/$t.php 2>&1 | tail -2)
  ck "B2: existing $t still passes on the patched tree" $(echo "$out" | grep -q -E '[ ,=]0 failed|fail=0|failed: 0|ALL PASS|^OK' && ! echo "$out" | grep -q '^FAIL' && echo 0 || echo 1) "$out"
done
rm -rf "$N"; mkdir -p "$N"; cp -a "$W/site" "$N/site" 2>/dev/null; rm -rf "$N/site/log"; mkdir -p "$N/site/log"
out=$( cd "$N/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$W/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_sfTrav_inject_travel.php notlane 2>&1 ); rc=$?
echo "$out" | grep -E '^(FAIL|imm26_sfTrav)'; ck "B3: notlane mode: seam inert outside /tmp/stobe-*/site (marker present, no proposal)" $rc "$(echo "$out" | grep -m3 FAIL)"
rm -rf "$N"

# C. inject-travel.sh
IT="$RT/inject-travel.sh"
it() { IT_DIRECT=1 bash "$IT" "$@" 2>&1; }
out=$(it "$W" Cind Squin --row 20-d --ttl 120); ck "C1: arm by NPC name" $(echo "$out" | grep -q '^ARMED' && echo 0 || echo 1) "$out"
python3 - "$W/test-inject-travel.json" <<'EOP'; ck "C2: marker is valid JSON with schema/npc/destination/kind/leader/row/expiry" $?
import json,sys,time
d=json.load(open(sys.argv[1])); assert d['schema']=='STOBE_TEST_TRAVEL_INJECT_V1' and d['npc']=='Cind' and d['destination']=='Squin' and d['kind']=='same_route' and d['leader']=='npc' and d['row']=='20-d' and d['keep_text'] is False
assert 100<=d['expires_at']-int(time.time())<=125, d
EOP
out=$(it "$W" --status); ck "C3: --status shows the marker and the deployed seam" $(echo "$out" | grep -q 'MARKER armed' && echo "$out" | grep -q 'SEAM deployed' && echo 0 || echo 1) "$out"
out=$(it "$W" --disarm); ck "C4: --disarm removes it" $([ ! -e "$W/test-inject-travel.json" ] && echo 0 || echo 1) "$out"
for bad in "Cind Squin --ttl 5" "Cind Squin --ttl 99999" 'Cind"x Squin' "Cind Squin --nope" "Cind Squin --kind duel_meeting" "Cind Squin --leader boss" "Cind a;b" "Cind Squin --row x;y"; do
  out=$(it "$W" $bad); rc=$?; ck "C5: refused: $bad" $([ $rc = 2 ] && echo "$out" | grep -q REFUSED && echo 0 || echo 1) "rc=$rc $out"
done
for badroot in /var/www/html/StobeServer /tmp/other /tmp/stobe-x/../etc; do
  out=$(it "$badroot" Cind Squin); rc=$?; ck "C6: refused root $badroot" $([ $rc = 2 ] && echo 0 || echo 1) "rc=$rc $out"
done
out=$(IT_DIRECT=0 bash "$IT" /var/www/html/StobeServer Cind Squin 2>&1); rc=$?
ck "C7: lane-table mode refuses the live tree root" $([ $rc = 2 ] && echo "$out" | grep -q 'not a known lane' && echo 0 || echo 1) "rc=$rc $out"
mk_lane "$W-n" "$BASE"; out=$(IT_DIRECT=1 bash "$IT" "$W-n" Cind Squin 2>&1); rc=$?
ck "C8: lane without the seam: SEAM-MISSING, exit 4, no marker" $([ $rc = 4 ] && echo "$out" | grep -q SEAM-MISSING && [ ! -e "$W-n/test-inject-travel.json" ] && echo 0 || echo 1) "rc=$rc $out"
rm -rf "$W-n"
rm -f "$W"/test-inject-travel.fired-*.json
out=$(it "$W" UtTrav Squin --row sftrav); out2=$(runphp "$W" armed UtTrav)
echo "$out2" | grep -E '^(FAIL|imm26_sfTrav)'; ck "C9: script-armed marker -> real PROPOSED trip on the next turn, then the player's Yes ACCEPTs" $(echo "$out2" | grep -q ' 0 failed' && echo 0 || echo 1) "$out | $(echo "$out2" | grep -m3 FAIL)"
rm -f "$W"/test-inject-travel.fired-*.json
out=$(it "$W" any "" --row sftrav); python3 - "$W/test-inject-travel.json" <<'EOP'; ck "C10: empty destination + any NPC marker written" $?
import json,sys
d=json.load(open(sys.argv[1])); assert d['npc']=='any' and d['destination']==''
EOP
out=$(it "$W" Cind Squin --keep-text --leader player --kind guide); python3 - "$W/test-inject-travel.json" <<'EOP'; ck "C11: --keep-text/--leader/--kind land in the marker" $?
import json,sys
d=json.load(open(sys.argv[1])); assert d['keep_text'] is True and d['leader']=='player' and d['kind']=='guide'
EOP
rm -f "$W/test-inject-travel.json"

# D. lane-table mode (fake transport) and the deploy script (its body is replayed against a local fake lane)
export KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG=$W.fake.log; : > "$KAH_ROW_FAKE_LOG"
out=$(bash "$IT" 5090-i3 Cind Squin --row 20-d 2>&1); rc=$?
ck "D1: lane name arms through lane.sh (fake transport): body targets /tmp/stobe-imm26-5090" $([ $rc = 0 ] && grep -q '^R=/tmp/stobe-imm26-5090$' "$KAH_ROW_FAKE_LOG" && grep -q 'STOBE_TEST_TRAVEL_INJECT_V1' "$KAH_ROW_FAKE_LOG" && echo 0 || echo 1) "rc=$rc $out"
: > "$KAH_ROW_FAKE_LOG"; out=$(bash "$IT" /tmp/stobe-standalone4080-i4 --disarm 2>&1)
ck "D2: lane root form resolves to its lane (4080-i4)" $(grep -q '^### w 4080-i4' "$KAH_ROW_FAKE_LOG" && echo 0 || echo 1) "$out"
mk_lane "$W-d" "$BASE"; : > "$KAH_ROW_FAKE_LOG"
bash "$RT/inject-travel-deploy.sh" 5090-i3 >/dev/null 2>&1
sed -n '/^### w 5090-i3$/,$p' "$KAH_ROW_FAKE_LOG" | tail -n +2 | sed "s#/tmp/stobe-imm26-5090#$W-d#g" > "$W.deploy.body"
out=$(bash "$W.deploy.body" 2>&1); ck "D3: deploy body installs the seam on an unpatched lane copy" $(echo "$out" | grep -q '^DEPLOY 5090-i3 OK' && python3 "$FIX/apply.py" "$W-d/site" --check >/dev/null && [ -f "$W-d/bak-pre-sfTrav/chat.php" ] && echo 0 || echo 1) "$out"
out=$(bash "$W.deploy.body" 2>&1); ck "D4: deploy is idempotent" $(echo "$out" | grep -q '^DEPLOY 5090-i3 OK' && echo 0 || echo 1) "$out"
out=$(cd "$W-d/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$W/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_sfTrav_inject_travel.php notlane 2>&1 | tail -1)
ck "D5: deployed test file runs on the deployed copy" $(echo "$out" | grep -q ' 0 failed' && echo 0 || echo 1) "$out"
rm -rf "$W-d" "$W.fake.log" "$W.deploy.body"
unset KAH_ROW_FAKE KAH_ROW_FAKE_LOG

if [ $fails = 0 ]; then echo "SELFTEST-RESULT PASS $checks checks"; exit 0; else echo "SELFTEST-RESULT FAIL $fails of $checks checks failed"; exit 1; fi
