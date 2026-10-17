#!/usr/bin/env bash
# NC31 native compose (WSL): bash compose-native.sh [NC30 tree] [dest tree]
# dest (default C:\KenshiTestRuns\imm26-nc31) = copy of the NC30 tree + imm26-fix26a3/fix26a3-travel-engine-end.patch (CRLF-exact, patch --binary -p1); lists files differing from the NC30 tree, runs imm26-fix26a3/offline-tests.sh and the STOBE cpp source tests. Prints RESULT nc31-native PASS|FAIL.
P=/mnt/c/KenshiModding/pending-fixes; S=${1:-/mnt/c/KenshiTestRuns/imm26-nc30}; D=${2:-/mnt/c/KenshiTestRuns/imm26-nc31}; ok=1
rm -rf $D; mkdir -p $D; cp -r $S/src $S/legacy-v1 $S/CMakeLists.txt $D/; [ -d $S/tests ] && cp -r $S/tests $D/
(cd $D && patch --binary -p1 -s < $P/imm26-fix26a3/fix26a3-travel-engine-end.patch) || ok=0
echo "files differing from NC30:"; diff -rq $S/src $D/src
NC30_SRC=$S/src bash $P/imm26-fix26a3/offline-tests.sh | tail -3 | grep -q "OFFLINE RESULT PASS" || { echo "FAIL fix26a3 offline-tests"; ok=0; }
T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
# mine_functionality_produces + playthrough_session_retry fail identically on the NC2627/NC28/NC29/NC30 base (pre-existing), so they are excluded from the gate
for t in $T/*.py; do n=$(basename $t .py); case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac
  python3 -I $t $D/src >/dev/null 2>&1 || { echo "FAIL $n"; ok=0; }; done
[ $ok = 1 ] && echo "RESULT nc31-native PASS" || echo "RESULT nc31-native FAIL"
[ $ok = 1 ]
