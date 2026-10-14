$ErrorActionPreference = 'Stop'

# PowerShell 5 can strip the inner quotes when a script string is passed directly
# to bash.exe -lc from an -EncodedCommand process. This proves the safe route:
# encode the Bash body, then send only a simple base64 pipeline through -lc.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/automation/remote-bash-arg-selftest.ps1

$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) {
    throw "Git Bash not found: $bash"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "kah-arg-regression-$PID"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$fake = Join-Path $tempRoot 'stobe-auto'
$fakeBody = @'
#!/usr/bin/env bash
printf 'argc=%s\n' "$#"
printf 'arg0=<%s>\n' "$1"
printf 'arg1=<%s>\n' "$2"
printf 'arg2=<%s>\n' "$3"
'@
Set-Content -LiteralPath $fake -Value $fakeBody -Encoding ascii

function ConvertTo-GitBashPath([string]$path) {
    $full = [IO.Path]::GetFullPath($path)
    if ($full.Length -lt 3 -or $full[1] -ne ':') {
        throw "Expected a drive-qualified path: $full"
    }
    '/' + $full.Substring(0, 1).ToLowerInvariant() + $full.Substring(2).Replace('\', '/')
}

$bin = ConvertTo-GitBashPath $tempRoot
$cases = @(
    @{ Target = 'Paste [Worker]'; Text = 'Hello there, how is business?' },
    @{ Target = 'Paste [Worker]'; Text = 'I can''t stay; she said "hello, there".' }
)
$passed = 0
try {
    # Reproduce the exact failing shape: an encoded Windows PowerShell script
    # passes a raw quoted shell string to Git Bash through a native argument.
    $unsafeScript = @'
$cmd='export PATH="__BIN__:$PATH"; stobe-auto stobe_say "Paste" "Hello there, how is business"'
& '__BASH__' -lc $cmd
'@
    $unsafeScript = $unsafeScript.Replace('__BIN__', $bin).Replace('__BASH__', $bash)
    $unsafeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($unsafeScript))
    $unsafeOutput = @(& cmd.exe /c powershell.exe -NoProfile -EncodedCommand $unsafeEncoded 2>&1 |
        ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -or $unsafeOutput.Count -ne 4 -or
        $unsafeOutput[0] -ne 'argc=3' -or $unsafeOutput[1] -ne 'arg0=<stobe_say>' -or
        $unsafeOutput[2] -ne 'arg1=<Paste>' -or $unsafeOutput[3] -ne 'arg2=<Hello>') {
        throw "Expected raw -lc invocation to reproduce first-word truncation: $($unsafeOutput -join ' | ')"
    }

    foreach ($case in $cases) {
        $targetB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($case.Target))
        $textB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($case.Text))
        $bashBody = @'
export PATH="__BIN__:$PATH"
stobe-auto stobe_say "$(printf %s __TARGET__ | base64 -d)" "$(printf %s __TEXT__ | base64 -d)"
'@
        $bashBody = $bashBody.Replace('__BIN__', $bin).Replace('__TARGET__', $targetB64).Replace('__TEXT__', $textB64)
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bashBody))
        $command = "printf '%s' $payload | base64 -d | bash -s"
        $output = @(& $bash -lc $command 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -ne 0) {
            throw "Git Bash failed: $($output -join ' | ')"
        }
        if ($output.Count -ne 4 -or $output[0] -ne 'argc=3' -or
            $output[1] -ne 'arg0=<stobe_say>' -or
            $output[2] -ne "arg1=<$($case.Target)>" -or
            $output[3] -ne "arg2=<$($case.Text)>") {
            throw "Argument boundary mismatch for '$($case.Text)': $($output -join ' | ')"
        }
        ++$passed
    }
} finally {
    $safeRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedRoot = [IO.Path]::GetFullPath($tempRoot)
    if (-not $resolvedRoot.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing cleanup outside temp directory: $resolvedRoot"
    }
    if (Test-Path -LiteralPath $fake) { Remove-Item -LiteralPath $fake -Force }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Force }
}

"RESULT REMOTE_BASH_ARG PASS cases=$passed unsafe=first-word-truncation safe=base64-payload"
