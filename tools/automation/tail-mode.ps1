# tail-mode.ps1: overlap ("tail") handoff state (docs/TAIL_HANDOFF_CONTRACT.md, Shay 2026-10-15).
# A coordinator near its context limit opens a NEW coordinator session and stays alive as a TAIL session so its in-session
# subagents are not killed. A tail session is marked by a flag file  <runs>\tail\<session>.flag :
#   { "session": "<id>", "pid": <claude pid>, "created": "<iso>", "new_coordinator_inbox": "...\\inbox\\coordinator", "agents": ["a","b"] }
#
#   tail-mode.ps1 enter  [-Session <id>] [-Agents a,b] [-ClaudePid n]   create/update the flag; agents = -Agents + every ledger agent whose
#                                                                        owner_session is tail:<id>. -Session omitted = newest transcript
#                                                                        under ~/.claude/projects/C--KenshiModding (the context meter prints the id).
#   tail-mode.ps1 status [-Session <id>]                                 show the flag, liveness and the state of each owned agent
#   tail-mode.ps1 leave  [-Session <id>] [-Force]                        remove the flag; refuses while an owned agent is unfinished or
#                                                                        unacknowledged unless -Force
#   tail-mode.ps1 list                                                   every tail flag: LIVE/DEAD, owned agents; DEAD tail + unfinished agents = respawn from checkpoints
#   tail-mode.ps1 current [show]                                         print the CURRENT-COORDINATOR pointer  <runs>\coordinator.current  (JSON session/pid/name/started/updated)
#   tail-mode.ps1 current set [-Session <id>] [-ClaudePid n] [-Name x]   write it (the live coordinator; session-start.ps1 and the coord-heartbeat claim do this)
#   tail-mode.ps1 adopt [-Session <id>]                                  make <id> (default: the pointer) the relay target of EVERY live tail's flag (flag field relay_to);
#                                                                        ledger owner_session stays tail:<id>, only where results are sent changes
#   tail-mode.ps1 target [-Agent a] [-ToSession x]                       print where tail-relay.ps1 would send a message right now
# Flag extras written by `enter`: proc_name / proc_start (the claude process identity, used by tail-close.ps1 against pid reuse), relay_to (adopt).
# Env: KAH_RUNS_DIR (or KCS_RUNS, or -Runs) overrides C:\KenshiTestRuns (selftests). Selftest: tools\automation\tail-hooks-selftest.ps1.
# Dot-sourcing this file only defines the functions (used by kenshi-waker-guard.ps1 and coord-supervisor.ps1).
# Ledger (programs\<program>.json), per agent, in the top-level `agents` map or a wp's `agent_records` (map or array):
#   owner_session (live | tail:<name>), routing_note, result_file, acked_by_new_coordinator. Missing fields are tolerated.
param([Parameter(Position = 0)][string]$TailCmd = '', [Parameter(Position = 1)][string]$Sub = '', [string]$Session = '', [string[]]$Agents = @(), [int]$ClaudePid = 0, [switch]$Force, [string]$Runs = '', [string]$Name = '', [string]$Agent = '', [string]$ToSession = '', [switch]$Auto)

$TAIL_TERMINAL = @('DONE', 'FAILED', 'STOPPED-CONTEXT')

function Get-TailRuns([string]$runs = '') {
    if ($runs) { return $runs }
    if ($env:KAH_RUNS_DIR) { return $env:KAH_RUNS_DIR }
    if ($env:KCS_RUNS) { return $env:KCS_RUNS }
    return 'C:\KenshiTestRuns'
}
function Get-TailDir([string]$runs) { Join-Path (Get-TailRuns $runs) 'tail' }
function Get-TailFlagPath([string]$runs, [string]$session) { Join-Path (Get-TailDir $runs) (($session -replace '[\\/:*?"<>|]', '_') + '.flag') }

