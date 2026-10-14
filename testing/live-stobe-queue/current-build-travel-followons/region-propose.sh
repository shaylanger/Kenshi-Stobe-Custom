#!/usr/bin/env bash
# Source the documented isolated rig-env helper before invoking.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/region-propose.py"
