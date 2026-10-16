# agent-guard-lib.ps1: shared logic for "agent work is not lost or stalled at a context handoff" (Shay 2026-10-15).
# Dot-source it:  . C:\KenshiModding\tools\automation\agent-guard-lib.ps1
# Used by hooks\kenshi-waker-guard.ps1 (Stop hook), session-start.ps1 and agent-status.ps1. Selftest: agent-guard-selftest.ps1.
# Everything here FAILS OPEN: an unreadable / malformed status file is skipped, any error yields an empty report, never a block.
#
#   Get-AgentReport [-AgentsDir <dir>] [-Now <time>]   -> object with
#       InFlight   RUNNING statuses updated < 45 min ago (work claimed: the waker rule applies)
#       Orphaned   RUNNING statuses with no update for >= 30 min and no successor (parent session gone?), unless an in-session
#                  agent (no <name>.session.json) wrote its OWN evidence < 10 min ago (PI-17, below)
#       Open       STOPPED-CONTEXT / FAILED statuses with no successor and not abandoned
#       OpenRecent same, updated within 18 h (the Stop hook blocks only on these; older ones are listed by session-start only)
#   Test-AgentSuccessor $x $s    true when status record $s continues the work of $x (see below)
#   Get-AgentRespawn $rec        exact respawn text for one record
#
# Successor rules (X = stopped/failed/orphaned record, S = another record updated at or after X):
#   (a) S.name = X.name + one suffix char: 2-9 or b-z, optionally after - or _   (wpA -> wpA2/wpA3, N2 -> N2b -> N2c, wpC1 -> wpC1b -> wpC1c, x -> x-2); a later sibling letter after a digit also counts (N2b -> N2c)
#   (b) same name stem, bigger trailing number (op1 -> op2) and the tasks match: equal / one contains the other, or X's task was
#       rewritten to "orphaned: ..." (then the task is unknown, the name decides)
#   (c) S is DONE and its task equals / contains X's task
#   (f) PI-33 (2026-10-16): S (RUNNING or DONE) names X as a whole word in its task/latest/next/outputs, or S has X's stem with a bigger trailing
#       number and shares a row id (NN-x) with X's task/latest/next text
#   (e) ledger tie (PI-11, Shay 2026-10-15): X is STOPPED-CONTEXT/FAILED, S is RUNNING with a status updated < 45 min ago and S.Mtime >= X.Mtime, and
#       the program ledger (programs\*.json) ties them to the same work package (X and S both among a wp's agent / successors / agent_records)
#       or to the same lane (lane-idle.ps1 lane table + lane-owners.json ops). If X sits in a lane and S sits in a DIFFERENT lane, the shared wp
#       does not count. Any read/parse error => rule (e) does not apply. Get-AgentReport.Accepted / Get-AgentAcceptedLines say which
#       successor was accepted and why ("accepted successor S for X via ledger wp W"). `agent-successor.ps1 <old> <new>` registers a pair.
# Own-evidence rule (PI-17, Shay 2026-10-15): a RUNNING in-session (INPROC: no <name>.session.json) agent whose status is silent >= 30 min is NOT orphaned
#   (and counts as InFlight) when its own evidence was written < EvidenceMin (10) min ago. Own evidence = agents\out\<name>.log, files under agents\out\<name>\,
#   and files under the lane out dirs of every lane-owners.json entry whose ops list contains the name. NEVER the .status file, never any other file in the tree,
#   so another process touching a directory cannot hide a dead agent. No evidence / old evidence / any read error => the 30 min ORPHANED catch applies unchanged.
#   Get-AgentEvidenceAgeMin <name> [-Now] returns the age in minutes of the newest own-evidence file, or $null. agent-rollcall.ps1 feeds it into LogAgeMin.
# Abandoned on purpose: a file agents\<name>.abandoned (agent-abandon.ps1) makes the record never reported.
# Test switches: KAH_RUNS_DIR (root, default C:\KenshiTestRuns).

