#!/usr/bin/env bash
# pywrap_cx4.sh: stand-in for $PY in hxrun_cx4.sh (imm26-fix15bx05cx3): 05-cx verdicts go to hxcheck_cx4.py, everything else passes through unchanged (attempt guard = attempts.py).
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
case "${1:-}" in *rowcheck.py) if "$P" "$H/hxcheck_cx4.py" --has "${2:-}"; then shift; exec "$P" "$H/hxcheck_cx4.py" "$@"; fi;; esac
exec "$P" "$@"
