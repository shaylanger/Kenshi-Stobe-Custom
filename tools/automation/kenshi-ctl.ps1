<#
kenshi-ctl.ps1: start, stop and watch Kenshi for automated test runs.

  kenshi-ctl.ps1 status                 running? pid, uptime, window, launcher open?
  kenshi-ctl.ps1 launch [-Save <name>]  archive logs, start Kenshi, press the launcher's OK,
                                        wait for the main menu (and load <name> if given)
  kenshi-ctl.ps1 stop                   kill Kenshi (never saves)
  kenshi-ctl.ps1 restart [-Save <name>] stop + launch
  kenshi-ctl.ps1 health                 ok | crashed | hung | not-running (exit code 0/1)
  kenshi-ctl.ps1 screenshot [-Save n]   PNG of the game window (works in the background)
                                        -> C:\KenshiTestRuns\shots\<n|time>.png

Steam must be running (steam_appid.txt lets the exe start without the Steam
"Play / modding tool" prompt). RE_Kenshi restarts the game into
RE_Kenshi\kenshi_x64.exe --norestart; the launcher dialog opens in that
second process, so both are followed. Loading a save needs the test inbox
switch (mods\Stobe\test_inbox.flag) and Stobe's autoload.txt support.
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Save = '',
  [int]$TimeoutSec = 300
)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'Win32Ui.cs')

$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
$ModDir = "$Kenshi\RE_Kenshi\mods\Stobe"
$ArchiveRoot = 'C:\KenshiTestRuns\logs'
$LauncherOkId = 1003

# The leading comma keeps a one-process result an array (so .Count works).
function Get-KenshiProcs { , @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'") }

function Get-Launcher {
  $procs = Get-KenshiProcs
  if ($procs.Count -eq 0) { return $null }
  $pids = [uint32[]]@($procs | ForEach-Object { [uint32]$_.ProcessId })
  [KenshiWin32]::TopWindows($pids) | Where-Object { $_.Cls -eq '#32770' -and $_.Title -like 'Kenshi*' } | Select-Object -First 1
}

function Get-GameWindow {
  $procs = Get-KenshiProcs
  if ($procs.Count -eq 0) { return $null }
  $pids = [uint32[]]@($procs | ForEach-Object { [uint32]$_.ProcessId })
  [KenshiWin32]::TopWindows($pids) | Where-Object { $_.Cls -like 'OgreD3D*' } | Select-Object -First 1
}

function Get-LatestCrashDump {
  Get-ChildItem $Kenshi -Filter 'crashDump*.zip' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Save-Logs([string]$Reason) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dest = Join-Path $ArchiveRoot "$stamp-$Reason"
  New-Item -ItemType Directory -Force $dest | Out-Null
  foreach ($f in @("$ModDir\stobe.log", "$Kenshi\KenshiFP.log", "$Kenshi\RE_Kenshi_log.txt",
                   "$ModDir\auto_outbox.txt", "$ModDir\test_outbox.txt")) {
    if (Test-Path $f) { Copy-Item $f $dest -ErrorAction SilentlyContinue }
  }
  $dest
}

function Stop-Kenshi {
  $procs = Get-KenshiProcs
  foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-KenshiProcs).Count -gt 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  if ((Get-KenshiProcs).Count -gt 0) { throw 'Kenshi did not exit' }
  "stopped ($($procs.Count) process(es))"
}

function Wait-Until([scriptblock]$Cond, [int]$Seconds, [string]$What) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $r = & $Cond
    if ($r) { return $r }
    if ((Get-KenshiProcs).Count -eq 0) { throw "Kenshi exited while waiting for $What" }
    Start-Sleep -Milliseconds 500
  }
  throw "timed out after $Seconds s waiting for $What"
}

function Read-StobeLogMatch([string]$Pattern) {
  $log = "$ModDir\stobe.log"
  if (-not (Test-Path $log)) { return $null }
  Select-String -Path $log -Pattern $Pattern -SimpleMatch | Select-Object -Last 1
}

