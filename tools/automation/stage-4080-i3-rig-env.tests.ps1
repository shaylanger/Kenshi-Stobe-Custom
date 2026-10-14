$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stage-4080-i3-rig-env.ps1')

$script:passed = 0
$script:failed = 0
function Check([string]$Name,[scriptblock]$Body) {
  try { if (-not (& $Body)) { throw 'assertion false' }; $script:passed++; Write-Output "PASS $Name" }
  catch { $script:failed++; Write-Output "FAIL $Name : $($_.Exception.Message)" }
}
function New-MockOps {
  $script:mock = [ordered]@{ identity=[pscustomobject]@{ Alias='4080'; Hostname='DESKTOP-NQQPA73' }; copyStatus='COPIED'; copyHash=$script:StageSourceHash; copyCount=1; copyOwned=$true; commitStatus='COMMITTED'; commitHash=$script:StageSourceHash; commitPath=$script:StageDestination; copyCalls=0; commitCalls=0; cleanup=(New-Object 'System.Collections.Generic.List[string]'); destinationHash=$script:StageBaselineHash; stagePath=''; destinationWriteCount=0 }
  $mockRef=$script:mock
  $probe = { $mockRef.identity }.GetNewClosure()
  $copy = {
    param($source,$remote)
    $mockRef.copyCalls++; $mockRef.stagePath=$remote.StagePath
    [pscustomobject]@{ Status=$mockRef.copyStatus; Hash=$mockRef.copyHash; FileCount=$mockRef.copyCount; Owned=$mockRef.copyOwned }
  }.GetNewClosure()
  $commit = {
    param($remote)
    $mockRef.commitCalls++
    if ($mockRef.commitStatus -eq 'COMMITTED' -and $mockRef.destinationHash -in @($remote.BaselineHash,$remote.ExpectedHash)) {
      $mockRef.destinationHash=$mockRef.commitHash; $mockRef.destinationWriteCount++
    }
    [pscustomobject]@{ Status=$mockRef.commitStatus; Hash=$mockRef.commitHash; Destination=$mockRef.commitPath }
  }.GetNewClosure()
  $cleanup = { param($token) $mockRef.cleanup.Add($token); $true }.GetNewClosure()
  $token = { '0123456789abcdef0123456789abcdef' }
  @{ Probe=$probe; Copy=$copy; Commit=$commit; Cleanup=$cleanup; TokenFactory=$token }
}
function Invoke-Mock($ops) { Invoke-StageTransaction -Probe $ops.Probe -Copy $ops.Copy -Commit $ops.Commit -Cleanup $ops.Cleanup -TokenFactory $ops.TokenFactory }
function New-ProcessReply([int]$ExitCode,[string[]]$Lines=@()) { [pscustomobject]@{ ExitCode=$ExitCode; Lines=@($Lines) } }
function Test-StageArgOption([string[]]$Arguments,[string]$Expected) {
  for ($i=0; $i -lt $Arguments.Count; $i++) {
    if ($Arguments[$i] -ceq '-o' -and $i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -ceq $Expected) { return $true }
    if ($Arguments[$i] -ceq "-o$Expected") { return $true }
  }
  return $false
}
function Invoke-MockedRealStage([bool]$ConfigPresent,[object[]]$Replies) {
  $oldConfig=(Get-Item Function:Test-StageSshConfig).ScriptBlock
  $oldProcess=(Get-Item Function:Invoke-StageProcess).ScriptBlock
  $oldToken=(Get-Item Function:New-StageToken).ScriptBlock
  $state=[pscustomobject]@{ ConfigPresent=$ConfigPresent; Replies=@($Replies); Calls=(New-Object 'System.Collections.Generic.List[object]'); Index=0; Result=$null; Failure=$null; ExitCode=$null }
  $configMock={ $state.ConfigPresent }.GetNewClosure()
  $tokenMock={ '0123456789abcdef0123456789abcdef' }
  $processMock={
    param([string]$FilePath,[string[]]$ArgumentList)
    $state.Calls.Add([pscustomobject]@{ FilePath=$FilePath; Arguments=@($ArgumentList) })
    if ($state.Index -ge $state.Replies.Count) { throw 'unexpected mocked subprocess' }
    $reply=$state.Replies[$state.Index]; $state.Index++
    $reply
  }.GetNewClosure()
  try {
    Set-Item Function:Test-StageSshConfig $configMock
    Set-Item Function:Invoke-StageProcess $processMock
    Set-Item Function:New-StageToken $tokenMock
    try { $state.Result=Invoke-RealStage }
    catch { $state.Failure=Format-StageFailureResult; $state.ExitCode=Get-StageProcessExitCode }
  } finally {
    Set-Item Function:Test-StageSshConfig $oldConfig
    Set-Item Function:Invoke-StageProcess $oldProcess
    Set-Item Function:New-StageToken $oldToken
  }
  $state
}
function Expected-HostReply { New-ProcessReply 0 @('DESKTOP-NQQPA73') }
function Expected-SuccessReplies {
  @(
    (Expected-HostReply),
    (New-ProcessReply 0),
    (New-ProcessReply 0),
    (New-ProcessReply 0 @('COMMITTED /c/KenshiModding/tools/automation/rig-env.sh b27297da77992325e35aa58c038fbbab5d638d5273c6c03453ecc9c401dded1c')),
    (New-ProcessReply 0)
  )
}

