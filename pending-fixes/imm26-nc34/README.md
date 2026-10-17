# NC34 = NC33 + fix26aonmesh (row 26-a, on-mesh actor with unconfirmed path) - BUILT, NOT installed anywhere

- Base: NC33 (DLL B3E02E06), source `C:\KenshiTestRuns\imm26-nc33` (never edited). Tree: `C:\KenshiTestRuns\imm26-nc34` (`compose-native.sh` in WSL rebuilds it into `imm26-nc34-c` and runs the gate).
- Patch: `fix26aonmesh.patch` (one file, `ActivityRuntimeBindings.cpp`, CRLF-exact; apply logic in `make-nc34.py`).

## Why
After the goat was KO'd 9 u away, `Goal::Issue(TakeItem)` was rejected with `current_native_path_unconfirmed` (SCAN_DIAG onMesh=1 rawPath=0 reach=0). `ConcreteRuntimeBindings::Refresh` ran the bounded fallback `ActivityReach::OffMeshShortRange` only when `!avatar->isOnNavmesh()`, so an ON-mesh actor whose `pathExists` said no (rawPath=0) never got it.

## What changed
Refresh: dropped `&& !avatar->isOnNavmesh()` from the fallback block condition. Kept: block only runs when the native rule left `t.reachable=false`; Hunt only; visible; target on/near mesh (`getClosestPoint` r=20); planar <= 35 u and |dy| <= 12 u (OffMeshShortRange, header unchanged). `ACTIVITY_OFFMESH_REACH` now also prints `actorOnMesh=<1|0>`. No broadening to far targets.

## Proof
- `tests/activity_onmesh_fallback_source_tests.py` (supersedes the NC31 `activity_offmesh_reach_source_tests.py`, which required the off-mesh-only condition): FAILS on NC33 (2 failures), PASSES on NC34. `compose-native.sh` -> `RESULT nc34-native PASS` (also all components/STOBE/tests/cpp/*.py + NC33 poll-keep test; mine_functionality/playthrough_session_retry excluded as before).
- `build-stobe.ps1 -Root C:\KenshiTestRuns\imm26-nc34 -Out C:\KenshiTestRuns\imm26-nc34-b -Guard ...,actorOnMesh` -> `BUILD OK (objects=70)`, log `C:\KenshiTestRuns\imm26-nc34-build.out`.
- **DLL `C:\KenshiModding\pending-fixes\imm26-nc34\Stobe.dll` (git-ignored; = `C:\KenshiTestRuns\imm26-nc34-b\out\Stobe.dll`), SHA256 `6E14E68690C9A992943DAC757C1649744ABB52F656AF08C7E180BBF0A5401AE9` (prefix 6E14E686).** Previous NC33 B3E02E06.

## components/STOBE
Not changed: it (and /root/STOBE-src) is behind the NC trees (earlier NC patches were never snapshotted), so a partial copy would mix bases; NC changes live as patches here (same as NC32/NC33).
