[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BackupDll,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$CandidateSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$BackupSha256,
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$root = 'D:\KenshiInst\3'
$target = Join-Path $root 'mods\Stobe\Stobe.dll'
$owner = '5090c-ui-setup-20261014'
$lock = 'C:\KenshiTestRuns\game-3.lock'
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
  foreach ($p in Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'") {
    if (-not $p.ExecutablePath) { throw "Cannot verify executable path for Kenshi PID $($p.ProcessId); refusing." }
    if ($p.ExecutablePath -ieq (Join-Path $root 'RE_Kenshi\kenshi_x64.exe')) { throw "D3 Kenshi still running (PID $($p.ProcessId)); refusing. This script never stops the game." }
  }
}
Assert-InstanceMarker
if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or -not (Test-Path -LiteralPath $BackupDll -PathType Leaf)) { throw 'Target or rollback DLL missing.' }
if ((Resolve-Path -LiteralPath $target).Path -ine $target) { throw 'Unexpected target resolution.' }
if (-not (Test-Path -LiteralPath $lock -PathType Leaf) -or (Get-Content -LiteralPath $lock -TotalCount 1).Trim() -cne $owner) { throw 'D3 lock owner mismatch; refusing.' }
Assert-D3Stopped
$want = $CandidateSha256.ToUpperInvariant(); $old = $BackupSha256.ToUpperInvariant()
$now = Get-Hash $target; $saved = Get-Hash $BackupDll
if ($now -cne $want) { throw "Rollback CAS failed: current target=$now, expected candidate=$want" }
if ($saved -cne $old -or $old -cne 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C') { throw "Rollback backup hash mismatch: $saved" }
"PLAN ONLY: target candidate=$now; rollback source=$saved"
if (-not $Apply) { 'No files changed. Pass -Apply only at an authorized rollback boundary.'; exit 0 }
$parent = Split-Path -Parent $target
$temp = Join-Path $parent ('.Stobe.dll.rollback-' + [guid]::NewGuid().ToString('N') + '.tmp')
$displaced = Join-Path (Split-Path -Parent $BackupDll) ('Stobe.dll.displaced-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
try {
  Copy-Item -LiteralPath $BackupDll -Destination $temp
  if ((Get-Hash $temp) -cne $old) { throw 'Rollback temp hash mismatch.' }
  Assert-D3Stopped
  if ((Get-Hash $target) -cne $want) { throw 'Target changed after rollback preflight; refusing replacement.' }
  [IO.File]::Replace($temp, $target, $displaced, $true)
  if ((Get-Hash $target) -cne $old -or (Get-Hash $displaced) -cne $want) { throw 'Post-rollback verification mismatch; preserve state for reviewed recovery.' }
  [ordered]@{ status='ROLLED_BACK'; instance=3; target=$target; restored_sha256=(Get-Hash $target); displaced_candidate=$displaced; displaced_sha256=(Get-Hash $displaced); owner=$owner; rolled_back_utc=[DateTime]::UtcNow.ToString('o') } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $BackupDll) 'rollback-receipt.json') -Encoding UTF8
  'ROLLBACK PASS: original target restored; displaced candidate retained.'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}
