# alert-ledger-selftest.ps1 (PI-21): open-alert ledger. Fixture runs dir (KAH_RUNS_DIR) only; never touches C:\KenshiTestRuns.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\alert-ledger-selftest.ps1
# Cases: open (lane idle, agent stall msg, failed agent, llm), operator inbox file, rate limit, ack closes (+ no re-open, re-open after hold),
# auto-clear, lane-stalled hard alert (section 13: raised / healthy / cleared by evidence / ack needs proof / exclusions abandoned+held+no-game), Stop block at 5 min (and not at 2 min), loop cap, tail/subagent exempt, reminder is one line, hook JSON only for the coordinator.
$ErrorActionPreference = 'Stop'
$auto = $PSScriptRoot
$guard = Join-Path $auto 'hooks\kenshi-waker-guard.ps1'
$fails = 0
function T([bool]$ok, [string]$n) { if ($ok) { "PASS $n" } else { "FAIL $n"; $script:fails++ } }
$runs = Join-Path ([IO.Path]::GetTempPath()) ('alertledger-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$savedRuns = $env:KAH_RUNS_DIR
foreach ($d in 'agents', 'inbox\coordinator', 'inbox\operators', 'tail') { New-Item -ItemType Directory -Force -Path (Join-Path $runs $d) | Out-Null }
$env:KAH_RUNS_DIR = $runs
$env:KAH_LANE_STALL_MIN = '999'          # lane-stalled escalation off for the older cases (section 13 turns it on with 12)
$lanes = '5090-i3', '5090-i4', '5090-i5', '4080-i3', '4080-i4'
$ov = [ordered]@{}; foreach ($l in $lanes) { $ov[$l] = @{ ops = @("op-$l"); dirs = @("dir-$l") } }
[IO.File]::WriteAllText((Join-Path $runs 'lane-owners.json'), ($ov | ConvertTo-Json -Depth 4))
function New-Status([string]$name, [string]$state, [int]$minAgo, [string]$task = 'fixture task') {
    $p = Join-Path $runs "agents\$name.status"
    [IO.File]::WriteAllText($p, "$name | $state | 2026-10-15 20:00:00`r`ntask: $task`r`nlatest: fixture`r`n")
    (Get-Item $p).LastWriteTime = (Get-Date).AddMinutes(-$minAgo)
}
function Set-Stamp([int]$secAgo) { (Get-Item (Join-Path $runs 'alerts\scan.stamp')).LastWriteTime = (Get-Date).AddSeconds(-$secAgo) }
function Open-Ids { @(Get-OpenAlerts $runs | ForEach-Object Id) }
function Set-Opened([string]$id, [int]$minAgo) {
    $p = Join-Path $runs "alerts\open\$id.json"; $j = Get-Content $p -Raw | ConvertFrom-Json
    $j.opened_at = (Get-Date).AddMinutes(-$minAgo).ToString('yyyy-MM-ddTHH:mm:ss'); [IO.File]::WriteAllText($p, ($j | ConvertTo-Json))
}
function Run-Guard([hashtable]$envs = @{}, [string]$sid = 'sess-coord') {
    $ErrorActionPreference = 'Continue'
    $saved = @{}; foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $envs[$k]) }
    try {
        $in = (@{ cwd = 'C:\KenshiModding'; session_id = $sid; stop_hook_active = $false } | ConvertTo-Json -Compress)
        ($in | & powershell -NoProfile -ExecutionPolicy Bypass -File $guard stop 2>$null) -join "`n"
    } finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}
