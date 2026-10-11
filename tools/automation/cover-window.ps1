<#
cover-window.ps1 [-Seconds 20] [-Title <game window title>] [-Instance n]
Test helper for capture-proof.sh (capture-fix 2026-10-11): puts an opaque magenta window, topmost and never activated
(no focus change, ShowWithoutActivation + WS_EX_NOACTIVATE), exactly over the game window's client area for -Seconds,
then closes it. A take recorded meanwhile must still show the game (Windows Graphics Capture), while a gdigrab clip
shows magenta. Writes "COVER <x>,<y> <w>x<h>" to C:\KenshiTestRuns\cover-window.state while it is up (deleted at the end).
#>
param([int]$Seconds = 20, [string]$Title = 'Kenshi 1.0.65 - x64 (Newland)')
$state = 'C:\KenshiTestRuns\cover-window.state'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public static class CoverWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
}
public class NoActForm : Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x8 | 0x80; return p; } } // NOACTIVATE|TOPMOST|TOOLWINDOW
}
'@ -ReferencedAssemblies System.Windows.Forms
try { [CoverWin]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch {}
$h = [CoverWin]::FindWindowW($null, $Title)
if ($h -eq [IntPtr]::Zero) { "cover: no window '$Title'"; exit 1 }
$r = New-Object CoverWin+RECT; [CoverWin]::GetClientRect($h, [ref]$r) | Out-Null
$p = New-Object CoverWin+POINT; [CoverWin]::ClientToScreen($h, [ref]$p) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$f = New-Object NoActForm
$f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.BackColor = [Drawing.Color]::FromArgb(255, 0, 255); $f.ShowInTaskbar = $false
$f.Text = 'kah-cover'
$t = New-Object Windows.Forms.Timer; $t.Interval = $Seconds * 1000; $t.Add_Tick({ $f.Close() })
$f.Add_Shown({ [CoverWin]::SetWindowPos($f.Handle, [IntPtr]-1, $p.X, $p.Y, $w, $hh, 0x10 -bor 0x40) | Out-Null; $t.Start() })
Set-Content -Path $state -Value "COVER $($p.X),$($p.Y) ${w}x$hh" -Encoding ascii
"COVER $($p.X),$($p.Y) ${w}x$hh"
[Windows.Forms.Application]::Run($f)
Remove-Item $state -Force -ErrorAction SilentlyContinue
"cover closed"
