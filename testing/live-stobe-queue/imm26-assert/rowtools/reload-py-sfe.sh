#!/usr/bin/env bash
# reload-py-sfe.sh (imm26-sfE2): python shim used as $PY by reload-run-sfe.sh. Rows 24-c and 26-f go to reloadcheck_sfe.py (SEEDED marker / ClearGroup preconditions on top of the
# unchanged set-A assertions); everything else is handled exactly like reload-py.sh.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 24-c|26-f) exec "$REAL" "$(dirname "$1")/reloadcheck_sfe.py" "$2" "$3";; esac
fi
exec "$(dirname "${BASH_SOURCE[0]}")/reload-py.sh" "$@"
