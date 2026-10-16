param(
    [string]$RuntimeDirectory = (Join-Path $PSScriptRoot 'reports\codex\operator-runtime'),
    [int]$SampleIntervalSeconds = 30,
    [int]$MaxRuntimeHours = 24
)

$ErrorActionPreference = 'Stop'
if ($SampleIntervalSeconds -lt 5 -or $SampleIntervalSeconds -gt 60) {
    throw 'SampleIntervalSeconds must be between 5 and 60.'
}
if ($MaxRuntimeHours -lt 1 -or $MaxRuntimeHours -gt 24) {
    throw 'MaxRuntimeHours must be between 1 and 24.'
}

New-Item -ItemType Directory -Path $RuntimeDirectory -Force | Out-Null
$csvPath = Join-Path $RuntimeDirectory 'host-load.csv'
$stopPath = Join-Path $RuntimeDirectory 'STOP'
$receiptPath = Join-Path $RuntimeDirectory 'host-load.pid.json'
$deadline = [DateTime]::UtcNow.AddHours($MaxRuntimeHours)

[pscustomobject]@{
    Pid = $PID
    StartedUtc = [DateTime]::UtcNow.ToString('o')
    DeadlineUtc = $deadline.ToString('o')
    Csv = $csvPath
    StopMarker = $stopPath
} | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8

if (-not (Test-Path -LiteralPath $csvPath)) {
    'timestamp_utc,cpu_percent,available_ram_gib,total_ram_gib' | Set-Content -LiteralPath $csvPath -Encoding ASCII
}

while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $stopPath)) {
    $processors = @(Get-CimInstance -ClassName Win32_Processor)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu = [math]::Round(($processors | Measure-Object -Property LoadPercentage -Average).Average, 1)
    $available = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    '{0},{1},{2},{3}' -f [DateTime]::UtcNow.ToString('o'), $cpu, $available, $total |
        Add-Content -LiteralPath $csvPath -Encoding ASCII
    Start-Sleep -Seconds $SampleIntervalSeconds
}
