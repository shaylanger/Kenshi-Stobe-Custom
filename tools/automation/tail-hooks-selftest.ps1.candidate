# tail-hooks-selftest.ps1: selftest of the overlap ("tail") handoff tooling of WP-T1 (docs/TAIL_HANDOFF_CONTRACT.md):
# tail-mode.ps1 (enter/status/leave/list), the waker-guard Stop hook for tail sessions, the heartbeat (tail never beats), the
# context meter (300k handoff, quiet for a tail, 400k tail hard limit), the handoff-ready/supervisor syntax and the supervisor selftest.
# Everything runs against a temp runs dir (KAH_RUNS_DIR / KCS_RUNS); no real flag, heartbeat or status file is touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\tail-hooks-selftest.ps1   (exit 0 = PASS)
$ErrorActionPreference = 'Stop'
$auto = $PSScriptRoot
$ws = Split-Path (Split-Path $auto)
$script:fails = 0
function T([bool]$ok, [string]$n) { if ($ok) { "PASS $n" } else { "FAIL $n"; $script:fails++ } }
$tm = Join-Path $auto 'tail-mode.ps1'
$guard = Join-Path $auto 'hooks\kenshi-waker-guard.ps1'
$hbs = Join-Path $auto 'coord-heartbeat.ps1'
$meter = Join-Path $env:USERPROFILE '.claude\hooks\context-meter.ps1'
$d = Join-Path ([IO.Path]::GetTempPath()) ("tailself-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'programs'), (Join-Path $d 'agents') | Out-Null
$env:KAH_RUNS_DIR = $d; $env:KCS_RUNS = $d
$env:KAH_TAIL_NO_CLOSE = '1'   # the Stop hook closes finished tails (tail-close.ps1); these flags use the selftest's own pid
Remove-Item Env:KAH_AGENT_NAME -ErrorAction SilentlyContinue
function RunPS([string[]]$a, [string]$stdin = '') {
    if ($stdin) { return @($stdin | & powershell -NoProfile -ExecutionPolicy Bypass @a 2>&1 | ForEach-Object { "$_" }) }
    return @(& powershell -NoProfile -ExecutionPolicy Bypass @a 2>&1 | ForEach-Object { "$_" })
}
function Status([string]$name, [string]$state) { Set-Content -LiteralPath (Join-Path $d "agents\$name.status") -Value @("$name | $state | d", 'task: T') }
function Ledger([string]$json) { Set-Content -LiteralPath (Join-Path $d 'programs\p.json') -Value $json }
try {
    # --- syntax of every changed script
    foreach ($f in @($tm, $guard, $hbs, (Join-Path $auto 'coord-supervisor.ps1'), (Join-Path $auto 'handoff-ready.ps1'), (Join-Path $ws '.claude\context-meter.project.ps1'), $meter)) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $err = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err)
        T (-not $err) "syntax $(Split-Path $f -Leaf)"
    }

    # --- tail-mode.ps1 CLI
    Ledger '{"name":"p","wps":[{"id":"w1","agent_records":{"a1":{"owner_session":"tail:S1","acked_by_new_coordinator":false},"a2":{"owner_session":"live"}}}],"agents":[{"agent":"a3","owner_session":"tail:S1","acked_by_new_coordinator":true}]}'
    Status 'a1' 'RUNNING'; Status 'a3' 'DONE'
    $o = RunPS @('-File', $tm, 'enter', '-Session', 'S1', '-ClaudePid', "$PID", '-Agents', 'zz')
    $fp = Join-Path $d 'tail\S1.flag'
    T (Test-Path $fp) 'enter writes tail\S1.flag'
    $j = Get-Content $fp -Raw | ConvertFrom-Json
    T ($j.session -eq 'S1' -and $j.pid -eq $PID -and $j.created -and $j.new_coordinator_inbox -like '*inbox\coordinator') 'flag has session/pid/created/inbox'
    T ((@($j.agents) | Sort-Object) -join ',' -eq 'a1,a3,zz') 'flag agents = -Agents + ledger owner tail:S1 (a2 owned by live is excluded)'
    $o = RunPS @('-File', $tm, 'status', '-Session', 'S1')
    T (($o -join "`n") -match 'LIVE' -and ($o -join "`n") -match 'agent a1: status=RUNNING' -and ($o -join "`n") -match 'stop allowed: False') 'status: LIVE, agents, stop not allowed'
    $o = RunPS @('-File', $tm, 'leave', '-Session', 'S1')
    T (($o -join "`n") -match 'REFUSED' -and (Test-Path $fp)) 'leave refuses while agents pending'
    $o = RunPS @('-File', $tm, 'list')
    T (($o -join "`n") -match 'tail session S1' -and ($o -join "`n") -match 'LIVE') 'list shows the live tail'
    # dead tail
    [void](RunPS @('-File', $tm, 'enter', '-Session', 'S2', '-ClaudePid', '2147480000', '-Agents', 'a1'))
    $o = RunPS @('-File', $tm, 'list')
    T (($o -join "`n") -match 'tail session S2 pid 2147480000 DEAD' -and ($o -join "`n") -match 'DEAD TAIL: process gone, agents a1') 'list flags the dead tail with its agents (respawn from checkpoints)'
    [void](RunPS @('-File', $tm, 'leave', '-Session', 'S2', '-Force'))
    T (-not (Test-Path (Join-Path $d 'tail\S2.flag'))) 'leave -Force removes the flag'

    # --- waker-guard Stop hook
    function Guard([string]$sid, [bool]$active = $false) {
        $json = (@{ session_id = $sid; cwd = 'C:\KenshiModding'; hook_event_name = 'Stop'; stop_hook_active = $active } | ConvertTo-Json -Compress)
        return (RunPS @('-File', $guard, 'stop') $json)
    }
    $o = (Guard 'S1') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'TAIL session' -and $o -match 'a1 \[running\]' -and $o -match 'zz') 'guard: tail with running/unacked agents -> Stop blocked with a clear message'
    $o = (Guard 'S1' $true) -join "`n"
    T ($o -match '"decision":"block"') 'guard: tail block ignores stop_hook_active (blocked every time)'
    # all done + acked: ledger acks, statuses terminal
    Status 'a1' 'DONE'
    Ledger '{"name":"p","agents":{"a1":{"owner_session":"tail:S1","acked_by_new_coordinator":true},"a3":{"owner_session":"tail:S1","acked_by_new_coordinator":true},"zz":{"owner_session":"tail:S1","acked_by_new_coordinator":true}}}'
    $o = (Guard 'S1') -join "`n"
    T ($o.Trim() -eq '') 'guard: all agents done AND acked -> tail may end (no idle-rig/handoff/waker rules)'
    # done but NOT acked
    Ledger '{"name":"p","agents":{"a1":{"owner_session":"tail:S1","acked_by_new_coordinator":false},"a3":{"owner_session":"tail:S1","acked_by_new_coordinator":true},"zz":{"owner_session":"tail:S1","acked_by_new_coordinator":true}}}'
    $o = (Guard 'S1') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'a1 \[DONE, not acknowledged\]') 'guard: finished but unacknowledged agent still blocks'
    # --- PI-18 A: a finished agent does not hold the tail on the explicit ack (relay delivered, or 5 min after the relay was written)
    $inbox = Join-Path $d 'inbox\coordinator'
    New-Item -ItemType Directory -Force -Path (Join-Path $inbox 'delivered') | Out-Null
    function Age([string]$path, [double]$minutesAgo) { (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddMinutes(-$minutesAgo) }
    function RelayFile([string]$agent, [double]$minutesAgo, [bool]$delivered) {
        $p = Join-Path $(if ($delivered) { Join-Path $inbox 'delivered' } else { $inbox }) ("20261015-120000-tail-$agent.msg")
        Set-Content -LiteralPath $p -Value "TAIL-RELAY $agent DONE x"; Age $p $minutesAgo; return $p
    }
    [void](RunPS @('-File', $tm, 'enter', '-Session', 'S4', '-ClaudePid', "$PID", '-Agents', 'r1'))
    Ledger '{"name":"p","agents":{"r1":{"owner_session":"tail:S4","acked_by_new_coordinator":false}}}'
    Status 'r1' 'DONE'; Age (Join-Path $d 'agents\r1.status') 7
    $o = (Guard 'S4') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'r1 \[DONE, not acknowledged\]' -and $o -match 'not relayed yet') 'PI-18 A: DONE + no relay file written -> still blocks (not relayed yet)'
    $rf = RelayFile 'r1' 2 $false
    $o = (Guard 'S4') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'ack grace ends in') 'PI-18 A: DONE + undelivered relay written 2 min ago -> blocks inside the 5 min grace'
    Age $rf 6
    $o = (Guard 'S4') -join "`n"
    T ($o.Trim() -eq '') 'PI-18 A: undelivered relay older than 5 min -> tail may end without the ack'
    Remove-Item -LiteralPath $rf
    $rf = RelayFile 'r1' 1 $true
    $o = (Guard 'S4') -join "`n"
    T ($o.Trim() -eq '') 'PI-18 A: relay file delivered (moved to delivered\) -> tail may end without the ack'
    Age $rf 30   # relay written before the agent finished = an earlier run of a same-named agent
    Status 'r1' 'DONE'
    $o = (Guard 'S4') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'not relayed yet') 'PI-18 A: a delivered relay from BEFORE the agent DONE does not release it'
    Remove-Item -LiteralPath $rf
    $rf = RelayFile 'r1' 1 $true
    Status 'r1' 'RUNNING'
    $o = (Guard 'S4') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'r1 \[running\]') 'PI-18 A: a RUNNING owned agent still blocks even with a delivered relay file'
    Status 'r1' 'FAILED'; Age (Join-Path $d 'agents\r1.status') 3
    $o = (Guard 'S4') -join "`n"
    T ($o.Trim() -eq '') 'PI-18 A: FAILED agent with a delivered relay -> tail may end'
    Remove-Item -LiteralPath $rf
    Ledger '{"name":"p","agents":{"r1":{"owner_session":"tail:S4","acked_by_new_coordinator":true}}}'
    $o = (Guard 'S4') -join "`n"
    T ($o.Trim() -eq '') 'PI-18 A: explicit ack in the ledger still releases the tail (unchanged)'
    $o = (RunPS @('-File', $tm, 'status', '-Session', 'S4')) -join "`n"
    T ($o -match 'r1') 'PI-18 A: tail-mode status still works'

    # --- PI-18 C: capped Stop blocks (message from the 4th unchanged block, tail let end after the 6th, count restarts on a change)
    [void](RunPS @('-File', $tm, 'enter', '-Session', 'S5', '-ClaudePid', "$PID", '-Agents', 'c1'))
    Ledger '{"name":"p","agents":{"c1":{"owner_session":"tail:S5","acked_by_new_coordinator":false}}}'
    Status 'c1' 'RUNNING'
    $outs = @(); for ($i = 1; $i -le 6; $i++) { $outs += ((Guard 'S5') -join "`n") }
    T (@($outs | Where-Object { $_ -match '"decision":"block"' }).Count -eq 6) 'PI-18 C: blocks 1-6 are all blocked'
    T (@($outs[0..2] | Where-Object { $_ -match 'ONE long background wait' }).Count -eq 0) 'PI-18 C: blocks 1-3 carry no wait advice'
    T ($outs[3] -match 'ONE long background wait' -and $outs[3] -match 'do not reply per block' -and $outs[5] -match 'ONE long background wait') 'PI-18 C: blocks 4-6 say to wait with ONE long background wait'
    $o = (Guard 'S5') -join "`n"
    T ($o.Trim() -eq '' -and (Test-Path (Join-Path $d 'tail\cap-ends.log')) -and ((Get-Content (Join-Path $d 'tail\cap-ends.log') -Raw) -match 'session=S5')) 'PI-18 C: the 7th unchanged attempt is let through and logged in cap-ends.log'
    $o = (Guard 'S5') -join "`n"
    T ($o.Trim() -eq '') 'PI-18 C: later attempts with the same pending set keep passing'
    Status 'c1' 'DONE'   # pending set changes (running -> done, unacked, unrelayed): count restarts
    $o = (Guard 'S5') -join "`n"
    T ($o -match '"decision":"block"' -and $o -notmatch 'ONE long background wait') 'PI-18 C: a changed pending set restarts the count (blocked again, no wait advice yet)'
    # the cap never touches a non-tail session or a tail with nothing pending
    $o = (Guard 'OTHER2' $true) -join "`n"
    T ($o.Trim() -eq '') 'PI-18 C: a non-tail session is unchanged'

    # --- PI-28 (+PI-27): an ARMED, provably alive tail-wait.ps1 lets a tail's turn END; no wait / dead pid / stale heartbeat / error = blocked as before
    $script:waitProcs = @()
    $tw = Join-Path $auto 'tail-wait.ps1'
    $twLib = Join-Path $auto 'tail-wait-lib.ps1'
    foreach ($f in @($tw, $twLib)) { $err = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err); T (-not $err) "syntax $(Split-Path $f -Leaf)" }
    function StartWait([string]$sess) {
        $wfile = Join-Path $d "tail\$sess.wait"
        Remove-Item -LiteralPath $wfile -Force -ErrorAction SilentlyContinue
        $pr = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tw, '-Session', $sess, '-IntervalSec', '15') -PassThru -WindowStyle Hidden
        $script:waitProcs += $pr
        for ($i = 0; $i -lt 60 -and -not (Test-Path -LiteralPath $wfile); $i++) { Start-Sleep -Milliseconds 250 }
        return $pr
    }
    function WaitJson([string]$sess) { Get-Content -LiteralPath (Join-Path $d "tail\$sess.wait") -Raw | ConvertFrom-Json }
    function SetWait([string]$sess, [string]$field, [string]$value) {
        $j = WaitJson $sess; $j.$field = $value
        [IO.File]::WriteAllText((Join-Path $d "tail\$sess.wait"), ($j | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
    [void](RunPS @('-File', $tm, 'enter', '-Session', 'SW', '-ClaudePid', "$PID", '-Agents', 'w1'))
    Ledger '{"name":"p","agents":{"w1":{"owner_session":"tail:SW","acked_by_new_coordinator":false}}}'
    Status 'w1' 'RUNNING'
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'tail-wait\.ps1 -Session SW' -and $o -match 'Never reply to this block') 'PI-28: no wait armed -> blocked, message names tail-wait.ps1 and says never reply per block'
    $o = (Guard 'SW') -join "`n"
    T ((Get-Content (Join-Path $d 'tail\SW.blocks') -Raw | ConvertFrom-Json).count -eq 2) 'PI-28: unarmed blocks still count toward the PI-18 cap'
    $wp1 = StartWait 'SW'
    T (Test-Path (Join-Path $d 'tail\SW.wait')) 'PI-28: tail-wait.ps1 registers <session>.wait'
    $o = (Guard 'SW') -join "`n"
    T ($o.Trim() -eq '') 'PI-28: armed alive wait, owned agent RUNNING -> turn may end (no block output)'
    $outs = @(); for ($i = 0; $i -lt 8; $i++) { $outs += ((Guard 'SW') -join "`n").Trim() }
    T (@($outs | Where-Object { $_ -ne '' }).Count -eq 0 -and (Get-Content (Join-Path $d 'tail\SW.blocks') -Raw | ConvertFrom-Json).count -eq 2) 'PI-28: 8 more armed Stops all pass and do not touch the block counter'
    Status 'w1' 'DONE'
    # cheap tail (2026-10-16): a JUST finished agent is inside the auto-relay window (the model is not needed); the wait relays it itself
    $o = (Guard 'SW') -join "`n"
    T ($o.Trim() -eq '') 'cheap tail: armed wait, owned agent finished 0 min ago and not relayed yet (auto-relay window) -> turn may end'
    Age (Join-Path $d 'agents\w1.status') 4   # still unrelayed after the 3 min retry window = genuinely missing
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"' -and $o -match 'w1') 'PI-28: armed wait but an owned agent finished 4 min ago and is still not relayed (needs the tail) -> still blocked'
    Age (Join-Path $d 'agents\w1.status') 7
    $rf = RelayFile 'w1' 2 $false
    $o = (Guard 'SW') -join "`n"
    T ($o.Trim() -eq '') 'PI-28: armed wait, agent DONE with relay written 2 min ago (only delivery/grace pending) -> may end'
    Remove-Item -LiteralPath $rf -Force; Status 'w1' 'RUNNING'
    # a wait of ANOTHER session does not help this one
    [void](RunPS @('-File', $tm, 'enter', '-Session', 'SW2', '-ClaudePid', "$PID", '-Agents', 'w1'))
    $o = (Guard 'SW2') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: a second tail without its own wait is blocked while SW has one'
    Copy-Item (Join-Path $d 'tail\SW.wait') (Join-Path $d 'tail\SW2.wait')
    $o = (Guard 'SW2') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: another sessions wait file copied under this session id (session/command-line mismatch) -> blocked'
    Remove-Item (Join-Path $d 'tail\SW2.wait') -Force
    # armed before the tail started
    $flagCreated = [string](Get-Content (Join-Path $d 'tail\SW.flag') -Raw | ConvertFrom-Json).created
    SetWait 'SW' 'armed' ([datetimeoffset]::Parse($flagCreated).AddHours(-1).ToString('o'))
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: wait armed before the tail flag was created -> blocked'
    # stale heartbeat (the live wait beats every 15 s: set it stale and check at once)
    $wp1.Kill(); $wp1.WaitForExit()
    $wp2 = StartWait 'SW'
    SetWait 'SW' 'hb' ((Get-Date).AddMinutes(-10).ToString('o'))
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: alive process but stale heartbeat -> blocked'
    # pid alive but it is not tail-wait.ps1 (the selftest's own powershell): command-line check
    $wp2.Kill(); $wp2.WaitForExit()
    $meProc = Get-Process -Id $PID
    $fake = [ordered]@{ session = 'SW'; pid = $PID; proc_start = $meProc.StartTime.ToString('o'); armed = (Get-Date).ToString('o'); hb = (Get-Date).ToString('o'); interval = 5; script = 'tail-wait.ps1' }
    [IO.File]::WriteAllText((Join-Path $d 'tail\SW.wait'), ($fake | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: live pid that is not this sessions tail-wait.ps1 (fresh heartbeat, right start time) -> blocked'
    # dead pid
    $wp3 = StartWait 'SW'
    $o = (Guard 'SW') -join "`n"
    T ($o.Trim() -eq '') 'PI-28: re-armed wait passes again'
    $wp3.Kill(); $wp3.WaitForExit()
    T (Test-Path (Join-Path $d 'tail\SW.wait')) 'PI-28: killed wait leaves its .wait file behind (the hook must not trust the file)'
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: wait process dead but file fresh -> blocked'
    # error: corrupt wait file
    Set-Content -LiteralPath (Join-Path $d 'tail\SW.wait') -Value '{ not json'
    $o = (Guard 'SW') -join "`n"
    T ($o -match '"decision":"block"') 'PI-28: corrupt wait file (error in the check) -> blocked (fail closed)'
    Remove-Item (Join-Path $d 'tail\SW.wait') -Force
    # the wait itself exits at once when the tail has something to do, and removes its file
    Status 'w1' 'DONE'; Age (Join-Path $d 'agents\w1.status') 4
    $env:KAH_TAILWAIT_NO_RETRY = '1'
    $out = @(RunPS @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tw, '-Session', 'SW', '-IntervalSec', '1'))
    Remove-Item Env:KAH_TAILWAIT_NO_RETRY
    T (($out -join "`n") -match 'TAIL-WAIT SW EXIT agent w1 needs the tail' -and -not (Test-Path (Join-Path $d 'tail\SW.wait'))) 'PI-27/28: tail-wait exits at once when an owned agent is DONE, unrelayed for > 3 min after the retry, and leaves no .wait file'
    Status 'w1' 'RUNNING'
    [void](RunPS @('-File', $tm, 'leave', '-Session', 'SW', '-Force')); [void](RunPS @('-File', $tm, 'leave', '-Session', 'SW2', '-Force'))
    # a non-tail session id with a .wait file lying around is unaffected (still the non-tail exit)
    [IO.File]::WriteAllText((Join-Path $d 'tail\NOTTAIL.wait'), ($fake | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $o = (Guard 'NOTTAIL' $true) -join "`n"
    T ($o.Trim() -eq '') 'PI-28: a non-tail (coordinator) session is unaffected by .wait files'

    # a non-tail session in the same runs dir is not treated as a tail (stop_hook_active => the existing once-per-turn exit)
    $o = (Guard 'OTHER' $true) -join "`n"
    T ($o.Trim() -eq '') 'guard: a non-tail session is unaffected by the tail flag of another session'
    # missing ledger / flag with no agents: tolerated
    Remove-Item (Join-Path $d 'programs\p.json')
    [void](RunPS @('-File', $tm, 'enter', '-Session', 'S3', '-ClaudePid', "$PID"))
    $o = (Guard 'S3') -join "`n"
    T ($o.Trim() -eq '') 'guard: tail flag with no agents and no ledger -> may end'

    # --- heartbeat: only the live coordinator beats
    $hbf = Join-Path $d 'coordinator.heartbeat'
    function Hook([string]$sid) { [void](RunPS @('-File', $hbs) (@{ session_id = $sid; tool_name = 'Bash'; tool_input = @{ command = 'echo hi' } } | ConvertTo-Json -Compress)) }
    Set-Content -LiteralPath $hbf -Value '1000 NEWC 2026-10-15'
    Hook 'S1'
    T ((Get-Content $hbf -Raw) -match '^1000 NEWC') 'heartbeat: a tail session does not beat (and cannot claim)'
    Hook 'NEWC'
    T ((Get-Content $hbf -Raw) -notmatch '^1000 ') 'heartbeat: the live coordinator beats'
    Set-Content -LiteralPath $hbf -Value '1000 S1 2026-10-15'
    [void](RunPS @('-File', $hbs, '-Beat'))
    T ((Get-Content $hbf -Raw) -match '^1000 S1') 'heartbeat: -Beat (event-wait) ignored while the owner is a tail session'
    Remove-Item (Join-Path $d 'tail\S1.flag')
    [void](RunPS @('-File', $hbs, '-Beat'))
    T ((Get-Content $hbf -Raw) -notmatch '^1000 S1') 'heartbeat: -Beat works again once the flag is gone'

    # --- context meter (user-level hook + project override)
    if (Test-Path -LiteralPath $meter) {
        $tr = Join-Path $d 'tr.jsonl'
        function Meter([int]$tokens, [string]$sid) {
            Set-Content -LiteralPath $tr -Value ('{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":' + $tokens + '}}}')
            $env:CLAUDE_PROJECT_DIR = $ws
            $r = RunPS @('-File', $meter) (@{ session_id = $sid; transcript_path = $tr; cwd = $ws; hook_event_name = 'PostToolUse' } | ConvertTo-Json -Compress)
            Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
            return ($r -join "`n")
        }
        T ((Meter 250000 'M1').Trim() -eq '') 'meter: silent at 250k (coordinator threshold raised from 200k)'
        $o = Meter 280000 'M1'
        T ($o -match 'overlap handoff at 300k') 'meter: warn at ~270k names the 300k overlap handoff'
        $o = Meter 310000 'M1'
        T ($o -match 'OVERLAP HANDOFF' -and $o -match 'tail-mode\.ps1 enter -Session M1' -and $o -match 'handoff-ready\.ps1' -and $o -match 'program-ledger\.ps1 route' -and $o -match 'tail-relay\.ps1') 'meter: handoff text at 300k describes the overlap flow with the session id'
        [void](RunPS @('-File', $tm, 'enter', '-Session', 'M1', '-ClaudePid', "$PID"))
        T ((Meter 310000 'M1').Trim() -eq '') 'meter: quiet for a session with a tail flag (310k)'
        T ((Meter 280000 'M1').Trim() -eq '') 'meter: quiet for a tail at the warn level'
        $o = Meter 410000 'M1'
        T ($o -match 'TAIL HARD LIMIT' -and $o -match 'leave -Session M1 -Force') 'meter: tail hard limit message at 400k'
        $env:KAH_AGENT_NAME = 'wpX'
        $o = Meter 210000 'M1'
        Remove-Item Env:KAH_AGENT_NAME
        T ($o -match 'independent agent session' -and $o -notmatch 'OVERLAP') 'meter: independent agent sessions keep the 200k agent handoff'
    } else { 'SKIP meter tests (no user-level context-meter.ps1)' }

    # --- supervisor selftest (tail cases 10a-g inside)
    $o = (RunPS @('-File', (Join-Path $auto 'coord-supervisor.ps1'), '-Selftest')) -join "`n"
    T ($o -match 'SELFTEST OK' -and $o -match 'PASS 10a' -and $o -match 'PASS 10c') 'supervisor selftest incl. tail cases'
} finally {
    foreach ($wpx in @($script:waitProcs)) { try { if (-not $wpx.HasExited) { $wpx.Kill() } } catch { } }
    Remove-Item Env:KAH_RUNS_DIR, Env:KCS_RUNS, Env:KAH_TAIL_NO_CLOSE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fails) { "RESULT tail-hooks FAIL ($($script:fails))"; exit 1 } else { 'RESULT tail-hooks PASS'; exit 0 }
