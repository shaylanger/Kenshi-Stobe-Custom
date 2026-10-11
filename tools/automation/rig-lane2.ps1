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
  - crossbow guard (NO PC CRASHES, 2026-10-11 BSOD: every TDR was on a crossbow shot/reload frame): no row command names
    a crossbow/ranged/turret/reload script or switch (fp-xbow*, crossbow, ranged, turret, reload, XB* rows, VMQUICK).
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
  HWND_NOTOPMOST, never activated, shrunk to the video mode (800x600: Ogre only accepts listed DXGI modes; 640x360 fell back to 4096x2160, m102) if far larger; never on the primary screen (the Samsung).
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
  Queue empty 5 min -> instance n stopped (frees ~4 GB RAM / 2.5 GB VRAM).
Files: runner\<lane>.{pid,log,state,cur,stopped,restart}; ALERT-<lane>-tdr.txt.
  rig-lane2.ps1 -SelfTest   eligibility + admission (GPU/RAM/CPU) + TDR filter + lane table + memory-guard order (no side effects)
#>
param([switch]$SelfTest, [switch]$Fake, [ValidateSet('5090b', '5090c')][string]$Lane = '5090b', [int]$TickSec = 30, [int]$MinGpuMB = 6144,
      [int]$MinRamMB = 7168, [int]$HoldRamMB = 4096, [int]$KillRamMB = 2048, [int]$MaxCpuPct = 85, [int]$Fps = 30,
      [int]$StallMin = 10, [int]$IdleStopMin = 5, [int]$SlotPitch = 0,
      [string]$VideoMode = '800 x 600', [string]$Monitor = 'DISPLAY2')   # extra lanes: small windows side by side on DISPLAY2 (lane A films on DISPLAY1, Shay 14:28/14:31)
# lane table: instance (D:\KenshiInst\<n>), window slot on $Monitor, CPU admission (a third game only while the CPU has room)
$Lanes = [ordered]@{ '5090b' = @{ Inst = 2; Slot = 0; Cpu = $false }; '5090c' = @{ Inst = 3; Slot = 1; Cpu = $true } }
$Inst = $Lanes[$Lane].Inst; $Slot = $Lanes[$Lane].Slot
$runs = 'C:\KenshiTestRuns'; $auto = 'C:\KenshiModding\tools\automation'

