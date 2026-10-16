# lane-brief.ps1 <lane> [-Out path] [-Name op] [-Predecessor op] [-Runs dir] [-Repo dir] [-NoRemote] [-MaxBytes 25600]
# PI-12 (Shay approved 2026-10-15): generate a self-contained operator brief for an imm26 lane at call time, so a new operator
# starts testing within ~2 minutes instead of reading the long briefs. Lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4.
# Shay orders #2/#3 (2026-10-15): the GENERATED brief is the only required reading (<= 25 KB). It embeds the KNOWN_BLOCKERS lines
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
    [int]$MaxBytes = 25600
)
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
    $f['save'] = "$($l.save_name) (save dir $($l.save_dir); the handoff may name a newer working save)"
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
            FSetup = (Clip (& $cell 1) 320); FUtter = (Clip (& $cell 2) 240); Expect = (Clip (& $cell 3) 560); Neg = (Clip (& $cell 4) 240); Build = (Clip (& $cell 5) 80) }
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
$taskTxt = "$Lane operator"; $taskNote = ''; $regNote = ''
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
$taskQ = $taskTxt -replace '([`"$])', '`$1'
$ra = Join-Path $Repo 'testing\live-stobe-queue\imm26-assert'
$ta = Join-Path $Repo 'tools\automation'

