# session-start.ps1: the fixed first step of every coordinator session (CLAUDE.md "Start here").
# Prints, compactly: the handoff marker (then archives it), testing/HANDOFF.md "Right now", each agent status
# file (C:\KenshiTestRuns\agents\<name>.status), inflight markers (+ the batch out dir a marker names: DONE/SUMMARY),
# game lock and Kenshi state.
$ws = 'C:\KenshiModding'
$runs = 'C:\KenshiTestRuns'

$mk = Join-Path $runs 'handoff.ready'
if (Test-Path -LiteralPath $mk) {
    '=== handoff.ready ==='
    Get-Content -LiteralPath $mk | Select-Object -First 6
    $done = Join-Path $runs 'handoff.done'
    New-Item -ItemType Directory -Force -Path $done | Out-Null
    Move-Item -LiteralPath $mk -Destination (Join-Path $done ("handoff-{0}.ready" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force
    Get-ChildItem -LiteralPath $done -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force
} else {
    '=== no handoff.ready (previous session ended without a context-limit handoff) ==='
}

'=== testing/HANDOFF.md: Right now ==='
$h = Get-Content -LiteralPath (Join-Path $ws 'testing\HANDOFF.md')
$i = [array]::FindIndex($h, [Predicate[string]]{ param($l) $l -like '## Right now*' })
if ($i -ge 0) {
    $j = $i + 1
    while ($j -lt $h.Count -and $h[$j] -notlike '## *') { $j++ }
    $h[$i..($j - 1)] | Select-Object -First 40
    if ($j - $i -gt 40) { "... ($($j - $i - 40) more lines: read testing/HANDOFF.md lines $($i + 41)-$j)" }
} else { $h | Select-Object -First 25 }

'=== agents (C:\KenshiTestRuns\agents) ==='
$ag = @(Get-ChildItem -LiteralPath (Join-Path $runs 'agents') -Filter '*.status' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if (-not $ag.Count) { 'none' }
foreach ($a in $ag) {
    "--- $($a.BaseName) (updated $(Get-Date $a.LastWriteTime -Format 'MM-dd HH:mm'))"
    Get-Content -LiteralPath $a.FullName | Select-Object -First 12
}

'=== rig runners (rig-runner.ps1: one daemon per rig runs the queue\<rig>\ and queue\any\ list files; ALERT on idle/stuck) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'rig-runner.ps1') -Ensure
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'rig-runner.ps1') -Status
'=== GPU telemetry (gpulog.ps1: 2 s nvidia-smi samples per rig in C:\KenshiTestRuns\gpulog\ for TDR/BSOD evidence) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'gpulog-ensure.ps1') -Rig both
Get-ChildItem 'C:\KenshiTestRuns' -Filter 'ALERT-*.txt' -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName }
'=== in flight ==='
$k = if (Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue) { 'running' } else { 'closed' }
$lock = if (Test-Path -LiteralPath (Join-Path $runs 'game.lock')) { (Get-Content -Raw -LiteralPath (Join-Path $runs 'game.lock')).Trim() } else { 'free' }
"kenshi: $k | game.lock: $lock"
# Ready queue per rig (Shay 2026-10-10): the next batch lists for each rig, queued before the current one ends
foreach ($rig in '5090', '4080', 'any', 'running') {
    $l = @(Get-ChildItem -LiteralPath (Join-Path $runs "queue\$rig") -Filter '*.list' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name)
    "queue\${rig}: $(if ($l.Count) { $l -join ', ' } else { 'empty' })"
}
foreach ($rig in '5090', '4080') {
    $q = Join-Path $runs "queue\$rig.next"
    if (Test-Path -LiteralPath $q) { "queue\$rig.next (old note file, since $(Get-Date (Get-Item -LiteralPath $q).LastWriteTime -Format 'MM-dd HH:mm')): $(((Get-Content -LiteralPath $q -TotalCount 3) -join ' / '))" }
}
$dn = @(Get-ChildItem -LiteralPath (Join-Path $runs 'queue\done'), (Join-Path $runs 'queue\failed') -Filter '*.result' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
foreach ($d in $dn) { "result $($d.Name): $(Get-Content -LiteralPath $d.FullName -TotalCount 1)" }
$inf = @(Get-ChildItem -LiteralPath (Join-Path $runs 'inflight') -File -ErrorAction SilentlyContinue)
if (-not $inf.Count) { 'inflight markers: none' }
foreach ($m in $inf) {
    $c = (Get-Content -Raw -LiteralPath $m.FullName -ErrorAction SilentlyContinue)
    $c = if ($c) { $c.Trim() } else { '' }
    "marker $($m.Name) (since $(Get-Date $m.LastWriteTime -Format 'MM-dd HH:mm')) $c"
    # A marker may hold a batch out dir (WSL /mnt/c/... or C:\...): report DONE + SUMMARY.txt
    $d = $c -replace '^/mnt/([a-z])/', '$1:/'
    if ($d -and (Test-Path -LiteralPath $d -PathType Container -ErrorAction SilentlyContinue)) {
        $s = Join-Path $d 'SUMMARY.txt'
        if (Test-Path -LiteralPath (Join-Path $d 'DONE')) { "  DONE; SUMMARY.txt:"; Get-Content -LiteralPath $s -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { "  $_" } }
        else { "  still running (no DONE): start a waker on it" }
    }
}
'=== stale test leftovers (testruns-sweep.ps1; delete or -Keep <path> "<reason>") ==='
$sw = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'testruns-sweep.ps1') 2>$null)
$sw | Select-Object -Last 1
$sw | Where-Object { $_ -like 'STALE*' } | Select-Object -First 20
'=== WSL services (cache-trim is (re)started here; STOBE server must be off for non-STOBE work) ==='
# speed-scout 2026-10-11: after the 13:31 BSOD reboot the WSL start left cache-trim off (its start line sat after
# start_env's shutdown 'read'; vmmem kept ~6 GB of page cache) and the STOBE server ON during FP work (LLM credits)
$wslq = 'bash /mnt/c/KenshiModding/tools/automation/wsl-cache-trim.sh start | tail -1; bash /mnt/c/KenshiModding/tools/automation/stobe-server.sh status 2>&1 | tail -2'
@(& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c $wslq 2>&1) | ForEach-Object { "  $_" }
$rv = Join-Path $runs 'review-verdicts.tsv'
if (Test-Path -LiteralPath $rv) { '=== newest review verdicts ==='; Get-Content -LiteralPath $rv -Tail 8 }
''
'Next: respawn every agent whose status is not DONE as a FRESH agent pointed at its status file; start a <=120 s waker if anything is in flight; continue from HANDOFF.md.'
