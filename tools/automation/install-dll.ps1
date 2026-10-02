<#
install-dll.ps1 Stobe|KenshiFP: install the freshly built DLL (Kenshi must be closed).

  Stobe     C:\StobeBuild\out\Stobe.dll  -> Kenshi\mods\Stobe\Stobe.dll
  KenshiFP  WSL /root/KenshiFP/re_plugin/KenshiFP.dll -> the Vortex KenshiFP folder

No backup copies: git is the history. Prints old and new SHA256 (first 8).
#>
param([Parameter(Mandatory = $true, Position = 0)][ValidateSet('Stobe', 'KenshiFP')][string]$Component)
$ErrorActionPreference = 'Stop'

$targets = @{
  'Stobe'    = @('C:\StobeBuild\out\Stobe.dll',
                 'D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll')
  'KenshiFP' = @('\\wsl.localhost\DwemerAI4Skyrim3\root\KenshiFP\re_plugin\KenshiFP.dll',
                 'C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll')
}
$src, $dst = $targets[$Component]

if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { throw 'Kenshi is running: close it first (kenshi-ctl.ps1 stop)' }
if (-not (Test-Path $src)) { throw "no build at $src" }
if (-not (Test-Path $dst)) { throw "install target missing: $dst" }

$old = (Get-FileHash $dst).Hash.Substring(0, 8)
$new = (Get-FileHash $src).Hash.Substring(0, 8)
if ($old -eq $new) { "$Component already installed: $new"; exit 0 }
Copy-Item $src $dst -Force
$check = (Get-FileHash $dst).Hash.Substring(0, 8)
if ($check -ne $new) { throw "hash mismatch after copy: $check != $new" }
"$Component installed: $old -> $new"
