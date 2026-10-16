#!/usr/bin/env bash
# pywrap_ub.sh: stand-in for $PY inside go-row.sh (unblockrun_b.sh sets PY to this file): rows owned by unblockcheck_b.py get that checker, everything else passes through.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
case "${1:-}" in
  *rowcheck.py) if "$P" "$H/unblockcheck_b.py" --has "${2:-}"; then shift; exec "$P" "$H/unblockcheck_b.py" "$@"; fi;;
esac
exec "$P" "$@"
