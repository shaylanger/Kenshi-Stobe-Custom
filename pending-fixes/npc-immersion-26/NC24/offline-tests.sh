#!/usr/bin/env bash
# NC24 offline proof (WSL): bash offline-tests.sh [NC23 tree dir]
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); N=$H/..; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc23}; W=$HOME/nc24work; rm -rf $W; mkdir -p $W/a/src $W/a/legacy-v1 $W/b/src $W/b/legacy-v1; ok=1
for d in a b; do cp $S/src/ActivityPolicySupport.cpp $W/$d/src/; cp $S/legacy-v1/ActivityPolicySupport.cpp $W/$d/legacy-v1/; done
python3 $T/mine_functionality_produces_source_tests.py $W/a > $W/before.txt; rb=$?; echo "before: exit=$rb $(head -1 $W/before.txt)"; [ $rb -ne 0 ] || { echo "FAIL baseline must fail"; ok=0; }
python3 $H/nc24edit.py $W/b || ok=0
python3 $T/mine_functionality_produces_source_tests.py $W/b > $W/after.txt; ra=$?; echo "after: exit=$ra $(head -1 $W/after.txt)"; [ $ra -eq 0 ] || { cat $W/after.txt; ok=0; }
python3 $H/nc24edit.py $W/b >/dev/null 2>&1 && { echo "FAIL second run must refuse"; ok=0; }
bash $N/NC23/offline-tests.sh | tail -1 | grep -q "nc23-offline PASS" || { echo "FAIL nc23 offline"; ok=0; }
[ $ok = 1 ] && echo "RESULT nc24-offline PASS" || echo "RESULT nc24-offline FAIL"
[ $ok = 1 ]
