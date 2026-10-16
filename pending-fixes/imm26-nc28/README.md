# NC28 = NC2627 + fixS1sleep (fight audience drops asleep / KO / dead bystanders) - BUILT, NOT installed anywhere

## Contents
- Base: NC2627 (DLL AB082050: NC3..NC25 + NC26 durable item id + NC27 Hunt timeout / give-up speech), source `C:\KenshiTestRuns\imm26-nc2627`.
- Patch: `pending-fixes/imm26-fixS1sleep/imm26-fixS1sleep.patch` (commit ff114dae): new `src/StobeAsleepState.h`; `main.cpp` witness block uses the shared helper (`ResolveCurrentNpcTaskSafe` non-static); `Utils.cpp` `CollectEventPeopleFromAnchor` skips dead/KO/asleep characters (actor/target of the event are still appended first). No CMakeLists change.
- Source tree: `C:\KenshiTestRuns\imm26-nc28` (`bash pending-fixes/imm26-nc28/compose-native.sh` rebuilds it from NC2627 + patch in WSL and diffs it against that tree).
- Build (2026-10-16, 139 s): `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc28 -Out C:\KenshiTestRuns\imm26-nc28-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH` -> `BUILD OK (objects=70)`; log `C:\KenshiTestRuns\imm26-nc28-build.out`. No compile errors, no source edited beyond the patch.
- **DLL: `C:\KenshiModding\pending-fixes\imm26-nc28\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc28-b\out\Stobe.dll`), SHA256 `3FE805BF57507D55624C4B3E10402F1DDCCF8F871FF6AA5C1F7AA9D0ACE87675` (prefix 3FE805BF).** Previous: NC2627 AB082050CD3D83840AFA2824F7739ABAC6018564628ABF76A3F815D4DD8420DA; NC25 CD455D583F662347B8251424F1B97B03D5110DFDEA83C0320AB8411C49F103F3.

## Offline proof
- `fixS1sleep/offline-tests.sh` -> `RESULT fixS1sleep-offline PASS` (base fails, patch == script result, mutation fails, second run refuses).
- `bash pending-fixes/imm26-nc28/compose-native.sh` -> `RESULT nc28-native PASS` (tree identical to built tree + all 12 other STOBE cpp source tests in `components/STOBE/tests/cpp` pass on the composed src).
- Two tests fail IDENTICALLY on the NC2627 base and on NC28 (pre-existing, not caused by this patch): `mine_functionality_produces_source_tests.py` (NaturalOutput not found) and the untracked `playthrough_session_retry_source_tests.py` (errors=1). Excluded from the compose gate; someone should look at them separately.
- Not provable offline: the DLL loads and the filter behaves in game.

## Install (operator, ONE lane first; Kenshi of that lane closed)
`tools\automation\install-dll.ps1 Stobe` copies `C:\StobeBuild\out\Stobe.dll` to Shay's Steam install: do NOT use it for this candidate unless Shay orders the live install (then first run `build-stobe.ps1` in default mode on `C:\KenshiTestRuns\imm26-nc28`). For a test lane use the NC2627 path (see `pending-fixes/imm26-comp2627/README.md` "Install per lane"):
- 4080 lane i3 first: stage at `C:\KenshiTestRuns\staged\Stobe-NC28-3FE805BF.dll` on the 4080, copy `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='3FE805BF57507D55624C4B3E10402F1DDCCF8F871FF6AA5C1F7AA9D0ACE87675'`, `$OldSha` = the lane's current SHA (AB082050... if NC2627 is installed, else NC25's), `-CandidatePath` the staged file; `-Action Plan`, `SelfTest`, `Apply -Instance 3`, `Rollback` if needed.
- 5090 lanes (parked): `D:\KenshiInst\<n>\mods\Stobe\Stobe.dll`, then `lane-install.ps1 -Lane i4|i5 -FromLane i3`.

## Proof row (live, not run)
`bash testing/live-stobe-queue/imm26-assert/rowtools/unblockdefs_c_v4.sh 15-bx <lane> [--allow-retry "why"]` on a kah-* copy. PASS needs: sleeper/KO bystander S1 ABSENT from the fight event's `people` list, an awake in-range bystander (P1..P3) PRESENT, the event's own actors still present. Server side: nothing new (this patch is DLL only; the NC2627 server combination still applies for durable/hunt rows). Also check log still shows `DURABLE_ITEM: hooked|install`.
