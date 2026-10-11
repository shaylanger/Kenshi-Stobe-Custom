# gpulog.ps1 [-Rig 5090|4080] [-Every 2]: GPU telemetry every <Every> s to C:\KenshiTestRuns\gpulog\<rig>-<MMdd-HHmm>.csv
# (temp, power, clocks, VRAM, util, pstate, throttle reasons) so a TDR/BSOD can be matched to the GPU state right before it.
# Why (m103 2026-10-11): a TDR hit the 5090 at 16:35 with 2 games + WGC capture + lab analysis running and nothing recorded
# the GPU state; `nvidia-smi -l -f` exits when started hidden, so this loop calls nvidia-smi once per sample and appends.
# One instance per rig (a lock file with the PID); files older than 3 days are deleted at start.
# Timeline (speed-scout 2026-10-11): each sample also diffs the set of GPU-using processes (kenshi_x64 per lane from its
# install path: D:\KenshiInst\<n> = i<n>, else i1; ffmpeg; wgccap) and appends start/exit lines to gpulog\timeline.tsv
# ("time<TAB>rig<TAB>lane<TAB>proc-start|proc-exit<TAB>name pid=<n>"), next to run-batch launch/row/stop and tdr-watch lines.
# -SelfTest checks the diff (no files).
param([string]$Rig = '5090', [int]$Every = 2, [switch]$SelfTest)
$watch = 'kenshi_x64', 'ffmpeg', 'wgccap'
function ProcSet { $h = @{}; foreach ($p in @(Get-Process -Name $watch -ErrorAction SilentlyContinue)) { $ln = if ("$($p.Path)" -match '\\KenshiInst\\(\d+)\\') { "i$($Matches[1])" } elseif ($p.ProcessName -eq 'kenshi_x64') { 'i1' } else { '-' }; $h["$($p.ProcessName) pid=$($p.Id)"] = $ln }; $h }
function ProcDiff([hashtable]$old, [hashtable]$new, [string]$ts, [string]$rig) {   # pure: timeline lines for started/ended processes
    foreach ($k in @($new.Keys | Sort-Object)) { if (-not $old.ContainsKey($k)) { "$ts`t$rig`t$($new[$k])`tproc-start`t$k" } }
    foreach ($k in @($old.Keys | Sort-Object)) { if (-not $new.ContainsKey($k)) { "$ts`t$rig`t$($old[$k])`tproc-exit`t$k" } }
}
if ($SelfTest) {
    $a = @{ 'kenshi_x64 pid=1' = 'i1'; 'ffmpeg pid=2' = '-' }; $b = @{ 'kenshi_x64 pid=1' = 'i1'; 'kenshi_x64 pid=3' = 'i2' }
    $got = (@(ProcDiff $a $b 'T' '5090') -join '|'); $want = "T`t5090`ti2`tproc-start`tkenshi_x64 pid=3|T`t5090`t-`tproc-exit`tffmpeg pid=2"
    $n0 = @(ProcDiff $b $b 'T' '5090').Count
    if ($got -eq $want -and $n0 -eq 0) { 'GPULOG-SELFTEST PASS 2 cases' } else { "GPULOG-SELFTEST FAIL got '$got' same-set=$n0"; exit 1 }
    exit 0
}
$d = 'C:\KenshiTestRuns\gpulog'; New-Item -ItemType Directory -Force $d | Out-Null
$lock = Join-Path $d "$Rig.pid"
if (Test-Path $lock) { $old = Get-Content $lock -ErrorAction SilentlyContinue; if ($old -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) { Write-Output "gpulog already running pid $old"; exit 0 } }
Set-Content $lock $PID
Get-ChildItem $d -Filter "$Rig-*.csv" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } | Remove-Item -ErrorAction SilentlyContinue
$f = Join-Path $d ("$Rig-" + (Get-Date -Format 'MMdd-HHmm') + '.csv')
$q = 'timestamp,temperature.gpu,power.draw,clocks.gr,clocks.mem,memory.used,utilization.gpu,pstate,clocks_event_reasons.active'
$hdr = & nvidia-smi.exe "--query-gpu=$q" --format=csv 2>&1 | Select-Object -First 1
if ("$hdr" -match 'not a valid field|Invalid') { $q = $q -replace ',clocks_event_reasons.active', '' }
& nvidia-smi.exe "--query-gpu=$q" --format=csv 2>&1 | Select-Object -First 1 | Add-Content $f
function Tls { [DateTime]::UtcNow.AddHours(-6).ToString('yyyy-MM-dd HH:mm:ss') }   # timeline time = the 5090 clock on every rig (Central, DST off = UTC-6; the 4080 runs Pacific)
$tlf = Join-Path $d 'timeline.tsv'; $ps = ProcSet
foreach ($k in @($ps.Keys | Sort-Object)) { try { Add-Content $tlf "$(Tls)`t$Rig`t$($ps[$k])`tproc-running`t$k (gpulog start)" } catch {} }
while ($true) {
    & nvidia-smi.exe "--query-gpu=$q" --format=csv,noheader 2>&1 | Add-Content $f
    try { $np = ProcSet; $tl = @(ProcDiff $ps $np (Tls) $Rig); if ($tl.Count) { Add-Content $tlf $tl }; $ps = $np } catch {}
    Start-Sleep -Seconds $Every
}
