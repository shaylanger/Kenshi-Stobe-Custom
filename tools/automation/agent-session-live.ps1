# agent-session-live.ps1 <name>  ->  prints "LIVE <detail>" or "DEAD <reason>" (exit 0 = LIVE, 1 = DEAD, 2 = no session record)
# An independent agent session (spawn-wp-session.ps1) is LIVE when BOTH hold:
#   1. its process is alive: agents\<name>.session.json claude_pid (verified by its recorded start time, so a recycled pid does not count);
#      when the claude pid was not found at launch the launcher window's pid is used instead;
#   2. its heartbeat is fresh: agents\<name>.status was written < 10 minutes ago (agent-status.ps1 is the heartbeat) and its state is RUNNING.
# A status of DONE / FAILED / STOPPED-CONTEXT is reported as DEAD (the work ended, whatever the window still does).
# No LLM, no side effects. Used by the supervisor / next coordinator to decide: adopt (LIVE) or respawn fresh (DEAD).
# Env: KAH_RUNS_DIR (default C:\KenshiTestRuns), KAH_HEARTBEAT_MIN (default 10).
param([Parameter(Mandatory)][string]$Name)
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$limit = if ($env:KAH_HEARTBEAT_MIN) { [double]$env:KAH_HEARTBEAT_MIN } else { 10 }
$sj = Join-Path $runs "agents\$Name.session.json"
$sf = Join-Path $runs "agents\$Name.status"
if (-not (Test-Path -LiteralPath $sj)) { "DEAD no session record ($sj)"; exit 2 }
try { $s = Get-Content -LiteralPath $sj -Raw | ConvertFrom-Json } catch { "DEAD unreadable session record ($($_.Exception.Message))"; exit 2 }

function Test-Pid([int]$procId, [string]$startIso) {
    if ($procId -le 0) { return $false }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($startIso) {
        try {
            $rec = [datetime]::Parse($startIso).ToUniversalTime()
            if ([math]::Abs(($p.StartTime.ToUniversalTime() - $rec).TotalSeconds) -gt 3) { return $false }   # pid recycled by another process
        } catch { }
    }
    return $true
}
$cp = if ($s.claude_pid) { [int]$s.claude_pid } else { 0 }
$lp = if ($s.launcher_pid) { [int]$s.launcher_pid } else { 0 }
$alive = $false; $which = ''
if ($cp -gt 0) { $alive = Test-Pid $cp "$($s.claude_start)"; $which = "claude pid $cp" }
else { $alive = Test-Pid $lp "$($s.launcher_start)"; $which = "launcher pid $lp (claude pid unknown)" }
if (-not $alive) { "DEAD process gone ($which)"; exit 1 }

if (-not (Test-Path -LiteralPath $sf)) { "DEAD no status file for a running process ($which)"; exit 1 }
$first = (Get-Content -LiteralPath $sf -TotalCount 1) -split '\|' | ForEach-Object { $_.Trim() }
$state = if ($first.Count -ge 2) { $first[1] } else { '?' }
$age = ((Get-Date) - (Get-Item -LiteralPath $sf).LastWriteTime).TotalMinutes
if ($state -ne 'RUNNING') { "DEAD status is $state ($which still alive)"; exit 1 }
if ($age -ge $limit) { "DEAD heartbeat stale $([int]$age) min >= $limit ($which alive)"; exit 1 }
"LIVE $which, heartbeat $([math]::Round($age,1)) min ago"
exit 0
