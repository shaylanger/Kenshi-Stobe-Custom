export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
printf '=== TIME ===\n'
timeout 10 stobe-auto time </dev/null
printf '=== ISOLATION ===\n'
timeout 10 stobe-auto input_isolation status </dev/null
printf '=== FP ===\n'
timeout 10 stobe-auto fp_state </dev/null
printf '=== ROSTER ===\n'
timeout 20 stobe-auto chars 300 </dev/null
