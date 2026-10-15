# tail-ack.ps1 -Agent <name> [-Program <name>]: the NEW coordinator acknowledges the tail's relayed result for <agent>
# (docs/TAIL_HANDOFF_CONTRACT.md section 4/6): sets acked_by_new_coordinator=true in every program ledger that has the agent
# (or only -Program). The tail session may end once all its agents are acked. Exit 1 when no ledger record exists.
# Env: KPL_DIR (ledger dir), KAH_RUNS_DIR.
param([Parameter(Mandatory)][string]$Agent, [string]$Program = '')
$ErrorActionPreference = 'Stop'
$ledger = Join-Path $PSScriptRoot 'program-ledger.ps1'
$rows = @()
try { $rows = @((& powershell -NoProfile -ExecutionPolicy Bypass -File $ledger records | Out-String) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
$hit = @($rows | Where-Object { $_.agent -ieq $Agent -and (-not $Program -or $_.program -ieq $Program) })
if (-not $hit.Count) { Write-Error "tail-ack: agent '$Agent' is in no program ledger"; exit 1 }
foreach ($h in $hit) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger ack $h.program $Agent
    if ($LASTEXITCODE -ne 0) { Write-Error "tail-ack: ledger ack failed for $($h.program)/$($h.wp)"; exit 1 }
}