function Get-AgentRunsDir { if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' } }

function Read-AgentRecord([System.IO.FileInfo]$File) {
    try {
        $lines = @(Get-Content -LiteralPath $File.FullName -Encoding UTF8 -TotalCount 8 -ErrorAction Stop)
        if (-not $lines.Count) { return $null }
        $first = ([string]$lines[0]).TrimStart([char]0xFEFF)
        if ($first -notmatch '^\s*[^|]+\|\s*(RUNNING|DONE|FAILED|STOPPED-CONTEXT)\s*\|') { return $null }   # malformed: skipped
        $state = $Matches[1]
        $f = @{ task = ''; latest = ''; outputs = ''; next = '' }
        foreach ($l in $lines | Select-Object -Skip 1) {
            if (([string]$l) -match '^(task|latest|outputs|next):\s?(.*)$') { $f[$Matches[1]] = $Matches[2].Trim() }
        }
        $name = $File.BaseName
        $ho = Join-Path $File.DirectoryName "$name.handoff.md"
        [pscustomobject]@{
            Name = $name; State = $state; Task = $f.task; Latest = $f.latest; Outputs = $f.outputs; Next = $f.next
            Mtime = $File.LastWriteTime; Path = $File.FullName
            Handoff = $(if (Test-Path -LiteralPath $ho) { $ho } else { $null })
            Abandoned = (Test-Path -LiteralPath (Join-Path $File.DirectoryName "$name.abandoned"))
        }
    } catch { $null }
}

function ConvertTo-TaskKey([string]$t) { ($t.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() }
function Test-OrphanTask([string]$t) { (ConvertTo-TaskKey $t) -like 'orphaned*' }
function Test-TaskMatch([string]$a, [string]$b) {
    $ka = ConvertTo-TaskKey $a; $kb = ConvertTo-TaskKey $b
    if (-not $ka -or -not $kb) { return $false }
    if ($ka -eq $kb) { return $true }
    if ($ka.Length -ge 8 -and $kb.Contains($ka)) { return $true }
    if ($kb.Length -ge 8 -and $ka.Contains($kb)) { return $true }
    $false
}

function Test-AgentSuccessorBasic($x, $s) {
    if ($s.Name -ceq $x.Name -or $s.Mtime -lt $x.Mtime) { return $false }
    $xn = [string]$x.Name; $sn = [string]$s.Name
    # (a) same name + one suffix character
    if ($sn.Length -gt $xn.Length -and $sn.StartsWith($xn, [StringComparison]::Ordinal) -and $sn.Substring($xn.Length) -cmatch '^[-_]?([2-9]|[b-z])$') { return $true }
    # (a2) sibling letter after a digit: N2b -> N2c, wpC1b -> wpC1c
    if ($xn -cmatch '^(.*[0-9])([b-y])$') {
        $stem2 = $Matches[1]; $xl = [char]$Matches[2]
        if ($sn.Length -eq $stem2.Length + 1 -and $sn.StartsWith($stem2, [StringComparison]::Ordinal) -and $sn[$sn.Length - 1] -cmatch '[c-z]' -and [char]$sn[$sn.Length - 1] -gt $xl) { return $true }
    }
    # (b) same stem, bigger trailing number (op1 -> op2)
    if ($xn -match '^(.*?)(\d+)$') {
        $stem = $Matches[1]; $xi = [int]$Matches[2]
        if ($sn -match '^(.*?)(\d+)$' -and $Matches[1] -ceq $stem -and [int]$Matches[2] -gt $xi) {
            if ((Test-OrphanTask $x.Task) -or (Test-TaskMatch $x.Task $s.Task)) { return $true }
        }
    }
    # (f) PI-33 (Shay 2026-10-16): the successor names the predecessor in its own status text (task/latest/next/outputs) as a whole word,
    #     or has the same stem + bigger trailing number and shares a row id (NN-x) with X's task text (sfE2 -> sfE3, i4op10 -> i4op11)
    if ($s.State -in 'RUNNING', 'DONE' -and -not (Test-OrphanTask $s.Task)) {
        $st = "$($s.Task) $($s.Latest) $($s.Next) $($s.Outputs)"
        if ($st -cmatch ('(?<![A-Za-z0-9_.-])' + [regex]::Escape($xn) + '(?![A-Za-z0-9_.-])')) { return $true }
        if ($xn -match '^(.*?)(\d+)$') {
            $stemF = $Matches[1]; $xiF = [int]$Matches[2]
            if ($stemF.Length -ge 3 -and $sn -match '^(.*?)(\d+)$' -and $Matches[1] -ceq $stemF -and [int]$Matches[2] -gt $xiF) {
                $rx = '\b\d{2}-[a-z]{1,2}\b'
                $xr = @([regex]::Matches(("$($x.Task) $($x.Latest) $($x.Next)").ToLowerInvariant(), $rx) | ForEach-Object { $_.Value })
                $sr = @([regex]::Matches($st.ToLowerInvariant(), $rx) | ForEach-Object { $_.Value })
                if (@($xr | Where-Object { $sr -contains $_ }).Count) { return $true }
            }
        }
    }
    # (c) a DONE status for the same task
    if ($s.State -eq 'DONE' -and -not (Test-OrphanTask $x.Task) -and -not (Test-OrphanTask $s.Task) -and (Test-TaskMatch $x.Task $s.Task)) { return $true }
    $false
}

# ---- rule (e): ledger / lane tie to a live successor (fails closed: any error => no groups => rule never applies) ----
$script:AgentGroups = $null    # cached by Initialize-AgentGroups (Get-AgentReport / Remove-SupersededTodos)
$script:AgentNow = $null

function Get-AgentLedgerGroups {
    try {
        $groups = New-Object System.Collections.ArrayList
        $pd = if ($env:KPL_DIR) { $env:KPL_DIR } else { Join-Path (Get-AgentRunsDir) 'programs' }
        if (Test-Path -LiteralPath $pd) {
            foreach ($f in Get-ChildItem -LiteralPath $pd -Filter '*.json' -File -ErrorAction Stop) {
                $j = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                foreach ($w in @($j.wps)) {
                    $n = @()
                    if ("$($w.agent)") { $n += "$($w.agent)" }
                    $n += @($w.successors | Where-Object { $_ } | ForEach-Object { "$_" })
                    if ($w.PSObject.Properties['agent_records'] -and $w.agent_records) { $n += @($w.agent_records.PSObject.Properties | ForEach-Object { $_.Name }) }
                    [void]$groups.Add([pscustomobject]@{ Kind = 'wp'; Label = "ledger wp $($w.id)"; Names = @($n | Select-Object -Unique) })
                }
            }
        }
        # lanes: the table in lane-idle.ps1 (ops lists) + the optional override <runs>\lane-owners.json (same precedence as lane-idle.ps1)
        $lanes = [ordered]@{}
        $li = Join-Path $PSScriptRoot 'lane-idle.ps1'
        if (Test-Path -LiteralPath $li) {
            $txt = Get-Content -LiteralPath $li -Raw -ErrorAction Stop
            foreach ($m in [regex]::Matches($txt, "'([^']+)'\s*=\s*@\{\s*ops\s*=\s*@\(([^)]*)\)")) {
                $lanes[$m.Groups[1].Value] = @([regex]::Matches($m.Groups[2].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            }
        }
        $ov = Join-Path (Get-AgentRunsDir) 'lane-owners.json'
        if (Test-Path -LiteralPath $ov) {
            $j = Get-Content -LiteralPath $ov -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in $j.psobject.Properties) { $lanes[$p.Name] = @($p.Value.ops | Where-Object { $_ } | ForEach-Object { "$_" }) }
        }
        foreach ($l in $lanes.Keys) { [void]$groups.Add([pscustomobject]@{ Kind = 'lane'; Label = "lane $l"; Names = @($lanes[$l]) }) }
        $groups.ToArray()
    } catch { @() }
}

function Initialize-AgentGroups([datetime]$Now = (Get-Date)) {
    $script:AgentNow = $Now
    $script:AgentGroups = @(Get-AgentLedgerGroups)
}

# returns the reason text ("ledger wp live-rows" / "lane 5090-i3") when rule (e) accepts S as successor of X, else $null
function Get-AgentSuccessorVia($x, $s, [int]$RunningMin = 45) {
    try {
        if ($null -eq $script:AgentGroups -or -not $script:AgentGroups.Count) { return $null }
        if (($x.State -notin 'STOPPED-CONTEXT', 'FAILED') -or $s.State -ne 'RUNNING') { return $null }
        if ($s.Name -ceq $x.Name -or $s.Mtime -lt $x.Mtime) { return $null }
        $now = if ($script:AgentNow) { $script:AgentNow } else { Get-Date }
        if (($now - $s.Mtime).TotalMinutes -ge $RunningMin) { return $null }
        $has = { param($g, $n) @($g.Names | Where-Object { $_ -ieq $n }).Count -gt 0 }
        $lx = @($script:AgentGroups | Where-Object { $_.Kind -eq 'lane' -and (& $has $_ $x.Name) })
        $ls = @($script:AgentGroups | Where-Object { $_.Kind -eq 'lane' -and (& $has $_ $s.Name) })
        foreach ($g in $lx) { if (& $has $g $s.Name) { return $g.Label } }      # same lane
        if ($lx.Count) { return $null }                                          # X is a lane operator: only a successor in the SAME lane counts (a shared wp proves nothing; Shay's PI-11 caveat)
        foreach ($g in ($script:AgentGroups | Where-Object { $_.Kind -eq 'wp' })) { if ((& $has $g $x.Name) -and (& $has $g $s.Name)) { return $g.Label } }
        $null
    } catch { $null }
}

function Test-AgentSuccessor($x, $s) {
    if (Test-AgentSuccessorBasic $x $s) { return $true }
    $null -ne (Get-AgentSuccessorVia $x $s)
}

function Get-NextAgentName([string]$n) {
    if ($n -cmatch '^(.*[0-9A-Za-z])([-_])(\d)$' -and [int]$Matches[3] -lt 9) { return $Matches[1] + $Matches[2] + ([int]$Matches[3] + 1) }
    if ($n -cmatch '^(.*[^a-z])([b-y])$' -or $n -cmatch '^(.*[0-9])([b-y])$') { return $Matches[1] + [char]([int][char]$Matches[2] + 1) }
    if ($n -cmatch '[0-9]$') { return $n + 'b' }
    $n + '2'
}

function Get-AgentRespawn($r) {
    $src = if ($r.Handoff) { $r.Handoff } else { $r.Path }
    $next = Get-NextAgentName $r.Name
    $nxt = if ($r.Next) { " Its own 'next:' line: $($r.Next)" } else { '' }
    "Respawn fresh agent '$next' for $($r.Name) ($($r.State) $($r.Mtime.ToString('MM-dd HH:mm'))): Agent prompt `"Resume the task '$($r.Task)' as a FRESH agent named $next. Read $src first (status file $($r.Path)), continue from where $($r.Name) stopped, keep your own status current with tools\automation\agent-status.ps1 $next RUNNING|DONE|FAILED|STOPPED-CONTEXT and write C:\KenshiTestRuns\agents\$next.handoff.md. Never SendMessage the old agent.$nxt`""
}

# newest write time (minutes before $Now) of one file or of all files under one dir; $null when none. Never counts *.status. Capped at 20000 files.
function Get-NewestAgeMin([string]$Path, [datetime]$Now) {
    try {
        $best = $null
        if (Test-Path -LiteralPath $Path -PathType Leaf) { $files = @($Path) }
        elseif (Test-Path -LiteralPath $Path -PathType Container) { $files = [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories) }
        else { return $null }
        $n = 0
        foreach ($f in $files) {
            if ($f -like '*.status') { continue }
            if (++$n -gt 20000) { break }
            try { $t = [System.IO.File]::GetLastWriteTime($f) } catch { continue }
            if ($null -eq $best -or $t -gt $best) { $best = $t }
        }
        if ($null -eq $best) { return $null }
        [math]::Round(($Now - $best).TotalMinutes, 1)
    } catch { $null }
}

# PI-17: age (minutes) of the newest file in the agent's OWN evidence locations, or $null (see header). Fails open to $null.
function Get-AgentEvidenceAgeMin([string]$Name, [datetime]$Now = (Get-Date), [string]$RunsDir = '') {
    try {
        if (-not $RunsDir) { $RunsDir = Get-AgentRunsDir }
        if (-not $Name -or $Name -match '[\/:*?"<>|]' -or $Name -like '*..*') { return $null }
        $paths = @((Join-Path $RunsDir "agents\out\$Name.log"), (Join-Path $RunsDir "agents\out\$Name"))
        $ov = Join-Path $RunsDir 'lane-owners.json'
        if (Test-Path -LiteralPath $ov) {
            $j = Get-Content -LiteralPath $ov -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in $j.psobject.Properties) {
                if (@($p.Value.ops | Where-Object { $_ -and "$_" -ieq $Name }).Count) {
                    foreach ($d in @($p.Value.dirs | Where-Object { $_ })) {
                        $d = "$d"
                        if ($d -match '[\/:*?"<>|]' -or $d -like '*..*') { continue }       # lane dirs are plain names under the runs dir
                        $paths += (Join-Path $RunsDir $d)
                    }
                }
            }
        }
        $best = $null
        foreach ($p in $paths) { $a = Get-NewestAgeMin $p $Now; if ($null -ne $a -and ($null -eq $best -or $a -lt $best)) { $best = $a } }
        $best
    } catch { $null }
}

function Get-AgentReport {
    param([string]$AgentsDir = '', [datetime]$Now = (Get-Date), [int]$RunningMin = 45, [int]$OrphanMin = 30, [int]$HorizonH = 18, [int]$EvidenceMin = 10)
    $rep = [pscustomobject]@{ InFlight = @(); Orphaned = @(); Open = @(); OpenRecent = @(); Todos = @(); Count = 0; Accepted = @() }
    try {
        if (-not $AgentsDir) { $AgentsDir = Join-Path (Get-AgentRunsDir) 'agents' }
        if (-not (Test-Path -LiteralPath $AgentsDir)) { return $rep }
        $recs = @(Get-ChildItem -LiteralPath $AgentsDir -Filter '*.status' -File -ErrorAction SilentlyContinue | Select-Object -First 400 | ForEach-Object { Read-AgentRecord $_ } | Where-Object { $_ })
        $rep.Count = $recs.Count
        $open = @(); $orph = @(); $fly = @(); $acc = @()
        try { Initialize-AgentGroups $Now } catch { $script:AgentGroups = @() }
        foreach ($r in $recs) {
            $age = ($Now - $r.Mtime).TotalMinutes
            if ($r.State -eq 'RUNNING' -and $age -lt $RunningMin) { $fly += $r }
            if ($r.Abandoned) { continue }
            if ($r.State -notin 'RUNNING', 'STOPPED-CONTEXT', 'FAILED') { continue }
            if ($r.State -eq 'RUNNING' -and $age -lt $OrphanMin) { continue }
            if ($r.State -eq 'RUNNING' -and -not (Test-Path -LiteralPath (Join-Path $AgentsDir "$($r.Name).session.json"))) {   # PI-17: in-session agent writing its own evidence is working
                $ev = Get-AgentEvidenceAgeMin $r.Name $Now (Split-Path -Parent $AgentsDir)
                if ($null -ne $ev -and $ev -lt $EvidenceMin) { if ($age -ge $RunningMin) { $fly += $r }; continue }
            }
            $sup = $false
            foreach ($s in $recs) { if (Test-AgentSuccessorBasic $r $s) { $sup = $true; break } }
            if (-not $sup) {      # rule (e): ledger/lane tie to a live successor under another name (report which one and why)
                foreach ($s in $recs) {
                    $via = Get-AgentSuccessorVia $r $s $RunningMin
                    if ($via) { $sup = $true; if (($Now - $r.Mtime).TotalHours -lt $HorizonH) { $acc += "accepted successor $($s.Name) for $($r.Name) via $via" }; break }
                }
            }
            if ($sup) { continue }
            if ($r.State -eq 'RUNNING') { $orph += $r } else { $open += $r }
        }
        $rep.InFlight = $fly; $rep.Orphaned = $orph; $rep.Open = $open; $rep.Accepted = $acc
        $rep.OpenRecent = @($open | Where-Object { ($Now - $_.Mtime).TotalHours -lt $HorizonH })
        # respawn todos (agent-status.ps1 writes respawn\<name>.todo on STOPPED-CONTEXT): the ones still open (not superseded/abandoned)
        $td = Join-Path (Split-Path -Parent $AgentsDir) 'respawn'
        if (Test-Path -LiteralPath $td) {
            $names = @($rep.Open | ForEach-Object Name)
            $rep.Todos = @(Get-ChildItem -LiteralPath $td -Filter '*.todo' -File -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.BaseName } | ForEach-Object BaseName)
        }
    } catch { }
    $rep
}

function Get-AgentAcceptedLines([string]$AgentsDir = '', [datetime]$Now = (Get-Date)) { @((Get-AgentReport -AgentsDir $AgentsDir -Now $Now).Accepted) }

function Get-AgentHealthLines([string]$AgentsDir = '', [datetime]$Now = (Get-Date)) {
    $rep = Get-AgentReport -AgentsDir $AgentsDir -Now $Now
    $out = @()
    foreach ($r in $rep.Orphaned) { $out += "ORPHANED (parent session gone?) $($r.Name): RUNNING, last update $([int](($Now - $r.Mtime).TotalMinutes)) min ago. $(Get-AgentRespawn $r)" }
    foreach ($r in $rep.Open) {
        $old = if (($Now - $r.Mtime).TotalHours -ge 18) { ' [older than 18 h: the Stop hook ignores it; respawn it or agent-abandon.ps1 ' + $r.Name + ' "<why>"]' } else { '' }
        $out += "NO SUCCESSOR $($r.Name): $($r.State) $([int](($Now - $r.Mtime).TotalMinutes)) min ago$old. $(Get-AgentRespawn $r)"
    }
    $out
}

# Remove respawn todos that a newer agent has taken over (called when an agent writes RUNNING, and by session-start).
function Remove-SupersededTodos([string]$AgentsDir = '') {
    try {
        if (-not $AgentsDir) { $AgentsDir = Join-Path (Get-AgentRunsDir) 'agents' }
        $td = Join-Path (Split-Path -Parent $AgentsDir) 'respawn'
        if (-not (Test-Path -LiteralPath $td)) { return }
        $recs = @(Get-ChildItem -LiteralPath $AgentsDir -Filter '*.status' -File -ErrorAction SilentlyContinue | ForEach-Object { Read-AgentRecord $_ } | Where-Object { $_ })
        try { Initialize-AgentGroups } catch { $script:AgentGroups = @() }
        foreach ($t in Get-ChildItem -LiteralPath $td -Filter '*.todo' -File -ErrorAction SilentlyContinue) {
            $rec = $recs | Where-Object { $_.Name -ceq $t.BaseName } | Select-Object -First 1
            $drop = (-not $rec) -or $rec.Abandoned -or ($rec.State -ne 'STOPPED-CONTEXT')
            if (-not $drop) { foreach ($s in $recs) { if (Test-AgentSuccessor $rec $s) { $drop = $true; break } } }
            if ($drop) { Remove-Item -LiteralPath $t.FullName -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
}
