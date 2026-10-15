# agent-router.ps1 (PreToolUse, matcher Agent): every subagent gets the model and effort of its tier (Shay 2026-10-14).
# Policy: tools\automation\model-policy.json. Reasoning and prices: docs\MODEL_ROUTING.md.
#   - Tags: the Agent description starts with [case:<name>]. An optional [ticket:<id>] is only recorded in the ledger.
#   - No case: only kenshi-reader may run. Every other tier needs a case.
#   - No cascade (Shay 2026-10-15): there are no verdict files, no FAIL gates and no verifier step. One agent on the right model does the task.
#   - Denied (exit 2) when a rule above fails. Allowed (updatedInput): model and effort set from the tier; a different model or
#     effort the coordinator passed is logged as an override.
#   - Every decision is one line in C:\KenshiTestRuns\ledger\agent-calls.tsv (env AGENT_LEDGER overrides, for tests), UTF-8 without BOM.
#     The ledger write never throws, so a deny still denies when the ledger is unwritable.
#   - Long-running in-session agents are allowed again (Shay 2026-10-15, tail handoff: docs/TAIL_HANDOFF_CONTRACT.md section 8). run_in_background and
#     the generator / debugger / escalation tiers are routed like any other call; [short] and [inproc-ok:<reason>] tags are accepted and ignored.
#   - Internal error: the call goes through unrouted and an error row is logged (event-sweep.sh reports those).
# Only acts when cwd is under C:\KenshiModding.
$ledger = if ($env:AGENT_LEDGER) { $env:AGENT_LEDGER } else { 'C:\KenshiTestRuns\ledger\agent-calls.tsv' }
$utf8 = New-Object System.Text.UTF8Encoding($false)

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

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ([string]$in.tool_name -ne 'Agent') { exit 0 }
    if ([string]$in.cwd -notmatch '^C:[\\/]KenshiModding([\\/]|$)') { exit 0 }
    $pol = Get-Content -Raw -LiteralPath $(if ($env:AGENT_POLICY) { $env:AGENT_POLICY } else { 'C:\KenshiModding\tools\automation\model-policy.json' }) | ConvertFrom-Json
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

    # in-session agents (incl. run_in_background and generator/debugger/escalation tiers) are the standard (Shay 2026-10-15, docs/TAIL_HANDOFF_CONTRACT.md).
    # [short] and [inproc-ok:<reason>] tags are still accepted in a description and simply ignored.

    $model = [string]$pol.tiers.$tier.model
    $effort = [string]$pol.tiers.$tier.effort
    # benchmark case (Shay 2026-10-15): model and effort come from [model:x] [effort:y] tags. Fable is never allowed.
    if ($case -eq 'bench') {
        $tm = ''; $te = ''
        if ($desc -match '\[model:([a-z]+)\]') { $tm = $Matches[1] }
        if ($desc -match '\[effort:([a-z]+)\]') { $te = $Matches[1] }
        if (@('haiku', 'sonnet', 'opus') -notcontains $tm) { Deny 'case bench needs [model:haiku|sonnet|opus] (fable is never allowed)' $case $ticket $stype $desc }
        if (@('low', 'medium', 'high', 'xhigh') -notcontains $te) { Deny 'case bench needs [effort:low|medium|high|xhigh]' $case $ticket $stype $desc }
        $model = $tm; $effort = $te
    }
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
