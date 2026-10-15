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
    Remove-Item Env:KAH_RUNS_DIR, Env:KCS_RUNS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fails) { "RESULT tail-hooks FAIL ($($script:fails))"; exit 1 } else { 'RESULT tail-hooks PASS'; exit 0 }
