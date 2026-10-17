# status-digest.ps1 (cut3, Shay-approved credit cut 2026-10-16): ONE cheap call replaces the coordinator's status-read turns
# (cat *.status, agent-rollcall, session-start -Brief, alert count, lane check). Prints one compact block, read-only except the "since" stamp.
#   status-digest.ps1 [-Consumer coord] [-Peek] [-SinceMin N] [-MaxRun 12] [-NoLanes] [-Json]
# Block:
#   DIGEST <time> run=<n> done_since=<n> problems=<n> alerts=<n>(oldest <m>m) lanes=<ACTIVE n=5|n problem(s)|-> [WIND-DOWN]
#   RUN  <name> <statusAge>m [ev <evidenceAge>m] <latest 70 chars>        (RUNNING agents, oldest-silent first, max -MaxRun)
#   DONE <name> <hh:mm> <task 50>                                         (DONE/FAILED/STOPPED-CONTEXT since the previous call of this -Consumer)
#   PROBLEM <ORPHANED|NO SUCCESSOR line from agent-guard-lib, 160 chars>   (the same lines session-start prints)
#   ALERT <id> <age>m <text 100>                                          (alerts\open, max 4)
#   LANE <lane-idle.ps1 problem line, 140 chars>                          (only problems; healthy = the lanes= field)
#   INBOX <n> unread file(s) in inbox\coordinator                         (only when > 0)
# "Since" stamp: <runs>\digest.since.json {consumer: iso time}; -Peek reads without advancing; first call = last 60 min.
# Wake-up payload wiring (proposal, the running waker is NOT edited here): see C:\KenshiTestRuns\inbox\operators\cut3.txt section W.
# Test switches: KAH_RUNS_DIR (runs root).
param(
    [string]$Consumer = 'coord', [switch]$Peek, [int]$SinceMin = 0, [int]$MaxRun = 12, [switch]$NoLanes, [switch]$Json
)
$ErrorActionPreference = 'SilentlyContinue'
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$here = $PSScriptRoot
$now = Get-Date
function Cut([string]$s, [int]$n) { $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }

# --- since stamp
$sinceFile = Join-Path $runs 'digest.since.json'
$since = $now.AddMinutes(-60)
$stamps = @{}
if (Test-Path -LiteralPath $sinceFile) {
    try { $o = Get-Content -LiteralPath $sinceFile -Raw | ConvertFrom-Json; foreach ($p in $o.psobject.Properties) { $stamps[$p.Name] = [string]$p.Value } } catch { }
    if ($stamps.ContainsKey($Consumer)) { try { $since = [datetime]$stamps[$Consumer] } catch { } }
}
if ($SinceMin -gt 0) { $since = $now.AddMinutes(-$SinceMin) }

# --- running agents
. (Join-Path $here 'agent-rollcall.ps1')
$roll = @(Get-AgentRoll | Sort-Object { -[double]$_.StatusAgeMin })
$runLines = @()
foreach ($r in ($roll | Select-Object -First $MaxRun)) {
    $ev = if ($null -ne $r.LogAgeMin) { " ev $($r.LogAgeMin)m" } else { '' }
    $dead = if ($r.Kind -eq 'INDEPENDENT' -and -not $r.Alive) { ' PROC-DEAD' } else { '' }
    $runLines += "RUN  $($r.Name) $($r.StatusAgeMin)m$ev$dead $(Cut $r.Latest 70)"
}
if ($roll.Count -gt $MaxRun) { $runLines += "RUN  ... +$($roll.Count - $MaxRun) more (oldest-silent shown first)" }

