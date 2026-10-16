# NC30 = NC29 + fix26a2 post-route scan grace - BUILT, NOT installed anywhere

## Contents
- Base: NC29 (DLL 80EF8D88: NC28 + fix26a arrival latch), source `C:\KenshiTestRuns\imm26-nc29` (never edited).
- Patch: `pending-fixes/imm26-fix26a2/fix26a2-postroute-scan.patch` (`patch --binary -p1`, CRLF-exact): `ActivityGoals.h/.cpp` (post-route scan grace of 16 scans, `ACTIVITY_SCAN_DIAG` Goal-side lines) and `ActivityRuntimeBindings.cpp` (Discover clause diag). Details and the SCAN_DIAG -> next-step table: [`pending-fixes/imm26-fix26a2/README.md`](../imm26-fix26a2/README.md) (section "If the live run still ends no_observed_suitable_reachable_target").
- Source tree: `C:\KenshiTestRuns\imm26-nc30` (`bash pending-fixes/imm26-nc30/compose-native.sh` in WSL rebuilds it from NC29 + patch; only the 3 patched files differ from NC29).
- Build (2026-10-16): `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc30 -Out C:\KenshiTestRuns\imm26-nc30-b -Guard DURABLE_ITEM,travel_terminal,FOLLOW_DIAG,ACTIVITY_PROGRESS_DIAG,ACTIVITY_GIVEUP_SPEECH,ACTIVITY_SCAN_DIAG` (NC29 guards + the new diag string) -> `BUILD OK (objects=70)`; log `C:\KenshiTestRuns\imm26-nc30-build.out`. **No compile errors; no source edited beyond the patch (the never-compiled ActivityRuntimeBindings.cpp hunk compiled as is).**
- **DLL: `C:\KenshiModding\pending-fixes\imm26-nc30\Stobe.dll` (git-ignored; same bytes as `C:\KenshiTestRuns\imm26-nc30-b\out\Stobe.dll`, 4518912 bytes), SHA256 `1084879559D5DF6D2483FCC05C7A2C092118FC1182997D43618B1537784249E1` (prefix 10848795).** Previous: NC29 80EF8D88D52864D1AC0AFCC748B142EBA754E52CAF14E3077DFF3C35F18F758E.

## Offline proof
- `bash pending-fixes/imm26-nc30/compose-native.sh` -> `RESULT nc30-native PASS`: patch applies clean, `imm26-fix26a2/offline-tests.sh` passes (base FAIL, patched PASS, 2 mutations FAIL), all `components/STOBE/tests/cpp/*.py` pass on the composed src. `mine_functionality_produces_source_tests.py` and `playthrough_session_retry_source_tests.py` fail identically on the NC28/NC29 base (pre-existing) and are excluded.
- Not provable offline: DLL loads, and the Hunt candidate scan after the route arrival in game.

## Install (operator, ONE lane first; Kenshi of that lane closed; never install-dll.ps1)
Copy the DLL to BOTH `<lane install>\mods\Stobe\Stobe.dll` and `<lane install>\RE_Kenshi\mods\Stobe\Stobe.dll` of that one lane, verify SHA256 prefix 10848795 on both files, then relaunch.
- 4080 lane i3 first: stage at `C:\KenshiTestRuns\staged\Stobe-NC30-10848795.dll`; `pending-fixes\4080-nc-install-20261015\install-stobe-4080-nc.ps1` with `$NewSha='1084879559D5DF6D2483FCC05C7A2C092118FC1182997D43618B1537784249E1'`, `$OldSha` = the lane's current SHA (80EF8D88... if NC29 is installed), `-CandidatePath` the staged file; `-Action Plan`, `SelfTest`, `Apply -Instance 3`, `Rollback` if needed (check the script copies to both folders).
- 5090 lanes (parked): `D:\KenshiInst\<n>\mods\Stobe` and `...\RE_Kenshi\mods\Stobe`, then `lane-install.ps1 -Lane i4|i5 -FromLane i3`.

## Proof row (live, not run)
Re-run row 26-a (`hunt26a-run-dest.sh`) on a kah-* copy. PASS = the Hunt accepts the record after the route arrival (no `no_observed_suitable_reachable_target`). On FAIL read the `ACTIVITY_SCAN_DIAG` lines and follow the table in the fix26a2 README. Also check `DURABLE_ITEM: hooked|install` in the log.
