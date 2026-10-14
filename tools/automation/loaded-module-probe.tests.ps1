param()

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'loaded-module-probe.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($probe, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) {
    $details = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
    throw "loaded-module probe parse failed: $details"
}

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw "Run this regression with Windows PowerShell 5.1; got $($PSVersionTable.PSVersion)"
}

function Invoke-ProbeFixture([string]$fixture) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -SyntheticFixture {1}' -f $probe, $fixture
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $psi
    $null = $child.Start()
    $stdout = $child.StandardOutput.ReadToEndAsync()
    $stderr = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()
    [pscustomobject]@{ ExitCode = $child.ExitCode; Stdout = $stdout.Result; Stderr = $stderr.Result }
}

function Get-ModulePathFromProof([string]$text, [string]$moduleName) {
    $collect = $false
    $parts = @{}
    $expectedPartCount = 0
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -eq "LOADED_MODULE=$moduleName") { $collect = $true; continue }
        if (-not $collect) { continue }
        if ($line -match '^MODULE_PATH_PART=(\d+)/(\d+):(.*)$') {
            $parts[[int]$Matches[1]] = [string]$Matches[3]
            $expectedPartCount = [int]$Matches[2]
            continue
        }
        if ($line -match '^ON_DISK_SHA256=[0-9A-F]{64}$' -or $line -match '^LOADED_MODULE=') { break }
    }
    if ($expectedPartCount -lt 1 -or $parts.Count -ne $expectedPartCount) { return $null }
    $joined = ''
    for ($part = 1; $part -le $expectedPartCount; $part++) {
        if (-not $parts.ContainsKey($part)) { return $null }
        $joined += $parts[$part]
    }
    return $joined
}

