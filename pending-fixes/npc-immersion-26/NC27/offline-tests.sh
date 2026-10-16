#!/usr/bin/env bash
# NC27 offline proof (WSL): bash offline-tests.sh [NC25 or NC26 base tree dir]
#  1. base src: activity_hunt_progress_tests must NOT compile/pass, hunt_progress_source_tests must FAIL.
#  2. nc27a_edit.py + nc27b_edit.py on a scratch copy: all three tests PASS (hunt goal logic, ending-speech policy, source wiring).
#  3. mutation: delete the `lastProgress_ = now;` of the NC27A damage block -> the goal test must FAIL.
#  4. second run of each edit script refuses (exit 3).   Prints RESULT nc27-offline PASS|FAIL.
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc27-base}; W=$HOME/nc27work; rm -rf $W; mkdir -p $W; cp -r $S/src $W/base; mkdir -p $W/new; cp -r $S/src $W/new/src; ok=1
GF="-std=gnu++11 -include cmath -D_finite(x)=std::isfinite(x)"
build() { # <srcdir> <out>
  g++ -std=gnu++11 -include cmath '-D_finite(x)=std::isfinite(x)' -I$1 $T/activity_hunt_progress_tests.cpp $1/ActivityGoals.cpp -o $2 > $2.log 2>&1; }
build $W/base $W/hunt_base; rb=$?
if [ $rb -eq 0 ] && $W/hunt_base >/dev/null 2>&1; then echo "FAIL baseline goal test must not pass"; ok=0; else echo "before: goal test fails/does not compile on base (ok)"; fi
python3 -I $T/hunt_progress_source_tests.py $W/base >/dev/null && { echo "FAIL baseline source test must fail"; ok=0; } || echo "before: source test fails on base (ok)"
python3 -I $H/nc27a_edit.py $W/new || ok=0
python3 -I $H/nc27b_edit.py $W/new || ok=0
build $W/new/src $W/hunt_new || { echo "FAIL goal test build"; tail -5 $W/hunt_new.log; ok=0; }
$W/hunt_new | tail -2; [ ${PIPESTATUS[0]} -eq 0 ] || { echo "FAIL goal test"; ok=0; }
g++ -std=gnu++11 -I$W/new/src $T/activity_ending_speech_policy_tests.cpp -o $W/policy > $W/policy.log 2>&1 && $W/policy | tail -1; [ ${PIPESTATUS[0]} -eq 0 ] || { echo "FAIL policy test"; ok=0; }
python3 -I $T/hunt_progress_source_tests.py $W/new/src || ok=0
# mutation: the damage block no longer resets the timer
mkdir -p $W/mut; cp $W/new/src/*.h $W/new/src/ActivityGoals.cpp $W/mut/
python3 - $W/mut/ActivityGoals.cpp <<'PY' || ok=0
import sys,io
p=sys.argv[1]; s=io.open(p,encoding='utf-8',newline='').read()
a='f.target.health < lastHealth_ - 0.5f) {\r\n      lastProgress_ = now;' if '\r\n' in s else 'f.target.health < lastHealth_ - 0.5f) {\n      lastProgress_ = now;'
assert s.count(a)==1, 'mutation anchor'
io.open(p,'w',encoding='utf-8',newline='').write(s.replace(a,a.replace('lastProgress_ = now;','/* mutated */')))
PY
build $W/mut $W/hunt_mut && $W/hunt_mut >/dev/null 2>&1 && { echo "FAIL mutant must fail the goal test"; ok=0; } || echo "mutation: goal test fails without the reset (ok)"
python3 -I $H/nc27a_edit.py $W/new >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL second A run must refuse"; ok=0; }
python3 -I $H/nc27b_edit.py $W/new >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL second B run must refuse"; ok=0; }
[ $ok = 1 ] && echo "RESULT nc27-offline PASS" || echo "RESULT nc27-offline FAIL"
[ $ok = 1 ]
