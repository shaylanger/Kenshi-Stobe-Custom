# wsl-restart.ps1: restart WSL (applies %USERPROFILE%\.wslconfig) and bring the DwemerAI4Skyrim3 stack back.
# Run only between batches: Kenshi closed, no run-batch/fixer job inside WSL. Exit 0 = stack ready.
$ErrorActionPreference = 'Stop'
$distro = 'DwemerAI4Skyrim3'
if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { Write-Output 'WSL-RESTART REFUSED: Kenshi is running'; exit 2 }
$busy = & wsl.exe -d $distro -u root --cd / -- bash -c 'pgrep -f run-batch.sh >/dev/null && echo busy'
if ($busy -match 'busy') { Write-Output 'WSL-RESTART REFUSED: run-batch.sh is running'; exit 2 }
& wsl.exe --shutdown
Start-Sleep -Seconds 8
# Same command the Dwemer launcher uses; start_env waits for Enter, so keep its window minimized.
Start-Process wsl.exe -ArgumentList "-d $distro -- /etc/start_env" -WindowStyle Minimized
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    $r = & wsl.exe -d $distro -u root --cd / -- bash -c 'pg_isready -q && pgrep -x apache2 >/dev/null && pgrep -f "StobeServer/service/start.sh" >/dev/null && echo ready'
    if ($r -match 'ready') { $ready = $true; break }
}
$mem = & wsl.exe -d $distro -u root --cd / -- bash -c "free -g | awk '/Mem:/{print \`$2}'"
if ($ready) { Write-Output "WSL-RESTART OK mem_total_gb=$mem"; exit 0 }
Write-Output "WSL-RESTART FAIL stack not ready after 300 s (mem_total_gb=$mem)"; exit 1
