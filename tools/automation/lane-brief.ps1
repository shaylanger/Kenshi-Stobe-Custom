# lane-brief.ps1 <lane> [-Out path] [-Name op] [-Predecessor op] [-Runs dir] [-Repo dir] [-NoRemote] [-MaxBytes 25600]
# PI-12 (Shay approved 2026-10-15): generate a self-contained operator brief for an imm26 lane at call time, so a new operator
# starts testing within ~2 minutes instead of reading the long briefs. Lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4.
# Shay orders #2/#3 (2026-10-15): the GENERATED brief is the only required reading (<= 14.5 KB since imm26-ctxfix2). It embeds the KNOWN_BLOCKERS lines
# relevant to the lane (by row id / lane / DLL), the full definitions of the next rows (TESTS file + the go-row.sh row script), the
# helper-script list with one-line usage, and a condensed COMMON/OPERATOR_COMMON rules block. -Predecessor <op> adds the PREDECESSOR
# HANDOVER section (successor started before the old operator died: no game commands until agents\<op>.handoff.md or a terminal
# status); without it the section is omitted. The size is printed on stderr.
# EVERYTHING dynamic is read when the script runs (no baked SHAs): lane files (lanes-5090.json / lane-defs.4080.json),
# lane DLL SHA256 from the lane install (4080 over ssh; -NoRemote skips it), newest NC DLL in pending-fixes/npc-immersion-26,
# predecessor handoff (newest of the lane's operator names + handoff globs), next 5 non-PASS rows of the lane
# (handoff TODO ids first, else UNRUN/SETUP-FAIL/GATED/FAIL rows) from testing/NPC_IMMERSION_26_TESTS.md,
# testing/KNOWN_BLOCKERS.md, rowtools row scripts, exact status/handoff/report command lines.
# PI-19 (Shay approved 2026-10-15): with -Name AND -Predecessor the brief prints the predecessor's exact status TASK text (agent-guard rule b:
# the successor's task must equal it) with a ready-to-paste agent-status.ps1 command, and the script registers the successor in
# <Runs>\lane-owners.json itself (operator-warn.ps1 -Register <pred> <name> -InLane <lane>; idempotent; skipped under -NoRemote).
# PI-20: standing rule in the brief: game speed above 5 only under tools/stobe-goal-watch.sh.
# Output: stdout, and -Out file when given. Exit 0 ok, 2 bad lane.
param(
    [Parameter(Position = 0)][string]$Lane,
    [string]$Out,
    [string]$Name,
    [string]$Predecessor,
    [string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }),
    [string]$Repo = 'C:\KenshiModding',
    [switch]$NoRemote,
    [int]$MaxBytes = 14500,
    [string]$Pilot     # 'haiku-i4' = SHADOW pilot brief variant (see below); empty = the normal brief, byte-identical in behaviour
)
# -Pilot haiku-i4 (Shay 2026-10-16, Haiku-vs-Sonnet pilot): same lane facts, rows and rules, but the operator never claims rows, never writes the TESTS file or
# setupfail tickets and never commits: pilot-mark.sh (shadow ledger C:\KenshiTestRuns\pilot\haiku-i4\verdicts.csv) replaces mkdir claims / mark-row / status-mark /
# setupfail. Rows come from <Runs>\pilot\rows-i4.txt (row :: one-call command). Anything outside one-call scripts goes to the coordinator, not improvised.
$ErrorActionPreference = 'Stop'
# lane -> operator names / handoff globs / evidence dirs (same defaults as lane-idle.ps1; <Runs>\lane-owners.json overrides ops+dirs)
$lanes = [ordered]@{
    '5090-i3' = @{ ops = @('imm26-5090-i3op3'); globs = @('imm26-5090-i3op*'); dirs = @('imm26-5090-i3', 'imm26-5090-i3op3') }
    '5090-i4' = @{ ops = @('imm26-5090-i4op3'); globs = @('imm26-5090-i4op*'); dirs = @('imm26-5090-i4', 'imm26-5090-i4op3') }
    '5090-i5' = @{ ops = @('imm26-5090-ctxop322', 'imm26-5090-ctxop32', 'imm26-5090-ctxop3'); globs = @('imm26-5090-i5op*', 'imm26-5090-ctxop*'); dirs = @('imm26-5090-i5', 'imm26-5090-ctxop3', 'imm26-5090-ctxop32') }
    '4080-i3' = @{ ops = @('imm26-4080-op2g'); globs = @('imm26-4080-op*'); dirs = @('imm26-4080') }
    '4080-i4' = @{ ops = @('imm26-4080-i4op5'); globs = @('imm26-4080-i4op*'); dirs = @('imm26-4080-i4') }
}
if (-not $Lane -or -not $lanes.Contains($Lane)) { [Console]::Error.WriteLine("usage: lane-brief.ps1 <$($lanes.Keys -join '|')> [-Out path] [-Name op] [-Predecessor op]"); exit 2 }
if ($Pilot -and ($Pilot -ne 'haiku-i4' -or $Lane -ne '5090-i4')) { [Console]::Error.WriteLine("lane-brief: -Pilot supports only 'haiku-i4' on lane 5090-i4"); exit 2 }
$ov = Join-Path $Runs 'lane-owners.json'
if (Test-Path -LiteralPath $ov) {
    try { $j = Get-Content -LiteralPath $ov -Raw | ConvertFrom-Json; if ($j.PSObject.Properties.Name -contains $Lane) { $p = $j.$Lane; $lanes[$Lane].ops = @($p.ops); $lanes[$Lane].dirs = @($p.dirs) } } catch { }
}
$cfg = $lanes[$Lane]
$rig, $id = $Lane -split '-', 2
function Clip([string]$s, [int]$n) { $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n - 3) + '...' } else { $s } }
function Sha8([string]$p) { try { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { $null } } catch { $null } }

