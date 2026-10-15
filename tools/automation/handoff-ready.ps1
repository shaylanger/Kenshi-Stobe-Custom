# handoff-ready.ps1: the last step of a context-limit handoff (the context-meter hook orders it at 300k).
# Writes C:\KenshiTestRuns\handoff.ready = proof the handoff is complete + where everything is, so the next
# session starts from fixed files instead of the old session's memory. Read back by session-start.ps1.
#   handoff-ready.ps1 "<one-line note: what was in progress>"
# Refuses (exit 1) unless testing/HANDOFF.md was updated in the last 30 min.
$ErrorActionPreference = 'Stop'
$ws = 'C:\KenshiModding'
$runs = 'C:\KenshiTestRuns'
$hf = Join-Path $ws 'testing\HANDOFF.md'
$age = (Get-Date) - (Get-Item -LiteralPath $hf).LastWriteTime
if ($age.TotalMinutes -gt 30) {
    "REFUSED: testing\HANDOFF.md was last written $([int]$age.TotalMinutes) min ago. Update its 'Current state' / 'Right now' first, then rerun."
    exit 1
}
$agentDir = Join-Path $runs 'agents'
$agents = @(Get-ChildItem -LiteralPath $agentDir -Filter '*.status' -File -ErrorAction SilentlyContinue)
$inflight = @(Get-ChildItem -LiteralPath (Join-Path $runs 'inflight') -File -ErrorAction SilentlyContinue)
$lock = if (Test-Path -LiteralPath (Join-Path $runs 'game.lock')) { (Get-Content -Raw -LiteralPath (Join-Path $runs 'game.lock')).Trim() } else { 'free' }
$kenshi = if (Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue) { 'running' } else { 'closed' }
$git = @(git -C $ws status --porcelain 2>$null).Count

# Overlap handoff (docs/TAIL_HANDOFF_CONTRACT.md): tail sessions still own running agents; the new coordinator must not respawn them.
$tailLines = @()
try {
    $rr = $runs
    $tailLines = @(& {
        . (Join-Path $PSScriptRoot 'tail-mode.ps1')   # its param block resets $runs/$Session inside this scope only
        foreach ($f in (Get-TailFlags $rr)) {
            $ag = @(Get-TailAgentSet $rr $f)
            "tail session $($f.Session) pid $($f.Pid) $(if ($f.Alive) { 'LIVE' } else { 'DEAD' }): owns agents $(if ($ag.Count) { ($ag | ForEach-Object { "$($_.Agent) [$($_.Why)]" }) -join ', ' } else { 'none' })"
        }
    })
} catch { }
$lines = @(
    "HANDOFF READY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "note: $($args -join ' ')"
    "handoff: $hf (written $(Get-Date (Get-Item -LiteralPath $hf).LastWriteTime -Format 'HH:mm'))"
    "kenshi: $kenshi | game.lock: $lock | uncommitted files in $ws : $git"
    "agent status files: $(if ($agents.Count) { ($agents | ForEach-Object { $_.FullName }) -join ', ' } else { 'none' })"
    "inflight markers: $(if ($inflight.Count) { ($inflight | ForEach-Object { $_.Name }) -join ', ' } else { 'none' })"
    "tail sessions (overlap handoff): $(if ($tailLines.Count) { $tailLines -join ' || ' } else { 'none' })"
    ''
    'NEXT SESSION: run  powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1'
    'It prints testing/HANDOFF.md "Right now", every agent status file, inflight markers and batch SUMMARY.txt files.'
    'Respawn agents whose status is not DONE from their status file (fresh agent, not SendMessage), EXCEPT agents owned by a LIVE tail session'
    '(listed above and in the ledger owner_session=tail:<id>): they keep running and report via TAIL-RELAY messages (inbox\coordinator); acknowledge each'
    '(program-ledger.ps1 ack / tail-ack.ps1) and treat the message as a result, not an order. Start a waker if'
    'anything is in flight, and carry on from HANDOFF.md.'
)
New-Item -ItemType Directory -Force -Path $runs | Out-Null
$out = Join-Path $runs 'handoff.ready'
Set-Content -LiteralPath $out -Value $lines -Encoding UTF8
"Wrote $out"
$lines
