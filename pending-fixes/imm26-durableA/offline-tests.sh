#!/usr/bin/env bash
# imm26-durableA offline proof (WSL): bash offline-tests.sh [NC25 tree] [server scratch copy with option B]
#  native: nc26_edit.py on a scratch copy of NC25 applies, a second run refuses; server: baseline (B) FAILS the native test, apply.py makes it PASS, B test still PASS.
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); N=${1:-/mnt/c/KenshiTestRuns/imm26-nc25}; S=${2:-/root/imm26/dur-work}; W=$HOME/durAtmp; ok=1
rm -rf $W; mkdir -p $W/n $W/s; cp -r $N/src $N/CMakeLists.txt $W/n/
python3 $H/nc26_edit.py $W/n >/dev/null || { echo "FAIL native apply"; ok=0; }
python3 $H/nc26_edit.py $W/n >/dev/null 2>&1 && { echo "FAIL second native run must refuse"; ok=0; }
grep -q "Stobe::DurableItem::Install" $W/n/src/main.cpp || { echo "FAIL install call missing"; ok=0; }
[ $(grep -c "Stobe::DurableItem::Reset" $W/n/src/main.cpp) = 3 ] || { echo "FAIL reset count"; ok=0; }
python3 $H/mk_native_test.py >/dev/null; php -l $H/imm26_durable_item_id_native_regression.php >/dev/null || ok=0
rm -rf $W/s; cp -a $S $W/s; cd $W/s; cp $H/imm26_durable_item_id_native_regression.php tests/
run() { flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/$1.php 2>&1 | tail -1; }
run imm26_durable_item_id_native_regression | grep -q "^OK" && { echo "FAIL baseline must fail the native test"; ok=0; }
python3 $H/apply.py $W/s >/dev/null || ok=0
run imm26_durable_item_id_native_regression | grep -q "^OK" || { echo "FAIL native test after apply"; ok=0; }
run imm26_durable_item_id_regression | grep -q "^OK" || { echo "FAIL B test after apply"; ok=0; }
rm -rf $W
[ $ok = 1 ] && echo "RESULT durableA-offline PASS" || echo "RESULT durableA-offline FAIL"