# ---- lane facts ------------------------------------------------------------------------------------------
$f = [ordered]@{}; $dllPaths = @()
if ($rig -eq '5090') {
    $lj = Get-Content -LiteralPath (Join-Path $Runs 'lanes\lanes-5090.json') -Raw | ConvertFrom-Json
    $l = $lj.lanes | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $l) { [Console]::Error.WriteLine("lane $id not in lanes-5090.json"); exit 2 }
    $f['rig'] = "5090 (this PC), game dir $($l.dir)"
    $f['backend'] = "WSL php port $($l.backend_port), bridge $($l.bridge_port), pg $($l.pg_port), root $($l.wsl_root)"
    $f['db'] = $l.db
    $f['save'] = "$($l.save_name) (dir $($l.save_dir); handoff may name a newer one)"
    $w = $l.window; $f['window'] = "$($w.display) at $($w.x),$($w.y) $($w.w)x$($w.h), $($l.video_mode), gfx $($l.gfx), cap $($l.framecap)"
    $f['lock'] = "$($l.lock) owner $($l.lock_owner); inflight $($l.inflight)"
    $f['logs'] = "$($l.stobe_log) | $($l.harness_log)"
    $dllPaths = @((Join-Path $l.dir 'RE_Kenshi\mods\Stobe\Stobe.dll'), (Join-Path $l.dir 'mods\Stobe\Stobe.dll'))
} else {
    $lj = Get-Content -LiteralPath (Join-Path $Repo 'tools\automation\lane-defs.4080.json') -Raw | ConvertFrom-Json
    $l = $lj.lanes.$id
    if (-not $l) { [Console]::Error.WriteLine("lane $id not in lane-defs.4080.json"); exit 2 }
    $f['rig'] = "4080 (ssh 4080; C:\KAH\ctl.ps1; owner rig4080), game dir $($l.dir)"
    $f['backend'] = "WSL php port $($l.php_port), bridge $($l.bridge_port), pg $($l.pg_port), root $($l.backend_root), task $($l.task)"
    $f['db'] = $l.db
    $f['save'] = "$($l.save) (the handoff may name a newer working save)"
    $f['window'] = "pos $($l.window_pos) size $($l.window_size) (DISPLAY5 desktop, parked right of it)"
    $f['lock'] = "$($l.lock); inflight marker $($l.marker)"
    $f['logs'] = "$($l.dir)\RE_Kenshi\mods\Stobe\stobe.log | $($l.dir)\mods\AutomationHarness\harness.log"
    $dllPaths = @("$($l.dir)\mods\Stobe\Stobe.dll", "$($l.dir)\RE_Kenshi\mods\Stobe\Stobe.dll")
}
$dllLines = @()
foreach ($p in $dllPaths) {
    $h = $null
    if ($rig -eq '5090') { $h = Sha8 $p }
    elseif (-not $NoRemote) {
        try {
            $r = & ssh -o ConnectTimeout=8 -o BatchMode=yes 4080 "certutil -hashfile $p SHA256" 2>$null
            $h = ($r | Where-Object { $_ -match '^[0-9a-fA-F ]{64,}$' } | Select-Object -First 1) -replace ' ', ''
        } catch { $h = $null }
    }
    if ($h) { $dllLines += "$($h.Substring(0,8).ToUpper()) $p" }
}
if ($dllLines.Count -eq 0) { $dllLines = @($(if ($rig -eq '4080' -and $NoRemote) { 'not read (-NoRemote); run: ssh 4080 certutil -hashfile <path> SHA256' } else { 'NOT FOUND in lane install (' + ($dllPaths -join ' | ') + ')' })) }
$ncDir = Join-Path $Repo 'pending-fixes\npc-immersion-26'
$nc = $null
if (Test-Path -LiteralPath $ncDir) { $nc = Get-ChildItem -LiteralPath $ncDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Stobe.dll' } | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ } | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
$ncLine = if ($nc) { "$((Sha8 $nc.FullName).Substring(0,8)) $($nc.Directory.Name) ($($nc.LastWriteTime.ToString('MM-dd HH:mm'))) $($nc.FullName)" } else { 'none found' }
$match = ''
if ($nc -and ($dllLines -join ' ') -match (Sha8 $nc.FullName).Substring(0, 8)) { $match = 'lane runs the newest NC DLL' } elseif ($nc) { $match = 'lane DLL differs from newest NC DLL: confirm with the handoff/coordinator before gated rows' }

# ---- LANE STATE (imm26-ctxfix2): what the operator would otherwise spend 20-25k tokens finding out -------------------------
$stLines = @()
$rc = Join-Path $PSScriptRoot 'rowcard.py'
function RowCard([string[]]$a) {
    try {
        $oldR = $env:KAH_RUNS_DIR; $oldP = $env:KAH_REPO
        $env:KAH_RUNS_DIR = $Runs; $env:KAH_REPO = $Repo
        $o = @(& python -I $rc @a 2>$null | ForEach-Object { "$_" })
        $env:KAH_RUNS_DIR = $oldR; $env:KAH_REPO = $oldP
        if ($LASTEXITCODE -eq 0 -and $o.Count) { return $o }
    } catch { }
    return @()
}
$saveLoaded = ''; $gameLine = ''
if ($rig -eq '5090') {
    try {
        if ($l.harness_log -and (Test-Path -LiteralPath $l.harness_log)) {
            $ll = Select-String -LiteralPath $l.harness_log -Pattern 'KAH: load save=' -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($ll) { $saveLoaded = (Clip $ll.Line 160) }
        }
        $gp = @(Get-Process -Name kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -like "$($l.dir)*" } catch { $false } })
        $gameLine = "game pid $(if ($gp.Count) { $gp[0].Id } else { 'none (closed)' }); lock $(if (Test-Path -LiteralPath $l.lock) { 'HELD' } else { 'free' }); inflight $(if (Test-Path -LiteralPath $l.inflight) { 'SET' } else { 'clear' })"
    } catch { $gameLine = 'game state not read: ' + (Clip "$_" 80) }
} elseif (-not $NoRemote) {
    try {
        $hl = "$($l.dir)\mods\AutomationHarness\harness.log"
        $ps1 = "`$g=@(Get-Process kenshi_x64 -ErrorAction SilentlyContinue|?{`$_.Path -like '$($l.dir)*'}); 'PID='+`$(if(`$g.Count){`$g[0].Id}else{'none'}); 'LOCK='+(Test-Path '$($l.lock)'); 'MARK='+(Test-Path '$($l.marker)'); if(Test-Path '$hl'){(Select-String -LiteralPath '$hl' -Pattern 'KAH: load save=' | Select-Object -Last 1).Line}"
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps1))
        $r = @(& ssh -o ConnectTimeout=8 -o BatchMode=yes 4080 "powershell -NoProfile -EncodedCommand $enc" 2>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        $pidv = ($r | Where-Object { $_ -like 'PID=*' } | Select-Object -First 1) -replace '^PID=', ''
        $lk = ($r | Where-Object { $_ -like 'LOCK=*' } | Select-Object -First 1) -replace '^LOCK=', ''
        $mk = ($r | Where-Object { $_ -like 'MARK=*' } | Select-Object -First 1) -replace '^MARK=', ''
        $sv = $r | Where-Object { $_ -match 'KAH: load save=' } | Select-Object -First 1
        if ($sv) { $saveLoaded = Clip $sv 160 }
        if ($pidv) { $gameLine = "game pid $pidv; lock $(if ($lk -eq 'True') { 'HELD' } else { 'free' }); inflight $(if ($mk -eq 'True') { 'SET' } else { 'clear' })" }
    } catch { $gameLine = 'game state not read (ssh failed)' }
}
if (-not $gameLine) { $gameLine = if ($NoRemote -and $rig -eq '4080') { 'not read (-NoRemote)' } else { 'not read' } }
$stLines += "- loaded save (last harness 'load save='): $(if ($saveLoaded) { $saveLoaded } else { 'none found in harness.log (game not loaded since the log rolled)' })"
$stLines += "- $gameLine"
$stateRc = @(RowCard @('state', $Lane))
if ($stateRc.Count -and -not $Pilot) { $stLines += '- ' + (Clip $stateRc[0] 700) }
$launch = if ($rig -eq '5090') {
    "launch: wsl lane-backend.sh start $id ; env KAH_INSTANCE=$($l.instance) KAH_OWNER=$($l.lock_owner) KAH_GFX=low KAH_VIDEO_MODE='1024 x 768' KAH_FPS=60 KENSHI_MONITOR='\.\DISPLAY2' kenshi-ctl.ps1 launch -Save <save> -Gfx low ; lane-window.ps1 -Lane $id -Action place   (scripts in tools\automation; then lane-setup.sh waits for the world)"
} else {
    "launch: ssh 4080 powershell -File C:\KAH\ctl.ps1 launch -Instance $($l.instance) -Save <save> ; backend: stobe-lane-backend.sh $id (tools\automation, WSL)"
}
$stLines += "- $launch"
$inboxRc = @(RowCard @('inbox', $Lane, '--max-bytes', '1500'))
$inboxRc2 = @(RowCard @('inbox', $Lane, '--max-bytes', '800'))
$kbClip = 260; $fullRows = 3

