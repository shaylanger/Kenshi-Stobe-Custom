<#
stage-kfp-hotkey-candidate.ps1: stage the exact reviewed KenshiFP configurable-toggle
candidate for a physical-rig operator. Writes only below pending-fixes/.../release-staging.
It never installs, launches, reads/changes live settings, or connects to a rig.

  .\stage-kfp-hotkey-candidate.ps1 -Rig 5090|4080
  .\stage-kfp-hotkey-candidate.ps1 -SelfTest

Target mappings are informational instance-3 paths only. Physical installation and
the operator row remain owned by /root/urgent_live_5090 and /root/urgent_live_4080.
#>
[CmdletBinding()]
param(
  [ValidateSet('5090','4080')][string]$Rig = '5090',
  [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$Workspace = [IO.Path]::GetFullPath('C:\KenshiModding').TrimEnd('\')
$StageRoot = Join-Path $Workspace 'pending-fixes\kenshifp-toggle-keybind\release-staging\f10-hotkey'
$Root = Join-Path $Workspace 'pending-fixes\ui-hotkeys-release'
$Pins = [ordered]@{
  dll = @{ path='kenshifp-build\scratch\components\KenshiFP\re_plugin\mod\KenshiFP.dll'; sha256='5C4424B387422EC59F95224D205BD92EBDD7A2091ED13C8A5BB51899484A9A13' }
  client = @{ path='kenshifp-build\scratch\components\KenshiFP\client\kenshifp_client.c'; sha256='4B40B44F6B0893E0010BA0FC3506D61B28E7AFE27F4810FF87D77F5952114F48' }
  policy = @{ path='kenshifp-build\scratch\components\KenshiFP\client\fp_toggle_key_policy.h'; sha256='D6155FF606398082CB8C90C69DC1F04F474590AAB4421C36174980F48F5A6D4A' }
  focusedTestSource = @{ path='exact-scope-tests\kenshifp\tests\test_toggle_key_policy.c'; sha256='C2C6A02351540944BD4A4894AD561D3B9EE6C5932F7956A1A4DF99B339176BB4' }
  focusedTestExe = @{ path='exact-scope-tests\kenshifp\tests\test_toggle_key_policy.exe'; sha256='815DD41029A8A17616E54759311C105136E0C6CC6460C5BECC88FFF351C326ED' }
  review = @{ path='exact-scope-tests\INDEPENDENT-REVIEW.md'; sha256='025BA96FCA96F54D09B0411732427CFAE8A2FC180D73AE9922D3BFF45000E5C6' }
  result = @{ path='exact-scope-tests\RESULT.md'; sha256='29465F9908C7BBBDFDB46A134203738E4DEF69FF7D3A673151E1FEB6889741EA' }
  buildReceipt = @{ path='KENSHIFP-BUILD-RECEIPT-20261013.md'; sha256='1652118A122A0EFAE06CBFDD91E7EF22AE9EEC19179D6488EB36BF3CE0632AC5' }
}
$Targets = @{
  '5090' = 'D:\KenshiInst\3\mods\KenshiFP\KenshiFP.dll'
  '4080' = 'C:\KenshiInst\3\mods\KenshiFP\KenshiFP.dll'
}

function Assert-SafeWorkspacePath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if (-not $full.StartsWith($Workspace + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "path outside workspace: $full" }
  $cursor = $Workspace
  foreach ($part in $full.Substring($Workspace.Length).TrimStart('\') -split '\\') {
    $cursor = Join-Path $cursor $part
    if (Test-Path -LiteralPath $cursor) {
      if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "reparse path rejected: $cursor" }
    }
  }
  return $full
}
function Get-PinnedFile([string]$Key) {
  $p = $Pins[$Key]
  $path = Assert-SafeWorkspacePath (Join-Path $Root $p.path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing pinned input: $path" }
  $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($actual -cne $p.sha256) { throw "pin mismatch for $Key; expected $($p.sha256), got $actual" }
  return [pscustomobject]@{ path=$path; sha256=$actual; length=(Get-Item -LiteralPath $path).Length }
}
function Test-TargetMapping([string]$ForRig, [string]$Path) {
  if (-not $Targets.ContainsKey($ForRig)) { return $false }
  if ($Path -cne $Targets[$ForRig]) { return $false }
  if ($Path -notmatch '^[DC]:\\KenshiInst\\3\\mods\\KenshiFP\\KenshiFP\.dll$') { return $false }
  return $true
}
function Test-NoLivePaths([string]$Text) {
  return ($Text -notmatch '(?i)(Steam|Vortex|AppData|Program Files|DwemerAI4Skyrim3|\\Users\\Shay|\\Kenshi\\mods\\)')
}
function Invoke-SelfTest {
  $checks = @()
  $hashesOk = $true
  foreach ($key in $Pins.Keys) { try { Get-PinnedFile $key | Out-Null } catch { $hashesOk = $false } }
  $checks += [pscustomobject]@{ name='all exact artifact hashes and sizes present'; ok=$hashesOk }
  $checks += [pscustomobject]@{ name='5090 instance-3 target mapping'; ok=(Test-TargetMapping '5090' $Targets['5090']) }
  $checks += [pscustomobject]@{ name='4080 instance-3 target mapping'; ok=(Test-TargetMapping '4080' $Targets['4080']) }
  $checks += [pscustomobject]@{ name='cross-rig target rejected'; ok=(-not (Test-TargetMapping '4080' $Targets['5090'])) }
  $checks += [pscustomobject]@{ name='live install target rejected'; ok=(-not (Test-TargetMapping '5090' 'D:\Steam\steamapps\common\Kenshi\mods\KenshiFP\KenshiFP.dll')) }
  $mapText = ($Targets.Values -join "`n")
  $checks += [pscustomobject]@{ name='target map contains no live paths'; ok=(Test-NoLivePaths $mapText) }
  $review = Get-Content -LiteralPath (Join-Path $Root $Pins.review.path) -Raw
  $checks += [pscustomobject]@{ name='review is exact and CLEAR'; ok=($review.Contains('Verdict: **CLEAR**') -and $review.Contains($Pins.dll.sha256) -and $review.Contains($Pins.client.sha256) -and $review.Contains($Pins.policy.sha256)) }
  $failed = @($checks | Where-Object { -not $_.ok }).Count
  foreach ($c in $checks) { Write-Host ('{0} {1}' -f $(if ($c.ok) {'PASS'} else {'FAIL'}), $c.name) }
  if ($failed) { Write-Host "RESULT KFP-STAGE-SELFTEST FAIL failed=$failed"; return 1 }
  Write-Host 'RESULT KFP-STAGE-SELFTEST PASS checks=7 writes=none rig=none install=none'
  return 0
}
if ($SelfTest) { exit (Invoke-SelfTest) }

$artifacts = [ordered]@{}
foreach ($key in $Pins.Keys) { $artifacts[$key] = Get-PinnedFile $key }
$target = $Targets[$Rig]
if (-not (Test-TargetMapping $Rig $target) -or -not (Test-NoLivePaths $target)) { throw 'target mapping is not an isolated instance-3 path' }
$reviewText = Get-Content -LiteralPath $artifacts.review.path -Raw
if (-not ($reviewText -match '(?im)^Verdict:\s*\*\*CLEAR\*\*') -or -not $reviewText.Contains($Pins.dll.sha256)) { throw 'review does not clear this exact candidate' }
$dest = Join-Path (Join-Path $StageRoot $Rig) $Pins.dll.sha256
$dllOut = Join-Path $dest 'KenshiFP.dll'
$manifestOut = Join-Path $dest 'PIN-MANIFEST.json'
$rowOut = Join-Path $dest 'OPERATOR-ROW.md'
foreach ($path in @($dllOut,$manifestOut,$rowOut)) { Assert-SafeWorkspacePath $path | Out-Null }
if (-not (Test-Path -LiteralPath $dllOut)) {
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  [IO.File]::Copy($artifacts.dll.path, $dllOut, $false)
} elseif ((Get-FileHash -LiteralPath $dllOut -Algorithm SHA256).Hash.ToUpperInvariant() -cne $Pins.dll.sha256) { throw 'existing staged DLL differs; refusing overwrite' }
if ((Get-FileHash -LiteralPath $dllOut -Algorithm SHA256).Hash.ToUpperInvariant() -cne $Pins.dll.sha256) { throw 'staged copy hash mismatch' }
$manifest = [ordered]@{
  format='kenshifp-f10-hotkey-operator-stage-v1'; candidate='KenshiFP configurable FP toggle binding'; rig=$Rig
  targetMapping=$target; packageDll=$dllOut; deploymentPerformed=$false; uiOrConfigActionPerformed=$false
  sourceBuildReviewPins=$artifacts; pins=$Pins
  buildSourceRevision='0e7f828-mod'; focusedTest='PASS fp_toggle_key_policy (24 checks)'; independentReview='CLEAR'
  targetRule='Instance 3 copied-save route only; operator must verify host, instance, local copied save, regular target path, and target link count 1 before any later copy.'
}
$manifestText = $manifest | ConvertTo-Json -Depth 6
if (Test-Path -LiteralPath $manifestOut) { if ([IO.File]::ReadAllText($manifestOut) -cne $manifestText) { throw 'existing pin manifest differs; refusing overwrite' } } else { [IO.File]::WriteAllText($manifestOut,$manifestText,[Text.UTF8Encoding]::new($false)) }
$row = @"
# Operator row: KenshiFP F10 configurable toggle

Candidate SHA-256: ``$($Pins.dll.sha256)``. Package: ``$dllOut``. Rig target map: ``$target`` (informational only).

Run only at the physical rig operator's approved safe boundary, with the exact candidate loaded in the isolated instance-3 copied-save setup. Do not use physical keyboard/mouse or change focus.

1. Enable ``stobe-auto input_isolation on``; verify ``input_isolation status`` reports ``isolation=on`` and ``focused=0``. Keep ``focused=0`` and recheck before and after each injected input group. Stop if either requirement changes.
2. Using injected F10 only, open KenshiFP settings. Read UI/screenshot and confirm ``FP on / off`` is shown.
3. Inject mouse move/click on that binding, release the click, then inject a verified-unused key (for example F9 only if confirmed unused). Read UI and the same install's INI; verify ``key_toggle_fp`` equals the chosen VK.
4. Close/reopen settings with injected F10 and verify the binding persisted. Inject the new key off/on; after each tap, read ``fp_keys state`` and capture a screenshot proving each transition.
5. Re-enter capture, inject Escape, and prove the chosen binding remains. Use injected mouse only to select Reset to Defaults; verify UI and INI show ``key_toggle_fp=0xA5`` (Right Alt), close/reopen and verify it persists, then inject Right Alt off/on and capture both state transitions.
6. Record one ``RESULT KAH-UI-004 PASS|FAIL`` line with host, instance, PID, save identity, loaded DLL SHA, INI path/hash, ``isolation=on``, ``focused=0`` evidence, chosen VK, persisted value, reset value, toggle states, and evidence paths. Any focus/isolation loss stops the row as setup failure. Input must be injected only through the approved isolated input interface; injection ACK alone is not proof.

This staged package does not install the DLL or authorize rig/UI/config actions. Physical installation and row execution belong solely to ``/root/urgent_live_5090`` and ``/root/urgent_live_4080`` at operator-approved safe boundaries.
"@
if (Test-Path -LiteralPath $rowOut) { if ([IO.File]::ReadAllText($rowOut) -cne $row) { throw 'existing operator row differs; refusing overwrite' } } else { [IO.File]::WriteAllText($rowOut,$row,[Text.UTF8Encoding]::new($false)) }
Write-Host "RESULT KFP-F10-STAGE PASS rig=$Rig sha256=$($Pins.dll.sha256) install=none target=$target"
Write-Host "PACKAGE $dllOut"
Write-Host "MANIFEST $manifestOut"
Write-Host "OPERATOR_ROW $rowOut"
