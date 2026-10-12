<#
rig-lane2.ps1: the extra game lanes on one rig (multi-instance, C:\KenshiTestRuns\multi-instance\PLAN.md; agents
multi-instance-c + lane-5090c 2026-10-11). Lane table ($Lanes below): "5090b" = Kenshi instance 2 (D:\KenshiInst\2, window
slot 0), "5090c" = instance 3 (D:\KenshiInst\3, slot 1), install copies made by kenshi-instance.ps1, beside the main lane's
game (instance 1, lane A, films on DISPLAY1). A new lane = one table row (+ rig-runner.ps1 ValidateSet/lists). Started and
controlled through rig-runner.ps1 (-Rig 5090b|5090c; -Ensure / -Start / -Stop / -Status / -Restart / -SelfTest include
them), never run by hand except -SelfTest. Below "instance n" = the lane's instance.

Queue: C:\KenshiTestRuns\queue\<lane>\*.list (run-batch.sh list format, FIFO by numeric prefix); own folder empty = the first
  lane-eligible list from queue\5090, then queue\any (moved into queue\<lane> first: one rename, no double pickup).
  A list is taken only if
  - "# gfx: low" (no recording / screenshot / pixel checks: filming stays on lane A), no Stobe rows (STOBE-*,
    tests/ingame/stobe, *.txt), no "# rig: 4080";
  - [OFF since speed-scout r8, Shay 17:20 + 19:00: only while runner\<lane>.xbow-serial exists] crossbow guard (NO PC CRASHES, 2026-10-11 BSOD: every TDR was on a crossbow shot/reload frame): no row command names
    a crossbow/ranged/turret/reload script or switch (fp-xbow*, crossbow, ranged, turret, reload, XB* rows, VMQUICK);
  - no "# tdr-isolate: yes" header. TDR isolation: while lane A runs such a list (or one with a fire/reload row, FireRx), the
    lanes launch nothing, stop an idle game, and end + requeue a running batch (xbow-escalate 2026-10-11).
  Lists that break a rule go to queue\failed\ (+ .result naming the rule); the owner gets a note.
Admission (checked before every launch of instance n): dedicated GPU memory free >= 6 GB (nvidia-smi) AND RAM free >= 7 GB,
  no ALERT-5090-tdr.txt / ALERT-<lane>-tdr.txt; lanes with Cpu=$true in the table (5090c) also need the 1-min CPU average
  < 85 % (Get-Counter, fallback Win32_Processor). Not admitted = the list waits ("waiting: <why>"), nothing is launched.
Memory guard (every tick, all lanes): RAM free < 4 GB -> the highest lane with an unheld batch (5090c before 5090b) writes
  <out>\HOLD ("ram free N MB"): run-batch.sh waits at its next row boundary, batch-health.sh says "HEALTH OK held", the
  lane's stall check is skipped; HOLD is removed when RAM free >= 7 GB (lower lanes resume first). RAM free < 2 GB = the
  highest running lane ends its batch (rig-runner-probe.sh end-batch) and stops its game. An idle lane whose game is up
  stops it at once when RAM free < 4 GB.
Frame cap: lanes run at $Fps (30) fps: KAH_FPS for kenshi-gfx.ps1 at launch + framecap.txt of the copy rewritten every tick
  (the harness rereads it every second). Window: every tick the lane's window is placed at DISPLAY2.left + slot*(window width + 10), top (no room = left where it is),
  HWND_NOTOPMOST, never activated, shrunk to the video mode (1024x768: Kenshi replaced 640x360 + 1024x576 (not DXGI modes) and 800x600 (a DXGI mode: Kenshi's minimum?) with the screen's largest mode, m102) if far larger; never on the primary screen (the Samsung).
Per list: if instance n is not running: kenshi-instance.ps1 sync -Instance n -Saves <launch save> (DLLs/mods/cfgs = what
  instance 1 has installed; the lane never installs anything itself); if it runs but instance 1's KenshiFP/harness DLL differs
  from the copy's, instance n is stopped and synced. Then run-batch.sh (snapshot in the out dir, lock game-n.lock owner
  runner-<lane>, KAH_INSTANCE=n, KAH_GFX=low, --launch <save> [--reuse]) detached; out dir C:\KenshiTestRuns\<list>-i<n>-<MMdd-HHmm>
  with .instance (=n, so rig-runner-probe.sh / batch-health.sh / kenshi_pids see only instance n); inflight marker
  runner-<lane>. Window: instance n is retitled "<title> [i<n>]" (kenshi-ctl.ps1 retitle) as soon as it has a window and every
  tick, so lane A's gdigrab title= capture never grabs it.
