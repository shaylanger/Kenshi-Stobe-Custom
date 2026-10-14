<#
.SYNOPSIS
  Fail-closed placement helper for the private 5090b/5090c Kenshi windows.
.DESCRIPTION
  This file is intentionally separate from rig launch/ownership code. It does not
  launch, stop, focus, click, type into, or otherwise own a game process. -Apply
  moves both already-running private instance windows as one checked operation.
  Run -SelfTest for synthetic-only validation; it does not inspect or change host
  windows.

  Slots were approved for DISPLAY1 (Sony), observed at (-4480,360) 1920x1080:
    instance 2 / 5090b: (-4480,360) 800x600
    instance 3 / 5090c: (-3680,360) 800x600
  The main instance remains at (-2560,0) 1600x900 on DISPLAY2. DISPLAY3 (Samsung)
  is forbidden. Any display-layout drift, identity uncertainty, or neighbor
  overlap is a hard failure. See rig5090-window-slots-restore.md for restoration.

  Usage after separate review and sole-operator activation only:
    .\rig5090-window-slots.ps1 -Apply -Instance2Pid <pid> -Instance3Pid <pid>
    .\rig5090-window-slots.ps1 -SelfTest
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Restore,
  [switch]$SelfTest,
  [int]$Instance2Pid = 0,
  [int]$Instance3Pid = 0
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$RestoreFile = 'C:\KenshiTestRuns\rig5090-window-slots.restore.json'

function Get-SlotLayout([int]$left, [int]$top, [int]$width, [int]$height) {
  [pscustomobject]@{
    Display = '\\.\DISPLAY1'
    DisplayBounds = [pscustomobject]@{ L=$left; T=$top; R=($left+$width); B=($top+$height) }
    Slots = @(
      [pscustomobject]@{ Instance=2; Pid=0; Rect=[pscustomobject]@{ L=$left; T=$top; R=($left+800); B=($top+600) } },
      [pscustomobject]@{ Instance=3; Pid=0; Rect=[pscustomobject]@{ L=($left+800); T=$top; R=($left+1600); B=($top+600) } }
    )
  }
}
function Test-RectOverlap($a, $b) {
  return ($a.L -lt $b.R -and $a.R -gt $b.L -and $a.T -lt $b.B -and $a.B -gt $b.T)
}
function Test-RectContained($outer, $inner) {
  return ($inner.L -ge $outer.L -and $inner.T -ge $outer.T -and $inner.R -le $outer.R -and $inner.B -le $outer.B)
}
function Test-LayoutData($layout, $protected, $forbidden, $neighbors, $identity) {
  if ($null -eq $layout -or @($layout.Slots).Count -ne 2) { return 'layout must contain exactly two slots' }
  $a = $layout.Slots[0].Rect; $b = $layout.Slots[1].Rect
  if ((Test-RectOverlap $a $b)) { return 'target slots overlap' }
  foreach ($s in $layout.Slots) {
    if (-not (Test-RectContained $layout.DisplayBounds $s.Rect)) { return "instance $($s.Instance) slot is outside DISPLAY1" }
    if ($null -ne $protected -and (Test-RectOverlap $s.Rect $protected)) { return "instance $($s.Instance) slot overlaps protected i1 window" }
    if ($null -ne $forbidden -and (Test-RectOverlap $s.Rect $forbidden)) { return "instance $($s.Instance) slot overlaps forbidden DISPLAY3" }
    foreach ($n in @($neighbors)) {
      if ($null -ne $n -and $n.Visible -and (Test-RectOverlap $s.Rect $n.Rect)) { return "instance $($s.Instance) slot overlaps unrelated window pid=$($n.Pid)" }
    }
  }
  if (@($identity).Count -ne 2) { return 'exactly two target identities are required' }
  foreach ($i in $identity) {
    if (-not $i.PathExact) { return "instance $($i.Instance) executable path mismatch" }
    if (-not $i.PidExact) { return "instance $($i.Instance) pid/window identity mismatch" }
    if (-not $i.TitleExact) { return "instance $($i.Instance) title instance marker mismatch" }
    if (-not $i.HandleValid) { return "instance $($i.Instance) main window handle is invalid" }
  }
  return ''
}
function Test-RestoreEntry($entry, [int]$instance, $expectedTarget, $displays, $protected, $neighbors=@()) {
  if ($null -eq $entry -or $null -eq $entry.Original -or $null -eq $entry.Target) { return "instance $instance restore receipt missing bounds" }
  if ($null -eq $entry.Instance -or [int]$entry.Instance -ne $instance) { return "instance $instance restore receipt instance mismatch" }
  try {
    $o=[pscustomobject]@{ L=[int]$entry.Original.L; T=[int]$entry.Original.T; R=[int]$entry.Original.R; B=[int]$entry.Original.B }
    $t=[pscustomobject]@{ L=[int]$entry.Target.L; T=[int]$entry.Target.T; R=[int]$entry.Target.R; B=[int]$entry.Target.B }
  } catch { return "instance $instance restore receipt has nonnumeric bounds" }
  $ow=$o.R-$o.L; $oh=$o.B-$o.T
  if ($ow -lt 100 -or $oh -lt 100 -or $ow -gt 8192 -or $oh -gt 8192) { return "instance $instance original bounds have invalid dimensions" }
  foreach ($v in @($o.L,$o.T,$o.R,$o.B)) { if ($v -lt -32768 -or $v -gt 32767) { return "instance $instance original bounds exceed coordinate limits" } }
  if ($t.L -ne $expectedTarget.L -or $t.T -ne $expectedTarget.T -or $t.R -ne $expectedTarget.R -or $t.B -ne $expectedTarget.B) { return "instance $instance target bounds differ from approved slot" }
  if ($null -ne $protected -and (Test-RectOverlap $o $protected)) { return "instance $instance original bounds overlap protected i1" }
  foreach ($neighbor in @($neighbors)) { if ($null -ne $neighbor -and $neighbor.Visible -and (Test-RectOverlap $o $neighbor.Rect)) { return "instance $instance original bounds overlap unrelated window pid=$($neighbor.Pid)" } }
  if ($displays.ContainsKey('\\.\DISPLAY3') -and (Test-RectOverlap $o $displays['\\.\DISPLAY3'])) { return "instance $instance original bounds overlap forbidden DISPLAY3" }
  $contained=$false
  foreach ($name in $displays.Keys) { if ($name -ne '\\.\DISPLAY3' -and (Test-RectContained $displays[$name] $o)) { $contained=$true } }
  if (-not $contained) { return "instance $instance original bounds are outside allowed displays" }
  return ''
}

