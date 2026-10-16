# waker-lanes-selftest.ps1 (PI-16): Stop hook + lane game locks (game-<N>.lock). Offline: temp runs dir (KAH_RUNS_DIR), test switches
# KAH_GUARD_TEST_LANE_PROCS / KAH_GUARD_TEST_STATE5090 / KAH_GUARD_TEST_STOP_AFTER_GAME, a dummy sleeping powershell as the waker. No real lane is touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\waker-lanes-selftest.ps1 [-Guard <candidate kenshi-waker-guard.ps1>]
param([string]$Guard = '')
$ErrorActionPreference = 'Stop'
$auto = $PSScriptRoot
if (-not $Guard) { $Guard = Join-Path $auto 'hooks\kenshi-waker-guard.ps1' }
$d = Join-Path ([IO.Path]::GetTempPath()) ("wakerlanes-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'agents'), (Join-Path $d 'inflight') | Out-Null
$keys = 'KAH_RUNS_DIR', 'KAH_AGENT_NAME', 'KAH_GUARD_TEST_LANE_PROCS', 'KAH_GUARD_TEST_STATE5090', 'KAH_GUARD_TEST_STOP_AFTER_GAME', 'KAH_GUARD_TEST_NO_WAKER'
$old = @{}; foreach ($k in $keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:KAH_RUNS_DIR = $d
foreach ($k in 'KAH_AGENT_NAME', 'KAH_GUARD_TEST_NO_WAKER') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$n) { if ($ok) { $script:pass++; "SELFTEST PASS $n" } else { $script:fail++; "SELFTEST FAIL $n" } }
function Set-Status([string]$name, [int]$ageMin) {
    $f = Join-Path $d "agents\$name.status"
    Set-Content -LiteralPath $f -Value @("$name | RUNNING | $(Get-Date -Format 'yyyy-MM-dd HH:mm')", 'task: t', 'latest: l', 'outputs: o', 'next: n') -Encoding UTF8
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
function Set-Lock([int]$n, [string]$txt) { Set-Content -LiteralPath (Join-Path $d "game-$n.lock") -Value @($txt, (Get-Date -Format s)) -Encoding UTF8 }
$waker = $null
try {
    # ---- library ----
    . (Join-Path $auto 'lane-lock-lib.ps1')
    foreach ($n in 3, 4, 5) { Set-Lock $n "rig5090-lane$n" }
    Set-Lock 2 'urgent_live_5090'
    $env:KAH_GUARD_TEST_LANE_PROCS = '3,4,5'
    $l = @(Get-LiveLaneGames $d)
    T ((($l | ForEach-Object N) -join ',') -eq '3,4,5') "3 lane games with locks and processes are live (got $(($l | ForEach-Object N) -join ','))"
    T ($l[0].Lock -eq 'rig5090-lane3' -and $l[0].Lane -eq '5090-i3') 'lock text and lane name read (BOM/second line stripped)'
    $env:KAH_GUARD_TEST_LANE_PROCS = '4'
    T ((($l = @(Get-LiveLaneGames $d)) | ForEach-Object N) -join ',' -eq '4') 'locks of dead lanes (no process from that instance) are stale: not live'
    $env:KAH_GUARD_TEST_LANE_PROCS = '0'
    T (@(Get-LiveLaneGames $d).Count -eq 0) 'no lane process at all: every lock is stale'
    Remove-Item Env:KAH_GUARD_TEST_LANE_PROCS -ErrorAction SilentlyContinue
    # lane-idle problems
    Set-Status 'imm26-5090-i3op3' 1; Set-Status 'imm26-5090-i4op3' 1; Set-Status 'imm26-5090-ctxop322' 1
    $live = @(3, 4, 5 | ForEach-Object { [pscustomobject]@{ N = $_; Lane = "5090-i$_"; Lock = 'x' } })
    T (@(Get-LaneIdleProblems $live $d).Count -eq 0) 'all 3 lanes have a fresh RUNNING operator: no lane problem'
    Set-Status 'imm26-5090-i4op3' 30
    $p = @(Get-LaneIdleProblems $live $d)
    T ($p.Count -eq 1 -and $p[0] -match 'LANE IDLE 5090-i4') "operator silent 30 min: LANE IDLE 5090-i4 ($($p -join '|'))"
    T (@(Get-LaneIdleProblems @($live[0], $live[2]) $d).Count -eq 0) 'problem of a lane that is not live is not reported'
    Set-Status 'imm26-5090-i4op3' 1
    Remove-Item (Join-Path $d 'agents\imm26-5090-ctxop322.status')
    $p = @(Get-LaneIdleProblems $live $d)
    T ($p.Count -eq 1 -and $p[0] -match 'LANE NO-OPERATOR 5090-i5') 'live lane without a RUNNING operator: LANE NO-OPERATOR'
    Set-Status 'imm26-5090-ctxop322' 1

    # ---- the hook ----
    $waker = Start-Process powershell -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 120' -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 800
    function Run-Hook([string]$state, [string]$procs) {
        $in = Join-Path $d 'hook.in'; $o = Join-Path $d 'hook.out'; $e = Join-Path $d 'hook.err'
        [IO.File]::WriteAllText($in, '{"cwd":"C:\\KenshiModding","hook_event_name":"Stop"}')
        $env:KAH_GUARD_TEST_STATE5090 = $state; $env:KAH_GUARD_TEST_LANE_PROCS = $procs; $env:KAH_GUARD_TEST_STOP_AFTER_GAME = '1'
        $p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Guard, 'stop' -RedirectStandardInput $in -RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru -WindowStyle Hidden
        [pscustomobject]@{ Code = $p.ExitCode; Out = ((Get-Content -Raw -LiteralPath $o -ErrorAction SilentlyContinue) -as [string]); Err = ((Get-Content -Raw -LiteralPath $e -ErrorAction SilentlyContinue) -as [string]) }
    }
    $idleGame = 'IDLE-GAME kenshi=no lock=rig5090 no batch running for 19 min ()'
    # 1. 3 lane games running, game.lock free, default slot reads IDLE-GAME: not blocked as idle
    $h = Run-Hook $idleGame '3,4,5'
    T ($h.Code -eq 0 -and $h.Out -match 'PASSED-5090-GAME' -and $h.Out -notmatch 'block') "3 lane games + game.lock free + default slot IDLE-GAME: not blocked ($($h.Out.Trim()) / $($h.Err.Trim()))"
    T ($h.Err -match '3 lane game') 'the pass is explained on stderr'
    # 2. a lane is idle: still blocked, names the lane
    Set-Status 'imm26-5090-i4op3' 30
    $h = Run-Hook $idleGame '3,4,5'
    T ($h.Out -match '"decision":"block"' -and $h.Out -match 'LANE IDLE 5090-i4') "idle lane under a running game: still blocked and named ($($h.Out.Trim()))"
    Set-Status 'imm26-5090-i4op3' 1
    # 3. stale (dead) lane locks + game.lock held by an idle default slot: blocked as before
    Set-Content -LiteralPath (Join-Path $d 'game.lock') -Value 'rig5090' -Encoding UTF8
    $h = Run-Hook $idleGame '0'
    T ($h.Out -match '"decision":"block"' -and $h.Out -match 'game slot is idle') "stale lane locks (no process) do not hide an idle default slot ($($h.Out.Trim()))"
    # 4. a live lane with no operator among the stale ones: blocked by lane-idle
    Remove-Item (Join-Path $d 'agents\imm26-5090-i3op3.status')
    $h = Run-Hook $idleGame '3'
    T ($h.Out -match '"decision":"block"' -and $h.Out -match 'LANE NO-OPERATOR 5090-i3') "live lane without operator blocks ($($h.Out.Trim()))"
    Remove-Item (Join-Path $d 'game.lock')
    # 5. stale lane lock only: not counted as running work
    $h = Run-Hook $idleGame '0'
    T ($h.Out -notmatch 'lane games running') 'stale lane lock never appears as running work'
    # 6. the real hook must still carry the original checks
    $src = Get-Content -Raw -LiteralPath $Guard
    T ($src -match "game slot is idle" -and $src -match "no waker is running" -and $src -match "the 5090 is idle" -and $src -match 'the 4080 is idle') 'idle/waker/4080 catches still present in the hook'
} finally {
    if ($waker) { try { Stop-Process -Id $waker.Id -Force -ErrorAction SilentlyContinue } catch { } }
    foreach ($k in $keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item "Env:$k" $old[$k] } }
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST waker-lanes $script:pass pass / $script:fail fail"
if ($script:fail) { exit 1 }
exit 0
