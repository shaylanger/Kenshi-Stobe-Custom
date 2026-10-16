<#
lane-window.ps1 [-Rig 5090] -Lane i3|i4|i5 -Action show|place|selftest
Window slots for the isolated imm26 lanes, from C:\KenshiTestRuns\lanes\lanes-5090.json (lane.window = {display,x,y,w,h} in physical pixels).
  show     prints each lane's actual outer window rect (DPI-aware, physical pixels), monitor, and whether it overlaps another lane window.
  place    moves the lane's game window (found by its kenshi_x64 pid under the lane dir) to its slot with SetWindowPos
           SWP_NOZORDER|NOACTIVATE|NOSENDCHANGING (never focuses, no input). Refuses a slot that is not wholly inside an allowed display
           (DISPLAY1/DISPLAY2; the Samsung DISPLAY3 is forbidden). A lane with no free slot is STACKED (cascade >= 40 px, wholly inside the working area)
           and sent to the BOTTOM of the z-order (HWND_BOTTOM + NOACTIVATE, never focused); a non-stacked slot still refuses to overlap a running lane window.
  plan     prints the slots computed from the LIVE monitor layout (registry window x/y/display are only a preference and go stale when
           Windows renumbers/moves monitors; never DISPLAY3 / the Samsung (also by hardware id SAM0B49); lanes only on DISPLAY1/DISPLAY2).
  sync     plan + writes those slots into lanes-5090.json (backup .bak-lanewindow) and deletes the cached C:\KenshiTestRuns\preflight-isolation-5090.txt.
  selftest synthetic layouts (Samsung primary, today's layout, renumbered Samsung, only-forbidden) + rect checks only; no game, no screen reads.
The render size is set by KAH_VIDEO_MODE at launch (kenshi-gfx.ps1 low); the outer window = client + frame, measure with `show` and put the real w/h in the registry.
#>
param([ValidateSet('3', '4', '5', 'i3', 'i4', 'i5', 'all')][string]$Lane = 'all', [ValidateSet('show', 'plan', 'sync', 'place', 'selftest')][string]$Action = 'show')
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
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct DD { public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Str; public int Flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Id; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Key; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevicesW(string dev, int i, ref DD d, int f);
  // ids of the monitors attached to an adapter (\\.\DISPLAYn); Windows keeps inactive ghosts, only flag&1 counts (same as kenshi-ctl.ps1)
  public static string Ids(string adapter) { var r = ""; for (int i = 0; ; i++) { var d = new DD(); d.cb = Marshal.SizeOf(d); if (!EnumDisplayDevicesW(adapter, i, ref d, 1)) break; if ((d.Flags & 1) != 0) r += d.Id + ";"; } return r; }
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
$ForbiddenMonIds = @('SAM0B49')   # Samsung by hardware id, same as kenshi-ctl.ps1: stays forbidden even if Windows renumbers it
# Live layout: Bounds (L,T,R,B), usable WorkingArea (WL..WB, no taskbar), Primary, Forbidden (by name from the registry or by monitor id).
function Screens([string[]]$forbidNames = @()) {
  [Windows.Forms.Screen]::AllScreens | ForEach-Object {
    $n = ($_.DeviceName -replace '^\\\\\.\\', ''); $ids = [LaneWin]::Ids('\\.\' + $n); $fb = $forbidNames -contains $n
    foreach ($f in $ForbiddenMonIds) { if ($ids -match "#$f#") { $fb = $true } }
    $w = $_.WorkingArea
    [pscustomobject]@{ Name = $n; L = $_.Bounds.Left; T = $_.Bounds.Top; R = $_.Bounds.Right; B = $_.Bounds.Bottom; WL = $w.Left; WT = $w.Top; WR = $w.Right; WB = $w.Bottom; Primary = $_.Primary; Forbidden = $fb }
  }
}
# Pure: slots for the lanes from a screen list (Name,WL,WT,WR,WB,Primary,Forbidden). Only DISPLAY1/DISPLAY2 that are not forbidden are allowed
# (never DISPLAY3 / the Samsung, whatever number Windows gives it). $lanes = @{Id;W;H;Display;X;Y} (registry values are only a preference):
# the registry slot is kept when it is still wholly inside the live working area of its display and free; otherwise first-fit (20 px grid,
# 20 px margin) on the preferred display, then the other allowed ones (non-primary first). Returns {Lane;Display;X;Y;W;H;Why}; Display $null = no room.
# When no free non-overlapping slot is left, the lane is STACKED on an allowed display (Why starts with 'stacked': cascade >= 40 px from every lane there,
# wholly inside the working area); only an all-forbidden layout still gives NO-SLOT.
function Plan-Slots($screens, $lanes) {
  $ok = @($screens | Where-Object { -not $_.Forbidden -and $_.Name -match '^DISPLAY[12]$' })
  $placed = @(); $out = @(); $m = 20
  foreach ($ln in $lanes) {
    $w = [int]$ln.W; $h = [int]$ln.H; $got = $null
    $order = @($ok | Where-Object { $_.Name -eq $ln.Display }) + @($ok | Where-Object { $_.Name -ne $ln.Display } | Sort-Object { [int]$_.Primary })
    foreach ($s in $order) {
      $r = [pscustomobject]@{ L = [int]$ln.X; T = [int]$ln.Y; R = [int]$ln.X + $w; B = [int]$ln.Y + $h }
      $wa = [pscustomobject]@{ L = $s.WL; T = $s.WT; R = $s.WR; B = $s.WB }
      if ($s.Name -eq $ln.Display -and (Inside $wa $r) -and -not @($placed | Where-Object { Overlap $_ $r }).Count) { $got = @($s, $r, 'registry slot still valid'); break }
      for ($y = $s.WT + $m; -not $got -and $y + $h -le $s.WB; $y += 20) {
        for ($x = $s.WL + $m; $x + $w -le $s.WR; $x += 20) {
          $r = [pscustomobject]@{ L = $x; T = $y; R = $x + $w; B = $y + $h }
          if (-not @($placed | Where-Object { Overlap $_ $r }).Count) { $got = @($s, $r, 'computed from live layout'); break }
        }
      }
      if ($got) { break }
    }
    if (-not $got) {   # no free slot anywhere: STACK on an allowed display (cascade, >= 40 px from every lane already there, wholly inside the working area); the game window goes to the bottom of the z-order at place time
      foreach ($s in $order) {
        for ($y = $s.WT + $m; -not $got -and $y + $h -le $s.WB; $y += 20) {
          for ($x = $s.WL + $m; $x + $w -le $s.WR; $x += 20) {
            $near = @($placed | Where-Object { $_.Disp -eq $s.Name -and [Math]::Max([Math]::Abs($_.L - $x), [Math]::Abs($_.T - $y)) -lt 40 })
            if (-not $near.Count) { $got = @($s, [pscustomobject]@{ L = $x; T = $y; R = $x + $w; B = $y + $h }, 'stacked (no free slot: cascade, window sent to bottom)'); break }
          }
        }
        if ($got) { break }
      }
    }
    if ($got) { $got[1] | Add-Member -NotePropertyName Disp -NotePropertyValue $got[0].Name; $placed += $got[1]; $out += [pscustomobject]@{ Lane = $ln.Id; Display = $got[0].Name; X = $got[1].L; Y = $got[1].T; W = $w; H = $h; Why = $got[2] } }
    else { $out += [pscustomobject]@{ Lane = $ln.Id; Display = $null; X = 0; Y = 0; W = $w; H = $h; Why = 'NO-SLOT on an allowed display' } }
  }
  $out
}
if ($Action -eq 'selftest') {
  $bad = 0
  function Scr($n, [int]$l, [int]$t, [int]$r, [int]$b, $prim = $false, $fb = $false) { [pscustomobject]@{ Name = $n; L = $l; T = $t; R = $r; B = $b; WL = $l; WT = $t; WR = $r; WB = $b - $(if ($prim) { 40 } else { 0 }); Primary = $prim; Forbidden = $fb } }
  $ln = @(@{ Id = 'i3'; W = 1040; H = 807; Display = 'DISPLAY2'; X = 0; Y = 0 }, @{ Id = 'i4'; W = 1040; H = 807; Display = 'DISPLAY2'; X = 1300; Y = 0 }, @{ Id = 'i5'; W = 1040; H = 807; Display = 'DISPLAY1'; X = -1500; Y = 400 })
  # A) layout that made the slots stale: Samsung DISPLAY3 primary at 0,0; DISPLAY1/2 to its left
  $LayA = @((Scr 'DISPLAY1' -4480 360 -2560 1440), (Scr 'DISPLAY2' -2560 0 0 1440), (Scr 'DISPLAY3' 0 0 3840 2160 $true $true))
  # B) today: DISPLAY2 is Shay's primary 2560x1440, DISPLAY1 on its left, no Samsung
  $LayB = @((Scr 'DISPLAY1' -1920 360 0 1440), (Scr 'DISPLAY2' 0 0 2560 1440 $true))
  # C) Windows renumbered: the Samsung (forbidden by hardware id) is now DISPLAY1
  $LayC = @((Scr 'DISPLAY1' 0 0 3840 2160 $true $true), (Scr 'DISPLAY2' 3840 0 5760 1080), (Scr 'DISPLAY4' 5760 0 8320 1440))
  foreach ($case in @(@('A', $LayA), @('B', $LayB), @('C', $LayC))) {
    $p = @(Plan-Slots $case[1] $ln)
    foreach ($s in $p) {
      if ($s.Display -in @('DISPLAY3')) { $bad++; "FAIL $($case[0]) $($s.Lane) planned on DISPLAY3" }
      if ($s.Display) {
        $sc = $case[1] | Where-Object { $_.Name -eq $s.Display }
        if ($sc.Forbidden -or $s.Display -notmatch '^DISPLAY[12]$') { $bad++; "FAIL $($case[0]) $($s.Lane) on a forbidden/unauthorised display $($s.Display)" }
        $r = [pscustomobject]@{ L = $s.X; T = $s.Y; R = $s.X + $s.W; B = $s.Y + $s.H }
        if (-not (Inside ([pscustomobject]@{ L = $sc.WL; T = $sc.WT; R = $sc.WR; B = $sc.WB }) $r)) { $bad++; "FAIL $($case[0]) $($s.Lane) not wholly inside $($s.Display)" }
        foreach ($o in $p) { if ($o.Lane -ne $s.Lane -and $o.Display -and $s.Why -notlike 'stacked*' -and $o.Why -notlike 'stacked*' -and (Overlap $r ([pscustomobject]@{ L = $o.X; T = $o.Y; R = $o.X + $o.W; B = $o.Y + $o.H }))) { $bad++; "FAIL $($case[0]) $($s.Lane) overlaps $($o.Lane)" } }
      }
    }
    if ($case[0] -ne 'C' -and @($p | Where-Object { -not $_.Display }).Count) { $bad++; "FAIL $($case[0]) a lane got no slot" }
  }
  $pB = @(Plan-Slots $LayB $ln); if ($pB[0].Why -notlike 'registry*' -or $pB[2].Display -ne 'DISPLAY1') { $bad++; 'FAIL B must keep valid registry slots / i5 on DISPLAY1' }
  $pA = @(Plan-Slots $LayA $ln); if ($pA[1].Why -notlike 'computed*' -or $pA[1].X -ne -1500 -or $pA[1].Display -ne 'DISPLAY2') { $bad++; "FAIL A stale i4 slot must be recomputed on DISPLAY2 (got $($pA[1].Display) $($pA[1].X))" }
  # D) the layout seen 2026-10-15: the Samsung (by hardware id) is DISPLAY1 at -1920,360, the primary DISPLAY2 is the only allowed screen: i3/i4 fit side by side, i5 is STACKED on DISPLAY2 (never DISPLAY1)
  $LayD = @((Scr 'DISPLAY1' -1920 360 0 1440 $false $true), (Scr 'DISPLAY2' 0 0 2560 1440 $true)); $pD = @(Plan-Slots $LayD $ln)
  if ($pD[0].Display -ne 'DISPLAY2' -or $pD[1].Display -ne 'DISPLAY2' -or $pD[2].Display -ne 'DISPLAY2' -or $pD[2].Why -notlike 'stacked*' -or $pD[0].Why -like 'stacked*' -or $pD[1].Why -like 'stacked*') { $bad++; 'FAIL D i3/i4 free slots on DISPLAY2, i5 stacked on DISPLAY2 expected' }
  foreach ($o in @($pD[0], $pD[1])) { if ([Math]::Max([Math]::Abs($pD[2].X - $o.X), [Math]::Abs($pD[2].Y - $o.Y)) -lt 40) { $bad++; "FAIL D i5 stack offset < 40 px from $($o.Lane)" } }
  # E) four lanes on one allowed screen: i5 and i6 both stacked, 40 px apart from every lane, still inside the working area
  $ln4 = $ln + @(@{ Id = 'i6'; W = 1040; H = 807; Display = 'DISPLAY2'; X = 0; Y = 0 }); $pE = @(Plan-Slots $LayD $ln4)
  foreach ($a1 in $pE) { if (-not $a1.Display -or $a1.Display -ne 'DISPLAY2') { $bad++; "FAIL E $($a1.Lane) display $($a1.Display)" } else { foreach ($o in $pE) { if ($o.Lane -ne $a1.Lane -and [Math]::Max([Math]::Abs($a1.X - $o.X), [Math]::Abs($a1.Y - $o.Y)) -lt 40) { $bad++; "FAIL E $($a1.Lane)/$($o.Lane) stack offset < 40 px" } }; if (-not (Inside ([pscustomobject]@{ L = 0; T = 0; R = 2560; B = 1400 }) ([pscustomobject]@{ L = $a1.X; T = $a1.Y; R = $a1.X + $a1.W; B = $a1.Y + $a1.H }))) { $bad++; "FAIL E $($a1.Lane) outside working area" } } }
  if (@($pE | Where-Object { $_.Why -like 'stacked*' }).Count -ne 2) { $bad++; 'FAIL E expected exactly i5/i6 stacked' }
  # F) a forbidden screen is never used for stacking (only-forbidden stays NO-SLOT: checked below)
  $pS = @(Plan-Slots @((Scr 'DISPLAY3' 0 0 3840 2160 $true $true)) $ln); if (@($pS | Where-Object { $_.Display }).Count) { $bad++; 'FAIL only-forbidden layout must give no slot' }
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
$scr = @(Screens $forbid)
function ScreenOf($r) { $scr | Where-Object { Inside $_ $r } | Select-Object -First 1 }
# Slots always come from the LIVE layout (registry window values are only a size/position preference, they go stale when Windows renumbers or moves monitors).
$planLanes = if ($Action -eq 'place' -or $Action -eq 'show') { @($reg.lanes | Where-Object { $id = $_.id; $id -eq ($Lane -replace '^(\d)$', 'i$1') -or @($rows | Where-Object { $_.Lane -eq $id -and $_.Rect }).Count }) } else { @($reg.lanes) }   # place/show: only running lanes + the requested one reserve space (one 5090 lane may be i5 even though the full 3-lane plan has no room for it)
$plan = @(Plan-Slots $scr @($planLanes | ForEach-Object { @{ Id = $_.id; W = $_.window.w; H = $_.window.h; Display = $_.window.display; X = $_.window.x; Y = $_.window.y } }))
function PlanOf($id) { $plan | Where-Object { $_.Lane -eq $id } | Select-Object -First 1 }
if ($Action -eq 'plan' -or $Action -eq 'sync') {
  foreach ($p in $plan) { "{0} slot {1} {2},{3} {4}x{5} ({6})" -f $p.Lane, $(if ($p.Display) { $p.Display } else { 'NONE' }), $p.X, $p.Y, $p.W, $p.H, $p.Why }
  "screens: " + (($scr | ForEach-Object { "$($_.Name) $($_.L),$($_.T)-$($_.R),$($_.B)$(if ($_.Primary) { ' primary' })$(if ($_.Forbidden) { ' FORBIDDEN' })" }) -join '; ')
  if ($Action -eq 'sync') {   # write the live slots into the registry (backup first); a lane without a slot keeps its old values
    Copy-Item 'C:\KenshiTestRuns\lanes\lanes-5090.json' 'C:\KenshiTestRuns\lanes\lanes-5090.json.bak-lanewindow' -Force
    foreach ($l in $reg.lanes) { $p = PlanOf $l.id; if ($p -and $p.Display) { $l.window.display = $p.Display; $l.window.x = $p.X; $l.window.y = $p.Y } }
    ($reg | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 'C:\KenshiTestRuns\lanes\lanes-5090.json'
    'registry window slots updated'
    Remove-Item 'C:\KenshiTestRuns\preflight-isolation-5090.txt' -ErrorAction SilentlyContinue   # drop the cached preflight isolation result: it was judged against the old slots
  }
  exit 0
}
if ($Action -eq 'show') {
  foreach ($r in $rows) {
    if (-not $r.Rect) { $pl = PlanOf $r.Lane; "{0} not running (slot {1} {2},{3} {4}x{5})" -f $r.Lane, $(if ($pl.Display) { $pl.Display } else { 'NONE' }), $pl.X, $pl.Y, $pl.W, $pl.H; continue }
    $s = ScreenOf $r.Rect
    $ov = @($rows | Where-Object { $_.Lane -ne $r.Lane -and $_.Rect -and (Overlap $_.Rect $r.Rect) } | ForEach-Object Lane)
    "{0} pid={1} rect={2},{3},{4},{5} ({6}x{7}) screen={8} overlap=[{9}] forbidden={10}" -f $r.Lane, $r.Pid, $r.Rect.L, $r.Rect.T, $r.Rect.R, $r.Rect.B, ($r.Rect.R - $r.Rect.L), ($r.Rect.B - $r.Rect.T), $(if ($s) { $s.Name } else { 'SPANS/NONE' }), ($ov -join ','), $(if ($s -and $s.Forbidden) { 'YES' } else { 'no' })
  }
  "foreground pid=$([LaneWin]::FgPid()) lanes=" + (($rows | ForEach-Object { "$($_.Lane):$($_.Pid)" }) -join ' ')
  exit 0
}
# place
$want = if ($Lane -eq 'all') { $rows } else { $rows | Where-Object { $_.Lane -eq ($Lane -replace '^(\d)$', 'i$1') } }
foreach ($r in $want) {
  if (-not $r.Rect) { "{0} not running: skipped" -f $r.Lane; continue }
  $pl = PlanOf $r.Lane
  if (-not $pl -or -not $pl.Display) { "REFUSED {0}: no free slot on an allowed display (DISPLAY1/2, not forbidden) in the live layout" -f $r.Lane; exit 1 }
  $sl = [pscustomobject]@{ display = $pl.Display; x = $pl.X; y = $pl.Y; w = $pl.W; h = $pl.H }; $dest = [pscustomobject]@{ L = [int]$sl.x; T = [int]$sl.y; R = [int]$sl.x + [int]$sl.w; B = [int]$sl.y + [int]$sl.h }
  $s = ScreenOf $dest
  if (-not $s -or ('\\.\' + $s.Name) -ne ('\\.\' + $sl.display) -or $s.Forbidden) { "REFUSED {0}: slot not wholly inside {1} (or forbidden)" -f $r.Lane, $sl.display; exit 1 }
  $stk = $pl.Why -like 'stacked*'
  $hit = @($rows | Where-Object { $_.Lane -ne $r.Lane -and $_.Rect -and (Overlap $_.Rect $dest) } | ForEach-Object Lane)
  if ($hit.Count -and -not $stk) { "REFUSED {0}: slot overlaps running window of {1}" -f $r.Lane, ($hit -join ','); exit 1 }
  "{0} slot {1} {2},{3} ({4}){5}" -f $r.Lane, $sl.display, $sl.x, $sl.y, $pl.Why, $(if ($stk -and $hit.Count) { " stacked-over=[$($hit -join ',')]" } else { '' })
  # stacked lane: HWND_BOTTOM (1) + NOACTIVATE|NOSENDCHANGING (no NOZORDER, so the window really goes to the bottom); never focuses, no input
  $ok = if ($stk) { [LaneWin]::SetWindowPos($r.Hwnd, [IntPtr]1, $dest.L, $dest.T, $sl.w, $sl.h, [uint32](0x0010 -bor 0x0400)) } else { [LaneWin]::SetWindowPos($r.Hwnd, [IntPtr]::Zero, $dest.L, $dest.T, $sl.w, $sl.h, [uint32](0x0004 -bor 0x0010 -bor 0x0400)) }
  $w = [LaneWin]::Game([uint32]$r.Pid) | Select-Object -First 1
  "{0} placed ok={1} now={2},{3},{4},{5}" -f $r.Lane, $ok, $w[1], $w[2], $w[3], $w[4]
}