if ($SelfTest) {
  $l = Get-SlotLayout -4480 360 1920 1080
  $i = @(
    [pscustomobject]@{ Instance=2; PathExact=$true; PidExact=$true; TitleExact=$true; HandleValid=$true },
    [pscustomobject]@{ Instance=3; PathExact=$true; PidExact=$true; TitleExact=$true; HandleValid=$true }
  )
  $protected = [pscustomobject]@{ L=-2560; T=0; R=-960; B=900 }
  $forbidden = [pscustomobject]@{ L=0; T=0; R=1920; B=1080 }
  $tests = @()
  $fakeDisplays = @{ '\\.\DISPLAY1'=[pscustomobject]@{ L=-4480; T=360; R=-2560; B=1440 }; '\\.\DISPLAY2'=$protected; '\\.\DISPLAY3'=$forbidden }
  $goodOriginal = [pscustomobject]@{ L=-4400; T=400; R=-3600; B=1000 }
  $entry2 = [pscustomobject]@{ Instance=2; Original=$goodOriginal; Target=$l.Slots[0].Rect }
  $tests += [pscustomobject]@{ Name='valid restore entry'; Got=(Test-RestoreEntry $entry2 2 $l.Slots[0].Rect $fakeDisplays $protected @()); Want='' }
  $wrongTarget = [pscustomobject]@{ Instance=2; Original=$goodOriginal; Target=[pscustomobject]@{ L=-4400; T=360; R=-3600; B=960 } }
  $tests += [pscustomobject]@{ Name='tampered restore target'; Got=(Test-RestoreEntry $wrongTarget 2 $l.Slots[0].Rect $fakeDisplays $protected @()); Want='instance 2 target bounds differ from approved slot' }
  $offscreen = [pscustomobject]@{ Instance=2; Original=[pscustomobject]@{ L=9000; T=0; R=9800; B=600 }; Target=$l.Slots[0].Rect }
  $tests += [pscustomobject]@{ Name='offscreen restore original'; Got=(Test-RestoreEntry $offscreen 2 $l.Slots[0].Rect $fakeDisplays $protected @()); Want='instance 2 original bounds are outside allowed displays' }
  $onI1 = [pscustomobject]@{ Instance=2; Original=$protected; Target=$l.Slots[0].Rect }
  $tests += [pscustomobject]@{ Name='protected i1 restore original'; Got=(Test-RestoreEntry $onI1 2 $l.Slots[0].Rect $fakeDisplays $protected @()); Want='instance 2 original bounds overlap protected i1' }
  $restoreNeighbor=@([pscustomobject]@{ Pid=555; Visible=$true; Rect=$goodOriginal })
  $tests += [pscustomobject]@{ Name='restore neighbor overlap'; Got=(Test-RestoreEntry $entry2 2 $l.Slots[0].Rect $fakeDisplays $protected $restoreNeighbor); Want='instance 2 original bounds overlap unrelated window pid=555' }
  $tests += [pscustomobject]@{ Name='approved two-slot layout'; Got=(Test-LayoutData $l $protected $forbidden @() $i); Want='' }
  $tests += [pscustomobject]@{ Name='missing DISPLAY1 layout'; Got=(Test-LayoutData $null $protected $forbidden @() $i); Want='layout must contain exactly two slots' }
  $bad = Get-SlotLayout -4480 360 1920 1080; $bad.Slots[1].Rect.L = -3700
  $tests += [pscustomobject]@{ Name='overlapping target slots'; Got=(Test-LayoutData $bad $protected $forbidden @() $i); Want='target slots overlap' }
  $bad = Get-SlotLayout -4480 360 1500 1080
  $tests += [pscustomobject]@{ Name='out-of-display slot'; Got=(Test-LayoutData $bad $protected $forbidden @() $i); Want='instance 3 slot is outside DISPLAY1' }
  $bad = Get-SlotLayout -4480 360 4000 1080; $bad.Slots[1].Rect.L = -2500; $bad.Slots[1].Rect.R = -1700
  $tests += [pscustomobject]@{ Name='protected i1 overlap'; Got=(Test-LayoutData $bad $protected $forbidden @() $i); Want='instance 3 slot overlaps protected i1 window' }
  $neighbor = @([pscustomobject]@{ Pid=555; Visible=$true; Rect=[pscustomobject]@{ L=-4470; T=370; R=-4400; B=440 } })
  $tests += [pscustomobject]@{ Name='unrelated neighbor overlap'; Got=(Test-LayoutData $l $protected $forbidden $neighbor $i); Want='instance 2 slot overlaps unrelated window pid=555' }
  $tests += [pscustomobject]@{ Name='wrong instance executable'; Got=(Test-LayoutData $l $protected $forbidden @() @($i[0],([pscustomobject]@{ Instance=3; PathExact=$false; PidExact=$true; TitleExact=$true; HandleValid=$true }))); Want='instance 3 executable path mismatch' }
  $tests += [pscustomobject]@{ Name='wrong PID/window identity'; Got=(Test-LayoutData $l $protected $forbidden @() @($i[0],([pscustomobject]@{ Instance=3; PathExact=$true; PidExact=$false; TitleExact=$true; HandleValid=$true }))); Want='instance 3 pid/window identity mismatch' }
  $tests += [pscustomobject]@{ Name='wrong title instance marker'; Got=(Test-LayoutData $l $protected $forbidden @() @($i[0],([pscustomobject]@{ Instance=3; PathExact=$true; PidExact=$true; TitleExact=$false; HandleValid=$true }))); Want='instance 3 title instance marker mismatch' }
  $tests += [pscustomobject]@{ Name='invalid target window handle'; Got=(Test-LayoutData $l $protected $forbidden @() @($i[0],([pscustomobject]@{ Instance=3; PathExact=$true; PidExact=$true; TitleExact=$true; HandleValid=$false }))); Want='instance 3 main window handle is invalid' }
  $tests += [pscustomobject]@{ Name='forbidden Samsung overlap'; Got=(Test-LayoutData $l $protected ([pscustomobject]@{ L=-4000; T=300; R=-3500; B=800 }) @() $i); Want='instance 2 slot overlaps forbidden DISPLAY3' }
  $failed = @($tests | Where-Object { $_.Got -ne $_.Want })
  if ($failed.Count) { "RESULT RIG5090-WINDOW-SLOTS-SELFTEST FAIL cases=$($tests.Count) failed=$($failed.Count) first='$($failed[0].Name): got='$($failed[0].Got)' want='$($failed[0].Want)'"; exit 1 }
  "RESULT RIG5090-WINDOW-SLOTS-SELFTEST PASS cases=$($tests.Count) host_windows=untouched"; exit 0
}

