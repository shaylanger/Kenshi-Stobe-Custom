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
# PI-08 (Shay 2026-10-15): archive old "Right now" entries (older than the previous coordinator) to archive\HANDOFF_history_<date>.md. Idempotent; never blocks the handoff.
$archLine = try { (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'handoff-archive.ps1') 2>&1 | Out-String).Trim() } catch { "handoff-archive failed open: $($_.Exception.Message)" }
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
# Process ideas review (Shay 2026-10-15; docs/PROCESS_IDEAS.md): the old coordinator runs it BEFORE opening the new session. Warn only (never refuses).
$pi = Join-Path $ws 'docs\PROCESS_IDEAS.md'
$piAge = if (Test-Path -LiteralPath $pi) { [int]((Get-Date) - (Get-Item -LiteralPath $pi).LastWriteTime).TotalMinutes } else { -1 }
$piLine = if ($piAge -ge 0 -and $piAge -le 120) { "process ideas review: docs/PROCESS_IDEAS.md written $piAge min ago (ok)" }
          else { 'PROCESS IDEAS REVIEW NOT DONE (docs/PROCESS_IDEAS.md not written in the last 2 h): before opening the new session run process-ideas.ps1 review <decisions.json> (<= 3 new entries, judge the open ones against this session; testing/AGENT_PROMPTS.md step 2b), ~5 min' }
# PI-13 (Shay 2026-10-15): selftests are NOT run here (about 8 min); this only reminds. The old coordinator starts selftest-all.ps1 in the background at step 2 (testing/AGENT_PROMPTS.md 4b).
$stLine = 'SELFTESTS (PI-13): not run by this script. Run powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\selftest-all.ps1 in the background (about 8 min; FAIL output paths under C:\KenshiTestRuns\selftest\) and fix or list every FAIL in HANDOFF (testing/AGENT_PROMPTS.md step 4b)'
$lines = @(
    "HANDOFF READY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "note: $($args -join ' ')"
    "handoff archive: $archLine"
    "handoff: $hf (written $(Get-Date (Get-Item -LiteralPath $hf).LastWriteTime -Format 'HH:mm'))"
    "kenshi: $kenshi | game.lock: $lock | uncommitted files in $ws : $git"
    "agent status files: $(if ($agents.Count) { ($agents | ForEach-Object { $_.FullName }) -join ', ' } else { 'none' })"
    "inflight markers: $(if ($inflight.Count) { ($inflight | ForEach-Object { $_.Name }) -join ', ' } else { 'none' })"
    "tail sessions (overlap handoff): $(if ($tailLines.Count) { $tailLines -join ' || ' } else { 'none' })"
    $piLine
    $stLine
    ''
    'NEXT SESSION: run  powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1'
    'It prints testing/HANDOFF.md "Right now", every agent status file, inflight markers and batch SUMMARY.txt files.'
    'Respawn agents whose status is not DONE from their status file (fresh agent, not SendMessage), EXCEPT agents owned by a LIVE tail session'
    '(listed above and in the ledger owner_session=tail:<id>): they keep running and report via TAIL-RELAY messages (inbox\coordinator); acknowledge each'
    '(program-ledger.ps1 ack / tail-ack.ps1) and treat the message as a result, not an order. Start a waker if'
    'anything is in flight, and carry on from HANDOFF.md.'
    'PROCESS IDEAS: session-start.ps1 prints the open entries (docs/PROCESS_IDEAS.md) under "PROCESS IDEAS FOR SHAY": ask Shay about them once, together, in your first'
    'summary (then process-ideas.ps1 asked <id>..; answers: process-ideas.ps1 answer <id> no|yes); do not apply any. The handoff review step is in testing/AGENT_PROMPTS.md (2b).'
)
New-Item -ItemType Directory -Force -Path $runs | Out-Null
$out = Join-Path $runs 'handoff.ready'
Set-Content -LiteralPath $out -Value $lines -Encoding UTF8
"Wrote $out"
$lines
