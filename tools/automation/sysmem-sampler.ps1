# sysmem-sampler.ps1: every -Interval s append one CSV line (vmmem + system memory + Kenshi) until <Csv>.stop exists.
# Usage: Start-Process powershell "-File sysmem-sampler.ps1 -Csv C:\...\sysmem.csv" -WindowStyle Hidden ; stop: New-Item <Csv>.stop
param([Parameter(Mandatory = $true)][string]$Csv, [int]$Interval = 30)
if (-not (Test-Path $Csv)) { 'time,vmmemWsMB,vmmemPrivMB,kenshiWsMB,kenshiPrivMB,sysFreeMB,commitUsedMB,commitLimitMB' | Out-File $Csv -Encoding utf8 }
while (-not (Test-Path "$Csv.stop")) {
  $vm = Get-Process vmmem, vmmemWSL -ErrorAction SilentlyContinue | Measure-Object WorkingSet64, PrivateMemorySize64 -Sum
  $k = Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Select-Object -First 1
  $os = Get-CimInstance Win32_OperatingSystem
  $mb = 1MB
  $line = '{0},{1},{2},{3},{4},{5},{6},{7}' -f (Get-Date -Format 'HH:mm:ss'),
    [int](($vm | Where-Object Property -eq WorkingSet64).Sum / $mb), [int](($vm | Where-Object Property -eq PrivateMemorySize64).Sum / $mb),
    $(if ($k) { [int]($k.WorkingSet64 / $mb) } else { '' }), $(if ($k) { [int]($k.PrivateMemorySize64 / $mb) } else { '' }),
    [int]($os.FreePhysicalMemory / 1KB), [int](($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1KB), [int]($os.TotalVirtualMemorySize / 1KB)
  $line | Out-File $Csv -Append -Encoding utf8
  Start-Sleep -Seconds $Interval
}
Remove-Item "$Csv.stop" -ErrorAction SilentlyContinue
