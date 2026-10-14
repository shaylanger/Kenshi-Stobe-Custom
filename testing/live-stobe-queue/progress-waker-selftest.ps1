[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$WakerPath,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$base=Join-Path $env:TEMP ('stobe-waker-self-'+[guid]::NewGuid().ToString('N'))
$script:caseCount=0
function Assert([bool]$ok,[string]$name){if(-not $ok){throw "SELFTEST FAIL $name"};$script:caseCount++;Write-Output "SELFTEST PASS $name"}
function Invoke-Waker([string]$fixtureRoot,[switch]$GuardOnly){
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-Once','-Root',('"'+$fixtureRoot+'"'))
  $a+='-SyntheticFixture';if($GuardOnly){$a+='-GuardOnlyFixture'}
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $fixtureRoot 'out.txt') -RedirectStandardError (Join-Path $fixtureRoot 'err.txt')
  if($p.ExitCode -ne 0){throw (Get-Content (Join-Path $fixtureRoot 'err.txt') -Raw)}
  Get-Content (Join-Path $fixtureRoot 'out.txt') -Raw -ErrorAction SilentlyContinue
}
function Events([string]$fixtureRoot){$p=Join-Path $fixtureRoot 'testing\live-stobe-queue\progress-waker\events.jsonl';if(Test-Path $p){Get-Content $p -Raw}else{''}}
function RemoteGameState([string]$fixtureRoot,[string]$gamePid,[switch]$QuerySucceeded){
  $out=Join-Path $fixtureRoot 'remote-state.out';$err=Join-Path $fixtureRoot 'remote-state.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-RemoteGameQueryFixture','-FixtureGamePid',('"'+$gamePid+'"'))
  if($QuerySucceeded){$a+='-FixtureQuerySucceeded'}
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  if($p.ExitCode -ne 0){throw (Get-Content $err -Raw)}
  (Get-Content $out -Raw).Trim()
}
function Validate-TargetSetFixture([string]$fixtureRoot){
  $out=Join-Path $fixtureRoot 'target-set.out';$err=Join-Path $fixtureRoot 'target-set.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-ValidateTargetSetFixture','-Root',('"'+$fixtureRoot+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  @{exit=$p.ExitCode;output=(Get-Content $out -Raw -ErrorAction SilentlyContinue).Trim()}
}
function WakerHash([string]$path){
  $out=Join-Path $base 'sha256.out';$err=Join-Path $base 'sha256.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-Sha256Fixture','-FixturePath',('"'+$path+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  if($p.ExitCode -ne 0){throw (Get-Content $err -Raw)}
  (Get-Content $out -Raw).Trim()
}
function Invoke-EventAppendFixture([string]$path){
  $out=Join-Path $base 'event-append.out';$err=Join-Path $base 'event-append.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-AppendEventFixture','-FixturePath',('"'+$path+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  @{exit=$p.ExitCode;output=(Get-Content $out -Raw -ErrorAction SilentlyContinue).Trim();error=(Get-Content $err -Raw -ErrorAction SilentlyContinue)}
}
function Invoke-PostOpenFailureFixture([string]$path){
  $out=Join-Path $base 'post-open-failure.out';$err=Join-Path $base 'post-open-failure.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-PostOpenFailureFixture','-FixturePath',('"'+$path+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  @{exit=$p.ExitCode;output=(Get-Content $out -Raw -ErrorAction SilentlyContinue).Trim();error=(Get-Content $err -Raw -ErrorAction SilentlyContinue)}
}
function Invoke-InteriorCorruptionFixture([string]$path){
  $out=Join-Path $base 'interior-corruption.out';$err=Join-Path $base 'interior-corruption.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-InteriorCorruptionFixture','-FixturePath',('"'+$path+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  @{exit=$p.ExitCode;output=(Get-Content $out -Raw -ErrorAction SilentlyContinue).Trim();error=(Get-Content $err -Raw -ErrorAction SilentlyContinue)}
}
function Invoke-ExclusiveRecoveryFixture([string]$path){
  $out=Join-Path $base 'exclusive-recovery.out';$err=Join-Path $base 'exclusive-recovery.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-ExclusiveRecoveryFixture','-FixturePath',('"'+$path+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  @{exit=$p.ExitCode;output=(Get-Content $out -Raw -ErrorAction SilentlyContinue).Trim();error=(Get-Content $err -Raw -ErrorAction SilentlyContinue)}
}
function Invoke-Utf8PartialSuffixFixture([string]$path){
  $out=Join-Path $base 'utf8-partial-suffix.out';$err=Join-Path $base 'utf8-partial-suffix.err'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$WakerPath+'"'),'-Utf8PartialSuffixFixture','-FixturePath',('"'+$path+'"'))
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  @{exit=$p.ExitCode;output=(Get-Content $out -Raw -ErrorAction SilentlyContinue).Trim();error=(Get-Content $err -Raw -ErrorAction SilentlyContinue)}
}
try {
  $schemaFixture=Get-Content (Join-Path $Root 'testing\live-stobe-queue\progress-waker\targets-schema-fixture.json') -Raw|ConvertFrom-Json
  Assert ($schemaFixture.schema -eq 2 -and $schemaFixture.pollSeconds -eq 120 -and $schemaFixture.rigs.Count -eq 2 -and $schemaFixture.rigs[0].source -eq 'local' -and $schemaFixture.rigs[0].uiActionId -and $schemaFixture.rigs[0].uiGeneration -eq 7 -and $schemaFixture.rigs[1].ssh.exe -eq 'C:\Windows\System32\OpenSSH\ssh.exe') 'frozen-two-rig-schema-fixture'
  $dir=Join-Path $base 'testing\live-stobe-queue\progress-waker';New-Item -ItemType Directory -Path $dir -Force|Out-Null
  $realSchema=Get-Content (Join-Path $Root 'testing\live-stobe-queue\progress-waker\targets-schema-fixture.json') -Raw|ConvertFrom-Json
  $realSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $validTargets=Validate-TargetSetFixture $base;Assert ($validTargets.exit -eq 0 -and $validTargets.output -eq 'TARGET_SET_VALID') 'strict-target-set-valid-two-rig-fixture'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs=@($badSchema.rigs[0],$badSchema.rigs[0]);$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'exactly one 4080 and one 5090') 'strict-target-set-rejects-duplicate-lane'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs=@($badSchema.rigs[0]);$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'exactly two rig entries') 'strict-target-set-rejects-missing-lane'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.schema=3;$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'schema must be version 2') 'strict-target-set-rejects-unknown-schema'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].uiGeneration=0;$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'UI generation outside') 'strict-target-set-rejects-invalid-ui-generation'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].request='chat-not-ui';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'exactly one request or UI action') 'strict-target-set-rejects-mixed-identities'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].phase='running-ish';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'phase outside allowed set') 'strict-target-set-rejects-unknown-phase'
  $terminalTargets=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json
  foreach($lane in $terminalTargets.rigs){$lane.row='none';$lane.request='';$lane.uiActionId='';$lane.uiGeneration=0;$lane.phase='complete_awaiting_next'}
  $terminalTargets|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $terminalResult=Validate-TargetSetFixture $base;Assert ($terminalResult.exit -eq 0 -and $terminalResult.output -eq 'TARGET_SET_VALID') 'terminal-phase-accepted-only-for-idle-lanes'
  $badSchema=$terminalTargets|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].row='KAH-TEST-5090';$badSchema.rigs[0].uiActionId='synthetic-ui-action-5090';$badSchema.rigs[0].uiGeneration=7;$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'phase outside allowed set') 'terminal-phase-rejects-active-row-identity'
  $badSchema=$terminalTargets|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].phase='complete-awaiting-next';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'phase outside allowed set') 'terminal-phase-rejects-hyphenated-near-match'
  $setupFailTargets=$terminalTargets|ConvertTo-Json -Depth 10|ConvertFrom-Json
  $setupFailTargets.rigs[0].phase='setup_fail';$setupFailTargets.rigs[0].receipt='C:\KenshiModding\testing\live-stobe-queue\KAH-CHAT-006-5090-preflight-setup-fail-20261014.receipt.md';$setupFailTargets.rigs[0].receiptSha256=('C'*64)
  $setupFailTargets|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $setupFailResult=Validate-TargetSetFixture $base;Assert ($setupFailResult.exit -eq 0 -and $setupFailResult.output -eq 'TARGET_SET_VALID') 'setup-failure-terminal-phase-accepted-with-pinned-idle-receipt'
  $badSchema=$setupFailTargets|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].rig='4080';$badSchema.rigs[1].rig='5090';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'phase outside allowed set') 'setup-failure-terminal-phase-rejects-cross-rig-receipt'
  $badSchema=$setupFailTargets|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].request='fake-request';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'phase outside allowed set') 'setup-failure-terminal-phase-rejects-active-identity'
  $badSchema=$terminalTargets|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].phase='setup-fail';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'phase outside allowed set') 'setup-failure-phase-rejects-hyphenated-near-match'
  $receiptOnly=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json
  $receiptOnly.rigs[1].row='none';$receiptOnly.rigs[1].request='';$receiptOnly.rigs[1].phase='complete_awaiting_next';$receiptOnly.rigs[1].receipt='C:\KenshiModding\testing\live-stobe-queue\KAH-CHAT-007-4080-session-read-setup-fail-20261014.receipt.md';$receiptOnly.rigs[1].receiptSha256=('A'*64)
  $receiptOnly.rigs[1]|Add-Member -NotePropertyName receiptOnly -NotePropertyValue $true
  $receiptOnly.rigs[1]|Add-Member -NotePropertyName lastCompletedRow -NotePropertyValue 'KAH-CHAT-007'
  $receiptOnly.rigs[1]|Add-Member -NotePropertyName lastCompletedRequest -NotePropertyValue ''
  $receiptOnly.rigs[1]|Add-Member -NotePropertyName lastCompletedActionId -NotePropertyValue ''
  $receiptOnly.rigs[1]|Add-Member -NotePropertyName lastCompletedGeneration -NotePropertyValue 0
  $receiptOnly|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $receiptTargets=Validate-TargetSetFixture $base;Assert ($receiptTargets.exit -eq 0 -and $receiptTargets.output -eq 'TARGET_SET_VALID') 'receipt-only-terminal-without-fabricated-id'
  $badSchema=$receiptOnly|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[1].phase='active';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'receipt-only terminal must be idle') 'receipt-only-rejects-active-phase'
  $badSchema=$receiptOnly|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[1].receiptSha256='';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'receipt-only terminal must be idle') 'receipt-only-requires-pinned-hash'
  $badSchema=$receiptOnly|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[1].lastCompletedRequest='made-up-request';$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'receipt-only terminal must be idle') 'receipt-only-rejects-fabricated-request'
  $badSchema=$receiptOnly|ConvertTo-Json -Depth 10|ConvertFrom-Json
  $badSchema.rigs[0].row='none';$badSchema.rigs[0].request='';$badSchema.rigs[0].phase='complete_awaiting_next';$badSchema.rigs[0].receipt='C:\KenshiModding\testing\live-stobe-queue\KAH-CHAT-007-5090-fake.receipt.md';$badSchema.rigs[0].receiptSha256=('B'*64);$badSchema.rigs[0].uiActionId='';$badSchema.rigs[0].uiGeneration=0
  $badSchema.rigs[0]|Add-Member -NotePropertyName receiptOnly -NotePropertyValue $true
  $badSchema.rigs[0]|Add-Member -NotePropertyName lastCompletedRow -NotePropertyValue 'KAH-CHAT-007'
  $badSchema.rigs[0]|Add-Member -NotePropertyName lastCompletedRequest -NotePropertyValue ''
  $badSchema.rigs[0]|Add-Member -NotePropertyName lastCompletedActionId -NotePropertyValue ''
  $badSchema.rigs[0]|Add-Member -NotePropertyName lastCompletedGeneration -NotePropertyValue 0
  $badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'receipt-only terminal must be idle') 'receipt-only-rejects-5090-lane'
  $badSchema=$realSchema|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badSchema.rigs[0].stallSeconds=30;$badSchema|ConvertTo-Json -Depth 10|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $badTargets=Validate-TargetSetFixture $base;Assert ($badTargets.exit -eq 2 -and $badTargets.output -match 'stallSeconds outside 120..3600') 'strict-target-set-rejects-invalid-stall-bound'
  $log=Join-Path $base 'stobe.log';Set-Content -LiteralPath $log -Value 'CHAT_SEND_STAGE request=req-123' -Encoding utf8
  $setupBase=Join-Path $base 'setup-failure-terminal';New-Item -ItemType Directory -Path $setupBase -Force|Out-Null
  $setupDir=Join-Path $setupBase 'testing\live-stobe-queue\progress-waker';New-Item -ItemType Directory -Path $setupDir -Force|Out-Null
  $setupReceipt=Join-Path $setupBase 'KAH-CHAT-006-5090-preflight-setup-fail-20261014.receipt.md'
  Set-Content -LiteralPath $setupReceipt -Value "KAH-CHAT-006`nRESULT KAH-CHAT-006 FAIL setup: synthetic preflight failure" -Encoding utf8
  $setupHash=(Get-FileHash -LiteralPath $setupReceipt -Algorithm SHA256).Hash
  $setupTargets=@{schema=1;pollSeconds=120;rigs=@(@{rig='5090';row='none';request='';phase='setup_fail';source='local';nativeLog=$log;receipt=$setupReceipt;receiptSha256=$setupHash;nextCandidate='synthetic next';gamePid=$PID;stallSeconds=30})}
  $setupTargets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $setupDir 'targets.json') -Encoding utf8
  Invoke-Waker $setupBase|Out-Null;$setupEvents=Events $setupBase
  Assert ($setupEvents.Contains('ROW_TERMINAL_SETUP_FAIL') -and $setupEvents.Contains('SETUP_FAIL_AWAITING_NEXT') -and -not $setupEvents.Contains('COMPLETE_AWAITING_NEXT') -and -not $setupEvents.Contains('ROW_TERMINAL_FAIL')) 'setup-failure-reported-distinct-from-pass-or-completion'
  $hashFixture=Join-Path $base 'sha256-fixture.txt';Set-Content -LiteralPath $hashFixture -Value 'sha256 compatibility fixture' -NoNewline -Encoding utf8
  $expectedHash=(Get-FileHash -LiteralPath $hashFixture -Algorithm SHA256).Hash
  Assert ((WakerHash $hashFixture) -eq $expectedHash) 'sha256-dotnet-compatibility-with-windows-powershell'
  $targets=@{schema=1;pollSeconds=120;rigs=@(@{rig='4080';row='CHAT-TEST';request='req-123';phase='active';source='local';nativeLog=$log;receipt=(Join-Path $base 'receipt.md');nextCandidate='next complex case';gamePid=$PID;stallSeconds=30})}
  $targets|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null
  $e=Events $base;Assert ($e.Contains('ROW_ADOPTED') -and $e.Contains('ROW_BASELINE') -and -not $e.Contains('ROW_PROGRESS')) 'baseline-does-not-count-as-progress'
  Add-Content -LiteralPath $log -Value 'NPC_SAY request=req-123 text=reply'
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('ROW_PROGRESS') 'exact-request-progress'
  $targets.rigs[0].row='CHAT-TEST-LONG';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  $longPrefix='CHAT_THREAD request=req-123 '+('x'*300);Set-Content -LiteralPath $log -Value ($longPrefix+'tail-A') -Encoding utf8;Invoke-Waker $base|Out-Null
  $beforeLong=([regex]::Matches((Events $base),'ROW_PROGRESS')).Count;Set-Content -LiteralPath $log -Value ($longPrefix+'tail-B') -Encoding utf8;Invoke-Waker $base|Out-Null
  $afterLong=([regex]::Matches((Events $base),'ROW_PROGRESS')).Count;Assert ($afterLong -gt $beforeLong) 'full-line-digest-detects-change-after-240-chars'
  $opfile=Join-Path $dir 'operators.json';@{schema=1;rigs=@{'4080'=@{operator='synthetic';status='active';updatedUtc=(Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')}}}|ConvertTo-Json -Depth 6|Set-Content $opfile
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('OPERATOR_HEARTBEAT_STALE') 'stale-operator-heartbeat'
  @{schema=1;rigs=@{'4080'=@{operator='synthetic';status='stopped';updatedUtc=(Get-Date).ToUniversalTime().ToString('o')}}}|ConvertTo-Json -Depth 6|Set-Content $opfile
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('OPERATOR_NOT_ACTIVE') 'dead-or-stopped-operator'
  $sp=Join-Path $dir 'state.json';$s=Get-Content $sp -Raw|ConvertFrom-Json;$s.rigs.'4080'.lastProgressUtc=(Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o');$s.rigs.'4080'.phase='active';$s|ConvertTo-Json -Depth 12|Set-Content $sp -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('ROW_STALLED') 'unchanged-active-row-stall'
  $targets.rigs[0].gamePid=2147483000;$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('GAME_PROCESS_DEAD') 'dead-game-process'
  $targets.rigs[0].row='none';$targets.rigs[0].request='';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('IDLE_LANE') -and $e.Contains('next complex case')) 'idle-lane-includes-next-candidate'
  $targets.rigs[0].row='CHAT-TEST';$targets.rigs[0].request='req-123';$targets.rigs[0].nativeLog=Join-Path $base 'missing.log';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('DEPENDENCY_BLOCKED') 'missing-progress-source-is-blocked'
  $targets.rigs[0].request='never-seen';$targets.rigs[0].phase='active';$targets.rigs[0].stallSeconds=1;$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;Start-Sleep -Milliseconds 1100;Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('DEPENDENCY_BLOCKED') -and $e.Contains('ROW_STALLED')) 'missing-exact-event-eventually-stalls'
  $targets.rigs[0].nativeLog=$log;$targets.rigs[0].request='req-123';Set-Content (Join-Path $base 'receipt.md') 'RESULT CHAT-TEST PASS request=req-123 evidence';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('ROW_TERMINAL_PASS') -and $e.Contains('COMPLETE_AWAITING_NEXT')) 'terminal-row-routes-next-candidate'
  Set-Content (Join-Path $base 'receipt.md') 'RESULT WRONG-ROW PASS request=wrong-request';Invoke-Waker $base|Out-Null;$e=Events $base;Assert $e.Contains('receipt identity or pinned SHA-256 failed validation') 'receipt-identity-mismatch-is-blocked'
  $targets.rigs[0].row='none';$targets.rigs[0].request='';$targets.rigs[0].lastCompletedRow='KAH-CHAT-TEST-FINAL';$targets.rigs[0].lastCompletedRequest='req-final';$targets.rigs[0].receipt=Join-Path $base 'receipt-final.md';$targets.rigs[0].nextCandidate='next READY complex row';Set-Content $targets.rigs[0].receipt 'RESULT KAH-CHAT-TEST-FINAL PASS request=req-final evidence';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('KAH-CHAT-TEST-FINAL') -and $e.Contains('next READY complex row')) 'idle-lane-receipt-routes-exact-completed-row'
  $countBefore=([regex]::Matches($e,'COMPLETE_AWAITING_NEXT')).Count;Invoke-Waker $base|Out-Null;$e=Events $base;$countAfter=([regex]::Matches($e,'COMPLETE_AWAITING_NEXT')).Count;Assert ($countAfter -eq $countBefore) 'completion-notification-deduplicated-after-restart'
  $targets.rigs[0].lastCompletedRow='KAH-CHAT-004';$targets.rigs[0].lastCompletedRequest='k1791937446159_39876_1';$targets.rigs[0].receipt=Join-Path $base 'receipt-5090.md';Set-Content $targets.rigs[0].receipt "# KAH-CHAT-004`nNative request ``k1791937446159_39876_1```n- **RESULT:** ``FAIL destination``";$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('ROW_TERMINAL_FAIL') -and $e.Contains('k1791937446159_39876_1')) 'markdown-result-receipt-parses-fail'
  $targets.rigs[0].lastCompletedRequest='k1791937426837_1724_1';$targets.rigs[0].receipt=Join-Path $base 'receipt-4080.md';Set-Content $targets.rigs[0].receipt "# KAH-CHAT-004`n`n## Result`n`n``RESULT KAH-CHAT-004 FAIL conversation; request=k1791937426837_1724_1``";$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('ROW_TERMINAL_FAIL') -and $e.Contains('k1791937426837_1724_1')) 'markdown-heading-result-receipt-parses-fail'
  $before=(Get-Content $sp -Raw|ConvertFrom-Json).rigs.'4080'.ticks
  Invoke-Waker $base|Out-Null;$after=(Get-Content $sp -Raw|ConvertFrom-Json).rigs.'4080'.ticks
  Assert ($after -gt $before) 'restart-recovers-state-and-tick'
  $lock=Join-Path $dir 'waker.lock';$held=[IO.File]::Open($lock,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$bytes=[Text.Encoding]::UTF8.GetBytes((@{pid=$PID;startedUtc=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Compress));$held.Write($bytes,0,$bytes.Length);$held.Flush()
  $o=Invoke-Waker $base;Assert ($o -match 'WAKER_ALREADY_RUNNING') 'duplicate-waker-prevented'
  $held.Dispose();Remove-Item $lock -Force
  $targets.rigs[0].source='ssh4080';$targets.rigs[0].receipt='';$targets.rigs[0].row='KAH-CHAT-TEST';$targets.rigs[0].request='req-123';$targets.rigs[0].ssh=@{host='not-4080';expectedHostname='not-host';config='bad';exe='bad'};$targets.rigs[0].nativeLog='C:\Windows\win.ini';$targets.rigs[0].gameExe='C:\Windows\system32\not-game.exe';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base -GuardOnly|Out-Null;$e=Events $base;Assert $e.Contains('canonical isolated-i3 guard') 'protected-4080-path-guard'
  $targets.rigs[0].ssh=@{host='4080';expectedHostname='DESKTOP-NQQPA73';config='C:\Users\Shay\.ssh\config';exe='C:\Temp\unexpected-ssh.exe'};$targets.rigs[0].nativeLog='C:\KenshiInst\3\RE_Kenshi\mods\Stobe\stobe.log';$targets.rigs[0].gameExe='C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base -GuardOnly|Out-Null;$e=Events $base;Assert $e.Contains('executable failed canonical isolated-i3 guard') '4080-ssh-executable-pinned'
  $targets.rigs[0].source='local';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base -GuardOnly|Out-Null;$e=Events $base;Assert $e.Contains('source does not match its trusted rig route') 'target-source-rig-route-guard';$targets.rigs[0].source='ssh4080'
  $targets.rigs[0].row='KAH-CHAT-004;Start-Process';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base -GuardOnly|Out-Null;$e=Events $base;Assert $e.Contains('target row ID failed schema validation') 'target-row-id-schema-guard'
  $targets.rigs[0].row='none';$targets.rigs[0].request='';$targets.rigs[0].receipt='C:\Windows\win.ini';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base -GuardOnly|Out-Null;$e=Events $base;Assert $e.Contains('receipt path escaped the rig-specific workspace evidence root') 'receipt-path-workspace-guard'
  # UI-only KAH rows use the actual action identity and game generation, never a fabricated chat request.
  $targets=@{schema=1;pollSeconds=120;rigs=@(@{rig='4080';row='KAH-UI-TEST';request='';uiActionId='kahui-operation-17';uiGeneration=3;phase='active';source='local';nativeLog=$log;receipt='';receiptSha256='';nextCandidate='next UI confirmation';gamePid=$PID;gameExe='';stallSeconds=30})}
  @{schema=1;rigs=@{'4080'=@{operator='synthetic-ui';status='active';updatedUtc=(Get-Date).ToUniversalTime().ToString('o');uiProgress=@{actionId='kahui-operation-17';generation=3;stage='open';readback='open key=2256103424|Beak gen=3'}}}}|ConvertTo-Json -Depth 8|Set-Content $opfile
  Set-Content -LiteralPath $log -Value 'portrait log changed without chat request';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('ROW_ADOPTED_UI') -and $e.Contains('ROW_UI_BASELINE') -and $e.Contains('kahui-operation-17')) 'ui-action-id-generation-baseline-without-chat-id'
  $uimap=Get-Content $opfile -Raw|ConvertFrom-Json;$uimap.rigs.'4080'.uiProgress.stage='read';$uimap.rigs.'4080'.uiProgress.readback='open=1 loaded=1 generation=3';$uimap|ConvertTo-Json -Depth 8|Set-Content $opfile
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('ROW_UI_PROGRESS') -and $e.Contains('generation=3')) 'ui-generation-readback-is-real-progress'
  $uimap.rigs.'4080'.uiProgress.actionId='unrelated-ui-action';$uimap.rigs.'4080'.uiProgress.readback='readback=1';$uimap|ConvertTo-Json -Depth 8|Set-Content $opfile
  $uiProgressBefore=([regex]::Matches((Events $base),'"code":"ROW_UI_PROGRESS"')).Count
  Add-Content -LiteralPath $log -Value 'generic NPC_SAY portrait chatter';Invoke-Waker $base|Out-Null;$e=Events $base
  $uiProgressAfter=([regex]::Matches($e,'"code":"ROW_UI_PROGRESS"')).Count
  Assert ($e.Contains('waiting for matching UI action/readback') -and $uiProgressAfter -eq $uiProgressBefore) 'mismatched-ui-id-and-generic-log-do-not-count'
  $uiReceipt=Join-Path $base 'ui-terminal.md';Set-Content $uiReceipt 'RESULT KAH-UI-TEST PASS actionId=kahui-operation-17 generation=3 readback=open=1 loaded=1'
  $targets.rigs[0].row='none';$targets.rigs[0].uiActionId='';$targets.rigs[0].uiGeneration=0;$targets.rigs[0].lastCompletedRow='KAH-UI-TEST';$targets.rigs[0].lastCompletedRequest='';$targets.rigs[0].lastCompletedActionId='kahui-operation-17';$targets.rigs[0].lastCompletedGeneration=3;$targets.rigs[0].receipt=$uiReceipt;$targets.rigs[0].receiptSha256='';$targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$e=Events $base;Assert ($e.Contains('ROW_TERMINAL_PASS') -and $e.Contains('actionId=kahui-operation-17') -and $e.Contains('generation=3')) 'ui-terminal-receipt-identity-without-request'
  $commits=@((Get-Content (Join-Path $dir 'events.jsonl')|ForEach-Object {$_|ConvertFrom-Json})|Where-Object {$_.code -eq 'TICK_COMMITTED'})
  Assert (@($commits|Where-Object {$_.rig -eq '4080' -and $_.actionId -eq 'kahui-operation-17' -and $_.generation -eq 3}).Count -gt 0) 'ui-tick-commit-carries-real-action-identity'
  $setupReceipt=Join-Path $base 'setup-terminal.md';Set-Content $setupReceipt 'RESULT KAH-SETUP-TEST FAIL setup: blocked before KAH transaction'
  $targets=@{schema=2;pollSeconds=120;rigs=@(@{rig='4080';row='none';request='';phase='complete_awaiting_next';source='local';nativeLog=$log;receipt=$setupReceipt;receiptSha256=('A'*64);receiptOnly=$true;lastCompletedRow='KAH-SETUP-TEST';lastCompletedRequest='';lastCompletedActionId='';lastCompletedGeneration=0;nextCandidate='fresh authorized setup after transport repair';gamePid=$PID;stallSeconds=240})}
  $targets|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'targets.json') -Encoding utf8
  Invoke-Waker $base|Out-Null;$terminalOnly=@((Get-Content (Join-Path $dir 'events.jsonl')|ForEach-Object {$_|ConvertFrom-Json})|Where-Object {$_.code -eq 'ROW_TERMINAL_FAIL' -and $_.row -eq 'KAH-SETUP-TEST'})|Select-Object -Last 1
  Assert ($terminalOnly -and -not $terminalOnly.request -and -not $terminalOnly.actionId -and $terminalOnly.evidence -match 'identity=receipt-only') 'receipt-only-terminal-emits-no-fake-identity'
  Assert ((RemoteGameState $base '' ) -eq 'unknown') 'remote-process-query-failure-is-unknown'
  Assert ((RemoteGameState $base '' -QuerySucceeded) -eq 'dead') 'remote-successful-query-no-match-is-dead'
  Assert ((RemoteGameState $base '3452' -QuerySucceeded) -eq 'alive') 'remote-successful-query-match-is-alive'
  $appendPath=Join-Path $base 'append-lock.jsonl';Set-Content -LiteralPath $appendPath -Value '{"sequence":0}' -Encoding utf8
  $holderScript=Join-Path $base 'hold-read.ps1';$holderReady=Join-Path $base 'holder.ready'
  @'
