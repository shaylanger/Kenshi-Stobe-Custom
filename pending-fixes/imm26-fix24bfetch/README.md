# imm26 fix24bfetch: stobeAreaGoalReadCurrentTrip treated fetchOne()===false (= no row) as a read failure (row 24-b)

After fixR2serial (d17dae65) the trip read passes its guards, but `PostgresDB::fetchOne()` (`pg_fetch_assoc`) returns **false for "no row"** as well as for a failed
query. `stobeAreaGoalReadCurrentTrip` counted false as failure, so every first region offer (no earlier travel_agreement row for the pair) answered
"I understand the area, but I can't verify our current trip or route yet." Offline fixture DBs returned null for no row, so no suite saw it.
Real-driver check (stobe_test, WSL): plain SELECT no row -> `bool(false)`; failed query -> `bool(false)`; scalar-subquery SELECT no row -> `['data'=>NULL]`.

Fix (apply.py, one edit in lib/area_goal_integration.php): `SELECT (SELECT data FROM eventlog WHERE type='travel_agreement' ... LIMIT 1) AS data` always returns one row
on success; NULL data (or a fixture null) = empty trip; false stays a read failure (fail closed); present rows keep the full validation.
Applies before or after fixR2serial (tested both orders, byte-identical result).

## Apply (lane operator; private lane site only)
    SITE=/tmp/stobe-imm26-5090/site
    BAK=$SITE/../bak-pre-fix24bfetch-$(date +%Y%m%d-%H%M%S); mkdir -p $BAK/lib; cp -a $SITE/lib/area_goal_integration.php $BAK/lib/
    python3 /mnt/c/KenshiModding/pending-fixes/imm26-fix24bfetch/apply.py $SITE     # APPLIED + WROTE test; rerun = ALREADY-APPLIED
    php -l $SITE/lib/area_goal_integration.php
    cd $SITE && STOBE_DB_NAME=stobe_test php tests/imm26_fix24bfetch_regression.php  # RESULT IMM26-FIX24BFETCH PASS assertions=17
Rollback: copy the file back from $BAK. opcache serves it after ~1 min; then `codemap.sh lib/area_goal_integration.php`. Re-run rows 24-b then 24-c.

## Evidence (staged copy /root/imm26/fix24bfetch/stage = i3 lane site after d17dae65)
- New test (driver-faithful fixture DB, production-shaped ids): before the fix 7 assertions fail (empty-trip cache seed, consider turn = can't-verify reply, no route_ready, no PROPOSED, no sticky-free
  recovery, future/other-pair rows, query shape); after: PASS 17. Real DB error (fetchOne false) still gives the exact fail-closed reply with no agreement row and zero actions; corrupt present rows still fail closed.
- Suites green after: regionroute 62, wpE_region 60, batch4 6, sfL 23, wpR1 area_goal 10, trip_resume 63, wpL2 15, wpL 25, wpE_destination 5, activity_kinds 51, situated_events 35, serial_regression 35.
- Other fetchOne users in the path (region_plan.php:142 uses `$row['data']??''`, tolerant) are unaffected. travel_companionship.php:267/319 have the same false-on-no-row convention but already treat false as empty.
