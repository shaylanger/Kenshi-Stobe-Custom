# coord-supervisor.ps1: notices when the COORDINATOR session ended without a handoff and its programs/agents are orphaned.
# 2026-10-15: the coordinator died at 12:45 and nothing noticed until 14:20. Fails OPEN everywhere (any missing/malformed input =
# do nothing, log it); never touches settings, hooks or CLAUDE.md.
#
# Inputs (all under C:\KenshiTestRuns, override with env KCS_RUNS or -Root)
#   coordinator.heartbeat   "<epoch> <session> <iso>" written by coord-heartbeat.ps1 (PostToolUse hook + event-wait.sh)
#   handoff.ready           fresh (< 30 min) = a proper handoff happened, a new session is about to start: never relaunch
#   programs\*.json         program ledgers {name, wps:[{id, items, state todo|running|stopped|done|blocked, agent, handoff, ...}]}
#   agents\*.status         agent status files (first line "name | STATE | date"); inflight\ markers; supervisor.autolaunch flag
# Decision (every IntervalSec, default 60 s)
#   1. heartbeat absent/unparseable -> nothing (hook not installed yet). Heartbeat younger than 10 min -> nothing, and a
#      previous COORDINATOR-SUPERVISOR alert is removed.
#   2. heartbeat stale > 10 min (coordinator presumed dead; its subagents die with it): every agents\*.status that says RUNNING,
#      is older than 30 min, has no inflight marker touched in the last 30 min that names the agent (marker name or content
#      contains the agent name, or the status text names the marker) and no live process whose command line contains the agent
#      name is rewritten to STOPPED-CONTEXT via agent-status.ps1 (task/outputs/next kept) and its ledger wp (state running) is set to
#      state=stopped. (Deliberately only while the heartbeat is stale: a live coordinator owns its own agents.)
#   3. handoff.ready younger than 30 min -> nothing (new session expected).
#   4. any program with a wp in todo/stopped/running -> the coordinator must be relaunched:
#        - rate limit: max 3 relaunches per rolling hour, backoff gap 15 min * 2^(n-1) after the n-th (15, 30, 60 min);
#          limit hit -> ALERT only.  After the 2nd relaunch within the hour an ALERT is written as well.
#        - AUTO-LAUNCH IS OFF BY DEFAULT: it launches only when C:\KenshiTestRuns\supervisor.autolaunch exists (Shay must create it;
#          `coord-supervisor.ps1 -Autolaunch on|off` does that). Without it: write ALERT-coordinator.txt + log "WOULD LAUNCH".
#        - launch = new PowerShell window running `claude '<prompt>' --add-dir ...`, the same mechanism as the context-meter
#          `handoff` command (CLAUDE* env markers dropped so the child session saves transcripts), prompt: run session-start.ps1,
#          resume program(s) <names> from the ledger, respawn stopped/orphaned agents.
#   ALERT-coordinator.txt: session-start prints it, rig-health.sh and the Stop hook block on ALERT-*.txt, so a live coordinator
#   cannot miss it. No relay-message mechanism exists in tools/automation (agents use SendMessage inside Claude); the ALERT is
#   the notification. State: supervisor\coord-supervisor.state.json (launch times), log supervisor\coord-supervisor.log.
# Tail sessions (overlap handoff, docs/TAIL_HANDOFF_CONTRACT.md; flags runs\tail\<session>.flag, tail-mode.ps1):
#   - every pass lists them (log + -Status). A tail whose claude process is gone while it still owns unfinished/unacknowledged agents is DEAD:
#     those agents died with it, so their RUNNING statuses are rewritten to STOPPED-CONTEXT at once (ledger wp -> stopped) and
#     ALERT-tail-dead.txt names them (respawn from checkpoints; then `tail-mode.ps1 leave -Session <id> -Force` clears it).
#   - agents owned by a LIVE tail are never marked orphaned, and while a live tail still owns agents NO new coordinator is auto-launched.
# Usage
#   coord-supervisor.ps1 -Ensure          start ONE hidden background loop (like rig-runner -Ensure); call from session-start
#   coord-supervisor.ps1 -Loop            the loop itself (hidden); -Stop kills it
#   coord-supervisor.ps1 -Once            one pass (what the loop runs); -Status read-only report; -Autolaunch on|off|status
#   coord-supervisor.ps1 -Selftest        fake clock + temp dirs + stub launcher (never opens a terminal, never touches real files)
param(
    [switch]$Ensure, [switch]$Loop, [switch]$Once, [switch]$Stop, [switch]$Status, [switch]$Selftest,
    [string]$Autolaunch = '',
    [string]$Root = '',
    [string]$ProjectDir = 'C:\KenshiModding',
    [int]$IntervalSec = 60
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = if ($env:KCS_RUNS) { $env:KCS_RUNS } else { 'C:\KenshiTestRuns' } }
. (Join-Path $PSScriptRoot 'tail-mode.ps1')   # tail-session helpers (functions only; its param block uses names this script does not)

$HB_STALE = 600; $AGENT_STALE = 1800; $HANDOFF_FRESH = 1800; $HOUR = 3600; $MAX_LAUNCH = 3; $BASE_GAP = 900
$ALERT_MARK = 'COORDINATOR-SUPERVISOR ALERT'

