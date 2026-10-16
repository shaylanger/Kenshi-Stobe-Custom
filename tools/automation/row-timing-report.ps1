# row-timing-report.ps1: summarise C:\KenshiTestRuns\row-timing.log written by go-row.sh / go-batch.sh (PI-09).
#   row-timing-report.ps1 [-Lane <lane>] [-Since '2026-10-15T18:00'] [-Log <path>] [-Raw]
# Log line (one per go-row call): <time> lane=<lane> row=<ROW> verdict=<PASS|FAIL|SETUP-FAIL|GATED|PREFLIGHT-FAIL|NEEDS-FIXER|DRY-RUN|NOLINE>
#   wall_s=<seconds> steps=<say steps run> attempt=<n|blocked|dry> agent=<KAH_AGENT_NAME or ->
# Prints per row: runs, verdict counts, wall seconds avg/min/max (only runs that actually executed: PASS FAIL SETUP-FAIL GATED), blocked count.
# Tool calls / tokens are NOT in the log (go-row.sh cannot see them); nothing here is estimated.
# Baseline (hand-run row 07-a): override with C:\KenshiTestRuns\row-timing-baseline.txt (first lines are printed verbatim).
param([string]$Lane = '', [string]$Since = '', [string]$Log = 'C:\KenshiTestRuns\row-timing.log', [switch]$Raw)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Log)) { Write-Output "NO row-timing.log yet ($Log): no row has been run through go-row.sh / go-batch.sh since PI-09 was installed."; exit 0 }
$since = if ($Since) { [datetime]$Since } else { [datetime]::MinValue }
$rows = foreach ($l in Get-Content $Log) {
  if ($l -notmatch '^(\S+) (.*)$') { continue }
  $h = @{ time = $Matches[1] }
  foreach ($m in [regex]::Matches($Matches[2], '(\w+)=(\S*)')) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
  if (-not $h.row) { continue }
  try { if ([datetime]$h.time -lt $since) { continue } } catch { continue }
  if ($Lane -and $h.lane -ne $Lane) { continue }
  [pscustomobject]@{ Time = $h.time; Lane = $h.lane; Row = $h.row; Verdict = $h.verdict; Wall = [int]($h.wall_s); Steps = [int]($h.steps); Attempt = $h.attempt; Agent = $h.agent }
}
$rows = @($rows)
if ($Raw) { $rows | Format-Table -AutoSize | Out-String -Width 200; exit 0 }
if (-not $rows.Count) { Write-Output "row-timing.log has no matching lines (Lane='$Lane' Since='$Since')."; exit 0 }
$ran = @('PASS', 'FAIL', 'SETUP-FAIL', 'GATED')
function Cnt($grp, $v) { @($grp | Where-Object { $_.Verdict -eq $v }).Count }
Write-Output ("ROW-TIMING {0} lines, {1} .. {2}{3}" -f $rows.Count, $rows[0].Time, $rows[-1].Time, $(if ($Lane) { " lane=$Lane" } else { '' }))
Write-Output ('{0,-6} {1,4} {2,4} {3,4} {4,5} {5,5} {6,7} {7,7} {8,7} {9,7} {10,7}' -f 'row', 'runs', 'PASS', 'FAIL', 'SETUP', 'GATED', 'blocked', 'avg_s', 'min_s', 'max_s', 'steps')
foreach ($g in ($rows | Group-Object Row | Sort-Object Name)) {
  $x = @($g.Group | Where-Object { $ran -contains $_.Verdict })
  $w = @($x | ForEach-Object { $_.Wall })
  $avg = '-'; $min = '-'; $max = '-'; $st = '-'
  if ($w.Count) {
    $avg = [math]::Round(($w | Measure-Object -Average).Average, 0)
    $min = ($w | Measure-Object -Minimum).Minimum
    $max = ($w | Measure-Object -Maximum).Maximum
    $st = [math]::Round((($x | ForEach-Object { $_.Steps } | Measure-Object -Average).Average), 1)
  }
  Write-Output ('{0,-6} {1,4} {2,4} {3,4} {4,5} {5,5} {6,7} {7,7} {8,7} {9,7} {10,7}' -f $g.Name, $x.Count, (Cnt $g.Group 'PASS'), (Cnt $g.Group 'FAIL'), (Cnt $g.Group 'SETUP-FAIL'), (Cnt $g.Group 'GATED'), ((Cnt $g.Group 'NEEDS-FIXER') + (Cnt $g.Group 'PREFLIGHT-FAIL')), $avg, $min, $max, $st)
}
$all = @($rows | Where-Object { $ran -contains $_.Verdict })
if ($all.Count) {
  $tot = ($all | Measure-Object Wall -Sum).Sum
  Write-Output ("TOTAL {0} executed rows, {1} s wall ({2} min), avg {3} s/row, PASS {4} FAIL {5} SETUP-FAIL {6} GATED {7}; blocked by attempt guard {8}, preflight-failed {9}" -f
    $all.Count, $tot, [math]::Round($tot / 60, 1), [math]::Round($tot / $all.Count, 0),
    (Cnt $all 'PASS'), (Cnt $all 'FAIL'), (Cnt $all 'SETUP-FAIL'), (Cnt $all 'GATED'), (Cnt $rows 'NEEDS-FIXER'), (Cnt $rows 'PREFLIGHT-FAIL'))
}
# baseline comparison (07-a hand run)
$bf = 'C:\KenshiTestRuns\row-timing-baseline.txt'
if (Test-Path $bf) { Write-Output ('BASELINE ' + ((Get-Content $bf -TotalCount 3) -join ' | ')) }
else { Write-Output 'BASELINE row 07-a hand-run (imm26-5090-ctxop3, 2026-10-15): one operator used a whole ~200k-token context on it (then respawned as ctxop32/ctxop322); wall time was not recorded. Target: one RESULT line per row at < 5k tokens (docs/PROCESS_IDEAS.md PI-09).' }
$r07 = @($rows | Where-Object { $_.Row -eq '07-a' -and $ran -contains $_.Verdict })
if ($r07.Count) { $last = $r07[-1]; Write-Output ('07-a via go-row.sh: {0} run(s), last verdict {1}, wall {2} s, steps {3} (token use is not logged; compare with the operator status/agent report)' -f $r07.Count, $last.Verdict, $last.Wall, $last.Steps) }
else { Write-Output '07-a via go-row.sh: no run in this log (07-a is not yet ported to go-row.sh), so no like-for-like wall time exists; the per-row average above is the number to compare.' }
