#!/bin/bash
# imm26-fix26a2 offline proof (WSL). Usage: bash offline-tests.sh   (needs g++, python3, patch)
# Base (NC29 tree) must FAIL the new behaviour test; patched must PASS it plus the existing Hunt goal test and all *_source_tests.py.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="${NC29_SRC:-/mnt/c/KenshiTestRuns/imm26-nc29/src}"
T="$REPO/components/STOBE/tests/cpp"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/base" "$W/p/src"; cp -r "$SRC/." "$W/base/"; cp -r "$SRC/." "$W/p/src/"
(cd "$W/p" && patch --binary -p1 -s -i "$HERE/fix26a2-postroute-scan.patch") || { echo "PATCH FAILED"; exit 1; }
rc=0
bld() { g++ -std=gnu++11 -include cmath '-D_finite(x)=std::isfinite(x)' -I"$1" "$2" "$1/ActivityGoals.cpp" -o "$3" 2>&1 | head -20; }
echo "== base must FAIL activity_postroute_scan_tests"
bld "$W/base" "$T/activity_postroute_scan_tests.cpp" "$W/t_base"; "$W/t_base" | tail -1; "$W/t_base" >/dev/null && { echo "UNEXPECTED PASS on base"; rc=1; }
echo "== patched must PASS activity_postroute_scan_tests"
bld "$W/p/src" "$T/activity_postroute_scan_tests.cpp" "$W/t_p"; "$W/t_p" | tail -1; "$W/t_p" >/dev/null || rc=1
echo "== patched must PASS activity_hunt_progress_tests (existing Hunt timeout/progress behaviour)"
bld "$W/p/src" "$T/activity_hunt_progress_tests.cpp" "$W/t_hp"; "$W/t_hp" | tail -1; "$W/t_hp" >/dev/null || rc=1
echo "== mutation (drop the grace: scans left set to 0 at arrival) must FAIL"
cp -r "$W/p/src" "$W/m1"; sed -i 's/postRouteScansLeft_=kPostRouteScanTries;/postRouteScansLeft_=0;/' "$W/m1/ActivityGoals.cpp"
bld "$W/m1" "$T/activity_postroute_scan_tests.cpp" "$W/t_m1"; "$W/t_m1" >/dev/null && { echo "MUTATION 1 SURVIVED"; rc=1; }
echo "== mutation (grace also left on after a target was selected: replan not immediate) must FAIL"
cp -r "$W/p/src" "$W/m2"; sed -i 's/target_ = candidates\[i\]; postRouteScansLeft_ = 0;/target_ = candidates[i];/' "$W/m2/ActivityGoals.cpp"
bld "$W/m2" "$T/activity_postroute_scan_tests.cpp" "$W/t_m2"; "$W/t_m2" >/dev/null && { echo "MUTATION 2 SURVIVED"; rc=1; }
echo "== source tests on the patched tree (mine_functionality_produces + playthrough_session_retry fail identically on the NC28/NC29 base, excluded)"
for t in "$T"/*_source_tests.py; do n=$(basename "$t" .py)
  case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac
  python3 -I "$t" "$W/p/src" >/dev/null 2>&1 && echo "PASS $n" || { echo "FAIL $n"; rc=1; }
done
[ $rc -eq 0 ] && echo "OFFLINE RESULT PASS" || echo "OFFLINE RESULT FAIL"
exit $rc
