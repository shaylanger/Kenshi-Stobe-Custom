# kenshi-waker-guard (PowerShell): Claude Code hooks for the Kenshi modding workspace (Shay, 2026-10-08).
# Why: on 2026-10-08 the coordinator sat "waiting" for ~10 min on subagent notifications with no waker running, so
# peer messages (which only arrive between tool rounds) went unread, and the 5090 sat idle after the sword agent
# released the lock. CLAUDE.md rules alone did not prevent it; this hook enforces them.
#
#   Stop hook  (kenshi-waker-guard.ps1 stop):
#     Only acts when cwd is under C:\KenshiModding and only once per turn (stop_hook_active => allow).
#     1. Work in flight (Kenshi running, game lock held, or a marker in C:\KenshiTestRuns\inflight\ newer than 6 h)
#        and no <=120 s waker process (sleep / Start-Sleep / batch-health / rig-health) => BLOCK: start a waker.
#     2. 5090 idle (no Kenshi, lock free) and C:\KenshiTestRuns\rig5090.idle absent or older than 60 min
#        => BLOCK once: launch the next 5090 batch or write the reason into that file.
#   PreToolUse hook (kenshi-waker-guard.ps1 pre), matcher Bash|PowerShell|ScheduleWakeup:
#     Denies a top-level `sleep N` / `Start-Sleep N` / `timeout /t N` with N > 120, and ScheduleWakeup delays > 120 s.
#
# Markers: scripts/agents `touch C:\KenshiTestRuns\inflight\<name>` when they start a batch, subagent or rig job,
# delete it when done. Idle reason: `kenshi-ctl.ps1 idle "<reason>"` or write the text into rig5090.idle.
$mode = $args[0]
$raw = [Console]::In.ReadToEnd()
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
$cwd = if ($in.cwd) { [string]$in.cwd } else { $PWD.Path }
if ($cwd -notmatch '^[A-Za-z]:[\\/]KenshiModding') { exit 0 }
$runs = 'C:\KenshiTestRuns'
$MAX = 120

function Block-Stop([string]$reason) {
    @{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

if ($mode -eq 'pre') {
    $tool = [string]$in.tool_name
    $ti = $in.tool_input
    if ($tool -eq 'ScheduleWakeup') {
        if ($ti.delaySeconds -and [double]$ti.delaySeconds -gt $MAX) {
            [Console]::Error.WriteLine("kenshi-waker-guard: ScheduleWakeup delay $($ti.delaySeconds)s > $MAX s. Check in at most every $MAX s (Shay 2026-10-07).")
            exit 2
        }
        exit 0
    }
    $cmd = [string]$ti.command
    if (-not $cmd) { exit 0 }
    $hits = @()
    foreach ($m in [regex]::Matches($cmd, '(?m)(?:^|[;&|({]\s*)(?:sleep|Start-Sleep)\s+(?:-Seconds\s+|-s\s+)?(\d+)(?![\d.]*[mh])')) {
        if ([int]$m.Groups[1].Value -gt $MAX) { $hits += $m.Value.Trim() }
    }
    foreach ($m in [regex]::Matches($cmd, '(?im)timeout\s+/t\s+(\d+)')) {
        if ([int]$m.Groups[1].Value -gt $MAX) { $hits += $m.Value.Trim() }
    }
    if ($hits.Count -gt 0) {
        [Console]::Error.WriteLine("kenshi-waker-guard: '$($hits -join ', ')' waits longer than $MAX s. Wakers are at most $MAX s (sleep $MAX; bash tools/automation/batch-health.sh <out> or rig-health.sh), so peer messages and stalls are seen within 2 min (Shay 2026-10-07/08).")
        exit 2
    }
    exit 0
}

if ($mode -ne 'stop') { exit 0 }
if ($in.stop_hook_active) { exit 0 }

# --- what is in flight ---
$kenshi = $null -ne (Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue)
$lockFile = Join-Path $runs 'game.lock'
$lock = if (Test-Path -LiteralPath $lockFile) { (Get-Content -LiteralPath $lockFile -Raw -ErrorAction SilentlyContinue).Trim() -replace '\s+', ' ' } else { $null }
$markers = @()
$inflightDir = Join-Path $runs 'inflight'
if (Test-Path -LiteralPath $inflightDir) {
    $markers = @(Get-ChildItem -LiteralPath $inflightDir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) } | ForEach-Object { $_.Name })
}
$inflight = @()
if ($kenshi) { $inflight += 'Kenshi running' }
if ($lock) { $inflight += "game.lock=$lock" }
if ($markers.Count) { $inflight += "inflight markers: $($markers -join ', ')" }