# ---- predecessor handoff ---------------------------------------------------------------------------------
$ag = Join-Path $Runs 'agents'
$cands = @()
foreach ($o in $cfg.ops) { $p = Join-Path $ag "$o.handoff.md"; if (Test-Path -LiteralPath $p) { $cands += Get-Item -LiteralPath $p } }
foreach ($g in $cfg.globs) { $cands += @(Get-ChildItem -Path (Join-Path $ag "$g.handoff.md") -ErrorAction SilentlyContinue) }
if ($Predecessor) { $pp = Join-Path $ag "$Predecessor.handoff.md"; if (Test-Path -LiteralPath $pp) { $cands += Get-Item -LiteralPath $pp } }
$ho = $cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($Predecessor -and (Test-Path -LiteralPath (Join-Path $ag "$Predecessor.handoff.md"))) { $ho = Get-Item -LiteralPath (Join-Path $ag "$Predecessor.handoff.md") }
$hoLines = @(); $todoIds = @()
if ($ho) {
    $all = @(Get-Content -LiteralPath $ho.FullName -Encoding UTF8)
    $hoLines = @($all | Where-Object { $_.Trim() } | Select-Object -First 15)
    foreach ($ln in $all) {
        if ($ln -match '(?i)\bTODO\b') {
            foreach ($m in [regex]::Matches($ln, '\b(\d{2})-([a-z])((?:/[a-z])*)\b')) {
                $ids = @("$($m.Groups[1].Value)-$($m.Groups[2].Value)")
                foreach ($x in ($m.Groups[3].Value -split '/' | Where-Object { $_ })) { $ids += "$($m.Groups[1].Value)-$x" }
                foreach ($i in $ids) { if ($todoIds -notcontains $i) { $todoIds += $i } }
            }
        }
    }
}

# ---- rows (full definitions) -----------------------------------------------------------------------------
$rows = @()
$tf = Join-Path $Repo 'testing\NPC_IMMERSION_26_TESTS.md'
if (Test-Path -LiteralPath $tf) {
    foreach ($ln in (Get-Content -LiteralPath $tf -Encoding UTF8)) {
        if ($ln -notmatch '^\|\s*IMM-(\d{2}-[a-z])\s*\|') { continue }
        $rid = $Matches[1]
        $c = $ln.Trim().Trim('|') -split '(?<!\\)\|'
        $st = $null; for ($i = 5; $i -lt $c.Count; $i++) { $t = $c[$i].Trim(); if ($t -match '^(PASS|FAIL|SETUP-FAIL|GATED|UNRUN)$') { $st = $t; break } }
        if (-not $st) { $st = '?' }
        $cell = { param($k) if ($c.Count -gt $k) { $c[$k] } else { '' } }
        $rows += [pscustomobject]@{ Id = $rid; Status = $st; Setup = (Clip $c[1] 70); Utter = (Clip ($c[2] -replace '^\s*say:\s*', '') 60)
            FSetup = (Clip (& $cell 1) 260); FUtter = (Clip (& $cell 2) 160); Expect = (Clip (& $cell 3) 320); Neg = (Clip (& $cell 4) 140); Build = (Clip (& $cell 5) 80) }
    }
}
$open = @($rows | Where-Object { $_.Status -ne 'PASS' })
$pick = @(); $src = @{}
foreach ($i in $todoIds) { $r = $open | Where-Object { $_.Id -eq $i } | Select-Object -First 1; if ($r -and $pick.Count -lt 5) { $pick += $r; $src[$r.Id] = 'handoff TODO' } }
$pri = @{ 'UNRUN' = 0; 'SETUP-FAIL' = 1; 'GATED' = 2; 'FAIL' = 3; '?' = 4 }
if ($pick.Count -lt 5) {
    foreach ($r in ($open | Sort-Object { $pri[$_.Status] }, Id)) { if ($pick.Count -ge 5) { break } if ($pick.Id -notcontains $r.Id) { $pick += $r; $src[$r.Id] = 'unowned fallback (other lanes may take it: check the TESTS file first)' } }
}
$passN = @($rows | Where-Object { $_.Status -eq 'PASS' }).Count
# PILOT: the row list is <Runs>\pilot\rows-i4.txt (`<row> :: <one-call command>`); no TESTS statuses (the shadow operator ignores the Sonnet lane's marks), no predecessor handoff, no inbox digest
$pilotRows = @()
if ($Pilot) {
    $pf = Join-Path $Runs 'pilot\rows-i4.txt'
    if (Test-Path -LiteralPath $pf) { foreach ($ln in (Get-Content -LiteralPath $pf -Encoding UTF8)) { if ($ln -match '^(\d{2}-[a-z]{1,3})\s*::\s*(.+)$') { $pilotRows += [pscustomobject]@{ Id = $Matches[1]; Cmd = $Matches[2].Trim() } } } }
    $ho = $null; $hoLines = @(); $inboxRc = @(); $inboxRc2 = @()
}

