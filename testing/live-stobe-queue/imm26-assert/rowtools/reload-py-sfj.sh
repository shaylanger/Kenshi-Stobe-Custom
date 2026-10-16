#!/usr/bin/env bash
# reload-py-sfj.sh (imm26-sfJ): python shim used as $PY by reload-run-sfj.sh. Rows 23-e and 20-d go to reloadcheck_sfj.py (23-e: control chase + stand-off threshold; 20-d: the unchanged
# set-A check); everything else is handled exactly like reload-py.sh.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 23-e|20-d) exec "$REAL" "$(dirname "$1")/reloadcheck_sfj.py" "$2" "$3";; esac
fi
exec "$(dirname "${BASH_SOURCE[0]}")/reload-py.sh" "$@"
