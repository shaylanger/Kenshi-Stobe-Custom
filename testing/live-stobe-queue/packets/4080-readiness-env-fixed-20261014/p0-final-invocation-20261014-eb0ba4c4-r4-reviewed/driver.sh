#!/usr/bin/env bash
# Executable entry point. Source the documented rig-env first; Python drives only existing KAH handlers.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/driver.py"
