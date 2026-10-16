# agent-ledger-post-selftest.ps1: the PostToolUse Agent hook (a) still writes the ledger line, (b) warns (additionalContext, exit 0) when a hand-back is > 12 lines.
$ErrorActionPreference = 'Stop'
$hook = Join-Path $PSScriptRoot 'hooks\agent-ledger-post.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('alp-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmp | Out-Null
$env:AGENT_RUNS = Join-Path $tmp 'agent-runs.tsv'
$fail = 0
function Chk($n, $c) { if ($c) { "ok   $n" } else { "FAIL $n"; $script:fail++ } }
function Run($text, $asString) {
    $resp = if ($asString) { $text + "`nagentId: abc123 (use SendMessage)`n<usage>total_tokens: 5</usage>" } else { @{ status = 'completed'; agentId = 'abc123'; content = @(@{ type = 'text'; text = $text }) } }
    $o = @{ tool_name = 'Agent'; cwd = 'C:\KenshiModding'; tool_input = @{ prompt = 'x'; description = '[case:read] t'; subagent_type = 'kenshi-reader' }; tool_response = $resp } | ConvertTo-Json -Depth 8
    $r = $o | powershell -NoProfile -ExecutionPolicy Bypass -File $hook
    @{ out = ($r -join "`n"); code = $LASTEXITCODE }
}
$short = (1..8 | ForEach-Object { "line $_" }) -join "`n"
$long = (1..20 | ForEach-Object { "line $_" }) -join "`n"
$r = Run $short $false; Chk 'object response, 8 lines: no warning, exit 0' ($r.code -eq 0 -and $r.out -notmatch 'handback-length')
$r = Run $long $false; $j = try { $r.out | ConvertFrom-Json } catch { $null }; Chk 'object response, 20 lines: exact warning in hookSpecificOutput.additionalContext (PostToolUse), exit 0' ($r.code -eq 0 -and $j -and $j.hookSpecificOutput.hookEventName -eq 'PostToolUse' -and $j.hookSpecificOutput.additionalContext -eq '[handback-length: 20 lines > 12; next time save the report with save-report.ps1 and hand back <= 8 lines]')
$r = Run $long $true;   Chk 'string response: 20 lines + trailing agentId/usage metadata not counted' ($r.code -eq 0 -and $r.out -match 'handback-length: 20 lines')
$r = Run $short $true;  Chk 'string response, 8 lines + metadata: no warning' ($r.out -notmatch 'handback-length')
$twelve = (1..12 | ForEach-Object { "l$_" }) -join "`n"
$r = Run $twelve $false; Chk '12 lines exactly: no warning' ($r.out -notmatch 'handback-length')
Chk 'ledger line still written' ((Test-Path $env:AGENT_RUNS) -and (@(Get-Content $env:AGENT_RUNS).Count -ge 5) -and ((Get-Content $env:AGENT_RUNS | Select-Object -First 1) -match 'abc123'))
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
if ($fail) { "SELFTEST FAIL $fail"; exit 1 } else { 'SELFTEST OK' }
