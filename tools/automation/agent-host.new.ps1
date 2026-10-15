# agent-host.ps1 [-Once] : hidden AGENT-HOST daemon (Shay 2026-10-15: no visible agent windows).
# A coordinator never owns agent processes: spawn-wp-session.ps1 writes agents\<name>.launch.ps1 + session.json and drops
# C:\KenshiTestRuns\agent-queue\<name>.job ({name, launcher, session_json, program, wp}); this daemon launches each job HIDDEN
# (`claude -p`, output in agents\out\<name>.log), so agents are children of the daemon, not of the coordinator, and survive its handoff.
# - singleton (agent-host.pid + live check), started hidden by spawn-wp-session.ps1 (Start-Process -WindowStyle Hidden), same pattern as coord-supervisor
# - max 4 concurrent agents (live launcher processes); extra jobs wait in the queue
# - relaunches nothing on its own; an agent that exits without a terminal status is marked FAILED by its launcher (see spawn-wp-session.ps1)
# - MONITOR (every 30 s, -MonitorOnce for selftests): per RUNNING agent: process gone -> FAILED + respawn todo + wake; status AND log silent > StallMin (10) -> 'AGENT STALL' wake;
#   > KillMin (20) -> kill the process tree, FAILED + respawn todo + wake; wall clock > WallMin (90, job field max_min overrides) -> kill, STOPPED-CONTEXT; RUNNING status with no
#   session (INPROC/orphan) silent > StallMin -> 'AGENT ORPHANED' wake. Wakes = a .msg in inbox\coordinator\ (event-wait.sh INBOX). Roll call: agent-rollcall.ps1.
# - quiet wakes: the ORPHANED/STALL wakes count the newest file under the status `outputs:` dirs as activity (agent-rollcall LogAgeMin); a working agent never wakes the coordinator. agent-rollcall.ps1 is
#   re-dot-sourced on change every monitor tick (live reload); agent-host-reload.ps1 restarts only the daemon (launchers keep running) to pick up a changed agent-host.ps1.
# - state: agent-queue\host.state.json (heartbeat, live count, last launches); jobs moved to agent-queue\started\
param([switch]$Once, [switch]$MonitorOnce, [int]$IntervalSec = 2, [int]$Max = 4, [int]$MonitorSec = 30,
      [int]$StallMin = 10, [int]$KillMin = 20, [int]$WallMin = 90)
