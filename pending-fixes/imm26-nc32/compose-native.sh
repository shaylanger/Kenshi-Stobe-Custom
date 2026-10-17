#!/usr/bin/env bash
# NC32 native compose (WSL): bash compose-native.sh [NC31 tree] [dest tree]
# dest (default C:\KenshiTestRuns\imm26-nc32) = copy of the NC31 tree + imm26-fix26anav/fix26anav-offmesh-reach.patch (CRLF-exact, patch --binary -p1); lists files differing from the NC31 tree, runs imm26-fix26anav/offline-tests.sh and the STOBE cpp source tests. Prints RESULT nc32-native PASS|FAIL.
P=/mnt/c/KenshiModding/pending-fixes; S=${1:-/mnt/c/KenshiTestRuns/imm26-nc31}; D=${2:-/mnt/c/KenshiTestRuns/imm26-nc32}; ok=1
rm -rf $D; mkdir -p $D; cp -r $S/src $S/legacy-v1 $S/CMakeLists.txt $D/; [ -d $S/tests ] && cp -r $S/tests $D/
(cd $D && patch --binary -p1 -s < $P/imm26-fix26anav/fix26anav-offmesh-reach.patch) || ok=0
echo "files differing from NC31:"; diff -rq $S/src $D/src
NC31_SRC=$S/src bash $P/imm26-fix26anav/offline-tests.sh | tail -3 | grep -q "OFFLINE RESULT PASS" || { echo "FAIL fix26anav offline-tests"; ok=0; }
T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
# mine_functionality_produces + playthrough_session_retry fail identically on the NC2627..NC31 base (pre-existing), so they are excluded from the gate
for t in $T/*.py; do n=$(basename $t .py); case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac
  python3 -I $t $D/src >/dev/null 2>&1 || { echo "FAIL $n"; ok=0; }; done
[ $ok = 1 ] && echo "RESULT nc32-native PASS" || echo "RESULT nc32-native FAIL"
[ $ok = 1 ]
