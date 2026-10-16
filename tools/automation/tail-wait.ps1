# tail-wait.ps1 (PI-28 + PI-27, Shay 2026-10-15): the ONE background wait of a TAIL session (docs/TAIL_HANDOFF_CONTRACT.md, testing/AGENT_PROMPTS.md block B).
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\tail-wait.ps1 -Session <session id>     (run as a BACKGROUND task)
# Watches ONLY the agents the tail owns (flag agents + ledger owner tail:<session>), not the event stream. Writes <runs>\tail\<session>.wait with its
# pid, process start time and a heartbeat every IntervalSec (<=15) so the Stop hook can prove the wait is alive; the hook then lets the turn END
# instead of blocking, and the session is woken by this task's completion. Exits (prints one line, exit 0) as soon as the tail has something to do:
#   an owned agent finished/stalled and needs its relay/ack, or every agent is released, or the flag is gone, or MaxHours passed.
# Re-arm it after handling the wake-up (relay, then run it again). Nothing else is read or written except the .wait file.
param(
    [Parameter(Mandatory)][string]$Session,
    [string]$Runs = '',
    [ValidateRange(1, 15)][int]$IntervalSec = 5,
    [double]$MaxHours = 6
)
$ErrorActionPreference = 'Stop'
# dot-sourcing tail-mode.ps1 (via the lib) re-runs its param block in this scope and would reset $Session/$Runs: copy ours first
$sess = $Session; $runsArg = $Runs; $ivl = $IntervalSec; $maxH = $MaxHours
. (Join-Path $PSScriptRoot 'tail-wait-lib.ps1')
$Session = $sess; $IntervalSec = $ivl; $MaxHours = $maxH
$runsDir = Get-TailRuns $runsArg
$flagPath = Get-TailFlagPath $runsDir $Session
$wf = Get-TailWaitPath $runsDir $Session
$me = Get-Process -Id $PID
$armed = (Get-Date).ToString('o')
$deadline = (Get-Date).AddHours($MaxHours)
function Write-Wait {
    $o = [ordered]@{ session = $Session; pid = $PID; proc_start = $me.StartTime.ToString('o'); armed = $armed; hb = (Get-Date).ToString('o'); interval = $IntervalSec; script = 'tail-wait.ps1' }
    $tmp = "$wf.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $wf -Force
}
try {
    New-Item -ItemType Directory -Force -Path (Split-Path $wf) | Out-Null
    # Check the action BEFORE registering: if the tail already has something to do, exit at once without ever looking armed.
    $reason = ''
    while ($true) {
        if (-not (Test-Path -LiteralPath $flagPath)) { $reason = "tail flag $flagPath is gone (tail left or was closed)"; break }
        $flag = Read-TailFlag $flagPath
        if (-not $flag) { $reason = 'tail flag unreadable'; break }
        $reason = Get-TailWaitAction $runsDir $flag
        if ($reason) { break }
        Write-Wait
        if ((Get-Date) -gt $deadline) { $reason = "MaxHours $MaxHours reached: re-arm the wait"; break }
        Start-Sleep -Seconds $IntervalSec
    }
    "TAIL-WAIT $Session EXIT $reason"
} finally {
    try {
        $j = (Get-Content -LiteralPath $wf -Raw -ErrorAction Stop) | ConvertFrom-Json
        if ([int]$j.pid -eq $PID) { Remove-Item -LiteralPath $wf -Force -ErrorAction SilentlyContinue }
    } catch { }
}
