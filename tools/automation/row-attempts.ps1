# row-attempts.ps1: inspect / override the go-row.sh attempt guard (PI-06).
#   row-attempts.ps1 show [lane]                       failed rows per lane (attempt count, last verdict, cause) + last 15 audit lines
#   row-attempts.ps1 reset <lane> <ROW> "<reason>"     forget the row's failed state so go-row.sh runs it again (reason is mandatory, logged)
#   row-attempts.ps1 log [n]                           last n audit lines (default 40) from attempts.log
# One-shot alternative without resetting: bash go-row.sh --allow-retry "<reason>" <ROW> <lane>   (also go-batch.sh --allow-retry "<reason>" ...)
# State: C:\KenshiTestRuns\row-attempts\<lane>.json ; audit trail: C:\KenshiTestRuns\row-attempts\attempts.log (time lane row event verdict attempt cause/reason)
param([Parameter(Position=0)][string]$Cmd = 'show', [Parameter(Position=1)][string]$A = '', [Parameter(Position=2)][string]$B = '', [Parameter(Position=3)][string]$Reason = '')
$ErrorActionPreference = 'Stop'
$dir = if ($env:KAH_ROWS_BASE_WIN) { Join-Path $env:KAH_ROWS_BASE_WIN 'row-attempts' } else { 'C:\KenshiTestRuns\row-attempts' }
$py = (Get-Command python3 -ErrorAction SilentlyContinue).Source; if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (-not $py) { throw 'python not found' }
$script = Join-Path $PSScriptRoot '..\..\testing\live-stobe-queue\imm26-assert\rowtools\attempts.py'
switch ($Cmd) {
  'show'  { if ($A) { & $py -I $script show $dir $A } else { & $py -I $script show $dir } }
  'reset' { if (-not $A -or -not $B -or -not $Reason) { Write-Error 'usage: row-attempts.ps1 reset <lane> <ROW> "<reason>"'; exit 2 }
            & $py -I $script reset $dir $A ($B -replace '^IMM-', '') $Reason; exit $LASTEXITCODE }
  'log'   { $n = if ($A) { [int]$A } else { 40 }; $f = Join-Path $dir 'attempts.log'; if (Test-Path $f) { Get-Content $f -Tail $n } else { 'no attempts.log yet' } }
  default { Write-Error "unknown command '$Cmd' (show|reset|log)"; exit 2 }
}