function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function To-Epoch([datetime]$d) { ([DateTimeOffset]$d.ToUniversalTime()).ToUnixTimeSeconds() }
function Stamp([int64]$e) { [DateTimeOffset]::FromUnixTimeSeconds($e).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') }

function Log([hashtable]$c, [string]$m) {
    $line = "$(Stamp $c.Now) $m"
    $c.Log.Add($line) | Out-Null
    # the loop repeats the same verdict every minute: write a message to the log file only when it changed (digits ignored)
    $key = $m -replace '\d+', '#'
    if ($script:lastLogKey -eq $key) { return }
    $script:lastLogKey = $key
    try {
        $dir = Join-Path $c.Root 'supervisor'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $f = Join-Path $dir 'coord-supervisor.log'
        if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).Length -gt 512KB) {
            $tail = Get-Content -LiteralPath $f -Tail 300; Set-Content -LiteralPath $f -Value $tail -Encoding UTF8
        }
        Add-Content -LiteralPath $f -Value $line -Encoding UTF8
    } catch {}
}

function Read-Heartbeat([string]$root) {
    $p = Join-Path $root 'coordinator.heartbeat'
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    try {
        $t = (Get-Content -LiteralPath $p -Raw -ErrorAction Stop).Trim() -split '\s+'
        if ($t[0] -match '^\d+$') { return @{ Epoch = [int64]$t[0]; Session = $(if ($t.Count -ge 2) { $t[1] } else { '' }) } }
    } catch {}
    return $null
}

# Program ledgers. Returns @{ Active = @(@{Name;Path;Wps}) ; Files = @(all parsed) ; Bad = @(paths) }
function Read-Programs([hashtable]$c) {
    $res = @{ Active = @(); All = @(); Bad = @() }
    $dir = Join-Path $c.Root 'programs'
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        try {
            $j = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $wps = @()
            if ($j -and $j.wps) { $wps = @($j.wps) }
            $name = if ($j -and $j.name) { "$($j.name)" } else { $f.BaseName }
            $rec = @{ Name = $name; Path = $f.FullName; Json = $j; Wps = $wps }
            $res.All += , $rec
            $open = @($wps | Where-Object { $_ -and "$($_.state)" -match '^(?i)(todo|stopped|running)$' })
            if ($open.Count) { $res.Active += , $rec }
        } catch { $res.Bad += $f.FullName }
    }
    return $res
}

function Save-Ledger([hashtable]$rec) {
    $tmp = "$($rec.Path).$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($rec.Json | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $rec.Path -Force
}

