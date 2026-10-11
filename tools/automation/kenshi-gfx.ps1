<#
kenshi-gfx.ps1 full|low|play|status [-Kenshi <dir>] [-Fps <n>]  (both rigs; Kenshi closed for full|low|play)
Test-launch graphics (Shay 2026-10-10 22:05: cut GPU/CPU/RAM without slowing tests):
  full   filming lists: Shay's graphics (settings.cfg as he set it), Video Mode 1600x900, frame cap 60 fps
  low    lists that don't film ("# gfx: low"): lowest graphics in settings.cfg (shadows, grass, foliage, reflections,
         post effects, decals, view/terrain distance, distant towns, half textures), Video Mode 1280x720 (KAH_VIDEO_MODE overrides), frame cap 60
  play   Shay's own settings back: settings.cfg graphics as saved, frame cap off (kenshi-ctl -Play / cfg play, kcfg play)
  status one line: applied mode, cap, Video Mode
Frame cap = <Kenshi>\mods\AutomationHarness\framecap.txt, read once a second by the harness (Plugin.cpp FrameCap; absent
or 0 = uncapped, so Shay's own play is never capped). -Fps overrides 60 (0 = off). Shay's graphics values are saved
to C:\KenshiTestRuns\settings.gfx.play at the first test launch and written back by full and play (play deletes the copy); kenshi.cfg's
Full Screen / Video Mode / VSync play values stay with kenshi-ctl.ps1 cfg (5090) and kcfg.ps1 (4080); this script only
sets Video Mode to the test size of the mode. The applied mode goes to C:\KenshiTestRuns\gfx.applied (runner: relaunch
only when a list's mode differs).
#>
param([Parameter(Position = 0)][ValidateSet('full', 'low', 'play', 'status')][string]$Mode = 'status',
      [string]$Kenshi = '', [int]$Fps = -1)
$ErrorActionPreference = 'Stop'
if (-not $Kenshi) {
  $Kenshi = @('D:\Steam\steamapps\common\Kenshi', 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi') |
            Where-Object { Test-Path "$_\kenshi.cfg" } | Select-Object -First 1
}
$scfg = "$Kenshi\settings.cfg"; $kcfg = "$Kenshi\kenshi.cfg"
$capF = "$Kenshi\mods\AutomationHarness\framecap.txt"
# no -Fps: 60, or uncapped while C:\KenshiTestRuns\uncapped.on exists (Shay 2026-10-11: PC free, use it fully; delete the file to cap again)
if ($Fps -lt 0) { $Fps = if (Test-Path 'C:\KenshiTestRuns\uncapped.on') { 0 } else { 60 } }
$save = 'C:\KenshiTestRuns\settings.gfx.play'; $applied = 'C:\KenshiTestRuns\gfx.applied'
# a multi-instance install copy (kenshi-instance.ps1, has instance.txt) keeps its own state next to its game, never instance 1's
if (Test-Path "$Kenshi\instance.txt") { $save = "$Kenshi\settings.gfx.play"; $applied = "$Kenshi\gfx.applied" }
# lowest graphics; gameplay-relevant ranges (npc range, objects view range) and visible gameplay (Blood, Dismemberment,
# Show names, floaters) stay as they are so no row behaves differently
$Low = [ordered]@{
  'view distance' = '3000'; 'terrain hi-res distance' = '500'; 'terrain detail' = '0'; 'terrain distant' = '0'
  'terrain threshold' = '500'; 'grass range' = '0'; 'grass density' = '0'; 'foliage range' = '0'
  'water reflection' = '0'; 'reflection range' = '0'; 'shadow mode' = '0'; 'shadow quality' = '0'; 'Shadow Range' = '1000'
  'texture resolution gimping' = '1'; 'Decal Resolution' = '256'; 'Decal Range' = '50'; 'feature range' = '1'
  'distant town range' = '1'; 'generate distant towns' = '0'; 'FXAA' = '0'; 'HeatHaze' = '0'; 'SSAOD' = '0'
  'Kuwahara' = '0'; 'Outlines' = '0'; 'Posterise' = '0'; 'Colourful' = '0'; 'DepthBlur' = '0'
  'ContrastAdaptiveSharpening' = '0'; 'FXAA_POST' = '0'
}
$VM = @{ full = '1600 x 900 @ 32-bit colour [0]'; low = '1280 x 720 @ 32-bit colour [0]' }   # a listed DXGI mode: Ogre replaces an unlisted one (1024x576, 640x360) with the screen's largest (2560x1440 / 4096x2160), m102

function Read-Kv([string]$f) { $h = [ordered]@{}; foreach ($l in Get-Content $f) { $i = $l.IndexOf('='); if ($i -gt 0) { $h[$l.Substring(0, $i)] = $l.Substring($i + 1) } }; $h }
function Set-Kv([string]$f, $want) {
  $seen = @{}
  $out = foreach ($l in Get-Content $f) { $i = $l.IndexOf('='); if ($i -gt 0 -and $want.Contains($l.Substring(0, $i))) { $k = $l.Substring(0, $i); $seen[$k] = 1; "$k=$($want[$k])" } else { $l } }
  # Kenshi writes every key it knows; a key it never wrote is left out (an unknown key could be read differently)
  Set-Content -Path $f -Value $out -Encoding Ascii
}
function Cap { if (Test-Path $capF) { (Get-Content $capF -TotalCount 1).Trim() } else { 'off' } }
function Status {
  $a = if (Test-Path $applied) { (Get-Content $applied -TotalCount 1).Trim() } else { 'none' }
  $vm = ((Get-Content $kcfg | Where-Object { $_ -like 'Video Mode=*' }) -replace '^Video Mode=', '')
  $sh = (Read-Kv $scfg)['shadow mode']
  "gfx: applied=$a cap=$(Cap) Video Mode=$vm shadow mode=$sh play values saved: $(Test-Path $save)"
}
if ($Mode -eq 'status') { Status; exit 0 }
if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { -not $_.Path -or $_.Path -like "$Kenshi\*" }) { 'gfx: Kenshi is running: the mode applies at the next launch; stop it first'; exit 1 }

$cur = Read-Kv $scfg
# Shay's values once (never overwrite them with low values: only keys that differ from the low value are new saves)
$saved = if (Test-Path $save) { Read-Kv $save } else { [ordered]@{} }
foreach ($k in $Low.Keys) { if (-not $saved.Contains($k) -and $cur.Contains($k) -and $cur[$k] -ne $Low[$k]) { $saved[$k] = $cur[$k] } }
Set-Content -Path $save -Value @($saved.Keys | ForEach-Object { "$_=$($saved[$_])" }) -Encoding Ascii

if ($Mode -eq 'low') { Set-Kv $scfg $Low } else { Set-Kv $scfg $saved }
if ($Mode -ne 'play') {
  # $env:KAH_VIDEO_MODE ('800 x 600', must be a listed DXGI mode): lanes 5090b/5090c small non-filming window (rig-lane2.ps1); only with gfx low
  $vmw = if ($Mode -eq 'low' -and $env:KAH_VIDEO_MODE -match '^\d+ x \d+$') { "$($env:KAH_VIDEO_MODE) @ 32-bit colour [0]" } else { $VM[$Mode] }
  Set-Kv $kcfg @{ 'Video Mode' = $vmw }
  if ($Fps -gt 0) { Set-Content -Path $capF -Value "$Fps" -Encoding Ascii } else { Remove-Item $capF -Force -ErrorAction SilentlyContinue }
  Set-Content -Path $applied -Value $Mode -Encoding Ascii
} else {
  # values Shay changes while playing are taken again at the next test launch
  Remove-Item $capF, $applied, $save -Force -ErrorAction SilentlyContinue
}
Status
