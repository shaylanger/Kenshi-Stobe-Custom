<#
install-dll.ps1 Stobe|KenshiFP|Harness|ProfessionGear: install the freshly built DLL (Kenshi must be closed).

  Stobe     C:\StobeBuild\out\Stobe.dll  -> Kenshi\mods\Stobe\Stobe.dll
  KenshiFP  WSL /root/KenshiFP/re_plugin/KenshiFP.dll -> the Vortex KenshiFP folder
  ProfessionGear  Kenshi-Profession-Gear-Progression\out\ProfessionGearProgression.dll -> Kenshi\mods\ProfessionGearProgression\
  Harness   Kenshi-Automation-Harness\out\AutomationHarness.dll -> Kenshi\mods\AutomationHarness\

  KenshiFP -Staged [-Hash <sha8>]  THE build kfp-pipeline.sh staged (C:\KenshiTestRuns\staged\KenshiFP-latest.txt line 1; else the
                                     newest), or the named one: C:\KenshiTestRuns\staged\KenshiFP-<sha8>.dll
           -Rig 4080                 same on the 4080 over ssh (runs C:\KAH\inst-staged.ps1 there: C:\KAH\staged\KenshiFP-latest.txt)

No backup copies: git is the history. Prints old and new SHA256 (first 8).
#>
param([Parameter(Mandatory = $true, Position = 0)][ValidateSet('Stobe', 'KenshiFP', 'Harness', 'ProfessionGear')][string]$Component,
      [switch]$Staged, [string]$Hash = '', [ValidateSet('5090', '4080')][string]$Rig = '5090')
$ErrorActionPreference = 'Stop'

if ($Staged -or $Rig -eq '4080') {
  if ($Component -ne 'KenshiFP' -or -not $Staged) { throw '-Staged / -Rig 4080 are for KenshiFP staged builds only' }
  if ($Rig -eq '4080') {
    $a = if ($Hash) { " -Hash $Hash" } else { '' }
    & ssh 4080 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\inst-staged.ps1$a"
    if ($LASTEXITCODE -ne 0) { throw "4080 staged install failed (exit $LASTEXITCODE)" }
    exit 0
  }
  $f = Get-ChildItem 'C:\KenshiTestRuns\staged\KenshiFP-*.dll' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  # one build line: KenshiFP-latest.txt (written by kfp-pipeline.sh) names THE build; never pick by date when it exists
  if (-not $Hash -and (Test-Path 'C:\KenshiTestRuns\staged\KenshiFP-latest.txt')) { $Hash = ((Get-Content 'C:\KenshiTestRuns\staged\KenshiFP-latest.txt' -TotalCount 1) -split ' ')[1] }
  if ($Hash) { $f = $f | Where-Object { $_.BaseName -eq "KenshiFP-$($Hash.ToUpper())" } }
  $f = $f | Select-Object -First 1
  if (-not $f) { throw 'no staged KenshiFP build in C:\KenshiTestRuns\staged (run kfp-pipeline.sh)' }
  $want = $f.BaseName.Substring(9)
  if ((Get-FileHash $f.FullName).Hash.Substring(0, 8) -ne $want) { throw "staged file $($f.Name) does not match its name hash" }
  $stagedSrc = $f.FullName
}

$targets = @{
  'Stobe'    = @('C:\StobeBuild\out\Stobe.dll',
                 'D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll')
  'KenshiFP' = @('\\wsl.localhost\DwemerAI4Skyrim3\root\KenshiFP\re_plugin\KenshiFP.dll',
                 'C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll')
  'Harness'  = @('C:\KenshiModding\Kenshi-Automation-Harness\out\AutomationHarness.dll',
                 'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll')
  'ProfessionGear' = @('C:\KenshiModding\Kenshi-Profession-Gear-Progression\out\ProfessionGearProgression.dll',
                 'D:\Steam\steamapps\common\Kenshi\mods\ProfessionGearProgression\ProfessionGearProgression.dll')
}
$src, $dst = $targets[$Component]
if ($Staged) { $src = $stagedSrc }

# only instance 1's game blocks (multi-instance 2026-10-11): these targets belong to the Steam install; a test game of an
# install copy (D:\KenshiInst\<n>, rig-runner lane 5090b) holds its own DLL copies
if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike 'D:\KenshiInst\*' }) { throw 'Kenshi is running: close it first (kenshi-ctl.ps1 stop)' }
if (-not (Test-Path $src)) { throw "no build at $src" }
if (-not (Test-Path $dst)) { throw "install target missing: $dst" }

$old = (Get-FileHash $dst).Hash.Substring(0, 8)
$new = (Get-FileHash $src).Hash.Substring(0, 8)
if ($old -eq $new) { "$Component already installed: $new"; exit 0 }
Copy-Item $src $dst -Force
$check = (Get-FileHash $dst).Hash.Substring(0, 8)
if ($check -ne $new) { throw "hash mismatch after copy: $check != $new" }
"$Component installed: $old -> $new"
