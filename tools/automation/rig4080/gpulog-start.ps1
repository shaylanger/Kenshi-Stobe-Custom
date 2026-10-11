# gpulog-start.ps1 (4080, C:\KAH; gpulog-ensure.ps1): gpulog.vbs into Shay's Startup folder (every logon), stop a stuck copy,
# start it now in Shay's desktop session through the kept task KAH-gpulog (an ssh-started process dies with the session)
param([int]$Stuck = 0)
$vbs = 'C:\KAH\gpulog.vbs'
[IO.File]::WriteAllText($vbs, "CreateObject(""WScript.Shell"").Run ""powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\KAH\gpulog.ps1 -Rig 4080"", 0, False`r`n")
Copy-Item $vbs ([Environment]::GetFolderPath('Startup')) -Force
if ($Stuck) { Stop-Process -Id $Stuck -Force -ErrorAction SilentlyContinue }
schtasks /create /tn KAH-gpulog /tr "wscript.exe //B $vbs" /sc once /st 23:59 /it /f | Out-Null
schtasks /run /tn KAH-gpulog | Out-Null
"RUN $LASTEXITCODE"
