# gaming-throttle.ps1 on|off|status   (Windows, no admin)
# Shay 2026-10-10: "I'm going to play Overwatch on the 5090: keep testing but cut CPU/GPU use, no 80% CPU spikes;
# reduce memory too." While C:\KenshiTestRuns\gaming.on exists:
#   - kenshi_x64: priority BelowNormal, affinity = logical CPUs 24-31 (8 of 32), frame cap 30 fps (harness framecap.txt,
#     needs a harness with FrameCap; launches write 60, the loop puts 30 back within 15 s)
#   - WSL: wsl-cpucap.sh pins every WSL process to vCPUs 0-5 (at most 6 host threads busy) and renices them to >= 10,
#     and drops the page cache so vmmem gives RAM back
#   (vmmem itself can't be reprioritised without admin: Access denied)
# Worst case ~14 of 32 logical CPUs busy instead of all 32. 'off' removes the flag; the loops restore full affinity,
# Normal priority and the 60 fps test cap, then exit.
param([Parameter(Position=0)][ValidateSet('on','off','status','loop')][string]$Cmd = 'status')
$Flag   = 'C:\KenshiTestRuns\gaming.on'
$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
$capF   = "$Kenshi\mods\AutomationHarness\framecap.txt"
$Mask   = [IntPtr]0xFF000000L
$All    = [IntPtr]0xFFFFFFFFL
$Distro = 'DwemerAI4Skyrim3'

function Kp { Get-Process kenshi_x64 -ErrorAction SilentlyContinue }
function Apply {
  foreach ($p in Kp) {
    try { if ($p.ProcessorAffinity -ne $Mask) { $p.ProcessorAffinity = $Mask } } catch {}
    try { if ($p.PriorityClass -ne 'BelowNormal') { $p.PriorityClass = 'BelowNormal' } } catch {}
  }
  if ((Kp) -and ((-not (Test-Path $capF)) -or ((Get-Content $capF -TotalCount 1).Trim() -ne '30'))) {
    Set-Content -Path $capF -Value '30' -Encoding Ascii }
}
function Restore {
  foreach ($p in Kp) { try { $p.ProcessorAffinity = $All; $p.PriorityClass = 'Normal' } catch {} }
  if (Test-Path $capF) { Set-Content -Path $capF -Value '60' -Encoding Ascii }
}
function StartWsl {
  & wsl.exe -d $Distro -u root --cd / -- setsid -f bash /mnt/c/KenshiModding/tools/automation/wsl-cpucap.sh loop | Out-Null
}

switch ($Cmd) {
  'on' {
    Set-Content -Path $Flag -Value "on $(Get-Date -Format s)" -Encoding Ascii
    Apply; StartWsl
    $me = $MyInvocation.MyCommand.Path
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$me`" loop"
    "gaming throttle ON: Kenshi CPUs 24-31 BelowNormal cap 30, WSL vCPUs 0-5 nice>=10 + cache drop"
  }
  'off' {
    Remove-Item $Flag -Force -ErrorAction SilentlyContinue; Restore
    "gaming throttle OFF (loops restore and exit within 15 s)"
  }
  'loop' {
    $mtx = New-Object System.Threading.Mutex($false, 'Global\kenshi-gaming-throttle')
    if (-not $mtx.WaitOne(0)) { exit 0 }
    $n = 0
    while (Test-Path $Flag) {
      Apply
      if ((++$n % 8) -eq 0) { StartWsl }   # every 2 min: restart the WSL loop if WSL restarted (it is single-instance)
      Start-Sleep 15
    }
    Restore
  }
  'status' {
    $on = Test-Path $Flag
    $k = Kp | Select-Object -First 1
    $cap = if (Test-Path $capF) { (Get-Content $capF -TotalCount 1).Trim() } else { 'off' }
    if ($k) { "gaming=$on kenshi affinity=0x{0:X} prio={1} cap={2}" -f [int64]$k.ProcessorAffinity, $k.PriorityClass, $cap }
    else { "gaming=$on kenshi=not running cap=$cap" }
  }
}
