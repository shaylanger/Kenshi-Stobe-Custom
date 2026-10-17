# rowgate.ps1: row rework gate CLI (imm26 credit-review cut #1; docs/ROW_REWORK_GATE.md). Thin wrapper over rowgate.py.
#   rowgate.ps1 status [row]                         one line per row with gated agents; with a row: every attempt, replay-evidence candidates, what the next agent needs
#   rowgate.ps1 list                                 same as status without a row
#   rowgate.ps1 add <row> <name> <role> [report] [outcome]   record an agent by hand (role fixer|recipe|investigator|operator); state running
#   rowgate.ps1 done <row> <name> [outcome]          mark an agent finished (clears the one-open-agent-per-row block)
#   rowgate.ps1 close <row> [outcome]                row PASSED / finished: attempts reset (new round) on the next agent
#   rowgate.ps1 cost <row> <name> <usd>              record an agent's cost
#   rowgate.ps1 seed                                 backfill from today's agents\*.status files (idempotent)
#   rowgate.ps1 rows <text>                          show which row ids the detector finds in a description
# Ledger: C:\KenshiTestRuns\rowgate\<row>.json ; gate/skip logs next to it. Hooks: tools\automation\hooks\rowgate-guard.ps1 (Pre) and rowgate-post.ps1 (Post).
param([Parameter(Position = 0)][string]$Cmd = 'status', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$py = Join-Path $PSScriptRoot 'rowgate.py'
$pyexe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyexe) { $pyexe = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $pyexe) { Write-Error 'rowgate: python not found'; exit 1 }
& $pyexe -I $py $Cmd @Rest
exit $LASTEXITCODE
