<#
stage-stobe-candidate.ps1: package an exact reviewed Stobe.dll and emit operator-only
instructions for the isolated instance-3 copies. This script never installs or connects
to a rig. Its only write targets are below C:\KenshiModding\pending-fixes\release-staging.

  .\stage-stobe-candidate.ps1 -Candidate stobe-ui-hotkeys|stobe-integrated|stobe-aef-social -Rig 5090|4080
  .\stage-stobe-candidate.ps1 -SelfTest

The emitted destination is informational and fail-closed: 5090 D:\KenshiInst\3\mods\Stobe\Stobe.dll
or 4080 C:\KenshiInst\3\mods\Stobe\Stobe.dll. A rig operator must independently prove
instance=3, local copied save, non-reparse path, and Stobe.dll link count=1 before copying.
No shared Steam/Vortex/personal install destination is accepted by this staging tool.
#>
[CmdletBinding()]
param(
  [ValidateSet('stobe-ui-hotkeys','stobe-integrated','stobe-aef-social')][string]$Candidate = '',
  [ValidateSet('5090','4080')][string]$Rig = '5090',
  [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$Workspace = [IO.Path]::GetFullPath('C:\KenshiModding').TrimEnd('\')
$StageRoot = Join-Path $Workspace 'pending-fixes\release-staging'
$CandidatePins = @{
  'stobe-ui-hotkeys' = @{ Source='pending-fixes\ui-hotkeys-release\stobe-build\Stobe.dll'; Sha256='EFE7B71C0B2D3A7A0F7A1F18033F88BF64F3BE6A3B055C506E913BA1D3CE61BA'; ReviewReceipt='pending-fixes\ui-hotkeys-release\STATUS.md'; SourceManifest=''; SourceManifestSha256=''; PayloadManifest=''; PayloadManifestSha256='' }
  'stobe-integrated' = @{ Source='pending-fixes\release-coordination\stobe-native-integrated-candidate-20261013\build-v100\Stobe.dll'; Sha256='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'; ReviewReceipt='pending-fixes\release-coordination\stobe-native-integrated-candidate-20261013\BUILD-RECEIPT.md'; SourceManifest=''; SourceManifestSha256=''; PayloadManifest=''; PayloadManifestSha256='' }
  'stobe-aef-social' = @{ Source='pending-fixes\release-coordination\stobe-native-integrated-social-repair-20261013\build-v100\Stobe.dll'; Sha256='842CEB786F338FFE06258F80E0CC0D96C8C1938F3F9F1115A0890EF21AF25FA8'; ReviewReceipt='pending-fixes\release-coordination\stobe-native-integrated-social-repair-20261013\INDEPENDENT-REVIEW.md'; ReviewReceiptSha256='9F7C8DA128FDCCC5B6E760F621F4A24CDD144CA3502CBA3DCE3F2311A5553781'; SourceManifest='pending-fixes\release-coordination\stobe-native-integrated-social-repair-20261013\SOURCE-MANIFEST.json'; SourceManifestSha256='7EAF6C685565C6208AD2D3CE9ED7BF0CCA9DC7D7865D06323A2AB9AEAFCD9691'; PayloadManifest='pending-fixes\release-coordination\stobe-native-integrated-social-repair-20261013\PAYLOAD-MANIFEST.json'; PayloadManifestSha256='4DAEE651F39FC20029E5E2A4CC4671CA23E677CC2E036F16E70167F347494BCB' }
}

function Is-UnderWorkspace([string]$Path) {
  if (-not $Path) { return $false }
  try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $full.StartsWith($Workspace + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-WorkspaceFile([string]$Path, [string]$Label) {
  if (-not (Is-UnderWorkspace $Path)) { throw "$Label must be a file under $Workspace" }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
  Assert-SafeWorkspaceWritePath $Path
}
function Assert-SafeWorkspaceWritePath([string]$Path, [string]$WorkspaceBase = $Workspace) {
  $base = [IO.Path]::GetFullPath($WorkspaceBase).TrimEnd('\')
  if (-not (Test-Path -LiteralPath $base -PathType Container)) { throw "workspace root is missing: $base" }
  $baseItem = Get-Item -LiteralPath $base -Force
  if ($baseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "workspace root is a reparse point: $base" }
  $volume = [IO.Path]::GetPathRoot($base)
  if (Test-Path -LiteralPath $volume) {
    $volumeItem = Get-Item -LiteralPath $volume -Force
    if ($volumeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "workspace volume root is a reparse point: $volume" }
  }
  $full = [IO.Path]::GetFullPath($Path)
  if (-not $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'write path is outside the workspace root' }
  $relative = $full.Substring($base.Length).TrimStart('\')
  $cursor = $base
  foreach ($part in ($relative -split '\\')) {
    $cursor = Join-Path $cursor $part
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "refusing reparse-point output path: $cursor" }
    }
  }
}
function Write-NewOrSameText([string]$Path, [string]$Content) {
  Assert-SafeWorkspaceWritePath $Path
  if (Test-Path -LiteralPath $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "output already exists and is not a file: $Path" }
    if ([IO.File]::ReadAllText($Path) -cne $Content) { throw "existing output differs; refusing to overwrite: $Path" }
    return $false
  }
  $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try {
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Content)
    $stream.Write($bytes, 0, $bytes.Length)
  } finally { $stream.Dispose() }
  $true
}
function Assert-PinnedHash([string]$Path, [string]$Expected) {
  if ($Expected -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Sha256 must be exactly 64 hexadecimal characters' }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($actual -cne $Expected.ToUpperInvariant()) { throw "candidate SHA256 mismatch: expected $($Expected.ToUpperInvariant()), got $actual" }
  $actual
}
function Get-IsolatedTarget([string]$ForRig) {
  switch ($ForRig) {
    '5090' { return 'D:\KenshiInst\3\mods\Stobe\Stobe.dll' }
    '4080' { return 'C:\KenshiInst\3\mods\Stobe\Stobe.dll' }
    default { throw 'Rig must be 5090 or 4080' }
  }
}
function Test-AllowedTarget([string]$Target, [string]$ForRig) {
  try { $expected = Get-IsolatedTarget $ForRig } catch { return $false }
  [string]::Equals($Target, $expected, [StringComparison]::OrdinalIgnoreCase)
}
function Test-StageInputs([string]$Name, [string]$ForRig) {
  if (-not $CandidatePins.ContainsKey($Name)) { throw 'candidate is not in the reviewed-candidate allowlist' }
  $pin = $CandidatePins[$Name]
  $src = Join-Path $Workspace $pin.Source
  $receipt = Join-Path $Workspace $pin.ReviewReceipt
  Assert-WorkspaceFile $src 'Source'
  Assert-WorkspaceFile $receipt 'ReviewReceipt'
  $actual = Assert-PinnedHash $src $pin.Sha256
  $reviewReceiptSha = if ($pin.ReviewReceiptSha256) { Assert-PinnedHash $receipt $pin.ReviewReceiptSha256 } else { '' }
  $sourceManifestPath = ''; $sourceManifestSha = ''; $payloadManifestPath = ''; $payloadManifestSha = ''
  if ($pin.SourceManifest) {
    $sourceManifestPath = Join-Path $Workspace $pin.SourceManifest
    $payloadManifestPath = Join-Path $Workspace $pin.PayloadManifest
    Assert-WorkspaceFile $sourceManifestPath 'SourceManifest'
    Assert-WorkspaceFile $payloadManifestPath 'PayloadManifest'
    $sourceManifestSha = Assert-PinnedHash $sourceManifestPath $pin.SourceManifestSha256
    $payloadManifestSha = Assert-PinnedHash $payloadManifestPath $pin.PayloadManifestSha256
    $payload = Get-Content -LiteralPath $payloadManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $stobePayload = @($payload.components | Where-Object { $_.name -ceq 'Stobe' -and $_.sha256 -ceq $actual })
    if ($stobePayload.Count -ne 1 -or $stobePayload[0].sourceManifest -cne (Split-Path $sourceManifestPath -Leaf)) {
      throw 'PayloadManifest does not bind the pinned Stobe DLL to the pinned source manifest'
    }
  }
  $receiptText = Get-Content -LiteralPath $receipt -Raw
  $mentionsAllPins = $receiptText.Contains($actual) -and
    (-not $sourceManifestSha -or $receiptText.Contains($sourceManifestSha)) -and
    (-not $payloadManifestSha -or $receiptText.Contains($payloadManifestSha))
  $reviewClear = ($receiptText -match '(?im)^.*independent.*review.*\bCLEAR\b.*$') -or
    (($receiptText -match '(?im)^Verdict:\s*\*\*CLEAR\b') -and ($receiptText -match '(?im)^.*independent.*review.*$'))
  if (-not $mentionsAllPins -or -not $reviewClear) {
    throw 'ReviewReceipt must name all pinned artifacts and record an independent review CLEAR'
  }
  $target = Get-IsolatedTarget $ForRig
  if (-not (Test-AllowedTarget $target $ForRig)) { throw 'derived target is outside the isolated instance-3 allowlist' }
  [pscustomobject]@{ Name=$Name; Source=[IO.Path]::GetFullPath($src); Receipt=[IO.Path]::GetFullPath($receipt); ReviewReceiptSha256=$reviewReceiptSha; Sha256=$actual; SourceManifest=$sourceManifestPath; SourceManifestSha256=$sourceManifestSha; PayloadManifest=$payloadManifestPath; PayloadManifestSha256=$payloadManifestSha; Rig=$ForRig; Target=$target }
}
function Invoke-SelfTest {
  $cases = @()
  $cases += [pscustomobject]@{ Name='5090 isolated i3 path'; Ok=(Test-AllowedTarget 'D:\KenshiInst\3\mods\Stobe\Stobe.dll' '5090') }
  $cases += [pscustomobject]@{ Name='4080 isolated i3 path'; Ok=(Test-AllowedTarget 'C:\KenshiInst\3\mods\Stobe\Stobe.dll' '4080') }
  $cases += [pscustomobject]@{ Name='5090 Steam path rejected'; Ok=(-not (Test-AllowedTarget 'D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll' '5090')) }
  $cases += [pscustomobject]@{ Name='4080 Steam path rejected'; Ok=(-not (Test-AllowedTarget 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll' '4080')) }
  $cases += [pscustomobject]@{ Name='Vortex backing path rejected'; Ok=(-not (Test-AllowedTarget 'C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\Stobe\Stobe.dll' '5090')) }
  $cases += [pscustomobject]@{ Name='wrong-rig path rejected'; Ok=(-not (Test-AllowedTarget 'D:\KenshiInst\3\mods\Stobe\Stobe.dll' '4080')) }
  $cases += [pscustomobject]@{ Name='bad hash format rejected'; Ok=(Assert-HashRejected) }
  $cases += [pscustomobject]@{ Name='wrong exact hash pin rejected'; Ok=(Assert-WrongHashRejected) }
  $cases += [pscustomobject]@{ Name='junction output path rejected'; Ok=(Assert-ReparseRejected) }
  $cases += [pscustomobject]@{ Name='workspace-root junction rejected'; Ok=(Assert-WorkspaceRootJunctionRejected) }
  $cases += [pscustomobject]@{ Name='existing hardlink is not written'; Ok=(Assert-ExistingHardlinkNotWritten) }
  $cases += [pscustomobject]@{ Name='source and review junctions rejected'; Ok=(Assert-InputJunctionRejected) }
  $cases += [pscustomobject]@{ Name='hotkey release exact pin and review'; Ok=(Assert-CandidatePinValid 'stobe-ui-hotkeys') }
  $cases += [pscustomobject]@{ Name='integrated release exact pin and review'; Ok=(Assert-CandidatePinValid 'stobe-integrated') }
  $cases += [pscustomobject]@{ Name='AEF social release exact triple pin and review'; Ok=(Assert-CandidatePinValid 'stobe-aef-social') }
  $bad = @($cases | Where-Object { -not $_.Ok }).Count
  foreach ($c in $cases) { Write-Host ('{0} {1}' -f $(if ($c.Ok) { 'PASS' } else { 'FAIL' }), $c.Name) }
  Write-Host "RESULT STOBE-STAGE-SELFTEST $(if ($bad) { 'FAIL' } else { 'PASS' }) cases=$($cases.Count)"
  return [int]($bad -gt 0)
}
function Assert-HashRejected {
  try { Assert-PinnedHash $PSCommandPath 'not-a-sha256' | Out-Null; return $false } catch { return $true }
}
function Assert-WrongHashRejected {
  try { Assert-PinnedHash $PSCommandPath ('0' * 64) | Out-Null; return $false } catch { return $true }
}
function Assert-ReparseRejected {
  $testRoot = Join-Path $StageRoot ('.selftest-reparse-' + [guid]::NewGuid().ToString('N'))
  $target = Join-Path $testRoot 'target'
  $junction = Join-Path $testRoot 'redirect'
  try {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop | Out-Null
    try { Assert-SafeWorkspaceWritePath (Join-Path $junction 'would-escape.txt'); return $false } catch { return $true }
  } finally {
    if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction, $false) }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
  }
}
function Assert-WorkspaceRootJunctionRejected {
  $testRoot = Join-Path $StageRoot ('.selftest-root-' + [guid]::NewGuid().ToString('N'))
  $target = Join-Path $testRoot 'target'
  $junction = Join-Path $testRoot 'workspace'
  try {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop | Out-Null
    try { Assert-SafeWorkspaceWritePath (Join-Path $junction 'new.txt') $junction; return $false } catch { return $true }
  } finally {
    if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction, $false) }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
  }
}
function Assert-ExistingHardlinkNotWritten {
  $testRoot = Join-Path $StageRoot ('.selftest-hardlink-' + [guid]::NewGuid().ToString('N'))
  $original = Join-Path $testRoot 'original.txt'
  $linked = Join-Path $testRoot 'linked.txt'
  try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    [IO.File]::WriteAllText($original, 'same-content')
    New-Item -ItemType HardLink -Path $linked -Target $original -ErrorAction Stop | Out-Null
    $before = [IO.File]::ReadAllText($original)
    $wrote = Write-NewOrSameText $linked 'same-content'
    return (-not $wrote -and [IO.File]::ReadAllText($original) -ceq $before)
  } finally { if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
}
function Assert-InputJunctionRejected {
  $testRoot = Join-Path $StageRoot ('.selftest-input-' + [guid]::NewGuid().ToString('N'))
  $target = Join-Path $testRoot 'target'
  $junction = Join-Path $testRoot 'redirect'
  $source = Join-Path $junction 'candidate.dll'
  $receipt = Join-Path $junction 'review.md'
  try {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $target 'candidate.dll'), 'candidate')
    [IO.File]::WriteAllText((Join-Path $target 'review.md'), 'independent review CLEAR')
    New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop | Out-Null
    $sourceRejected = $false; $receiptRejected = $false
    try { Assert-WorkspaceFile $source 'Source' } catch { $sourceRejected = $true }
    try { Assert-WorkspaceFile $receipt 'ReviewReceipt' } catch { $receiptRejected = $true }
    return ($sourceRejected -and $receiptRejected)
  } finally {
    if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction, $false) }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
  }
}
function Assert-CandidatePinValid([string]$Name) {
  try { Test-StageInputs $Name '5090' | Out-Null; return $true } catch { return $false }
}

