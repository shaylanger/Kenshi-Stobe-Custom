<#
kcfg.ps1 (4080 rig, C:\KAH\kcfg.ps1) test|play|status: kenshi.cfg render mode. Takes assume the 5090's windowed
1600x900 (render crops, sky strip); the 4080's own setting is full screen 1920x1080. test = save the current values to
C:\KenshiTestRuns\kenshi.cfg.play (once) and set Full Screen=No, Video Mode=1600 x 900; play = restore them. Kenshi closed.
#>
param([Parameter(Position = 0)][ValidateSet('test', 'play', 'status')][string]$Mode = 'status')
$cfg = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi\kenshi.cfg'; $save = 'C:\KenshiTestRuns\kenshi.cfg.play'
$keys = 'Full Screen', 'Video Mode'
$lines = Get-Content $cfg
function val($k) { ($lines | Where-Object { $_ -like "$k=*" } | Select-Object -First 1) }
if ($Mode -eq 'status') { "kenshi.cfg: $(val 'Full Screen'); $(val 'Video Mode'); play values saved: $(Test-Path $save)"; exit 0 }
if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { 'Kenshi is running: stop it first'; exit 1 }
if ($Mode -eq 'test') {
  if (-not (Test-Path $save)) { $keys | ForEach-Object { val $_ } | Set-Content $save -Encoding ASCII }
  $new = @{ 'Full Screen' = 'Full Screen=No'; 'Video Mode' = 'Video Mode=1600 x 900 @ 32-bit colour [0]' }
} else {
  if (-not (Test-Path $save)) { 'no saved play values'; exit 0 }
  $new = @{}; Get-Content $save | ForEach-Object { $new[($_ -split '=')[0]] = $_ }
}
$lines = $lines | ForEach-Object { $l = $_; foreach ($k in $keys) { if ($l -like "$k=*" -and $new[$k]) { $l = $new[$k] } }; $l }
Set-Content $cfg $lines -Encoding ASCII
if ($Mode -eq 'play') { Remove-Item $save -Force }
"kenshi.cfg -> ${Mode}: $(($lines | Where-Object { $_ -like 'Full Screen=*' -or $_ -like 'Video Mode=*' }) -join '; ')"