Every tick (30 s) of a batch: TDR guard = System-log nvlddmkm/Display 4101|153 since the batch started (same rule as
  rig-runner.ps1 TdrFilter) or an ALERT-5090-tdr.txt from lane A -> PREEMPT TDR, instance n stopped, ALERT-<lane>-tdr.txt,
  <lane>.stopped, loop exits (lane A's own guard stops instance 1 on the same events: one GPU). batch-health.sh STALL held
  >= 10 min -> rig-runner-probe.sh end-batch + instance n stopped. DONE -> queue\done\<list> + .result + .SUMMARY.txt.
  Queue empty (IdleStopMin, 0 since speed-scout r8) -> instance n stopped (frees ~4 GB RAM / 2.5 GB VRAM).
Files: runner\<lane>.{pid,log,state,cur,stopped,restart}; ALERT-<lane>-tdr.txt.
  rig-lane2.ps1 -SelfTest   eligibility + admission (GPU/RAM/CPU) + TDR filter + lane table + memory-guard order (no side effects)
#>
param([switch]$SelfTest, [switch]$Fake, [ValidateSet('5090b', '5090c')][string]$Lane = '5090b', [int]$TickSec = 30, [int]$MinGpuMB = 6144,
      [int]$MinRamMB = 7168, [int]$HoldRamMB = 4096, [int]$KillRamMB = 2048, [int]$MaxCpuPct = 85, [int]$Fps = 30,
      [int]$StallMin = 10, [int]$IdleStopMin = 0, [int]$SlotPitch = 0, [int]$FilmAfterMin = 0, [string]$FilmMode = '1600 x 900', [string]$FilmMonitor = 'DISPLAY1',
      [string]$VideoMode = '1024 x 768', [string]$Monitor = 'DISPLAY2')   # extra lanes: small windows side by side on DISPLAY2 (lane A films on DISPLAY1, Shay 14:28/14:31)
# lane table: instance (D:\KenshiInst\<n>), window slot on $Monitor, CPU admission (a third game only while the CPU has room)
$Lanes = [ordered]@{ '5090b' = @{ Inst = 2; Slot = 0; Cpu = $false; Film = $true }; '5090c' = @{ Inst = 3; Slot = 1; Cpu = $true; Film = $true } }
# film mode (Shay 15:20 "if we run out of lower graphics work, stop lane 3 and make lane 2 higher graphics"): a Film lane
# with no gfx-low work for $FilmAfterMin min takes filming lists (full gfx, $FilmMode, topmost on its own screen spot) from
# queue\5090 / any; an idle lane stops its game while another films; gfx-low work always comes first again. Takes record
# with Windows Graphics Capture (capture.default = wgc, capture-fix 15:25: covered windows film fine), so filming lanes may
# overlap and are pinned topmost only under gdigrab. Filming lanes sit on $FilmMonitor (DISPLAY1, with lane A: WGC films a
# covered window), never DISPLAY2: DISPLAY2's scaling made lane 5090b's 1600x900 game a 960x540 capture (CAPPROOF FAIL 15:33). A lane's first filming list (per lane, until it passes) starts with a
# CAPPROOF row (capture-proof.sh on the lane's own window); CAPPROOF FAIL = no more film mode on that lane (note to coordinator).
$Inst = $Lanes[$Lane].Inst; $Slot = $Lanes[$Lane].Slot
$runs = 'C:\KenshiTestRuns'; $auto = 'C:\KenshiModding\tools\automation'

# ---------------------------------------------------------------- pure rules (-SelfTest)
function LaneRows([string[]]$lines) { @($lines | Where-Object { $_ -notmatch '^\s*(#|$)' }) }
# instance sync failure (speed-scout r9: 210-fists-zpv4-any went to failed\ on lane 5090c 19:11 for a sync whose output lacked
# the launch save line, the next sync 90 s later was fine): full output -> runner\<lane>.syncfail.txt, one retry, then a list
# stolen from queue\5090|any goes BACK there (lane trouble is not the list's failure); only an own-folder list fails.
function SyncOk([string[]]$sy, [string]$launch) { [bool]@($sy | Where-Object { $_ -like "save $launch -> *" }).Count }
function SyncFailAction([int]$try, [string]$stoleFrom) { if ($try -lt 2) { 'retry' } elseif ($stoleFrom) { "requeue $stoleFrom" } else { 'fail' } }
function CapMode { $m = "$((Get-Content 'C:\KenshiTestRuns\capture.default' -TotalCount 1 -ErrorAction SilentlyContinue))".Trim(); if ($env:KAH_CAPTURE) { $m = $env:KAH_CAPTURE }; if ($m) { $m } else { 'gdigrab' } }
function LaneMon { if ($script:film) { $FilmMonitor } else { $Monitor } }
function Pin { [bool]$script:film -and (CapMode) -ne 'wgc' }   # topmost only while filming with gdigrab (screen area)
function LaneGfx([string[]]$lines) { $g = @($lines | Where-Object { $_ -match '^\s*#\s*gfx:\s*(\S+)' } | ForEach-Object { $Matches[1].ToLower() } | Select-Object -First 1); if ($g -and $g[0] -eq 'low') { 'low' } else { 'full' } }
function Rig4080Copy([string[]]$lines) { @($lines | ForEach-Object { $_ -replace '\bRIG=4080\b', 'RIG=5090' }) }
function LaneReject([string[]]$lines, [bool]$film = $false) {   # $null = the lane may run this list, else why not ($film: a filming lane in film mode)
    if ($lines -match '^\s*#\s*rig:\s*4080') { return '"# rig: 4080" list' }
    if ((XbGuard) -and (IsoHeader $lines)) { return '"# tdr-isolate: yes" (crossbow/turret TDR isolation: lane A only)' }
    if (-not $film -and (LaneGfx $lines) -ne 'low') { return 'not "# gfx: low" (filming/full-gfx lists stay on lane 1)' }
    $rows = LaneRows $lines
    if (-not $rows.Count) { return 'no rows' }
    foreach ($r in $rows) {
        $f = @($r -split '\|'); $cmd = $f[-1]; $id = $f[0].Trim()
        if (($cmd -replace '\S+=\S+', '') -match 'STOBE-|tests/ingame/stobe|\.txt(\s|$)') { return "Stobe row $id (lane 2 has no Stobe server path)" }
        $x = if (XbGuard) { XbowRow $r }; if ($x) { return "crossbow guard: row $id names crossbow/ranged/turret work ($x)" }
    }
    $null
}
# crossbow guard + TDR isolation are OFF (Shay 17:20 "crossbow on all rigs/lanes, no TDR holds", 19:00 "remove any blockers";
# speed-scout r8): only while C:/KenshiTestRuns/runner/<lane>.xbow-serial exists (create it after a TDR if Shay wants crossbow
# serial again) does the lane refuse crossbow/tdr-isolate lists and hold while lane A runs one. The TDR guard (a real
# GPU reset stops the lane) stays on.
$script:XbGuardTest = $null   # -SelfTest pins it
function XbGuard { if ($null -ne $script:XbGuardTest) { return $script:XbGuardTest }; Test-Path -LiteralPath (Join-Path $runs "runner\$Lane.xbow-serial") }
function XbowRow([string]$r) {   # $null or the crossbow word a row names (the melee fixture's save name and the WS_NOXBOW / pf_noxbow guard are not crossbow work)
    $f = @($r -split '\|'); $id = $f[0].Trim()
    $c = $f[-1] -replace '(?i)kah-fpxbow', 'kah-SAVE' -replace '(?i)\w*noxbow\w*', 'GUARD'
    if ($c -match '(?i)(xbow|crossbow|ranged|turret|reload|\bbolt|vmquick|fp-e6-xbow)') { return $Matches[1] }; if ($id -match '^(?i)(XB|T6|VMQ)') { return $id }; $null
}
# TDR isolation (xbow-escalate 2026-10-11, Shay 15:28 crossbow 4080-first then 5090): while lane A runs a list with
# "# tdr-isolate: yes" or a crossbow-guard row, lanes 5090b/c run nothing (a running batch is ended + requeued, the game stopped)
function IsoHeader([string[]]$lines) { [bool](@($lines | Where-Object { $_ -match '^\s*#\s*tdr-isolate:\s*yes' }).Count) }
$FireRx = '(?i)(fire|reload|shoot|shot|tdr|rangedtest|vmquick|xbr-|fp-e6-xbow|turret-take)'   # = rig-lane2-4080.ps1 (turret-nofire / WS_NOXBOW melee must not hold the lanes)
function FireRow([string]$r) {
    $f = @($r -split '\|'); $id = $f[0].Trim()
    $c = $f[-1] -replace '(?i)kah-fpxbow', 'kah-SAVE' -replace '(?i)\w*no-?(xbow|fire|shot|reload)\w*', 'GUARD'
    if ($c -match $FireRx) { return $Matches[1] }; if ($id -match '^(?i)(XB|T6|VMQ)') { return $id }; $null
}
function IsoList([string[]]$lines) { if (IsoHeader $lines) { return $true }; foreach ($l in LaneRows $lines) { if (FireRow $l) { return $true } }; $false }
function LaneAdmit([int]$gpuFreeMB, [int]$ramFreeMB, [bool]$tdr, [int]$cpuPct = -1) {   # $null = may launch instance n; cpuPct -1 = not checked
    if ($tdr) { return 'TDR alert present' }
    if ($gpuFreeMB -lt $MinGpuMB) { return "GPU memory free $gpuFreeMB MB < $MinGpuMB" }
    if ($ramFreeMB -lt $MinRamMB) { return "RAM free $ramFreeMB MB < $MinRamMB" }
    if ($cpuPct -ge $MaxCpuPct) { return "CPU $cpuPct % >= $MaxCpuPct (1-min average)" }
    $null
}
# memory guard decision for lane $me. $act = @{ lane = @{ Active = bool; Held = bool } } of every lane in $Lanes.
# returns 'hold' | 'release' | 'kill' | '' (nothing). Higher instance gives way first; lower instance resumes first.
# filler list skip rule for a lane: $null = may claim, else why not ($q = its filler-rotation.tsv row, $running = names in queue\running)
function FillerSkip([string]$name, [string[]]$lines, $q, [string[]]$running, [datetime]$now) {
    $w = LaneReject $lines; if ($w) { return $w }
    if ($q -and $q.Count -ge 4 -and $q[3] -and ([datetime]$q[3]) -gt $now) { return "benched until $($q[3])" }
    if (@($running | Where-Object { $_ -like "*__filler__$name" }).Count) { return 'running on another lane/rig' }
    $null
}
function MemGuardAct([string]$me, [int]$ramFreeMB, $act) {
    $mi = $Lanes[$me].Inst; $a = $act[$me]; if (-not $a -or -not $a.Active) { return '' }
    $higher = @($Lanes.Keys | Where-Object { $Lanes[$_].Inst -gt $mi -and $act[$_] -and $act[$_].Active })
    $lower = @($Lanes.Keys | Where-Object { $Lanes[$_].Inst -lt $mi -and $act[$_] -and $act[$_].Active })
    if ($ramFreeMB -lt $KillRamMB -and -not $higher.Count) { return 'kill' }
    if ($a.Held) { if ($ramFreeMB -ge $MinRamMB -and -not @($lower | Where-Object { $act[$_].Held }).Count) { return 'release' }; return '' }
    if ($ramFreeMB -lt $HoldRamMB -and -not @($higher | Where-Object { -not $act[$_].Held }).Count) { return 'hold' }
    ''
}
function LaneTdrFilter([string[]]$lines, [long]$since) {
    @($lines | Where-Object { $q = "$_" -split '\|', 4; $q.Count -ge 3 -and $q[0] -match '^\d+$' -and [long]$q[0] -ge $since -and $q[2] -in '4101', '153' -and $q[1] -match '^(nvlddmkm|display)$' })
}
if ($SelfTest) {
    $bad = 0; $n = 0; $script:XbGuardTest = $true   # the legacy guard cases below; guard-off cases at the end
    $low = '# gfx: low'
    $cases = @(
        @('melee gfx low', @($low, 'M | kah-fpxbow | Malzin | Axima | 1200 | DRYRUN_NOREC=1 bash {CR}/x/fp-manual-melee.sh Malzin Skaera {OUT}/M'), ''),
        @('no gfx header', @('M | kah-fpxbow | Malzin | Axima | 1200 | bash x/fp-manual-melee.sh'), 'not "# gfx: low"'),
        @('gfx full', @('# gfx: full', 'M | s | a | b | 1 | bash x/fp-control.sh'), 'not "# gfx: low"'),
        @('crossbow script', @($low, 'XC | kah-fpxbow | a | b | 1 | bash x/fp-xbow-tdrconfirm.sh {OUT}/XC'), 'crossbow guard'),
        @('turret row', @($low, 'T1 | s | a | b | 1 | bash x/fp-turret-take.sh'), 'crossbow guard'),
        @('ranged list', @($low, 'R | s | a | b | 1 | bash x/fp-ranged.sh'), 'crossbow guard'),
        @('XB row id', @($low, 'XBRLD | s | a | b | 1 | bash x/fp-thing.sh'), 'crossbow guard'),
        @('stobe row', @($low, 'S1 | s | a | b | 1 | bash {CR}/KenshiModding/tests/ingame/stobe/STOBE-X.sh'), 'Stobe row'),
        @('save name + WS_NOXBOW guard are not crossbow work', @($low, 'W | kah-fpxbow | a | b | 1 | WS_NOXBOW=1 PF_SAVE=kah-fpxbow bash x/fp-weapon-sweep.sh'), ''),
        @('tdr-isolate list (fp-controls K: no crossbow word)', @($low, '# tdr-isolate: yes', 'K | kah-fpxbow | a | b | 1 | bash x/fp-controls.sh'), '"# tdr-isolate: yes"')
    )
    $g = (Rig4080Copy @('A | s | a | b | 1 | RIG=4080 bash x/fp-control.sh', 'B | s | a | b | 1 | XRIG=40801 bash y')) -join '/'; $n++; $ok = $g -eq 'A | s | a | b | 1 | RIG=5090 bash x/fp-control.sh/B | s | a | b | 1 | XRIG=40801 bash y'; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) steal-4080 copy rewrites RIG=4080 only: $g"
    $cases += ,@('film lane takes a filming list', @('# gfx: full', 'F | s | a | b | 1 | bash x/fp-control.sh'), '', $true)
    $cases += ,@('film lane: crossbow guard still on', @('# gfx: full', 'F | s | a | b | 1 | bash x/fp-xbow-take.sh'), 'crossbow guard', $true)
    $cases += ,@('film lane: never a 4080 list', @('# gfx: full', '# rig: 4080', 'F | s | a | b | 1 | bash x/fp-control.sh'), '"# rig: 4080"', $true)
    $cases += ,@('low lane: never a 4080 list', @($low, '# rig: 4080', 'F | s | a | b | 1 | bash x/fp-control.sh'), '"# rig: 4080"')
    foreach ($c in $cases) { $n++; $g = [string](LaneReject $c[1] ([bool]($c.Count -ge 4 -and $c[3]))); $ok = if ($c[2]) { $g -like "$($c[2])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane2 list $($c[0]): got '$g'" }
    $ad = @(@(20000, 20000, $false, -1, ''), @(5000, 20000, $false, -1, 'GPU'), @(20000, 6000, $false, -1, 'RAM'), @(20000, 7500, $false, -1, ''), @(20000, 20000, $true, -1, 'TDR'),
            @(20000, 20000, $false, 50, ''), @(20000, 20000, $false, 90, 'CPU'))
    foreach ($a in $ad) { $n++; $g = [string](LaneAdmit $a[0] $a[1] $a[2] $a[3]); $ok = if ($a[4]) { $g -like "$($a[4])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane2 admit gpu=$($a[0]) ram=$($a[1]) tdr=$($a[2]) cpu=$($a[3]): got '$g'" }
    # lane table: instance + slot unique, instances >= 2, 5090b = instance 2 (existing copy), 5090c needs CPU room
    $n++; $ins = @($Lanes.Values | ForEach-Object { $_.Inst }); $sl = @($Lanes.Values | ForEach-Object { $_.Slot })
    $ok = (@($ins | Select-Object -Unique).Count -eq $ins.Count) -and (@($sl | Select-Object -Unique).Count -eq $sl.Count) -and -not @($ins | Where-Object { $_ -lt 2 }).Count -and $Lanes['5090b'].Inst -eq 2 -and $Lanes['5090c'].Inst -eq 3 -and $Lanes['5090c'].Cpu
    if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane table: $(($Lanes.Keys | ForEach-Object { "$_=i$($Lanes[$_].Inst)/slot$($Lanes[$_].Slot)" }) -join ' ')"
    # filler pick (coordinator 15:15: lanes idled while queue\filler had gfx-low lists): skip rule + one lane per list
    $fr = @(
        @('gfx-low filler free', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/fp-manual-melee.sh'), $null, @(), ''),
        @('filming filler', 'rg-01.list', @('M | s | a | b | 1 | bash x/fp-control.sh'), $null, @(), 'not "# gfx: low"'),
        @('crossbow filler', 'rg-03.list', @($low, 'R | s | a | b | 1 | bash x/fp-ranged.sh'), $null, @(), 'crossbow guard'),
        @('benched filler', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), @('rg-04.list', 'x', '5090', '2099-01-01T00:00:00', 'dry run FAIL'), @(), 'benched'),
        @('bench expired', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), @('rg-04.list', 'x', '5090', '2000-01-01T00:00:00', 'old'), @(), ''),
        @('lane A runs it', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), $null, @('5090__filler__rg-04.list'), 'running'),
        @('lane 5090c runs it', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), $null, @('5090c__filler__rg-04.list'), 'running'),
        @('other filler running only', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), $null, @('5090b__filler__rg-02.list'), '')
    )
    foreach ($c in $fr) { $n++; $g = [string](FillerSkip $c[1] $c[2] $c[3] $c[4] (Get-Date)); $ok = if ($c[5]) { $g -like "$($c[5])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) filler $($c[0]): got '$g'" }
    $n++; $tf = Join-Path $env:TEMP "lane2-claim-$PID"; Remove-Item $tf -ErrorAction SilentlyContinue; $w = 0
    foreach ($i in 1, 2) { try { $fs = [IO.File]::Open($tf, 'CreateNew', 'Write', 'None'); $fs.Close(); $w++ } catch { } }
    Remove-Item $tf -ErrorAction SilentlyContinue; $ok = $w -eq 1; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) filler claim: two lanes claim one list, $w win(s)"
    # memory guard: which lane holds / releases / is killed (B = 5090b, C = 5090c; a = active, h = held)
    function A([bool]$ba, [bool]$bh, [bool]$ca, [bool]$ch) { @{ '5090b' = @{ Active = $ba; Held = $bh }; '5090c' = @{ Active = $ca; Held = $ch } } }
    $mg = @(
        @('RAM ok, nothing held', '5090c', 20000, (A $true $false $true $false), ''),
        @('RAM low: C holds first', '5090c', 3000, (A $true $false $true $false), 'hold'),
        @('RAM low: B waits while C unheld', '5090b', 3000, (A $true $false $true $false), ''),
        @('RAM low, C held: B holds too', '5090b', 3000, (A $true $false $true $true), 'hold'),
        @('RAM low, C idle: B holds', '5090b', 3000, (A $true $false $false $false), 'hold'),
        @('RAM back: B resumes first', '5090b', 8000, (A $true $true $true $true), 'release'),
        @('RAM back: C waits for B', '5090c', 8000, (A $true $true $true $true), ''),
        @('RAM back, B resumed: C resumes', '5090c', 8000, (A $true $false $true $true), 'release'),
        @('between thresholds: held stays held', '5090c', 5000, (A $true $false $true $true), ''),
        @('RAM critical: C killed', '5090c', 1500, (A $true $true $true $true), 'kill'),
        @('RAM critical: B spared while C runs', '5090b', 1500, (A $true $true $true $true), ''),
        @('RAM critical, C gone: B killed', '5090b', 1500, (A $true $true $false $false), 'kill'),
        @('inactive lane: nothing', '5090c', 1500, (A $true $false $false $false), '')
    )
    foreach ($c in $mg) { $n++; $g = [string](MemGuardAct $c[1] $c[2] $c[3]); $ok = $g -eq $c[4]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) memguard $($c[0]): got '$g' want '$($c[4])'" }
    $n++; $t = @(LaneTdrFilter @('1000|Display|4101|reset', '1100|nvlddmkm|153|err', '1200|disk|153|io', '900|Display|4101|old') 950)
    $ok = ($t | ForEach-Object { ($_ -split '\|')[0] }) -join ',' -eq '1000,1100'; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane2 TDR filter: $($t -join ' ; ')"
    # render size (agreerec-i2 m102: 640x360 is no DXGI mode, Ogre fell back to 4096x2160 and pf_rig expected 1600x900):
    # the lane's video mode is a listed display mode, and rig-env.sh hands the takes that size as RES_W x RES_H
    $n++; $modes = @(Get-CimInstance CIM_VideoControllerResolution -ErrorAction SilentlyContinue | ForEach-Object { "$($_.HorizontalResolution) x $($_.VerticalResolution)" } | Select-Object -Unique)
    $vw = [int]($VideoMode -split " x ")[0]; $ok = ($vw -ge 1024) -and (-not $modes.Count -or $modes -contains $VideoMode); if (-not $ok) { $bad++ }; "$(if ($ok) { "ok  " } else { "FAIL" }) lane video mode $VideoMode is a listed display mode ($($modes.Count) listed) and >= 1024 wide (800x600 fell back to 4096x2160)"
    foreach ($c in @(@("KAH_VIDEO_MODE='$VideoMode' KAH_GFX=low", ($VideoMode -replace ' ', '')), @('KAH_GFX=low', '1280x720'), @('KAH_GFX=full', '1600x900'))) {
        $n++; $g = (& 'C:\Program Files\Git\bin\bash.exe' -c "export $($c[0]); source /c/KenshiModding/tools/automation/rig-env.sh >/dev/null 2>&1; echo `${RES_W}x`${RES_H}" 2>&1 | Select-Object -Last 1)
        $ok = "$g" -eq $c[1]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) rig-env.sh RES for $($c[0]): got '$g' want '$($c[1])'"
    }
    $ic = @(@('tdr-isolate header, no crossbow word', @('# tdr-isolate: yes', 'K | kah-fpxbow | a | b | 1 | bash x/fp-controls.sh'), $true),
            @('crossbow fire row, no header (full gfx lane A list)', @('# gfx: full', 'XC | kah-fpxbow | a | b | 1 | bash x/fp-xbow-tdrconfirm.sh'), $true),
            @('turret nofire row', @($low, 'TN | kah-fpturret | a | b | 1 | bash x/fp-turret-nofire.sh'), $false),
            @('fists on the xbow save', @($low, 'fq0 | kah-fpxbow | a | b | 1 | RIG=5090 FIST_NATIVE=1 bash x/fp-fist-take.sh'), $false),
            @('melee list on the xbow save with WS_NOXBOW', @($low, 'W | kah-fpxbow | a | b | 1 | WS_NOXBOW=1 bash x/fp-weapon-sweep.sh'), $false))
    foreach ($c in $ic) { $n++; $g = [bool](IsoList $c[1]); $ok = $g -eq $c[2]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane2 TDR isolation $($c[0]): iso=$g" }
    # speed-scout r8 (Shay 17:20/19:00): guard off by default = crossbow / turret / tdr-isolate lists run on this lane, no hold
    $script:XbGuardTest = $null; $n++; $ok = -not (XbGuard) -eq -not (Test-Path (Join-Path $runs "runner\$Lane.xbow-serial")); if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) xbow guard follows runner\$Lane.xbow-serial (now $(XbGuard))"
    $script:XbGuardTest = $false
    foreach ($c in @(@('crossbow script', @($low, 'XC | kah-fpxbow | a | b | 1 | bash x/fp-xbow-tdrconfirm.sh {OUT}/XC')), @('turret row', @($low, 'T1 | s | a | b | 1 | bash x/fp-turret-take.sh')),
                     @('tdr-isolate list', @($low, '# tdr-isolate: yes', 'K | s | a | b | 1 | bash x/fp-controls.sh')), @('film xbow list', @('# gfx: full', 'F | s | a | b | 1 | bash x/fp-xbow-take.sh'), $true))) {
        $n++; $g = [string](LaneReject $c[1] ([bool]($c.Count -ge 3 -and $c[2]))); $ok = $g -eq ''; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) guard off: $($c[0]) taken: got '$g'"
    }
    $n++; $ok = ($IdleStopMin -eq 0) -and ($FilmAfterMin -eq 0); if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) no idle holds: IdleStopMin=$IdleStopMin FilmAfterMin=$FilmAfterMin (Shay 19:00)"
    $okSy = @('save kah-fpxbow -> D:\KenshiInst\3\save\kah-fpxbow', 'save kah-squin -> D:\KenshiInst\3\save\kah-squin'); $badSy = @('sync instance 3 -> D:\KenshiInst\3 : 0 junctions', 'save kah-squin -> D:\KenshiInst\3\save\kah-squin')
    foreach ($c in @(@('launch line present', (SyncOk $okSy 'kah-fpxbow'), $true), @('launch line missing (210 case)', (SyncOk $badSy 'kah-fpxbow'), $false),
                     @('1st fail = retry', (SyncFailAction 1 'C:\q\any'), 'retry'), @('2nd fail, stolen = requeue', (SyncFailAction 2 'C:\q\any'), 'requeue C:\q\any'), @('2nd fail, own list = fail', (SyncFailAction 2 ''), 'fail'))) {
        $n++; $ok = "$($c[1])" -eq "$($c[2])"; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) sync failure: $($c[0]): $($c[1])"
    }
    "LANE2-SELFTEST $(if ($bad) { "FAIL $bad" } else { 'PASS' }) $n cases"; exit [int]($bad -gt 0)
}

