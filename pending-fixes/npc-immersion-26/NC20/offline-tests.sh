# Run in WSL: bash offline-tests.sh [tree]   (default NC20 tree). NC20 source test + NC18 suite + candidate policy test.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc20/src}; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp; N=/mnt/c/KenshiModding/pending-fixes/npc-immersion-26; B=$HOME/nc20b; mkdir -p $B
python3 $T/clear_group_member_diag_source_tests.py $S; echo src_cgdiag_exit=$?
bash $N/NC18/offline-tests.sh $S
g++ -std=c++14 -I$S $T/activity_candidate_policy_tests.cpp -o $B/acp 2>&1 | tail -5; $B/acp | tail -1; echo candidate_policy exit=${PIPESTATUS[0]}
