$ErrorActionPreference = 'Stop'
$invocationId = '5090-source-excerpts-staged-20261014-c6cb2306'
$expectedHost = 'DESKTOP-JFLPK99'
$expectedDistro = 'DwemerAI4Skyrim3'
$expectedWorkingDirectory = '/mnt/c/KenshiModding'
$transport = 'C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1'
$expectedTransportSha256 = 'ED417184EAC849DEFCDCB9F49F969B037A6159B67431051E53FCF450E70667DF'
$body = Join-Path $PSScriptRoot 'excerpt.sh'
$expectedBodySha256 = '404F58604FB9C34EF9D0B189B631A4EC3AF4B17ECF9C2EC58E9B59BF58F8BD97'
$manifest = Join-Path $PSScriptRoot 'packet.manifest.tsv'

function Assert-TransportPin([string]$Path, [string]$ExpectedHash) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "PACKET_GATE_FAIL transport missing: $Path; WSL was not invoked"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actual -cne $ExpectedHash) {
        throw "PACKET_GATE_FAIL transport hash mismatch: $Path; WSL was not invoked"
    }
}

if ($env:COMPUTERNAME -cne $expectedHost) {
    throw "HOST_GATE_FAIL expected=$expectedHost actual=$env:COMPUTERNAME; WSL was not invoked"
}
$fixtureVariables = @(
    'STOBE_PACKET_FIXTURE', 'STOBE_PACKET_FIXTURE_PATH', 'STOBE_PACKET_GIT_FIXTURE',
    'STOBE_PACKET_GIT_FIXTURE_ROOT', 'STOBE_PACKET_GIT_FIXTURE_COMMIT', 'STOBE_PACKET_GIT_FIXTURE_PATH'
)
foreach ($name in $fixtureVariables) {
    if (Test-Path -LiteralPath "Env:$name") { throw "PACKET_GATE_FAIL inherited fixture variable $name; WSL was not invoked" }
}

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'PACKET_GATE_FAIL manifest missing; WSL was not invoked' }
$manifestLines = @(Get-Content -LiteralPath $manifest)
if ($manifestLines.Count -lt 2 -or $manifestLines[0] -cne "kind`tpath`tsha256") {
    throw 'PACKET_GATE_FAIL manifest header invalid; WSL was not invoked'
}
$expectedFiles = @('README.md', 'run.ps1', 'excerpt.sh', 'selftest.ps1', 'sanitizer.fixture.txt', 'invoke-wsl-captured.ps1', 'transport-helper.tests.ps1')
$expectedExternal = @('C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1', 'C:\KenshiModding\tools\automation\invoke-wsl-captured-ps51.tests.ps1')
$seenFiles = @{}
$seenExternal = @{}
foreach ($line in $manifestLines | Select-Object -Skip 1) {
    $fields = $line -split "`t", 3
    if ($fields.Count -ne 3 -or $fields[2] -notmatch '^[0-9A-F]{64}$') { throw 'PACKET_GATE_FAIL malformed manifest entry; WSL was not invoked' }
    $kind = $fields[0]; $path = $fields[1]; $expectedHash = $fields[2]
    if ($kind -ceq 'file') {
        if ($path -cnotin $expectedFiles -or $seenFiles.ContainsKey($path)) { throw "PACKET_GATE_FAIL unexpected/duplicate packet path $path; WSL was not invoked" }
        $resolved = Join-Path $PSScriptRoot $path
        $seenFiles[$path] = $true
    } elseif ($kind -ceq 'external') {
        if ($path -cnotin $expectedExternal -or $seenExternal.ContainsKey($path)) { throw "PACKET_GATE_FAIL unexpected/duplicate external path $path; WSL was not invoked" }
        $resolved = $path
        $seenExternal[$path] = $true
    } else {
        throw 'PACKET_GATE_FAIL unknown manifest entry type; WSL was not invoked'
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "PACKET_GATE_FAIL pinned artifact missing: $path; WSL was not invoked" }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash
    if ($actualHash -cne $expectedHash) { throw "PACKET_GATE_FAIL artifact hash mismatch: $path; WSL was not invoked" }
}
if (($seenFiles.Count -ne $expectedFiles.Count) -or ($seenExternal.Count -ne $expectedExternal.Count)) {
    throw 'PACKET_GATE_FAIL manifest artifact set incomplete; WSL was not invoked'
}
if (-not (Test-Path -LiteralPath $body -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $body).Hash -cne $expectedBodySha256) {
    throw 'PACKET_GATE_FAIL body hash mismatch; WSL was not invoked'
}
Assert-TransportPin -Path $transport -ExpectedHash $expectedTransportSha256

"PACKET_PREFLIGHT=PASS INVOCATION_ID=$invocationId HOST=$expectedHost DISTRO=$expectedDistro CWD=$expectedWorkingDirectory"
& $transport -BashBodyPath $body -Distro $expectedDistro -WorkingDirectory $expectedWorkingDirectory
if ($LASTEXITCODE -ne 0) { throw "SOURCE_EXCERPT_FAIL exit=$LASTEXITCODE" }
