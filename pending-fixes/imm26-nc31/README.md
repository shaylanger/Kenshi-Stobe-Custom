# NC31 = NC30 + fix26a3 engine-ended MOVE arrival - BUILT, NOT installed anywhere

## Contents
- Base: NC30 (DLL 10848795: NC29 + fix26a2 post-route scan grace), source `C:\KenshiTestRuns\imm26-nc30` (never edited).
- Patch: `pending-fixes/imm26-fix26a3/fix26a3-travel-engine-end.patch` (`patch --binary -p1`, CRLF-exact; commit 97f93d46): new `ActivityTravelArrival.h` (`EndedNearPoint`, planar distance <= 16 u so an engine-ended MOVE counts as arrived) and `ActivityNativeExecutor.cpp` (uses it; new `ACTIVITY_POLL_DIAG ... owned_order_gone` line). Details: [`pending-fixes/imm26-fix26a3/README.md`](../imm26-fix26a3/README.md).
- Source tree: `C:\KenshiTestRuns\imm26-nc31` (`bash pending-fixes/imm26-nc31/compose-native.sh` in WSL rebuilds it from NC30 + patch; only `ActivityNativeExecutor.cpp` differs, plus the new `ActivityTravelArrival.h`).
- Build (2026-10-16): `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc31 -Out C:\KenshiTestRuns\imm26-nc31-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH,ACTIVITY_SCAN_DIAG,ACTIVITY_POLL_DIAG` (NC30 guards + the new diag string) -> `BUILD OK (objects=70)`; log `C:\KenshiTestRuns\imm26-nc31-build.out`. No compile errors; no source edited beyond the patch.
- **DLL: `C:\KenshiModding\pending-fixes\imm26-nc31\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc31-b\out\Stobe.dll`, 4520448 bytes), SHA256 `004DAF2A326C746FDDB4498FC121A4F1402EBD1425E9CC353173610EF8A46C79` (prefix 004DAF2A).** Previous: NC30 1084879559D5DF6D2483FCC05C7A2C092118FC1182997D43618B1537784249E1.

## Offline proof
- `bash pending-fixes/imm26-nc31/compose-native.sh` -> `RESULT nc31-native PASS`: patch applies clean, `imm26-fix26a3/offline-tests.sh` passes (base FAIL, patched PASS, mutations abort as expected), all `components/STOBE/tests/cpp/*.py` pass on the composed src. `mine_functionality_produces_source_tests.py` and `playthrough_session_retry_source_tests.py` fail identically on the earlier bases (pre-existing) and are excluded.
- Not provable offline: DLL loads, and an engine-ended MOVE near the point counting as arrived in game.

## Install (operator, ONE lane first; Kenshi of that lane closed; never install-dll.ps1)
Copy the DLL to BOTH `<lane install>\mods\Stobe\Stobe.dll` and `<lane install>\RE_Kenshi\mods\Stobe\Stobe.dll` of that one lane, verify SHA256 prefix 004DAF2A on both files, then relaunch.
- 4080 lane i3 first: stage at `C:\KenshiTestRuns\staged\Stobe-NC31-004DAF2A.dll`; `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='004DAF2A326C746FDDB4498FC121A4F1402EBD1425E9CC353173610EF8A46C79'`, `$OldSha` = the lane's current SHA (10848795... if NC30 is installed), `-CandidatePath` the staged file; `-Action Plan`, `SelfTest`, `Apply -Instance 3`, `Rollback` if needed.
- 5090 lanes (parked): `D:\KenshiInst\<n>\mods\Stobe` and `...\RE_Kenshi\mods\Stobe`, then `lane-install.ps1 -Lane i4|i5 -FromLane i3`.

## Proof row (live, not run)
Re-run row 26-a with `testing/live-stobe-queue/imm26-assert/rowtools/hunt26a-run-dest.sh` and `GOAT_SETTLE=40` on a kah-* copy. PASS = the trip/Hunt counts the engine-ended MOVE as arrived (no travel stall at the destination). On FAIL read the `ACTIVITY_POLL_DIAG ... owned_order_gone` line (orders, distance) and `ACTIVITY_SCAN_DIAG`. Also check `DURABLE_ITEM: hooked|install` in the log.
