[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CandidateDll,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$CandidateSha256,
  [Parameter(Mandatory=$true)][string]$BoundaryReceipt,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$BoundaryReceiptSha256,
  [Parameter(Mandatory=$true)][string]$BackupDirectory,
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$root = 'D:\KenshiInst\3'
$target = Join-Path $root 'mods\Stobe\Stobe.dll'
$baseline = 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'
$owner = '5090c-ui-setup-20261014'
$lock = 'C:\KenshiTestRuns\game-3.lock'
$candidateExpected = $CandidateSha256.ToUpperInvariant()
Import-Module -Name (Join-Path $PSScriptRoot 'ReceiptTime.psm1') -Force

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-InstanceMarker {
  $markerPath = Join-Path $root 'instance.txt'
  if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'D3 instance marker absent.' }
  $marker = Get-Content -LiteralPath $markerPath -Raw
  if ($marker -cnotmatch '\Ainstance=3 synced=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} from=D:\\Steam\\steamapps\\common\\Kenshi\r?\n?\z') {
    throw 'D3 instance marker content is not the expected instance=3 synced=<timestamp> from=<canonical Kenshi source> format.'
  }
}
function Assert-D3Stopped {
  $found = @()
  foreach ($p in Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'") {
    if (-not $p.ExecutablePath) { throw "Cannot verify executable path for Kenshi PID $($p.ProcessId); refusing." }
    if ($p.ExecutablePath -ieq (Join-Path $root 'RE_Kenshi\kenshi_x64.exe')) { $found += [int]$p.ProcessId }
  }
  if ($found.Count) { throw "D3 Kenshi still running (PID(s): $($found -join ', ')); refusing. This script never stops the game." }
}
function Assert-Identity {
  Assert-InstanceMarker
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Target missing: $target" }
  $resolved = (Resolve-Path -LiteralPath $target).Path
  if ($resolved -ine $target) { throw "Unexpected target resolution: $resolved" }
  if (-not (Test-Path -LiteralPath $lock -PathType Leaf)) { throw "Expected owner lock absent: $lock" }
  if ((Get-Content -LiteralPath $lock -TotalCount 1).Trim() -cne $owner) { throw 'D3 lock owner mismatch; refusing.' }
  Assert-D3Stopped
}

if (-not (Test-Path -LiteralPath $CandidateDll -PathType Leaf)) { throw "Candidate missing: $CandidateDll" }
if (-not (Test-Path -LiteralPath $BoundaryReceipt -PathType Leaf)) { throw "Boundary receipt missing: $BoundaryReceipt" }
if ((Get-Hash $BoundaryReceipt) -cne $BoundaryReceiptSha256.ToUpperInvariant()) { throw 'Boundary receipt SHA-256 mismatch.' }
$receiptRaw = Get-Content -LiteralPath $BoundaryReceipt -Raw
$receipt = $receiptRaw | ConvertFrom-Json
if ($receipt.status -cne 'CLEAR' -or [int]$receipt.instance -ne 3 -or $receipt.target -ine $target -or
    $receipt.candidate_sha256 -cne $candidateExpected -or $receipt.owner -cne $owner -or
    $receipt.game_stopped -ne $true -or [string]::IsNullOrWhiteSpace([string]$receipt.review_verdict)) {
  throw 'Boundary receipt fields do not exactly authorize this candidate and target.'
}
$issued = (ConvertFrom-PinnedReceiptUtc -Json $receiptRaw).ToUniversalTime()
$age = [DateTimeOffset]::UtcNow - $issued
if ($age -lt [TimeSpan]::Zero -or $age -gt [TimeSpan]::FromMinutes(10)) { throw "Boundary receipt is not fresh (age=$age; maximum 10 minutes)." }
$candidateActual = Get-Hash $CandidateDll
if ($candidateActual -cne $candidateExpected) { throw "Candidate pin mismatch: got $candidateActual" }
Assert-Identity
$targetHash = Get-Hash $target
if ($targetHash -cne $baseline) { throw "Baseline compare-and-swap failed: target is $targetHash" }

"PLAN ONLY: target=$target baseline=$targetHash candidate=$candidateActual backup=$BackupDirectory"
if (-not $Apply) { 'No files changed. Pass -Apply only at the approved install boundary.'; exit 0 }

if (Test-Path -LiteralPath $BackupDirectory) { throw "Backup directory already exists: $BackupDirectory" }
$parent = Split-Path -Parent $target
$backupParent = Split-Path -Parent $BackupDirectory
if (([IO.Path]::GetPathRoot($parent)) -ine ([IO.Path]::GetPathRoot($backupParent))) { throw 'Backup must be on the target volume for transactional replacement.' }
New-Item -ItemType Directory -Path $BackupDirectory | Out-Null
$backupFile = Join-Path $BackupDirectory 'Stobe.dll.before-composite'
$temp = Join-Path $parent ('.Stobe.dll.install-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
  Copy-Item -LiteralPath $CandidateDll -Destination $temp
  if ((Get-Hash $temp) -cne $candidateExpected) { throw 'Same-volume staged candidate hash mismatch.' }
  Assert-Identity
  if ((Get-Hash $target) -cne $baseline) { throw 'Target changed after preflight; refusing replacement.' }
  [IO.File]::Replace($temp, $target, $backupFile, $true)
  $installed = Get-Hash $target
  $saved = Get-Hash $backupFile
  if ($installed -cne $candidateExpected -or $saved -cne $baseline) {
    throw "Post-replace verification mismatch (installed=$installed backup=$saved); preserve state for reviewed recovery."
  }
  [ordered]@{ status='INSTALLED'; instance=3; target=$target; candidate_sha256=$installed; backup=$backupFile; backup_sha256=$saved; owner=$owner; installed_utc=[DateTime]::UtcNow.ToString('o') } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupDirectory 'install-receipt.json') -Encoding UTF8
  'INSTALL PASS: target and rollback backup hashes verified.'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}
