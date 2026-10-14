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
    $aid = ''; $out = ''
    if ($resp -match 'agentId:\s*([A-Za-z0-9_-]+)') { $aid = $Matches[1] }
    if ($resp -match 'output_file:\s*([^\s"]+)') { $out = $Matches[1] }
    if (-not $aid) { exit 0 }
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
