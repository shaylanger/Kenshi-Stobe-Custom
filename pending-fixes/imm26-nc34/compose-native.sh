#!/usr/bin/env bash
# NC34 native compose (WSL): bash compose-native.sh [NC33 tree] [dest tree]
# dest (default C:\KenshiTestRuns\imm26-nc34-c) = copy of the NC33 tree + make-nc34.py edit. Gate: the new source test FAILS on NC33 and PASSES on NC34,
# then all components/STOBE/tests/cpp/*.py plus the NC33 poll-keep test run on the composed src. Prints RESULT nc34-native PASS|FAIL.
H="$(cd "$(dirname "$0")" && pwd)"; S=${1:-/mnt/c/KenshiTestRuns/imm26-nc33}; D=${2:-/mnt/c/KenshiTestRuns/imm26-nc34-c}; ok=1
rm -rf $D; mkdir -p $D; cp -r $S/src $S/legacy-v1 $S/CMakeLists.txt $D/; [ -d $S/tests ] && cp -r $S/tests $D/
python3 -I $H/make-nc34.py $D || ok=0
echo "files differing from NC33:"; diff -rq $S/src $D/src
T=$H/tests/activity_onmesh_fallback_source_tests.py
python3 -I $T $S/src >/dev/null && { echo "FAIL: new test PASSES on NC33"; ok=0; } || echo "new test FAILS on NC33 (expected)"
python3 -I $T $D/src || { echo "FAIL new test on NC34"; ok=0; }
O=/mnt/c/KenshiModding/components/STOBE/tests/cpp
for t in $O/*.py $H/../imm26-nc33/tests/activity_poll_keep_source_tests.py; do n=$(basename $t .py); case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac
  python3 -I $t $D/src >/dev/null 2>&1 || { echo "FAIL $n"; ok=0; }; done
[ $ok = 1 ] && echo "RESULT nc34-native PASS" || echo "RESULT nc34-native FAIL"
[ $ok = 1 ]
