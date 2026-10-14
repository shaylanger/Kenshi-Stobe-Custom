param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$checks = @(
    @{ Path = Join-Path $PSScriptRoot 'rig-runner.ps1'; Need = @('-F $trusted4080SshConfig', 'DESKTOP-NQQPA73', 'refusing ambient alias') },
    @{ Path = Join-Path $PSScriptRoot 'rig-lane2-4080.ps1'; Need = @('-F $cfg', 'DESKTOP-NQQPA73', 'scp.exe -F') },
    @{ Path = Join-Path $PSScriptRoot 'list-rigcheck.sh'; Need = @('SSH_CONFIG=', 'SSH_BIN=', '"$SSH_BIN" -F "$SSH_CONFIG"', "route_host" , 'DESKTOP-NQQPA73') }
)
foreach ($check in $checks) {
    $text = Get-Content -LiteralPath $check.Path -Raw
    foreach ($needle in $check.Need) {
        if (-not $text.Contains($needle)) { throw "4080 route drift: $($check.Path) is missing '$needle'" }
    }
    if ($text -match 'ssh(?:\.exe)?\s+-n\s+-o\s+BatchMode=yes\s+-o\s+ConnectTimeout=\d+\s+4080') {
        throw "4080 route drift: ambient alias invocation remains in $($check.Path)"
    }
}
# Host verification is deliberately based on the remote `hostname` command's
# stdout. Simulate the guard's PowerShell join/trim behavior without invoking
# ssh or reading the local COMPUTERNAME environment variable.
$expectedHost = 'DESKTOP-NQQPA73'
$hostCases = @(
    @{ Name = 'remote 4080 hostname'; Lines = @('DESKTOP-NQQPA73'); ExitCode = 0; Pass = $true },
    @{ Name = 'remote 5090 hostname'; Lines = @('KenshiModding-5090'); ExitCode = 0; Pass = $false },
    @{ Name = 'ssh failure'; Lines = @('DESKTOP-NQQPA73'); ExitCode = 255; Pass = $false }
)
foreach ($case in $hostCases) {
    $reportedHost = ($case.Lines -join '').Trim()
    $accepted = ($case.ExitCode -eq 0 -and $reportedHost -eq $expectedHost)
    if ($accepted -ne $case.Pass) { throw "4080 hostname guard fixture failed: $($case.Name) reported='$reportedHost' rc=$($case.ExitCode)" }
}
foreach ($path in @((Join-Path $PSScriptRoot 'rig-runner.ps1'), (Join-Path $PSScriptRoot 'rig-lane2-4080.ps1'))) {
    $text = Get-Content -LiteralPath $path -Raw
    if ($text -notmatch 'ssh\.exe\s+-F\s+\$\w+\s+-n[^\r\n]*4080\s+hostname') {
        throw "4080 hostname guard fixture failed: remote hostname probe missing in $path"
    }
}
"RESULT 4080-SSH-ROUTE PASS files=$($checks.Count) trusted_config=C:\Users\Shay\.ssh\config host=DESKTOP-NQQPA73"