if (($Apply -and $Restore) -or (-not $Apply -and -not $Restore)) { 'RESULT RIG5090-WINDOW-SLOTS FAIL setup: specify exactly one of -SelfTest, -Apply, or -Restore'; exit 2 }
if ($Instance2Pid -le 0 -or $Instance3Pid -le 0 -or $Instance2Pid -eq $Instance3Pid) {
  'RESULT RIG5090-WINDOW-SLOTS FAIL setup: two distinct positive target PIDs are required'; exit 2
}

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Rig5090SlotsNative {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONITORINFOEX { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szDevice; }
  public delegate bool MonitorEnum(IntPtr h, IntPtr dc, IntPtr r, IntPtr data);
  public delegate bool WindowEnum(IntPtr h, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnum cb, IntPtr data);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfoW(IntPtr h, ref MONITORINFOEX i);
  [DllImport("user32.dll")] public static extern bool EnumWindows(WindowEnum cb, IntPtr data);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint flags);
}
'@

function RectObject($r) { [pscustomobject]@{ L=$r.Left; T=$r.Top; R=$r.Right; B=$r.Bottom } }
function Get-DisplaySnapshot {
  $found = @{}
  $cb = [Rig5090SlotsNative+MonitorEnum]{ param($h,$dc,$r,$d)
    $mi = New-Object Rig5090SlotsNative+MONITORINFOEX; $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
    if ([Rig5090SlotsNative]::GetMonitorInfoW($h,[ref]$mi)) { $found[$mi.szDevice] = RectObject $mi.rcMonitor }
    return $true
  }
  if (-not [Rig5090SlotsNative]::EnumDisplayMonitors([IntPtr]::Zero,[IntPtr]::Zero,$cb,[IntPtr]::Zero)) { throw 'EnumDisplayMonitors failed' }
  return $found
}
function Get-WindowText([IntPtr]$h) { $b=New-Object Text.StringBuilder 512; [void][Rig5090SlotsNative]::GetWindowTextW($h,$b,$b.Capacity); $b.ToString() }
function Get-WindowClass([IntPtr]$h) { $b=New-Object Text.StringBuilder 256; [void][Rig5090SlotsNative]::GetClassNameW($h,$b,$b.Capacity); $b.ToString() }
function Get-VisibleNeighborWindows([int[]]$ignorePids) {
  $list = New-Object 'System.Collections.Generic.List[object]'
  $cb = [Rig5090SlotsNative+WindowEnum]{ param($h,$d)
    if (-not [Rig5090SlotsNative]::IsWindowVisible($h) -or [Rig5090SlotsNative]::GetWindow($h,4) -ne [IntPtr]::Zero) { return $true }
    [uint32]$wpid=0; [void][Rig5090SlotsNative]::GetWindowThreadProcessId($h,[ref]$wpid)
    if ($ignorePids -contains [int]$wpid) { return $true }
    if ((Get-WindowClass $h) -in @('Progman','WorkerW','Shell_TrayWnd','NotifyIconOverflowWindow')) { return $true }
    $wr=New-Object Rig5090SlotsNative+RECT
    if ([Rig5090SlotsNative]::GetWindowRect($h,[ref]$wr)) { [void]$list.Add([pscustomobject]@{ Pid=[int]$wpid; Title=(Get-WindowText $h); Rect=(RectObject $wr); Visible=$true }) }
    return $true
  }
  if (-not [Rig5090SlotsNative]::EnumWindows($cb,[IntPtr]::Zero)) { throw 'EnumWindows failed' }
  return $list.ToArray()
}
function Get-TargetIdentity([int]$pid,[int]$instance) {
  $root = "D:\KenshiInst\$instance"
  $expected = [IO.Path]::GetFullPath((Join-Path $root 'kenshi_x64.exe'))
  $p = Get-Process -Id $pid -ErrorAction Stop
  if (-not $p.Path) { throw "instance $instance PID $pid executable path unavailable" }
  $actual = [IO.Path]::GetFullPath($p.Path)
  $pathExact = [string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase)
  if (-not $pathExact) { throw "instance $instance PID $pid path mismatch actual='$actual' expected='$expected'" }
  $h = [IntPtr]$p.MainWindowHandle
  if ($h -eq [IntPtr]::Zero -or -not [Rig5090SlotsNative]::IsWindow($h) -or -not [Rig5090SlotsNative]::IsWindowVisible($h)) { throw "instance $instance PID $pid has no visible main window" }
  if ([Rig5090SlotsNative]::GetWindow($h,4) -ne [IntPtr]::Zero) { throw "instance $instance HWND is owned, not a top-level game window" }
  [uint32]$actualPid = 0; [void][Rig5090SlotsNative]::GetWindowThreadProcessId($h,[ref]$actualPid)
  if ($actualPid -ne [uint32]$pid) { throw "instance $instance HWND PID mismatch actual=$actualPid expected=$pid" }
  $title = Get-WindowText $h
  if ($title -notmatch ("\[i" + $instance + "\]$")) { throw "instance $instance window title lacks exact [i$instance] marker: '$title'" }
  [pscustomobject]@{ Instance=$instance; Pid=$pid; Handle=$h; Path=$actual; Title=$title; Rect=$null }
}
function Set-VerifiedRect($target,$rect) {
  $w=$rect.R-$rect.L; $h=$rect.B-$rect.T
  if ($w -le 0 -or $h -le 0) { throw "invalid bounds for instance $($target.Instance)" }
  if (-not [Rig5090SlotsNative]::SetWindowPos($target.Handle,[IntPtr]::Zero,$rect.L,$rect.T,$w,$h,[uint32](0x0004 -bor 0x0010 -bor 0x0400))) { throw "SetWindowPos failed for instance $($target.Instance)" }
  $actual=New-Object Rig5090SlotsNative+RECT
  if (-not [Rig5090SlotsNative]::GetWindowRect($target.Handle,[ref]$actual)) { throw "post-move GetWindowRect failed for instance $($target.Instance)" }
  if ($actual.Left -ne $rect.L -or $actual.Top -ne $rect.T -or $actual.Right -ne $rect.R -or $actual.Bottom -ne $rect.B) { throw "post-move bounds mismatch instance $($target.Instance)" }
}

