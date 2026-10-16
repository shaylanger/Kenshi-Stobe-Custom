# agent-guard-selftest.ps1: selftest of the handoff guards (agent-guard-lib.ps1, agent-status.ps1, agent-abandon.ps1,
# hooks\kenshi-waker-guard.ps1 agent checks, inflight-claims.sh, event-wait.sh STATUS line, session-start health lines).
# Everything runs against a temp runs dir (env KAH_RUNS_DIR); the real C:\KenshiTestRuns is never touched.
# Usage: powershell -NoProfile -File tools\automation\agent-guard-selftest.ps1      Last line: "SELFTEST agent-guard: PASS|FAIL (n/m)".
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("agentguard-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ag = Join-Path $tmp 'agents'
New-Item -ItemType Directory -Force -Path $ag, (Join-Path $tmp 'inflight') | Out-Null
$env:KAH_RUNS_DIR = $tmp
$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$what) { if ($c) { $script:pass++ } else { $script:fail++; "  FAIL: $what" } }
function New-St([string]$name, [string]$state, [string]$task, [double]$ageMin, [string]$next = '') {
    $f = Join-Path $ag "$name.status"
    @("$name | $state | 2026-10-15 12:00", "task: $task", 'latest: x', 'outputs: y', "next: $next") | Set-Content -LiteralPath $f -Encoding UTF8
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
. (Join-Path $here 'agent-guard-lib.ps1')
try {
    # ---- fixture: the 2026-10-15 imm26 situation + edge cases ----
    New-St 'wpA' 'STOPPED-CONTEXT' 'WP-A items 1,12,13' 120
    New-St 'wpA2' 'STOPPED-CONTEXT' 'orphaned: parent coordinator session ended' 60
    New-St 'wpA3' 'RUNNING' 'WP-A resume' 5
    New-St 'N2' 'STOPPED-CONTEXT' 'N2 native package' 120
    New-St 'N2b' 'STOPPED-CONTEXT' 'orphaned: parent' 60
    New-St 'N2c' 'RUNNING' 'N2 native package' 4
    New-St 'wpC1' 'STOPPED-CONTEXT' 'WP-C1 items 2,5,6,7' 120
    New-St 'wpC1b' 'STOPPED-CONTEXT' 'orphaned: parent' 60
    New-St 'wpC1c' 'RUNNING' 'WP-C1 tests+patch' 3
    New-St 'wpC2' 'STOPPED-CONTEXT' 'WP-C2 items 8,9,11' 120
    New-St 'wpC2c' 'RUNNING' 'WP-C2 finish' 3
    New-St 'rig-op1' 'STOPPED-CONTEXT' 'orphaned: parent' 60
    New-St 'rig-op2' 'RUNNING' '5090 baseline rows' 3
    New-St 'wpD' 'RUNNING' 'WP-D items 14,18' 200          # stale RUNNING, superseded by a DONE successor
    New-St 'wpD3' 'DONE' 'WP-D items 14,18,19' 2
    New-St 'dbg' 'STOPPED-CONTEXT' 'investigate crash in module X' 100
    New-St 'dbg-2' 'STOPPED-CONTEXT' 'investigate crash in module X' 50
    New-St 'dbg-3' 'DONE' 'investigate crash in module X' 10
    New-St 'taskdone' 'FAILED' 'build the widget thoroughly' 100   # superseded by a DONE status with the same task, other name
    New-St 'widgetwork' 'DONE' 'build the widget thoroughly' 20
    # genuinely open / no false positives
    New-St 'lone' 'STOPPED-CONTEXT' 'lone task needs respawn' 30 'do the next thing'
    New-St 'failed1' 'FAILED' 'something failed' 30
    New-St 'wpC9' 'STOPPED-CONTEXT' 'WP-C9 other package' 100        # wpC9 vs wpC1/2c: different stem numbers must not supersede
    New-St 'oldstop' 'STOPPED-CONTEXT' 'ancient task' (60 * 30)
    New-St 'dropped' 'STOPPED-CONTEXT' 'abandoned task' 30
    Set-Content (Join-Path $ag 'dropped.abandoned') 'test'
    New-St 'r40' 'RUNNING' 'running 40 min' 40
    New-St 'r35' 'RUNNING' 'running 35 min' 35
    New-St 'r50' 'RUNNING' 'running 50 min' 50
    Set-Content (Join-Path $ag 'garbage.status') 'owner: /root/something else'     # malformed: skipped, never throws
    [IO.File]::WriteAllBytes((Join-Path $ag 'binary.status'), [byte[]](0, 1, 2, 255, 254))
    Set-Content (Join-Path $ag 'empty.status') ''

    $r = Get-AgentReport
    $open = @($r.Open | ForEach-Object Name) -join ','
    $orph = @($r.Orphaned | ForEach-Object Name) -join ','
    $fly = @($r.InFlight | ForEach-Object Name)
    foreach ($n in 'wpA', 'wpA2', 'N2', 'N2b', 'wpC1', 'wpC1b', 'wpC2', 'rig-op1', 'dbg', 'dbg-2', 'taskdone') { Ok ($open -notmatch "(^|,)$n(,|$)") "$n has a successor, must not be reported (open=$open)" }
    foreach ($n in 'lone', 'failed1', 'wpC9', 'oldstop') { Ok ($open -match "(^|,)$n(,|$)") "$n has no successor, must be reported (open=$open)" }
    Ok ($open -notmatch 'dropped') 'abandoned agent is not reported'
    Ok (@($r.OpenRecent | ForEach-Object Name) -notcontains 'oldstop') 'a status older than 18 h is not in OpenRecent (Stop hook ignores it)'
    Ok (@($r.OpenRecent | ForEach-Object Name) -contains 'lone') 'recent open agent is in OpenRecent'
    Ok ($orph -match 'r35' -and $orph -match 'r50' -and $orph -match 'r40' -and $orph -notmatch 'wpA3') "orphaned = RUNNING >= 30 min: $orph"
    Ok ($orph -notmatch 'wpD') 'stale RUNNING with a DONE successor is not orphaned'
    Ok ($fly -contains 'r40' -and $fly -contains 'wpA3' -and $fly -contains 'r35' -and $fly -notcontains 'r50') "in-flight = RUNNING updated < 45 min: $($fly -join ',')"
    Ok ($fly -notcontains 'r50') 'RUNNING 50 min old is not in-flight'
    Ok ($r.Count -ge 20) "malformed files skipped, valid ones read ($($r.Count))"
    # respawn text
    $lone = $r.Open | Where-Object Name -eq 'lone'
    $txt = Get-AgentRespawn $lone
    Ok ($txt -match 'FRESH' -and $txt -match 'lone2' -and $txt -match 'lone\.status' -and $txt -match 'do the next thing') "respawn text: $txt"
    Ok ((Get-NextAgentName 'wpA') -eq 'wpA2' -and (Get-NextAgentName 'N2b') -eq 'N2c' -and (Get-NextAgentName 'wpC1') -eq 'wpC1b' -and (Get-NextAgentName 'dbg-2') -eq 'dbg-3') 'next-name rules'
    $hl = @(Get-AgentHealthLines)
    Ok (@($hl | Where-Object { $_ -like 'ORPHANED*r50*' }).Count -eq 1) 'session-start health: ORPHANED line with respawn text'
    Ok (@($hl | Where-Object { $_ -like 'NO SUCCESSOR lone*' }).Count -eq 1) 'session-start health: NO SUCCESSOR line'
    Ok (@($hl | Where-Object { $_ -like '*oldstop*older than 18 h*' }).Count -eq 1) 'old open agent listed with the 18 h note'
    Ok (-not ($hl -match 'wpA3|dropped')) 'running/abandoned agents not listed as open'

    # ---- PI-17: own-evidence freshness keeps an in-session agent out of ORPHANED (separate sandbox runs dir) ----
    $pi = Join-Path $tmp 'pi17'; $pa = Join-Path $pi 'agents'
    New-Item -ItemType Directory -Force -Path (Join-Path $pa 'out'), (Join-Path $pi 'lane-a'), (Join-Path $pi 'lane-b'), (Join-Path $pi 'foreign') | Out-Null
    function New-PSt([string]$name, [double]$ageMin) {
        $f = Join-Path $pa "$name.status"
        @("$name | RUNNING | 2026-10-15 12:00", 'task: pi17', 'latest: x', 'outputs: y', 'next: ') | Set-Content -LiteralPath $f -Encoding UTF8
        (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
    }
    function New-Ev([string]$path, [double]$ageMin) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        Set-Content -LiteralPath $path -Value 'x' -Encoding ascii
        (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
    }
    @{ 'lane-x' = @{ ops = @('pi-lane'); dirs = @('lane-a', '..\foreign', 'foreign') }; 'lane-y' = @{ ops = @('someone-else'); dirs = @('lane-b') } } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $pi 'lane-owners.json') -Encoding UTF8
    New-PSt 'pi-log' 31;   New-Ev (Join-Path $pa 'out\pi-log.log') 2                  # own poll log fresh
    New-PSt 'pi-dir' 45;   New-Ev (Join-Path $pa 'out\pi-dir\rows\r1.txt') 3           # own evidence dir fresh, status 45 min old
    New-PSt 'pi-lane' 40;  New-Ev (Join-Path $pi 'lane-a\sub\res.json') 4              # its lane out dir (lane-owners.json ops) fresh
    New-PSt 'pi-oldev' 31; New-Ev (Join-Path $pa 'out\pi-oldev.log') 20                # own log but older than 10 min
    New-PSt 'pi-foreign' 31; New-Ev (Join-Path $pa 'out\somebody-else.log') 1; New-Ev (Join-Path $pi 'foreign\f.txt') 1; New-Ev (Join-Path $pi 'lane-b\f.txt') 1   # only foreign files fresh
    New-PSt 'pi-none' 31                                                               # no evidence at all
    New-PSt 'pi-stonly' 31; New-Ev (Join-Path $pa 'out\pi-stonly\x.status') 1          # a .status file never counts
    New-PSt 'pi-sess' 31;  New-Ev (Join-Path $pa 'out\pi-sess.log') 1; Set-Content (Join-Path $pa 'pi-sess.session.json') '{}'   # INDEPENDENT: the host judges liveness, rule unchanged
    New-PSt 'pi-trav' 31                                                               # lane dir '..\foreign' must be ignored (and 'foreign' is not its lane)
    $pr = Get-AgentReport -AgentsDir $pa
    $po = @($pr.Orphaned | ForEach-Object Name); $pf = @($pr.InFlight | ForEach-Object Name)
    Ok ($po -notcontains 'pi-log') "PI-17: silent 31 min + fresh own log is not orphaned (orphaned=$($po -join ','))"
    Ok ($po -notcontains 'pi-dir') 'PI-17: fresh own evidence dir is not orphaned'
    Ok ($po -notcontains 'pi-lane') 'PI-17: fresh lane out dir (lane-owners.json) is not orphaned'
    Ok ($pf -contains 'pi-dir' -and $pf -contains 'pi-lane' -and $pf -contains 'pi-log') "PI-17: working agent counts as in-flight even when its status is >= 45 min old ($($pf -join ','))"
    Ok ($po -contains 'pi-oldev') 'PI-17: own log older than 10 min => still orphaned'
    Ok ($po -contains 'pi-foreign') 'PI-17: silent 31 min + only a foreign file fresh => still orphaned'
    Ok ($po -contains 'pi-none') 'PI-17: no evidence => still orphaned (30 min catch unchanged)'
    Ok ($po -contains 'pi-stonly') 'PI-17: a fresh .status file in the evidence dir does not count'
    Ok ($po -contains 'pi-sess') 'PI-17: agent with a session.json keeps the old rule'
    Ok ($po -contains 'pi-trav') 'PI-17: no evidence for pi-trav even with a traversal lane dir'
    Ok ($null -eq (Get-AgentEvidenceAgeMin 'pi-none' (Get-Date) $pi)) 'PI-17: Get-AgentEvidenceAgeMin returns $null without evidence'
    $ea = Get-AgentEvidenceAgeMin 'pi-log' (Get-Date) $pi
    Ok ($null -ne $ea -and $ea -lt 5) "PI-17: Get-AgentEvidenceAgeMin returns the log age ($ea)"
    Ok ($null -eq (Get-AgentEvidenceAgeMin '..\foreign' (Get-Date) $pi)) 'PI-17: a path-like agent name is refused'

    # ---- the hook (agent checks only) ----
    function Run-Hook([string]$mode, [string]$json, [hashtable]$extraEnv = @{}) {
        $in = Join-Path $tmp 'hook.in'; $o = Join-Path $tmp 'hook.out'; $e = Join-Path $tmp 'hook.err'
        [IO.File]::WriteAllText($in, $json)
        $env:KAH_GUARD_TEST_ONLY_AGENTS = '1'
        foreach ($k in $extraEnv.Keys) { Set-Item "Env:$k" $extraEnv[$k] }
        $p = Start-Process powershell -ArgumentList '-NoProfile', '-File', (Join-Path $here 'hooks\kenshi-waker-guard.ps1'), $mode -RedirectStandardInput $in -RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru -WindowStyle Hidden
        foreach ($k in $extraEnv.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
        [pscustomobject]@{ Code = $p.ExitCode; Out = ((Get-Content -Raw -LiteralPath $o -ErrorAction SilentlyContinue) -as [string]); Err = ((Get-Content -Raw -LiteralPath $e -ErrorAction SilentlyContinue) -as [string]) }
    }
    $stopJson = '{"cwd":"C:\\KenshiModding","hook_event_name":"Stop"}'
    $h = Run-Hook 'stop' $stopJson
    Ok ($h.Code -eq 0 -and $h.Out -match '"decision":"block"' -and $h.Out -match 'lone' -and $h.Out -match 'FRESH' -and $h.Out -notmatch 'oldstop') "hook blocks on an unsuperseded stopped agent and names the respawn: $($h.Out.Substring(0, [Math]::Min(160, $h.Out.Length)))"
    $h = Run-Hook 'stop' '{"cwd":"C:\\KenshiModding","stop_hook_active":true}'
    Ok ($h.Code -eq 0 -and -not $h.Out) 'stop_hook_active: allowed (blocks once per turn)'
    $h = Run-Hook 'stop' 'not json at all'
    Ok ($h.Code -eq 0 -and -not $h.Out) 'garbage stdin: fails open'
    $h = Run-Hook 'stop' '{"cwd":"D:\\elsewhere"}'
    Ok ($h.Code -eq 0 -and -not $h.Out) 'cwd outside the workspace: allowed'
    Set-Content (Join-Path $tmp 'handoff.ready') 'x'
    $h = Run-Hook 'stop' $stopJson
    Ok ($h.Code -eq 0 -and -not $h.Out) 'fresh handoff.ready: allowed (the next session owns the agents)'
    Remove-Item (Join-Path $tmp 'handoff.ready')
    # resolve every open agent -> the hook only reports the in-flight list
    foreach ($n in 'lone', 'failed1', 'wpC9') { Set-Content (Join-Path $ag "$n.abandoned") 'test' }
    (Get-Item (Join-Path $ag 'oldstop.status')).LastWriteTime = (Get-Date).AddDays(-2)
    $h = Run-Hook 'stop' $stopJson
    Ok ($h.Code -eq 0 -and $h.Out -match '^INFLIGHT: ' -and $h.Out -match 'wpA3' -and $h.Out -match 'r40' -and $h.Out -notmatch 'r50') "no open agents: nothing blocks, RUNNING < 45 min counts as in-flight ($($h.Out.Trim()))"
    $h = Run-Hook 'pre' '{"cwd":"C:\\KenshiModding","tool_name":"Bash","tool_input":{"command":"sleep 300"}}'
    Ok ($h.Code -eq 2 -and $h.Err -match 'event-wait\.sh') "pre hook: long sleep denied with the event-wait pointer: $($h.Err.Trim())"
    $h = Run-Hook 'pre' '{"cwd":"C:\\KenshiModding","tool_name":"Bash","tool_input":{"command":"sleep 60"}}'
    Ok ($h.Code -eq 0) 'pre hook: short sleep allowed'

    # ---- agent-status.ps1: marker + todo lifecycle ----
    $st = Join-Path $here 'agent-status.ps1'
    $runStatus = { param($n, $s, $t) & powershell -NoProfile -File $st $n $s $t 'step' 'out' 'nxt' | Out-Null }
    & $runStatus 'zz1' 'RUNNING' 'zz task'
    Ok (Test-Path (Join-Path $tmp 'inflight\zz1')) 'RUNNING creates the inflight marker'
    & $runStatus 'zz1' 'STOPPED-CONTEXT' 'zz task'
    Ok ((Test-Path (Join-Path $tmp 'inflight\zz1')) -and (Test-Path (Join-Path $tmp 'respawn\zz1.todo'))) 'STOPPED-CONTEXT keeps the marker and writes respawn\zz1.todo'
    Ok ((Get-Content -Raw (Join-Path $tmp 'respawn\zz1.todo')) -match 'task: zz task' -and (Get-Content -Raw (Join-Path $tmp 'respawn\zz1.todo')) -match 'zz1\.status') 'todo names task and status path'
    $rep2 = Get-AgentReport
    Ok (@($rep2.Todos) -contains 'zz1') 'the todo is listed while the agent has no successor'
    & $runStatus 'zz2' 'RUNNING' 'zz task'
    Ok (-not (Test-Path (Join-Path $tmp 'respawn\zz1.todo'))) 'a successor RUNNING deletes the predecessor todo'
    Ok (Test-Path (Join-Path $tmp 'inflight\zz1')) 'predecessor marker is kept (coordinator removes it later)'
    & $runStatus 'zz2' 'DONE' 'zz task'
    Ok (-not (Test-Path (Join-Path $tmp 'inflight\zz2'))) 'DONE deletes the marker'
    'x' | Set-Content (Join-Path $tmp 'inflight\batchmark')
    & $runStatus 'zzm' 'RUNNING' 'marker test'
    Set-Content (Join-Path $tmp 'inflight\zzm') '/mnt/c/some/outdir'
    & $runStatus 'zzm' 'RUNNING' 'marker test'
    Ok ((Get-Content -Raw (Join-Path $tmp 'inflight\zzm')).Trim() -eq '/mnt/c/some/outdir') 'an existing marker keeps its content on RUNNING'
    & powershell -NoProfile -File (Join-Path $here 'agent-abandon.ps1') 'zz1' 'selftest' | Out-Null
    Ok (Test-Path (Join-Path $ag 'zz1.abandoned')) 'agent-abandon.ps1 writes the .abandoned file'
    Ok (-not (Test-Path (Join-Path $tmp 'inflight\zz1'))) 'agent-abandon.ps1 deletes the agent inflight marker'
    Ok (Test-Path (Join-Path $tmp 'inflight\zzm')) 'agent-abandon.ps1 leaves other markers alone'

    # ---- quiet Stop-hook block (Shay order #5): count + only the 2 newest markers + one next action ----
    $q = Join-Path ([IO.Path]::GetTempPath()) ("agentguardq-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $q 'inflight'), (Join-Path $q 'agents') | Out-Null
    $ages = [ordered]@{ mkOld1 = 300; mkOld2 = 200; mkOld3 = 100; mkNew2 = 20; mkNew1 = 3 }
    foreach ($k in $ages.Keys) { $f = Join-Path $q "inflight\$k"; Set-Content $f 'x'; (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-$ages[$k]) }
    $hookIn = (@{ cwd = 'C:\KenshiModding'; hook_event_name = 'Stop' } | ConvertTo-Json -Compress)
    $env:KAH_RUNS_DIR = $q; $env:KAH_GUARD_TEST_NO_WAKER = '1'; Remove-Item Env:KAH_GUARD_TEST_ONLY_AGENTS -ErrorAction SilentlyContinue
    $ho = ($hookIn | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'hooks\kenshi-waker-guard.ps1') stop 2>$null) -join "`n"
    $env:KAH_RUNS_DIR = $tmp; Remove-Item Env:KAH_GUARD_TEST_NO_WAKER -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $q -Recurse -Force -ErrorAction SilentlyContinue
    Ok ($ho -match '"decision":"block"' -and $ho -match 'work is in flight') 'quiet block: still blocks while markers are in flight and no waker runs'
    Ok ($ho -match 'inflight markers: 5 \(newest 2: mkNew1 \(3 min old\), mkNew2 \(20 min old\)\)') "quiet block: count 5 plus the 2 newest with ages: $ho"
    Ok ($ho -notmatch 'mkOld1|mkOld2|mkOld3') 'quiet block: older markers are not listed'
    Ok ($ho -match 'Next action: start the background command .*event-wait\.sh') 'quiet block: the next action names the waker command (not an empty string)'

    # ---- line endings + WSL syntax of every .sh this tooling touches (2026-10-15: a CRLF event-wait.sh killed the waker) ----
    $shs = 'event-wait.sh', 'event-sweep.sh', 'rig-health.sh', 'inflight-claims.sh'
    foreach ($sh in $shs) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $here $sh))
        Ok (-not ($bytes -contains 13)) "$sh has LF line endings only"
    }
    # one line ending in a comment: the pipe appends CR LF and the CR must land inside the comment
    $wslScript = "for f in event-wait.sh event-sweep.sh rig-health.sh inflight-claims.sh; do bash -n /mnt/c/KenshiModding/tools/automation/`$f 2>&1 && echo OK:`$f; done #"
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $wslOut = @($wslScript | & wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s 2>$null | ForEach-Object { "$_".Trim() })
    $ErrorActionPreference = $eap
    if ($LASTEXITCODE -ne 0 -and -not $wslOut.Count) { 'SKIP wsl bash -n: wsl.exe unavailable' }
    else { foreach ($sh in $shs) { Ok ($wslOut -contains "OK:$sh") "wsl bash -n $sh" } }

    # ---- bash parts: inflight-claims.sh, event-wait.sh ----
    $bash = (Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $bash) { 'SKIP bash parts: no bash on PATH' }
    else {
        $gb = '/' + ($tmp.Substring(0, 1).ToLower()) + ($tmp.Substring(2) -replace '\\', '/')
        Remove-Item (Join-Path $tmp 'inflight\*') -Force
        foreach ($n in 'zzm', '4080-x', 'batch1') { Set-Content (Join-Path $tmp "inflight\$n") 'x' }
        $env:MSYS_NO_PATHCONV = '1'
        $cl = @(& $bash (Join-Path $here 'inflight-claims.sh') $gb) | ForEach-Object { "$_".Trim() }
        Ok (($cl -join ',') -eq 'batch1') "inflight-claims.sh ignores 4080-* and agent-name markers: $($cl -join ',')"
        # event-wait.sh: a status written after the wait started ends it with the respawn text
        $ewo = Join-Path $tmp 'ew.out'
        $env:KAH_RUNS = $gb
        $p = Start-Process $bash -ArgumentList (Join-Path $here 'event-wait.sh'), '--no-health', '--poll', '1', '--backstop', '40', '--me', 'selftest' -RedirectStandardOutput $ewo -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        & powershell -NoProfile -File $st 'ew1' 'STOPPED-CONTEXT' 'event wait task' 'step' 'out' 'nxt' | Out-Null
        [void]$p.WaitForExit(30000)
        $eo = (Get-Content -Raw -LiteralPath $ewo -ErrorAction SilentlyContinue) -as [string]
        Ok ($eo -match 'EVENT STATUS ew1 STOPPED-CONTEXT' -and $eo -match 'respawn fresh event wait task from' -and $eo -match 'ew1\.status') "event-wait.sh STATUS line carries the respawn text: $($eo.Trim())"
        if (-not $p.HasExited) { $p.Kill() }
    }
} finally {
    Remove-Item Env:KAH_RUNS_DIR, Env:KAH_RUNS, Env:KAH_GUARD_TEST_ONLY_AGENTS, Env:MSYS_NO_PATHCONV -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST agent-guard: $(if ($script:fail) { 'FAIL' } else { 'PASS' }) ($script:pass/$($script:pass + $script:fail))"
exit ([int]($script:fail -gt 0))