# row scripts: rd_<id without dash> in rowtools/rowdefs.sh + tripdefs.sh (go-row.sh runs them); the comment after `{` is the usage note
$rtDir = Join-Path $Repo 'testing\live-stobe-queue\imm26-assert\rowtools'
$rdNote = @{}
foreach ($fn in 'rowdefs.sh', 'tripdefs.sh') {
    $pth = Join-Path $rtDir $fn
    if (-not (Test-Path -LiteralPath $pth)) { continue }
    foreach ($ln in (Get-Content -LiteralPath $pth -Encoding UTF8)) {
        if ($ln -match '^rd_(\d{2}[a-z])\(\)\s*\{\s*(?:#\s*(.*))?$') { $k = $Matches[1]; $rdNote["$($k.Substring(0,2))-$($k.Substring(2))"] = $(if ($Matches[2]) { Clip $Matches[2] 230 } else { '' }) }
    }
}

# ---- known blockers (only the lines relevant to this lane) -----------------------------------------------
$kb = Join-Path $Repo 'testing\KNOWN_BLOCKERS.md'
$kbAll = @(); if (Test-Path -LiteralPath $kb) { $kbAll = @(Get-Content -LiteralPath $kb -Encoding UTF8 | Where-Object { $_ -match '^\s*(-|#{2,})\s+\S' } | ForEach-Object { ($_ -replace '^\s*(-|#+)\s+', '').Trim() }) }
$laneTag = "$rig $id"                                    # e.g. '5090 i4'
$pickIds = @($pick | ForEach-Object { $_.Id })
$dllKeys = @(); foreach ($d in $dllLines) { if ($d -match '^[0-9A-F]{8}') { $dllKeys += $d.Substring(0, 8) } }; if ($nc) { $dllKeys += (Sha8 $nc.FullName).Substring(0, 8) }
function KbRelevant([string]$b) {
    $lm = @([regex]::Matches($b, '\b(5090|4080)\s+(i\d)\b') | ForEach-Object { "$($_.Groups[1].Value) $($_.Groups[2].Value)" } | Select-Object -Unique)
    # a line naming other lanes only is skipped unless it names this lane, names >= 3 lanes / 'ALL' lanes (global), or mentions one of this lane's rows / DLLs
    if ($lm.Count -eq 0 -or $lm -contains $laneTag -or $lm.Count -ge 3 -or $b -match '(?i)\ball (five )?lanes\b') { return $true }
    foreach ($k in $dllKeys) { if ($b -match [regex]::Escape($k)) { return $true } }
    foreach ($m in [regex]::Matches($b, '\b(\d{2})-([a-z*])((?:/[a-z])*)(?![A-Za-z0-9])')) {
        $n = $m.Groups[1].Value; $ls = @($m.Groups[2].Value) + @($m.Groups[3].Value -split '/' | Where-Object { $_ })
        foreach ($x in $ls) { foreach ($pid2 in $pickIds) { if ($pid2 -eq "$n-$x" -or ($x -eq '*' -and $pid2.StartsWith("$n-"))) { return $true } } }
    }
    $false
}
$kbl = @($kbAll | Where-Object { KbRelevant $_ })
$kbSkipped = $kbAll.Count - $kbl.Count

