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
Admission (before every launch of instance 2): 4080 GPU memory free >= 4 GB (nvidia-smi over ssh), RAM free >= 6 GB, no
  ALERT-4080-tdr.txt / ALERT-4080b-tdr.txt, and lane 4080 is not running a crossbow list (TDR isolation: a TDR during such a
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
      [string]$VideoMode = '800 x 600', [int]$Fps = 30)
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
function LaneReject([string[]]$lines) {   # $null = the lane may run this list, else why not
    $g = @($lines | Where-Object { $_ -match '^\s*#\s*gfx:\s*(\S+)' } | ForEach-Object { $Matches[1].ToLower() } | Select-Object -First 1)
    if (-not $g -or $g[0] -ne 'low') { return 'not "# gfx: low" (filming/full-gfx lists stay on lane 4080)' }
    if ($lines -match '^\s*#\s*rig:\s*5090') { return '"# rig: 5090"' }
    $rows = LaneRows $lines
    if (-not $rows.Count) { return 'no rows' }
    foreach ($r in $rows) {
        $id = (@($r -split '\|'))[0].Trim()
        if ((@($r -split '\|'))[-1] -match 'STOBE-|tests/ingame/stobe|\.txt(\s|$)') { return "Stobe row $id (no Stobe on the 4080)" }
        $x = XbowRow $r; if ($x) { return "crossbow guard: row $id names crossbow/ranged/turret work ($x)" }
    }
    $null
}
$FireRx = '(?i)(fire|reload|shoot|shot|tdr|rangedtest|vmquick|xbr-|fp-e6-xbow|turret-take)'
function FireRow([string]$r) {
    $f = @($r -split '\|'); $id = $f[0].Trim()
    $c = $f[-1] -replace '(?i)kah-fpxbow', 'kah-SAVE' -replace '(?i)\w*no-?(xbow|fire|shot|reload)\w*', 'GUARD'
    if ($c -match $FireRx) { return $Matches[1] }; if ($id -match '^(?i)(XB|T6|VMQ)') { return $id }; $null
}
function LaneAdmit([int]$gpuFreeMB, [int]$ramFreeMB, [bool]$tdr, [bool]$xbow1) {   # $null = may launch instance 2
    if ($tdr) { return 'TDR alert present' }
    if ($xbow1) { return 'lane 4080 runs a crossbow list (TDR isolation)' }
    if ($gpuFreeMB -lt $MinGpuMB) { return "4080 GPU memory free $gpuFreeMB MB < $MinGpuMB" }
    if ($ramFreeMB -lt $MinRamMB) { return "4080 RAM free $ramFreeMB MB < $MinRamMB" }
    $null
}
function LaneTdrFilter([string[]]$lines, [long]$since) {
    @($lines | Where-Object { $q = "$_" -split '\|', 4; $q.Count -ge 3 -and $q[0] -match '^\d+$' -and [long]$q[0] -ge $since -and $q[2] -in '4101', '153' -and $q[1] -match '^(nvlddmkm|display)$' })
}
if ($SelfTest) {
    $bad = 0; $n = 0
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
        @('save name + WS_NOXBOW guard are not crossbow work', @($low, 'W | kah-fpxbow | a | b | 1 | WS_NOXBOW=1 PF_SAVE=kah-fpxbow bash x/fp-weapon-sweep.sh'), '')
    )
    foreach ($c in $cases) { $n++; $g = [string](LaneReject $c[1]); $ok = if ($c[2]) { $g -like "$($c[2])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b list $($c[0]): got '$g'" }
    $ad = @(@(9000, 20000, $false, $false, ''), @(3000, 20000, $false, $false, '4080 GPU'), @(9000, 5000, $false, $false, '4080 RAM'), @(9000, 20000, $true, $false, 'TDR'), @(9000, 20000, $false, $true, 'lane 4080 runs a crossbow'))
    foreach ($a in $ad) { $n++; $g = [string](LaneAdmit $a[0] $a[1] $a[2] $a[3]); $ok = if ($a[4]) { $g -like "$($a[4])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b admit gpu=$($a[0]) ram=$($a[1]) tdr=$($a[2]) xbow1=$($a[3]): got '$g'" }
    $fc = @(@('turret nofire row (no shot, no reload)', 'TN | kah-fpturret | a | b | 600 | bash {CR}/x/fp-turret-nofire.sh {OUT}/TN', $false),
            @('melee sweep with WS_NOXBOW on the xbow fixture', 'wm-2hlb | kah-fpxbow | Axima | Malzin | 900 | RIG=4080 WS_NOXBOW=1 PF_SAVE=kah-fpxbow bash {CR}/x/fp-weapon-sweep.sh {OUT}/wm', $false),
            @('crossbow TDR confirm', 'XC | kah-fpxbow | a | b | 900 | bash {CR}/x/fp-xbow-tdrconfirm.sh {OUT}/XC', $true),
            @('turret fire take', 'TT | kah-fpturret | a | b | 900 | bash {CR}/x/fp-turret-take.sh {OUT}/T6', $true),
            @('crossbow reload row', 'R1 | kah-fpxbow | a | b | 900 | bash {CR}/x/fp-xbow-reload.sh {OUT}/R1', $true))
    foreach ($c in $fc) { $n++; $g = [bool](FireRow $c[1]); $ok = $g -eq $c[2]; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b TDR isolation $($c[0]): fire=$g" }
    $n++; $t = @(LaneTdrFilter @('1000|Display|4101|reset', '1100|nvlddmkm|153|err', '1200|disk|153|io', '900|Display|4101|old', 'ssh: connect timed out') 950)
    $ok = ($t | ForEach-Object { ($_ -split '\|')[0] }) -join ',' -eq '1000,1100'; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane4080b TDR filter: $($t -join ' ; ')"
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
    foreach ($r in @(Get-ChildItem "$qd\running" -Filter '4080__*' -File -ErrorAction SilentlyContinue)) { foreach ($l in LaneRows @(Get-Content $r.FullName)) { if (FireRow $l) { return $true } } }
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

Log "lane $Lane up pid=$PID"
$idleSince = Get-Date
while ($true) {
    if (Test-Path $stopF) { Log 'stopped flag: exit'; Remove-Item (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue; exit 0 }
    $cur = if (Test-Path $curF) { @(Get-Content $curF) } else { @() }   # runPath, outN, start epoch, owner, start ISO, list name (rig-runner -Status reads [4] + [5])
    if ($cur.Count -ge 6) {
        $outN = $cur[1]; $t0 = [long]$cur[2]; $own = $cur[3]; $name = $cur[5]; $outP = "/c/KenshiTestRuns/$outN"
        if (Test-Path $tdr1) { TdrStop "lane 4080 TDR alert ($((Get-Content $tdr1 -TotalCount 1)))" $outN }
        $h = @(LaneTdrFilter (TdrEvents ($t0 - 30)) ($t0 - 30)); if ($h.Count) { TdrStop "TDR (GPU driver reset) on the 4080 during lane $Lane list $name : $($h[0])" $outN }
        $p = Probe $outP
        if ($p -and $p.done -eq '1') {
            $tmp = Join-Path $rd "$Lane-$outN"; New-Item -ItemType Directory -Force $tmp | Out-Null
            $null = & scp -q -o BatchMode=yes "4080:C:/KenshiTestRuns/$outN/SUMMARY.txt" (Join-Path $tmp 'SUMMARY.txt') 2>&1
            $sum = Join-Path $tmp 'SUMMARY.txt'; $sl = if (Test-Path $sum) { @(Get-Content $sum) } else { @() }
            $ps = @($sl | Where-Object { $_ -match '^RESULT \S+ PASS' }).Count; $fs = @($sl | Where-Object { $_ -match '^RESULT \S+ FAIL' }).Count
            $dst = Join-Path "$qd\done" $name; Move-Item -LiteralPath $cur[0] $dst -Force -ErrorAction SilentlyContinue
            if (Test-Path $sum) { Copy-Item $sum "$dst.SUMMARY.txt" -Force }
            Set-Content "$dst.result" "DONE $Lane start=$([DateTimeOffset]::FromUnixTimeSeconds($t0).LocalDateTime.ToString('s')) end=$(Get-Date -Format s) out=4080:C:\KenshiTestRuns\$outN pass=$ps fail=$fs summary=$dst.SUMMARY.txt"
            Log "DONE $name pass=$ps fail=$fs"; Note $own "lane $Lane finished $name : pass=$ps fail=$fs, $dst.SUMMARY.txt"
            Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            $idleSince = Get-Date; continue
        }
        if ($p) {
            $lim = if ($p.stallmin -match '^\d+$') { [Math]::Max([int]$p.stallmin, $StallMin) } else { $StallMin }
            $why = if ($p.alive -eq '0') { 'batch process gone without DONE' } elseif ($p.age -match '^\d+$' -and [int]$p.age -ge $lim * 60) { "no new output for $([int]([int]$p.age / 60)) min" } else { '' }
            if ($why) { $o = Probe $outP 'end-batch' "lane $Lane stall: $why"; Log "STALL end-batch ($why): $o"; Stop2 'stall' }
            State "running $name -> 4080:C:\KenshiTestRuns\$outN (step=$($p.step) phase=$($p.phase) gh=$($p.gh) age=$($p.age)s$(if ($why) { " STALL: $why" }))"
        } else { State "running $name -> 4080:C:\KenshiTestRuns\$outN (probe: no answer)" }
        Start-Sleep $TickSec; continue
    }
    if (Test-Path (Join-Path $rd "$Lane.restart")) {   # rig-runner.ps1 -Restart: re-spawn at the list boundary
        Remove-Item (Join-Path $rd "$Lane.restart"), (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue
        Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$auto\rig-runner.ps1", '-Rig', $Lane); Log 'restart: re-spawned'; exit 0
    }
    $tdrOn = (Test-Path $tdr1) -or (Test-Path $tdrF)
    if ($tdrOn) { $rm = Remote; if ($rm.k2) { Stop2 'TDR alert' }; State 'waiting: TDR alert present (no instance 2 launch)'; Start-Sleep $TickSec; continue }
    $f = Get-ChildItem "$qd\$Lane" -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Select-Object -First 1
    $rm = $null
    if (-not $f) {
        $rm = Remote
        if ($rm.ok -and ($rm.k2 -or -not (LaneAdmit $rm.gpu $rm.ram $false (Xbow1)))) {
            foreach ($src in "$qd\4080", "$qd\any") {
                $c = @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Where-Object { -not (LaneReject @(Get-Content $_.FullName)) }) | Select-Object -First 1
                if ($c) { try { Move-Item -LiteralPath $c.FullName (Join-Path "$qd\$Lane" $c.Name) -ErrorAction Stop; Log "STEAL $($c.Name) from $src (lane $Lane eligible, own folder empty)"; $f = Get-Item (Join-Path "$qd\$Lane" $c.Name); break } catch { } }
            }
        }
    }
    if (-not $f) {
        if ($rm -and $rm.k2 -and ((Get-Date) - $idleSince).TotalMinutes -ge $IdleStopMin) { Stop2 "queue empty $IdleStopMin min" }
        State "idle: queue\$Lane empty$(if ($rm -and $rm.k2) { ' (instance 2 up)' })$(if ($rm -and -not $rm.ok) { ' (4080 unreachable)' })"; Start-Sleep $TickSec; continue
    }
    $txt = @(Get-Content $f.FullName); $name = $f.Name
    $own = @($txt | Where-Object { $_ -match '^\s*#\s*owner:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1); $own = if ($own) { $own[0] } else { 'coordinator' }
    $why = LaneReject $txt; if ($why) { Fail $f.FullName $name $own $why; continue }
    if (-not $rm) { $rm = Remote }
    if (-not $rm.ok) { State "waiting: 4080 unreachable ($name queued)"; Start-Sleep $TickSec; continue }
    $up = $rm.k2 -gt 0
    if (-not $up) { $why = LaneAdmit $rm.gpu $rm.ram $false (Xbow1); if ($why) { State "waiting: $why ($name queued)"; Start-Sleep $TickSec; continue } }
    State "checking $name (list-rigcheck, dry run)"
    $lp = (($f.FullName -replace '\\', '/') -replace '^C:', '/c')
    $rc = @(& $gitBash -lc "bash /c/KenshiModding/tools/automation/list-rigcheck.sh --quiet --fix '$lp' 4080" 2>&1 | ForEach-Object { "$_" }) | Select-Object -Last 1
    if ($rc -like 'NO *') { Fail $f.FullName $name $own "cannot run on the 4080: $($rc.Substring(3))"; continue }
    # dry run (fake game, seconds) at nice 0, rows named in "# nodryrun: <row> <reason>" left out (as rig-runner.ps1)
    $tmpD = Join-Path $rd "$Lane-dry"; Remove-Item $tmpD -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $tmpD | Out-Null
    $skip = @($txt | Where-Object { $_ -match '^\s*#\s*nodryrun:\s*(\S+)' } | ForEach-Object { $Matches[1] })
    $drl = ($txt -replace '\{CR\}', '/c') | Where-Object { $r = $_; if ($r -match '^\s*(#|$)') { return $true }; -not ($skip -contains (($r -split '\|')[0].Trim())) }
    [IO.File]::WriteAllText((Join-Path $tmpD 'list.dryrun.txt'), (($drl -join "`n") + "`n"))
    $dr = Wsl @('timeout', '1200', 'bash', "$(WslPath $auto)/dryrun.sh", '--rig', '4080', '--out', "$(WslPath $tmpD)/out", "$(WslPath $tmpD)/list.dryrun.txt")
    $sum = ($dr | Where-Object { $_ -like 'DRYRUN-SUMMARY*' } | Select-Object -Last 1)
    Log "dryrun $name : $sum"
    if ($sum -cnotmatch '^DRYRUN-SUMMARY pass=\d+ fail=0 ') { Fail $f.FullName $name $own "dryrun failed: $sum $(@($dr | Where-Object { $_ -match '^DRYRUN .* FAIL' } | Select-Object -First 2) -join ' | ')"; continue }
    Remove-Item $tmpD -Recurse -Force -ErrorAction SilentlyContinue
    $launch = @($txt | Where-Object { $_ -match '^\s*#\s*launch:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $launch = if ($launch) { $launch[0] } else { ((LaneRows $txt)[0] -split '\|')[1].Trim() }
    if ($launch -in '-', 'home') { $launch = 'kah-fpxbow' }
    $outN = @($txt | Where-Object { $_ -match '^\s*#\s*out:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $outN = if ($outN) { "$($outN[0])-i2-$(Get-Date -Format MMdd-HHmm)" } else { "$($f.BaseName)-i2-$(Get-Date -Format MMdd-HHmm)" }
    $outP = "/c/KenshiTestRuns/$outN"
    $run = Join-Path "$qd\running" "${Lane}__$name"; Move-Item -LiteralPath $f.FullName $run -Force
    $t0 = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Set-Content $curF @($run, $outN, $t0, $own, (Get-Date -Format s), $name); Set-Content (Join-Path $runs "inflight\runner-$Lane") "4080:C:\KenshiTestRuns\$outN"
    State "starting $name -> 4080:C:\KenshiTestRuns\$outN"
    if ($up -and $rm.dll1 -ne $rm.dll2) { Log "instance 1 has other DLLs ($($rm.dll1)) than instance 2 ($($rm.dll2)): stop + sync"; Stop2 'DLL sync'; $up = $false }
    State "starting $name : script sync, instance 2 $(if ($up) { 'reuse' } else { 'sync + launch' })"
    SyncList $run
    if (-not $up) {
        $sy = @(Ssh4Ps 'C:\KAH\kenshi-instance.ps1' @('sync', '-Instance', "$Inst", '-Saves', $launch))
        Log "instance sync: $(@($sy | Where-Object { $_ -like 'sync instance*' }) -join ' ')"
        if (-not ($sy -match '^sync instance')) { Fail $run $name $own "instance 2 sync failed: $(($sy | Select-Object -Last 2) -join ' / ')"; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
        $o = Ssh4Enc "`$env:KAH_VIDEO_MODE='$VideoMode'; & C:\KAH\kcfg.ps1 test -Instance $Inst -Gfx low"
        Log "kcfg: $($o -join ' / ')"
        $null = Ssh4Enc "Set-Content '$K2\mods\AutomationHarness\framecap.txt' '$Fps' -Encoding Ascii"
        $o = Ctl2 @('launch', '-Save', $launch); Log "launch $launch : $(($o | Select-Object -Last 3) -join ' / ')"
        if (-not ($o -match 'autoload')) { Fail $run $name $own "instance 2 launch failed: $(($o | Select-Object -Last 2) -join ' / ')"; Stop2 'launch failed'; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
    } else {
        $sy = @(Ssh4Ps 'C:\KAH\kenshi-instance.ps1' @('save', $launch, '-Instance', "$Inst")); Log "save copy: $(($sy | Select-Object -Last 1))"
    }
    $o = Ssh4Bash @('-c', "'grep -q KAH_DIR:- /c/KAH/bin/stobe-auto && echo SHIM-OK'")
    if (-not ($o -match 'SHIM-OK')) { Fail $run $name $own "C:\KAH\bin\stobe-auto ignores KAH_DIR (would drive lane 4080's game): run rig4080/setup.sh"; Stop2 'shim'; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
    $o = Ssh4Bash @('-c', "'export KAH_INSTANCE=$Inst; . /c/KenshiModding/tools/automation/rig-env.sh; /c/KAH/bin/stobe-auto input_isolation on'"); Log "isolation: $($o -join ' ')"
    $tmp = Join-Path $rd "$Lane-$outN"; New-Item -ItemType Directory -Force $tmp | Out-Null
    [IO.File]::WriteAllText((Join-Path $tmp 'list.txt'), ((((Get-Content $run) -replace '\{CR\}', '/c') -join "`n") + "`n"))
    Set-Content (Join-Path $tmp '.instance') "$Inst" -Encoding Ascii
    Copy-Item "$auto\run-batch.sh" (Join-Path $tmp '.run-batch.sh') -Force
    $rl = if ($up) { "--launch $launch --reuse " } else { '' }
    [IO.File]::WriteAllText((Join-Path $tmp '.start.sh'), "#!/bin/bash`nexport KAH_OWNER=$owner KAH_INSTANCE=$Inst KAH_GFX=low KAH_VIDEO_MODE='$VideoMode'`nexec bash $outP/.run-batch.sh $rl--no-dryrun 'lane $Lane dry-ran the list' $outP/list.txt $outP`n")
    $null = Ssh @('mkdir', "C:\KenshiTestRuns\$outN")
    $ok = Scp4 @((Join-Path $tmp 'list.txt'), (Join-Path $tmp '.instance'), (Join-Path $tmp '.run-batch.sh'), (Join-Path $tmp '.start.sh')) "C:/KenshiTestRuns/$outN/"
    if (-not $ok) { Fail $run $name $own '4080 copy (scp) failed'; Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; continue }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $o = Ssh4Ps 'C:\KAH\itrun.ps1' @('-Log', "C:\KenshiTestRuns\$outN.itrun.out", '-Cmd', "$outP/.start.sh")
    Log "START $name -> 4080:C:\KenshiTestRuns\$outN (launch $launch$(if ($up) { ', reuse' }), 4080 gpu free $($rm.gpu) MB, ram free $($rm.ram) MB): $($o -join ' ')"
    Note $own "lane $Lane started $name : out=4080:C:\KenshiTestRuns\$outN"
    State "running $name -> 4080:C:\KenshiTestRuns\$outN"
}
