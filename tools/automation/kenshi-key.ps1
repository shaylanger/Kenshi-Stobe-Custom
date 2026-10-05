# kenshi-key.ps1 <vk-hex> [holdMs]: focus the Kenshi window and press one virtual key (real input, so hooks that
# poll GetAsyncKeyState + window focus see it). Example: kenshi-key.ps1 0xDC (VK_OEM_5 '\'), 0xBF ('/'), 0x1B (Esc).
param([Parameter(Mandatory=$true)][string]$Vk, [int]$HoldMs = 200)
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KK {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
}
'@
$p = Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
if (-not $p) { Write-Output 'KEY FAIL no Kenshi window'; exit 1 }
$h = $p.MainWindowHandle
if ([KK]::GetForegroundWindow() -ne $h) {
  (New-Object -ComObject WScript.Shell).AppActivate($p.Id) | Out-Null
  [KK]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 400
}
if ([KK]::GetForegroundWindow() -ne $h) { Write-Output 'KEY FAIL Kenshi not focused'; exit 1 }
$v = [byte][Convert]::ToInt32($Vk, 16); $s = [byte][KK]::MapVirtualKey($v, 0)
[KK]::keybd_event($v, $s, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds $HoldMs
[KK]::keybd_event($v, $s, 2, [UIntPtr]::Zero)
Write-Output "KEY OK vk=$Vk"
