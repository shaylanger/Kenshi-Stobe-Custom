# imm26 WP-R2: region route server (row 24-b)

Shay 2026-10-16: "consider <region>" -> grounded destination = native candidate id if in range, else the NEAREST KNOWN TOWN of the region
(rumoured/undiscovered towns allowed). The NPC OFFERS a first leg (PROPOSE only, no movement, server-written reply); the next explicit Yes is the
ordinary ACCEPT -> TRAVEL_LOCATION. The strict checker `c_24b` (rowcheck.py, commit 899d48ca) accepts the produced rows/reply (grounded_dest + reply names town).

## Apply (offline compose tree only, never the live tree)
    python3 pending-fixes/imm26-regionR2/apply.py <compose tree>      # anchor-asserting, idempotent, php -l is run by the tests

## Files
- `files/lib/region_route.php` (new): `stobeRegionRouteTownRegions()` = THE data seam; `stobeRegionRoutePick()` pure nearest pick; `stobeRegionRouteResolve()` entry point.
- `files/data/kenshi_town_regions.json` (new): 36 towns, each with a `source`. Vain = Hive Village NE/CE/CW/S (UWE 'Map of Vain') + W/NW/SW ('Map of Vain, Extended')
  + E (Shay decision 2026-10-16).
- `apply.py` patches `lib/area_goal.php` (town fallback in `stobeAreaGoalResolve`, new `$townRoute` arg), `lib/area_goal_integration.php` (`stobeAreaGoalOfferRoute`:
  PROPOSE-only, `regional_goal` upgrade, `route_ready` region_plan row, server reply), `lib/region_plan.php`, `lib/travel_companionship.php`
  (allowlist values + request-local pin `STOBE_TRAVEL_REGION_ROUTE_PIN` at the top of `stobeTravelResolvePlan` so an undiscovered town can be PROPOSEd).
- `files/tests/imm26_regionroute_regression.php`: 62 assertions (14 sections incl. nearest, current-town exclusion, native-first, blocked trip, Hive Village E).

## Tests
    php tests/imm26_regionroute_regression.php    # RESULT IMM26-REGIONROUTE PASS assertions=62
All existing suites stay green on the patched tree (sfL 23, wpE x4, wpR1 area_goal_resume 10, batch4 x4).

## Deploy
Compose -> lane deploy only: copy lib/area_goal.php, area_goal_integration.php, region_plan.php, region_route.php, travel_companionship.php,
data/kenshi_town_regions.json, tests/imm26_regionroute_regression.php into the lane's private backend site. Never the live tree. Regenerate the codemap
(`codemap.sh travel_companionship.php`; `--check` lists stale maps).

## Limits
- `route_ready` blocks a second consider while the PROPOSED offer is open (= blocked_by_existing_trip, by design).
- Stage `route_ready` is deliberately NOT in the referential stage lists.
- A native candidate proves a region only through the NPC's own region memory (`stobeDestinationKnownRegions`); the candidate normaliser drops `spatial.region_name`.
- A native `region` field on world_towns would replace `stobeRegionRouteTownRegions()` only.
