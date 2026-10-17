# waker-persist-hook-selftest.ps1 (PI-51): the Stop + PreToolUse hook accepts the persistent waker (fresh heartbeat) and keeps every old catch.
# Offline: temp runs dir (KAH_RUNS_DIR), switches KAH_GUARD_TEST_STATE5090 / STOP_AFTER_GAME / NO_WAKER. No real lane, game or server is touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\waker-persist-hook-selftest.ps1 [-Guard <hook file>] [-Legacy]
#   default Guard = hooks\kenshi-waker-guard.ps1.candidate if it exists, else hooks\kenshi-waker-guard.ps1.
#   -Legacy = expect the OLD hook: the persistent waker is NOT accepted (case b blocks), everything else identical (proves the test tells the two apart).
param([string]$Guard = '', [switch]$Legacy)
$ErrorActionPreference = 'Stop'
$auto = $PSScriptRoot
if (-not $Guard) { $Guard = Join-Path $auto 'hooks\kenshi-waker-guard.ps1.candidate'; if (-not (Test-Path -LiteralPath $Guard)) { $Guard = Join-Path $auto 'hooks\kenshi-waker-guard.ps1' } }
# -File needs a .ps1 name and the hook dot-sources ..lert-lib.ps1 etc. via $PSScriptRoot: run a temp copy next to the original (removed in finally)
$tmpGuard = $null
if ($Guard -notmatch '\.ps1$') { $tmpGuard = Join-Path (Split-Path $Guard -Parent) ('kenshi-waker-guard.selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1'); Copy-Item -LiteralPath $Guard -Destination $tmpGuard -Force }
$GuardRun = if ($tmpGuard) { $tmpGuard } else { $Guard }
$d = Join-Path ([IO.Path]::GetTempPath()) ("wakerpersist-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'agents'), (Join-Path $d 'inflight'), (Join-Path $d 'waker') | Out-Null
$keys = 'KAH_RUNS_DIR', 'KAH_AGENT_NAME', 'KAH_GUARD_TEST_STATE5090', 'KAH_GUARD_TEST_STOP_AFTER_GAME', 'KAH_GUARD_TEST_NO_WAKER', 'KAH_GUARD_TEST_NO_PROCWAKER', 'KAH_WAKER_ME'
$old = @{}; foreach ($k in $keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:KAH_RUNS_DIR = $d
foreach ($k in 'KAH_AGENT_NAME', 'KAH_GUARD_TEST_NO_WAKER', 'KAH_WAKER_ME') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$n) { if ($ok) { $script:pass++; "SELFTEST PASS $n" } else { $script:fail++; "SELFTEST FAIL $n" } }
function Run-Hook([string]$mode, [string]$json) {
    $in = Join-Path $d 'hook.in'; $o = Join-Path $d 'hook.out'; $e = Join-Path $d 'hook.err'
    [IO.File]::WriteAllText($in, $json)
    $p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $GuardRun, $mode -RedirectStandardInput $in -RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru -WindowStyle Hidden
    [pscustomobject]@{ Code = $p.ExitCode; Out = ((Get-Content -Raw -LiteralPath $o -ErrorAction SilentlyContinue) -as [string]); Err = ((Get-Content -Raw -LiteralPath $e -ErrorAction SilentlyContinue) -as [string]) }
}
function Pre([string]$cmd) { Run-Hook 'pre' (@{ cwd = 'C:\KenshiModding'; hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = @{ command = $cmd } } | ConvertTo-Json -Compress) }
function Stop-Hook { Run-Hook 'stop' '{"cwd":"C:\\KenshiModding","hook_event_name":"Stop"}' }
function Set-Hb([int]$ageSec, [string]$name = 'coordinator.hb', [string]$text = '') {
    $f = Join-Path $d "waker\$name"
    if (-not $text) { $text = "pid=4242 epoch=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ageSec) me=coordinator child=4243 started=0" }
    Set-Content -LiteralPath $f -Value $text -Encoding ASCII
}
function Clear-Hb { Get-ChildItem -LiteralPath (Join-Path $d 'waker') -ErrorAction SilentlyContinue | Remove-Item -Force }
$sl = 'sl' + 'eep'      # keep the literal long-sleep commands out of this file's own text
try {
    $env:KAH_GUARD_TEST_STATE5090 = 'BUSY test'; $env:KAH_GUARD_TEST_STOP_AFTER_GAME = '1'; $env:KAH_GUARD_TEST_NO_PROCWAKER = '1'   # a real waker of the session running this test must not satisfy the process check
    Set-Content -LiteralPath (Join-Path $d 'inflight\batch-pi51test') -Value 'x'              # fresh in-flight marker = work in flight
    Set-Content -LiteralPath (Join-Path $d 'rig5090.idle') -Value 'selftest' -Encoding ASCII  # a fresh idle reason, so only the waker check can block
    $waker = 'no waker is running'
    # ---------- Stop hook: old catches kept (new hook only: the legacy hook cannot ignore a real process waker, so its Stop path is not hermetic) ----------
    if (-not $Legacy) {
    Clear-Hb
    $h = Stop-Hook; T ($h.Out -match '"decision":"block"' -and $h.Out -match $waker) 'in flight + no waker + no heartbeat: still blocked'
    Set-Hb 151; $h = Stop-Hook; T ($h.Out -match $waker) 'heartbeat 151 s old (dead daemon): still blocked'
    Set-Hb 400; $h = Stop-Hook; T ($h.Out -match $waker) 'heartbeat 400 s old: still blocked'
    Set-Hb 0 'coordinator.hb' 'garbage'; $h = Stop-Hook; T ($h.Out -match $waker) 'garbage heartbeat file: still blocked'
    Set-Hb 0 'coordinator.hb' 'pid=1 child=0'; $h = Stop-Hook; T ($h.Out -match $waker) 'heartbeat without epoch: still blocked'
    Clear-Hb; Set-Hb 0 'someoneelse.hb'; $h = Stop-Hook; T ($h.Out -match $waker) "another session's heartbeat file (someoneelse.hb) does not count for the coordinator"
    Clear-Hb; Set-Hb 5; $env:KAH_GUARD_TEST_NO_WAKER = '1'; $h = Stop-Hook; Remove-Item Env:KAH_GUARD_TEST_NO_WAKER
    T ($h.Out -match $waker) 'KAH_GUARD_TEST_NO_WAKER still forces the block even with a fresh heartbeat (switch can only make the block fire)'
    # ---------- Stop hook: persistent waker accepted ----------
    Clear-Hb; Set-Hb 5; $h = Stop-Hook
    if ($Legacy) { T ($h.Out -match $waker) 'LEGACY hook: a fresh heartbeat is not known, blocked as before' }
    else {
        T ($h.Out -notmatch $waker -and $h.Out -match 'PASSED-5090-GAME') "fresh heartbeat (5 s): persistent waker accepted, hook proceeds ($($h.Out.Trim()))"
        Set-Hb 135; $h = Stop-Hook; T ($h.Out -notmatch $waker) 'heartbeat 135 s old: still accepted (limit is 150 s)'
        Clear-Hb; $env:KAH_WAKER_ME = 'coordinator2'; Set-Hb 5 'coordinator2.hb'; $h = Stop-Hook; Remove-Item Env:KAH_WAKER_ME
        T ($h.Out -notmatch $waker) 'KAH_WAKER_ME selects the heartbeat file of another waker name'
    }
    # ---------- Stop hook: other catches untouched while a fresh heartbeat exists ----------
    Clear-Hb; Set-Hb 5
    $env:KAH_GUARD_TEST_STATE5090 = 'IDLE-GAME kenshi=no lock=rig5090 no batch running for 19 min ()'
    Set-Content -LiteralPath (Join-Path $d 'game.lock') -Value 'rig5090' -Encoding ASCII
    $h = Stop-Hook; T ($h.Out -match '"decision":"block"' -and $h.Out -match 'game slot is idle') 'fresh heartbeat does NOT hide an idle 5090 game slot (still blocked)'
    Remove-Item (Join-Path $d 'game.lock') -Force; $env:KAH_GUARD_TEST_STATE5090 = 'BUSY test'
    Remove-Item (Join-Path $d 'rig5090.idle') -Force
    if (Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue) { 'SELFTEST SKIP "5090 idle, no reason" case: a real Kenshi is running here' }
    else { $h = Stop-Hook; T ($h.Out -match '"decision":"block"' -and $h.Out -match 'the 5090 is idle') 'fresh heartbeat does NOT hide "5090 idle, no reason recorded" (still blocked)' }
    Set-Content -LiteralPath (Join-Path $d 'rig5090.idle') -Value 'selftest' -Encoding ASCII
    }
    # ---------- PreToolUse: sleeps and wakeups still denied, duplicate waker denied ----------
    foreach ($hbState in 'none', 'fresh') {
        Clear-Hb; if ($hbState -eq 'fresh') { Set-Hb 5 }
        $r = Pre "$sl 300"; T ($r.Code -eq 2 -and $r.Err -match 'longer than 120') "[$hbState heartbeat] long wait of 300 s denied ($($r.Code))"
        $r = Pre "echo a; Start-S$($sl.Substring(1)) -Seconds 600"; T ($r.Code -eq 2) "[$hbState heartbeat] Start-Sleep 600 denied"
        $r = Pre "$sl 100"; T ($r.Code -eq 0) "[$hbState heartbeat] wait of 100 s allowed"
        $r = Run-Hook 'pre' '{"cwd":"C:\\KenshiModding","tool_name":"ScheduleWakeup","tool_input":{"delaySeconds":900}}'; T ($r.Code -eq 2) "[$hbState heartbeat] ScheduleWakeup 900 denied"
    }
    Clear-Hb
    $r = Pre 'bash tools/automation/event-wait.sh --batch /x'; T ($r.Code -eq 0) 'no persistent waker: starting event-wait.sh is allowed (legacy path kept)'
    Set-Hb 5
    $r = Pre 'bash tools/automation/event-wait.sh --batch /x'
    if ($Legacy) { T ($r.Code -eq 0) 'LEGACY hook: duplicate event-wait.sh not denied' }
    else {
        T ($r.Code -eq 2 -and $r.Err -match 'second waker') "persistent waker alive: starting event-wait.sh is DENIED ($($r.Code))"
        $r = Pre 'MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/event-wait.sh --batch /mnt/c/x'; T ($r.Code -eq 2) 'the wsl.exe form is denied too'
        $r = Pre 'KAH_RUNS=/tmp/t bash tools/automation/event-wait.sh --no-health'; T ($r.Code -eq 0) 'a selftest run with KAH_RUNS= is exempt'
        $r = Pre 'grep -n INBOX tools/automation/event-wait.sh'; T ($r.Code -eq 0) 'grep of event-wait.sh is not a waker start'
        $r = Pre 'bash -n tools/automation/event-wait.sh'; T ($r.Code -eq 0) 'bash -n syntax check is not a waker start'
        $r = Pre 'wsl.exe -d DwemerAI4Skyrim3 -- bash /mnt/c/KenshiModding/tools/automation/waker-persist.sh watch'; T ($r.Code -eq 0) 'waker-persist.sh watch itself is allowed (idempotent)'
        Set-Hb 200; $r = Pre 'bash tools/automation/event-wait.sh'; T ($r.Code -eq 0) 'stale heartbeat (dead daemon): event-wait.sh allowed again'
    }
    $src = Get-Content -Raw -LiteralPath $Guard
    T ($src -match 'no waker is running' -and $src -match 'game slot is idle' -and $src -match 'the 5090 is idle' -and $src -match 'the 4080 is idle' -and $src -match 'waits longer than') 'all original catch texts still present in the hook'
} finally {
    if ($tmpGuard) { Remove-Item -LiteralPath $tmpGuard -Force -ErrorAction SilentlyContinue }
    foreach ($k in $keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item "Env:$k" $old[$k] } }
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST waker-persist-hook $script:pass pass / $script:fail fail ($(Split-Path $Guard -Leaf)$(if ($Legacy) { ', legacy expectations' }))"
if ($script:fail) { exit 1 }
exit 0
