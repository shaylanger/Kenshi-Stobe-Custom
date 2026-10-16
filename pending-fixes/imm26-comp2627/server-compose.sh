#!/usr/bin/env bash
# NC2627 server compose + offline tests (WSL, root): bash server-compose.sh [base tree = imm26 compose tree] [dest]
# default base /root/imm26/huntA-tree (= imm26 compose + huntA apply.py), dest /root/imm26/comp2627-server (scratch, NEVER the live tree).
# Applies imm26-durableA/apply.py --with-b (NC26 option A on top of option B) then imm26-huntA/apply.py (idempotent), runs the 7 tests.
B=${1:-/root/imm26/huntA-tree}; D=${2:-/root/imm26/comp2627-server}; H=/mnt/c/KenshiModding/pending-fixes; ok=1
rm -rf $D; cp -a $B $D
python3 $H/imm26-durableA/apply.py $D --with-b >/dev/null || ok=0
python3 $H/imm26-huntA/apply.py $D >/dev/null || ok=0
cp $H/imm26-durableA/imm26_durable_item_id_native_regression.php $H/imm26-huntA/tests/*.php $D/tests/
cd $D
for f in lib/activity/ActivityAgreementAdapter.php activity.php lib/situated_dialogue.php lib/social_event_contract.php; do php -l $f >/dev/null || { echo "FAIL php -l $f"; ok=0; }; done
for t in imm26_durable_item_id_native_regression imm26_durable_item_id_regression imm26_huntA_timeout_regression imm26_huntA_giveup_regression imm26_wpE_situated_events_regression imm26_wpE_activity_kinds_regression imm26_wpR1_activity_resume_regression; do
  r=$(flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 php tests/$t.php 2>&1 | tail -1); echo "$t: $r"
  echo "$r" | grep -q -E "fail=0| 0 failed|checks passed|PASS|^OK" || ok=0
done
[ $ok = 1 ] && echo "RESULT comp2627-server PASS" || echo "RESULT comp2627-server FAIL"
[ $ok = 1 ]
