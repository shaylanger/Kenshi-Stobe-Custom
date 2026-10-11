<#
kfp-fastswap.ps1: load a new KenshiFP build into the game in the fewest seconds (hotswap2, 2026-10-11).

  kfp-fastswap.ps1 [-Staged] [-Hash <sha8>] [-Dll <path>] [-Save <name> | -Keep] [-Instance n] [-Gfx full|low] [-NoInstall]

  -Staged / -Hash  the staged build (C:\KenshiTestRuns\staged\KenshiFP-latest.txt, or KenshiFP-<sha8>.dll); -Dll any file
  -Keep            the running game is saved first (harness `save kah-swap`, waits until the save folder settles) and the
                   new build comes up in exactly that state (positions, time, inventories; KenshiFP's own in-memory
                   state such as fp mode is NOT kept: re-enter it)
  -Save <name>     relaunch into that save instead (default: the save the harness says is loaded, else kah-fpxbow)
  -Instance n      a second test install (D:\KenshiInst\<n>, KAH_INSTANCE); default 1 = the Steam install
  -NoInstall       just the fast restart (measure / recover)
Prints one line per phase with seconds since start and ends with
  FASTSWAP OK total=<s> stop=<s> install=<s> menu=<s> world=<s> dll=<sha8> save=<name>   (or FASTSWAP FAIL <why>)

Why a fast restart and not an in-process DLL swap: KenshiFP hooks through KenshiLib::AddHook (no remove), runs its own
threads (DirectInput poll, hook watchdog) and D3D/dinput hooks; unloading code another thread may still be inside is
the 0xD1-at-a-freed-address class of the 2026-10-11 BSOD. A restart is the only swap that cannot execute freed code.
Speed comes from cutting waits instead: kill (no graceful exit), copy + SHA check, harness autoload (no menu clicks),
native 0.2 s polls on harness.log / outbox (no WSL client start-up), window re-place/fit running while the save loads.
Lock: kenshi-ctl.ps1 stop/launch take the game lock for $env:KAH_OWNER (default hotswap).
#>
param(
  [switch]$Staged, [string]$Hash = '', [string]$Dll = '',
  [string]$Save = '', [switch]$Keep, [int]$Instance = 1,
  [ValidateSet('', 'full', 'low')][string]$Gfx = '', [switch]$NoInstall, [int]$TimeoutSec = 180
)
$ErrorActionPreference = 'Stop'
$Ctl = 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1'
$K = if ($Instance -ge 2) { "D:\KenshiInst\$Instance" } else { 'D:\Steam\steamapps\common\Kenshi' }
$H = "$K\mods\AutomationHarness"
$SaveRoot = if ($Instance -ge 2) { "$K\save" } else { "$env:LOCALAPPDATA\kenshi\save" }
if (-not $env:KAH_OWNER) { $env:KAH_OWNER = 'hotswap' }
if ($Instance -ge 2) { $env:KAH_INSTANCE = "$Instance" } else { Remove-Item Env:KAH_INSTANCE -ErrorAction SilentlyContinue }
$sw = [Diagnostics.Stopwatch]::StartNew()
$T = [ordered]@{}
function Say([string]$m) { "{0,6:N1} {1}" -f $sw.Elapsed.TotalSeconds, $m }
function Mark([string]$k) { $T[$k] = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
# Foreground lock (bench 100, 2026-10-11): kenshi-ctl started by Start-Process below is a grandchild that may not take the
# lock ("foreground lock not taken"), and the game then took the foreground once. Take it here (this process has the same
# right as run-batch's kenshi-ctl) for the whole launch, release it on every exit.
Add-Type -Namespace KfpFs -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool LockSetForegroundWindow(uint c);' -ErrorAction SilentlyContinue
$script:fgLock = $false
function FgUnlock { if ($script:fgLock) { $null = [KfpFs.U]::LockSetForegroundWindow(2); $script:fgLock = $false } }
function Fail([string]$m) { FgUnlock; "FASTSWAP FAIL $m (after $([math]::Round($sw.Elapsed.TotalSeconds,1)) s)"; exit 1 }
function Procs { , @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object {
    if ($Instance -ge 2) { $_.ExecutablePath -like "$K\*" } else { -not $_.ExecutablePath -or $_.ExecutablePath -notlike 'D:\KenshiInst\*' } }) }