function Get-State([hashtable]$c) {
    $p = Join-Path $c.Root 'supervisor\coord-supervisor.state.json'
    try {
        if (Test-Path -LiteralPath $p) {
            $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
            return @(@($j.launches) | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int64]$_ })
        }
    } catch {}
    return @()
}
function Save-State([hashtable]$c, [int64[]]$launches) {
    $dir = Join-Path $c.Root 'supervisor'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $json = '{"launches":[' + (($launches | ForEach-Object { "$_" }) -join ',') + ']}'
    [IO.File]::WriteAllText((Join-Path $dir 'coord-supervisor.state.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Write-Alert([hashtable]$c, [string[]]$lines) {
    $f = Join-Path $c.Root 'ALERT-coordinator.txt'
    $txt = @("$ALERT_MARK $(Stamp $c.Now)") + $lines
    Set-Content -LiteralPath $f -Value $txt -Encoding UTF8
    $c.Alerts.Add(($lines -join ' | ')) | Out-Null
}
function Clear-Alert([hashtable]$c) {
    $f = Join-Path $c.Root 'ALERT-coordinator.txt'
    if (Test-Path -LiteralPath $f) {
        $first = Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction SilentlyContinue
        if ("$first" -like "*$ALERT_MARK*") { Remove-Item -LiteralPath $f -Force; Log $c 'heartbeat fresh again: alert cleared' }
    }
}

# ---- tail sessions (overlap handoff) ----
$TAIL_ALERT_MARK = 'TAIL-SUPERVISOR ALERT'
# @{ Live = tails with the agents they still own; Dead = tails whose process is gone and that still own unfinished/unacked agents; LiveAgents/DeadAgents = names }
function Get-TailInfo([hashtable]$c) {
    $i = @{ Live = @(); Dead = @(); LiveAgents = @(); DeadAgents = @() }
    try {
        foreach ($f in (Get-TailFlags $c.Root)) {
            $pend = @(Get-TailAgentSet $c.Root $f | Where-Object { $_.Pending })
            if ($f.Alive) {
                $i.Live += , @{ Flag = $f; Agents = $pend }
                $i.LiveAgents += @($pend | ForEach-Object { $_.Agent })
            } elseif ($pend.Count) {
                $i.Dead += , @{ Flag = $f; Agents = $pend }
                $i.DeadAgents += @($pend | ForEach-Object { $_.Agent })
            }
        }
    } catch { Log $c "tail scan failed (fail open): $($_.Exception.Message)" }
    return $i
}

function Invoke-TailPass([hashtable]$c) {
    $ti = Get-TailInfo $c
    $c.Tails = $ti
    foreach ($t in $ti.Live) { Log $c "tail session $($t.Flag.Session) LIVE (pid $($t.Flag.Pid)) owns: $(if ($t.Agents.Count) { ($t.Agents | ForEach-Object Agent) -join ', ' } else { 'nothing pending' })" }
    $af = Join-Path $c.Root 'ALERT-tail-dead.txt'
    if (-not $ti.Dead.Count) {
        if ((Test-Path -LiteralPath $af) -and "$(Get-Content -LiteralPath $af -TotalCount 1)" -like "*$TAIL_ALERT_MARK*") { Remove-Item -LiteralPath $af -Force; Log $c 'no dead tail sessions left: alert cleared' }
        return
    }
    $dir = Join-Path $c.Root 'agents'
    $marked = @()
    $lines = @()
    foreach ($t in $ti.Dead) {
        $names = @($t.Agents | ForEach-Object Agent)
        $lines += "tail session $($t.Flag.Session) (pid $($t.Flag.Pid)) is DEAD and its agents died with it: $($names -join ', '). Respawn each as a FRESH agent from its checkpoint/handoff (names wpA -> wpA2), then: powershell -NoProfile -File C:\KenshiModding\tools\automation\tail-mode.ps1 leave -Session $($t.Flag.Session) -Force"
        foreach ($n in $names) {
            try {
                $sf = Join-Path $dir "$n.status"
                if (-not (Test-Path -LiteralPath $sf)) { continue }
                $l = @(Get-Content -LiteralPath $sf -ErrorAction Stop)
                $head = "$($l[0])".TrimStart([char]0xFEFF) -split '\s*\|\s*'
                if ($head.Count -lt 2 -or $head[1].Trim() -ne 'RUNNING') { continue }
                $get = { param($p) $x = $l | Where-Object { $_ -like "$($p):*" } | Select-Object -First 1; if ($x) { ("$x" -replace "^$($p):\s*", '') } else { '' } }
                & $c.StatusWriter $n 'STOPPED-CONTEXT' (& $get 'task') "ORPHANED: tail session $($t.Flag.Session) is dead; marked STOPPED-CONTEXT by coord-supervisor. Was: $(& $get 'latest')" (& $get 'outputs') (& $get 'next')
                $marked += $n
                Log $c "agent $n marked STOPPED-CONTEXT (dead tail $($t.Flag.Session))"
            } catch { Log $c "dead-tail agent $n mark failed: $($_.Exception.Message)" }
        }
    }
    if ($marked.Count) {
        $programs = Read-Programs $c
        foreach ($rec in $programs.All) {
            $changed = $false
            foreach ($w in $rec.Wps) { if ($w -and $marked -contains "$($w.agent)" -and "$($w.state)" -ieq 'running') { $w.state = 'stopped'; $changed = $true } }
            if ($changed) { try { Save-Ledger $rec } catch { Log $c "ledger write failed $($rec.Path): $($_.Exception.Message)" } }
        }
    }
    $txt = @("$TAIL_ALERT_MARK $(Stamp $c.Now)") + $lines
    Set-Content -LiteralPath $af -Value $txt -Encoding UTF8
    $c.Alerts.Add(($lines -join ' | ')) | Out-Null
}

# ---- launch ----
function New-LaunchSpec([string]$projectDir, [string]$handoffDir, [string[]]$programs, [int]$n, [int64]$now) {
    $names = ($programs -join ', ')
    $prompt = "The previous coordinator session ended without a handoff (supervisor relaunch $n, $(Stamp $now)). " +
        "Run powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\session-start.ps1 first. " +
        "Then resume program(s) $names from the ledger in C:\KenshiTestRuns\programs\ (state todo/stopped/running work packages), " +
        "respawn stopped or orphaned agents (STOPPED-CONTEXT or stale RUNNING status files) as fresh agents pointed at their status files, " +
        "and update testing/HANDOFF.md Right now."
    $prompt = $prompt -replace "'", "''"
    $addDir = $handoffDir -replace "'", "''"
    return @{
        WorkingDirectory = $projectDir
        ArgumentList     = @('-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', "claude '$prompt' --add-dir '$addDir'")
        Prompt           = $prompt
    }
}
function Start-RealLaunch([hashtable]$spec) {
    # same mechanism as context-meter.ps1 `handoff` (HANDOFF_MODE terminal): drop CLAUDE* session markers inherited from the
    # session that started this loop (unless set at User/Machine level), then open a new PowerShell window.
    Get-ChildItem Env: | Where-Object { $_.Name -like 'CLAUDE*' -and -not [Environment]::GetEnvironmentVariable($_.Name, 'User') -and -not [Environment]::GetEnvironmentVariable($_.Name, 'Machine') } |
        ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" -ErrorAction SilentlyContinue }
    Start-Process (Get-Process -Id $PID).Path -WorkingDirectory $spec.WorkingDirectory -WindowStyle Normal -ErrorAction Stop -ArgumentList $spec.ArgumentList
}

# ---- orphaned agents ----
function Real-StatusWriter([string]$name, [string]$state, [string]$task, [string]$step, [string]$outputs, [string]$next) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'agent-status.ps1') $name $state $task $step $outputs $next | Out-Null
}
function Real-ProcessProbe([string]$agent) {
    try {
        $hit = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -like "*$agent*" -and $_.CommandLine -notlike '*coord-supervisor*' })
        return ($hit.Count -gt 0)
    } catch { return $true }   # cannot tell -> assume alive (fail open = do not touch)
}

