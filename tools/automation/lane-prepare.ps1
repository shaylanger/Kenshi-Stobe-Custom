<#
lane-prepare.ps1 -Lane <i4> [-FromLane i3] [-FromSave <fixture save>] [-Defs <lane-defs json>] [-Force]   (runs ON the 4080, PowerShell 5, lane's game CLOSED)
Make an isolated 4080 test lane's Kenshi install ready to launch next to the other lane(s). The install copy itself comes from
`kenshi-instance.ps1 sync -Instance <n>` (junctions/hard links from the Steam install, own settings.cfg "User save location=0", own
mods\ runtime files); this script then does the lane-specific parts, all from lane-defs.4080.json:
  1. Stobe mod files: Stobe.dll copied from the source lane (-FromLane, default i3: the reviewed build that lane already runs; SHA256
     compared, no other DLL is touched), Stobe.ini / StobeCustom.ini ServerPort = the lane's php_port (ServerHost 127.0.0.1).
  2. Save: a fresh copy of fixture -FromSave (default kah-stobe-4080-standalone-active, taken from the source lane's save dir) as the
     lane's own save name (defs "save"); refuses to overwrite an existing one unless -Force.
  3. Window: C:\KenshiTestRuns\inst-window-<n>.pos = defs window_pos (inst-window.ps1 parks the lane's windows there, never activated), so
     the lane never lands on another lane's rect (inst-window defaults every lane >= 2 to 1920,0).
  4. Graphics: kcfg.ps1 test -Instance <n> -Gfx low  = windowed (Full Screen=No), tutorials=0, lowest graphics, Video Mode 1280x720
     (KAH_VIDEO_MODE), 60 fps cap (harness framecap.txt), per-install gfx.applied.
Prints one line per step and `RESULT lane-prepare <lane> PASS|FAIL <why>`; exit 1 on FAIL.
#>
param([Parameter(Mandatory = $true)][string]$Lane, [string]$FromLane = 'i3', [string]$FromSave = 'kah-stobe-4080-standalone-active',
      [string]$Defs = 'C:\KenshiTestRuns\lane-i4\lane-defs.4080.json', [switch]$Force)
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { "RESULT lane-prepare $Lane FAIL $m"; exit 1 }
$d = Get-Content $Defs -Raw | ConvertFrom-Json
$L = $d.lanes.$Lane; $S = $d.lanes.$FromLane
if (-not $L -or -not $S) { Fail "unknown lane in $Defs" }
if ("$($L.owner_note)" -notlike 'built by*') { Fail "lane $Lane is not owned by this tooling" }
$dir = $L.dir; $n = [int]$L.instance
if (-not (Test-Path "$dir\kenshi_x64.exe")) { Fail "no install at $dir (kenshi-instance.ps1 sync -Instance $n first)" }
$pre = $dir.TrimEnd('\') + '\'
if (@(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) }).Count) { Fail "lane $Lane game is running" }

# 1. Stobe files
$srcDll = "$($S.dir)\mods\Stobe\Stobe.dll"; $dstDll = "$dir\mods\Stobe\Stobe.dll"
if (-not (Test-Path $srcDll)) { Fail "no source Stobe.dll $srcDll" }
$h1 = (Get-FileHash $srcDll -Algorithm SHA256).Hash
if (-not (Test-Path $dstDll) -or (Get-FileHash $dstDll -Algorithm SHA256).Hash -ne $h1) { Copy-Item $srcDll $dstDll -Force }
$h2 = (Get-FileHash $dstDll -Algorithm SHA256).Hash
if ($h1 -ne $h2) { Fail "Stobe.dll hash mismatch after copy" }
"Stobe.dll $h2 (same as lane $FromLane)"
foreach ($ini in 'Stobe.ini', 'StobeCustom.ini') {
  $f = "$dir\RE_Kenshi\mods\Stobe\$ini"
  if (-not (Test-Path $f)) { $f2 = "$($S.dir)\RE_Kenshi\mods\Stobe\$ini"; if (Test-Path $f2) { New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; Copy-Item $f2 $f } else { continue } }
  $bom = ([IO.File]::ReadAllBytes($f) | Select-Object -First 1) -eq 0xEF; $raw = [IO.File]::ReadAllText($f)
  $new = [regex]::Replace($raw, '(?m)^ServerPort=\d+', "ServerPort=$($L.php_port)")
  $new = [regex]::Replace($new, '(?m)^ServerHost=.*', 'ServerHost=127.0.0.1')
  if ($new -ne $raw) { [IO.File]::WriteAllText($f, $new, (New-Object Text.UTF8Encoding($bom))) }
  "$ini -> ServerPort=$($L.php_port)"
}

# 1b. game-side activity-transport key = the lane's OWN server key (the synced copy is instance 1's key = lane i3's server key)
$keyTxt = ((& wsl.exe -d $d.wsl_distro -u root --cd / -- cat "$($L.backend_root)/activity-transport.key") -join '').Trim()
if ($keyTxt -notmatch '^[0-9a-f]{64}$') { Fail "cannot read the lane server's activity-transport.key ($($L.backend_root)); provision the backend first" }
$kf = "$dir\mods\Stobe\activity-transport.key"
if (Test-Path $kf) { Remove-Item $kf -Force }   # a hard link would only drop this name
[IO.File]::WriteAllText($kf, $keyTxt, (New-Object Text.ASCIIEncoding))
"activity-transport.key = lane server key (sha256 $((Get-FileHash $kf -Algorithm SHA256).Hash.Substring(0,12)))"

# 2. fixture save
$from = "$($S.dir)\save\$FromSave"; if (-not (Test-Path $from)) { $from = "$env:LOCALAPPDATA\kenshi\save\$FromSave" }
if (-not (Test-Path $from)) { Fail "no fixture save $FromSave" }
$to = "$dir\save\$($L.save)"
if ((Test-Path $to) -and -not $Force) { "save $($L.save) exists (kept; -Force to recreate)" }
else {
  $null = robocopy $from $to /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -ge 8) { Fail "robocopy of $FromSave failed ($LASTEXITCODE)" }
  "save $FromSave -> $to"
}

# 3. window rect
Set-Content "C:\KenshiTestRuns\inst-window-$n.pos" $L.window_pos -Encoding Ascii
"window park pos $($L.window_pos) ($($L.window_size))"

# 4. windowed + low graphics + 60 fps cap
$env:KAH_VIDEO_MODE = ($L.window_size -replace 'x', ' x ')
& C:\KAH\kcfg.ps1 test -Instance $n -Gfx low
"RESULT lane-prepare $Lane PASS dir=$dir save=$($L.save) port=$($L.php_port) window=$($L.window_pos) $($L.window_size) stobe=$($h2.Substring(0,8))"
