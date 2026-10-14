<#
  Exact Main Steam Stobe install. Dry-run by default; writes only with -Apply.
  This packet is pinned to candidate 769859... and the two observed AEF baselines.
  Do not use for a test-instance or another rig.
#>
[CmdletBinding()]
param([switch]$Apply,[ValidatePattern('^mainsteam-769859-\d{8}T\d{6}Z$')][string]$OperationId='')
$ErrorActionPreference = 'Stop'

$candidate = 'C:\KenshiModding\pending-fixes\portrait-black-render\native-auth-chatbox-portrait-composite-abi-fix-20261014\build-v100\Stobe.dll'
$candidateSha = '769859CB364D1C719F94FC465265BEF9C7EF6803D40FAD7F6B695E8425354E9A'
$candidateReview = 'C:\KenshiModding\pending-fixes\portrait-black-render\native-auth-chatbox-portrait-composite-abi-fix-20261014\INDEPENDENT-REVIEW-769859CB.md'
$candidateReviewSha = '3A61A9FFD83EDFFD5A266400A5ED275DEBDF18A2BE2AAA1CB4D3E3F75CA8E5CB'
$reviewGate = Join-Path $PSScriptRoot 'review-gate.ps1'
$reviewGateSha = 'ABEC75329C6A2B80CB0FD96E9164AAA0B2B1CCE3F3E467C48C97A107873F9307'
$targets = @(
  [pscustomobject]@{ Path='D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll'; Baseline='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'; Label='RE_Kenshi' },
  [pscustomobject]@{ Path='D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll'; Baseline='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'; Label='root-mods' }
)
$op = if ($OperationId) { $OperationId } else { 'mainsteam-769859-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') }

