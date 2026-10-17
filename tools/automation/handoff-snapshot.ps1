# Mechanical state snapshot for the living HANDOFF (Shay 2026-10-16): run by the PreCompact hook (writes the file)
# and by a SessionStart "compact" hook (-Print: puts it back into the compacted context).
# Writes C:\KenshiTestRuns\handoff-auto.md = newest `session-start.ps1 -Brief` output (HANDOFF "Right now", agent statuses,
# inflight, alerts, ledger, waker) + git head. Never fails the hook.
param([switch]$Print)
$ErrorActionPreference = 'SilentlyContinue'
# Hook stdin (PreCompact/SessionStart JSON): session_id, trigger/source.
$hin = $null
try { if ([Console]::IsInputRedirected) { $hin = [Console]::In.ReadToEnd() | ConvertFrom-Json } } catch {}
$out = 'C:\KenshiTestRuns\handoff-auto.md'
if ($Print) {
    if (Test-Path -LiteralPath $out) {
        "[handoff-auto: snapshot taken at the last compaction/checkpoint; testing/HANDOFF.md 'Right now' is the narrative source of truth. Re-run session-start.ps1 -Brief for live state.]"
        'OWED TO SHAY: report the REAL cost of this compaction (compact audit): C:\KenshiTestRuns\compact-audit\latest.md (written ~15 min after the compaction; tools/automation/compact-audit.py compacts --session <id>). Tell Shay when it exists, then record it in docs/COMPACT_AUDIT.md.'
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
# Compact audit: ~15 min after the compaction (enough post-compact turns), measure what it really cost.
if ($hin -and $hin.session_id) {
    $sid = "$($hin.session_id)"
    $cmd = "Start-Sleep 900; python -I '$ws	oolsutomation\compact-audit.py' compacts --session $sid | Out-Null"
    Start-Process -WindowStyle Hidden -FilePath powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd | Out-Null
}
exit 0
