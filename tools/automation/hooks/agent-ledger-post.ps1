# agent-ledger-post.ps1 (PostToolUse, matcher Agent): one line per Agent call that ran, linking it to its transcript (Shay 2026-10-14).
# Writes C:\KenshiTestRuns\ledger\agent-runs.tsv: time, agentId, output_file, case, ticket, subagent_type, model, effort.
# tools\automation\ledger-report.py adds up the tokens from output_file. AGENT_RUNS overrides the path (tests). Never blocks.
# The routing header the router put in the prompt ("Routing: case=.. tier=.. ticket=..") is read first; the description tags are the fallback.
$runs = if ($env:AGENT_RUNS) { $env:AGENT_RUNS } else { 'C:\KenshiTestRuns\ledger\agent-runs.tsv' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ([string]$in.tool_name -ne 'Agent') { exit 0 }
    if ([string]$in.cwd -notmatch '^C:[\\/]KenshiModding([\\/]|$)') { exit 0 }
    $resp = if ($in.tool_response -is [string]) { [string]$in.tool_response } else { ($in.tool_response | ConvertTo-Json -Depth 8) -replace '\\\\', '\' }
    # hand-back length warning (Shay 2026-10-16): the sub-agent's result text lands in the coordinator's context on every later turn.
    # > 12 non-blank lines (trailing agentId/usage metadata not counted) -> additionalContext warning on stdout. Never blocks. HANDBACK_MAX overrides 12.
    $hbMax = 12; if ($env:HANDBACK_MAX -match '^\d+$') { $hbMax = [int]$env:HANDBACK_MAX }
    $hbText = ''
    if ($in.tool_response -is [string]) { $hbText = [string]$in.tool_response }
    elseif ($in.tool_response.content) { $hbText = (@($in.tool_response.content) | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.text } }) -join "`n" }
    elseif ($in.tool_response.text) { $hbText = [string]$in.tool_response.text }
    elseif ($in.tool_response.result) { $hbText = [string]$in.tool_response.result }
    $hbLines = @($hbText -split "`r?`n")
    $hbCut = @($hbLines | Where-Object { $_ -match '^\s*(agentId:|<usage>|<task-notification>)' } | Select-Object -First 1)
    if ($hbCut.Count) { $ci = [Array]::IndexOf($hbLines, $hbCut[0]); $hbLines = if ($ci -le 0) { @() } else { $hbLines[0..($ci - 1)] } }
    $hbN = @($hbLines | Where-Object { $_ -and $_.Trim() }).Count
    if ($hbN -gt $hbMax -and $hbText -notmatch 'Async agent launched') {
        $warn = "[handback-length: $hbN lines > $hbMax; next time save the report with save-report.ps1 and hand back <= 8 lines]"
        [Console]::Out.WriteLine((@{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $warn } } | ConvertTo-Json -Compress))
    }
    $aid = ''; $out = ''
    if ($resp -match 'agentId"?\s*:\s*"?([A-Za-z0-9_-]+)') { $aid = $Matches[1] }
    if ($resp -match 'output_file"?\s*:\s*"?([^\s"]+)') { $out = $Matches[1] }
    # a foreground run has no output_file in its response: its transcript is <session>\subagents\agent-<agentId>.jsonl
    if (-not $out -and $in.transcript_path -and $aid) {
        $tp = [string]$in.transcript_path
        $out = Join-Path (Join-Path (Split-Path -Parent $tp) ([IO.Path]::GetFileNameWithoutExtension($tp))) ('subagents\agent-' + $aid + '.jsonl')
    }
    if (-not $aid) {
        [IO.File]::AppendAllText((Join-Path (Split-Path -Parent $runs) 'agent-ledger-post.log'), ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' no agentId in response: ' + $resp.Substring(0, [Math]::Min(200, $resp.Length)).Replace("`n", ' ') + "`n"), $utf8)
        exit 0
    }
    $ti = $in.tool_input
    $prompt = [string]$ti.prompt
    $desc = [string]$ti.description
    $case = ''; $ticket = ''; $tier = ''
    if ($prompt -match 'Routing: case=([a-z]*) tier=(\S*) ticket=(\S*)') { $case = $Matches[1]; $tier = $Matches[2]; $ticket = $Matches[3] }
    else {
        if ($desc -match '\[case:([a-z]+)\]') { $case = $Matches[1] }
        if ($desc -match '\[ticket:([A-Za-z0-9._-]+)\]') { $ticket = $Matches[1] }
    }
    $model = [string]$ti.model; $effort = [string]$ti.effort
    if ($tier) {
        $pol = Get-Content -Raw -LiteralPath 'C:\KenshiModding\tools\automation\model-policy.json' | ConvertFrom-Json
        $model = [string]$pol.tiers.$tier.model; $effort = [string]$pol.tiers.$tier.effort
    }
    $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $aid, $out, $case, $ticket, [string]$ti.subagent_type, $model, $effort
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runs) | Out-Null
    [System.IO.File]::AppendAllText($runs, $line + "`n", $utf8)
} catch {
    [Console]::Error.WriteLine("agent-ledger-post: $($_.Exception.Message)")
}
exit 0