# --- finished since the last call
$doneLines = @()
$ad = Join-Path $runs 'agents'
foreach ($f in Get-ChildItem -LiteralPath $ad -Filter '*.status' -File | Where-Object { $_.LastWriteTime -gt $since } | Sort-Object LastWriteTime) {
    $ls = @(Get-Content -LiteralPath $f.FullName -TotalCount 2)
    if (-not $ls.Count) { continue }
    $parts = (($ls[0] -replace '^\uFEFF', '') -split '\s*\|\s*')
    if ($parts.Count -lt 2 -or $parts[1].Trim() -notin 'DONE', 'FAILED', 'STOPPED-CONTEXT') { continue }
    $t = if ($ls.Count -gt 1) { $ls[1] -replace '^task:\s*', '' } else { '' }
    $doneLines += "$($parts[1].Trim()) $($parts[0].Trim()) $($f.LastWriteTime.ToString('HH:mm')) $(Cut $t 50)"
}

# --- problems (orphaned / no successor): the same logic the Stop hook and session-start use
$prob = @()
try { . (Join-Path $here 'agent-guard-lib.ps1'); $prob = @(Get-AgentHealthLines | ForEach-Object { Cut $_ 160 }) } catch { }

# --- open alerts
$alerts = @()
$od = Join-Path $runs 'alerts\open'
foreach ($f in Get-ChildItem -LiteralPath $od -Filter '*.json' -File | Sort-Object LastWriteTime) {
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        $age = [int]($now - [datetime]$j.opened_at).TotalMinutes
        $alerts += [pscustomobject]@{ Id = $f.BaseName; Age = $age; Text = (Cut ([string]$j.text) 100) }
    } catch { }
}
$oldest = if ($alerts.Count) { ($alerts | Measure-Object Age -Maximum).Maximum } else { 0 }

# --- lanes (lane-idle.ps1 -NoMemory prints "LANES ACTIVE n=5" or one line per problem; no memory/alert side effects)
$laneState = '-'; $laneLines = @()
if (-not $NoLanes) {
    $li = Join-Path $here 'lane-idle.ps1'
    if (Test-Path -LiteralPath $li) {
        $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $li -NoMemory -Runs $runs 2>$null)
        $act = @($out | Where-Object { $_ -match '^LANES ACTIVE' })
        $bad = @($out | Where-Object { $_ -match '^LANE ' })
        if ($bad.Count) { $laneState = "$($bad.Count) problem(s)"; $laneLines = @($bad | Select-Object -First 4 | ForEach-Object { 'LANE ' + (Cut ($_ -replace '^LANE ', '') 140) }) }
        elseif ($act.Count) { $laneState = ($act[0] -replace '^LANES ', '') }
        else { $laneState = 'unknown' }
    }
}
$inbox = 0; $id = Join-Path $runs 'inbox\coordinator'
if (Test-Path -LiteralPath $id) { $inbox = @(Get-ChildItem -LiteralPath $id -File).Count }
$wd = if (Test-Path -LiteralPath (Join-Path $runs 'WIND_DOWN.flag')) { ' WIND-DOWN' } else { '' }

if ($Json) {
    [pscustomobject]@{ time = $now.ToString('s'); running = $roll.Count; run = $runLines; finished = $doneLines; problems = $prob; alerts = $alerts; lanes = $laneState; laneLines = $laneLines; inbox = $inbox } | ConvertTo-Json -Depth 4
} else {
    "DIGEST $($now.ToString('HH:mm')) run=$($roll.Count) finished_since=$($doneLines.Count) problems=$($prob.Count) alerts=$($alerts.Count)(oldest $($oldest)m) lanes=$laneState$wd"
    $runLines
    foreach ($d in ($doneLines | Select-Object -Last 12)) { $d }
    if ($doneLines.Count -gt 12) { "(+$($doneLines.Count - 12) earlier finished; newest 12 shown)" }
    foreach ($p in $prob) { "PROBLEM $p" }
    foreach ($a in ($alerts | Select-Object -First 4)) { "ALERT $($a.Id) $($a.Age)m $($a.Text)" }
    $laneLines
    if ($inbox -gt 0) { "INBOX $inbox file(s) in inbox\coordinator" }
}
if (-not $Peek) {
    try { $stamps[$Consumer] = $now.ToString('s'); ($stamps | ConvertTo-Json) | Set-Content -LiteralPath $sinceFile -Encoding UTF8 } catch { }
}
