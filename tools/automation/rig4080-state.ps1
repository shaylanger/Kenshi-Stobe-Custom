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
if ($mk.Count) { "BUSY marker=$($mk -join ',')"; exit 0 }
if (-not $Fresh -and (Test-Path -LiteralPath $cache) -and (Get-Item -LiteralPath $cache).LastWriteTime -gt (Get-Date).AddMinutes(-3)) {
    $k = (Get-Content -LiteralPath $cache -Raw).Trim()
} else {
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=5 4080 'tasklist /nh' 2>$null
    $k = if ($LASTEXITCODE -ne 0 -or -not $out) { 'UNREACHABLE' } elseif ($out -match 'kenshi_x64') { 'BUSY kenshi=yes' } else { 'IDLE kenshi=no' }
    Set-Content -LiteralPath $cache -Value $k -Encoding ascii
}
if ($k -like 'IDLE*') {
    $f = Join-Path $runs 'rig4080.idle'
    if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).LastWriteTime -gt (Get-Date).AddMinutes(-60)) {
        $k = "IDLE-OK reason=$((Get-Content -LiteralPath $f -Raw).Trim())"
    }
}
$k