function Test-TailPid([int]$p, [string]$created) {
    if ($p -le 0) { return $true }   # pid unknown: cannot tell, fail open
    $pr = Get-Process -Id $p -ErrorAction SilentlyContinue
    if (-not $pr) { return $false }
    try {
        $cr = [datetimeoffset]::Parse($created)
        if ($pr.StartTime.ToUniversalTime() -gt $cr.UtcDateTime.AddMinutes(2)) { return $false }   # pid reused by a younger process
    } catch { }
    return $true
}

function Read-TailFlag([string]$path) {
    try {
        $t = ((Get-Content -LiteralPath $path -Raw -ErrorAction Stop) -as [string]).TrimStart([char]0xFEFF)
        $j = $t | ConvertFrom-Json -ErrorAction Stop
        $sess = if ($j.session) { [string]$j.session } else { [IO.Path]::GetFileNameWithoutExtension($path) }
        $p = 0; if ($j.pid) { [void][int]::TryParse([string]$j.pid, [ref]$p) }
        [pscustomobject]@{
            Session = $sess; Pid = $p; Created = [string]$j.created; Inbox = [string]$j.new_coordinator_inbox
            ProcName = [string]$j.proc_name; ProcStart = [string]$j.proc_start; RelayTo = [string]$j.relay_to
            Agents = @(@($j.agents) | Where-Object { $_ } | ForEach-Object { [string]$_ }); Path = $path
            Alive = (Test-TailPid $p ([string]$j.created))
        }
    } catch { return $null }
}

function Get-TailFlags([string]$runs = '') {
    $d = Get-TailDir $runs
    if (-not (Test-Path -LiteralPath $d)) { return @() }
    @(Get-ChildItem -LiteralPath $d -Filter '*.flag' -File -ErrorAction SilentlyContinue | ForEach-Object { Read-TailFlag $_.FullName } | Where-Object { $_ })
}

# Ledger agent records: Program, Wp, Agent, Owner, Note, Result, Acked.
function Get-LedgerAgentRecords([string]$runs = '') {
    $out = New-Object Collections.ArrayList
    $dir = Join-Path (Get-TailRuns $runs) 'programs'
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $j = (Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if (-not $j) { continue }
        $prog = if ($j.name) { [string]$j.name } else { $f.BaseName }
        $add = {
            param($container, $wpId)
            if ($null -eq $container) { return }
            $pairs = @()
            if ($container -is [System.Collections.IList]) {
                foreach ($i in $container) { if ($i) { $n = if ($i.agent) { [string]$i.agent } else { [string]$i.name }; if ($n) { $pairs += , @($n, $i) } } }
            } else {
                foreach ($p in $container.PSObject.Properties) { if ($p.Value) { $pairs += , @([string]$p.Name, $p.Value) } }
            }
            foreach ($pr in $pairs) {
                $r = $pr[1]
                [void]$out.Add([pscustomobject]@{
                    Program = $prog; Wp = $wpId; Agent = $pr[0]
                    Owner = [string]$r.owner_session; Note = [string]$r.routing_note; Result = [string]$r.result_file
                    Acked = ([string]$r.acked_by_new_coordinator -eq 'True')
                })
            }
        }
        & $add $j.agents ''
        foreach ($w in @($j.wps)) { if ($w) { & $add $w.agent_records ([string]$w.id) } }
    }
    return @($out)
}

function Get-AgentStatusState([string]$runs, [string]$agent) {
    $sf = Join-Path (Join-Path (Get-TailRuns $runs) 'agents') "$agent.status"
    if (-not (Test-Path -LiteralPath $sf)) { return @{ State = ''; AgeMin = 9999 } }
    $l1 = ((Get-Content -LiteralPath $sf -TotalCount 1 -ErrorAction SilentlyContinue) -as [string]).TrimStart([char]0xFEFF)
    $pp = @($l1 -split '\|' | ForEach-Object { $_.Trim() })
    @{ State = $(if ($pp.Count -ge 2) { $pp[1] } else { '' }); AgeMin = ((Get-Date) - (Get-Item -LiteralPath $sf).LastWriteTime).TotalMinutes }
}

