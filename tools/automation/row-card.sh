#!/usr/bin/env bash
# row-card.sh <row> [lane]   fixed card (<= 600 chars) for one imm26 test row: status, claim, exact RUN command, SETUP, EXPECT, RESULT/evidence path, last attempt.
# Built from testing/NPC_IMMERSION_26_TESTS.md + tools/automation/row-runners.tsv + claims\ + row-attempts\ (read-only). Use it instead of grep/awk over the 200 KB TESTS file.
# The full row text is still there: grep -n "IMM-<row> " testing/NPC_IMMERSION_26_TESTS.md  (only when the card is not enough). Impl: rowcard.py.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
[ -n "$1" ] || { sed -n 2,4p "$0" | cut -c1-200; exit 2; }
if [ -n "$2" ]; then exec "$PY" -I "$HERE/rowcard.py" card "$1" --lane "$2"; fi
exec "$PY" -I "$HERE/rowcard.py" card "$1"
