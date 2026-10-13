for($i=0;$i -lt 6;$i++) {
    $os=Get-CimInstance Win32_OperatingSystem
    $gpu=& nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader
    $rows=Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'kenshi|llama|vmmem'} | Select-Object ProcessId,Name,WorkingSetSize
    $pf=Get-CimInstance Win32_PageFileUsage | Select-Object CurrentUsage,PeakUsage
    $r=@{utc=[DateTime]::UtcNow.ToString('o');ram_free_mib=[math]::Round($os.FreePhysicalMemory/1024);virtual_free_mib=[math]::Round($os.FreeVirtualMemory/1024);gpu=$gpu;processes=$rows;pagefile=$pf}|ConvertTo-Json -Depth 5 -Compress
    $r | Add-Content C:\KenshiTestRuns\standalone4080\resource-watch.jsonl
    $gpuUsed=[int](($gpu -split ' ')[0])
    if($os.FreePhysicalMemory -lt 2097152 -or $gpuUsed -gt 14328) { "PRESSURE $r" }
    if($i -lt 5) { Start-Sleep -Seconds 10 } else { $r }
}
