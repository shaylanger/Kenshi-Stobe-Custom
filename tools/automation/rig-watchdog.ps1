# rig-watchdog.ps1: session-independent fallback that keeps BOTH rigs working (Shay 2026-10-10: "having either the 5090
# or 4080 paused or idle for more than 2 min is not acceptable"). Runs as one hidden background loop (60 s tick):
#   1. state per rig: 5090 = rig5090-state.ps1 (IDLE-GAME: Kenshi open/paused, no batch; IDLE: closed), 4080 =
#      rig4080-state.ps1 -Fresh (IDLE-GAME: Kenshi open but every 4080-* marker job has its DONE file; IDLE: closed).
#      A fresh idle reason (kenshi-ctl.ps1 idle / idle4080) = not idle.
#   2. idle for >= 2 min: run the rig's queue line  run: <out> | <command>  from C:\KenshiTestRuns\queue\<rig>.next
#      (each distinct line once; logged in queue\<rig>.ran), detached, output in C:\KenshiTestRuns\watchdog\, marker
#      inflight\auto-5090 = <out> (a run-batch out dir) or inflight\4080-auto = 4080:<out>.
#   3. no usable run line: C:\KenshiTestRuns\ALERT-<rig>.txt + a note to the queue owner; rig-health.sh and the Stop hook
#      show/block on every ALERT file, so the coordinator must start work. The ALERT clears itself once the rig is busy.
# Start/ensure: powershell -NoProfile -ExecutionPolicy Bypass -File rig-watchdog.ps1 -Ensure  (session-start does this)
# Status: Get-Content C:\KenshiTestRuns\watchdog\watchdog.log -Tail 20 ; stop: -Stop
param([switch]$Ensure, [switch]$Stop, [int]$IdleMin = 2, [int]$TickSec = 60)
$runs = 'C:\KenshiTestRuns'; $auto = 'C:\KenshiModding\tools\automation'
$wd = Join-Path $runs 'watchdog'; New-Item -ItemType Directory -Force $wd | Out-Null
$pidFile = Join-Path $wd 'watchdog.pid'; $log = Join-Path $wd 'watchdog.log'
function Alive { if (Test-Path $pidFile) { $p = [int](Get-Content $pidFile -Raw); return [bool](Get-Process -Id $p -ErrorAction SilentlyContinue) } $false }
if ($Stop) { if (Alive) { Stop-Process -Id ([int](Get-Content $pidFile -Raw)) -Force }; Remove-Item $pidFile -ErrorAction SilentlyContinue; 'stopped'; exit 0 }
if ($Ensure) {
    if (Alive) { "watchdog running pid=$(Get-Content $pidFile -Raw)"; exit 0 }
    $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
    "watchdog started pid=$($p.Id)"; exit 0
}
if (Alive) { exit 0 }
Set-Content $pidFile $PID
function Log([string]$m) { Add-Content $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m" }
Log "start pid=$PID idle>=${IdleMin}m tick=${TickSec}s"
$since = @{}
while ($true) {
    foreach ($rig in '5090', '4080') {
        try {
            $s = if ($rig -eq '5090') { & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig5090-state.ps1" | Select-Object -First 1 }
                 else { & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig4080-state.ps1" -Fresh | Select-Object -First 1 }
            $s = [string]$s
            $idle = ($s -like 'IDLE-GAME*') -or ($s -eq 'IDLE') -or ($s -like 'IDLE kenshi=no*')
            $alert = Join-Path $runs "ALERT-$rig.txt"
            if (-not $idle) { $since.Remove($rig); if (Test-Path $alert) { Remove-Item $alert; Log "$rig busy again ($s): alert cleared" }; continue }
            if (-not $since.ContainsKey($rig)) { $since[$rig] = Get-Date; Log "$rig idle: $s"; continue }
            $mins = ((Get-Date) - $since[$rig]).TotalMinutes
            if ($mins -lt $IdleMin) { continue }
            $q = Join-Path $runs "queue\$rig.next"; $ranF = Join-Path $runs "queue\$rig.ran"
            $owner = if (Test-Path $q) { ((Get-Content $q -TotalCount 1) -replace '^owner:\s*', '' -split '\s')[0] } else { 'coordinator' }
            $line = if (Test-Path $q) { Get-Content $q | Where-Object { $_ -match '^run:\s*(.+?)\s*\|\s*(.+)$' } | Select-Object -First 1 } else { $null }
            $ran = if (Test-Path $ranF) { Get-Content $ranF } else { @() }
            if ($line -and ($ran -notcontains $line)) {
                $null = $line -match '^run:\s*(.+?)\s*\|\s*(.+)$'; $out = $Matches[1]; $cmd = $Matches[2]
                $tag = "$rig-$((Get-Date).ToString('HHmmss'))"; $o = Join-Path $wd "$tag.out"
                Add-Content $ranF $line
                if ($rig -eq '5090') { Set-Content (Join-Path $runs 'inflight\auto-5090') $out } else { Set-Content (Join-Path $runs 'inflight\4080-auto') "4080:$out" }
                Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',"& { $cmd } *> '$o'" | Out-Null
                Log "$rig idle $([int]$mins)m ($s): AUTO-START queue line: $line  (output $o)"
                Add-Content (Join-Path $runs "agents\$owner.note-from-watchdog") "$((Get-Date).ToString('HH:mm')) watchdog: $rig was idle $([int]$mins) min; started your queue run line: $line. Judge it when its out dir has DONE, then write the next run: line."
                $since.Remove($rig); if (Test-Path $alert) { Remove-Item $alert }
            } elseif (-not (Test-Path $alert)) {
                $why = if ($line) { 'its run: line already ran' } else { 'no run: line in the queue' }
                Set-Content $alert "ALERT $rig idle $([int]$mins) min since $($since[$rig].ToString('HH:mm')) ($s); $why. Owner ${owner}: start the next batch now and put a 'run: <out> | <command>' line in queue\$rig.next."
                Add-Content (Join-Path $runs "agents\$owner.note-from-watchdog") "$((Get-Date).ToString('HH:mm')) watchdog ALERT: $rig idle $([int]$mins) min and $why. Start the next batch NOW; keep a 'run: <out> | <command>' line in queue\$rig.next so the watchdog can restart the rig itself."
                Log "$rig ALERT: idle $([int]$mins)m, $why"
            }
        } catch { Log "$rig error: $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds $TickSec
}
