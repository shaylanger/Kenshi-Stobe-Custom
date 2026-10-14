[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BackupDll,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$CandidateSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$RuntimeSha256 = '40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D',
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$root = 'D:\KenshiInst\3'
$target = Join-Path $root 'RE_Kenshi\mods\Stobe\Stobe.dll'
$wrongPath = Join-Path $root 'mods\Stobe\Stobe.dll'
$owner = '5090c-ui-setup-20261014'
$lock = 'C:\KenshiTestRuns\game-3.lock'
$requiredClosedPid = 113932
function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-Identity {
  $marker = Get-Content -LiteralPath (Join-Path $root 'instance.txt') -Raw
  if ($marker -cnotmatch '\Ainstance=3 synced=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} from=D:\\Steam\\steamapps\\common\\Kenshi\r?\n?\z') { throw 'D3 instance marker mismatch.' }
  if ((Resolve-Path -LiteralPath $target).Path -ine $target -or $target -ieq $wrongPath) { throw 'Actual runtime target identity failed.' }
  if ((Get-Content -LiteralPath $lock -TotalCount 1).Trim() -cne $owner) { throw 'D3 owner lock mismatch.' }
  try {
    if (Get-CimInstance Win32_Process -Filter "ProcessId=$requiredClosedPid") { throw "Required PID $requiredClosedPid still present." }
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'")) {
      if (-not $p.ExecutablePath) { throw "Cannot identify Kenshi PID $($p.ProcessId)." }
      if ($p.ExecutablePath -ieq (Join-Path $root 'RE_Kenshi\kenshi_x64.exe')) { throw "D3 game PID $($p.ProcessId) still running." }
    }
  } catch { throw "Cannot prove game is closed: $($_.Exception.Message)" }
}
if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or -not (Test-Path -LiteralPath $BackupDll -PathType Leaf)) { throw 'Actual target or rollback file missing.' }
Assert-Identity
$expectedCandidate = $CandidateSha256.ToUpperInvariant(); $expectedRuntime = $RuntimeSha256.ToUpperInvariant()
$current = Get-Hash $target; $backup = Get-Hash $BackupDll
if ($current -cne $expectedCandidate) { throw "Rollback CAS refused: actual target=$current, expected candidate=$expectedCandidate" }
if ($backup -cne $expectedRuntime) { throw "Rollback bytes mismatch: $backup, expected original runtime=$expectedRuntime" }
"PLAN ONLY: actualTarget=$target candidate=$current rollback=$backup; wrongPath=$wrongPath ignored"
if (-not $Apply) { 'No files changed. Pass -Apply only at an authorized rollback boundary.'; exit 0 }
$dir = Split-Path -Parent $BackupDll
$temp = Join-Path (Split-Path -Parent $target) ('.Stobe.dll.rollback-' + [guid]::NewGuid().ToString('N') + '.tmp')
$displaced = Join-Path $dir ('Stobe.dll.displaced-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
try {
  Copy-Item -LiteralPath $BackupDll -Destination $temp
  if ((Get-Hash $temp) -cne $expectedRuntime) { throw 'Rollback temp hash mismatch.' }
  Assert-Identity
  if ((Get-Hash $target) -cne $expectedCandidate) { throw 'Target changed after rollback preflight.' }
  [IO.File]::Replace($temp,$target,$displaced,$true)
  if ((Get-Hash $target) -cne $expectedRuntime -or (Get-Hash $displaced) -cne $expectedCandidate) { throw 'Post-rollback hash mismatch.' }
  'ROLLBACK PASS: previous actual runtime restored; candidate retained.'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
