<#
paired-runner-supervisor.ps1

Paired, read-only monitor for the primary 5090 and 4080 rig runners. The session-start path
ensures one persistent instance. It samples both rig runner heartbeats and the exact named
row progress fields at 45 s by default (clamped to <=60 s). A game PID and an unchanged row
label never count as progress.

Recovery is OFF unless tools/automation/paired-runner-supervisor.reviewed.sha256 contains
the SHA256 of this exact script. This is a post-review pin: any edit invalidates it. The
monitor never kills a game. For a reviewed stale runner it uses rig-runner.ps1 -Stop/-Start
for that rig, and for a dead runner it uses -Ensure -Rig <rig>, only after proving no batch
owner markers are present. Ambiguous state fails closed.

  paired-runner-supervisor.ps1 -Ensure       ensure one hidden persistent monitor
  paired-runner-supervisor.ps1 -Once         one read-only sample
  paired-runner-supervisor.ps1 -SelfTest     synthetic tests; no rig/process actions
#>
param(
    [switch]$Ensure,
    [switch]$Loop,
    [switch]$Once,
    [switch]$SelfTest,
    [string]$Root = 'C:\KenshiTestRuns',
    [string]$ReviewPin = 'C:\KenshiModding\tools\automation\paired-runner-supervisor.reviewed.sha256',
    [ValidateRange(1, 600)][int]$IntervalSec = 45,
    [ValidateRange(60, 3600)][int]$StaleRunnerSec = 180
)

$ErrorActionPreference = 'Stop'
$script:SupervisorName = 'paired-runner-supervisor.ps1'

function Assert([bool]$ok, [string]$name) {
    if (-not $ok) { throw "FAIL $name" }
    "PASS $name"
}

