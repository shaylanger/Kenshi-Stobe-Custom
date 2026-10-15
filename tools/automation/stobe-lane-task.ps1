<#
stobe-lane-task.ps1 -Lane <i4> -Action register|start|stop|status [-Defs <lane-defs json>]   (runs ON the 4080, PowerShell 5)
The Windows scheduled task that keeps one isolated lane's private STOBE backend alive: it runs
`wsl.exe -d <distro> -u root --exec bash <dir>\stobe-lane-backend.sh <lane> supervise` (start everything idempotently, then sleep
forever so the WSL session and its children stay up), the same way the lane-i3 task StobeStandalone4080Backend does. Task name, ports and
paths come from lane-defs.4080.json ("task"). Same task settings as the i3 task: interactive token (user Shay), no battery
limits, no time limit, IgnoreNew. 'start' is idempotent (a second start while it runs is ignored).
From the 5090: ssh 4080 powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiTestRuns\lane-i4\stobe-lane-task.ps1 -Lane i4 -Action register
#>
param([Parameter(Mandatory = $true)][string]$Lane, [ValidateSet('register', 'start', 'stop', 'status')][string]$Action = 'status',
      [string]$Defs = 'C:\KenshiTestRuns\lane-i4\lane-defs.4080.json')
$ErrorActionPreference = 'Stop'
$d = Get-Content $Defs -Raw | ConvertFrom-Json
$L = $d.lanes.$Lane
if (-not $L) { throw "no lane '$Lane' in $Defs" }
$task = $L.task
$script = '/mnt/c/KenshiTestRuns/lane-i4/stobe-lane-backend.sh'
switch ($Action) {
  'register' {
    if ("$($L.owner_note)" -notlike 'built by*') { throw "lane $Lane is not owned by this tooling ($($L.owner_note))" }
    $a = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wsl.exe' -Argument "-d $($d.wsl_distro) -u root --exec bash $script $Lane supervise"
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    Register-ScheduledTask -TaskName $task -Action $a -Settings $s -Principal $p -Description "Dedicated private standalone test backend for lane $Lane; no production services" -Force | Out-Null
    "registered $task"
  }
  'start' { Start-ScheduledTask -TaskName $task; "started $task" }
  'stop' { Stop-ScheduledTask -TaskName $task; "stopped $task (the backend processes stay up; stop them with stobe-lane-backend.sh $Lane stop)" }
  'status' { $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue; if ($t) { "$task state=$($t.State)" } else { "$task not registered" } }
}
