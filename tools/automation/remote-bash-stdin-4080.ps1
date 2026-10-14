param(
    [string]$BodyPath,
    [string]$SshConfig = 'C:\Users\Shay\.ssh\config',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# Keep the large Bash body out of both Windows CreateProcess command lines. The
# only remote command argument is a small, fixed PowerShell receiver encoded
# with the verified PS5 UTF-16LE -EncodedCommand convention. The UTF-8 Bash
# bytes travel as Base64 on SSH stdin and are then written byte-for-byte to
# Git Bash's stdin.
$script:RemoteReceiver = @'
$ErrorActionPreference = 'Stop'
if ([Environment]::MachineName -cne 'DESKTOP-NQQPA73') { throw 'Refusing remote Bash body on an unexpected host' }
$encodedBody = [Console]::In.ReadToEnd()
$bodyBytes = [Convert]::FromBase64String($encodedBody)
$body = [Text.Encoding]::UTF8.GetString($bodyBytes).TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
$routePreamble = "export RIG=4080 KAH_INSTANCE=3`nexport KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3`nexport KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'`n"
$rigEnvLine = '. /c/KenshiModding/tools/automation/rig-env.sh' + "`n"
if (-not $body.StartsWith(($routePreamble + $rigEnvLine), [StringComparison]::Ordinal)) { throw 'Isolated-i3 preamble drift' }
$remainingBody = $body.Substring(($routePreamble + $rigEnvLine).Length)
$readonlyRoute = "readonly -x RIG=4080 KAH_INSTANCE=3 KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3 KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'`n"
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($routePreamble + $rigEnvLine + $readonlyRoute + $remainingBody)
$bash = New-Object System.Diagnostics.Process
$bash.StartInfo.FileName = 'C:\Program Files\Git\bin\bash.exe'
$bash.StartInfo.Arguments = '-s'
$bash.StartInfo.UseShellExecute = $false
$bash.StartInfo.RedirectStandardInput = $true
$bash.StartInfo.RedirectStandardOutput = $true
$bash.StartInfo.RedirectStandardError = $true
$null = $bash.Start()
$stdout = $bash.StandardOutput.ReadToEndAsync()
$stderr = $bash.StandardError.ReadToEndAsync()
$inputStream = $bash.StandardInput.BaseStream
$inputStream.Write($bodyBytes, 0, $bodyBytes.Length)
$inputStream.Close()
$bash.WaitForExit()
[Console]::Out.Write($stdout.Result)
[Console]::Error.Write($stderr.Result)
exit $bash.ExitCode
'@

function Get-ReceiverEncodedCommand {
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script:RemoteReceiver))
}

function Get-SshArguments([string]$config) {
    $receiver = Get-ReceiverEncodedCommand
    '-F "{0}" -o BatchMode=yes -o ConnectTimeout=8 4080 powershell.exe -NoProfile -NonInteractive -EncodedCommand {1}' -f $config, $receiver
}

function Assert-IsolatedI3Body([string]$body) {
    $body = $body.TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
    $routePreamble = @'
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
'@ + "`n"
    if (-not $body.StartsWith($routePreamble, [StringComparison]::Ordinal)) {
        throw 'Refusing remote body without the exact explicit isolated-i3 route preamble'
    }
    $tail = $body.Substring($routePreamble.Length)
    $rigEnvLine = '. /c/KenshiModding/tools/automation/rig-env.sh' + "`n"
    if (-not $tail.StartsWith($rigEnvLine, [StringComparison]::Ordinal)) {
        throw 'Refusing remote body without the trusted rig-env setup immediately after the i3 preamble'
    }
    $tail = $tail.Substring($rigEnvLine.Length)
    if ($tail -match '(?i)\b(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\s*=' -or
        $tail -match '(?i)\bunset\s+(?:-v\s+)?(?:RIG|KAH_INSTANCE|KENSHI_DIR|KDIR|KAH_DIR)\b' -or
        $tail -match '(?im)(?:^|[;&|\s])(?:command\s+)?(?:env|eval|exec|source)\b' -or
        $tail -match '(?im)(?:^|[;&|\s])\.\s+') {
        throw 'Refusing remote body that could override or unset isolated-i3 routing'
    }
}

function Invoke-RemoteBashBody([string]$path, [string]$config) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bash body file not found: $path" }
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "Trusted SSH config not found: $config" }
    $bodyBytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($path))
    $body = [Text.Encoding]::UTF8.GetString($bodyBytes).TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
    Assert-IsolatedI3Body $body
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
    $payload = [Convert]::ToBase64String($bodyBytes)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'ssh.exe'
    $psi.Arguments = Get-SshArguments $config
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $ssh = New-Object System.Diagnostics.Process
    $ssh.StartInfo = $psi
    $null = $ssh.Start()
    $stdout = $ssh.StandardOutput.ReadToEndAsync()
    $stderr = $ssh.StandardError.ReadToEndAsync()
    $ssh.StandardInput.Write($payload)
    $ssh.StandardInput.Close()
    $ssh.WaitForExit()
    [Console]::Out.Write($stdout.Result)
    [Console]::Error.Write($stderr.Result)
    exit $ssh.ExitCode
}

