#!/usr/bin/env bash
# unblockpy_sff.sh: python shim used as $PY by unblockrun_sff.sh. `$PY rowtools/rowcheck.py 03-b <ev>` goes to unblockcheck_sff.py, everything else runs unchanged.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 03-b) exec "$REAL" "$(dirname "$1")/unblockcheck_sff.py" "$2" "$3";; esac
fi
exec "$REAL" "$@"
