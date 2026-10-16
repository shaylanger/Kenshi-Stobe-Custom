# agent-successor-selftest.ps1: selftest of successor rule (e) (PI-11): agent-guard-lib.ps1 Get-AgentReport / Get-AgentSuccessorVia,
# the Stop hook line, session-start's accepted lines source, and agent-successor.ps1. Temp runs dir only (KAH_RUNS_DIR / KPL_DIR).
# Usage: powershell -NoProfile -File tools\automation\agent-successor-selftest.ps1     Last line: "SELFTEST agent-successor: PASS|FAIL (n/m)".
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("agentsucc-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ag = Join-Path $tmp 'agents'; $pg = Join-Path $tmp 'programs'
New-Item -ItemType Directory -Force -Path $ag, $pg, (Join-Path $tmp 'inflight') | Out-Null
$env:KAH_RUNS_DIR = $tmp
$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$what) { if ($c) { $script:pass++ } else { $script:fail++; "  FAIL: $what" } }
function New-St([string]$name, [string]$state, [string]$task, [double]$ageMin) {
    $f = Join-Path $ag "$name.status"
    @("$name | $state | 2026-10-15 12:00", "task: $task", 'latest: x', 'outputs: y', 'next: ') | Set-Content -LiteralPath $f -Encoding UTF8
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
function Wp([string]$id, [string]$agent, [string[]]$succ = @()) { [ordered]@{ id = $id; agent = $agent; successors = @($succ); state = 'running' } }
. (Join-Path $here 'agent-guard-lib.ps1')
try {
    # ---- ledger + lane table ----
    $wps = @(
        (Wp 'wpOne' 'pa' @('pa-next')),
        (Wp 'wpTwo' 'qa'),
        (Wp 'wpThree' 'zz-live'),
        (Wp 'wpRa' 'ra' @('ra-new')),
        (Wp 'wpSa' 'sa' @('sa-fin')),
        (Wp 'wpTa' 'ta' @('ta-two')),
        (Wp 'wpUa' 'ua' @('ua-old')),
        (Wp 'wpFour' 'ma' @('ma-lane')),
        (Wp 'wpFive' 'na' @('na-fresh')),
        (Wp 'wpO' 'oa' @('oa-mate'))
    )
    [ordered]@{ name = 'prog'; md = ''; wps = $wps } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $pg 'prog.json') -Encoding UTF8
    $laneObj = [ordered]@{
        'lane-q' = @{ ops = @('la', 'la-new'); dirs = @() }
        'lane-r' = @{ ops = @('ma'); dirs = @() }
        'lane-s' = @{ ops = @('ma-lane'); dirs = @() }
        'lane-t' = @{ ops = @('na'); dirs = @() }
    }
    $laneObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tmp 'lane-owners.json') -Encoding UTF8

    New-St 'pa' 'STOPPED-CONTEXT' 'travel region rows i3' 100;       New-St 'pa-next' 'RUNNING' 'operator rows 23-d' 3      # accepted via wp
    New-St 'qa' 'STOPPED-CONTEXT' 'qa task' 100;                     New-St 'zz-live' 'RUNNING' 'other wp work' 2            # unrelated live agent
    New-St 'ra' 'STOPPED-CONTEXT' 'ra task' 100;                     New-St 'ra-new' 'RUNNING' 'ra resume' 50                # successor stale (>= 45 min)
    New-St 'sa' 'STOPPED-CONTEXT' 'sa task' 100;                     New-St 'sa-fin' 'DONE' 'something else entirely' 5      # DONE does not count under (e)
    New-St 'ta' 'STOPPED-CONTEXT' 'ta task' 100;                     New-St 'ta-two' 'STOPPED-CONTEXT' 'ta other' 5         # stopped successor does not count
    New-St 'ua' 'STOPPED-CONTEXT' 'ua task' 10;                      New-St 'ua-old' 'RUNNING' 'older than ua' 20            # successor older than X
    New-St 'la' 'STOPPED-CONTEXT' 'la task' 100;                     New-St 'la-new' 'RUNNING' 'la resume' 3                 # accepted via lane (no wp)
    New-St 'ma' 'STOPPED-CONTEXT' 'ma task' 100;                     New-St 'ma-lane' 'RUNNING' 'other lane op' 3               # same wp but two different lanes
    New-St 'na' 'STOPPED-CONTEXT' 'na task' 100;                     New-St 'na-fresh' 'RUNNING' 'na resume' 3               # in a lane, successor in no lane, same wp
    New-St 'oa' 'RUNNING' 'orphan' 60;                               New-St 'oa-mate' 'RUNNING' 'oa mate' 2                     # a stale RUNNING orphan is not hidden by (e)

    $r = Get-AgentReport
    $open = @($r.Open | ForEach-Object Name); $orph = @($r.Orphaned | ForEach-Object Name); $acc = @($r.Accepted)
    Ok ($open -notcontains 'pa') "live successor under another name on the same wp is accepted (open=$($open -join ','))"
    Ok ($acc -contains 'accepted successor pa-next for pa via ledger wp wpOne') "accepted line names successor, old agent and the wp (acc=$($acc -join ' | '))"
    Ok ($open -contains 'qa') 'an unrelated live agent on another wp/lane does NOT hide a dead agent'
    Ok ($open -contains 'ra') 'a successor RUNNING but stale (50 min) does NOT count'
    Ok ($open -contains 'sa') 'a DONE agent with another task does not count under rule (e)'
    Ok ($open -contains 'ta' -and $open -contains 'ta-two') 'a stopped agent is not a successor under rule (e)'
    Ok ($open -contains 'ua') 'a successor older than X does not count'
    Ok ($open -notcontains 'la' -and $acc -contains 'accepted successor la-new for la via lane lane-q') "same lane via lane-owners.json is accepted (acc=$($acc -join ' | '))"
    Ok ($open -contains 'ma') 'X and S in two different lanes: the shared wp does not count'
    Ok ($open -notcontains 'na' -and $acc -contains 'accepted successor na-fresh for na via ledger wp wpFive') 'X in a lane, S in no lane, same wp: accepted via wp'
    Ok ($orph -contains 'oa') 'a stale RUNNING orphan is still reported (rule (e) is for STOPPED-CONTEXT/FAILED only)'
    Ok (-not ($acc -match 'accepted successor \S+ for (qa|ra|sa|ta|ua|ma|oa) ')) 'no accepted line for the rejected ones'
    Ok (@(Get-AgentAcceptedLines) -contains 'accepted successor pa-next for pa via ledger wp wpOne') 'session-start source Get-AgentAcceptedLines carries the line'
    # rule (e) must not change the old rules: a basic-rule pair needs no ledger
    New-St 'basic' 'STOPPED-CONTEXT' 'basic task' 100; New-St 'basic2' 'RUNNING' 'basic resume' 2
    Ok (@((Get-AgentReport).Open | ForEach-Object Name) -notcontains 'basic') 'rules (a)-(c) still work unchanged'
    Ok (-not (@((Get-AgentReport).Accepted) -match 'for basic ')) 'basic-rule successors are not reported as ledger-accepted'

    # ---- fail closed: a broken ledger or lane file turns rule (e) off ----
    Set-Content -LiteralPath (Join-Path $pg 'zz-bad.json') '{ not json'
    $r2 = Get-AgentReport
    Ok (@($r2.Open | ForEach-Object Name) -contains 'pa' -and $r2.Accepted.Count -eq 0) 'unparseable ledger: rule (e) does not apply, the agent is reported'
    Remove-Item -LiteralPath (Join-Path $pg 'zz-bad.json') -Force
    Set-Content -LiteralPath (Join-Path $tmp 'lane-owners.json') 'garbage'
    $r3 = Get-AgentReport
    Ok (@($r3.Open | ForEach-Object Name) -contains 'pa' -and $r3.Accepted.Count -eq 0) 'unparseable lane-owners.json: rule (e) does not apply'
    Remove-Item -LiteralPath (Join-Path $tmp 'lane-owners.json') -Force
    $r4 = Get-AgentReport
    Ok (@($r4.Open | ForEach-Object Name) -notcontains 'pa') 'without lane-owners.json the ledger tie still works'
    $laneObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tmp 'lane-owners.json') -Encoding UTF8
    Remove-Item -LiteralPath $pg -Recurse -Force
    $r5 = Get-AgentReport
    Ok (@($r5.Open | ForEach-Object Name) -contains 'pa' -and -not (@($r5.Accepted) -match 'ledger wp')) 'no ledger at all: no ledger-based acceptance (lane ties still work)'
    New-Item -ItemType Directory -Force -Path $pg | Out-Null
    [ordered]@{ name = 'prog'; md = ''; wps = $wps } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $pg 'prog.json') -Encoding UTF8

    # ---- the Stop hook says which successor it accepted ----
    function Run-Hook([string]$json) {
        $in = Join-Path $tmp 'hook.in'; $o = Join-Path $tmp 'hook.out'; $e = Join-Path $tmp 'hook.err'
        [IO.File]::WriteAllText($in, $json)
        $env:KAH_GUARD_TEST_ONLY_AGENTS = '1'
        $p = Start-Process powershell -ArgumentList '-NoProfile', '-File', (Join-Path $here 'hooks\kenshi-waker-guard.ps1'), 'stop' -RedirectStandardInput $in -RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru -WindowStyle Hidden
        [pscustomobject]@{ Code = $p.ExitCode; Out = ((Get-Content -Raw -LiteralPath $o -ErrorAction SilentlyContinue) -as [string]); Err = ((Get-Content -Raw -LiteralPath $e -ErrorAction SilentlyContinue) -as [string]) }
    }
    $sj = '{"cwd":"C:\\KenshiModding","hook_event_name":"Stop"}'
    $h = Run-Hook $sj
    Ok ($h.Code -eq 0 -and $h.Out -match '"decision":"block"' -and $h.Out -match 'accepted successor pa-next for pa via ledger wp wpOne' -and $h.Out -match 'qa' ) "hook block names the accepted pair and still blocks the real orphans: $($h.Out.Substring(0, [Math]::Min(120, $h.Out.Length)))"
    Ok ($h.Err -match 'accepted successor pa-next for pa via ledger wp wpOne') 'hook writes the accepted line to stderr'
    foreach ($n in 'qa', 'ra', 'sa', 'ta', 'ta-two', 'ua', 'ma', 'basic') { Set-Content (Join-Path $ag "$n.abandoned") 'test' }
    $h = Run-Hook $sj
    Ok ($h.Code -eq 0 -and $h.Out -match 'INFLIGHT: ' -and $h.Out -match 'accepted successor pa-next for pa via ledger wp wpOne' -and $h.Out -notmatch '"decision"') "all other agents handled: hook allows and still prints the accepted line ($($h.Out.Trim() -replace '\s+', ' '))"

    # ---- agent-successor.ps1 ----
    $env:KPL_DIR = $pg
    New-St 'qa-fix' 'RUNNING' 'qa resume' 1
    Remove-Item (Join-Path $ag 'qa.abandoned') -ErrorAction SilentlyContinue
    Ok (@((Get-AgentReport).Open | ForEach-Object Name) -contains 'qa') 'before registering, qa-fix (other wp) does not hide qa'
    $o1 = & powershell -NoProfile -File (Join-Path $here 'agent-successor.ps1') 'qa' 'qa-fix'
    $code1 = $LASTEXITCODE
    Ok ($code1 -eq 0 -and "$o1" -match 'registered successor qa-fix for qa in ledger prog wp wpTwo') "agent-successor registers the pair: $o1"
    $j = Get-Content -Raw -LiteralPath (Join-Path $pg 'prog.json') | ConvertFrom-Json
    Ok (@(($j.wps | Where-Object id -eq 'wpTwo').successors) -contains 'qa-fix') 'ledger wpTwo.successors now lists qa-fix'
    $rr = Get-AgentReport
    Ok (@($rr.Open | ForEach-Object Name) -notcontains 'qa' -and @($rr.Accepted) -contains 'accepted successor qa-fix for qa via ledger wp wpTwo') 'after registering, the live qa-fix is the accepted successor of qa'
    $o2 = & powershell -NoProfile -File (Join-Path $here 'agent-successor.ps1') 'qa' 'qa-fix'
    Ok ($LASTEXITCODE -eq 0 -and "$o2" -match 'nothing to do') 'registering twice is a no-op'
    $o3 = & powershell -NoProfile -File (Join-Path $here 'agent-successor.ps1') 'nobody-here' 'qa-fix'
    Ok ($LASTEXITCODE -eq 1 -and "$o3" -match 'not the agent/successor') 'an old agent that is in no wp exits 1'
    & powershell -NoProfile -File (Join-Path $here 'agent-successor.ps1') 'only-one' | Out-Null
    Ok ($LASTEXITCODE -eq 1) 'missing argument exits 1'
} finally {
    Remove-Item Env:KAH_RUNS_DIR, Env:KPL_DIR, Env:KAH_GUARD_TEST_ONLY_AGENTS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST agent-successor: $(if ($script:fail) { 'FAIL' } else { 'PASS' }) ($script:pass/$($script:pass + $script:fail))"
exit ([int]($script:fail -gt 0))