# ---- names / commands ------------------------------------------------------------------------------------
if (-not $Name) {
    $base = if ($cfg.ops.Count) { $cfg.ops[0] } else { "imm26-$Lane-op" }
    $Name = if ($base -match '^(.*?)(\d+)$') { $Matches[1] + ([int]$Matches[2] + 1) } else { $base + '2' }
}
$as = 'powershell -NoProfile -File C:\KenshiModding\tools\automation\agent-status.ps1'
$ho2 = "C:\KenshiTestRuns\agents\$Name.handoff.md"
# PI-19: the predecessor's status TASK text (line 2 of its status file) and the successor registration
$taskTxt = $(if ($Pilot) { "$Lane pilot operator (shadow, $Pilot)" } else { "$Lane operator" }); $taskNote = ''; $regNote = ''
if ($Predecessor) {
    $pst = Join-Path $ag "$Predecessor.status"
    $ptask = $null
    if (Test-Path -LiteralPath $pst) { try { $t2 = Get-Content -LiteralPath $pst -Encoding UTF8 -TotalCount 2 | Select-Object -Skip 1 -First 1; if ($t2 -match '^task:\s?(.*)$' -and $Matches[1].Trim()) { $ptask = $Matches[1].Trim() } } catch { } }
    if ($ptask) { $taskTxt = $ptask; $taskNote = 'from the predecessor status file' } else { $taskNote = "predecessor status file or its task line NOT found: read line 2 of C:\KenshiTestRuns\agents\$Predecessor.status and use that text" }
    if ($PSBoundParameters.ContainsKey('Name')) {
        if ($NoRemote) { $regNote = "registration skipped (-NoRemote/test mode): run: powershell -NoProfile -File $PSScriptRoot\operator-warn.ps1 -Register $Predecessor $Name -InLane $Lane" }
        else {
            try {
                $rg = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'operator-warn.ps1') -Register $Predecessor $Name -InLane $Lane -Runs $Runs 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ })
                $regNote = if ($LASTEXITCODE -eq 0) { ($rg -join ' ') + ' (done by lane-brief.ps1, idempotent: no need to run operator-warn.ps1 -Register)' } else { 'registration FAILED (' + ($rg -join ' ') + '): run operator-warn.ps1 -Register by hand' }
            } catch { $regNote = "registration FAILED ($_): run operator-warn.ps1 -Register $Predecessor $Name -InLane $Lane by hand" }
        }
    }
}
# PI-32 (confirmed 2026-10-16): spawning an operator records the rig idle reason for the lane's rig so the Stop hook / rig-health do
# not demand one by hand while the lane launches. Valid for 15 min only (file mtime backdated 45 min; every consumer accepts < 60 min)
# and it is only read while the game is closed, so it lapses on its own once a game starts. A fresh manual reason is never overwritten.
if ($PSBoundParameters.ContainsKey('Name') -and -not $NoRemote -and $Runs -eq 'C:\KenshiTestRuns') {
    try {
        $idleF = Join-Path $Runs $(if ($Lane -like '4080*') { 'rig4080.idle' } else { 'rig5090.idle' })
        $freshIdle = (Test-Path -LiteralPath $idleF) -and ((Get-Item -LiteralPath $idleF).LastWriteTime -gt (Get-Date).AddMinutes(-15))
        if (-not $freshIdle) {
            Set-Content -LiteralPath $idleF -Value "lane-brief $(Get-Date -Format 'yyyy-MM-dd HH:mm') operator $Name spawned for $Lane, lane launching (auto, 15 min)" -Encoding utf8
            (Get-Item -LiteralPath $idleF).LastWriteTime = (Get-Date).AddMinutes(-45)
        }
    } catch { [Console]::Error.WriteLine("lane-brief: idle-reason record failed: $_") }
}
$taskQ = $taskTxt -replace '([`"$])', '`$1'
$ra = Join-Path $Repo 'testing\live-stobe-queue\imm26-assert'
$ta = Join-Path $Repo 'tools\automation'

# helper scripts: [path, one-line usage]; entries whose file is missing are dropped (so the list never lies)
$helpers = @(
    @("$ta\next-row.sh", "bash next-row.sh $Lane [--n N] [--ids] [--claim] [--cards]  = next unclaimed open row as one card with its runner command"),
    @("$ta\row-card.sh", "bash row-card.sh <ROW> [$Lane]  = fixed card: status, claim, RUN command, setup, expect, evidence path (not the 200 KB TESTS file)"),
    @("$ta\logwin.sh", "bash logwin.sh <log> <pattern|since:<regex>|at:HH:MM:SS[+SEC]> [maxchars=2500]  = capped, noise-filtered log window (RESULT lines never cut)"),
    @("$ta\usage.sh", "bash usage.sh <script> | --list  = usage of a row/lane script (not opening it)"),
    @("$ta\status-mark.sh", "bash status-mark.sh $Name <ROW> <STATUS> `"<evidence>`" [--lane $Lane] [--next `"<step>`"]  = mark-row.py + agent-status + quiet TESTS commit/push in ONE call"),
    @("$ta\wait-row.sh", "bash wait-row.sh <out-file|batch-dir> [max_s=110]  = one-line poll of a backgrounded row/batch (experimental)"),
    @("$ra\go-row.sh", "bash go-row.sh [--allow-retry `"<why>`"] <ROW> $Lane  = preflight + row + evidence; prints ONE `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [excerpt=<file>]` line (exit 4 = ROW-NEEDS-FIXER)"),
    @("$ra\go-batch.sh", "bash go-batch.sh <lane> ROW1 ROW2 ...  = whole row list as ONE detached job; wait with event-wait.sh --batch <dir>"),
    @("$ta\lane-setup.sh", "bash lane-setup.sh <5090|4080> <instance> <save|-> [--with NAME] [--teleport x y z]  = one-command lane reset (load save, speed 0, heal, player at The Hub)"),
    @("$ta\event-wait.sh", "bash event-wait.sh [--batch <dir>]  = background waker (<= 120 s); restart when it wakes you")
) | Where-Object { Test-Path -LiteralPath $_[0] }
if ($Pilot) {
    $helpers = @(
        @("$ta\pilot-mark.sh", "bash /c/KenshiModding/tools/automation/pilot-mark.sh $Name <ROW> START | <PASS|FAIL|SETUP-FAIL|GATED|ESCALATE> `"<one line>`" --evidence-file <file>  = the ONLY way to record a row (exit 0 ok, 3 your verdict disagrees with the checker line, 4 row closed/escalated)"),
        @("$ta\logwin.sh", "bash logwin.sh <log> <pattern|since:<regex>|at:HH:MM:SS[+SEC]> [maxchars=2500]  = capped log window (RESULT lines never cut)"),
        @("$ta\usage.sh", "bash usage.sh <script> | --list  = usage of a row/lane script"),
        @("$ta\lane-setup.sh", "bash lane-setup.sh 5090 4 kah-imm26-i4 --with Cind  = lane reset (load save, speed 0, heal, player at The Hub); use when preflight says dist>=80"),
        @("$ta\event-wait.sh", "bash event-wait.sh [--batch <dir>]  = background waker (<= 120 s)")
    ) | Where-Object { Test-Path -LiteralPath $_[0] }
}
# PI-48 standing rule (every brief, pilot or not): a bare `stobe-auto` answers from Shay's LIVE install. While a pilot is ACTIVE the PreToolUse guard (hooks\kenshi-waker-guard.ps1) also refuses it.
$banRule = "- STOBE-AUTO BAN (PI-48): NEVER run bare ``stobe-auto`` (no KAH_DIR) or any command on the live install / default port / Steam Kenshi dir: it answers from Shay's LIVE game, not this lane. Lane-scoped tools only: go-row/go-batch/row scripts, lane-setup.sh, preflight.sh, status tools, kenshi-ctl.ps1 with KAH_INSTANCE=<n>. A by-hand harness query is only ``KAH_DIR='$($l.dir)\mods\AutomationHarness' stobe-auto ...``."
$pilotRules = @()
if ($Pilot) {
    $pm = "bash /c/KenshiModding/tools/automation/pilot-mark.sh $Name"
    $pilotRules = @(
        '- Scope: ONE lane (above). Never the live install, live server tree or DB, Shay''s saves, or another lane. PLAYER_NAME=''Shay''. Windowed launches, never focus the game.',
        $banRule,
        ('- SHADOW MODE (hard): you NEVER claim rows (no mkdir claims, no next-row.sh --claim), NEVER write testing/NPC_IMMERSION_26_TESTS.md or tickets (no mark-row.py, status-mark.sh, setupfail.ps1), NEVER git commit/push. The ONLY recording tool is ' + $pm + ' ... (it also updates your agent status).'),
        '- Verdict = what the checker printed. PASS/FAIL are accepted only if the evidence file holds the matching `RESULT <row> PASS|FAIL` line (exit 3 = you disagreed with the checker: re-mark with the checker''s word or ESCALATE; a 2nd disagreement escalates). SETUP-FAIL, GATED, ROW-NEEDS-FIXER, a 2nd FAIL of one row, no RESULT line, odd logs = ESCALATE (exit 4) and go to the NEXT row. A closed row (exit 4) is never retried.',
        '- One attempt per row, no debugging, no fixing. Do not open evidence files except to quote the checker line; do not read the TESTS file, the long briefs or old handoffs. The pilot measures you, not the fix.',
        '- Deploy: tools/automation/lane-deploy.sh is the ONLY server deploy path (and you only run it if the coordinator tells you); never edit server or DLL files. The lane is already on the same Stobe.dll and server bundle as the Sonnet lane.',
        ('- ANYTHING outside the one-call scripts above (lane or game down, launch problem, LLM health 402/empty replies, preflight errors you cannot fix with lane-setup.sh, unclear instruction): do NOT improvise. Record it with ' + $pm + ' 00-ask ESCALATE "<what you need>" (this only messages the coordinator, it does not close anything), then end your turn with a 2-line handback; the coordinator answers.'),
        '- Game speed (PI-20): above 5 only under bash tools/stobe-goal-watch.sh; never speed 10 for minutes. Never sleeps > 120 s in one call (hook denies); poll in 30 s loops.',
        '- Status: agent-status.ps1 at start and after every row (pilot-mark.sh does it for you after each call); silence > 20 min = killed. Keep your handoff file current. Checkpoint every ~40k tokens; at ~120k finish the row, write the handoff, end STOPPED-CONTEXT.',
        '- Ending: after the last row of rows-i4.txt (or every remaining row escalated) end DONE with a line "pilot rows: <n> accepted, <n> escalated, <n> refused". Hand-back (SubagentHandback) = AT MOST 8 lines: verdict, files/commits, SHA/paths, one next action, any DECISION/QUESTION for Shay; full report first via save-report.ps1.'
    )
}

