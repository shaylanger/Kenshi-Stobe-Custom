# hook-command-selftest.ps1: runs the EXACT heartbeat hook command from .claude/settings.json through Git Bash (the shell the
# hooks run in; 2026-10-15: backslash paths were eaten by it, bbc3544) with a sample hook JSON on stdin and a temp KCS_RUNS,
# then checks the heartbeat file was written. No real heartbeat file is touched.
# Usage: powershell -NoProfile -File tools\automation\hook-command-selftest.ps1   (exit 0 = PASS)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$settings = Get-Content (Join-Path $root '.claude\settings.json') -Raw | ConvertFrom-Json
$cmds = @()
foreach ($grp in $settings.hooks.PostToolUse) { foreach ($h in $grp.hooks) { if ($h.command -match 'coord-heartbeat') { $cmds += $h.command } } }
if ($cmds.Count -eq 0) { Write-Output 'RESULT hook-command FAIL no coord-heartbeat PostToolUse hook in settings.json'; exit 1 }
$bash = (Get-Command bash -ErrorAction SilentlyContinue | Where-Object { $_.Source -match 'Git' } | Select-Object -First 1).Source
if (-not $bash) { $bash = 'C:\Program Files\Git\bin\bash.exe' }
$tmp = Join-Path $env:TEMP ('hookself-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$fail = 0
try {
    foreach ($c in $cmds) {
        $env:KCS_RUNS = $tmp
        Remove-Item (Join-Path $tmp 'coordinator.heartbeat') -ErrorAction SilentlyContinue
        $json = '{"session_id":"selftest-0001","tool_name":"Bash","tool_input":{"command":"echo hi"},"hook_event_name":"PostToolUse"}'
        $json | & $bash -c $c
        $hb = Join-Path $tmp 'coordinator.heartbeat'
        if ((Test-Path $hb) -and ((Get-Content $hb -Raw) -match 'selftest-0001')) { Write-Output "RESULT hook-command PASS wrote heartbeat via git bash: $c" }
        else { Write-Output "RESULT hook-command FAIL no heartbeat written via git bash: $c"; $fail++ }
    }
} finally { Remove-Item Env:KCS_RUNS -ErrorAction SilentlyContinue; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
exit $fail
