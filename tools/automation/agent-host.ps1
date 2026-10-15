# agent-host.ps1 [-Once] : hidden AGENT-HOST daemon (Shay 2026-10-15: no visible agent windows).
# A coordinator never owns agent processes: spawn-wp-session.ps1 writes agents\<name>.launch.ps1 + session.json and drops
# C:\KenshiTestRuns\agent-queue\<name>.job ({name, launcher, session_json, program, wp}); this daemon launches each job HIDDEN
# (`claude -p`, output in agents\out\<name>.log), so agents are children of the daemon, not of the coordinator, and survive its handoff.
# - singleton (agent-host.pid + live check), started hidden by spawn-wp-session.ps1 (Start-Process -WindowStyle Hidden), same pattern as coord-supervisor
# - max 4 concurrent agents (live launcher processes); extra jobs wait in the queue
# - relaunches nothing on its own; an agent that exits without a terminal status is marked FAILED by its launcher (see spawn-wp-session.ps1)
# - state: agent-queue\host.state.json (heartbeat, live count, last launches); jobs moved to agent-queue\started\
param([switch]$Once, [int]$IntervalSec = 2, [int]$Max = 4)
$ErrorActionPreference = 'Continue'
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$here = $PSScriptRoot
$q = Join-Path $runs 'agent-queue'
New-Item -ItemType Directory -Force -Path $q, (Join-Path $q 'started') | Out-Null
$pidF = Join-Path $q 'agent-host.pid'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $Once) {
    if (Test-Path -LiteralPath $pidF) {
        $old = 0; [int]::TryParse((Get-Content -LiteralPath $pidF -Raw).Trim(), [ref]$old) | Out-Null
        if ($old -gt 0 -and $old -ne $PID -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) { "agent-host already running pid $old"; return }
    }
    [IO.File]::WriteAllText($pidF, "$PID", $utf8)
}

function Get-LiveLaunchers {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '\.launch\.ps1' })
}

function Start-Job1($jobFile) {
    $job = Get-Content -LiteralPath $jobFile -Raw | ConvertFrom-Json
    $sessJson = $job.session_json
    $proc = Start-Process -FilePath 'powershell.exe' -WorkingDirectory $job.workdir -WindowStyle Hidden -PassThru -ErrorAction Stop `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($job.launcher)`"")
    $cp = 0; $cstart = ''
    for ($i = 0; $i -lt 80 -and -not $cp; $i++) {
        Start-Sleep -Milliseconds 500
        $kid = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(claude|node)\.exe$' })
        if ($kid.Count) { $cp = [int]$kid[0].ProcessId; try { $cstart = (Get-Process -Id $cp).StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') } catch { } }
        if ($proc.HasExited) { break }
    }
    try {
        $s = Get-Content -LiteralPath $sessJson -Raw | ConvertFrom-Json
        $s.launcher_pid = $proc.Id
        try { $s.launcher_start = $proc.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') } catch { }
        $s.claude_pid = $cp; $s.claude_start = $cstart
        $s | Add-Member -NotePropertyName host_pid -NotePropertyValue $PID -Force
        [IO.File]::WriteAllText($sessJson, ($s | ConvertTo-Json -Depth 6), $utf8)
    } catch { }
    if ($job.program) {
        try {
            $la = @('session', $job.program, $job.wp, $job.name, "$($proc.Id)"); if ($cp -gt 0) { $la += "$cp" }
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'program-ledger.ps1') @la | Out-Null
        } catch { }
    }
    Move-Item -LiteralPath $jobFile -Destination (Join-Path $q 'started') -Force
    return "$($job.name) launcher=$($proc.Id) claude=$cp"
}

$last = @()
do {
    $jobs = @(Get-ChildItem -LiteralPath $q -Filter '*.job' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    $live = (Get-LiveLaunchers).Count
    foreach ($j in $jobs) {
        if ($live -ge $Max) { break }
        try { $last += (Start-Job1 $j.FullName); $live++ }
        catch { $last += "FAILED $($j.Name): $($_.Exception.Message)"; Move-Item -LiteralPath $j.FullName -Destination (Join-Path $q 'started') -Force -ErrorAction SilentlyContinue }
    }
    if ($last.Count -gt 10) { $last = $last[-10..-1] }
    $st = [ordered]@{ pid = $PID; beat = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'); live = $live; queued = (@(Get-ChildItem -LiteralPath $q -Filter '*.job' -ErrorAction SilentlyContinue)).Count; max = $Max; last = $last }
    [IO.File]::WriteAllText((Join-Path $q 'host.state.json'), ($st | ConvertTo-Json -Depth 4), $utf8)
    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSec
} while ($true)