# The agents a tail flag owns, with their state. Pending = still running, or finished but not acknowledged by the new coordinator.
function Get-TailAgentSet([string]$runs, $flag) {
    $recs = @(Get-LedgerAgentRecords $runs)
    $names = New-Object Collections.ArrayList
    foreach ($a in $flag.Agents) { if ($a -and $names -notcontains $a) { [void]$names.Add($a) } }
    foreach ($r in $recs) { if ($r.Owner -eq "tail:$($flag.Session)" -and $names -notcontains $r.Agent) { [void]$names.Add($r.Agent) } }
    $res = @()
    foreach ($n in $names) {
        $rec = $recs | Where-Object { $_.Agent -eq $n } | Select-Object -First 1
        $st = Get-AgentStatusState $runs $n
        $acked = [bool]($rec -and $rec.Acked)
        $running = ($st.State -ne '') -and ($TAIL_TERMINAL -notcontains $st.State) -and ($st.AgeMin -lt 45)
        $pending = (-not $acked) -or $running
        $why = if ($running) { "running" } elseif (-not $rec) { "$(if ($st.State) { $st.State } else { 'no status' }), no ledger record" } elseif (-not $acked) { "$(if ($st.State) { $st.State } else { 'no status' }), not acknowledged" } else { 'done+acked' }
        $res += [pscustomobject]@{ Agent = $n; Program = $(if ($rec) { $rec.Program } else { '' }); State = $st.State; Acked = $acked; Pending = $pending; Why = $why }
    }
    return @($res)
}

# Stop-hook verdict for a session: Tail=$false when it has no flag; Block=$true while an owned agent is pending.
function Get-TailStopVerdict([string]$runs, [string]$session) {
    if (-not $session) { return @{ Tail = $false; Block = $false; Message = '' } }
    $fp = Get-TailFlagPath $runs $session
    if (-not (Test-Path -LiteralPath $fp)) { return @{ Tail = $false; Block = $false; Message = '' } }
    $flag = Read-TailFlag $fp
    if (-not $flag) { return @{ Tail = $true; Block = $false; Message = 'unreadable tail flag: not blocking' } }
    $set = @(Get-TailAgentSet $runs $flag | Where-Object { $_.Pending })
    if (-not $set.Count) { return @{ Tail = $true; Block = $false; Message = '' } }
    $msg = "this is a TAIL session (overlap handoff, flag $fp) and still owns $($set.Count) agent(s) that are not finished or not acknowledged by the new coordinator: " +
        (($set | ForEach-Object { "$($_.Agent) [$($_.Why)]" }) -join '; ') +
        ". Do not end the turn: keep waiting for them (you spawn and decide nothing new), and when one finishes save its report to a file, relay it to the new coordinator (tail-relay.ps1 + SendMessage, inbox C:\KenshiTestRuns\inbox\coordinator), and wait for its ACK (program-ledger.ps1 ack / tail-ack.ps1). A stalled agent: silent 10 min -> message it, 20 min -> TaskStop it and tell the new coordinator. You may end only when every agent is done AND acknowledged. If this flag is wrong: powershell -NoProfile -File C:\KenshiModding\tools\automation\tail-mode.ps1 leave -Session $session -Force"
    return @{ Tail = $true; Block = $true; Message = $msg; Pending = $set }
}

# Nearest claude/node ancestor of this process (the session's own process).
function Find-ClaudePid {
    try {
        $procs = @{}
        foreach ($p in (Get-CimInstance Win32_Process -ErrorAction Stop)) { $procs[[int]$p.ProcessId] = $p }
        $cur = $PID; $hops = 0
        while ($cur -and $procs.ContainsKey($cur) -and $hops -lt 20) {
            if ($procs[$cur].Name -match '^(claude|node)\.exe$') { return $cur }
            $cur = [int]$procs[$cur].ParentProcessId; $hops++
        }
    } catch { }
    return 0
}

