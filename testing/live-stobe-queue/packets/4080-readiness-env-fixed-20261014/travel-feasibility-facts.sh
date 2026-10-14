export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
printf '=== WORLD ===\n'
timeout 10 stobe-auto status </dev/null
printf '=== TOWN ===\n'
timeout 15 stobe-auto towns 'The Hub' max 5 </dev/null
printf '=== WALK/RUN CAPABILITY ===\n'
timeout 15 stobe-auto runspeed '#2529907200/2' </dev/null
printf '=== CURRENT TARGET ===\n'
timeout 15 stobe-auto stobe_state '#2529907200/2' </dev/null
