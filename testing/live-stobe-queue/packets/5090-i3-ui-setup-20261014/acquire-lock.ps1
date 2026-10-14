# Candidate: explicit atomic acquisition; no stale-lock takeover.
param([switch]$Apply)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -cne 'DESKTOP-JFLPK99'){throw 'wrong host'}
$root='D:\KenshiInst\3'
$lock='C:\KenshiTestRuns\game-3.lock'
if(@(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) }).Count){throw 'D3 running/unknown executable'}
if(Test-Path -LiteralPath $lock){throw 'existing lock; do not steal'}
if(@(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match '(?i)(rig-lane2|rig-runner)\.ps1' -and $_.CommandLine -match '(?i)5090c' }).Count){throw 'existing instance-3 runner'}
foreach($p in @('C:\KenshiTestRuns','D:\KenshiInst','D:\KenshiInst\3')){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'reparse ancestor'}}
if(-not $Apply){'PLAN ONLY atomic create-new D3 lock';exit 0}
$stream=[IO.File]::Open($lock,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {$bytes=[Text.Encoding]::UTF8.GetBytes("5090c-ui-setup-20261014`r`n$([DateTime]::UtcNow.ToString('o'))`r`n");$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
'LOCK_CREATED owner=5090c-ui-setup-20261014 instance=3'
