# lane-idle.ps1: per-lane "is it really testing" check for the imm26 lanes (Shay 2026-10-15: "do you check that every lane is currently testing and active and not idle?").
# A lane is ACTIVE when its operator agent has a RUNNING status AND the newest of {operator status file, files under the lane's evidence dirs}
# is younger than -Max minutes (default 6). Prints one line per problem lane, each repeated at most every -Repeat minutes:
#   LANE IDLE <lane> <min>m operator=<name> ...      (operator RUNNING but no status/evidence activity for > Max)
#   LANE NO-OPERATOR <lane> ...                      (no RUNNING operator for the lane)
#   (LANE STALLED is NOT raised for: an operator with agents\<op>.abandoned, a lane listed in <runs>\lanes.held, a 5090 lane with no live game/lock.)
#   LANE STALLED <lane> <min>m ... (escalation, token-free: operator RUNNING, status file AND evidence both older than -StallMin (default 12, env KAH_LANE_STALL_MIN);
#                                    names the operator, minutes, last evidence file+time and the exact action. The text also contains "LANE IDLE" so the
#                                    unchanged waker scripts (event-wait.sh / event-stream.sh, which match that phrase) wake on it. Suppressed while
#                                    <runs>\lane-longwait\<lane>.txt is < 60 min old (a declared long wait, e.g. a save/load cycle). alert-lib.ps1 turns it into the hard
#                                    alert lane-stalled-<lane> that alert-ack.ps1 only closes with proof (stopped / respawned / fresh evidence path).)
# Else "LANES ACTIVE n=5". Exit 0 OK, 1 problem. -Runs overrides C:\KenshiTestRuns (selftest). Memory: <runs>\lane-idle.mem.json.
param([int]$Max = 6, [int]$Repeat = 10, [int]$StallMin = $(if ($env:KAH_LANE_STALL_MIN) { [int]$env:KAH_LANE_STALL_MIN } else { 12 }), [string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }), [switch]$NoMemory)
$lanes = [ordered]@{
    '5090-i3' = @{ ops = @('imm26-5090-i3op3');                    dirs = @('imm26-5090-i3', 'imm26-5090-i3op3') }
    '5090-i4' = @{ ops = @('imm26-5090-i4op3');                    dirs = @('imm26-5090-i4', 'imm26-5090-i4op3') }
    '5090-i5' = @{ ops = @('imm26-5090-ctxop322', 'imm26-5090-ctxop32', 'imm26-5090-ctxop3'); dirs = @('imm26-5090-i5', 'imm26-5090-ctxop3', 'imm26-5090-ctxop32') }
    '4080-i3' = @{ ops = @('imm26-4080-op2g');                     dirs = @('imm26-4080') }
    '4080-i4' = @{ ops = @('imm26-4080-i4op5');                    dirs = @('imm26-4080-i4') }
}
# optional override: <runs>\lane-owners.json {"5090-i3":{"ops":[...],"dirs":[...]}, ...} (lets the coordinator re-map when an operator is respawned)
$ov = Join-Path $Runs 'lane-owners.json'
if (Test-Path -LiteralPath $ov) { try { $j = Get-Content -LiteralPath $ov -Raw | ConvertFrom-Json; foreach ($p in $j.psobject.Properties) { $lanes[$p.Name] = @{ ops = @($p.Value.ops); dirs = @($p.Value.dirs) } } } catch { } }
$now = Get-Date
# PI-47 (Shay 2026-10-16): the LANE NO-OPERATOR line carries the exact, ready-to-run successor spawn text (one line, so the unchanged waker grep keeps it):
# next operator name (trailing number + 1, or +2 after a letter suffix; never an existing status name), predecessor = newest-status operator of the lane + its state.
function Get-SuccessorText([string]$lane, $cfg) {
    $pred = $null; $predT = $null; $predState = 'none'
    foreach ($op in $cfg.ops) {
        $sf = Join-Path $Runs "agents\$op.status"
        if (-not (Test-Path -LiteralPath $sf)) { continue }
        $t = (Get-Item -LiteralPath $sf).LastWriteTime
        if (-not $predT -or $t -gt $predT) { $predT = $t; $pred = $op; $first = ((Get-Content -LiteralPath $sf -TotalCount 1) -as [string]) -replace '^\uFEFF', ''; $predState = if ($first -match '\|\s*([A-Z-]+)\s*\|') { $Matches[1] } else { '?' } }
    }
    $base = if ($pred) { $pred } else { $cfg.ops[0] }
    $next = if ($base -match '^(.*?)(\d+)$') { $Matches[1] + ([int]$Matches[2] + 1) } else { $base + '2' }
    while (Test-Path -LiteralPath (Join-Path $Runs "agents\$next.status")) { $next = if ($next -match '^(.*?)(\d+)$') { $Matches[1] + ([int]$Matches[2] + 1) } else { $next + '2' } }
    $br = "C:\KenshiTestRuns\agents\$next.brief.md"
    $pa = if ($pred) { " -Predecessor $pred" } else { '' }
    $ps = if ($pred) { "predecessor $pred=$predState" } else { 'no predecessor status' }
    $rest = if ($pred) { " (if the lane should rest instead: agent-abandon.ps1 $pred `"parked: <why>`" holds it 2 h)" } else { '' }
    "SUCCESSOR ($ps): 1) powershell -NoProfile -File C:\KenshiModding\tools\automation\lane-brief.ps1 $lane -Out $br -Name $next$pa  2) Agent prompt: `"[case:generate] You are $next, lane $lane. Read $br, then the handoff it names, and start the next row. Hand back AT MOST 8 lines (verdict, files/commits, SHA/paths, one next action, any DECISION/QUESTION for Shay); full report via save-report.ps1.`"$rest"
}
# held lanes: <runs>\lanes.held, one lane per line, '#' comments (e.g. lanes Shay holds); no LANE STALLED for them
# PI-50 (Shay 2026-10-16): lines written by agent-abandon.ps1 "parked: ..." carry "# auto-hold from=.. until=.. by=.. reason=.."; they expire after 2 h
# (an expired hold no longer suppresses) and are released when a RUNNING operator status for the lane newer than from= appears (lane-hold-lib.ps1).
$held = @(); $heldF = Join-Path $Runs 'lanes.held'
if (Test-Path -LiteralPath $heldF) {
    . (Join-Path $PSScriptRoot 'lane-hold-lib.ps1')
    try { $null = Release-HoldsForNewOperator $Runs $lanes } catch { }
    $held = @(Get-ActiveHolds $Runs)
}
# live 5090 lane games (game-N.lock + kenshi_x64 from D:\KenshiInst\N; lane-lock-lib.ps1); 4080 lanes cannot be checked locally (never excluded by this)
$liveN = @(); try { . (Join-Path $PSScriptRoot 'lane-lock-lib.ps1'); $liveN = @(Get-LiveLaneGames $Runs | ForEach-Object { [int]$_.N }) } catch { $liveN = @(2..9) }
$memF = Join-Path $Runs 'lane-idle.mem.json'
$mem = @{}
if (-not $NoMemory -and (Test-Path -LiteralPath $memF)) { try { (Get-Content -LiteralPath $memF -Raw | ConvertFrom-Json).psobject.Properties | ForEach-Object { $mem[$_.Name] = [datetime]$_.Value } } catch { } }
$out = @(); $n = 0
foreach ($l in $lanes.Keys) {
    $n++
    $cfg = $lanes[$l]
    $runOp = $null; $newest = $null; $what = ''; $stT = $null; $evT = $null; $evF = ''
    foreach ($op in $cfg.ops) {
        $sf = Join-Path $Runs "agents\$op.status"
        if (-not (Test-Path -LiteralPath $sf)) { continue }
        $first = ((Get-Content -LiteralPath $sf -TotalCount 1) -as [string]) -replace '^\uFEFF', ''
        if ($first -notmatch '\|\s*RUNNING\s*\|') { continue }
        $runOp = $op
        $t = (Get-Item -LiteralPath $sf).LastWriteTime
        if (-not $stT -or $t -gt $stT) { $stT = $t }
        if (-not $newest -or $t -gt $newest) { $newest = $t; $what = 'status' }
    }
    if (-not $runOp) {
        if ($held -contains $l) { continue }   # held / retired lanes (lanes.held) never raise LANE NO-OPERATOR
        $key = "noop:$l"
        if (-not $mem.ContainsKey($key) -or ($now - $mem[$key]).TotalMinutes -ge $Repeat) { $mem[$key] = $now; $out += "LANE NO-OPERATOR $l : no RUNNING operator among $($cfg.ops -join ',') -> spawn/respawn one from the handoff. $(Get-SuccessorText $l $cfg)" }
        continue
    }
    foreach ($d in $cfg.dirs) {
        $p = Join-Path $Runs $d
        if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
        $f = Get-ChildItem -LiteralPath $p -Recurse -File -Depth 4 -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f -and (-not $evT -or $f.LastWriteTime -gt $evT)) { $evT = $f.LastWriteTime; $evF = $f.FullName }
        if ($f -and (-not $newest -or $f.LastWriteTime -gt $newest)) { $newest = $f.LastWriteTime; $what = "evidence $d\$($f.Name)" }
    }
    $age = [math]::Round(($now - $newest).TotalMinutes, 1)
    if ($age -gt $Max -and ($held -notcontains $l)) {   # held lanes (lanes.held) never raise LANE IDLE either
        $key = "idle:$l"
        if (-not $mem.ContainsKey($key) -or ($now - $mem[$key]).TotalMinutes -ge $Repeat) { $mem[$key] = $now; $out += "LANE IDLE $l ${age}m operator=$runOp (newest activity: $what) -> ask the operator what it is doing; if it is stuck, fix the root or respawn it" }
    } else { $mem.Remove("idle:$l"); $mem.Remove("noop:$l") }
    # escalation: operator status AND evidence both silent > StallMin (and no declared long wait) -> LANE STALLED (not rate-limited by Repeat when -NoMemory)
    $lw = Join-Path $Runs "lane-longwait\$l.txt"
    $declared = (Test-Path -LiteralPath $lw) -and (($now - (Get-Item -LiteralPath $lw).LastWriteTime).TotalMinutes -lt 60)
    # exclusions (coordinator 2026-10-15): abandoned operator (agents\<op>.abandoned), held lane (<runs>\lanes.held), 5090 lane without a live game
    if (-not $declared) {
        if (Test-Path -LiteralPath (Join-Path $Runs "agents\$runOp.abandoned")) { $declared = $true }
        elseif ($held -contains $l) { $declared = $true }
        elseif ($l -match '^5090-i(\d+)$' -and $liveN -notcontains [int]$Matches[1]) { $declared = $true }
    }
    $stAge = [math]::Round(($now - $stT).TotalMinutes, 1)
    $evAge = if ($evT) { [math]::Round(($now - $evT).TotalMinutes, 1) } else { 9999 }
    if ($stAge -gt $StallMin -and $evAge -gt $StallMin -and -not $declared) {
        $key = "stalled:$l"
        if (-not $mem.ContainsKey($key) -or ($now - $mem[$key]).TotalMinutes -ge $Repeat) {
            $mem[$key] = $now
            $last = if ($evT) { "$evF at $($evT.ToString('HH:mm:ss'))" } else { 'none' }
            $out += "LANE STALLED $l ${age}m (escalated from LANE IDLE) operator=$runOp status silent ${stAge}m, last evidence: $last -> 1) SendMessage/ping the operator (in-session agents: you cannot reach tail-owned ones) 2) if no status update within 3 min: TaskStop it, mark its status STOPPED-CONTEXT (agent-status.ps1), spawn the successor via lane-brief.ps1 $l -Out <file> -Name <opN+1> -Predecessor $runOp. A plain ack is refused: ack needs 'stopped'/'respawned' or an evidence path newer than 5 min."
        }
    } else { $mem.Remove("stalled:$l") }
}
if (-not $NoMemory) { try { $o = @{}; foreach ($k in $mem.Keys) { $o[$k] = $mem[$k].ToString('o') }; ($o | ConvertTo-Json) | Set-Content -LiteralPath $memF -Encoding UTF8 } catch { } }
if ($out.Count -gt 0) { $out; exit 1 }
"LANES ACTIVE n=$n"; exit 0
