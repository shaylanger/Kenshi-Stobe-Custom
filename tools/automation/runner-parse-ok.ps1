<#
runner-parse-ok.ps1 -Rig <lane> [-Files a.ps1,b.ps1]: pre-respawn guard for rig-runner.ps1 / rig-lane2*.ps1 (coordinator m102
2026-10-11: an uncommitted live edit of rig-runner.ps1 did not parse; every runner re-spawns from that file at its list
boundary after -Restart, so one bad edit would have killed every rig runner). Parses the runner scripts; prints
"PARSE OK" (exit 0, clears C:\KenshiTestRuns\ALERT-<lane>-restart.txt) or "PARSE FAIL <file>:<line> <message>" (exit 1,
writes that ALERT: rig-health.sh and the Stop hook block on it). The caller keeps running its old code and keeps the
.restart flag, so the respawn happens at the first boundary after the file is fixed.
Edit runner scripts in a copy (<name>.wip), parse + -SelfTest it, then move it into place in one step.
#>
param([string]$Rig = '', [string[]]$Files = @(), [string]$AlertDir = 'C:\KenshiTestRuns')
$auto = $PSScriptRoot
if (-not $Files.Count) { $Files = @('rig-runner.ps1', 'rig-lane2.ps1', 'rig-lane2-4080.ps1') | ForEach-Object { Join-Path $auto $_ } }
$bad = @()
foreach ($f in $Files) {
    if (-not (Test-Path -LiteralPath $f)) { $bad += "$(Split-Path $f -Leaf):0 file missing"; continue }
    $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
    if ($e) { $bad += "$(Split-Path $f -Leaf):$($e[0].Extent.StartLineNumber) $($e[0].Message) ($($e.Count) errors)" }
}
$al = if ($Rig) { Join-Path $AlertDir "ALERT-$Rig-restart.txt" } else { $null }
if ($bad) {
    $m = "PARSE FAIL $($bad -join ' | ')"
    if ($al) { Set-Content $al "ALERT $Rig $((Get-Date).ToString('HH:mm')) runner restart refused (old loop keeps running): $m" }
    $m; exit 1
}
if ($al -and (Test-Path $al)) { Remove-Item $al -ErrorAction SilentlyContinue }
'PARSE OK'; exit 0
