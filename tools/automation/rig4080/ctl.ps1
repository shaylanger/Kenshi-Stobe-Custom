<#
C:\KAH\ctl.ps1 (4080 test rig): run kenshi-ctl.ps1 inside the logged-in desktop session.
Over SSH, processes start in a session without a desktop, so Kenshi can't open its window there.
This runs C:\KAH\tools\kenshi-ctl.ps1 through a one-off interactive scheduled task, waits, and prints its output.
Usage (from the 5090): ssh 4080 powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\ctl.ps1 <status|launch|stop|restart|health|screenshot> [-Save x] [-Owner name] [-Instance n]
Game lock: C:\KenshiTestRuns\game.lock (launch/restart/stop refuse if another owner holds it; 'lock' shows it, 'release' frees it).
Multi-instance (lane 4080b, 2026-10-11): -Instance n >= 2 (or env KAH_INSTANCE) drives the install copy C:\KenshiInst\<n>
(kenshi-instance.ps1) with its own lock game-<n>.lock; C:\KAH\tools\kenshi-ctl.ps1 only sees/stops the game of the install
it is given (-Kenshi), so instance 1 and 2 never touch each other. Each call uses its own task name + wrapper file (two
lanes may call ctl.ps1 at the same time).
#>
param([Parameter(Position = 0)][string]$Command = 'status', [string]$Save = '', [string]$Owner = 'rig4080', [int]$TimeoutSec = 420,
      [int]$Instance = $(if ($env:KAH_INSTANCE -match '^\d+$') { [int]$env:KAH_INSTANCE } else { 1 }))
$ErrorActionPreference = 'Stop'
$k1 = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi'
$kdir = if ($Instance -ge 2) { "C:\KenshiInst\$Instance" } else { $k1 }
if ($Instance -ge 2 -and -not (Test-Path "$kdir\kenshi_x64.exe")) { "no instance $Instance at $kdir (kenshi-instance.ps1 sync -Instance $Instance)"; exit 1 }
$lock = if ($Instance -ge 2) { "C:\KenshiTestRuns\game-$Instance.lock" } else { 'C:\KenshiTestRuns\game.lock' }
if ($Command -eq 'lock') { if (Test-Path $lock) { Get-Content $lock } else { 'free' }; exit 0 }
if ($Command -eq 'release') {
  if (Test-Path $lock) { $h = (Get-Content $lock -TotalCount 1).Trim(); if ($h -ne $Owner) { "lock held by '$h'"; exit 1 }; Remove-Item $lock -Force }
  'released'; exit 0
}
if ($Command -in 'launch', 'restart', 'stop') {
  if (Test-Path $lock) { $h = (Get-Content $lock -TotalCount 1).Trim(); if ($h -ne $Owner) { "lock held by '$h', not '$Owner'"; exit 1 } }
  else { Set-Content $lock "$Owner`n$(Get-Date -Format s)" }
}
$id = [guid]::NewGuid().ToString('N')
$out = "C:\KenshiTestRuns\ctl-$id.txt"
$args2 = "-NoProfile -ExecutionPolicy Bypass -File C:\KAH\tools\kenshi-ctl.ps1 $Command -Kenshi `"$kdir`" -ExtraLogs `"$kdir\KenshiFP.log`"" + $(if ($Save) { " -Save `"$Save`"" } else { '' })
$wrap = "C:\KenshiTestRuns\ctl-run-$($id.Substring(0, 12)).cmd"
# instance >= 2: inst-window.ps1 (desktop session) parks its windows right of the screen + retitles "[i<n>]" while it runs
$watch = if ($Instance -ge 2 -and $Command -in 'launch', 'restart' -and (Test-Path 'C:\KAH\inst-window.ps1')) { "@start `"`" /b powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\KAH\inst-window.ps1 -Instance $Instance`r`n" } else { '' }
Set-Content $wrap "$watch@powershell $args2 > `"$out`" 2>&1`r`n@echo __DONE__>> `"$out`"" -Encoding ASCII
$tn = "KAH_ctl_$($id.Substring(0, 12))"
schtasks /create /tn $tn /tr "`"$wrap`"" /sc once /st 23:59 /it /f | Out-Null
schtasks /run /tn $tn | Out-Null
$end = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $end) {
  if ((Test-Path $out) -and ((Get-Content $out -Raw) -match '__DONE__')) { break }
  Start-Sleep 2
}
schtasks /delete /tn $tn /f | Out-Null
Remove-Item $wrap -Force -ErrorAction SilentlyContinue
Get-ChildItem 'C:\KenshiTestRuns' -Filter 'ctl-run*.cmd' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-2) } | Remove-Item -Force -ErrorAction SilentlyContinue
if (Test-Path $out) { (Get-Content $out) | Where-Object { $_ -ne '__DONE__' }; Remove-Item $out -Force } else { 'no output (timeout)' }
