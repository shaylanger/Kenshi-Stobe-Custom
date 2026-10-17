#!/usr/bin/env bash
# pywrap_uf3.sh: stand-in for $PY inside go-row.sh (unblockrun_f3.sh): 13-c / 13-c-neg are owned by unblockcheck_f3.py, everything else passes through.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
case "${1:-}" in
  *rowcheck.py) if "$P" "$H/unblockcheck_f3.py" --has "${2:-}"; then shift; exec "$P" "$H/unblockcheck_f3.py" "$@"; fi;;
esac
exec "$P" "$@"
