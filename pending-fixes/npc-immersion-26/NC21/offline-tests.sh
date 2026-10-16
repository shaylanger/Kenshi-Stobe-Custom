# Run in WSL: bash offline-tests.sh [tree]   (default NC21 tree). NC21 identity + sim tests, source test, NC20 suite, server hand_ proof check.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc21/src}; T=/mnt/c/KenshiModding/components/STOBE/tests/cpp; N=/mnt/c/KenshiModding/pending-fixes/npc-immersion-26; B=$HOME/nc21b; mkdir -p $B/inc/kenshi
cp $N/NC21/stubs/KenshiAiCompat.h $N/NC21/stubs/StobeText.h $B/inc/; cp $N/NC21/stubs/kenshi/*.h $B/inc/kenshi/
cp $S/ParticipationEvidence.h $S/ParticipationIdentity.h $B/inc/ 2>&1 | head -2
g++ -std=c++14 -I$B/inc $N/NC21/participation_identity_tests.cpp -o $B/pid 2>&1 | tail -5; $B/pid | tail -1; echo identity exit=${PIPESTATUS[0]}
g++ -std=c++14 -I$B/inc $N/NC21/participation_evidence_sim_tests.cpp -o $B/psim 2>&1 | tail -8; $B/psim | grep -v '^PASS'; echo evidence_sim exit=${PIPESTATUS[0]}
python3 $T/participation_hand_fallback_source_tests.py $S; echo src_hand_fallback_exit=$?
bash $N/NC20/offline-tests.sh $S
COMPOSE=/root/imm26/compose php $N/NC21/server_hand_proof_check.php | tail -1; echo server_hand_proof exit=${PIPESTATUS[0]}
g++ -std=c++14 -I$B/inc $N/NC21/participation_null_uid_repro.cpp -o $B/prepro 2>&1 | tail -5; $B/prepro; echo null_uid_repro exit=$?
