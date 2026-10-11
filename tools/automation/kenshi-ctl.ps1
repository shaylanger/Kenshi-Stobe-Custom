<#
kenshi-ctl.ps1 (workspace): the harness repo's kenshi-ctl.ps1 with this PC's
paths; also archives stobe.log, KenshiFP.log and ProfessionGear.log/affixes
(all reset or rewritten on launch).
Commands: status | launch [-Save x] | stop | restart [-Save x] | health | screenshot [-Save n] | lock | release | idle ["<reason>"|clear]

Game lock (C:\KenshiTestRuns\game.lock): only one session drives Kenshi.
launch/stop/restart take the lock for $env:KAH_OWNER (default 'coordinator')
and refuse if another owner holds it. `release` frees it (owner only),
`lock` shows it. See MASTER_TEST_PLAN.md "How this works".

Background runs (default for launch/restart, Shay 2026-10-07): the game opens on
-Monitor (default $env:KENSHI_MONITOR, else DISPLAY1) without taking the focus
(if it grabs it during the launch, it goes back to the window that had it),
and starts with harness input isolation ON: real keys/mouse ignored, cursor
never clipped, input only via `stobe-auto key_inject|mouse_inject` (kenshi-key.ps1 /
kenshi-click.ps1 switch to those by themselves), game keeps running unfocused.
-Play: a normal launch for Shay (no monitor move, focus allowed, isolation off).
Also: monitors | place [-Monitor x] | window (which monitor, who has the focus) | fit (render at the
kenshi.cfg Video Mode size: checks a harness screenshot, resizes the window; also run after every launch).

Windowed test runs (Shay, 2026-10-08: m72 ran exclusive-fullscreen on DISPLAY2 and
interrupted him): every non -Play launch first sets kenshi.cfg to Full Screen=No,
Video Mode=1600 x 900 (fits DISPLAY2, 1920x1080) and keeps Shay's own values in
C:\KenshiTestRuns\kenshi.cfg.play; -Play (and `cfg play`, also run by gfx-mods.sh on)
writes them back. `cfg status|test|play` shows/applies the two modes.

