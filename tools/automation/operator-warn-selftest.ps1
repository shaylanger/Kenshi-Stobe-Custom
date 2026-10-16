# operator-warn-selftest.ps1: selftest for agent-status.ps1 WARN-120k marker + operator-warn.ps1 (temp runs dir; never touches C:\KenshiTestRuns).
#   powershell -NoProfile -ExecutionPolicy Bypass -File operator-warn-selftest.ps1 [-AgentStatus <path>]
param([string]$AgentStatus = (Join-Path $PSScriptRoot 'agent-status.ps1'))
$ErrorActionPreference = 'Stop'
$ow = Join-Path $PSScriptRoot 'operator-warn.ps1'
$runs = Join-Path ([IO.Path]::GetTempPath()) "ow-selftest-$PID"
Remove-Item -LiteralPath $runs -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $runs 'agents') | Out-Null
$env:KAH_RUNS_DIR = $runs
$fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { "PASS $n" } else { "FAIL $n $d"; $script:fail++ } }
function St($n, $state, $task, $step) { & powershell -NoProfile -ExecutionPolicy Bypass -File $AgentStatus $n $state $task $step 'out' 'next' | Out-Null }
function Ow([string[]]$a = @()) { @(& powershell -NoProfile -ExecutionPolicy Bypass -File $ow -Runs $runs @a 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ }) }
@{ '9090-i3' = @{ ops = @('opx3', 'opx2'); dirs = @('d1') } } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runs 'lane-owners.json') -Encoding UTF8

