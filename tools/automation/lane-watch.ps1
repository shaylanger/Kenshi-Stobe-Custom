# lane-watch.ps1: per-lane stuck detector (Shay 2026-10-11 18:40: lane A sat paused 6 min, the coordinator did not notice).
# Reads C:\KenshiTestRuns\runner\<lane>.state for every game lane and prints one line per lane that has NOT been running a
# test row for more than -Max seconds (launch, dry run, gfx relaunch, "busy with other work", PARKED, paused, dead runner):
#   LANE STUCK <lane> <secs>s <state>
# else one line "LANES OK n=<lanes>". Exit 0 OK, 1 STUCK. Memory per lane in runner\lanewatch.json (first non-productive time). A lane already reported is reported again only after -Repeat s (120).
# Productive = state says "running" with a real row (row=<x>, not row=-) or a lane batch "HEALTH OK ... phase=world".
# Used by lane-waker.sh (the coordinator's waker; checks every 15 s and wakes at once on STUCK).
param([int]$Max = 90, [int]$Repeat = 120, [string[]]$Lanes = @('5090', '5090b', '5090c', '4080', '4080b'))
$dir = 'C:\KenshiTestRuns\runner'
$memF = Join-Path $dir 'lanewatch.json'
$now = Get-Date
$mem = @{}
if (Test-Path $memF) { try { (Get-Content $memF -Raw | ConvertFrom-Json).psobject.Properties | ForEach-Object { $mem[$_.Name] = [datetime]$_.Value } } catch {} }
$out = @(); $n = 0
foreach ($l in $Lanes) {
    $f = Join-Path $dir "$l.state"
    if (-not (Test-Path $f)) { continue }
    $n++
    $it = Get-Item $f
    $s = ((Get-Content $f -TotalCount 1) -as [string]).Trim()
    $stale = $it.LastWriteTime -lt $now.AddMinutes(-3)
    $prod = (-not $stale) -and ($s -match ' running ') -and (($s -match 'row=[^-\s]') -or ($s -match 'HEALTH OK.*phase=world') -or ($s -match 'step=[^-\s].*phase=world'))
    if ($s -match 'no changed work') { $prod = $true }   # the one allowed idle (CLAUDE.md rig uptime)
    if ($prod) { $mem.Remove($l); $mem.Remove("rep:$l"); continue }
    if (-not $mem.ContainsKey($l)) { $mem[$l] = $now }
    $age = [int]($now - $mem[$l]).TotalSeconds
    # one report per lane per -Repeat s (the waker would otherwise wake at once again for a lane already being handled)
    $rk = "rep:$l"
    if ($age -gt $Max -and (-not $mem.ContainsKey($rk) -or ($now - $mem[$rk]).TotalSeconds -ge $Repeat)) { $mem[$rk] = $now; $out +="LANE STUCK $l ${age}s $(if ($stale) { '(state file stale: runner dead?) ' })$($s.Substring(0, [Math]::Min(200, $s.Length)))" }
}
$h = @{}; foreach ($k in $mem.Keys) { $h[$k] = $mem[$k].ToString('o') }
$h | ConvertTo-Json | Set-Content $memF -Encoding utf8
if ($out.Count) { $out; exit 1 }
"LANES OK n=$n"; exit 0
