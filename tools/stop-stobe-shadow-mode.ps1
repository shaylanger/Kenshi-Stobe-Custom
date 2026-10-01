$root = 'C:\KenshiModding\training-data'
Remove-Item -LiteralPath (Join-Path $root 'shadow-enabled.flag') -Force -ErrorAction SilentlyContinue

Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -like '*stobe-shadow-worker.py*' -and $_.Name -match '^python'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$listener = Get-NetTCPConnection -State Listen -LocalPort 8091 -ErrorAction SilentlyContinue
if ($listener) {
    Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
}
Write-Output 'Shadow mode disabled. Port 8091 shadow server and worker stopped.'
