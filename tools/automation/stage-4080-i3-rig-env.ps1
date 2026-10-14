[CmdletBinding()]
param([switch]$Invoke)
$ErrorActionPreference = 'Stop'

# Exact one-file 4080/i3 staging helper. Dot-source for mock-only tests; -Invoke
# is deliberately separate and requires a later, fresh authorization review.
$script:StageWorkspace = 'C:\KenshiModding'
$script:StageSource = 'C:\KenshiModding\testing\live-stobe-queue\4080-i3-rig-env-helper.candidate.sh'
$script:StageSourceHash = 'B27297DA77992325E35AA58C038FBBAB5D638D5273C6C03453ECC9C401DDED1C'
$script:StagePatch = 'C:\KenshiModding\testing\live-stobe-queue\4080-i3-rig-env-helper.patch'
$script:StagePatchHash = '0A9569F48B330BF0A8DAB7EB290A600556B688485C35F14F92D46D7AF1FACC0F'
$script:StagePatchHeadBlob = '5a3ea33397b7aeda55aebdbe127115d65a24446c'
$script:StageAlias = '4080'
$script:StageHost = 'DESKTOP-NQQPA73'
$script:StageDestination = 'C:\KenshiModding\tools\automation\rig-env.sh'
$script:StageDestinationPosix = '/c/KenshiModding/tools/automation/rig-env.sh'
$script:StageBaselineHash = 'FE94F1DF613EBE52E0854E84B16BE0179EAD370BE6E7024C09C4BD69E798665D'
$script:StageSshConfig = 'C:\Users\Shay\.ssh\config'
$script:StageFailurePhase = 'local_preflight'
$script:StageNativeExitCode = $null
$script:StageRecoveryPath = $null
$script:StageRetainRecovery = $false

