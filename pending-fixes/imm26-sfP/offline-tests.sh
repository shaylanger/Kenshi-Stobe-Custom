#!/usr/bin/env bash
# imm26-sfP proof check (run in WSL):  bash offline-tests.sh [NC22 src dir]
#   1. source test on the unpatched NC22 src  -> must FAIL (26-d cause present)
#   2. apply sfPedit.py to a scratch copy      -> source test must PASS
#   3. the shipped sfP-over-nc22.patch must apply cleanly to a fresh NC22 copy and produce byte-identical ActivityRuntimeBindings.cpp
# Prints RESULT sfP-offline PASS|FAIL.
S=${1:-/mnt/c/KenshiTestRuns/imm26-nc22/src}
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=/mnt/c/KenshiModding/components/STOBE/tests/cpp
W=$HOME/sfPwork; rm -rf "$W"; mkdir -p "$W/a/src" "$W/b/src" "$W/c/src"
for d in a b c; do cp "$S"/ActivityRuntimeBindings.cpp "$S"/ActivityRuntime.cpp "$S"/ActivityGoals.cpp "$W/$d/src/"; done
ok=1
python3 "$T/hunt_grant_import_sight_source_tests.py" "$W/a/src" > "$W/before.txt"; rb=$?
echo "before: exit=$rb $(head -1 "$W/before.txt")"; [ $rb -ne 0 ] || { echo "FAIL baseline must fail the source test"; ok=0; }
python3 "$H/sfPedit.py" "$W/b" || ok=0
python3 "$T/hunt_grant_import_sight_source_tests.py" "$W/b/src" > "$W/after.txt"; ra=$?
echo "after: exit=$ra $(head -1 "$W/after.txt")"; [ $ra -eq 0 ] || { cat "$W/after.txt"; ok=0; }
( cd "$W/c" && patch -p1 --binary < "$H/sfP-over-nc22.patch" > "$W/patch.txt" 2>&1 ) || { cat "$W/patch.txt"; echo "FAIL patch does not apply"; ok=0; }
cmp -s "$W/b/src/ActivityRuntimeBindings.cpp" "$W/c/src/ActivityRuntimeBindings.cpp" || { echo "FAIL patch result differs from sfPedit.py result"; ok=0; }
python3 "$H/sfPedit.py" "$W/b" >/dev/null 2>&1 && { echo "FAIL second sfPedit run must refuse (already applied)"; ok=0; }
[ $ok = 1 ] && echo "RESULT sfP-offline PASS (baseline FAILs, patched PASSes, patch == edit script)" || echo "RESULT sfP-offline FAIL"
[ $ok = 1 ]