function Invoke-TransportSelfTest {
    $bodyPrefix = @'
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
'@
    $bodyPrefix = $bodyPrefix.Replace("`r`n", "`n").Replace("`r", "`n")
    $arguments = Get-SshArguments 'C:\Users\Shay\.ssh\config'
    $commandLineLength = ('ssh.exe ' + $arguments).Length
    $receiverLength = (Get-ReceiverEncodedCommand).Length
    if ($script:RemoteReceiver -notmatch 'DESKTOP-NQQPA73' -or $commandLineLength -ge 8192 -or $receiverLength -ge 8192) {
        throw "Fixed transport command unexpectedly large: cmd=$commandLineLength receiver=$receiverLength"
    }

    $cases = @(
        @{ Name = 'near Windows limit'; Size = 30000 },
        @{ Name = 'past Windows limit'; Size = 50000 },
        @{ Name = 'large body'; Size = 250000 }
    )
    foreach ($case in $cases) {
        $paddingLength = $case.Size - [Text.Encoding]::UTF8.GetByteCount($bodyPrefix)
        $body = $bodyPrefix + "`n# synthetic padding begins`n" + ('x' * ($paddingLength - 30)) + "`n# synthetic end`n"
        Assert-IsolatedI3Body $body
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $payload = [Convert]::ToBase64String($bytes)
        $roundTrip = [Convert]::FromBase64String($payload)
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]]$roundTrip)) {
            throw "UTF-8 transport round-trip failed for $($case.Name)"
        }
        if ($payload.Length -le 32767 -and $case.Size -gt 32767) {
            throw "Fixture failed to cross the CreateProcess argument limit: $($case.Name)"
        }
    }
    # Reproduce the failure class without SSH: the old wrapper nested the
    # complete UTF-8/Base64 Bash body inside a PowerShell -EncodedCommand
    # argument. CreateProcess rejects that oversized native command line.
    $failingBody = $bodyPrefix + "`n#" + ('x' * 30000)
    $nestedBashPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($failingBody))
    $unsafePs = '$bashPayload = ''' + $nestedBashPayload + '''; $null = $bashPayload'
    $unsafePsEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($unsafePs))
    $unsafe = New-Object System.Diagnostics.ProcessStartInfo
    $unsafe.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $unsafe.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + $unsafePsEncoded
    $unsafe.UseShellExecute = $false
    $unsafeRejected = $false
    try {
        $oversized = [Diagnostics.Process]::Start($unsafe)
        if ($oversized) { $oversized.WaitForExit(); throw 'Oversized legacy command unexpectedly started' }
    } catch [ComponentModel.Win32Exception] {
        $unsafeRejected = $true
    }
    if (-not $unsafeRejected) { throw 'Synthetic legacy PS/SSH wrapper did not reproduce the CreateProcess command-line rejection' }
    $badBody = "export RIG=4080 KAH_INSTANCE=1`nexport KENSHI_DIR=/c/KenshiInst/1`nexport KAH_DIR=/c/KenshiInst/1/mods/AutomationHarness`n"
    $rejected = $false
    try { Assert-IsolatedI3Body $badBody } catch { $rejected = $true }
    if (-not $rejected) { throw 'Non-i3 body was not rejected' }
    $overrideCases = @("`nexport KAH_INSTANCE=1", "`nunset KAH_DIR", "`nKDIR=/c/KenshiInst/1 stobe-auto status", "`nenv -u KAH_DIR stobe-auto status", "`neval 'KAH_INSTANCE=1'", "`n. /tmp/route-override.sh")
    foreach ($override in $overrideCases) {
        $rejected = $false
        try { Assert-IsolatedI3Body ($bodyPrefix + $override) } catch { $rejected = $true }
        if (-not $rejected) { throw "i3 override fixture was accepted: $override" }
    }
    "RESULT 4080-REMOTE-BASH-STDIN PASS cases=$($cases.Count) max_body=250000 legacy_createprocess=blocked route_guard=4 fail-closed command_chars=$commandLineLength receiver_chars=$receiverLength"
}

if ($SelfTest) { Invoke-TransportSelfTest; exit 0 }
if (-not $BodyPath) { throw 'Usage: remote-bash-stdin-4080.ps1 -BodyPath <UTF-8 Bash file> [-SshConfig <trusted config>]' }
Invoke-RemoteBashBody $BodyPath $SshConfig
