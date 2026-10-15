# agent-host-reload.ps1 [-DryRun] [-Force] [-HostScript <path>] : restart ONLY the hidden agent-host daemon (monitor loop) so it loads a changed agent-host.ps1 / agent-rollcall.ps1.
# Why this is safe (Shay 2026-10-15, running hidden agents must not die): the agents are the daemon's CHILD processes (launcher -> claude), but Windows does not kill children when a parent
# exits and this script stops the daemon pid ONLY (Stop-Process, never taskkill /T). The monitor reads status/session.json, not the parent link, so the new daemon adopts the running agents.
# Guards: refuses while queued *.job files exist (the daemon may be mid-launch and would lose the session.json update) unless -Force; verifies every launcher that was alive before is alive after.
# Without this script the same effect is partial: the daemon re-dot-sources agent-rollcall.ps1 on change every monitor tick (agent-host.ps1 of 2026-10-15 or later), so rollcall edits need no restart at all.
# Prints one line: RELOAD ok|dry-run|refused|failed ... Exit 0 ok/dry-run, 2 refused, 1 failed. Test switch: KAH_RUNS_DIR.
param([switch]$DryRun, [switch]$Force, [string]$HostScript = '')
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
if (-not $HostScript) { $HostScript = Join-Path $PSScriptRoot 'agent-host.ps1' }
$q = Join-Path $runs 'agent-queue'
$pf = Join-Path $q 'agent-host.pid'
$sf = Join-Path $q 'host.state.json'
function Get-Launchers { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match '\.launch\.ps1' }) }
try {
    $old = 0
    if (Test-Path -LiteralPath $pf) { [int]::TryParse((Get-Content -LiteralPath $pf -Raw).Trim(), [ref]$old) | Out-Null }
    $oldAlive = ($old -gt 0 -and [bool](Get-Process -Id $old -ErrorAction SilentlyContinue))
    $jobs = @(Get-ChildItem -LiteralPath $q -Filter '*.job' -File -ErrorAction SilentlyContinue).Count
    $kids = @(Get-Launchers | Where-Object { $oldAlive -and $_.ParentProcessId -eq $old })
    $kidIds = @($kids | ForEach-Object { [int]$_.ProcessId })
    $desc = "old_pid=$old alive=$oldAlive queued_jobs=$jobs launcher_children=$($kidIds.Count) [$($kidIds -join ',')]"
    if ($jobs -gt 0 -and -not $Force) { "RELOAD refused $desc (jobs queued: the daemon may be mid-launch; retry in a minute or use -Force)"; exit 2 }
    if ($DryRun) { "RELOAD dry-run $desc : would stop only pid $old (children keep running) and start a hidden daemon from $HostScript"; exit 0 }
    if ($oldAlive) { Stop-Process -Id $old -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
    Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
    $np = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$HostScript`"")
    $new = 0; $beat = $false
    for ($i = 0; $i -lt 40 -and -not $beat; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-Path -LiteralPath $pf) { [int]::TryParse((Get-Content -LiteralPath $pf -Raw).Trim(), [ref]$new) | Out-Null }
        if ($new -gt 0 -and $new -ne $old -and (Test-Path -LiteralPath $sf)) {
            try { $beat = (((Get-Date) - [datetime](Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json).beat).TotalSeconds -lt 15 -and (Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json).pid -eq $new) } catch { }
        }
    }
    $kept = @($kidIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    if (-not $beat) { "RELOAD failed $desc : new daemon (pid $($np.Id)) did not write a fresh heartbeat in 20 s; launchers kept $($kept.Count)/$($kidIds.Count)"; exit 1 }
    "RELOAD ok $desc -> new_pid=$new, launchers kept $($kept.Count)/$($kidIds.Count)"
    if ($kept.Count -ne $kidIds.Count) { exit 1 }
    exit 0
} catch { "RELOAD failed: $($_.Exception.Message)"; exit 1 }
