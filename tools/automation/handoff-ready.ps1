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

$lines = @(
    "HANDOFF READY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "note: $($args -join ' ')"
    "handoff: $hf (written $(Get-Date (Get-Item -LiteralPath $hf).LastWriteTime -Format 'HH:mm'))"
    "kenshi: $kenshi | game.lock: $lock | uncommitted files in $ws : $git"
    "agent status files: $(if ($agents.Count) { ($agents | ForEach-Object { $_.FullName }) -join ', ' } else { 'none' })"
    "inflight markers: $(if ($inflight.Count) { ($inflight | ForEach-Object { $_.Name }) -join ', ' } else { 'none' })"
    ''
    'NEXT SESSION: run  powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1'
    'It prints testing/HANDOFF.md "Right now", every agent status file, inflight markers and batch SUMMARY.txt files.'
    'Respawn agents whose status is not DONE from their status file (fresh agent, not SendMessage), start a waker if'
    'anything is in flight, and carry on from HANDOFF.md.'
)
New-Item -ItemType Directory -Force -Path $runs | Out-Null
$out = Join-Path $runs 'handoff.ready'
Set-Content -LiteralPath $out -Value $lines -Encoding UTF8
"Wrote $out"
$lines
