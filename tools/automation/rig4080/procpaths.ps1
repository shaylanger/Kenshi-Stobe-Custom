<#
procpaths.ps1 (4080 rig, C:\KAH\runner\procpaths.ps1; copied there by rig-runner.ps1 -Rig 4080 at start): one line per running
bash/sh/python/timeout process: "<pid> <name> <command line>". rig-runner.ps1 reads the repo scripts in these command lines
to defer syncing files a still-running background analysis uses (never overwrite a script a running batch executes).
#>
Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(bash|sh|python[0-9.]*|py|timeout)\.exe$' } | ForEach-Object { "$($_.ProcessId) $($_.Name) $($_.CommandLine)" }
"PROCPATHS-END"
