# NC29 = NC28 + fix26a arrival latch - BUILT, NOT installed anywhere

## Contents
- Base: NC28 (DLL 3FE805BF: NC2627 + fixS1sleep), source `C:\KenshiTestRuns\imm26-nc28` (never edited).
- Patch: `pending-fixes/imm26-fix26a/fix26a-arrival.patch` (commits 3c69cd34..8504e526; `patch --binary -p1`, CRLF-exact): `ActivityNativeExecutor.cpp/.h` only. `Operation::arrived` latch set in `Poll` on Travel Succeeded; `Observe` uses `facts.arrived = op.arrived || dist^2 <= 64`. Fixes row 26-a `arrival_not_verified`.
- Source tree: `C:\KenshiTestRuns\imm26-nc29` (`bash pending-fixes/imm26-nc29/compose-native.sh` rebuilds it from NC28 + patch in WSL; only the 2 patched files differ from NC28).
- Build (2026-10-16): `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc29 -Out C:\KenshiTestRuns\imm26-nc29-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH` (same guards as NC28) -> `BUILD OK (objects=70)`; log `C:\KenshiTestRuns\imm26-nc29-build.out`.
- **DLL: `C:\KenshiModding\pending-fixes\imm26-nc29\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc29-b\out\Stobe.dll`), SHA256 `80EF8D88D52864D1AC0AFCC748B142EBA754E52CAF14E3077DFF3C35F18F758E` (prefix 80EF8D88).** Previous: NC28 3FE805BF57507D55624C4B3E10402F1DDCCF8F871FF6AA5C1F7AA9D0ACE87675; NC2627 AB082050CD3D83840AFA2824F7739ABAC6018564628ABF76A3F815D4DD8420DA.

## Offline proof
- `bash pending-fixes/imm26-nc29/compose-native.sh` -> `RESULT nc29-native PASS` (patch applies clean; all STOBE cpp source tests in `components/STOBE/tests/cpp` pass on the composed src, incl. `native_travel_arrival_latch_source_tests.py`). `mine_functionality_produces_source_tests.py` and `playthrough_session_retry_source_tests.py` fail identically on the NC2627/NC28 base (pre-existing) and are excluded.
- `pending-fixes/imm26-fix26a/offline-tests.sh` covers base-fail / patch-pass / mutations.
- Not provable offline: DLL loads and the Hunt route verifies arrival in game.

## Route-path check (run 26-a-op14g)
The failing step is the native Travel leg, not RouteTravel: the RouteTravel leg completed (`NATIVE_TRAVEL ... phase=completed reason=measured_route_arrival_order_ended arrived=1`, 16:56:48.9), the goal re-scanned and issued a native `Travel` to the goat, and `ActivityGoals.cpp:292` (`pendingCommand_==Travel && !f.arrived`) raised `arrival_not_verified` ~6 s later (END_DIAG 16:56:54.7), so the patch applies.

## Install (operator, ONE lane first; Kenshi of that lane closed)
`tools\automation\install-dll.ps1 Stobe` copies `C:\StobeBuild\out\Stobe.dll` to Shay's Steam install: do NOT use it for this candidate unless Shay orders the live install (then first run `build-stobe.ps1` in default mode on `C:\KenshiTestRuns\imm26-nc29`). For a test lane:
- 4080 lane i3 first: stage at `C:\KenshiTestRuns\staged\Stobe-NC29-80EF8D88.dll` on the 4080, copy `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='80EF8D88D52864D1AC0AFCC748B142EBA754E52CAF14E3077DFF3C35F18F758E'`, `$OldSha` = the lane's current SHA (3FE805BF... if NC28 is installed, else AB082050...), `-CandidatePath` the staged file; `-Action Plan`, `SelfTest`, `Apply -Instance 3`, `Rollback` if needed.
- 5090 lanes (parked): `D:\KenshiInst\<n>\mods\Stobe\Stobe.dll`, then `lane-install.ps1 -Lane i4|i5 -FromLane i3`.

## Proof row (live, not run)
Re-run row 26-a (`hunt26a-run-dest.sh` recipe c6f45f42) on a kah-* copy. PASS needs the Hunt to pass the post-route Travel arrival check (no `arrival_not_verified`) and proceed to attack/harvest. Also check the log still shows `DURABLE_ITEM: hooked|install`.
