# Mechanical state snapshot for the living HANDOFF (Shay 2026-10-16): run by the PreCompact hook (writes the file)
# and by a SessionStart "compact" hook (-Print: puts it back into the compacted context).
# Writes C:\KenshiTestRuns\handoff-auto.md = newest `session-start.ps1 -Brief` output (HANDOFF "Right now", agent statuses,
# inflight, alerts, ledger, waker) + git head. Never fails the hook.
param([switch]$Print)
$ErrorActionPreference = 'SilentlyContinue'
$out = 'C:\KenshiTestRuns\handoff-auto.md'
if ($Print) {
    if (Test-Path -LiteralPath $out) {
        "[handoff-auto: snapshot taken at the last compaction/checkpoint; testing/HANDOFF.md 'Right now' is the narrative source of truth. Re-run session-start.ps1 -Brief for live state.]"
        Get-Content -LiteralPath $out -TotalCount 220
    }
    exit 0
}
$ws = 'C:\KenshiModding'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# handoff-auto snapshot $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (mechanical; narrative is testing/HANDOFF.md)")
[void]$sb.AppendLine("git: " + (git -C $ws log --oneline -1) + " | uncommitted: " + ((git -C $ws status --porcelain | Measure-Object).Count))
$ss = & powershell -NoProfile -ExecutionPolicy Bypass -File "$ws\tools\automation\session-start.ps1" -Brief 2>&1 | Out-String
[void]$sb.AppendLine($ss)
$tmp = "$out.tmp"
Set-Content -LiteralPath $tmp -Value $sb.ToString() -Encoding UTF8
Move-Item -Force -LiteralPath $tmp -Destination $out
exit 0
