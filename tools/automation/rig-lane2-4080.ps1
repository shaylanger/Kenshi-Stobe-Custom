<#
rig-lane2-4080.ps1: lane "4080b" = a second Kenshi on the 4080 (install copy C:\KenshiInst\2, kenshi-instance.ps1) beside
lane 4080's game (instance 1), driven from the 5090 over ssh like lane 4080 (agent multi-instance-4080, 2026-10-11). Same
rules as lane 5090b (rig-lane2.ps1), only the transport differs. Started and controlled through rig-runner.ps1 (-Rig 4080b;
-Ensure / -Start / -Stop / -Status / -Restart include it), never run by hand except -SelfTest.

Queue: C:\KenshiTestRuns\queue\4080b\*.list first (FIFO by numeric prefix); own folder empty and instance 2 admitted = the
  first lane-eligible list from queue\4080, then queue\any (moved into queue\4080b first: one rename, lane 4080 can't take it
  at the same time). Eligible (LaneReject):
  - "# gfx: low" (no filming: lane 4080 films its 1600x900 window with gdigrab on the 4080's only screen), no Stobe rows
    (no Stobe on the 4080), not "# rig: 5090";
  - crossbow guard (NO PC CRASHES, 2026-10-11 BSOD: every TDR was on a crossbow shot/reload frame): no row names a
    crossbow/ranged/turret/reload script or switch (fp-xbow*, crossbow, ranged, turret, reload, bolt, VMQUICK, XB*/T6 rows);
  - list-rigcheck.sh --fix <list> 4080 OK, dryrun.sh --rig 4080 PASS (run here, at nice 0).
  Lists that break a rule go to queue\failed\ (+ .result naming the rule); the owner gets a note.
  Own folder and queue\4080/any have no gfx-low list -> FILLER: the first queue\filler list (gfx low, same rules) with rows
  changed since their last PASS (rig-runner.ps1 -Rig 4080 -FillerRows: lane 4080's ledger), not benched, not running on any
  lane: claimed as running\4080b__filler__<name> (CreateNew, one lane wins), only the changed rows run; at DONE the 4080 out
  dir's rows.tsv goes into the ledger (rig-runner.ps1 -Rig 4080 -LedgerFrom).
  FILM MODE (Shay 15:20: when the low work runs out the extra lane films; a filming list comes before filler): no gfx-low list for $FilmAfterMin min and
  lane 4080 busy with a batch -> the first filming list (no "# gfx: low"; every other rule above still holds) from queue\4080
  then queue\any. Instance 2 then runs full gfx at the default 1600x900, 60 fps cap, window ON the screen at 0,0 (inst-window
  .pos file; not topmost: takes record with WGC = capture.default on the 4080, which films covered windows). The lane's
  first filming list (until runner\4080b.capproof says PASS) starts with a CAPPROOF row (capture-proof.sh on instance 2's
  window); CAPPROOF FAIL -> PREEMPT, the list goes back to queue\4080, runner\4080b.capproof FAIL = no film mode until
  deleted (note to coordinator). A gfx change between lists = instance 2 restarted. Runner\4080b.gfx = mode of instance 2.
Dry run: through rig-runner.ps1 -Rig 4080 -PreDryOf (lane 4080's pre-dry-run cache: a list lane 4080 already pre-dried
  starts at once); while a batch runs, the head of queue\4080b is pre-dried in the background (nice 15).
Admission (before every launch of instance 2): 4080 GPU memory free >= 4 GB (nvidia-smi over ssh), RAM free >= 6 GB, no
  ALERT-4080-tdr.txt / ALERT-4080b-tdr.txt, and lane 4080 is not running a crossbow list (a fire/reload row or the header
  "# tdr-isolate: yes", which this lane also never takes; a running lane-4080b batch is ended and requeued, an idle instance 2
  stopped, the moment lane 4080 starts one) (TDR isolation: a TDR during such a
  list must be the crossbow's). Not admitted = the list waits (state "waiting: <why>").
Per list: instance 2 down -> kenshi-instance.ps1 sync -Instance 2 (DLLs/mods/cfgs = instance 1's; all kah-* saves), kcfg.ps1
  test -Instance 2 (window 800x600, gfx low), frame cap 30 (framecap.txt), ctl.ps1 launch -Instance 2 -Save <launch>
  -Owner runner-4080b (lock game-2.lock; ctl.ps1 starts C:\KAH\inst-window.ps1: the window is parked right of the screen
  at 1920,0, never topmost, title "... [i2]" so lane 4080's title capture never grabs it), input isolation on. Instance 2
  up but instance 1's KenshiFP/harness DLLs differ -> stop + sync + launch. Then rig4080/setup.sh syncs the list's scripts
  (files a running 4080 process uses are deferred) and run-batch.sh runs via C:\KAH\itrun.ps1 (desktop session) with
  KAH_INSTANCE=2 KAH_OWNER=runner-4080b KAH_GFX=low; out dir 4080:C:\KenshiTestRuns\<list>-i2-<MMdd-HHmm> with .instance=2
  (rig-runner-probe.sh then sees only instance 2's harness/pids); inflight marker runner-4080b (not 4080-*: lane B must not
  make lane 4080 look busy).
Every tick (30 s) of a batch: TDR guard = 4080 System-log nvlddmkm/Display 4101|153 since the batch started, or
  ALERT-4080-tdr.txt from lane 4080 -> PREEMPT TDR, instance 2 stopped, ALERT-4080b-tdr.txt, 4080b.stopped, loop exits.
  rig-runner-probe.sh: batch process gone without DONE, or no new file for StallMin (a row's STALL_MIN wins) -> end-batch +
  instance 2 stopped. DONE -> SUMMARY.txt copied to queue\done\<list>.SUMMARY.txt + .result. Queue empty 5 min -> instance 2
  stopped (frees ~3.5 GB RAM / 2 GB VRAM on the 4080).
Files: runner\4080b.{pid,log,state,cur,stopped,restart}; ALERT-4080b-tdr.txt.
  rig-lane2-4080.ps1 -SelfTest   eligibility + admission + TDR filter on fixed cases (no side effects, no ssh)
#>
param([switch]$SelfTest, [switch]$Fake, [int]$TickSec = 30, [int]$MinGpuMB = 4096, [int]$MinRamMB = 6144, [int]$StallMin = 20, [int]$IdleStopMin = 5,
      [string]$VideoMode = '1024 x 768', [int]$Fps = 30, [int]$FilmAfterMin = 2)   # 1024x768: 800x600 rendered 4096x2160 on lane 5090b (m102)
$Lane = '4080b'; $Inst = 2
$runs = 'C:\KenshiTestRuns'; $auto = 'C:\KenshiModding\tools\automation'

# ---------------------------------------------------------------- pure rules (-SelfTest)
function LaneRows([string[]]$lines) { @($lines | Where-Object { $_ -notmatch '^\s*(#|$)' }) }
$XbowRx = '(?i)(xbow|crossbow|ranged|turret|reload|\bbolt|vmquick|fp-e6-xbow)'
function XbowRow([string]$r) {   # $null or the crossbow word a row names (the melee fixture save + *noxbow* guards are not crossbow work)
    $f = @($r -split '\|'); $id = $f[0].Trim()
    $c = $f[-1] -replace '(?i)kah-fpxbow', 'kah-SAVE' -replace '(?i)\w*noxbow\w*', 'GUARD'
    if ($c -match $XbowRx) { return $Matches[1] }; if ($id -match '^(?i)(XB|T6|VMQ)') { return $id }; $null
}
function LaneGfx([string[]]$lines) { $g = @($lines | Where-Object { $_ -match '^\s*#\s*gfx:\s*(\S+)' } | ForEach-Object { $Matches[1].ToLower() } | Select-Object -First 1); if ($g -and $g[0] -eq 'low') { 'low' } else { 'full' } }
function LaneReject([string[]]$lines, [bool]$film = $false) {   # $null = the lane may run this list, else why not ($film: film mode)
    if (-not $film -and (LaneGfx $lines) -ne 'low') { return 'not "# gfx: low" (filming/full-gfx lists stay on lane 4080)' }
    if ($lines -match '^\s*#\s*rig:\s*5090') { return '"# rig: 5090"' }
    if ((IsoHeader $lines) -and -not (XbPar)) { return '"# tdr-isolate: yes" (crossbow/turret TDR isolation: lane 4080 only)' }
    $rows = LaneRows $lines
    if (-not $rows.Count) { return 'no rows' }
    foreach ($r in $rows) {
        $id = (@($r -split '\|'))[0].Trim()
        if ((@($r -split '\|'))[-1] -match 'STOBE-|tests/ingame/stobe|\.txt(\s|$)') { return "Stobe row $id (no Stobe on the 4080)" }
        $x = XbowRow $r; if ($x -and -not (XbPar)) { return "crossbow guard: row $id names crossbow/ranged/turret work ($x)" }
    }
    $null
}
$FireRx = '(?i)(fire|reload|shoot|shot|tdr|rangedtest|vmquick|xbr-|fp-e6-xbow|turret-take)'
function FireRow([string]$r) {
    $f = @($r -split '\|'); $id = $f[0].Trim()
    $c = $f[-1] -replace '(?i)kah-fpxbow', 'kah-SAVE' -replace '(?i)\w*no-?(xbow|fire|shot|reload)\w*', 'GUARD'
    if ($c -match $FireRx) { return $Matches[1] }; if ($id -match '^(?i)(XB|T6|VMQ)') { return $id }; $null
}
# "# tdr-isolate: yes" (xbow-escalate 2026-10-11): a list whose rows fire/reload the crossbow or a turret through scripts the
# FireRx words miss (fp-manual-ranged/hits/anatomy, fp-controls K, fp-turret-rows T3): lane 4080 only, lane 4080b holds.
# Crossbow in parallel on both 4080 lanes (Shay 2026-10-11 17:00: "if we crash then we just run one at a time"): while
# C:\KenshiTestRuns\runner\4080b.xbow-parallel exists, lane 4080b takes crossbow/tdr-isolate lists and does not hold
# for lane 4080's crossbow list; the TDR guard still stops the lane, and the coordinator deletes the file after a TDR.
$script:XbParTest = $null   # -SelfTest pins the switch ($false/$true) so the real file never changes the cases
function XbPar { if ($null -ne $script:XbParTest) { return $script:XbParTest }; Test-Path -LiteralPath (Join-Path $runs 'runner\4080b.xbow-parallel') }
function IsoHeader([string[]]$lines) { [bool](@($lines | Where-Object { $_ -match '^\s*#\s*tdr-isolate:\s*yes' }).Count) }
function IsoList([string[]]$lines) { if (IsoHeader $lines) { return $true }; foreach ($l in LaneRows $lines) { if (FireRow $l) { return $true } }; $false }
function LaneAdmit([int]$gpuFreeMB, [int]$ramFreeMB, [bool]$tdr, [bool]$xbow1) {   # $null = may launch instance 2
    if ($tdr) { return 'TDR alert present' }
    if ($xbow1 -and -not (XbPar)) { return 'lane 4080 runs a crossbow list (TDR isolation)' }
    if ($gpuFreeMB -lt $MinGpuMB) { return "4080 GPU memory free $gpuFreeMB MB < $MinGpuMB" }
    if ($ramFreeMB -lt $MinRamMB) { return "4080 RAM free $ramFreeMB MB < $MinRamMB" }
    $null
}
# filler skip rule ($q = its filler-rotation.tsv row, $running = names in queue\running): $null = may claim, else why not
function FillerSkip([string]$name, [string[]]$lines, $q, [string[]]$running, [datetime]$now) {
    $w = LaneReject $lines; if ($w) { return $w }
    if ($q -and $q.Count -ge 4 -and $q[3] -and ([datetime]$q[3]) -gt $now) { return "benched until $($q[3])" }
    if (@($running | Where-Object { $_ -like "*__filler__$name" }).Count) { return 'running on another lane/rig' }
    $null
}
# the list a batch runs: CAPPROOF row first (after the header lines) while instance 2's window was never proven
$CapRow = 'CAPPROOF | kah-fpstudio | Axima | Malzin | 300 | bash {CR}/KenshiModding/tools/automation/capture-proof.sh {OUT}/capproof 3'
function RunLines([string[]]$lines, [bool]$proof) { if (-not $proof) { return @($lines) }; @($lines | Where-Object { $_ -match '^\s*(#|$)' }) + @($CapRow) + @(LaneRows $lines) }
function LaneTdrFilter([string[]]$lines, [long]$since) {
    @($lines | Where-Object { $q = "$_" -split '\|', 4; $q.Count -ge 3 -and $q[0] -match '^\d+$' -and [long]$q[0] -ge $since -and $q[2] -in '4101', '153' -and $q[1] -match '^(nvlddmkm|display)$' })
}
if ($SelfTest) {
    $bad = 0; $n = 0; $script:XbParTest = $false
    $low = '# gfx: low'
    $cases = @(
        @('melee gfx low', @($low, 'M | kah-fpxbow | Malzin | Axima | 1200 | DRYRUN_NOREC=1 bash {CR}/x/fp-manual-melee.sh Malzin Skaera {OUT}/M'), ''),
        @('no gfx header', @('M | kah-fpxbow | Malzin | Axima | 1200 | bash x/fp-manual-melee.sh'), 'not "# gfx: low"'),
        @('gfx full', @('# gfx: full', 'M | s | a | b | 1 | bash x/fp-control.sh'), 'not "# gfx: low"'),
        @('rig 5090 pin', @($low, '# rig: 5090', 'M | s | a | b | 1 | bash x/fp-control.sh'), '"# rig: 5090"'),
        @('crossbow script', @($low, 'XC | kah-fpxbow | a | b | 1 | bash x/fp-xbow-tdrconfirm.sh {OUT}/XC'), 'crossbow guard'),
        @('turret row', @($low, 'T1 | s | a | b | 1 | bash x/fp-turret-take.sh'), 'crossbow guard'),
        @('ranged list', @($low, 'R | s | a | b | 1 | bash x/fp-ranged.sh'), 'crossbow guard'),
        @('XB row id', @($low, 'XBRLD | s | a | b | 1 | bash x/fp-thing.sh'), 'crossbow guard'),
        @('stobe row', @($low, 'S1 | s | a | b | 1 | bash {CR}/KenshiModding/tests/ingame/stobe/STOBE-X.sh'), 'Stobe row'),
        @('tdr-isolate list (fp-controls K: no crossbow word in the row)', @($low, '# tdr-isolate: yes', 'K | kah-fpxbow | a | b | 1 | bash x/fp-controls.sh'), '"# tdr-isolate: yes"'),
        @('save name + WS_NOXBOW guard are not crossbow work', @($low, 'W | kah-fpxbow | a | b | 1 | WS_NOXBOW=1 PF_SAVE=kah-fpxbow bash x/fp-weapon-sweep.sh'), '')
    )
    $cases += ,@('film mode takes a filming list', @('# gfx: full', 'F | s | a | b | 1 | bash x/fp-control.sh'), '', $true)
    $cases += ,@('film mode: no gfx header = filming list', @('F | s | a | b | 1 | bash x/fp-fist-take.sh'), '', $true)
    $cases += ,@('film mode: crossbow guard still on', @('# gfx: full', 'F | s | a | b | 1 | bash x/fp-xbow-take.sh'), 'crossbow guard', $true)
    $cases += ,@('film mode: turret take refused', @('T6 | kah-fpturret | a | b | 1 | bash x/fp-turret-take.sh'), 'crossbow guard', $true)
    $cases += ,@('film mode: never a 5090 list', @('# rig: 5090', 'F | s | a | b | 1 | bash x/fp-control.sh'), '"# rig: 5090"', $true)
    $cases += ,@('film mode: never a tdr-isolate list', @('# tdr-isolate: yes', 'K | s | a | b | 1 | bash x/fp-controls.sh'), '"# tdr-isolate: yes"', $true)
    $cases += ,@('film mode: never Stobe', @('S1 | s | a | b | 1 | bash {CR}/KenshiModding/tests/ingame/stobe/STOBE-X.sh'), 'Stobe row', $true)
    foreach ($c in $cases) { $n++; $g = [string](LaneReject $c[1] ([bool]($c.Count -ge 4 -and $c[3]))); $ok = if ($c[2]) { $g -like "$($c[2])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b list $($c[0]): got '$g'" }
    $ad = @(@(9000, 20000, $false, $false, ''), @(3000, 20000, $false, $false, '4080 GPU'), @(9000, 5000, $false, $false, '4080 RAM'), @(9000, 20000, $true, $false, 'TDR'), @(9000, 20000, $false, $true, 'lane 4080 runs a crossbow'))
    foreach ($a in $ad) { $n++; $g = [string](LaneAdmit $a[0] $a[1] $a[2] $a[3]); $ok = if ($a[4]) { $g -like "$($a[4])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b admit gpu=$($a[0]) ram=$($a[1]) tdr=$($a[2]) xbow1=$($a[3]): got '$g'" }
    $fc = @(@('turret nofire row (no shot, no reload)', 'TN | kah-fpturret | a | b | 600 | bash {CR}/x/fp-turret-nofire.sh {OUT}/TN', $false),
            @('melee sweep with WS_NOXBOW on the xbow fixture', 'wm-2hlb | kah-fpxbow | Axima | Malzin | 900 | RIG=4080 WS_NOXBOW=1 PF_SAVE=kah-fpxbow bash {CR}/x/fp-weapon-sweep.sh {OUT}/wm', $false),
            @('crossbow TDR confirm', 'XC | kah-fpxbow | a | b | 900 | bash {CR}/x/fp-xbow-tdrconfirm.sh {OUT}/XC', $true),
            @('turret fire take', 'TT | kah-fpturret | a | b | 900 | bash {CR}/x/fp-turret-take.sh {OUT}/T6', $true),
            @('crossbow reload row', 'R1 | kah-fpxbow | a | b | 900 | bash {CR}/x/fp-xbow-reload.sh {OUT}/R1', $true))
    foreach ($c in $fc) { $n++; $g = [bool](FireRow $c[1]); $ok = $g -eq $c[2]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b TDR isolation $($c[0]): fire=$g" }
    $ic = @(@('tdr-isolate header, no fire word', @('# tdr-isolate: yes', 'K | kah-fpxbow | a | b | 1 | bash x/fp-controls.sh'), $true),
            @('fire row, no header', @('XC | kah-fpxbow | a | b | 1 | bash x/fp-xbow-tdrconfirm.sh'), $true),
            @('melee list', @('# gfx: low', 'M | kah-fpxbow | a | b | 1 | bash x/fp-manual-melee.sh'), $false))
    foreach ($c in $ic) { $n++; $g = [bool](IsoList $c[1]); $ok = $g -eq $c[2]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b isolation list $($c[0]): iso=$g" }
    $n++; $t = @(LaneTdrFilter @('1000|Display|4101|reset', '1100|nvlddmkm|153|err', '1200|disk|153|io', '900|Display|4101|old', 'ssh: connect timed out') 950)
    $ok = ($t | ForEach-Object { ($_ -split '\|')[0] }) -join ',' -eq '1000,1100'; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b TDR filter: $($t -join ' ; ')"
    $fr = @(
        @('gfx-low filler free', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/fp-manual-melee.sh'), $null, @(), ''),
        @('filming filler', 'rg-01.list', @('M | s | a | b | 1 | bash x/fp-control.sh'), $null, @(), 'not "# gfx: low"'),
        @('crossbow filler', 'rg-03.list', @($low, 'R | s | a | b | 1 | bash x/fp-ranged.sh'), $null, @(), 'crossbow guard'),
        @('5090-only filler', 'rg-05.list', @($low, '# rig: 5090', 'M | s | a | b | 1 | bash x/m.sh'), $null, @(), '"# rig: 5090"'),
        @('benched filler', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), @('rg-04.list', 'x', '4080', '2099-01-01T00:00:00', 'dry run FAIL'), @(), 'benched'),
        @('bench expired', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), @('rg-04.list', 'x', '4080', '2000-01-01T00:00:00', 'old'), @(), ''),
        @('lane 4080 runs it', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), $null, @('4080__filler__rg-04.list'), 'running'),
        @('lane 5090b runs it', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), $null, @('5090b__filler__rg-04.list'), 'running'),
        @('other filler running only', 'rg-04.list', @($low, 'M | s | a | b | 1 | bash x/m.sh'), $null, @('4080b__filler__rg-02.list'), '')
    )
    foreach ($c in $fr) { $n++; $g = [string](FillerSkip $c[1] $c[2] $c[3] $c[4] (Get-Date)); $ok = if ($c[5]) { $g -like "$($c[5])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b filler $($c[0]): got '$g'" }
    $n++; $rl = @(RunLines @('# owner: x', '# gfx: full', 'A | s | a | b | 1 | bash x/a.sh', 'B | s | a | b | 1 | bash x/b.sh') $true)
    $ok = $rl.Count -eq 5 -and $rl[2] -eq $CapRow -and $rl[3] -like 'A *' -and $rl[0] -eq '# owner: x'; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b film list: CAPPROOF row after the header, before the rows ($($rl.Count) lines)"
    $n++; $rl = @(RunLines @('# gfx: full', 'A | s | a | b | 1 | bash x/a.sh') $false); $ok = $rl.Count -eq 2 -and -not ($rl -match 'CAPPROOF'); if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b film list after CAPPROOF PASS: no extra row"
    $n++; $tf = Join-Path $env:TEMP "lane4080b-claim-$PID"; Remove-Item $tf -ErrorAction SilentlyContinue; $w = 0
    foreach ($i in 1, 2) { try { $fs = [IO.File]::Open($tf, 'CreateNew', 'Write', 'None'); $fs.Close(); $w++ } catch { } }
    Remove-Item $tf -ErrorAction SilentlyContinue; $ok = $w -eq 1; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b filler claim: two lanes claim one list, $w win(s)"
    $script:XbParTest = $true   # runner\4080b.xbow-parallel present: crossbow / tdr-isolate lists admitted, no hold for lane 4080
    $n++; $g = [string](LaneReject @('# gfx: low', '# tdr-isolate: yes', 'XC | kah-fpxbow | a | b | 1 | bash x/fp-xbow-tdrconfirm.sh {OUT}/XC') $false); $ok = $g -eq ''; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b xbow-parallel: tdr-isolate crossbow list admitted: got '$g'"
    $n++; $g = [string](LaneAdmit 9000 20000 $false $true); $ok = $g -eq ''; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b xbow-parallel: no hold while lane 4080 runs crossbow: got '$g'"
    $script:XbParTest = $false
    # source pin (17:19: the in-batch end-batch check lacked XbPar and killed 114a twice): every isolation `if ((Xbow1)` honours the switch
    $n++; $src = @(Get-Content -LiteralPath $PSCommandPath | Where-Object { $_ -match '^\s*if \(+Xbow1\)' -and $_ -notmatch 'XbPar' }); $ok = $src.Count -eq 0; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b xbow-parallel: every isolation check honours the switch ($($src.Count) without XbPar)"
    "LANE4080B-SELFTEST $(if ($bad) { "FAIL $bad" } else { 'PASS' }) $n cases"; exit [int]($bad -gt 0)
}

# ---------------------------------------------------------------- loop (started by rig-runner.ps1 -Rig 4080b)
$rd = Join-Path $runs 'runner'; $qd = Join-Path $runs 'queue'
foreach ($d in "$qd\$Lane", "$qd\running", "$qd\done", "$qd\failed") { New-Item -ItemType Directory -Force $d | Out-Null }
$log = Join-Path $rd "$Lane.log"; $stateF = Join-Path $rd "$Lane.state"; $curF = Join-Path $rd "$Lane.cur"
$stopF = Join-Path $rd "$Lane.stopped"; $tdrF = Join-Path $runs "ALERT-$Lane-tdr.txt"; $tdr1 = Join-Path $runs 'ALERT-4080-tdr.txt'
$owner = "runner-$Lane"; $K2 = "C:\KenshiInst\$Inst"; $K1 = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi'; $distro = 'DwemerAI4Skyrim3'
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
function Log([string]$m) { Add-Content $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m" -ErrorAction SilentlyContinue }
function State([string]$m) { Set-Content $stateF "$((Get-Date).ToString('HH:mm')) $m" -ErrorAction SilentlyContinue }
function Note([string]$who, [string]$m) { Add-Content (Join-Path $runs "agents\$who.note-from-rig-runner") "$((Get-Date).ToString('MM-dd HH:mm')) rig-runner $Lane`: $m" -ErrorAction SilentlyContinue }
function Wsl([string[]]$a) { & wsl.exe -d $distro -u root --cd / -- @a 2>&1 | ForEach-Object { "$_" } }
function WslPath([string]$w) { '/mnt/' + $w.Substring(0, 1).ToLower() + ($w.Substring(2) -replace '\\', '/') }
function Ssh([string[]]$a) { & ssh.exe -n -o BatchMode=yes -o ConnectTimeout=10 4080 @a 2>&1 | ForEach-Object { "$_" } }
function Ssh4Ps([string]$file, [string[]]$a) { Ssh (@('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file) + $a) }
function Ssh4Enc([string]$ps) { Ssh @('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))) }
function Ssh4Bash([string[]]$a) { Ssh (@('C:\PROGRA~1\Git\bin\bash.exe', '-l') + $a) }
function Scp4([string[]]$src, [string]$dst) { & scp -q -o BatchMode=yes @src "4080:$dst" 2>&1 | ForEach-Object { "$_" }; $LASTEXITCODE -eq 0 }
# one ssh round trip for the lane's view of the 4080: instance 2 up, free GPU/RAM, both installs' DLL hashes
function Remote {
    $ps = @"
`$k = @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { `$_.ExecutablePath -like '$K2\*' }).Count
`$g = try { [int]((& nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | Select-Object -First 1).Trim()) } catch { 0 }
`$r = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
function dh(`$root) { @(Get-ChildItem "`$root\mods" -Recurse -Include 'KenshiFP.dll', 'AutomationHarness.dll' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "`$(`$_.Name)=`$((Get-FileHash `$_.FullName).Hash.Substring(0, 8))" }) -join ','
}
"REMOTE k2=`$k gpu=`$g ram=`$r dll1=`$(dh '$K1') dll2=`$(dh '$K2')"
"@
    $l = @(Ssh4Enc $ps | Where-Object { $_ -like 'REMOTE *' }) | Select-Object -Last 1
    $h = @{ ok = [bool]$l; k2 = 0; gpu = 0; ram = 0; dll1 = ''; dll2 = '' }
    if ($l) { foreach ($kv in ($l.Substring(7) -split ' ')) { $p = $kv -split '=', 2; if ($p.Count -eq 2) { $h[$p[0]] = $p[1] } } }
    $h.k2 = [int]$h.k2; $h.gpu = [int]$h.gpu; $h.ram = [int]$h.ram; $h
}
function Ctl2([string[]]$a) { Ssh4Ps 'C:\KAH\ctl.ps1' (@($a) + @('-Instance', "$Inst", '-Owner', $owner)) }
function Stop2([string]$why) {
    $o = Ctl2 @('stop'); Log "instance 2 stopped ($why): $(($o | Select-Object -Last 1))"
    $left = @(Ssh4Enc "@(Get-CimInstance Win32_Process -Filter `"Name='kenshi_x64.exe'`" | Where-Object { `$_.ExecutablePath -like '$K2\*' } | ForEach-Object { taskkill.exe /F /T /PID `$_.ProcessId 2>&1 })")
    if ($left -match 'SUCCESS') { Log "instance 2 force-killed: $($left -join ' ')" }
}
function TdrEvents([long]$since) {
    $cmd = "`$s=[DateTimeOffset]::FromUnixTimeSeconds($since).LocalDateTime; Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,153; StartTime=`$s} -ErrorAction SilentlyContinue | ForEach-Object { '{0}|{1}|{2}|{3}' -f ([DateTimeOffset]`$_.TimeCreated).ToUnixTimeSeconds(), `$_.ProviderName, `$_.Id, (([string]`$_.Message -replace '\s+',' ') -replace '\|','/') }"
    @(Ssh4Enc $cmd)
}
# TDR isolation (FireRow above; coordinator m102: "turret-nofire" or a WS_NOXBOW melee sweep must not hold the lane)
function Xbow1 {   # lane 4080's running list has a crossbow/turret fire or reload row (TDR isolation)
    foreach ($r in @(Get-ChildItem "$qd\running" -Filter '4080__*' -File -ErrorAction SilentlyContinue)) { if (IsoList @(Get-Content $r.FullName)) { return $true } }
    $false
}
function QSort { @($input) | Sort-Object @{ e = { if ($_.Name -match '^(\d+)') { [long]$matches[1] } else { [long]::MaxValue } } }, @{ e = { -join ($_.Name.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) } } }
function Fail([string]$path, [string]$name, [string]$own, [string]$why) {
    $dst = Join-Path "$qd\failed" $name; Move-Item -LiteralPath $path $dst -Force -ErrorAction SilentlyContinue
    Set-Content "$dst.result" "FAILED $Lane $(Get-Date -Format s) $why"; Log "FAILED $name : $why"
    Note $own "list $name NOT run on lane $Lane ($why); $dst.result."
}
function TdrStop([string]$m, [string]$outN) {
    Set-Content $tdrF @("ALERT $Lane $(Get-Date -Format HH:mm) $m", "Lane $Lane stopped (4080 instance 2). A TDR is a crash warning (2026-10-11 BSOD). Delete only once Shay cleared the cause, then rig-runner.ps1 -Start -Rig $Lane.")
    if ($outN) { $null = Ssh4Enc "Set-Content 'C:\KenshiTestRuns\$outN\PREEMPT' 'TDR'" }
    Stop2 'TDR'; Log "TDR $m"; Note 'coordinator' "$m. Lane $Lane STOPPED, 4080 instance 2 stopped."
    Set-Content $stopF "$(Get-Date -Format s) by TDR guard: $m"; State "STOPPED TDR: $m"; Remove-Item (Join-Path $rd "$Lane.pid"), (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; exit 0
}
function Probe([string]$outP, [string]$act = '', [string]$why = '') {
    $a = @($outP) + $(if ($act) { @($act) } else { @() }) + $(if ($why) { @($why -replace '[^\w.=-]', '_') } else { @() })
    $r = Ssh4Bash (@('/c/KenshiModding/tools/automation/rig-runner-probe.sh') + $a)
    if ($act) { return ($r -join ' ') }
    $l = $r | Where-Object { $_ -like 'PROBE *' } | Select-Object -Last 1
    if (-not $l) { return $null }
    $h = @{}; foreach ($kv in ($l.Substring(6) -split ' ')) { $p = $kv -split '=', 2; if ($p.Count -eq 2) { $h[$p[0]] = $p[1] } }; $h
}
# rig4080/setup.sh for this list: every synced file a running 4080 process names is deferred (never overwrite a script a
# running batch executes, on either lane); lane 4080's runner does the full closure at its own boundaries
function SyncList([string]$listFile) {
    $cl = @(Ssh4Ps 'C:\KAH\runner\procpaths.ps1' @())
    if (-not ($cl -contains 'PROCPATHS-END')) { Log "sync SKIPPED: 4080 process list unreadable; the 4080 keeps its current scripts"; return }
    $all = @(& $gitBash -lc "bash /c/KenshiModding/tools/automation/rig4080/setup.sh --with-list '$((($listFile -replace '\\', '/') -replace '^C:', '/c'))' --list" 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^[\w.-]+/' })
    $cj = $cl -join "`n"
    $defer = @($all | Where-Object { $cj -match [regex]::Escape((Split-Path $_ -Leaf)) })
    $df = Join-Path $rd "$Lane.deferred"; [IO.File]::WriteAllText($df, (($defer -join "`n") + $(if ($defer.Count) { "`n" } else { '' })))
    $so = & $gitBash -lc "bash /c/KenshiModding/tools/automation/rig4080/setup.sh --with-list '$((($listFile -replace '\\', '/') -replace '^C:', '/c'))' --defer /c/KenshiTestRuns/runner/$Lane.deferred" 2>&1 | ForEach-Object { "$_" }
    Log "sync: $(($so | Select-Object -Last 1))$(if ($defer.Count) { " deferred: $($defer -join ',')" })"
}

# steal the first list from queue\4080 then queue\any this lane may run ($film: filming lists, else gfx-low ones)
function StealList([bool]$film) {
    foreach ($src in "$qd\4080", "$qd\any") {
        $c = @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Where-Object { $t = @(Get-Content $_.FullName); -not (LaneReject $t $film) -and ($film -eq ((LaneGfx $t) -ne 'low')) }) | Select-Object -First 1
        if ($c) { try { Move-Item -LiteralPath $c.FullName (Join-Path "$qd\$Lane" $c.Name) -ErrorAction Stop; Log "STEAL $(if ($film) { 'FILM ' })$($c.Name) from $src (own folder empty$(if ($film) { ", no gfx-low work $FilmAfterMin min, lane 4080 busy" }))"; return Get-Item (Join-Path "$qd\$Lane" $c.Name) } catch { } }
    }
    $null
}
# a gfx-low filler list with rows changed since their last PASS (lane 4080's ledger, cached 5 min per list), not benched,
# not running anywhere, not failing its dry run here in the last 3 h: claimed as running\4080b__filler__<name> (CreateNew)
$script:fillCache = @{}; $script:fillBad = @{}
function PickFiller {
    $rot = @{}; foreach ($l in @(Get-Content (Join-Path $rd 'filler-rotation.tsv') -ErrorAction SilentlyContinue)) { $q = @($l -split "`t"); if ($q[0]) { $rot[$q[0]] = $q } }
    foreach ($fl in @(Get-ChildItem "$qd\filler" -Filter *.list -File -ErrorAction SilentlyContinue | QSort)) {
        if ($script:fillBad[$fl.Name] -and ((Get-Date) - $script:fillBad[$fl.Name]).TotalHours -lt 3) { continue }
        $t = @(Get-Content $fl.FullName)
        if (FillerSkip $fl.Name $t $rot[$fl.Name] @(Get-ChildItem "$qd\running" -File -ErrorAction SilentlyContinue | ForEach-Object Name) (Get-Date)) { continue }
        $c = $script:fillCache[$fl.Name]
        if (-not $c -or ((Get-Date) - $c.At).TotalMinutes -ge 5 -or $c.Stamp -ne $fl.LastWriteTimeUtc.Ticks) {
            $o = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig-runner.ps1" -Rig 4080 -FillerRows $fl.FullName 2>&1 | ForEach-Object { "$_" })
            $c = @{ At = Get-Date; Stamp = $fl.LastWriteTimeUtc.Ticks; Build = @($o | Where-Object { $_ -like "#build`t*" -and $_ -notmatch '\?' } | Select-Object -First 1); Rows = @($o | Where-Object { $_ -like "ROW`t*" }) }
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
# dry-run verdict through lane 4080's pre-dry-run cache (rig-runner.ps1 -PreDryOf): @{ V = PASS|FAIL|PENDING|none; Lines }
function PreDry([string]$path, [int]$nice, [int]$wait) {
    $o = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig-runner.ps1" -Rig 4080 -PreDryOf $path -PreDryNice $nice -PreDryWaitSec $wait 2>&1 | ForEach-Object { "$_" })
    $l = @($o | Where-Object { $_ -like 'PREDRY *' } | Select-Object -Last 1); $v = if ($l) { ($l[0] -split ' ')[2] } else { 'none' }
    @{ V = $v; Lines = $o }
}
function Busy1 { [bool]@(Get-ChildItem "$qd\running" -Filter '4080__*' -File -ErrorAction SilentlyContinue).Count }   # lane 4080 has a batch
function Gfx2 { $g = "$((Get-Content (Join-Path $rd "$Lane.gfx") -TotalCount 1 -ErrorAction SilentlyContinue))".Trim(); if ($g) { $g } else { 'low' } }
function CapState { "$((Get-Content (Join-Path $rd "$Lane.capproof") -TotalCount 1 -ErrorAction SilentlyContinue))" }
function SetPos([string]$xy) { $null = Ssh4Enc "Set-Content 'C:\KenshiTestRuns\inst-window-$Inst.pos' '$xy' -Encoding Ascii" }

Log "lane $Lane up pid=$PID"
$idleSince = Get-Date; $noLowSince = $null; $preAt = @{}
while ($true) {
    if (Test-Path $stopF) { Log 'stopped flag: exit'; Remove-Item (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue; exit 0 }
    $cur = if (Test-Path $curF) { @(Get-Content $curF) } else { @() }   # runPath, outN, start epoch, owner, start ISO, list name (rig-runner -Status reads [4] + [5])
    if ($cur.Count -ge 6) {
        $outN = $cur[1]; $t0 = [long]$cur[2]; $own = $cur[3]; $name = $cur[5]; $outP = "/c/KenshiTestRuns/$outN"
        if (Test-Path $tdr1) { TdrStop "lane 4080 TDR alert ($((Get-Content $tdr1 -TotalCount 1)))" $outN }
        $h = @(LaneTdrFilter (TdrEvents ($t0 - 30)) ($t0 - 30)); if ($h.Count) { TdrStop "TDR (GPU driver reset) on the 4080 during lane $Lane list $name : $($h[0])" $outN }
        if ((Xbow1) -and -not (XbPar)) {   # TDR isolation (off while the xbow-parallel switch exists; 17:19 it ended 114a twice beside 116): lane 4080 started a crossbow/turret list -> end this batch now, requeue the list for later
            $o = Probe $outP 'end-batch' "lane $Lane TDR isolation: lane 4080 runs a crossbow/turret list"; Stop2 'TDR isolation'
            $back = Join-Path "$qd\$Lane" $name
            if ((Split-Path $cur[0] -Leaf) -like '*__filler__*') { Remove-Item -LiteralPath $cur[0] -ErrorAction SilentlyContinue; $back = 'filler claim released' } else { Move-Item -LiteralPath $cur[0] $back -Force -ErrorAction SilentlyContinue }
            Remove-Item (Join-Path $rd "$Lane.requeue") -ErrorAction SilentlyContinue
            Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue
            Log "ISOLATION end-batch $name (requeued $back): $o"; Note $own "lane $Lane ended $name (lane 4080 runs a crossbow/turret list, TDR isolation); requeued in queue\$Lane, reruns after it"
            $idleSince = Get-Date; continue
        }
        $p = Probe $outP
        if ($p -and $p.done -eq '1') {
            $tmp = Join-Path $rd "$Lane-$outN"; New-Item -ItemType Directory -Force $tmp | Out-Null
            $null = & scp -q -o BatchMode=yes "4080:C:/KenshiTestRuns/$outN/SUMMARY.txt" (Join-Path $tmp 'SUMMARY.txt') 2>&1
            $sum = Join-Path $tmp 'SUMMARY.txt'; $sl = if (Test-Path $sum) { @(Get-Content $sum) } else { @() }
            $ps = @($sl | Where-Object { $_ -match '^RESULT \S+ PASS' }).Count; $fs = @($sl | Where-Object { $_ -match '^RESULT \S+ FAIL' }).Count
            if ((Split-Path $cur[0] -Leaf) -like '*__filler__*') {   # filler: this run's row results into lane 4080's ledger
                $null = & scp -q -o BatchMode=yes "4080:C:/KenshiTestRuns/$outN/rows.tsv" (Join-Path $tmp 'rows.tsv') 2>&1
                $lg = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig-runner.ps1" -Rig 4080 -LedgerFrom $tmp -LedgerList $name 2>&1 | ForEach-Object { "$_" }); Log "ledger: $($lg | Select-Object -Last 1)"
            }
            $cp = @($sl | Where-Object { $_ -match '^RESULT CAPPROOF (PASS|FAIL)' } | Select-Object -Last 1)
            if ($cp) { $cv = if ($cp[0] -match '^RESULT CAPPROOF FAIL') { 'FAIL' } else { 'PASS' }; Set-Content (Join-Path $rd "$Lane.capproof") "$cv $(Get-Date -Format s) 4080:C:\KenshiTestRuns\$outN"; Log "CAPPROOF $cv"
                if ($cv -eq 'FAIL') { Note 'coordinator' "lane $Lane CAPPROOF FAIL on instance 2's window (4080:C:\KenshiTestRuns\$outN): film mode off for lane $Lane until runner\$Lane.capproof is deleted" } }
            $rq = "$((Get-Content (Join-Path $rd "$Lane.requeue") -TotalCount 1 -ErrorAction SilentlyContinue))".Trim(); Remove-Item (Join-Path $rd "$Lane.requeue") -ErrorAction SilentlyContinue
            $dst = Join-Path "$qd\done" $name
            if ($rq -and (Split-Path $cur[0] -Leaf) -notlike '*__filler__*') { Move-Item -LiteralPath $cur[0] (Join-Path "$qd\$rq" $name) -Force -ErrorAction SilentlyContinue; Log "REQUEUED $name to queue\$rq"; Note $own "lane $Lane gave $name back to queue\$rq (CAPPROOF FAIL on its window; 4080:C:\KenshiTestRuns\$outN)" }
            else { Move-Item -LiteralPath $cur[0] $dst -Force -ErrorAction SilentlyContinue }
            if (Test-Path $sum) { Copy-Item $sum "$dst.SUMMARY.txt" -Force }
            Set-Content "$dst.result" "DONE $Lane start=$([DateTimeOffset]::FromUnixTimeSeconds($t0).LocalDateTime.ToString('s')) end=$(Get-Date -Format s) out=4080:C:\KenshiTestRuns\$outN pass=$ps fail=$fs summary=$dst.SUMMARY.txt"
            Log "DONE $name pass=$ps fail=$fs"; Note $own "lane $Lane finished $name : pass=$ps fail=$fs, $dst.SUMMARY.txt"
            Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            $idleSince = Get-Date; continue
        }
        # film mode, window not proven yet: a CAPPROOF FAIL ends the batch at the next row boundary, the list goes back to queue\4080
        if ((Gfx2) -eq 'full' -and (CapState) -notlike 'PASS*' -and -not (Test-Path (Join-Path $rd "$Lane.requeue"))) {
            $cl = @(Ssh4Enc "Select-String -Path 'C:\KenshiTestRuns\$outN\SUMMARY.txt' -Pattern '^RESULT CAPPROOF (PASS|FAIL)' -ErrorAction SilentlyContinue | Select-Object -Last 1 | ForEach-Object Line") | Where-Object { $_ -like 'RESULT CAPPROOF*' } | Select-Object -Last 1
            if ($cl -like 'RESULT CAPPROOF FAIL*') { $null = Ssh4Enc "Set-Content 'C:\KenshiTestRuns\$outN\PREEMPT' 'CAPPROOF FAIL on lane $Lane'"; Set-Content (Join-Path $rd "$Lane.requeue") '4080'; Log "CAPPROOF FAIL: $name preempted, back to queue\4080 at DONE ($cl)" }
            elseif ($cl -like 'RESULT CAPPROOF PASS*') { Set-Content (Join-Path $rd "$Lane.capproof") "PASS $(Get-Date -Format s) 4080:C:\KenshiTestRuns\$outN"; Log "CAPPROOF PASS: $cl" }
        }
        # pre-dry-run the next own-folder list in the background (nice 15), at most once per list per 5 min
        $nx = Get-ChildItem "$qd\$Lane" -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Select-Object -First 1
        if ($nx -and (-not $preAt[$nx.Name] -or ((Get-Date) - $preAt[$nx.Name]).TotalMinutes -ge 5)) { $preAt[$nx.Name] = Get-Date; $pv = PreDry $nx.FullName 15 0; Log "predry $($nx.Name): $($pv.V)" }
        if ($p) {
            $lim = if ($p.stallmin -match '^\d+$') { [Math]::Max([int]$p.stallmin, $StallMin) } else { $StallMin }
            $why = if ($p.alive -eq '0') { 'batch process gone without DONE' } elseif ($p.age -match '^\d+$' -and [int]$p.age -ge $lim * 60) { "no new output for $([int]([int]$p.age / 60)) min" } else { '' }
            if ($why) { $o = Probe $outP 'end-batch' "lane $Lane stall: $why"; Log "STALL end-batch ($why): $o"; Stop2 'stall' }
            State "running $name -> 4080:C:\KenshiTestRuns\$outN (step=$($p.step) phase=$($p.phase) gh=$($p.gh) age=$($p.age)s$(if ($why) { " STALL: $why" }))"
        } else { State "running $name -> 4080:C:\KenshiTestRuns\$outN (probe: no answer)" }
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
    $tdrOn = (Test-Path $tdr1) -or (Test-Path $tdrF)
    if ($tdrOn) { $rm = Remote; if ($rm.k2) { Stop2 'TDR alert' }; State 'waiting: TDR alert present (no instance 2 launch)'; Start-Sleep $TickSec; continue }
    if ((Xbow1) -and -not (XbPar)) {   # TDR isolation (off while the xbow-parallel switch exists): no instance 2 beside lane 4080's crossbow/turret list (stop an idle one too)
        $rm = Remote; if ($rm.k2) { Stop2 'TDR isolation' }; State 'waiting: lane 4080 runs a crossbow list (TDR isolation)'; Start-Sleep $TickSec; continue
    }
    $f = Get-ChildItem "$qd\$Lane" -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Select-Object -First 1
    $rm = $null; $fill = $null
    if (-not $f) {
        $rm = Remote
        $admit = $rm.ok -and ($rm.k2 -or -not (LaneAdmit $rm.gpu $rm.ram $false (Xbow1)))
        if ($admit) { $f = StealList $false }
        # filming work beats filler (as rig-laneB/C d8be0be): only real gfx-low lists hold film mode off
        if ($f) { $noLowSince = $null } elseif (-not $noLowSince) { $noLowSince = Get-Date }
        if (-not $f -and $admit -and (CapState) -notlike 'FAIL*' -and (Busy1) -and ((Get-Date) - $noLowSince).TotalMinutes -ge $FilmAfterMin) { $f = StealList $true }
        if (-not $f -and $admit) { $fill = PickFiller }
    } else { $noLowSince = $null }
    if (-not $f -and -not $fill) {
        if ($rm -and $rm.k2 -and ((Get-Date) - $idleSince).TotalMinutes -ge $IdleStopMin) { Stop2 "queue empty $IdleStopMin min" }
        State "idle: no work for lane $Lane (own folder, queue\4080/any gfx-low, changed filler; filming after $FilmAfterMin min while lane 4080 is busy$(if ((CapState) -like 'FAIL*') { ': OFF, CAPPROOF FAIL' }))$(if ($rm -and $rm.k2) { ' (instance 2 up)' })$(if ($rm -and -not $rm.ok) { ' (4080 unreachable)' })"; Start-Sleep $TickSec; continue
    }
    if ($fill) { $src = $fill.Run; $name = $fill.Name } else { $src = $f.FullName; $name = $f.Name }
    $txt = @(Get-Content $src)
    $own = @($txt | Where-Object { $_ -match '^\s*#\s*owner:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1); $own = if ($own) { $own[0] } else { 'coordinator' }
    function Drop([string]$why) { if ($fill) { Remove-Item -LiteralPath $src -ErrorAction SilentlyContinue; $script:fillBad[$name] = Get-Date; Log "filler $name dropped: $why" } else { Fail $src $name $own $why } }
    $film = (LaneGfx $txt) -ne 'low'
    if ($film -and -not $fill -and (CapState) -like 'FAIL*') { Move-Item -LiteralPath $src (Join-Path "$qd\4080" $name) -Force -ErrorAction SilentlyContinue; Log "film list $name back to queue\4080 (CAPPROOF FAIL: no film mode)"; continue }
    $why = LaneReject $txt $film; if ($why) { Drop $why; continue }
    if (-not $rm) { $rm = Remote }
    if (-not $rm.ok) { if ($fill) { Remove-Item -LiteralPath $src -ErrorAction SilentlyContinue }; State "waiting: 4080 unreachable ($name queued)"; Start-Sleep $TickSec; continue }
    $up = $rm.k2 -gt 0
    $want = if ($film) { 'full' } else { 'low' }
    if ($up -and (Gfx2) -ne $want) { Stop2 "gfx switch to $want"; $up = $false }
    if (-not $up) { $why = LaneAdmit $rm.gpu $rm.ram $false (Xbow1); if ($why) { if ($fill) { Remove-Item -LiteralPath $src -ErrorAction SilentlyContinue }; State "waiting: $why ($name queued)"; Start-Sleep $TickSec; continue } }
    State "checking $name (list-rigcheck, dry run)"
    $lp = (($src -replace '\\', '/') -replace '^C:', '/c')
    $rc = @(& $gitBash -lc "bash /c/KenshiModding/tools/automation/list-rigcheck.sh --quiet --fix '$lp' 4080" 2>&1 | ForEach-Object { "$_" }) | Select-Object -Last 1
    if ($rc -like 'NO *') { Drop "cannot run on the 4080: $($rc.Substring(3))"; continue }
    # dry run (fake game) through lane 4080's pre-dry-run cache: cached = no wait; else nice 0 now (rows in "# nodryrun:" left out)
    $pv = PreDry $src 0 1200
    $sum = @($pv.Lines | Where-Object { $_ -like 'DRYRUN-SUMMARY*' } | Select-Object -Last 1)
    Log "dryrun $name : $($pv.V) $sum"
    # 17:21 114a: the pre-dry run left no verdict (none) and the list went to failed\ after 4 good dry runs; none/PENDING = retry
    # the next tick (up to 3 times), only PASS starts and only FAIL (or a 4th none) drops it
    if ($pv.V -in @('none', 'PENDING')) { if (-not $script:pdRetry) { $script:pdRetry = @{} }; $script:pdRetry[$name] = 1 + [int]$script:pdRetry[$name]
        if ($script:pdRetry[$name] -le 3) { if ($fill) { Remove-Item -LiteralPath $src -ErrorAction SilentlyContinue }; State "dry run of $name gave no verdict ($($pv.V)), retry $($script:pdRetry[$name])/3"; Start-Sleep $TickSec; continue } }
    if ($pv.V -ne 'PASS') { Drop "dryrun $($pv.V): $sum $(@($pv.Lines | Where-Object { $_ -match '^DRYRUN .* FAIL' } | Select-Object -First 2) -join ' | ')"; continue }
    $launch = @($txt | Where-Object { $_ -match '^\s*#\s*launch:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $launch = if ($launch) { $launch[0] } else { ((LaneRows $txt)[0] -split '\|')[1].Trim() }
    if ($launch -in '-', 'home') { $launch = 'kah-fpxbow' }
    $outN = @($txt | Where-Object { $_ -match '^\s*#\s*out:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $outN = if ($outN) { "$($outN[0])-i2-$(Get-Date -Format MMdd-HHmm)" } else { "$([IO.Path]::GetFileNameWithoutExtension($name))-i2-$(Get-Date -Format MMdd-HHmm)" }
    $outP = "/c/KenshiTestRuns/$outN"
    if ($fill) { $run = $src } else { $run = Join-Path "$qd\running" "${Lane}__$name"; Move-Item -LiteralPath $src $run -Force }
    $src = $run   # Drop / Fail act on the running copy from here on
    $proof = $film -and (CapState) -notlike 'PASS*'
    $saves = if ($proof -and $launch -ne 'kah-fpstudio') { "$launch,kah-fpstudio" } else { $launch }
    $tmp = Join-Path $rd "$Lane-$outN"; New-Item -ItemType Directory -Force $tmp | Out-Null
    [IO.File]::WriteAllLines((Join-Path $tmp 'list.src.list'), [string[]](RunLines @(Get-Content $run) $proof))   # {CR} form: SyncList + list.txt
    if ($fill) { Set-Content (Join-Path $tmp 'rowmeta.tsv') $fill.Meta }
    Set-Content (Join-Path $rd "$Lane.gfx") $want; Remove-Item (Join-Path $rd "$Lane.requeue") -ErrorAction SilentlyContinue
    if ($proof) { Log "film: CAPPROOF row first (instance 2's window never proven)" }
    $t0 = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Set-Content $curF @($run, $outN, $t0, $own, (Get-Date -Format s), $name); Set-Content (Join-Path $runs "inflight\runner-$Lane") "4080:C:\KenshiTestRuns\$outN"
    State "starting $name -> 4080:C:\KenshiTestRuns\$outN"
    if ($up -and $rm.dll1 -ne $rm.dll2) { Log "instance 1 has other DLLs ($($rm.dll1)) than instance 2 ($($rm.dll2)): stop + sync"; Stop2 'DLL sync'; $up = $false }
    State "starting $name : script sync, instance 2 $(if ($up) { 'reuse' } else { 'sync + launch' })"
    SyncList (Join-Path $tmp 'list.src.list')
    # window: on the screen at 0,0 while filming (WGC films it; not topmost), parked right of the screen for gfx-low work
    SetPos $(if ($film) { '0,0' } else { '1920,0' })
    if (-not $up) {
        $sy = @(Ssh4Ps 'C:\KAH\kenshi-instance.ps1' @('sync', '-Instance', "$Inst", '-Saves', $saves))
        Log "instance sync: $(@($sy | Where-Object { $_ -like 'sync instance*' }) -join ' ')"
        if (-not ($sy -match '^sync instance')) { Drop "instance 2 sync failed: $(($sy | Select-Object -Last 2) -join ' / ')"; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
        $o = if ($film) { Ssh4Enc "Remove-Item env:KAH_VIDEO_MODE -ErrorAction SilentlyContinue; & C:\KAH\kcfg.ps1 test -Instance $Inst -Gfx full" } else { Ssh4Enc "`$env:KAH_VIDEO_MODE='$VideoMode'; & C:\KAH\kcfg.ps1 test -Instance $Inst -Gfx low" }
        Log "kcfg ($want): $($o -join ' / ')"
        $null = Ssh4Enc "Set-Content '$K2\mods\AutomationHarness\framecap.txt' '$(if ($film) { 60 } else { $Fps })' -Encoding Ascii"
        $o = Ctl2 @('launch', '-Save', $launch); Log "launch $launch : $(($o | Select-Object -Last 3) -join ' / ')"
        if (-not ($o -match 'autoload')) { Drop "instance 2 launch failed: $(($o | Select-Object -Last 2) -join ' / ')"; Stop2 'launch failed'; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
    } else {
        $sy = @(Ssh4Ps 'C:\KAH\kenshi-instance.ps1' @('save', $saves, '-Instance', "$Inst")); Log "save copy: $(($sy | Select-Object -Last 1))"
    }
    $o = Ssh4Bash @('-c', "'grep -q KAH_DIR:- /c/KAH/bin/stobe-auto && echo SHIM-OK'")
    if (-not ($o -match 'SHIM-OK')) { Drop "C:\KAH\bin\stobe-auto ignores KAH_DIR (would drive lane 4080's game): run rig4080/setup.sh"; Stop2 'shim'; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
    $o = Ssh4Bash @('-c', "'export KAH_INSTANCE=$Inst; . /c/KenshiModding/tools/automation/rig-env.sh; /c/KAH/bin/stobe-auto input_isolation on'"); Log "isolation: $($o -join ' ')"
    [IO.File]::WriteAllText((Join-Path $tmp 'list.txt'), ((((Get-Content (Join-Path $tmp 'list.src.list')) -replace '\{CR\}', '/c' -replace '\{RIG\}', '4080') -join "`n") + "`n"))
    Set-Content (Join-Path $tmp '.instance') "$Inst" -Encoding Ascii
    Copy-Item "$auto\run-batch.sh" (Join-Path $tmp '.run-batch.sh') -Force
    $rl = if ($up) { "--launch $launch --reuse " } else { '' }
    $ev = if ($film) { 'KAH_GFX=full' } else { "KAH_GFX=low KAH_VIDEO_MODE='$VideoMode'" }
    [IO.File]::WriteAllText((Join-Path $tmp '.start.sh'), "#!/bin/bash`nexport KAH_OWNER=$owner KAH_INSTANCE=$Inst $ev`nexec bash $outP/.run-batch.sh $rl--no-dryrun 'lane $Lane dry-ran the list' $outP/list.txt $outP`n")
    $null = Ssh @('mkdir', "C:\KenshiTestRuns\$outN")
    $ok = Scp4 @((Join-Path $tmp 'list.txt'), (Join-Path $tmp '.instance'), (Join-Path $tmp '.run-batch.sh'), (Join-Path $tmp '.start.sh')) "C:/KenshiTestRuns/$outN/"
    if (-not $ok) { Drop '4080 copy (scp) failed'; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
    Get-ChildItem $tmp -File | Where-Object { $_.Name -ne 'rowmeta.tsv' } | Remove-Item -ErrorAction SilentlyContinue   # rowmeta.tsv stays for the ledger at DONE
    $o = Ssh4Ps 'C:\KAH\itrun.ps1' @('-Log', "C:\KenshiTestRuns\$outN.itrun.out", '-Cmd', "$outP/.start.sh")
    Log "START $(if ($fill) { 'FILLER ' })$(if ($film) { 'FILM ' })$name ->4080:C:\KenshiTestRuns\$outN (launch $launch$(if ($up) { ', reuse' }), 4080 gpu free $($rm.gpu) MB, ram free $($rm.ram) MB): $($o -join ' ')"
    Note $own "lane $Lane started $name : out=4080:C:\KenshiTestRuns\$outN"
    State "running $name -> 4080:C:\KenshiTestRuns\$outN"
}
