#!/usr/bin/env bash
# unblockpy_d.sh: python shim used as $PY by unblockrun_d.sh. go-row.sh calls `$PY rowtools/rowcheck.py <ROW> <ev>`; for 03-b the call goes to unblockcheck_d.py,
# everything else (attempts.py, other rows) runs unchanged. Lets row 03-b work without editing rowcheck.py / rowdefs.sh.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 03-b) exec "$REAL" "$(dirname "$1")/unblockcheck_d.py" "$2" "$3";; esac
fi
exec "$REAL" "$@"
