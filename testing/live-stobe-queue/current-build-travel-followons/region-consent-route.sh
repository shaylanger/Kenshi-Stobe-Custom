#!/usr/bin/env bash
# Source the documented isolated rig-env helper and prepare exact receipts first.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/region-consent-route.py"
