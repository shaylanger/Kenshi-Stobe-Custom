<#
itrun.ps1 (4080 rig, installed as C:\KAH\itrun.ps1): run one bash command line detached inside Shay's logged-in desktop
session, with no visible window. Needed for anything that captures the screen (ffmpeg gdigrab by window title): an ssh
session has no desktop. rig-env.sh is sourced first. Returns at once; the command's output goes to -Log.
Usage: powershell -File C:\KAH\itrun.ps1 -Cmd "bash /c/KenshiTestRuns/f36/take5.sh" -Log C:\KenshiTestRuns\x.out
#>
param([Parameter(Mandatory = $true)][string]$Cmd, [Parameter(Mandatory = $true)][string]$Log)
$ErrorActionPreference = 'Stop'
$dir = 'C:\KAH\itrun'; New-Item -ItemType Directory -Force $dir | Out-Null
$vbs = 'C:\KAH\hide.vbs'
if (-not (Test-Path $vbs)) {
  Set-Content $vbs 'CreateObject("WScript.Shell").Run """C:\Program Files\Git\bin\bash.exe"" -l " & WScript.Arguments(0), 0, False' -Encoding ASCII
}
Get-ChildItem $dir -Filter *.sh | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force
$id = [guid]::NewGuid().ToString('N').Substring(0, 12)
$sh = Join-Path $dir "$id.sh"
$logp = '/' + $Log.Substring(0, 1).ToLower() + ($Log.Substring(2).Replace([string][char]92, '/'))
$body = "#!/bin/bash`n{ . /c/KenshiModding/tools/automation/rig-env.sh; $Cmd ; } > '$logp' 2>&1 < /dev/null`n"
[IO.File]::WriteAllText($sh, $body)
$tn = "KAH_it_$id"
schtasks /create /tn $tn /tr "wscript.exe //B $vbs C:/KAH/itrun/$id.sh" /sc once /st 23:59 /it /f | Out-Null
schtasks /run /tn $tn | Out-Null
Start-Sleep 2
schtasks /delete /tn $tn /f | Out-Null
"started $id log=$Log"
