# agent-abandon.ps1 <name> "<reason>": mark a STOPPED-CONTEXT/FAILED agent as dropped on purpose (nobody will respawn it).
# Writes C:\KenshiTestRuns\agents\<name>.abandoned and removes its respawn todo; the Stop hook and session-start no longer report it.
# The status file is kept (git/history). Test switch: KAH_RUNS_DIR.
param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Reason)
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$dir = Join-Path $runs 'agents'
if (-not (Test-Path -LiteralPath (Join-Path $dir "$Name.status"))) { "no such agent status: $Name"; exit 1 }
Set-Content -LiteralPath (Join-Path $dir "$Name.abandoned") -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $Reason" -Encoding UTF8
Remove-Item -LiteralPath (Join-Path $runs "respawn\$Name.todo") -Force -ErrorAction SilentlyContinue
# also drop its inflight marker so an abandoned agent stops counting as in-flight work (Stop hook)
Remove-Item -LiteralPath (Join-Path $runs "inflight\$Name") -Force -ErrorAction SilentlyContinue
"abandoned $Name ($Reason)"
