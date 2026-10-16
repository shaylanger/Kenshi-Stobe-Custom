# tail-close-selftest.ps1: offline selftest of "relay follows the current coordinator" (coordinator.current, tail-relay target, adopt) and of
# the safe auto-close of a finished tail session (tail-close.ps1, tail-ack.ps1 auto-close, Stop-hook trigger). Everything runs against a temp
# runs dir (KAH_RUNS_DIR); a dummy sleeping powershell process stands in for the claude pid. No real flag, pointer, heartbeat or process is touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\tail-close-selftest.ps1 [-Guard <path to a candidate kenshi-waker-guard.ps1>]
param([string]$Guard = '')
$ErrorActionPreference = 'Stop'
$auto = $PSScriptRoot
$tm = Join-Path $auto 'tail-mode.ps1'
$relay = Join-Path $auto 'tail-relay.ps1'
$close = Join-Path $auto 'tail-close.ps1'
$ack = Join-Path $auto 'tail-ack.ps1'
$ledger = Join-Path $auto 'program-ledger.ps1'
if (-not $Guard) { $Guard = Join-Path $auto 'hooks\kenshi-waker-guard.ps1' }
$d = Join-Path ([IO.Path]::GetTempPath()) ("tailclose-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'programs'), (Join-Path $d 'agents'), (Join-Path $d 'tail'), (Join-Path $d 'inbox\coordinator') | Out-Null
$old = @{}; foreach ($k in 'KAH_RUNS_DIR', 'KCS_RUNS', 'KPL_DIR', 'KAH_TAIL_NO_CLOSE', 'KAH_TAIL_CLOSE_DELAY', 'KAH_AGENT_NAME', 'KAH_COORD_SESSION') { $old[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:KAH_RUNS_DIR = $d; $env:KCS_RUNS = $d; $env:KPL_DIR = Join-Path $d 'programs'
foreach ($k in 'KAH_TAIL_NO_CLOSE', 'KAH_AGENT_NAME', 'KAH_COORD_SESSION') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
$script:pass = 0; $script:fail = 0
$dummies = New-Object Collections.ArrayList
function T([bool]$ok, [string]$n) { if ($ok) { $script:pass++; "PASS $n" } else { $script:fail++; "FAIL $n" } }
function RunPS([string[]]$a, [string]$stdin = '') {
    $ErrorActionPreference = 'Continue'
    if ($stdin) { return @($stdin | & powershell -NoProfile -ExecutionPolicy Bypass @a 2>&1 | ForEach-Object { "$_" }) }
    return @(& powershell -NoProfile -ExecutionPolicy Bypass @a 2>&1 | ForEach-Object { "$_" })
}
function Dummy { $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 600' -WindowStyle Hidden -PassThru; [void]$dummies.Add($p); Start-Sleep -Milliseconds 400; return $p }
function Alive($p) { [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue) }
function WaitDead($p, [int]$sec = 25) { for ($i = 0; $i -lt $sec * 4; $i++) { if (-not (Alive $p)) { return $true }; Start-Sleep -Milliseconds 250 }; return $false }
function Status([string]$n, [string]$state) { Set-Content -LiteralPath (Join-Path $d "agents\$n.status") -Value @("$n | $state | d", 'task: T') }
function L([string[]]$a) { [void](RunPS (@('-File', $ledger) + $a)) }
function RouteAgent([string]$prog, [string]$wp, [string]$agent, [string]$owner) {
    if (-not (Test-Path (Join-Path $d "programs\$prog.json"))) { L @('init', $prog, "testing/$prog.md") }
    $has = (Get-Content (Join-Path $d "programs\$prog.json") -Raw) -match "`"id`":\s*`"$wp`""
    if (-not $has) { L @('add-wp', $prog, $wp, "agent=$agent", 'state=running') }
    L @('route', $prog, $agent, '-Owner', $owner, '-Note', 'n')
}
function Ack([string]$prog, [string]$agent) { L @('ack', $prog, $agent) }
function Enter([string]$sid, $proc, [string]$agents = '') {
    $a = @('-File', $tm, 'enter', '-Session', $sid, '-ClaudePid', "$($proc.Id)"); if ($agents) { $a += @('-Agents', $agents) }
    [void](RunPS $a)
}
function FlagPath([string]$sid) { Join-Path $d "tail\$sid.flag" }
function SetFlag([string]$sid, [scriptblock]$edit) { $f = FlagPath $sid; $j = Get-Content $f -Raw | ConvertFrom-Json; & $edit $j; [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))) }
function Pointer([string]$sid, [int]$procId) { [void](RunPS @('-File', $tm, 'current', 'set', '-Session', $sid, '-ClaudePid', "$procId")) }
function Msgs { @(Get-ChildItem -LiteralPath (Join-Path $d 'inbox\coordinator') -Filter '*.msg' -File | Sort-Object Name) }
function ClearInbox { Get-ChildItem -LiteralPath (Join-Path $d 'inbox\coordinator') -File | Remove-Item -Force }
function CloseLog { $f = Join-Path $d 'tail\closed.log'; if (Test-Path $f) { Get-Content $f -Raw } else { '' } }
try {
    foreach ($f in @($tm, $relay, $close, $ack, (Join-Path $auto 'session-start.ps1'), (Join-Path $auto 'coord-heartbeat.ps1'), $Guard)) {
        $err = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err)
        T (-not $err) "syntax $(Split-Path $f -Leaf)"
    }

    # =============== (A) coordinator.current pointer + relay target
    $coord = Dummy     # stands in for the live coordinator process
    $tailp = Dummy     # stands in for a tail session's claude process
    RouteAgent 'tp' 'w1' 'a1' 'tail:T1'
    Status 'a1' 'DONE'; Ack 'tp' 'a1'
    Enter 'T1' $tailp 'a1'
    $fl = Get-Content (FlagPath 'T1') -Raw | ConvertFrom-Json
    T ($fl.proc_name -eq 'powershell' -and $fl.proc_start -and [Math]::Abs(([datetimeoffset]::Parse($fl.proc_start).UtcDateTime - (Get-Process -Id $tailp.Id).StartTime.ToUniversalTime()).TotalSeconds) -lt 2) 'enter records proc_name + proc_start of the claude pid'
    $o = (RunPS @('-File', $tm, 'current')) -join "`n"
    T ($o -match 'no usable coordinator.current') 'current: no pointer yet'
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'no pointer')) -join "`n"
    T ($o -notmatch '(?m)^to: ' -and $o -match 'relay target: none, inbox file only -- no coordinator.current pointer') 'pointer missing: old behaviour (inbox file only, no to: line), target printed'
    T ((Msgs).Count -eq 1) 'pointer missing: inbox file still written'
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x', '-ToSession', 'OLDC')) -join "`n"
    T ($o -match '(?m)^to: OLDC' -and $o -match 'relay target: OLDC') 'pointer missing + -ToSession: kept as given'
    [IO.File]::WriteAllText((Join-Path $d 'coordinator.current'), '{ not json')
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x')) -join "`n"
    T ($o -match 'inbox file only') 'garbage pointer = missing (fallback, no error)'
    ClearInbox
    $o = (RunPS @('-File', $tm, 'current', 'set', '-Session', 'NEWC', '-ClaudePid', "$($coord.Id)", '-Name', 'coord B')) -join "`n"
    T ($o -match 'coordinator.current: session NEWC pid') 'current set writes the pointer'
    $pj = Get-Content (Join-Path $d 'coordinator.current') -Raw | ConvertFrom-Json
    T ($pj.session -eq 'NEWC' -and $pj.pid -eq $coord.Id -and $pj.name -eq 'coord B' -and $pj.started -and $pj.updated) 'pointer JSON has session/pid/name/started/updated'
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'to default')) -join "`n"
    T ($o -match '(?m)^to: NEWC' -and $o -match 'relay target: NEWC -- current coordinator') 'no -ToSession: relay goes to the current coordinator'
    $m = Msgs
    T ($m.Count -eq 1 -and (Get-Content $m[0].FullName -Raw) -match '(?m)^to: NEWC') 'the shared inbox file is written too (names the target)'
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x', '-ToSession', 'T1')) -join "`n"
    T ($o -match '(?m)^to: NEWC' -and $o -match 'redirected to the current coordinator') '-ToSession is itself a tail session: redirected to the current coordinator'
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x', '-ToSession', 'SOMEONE')) -join "`n"
    T ($o -match '(?m)^to: SOMEONE') '-ToSession of an ordinary (non-tail) session is kept'
    # pointer names a dead coordinator / a tail
    Pointer 'DEADC' 2147480000
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x')) -join "`n"
    T ($o -match 'inbox file only' -and $o -match 'not alive') 'pointer with a dead process: not used (inbox only)'
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x', '-ToSession', 'DEADC')) -join "`n"
    T ($o -match '(?m)^to: DEADC' -and $o -match 'no usable current coordinator') 'dead requested target and no usable pointer: kept, with a warning reason'
    Pointer 'T1' $tailp.Id
    T ((Get-Content (Join-Path $d 'coordinator.current') -Raw) -match 'DEADC') 'current set refuses to write a tail session as the coordinator'
    $pj = Get-Content (Join-Path $d 'coordinator.current') -Raw | ConvertFrom-Json
    [IO.File]::WriteAllText((Join-Path $d 'coordinator.current'), (@{ session = 'T1'; pid = $tailp.Id; name = 'x'; started = (Get-Date).ToString('o') } | ConvertTo-Json))
    $o = (RunPS @('-File', $relay, '-Agent', 'a1', '-Kind', 'STALL', '-Summary', 'x')) -join "`n"
    T ($o -match 'inbox file only' -and $o -match 'itself a tail session') 'pointer that is itself a tail session: not used'
    Pointer 'NEWC' $coord.Id
    # a dead target session ID given explicitly that equals the (dead) pointer is redirected when another live coordinator is known: covered by tail flag case above

    # adopt
    $t2 = Dummy
    RouteAgent 'tp' 'w2' 'a2' 'tail:T2'; Status 'a2' 'RUNNING'
    Enter 'T2' $t2 'a2'
    $deadF = FlagPath 'TDEAD'
    [IO.File]::WriteAllText($deadF, (@{ session = 'TDEAD'; pid = 2147480000; created = (Get-Date).ToString('o'); new_coordinator_inbox = (Join-Path $d 'inbox\coordinator'); agents = @('zz') } | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $o = (RunPS @('-File', $tm, 'adopt')) -join "`n"
    T ($o -match 'ADOPT: 2 live tail\(s\) now relay to coordinator NEWC' -and $o -match 'tail TDEAD: DEAD, skipped') 'adopt: every live tail now relays to the current coordinator, dead tail skipped'
    T ((Get-Content (FlagPath 'T2') -Raw | ConvertFrom-Json).relay_to -eq 'NEWC' -and (Get-Content (FlagPath 'T1') -Raw | ConvertFrom-Json).relay_to -eq 'NEWC') 'adopt writes relay_to into the tail flags'
    $recs = @((RunPS @('-File', $ledger, 'records')) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ })
    T (($recs | Where-Object { $_.agent -eq 'a2' }).owner_session -eq 'tail:T2') 'adopt leaves the ledger owner as tail:<id> (only the relay target changes)'
    $o = (RunPS @('-File', $tm, 'list')) -join "`n"
    T ($o -match 'relays go to coordinator NEWC') 'list shows the adopted relay target'
    $o = (RunPS @('-File', $tm, 'adopt', '-Session', 'T1')) -join "`n"
    T ($o -match 'refusing') 'adopt refuses a tail session as the coordinator'
    # relay_to is the fallback when the pointer is unusable
    Remove-Item (Join-Path $d 'coordinator.current')
    $o = (RunPS @('-File', $tm, 'target', '-Agent', 'a2')) -join "`n"
    T ($o -match 'relay target: NEWC -- relay_to of the owning tail flag') 'pointer gone: the adopted relay_to of the owning flag is used'
    $o = (RunPS @('-File', $tm, 'target', '-Agent', 'nobody')) -join "`n"
    T ($o -match 'none: inbox file only') 'pointer gone + agent not owned: inbox only'
    # current set -Auto rules (session-start)
    $env:KAH_COORD_SESSION = 'CC1'
    $o = (RunPS @('-File', $tm, 'current', 'set', '-Auto')) -join "`n"
    T ((Get-Content (Join-Path $d 'coordinator.current') -Raw | ConvertFrom-Json).session -eq 'CC1') 'current set -Auto uses KAH_COORD_SESSION'
    $env:KAH_COORD_SESSION = 'T1'
    $o = (RunPS @('-File', $tm, 'current', 'set', '-Auto')) -join "`n"
    T ($o -match 'is a tail session' -and (Get-Content (Join-Path $d 'coordinator.current') -Raw | ConvertFrom-Json).session -eq 'CC1') 'current set -Auto never writes a tail session'
    $env:KAH_COORD_SESSION = 'AG1'; $env:KAH_AGENT_NAME = 'wpX'
    [void](RunPS @('-File', $tm, 'current', 'set', '-Auto'))
    T ((Get-Content (Join-Path $d 'coordinator.current') -Raw | ConvertFrom-Json).session -eq 'CC1') 'current set -Auto is a no-op for an independent agent session'
    Remove-Item Env:KAH_COORD_SESSION, Env:KAH_AGENT_NAME
    # session-start lists the adopt + relay target
    $env:KAH_COORD_SESSION = 'NEWC2'
    $o = (RunPS @('-File', (Join-Path $auto 'session-start.ps1'), '-Brief', '-AgentsOnly')) -join "`n"
    Remove-Item Env:KAH_COORD_SESSION
    T ($o -match 'COORDINATOR POINTER: coordinator.current: session NEWC2' -and $o -match 'ADOPT: 2 live tail\(s\) now relay to coordinator NEWC2' -and $o -match 'tail T2: relays of a2 now go to NEWC2') 'session-start writes the pointer and lists the adopt result'
    T ($o -match 'TAIL T2 LIVE .*relays go to NEWC2') 'session-start TAIL line names the relay target'
    Remove-Item (FlagPath 'TDEAD') -Force
    Pointer 'NEWC' $coord.Id

    # =============== (B) tail-close safety
    # T2 still has a RUNNING agent -> never closed
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'NOT closing' -and $o -match 'a2 \[running\]' -and (Alive $t2) -and (Test-Path (FlagPath 'T2'))) 'unacked/running agent: not closed (process alive, flag kept)'
    Status 'a2' 'DONE'      # done but NOT acknowledged
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'NOT closing' -and $o -match 'not acknowledged' -and (Alive $t2)) 'finished but unacknowledged agent: not closed'
    T ((CloseLog) -match 'REFUSED session=T2') 'refusals are logged to closed.log'
    Ack 'tp' 'a2'
    # dry run: nothing killed
    ClearInbox
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DryRun')) -join "`n"
    Start-Sleep -Seconds 2
    T ($o -match 'DRY-RUN: would relay TAIL-DONE' -and $o -match "pid $($t2.Id)" -and (Alive $t2) -and (Test-Path (FlagPath 'T2')) -and (CloseLog) -match 'DRYRUN session=T2') 'dry-run prints the plan, kills nothing, logs DRYRUN'
    T ((Msgs).Count -eq 0) 'dry-run sends no TAIL-DONE message'
    # process identity mismatch (pid reuse guards)
    SetFlag 'T2' { param($j) $j.proc_start = (Get-Date).AddHours(-3).ToUniversalTime().ToString('o') }
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'start time mismatch' -and (Alive $t2) -and (Test-Path (FlagPath 'T2'))) 'start-time mismatch: not closed'
    SetFlag 'T2' { param($j) $j.proc_start = (Get-Process -Id $t2.Id).StartTime.ToUniversalTime().ToString('o'); $j.proc_name = 'explorer' }
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'name mismatch' -and (Alive $t2)) 'process-name mismatch: not closed'
    SetFlag 'T2' { param($j) $j.proc_name = 'powershell' }
    # never the coordinator: pointer pid / pointer session / heartbeat owner
    Pointer 'NEWC' $t2.Id
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'CURRENT coordinator' -and (Alive $t2)) 'pointer pid == tail pid: never closed'
    Pointer 'T2' $coord.Id   # refused write (T2 is a tail), so craft the pointer by hand
    [IO.File]::WriteAllText((Join-Path $d 'coordinator.current'), (@{ session = 'T2'; pid = $coord.Id; name = 'x'; started = (Get-Date).ToString('o') } | ConvertTo-Json))
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'CURRENT coordinator' -and (Alive $t2)) 'pointer session == tail session: never closed'
    Pointer 'NEWC' $coord.Id
    Set-Content (Join-Path $d 'coordinator.heartbeat') -Value '1000 T2 2026-10-15'
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'owns the coordinator heartbeat' -and (Alive $t2)) 'heartbeat owner: never closed'
    Set-Content (Join-Path $d 'coordinator.heartbeat') -Value '1000 NEWC 2026-10-15'
    # tail flag whose pid is the CURRENT coordinator's process (even with a different session id)
    $cf = Dummy
    RouteAgent 'tp' 'w9' 'a9' 'tail:TC'; Status 'a9' 'DONE'; Ack 'tp' 'a9'
    Enter 'TC' $cf 'a9'
    Pointer 'NEWC' $cf.Id
    $o = (RunPS @('-File', $close, '-Session', 'TC', '-DelaySec', '1')) -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match 'CURRENT coordinator' -and (Alive $cf)) 'coordinator.current pid == flag pid: never closed'
    Pointer 'NEWC' $coord.Id
    # no flag / unreadable flag
    $o = (RunPS @('-File', $close, '-Session', 'NOFLAG', '-DelaySec', '1')) -join "`n"
    T ($o -match 'no tail flag') 'no flag: nothing to close'
    [IO.File]::WriteAllText((FlagPath 'BAD'), '{ nope')
    $o = (RunPS @('-File', $close, '-Session', 'BAD', '-DelaySec', '1')) -join "`n"
    T ($o -match 'unreadable') 'unreadable flag: refused'
    Remove-Item (FlagPath 'BAD') -Force
    # zero agents: only after the flag is old enough
    $z = Dummy
    Enter 'TZ' $z
    $o = (RunPS @('-File', $close, '-Session', 'TZ', '-DryRun')) -join "`n"
    T ($o -match 'no agents and is younger') 'flag with no agents, just created: not closable yet'
    SetFlag 'TZ' { param($j) $j.created = (Get-Date).AddMinutes(-30).ToString('o') }
    $o = (RunPS @('-File', $close, '-Session', 'TZ', '-DryRun')) -join "`n"
    T ($o -match 'DRY-RUN: would') 'flag with no agents, old enough: closable'
    Remove-Item (FlagPath 'TZ') -Force
    # worker re-check: agent un-acked between schedule and kill -> nothing killed
    ClearInbox
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '4')) -join "`n"
    T ($o -match 'closes in 4 s') 'T2 scheduled (4 s delay)'
    Start-Sleep -Milliseconds 800
    RouteAgent 'tp' 'w2' 'a2' 'tail:T2'     # re-route resets the ack
    Start-Sleep -Seconds 7
    T ((Alive $t2) -and (Test-Path (FlagPath 'T2')) -and (CloseLog) -match 'REFUSED-AT-KILL session=T2') 'worker re-checks at kill time: an agent un-acked in the delay window stops the close'
    Remove-Item (Join-Path $d 'tail\T2.closing') -Force -ErrorAction SilentlyContinue
    Ack 'tp' 'a2'

    # =============== (C) the real close: TAIL-DONE message, delayed kill of the matching process, flag removed
    ClearInbox
    $o = (RunPS @('-File', $close, '-Session', 'T2', '-DelaySec', '1')) -join "`n"
    T ($o -match 'TAIL-RELAY tail-T2 TAILDONE' -and $o -match '(?m)^TAIL-DONE T2' -and $o -match 'finished all agents, closing' -and $o -match 'relay target: NEWC') 'close prints the TAIL-DONE text (for SendMessage) and its target'
    $m = Msgs
    T ($m.Count -eq 1 -and (Get-Content $m[0].FullName -Raw) -match '(?m)^TAIL-DONE T2' -and (Get-Content $m[0].FullName -Raw) -match '(?m)^to: NEWC') 'TAIL-DONE inbox message written, addressed to the current coordinator'
    T (WaitDead $t2) 'the matching dummy claude process is closed after the delay'
    Start-Sleep -Seconds 1
    T (-not (Test-Path (FlagPath 'T2'))) 'the tail flag is removed after the process is gone'
    T ((CloseLog) -match 'SCHEDULED session=T2' -and (CloseLog) -match 'CLOSED session=T2') 'SCHEDULED + CLOSED logged'
    T ((Alive $coord) -and (Alive $tailp)) 'other processes (coordinator, other tail) untouched'
    # a second call right away does not stack workers
    # process already gone + all acked: flag just removed
    RouteAgent 'tp' 'w3' 'a3' 'tail:T3'; Status 'a3' 'DONE'; Ack 'tp' 'a3'
    $g = Dummy; Enter 'T3' $g 'a3'; Stop-Process -Id $g.Id -Force; Start-Sleep -Milliseconds 500
    $o = (RunPS @('-File', $close, '-Session', 'T3')) -join "`n"
    T ($o -match 'already gone; flag removed' -and -not (Test-Path (FlagPath 'T3'))) 'process already gone and all acked: only the flag is removed'

    # =============== (D) tail-ack auto-close
    $t4 = Dummy
    RouteAgent 'tp' 'w4' 'a4' 'tail:T4'; RouteAgent 'tp' 'w5' 'a5' 'tail:T4'
    Status 'a4' 'DONE'; Status 'a5' 'DONE'
    Enter 'T4' $t4 'a4,a5'
    $env:KAH_TAIL_CLOSE_DELAY = '1'
    $o = (RunPS @('-File', $ack, '-Agent', 'a4')) -join "`n"
    Start-Sleep -Seconds 2
    T ($o -match 'tail T4: still waiting for a5' -and (Alive $t4)) 'tail-ack of a non-last agent: tail kept, says what it waits for'
    $o = (RunPS @('-File', $ack, '-Agent', 'a5', '-NoClose')) -join "`n"
    Start-Sleep -Seconds 2
    T ($o -match 'all agents done\+acked. Close it with: tail-close.ps1' -and (Alive $t4)) 'tail-ack -NoClose: only the hint'
    L @('route', 'tp', 'a5', '-Owner', 'tail:T4', '-Note', 'n')
    $o = (RunPS @('-File', $ack, '-Agent', 'a5', '-DryRunClose')) -join "`n"
    T ($o -match 'DRY-RUN' -and (Alive $t4)) 'tail-ack -DryRunClose: previews, kills nothing'
    ClearInbox
    $o = (RunPS @('-File', $ack, '-Agent', 'a5')) -join "`n"
    T ($o -match 'all agents done\+acked -> closing the finished tail session' -and $o -match 'closes in 1 s') 'tail-ack of the LAST agent triggers tail-close'
    T (WaitDead $t4) 'tail-ack auto-close ends the finished tail process'
    T ((Msgs).Count -eq 0) 'ack-triggered close sends no TAIL-DONE (the coordinator itself acked)'

    # =============== (E) Stop hook trigger (candidate or live hook given by -Guard)
    function GuardRun([string]$sid) {
        $json = (@{ session_id = $sid; cwd = 'C:\KenshiModding'; hook_event_name = 'Stop'; stop_hook_active = $false } | ConvertTo-Json -Compress)
        return @(RunPS @('-File', $Guard, 'stop') $json)
    }
    $t5 = Dummy
    RouteAgent 'tp' 'w6' 'a6' 'tail:T5'; Status 'a6' 'DONE'
    Enter 'T5' $t5 'a6'
    $o = (GuardRun 'T5') -join "`n"
    Start-Sleep -Seconds 3
    T ($o -match '"decision":"block"' -and (Alive $t5)) 'hook: unacked agent -> Stop blocked, tail process kept'
    Ack 'tp' 'a6'
    $env:KAH_TAIL_NO_CLOSE = '1'
    $o = (GuardRun 'T5') -join "`n"
    Start-Sleep -Seconds 3
    T ($o.Trim() -eq '' -and (Alive $t5)) 'hook: KAH_TAIL_NO_CLOSE=1 -> Stop allowed, nothing closed'
    Remove-Item Env:KAH_TAIL_NO_CLOSE
    ClearInbox
    $o = (GuardRun 'T5') -join "`n"
    T ($o.Trim() -eq '') 'hook: all done+acked -> Stop allowed with no output'
    T (WaitDead $t5) 'hook: the allowed-to-end tail is closed automatically (TAIL-DONE + delayed kill)'
    T (((Msgs) | Where-Object { (Get-Content $_.FullName -Raw) -match '(?m)^TAIL-DONE T5' }).Count -eq 1) 'hook: TAIL-DONE message reached the coordinator inbox'
    Start-Sleep -Seconds 1
    T (-not (Test-Path (FlagPath 'T5'))) 'hook: flag removed'
    T ((CloseLog) -match 'CLOSED session=T5 source=hook') 'hook: close logged with source=hook'
    T ((Alive $coord)) 'coordinator dummy never touched'
} finally {
    foreach ($p in $dummies) { try { if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch { } }
    foreach ($k in $old.Keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item -LiteralPath "Env:$k" -Value $old[$k] } }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT tail-close $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
