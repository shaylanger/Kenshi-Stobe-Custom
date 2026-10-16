# operator-warn.ps1: lane-operator handover OVERLAP detector (Shay 2026-10-15, order #2): the successor operator is started
# BEFORE the old one dies, so the lane never idles.
#
# Contract: an operator at ~120k context runs  agent-status.ps1 <name> RUNNING "<task>" "WARN-120k ..." ...  ; agent-status.ps1
# then writes the marker  <runs>\agents\<name>.warn  (cleared by any DONE / FAILED / STOPPED-CONTEXT). This script (standalone,
# no waker edit needed to try it) prints ONE line per NEW warn, de-duplicated by the state file <runs>\operator-warn.state.json:
#   OPERATOR WARN <name> lane <lane> successor=<new> | brief: <cmd> | prompt: <Agent prompt, two lines joined by ' // '> | register: <cmd>
# The same text, multi-line, is saved to <runs>\agents\<name>.warn.spawn.md. Nothing is printed when nothing is new (exit 0).
#
#   operator-warn.ps1 [-Runs dir] [-Peek]                 detect (Peek = do not mark as seen)
#   operator-warn.ps1 -Register <old> <new> [-Runs dir]   put <new> at the front of the lane's ops in lane-owners.json (atomic); prints
#                                                         "REGISTERED lane <lane>: <new>,<old>,..." ; lane-idle.ps1 / lane-brief.ps1 / agent-guard rule (e) read it
#   operator-warn.ps1 -Selftest                           see operator-warn-selftest.ps1
# Lane <-> operator: lane-idle.ps1 table + <runs>\lane-owners.json (same precedence as lane-idle.ps1). A warn from an agent that is
# not a lane operator is still reported: "lane -" and a respawn-from-handoff hint (no lane-brief command).
# Successor name: trailing number + 1 (imm26-5090-i3op3 -> ...op4, skipping names already used by a status file, a brief or any lane ops
# list), else name + '2'. The successor's status TASK must equal the predecessor's task (agent-guard rule b) .
# Exit 0 always except bad usage (2). Test switch: KAH_RUNS_DIR.
param(
    [string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }),
    [switch]$Peek,
    [string]$Register,
    [Parameter(Position = 0)][string]$New
)
$ErrorActionPreference = 'Stop'
$agents = Join-Path $Runs 'agents'
$tools = $PSScriptRoot
$stateF = Join-Path $Runs 'operator-warn.state.json'

