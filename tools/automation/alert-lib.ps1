# alert-lib.ps1: open-alert ledger (PI-21, Shay 2026-10-15). Dot-source it:  . C:\KenshiModding\tools\automation\alert-lib.ps1
# Why: on 2026-10-15 a 'LANE IDLE 4080-i4 7m' waker event arrived while the coordinator was mid-edit and nothing tracked whether anyone
# acted on it; the 5090-i4 lane then sat idle 16.7 min until Shay asked. The waker alerts once; this ledger keeps every urgent alert OPEN
# until somebody acts (alert-ack.ps1) or the condition clears by itself.
#
# Layout (root = $env:KAH_RUNS_DIR, default C:\KenshiTestRuns):
#   alerts\open\<id>.json      {id, kind, subject, text, source(lane|report|msg|llm), opened_at, last_seen}
#   alerts\closed\<id>-<stamp>.json   the same + closed_at, closed_by (ack|cleared), action (ack text or 'cleared: <why>')
#   alerts\acked\<id>.json     {acked_at, action}: an ack closes the alert but the SAME incident (condition still true) is not re-opened for
#                              AckHoldMin (30) min; after that, or after the condition cleared and came back, it opens again. Ack never hides a later alert.
#   alerts\scan.stamp / scan.lock / seen.json / stop-block.json / cap-ends.log   (rate limit, mutex, handled inbox messages, Stop-hook loop cap, cap log)
#   inbox\operators\<lane>-alert.txt   the lane's open alerts for its operator (removed when none is open)
# id = <kind>-<subject> lower-case (lane-idle-5090-i4, agent-orphaned-imm26-x, agent-failed-x, llm-health-fail-llm).
#
# Sources (read only; the same ones the waker uses, event-wait.sh / event-stream.sh are NOT touched):
#   lane-idle.ps1 -NoMemory                      LANE IDLE / LANE NO-OPERATOR / LANE STALLED   cleared when the lane is reported active (STALLED: when status or evidence is fresh again)
#                                                LANE STALLED = HARD alert kind lane-stalled (operator status AND evidence silent > 12 min): alert-ack.ps1 refuses a plain
#                                                ack (needs 'stopped'/'respawned' or an evidence path newer than 5 min, Test-StalledAckProof); the Stop hook blocks the coordinator after 3 min
#   agent-guard-lib Get-AgentReport              ORPHANED, FAILED / STOPPED-CONTEXT with no successor   cleared on DONE / successor / abandoned / fresh status
#   inbox\coordinator\*.msg + delivered\*.msg    AGENT STALL|ORPHANED|DEAD|KILLED|WALL-CLOCK <name>, LLM-HEALTH FAIL / PREFLIGHT-FAIL llm
#                                                (messages < 90 min old, each handled once); cleared by the agent state (see Test-MsgAgentBad) / llm-health OK
# Consumers: alert-scan.ps1 -Hook (PostToolUse reminder), hooks\kenshi-waker-guard.ps1 (Stop block for the coordinator), session-start.ps1.
# Everything FAILS OPEN: any error yields no alert / no block. Test seams: KAH_RUNS_DIR, KAH_ALERT_LLM_OUT (literal llm-health output line).

$script:AlertLibDir = $PSScriptRoot
try { . (Join-Path $PSScriptRoot 'agent-guard-lib.ps1') } catch { }
$script:AlertScanSec = 60
$script:AlertAckHoldMin = 30
$script:AlertMsgWindowMin = 90
$script:AlertHardKinds = @('lane-stalled')          # hard alerts: Stop block after 3 min (others 5), ack needs proof
$script:AlertHardMinAge = 3

