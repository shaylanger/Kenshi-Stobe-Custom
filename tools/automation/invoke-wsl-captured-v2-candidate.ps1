<#
Run one WSL command while preserving its stdout, stderr, and exit code.

Use for KAH operations that must return an ACK. Prefer -BashBodyPath: it sends
the UTF-8 body over stdin to a small receiver that stages the complete body
before executing it with `bash -s`. This prevents a fail-fast script from
closing the pipe while PowerShell is still writing the script. The default
fails closed when the process exits successfully without either output stream;
pass -AllowEmpty only for commands whose documented success response is empty.
This helper does not choose an instance, route, or command and is not a
substitute for the relevant preflight.
#>
param(
    [string]$BashBodyPath,
    [string]$Distro = 'DwemerAI4Skyrim3',
    [string]$WorkingDirectory = '/mnt/c/KenshiModding',
    [string]$Executable = 'wsl.exe',
    [switch]$AllowEmpty,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Invoke-CapturedProcess([string]$file, [string]$arguments, [byte[]]$inputBytes = $null, [hashtable]$environment = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $null -ne $inputBytes
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($null -ne $environment) {
        foreach ($name in $environment.Keys) { $psi.EnvironmentVariables[$name] = [string]$environment[$name] }
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $inputError = $null
    if ($null -ne $inputBytes) {
        try {
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.BaseStream.Flush()
        } catch {
            # A WSL startup/receiver failure can close stdin before all bytes
            # arrive. Preserve the child's own streams and exit status so the
            # caller sees the actionable failure instead of only a PowerShell
            # "pipe has been ended" exception.
            $inputError = $_.Exception.Message
        } finally {
            try { $process.StandardInput.Close() } catch {}
        }
    }
    $process.WaitForExit()
    $captured = [pscustomobject]@{
        Stdout = $stdoutTask.Result
        Stderr = $stderrTask.Result
        ExitCode = $process.ExitCode
        InputError = $inputError
    }
    $process.Dispose()
    $captured
}

function Get-TransportResult($result, [bool]$allowEmpty, [bool]$quiet = $false) {
    $hasOutput = -not [string]::IsNullOrWhiteSpace($result.Stdout) -or -not [string]::IsNullOrWhiteSpace($result.Stderr)
    if ($result.InputError) {
        if (-not $quiet) { [Console]::Error.WriteLine("TRANSPORT FAIL stdin delivery failed; child_exit=$($result.ExitCode); error=$($result.InputError)") }
        if ($result.ExitCode -ne 0) { return [int]$result.ExitCode }
        return 125
    }
    if ($result.ExitCode -ne 0) {
        if (-not $hasOutput -and -not $quiet) { [Console]::Error.WriteLine("TRANSPORT FAIL child exited $($result.ExitCode) with no stdout/stderr") }
        return [int]$result.ExitCode
    }
    if (-not $hasOutput -and -not $allowEmpty) {
        if (-not $quiet) { [Console]::Error.WriteLine('TRANSPORT FAIL child exited 0 with empty stdout/stderr; expected an ACK') }
        return 2
    }
    return 0
}

function Get-BashBodyBytes([string]$path) {
    $bytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($path))
    $body = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
    return ,([Text.Encoding]::UTF8.GetBytes($body))
}

function Quote-ProcessArgument([string]$argument) {
    # WSL parses its own command line before Linux argv: quoted option names are treated as a command.
    if ($argument -match '^[A-Za-z0-9_./:=+-]+$') { return $argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $argument.ToCharArray()) {
        if ($character -eq [char]0x5c) { $slashes++; continue }
        if ($character -eq [char]0x22) {
            if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
            [void]$builder.Append('\"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
    [void]$builder.Append('"')
    $builder.ToString()
}

function Get-ProcessArgumentLine([string[]]$arguments) {
    (@($arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ')
}

function Get-WslBashReceiver {
    # Bash must read EOF before executing the body. The receiver stages stdin
    # to a private temporary file, then runs it from that regular file.
    'tmp=$(mktemp) || exit $?; trap ''rm -f -- "$tmp"'' EXIT; cat >"$tmp" || exit $?; bash -s <"$tmp"; exit $?'
}

function Get-WslBashArguments([string]$distro, [string]$workingDirectory) {
    # Prefer WSL's explicit long options and --exec so the command boundary
    # after --cd is unambiguous. The reported `/bin/bash: -d: command not
    # found` transport failure has not been reproduced locally; this change
    # is a candidate correction pending a separately reviewed exact invocation.
    Get-ProcessArgumentLine @('--distribution', $distro, '--user', 'root', '--cd', $workingDirectory, '--exec', 'bash', '-c', (Get-WslBashReceiver))
}

function Invoke-TransportSelfTest {
    $fixture = Join-Path ([IO.Path]::GetTempPath()) "wsl-captured-selftest-$PID.sh"
    try {
        # Use Git for Windows' bundled Bash directly. The `Git\bin` shim can
        # resolve to the WSL launcher on some installations, which would turn
        # a supposed local self-test into a real WSL attempt.
        $bash = 'C:\Program Files\Git\usr\bin\bash.exe'
        if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw "Git Bash not found for synthetic-only selftest: $bash" }
        $testEnvironment = @{ PATH = (Split-Path -Parent $bash) + ';' + $env:PATH }
        $argv = Get-WslBashArguments 'DwemerAI4Skyrim3' '/mnt/c/KenshiModding'
        if ($argv -notmatch '--distribution DwemerAI4Skyrim3 --user root --cd /mnt/c/KenshiModding --exec bash -c' -or
            -not $argv.Contains('mktemp') -or -not $argv.Contains('cat >') -or -not $argv.Contains('bash -s <')) {
            throw "unexpected fixed WSL argv/staged receiver: <$argv>"
        }
        if ($argv.Contains('"--"')) { throw "ambiguous WSL command separator remains: <$argv>" }
        $receiver = Get-WslBashReceiver
        $bashArgs = Get-ProcessArgumentLine @('-c', $receiver)
        $body = "printf 'synthetic-stdout\\n'; printf 'synthetic-stderr\\n' >&2; exit 7`n"
        [IO.File]::WriteAllBytes($fixture, [Text.Encoding]::UTF8.GetBytes($body))
        $capture = Invoke-CapturedProcess $bash $bashArgs (Get-BashBodyBytes $fixture) $testEnvironment
        $status = Get-TransportResult $capture $false
        if ($status -ne 7 -or $capture.Stdout -notmatch 'synthetic-stdout' -or $capture.Stderr -notmatch 'synthetic-stderr') {
            throw "nonzero stream/exit propagation failed: exit=$status stdout=<$($capture.Stdout)> stderr=<$($capture.Stderr)>"
        }

        [IO.File]::WriteAllBytes($fixture, [Text.Encoding]::UTF8.GetBytes("exit 0`n"))
        $empty = Invoke-CapturedProcess $bash $bashArgs (Get-BashBodyBytes $fixture) $testEnvironment
        $emptyStatus = Get-TransportResult $empty $false $true
        if ($emptyStatus -ne 2) { throw "empty-success response was accepted: exit=$emptyStatus" }
        $allowedStatus = Get-TransportResult $empty $true
        if ($allowedStatus -ne 0) { throw "explicitly allowed empty response failed: exit=$allowedStatus" }
        # PowerShell treats U+2019 as a quote delimiter. Build it from its code
        # point so this file parses under Windows PowerShell 5.1 as well.
        $unicodeWord = 'you' + [char]0x2019 + 'd'
        $unicodeBody = 'printf "<%s>\\n" "' + $unicodeWord + '"' + "`n"
        [IO.File]::WriteAllBytes($fixture, [Text.Encoding]::UTF8.GetBytes($unicodeBody))
        $unicode = Invoke-CapturedProcess $bash $bashArgs (Get-BashBodyBytes $fixture) $testEnvironment
        $expectedUnicode = 'you' + [char]0x2019 + 'd'
        if ($unicode.ExitCode -ne 0 -or $unicode.Stdout -notmatch [regex]::Escape($expectedUnicode)) { throw "UTF-8 stdin quoting failed: exit=$($unicode.ExitCode) output=<$($unicode.Stdout)>" }

        # The old `bash -s` pipe could break when a fail-fast body exited
        # before the host finished writing its tail. A staged receiver must
        # consume this whole large body before the child Bash can exit.
        $earlyExitBody = "exit 23`n# unread tail begins`n" + ('x' * 250000) + "`n# unread tail ends`n"
        [IO.File]::WriteAllBytes($fixture, [Text.Encoding]::UTF8.GetBytes($earlyExitBody))
        $earlyExit = Invoke-CapturedProcess $bash $bashArgs (Get-BashBodyBytes $fixture) $testEnvironment
        if ($earlyExit.ExitCode -ne 23 -or $earlyExit.InputError) {
            throw "staged early-exit body was truncated: exit=$($earlyExit.ExitCode) input_error=<$($earlyExit.InputError)>"
        }

        # Reproduce the old failure deterministically: the receiver closes
        # stdin immediately, while the parent attempts a multi-megabyte write.
        $closedArgs = Get-ProcessArgumentLine @('-c', "exec 0<&-; printf 'synthetic-child-output\\n'; printf 'synthetic-child-error\\n' >&2; sleep 0.25; exit 23")
        $closedPipe = Invoke-CapturedProcess $bash $closedArgs (New-Object byte[] (4 * 1024 * 1024)) $testEnvironment
        $closedStatus = Get-TransportResult $closedPipe $false $true
        if (-not $closedPipe.InputError -or $closedPipe.ExitCode -ne 23 -or $closedStatus -ne 23 -or
            $closedPipe.Stdout -notmatch 'synthetic-child-output' -or $closedPipe.Stderr -notmatch 'synthetic-child-error') {
            throw "closed-pipe diagnostic preservation failed: exit=$closedStatus input_error=<$($closedPipe.InputError)> stdout=<$($closedPipe.Stdout)> stderr=<$($closedPipe.Stderr)>"
        }
        'RESULT WSL-CAPTURED-TRANSPORT PASS cases=6 argv=explicit_distribution_user_cd_exec streams=stdout+stderr exit=7 empty_success=fail_closed allow_empty=explicit utf8_stdin=preserved staged_early_exit=complete early_close_diagnostics=preserved'
    } finally {
        Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) { Invoke-TransportSelfTest; exit 0 }
if (-not $BashBodyPath) { throw 'Usage: invoke-wsl-captured.ps1 -BashBodyPath <UTF-8 Bash script> [-Distro DwemerAI4Skyrim3] [-WorkingDirectory /mnt/c/KenshiModding] [-AllowEmpty]' }
if (-not (Test-Path -LiteralPath $BashBodyPath -PathType Leaf)) { throw "Bash body file not found: $BashBodyPath" }
$bodyBytes = Get-BashBodyBytes $BashBodyPath
$argumentLine = Get-WslBashArguments $Distro $WorkingDirectory
$captured = Invoke-CapturedProcess $Executable $argumentLine $bodyBytes
if ($captured.Stdout) { [Console]::Out.Write($captured.Stdout) }
if ($captured.Stderr) { [Console]::Error.Write($captured.Stderr) }
$resultCode = Get-TransportResult $captured ([bool]$AllowEmpty)
exit $resultCode
