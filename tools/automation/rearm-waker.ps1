# rearm-waker.ps1 [-Batch <wsl path of out dir>] [-KillOnly]   (PI-34, Shay 2026-10-16)
# Kills stale event-wait.sh processes in WSL (a waker started with a bare & / disown is not tracked by the session and
# never wakes it), then prints the ONE correct command to run with the Bash tool's run_in_background=true.
# Never append & or disown to that command; restart it every time it wakes you.
param([string]$Batch = '', [switch]$KillOnly)
$null = & wsl.exe -d DwemerAI4Skyrim3 -u root -- pkill -f 'tools/automation/event-wait.sh'
"killed stale event-wait.sh processes (if any)"
if ($KillOnly) { return }
$b = if ($Batch) { " --batch $Batch" } else { '' }
"NOW run with Bash run_in_background=true (no trailing & / disown):"
"MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/event-wait.sh$b"
