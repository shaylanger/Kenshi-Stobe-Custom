# tail-ack.ps1 -Agent <name> [-Program <name>]: the NEW coordinator acknowledges the tail's relayed result for <agent>
# (docs/TAIL_HANDOFF_CONTRACT.md section 4/6): sets acked_by_new_coordinator=true in every program ledger that has the agent
# (or only -Program). The tail session may end once all its agents are acked. An agent in no ledger is acked via <runs>\tail\acks\<agent>.ack (PI-59).
# Env: KPL_DIR (ledger dir), KAH_RUNS_DIR.
# Auto-close (2026-10-15): when this ack leaves a tail session with NO pending agent (all done + acknowledged), the tail is finished:
# tail-close.ps1 -Source ack -NoRelay is called for it (closes its claude process after ~20 s; checks in tail-close.ps1, fail closed).
# -NoClose only prints the hint; -DryRunClose previews. Env KAH_TAIL_NO_CLOSE=1 disables the kill.
param([Parameter(Mandatory)][string]$Agent, [string]$Program = '', [switch]$NoClose, [switch]$DryRunClose)
$ErrorActionPreference = 'Stop'
$ledger = Join-Path $PSScriptRoot 'program-ledger.ps1'
$rows = @()
try { $rows = @((& powershell -NoProfile -ExecutionPolicy Bypass -File $ledger records | Out-String) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
$hit = @($rows | Where-Object { $_.agent -ieq $Agent -and (-not $Program -or $_.program -ieq $Program) })
# PI-59: an agent in no program ledger (in-session imm26-* operators/fixers) is acked through a marker file
# <runs>\tail\acks\<agent>.ack (read by Get-TailAgentSet in tail-mode.ps1). It changes no agent state.
$runsDir0 = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
if (-not $hit.Count) {
    $ackDir = Join-Path $runsDir0 'tail\acks'
    New-Item -ItemType Directory -Force -Path $ackDir | Out-Null
    $safe = ($Agent -replace '[^A-Za-z0-9._-]', '_')
    Set-Content -LiteralPath (Join-Path $ackDir "$safe.ack") -Value ("acked " + (Get-Date).ToString('s') + " (agent in no program ledger)") -Encoding ASCII
    "acked $Agent via marker (agent in no program ledger)"
}
foreach ($h in $hit) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger ack $h.program $Agent
    if ($LASTEXITCODE -ne 0) { Write-Error "tail-ack: ledger ack failed for $($h.program)/$($h.wp)"; exit 1 }
}

# ---- did this ack finish a tail? ----
try {
    $runsDir = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
    $ctx = @{ Agent = $Agent; Runs = $runsDir; Dir = $PSScriptRoot; NoClose = [bool]$NoClose; Dry = [bool]$DryRunClose }
    & {
        param($ctx)
        . (Join-Path $ctx.Dir 'tail-mode.ps1')
        foreach ($f in @(Get-TailFlags $ctx.Runs)) {
            $set = @(Get-TailAgentSet $ctx.Runs $f)
            if (-not ($set | Where-Object { $_.Agent -ieq $ctx.Agent })) { continue }
            $pend = @($set | Where-Object { $_.Pending })
            if ($pend.Count) { "tail $($f.Session): still waiting for $(($pend | ForEach-Object { "$($_.Agent) [$($_.Why)]" }) -join '; ')"; continue }
            if ($ctx.NoClose) { "tail $($f.Session): all agents done+acked. Close it with: tail-close.ps1 -Session $($f.Session) [-DryRun]"; continue }
            "tail $($f.Session): all agents done+acked -> closing the finished tail session"
            $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ctx.Dir 'tail-close.ps1'), '-Session', $f.Session, '-Source', 'ack', '-NoRelay', '-Runs', $ctx.Runs)
            if ($ctx.Dry) { $a += '-DryRun' }
            $ErrorActionPreference = 'Continue'
            & powershell @a 2>&1 | ForEach-Object { "  $_" }
            $ErrorActionPreference = 'Stop'
        }
    } $ctx
} catch { "tail-ack: tail-close check failed open ($($_.Exception.Message)); nothing closed" }
