<#
inst-window.ps1 (4080 rig, C:\KAH\inst-window.ps1; lane 4080b, multi-instance-4080 2026-10-11): keeps a second Kenshi
instance's windows out of lane 1's way. Runs in Shay's desktop session (window calls fail from ssh): ctl.ps1 starts it
next to every `launch|restart -Instance n` (n >= 2). Every second while the game of C:\KenshiInst\<n> runs:
  - every top-level window of that install's kenshi_x64 processes (launcher dialog + game window) goes to -X,-Y (default
    1920,0 = right of the 4080's only screen, 1920x1080: lane 1 films its window with gdigrab, which grabs whatever covers
    it), never activated, never topmost;
  - the game window title gets " [i<n>]" (lane 1's take scripts capture by the exact title "Kenshi 1.0.65 - x64 (Newland)";
    two windows with that title = the capture may pick instance n).
Exits 60 s after the instance's game is gone, or after 10 min if it never appeared. One watcher per instance (mutex).
Log: C:\KenshiTestRuns\inst-window-<n>.log (one line per change). C:\KenshiTestRuns\inst-window-<n>.pos ("x,y", read every
pass) overrides -X/-Y: lane 4080b puts its window on the screen (0,0, not topmost) while it films (WGC films covered windows).
  inst-window.ps1 -Instance 2 [-X 1920 -Y 0] [-Once]   (-Once: one pass, print what it did; for checks over itrun)
#>
param([int]$Instance = 2, [int]$X = 1920, [int]$Y = 0, [switch]$Once)
$ErrorActionPreference = 'Continue'
$root = "C:\KenshiInst\$Instance\"
$log = "C:\KenshiTestRuns\inst-window-$Instance.log"
function Log([string]$m) { Add-Content $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m" -ErrorAction SilentlyContinue; if ($Once) { $m } }
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class KInstWin {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string Text(IntPtr h) { var s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
  public static string Cls(IntPtr h) { var s = new StringBuilder(128); GetClassName(h, s, 128); return s.ToString(); }
  public static List<IntPtr> Of(uint[] pids) {
    var r = new List<IntPtr>(); var set = new HashSet<uint>(pids);
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (set.Contains(p) && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero);
    return r;
  }
}
'@
[KInstWin]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$mtx = New-Object Threading.Mutex($false, "Global\KAH_instwin_$Instance")
if (-not $Once -and -not $mtx.WaitOne(0)) { exit 0 }   # another watcher has this instance
$t0 = Get-Date; $seen = $null; $gone = $null; $done = @{}
Log "watcher up pid=$PID instance=$Instance park=$X,$Y"
while ($true) {
  $pids = [uint32[]]@(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { [uint32]$_.ProcessId })
  $pf = "C:\KenshiTestRuns\inst-window-$Instance.pos"
  if (Test-Path $pf) { $pq = "$((Get-Content $pf -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -split ','; if ($pq.Count -eq 2 -and $pq[0] -match '^-?\d+$' -and $pq[1] -match '^-?\d+$') { $X = [int]$pq[0]; $Y = [int]$pq[1] } }
  if ($pids.Count) {
    $seen = Get-Date; $gone = $null
    foreach ($h in [KInstWin]::Of($pids)) {
      $r = New-Object KInstWin+RECT; [KInstWin]::GetWindowRect($h, [ref]$r) | Out-Null
      $top = ([KInstWin]::GetWindowLong($h, -20) -band 0x8) -ne 0
      if ($r.Left -ne $X -or $r.Top -ne $Y -or $top) {
        # HWND_NOTOPMOST (-2), SWP_NOSIZE 1 | SWP_NOACTIVATE 0x10 | SWP_NOOWNERZORDER 0x200
        $ok = [KInstWin]::SetWindowPos($h, [IntPtr](-2), $X, $Y, 0, 0, 0x211)
        if (-not $done["p$h"] -or $Once) { Log "park $([KInstWin]::Cls($h)) '$([KInstWin]::Text($h))' from $($r.Left),$($r.Top) topmost=$top -> $X,$Y ok=$ok" }; $done["p$h"] = 1
      }
      $c = [KInstWin]::Cls($h); $t = [KInstWin]::Text($h)
      if ($c -like 'OgreD3D*' -and $t -and -not $t.EndsWith(" [i$Instance]")) { $ok = [KInstWin]::SetWindowText($h, "$t [i$Instance]"); Log "retitle '$t' -> '$t [i$Instance]' ok=$ok" }
    }
  } else {
    if ($seen -and -not $gone) { $gone = Get-Date }
    if ($gone -and ((Get-Date) - $gone).TotalSeconds -ge 60) { Log 'game gone 60 s: exit'; break }
    if (-not $seen -and ((Get-Date) - $t0).TotalMinutes -ge 10) { Log 'game never appeared in 10 min: exit'; break }
  }
  if ($Once) { break }
  Start-Sleep -Milliseconds 1000
}
