# agent-router.ps1 (PreToolUse, matcher Agent): every subagent gets the model and effort of its tier (Shay 2026-10-14).
# Policy: tools\automation\model-policy.json. Reasoning and prices: docs\MODEL_ROUTING.md.
#   - Tags: the Agent description starts with [case:<name>]. Cases in needs_ticket also need [ticket:<id>].
#   - No case: only kenshi-reader may run. Every other tier needs a case.
#   - Cascade gates: debug needs a FAIL verdict for its ticket; escalate needs a debug row for that ticket and a FAIL verdict
#     written after it. Verdicts: C:\KenshiTestRuns\verdicts\<ticket>.txt (env AGENT_VERDICTS overrides, for tests).
#   - Denied (exit 2) when a rule above fails. Allowed (updatedInput): model and effort set from the tier; a different model or
#     effort the coordinator passed is logged as an override.
#   - Every decision is one line in C:\KenshiTestRuns\ledger\agent-calls.tsv (env AGENT_LEDGER overrides, for tests), UTF-8 without BOM.
#     The ledger write never throws, so a deny still denies when the ledger is unwritable.
#   - Internal error: the call goes through unrouted and an error row is logged (event-sweep.sh reports those).
# Only acts when cwd is under C:\KenshiModding.
$ledger = if ($env:AGENT_LEDGER) { $env:AGENT_LEDGER } else { 'C:\KenshiTestRuns\ledger\agent-calls.tsv' }
$verdicts = if ($env:AGENT_VERDICTS) { $env:AGENT_VERDICTS } else { 'C:\KenshiTestRuns\verdicts' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$inv = [Globalization.CultureInfo]::InvariantCulture

function Write-Ledger([string]$action, [string]$case, [string]$ticket, [string]$stype, [string]$model, [string]$effort, [string]$desc) {
    try {
        $d = ($desc -replace '[\t\r\n]+', ' ')
        if ($d.Length -gt 80) { $d = $d.Substring(0, 80) }
        $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $case, $ticket, $stype, $model, $effort, $action, $d
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ledger) | Out-Null
        [System.IO.File]::AppendAllText($ledger, $line + "`n", $utf8)
    } catch {
        [Console]::Error.WriteLine("agent-router: ledger write failed: $($_.Exception.Message)")
    }
}

function Deny([string]$msg, [string]$case, [string]$ticket, [string]$stype, [string]$desc) {
    Write-Ledger 'deny' $case $ticket $stype '' '' $desc
    [Console]::Error.WriteLine("agent-router: $msg")
    exit 2
}

# latest allow or override ledger time for this case and ticket, or $null
function Get-LastTime([string]$case, [string]$ticket) {
    if (-not (Test-Path -LiteralPath $ledger)) { return $null }
    $best = $null
    foreach ($row in (Get-Content -LiteralPath $ledger -Encoding UTF8)) {
        $f = $row -split "`t"
        if ($f.Count -ge 7 -and $f[1] -eq $case -and $f[2] -eq $ticket -and ($f[6] -eq 'allow' -or $f[6] -eq 'override')) {
            try {
                $t = [datetime]::ParseExact($f[0].Trim(), 'yyyy-MM-dd HH:mm:ss', $inv)
                if (-not $best -or $t -gt $best) { $best = $t }
            } catch {}
        }
    }
    return $best
}

# the ticket's verdict: first word (PASS or FAIL) and write time, or $null when there is no file
function Get-Verdict([string]$ticket) {
    $p = Join-Path $verdicts "$ticket.txt"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $first = [string](Get-Content -LiteralPath $p -TotalCount 1 -Encoding UTF8)
    $first = $first -replace '^\uFEFF', ''
    return @{ Word = (($first.Trim() -split '\s+')[0]); Time = (Get-Item -LiteralPath $p).LastWriteTime }
}

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ([string]$in.tool_name -ne 'Agent') { exit 0 }
    if ([string]$in.cwd -notmatch '^C:[\\/]KenshiModding([\\/]|$)') { exit 0 }
    $pol = Get-Content -Raw -LiteralPath 'C:\KenshiModding\tools\automation\model-policy.json' | ConvertFrom-Json
    $ti = $in.tool_input
    $desc = [string]$ti.description
    $stype = [string]$ti.subagent_type
    $case = ''; $ticket = ''
    if ($desc -match '\[case:([a-z]+)\]') { $case = $Matches[1] }
    if ($desc -match '\[ticket:([A-Za-z0-9._-]+)\]') { $ticket = $Matches[1] }
    $tiers = @($pol.tiers.PSObject.Properties.Name)

    if ($case) {
        $cp = $pol.cases.PSObject.Properties[$case]
        if (-not $cp) { Deny "unknown case [case:$case]. Cases: $(@($pol.cases.PSObject.Properties.Name) -join ', ')" $case $ticket $stype $desc }
        $tier = [string]$cp.Value
        if ($stype -and ($tiers -contains $stype) -and ($stype -ne $tier)) { Deny "case $case runs on $tier, not $stype" $case $ticket $stype $desc }
    } else {
        if ($stype -ne 'kenshi-reader') { Deny 'tag the description with [case:<name>] (cases in tools\automation\model-policy.json). Only kenshi-reader may run without a case' '' $ticket $stype $desc }
        $tier = 'kenshi-reader'
    }
    if (($pol.needs_ticket -contains $case) -and -not $ticket) { Deny "case $case needs a [ticket:<id>] tag" $case '' $stype $desc }
    if ($case -eq 'debug') {
        $v = Get-Verdict $ticket
        if (-not $v -or $v.Word -ne 'FAIL') { Deny "debug on ticket $ticket needs a FAIL verdict first: verdicts\$ticket.txt, written by a verifier" $case $ticket $stype $desc }
    }
    if ($case -eq 'escalate') {
        $dbg = Get-LastTime 'debug' $ticket
        $v = Get-Verdict $ticket
        if (-not $dbg) { Deny "escalate on ticket $ticket needs a debug round on that ticket first" $case $ticket $stype $desc }
        if (-not $v -or $v.Word -ne 'FAIL' -or $v.Time -lt $dbg) { Deny "escalate on ticket $ticket needs a FAIL verdict written after its debug round" $case $ticket $stype $desc }
    }

    $model = [string]$pol.tiers.$tier.model
    $effort = [string]$pol.tiers.$tier.effort
    $action = 'allow'
    if (($ti.model -and [string]$ti.model -ne $model) -or ($ti.effort -and [string]$ti.effort -ne $effort)) { $action = 'override' }
    $new = [ordered]@{}
    foreach ($p in $ti.PSObject.Properties) { $new[$p.Name] = $p.Value }
    $new['model'] = $model
    $new['effort'] = $effort
    # the subagent only sees its prompt, not the description, so the routing facts go into the first line of the prompt
    $new['prompt'] = "Routing: case=$case tier=$tier ticket=$ticket`n" + [string]$ti.prompt
    Write-Ledger $action $case $ticket $stype $model $effort $desc
    @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'allow'; updatedInput = $new } } | ConvertTo-Json -Depth 10 -Compress
    exit 0
} catch {
    Write-Ledger 'error' '' '' '' '' '' $_.Exception.Message
    [Console]::Error.WriteLine("agent-router: internal error, call allowed unrouted: $($_.Exception.Message)")
    exit 0
}
