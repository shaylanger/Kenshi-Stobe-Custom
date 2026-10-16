# NC18 = NC17 (6DDCA648..., which is NC16 + player-faction partner) + native-owned travel can actually finish (rows IMM-13-c, 13-c-neg, 19-d, 23-a)

Diagnosis (evidence only, no game run; see imm26-sfB handoff):
- Server reconciles a native travel receipt only inside a conversation prompt build (`lib/commitment_native_bridge.php` stobeCommitmentReconcileNative) with a fresh snapshot (<=120 s). Rowtools rd_13c/rd_13cneg poll the eventlog only and never trigger a turn, so the agreement stays ACCEPTED whatever native did (23-a worked because it did ctxpush + a "We're here" line). Operator side, no server change.
- Native: Tick arrival was 3D <= 8 u (`AtAgreedEndpoint`) against the server destination y, which can sit ~70 u below terrain; and the engine MOVE order ended ~150 u from the point (order point probably not connected on the navmesh) -> `native_order_ended_before_goal`. No native logging existed.

Change (only `NativeTravelLifecycle.cpp` + new pure header `NativeTravelRouteTarget.h`):
1. `Start` (route kind only, never follow): if `navmesh->pathExists(actor, requested)==0`, pick the nearest reachable walkable navmesh point (rings 25..140 u, drift <=160 u, <=28 probes, 150 ms budget; `-1` = unknown -> keep requested, never guess). Logs `NATIVE_TRAVEL_START ... target=requested_reachable|adjusted_to_reachable|no_reachable_substitute|...`.
2. `Tick`: arrival = planar radius 8 u (+|dy|<=40) via `RouteNear`; if the engine removed the MOVE order itself, completion also accepted within 16 u (`kEngineEndRadius`). Follow arrival still needs the leader near the goal.
3. Diagnostics: `NATIVE_TRAVEL` (every phase change), `NATIVE_TRAVEL_OBS` (every 2 s), `NATIVE_TRAVEL_ORDER_ENDED`, `NATIVE_TRAVEL_FINISH`.
4. Include guard: GameWorld/HavokCharacter/NavMesh/UtilityT included inside push/pop of the min/max macros (Ogre Aabb.inl breaks otherwise).

Files: `nc18edit.py <tree>` (asserts anchors; run on the NC17 tree), `nc18-over-nc17.patch`, `NativeTravelRouteTarget.h` (copy to src/), tests `native_travel_route_target_tests.cpp` (26 PASS), `components/STOBE/tests/cpp/native_travel_route_arrival_source_tests.py` (fails on NC17, passes on NC18), `offline-tests.sh` (WSL, all PASS incl. NC17/receipt regression).
Build: `RESULT NC-BUILD PASS objects=69`, work tree `C:\KenshiTestRuns\imm26-nc18`, DLL `NC18\Stobe.dll` SHA256 `D54D02689D81718E9561B52C18BEA02357A2B5DF3BAE566C1785F8B95B01F8F8` (gitignored). NOT installed on any lane. Carries NC17 too.
Reproduce: copy `imm26-nc17\{src,legacy-v1,tests}` to a new tree, copy `NativeTravelRouteTarget.h` into src, `python3 nc18edit.py <tree>`, build with `NC\build.ps1 -Out <tree>\build -SrcDir <tree>\src -LegacyDir <tree>\legacy-v1`.
Unproven: whether the order point was really off-navmesh (the new logs decide). Empty InstanceID uid => `participation_bound=0` (server hand_ fallback is a Shay decision).
