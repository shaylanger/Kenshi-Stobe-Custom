[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Dumpbin)
$ErrorActionPreference = 'Stop'
$folder = $PSScriptRoot
$root = 'D:\KenshiInst\3'
$actual = Join-Path $root 'RE_Kenshi\mods\Stobe\Stobe.dll'
$wrong = Join-Path $root 'mods\Stobe\Stobe.dll'
$brokenCandidate = 'BC9D2F91F8DD134CD8E8BA79514703C158923DC43EB2B8D9F4C361A8E34494A2'
$expectedActual = '40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D'
$checks = 0
foreach ($path in @('install-corrected-path.ps1','rollback-corrected-path.ps1','check-pe-imports.ps1','ReceiptTime.psm1')) {
  $full = Join-Path $folder $path
  $tokens = $null; $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw "PowerShell parse error in $path : $($errors[0].Message)" }
  $checks++
}
if ($actual -ieq $wrong) { throw 'Regression: actual and wrong-path directories alias.' }
if (-not (Test-Path -LiteralPath $actual -PathType Leaf) -or -not (Test-Path -LiteralPath $wrong -PathType Leaf)) { throw 'Expected read-only actual/wrong-path files unavailable.' }
$actualHash = (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash.ToUpperInvariant()
$wrongHash = (Get-FileHash -LiteralPath $wrong -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actualHash -cne $expectedActual) { throw "Actual runtime hash changed: $actualHash" }
if ($wrongHash -cne $brokenCandidate) { throw "Wrong-path sibling no longer matches the known broken candidate: $wrongHash" }
$checks += 2
$candidateOut = @(& (Join-Path $folder 'check-pe-imports.ps1') -DllPath $wrong -GameRoot $root -SystemRoot "$env:WINDIR\System32" -Dumpbin $Dumpbin 2>&1)
if ($LASTEXITCODE -ne 1 -or -not (($candidateOut -join "`n") -match [regex]::Escape('OgreMain_x64.dll!?getColourWriteEnabled@Pass@Ogre@@QEBA_NXZ'))) { throw 'Import gate did not reject the BC9D candidate for the exact unresolved Ogre symbol.' }
$checks++
$runtimeOut = @(& (Join-Path $folder 'check-pe-imports.ps1') -DllPath $actual -GameRoot $root -SystemRoot "$env:WINDIR\System32" -Dumpbin $Dumpbin 2>&1)
if ($LASTEXITCODE -ne 0 -or -not (($runtimeOut -join "`n") -match 'PASS imports=\d+ dependencies=\d+ unresolved=0')) { throw 'Import gate failed the exact current runtime DLL.' }
$checks++
$installText = Get-Content -LiteralPath (Join-Path $folder 'install-corrected-path.ps1') -Raw
if (-not $installText.Contains("Join-Path `$root 'RE_Kenshi\mods\Stobe\Stobe.dll'") -or
    -not $installText.Contains("Join-Path `$root 'mods\Stobe\Stobe.dll'") -or
    -not $installText.Contains($brokenCandidate) -or -not $installText.Contains('$requiredClosedPid = 113932')) { throw 'Install guard constants missing (actual path, wrong path, BC9D block, or PID 113932).' }
$checks++
"PASS: $checks corrected-path checks; actual runtime import gate passes; wrong-path BC9D candidate is rejected by the exact-export gate. No files changed."
