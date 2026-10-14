$ErrorActionPreference = 'Stop'
$expectedHost = 'DESKTOP-JFLPK99'
if ($env:COMPUTERNAME -cne $expectedHost) {
    throw "HOST_GATE_FAIL expected=$expectedHost actual=$env:COMPUTERNAME; WSL was not invoked"
}
$body = Join-Path $PSScriptRoot 'inventory.sh'
$transport = 'C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1'
if (-not (Test-Path -LiteralPath $body -PathType Leaf)) { throw 'PACKET_GATE_FAIL body missing' }
if (-not (Test-Path -LiteralPath $transport -PathType Leaf)) { throw 'PACKET_GATE_FAIL transport missing' }
"HOST_PREFLIGHT=PASS HOST_ALIAS=5090 COMPUTERNAME=$expectedHost"
& $transport -BashBodyPath $body -Distro DwemerAI4Skyrim3 -WorkingDirectory /mnt/c/KenshiModding
if ($LASTEXITCODE -ne 0) { throw "INVENTORY_FAIL exit=$LASTEXITCODE" }