# --- native harness IPC (same protocol as client/kah.py: inbox.txt.lock, temp + rename, reply line in outbox.txt) ---
$script:n = 0
function Kah([string]$cmd, [double]$timeout = 10) {
  $inbox = "$H\inbox.txt"; $lock = "$inbox.lock"; $out = "$H\outbox.txt"
  $end = (Get-Date).AddSeconds($timeout)
  $start = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }
  $script:n++; $cid = "fs$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())_${PID}_$($script:n)"
  while ($true) {
    try { $fs = [IO.File]::Open($lock, 'CreateNew', 'Write'); $fs.Close(); break } catch { if ((Get-Date) -gt $end) { return $null }; Start-Sleep -Milliseconds 100 }
  }
  try {
    while (Test-Path $inbox) { if ((Get-Date) -gt $end) { return $null }; Start-Sleep -Milliseconds 100 }
    $tmp = "$inbox.$PID.$($script:n).tmp"
    [IO.File]::WriteAllText($tmp, "$cid`t$(($cmd -split ' ') -join "`t")`n")   # fields are tab-separated (kah.py): "save kah-swap" was one unknown command
    Move-Item $tmp $inbox -Force
  } finally { Remove-Item $lock -ErrorAction SilentlyContinue }
  while ((Get-Date) -lt $end) {
    if (Test-Path $out) {
      $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite,Delete')
      try {
        if ($fs.Length -lt $start) { $start = 0 }
        $null = $fs.Seek($start, 'Begin'); $txt = (New-Object IO.StreamReader($fs)).ReadToEnd()
      } finally { $fs.Close() }
      foreach ($l in ($txt -split "`n")) { $p = $l.TrimEnd("`r") -split "`t", 3; if ($p[0] -eq $cid -and $p.Count -eq 3) { return $p[2] } }
    }
    Start-Sleep -Milliseconds 200
  }
  $null
}
function HLog([string]$pat) { if (Test-Path "$H\harness.log") { Select-String -Path "$H\harness.log" -Pattern $pat -SimpleMatch | Select-Object -Last 1 } }

# --- 0. which build ---
$src = $null
if (-not $NoInstall) {
  if ($Dll) { $src = (Resolve-Path $Dll).Path }
  else {
    if (-not $Hash -and (Test-Path 'C:\KenshiTestRuns\staged\KenshiFP-latest.txt')) { $Hash = ((Get-Content 'C:\KenshiTestRuns\staged\KenshiFP-latest.txt' -TotalCount 1) -split ' ')[1] }
    if (-not $Hash) { Fail 'no -Dll and no staged build (KenshiFP-latest.txt)' }
    $src = "C:\KenshiTestRuns\staged\KenshiFP-$($Hash.ToUpper()).dll"
  }
  if (-not (Test-Path $src)) { Fail "no build at $src" }
}
$dst = "$K\mods\KenshiFP\KenshiFP.dll"
$di = Get-Item $dst -ErrorAction SilentlyContinue
if ($di -and $di.LinkType -eq 'SymbolicLink') { $dst = @($di.Target)[0] }   # instance 1: the Vortex mod folder file

# --- 1. keep the current state ---
$running = (Procs).Count -gt 0
if ($running) {
  $st = Kah 'status' 5
  if (-not $Save -and $st -match ' save=(\S+)' -and $Matches[1] -ne '?') { $Save = $Matches[1] }
  if ($Keep) {
    if ($st -notmatch 'phase=world') { Fail "-Keep: the game is not in the world ($st)" }
    $dir = Join-Path $SaveRoot 'kah-swap'; $t0 = Get-Date
    $r = Kah 'save kah-swap' 10
    if ($r -notmatch '^saving') { Fail "-Keep: save refused ($r)" }
    # the game writes the save on its own thread: done = folder written after the request and quiet for 1.5 s
    $quiet = $null
    while ($sw.Elapsed.TotalSeconds -lt 90) {
      $last = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($last -and $last.LastWriteTime -gt $t0) {
        if ($quiet -and $quiet -eq $last.LastWriteTime -and ((Get-Date) - $last.LastWriteTime).TotalSeconds -ge 1.5) { break }
        $quiet = $last.LastWriteTime
      }
      Start-Sleep -Milliseconds 250
    }
    if (-not $last -or $last.LastWriteTime -le $t0) { Fail "-Keep: save kah-swap never written to $dir" }
    $Save = 'kah-swap'; Mark 'save'; Say "saved current game as kah-swap"
  }
}
if (-not $Save) { $Save = 'kah-fpxbow' }

