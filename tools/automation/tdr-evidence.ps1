# tdr-evidence.ps1 -Out <dir> [-Rig 5090|4080] [-Since <unix epoch>] [-BatchLog <file>] [-Minutes 5]
# Collects what was going on when a GPU driver reset (TDR) hit, into <dir> (run-batch.sh tdr_guard: <out>\TDR-evidence\),
# BEFORE the game is stopped (m103 2026-10-11: Shay wants every crash diagnosable; the 16:35 5090 TDR left no GPU record):
#   gpulog.csv      the last <Minutes> min of C:\KenshiTestRuns\gpulog\<rig>-*.csv (gpulog.ps1, 2 s samples) + its header
#   events.txt      System log events of the last 30 min from nvlddmkm / Display / LiveKernelEvent / WHEA / Kernel-Power
#   batch-tail.txt  the last 200 lines of the lane's batch.log
#   procs.txt       Kenshi instances (path, start, memory), capture/encode tools (ffmpeg, wgccap), python, vmmem, nvidia-smi
#                   (full + compute apps), the runner state/running lists
#   timeline.tsv    the last 80 lines of gpulog\timeline.tsv (processes per lane, WSL GPU jobs, batch rows, TDRs)
#   livekernel.txt  C:\Windows\LiveKernelReports files newer than <Since> - 10 min (WATCHDOG dumps: name, time, size; readable
#                   ones only, no copy of the dump)
# Prints "TDR-EVIDENCE <dir> files=<n>". Never stops or changes anything.
param([Parameter(Mandatory = $true)][string]$Out, [string]$Rig = '5090', [long]$Since = 0, [string]$BatchLog = '', [int]$Minutes = 5)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Out | Out-Null
$now = Get-Date
$t0 = if ($Since -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($Since).LocalDateTime } else { $now.AddMinutes(-$Minutes) }

# gpulog: rows of the newest csv(s) from the last $Minutes min (timestamp column "yyyy/MM/dd HH:mm:ss.fff")
$g = @(Get-ChildItem 'C:\KenshiTestRuns\gpulog' -Filter "$Rig-*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 2)
if ($g.Count) {
    $hdr = Get-Content $g[-1].FullName -TotalCount 1
    $cut = $now.AddMinutes(-$Minutes)
    function TailShared([string]$p, [int]$n) {   # gpulog.ps1 appends every 2 s: open shared, a few retries
        for ($i = 0; $i -lt 5; $i++) {
            try { $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite, Delete'); try { $t = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Close() }
                return @($t -split "`r?`n" | Where-Object { $_ } | Select-Object -Last $n) } catch { Start-Sleep -Milliseconds 150 } }
        @() }
    $rows = foreach ($f in $g) { TailShared $f.FullName 400 | Where-Object { $_ -notlike 'timestamp*' } | Where-Object {
            $ts = ($_ -split ',')[0].Trim(); $d = [datetime]::MinValue
            [datetime]::TryParseExact($ts, 'yyyy/MM/dd HH:mm:ss.fff', $null, 0, [ref]$d) -and $d -ge $cut } }
    @($hdr) + @($rows) | Set-Content (Join-Path $Out 'gpulog.csv')
} else { 'no gpulog csv for this rig (gpulog-ensure.ps1 not running?)' | Set-Content (Join-Path $Out 'gpulog.csv') }
# timeline: the last 80 lines of gpulog\timeline.tsv (process start/exit per lane, WSL GPU jobs, batch launch/row/stop, TDRs)
$tlp = 'C:\KenshiTestRuns\gpulog\timeline.tsv'
if (Test-Path $tlp) { try { Get-Content $tlp -Tail 80 -ErrorAction Stop | Set-Content (Join-Path $Out 'timeline.tsv') } catch { "timeline read failed: $($_.Exception.Message)" | Set-Content (Join-Path $Out 'timeline.tsv') } }

# events
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $now.AddMinutes(-30) } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'nvlddmkm|Display|LiveKernel|WHEA|Kernel-Power|dxgkrnl' -or $_.Id -in 4101, 153, 141, 117 }
@("System events (GPU/kernel) since $($now.AddMinutes(-30).ToString('s')): $(@($ev).Count)") + @($ev | ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss} {1} {2} {3}' -f $_.TimeCreated, $_.ProviderName, $_.Id, (([string]$_.Message -replace '\s+', ' ').Substring(0, [Math]::Min(300, ([string]$_.Message -replace '\s+', ' ').Length))) }) |
    Set-Content (Join-Path $Out 'events.txt')

# batch log tail
if ($BatchLog -and (Test-Path -LiteralPath $BatchLog)) { Get-Content -LiteralPath $BatchLog -Tail 200 | Set-Content (Join-Path $Out 'batch-tail.txt') }

# processes + GPU users + runner state
$p = New-Object Collections.Generic.List[string]
$p.Add("== $($now.ToString('s')) rig $Rig")
$p.Add('== kenshi instances')
Get-Process kenshi_x64 -ErrorAction SilentlyContinue | ForEach-Object { $p.Add(('pid={0} start={1:HH:mm:ss} ws={2}MB priv={3}MB path={4}' -f $_.Id, $_.StartTime, [int]($_.WorkingSet64 / 1MB), [int]($_.PrivateMemorySize64 / 1MB), $_.Path)) }
$p.Add('== capture / encode / lab / wsl')
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(ffmpeg|wgccap|python|python3|vmmem|vmmemWSL|wsl|powershell)\.?' -or $_.Name -match 'ffmpeg|wgccap' } |
    ForEach-Object { $p.Add(('pid={0} {1} {2}' -f $_.ProcessId, $_.Name, ([string]$_.CommandLine).Substring(0, [Math]::Min(220, ([string]$_.CommandLine).Length)))) }
$p.Add('== nvidia-smi')
& nvidia-smi.exe 2>&1 | ForEach-Object { $p.Add("$_") }
& nvidia-smi.exe --query-compute-apps=pid,process_name,used_memory --format=csv 2>&1 | ForEach-Object { $p.Add("$_") }
$p.Add('== runner')
Get-ChildItem 'C:\KenshiTestRuns\queue\running' -ErrorAction SilentlyContinue | ForEach-Object { $p.Add("running $($_.Name) since $($_.LastWriteTime.ToString('HH:mm:ss'))") }
Get-ChildItem 'C:\KenshiTestRuns\runner' -Filter '*.state' -ErrorAction SilentlyContinue | ForEach-Object { $p.Add("$($_.BaseName): $(Get-Content $_.FullName -Raw)".Trim()) }
$p | Set-Content (Join-Path $Out 'procs.txt')

# LiveKernelReports (WATCHDOG dumps of a TDR)
$lk = @(Get-ChildItem 'C:\Windows\LiveKernelReports' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $t0.AddMinutes(-10) })
@("LiveKernelReports newer than $($t0.AddMinutes(-10).ToString('s')): $($lk.Count)") + @($lk | ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss} {1} {2}KB' -f $_.LastWriteTime, $_.FullName, [int]($_.Length / 1KB) }) |
    Set-Content (Join-Path $Out 'livekernel.txt')
"TDR-EVIDENCE $Out files=$(@(Get-ChildItem $Out -File).Count)"