function Mark-Orphans([hashtable]$c, $programs) {
    $dir = Join-Path $c.Root 'agents'
    $marked = @()
    $markers = @(Get-ChildItem -LiteralPath (Join-Path $c.Root 'inflight') -File -ErrorAction SilentlyContinue |
        Where-Object { ($c.Now - (To-Epoch $_.LastWriteTime)) -lt $AGENT_STALE })
    $markerText = @{}
    foreach ($m in $markers) { $markerText[$m.Name] = ("$($m.Name) " + (Get-Content -LiteralPath $m.FullName -Raw -ErrorAction SilentlyContinue)).ToLowerInvariant() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.status' -File -ErrorAction SilentlyContinue)) {
        try {
            $lines = @(Get-Content -LiteralPath $f.FullName -ErrorAction Stop)
            if (-not $lines.Count) { continue }
            $head = "$($lines[0])".TrimStart([char]0xFEFF) -split '\s*\|\s*'
            if ($head.Count -lt 2 -or $head[1].Trim() -ne 'RUNNING') { continue }
            $name = $head[0].Trim()
            if (-not $name -or $name -eq 'coord-supervisor') { continue }
            $age = $c.Now - (To-Epoch $f.LastWriteTime)
            if ($age -le $AGENT_STALE) { continue }
            if ($c.Tails -and @($c.Tails.LiveAgents) -contains $name) { Log $c "agent $name stale $([int]($age/60)) min but a LIVE tail session owns it: left RUNNING"; continue }
            $low = $name.ToLowerInvariant()
            $statusText = ($lines -join ' ').ToLowerInvariant()
            $protected = $false
            foreach ($k in $markerText.Keys) {
                if ($markerText[$k].Contains($low) -or $statusText.Contains($k.ToLowerInvariant())) { $protected = $true; break }
            }
            if ($protected) { Log $c "agent $name stale $([int]($age/60)) min but a fresh inflight marker names it: left RUNNING"; continue }
            if (& $c.ProcessProbe $name) { Log $c "agent $name stale but a live process mentions it: left RUNNING"; continue }
            $get = { param($p) $l = $lines | Where-Object { $_ -like "$($p):*" } | Select-Object -First 1; if ($l) { ("$l" -replace "^$($p):\s*", '') } else { '' } }
            $task = & $get 'task'; $latest = & $get 'latest'; $outputs = & $get 'outputs'; $next = & $get 'next'
            $step = "ORPHANED: coordinator heartbeat stale, no update since $(Stamp (To-Epoch $f.LastWriteTime)); marked STOPPED-CONTEXT by coord-supervisor. Was: $latest"
            & $c.StatusWriter $name 'STOPPED-CONTEXT' $task $step $outputs $next
            $marked += $name
            Log $c "agent $name marked STOPPED-CONTEXT (status $([int]($age/60)) min old)"
        } catch { Log $c "orphan check failed for $($f.Name): $($_.Exception.Message)" }
    }
    if ($marked.Count -and $programs) {
        foreach ($rec in $programs.All) {
            $changed = $false
            foreach ($w in $rec.Wps) {
                if ($w -and $marked -contains "$($w.agent)" -and "$($w.state)" -ieq 'running') {
                    $w.state = 'stopped'; $changed = $true
                    Log $c "ledger $($rec.Name): wp $($w.id) running -> stopped (agent $($w.agent))"
                }
            }
            if ($changed) { try { Save-Ledger $rec } catch { Log $c "ledger write failed $($rec.Path): $($_.Exception.Message)" } }
        }
    }
    return $marked
}

# ---- one pass ----
function Invoke-Pass([hashtable]$c) {
    $r = @{ Result = ''; Launched = $false }
    try {
        Invoke-TailPass $c
        $hb = Read-Heartbeat $c.Root
        if (-not $hb) { Log $c 'no (readable) coordinator.heartbeat: hook not installed yet, doing nothing'; $r.Result = 'no-heartbeat'; return $r }
        $hbAge = $c.Now - $hb.Epoch
        if ($hbAge -le $HB_STALE) { Clear-Alert $c; $r.Result = 'fresh'; return $r }

        $programs = Read-Programs $c
        foreach ($b in $programs.Bad) { Log $c "malformed ledger ignored: $b" }

        $marked = @(Mark-Orphans $c $programs)
        if ($marked.Count) { $programs = Read-Programs $c }   # states changed

        $hf = Join-Path $c.Root 'handoff.ready'
        if (Test-Path -LiteralPath $hf) {
            $hAge = $c.Now - (To-Epoch (Get-Item -LiteralPath $hf).LastWriteTime)
            if ($hAge -lt $HANDOFF_FRESH) { Log $c "heartbeat stale $([int]($hbAge/60)) min but handoff.ready is $([int]($hAge/60)) min old: new session expected"; $r.Result = 'handoff-fresh'; return $r }
        }
        if ($c.Tails -and @($c.Tails.LiveAgents).Count) {
            Log $c "heartbeat stale $([int]($hbAge/60)) min, but a LIVE tail session still owns agents ($((@($c.Tails.LiveAgents)) -join ', ')): no coordinator relaunch"
            $r.Result = 'tail-live'; return $r
        }
        if (-not $programs.Active.Count) { Log $c "heartbeat stale $([int]($hbAge/60)) min, no program with open work packages: nothing to resume"; $r.Result = 'no-open-work'; return $r }

        $names = @($programs.Active | ForEach-Object { $_.Name })
        $open = 0; foreach ($p in $programs.Active) { $open += @($p.Wps | Where-Object { $_ -and "$($_.state)" -match '^(?i)(todo|stopped|running)$' }).Count }
        $why = "coordinator heartbeat stale $([int]($hbAge/60)) min (session $($hb.Session)), no fresh handoff.ready, programs with open work: $($names -join ', ') ($open open wps)"

        $launches = @(Get-State $c)
        $recent = @($launches | Where-Object { ($c.Now - $_) -lt $HOUR } | Sort-Object)
        $flag = Test-Path -LiteralPath (Join-Path $c.Root 'supervisor.autolaunch')

        if ($recent.Count -ge $MAX_LAUNCH) {
            Write-Alert $c @($why, "RATE LIMIT: $($recent.Count) relaunches in the last hour, not launching again. Start a coordinator by hand: run tools\automation\session-start.ps1.")
            Log $c "rate limit hit ($($recent.Count)/h)"; $r.Result = 'rate-limited'; return $r
        }
        if ($recent.Count -ge 1) {
            $gap = $BASE_GAP * [math]::Pow(2, $recent.Count - 1)
            $since = $c.Now - $recent[-1]
            if ($since -lt $gap) {
                Log $c "backoff: last relaunch $([int]($since/60)) min ago, next allowed after $([int]($gap/60)) min"
                $r.Result = 'backoff'; return $r
            }
        }
        if (-not $flag) {
            Write-Alert $c @($why, 'WOULD LAUNCH a coordinator but auto-launch is OFF (create C:\KenshiTestRuns\supervisor.autolaunch or run coord-supervisor.ps1 -Autolaunch on). Start one by hand: run tools\automation\session-start.ps1 and resume the program ledger.')
            Log $c "WOULD LAUNCH coordinator ($why); autolaunch flag absent -> alert only"
            $r.Result = 'alert-only'; return $r
        }
        $n = $recent.Count + 1
        $spec = New-LaunchSpec $c.ProjectDir (Join-Path $c.Root 'programs') $names $n $c.Now
        & $c.Launcher $spec
        Save-State $c (@($recent) + @([int64]$c.Now))
        $c.Launched.Add($spec) | Out-Null
        $r.Launched = $true; $r.Result = 'launched'
        Log $c "LAUNCHED coordinator relaunch #$n ($why)"
        if ($n -ge 2) { Write-Alert $c @($why, "Coordinator relaunched $n times within the hour; it keeps dying. Look at the newest session and agents\*.handoff.md.") }
    } catch { Log $c "pass failed (fail open): $($_.Exception.Message)"; $r.Result = 'error' }
    return $r
}