function Start-Kenshi {
  if ((Get-KenshiProcs).Count -gt 0) { throw 'Kenshi is already running (stop it first)' }
  if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Steam is not running' }
  $archived = Save-Logs 'before-launch'
  "logs archived to $archived"
  # Stobe recreates stobe.log on start; removing it keeps the waits below from
  # matching lines of the previous session.
  Remove-Item "$ModDir\stobe.log" -ErrorAction SilentlyContinue
  if ($Save) {
    if (-not (Test-Path "$ModDir\test_inbox.flag")) { throw 'test inbox is off (stobe-say on) so autoload would be ignored' }
    Set-Content -Path "$ModDir\autoload.txt" -Value $Save -Encoding Ascii -NoNewline
  }
  Remove-Item "$ModDir\auto_inbox.txt" -ErrorAction SilentlyContinue
  $t0 = Get-Date
  Start-Process -FilePath "$Kenshi\kenshi_x64.exe" -WorkingDirectory $Kenshi | Out-Null
  $launcher = Wait-Until { Get-Launcher } 120 'the launcher dialog'
  # Let the dialog finish initialising (mod list) before pressing OK.
  Start-Sleep -Seconds 2
  [KenshiWin32]::PressDialogButton($launcher.Handle, $LauncherOkId)
  "launcher OK pressed after $([int]((Get-Date) - $t0).TotalSeconds) s"
  Wait-Until { -not (Get-Launcher) -and (Get-GameWindow) } 60 'the game window' | Out-Null
  Wait-Until { Read-StobeLogMatch 'TEST_AUTO: frame listener running' } $TimeoutSec 'the Stobe frame listener' | Out-Null
  "frame listener running after $([int]((Get-Date) - $t0).TotalSeconds) s"
  if ($Save) {
    Wait-Until { Read-StobeLogMatch "TEST_AUTO: autoload $Save" } $TimeoutSec 'autoload' | ForEach-Object { $_.Line }
  }
  $p = Get-KenshiProcs | Select-Object -First 1
  "running: pid=$($p.ProcessId) cmd=$($p.CommandLine)"
}

function Get-Health {
  $procs = Get-KenshiProcs
  $state = Join-Path $ArchiveRoot 'last-launch.txt'
  if ($procs.Count -eq 0) {
    $dump = Get-LatestCrashDump
    if ($dump -and $dump.LastWriteTime -gt (Get-Date).AddMinutes(-10)) { return "crashed (dump $($dump.Name) at $($dump.LastWriteTime))" }
    return 'not-running'
  }
  $win = Get-GameWindow
  if (-not $win) { if (Get-Launcher) { return 'launcher-open' } return 'no-window' }
  $p = Get-Process -Id $procs[0].ProcessId
  if (-not $p.Responding) { return 'hung (window not responding)' }
  return 'ok'
}

switch ($Command) {
  'status' {
    $procs = Get-KenshiProcs
    if ($procs.Count -eq 0) { 'not running'; break }
    foreach ($p in $procs) { "pid=$($p.ProcessId) started=$($p.CreationDate) cmd=$($p.CommandLine)" }
    "launcher open: $([bool](Get-Launcher))   game window: $([bool](Get-GameWindow))   health: $(Get-Health)"
  }
  'launch' { Start-Kenshi }
  'stop' { Save-Logs 'stop' | Out-Null; Stop-Kenshi }
  'restart' { if ((Get-KenshiProcs).Count -gt 0) { Save-Logs 'restart' | Out-Null; Stop-Kenshi }; Start-Kenshi }
  'health' { $h = Get-Health; $h; if ($h -ne 'ok') { exit 1 } }
  'screenshot' {
    Add-Type -Path (Join-Path $PSScriptRoot 'WindowCapture.cs') -ReferencedAssemblies System.Drawing
    $win = Get-GameWindow
    if (-not $win) { throw 'no game window' }
    $dir = 'C:\KenshiTestRuns\shots'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $path = if ($Save) { Join-Path $dir "$Save.png" } else { Join-Path $dir ("shot-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.png') }
    $size = [KenshiCapture]::Save($win.Handle, $path, 1600)
    "$path ($size)"
  }
  default { throw "unknown command: $Command" }
}
