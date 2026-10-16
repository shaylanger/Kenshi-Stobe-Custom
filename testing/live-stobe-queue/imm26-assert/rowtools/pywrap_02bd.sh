#!/usr/bin/env bash
# pywrap_02bd.sh (imm26-rr02): stand-in for $PY inside go-row.sh for hxrun_02bd.sh.  02-bx / 02-dx verdicts come from hxcheck_02bd.py; everything else goes to pywrap_hx.sh unchanged.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
case "${1:-}" in *rowcheck.py) if "$P" "$H/hxcheck_02bd.py" --has "${2:-}"; then shift; exec "$P" "$H/hxcheck_02bd.py" "$@"; fi;; esac
exec "$H/pywrap_hx.sh" "$@"
