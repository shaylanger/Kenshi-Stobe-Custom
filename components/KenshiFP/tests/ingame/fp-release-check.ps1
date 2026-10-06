<#
fp-release-check.ps1 (S05-BUILD): is the installed KenshiFP the release build with release config?
Runs on both rigs (Kenshi may be running). Checks: KenshiFP.dll SHA256 starts with -Hash, KenshiFP.ini and
RE_Kenshi.json present, no ini line turns manual combat on, KenshiFP.mod listed in data\mods.cfg.
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File fp-release-check.ps1 -Hash FE26573F [-ModDir <dir>] [-KenshiDir <dir>]
Prints one line: RESULT S05-BUILD PASS|FAIL <evidence>
#>
param([Parameter(Mandatory = $true)][string]$Hash, [string]$ModDir = '', [string]$KenshiDir = '')
$ErrorActionPreference = 'Stop'
if (-not $KenshiDir) {
  $KenshiDir = @('D:\Steam\steamapps\common\Kenshi', 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi') |
    Where-Object { Test-Path "$_\kenshi_x64.exe" } | Select-Object -First 1
}
if (-not $ModDir) {
  $ModDir = @('C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP',
              "$KenshiDir\mods\KenshiFP") | Where-Object { Test-Path "$_\KenshiFP.dll" } | Select-Object -First 1
}
$fail = @(); $ev = @()
if (-not $ModDir) { "RESULT S05-BUILD FAIL no KenshiFP.dll found (KenshiDir=$KenshiDir)"; exit 1 }
$h = (Get-FileHash "$ModDir\KenshiFP.dll").Hash.Substring(0, 8)
$ev += "dll=$h"; if ($h -ne $Hash.Substring(0, 8).ToUpper()) { $fail += "hash $h != $Hash" }
foreach ($f in 'KenshiFP.ini', 'RE_Kenshi.json') { if (-not (Test-Path "$ModDir\$f")) { $fail += "missing $f" } }
if (Test-Path "$ModDir\KenshiFP.ini") {
  $on = Select-String -Path "$ModDir\KenshiFP.ini" -Pattern '^\s*(manual_combat|combat_enabled|combat_manual|manual_ownership)\s*=\s*[1-9]' |
    ForEach-Object { $_.Line.Trim() }
  if ($on) { $fail += "ini enables manual combat: $($on -join ';')" } else { $ev += 'manual_combat=off' }
}
$cfg = "$KenshiDir\data\mods.cfg"
if (-not (Test-Path $cfg)) { $fail += "no $cfg" }
elseif (-not (Select-String -Path $cfg -Pattern '^\s*KenshiFP\.mod\s*$' -Quiet)) { $fail += 'KenshiFP.mod not in mods.cfg' }
else { $ev += 'mods.cfg=KenshiFP.mod' }
if ($fail) { "RESULT S05-BUILD FAIL $($fail -join '; ') ($($ev -join ' ')) dir=$ModDir"; exit 1 }
"RESULT S05-BUILD PASS $($ev -join ' ') ini+RE_Kenshi.json present dir=$ModDir"
