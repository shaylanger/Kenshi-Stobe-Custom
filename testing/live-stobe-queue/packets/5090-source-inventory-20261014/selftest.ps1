$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$body = Get-Content -LiteralPath (Join-Path $dir 'inventory.sh') -Raw
$readme = Get-Content -LiteralPath (Join-Path $dir 'README.md') -Raw
$runner = Get-Content -LiteralPath (Join-Path $dir 'run.ps1') -Raw
$parseTokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($runner, [ref]$parseTokens, [ref]$parseErrors)
$checks = @(
    @{ Name='host pinned and enforced'; Ok=$runner.Contains('$expectedHost = ''DESKTOP-JFLPK99''') -and $runner.Contains('$env:COMPUTERNAME -cne $expectedHost') -and $readme.Contains('Host alias: `5090`, enforced as Windows hostname `DESKTOP-JFLPK99`') },
    @{ Name='distro pinned'; Ok=$body.Contains('DISTRO=DwemerAI4Skyrim3') -and $readme.Contains('DwemerAI4Skyrim3') },
    @{ Name='only documented roots'; Ok=$body.Contains('/var/www/html/StobeServer') -and $body.Contains('/root/stobe-work/ss-merge') -and $body -notmatch '/home/|/mnt/[a-z]/|/etc/' },
    @{ Name='no service routes'; Ok=$readme.Contains('`:8083`') -and $readme.Contains('`:18083`') -and $body -notmatch 'curl|wget|psql|pg_isready|8083|18083|http://' },
    @{ Name='no SSH or runtime actions'; Ok=$body -notmatch 'ssh|scp|systemctl|service |start_env|stobe-server|kenshi|save|POST|UPDATE|DELETE|INSERT' },
    @{ Name='only allowlisted manifests/sources'; Ok=$body.Contains('SOURCE-MANIFEST.json A9-BASELINE-SOURCE-MANIFEST.json MANIFEST.md server-manifest.json') -and $body.Contains('interaction.php lib/playthrough_preferences.php lib/playthrough_runtime.php lib/playthrough_switching.php lib/travel_companionship.php lib/chat_helper_functions.php lib/activity/ActivityService.php') },
    @{ Name='hash only, no source content'; Ok=$body.Contains('sha256sum') -and $body -notmatch 'cat |sed |awk |grep ' },
    @{ Name='canonical parent containment'; Ok=$body.Contains('realpath -e -- "$path"') -and $body.Contains('"$root/$rel"') },
    @{ Name='hash failures fail closed'; Ok=$body.Contains('raw=$(sha256sum -- "$target" 2>/dev/null) || return 1') -and $body.Contains('set -uo pipefail') },
    @{ Name='exact command documented'; Ok=$readme.Contains('C:\KenshiModding\testing\live-stobe-queue\packets\5090-source-inventory-20261014\run.ps1') -and $runner.Contains('invoke-wsl-captured.ps1') -and $runner.Contains('-BashBodyPath $body -Distro DwemerAI4Skyrim3 -WorkingDirectory /mnt/c/KenshiModding') },
    @{ Name='PowerShell syntax'; Ok=$parseErrors.Count -eq 0 }
)
$failed = @($checks | Where-Object { -not $_.Ok })
if ($failed.Count) { $failed | ForEach-Object { "FAIL $($_.Name)" }; throw "packet checks failed=$($failed.Count)" }
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw "Git Bash missing for local syntax check: $bash" }
& $bash -n (Join-Path $dir 'inventory.sh')
if ($LASTEXITCODE -ne 0) { throw "bash -n failed exit=$LASTEXITCODE" }
"RESULT 5090-SOURCE-INVENTORY-SELFTEST PASS cases=$($checks.Count) shell_syntax=pass runtime_contact=no"
