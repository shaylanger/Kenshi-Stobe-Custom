# review-verdict.ps1: write a sheet/video/frame review verdict to a file the moment it is made, so the image never
# has to be looked at again (images are the coordinator's biggest context cost) and a handoff loses nothing.
#   review-verdict.ps1 <row> <PASS|FAIL|REJECT-SHEET> "<sheet path>" "<what was seen, one line>"
# Appends to C:\KenshiTestRuns\review-verdicts.tsv; session-start.ps1 prints the newest lines.
param(
    [Parameter(Mandatory)][string]$Row,
    [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'REJECT-SHEET')][string]$Verdict,
    [Parameter(Mandatory)][string]$Sheet,
    [Parameter(Mandatory)][string]$Note
)
$f = 'C:\KenshiTestRuns\review-verdicts.tsv'
"$(Get-Date -Format 'yyyy-MM-dd HH:mm')`t$Row`t$Verdict`t$Sheet`t$Note" | Add-Content -LiteralPath $f -Encoding UTF8
"RESULT $Row $Verdict (review) $Note"
