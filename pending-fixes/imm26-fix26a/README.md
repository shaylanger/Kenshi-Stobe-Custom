# imm26-fix26a - row 26-a hunt route "arrival_not_verified" (arrival latch)

Patch: `fix26a-arrival.patch` (-p1, apply with `patch --binary -p1`; files are CRLF) against the NC28 tree `C:\KenshiTestRuns\imm26-nc28\src`
(ActivityNativeExecutor.cpp / .h only). Not built, not installed.

## What
- `Operation` gets `bool arrived` (ctor default false).
- `NativeExecutor::Poll` sets `op.arrived=true` at both `arrived_at_scoped_point` Succeeded returns (Travel, <= 8 u 3D).
- `NativeExecutor::Observe` (the `op.cleanupRequired` Travel loop): `facts.arrived = op.arrived || dist^2 <= 64`.

## Why
`ActivityGoals.cpp:292` (`pendingCommand_==Travel && !f.arrived` -> `Replan("arrival_not_verified")`) runs after `Poll` returned Succeeded and
`Release` succeeded. `f` comes from `Observe` (ActivityNativeExecutor.cpp:106-108), which only re-measures the live distance. `Poll` keeps returning
the stored Succeeded receipt while `Release` retries (`owned_order_cleanup_pending`); during those ticks Malzin walks on, the re-measure goes
> 8 u and the verified arrival is replanned/stopped (~6 s after the route arrived in runs 14f/14g). The latch keeps the verified fact.

## Risk / checks
- Stale latch for a new order/route: `Operation` objects are per request id (`operations_.count(r.id)` rejects reuse; each dispatch builds a fresh
  Operation with `arrived=false`). `Observe` reads `op.arrived` only for operations of this agreement with `cleanupRequired` true (finished/cleaned
  ones are skipped), and the latch is never cleared, so an older finished Travel op cannot leak into a later one.
- Save/load: `operations_` is runtime-only (not serialised); `Bind` clears it on world/worldId change. Nothing persists the latch. After a load the
  goal's pending request resolves via the existing paths and re-measures distance (unchanged behaviour).
- Scope note: only `Command==Travel` native ops; Attack/WorkResource/TakeItem untouched. Observe in a tick before Poll's first success still uses the
  live distance (same-frame position, unchanged). If a different cause (e.g. RouteTravel path, not native Travel) is behind 14g, this patch will not
  change it: check the next run for `arrival_not_verified` vs the new behaviour.
- The 8 u (64 sq) radius is unchanged.

## Offline proof
`bash pending-fixes/imm26-fix26a/offline-tests.sh` -> base FAIL (4), patched PASS, two mutations FAIL, then runs all `*_source_tests.py` on the
patched copy. Source test: `components/STOBE/tests/cpp/native_travel_arrival_latch_source_tests.py`.
Known pre-existing failures (unchanged): mine_functionality_produces_source_tests.py, playthrough_session_retry_source_tests.py.
