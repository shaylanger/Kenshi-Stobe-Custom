#!/bin/bash
# Offline tests for imm26-sf26e (WSL). Usage: bash run-tests.sh [compose-root] [new-only]
# Installs the two new tests (assembled from the wpR1 helpers + body1.php) into <root>/tests, then runs them and the related suites.
here="$(cd "$(dirname "$0")" && pwd)"
root="${1:-/root/imm26/compose}"
cd "$root" || exit 1
{ cat <<'H'
<?php
// imm26-sf26e (row 26-e): after a save/load the native displayed-offer map is empty, so the player's Yes after a resumed PROPOSED activity carries no consent;
// the model answers ACCEPT (intent null) and accept() fails 'Explicit scoped consent was not verified' on every Yes. Fix: ACCEPT without consent on a proposed
// record re-displays the SAME offer (decision PROPOSE, offerDisplayed) so the native side binds it and the next Yes carries consent.
// Offline: real ActivityStore + adapter + stobeActivityChatFinish on TEMP tables in stobe_test. Run:
//   STOBE_DB_NAME=stobe_test php tests/imm26_sf26e_consent_redisplay_regression.php   (flock /tmp/stobe-tests.lock)
H
sed -n 6,89p tests/imm26_wpR1_activity_resume_regression.php | sed 's/4000.0, 20.0, 6000.0/4000.5, 20.5, 6000.5/g' # fractional coords: canonical() compares floats with !== against the DB value
cat "$here/body1.php"; } > tests/imm26_sf26e_consent_redisplay_regression.php
cp "$here/far_target_test.php" tests/imm26_inv26_far_target_regression.php
rc=0
suites="imm26_sf26e_consent_redisplay_regression imm26_inv26_far_target_regression"
[ "$2" = new-only ] || suites="$suites imm26_wpR1_activity_resume_regression imm26_wpR1_area_goal_resume_regression imm26_wpR2_resume_regression imm26_wpD_plans_regression imm26_wpE_activity_kinds_regression imm26_u4_ground_hunt_accept imm26_u4b_route_hunt_accept imm26_travel_target_out_of_people_regression imm26_wpL2_model_emitted_resume_regression imm26_wpL_landmark_resume_regression activity-camp-scope-regression $(ls tests | grep -i '^activity' | sed 's/\.php$//' | grep -v '^activity-camp-scope-regression$')"
for t in $suites; do
  [ -f tests/$t.php ] || { echo "== $t (missing)"; continue; }
  echo "== $t"
  STOBE_DB_NAME=stobe_test flock /tmp/stobe-tests.lock php tests/$t.php 2>&1 | tail -4
  [ "${PIPESTATUS[0]}" = 0 ] || { rc=1; echo "RC-FAIL $t"; }
done
exit $rc