$ErrorActionPreference = 'Continue'
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$here = $PSScriptRoot
$q = Join-Path $runs 'agent-queue'
New-Item -ItemType Directory -Force -Path $q, (Join-Path $q 'started') | Out-Null
$pidF = Join-Path $q 'agent-host.pid'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $Once -and -not $MonitorOnce) {
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

$rcFile = Join-Path $here 'agent-rollcall.ps1'
. $rcFile
$rcStamp = (Get-Item -LiteralPath $rcFile).LastWriteTimeUtc.Ticks
# live reload (agent-host-reload task): the loop below re-dot-sources agent-rollcall.ps1 (at script scope, so the functions replace the old ones) when the file changed; edits apply without a daemon restart.
$flagDir = Join-Path $q 'flags'
New-Item -ItemType Directory -Force -Path $flagDir | Out-Null

function Send-Wake([string]$name, [string]$text) {
    $d = Join-Path $runs 'inbox\coordinator'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    [IO.File]::WriteAllText((Join-Path $d ("{0}-{1}.msg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $name)), $text, $utf8)
}
function Log-Tail([string]$name) {
    $lf = Join-Path $runs "agents\out\$name.log"
    if (-not (Test-Path -LiteralPath $lf)) { return '(no log)' }
    $t = @(Get-Content -LiteralPath $lf -Tail 3 -ErrorAction SilentlyContinue | ForEach-Object { $x = "$_" -replace '[^\x20-\x7E]', ''; if ($x.Length -gt 160) { $x.Substring(0, 160) } else { $x } })
    return ($t -join ' // ')
}
function Set-AgentTerminal([string]$name, [string]$state, [string]$why) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-status.ps1') $name $state "agent-host monitor" $why '' 'coordinator: respawn a fresh successor from the handoff/status' | Out-Null
    if ($state -eq 'FAILED') {
        try {
            $td = Join-Path $runs 'respawn'; New-Item -ItemType Directory -Force -Path $td | Out-Null
            $ho = Join-Path $runs "agents\$name.handoff.md"
            [IO.File]::WriteAllText((Join-Path $td "$name.todo"), ("name: $name`
written: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`
task: (agent-host: $why)`
handoff: $(if (Test-Path -LiteralPath $ho) { $ho } else { '(none written: use the status file)' })`
status: $(Join-Path $runs "agents\$name.status")`
next: respawn a FRESH successor with spawn-wp-session.ps1 (same brief + 'continue from the status/handoff')`
"), $utf8)
        } catch { }
    }
}
function Invoke-Monitor {
    foreach ($a in @(Get-AgentRoll)) {
        $n = $a.Name
        $fStall = Join-Path $flagDir "$n.stall"
        if ($a.Kind -eq 'INPROC') {
            # evidence counts (LogAgeMin includes the newest file under the status `outputs:` dirs): a fresh evidence dir = a working agent, no wake
            $evQuiet = ($null -eq $a.LogAgeMin) -or ($a.LogAgeMin -gt $StallMin)
            if ($a.StatusAgeMin -gt $StallMin -and $evQuiet -and -not (Test-Path -LiteralPath (Join-Path $flagDir "$n.orphan"))) {
                'x' | Set-Content (Join-Path $flagDir "$n.orphan")
                Send-Wake $n "AGENT ORPHANED $n : status RUNNING, no session/process known to the agent-host, silent $($a.StatusAgeMin) min. Latest: $($a.Latest). Respawn it (spawn-wp-session.ps1) or agent-abandon.ps1."
            } elseif ($a.StatusAgeMin -le $StallMin -or -not $evQuiet) { Remove-Item (Join-Path $flagDir "$n.orphan") -ErrorAction SilentlyContinue }
            continue
        }
        # launching grace: no pid recorded yet and started < 2 min ago
        if ($a.LauncherPid -le 0 -and $a.StartedAgeMin -ne $null -and $a.StartedAgeMin -lt 2) { continue }
        if (-not $a.Alive) {
            Set-AgentTerminal $n 'FAILED' "process gone without a terminal status (launcher $($a.LauncherPid), claude $($a.ClaudePid)); log tail: $(Log-Tail $n)"
            Send-Wake $n "AGENT DEAD $n : process gone while status was RUNNING (status age $($a.StatusAgeMin) min). Marked FAILED, respawn todo written. Log: $(Log-Tail $n)"
            continue
        }
        $wall = $WallMin
        $jf = Join-Path $q "started\$n.job"
        if (Test-Path -LiteralPath $jf) { try { $jj = Get-Content -LiteralPath $jf -Raw | ConvertFrom-Json; if ($jj.max_min) { $wall = [int]$jj.max_min } } catch { } }
        if ($a.StartedAgeMin -ne $null -and $a.StartedAgeMin -gt $wall) {
            & taskkill /PID $a.LauncherPid /T /F 2>&1 | Out-Null
            Set-AgentTerminal $n 'STOPPED-CONTEXT' "wall-clock limit $wall min reached; killed by agent-host. Successor continues from its handoff."
            Send-Wake $n "AGENT WALL-CLOCK $n : ran $($a.StartedAgeMin) min (limit $wall), killed, marked STOPPED-CONTEXT with respawn todo."
            continue
        }
        $logQuiet = ($null -eq $a.LogAgeMin) -or ($a.LogAgeMin -gt $StallMin)
        $silent = [math]::Max($a.StatusAgeMin, $(if ($null -eq $a.LogAgeMin) { $a.StatusAgeMin } else { $a.LogAgeMin }))
        $silentMin = [math]::Min($a.StatusAgeMin, $(if ($null -eq $a.LogAgeMin) { $a.StatusAgeMin } else { $a.LogAgeMin }))
        if ($a.StatusAgeMin -gt $StallMin -and $logQuiet) {
            if ($silentMin -gt $KillMin) {
                & taskkill /PID $a.LauncherPid /T /F 2>&1 | Out-Null
                Set-AgentTerminal $n 'FAILED' "stalled > $KillMin min (status $($a.StatusAgeMin) min, log $($a.LogAgeMin) min); killed by agent-host. Log: $(Log-Tail $n)"
                Send-Wake $n "AGENT KILLED $n : stalled $silentMin min (status+log), process tree killed, marked FAILED with respawn todo. Log: $(Log-Tail $n)"
                Remove-Item $fStall -ErrorAction SilentlyContinue
            } elseif (-not (Test-Path -LiteralPath $fStall)) {
                'x' | Set-Content $fStall
                Send-Wake $n "AGENT STALL $n : $silentMin min with no status heartbeat (status $($a.StatusAgeMin) m, log $(if ($null -eq $a.LogAgeMin) { '-' } else { $a.LogAgeMin }) m). Latest: $($a.Latest). Log: $(Log-Tail $n). Auto-kill at $KillMin min."
            }
        } else { Remove-Item $fStall -ErrorAction SilentlyContinue }
    }
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
$nextMon = Get-Date
if ($MonitorOnce) { Invoke-Monitor; return }
do {
    if ((Get-Date) -ge $nextMon) {
        try { $t = (Get-Item -LiteralPath $rcFile -ErrorAction Stop).LastWriteTimeUtc.Ticks; if ($t -ne $rcStamp) { $rcStamp = $t; . $rcFile } }
        catch { $last += "ROLLCALL RELOAD ERROR (kept previous functions): $($_.Exception.Message)" }
        try { Invoke-Monitor } catch { $last += "MONITOR ERROR: $($_.Exception.Message)" }; $nextMon = (Get-Date).AddSeconds($MonitorSec) }
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
