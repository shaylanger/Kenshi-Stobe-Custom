# agent-status.ps1: every agent (fixer, rig operator, builder, ...) reports to a FILE, not only to the session that
# started it, so any later session can pick it up (Shay 2026-10-10: agents of an old session couldn't reach the new one).
#   agent-status.ps1 <name> <RUNNING|DONE|FAILED|STOPPED-CONTEXT> "<task>" "<latest step>" "<outputs/paths>" ["<next step>"]
# Writes C:\KenshiTestRuns\agents\<name>.status (overwritten each call). Call it at start, after every milestone,
# and with DONE/FAILED + the final result paths before the final report. Read back by session-start.ps1.
# Handoff guards (Shay 2026-10-15; agent work must not be lost or stall at a context handoff):
#   RUNNING          creates/touches the inflight marker C:\KenshiTestRuns\inflight\<name> (an existing marker keeps its content, e.g. a
#                    batch out dir) and deletes the respawn todos of the agents this one continues (agent-guard-lib.ps1 successor rules).
#   DONE             deletes the marker (and this agent's respawn todo).
#   WARN-120k        a RUNNING call whose step starts with 'WARN-120k' (lane operator at ~120k context, Shay 2026-10-15 handover overlap)
#                    also writes the marker agents\<name>.warn; operator-warn.ps1 turns it into ONE urgent waker event carrying the
#                    successor spawn text. DONE / FAILED / STOPPED-CONTEXT delete the marker (and agents\<name>.warn.spawn.md).
#   STOPPED-CONTEXT  keeps the marker and writes C:\KenshiTestRuns\respawn\<name>.todo (task, handoff path, status path, next) so a
#                    fresh agent is spawned from it; FAILED keeps the marker too. Coordinators never delete the marker of a
#                    STOPPED-CONTEXT/FAILED agent until a successor exists.
# Program ledger: every call also runs `program-ledger.ps1 sync <name> <STATE>` (RUNNING->running, DONE->done, STOPPED-CONTEXT/FAILED->stopped
#   on the ledger WP whose agent/successors names this agent; programs\*.json; fail-open).
# Test switch: KAH_RUNS_DIR (root, default C:\KenshiTestRuns); selftest: agent-guard-selftest.ps1.
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ValidateSet('RUNNING', 'DONE', 'FAILED', 'STOPPED-CONTEXT')][string]$State,
    [Parameter(Mandatory)][string]$Task,
    [string]$Step = '',
    [string]$Outputs = '',
    [string]$Next = ''
)
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$dir = Join-Path $runs 'agents'
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
# --- handoff guards: inflight marker + respawn todo (never fails the status write) ---
try {
    $mk = Join-Path $runs "inflight\$Name"
    $todo = Join-Path $runs "respawn\$Name.todo"
    switch ($State) {
        'RUNNING' {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mk) | Out-Null
            if (Test-Path -LiteralPath $mk) { (Get-Item -LiteralPath $mk).LastWriteTime = Get-Date }
            else { Set-Content -LiteralPath $mk -Value $f -Encoding ascii }
            Remove-Item -LiteralPath $todo -Force -ErrorAction SilentlyContinue
            if ($Step -match '^\s*WARN-120k') { Set-Content -LiteralPath (Join-Path $dir "$Name.warn") -Value @("$Name", (Get-Date -Format s), $Step) -Encoding ascii }
            . (Join-Path $PSScriptRoot 'agent-guard-lib.ps1')
            Remove-SupersededTodos -AgentsDir $dir
        }
        'DONE' {
            Remove-Item -LiteralPath $mk, $todo -Force -ErrorAction SilentlyContinue
        }
        'STOPPED-CONTEXT' {
            if (-not (Test-Path -LiteralPath $mk)) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mk) | Out-Null; Set-Content -LiteralPath $mk -Value $f -Encoding ascii }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $todo) | Out-Null
            $ho = Join-Path $dir "$Name.handoff.md"
            @(
                "name: $Name"
                "written: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                "task: $Task"
                "handoff: $(if (Test-Path -LiteralPath $ho) { $ho } else { '(none written: use the status file)' })"
                "status: $f"
                "next: $Next"
                "action: spawn a FRESH agent from the handoff/status file; never SendMessage this one"
                "handback: tell the successor to hand back at most 8 lines (verdict, files/commits, SHA/paths, one next action, any DECISION/QUESTION for Shay) and save the full report with save-report.ps1 first"
            ) | Set-Content -LiteralPath $todo -Encoding UTF8
        }
    }
} catch { }
# --- WARN-120k marker: any terminal state clears it (fail-open) ---
try { if ($State -ne 'RUNNING') { Remove-Item -LiteralPath (Join-Path $dir "$Name.warn"), (Join-Path $dir "$Name.warn.spawn.md") -Force -ErrorAction SilentlyContinue } } catch { }
# --- program ledger: move the work package this agent owns (programs\*.json, program-ledger.ps1 sync); fail-open ---
try {
    $pl = Join-Path $PSScriptRoot 'program-ledger.ps1'
    if ((Test-Path -LiteralPath $pl) -and (Test-Path -LiteralPath (Join-Path $runs 'programs'))) { & $pl sync $Name $State 2>$null }
} catch { }
