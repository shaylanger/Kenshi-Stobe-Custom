#!/usr/bin/env bash
# NC23 offline proof (WSL): bash offline-tests.sh [NC22 src dir]
#  1. NC22 src: attack_cleanup source test must FAIL.  2. nc23edit.py on a scratch copy: must PASS.  3. second run refuses.
#  4. sfP offline tests (NC22 base).  5. NC22 suite.   Prints RESULT nc23-offline PASS|FAIL.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc22/src}
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); N=$H/..; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
W=$HOME/nc23work; rm -rf $W; mkdir -p $W/a/src $W/b/src; ok=1
cp $S/ActivityNativeExecutor.cpp $W/a/src/; cp $S/ActivityNativeExecutor.cpp $W/b/src/
python3 $T/attack_cleanup_source_tests.py $W/a/src > $W/before.txt; rb=$?; echo "before: exit=$rb $(head -1 $W/before.txt)"; [ $rb -ne 0 ] || { echo "FAIL baseline must fail"; ok=0; }
python3 $H/nc23edit.py $W/b || ok=0
python3 $T/attack_cleanup_source_tests.py $W/b/src > $W/after.txt; ra=$?; echo "after: exit=$ra $(head -1 $W/after.txt)"; [ $ra -eq 0 ] || { cat $W/after.txt; ok=0; }
python3 $H/nc23edit.py $W/b >/dev/null 2>&1 && { echo "FAIL second run must refuse"; ok=0; }
bash $N/../imm26-sfP/offline-tests.sh $S | tail -3 | grep -q "RESULT sfP-offline PASS" || { echo "FAIL sfP offline"; ok=0; }
bash $N/NC22/offline-tests.sh $S > $W/nc22.txt 2>&1; grep -c "FAIL" $W/nc22.txt | sed 's/^/nc22 suite FAIL lines: /'
[ $ok = 1 ] && echo "RESULT nc23-offline PASS" || echo "RESULT nc23-offline FAIL"
[ $ok = 1 ]
