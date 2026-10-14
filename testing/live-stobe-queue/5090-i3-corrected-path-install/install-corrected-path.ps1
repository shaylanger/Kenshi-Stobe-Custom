[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CandidateDll,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$CandidateSha256,
  [Parameter(Mandatory=$true)][string]$ReviewReceipt,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ReviewReceiptSha256,
  [Parameter(Mandatory=$true)][string]$BoundaryReceipt,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$BoundaryReceiptSha256,
  [Parameter(Mandatory=$true)][string]$BackupDirectory,
  [Parameter(Mandatory=$true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$Dumpbin,
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$root = 'D:\KenshiInst\3'
$target = Join-Path $root 'RE_Kenshi\mods\Stobe\Stobe.dll'
$wrongPath = Join-Path $root 'mods\Stobe\Stobe.dll'
$baseline = '40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D'
$blocked = 'BC9D2F91F8DD134CD8E8BA79514703C158923DC43EB2B8D9F4C361A8E34494A2'
$owner = '5090c-ui-setup-20261014'
$requiredClosedPid = 113932
$lock = 'C:\KenshiTestRuns\game-3.lock'
$checker = Join-Path $PSScriptRoot 'check-pe-imports.ps1'
Import-Module -Name (Join-Path $PSScriptRoot 'ReceiptTime.psm1') -Force
function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-InstanceMarker {
  $path = Join-Path $root 'instance.txt'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'D3 instance marker absent.' }
  $text = Get-Content -LiteralPath $path -Raw
  if ($text -cnotmatch '\Ainstance=3 synced=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} from=D:\\Steam\\steamapps\\common\\Kenshi\r?\n?\z') { throw 'D3 marker does not identify canonical instance 3.' }
}
function Assert-GameClosed {
  try {
    $required = Get-CimInstance Win32_Process -Filter "ProcessId=$requiredClosedPid"
    if ($required) { throw "Required game PID $requiredClosedPid is still present; refusing." }
    $games = @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'")
  } catch { throw "Cannot prove required game PID/process closure; refusing: $($_.Exception.Message)" }
  foreach ($p in $games) {
    if (-not $p.ExecutablePath) { throw "Cannot identify Kenshi PID $($p.ProcessId); refusing." }
    if ($p.ExecutablePath -ieq (Join-Path $root 'RE_Kenshi\kenshi_x64.exe')) { throw "D3 game PID $($p.ProcessId) still running; refusing. This script never stops Kenshi." }
  }
}
function Assert-Identity {
  Assert-InstanceMarker
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Actual target missing: $target" }
  if ((Resolve-Path -LiteralPath $target).Path -ine $target) { throw 'Actual target resolves elsewhere; refusing.' }
  if ($target -ieq $wrongPath) { throw 'Wrong-path guard failed: runtime target aliases D3 root mods path.' }
  if (-not (Test-Path -LiteralPath $lock -PathType Leaf) -or (Get-Content -LiteralPath $lock -TotalCount 1).Trim() -cne $owner) { throw 'D3 lock owner mismatch; refusing.' }
  Assert-GameClosed
}

$candidateExpected = $CandidateSha256.ToUpperInvariant()
if ($candidateExpected -ceq $blocked) { throw "REFUSED: known-broken BC9D candidate has an unresolved Ogre ABI import. Require a new candidate hash and exact review." }
if (-not (Test-Path -LiteralPath $CandidateDll -PathType Leaf)) { throw "Candidate missing: $CandidateDll" }
if (-not (Test-Path -LiteralPath $ReviewReceipt -PathType Leaf) -or -not (Test-Path -LiteralPath $BoundaryReceipt -PathType Leaf)) { throw 'Independent review or fresh boundary receipt missing.' }
if ((Get-Hash $ReviewReceipt) -cne $ReviewReceiptSha256.ToUpperInvariant()) { throw 'Review receipt SHA-256 mismatch.' }
if ((Get-Hash $BoundaryReceipt) -cne $BoundaryReceiptSha256.ToUpperInvariant()) { throw 'Boundary receipt SHA-256 mismatch.' }
if ((Get-Hash $CandidateDll) -cne $candidateExpected) { throw 'Candidate SHA-256 mismatch.' }
$review = Get-Content -LiteralPath $ReviewReceipt -Raw | ConvertFrom-Json
if ($review.status -cne 'CLEAR' -or $review.candidate_sha256 -cne $candidateExpected -or $review.target -ine $target) { throw 'Independent review does not CLEAR these exact candidate and target pins.' }
$boundaryRaw = Get-Content -LiteralPath $BoundaryReceipt -Raw
$boundary = $boundaryRaw | ConvertFrom-Json
if ($boundary.status -cne 'CLEAR' -or [int]$boundary.instance -ne 3 -or $boundary.target -ine $target -or
    $boundary.candidate_sha256 -cne $candidateExpected -or $boundary.owner -cne $owner -or $boundary.game_stopped -ne $true -or
    [string]::IsNullOrWhiteSpace([string]$boundary.review_verdict)) { throw 'Boundary receipt does not authorize exact target/candidate/owner.' }
$issued = (ConvertFrom-PinnedReceiptUtc -Json $boundaryRaw).ToUniversalTime()
$age = [DateTimeOffset]::UtcNow - $issued
if ($age -lt [TimeSpan]::Zero -or $age -gt [TimeSpan]::FromMinutes(10)) { throw "Boundary receipt stale or future-dated (age=$age)." }
Assert-Identity
$oldHash = Get-Hash $target
if ($oldHash -cne $baseline) { throw "Current-runtime CAS failed: target=$oldHash expected=$baseline" }
$wrongHash = if (Test-Path -LiteralPath $wrongPath -PathType Leaf) { Get-Hash $wrongPath } else { 'absent' }
"WRONG_PATH_IGNORED path=$wrongPath sha256=$wrongHash; install target remains $target"
"IMPORT_EXPORT_GATE candidate=$CandidateDll"
& $checker -DllPath $CandidateDll -GameRoot $root -SystemRoot "$env:WINDIR\System32" -Dumpbin $Dumpbin
if ($LASTEXITCODE -ne 0) { throw 'Candidate failed exact installed dependency import/export gate.' }
"PLAN ONLY: actualTarget=$target priorRuntime=$oldHash candidate=$candidateExpected rollbackRoot=$BackupDirectory"
if (-not $Apply) { 'No files changed. Pass -Apply only at the approved future install boundary.'; exit 0 }

if (Test-Path -LiteralPath $BackupDirectory) { throw "Rollback directory already exists: $BackupDirectory" }
$parent = Split-Path -Parent $target
$backupParent = Split-Path -Parent $BackupDirectory
if ([IO.Path]::GetPathRoot($parent) -ine [IO.Path]::GetPathRoot($backupParent)) { throw 'Rollback must be on the target volume.' }
New-Item -ItemType Directory -Path $BackupDirectory | Out-Null
$backupFile = Join-Path $BackupDirectory 'Stobe.dll.before-corrected-path'
$temp = Join-Path $parent ('.Stobe.dll.install-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
  Copy-Item -LiteralPath $CandidateDll -Destination $temp
  if ((Get-Hash $temp) -cne $candidateExpected) { throw 'Same-volume staged candidate hash mismatch.' }
  Assert-Identity
  if ((Get-Hash $target) -cne $baseline) { throw 'Actual runtime target changed after preflight.' }
  [IO.File]::Replace($temp, $target, $backupFile, $true)
  $installed = Get-Hash $target
  $saved = Get-Hash $backupFile
  if ($installed -cne $candidateExpected -or $saved -cne $baseline) { throw 'Post-replace verification failed; preserve state for reviewed recovery.' }
  [ordered]@{status='INSTALLED';target=$target;candidate_sha256=$installed;rollback=$backupFile;rollback_sha256=$saved;owner=$owner;installed_utc=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupDirectory 'install-receipt.json') -Encoding UTF8
  'INSTALL PASS: actual runtime target and rollback hashes verified.'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}
