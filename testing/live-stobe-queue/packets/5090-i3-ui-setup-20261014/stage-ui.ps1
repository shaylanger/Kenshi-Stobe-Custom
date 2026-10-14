# Local candidate only; independent review + Validator CLEAR required before -Apply.
# Stages only existing D3; does not launch a game, contact a backend, or provision services.
param([Parameter(Mandatory=$true)][string]$FixturePath, [switch]$Apply)
$ErrorActionPreference='Stop'
$root='D:\KenshiInst\3'
$save=Join-Path $root 'save\kah-5090c-ui-20261014'
$backup=Join-Path $root 'stobe-ui-rollback-20261014'
$want='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'
$source="C:\KenshiModding\pending-fixes\release-staging\stobe-integrated\5090\$want\Stobe.dll"
$dll=Join-Path $root 'mods\Stobe\Stobe.dll'
$ini=Join-Path $root 'RE_Kenshi\mods\Stobe\StobeCustom.ini'
$settings=Join-Path $root 'settings.cfg'
function RealPath([string]$path) {
  $full=[IO.Path]::GetFullPath($path)
  $cursor=$full
  while ($cursor) {
    $entry=Get-Item -LiteralPath $cursor -Force
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "reparse path rejected: $cursor" }
    $parent=Split-Path -Parent $cursor
    if ($parent -eq $cursor) { break }
    $cursor=$parent
  }
  $full
}
function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Manifest([string]$path) {
  $base=(RealPath $path).TrimEnd('\')+'\'
  $map=[ordered]@{}
  foreach($entry in (Get-ChildItem -LiteralPath $path -Recurse -Force | Sort-Object FullName)) {
    [void](RealPath $entry.FullName)
    if (-not $entry.PSIsContainer) { $map[$entry.FullName.Substring($base.Length)]=Hash $entry.FullName }
  }
  $map
}
if ($env:COMPUTERNAME -cne 'DESKTOP-JFLPK99') { throw 'wrong host' }
[void](RealPath $root)
if ((Get-Content -LiteralPath (Join-Path $root 'instance.txt') -Raw) -notmatch '^instance=3(?:\s|$)') { throw 'instance marker mismatch' }
if ((Get-Content -LiteralPath $settings -Raw) -notmatch '(?m)^User save location=0\s*$') { throw 'save setting not local' }
$running=@(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) })
if($running.Count){throw 'D3 game running or executable identity unavailable'}
if (@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object LocalPort -eq 18086).Count) { throw '18086 listener exists; no UI-disconnected staging' }
$lock=(Get-Content -LiteralPath 'C:\KenshiTestRuns\game-3.lock' -TotalCount 1).Trim()
if ($lock -cne '5090c-ui-setup-20261014') { throw 'scoped lock owner missing; operator must acquire lock first' }
foreach($p in @($source,$dll,$ini,$settings)){[void](RealPath $p)}
if ((Hash $source) -cne $want) { throw 'candidate SHA mismatch' }
$candidate='C:\KenshiModding\pending-fixes\release-coordination\stobe-native-integrated-candidate-20261013'
if ((Hash (Join-Path $candidate 'SOURCE-MANIFEST.json')) -cne 'AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C') {throw 'source manifest mismatch'}
if ((Hash (Join-Path $candidate 'PAYLOAD-MANIFEST.json')) -cne '475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A') {throw 'payload manifest mismatch'}
if ((Hash (Join-Path $root 'mods\AutomationHarness\AutomationHarness.dll')) -cne '974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D') {throw 'Harness mismatch'}
$fixture=RealPath $FixturePath
if (-not (Test-Path -LiteralPath (Join-Path $fixture 'quick.save') -PathType Leaf)) { throw 'fixture quick.save missing' }
if (Test-Path -LiteralPath $save) { throw 'copied-save destination exists' }
if (Test-Path -LiteralPath $backup) { throw 'rollback directory exists' }
[void](RealPath (Join-Path $root 'save'))
$manifest=Manifest $fixture
$iniBytes=[IO.File]::ReadAllBytes($ini)
$hasBom=$iniBytes.Length -ge 3 -and $iniBytes[0] -eq 239 -and $iniBytes[1] -eq 187 -and $iniBytes[2] -eq 191
$offset=if($hasBom){3}else{0}
$strictUtf8=New-Object System.Text.UTF8Encoding($false,$true)
$rawIni=$strictUtf8.GetString($iniBytes,$offset,$iniBytes.Length-$offset)
$lines=@($rawIni -split '\r?\n')
foreach($key in @('ServerHost','ServerPort','ChatHotkey')) {
  if(@($lines | Where-Object {$_ -match ('^\s*'+$key+'\s*=')}).Count -ne 1){throw "ambiguous/missing INI key: $key"}
}
$newIni=[regex]::Replace($rawIni,'(?m)^(\s*ServerHost\s*=)[^\r\n]*','${1}127.0.0.1')
$newIni=[regex]::Replace($newIni,'(?m)^(\s*ServerPort\s*=)[^\r\n]*','${1}18086')
$newIni=[regex]::Replace($newIni,'(?m)^(\s*ChatHotkey\s*=)[^\r\n]*','${1}/')
$newBytes=$strictUtf8.GetBytes($newIni)
if($hasBom){$newBytes=[byte[]](@(239,187,191)+$newBytes)}
# Single-link verification avoids overwriting any shared mutable file.
Add-Type @'
using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class UiStageLinks {
 [StructLayout(LayoutKind.Sequential)] struct Info { public uint a,b,c,d,e,f,g,h,i,j,count,k,l; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static uint Count(string p){using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){Info i;if(!GetFileInformationByHandle(f.SafeFileHandle,out i))throw new IOException("link count failed");return i.count;}}
}
'@
foreach($p in @($dll,$ini,$settings)){if([UiStageLinks]::Count($p) -ne 1){throw 'shared mutable file rejected'}}
if(-not $Apply){'PLAN ONLY: guards passed; no staging performed';exit 0}
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $backup 'Stobe.dll')
Copy-Item -LiteralPath $ini -Destination (Join-Path $backup 'StobeCustom.ini')
$old=@{dll=Hash $dll;ini=Hash $ini;settings=Hash $settings;fixture=$fixture;files=$manifest}
$old | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'before.json') -Encoding UTF8
try {
  New-Item -ItemType Directory -Path $save | Out-Null
  Get-ChildItem -LiteralPath $fixture -Force | Copy-Item -Destination $save -Recurse
  $copied=Manifest $save
  if(($manifest | ConvertTo-Json -Compress) -cne ($copied | ConvertTo-Json -Compress)){throw 'save copy manifest mismatch'}
  Copy-Item -LiteralPath $source -Destination $dll -Force
  if((Hash $dll) -cne $want){throw 'installed DLL mismatch'}
  [IO.File]::WriteAllBytes($ini,$newBytes)
  @{dll=Hash $dll;ini=Hash $ini;save=$save;files=$copied;endpoint='127.0.0.1:18086';backend='NOT_STARTED'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'staged.json') -Encoding UTF8
  'STAGED ONLY instance=3 game_launched=false backend_started=false'
} catch {
  Copy-Item -LiteralPath (Join-Path $backup 'Stobe.dll') -Destination $dll -Force
  Copy-Item -LiteralPath (Join-Path $backup 'StobeCustom.ini') -Destination $ini -Force
  if((Hash $dll) -cne $old.dll -or (Hash $ini) -cne $old.ini){throw 'rollback hash mismatch; operator intervention required'}
  Write-Warning "Staging failed; original DLL/INI restored. Retained owned partial save $save and rollback $backup require reviewed cleanup before retry."
  throw
}
