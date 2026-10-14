export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -eu
hostname
printf 'PROCESS='
powershell.exe -NoProfile -NonInteractive -Command '$ProgressPreference="SilentlyContinue"; Get-Process -Id 3452,2260 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,Responding | ConvertTo-Json -Compress'
printf 'LISTENER='
netstat.exe -ano -p tcp | grep ':18084' | grep 'LISTENING' || true
printf 'HEALTH='
curl.exe --silent --show-error --max-time 3 --output /dev/null --write-out 'http=%{http_code} total=%{time_total}\n' http://127.0.0.1:18084/health || true