function Get-DefaultSession {
    $d = Join-Path $env:USERPROFILE '.claude\projects\C--KenshiModding'
    $f = Get-ChildItem -LiteralPath $d -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return [IO.Path]::GetFileNameWithoutExtension($f.Name) }
    return ''
}

function Write-TailFlag([string]$runs, [string]$session, [int]$cpid, [string[]]$agents, [string]$created, [string]$procName = '', [string]$procStart = '', [string]$relayTo = '') {
    $d = Get-TailDir $runs
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $obj = [ordered]@{
        session = $session; pid = $cpid; created = $created
        new_coordinator_inbox = (Join-Path (Get-TailRuns $runs) 'inbox\coordinator')
        agents = @($agents)
    }
    if ($procName) { $obj['proc_name'] = $procName }
    if ($procStart) { $obj['proc_start'] = $procStart }
    if ($relayTo) { $obj['relay_to'] = $relayTo }
    $fp = Get-TailFlagPath $runs $session
    $tmp = "$fp.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $fp -Force
    return $fp
}

# ---------------------------------------------------------------- current-coordinator pointer, relay target, safe close (Shay 2026-10-15)
function Get-CoordPointerPath([string]$runs = '') { Join-Path (Get-TailRuns $runs) 'coordinator.current' }

# Process identity recorded in the tail flag: name (no .exe) + start time (ISO, UTC). $null when the pid is not running.
function Get-ProcIdentity([int]$p) {
    if ($p -le 0) { return $null }
    $pr = Get-Process -Id $p -ErrorAction SilentlyContinue
    if (-not $pr) { return $null }
    $st = ''; try { $st = $pr.StartTime.ToUniversalTime().ToString('o') } catch { }
    return [pscustomobject]@{ Name = $pr.ProcessName; Start = $st }
}

# The pointer: Session/Pid/Name/Started/Updated/Alive/IsTail. $null when missing or unreadable (callers fall back to the inbox only).
function Read-CoordPointer([string]$runs = '') {
    try {
        $path = Get-CoordPointerPath $runs
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $j = ((Get-Content -LiteralPath $path -Raw -ErrorAction Stop) -as [string]).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
        if (-not $j -or -not $j.session) { return $null }
        $p = 0; if ($j.pid) { [void][int]::TryParse([string]$j.pid, [ref]$p) }
        $sess = [string]$j.session
        return [pscustomobject]@{
            Session = $sess; Pid = $p; Name = [string]$j.name; Started = [string]$j.started; Updated = [string]$j.updated
            Alive = (Test-TailPid $p ([string]$j.started))
            IsTail = (Test-Path -LiteralPath (Get-TailFlagPath $runs $sess))
        }
    } catch { return $null }
}

function Write-CoordPointer([string]$runs, [string]$session, [int]$cpid, [string]$name = '') {
    New-Item -ItemType Directory -Force -Path (Get-TailRuns $runs) | Out-Null
    $old = Read-CoordPointer $runs
    $started = (Get-Date).ToString('o')
    if ($old -and $old.Session -eq $session -and $old.Started) { $started = $old.Started }   # same coordinator re-running session-start: keep its start time
    $obj = [ordered]@{ session = $session; pid = $cpid; name = $(if ($name) { $name } else { 'coordinator' }); started = $started; updated = (Get-Date).ToString('o') }
    $path = Get-CoordPointerPath $runs
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
    return $path
}

