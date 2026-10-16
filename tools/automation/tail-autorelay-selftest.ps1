# tail-autorelay-selftest.ps1: selftest for tail-autorelay.ps1 (PI-25). Temp runs dir only (KAH_RUNS_DIR / KPL_DIR); never touches
# C:\KenshiTestRuns. Prints PASS/FAIL lines and "SELFTEST PASS n/m" (exit 1 on any FAIL).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$ledger = Join-Path $here 'program-ledger.ps1'
$auto = Join-Path $here 'tail-autorelay.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tail-autorelay-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$old = @{ KAH_RUNS_DIR = $env:KAH_RUNS_DIR; KPL_DIR = $env:KPL_DIR; KPL_WS = $env:KPL_WS }
$env:KAH_RUNS_DIR = $tmp; $env:KPL_DIR = Join-Path $tmp 'programs'; $env:KPL_WS = Join-Path $tmp 'ws'
$inbox = Join-Path $tmp 'inbox\coordinator'
New-Item -ItemType Directory -Force -Path $env:KPL_DIR, $env:KPL_WS, (Join-Path $tmp 'agents'), (Join-Path $tmp 'tail'), $inbox | Out-Null
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
function RunPs([string]$file, [string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $file @a 2>&1
    [pscustomobject]@{ code = $LASTEXITCODE; out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Status([string]$n, [string]$state) {
    Set-Content -LiteralPath (Join-Path $tmp "agents\$n.status") -Value @("$n | $state | 2026-10-15 17:00", "task: t") -Encoding UTF8
}
function Report([string]$n, [string[]]$lines) {
    $d = Join-Path $tmp "agents\out\$n"; New-Item -ItemType Directory -Force -Path $d | Out-Null
    Set-Content -LiteralPath (Join-Path $d 'latest.md') -Value $lines -Encoding UTF8
}
function Msgs([string]$n) { @(Get-ChildItem -LiteralPath $inbox -Filter "*-tail-$n.msg" -File -ErrorAction SilentlyContinue) }
function Flag([string]$sess, [string[]]$agents) {
    $f = [pscustomobject]@{ session = $sess; pid = $PID; created = (Get-Date).ToString('o'); new_coordinator_inbox = $inbox; agents = $agents }
    [IO.File]::WriteAllText((Join-Path $tmp "tail\$sess.flag"), ($f | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}
function Auto([string[]]$extra) { RunPs $auto (@('-TailSession', 'tS', '-PollSec', '1') + $extra) }
try {
    T ($env:KAH_RUNS_DIR.StartsWith($tmp)) '0 temp dirs in use'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger init tp testing/TP.md | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger add-wp tp wA agent=agA state=running items=1 | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger route tp agA -Owner tail:tS -Note 'brief A' | Out-Null
    # agB, agC, agD owned via the flag only (not in the ledger)
    Flag 'tS' @('agB', 'agC', 'agD')
    # long report with a late DECISION and a QUESTION line: both must survive the 30-line message cut
    $a = @('# agA report', 'Built X in /root/x.patch'); 1..80 | ForEach-Object { $a += "detail line $_" }
    $a += 'DECISION needed: ship patch 1 or 2 ?'; $a += '  question: should it be case-insensitive?'; $a += 'tail line after decisions'
    Report 'agA' $a
    Status 'agA' 'DONE'
    Status 'agB' 'RUNNING'
    Report 'agC' @('# agC', 'broke', 'RESULT 1 FAIL')
    Status 'agC' 'FAILED'
    Status 'agD' 'STOPPED-CONTEXT'
    Set-Content -LiteralPath (Join-Path $tmp 'agents\agD.handoff.md') -Value @('# agD handoff', 'resume at step 3', 'QUESTION: keep the old DB?') -Encoding UTF8

    $r = Auto @('-Once')
    T ($r.code -eq 0 -and $r.out -match 'relayed agA DONE' -and $r.out -match 'relayed agC FAILED' -and $r.out -match 'relayed agD STOPPED-CONTEXT') '1a first pass relays DONE, FAILED and STOPPED-CONTEXT agents'
    T ((Msgs 'agB').Count -eq 0) '1b a RUNNING agent is not relayed'
    T ($r.out -match 'exit: -Once pass done') '1c -Once exits after one pass with an agent still running'
    $m = Msgs 'agA'
    T ($m.Count -eq 1 -and $m[0].Name -match '^\d{8}-\d{6}-tail-agA\.msg$') '2a inbox file <ts>-tail-<agent>.msg written'
    $txt = (Get-Content -LiteralPath $m[0].FullName -Raw)
    $ls = @($txt.TrimEnd() -split "`r?`n")
    T ($ls[0] -match '^TAIL-RELAY agA DONE \d{4}-\d\d-\d\dT' -and $ls[1] -like 'report: *agents\out\agA\latest.md' -and $ls[2] -eq 'ledger: tp/wA routing_note') '2b same TAIL-RELAY format (header, report path, ledger pointer)'
    T ($ls.Count -le 30) "2c message <= 30 lines (got $($ls.Count))"
    T ($txt -match 'DECISION needed: ship patch 1 or 2' -and $txt -match "question: should it be case-insensitive") '2d late DECISION and QUESTION lines survive the cut'
    T ($txt -match '# agA report' -and $txt -match 'Built X in /root/x.patch') '2e first lines of latest.md present'
    T (-not ($txt -match 'detail line 70')) '2f the middle of a long report is not copied'
    $mc = (Get-Content -LiteralPath (Msgs 'agC')[0].FullName -Raw)
    T ($mc -match '^TAIL-RELAY agC FAILED ' -and $mc -match 'STATUS FAILED' -and $mc -match 'RESULT 1 FAIL') '3a FAILED agent relayed with Kind FAILED'
    $md = (Get-Content -LiteralPath (Msgs 'agD')[0].FullName -Raw)
    T ($md -match '^TAIL-RELAY agD FAILED ' -and $md -match 'STOPPED-CONTEXT' -and $md -match 'agD2' -and $md -match 'agD\.handoff\.md' -and $md -match 'QUESTION: keep the old DB') '3b STOPPED-CONTEXT: handoff file used, respawn line, QUESTION kept'
    $recs = @((RunPs $ledger @('records')).out | ConvertFrom-Json | ForEach-Object { $_ })
    $ra = $recs | Where-Object { $_.agent -eq 'agA' }
    T ($ra.result_file -like '*agents\out\agA\latest.md' -and $ra.acked_by_new_coordinator -eq $false) '3c ledger result_file recorded by tail-relay (reused, not forked)'
    $log = Get-Content -LiteralPath (Join-Path $tmp 'tail\autorelay.log') -Raw
    T (([regex]::Matches($log, 'tail-autorelay tS relayed ')).Count -eq 3) '4a one log line per relay'
    # idempotent
    $r2 = Auto @('-Once')
    T ((Msgs 'agA').Count -eq 1 -and (Msgs 'agC').Count -eq 1 -and (Msgs 'agD').Count -eq 1 -and $r2.out -notmatch 'relayed ') '5a second run relays nothing again (state file)'
    $st = Get-Content -LiteralPath (Join-Path $tmp 'tail\tS.autorelay.json') -Raw | ConvertFrom-Json
    T ($st.relayed.'agA|DONE' -and $st.relayed.'agC|FAILED' -and $st.relayed.'agD|STOPPED-CONTEXT' -and -not $st.relayed.'agB|RUNNING') '5b state file keys agent|STATE'
    # a new status of the same agent is a new event: agD respawned status FAILED later relays again
    Status 'agD' 'FAILED'
    $r3 = Auto @('-Once')
    T ($r3.out -match 'relayed agD FAILED' -and (Msgs 'agD').Count -eq 2) '5c same agent, new status = relayed once more'
    # looping mode: agB finishes while it runs; it must exit by itself when everything is relayed
    $job = Start-Job -ScriptBlock { param($f, $t, $k, $p) $env:KAH_RUNS_DIR = $t; $env:KPL_DIR = $p; & powershell -NoProfile -ExecutionPolicy Bypass -File $f -TailSession tS -PollSec 1 2>&1 | ForEach-Object { "$_" } } -ArgumentList $auto, $tmp, '', $env:KPL_DIR
    Start-Sleep -Seconds 3
    T ((Msgs 'agB').Count -eq 0 -and $job.State -eq 'Running') '6a loop mode keeps polling while an agent runs'
    Report 'agB' @('# agB done', 'RESULT 9 PASS')
    Status 'agB' 'DONE'
    $null = Wait-Job $job -Timeout 40
    $jo = (Receive-Job $job) -join "`n"
    T ($job.State -eq 'Completed' -and (Msgs 'agB').Count -eq 1 -and $jo -match 'relayed agB DONE' -and $jo -match 'exit: all 4 owned agent\(s\) relayed') '6b loop relays agB when it finishes and exits when all owned agents are relayed'
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    # flag gone: exit at once
    Status 'agB' 'RUNNING'
    Remove-Item -LiteralPath (Join-Path $tmp 'tail\tS.flag') -Force
    $r4 = Auto @()
    T ($r4.code -eq 0 -and $r4.out -match 'exit: tail flag gone') '7a exits when the tail flag is gone'
    # -Skip: agent relayed by hand
    Flag 'tS' @('agE'); Status 'agE' 'DONE'
    $r5 = Auto @('-Once', '-Skip', 'agE')
    T ((Msgs 'agE').Count -eq 0 -and $r5.out -match 'exit: all [0-9]+ owned') '8a -Skip leaves a manually relayed agent out'
    # relay message fallback with no report files: status file text
    Flag 'tS' @('agF'); Status 'agF' 'DONE'
    $r6 = Auto @('-Once')
    $mf = Msgs 'agF'
    T ($mf.Count -eq 1 -and (Get-Content -LiteralPath $mf[0].FullName -Raw) -match 'agF \| DONE') '9a no report file: summary falls back to the status file'
    # quote in a report line does not break the relay
    Report 'agG' @('# agG', 'said "hello" to the DB'); Status 'agG' 'DONE'; Flag 'tS' @('agG')
    $r7 = Auto @('-Once')
    T ((Msgs 'agG').Count -eq 1 -and (Get-Content -LiteralPath (Msgs 'agG')[0].FullName -Raw) -match "said 'hello' to the DB") '9b double quotes in a report line survive the relay'
    # tail-ack + PI-18 helper still sees the relay
    . (Join-Path $here 'tail-mode.ps1')
    $fl = Read-TailFlag (Get-TailFlagPath $tmp 'tS')
    $rs = Get-TailRelayState $tmp $fl 'agG' ((Get-Date).AddMinutes(-2))
    T ($rs.Relayed) '10a tail-mode (PI-18) recognises the autorelay file as a relay of the agent'
} finally {
    foreach ($k in $old.Keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item -LiteralPath "Env:$k" -Value $old[$k] } }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
