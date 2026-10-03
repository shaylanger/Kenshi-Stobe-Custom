<#
kenshi-ctl.ps1 (workspace): the harness repo's kenshi-ctl.ps1 with this PC's
paths; also archives stobe.log, KenshiFP.log and ProfessionGear.log/affixes
(all reset or rewritten on launch).
Commands: status | launch [-Save x] | stop | restart [-Save x] | health | screenshot [-Save n] | lock | release

Game lock (C:\KenshiTestRuns\game.lock): only one session drives Kenshi.
launch/stop/restart take the lock for $env:KAH_OWNER (default 'coordinator')
and refuse if another owner holds it. `release` frees it (owner only),
`lock` shows it. See MASTER_TEST_PLAN.md "How this works".
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Save = '',
  [int]$TimeoutSec = 300
)
$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
$LockFile = 'C:\KenshiTestRuns\game.lock'
$Owner = if ($env:KAH_OWNER) { $env:KAH_OWNER } else { 'coordinator' }

if ($Command -eq 'lock') {
  if (Test-Path $LockFile) { Get-Content $LockFile } else { 'free' }
  exit 0
}
if ($Command -eq 'release') {
  if (Test-Path $LockFile) {
    $held = (Get-Content $LockFile -TotalCount 1).Trim()
    if ($held -ne $Owner) { "lock held by '$held', not '$Owner'"; exit 1 }
    Remove-Item $LockFile -Force
  }
  'released'
  exit 0
}
if ($Command -in @('launch', 'stop', 'restart')) {
  if (Test-Path $LockFile) {
    $held = (Get-Content $LockFile -TotalCount 1).Trim()
    if ($held -ne $Owner) { "Kenshi is locked by '$held' (set KAH_OWNER or ask that session to release)"; exit 1 }
  } else {
    Set-Content -Path $LockFile -Value @($Owner, (Get-Date -Format s)) -Encoding utf8
  }
}

& 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' $Command -Save $Save -TimeoutSec $TimeoutSec `
  -Kenshi $Kenshi -ArchiveRoot 'C:\KenshiTestRuns' `
  -ExtraLogs @("$Kenshi\RE_Kenshi\mods\Stobe\stobe.log", "$Kenshi\KenshiFP.log",
               "$Kenshi\mods\ProfessionGearProgression\ProfessionGear.log",
               "$Kenshi\mods\ProfessionGearProgression\profession_gear_affixes.tsv")
exit $LASTEXITCODE
