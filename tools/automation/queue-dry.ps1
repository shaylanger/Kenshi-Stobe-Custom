<#
queue-dry.ps1 (dot-sourced by rig-runner.ps1, rig-lane2.ps1, rig-lane2-4080.ps1; speed-scout r8, coordinator m105 18:50:
lanes 5090b/5090c sat "idle: no work" for 4+ min before anyone queued work). Every runner lane that has nothing to take
calls DryNote <lane> <why> every idle tick:
  - runner\<lane>.dry = "<time> <why>" (the lane's idle reason, rewritten every tick; DryClear removes it when work starts)
  - the coordinator gets ONE line in C:\KenshiTestRuns\agents\coordinator.note-from-runner at once: the first idle tick of
    a lane's dry spell writes it unless another lane wrote one < 2 min ago; while the queues stay dry a lane repeats it every
    10 min. The line has the queue counts and every idle lane's reason, so real work gets queued in seconds.
  powershell -c ". C:\KenshiModding	oolsutomation\queue-dry.ps1; QueueDrySelfTest"   note once per spell, 2-min shared throttle, 10-min repeat, clear (temp dir, no side effects)
#>
function QueueCounts([string]$qd) {
    (@('5090', '4080', 'any', '5090b', '5090c', '4080b', 'filler') | ForEach-Object { "$_=$(@(Get-ChildItem (Join-Path $qd $_) -Filter *.list -File -ErrorAction SilentlyContinue).Count)" }) -join ' '
}
$script:dryNoted = $false
function DryNote([string]$lane, [string]$why, [string]$rd, [string]$noteF, [string]$qd, [datetime]$now = (Get-Date)) {   # $true = a note was written
    Set-Content (Join-Path $rd "$lane.dry") "$($now.ToString('s')) $why" -ErrorAction SilentlyContinue
    $st = Join-Path $rd 'dry-note.stamp'
    $age = if (Test-Path $st) { ($now - [datetime]((Get-Content $st -TotalCount 1).Trim())).TotalMinutes } else { 1e9 }
    $send = ((-not $script:dryNoted) -and $age -ge 2) -or $age -ge 10
    $script:dryNoted = $true
    if (-not $send) { return $false }
    Set-Content $st $now.ToString('s')
    $idle = @(Get-ChildItem $rd -Filter '*.dry' -File -ErrorAction SilentlyContinue | ForEach-Object { "$($_.BaseName): $((Get-Content $_.FullName -TotalCount 1) -replace '^\S+ ', '')" })
    Add-Content $noteF "$($now.ToString('MM-dd HH:mm')) runner ${lane}: QUEUES DRY, queue real work now ($(QueueCounts $qd)). Idle lanes: $($idle -join ' | ')" -ErrorAction SilentlyContinue
    $true
}
function DryClear([string]$lane, [string]$rd) { Remove-Item (Join-Path $rd "$lane.dry") -ErrorAction SilentlyContinue; $script:dryNoted = $false }

function QueueDrySelfTest {
    $bad = 0; $n = 0; $t = Join-Path $env:TEMP "queue-dry-st-$PID"; $rd = Join-Path $t 'runner'; $qd = Join-Path $t 'queue'; $nf = Join-Path $t 'note'
    New-Item -ItemType Directory -Force $rd, "$qd\5090", "$qd\filler" | Out-Null; Set-Content "$qd\5090\1-x.list" 'x'
    function Lines { @(Get-Content $nf -ErrorAction SilentlyContinue).Count }
    $t0 = Get-Date '2026-10-11T19:00:00'
    $c = @(
        @('first idle tick of lane B writes a note', '5090b', 0, $false, 1),
        @('lane B next tick: no repeat', '5090b', 0.5, $false, 1),
        @('lane C idle 1 min later: shared 2-min throttle', '5090c', 1, $false, 1),
        @('lane B still dry 11 min later: repeat', '5090b', 11, $false, 2),
        @('lane B took work, dry again 13 min: new spell but < 2 min since last note', '5090b', 12, $true, 2),
        @('lane B dry spell 15 min: note', '5090b', 15, $true, 3)
    )
    $script:spell = @{}
    foreach ($x in $c) {
        $n++; if ($x[3]) { DryClear $x[1] $rd }
        $script:dryNoted = [bool]$script:spell[$x[1]] -and -not $x[3]; $null = DryNote $x[1] 'idle: test' $rd $nf $qd ($t0.AddMinutes($x[2])); $script:spell[$x[1]] = $true
        $ok = (Lines) -eq $x[4]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) $($x[0]): note lines=$(Lines) want $($x[4])"
    }
    $n++; $l = @(Get-Content $nf)[0]; $ok = $l -match 'QUEUES DRY' -and $l -match '5090=1 ' -and $l -match '5090b: idle: test'; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) note text: $l"
    $n++; DryClear '5090b' $rd; $ok = -not (Test-Path "$rd\5090b.dry") -and (Test-Path "$rd\5090c.dry"); if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) DryClear removes only its lane's .dry"
    Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue
    "QUEUE-DRY-SELFTEST $(if ($bad) { "FAIL $bad" } else { 'PASS' }) $n cases"
}
