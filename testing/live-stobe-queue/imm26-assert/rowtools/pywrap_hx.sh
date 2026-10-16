#!/usr/bin/env bash
# pywrap_hx.sh: stand-in for $PY inside go-row.sh (hxrun.sh sets PY to this file). go-row.sh calls `$PY .../rowcheck.py <ROW> <ev>` for the verdict and
# `$PY .../attempts.py ...` for the attempt guard: the hardening rows owned by hxcheck.py get that checker, everything else passes through unchanged.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P=$(command -v python3 || command -v python)
[ -f "$H/hxcheck_b.py" ] && case "${1:-}" in *rowcheck.py) if "$P" "$H/hxcheck_b.py" --has "${2:-}"; then shift; exec "$P" "$H/hxcheck_b.py" "$@"; fi;; esac   # family B (imm26-hxB)
[ -f "$H/hxcheck_a.py" ] && case "${1:-}" in *rowcheck.py) if "$P" "$H/hxcheck_a.py" --has "${2:-}"; then shift; exec "$P" "$H/hxcheck_a.py" "$@"; fi;; esac   # family A (imm26-hxA)
case "${1:-}" in
  *rowcheck.py) if "$P" "$H/hxcheck.py" --has "${2:-}"; then shift; exec "$P" "$H/hxcheck.py" "$@"; fi;;
esac
exec "$P" "$@"
