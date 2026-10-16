# lane-lock-lib.ps1 (PI-16, Shay 2026-10-15): lane game locks for the Stop hook (hooks\kenshi-waker-guard.ps1). Selftest: waker-lanes-selftest.ps1.
# Why: the hook only read game.lock (instance 1). With the imm26 lanes (D:\KenshiInst\<N>\RE_Kenshi, lock C:\KenshiTestRuns\game-<N>.lock) running under
# operators and the default slot idle, the Stop hook blocked with IDLE-GAME and the coordinator had to record a fake idle reason.
#   Get-LiveLaneGames [-Runs <dir>]  -> one object per LIVE lane: N, Lane ('5090-i<N>'), Lock (lock text).
#       Live = game-<N>.lock exists (N >= 2) AND a kenshi_x64 process runs from D:\KenshiInst\<N>\. A lock without that process (stale, dead
#       game) is NOT live: it never counts as running work and never hides an idle slot. Locks carry no PID, the instance directory is the identity.
#       Test seam: env KAH_GUARD_TEST_LANE_PROCS="3,4,5" replaces the process query (instance numbers that count as running).
#   Get-LaneIdleProblems $liveLanes [-Runs <dir>]  -> lane-idle.ps1 problem lines (LANE IDLE / LANE NO-OPERATOR) for the live lanes only
#       (lane-idle: operator RUNNING + status/evidence activity < 6 min). A live lane without a RUNNING operator or without recent activity is a problem.
# Everything fails open (errors => empty result).
function Get-LiveLaneGames([string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' })) {
    $alive = @{}
    try {
        if ($null -ne $env:KAH_GUARD_TEST_LANE_PROCS) {
            foreach ($t in ($env:KAH_GUARD_TEST_LANE_PROCS -split '[,\s]+')) { if ($t -match '^\d+$') { $alive[[int]$t] = $true } }
        } else {
            foreach ($p in @(Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue)) {
                if ([string]$p.Path -match '(?i)\KenshiInst\(\d+)\') { $alive[[int]$Matches[1]] = $true }
            }
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $Runs -Filter 'game-*.lock' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if ($f.Name -notmatch '^game-(\d+)\.lock$') { continue }
            $n = [int]$Matches[1]
            if ($n -lt 2 -or -not $alive.ContainsKey($n)) { continue }
            $txt = ((Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue) -as [string])
            $txt = if ($txt) { ($txt.TrimStart([char]0xFEFF).Trim() -split "\r?\n")[0].Trim() } else { '' }
            [pscustomobject]@{ N = $n; Lane = "5090-i$n"; Lock = $txt }
        }
    } catch { }
}

function Get-LaneIdleProblems($LiveLanes, [string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' })) {
    $out = @()
    try {
        $names = @($LiveLanes | ForEach-Object { $_.Lane })
        if (-not $names.Count) { return @() }
        $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'lane-idle.ps1') -Runs $Runs -NoMemory 2>$null)
        foreach ($l in $lines) {
            if (([string]$l) -match '^LANE (IDLE|NO-OPERATOR) (\S+)' -and $names -contains $Matches[2]) { $out += [string]$l }
        }
    } catch { }
    $out
}
