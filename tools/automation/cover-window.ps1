<#
cover-window.ps1 [-Seconds 20] [-Title <game window title>] [-State <file>]
cover-window.ps1 -SelfTest [-CoverScript <other copy>] [-Ffmpeg <ffmpeg.exe>]
Test helper for capture-proof.sh (capture-fix 2026-10-11): puts an opaque magenta window, topmost and never activated
(WS_EX_NOACTIVATE, SW_SHOWNOACTIVATE), exactly over the game window's client area for -Seconds, then closes it. A take
recorded meanwhile must still show the game (Windows Graphics Capture), while a screen grab of the area shows magenta.
State file (default C:\KenshiTestRuns\cover-window.state), written once the cover is up AND verified:
  "COVER <x>,<y> <w>x<h>"   the cover is the top window at 9 points of the target's client area (WindowFromPoint)
  "COVERFAIL <why>"         it is not (wrong place / another window on top / no target): capture-proof fails setup with <why>
-SelfTest (no game): opens a grey, never-activated target window on DISPLAY2 (never the Samsung), covers it with this script
  (or -CoverScript) in a second process, then checks on its own with WindowFromPoint that the target is hidden at 9 points;
  prints ONE line COVERTEST PASS|FAIL. -Ffmpeg: also the capture-proof control while covered: a gdigrab grab of the screen
  area must be magenta (screen=rgb); a gdigrab title= grab is reported (title=rgb: grey here = title= reads the window's
  own surface, which is why 89b's title= control could never see the cover).
Why native windows (89b-capproof-5090 2026-10-11, "gdigrab control is rgb(103 102 94), not magenta"): the WinForms cover in
a per-monitor-DPI PowerShell was first shown at the default place (primary monitor = Shay's Samsung) and moved across
monitors with different DPI; WinForms then rescaled/moved it (a WinForms selftest target was seen jumping between DISPLAY2
and the Samsung). Plain CreateWindowEx windows are created in place and never moved by DPI changes.
#>
param([int]$Seconds = 20, [string]$Title = 'Kenshi 1.0.65 - x64 (Newland)', [string]$State = 'C:\KenshiTestRuns\cover-window.state',
      [switch]$SelfTest, [string]$CoverScript = '', [string]$Ffmpeg = '')
$logf = 'C:\KenshiTestRuns\cover-window.log'
function Log($m) { Add-Content $logf "$(Get-Date -Format s) $m" }
trap { Log "ERROR $_"; if (-not $SelfTest) { Set-Content -Path $State -Value "COVERFAIL error: $_" -Encoding ascii }; "COVERTEST FAIL error: $_"; exit 1 }
Log "start title='$Title' seconds=$Seconds selftest=$SelfTest"
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Threading;
public static class NW {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint m; public IntPtr w, l; public uint t; public POINT p; }
  delegate IntPtr WndProcD(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct WNDCLASS { public uint style; public WndProcD proc; public int ce, we;
    public IntPtr inst, icon, cursor, brush; public string menu, cls; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowW(IntPtr c, string t);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassW(ref WNDCLASS c);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string cls, string t, uint st, int x, int y, int w, int h, IntPtr p, IntPtr m, IntPtr i, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool PeekMessageW(out MSG m, IntPtr h, uint a, uint b, uint r);
  [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessageW(ref MSG m);
  [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(uint c);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandleW(IntPtr n);
  static WndProcD keep = Proc;   // the delegate must outlive the windows
  static IntPtr Proc(IntPtr h, uint m, IntPtr w, IntPtr l) { if (m == 0x02E0) return IntPtr.Zero; return DefWindowProcW(h, m, w, l); } // WM_DPICHANGED: stay put
  // a borderless solid window created in place (x,y,w,h physical px), shown without activation; topmost optional
  public static IntPtr Make(string title, uint bgr, int x, int y, int w, int h, bool top) {
    string cls = "kah-cover-" + bgr.ToString("x6");
    WNDCLASS c = new WNDCLASS(); c.proc = keep; c.inst = GetModuleHandleW(IntPtr.Zero); c.brush = CreateSolidBrush(bgr); c.cls = cls;
    RegisterClassW(ref c);   // fails harmlessly if already registered
    uint ex = 0x08000000 | 0x80 | (top ? 0x8u : 0u);   // NOACTIVATE | TOOLWINDOW | TOPMOST
    IntPtr hw = CreateWindowExW(ex, cls, title, 0x80000000, x, y, w, h, IntPtr.Zero, IntPtr.Zero, c.inst, IntPtr.Zero); // WS_POPUP
    if (hw != IntPtr.Zero) { ShowWindow(hw, 4); SetWindowPos(hw, top ? new IntPtr(-1) : IntPtr.Zero, x, y, w, h, 0x10 | 0x40 | (top ? 0u : 0x4u)); }
    return hw;
  }
  public static void Pump(int ms) { MSG m; var end = Environment.TickCount + ms;
    do { while (PeekMessageW(out m, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref m); DispatchMessageW(ref m); } Thread.Sleep(20); } while (Environment.TickCount < end); }
  // how many of 9 client points of target show 'want' as their top-level window (or anything but target when want == 0)
  public static int Hits(IntPtr target, IntPtr want) { RECT r; GetClientRect(target, out r); POINT o = new POINT(); ClientToScreen(target, ref o); int n = 0;
    foreach (double fx in new[] { 0.05, 0.5, 0.95 }) foreach (double fy in new[] { 0.05, 0.5, 0.95 }) {
      POINT q = new POINT(); q.X = o.X + (int)(r.R * fx); q.Y = o.Y + (int)(r.B * fy); IntPtr top = GetAncestor(WindowFromPoint(q), 2);
      if (want == IntPtr.Zero ? top != target : top == want) n++; }
    return n; }
}
'@
[NW]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null   # per-monitor v2: every coordinate is physical pixels

if ($SelfTest) {
  Add-Type -AssemblyName System.Windows.Forms
  $scr = [Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -like '*DISPLAY2' } | Select-Object -First 1
  if (-not $scr) { "COVERTEST FAIL no DISPLAY2 (never test on the Samsung)"; exit 1 }
  $tt = "kah-cover-selftest-$PID"; $gx = $scr.Bounds.X + $scr.Bounds.Width - 900; $gy = $scr.Bounds.Y + 120
  $g = [NW]::Make($tt, 0x808080, $gx, $gy, 640, 400, $false)
  $res = 'COVERTEST FAIL timeout'
  try {
    $wr = New-Object NW+RECT; [NW]::GetWindowRect($g, [ref]$wr) | Out-Null
    if ($wr.L -ne $gx -or $wr.T -ne $gy) { throw "target not placed: $($wr.L),$($wr.T) for $gx,$gy" }
    $sf = "$env:TEMP\cover-selftest-$PID.state"; Remove-Item $sf -Force -ErrorAction SilentlyContinue
    $cs = if ($CoverScript) { $CoverScript } else { $PSCommandPath }
    $ps = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$cs`"",'-Seconds','4','-Title',"`"$tt`"",'-State',"`"$sf`""
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 15000 -and -not (Test-Path $sf)) { [NW]::Pump(100) }
    if (Test-Path $sf) {
      $s = (Get-Content $sf -Raw).Trim(); [NW]::Pump(800)
      $hid = [NW]::Hits($g, [IntPtr]::Zero); [NW]::GetWindowRect($g, [ref]$wr) | Out-Null
      $grab = ''; $scrok = $true
      if ($Ffmpeg) {
        $rgb = { param($a) & $Ffmpeg -hide_banner -loglevel error -y -f gdigrab @a -frames:v 1 -vf scale=1:1:flags=area -f rawvideo -pix_fmt rgb24 "$env:TEMP\cover-grab-$PID.raw" 2>$null
          $b = [IO.File]::ReadAllBytes("$env:TEMP\cover-grab-$PID.raw"); Remove-Item "$env:TEMP\cover-grab-$PID.raw" -Force; $b }
        $sb = & $rgb @('-offset_x', "$($gx + 8)", '-offset_y', "$($gy + 8)", '-video_size', '624x384', '-i', 'desktop')
        $tb = & $rgb @('-i', "title=$tt")
        $scrok = $sb.Count -eq 3 -and $sb[0] -gt 150 -and $sb[1] -lt 90 -and $sb[2] -gt 150
        $grab = " screen=rgb($($sb -join ' ')) title=rgb($($tb -join ' '))" }
      $res = if ($s -like 'COVER *' -and $hid -eq 9 -and $scrok) { "COVERTEST PASS $s$grab" } else { "COVERTEST FAIL state '$s', target hidden at $hid/9 points (target at $($wr.L),$($wr.T))$grab" }
    }
    $ps.WaitForExit(10000) | Out-Null; Remove-Item $sf -Force -ErrorAction SilentlyContinue
  } catch { $res = "COVERTEST FAIL $_" } finally { [NW]::DestroyWindow($g) | Out-Null }
  $res; Log $res; if ($res -like 'COVERTEST PASS*') { exit 0 } else { exit 1 }
}

Remove-Item $State -Force -ErrorAction SilentlyContinue
$h = [NW]::FindWindowW([IntPtr]::Zero, $Title)   # IntPtr.Zero: PowerShell passes "" for $null to a string param
if ($h -eq [IntPtr]::Zero) { Log "no window '$Title'"; Set-Content -Path $State -Value "COVERFAIL no window '$Title'" -Encoding ascii; "cover: no window '$Title'"; exit 1 }
$r = New-Object NW+RECT; [NW]::GetClientRect($h, [ref]$r) | Out-Null
$p = New-Object NW+POINT; [NW]::ClientToScreen($h, [ref]$p) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$f = [NW]::Make('kah-cover', 0xFF00FF, $p.X, $p.Y, $w, $hh, $true)
if ($f -eq [IntPtr]::Zero) { Set-Content -Path $State -Value 'COVERFAIL CreateWindowEx failed' -Encoding ascii; exit 1 }
[NW]::Pump(300)
$wr = New-Object NW+RECT; [NW]::GetWindowRect($f, [ref]$wr) | Out-Null
$on = [NW]::Hits($h, $f)
$msg = if ($wr.L -ne $p.X -or $wr.T -ne $p.Y -or ($wr.R - $wr.L) -ne $w -or ($wr.B - $wr.T) -ne $hh) { "COVERFAIL cover at $($wr.L),$($wr.T) $($wr.R - $wr.L)x$($wr.B - $wr.T), target $($p.X),$($p.Y) ${w}x$hh" }
       elseif ($on -ne 9) { "COVERFAIL cover on top at $on/9 points of the target $($p.X),$($p.Y) ${w}x$hh" }
       else { "COVER $($p.X),$($p.Y) ${w}x$hh" }
Set-Content -Path $State -Value $msg -Encoding ascii; Log $msg; $msg
if ($msg -like 'COVERFAIL*') { [NW]::DestroyWindow($f) | Out-Null; exit 1 }   # a COVERFAIL state stays for the caller
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt $Seconds * 1000 -and [NW]::IsWindow($h)) {   # keep it on top of the target, follow a move
  [NW]::Pump(200); $c = New-Object NW+POINT; [NW]::ClientToScreen($h, [ref]$c) | Out-Null
  [NW]::SetWindowPos($f, [IntPtr]-1, $c.X, $c.Y, $w, $hh, 0x10) | Out-Null }
[NW]::DestroyWindow($f) | Out-Null
Remove-Item $State -Force -ErrorAction SilentlyContinue
"cover closed"
