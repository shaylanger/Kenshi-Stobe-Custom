<#
C:\KAH\ctl.ps1 (4080 test rig): run kenshi-ctl.ps1 inside the logged-in desktop session.
Over SSH, processes start in a session without a desktop, so Kenshi can't open its window there.
This runs C:\KAH\tools\kenshi-ctl.ps1 through a one-off interactive scheduled task, waits, and prints its output.
Usage (from the 5090): ssh 4080 powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\ctl.ps1 <status|launch|stop|restart|health|screenshot> [-Save x] [-Owner name]
Game lock: C:\KenshiTestRuns\game.lock (launch/restart/stop refuse if another owner holds it; 'lock' shows it, 'release' frees it).
#>
param([Parameter(Position = 0)][string]$Command = 'status', [string]$Save = '', [string]$Owner = 'rig4080', [int]$TimeoutSec = 420)
$ErrorActionPreference = 'Stop'
$lock = 'C:\KenshiTestRuns\game.lock'
if ($Command -eq 'lock') { if (Test-Path $lock) { Get-Content $lock } else { 'free' }; exit 0 }
if ($Command -eq 'release') {
  if (Test-Path $lock) { $h = (Get-Content $lock -TotalCount 1).Trim(); if ($h -ne $Owner) { "lock held by '$h'"; exit 1 }; Remove-Item $lock -Force }
  'released'; exit 0
}
if ($Command -in 'launch', 'restart', 'stop') {
  if (Test-Path $lock) { $h = (Get-Content $lock -TotalCount 1).Trim(); if ($h -ne $Owner) { "lock held by '$h', not '$Owner'"; exit 1 } }
  else { Set-Content $lock "$Owner`n$(Get-Date -Format s)" }
}
$out = "C:\KenshiTestRuns\ctl-$([guid]::NewGuid().ToString('N')).txt"
$args2 = "-NoProfile -ExecutionPolicy Bypass -File C:\KAH\tools\kenshi-ctl.ps1 $Command -ExtraLogs `"C:\Program Files (x86)\Steam\steamapps\common\Kenshi\KenshiFP.log`"" + $(if ($Save) { " -Save `"$Save`"" } else { '' })
$wrap = "C:\KenshiTestRuns\ctl-run.cmd"
Set-Content $wrap "@powershell $args2 > `"$out`" 2>&1`r`n@echo __DONE__>> `"$out`"" -Encoding ASCII
$tn = 'KAH_ctl'
schtasks /create /tn $tn /tr "`"$wrap`"" /sc once /st 23:59 /it /f | Out-Null
schtasks /run /tn $tn | Out-Null
$end = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $end) {
  if ((Test-Path $out) -and ((Get-Content $out -Raw) -match '__DONE__')) { break }
  Start-Sleep 2
}
schtasks /delete /tn $tn /f | Out-Null
if (Test-Path $out) { (Get-Content $out) | Where-Object { $_ -ne '__DONE__' }; Remove-Item $out -Force } else { 'no output (timeout)' }