$targets = @()
$moved = @()
try {
  if ($Restore) {
    if (-not (Test-Path -LiteralPath $RestoreFile -PathType Leaf)) { throw "restore receipt absent: $RestoreFile" }
    $saved = Get-Content -LiteralPath $RestoreFile -Raw | ConvertFrom-Json
    if ($saved.Version -ne 1 -or [int]$saved.Instance2.Pid -ne $Instance2Pid -or [int]$saved.Instance3.Pid -ne $Instance3Pid) { throw 'restore receipt version or PID pair mismatch' }
    $restoreDisplays = Get-DisplaySnapshot
    $restoreD1 = $restoreDisplays['\\.\DISPLAY1']
    $restoreD3 = $restoreDisplays['\\.\DISPLAY3']
    if ($null -eq $restoreD1 -or $restoreD1.L -ne -4480 -or $restoreD1.T -ne 360 -or $restoreD1.R -ne -2560 -or $restoreD1.B -ne 1440) { throw 'required Sony DISPLAY1 bounds absent or changed; refusing restore' }
    $restoreLayout=Get-SlotLayout -4480 360 1920 1080
    $restoreProtected=[pscustomobject]@{ L=-2560; T=0; R=-960; B=900 }
    $entryCheck=Test-RestoreEntry $saved.Instance2 2 $restoreLayout.Slots[0].Rect $restoreDisplays $restoreProtected @()
    if ($entryCheck) { throw $entryCheck }
    $entryCheck=Test-RestoreEntry $saved.Instance3 3 $restoreLayout.Slots[1].Rect $restoreDisplays $restoreProtected @()
    if ($entryCheck) { throw $entryCheck }
    $targets = @((Get-TargetIdentity $Instance2Pid 2),(Get-TargetIdentity $Instance3Pid 3))
    $restoreNeighbors=Get-VisibleNeighborWindows @($Instance2Pid,$Instance3Pid)
    foreach ($target in $targets) {
      $entry = if ($target.Instance -eq 2) { $saved.Instance2 } else { $saved.Instance3 }
      if ([string]$entry.Handle -ne $target.Handle.ToInt64().ToString() -or -not [string]::Equals([string]$entry.Path,$target.Path,[StringComparison]::OrdinalIgnoreCase) -or [string]$entry.Title -ne $target.Title) { throw "instance $($target.Instance) no longer matches restore receipt" }
      $cur=New-Object Rig5090SlotsNative+RECT
      if (-not [Rig5090SlotsNative]::GetWindowRect($target.Handle,[ref]$cur)) { throw "pre-restore GetWindowRect failed for instance $($target.Instance)" }
      $atTarget = $cur.Left -eq [int]$entry.Target.L -and $cur.Top -eq [int]$entry.Target.T -and $cur.Right -eq [int]$entry.Target.R -and $cur.Bottom -eq [int]$entry.Target.B
      $atOriginal = $cur.Left -eq [int]$entry.Original.L -and $cur.Top -eq [int]$entry.Original.T -and $cur.Right -eq [int]$entry.Original.R -and $cur.Bottom -eq [int]$entry.Original.B
      if (-not $atTarget -and -not $atOriginal) { throw "instance $($target.Instance) moved since placement; refusing stale restore" }
      $target.Rect=[pscustomobject]@{ L=[int]$entry.Original.L; T=[int]$entry.Original.T; R=[int]$entry.Original.R; B=[int]$entry.Original.B }
      if ($null -ne $restoreD3 -and (Test-RectOverlap $target.Rect $restoreD3)) { throw "saved original rect for instance $($target.Instance) intersects forbidden DISPLAY3 (Samsung)" }
      foreach ($neighbor in $restoreNeighbors) { if (Test-RectOverlap $target.Rect $neighbor.Rect) { throw "saved original rect for instance $($target.Instance) overlaps unrelated window pid=$($neighbor.Pid)" } }
      $target.OriginalRect=[pscustomobject]@{ L=$cur.Left; T=$cur.Top; R=$cur.Right; B=$cur.Bottom }
      $moved += $target
      Set-VerifiedRect $target $target.Rect
    }
    Remove-Item -LiteralPath $RestoreFile -Force
    "RESULT RIG5090-WINDOW-SLOTS PASS mode=restore i2_pid=$Instance2Pid i2_bounds=$($targets[0].Rect.L),$($targets[0].Rect.T)-$($targets[0].Rect.R),$($targets[0].Rect.B) i3_pid=$Instance3Pid i3_bounds=$($targets[1].Rect.L),$($targets[1].Rect.T)-$($targets[1].Rect.R),$($targets[1].Rect.B)"
    exit 0
  }
  $displays = Get-DisplaySnapshot
  $d1 = $displays['\\.\DISPLAY1']; $d3 = $displays['\\.\DISPLAY3']
  if ($null -eq $d1) { throw 'required Sony DISPLAY1 is absent' }
  $expectedD1 = [pscustomobject]@{ L=-4480; T=360; R=-2560; B=1440 }
  if ($d1.L -ne $expectedD1.L -or $d1.T -ne $expectedD1.T -or $d1.R -ne $expectedD1.R -or $d1.B -ne $expectedD1.B) {
    throw "DISPLAY1 bounds drift: observed $($d1.L),$($d1.T)-$($d1.R),$($d1.B); required -4480,360--2560,1440"
  }
  $layout = Get-SlotLayout $d1.L $d1.T ($d1.R-$d1.L) ($d1.B-$d1.T)
  $protected = [pscustomobject]@{ L=-2560; T=0; R=-960; B=900 }
  if ((Test-RectOverlap $layout.Slots[0].Rect $protected) -or (Test-RectOverlap $layout.Slots[1].Rect $protected)) { throw 'planned slots overlap protected i1 window bounds' }
  if ($null -ne $d3 -and ((Test-RectOverlap $layout.Slots[0].Rect $d3) -or (Test-RectOverlap $layout.Slots[1].Rect $d3))) { throw 'planned slots overlap forbidden DISPLAY3 (Samsung)' }
  $targets = @((Get-TargetIdentity $Instance2Pid 2),(Get-TargetIdentity $Instance3Pid 3))
  $targetPids = @($Instance2Pid,$Instance3Pid)
  $neighborList = New-Object 'System.Collections.Generic.List[object]'
  $wcb = [Rig5090SlotsNative+WindowEnum]{ param($h,$d)
    if (-not [Rig5090SlotsNative]::IsWindowVisible($h) -or [Rig5090SlotsNative]::GetWindow($h,4) -ne [IntPtr]::Zero) { return $true }
    [uint32]$wpid=0; [void][Rig5090SlotsNative]::GetWindowThreadProcessId($h,[ref]$wpid)
    if ($targetPids -contains [int]$wpid) { return $true }
    $cls=Get-WindowClass $h
    if ($cls -in @('Progman','WorkerW','Shell_TrayWnd','NotifyIconOverflowWindow')) { return $true }
    $wr=New-Object Rig5090SlotsNative+RECT
    if ([Rig5090SlotsNative]::GetWindowRect($h,[ref]$wr)) { [void]$neighborList.Add([pscustomobject]@{ Pid=[int]$wpid; Title=(Get-WindowText $h); Rect=(RectObject $wr); Visible=$true }) }
    return $true
  }
  if (-not [Rig5090SlotsNative]::EnumWindows($wcb,[IntPtr]::Zero)) { throw 'EnumWindows failed' }
  $verdict = Test-LayoutData $layout $protected $d3 @($neighborList) @(
    [pscustomobject]@{ Instance=2; PathExact=$true; PidExact=$true; TitleExact=$true; HandleValid=$true },
    [pscustomobject]@{ Instance=3; PathExact=$true; PidExact=$true; TitleExact=$true; HandleValid=$true }
  )
  if ($verdict) { throw $verdict }
  foreach ($s in $layout.Slots) {
    $target = @($targets | Where-Object { $_.Instance -eq $s.Instance })[0]
    $target.Rect = $s.Rect
    $old = New-Object Rig5090SlotsNative+RECT
    if (-not [Rig5090SlotsNative]::GetWindowRect($target.Handle,[ref]$old)) { throw "pre-move GetWindowRect failed for instance $($target.Instance)" }
    $target.OriginalRect = RectObject $old
    $entryCheck=Test-RestoreEntry ([pscustomobject]@{ Instance=$target.Instance; Original=$target.OriginalRect; Target=$target.Rect }) $target.Instance $target.Rect $displays $protected @()
    if ($entryCheck) { throw "current instance $($target.Instance) bounds are not safely restorable: $entryCheck" }
  }
  $restoreDir = Split-Path -Parent $RestoreFile
  if (-not (Test-Path -LiteralPath $restoreDir -PathType Container)) { throw "restore receipt directory absent: $restoreDir" }
  if (Test-Path -LiteralPath $RestoreFile) { throw "an earlier restore receipt already exists: $RestoreFile; restore it before another placement" }
  $receipt = [pscustomobject]@{
    Version=1; CreatedUtc=[DateTime]::UtcNow.ToString('o')
    Instance2=[pscustomobject]@{ Instance=2; Pid=$targets[0].Pid; Handle=$targets[0].Handle.ToInt64().ToString(); Path=$targets[0].Path; Title=$targets[0].Title; Original=$targets[0].OriginalRect; Target=$targets[0].Rect }
    Instance3=[pscustomobject]@{ Instance=3; Pid=$targets[1].Pid; Handle=$targets[1].Handle.ToInt64().ToString(); Path=$targets[1].Path; Title=$targets[1].Title; Original=$targets[1].OriginalRect; Target=$targets[1].Rect }
  }
  $receiptTemp = "$RestoreFile.$PID.tmp"
  ConvertTo-Json -InputObject $receipt -Depth 6 | Set-Content -LiteralPath $receiptTemp -Encoding UTF8
  Move-Item -LiteralPath $receiptTemp -Destination $RestoreFile
  # SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSENDCHANGING. No foreground/input APIs.
  $flags = [uint32](0x0004 -bor 0x0010 -bor 0x0400)
  foreach ($target in $targets) {
    $r=$target.Rect
    $moved += $target
    if (-not [Rig5090SlotsNative]::SetWindowPos($target.Handle,[IntPtr]::Zero,$r.L,$r.T,800,600,$flags)) { throw "SetWindowPos failed for instance $($target.Instance)" }
    $actual=New-Object Rig5090SlotsNative+RECT
    if (-not [Rig5090SlotsNative]::GetWindowRect($target.Handle,[ref]$actual)) { throw "post-move GetWindowRect failed for instance $($target.Instance)" }
    if ($actual.Left -ne $r.L -or $actual.Top -ne $r.T -or $actual.Right -ne $r.R -or $actual.Bottom -ne $r.B) {
      throw "post-move bounds mismatch instance $($target.Instance): $($actual.Left),$($actual.Top)-$($actual.Right),$($actual.Bottom) expected $($r.L),$($r.T)-$($r.R),$($r.B)"
    }
  }
  "RESULT RIG5090-WINDOW-SLOTS PASS i2_pid=$Instance2Pid i2_bounds=-4480,360--3680,960 i3_pid=$Instance3Pid i3_bounds=-3680,360--2880,960 display=DISPLAY1 noactivate=1"
  exit 0
} catch {
  $rollback = 'none-needed'
  if ($moved.Count -gt 0) {
    $rollback = 'pass'
    foreach ($target in @($moved | Sort-Object Instance -Descending)) {
      try {
        $o=$target.OriginalRect; $w=$o.R-$o.L; $h=$o.B-$o.T
        if (-not [Rig5090SlotsNative]::SetWindowPos($target.Handle,[IntPtr]::Zero,$o.L,$o.T,$w,$h,[uint32](0x0004 -bor 0x0010 -bor 0x0400))) { $rollback='fail'; continue }
        $actual=New-Object Rig5090SlotsNative+RECT
        if (-not [Rig5090SlotsNative]::GetWindowRect($target.Handle,[ref]$actual) -or $actual.Left -ne $o.L -or $actual.Top -ne $o.T -or $actual.Right -ne $o.R -or $actual.Bottom -ne $o.B) { $rollback='fail' }
      } catch { $rollback='fail' }
    }
    if ($Apply -and $rollback -eq 'pass' -and (Test-Path -LiteralPath $RestoreFile)) { Remove-Item -LiteralPath $RestoreFile -Force }
  }
  "RESULT RIG5090-WINDOW-SLOTS FAIL setup: $($_.Exception.Message) rollback=$rollback"
  exit 1
}
