# coord-chores.ps1 - take the model out of the mechanical waker wake-ups (Shay 2026-10-16: "a script can do them at zero tokens").
#
# Consumes the waker event stream (waker-persist.sh lines: '<iso> EVENT ...', 'SWEEP ...', 'WAKER ...') and handles the DETERMINISTIC events
# without a model; only events that need judgment reach the coordinator, in full. Rules: coord-chores.rules.json (first match wins, a rule whose
# condition is false is skipped, no match = JUDGMENT). Selftest: coord-chores-selftest.ps1. Wrapper for the Monitor tool: waker-persist-chores.sh.
#
#   coord-chores.ps1 stream [-InputFile f]   filter stdin (or a file) -> stdout. AUTO events are handled + counted silently; JUDGMENT events are printed
#                                            in full behind ONE summary line:  CHORES: 4 auto (2 DONE logged, 1 alert acked, 1 sweep clean) | ATTENTION: 1
#                                            An auto-only quiet period prints nothing (a line is one Monitor notification = one model wake); every
#                                            settings.autoOnlyLineEveryMin (60) minutes one liveness line is printed if anything was automated.
#   coord-chores.ps1 classify -InputFile f [-NoActions]   print AUTO/JUDGMENT + rule per item (-NoActions = no side effects at all)
#   coord-chores.ps1 register-new [-DryRun]   record agentId -> name for in-session subagents that were spawned (agent-ids.ps1 add); the id and
#                                            name are recovered from <session>\subagents\agent-<id>.jsonl (first record = the prompt) + the status file
#   coord-chores.ps1 ack-sweep [-DryRun]      ack open lane-idle / lane-no-operator alerts that a rule allows (never any other kind)
#   coord-chores.ps1 flush-to-live [-Date d] [-NoCommit] [-NoPush]   (alias: -FlushToLive) append the day's digest to testing/COORDINATOR_LIVE.md,
#                                            commit with an explicit pathspec (identity shaylanger, retry on index.lock) and push
#   coord-chores.ps1 status                   one line: heartbeat, today's digest file, counts
#
# Output files (Runs = C:\KenshiTestRuns): coordinator-digest\<date>.md (one dated line per handled event), coordinator-digest\chores.log (actions,
# acks, errors), coordinator-digest\chores.state.json (seen events, last sweep refresh), coordinator-digest\chores.hb (heartbeat).
# HARD CONSTRAINTS (also enforced in code): stall / orphaned / dead / killed / LLM-HEALTH / LANE STALLED events and failed or stopped agents with no
# successor are NEVER auto-handled; an auto-ack only closes a lane-idle / lane-no-operator alert when a rule condition holds (WIND_DOWN.flag, lanes.held,
# operator DONE + no claimable row), is shown as '[auto-acked <id>: <rule>]' in the next printed block + stored in the closed alert, and the alert
# re-opens by the existing 30-minute rule if the condition is still true. Any internal error passes the event through unchanged.
# Test switches: -Runs (default $env:KAH_RUNS_DIR or C:\KenshiTestRuns), -Rules, -Repo, -SubagentsDir, -LiveMd, -LibOnly (dot-source for the selftest).
param(
    [Parameter(Position = 0)][string]$Command = 'stream',
    [string]$InputFile = '', [string]$Runs = '', [string]$Rules = '', [string]$Repo = 'C:\KenshiModding',
    [string]$Date = '', [string]$SubagentsDir = '', [string]$LiveMd = '',
    [switch]$FlushToLive, [switch]$NoActions, [switch]$DryRun, [switch]$NoCommit, [switch]$NoPush, [switch]$LibOnly
)
$ErrorActionPreference = 'Continue'
if ($FlushToLive) { $Command = 'flush-to-live' }
if (-not $Runs) { $Runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' } }
$script:Runs = $Runs
$script:Here = $PSScriptRoot
if (-not $Rules) { $Rules = Join-Path $PSScriptRoot 'coord-chores.rules.json' }
$script:NoActions = [bool]$NoActions
$script:DigestDir = Join-Path $Runs 'coordinator-digest'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $PSScriptRoot 'alert-lib.ps1')   # definitions only (Get-OpenAlerts, ConvertTo-AlertId, Invoke-AlertScan)

