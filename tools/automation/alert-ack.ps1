# alert-ack.ps1 (PI-21, Shay 2026-10-15): close an open alert after acting on it.
#   alert-ack.ps1 <id|subject|wildcard> "<action taken>"     closes every open alert whose id or subject matches (id = lane-idle-5090-i4, subject = 5090-i4)
#   alert-ack.ps1 -List                                        print the open alerts
# The action text is required (it is stored with the closed alert). Ack ONLY closes: the same incident is not re-opened for 30 min; if the condition is
# still true after that (or comes back later) a new alert opens. An alert whose condition clears by itself closes without an ack ("cleared").
# Alerts opened for a lane also remove inbox\operators\<lane>-alert.txt. -Runs / $env:KAH_RUNS_DIR override C:\KenshiTestRuns (selftest).
param([Parameter(Position = 0)][string]$Key = '', [Parameter(Position = 1)][string]$Action = '', [switch]$List, [string]$Runs = '')
. (Join-Path $PSScriptRoot 'alert-lib.ps1')
if (-not $Runs) { $Runs = Get-AlertRuns }
$open = @(Get-OpenAlerts $Runs)
if ($List -or -not $Key) {
    if (-not $open.Count) { 'no open alerts' } else { $open | ForEach-Object { "$($_.Id) | subject $($_.Subject) | $([int]$_.AgeMin) min | $($_.Text)" } }
    exit 0
}
if (-not $Action -or $Action.Trim().Length -lt 3) { Write-Error 'alert-ack: give the action taken as the second argument (what you did or why it is a false alarm).'; exit 2 }
$hit = @($open | Where-Object { $_.Id -ieq $Key -or $_.Subject -ieq $Key -or $_.Id -like $Key })
if (-not $hit.Count) { "alert-ack: no open alert matches '$Key'. Open: " + ($(if ($open.Count) { ($open | ForEach-Object Id) -join ', ' } else { 'none' })); exit 1 }
foreach ($a in $hit) { if (Close-Alert $Runs $a.Id 'ack' $Action.Trim()) { "ACKED $($a.Id): $($Action.Trim())" } }
Update-OperatorAlertFiles $Runs
exit 0