Check 'exact pinned candidate bytes, patch and destination' {
  (Get-StageHash $script:StageSource) -ceq 'B27297DA77992325E35AA58C038FBBAB5D638D5273C6C03453ECC9C401DDED1C' -and
  (Get-StageHash $script:StagePatch) -ceq '0A9569F48B330BF0A8DAB7EB290A600556B688485C35F14F92D46D7AF1FACC0F' -and
  $script:StageDestination -ceq 'C:\KenshiModding\tools\automation\rig-env.sh' -and $script:StageAlias -ceq '4080' -and $script:StageHost -ceq 'DESKTOP-NQQPA73'
}
Check 'fixed hash cannot be weakened by invocation input' { (Get-Command Invoke-StageTransaction).Parameters.ContainsKey('Hash') -eq $false }
Check 'successful one-file atomic replace' {
  New-MockOps | ForEach-Object { $o=$_; $r=Invoke-Mock $o; $r.Status -eq 'PASS' -and $r.FileCount -eq 1 -and $script:mock.destinationHash -eq $script:StageSourceHash -and $script:mock.destinationWriteCount -eq 1 }
}
Check 'wrong alias fails before copy' { $o=New-MockOps; $script:mock.identity=[pscustomobject]@{Alias='other';Hostname='DESKTOP-NQQPA73'}; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.copyCalls -eq 0 } }
Check 'wrong host fails before copy' { $o=New-MockOps; $script:mock.identity=[pscustomobject]@{Alias='4080';Hostname='OTHER-PC'}; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.copyCalls -eq 0 } }
Check 'remote preflight failure fails closed before copy' { $o=New-MockOps; $o.Probe={ throw 'mock preflight failure' }; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.copyCalls -eq 0 } }
Check 'traversal and alternate destinations rejected' { -not (Test-StageRemotePath 'C:\KenshiModding\..\other\rig-env.sh') -and -not (Test-StageRemotePath 'C:\KenshiModding\tools\setup.sh') }
Check 'reparse-point source redirection rejected' {
  $link=Join-Path $script:StageWorkspace ('testing\live-stobe-queue\.stager-reparse-' + [guid]::NewGuid().ToString('N'))
  $target=Join-Path $script:StageWorkspace 'testing\live-stobe-queue'
  $created=$false
  try {
    # Windows PowerShell 5.1 does not consistently expose Junction through
    # New-Item. cmd's built-in mklink creates a real directory reparse point
    # without prompting, so this continues to exercise the production check.
    $command='mklink /J "{0}" "{1}"' -f $link,$target
    $mklinkOutput=@(& $env:ComSpec /d /c $command 2>&1)
    $mklinkExit=$LASTEXITCODE
    if ($mklinkExit -ne 0 -or -not (Test-Path -LiteralPath $link)) {
      $detail=($mklinkOutput | ForEach-Object { [string]$_ }) -join ' | '
      throw "junction fixture creation failed (exit=$mklinkExit): $detail"
    }
    $created=$true
    $item=Get-Item -LiteralPath $link -Force
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'mklink fixture is not a reparse point' }
    if (Test-StagePathSafe (Join-Path $link 'redirected.sh') $script:StageWorkspace) { throw 'production path check accepted a path through the junction' }
    $true
  } finally {
    if ($created -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link,$false) }
  }
}
Check 'unique validated same-volume C KAH stage path' { $o=New-MockOps; Invoke-Mock $o | Out-Null; $script:mock.stagePath -match '^C:\\KAH\\stage-rig-env-[a-f0-9]{32}$' }
Check 'stale source pin fails closed before network adapters' {
  $o=New-MockOps; $old=(Get-Item Function:Get-StageHash).ScriptBlock
  try { Set-Item Function:Get-StageHash { param($Path) '0' * 64 }; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.copyCalls -eq 0 } }
  finally { Set-Item Function:Get-StageHash $old }
}
Check 'copy failure never renames and cleans only owned stage' { $o=New-MockOps; $script:mock.copyStatus='FAILED'; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.commitCalls -eq 0 -and $script:mock.cleanup.Count -eq 1 -and $script:mock.cleanup[0] -eq '0123456789abcdef0123456789abcdef' } }
Check 'partial/multiple-file copy is rejected before rename' { $o=New-MockOps; $script:mock.copyCount=2; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.commitCalls -eq 0 } }
Check 'staged hash mismatch never renames' { $o=New-MockOps; $script:mock.copyHash='0' * 64; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.commitCalls -eq 0 } }
Check 'candidate TOCTOU hash change stops before commit' {
  $o=New-MockOps; $old=(Get-Item Function:Get-StageHash).ScriptBlock; $script:hashCall=0
  try { Set-Item Function:Get-StageHash { param($Path) $script:hashCall++; if ($script:hashCall -ge 4) { '0' * 64 } else { 'B27297DA77992325E35AA58C038FBBAB5D638D5273C6C03453ECC9C401DDED1C' } }; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.commitCalls -eq 0 } }
  finally { Set-Item Function:Get-StageHash $old }
}
Check 'no-overwrite on unexpected existing destination' { $o=New-MockOps; $script:mock.destinationHash='F' * 64; $script:mock.commitStatus='REJECTED'; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.destinationHash -eq ('F' * 64) -and $script:mock.destinationWriteCount -eq 0 } }
Check 'missing destination is rejected without rename or write' { $o=New-MockOps; $script:mock.destinationHash='absent'; $script:mock.commitStatus='REJECTED'; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.destinationHash -eq 'absent' -and $script:mock.destinationWriteCount -eq 0 } }
Check 'atomic rename failure preserves old destination' { $o=New-MockOps; $script:mock.commitStatus='RENAME_FAILED'; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.destinationHash -eq $script:StageBaselineHash -and $script:mock.destinationWriteCount -eq 0 } }
Check 'final hash mismatch is a failure and preserves prior bytes' { $o=New-MockOps; $script:mock.commitHash='0' * 64; $script:mock.commitStatus='HASH_FAILED'; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.destinationHash -eq $script:StageBaselineHash -and $script:mock.destinationWriteCount -eq 0 } }
Check 'invalid/colliding stage token rejected before copy' { $o=New-MockOps; $o.TokenFactory={ '../collision' }; try { Invoke-Mock $o | Out-Null; $false } catch { $script:mock.copyCalls -eq 0 } }
Check 'sanitized terminal output contains no exception detail' {
  $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stage-4080-i3-rig-env.ps1') -Raw
  $text.Contains('Format-StageFailureResult') -and -not $text.Contains('$($_.Exception.Message)') -and
    -not $text.Contains('$_.Exception.Message') -and $text.Contains('native_exit=')
}
Check 'local SSH config preflight has a fixed sanitized phase and no process call' {
  $r=Invoke-MockedRealStage $false @()
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=local_ssh_config_identity_preflight' -and $r.Calls.Count -eq 0 -and $r.ExitCode -eq 1
}
Check 'remote host subprocess failure preserves exact native exit and hides output' {
  $r=Invoke-MockedRealStage $true @((New-ProcessReply 255 @('PRIVATE_KEY_PATH','secret stderr')))
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=remote_host_preflight native_exit=255' -and $r.ExitCode -eq 255 -and
    $r.Failure -notmatch 'PRIVATE|secret|stderr' -and $r.Calls.Count -eq 1
}
Check 'remote hostname mismatch is sanitized and nonzero overall despite native zero' {
  $r=Invoke-MockedRealStage $true @((New-ProcessReply 0 @('wrong-host','sensitive extra output')))
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=remote_host_preflight native_exit=0' -and $r.ExitCode -eq 1 -and
    $r.Failure -notmatch 'wrong-host|sensitive' -and $r.Calls.Count -eq 1
}
Check 'remote mkdir host check failure is classified as host preflight' {
  $r=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 30 @('raw host output')))
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=remote_host_preflight native_exit=30' -and $r.ExitCode -eq 30 -and $r.Calls.Count -eq 2
}
Check 'remote mkdir failure is classified as stage copy with native status' {
  $r=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 35 @('raw mkdir error')))
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=remote_stage_mkdir_copy native_exit=35' -and $r.ExitCode -eq 35 -and $r.Calls.Count -eq 2
}
Check 'SCP failure is classified, preserves status, and cleans only the owned stage' {
  $r=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 255 @('raw scp stderr')),(New-ProcessReply 0))
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=remote_stage_mkdir_copy native_exit=255' -and $r.ExitCode -eq 255 -and
    $r.Failure -notmatch 'raw|stderr' -and $r.Calls.Count -eq 4 -and $r.Calls[3].FilePath -eq 'ssh.exe'
}
Check 'atomic commit rejection maps every fixed remote failure code without leaking text' {
  $cases=@(
    @{ Code=31; Phase='atomic_commit' }, @{ Code=32; Phase='remote_stage_mkdir_copy' },
    @{ Code=33; Phase='atomic_commit' }, @{ Code=34; Phase='baseline_rollback' },
    @{ Code=41; Phase='atomic_commit' }, @{ Code=42; Phase='final_hash_verification' },
    @{ Code=44; Phase='baseline_rollback' }, @{ Code=77; Phase='atomic_commit' }
  )
  foreach ($case in $cases) {
    $replies=@((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply $case.Code @('secret remote detail')))
    if ($case.Code -ne 44) { $replies += (New-ProcessReply 0) }
    $r=Invoke-MockedRealStage $true $replies
    $expected="RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=$($case.Phase) native_exit=$($case.Code)"
    if ($case.Code -in @(41,44,77)) {
      $phase=if ($case.Code -eq 44) { 'baseline_rollback' } else { 'atomic_commit' }
      $recovery='C:\KAH\stage-rig-env-0123456789abcdef0123456789abcdef'
      $retained="RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=$phase native_exit=$($case.Code) recovery_path=$recovery"
      if ($r.Failure -cne $retained -or $r.Calls.Count -ne 4) { return $false }
    } elseif ($r.Failure -ne $expected -or $r.Calls.Count -ne 5) { return $false }
    if ($r.ExitCode -ne $case.Code -or $r.Failure -match 'secret|detail') { return $false }
  }
  $true
}
Check 'rollback failure retains owned stage and baseline backup for recovery' {
  $r=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply 44 @('private remote output')))
  if ($r.Failure -notmatch '^RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=baseline_rollback native_exit=44 recovery_path=C:\\KAH\\stage-rig-env-[a-f0-9]{32}$' -or $r.Calls.Count -ne 4 -or $r.ExitCode -ne 44) { return $false }
  $command=[string]$r.Calls[3].Arguments[-1]
  if ($command -notmatch "echo ([A-Za-z0-9+/=]+) \| base64 -d \| bash") { return $false }
  $scriptText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
  $scriptText.Contains('cp -p "$dst" "$stage/rollback"') -and
    $scriptText.Contains('cp -p "$stage/rollback" "$dst" || exit 44') -and
    -not $scriptText.Contains('mv -f "$stage/rollback" "$dst"') -and
    $scriptText.Contains('test "$restored" = "$base" || exit 44')
}
Check 'atomic commit protocol rejects malformed stdout as sanitized failure' {
  $replies=@((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply 0 @('COMMITTED /wrong/path secret')))
  $r=Invoke-MockedRealStage $true $replies
  $r.Failure -eq 'RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=atomic_commit native_exit=0 recovery_path=C:\KAH\stage-rig-env-0123456789abcdef0123456789abcdef' -and
    $r.ExitCode -eq 1 -and $r.Calls.Count -eq 4 -and $r.Failure -notmatch 'wrong/path|secret'
}
Check 'successful mocked transaction retains exact staged receipt and cleanup' {
  $r=Invoke-MockedRealStage $true (Expected-SuccessReplies)
  if ($r.Failure -ne $null -or $r.Result.Status -ne 'PASS' -or $r.Result.Sha256 -ne $script:StageSourceHash -or $r.Calls.Count -ne 5) { return $false }
  $cleanupCommand=[string]$r.Calls[4].Arguments[-1]
  $cleanupCommand -match "echo ([A-Za-z0-9+/=]+) \| base64 -d \| bash" -and
    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1])) -match "rm -rf '/c/KAH/stage-rig-env-[a-f0-9]{32}'")
}
Check 'every mocked SSH/SCP invocation disables unsafe transport and has a bounded timeout' {
  $r=Invoke-MockedRealStage $true (Expected-SuccessReplies)
  if ($r.Failure -ne $null -or $r.Result.Status -ne 'PASS' -or $r.Calls.Count -lt 5) { return $false }
  $required=@('StrictHostKeyChecking=yes','ClearAllForwardings=yes','PermitLocalCommand=no','RequestTTY=no','ForwardAgent=no','ForwardX11=no','BatchMode=yes')
  foreach ($call in $r.Calls) {
    if ($call.FilePath -cnotin @('ssh.exe','scp.exe')) { return $false }
    $cfgIndex=[Array]::IndexOf([string[]]$call.Arguments,'-F')
    if ($cfgIndex -lt 0 -or $cfgIndex + 1 -ge $call.Arguments.Count -or $call.Arguments[$cfgIndex + 1] -cne $script:StageSshConfig) { return $false }
    foreach ($option in $required) { if (-not (Test-StageArgOption $call.Arguments $option)) { return $false } }
    $timeout=$null; $timeoutCount=0
    foreach ($arg in $call.Arguments) { if ($arg -match '^ConnectTimeout=(\d+)$') { $timeout=[int]$Matches[1] } }
    $timeoutCount=@($call.Arguments | Where-Object { $_ -match '^ConnectTimeout=\d+$' }).Count
    if ($timeoutCount -ne 1 -or $null -eq $timeout -or $timeout -lt 1 -or $timeout -gt 10) { return $false }
    if ($call.FilePath -ceq 'ssh.exe' -and ('-n' -notin $call.Arguments -or '-T' -notin $call.Arguments)) { return $false }
    if ($call.FilePath -ceq 'scp.exe' -and '-q' -notin $call.Arguments) { return $false }
  }
  @($r.Calls | Where-Object { $_.FilePath -ceq 'ssh.exe' }).Count -ge 4 -and
    @($r.Calls | Where-Object { $_.FilePath -ceq 'scp.exe' }).Count -ge 1
}
Check 'ambiguous commit transport failures retain token-owned stage and rollback backup' {
  $expectedPath='C:\KAH\stage-rig-env-0123456789abcdef0123456789abcdef'
  foreach ($nativeExit in @(41,44,77,255)) {
    $r=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply $nativeExit @('private remote detail')))
    $phase=if ($nativeExit -eq 44) { 'baseline_rollback' } else { 'atomic_commit' }
    $expected="RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=$phase native_exit=$nativeExit recovery_path=$expectedPath"
    if ($r.Failure -cne $expected -or $r.ExitCode -ne $nativeExit -or $r.Calls.Count -ne 4 -or $r.Failure -match 'private|detail|secret') { return $false }
    $commitCommand=[string]$r.Calls[3].Arguments[-1]
    if ($commitCommand -notmatch "echo ([A-Za-z0-9+/=]+) \| base64 -d \| bash") { return $false }
    $scriptText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
    $stagePosix=$expectedPath -replace '\\','/' -replace '^C:','/c'
    if (-not $scriptText.Contains('cp -p "$dst" "$stage/rollback"') -or
        -not $scriptText.Contains('mv -f "$src" "$dst"') -or
        -not $scriptText.Contains("src='$stagePosix/payload'") -or
        $scriptText.Contains('rm -rf')) { return $false }
  }
  $true
}
Check 'ambiguous exit-zero commit receipt retains recovery artifacts' {
  $expected='RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=atomic_commit native_exit=0 recovery_path=C:\KAH\stage-rig-env-0123456789abcdef0123456789abcdef'
  $empty=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply 0 ([string[]]@())))
  if ($empty.Failure -cne $expected -or $empty.ExitCode -ne 1 -or $empty.Calls.Count -ne 4) { return $false }
  $malformed=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply 0 @('unexpected commit response')))
  $malformed.Failure -ceq $expected -and $malformed.ExitCode -eq 1 -and $malformed.Calls.Count -eq 4 -and $malformed.Failure -notmatch 'unexpected|private'
}
Check 'recovery token does not leak from ambiguous commit into next preflight failure' {
  $expectedPath='C:\KAH\stage-rig-env-0123456789abcdef0123456789abcdef'
  $ambiguous=Invoke-MockedRealStage $true @((Expected-HostReply),(New-ProcessReply 0),(New-ProcessReply 0),(New-ProcessReply 255 @('private remote detail')))
  $firstExpected="RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=atomic_commit native_exit=255 recovery_path=$expectedPath"
  if ($ambiguous.Failure -cne $firstExpected -or $ambiguous.Calls.Count -ne 4) { return $false }
  $preflight=Invoke-MockedRealStage $false @()
  $secondExpected='RESULT 4080-I3-RIG-ENV-STAGE FAIL phase=local_ssh_config_identity_preflight'
  $preflight.Failure -ceq $secondExpected -and $preflight.ExitCode -eq 1 -and $preflight.Calls.Count -eq 0 -and $preflight.Failure -notmatch 'recovery_path='
}
Check 'native process adapter preserves exit status and suppresses stderr' {
  # `echo TEXT ` includes the space before `&` in cmd.exe output; use echo( and
  # no separator whitespace so this checks exact sentinel bytes, not shell syntax.
  $command='echo(STAGE_STDOUT_SENTINEL&echo(STAGE_STDERR_SENTINEL 1>&2&exit /b 23'
  # Capture every stream from the adapter call so a leaked ErrorRecord or
  # success-stream diagnostic cannot disappear into the test harness.
  $observed=@(Invoke-StageProcess $env:ComSpec @('/d','/c',$command) 2>&1)
  $details=@($observed | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { 'error=' + $_.ToString() }
    elseif ($null -ne $_.PSObject.Properties['ExitCode'] -and $null -ne $_.PSObject.Properties['Lines']) {
      'result(exit=' + $_.ExitCode + ',lines=' + (@($_.Lines | ForEach-Object { [string]$_ }) -join '|') + ')'
    } else { 'output=' + [string]$_ }
  }) -join '; '
  if ($observed.Count -ne 1 -or $null -eq $observed[0].PSObject.Properties['ExitCode'] -or $null -eq $observed[0].PSObject.Properties['Lines']) {
    throw "unexpected adapter output: $details"
  }
  $r=$observed[0]
  $lines=@($r.Lines | ForEach-Object { [string]$_ })
  if ([int]$r.ExitCode -ne 23 -or $lines.Count -ne 1 -or $lines[0] -cne 'STAGE_STDOUT_SENTINEL' -or
      $details -match 'STAGE_STDERR_SENTINEL') {
    throw "native adapter mismatch: exit=$($r.ExitCode); lines=$($lines -join '|'); observed=$details"
  }
  $true
}
Check 'remote rollback script distinguishes final verification from rollback failure' {
  $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stage-4080-i3-rig-env.ps1') -Raw
  $text.Contains('restore_baseline') -and $text.Contains('exit 42') -and $text.Contains('exit 44') -and
    $text.Contains("'final_hash_verification'") -and $text.Contains("'baseline_rollback'")
}

Write-Output "RESULT 4080-I3-STAGER-TESTS $(if($script:failed){'FAIL'}else{'PASS'}) passed=$script:passed failed=$script:failed remote_calls=mock_only"
if ($script:failed) { exit 1 }


