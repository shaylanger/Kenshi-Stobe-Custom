<#
lane-window.ps1 [-Rig 5090] -Lane i3|i4|i5 -Action show|place|selftest
Window slots for the isolated imm26 lanes, from C:\KenshiTestRuns\lanes\lanes-5090.json (lane.window = {display,x,y,w,h} in physical pixels).
  show     prints each lane's actual outer window rect (DPI-aware, physical pixels), monitor, and whether it overlaps another lane window.
  place    moves the lane's game window (found by its kenshi_x64 pid under the lane dir) to its slot with SetWindowPos
           SWP_NOZORDER|NOACTIVATE|NOSENDCHANGING (never focuses, no input). Refuses a slot that is not wholly inside an allowed display
           (DISPLAY1/DISPLAY2; the Samsung DISPLAY3 is forbidden) or overlaps another lane's actual window.
  selftest synthetic rect checks only.
The render size is set by KAH_VIDEO_MODE at launch (kenshi-gfx.ps1 low); the outer window = client + frame, measure with `show` and put the real w/h in the registry.
#>
param([ValidateSet('3', '4', '5', 'i3', 'i4', 'i5', 'all')][string]$Lane = 'all', [ValidateSet('show', 'place', 'selftest')][string]$Action = 'show')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class LaneWin {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static uint FgPid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; }
  public static List<object[]> Game(uint pid) {
    var l = new List<object[]>();
    EnumWindows((h, p) => { uint w; GetWindowThreadProcessId(h, out w); if (w == pid && IsWindowVisible(h)) {
      var sb = new StringBuilder(64); GetClassName(h, sb, 64); RECT r; GetWindowRect(h, out r);
      if (sb.ToString() == "OgreD3D11Wnd") l.Add(new object[] { h, r.L, r.T, r.R, r.B }); } return true; }, IntPtr.Zero);
    return l;
  }
}
'@
[void][LaneWin]::SetProcessDpiAwarenessContext([IntPtr]-4)
function Overlap($a, $b) { $a.L -lt $b.R -and $a.R -gt $b.L -and $a.T -lt $b.B -and $a.B -gt $b.T }
function Inside($o, $i) { $i.L -ge $o.L -and $i.T -ge $o.T -and $i.R -le $o.R -and $i.B -le $o.B }
function Screens { [Windows.Forms.Screen]::AllScreens | ForEach-Object { [pscustomobject]@{ Name = ($_.DeviceName -replace '^\\\\\.\\', ''); L = $_.Bounds.Left; T = $_.Bounds.Top; R = $_.Bounds.Right; B = $_.Bounds.Bottom } } }
if ($Action -eq 'selftest') {
  $bad = 0
  $a = [pscustomobject]@{ L = 0; T = 0; R = 10; B = 10 }; $b = [pscustomobject]@{ L = 10; T = 0; R = 20; B = 10 }; $c = [pscustomobject]@{ L = 5; T = 5; R = 15; B = 15 }
  if (Overlap $a $b) { $bad++; 'FAIL touching edges must not overlap' }
  if (-not (Overlap $a $c)) { $bad++; 'FAIL overlap missed' }
  if (-not (Inside $b ([pscustomobject]@{ L = 11; T = 1; R = 19; B = 9 }))) { $bad++; 'FAIL inside' }
  if (Inside $a $b) { $bad++; 'FAIL outside' }
  if ($bad) { "SELFTEST FAIL $bad"; exit 1 } else { 'SELFTEST PASS lane-window'; exit 0 }
}
$reg = Get-Content 'C:\KenshiTestRuns\lanes\lanes-5090.json' -Raw | ConvertFrom-Json
$forbid = @($reg.forbidden_displays)
$rows = foreach ($l in $reg.lanes) {
  $dir = $l.dir.TrimEnd('\') + '\'
  $p = Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
  $w = $null; if ($p) { $w = [LaneWin]::Game([uint32]$p.ProcessId) | Select-Object -First 1 }
  [pscustomobject]@{ Lane = $l.id; Pid = $(if ($p) { $p.ProcessId } else { 0 }); Hwnd = $(if ($w) { $w[0] } else { [IntPtr]::Zero }); Rect = $(if ($w) { [pscustomobject]@{ L = $w[1]; T = $w[2]; R = $w[3]; B = $w[4] } } else { $null }); Slot = $l.window }
}
$scr = Screens
function ScreenOf($r) { $scr | Where-Object { Inside $_ $r } | Select-Object -First 1 }
if ($Action -eq 'show') {
  foreach ($r in $rows) {
    if (-not $r.Rect) { "{0} not running (slot {1} {2},{3} {4}x{5})" -f $r.Lane, $r.Slot.display, $r.Slot.x, $r.Slot.y, $r.Slot.w, $r.Slot.h; continue }
    $s = ScreenOf $r.Rect
    $ov = @($rows | Where-Object { $_.Lane -ne $r.Lane -and $_.Rect -and (Overlap $_.Rect $r.Rect) } | ForEach-Object Lane)
    "{0} pid={1} rect={2},{3},{4},{5} ({6}x{7}) screen={8} overlap=[{9}] forbidden={10}" -f $r.Lane, $r.Pid, $r.Rect.L, $r.Rect.T, $r.Rect.R, $r.Rect.B, ($r.Rect.R - $r.Rect.L), ($r.Rect.B - $r.Rect.T), $(if ($s) { $s.Name } else { 'SPANS/NONE' }), ($ov -join ','), $(if ($s -and $forbid -contains $s.Name) { 'YES' } else { 'no' })
  }
  "foreground pid=$([LaneWin]::FgPid()) lanes=" + (($rows | ForEach-Object { "$($_.Lane):$($_.Pid)" }) -join ' ')
  exit 0
}
# place
$want = if ($Lane -eq 'all') { $rows } else { $rows | Where-Object { $_.Lane -eq ($Lane -replace '^(\d)$', 'i$1') } }
foreach ($r in $want) {
  if (-not $r.Rect) { "{0} not running: skipped" -f $r.Lane; continue }
  $sl = $r.Slot; $dest = [pscustomobject]@{ L = [int]$sl.x; T = [int]$sl.y; R = [int]$sl.x + [int]$sl.w; B = [int]$sl.y + [int]$sl.h }
  $s = ScreenOf $dest
  if (-not $s -or ('\\.\' + $s.Name) -ne ('\\.\' + $sl.display) -or $forbid -contains $s.Name) { "REFUSED {0}: slot not wholly inside {1} (or forbidden)" -f $r.Lane, $sl.display; exit 1 }
  $hit = @($rows | Where-Object { $_.Lane -ne $r.Lane -and $_.Rect -and (Overlap $_.Rect $dest) } | ForEach-Object Lane)
  if ($hit.Count) { "REFUSED {0}: slot overlaps running window of {1}" -f $r.Lane, ($hit -join ','); exit 1 }
  $ok = [LaneWin]::SetWindowPos($r.Hwnd, [IntPtr]::Zero, $dest.L, $dest.T, $sl.w, $sl.h, [uint32](0x0004 -bor 0x0010 -bor 0x0400))
  $w = [LaneWin]::Game([uint32]$r.Pid) | Select-Object -First 1
  "{0} placed ok={1} now={2},{3},{4},{5}" -f $r.Lane, $ok, $w[1], $w[2], $w[3], $w[4]
}
