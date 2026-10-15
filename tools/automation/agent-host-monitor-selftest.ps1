# agent-host-monitor-selftest.ps1 : sandbox selftest of the agent-host monitor (KAH_RUNS_DIR sandbox, synthetic agents, real sleeper processes). Prints SELFTEST PASS n/n.
$ErrorActionPreference = 'Stop'
$box = Join-Path ([IO.Path]::GetTempPath()) ("hostmon-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ad = Join-Path $box 'agents'; New-Item -ItemType Directory -Force -Path $ad, (Join-Path $ad 'out'), (Join-Path $box 'inbox\coordinator') | Out-Null
$env:KAH_RUNS_DIR = $box
$here = $PSScriptRoot
$pass = 0; $fail = 0
function Check([string]$what, [bool]$ok) { if ($ok) { $script:pass++; "  ok   $what" } else { $script:fail++; "  FAIL $what" } }
$procs = @()
function New-Agent([string]$name, [double]$statusAgeMin, [double]$logAgeMin, [string]$proc, [double]$startedAgoMin = 1) {
    $st = Join-Path $ad "$name.status"
    Set-Content $st "$name | RUNNING | 2026-10-15 16:00`ntask: selftest`nlatest: working" -Encoding utf8
    (Get-Item $st).LastWriteTime = (Get-Date).AddMinutes(-$statusAgeMin)
    if ($logAgeMin -ge 0) { $lg = Join-Path $ad "out\$name.log"; Set-Content $lg 'line' -Encoding ascii; (Get-Item $lg).LastWriteTime = (Get-Date).AddMinutes(-$logAgeMin) }
    $lp = 0
    if ($proc -eq 'live') { $p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 300'; $script:procs += $p; $lp = $p.Id }
    elseif ($proc -eq 'dead') { $lp = 999999 }
    if ($proc -ne 'none') {
        @{ name = $name; launcher_pid = $lp; claude_pid = 0; started = (Get-Date).AddMinutes(-$startedAgoMin).ToString('yyyy-MM-ddTHH:mm:sszzz') } | ConvertTo-Json | Set-Content (Join-Path $ad "$name.session.json") -Encoding utf8
    }
}
function Run-Monitor { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-host.ps1') -MonitorOnce | Out-Null }
function State([string]$n) { ((Get-Content (Join-Path $ad "$n.status") -TotalCount 1) -replace '^﻿', '') -split '\s*\|\s*' | Select-Object -Index 1 }
function Wakes { @(Get-ChildItem (Join-Path $box 'inbox\coordinator') -Filter '*.msg' | ForEach-Object { Get-Content $_.FullName -Raw }) }

New-Agent 'healthy' 1 1 'live'
New-Agent 'dead' 1 1 'dead' 5
New-Agent 'stall' 12 12 'live'
New-Agent 'killme' 22 22 'live'
New-Agent 'wall' 1 1 'live' 100
New-Agent 'orphan' 12 -1 'none'
New-Agent 'logfresh' 15 1 'live'   # status silent but log growing -> not a stall
Run-Monitor
$w = Wakes
Check 'healthy: no wake, still RUNNING' ((State 'healthy') -eq 'RUNNING' -and -not ($w -match 'healthy'))
Check 'dead: FAILED + AGENT DEAD wake' ((State 'dead') -eq 'FAILED' -and [bool]($w -match 'AGENT DEAD dead'))
Check 'stall: AGENT STALL wake, still RUNNING' ((State 'stall') -eq 'RUNNING' -and [bool]($w -match 'AGENT STALL stall'))
Check 'killme: killed, FAILED, AGENT KILLED wake' ((State 'killme') -eq 'FAILED' -and [bool]($w -match 'AGENT KILLED killme'))
Check 'killme: process tree gone' (-not (Get-Process -Id ((Get-Content (Join-Path $ad 'killme.session.json') -Raw | ConvertFrom-Json).launcher_pid) -ErrorAction SilentlyContinue))
Check 'wall: STOPPED-CONTEXT + AGENT WALL-CLOCK wake' ((State 'wall') -eq 'STOPPED-CONTEXT' -and [bool]($w -match 'AGENT WALL-CLOCK wall'))
Check 'orphan: AGENT ORPHANED wake, status untouched' ((State 'orphan') -eq 'RUNNING' -and [bool]($w -match 'AGENT ORPHANED orphan'))
Check 'logfresh: log growing => no stall wake' (-not ($w -match 'logfresh'))
Check 'FAILED agents get a respawn todo' (Test-Path (Join-Path $box 'respawn\killme.todo'))
$n1 = $w.Count
Run-Monitor
Check 'second run: no duplicate wakes' ((Wakes).Count -eq $n1)
Get-ChildItem (Join-Path $box 'inbox\coordinator') | Remove-Item
$rc = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-rollcall.ps1')
Check 'rollcall prints one line per RUNNING agent' (@($rc | Where-Object { $_ -match '^ROLLCALL ' }).Count -ge 4)
foreach ($p in $procs) { try { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null } catch { } }
Remove-Item -Recurse -Force $box -ErrorAction SilentlyContinue
if ($fail) { "SELFTEST FAIL $fail (pass $pass)"; exit 1 }
"SELFTEST PASS $pass/$pass"