Graphics + frame cap (Shay 2026-10-10 22:05, kenshi-gfx.ps1): every test launch caps the game at 60 fps (harness
framecap.txt) and applies graphics mode -Gfx full|low (default: $env:KAH_GFX, else C:\KenshiTestRuns\gfx.want line 1,
else full): full = Shay's graphics at 1600x900 (filming lists), low = lowest graphics at 1024x576 ("# gfx: low" lists,
no filming). -Play / cfg play restore Shay's graphics and remove the cap. `gfx [full|low|status]` applies/shows it.
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Save = '',
  [int]$TimeoutSec = 300,
  [string]$Monitor = $(if ($env:KENSHI_MONITOR) { $env:KENSHI_MONITOR } else { 'AUTO' }),
  [switch]$Play,
  [ValidateSet('', 'full', 'low')][string]$Gfx = '',
  [Parameter(Position = 1)][string]$Mode = 'status'
)
$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
$LockFile = 'C:\KenshiTestRuns\game.lock'
$Owner = if ($env:KAH_OWNER) { $env:KAH_OWNER } else { 'coordinator' }
$Cfg = "$Kenshi\kenshi.cfg"
$CfgPlay = 'C:\KenshiTestRuns\kenshi.cfg.play'
$Archive = 'C:\KenshiTestRuns'
# Multi-instance (C:\KenshiTestRuns\multi-instance\PLAN.md): $env:KAH_INSTANCE = n >= 2 drives the install copy
# D:\KenshiInst\<n> (kenshi-instance.ps1 sync) with its own lock game-<n>.lock, cfg play copy and log archive; unset or 1 =
# instance 1 exactly as before. The harness kenshi-ctl.ps1 only sees/stops the game of the -Kenshi it is given.
$Inst = if ($env:KAH_INSTANCE -match '^\d+$') { [int]$env:KAH_INSTANCE } else { 1 }
if ($Inst -ge 2) {
  $Kenshi = "D:\KenshiInst\$Inst"
  if (-not (Test-Path "$Kenshi\instance.txt")) { "instance $Inst not created: kenshi-instance.ps1 sync -Instance $Inst"; exit 1 }
  $LockFile = "C:\KenshiTestRuns\game-$Inst.lock"
  $Cfg = "$Kenshi\kenshi.cfg"; $CfgPlay = "$Kenshi\kenshi.cfg.play"
  $Archive = "C:\KenshiTestRuns\multi-instance\inst$Inst"
  if ($Play) { 'instance copies are for tests only: no -Play'; exit 1 }
}
$KahDir = "$Kenshi\mods\AutomationHarness"
# AUTO = the first monitor that is NOT Shay's primary (2026-10-11: Windows renumbered the screens, DISPLAY2 became the
# primary 2560x1440 and test games landed on Shay's screen, glitching through resize rounds)
if ($Monitor -eq 'AUTO') {
  $ml = @((& 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' monitors -Kenshi $Kenshi) -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $sec = @($ml | Where-Object { $_ -notmatch ' primary' })
  $Monitor = if ($sec.Count) { ($sec[0] -split ' ')[0] } else { ($ml[0] -split ' ')[0] }
}
# VSync=No for tests: a windowed background game presents at refresh/3 with VSync on (22 fps on the 60 Hz DISPLAY2, 45 on a
# 143 Hz one; GPU idle), too slow for the ~40 fps viewmodel passes (vm-sword 2026-10-08). Shay's value goes to the play copy.
$TestCfg = @{ 'Full Screen' = 'No'; 'Video Mode' = '1600 x 900 @ 32-bit colour [0]'; 'VSync' = 'No' }

function Get-CfgValues {
  $v = @{}
  foreach ($line in Get-Content $Cfg) { foreach ($k in $TestCfg.Keys) { if ($line -like "$k=*") { $v[$k] = $line.Substring($k.Length + 1) } } }
  $v
}
function Set-CfgValues([hashtable]$Want) {
  $out = foreach ($line in Get-Content $Cfg) {
    $hit = $null; foreach ($k in $Want.Keys) { if ($line -like "$k=*") { $hit = $k } }
    if ($hit) { "$hit=$($Want[$hit])" } else { $line }
  }
  Set-Content -Path $Cfg -Value $out -Encoding Ascii
}
$GfxPs = Join-Path $PSScriptRoot 'kenshi-gfx.ps1'
function Gfx-Want {
  if ($Gfx) { return $Gfx }
  if ($env:KAH_GFX -in @('full', 'low')) { return $env:KAH_GFX }
  $w = 'C:\KenshiTestRuns\gfx.want'
  if (Test-Path $w) { $v = (Get-Content $w -TotalCount 1).Trim(); if ($v -in @('full', 'low')) { return $v } }
  'full'
}
function Cfg-Status {
  $cur = Get-CfgValues
  $isTest = $true; foreach ($k in $TestCfg.Keys) { if ($cur[$k] -ne $TestCfg[$k]) { $isTest = $false } }
  $saved = if (Test-Path $CfgPlay) { (Get-Content $CfgPlay) -join '; ' } else { 'none' }
  "kenshi.cfg: $(if ($isTest) { 'TEST (windowed)' } else { 'PLAY' }) Full Screen=$($cur['Full Screen']) Video Mode=$($cur['Video Mode']); saved play values: $saved"
}
function Cfg-Test {   # windowed for automated runs; remember Shay's values once (never overwrite them with test values)
  $cur = Get-CfgValues
  $isTest = $true; foreach ($k in $TestCfg.Keys) { if ($cur[$k] -ne $TestCfg[$k]) { $isTest = $false } }
  if ($isTest) { return "kenshi.cfg already windowed for tests" }
  # merge: keys already saved keep Shay's value; a key new to the play copy (e.g. VSync added later) is saved from the current
  # file only while it still differs from the test value (so a test value never replaces a saved play value)
  $saved = @{}; if (Test-Path $CfgPlay) { foreach ($line in Get-Content $CfgPlay) { $i = $line.IndexOf('='); if ($i -gt 0) { $saved[$line.Substring(0, $i)] = $line.Substring($i + 1) } } }
  foreach ($k in $cur.Keys) { if (-not $saved.ContainsKey($k) -and $cur[$k] -ne $TestCfg[$k]) { $saved[$k] = $cur[$k] } }
  Set-Content -Path $CfgPlay -Value @($saved.Keys | ForEach-Object { "$_=$($saved[$_])" }) -Encoding Ascii
  Set-CfgValues $TestCfg
  "kenshi.cfg set to windowed 1600x900 for tests (play values saved: $((Get-Content $CfgPlay) -join '; '))"
}
function Cfg-Play {   # Shay's values back
  & $GfxPs play -Kenshi $Kenshi   # graphics + no frame cap (kenshi-gfx.ps1)
  if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { & $PSCommandPath ontop off | Out-Null }   # test topmost off
  if (-not (Test-Path $CfgPlay)) { return "kenshi.cfg: no saved play values ($CfgPlay), left as is: $(Cfg-Status)" }
  $want = @{}; foreach ($line in Get-Content $CfgPlay) { $i = $line.IndexOf('='); if ($i -gt 0) { $want[$line.Substring(0, $i)] = $line.Substring($i + 1) } }
  Set-CfgValues $want
  "kenshi.cfg restored for play: $(($want.Keys | ForEach-Object { "$_=$($want[$_])" }) -join '; ')"
}

if ($Command -eq 'cfg') {
  switch ($Mode) { 'test' { Cfg-Test } 'play' { Cfg-Play } default { Cfg-Status; & $GfxPs status -Kenshi $Kenshi } }
  exit 0
}

if ($Command -eq 'gfx') {
  if ($Mode -in @('full', 'low')) { & $GfxPs $Mode -Kenshi $Kenshi } else { & $GfxPs status -Kenshi $Kenshi }
  exit $LASTEXITCODE
}
if ($Command -eq 'lock') {
  if (Test-Path $LockFile) { Get-Content $LockFile } else { 'free' }
  exit 0
}
if ($Command -eq 'idle') {
  # Shay 2026-10-08: the 5090 must not sit idle unnoticed. The Stop hook (~/.claude/hooks/kenshi-waker-guard.ps1) blocks a
  # Kenshi session from ending its turn while Kenshi is closed and the lock is free unless this reason is < 60 min old.
  # `idle "<reason>"` records it; `idle` shows it; `idle clear` removes it.
  $f = 'C:\KenshiTestRuns\rig5090.idle'
  if ($Mode -eq 'status' -or -not $Mode) { if (Test-Path $f) { "$((Get-Item $f).LastWriteTime.ToString('HH:mm')) $(Get-Content $f -Raw)".Trim() } else { 'no idle reason recorded' }; exit 0 }
  if ($Mode -eq 'clear') { Remove-Item $f -Force -ErrorAction SilentlyContinue; 'cleared'; exit 0 }
  Set-Content -Path $f -Value "$Owner $(Get-Date -Format 'yyyy-MM-dd HH:mm') $Mode" -Encoding utf8
  "idle reason recorded (60 min): $Mode"; exit 0
}
if ($Command -eq 'idle4080') {
  # Shay 2026-10-10: same as `idle` for the 4080 (the Stop hook blocks while the 4080 is idle with no reason < 60 min).
  $f = 'C:\KenshiTestRuns\rig4080.idle'
  if ($Mode -eq 'status' -or -not $Mode) { if (Test-Path $f) { "$((Get-Item $f).LastWriteTime.ToString('HH:mm')) $(Get-Content $f -Raw)".Trim() } else { 'no 4080 idle reason recorded' }; exit 0 }
  if ($Mode -eq 'clear') { Remove-Item $f -Force -ErrorAction SilentlyContinue; 'cleared'; exit 0 }
  Set-Content -Path $f -Value "$Owner $(Get-Date -Format 'yyyy-MM-dd HH:mm') $Mode" -Encoding utf8
  "4080 idle reason recorded (60 min): $Mode"; exit 0
}
if ($Command -eq 'release') {
  if (Test-Path $LockFile) {
    $held = (Get-Content $LockFile -TotalCount 1).Trim()
    if ($held -ne $Owner) { "lock held by '$held', not '$Owner'"; exit 1 }
    Remove-Item $LockFile -Force
  }
  'released'
  exit 0
}
if ($Command -in @('launch', 'stop', 'restart')) {
  if (Test-Path $LockFile) {
    $held = (Get-Content $LockFile -TotalCount 1).Trim()
    if ($held -ne $Owner) { "Kenshi is locked by '$held' (set KAH_OWNER or ask that session to release)"; exit 1 }
  } else {
    Set-Content -Path $LockFile -Value @($Owner, (Get-Date -Format s)) -Encoding utf8
  }
}

# Render size (2026-10-09: on the 5090 the windowed game rendered at 958x510 although kenshi.cfg says 1600x900: the
# window lands on DISPLAY2 at 150% while the primary runs 250%, Windows rescales the window of the DPI-aware game and
# Ogre resizes its back buffer to the new client; screenshots/sheets were tiny). Measure what the game renders (harness
# screenshot size) and resize the window, without moving or activating it, until the back buffer is the Video Mode size.
function Fit-RenderSize {
  if (-not ('KenshiFit' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KenshiFit {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  // window and client size in physical pixels; scale the client by (sx, sy) when sx > 0 (SWP_NOMOVE 0x2|NOZORDER|NOACTIVATE)
  public static string Fit(IntPtr h, double sx, double sy) {
    IntPtr old = IntPtr.Zero; try { old = SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }
    try {
      RECT w, c; GetWindowRect(h, out w); GetClientRect(h, out c);
      int ww = w.R - w.L, wh = w.B - w.T, cw = c.R - c.L, ch = c.B - c.T;
      if (sx > 0) SetWindowPos(h, IntPtr.Zero, 0, 0, ww + (int)Math.Round(cw * (sx - 1)), wh + (int)Math.Round(ch * (sy - 1)), 0x0002 | 0x0004 | 0x0010);
      return "window " + ww + "x" + wh + " client " + cw + "x" + ch;
    } finally { if (old != IntPtr.Zero) SetThreadDpiAwarenessContext(old); }
  }
}
'@
  }
  $vm = (Get-Content $Cfg | Where-Object { $_ -match '^Video Mode=' }) -replace '^Video Mode=\s*', ''
  if ($vm -notmatch '^(\d+)\s*x\s*(\d+)') { "render size: no Video Mode in $Cfg"; return }
  $ww = [int]$Matches[1]; $wh = [int]$Matches[2]
  $p = Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and (-not $_.Path -or $_.Path -like "$Kenshi\*") } | Select-Object -First 1
  if (-not $p) { 'render size: no game window'; return }
  foreach ($i in 1..3) {
    $kahWsl = '/mnt/' + $KahDir.Substring(0,1).ToLower() + ($KahDir.Substring(2) -replace '\\','/')
    $r = wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- env "KAH_DIR=$kahWsl" stobe-auto screenshot kctl-size 2>&1 | Out-String
    $m = [regex]::Match($r, '\((\d+)x(\d+)\)')
    if (-not $m.Success) { "render size: no screenshot ($($r.Trim()))"; return }
    $sw = [int]$m.Groups[1].Value; $sh = [int]$m.Groups[2].Value
    if ($sw -eq $ww -and $sh -eq $wh) { "render size: ${sw}x${sh} ok ($([KenshiFit]::Fit($p.MainWindowHandle, 0, 0)))"; return }
    $before = [KenshiFit]::Fit($p.MainWindowHandle, $ww / $sw, $wh / $sh)
    "render size: ${sw}x${sh}, want ${ww}x${wh}: resized ($before)"
    Start-Sleep -Seconds 2
  }
  "render size: STILL WRONG after 3 resizes"
}
# retitle (multi-instance lane 5090b, 2026-10-11): instance n >= 2 gets the window title "<title> [i<n>]" so a filming row
# on instance 1 (ffmpeg gdigrab title=..., exact match) never captures instance 2's window. Instance 1: no-op.
function Set-InstTitle {
  if ($Inst -lt 2) { return 'retitle: instance 1 (no-op)' }
  if (-not ('KenshiTitle' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class KenshiTitle {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowTextW(IntPtr h, string t);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder b, int n);
  public static string Get(IntPtr h) { var b = new StringBuilder(256); GetWindowTextW(h, b, 256); return b.ToString(); }
}
'@
  }
  $p = Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Path -like "$Kenshi\*" } | Select-Object -First 1
  if (-not $p) { return 'retitle: no game window' }
  $t = [KenshiTitle]::Get($p.MainWindowHandle); $tag = " [i$Inst]"
  if ($t.EndsWith($tag)) { return "retitle: ok '$t'" }
  $null = [KenshiTitle]::SetWindowTextW($p.MainWindowHandle, $t + $tag); "retitle: set '$([KenshiTitle]::Get($p.MainWindowHandle))'"
}
# ontop [on|off|check] (capture-fix 2026-10-11: 5090 takes failed pf_open "openground open=0.00": ffmpeg gdigrab grabs the
# SCREEN area of the background game window, so any window of Shay's covering it was filmed). on = HWND_TOPMOST with
# SWP_NOACTIVATE|NOMOVE|NOSIZE (never focuses it, never takes input); off = HWND_NOTOPMOST (-Play / cfg play / gfx-mods on);
# check = WindowFromPoint at 9 points inside the client rect must all be the game window, else exit 1 with
# "occluded by <process> '<title>' at x,y". on also runs check. Window capture (KAH_CAPTURE=wgc) does not need any of this.
function Set-OnTop([string]$what) {
  if (-not ('KenshiTop' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class KenshiTop {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder b, int n);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  public static bool Set(IntPtr h, bool top) {   // SWP_NOSIZE 1 | NOMOVE 2 | NOACTIVATE 0x10 | NOOWNERZORDER 0x200
    return SetWindowPos(h, new IntPtr(top ? -1 : -2), 0, 0, 0, 0, 0x1 | 0x2 | 0x10 | 0x200);
  }
  public static bool IsTop(IntPtr h) { return (GetWindowLong(h, -20) & 0x8) != 0; }   // WS_EX_TOPMOST
  // "" = unoccluded, else "<pid> '<title>' at x,y" of the first covering top-level window
  public static string Check(IntPtr h) {
    IntPtr old = IntPtr.Zero; try { old = SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }
    try {
      if (IsIconic(h)) return "0 'minimized' at -";
      RECT c; GetClientRect(h, out c); int w = c.R - c.L, hh = c.B - c.T;
      if (w < 8 || hh < 8) return "0 'empty client rect' at -";
      foreach (double fy in new[] { 0.1, 0.5, 0.9 }) foreach (double fx in new[] { 0.1, 0.5, 0.9 }) {
        POINT p = new POINT(); p.X = (int)(w * fx); p.Y = (int)(hh * fy); ClientToScreen(h, ref p);
        IntPtr at = WindowFromPoint(p); IntPtr root = at == IntPtr.Zero ? IntPtr.Zero : GetAncestor(at, 2);
        if (root != h) {
          uint pid = 0; if (root != IntPtr.Zero) GetWindowThreadProcessId(root, out pid);
          var b = new StringBuilder(128); if (root != IntPtr.Zero) GetWindowTextW(root, b, 128);
          return pid + " '" + b + "' at " + p.X + "," + p.Y;
        }
      }
      return "";
    } finally { if (old != IntPtr.Zero) SetThreadDpiAwarenessContext(old); }
  }
}
'@
  }
  $p = Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and (-not $_.Path -or $_.Path -like "$Kenshi\*") } | Select-Object -First 1
  if (-not $p) { 'ontop: no game window'; return 1 }
  $h = $p.MainWindowHandle
  if ($what -eq 'off') { $null = [KenshiTop]::Set($h, $false); "ontop off: topmost=$([KenshiTop]::IsTop($h))"; return 0 }
  if ($what -eq 'on') { $null = [KenshiTop]::Set($h, $true) }
  $o = [KenshiTop]::Check($h); $t = [KenshiTop]::IsTop($h)
  if (-not $o) { "ontop ${what}: topmost=$t unoccluded"; return 0 }
  $opid = [int]($o -split ' ')[0]; $pn = (Get-Process -Id $opid -ErrorAction SilentlyContinue).ProcessName
  "ontop ${what}: topmost=$t occluded by $(if ($pn) { $pn } else { "pid $opid" }) $($o.Substring($o.IndexOf(' ') + 1))"; return 1
}
if ($Command -eq 'ontop') {
  $m = if ($Mode -in @('on', 'off', 'check')) { $Mode } else { 'check' }
  $r = @(Set-OnTop $m); $r[0..($r.Count - 2)]; exit $r[-1]
}
if ($Command -eq 'retitle') { Set-InstTitle; exit 0 }
if ($Command -eq 'fit') { Fit-RenderSize; exit 0 }
# postlaunch (run-batch.sh after it kills the stuck launch proxy, which also killed the re-place/fit below: 2026-10-10
# studio-fixture rendered 798x413 on DISPLAY1): re-place on the test monitor + fit, verify, up to 3 rounds; exit 1 if wrong
if ($Command -eq 'postlaunch') {
  $ctl = 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1'
  $mons = & $ctl monitors -Kenshi $Kenshi
  $want = '\\.\' + ($Monitor -replace '^\\\\\.\\', '').ToUpper()
  if ($mons -notmatch [regex]::Escape($want) + ' ') { $Monitor = ((@($mons -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))[0] -split ' ')[0]; $want = $Monitor }
  if ($Inst -ge 2) { Set-InstTitle }
  foreach ($i in 1..3) {
    $b = & $ctl background -Monitor $Monitor -Kenshi $Kenshi
    $fit = @(Fit-RenderSize) -join ' / '
    $w = (& $ctl window -Kenshi $Kenshi 2>&1 | Out-String).Trim()
    $onMon = $w -match [regex]::Escape(($want -replace '^\\\\\.\\', '')) ; $okSize = $fit -match 'ok \('
    if ($onMon -and $okSize) { "postlaunch ok (round $i): $fit; $w; $(@(Set-OnTop on)[0])"; exit 0 }
    "postlaunch round ${i}: $fit; $w"
    Start-Sleep -Seconds 3
  }
  "postlaunch FAIL: game not at the Video Mode size on $want after 3 rounds"; exit 1
}

