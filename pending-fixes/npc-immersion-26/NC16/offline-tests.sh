# Run in WSL: bash offline-tests.sh   (compiles the existing offline native tests against the NC16 src)
S=/mnt/c/KenshiTestRuns/imm26-nc16/src; N=/mnt/c/KenshiModding/pending-fixes; B=$HOME/nc16b; mkdir -p $B
python3 /mnt/c/KenshiModding/components/STOBE/tests/cpp/activity_travel_world_source_tests.py $S; echo exit0=$?
for t in $N/npc-immersion-26/NC15/nc15_sidkey_tests.cpp $N/npc-immersion-26/N1/tests/tests-activity-adapter.cpp $N/activity-camp-native-adapter-20261014/ActivityCampNativeAdapterTests.cpp; do
  n=$(basename $t .cpp); g++ -std=c++14 -I$S -I$(dirname $t) $t -o $B/$n 2>&1 | tail -5; $B/$n | tail -2; echo "$n exit=${PIPESTATUS[0]}"
done
