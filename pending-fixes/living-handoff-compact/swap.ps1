# Living handoff + auto-compact at ~150k: run by Shay. Backs up .claude\settings.json and .claude\context-meter.project.ps1 to C:\KenshiTestRuns\backup.
$ErrorActionPreference = 'Stop'
Set-Location C:\KenshiModding
python -I pending-fixes\living-handoff-compact\apply.py
Get-Content .claude\settings.json | Select-String -Pattern 'autoCompactWindow|PreCompact|"compact"'
Select-String -Path .claude\context-meter.project.ps1 -Pattern 'WARN = 120000|LIVING-HANDOFF' | Select-Object -First 2
'APPLIED: restart/continue the session; the new threshold takes effect on the next compaction check. Undo: copy the .pre-livehandoff-* files from C:\KenshiTestRuns\backup back.'