if ($SelfTest) { $selfTestExit = Invoke-SelfTest; exit [int]$selfTestExit }
if (-not $Candidate) { throw 'Candidate is required; use -SelfTest for offline checks.' }
$input = Test-StageInputs $Candidate $Rig
$dest = Join-Path (Join-Path (Join-Path $StageRoot $Candidate) $Rig) $input.Sha256
$dllOut = Join-Path $dest 'Stobe.dll'
$manifestOut = Join-Path $dest 'manifest.json'
$instructionsOut = Join-Path $dest 'APPLY-INSTRUCTIONS.txt'
if (-not (Is-UnderWorkspace $dllOut) -or -not (Is-UnderWorkspace $manifestOut)) { throw 'stage output escaped workspace allowlist' }
Assert-SafeWorkspaceWritePath $dllOut
Assert-SafeWorkspaceWritePath $manifestOut
Assert-SafeWorkspaceWritePath $instructionsOut
if (Test-Path -LiteralPath $dllOut) {
  if ((Get-FileHash -LiteralPath $dllOut -Algorithm SHA256).Hash.ToUpperInvariant() -cne $input.Sha256) { throw 'existing stage file differs from pinned candidate; refusing overwrite' }
} else {
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  $srcStream = [IO.File]::OpenRead($input.Source)
  try {
    $outStream = New-Object IO.FileStream($dllOut, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $srcStream.CopyTo($outStream) } finally { $outStream.Dispose() }
  } finally { $srcStream.Dispose() }
}
if ((Get-FileHash -LiteralPath $dllOut -Algorithm SHA256).Hash.ToUpperInvariant() -cne $input.Sha256) { throw 'staged copy hash verification failed' }
$manifest = [ordered]@{
  format = 'stobe-isolated-stage-v1'
  candidate = $Candidate
  rig = $Rig
  target = $input.Target
  sha256 = $input.Sha256
  source = $input.Source
  stagedDll = $dllOut
  reviewReceipt = $input.Receipt
  deploymentPerformed = $false
  requiredOperatorProof = @('instance.txt exactly instance=3','settings.cfg contains User save location=0','target and ancestors are not reparse points','target Stobe.dll is a regular file with NTFS link count 1','record existing target SHA256 before copy and retain a rollback copy inside the isolated instance-3 folder')
}
if ($input.SourceManifestSha256) {
  $manifest.reviewReceiptSha256 = $input.ReviewReceiptSha256
  $manifest.sourceManifest = $input.SourceManifest
  $manifest.sourceManifestSha256 = $input.SourceManifestSha256
  $manifest.payloadManifest = $input.PayloadManifest
  $manifest.payloadManifestSha256 = $input.PayloadManifestSha256
}
$manifestText = $manifest | ConvertTo-Json -Depth 4
Write-NewOrSameText $manifestOut $manifestText | Out-Null
$instructions = @"
STOBE CANDIDATE STAGED ONLY — no deployment was performed.
Candidate: $Candidate
Rig: $Rig
Candidate SHA256: $($input.Sha256)
Package: $dllOut
Review receipt: $($input.Receipt)
Allowed isolated target: $($input.Target)

Operator-only apply procedure (not automated here):
1. Verify the exact physical host and that the intended game is isolated instance 3.
2. Prove instance.txt is exactly instance=3, settings.cfg says User save location=0, and the copied test save is local.
3. Prove every target ancestor is a real directory (no junction/symlink) and target Stobe.dll has NTFS link count 1.
4. Refuse this package if the target resolves to any Steam, Vortex, personal, shared, or non-instance-3 path.
5. With instance 3 closed, record the old SHA256 and make a rollback copy inside that isolated instance-3 folder.
6. Copy the staged DLL to the exact allowlisted target, verify the candidate SHA256, and record old/new hashes plus host/PID/save in the receipt.
7. If verification fails, restore the rollback copy and verify its old SHA256. Do not proceed without a new reviewed instruction.

This package is an offline handoff; it does not grant authorization to launch, stop, install, or modify a rig.
"@
Write-NewOrSameText $instructionsOut $instructions | Out-Null
"RESULT STOBE-STAGE PASS candidate=$Candidate rig=$Rig sha256=$($input.Sha256) deployment=none"
"manifest=$manifestOut"
"instructions=$instructionsOut"
