export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
printf '=== I3 PROCESS AND LOADED MODULES ===\n'
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' -ExpectedExecutablePath 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'
printf '=== CURRENT WORLD / SAVE ===\n'
timeout 15 stobe-auto status </dev/null
printf '=== INPUT ISOLATION ===\n'
timeout 15 stobe-auto input_isolation status </dev/null
printf '=== FRESH ACTOR LIST (300) ===\n'
timeout 20 stobe-auto chars 300 </dev/null
