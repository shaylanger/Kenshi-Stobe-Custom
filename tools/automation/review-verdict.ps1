# review-verdict.ps1: write a sheet/video/frame review verdict to a file the moment it is made, so the image never
# has to be looked at again (images are the coordinator's biggest context cost) and a handoff loses nothing.
#   review-verdict.ps1 <row> <PASS|FAIL|REJECT-SHEET> "<sheet path>" "<what was seen, one line>" [-Class pose|setup] [-Build <id>] [-Finder review|shay]
# Appends to C:\KenshiTestRuns\review-verdicts.tsv; session-start.ps1 prints the newest lines.
# FAIL / REJECT-SHEET also append a PENDING row to the animation lab's lists so a review flaw can't be forgotten
# (Shay 2026-10-10 "review flaws feed the lab"): pose flaws -> STATUS.md "Misses", take/setup flaws (REJECT-SHEET, or a
# note naming wall/slope/cursor/night/dark/black/bystander/combat/unloaded/popup/label/end/frame/setup) -> SETUP_MISSES.md
# (harness docs/animlab). The lab maintainer turns each PENDING row into a check (Misses) / a take-preflight check (setup).
param(
    [Parameter(Mandatory)][string]$Row,
    [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'REJECT-SHEET')][string]$Verdict,
    [Parameter(Mandatory)][string]$Sheet,
    [Parameter(Mandatory)][string]$Note,
    [ValidateSet('', 'pose', 'setup')][string]$Class = '',
    [string]$Build = '-',
    [ValidateSet('review', 'shay')][string]$Finder = 'review'
)
$f = if ($env:REVIEW_VERDICTS) { $env:REVIEW_VERDICTS } else { 'C:\KenshiTestRuns\review-verdicts.tsv' }
"$(Get-Date -Format 'yyyy-MM-dd HH:mm')`t$Row`t$Verdict`t$Sheet`t$Note" | Add-Content -LiteralPath $f -Encoding UTF8
if ($Verdict -ne 'PASS') {
    $docs = if ($env:ANIMLAB_DOCS) { $env:ANIMLAB_DOCS } else { 'C:\KenshiModding\Kenshi-Automation-Harness\docs\animlab' }   # env: tests
    if (-not $Class) {
        $setupRx = '(?i)wall|slope|cursor|night|dark|black|bystander|combat|unloaded|popup|label|past the end|end label|setup|blur|cropped|judgeable|camera|jammed'
        $Class = if ($Verdict -eq 'REJECT-SHEET' -or $Note -match $setupRx) { 'setup' } else { 'pose' }
    }
    $clean = ($Note -replace '\|', '/' -replace '[\r\n]+', ' ').Trim()
    $line = "- $(Get-Date -Format 'yyyy-MM-dd') | $Row ($Verdict) | $clean | $Sheet | $Build | PENDING (review-verdict.ps1: needs a lab check) found:$Finder"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        if ($Class -eq 'setup') {
            $p = Join-Path $docs 'SETUP_MISSES.md'; $t = [IO.File]::ReadAllText($p, $utf8)
            $i = $t.IndexOf("`nWiring:")   # rows end before the Wiring paragraph
            if ($i -lt 0) { $t = $t.TrimEnd() + "`n" + $line + "`n" } else { $t = $t.Substring(0, $i).TrimEnd() + "`n" + $line + "`n" + $t.Substring($i) }
        } else {
            $p = Join-Path $docs 'STATUS.md'; $t = [IO.File]::ReadAllText($p, $utf8)
            $s = $t.IndexOf('## Misses (game found, lab missed)'); if ($s -lt 0) { throw 'Misses section not found' }
            $e = $t.IndexOf("`n## ", $s + 5); if ($e -lt 0) { $e = $t.Length }
            $t = $t.Substring(0, $e).TrimEnd() + "`n" + $line + "`n" + $t.Substring($e)
        }
        [IO.File]::WriteAllText($p, $t, $utf8)
        "lab row added ($Class): $p"
    } catch { "WARNING lab row NOT added ($($_.Exception.Message)); add it by hand: $line" }
}
"RESULT $Row $Verdict (review) $Note"
