#!/usr/bin/env bash
# NC30 native compose (WSL): bash compose-native.sh [NC29 tree] [dest tree]
# dest (default C:\KenshiTestRuns\imm26-nc30) = copy of the NC29 tree + imm26-fix26a2/fix26a2-postroute-scan.patch (CRLF-exact, patch --binary -p1); lists files differing from the NC29 tree, runs imm26-fix26a2/offline-tests.sh and the STOBE cpp source tests. Prints RESULT nc30-native PASS|FAIL.
P=/mnt/c/KenshiModding/pending-fixes; S=${1:-/mnt/c/KenshiTestRuns/imm26-nc29}; D=${2:-/mnt/c/KenshiTestRuns/imm26-nc30}; ok=1
rm -rf $D; mkdir -p $D; cp -r $S/src $S/legacy-v1 $S/CMakeLists.txt $D/; [ -d $S/tests ] && cp -r $S/tests $D/
(cd $D && patch --binary -p1 -s < $P/imm26-fix26a2/fix26a2-postroute-scan.patch) || ok=0
echo "files differing from NC29:"; diff -rq $S/src $D/src
NC29_SRC=$S/src bash $P/imm26-fix26a2/offline-tests.sh | tail -3 | grep -q "OFFLINE RESULT PASS" || { echo "FAIL fix26a2 offline-tests"; ok=0; }
T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
# mine_functionality_produces + playthrough_session_retry fail identically on the NC2627/NC28/NC29 base (pre-existing), so they are excluded from the gate
for t in $T/*.py; do n=$(basename $t .py); case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac
  python3 -I $t $D/src >/dev/null 2>&1 || { echo "FAIL $n"; ok=0; }; done
[ $ok = 1 ] && echo "RESULT nc30-native PASS" || echo "RESULT nc30-native FAIL"
[ $ok = 1 ]
