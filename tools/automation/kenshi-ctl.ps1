<#
kenshi-ctl.ps1 (workspace): the harness repo's kenshi-ctl.ps1 with this PC's
paths; also archives stobe.log and KenshiFP.log (both reset on launch).
Commands: status | launch [-Save x] | stop | restart [-Save x] | health | screenshot [-Save n]
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Save = '',
  [int]$TimeoutSec = 300
)
$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
& 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' $Command -Save $Save -TimeoutSec $TimeoutSec `
  -Kenshi $Kenshi -ArchiveRoot 'C:\KenshiTestRuns' `
  -ExtraLogs @("$Kenshi\RE_Kenshi\mods\Stobe\stobe.log", "$Kenshi\KenshiFP.log")
exit $LASTEXITCODE
