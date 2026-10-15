# tail-ledger-selftest.ps1: selftest for the tail-handoff ledger side (WP-T2): program-ledger.ps1 route/ack/records, tail-relay.ps1,
# tail-ack.ps1 and session-start.ps1 (tail listing + COLD START). Runs entirely in a temp runs dir (KAH_RUNS_DIR / KPL_DIR); never touches
# C:\KenshiTestRuns. Prints PASS/FAIL lines and "SELFTEST PASS n/m" (exit 1 on any FAIL).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$ledger = Join-Path $here 'program-ledger.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tail-ledger-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$old = @{ KAH_RUNS_DIR = $env:KAH_RUNS_DIR; KPL_DIR = $env:KPL_DIR; KPL_WS = $env:KPL_WS }
$env:KAH_RUNS_DIR = $tmp; $env:KPL_DIR = Join-Path $tmp 'programs'; $env:KPL_WS = Join-Path $tmp 'ws'
New-Item -ItemType Directory -Force -Path $env:KPL_DIR, $env:KPL_WS, (Join-Path $tmp 'agents'), (Join-Path $tmp 'tail'), (Join-Path $tmp 'inbox\coordinator') | Out-Null
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
function RunPs([string]$file, [string[]]$a) {
    $ErrorActionPreference = "Continue"
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $file @a 2>&1
    [pscustomobject]@{ code = $LASTEXITCODE; out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function L([string[]]$a) { RunPs $ledger $a }
function Recs { @((L @('records')).out | ConvertFrom-Json | ForEach-Object { $_ }) }
function Status([string]$n, [string]$state, [int]$ageMin, [string]$task = 't') {
    $f = Join-Path $tmp "agents\$n.status"
    Set-Content -LiteralPath $f -Value @("$n | $state | 2026-10-15 17:00", "task: $task") -Encoding UTF8
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
try {
    T ($env:KPL_DIR.StartsWith($tmp)) '0 temp dirs in use'
    # ---- ledger: route / ack / records ----
    L @('init', 'tp', 'testing/TP.md') | Out-Null
    L @('add-wp', 'tp', 'wA', 'agent=agA', 'state=running', 'items=1') | Out-Null
    L @('add-wp', 'tp', 'wB', 'agent=agB', 'state=running', 'items=2') | Out-Null
    L @('add-wp', 'tp', 'wC', 'agent=agC', 'state=running', 'items=3', 'successors=agC2') | Out-Null
    L @('add-wp', 'tp', 'wD', 'agent=agD', 'state=running', 'items=4') | Out-Null
    $r = L @('route', 'tp', 'agA', '-Owner', 'tail:liveS', '-Note', 'brief: build X; output /root/x.patch; when done run tests; WARNING depends on wB', '-Result', 'C:\x\agA-report.md')
    T ($r.code -eq 0 -and $r.out -match 'routed tp agA owner=tail:liveS') '1a route succeeds'
    $j = Get-Content -LiteralPath (Join-Path $env:KPL_DIR 'tp.json') -Raw | ConvertFrom-Json
    $rec = $j.wps[0].agent_records.agA
    T ($rec.owner_session -eq 'tail:liveS' -and $rec.routing_note -like 'brief: build X*' -and $rec.result_file -eq 'C:\x\agA-report.md' -and $rec.acked_by_new_coordinator -eq $false) '1b stored fields (owner_session, routing_note, result_file, acked false) per contract sec 6'
    T ((L @('route', 'tp', 'agA', '-Owner', 'bogus', '-Note', 'x')).code -ne 0) '1c bad -Owner rejected'
    T ((L @('route', 'tp', 'nobody', '-Owner', 'live', '-Note', 'x')).code -ne 0) '1d unknown agent rejected'
    T ((L @('route', 'tp', 'agB', '-Owner', 'live')).code -ne 0) '1e route without any note rejected'
    T ((L @('route', 'tp', 'agC2', '-Owner', 'tail:liveS', '-Note', 'successor routed')).code -eq 0) '1f a successor name can be routed'
    $show = (L @('show', 'tp')).out
    T ($show -match 'route agA: owner=tail:liveS acked=no result=C:\\x\\agA-report.md note: brief: build X') '2a show prints owner, ack state, result, note'
    $brief = (L @('brief')).out
    T ($brief -match 'route agA: owner=tail:liveS') '2b brief prints the route line'
    $rows = Recs
    $ra = $rows | Where-Object { $_.agent -eq 'agA' }
    $rb = $rows | Where-Object { $_.agent -eq 'agB' }
    T ($ra.owner_session -eq 'tail:liveS' -and $ra.program -eq 'tp' -and $ra.wp -eq 'wA' -and $rb.owner_session -eq 'live' -and $rb.acked_by_new_coordinator -eq $false) '2c records JSON: routed agent has its owner, unrouted wp agent defaults to live'
    T ((L @('ack', 'tp', 'agA')).code -eq 0 -and (Recs | Where-Object { $_.agent -eq 'agA' }).acked_by_new_coordinator -eq $true) '3a ack sets acked_by_new_coordinator'
    L @('route', 'tp', 'agA', '-Owner', 'tail:liveS') | Out-Null
    $ra = Recs | Where-Object { $_.agent -eq 'agA' }
    T ($ra.acked_by_new_coordinator -eq $false -and $ra.routing_note -like 'brief: build X*') '3b re-route resets ack and keeps the old note'
    T ((L @('ack', 'tp', 'nobody')).code -ne 0) '3c ack of an unknown agent fails'
    $m = (L @('show', 'tp', '-Md')).out
    T ($m -match 'route agA: owner tail:liveS') '3d markdown mirror lists the route'
    # ---- tail-relay ----
    $rep = Join-Path $tmp 'agA-report.md'
    $lines = @('# agA report', 'Built X in /root/x.patch')
    1..120 | ForEach-Object { $lines += "detail line $_" }
    $lines += 'RESULT 05-a PASS evidence=C:\e\1.txt'
    $lines += 'blocker: need decision on Y?'
    Set-Content -LiteralPath $rep -Value $lines -Encoding UTF8
    $flag = [pscustomobject]@{ session = 'liveS'; pid = $PID; created = (Get-Date).ToString('o'); new_coordinator_inbox = (Join-Path $tmp 'inbox\coordinator'); agents = @('agA', 'agD') }
    [IO.File]::WriteAllText((Join-Path $tmp 'tail\liveS.flag'), ($flag | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $rl = RunPs (Join-Path $here 'tail-relay.ps1') @('-Agent', 'agA', '-Report', $rep)
    $msgLines = @($rl.out -split "`r?`n" | Where-Object { $_ -notlike '(inbox file:*' })
    T ($rl.code -eq 0 -and $msgLines[0] -match '^TAIL-RELAY agA DONE \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d') '4a relay first line: TAIL-RELAY <agent> DONE <iso>'
    T ($msgLines[1] -eq "report: $rep" -and $msgLines[2] -eq 'ledger: tp/wA routing_note') '4b relay lines 2-3: report path and ledger pointer'
    T ($msgLines.Count -le 30) "4c relay message <= 30 lines (got $($msgLines.Count))"
    T (($msgLines -join "`n") -match 'RESULT 05-a PASS' -and ($msgLines -join "`n") -match 'blocker: need decision') '4d keyword lines (RESULT/blocker) survive the cut'
    $inb = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'inbox\coordinator') -Filter '*-tail-agA.msg' -File)
    T ($inb.Count -eq 1 -and $inb[0].Name -match '^\d{8}-\d{6}-tail-agA\.msg$' -and ((Get-Content -LiteralPath $inb[0].FullName -Raw).TrimEnd() -eq ($msgLines -join "`n").TrimEnd())) '4e inbox file <ts>-tail-<agent>.msg has the same text'
    $ra = Recs | Where-Object { $_.agent -eq 'agA' }
    T ($ra.result_file -eq $rep -and $ra.acked_by_new_coordinator -eq $false -and $ra.owner_session -eq 'tail:liveS') '4f relay records result_file, leaves it un-acked, keeps the owner'
    $rl2 = RunPs (Join-Path $here 'tail-relay.ps1') @('-Agent', 'agB', '-Kind', 'QUESTION', '-Summary', "Should I use plan 1 or 2?`nline2", '-ToSession', 'newCoord')
    $ml2 = @($rl2.out -split "`r?`n" | Where-Object { $_ -notlike '(inbox file:*' })
    T ($rl2.code -eq 0 -and $ml2[0] -match '^TAIL-RELAY agB QUESTION ' -and $ml2[3] -eq 'to: newCoord' -and $ml2[4] -eq 'Should I use plan 1 or 2?') '4g QUESTION with -Summary and -ToSession (no report needed)'
    T ((RunPs (Join-Path $here 'tail-relay.ps1') @('-Agent', 'agB', '-Report', (Join-Path $tmp 'missing.md'))).code -ne 0) '4h DONE with a missing report file fails'
    # ---- tail-ack ----
    $ak = RunPs (Join-Path $here 'tail-ack.ps1') @('-Agent', 'agA')
    T ($ak.code -eq 0 -and (Recs | Where-Object { $_.agent -eq 'agA' }).acked_by_new_coordinator -eq $true) '5a tail-ack.ps1 sets acked'
    T ((RunPs (Join-Path $here 'tail-ack.ps1') @('-Agent', 'ghost')).code -ne 0) '5b tail-ack for an agent in no ledger fails'
    # ---- session-start: tail listing + cold start ----
    $deadPid = 0
    foreach ($p in 91000..91400) { if (-not (Get-Process -Id $p -ErrorAction SilentlyContinue)) { $deadPid = $p; break } }
    $flag2 = [pscustomobject]@{ session = 'deadS'; pid = $deadPid; created = (Get-Date).AddHours(-1).ToString('o'); new_coordinator_inbox = (Join-Path $tmp 'inbox\coordinator'); agents = @('agB') }
    [IO.File]::WriteAllText((Join-Path $tmp 'tail\deadS.flag'), ($flag2 | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    L @('route', 'tp', 'agA', '-Owner', 'tail:liveS', '-Note', 'brief: build X; output /root/x.patch; when done run tests') | Out-Null
    L @('route', 'tp', 'agB', '-Owner', 'tail:deadS', '-Note', 'brief: build B; resume from /root/b; then merge with A') | Out-Null
    L @('route', 'tp', 'agD', '-Owner', 'tail:liveS', '-Note', 'brief: D, fresh heartbeat') | Out-Null
    Status 'agA' 'RUNNING' 90          # stale status, but owned by a LIVE tail: must not be listed for respawn nor as ORPHANED
    Status 'agB' 'RUNNING' 90          # owner tail process gone
    Status 'agC' 'RUNNING' 200         # no owner, silent for hours: cold-start dead
    Status 'agD' 'RUNNING' 2           # fresh heartbeat, owned by the live tail
    $ss = RunPs (Join-Path $here 'session-start.ps1') @('-Brief', '-AgentsOnly')
    $o = $ss.out
    T ($o -match 'TAIL liveS LIVE \(pid \d+.*owns agA, agD') '6a lists the LIVE tail with the agents it owns'
    T ($o -match 'TAIL deadS DEAD \(process \d+ gone\): its agents are DEAD with it: agB') '6b a tail whose process is gone is DEAD and so are its agents'
    T ($o -match 'OWNED-BY-LIVE-TAIL agA \(tp/wA' -and $o -match 'OWNED-BY-LIVE-TAIL agD \(tp/wD' -and $o -match 'acked=NO' -and $o -match 'routing note: brief: build X') '6c per-agent owner_session / ack state / routing note shown for tail-owned agents'
    T ($o -match 'DEAD agB \(tp/wB, wp running\): owner tail deadS is gone -> respawn a FRESH agent agB2' -and $o -match 'Routing note: brief: build B; resume from /root/b') '6d dead tail agent: DEAD + respawn line + routing note'
    T ($o -match 'DEAD agC \(tp/wC, wp running\): status RUNNING 20\d min ago \(not alive\) -> respawn a FRESH agent agC2' -and $o -match 'no routing note in the ledger') '6e cold start: stale agent without owner is DEAD with respawn line (and says when there is no note)'
    $bad = @($o -split "`r?`n" | Where-Object { $_ -match '(?i)respawn' -and $_ -match '(?<![\w.-])(agA|agD)(?![\w.-])' })
    T ($bad.Count -eq 0) "6f no 'respawn' text for agents owned by a live tail (offending lines: $($bad.Count))"
    T (-not ($o -match 'ORPHANED[^\r\n]*agA') -and -not ($o -match 'NO SUCCESSOR agA')) '6g the agent-health ORPHANED line for the tail-owned agent is filtered out'
    T ($o -match 'ORPHANED[^\r\n]*agC' -or $o -match 'ORPHANED[^\r\n]*agB') '6h the agent-health lines for non-owned stale agents are kept'
    # no tail flags: no tail section
    Remove-Item -LiteralPath (Join-Path $tmp 'tail\liveS.flag'), (Join-Path $tmp 'tail\deadS.flag') -Force
    $o2 = (RunPs (Join-Path $here 'session-start.ps1') @('-Brief', '-AgentsOnly')).out
    T (-not ($o2 -match '=== tail sessions') -and $o2 -match 'DEAD agA \(tp/wA' -and $o2 -match 'owner tail liveS is gone') '6i without a flag the former tail owner is gone: its agent is DEAD (cold start)'
} finally {
    foreach ($k in $old.Keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item -LiteralPath "Env:$k" -Value $old[$k] } }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
