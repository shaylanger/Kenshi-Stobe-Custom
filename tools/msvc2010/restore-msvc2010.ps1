# Undoes install-msvc2010.ps1: removes every program that was not installed when the snapshot was taken,
# then makes sure the VC++ 2010 redistributables from the snapshot are present again.
# Run from an elevated PowerShell:  powershell -ExecutionPolicy Bypass -File restore-msvc2010.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dl   = Join-Path $here 'downloads'
$snap = Join-Path $here 'snapshot-before.json'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    throw 'Run this from an elevated (Administrator) PowerShell.'
}
if (-not (Test-Path $snap)) { throw "No snapshot at $snap - nothing to restore against." }

function Get-Installed {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName |
        Select-Object @{n='Key';e={$_.PSChildName}}, DisplayName, DisplayVersion, UninstallString
}

$before = Get-Content $snap -Raw | ConvertFrom-Json
$beforeNames = $before | ForEach-Object { $_.DisplayName }
$added = Get-Installed | Where-Object { $beforeNames -notcontains $_.DisplayName }

# Never remove the 2010 redistributables here; they are handled below.
$added = $added | Where-Object { $_.DisplayName -notlike 'Microsoft Visual C++ 2010*Redistributable*' }

if ($added) {
    Write-Host 'Programs installed since the snapshot:'
    $added | ForEach-Object { "  - $($_.DisplayName) $($_.DisplayVersion)" }
    if ((Read-Host "`nUninstall all of these? (y/n)") -ne 'y') { Write-Host 'Aborted.'; exit 1 }
    # Compiler update first, then the SDK pieces
    $added = $added | Sort-Object { if ($_.DisplayName -match 'Compilers') { 0 } else { 1 } }
    foreach ($p in $added) {
        Write-Host "Removing $($p.DisplayName)"
        if ($p.Key -match '^\{[0-9A-Fa-f-]+\}$') {
            Start-Process msiexec.exe -ArgumentList "/x $($p.Key) /qn /norestart" -Wait
        } elseif ($p.UninstallString) {
            Write-Host '  (non-MSI uninstaller; its window may open)'
            Start-Process cmd.exe -ArgumentList "/c `"$($p.UninstallString)`"" -Wait
        }
    }
} else { Write-Host 'Nothing was added since the snapshot.' }

# Make sure the 2010 redistributables match the snapshot
$wantRedist = $before | Where-Object { $_.DisplayName -like 'Microsoft Visual C++ 2010*Redistributable*' }
$haveRedist = Get-Installed | Where-Object { $_.DisplayName -like 'Microsoft Visual C++ 2010*Redistributable*' }
foreach ($w in $wantRedist) {
    $match = $haveRedist | Where-Object { $_.DisplayName -eq $w.DisplayName }
    if (-not $match) {
        $exe = if ($w.DisplayName -match 'x64') { 'vcredist_x64.exe' } else { 'vcredist_x86.exe' }
        Write-Host "Reinstalling $($w.DisplayName)"
        Start-Process (Join-Path $dl $exe) -ArgumentList '/q /norestart' -Wait
    }
}

Write-Host "`n--- Differences from snapshot (should be empty) ---"
$now = Get-Installed
$nowNames = $now | ForEach-Object { $_.DisplayName }
$now    | Where-Object { $beforeNames -notcontains $_.DisplayName } | ForEach-Object { "  extra:   $($_.DisplayName)" }
$before | Where-Object { $nowNames   -notcontains $_.DisplayName } | ForEach-Object { "  missing: $($_.DisplayName)" }