function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-NoReparsePath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  $drive = [IO.Path]::GetPathRoot($full)
  $tail = $full.Substring($drive.Length).TrimEnd('\')
  $parts = $tail.Split('\')
  $cur = $drive.TrimEnd('\')
  foreach ($part in $parts) {
    $cur = Join-Path $cur $part
    if (-not (Test-Path -LiteralPath $cur)) { throw "Expected exact path component missing: $cur" }
    $item = Get-Item -LiteralPath $cur -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point forbidden on exact target chain: $cur" }
  }
}
function Assert-KenshiStopped {
  # Any Kenshi process blocks a Main Steam replacement; inaccessible/uncertain enumeration fails closed.
  try { $running = @(Get-Process -Name 'kenshi_x64' -ErrorAction Stop) }
  catch {
    if ($_.Exception.Message -like 'Cannot find a process with the name*') { return }
    throw "Cannot establish that Kenshi is stopped: $($_.Exception.Message)"
  }
  if ($running.Count -ne 0) { throw 'Kenshi is running; close the game before installing or rolling back.' }
}
function Assert-Review {
  if (-not (Test-CandidateReview $candidateReview $candidateReviewSha $candidateSha)) { throw 'Review must be the exact pinned CLEAR receipt and explicitly pin the exact candidate SHA-256.' }
  return (Get-Sha $candidateReview)
}
function Assert-Target([object]$Target, [string]$ExpectedSha) {
  Assert-NoReparsePath $Target.Path
  if (-not (Test-Path -LiteralPath $Target.Path -PathType Leaf)) { throw "Target is not a regular file: $($Target.Path)" }
  $actual = Get-Sha $Target.Path
  if ($actual -cne $ExpectedSha) { throw "$($Target.Label) compare-and-swap refused: current=$actual expected=$ExpectedSha" }
  return $actual
}
function Write-ExactTemp([string]$Source, [string]$Dest, [string]$ExpectedSha) {
  $stream = [IO.File]::Open($Dest, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $input = [IO.File]::OpenRead($Source); try { $input.CopyTo($stream); $stream.Flush($true) } finally { $input.Dispose() } }
  finally { $stream.Dispose() }
  if ((Get-Sha $Dest) -cne $ExpectedSha) { throw "Staged same-volume temp hash mismatch: $Dest" }
}
function Restore-JustInstalled([object]$Target, [string]$Backup, [string]$InstalledSha, [string]$BaselineSha, [string]$OpId) {
  $displaced = $Target.Path + '.failed-candidate-' + $OpId + '.dll'
  Assert-NoReparsePath $Target.Path
  Assert-NoReparsePath $Backup
  if (Test-Path -LiteralPath $displaced) { Assert-NoReparsePath $displaced }
  if ((Get-Sha $Target.Path) -cne $InstalledSha -or (Get-Sha $Backup) -cne $BaselineSha -or (Test-Path -LiteralPath $displaced)) {
    throw "Automatic rollback CAS refused for $($Target.Label); preserve all files for manual review."
  }
  [IO.File]::Replace($Backup, $Target.Path, $displaced, $true)
  if ((Get-Sha $Target.Path) -cne $BaselineSha -or (Get-Sha $displaced) -cne $InstalledSha) { throw "Automatic rollback verification failed for $($Target.Label)." }
}

if ((Get-Sha $reviewGate) -cne $reviewGateSha) { throw 'Review parser helper hash mismatch.' }
. $reviewGate
Assert-KenshiStopped
Assert-NoReparsePath $candidate
if (-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or (Get-Sha $candidate) -cne $candidateSha) { throw 'Candidate missing or does not match the full pinned SHA-256.' }
$reviewSha = Assert-Review
foreach ($t in $targets) { [void](Assert-Target $t $t.Baseline) }
foreach ($t in $targets) {
  $backup = $t.Path + '.pre-' + $op + '.bak'
  if (Test-Path -LiteralPath $backup) { throw "Refusing to overwrite existing backup: $backup" }
}
"PLAN: candidate=$candidate sha256=$candidateSha review_sha256=$reviewSha operation=$op"
foreach ($t in $targets) { "PLAN: $($t.Label) target=$($t.Path) baseline=$($t.Baseline) backup=$($t.Path).pre-$op.bak" }
if (-not $Apply) { 'No files changed. Review the plan; pass -Apply only after the exact-candidate build and install packet are CLEAR.'; exit 0 }

# Revalidate both targets and the stopped-game gate immediately before any mutation.
Assert-KenshiStopped
if ((Get-Sha $candidate) -cne $candidateSha -or (Assert-Review) -cne $reviewSha) { throw 'Candidate/review changed after preflight.' }
foreach ($t in $targets) { [void](Assert-Target $t $t.Baseline) }
$temps = @{}
$backups = @{}
$done = [Collections.Generic.List[object]]::new()
try {
  foreach ($t in $targets) {
    $temp = Join-Path (Split-Path -Parent $t.Path) ('.Stobe-' + $op + '-' + $t.Label + '.tmp')
    Write-ExactTemp $candidate $temp $candidateSha
    $temps[$t.Label] = $temp
    $backups[$t.Label] = $t.Path + '.pre-' + $op + '.bak'
  }
  foreach ($t in $targets) { [void](Assert-Target $t $t.Baseline) }
  foreach ($t in $targets) {
    Assert-KenshiStopped
    [void](Assert-Target $t $t.Baseline)
    Assert-NoReparsePath $temps[$t.Label]
    if ((Get-Sha $temps[$t.Label]) -cne $candidateSha) { throw "Temp changed after staging: $($t.Label)" }
    if (Test-Path -LiteralPath $backups[$t.Label]) { throw "Backup appeared after preflight; refusing to overwrite: $($backups[$t.Label])" }
    [IO.File]::Replace($temps[$t.Label], $t.Path, $backups[$t.Label], $true)
    $done.Add($t)
    if ((Get-Sha $t.Path) -cne $candidateSha -or (Get-Sha $backups[$t.Label]) -cne $t.Baseline) { throw "Post-replace hash check failed: $($t.Label)" }
  }
} catch {
  for ($i = $done.Count - 1; $i -ge 0; $i--) { Restore-JustInstalled $done[$i] $backups[$done[$i].Label] $candidateSha $done[$i].Baseline $op }
  throw
} finally {
  foreach ($t in $targets) { $tmp = $temps[$t.Label]; if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force } }
}
$receipt = Join-Path $PSScriptRoot ('INSTALL-' + $op + '.receipt.md')
$lines = @('# Main Steam Stobe install receipt', '', "- Candidate SHA-256: $candidateSha", "- Review receipt SHA-256: $reviewSha", "- Operation: $op", '- Game launch/reload: not performed by installer.', '')
foreach ($t in $targets) { $lines += "- $($t.Label): $($t.Path); installed=$((Get-Sha $t.Path)); rollback=$($backups[$t.Label]); rollback_sha=$((Get-Sha $backups[$t.Label]))" }
$lines | Set-Content -LiteralPath $receipt -Encoding UTF8
"INSTALL PASS: both allowlisted Main Steam files verified; receipt=$receipt"
