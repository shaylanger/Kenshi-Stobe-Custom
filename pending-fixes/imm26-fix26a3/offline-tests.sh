#!/bin/bash
# imm26-fix26a3 offline proof (WSL). Usage: bash offline-tests.sh   (needs g++, python3, patch)
# Base (NC30 tree) must FAIL both new tests; patched must PASS them plus the existing source tests; mutations must FAIL.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="${NC30_SRC:-}"; [ -n "$SRC" ] || { [ -d /mnt/c/KenshiTestRuns/imm26-nc30/src ] && SRC=/mnt/c/KenshiTestRuns/imm26-nc30/src || SRC=/c/KenshiTestRuns/imm26-nc30/src; }
T="$HERE/tests"; OLD="$REPO/components/STOBE/tests/cpp"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/base" "$W/p/src"; cp -r "$SRC/." "$W/base/"; cp -r "$SRC/." "$W/p/src/"
(cd "$W/p" && patch --binary -p1 -s -i "$HERE/fix26a3-travel-engine-end.patch") || { echo "PATCH FAILED"; exit 1; }
rc=0
cpp() { g++ -std=gnu++11 -Wall -I"$1" "$T/activity_travel_engine_end_tests.cpp" -o "$2" 2>&1 | head -10; }
echo "== base must FAIL (header absent / old rule)"
cpp "$W/base" "$W/t_base" >/dev/null; [ -x "$W/t_base" ] && { echo "UNEXPECTED: base compiled"; rc=1; } || echo "base: no ActivityTravelArrival.h (FAIL as expected)"
python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/base" | tail -3; python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/base" >/dev/null && { echo "UNEXPECTED PASS on base"; rc=1; }
echo "== patched must PASS behaviour test"
cpp "$W/p/src" "$W/t_p"; "$W/t_p" | tail -3; "$W/t_p" >/dev/null || rc=1
echo "== patched must PASS source test"
python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/p/src" | tail -3; python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/p/src" >/dev/null || rc=1
echo "== mutation 1 (drop the list-empty gate: a foreign/replaced order near the point would count as arrival) must FAIL"
cp -r "$W/p/src" "$W/m1"; sed -i 's/if(!orderListEmpty) return false;//' "$W/m1/ActivityTravelArrival.h"
cpp "$W/m1" "$W/t_m1" >/dev/null; "$W/t_m1" >/dev/null && { echo "MUTATION 1 SURVIVED (behaviour)"; rc=1; }
python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/m1" >/dev/null && { echo "MUTATION 1 SURVIVED (source)"; rc=1; }
echo "== mutation 2 (radius back to 8 u) must FAIL"
cp -r "$W/p/src" "$W/m2"; sed -i 's/kEngineEndRadius = 16.0/kEngineEndRadius = 8.0/' "$W/m2/ActivityTravelArrival.h"
cpp "$W/m2" "$W/t_m2" >/dev/null; "$W/t_m2" >/dev/null && { echo "MUTATION 2 SURVIVED (behaviour)"; rc=1; }
echo "== mutation 3 (Observe no longer uses the predicate: Tick would Replan arrival_not_verified in the same tick) must FAIL"
cp -r "$W/p/src" "$W/m3"; sed -i 's/ || *$//; /!ownedNow \&\& ActivityTravel::EndedNearPoint/d' "$W/m3/ActivityNativeExecutor.cpp"
python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/m3" >/dev/null && { echo "MUTATION 3 SURVIVED"; rc=1; }
echo "== mutation 4 (Poll drops the Succeeded branch) must FAIL"
cp -r "$W/p/src" "$W/m4"; sed -i 's/if(nearEnd) { op.arrived=true; return op.receipt=Result(Receipt::Succeeded,"arrived_order_ended_near_point"); }//' "$W/m4/ActivityNativeExecutor.cpp"
python3 -I "$T/activity_travel_engine_end_source_tests.py" "$W/m4" >/dev/null && { echo "MUTATION 4 SURVIVED"; rc=1; }
echo "== existing tests on the patched tree"
for t in "$OLD"/*_source_tests.py; do n=$(basename "$t" .py)
  case $n in mine_functionality_produces_source_tests|playthrough_session_retry_source_tests) continue;; esac   # fail identically on the NC28-NC30 base
  python3 -I "$t" "$W/p/src" >/dev/null 2>&1 && echo "PASS $n" || { echo "FAIL $n"; rc=1; }
done
for g in activity_goal_tests activity_hunt_progress_tests activity_postroute_scan_tests; do   # Goal tests: result must equal the base result (activity_goal_tests fails on the base too: stale Start() fixture, unrelated)
  [ -f "$OLD/$g.cpp" ] || continue
  for v in base p/src; do
    g++ -std=gnu++11 -include cmath '-D_finite(x)=std::isfinite(x)' -I"$W/$v" "$OLD/$g.cpp" "$W/$v/ActivityGoals.cpp" -o "$W/${g}_${v//\//_}" 2>/dev/null
    if [ -x "$W/${g}_${v//\//_}" ] && "$W/${g}_${v//\//_}" >/dev/null 2>&1; then eval "r_${v//\//_}=PASS"; else eval "r_${v//\//_}=FAIL"; fi
  done
  [ "$r_base" = "$r_p_src" ] && echo "SAME-AS-BASE ($r_p_src) $g" || { echo "DIFFERS-FROM-BASE base=$r_base patched=$r_p_src $g"; rc=1; }
done
[ $rc -eq 0 ] && echo "OFFLINE RESULT PASS" || echo "OFFLINE RESULT FAIL"
exit $rc
