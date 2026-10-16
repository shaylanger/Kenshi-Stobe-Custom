# Run in WSL: bash offline-tests.sh [tree]   (default NC17 tree). Compiles the policy test and runs the source tests.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc17/src}; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp; N=/mnt/c/KenshiModding/pending-fixes; B=$HOME/nc17b; mkdir -p $B
python3 $T/activity_player_faction_partner_source_tests.py $S; echo src_partner_exit=$?
python3 $T/activity_travel_world_source_tests.py $S; echo src_world_exit=$?
g++ -std=c++14 -I$S $T/native_travel_receipt_tests.cpp -o $B/ntr 2>&1 | tail -5; $B/ntr | grep -c '^PASS' ; $B/ntr >/dev/null; echo native_travel_receipt exit=$?
for t in $N/npc-immersion-26/NC15/nc15_sidkey_tests.cpp $N/npc-immersion-26/N1/tests/tests-activity-adapter.cpp $N/activity-camp-native-adapter-20261014/ActivityCampNativeAdapterTests.cpp; do
  n=$(basename $t .cpp); g++ -std=c++14 -I$S -I$(dirname $t) $t -o $B/$n 2>&1 | tail -5; $B/$n | tail -1; echo "$n exit=${PIPESTATUS[0]}"
done
