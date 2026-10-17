# worklock-selftest.ps1 (Shay 2026-10-17): the Stop hook blocks while open work remains and nothing is running on it; idle reasons do not count;
# only a self-wake, running work or a transcript-verified Shay stop order lets the turn end; the 4th consecutive block is let through and logged.
# Offline: temp runs dir (KAH_RUNS_DIR), test seams KAH_GUARD_TEST_WORKLEFT_TICKETS / _ROWS. No real lane, game, server or ticket is touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\worklock-selftest.ps1 [-Guard <hook file>]
param([string]$Guard = '')
$ErrorActionPreference = 'Stop'
if (-not $Guard) { $Guard = Join-Path $PSScriptRoot 'hooks\kenshi-waker-guard.ps1' }
$d = Join-Path ([IO.Path]::GetTempPath()) ('worklock-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'agents'), (Join-Path $d 'inflight'), (Join-Path $d 'waker'), (Join-Path $d 'alerts') | Out-Null
$keys = 'KAH_RUNS_DIR', 'KAH_AGENT_NAME', 'KAH_GUARD_TEST_WORKLEFT_TICKETS', 'KAH_GUARD_TEST_WORKLEFT_ROWS', 'KAH_GUARD_NO_WORKLEFT', 'KAH_GUARD_TEST_STATE5090'
$old = @{}; foreach ($k in $keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:KAH_RUNS_DIR = $d
foreach ($k in 'KAH_AGENT_NAME', 'KAH_GUARD_NO_WORKLEFT') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
$tk = Join-Path $d 'tickets.txt'; $rw = Join-Path $d 'rows.md'; $tr = Join-Path $d 'transcript.jsonl'
$env:KAH_GUARD_TEST_WORKLEFT_TICKETS = $tk; $env:KAH_GUARD_TEST_WORKLEFT_ROWS = $rw
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$n) { if ($ok) { $script:pass++; "SELFTEST PASS $n" } else { $script:fail++; "SELFTEST FAIL $n" } }
function Run-Hook([string]$mode, [hashtable]$h) {
    $in = Join-Path $d 'hook.in'; $o = Join-Path $d 'hook.out'; $e = Join-Path $d 'hook.err'
    [IO.File]::WriteAllText($in, ($h | ConvertTo-Json -Compress))
    $p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Guard, $mode -RedirectStandardInput $in -RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru -WindowStyle Hidden
    [pscustomobject]@{ Code = $p.ExitCode; Out = ((Get-Content -Raw -LiteralPath $o -ErrorAction SilentlyContinue) -as [string]); Err = ((Get-Content -Raw -LiteralPath $e -ErrorAction SilentlyContinue) -as [string]) }
}
function Stop-Hook([bool]$active = $false) { Run-Hook 'stop' @{ cwd = 'C:\KenshiModding'; hook_event_name = 'Stop'; session_id = 'sess-A'; transcript_path = $tr; stop_hook_active = $active } }
function Blocked($r) { $r.Out -match 'item\(s\) of work remain' }
function Reset-State { Get-ChildItem -LiteralPath $d -File | Where-Object { $_.Name -in 'worklock.count', 'shay-stop-order.json', 'selfwake.json', 'rig5090.idle' } | Remove-Item -Force; Get-ChildItem -LiteralPath (Join-Path $d 'agents'), (Join-Path $d 'inflight') -File | Remove-Item -Force }
try {
    Set-Content -LiteralPath $tk -Value @('01-cx age=12h40m needs=recipe owner=- state=open - unowned', '23-a age=1h needs=recipe owner=x state=closed') -Encoding ASCII
    Set-Content -LiteralPath $rw -Value @('| IMM-01-cx | setup (|aff before| <= 10) | say | exp | neg | NC28 | SETUP-FAIL | ev | 2026-10-16 |', '| IMM-26-f | s | u | e | n | NC28 | PASS | ev | d |') -Encoding ASCII
    Set-Content -LiteralPath $tr -Value '{"type":"user","message":{"role":"user","content":"hello"}}' -Encoding ASCII

    Reset-State
    $r = Stop-Hook; T (Blocked $r) 'a open ticket + FAIL row, nothing running -> Stop blocked'
    T ($r.Out -match 'Block 1 of 3') 'a2 block counter starts at 1'

    Reset-State; Set-Content -LiteralPath (Join-Path $d 'rig5090.idle') -Value 'waiting for Shay' -Encoding ASCII
    $r = Stop-Hook; T (Blocked $r) 'b a recorded idle reason does NOT lift the block'

    Reset-State
    $r = Stop-Hook $true; T (Blocked $r) 'c stop_hook_active does not skip the open-work block'

    Reset-State
    $null = Stop-Hook; $null = Stop-Hook; $r3 = Stop-Hook; $r4 = Stop-Hook
    T ((Blocked $r3) -and -not (Blocked $r4)) 'd blocks 1-3, the 4th stop is let through'
    T ((Get-Content -Raw -LiteralPath (Join-Path $d 'alerts\cap-ends.log') -ErrorAction SilentlyContinue) -match 'worklock') 'd2 the let-through is logged in alerts\cap-ends.log'

    Reset-State
    @{ session = 'sess-A'; until = (Get-Date).AddMinutes(25).ToString('o') } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $d 'selfwake.json') -Encoding ASCII
    T (-not (Blocked (Stop-Hook))) 'e a live self-wake of this session lets the turn end'
    Reset-State
    @{ session = 'sess-B'; until = (Get-Date).AddMinutes(25).ToString('o') } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $d 'selfwake.json') -Encoding ASCII
    T (Blocked (Stop-Hook)) 'e2 another session''s self-wake does not count'
    Reset-State
    @{ session = 'sess-A'; until = (Get-Date).AddMinutes(-5).ToString('o') } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $d 'selfwake.json') -Encoding ASCII
    T (Blocked (Stop-Hook)) 'e3 an expired self-wake does not count'

    Reset-State
    Set-Content -LiteralPath (Join-Path $d 'agents\wp1.status') -Value ('wp1 | RUNNING | task | step | out | next | ' + (Get-Date -Format s)) -Encoding ASCII
    T (-not (Blocked (Stop-Hook))) 'f a fresh RUNNING agent counts as work in progress'
    Reset-State
    Set-Content -LiteralPath (Join-Path $d 'inflight\batch-x') -Value 'x' -Encoding ASCII
    T (-not (Blocked (Stop-Hook))) 'f2 a fresh inflight marker counts as work in progress'

    Reset-State
    @{ quote = 'stop everything now'; at = '09:40' } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $d 'shay-stop-order.json') -Encoding ASCII
    Set-Content -LiteralPath $tr -Value '{"type":"assistant","message":{"role":"assistant","content":"stop everything now"}}' -Encoding ASCII
    T (Blocked (Stop-Hook)) 'g a stop-order quote that only appears in assistant text is rejected'
    Set-Content -LiteralPath $tr -Value '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"stop everything now"}]}}' -Encoding ASCII
    T (Blocked (Stop-Hook)) 'g2 a quote inside a tool result is rejected'
    Set-Content -LiteralPath $tr -Value '{"type":"user","message":{"role":"user","content":"Shay: stop everything now please"}}' -Encoding ASCII
    T (-not (Blocked (Stop-Hook))) 'g3 a quote found in a real user message lets the turn end'

    Reset-State
    Set-Content -LiteralPath $tk -Value @('23-a age=1h needs=recipe owner=x state=closed') -Encoding ASCII
    Set-Content -LiteralPath $rw -Value @('| IMM-26-f | s | u | e | n | NC28 | PASS | ev | d |') -Encoding ASCII
    T (-not (Blocked (Stop-Hook))) 'h no open work -> the open-work block stays quiet'

    Set-Content -LiteralPath $rw -Value @('| IMM-01-cx | s | u | e | n | NC28 | FAIL | ev | d |') -Encoding ASCII
    Reset-State
    T (Blocked (Stop-Hook)) 'i a FAIL row alone is open work'
    $env:KAH_GUARD_NO_WORKLEFT = '1'
    Reset-State
    T (-not (Blocked (Stop-Hook))) 'j KAH_GUARD_NO_WORKLEFT=1 switches the block off'
    Remove-Item Env:KAH_GUARD_NO_WORKLEFT
    $env:KAH_AGENT_NAME = 'someagent'
    Reset-State
    T (-not (Blocked (Stop-Hook))) 'k agent sessions are not held to the coordinator open-work rule'
    Remove-Item Env:KAH_AGENT_NAME

    # PreToolUse: self-wake
    Reset-State
    $r = Run-Hook 'pre' @{ cwd = 'C:\KenshiModding'; session_id = 'sess-A'; hook_event_name = 'PreToolUse'; tool_name = 'ScheduleWakeup'; tool_input = @{ delaySeconds = 1500; reason = 'self-wake: work left'; prompt = 'x' } }
    T ($r.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $d 'selfwake.json'))) 'l a labelled 1500 s self-wake is allowed and recorded'
    Reset-State
    $r = Run-Hook 'pre' @{ cwd = 'C:\KenshiModding'; session_id = 'sess-A'; hook_event_name = 'PreToolUse'; tool_name = 'ScheduleWakeup'; tool_input = @{ delaySeconds = 1500; reason = 'polling the batch'; prompt = 'x' } }
    T ($r.Code -eq 2) 'm an unlabelled 1500 s ScheduleWakeup is still denied'
    $r = Run-Hook 'pre' @{ cwd = 'C:\KenshiModding'; session_id = 'sess-A'; hook_event_name = 'PreToolUse'; tool_name = 'ScheduleWakeup'; tool_input = @{ delaySeconds = 3000; reason = 'self-wake: far'; prompt = 'x' } }
    T ($r.Code -eq 2) 'n a labelled self-wake over 30 min is denied'
    $r = Run-Hook 'pre' @{ cwd = 'C:\KenshiModding'; session_id = 'sess-A'; hook_event_name = 'PreToolUse'; tool_name = 'ScheduleWakeup'; tool_input = @{ delaySeconds = 90; reason = 'x'; prompt = 'x' } }
    T ($r.Code -eq 0) 'o a <= 120 s ScheduleWakeup is still allowed'
} finally {
    foreach ($k in $keys) { [Environment]::SetEnvironmentVariable($k, $old[$k]) }
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST SUMMARY pass=$($script:pass) fail=$($script:fail)"
if ($script:fail -gt 0) { exit 1 }
