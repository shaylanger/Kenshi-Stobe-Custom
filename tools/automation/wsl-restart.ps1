# wsl-restart.ps1: restart WSL (applies %USERPROFILE%\.wslconfig) and bring the DwemerAI4Skyrim3 stack back.
# Run only between batches: Kenshi closed, no run-batch/fixer job inside WSL. Exit 0 = stack ready.
# After start_env: voice services stopped, wsl-cache-trim started + page cache dropped, STOBE server off (-Stobe: keep on).
param([switch]$Stobe)
$ErrorActionPreference = 'Stop'
$distro = 'DwemerAI4Skyrim3'
if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { Write-Output 'WSL-RESTART REFUSED: Kenshi is running'; exit 2 }
$busy = & wsl.exe -d $distro -u root --cd / -- bash -c 'pgrep -f [r]un-batch.sh >/dev/null && echo busy'
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
if ($ready) {
    # RAM rule (CLAUDE.md): start_env brings up Parakeet STT and PocketTTS; tests run without them
    $voice = & wsl.exe -d $distro -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/wsl-voice.sh all stop --wait 120
    # cache-trim: start_env reaches its own start line only after its Enter prompt (2026-10-11: not running after a
    # restart, page cache filled 9.5 of the 14 GB cap at boot and vmmem never gives it back on Windows 10)
    $trim = & wsl.exe -d $distro -u root --cd / -- bash -c 'bash /mnt/c/KenshiModding/tools/automation/wsl-cache-trim.sh start >/dev/null; sync; echo 1 > /proc/sys/vm/drop_caches; bash /mnt/c/KenshiModding/tools/automation/wsl-cache-trim.sh status | head -1'
    # STOBE stays off unless a STOBE batch needs it (CLAUDE.md "STOBE server off"); start_env turns it on. -Stobe keeps it on.
    $stobe = if ($Stobe) { 'on (kept)' } else { & wsl.exe -d $distro -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/stobe-server.sh off }
    Write-Output "WSL-RESTART OK mem_total_gb=$mem voice=$($voice -join ',') trim=$trim stobe=$stobe"; exit 0
}
Write-Output "WSL-RESTART FAIL stack not ready after 300 s (mem_total_gb=$mem)"; exit 1