function Get-Cfg {
    $j = [IO.File]::ReadAllText($Rules, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $j
}
$script:Cfg = Get-Cfg
$S = $script:Cfg.settings

# ---------------------------------------------------------------- small helpers
function Ensure-Dir([string]$d) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }
function Append-Text([string]$path, [string]$text) {
    for ($i = 0; $i -lt 6; $i++) {
        try { [IO.File]::AppendAllText($path, $text, $script:Utf8); return $true } catch { Start-Sleep -Milliseconds (150 * ($i + 1)) }
    }
    $false
}
function Write-ChoreLog([string]$text) {
    Ensure-Dir $script:DigestDir
    [void](Append-Text (Join-Path $script:DigestDir 'chores.log') ((Get-Date).ToString('s') + "`t" + $text + "`n"))
}
function Get-DigestPath([string]$date = '') {
    if (-not $date) { $date = (Get-Date).ToString('yyyy-MM-dd') }
    Join-Path $script:DigestDir ($date + '.md')
}
function Write-DigestLine([string]$text) {
    if ($script:NoActions) { return }
    Ensure-Dir $script:DigestDir
    $p = Get-DigestPath
    if (-not (Test-Path -LiteralPath $p)) {
        [void](Append-Text $p ("# Coordinator digest " + (Get-Date).ToString('yyyy-MM-dd') + " (written by coord-chores.ps1, zero model tokens; one line per handled event)`n"))
    }
    $t = ($text -replace '[\r\n]+', ' ')
    if ($t.Length -gt 700) { $t = $t.Substring(0, 700) + '...' }
    [void](Append-Text $p ('- ' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + ' ' + $t + "`n"))
}
function Cut([string]$s, [int]$n) { if ($null -eq $s) { return '' }; $s = $s.Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }
function Read-StatusFile([string]$name) {
    $f = Join-Path (Join-Path $script:Runs 'agents') ($name + '.status')
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $lines = @([IO.File]::ReadAllLines($f, $script:Utf8) | ForEach-Object { $_ -replace '^\uFEFF', '' })
    $o = @{ Name = $name; File = $f; First = ''; State = ''; Task = ''; Latest = ''; Outputs = ''; Next = ''; Mtime = (Get-Item -LiteralPath $f).LastWriteTime }
    if ($lines.Count) {
        $o.First = $lines[0]
        $p = $lines[0] -split '\|'
        if ($p.Count -ge 2) { $o.State = $p[1].Trim() }
    }
    foreach ($l in $lines) {
        if ($l -match '^task:\s*(.*)$') { $o.Task = $Matches[1] }
        elseif ($l -match '^latest:\s*(.*)$') { $o.Latest = $Matches[1] }
        elseif ($l -match '^outputs:\s*(.*)$') { $o.Outputs = $Matches[1] }
        elseif ($l -match '^next:\s*(.*)$') { $o.Next = $Matches[1] }
    }
    $o
}

