#!/usr/bin/env bash
# NC33 native compose (WSL): bash compose-native.sh [NC32 tree] [dest tree]
# dest (default C:\KenshiTestRuns\imm26-nc33-c) = copy of the NC32 tree + fix26apoll-poll-keep.patch (patch --binary -p1, CRLF-exact). Gate: the new source test FAILS on NC32 and PASSES
# on NC33, then all components/STOBE/tests/cpp/*.py run on the composed src. Prints RESULT nc33-native PASS|FAIL.
H="$(cd "$(dirname "$0")" && pwd)"; S=${1:-/mnt/c/KenshiTestRuns/imm26-nc32}; D=${2:-/mnt/c/KenshiTestRuns/imm26-nc33-c}; ok=1
rm -rf $D; mkdir -p $D; cp -r $S/src $S/legacy-v1 $S/CMakeLists.txt $D/; [ -d $S/tests ] && cp -r $S/tests $D/
(cd $D && patch --binary -p1 -s < $H/fix26apoll-poll-keep.patch) || ok=0
echo "files differing from NC32:"; diff -rq $S/src $D/src
T=$H/tests/activity_poll_keep_source_tests.py
python3 -I $T $S/src >/dev/null && { echo "FAIL: new test PASSES on NC32"; ok=0; } || echo "new test FAILS on NC32 (expected)"
python3 -I $T $D/src || { echo "FAIL new test on NC33"; ok=0; }
O=/mnt/c/KenshiModding/components/STOBE/tests/cpp
for t in $O/*.py $H/../imm26-fix26anav/tests/activity_offmesh_reach_source_tests.py; do n=$(basename $t .py); case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac
  python3 -I $t $D/src >/dev/null 2>&1 || { echo "FAIL $n"; ok=0; }; done
[ $ok = 1 ] && echo "RESULT nc33-native PASS" || echo "RESULT nc33-native FAIL"
[ $ok = 1 ]
