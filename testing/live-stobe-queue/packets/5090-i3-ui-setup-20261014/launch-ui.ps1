# Candidate only: exact D3 background launch + launch-file rollback. Separate operation review required.
param([switch]$Apply,[switch]$Restore)
$ErrorActionPreference='Stop'
$root='D:\KenshiInst\3';$backup=Join-Path $root 'stobe-ui-rollback-20261014\launch';$owner='5090c-ui-setup-20261014'
if($env:COMPUTERNAME -cne 'DESKTOP-JFLPK99'){throw 'wrong host'}
if((Get-Content -LiteralPath 'C:\KenshiTestRuns\game-3.lock' -TotalCount 1).Trim() -cne $owner){throw 'wrong lock owner'}
$pins=@{
 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1'='42500C22D946462633CFDB4059BCA031626CE21B968290BE6FB09E10341C746B'
 'C:\KenshiModding\tools\automation\kenshi-gfx.ps1'='B072A9D67424D0A6F8C9C070C00AFFDF55EB392FA4EF38B5A49F9B67A8B8F680'
 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1'='ADB25A651D7A849FA0D52A5AD7B5E75D20F9D3ABEDBB261F47870D8DB1E142D7'
}
foreach($p in $pins.Keys){if((Get-FileHash -LiteralPath $p).Hash -cne $pins[$p]){throw "tool changed: $p"}}
function Safe([string]$path){$cursor=$path;while($cursor){if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "reparse: $cursor"}};$parent=Split-Path -Parent $cursor;if($parent -eq $cursor){break};$cursor=$parent}}
$files=@('kenshi.cfg','settings.cfg','kenshi.cfg.play','settings.gfx.play','gfx.applied','settings.tutorials.play','mods\AutomationHarness\framecap.txt','mods\AutomationHarness\autoload.txt','mods\AutomationHarness\input_isolation.flag','mods\AutomationHarness\input_isolation.on')
foreach($rel in $files){Safe (Join-Path $root $rel)}
Safe $backup
Add-Type @'
using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class UiLaunchLinks {
 [StructLayout(LayoutKind.Sequential)] struct Info { public uint a,b,c,d,e,f,g,h,i,j,count,k,l; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static uint Count(string p){using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){Info i;if(!GetFileInformationByHandle(f.SafeFileHandle,out i))throw new IOException("link count failed");return i.count;}}
}
'@
foreach($rel in $files){$p=Join-Path $root $rel;if(Test-Path -LiteralPath $p){if([UiLaunchLinks]::Count($p) -ne 1){throw 'shared mutable launch file'}}}
$running=@(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) })
if($running.Count){throw 'D3 running or unidentified; launch/restore requires D3 stopped'}
if(-not $Apply){"PLAN ONLY launch=$(-not $Restore) restore=$Restore instance=3";exit 0}
if($Restore){
 $receipt=Get-Content -LiteralPath (Join-Path $backup 'files.json') -Raw | ConvertFrom-Json
 if(@($receipt).Count -ne $files.Count -or @($receipt.path | Select-Object -Unique).Count -ne $files.Count){throw 'restore receipt count/duplicates'}
 foreach($r in $receipt){if($files -cnotcontains $r.path -or $r.existed -isnot [bool]){throw 'restore receipt outside exact allowlist'}}
 # Restore only after exact D3 is stopped. Configs are test-owned in isolated D3.
 foreach($r in $receipt){$target=Join-Path $root $r.path;Safe $target;if($r.existed){$src=Join-Path $backup $r.path;Safe $src;if((Get-FileHash -LiteralPath $src).Hash -cne $r.sha){throw 'backup altered'};Copy-Item -LiteralPath $src -Destination $target -Force;if((Get-FileHash -LiteralPath $target).Hash -cne $r.sha){throw 'restore mismatch'}}elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force}}
 'LAUNCH_FILES_RESTORED instance=3';exit 0
}
if(Test-Path -LiteralPath $backup){throw 'launch backup exists'}
if((Get-FileHash -LiteralPath (Join-Path $root 'mods\Stobe\Stobe.dll')).Hash -cne 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'){throw 'Stobe mismatch'}
if(-not(Test-Path -LiteralPath (Join-Path $root 'save\kah-5090c-ui-20261014\quick.save'))){throw 'copied save absent'}
if(@(Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 18086).Count){throw 'UI private port occupied'}
$ini=Get-Content -LiteralPath (Join-Path $root 'RE_Kenshi\mods\Stobe\StobeCustom.ini') -Raw
foreach($pair in @(@('ServerHost','127.0.0.1'),@('ServerPort','18086'),@('ChatHotkey','/'))){if($ini -notmatch ('(?m)^\s*'+$pair[0]+'\s*=\s*'+[regex]::Escape($pair[1])+'\s*$')){throw 'private config mismatch'}}
New-Item -ItemType Directory -Path $backup | Out-Null
$receipt=@(foreach($rel in $files){$path=Join-Path $root $rel;$exists=Test-Path -LiteralPath $path;if($exists){$dst=Join-Path $backup $rel;New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null;Copy-Item -LiteralPath $path -Destination $dst;@{path=$rel;existed=$true;sha=(Get-FileHash -LiteralPath $path).Hash}}else{@{path=$rel;existed=$false;sha=$null}}})
$receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'files.json') -Encoding UTF8
$prevInst=$env:KAH_INSTANCE;$prevOwner=$env:KAH_OWNER
try {
 $env:KAH_INSTANCE='3';$env:KAH_OWNER=$owner
 # Wrapper verifies DISPLAY1 exists, rejects forbidden Samsung monitor, and supplies Background+Isolate+warning guard.
 & 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' launch -Save 'kah-5090c-ui-20261014' -Gfx low -Monitor '\\.\DISPLAY1' -TimeoutSec 120
 if($LASTEXITCODE -ne 0){throw 'scoped launch failed; preserve output/backup for recovery'}
 'LAUNCH_RETURNED instance=3 gameplay_result=UNPROVEN'
}finally{$env:KAH_INSTANCE=$prevInst;$env:KAH_OWNER=$prevOwner}