function Run-Hook([hashtable]$obj) { $ErrorActionPreference = 'Continue'; (($obj | ConvertTo-Json -Compress) | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'alert-scan.ps1') -Hook 2>$null) -join "`n" }
try {
    . (Join-Path $auto 'alert-lib.ps1')
    # --- 1. open: 5090-i3 operator RUNNING but silent 20 min, the other lanes active
    foreach ($l in $lanes) { New-Status "op-$l" 'RUNNING' 1 }
    New-Status 'op-5090-i3' 'RUNNING' 20
    $r = Invoke-AlertScan -Runs $runs -Force
    T ((Open-Ids) -contains 'lane-idle-5090-i3' -and (Open-Ids).Count -eq 1) 'open: lane idle alert opened, active lanes quiet'
    $a = Get-OpenAlerts $runs | Select-Object -First 1
    T ($a.Kind -eq 'lane-idle' -and $a.Subject -eq '5090-i3' -and $a.Text -match 'LANE IDLE 5090-i3' -and $a.OpenedAt -and $a.LastSeen) 'open: record has kind/subject/text/opened_at/last_seen'
    $of = Join-Path $runs 'inbox\operators\5090-i3-alert.txt'
    T ((Test-Path $of) -and ((Get-Content $of -Raw) -match 'lane-idle-5090-i3') -and ((Get-Content $of -Raw) -match 'alert-ack\.ps1')) 'operator inbox file written with the ack hint'
    # --- 2. rate limit
    $r2 = Invoke-AlertScan -Runs $runs
    T ($r2.Skipped) 'rate limit: second scan within 60 s is skipped'
    Set-Stamp 70
    $r3 = Invoke-AlertScan -Runs $runs
    T (-not $r3.Skipped) 'rate limit: scan runs again after 60 s'
    # --- 3. ack closes; same incident not re-opened; re-opens after the hold
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'alert-ack.ps1') '5090-i3' 'asked operator, restarted batch' 2>&1 | Out-String
    T ($o -match 'ACKED lane-idle-5090-i3' -and (Open-Ids).Count -eq 0) 'ack by subject closes it'
    $cl = @(Get-ChildItem (Join-Path $runs 'alerts\closed') -Filter 'lane-idle-5090-i3-*.json')
    T ($cl.Count -eq 1 -and ((Get-Content $cl[0].FullName -Raw | ConvertFrom-Json).action -eq 'asked operator, restarted batch') -and ((Get-Content $cl[0].FullName -Raw | ConvertFrom-Json).closed_by -eq 'ack')) 'closed record keeps the action text and closed_by=ack'
    T (-not (Test-Path $of)) 'operator inbox file removed after ack'
    $oe = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'alert-ack.ps1') 'nonexistent' 'x y z' 2>&1 | Out-String
    T ($oe -match 'no open alert matches') 'ack of an unknown id says so'
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids).Count -eq 0) 'ack hold: condition still true, not re-opened right after the ack'
    $ak = Join-Path $runs 'alerts\acked\lane-idle-5090-i3.json'
    $aj = Get-Content $ak -Raw | ConvertFrom-Json; $aj.acked_at = (Get-Date).AddMinutes(-40).ToString('yyyy-MM-ddTHH:mm:ss'); [IO.File]::WriteAllText($ak, ($aj | ConvertTo-Json))
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids) -contains 'lane-idle-5090-i3' -and ((Get-OpenAlerts $runs)[0].Text -match 'still true')) 'ack never hides: re-opened with a note after the 30 min hold'
    # --- 4. auto-clear: operator active again
    New-Status 'op-5090-i3' 'RUNNING' 0
    [void](Invoke-AlertScan -Runs $runs -Force)
    $cl2 = @(Get-ChildItem (Join-Path $runs 'alerts\closed') -Filter 'lane-idle-5090-i3-*.json' | Where-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).closed_by -eq 'cleared' })
    T ((Open-Ids).Count -eq 0 -and $cl2.Count -eq 1 -and -not (Test-Path (Join-Path $runs 'alerts\acked\lane-idle-5090-i3.json'))) 'auto-clear: lane active again closes it as cleared and releases the ack hold'
    # --- 5. agent alerts: stall message, failed agent without successor, successor clears
    New-Status 'wpStall' 'RUNNING' 25
    $mp = Join-Path $runs 'inbox\coordinator\20261015-200000-wpStall.msg'
    [IO.File]::WriteAllText($mp, 'AGENT STALL wpStall : status RUNNING, silent 25 min. Latest: fixture')
    New-Status 'wpFail' 'FAILED' 12
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids) -contains 'agent-stall-wpstall') 'agent STALL message opens an alert (id lower-cased)'
    T ((Open-Ids) -contains 'agent-failed-wpfail') 'FAILED agent with no successor opens an alert'
    [void](Invoke-AlertScan -Runs $runs -Force)
    T (@(Get-OpenAlerts $runs | Where-Object Id -eq 'agent-stall-wpstall').Count -eq 1) 'a message is handled once (no duplicate on re-scan)'
    New-Status 'wpFail2' 'RUNNING' 0
    New-Status 'wpStall' 'RUNNING' 0
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids).Count -eq 0) 'auto-clear: successor RUNNING / stalled agent writing status again close both'
    # --- 6. llm alert via message + llm-health result
    [IO.File]::WriteAllText((Join-Path $runs 'inbox\coordinator\20261015-200500-op.msg'), 'PREFLIGHT-FAIL llm provider down (LLM-HEALTH FAIL http=402)')
    $env:KAH_ALERT_LLM_OUT = 'LLM-HEALTH FAIL http=402 no balance'
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids) -contains 'llm-health-fail-llm') 'LLM-HEALTH FAIL opens an alert'
    $env:KAH_ALERT_LLM_OUT = 'LLM-HEALTH OK 400'
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids).Count -eq 0) 'auto-clear: llm-health OK closes the llm alert'
    Remove-Item Env:KAH_ALERT_LLM_OUT -ErrorAction SilentlyContinue
    # --- 7. Stop hook: block at 5 min, not at 2 min; verdict names the id and alert-ack.ps1
    $env:KAH_ALERT_NO_SCAN = '1'
    New-Status 'op-5090-i3' 'RUNNING' 20
    Set-Stamp 120; [void](Invoke-AlertScan -Runs $runs -Force)      # re-open lane-idle-5090-i3 (the ack was long cleared)
    Remove-Item (Join-Path $runs 'alerts\acked\*') -Force -ErrorAction SilentlyContinue
    if (-not ((Open-Ids) -contains 'lane-idle-5090-i3')) { [void](Invoke-AlertScan -Runs $runs -Force) }
    Set-Opened 'lane-idle-5090-i3' 2
    $out = Run-Guard
    T ($out -notmatch 'open alert') 'stop: alert 2 min old does not block'
    Set-Opened 'lane-idle-5090-i3' 6
    $out = Run-Guard
    T ($out -match '"decision":"block"' -and $out -match 'lane-idle-5090-i3' -and $out -match 'alert-ack\.ps1' -and $out -match '1 open alert') 'stop: alert 6 min old and unacked blocks the coordinator, names id and alert-ack.ps1'
    # --- 8. loop cap: 3 blocks, the 4th stop passes once (logged), then blocks again
    Remove-Item (Join-Path $runs 'alerts\stop-block.json') -Force -ErrorAction SilentlyContinue
    $b = @(1..5 | ForEach-Object { [bool]((Run-Guard) -match 'open alert\(s\) older') })
    T ($b[0] -and $b[1] -and $b[2] -and -not $b[3] -and $b[4]) "loop cap: blocks 1-3, 4th let through, 5th blocks again ($($b -join ','))"
    T ((Test-Path (Join-Path $runs 'alerts\cap-ends.log')) -and ((Get-Content (Join-Path $runs 'alerts\cap-ends.log') -Raw) -match 'lane-idle-5090-i3')) 'loop cap: the let-through is logged in alerts\cap-ends.log'
    # a changed alert set restarts the count
    Remove-Item (Join-Path $runs 'alerts\stop-block.json') -Force -ErrorAction SilentlyContinue
    [void](Run-Guard); [void](Run-Guard)
    New-Status 'wpFail' 'FAILED' 12
    $ex = Join-Path $runs 'alerts\open\agent-failed-wpfail.json'
    [IO.File]::WriteAllText($ex, (@{ id = 'agent-failed-wpfail'; kind = 'agent-failed'; subject = 'wpFail'; text = 'x'; source = 'report'; opened_at = (Get-Date).AddMinutes(-9).ToString('yyyy-MM-ddTHH:mm:ss'); last_seen = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') } | ConvertTo-Json))
    T ([bool]((Run-Guard) -match '2 open alert')) 'loop cap: a changed alert set restarts the count (still blocking)'
    Remove-Item $ex -Force
    # --- 9. exempt: tail session and agent session are not blocked by alerts; retired coordinator neither
    Remove-Item (Join-Path $runs 'alerts\stop-block.json') -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText((Join-Path $runs 'tail\sess-tail.flag'), 'tail')
    $o1 = Run-Guard @{} 'sess-tail'
    T ($o1 -notmatch 'open alert') 'exempt: a tail session is not blocked by alerts'
    $o2 = Run-Guard @{ KAH_AGENT_NAME = 'someagent' }
    T ($o2 -notmatch 'open alert') 'exempt: an agent session (subagent) is not blocked by alerts'
    [IO.File]::WriteAllText((Join-Path $runs 'coordinator.heartbeat'), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) other-session now")
    $o3 = Run-Guard @{} 'sess-retired'
    T ($o3 -notmatch 'open alert') 'exempt: a session that is not the heartbeat owner is not blocked by alerts'
    Remove-Item (Join-Path $runs 'coordinator.heartbeat') -Force
    # --- 10. ack closes and the stop passes again
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'alert-ack.ps1') 'lane-idle-5090-i3' 'lane checked, operator restarted' 2>&1
    T ((Run-Guard) -notmatch 'open alert') 'ack: after the ack the stop is no longer blocked by that alert'
    Remove-Item Env:KAH_ALERT_NO_SCAN -ErrorAction SilentlyContinue
    # --- 11. reminder: one line, only when an alert is older than 3 min
    Remove-Item (Join-Path $runs 'alerts\acked\*') -Force -ErrorAction SilentlyContinue
    New-Status 'op-5090-i3' 'RUNNING' 20
    Set-Stamp 120; [void](Invoke-AlertScan -Runs $runs -Force)
    Set-Opened 'lane-idle-5090-i3' 2
    T ((Get-AlertReminder $runs) -eq '') 'reminder: nothing while every alert is younger than 3 min'
    Set-Opened 'lane-idle-5090-i3' 4
    $rem = Get-AlertReminder $runs
    T ($rem -match '^\[open-alerts: 1, oldest 4 min: lane-idle-5090-i3' -and $rem -notmatch "`n" -and $rem.EndsWith(']')) "reminder: one line [open-alerts: n, oldest m min: ids] ($rem)"
    Set-Stamp 5; (Get-Item (Join-Path $runs 'alerts\scan.stamp')).LastWriteTime = Get-Date     # fresh stamp: the hook's own scan is rate-limited, planted state stays
    $h = Run-Hook @{ session_id = 'sess-coord'; cwd = 'C:\KenshiModding'; tool_name = 'Bash' }
    $hj = $null; try { $hj = $h | ConvertFrom-Json } catch { }
    T ($hj -and $hj.hookSpecificOutput.hookEventName -eq 'PostToolUse' -and $hj.hookSpecificOutput.additionalContext -match '^\[open-alerts: 1' -and ($h -split "`n").Count -eq 1) 'hook: coordinator gets one JSON line with the reminder'
    T ((Run-Hook @{ session_id = 'sess-coord'; agent_id = 'abc123'; tool_name = 'Bash' }) -eq '') 'hook: a subagent call gets no reminder'
    T ((Run-Hook @{ session_id = 'sess-tail'; tool_name = 'Bash' }) -eq '') 'hook: a tail session gets no reminder'
    [IO.File]::WriteAllText((Join-Path $runs 'coordinator.heartbeat'), "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) other-session now")
    T ((Run-Hook @{ session_id = 'sess-coord'; tool_name = 'Bash' }) -eq '') 'hook: a non-owner session gets no reminder'
    Remove-Item (Join-Path $runs 'coordinator.heartbeat') -Force
    # --- 12. session-start lines (cap 6)
    foreach ($i in 1..8) { [IO.File]::WriteAllText((Join-Path $runs "alerts\open\agent-failed-x$i.json"), (@{ id = "agent-failed-x$i"; kind = 'agent-failed'; subject = "x$i"; text = 'fixture'; source = 'report'; opened_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'); last_seen = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') } | ConvertTo-Json)) }
    $bl = @(Get-AlertBriefLines $runs)
    T ($bl.Count -le 6 -and $bl[0] -match '^=== OPEN ALERTS \(9') "brief: header + at most 6 lines ($($bl.Count))"
    # --- 13. lane-stalled: HARD alert (operator RUNNING, status AND evidence silent > 12 min)
    Remove-Item (Join-Path $runs 'alerts\open\*'), (Join-Path $runs 'alerts\acked\*') -Force -ErrorAction SilentlyContinue
    Remove-Item Env:KAH_ALERT_NO_SCAN -ErrorAction SilentlyContinue
    $env:KAH_LANE_STALL_MIN = '12'; $env:KAH_GUARD_TEST_LANE_PROCS = '3,4,5'
    foreach ($n in 3, 4, 5) { [IO.File]::WriteAllText((Join-Path $runs "game-$n.lock"), "rig5090-lane$n") }
    function New-Ev([string]$lane, [int]$minAgo) {
        $dd = Join-Path $runs "dir-$lane\rows"; New-Item -ItemType Directory -Force -Path $dd | Out-Null
        $f = Join-Path $dd 'ev.txt'; [IO.File]::WriteAllText($f, 'evidence'); (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-$minAgo); $f
    }
    function Ack([string]$k, [string]$act) { $ErrorActionPreference = 'Continue'; $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'alert-ack.ps1') $k $act 2>&1 | Out-String; @{ Out = $o; Code = $LASTEXITCODE } }
    foreach ($l in $lanes) { New-Status "op-$l" 'RUNNING' 1; [void](New-Ev $l 1) }
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids).Count -eq 0) 'stalled: healthy lanes (status+evidence fresh) raise nothing'
    New-Status 'op-4080-i3' 'RUNNING' 20; $evf = New-Ev '4080-i3' 20
    [void](Invoke-AlertScan -Runs $runs -Force)
    $st = Get-OpenAlerts $runs | Where-Object { $_.Id -eq 'lane-stalled-4080-i3' }
    T ($st -and $st.Kind -eq 'lane-stalled' -and $st.Text -match 'operator=op-4080-i3' -and $st.Text -match '2\d(\.\d)?m' -and $st.Text -match [regex]::Escape($evf) -and $st.Text -match 'TaskStop' -and $st.Text -match 'lane-brief\.ps1 4080-i3' -and $st.Text -match 'LANE IDLE') 'stalled: raised, text names operator, minutes, last evidence file and the action'
    T ((Open-Ids) -contains 'lane-idle-4080-i3') 'stalled: the plain lane-idle alert is open too'
    # status fresh but evidence old (operator alive, just writing status): not stalled
    New-Status 'op-4080-i3' 'RUNNING' 1
    [void](Invoke-AlertScan -Runs $runs -Force)
    T (-not ((Open-Ids) -contains 'lane-stalled-4080-i3')) 'stalled: fresh status alone (evidence old) does not raise / clears'
    New-Status 'op-4080-i3' 'RUNNING' 20
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids) -contains 'lane-stalled-4080-i3') 'stalled: raised again when both silent'
    # Stop hook: hard alert blocks the coordinator after 3 min (idle alert needs 5)
    Set-Opened 'lane-stalled-4080-i3' 4; Set-Opened 'lane-idle-4080-i3' 4
    $v = Get-AlertStopVerdict $runs
    T ($v.Block -and ($v.Ids -contains 'lane-stalled-4080-i3') -and -not ($v.Ids -contains 'lane-idle-4080-i3')) 'stalled: Stop verdict blocks at 4 min for the stalled alert only'
    T ((Get-AlertReminder $runs) -match 'lane-stalled-4080-i3') 'stalled: PostToolUse reminder lists it'
    Remove-Item (Join-Path $runs 'alerts\stop-block.json') -Force -ErrorAction SilentlyContinue
    # ack without proof refused
    $a1 = Ack 'lane-stalled-4080-i3' 'looked at it, fine'
    T ($a1.Out -match 'REFUSED' -and $a1.Code -eq 3 -and (Open-Ids) -contains 'lane-stalled-4080-i3') 'ack: plain ack refused, alert stays open'
    $a2 = Ack '4080-i3' "evidence $evf"
    T ($a2.Out -match 'REFUSED' -and (Open-Ids) -contains 'lane-stalled-4080-i3') 'ack: evidence path older than 5 min refused'
    $fresh = Join-Path $runs 'fresh-proof.txt'; [IO.File]::WriteAllText($fresh, 'x')
    $a3 = Ack 'lane-stalled-4080-i3' "evidence $fresh"
    T ($a3.Out -match 'ACKED lane-stalled-4080-i3' -and -not ((Open-Ids) -contains 'lane-stalled-4080-i3')) 'ack: evidence path newer than 5 min accepted'
    Remove-Item (Join-Path $runs 'alerts\acked\lane-stalled-4080-i3.json') -Force -ErrorAction SilentlyContinue
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids) -contains 'lane-stalled-4080-i3') 'stalled: reopened for the respawn ack case'
    $a4 = Ack 'lane-stalled-4080-i3' 'TaskStop op-4080-i3, respawned as op-4080-i3b'
    T ($a4.Out -match 'ACKED lane-stalled-4080-i3' -and -not ((Open-Ids) -contains 'lane-stalled-4080-i3')) 'ack: "respawned" accepted'
    Remove-Item (Join-Path $runs 'alerts\acked\lane-stalled-4080-i3.json') -Force -ErrorAction SilentlyContinue
    [void](Invoke-AlertScan -Runs $runs -Force)
    T ((Open-Ids) -contains 'lane-stalled-4080-i3') 'stalled: reopened for the clear case'
    [void](New-Ev '4080-i3' 0)
    [void](Invoke-AlertScan -Runs $runs -Force)
    $cl3 = @(Get-ChildItem (Join-Path $runs 'alerts\closed') -Filter 'lane-stalled-4080-i3-*.json' | Where-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).closed_by -eq 'cleared' })
    T (-not ((Open-Ids) -contains 'lane-stalled-4080-i3') -and $cl3.Count -ge 1) 'stalled: new evidence clears it by itself (closed as cleared)'
    # exclusions: 5090-i4 (live game via lock + test procs) stalled, then abandoned / held / no game / declared wait
    New-Status 'op-5090-i4' 'RUNNING' 30; [void](New-Ev '5090-i4' 30)
    $ln = { @(& (Join-Path $auto 'lane-idle.ps1') -NoMemory -Runs $runs 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^LANE STALLED 5090-i4' }).Count }
    T ((& $ln) -eq 1) 'exclusions: control, live-game lane with silent operator is stalled'
    [IO.File]::WriteAllText((Join-Path $runs 'agents\op-5090-i4.abandoned'), 'abandoned on purpose')
    T ((& $ln) -eq 0) 'exclusions: operator with an .abandoned marker is not stalled'
    Remove-Item (Join-Path $runs 'agents\op-5090-i4.abandoned') -Force
    [IO.File]::WriteAllText((Join-Path $runs 'lanes.held'), "# held`n5090-i4`n")
    T ((& $ln) -eq 0) 'exclusions: lane listed in lanes.held is not stalled'
    Remove-Item (Join-Path $runs 'lanes.held') -Force
    T ((& $ln) -eq 1) 'exclusions: control again after removing the hold'
    $env:KAH_GUARD_TEST_LANE_PROCS = '3,5'
    T ((& $ln) -eq 0) 'exclusions: 5090 lane with no live game is not stalled'
    $env:KAH_GUARD_TEST_LANE_PROCS = '3,4,5'
    New-Item -ItemType Directory -Force -Path (Join-Path $runs 'lane-longwait') | Out-Null
    [IO.File]::WriteAllText((Join-Path $runs 'lane-longwait\5090-i4.txt'), 'save/load cycle')
    T ((& $ln) -eq 0) 'exclusions: declared long wait (lane-longwait marker) is not stalled'
} catch { "FAIL selftest crashed: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"; $fails++ }
finally {
    if ($null -eq $savedRuns) { Remove-Item Env:KAH_RUNS_DIR -ErrorAction SilentlyContinue } else { $env:KAH_RUNS_DIR = $savedRuns }
    Remove-Item Env:KAH_LANE_STALL_MIN, Env:KAH_GUARD_TEST_LANE_PROCS -ErrorAction SilentlyContinue
    Remove-Item Env:KAH_ALERT_NO_SCAN -ErrorAction SilentlyContinue; Remove-Item Env:KAH_ALERT_LLM_OUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $runs -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fails) { "SELFTEST alert-ledger FAILED ($fails)"; exit 1 } else { 'SELFTEST alert-ledger OK'; exit 0 }
