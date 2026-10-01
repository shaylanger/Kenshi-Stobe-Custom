# Installs the MSVC 2010 x64 compiler (Windows SDK 7.1 + VC 2010 SP1 compiler update) for building Stobe.dll.
# Run from an elevated PowerShell:  powershell -ExecutionPolicy Bypass -File install-msvc2010.ps1
# Takes a snapshot of installed programs first so restore-msvc2010.ps1 can undo everything.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dl   = Join-Path $here 'downloads'
$snap = Join-Path $here 'snapshot-before.json'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    throw 'Run this from an elevated (Administrator) PowerShell.'
}
if (Get-Process -Name 'kenshi*' -ErrorAction SilentlyContinue) { throw 'Close Kenshi first.' }

function Get-Installed {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName |
        Select-Object @{n='Key';e={$_.PSChildName}}, DisplayName, DisplayVersion, UninstallString
}

# 0. Snapshot (never overwrite an existing one: it is the true "before" state)
if (-not (Test-Path $snap)) {
    Get-Installed | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 $snap
    Write-Host "Snapshot saved: $snap"
} else { Write-Host "Keeping existing snapshot: $snap" }

# Downloads (skipped if already present)
New-Item -ItemType Directory -Force $dl | Out-Null
$files = [ordered]@{
    'GRMSDKX_EN_DVD.iso'        = 'https://download.microsoft.com/download/F/1/0/F10113F5-B750-4969-A255-274341AC6BCE/GRMSDKX_EN_DVD.iso'
    'VC-Compiler-KB2519277.exe' = 'https://download.microsoft.com/download/7/5/0/75040801-126C-4591-BCE4-4CD1FD1499AA/VC-Compiler-KB2519277.exe'
    'vcredist_x64.exe'          = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe'
    'vcredist_x86.exe'          = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe'
}
$ProgressPreference = 'SilentlyContinue'
foreach ($name in $files.Keys) {
    $out = Join-Path $dl $name
    if (-not (Test-Path $out)) { Write-Host "Downloading $name ..."; Invoke-WebRequest $files[$name] -OutFile $out -UseBasicParsing }
}

# 1. Uninstall VC++ 2010 redistributables
Write-Host "`n[1/4] Removing VC++ 2010 redistributables"
Get-Installed | Where-Object { $_.DisplayName -like 'Microsoft Visual C++ 2010*Redistributable*' } | ForEach-Object {
    Write-Host "  - $($_.DisplayName)"
    Start-Process msiexec.exe -ArgumentList "/x $($_.Key) /qn /norestart" -Wait
}

# 2. Windows SDK 7.1 (interactive: accept defaults, keep 'Visual C++ Compilers' checked)
Write-Host "`n[2/4] Windows SDK 7.1 - the installer window will open; accept the defaults."
$iso = Join-Path $dl 'GRMSDKX_EN_DVD.iso'
$img = Mount-DiskImage -ImagePath $iso -PassThru
try {
    $drive = ($img | Get-Volume).DriveLetter
    Start-Process "${drive}:\setup.exe" -WorkingDirectory "${drive}:\" -Wait
} finally { Dismount-DiskImage -ImagePath $iso | Out-Null }

# 3. VC 2010 SP1 compiler update
Write-Host "`n[3/4] VC 2010 SP1 compiler update (KB2519277) - the installer window will open."
Start-Process (Join-Path $dl 'VC-Compiler-KB2519277.exe') -Wait

# 4. Reinstall latest VC++ 2010 redistributables
Write-Host "`n[4/4] Reinstalling VC++ 2010 redistributables"
foreach ($r in 'vcredist_x64.exe', 'vcredist_x86.exe') {
    Start-Process (Join-Path $dl $r) -ArgumentList '/q /norestart' -Wait
}

# Verify
Write-Host "`n--- Check ---"
$setenv = 'C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.cmd'
$cl     = 'C:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\bin\amd64\cl.exe'
"SetEnv.cmd : $(Test-Path $setenv)"
"cl.exe x64 : $(Test-Path $cl)"
if (Test-Path $cl) { (Get-Item $cl).VersionInfo.FileVersion }
Get-Installed | Where-Object { $_.DisplayName -like 'Microsoft Visual C++ 2010*Redistributable*' } | ForEach-Object { "Redist     : $($_.DisplayName)" }
