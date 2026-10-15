# agent-host-ensure.ps1 [-DryRun]: make sure the hidden agent-host daemon runs when it has work (Shay 2026-10-15).
# Work = queued agent-queue\*.job files or RUNNING INDEPENDENT agents. Down = agent-host.pid dead, or host.state.json beat older than 120 s.
# Prints one line: HOST up|down-restarted|down-would-restart|idle-down ... . Test switch: KAH_RUNS_DIR. Fail-open (never throws).
param([switch]$DryRun)
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
try {
    $q = Join-Path $runs 'agent-queue'
    $jobs = @(Get-ChildItem -LiteralPath $q -Filter '*.job' -File -ErrorAction SilentlyContinue).Count
    . (Join-Path $PSScriptRoot 'agent-rollcall.ps1')
    $ind = @(Get-AgentRoll | Where-Object { $_.Kind -eq 'INDEPENDENT' }).Count
    $alive = $false; $beatAge = $null
    $pf = Join-Path $q 'agent-host.pid'
    if (Test-Path -LiteralPath $pf) { $hp = 0; [int]::TryParse((Get-Content -LiteralPath $pf -Raw).Trim(), [ref]$hp) | Out-Null; $alive = ($hp -gt 0 -and [bool](Get-Process -Id $hp -ErrorAction SilentlyContinue)) }
    $sf = Join-Path $q 'host.state.json'
    if (Test-Path -LiteralPath $sf) { try { $st = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json; $beatAge = [math]::Round(((Get-Date) - [datetime]$st.beat).TotalSeconds) } catch { } }
    $stale = ($null -eq $beatAge) -or ($beatAge -gt 120)
    $desc = "queued_jobs=$jobs independent_running=$ind pid_alive=$alive beat_age=$(if ($null -eq $beatAge) { '-' } else { "${beatAge}s" })"
    if ($alive -and -not $stale) { "HOST up $desc"; return }
    if ($jobs -eq 0 -and $ind -eq 0) { "HOST idle-down $desc (nothing to run; spawn-wp-session.ps1 starts it on demand)"; return }
    if ($DryRun) { "HOST down-would-restart $desc"; return }
    if ($alive) { try { Stop-Process -Id $hp -Force -ErrorAction SilentlyContinue } catch { } }   # stale daemon: replace it (singleton check is by pid file)
    Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'agent-host.ps1')`"") | Out-Null
    "HOST down-restarted $desc"
} catch { "HOST check failed open: $($_.Exception.Message)" }
