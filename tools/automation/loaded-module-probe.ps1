<#
Emit a machine-readable proof of the modules loaded in one exact Kenshi process.

This helper is invoked with -File from Git Bash. Avoid `-Command -`/stdin:
that nested PowerShell path can emit startup/CLIXML noise while losing the
script's marker output in the isolated 4080 OpenSSH route. Output is written
directly to Console.Out so the calling Bash process receives plain text.
#>
[CmdletBinding()]
param(
    [string]$ExpectedExecutablePath,
    [ValidateSet('success', 'missing-module', 'process-count', 'path-case', 'path-mismatch', 'long-path')]
    [string]$SyntheticFixture
)

$ErrorActionPreference = 'Stop'
$requiredModules = @('Stobe.dll', 'AutomationHarness.dll')

function New-ModuleProofResult {
    param(
        [object[]]$Processes,
        [string]$RequiredPath,
        [string[]]$ModuleNames
    )

    if ($Processes.Count -ne 1) {
        return [pscustomobject]@{
            ExitCode = 21
            Lines = @("PROCESS_GATE_FAIL count=$($Processes.Count)")
        }
    }

    $process = $Processes[0]
    if ($process.Path -ine $RequiredPath) {
        return [pscustomobject]@{
            ExitCode = 21
            Lines = @('PROCESS_GATE_FAIL path_mismatch', "EXPECTED_PATH=$RequiredPath", "ACTUAL_PATH=$($process.Path)")
        }
    }

    $lines = @("PID=$($process.ProcessId)")
    $lines += @(Get-CompactPathProofLines 'PROCESS_PATH_PART' $process.Path)
    foreach ($name in $ModuleNames) {
        $matches = @($process.Modules | Where-Object { $_.ModuleName -ceq $name })
        if ($matches.Count -ne 1) {
            $lines += "MODULE_GATE_FAIL name=$name count=$($matches.Count)"
            return [pscustomobject]@{ ExitCode = 22; Lines = $lines }
        }

        $file = [string]$matches[0].FileName
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            $lines += "MODULE_GATE_FAIL name=$name file_missing"
            return [pscustomobject]@{ ExitCode = 23; Lines = $lines }
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash
        $lines += "LOADED_MODULE=$name"
        $lines += @(Get-CompactPathProofLines 'MODULE_PATH_PART' $file)
        $lines += "ON_DISK_SHA256=$hash"
    }

    return [pscustomobject]@{ ExitCode = 0; Lines = $lines }
}

function Write-ModuleProofResult($result) {
    foreach ($line in $result.Lines) {
        [Console]::Out.WriteLine([string]$line)
    }
}

function Get-CompactPathProofLines([string]$key, [string]$path) {
    $chunkSize = 45
    $count = [Math]::Max(1, [int][Math]::Ceiling($path.Length / [double]$chunkSize))
    $proofLines = @()
    for ($part = 0; $part -lt $count; $part++) {
        $start = $part * $chunkSize
        $length = [Math]::Min($chunkSize, $path.Length - $start)
        $piece = $path.Substring($start, $length)
        $proofLines += ('{0}={1}/{2}:{3}' -f $key, ($part + 1), $count, $piece)
    }
    return $proofLines
}

function Invoke-SyntheticFixture([string]$fixture) {
    $leaf = "lp-$PID"
    if ($fixture -eq 'long-path') { $leaf += '-' + ('x' * 72) }
    $root = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "tmp\$leaf"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    try {
        $stobePath = Join-Path $root 'Stobe.dll'
        $harnessPath = Join-Path $root 'AutomationHarness.dll'
        [IO.File]::WriteAllBytes($stobePath, [byte[]](1, 2, 3, 4))
        [IO.File]::WriteAllBytes($harnessPath, [byte[]](5, 6, 7, 8))

        $modules = @(
            [pscustomobject]@{ ModuleName = 'Stobe.dll'; FileName = $stobePath }
        )
        if ($fixture -ne 'missing-module') {
            $modules += [pscustomobject]@{ ModuleName = 'AutomationHarness.dll'; FileName = $harnessPath }
        }

        $syntheticPath = 'C:\Synthetic\kenshi_x64.exe'
        if ($fixture -eq 'path-case') { $syntheticPath = 'c:\synthetic\KENSHI_X64.EXE' }
        if ($fixture -eq 'path-mismatch') { $syntheticPath = 'C:\Synthetic\other.exe' }
        $processes = @([pscustomobject]@{
            ProcessId = 4242
            Path = $syntheticPath
            CommandLine = 'synthetic fixture'
            Modules = $modules
        })
        if ($fixture -eq 'process-count') {
            $processes += $processes[0]
        }

        $result = New-ModuleProofResult -Processes $processes `
            -RequiredPath 'C:\Synthetic\kenshi_x64.exe' -ModuleNames $requiredModules
        Write-ModuleProofResult $result
        return [int]$result.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SyntheticFixture) {
    $fixtureExit = Invoke-SyntheticFixture $SyntheticFixture
    exit $fixtureExit
}

if (-not $ExpectedExecutablePath) {
    [Console]::Error.WriteLine('Usage: loaded-module-probe.ps1 -ExpectedExecutablePath <exact kenshi_x64.exe path>')
    exit 2
}

try {
    $all = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'kenshi_x64.exe' -and $_.ExecutablePath -ieq $ExpectedExecutablePath
    })
    if ($all.Count -ne 1) {
        $result = New-ModuleProofResult -Processes $all -RequiredPath $ExpectedExecutablePath -ModuleNames $requiredModules
        Write-ModuleProofResult $result
        exit $result.ExitCode
    }

    $processInfo = $all[0]
    $game = Get-Process -Id $processInfo.ProcessId -ErrorAction Stop
    $modules = @($game.Modules | ForEach-Object {
        [pscustomobject]@{ ModuleName = $_.ModuleName; FileName = $_.FileName }
    })
    $record = [pscustomobject]@{
        ProcessId = $processInfo.ProcessId
        Path = $processInfo.ExecutablePath
        CommandLine = $processInfo.CommandLine
        Modules = $modules
    }
    $result = New-ModuleProofResult -Processes @($record) `
        -RequiredPath $ExpectedExecutablePath -ModuleNames $requiredModules
    Write-ModuleProofResult $result
    exit $result.ExitCode
}
catch {
    [Console]::Error.WriteLine("MODULE_GATE_FAIL name=enumeration error=$($_.Exception.Message)")
    exit 23
}
