#!/usr/bin/env bash
# imm26-fixS1sleep offline proof (WSL): bash offline-tests.sh [NC2627-or-later tree root]
#  1. base: fight_audience_asleep_source_tests must FAIL.  2. make_edit.py applies -> test PASSES (and patch file == the edit result).
#  3. mutation: remove the filter call -> test FAILS.  4. second make_edit.py run refuses (exit 3).  Prints RESULT fixS1sleep-offline PASS|FAIL.
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc2627}; W=$HOME/fixS1work; rm -rf $W; mkdir -p $W/new/src $W/mut; ok=1
cp $S/src/Utils.cpp $S/src/main.cpp $W/new/src/; cp -r $W/new $W/orig
python3 -I $T/fight_audience_asleep_source_tests.py $W/orig/src >/dev/null && { echo "FAIL baseline must fail"; ok=0; } || echo "before: test fails on base (ok)"
python3 -I $H/make_edit.py $W/new || ok=0
python3 -I $T/fight_audience_asleep_source_tests.py $W/new/src || ok=0
if [ -f $H/imm26-fixS1sleep.patch ]; then
  mkdir -p $W/pt/src; cp $W/orig/src/* $W/pt/src/; (cd $W/pt && patch -p1 --binary -s < $H/imm26-fixS1sleep.patch) || ok=0
  for f in Utils.cpp main.cpp StobeAsleepState.h; do cmp -s $W/pt/src/$f $W/new/src/$f || { echo "FAIL patch result differs: $f"; ok=0; }; done
  echo "patch applies and equals the edit script result"
fi
cp -r $W/new/src $W/mut/; sed -i 's/if (StobeCharacterDownOrAsleep(other)) {/if (false) {/' $W/mut/src/Utils.cpp
python3 -I $T/fight_audience_asleep_source_tests.py $W/mut/src >/dev/null && { echo "FAIL mutant must fail"; ok=0; } || echo "mutation: test fails without the filter (ok)"
python3 -I $H/make_edit.py $W/new >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL second run must refuse"; ok=0; }
[ $ok = 1 ] && echo "RESULT fixS1sleep-offline PASS" || echo "RESULT fixS1sleep-offline FAIL"
[ $ok = 1 ]