function Get-StageHash([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Test-StagePathSafe([string]$Path, [string]$Root) {
  try { $full = [IO.Path]::GetFullPath($Path); $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') }
  catch { return $false }
  if (-not $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
  $cursor = $base
  foreach ($part in $full.Substring($base.Length).TrimStart('\') -split '\\') {
    $cursor = Join-Path $cursor $part
    if (Test-Path -LiteralPath $cursor) {
      if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    }
  }
  return $true
}
function Assert-StageInputs {
  if (-not (Test-StagePathSafe $script:StageSource $script:StageWorkspace) -or
      -not (Test-StagePathSafe $script:StagePatch $script:StageWorkspace)) { throw 'pinned source path rejected' }
  if (-not (Test-Path -LiteralPath $script:StageSource -PathType Leaf) -or
      -not (Test-Path -LiteralPath $script:StagePatch -PathType Leaf)) { throw 'pinned source is missing' }
  if ((Get-StageHash $script:StagePatch) -cne $script:StagePatchHash) { throw 'candidate patch pin mismatch' }
  if ((Get-StageHash $script:StageSource) -cne $script:StageSourceHash) { throw 'candidate source pin mismatch' }
  # Hash again immediately before transfer. Caller rechecks after the copy adapter
  # returns, closing the ordinary source-swap/TOCTOU window.
  return [pscustomobject]@{ Source=$script:StageSource; Sha256=$script:StageSourceHash; Destination=$script:StageDestination }
}
function New-StageToken { [guid]::NewGuid().ToString('N') }
function Set-StageFailure {
  param([Parameter(Mandatory)][string]$Phase,[Nullable[int]]$NativeExitCode=$null,[switch]$RetainRecovery)
  $script:StageFailurePhase = $Phase
  $script:StageNativeExitCode = $NativeExitCode
  if ($RetainRecovery) { $script:StageRetainRecovery = $true }
  # Never propagate a native diagnostic, remote output, or exception text.
  throw 'stage operation failed'
}
function Set-StagePhase([Parameter(Mandatory)][string]$Phase) {
  $script:StageFailurePhase = $Phase
  $script:StageNativeExitCode = $null
}
function Format-StageFailureResult {
  $line = "RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=$($script:StageFailurePhase)"
  if ($null -ne $script:StageNativeExitCode) { $line += " native_exit=$($script:StageNativeExitCode)" }
  if ($script:StageRecoveryPath -match '^C:\\KAH\\stage-rig-env-[a-f0-9]{32}$') { $line += " recovery_path=$($script:StageRecoveryPath)" }
  return $line
}
function Get-StageProcessExitCode {
  if ($null -eq $script:StageNativeExitCode -or [int]$script:StageNativeExitCode -eq 0) { return 1 }
  return [int]$script:StageNativeExitCode
}
function Test-StageSshConfig {
  Test-Path -LiteralPath $script:StageSshConfig -PathType Leaf
}
function Get-StageTransportOptions([int]$ConnectTimeout) {
  if ($ConnectTimeout -lt 1 -or $ConnectTimeout -gt 30) { throw 'transport timeout rejected' }
  @(
    '-o','StrictHostKeyChecking=yes',
    '-o','ClearAllForwardings=yes',
    '-o','ForwardAgent=no',
    '-o','ForwardX11=no',
    '-o','PermitLocalCommand=no',
    '-o','RequestTTY=no',
    '-o','BatchMode=yes',
    '-o',("ConnectTimeout=$ConnectTimeout")
  )
}
function ConvertTo-StageWindowsArgument([AllowEmptyString()][string]$Argument) {
  # ProcessStartInfo.Arguments is a single command-line string on Windows
  # PowerShell 5.1. Quote according to the Windows CRT rules so spaces,
  # embedded quotes, and trailing backslashes survive as one argument.
  if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') { return $Argument }
  $builder = New-Object Text.StringBuilder
  [void]$builder.Append('"')
  $slashes = 0
  foreach ($character in $Argument.ToCharArray()) {
    if ($character -eq [char]92) { $slashes++; continue }
    if ($character -eq [char]34) {
      if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes + 1)) }
      else { [void]$builder.Append([char]92) }
      [void]$builder.Append([char]34)
      $slashes = 0
      continue
    }
    if ($slashes -gt 0) { [void]$builder.Append([char]92, $slashes) }
    [void]$builder.Append($character)
    $slashes = 0
  }
  if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
  [void]$builder.Append('"')
  $builder.ToString()
}
function Invoke-StageProcess {
  param([Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string[]]$ArgumentList)
  # Do not invoke native programs through PowerShell's pipeline: Windows
  # PowerShell 5.1 can turn redirected native stderr into NativeCommandError
  # records before `2>$null` suppresses them. Directly redirect both .NET streams,
  # consume stderr privately, and preserve stdout's protocol lines and exit code.
  $startInfo = New-Object Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FilePath
  $startInfo.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-StageWindowsArgument ([string]$_) }) -join ' ')
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { throw 'native process start failed' }
    # Read stdout and drain stderr asynchronously to avoid pipe deadlocks.
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    # PowerShell may surface the runtime's internal VoidTaskResult here even
    # though CopyToAsync is semantically void; explicitly discard it so the
    # adapter emits only its structured result object.
    [void]$stderrTask.GetAwaiter().GetResult()
    $nativeExit = [int]$process.ExitCode
  } finally {
    $process.Dispose()
  }
  $lines = @()
  if ($stdout.Length -gt 0) {
    $splitLines = [regex]::Split($stdout, "\r\n|\n|\r")
    $lineCount = $splitLines.Length
    if ($stdout.EndsWith("`n") -or $stdout.EndsWith("`r")) { $lineCount-- }
    for ($i = 0; $i -lt $lineCount; $i++) { $lines += [string]$splitLines[$i] }
  }
  [pscustomobject]@{ ExitCode=$nativeExit; Lines=$lines }
}
function Test-StageIdentity($Identity) {
  return ($Identity -and $Identity.Alias -ceq $script:StageAlias -and $Identity.Hostname -ceq $script:StageHost)
}
function Test-StageRemotePath([string]$Path) {
  return ($Path -ceq $script:StageDestination -and $Path -notmatch '[.]{2}|[\\/]$')
}
function Invoke-StageTransaction {
  param(
    [Parameter(Mandatory)][scriptblock]$Probe,
    [Parameter(Mandatory)][scriptblock]$Copy,
    [Parameter(Mandatory)][scriptblock]$Commit,
    [scriptblock]$Cleanup = { param($token) $true },
    [scriptblock]$TokenFactory = { New-StageToken }
  )
  $plan = Assert-StageInputs
  $identity = & $Probe
  if (-not (Test-StageIdentity $identity)) { throw 'remote identity check failed' }
  $token = & $TokenFactory
  if ($token -notmatch '^[a-f0-9]{32}$') { throw 'stage token rejected' }
  $stage = "C:\KAH\stage-rig-env-$token"
  if ($stage -notmatch '^C:\\KAH\\stage-rig-env-[a-f0-9]{32}$') { throw 'stage path rejected' }
  $remote = [pscustomobject]@{ Alias=$script:StageAlias; Hostname=$script:StageHost; StagePath=$stage; Destination=$script:StageDestination; ExpectedHash=$script:StageSourceHash; BaselineHash=$script:StageBaselineHash }
  $before = Get-StageHash $plan.Source
  if ($before -cne $plan.Sha256) { throw 'candidate changed before transfer' }
  $owned = $false
  $script:StageRetainRecovery = $false
  $script:StageRecoveryPath = $null
  try {
    $copyResult = & $Copy $plan.Source $remote
    $owned = [bool]($copyResult -and $copyResult.Owned)
    if (-not $copyResult -or $copyResult.Status -cne 'COPIED' -or $copyResult.Hash -cne $plan.Sha256 -or $copyResult.FileCount -ne 1) {
      if ($copyResult -and $null -ne $copyResult.NativeExitCode) {
        Set-StageFailure 'remote_stage_mkdir_copy' ([int]$copyResult.NativeExitCode)
      }
      throw 'single-file stage copy failed verification'
    }
    if ((Get-StageHash $plan.Source) -cne $plan.Sha256) { throw 'candidate changed during transfer' }
    $commitResult = & $Commit $remote
    if (-not $commitResult -or $commitResult.Status -cne 'COMMITTED' -or $commitResult.Hash -cne $plan.Sha256 -or
        -not (Test-StageRemotePath $commitResult.Destination)) { throw 'atomic destination commit failed verification' }
    return [pscustomobject]@{ Status='PASS'; Alias=$script:StageAlias; Hostname=$script:StageHost; Destination=$script:StageDestination; Sha256=$plan.Sha256; FileCount=1 }
  } finally {
    if ($owned) {
      if ($script:StageRetainRecovery) {
        # Exit 44 means the remote baseline restore itself failed. Keep the
        # operation-owned stage (including its rollback copy) for recovery.
        $script:StageRecoveryPath = $stage
      } else {
        [void](& $Cleanup $token)
      }
    }
  }
}

