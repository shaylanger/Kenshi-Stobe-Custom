# lane-idle.ps1: per-lane "is it really testing" check for the imm26 lanes (Shay 2026-10-15: "do you check that every lane is currently testing and active and not idle?").
# A lane is ACTIVE when its operator agent has a RUNNING status AND the newest of {operator status file, files under the lane's evidence dirs}
# is younger than -Max minutes (default 6). Prints one line per problem lane, each repeated at most every -Repeat minutes:
#   LANE IDLE <lane> <min>m operator=<name> ...      (operator RUNNING but no status/evidence activity for > Max)
#   LANE NO-OPERATOR <lane> ...                      (no RUNNING operator for the lane)
# Else "LANES ACTIVE n=5". Exit 0 OK, 1 problem. -Runs overrides C:\KenshiTestRuns (selftest). Memory: <runs>\lane-idle.mem.json.
param([int]$Max = 6, [int]$Repeat = 10, [string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }), [switch]$NoMemory)
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
$memF = Join-Path $Runs 'lane-idle.mem.json'
$mem = @{}
if (-not $NoMemory -and (Test-Path -LiteralPath $memF)) { try { (Get-Content -LiteralPath $memF -Raw | ConvertFrom-Json).psobject.Properties | ForEach-Object { $mem[$_.Name] = [datetime]$_.Value } } catch { } }
$out = @(); $n = 0
foreach ($l in $lanes.Keys) {
    $n++
    $cfg = $lanes[$l]
    $runOp = $null; $newest = $null; $what = ''
    foreach ($op in $cfg.ops) {
        $sf = Join-Path $Runs "agents\$op.status"
        if (-not (Test-Path -LiteralPath $sf)) { continue }
        $first = ((Get-Content -LiteralPath $sf -TotalCount 1) -as [string]) -replace '^\uFEFF', ''
        if ($first -notmatch '\|\s*RUNNING\s*\|') { continue }
        $runOp = $op
        $t = (Get-Item -LiteralPath $sf).LastWriteTime
        if (-not $newest -or $t -gt $newest) { $newest = $t; $what = 'status' }
    }
    if (-not $runOp) {
        $key = "noop:$l"
        if (-not $mem.ContainsKey($key) -or ($now - $mem[$key]).TotalMinutes -ge $Repeat) { $mem[$key] = $now; $out += "LANE NO-OPERATOR $l : no RUNNING operator among $($cfg.ops -join ',') -> spawn/respawn one from the handoff" }
        continue
    }
    foreach ($d in $cfg.dirs) {
        $p = Join-Path $Runs $d
        if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
        $f = Get-ChildItem -LiteralPath $p -Recurse -File -Depth 4 -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f -and (-not $newest -or $f.LastWriteTime -gt $newest)) { $newest = $f.LastWriteTime; $what = "evidence $d\$($f.Name)" }
    }
    $age = [math]::Round(($now - $newest).TotalMinutes, 1)
    if ($age -gt $Max) {
        $key = "idle:$l"
        if (-not $mem.ContainsKey($key) -or ($now - $mem[$key]).TotalMinutes -ge $Repeat) { $mem[$key] = $now; $out += "LANE IDLE $l ${age}m operator=$runOp (newest activity: $what) -> ask the operator what it is doing; if it is stuck, fix the root or respawn it" }
    } else { $mem.Remove("idle:$l"); $mem.Remove("noop:$l") }
}
if (-not $NoMemory) { try { $o = @{}; foreach ($k in $mem.Keys) { $o[$k] = $mem[$k].ToString('o') }; ($o | ConvertTo-Json) | Set-Content -LiteralPath $memF -Encoding UTF8 } catch { } }
if ($out.Count -gt 0) { $out; exit 1 }
"LANES ACTIVE n=$n"; exit 0
