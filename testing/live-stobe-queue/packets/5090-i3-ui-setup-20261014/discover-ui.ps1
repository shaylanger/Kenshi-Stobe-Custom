# Candidate read-only Windows facts; no endpoint/network/game commands or mutations.
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'DESKTOP-JFLPK99'){throw 'wrong host'}
"HOST=$env:COMPUTERNAME"
Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Select-Object ProcessId,ExecutablePath | ConvertTo-Json -Compress
$root='D:\KenshiInst\3'
foreach($rel in @('instance.txt','settings.cfg','mods\Stobe\Stobe.dll','mods\AutomationHarness\AutomationHarness.dll','RE_Kenshi\mods\Stobe\StobeCustom.ini','RE_Kenshi\mods\Stobe\Stobe.ini')) {
  $path=Join-Path $root $rel
  if(-not(Test-Path -LiteralPath $path)) {"MISSING=$path";continue}
  $item=Get-Item -LiteralPath $path -Force
  "FILE=$path SHA256=$((Get-FileHash -LiteralPath $path).Hash) REPARSE=$([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint))"
  if($rel -eq 'instance.txt'){Get-Content -LiteralPath $path}
  if($rel -eq 'settings.cfg'){Get-Content -LiteralPath $path | Where-Object {$_ -match '^User save location='}}
  if($rel -match '\.ini$'){Get-Content -LiteralPath $path | Where-Object {$_ -match '^\s*(ServerHost|ServerPort|ChatHotkey)\s*='}}
}
foreach($dir in @($root,(Join-Path $root 'mods'),(Join-Path $root 'mods\Stobe'),(Join-Path $root 'RE_Kenshi'),(Join-Path $root 'RE_Kenshi\mods'),(Join-Path $root 'RE_Kenshi\mods\Stobe'),(Join-Path $root 'save'))) {
  if(Test-Path -LiteralPath $dir){$item=Get-Item -LiteralPath $dir -Force;"DIR=$dir REPARSE=$([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint))"}
}
$saveRoot=Join-Path $env:LOCALAPPDATA 'kenshi\save'
Get-ChildItem -LiteralPath $saveRoot -Directory | Where-Object {$_.Name -match '(?i)fresh.*start|^kah-'} | Sort-Object Name | ForEach-Object {
  $quick=Join-Path $_.FullName 'quick.save'
  if(Test-Path -LiteralPath $quick -PathType Leaf){"FIXTURE=$($_.FullName) QUICK_SHA256=$((Get-FileHash -LiteralPath $quick).Hash)"}
}
$lock='C:\KenshiTestRuns\game-3.lock'
if(Test-Path -LiteralPath $lock){"LOCK_OWNER=$((Get-Content -LiteralPath $lock -TotalCount 1).Trim())"}else{'LOCK=ABSENT'}
$listeners=@(Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 18086)
"PRIVATE_PORT_18086_LISTENERS=$($listeners.Count)"