# ---------------------------------------------------------------- state (seen events, last sweep refresh)
$script:StatePath = Join-Path $script:DigestDir 'chores.state.json'
$script:State = @{ seen = @(); lastSweepRefresh = ''; regTried = @{} }
$script:SeenSet = New-Object 'System.Collections.Generic.HashSet[string]'
function Load-State {
    try {
        if (Test-Path -LiteralPath $script:StatePath) {
            $j = [IO.File]::ReadAllText($script:StatePath, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            foreach ($h in @($j.seen)) { if ($h) { [void]$script:SeenSet.Add([string]$h) } }
            if ($j.lastSweepRefresh) { $script:State.lastSweepRefresh = [string]$j.lastSweepRefresh }
            if ($j.regTried) { foreach ($p in $j.regTried.psobject.Properties) { $script:State.regTried[$p.Name] = [int]$p.Value } }
        }
    } catch { }
}
$script:SeenOrder = New-Object System.Collections.Generic.List[string]
function Save-State {
    if ($script:NoActions) { return }
    try {
        Ensure-Dir $script:DigestDir
        $keep = [int]$S.seenKeep
        $arr = @($script:SeenOrder)
        if ($arr.Count -gt $keep) { $arr = $arr[($arr.Count - $keep)..($arr.Count - 1)] }
        $o = [ordered]@{ seen = $arr; lastSweepRefresh = $script:State.lastSweepRefresh; regTried = $script:State.regTried }
        $tmp = $script:StatePath + '.tmp'
        [IO.File]::WriteAllText($tmp, ($o | ConvertTo-Json -Depth 4), $script:Utf8)
        Move-Item -Force -LiteralPath $tmp -Destination $script:StatePath
    } catch { }
}
function Get-LineKey([string]$line) {
    $sha = [Security.Cryptography.SHA1]::Create()
    -join ($sha.ComputeHash($script:Utf8.GetBytes($line)) | ForEach-Object { $_.ToString('x2') })
}

# ---------------------------------------------------------------- waker line -> items
# returns @{ Prefix = '<iso> '; Items = @('<normalized item text>'...); Kind = 'digest|lane|other' }
function Split-WakerLine([string]$line) {
    $l = ($line -replace '^\uFEFF', '').TrimEnd("`r", "`n")
    $prefix = ''
    if ($l -match '^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\s+)(.*)$') { $prefix = $Matches[1]; $t = $Matches[2] } else { $t = $l }
    $items = @(); $kind = 'other'
    if ($t -match '^EVENT DIGEST \d+ items(?<rest>.*)$') {
        $kind = 'digest'
        foreach ($it in ($Matches['rest'] -split ' ;; ')) { $x = $it.Trim(); if ($x) { $items += $x } }
    } elseif ($t -match '^EVENT LANE (?<r>.*)$') {
        $kind = 'lane'
        foreach ($seg in [regex]::Split($Matches['r'], '(?=LANE (?:IDLE|NO-OPERATOR|STALLED) \S)')) { $x = $seg.Trim(); if ($x) { $items += $x } }
        if (-not $items.Count) { $items = @('LANE ' + $t.Substring(11)) }
    } elseif ($t -match '^EVENT STATUS (?<n>\S+) DONE: (?<task>.*)$') {
        $items = @('DONE: STATUS ' + $Matches['n'] + ' DONE: ' + $Matches['task'])
    } elseif ($t -match '^EVENT DONE\(quiet\) (?<r>.*)$') {
        $items = @('DONE: ' + $Matches['r'])
    } elseif ($t -match '^EVENT (?<r>.*)$') {
        $items = @($Matches['r'])
    } else {
        $items = @($t)
    }
    @{ Prefix = $prefix; Items = $items; Kind = $kind; Raw = $line }
}

# ---------------------------------------------------------------- conditions
function Test-WindDown($ctx) {
    $f = [string]$S.windDownFlag
    if (-not [IO.Path]::IsPathRooted($f)) { $f = Join-Path $script:Runs $f }
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    if ($ctx.Kind -eq 'IDLE' -and $ctx.IdleMin -gt [double]$S.maxIdleAckMin) { return $false }   # idle far too long = a stall candidate: the model looks
    $true
}
function Test-LaneHeld($ctx) {
    $lane = $ctx.Lane
    if (-not $lane) { return $false }
    $hf = Join-Path $script:Runs 'lanes.held'
    if (-not (Test-Path -LiteralPath $hf)) { return $false }
    try {
        . (Join-Path $script:Here 'lane-hold-lib.ps1')
        return (@(Get-ActiveHolds $script:Runs) -contains $lane)
    } catch { }
    foreach ($h in @([IO.File]::ReadAllLines($hf))) { $x = $h.Trim(); if ($x -and -not $x.StartsWith('#') -and $x -eq $lane) { return $true } }
    $false
}
$script:NextRowFn = {
    param($lane)
    $o = & wsl.exe -e bash -lc ("cd /mnt/c/KenshiModding && timeout 20 bash tools/automation/next-row.sh $lane --ids 2>&1 | head -3") 2>&1 | Out-String
    $o
}
function Test-DoneNoRows($ctx) {
    if ($ctx.Kind -ne 'NO-OPERATOR' -or -not $ctx.Lane) { return $false }
    if ($ctx.Text -notmatch 'among (?<ops>\S+)') { return $false }
    $first = ($Matches['ops'] -split ',')[0]
    $st = Read-StatusFile $first
    if (-not $st -or $st.State -ne 'DONE') { return $false }
    try { $o = [string](& $script:NextRowFn $ctx.Lane) } catch { return $false }
    ($o -match ('NEXT ' + [regex]::Escape($ctx.Lane) + ': no claimable'))
}
function Test-TicketOwned($ctx) {
    $row = $ctx.Row
    if (-not $row) { return $false }
    $d = Join-Path $script:Runs 'setupfail'
    $f = Join-Path $d ($row + '.json')
    if (-not (Test-Path -LiteralPath $f)) { $f = Join-Path $d (($row.ToLower()) + '.json') }
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    try {
        $t = [IO.File]::ReadAllText($f, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json
        $own = [string]$t.owner
        if (-not $own -or $own -eq '-') { return $false }
        $st = Read-StatusFile $own
        return ($st -and $st.State -eq 'RUNNING')
    } catch { return $false }
}
function Test-SuccessorExists($ctx) {
    $n = $ctx.Name
    if (-not $n) { return $false }
    if ($ctx.Text -match '\(successor (?<s>[A-Za-z0-9._-]+)\)') {
        $st = Read-StatusFile $Matches['s']
        if ($st -and ($st.State -eq 'RUNNING' -or $st.State -eq 'DONE')) { return $true }
        return $false
    }
    try {
        . (Join-Path $script:Here 'agent-guard-lib.ps1')
        $r = Get-AgentReport -AgentsDir (Join-Path $script:Runs 'agents')
        return (-not (@($r.Open | ForEach-Object { $_.Name }) -contains $n))
    } catch { return $false }
}
function Test-RollcallFresh($ctx) {
    $t = $ctx.Text
    if ($t -match 'proc=DEAD') { return $false }
    if ($t -notmatch 'status_age=(?<a>\d+(\.\d+)?)m') { return $false }
    ([double]$Matches['a'] -le [double]$S.rollcallFreshMin)
}
function Test-Cond([string]$name, $ctx) {
    switch ($name) {
        'windDown' { return (Test-WindDown $ctx) }
        'held' { return (Test-LaneHeld $ctx) }
        'doneNoRows' { return (Test-DoneNoRows $ctx) }
        'ticketOwned' { return (Test-TicketOwned $ctx) }
        'successorExists' { return (Test-SuccessorExists $ctx) }
        'rollcallFresh' { return (Test-RollcallFresh $ctx) }
        default { return $false }
    }
}

# ---------------------------------------------------------------- classification
# returns @{ Class = 'AUTO'|'JUDGMENT'; Rule; Label; Action; Ctx; Text }
function Classify-Item([string]$text) {
    $res = @{ Class = 'JUDGMENT'; Rule = ''; Label = ''; Action = ''; Ctx = $null; Text = $text }
    $guard = [string]$S.guardRegex
    foreach ($r in @($script:Cfg.rules)) {
        $m = [regex]::Match($text, [string]$r.match)
        if (-not $m.Success) { continue }
        $ctx = @{ Text = $text; Name = ''; Row = ''; Lane = ''; Kind = ''; IdleMin = 0.0 }
        foreach ($gn in 'name', 'row', 'lane', 'kind') { if ($m.Groups[$gn].Success) { $ctx[(Get-Culture).TextInfo.ToTitleCase($gn)] = $m.Groups[$gn].Value } }
        if ($text -match '^LANE IDLE \S+ (?<i>\d+(\.\d+)?)m') { $ctx.IdleMin = [double]$Matches['i'] }
        $gmode = if ($r.guard) { [string]$r.guard } else { 'full' }
        if ($gmode -ne 'none') {
            $gt = if ($gmode -eq 'head') { $text.Substring(0, [Math]::Min(90, $text.Length)) } else { $text }
            if ($gt -cmatch $guard) { continue }
        }
        if ($r.if -and -not (Test-Cond ([string]$r.if) $ctx)) { continue }
        $res.Class = [string]$r.class; $res.Rule = [string]$r.id; $res.Label = [string]$r.label; $res.Action = [string]$r.action; $res.Ctx = $ctx
        return $res
    }
    $res
}

# ---------------------------------------------------------------- actions
$script:Acks = New-Object System.Collections.Generic.List[string]
$script:LastForcedScan = [datetime]::MinValue
$script:SweepRefreshFn = {
    Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:Here 'testruns-sweep.ps1'), 'refresh4080' | Out-Null
}
function Do-LogDone($c) {
    $st = Read-StatusFile $c.Ctx.Name
    if ($st) {
        Write-DigestLine ("DONE " + $st.Name + " | " + (Cut ($st.Task -replace '^task:\s*', '') 140) + " | latest: " + (Cut $st.Latest 160) + " | outputs: " + (Cut $st.Outputs 160) + " | next: " + (Cut $st.Next 120))
    } else {
        Write-DigestLine ("DONE " + (Cut ($c.Text -replace '^DONE: ', '') 300) + " (no status file)")
    }
}
function Do-LogLine($c) {
    $t = $c.Text -replace '^(DONE|INFO|HAS-SUCCESSOR|SETUP-FAIL-READY): ', '$1 '
    Write-DigestLine (Cut $t 500)
}
function Find-OpenAlert([string]$id) {
    @(Get-OpenAlerts $script:Runs) | Where-Object { $_.Id -eq $id } | Select-Object -First 1
}
function Do-LaneAck($c) {
    $kind = switch ([string]$c.Ctx.Kind) { 'IDLE' { 'lane-idle' } 'NO-OPERATOR' { 'lane-no-operator' } 'STALLED' { 'lane-stalled' } default { 'unknown-' + [string]$c.Ctx.Kind } }
    $never = @($S.neverAckKinds)
    $ok = @($S.ackableKinds)
    if ($never -contains $kind -or $ok -notcontains $kind) { return 'refused: kind not ackable' }
    $id = ConvertTo-AlertId $kind $c.Ctx.Lane
    $a = Find-OpenAlert $id
    if (-not $a -and ((Get-Date) - $script:LastForcedScan).TotalSeconds -gt 60) {
        $script:LastForcedScan = Get-Date
        try { [void](Invoke-AlertScan -Runs $script:Runs -Force) } catch { }
        $a = Find-OpenAlert $id
    }
    if (-not $a) { return 'no open alert (nothing to ack)' }
    $action = "auto-acked by coord-chores ($($c.Rule)); alert re-opens after 30 min if still true"
    $out = & (Join-Path $script:Here 'alert-ack.ps1') -Runs $script:Runs $id $action 2>&1 | Out-String
    if ($out -match '^\s*ACKED ') {
        $script:Acks.Add("[auto-acked ${id}: $($c.Rule)]")
        Write-ChoreLog "auto-acked $id rule=$($c.Rule)"
        Write-DigestLine "alert auto-acked $id ($($c.Rule))"
        return 'acked'
    }
    Write-ChoreLog ("ack failed $id : " + (Cut $out 200))
    'ack-failed'
}
function Do-Backstop {
    if (-not [bool]$S.sweepRefresh.enabled) { return }
    $due = $true
    if ($script:State.lastSweepRefresh) {
        try { $due = (((Get-Date) - [datetime]$script:State.lastSweepRefresh).TotalMinutes -ge [double]$S.sweepRefresh.everyMin) } catch { $due = $true }
    }
    if ($due) {
        try { & $script:SweepRefreshFn } catch { Write-ChoreLog ("sweep refresh failed: " + $_.Exception.Message) }
        $script:State.lastSweepRefresh = (Get-Date).ToString('s')
        Write-ChoreLog 'sweep cache refresh started (refresh4080)'
        $script:ExtraAuto.Add('sweep refresh')
    }
}
$script:ExtraAuto = New-Object System.Collections.Generic.List[string]
function Do-Action($c) {
    if ($script:NoActions) { return 'skipped (no-actions)' }
    switch ($c.Action) {
        'log-done' { Do-LogDone $c; return 'logged' }
        'log-line' { Do-LogLine $c; return 'logged' }
        'count' { return 'counted' }
        'lane-ack' { return (Do-LaneAck $c) }
        'backstop' { Do-Backstop; return 'backstop' }
        default { return 'noop' }
    }
}

# ===================================================================== PI-68 BEGIN: duplicate hand-back guard
# A finished agent (status DONE) that keeps re-delivering the same hand-back shows up here as repeated identical DONE events
# (EVENT STATUS <n> DONE / DONE(quiet) / INBOX '<n> DONE' / TAIL-RELAY '<n> DONE'). The bot cannot see the SubagentHandback text itself;
# the hash covers the normalised event text PLUS the agent's status file (latest/outputs/next = the hand-back text the hook stored).
# State: <digest>\handback-seen\<agent>.txt = "<hash> <count> <emitted 0|1>". 1st event passes, 1st duplicate is swallowed (counted),
# the 2nd duplicate emits ONE line (the bot cannot TaskStop), further ones are swallowed. Differing text resets; non-DONE agents are never touched.
function Get-Pi68Agent([string]$item) {
    if ($item -match '^(?:(?:DONE|INFO): )?STATUS (?<n>\S+) DONE\b') { return $Matches['n'] }
    if ($item -match '^(?:(?:DONE|INFO): )?INBOX \S+: (?:TAIL-RELAY )?(?<n>[A-Za-z0-9][A-Za-z0-9._-]*) (?:DONE|TAILDONE)(?:[\s:]|$)') { return $Matches['n'] }
    return ''
}
function Test-Pi68Handback([string]$item) {
    $res = @{ Action = 'pass'; Agent = ''; N = 0; Line = '' }
    if ($script:NoActions) { return $res }
    try {
        $name = Get-Pi68Agent $item
        if (-not $name) { return $res }
        $st = Read-StatusFile $name
        if (-not $st -or $st.State -ne 'DONE') { return $res }
        $norm = ($item -replace '\d{4}-\d\d-\d\dT[\d:.\-]+(?:[+\-]\d\d:\d\d)?', '' -replace '^((?:DONE|INFO): )?INBOX \S+:', '$1INBOX:' -replace '\s+', ' ').Trim()
        $h = Get-LineKey ($norm + '|' + $st.Latest + '|' + $st.Outputs + '|' + $st.Next)
        $dir = Join-Path $script:DigestDir 'handback-seen'
        Ensure-Dir $dir
        $f = Join-Path $dir (($name -replace '[^A-Za-z0-9._-]', '_') + '.txt')
        $cnt = 0; $emitted = 0
        if (Test-Path -LiteralPath $f) {
            $p = ([IO.File]::ReadAllText($f, $script:Utf8).Trim() -split '\s+')
            if ($p.Count -ge 3 -and $p[0] -eq $h) { $cnt = [int]$p[1]; $emitted = [int]$p[2] }
        }
        $cnt++
        if ($cnt -eq 1) { $res.Action = 'pass' }
        elseif ($cnt -eq 2) { $res.Action = 'swallow' }
        elseif ($emitted -eq 0) { $res.Action = 'emit'; $emitted = 1; $res.Line = "DUPLICATE HANDBACK $name x${cnt}: TaskStop it" }
        else { $res.Action = 'swallow' }
        $res.Agent = $name; $res.N = $cnt
        [IO.File]::WriteAllText($f, "$h $cnt $emitted`n", $script:Utf8)
    } catch { Write-ChoreLog ("pi68 error: " + $_.Exception.Message); $res.Action = 'pass' }
    $res
}
# ===================================================================== PI-68 END

# ---------------------------------------------------------------- process one waker line
# returns @{ Auto = @(label...); Attention = @(line...) }
function Process-Line([string]$line) {
    $auto = @(); $att = @()
    if (-not $line.Trim()) { return @{ Auto = $auto; Attention = $att } }
    $key = Get-LineKey $line
    if ($script:SeenSet.Contains($key)) { return @{ Auto = @('replay skipped'); Attention = $att } }
    $sp = Split-WakerLine $line
    $judg = @()
    foreach ($it in $sp.Items) {
        $d68 = Test-Pi68Handback $it   # PI-68 duplicate hand-back guard
        if ($d68.Action -eq 'swallow') { $auto += 'dup handback swallowed'; continue }
        if ($d68.Action -eq 'emit') { $att += ($sp.Prefix + $d68.Line); continue }
        $c = $null
        try { $c = Classify-Item $it } catch { $c = @{ Class = 'JUDGMENT'; Rule = 'error'; Text = $it } }
        if ($c.Class -eq 'AUTO') {
            $r = ''
            try { $r = Do-Action $c } catch { $r = 'error: ' + $_.Exception.Message; Write-ChoreLog ("action error on '" + (Cut $it 120) + "': " + $_.Exception.Message) }
            if ($r -like 'error:*' -or $r -eq 'ack-failed' -or $r -like 'refused*') { $judg += $it }
            else {
                $lab = [string]$c.Label
                if ($c.Action -eq 'lane-ack' -and $r -ne 'acked') { $lab = 'alert already clear' }
                $auto += $lab
            }
        } else { $judg += $it }
    }
    if ($judg.Count -eq 0) {
        [void]$script:SeenSet.Add($key); $script:SeenOrder.Add($key)
    } elseif ($judg.Count -eq $sp.Items.Count -or $sp.Kind -eq 'other') {
        $att += $line.TrimEnd("`r", "`n")                                    # all items need the model: the original line, verbatim
        [void]$script:SeenSet.Add($key); $script:SeenOrder.Add($key)
    } else {
        foreach ($j in $judg) {                                              # mixed line: only the items that need the model
            if ($sp.Kind -eq 'lane') { $att += ($sp.Prefix + 'EVENT LANE ' + $j) }
            else { $att += ($sp.Prefix + 'EVENT DIGEST 1 of ' + $sp.Items.Count + ' items (the rest handled by coord-chores) ;; ' + $j) }
        }
        [void]$script:SeenSet.Add($key); $script:SeenOrder.Add($key)
    }
    @{ Auto = $auto; Attention = $att }
}

# ---------------------------------------------------------------- ack sweep over the alert ledger
function Invoke-AckSweep {
    $n = 0
    if ($script:NoActions) { return 0 }
    foreach ($a in @(Get-OpenAlerts $script:Runs)) {
        if (@($S.ackableKinds) -notcontains $a.Kind) { continue }
        $k = if ($a.Kind -eq 'lane-idle') { 'IDLE' } else { 'NO-OPERATOR' }
        $txt = $a.Text
        if ($txt -notmatch '^LANE (IDLE|NO-OPERATOR) ') { $txt = "LANE $k $($a.Subject) $txt" }
        $c = Classify-Item $txt
        if ($c.Class -ne 'AUTO' -or $c.Action -ne 'lane-ack') { continue }
        if ($DryRun) { Write-Host "would ack $($a.Id): $($c.Rule)"; continue }
        $r = Do-LaneAck $c
        if ($r -eq 'acked') { $n++ }
    }
    $n
}

# ---------------------------------------------------------------- register-new (agent id -> name)
function Get-IdsStore { Join-Path (Join-Path $script:Runs 'agents') 'ids.json' }
function Read-Ids {
    $h = @{}
    $p = Get-IdsStore
    if (Test-Path -LiteralPath $p) {
        try {
            $o = [IO.File]::ReadAllText($p, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ($o) { foreach ($q in $o.psobject.Properties) { $h[$q.Name] = $q.Value } }
        } catch { }
    }
    $h
}
$script:IdsAddFn = {
    param($name, $id, $session)
    if ($script:Runs -eq 'C:\KenshiTestRuns') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:Here 'agent-ids.ps1') add $name $id $session | Out-Null
    } else {
        $h = Read-Ids
        $h[$name] = @{ id = $id; session = $session; at = (Get-Date).ToString('s') }
        $tmp = (Get-IdsStore) + '.tmp'
        ($h | ConvertTo-Json -Depth 4) | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Force $tmp (Get-IdsStore)
    }
}
function Get-AgentNameFromRecord([string]$text, [string]$desc) {
    $t = if ($text.Length -gt 8000) { $text.Substring(0, 8000) } else { $text }
    foreach ($rx in @(
            'agent-status\.ps1\s+["'']?([A-Za-z0-9][A-Za-z0-9._-]*-[A-Za-z0-9._-]*[A-Za-z0-9])["'']?\s+(?:RUNNING|DONE)',
            'agents[\\/]+([A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])\.status',
            'You are ([A-Za-z0-9][A-Za-z0-9._-]*-[A-Za-z0-9._-]*[A-Za-z0-9])')) {
        $m = [regex]::Match($t, $rx)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    $m = [regex]::Match($desc, '\]\s+(\S+)\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
    ''
}
function Get-SubagentsDir {
    if ($SubagentsDir) { return $SubagentsDir }
    $sess = ''
    $cur = Join-Path $script:Runs 'coordinator.current'
    if (Test-Path -LiteralPath $cur) { try { $sess = [string](([IO.File]::ReadAllText($cur, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json).session) } catch { } }
    $base = Join-Path (Join-Path $env:USERPROFILE '.claude\projects') 'C--KenshiModding'
    if ($sess) { $d = Join-Path (Join-Path $base $sess) 'subagents'; if (Test-Path -LiteralPath $d) { return $d } }
    $c = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'subagents' } | Where-Object { Test-Path -LiteralPath $_ } |
        Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending | Select-Object -First 1
    if ($c) { return $c }
    ''
}
function Get-CoordSession {
    $cur = Join-Path $script:Runs 'coordinator.current'
    if (Test-Path -LiteralPath $cur) { try { return [string](([IO.File]::ReadAllText($cur, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json).session) } catch { } }
    ''
}
function Invoke-RegisterNew {
    $dir = Get-SubagentsDir
    $out = @()
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @('register-new: no subagents dir found') }
    $ids = Read-Ids
    $known = @{}; foreach ($k in $ids.Keys) { $known[[string]$ids[$k].id] = $k }
    $maxAge = (Get-Date).AddHours(-[double]$S.registerNew.maxAgeHours)
    $sess = Get-CoordSession
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'agent-*.jsonl' -File -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -gt $maxAge })) {
        $id = $f.BaseName.Substring(6)
        if ($known.ContainsKey($id)) { continue }
        if ($script:State.regTried.ContainsKey($id) -and $script:State.regTried[$id] -ge 60) { continue }
        $text = ''; $desc = ''
        try {
            $sr = New-Object IO.StreamReader($f.FullName, $script:Utf8)
            try { $first = $sr.ReadLine() } finally { $sr.Close() }
            $j = $first | ConvertFrom-Json
            $c = $j.message.content
            $text = if ($c -is [string]) { $c } else { (@($c) | ForEach-Object { $_.text }) -join ' ' }
            $mp = Join-Path $dir ($f.BaseName + '.meta.json')
            if (Test-Path -LiteralPath $mp) { $desc = [string](([IO.File]::ReadAllText($mp, $script:Utf8) | ConvertFrom-Json).description) }
        } catch { $script:State.regTried[$id] = 1 + [int]$script:State.regTried[$id]; continue }
        $name = Get-AgentNameFromRecord $text $desc
        if (-not $name) { $script:State.regTried[$id] = 99; $out += "unresolved $id (no name in prompt)"; continue }   # the prompt is the first record: it will never gain a name
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $script:Runs 'agents') ($name + '.status')))) {
            $script:State.regTried[$id] = 1 + [int]$script:State.regTried[$id]; $out += "pending $id -> $name (no status file yet)"; continue
        }
        if ($ids.ContainsKey($name)) {
            try { if ($f.CreationTime -le [datetime]$ids[$name].at) { $out += "skip $id -> $name (older than the recorded $($ids[$name].id))"; $script:State.regTried[$id] = 99; continue } } catch { }
        }
        if ($DryRun) { $out += "would register $name -> $id"; continue }
        try { & $script:IdsAddFn $name $id $sess; $out += "registered $name -> $id"; Write-ChoreLog "registered $name -> $id"; $known[$id] = $name; $ids[$name] = @{ id = $id; at = (Get-Date).ToString('s') } }
        catch { $out += "FAILED $name -> $id : $($_.Exception.Message)" }
    }
    if (-not $DryRun) { Save-State }
    $out
}

