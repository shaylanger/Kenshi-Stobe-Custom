# tail-relay.ps1: tail-mode relay of one agent event to the NEW coordinator (docs/TAIL_HANDOFF_CONTRACT.md sections 3 and 4).
#   tail-relay.ps1 -Agent <name> -Report <file> [-Summary <text>] [-ToSession <id>] [-Kind DONE|FAILED|STALL|QUESTION|PEER]
# Builds the relay message (<= 30 lines in total):
#   TAIL-RELAY <agent> <KIND> <iso time>
#   report: <path>
#   ledger: <program>/<wp> routing_note
#   [to: <session>]
#   <key results / patch+test locations / blockers: -Summary lines, else picked from the report>
# writes it to the new coordinator's inbox as <inbox>\<yyyyMMdd-HHmmss>-tail-<agent>.msg (inbox = the agent's tail flag
# new_coordinator_inbox, else <runs>\inbox\coordinator) and prints the same text on stdout, for SendMessage to the new coordinator.
# When the ledger knows the agent the report path is recorded as its result_file and acked_by_new_coordinator is reset (tail-ack.ps1 sets it).
# Fail-open about the ledger: a missing ledger record still relays. Env: KAH_RUNS_DIR (default C:\KenshiTestRuns), KPL_DIR (ledger dir).
param(
    [Parameter(Mandatory)][string]$Agent,
    [string]$Report = '',
    [string]$Summary = '',
    [string]$ToSession = '',
    [ValidateSet('DONE', 'FAILED', 'STALL', 'QUESTION', 'PEER')][string]$Kind = 'DONE'
)
$ErrorActionPreference = 'Stop'
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$ledger = Join-Path $PSScriptRoot 'program-ledger.ps1'
if ($Agent -notmatch '^[A-Za-z0-9_.-]+$') { Write-Error "tail-relay: bad agent name '$Agent'"; exit 1 }
if (-not $Report -and -not $Summary) { Write-Error 'tail-relay: need -Report <file> or -Summary <text>'; exit 1 }
if ($Report -and -not (Test-Path -LiteralPath $Report -PathType Leaf)) {
    if ($Kind -in 'DONE', 'FAILED') { Write-Error "tail-relay: report file not found: $Report"; exit 1 }
}

# ledger record for this agent
$rec = $null
try {
    $rows = @((& powershell -NoProfile -ExecutionPolicy Bypass -File $ledger records | Out-String) | ConvertFrom-Json | ForEach-Object { $_ })
    $rec = @($rows | Where-Object { $_.agent -ieq $Agent }) | Select-Object -First 1
} catch { }

# inbox: the tail flag that owns this agent, else the default
$inbox = Join-Path $runs 'inbox\coordinator'
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $runs 'tail') -Filter '*.flag' -File -ErrorAction SilentlyContinue)) {
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        if (@($j.agents) -contains $Agent -and $j.new_coordinator_inbox) { $inbox = [string]$j.new_coordinator_inbox; break }
    } catch { }
}

$now = Get-Date
$head = @(
    "TAIL-RELAY $Agent $Kind $($now.ToString('yyyy-MM-ddTHH:mm:sszzz'))",
    "report: $(if ($Report) { $Report } else { '(none: see summary)' })",
    "ledger: $(if ($rec) { "$($rec.program)/$($rec.wp)" } else { '(agent not in a program ledger)' }) routing_note"
)
if ($ToSession) { $head += "to: $ToSession" }
$budget = 30 - $head.Count

function Cut([string]$l) { $l = $l.TrimEnd(); if ($l.Length -gt 220) { $l.Substring(0, 217) + '...' } else { $l } }
$body = @()
if ($Summary) {
    $body = @($Summary -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Cut $_ })
} elseif ($Report -and (Test-Path -LiteralPath $Report -PathType Leaf)) {
    $lines = @(Get-Content -LiteralPath $Report -TotalCount 4000 | Where-Object { $_.Trim() })
    $kw = 'RESULT|PASS|FAIL|patch|\.patch|blocker|BLOCK|question|\?\s*$|SELFTEST|commit|STOPPED|error|DONE'
    $pick = @()
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($i -lt 5 -or $lines[$i] -match $kw) { $pick += Cut $lines[$i] } }
    $body = @($pick | Select-Object -Unique)
}
if ($body.Count -gt $budget) {
    $more = $body.Count - ($budget - 1)
    $body = @($body | Select-Object -First ($budget - 1)) + "... ($more more lines: read the report)"
}
$msg = (($head + $body) -join "`n") + "`n"

New-Item -ItemType Directory -Force -Path $inbox | Out-Null
$file = Join-Path $inbox ("{0}-tail-{1}.msg" -f $now.ToString('yyyyMMdd-HHmmss'), $Agent)
[IO.File]::WriteAllText($file, $msg, (New-Object Text.UTF8Encoding($false)))

# record the result file; a new relay is un-acked until tail-ack.ps1 runs
if ($rec -and $Report -and $Kind -in 'DONE', 'FAILED') {
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger route $rec.program $Agent -Owner $rec.owner_session -Result $Report -Note $rec.routing_note | Out-Null } catch { }
}
$msg.TrimEnd()
"(inbox file: $file)" | Write-Host