# ---------------------------------------------------------------- pure rules (-SelfTest)
function LaneRows([string[]]$lines) { @($lines | Where-Object { $_ -notmatch '^\s*(#|$)' }) }
function LaneReject([string[]]$lines) {   # $null = the lane may run this list, else why not
    $g = @($lines | Where-Object { $_ -match '^\s*#\s*gfx:\s*(\S+)' } | ForEach-Object { $Matches[1].ToLower() } | Select-Object -First 1)
    if (-not $g -or $g[0] -ne 'low') { return 'not "# gfx: low" (filming/full-gfx lists stay on lane 1)' }
    $rows = LaneRows $lines
    if (-not $rows.Count) { return 'no rows' }
    foreach ($r in $rows) {
        $f = @($r -split '\|'); $cmd = $f[-1]; $id = $f[0].Trim()
        if ($cmd -match 'STOBE-|tests/ingame/stobe|\.txt(\s|$)') { return "Stobe row $id (lane 2 has no Stobe server path)" }
        $c = $cmd -replace '(?i)kah-fpxbow', 'kah-SAVE' -replace '(?i)\w*noxbow\w*', 'GUARD'   # the melee fixture's save name and the WS_NOXBOW / pf_noxbow guard are not crossbow work
        if ($c -match '(?i)(xbow|crossbow|ranged|turret|reload|\bbolt|vmquick|fp-e6-xbow)' -or $id -match '^(?i)(XB|T6|VMQ)') { return "crossbow guard: row $id names crossbow/ranged/turret work ($($Matches[1]))" }
    }
    $null
}
function LaneAdmit([int]$gpuFreeMB, [int]$ramFreeMB, [bool]$tdr, [int]$cpuPct = -1) {   # $null = may launch instance n; cpuPct -1 = not checked
    if ($tdr) { return 'TDR alert present' }
    if ($gpuFreeMB -lt $MinGpuMB) { return "GPU memory free $gpuFreeMB MB < $MinGpuMB" }
    if ($ramFreeMB -lt $MinRamMB) { return "RAM free $ramFreeMB MB < $MinRamMB" }
    if ($cpuPct -ge $MaxCpuPct) { return "CPU $cpuPct % >= $MaxCpuPct (1-min average)" }
    $null
}
# memory guard decision for lane $me. $act = @{ lane = @{ Active = bool; Held = bool } } of every lane in $Lanes.
# returns 'hold' | 'release' | 'kill' | '' (nothing). Higher instance gives way first; lower instance resumes first.
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
    $bad = 0; $n = 0
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
        @('save name + WS_NOXBOW guard are not crossbow work', @($low, 'W | kah-fpxbow | a | b | 1 | WS_NOXBOW=1 PF_SAVE=kah-fpxbow bash x/fp-weapon-sweep.sh'), '')
    )
    foreach ($c in $cases) { $n++; $g = [string](LaneReject $c[1]); $ok = if ($c[2]) { $g -like "$($c[2])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane2 list $($c[0]): got '$g'" }
    $ad = @(@(20000, 20000, $false, -1, ''), @(5000, 20000, $false, -1, 'GPU'), @(20000, 6000, $false, -1, 'RAM'), @(20000, 7500, $false, -1, ''), @(20000, 20000, $true, -1, 'TDR'),
            @(20000, 20000, $false, 50, ''), @(20000, 20000, $false, 90, 'CPU'))
    foreach ($a in $ad) { $n++; $g = [string](LaneAdmit $a[0] $a[1] $a[2] $a[3]); $ok = if ($a[4]) { $g -like "$($a[4])*" } else { $g -eq '' }; if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane2 admit gpu=$($a[0]) ram=$($a[1]) tdr=$($a[2]) cpu=$($a[3]): got '$g'" }
    # lane table: instance + slot unique, instances >= 2, 5090b = instance 2 (existing copy), 5090c needs CPU room
    $n++; $ins = @($Lanes.Values | ForEach-Object { $_.Inst }); $sl = @($Lanes.Values | ForEach-Object { $_.Slot })
    $ok = (@($ins | Select-Object -Unique).Count -eq $ins.Count) -and (@($sl | Select-Object -Unique).Count -eq $sl.Count) -and -not @($ins | Where-Object { $_ -lt 2 }).Count -and $Lanes['5090b'].Inst -eq 2 -and $Lanes['5090c'].Inst -eq 3 -and $Lanes['5090c'].Cpu
    if (-not $ok) { $bad++ }; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) lane table: $(($Lanes.Keys | ForEach-Object { "$_=i$($Lanes[$_].Inst)/slot$($Lanes[$_].Slot)" }) -join ' ')"
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
    "LANE2-SELFTEST $(if ($bad) { "FAIL $bad" } else { 'PASS' }) $n cases"; exit [int]($bad -gt 0)
}

