#!/bin/bash
# Proof run (WSL, root): bash /mnt/c/KenshiModding/pending-fixes/imm26-fix22b20d/run.sh [before|after|both]
# STAGED copies only (hard-link scratch of $BASE; patched files are replaced by real files). Never the live tree / live DB:
# tests run against the stobe_test database under the shared /tmp/stobe-tests.lock.
# BASE default = /root/imm26/fix22b20d-base (a copy of /root/imm26/comp2627-server = imm26 compose + huntA + durableA, no logs).
set -u
BASE=${BASE:-/root/imm26/fix22b20d-base}
HERE=/mnt/c/KenshiModding/pending-fixes/imm26-fix22b20d
OUT=${OUT:-/tmp/imm26-fix22b20d-run}
mode=${1:-both}
mk() {  # mk <name> [patch]
  local t=$OUT/$1; rm -rf "$t"; mkdir -p "$OUT"
  cp -al "$BASE" "$t"
  cp --remove-destination "$HERE/tests/imm26_fix22b20d_regression.php" "$t/tests/"
  if [ "${2:-}" = patch ]; then
    python3 "$HERE/apply.py" "$t" || { echo "APPLY FAILED"; exit 3; }
    for f in lib/imm26_plans.php lib/travel_companionship.php; do php -l "$t/$f" >/dev/null || { echo "LINT FAIL $f"; exit 4; }; done
  fi
}
runt() { (cd "$OUT/$1" && flock /tmp/stobe-tests.lock env STOBE_DB_NAME=stobe_test STOBE_NO_BACKGROUND_PROCESSOR=1 timeout 300 php -d display_errors=1 tests/imm26_fix22b20d_regression.php 2>&1 | tail -${2:-60}); }
rc=0
if [ "$mode" = before ] || [ "$mode" = both ]; then mk before; echo "=== BEFORE (unpatched; FAIL lines expected)"; runt before; fi
if [ "$mode" = after ] || [ "$mode" = both ]; then
  mk after patch; echo "=== AFTER (patched; must end 'N passed, 0 failed')"; res=$(runt after 80); echo "$res"
  echo "$res" | grep -q ' 0 failed' || rc=1
fi
[ "${KEEP:-0}" = 1 ] || rm -rf "$OUT"
exit $rc
