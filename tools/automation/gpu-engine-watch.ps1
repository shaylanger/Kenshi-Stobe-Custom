# gpu-engine-watch.ps1 [-Out <dir>] [-Interval 1] [-Hours 12]     (tdr-xbow 2026-10-11; either rig, run hidden/detached)
# GPU TDR forensics: which process and which GPU engine was busy when the driver timed out.
# Every -Interval s it samples \GPU Engine(*)\Utilization Percentage and keeps the last 20 samples (process, pid,
# engine type, %; only entries > 1%) in memory. When a new nvlddmkm 153 / Display 4101 event appears (a TDR), it writes
#   <Out>\tdr-<yyyyMMdd-HHmmss>.txt   the TDR event + the last 20 samples (= the ~20 s before the reset)
# and keeps watching. Also writes <Out>\gpu-engine-watch.alive (time + last sample) once a minute.
# Why: 5090 TDR 2026-10-11 07:09:52 (WER LiveKernelEvent 141 = video engine timeout) while KenshiFP still logged frames,
# so the hung engine may not be Kenshi's 3D queue; this names the engine/process at the next TDR.
# Start (5090): Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',
#   'C:\KenshiModding\tools\automation\gpu-engine-watch.ps1'
param([string]$Out = 'C:\KenshiTestRuns\tdr-xbow\engine-watch', [int]$Interval = 1, [double]$Hours = 12)
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force $Out | Out-Null
$ring = New-Object System.Collections.Generic.Queue[string]
$since = Get-Date; $end = $since.AddHours($Hours); $lastAlive = Get-Date '2000-01-01'
$names = @{}
function PName($procId) { if (-not $names.ContainsKey($procId)) { $p = Get-Process -Id $procId -ErrorAction SilentlyContinue; $names[$procId] = if ($p) { $p.ProcessName } else { '?' } }; $names[$procId] }
while ((Get-Date) -lt $end) {
  $t = Get-Date
  $s = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue).CounterSamples | Where-Object { $_.CookedValue -gt 1 }
  $parts = foreach ($x in $s) {
    if ($x.InstanceName -match '^pid_(\d+)_.*_eng_(\d+)_engtype_(.*)$') { '{0}/{1}:{2}#{3}={4:F0}%' -f (PName([int]$Matches[1])), $Matches[1], $Matches[3], $Matches[2], $x.CookedValue }
  }
  $line = '{0} {1}' -f $t.ToString('HH:mm:ss.fff'), ($parts -join ' ')
  $ring.Enqueue($line); while ($ring.Count -gt 20) { [void]$ring.Dequeue() }
  $ev = Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = 153, 4101; StartTime = $since } -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -in 'nvlddmkm', 'Display' }
  if ($ev) {
    $f = Join-Path $Out ('tdr-{0}.txt' -f $t.ToString('yyyyMMdd-HHmmss'))
    $hdr = $ev | ForEach-Object { 'TDR-EVENT {0} {1} {2}' -f $_.TimeCreated.ToString('HH:mm:ss.fff'), $_.Id, $_.ProviderName }
    ($hdr + '--- last samples (process/pid:engine#n=util) ---' + $ring.ToArray()) | Out-File -Encoding utf8 $f
    $since = $t.AddSeconds(1)
  }
  if (($t - $lastAlive).TotalSeconds -ge 60) { $lastAlive = $t; $line | Out-File -Encoding utf8 (Join-Path $Out 'gpu-engine-watch.alive') }
  $names.Clear() | Out-Null
  $sl = $Interval * 1000 - ((Get-Date) - $t).TotalMilliseconds; if ($sl -gt 0) { Start-Sleep -Milliseconds ([int]$sl) }
}