function Get-LaneTable {
    $lanes = [ordered]@{}
    $li = Join-Path $tools 'lane-idle.ps1'
    if (Test-Path -LiteralPath $li) {
        $txt = Get-Content -LiteralPath $li -Raw
        foreach ($m in [regex]::Matches($txt, "'([^']+)'\s*=\s*@\{\s*ops\s*=\s*@\(([^)]*)\)")) {
            $lanes[$m.Groups[1].Value] = @([regex]::Matches($m.Groups[2].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        }
    }
    $ov = Join-Path $Runs 'lane-owners.json'
    if (Test-Path -LiteralPath $ov) {
        try { $j = Get-Content -LiteralPath $ov -Raw | ConvertFrom-Json; foreach ($p in $j.psobject.Properties) { $lanes[$p.Name] = @($p.Value.ops | Where-Object { $_ } | ForEach-Object { "$_" }) } } catch { }
    }
    $lanes
}
function Get-LaneOf([string]$name, $lanes) { foreach ($l in $lanes.Keys) { if (@($lanes[$l]) -contains $name) { return $l } }; $null }
function Get-State([string]$file) {   # first line of a status file -> RUNNING|DONE|... or $null
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $first = ((Get-Content -LiteralPath $file -TotalCount 1 -Encoding UTF8) -as [string]) -replace '^\uFEFF', ''
    if ($first -match '^\s*[^|]+\|\s*(RUNNING|DONE|FAILED|STOPPED-CONTEXT)\s*\|') { $Matches[1] } else { $null }
}
function Get-Successor([string]$name, $lanes) {
    $used = @{}
    foreach ($l in $lanes.Keys) { foreach ($o in $lanes[$l]) { $used[$o] = 1 } }
    if ($name -match '^(.*?)(\d+)$') { $stem = $Matches[1]; $n = [int]$Matches[2] + 1 } else { $stem = $name; $n = 2 }
    while ($true) {
        $c = "$stem$n"
        if (-not $used.ContainsKey($c) -and -not (Test-Path -LiteralPath (Join-Path $agents "$c.status")) -and -not (Test-Path -LiteralPath (Join-Path $agents "$c.brief.md"))) { return $c }
        $n++
    }
}

# ---- -Register <old> <new> ----
if ($Register) {
    if (-not $New) { [Console]::Error.WriteLine('usage: operator-warn.ps1 -Register <old> <new>'); exit 2 }
    $ov = Join-Path $Runs 'lane-owners.json'
    if (-not (Test-Path -LiteralPath $ov)) { [Console]::Error.WriteLine("no $ov"); exit 2 }
    $j = Get-Content -LiteralPath $ov -Raw | ConvertFrom-Json
    $done = $false
    foreach ($p in $j.psobject.Properties) {
        $ops = @($p.Value.ops | ForEach-Object { "$_" })
        if ($ops -contains $Register) {
            if ($ops -notcontains $New) { $p.Value.ops = @(@($New) + $ops) }
            "REGISTERED lane $($p.Name): $(@($p.Value.ops) -join ',')"; $done = $true; break
        }
    }
    if (-not $done) { [Console]::Error.WriteLine("operator '$Register' is in no lane of $ov"); exit 2 }
    $tmp = "$ov.tmp$PID"
    ($j | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $ov -Force
    exit 0
}

# ---- detect ----
$seen = @{}
if (Test-Path -LiteralPath $stateF) { try { (Get-Content -LiteralPath $stateF -Raw | ConvertFrom-Json).psobject.Properties | ForEach-Object { $seen[$_.Name] = "$($_.Value)" } } catch { } }
$lanes = Get-LaneTable
$changed = $false
$live = @{}
if (Test-Path -LiteralPath $agents) {
    foreach ($w in Get-ChildItem -LiteralPath $agents -Filter '*.warn' -File -ErrorAction SilentlyContinue) {
        $name = $w.Name.Substring(0, $w.Name.Length - 5)
        $st = Get-State (Join-Path $agents "$name.status")
        if ($st -ne 'RUNNING') { if (-not $Peek) { Remove-Item -LiteralPath $w.FullName, (Join-Path $agents "$name.warn.spawn.md") -Force -ErrorAction SilentlyContinue }; continue }   # terminal / unknown: stale marker
        $live[$name] = 1
        $stamp = $w.LastWriteTimeUtc.ToString('o')
        if ($seen.ContainsKey($name) -and $seen[$name] -eq $stamp) { continue }
        $lane = Get-LaneOf $name $lanes
        $task = ''
        try { $t = Get-Content -LiteralPath (Join-Path $agents "$name.status") -Encoding UTF8 -TotalCount 2 | Select-Object -Skip 1 -First 1; if ($t -match '^task:\s?(.*)$') { $task = $Matches[1].Trim() } } catch { }
        $briefDir = $agents
        if ($lane) {
            $new = Get-Successor $name $lanes
            $brief = "powershell -NoProfile -File $tools\lane-brief.ps1 $lane -Out $briefDir\$new.brief.md -Name $new -Predecessor $name"
            $p1 = "[case:generate] You are $new, lane $lane. Read $briefDir\$new.brief.md (PREDECESSOR HANDOVER section), then the handoff it names, and start the next row."
            $p2 = "Predecessor $name keeps running until it reports DONE/STOPPED-CONTEXT: do not launch/stop/command the lane before that; your status TASK must be exactly: $task"
            $reg = "powershell -NoProfile -File $tools\operator-warn.ps1 -Register $name $new"
            $line = "OPERATOR WARN $name lane $lane successor=$new | brief: $brief | prompt: $p1 // $p2 | register: $reg"
            $md = @("# OPERATOR WARN $name lane $lane (successor $new)", '', '1. Generate the brief:', '', "    $brief", '', '2. Spawn (Agent tool prompt, two lines):', '', "    $p1", "    $p2", '', '3. Update lane-owners.json (new name first in ops):', '', "    $reg", '', "Predecessor stays RUNNING during the overlap; this marker clears itself when $name reports DONE/FAILED/STOPPED-CONTEXT.")
        } else {
            $new = Get-Successor $name $lanes
            $line = "OPERATOR WARN $name lane - successor=$new | not a lane operator (no lane-owners entry): respawn a fresh agent $new from $agents\$name.handoff.md or the status file, same task text: $task"
            $md = @("# OPERATOR WARN $name lane - (successor $new)", '', $line)
        }
        if (-not $Peek) {
            try { $md | Set-Content -LiteralPath (Join-Path $agents "$name.warn.spawn.md") -Encoding UTF8 } catch { }
            $seen[$name] = $stamp; $changed = $true
        }
        $line
    }
}
# forget names whose marker is gone (a later warn of the same name must fire again)
foreach ($k in @($seen.Keys)) { if (-not $live.ContainsKey($k)) { $seen.Remove($k); $changed = $true } }
if ($changed -and -not $Peek) {
    $o = [ordered]@{}; foreach ($k in $seen.Keys) { $o[$k] = $seen[$k] }
    $tmp = "$stateF.tmp$PID"
    ($o | ConvertTo-Json) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $stateF -Force
}
exit 0
