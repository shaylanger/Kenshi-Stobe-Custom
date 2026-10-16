#!/usr/bin/env bash
# sfrpy.sh: python shim used as $PY by sfrrun.sh. go-row.sh calls `$PY rowtools/rowcheck.py <ROW> <ev>`; for 23-b 22-b 20-a the call goes to sfrcheck.py (20-a: the unchanged
# unblockcheck_c.py -> rowcheck.py chain plus the placement rule), everything else (attempts.py, other rows) runs unchanged. rowcheck.py / rowdefs.sh are not edited.
REAL=$(command -v python3 || command -v python)
if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]]; then
  case "${2#IMM-}" in 23-b|22-b|20-a) exec "$REAL" "$(dirname "$1")/sfrcheck.py" "$2" "$3";; esac
fi
exec "$REAL" "$@"
