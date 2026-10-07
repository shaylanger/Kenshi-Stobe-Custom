# kenshi-key.ps1 <vk-hex> [holdMs]: press one virtual key in Kenshi. Example: kenshi-key.ps1 0xDC (VK_OEM_5 '\'), 0xBF ('/'), 0x1B (Esc).
# Input isolation on (the harness writes mods\AutomationHarness\input_isolation.on; kenshi-ctl launch turns it on by default):
# the key goes in through the harness (`key_inject <vk> tap <ms>`: DirectInput/OIS + GetAsyncKeyState, no focus needed).
# Otherwise: focus the Kenshi window and press it for real (hooks that poll GetAsyncKeyState + window focus see it).
param([Parameter(Mandatory=$true)][string]$Vk, [int]$HoldMs = 200)
$iso = 'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\input_isolation.on'
if ((Test-Path $iso) -and (Get-Process kenshi_x64 -ErrorAction SilentlyContinue)) {
  $r = (& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- stobe-auto key_inject $Vk tap $HoldMs 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { Write-Output "KEY FAIL injected vk=$Vk : $r"; exit 1 }
  Start-Sleep -Milliseconds ($HoldMs + 100)   # like the real press: return after the key is up again
  Write-Output "KEY OK vk=$Vk injected ($r)"; exit 0
}
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class KK {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
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
# m51: while someone uses the desktop the foreground lock refuses SetForegroundWindow: attach to the foreground thread's input
if ([KK]::GetForegroundWindow() -ne $h) {
  $me = [KK]::GetCurrentThreadId(); $fg = [KK]::GetWindowThreadProcessId([KK]::GetForegroundWindow(), [IntPtr]::Zero)
  [KK]::AttachThreadInput($me, $fg, $true) | Out-Null
  [KK]::BringWindowToTop($h) | Out-Null; [KK]::SetForegroundWindow($h) | Out-Null
  [KK]::AttachThreadInput($me, $fg, $false) | Out-Null
  Start-Sleep -Milliseconds 400
}
if ([KK]::GetForegroundWindow() -ne $h) { Write-Output 'KEY FAIL Kenshi not focused'; exit 1 }
$v = [byte][Convert]::ToInt32($Vk, 16); $s = [byte][KK]::MapVirtualKey($v, 0)
[KK]::keybd_event($v, $s, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds $HoldMs
[KK]::keybd_event($v, $s, 2, [UIntPtr]::Zero)
Write-Output "KEY OK vk=$Vk"