function Invoke-RealStage {
  # Reset every receipt field before local preflight: a failure here must never
  # leak a recovery token or native exit code from a previous invocation.
  $script:StageFailurePhase = 'local_ssh_config_identity_preflight'
  $script:StageNativeExitCode = $null
  $script:StageRecoveryPath = $null
  $script:StageRetainRecovery = $false
  $cfg = $script:StageSshConfig
  $alias = $script:StageAlias
  $expectedHost = $script:StageHost
  $sourceHash = $script:StageSourceHash
  $baselineHash = $script:StageBaselineHash
  $destination = $script:StageDestination
  $destinationPosix = $script:StageDestinationPosix
  if (-not (Test-StageSshConfig)) { Set-StageFailure 'local_ssh_config_identity_preflight' }
  $probe = {
    Set-StagePhase 'remote_host_preflight'
    $result = Invoke-StageProcess 'ssh.exe' (@('-F',$cfg,'-n','-T') + (Get-StageTransportOptions 8) + @($alias,'hostname'))
    if ($result.ExitCode -ne 0) { Set-StageFailure 'remote_host_preflight' $result.ExitCode }
    if ($result.Lines.Count -ne 1 -or $result.Lines[0].Trim() -cne $expectedHost) { Set-StageFailure 'remote_host_preflight' $result.ExitCode }
    [pscustomobject]@{ Alias=$alias; Hostname=$result.Lines[0].Trim() }
  }.GetNewClosure()
  $copy = {
    param($source,$remote)
    $stagePosix = $remote.StagePath -replace '\\','/' -replace '^C:','/c'
    $prep = "test `"`$(hostname)`" = '$expectedHost' || exit 30; mkdir '$stagePosix' || exit 35"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($prep))
    Set-StagePhase 'remote_stage_mkdir_copy'
    $prepResult = Invoke-StageProcess 'ssh.exe' (@('-F',$cfg,'-n','-T') + (Get-StageTransportOptions 8) + @($alias,"C:\PROGRA~1\Git\bin\bash.exe -lc 'echo $b64 | base64 -d | bash'"))
    if ($prepResult.ExitCode -ne 0) {
      $phase = if ($prepResult.ExitCode -eq 30) { 'remote_host_preflight' } else { 'remote_stage_mkdir_copy' }
      Set-StageFailure $phase $prepResult.ExitCode
    }
    $copyResult = Invoke-StageProcess 'scp.exe' (@('-F',$cfg,'-q') + (Get-StageTransportOptions 8) + @($source,"${alias}:$stagePosix/payload"))
    if ($copyResult.ExitCode -ne 0) { return [pscustomobject]@{ Status='FAILED'; Owned=$true; NativeExitCode=$copyResult.ExitCode } }
    [pscustomobject]@{ Status='COPIED'; Hash=$sourceHash; FileCount=1; Owned=$true }
  }.GetNewClosure()
  $commit = {
    param($remote)
    # The remote script refuses unexpected pre-existing files and checks the staged
    # byte hash before a same-volume mv. The destination may be replaced only when
    # it is the exact HEAD baseline or already the exact candidate.
    $scriptText = @"
set -e
test "`$(hostname)" = '$expectedHost' || exit 30
src='/c/KAH/stage-rig-env-$($remote.StagePath.Split('-')[-1])/payload'
dst='$destinationPosix'
stage="`${src%/payload}"
want='$($sourceHash.ToLowerInvariant())'
base='$($baselineHash.ToLowerInvariant())'
test "`$(realpath -m "`$dst")" = "`$dst" || exit 31
test "`$(realpath -m "`$stage")" = "`$stage" || exit 31
test ! -L "`$dst" || exit 31
test "`$(find "`$stage" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" = 1 || exit 32
test -f "`$src" || exit 32
got=`$(sha256sum "`$src" | cut -d' ' -f1) || exit 32
test "`$got" = "`$want" || exit 32
if test -f "`$dst"; then old=`$(sha256sum "`$dst" | cut -d' ' -f1) || exit 33; test "`$old" = "`$base" || test "`$old" = "`$want" || exit 33; else exit 33; fi
if test "`$old" != "`$want"; then
  if test "`$old" = "`$base"; then cp -p "`$dst" "`$stage/rollback" || exit 34; backup=`$(sha256sum "`$stage/rollback" | cut -d' ' -f1) || exit 34; test "`$backup" = "`$base" || exit 34; fi
  mv -f "`$src" "`$dst" || exit 41
fi
restore_baseline() {
  if test -f "`$stage/rollback"; then cp -p "`$stage/rollback" "`$dst" || exit 44; restored=`$(sha256sum "`$dst" | cut -d' ' -f1) || exit 44; test "`$restored" = "`$base" || exit 44; else rm -f "`$dst" || exit 44; fi
}
final=`$(sha256sum "`$dst" | cut -d' ' -f1) || { restore_baseline; exit 42; }
if test "`$final" != "`$want"; then
  restore_baseline
  exit 42
fi
printf 'COMMITTED %s %s\\n' "`$dst" "`$final"
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($scriptText))
    Set-StagePhase 'atomic_commit'
    # Once commit transport starts, a lost or malformed response cannot prove
    # whether the remote rename happened. Keep the token-owned backup until the
    # response proves a valid commit or a definitive pre-mutation/rollback code.
    $script:StageRetainRecovery = $true
    $commitProcess = Invoke-StageProcess 'ssh.exe' (@('-F',$cfg,'-n','-T') + (Get-StageTransportOptions 10) + @($alias,"C:\PROGRA~1\Git\bin\bash.exe -lc 'echo $b64 | base64 -d | bash'"))
    if ($commitProcess.ExitCode -ne 0) {
      $phase = switch ($commitProcess.ExitCode) {
        30 { 'remote_host_preflight' }
        31 { 'atomic_commit' }
        32 { 'remote_stage_mkdir_copy' }
        33 { 'atomic_commit' }
        34 { 'baseline_rollback' }
        41 { 'atomic_commit' }
        42 { 'final_hash_verification' }
        44 { 'baseline_rollback' }
        default { 'atomic_commit' }
      }
      $ambiguous = $commitProcess.ExitCode -notin @(30,31,32,33,34,42)
      $script:StageRetainRecovery = [bool]$ambiguous
      Set-StageFailure $phase $commitProcess.ExitCode -RetainRecovery:$ambiguous
    }
    $lines = $commitProcess.Lines
    if ($lines.Count -ne 1 -or $lines[0] -notmatch '^COMMITTED /c/KenshiModding/tools/automation/rig-env\.sh ([0-9a-f]{64})$' -or $Matches[1] -cne $sourceHash.ToLowerInvariant()) { Set-StageFailure 'atomic_commit' $commitProcess.ExitCode -RetainRecovery }
    $script:StageRetainRecovery = $false
    [pscustomobject]@{ Status='COMMITTED'; Destination=$destination; Hash=$Matches[1].ToUpperInvariant() }
  }.GetNewClosure()
  $cleanup = {
    param($token)
    $remotePath = "C:\KAH\stage-rig-env-$token"
    $cmd = "test `"`$(hostname)`" = '$expectedHost' && rm -rf '/c/KAH/stage-rig-env-$token'"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
    $cleanupResult = Invoke-StageProcess 'ssh.exe' (@('-F',$cfg,'-n','-T') + (Get-StageTransportOptions 8) + @($alias,"C:\PROGRA~1\Git\bin\bash.exe -lc 'echo $b64 | base64 -d | bash'"))
    return ($cleanupResult.ExitCode -eq 0)
  }.GetNewClosure()
  Invoke-StageTransaction -Probe $probe -Copy $copy -Commit $commit -Cleanup $cleanup
}

if ($Invoke -and $MyInvocation.InvocationName -ne '.') {
  try { $r=Invoke-RealStage; Write-Output "RESULT 4080-I3-RIG-ENV-STAGE $($r.Status) alias=4080 host=DESKTOP-NQQPA73 destination=C:\KenshiModding\tools\automation\rig-env.sh sha256=$($r.Sha256) files=1"; exit 0 }
  catch { Write-Output (Format-StageFailureResult); exit (Get-StageProcessExitCode) }
}
