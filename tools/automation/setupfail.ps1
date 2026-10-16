# setupfail.ps1: SETUP-FAIL unblock tickets (Shay 2026-10-15). Thin wrapper over setupfail.py (the logic and docs live there).
#   setupfail.ps1 list [-All] [-Lane <lane>]        one line per open ticket: row, age, needs, owner, state (unowned first, then oldest)
#   setupfail.ps1 assign <row> <agent> [plan_path]  owner = agent; open -> planned
#   setupfail.ps1 state <row> open|planned|building|ready|closed [note]
#   setupfail.ps1 close <row> [note]
#   setupfail.ps1 open <row> <lane> <reason>        (normally created by mark-row.py / go-row attempts.py)
#   setupfail.ps1 sync [-Notify]                    tickets <-> NPC_IMMERSION_26_TESTS.md (create for SETUP-FAIL rows without a ticket, close PASS/FAIL/GATED)
#   setupfail.ps1 backfill [-Force]                 tickets for the CURRENT SETUP-FAIL rows (+ the 2026-10-15 owner/state seed)
#   setupfail.ps1 brief [n]                         the SETUP-FAIL TICKETS section for session-start -Brief (cap n lines, default 12)
# Tickets: <runs>\setupfail\<row>.json; env KAH_RUNS_DIR (default C:\KenshiTestRuns), KAH_TESTS_MD.
param([Parameter(Position = 0)][string]$Cmd = 'list', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$py = Join-Path $PSScriptRoot 'setupfail.py'
$pyexe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyexe) { $pyexe = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $pyexe) { Write-Error 'setupfail: python not found'; exit 1 }
$a = @($Cmd.ToLower())
$flags = @{ '-all' = '--all'; '-lane' = '--lane'; '-notify' = '--notify'; '-force' = '--force' }
foreach ($r in @($Rest)) { if ($flags.ContainsKey("$r".ToLower())) { $a += $flags["$r".ToLower()] } else { $a += $r } }
& $pyexe $py @a
exit $LASTEXITCODE