$bg = @{}
if (-not $Play) { $bg = @{ Monitor = $Monitor; Background = $true; Isolate = $true } }
if ($Command -in @('launch', 'restart')) {
  if ($Play) { Cfg-Play } else {
    # never open a test game on Shay's screen: refuse when the test monitor is off/disconnected (2026-10-08: DISPLAY1/2
    # vanished from the monitor list mid-session and the windowed game landed on the primary)
    $mons = & 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' monitors -Kenshi $Kenshi
    $want = '\\.\' + ($Monitor -replace '^\\\\\.\\', '').ToUpper()
    $list = @($mons -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($mons -notmatch [regex]::Escape($want) + ' ') {
      # Shay 2026-10-08: windowed + background is what matters, the monitor is a preference: when the preferred one is
      # off use the first one that is on (a single screen: that one)
      $Monitor = ($list[0] -split ' ')[0]; "test monitor $want is off: using $Monitor (windowed, background)"; $bg.Monitor = $Monitor
    }
    Cfg-Test
    if ($Command -eq 'restart') { & 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' stop -Kenshi $Kenshi | Out-Null }
    & $GfxPs (Gfx-Want) -Kenshi $Kenshi
  }
}
& 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' $Command -Save $Save -TimeoutSec $TimeoutSec @bg `
  -Kenshi $Kenshi -ArchiveRoot $Archive `
  -ExtraLogs @("$Kenshi\RE_Kenshi\mods\Stobe\stobe.log", "$Kenshi\KenshiFP.log", "$Kenshi\RE_Kenshi\mods\Stobe\stobe_goals.log",
               "$Kenshi\mods\ProfessionGearProgression\ProfessionGear.log",
               "$Kenshi\mods\ProfessionGearProgression\profession_gear_affixes.tsv")
$rc = $LASTEXITCODE
if ($rc -eq 0 -and -not $Play -and $Command -in @('launch', 'restart')) {
  # Ogre moves/resizes its window again after the launch waits (2026-10-08: ended on DISPLAY1): re-place it without
  # activating, a few times, and report where it is and who has the focus
  $ctl = 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1'
  foreach ($i in 1..3) {
    Start-Sleep -Seconds 3
    $last = & $ctl background -Monitor $Monitor -Kenshi $Kenshi
  }
  "background: $last"
  Fit-RenderSize
  "background after the resize: $(& $ctl background -Monitor $Monitor -Kenshi $Kenshi)"
  @(Set-OnTop on)[0]
}
exit $rc
