imm26-inv22b2 - row 22-b (4080-i3) "completed native receipt not ingested"
Root cause: the 22-b bored tick (rowtools/sfr22b_bored_g.sh, from unblockdefs_a.sh i4_bored) sends profile=Cind / people=Cind|serial (bare name);
the DLL sends "Cind [Hungry Bandit]". getNpcData is an exact-name lookup, so bored.php resolves the stale placeholder row "Cind"
(core_npc_master id 3213, metadata {"storage_id":"hand_2017700224"}, no travel_lifecycle); stobeCommitmentReconcileNative returns at
stobeCommitmentNativeSnapshot (commitment_native_bridge.php:7-8). No server or native change needed.
Files:
  apply_recipe.py                                  anchor-asserting patch for rowtools/sfr22b_bored_g.sh + sfr22b_v3_selftest.sh (+1 check)
  imm26_inv22b2_bored_profile_regression.php       16-check server characterization test on stobe_test (copy into <tree>/tests/)
Apply:  python3 apply_recipe.py C:/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools     (not while a list/batch uses sfrrun_v3.sh)
Proof:  wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding/testing/live-stobe-queue/imm26-assert -- bash rowtools/sfr22b_v3_selftest.sh
        before fix (new check, old recipe): FAIL bored-tick-uses-dll-full-name (profile=Cind), 20/21; after: 21/21 PASS.
Server test: flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test php tests/imm26_inv22b2_bored_profile_regression.php  -> 16 passed, 0 failed
Live proof: rerun 22-b (redeploy the sfTrav seam first), expect agreement COMPLETED and a situated_event arrival claimed by the bored tick.
