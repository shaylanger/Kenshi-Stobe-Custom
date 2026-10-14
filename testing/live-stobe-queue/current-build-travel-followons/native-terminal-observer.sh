#!/usr/bin/env bash
# Read-only native terminal-state observer; uses only existing stobe-auto handlers.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/native-terminal-observer.py"
