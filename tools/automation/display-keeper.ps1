# display-keeper.ps1 -- keep the display awake while takes are filmed (HANDOFF gotcha: the display sleeps after 60 min
# without input and ffmpeg gdigrab then records BLACK frames). Holds SetThreadExecutionState(ES_CONTINUOUS |
# ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED) and writes a heartbeat every 20 s to C:\KenshiTestRuns\display-keeper.beat
# (take-preflight.sh pf_display checks it is < 60 s old and starts the keeper when it is not).
#   display-keeper.ps1 [-Minutes 240]   run (exits after -Minutes; the preflight restarts it for the next take)
#   display-keeper.ps1 -Status          print "KEEPER RUNNING age=<s>" or "KEEPER DOWN"
param([int]$Minutes = 240, [switch]$Status)
$beat = 'C:\KenshiTestRuns\display-keeper.beat'
if ($Status) {
  if (Test-Path $beat) { $age = [int]((Get-Date) - (Get-Item $beat).LastWriteTime).TotalSeconds
    if ($age -lt 60) { "KEEPER RUNNING age=$age"; exit 0 } }
  'KEEPER DOWN'; exit 1
}
Add-Type -Namespace KFP -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
$end = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $end) {
  [void][KFP.Power]::SetThreadExecutionState([uint32]'0x80000003')   # ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED
  Set-Content -Path $beat -Value "$PID $(Get-Date -Format s)" -Encoding ascii
  Start-Sleep -Seconds 20
}
[void][KFP.Power]::SetThreadExecutionState([uint32]'0x80000000'); Remove-Item $beat -ErrorAction SilentlyContinue
