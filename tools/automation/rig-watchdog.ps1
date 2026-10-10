# rig-watchdog.ps1: RETIRED 2026-10-10, merged into rig-runner.ps1 (one daemon per rig runs the queued batch lists and
# raises ALERT-<rig>.txt when a rig is idle with an empty queue or a batch is stuck). Kept as a shim so old callers work:
#   -Ensure  stops a still-running old watchdog loop, then rig-runner.ps1 -Ensure
#   -Stop    rig-runner.ps1 -Stop
param([switch]$Ensure, [switch]$Stop)
$pidFile = 'C:\KenshiTestRuns\watchdog\watchdog.pid'
if (Test-Path $pidFile) {
    $p = [int](Get-Content $pidFile -Raw)
    if (Get-Process -Id $p -ErrorAction SilentlyContinue) { Stop-Process -Id $p -Force; "old watchdog loop $p stopped (replaced by rig-runner.ps1)" }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}
$r = Join-Path $PSScriptRoot 'rig-runner.ps1'
if ($Stop) { & powershell -NoProfile -ExecutionPolicy Bypass -File $r -Stop; exit 0 }
& powershell -NoProfile -ExecutionPolicy Bypass -File $r -Ensure