function Normalize-Path([string]$path) {
    try { [IO.Path]::GetFullPath($path).TrimEnd('\').ToLowerInvariant() } catch { $path.TrimEnd('\').ToLowerInvariant() }
}

function Get-ScriptHash([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-ReviewPin([string]$pinPath, [string]$scriptHash) {
    if (-not $scriptHash -or -not (Test-Path -LiteralPath $pinPath -PathType Leaf)) { return $false }
    $pin = (Get-Content -LiteralPath $pinPath -Raw -ErrorAction SilentlyContinue).Trim().ToUpperInvariant()
    return $pin -match '^[A-F0-9]{64}$' -and $pin -ceq $scriptHash.ToUpperInvariant()
}

function Get-ProcessInventory {
    # One read-only CIM snapshot is shared by both rigs each cycle. A failed query is UNKNOWN,
    # never proof that a PID is dead.
    try { @(Get-CimInstance Win32_Process -ErrorAction Stop) } catch { $null }
}

function Find-RunnerMatches([object[]]$inventory, [string]$scriptPath, [string]$rig) {
    if ($null -eq $inventory) { return $null }
    $scriptNeedle = [regex]::Escape((Normalize-Path $scriptPath))
    @($inventory | Where-Object {
        ([string]$_.Name -match '^(?i:powershell|pwsh)\.exe$') -and
        (($cmd = ([string]$_.CommandLine).ToLowerInvariant() -replace '/', '\')) -and
        $cmd -match $scriptNeedle -and $cmd -match "(?i)(?:^|\s)-rig\s+$([regex]::Escape($rig.ToLowerInvariant()))(?:\s|$)" -and
        $cmd -notmatch '(?i)(?:^|\s)-ensure(?:\s|$)'
    } | ForEach-Object { [pscustomobject]@{ Id = [int]$_.ProcessId; CommandLine = [string]$_.CommandLine; CreationDate = $_.CreationDate } })
}

function Get-ProcessAgeSec([object]$processRecord) {
    if (-not $processRecord -or -not $processRecord.CreationDate) { return $null }
    try {
        $started = if ($processRecord.CreationDate -is [datetime]) { $processRecord.CreationDate } else { [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$processRecord.CreationDate) }
        [Math]::Max(0, [int]((Get-Date) - $started).TotalSeconds)
    } catch { $null }
}

function Find-ProcessById([object[]]$inventory, [int]$id) {
    if ($null -eq $inventory) { return $null }
    @($inventory | Where-Object { [int]$_.ProcessId -eq $id } | Select-Object -First 1)[0]
}

function Get-StateRow([string]$stateText) {
    # rig-runner's state line includes the exact named row, its probe age, and game time.
    $m = [regex]::Match($stateText, 'running\s+(?<list>\S+).*?\brow=(?<row>\S+)\s+age=(?<age>\d+)s\s+gh=(?<gh>[0-9.]+|-)')
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        List = $m.Groups['list'].Value
        Row = $m.Groups['row'].Value
        OutputAgeSec = [int]$m.Groups['age'].Value
        GameHours = if ($m.Groups['gh'].Value -eq '-') { $null } else { [double]$m.Groups['gh'].Value }
    }
}

function Get-RowEvidence([string]$outDir, [string]$row) {
    $e = [ordered]@{ ResultCursor = ''; RowFile = '' }
    if (-not $outDir -or -not $row) { return [pscustomobject]$e }
    $summary = Join-Path $outDir 'SUMMARY.txt'
    if (Test-Path -LiteralPath $summary -PathType Leaf) {
        try {
            $matches = @(Get-Content -LiteralPath $summary -ErrorAction Stop | Where-Object { $_ -match "^RESULT\s+$([regex]::Escape($row))\s+(PASS|PASS-REC|FAIL)\b" })
            if ($matches.Count) { $e.ResultCursor = $matches[-1] }
        } catch { }
    }
    $rf = Join-Path $outDir "$row.txt"
    if (Test-Path -LiteralPath $rf -PathType Leaf) {
        try { $f = Get-Item -LiteralPath $rf; $e.RowFile = "$($f.Length):$($f.LastWriteTimeUtc.Ticks)" } catch { }
    }
    [pscustomobject]$e
}

function Get-Progress([object]$previous, [object]$current) {
    $sources = @()
    if (-not $current -or -not $current.Row) { return [pscustomobject]@{ Progress = $false; Sources = @(); Baseline = [bool](-not $previous) } }
    if (-not $previous -or $previous.Row -ne $current.Row -or $previous.List -ne $current.List) {
        return [pscustomobject]@{ Progress = [bool]$previous; Sources = $(if ($previous) { @('named-row-transition') } else { @() }); Baseline = [bool](-not $previous) }
    }
    if ($null -ne $current.GameHours -and $null -ne $previous.GameHours -and $current.GameHours -gt $previous.GameHours) { $sources += 'game-hours-advanced' }
    if ($null -ne $current.OutputAgeSec -and $null -ne $previous.OutputAgeSec -and $current.OutputAgeSec -lt $previous.OutputAgeSec) { $sources += 'active-batch-output-updated' }
    if ($current.ResultCursor -and $current.ResultCursor -ne $previous.ResultCursor) { $sources += 'named-row-result' }
    if ($current.RowFile -and $current.RowFile -ne $previous.RowFile) { $sources += 'named-row-file-updated' }
    [pscustomobject]@{ Progress = [bool]$sources.Count; Sources = $sources; Baseline = $false }
}

function Get-OwnerProof([string]$root, [string]$rig, [string]$stateText, [string[]]$curLines) {
    $rd = Join-Path $root 'runner'; $qd = Join-Path $root 'queue'; $inf = Join-Path $root 'inflight'
    $reasons = @()
    foreach ($dir in @($rd, (Join-Path $qd 'running'), $inf)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { $reasons += "owner directory missing ($dir)"; continue }
        try { $null = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) }
        catch { $reasons += "owner directory unreadable ($dir)" }
    }
    $cur = Join-Path $rd "$rig.cur"
    if (Test-Path -LiteralPath $cur -PathType Leaf) { $reasons += "$rig.cur present" }
    $tails = @(Get-ChildItem -LiteralPath $rd -Filter "$rig.tail.*" -File -ErrorAction SilentlyContinue)
    if ($tails.Count) { $reasons += "$rig.tail present" }
    $running = @(Get-ChildItem -LiteralPath (Join-Path $qd 'running') -Filter "${rig}__*" -File -ErrorAction SilentlyContinue)
    if ($running.Count) { $reasons += 'queue/running entry present' }
    $marker = if ($rig -eq '5090') { Join-Path $inf 'runner-5090' } else { Join-Path $inf '4080-runner' }
    if (Test-Path -LiteralPath $marker -PathType Leaf) { $reasons += "inflight marker present ($([IO.Path]::GetFileName($marker)))" }
    if ($rig -eq '5090' -and (Test-Path -LiteralPath (Join-Path $root 'game.lock') -PathType Leaf)) { $reasons += 'game.lock present' }
    if ($stateText -match '^\d\d:\d\d\s+(running|starting)\b' -and -not (Test-Path -LiteralPath $cur -PathType Leaf)) { $reasons += 'state says running/starting but cur is absent' }
    if ($reasons.Count) { return [pscustomobject]@{ Clear = $false; Detail = $reasons -join '; '; Ambiguous = $true } }
    [pscustomobject]@{ Clear = $true; Detail = 'no current/tail/running/inflight/lock owner markers'; Ambiguous = $false }
}

function Get-RigSnapshot([string]$root, [string]$rig, [string]$runnerScript, [object[]]$inventory) {
    $rd = Join-Path $root 'runner'; $pidPath = Join-Path $rd "$rig.pid"; $statePath = Join-Path $rd "$rig.state"; $curPath = Join-Path $rd "$rig.cur"
    $pidText = if (Test-Path -LiteralPath $pidPath -PathType Leaf) { (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    $stateText = if (Test-Path -LiteralPath $statePath -PathType Leaf) { (Get-Content -LiteralPath $statePath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    $stateItem = Get-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
    $hbAge = if ($stateItem) { [Math]::Max(0, [int]((Get-Date) - $stateItem.LastWriteTime).TotalSeconds) } else { $null }
    $curLines = if (Test-Path -LiteralPath $curPath -PathType Leaf) { @(Get-Content -LiteralPath $curPath -ErrorAction SilentlyContinue) } else { @() }
    $owner = Get-OwnerProof $root $rig $stateText $curLines
    $stopped = Test-Path -LiteralPath (Join-Path $rd "$rig.stopped") -PathType Leaf
    $processStatus = 'unknown'; $processId = $null; $processDetail = ''; $processAgeSec = $null
    $runnerMatches = if ($null -eq $inventory) { $null } else { @(Find-RunnerMatches -inventory $inventory -scriptPath $runnerScript -rig $rig) }
    $matchCount = if ($null -eq $runnerMatches) { -1 } else { @($runnerMatches).Count }
    if ($null -eq $runnerMatches) { $processDetail = 'runner process query unavailable' }
    elseif ($matchCount -gt 1) { $processStatus = 'ambiguous'; $processDetail = "multiple runner command matches ($matchCount)" }
    elseif ($matchCount -eq 1) {
        $processStatus = 'alive'; $processId = [int]$runnerMatches[0].Id; $processDetail = 'runner command verified'
        $processAgeSec = Get-ProcessAgeSec $runnerMatches[0]
        if ($pidText -and $pidText -match '^\d+$' -and [int]$pidText -ne $processId) { $processStatus = 'ambiguous'; $processDetail = "pid file $pidText disagrees with verified runner $processId" }
        elseif (-not $pidText) { $processStatus = 'ambiguous'; $processDetail = 'runner command exists but pid file is absent' }
    }
    elseif ($pidText -match '^\d+$') {
        $p = Find-ProcessById $inventory ([int]$pidText)
        if ($null -eq $p -and $null -ne $inventory) { $processStatus = 'dead'; $processId = [int]$pidText; $processDetail = 'pid file process is absent' }
        elseif ($null -eq $p) { $processStatus = 'unknown'; $processId = [int]$pidText; $processDetail = 'pid query unavailable' }
        else { $processStatus = 'ambiguous'; $processId = [int]$pidText; $processDetail = 'pid is live but command line does not identify this runner' }
    } elseif ($pidText) { $processStatus = 'ambiguous'; $processDetail = 'runner pid file is malformed' }
    elseif ($matchCount -eq 0) { $processStatus = 'dead'; $processDetail = 'no runner pid or command match' }
    $row = Get-StateRow $stateText
    $outDir = if ($curLines.Count -ge 2) { $curLines[1] } else { '' }
    $evidence = if ($row) { Get-RowEvidence $outDir $row.Row } else { [pscustomobject]@{ ResultCursor = ''; RowFile = '' } }
    if ($row) { $row | Add-Member -NotePropertyName ResultCursor -NotePropertyValue $evidence.ResultCursor -Force; $row | Add-Member -NotePropertyName RowFile -NotePropertyValue $evidence.RowFile -Force }
    [pscustomobject]@{
        Rig = $rig; Pid = $processId; PidFile = $pidText; ProcessStatus = $processStatus; ProcessDetail = $processDetail; ProcessAgeSec = $processAgeSec
        StateText = $stateText; HeartbeatAgeSec = $hbAge; Row = $row; Owner = $owner; Stopped = $stopped; OutDir = $outDir
    }
}

function Get-RunnerAction([object]$snapshot, [int]$staleSec, [bool]$reviewed, [bool]$hasBaseline) {
    if ($snapshot.Stopped) { return [pscustomobject]@{ Action = 'none'; Reason = 'stopped flag is set' } }
    if ($snapshot.ProcessStatus -in @('ambiguous', 'unknown')) { return [pscustomobject]@{ Action = 'none'; Reason = $snapshot.ProcessDetail } }
    if (-not $snapshot.Owner.Clear) { return [pscustomobject]@{ Action = 'none'; Reason = "owner/batch is not proven clear: $($snapshot.Owner.Detail)" } }
    if ($snapshot.ProcessStatus -eq 'alive') {
        if ($null -ne $snapshot.ProcessAgeSec -and $snapshot.ProcessAgeSec -lt $staleSec) { return [pscustomobject]@{ Action = 'none'; Reason = 'verified runner is in startup grace' } }
        if ($null -ne $snapshot.HeartbeatAgeSec -and $snapshot.HeartbeatAgeSec -lt $staleSec) { return [pscustomobject]@{ Action = 'none'; Reason = 'runner heartbeat is fresh' } }
        $age = if ($null -ne $snapshot.HeartbeatAgeSec) { [int]$snapshot.HeartbeatAgeSec } else { $snapshot.ProcessAgeSec }
        if ($null -eq $age) { return [pscustomobject]@{ Action = 'none'; Reason = 'runner heartbeat and process age are unavailable' } }
        if (-not $reviewed) { return [pscustomobject]@{ Action = 'recovery-disabled'; Reason = "live runner heartbeat stale ($($age)s); exact-hash review pin absent/mismatched" } }
        return [pscustomobject]@{ Action = 'restart-runner'; Reason = "verified live runner heartbeat stale ($($age)s), owner clear" }
    }
    if ($snapshot.ProcessStatus -eq 'dead') {
        if (-not $reviewed) { return [pscustomobject]@{ Action = 'recovery-disabled'; Reason = 'runner is down; exact-hash review pin absent/mismatched' } }
        return [pscustomobject]@{ Action = 'start-runner'; Reason = 'runner is down and owner markers are clear' }
    }
    [pscustomobject]@{ Action = 'none'; Reason = 'runner state is not actionable' }
}

function Get-EnsurePlan([string]$pidState, [int]$matchingCount) {
    if ($matchingCount -gt 1) { return 'ambiguous-duplicate-supervisors' }
    if ($matchingCount -eq 1) { return 'already-running' }
    if ($pidState -in @('unknown', 'verified')) { return 'ambiguous-pid' }
    'start-supervisor'
}

function Invoke-RunnerAction([string]$rig, [string]$action, [string]$runnerScript, [string]$rd) {
    # This is only reached after the exact script hash pin and clear-owner proof pass.
    # rig-runner -Stop/-Start targets the runner PID only; no game PID is ever passed or killed.
    if ($action -eq 'start-runner') {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerScript -Ensure -Rig $rig 2>&1 | ForEach-Object { "$($_)" }
        return
    }
    if ($action -eq 'restart-runner') {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerScript -Stop -Rig $rig 2>&1 | ForEach-Object { "$($_)" }
        if ($LASTEXITCODE -ne 0) { throw "runner stop path failed for $rig ($LASTEXITCODE)" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerScript -Start -Rig $rig 2>&1 | ForEach-Object { "$($_)" }
        if ($LASTEXITCODE -ne 0) { throw "runner start path failed for $rig ($LASTEXITCODE)" }
    }
}

function Write-SupervisorLine([string]$root, [string]$line) {
    $rd = Join-Path $root 'runner'; New-Item -ItemType Directory -Force -Path $rd | Out-Null
    Add-Content -LiteralPath (Join-Path $rd 'paired-supervisor.log') -Value $line -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $rd 'paired-supervisor.heartbeat') -Value (Get-Date -Format o) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $rd 'paired-supervisor.status') -Value $line -Encoding UTF8
}

function Ensure-Supervisor([string]$scriptPath, [string]$root, [int]$intervalSec) {
    $rd = Join-Path $root 'runner'; New-Item -ItemType Directory -Force -Path $rd | Out-Null
    $ensureLock = Join-Path $rd 'paired-supervisor.ensure.lock'
    $fs = $null
    try {
        try { $fs = [IO.File]::Open($ensureLock, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { 'SUPERVISOR ENSURE busy; singleton state not changed'; return }
        $procFile = Join-Path $rd 'paired-supervisor.pid'
        $pidState = 'missing'; $matches = @(); $inventory = Get-ProcessInventory
        if ($null -eq $inventory) { 'SUPERVISOR ENSURE process query unavailable; fail closed'; return }
        if (Test-Path -LiteralPath $procFile -PathType Leaf) {
            $txt = (Get-Content -LiteralPath $procFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($txt -match '^\d+$') {
                $p = Find-ProcessById $inventory ([int]$txt)
                if ($null -eq $p) { $pidState = 'dead' }
                elseif ($p.CommandLine -and $p.CommandLine.ToLowerInvariant().Replace('/', '\').Contains((Normalize-Path $scriptPath)) -and $p.CommandLine -match '(?i)(?:^|\s)-loop(?:\s|$)') { $pidState = 'verified' }
                else { $pidState = 'unknown' }
            } else { $pidState = 'unknown' }
        }
        # Supervisor uses -Loop, not -Rig; query its exact command line separately.
        $needle = [regex]::Escape((Normalize-Path $scriptPath))
        $matches = @($inventory | Where-Object {
            ([string]$_.Name -match '^(?i:powershell|pwsh)\.exe$') -and
            (($c = ([string]$_.CommandLine).ToLowerInvariant() -replace '/', '\')) -and
            $c -match $needle -and $c -match '(?i)(?:^|\s)-loop(?:\s|$)'
        })
        $plan = Get-EnsurePlan $pidState $matches.Count
        if ($plan -eq 'already-running') { $spid = [int]$matches[0].ProcessId; Set-Content -LiteralPath $procFile -Value $spid; "SUPERVISOR ENSURED pid=$spid interval=${intervalSec}s recovery=hash-gated"; return }
        if ($plan -like 'ambiguous*') { "SUPERVISOR ENSURE $plan; fail closed"; return }
        if ($pidState -eq 'dead') { Remove-Item -LiteralPath $procFile -Force -ErrorAction SilentlyContinue }
        $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-Loop', '-Root', $root, '-IntervalSec', [string]$intervalSec)
        $p = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList $arg
        Set-Content -LiteralPath $procFile -Value $p.Id
        "SUPERVISOR STARTED pid=$($p.Id) interval=${intervalSec}s recovery=hash-gated"
    } finally { if ($fs) { $fs.Dispose() } }
}

function Invoke-OneSample([string]$root, [string]$reviewPin, [int]$staleSec, [hashtable]$previous, [bool]$executeActions) {
    $scriptPath = $PSCommandPath
    $runnerScript = Join-Path $PSScriptRoot 'rig-runner.ps1'
    $hash = Get-ScriptHash $scriptPath
    $reviewed = Test-ReviewPin $reviewPin $hash
    $inventory = Get-ProcessInventory
    $records = @()
    foreach ($rig in '5090', '4080') {
        $snap = Get-RigSnapshot $root $rig $runnerScript $inventory
        $progress = Get-Progress $previous[$rig] $snap.Row
        $previous[$rig] = $snap.Row
        $act = Get-RunnerAction $snap $staleSec $reviewed ([bool]$snap.Row)
        $row = if ($snap.Row) { $snap.Row.Row } else { '-' }
        $progressText = if ($progress.Baseline) { 'baseline' } elseif ($progress.Progress) { $progress.Sources -join ',' } elseif ($snap.Row) { 'no-change' } else { 'no-active-row' }
        $line = '{0} rig={1} runner={2} heartbeat={3}s row={4} progress={5} ownerClear={6} action={7} reason={8}' -f (Get-Date -Format o), $rig, $snap.ProcessStatus, $(if ($null -eq $snap.HeartbeatAgeSec) { '?' } else { $snap.HeartbeatAgeSec }), $row, $progressText, $snap.Owner.Clear, $act.Action, ($act.Reason -replace '[\r\n]', ' ')
        Write-SupervisorLine $root $line
        if ($executeActions -and $act.Action -in @('start-runner', 'restart-runner')) {
            Invoke-RunnerAction $rig $act.Action $runnerScript (Join-Path $root 'runner')
            Write-SupervisorLine $root ('{0} rig={1} action-complete={2}' -f (Get-Date -Format o), $rig, $act.Action)
        }
        $records += [pscustomobject]@{ Rig = $rig; Snapshot = $snap; Progress = $progress; Decision = $act }
    }
    $records
}

function Invoke-SelfTest {
    $script:testN = 0
    $script:testOk = $true
    $check = { param($v, $name) $script:testN++; if ($v) { "PASS $name" } else { $script:testOk = $false; "FAIL $name" } }
    $prior = [pscustomobject]@{ List = 'batch-a'; Row = 'CHAT-001'; OutputAgeSec = 90; GameHours = 4.1; ResultCursor = ''; RowFile = '10:1' }
    $fresh = [pscustomobject]@{ List = 'batch-a'; Row = 'CHAT-001'; OutputAgeSec = 7; GameHours = 4.1; ResultCursor = ''; RowFile = '11:2' }
    $real = Get-Progress $prior $fresh
    & $check ($real.Progress -and ($real.Sources -contains 'active-batch-output-updated') -and ($real.Sources -contains 'named-row-file-updated')) 'real-named-row-progress'
    $sameLabelStale = [pscustomobject]@{ List = 'batch-a'; Row = 'CHAT-001'; OutputAgeSec = 135; GameHours = 4.1; ResultCursor = ''; RowFile = '10:1'; GamePidAlive = $true }
    $staleProgress = Get-Progress $prior $sameLabelStale
    & $check (-not $staleProgress.Progress) 'unchanged-row-label-and-live-game-pid-are-not-progress'
    $state5090 = Get-StateRow '12:01 running list-5090 row=CHAT-002 age=2s gh=4.2'
    $state4080 = Get-StateRow '12:01 running list-4080 row=CHAT-002 age=3s gh=7.5'
    & $check ($state5090.Row -eq 'CHAT-002' -and $state4080.Row -eq 'CHAT-002' -and (Get-Progress $prior $state5090).Progress -and (Get-Progress $prior $state4080).Progress) 'both-rigs-report-exact-named-row-transitions'

    $clearOwner = [pscustomobject]@{ Clear = $true; Detail = 'no owner'; Ambiguous = $false }
    $activeOwner = [pscustomobject]@{ Clear = $false; Detail = '5090.cur present'; Ambiguous = $true }
    $base = @{ Stopped = $false; Owner = $clearOwner; HeartbeatAgeSec = 300; ProcessStatus = 'alive'; ProcessDetail = 'verified'; Row = $null; Pid = 101 }
    $stale = [pscustomobject]$base
    $decision = Get-RunnerAction $stale 180 $true $true
    & $check ($decision.Action -eq 'restart-runner') 'verified-live-stale-runner-recovery'
    $cimAge = Get-ProcessAgeSec ([pscustomobject]@{ CreationDate = (Get-Date).AddMinutes(-10) })
    & $check ($null -ne $cimAge -and $cimAge -ge 598) 'runner-process-start-time-measures-age'
    $missingHeartbeat = [pscustomobject]@{ Stopped = $false; Owner = $clearOwner; HeartbeatAgeSec = $null; ProcessAgeSec = 300; ProcessStatus = 'alive'; ProcessDetail = 'verified'; Row = $null; Pid = 102 }
    & $check ((Get-RunnerAction $missingHeartbeat 180 $true $false).Action -eq 'restart-runner') 'missing-heartbeat-uses-verified-runner-age'
    $startupGrace = [pscustomobject]@{ Stopped = $false; Owner = $clearOwner; HeartbeatAgeSec = 900; ProcessAgeSec = 20; ProcessStatus = 'alive'; ProcessDetail = 'verified'; Row = $null; Pid = 103 }
    & $check ((Get-RunnerAction $startupGrace 180 $true $false).Action -eq 'none') 'fresh-runner-process-gets-startup-grace'
    $blocked = [pscustomobject]@{ Stopped = $false; Owner = $activeOwner; HeartbeatAgeSec = 300; ProcessStatus = 'alive'; ProcessDetail = 'verified'; Row = $prior; Pid = 101 }
    $decisionActive = Get-RunnerAction $blocked 180 $true $true
    & $check ($decisionActive.Action -eq 'none' -and $decisionActive.Reason -like '*owner/batch*') 'live-row-owner-blocks-recovery'
    $decisionUnreviewed = Get-RunnerAction $stale 180 $false $true
    & $check ($decisionUnreviewed.Action -eq 'recovery-disabled') 'recovery-disabled-without-exact-hash-review'
    $pinFile = Join-Path $env:TEMP "paired-supervisor-pin-$PID.txt"
    $fakeHash = Get-ScriptHash $PSCommandPath
    try {
        Set-Content -LiteralPath $pinFile -Value $fakeHash -NoNewline
        & $check (Test-ReviewPin $pinFile $fakeHash) 'exact-review-pin-enables-test-decision'
        & $check (-not (Test-ReviewPin $pinFile ('B' * 64))) 'mismatched-review-pin-fails-closed'
    } finally { Remove-Item -LiteralPath $pinFile -Force -ErrorAction SilentlyContinue }
    & $check ((Get-EnsurePlan 'verified' 1) -eq 'already-running') 'ensure-singleton-existing-supervisor'
    & $check ((Get-EnsurePlan 'missing' 0) -eq 'start-supervisor') 'ensure-starts-missing-supervisor'
    & $check ((Get-EnsurePlan 'unknown' 0) -eq 'ambiguous-pid') 'ensure-fails-closed-on-ambiguous-pid'
    & $check ((Get-EnsurePlan 'verified' 2) -eq 'ambiguous-duplicate-supervisors') 'ensure-fails-closed-on-duplicates'

    $down = [pscustomobject]@{ Stopped = $false; Owner = $clearOwner; HeartbeatAgeSec = 999; ProcessStatus = 'dead'; ProcessDetail = 'down'; Row = $null; Pid = $null }
    $deadDecision = Get-RunnerAction $down 180 $true $false
    & $check ($deadDecision.Action -eq 'start-runner') 'dead-runner-start-through-runner-path'

    $fixtureRoot = Join-Path $env:TEMP "paired-supervisor-owner-$PID"
    try {
        foreach ($d in @('runner', 'queue\running', 'inflight')) { New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRoot $d) | Out-Null }
        $proof5090 = Get-OwnerProof $fixtureRoot '5090' '' @()
        $proof4080 = Get-OwnerProof $fixtureRoot '4080' '' @()
        & $check ($proof5090.Clear -and $proof4080.Clear) 'both-rigs-clear-owner-proof-from-synthetic-root'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'runner\5090.cur') -Value 'synthetic-active-row'
        $proof5090 = Get-OwnerProof $fixtureRoot '5090' '' @('synthetic-active-row')
        $proof4080 = Get-OwnerProof $fixtureRoot '4080' '' @()
        & $check (-not $proof5090.Clear -and $proof4080.Clear) 'ambiguous-owner-is-scoped-to-affected-rig'
    } finally { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }

    $pairRoot = Join-Path $env:TEMP "paired-supervisor-pair-$PID"
    try {
        foreach ($d in @('runner', 'queue\running', 'inflight', 'out-4080')) { New-Item -ItemType Directory -Force -Path (Join-Path $pairRoot $d) | Out-Null }
        Set-Content -LiteralPath (Join-Path $pairRoot 'runner\5090.pid') -Value '111'
        Set-Content -LiteralPath (Join-Path $pairRoot 'runner\5090.state') -Value '12:00 queue empty'
        (Get-Item -LiteralPath (Join-Path $pairRoot 'runner\5090.state')).LastWriteTime = (Get-Date).AddMinutes(-10)
        Set-Content -LiteralPath (Join-Path $pairRoot 'runner\4080.pid') -Value '222'
        Set-Content -LiteralPath (Join-Path $pairRoot 'runner\4080.state') -Value '12:00 running batch-b row=CHAT-003 age=500s gh=7.2'
        (Get-Item -LiteralPath (Join-Path $pairRoot 'runner\4080.state')).LastWriteTime = (Get-Date).AddMinutes(-10)
        Set-Content -LiteralPath (Join-Path $pairRoot 'runner\4080.cur') -Value @('synthetic-list', (Join-Path $pairRoot 'out-4080'))
        $runnerScript = Join-Path $PSScriptRoot 'rig-runner.ps1'
        $inventory = @(
            [pscustomobject]@{ Name = 'powershell.exe'; ProcessId = 111; CommandLine = "powershell.exe -File $runnerScript -Rig 5090"; CreationDate = (Get-Date).AddMinutes(-10) },
            [pscustomobject]@{ Name = 'powershell.exe'; ProcessId = 222; CommandLine = "powershell.exe -File $runnerScript -Rig 4080"; CreationDate = (Get-Date).AddMinutes(-10) }
        )
        $snap5090 = Get-RigSnapshot -root $pairRoot -rig '5090' -runnerScript $runnerScript -inventory $inventory
        $snap4080 = Get-RigSnapshot -root $pairRoot -rig '4080' -runnerScript $runnerScript -inventory $inventory
        $decision5090 = Get-RunnerAction $snap5090 180 $true $false
        $decision4080 = Get-RunnerAction $snap4080 180 $true $false
        $pairActions = @($decision5090.Action, $decision4080.Action)
        & $check ($pairActions[0] -eq 'restart-runner' -and $pairActions[1] -eq 'none' -and -not $snap4080.Owner.Clear) 'one-rig-only-recovery-from-synthetic-paired-state'
    } finally { Remove-Item -LiteralPath $pairRoot -Recurse -Force -ErrorAction SilentlyContinue }

    $ambiguous = [pscustomobject]@{ Stopped = $false; Owner = $clearOwner; HeartbeatAgeSec = 300; ProcessStatus = 'ambiguous'; ProcessDetail = 'pid mismatch'; Row = $null; Pid = 303 }
    & $check ((Get-RunnerAction $ambiguous 180 $true $false).Action -eq 'none') 'ambiguous-runner-owner-fails-closed'
    $liveGame = [pscustomobject]@{ Stopped = $false; Owner = $clearOwner; HeartbeatAgeSec = 300; ProcessStatus = 'alive'; ProcessDetail = 'verified'; Row = $null; Pid = 404; GameAlive = $true }
    $safePlan = Get-RunnerAction $liveGame 180 $true $false
    & $check ($safePlan.Action -eq 'restart-runner' -and $safePlan.Action -notlike '*game*') 'healthy-game-is-never-a-recovery-target'
    $selfText = Get-Content -LiteralPath $PSCommandPath -Raw
    & $check ($selfText.Contains('-Stop -Rig $rig') -and $selfText.Contains('-Start -Rig $rig') -and $selfText.Contains('-Ensure -Rig $rig')) 'recovery-uses-existing-rig-runner-path'
    $codeOnly = $selfText.Substring(0, $selfText.IndexOf('function Invoke-SelfTest'))
    & $check ($codeOnly -notmatch '(?i)taskkill|kill-game|kenshi-ctl\.ps1.{0,20}stop|ctl\.ps1.{0,20}stop') 'supervisor-has-no-game-kill-path'

    $sessionStart = Join-Path $PSScriptRoot 'session-start.ps1'
    $src = Get-Content -LiteralPath $sessionStart -Raw
    $calls = [regex]::Matches($src, 'paired-runner-supervisor\.ps1[^\r\n]*-Ensure').Count
    & $check ($calls -eq 1) 'session-start-ensures-one-persistent-supervisor'
    "SELFTEST $(if ($script:testOk) { 'PASS' } else { 'FAIL' }) cases=$script:testN"
    exit [int](-not $script:testOk)
}

if ($SelfTest) { Invoke-SelfTest }

$IntervalSec = [Math]::Min(60, [Math]::Max(1, $IntervalSec))
$scriptPath = $PSCommandPath
if ($Ensure) { Ensure-Supervisor $scriptPath $Root $IntervalSec; exit 0 }
if ($Once) { $null = Invoke-OneSample $Root $ReviewPin $StaleRunnerSec @{} $true; exit 0 }
if ($Loop) {
    $rd = Join-Path $Root 'runner'; New-Item -ItemType Directory -Force -Path $rd | Out-Null
    $loopLock = Join-Path $rd 'paired-supervisor.loop.lock'; $lockStream = $null
    try { $lockStream = [IO.File]::Open($loopLock, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { 'SUPERVISOR LOOP duplicate or lock ambiguous; exiting'; exit 0 }
    $pidPath = Join-Path $rd 'paired-supervisor.pid'; Set-Content -LiteralPath $pidPath -Value $PID
    $previous = @{ '5090' = $null; '4080' = $null }
    try {
        while ($true) {
            try { $null = Invoke-OneSample $Root $ReviewPin $StaleRunnerSec $previous $true }
            catch { Write-SupervisorLine $Root ('{0} ERROR {1}' -f (Get-Date -Format o), $_.Exception.Message) }
            Start-Sleep -Seconds $IntervalSec
        }
    } finally {
        if ((Test-Path -LiteralPath $pidPath) -and ((Get-Content -LiteralPath $pidPath -Raw).Trim() -eq [string]$PID)) { Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue }
        if ($lockStream) { $lockStream.Dispose() }
    }
}

Write-Output 'usage: paired-runner-supervisor.ps1 -Ensure|-Loop|-Once|-SelfTest'
exit 2
