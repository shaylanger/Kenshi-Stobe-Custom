<#
inst-staged.ps1 [-Hash <sha8>]: 4080 side of `install-dll.ps1 KenshiFP -Staged -Rig 4080`. Installs THE build named by C:\KAH\staged\KenshiFP-latest.txt (else the newest, or -Hash)
KenshiFP build kfp-pipeline.sh staged in C:\KAH\staged\KenshiFP-<sha8>.dll into the Kenshi mods\KenshiFP folder.
Kenshi must be closed. Copied to C:\KAH\ by kfp-pipeline.sh on every staging (source: KenshiModding tools/automation/rig4080).
#>
param([string]$Hash = '')
$ErrorActionPreference = 'Stop'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\KenshiFP\KenshiFP.dll'
# only instance 1's game blocks: a lane-2+ game (C:\KenshiInst\<n>, lane 4080b) holds its own DLL copies (m102: 4080b's game failed every 4080 install)
# wait up to 45 s for an exit already under way: the runner calls this right after `ctl.ps1 stop` (m102 15:20: three lists
# FAILED "kenshi still running" within 50 s of a gfx relaunch stop)
$until = (Get-Date).AddSeconds(45)
while ((Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike 'C:\KenshiInst\*' }) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 2 }
if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike 'C:\KenshiInst\*' }) { 'kenshi still running: close it first'; exit 1 }
$f = Get-ChildItem 'C:\KAH\staged\KenshiFP-*.dll' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
# one build line: KenshiFP-latest.txt names THE build (kfp-pipeline.sh); never pick by date when it exists
if (-not $Hash -and (Test-Path 'C:\KAH\staged\KenshiFP-latest.txt')) { $Hash = ((Get-Content 'C:\KAH\staged\KenshiFP-latest.txt' -TotalCount 1) -split ' ')[1] }
if ($Hash) { $f = $f | Where-Object { $_.BaseName -eq "KenshiFP-$($Hash.ToUpper())" } }
$f = $f | Select-Object -First 1
if (-not $f) { 'no staged KenshiFP build in C:\KAH\staged'; exit 1 }
$want = $f.BaseName.Substring(9)
if ((Get-FileHash $f.FullName).Hash.Substring(0, 8) -ne $want) { "staged file $($f.Name) does not match its name hash"; exit 1 }
$old = (Get-FileHash $dst).Hash.Substring(0, 8)
if ($old -eq $want) { "KenshiFP already installed: $want"; exit 0 }
Copy-Item $f.FullName $dst -Force
$new = (Get-FileHash $dst).Hash.Substring(0, 8)
if ($new -ne $want) { "hash mismatch after copy: $new != $want"; exit 1 }
"KenshiFP installed (4080): $old -> $new"