# Where does a tail relay go? ("relay follows the current coordinator", docs/TAIL_HANDOFF_CONTRACT.md)
#   no -ToSession -> the current coordinator (pointer alive and not itself a tail), else the relay_to of a tail flag owning the agent, else '' (inbox file only)
#   -ToSession X  -> X, unless X is itself a tail session (flag) or is the pointer session with a dead process: then the current coordinator
# Returns Target/Reason/Redirected. Never throws.
function Resolve-RelayTarget([string]$runs, [string]$agentName, [string]$toSession) {
    try {
        $ptr = Read-CoordPointer $runs
        $ptrOk = $ptr -and $ptr.Alive -and (-not $ptr.IsTail)
        if (-not $toSession) {
            if ($ptrOk) { return @{ Target = $ptr.Session; Reason = 'current coordinator (coordinator.current)'; Redirected = $false } }
            foreach ($f in @(Get-TailFlags $runs)) {
                if ($f.RelayTo -and ($f.Agents -contains $agentName)) { return @{ Target = $f.RelayTo; Reason = 'relay_to of the owning tail flag (adopt); coordinator.current unusable'; Redirected = $false } }
            }
            $why = if (-not $ptr) { 'no coordinator.current pointer' } elseif ($ptr.IsTail) { 'coordinator.current is itself a tail session' } else { 'coordinator.current process not alive' }
            return @{ Target = ''; Reason = "$why`: inbox file only"; Redirected = $false }
        }
        $isTail = Test-Path -LiteralPath (Get-TailFlagPath $runs $toSession)
        $isDead = $ptr -and ($ptr.Session -eq $toSession) -and (-not $ptr.Alive)
        $what = if ($isTail) { 'itself a tail session' } else { 'not alive' }
        if (($isTail -or $isDead) -and $ptrOk -and $ptr.Session -ne $toSession) {
            return @{ Target = $ptr.Session; Reason = "requested $toSession is $what`: redirected to the current coordinator"; Redirected = $true }
        }
        $note = if ($isTail -or $isDead) { "requested $toSession is $what but no usable current coordinator is known: kept as given" } else { 'as requested' }
        return @{ Target = $toSession; Reason = $note; Redirected = $false }
    } catch { return @{ Target = $toSession; Reason = "relay-target resolution failed ($($_.Exception.Message)): kept as given"; Redirected = $false } }
}

