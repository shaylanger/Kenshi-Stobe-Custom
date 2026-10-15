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
# Env: KAH_RUNS_DIR (or KCS_RUNS, or -Runs) overrides C:\KenshiTestRuns (selftests). Selftest: tools\automation\tail-hooks-selftest.ps1.
# Dot-sourcing this file only defines the functions (used by kenshi-waker-guard.ps1 and coord-supervisor.ps1).
# Ledger (programs\<program>.json), per agent, in the top-level `agents` map or a wp's `agent_records` (map or array):
#   owner_session (live | tail:<name>), routing_note, result_file, acked_by_new_coordinator. Missing fields are tolerated.
param([Parameter(Position = 0)][string]$TailCmd = '', [string]$Session = '', [string[]]$Agents = @(), [int]$ClaudePid = 0, [switch]$Force, [string]$Runs = '')

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

function Write-TailFlag([string]$runs, [string]$session, [int]$cpid, [string[]]$agents, [string]$created) {
    $d = Get-TailDir $runs
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $obj = [ordered]@{
        session = $session; pid = $cpid; created = $created
        new_coordinator_inbox = (Join-Path (Get-TailRuns $runs) 'inbox\coordinator')
        agents = @($agents)
    }
    $fp = Get-TailFlagPath $runs $session
    $tmp = "$fp.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $fp -Force
    return $fp
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
        $fp = Write-TailFlag $runsDir $s $cp @($names) $created
        "TAIL MODE ON: session $s pid $cp, flag $fp, agents: $(if ($names.Count) { $names -join ', ' } else { 'none' })"
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
            if (-not $f.Alive) {
                $pend = @(Get-TailAgentSet $runsDir $f | Where-Object { $_.Pending })
                if ($pend.Count) { "  DEAD TAIL: process gone, agents $((($pend | ForEach-Object Agent) -join ', ')) died with it: respawn them from their checkpoints (fresh names), then: tail-mode.ps1 leave -Session $($f.Session) -Force" }
            }
        }
        exit 0
    }
    default { 'usage: tail-mode.ps1 enter|status|leave|list [-Session <id>] [-Agents a,b] [-ClaudePid n] [-Force] [-Runs <dir>]'; exit 2 }
}
