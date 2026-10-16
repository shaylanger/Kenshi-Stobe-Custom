# imm26-fix26a2 - row 26-a: Hunt candidate scan right after the route arrival (grace retry + clause diag)

Patch: `fix26a2-postroute-scan.patch` (-p1, `patch --binary -p1`; files are CRLF) against the NC29 tree `C:\KenshiTestRuns\imm26-nc29\src`
(ActivityGoals.h / ActivityGoals.cpp / ActivityRuntimeBindings.cpp). NOT built, NOT installed. Compose as NC30 = NC29 + this patch
(same pattern as `pending-fixes/imm26-nc29/compose-native.sh`). The ActivityRuntimeBindings.cpp hunk is engine code and was not compiled
(no SDK here); it is diagnostics only, wrapped in try/catch, VS2010-safe constructs (no range-for).

## What
- `Goal` gets `postRouteScansLeft_` (ctor 0). Set to 16 where the route arrival is accepted (ActivityGoals.cpp:187-188), zeroed when a
  Suitable candidate is selected. In the Searching scan, an empty / unsuitable result while `postRouteScansLeft_ > 0` decrements it and
  returns (phase stays Searching, reason stays `arrived_rescanning_activity_purpose`) instead of `Stop(Failed)`. 16 scans at the 500 ms
  decision cadence (ActivityController.cpp:322) = about 8 s real at any game speed. Replan searches (target died/left, row 26-c) are NOT
  covered because the counter is already 0 then.
- `ACTIVITY_SCAN_DIAG id=.. scan=n/16 candidates=N [serial vis reach legal dead harv item]` on scans 1, 4, 8, 12, 16 (Goal side).
- `ACTIVITY_SCAN_DIAG id=.. stage=discover candRegistered agreementBound serialMatch resolved sameInstance sees onMesh rawPath d2 protected vis reach why=..`
  (Bindings side) whenever `Discover()` drops the agreed animal: names the failing clause, which `Discover` used to swallow (line 392) and
  `NativeHost::Candidates` dropped silently (the NC28 "Resolve-reason diag when Candidates() is empty" never made it into the source).

## Why
See the report (agents/out/imm26-inv26a): one scan, 0.75 s after the route order was released, converts an empty snapshot into a terminal
Failed; the same code selected the goat in run 26-a-op14g.

## Proof
`bash pending-fixes/imm26-fix26a2/offline-tests.sh` (WSL): base FAIL (46 checks), patched PASS, existing `activity_hunt_progress_tests` PASS,
two mutations FAIL, all `*_source_tests.py` PASS. Test: `components/STOBE/tests/cpp/activity_postroute_scan_tests.cpp` (new, uncommitted).
Live proof: rerun `hunt26a-run-dest.sh` on the NC30 lane: `ACTIVITY_SCAN_DIAG` lines show the clause; PASS = record accepted -> completed.

## If the live run still ends no_observed_suitable_reachable_target
Read the SCAN_DIAG lines: `sees=0` for all 16 scans with small d2 -> relax `canISeeThisGuy` for Hunt in `Refresh` to "sees OR within ~80 u"
(mirror of the sfP grant-import relaxation); `rawPath=-1` for all scans -> navmesh read lock/streaming, extend the window or retry the path;
`rawPath=0` -> the pinned goat is off the navmesh (recipe y/xz); `sameInstance=0` / `resolved=0` -> the teleported goat was re-instantiated
or unloaded (recipe: pin the agreed goat only after the destination zone is loaded); `protected=1:<reason>` -> ownership/wild verdict.