# --- 2. stop ---
if ($running) {
  $o = & $Ctl stop 2>&1 | Out-String
  if ((Procs).Count) { Fail "stop: game still running ($($o.Trim()))" }
}
Mark 'stop'; Say "stopped (was running: $running)"

# --- 3. install ---
$sha = if (Test-Path $dst) { (Get-FileHash $dst).Hash.Substring(0, 8) } else { '-' }
if ($src) {
  $new = (Get-FileHash $src).Hash.Substring(0, 8)
  if ($new -ne $sha) {
    Copy-Item $src $dst -Force
    $sha = (Get-FileHash $dst).Hash.Substring(0, 8)
    if ($sha -ne $new) { Fail "hash mismatch after copy: $sha != $new" }
    Say "KenshiFP installed $new -> $dst"
  } else { Say "KenshiFP already $new" }
}
Mark 'install'

# --- 4. launch (kenshi-ctl: windowed, background, isolation, autoload; its window re-place/fit tail runs while the save loads) ---
$la = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Ctl, 'launch', '-Save', $Save, '-TimeoutSec', "$TimeoutSec")
if ($Gfx) { $la += @('-Gfx', $Gfx) }
$logOut = "$env:TEMP\kfp-fastswap-$Instance.out"
# only this launch's harness.log counts (kenshi-ctl deletes it too, but the polls below start before it does)
Remove-Item "$H\harness.log" -ErrorAction SilentlyContinue
if (Test-Path "$H\harness.log") { Fail "old harness.log still held open ($H): is a game still running?" }
$script:fgLock = [KfpFs.U]::LockSetForegroundWindow(1); Say "foreground lock $(if ($script:fgLock) { 'ON' } else { 'not taken' })"
$p = Start-Process powershell -ArgumentList $la -NoNewWindow -PassThru -RedirectStandardOutput $logOut -RedirectStandardError "$logOut.err"
$null = $p.Handle   # cache the process handle: without it a -PassThru process reports ExitCode $null after it exits (read as a failure)
$hStart = $null; $menu = $false; $sig = $false
while ($true) {
  if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec + 30) { Fail "world not reached in $TimeoutSec s (launch log $logOut)" }
  if ($p.HasExited -and $null -ne $p.ExitCode -and $p.ExitCode -ne 0) { Fail "kenshi-ctl launch exit $($p.ExitCode): $((Get-Content $logOut -Tail 3) -join ' / ')" }
  if (-not $menu -and (HLog 'KAH: frame listener running')) { $menu = $true; Mark 'menu'; Say 'main menu up (harness frame listener)' }
  if ($menu -and -not $sig -and (HLog "game load signalled save=$Save")) { $sig = $true; Mark 'loadstart'; Say "loading $Save" }
  if ($sig) {
    $st = Kah 'status' 3
    if ($st -match 'phase=world' -and $st -match 'squad=[1-9]') { Mark 'world'; Say "in the world: $st"; break }
  }
  Start-Sleep -Milliseconds 200
}
# kenshi-ctl's tail (re-place x3 + render fit) normally ends about now; never leave it half done
if (-not $p.WaitForExit(45000)) { Say 'kenshi-ctl tail still running after 45 s: killing it, running postlaunch'; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$lo = (Get-Content $logOut -ErrorAction SilentlyContinue) -join "`n"
$pl = if ($p.HasExited -and $p.ExitCode -eq 0 -and $lo -match 'render size: \d+x\d+ ok \(') { "kenshi-ctl fit: $([regex]::Match($lo, 'render size: \d+x\d+ ok').Value)" } else { & $Ctl postlaunch 2>&1 | Out-String }
FgUnlock
Mark 'placed'
Say "window: $(($pl.Trim() -split "`n")[-1])"
if ($pl -match 'postlaunch FAIL') { Fail 'game window not at the Video Mode size (postlaunch FAIL)' }
$parts = ($T.Keys | ForEach-Object { "$_=$($T[$_])" }) -join ' '
"FASTSWAP OK total=$([math]::Round($sw.Elapsed.TotalSeconds,1)) $parts dll=$sha save=$Save instance=$Instance"
