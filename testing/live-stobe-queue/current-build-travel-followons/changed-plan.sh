#!/usr/bin/env bash
# Source tools/automation/rig-env.sh and operator preflight before running.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/changed-plan.py"
