#!/bin/bash
# imm26-fix26anav offline proof (WSL). Usage: bash offline-tests.sh   (needs g++, python3, patch)
# Base (NC31 tree) must FAIL both new tests; patched must PASS them plus the existing source tests; mutations must FAIL.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="${NC31_SRC:-}"; [ -n "$SRC" ] || { [ -d /mnt/c/KenshiTestRuns/imm26-nc31/src ] && SRC=/mnt/c/KenshiTestRuns/imm26-nc31/src || SRC=/c/KenshiTestRuns/imm26-nc31/src; }
T="$HERE/tests"; OLD="$REPO/components/STOBE/tests/cpp"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/base" "$W/p/src"; cp -r "$SRC/." "$W/base/"; cp -r "$SRC/." "$W/p/src/"
(cd "$W/p" && patch --binary -p1 -s -i "$HERE/fix26anav-offmesh-reach.patch") || { echo "PATCH FAILED"; exit 1; }
rc=0
cpp() { g++ -std=gnu++11 -Wall -I"$1" "$T/activity_offmesh_reach_tests.cpp" -o "$2" 2>&1 | head -10; }
PYT="$T/activity_offmesh_reach_source_tests.py"
echo "== base must FAIL (header absent / old rule)"
cpp "$W/base" "$W/t_base" >/dev/null; [ -x "$W/t_base" ] && { echo "UNEXPECTED: base compiled"; rc=1; } || echo "base: no ActivityOffMeshReach.h (FAIL as expected)"
python3 -I "$PYT" "$W/base" | tail -3; python3 -I "$PYT" "$W/base" >/dev/null && { echo "UNEXPECTED PASS on base"; rc=1; }
echo "== patched must PASS behaviour test"
cpp "$W/p/src" "$W/t_p"; "$W/t_p" | tail -3; "$W/t_p" >/dev/null || rc=1
echo "== patched must PASS source test"
python3 -I "$PYT" "$W/p/src" | tail -3; python3 -I "$PYT" "$W/p/src" >/dev/null || rc=1
echo "== mutation 1 (drop the off-mesh gate: an on-mesh actor with a failed pathExists would count as reachable) must FAIL"
cp -r "$W/p/src" "$W/m1"; sed -i 's/ || onMesh || !visible/ || !visible/' "$W/m1/ActivityOffMeshReach.h"
cpp "$W/m1" "$W/t_m1" >/dev/null; "$W/t_m1" >/dev/null && { echo "MUTATION 1 SURVIVED (behaviour)"; rc=1; }
python3 -I "$PYT" "$W/m1" >/dev/null && { echo "MUTATION 1 SURVIVED (source)"; rc=1; }
echo "== mutation 2 (range 35 u -> 300 u) must FAIL"
cp -r "$W/p/src" "$W/m2"; sed -i 's/kOffMeshShortRange = 35.0/kOffMeshShortRange = 300.0/' "$W/m2/ActivityOffMeshReach.h"
cpp "$W/m2" "$W/t_m2" >/dev/null; "$W/t_m2" >/dev/null && { echo "MUTATION 2 SURVIVED (behaviour)"; rc=1; }
python3 -I "$PYT" "$W/m2" >/dev/null && { echo "MUTATION 2 SURVIVED (source)"; rc=1; }
echo "== mutation 3 (Refresh no longer consults OffMeshShortRange) must FAIL"
cp -r "$W/p/src" "$W/m3"; sed -i 's/t\.reachable=Stobe::ActivityReach::OffMeshShortRange(/(void)Stobe::ActivityReach::OffMeshShortRange(/' "$W/m3/ActivityRuntimeBindings.cpp"
python3 -I "$PYT" "$W/m3" >/dev/null && { echo "MUTATION 3 SURVIVED"; rc=1; }
echo "== existing tests on the patched tree"
for t in "$OLD"/*_source_tests.py; do n=$(basename "$t" .py)
  case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac   # fail identically on the NC28-NC31 base
  if python3 -I "$t" "$W/p/src" >/dev/null 2>&1; then echo "PASS $n"
  elif python3 -I "$t" "$W/base" >/dev/null 2>&1; then echo "FAIL $n (passes on base)"; rc=1
  else echo "SAME-AS-BASE (fails on both) $n"; fi
done
[ $rc -eq 0 ] && echo "OFFLINE RESULT PASS" || echo "OFFLINE RESULT FAIL"
exit $rc
