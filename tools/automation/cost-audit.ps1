# cost-audit.ps1 - wrapper for cost-audit.py (read-only cost/token audit of Claude Code transcripts).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\cost-audit.ps1 [-Since YYYY-MM-DD] [-Out DIR] [-NoLabels]
param(
    [string]$Since = '',
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
if ($NoLabels) { $argsList += '--no-labels' }
& $py @argsList
exit $LASTEXITCODE