# helper scripts: [path, one-line usage]; entries whose file is missing are dropped (so the list never lies)
$helpers = @(
    @("$ra\go-row.sh", "bash go-row.sh [--allow-retry `"<why>`"] <ROW> $Lane  = preflight + row steps + evidence + verdict; stdout is ONE `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <evidence> [excerpt=<file>]` line (exit 4 = ROW-NEEDS-FIXER); evidence in <lane dir>\rows\<ROW>\"),
    @("$ra\go-batch.sh", "bash go-batch.sh <lane> ROW1 ROW2 ...  = whole row list as ONE detached job; prints results=<path>; DONE + summary.txt when finished; wait with event-wait.sh --batch <dir>"),
    @("$ra\preflight.sh", "bash preflight.sh $Lane [npc]  = lane answers, isolation, PLAYER_NAME='Shay', leftover deals/trips cleared, dist < 80; PREFLIGHT-OK or PREFLIGHT-FAIL <reason>"),
    @("$ta\lane-setup.sh", "bash lane-setup.sh <5090|4080> <instance> <save|-> [--with NAME] [--teleport x y z]  = one-command reset: load save, speed 0, squad healed, player at The Hub, outlaws cleared"),
    @("$ta\setupfail.ps1", "powershell -NoProfile -File setupfail.ps1 list [-Lane <lane>]  = open SETUP-FAIL unblock tickets (row, age, needs, owner, state); mark rows with python mark-row.py <ROW> <STATUS> `"<evidence>`" --lane <lane>"),
    @("$ta\row-attempts.ps1", "powershell -NoProfile -File row-attempts.ps1 show [lane] | reset <lane> <ROW> `"<why>`"  = per-row attempt counts (PI-06 guard)"),
    @("$ta\lane-isolation-check.ps1", "powershell -NoProfile -File lane-isolation-check.ps1 <5090|4080>  = proves the lane touches no live install/server/DB (go-row runs it)"),
    @("$ta\lane-idle.ps1", "powershell -NoProfile -File lane-idle.ps1 -NoMemory  = which lanes sit idle > 6 min"),
    @("$ta\row-timing-report.ps1", "powershell -NoProfile -File row-timing-report.ps1  = wall time per row from row-timing.log"),
    @("$ta\save-report.ps1", "powershell -NoProfile -File save-report.ps1 $Name <srcfile>  = store your full report under agents\out\$Name\"),
    @("$ta\event-wait.sh", "bash event-wait.sh [--batch <dir>]  = background waker (<= 120 s); restart it each time it wakes you"),
    @("$ta\kenshi-ctl.ps1", "powershell -NoProfile -File kenshi-ctl.ps1 launch|stop ...  = game start/stop on YOUR lane slot only (windowed, never focus the game)")
) | Where-Object { Test-Path -LiteralPath $_[0] }

function Build([int]$exBudget) {
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# OPERATOR BRIEF lane $Lane (generated $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) by lane-brief.ps1; this brief is the ONLY required reading: read it, then the predecessor handoff, then test)")
    $null = $sb.AppendLine("You are operator '$Name' for ISOLATED lane $Lane only (never the live install, live server tree or DB, other lanes, or Shay's saves).")
    if ($Predecessor) {
        $pw = Join-Path $ag "$Predecessor.warn"; $ps = Join-Path $ag "$Predecessor.status"
        $pl = "agents\${Predecessor}.handoff.md"
        $null = $sb.AppendLine('## PREDECESSOR HANDOVER (the old operator may still be running: do NOT touch the game yet)')
        $null = $sb.AppendLine("- Predecessor: $Predecessor (status C:\KenshiTestRuns\agents\$Predecessor.status, handoff C:\KenshiTestRuns\$pl, warn marker C:\KenshiTestRuns\agents\$Predecessor.warn). You were started BEFORE it died.")
        $null = $sb.AppendLine("- Until C:\KenshiTestRuns\$pl exists (and is newer than the .warn marker when one exists) OR the first line of $Predecessor.status says DONE, STOPPED-CONTEXT or FAILED: send NO game commands (no kenshi-ctl launch/stop, no stobe-auto, no go-row/go-batch/lane-setup, no lane lock acquire, no inflight marker). Reading files and this brief is fine.")
        $null = $sb.AppendLine('- Wait cheaply with ONE bash call (an until-loop, about 60 s per check; never repeated tool calls); it prints PREDECESSOR-READY or PREDECESSOR-TIMEOUT after 90 min:')
        $null = $sb.AppendLine("    A=/c/KenshiTestRuns/agents; P=$Predecessor; for i in `$(seq 1 90); do if { [ -f `$A/`$P.handoff.md ] && { [ ! -f `$A/`$P.warn ] || [ `$A/`$P.handoff.md -nt `$A/`$P.warn ]; }; } || head -1 `$A/`$P.status 2>/dev/null | grep -qE '\| (DONE|STOPPED-CONTEXT|FAILED) \|'; then echo PREDECESSOR-READY; break; fi; sleep 60; done; [ `$i -ge 90 ] && echo PREDECESSOR-TIMEOUT")
        $null = $sb.AppendLine('- Then: re-read the predecessor handoff whole, check the lane lock/inflight marker is free (lane facts below), take the lane lock, run lane-idle.ps1 -NoMemory, and CONTINUE from the handoff TODO list. If the lock is still held by the predecessor, wait one more loop; on PREDECESSOR-TIMEOUT tell the coordinator in <= 3 lines and stop.')
        $null = $sb.AppendLine("- STATUS TASK (agent-guard: your task text must EQUAL the predecessor's; $taskNote): $taskTxt")
        $null = $sb.AppendLine("  first status call (paste): $as $Name RUNNING `"$taskQ`" `"started, reading brief`" `"<evidence dir>`" `"wait for $Predecessor handoff`"")
        if ($regNote) { $null = $sb.AppendLine("- Lane-owners registration: $regNote") }
        $null = $sb.AppendLine("- Your own side of the contract: at about 120k context (when the meter warns) run: $as $Name RUNNING `"$taskQ`" `"WARN-120k <current row>`" `"<outputs>`" `"<next>`"  FIRST (that writes agents\$Name.warn and tells the coordinator to start your successor), then finish the current row, write $ho2 and end STOPPED-CONTEXT.")
    }
    $null = $sb.AppendLine('## Lane facts')
    foreach ($k in $f.Keys) { $null = $sb.AppendLine("- ${k}: $($f[$k])") }
    $null = $sb.AppendLine('## DLLs (read now)')
    foreach ($d in $dllLines) { $null = $sb.AppendLine("- lane Stobe.dll: $d") }
    $null = $sb.AppendLine("- newest NC DLL: $ncLine" + $(if ($match) { " -> $match" }))
    $null = $sb.AppendLine('## Predecessor handoff')
    if ($ho) {
        $null = $sb.AppendLine("- $($ho.FullName) (updated $($ho.LastWriteTime.ToString('MM-dd HH:mm'))): read it whole if the excerpt is cut; first lines:")
        # water-filling: per-line cap c, weight 2 for Helpers/TODO/LESSONS lines
        $w = @($hoLines | ForEach-Object { if ($_ -match '^\s*(Helpers|TODO|LESSONS)') { 2 } else { 1 } })
        $lo = 40; $hi = 2000
        while ($lo -lt $hi) { $mid = [int](($lo + $hi + 1) / 2); $tot = 0; for ($i = 0; $i -lt $hoLines.Count; $i++) { $tot += [math]::Min($hoLines[$i].Length, $mid * $w[$i]) }; if ($tot -le $exBudget) { $lo = $mid } else { $hi = $mid - 1 } }
        for ($i = 0; $i -lt $hoLines.Count; $i++) { $null = $sb.AppendLine('  ' + (Clip $hoLines[$i] ([math]::Max(60, $lo * $w[$i])))) }
    } else { $null = $sb.AppendLine('- none found for this lane: ask the coordinator for the lane state; start from lane-setup.sh and the TESTS file') }
    $null = $sb.AppendLine("## Next rows: full definitions (testing/NPC_IMMERSION_26_TESTS.md; $passN rows PASS, $($open.Count) not PASS; grep the row id there only if you need the Evidence column)")
    if ($pick.Count -eq 0) { $null = $sb.AppendLine('- none open') }
    foreach ($r in $pick) {
        $null = $sb.AppendLine("### IMM-$($r.Id) [$($r.Status)] <$($src[$r.Id])>")
        $null = $sb.AppendLine("- setup: $($r.FSetup)")
        $null = $sb.AppendLine("- say/action: $($r.FUtter)")
        $null = $sb.AppendLine("- expected evidence: $($r.Expect)")
        if ($r.Neg) { $null = $sb.AppendLine("- negative control: $($r.Neg)") }
        $null = $sb.AppendLine("- build: $($r.Build)")
        if ($rdNote.ContainsKey($r.Id)) { $null = $sb.AppendLine("- helper: bash $ra\go-row.sh $($r.Id) $Lane   (row script rd_$($r.Id -replace '-',''): $($rdNote[$r.Id]))") }
        else { $null = $sb.AppendLine("- helper: no row script yet; run it by hand with the predecessor handoff Helpers + lane-setup.sh, keep the evidence in a bundle dir and mark the row")}
    }
    $ported = @($rdNote.Keys | Sort-Object)
    $null = $sb.AppendLine("- rows with a go-row.sh script ($($ported.Count)): $($ported -join ' ')  (everything else is manual)")
    $null = $sb.AppendLine("## Known blockers relevant to $Lane (testing/KNOWN_BLOCKERS.md; $kbSkipped line(s) about other lanes/rows left out; the file need NOT be read)")
    if ($kbl.Count -eq 0) { $null = $sb.AppendLine('- none listed') }
    foreach ($b in $kbl) { $null = $sb.AppendLine('- ' + (Clip $b 900)) }
    $null = $sb.AppendLine('## Essential rules (condensed from briefs\COMMON.md + briefs\OPERATOR_COMMON.md + docs\COORDINATOR_IMPROVEMENTS.md; those files exist at C:\KenshiTestRuns\agents\briefs\ but you do NOT need to read them)')
    foreach ($ln in @(
        '- Scope: you own ONE lane (above). Never touch the live install, live server tree or DB, Shay''s saves, or another lane. Run lane-isolation-check first (go-row does). Windowed launches on the lane slot, never focus the game.',
        '- Test only on the lane''s kah-* save copy. PLAYER_NAME=''Shay''. Fail fast if dist_to_target >= 80 (native people list drops NPCs beyond 80 units). Clear leftover deals/trips before each row (preflight does).',
        '- Debug budget: ONE attempt per row. After a FAIL/SETUP-FAIL record the cause (or best hypothesis + evidence file) in the row and your status `latest`, mark it, move on; the coordinator sends a fixer. Never hold the lane on one row.',
        '- PI-06 attempt guard (ENFORCED): go-row.sh / go-batch.sh count attempts per row per lane; a row whose last attempt FAILED is NOT run again: it prints `ROW-NEEDS-FIXER <row> <lane> cause=...` (exit 4), record it and move on. Override only with a logged reason: `go-row.sh --allow-retry "<reason>" <ROW> <lane>` (also go-batch.sh) or `row-attempts.ps1 reset <lane> <ROW> "<reason>"`. PASS clears the count; GATED and PREFLIGHT-FAIL do not count.',
        '- SETUP-FAIL marks (Shay 2026-10-15): a SETUP-FAIL mark must say needs: recipe|server-fix|native|design|fixture and what exactly; never just retry; the coordinator opens a ticket owner. Run setupfail.ps1 list for your lane''s tickets. Mark rows with tools/automation/mark-row.py (a bare SETUP-FAIL is refused; PREFLIGHT-FAIL llm/lane-down is exempt).',
        '- LLM health (PI-15): when replies are empty/"..." run `bash tools/automation/llm-health.sh` (1-token chat check; preflight runs it too and prints PREFLIGHT-FAIL llm provider down). Never mark LLM rows during LLM-HEALTH FAIL (402 = no balance); stop and tell the coordinator.',
        '- Alerts (PI-21): check C:\KenshiTestRuns\inbox\operators\<lane>-alert.txt now and then (it exists while the coordinator has an open alert for your lane, e.g. LANE IDLE); act on it, then close it with `powershell -NoProfile -File C:\KenshiModding\tools\automation\alert-ack.ps1 <id> "<action taken>"` (ack only closes; an active lane clears it by itself).',
        '- Game speed (PI-20): above 5 ONLY under bash tools/stobe-goal-watch.sh; never run speed 10 for minutes (2026-10-15 an operator starved Shay, the test character, and the lane had to be reset). Above speed 3 check Shay/squad hunger about every 60 s.',
        '- A PASS = real game/DB state changed (stobe.log line, DB row, inventory/status delta), never just NPC words. Never weaken an assertion; no unchanged retries.',
        '- Batching: run your WHOLE open row list through go-batch.sh (one batch per lane); by hand only rows the scripts cannot do. Open evidence files only for a FAIL (its excerpt= file). KEEP THE LANE BUSY: a blocked row -> next row; never idle > 2 min (lane-idle.ps1 flags > 6 min).',
        '- Mark each row in testing/NPC_IMMERSION_26_TESTS.md the moment it finishes; commit + push the TESTS file only, identity shaylanger <shaylanger2@gmail.com> (repo-local), one piece per commit. Never commit logs, DLLs or runtime state.',
        '- If a failure points to a server/DLL bug: write cause (file+function+evidence) in the row and your status `latest`; do not fix it yourself. Agents never override Shay''s orders.',
        '- Searching (Shay 2026-10-15): never run `find /` (or any whole-drive find/grep -r from /): Git Bash walks every mounted drive and several runaway finds ate the 5090 CPU for hours. Search a named directory (find <dir> -maxdepth N ...), use the codemaps, `git grep` or Grep/Glob with a path.',
        '- Ending (PI-22): never set DONE while your lane still has runnable non-PASS rows. End with STOPPED-CONTEXT (successor named in the handoff) or DONE only with a `lane complete: <why no row can run>` line in your status `latest`. An early DONE leaves the lane without an operator (2026-10-15 a lane sat empty ~10 min).',
        '- GATED / needs-native claims (PI-23): before you mark a row GATED or `needs: native`, grep the NATIVE sources (C:\KenshiTestRuns\imm26-nc10\src and components/STOBE) for the native names (event types, struct fields, log tags), not the server words, and paste the grep command + result in the row (2026-10-15 row 10-d sat GATED on a server-word grep; the event already existed in NC6/9/10).',
        '- Reruns (PI-24): the FIRST time you hand-run a row that has no rd_<row> script, write down its steps in your handoff file as a runnable list (commands in order) so a second run is one command; before a SECOND manual run ask the coordinator for a row script (never weaken the assertions).',
        '- Status discipline: update agent-status after EVERY row (the monitor counts status/log/evidence activity; silence > 20 min = killed). Keep your handoff file current after every row (what is up, helpers, DONE rows, TODO rows, lessons).',
        '- Checkpoints: every ~40k tokens (and every milestone) refresh status `latest`, the handoff file and the TESTS marks. At ~120k run the WARN-120k status step (see Commands), at ~150k finish the row, write the handoff and end STOPPED-CONTEXT so a fresh successor (name + 1) continues. Budget <= 120k.',
        '- Handbacks to the coordinator are <= 8 lines (verdict, PASS/FAIL counts, report file path, commit hashes, next action). The FULL report goes to a file with save-report.ps1 first (report file <= 30 lines), then end with SubagentHandback.'
    )) { $null = $sb.AppendLine($ln) }
    $null = $sb.AppendLine('## Helper scripts (one line each; all exist now)')
    foreach ($h in $helpers) { $null = $sb.AppendLine("- $(Split-Path -Leaf $h[0]): $($h[1])   [$($h[0])]") }
    $null = $sb.AppendLine('## Commands')
    $null = $sb.AppendLine("- status: $as $Name RUNNING `"$taskQ`" `"<row/step>`" `"<evidence dir>`" `"<next row>`"   (DONE|FAILED|STOPPED-CONTEXT when ending)")
    $null = $sb.AppendLine("- context warning (~120k): $as $Name RUNNING `"$taskQ`" `"WARN-120k <row/step>`" `"<evidence dir>`" `"<next row>`"   (writes agents\$Name.warn; then finish the row, write the handoff, STOPPED-CONTEXT)")
    $null = $sb.AppendLine("- handoff file: $ho2 (what is up, helpers, DONE rows, TODO rows, lessons; successor: same name with the number incremented)")
    $null = $sb.AppendLine("- report: powershell -NoProfile -File $ta\save-report.ps1 $Name <srcfile>   (final report <= 8 lines; then SubagentHandback)")
    $null = $sb.AppendLine("- lane active check: powershell -NoProfile -File $ta\lane-idle.ps1 -NoMemory")
    $sb.ToString()
}
$budget = 5000
$text = Build $budget
while ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxBytes -and $budget -gt 300) { $budget -= 400; $text = Build $budget }
$bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
if ($Out) { $d = Split-Path -Parent $Out; if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; [System.IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding($false))) }
$text
[Console]::Error.WriteLine("lane-brief: $Lane brief size $bytes bytes (limit $MaxBytes)" + $(if ($bytes -gt $MaxBytes) { ' OVER LIMIT' } else { '' }))
