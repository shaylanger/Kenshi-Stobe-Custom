$ErrorActionPreference = 'Stop'
$root = 'C:\KenshiModding\training-data'
New-Item -ItemType Directory -Force -Path $root | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $root 'shadow-enabled.flag') | Out-Null

$listener = Get-NetTCPConnection -State Listen -LocalPort 8091 -ErrorAction SilentlyContinue
if (-not $listener) {
    Start-Process -FilePath 'C:\Users\Shay\Desktop\Start STOBE Shadow Qwen 9B.cmd' -WindowStyle Minimized
    Write-Output 'Started Qwen3.5 9B shadow server on port 8091.'
} else {
    Write-Output 'Shadow server is already listening on port 8091.'
}

$worker = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -like '*stobe-shadow-worker.py*' -and $_.Name -match '^python'
}
if (-not $worker) {
    $python = (Get-Command python).Source
    Start-Process -FilePath $python -WindowStyle Hidden -ArgumentList 'C:\KenshiModding\tools\stobe-shadow-worker.py'
    Write-Output 'Started STOBE shadow worker.'
} else {
    Write-Output 'STOBE shadow worker is already running.'
}

Write-Output 'Shadow mode ENABLED. DeepSeek remains authoritative.'
