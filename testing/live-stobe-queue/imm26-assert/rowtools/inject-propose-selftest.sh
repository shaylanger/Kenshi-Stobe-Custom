#!/usr/bin/env bash
# inject-propose-selftest.sh (imm26-sfO): OFFLINE selftest of the activity PROPOSE test seam + inject-propose.sh. No lane, no game, no live tree.
# Needs WSL (php, the stobe_test database on the local postgres); re-executes itself through wsl.exe when started from Git Bash. ~1 min.
#   A  unpatched tree  -> the seam test must FAIL (it fails before the seam exists)
#   B  patched tree    -> lane mode test PASS (armed Hunt/ClearGroup become real proposed records, one-shot, expiry, other actor, filters,
#                         gate, the player's "Yes" accepts), notlane mode PASS (inert outside /tmp/stobe-*/site)
#   C  inject-propose.sh argument checks and marker format; the marker it writes is accepted by the server seam (armed mode)
# Env: SFO_BASE (unpatched server tree, default /root/imm26/compose). Prints SELFTEST-RESULT PASS|FAIL <n checks>.
set -u
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  exec env MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash "/mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools/inject-propose-selftest.sh" "$@"
fi
RT=/mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools
FIX=/mnt/c/KenshiModding/pending-fixes/imm26-sfO
BASE=${SFO_BASE:-/root/imm26/compose}
W=/tmp/stobe-sfo-selftest-$$
N=/tmp/sfo-selftest-notlane-$$
fails=0; checks=0
ck() { checks=$((checks+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: ${3:-}"; fails=$((fails+1)); fi; }
SOCATS=""
cleanup() { [ -z "$SOCATS" ] || kill $SOCATS 2>/dev/null; rm -rf "$W" "$N" "$(dirname "$BASE")/test-inject-activity.json"; }
trap cleanup EXIT
mk_lane() { # <lane root> <tree> : real copy of every code dir (data/ symlinked), private socket dir inside the lane root
  local r=$1 t=$2 e b
  rm -rf "$r"; mkdir -p "$r/site/log" "$r/socket"
  # a lane-private unix socket (the gate requires the DB socket inside the lane root); forwards to the local test postgres (password auth over TCP)
  socat UNIX-LISTEN:"$r/socket/.s.PGSQL.5432",fork,mode=777 TCP:127.0.0.1:5432 &
  SOCATS="$SOCATS $!"; sleep 0.4
  for e in "$t"/* "$t"/.[!.]*; do [ -e "$e" ] || continue; b=$(basename "$e")
    case $b in data) ln -s "$e" "$r/site/$b" ;; log|.git) ;; *) cp -a "$e" "$r/site/$b" ;; esac; done   # data (no php) symlinked: a symlinked php dir would load a second copy of every lib
  cp "$FIX/imm26_sfO_inject_propose.php" "$r/site/tests/"
}
runphp() { # <lane root> <mode and args...>
  local r=$1; shift
  ( cd "$r/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$r/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_sfO_inject_propose.php "$@" 2>&1 )
}
[ -d "$BASE/lib/activity" ] || { echo "SELFTEST-RESULT FAIL base tree $BASE missing"; exit 1; }
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
php -l "$W/site/lib/activity/ActivityChat.php" >/dev/null && php -l "$W/site/lib/activity/ActivityTestInject.php" >/dev/null; ck "B0d: php -l ActivityChat.php + ActivityTestInject.php" $?
out=$(runphp "$W" lane); rc=$?
echo "$out" | grep -E '^(FAIL|imm26_sfO)' ; ck "B: lane mode: all seam checks pass" $rc "rc=$rc $(echo "$out" | grep -m3 FAIL)"
# existing activity regression must still pass on the patched lane tree (seam is inert without a marker)
out=$(cd "$W/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$W/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_wpE_activity_kinds_regression.php 2>&1 | tail -1)
ck "B2: existing activity-kinds regression still passes on the patched tree" $(echo "$out" | grep -q 'fail=0' && echo 0 || echo 1) "$out"

# notlane: same patched code under a path that is NOT /tmp/stobe-*/site
rm -rf "$N"; mkdir -p "$N"; cp -a "$W/site" "$N/site" 2>/dev/null; rm -rf "$N/site/log"; mkdir -p "$N/site/log"
out=$( cd "$N/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$W/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_sfO_inject_propose.php notlane 2>&1 ); rc=$?
echo "$out" | grep -E '^(FAIL|imm26_sfO)'; ck "B3: notlane mode: seam inert outside /tmp/stobe-*/site (marker present, no proposal)" $rc "$(echo "$out" | grep -m3 FAIL)"
rm -rf "$N"

# C. inject-propose.sh
IP="$RT/inject-propose.sh"
ip() { IP_DIRECT=1 bash "$IP" "$@" 2>&1; }
out=$(ip "$W" Cind Hunt --row 26-a --ttl 120); ck "C1: arm Hunt by NPC name" $(echo "$out" | grep -q '^ARMED' && echo 0 || echo 1) "$out"
python3 - "$W/test-inject-activity.json" <<'EOF'; ck "C2: marker is valid JSON with schema/kind/npc/row/expiry" $?
import json,sys,time
d=json.load(open(sys.argv[1])); assert d['schema']=='STOBE_TEST_ACTIVITY_INJECT_V1' and d['kind']=='Hunt' and d['npc']=='Cind' and d['actor']==0 and d['row']=='26-a'
assert 100<=d['expires_at']-int(time.time())<=125, d
EOF
out=$(ip "$W" --status); ck "C3: --status shows the marker and the deployed seam" $(echo "$out" | grep -q 'MARKER armed' && echo "$out" | grep -q 'SEAM deployed' && echo 0 || echo 1) "$out"
out=$(ip "$W" --disarm); ck "C4: --disarm removes it" $([ ! -e "$W/test-inject-activity.json" ] && echo 0 || echo 1) "$out"
for bad in "Cind Mine" "Cind Hunt --ttl 5" "Cind Hunt --ttl 99999" 'Cind"x Hunt' "Cind Hunt --nope" "Cind Hunt --quantity 0" "Cind Hunt a;b"; do
  out=$(ip "$W" $bad); rc=$?; ck "C5: refused: $bad" $([ $rc = 2 ] && echo "$out" | grep -q REFUSED && echo 0 || echo 1) "rc=$rc $out"
done
for badroot in /var/www/html/StobeServer /tmp/other /tmp/stobe-x/../etc; do
  out=$(ip "$badroot" Cind Hunt); rc=$?; ck "C6: refused root $badroot" $([ $rc = 2 ] && echo 0 || echo 1) "rc=$rc $out"
done
out=$(IP_DIRECT=0 bash "$IP" /var/www/html/StobeServer Cind Hunt 2>&1); rc=$?
ck "C7: lane-table mode refuses the live tree root" $([ $rc = 2 ] && echo "$out" | grep -q 'not a known lane' && echo 0 || echo 1) "rc=$rc $out"
# seam not deployed -> exit 4
mk_lane "$W-n" "$BASE"; out=$(IP_DIRECT=1 bash "$IP" "$W-n" Cind Hunt 2>&1); rc=$?
ck "C8: lane without the seam: SEAM-MISSING, exit 4, no marker" $([ $rc = 4 ] && echo "$out" | grep -q SEAM-MISSING && [ ! -e "$W-n/test-inject-activity.json" ] && echo 0 || echo 1) "rc=$rc $out"
rm -rf "$W-n"
# the marker written by the script is what the server seam accepts (serial and ClearGroup)
out=$(ip "$W" 7401 Hunt --row sfo); out2=$(runphp "$W" armed 7401 Hunt)
echo "$out2" | grep -E '^(FAIL|imm26_sfO)'; ck "C9: script-armed Hunt (serial) -> real proposed Hunt on the next turn" $(echo "$out2" | grep -q ' 0 failed' && echo 0 || echo 1) "$out | $(echo "$out2" | grep -m3 FAIL)"
rm -f "$W"/test-inject-activity.fired-*.json
out=$(ip "$W" any ClearGroup --row sfo); out2=$(runphp "$W" armed 7402 ClearGroup)
echo "$out2" | grep -E '^(FAIL|imm26_sfO)'; ck "C10: script-armed ClearGroup (any NPC) -> real proposed ClearGroup" $(echo "$out2" | grep -q ' 0 failed' && echo 0 || echo 1) "$(echo "$out2" | grep -m3 FAIL)"

# D. lane-table mode (fake transport) and the deploy script (its body is replayed against a local fake lane)
export KAH_ROW_FAKE=1 KAH_ROW_FAKE_LOG=$W.fake.log; : > "$KAH_ROW_FAKE_LOG"
out=$(bash "$IP" 5090-i3 Cind Hunt --row 26-a 2>&1); rc=$?
ck "D1: lane name arms through lane.sh (fake transport): body targets /tmp/stobe-imm26-5090" $([ $rc = 0 ] && grep -q '^R=/tmp/stobe-imm26-5090$' "$KAH_ROW_FAKE_LOG" && grep -q '"kind":"%s"' "$KAH_ROW_FAKE_LOG" && echo 0 || echo 1) "rc=$rc $out"
: > "$KAH_ROW_FAKE_LOG"; out=$(bash "$IP" /tmp/stobe-standalone4080-i4 --disarm 2>&1)
ck "D2: lane root form resolves to its lane (4080-i4)" $(grep -q '^### w 4080-i4' "$KAH_ROW_FAKE_LOG" && echo 0 || echo 1) "$out"
mk_lane "$W-d" "$BASE"; : > "$KAH_ROW_FAKE_LOG"
bash "$RT/inject-propose-deploy.sh" 5090-i3 >/dev/null 2>&1
sed -n '/^### w 5090-i3$/,$p' "$KAH_ROW_FAKE_LOG" | tail -n +2 | sed "s#/tmp/stobe-imm26-5090#$W-d#g" > "$W.deploy.body"
out=$(bash "$W.deploy.body" 2>&1); ck "D3: deploy body installs the seam on an unpatched lane copy" $(echo "$out" | grep -q '^DEPLOY 5090-i3 OK' && python3 "$FIX/apply.py" "$W-d/site" --check >/dev/null && [ -f "$W-d/bak-pre-sfO/ActivityChat.php" ] && echo 0 || echo 1) "$out"
out=$(bash "$W.deploy.body" 2>&1); ck "D4: deploy is idempotent" $(echo "$out" | grep -q '^DEPLOY 5090-i3 OK' && echo 0 || echo 1) "$out"
out=$(cd "$W-d/site" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_DB_HOST="$W/socket" STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 120 php tests/imm26_sfO_inject_propose.php notlane 2>&1 | tail -1)
ck "D5: deployed test file runs on the deployed copy" $(echo "$out" | grep -q ' 0 failed' && echo 0 || echo 1) "$out"
rm -rf "$W-d" "$W.fake.log" "$W.deploy.body"
unset KAH_ROW_FAKE KAH_ROW_FAKE_LOG

if [ $fails = 0 ]; then echo "SELFTEST-RESULT PASS $checks checks"; exit 0; else echo "SELFTEST-RESULT FAIL $fails of $checks checks failed"; exit 1; fi
