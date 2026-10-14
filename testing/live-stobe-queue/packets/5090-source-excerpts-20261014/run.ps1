$ErrorActionPreference = 'Stop'
$expectedHost = 'DESKTOP-JFLPK99'
if ($env:COMPUTERNAME -cne $expectedHost) {
    throw "HOST_GATE_FAIL expected=$expectedHost actual=$env:COMPUTERNAME; WSL was not invoked"
}
if ((Test-Path Env:STOBE_PACKET_FIXTURE) -or (Test-Path Env:STOBE_PACKET_FIXTURE_PATH) -or (Test-Path Env:STOBE_PACKET_GIT_FIXTURE) -or (Test-Path Env:STOBE_PACKET_GIT_FIXTURE_ROOT) -or (Test-Path Env:STOBE_PACKET_GIT_FIXTURE_COMMIT) -or (Test-Path Env:STOBE_PACKET_GIT_FIXTURE_PATH)) {
    throw 'PACKET_GATE_FAIL fixture variables must not be inherited; WSL was not invoked'
}
$body = Join-Path $PSScriptRoot 'excerpt.sh'
$transport = 'C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1'
$expectedTransportSha256 = 'ED417184EAC849DEFCDCB9F49F969B037A6159B67431051E53FCF450E70667DF'
function Assert-TransportPin {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ExpectedHash)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'PACKET_GATE_FAIL transport missing' }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actual -cne $ExpectedHash) { throw "PACKET_GATE_FAIL transport hash mismatch expected=$ExpectedHash actual=$actual; WSL was not invoked" }
}
if (-not (Test-Path -LiteralPath $body -PathType Leaf)) { throw 'PACKET_GATE_FAIL body missing' }
Assert-TransportPin -Path $transport -ExpectedHash $expectedTransportSha256
$expectedBodySha256 = '388A2C1F2CAE8727523F09E50C7BBF867A492DC11CE3CB1C3A48BDBD061A9D7D'
$actualBodySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $body).Hash
if ($actualBodySha256 -cne $expectedBodySha256) { throw "PACKET_GATE_FAIL body hash mismatch expected=$expectedBodySha256 actual=$actualBodySha256; WSL was not invoked" }
"HOST_PREFLIGHT=PASS HOST_ALIAS=5090 COMPUTERNAME=$expectedHost"
& $transport -BashBodyPath $body -Distro DwemerAI4Skyrim3 -WorkingDirectory /mnt/c/KenshiModding
if ($LASTEXITCODE -ne 0) { throw "SOURCE_EXCERPT_FAIL exit=$LASTEXITCODE" }
