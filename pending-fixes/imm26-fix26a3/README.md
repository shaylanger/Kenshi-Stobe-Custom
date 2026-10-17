# imm26-fix26a3 - row 26-a: Hunt Travel step fails "owned_order_changed_or_ended" when the engine ends the MOVE order wider than 8 u

Patch: `fix26a3-travel-engine-end.patch` (-p1, `patch --binary -p1`; .cpp is CRLF, the new header LF) against the NC30 tree
`C:\KenshiTestRuns\imm26-nc30\src` (= NC29 + fix26a2). Adds `src/ActivityTravelArrival.h`, edits `ActivityNativeExecutor.cpp` only.
NOT built, NOT installed (no SDK in this session). Compose as NC31 = NC30 + this patch (same pattern as `pending-fixes/imm26-nc29/compose-native.sh`).

## What
- `ActivityTravel::EndedNearPoint(orderListEmpty, dx, dz)`: true only when the actor's order list is EMPTY and the planar (x,z) distance to the
  Travel point is <= 16 u (= `NativeTravelRouteTarget::kEngineEndRadius`, the radius the route lifecycle already uses for "engine removed the MOVE order").
- `NativeExecutor::Poll`: when `CaptureOwned` fails, a Travel op with that predicate true latches `op.arrived` and returns Succeeded
  `arrived_order_ended_near_point`; anything else (foreign/replaced order, actor farther than 16 u, Attack/WorkResource) still returns Interrupted
  `owned_order_changed_or_ended`. One `ACTIVITY_POLL_DIAG` line per operation records orders / planar / dy / nearEnd.
- `NativeExecutor::Observe`: `facts.arrived` also becomes true on the same predicate (`!ownedNow && EndedNearPoint(orderCount==0,dx,dz)`).
  Needed because `Goal::Tick` reads `f` (Observe) BEFORE `Poll` latches; without it the same tick would Replan `arrival_not_verified` (ActivityGoals.cpp:309).

## Why
See the investigation report (agents\out\imm26-inv26a2): in 26-a-op17 the Travel order to the agreed goat was removed by the engine within one 500 ms tick
while Malzin stood > 8 u (3D) from the goat; `Poll` only accepts <= 8 u 3D, so the ended order became Interrupted, `Replan` blacklisted the only agreed goat
(`attempted_`), the next scan found it unsuitable and the goal failed `owned_order_changed_or_ended; no_observed_suitable_reachable_target`.

## Proof
`wsl bash pending-fixes/imm26-fix26a3/offline-tests.sh`: base FAIL (header absent, 3 wiring checks), patched PASS (behaviour test + wiring test), four
mutations FAIL, all existing `*_source_tests.py` PASS (two pre-existing base failures excluded), Goal tests identical to base.
Live proof: rerun `hunt26a-run-dest.sh` on the NC31 lane; no `ACTIVITY_END_DIAG ... owned_order_changed_or_ended`; an `ACTIVITY_POLL_DIAG ... nearEnd=1`
line may appear; the Goal then issues the Attack on the goat.