$success = Invoke-ProbeFixture 'success'
$successExit = $success.ExitCode
$successText = $success.Stdout
$successModuleCount = [regex]::Matches($successText, '(?m)^LOADED_MODULE=(?:Stobe|AutomationHarness)\.dll\r?$').Count
$successPathCount = [regex]::Matches($successText, '(?m)^MODULE_PATH_PART=\d+/\d+:.+\r?$').Count
$successHashCount = [regex]::Matches($successText, '(?m)^ON_DISK_SHA256=[0-9A-F]{64}\r?$').Count
$maxLineLength = (($successText -split "`r?`n" | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
if ($successExit -ne 0 -or
    $successModuleCount -ne 2 -or
    $successPathCount -lt 2 -or
    $successHashCount -ne 2 -or
    $maxLineLength -gt 80 -or
    $success.Stderr) {
    throw "synthetic success proof was not captured as plain stdout markers: exit=$successExit module_count=$successModuleCount path_count=$successPathCount hash_count=$successHashCount max_line=$maxLineLength stdout=<$successText> stderr=<$($success.Stderr)>"
}
if ((Get-ModulePathFromProof $successText 'Stobe.dll') -notmatch '\\Stobe\.dll$' -or
    (Get-ModulePathFromProof $successText 'AutomationHarness.dll') -notmatch '\\AutomationHarness\.dll$') {
    throw "short module path parts did not reconstruct exact fixture paths: stdout=<$successText>"
}

$missing = Invoke-ProbeFixture 'missing-module'
$missingExit = $missing.ExitCode
$missingText = $missing.Stdout
if ($missingExit -ne 22 -or
    $missingText -notmatch '(?m)^MODULE_GATE_FAIL name=AutomationHarness\.dll count=0\r?$' -or
    $missingText -match '(?m)^LOADED_MODULE=AutomationHarness\.dll\r?$' -or
    $missing.Stderr) {
    throw "missing-module case did not fail closed on plain stdout: exit=$missingExit stdout=<$missingText> stderr=<$($missing.Stderr)>"
}

$processCount = Invoke-ProbeFixture 'process-count'
$processExit = $processCount.ExitCode
$processText = $processCount.Stdout
if ($processExit -ne 21 -or $processText -notmatch '(?m)^PROCESS_GATE_FAIL count=2\r?$') {
    throw "multiple-process case did not fail closed: exit=$processExit output=<$processText>"
}

$pathCase = Invoke-ProbeFixture 'path-case'
if ($pathCase.ExitCode -ne 0 -or
    $pathCase.Stdout -notmatch '(?m)^PROCESS_PATH_PART=1/1:c:\\synthetic\\KENSHI_X64\.EXE\r?$' -or
    @([regex]::Matches($pathCase.Stdout, '(?m)^LOADED_MODULE=(?:Stobe|AutomationHarness)\.dll\r?$')).Count -ne 2) {
    throw "case-insensitive Windows executable-path comparison failed: exit=$($pathCase.ExitCode) stdout=<$($pathCase.Stdout)>"
}

$pathMismatch = Invoke-ProbeFixture 'path-mismatch'
if ($pathMismatch.ExitCode -ne 21 -or
    $pathMismatch.Stdout -notmatch '(?m)^PROCESS_GATE_FAIL path_mismatch\r?$' -or
    $pathMismatch.Stdout -match '(?m)^LOADED_MODULE=') {
    throw "unexpected executable path did not fail closed: exit=$($pathMismatch.ExitCode) stdout=<$($pathMismatch.Stdout)>"
}

$longPath = Invoke-ProbeFixture 'long-path'
$longPathMaxLine = (($longPath.Stdout -split "`r?`n" | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
$longStobePath = Get-ModulePathFromProof $longPath.Stdout 'Stobe.dll'
$longHarnessPath = Get-ModulePathFromProof $longPath.Stdout 'AutomationHarness.dll'
if ($longPath.ExitCode -ne 0 -or $longPathMaxLine -gt 80 -or
    $longStobePath.Length -le 80 -or $longStobePath -notmatch '\\Stobe\.dll$' -or
    $longHarnessPath.Length -le 80 -or $longHarnessPath -notmatch '\\AutomationHarness\.dll$') {
    throw "long module paths were not split/reconstructed safely: exit=$($longPath.ExitCode) max_line=$longPathMaxLine stdout=<$($longPath.Stdout)>"
}

foreach ($path in @(
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'pending-fixes\rig4080-validation\chat007-preflight-once.sh'),
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'pending-fixes\rig4080-validation\int003-preflight-4080i3-20261014.sh')
)) {
    $body = Get-Content -LiteralPath $path -Raw
    if ($body -notmatch "loaded-module-probe\.ps1' -ExpectedExecutablePath" -or
        $body -match 'powershell\.exe[^\r\n]*-Command\s+-') {
        throw "preflight does not use the direct -File probe or retained fragile stdin mode: $path"
    }
}

$chat007Path = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'pending-fixes\rig4080-validation\chat007-preflight-once.sh'
$chat007Body = Get-Content -LiteralPath $chat007Path -Raw
$expectedChat007Probe = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\loaded-module-probe.ps1' -ExpectedExecutablePath 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe'"
$exactChat007ProbeCount = [regex]::Matches($chat007Body, '(?m)^' + [regex]::Escape($expectedChat007Probe) + '\r?$').Count
$policyOrRegistryMutation = '(?i)\bSet-ExecutionPolicy\b|\b(?:Set|New|Remove)-ItemProperty\b|\breg(?:\.exe)?\s+(?:add|delete)\b|\bRegistry::|\bHKEY_(?:LOCAL_MACHINE|CURRENT_USER)\\|\bHK(?:LM|CU):\\'
if ($exactChat007ProbeCount -ne 1 -or $chat007Body -match $policyOrRegistryMutation) {
    throw "CHAT-007 probe invocation drifted or caller attempts a global policy/registry mutation: exact_invocation_count=$exactChat007ProbeCount"
}

$int003Path = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'pending-fixes\rig4080-validation\int003-preflight-4080i3-20261014.sh'
$int003Body = Get-Content -LiteralPath $int003Path -Raw
$guard = [regex]::Match($int003Body, '(?s)if ! rig4080_i3_preflight; then(?<failure>.*?)\nfi')
$guardEnd = $guard.Index + $guard.Length
$downstreamProbes = @(
    'powershell.exe -NoProfile -Command',
    "loaded-module-probe.ps1' -ExpectedExecutablePath",
    'sha256sum /c/KenshiInst/3/mods/Stobe/Stobe.dll',
    "grep -iE '^(ServerHost|ServerPort)'",
    'curl -fsS --max-time 5 http://127.0.0.1:18084/health.php',
    'timeout 15 stobe-auto status',
    'timeout 15 stobe-auto input_isolation status',
    'timeout 15 stobe-auto fp_state',
    'timeout 15 stobe-auto stobe_ping',
    'timeout 20 stobe-auto chars 500',
    'timeout 20 stobe-auto traders 500',
    'tail -n 160 /c/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log'
)
$downstreamIndexes = @($downstreamProbes | ForEach-Object { $int003Body.IndexOf($_) })
if (-not $guard.Success -or
    $guard.Groups['failure'].Value -notmatch 'RESULT INT-003 FAIL setup: isolated i3 route preflight failed' -or
    $guard.Groups['failure'].Value -notmatch '(?m)^\s*exit 23\s*$' -or
    @($downstreamIndexes | Where-Object { $_ -lt 0 -or $_ -le $guardEnd }).Count -gt 0) {
    throw 'INT-003 route preflight is not a fail-closed guard before game/KAH probes'
}

'RESULT LOADED-MODULE-PROBE PASS cases=success+missing-module+process-count+windows-path-case+path-mismatch+long-path+CHAT007-exact-bypass-no-global-mutation+INT003-static-route-guard-order capture=redirected-stdout markers=2 callers=2'
