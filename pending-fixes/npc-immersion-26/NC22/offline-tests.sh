# Run in WSL: bash offline-tests.sh [tree]   (default NC22 tree). NC22 pure ownership test + source test + the NC21 suite.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc22/src}; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp; N=/mnt/c/KenshiModding/pending-fixes/npc-immersion-26; B=$HOME/nc22b; mkdir -p $B
g++ -std=c++14 -I$S $N/NC22/ownership_tests.cpp -o $B/own 2>&1 | tail -5; $B/own | tail -14; echo ownership_unit exit=${PIPESTATUS[0]}
python3 $T/activity_ownership_source_tests.py $S; echo src_ownership_exit=$?
bash $N/NC21/offline-tests.sh $S
