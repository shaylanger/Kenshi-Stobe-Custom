# agent-host-ensure-selftest.ps1: offline checks of agent-host-ensure.ps1 and the rollcall kind in session-start (temp KAH_RUNS_DIR, -DryRun only).
$ens = Join-Path $PSScriptRoot 'agent-host-ensure.ps1'
$tmp = Join-Path $env:TEMP ("ahe-selftest-" + [guid]::NewGuid().ToString('N'))
$q = Join-Path $tmp 'agent-queue'; $ag = Join-Path $tmp 'agents'
New-Item -ItemType Directory -Force -Path $q, $ag | Out-Null
$env:KAH_RUNS_DIR = $tmp
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { $script:pass++; "ok   $n" } else { $script:fail++; "FAIL $n $d" } }
function Ens { (& powershell -NoProfile -ExecutionPolicy Bypass -File $ens -DryRun) -join ' ' }
function Beat([int]$agoSec) { @{ pid = $PID; beat = (Get-Date).AddSeconds(-$agoSec).ToString('o'); live = 0; queued = 0; max = 4 } | ConvertTo-Json | Set-Content (Join-Path $q 'host.state.json') }
function Status([string]$name, [string]$state) { "$name | $state | selftest`nlatest: x" | Set-Content (Join-Path $ag "$name.status") }

$r = Ens; Check 'no work, no daemon: idle-down' ($r -match 'HOST idle-down') $r
'{}' | Set-Content (Join-Path $q 'x.job'); $r = Ens; Check 'queued job, no daemon: would restart' ($r -match 'down-would-restart' -and $r -match 'queued_jobs=1') $r
Set-Content (Join-Path $q 'agent-host.pid') "$PID"; Beat 5; $r = Ens; Check 'live pid + fresh beat: up' ($r -match 'HOST up') $r
Beat 300; $r = Ens; Check 'live pid + beat 300 s old: would restart' ($r -match 'down-would-restart') $r
Beat 5; Set-Content (Join-Path $q 'agent-host.pid') '999999'; $r = Ens; Check 'dead pid: would restart' ($r -match 'down-would-restart' -and $r -match 'pid_alive=False') $r
Remove-Item (Join-Path $q 'x.job'); $r = Ens; Check 'dead pid, no work: idle-down' ($r -match 'idle-down') $r
Status 'indep1' 'RUNNING'; '{"launcher_pid":999998,"claude_pid":999997,"started":"2026-10-15T10:00:00-06:00"}' | Set-Content (Join-Path $ag 'indep1.session.json')
$r = Ens; Check 'RUNNING independent agent, daemon dead: would restart' ($r -match 'down-would-restart' -and $r -match 'independent_running=1') $r
Status 'inproc1' 'RUNNING'
$rc = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'agent-rollcall.ps1')) -join "`n"
Check 'rollcall kind=INDEPENDENT with session.json' ($rc -match 'ROLLCALL indep1 kind=INDEPENDENT proc=DEAD') $rc
Check 'rollcall kind=INPROC without session.json' ($rc -match 'ROLLCALL inproc1 kind=INPROC') $rc
$ss = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'session-start.ps1') -Brief -AgentsOnly 2>&1) -join "`n"
Check 'session-start prints ROLLCALL lines' ($ss -match 'ROLLCALL inproc1 kind=INPROC' -and $ss -match 'ROLLCALL indep1 kind=INDEPENDENT') ($ss.Substring(0, [math]::Min(300, $ss.Length)))
Check 'session-start prints HOST line' ($ss -match 'HOST (up|down|idle)') 
Check 'session-start flags INPROC agents as dying at handoff' ($ss -match 'INPROC.*(die|dies|lost)') 
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
$n = $pass + $fail
if ($fail) { "SELFTEST FAIL $pass/$n"; exit 1 } else { "SELFTEST PASS $pass/$n" }
