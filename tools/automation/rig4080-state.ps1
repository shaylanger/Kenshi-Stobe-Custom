# rig4080-state.ps1: ONE word about the 4080 rig: BUSY | IDLE | IDLE-OK | UNREACHABLE (+ detail).
# Why (Shay 2026-10-10): the 4080 sat idle for a day while the 5090 worked; every check (Stop hook, rig-health.sh) only
# looked at the local game, so "5090 busy" hid "4080 idle". This makes the 4080 visible to the hook and the wakers.
#   BUSY        Kenshi runs on the 4080, or a marker C:\KenshiTestRuns\inflight\4080-* (newer than 6 h) claims it
#   IDLE        Kenshi closed on the 4080, no 4080 marker, no fresh reason => put the next PG/harness/KenshiFP rows there
#   IDLE-OK     idle with a reason < 60 min old in C:\KenshiTestRuns\rig4080.idle (kenshi-ctl.ps1 idle4080 "<reason>")
#   UNREACHABLE ssh failed (4080 off/asleep): treated like IDLE-OK by the hook, but say so in the summary
# Result is cached 3 min in C:\KenshiTestRuns\rig4080.state (ssh ~0.3 s; the Stop hook calls this every turn).
# Use: powershell -NoProfile -File tools\automation\rig4080-state.ps1 [-Fresh]
param([switch]$Fresh)
$runs = 'C:\KenshiTestRuns'
$cache = Join-Path $runs 'rig4080.state'
$mk = @(Get-ChildItem -LiteralPath (Join-Path $runs 'inflight') -Filter '4080*' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) } | ForEach-Object Name)
# A marker naming a 4080 job ("4080:<path> ...") is checked for its end file (<path>.DONE, <stem>.DONE or <path>\DONE)
# over ssh: a finished job no longer counts as BUSY (Shay 2026-10-10: no rig idle or paused > 2 min).
# Cheap (res-wait 2026-10-10): ONE ssh for all marker paths per call, a path seen DONE is remembered for good
# (rig4080.markerdone), a RUN answer is reused for 60 s (rig4080.markerrun) instead of one ssh per marker per call.
$mkBusy = @(); $ask = @{}
$doneF = Join-Path $runs 'rig4080.markerdone'; $runF = Join-Path $runs 'rig4080.markerrun'
$known = @(Get-Content -LiteralPath $doneF -ErrorAction SilentlyContinue)
$runFresh = (Test-Path -LiteralPath $runF) -and (Get-Item -LiteralPath $runF).LastWriteTime -gt (Get-Date).AddSeconds(-60)
$runKnown = if ($runFresh) { @(Get-Content -LiteralPath $runF -ErrorAction SilentlyContinue) } else { @() }
foreach ($n in $mk) {
    $first = ((Get-Content -LiteralPath (Join-Path $runs "inflight\$n") -TotalCount 1 -ErrorAction SilentlyContinue) -as [string])
    if ($first -match '^4080:(\S+)') {
        $p = $Matches[1]
        if ($known -contains $p) { continue }
        if ($runKnown -contains $p) { $mkBusy += $n; continue }
        $ask[$n] = $p; continue
    }
    $mkBusy += $n
}
if ($ask.Count) {
    $q = ($ask.Values | Select-Object -Unique | ForEach-Object { $s_ = $_ -replace '\.[A-Za-z0-9]+$', ''; "if ((Test-Path '$_.DONE') -or (Test-Path '$s_.DONE') -or (Test-Path '$_\DONE')) { 'DONE $_' } else { 'RUN $_' }" }) -join '; '
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($q))
    $r = @(& ssh -o BatchMode=yes -o ConnectTimeout=5 4080 "powershell -NoProfile -EncodedCommand $b64" 2>$null | ForEach-Object { "$_".Trim() })
    $newDone = @($r | Where-Object { $_ -like 'DONE *' } | ForEach-Object { $_.Substring(5) })
    if ($newDone.Count) { Add-Content -LiteralPath $doneF -Value $newDone -Encoding ascii }
    Set-Content -LiteralPath $runF -Value @($runKnown + @($r | Where-Object { $_ -like 'RUN *' } | ForEach-Object { $_.Substring(4) })) -Encoding ascii
    foreach ($n in $ask.Keys) { if ($newDone -notcontains $ask[$n]) { $mkBusy += $n } }
}
if ($mkBusy.Count) { "BUSY marker=$($mkBusy -join ',')"; exit 0 }
$allDone = $mk.Count -gt 0
# every marker job is DONE: look at the rig itself, but at most once a minute (was: a fresh ssh on every call)
$maxAge = if ($allDone) { -1 } else { -3 }
if (-not $Fresh -and (Test-Path -LiteralPath $cache) -and (Get-Item -LiteralPath $cache).LastWriteTime -gt (Get-Date).AddMinutes($maxAge)) {
    $k = (Get-Content -LiteralPath $cache -Raw).Trim()
} else {
    # instance 1 only (multi-instance-4080): lane 4080b's second game (C:\KenshiInst\<n>) must not hide an idle lane 4080
    $q1 = "if (@(Get-CimInstance Win32_Process -Filter `"Name='kenshi_x64.exe'`" | Where-Object { -not `$_.ExecutablePath -or `$_.ExecutablePath -notlike '*\KenshiInst\*' }).Count) { 'K1 yes' } else { 'K1 no' }"
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=5 4080 "powershell -NoProfile -EncodedCommand $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($q1)))" 2>$null
    $k = if ($LASTEXITCODE -ne 0 -or -not ($out -match '^K1 ')) { 'UNREACHABLE' } elseif ($out -match '^K1 yes') { 'BUSY kenshi=yes' } else { 'IDLE kenshi=no' }
    Set-Content -LiteralPath $cache -Value $k -Encoding ascii
}
if ($allDone -and $k -like 'BUSY kenshi=yes*') { $k = "IDLE-GAME kenshi=yes all marker jobs DONE ($($mk -join ',')): queue a list in queue\4080\ (rig-runner.ps1 starts it)" }
if ($k -like 'IDLE*') {
    $f = Join-Path $runs 'rig4080.idle'
    if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).LastWriteTime -gt (Get-Date).AddMinutes(-60)) {
        $k = "IDLE-OK reason=$((Get-Content -LiteralPath $f -Raw).Trim())"
    }
}
$k
