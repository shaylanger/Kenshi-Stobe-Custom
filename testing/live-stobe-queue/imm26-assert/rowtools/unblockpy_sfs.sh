#!/usr/bin/env bash
# unblockpy_sfs.sh: python shim used as $PY by unblockrun_sfs.sh (imm26-sfS). go-row.sh calls `$PY rowtools/rowcheck.py <ROW> <ev>`; 08-d goes to unblockcheck_sfs.py (08-d v2: the ask check
# looks only after tick 1), everything else (attempts.py, other rows) runs unchanged.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 08-d) exec "$REAL" "$(dirname "$1")/unblockcheck_sfs.py" "$2" "$3";; esac
fi
exec "$REAL" "$@"