# ---------------------------------------------------------------- loop (started by rig-runner.ps1 -Rig 5090b|5090c)
$rd = if ($Fake) { Join-Path $runs 'runner\fake' } else { Join-Path $runs 'runner' }
. (Join-Path $PSScriptRoot 'tdr-handled.ps1')   # shared last-handled GPU-reset epoch per rig (no re-trip on an old event)
. (Join-Path $PSScriptRoot 'queue-dry.ps1')   # DryNote/DryClear: idle reason runner\<lane>.dry + coordinator.note-from-runner when the queues run dry (speed-scout r8)
$qd = if ($Fake) { Join-Path $rd 'queue' } else { Join-Path $runs 'queue' }
foreach ($d in "$qd\$Lane", "$qd\running", "$qd\done", "$qd\failed") { New-Item -ItemType Directory -Force $d | Out-Null }
$log = Join-Path $rd "$Lane.log"; $stateF = Join-Path $rd "$Lane.state"; $curF = Join-Path $rd "$Lane.cur"
$dryNF = Join-Path $runs "agents\$(if ($Fake) { 'fake-' })coordinator.note-from-runner"
$stopF = Join-Path $rd "$Lane.stopped"; $tdrF = Join-Path $runs "ALERT-$Lane-tdr.txt"; $tdr1 = Join-Path $runs 'ALERT-5090-tdr.txt'
$owner = "runner-$Lane"; $K2 = "D:\KenshiInst\$Inst"; $K1 = 'D:\Steam\steamapps\common\Kenshi'; $distro = 'DwemerAI4Skyrim3'
function Log([string]$m) { Add-Content $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m" -ErrorAction SilentlyContinue }
function State([string]$m) { Set-Content $stateF "$((Get-Date).ToString('HH:mm')) $m" -ErrorAction SilentlyContinue }
function Note([string]$who, [string]$m) { Add-Content (Join-Path $runs "agents\$who.note-from-rig-runner") "$((Get-Date).ToString('MM-dd HH:mm')) rig-runner $Lane`: $m" -ErrorAction SilentlyContinue }
function Wsl([string[]]$a) { & wsl.exe -d $distro -u root --cd / -- @a 2>&1 | ForEach-Object { "$_" } }
function WslPath([string]$w) { '/mnt/' + $w.Substring(0, 1).ToLower() + ($w.Substring(2) -replace '\\', '/') }
function K2Procs { @(Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$K2\*" }) }
function Ctl2([string[]]$a) {   # workspace kenshi-ctl.ps1 on instance $Inst as runner-<lane>
    $env:KAH_INSTANCE = "$Inst"; $env:KAH_OWNER = $owner; $env:KAH_GFX = $(if ($script:film) { 'full' } else { 'low' }); $env:KAH_VIDEO_MODE = $VideoMode; $env:KENSHI_MONITOR = (LaneMon); $env:KAH_FPS = "$(if ($script:film) { 60 } else { $Fps })"
    if ($script:film) { $env:KAH_LANE_FILM = '1' } else { Remove-Item env:KAH_LANE_FILM -ErrorAction SilentlyContinue }
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-ctl.ps1" @a 2>&1 | ForEach-Object { "$_" } } finally { Remove-Item env:KAH_INSTANCE, env:KAH_GFX, env:KAH_VIDEO_MODE, env:KENSHI_MONITOR, env:KAH_FPS -ErrorAction SilentlyContinue }
}
function Stop2([string]$why) { if (K2Procs) { $o = Ctl2 @('stop'); Log "instance $Inst stopped ($why): $(($o | Select-Object -Last 1))"; if (K2Procs) { foreach ($k in K2Procs) { & taskkill.exe /F /T /PID $k.Id 2>&1 | Out-Null }; Log "instance $Inst force-killed" } } }
function GpuFreeMB { try { [int]((& nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | Select-Object -First 1).Trim()) } catch { 0 } }
function RamFreeMB { [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB) }
# CPU % averaged over $samples x 2 s (30 = the 1-min admission average); -1 = this lane has no CPU rule
function CpuPct([int]$samples) {
    if (-not $Lanes[$Lane].Cpu) { return -1 }
    try { [int](@((Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples $samples -ErrorAction Stop).CounterSamples | ForEach-Object CookedValue) | Measure-Object -Average).Average }
    catch { [int]((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average) }
}
# memory guard input: every lane's batch (runner\<lane>.cur names its out dir) active (no DONE) and held (<out>\HOLD)
function LaneActs {
    $r = @{}
    foreach ($l in $Lanes.Keys) {
        $c = @(Get-Content (Join-Path $rd "$l.cur") -ErrorAction SilentlyContinue)
        $o = if ($c.Count -ge 6) { $c[1] } else { '' }
        $r[$l] = @{ Active = [bool]($o -and -not (Test-Path (Join-Path $o 'DONE'))); Held = [bool]($o -and (Test-Path (Join-Path $o 'HOLD'))) }
    }
    $r
}
# frame cap of this lane's copy (harness rereads framecap.txt every second): $Fps, written only when different
function CapFps { $Fps = if ($script:film) { 60 } else { $Fps }; if ($Fps -gt 0) { $cf = "$K2\mods\AutomationHarness\framecap.txt"; if ((Test-Path (Split-Path $cf)) -and "$((Get-Content $cf -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -ne "$Fps") { Set-Content $cf "$Fps" -Encoding Ascii; Log "framecap $Fps written ($cf)" } } }
# window: DISPLAY2.left + slot*pitch, top; HWND_NOTOPMOST, no activate; shrink to the video mode if far larger; never on
# the primary screen (the Samsung, Shay 14:31). Physical pixels (per-monitor DPI v2 thread).
if (-not ('LaneWin' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class LaneWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct MI { public int cb; public RECT mon; public RECT work; public uint flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dev; }
  delegate bool MonProc(IntPtr m, IntPtr dc, IntPtr r, IntPtr d);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonProc p, IntPtr d);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfoW(IntPtr m, ref MI mi);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  public static string Place(IntPtr h, string dev, int slot, int pitch, int cw, int ch, bool pin) {
    IntPtr old = IntPtr.Zero; try { old = SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }
    try {
      MI found = new MI(); bool ok = false; string want = @"\\.\" + dev.ToUpper();
      EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m, dc, r, d) => { MI mi = new MI(); mi.cb = Marshal.SizeOf(typeof(MI)); if (GetMonitorInfoW(m, ref mi) && mi.dev.ToUpper() == want) { found = mi; ok = true; } return true; }, IntPtr.Zero);
      if (!ok) return "place: " + dev + " is off (window left where it is)";
      if ((found.flags & 1) != 0) return "place: " + dev + " is the primary screen (never used)";
      if (IsIconic(h)) return "place: minimized";
      RECT w, c; GetWindowRect(h, out w); GetClientRect(h, out c);
      int bw = (w.R - w.L) - (c.R - c.L), bh = (w.B - w.T) - (c.B - c.T);
      bool big = (c.R - c.L) > cw * 3 / 2 || (c.B - c.T) > ch * 3 / 2;
      int ww = big ? cw + bw : w.R - w.L, wh = big ? ch + bh : w.B - w.T;   // pitch 0 = own window width + 10 (lanes share one size)
      int x = found.mon.L + slot * (pitch > 0 ? pitch : ww + 10), y = found.mon.T;
      if (x + ww > found.mon.R || y + wh > found.mon.B) return "place: no room for slot " + slot + " (" + ww + "x" + wh + " at " + x + " on " + dev + "): left where it is";
      bool top = (GetWindowLong(h, -20) & 0x8) != 0;
      if (w.L == x && w.T == y && !big && top == pin) return "ok";
      uint fl = 0x10 | 0x200 | (big ? 0u : 0x1u);   // NOACTIVATE | NOOWNERZORDER | (NOSIZE unless shrinking)
      SetWindowPos(h, new IntPtr(pin ? -1 : -2), x, y, cw + bw, ch + bh, fl);   // filming lane: topmost (gdigrab films the screen area)
      return "placed at " + x + "," + y + (big ? " shrunk from client " + (c.R - c.L) + "x" + (c.B - c.T) + " to " + cw + "x" + ch : "") + (top != pin ? (pin ? " (pinned topmost: filming)" : " (was topmost)") : "");
    } finally { if (old != IntPtr.Zero) SetThreadDpiAwarenessContext(old); }
  }
}
'@
}
function PlaceWin {
    $k = K2Procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1; if (-not $k) { return }
    $vm = [regex]::Match($(if ($script:film) { $FilmMode } else { $VideoMode }), '(\d+)\s*x\s*(\d+)'); if (-not $vm.Success) { return }
    $r = [LaneWin]::Place($k.MainWindowHandle, (LaneMon), $(if ($script:film) { 0 } else { $Slot }), $SlotPitch, [int]$vm.Groups[1].Value, [int]$vm.Groups[2].Value, (Pin))
    if ($r -ne 'ok' -and $r -ne $script:lastPlace) { Log "window: $r" }; $script:lastPlace = $r
}
$script:lastPlace = ''; $script:film = $false
function TdrEvents([long]$since) {
    $s = [DateTimeOffset]::FromUnixTimeSeconds($since).LocalDateTime
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101, 153; StartTime = $s } -ErrorAction SilentlyContinue | ForEach-Object { '{0}|{1}|{2}|{3}' -f ([DateTimeOffset]$_.TimeCreated).ToUnixTimeSeconds(), $_.ProviderName, $_.Id, (([string]$_.Message -replace '\s+', ' ') -replace '\|', '/') })
}
function DllHash([string]$root) {   # KenshiFP + harness DLLs the game loads (Vortex links resolved by Get-FileHash)
    @(Get-ChildItem "$root\mods" -Recurse -Include 'KenshiFP.dll', 'AutomationHarness.dll' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash $_.FullName).Hash.Substring(0, 8))" }) -join ' '
}
function IsoA {   # lane A (rig-runner -Rig 5090) runs a TDR-isolation list (running\5090__*; lanes are running\5090b__ / 5090c__)
    # Shay 2026-10-11 17:00 (speed): while C:/KenshiTestRuns/runner/<lane>.iso-off exists, this lane keeps running its own
    # NON-crossbow lists beside lane A's crossbow list (the crossbow guard still refuses crossbow lists here; the TDR guard
    # still stops the lane); the coordinator deletes the file after any TDR.
    if (-not (XbGuard) -or (Test-Path -LiteralPath (Join-Path $runs "runner/$Lane.iso-off"))) { return $false }
    foreach ($r in @(Get-ChildItem "$qd\running" -Filter '5090__*' -File -ErrorAction SilentlyContinue)) { if (IsoList @(Get-Content $r.FullName)) { return $true } }
    $false
}
function QSort { @($input) | Sort-Object @{ e = { if ($_.Name -match '^(\d+)') { [long]$matches[1] } else { [long]::MaxValue } } }, @{ e = { -join ($_.Name.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) } } }
function Fail([string]$path, [string]$name, [string]$own, [string]$why) {
    $dst = Join-Path "$qd\failed" $name; Move-Item -LiteralPath $path $dst -Force -ErrorAction SilentlyContinue
    Set-Content "$dst.result" "FAILED $Lane $(Get-Date -Format s) $why"; Log "FAILED $name : $why"
    Note $own "list $name NOT run on lane $Lane ($why); $dst.result."
}
function Retitle { if (K2Procs) { $o = Ctl2 @('retitle'); if ("$o" -match 'set') { Log "$o"; $t = Ctl2 @('ontop', $(if (Pin) { 'on' } else { 'off' })); Log "lane $Lane window $(if (Pin) { 'pinned (filming, gdigrab)' } else { 'not pinned' }): $t" } } }   # topmost only while filming
function TdrStop([string]$m, [string]$out) {
    Set-Content $tdrF @("ALERT $Lane $(Get-Date -Format HH:mm) $m", "Lane $Lane stopped (instance $Inst). A TDR is a crash warning (2026-10-11 BSOD). Delete only once Shay cleared the cause, then rig-runner.ps1 -Start -Rig $Lane.")
    if ($out) { Set-Content (Join-Path $out 'PREEMPT') 'TDR' -ErrorAction SilentlyContinue }
    Stop2 'TDR'; Log "TDR $m"; Note 'coordinator' "$m. Lane $Lane STOPPED, instance $Inst stopped."
    Set-Content $stopF "$(Get-Date -Format s) by TDR guard: $m"; State "STOPPED TDR: $m"; Remove-Item (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue; exit 0
}

# steal the first list from queue\5090 then queue\any that this lane may run ($film = filming lists, not gfx-low ones)
function StealList([bool]$film) {
    foreach ($src in "$qd\5090", "$qd\any") {
        $c = @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Where-Object { $t = @(Get-Content $_.FullName); -not (LaneReject $t $film) -and ($film -eq ((LaneGfx $t) -ne 'low')) }) | Select-Object -First 1
        if ($c) { try { Move-Item -LiteralPath $c.FullName (Join-Path "$qd\$Lane" $c.Name) -ErrorAction Stop; Log "STEAL $(if ($film) { 'FILM ' })$($c.Name) from $src (own folder empty$(if ($film) { ", no gfx-low work $FilmAfterMin min" }))"; $script:stoleFrom = $src; return Get-Item (Join-Path "$qd\$Lane" $c.Name) } catch { } }
    }
    Steal4080 $film
}
# steal from queue\4080 (coordinator m102: the 4080 had a backlog while lanes B/C idled): only while lane 4080 runs a list,
# the head list this lane may run once its rows' hard-coded RIG=4080 become RIG=5090 (no "# rig: 4080" header) and
# list-rigcheck.sh <copy> 5090 says OK (Git Bash; verdict cached per list + mtime). The converted copy goes to queue\<lane>
# (header "# stolen-from: queue\4080 ..."), the original is removed, the owner gets a note.
$script:rc4080 = @{}
function Steal4080([bool]$film) {
    if (-not @(Get-ChildItem "$qd\running" -Filter '4080__*' -File -ErrorAction SilentlyContinue).Count) { return $null }
    $c = @(Get-ChildItem "$qd\4080" -Filter *.list -File -ErrorAction SilentlyContinue | QSort) | Select-Object -First 1
    if (-not $c) { return $null }
    $t = Rig4080Copy @(Get-Content $c.FullName)
    if ((LaneReject $t $film) -or ($film -ne ((LaneGfx $t) -ne 'low'))) { return $null }
    $k = "$($c.Name)|$($c.LastWriteTimeUtc.Ticks)"
    if (-not $script:rc4080.ContainsKey($k)) {
        $tmp = Join-Path $env:TEMP "steal4080-$PID-$($c.Name)"; [IO.File]::WriteAllLines($tmp, [string[]]$t)
        $o = @(& 'C:\Program Files\Git\bin\bash.exe' -lc "bash /c/KenshiModding/tools/automation/list-rigcheck.sh --quiet '$($tmp -replace '\\', '/')' 5090" 2>&1 | ForEach-Object { "$_" })
        Remove-Item $tmp -ErrorAction SilentlyContinue
        $script:rc4080[$k] = if ($LASTEXITCODE -eq 0) { 'OK' } else { "NO $(($o | Select-Object -Last 1))" }
        Log "steal-4080 check $($c.Name): $($script:rc4080[$k])"
    }
    if ($script:rc4080[$k] -ne 'OK') { return $null }
    $claim = Join-Path "$qd\4080" "$($c.Name).stealing-$Lane"
    try { Move-Item -LiteralPath $c.FullName $claim -ErrorAction Stop } catch { return $null }
    $dst = Join-Path "$qd\$Lane" $c.Name
    [IO.File]::WriteAllLines($dst, [string[]](@("# stolen-from: queue\4080 by lane $Lane $(Get-Date -Format s) (RIG=4080 -> RIG=5090, list-rigcheck 5090 OK)") + $t))
    Remove-Item $claim -ErrorAction SilentlyContinue
    $own = @($t | Where-Object { $_ -match '^\s*#\s*owner:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1); $own = if ($own) { $own[0] } else { 'coordinator' }
    Log "STEAL $(if ($film) { 'FILM ' })$($c.Name) from queue\4080 (lane 4080 busy; RIG=4080 -> RIG=5090)"
    Note $own "lane $Lane took $($c.Name) from queue\4080 (the 4080 was busy): it runs on the 5090 with RIG=5090; result in queue\done as usual."
    Get-Item $dst
}
# pre-dry-run ahead (lane-5090c 2026-10-11: every lane list spent ~90 s in run-batch's inline dry run at the boundary):
# while a batch runs, the list this lane would take next (own folder head, else the first eligible queue\5090 / any list)
# gets its dry run in the background through lane A's cache (rig-runner.ps1 -Rig 5090 -PreDryOf, same key, nice 15; at
# most one call per 2 min). At the start a cached PASS = run-batch --no-dryrun, a cached FAIL fails the list at once,
# else the lane waits up to 2 min for it (nice 0) and falls back to run-batch's own dry run.
function PeekNext {
    $c = Get-ChildItem "$qd\$Lane" -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Select-Object -First 1; if ($c) { return $c }
    foreach ($film in @(@($false) + @(if ($Lanes[$Lane].Film) { $true }))) {
        foreach ($src in "$qd\5090", "$qd\any") {
            $c = @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Where-Object { $t = @(Get-Content $_.FullName); -not (LaneReject $t $film) -and ($film -eq ((LaneGfx $t) -ne 'low')) }) | Select-Object -First 1
            if ($c) { return $c }
        }
    }
    $null
}
function LanePreDry([string]$path, [int]$nice, [int]$wait = 0) {   # PASS | FAIL | PENDING | none
    $o = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig-runner.ps1" -Rig 5090 -PreDryOf $path -PreDryNice $nice -PreDryWaitSec $wait 2>&1 | ForEach-Object { "$_" })
    $l = @($o | Where-Object { $_ -like 'PREDRY *' }) | Select-Object -First 1
    if ("$l" -match '^PREDRY \S+ (\S+)') { $Matches[1] } else { 'none' }
}
function PreDryAhead {
    if ($script:pdAt -and ((Get-Date) - $script:pdAt).TotalSeconds -lt 120) { return }
    $script:pdAt = Get-Date; $n = PeekNext; if (-not $n) { return }
    $v = LanePreDry $n.FullName 15
    if ($script:pdLog -ne "$($n.Name) $v") { $script:pdLog = "$($n.Name) $v"; Log "predry ahead $($n.Name): $v" }
}
# a gfx-low filler list with changed rows (rig-runner.ps1 -FillerRows: same ledger as lane A; cached 5 min per list), not
# benched, not running anywhere: claimed by creating running\<lane>__filler__<name> (CreateNew: one lane wins)
$script:fillCache = @{}
function PickFiller {
    $rot = @{}; foreach ($l in @(Get-Content (Join-Path $rd 'filler-rotation.tsv') -ErrorAction SilentlyContinue)) { $q = @($l -split "`t"); if ($q[0]) { $rot[$q[0]] = $q } }
    foreach ($fl in @(Get-ChildItem "$qd\filler" -Filter *.list -File -ErrorAction SilentlyContinue | QSort)) {
        $t = @(Get-Content $fl.FullName)
        if (FillerSkip $fl.Name $t $rot[$fl.Name] @(Get-ChildItem "$qd\running" -File -ErrorAction SilentlyContinue | ForEach-Object Name) (Get-Date)) { continue }
        $c = $script:fillCache[$fl.Name]
        if (-not $c -or ((Get-Date) - $c.At).TotalMinutes -ge 5 -or $c.Stamp -ne $fl.LastWriteTimeUtc.Ticks) {
            $o = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig-runner.ps1" -Rig 5090 -FillerRows $fl.FullName 2>&1 | ForEach-Object { "$_" })
            $c = @{ At = Get-Date; Stamp = $fl.LastWriteTimeUtc.Ticks; Build = @($o | Where-Object { $_ -like "#build`t*" } | Select-Object -First 1); Rows = @($o | Where-Object { $_ -like "ROW`t*" }) }
            $script:fillCache[$fl.Name] = $c
        }
        if (-not $c.Rows.Count -or -not $c.Build.Count) { continue }
        $run = Join-Path "$qd\running" "${Lane}__filler__$($fl.Name)"
        try { $fs = [IO.File]::Open($run, 'CreateNew', 'Write', 'None'); $fs.Close() } catch { continue }
        $rows = @($c.Rows | ForEach-Object { ($_ -split "`t", 3)[2] })
        Set-Content $run (@($t | Where-Object { $_ -match '^\s*(#|$)' }) + $rows)
        $meta = @($c.Build[0]) + @($c.Rows | ForEach-Object { $q = $_ -split "`t", 3; "$(($q[2] -split '\|')[0].Trim())`t$($q[1])" })
        $script:fillCache.Remove($fl.Name)
        Log "FILLER $($fl.Name) claimed: $($rows.Count) changed row(s) ($((@($rows | ForEach-Object { ($_ -split '\|')[0].Trim() })) -join ', '))"
        return @{ Run = $run; Name = $fl.Name; Meta = $meta }
    }
    $null
}
# another lane is filming now (its .gfx says full and it has a batch): an idle lane stops its game to give it the PC
function OtherLaneFilming { foreach ($l in $Lanes.Keys) { if ($l -ne $Lane -and (Test-Path (Join-Path $rd "$l.cur")) -and "$((Get-Content (Join-Path $rd "$l.gfx") -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -eq 'full') { return $true } }; $false }

Log "lane $Lane up pid=$PID"
$noLowSince = $null
# re-adopt: a running batch of this lane keeps its mode (runner\<lane>.gfx = full while it films)
$script:film = (Test-Path $curF) -and "$((Get-Content (Join-Path $rd "$Lane.gfx") -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -eq 'full'
$idleSince = Get-Date; $stall = $null
while ($true) {
    if (Test-Path $stopF) { Log 'stopped flag: exit'; Remove-Item (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue; exit 0 }
    $cur = if (Test-Path $curF) { @(Get-Content $curF) } else { @() }   # runPath, outW, start epoch, owner, start ISO, list name (rig-runner -Status reads [4] + [5])
    if ($cur.Count -ge 6) {
        $outW = $cur[1]; $t0 = [long]$cur[2]; $own = $cur[3]; $name = $cur[5]
        # a finished batch (DONE, e.g. the one a TDR stop left in <lane>.cur) is not guarded: 17:30 a restarted 5090c re-adopted
        # its 16:33 batch and alerted on a later TDR it never ran beside (the DONE branch below clears it)
        $live = -not (Test-Path (Join-Path $outW 'DONE'))
        if ($live -and (Test-Path $tdr1)) { TdrStop "lane A TDR alert ($((Get-Content $tdr1 -TotalCount 1)))" $outW }
        $ts = [Math]::Max($t0 - 30, (TdrHandledGet $Lane $rd $(if ($Fake) { $rd } else { Join-Path $runs 'gpulog' })) + 1)   # events already alerted never re-trip a restarted lane
        $h = if ($live) { @(LaneTdrFilter (TdrEvents $ts) $ts) } else { @() }; if ($h.Count) { TdrHandledSet $Lane (TdrNewest $h) 'lane-guard' $rd; TdrStop "TDR (GPU driver reset) during lane $Lane list $name : $($h[0])" $outW }
        if (IsoA) {   # TDR isolation: lane A started a crossbow/turret list -> end this batch now, requeue it (filler: just release the claim)
            $o = Wsl @('bash', "$(WslPath $auto)/rig-runner-probe.sh", (WslPath $outW), 'end-batch', "lane $Lane TDR isolation: lane A runs a crossbow/turret list"); Stop2 'TDR isolation'
            if ((Split-Path $cur[0] -Leaf) -like '*__filler__*') { Remove-Item -LiteralPath $cur[0] -ErrorAction SilentlyContinue } else { Move-Item -LiteralPath $cur[0] (Join-Path "$qd\$Lane" $name) -Force -ErrorAction SilentlyContinue }
            Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue
            Log "ISOLATION end-batch $name (requeued): $(($o | Select-Object -Last 1))"; Note $own "lane $Lane ended $name (lane A runs a crossbow/turret list, TDR isolation); requeued, reruns after it"
            $idleSince = Get-Date; $stall = $null; continue
        }
        Retitle; PlaceWin; CapFps
        if ($script:film -and -not (Test-Path (Join-Path $outW 'PREEMPT')) -and (Select-String -Path (Join-Path $outW 'SUMMARY.txt') -Pattern '^RESULT CAPPROOF FAIL' -Quiet -ErrorAction SilentlyContinue)) {
            Set-Content (Join-Path $outW 'PREEMPT') "CAPPROOF FAIL on lane $Lane : list back to queue\5090"; Set-Content (Join-Path $outW '.requeue') '5090'; Log "CAPPROOF FAIL: $name preempted, back to queue\5090 at DONE"
        }
        $holdF = Join-Path $outW 'HOLD'; $ram = RamFreeMB
        switch (MemGuardAct $Lane $ram (LaneActs)) {
            'hold' { Set-Content $holdF "ram free $ram MB < $HoldRamMB (lane $Lane memory guard $(Get-Date -Format HH:mm))"; Log "HOLD $name : ram free $ram MB"; Note $own "lane $Lane holds $name at the next row boundary: RAM free $ram MB < $HoldRamMB" }
            'release' { Remove-Item $holdF -ErrorAction SilentlyContinue; Log "HOLD released $name : ram free $ram MB" }
            'kill' {
                Set-Content $holdF "RAM critical: ram free $ram MB < $KillRamMB, batch ended (lane $Lane memory guard)"
                $o = Wsl @('bash', "$(WslPath $auto)/rig-runner-probe.sh", (WslPath $outW), 'end-batch', "lane $Lane RAM critical: free $ram MB"); Log "RAM CRITICAL end-batch ($ram MB free): $(($o | Select-Object -Last 1))"
                Stop2 "RAM critical $ram MB"; Note 'coordinator' "lane $Lane ended $name and stopped instance $Inst : RAM free $ram MB < $KillRamMB"
            }
        }
        if (Test-Path (Join-Path $outW 'DONE')) {
            Remove-Item $holdF -ErrorAction SilentlyContinue
            $sum = Join-Path $outW 'SUMMARY.txt'; $sl = if (Test-Path $sum) { @(Get-Content $sum) } else { @() }
            $p = @($sl | Where-Object { $_ -match '^RESULT \S+ PASS' }).Count; $f = @($sl | Where-Object { $_ -match '^RESULT \S+ FAIL' }).Count
            if ((Split-Path $cur[0] -Leaf) -like '*__filler__*') { $lg = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig-runner.ps1" -Rig 5090 -LedgerFrom $outW -LedgerList $name 2>&1 | ForEach-Object { "$_" }); Log "ledger: $($lg | Select-Object -Last 1)" }
            $rq = "$((Get-Content (Join-Path $outW '.requeue') -TotalCount 1 -ErrorAction SilentlyContinue))".Trim()
            if ($rq) { Move-Item -LiteralPath $cur[0] (Join-Path "$qd\$rq" $name) -Force -ErrorAction SilentlyContinue; Log "REQUEUED $name to queue\$rq"; Note $own "lane $Lane gave $name back to queue\$rq (CAPPROOF FAIL on its window; $outW)" }
            $dst = Join-Path "$qd\done" $name; if (-not $rq) { Move-Item -LiteralPath $cur[0] $dst -Force -ErrorAction SilentlyContinue }
            if (Test-Path $sum) { Copy-Item $sum "$dst.SUMMARY.txt" -Force }
            Set-Content "$dst.result" "DONE $Lane start=$([DateTimeOffset]::FromUnixTimeSeconds($t0).LocalDateTime.ToString('s')) end=$(Get-Date -Format s) out=$outW pass=$p fail=$f summary=$dst.SUMMARY.txt"
            $cp = @($sl | Where-Object { $_ -match '^RESULT CAPPROOF (PASS|FAIL)' } | Select-Object -Last 1)
            if ($cp) { Set-Content (Join-Path $rd "$Lane.capproof") "$($Matches[1]) $(Get-Date -Format s) $outW"; if ($cp[0] -match 'FAIL') { Note 'coordinator' "lane $Lane CAPPROOF FAIL ($outW): film mode off for this lane until $Lane.capproof is deleted" } }
            Log "DONE $name pass=$p fail=$f"; Note $own "lane $Lane finished $name : pass=$p fail=$f, $dst.SUMMARY.txt"
            Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; $idleSince = Get-Date; $stall = $null; continue
        }
        $hl = (Wsl @('bash', "$(WslPath $auto)/batch-health.sh", (WslPath $outW)) | Select-Object -Last 1)
        # a batch waiting on HOLD reads "HEALTH OK held" (batch-health.sh): no stall
        if ($hl -match '^HEALTH STALL') { if (-not $stall) { $stall = Get-Date }; if (((Get-Date) - $stall).TotalMinutes -ge $StallMin) {
                $o = Wsl @('bash', "$(WslPath $auto)/rig-runner-probe.sh", (WslPath $outW), 'end-batch', "lane $Lane stall: $hl"); Log "STALL end-batch: $hl / $(($o | Select-Object -Last 1))"; Stop2 'stall'; $stall = $null } }
        else { $stall = $null }
        PreDryAhead
        State "running $name -> $outW ($(if ($stall) { "STALL since $($stall.ToString('HH:mm')): " })$hl)"
        Start-Sleep $TickSec; continue
    }
    # rig-runner.ps1 -Restart: re-spawn at the list boundary, only if the runner scripts parse (runner-parse-ok.ps1: else this
    # old loop keeps running + ALERT-<lane>-restart.txt, the flag stays)
    $pk = if (Test-Path (Join-Path $rd "$Lane.restart")) { [string](& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\runner-parse-ok.ps1" -Rig $Lane 2>&1 | Select-Object -Last 1) } else { '' }
    if ($pk -and $pk -notlike 'PARSE OK*' -and $script:parseLogged -ne $pk) { $script:parseLogged = $pk; Log "restart refused, old loop keeps running: $pk" }
    if ($pk -like 'PARSE OK*') {
        Remove-Item (Join-Path $rd "$Lane.restart"), (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue
        Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$auto\rig-runner.ps1", '-Rig', $Lane); Log 'restart: re-spawned'; exit 0
    }
    if ((Test-Path $tdr1) -or (Test-Path $tdrF)) { Stop2 'TDR alert'; State "waiting: TDR alert present (no instance $Inst launch)"; Start-Sleep $TickSec; continue }
    if (IsoA) { Stop2 'TDR isolation'; State 'waiting: lane A runs a crossbow/turret list (TDR isolation)'; Start-Sleep $TickSec; continue }
    # pick (lane-5090c 2026-10-11): own folder head; else the first gfx-low list from queue\5090 then queue\any (coordinator
    # 14:35: no lane idles while another has a backlog; moved into queue\<lane> first: one rename, lane A can't take it too);
    # else a gfx-low filler list with rows changed since their last PASS (rig-runner.ps1 ledger; claimed as
    # running\<lane>__filler__<name>, so lane A and the other lanes skip it); else, on a Film lane after $FilmAfterMin min with
    # none of that, a filming list from queue\5090 / any (film mode). Only while instance $Inst may run now.
    $script:stoleFrom = $null
    $f = Get-ChildItem "$qd\$Lane" -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Select-Object -First 1
    $fill = $null; $film = $false
    $admit = (K2Procs) -or -not (LaneAdmit (GpuFreeMB) (RamFreeMB) ((Test-Path $tdr1) -or (Test-Path $tdrF)) (CpuPct 3))
    if (-not $f -and $admit) { $f = StealList $false }
    # filming work beats filler (coordinator m102: filler kept lane B off film mode): only real gfx-low lists hold film mode
    # off ($noLowSince); a Film lane takes a queued filming list before a filler list once $FilmAfterMin min passed without them
    if ($f) { $noLowSince = $null } elseif (-not $noLowSince) { $noLowSince = Get-Date }
    if (-not $f -and $admit -and $Lanes[$Lane].Film -and "$((Get-Content (Join-Path $rd "$Lane.capproof") -TotalCount 1 -ErrorAction SilentlyContinue))" -notlike 'FAIL*' -and ((Get-Date) - $noLowSince).TotalMinutes -ge $FilmAfterMin) { $f = StealList $true }
    if (-not $f -and $admit) { $fill = PickFiller }
    if (-not $f -and -not $fill) {
        if ((K2Procs) -and (RamFreeMB) -lt $HoldRamMB) { Stop2 "idle and RAM free $(RamFreeMB) MB < $HoldRamMB" }
        if ((K2Procs) -and (OtherLaneFilming)) { Stop2 'idle while lane 5090b films (Shay 15:20: stop lane 3 for it)' }
        if ((K2Procs) -and ((Get-Date) - $idleSince).TotalMinutes -ge $IdleStopMin) { Stop2 "queue empty $IdleStopMin min" }
        State "idle: no work for lane $Lane (own folder, queue\5090/any gfx-low, changed filler$(if ($Lanes[$Lane].Film) { ', filming after ' + $FilmAfterMin + ' min' }))$(if (K2Procs) { " (instance $Inst up)" })"; $null = DryNote $Lane "$((Get-Content $stateF -TotalCount 1) -replace '^\S+ ', '')" $rd $dryNF $qd; Start-Sleep $TickSec; continue
    }
    DryClear $Lane $rd
    if ($fill) { $runPre = $fill.Run; $name = $fill.Name; $txt = @(Get-Content $runPre) } else { $runPre = $null; $txt = @(Get-Content $f.FullName); $name = $f.Name }
    $own = @($txt | Where-Object { $_ -match '^\s*#\s*owner:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1); $own = if ($own) { $own[0] } else { 'coordinator' }
    $film = $Lanes[$Lane].Film -and (LaneGfx $txt) -ne 'low'
    $why = LaneReject $txt $film; if ($why) { if ($fill) { Remove-Item $runPre -ErrorAction SilentlyContinue; Log "filler $name not eligible: $why" } else { Fail $f.FullName $name $own $why }; continue }
    $noDry = $false
    if (-not $fill) {
        $v = LanePreDry $f.FullName 0 120
        if ($v -eq 'FAIL') { Fail $f.FullName $name $own 'dry run FAIL (cached: rig-runner.ps1 -Rig 5090 -PreDryOf <list> shows the DRYRUN FAIL lines)'; continue }
        $noDry = $v -eq 'PASS'; Log "predry $name : $v$(if ($noDry) { ' (run-batch skips its dry run)' })"
    }
    $script:film = $film
    $up = [bool](K2Procs)
    $gfxF = Join-Path $rd "$Lane.gfx"; $want = if ($film) { 'full' } else { 'low' }
    $have = "$((Get-Content $gfxF -TotalCount 1 -ErrorAction SilentlyContinue))".Trim(); if (-not $have) { $have = 'low' }   # no .gfx yet = a game the lane started before film mode existed: low
    if ($up -and $have -ne $want) { Stop2 "gfx switch to $want"; $up = $false }
    if (-not $up) { $why = LaneAdmit (GpuFreeMB) (RamFreeMB) ((Test-Path $tdr1) -or (Test-Path $tdrF)) (CpuPct 30); if ($why) { if ($fill) { Remove-Item $runPre -ErrorAction SilentlyContinue }; State "waiting: $why ($name queued)"; Start-Sleep $TickSec; continue } }
    $launch = @($txt | Where-Object { $_ -match '^\s*#\s*launch:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $launch = if ($launch) { $launch[0] } else { ((LaneRows $txt)[0] -split '\|')[1].Trim() }
    # every kah-* test save, not only the list's header one (Shay 2026-10-11: all lanes can use all saves at the same time).
    # run-batch's load_target swaps the launch save for the row script's pf_load target and rows name their own saves:
    # m102 96-agree-rec sat on the menu 6 min because instance $Inst had kah-fpxbow but not kah-fpstudio.
    $saves = @(@($launch) + @(Get-ChildItem "$env:LOCALAPPDATA\kenshi\save" -Directory -Filter 'kah-*' | ForEach-Object Name) | Select-Object -Unique)
    if ($up -and (DllHash $K1) -ne (DllHash $K2)) { Log "instance 1 has other DLLs ($(DllHash $K1)) than instance $Inst ($(DllHash $K2)): stop + sync"; Stop2 'DLL sync'; $up = $false }
    if (-not $up) {
        $syTry = 0; $syAct = ''
        while ($true) {
            $syTry++
            $sy = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-instance.ps1" sync -Instance $Inst -Saves ($saves -join ',') 2>&1 | ForEach-Object { "$_" })
            Log "sync: $(($sy | Select-Object -Last 2) -join ' / ')"
            if (SyncOk $sy $launch) { break }
            Set-Content (Join-Path $rd "$Lane.syncfail.txt") (@("$(Get-Date -Format s) try $syTry list $name launch '$launch' saves $($saves -join ',')") + $sy)
            $syAct = SyncFailAction $syTry $script:stoleFrom; Log "sync failed (try $syTry, launch '$launch' line missing; full output runner\$Lane.syncfail.txt): $syAct"
            if ($syAct -ne 'retry' -or $fill) { break }
            Start-Sleep 5
        }
        if (-not (SyncOk $sy $launch)) {
            if ($fill) { Remove-Item $runPre -ErrorAction SilentlyContinue; Log "filler $name : sync failed"; continue }
            if ($syAct -like 'requeue *') { $back = $syAct.Substring(8); Move-Item -LiteralPath $f.FullName (Join-Path $back $name) -Force -ErrorAction SilentlyContinue; Log "REQUEUED $name to $back (instance $Inst sync failed twice)"; State "waiting: instance $Inst sync failed twice (runner\$Lane.syncfail.txt), $name back in $back"; Start-Sleep 60; continue }
            Fail $f.FullName $name $own "instance $Inst sync failed: $(($sy | Select-Object -Last 2) -join ' / ')"; continue
        }
    } else {
        $sy = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-instance.ps1" save ($saves -join ',') -Instance $Inst 2>&1 | ForEach-Object { "$_" }); Log "save copy: $(($sy | Select-Object -Last 1))"
    }
    $outN = @($txt | Where-Object { $_ -match '^\s*#\s*out:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $outN = if ($outN) { "$($outN[0])-i$Inst$(if ($fill) { '-' + (Get-Date -Format MMdd-HHmm) })" } else { "$([IO.Path]::GetFileNameWithoutExtension($name))-i$Inst-$(Get-Date -Format MMdd-HHmm)" }
    # never reuse an old out dir: a "# out:" name made a requeued film list start in its old dir, whose PREEMPT (CAPPROOF
    # FAIL) ended the new batch at once, a loop every 30 s (16:04, lane 5090c fistbzany-i3); -2, -3 ... like rig-runner.ps1
    $outW = Join-Path $runs $outN; $i = 2; while (Test-Path $outW) { $outW = Join-Path $runs "$outN-$i"; $i++ }
    $outP = WslPath $outW; New-Item -ItemType Directory -Force $outW | Out-Null
    if ($fill) { $run = $runPre; Set-Content (Join-Path $outW 'rowmeta.tsv') $fill.Meta } else { $run = Join-Path "$qd\running" "${Lane}__$name"; Move-Item -LiteralPath $f.FullName $run -Force }
    Set-Content $gfxF $want
    $capF = Join-Path $rd "$Lane.capproof"; $capS = "$((Get-Content $capF -TotalCount 1 -ErrorAction SilentlyContinue))"
    $ll = @(Get-Content $run)
    if ($film -and $capS -notlike 'PASS*') { $ll = @($ll | Where-Object { $_ -match '^\s*(#|$)' }) + @("CAPPROOF | kah-fpstudio | Axima | Malzin | 300 | bash {CR}/KenshiModding/tools/automation/capture-proof.sh {OUT}/capproof 3") + @(LaneRows $ll); Log "film: CAPPROOF row first (lane window never proven yet)" }
    Set-Content (Join-Path $outW 'list.txt') ($ll -replace '\{CR\}', '/mnt/c' -replace '\{RIG\}', '5090');   # {CR} = /mnt/c (as rig-runner.ps1 does)
    Set-Content (Join-Path $outW '.instance') "$Inst"
    Copy-Item "$auto\run-batch.sh" (Join-Path $outW '.run-batch.sh') -Force
    $rl = if ($up) { '--reuse ' } else { '' }
    if ($noDry) { $rl += "--no-dryrun 'lane $Lane predry PASS cached' " }
    $ev = if ($film) { "KAH_GFX=full KAH_FPS=60 KAH_LANE_FILM=1" } else { "KAH_GFX=low KAH_VIDEO_MODE='$VideoMode' KAH_FPS=$Fps" }
    $st = "#!/bin/bash`nexport KAH_OWNER=$owner $ev KAH_INSTANCE=$Inst KDIR=/mnt/d/KenshiInst/$Inst KAH_DIR='D:\KenshiInst\$Inst\mods\AutomationHarness' KENSHI_MONITOR=$(LaneMon) WSLENV=KAH_OWNER:KAH_GFX:KAH_INSTANCE:KAH_VIDEO_MODE:KENSHI_MONITOR:KAH_FPS:KAH_LANE_FILM`ncd /`nsetsid nohup bash $outP/.run-batch.sh --launch $launch $rl$outP/list.txt $outP >/dev/null 2>&1 </dev/null &`nsleep 5`n"
    [IO.File]::WriteAllText((Join-Path $outW '.start.sh'), $st)
    $t0 = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Set-Content $curF @($run, $outW, $t0, $own, (Get-Date -Format s), $name); Set-Content (Join-Path $runs "inflight\runner-$Lane") $outP
    Wsl @('bash', "$outP/.start.sh") | Out-Null
    Log "START $(if ($fill) { 'FILLER ' })$(if ($film) { 'FILM ' })$name -> $outW (launch $launch$(if ($up) { ', reuse' }), gpu free $(GpuFreeMB) MB, ram free $(RamFreeMB) MB)"; Note $own "lane $Lane started $name : out=$outW"
    State "running $name -> $outW (launching instance $Inst)"
    # retitle as soon as instance $Inst has a window (lane 1 filming captures by exact title), up to 4 min
    for ($i = 0; $i -lt 80 -and -not (Test-Path (Join-Path $outW 'DONE')); $i++) { $k = K2Procs | Where-Object { $_.MainWindowHandle -ne 0 }; if ($k) { Retitle; PlaceWin; if ((Ctl2 @('retitle')) -match 'ok') { break } }; Start-Sleep 3 }
}
