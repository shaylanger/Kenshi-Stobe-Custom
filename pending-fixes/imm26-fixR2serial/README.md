# imm26 fixR2serial: area-goal / region route used social ids as live serials (row 24-b)

Found live by 5090-i3op25 (`C:\KenshiTestRuns\agents\out\imm26-5090-i3op25\out-20261016-161342.md`): WP-R2 (commit 3f672904) was never reached.
Cind answered the fixed "I understand the area, but I can't verify our current trip or route yet." because `stobeAreaGoalReadCurrentTrip` compared the
scope `actor_id`/`speaker_id` (social DB ids, e.g. 5969 / 2) with the live serials (2529907200 / 971557632). Same assumption in `stobeAreaGoalResolve`, its call
site and `stobeTravelTakeRegionalConsent`. Fixture tests passed only because they set id == serial.

## Fix (see apply.py header)
Scope ids stay the `region_plan` key only. Trip key, trip read, resolve and consent marker bind the LIVE serials (`stobeAreaGoalLiveActorSerial` = same lookup as
`stobeTravelKey`). `stobeAreaGoalResolve(..., int $speakerSerial = 0)` gets the live speaker serial from the call site. Files: `lib/area_goal_integration.php`,
`lib/area_goal.php`, `lib/travel_companionship.php` (+ new test `tests/imm26_regionroute_serial_regression.php`).
Residual by design: nothing can verify offline that a social id belongs to a serial; the scope is built server-side from the same two names, and the serials are
checked against the names' live lookups (a missing/zero serial still fails the read).

## Apply (lane operator; 5090-i3 private site only, never the live tree). Requires WP-R2 already applied (it is, on /tmp/stobe-imm26-5090/site)
    SITE=/tmp/stobe-imm26-5090/site
    BAK=$SITE/../bak-pre-fixR2serial-$(date +%Y%m%d-%H%M%S); mkdir -p $BAK/lib $BAK/tests
    cp -a $SITE/lib/area_goal.php $SITE/lib/area_goal_integration.php $SITE/lib/travel_companionship.php $BAK/lib/
    python3 /mnt/c/KenshiModding/pending-fixes/imm26-fixR2serial/apply.py $SITE        # prints APPLIED x7 + WROTE test; rerun = ALREADY-APPLIED
    for f in lib/area_goal.php lib/area_goal_integration.php lib/travel_companionship.php tests/imm26_regionroute_serial_regression.php; do php -l $SITE/$f; done
    cd $SITE && STOBE_DB_NAME=stobe_test php tests/imm26_regionroute_serial_regression.php   # RESULT IMM26-REGIONROUTE-SERIAL PASS assertions=35
Rollback: copy the three files from `$BAK/lib/` back. PHP opcache serves the changed files after ~1 min. Regenerate codemaps afterwards (`codemap.sh <file>`).
Then re-run row 24-b on the lane (consider Vain with Cind) and expect the region-route offer reply instead of the "can't verify" text.

## Evidence (offline, staged copy of the lane site at /root/imm26/fixR2serial/stage)
- Before the fix the new test fails 14 assertions (section 2 reply = the exact live "can't verify" text). After: `RESULT IMM26-REGIONROUTE-SERIAL PASS assertions=35`.
- Existing suites unchanged and green: regionroute 62, wpE_region 60, batch4_region 6, sfL_region_waypoint 23, wpR1_area_goal_resume 10, trip_resume 63,
  wpL2 15, wpL 25, wpE_destination 5, wpE_activity_kinds 51, wpE_situated_events 35.