function Build([int]$exBudget) {
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# OPERATOR BRIEF lane $Lane (generated $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) by lane-brief.ps1; this brief is the ONLY required reading: read it, then the predecessor handoff, then test)")
    $null = $sb.AppendLine("You are operator '$Name' for ISOLATED lane $Lane only (never the live install, live server tree or DB, other lanes, or Shay's saves).")
    if ($Pilot) { $null = $sb.AppendLine("PILOT $Pilot (SHADOW MODE, Shay-approved head-to-head vs the Sonnet operator on 5090-i3; same build, same rows; only the model differs): you record rows ONLY with pilot-mark.sh. Setup + exact launch: C:\KenshiTestRuns\pilot\haiku-i4\SETUP.md. Row list: C:\KenshiTestRuns\pilot\rows-i4.txt.") }
    if ($Predecessor) {
        $pw = Join-Path $ag "$Predecessor.warn"; $ps = Join-Path $ag "$Predecessor.status"
        $pl = "agents\${Predecessor}.handoff.md"
        $null = $sb.AppendLine('## PREDECESSOR HANDOVER (the old operator may still be running: do NOT touch the game yet)')
        $null = $sb.AppendLine("- Predecessor: $Predecessor (status C:\KenshiTestRuns\agents\$Predecessor.status, handoff C:\KenshiTestRuns\$pl, warn marker agents\$Predecessor.warn). You started BEFORE it died.")
        $null = $sb.AppendLine("- Until the handoff exists (and is newer than the .warn marker if one exists) OR the first status line says DONE, STOPPED-CONTEXT or FAILED: NO game commands (no kenshi-ctl launch/stop, stobe-auto, go-row/go-batch, lane-setup, lock, inflight marker). Reading files is fine.")
        $null = $sb.AppendLine('- Wait with ONE bash call (about 60 s per check); it prints PREDECESSOR-READY or PREDECESSOR-TIMEOUT after 90 min:')
        $null = $sb.AppendLine("    A=/c/KenshiTestRuns/agents; P=$Predecessor; for i in `$(seq 1 90); do if { [ -f `$A/`$P.handoff.md ] && { [ ! -f `$A/`$P.warn ] || [ `$A/`$P.handoff.md -nt `$A/`$P.warn ]; }; } || head -1 `$A/`$P.status 2>/dev/null | grep -qE '\| (DONE|STOPPED-CONTEXT|FAILED) \|'; then echo PREDECESSOR-READY; break; fi; sleep 60; done; [ `$i -ge 90 ] && echo PREDECESSOR-TIMEOUT")
        $null = $sb.AppendLine('- Then re-read the predecessor handoff whole, check the lane lock/inflight is free, take the lock, and CONTINUE from its TODO list. Lock still held: wait one more loop; on PREDECESSOR-TIMEOUT tell the coordinator in <= 3 lines and stop.')
        $null = $sb.AppendLine("- STATUS TASK (agent-guard: your task text must EQUAL the predecessor's; $taskNote): $taskTxt")
        $null = $sb.AppendLine("  first status call (paste): $as $Name RUNNING `"$taskQ`" `"started, reading brief`" `"<evidence dir>`" `"wait for $Predecessor handoff`"")
        if ($regNote) { $null = $sb.AppendLine("- Lane-owners registration: $regNote") }
    }
    $null = $sb.AppendLine('## Lane facts')
    foreach ($k in $f.Keys) { $null = $sb.AppendLine("- ${k}: $($f[$k])") }
    $null = $sb.AppendLine('## DLLs (read now)')
    foreach ($d in $dllLines) { $null = $sb.AppendLine("- lane Stobe.dll: $d") }
    $null = $sb.AppendLine("- newest NC DLL: $ncLine" + $(if ($match) { " -> $match" }))
    $null = $sb.AppendLine('## LANE STATE (read now; no need to re-derive)')
    foreach ($x in $stLines) { $null = $sb.AppendLine($x) }
    if ($inboxRc.Count) { $null = $sb.AppendLine('## Inbox digest (operator notes for this lane, newest first; open one only if relevant)'); foreach ($x in $inboxRc) { $null = $sb.AppendLine($x) } }
    $null = $sb.AppendLine('## Predecessor handoff')
    if ($ho) {
        $null = $sb.AppendLine("- $($ho.FullName) (updated $($ho.LastWriteTime.ToString('MM-dd HH:mm'))): read it whole if the excerpt is cut; first lines:")
        # water-filling: per-line cap c, weight 2 for Helpers/TODO/LESSONS lines
        $w = @($hoLines | ForEach-Object { if ($_ -match '^\s*(Helpers|TODO|LESSONS)') { 2 } else { 1 } })
        $lo = 40; $hi = 2000
        while ($lo -lt $hi) { $mid = [int](($lo + $hi + 1) / 2); $tot = 0; for ($i = 0; $i -lt $hoLines.Count; $i++) { $tot += [math]::Min($hoLines[$i].Length, $mid * $w[$i]) }; if ($tot -le $exBudget) { $lo = $mid } else { $hi = $mid - 1 } }
        for ($i = 0; $i -lt $hoLines.Count; $i++) { $null = $sb.AppendLine('  ' + (Clip $hoLines[$i] ([math]::Max(60, $lo * $w[$i])))) }
    } elseif ($Pilot) { $null = $sb.AppendLine('- pilot: none (fresh start; the lane is launched from SETUP.md; write your own handoff file at the Commands section path when you stop)')
    } else { $null = $sb.AppendLine('- none found for this lane: ask the coordinator for the lane state; start from lane-setup.sh and the TESTS file') }
    if ($Pilot) {
        $null = $sb.AppendLine("## ROWS (in this order; cd /c/KenshiModding/testing/live-stobe-queue/imm26-assert in Git Bash; each line: row :: the exact one-call command; do not read the TESTS file)")
        $null = $sb.AppendLine("Per row: (1) bash /c/KenshiModding/tools/automation/pilot-mark.sh $Name <ROW> START   (2) run the command exactly, it prints/tees ONE `RESULT <ROW> ...` line   (3) bash /c/KenshiModding/tools/automation/pilot-mark.sh $Name <ROW> <PASS|FAIL> `"<one line>`" --evidence-file C:/KenshiTestRuns/pilot/haiku-i4/out/<ROW>.out  with the SAME word the RESULT line has. Anything else (SETUP-FAIL, GATED, ROW-NEEDS-FIXER, no RESULT line, crash): ESCALATE the row, same call with ESCALATE, then the next row.")
        if ($pilotRows.Count -eq 0) { $null = $sb.AppendLine('- ROW LIST MISSING (C:\KenshiTestRuns\pilot\rows-i4.txt): ask the coordinator, do not guess rows') }
        foreach ($r in $pilotRows) { $null = $sb.AppendLine("- $($r.Id) :: $($r.Cmd)") }
    } else {
    $null = $sb.AppendLine("## Next rows: first 3 in full, rest one line (any other row: bash $ta\row-card.sh <ROW>; $passN rows PASS, $($open.Count) not PASS; next unclaimed: bash $ta\next-row.sh $Lane)")
    if ($pick.Count -eq 0) { $null = $sb.AppendLine('- none open') }
    $rn = 0
    foreach ($r in $pick) {
        $rn++
        if ($rn -gt $fullRows) {
            $null = $sb.AppendLine("### IMM-$($r.Id) [$($r.Status)] <$($src[$r.Id])> $(Clip $r.FSetup 110) | $(if ($rdNote.ContainsKey($r.Id)) { 'script: go-row.sh' } else { 'no row script' }) | full card: bash $ta\row-card.sh $($r.Id)")
            continue
        }
        $null = $sb.AppendLine("### IMM-$($r.Id) [$($r.Status)] <$($src[$r.Id])>")
        $null = $sb.AppendLine("- setup: $($r.FSetup)")
        $null = $sb.AppendLine("- say/action: $($r.FUtter)")
        $null = $sb.AppendLine("- expected evidence: $($r.Expect)")
        if ($r.Neg) { $null = $sb.AppendLine("- negative control: $($r.Neg)") }
        if ($r.Build -and $r.Build -ne 'BASE') { $null = $sb.AppendLine("- build: $($r.Build)") }
        if ($rdNote.ContainsKey($r.Id)) { $null = $sb.AppendLine("- helper: bash $ra\go-row.sh $($r.Id) $Lane   (row script rd_$($r.Id -replace '-',''): $($rdNote[$r.Id]))") }
        else { $null = $sb.AppendLine("- helper: no row script; run by hand (handoff Helpers + lane-setup.sh), bundle the evidence, mark the row")}
    }
    $ported = @($rdNote.Keys | Sort-Object)
    $null = $sb.AppendLine("- rows with a go-row.sh script ($($ported.Count)): $($ported -join ' ')  (everything else is manual)")
    }
    $null = $sb.AppendLine("## Known blockers relevant to $Lane (KNOWN_BLOCKERS.md, $kbSkipped other-lane line(s) left out; need not be read)")
    if ($kbl.Count -eq 0) { $null = $sb.AppendLine('- none listed') }
    foreach ($b in $kbl) { $null = $sb.AppendLine('- ' + (Clip $b $kbClip)) }
    $null = $sb.AppendLine('## Essential rules (condensed; the long briefs need NOT be read)')
    $ruleLines = @(
        '- Scope: ONE lane (above). Never the live install, live server tree or DB, Shay''s saves, or another lane. Test only on the lane''s kah-* save copy; PLAYER_NAME=''Shay''; dist_to_target < 80. Windowed launches, never focus the game (go-row runs isolation check + preflight).',
        '- Debug budget: ONE attempt per row. After FAIL/SETUP-FAIL record the cause (or hypothesis + evidence file) in the row and status `latest`, mark it, move on; the coordinator sends a fixer.',
        '- PI-06 guard (ENFORCED): a row whose last attempt FAILED is not rerun: go-row/go-batch print `ROW-NEEDS-FIXER <row> <lane> cause=...` (exit 4); record it and move on. Override only with a logged reason: `--allow-retry "<why>"` or `row-attempts.ps1 reset <lane> <ROW> "<why>"`.',
        '- SETUP-FAIL (Shay 2026-10-15): the mark must say needs: recipe|server-fix|native|design|fixture + what exactly (mark-row.py refuses a bare one); never just retry; `setupfail.ps1 list` shows your lane''s tickets.',
        '- LLM health (PI-15): empty/"..." replies -> `bash tools/automation/llm-health.sh`; never mark LLM rows during LLM-HEALTH FAIL (402 = no balance); tell the coordinator.',
        '- Alerts (PI-21): inbox\operators\<lane>-alert.txt exists while the coordinator has an open alert for your lane; act, then `alert-ack.ps1 <id> "<action>"`.',
        '- Game speed (PI-20): above 5 ONLY under bash tools/stobe-goal-watch.sh; never speed 10 for minutes; above speed 3 check Shay/squad hunger about every 60 s.',
        '- A PASS = real game/DB state changed (stobe.log line, DB row, inventory delta), never just NPC words. Never weaken an assertion; no unchanged retries. Open evidence files only for a FAIL (its excerpt= file).',
        '- Batching: whole open row list through go-batch.sh (one batch per lane); keep the lane busy (blocked row -> next row, never idle > 2 min). Mark each row in testing/NPC_IMMERSION_26_TESTS.md when it finishes; commit + push that file only (shaylanger <shaylanger2@gmail.com>); never logs, DLLs or runtime state.',
        '- Server/DLL bug: write cause (file+function+evidence) in the row and status `latest`; do not fix it. GATED / needs-native (PI-23): grep the NATIVE sources (C:\KenshiTestRuns\imm26-nc10\src, components/STOBE) for native names, paste grep + result in the row. No `find /` (search a named directory).',
        '- Ending (PI-22): never DONE while runnable non-PASS rows remain; end STOPPED-CONTEXT (successor in the handoff) or DONE with a `lane complete: <why>` line. PI-24: write the steps of a hand-run row without rd_ script into your handoff.',
        '- Status discipline: agent-status after EVERY row (silence > 20 min = killed); keep the handoff file current. Checkpoint every ~40k tokens; ~120k run the WARN-120k step, ~150k finish the row, write the handoff, end STOPPED-CONTEXT (successor name + 1). Budget <= 120k.',
        '- Hand-back (SubagentHandback) = AT MOST 8 lines: verdict (+PASS/FAIL counts), files/commits, SHA/paths (report path), one next action, any DECISION/QUESTION for Shay. Save the full report first (save-report.ps1, <= 30 lines); every hand-back line lands in the coordinator context.'
    )
    $ruleLines = @($ruleLines[0], $banRule) + @($ruleLines | Select-Object -Skip 1)
    if ($Pilot) { $ruleLines = $pilotRules }
    foreach ($ln in $ruleLines) { $null = $sb.AppendLine($ln) }
    $null = $sb.AppendLine("## Helper scripts (all exist now; in $ta, those marked [R] in $ra)")
    $hl = @($helpers); if ($hl.Count -gt 0 -and $hl[0] -is [string]) { $hl = @(, $hl) }
    foreach ($h in $hl) { $null = $sb.AppendLine("- $(Split-Path -Leaf $h[0]): $($h[1])" + $(if ($h[0].StartsWith($ra)) { ' [R]' } else { '' })) }
    $null = $sb.AppendLine('## Commands')
    $null = $sb.AppendLine("- status: $as $Name RUNNING `"$taskQ`" `"<row/step>`" `"<evidence dir>`" `"<next row>`"   (DONE|FAILED|STOPPED-CONTEXT when ending)")
    $null = $sb.AppendLine("- context warning (~120k): $as $Name RUNNING `"$taskQ`" `"WARN-120k <row/step>`" `"<evidence dir>`" `"<next row>`"   (writes agents\$Name.warn)")
    $null = $sb.AppendLine("- handoff file: $ho2 (successor: same name, number + 1)")
    $null = $sb.AppendLine("- report: powershell -NoProfile -File $ta\save-report.ps1 $Name <srcfile>   (save the full report first; then SubagentHandback with AT MOST 8 lines: verdict, files/commits, SHA/paths, one next action, any DECISION/QUESTION for Shay)")
    $sb.ToString()
}
$budget = 2200
$text = Build $budget
while ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxBytes -and $budget -gt 1000) { $budget -= 400; $text = Build $budget }
if ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxBytes) { $kbClip = 200; $inboxRc = $inboxRc2; $budget = 1000; $text = Build $budget }
if ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxBytes) { $fullRows = 2; $kbClip = 160; $budget = 800; $text = Build $budget }
while ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxBytes -and $budget -gt 300) { $budget -= 250; $text = Build $budget }
$bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
if ($Out) { $d = Split-Path -Parent $Out; if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; [System.IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding($false))) }
$text
[Console]::Error.WriteLine("lane-brief: $Lane brief size $bytes bytes (limit $MaxBytes)" + $(if ($bytes -gt $MaxBytes) { ' OVER LIMIT' } else { '' }))
