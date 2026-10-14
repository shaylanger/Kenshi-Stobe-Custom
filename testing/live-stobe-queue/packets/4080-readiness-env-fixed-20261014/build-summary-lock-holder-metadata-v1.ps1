param(
    [string]$OutputPath = (Join-Path $env:TEMP '4080-summary-lock-holder-metadata.sh')
)
$ErrorActionPreference='Stop'
$sourcePath = Join-Path $PSScriptRoot 'summary-lock-holder-metadata-v1.py'
$source = [IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8)
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
$body = @"
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
printf '%s' '$encoded' | base64 -d | MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -
"@
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$body,[Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256 | Select-Object Path,Hash
