# agent-note.ps1 (cut3): a status milestone that does NOT cost its own model turn. Prefix it to the next real command in the SAME tool call:
#   powershell -NoProfile -File C:\KenshiModding\tools\automation\agent-note.ps1 <name> "<step>" ["<outputs>"] ["<next>"] ; <real command>
# (bash: `powershell.exe -NoProfile -File C:/KenshiModding/tools/automation/agent-note.ps1 <name> "<step>" ; <real command>`)
# Keeps the status RUNNING and the task text (read from the existing status file), replaces latest/outputs/next, then delegates to agent-status.ps1
# (marker, ledger sync, WARN-120k handling stay in ONE place). With the hooks wired (hooks\agent-status-hook.py) you normally need NO status call at all:
# RUNNING is written at spawn, `latest:` is stamped every 5 min from your tool calls, DONE/FAILED/STOPPED-CONTEXT from your final message.
# Use it only for a milestone a successor must read (an outputs path, a next step), or -State STOPPED-CONTEXT / DONE / FAILED merged into the final command.
param(
    [Parameter(Mandatory, Position = 0)][string]$Name,
    [Parameter(Mandatory, Position = 1)][string]$Step,
    [Parameter(Position = 2)][string]$Outputs = '',
    [Parameter(Position = 3)][string]$Next = '',
    [ValidateSet('RUNNING', 'DONE', 'FAILED', 'STOPPED-CONTEXT')][string]$State = 'RUNNING'
)
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$sf = Join-Path $runs "agents\$Name.status"
$task = '(note)'; $o = $Outputs; $n = $Next
if (Test-Path -LiteralPath $sf) {
    $lines = @(Get-Content -LiteralPath $sf -ErrorAction SilentlyContinue)
    foreach ($l in $lines) {
        if ($l -match '^task:\s?(.*)$') { $task = $Matches[1] }
        elseif ($l -match '^outputs:\s?(.*)$' -and -not $PSBoundParameters.ContainsKey('Outputs')) { $o = $Matches[1] }
        elseif ($l -match '^next:\s?(.*)$' -and -not $PSBoundParameters.ContainsKey('Next')) { $n = $Matches[1] }
    }
}
& (Join-Path $PSScriptRoot 'agent-status.ps1') $Name $State $task $Step $o $n | Out-Null
