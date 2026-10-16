# Run in WSL: bash offline-tests.sh [tree]   (default NC18 tree). Route-target pure tests + source tests + NC17 regression.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc18/src}; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp; N=/mnt/c/KenshiModding/pending-fixes/npc-immersion-26; B=$HOME/nc18b; mkdir -p $B
g++ -std=c++14 -I$S $N/NC18/native_travel_route_target_tests.cpp -o $B/rt 2>&1 | tail -5; $B/rt | tail -1; echo route_target exit=${PIPESTATUS[0]}
python3 $T/native_travel_route_arrival_source_tests.py $S; echo src_route_arrival_exit=$?
python3 $T/activity_player_faction_partner_source_tests.py $S; echo src_partner_exit=$?
python3 $T/activity_travel_world_source_tests.py $S; echo src_world_exit=$?
g++ -std=c++14 -I$S $T/native_travel_receipt_tests.cpp -o $B/ntr 2>&1 | tail -5; $B/ntr >/dev/null; echo native_travel_receipt exit=$?
