# agent-status.ps1: every agent (fixer, rig operator, builder, ...) reports to a FILE, not only to the session that
# started it, so any later session can pick it up (Shay 2026-10-10: agents of an old session couldn't reach the new one).
#   agent-status.ps1 <name> <RUNNING|DONE|FAILED|STOPPED-CONTEXT> "<task>" "<latest step>" "<outputs/paths>" ["<next step>"]
# Writes C:\KenshiTestRuns\agents\<name>.status (overwritten each call). Call it at start, after every milestone,
# and with DONE/FAILED + the final result paths before the final report. Read back by session-start.ps1.
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ValidateSet('RUNNING', 'DONE', 'FAILED', 'STOPPED-CONTEXT')][string]$State,
    [Parameter(Mandatory)][string]$Task,
    [string]$Step = '',
    [string]$Outputs = '',
    [string]$Next = ''
)
$dir = 'C:\KenshiTestRuns\agents'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$f = Join-Path $dir "$Name.status"
@(
    "$Name | $State | $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    "task: $Task"
    "latest: $Step"
    "outputs: $Outputs"
    "next: $Next"
) | Set-Content -LiteralPath $f -Encoding UTF8
"wrote $f"
