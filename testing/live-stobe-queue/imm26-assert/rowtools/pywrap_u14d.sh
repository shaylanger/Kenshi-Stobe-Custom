#!/usr/bin/env bash
# pywrap_u14d.sh: stand-in for $PY inside go-row.sh (unblockrun_14d.sh): row 14-d is owned by unblockcheck_14d.py, everything else (attempts.py ...) passes through.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
case "${1:-}" in
  *rowcheck.py) if "$P" "$H/unblockcheck_14d.py" --has "${2:-}"; then shift; exec "$P" "$H/unblockcheck_14d.py" "$@"; fi;;
esac
exec "$P" "$@"
