# agent-successor.ps1 <old> <new>: declare <new> the successor of <old> in the program ledger (PI-11, Shay 2026-10-15).
# Finds the wp whose agent / successors / agent_records contains <old> and appends <new> to that wp's `successors`
# (program-ledger.ps1 set <ledger> <wp> successors+=<new>). The Stop hook rule (e) in agent-guard-lib.ps1 then accepts <new> as the
# successor of <old> while <new> is RUNNING (status updated < 45 min ago) and at least as new as <old>.
# Exit 0 registered (or already registered), 1 <old> is in no ledger wp / bad args. Env: KPL_DIR / KAH_RUNS_DIR as in program-ledger.ps1.
param([Parameter(Position = 0)][string]$Old, [Parameter(Position = 1)][string]$New)
$ErrorActionPreference = 'Stop'
if (-not $Old -or -not $New -or $Old -ceq $New) { 'usage: agent-successor.ps1 <old> <new>   (two different agent names)'; exit 1 }
$pd = if ($env:KPL_DIR) { $env:KPL_DIR } else { Join-Path $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }) 'programs' }
$hit = $null
foreach ($f in Get-ChildItem -LiteralPath $pd -Filter '*.json' -File -ErrorAction SilentlyContinue) {
    try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
    foreach ($w in @($j.wps)) {
        $names = @("$($w.agent)") + @($w.successors | ForEach-Object { "$_" })
        if ($w.PSObject.Properties['agent_records'] -and $w.agent_records) { $names += @($w.agent_records.PSObject.Properties | ForEach-Object { $_.Name }) }
        if (@($names | Where-Object { $_ -ieq $Old }).Count) { $hit = [pscustomobject]@{ Ledger = $f.BaseName; Wp = "$($w.id)"; Has = (@($names | Where-Object { $_ -ieq $New }).Count -gt 0) }; break }
    }
    if ($hit) { break }
}
if (-not $hit) { "agent-successor: '$Old' is not the agent/successor of any work package in $pd (add it first: program-ledger.ps1 set <ledger> <wp> successors+=$Old)"; exit 1 }
if ($hit.Has) { "agent-successor: $New is already listed in ledger $($hit.Ledger) wp $($hit.Wp); nothing to do"; exit 0 }
try { & (Join-Path $PSScriptRoot 'program-ledger.ps1') set $hit.Ledger $hit.Wp "successors+=$New" | Out-Null }
catch { "agent-successor: program-ledger set failed: $($_.Exception.Message)"; exit 1 }
"registered successor $New for $Old in ledger $($hit.Ledger) wp $($hit.Wp)"
exit 0