param([string]$Path,[string]$Ready)
$h=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
Set-Content -LiteralPath $Ready -Value 'held'
Start-Sleep -Milliseconds 500
$h.Dispose()
'@ | Set-Content -LiteralPath $holderScript -Encoding utf8
  $holder=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$holderScript+'"'),('"'+$appendPath+'"'),('"'+$holderReady+'"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $base 'holder.out') -RedirectStandardError (Join-Path $base 'holder.err')
  $until=(Get-Date).AddSeconds(3);while(-not (Test-Path -LiteralPath $holderReady) -and (Get-Date) -lt $until){Start-Sleep -Milliseconds 20}
  Assert (Test-Path -LiteralPath $holderReady) 'append-lock-holder-armed'
  $appendResult=Invoke-EventAppendFixture $appendPath
  Wait-Process -Id $holder.Id -Timeout 5 -ErrorAction SilentlyContinue
  $appended=@(Get-Content -LiteralPath $appendPath|ForEach-Object {try{$_|ConvertFrom-Json}catch{$null}}|Where-Object {$_.code -eq 'APPEND_FIXTURE'})
  Assert ($appendResult.exit -eq 0 -and $appendResult.output -eq 'EVENT_APPEND_FIXTURE_PASS' -and $appended.Count -eq 1) 'event-append-retries-transient-shared-reader'
  $partialPath=Join-Path $base 'append-partial.jsonl';$partialResult=Invoke-PostOpenFailureFixture $partialPath
  Assert ($partialResult.exit -eq 0 -and $partialResult.output -eq 'EVENT_POSTOPEN_FAILURE_FIXTURE_PASS') 'post-open-partial-failure-stops-appends-and-recovers-tail'
  $corruptPath=Join-Path $base 'append-interior-corrupt.jsonl';$corruptResult=Invoke-InteriorCorruptionFixture $corruptPath
  Assert ($corruptResult.exit -eq 0 -and $corruptResult.output -eq 'EVENT_INTERIOR_CORRUPTION_FIXTURE_PASS') 'interior-corruption-fails-closed-without-appending'
  $exclusivePath=Join-Path $base 'append-exclusive-recovery.jsonl';$exclusiveResult=Invoke-ExclusiveRecoveryFixture $exclusivePath
  Assert ($exclusiveResult.exit -eq 0 -and $exclusiveResult.output -eq 'EVENT_EXCLUSIVE_RECOVERY_FIXTURE_PASS') 'exclusive-recovery-fails-closed-with-live-reader'
  $utf8Path=Join-Path $base 'append-utf8-partial.jsonl';$utf8Result=Invoke-Utf8PartialSuffixFixture $utf8Path
  Assert ($utf8Result.exit -eq 0 -and $utf8Result.output -eq 'EVENT_UTF8_PARTIAL_SUFFIX_FIXTURE_PASS') 'partial-utf8-codepoint-suffix-recovers'
  # stale/dead operator is surfaced from its explicit, operator-maintained heartbeat; missing is not inferred alive.
  Write-Output "RESULT LIVE-TESTING-WAKER-SELFTEST PASS cases=$script:caseCount controls=none"
  exit 0
} catch {Write-Output "RESULT LIVE-TESTING-WAKER-SELFTEST FAIL reason=$($_.Exception.Message)";exit 1}
finally {Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue}