function New-Ctx([string]$root, [int64]$now, [scriptblock]$launcher, [scriptblock]$writer, [scriptblock]$probe, [string]$projectDir) {
    return @{
        Root = $root; Now = $now; ProjectDir = $projectDir
        Launcher = $launcher; StatusWriter = $writer; ProcessProbe = $probe
        Tails = $null
        Log = (New-Object Collections.ArrayList); Alerts = (New-Object Collections.ArrayList); Launched = (New-Object Collections.ArrayList)
    }
}

# ---- process management (like rig-runner -Ensure) ----
function Get-PidFile { Join-Path $Root 'supervisor\coord-supervisor.pid' }
function Find-Loops {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^(?i:powershell|pwsh)\.exe$' -and $_.CommandLine -like '*coord-supervisor.ps1*' -and $_.CommandLine -match '(?i)\s-loop(\s|$)' })
}

# ---- selftest ----
function Invoke-Selftest {
    $script:fails = 0
    function T([bool]$ok, [string]$n) { if ($ok) { "PASS $n" } else { "FAIL $n"; $script:fails++ } }
    $base = Join-Path ([IO.Path]::GetTempPath()) ("coordsup-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $T0 = [int64]2000000000    # fake clock origin (epoch s)
    function SetMtime([string]$p, [int64]$e) { (Get-Item -LiteralPath $p).LastWriteTimeUtc = [DateTimeOffset]::FromUnixTimeSeconds($e).UtcDateTime }
    function NewEnv([string]$name) {
        $r = Join-Path $base $name
        foreach ($s in 'agents', 'inflight', 'programs', 'supervisor') { New-Item -ItemType Directory -Force -Path (Join-Path $r $s) | Out-Null }
        return $r
    }
    function Beat([string]$r, [int64]$e) { Set-Content -LiteralPath (Join-Path $r 'coordinator.heartbeat') -Value "$e sessX iso" }
    function Ledger([string]$r, [string]$file, [string]$json) { Set-Content -LiteralPath (Join-Path $r "programs\$file") -Value $json }
    $todoLedger = '{"name":"imm26","wps":[{"id":"wp1","items":"a","state":"todo","agent":"","handoff":""},{"id":"wp2","items":"b","state":"running","agent":"agentOrph","handoff":""},{"id":"wp3","state":"done"}]}'
    $script:calls = New-Object Collections.ArrayList
    $launcher = { param($s) $script:calls.Add($s) | Out-Null }
    $writer = { param($name, $state, $task, $step, $outputs, $next)
        $f = Join-Path $script:curRoot "agents\$name.status"
        Set-Content -LiteralPath $f -Value @("$name | $state | stub", "task: $task", "latest: $step", "outputs: $outputs", "next: $next") }
    $dead = { param($a) $false }
    function Run([string]$r, [int64]$now, [bool]$flagOn = $false) {
        $script:curRoot = $r; $script:calls.Clear()
        $flag = Join-Path $r 'supervisor.autolaunch'
        if ($flagOn) { Set-Content -LiteralPath $flag -Value 'on' } elseif (Test-Path $flag) { Remove-Item $flag }
        $c = New-Ctx $r $now $launcher $writer $dead 'C:\KenshiModding'
        return (Invoke-Pass $c)
    }
    try {
        # 1 fresh heartbeat -> nothing
        $r = NewEnv 'fresh'; Beat $r ($T0 - 60); Ledger $r 'imm26.json' $todoLedger
        $x = Run $r $T0 $true
        T ($x.Result -eq 'fresh' -and $script:calls.Count -eq 0 -and -not (Test-Path "$r\ALERT-coordinator.txt")) '1 fresh heartbeat: nothing'

        # 2 no heartbeat file -> nothing (fail open)
        $r = NewEnv 'nohb'; Ledger $r 'imm26.json' $todoLedger
        $x = Run $r $T0 $true
        T ($x.Result -eq 'no-heartbeat' -and $script:calls.Count -eq 0) '2 no heartbeat file: nothing'

        # 3 stale + todo wp + flag absent -> alert only
        $r = NewEnv 'alert'; Beat $r ($T0 - 700); Ledger $r 'imm26.json' $todoLedger
        $x = Run $r $T0 $false
        $al = if (Test-Path "$r\ALERT-coordinator.txt") { Get-Content "$r\ALERT-coordinator.txt" -Raw } else { '' }
        T ($x.Result -eq 'alert-only' -and $script:calls.Count -eq 0 -and $al -match 'WOULD LAUNCH' -and $al -match 'imm26' -and -not (Test-Path "$r\supervisor\coord-supervisor.state.json")) '3 stale + todo + flag absent: alert only, would launch'

        # 4 flag present -> launch recorded (stub)
        $r = NewEnv 'launch'; Beat $r ($T0 - 700); Ledger $r 'imm26.json' $todoLedger
        $x = Run $r $T0 $true
        $spec = if ($script:calls.Count) { $script:calls[0] } else { $null }
        T ($x.Result -eq 'launched' -and $script:calls.Count -eq 1 -and $spec.Prompt -match 'session-start\.ps1' -and $spec.Prompt -match 'imm26') '4 flag present: launch command recorded'
        # launch command text must parse as PowerShell and contain claude + add-dir
        $cmdText = $spec.ArgumentList[-1]
        $parsed = $false; try { [void][scriptblock]::Create($cmdText); $parsed = $true } catch {}
        T ($parsed -and $cmdText -like "claude '*' --add-dir '*'" -and $spec.WorkingDirectory -eq 'C:\KenshiModding') '4b launch command is valid PowerShell (claude <prompt> --add-dir)'
        T (-not (Test-Path "$r\ALERT-coordinator.txt")) '4c first relaunch writes no alert'

        # 5 rate limit + backoff
        $x = Run $r ($T0 + 300) $true
        T ($x.Result -eq 'backoff' -and $script:calls.Count -eq 0) '5a 5 min after 1st: backoff, no launch'
        $x = Run $r ($T0 + 960) $true   # 16 min after the 1st
        T ($x.Result -eq 'launched' -and (Test-Path "$r\ALERT-coordinator.txt")) '5b 16 min later: 2nd launch + ALERT written'
        $x = Run $r ($T0 + 960 + 1200) $true  # 20 min after the 2nd, gap is 30
        T ($x.Result -eq 'backoff') '5c 20 min after 2nd: backoff (needs 30)'
        $x = Run $r ($T0 + 960 + 1900) $true  # 31.6 min after the 2nd, still inside the hour of launch 1? T0+2860 < T0+3600
        T ($x.Result -eq 'launched') '5d 31 min after 2nd: 3rd launch'
        $x = Run $r ($T0 + 960 + 1900 + 4000 - 3000) $true   # = T0+3860: launches at T0, T0+960, T0+2860 -> first expired (>3600)? T0+3860-T0=3860 so 2 left
        T ($x.Result -ne 'rate-limited') '5e window rolls: oldest launch expires from the hour count'
        $r2 = NewEnv 'ratelimit'; Beat $r2 ($T0 - 700); Ledger $r2 'imm26.json' $todoLedger
        Save-State (@{ Root = $r2 }) @(($T0 - 3000), ($T0 - 2000), ($T0 - 1000))
        $x = Run $r2 $T0 $true
        T ($x.Result -eq 'rate-limited' -and $script:calls.Count -eq 0 -and (Get-Content "$r2\ALERT-coordinator.txt" -Raw) -match 'RATE LIMIT') '5f 3 launches in the hour: no 4th, alert'

        # 6 malformed ledger -> no crash, no launch; with a good one next to it still launches
        $r = NewEnv 'badledger'; Beat $r ($T0 - 700); Ledger $r 'broken.json' '{"name": "x", "wps": [ {'
        $x = Run $r $T0 $true
        T ($x.Result -eq 'no-open-work' -and $script:calls.Count -eq 0) '6a malformed ledger alone: no crash, no launch'
        Ledger $r 'empty.json' ''; Ledger $r 'nowps.json' '{"name":"y"}'; Ledger $r 'weird.json' '[1,2,3]'
        $x = Run $r $T0 $true
        T ($x.Result -eq 'no-open-work') '6b empty / no-wps / array ledgers tolerated'
        Ledger $r 'imm26.json' $todoLedger
        $x = Run $r $T0 $true
        T ($x.Result -eq 'launched') '6c good ledger next to malformed ones still launches'
        $r = NewEnv 'alldone'; Beat $r ($T0 - 700); Ledger $r 'p.json' '{"name":"p","wps":[{"id":"a","state":"done"},{"id":"b","state":"blocked"}]}'
        $x = Run $r $T0 $true
        T ($x.Result -eq 'no-open-work') '6d only done/blocked wps: no launch'

        # 7 handoff.ready fresh -> no launch; old -> launch
        $r = NewEnv 'handoff'; Beat $r ($T0 - 700); Ledger $r 'imm26.json' $todoLedger
        Set-Content "$r\handoff.ready" 'HANDOFF READY'; SetMtime "$r\handoff.ready" ($T0 - 600)
        $x = Run $r $T0 $true
        T ($x.Result -eq 'handoff-fresh' -and $script:calls.Count -eq 0) '7a fresh handoff.ready: no launch'
        SetMtime "$r\handoff.ready" ($T0 - 7200)
        $x = Run $r $T0 $true
        T ($x.Result -eq 'launched') '7b old handoff.ready: launch'

        # 8 orphaned agents
        $r = NewEnv 'orphan'; Beat $r ($T0 - 700); Ledger $r 'imm26.json' $todoLedger
        $mk = { param($n, $state, $age) $p = "$r\agents\$n.status"; Set-Content $p @("$n | $state | d", 'task: T', 'latest: L', 'outputs: O', 'next: N'); SetMtime $p ($T0 - $age) }
        & $mk 'agentOrph' 'RUNNING' 7200
        & $mk 'agentMarked' 'RUNNING' 7200
        & $mk 'agentFresh' 'RUNNING' 300
        & $mk 'agentDone' 'DONE' 7200
        Set-Content "$r\inflight\somebatch" 'run for agentMarked out'; SetMtime "$r\inflight\somebatch" ($T0 - 120)
        $x = Run $r $T0 $false
        $st = { param($n) (Get-Content "$r\agents\$n.status" -TotalCount 1) }
        T ((& $st 'agentOrph') -match 'STOPPED-CONTEXT') '8a stale RUNNING agent marked STOPPED-CONTEXT'
        T ((Get-Content "$r\agents\agentOrph.status" -Raw) -match 'task: T' -and (Get-Content "$r\agents\agentOrph.status" -Raw) -match 'ORPHANED') '8b task kept, latest says ORPHANED'
        T ((& $st 'agentMarked') -match 'RUNNING') '8c fresh inflight marker naming the agent protects it'
        T ((& $st 'agentFresh') -match 'RUNNING' -and (& $st 'agentDone') -match 'DONE') '8d fresh status / DONE untouched'
        $led = Get-Content "$r\programs\imm26.json" -Raw | ConvertFrom-Json
        T ((@($led.wps) | Where-Object { $_.id -eq 'wp2' }).state -eq 'stopped' -and (@($led.wps) | Where-Object { $_.id -eq 'wp1' }).state -eq 'todo') '8e ledger wp of the orphaned agent -> stopped'
        # live process probe protects
        $r = NewEnv 'orphan2'; Beat $r ($T0 - 700); & $mk 'agentOrph' 'RUNNING' 7200
        $script:curRoot = $r; $c = New-Ctx $r $T0 $launcher $writer { param($a) $true } 'C:\KenshiModding'
        [void](Mark-Orphans $c $null)
        T ((Get-Content "$r\agents\agentOrph.status" -TotalCount 1) -match 'RUNNING') '8f live process protects the agent'
        # heartbeat fresh -> agents untouched
        $r = NewEnv 'orphan3'; Beat $r ($T0 - 60); & $mk 'agentOrph' 'RUNNING' 7200
        $x = Run $r $T0 $false
        T ((Get-Content "$r\agents\agentOrph.status" -TotalCount 1) -match 'RUNNING') '8g coordinator alive: agents untouched'

        # 9 alert auto-clears when the heartbeat returns; a foreign ALERT file is kept
        $r = NewEnv 'clear'; Beat $r ($T0 - 700); Ledger $r 'imm26.json' $todoLedger
        $x = Run $r $T0 $false
        Beat $r ($T0 + 100)
        $x = Run $r ($T0 + 110) $false
        T (-not (Test-Path "$r\ALERT-coordinator.txt")) '9a alert cleared once heartbeat is fresh'
        Set-Content "$r\ALERT-coordinator.txt" 'someone else wrote this'
        $x = Run $r ($T0 + 120) $false
        T (Test-Path "$r\ALERT-coordinator.txt") '9b foreign alert file not deleted'

        # 10 tail sessions (overlap handoff): flag + pid; $PID = a live process, 2147480000 = none
        function TailFlag([string]$r, [string]$sess, [int]$cpid, [string[]]$ag) {
            New-Item -ItemType Directory -Force -Path (Join-Path $r 'tail') | Out-Null
            [IO.File]::WriteAllText((Join-Path $r "tail\$sess.flag"), ((@{ session = $sess; pid = $cpid; created = (Get-Date).AddMinutes(1).ToString('o'); agents = @($ag) }) | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        }
        function MkSt([string]$r, [string]$n, [int64]$age) { $f = "$r\agents\$n.status"; Set-Content $f @("$n | RUNNING | d", 'task: T', 'latest: L', 'outputs: O', 'next: N'); SetMtime $f ($T0 - $age) }
        $r = NewEnv 'tail-live'; Beat $r ($T0 - 700); Ledger $r 'imm26.json' $todoLedger; MkSt $r 'tA' 7200; TailFlag $r 'sLive' $PID @('tA')
        $x = Run $r $T0 $true
        T ($x.Result -eq 'tail-live' -and $script:calls.Count -eq 0) '10a live tail owning an agent: no coordinator relaunch'
        T ((Get-Content "$r\agents\tA.status" -TotalCount 1) -match 'RUNNING') '10b live tail agent not marked orphaned'
        $r = NewEnv 'tail-dead'; Beat $r ($T0 - 60); Ledger $r 'imm26.json' ('{"name":"imm26","wps":[{"id":"wp1","state":"running","agent":"tB"}]}'); MkSt $r 'tB' 60; TailFlag $r 'sDead' 2147480000 @('tB')
        $x = Run $r $T0 $false
        T ((Get-Content "$r\agents\tB.status" -TotalCount 1) -match 'STOPPED-CONTEXT') '10c dead tail: its RUNNING agent marked STOPPED-CONTEXT at once'
        T ((Test-Path "$r\ALERT-tail-dead.txt") -and ((Get-Content "$r\ALERT-tail-dead.txt" -Raw) -match 'tB' -and (Get-Content "$r\ALERT-tail-dead.txt" -Raw) -match 'sDead')) '10d dead tail alert names tail and agent'
        T (((Get-Content "$r\programs\imm26.json" -Raw | ConvertFrom-Json).wps | Where-Object { $_.id -eq 'wp1' }).state -eq 'stopped') '10e dead tail agent ledger wp -> stopped'
        Remove-Item "$r\tail\sDead.flag"
        $x = Run $r $T0 $false
        T (-not (Test-Path "$r\ALERT-tail-dead.txt")) '10f alert cleared once the dead flag is removed'
        $r = NewEnv 'tail-dead2'; Beat $r ($T0 - 60); MkSt $r 'tC' 60; TailFlag $r 'sDead2' 2147480000 @('tC')
        Set-Content "$r\ALERT-tail-dead.txt" 'foreign'; Remove-Item "$r\tail\sDead2.flag"
        $x = Run $r $T0 $false
        T (Test-Path "$r\ALERT-tail-dead.txt") '10g foreign ALERT-tail-dead.txt file not deleted'
    } finally { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
    if ($script:fails) { "SELFTEST FAILED ($script:fails)"; exit 1 } else { 'SELFTEST OK'; exit 0 }
}

# ---- main ----
if ($Selftest) { Invoke-Selftest }

if ($Autolaunch) {
    $flag = Join-Path $Root 'supervisor.autolaunch'
    switch ($Autolaunch.ToLowerInvariant()) {
        'on' { Set-Content -LiteralPath $flag -Value "on $(Get-Date -Format 'yyyy-MM-dd HH:mm')"; 'auto-launch ON' }
        'off' { Remove-Item -LiteralPath $flag -ErrorAction SilentlyContinue; 'auto-launch OFF' }
        default { if (Test-Path -LiteralPath $flag) { 'auto-launch ON' } else { 'auto-launch OFF' } }
    }
    exit 0
}

function New-RealCtx {
    New-Ctx $Root (Get-Now) { param($s) Start-RealLaunch $s } { param($n, $s, $t, $l, $o, $x) Real-StatusWriter $n $s $t $l $o $x } { param($a) Real-ProcessProbe $a } $ProjectDir
}

if ($Status) {
    $c = New-RealCtx; $hb = Read-Heartbeat $Root
    "heartbeat: $(if ($hb) { "age $([int](($c.Now - $hb.Epoch)/60)) min, session $($hb.Session) (stale > $($HB_STALE/60) min = coordinator presumed dead)" } else { 'none' })"
    $hf = Join-Path $Root 'handoff.ready'
    "handoff.ready: $(if (Test-Path $hf) { "$([int](($c.Now - (To-Epoch (Get-Item $hf).LastWriteTime))/60)) min old" } else { 'absent' })"
    $p = Read-Programs $c
    "programs with open wps: $(if ($p.Active.Count) { ($p.Active | ForEach-Object { $_.Name }) -join ', ' } else { 'none' }); malformed ledgers: $($p.Bad.Count)"
    "auto-launch: $(if (Test-Path (Join-Path $Root 'supervisor.autolaunch')) { 'ON' } else { 'OFF (default)' }); relaunches in the last hour: $(@(Get-State $c | Where-Object { ($c.Now - $_) -lt $HOUR }).Count)"
    $ti = Get-TailInfo $c
    "tail sessions: $(if (@(Get-TailFlags $Root).Count) { (@(Get-TailFlags $Root) | ForEach-Object { "$($_.Session) $(if ($_.Alive) { 'LIVE' } else { 'DEAD' })" }) -join '; ' } else { 'none' }); live-tail agents: $(if (@($ti.LiveAgents).Count) { @($ti.LiveAgents) -join ', ' } else { 'none' }); dead-tail agents (respawn): $(if (@($ti.DeadAgents).Count) { @($ti.DeadAgents) -join ', ' } else { 'none' })"
    $loops = Find-Loops; "loop: $(if ($loops) { "running pid $($loops[0].ProcessId)" } else { 'not running' })"
    exit 0
}
if ($Stop) {
    foreach ($l in (Find-Loops)) { Stop-Process -Id $l.ProcessId -Force -ErrorAction SilentlyContinue; "stopped loop $($l.ProcessId)" }
    Remove-Item -LiteralPath (Get-PidFile) -ErrorAction SilentlyContinue; exit 0
}
if ($Ensure) {
    $loops = @(Find-Loops)
    if ($loops.Count -ge 1) { "coord-supervisor loop already running pid $($loops[0].ProcessId)"; exit 0 }
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'supervisor') | Out-Null
    $p = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Loop', '-Root', $Root, '-IntervalSec', "$IntervalSec")
    Set-Content -LiteralPath (Get-PidFile) -Value $p.Id
    "coord-supervisor loop started pid $($p.Id) (auto-launch $(if (Test-Path (Join-Path $Root 'supervisor.autolaunch')) { 'ON' } else { 'OFF: alert only' }))"
    exit 0
}
if ($Loop) {
    while ($true) {
        try { $c = New-RealCtx; [void](Invoke-Pass $c) } catch {}
        Start-Sleep -Seconds $IntervalSec
    }
}
if ($Once) {
    $c = New-RealCtx; $r = Invoke-Pass $c
    $c.Log | ForEach-Object { $_ }
    "result: $($r.Result)"
    exit 0
}
'usage: coord-supervisor.ps1 -Ensure | -Once | -Status | -Autolaunch on|off|status | -Stop | -Selftest   (see header)'