# --- is a waker running? (a background sleep/Start-Sleep or a health check chained after one) ---
$me = $PID
# A waker is a sleep of >= 30 s (short polling sleeps don't count) or a health check chained after one, and it must belong
# to THIS session: another session's waker wakes that session, not this one. The session root is the nearest claude.exe
# (or node.exe) above this hook; a candidate counts only if that root is among its ancestors.
$procs = @{}
foreach ($p in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) { $procs[[int]$p.ProcessId] = $p }
$root = $null; $cur = $me; $hops = 0
while ($cur -and $procs.ContainsKey($cur) -and $hops -lt 20) {
    if ($procs[$cur].Name -match '^(claude|node)\.exe$') { $root = $cur; break }
    $cur = [int]$procs[$cur].ParentProcessId; $hops++
}
function Under-Root([int]$pid0) {
    if (-not $root) { return $true }   # cannot tell (hook run by hand): accept any waker
    $c = $pid0; $n = 0
    while ($c -and $procs.ContainsKey($c) -and $n -lt 30) {
        if ($c -eq $root) { return $true }
        $next = [int]$procs[$c].ParentProcessId
        if ($next -eq $c) { break }
        $c = $next; $n++
    }
    return $false
}
$waker = $procs.Values | Where-Object {
    if ($_.ProcessId -eq $me -or $_.Name -notmatch '^(sleep|wsl|bash|sh|powershell|pwsh|timeout)\.exe$') { return $false }
    $cl = [string]$_.CommandLine
    $isWaker = $false
    if ($cl -match 'batch-health|rig-health') { $isWaker = $true }
    else {
        # matches `sleep 120; ...` inside a bash -c string and `"C:\...\sleep.exe" 120` (Git Bash spawns sleep as its own process)
        $m = [regex]::Match($cl, '(?:^|[;&|(\s"\\/])(?:sleep|Start-Sleep)(?:\.exe")?\s+(?:-Seconds\s+|-s\s+)?(\d+)(?!\S)')
        $isWaker = $m.Success -and [int]$m.Groups[1].Value -ge 30
    }
    $isWaker -and (Under-Root ([int]$_.ProcessId))
} | Select-Object -First 1

if ($inflight.Count -gt 0 -and -not $waker) {
    Block-Stop ('kenshi-waker-guard: work is in flight (' + ($inflight -join '; ') + ') but no waker is running, so this session would go quiet and miss peer messages and stalls. Before ending the turn start a background waker (Bash run_in_background): "sleep 120; bash tools/automation/batch-health.sh <out-dir>" for a batch, else "sleep 120; bash tools/automation/rig-health.sh". Restart it every time it wakes you. If nothing is really in flight, release the lock / delete the stale marker in C:\KenshiTestRuns\inflight\ and say so.')
}

# --- 5090 idle? ---
if (-not $kenshi -and -not $lock) {
    $idleFile = Join-Path $runs 'rig5090.idle'
    $fresh = (Test-Path -LiteralPath $idleFile) -and ((Get-Item -LiteralPath $idleFile).LastWriteTime -gt (Get-Date).AddMinutes(-60))
    if (-not $fresh) {
        Block-Stop ('kenshi-waker-guard: the 5090 is idle (Kenshi closed, game lock free) and no reason is recorded. Shay''s rule: when the 5090 finishes its work, don''t stop; run the next open rows there (viewmodel/FP/STOBE/PG). Either launch the next 5090 batch now, or record a one-line reason with: & C:\KenshiModding\tools\automation\kenshi-ctl.ps1 idle "<reason>"  (e.g. "Shay playing", "nothing testable left", "waiting for build X", "chat-only session"); it is good for 60 min, "idle" shows it, "idle clear" removes it.')
    }
}

# --- 4080 idle? (Shay 2026-10-10: it sat idle a whole day while the 5090 worked; nothing looked at it) ---
$r4 = & powershell -NoProfile -File (Join-Path $PSScriptRoot '..\rig4080-state.ps1') 2>$null | Select-Object -First 1
if ($r4 -like 'IDLE kenshi=no*') {
    Block-Stop ('kenshi-waker-guard: the 4080 is idle (Kenshi closed there, no C:\KenshiTestRuns\inflight\4080-* marker, no reason recorded). Shay''s rule: use BOTH rigs, in parallel, without being told. Start a 4080 job now (PG rows, harness rows, KenshiFP combat/viewmodel rows, or split off part of the current 5090 work) via the 4080 operator agent and touch C:\KenshiTestRuns\inflight\4080-<job> while it runs; or record a one-line reason with: & C:\KenshiModding\tools\automation\kenshi-ctl.ps1 idle4080 "<reason>" (good for 60 min). State: tools\automation\rig4080-state.ps1 -Fresh.')
}
exit 0
