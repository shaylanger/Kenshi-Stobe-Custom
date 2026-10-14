<#
stage-stobe-pair.ps1 — workspace-only paired Stobe native/server staging.

This helper never installs, contacts a rig, stops a service, reads a save/database,
or writes outside C:\KenshiModding\pending-fixes\release-staging. Server composition,
source, payload, exact reviews, metadata cross-check, and source-pair validation gate
are pinned below. Validation staging preserves runtime/copy-save PENDING and final
RELEASE_HOLD; final staging requires a separate exact-pinned release gate.

  .\stage-stobe-pair.ps1 -Stage
.\stage-stobe-pair.ps1 -StageForValidation
  .\stage-stobe-pair.ps1 -SelfTest
#>
[CmdletBinding()]
param(
  [switch]$Stage,
  [switch]$StageForValidation,
  [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$Workspace = [IO.Path]::GetFullPath('C:\KenshiModding').TrimEnd('\')
$StageRoot = Join-Path $Workspace 'pending-fixes\release-staging'
$PairName = 'stobe-v4-server-final-4080-pair'
$CandidateRoot = Join-Path $Workspace 'pending-fixes\release-coordination\stobe-native-integrated-activity-social-20261013-aefsocialroute-v4-hotkeyunion'
$ServerRoot = Join-Path $Workspace 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel'

# Frozen native package pins. The exact independent review covers package integrity
# and offline evidence only; it does not clear installation or gameplay/runtime gates.
$NativePins = [ordered]@{
  Source = 'pending-fixes\release-coordination\stobe-native-integrated-activity-social-20261013-aefsocialroute-v4-hotkeyunion\build-v100\Stobe.dll'
  Sha256 = '128171DCA37821BCB254C601BD7145E9888EB22DC7CE33B3F3497C1283827620'
  SourceManifest = 'pending-fixes\release-coordination\stobe-native-integrated-activity-social-20261013-aefsocialroute-v4-hotkeyunion\SOURCE-MANIFEST.json'
  SourceManifestSha256 = '88D85D31A2D75CFD6CDAD49E54529411B61F7114985693DBC2B199357352846D'
  PayloadManifest = 'pending-fixes\release-coordination\stobe-native-integrated-activity-social-20261013-aefsocialroute-v4-hotkeyunion\PAYLOAD-MANIFEST.json'
  PayloadManifestSha256 = 'D4F3998B8315C493B414A628D5C60668EC135D670D1E8109B7AF680F0D6D2FC7'
  ReviewReceipt = 'pending-fixes\release-coordination\stobe-native-integrated-activity-social-20261013-aefsocialroute-v4-hotkeyunion\INDEPENDENT-REVIEW.md'
  ReviewReceiptSha256 = '24B63F39A0F812C09021F697D1D25A05D2D4E92A3EA3350FC38990314FCA9AF3'
}

# Frozen final server package pins. Source-pair contract is independently CLEAR;
# runtime/copy-save evidence remains pending and the final release gate is absent.
$ServerPins = [ordered]@{
  SourceRoot = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\release-candidate'
  SourceManifest = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\FINAL-SOURCE-MANIFEST.json'
  SourceManifestSha256 = 'E4168F120D8ED9E0530256C7495033E254A68FAFBBDC79636B8661D46015645D'
  PayloadManifest = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\release-candidate\PAYLOAD-MANIFEST.json'
  PayloadManifestSha256 = '67DBAACDDBFB322E48EC02CBDCB1D68CA206368CC4CB9149232634C870FFB604'
  Composition = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\release-candidate\COMPOSITION.json'
  CompositionSha256 = '8E25AE3C909F4307AEB31FEAFF170D4EEC702910599CAC7EDB97CE443799919E'
  ValidationReceipt = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\FINAL-VALIDATION-RECEIPT.md'
  ValidationReceiptSha256 = '814F4DAB73E9EC86EEA60E2DA50BCA7B15697240E7C8DD10F2214B636BA647B9'
  ReviewReceipt = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\validation-rerun\FINAL-INDEPENDENT-REVIEW.md'
  ReviewReceiptSha256 = 'A7C8CD4373C35CC18DFA902D87BB37607848B8512FB5AF4813E81DAFCEE5C5A7'
  MetadataCrossCheck = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\validation-rerun\FINAL-METADATA-CROSS-CHECK.md'
  MetadataCrossCheckSha256 = '5B0B62E65A1794CFC0A5E035BA1877BF179AFC6486633CB892CCF6791E0992BE'
  SourceValidationGate = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\release-candidate\PAIR-SOURCE-VALIDATION-GATE.json'
  SourceValidationGateSha256 = 'AEE26BBA6AFD928E18EC76D41E8547EFC2F45706487FD3518D6CC688F01838B4'
  ReleaseGate = 'pending-fixes\release-coordination\stobe-server-final-composition-20261013-activity-travel\PAIR-RELEASE-GATE.json'
  ReleaseGateSha256 = 'PENDING'
}

function Test-Under([string]$Path, [string]$Base) {
  try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $root = [IO.Path]::GetFullPath($Base).TrimEnd('\')
  return $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-SafePath([string]$Path, [string]$Base = $Workspace) {
  $base = [IO.Path]::GetFullPath($Base).TrimEnd('\')
  if (-not (Test-Path -LiteralPath $base -PathType Container)) { throw "base directory missing: $base" }
  $bi = Get-Item -LiteralPath $base -Force
  if ($bi.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "base is a reparse point: $base" }
  $full = [IO.Path]::GetFullPath($Path)
  if (-not $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'path escapes allowed base' }
  $cursor = $base
  foreach ($part in $full.Substring($base.Length).TrimStart('\') -split '\\') {
    if (-not $part) { continue }
    $cursor = Join-Path $cursor $part
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "reparse point in path: $cursor" }
    }
  }
}
function Assert-WorkspaceFile([string]$Path, [string]$Label) {
  if (-not (Test-Under $Path $Workspace)) { throw "$Label is outside the workspace" }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label missing: $Path" }
  Assert-SafePath $Path
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-Pin([string]$Path, [string]$Expected, [string]$Label) {
  if ($Expected -notmatch '^[A-Fa-f0-9]{64}$') { throw "$Label hash pin is missing or malformed" }
  Assert-WorkspaceFile $Path $Label
  $actual = Get-Sha $Path
  if ($actual -cne $Expected.ToUpperInvariant()) { throw "$Label hash mismatch: expected $($Expected.ToUpperInvariant()), got $actual" }
  return $actual
}
function Assert-Review([string]$Path, [string]$ExpectedSha, [string]$RequiredPins, [string]$Label) {
  [void](Assert-Pin $Path $ExpectedSha "$Label review receipt")
  $body = [IO.File]::ReadAllText($Path)
  if ($body -notmatch '(?im)^\s*(?:Status|Verdict):\s*\*\*?CLEAR\b' -and
      $body -notmatch '(?im)^.*independent(?: exact-hash)? review.*\bCLEAR\b.*$') { throw "$Label review receipt has no CLEAR verdict" }
  foreach ($pin in ($RequiredPins -split '\s+')) { if ($pin -and -not $body.Contains($pin)) { throw "$Label review receipt omits required pin $pin" } }
  return (Get-Sha $Path)
}
function Assert-ManifestTree([string]$Root, [hashtable]$Files, [string]$Label) {
  if (-not $Files -or $Files.Count -lt 1) { throw "$Label payload file map is empty" }
  $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not (Test-Under $fullRoot $Workspace)) { throw "$Label source root is outside the workspace" }
  Assert-SafePath $fullRoot
  foreach ($rel in $Files.Keys) {
    if (-not $rel -or [IO.Path]::IsPathRooted([string]$rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)' -or $rel -match ':') { throw "$Label manifest has unsafe relative path: $rel" }
    $expected = [string]$Files[$rel]
    if ($expected -notmatch '^[A-Fa-f0-9]{64}$') { throw "$Label has malformed file hash: $rel" }
    $file = Join-Path $fullRoot ($rel -replace '/', '\')
    Assert-WorkspaceFile $file "$Label payload file $rel"
    $actual = Get-Sha $file
    if ($actual -cne $expected.ToUpperInvariant()) { throw "$Label payload hash mismatch: $rel" }
  }
}
function Write-NewText([string]$Path, [string]$Text) {
  Assert-SafePath $Path
  if (Test-Path -LiteralPath $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.File]::ReadAllText($Path) -cne $Text) { throw "existing output differs; refusing overwrite: $Path" }
    return $false
  }
  $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
  return $true
}
function Copy-NewFile([string]$Source, [string]$Destination, [string]$ExpectedSha) {
  Assert-SafePath $Destination
  if (Test-Path -LiteralPath $Destination) {
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { throw "existing output is not a regular file: $Destination" }
    $old = Get-Sha $Destination
    if ($old -cne $ExpectedSha) { throw "existing output differs; refusing overwrite: $Destination" }
    return $old
  }
  $parent = Split-Path -Parent $Destination
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  Assert-SafePath $Destination
  $in = [IO.File]::OpenRead($Source)
  try {
    $out = New-Object IO.FileStream($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $in.CopyTo($out) } finally { $out.Dispose() }
  } finally { $in.Dispose() }
  $actual = Get-Sha $Destination
  if ($actual -cne $ExpectedSha) { throw "copied output hash mismatch: $Destination" }
  return $actual
}

function Assert-PairInputs([hashtable]$Pins, [string]$Root, [switch]$Synthetic, [switch]$ValidationStage) {
  $native = $Pins.Native
  $server = $Pins.Server
  $nativeSource = if ($Synthetic) { $native.Source } else { Join-Path $Workspace $native.Source }
  $nativeSourceSha = Assert-Pin $nativeSource $native.Sha256 'native DLL'
  $nativeSourceManifest = if ($Synthetic) { $native.SourceManifest } else { Join-Path $Workspace $native.SourceManifest }
  $nativePayloadManifest = if ($Synthetic) { $native.PayloadManifest } else { Join-Path $Workspace $native.PayloadManifest }
  $nativeReview = if ($Synthetic) { $native.ReviewReceipt } else { Join-Path $Workspace $native.ReviewReceipt }
  $nsm = Assert-Pin $nativeSourceManifest $native.SourceManifestSha256 'native source manifest'
  $npm = Assert-Pin $nativePayloadManifest $native.PayloadManifestSha256 'native payload manifest'
  $nativePayloadJson = Get-Content -LiteralPath $nativePayloadManifest -Raw | ConvertFrom-Json -ErrorAction Stop
  $nitems = @($nativePayloadJson.components | Where-Object { $_.name -ceq 'Stobe' -and $_.sha256 -ceq $nativeSourceSha -and $_.sourceManifest -ceq (Split-Path $nativeSourceManifest -Leaf) })
  if ($nitems.Count -ne 1 -or $nativePayloadJson.components.Count -ne 1) { throw 'native payload manifest must bind exactly one Stobe DLL to the pinned source manifest' }
  $nr = Assert-Review $nativeReview $native.ReviewReceiptSha256 "$($native.Sha256) $($native.SourceManifestSha256) $($native.PayloadManifestSha256)" 'native'

  $serverSourceManifest = if ($Synthetic) { $server.SourceManifest } else { Join-Path $Workspace $server.SourceManifest }
  $serverPayloadManifest = if ($Synthetic) { $server.PayloadManifest } else { Join-Path $Workspace $server.PayloadManifest }
  $serverComposition = if ($Synthetic) { $server.Composition } else { Join-Path $Workspace $server.Composition }
  $serverValidation = if ($Synthetic) { $server.ValidationReceipt } else { Join-Path $Workspace $server.ValidationReceipt }
  $serverReview = if ($Synthetic) { $server.ReviewReceipt } else { Join-Path $Workspace $server.ReviewReceipt }
  $metadataCrossCheck = if ($Synthetic) { $server.MetadataCrossCheck } else { Join-Path $Workspace $server.MetadataCrossCheck }
  $sourceGate = if ($Synthetic) { $server.SourceValidationGate } else { Join-Path $Workspace $server.SourceValidationGate }
  $gate = if ($Synthetic) { $server.ReleaseGate } else { Join-Path $Workspace $server.ReleaseGate }
  $ssm = Assert-Pin $serverSourceManifest $server.SourceManifestSha256 'server source manifest'
  $spm = Assert-Pin $serverPayloadManifest $server.PayloadManifestSha256 'server payload manifest'
  $scm = Assert-Pin $serverComposition $server.CompositionSha256 'server composition'
  $svr = Assert-Pin $serverValidation $server.ValidationReceiptSha256 'server final validation receipt'
  $metadataSha = Assert-Pin $metadataCrossCheck $server.MetadataCrossCheckSha256 'server final metadata cross-check'
  $sourceGateSha = Assert-Pin $sourceGate $server.SourceValidationGateSha256 'source/contract validation gate'
  $serverPayloadJson = Get-Content -LiteralPath $serverPayloadManifest -Raw | ConvertFrom-Json -ErrorAction Stop
  $compositionJson = Get-Content -LiteralPath $serverComposition -Raw | ConvertFrom-Json -ErrorAction Stop
  if ($ValidationStage) {
    if ($compositionJson.status -cne 'RELEASE_HOLD' -or $compositionJson.installable -ne $false) { throw 'validation-stage mode requires the final-release HOLD to remain explicit' }
  } elseif ($compositionJson.status -cne 'READY' -or $compositionJson.installable -ne $true) { throw "server composition remains held/not installable: $($compositionJson.status)" }
  if ($compositionJson.finalSourceManifestSha256.ToUpperInvariant() -cne $ssm -or $compositionJson.payloadManifestSha256.ToUpperInvariant() -cne $spm) { throw 'server composition metadata does not match the source and payload pins' }
  $validationText = [IO.File]::ReadAllText($serverValidation)
  if ($ValidationStage) {
    if ($validationText -notmatch '(?im)^State:\s*RELEASE_HOLD\b') { throw 'validation-stage mode requires a truthful final release HOLD in the validation receipt' }
  } elseif ($validationText -notmatch '(?im)^State:\s*RELEASE_READY\b' -or $validationText -match '(?i)RELEASE_HOLD|not installable') { throw 'server validation receipt does not declare RELEASE_READY' }
  if ($ValidationStage) {
    if ($serverPayloadJson.status -cne 'RELEASE_HOLD' -or $serverPayloadJson.installable -ne $false) { throw 'validation-stage mode requires the payload manifest to retain final release HOLD' }
  } elseif ($serverPayloadJson.status -cne 'READY' -or $serverPayloadJson.installable -ne $true) { throw "server payload status is held/not installable: $($serverPayloadJson.status)" }
  if ($serverPayloadJson.sourceManifestSha256.ToUpperInvariant() -cne $ssm) { throw 'server payload manifest does not bind the pinned server source manifest' }
  $live = $serverPayloadJson.payloads.live
  if (-not $live -or $live.deploymentRole -notmatch 'candidate live source tree') { throw 'server live payload is missing or has an unexpected deployment role' }
  if ($live.root -cne 'server/live' -or $live.entryCount -ne @($live.files.PSObject.Properties).Count) { throw 'server live payload root/count is invalid' }
  $serverSourceRoot = if ($Synthetic) { Join-Path $server.SourceRoot 'server\live' } else { Join-Path $Workspace ($server.SourceRoot + '\server\live') }
  $serverFiles = @{}
  foreach ($property in $live.files.PSObject.Properties) { $serverFiles[$property.Name] = [string]$property.Value }
  Assert-ManifestTree $serverSourceRoot $serverFiles 'server live'
  $serverReviewSha = Assert-Review $serverReview $server.ReviewReceiptSha256 "$($server.SourceManifestSha256) $($server.PayloadManifestSha256)" 'server'
  $serverReviewText = [IO.File]::ReadAllText($serverReview)
  $preReviewMatch = [regex]::Match($serverReviewText, '(?i)pre-review COMPOSITION\.json SHA-256 is `([A-F0-9]{64})`')
  if (-not $preReviewMatch.Success) { throw 'server review does not pin its frozen pre-review composition' }
  $preReviewCompositionSha = $preReviewMatch.Groups[1].Value.ToUpperInvariant()
  $crossCheckText = [IO.File]::ReadAllText($metadataCrossCheck)
  foreach ($pin in @($server.CompositionSha256,$server.ReviewReceiptSha256,$server.ValidationReceiptSha256,$server.SourceManifestSha256,$server.PayloadManifestSha256)) {
    if (-not $crossCheckText.Contains($pin)) { throw "metadata cross-check omits current frozen pin $pin" }
  }
  if ($crossCheckText -notmatch '(?im)^Verdict:\s*\*\*?CLEAR\b' -and $crossCheckText -notmatch '(?im)^Status:\s*\*\*?CLEAR\b') { throw 'metadata cross-check has no CLEAR verdict' }
  $sourceGateJson = Get-Content -LiteralPath $sourceGate -Raw | ConvertFrom-Json -ErrorAction Stop
  foreach ($field in @('status','contractStatus')) { if ($sourceGateJson.$field -cne 'CLEAR') { throw "source validation gate $field is not CLEAR" } }
  if ($sourceGateJson.stagePurpose -cne 'ISOLATED_RUNTIME_VALIDATION' -or $sourceGateJson.unresolvedSourceHolds -ne 0) { throw 'source validation gate has unresolved source/contract holds or wrong stage purpose' }
  if ($ValidationStage -and ($sourceGateJson.runtimeEvidence -cne 'PENDING' -or $sourceGateJson.copySaveEvidence -cne 'PENDING' -or $sourceGateJson.releaseStatus -cne 'RELEASE_HOLD' -or $sourceGateJson.installable -ne $false -or $sourceGateJson.deploymentAllowed -ne $false)) { throw 'validation staging requires runtime/copy-save pending and final-release HOLD' }
  $expectedCrossCheck = [IO.Path]::GetFullPath($metadataCrossCheck)
  $actualCrossCheckPath = [string]$sourceGateJson.metadataCrossCheck.path
  if ([IO.Path]::IsPathRooted($actualCrossCheckPath)) { $actualCrossCheckPath = [IO.Path]::GetFullPath($actualCrossCheckPath) } else { $actualCrossCheckPath = [IO.Path]::GetFullPath((Join-Path $Workspace $actualCrossCheckPath)) }
  if ($sourceGateJson.compositionSha256.ToUpperInvariant() -cne $scm -or $sourceGateJson.preReviewCompositionSha256.ToUpperInvariant() -cne $preReviewCompositionSha -or $sourceGateJson.metadataCrossCheck.sha256.ToUpperInvariant() -cne $metadataSha -or $actualCrossCheckPath -cne $expectedCrossCheck) { throw 'source validation gate composition/metadata-cross-check pin mismatch' }
  if ($sourceGateJson.native.dllSha256.ToUpperInvariant() -cne $native.Sha256 -or $sourceGateJson.native.sourceManifestSha256.ToUpperInvariant() -cne $native.SourceManifestSha256 -or $sourceGateJson.native.payloadManifestSha256.ToUpperInvariant() -cne $native.PayloadManifestSha256) { throw 'source validation gate native pins mismatch' }
  if ($sourceGateJson.server.sourceManifestSha256.ToUpperInvariant() -cne $server.SourceManifestSha256 -or $sourceGateJson.server.payloadManifestSha256.ToUpperInvariant() -cne $server.PayloadManifestSha256) { throw 'source validation gate server pins mismatch' }
  if ($sourceGateJson.contract.review.scope -cne 'SOURCE_PAIRING_PRODUCER_CONSUMER_CONTRACT') { throw 'contract review must cover the native/server source pairing and producer/consumer contract only' }
  $expectedNativeReview = [IO.Path]::GetFullPath($nativeReview)
  $expectedServerReview = [IO.Path]::GetFullPath($serverReview)
  foreach ($reviewSpec in @(
    @{ Spec=$sourceGateJson.native.review; ExpectedPath=$expectedNativeReview; ExpectedSha=$native.ReviewReceiptSha256; Name='native' },
    @{ Spec=$sourceGateJson.server.review; ExpectedPath=$expectedServerReview; ExpectedSha=$server.ReviewReceiptSha256; Name='server' },
    @{ Spec=$sourceGateJson.contract.review; ExpectedPath=''; ExpectedSha=''; Name='contract' }
  )) {
    $specPath = [string]$reviewSpec.Spec.path
    $reviewPath = if ([IO.Path]::IsPathRooted($specPath)) { [IO.Path]::GetFullPath($specPath) } else { [IO.Path]::GetFullPath((Join-Path $Workspace $specPath)) }
    if (-not (Test-Under $reviewPath $Workspace)) { throw "$($reviewSpec.Name) review path escapes workspace" }
    if ($reviewSpec.ExpectedPath -and $reviewPath -cne $reviewSpec.ExpectedPath) { throw "$($reviewSpec.Name) review path differs from frozen path" }
    $reviewExpected = if ($reviewSpec.ExpectedSha) { $reviewSpec.ExpectedSha } else { [string]$reviewSpec.Spec.sha256 }
    if ($reviewSpec.ExpectedSha -and ([string]$reviewSpec.Spec.sha256).ToUpperInvariant() -cne $reviewSpec.ExpectedSha) { throw "$($reviewSpec.Name) review SHA differs from frozen pin" }
    $reviewActual = Assert-Pin $reviewPath $reviewExpected "$($reviewSpec.Name) source/contract review"
    if ($reviewActual -cne ([string]$reviewSpec.Spec.sha256).ToUpperInvariant()) { throw "$($reviewSpec.Name) review SHA is inconsistent" }
    $reviewBody = [IO.File]::ReadAllText($reviewPath)
    if ($reviewBody -match '(?im)^\s*(?:Status|Verdict):\s*\*\*?REVISE\b') { throw "$($reviewSpec.Name) review contains an explicit REVISE verdict" }
    if ($reviewBody -notmatch '(?im)^\s*(?:Status|Verdict):\s*\*\*?CLEAR\b') { throw "$($reviewSpec.Name) review does not record an explicit CLEAR verdict" }
    if ($reviewSpec.Name -ceq 'contract') {
      foreach ($pin in @($native.Sha256,$native.SourceManifestSha256,$native.PayloadManifestSha256,$server.SourceManifestSha256,$server.PayloadManifestSha256)) {
        if (-not $reviewBody.Contains($pin)) { throw "contract review does not cover exact paired source pin $pin" }
      }
      if ($reviewBody -notmatch '(?i)(?:PHP.{0,30}native\s+v4\s+Activity\s+contract|producer.{0,30}consumer.{0,30}contract|native/server\s+source\s+contract)') { throw 'contract review body does not describe the paired producer/consumer source contract' }
    }
  }
  if (-not $ValidationStage) {
    $gateSha = Assert-Pin $gate $server.ReleaseGateSha256 'paired release gate'
    $gateJson = Get-Content -LiteralPath $gate -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($field in @('status','runtime','migration','copiedSave')) { if ($gateJson.$field -cne 'CLEAR') { throw "release gate $field is not CLEAR" } }
    if ($gateJson.componentHolds -ne 0 -or $gateJson.installable -ne $true -or $gateJson.status -cne 'CLEAR') { throw 'paired release gate remains held or non-installable' }
    $expectedReleasePins = @{
      'native.dllSha256'=$native.Sha256
      'native.sourceManifestSha256'=$native.SourceManifestSha256
      'native.payloadManifestSha256'=$native.PayloadManifestSha256
      'native.reviewSha256'=$native.ReviewReceiptSha256
      'server.sourceManifestSha256'=$server.SourceManifestSha256
      'server.payloadManifestSha256'=$server.PayloadManifestSha256
      'server.compositionSha256'=$server.CompositionSha256
      'server.validationReceiptSha256'=$server.ValidationReceiptSha256
      'server.reviewSha256'=$server.ReviewReceiptSha256
      'server.metadataCrossCheckSha256'=$server.MetadataCrossCheckSha256
    }
    foreach ($entry in $expectedReleasePins.GetEnumerator()) {
      $actual = $gateJson
      foreach ($part in $entry.Key.Split('.')) { $actual = $actual.$part }
      if ([string]$actual -cne [string]$entry.Value) { throw "paired release gate exact package pin mismatch: $($entry.Key)" }
    }
  }

  $mode = if ($ValidationStage) { 'validation' } else { 'final' }
  $releaseRoot = if ($Synthetic) { Join-Path (Join-Path $Root ('output-' + $mode)) '4080' } else { Join-Path (Join-Path (Join-Path (Join-Path $StageRoot $PairName) $mode) '4080') $native.Sha256 }
  if (-not (Test-Under $releaseRoot $StageRoot)) { throw 'paired stage output escaped release-staging' }
  return [pscustomobject]@{
    NativeSource=$nativeSource; NativeSha256=$nativeSourceSha; NativeSourceManifestSha256=$nsm; NativePayloadManifestSha256=$npm; NativeReviewSha256=$nr
    ServerSourceRoot=$serverSourceRoot; ServerFiles=$serverFiles; ServerSourceManifestSha256=$ssm; ServerPayloadManifestSha256=$spm
    ServerCompositionSha256=$scm; ServerValidationReceiptSha256=$svr; ServerReviewSha256=$serverReviewSha; ContractReviewSha256=([string]$sourceGateJson.contract.review.sha256).ToUpperInvariant(); MetadataCrossCheckSha256=$metadataSha; SourceValidationGateSha256=$sourceGateSha; SourceGateJson=$sourceGateJson; ReleaseGateSha256=if ($ValidationStage) { 'NOT_REQUIRED_FOR_VALIDATION' } else { Get-Sha $gate }; ReleaseRoot=$releaseRoot; Mode=$mode
  }
}

function Invoke-Stage([hashtable]$Pins, [switch]$Synthetic, [switch]$ValidationStage) {
  $outputBase = if ($Synthetic) { $Pins.OutputRoot } else { $StageRoot }
  $verified = Assert-PairInputs $Pins $outputBase -Synthetic:$Synthetic -ValidationStage:$ValidationStage
  $nativePath = Join-Path $verified.ReleaseRoot 'native\Stobe.dll'
  $serverOutRoot = Join-Path $verified.ReleaseRoot 'server\live'
  $null = Copy-NewFile $verified.NativeSource $nativePath $verified.NativeSha256
  $rows = @()
  foreach ($relative in ($verified.ServerFiles.Keys | Sort-Object -CaseSensitive)) {
    $expected = ([string]$verified.ServerFiles[$relative]).ToUpperInvariant()
    $src = Join-Path $verified.ServerSourceRoot ($relative -replace '/', '\')
    $dst = Join-Path $serverOutRoot ($relative -replace '/', '\')
    $null = Copy-NewFile $src $dst $expected
    $rows += [pscustomobject]@{ RelativePath=$relative; StagedSha256=$expected; InstallTarget='UNRESOLVED: map relative to verified private 127.0.0.1:18084 service root at separately authorized safe boundary'; PreInstallSha256='PENDING safe-boundary read'; RollbackBackup='PENDING exact pre-install file backup'; RollbackTarget='same verified private service relative path only' }
  }
  $status = if ($ValidationStage) { 'STAGED_FOR_ISOLATED_VALIDATION' } else { 'STAGED_FINAL_RELEASE_CANDIDATE' }
  $map = [ordered]@{
    format='stobe-native-server-pair-stage-v1'; status=$status; stagePurpose=$(if ($ValidationStage) { 'ISOLATED_RUNTIME_VALIDATION' } else { 'FINAL_RELEASE_CANDIDATE_STAGING' }); finalReleaseStatus=$(if ($ValidationStage) { 'RELEASE_HOLD' } else { 'RELEASE_READY' }); installable=$false; deploymentAllowed=$false; deploymentPerformed=$false
    candidate='Stobe native v4 + final composed server'; rig='4080'; gameInstance='3'
    artifacts=[ordered]@{
      native=[ordered]@{dllSha256=$verified.NativeSha256;sourceManifestSha256=$verified.NativeSourceManifestSha256;payloadManifestSha256=$verified.NativePayloadManifestSha256}
      server=[ordered]@{sourceManifestSha256=$verified.ServerSourceManifestSha256;payloadManifestSha256=$verified.ServerPayloadManifestSha256;liveFileCount=$rows.Count;mergeCopied=$false}
    }
    native=[ordered]@{ staged='native\Stobe.dll'; sha256=$verified.NativeSha256; installTarget='C:\KenshiInst\3\mods\Stobe\Stobe.dll'; preInstallSha256='PENDING safe-boundary read'; rollback='PENDING exact instance-3 DLL backup' }
    server=[ordered]@{ route='private service at 127.0.0.1:18084'; serviceRoot='UNRESOLVED; must be proven from current private launcher/config at a separately authorized boundary'; manifestSha256=$verified.ServerPayloadManifestSha256; files=$rows; protectedSettings='unchanged'; campaignDatabase='unchanged' }
    reviews=[ordered]@{
      native=[ordered]@{path=$verified.SourceGateJson.native.review.path;sha256=$verified.NativeReviewSha256}
      server=[ordered]@{path=$verified.SourceGateJson.server.review.path;sha256=$verified.ServerReviewSha256}
      pairContract=[ordered]@{path=$verified.SourceGateJson.contract.review.path;sha256=$verified.ContractReviewSha256}
    }
    serverCompositionSha256=$verified.ServerCompositionSha256
    serverValidationReceiptSha256=$verified.ServerValidationReceiptSha256
    sourceValidationGateSha256=$verified.SourceValidationGateSha256
    metadataCrossCheckSha256=$verified.MetadataCrossCheckSha256
    runtimeEvidence=$(if ($ValidationStage) { $verified.SourceGateJson.runtimeEvidence } else { 'CLEAR' })
    copySaveEvidence=$(if ($ValidationStage) { $verified.SourceGateJson.copySaveEvidence } else { 'CLEAR' })
    releaseGateSha256=$verified.ReleaseGateSha256
    exclusions=@(':5432','production 5090','instance 1','Steam/Vortex backing directories','all user saves')
    note='This package contains workspace-staged payloads and an informational install/rollback map. It does not authorize or perform installation or deployment. Record current target ownership, pre-install hashes, backup paths, and restore hashes only in a separately cleared operator plan.'
  }
  $mapPath = Join-Path $verified.ReleaseRoot 'PAIR-STAGE-MAP.json'
  $instructionsPath = Join-Path $verified.ReleaseRoot 'OPERATOR-NOTES.txt'
  $mapText = ($map | ConvertTo-Json -Depth 12) + "`n"
  $notes = @"
STOBE NATIVE + SERVER PAIR — WORKSPACE STAGE ONLY

No install or deployment was performed. This package is for the isolated 4080 instance 3 / private :18084 route only, after a separate release and operator clearance. The native target is C:\KenshiInst\3\mods\Stobe\Stobe.dll. The server's active private service root is unresolved and must be proven from its current private launcher/config; do not infer it from an older instance-2 receipt.

For each file in PAIR-STAGE-MAP.json, the staged SHA is fixed. Pre-install hashes and rollback backup paths are intentionally PENDING until the safe boundary. Preserve private settings, auth, and campaign DB bytes. Excluded: :5432, production 5090, instance 1, Steam/Vortex backing directories, and user saves.
"@
  [void](Write-NewText $mapPath $mapText)
  [void](Write-NewText $instructionsPath $notes)
  return [pscustomobject]@{ NativeSha256=$verified.NativeSha256; ServerFiles=$rows.Count; ReleaseRoot=$verified.ReleaseRoot; MapPath=$mapPath; Status=$status }
}

function New-SyntheticBundle([string]$Root, [switch]$ValidationScenario) {
  $inputRoot = Join-Path $Root 'inputs'
  $nroot = Join-Path $inputRoot 'native'
  $sroot = Join-Path $inputRoot 'server\server\live'
  New-Item -ItemType Directory -Path $nroot,$sroot -Force | Out-Null
  $nativeDll = Join-Path $nroot 'Stobe.dll'; [IO.File]::WriteAllBytes($nativeDll, [byte[]](1,3,3,7,2))
  $nativeSourceManifest = Join-Path $nroot 'SOURCE-MANIFEST.json'; [IO.File]::WriteAllText($nativeSourceManifest, '{"inputs":[]}', (New-Object Text.UTF8Encoding($false)))
  $nativePayloadManifest = Join-Path $nroot 'PAYLOAD-MANIFEST.json'
  $nh = Get-Sha $nativeDll
  [IO.File]::WriteAllText($nativePayloadManifest, (@{components=@(@{name='Stobe';sha256=$nh;sourceManifest='SOURCE-MANIFEST.json'})} | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
  $nativeReview = Join-Path $nroot 'INDEPENDENT-REVIEW.md'
  $nsmHash = Get-Sha $nativeSourceManifest; $npmHash = Get-Sha $nativePayloadManifest
  [IO.File]::WriteAllText($nativeReview, "Status: **CLEAR**`n$nh`n$nsmHash`n$npmHash", (New-Object Text.UTF8Encoding($false)))
  $serverFile = Join-Path $sroot 'lib\fixture.php'; New-Item -ItemType Directory -Path (Split-Path -Parent $serverFile) -Force | Out-Null; [IO.File]::WriteAllText($serverFile, '<?php echo "ok";')
  $sh = Get-Sha $serverFile
  $serverFile2 = Join-Path $sroot 'lib\fixture-extra.php'; [IO.File]::WriteAllText($serverFile2, '<?php echo "second";')
  $sh2 = Get-Sha $serverFile2
  $serverSourceManifest = Join-Path $inputRoot 'FINAL-SOURCE-MANIFEST.json'; [IO.File]::WriteAllText($serverSourceManifest, '{"files":[]}', (New-Object Text.UTF8Encoding($false)))
  $ss = Get-Sha $serverSourceManifest
  $serverPayloadManifest = Join-Path $inputRoot 'PAYLOAD-MANIFEST.json'
  $serverStatus = if ($ValidationScenario) { 'RELEASE_HOLD' } else { 'READY' }
  $installable = -not $ValidationScenario
  $payload = [ordered]@{ status=$serverStatus; installable=$installable; sourceManifestSha256=$ss; payloads=[ordered]@{ live=[ordered]@{ root='server/live'; deploymentRole='candidate live source tree'; entryCount=2; files=[ordered]@{ 'lib/fixture.php'=$sh; 'lib/fixture-extra.php'=$sh2 } }; merge=[ordered]@{ root='server/merge'; deploymentRole='comparison only'; entryCount=0; files=[ordered]@{} } } }
  [IO.File]::WriteAllText($serverPayloadManifest, ($payload | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
  $sp=Get-Sha $serverPayloadManifest
  $preReviewComposition = Join-Path $inputRoot 'PRE-REVIEW-COMPOSITION.json'; $preComposition=[ordered]@{status=$serverStatus;installable=$installable;finalSourceManifestSha256=$ss;payloadManifestSha256=$sp}
  [IO.File]::WriteAllText($preReviewComposition, ($preComposition | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
  $preReviewSha = Get-Sha $preReviewComposition
  $serverReview = Join-Path $inputRoot 'INDEPENDENT-REVIEW.md'
  [IO.File]::WriteAllText($serverReview, "Verdict: **CLEAR**`nThis recheck is against the refreshed frozen candidate, before its review pin is written into COMPOSITION.json. The current pre-review COMPOSITION.json SHA-256 is ``$preReviewSha``.`n$ss`n$sp", (New-Object Text.UTF8Encoding($false)))
  $serverReviewSha = Get-Sha $serverReview
  $serverComposition = Join-Path $inputRoot 'COMPOSITION.json'; $composition=[ordered]@{status=$serverStatus;installable=$installable;finalSourceManifestSha256=$ss;payloadManifestSha256=$sp;independentReviewSha256=$serverReviewSha}
  [IO.File]::WriteAllText($serverComposition, ($composition | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
  $serverValidation = Join-Path $inputRoot 'FINAL-VALIDATION-RECEIPT.md'
  $stateText = if ($ValidationScenario) { 'State: RELEASE_HOLD; not installable.' } else { 'State: RELEASE_READY; installable.' }
  [IO.File]::WriteAllText($serverValidation, $stateText, (New-Object Text.UTF8Encoding($false)))
  $scm=Get-Sha $serverComposition; $svr=Get-Sha $serverValidation
  $contractReview = Join-Path $inputRoot 'PAIR-CONTRACT-REVIEW.md'; [IO.File]::WriteAllText($contractReview, "Verdict: **CLEAR**`nIndependent E416 PHP to native v4 Activity contract review`n$nh`n$nsmHash`n$npmHash`n$ss`n$sp", (New-Object Text.UTF8Encoding($false)))
  $contractReviewSha = Get-Sha $contractReview
  $metadataCrossCheck = Join-Path $inputRoot 'FINAL-METADATA-CROSS-CHECK.md'
  [IO.File]::WriteAllText($metadataCrossCheck, "Verdict: **CLEAR**`n$scm`n$serverReviewSha`n$svr`n$ss`n$sp", (New-Object Text.UTF8Encoding($false)))
  $metadataSha = Get-Sha $metadataCrossCheck
  $sourceGate = Join-Path $inputRoot 'PAIR-SOURCE-VALIDATION-GATE.json'
  $sourceGateJson = [ordered]@{
    status='CLEAR'; contractStatus='CLEAR'; stagePurpose='ISOLATED_RUNTIME_VALIDATION'; unresolvedSourceHolds=0
    runtimeEvidence='PENDING'; copySaveEvidence='PENDING'; releaseStatus='RELEASE_HOLD'; installable=$false; deploymentAllowed=$false
    preReviewCompositionSha256=$preReviewSha; compositionSha256=$scm; metadataCrossCheck=[ordered]@{path=$metadataCrossCheck;sha256=$metadataSha}
    native=[ordered]@{dllSha256=$nh;sourceManifestSha256=$nsmHash;payloadManifestSha256=$npmHash;review=[ordered]@{path=$nativeReview;sha256=(Get-Sha $nativeReview)}}
    server=[ordered]@{sourceManifestSha256=$ss;payloadManifestSha256=$sp;review=[ordered]@{path=$serverReview;sha256=$serverReviewSha}}
    contract=[ordered]@{review=[ordered]@{path=$contractReview;sha256=$contractReviewSha;scope='SOURCE_PAIRING_PRODUCER_CONSUMER_CONTRACT'}}
  }
  [IO.File]::WriteAllText($sourceGate, ($sourceGateJson | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
  $releaseGate = [ordered]@{
    status='CLEAR';runtime='CLEAR';migration='CLEAR';copiedSave='CLEAR';componentHolds=0;installable=$true
    native=[ordered]@{dllSha256=$nh;sourceManifestSha256=$nsmHash;payloadManifestSha256=$npmHash;reviewSha256=(Get-Sha $nativeReview)}
    server=[ordered]@{sourceManifestSha256=$ss;payloadManifestSha256=$sp;compositionSha256=$scm;validationReceiptSha256=$svr;reviewSha256=$serverReviewSha;metadataCrossCheckSha256=$metadataSha}
  }
  $gate = Join-Path $inputRoot 'PAIR-RELEASE-GATE.json'; [IO.File]::WriteAllText($gate, ($releaseGate | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
  $n = [ordered]@{ Source=$nativeDll; Sha256=$nh; SourceManifest=$nativeSourceManifest; SourceManifestSha256=$nsmHash; PayloadManifest=$nativePayloadManifest; PayloadManifestSha256=$npmHash; ReviewReceipt=$nativeReview; ReviewReceiptSha256=(Get-Sha $nativeReview) }
  $s = [ordered]@{ SourceRoot=(Join-Path $inputRoot 'server'); SourceManifest=$serverSourceManifest; SourceManifestSha256=$ss; PayloadManifest=$serverPayloadManifest; PayloadManifestSha256=$sp; Composition=$serverComposition; CompositionSha256=$scm; ValidationReceipt=$serverValidation; ValidationReceiptSha256=$svr; ReviewReceipt=$serverReview; ReviewReceiptSha256=$serverReviewSha; MetadataCrossCheck=$metadataCrossCheck; MetadataCrossCheckSha256=$metadataSha; SourceValidationGate=$sourceGate; SourceValidationGateSha256=(Get-Sha $sourceGate); ReleaseGate=$gate; ReleaseGateSha256=(Get-Sha $gate) }
  return @{ Native=$n; Server=$s; OutputRoot=$Root }
}
function Invoke-SelfTest {
  $root = Join-Path $StageRoot ('.selftest-pair-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  $cases = [Collections.Generic.List[object]]::new()
  try {
    $pins = New-SyntheticBundle $root
    $r = Invoke-Stage $pins -Synthetic
    $copiedNative = Join-Path $r.ReleaseRoot 'native\Stobe.dll'
    $copiedServer = Join-Path $r.ReleaseRoot 'server\live\lib\fixture.php'
    $copiedServer2 = Join-Path $r.ReleaseRoot 'server\live\lib\fixture-extra.php'
    $cases.Add([pscustomobject]@{Name='synthetic final mode stages exact native and multi-file live server payload';Ok=((Get-Sha $copiedNative) -ceq $pins.Native.Sha256 -and (Get-Sha $copiedServer) -ceq (Get-Sha (Join-Path $pins.Server.SourceRoot 'server\live\lib\fixture.php')) -and (Get-Sha $copiedServer2) -ceq (Get-Sha (Join-Path $pins.Server.SourceRoot 'server\live\lib\fixture-extra.php')) -and $r.Status -ceq 'STAGED_FINAL_RELEASE_CANDIDATE')})
    $map = Get-Content -LiteralPath $r.MapPath -Raw | ConvertFrom-Json
    $cases.Add([pscustomobject]@{Name='final stage remains non-deploying and rollback facts truthful';Ok=($map.deploymentPerformed -eq $false -and $map.deploymentAllowed -eq $false -and $map.installable -eq $false -and $map.server.serviceRoot -like 'UNRESOLVED*' -and $map.native.preInstallSha256 -like 'PENDING*' -and $map.server.files[0].PreInstallSha256 -like 'PENDING*')})
    $validationPins = New-SyntheticBundle (Join-Path $root 'validation') -ValidationScenario
    $vr = Invoke-Stage $validationPins -Synthetic -ValidationStage
    $validationMap = Get-Content -LiteralPath $vr.MapPath -Raw | ConvertFrom-Json
    $cases.Add([pscustomobject]@{Name='validation mode allows pending runtime/copy-save only with final HOLD';Ok=($vr.Status -ceq 'STAGED_FOR_ISOLATED_VALIDATION' -and $validationMap.stagePurpose -ceq 'ISOLATED_RUNTIME_VALIDATION' -and $validationMap.runtimeEvidence -ceq 'PENDING' -and $validationMap.copySaveEvidence -ceq 'PENDING' -and $validationMap.finalReleaseStatus -ceq 'RELEASE_HOLD' -and $validationMap.installable -eq $false -and $validationMap.deploymentAllowed -eq $false)})
    $cases.Add([pscustomobject]@{Name='both synthetic output roots stay under release-staging';Ok=((Test-Under $r.ReleaseRoot $StageRoot) -and (Test-Under $vr.ReleaseRoot $StageRoot))})
    $bad = New-SyntheticBundle (Join-Path $root 'held-validation') -ValidationScenario
    $badGate=Get-Content -LiteralPath $bad.Server.SourceValidationGate -Raw | ConvertFrom-Json; $badGate.runtimeEvidence='RELEASE_HOLD'; [IO.File]::WriteAllText($bad.Server.SourceValidationGate, ($badGate | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false))); $bad.Server.SourceValidationGateSha256=Get-Sha $bad.Server.SourceValidationGate
    $cases.Add([pscustomobject]@{Name='held runtime evidence is not accepted as validation-pending';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'final-from-held') -ValidationScenario
    $cases.Add([pscustomobject]@{Name='held final package cannot enter final-stage mode';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic })})
    $bad = New-SyntheticBundle (Join-Path $root 'held')
    $gateJson=Get-Content -LiteralPath $bad.Server.ReleaseGate -Raw | ConvertFrom-Json; $gateJson.runtime='RELEASE_HOLD'; [IO.File]::WriteAllText($bad.Server.ReleaseGate, ($gateJson | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))); $bad.Server.ReleaseGateSha256=Get-Sha $bad.Server.ReleaseGate
    $cases.Add([pscustomobject]@{Name='held runtime gate rejected by final mode';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic })})
    $bad = New-SyntheticBundle (Join-Path $root 'wrong-release-pair')
    $gateJson=Get-Content -LiteralPath $bad.Server.ReleaseGate -Raw | ConvertFrom-Json; $gateJson.native.dllSha256=('0'*64); [IO.File]::WriteAllText($bad.Server.ReleaseGate, ($gateJson | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false))); $bad.Server.ReleaseGateSha256=Get-Sha $bad.Server.ReleaseGate
    $cases.Add([pscustomobject]@{Name='final mode rejects a CLEAR release gate pinned to another native DLL';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic })})
    $bad = New-SyntheticBundle (Join-Path $root 'contract-review-revise') -ValidationScenario
    $badGate=Get-Content -LiteralPath $bad.Server.SourceValidationGate -Raw | ConvertFrom-Json; $contractPath=[string]$badGate.contract.review.path
    [IO.File]::WriteAllText($contractPath, "Verdict: **REVISE**`nScope: SOURCE_PAIRING_PRODUCER_CONSUMER_CONTRACT`n$($bad.Native.Sha256)`n$($bad.Native.SourceManifestSha256)`n$($bad.Native.PayloadManifestSha256)`n$($bad.Server.SourceManifestSha256)`n$($bad.Server.PayloadManifestSha256)", (New-Object Text.UTF8Encoding($false)))
    $badGate.contract.review.sha256=Get-Sha $contractPath; [IO.File]::WriteAllText($bad.Server.SourceValidationGate, ($badGate | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false))); $bad.Server.SourceValidationGateSha256=Get-Sha $bad.Server.SourceValidationGate
    $cases.Add([pscustomobject]@{Name='REVISE contract receipt blocks validation staging';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'contract-review-conflict') -ValidationScenario
    $badGate=Get-Content -LiteralPath $bad.Server.SourceValidationGate -Raw | ConvertFrom-Json; $contractPath=[string]$badGate.contract.review.path
    [IO.File]::WriteAllText($contractPath, "Verdict: **REVISE**`nIndependent exact-hash review: CLEAR`nScope: SOURCE_PAIRING_PRODUCER_CONSUMER_CONTRACT`n$($bad.Native.Sha256)`n$($bad.Native.SourceManifestSha256)`n$($bad.Native.PayloadManifestSha256)`n$($bad.Server.SourceManifestSha256)`n$($bad.Server.PayloadManifestSha256)", (New-Object Text.UTF8Encoding($false)))
    $badGate.contract.review.sha256=Get-Sha $contractPath; [IO.File]::WriteAllText($bad.Server.SourceValidationGate, ($badGate | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false))); $bad.Server.SourceValidationGateSha256=Get-Sha $bad.Server.SourceValidationGate
    $cases.Add([pscustomobject]@{Name='mixed REVISE and CLEAR contract lines remain rejected';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'contract-gate-wrong-scope') -ValidationScenario
    $badGate=Get-Content -LiteralPath $bad.Server.SourceValidationGate -Raw | ConvertFrom-Json; $badGate.contract.review.scope='RUNTIME_CONTRACT'; [IO.File]::WriteAllText($bad.Server.SourceValidationGate, ($badGate | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false))); $bad.Server.SourceValidationGateSha256=Get-Sha $bad.Server.SourceValidationGate
    $cases.Add([pscustomobject]@{Name='contract gate with wrong scope is rejected';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'source-hold') -ValidationScenario
    $badGate=Get-Content -LiteralPath $bad.Server.SourceValidationGate -Raw | ConvertFrom-Json; $badGate.unresolvedSourceHolds=1; [IO.File]::WriteAllText($bad.Server.SourceValidationGate, ($badGate | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false))); $bad.Server.SourceValidationGateSha256=Get-Sha $bad.Server.SourceValidationGate
    $cases.Add([pscustomobject]@{Name='unresolved source hold rejected by validation mode';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'no-review')
    $bad.Server.ReviewReceiptSha256='PENDING'
    $cases.Add([pscustomobject]@{Name='missing exact server review hash rejected';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'hash-mismatch')
    $bad.Native.Sha256=('0'*64)
    $cases.Add([pscustomobject]@{Name='native hash mismatch rejected';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $bad = New-SyntheticBundle (Join-Path $root 'missing-payload')
    Remove-Item -LiteralPath $bad.Server.PayloadManifest -Force
    $cases.Add([pscustomobject]@{Name='missing server payload manifest rejected';Ok=(Assert-Rejected { Invoke-Stage $bad -Synthetic -ValidationStage })})
    $unsafe = @{ 'lib/../escape.php'=('0'*64) }
    $cases.Add([pscustomobject]@{Name='unsafe server relative path rejected';Ok=(Assert-Rejected { Assert-ManifestTree (Join-Path $root 'inputs\server') $unsafe 'test' })})
    $target = Join-Path $r.ReleaseRoot 'native\hardlink.dll'; $original = Join-Path $r.ReleaseRoot 'native\Stobe.dll'; New-Item -ItemType HardLink -Path $target -Target $original -ErrorAction Stop | Out-Null
    $before=(Get-Sha $original); $cases.Add([pscustomobject]@{Name='existing hardlink destination is not overwritten';Ok=((Copy-NewFile $original $target $before) -ceq $before -and (Get-Sha $original) -ceq $before)})
    $linkTarget=Join-Path $root 'redirect-target'; $junction=Join-Path $root 'redirect'; New-Item -ItemType Directory -Path $linkTarget -Force | Out-Null; New-Item -ItemType Junction -Path $junction -Target $linkTarget -ErrorAction Stop | Out-Null
    $cases.Add([pscustomobject]@{Name='reparse-point output rejected';Ok=(Assert-Rejected { Assert-SafePath (Join-Path $junction 'would-escape.txt') })})
    [IO.Directory]::Delete($junction, $false)
  } catch {
    $cases.Add([pscustomobject]@{Name=('unexpected selftest exception: ' + $_.Exception.Message);Ok=$false})
  } finally {
    $junction=Join-Path $root 'redirect'
    if (Test-Path -LiteralPath $junction) { try { [IO.Directory]::Delete($junction,$false) } catch {} }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  }
  $failed=@($cases | Where-Object { -not $_.Ok }).Count
  foreach ($case in $cases) { Write-Host ('{0} {1}' -f $(if ($case.Ok) { 'PASS' } else { 'FAIL' }), $case.Name) }
  Write-Host "RESULT STOBE-PAIR-STAGE-SELFTEST $(if ($failed) { 'FAIL' } else { 'PASS' }) cases=$($cases.Count)"
  return [int]($failed -gt 0)
}
function Assert-Rejected([scriptblock]$Action) { try { & $Action | Out-Null; return $false } catch { return $true } }

if ($SelfTest) { exit (Invoke-SelfTest) }
if ($Stage -and $StageForValidation) { throw '-Stage and -StageForValidation are mutually exclusive.' }
if (-not $Stage -and -not $StageForValidation) { throw 'Choose -Stage, -StageForValidation, or -SelfTest.' }
$pins = @{ Native=$NativePins; Server=$ServerPins }
try {
  if ($StageForValidation) { $result = Invoke-Stage $pins -ValidationStage } else { $result = Invoke-Stage $pins }
  Write-Host "RESULT STOBE-PAIR-STAGE PASS status=$($result.Status) native=$($result.NativeSha256) server_files=$($result.ServerFiles) map=$($result.MapPath)"
} catch {
  Write-Host "RESULT STOBE-PAIR-STAGE BLOCKED reason=$($_.Exception.Message)"
  exit 2
}
