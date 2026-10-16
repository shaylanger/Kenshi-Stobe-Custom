#!/usr/bin/env bash
# usage.sh <script> [--list]   <= 12-line usage for a row/lane script, read from tools/automation/usage-table.tsv (the scripts themselves are not edited or opened).
#   usage.sh unblockrun_f.sh      usage.sh reload-run-sfi      (the .sh/.py suffix and any path are optional)    usage.sh --list = every script in the table
# Prints the usage line wrapped to 150 columns, then "(more: sed -n 1,25p <path>)" when the script is found on disk. Impl: usage.py.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
[ $# -ge 1 ] || { sed -n 2,3p "$0" | cut -c1-200; exit 2; }
exec "$PY" -I "$HERE/usage.py" "$@"
