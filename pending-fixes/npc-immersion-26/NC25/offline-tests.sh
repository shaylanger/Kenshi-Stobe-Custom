#!/usr/bin/env bash
# NC25 offline proof (WSL): bash offline-tests.sh [NC24 tree dir]
#  1. NC24 src: both source tests must FAIL.  2. nc25a_edit.py + nc25b_edit.py on a scratch copy: both must PASS.
#  3. second run of each refuses.  4. NC24 offline suite.   Prints RESULT nc25-offline PASS|FAIL.
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); N=$H/..; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc24}; W=$HOME/nc25work; rm -rf $W; mkdir -p $W/a/src $W/b/src; ok=1
for f in main.cpp NativeTravelLifecycle.cpp NativeTravelLifecycle.h Utils.cpp; do cp $S/src/$f $W/a/src/; cp $S/src/$f $W/b/src/; done
for t in native_travel_terminal_push_source_tests follow_expiry_unloaded_source_tests; do
  python3 $T/$t.py $W/a/src > $W/before.txt; rb=$?; echo "before $t: exit=$rb $(head -1 $W/before.txt)"; [ $rb -ne 0 ] || { echo "FAIL baseline must fail"; ok=0; }
done
python3 $H/nc25a_edit.py $W/b || ok=0
python3 $H/nc25b_edit.py $W/b || ok=0
for t in native_travel_terminal_push_source_tests follow_expiry_unloaded_source_tests; do
  python3 $T/$t.py $W/b/src > $W/after.txt; ra=$?; echo "after $t: exit=$ra $(head -1 $W/after.txt)"; [ $ra -eq 0 ] || { cat $W/after.txt; ok=0; }
done
python3 $H/nc25a_edit.py $W/b >/dev/null 2>&1 && { echo "FAIL second A run must refuse"; ok=0; }
python3 $H/nc25b_edit.py $W/b >/dev/null 2>&1 && { echo "FAIL second B run must refuse"; ok=0; }
bash $N/NC24/offline-tests.sh | tail -1 | grep -q "nc24-offline PASS" || { echo "FAIL nc24 offline"; ok=0; }
[ $ok = 1 ] && echo "RESULT nc25-offline PASS" || echo "RESULT nc25-offline FAIL"
[ $ok = 1 ]
