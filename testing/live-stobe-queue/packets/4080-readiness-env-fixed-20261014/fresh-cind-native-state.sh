export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
timeout 15 stobe-auto status </dev/null
timeout 15 stobe-auto time </dev/null
timeout 15 stobe-auto stobe_state '#2529907200/2' </dev/null
timeout 15 stobe-auto where '#2529907200/2' </dev/null
