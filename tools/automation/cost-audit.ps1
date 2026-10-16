# cost-audit.ps1 - wrapper for cost-audit.py (read-only cost/token audit of Claude Code transcripts).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\cost-audit.ps1 [-Since 'YYYY-MM-DD[ HH:MM]'] [-Until ...] [-Agents a,b] [-Out DIR] [-NoLabels] [-PilotCompare A,B]
# Default window = 2026-10-14 00:00 local to now (-Since all = no lower bound).
param(
    [string]$Since = '',
    [string]$Until = '',
    [string]$Agents = '',
    [string[]]$PilotCompare = @(),
    [string]$Out = 'C:\KenshiTestRuns\agents\out\imm26-costaudit',
    [switch]$NoLabels
)
$py = $null
foreach ($c in @('python', 'python3', 'py')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { $py = $cmd.Source; break }
}
if (-not $py) { $py = (Get-Command python3 -ErrorAction Stop).Source }
$argsList = @('-I', (Join-Path $PSScriptRoot 'cost-audit.py'), '--out', $Out)
if ($Since) { $argsList += @('--since', $Since) }
if ($Until) { $argsList += @('--until', $Until) }
if ($Agents) { $argsList += @('--agents', $Agents) }
if ($PilotCompare.Count -eq 2) { $argsList += @('--pilot-compare', $PilotCompare[0], $PilotCompare[1]) }
if ($NoLabels) { $argsList += '--no-labels' }
& $py @argsList
exit $LASTEXITCODE
