# lane-brief.ps1 <lane> [-Out path] [-Name op] [-Runs dir] [-Repo dir] [-NoRemote] [-MaxBytes 6000]
# PI-12 (Shay approved 2026-10-15): generate a one-page operator brief for an imm26 lane at call time, so a new operator
# starts testing within ~2 minutes instead of reading the long briefs. Lanes: 5090-i3 5090-i4 5090-i5 4080-i3 4080-i4.
# EVERYTHING dynamic is read when the script runs (no baked SHAs): lane files (lanes-5090.json / lane-defs.4080.json),
# lane DLL SHA256 from the lane install (4080 over ssh; -NoRemote skips it), newest NC DLL in pending-fixes/npc-immersion-26,
# predecessor handoff (newest of the lane's operator names + handoff globs), next 5 non-PASS rows of the lane
# (handoff TODO ids first, else UNRUN/SETUP-FAIL/GATED/FAIL rows) from testing/NPC_IMMERSION_26_TESTS.md,
# testing/KNOWN_BLOCKERS.md bullets, standing rules, exact status/handoff/report command lines.
# Output: stdout, and -Out file when given. Exit 0 ok, 2 bad lane.
param(
    [Parameter(Position = 0)][string]$Lane,
    [string]$Out,
    [string]$Name,
    [string]$Runs = $(if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }),
    [string]$Repo = 'C:\KenshiModding',
    [switch]$NoRemote,
    [int]$MaxBytes = 6000
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
if (-not $Lane -or -not $lanes.Contains($Lane)) { [Console]::Error.WriteLine("usage: lane-brief.ps1 <$($lanes.Keys -join '|')> [-Out path] [-Name op]"); exit 2 }
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
$ho = $cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1
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

# ---- next rows -------------------------------------------------------------------------------------------
$rows = @()
$tf = Join-Path $Repo 'testing\NPC_IMMERSION_26_TESTS.md'
if (Test-Path -LiteralPath $tf) {
    foreach ($ln in (Get-Content -LiteralPath $tf -Encoding UTF8)) {
        if ($ln -notmatch '^\|\s*IMM-(\d{2}-[a-z])\s*\|') { continue }
        $rid = $Matches[1]
        $c = $ln.Trim().Trim('|') -split '(?<!\\)\|'
        $st = $null; for ($i = 5; $i -lt $c.Count; $i++) { $t = $c[$i].Trim(); if ($t -match '^(PASS|FAIL|SETUP-FAIL|GATED|UNRUN)$') { $st = $t; break } }
        if (-not $st) { $st = '?' }
        $rows += [pscustomobject]@{ Id = $rid; Status = $st; Setup = (Clip $c[1] 70); Utter = (Clip ($c[2] -replace '^\s*say:\s*', '') 60) }
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

# ---- known blockers --------------------------------------------------------------------------------------
$kb = Join-Path $Repo 'testing\KNOWN_BLOCKERS.md'
$kbl = @(); if (Test-Path -LiteralPath $kb) { $kbl = @(Get-Content -LiteralPath $kb -Encoding UTF8 | Where-Object { $_ -match '^\s*(-|#{2,})\s+\S' } | ForEach-Object { Clip (($_ -replace '^\s*(-|#+)\s+', '')) 100 }) }

# ---- names / commands ------------------------------------------------------------------------------------
if (-not $Name) {
    $base = if ($cfg.ops.Count) { $cfg.ops[0] } else { "imm26-$Lane-op" }
    $Name = if ($base -match '^(.*?)(\d+)$') { $Matches[1] + ([int]$Matches[2] + 1) } else { $base + '2' }
}
$as = 'powershell -NoProfile -File C:\KenshiModding\tools\automation\agent-status.ps1'
$ho2 = "C:\KenshiTestRuns\agents\$Name.handoff.md"

function Build([int]$exBudget) {
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# OPERATOR BRIEF lane $Lane (generated $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) by lane-brief.ps1; read this, then the predecessor handoff, then test)")
    $null = $sb.AppendLine("You are operator '$Name' for ISOLATED lane $Lane only (never the live install, live server tree or DB, other lanes, or Shay's saves).")
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
    $null = $sb.AppendLine("## Next rows (testing/NPC_IMMERSION_26_TESTS.md; $passN rows PASS, $($open.Count) not PASS)")
    if ($pick.Count -eq 0) { $null = $sb.AppendLine('- none open') }
    foreach ($r in $pick) { $null = $sb.AppendLine("- $($r.Id) [$($r.Status)] $($r.Setup) | say: $($r.Utter)  <$($src[$r.Id])>") }
    $null = $sb.AppendLine('## Known blockers (testing/KNOWN_BLOCKERS.md; read it fully before a gated row)')
    foreach ($b in $kbl) { $null = $sb.AppendLine("- $b") }
    $null = $sb.AppendLine('## Standing rules')
    $null = $sb.AppendLine('- Debug budget: ONE attempt per row; if it fails again, mark the row (FAIL / SETUP-FAIL with the cause) and move on. No unchanged retries, never weaken an assertion; PASS only with real game-state evidence.')
    $null = $sb.AppendLine('- Handbacks to the coordinator <= 8 lines (row, result, evidence path, next). Full text goes in the handoff file / report file.')
    $null = $sb.AppendLine('- Keep status AND handoff files current after every row; mark rows in the TESTS file (the predecessor helper mk/cm) and commit+push TESTS only, as shaylanger.')
    $null = $sb.AppendLine("- Isolated lane only; hold the lane lock/inflight marker above while the lane runs; never fight another operator for a lane; agents never override Shay's orders.")
    $null = $sb.AppendLine('- Idle > 6 min on the lane gets flagged by lane-idle.ps1: keep the next row moving; write handoff at ~150k tokens and stop STOPPED-CONTEXT.')
    $null = $sb.AppendLine('## Commands')
    $null = $sb.AppendLine("- status: $as $Name RUNNING `"$Lane operator`" `"<row/step>`" `"<evidence dir>`" `"<next row>`"   (DONE|FAILED|STOPPED-CONTEXT when ending)")
    $null = $sb.AppendLine("- handoff file: $ho2 (what is up, helpers, DONE rows, TODO rows, lessons; successor: same name with the number incremented)")
    $null = $sb.AppendLine("- report: powershell -NoProfile -File C:\KenshiModding\tools\automation\save-report.ps1 $Name <srcfile>   (final report <= 8 lines; then SubagentHandback)")
    $null = $sb.AppendLine("- lane active check: powershell -NoProfile -File C:\KenshiModding\tools\automation\lane-idle.ps1 -NoMemory")
    $sb.ToString()
}
$budget = 2600
$text = Build $budget
while ([System.Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxBytes -and $budget -gt 300) { $budget -= 250; $text = Build $budget }
if ($Out) { $d = Split-Path -Parent $Out; if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; [System.IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding($false))) }
$text
