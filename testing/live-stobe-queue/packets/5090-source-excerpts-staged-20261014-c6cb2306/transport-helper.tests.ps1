param()

$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'invoke-wsl-captured.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($helper, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) {
    $details = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
    throw "helper parse failed: $details"
}

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw "Run this regression with Windows PowerShell 5.1; got $($PSVersionTable.PSVersion)"
}
'RESULT WSL-CAPTURED-PS51-PARSE PASS version=5.1 errors=0'

# The helper's SelfTest executes only the fixed argv + stdin transport fixture
# through local Git Bash; it does not invoke WSL, SSH, Kenshi, or a rig.
$output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -SelfTest 2>&1
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { throw "helper self-test failed (exit=$exitCode): $($output -join ' ')" }
$result = @($output | ForEach-Object { $_.ToString() } | Where-Object { $_ -match '^RESULT WSL-CAPTURED-TRANSPORT PASS ' })
if ($result.Count -ne 1) { throw "expected exactly one transport RESULT line; got: $($output -join ' ')" }
$result[0]