function Get-AlertRuns { if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' } }
function Get-AlertDir([string]$runs) { $d = Join-Path $runs 'alerts'; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; $d }
function Get-AlertSub([string]$runs, [string]$sub) { $d = Join-Path (Join-Path $runs 'alerts') $sub; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; $d }
function ConvertTo-AlertId([string]$kind, [string]$subject) { (($kind + '-' + $subject).ToLowerInvariant() -replace '[^a-z0-9._-]+', '_') }
function ConvertTo-AlertTime($v) {
    if ($v -is [datetime]) { return $v }
    try { return [datetime]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture) } catch { return (Get-Date) }
}
function Format-AlertTime([datetime]$t) { $t.ToString('yyyy-MM-ddTHH:mm:ss') }
function Write-AlertJson([string]$path, $obj) {
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}
function Read-AlertJson([string]$path) { try { Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { $null } }

# open alerts, oldest first: objects with Id Kind Subject Text Source OpenedAt LastSeen AgeMin
function Get-OpenAlerts([string]$Runs = '', [datetime]$Now = (Get-Date)) {
    if (-not $Runs) { $Runs = Get-AlertRuns }
    $d = Join-Path (Join-Path $Runs 'alerts') 'open'
    if (-not (Test-Path -LiteralPath $d)) { return @() }
    $out = @()
    foreach ($f in Get-ChildItem -LiteralPath $d -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        $j = Read-AlertJson $f.FullName
        if (-not $j -or -not $j.id) { continue }
        $o = ConvertTo-AlertTime $j.opened_at
        $out += [pscustomobject]@{ Id = [string]$j.id; Kind = [string]$j.kind; Subject = [string]$j.subject; Text = [string]$j.text; Source = [string]$j.source
            OpenedAt = $o; LastSeen = (ConvertTo-AlertTime $j.last_seen); AgeMin = [math]::Round(($Now - $o).TotalMinutes, 1) }
    }
    @($out | Sort-Object OpenedAt)
}

function Close-Alert([string]$Runs, [string]$Id, [string]$By, [string]$Action, [datetime]$Now = (Get-Date)) {
    $op = Join-Path (Get-AlertSub $Runs 'open') "$Id.json"
    $j = Read-AlertJson $op
    if (-not $j) { return $false }
    $o = [ordered]@{}; foreach ($p in $j.psobject.Properties) { $o[$p.Name] = $p.Value }
    $o['closed_at'] = Format-AlertTime $Now; $o['closed_by'] = $By; $o['action'] = $Action
    Write-AlertJson (Join-Path (Get-AlertSub $Runs 'closed') ("$Id-" + $Now.ToString('yyyyMMdd-HHmmss') + '.json')) $o
    Remove-Item -LiteralPath $op -Force -ErrorAction SilentlyContinue
    if ($By -eq 'ack') { Write-AlertJson (Join-Path (Get-AlertSub $Runs 'acked') "$Id.json") ([ordered]@{ id = $Id; acked_at = (Format-AlertTime $Now); action = $Action }) }
    $true
}

# inbox\operators\<lane>-alert.txt for every lane with open lane alerts; stale ones (first line '# alert-ledger') removed
function Update-OperatorAlertFiles([string]$Runs) {
    try {
        $od = Join-Path (Join-Path $Runs 'inbox') 'operators'
        $open = @(Get-OpenAlerts $Runs | Where-Object { $_.Kind -like 'lane-*' })
        $lanes = @($open | ForEach-Object Subject | Select-Object -Unique)
        foreach ($l in $lanes) {
            if (-not (Test-Path -LiteralPath $od)) { New-Item -ItemType Directory -Force -Path $od | Out-Null }
            $lines = @('# alert-ledger (PI-21): open alert(s) for lane ' + $l + '. Act on them, then: powershell -NoProfile -File C:\KenshiModding\tools\automation\alert-ack.ps1 <id> "<action taken>"')
            foreach ($a in ($open | Where-Object { $_.Subject -eq $l })) { $lines += "$($a.Id) | open $([int]$a.AgeMin) min | $($a.Text)" }
            [IO.File]::WriteAllText((Join-Path $od "$l-alert.txt"), (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
        }
        if (Test-Path -LiteralPath $od) {
            foreach ($f in Get-ChildItem -LiteralPath $od -Filter '*-alert.txt' -File -ErrorAction SilentlyContinue) {
                $l = $f.Name -replace '-alert\.txt$', ''
                if ($lanes -contains $l) { continue }
                $first = Get-Content -LiteralPath $f.FullName -TotalCount 1 -ErrorAction SilentlyContinue
                if ([string]$first -like '# alert-ledger*') { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
            }
        }
    } catch { }
}

# Ack proof for a hard alert (lane-stalled): the action text must say the operator was 'stopped' or 'respawned', or name an existing file path
# (after the word 'evidence') whose LastWriteTime is < 5 min old. Returns $true / $false.
function Test-StalledAckProof([string]$Action, [datetime]$Now = (Get-Date)) {
    try {
        if ($Action -match '(?i)\b(stopped|respawned)\b') { return $true }
        if ($Action -match '(?i)\bevidence\b') {
            foreach ($m in [regex]::Matches($Action, '[A-Za-z]:\\[^\s"'',;|]+')) {
                if ((Test-Path -LiteralPath $m.Value) -and (($Now - (Get-Item -LiteralPath $m.Value).LastWriteTime).TotalMinutes -lt 5)) { return $true }
            }
        }
    } catch { }
    $false
}

# does the agent named in a STALL / ORPHANED / DEAD / KILLED / WALL-CLOCK message still need attention? ($ar = Get-AgentReport result)
function Test-MsgAgentBad([string]$Runs, [string]$Kind, [string]$Name, [datetime]$OpenedAt, $ar, [datetime]$Now) {
    try {
        $sf = Get-Item -LiteralPath (Join-Path (Join-Path $Runs 'agents') "$Name.status") -ErrorAction Stop
        $rec = Read-AgentRecord $sf
        if (-not $rec) { return $false }
        if ($rec.Abandoned -or $rec.State -eq 'DONE') { return $false }
        if ($rec.State -eq 'RUNNING') {
            if ($rec.Mtime -gt $OpenedAt) { return $false }                                   # status rewritten since the alert: alive
            if ($Kind -in 'stall', 'orphaned') {
                $ev = Get-AgentEvidenceAgeMin $Name $Now $Runs
                if ($null -ne $ev -and $ev -lt 10) { return $false }                           # own evidence fresh (PI-17 filter, same as event-wait.sh)
            }
            return $true
        }
        # FAILED / STOPPED-CONTEXT: still needs attention only while it has no successor
        return (@($ar.OpenRecent | Where-Object { $_.Name -eq $Name }).Count -gt 0)
    } catch { $false }
}

# One scan. Returns @{Skipped; Opened; Closed; Open}. Rate-limited to once per 60 s unless -Force. Mutex: alerts\scan.lock (stale after 120 s).
function Invoke-AlertScan {
    param([string]$Runs = '', [switch]$Force, [datetime]$Now = (Get-Date))
    $res = @{ Skipped = $false; Opened = @(); Closed = @(); Open = 0 }
    $lockPath = $null
    try {
        if (-not $Runs) { $Runs = Get-AlertRuns }
        $ad = Join-Path $Runs 'alerts'
        foreach ($s in 'open', 'closed', 'acked') { [void](Get-AlertSub $Runs $s) }
        $stamp = Join-Path $ad 'scan.stamp'
        if (-not $Force -and (Test-Path -LiteralPath $stamp) -and (((Get-Date) - (Get-Item -LiteralPath $stamp).LastWriteTime).TotalSeconds -lt $script:AlertScanSec)) { $res.Skipped = $true; return $res }
        $lockPath = Join-Path $ad 'scan.lock'
        if (Test-Path -LiteralPath $lockPath) {
            if (((Get-Date) - (Get-Item -LiteralPath $lockPath).LastWriteTime).TotalSeconds -lt 120) { $res.Skipped = $true; $lockPath = $null; return $res }
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
        try { $fs = [IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None'); $fs.Close() } catch { $res.Skipped = $true; $lockPath = $null; return $res }
        [IO.File]::WriteAllText($stamp, (Format-AlertTime (Get-Date)))
        (Get-Item -LiteralPath $stamp).LastWriteTime = Get-Date

        $conds = @{}           # id -> @{Kind;Subject;Text;Source;OpenedAt}
        $laneOk = $false; $agentsOk = $false
        # 1. lanes
        try {
            $li = @(& (Join-Path $script:AlertLibDir 'lane-idle.ps1') -NoMemory -Runs $Runs 2>&1 | ForEach-Object { "$_" })
            $seenLine = $false
            foreach ($l in $li) {
                if ($l -match '^LANE (IDLE|NO-OPERATOR|STALLED) (\S+)') {
                    $k = 'lane-' + $Matches[1].ToLowerInvariant(); $sub = $Matches[2]; $seenLine = $true
                    $conds[(ConvertTo-AlertId $k $sub)] = @{ Kind = $k; Subject = $sub; Text = ($l.Substring(0, [Math]::Min($(if ($k -in $script:AlertHardKinds) { 900 } else { 300 }), $l.Length))); Source = 'lane'; OpenedAt = $null }
                } elseif ($l -match '^LANES ACTIVE') { $seenLine = $true }
            }
            $laneOk = $seenLine
        } catch { }
        # 2. agents (report) + 3. inbox messages
        $ar = $null
        try {
            $old = $env:KAH_RUNS_DIR; $env:KAH_RUNS_DIR = $Runs
            try { $ar = Get-AgentReport -AgentsDir (Join-Path $Runs 'agents') -Now $Now } finally { if ($null -eq $old) { Remove-Item Env:KAH_RUNS_DIR -ErrorAction SilentlyContinue } else { $env:KAH_RUNS_DIR = $old } }
            foreach ($r in $ar.Orphaned) {
                $id = ConvertTo-AlertId 'agent-orphaned' $r.Name
                $conds[$id] = @{ Kind = 'agent-orphaned'; Subject = $r.Name; Text = "AGENT ORPHANED $($r.Name): status RUNNING, silent $([int]($Now - $r.Mtime).TotalMinutes) min. Latest: $($r.Latest)"; Source = 'report'; OpenedAt = $null }
            }
            foreach ($r in $ar.OpenRecent) {
                $k = 'agent-' + $r.State.ToLowerInvariant()
                $conds[(ConvertTo-AlertId $k $r.Name)] = @{ Kind = $k; Subject = $r.Name; Text = "$($r.State) $($r.Name) with no successor (updated $([int]($Now - $r.Mtime).TotalMinutes) min ago). Latest: $($r.Latest)"; Source = 'report'; OpenedAt = $null }
            }
            $agentsOk = $true
        } catch { }
        $seenF = Join-Path $ad 'seen.json'
        $seen = @{}
        $sj = Read-AlertJson $seenF
        if ($sj) { foreach ($p in $sj.psobject.Properties) { $seen[$p.Name] = [string]$p.Value } }
        $llmMsg = $false
        try {
            $cd = Join-Path (Join-Path $Runs 'inbox') 'coordinator'
            $files = @()
            if (Test-Path -LiteralPath $cd) {
                $files += @(Get-ChildItem -LiteralPath $cd -Filter '*.msg' -File -ErrorAction SilentlyContinue)
                $dd = Join-Path $cd 'delivered'
                if (Test-Path -LiteralPath $dd) { $files += @(Get-ChildItem -LiteralPath $dd -Filter '*.msg' -File -ErrorAction SilentlyContinue) }
            }
            foreach ($f in ($files | Where-Object { ($Now - $_.LastWriteTime).TotalMinutes -lt $script:AlertMsgWindowMin })) {
                if ($seen.ContainsKey($f.Name)) { continue }
                $seen[$f.Name] = (Format-AlertTime $Now)
                $txt = (Get-Content -LiteralPath $f.FullName -TotalCount 3 -Encoding UTF8 -ErrorAction SilentlyContinue) -join ' '
                if ($txt.Length -gt 400) { $txt = $txt.Substring(0, 400) }
                if ($txt -match '^\s*AGENT\s+(STALL|ORPHANED|DEAD|KILLED|WALL-CLOCK)\s+([A-Za-z0-9._-]+)') {
                    $k = 'agent-' + $Matches[1].ToLowerInvariant(); $nm = $Matches[2]
                    if (Test-MsgAgentBad $Runs $Matches[1].ToLowerInvariant() $nm $f.LastWriteTime $ar $Now) {
                        $id = ConvertTo-AlertId $k $nm
                        if (-not $conds.ContainsKey($id)) { $conds[$id] = @{ Kind = $k; Subject = $nm; Text = $txt.Trim(); Source = 'msg'; OpenedAt = $f.LastWriteTime } }
                    }
                } elseif ($txt -match 'LLM-HEALTH FAIL|PREFLIGHT-FAIL llm') { $llmMsg = $true }
            }
            # forget handled-message names older than 6 h
            foreach ($k in @($seen.Keys)) { if (((Get-Date) - (ConvertTo-AlertTime $seen[$k])).TotalHours -gt 6) { $seen.Remove($k) } }
            Write-AlertJson $seenF $seen
        } catch { }
        # re-check open message-sourced agent alerts (the message is not seen again)
        foreach ($a in (Get-OpenAlerts $Runs $Now | Where-Object { $_.Source -eq 'msg' -and $_.Kind -like 'agent-*' })) {
            if ($conds.ContainsKey($a.Id)) { continue }
            if (Test-MsgAgentBad $Runs ($a.Kind -replace '^agent-', '') $a.Subject $a.OpenedAt $ar $Now) {
                $conds[$a.Id] = @{ Kind = $a.Kind; Subject = $a.Subject; Text = $a.Text; Source = 'msg'; OpenedAt = $a.OpenedAt }
            }
        }
        # 4. LLM health: only checked when a message reported it or an llm alert is open (a network call); FAIL holds, anything else clears
        $llmId = ConvertTo-AlertId 'llm-health-fail' 'llm'
        if ($llmMsg -or (Test-Path -LiteralPath (Join-Path (Join-Path $ad 'open') "$llmId.json"))) {
            $line = ''
            try {
                if ($env:KAH_ALERT_LLM_OUT) { $line = $env:KAH_ALERT_LLM_OUT }
                else { $line = [string](& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:AlertLibDir 'llm-health.ps1') -NoCache 2>&1 | Select-Object -Last 1) }
            } catch { $line = 'LLM-HEALTH FAIL http=000 check failed' }
            if ($line -match '^LLM-HEALTH FAIL') { $conds[$llmId] = @{ Kind = 'llm-health-fail'; Subject = 'llm'; Text = $line.Trim(); Source = 'llm'; OpenedAt = $null } }
        }

        # reconcile
        $openDir = Get-AlertSub $Runs 'open'; $ackDir = Get-AlertSub $Runs 'acked'
        foreach ($id in $conds.Keys) {
            $c = $conds[$id]
            $op = Join-Path $openDir "$id.json"
            $ex = Read-AlertJson $op
            if ($ex) {
                $o = [ordered]@{}; foreach ($p in $ex.psobject.Properties) { $o[$p.Name] = $p.Value }
                $o['last_seen'] = (Format-AlertTime $Now); $o['text'] = $c.Text
                if ($c.OpenedAt -and (ConvertTo-AlertTime $o['opened_at']) -gt $c.OpenedAt) { $o['opened_at'] = (Format-AlertTime $c.OpenedAt) }
                Write-AlertJson $op $o
                continue
            }
            $ak = Join-Path $ackDir "$id.json"
            $aj = Read-AlertJson $ak
            $txt = $c.Text
            if ($aj) {
                if (($Now - (ConvertTo-AlertTime $aj.acked_at)).TotalMinutes -lt $script:AlertAckHoldMin) { continue }   # acknowledged: same incident, held
                Remove-Item -LiteralPath $ak -Force -ErrorAction SilentlyContinue
                $txt = "[still true $($script:AlertAckHoldMin)+ min after ack '$($aj.action)'] " + $txt
            }
            $opened = if ($c.OpenedAt) { $c.OpenedAt } else { $Now }
            Write-AlertJson $op ([ordered]@{ id = $id; kind = $c.Kind; subject = $c.Subject; text = $txt; source = $c.Source; opened_at = (Format-AlertTime $opened); last_seen = (Format-AlertTime $Now) })
            $res.Opened += $id
        }
        foreach ($a in (Get-OpenAlerts $Runs $Now)) {
            if ($conds.ContainsKey($a.Id)) { continue }
            if ($a.Source -eq 'lane' -and -not $laneOk) { continue }                                  # lane check failed: keep
            if ($a.Source -in 'report', 'msg' -and -not $agentsOk) { continue }
            [void](Close-Alert $Runs $a.Id 'cleared' 'cleared: condition no longer reported' $Now)
            $res.Closed += $a.Id
        }
        # an incident that ended releases its ack hold (so a later recurrence alerts again)
        foreach ($f in Get-ChildItem -LiteralPath $ackDir -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            $id = $f.BaseName
            if ($conds.ContainsKey($id)) { continue }
            if ($id -like 'lane-*' -and -not $laneOk) { continue }
            if ($id -like 'agent-*' -and -not $agentsOk) { continue }
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
        Update-OperatorAlertFiles $Runs
        $res.Open = @(Get-OpenAlerts $Runs $Now).Count
    } catch { }
    finally { if ($lockPath) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } }
    $res
}

# one reminder line, only when an alert is older than 3 min; '' otherwise
function Get-AlertReminder([string]$Runs = '', [datetime]$Now = (Get-Date), [int]$MinAge = 3) {
    try {
        $open = @(Get-OpenAlerts $Runs $Now)
        if (-not ($open | Where-Object { $_.AgeMin -gt $MinAge })) { return '' }
        $ids = @($open | Select-Object -First 3 | ForEach-Object Id)
        $more = if ($open.Count -gt 3) { " +$($open.Count - 3) more" } else { '' }
        "[open-alerts: $($open.Count), oldest $([int]$open[0].AgeMin) min: $($ids -join ', ')$more | act, then: tools/automation/alert-ack.ps1 <id> `"<action taken>`"]"
    } catch { '' }
}

# Stop-hook verdict for the COORDINATOR: block while an alert is older than 5 min and unacked. Loop cap: after 3 consecutive blocks for the
# same alert-id set (nothing changed) the 4th attempt is let through ONCE and logged to alerts\cap-ends.log, then the count restarts.
function Get-AlertStopVerdict([string]$Runs = '', [datetime]$Now = (Get-Date), [int]$MinAge = 5, [int]$Cap = 3) {
    $v = @{ Block = $false; Message = ''; Ids = @(); Capped = $false }
    try {
        if (-not $Runs) { $Runs = Get-AlertRuns }
        $sf = Join-Path (Get-AlertDir $Runs) 'stop-block.json'
        $old = @(Get-OpenAlerts $Runs $Now | Where-Object { $_.AgeMin -ge $(if ($_.Kind -in $script:AlertHardKinds) { [Math]::Min($MinAge, $script:AlertHardMinAge) } else { $MinAge }) })
        if (-not $old.Count) { Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue; return $v }
        $ids = @($old | ForEach-Object Id | Sort-Object)
        $sig = $ids -join '|'
        $st = Read-AlertJson $sf
        $prev = if ($st -and [string]$st.sig -eq $sig) { [int]$st.count } else { 0 }
        if ($prev -ge $Cap) {
            Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue
            Add-Content -LiteralPath (Join-Path (Get-AlertDir $Runs) 'cap-ends.log') -Value ("$(Format-AlertTime $Now) Stop let through after $Cap blocks with nothing changed: $sig") -ErrorAction SilentlyContinue
            $v.Capped = $true; $v.Ids = $ids
            return $v
        }
        Write-AlertJson $sf ([ordered]@{ sig = $sig; count = ($prev + 1); at = (Format-AlertTime $Now) })
        $parts = @($old | Select-Object -First 5 | ForEach-Object { "$($_.Id) ($([int]$_.AgeMin) min: $($_.Text.Substring(0, [Math]::Min(110, $_.Text.Length))))" })
        $more = if ($old.Count -gt 5) { " (+$($old.Count - 5) more)" } else { '' }
        $v.Block = $true; $v.Ids = $ids
        $v.Message = "$($old.Count) open alert(s) older than $MinAge min and not acked: " + ($parts -join ' || ') + $more + ". The waker raised them and nothing recorded an action. Act on each (or confirm it is a false alarm), then close it with: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\alert-ack.ps1 <id> `"<action taken>`" (an ack closes it; an alert whose condition clears closes itself; a lane-stalled alert is a HARD alert, its ack is refused unless the action says 'stopped' or 'respawned' or names an 'evidence' file path newer than 5 min). Block $($prev + 1) of $Cap for this alert set; after $Cap unchanged blocks the hook lets one stop through and logs it."
    } catch { }
    $v
}

# session-start -Brief lines (cap 6)
function Get-AlertBriefLines([string]$Runs = '', [int]$Max = 6) {
    try {
        $open = @(Get-OpenAlerts $Runs)
        if (-not $open.Count) { return @() }
        $out = @("=== OPEN ALERTS ($($open.Count); close with tools/automation/alert-ack.ps1 <id> `"<action>`") ===")
        $show = if ($open.Count -le $Max - 1) { $open.Count } else { $Max - 2 }
        foreach ($a in ($open | Select-Object -First $show)) { $out += "  $($a.Id) | $([int]$a.AgeMin) min | $($a.Text.Substring(0, [Math]::Min(150, $a.Text.Length)))" }
        if ($open.Count -gt $show) { $out += "  ($($open.Count - $show) more: alert-scan.ps1 -List)" }
        $out
    } catch { @() }
}
