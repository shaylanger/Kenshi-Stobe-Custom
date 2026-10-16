#!/usr/bin/env bash
# NC2627 native compose (WSL): bash compose-native.sh <fresh NC25 tree> <dest tree>
# dest = copy of the NC25 tree + nc27a + nc27b + nc26 (order matters not: files are disjoint; this order is the one built).
# Prints RESULT comp2627-native PASS|FAIL (also diffs dest against the built tree C:\KenshiTestRuns\imm26-nc2627 when present).
P=/mnt/c/KenshiModding/pending-fixes; S=${1:-/mnt/c/KenshiTestRuns/imm26-nc25}; D=${2:-$HOME/nc2627work}; ok=1
rm -rf $D; mkdir -p $D; cp -r $S/src $S/legacy-v1 $S/CMakeLists.txt $D/ 2>/dev/null; [ -d $S/tests ] && cp -r $S/tests $D/
python3 -I $P/npc-immersion-26/NC27/nc27a_edit.py $D || ok=0
python3 -I $P/npc-immersion-26/NC27/nc27b_edit.py $D || ok=0
python3 -I $P/imm26-durableA/nc26_edit.py $D || ok=0
B=/mnt/c/KenshiTestRuns/imm26-nc2627
if [ -d $B ]; then diff -rq $B/src $D/src && diff -q $B/CMakeLists.txt $D/CMakeLists.txt && echo "composed tree identical to the built tree" || ok=0; fi
T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
for t in hunt_progress_source_tests native_travel_terminal_push_source_tests follow_expiry_unloaded_source_tests; do python3 -I $T/$t.py $D/src >/dev/null 2>&1 || { echo "FAIL $t"; ok=0; }; done
grep -c "Stobe::DurableItem::Reset" $D/src/main.cpp | grep -q '^3$' || { echo "FAIL durable reset count"; ok=0; }
[ $ok = 1 ] && echo "RESULT comp2627-native PASS" || echo "RESULT comp2627-native FAIL"
[ $ok = 1 ]
