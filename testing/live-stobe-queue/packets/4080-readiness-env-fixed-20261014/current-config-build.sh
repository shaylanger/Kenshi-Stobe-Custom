export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
sha256sum /c/KenshiInst/3/mods/Stobe/Stobe.dll /c/KenshiInst/3/mods/AutomationHarness/AutomationHarness.dll
grep -iE '^(ServerHost|ServerPort)' /c/KenshiInst/3/RE_Kenshi/mods/Stobe/StobeCustom.ini
curl.exe -fsS --max-time 5 http://127.0.0.1:18084/health.php
