# imm26-fix26anav - row 26-a (NC31): Hunt fails `current_native_path_unconfirmed; no_observed_suitable_reachable_target` right after a normal route arrival

Patch: `fix26anav-offmesh-reach.patch` (`patch --binary -p1`; .cpp is CRLF, the new header LF) against the NC31 tree `C:\KenshiTestRuns\imm26-nc31\src`
(DLL 004DAF2A). Adds `src/ActivityOffMeshReach.h`, edits `ActivityRuntimeBindings.cpp` only (`Refresh()`).
NOT built, NOT installed. Compose as NC32 = NC31 + this patch (pattern: `pending-fixes/imm26-nc29/compose-native.sh`).

## Root cause (verified in code + 5090-i5 op18 evidence)
- Evidence (`imm26-5090-i5/rows/26-a-nc31/r1`): route finished `measured_route_arrival planar=6.7 dy=2.4` (18:25:21.8, fix26a3 path not involved), then the
  post-route grace (`kPostRouteScanTries=16` scans, ~8-10 s) ended 18:25:31.5 with `ACTIVITY_SCAN_DIAG stage=discover sees=1 onMesh=0 rawPath=99 d2=961 reach=0
  why=current_native_path_unconfirmed`. Same 16 scans all failed, so the "off-mesh" state is stable while the actor stands, not a one-tick lag.
- `ConcreteRuntimeBindings::Refresh()` (ActivityRuntimeBindings.cpp:379-381) sets `t.reachable = ... avatar->isOnNavmesh() && pathExists(avatar,p)==1`.
  `Discover()` (:385-) drops the agreed source when `!agreed.facts.reachable`; the diag (:397-402) likewise only calls pathExists `if(onMesh && navmesh)`,
  hence `rawPath=99` (never evaluated). So pathExists was never asked: hypothesis CONFIRMED. The actor was on-mesh when the offer was made (the
  ProposalFacts gate at :679 requires it) and off-mesh 6.7 u from the mesh-projected route point after arrival (the route point comes from
  `getClosestPoint(...,60 u)`, so the engine's stop point is not guaranteed to be inside a mesh poly).
- Why not "probe from the nearest mesh point": `NavMesh::pathExists(HavokCharacter*, Vector3)` takes the AVATAR as its start, so an off-mesh avatar cannot
  be probed from a different start; only the target can be projected (`getClosestPoint`). Calling pathExists with an off-mesh avatar is not done anywhere
  in this tree (every use is behind `isOnNavmesh()`), so the patch does not start doing it blind.
- Why op17/NC30 passed: the first post-route scan happened while the actor still reported on-mesh.

## What
`Stobe::ActivityReach::OffMeshShortRange(huntKind,onMesh,visible,targetOnMesh,dx,dz,dy)` (pure): true only for a HUNT target that is visible, the actor
off-mesh, the TARGET within `getClosestPoint(p,20 u)` of walkable mesh, <= 35 u planar and |dy| <= 12 u. In `Refresh()` it is consulted only when the native
rule failed AND the actor is off-mesh (`!avatar->isOnNavmesh()`); an on-mesh actor with `pathExists != 1` stays unreachable exactly as before. One
`ACTIVITY_OFFMESH_REACH id= serial= targetOnMesh= dx= dz= dy= reachable=` line (2 s rate limit). The native Travel/Attack order then paths itself; an order
that cannot get there ends through the Goal no-progress timeout / `path_failed`, so a wrong "reachable" costs time, never a stuck goal.
Risk: a visible goat within 35 u across a cliff/fence while the actor is off-mesh now dispatches an order that fails later instead of failing the Hunt at once.

## Proof
`wsl bash pending-fixes/imm26-fix26anav/offline-tests.sh`: base FAIL (header absent, 3 wiring checks), patched PASS (behaviour + source test), three mutations
FAIL, all existing `*_source_tests.py` PASS (two pre-existing base failures excluded). Live proof: rerun `hunt26a-run-dest.sh` on the NC32 lane; expect an
`ACTIVITY_OFFMESH_REACH ... reachable=1` line after `measured_route_arrival`, no `no_observed_suitable_reachable_target`, then the Attack on the goat.
If the line shows `targetOnMesh=0` the goat itself is off-mesh: next step is a larger snap radius or a wild-animal-specific rule.
