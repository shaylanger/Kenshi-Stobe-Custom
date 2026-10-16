#!/usr/bin/env bash
# reload-py.sh: python shim used as $PY by reload-run.sh. go-row.sh calls `$PY rowtools/rowcheck.py <ROW> <ev>`; for the save+load resume rows (set A) the
# call is redirected to reloadcheck_a.py, everything else (attempts.py, other rows) runs unchanged. Lets the rows work without editing rowcheck.py / rowdefs.sh.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 26-d|26-dx|26-e|26-f|24-c|23-e|27-a|08-e|20-d) exec "$REAL" "$(dirname "$1")/reloadcheck_a.py" "$2" "$3";; esac
fi
exec "$REAL" "$@"
