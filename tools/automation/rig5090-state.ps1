# rig5090-state.ps1: ONE line about whether the 5090 game slot is really working (used by rig-health.sh and the
# kenshi-waker-guard Stop hook). Shay 2026-10-10: the 5090 sat idle 13:31-13:36 because Kenshi was open, the lock held
# and inflight\5090-operator still pointed at a batch that had written DONE, so everything said BUSY.
#   BUSY <why>        a game batch is running (marker -> out dir without DONE), or a 5090 marker was touched < 3 min ago
#   IDLE-GAME <why>   Kenshi open and/or lock held, but no batch has run for > 3 min (every marked out dir has DONE)
#   IDLE-OK <reason>  idle with a reason recorded (kenshi-ctl.ps1 idle "<reason>", < 60 min old)
#   IDLE              Kenshi closed, lock free
# Markers: C:\KenshiTestRuns\inflight\<name>, first line = out dir (/mnt/c/... or C:\...) of the running batch.
# Game work = the lock owner's marker or a run-batch out dir (has batch.log); 4080-* and offline/lab markers are ignored,
# except a plain marker of the lock owner, which counts while < 30 min old (an operator between list and launch).
param([int]$GraceMin = 2)
$runs = 'C:\KenshiTestRuns'
$now = Get-Date
$kenshiP = Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue | Select-Object -First 1
$lockFile = Join-Path $runs 'game.lock'
$owner = $null; $last = $null
if (Test-Path -LiteralPath $lockFile) {
    $owner = ((Get-Content -LiteralPath $lockFile -TotalCount 1 -ErrorAction SilentlyContinue) -as [string]).Trim()
    $last = (Get-Item -LiteralPath $lockFile).LastWriteTime
}
$idleFile = Join-Path $runs 'rig5090.idle'
$reason = $null
if ((Test-Path -LiteralPath $idleFile) -and (Get-Item -LiteralPath $idleFile).LastWriteTime -gt $now.AddMinutes(-60)) {
    $reason = ((Get-Content -LiteralPath $idleFile -Raw) -as [string]).Trim()
}
if (-not $kenshiP -and -not $owner) {
    if ($reason) { "IDLE-OK $reason" } else { 'IDLE' }
    exit 0
}
if ($kenshiP -and $kenshiP.StartTime -and (-not $last -or $kenshiP.StartTime -gt $last)) { $last = $kenshiP.StartTime }
$busy = @(); $done = @()
foreach ($m in @(Get-ChildItem -LiteralPath (Join-Path $runs 'inflight') -File -ErrorAction SilentlyContinue)) {
    if ($m.Name -like '4080-*' -or $m.LastWriteTime -lt $now.AddHours(-6)) { continue }
    $p = ((Get-Content -LiteralPath $m.FullName -TotalCount 1 -ErrorAction SilentlyContinue) -as [string])
    $p = if ($p) { $p.Trim() } else { '' }
    $win = $null
    if ($p -match '^/mnt/([a-z])/(.*)$') { $win = ($Matches[1].ToUpper() + ':\' + ($Matches[2] -replace '/', '\')) }
    elseif ($p -match '^[A-Za-z]:[\\/]') { $win = $p }
    # game work = the lock owner's marker or a run-batch out dir (batch.log); lab/offline jobs (WSL path, plain text,
    # a C: scratch dir without batch.log) are not 5090 game work
    if ($m.Name -ne $owner -and -not ($win -and (Test-Path -LiteralPath (Join-Path $win 'batch.log')))) { continue }
    if ($m.LastWriteTime -gt $last) { $last = $m.LastWriteTime }
    if ($m.LastWriteTime -gt $now.AddMinutes(-$GraceMin)) { $busy += "$($m.Name)(touched)"; continue }
    if ($win -and (Test-Path -LiteralPath $win -PathType Container)) {
        $d = Join-Path $win 'DONE'
        if (Test-Path -LiteralPath $d) {
            $t = (Get-Item -LiteralPath $d).LastWriteTime
            if ($t -gt $last) { $last = $t }
            $done += "$($m.Name)=DONE@$($t.ToString('HH:mm'))"
        } else { $busy += "$($m.Name)->$p" }
    } elseif (-not $win -and $m.Name -eq $owner -and $m.LastWriteTime -gt $now.AddMinutes(-30)) {
        $busy += "$($m.Name)(owner marker)"
    }
}
# newest finished batch anywhere in C:\KenshiTestRuns (run-batch.sh deletes its marker at DONE, so markers alone lose the end time)
$nd = Get-ChildItem -LiteralPath $runs -Directory -ErrorAction SilentlyContinue | ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'DONE') -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($nd -and $nd.LastWriteTime -gt $last) { $last = $nd.LastWriteTime; $done += "last DONE $(Split-Path $nd.DirectoryName -Leaf)@$($nd.LastWriteTime.ToString('HH:mm'))" }
if ($busy.Count) { "BUSY $($busy -join ' ')"; exit 0 }
if ($last -and $last -gt $now.AddMinutes(-$GraceMin)) { "BUSY between batches (last change $($last.ToString('HH:mm')))"; exit 0 }
if ($reason) { "IDLE-OK $reason"; exit 0 }
$k = if ($kenshiP) { 'kenshi=yes' } else { 'kenshi=no' }
$ago = if ($last) { [int]($now - $last).TotalMinutes } else { -1 }
"IDLE-GAME $k lock=$owner no batch running for ${ago} min ($($done -join ' ')): launch queue\5090.next or record kenshi-ctl.ps1 idle `"<reason>`""
exit 0
