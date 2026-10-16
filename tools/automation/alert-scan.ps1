# alert-scan.ps1 (PI-21, Shay 2026-10-15): scan for urgent waker-type alerts and keep the open-alert ledger (alert-lib.ps1).
#   -Hook     PostToolUse hook (registered in .claude/settings.json next to coord-heartbeat.ps1): reads the hook JSON on stdin, runs ONE scan
#             at most every 60 s (any session, so a busy subagent keeps the ledger fresh), and prints the reminder JSON
#             {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[open-alerts: n, oldest m min: ...]"}} ONLY to the live
#             coordinator (not subagents, not tail sessions, not agent sessions) and only while an alert is older than 3 min. Always exit 0, fail open.
#   -Force    scan now (ignore the 60 s rate limit);   -List  print the open alerts;   no switch: scan (rate-limited) and print a summary.
# Runs: -Runs <dir> or $env:KAH_RUNS_DIR (default C:\KenshiTestRuns). Selftest: alert-ledger-selftest.ps1.
param([switch]$Hook, [switch]$Force, [switch]$List, [string]$Runs = '')
$ErrorActionPreference = 'SilentlyContinue'
try {
    . (Join-Path $PSScriptRoot 'alert-lib.ps1')
    if (-not $Runs) { $Runs = Get-AlertRuns }
    if ($List) {
        $o = @(Get-OpenAlerts $Runs)
        if (-not $o.Count) { 'no open alerts' } else { $o | ForEach-Object { "$($_.Id) | $([int]$_.AgeMin) min | $($_.Text)" } }
        exit 0
    }
    if ($Hook) {
        $in = $null
        try { if ([Console]::IsInputRedirected) { $raw = [Console]::In.ReadToEnd(); if ($raw) { $in = $raw | ConvertFrom-Json } } } catch { }
        [void](Invoke-AlertScan -Runs $Runs)
        $isAgent = [bool]($env:KAH_AGENT_NAME -or ($in -and $in.agent_id))
        if ($isAgent) { exit 0 }
        $sid = if ($in -and $in.session_id) { [string]$in.session_id } else { '' }
        if ($sid -and (Test-Path -LiteralPath (Join-Path (Join-Path $Runs 'tail') (($sid -replace '[\/:*?"<>|]', '_') + '.flag')))) { exit 0 }   # tail session
        $hb = Join-Path $Runs 'coordinator.heartbeat'                     # only the live coordinator (same rule as the Stop hook)
        if ((Test-Path -LiteralPath $hb) -and $sid) {
            $hp = (Get-Content -LiteralPath $hb -TotalCount 1) -split '\s+'
            if ($hp.Count -ge 2 -and $hp[1] -ne $sid -and ((Get-Date) - (Get-Item -LiteralPath $hb).LastWriteTime).TotalMinutes -lt 30) { exit 0 }
        }
        $msg = Get-AlertReminder $Runs
        if ($msg) { @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress | Write-Output }
        exit 0
    }
    $r = Invoke-AlertScan -Runs $Runs -Force:$Force
    if ($r.Skipped) { 'alert-scan: skipped (rate limit / scan running); open=' + @(Get-OpenAlerts $Runs).Count }
    else { "alert-scan: open=$($r.Open) opened=$(@($r.Opened) -join ',') closed=$(@($r.Closed) -join ',')" }
} catch { }
exit 0
