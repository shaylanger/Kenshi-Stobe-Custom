#!/bin/bash
# imm26-fix26a offline proof. Usage: bash offline-tests.sh   (needs WSL/git-bash python3 + patch)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="${NC28_SRC:-/c/KenshiTestRuns/imm26-nc28/src}"
T="$REPO/components/STOBE/tests/cpp/native_travel_arrival_latch_source_tests.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cp -r "$SRC" "$W/base"; cp -r "$SRC" "$W/patched"
rc=0
echo "== base must FAIL"; python3 "$T" "$W/base" && { echo "UNEXPECTED PASS on base"; rc=1; }
(cd "$W" && mkdir -p p/src && cp -r patched/. p/src/ && cd p && patch --binary -p1 -i "$HERE/fix26a-arrival.patch") || { echo "PATCH FAILED"; exit 1; }
echo "== patched must PASS"; python3 "$T" "$W/p/src" || rc=1
echo "== mutation (drop the latch in Observe) must FAIL"
cp -r "$W/p/src" "$W/m1"; sed -i 's/op\.arrived || dx/dx/' "$W/m1/ActivityNativeExecutor.cpp"
python3 "$T" "$W/m1" && { echo "MUTATION 1 SURVIVED"; rc=1; }
echo "== mutation (drop one Poll latch) must FAIL"
cp -r "$W/p/src" "$W/m2"; sed -i '0,/op\.arrived=true;/{s/op\.arrived=true;//}' "$W/m2/ActivityNativeExecutor.cpp"
python3 "$T" "$W/m2" && { echo "MUTATION 2 SURVIVED"; rc=1; }
echo "== other source tests on patched copy"
for t in "$REPO"/components/STOBE/tests/cpp/*_source_tests.py; do
  python3 "$t" "$W/p/src" >/dev/null 2>&1 && echo "PASS $(basename "$t")" || echo "FAIL $(basename "$t")"
done
[ $rc -eq 0 ] && echo "OFFLINE RESULT PASS" || echo "OFFLINE RESULT FAIL"
exit $rc
