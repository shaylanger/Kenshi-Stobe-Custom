<#
stobe-isolation-gate.ps1: fail-closed 4080 Stobe row gate.

The only approved isolated Stobe target is instance 3. A 4080 list must declare
the same copied save in # stobe-save: and # launch:, and pin the reviewed
Stobe.dll SHA below. The remote proof checks the instance marker, local-save
setting, all path ancestors for reparse points, the copied quick.save, and the
installed DLL hash/link count. This script is invoked by list-rigcheck.sh.

  stobe-isolation-gate.ps1 -ListPath <list>
  stobe-isolation-gate.ps1 -SelfTest
#>
param([string]$ListPath = '', [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$ExpectedInstance = '3'
$ExpectedDllSha256 = '40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D'

function HeaderValue([string[]]$lines, [string]$key) {
    $hits = @($lines | Where-Object { $_ -match "^\s*#\s*$([regex]::Escape($key))\s*:\s*(.*?)\s*$" } | ForEach-Object {
        $null = $_ -match "^\s*#\s*$([regex]::Escape($key))\s*:\s*(.*?)\s*$"; $Matches[1].Trim()
    })
    if ($hits.Count -ne 1) { return $null }
    [string]$hits[0]
}
function StobeRows([string[]]$lines) {
    @($lines | Where-Object { $_ -notmatch '^\s*(#|$)' } | Where-Object {
        $last = (($_ -split '\|')[-1] -replace '\S+=\S+', '')
        $last -match 'STOBE-|tests/ingame/stobe|\.txt(\s|$)'
    }).Count -gt 0
}
function StobeContract([string[]]$lines) {
    if (-not (StobeRows $lines)) { return 'list has no Stobe row' }
    $instance = HeaderValue $lines 'stobe-instance'
    if ($instance -cne $ExpectedInstance) { return 'stobe-instance must be 3' }
    $save = HeaderValue $lines 'stobe-save'
    if (-not $save -or $save -notmatch '^[A-Za-z0-9][A-Za-z0-9_. -]*$' -or $save -in '.', '..') { return 'stobe-save must name one local save folder' }
    $launch = HeaderValue $lines 'launch'
    if ($launch -cne $save) { return 'launch must exactly match stobe-save' }
    $sha = HeaderValue $lines 'stobe-dll-sha256'
    if ($sha -notmatch '^[A-Fa-f0-9]{64}$' -or $sha.ToUpperInvariant() -cne $ExpectedDllSha256) { return 'stobe-dll-sha256 is not the reviewed DLL hash' }
    foreach ($row in @($lines | Where-Object { $_ -notmatch '^\s*(#|$)' })) {
        $fields = @($row -split '\|')
        if ($fields.Count -lt 6) { return 'malformed Stobe row' }
        $rowSave = $fields[1].Trim()
        if (-not $rowSave) { return 'Stobe row has no save field' }
        if ($rowSave -notin '-', $save) { return "row save '$rowSave' is outside the declared isolated save" }
    }
    $null
}
function StobeProofError($proof, [string]$save) {
    if (-not $proof) { return '4080 isolation proof missing' }
    if ($proof.root -cne 'C:\KenshiInst\3') { return 'unknown/shared instance path' }
    if (-not $proof.instanceSafe -or $proof.instanceText -notmatch '^instance=3(?:\s|$)') { return 'instance 3 marker/path is not verified' }
    if (-not $proof.stobeSafe) { return 'Stobe directory or an ancestor is missing/reparse' }
    if (-not $proof.dllSafe -or [int]$proof.dllLinks -ne 1) { return 'Stobe.dll is missing, reparse, or shared by hard link' }
    if ($proof.dllSha256 -cne $ExpectedDllSha256) { return 'installed Stobe.dll SHA256 does not match the reviewed hash' }
    if (-not $proof.settingsSafe -or -not $proof.localSaveSetting) { return 'instance 3 is not configured for local saves' }
    if (-not $proof.saveRootSafe -or -not $proof.saveSafe) { return 'declared copied save or an ancestor is missing/reparse' }
    if ([int]$proof.saveLinks -ne 1) { return 'quick.save is missing or shared by hard link' }
    if ($proof.saveName -cne $save) { return '4080 proof returned a different save name' }
    $null
}
function Test-StobeGate {
    $bad = 0; $n = 0
    $goodLines = @('# stobe-instance: 3', '# stobe-save: kah-stobe-travel-validation-20261013', '# launch: kah-stobe-travel-validation-20261013', "# stobe-dll-sha256: $ExpectedDllSha256", 'S1 | - | Axima | Malzin | 60 | bash {CR}/KenshiModding/tests/ingame/stobe/STOBE-X.sh')
    $goodProof = [pscustomobject]@{ root='C:\KenshiInst\3'; instanceSafe=$true; instanceText='instance=3 synced=2026-10-13'; stobeSafe=$true; dllSafe=$true; dllLinks=1; dllSha256=$ExpectedDllSha256; settingsSafe=$true; localSaveSetting=$true; saveRootSafe=$true; saveSafe=$true; saveLinks=1; saveName='kah-stobe-travel-validation-20261013' }
    $cases = @(
        @('verified isolated instance 3', (StobeContract $goodLines), $goodProof, 'kah-stobe-travel-validation-20261013', $null),
        @('unknown instance header', (StobeContract ($goodLines -replace '# stobe-instance: 3', '# stobe-instance: 9')), $goodProof, 'kah-stobe-travel-validation-20261013', 'stobe-instance must be 3'),
        @('unknown/shared install path', $null, ($goodProof | Select-Object * -ExcludeProperty root | ForEach-Object { $p = $_ | Select-Object *; $p }), 'kah-stobe-travel-validation-20261013', 'unknown/shared instance path'),
        @('shared DLL hard link', $null, $null, 'kah-stobe-travel-validation-20261013', 'Stobe.dll is missing, reparse, or shared by hard link'),
        @('junction in Stobe path', $null, $null, 'kah-stobe-travel-validation-20261013', 'Stobe directory or an ancestor is missing/reparse'),
        @('junction in copied save path', $null, $null, 'kah-stobe-travel-validation-20261013', 'declared copied save or an ancestor is missing/reparse'),
        @('wrong installed DLL hash', $null, $null, 'kah-stobe-travel-validation-20261013', 'installed Stobe.dll SHA256 does not match the reviewed hash'),
        @('save declaration mismatch', (StobeContract ($goodLines -replace '# launch: kah-stobe-travel-validation-20261013', '# launch: kah-other-save')), $null, 'kah-stobe-travel-validation-20261013', 'launch must exactly match stobe-save')
    )
    foreach ($c in $cases) {
        $proof = $goodProof
        switch ($c[0]) {
            'unknown/shared install path' { $proof = $goodProof.PSObject.Copy(); $proof.root = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi' }
            'shared DLL hard link' { $proof = $goodProof.PSObject.Copy(); $proof.dllLinks = 2 }
            'junction in Stobe path' { $proof = $goodProof.PSObject.Copy(); $proof.stobeSafe = $false }
            'junction in copied save path' { $proof = $goodProof.PSObject.Copy(); $proof.saveSafe = $false }
            'wrong installed DLL hash' { $proof = $goodProof.PSObject.Copy(); $proof.dllSha256 = 'BAD' }
        }
        $got = if ($c[1]) { [string]$c[1] } else { StobeProofError $proof $c[3] }
        $ok = if ($c[4]) { $got -eq $c[4] } else { -not $got }
        if (-not $ok) { $bad++ }
        $n++; "$(if ($ok) { 'ok  ' } else { 'FAIL' }) $($c[0]): $(if ($got) { $got } else { 'accepted' })"
    }
    "STOBE-GATE-SELFTEST $(if ($bad) { "FAIL $bad" } else { 'PASS' }) $n cases"
    return [int]($bad -gt 0)
}
function RemoteProof([string]$save) {
    $save64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($save))
    $remote = @'
$ErrorActionPreference = 'Stop'
$root = 'C:\KenshiInst\3'
$expected = '40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D'
$save = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SAVE64__'))
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class StobeGateLinks {
  [StructLayout(LayoutKind.Sequential)] public struct FileInfo {
    public uint Attributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime, LastAccessTime, LastWriteTime;
    public uint VolumeSerialNumber, SizeHigh, SizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
  }
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetFileInformationByHandle(SafeFileHandle h, out FileInfo info);
  public static uint Count(SafeFileHandle h) { FileInfo i; return GetFileInformationByHandle(h, out i) ? i.NumberOfLinks : 0; }
}
"@
function SafePath([string]$path, [string]$base) {
  try {
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
    $baseFull = [IO.Path]::GetFullPath($base).TrimEnd('\')
    if (-not ($full.Equals($baseFull, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($baseFull + '\', [StringComparison]::OrdinalIgnoreCase))) { return $false }
    $cur = $full
    while ($true) {
      $i = Get-Item -LiteralPath $cur -Force -ErrorAction Stop
      if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
      if ($cur.Equals($baseFull, [StringComparison]::OrdinalIgnoreCase)) { break }
      $cur = Split-Path -Parent $cur
      if (-not $cur) { return $false }
    }
    return $true
  } catch { return $false }
}
function LinkCount([string]$path) {
  try {
    $s = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try { return [int][StobeGateLinks]::Count($s.SafeFileHandle) } finally { $s.Dispose() }
  } catch { return 0 }
}
$dll = Join-Path $root 'mods\Stobe\Stobe.dll'
$settings = Join-Path $root 'settings.cfg'
$marker = Join-Path $root 'instance.txt'
$saveDir = Join-Path (Join-Path $root 'save') $save
$quick = Join-Path $saveDir 'quick.save'
$dllHash = if (Test-Path -LiteralPath $dll) { (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToUpperInvariant() } else { '' }
$instanceText = if (Test-Path -LiteralPath $marker) { [string](Get-Content -LiteralPath $marker -Raw).Trim() } else { '' }
$localSaveSetting = $false
if (Test-Path -LiteralPath $settings) { $localSaveSetting = [bool](@(Get-Content -LiteralPath $settings | Where-Object { $_.Trim() -eq 'User save location=0' }).Count) }
$proof = [ordered]@{
  root=$root; instanceText=$instanceText; instanceSafe=(SafePath $marker 'C:\KenshiInst');
  stobeSafe=((SafePath (Join-Path $root 'mods') 'C:\KenshiInst') -and (SafePath (Join-Path $root 'mods\Stobe') 'C:\KenshiInst'));
  dllSafe=(SafePath $dll 'C:\KenshiInst'); dllLinks=(LinkCount $dll); dllSha256=$dllHash;
  settingsSafe=(SafePath $settings 'C:\KenshiInst'); localSaveSetting=$localSaveSetting;
  saveRootSafe=(SafePath (Join-Path $root 'save') 'C:\KenshiInst'); saveSafe=(SafePath $quick 'C:\KenshiInst'); saveLinks=(LinkCount $quick); saveName=$save
}
'STOBE-PROOF ' + ($proof | ConvertTo-Json -Compress)
'@
    $remote = $remote.Replace('__SAVE64__', $save64)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
    $lines = @(& ssh.exe -n -o BatchMode=yes -o ConnectTimeout=10 4080 powershell.exe -NoProfile -EncodedCommand $encoded 2>$null | ForEach-Object { "$($_)".Trim() })
    $line = $lines | Where-Object { $_ -like 'STOBE-PROOF *' } | Select-Object -Last 1
    if (-not $line) { return $null }
    try { return ($line.Substring(12) | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

if ($SelfTest) {
    $self = @(Test-StobeGate)
    foreach ($line in $self) { if ($line -is [string]) { Write-Output $line } }
    exit [int]$self[-1]
}
if (-not $ListPath -or -not (Test-Path -LiteralPath $ListPath -PathType Leaf)) { 'STOBE-GATE NO list path missing'; exit 1 }
try { $lines = @(Get-Content -LiteralPath $ListPath) } catch { 'STOBE-GATE NO list unreadable'; exit 1 }
$contract = StobeContract $lines
if ($contract) { "STOBE-GATE NO $contract"; exit 1 }
$save = HeaderValue $lines 'stobe-save'
$proof = RemoteProof $save
$proofError = StobeProofError $proof $save
if ($proofError) { "STOBE-GATE NO $proofError"; exit 1 }
"STOBE-GATE PASS instance=3 save=$save dll_sha256=$ExpectedDllSha256"
exit 0
