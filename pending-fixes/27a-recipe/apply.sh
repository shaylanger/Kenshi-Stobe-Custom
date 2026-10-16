#!/usr/bin/env bash
# apply.sh [rowtools dir] [NPC_IMMERSION_26_TESTS.md]   imm26-fix27a: apply the 27-a recipe fix to the LIVE rowtools dir + the TESTS.md 27-a wording. Idempotent, anchor-asserted
# (per file set nothing is written unless every anchor matches). Do NOT run while a job that sources these scripts runs (a mid-run edit kills it): wait until the 4080-i4 operator is idle.
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D="${1:-$HERE/../../testing/live-stobe-queue/imm26-assert/rowtools}"
T="${2:-$HERE/../../testing/NPC_IMMERSION_26_TESTS.md}"
PY=$(command -v python3 || command -v python)
"$PY" -I "$HERE/patch27a.py" "$D"
"$PY" -I "$HERE/patch27a_tests.py" "$T"