# ---------------------------------------------------------------- loop (started by rig-runner.ps1 -Rig 5090b|5090c)
$rd = if ($Fake) { Join-Path $runs 'runner\fake' } else { Join-Path $runs 'runner' }
$qd = if ($Fake) { Join-Path $rd 'queue' } else { Join-Path $runs 'queue' }
foreach ($d in "$qd\$Lane", "$qd\running", "$qd\done", "$qd\failed") { New-Item -ItemType Directory -Force $d | Out-Null }
$log = Join-Path $rd "$Lane.log"; $stateF = Join-Path $rd "$Lane.state"; $curF = Join-Path $rd "$Lane.cur"
$stopF = Join-Path $rd "$Lane.stopped"; $tdrF = Join-Path $runs "ALERT-$Lane-tdr.txt"; $tdr1 = Join-Path $runs 'ALERT-5090-tdr.txt'
$owner = "runner-$Lane"; $K2 = "D:\KenshiInst\$Inst"; $K1 = 'D:\Steam\steamapps\common\Kenshi'; $distro = 'DwemerAI4Skyrim3'
function Log([string]$m) { Add-Content $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m" -ErrorAction SilentlyContinue }
function State([string]$m) { Set-Content $stateF "$((Get-Date).ToString('HH:mm')) $m" -ErrorAction SilentlyContinue }
function Note([string]$who, [string]$m) { Add-Content (Join-Path $runs "agents\$who.note-from-rig-runner") "$((Get-Date).ToString('MM-dd HH:mm')) rig-runner $Lane`: $m" -ErrorAction SilentlyContinue }
function Wsl([string[]]$a) { & wsl.exe -d $distro -u root --cd / -- @a 2>&1 | ForEach-Object { "$_" } }
function WslPath([string]$w) { '/mnt/' + $w.Substring(0, 1).ToLower() + ($w.Substring(2) -replace '\\', '/') }
function K2Procs { @(Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$K2\*" }) }
function Ctl2([string[]]$a) {   # workspace kenshi-ctl.ps1 on instance $Inst as runner-<lane>
    $env:KAH_INSTANCE = "$Inst"; $env:KAH_OWNER = $owner; $env:KAH_GFX = 'low'; $env:KAH_VIDEO_MODE = $VideoMode; $env:KENSHI_MONITOR = $Monitor; $env:KAH_FPS = "$Fps"
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
function CapFps { if ($Fps -gt 0) { $cf = "$K2\mods\AutomationHarness\framecap.txt"; if ((Test-Path (Split-Path $cf)) -and "$((Get-Content $cf -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -ne "$Fps") { Set-Content $cf "$Fps" -Encoding Ascii; Log "framecap $Fps written ($cf)" } } }
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
  public static string Place(IntPtr h, string dev, int slot, int pitch, int cw, int ch) {
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
      if (w.L == x && w.T == y && !big && !top) return "ok";
      uint fl = 0x10 | 0x200 | (big ? 0u : 0x1u);   // NOACTIVATE | NOOWNERZORDER | (NOSIZE unless shrinking)
      SetWindowPos(h, new IntPtr(-2), x, y, cw + bw, ch + bh, fl);
      return "placed at " + x + "," + y + (big ? " shrunk from client " + (c.R - c.L) + "x" + (c.B - c.T) + " to " + cw + "x" + ch : "") + (top ? " (was topmost)" : "");
    } finally { if (old != IntPtr.Zero) SetThreadDpiAwarenessContext(old); }
  }
}
'@
}
function PlaceWin {
    $k = K2Procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1; if (-not $k) { return }
    $vm = [regex]::Match($VideoMode, '(\d+)\s*x\s*(\d+)'); if (-not $vm.Success) { return }
    $r = [LaneWin]::Place($k.MainWindowHandle, $Monitor, $Slot, $SlotPitch, [int]$vm.Groups[1].Value, [int]$vm.Groups[2].Value)
    if ($r -ne 'ok' -and $r -ne $script:lastPlace) { Log "window: $r" }; $script:lastPlace = $r
}
$script:lastPlace = ''
function TdrEvents([long]$since) {
    $s = [DateTimeOffset]::FromUnixTimeSeconds($since).LocalDateTime
    @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101, 153; StartTime = $s } -ErrorAction SilentlyContinue | ForEach-Object { '{0}|{1}|{2}|{3}' -f ([DateTimeOffset]$_.TimeCreated).ToUnixTimeSeconds(), $_.ProviderName, $_.Id, (([string]$_.Message -replace '\s+', ' ') -replace '\|', '/') })
}
function DllHash([string]$root) {   # KenshiFP + harness DLLs the game loads (Vortex links resolved by Get-FileHash)
    @(Get-ChildItem "$root\mods" -Recurse -Include 'KenshiFP.dll', 'AutomationHarness.dll' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash $_.FullName).Hash.Substring(0, 8))" }) -join ' '
}
function QSort { @($input) | Sort-Object @{ e = { if ($_.Name -match '^(\d+)') { [long]$matches[1] } else { [long]::MaxValue } } }, @{ e = { -join ($_.Name.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) } } }
function Fail([string]$path, [string]$name, [string]$own, [string]$why) {
    $dst = Join-Path "$qd\failed" $name; Move-Item -LiteralPath $path $dst -Force -ErrorAction SilentlyContinue
    Set-Content "$dst.result" "FAILED $Lane $(Get-Date -Format s) $why"; Log "FAILED $name : $why"
    Note $own "list $name NOT run on lane $Lane ($why); $dst.result."
}
function Retitle { if (K2Procs) { $o = Ctl2 @('retitle'); if ("$o" -match 'set') { Log "$o"; $t = Ctl2 @('ontop', 'off'); Log "lane B window not pinned: $t" } } }   # lane B = non-filming: never topmost
function TdrStop([string]$m, [string]$out) {
    Set-Content $tdrF @("ALERT $Lane $(Get-Date -Format HH:mm) $m", "Lane $Lane stopped (instance $Inst). A TDR is a crash warning (2026-10-11 BSOD). Delete only once Shay cleared the cause, then rig-runner.ps1 -Start -Rig $Lane.")
    if ($out) { Set-Content (Join-Path $out 'PREEMPT') 'TDR' -ErrorAction SilentlyContinue }
    Stop2 'TDR'; Log "TDR $m"; Note 'coordinator' "$m. Lane $Lane STOPPED, instance $Inst stopped."
    Set-Content $stopF "$(Get-Date -Format s) by TDR guard: $m"; State "STOPPED TDR: $m"; Remove-Item (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue; exit 0
}

Log "lane $Lane up pid=$PID"
$idleSince = Get-Date; $stall = $null
while ($true) {
    if (Test-Path $stopF) { Log 'stopped flag: exit'; Remove-Item (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue; exit 0 }
    $cur = if (Test-Path $curF) { @(Get-Content $curF) } else { @() }   # runPath, outW, start epoch, owner, start ISO, list name (rig-runner -Status reads [4] + [5])
    if ($cur.Count -ge 6) {
        $outW = $cur[1]; $t0 = [long]$cur[2]; $own = $cur[3]; $name = $cur[5]
        if (Test-Path $tdr1) { TdrStop "lane A TDR alert ($((Get-Content $tdr1 -TotalCount 1)))" $outW }
        $h = @(LaneTdrFilter (TdrEvents ($t0 - 30)) ($t0 - 30)); if ($h.Count) { TdrStop "TDR (GPU driver reset) during lane $Lane list $name : $($h[0])" $outW }
        Retitle; PlaceWin; CapFps
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
            $dst = Join-Path "$qd\done" $name; Move-Item -LiteralPath $cur[0] $dst -Force -ErrorAction SilentlyContinue
            if (Test-Path $sum) { Copy-Item $sum "$dst.SUMMARY.txt" -Force }
            Set-Content "$dst.result" "DONE $Lane start=$([DateTimeOffset]::FromUnixTimeSeconds($t0).LocalDateTime.ToString('s')) end=$(Get-Date -Format s) out=$outW pass=$p fail=$f summary=$dst.SUMMARY.txt"
            Log "DONE $name pass=$p fail=$f"; Note $own "lane $Lane finished $name : pass=$p fail=$f, $dst.SUMMARY.txt"
            Remove-Item $curF, (Join-Path $runs "inflight\runner-$Lane") -ErrorAction SilentlyContinue; $idleSince = Get-Date; $stall = $null; continue
        }
        $hl = (Wsl @('bash', "$(WslPath $auto)/batch-health.sh", (WslPath $outW)) | Select-Object -Last 1)
        # a batch waiting on HOLD reads "HEALTH OK held" (batch-health.sh): no stall
        if ($hl -match '^HEALTH STALL') { if (-not $stall) { $stall = Get-Date }; if (((Get-Date) - $stall).TotalMinutes -ge $StallMin) {
                $o = Wsl @('bash', "$(WslPath $auto)/rig-runner-probe.sh", (WslPath $outW), 'end-batch', "lane $Lane stall: $hl"); Log "STALL end-batch: $hl / $(($o | Select-Object -Last 1))"; Stop2 'stall'; $stall = $null } }
        else { $stall = $null }
        State "running $name -> $outW ($(if ($stall) { "STALL since $($stall.ToString('HH:mm')): " })$hl)"
        Start-Sleep $TickSec; continue
    }
    if (Test-Path (Join-Path $rd "$Lane.restart")) {   # rig-runner.ps1 -Restart: re-spawn at the list boundary
        Remove-Item (Join-Path $rd "$Lane.restart"), (Join-Path $rd "$Lane.pid") -ErrorAction SilentlyContinue
        Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$auto\rig-runner.ps1", '-Rig', $Lane); Log 'restart: re-spawned'; exit 0
    }
    if ((Test-Path $tdr1) -or (Test-Path $tdrF)) { Stop2 'TDR alert'; State "waiting: TDR alert present (no instance $Inst launch)"; Start-Sleep $TickSec; continue }
    $f = Get-ChildItem "$qd\$Lane" -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Select-Object -First 1
    # own folder empty: take the first lane-eligible list (gfx low, crossbow guard, no Stobe, no "# rig: 4080") from queue\5090
    # then queue\any (coordinator 14:35: no lane idles while the other has a backlog), only if instance $Inst may run now; the
    # list is first moved into queue\<lane> (one rename: lane A can't take it at the same time)
    if (-not $f -and ((K2Procs) -or -not (LaneAdmit (GpuFreeMB) (RamFreeMB) ((Test-Path $tdr1) -or (Test-Path $tdrF)) (CpuPct 3)))) {
        foreach ($src in "$qd\5090", "$qd\any") {
            $c = @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | QSort | Where-Object { $t = @(Get-Content $_.FullName); -not (LaneReject $t) -and -not ($t -match '^\s*#\s*rig:\s*4080') }) | Select-Object -First 1
            if ($c) { try { Move-Item -LiteralPath $c.FullName (Join-Path "$qd\$Lane" $c.Name) -ErrorAction Stop; Log "STEAL $($c.Name) from $src (lane $Lane eligible, own folder empty)"; $f = Get-Item (Join-Path "$qd\$Lane" $c.Name); break } catch { } }
        }
    }
    if (-not $f) {
        if ((K2Procs) -and (RamFreeMB) -lt $HoldRamMB) { Stop2 "idle and RAM free $(RamFreeMB) MB < $HoldRamMB" }
        if ((K2Procs) -and ((Get-Date) - $idleSince).TotalMinutes -ge $IdleStopMin) { Stop2 "queue empty $IdleStopMin min" }
        State "idle: queue\$Lane empty$(if (K2Procs) { " (instance $Inst up)" })"; Start-Sleep $TickSec; continue
    }
    $txt = @(Get-Content $f.FullName); $name = $f.Name
    $own = @($txt | Where-Object { $_ -match '^\s*#\s*owner:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1); $own = if ($own) { $own[0] } else { 'coordinator' }
    $why = LaneReject $txt; if ($why) { Fail $f.FullName $name $own $why; continue }
    $up = [bool](K2Procs)
    if (-not $up) { $why = LaneAdmit (GpuFreeMB) (RamFreeMB) ((Test-Path $tdr1) -or (Test-Path $tdrF)) (CpuPct 30); if ($why) { State "waiting: $why ($name queued)"; Start-Sleep $TickSec; continue } }
    $launch = @($txt | Where-Object { $_ -match '^\s*#\s*launch:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $launch = if ($launch) { $launch[0] } else { ((LaneRows $txt)[0] -split '\|')[1].Trim() }
    # every kah-* test save, not only the list's header one (Shay 2026-10-11: all lanes can use all saves at the same time).
    # run-batch's load_target swaps the launch save for the row script's pf_load target and rows name their own saves:
    # m102 96-agree-rec sat on the menu 6 min because instance $Inst had kah-fpxbow but not kah-fpstudio.
    $saves = @(@($launch) + @(Get-ChildItem "$env:LOCALAPPDATA\kenshi\save" -Directory -Filter 'kah-*' | ForEach-Object Name) | Select-Object -Unique)
    if ($up -and (DllHash $K1) -ne (DllHash $K2)) { Log "instance 1 has other DLLs ($(DllHash $K1)) than instance $Inst ($(DllHash $K2)): stop + sync"; Stop2 'DLL sync'; $up = $false }
    if (-not $up) {
        $sy = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-instance.ps1" sync -Instance $Inst -Saves ($saves -join ',') 2>&1 | ForEach-Object { "$_" })
        Log "sync: $(($sy | Select-Object -Last 2) -join ' / ')"
        if (-not ($sy -match "save $launch ->")) { Fail $f.FullName $name $own "instance $Inst sync failed: $(($sy | Select-Object -Last 2) -join ' / ')"; continue }
    } else {
        $sy = @(& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-instance.ps1" save ($saves -join ',') -Instance $Inst 2>&1 | ForEach-Object { "$_" }); Log "save copy: $(($sy | Select-Object -Last 1))"
    }
    $outN = @($txt | Where-Object { $_ -match '^\s*#\s*out:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $outN = if ($outN) { "$($outN[0])-i$Inst" } else { "$($f.BaseName)-i$Inst-$(Get-Date -Format MMdd-HHmm)" }
    $outW = Join-Path $runs $outN; $outP = WslPath $outW; New-Item -ItemType Directory -Force $outW | Out-Null
    $run = Join-Path "$qd\running" "${Lane}__$name"; Move-Item -LiteralPath $f.FullName $run -Force
    Set-Content (Join-Path $outW 'list.txt') ((Get-Content $run) -replace '\{CR\}', '/mnt/c');   # {CR} = /mnt/c (as rig-runner.ps1 does)
    Set-Content (Join-Path $outW '.instance') "$Inst"
    Copy-Item "$auto\run-batch.sh" (Join-Path $outW '.run-batch.sh') -Force
    $rl = if ($up) { '--reuse ' } else { '' }
    $st = "#!/bin/bash`nexport KAH_OWNER=$owner KAH_GFX=low KAH_INSTANCE=$Inst KDIR=/mnt/d/KenshiInst/$Inst KAH_DIR='D:\KenshiInst\$Inst\mods\AutomationHarness' KAH_VIDEO_MODE='$VideoMode' KENSHI_MONITOR=$Monitor KAH_FPS=$Fps WSLENV=KAH_OWNER:KAH_GFX:KAH_INSTANCE:KAH_VIDEO_MODE:KENSHI_MONITOR:KAH_FPS`ncd /`nsetsid nohup bash $outP/.run-batch.sh --launch $launch $rl$outP/list.txt $outP >/dev/null 2>&1 </dev/null &`nsleep 5`n"
    [IO.File]::WriteAllText((Join-Path $outW '.start.sh'), $st)
    $t0 = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Set-Content $curF @($run, $outW, $t0, $own, (Get-Date -Format s), $name); Set-Content (Join-Path $runs "inflight\runner-$Lane") $outP
    Wsl @('bash', "$outP/.start.sh") | Out-Null
    Log "START $name -> $outW (launch $launch$(if ($up) { ', reuse' }), gpu free $(GpuFreeMB) MB, ram free $(RamFreeMB) MB)"; Note $own "lane $Lane started $name : out=$outW"
    State "running $name -> $outW (launching instance $Inst)"
    # retitle as soon as instance $Inst has a window (lane 1 filming captures by exact title), up to 4 min
    for ($i = 0; $i -lt 80 -and -not (Test-Path (Join-Path $outW 'DONE')); $i++) { $k = K2Procs | Where-Object { $_.MainWindowHandle -ne 0 }; if ($k) { Retitle; PlaceWin; if ((Ctl2 @('retitle')) -match 'ok') { break } }; Start-Sleep 3 }
}
