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
    [ValidateSet('DONE', 'FAILED', 'STALL', 'QUESTION', 'PEER', 'TAILDONE')][string]$Kind = 'DONE',
    [switch]$Force   # PI-57: bypass the 2 h identical-relay dedupe (also env KAH_RELAY_NODEDUPE=1)
)
if ($Force) { $env:KAH_RELAY_NODEDUPE = '1' }
# Target (2026-10-15, "relay follows the current coordinator"): without -ToSession the message goes to the CURRENT coordinator
# (C:\KenshiTestRuns\coordinator.current, written by session-start.ps1 / the heartbeat claim; tail-mode.ps1 current); a -ToSession that is
# itself a tail session or a dead coordinator is replaced by the current coordinator. Pointer missing/unreadable = old behaviour
# (inbox file only, plus -ToSession when given). The inbox file is ALWAYS written. The chosen target is printed on the last line;
# SendMessage the printed text to it. -Kind TAILDONE = the tail announces it has finished all agents and is closing (tail-close.ps1).
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

# where does it go? (fail-open: any error keeps the requested -ToSession / inbox only)
$tgt = @{ Target = $ToSession; Reason = 'as requested'; Redirected = $false }
try {
    $tgt = & { param($tm, $r, $a, $t) . $tm; Resolve-RelayTarget $r $a $t } (Join-Path $PSScriptRoot 'tail-mode.ps1') $runs $Agent $ToSession
} catch { $tgt = @{ Target = $ToSession; Reason = "target resolution failed ($($_.Exception.Message))"; Redirected = $false } }
$ToSession = [string]$tgt.Target

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

# PI-57 (Shay 2026-10-16): drop a relay whose content hash equals one already delivered for the same agent within the last 2 h
# (an agent waiting on its own background job re-sent the same DONE report 7 times). Hash = agent + kind + report path + report file SHA256 + body
# (the time/to header lines are not part of it). STALL and TAILDONE are never deduped (a repeated stall is information). Drops are logged in
# <runs>\tail\relay-dedupe.log and nothing is written (no inbox file, no ledger change); exit 0. -Force or env KAH_RELAY_NODEDUPE=1 bypasses.
$dedupeMin = 120
$dedupeDir = Join-Path $runs 'tail\relay-dedupe'
$dedupeFile = Join-Path $dedupeDir ("{0}.json" -f $Agent)
$relayHash = $null
if ($Kind -in 'DONE', 'FAILED', 'QUESTION', 'PEER') {
    try {
        $rsha = ''
        if ($Report -and (Test-Path -LiteralPath $Report -PathType Leaf)) { $rsha = (Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash }
        $sha = [Security.Cryptography.SHA256]::Create()
        $relayHash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(("$Agent|$Kind|$Report|$rsha|" + ($body -join "`n")))) | ForEach-Object { $_.ToString('x2') })
        $prior = @()
        if (Test-Path -LiteralPath $dedupeFile) { $prior = @((Get-Content -LiteralPath $dedupeFile -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) }
        $prior = @($prior | Where-Object { $_ -and $_.hash -and ((Get-Date) - [datetime]$_.time).TotalMinutes -lt $dedupeMin })
        $hit = $prior | Where-Object { $_.hash -eq $relayHash } | Select-Object -First 1
        if ($hit -and -not $env:KAH_RELAY_NODEDUPE) {
            $ageMin = [int]((Get-Date) - [datetime]$hit.time).TotalMinutes
            $note = "{0} DROP duplicate relay agent={1} kind={2} hash={3} (identical to {4} delivered {5} min ago)" -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $Agent, $Kind, $relayHash.Substring(0, 12), $hit.file, $ageMin
            New-Item -ItemType Directory -Force -Path (Join-Path $runs 'tail') | Out-Null
            Add-Content -LiteralPath (Join-Path $runs 'tail\relay-dedupe.log') -Value $note -Encoding UTF8
            "TAIL-RELAY $Agent $Kind DROPPED: identical to the relay already delivered $ageMin min ago ($($hit.file)); nothing sent."
            "(inbox file: none -- duplicate relay dropped; relay target: none -- see $runs\tail\relay-dedupe.log)" | Write-Host
            exit 0
        }
    } catch { $relayHash = $null }
}

New-Item -ItemType Directory -Force -Path $inbox | Out-Null
$file =Join-Path $inbox ("{0}-tail-{1}.msg" -f $now.ToString('yyyyMMdd-HHmmss'), $Agent)
[IO.File]::WriteAllText($file, $msg, (New-Object Text.UTF8Encoding($false)))

# remember this relay's hash for the dedupe window (fail-open)
if ($relayHash) {
    try {
        New-Item -ItemType Directory -Force -Path $dedupeDir | Out-Null
        $keep = @()
        if (Test-Path -LiteralPath $dedupeFile) { $keep = @((Get-Content -LiteralPath $dedupeFile -Raw | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_ -and $_.hash -and ((Get-Date) - [datetime]$_.time).TotalMinutes -lt $dedupeMin }) }
        $keep += [pscustomobject]@{ hash = $relayHash; time = $now.ToString('o'); file = (Split-Path -Leaf $file) }
        [IO.File]::WriteAllText($dedupeFile, (ConvertTo-Json -InputObject @($keep) -Depth 3), (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

# record the result file; a new relay is un-acked until tail-ack.ps1 runs
if ($rec -and $Report -and $Kind -in 'DONE', 'FAILED') {
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger route $rec.program $Agent -Owner $rec.owner_session -Result $Report -Note $rec.routing_note | Out-Null } catch { }
}
$msg.TrimEnd()
"(inbox file: $file; relay target: $(if ($ToSession) { $ToSession } else { 'none, inbox file only' }) -- $($tgt.Reason))" | Write-Host
