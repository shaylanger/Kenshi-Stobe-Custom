# tail-cheap-selftest.ps1: selftest for the CHEAP TAIL fixes (Shay 2026-10-16, imm26-wk2): a tail relays finished agents with NO model turn.
#   - agents in no program ledger (registered in agents\ids.json by the tail's session) are owned and relayed
#   - a relay moved to inbox\coordinator\done\ (or delivered\, or any subdirectory) counts as relayed/delivered
#   - duplicate relays are not re-sent (state file, manual relay file, two concurrent passes, second long-running instance)
#   - tail-wait.ps1 does not wake for a finished agent that is being relayed; it relays it itself (autorelay -Once) and exits only when all are
#     released (or when a relay is genuinely missing after the retry window)
# Uses the *.candidate version of tail-mode / tail-wait / tail-wait-lib / tail-autorelay when it exists, else the plain file, copied into a temp
# scripts dir together with tail-relay.ps1 and program-ledger.ps1. Temp runs dir only (KAH_RUNS_DIR / KPL_DIR); never touches C:\KenshiTestRuns.
# Prints PASS/FAIL lines and "SELFTEST PASS n/m" (exit 1 on any FAIL).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tail-cheap-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$sd = Join-Path $tmp 'scripts'; $rdir = Join-Path $tmp 'runs'
$inbox = Join-Path $rdir 'inbox\coordinator'
$old = @{ KAH_RUNS_DIR = $env:KAH_RUNS_DIR; KPL_DIR = $env:KPL_DIR; KPL_WS = $env:KPL_WS; KAH_TAIL_AUTORELAY = $env:KAH_TAIL_AUTORELAY; KAH_TAIL_NO_AUTORELAY = $env:KAH_TAIL_NO_AUTORELAY }
New-Item -ItemType Directory -Force -Path $sd, (Join-Path $rdir 'agents'), (Join-Path $rdir 'tail'), (Join-Path $rdir 'programs'), (Join-Path $tmp 'ws'), $inbox | Out-Null
foreach ($f in 'tail-mode.ps1', 'tail-wait-lib.ps1', 'tail-wait.ps1', 'tail-autorelay.ps1') {
    $src = if (-not $env:KAH_SELFTEST_ORIGINAL -and (Test-Path (Join-Path $here "$f.candidate"))) { Join-Path $here "$f.candidate" } else { Join-Path $here $f }
    Copy-Item -LiteralPath $src -Destination (Join-Path $sd $f)
}
foreach ($f in 'tail-relay.ps1', 'program-ledger.ps1') { Copy-Item -LiteralPath (Join-Path $here $f) -Destination (Join-Path $sd $f) }
$env:KAH_RUNS_DIR = $rdir; $env:KPL_DIR = Join-Path $rdir 'programs'; $env:KPL_WS = Join-Path $tmp 'ws'
Remove-Item Env:KAH_TAIL_AUTORELAY, Env:KAH_TAIL_NO_AUTORELAY -ErrorAction SilentlyContinue
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
function RunPs([string]$file, [string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $file @a 2>&1
    [pscustomobject]@{ code = $LASTEXITCODE; out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Status([string]$n, [string]$state, [int]$ageMin = 0) {
    $p = Join-Path $rdir "agents\$n.status"
    Set-Content -LiteralPath $p -Value @("$n | $state | 2026-10-16 17:00", 'task: t') -Encoding UTF8
    if ($ageMin) { (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddMinutes(-$ageMin) }
}
function Report([string]$n, [string[]]$lines) {
    $d = Join-Path $rdir "agents\out\$n"; New-Item -ItemType Directory -Force -Path $d | Out-Null
    Set-Content -LiteralPath (Join-Path $d 'latest.md') -Value $lines -Encoding UTF8
}
function Msgs([string]$n) { @(Get-ChildItem -LiteralPath $inbox -Filter "*-tail-$n.msg" -File -Recurse -ErrorAction SilentlyContinue) }
function Flag([string]$sess, [string[]]$agents, [datetime]$created = (Get-Date).AddMinutes(-30)) {
    $f = [pscustomobject]@{ session = $sess; pid = $PID; created = $created.ToString('o'); new_coordinator_inbox = $inbox; agents = $agents }
    [IO.File]::WriteAllText((Join-Path $rdir "tail\$sess.flag"), ($f | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}
function Ids([hashtable]$map) {   # name -> session
    $o = [ordered]@{}
    foreach ($k in $map.Keys) { $o[$k] = [ordered]@{ id = "id$k"; session = $map[$k]; at = (Get-Date).ToString('s') } }
    [IO.File]::WriteAllText((Join-Path $rdir 'agents\ids.json'), ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
}
function Auto([string[]]$extra) { RunPs (Join-Path $sd 'tail-autorelay.ps1') (@('-TailSession', 'tS', '-PollSec', '1') + $extra) }
try {
    T ($env:KAH_RUNS_DIR.StartsWith($tmp)) '0 temp dirs in use'
    # ---- 1. agent in NO ledger and NOT in the flag: owned through ids.json (session == tail session), relayed without a model
    Flag 'tS' @()
    Status 'agX' 'RUNNING'; Status 'agOther' 'DONE'; Status 'agOld' 'DONE' 120
    Ids @{ agX = 'tS'; agOther = 'someone-else'; agOld = 'tS' }
    Report 'agX' @('# agX report', 'RESULT 1 PASS ok', 'DECISION: ship it?')
    $r = Auto @('-Once')
    T ((Msgs 'agX').Count -eq 0 -and $r.out -notmatch 'exit: the tail owns no agents') '1a ids.json agent owned (flag + ledger empty); RUNNING = nothing relayed yet'
    T ((Msgs 'agOther').Count -eq 0) '1b agent registered by ANOTHER session is not relayed'
    T ((Msgs 'agOld').Count -eq 0) '1c agent that finished 2 h before the tail started is not relayed'
    Status 'agX' 'DONE'
    $r = Auto @('-Once')
    $m = Msgs 'agX'
    T ($m.Count -eq 1 -and $r.out -match 'relayed agX DONE') '1d status DONE -> relay file appears under inbox\coordinator (no model turn)'
    $txt = if ($m.Count) { Get-Content -LiteralPath $m[0].FullName -Raw } else { '' }
    T ($txt -match '^TAIL-RELAY agX DONE ' -and $txt -match '\(agent not in a program ledger\)' -and $txt -match 'DECISION: ship it\?') '1e agent not in any ledger still gets a complete relay (DECISION line kept)'
    $r = Auto @('-Once')
    T ((Msgs 'agX').Count -eq 1 -and $r.out -notmatch 'relayed ') '1f second pass does not re-send (duplicate relay guard)'

    # ---- 2. relay moved to done\ / delivered\ / another subdirectory counts as relayed + delivered (dot-sourced candidate tail-mode)
    . (Join-Path $sd 'tail-mode.ps1')
    $fl = Read-TailFlag (Get-TailFlagPath $rdir 'tS')
    $doneAt = (Get-Date).AddMinutes(-2)
    $rs = Get-TailRelayState $rdir $fl 'agX' $doneAt
    T ($rs.Relayed -and -not $rs.Delivered) '2a fresh relay at the inbox top level = relayed, not delivered'
    foreach ($sub in 'done', 'delivered', 'archive\2026-10') {
        $d = Join-Path $inbox $sub; New-Item -ItemType Directory -Force -Path $d | Out-Null
        $nm = (Get-Date).ToString('yyyyMMdd-HHmmss') + '-tail-agX.msg'
        Move-Item -LiteralPath (Msgs 'agX')[0].FullName -Destination (Join-Path $d $nm) -Force
        $rs = Get-TailRelayState $rdir $fl 'agX' $doneAt
        T ($rs.Relayed -and $rs.Delivered) "2b relay moved to ${sub}\ = relayed and delivered"
        Move-Item -LiteralPath (Join-Path $d $nm) -Destination (Join-Path $inbox $nm) -Force
    }
    # relay file gone altogether: the autorelay state file still proves it was relayed
    Remove-Item -LiteralPath (Msgs 'agX')[0].FullName -Force
    $rs = Get-TailRelayState $rdir $fl 'agX' $doneAt
    T ($rs.Relayed -and -not $rs.Delivered) '2c relay file deleted: autorelay state file still counts as relayed'
    # the agent set: delivered relay in done\ releases the agent (not pending)
    $d = Join-Path $inbox 'done'; Set-Content -LiteralPath (Join-Path $d ((Get-Date).ToString('yyyyMMdd-HHmmss') + '-tail-agX.msg')) -Value 'TAIL-RELAY agX DONE'
    $set = @(Get-TailAgentSet $rdir $fl)
    $ax = $set | Where-Object { $_.Agent -eq 'agX' }
    T ($set.Agent -contains 'agX' -and $set.Agent -notcontains 'agOther' -and $set.Agent -notcontains 'agOld' -and $ax -and -not $ax.Pending) '2d agent set = ids agent only, released once its relay sits in done\'

    # ---- 3. manual relay first: autorelay records it, does not send a second one
    Status 'agM' 'DONE'; Flag 'tS' @('agM'); Report 'agM' @('# agM', 'RESULT 2 PASS')
    $null = RunPs (Join-Path $sd 'tail-relay.ps1') @('-Agent', 'agM', '-Kind', 'DONE', '-Summary', 'relayed by hand')
    $r = Auto @('-Once')
    T ((Msgs 'agM').Count -eq 1 -and $r.out -match 'already-relayed agM') '3a manual tail-relay.ps1 relay is not duplicated by the autorelay'

    # ---- 4. two concurrent passes relay one agent exactly once; a second long-running instance exits at once
    Status 'agC' 'DONE'; Flag 'tS' @('agC'); Report 'agC' @('# agC', 'RESULT 3 PASS')
    $psi = { param($f) $p = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $f, '-TailSession', 'tS', '-PollSec', '1', '-Once') -PassThru -WindowStyle Hidden; $p }
    $p1 = & $psi (Join-Path $sd 'tail-autorelay.ps1'); $p2 = & $psi (Join-Path $sd 'tail-autorelay.ps1')
    $null = $p1.WaitForExit(60000); $null = $p2.WaitForExit(60000)
    T ((Msgs 'agC').Count -eq 1) "4a two concurrent -Once passes relay the agent once (got $((Msgs 'agC').Count))"
    Status 'agL' 'RUNNING'; Flag 'tS' @('agL')
    $job = Start-Job -ScriptBlock { param($f, $t) $env:KAH_RUNS_DIR = $t; $env:KPL_DIR = "$t\programs"; & powershell -NoProfile -ExecutionPolicy Bypass -File $f -TailSession tS -PollSec 1 2>&1 | ForEach-Object { "$_" } } -ArgumentList (Join-Path $sd 'tail-autorelay.ps1'), $rdir
    Start-Sleep -Seconds 4
    $r2 = Auto @()
    T ($r2.code -eq 0 -and $r2.out -match 'another auto-relay instance already runs') '4b a second long-running instance for the same tail exits at once'
    Status 'agL' 'DONE'
    $null = Wait-Job $job -Timeout 40
    $jo = (Receive-Job $job) -join "`n"
    T ($job.State -eq 'Completed' -and (Msgs 'agL').Count -eq 1 -and $jo -match 'exit: all \d+ owned') '4c the running instance relays agL when it finishes and exits'
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    # ---- 5. tail-wait: a finished agent is relayed BY THE WAIT (no daemon, no model); it ends only when all are released
    Remove-Item -LiteralPath (Join-Path $rdir 'tail\tS.autorelay.json') -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $inbox -Recurse -File | Remove-Item -Force
    Flag 'tS' @(); Ids @{ agW = 'tS' }
    Status 'agW' 'RUNNING'
    $wo = Join-Path $tmp 'wait.out'
    $wp = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $sd 'tail-wait.ps1'), '-Session', 'tS', '-Runs', $rdir, '-IntervalSec', '1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $wo
    Start-Sleep -Seconds 4
    T (-not $wp.HasExited) '5a wait keeps waiting while the ids.json agent runs'
    Report 'agW' @('# agW', 'RESULT 4 PASS')
    Status 'agW' 'DONE'
    $t0 = Get-Date
    while ((Msgs 'agW').Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Seconds 1 }
    T ((Msgs 'agW').Count -eq 1) '5b agent DONE -> the wait relayed it itself (autorelay -Once retry), no model involved'
    Start-Sleep -Seconds 6
    T (-not $wp.HasExited) '5c wait does NOT exit for a finished agent that is relayed (relay awaiting delivery)'
    $dd = Join-Path $inbox 'done'; New-Item -ItemType Directory -Force -Path $dd | Out-Null
    Move-Item -LiteralPath (Msgs 'agW')[0].FullName -Destination $dd -Force
    $null = $wp.WaitForExit(40000)
    $woTxt = if (Test-Path $wo) { Get-Content -LiteralPath $wo -Raw } else { '' }
    T ($wp.HasExited -and $woTxt -match 'TAIL-WAIT tS EXIT all owned agents are released') '5d relay moved to done\ = delivered -> wait ends "all released" (not an endless instant-exit loop)'
    if (-not $wp.HasExited) { Stop-Process -Id $wp.Id -Force -ErrorAction SilentlyContinue }

    # ---- 6. genuinely missing relay: only after the retry window does the tail get needed
    . (Join-Path $sd 'tail-wait-lib.ps1')
    Ids @{}
    Get-ChildItem -LiteralPath $inbox -Recurse -File | Remove-Item -Force
    Remove-Item -LiteralPath (Join-Path $rdir 'tail\tS.autorelay.json') -Force -ErrorAction SilentlyContinue
    Flag 'tS' @('agZ'); Status 'agZ' 'DONE' 0
    $fl = Read-TailFlag (Get-TailFlagPath $rdir 'tS')
    T (-not [string](Get-TailWaitAction $rdir $fl)) '6a finished 0 min ago, not relayed yet: still in the autorelay window, the model is not needed'
    Status 'agZ' 'DONE' 4
    $act = [string](Get-TailWaitAction $rdir $fl)
    T ($act -match 'agent agZ needs the tail' -and $act -match 'not relayed yet') '6b still unrelayed after 4 min: genuinely missing, the tail is needed'
    Set-Content -LiteralPath (Join-Path $inbox ((Get-Date).ToString('yyyyMMdd-HHmmss') + '-tail-agZ.msg')) -Value 'TAIL-RELAY agZ DONE'
    T (-not [string](Get-TailWaitAction $rdir $fl)) '6c relay file present: the tail is not needed'

    # ---- 7. enter: records ids.json agents; autostarts the relay only in the real runs dir or with KAH_TAIL_AUTORELAY=1
    Remove-Item -LiteralPath (Join-Path $rdir 'tail\tE.flag') -Force -ErrorAction SilentlyContinue
    Status 'agE1' 'RUNNING'; Ids @{ agE1 = 'tE' }
    $eo = (RunPs (Join-Path $sd 'tail-mode.ps1') @('enter', '-Session', 'tE', '-ClaudePid', "$PID", '-Runs', $rdir)).out
    T ($eo -match 'agents: agE1' -and $eo -notmatch 'AUTO-RELAY started') '7a enter records the ids.json agent; no autostart in a sandbox runs dir'
    Remove-Item -LiteralPath (Join-Path $rdir 'tail\tE.flag') -Force
    $env:KAH_TAIL_AUTORELAY = '1'
    $eo2 = (RunPs (Join-Path $sd 'tail-mode.ps1') @('enter', '-Session', 'tE', '-ClaudePid', "$PID", '-Runs', $rdir)).out
    Remove-Item Env:KAH_TAIL_AUTORELAY
    $apid = 0; if ($eo2 -match 'AUTO-RELAY started \(pid (\d+)') { $apid = [int]$Matches[1] }
    T ($apid -gt 0) '7b KAH_TAIL_AUTORELAY=1: enter starts the auto-relay detached'
    Start-Sleep -Seconds 3
    $arLog = Get-Content -LiteralPath (Join-Path $rdir 'tail\autorelay.log') -Raw -ErrorAction SilentlyContinue
    T ($arLog -match 'tail-autorelay tE start') '7c the detached auto-relay is running (log start line)'
    Status 'agE1' 'DONE'
    $t0 = Get-Date
    while ((Msgs 'agE1').Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -lt 40) { Start-Sleep -Seconds 1 }
    T ((Msgs 'agE1').Count -ge 1) '7d the autostarted relay relays agE1 with no further action'
    Remove-Item -LiteralPath (Join-Path $rdir 'tail\tE.flag') -Force -ErrorAction SilentlyContinue
    if ($apid) { $t0 = Get-Date; while ((Get-Process -Id $apid -ErrorAction SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep -Seconds 1 }; if (Get-Process -Id $apid -ErrorAction SilentlyContinue) { Stop-Process -Id $apid -Force } }
} finally {
    foreach ($k in $old.Keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item -LiteralPath "Env:$k" -Value $old[$k] } }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
