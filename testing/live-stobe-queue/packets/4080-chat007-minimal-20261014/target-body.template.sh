export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
# Replace both tokens from the just-captured roster; independently review the
# final bytes and SHA-256 before invoking the guarded wrapper.
timeout 15 stobe-auto where "<EXACT_CURRENT_DISPLAY_NAME>" </dev/null
timeout 15 stobe-auto where "#<CURRENT_SERIAL>/<CURRENT_INDEX>" </dev/null