# 1 no marker, no event
Check 'no-marker-no-event' ((Ow).Count -eq 0)
# 2 ordinary RUNNING does not write a marker
St 'opx3' RUNNING 'lane 9090-i3 operator' 'testing row 5'
Check 'plain-running-no-marker' (-not (Test-Path (Join-Path $runs 'agents\opx3.warn')))
Check 'plain-running-no-event' ((Ow).Count -eq 0)
# 3 WARN-120k -> marker -> exactly one event
St 'opx3' RUNNING 'lane 9090-i3 operator' 'WARN-120k context at 120k, finishing row 5'
Check 'marker-written' (Test-Path (Join-Path $runs 'agents\opx3.warn'))
$e = @(Ow)
Check 'one-event' ($e.Count -eq 1) "got $($e.Count): $e"
$line = "$($e[0])"
Check 'event-prefix' ($line -like 'OPERATOR WARN opx3 lane 9090-i3 *') $line
Check 'successor-name-skips-used' ($line -like '*successor=opx4 *') $line   # opx3 -> opx4
Check 'brief-cmd' ($line -like '*lane-brief.ps1 9090-i3 -Out *\opx4.brief.md -Name opx4 -Predecessor opx3*') $line
Check 'prompt-two-lines' ($line -like '*You are opx4, lane 9090-i3. Read *opx4.brief.md*// Predecessor opx3 keeps running*task*be exactly: lane 9090-i3 operator*') $line
Check 'register-hint' ($line -like '*operator-warn.ps1 -Register opx3 opx4') $line
Check 'spawn-md-written' (Test-Path (Join-Path $runs 'agents\opx3.warn.spawn.md'))
# 4 no duplicate (also after the operator keeps writing normal RUNNING steps)
Check 'no-duplicate' ((Ow).Count -eq 0)
St 'opx3' RUNNING 'lane 9090-i3 operator' 'testing row 6'
Check 'no-duplicate-after-normal-step' ((Ow).Count -eq 0)
Check 'marker-kept-while-running' (Test-Path (Join-Path $runs 'agents\opx3.warn'))
# 5 -Peek does not mark as seen
St 'opx3' DONE 'lane 9090-i3 operator' 'handed over'
Check 'done-clears-marker' (-not (Test-Path (Join-Path $runs 'agents\opx3.warn')))
Check 'done-clears-spawn-md' (-not (Test-Path (Join-Path $runs 'agents\opx3.warn.spawn.md')))
Check 'done-no-event' ((Ow).Count -eq 0)
St 'opx3' RUNNING 'lane 9090-i3 operator' 'WARN-120k again'
Check 'peek-prints' ((Ow @('-Peek')).Count -eq 1)
Check 'peek-does-not-mark' ((Ow).Count -eq 1)
Check 'after-mark-quiet' ((Ow).Count -eq 0)
# 6 a stale marker of a non-RUNNING agent (killed operator) is dropped silently
St 'opx3' STOPPED-CONTEXT 'lane 9090-i3 operator' 'x'
Set-Content (Join-Path $runs 'agents\opx3.warn') 'stale'
Check 'stale-marker-no-event' ((Ow).Count -eq 0)
Check 'stale-marker-removed' (-not (Test-Path (Join-Path $runs 'agents\opx3.warn')))
# 7 a later warn of the same name fires again after the marker was cleared
St 'opx3' RUNNING 'lane 9090-i3 operator' 'WARN-120k third'
Check 'refire-after-clear' ((Ow).Count -eq 1)
# 8 successor naming: name without trailing digit -> name2 ; existing status skips
St 'solo' RUNNING 'some task' 'WARN-120k x'
$e2 = @(Ow)
Check 'non-lane-event' ($e2.Count -eq 1 -and "$($e2[0])" -like 'OPERATOR WARN solo lane - successor=solo2 *') "$e2"
# 9 -Register puts the successor first, atomically
$r = @(Ow @('-Register', 'opx3', 'opx4'))
Check 'register-output' (($r -join ' ') -eq 'REGISTERED lane 9090-i3: opx4,opx3,opx2') ($r -join ' ')
$j = Get-Content (Join-Path $runs 'lane-owners.json') -Raw | ConvertFrom-Json
Check 'register-json' ((@($j.'9090-i3'.ops) -join ',') -eq 'opx4,opx3,opx2' -and (@($j.'9090-i3'.dirs) -join ',') -eq 'd1')
$r2 = @(Ow @('-Register', 'opx3', 'opx4'))
Check 'register-idempotent' (($r2 -join ' ') -eq 'REGISTERED lane 9090-i3: opx4,opx3,opx2')
# with opx4 now registered, the next warn of opx4 goes to opx5
St 'opx4' RUNNING 'lane 9090-i3 operator' 'WARN-120k'
$e3 = @(Ow)
Check 'next-successor-opx5' ($e3.Count -eq 1 -and "$($e3[0])" -like '*successor=opx5 *') "$e3"
# 10 PI-19: -InLane puts the successor first when the predecessor is in no lane; idempotent; unknown lane still fails
$r3 = @(Ow @('-Register', 'unlisted-op', 'newop1', '-InLane', '9090-i3'))
Check 'register-inlane-output' (($r3 -join ' ') -eq 'REGISTERED lane 9090-i3: newop1,opx4,opx3,opx2') ($r3 -join ' ')
$r4 = @(Ow @('-Register', 'unlisted-op', 'newop1', '-InLane', '9090-i3'))
Check 'register-inlane-idempotent' (($r4 -join ' ') -eq 'REGISTERED lane 9090-i3: newop1,opx4,opx3,opx2') ($r4 -join ' ')
$j2 = Get-Content (Join-Path $runs 'lane-owners.json') -Raw | ConvertFrom-Json
Check 'register-inlane-json' ((@($j2.'9090-i3'.ops) -join ',') -eq 'newop1,opx4,opx3,opx2' -and (@($j2.'9090-i3'.dirs) -join ',') -eq 'd1')
$ErrorActionPreference = 'Continue'; $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $ow -Runs $runs -Register unlisted-op newop2 -InLane nolane 2>$null; $ec = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
Check 'register-inlane-unknown-lane-exit2' ($ec -eq 2)Remove-Item -LiteralPath $runs -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:KAH_RUNS_DIR -ErrorAction SilentlyContinue
if ($fail) { "operator-warn-selftest FAILED ($fail)"; exit 1 }
'operator-warn-selftest OK'; exit 0
