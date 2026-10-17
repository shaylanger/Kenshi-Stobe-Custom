# NC32 = NC31 + fix26anav off-mesh short-range reachability - BUILT, NOT installed anywhere

## Contents
- Base: NC31 (DLL 004DAF2A: NC30 + fix26a3 engine-ended MOVE arrival), source `C:\KenshiTestRuns\imm26-nc31` (never edited).
- Patch: `pending-fixes/imm26-fix26anav/fix26anav-offmesh-reach.patch` (`patch --binary -p1`, CRLF-exact; commits 6f9b1657 5c116e97 61b7e852): new `src/ActivityOffMeshReach.h` and an off-mesh short-range reachability rule in `ActivityRuntimeBindings.cpp` `Refresh()`; new diag string `ACTIVITY_OFFMESH_REACH`. Details: [`pending-fixes/imm26-fix26anav/README.md`](../imm26-fix26anav/README.md).
- Source tree: `C:\KenshiTestRuns\imm26-nc32` (`bash pending-fixes/imm26-nc32/compose-native.sh` in WSL rebuilds it from NC31 + patch; only `ActivityRuntimeBindings.cpp` differs, plus the new `ActivityOffMeshReach.h`).
- Build (2026-10-16): `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc32 -Out C:\KenshiTestRuns\imm26-nc32-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH,ACTIVITY_SCAN_DIAG,ACTIVITY_POLL_DIAG,ACTIVITY_OFFMESH_REACH` (NC31 guards + the new diag string; the patch adds no other) -> `BUILD OK (objects=70)` first try; log `C:\KenshiTestRuns\imm26-nc32-build.out`. No compile errors; the patch needed no change.
- **DLL: `C:\KenshiModding\pending-fixes\imm26-nc32\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc32-b\out\Stobe.dll`), SHA256 `9BD75D7D3951B079F5901461CCA74E52B63BE935BB8FB590A1FA9D3E3E2E1FA1` (prefix 9BD75D7D).** Previous: NC31 004DAF2A326C746FDDB4498FC121A4F1402EBD1425E9CC353173610EF8A46C79.

## Offline proof
- `bash pending-fixes/imm26-nc32/compose-native.sh` -> `RESULT nc32-native PASS`: patch applies clean, `imm26-fix26anav/offline-tests.sh` passes (base FAIL, patched PASS, mutations FAIL as expected), all `components/STOBE/tests/cpp/*.py` pass on the composed src. `mine_functionality_produces_source_tests.py` and `playthrough_session_retry_source_tests.py` fail identically on earlier bases (pre-existing) and are excluded.
- Not provable offline: DLL loads in game, and the off-mesh rule firing live.

## Install (operator, ONE lane first; Kenshi of that lane closed; never install-dll.ps1)
Copy the DLL to BOTH `<lane install>\mods\Stobe\Stobe.dll` and `<lane install>\RE_Kenshi\mods\Stobe\Stobe.dll` of that one lane, verify SHA256 prefix 9BD75D7D on both files, then relaunch.
- 4080 lane i3 first: stage at `C:\KenshiTestRuns\staged\Stobe-NC32-9BD75D7D.dll`; `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='9BD75D7D3951B079F5901461CCA74E52B63BE935BB8FB590A1FA9D3E3E2E1FA1'`, `$OldSha` = the lane's current SHA, `-CandidatePath` the staged file; `-Action Plan`, `SelfTest`, `Apply -Instance 3`, `Rollback` if needed.
- 5090 lanes (parked): `D:\KenshiInst\<n>\mods\Stobe` and `...\RE_Kenshi\mods\Stobe`, then `lane-install.ps1 -Lane i4|i5 -FromLane i3`.

## Proof row 26-a (live, not run)
Run `testing/live-stobe-queue/imm26-assert/rowtools/hunt26a-run-dest.sh` from Git Bash on a kah-* copy (`GOAT_SETTLE=40`). Expect after `measured_route_arrival` an `ACTIVITY_OFFMESH_REACH ... reachable=1` log line, no `no_observed_suitable_reachable_target`, then the Attack on the goat. If the line shows `targetOnMesh=0` the goat itself is off-mesh and a follow-up is needed (larger snap radius or a wild-animal-specific rule). Also check `DURABLE_ITEM: hooked|install` in the log.
