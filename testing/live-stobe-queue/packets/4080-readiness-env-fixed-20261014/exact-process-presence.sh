export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
timeout 15 powershell.exe -NoProfile -NonInteractive -Command '$ProgressPreference="SilentlyContinue"; $p=Get-CimInstance Win32_Process -Filter "ProcessId=3452"; if($p.ExecutablePath -cne "C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe"){throw "instance process mismatch"}; "PID=3452 exact_i3_executable=true"' </dev/null
MSYS_NO_PATHCONV=1 timeout 10 tasklist.exe /FI 'PID eq 3452' /M Stobe.dll </dev/null
MSYS_NO_PATHCONV=1 timeout 10 tasklist.exe /FI 'PID eq 3452' /M AutomationHarness.dll </dev/null
