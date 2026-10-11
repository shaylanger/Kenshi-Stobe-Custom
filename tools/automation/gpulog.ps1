# gpulog.ps1 [-Rig 5090|4080] [-Every 2]: GPU telemetry every <Every> s to C:\KenshiTestRuns\gpulog\<rig>-<MMdd-HHmm>.csv
# (temp, power, clocks, VRAM, util, pstate, throttle reasons) so a TDR/BSOD can be matched to the GPU state right before it.
# Why (m103 2026-10-11): a TDR hit the 5090 at 16:35 with 2 games + WGC capture + lab analysis running and nothing recorded
# the GPU state; `nvidia-smi -l -f` exits when started hidden, so this loop calls nvidia-smi once per sample and appends.
# One instance per rig (a lock file with the PID); files older than 3 days are deleted at start.
param([string]$Rig = '5090', [int]$Every = 2)
$d = 'C:\KenshiTestRuns\gpulog'; New-Item -ItemType Directory -Force $d | Out-Null
$lock = Join-Path $d "$Rig.pid"
if (Test-Path $lock) { $old = Get-Content $lock -ErrorAction SilentlyContinue; if ($old -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) { Write-Output "gpulog already running pid $old"; exit 0 } }
Set-Content $lock $PID
Get-ChildItem $d -Filter "$Rig-*.csv" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } | Remove-Item -ErrorAction SilentlyContinue
$f = Join-Path $d ("$Rig-" + (Get-Date -Format 'MMdd-HHmm') + '.csv')
$q = 'timestamp,temperature.gpu,power.draw,clocks.gr,clocks.mem,memory.used,utilization.gpu,pstate,clocks_event_reasons.active'
$hdr = & nvidia-smi.exe "--query-gpu=$q" --format=csv 2>&1 | Select-Object -First 1
if ("$hdr" -match 'not a valid field|Invalid') { $q = $q -replace ',clocks_event_reasons.active', '' }
& nvidia-smi.exe "--query-gpu=$q" --format=csv 2>&1 | Select-Object -First 1 | Add-Content $f
while ($true) {
    & nvidia-smi.exe "--query-gpu=$q" --format=csv,noheader 2>&1 | Add-Content $f
    Start-Sleep -Seconds $Every
}
