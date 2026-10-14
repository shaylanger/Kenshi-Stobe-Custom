param(
    [Parameter(Mandatory=$true)][ValidateSet('pause','rollback')][string]$Mode,
    [string]$ExpectedUpdatedAt,
    [string]$OutputPath = (Join-Path $env:TEMP ('4080-summary-interval-' + $Mode + '.sh'))
)
$ErrorActionPreference='Stop'
if ($Mode -eq 'pause' -and $ExpectedUpdatedAt) { throw 'Pause mode takes no timestamp' }
if ($Mode -eq 'rollback' -and $ExpectedUpdatedAt -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}$') { throw 'Rollback needs the exact updated_at returned by the pause CAS' }
$sourcePath = Join-Path $PSScriptRoot 'memory-summary-interval-gate.py'
$source = [IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8)
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
$tail = if ($Mode -eq 'rollback') { "'$Mode' '$ExpectedUpdatedAt'" } else { "'$Mode'" }
$body = @"
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail
rig4080_i3_preflight
printf '%s' '$encoded' | base64 -d | MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 - $tail
"@
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$body,[Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256 | Select-Object Path,Hash