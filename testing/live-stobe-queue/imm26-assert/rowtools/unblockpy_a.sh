#!/usr/bin/env bash
# unblockpy_a.sh: python shim used as $PY by unblockrun_a.sh. go-row.sh calls `$PY rowtools/rowcheck.py <ROW> <ev>`; for 08-e 08-d 11-b the call goes to unblockcheck_a.py,
# everything else (attempts.py, other rows) runs unchanged. Lets the unblock rows work without editing rowcheck.py / rowdefs.sh.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 08-e|08-d|11-b) exec "$REAL" "$(dirname "$1")/unblockcheck_a.py" "$2" "$3";; esac
fi
exec "$REAL" "$@"
