export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
printf '=== EXACT TARGET STATE ===\n'
timeout 15 stobe-auto state '#2529907200/2' </dev/null
printf '=== EXACT NAME RESOLUTION ===\n'
timeout 15 stobe-auto where 'Cind' </dev/null
printf '=== EXACT SERIAL RESOLUTION ===\n'
timeout 15 stobe-auto where '#2529907200/2' </dev/null
