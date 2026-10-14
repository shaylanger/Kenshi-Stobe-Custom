$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$install=Get-Content -LiteralPath (Join-Path $root 'install-main-steam.ps1') -Raw
$rollback=Get-Content -LiteralPath (Join-Path $root 'rollback-main-steam.ps1') -Raw
$reviewGatePath=Join-Path $root 'review-gate.ps1'
$reviewGateText=Get-Content -LiteralPath $reviewGatePath -Raw
$candidateReview='C:\KenshiModding\pending-fixes\portrait-black-render\native-auth-chatbox-portrait-composite-abi-fix-20261014\INDEPENDENT-REVIEW-769859CB.md'
$candidateReviewSha='3A61A9FFD83EDFFD5A266400A5ED275DEBDF18A2BE2AAA1CB4D3E3F75CA8E5CB'
$candidateSha='769859CB364D1C719F94FC465265BEF9C7EF6803D40FAD7F6B695E8425354E9A'
$reviewGateSha='ABEC75329C6A2B80CB0FD96E9164AAA0B2B1CCE3F3E467C48C97A107873F9307'
$installPath=Join-Path $root 'install-main-steam.ps1'
$installText=Get-Content -LiteralPath $installPath -Raw
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$ok,[string]$name){if(-not $ok){throw "SELFTEST FAIL $name"};$checks.Add($name)}
foreach($f in @('install-main-steam.ps1','rollback-main-steam.ps1','review-gate.ps1')){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f),[ref]$tokens,[ref]$errors)
  Check ($errors.Count -eq 0) "PowerShell syntax $f"
}
$targets=@('D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll','D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll')
foreach($t in $targets){Check ($install.Contains($t) -and $rollback.Contains($t)) "exact target allowlist $t"}
Check ($install.Contains('769859CB364D1C719F94FC465265BEF9C7EF6803D40FAD7F6B695E8425354E9A')) 'full candidate pin'
Check ($install.Contains($reviewGateSha) -and (Get-FileHash -LiteralPath $reviewGatePath -Algorithm SHA256).Hash -ceq $reviewGateSha) 'review parser exact hash pin'
Check ($install.Contains('AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C') -and $rollback.Contains('AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C')) 'both baseline pins'
Check ($install.Contains('File]::Replace') -and $rollback.Contains('File]::Replace')) 'atomic replacement only'
Check ($install.Contains('Assert-KenshiStopped') -and $rollback.Contains('Assert-KenshiStopped')) 'closed-game guard'
Check ($install.Contains('Assert-NoReparsePath') -and $rollback.Contains('Assert-NoReparsePath')) 'reparse-chain guard'
Check ($install.Contains('compare-and-swap refused') -and $rollback.Contains('Rollback CAS refused')) 'compare-and-swap guard'
Check ($install.Contains('Assert-Target $t $t.Baseline') -and $rollback.Contains('$current -cne $candidateSha -and $current -cne $t.Baseline')) 'target hashes checked before writes'
Check ($install.Contains('Get-Sha $t.Path) -cne $candidateSha') -and $rollback.Contains('Get-Sha $t.Path) -cne $t.Baseline')) 'post-write target hashes checked'
Check ($install.Contains('CopyTo($stream)') -and $install.Contains('Get-Sha $Dest') -and $install.Contains('Join-Path (Split-Path -Parent $t.Path)')) 'same-volume candidate temp is hashed'
Check ($install.Contains('if (Test-Path -LiteralPath $backup)') -and $install.Contains('Backup appeared after preflight')) 'backup is never overwritten'
Check ($install -match 'Assert-KenshiStopped\s+\[void\]\(Assert-Target' -and $install.Contains('File]::Replace($temps[')) 'per-target immediate pre-replace guards'
Check ($install.Contains('for ($i = $done.Count - 1; $i -ge 0; $i--)') -and $install.Contains('Restore-JustInstalled')) 'partial install rolls back already-replaced target'
Check ($install.Contains('Assert-NoReparsePath $Backup') -and $install.Contains('Assert-NoReparsePath $displaced')) 'automatic partial rollback rechecks reparse paths'
Check ($rollback.Contains('t.Current -ceq $t.Baseline){continue}') -and $rollback.Contains('File]::Replace($t.Backup,$t.Path,$t.Displaced')) 'rollback is idempotent and retains displaced candidate'
Check ($rollback.Contains('if(Test-Path -LiteralPath $backup){Assert-NoReparsePath $backup}') -and $rollback.Contains('if(Test-Path -LiteralPath $t.Displaced){Assert-NoReparsePath $t.Displaced}')) 'rollback backup/displaced paths reject reparse points'
Check ($rollback.Contains('Assert-NoReparsePath $t.Backup') -and $rollback.Contains('Assert-NoReparsePath $t.Displaced')) 'rollback rechecks backup/displaced immediately before replace'
Check (-not (($install+$rollback) -match '(?i)KenshiInst|\\4080\b|\bssh\b|install-dll\.ps1')) 'no other rig/instance route or generic installer'
Check (-not (($install+$rollback) -match '(?i)Start-Process|kenshi-ctl\.ps1.*launch|launch-ui\.ps1')) 'no game launch code'
. $reviewGatePath
Check (Test-CandidateReview $candidateReview $candidateReviewSha $candidateSha) 'real pinned review receipt parser positive case'
Check (-not (Test-CandidateReview $candidateReview ('0'*64) $candidateSha)) 'review receipt hash mismatch rejected'
Check (-not (Test-CandidateReview $candidateReview $candidateReviewSha ('0'*64))) 'review candidate mismatch rejected'
$tempReview=Join-Path $env:TEMP ('stobe-review-gate-negative-'+[guid]::NewGuid().ToString('N')+'.md')
try {
  $mutated=(Get-Content -LiteralPath $candidateReview -Raw) -replace '(?im)^Verdict:\s*\*\*CLEAR','Verdict: **REVISE'
  [IO.File]::WriteAllText($tempReview,$mutated,[Text.Encoding]::UTF8)
  $tempHash=(Get-FileHash -LiteralPath $tempReview -Algorithm SHA256).Hash
  Check (-not (Test-CandidateReview $tempReview $tempHash $candidateSha)) 'non-CLEAR pinned receipt rejected'
} finally { if(Test-Path -LiteralPath $tempReview){Remove-Item -LiteralPath $tempReview -Force} }
"RESULT 5090-MAIN-STEAM-PACKET-SELFTEST PASS checks=$($checks.Count) files=2 external_runtime_write=no"
