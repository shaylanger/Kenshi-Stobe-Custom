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
$mkBusy = @()
foreach ($n in $mk) {
    $first = ((Get-Content -LiteralPath (Join-Path $runs "inflight\$n") -TotalCount 1 -ErrorAction SilentlyContinue) -as [string])
    if ($first -match '^4080:(\S+)') {
        $p = $Matches[1]; $stem = $p -replace '\.[A-Za-z0-9]+$', ''
        $q = "if ((Test-Path '$p.DONE') -or (Test-Path '$stem.DONE') -or (Test-Path '$p\DONE')) { 'DONE' } else { 'RUN' }"
        $r = & ssh -o BatchMode=yes -o ConnectTimeout=5 4080 "powershell -NoProfile -Command `"$q`"" 2>$null
        if (($r -join '') -match 'DONE') { continue }
    }
    $mkBusy += $n
}
if ($mkBusy.Count) { "BUSY marker=$($mkBusy -join ',')"; exit 0 }
$allDone = $mk.Count -gt 0
if ($allDone) { $Fresh = $true }   # every marker job is DONE: look at the rig itself
if (-not $Fresh -and (Test-Path -LiteralPath $cache) -and (Get-Item -LiteralPath $cache).LastWriteTime -gt (Get-Date).AddMinutes(-3)) {
    $k = (Get-Content -LiteralPath $cache -Raw).Trim()
} else {
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=5 4080 'tasklist /nh' 2>$null
    $k = if ($LASTEXITCODE -ne 0 -or -not $out) { 'UNREACHABLE' } elseif ($out -match 'kenshi_x64') { 'BUSY kenshi=yes' } else { 'IDLE kenshi=no' }
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
