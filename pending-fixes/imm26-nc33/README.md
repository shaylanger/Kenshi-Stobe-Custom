# NC33 = NC32 + fix26apoll (row 26-a Hunt poll fix) - BUILT, NOT installed anywhere

## Contents
- Base: NC32 (DLL 9BD75D7D: NC31 + off-mesh reachability), source `C:\KenshiTestRuns\imm26-nc32` (never edited).
- Patch: `fix26apoll-poll-keep.patch` (`patch --binary -p1`, CRLF-exact; regenerate with `make-patch.sh`, apply logic in `make-nc33.py`). Two files: `ActivityNativeExecutor.cpp`, `ActivityRuntimeBindings.cpp`.
- Source tree: `C:\KenshiTestRuns\imm26-nc33` (`bash pending-fixes/imm26-nc33/compose-native.sh` in WSL rebuilds it from NC32 + patch into `imm26-nc33-c` and runs the gate).

## Why (operator report `C:\KenshiTestRuns\agents\out\imm26-5090-i5-op19\out-20261016-193034.md`, evidence `C:\KenshiTestRuns\imm26-5090-i5\rows\26-a-nc32`)
On NC32 the Travel arrived, the Attack was dispatched and ACTIVITY_OFFMESH_REACH fired reachable=1, yet Hunt failed one second later. Cause: `NativeExecutor::Poll` re-runs `policy_.Revalidate` every tick; one tick with reachable=0 returns Interrupted("current_native_path_unconfirmed") (`Revalidate`, ActivityRuntime.cpp), `Goal::Tick` then calls `Replan` (adds the goat to `attempted_`) and the next empty scan stops the Hunt.

## What changed
- `NativeExecutor::Poll`: when Revalidate fails with EXACTLY `current_native_path_unconfirmed`, the command is Attack or Travel, and our owned order is still the single live order (`CaptureOwned(actor,op,false)`), the operation stays Pending (`current` reset to the dispatch-time facts). Every other Revalidate failure (scope, authorization, hunt_source_mismatch, target_not_observed, ...), expiry, dead actor and identity change still Interrupt exactly as before. Logged as `ACTIVITY_POLL_DIAG id=.. cmd=.. revalidate_path_unconfirmed keepPending=1 n=..` (first occurrence, then every 10th). A lost/replaced order still ends via the existing `owned_order_changed_or_ended` path; the Goal no-progress timeout and agreement expiry still bound a stuck order.
- `ACTIVITY_SCAN_DIAG ... stage=discover` now also prints `targetOnMesh=<1|0|-1 unknown|-2 exception> dx= dz= dy=` (goat minus actor), to tell an off-mesh goat from an off-mesh actor.

## Build and proof
- `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc33 -Out C:\KenshiTestRuns\imm26-nc33-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH,ACTIVITY_SCAN_DIAG,ACTIVITY_POLL_DIAG,ACTIVITY_OFFMESH_REACH,revalidate_path_unconfirmed` -> `BUILD OK (objects=70)` first try; log `C:\KenshiTestRuns\imm26-nc33-build.out`.
- **DLL: `C:\KenshiModding\pending-fixes\imm26-nc33\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc33-b\out\Stobe.dll`), SHA256 `B3E02E06A3A7663C0C5C88DB3BD8FAE978622E77FCCA10C0E0C9169DAA7BA763` (prefix B3E02E06).** Previous: NC32 9BD75D7D3951B079F5901461CCA74E52B63BE935BB8FB590A1FA9D3E3E2E1FA1.
- Offline: `compose-native.sh` -> `RESULT nc33-native PASS`: new `tests/activity_poll_keep_source_tests.py` FAILS on NC32 (7 failures) and PASSES on NC33; every `components/STOBE/tests/cpp/*.py` plus the nc32 `activity_offmesh_reach_source_tests.py` pass on the composed src (`mine_functionality_produces_source_tests` and `playthrough_session_retry_source_tests` fail identically on earlier bases and are excluded). A mutation dropping the CaptureOwned gate fails the test.
- Not provable offline: DLL loads in game; the keep path firing live.

## Install (operator, ONE lane first; Kenshi of that lane closed; never install-dll.ps1)
Copy the DLL to BOTH `<lane install>\mods\Stobe\Stobe.dll` and `<lane install>\RE_Kenshi\mods\Stobe\Stobe.dll` of that one lane and verify SHA256 prefix B3E02E06 on both files, then relaunch.
- 5090 lanes: `D:\KenshiInst\<n>\mods\Stobe` and `...\RE_Kenshi\mods\Stobe`; then `lane-install.ps1 -Lane i4|i5 -FromLane i3` for the others.
- 4080: stage at `C:\KenshiTestRuns\staged\Stobe-NC33-B3E02E06.dll`; `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='B3E02E06A3A7663C0C5C88DB3BD8FAE978622E77FCCA10C0E0C9169DAA7BA763'`, `$OldSha` = the lane's current SHA, `-Action Plan|SelfTest|Apply -Instance <n>|Rollback`.

## Proof row 26-a (live, not run)
`testing/live-stobe-queue/imm26-assert/rowtools/hunt26a-run-dest.sh` on a kah-* copy (`GOAT_SETTLE=40`). Expect `ACTIVITY_OFFMESH_REACH ... reachable=1`, then (if a tick reads reachable=0) `ACTIVITY_POLL_DIAG ... revalidate_path_unconfirmed keepPending=1` instead of an Interrupted/Replan, and the Hunt continues to the kill/harvest. If SCAN_DIAG shows `targetOnMesh=0` the goat itself is off-mesh (follow-up needed).

## Note on components/STOBE
`components/STOBE/src` is behind the NC trees (71 files differ from NC32: earlier NC patches were never snapshotted there; same for /root/STOBE-src), so a partial copy back would mix bases. NC changes are kept as patches in `pending-fixes/` (same as NC32); no components/STOBE source was changed.
