#!/usr/bin/env bash
# pywrap_uf.sh: stand-in for $PY inside go-row.sh (unblockrun_f.sh sets PY to this file): 13-c / 13-c-neg are owned by unblockcheck_f.py, everything else passes through
# to pywrap_ub.sh (-> unblockcheck_b.py / rowcheck.py).
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
case "${1:-}" in
  *rowcheck.py) if "$P" "$H/unblockcheck_f.py" --has "${2:-}"; then shift; exec "$P" "$H/unblockcheck_f.py" "$@"; fi;;
esac
exec "$P" "$@"