function Set-TailFlagField([string]$path, [string]$field, [string]$value) {
    $j = ((Get-Content -LiteralPath $path -Raw -ErrorAction Stop) -as [string]).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
    if ($j.PSObject.Properties[$field]) { $j.$field = $value } else { Add-Member -InputObject $j -NotePropertyName $field -NotePropertyValue $value }
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($j | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

# Is it safe to close (kill the claude process of) a tail session? Fails closed: any doubt = Ok $false with the reason.
# $callerSelf = true when the tail's own Stop hook asks (its own process is then legitimately an ancestor of the caller).
function Test-TailClosable([string]$runs, [string]$session, [bool]$callerSelf = $false, [int]$minAgeNoAgentsMin = 5) {
    $no = { param($why) @{ Ok = $false; Gone = $false; Why = $why; Pid = 0; Name = '' } }
    try {
        if (-not $session) { return (& $no 'no session id') }
        $fp = Get-TailFlagPath $runs $session
        if (-not (Test-Path -LiteralPath $fp)) { return (& $no "no tail flag for $session") }
        $flag = Read-TailFlag $fp
        if (-not $flag) { return (& $no 'tail flag unreadable') }
        $set = @(Get-TailAgentSet $runs $flag)
        $pend = @($set | Where-Object { $_.Pending })
        if ($pend.Count) { return (& $no ('agent(s) not done+acked: ' + (($pend | ForEach-Object { "$($_.Agent) [$($_.Why)]" }) -join '; '))) }
        if (-not $set.Count) {
            $age = 0.0; try { $age = ((Get-Date) - [datetimeoffset]::Parse($flag.Created).LocalDateTime).TotalMinutes } catch { $age = 0.0 }
            if ($age -lt $minAgeNoAgentsMin) { return (& $no "flag lists no agents and is younger than $minAgeNoAgentsMin min (handoff may still be in progress)") }
        }
        if ($flag.Pid -le 0) { return (& $no 'flag has no pid') }
        $pr = Get-Process -Id $flag.Pid -ErrorAction SilentlyContinue
        if (-not $pr) { return @{ Ok = $false; Gone = $true; Why = "process $($flag.Pid) already gone"; Pid = $flag.Pid; Name = '' } }
        # identity: name + start time recorded by `enter`; older flags: claude/node and not younger than the flag
        if ($flag.ProcName) { if ($pr.ProcessName -ine $flag.ProcName) { return (& $no "process name mismatch (pid $($flag.Pid) is '$($pr.ProcessName)', flag says '$($flag.ProcName)'): pid reused?") } }
        elseif ($pr.ProcessName -notmatch '^(claude|node)$') { return (& $no "pid $($flag.Pid) is '$($pr.ProcessName)', not claude/node, and the flag records no process name") }
        if ($flag.ProcStart) {
            $rec = [datetimeoffset]::Parse($flag.ProcStart).UtcDateTime
            if ([math]::Abs(($pr.StartTime.ToUniversalTime() - $rec).TotalSeconds) -gt 2) { return (& $no "process start time mismatch (pid $($flag.Pid) started $($pr.StartTime.ToUniversalTime().ToString('o')), flag says $($flag.ProcStart)): pid reused") }
        } elseif (-not (Test-TailPid $flag.Pid $flag.Created)) { return (& $no "pid $($flag.Pid) is younger than the flag: pid reused") }
        # never the live coordinator
        $ptr = Read-CoordPointer $runs
        if ($ptr -and ($ptr.Session -eq $session -or ($ptr.Pid -gt 0 -and $ptr.Pid -eq $flag.Pid))) { return (& $no 'this is the CURRENT coordinator (coordinator.current): never closed') }
        $hb = Join-Path (Get-TailRuns $runs) 'coordinator.heartbeat'
        if (Test-Path -LiteralPath $hb) {
            $hp = @(((Get-Content -LiteralPath $hb -TotalCount 1 -ErrorAction Stop) -as [string]) -split '\s+')
            if ($hp.Count -ge 2 -and $hp[1] -eq $session) { return (& $no 'this session owns the coordinator heartbeat: never closed (the new coordinator has not claimed it yet)') }
        }
        if (-not $callerSelf) {   # a manual close must not take down the process that runs it
            $parents = @{}
            foreach ($p in (Get-CimInstance Win32_Process -ErrorAction Stop)) { $parents[[int]$p.ProcessId] = [int]$p.ParentProcessId }
            $cur = $PID; $hops = 0
            while ($cur -and $parents.ContainsKey($cur) -and $hops -lt 30) {
                if ($cur -eq $flag.Pid) { return (& $no 'the target pid is an ancestor of the caller (would close the caller)') }
                $cur = $parents[$cur]; $hops++
            }
        }
        return @{ Ok = $true; Gone = $false; Why = 'all agents done+acked, process identity matches, not the coordinator'; Pid = $flag.Pid; Name = $pr.ProcessName }
    } catch { return (& $no "check failed closed: $($_.Exception.Message)") }
}

if ($MyInvocation.InvocationName -eq '.') { return }

# ---------------------------------------------------------------- CLI
$ErrorActionPreference = 'Stop'
$runsDir = Get-TailRuns $Runs
function Resolve-Session {
    if ($Session) { return $Session }
    $s = Get-DefaultSession
    if ($s) { Write-Host "(no -Session given: using newest transcript id $s)" }
    return $s
}
function Show-Agents($flag) {
    $set = @(Get-TailAgentSet $runsDir $flag)
    if (-not $set.Count) { '  agents: none' }
    foreach ($a in $set) { "  agent $($a.Agent): status=$(if ($a.State) { $a.State } else { 'none' }) acked=$($a.Acked) -> $($a.Why)" }
}

switch ($TailCmd.ToLowerInvariant()) {
    'enter' {
        $s = Resolve-Session
        if (-not $s) { 'tail-mode enter: need -Session <id> (the context meter handoff text prints it)'; exit 2 }
        $cp = if ($ClaudePid) { $ClaudePid } else { Find-ClaudePid }
        if (-not $cp) { Write-Host 'WARNING: could not find the claude process; pid recorded as 0 (liveness unknown)' }
        $fp = Get-TailFlagPath $runsDir $s
        $names = New-Object Collections.ArrayList
        $created = (Get-Date).ToString('o')
        if (Test-Path -LiteralPath $fp) {   # re-enter: keep creation time + known agents
            $old = Read-TailFlag $fp
            if ($old) { $created = $old.Created; foreach ($a in $old.Agents) { [void]$names.Add($a) } if (-not $cp) { $cp = $old.Pid } }
        }
        foreach ($a in $Agents) { foreach ($x in ($a -split ',')) { $x = $x.Trim(); if ($x -and $names -notcontains $x) { [void]$names.Add($x) } } }
        foreach ($r in (Get-LedgerAgentRecords $runsDir)) { if ($r.Owner -eq "tail:$s" -and $names -notcontains $r.Agent) { [void]$names.Add($r.Agent) } }
        $idn = Get-ProcIdentity $cp
        $relayKeep = ''
        if ($old -and $old.RelayTo) { $relayKeep = $old.RelayTo }
        $fp = Write-TailFlag $runsDir $s $cp @($names) $created $(if ($idn) { $idn.Name } else { '' }) $(if ($idn) { $idn.Start } else { '' }) $relayKeep
        "TAIL MODE ON: session $s pid $cp, flag $fp, agents: $(if ($names.Count) { $names -join ', ' } else { 'none' })"
        $ptrNow = Read-CoordPointer $runsDir
        if ($ptrNow -and $ptrNow.Session -eq $s) { 'NOTE: coordinator.current still names this session; the new coordinator''s session-start.ps1 replaces it (until then relays use the inbox file only).' }
        'When ALL your agents are done and acknowledged, close yourself: tail-close.ps1 -Session ' + $s + ' (sends TAIL-DONE to the current coordinator, then ends this process after ~20 s; the Stop hook does it automatically when you may end).'
        'From now on: spawn nothing, edit nothing, decide nothing; keep your event-wait waker; relay each finished agent to the new coordinator; end only when all are done AND acknowledged.'
        exit 0
    }
    'status' {
        $s = Resolve-Session
        $fp = Get-TailFlagPath $runsDir $s
        if (-not $s -or -not (Test-Path -LiteralPath $fp)) { "not in tail mode (no flag for session '$s')"; exit 0 }
        $f = Read-TailFlag $fp
        if (-not $f) { "tail flag $fp unreadable"; exit 1 }
        "tail session $($f.Session) pid $($f.Pid) $(if ($f.Alive) { 'LIVE' } else { 'DEAD' }) created $($f.Created) flag $fp"
        Show-Agents $f
        if ($f.RelayTo) { "  relays go to coordinator $($f.RelayTo)" }
        $v = Get-TailStopVerdict $runsDir $s
        "stop allowed: $(-not $v.Block)"
        exit 0
    }
    'leave' {
        $s = Resolve-Session
        $fp = Get-TailFlagPath $runsDir $s
        if (-not $s -or -not (Test-Path -LiteralPath $fp)) { "not in tail mode (no flag for session '$s')"; exit 0 }
        $v = Get-TailStopVerdict $runsDir $s
        if ($v.Block -and -not $Force) { "REFUSED: agents still pending: $((@($v.Pending) | ForEach-Object { "$($_.Agent) [$($_.Why)]" }) -join '; '). Use -Force to drop the flag anyway."; exit 1 }
        Remove-Item -LiteralPath $fp -Force
        "TAIL MODE OFF: removed $fp"
        exit 0
    }
    'list' {
        $fl = @(Get-TailFlags $runsDir)
        if (-not $fl.Count) { 'no tail sessions'; exit 0 }
        foreach ($f in $fl) {
            "tail session $($f.Session) pid $($f.Pid) $(if ($f.Alive) { 'LIVE' } else { 'DEAD' }) created $($f.Created)"
            Show-Agents $f
            if ($f.RelayTo) { "  relays go to coordinator $($f.RelayTo)" }
            if (-not $f.Alive) {
                $pend = @(Get-TailAgentSet $runsDir $f | Where-Object { $_.Pending })
                if ($pend.Count) { "  DEAD TAIL: process gone, agents $((($pend | ForEach-Object Agent) -join ', ')) died with it: respawn them from their checkpoints (fresh names), then: tail-mode.ps1 leave -Session $($f.Session) -Force" }
            }
        }
        exit 0
    }
    'current' {
        if ($Sub -ne 'set') {
            $pp = Read-CoordPointer $runsDir
            if (-not $pp) { "no usable coordinator.current ($(Get-CoordPointerPath $runsDir))"; exit 0 }
            "coordinator.current: session $($pp.Session) pid $($pp.Pid) name $($pp.Name) started $($pp.Started) updated $($pp.Updated) $(if ($pp.Alive) { 'ALIVE' } else { 'DEAD' })$(if ($pp.IsTail) { ' (but it is a TAIL session)' })"
            exit 0
        }
        # set: the live coordinator. -Auto (session-start.ps1) = best effort, never an error, never for agents / tail sessions.
        if ($Auto -and $env:KAH_AGENT_NAME) { 'coordinator.current: not written (independent agent session)'; exit 0 }
        $s = if ($Session) { $Session } elseif ($env:KAH_COORD_SESSION) { $env:KAH_COORD_SESSION } else { Get-DefaultSession }
        if (-not $s) { 'coordinator.current: no session id (pass -Session)'; if ($Auto) { exit 0 } else { exit 2 } }
        if (Test-Path -LiteralPath (Get-TailFlagPath $runsDir $s)) { "coordinator.current: not written, $s is a tail session"; exit 0 }
        $cp = if ($ClaudePid) { $ClaudePid } else { Find-ClaudePid }
        $pf = Write-CoordPointer $runsDir $s $cp $Name
        "coordinator.current: session $s pid $cp -> $pf"
        exit 0
    }
    'adopt' {
        $s = $Session
        if (-not $s) { $pp = Read-CoordPointer $runsDir; if ($pp) { $s = $pp.Session } }
        if (-not $s) { 'adopt: no -Session and no coordinator.current'; exit 2 }
        if (Test-Path -LiteralPath (Get-TailFlagPath $runsDir $s)) { "adopt: $s is itself a tail session, refusing"; exit 1 }
        $n = 0
        foreach ($f in @(Get-TailFlags $runsDir)) {
            if (-not $f.Alive) { "  tail $($f.Session): DEAD, skipped"; continue }
            if ($f.Session -eq $s) { continue }
            try {
                if ($f.RelayTo -ne $s) { Set-TailFlagField $f.Path 'relay_to' $s }
                $n++
                "  tail $($f.Session): relays of $(if ($f.Agents.Count) { $f.Agents -join ', ' } else { '(no agents)' }) now go to $s (ledger owner stays tail:$($f.Session))"
            } catch { "  tail $($f.Session): could not update flag ($($_.Exception.Message))" }
        }
        "ADOPT: $n live tail(s) now relay to coordinator $s"
        exit 0
    }
    'target' {
        $t = Resolve-RelayTarget $runsDir $Agent $ToSession
        "relay target: $(if ($t.Target) { $t.Target } else { '(none: inbox file only)' }) -- $($t.Reason)"
        exit 0
    }
    default { 'usage: tail-mode.ps1 enter|status|leave|list|current [set]|adopt|target [-Session <id>] [-Agents a,b] [-ClaudePid n] [-Force] [-Runs <dir>] [-Name x] [-Agent a] [-ToSession x]'; exit 2 }
}
