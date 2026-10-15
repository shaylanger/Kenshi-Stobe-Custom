# agent-host-monitor-selftest.ps1 : sandbox selftest of the agent-host monitor (KAH_RUNS_DIR sandbox, synthetic agents, real sleeper processes). Prints SELFTEST PASS n/n.
$ErrorActionPreference = 'Stop'
$box = Join-Path ([IO.Path]::GetTempPath()) ("hostmon-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ad = Join-Path $box 'agents'; New-Item -ItemType Directory -Force -Path $ad, (Join-Path $ad 'out'), (Join-Path $box 'inbox\coordinator') | Out-Null
$env:KAH_RUNS_DIR = $box
$here = $PSScriptRoot
# tests the staged agent-host.new.ps1 when it exists (swap pending), else the live agent-host.ps1
$hostScript = if (Test-Path (Join-Path $here 'agent-host.new.ps1')) { Join-Path $here 'agent-host.new.ps1' } else { Join-Path $here 'agent-host.ps1' }
$pass = 0; $fail = 0
function Check([string]$what, [bool]$ok) { if ($ok) { $script:pass++; "  ok   $what" } else { $script:fail++; "  FAIL $what" } }
$procs = @()
function New-Agent([string]$name, [double]$statusAgeMin, [double]$logAgeMin, [string]$proc, [double]$startedAgoMin = 1, [string]$outputs = '') {
    $st = Join-Path $ad "$name.status"
    Set-Content $st "$name | RUNNING | 2026-10-15 16:00`ntask: selftest`nlatest: working`noutputs: $outputs" -Encoding utf8
    (Get-Item $st).LastWriteTime = (Get-Date).AddMinutes(-$statusAgeMin)
    if ($logAgeMin -ge 0) { $lg = Join-Path $ad "out\$name.log"; Set-Content $lg 'line' -Encoding ascii; (Get-Item $lg).LastWriteTime = (Get-Date).AddMinutes(-$logAgeMin) }
    $lp = 0
    if ($proc -eq 'live') { $p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 300'; $script:procs += $p; $lp = $p.Id }
    elseif ($proc -eq 'dead') { $lp = 999999 }
    if ($proc -ne 'none') {
        @{ name = $name; launcher_pid = $lp; claude_pid = 0; started = (Get-Date).AddMinutes(-$startedAgoMin).ToString('yyyy-MM-ddTHH:mm:sszzz') } | ConvertTo-Json | Set-Content (Join-Path $ad "$name.session.json") -Encoding utf8
    }
}
function Run-Monitor { & powershell -NoProfile -ExecutionPolicy Bypass -File $hostScript -MonitorOnce | Out-Null }
function State([string]$n) { ((Get-Content (Join-Path $ad "$n.status") -TotalCount 1) -replace '^﻿', '') -split '\s*\|\s*' | Select-Object -Index 1 }
function Wakes { @(Get-ChildItem (Join-Path $box 'inbox\coordinator') -Filter '*.msg' | ForEach-Object { Get-Content $_.FullName -Raw }) }

New-Agent 'healthy' 1 1 'live'
New-Agent 'dead' 1 1 'dead' 5
New-Agent 'stall' 12 12 'live'
New-Agent 'killme' 22 22 'live'
New-Agent 'wall' 1 1 'live' 100
New-Agent 'orphan' 12 -1 'none'
New-Agent 'logfresh' 15 1 'live'   # status silent but log growing -> not a stall
$ev = Join-Path $box 'evidence'; New-Item -ItemType Directory -Force -Path $ev | Out-Null
Set-Content (Join-Path $ev 'result.txt') 'fresh' -Encoding ascii   # evidence just written
New-Agent 'stallev' 15 15 'live' 1 $ev          # status+log silent but evidence dir fresh -> working, no stall wake
New-Agent 'orphanev' 15 -1 'none' 1 $ev         # INPROC, evidence fresh -> no orphan wake
$evOld = Join-Path $box 'evidence-old'; New-Item -ItemType Directory -Force -Path $evOld | Out-Null
Set-Content (Join-Path $evOld 'x.txt') 'old' -Encoding ascii; (Get-Item (Join-Path $evOld 'x.txt')).LastWriteTime = (Get-Date).AddMinutes(-30)
New-Agent 'stalloldev' 15 15 'live' 1 $evOld    # evidence also old -> real stall, wakes
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
Check 'stallev: fresh evidence dir => no stall wake' (-not ($w -match 'stallev'))
Check 'orphanev: fresh evidence dir => no orphan wake' (-not ($w -match 'orphanev'))
Check 'stalloldev: old evidence => stall wake still sent' ([bool]($w -match 'AGENT STALL stalloldev'))
Check 'FAILED agents get a respawn todo' (Test-Path (Join-Path $box 'respawn\killme.todo'))
$n1 = $w.Count
Run-Monitor
Check 'second run: no duplicate wakes' ((Wakes).Count -eq $n1)
Get-ChildItem (Join-Path $box 'inbox\coordinator') | Remove-Item
$rc = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-rollcall.ps1')
Check 'rollcall prints one line per RUNNING agent' (@($rc | Where-Object { $_ -match '^ROLLCALL ' }).Count -ge 4)
# --- live reload of agent-rollcall.ps1 + agent-host-reload.ps1 (sandbox daemon; statuses cleared so the daemon has nothing to act on)
Get-ChildItem $ad -File | Where-Object { $_.Name -match '\.(status|session\.json)$' } | Remove-Item -Force
foreach ($p in $procs) { try { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null } catch { } }
$q = Join-Path $box 'agent-queue'; New-Item -ItemType Directory -Force -Path $q | Out-Null
$hs = Join-Path $box 'hs'; New-Item -ItemType Directory -Force -Path $hs | Out-Null
Copy-Item $hostScript (Join-Path $hs 'agent-host.ps1'); Copy-Item (Join-Path $here 'agent-rollcall.ps1') (Join-Path $hs 'agent-rollcall.ps1')
Copy-Item (Join-Path $here 'agent-status.ps1') (Join-Path $hs 'agent-status.ps1')
$d1 = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $hs 'agent-host.ps1')`"", '-MonitorSec', '2'
Start-Sleep -Seconds 4
$flag = Join-Path $box 'reloaded.flag'
Check 'live reload: daemon started, flag absent before edit' ((-not $d1.HasExited) -and -not (Test-Path $flag))
Add-Content (Join-Path $hs 'agent-rollcall.ps1') "`nSet-Content (Join-Path `$env:KAH_RUNS_DIR 'reloaded.flag') 'x'"
for ($i = 0; $i -lt 16 -and -not (Test-Path $flag); $i++) { Start-Sleep -Milliseconds 500 }
Check 'live reload: edited agent-rollcall.ps1 re-sourced without restart' (Test-Path $flag)
Add-Content (Join-Path $hs 'agent-rollcall.ps1') "`n{{{ broken ("
Start-Sleep -Seconds 5
Check 'live reload: a broken edit does not kill the daemon' (-not $d1.HasExited)
try { Stop-Process -Id $d1.Id -Force } catch { }
Remove-Item (Join-Path $q 'agent-host.pid') -Force -ErrorAction SilentlyContinue

# reload script: fake daemon (pid file) with a launcher-like child; the reload must stop only the daemon and keep the child
$launch = Join-Path $box 'sbx.launch.ps1'; Set-Content $launch 'Start-Sleep 300' -Encoding ascii
$fakeCmd = "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$launch'; Start-Sleep 300"
$fake = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', $fakeCmd
Set-Content (Join-Path $q 'agent-host.pid') "$($fake.Id)" -Encoding ascii
Start-Sleep -Seconds 3
$kid = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($fake.Id)" | Where-Object { $_.CommandLine -match 'sbx\.launch\.ps1' })
Check 'reload fixture: launcher child of the fake daemon' ($kid.Count -eq 1)
$reload = Join-Path $here 'agent-host-reload.ps1'
$dr = (& powershell -NoProfile -ExecutionPolicy Bypass -File $reload -DryRun) -join ' '
Check 'reload -DryRun: lists the launcher child, stops nothing' (($dr -match 'RELOAD dry-run') -and ($dr -match 'launcher_children=1') -and [bool](Get-Process -Id $fake.Id -ErrorAction SilentlyContinue))
Set-Content (Join-Path $q 'pending.job') '{}' -Encoding ascii
$rf = (& powershell -NoProfile -ExecutionPolicy Bypass -File $reload) -join ' '
Check 'reload refuses while a job is queued (mid-launch guard), exit 2' (($rf -match 'RELOAD refused') -and $LASTEXITCODE -eq 2 -and [bool](Get-Process -Id $fake.Id -ErrorAction SilentlyContinue))
Remove-Item (Join-Path $q 'pending.job') -Force
$ro = (& powershell -NoProfile -ExecutionPolicy Bypass -File $reload -HostScript (Join-Path $hs 'agent-host.ps1')) -join ' '
Check 'reload ok: output RELOAD ok, launchers kept 1/1' (($ro -match '^RELOAD ok') -and ($ro -match 'kept 1/1'))
Check 'reload: old daemon gone, launcher child still alive' ((-not (Get-Process -Id $fake.Id -ErrorAction SilentlyContinue)) -and [bool](Get-Process -Id $kid[0].ProcessId -ErrorAction SilentlyContinue))
$np = 0; [int]::TryParse((Get-Content (Join-Path $q 'agent-host.pid') -Raw).Trim(), [ref]$np) | Out-Null
Check 'reload: new daemon alive with a different pid' ($np -gt 0 -and $np -ne $fake.Id -and [bool](Get-Process -Id $np -ErrorAction SilentlyContinue))
if ($np -gt 0) { try { Stop-Process -Id $np -Force } catch { } }
try { Stop-Process -Id $kid[0].ProcessId -Force } catch { }

foreach ($p in $procs) { try { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null } catch { } }
Remove-Item -Recurse -Force $box -ErrorAction SilentlyContinue
if ($fail) { "SELFTEST FAIL $fail (pass $pass)"; exit 1 }
"SELFTEST PASS $pass/$pass"