# ---------------------------------------------------------------- flush-to-live
function Invoke-FlushToLive {
    $date = if ($Date) { $Date } else { (Get-Date).ToString('yyyy-MM-dd') }
    $dp = Get-DigestPath $date
    if (-not (Test-Path -LiteralPath $dp)) { return "flush-to-live: no digest for $date" }
    $lines = @([IO.File]::ReadAllLines($dp, $script:Utf8) | Where-Object { $_ -like '- *' })
    $mark = $dp + '.flushed'
    $done = 0
    if (Test-Path -LiteralPath $mark) { try { $done = [int]([IO.File]::ReadAllText($mark).Trim()) } catch { $done = 0 } }
    if ($lines.Count -le $done) { return "flush-to-live: nothing new for $date ($done lines already flushed)" }
    $new = @($lines[$done..($lines.Count - 1)])
    $md = if ($LiveMd) { $LiveMd } else { Join-Path $Repo 'testing\COORDINATOR_LIVE.md' }
    if (-not (Test-Path -LiteralPath $md)) { return "flush-to-live: $md not found" }
    $block = "`n## Chores digest $date (auto, coord-chores.ps1; $($new.Count) lines)`n" + (($new -join "`n")) + "`n"
    if ($DryRun) { return ($block + "(dry run: nothing written)") }
    if (-not (Append-Text $md $block)) { return "flush-to-live: could not append to $md" }
    [IO.File]::WriteAllText($mark, [string]$lines.Count)
    if ($NoCommit) { return "flush-to-live: appended $($new.Count) lines to $md (no commit)" }
    $rel = (Resolve-Path -LiteralPath $md).Path.Substring((Resolve-Path -LiteralPath $Repo).Path.Length).TrimStart('\', '/') -replace '\\', '/'
    $msg = "live: chores digest $date ($($new.Count) auto-handled events, coord-chores)"
    $ok = $false; $last = ''
    for ($i = 0; $i -lt 6 -and -not $ok; $i++) {
        $last = (& git -C $Repo -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -m $msg -- $rel 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) { $ok = $true } elseif ($last -match 'index\.lock') { Start-Sleep -Seconds 2 } else { break }
    }
    if (-not $ok) { return "flush-to-live: appended, COMMIT FAILED: $(Cut $last 300)" }
    if ($NoPush) { return "flush-to-live: appended + committed $($new.Count) lines (no push)" }
    $po = (& git -C $Repo push origin main 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { return "flush-to-live: appended + committed, PUSH FAILED: $(Cut $po 300)" }
    "flush-to-live: appended + committed + pushed $($new.Count) lines to $rel"
}

# ---------------------------------------------------------------- stream
function Format-Summary($counts, [int]$attN, [string]$since) {
    $total = 0; foreach ($k in $counts.Keys) { $total += $counts[$k] }
    $parts = @(); foreach ($k in ($counts.Keys | Sort-Object { -$counts[$_] }, { $_ })) { $parts += ("{0} {1}" -f $counts[$k], $k) }
    $a = if ($attN -gt 0) { "ATTENTION: $attN" } else { 'ATTENTION: none' }
    $s = "CHORES: $total auto" + $(if ($parts.Count) { ' (' + ($parts -join ', ') + ')' } else { '' })
    if ($since) { $s += " since $since" }
    $s + ' | ' + $a
}
function Invoke-Stream {
    if (-not $InputFile) {   # single consumer: an older instance whose pipe is already dead exits by itself within seconds; wait for it
        $hbp = Join-Path $script:DigestDir 'chores.hb'
        for ($w = 0; $w -lt 12; $w++) {
            $other = 0
            try { if ((Test-Path -LiteralPath $hbp) -and ([IO.File]::ReadAllText($hbp) -match 'pid=(\d+)')) { $other = [int]$Matches[1] } } catch { }
            if ($other -le 0 -or $other -eq $PID -or -not (Get-Process -Id $other -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Seconds 1
        }
    }
    Load-State
    Ensure-Dir $script:DigestDir
    try { [Console]::OutputEncoding = $script:Utf8 } catch { }
    $reader = $null
    if ($InputFile) { $reader = New-Object IO.StreamReader($InputFile, $script:Utf8) }
    else { $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), $script:Utf8) }
    $counts = @{}; $att = New-Object System.Collections.Generic.List[string]
    $st = @{ firstAtt = $null; lastAtt = $null; since = (Get-Date).ToString('HH:mm'); lastPrint = Get-Date }
    $lastHb = [datetime]::MinValue; $lastAck = Get-Date; $lastReg = Get-Date
    $task = $null
    $out = [Console]::Out
    $flush = {
        param([bool]$force)
        $now = Get-Date
        $due = $false
        if ($att.Count -gt 0) {
            if ($force -or (($now - $st.lastAtt).TotalSeconds -ge [double]$S.attentionCoalesceSec) -or (($now - $st.firstAtt).TotalSeconds -ge [double]$S.attentionMaxHoldSec)) { $due = $true }
        } elseif ($counts.Count -gt 0 -and [double]$S.autoOnlyLineEveryMin -gt 0 -and (($now - $st.lastPrint).TotalMinutes -ge [double]$S.autoOnlyLineEveryMin)) { $due = $true }
        elseif ($force -and $counts.Count -gt 0) { $due = $true }
        if (-not $due) { return }
        foreach ($x in $script:ExtraAuto) { if ($counts.ContainsKey($x)) { $counts[$x]++ } else { $counts[$x] = 1 } }
        $script:ExtraAuto.Clear()
        $out.WriteLine((Format-Summary $counts $att.Count $st.since))
        foreach ($a in $script:Acks) { $out.WriteLine($a) }
        foreach ($l in $att) { $out.WriteLine($l) }
        $out.Flush()
        $counts.Clear(); $att.Clear(); $script:Acks.Clear(); $st.firstAtt = $null; $st.lastAtt = $null
        $st.since = (Get-Date).ToString('HH:mm'); $st.lastPrint = Get-Date
        Save-State
    }
    $handle = {
        param([string]$line)
        $r = $null
        try { $r = Process-Line $line }
        catch { $r = @{ Auto = @(); Attention = @("[chores-error: " + $_.Exception.Message + "] " + $line) } ; Write-ChoreLog ("process error: " + $_.Exception.Message) }
        foreach ($a in $r.Auto) { if ($counts.ContainsKey($a)) { $counts[$a]++ } else { $counts[$a] = 1 } }
        foreach ($x in $script:ExtraAuto) { if ($counts.ContainsKey($x)) { $counts[$x]++ } else { $counts[$x] = 1 } }
        $script:ExtraAuto.Clear()
        foreach ($l in $r.Attention) { $att.Add($l); if (-not $st.firstAtt) { $st.firstAtt = Get-Date }; $st.lastAtt = Get-Date }
    }
    while ($true) {
        $line = $null; $got = $false
        if ($InputFile) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            $got = $true
        } else {
            if (-not $task) { $task = $reader.ReadLineAsync() }
            if ($task.Wait(1000)) {
                try { $line = $task.Result } catch { $line = $null }
                $task = $null
                if ($null -eq $line) { break }
                $got = $true
            }
        }
        if ($got) { & $handle $line }
        if (-not $InputFile) {
            $now = Get-Date
            if (($now - $lastHb).TotalSeconds -ge 10) {
                $lastHb = $now
                try { [IO.File]::WriteAllText((Join-Path $script:DigestDir 'chores.hb'), "pid=$PID epoch=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) at=$($now.ToString('s'))`n") } catch { }
            }
            if (($now - $lastAck).TotalSeconds -ge [double]$S.ackSweepEverySec) {
                $lastAck = $now
                try { $n = Invoke-AckSweep; if ($n -gt 0) { $lbl = 'alert acked'; if ($counts.ContainsKey($lbl)) { $counts[$lbl] += $n } else { $counts[$lbl] = $n } } } catch { Write-ChoreLog ("ack-sweep error: " + $_.Exception.Message) }
            }
            if ([bool]$S.registerNew.enabled -and (($now - $lastReg).TotalSeconds -ge [double]$S.registerNew.everySec)) {
                $lastReg = $now
                try { $o = @(Invoke-RegisterNew | Where-Object { $_ -like 'registered *' }); if ($o.Count) { $lbl = 'agent id registered'; if ($counts.ContainsKey($lbl)) { $counts[$lbl] += $o.Count } else { $counts[$lbl] = $o.Count } } } catch { Write-ChoreLog ("register-new error: " + $_.Exception.Message) }
            }
            # ==== PI-49 SNAG-SCAN BEGIN (self-contained; merge as one block; needs snag-scan.ps1 next to this script) ====
            # Every 60 s: read-only count of C:\KenshiTestRuns\snags\snags.log; a 'SNAG REPEAT ...' line (2nd distinct operator on one
            # script:line, again only for a 3rd) is queued as an ATTENTION line = one wake. Nothing else is printed. Errors never leak.
            if (-not $lastSnag) { $lastSnag = [datetime]::MinValue }
            if (($now - $lastSnag).TotalSeconds -ge 60) {
                $lastSnag = $now
                try {
                    foreach ($sl in @(& (Join-Path $PSScriptRoot 'snag-scan.ps1') -Runs $script:Runs | Where-Object { $_ -like 'SNAG REPEAT *' })) {
                        $att.Add([string]$sl); if (-not $st.firstAtt) { $st.firstAtt = Get-Date }; $st.lastAtt = Get-Date
                        Write-ChoreLog ([string]$sl)
                    }
                } catch { Write-ChoreLog ("snag-scan error: " + $_.Exception.Message) }
            }
            # ==== PI-49 SNAG-SCAN END ====
        }
        & $flush $false
    }
    & $flush $true
    Save-State
}

function Invoke-Classify {
    if (-not $InputFile) { Write-Error 'classify needs -InputFile'; return }
    $script:NoActions = $true
    foreach ($line in [IO.File]::ReadAllLines($InputFile, $script:Utf8)) {
        if (-not $line.Trim()) { continue }
        $sp = Split-WakerLine $line
        foreach ($it in $sp.Items) {
            $c = Classify-Item $it
            ('{0,-8} {1,-24} {2}' -f $c.Class, $c.Rule, (Cut $it 150))
        }
    }
}

if ($LibOnly) { return }
switch ($Command.ToLower()) {
    'stream' { Invoke-Stream }
    'classify' { Invoke-Classify }
    'register-new' { Load-State; Invoke-RegisterNew | ForEach-Object { Write-Output $_ } }
    'ack-sweep' { Load-State; $n = Invoke-AckSweep; Write-Output "ack-sweep: $n acked" }
    'flush-to-live' { Invoke-FlushToLive }
    'status' {
        $hb = Join-Path $script:DigestDir 'chores.hb'
        $age = if (Test-Path -LiteralPath $hb) { [int]((Get-Date) - (Get-Item -LiteralPath $hb).LastWriteTime).TotalSeconds } else { -1 }
        $dp = Get-DigestPath
        $n = if (Test-Path -LiteralPath $dp) { @([IO.File]::ReadAllLines($dp) | Where-Object { $_ -like '- *' }).Count } else { 0 }
        "CHORES hb_age=${age}s digest=$dp lines=$n"
    }
    default { Write-Error "unknown command '$Command' (stream|classify|register-new|ack-sweep|flush-to-live|status)"; exit 2 }
}
