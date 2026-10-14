<#
live-testing-waker.ps1 — detached, read-only 120-second Stobe row progress monitor.

Start (hidden): Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(..., '-File', '...')
                 -WorkingDirectory C:\KenshiModding
  -Run                         persistent loop; one tick every 120 seconds
  -Once                        one observation (for focused checks)
  -SelfTest                    synthetic state-machine checks; never contacts a game or rig

Writes its PID, heartbeat, per-rig row identity/evidence cursors, and append-only events under
testing/live-stobe-queue/progress-waker/. Inputs are read-only. It never sends game input, edits a queue,
touches an inbox, or treats a live game PID / unchanged agent marker as gameplay progress. Current rows and
their exact log/receipt paths are pinned in targets.json; refresh that file only from operator/supervisor receipts.
#>
[CmdletBinding()]
param([switch]$Run,[switch]$Once,[switch]$SelfTest,[switch]$SyntheticFixture,[switch]$GuardOnlyFixture,[switch]$RemoteGameQueryFixture,[switch]$ValidateTargetSetFixture,[switch]$Sha256Fixture,[switch]$AppendEventFixture,[switch]$PostOpenFailureFixture,[switch]$InteriorCorruptionFixture,[switch]$ExclusiveRecoveryFixture,[switch]$Utf8PartialSuffixFixture,[string]$FixturePath='',[string]$FixtureGamePid='',[switch]$FixtureQuerySucceeded,[string]$Root='')
$ErrorActionPreference='Stop'
if(-not $Root){$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)}
$stateDir = Join-Path $Root 'testing\live-stobe-queue\progress-waker'
$statePath=Join-Path $stateDir 'state.json'; $eventsPath=Join-Path $stateDir 'events.jsonl'; $lockPath=Join-Path $stateDir 'waker.lock';$operatorPath=Join-Path $stateDir 'operators.json'
$script:eventSequence=0;$script:eventAppendUnsafe=$false;$script:forcePartialAppendFailure=$false

function Write-AtomicJson([string]$Path,$Value) {
  $tmp="$Path.$PID.tmp"; $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding utf8
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Parse-Utc([string]$Value) { [DateTimeOffset]::Parse($Value).UtcDateTime }
function Get-Sha256Hex([string]$Path) {
  $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}
  finally{$sha.Dispose();$stream.Dispose()}
}
function Get-TextSha256([string]$Text) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','')}
  finally{$sha.Dispose()}
}
function Test-UiStage([string]$Stage) {
  $Stage -match '^(preflight|open|read|screenshot|close|result|A_open_pending|A_read_pending|A_screenshot_pending|A_done_B_read_pending|B_select_pending|B_read_pending|return_A_read_pending|ABA_complete_receipt_pending)$'
}
function Test-TargetPhase($Target) {
  $phase=[string]$Target.phase
  if($phase -in @('active','in_flight','awaiting-poststate')){return $true}
  # A terminal lane is never an active row. Keep this exact spelling and require
  # the row/action identity to be absent so terminal metadata cannot mask work.
  if($phase -eq 'complete_awaiting_next'){
    return ([string]$Target.row -eq 'none' -and -not [string]$Target.request -and
      -not [string]$Target.uiActionId -and [int]$Target.uiGeneration -eq 0)
  }
  # Setup failures are terminal observations too, but stay distinct from PASS and
  # completed-row receipts. Require an idle lane and a pinned KAH setup-failure receipt.
  if($phase -eq 'setup_fail'){
    $name=[IO.Path]::GetFileName([string]$Target.receipt)
    return ([string]$Target.rig -eq '5090' -and [string]$Target.row -eq 'none' -and -not [string]$Target.request -and
      -not [string]$Target.uiActionId -and [int]$Target.uiGeneration -eq 0 -and
      [string]$Target.receiptSha256 -match '^[A-Fa-f0-9]{64}$' -and
      $name -match '^KAH-[A-Z0-9-]+-5090-.+setup-fail.*\.receipt\.md$')
  }
  # These phases are emitted by the UI-only KAH A/B/A workflow. Accept them
  # only when the target is bound to a real UI action identity; do not widen
  # the general phase schema or accept arbitrary bounded tokens.
  if([string]$Target.uiActionId -and $phase -in @('A_open_pending','A_read_pending','A_screenshot_pending','A_done_B_read_pending','B_select_pending','B_read_pending','return_A_read_pending','ABA_complete_receipt_pending')){return $true}
  $false
}
function Test-ReceiptOnlyTerminal($Target) {
  $receiptPath=[string]$Target.receipt
  if($receiptPath -and -not [IO.Path]::IsPathRooted($receiptPath)){try{$receiptPath=[IO.Path]::GetFullPath((Join-Path $Root $receiptPath))}catch{return $false}}
  $receiptName=if($receiptPath){[IO.Path]::GetFileName($receiptPath)}else{''}
  ([bool]$Target.receiptOnly -and [string]$Target.rig -eq '4080' -and $receiptPath.StartsWith('C:\KenshiModding\testing\live-stobe-queue\',[StringComparison]::OrdinalIgnoreCase) -and $receiptName -match '^KAH-[A-Z0-9-]+-4080-.+\.receipt\.md$' -and
   [string]$Target.row -eq 'none' -and [string]$Target.phase -eq 'complete_awaiting_next' -and
   [string]$Target.lastCompletedRow -match '^KAH-[A-Z0-9-]+$' -and -not [string]$Target.request -and
   -not [string]$Target.lastCompletedRequest -and -not [string]$Target.uiActionId -and
   -not [string]$Target.lastCompletedActionId -and [int]$Target.uiGeneration -eq 0 -and [int]$Target.lastCompletedGeneration -eq 0 -and
   [string]$Target.receipt -and [string]$Target.receiptSha256 -match '^[A-Fa-f0-9]{64}$')
}
function Emit([string]$Code,[string]$Rig,[string]$Row,[string]$Request,[string]$Evidence,[string]$Severity='info',[string]$ActionId='',[int]$Generation=0) {
  if($script:eventAppendUnsafe){throw 'event JSONL may have a partial tail; refusing further appends'}
  $script:eventSequence++
  $event=[ordered]@{sequence=$script:eventSequence;at=(Get-Date).ToUniversalTime().ToString('o');code=$Code;rig=$Rig;row=$Row;request=$Request;actionId=$ActionId;generation=$Generation;severity=$Severity;evidence=$Evidence}
  $line=($event | ConvertTo-Json -Compress)+"`r`n"
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($line)
  for($attempt=0;$attempt -lt 12;$attempt++){
    $stream=$null
    try{
      $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
      $stream=[IO.FileStream]::new($eventsPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,$share)
    }catch [IO.IOException]{
      if($attempt -eq 11){throw}
      Start-Sleep -Milliseconds ([Math]::Min(250,25*(1+$attempt)))
      continue
    }
    try{
      if($stream.Length -gt 0){$stream.Position=$stream.Length-1;$last=$stream.ReadByte();if($last -ne 10){$script:eventAppendUnsafe=$true;throw 'event JSONL has an unterminated tail; restart recovery is required'}}
      $stream.Position=$stream.Length
      if($script:forcePartialAppendFailure){$partial=[Math]::Min(5,$bytes.Length);$stream.Write($bytes,0,$partial);throw [IO.IOException]::new('synthetic post-open partial-write failure')}
      $stream.Write($bytes,0,$bytes.Length);$stream.Flush();return
    }catch{$script:eventAppendUnsafe=$true;throw}
    finally{$stream.Dispose()}
  }
}
function Get-TargetSet {
  $p=Join-Path $stateDir 'targets.json'
  if(-not (Test-Path -LiteralPath $p)){throw "missing target map: $p"}
  Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
}
function Validate-TargetSet($set) {
  if($null -eq $set -or [int]$set.schema -ne 2){return 'target set schema must be version 2'}
  if([int]$set.pollSeconds -ne 120){return 'target set pollSeconds must be 120'}
  if($null -eq $set.rigs -or @($set.rigs).Count -ne 2){return 'target set must contain exactly two rig entries'}
  $names=@($set.rigs | ForEach-Object {[string]$_.rig})
  if(@($names | Select-Object -Unique).Count -ne 2 -or @($names | Sort-Object) -join ',' -ne '4080,5090'){return 'target set must contain exactly one 4080 and one 5090 lane'}
  foreach($t in $set.rigs){
    if(-not (Test-TargetPhase $t)){return "target phase outside allowed set for rig $($t.rig)"}
    if($null -eq $t.stallSeconds -or [int]$t.stallSeconds -lt 120 -or [int]$t.stallSeconds -gt 3600){return "stallSeconds outside 120..3600 for rig $($t.rig)"}
    if([string]$t.row -ne 'none' -and [string]$t.row -notmatch '^KAH-[A-Z0-9-]+$'){return "target row ID failed schema validation for rig $($t.rig)"}
    $request=[string]$t.request;$action=[string]$t.uiActionId;$generation=[int]$t.uiGeneration
    if($request -and $request -notmatch '^[A-Za-z0-9_-]+$'){return "target request ID failed schema validation for rig $($t.rig)"}
    if($action -and $action -notmatch '^[A-Za-z0-9_.:|/-]{1,128}$'){return "target UI action ID failed schema validation for rig $($t.rig)"}
    if($action -and ($generation -lt 1 -or $generation -gt 2147483647)){return "target UI generation outside 1..2147483647 for rig $($t.rig)"}
    if([bool]$t.receiptOnly){if(-not (Test-ReceiptOnlyTerminal $t)){return "receipt-only terminal must be idle, complete-awaiting-next, row-pinned, and hash-pinned for rig $($t.rig)"}}
    elseif(([string]$t.row -eq 'none' -and ($request -or $action -or $generation -gt 0)) -or ([string]$t.row -ne 'none' -and (([bool]$request -eq [bool]$action) -or ($action -and $generation -lt 1) -or ($request -and $generation -gt 0)))){return "active row must have exactly one request or UI action/generation identity for rig $($t.rig)"}
    if([string]$t.nextCandidate -and ([string]$t.nextCandidate).Length -gt 512){return "next candidate note exceeds bounded schema length for rig $($t.rig)"}
  }
  ''
}
function Get-OperatorMap {
  if(Test-Path -LiteralPath $operatorPath){try{return (Get-Content -LiteralPath $operatorPath -Raw | ConvertFrom-Json)}catch{}}
  return $null
}
function Init-EventSequence {
  # Startup recovery is unsafe until the entire journal has been scanned successfully.
  # Any exception must leave appends latched off so the outer handler cannot add JSON
  # after an interior corrupt record and turn a repairable file into an unrecoverable one.
  $script:eventAppendUnsafe=$true
  $stream=$null
  for($attempt=0;$attempt -lt 12;$attempt++){
    try{$stream=[IO.FileStream]::new($eventsPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);break}
    catch [IO.IOException]{if($attempt -eq 11){throw};Start-Sleep -Milliseconds ([Math]::Min(250,25*(1+$attempt)))}
  }
  if(-not $stream){throw 'could not acquire exclusive ownership of event JSONL for restart recovery'}
  try{
    if($stream.Length -gt [int]::MaxValue){throw 'event JSONL exceeds safe restart scan size'}
    $bytes=New-Object byte[] ([int]$stream.Length);$read=0
    while($read -lt $bytes.Length){$n=$stream.Read($bytes,$read,$bytes.Length-$read);if($n -le 0){throw 'event JSONL changed during exclusive recovery scan'};$read+=$n}
    $utf8=[Text.UTF8Encoding]::new($false,$true);$completeEnd=0
    # Find record boundaries as bytes before decoding. A crash can leave the final
    # UTF-8 code point incomplete; that suffix is discarded without decoding it.
    for($i=0;$i -lt $bytes.Length;$i++){if($bytes[$i] -eq 10){$completeEnd=$i+1}}
    $truncateAt=$completeEnd;$lineStart=0;$lineNumber=0
    for($end=0;$end -lt $completeEnd;$end++){
      if($bytes[$end] -ne 10){continue}
      $recordLength=$end-$lineStart;if($recordLength -gt 0 -and $bytes[$end-1] -eq 13){$recordLength--}
      $line='';$decodeFailed=$false
      try{$recordBytes=New-Object byte[] $recordLength;if($recordLength -gt 0){[Array]::Copy($bytes,$lineStart,$recordBytes,0,$recordLength)};$line=$utf8.GetString($recordBytes)}catch{$decodeFailed=$true}
      if($lineNumber -eq 0 -and $line.Length -gt 0 -and $line[0] -eq [char]0xFEFF){$line=$line.Substring(1)}
      if($recordLength -eq 0){$event=$null}
      elseif(-not $decodeFailed){try{$event=$line|ConvertFrom-Json -ErrorAction Stop;if($null -eq $event.sequence -or [long]$event.sequence -lt 1){throw 'event sequence missing'}}catch{$decodeFailed=$true}}
      if($decodeFailed){
        # A malformed final complete record is a trailing suffix only when no later
        # bytes exist. Otherwise it is interior corruption; preserve the file and fail closed.
        if($end -ne ($bytes.Length-1)){throw "invalid non-trailing event JSONL record at byte $lineStart"}
        $truncateAt=$lineStart;break
      }
      if($event -and [long]$event.sequence -gt $script:eventSequence){$script:eventSequence=[long]$event.sequence}
      $lineStart=$end+1;$lineNumber++
    }
    # Anything after the final LF is not a committed record, even when it happens to
    # decode as JSON; leave only the complete prefix and recover its max sequence.
    if($truncateAt -lt $bytes.Length){$stream.SetLength($truncateAt);$stream.Flush()}
  }finally{$stream.Dispose()}
  $script:eventAppendUnsafe=$false
}
function Read-Source($t) {
  # Returns an explicit availability state and a tail; it does not infer progress from process existence.
  if($t.source -eq 'local') {
    if(-not (Test-Path -LiteralPath $t.nativeLog)){return @{ok=$false;reason="native log unavailable: $($t.nativeLog)";tail=''}}
    $item=Get-Item -LiteralPath $t.nativeLog
    $tail=(Get-Content -LiteralPath $t.nativeLog -Tail 800 -ErrorAction Stop) -join "`n"
    $gp=$null;$gameState='unknown'
    if($t.gameExe){try{$g=Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" -ErrorAction Stop | Where-Object {$_.ExecutablePath -eq [string]$t.gameExe} | Select-Object -First 1;if($g){$gp=[string]$g.ProcessId;$gameState='alive'}else{$gameState='dead'}}catch{}}
    return @{ok=$true;reason='';tail=$tail;length=$item.Length;writeUtc=$item.LastWriteTimeUtc.ToString('o');gamePid=$gp;gameState=$gameState}
  }
  if($t.source -eq 'ssh4080') {
    $ssh=$t.ssh; $remote=$t.nativeLog
    if(-not (Test-Path -LiteralPath $ssh.exe)){return @{ok=$false;reason='SSH executable unavailable';tail=''}}
    $q=$remote.Replace("'","''")
    $want=([string]$t.gameExe).Replace("'","''")
    $script=@"
`$p='$q'
if(-not (Test-Path -LiteralPath `$p)){exit 42}
`$i=Get-Item -LiteralPath `$p
Write-Output ('__HOST__'+(hostname))
Write-Output ('__META__'+`$i.Length+'|'+`$i.LastWriteTimeUtc.ToString('o'))
try {
  `$all=Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" -ErrorAction Stop
  Write-Output '__GAME_QUERY_OK__'
  `$g=`$all | Where-Object {`$_.ExecutablePath -eq '$want'} | Select-Object -First 1
  if(`$g){Write-Output ('__GAME__'+`$g.ProcessId+'|'+`$g.ExecutablePath)}
} catch { Write-Output '__GAME_QUERY_FAILED__' }
Get-Content -LiteralPath `$p -Tail 800
"@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $args=@('-F',$ssh.config,'-n','-o','BatchMode=yes','-o','ConnectTimeout=8',$ssh.host,'powershell.exe','-NoProfile','-NonInteractive','-EncodedCommand',$encoded)
    $raw=& $ssh.exe @args 2>&1; $ec=$LASTEXITCODE
    if($ec -ne 0){return @{ok=$false;reason="remote read failed exit=$ec";tail=''}}
    $lines=@($raw | ForEach-Object { [string]$_ }); $meta=$lines | Where-Object {$_ -like '__META__*'} | Select-Object -First 1
    if(-not $meta){return @{ok=$false;reason='remote native log returned no metadata';tail=''}}
    $hostline=$lines | Where-Object {$_ -like '__HOST__*'} | Select-Object -First 1
    if(-not $hostline -or $hostline.Substring(8).Trim() -ne [string]$ssh.expectedHostname){return @{ok=$false;reason='trusted SSH host verification failed';tail=''}}
    $parts=$meta.Substring(8).Split('|',2)
    $queryOk=[bool]($lines | Where-Object {$_ -eq '__GAME_QUERY_OK__'} | Select-Object -First 1)
    $queryFailed=[bool]($lines | Where-Object {$_ -eq '__GAME_QUERY_FAILED__'} | Select-Object -First 1)
    $gline=$lines | Where-Object {$_ -like '__GAME__*'} | Select-Object -First 1
    $gp=$null;if($gline){$gp=($gline.Substring(8).Split('|',2))[0]}
    $gameState=Resolve-RemoteGameState $gp ($queryOk -and -not $queryFailed)
    return @{ok=$true;reason='';tail=(($lines | Where-Object {$_ -notlike '__META__*' -and $_ -notlike '__HOST__*' -and $_ -notlike '__GAME__*' -and $_ -ne '__GAME_QUERY_OK__' -and $_ -ne '__GAME_QUERY_FAILED__'}) -join "`n");length=[long]$parts[0];writeUtc=$parts[1];gamePid=$gp;gameState=$gameState}
  }
  return @{ok=$false;reason="unsupported source '$($t.source)'";tail=''}
}
function Get-ReceiptState($t) {
  if(-not $t.receipt){return 'pending'}
  $receiptPath=[string]$t.receipt;if(-not [IO.Path]::IsPathRooted($receiptPath)){$receiptPath=Join-Path $Root $receiptPath}
  if(-not (Test-Path -LiteralPath $receiptPath)){return 'pending'}
  if(-not $SyntheticFixture){
    if([string]$t.receiptSha256 -notmatch '^[A-Fa-f0-9]{64}$'){return 'invalid'}
    $actual=Get-Sha256Hex $receiptPath
    if($actual -ne [string]$t.receiptSha256){return 'invalid'}
  }
  $raw=Get-Content -LiteralPath $receiptPath -Raw
  if([string]$t.phase -eq 'setup_fail'){
    $name=[IO.Path]::GetFileName($receiptPath)
    $nameMatch=[regex]::Match($name,'^(KAH-[A-Z0-9-]+)-5090-.+setup-fail.*\.receipt\.md$')
    if(-not $nameMatch.Success -or $raw -notmatch '(?im)FAIL\s+setup' -or $raw -notmatch [regex]::Escape($nameMatch.Groups[1].Value)){return 'invalid'}
    return 'setup_fail'
  }
  $expectedRow=[string]$t.row;$expectedRequest=[string]$t.request;$expectedAction=[string]$t.uiActionId;$expectedGeneration=[int]$t.uiGeneration
  if((-not $expectedRow -or $expectedRow -eq 'none') -and $t.lastCompletedRow){$expectedRow=[string]$t.lastCompletedRow}
  if(-not $expectedRequest -and $t.lastCompletedRequest){$expectedRequest=[string]$t.lastCompletedRequest}
  if(-not $expectedAction -and $t.lastCompletedActionId){$expectedAction=[string]$t.lastCompletedActionId;$expectedGeneration=[int]$t.lastCompletedGeneration}
  if(($expectedRow -and $raw -notmatch [regex]::Escape($expectedRow)) -or ($expectedRequest -and $raw -notmatch [regex]::Escape($expectedRequest))){return 'invalid'}
  if($expectedAction -and ($raw -notmatch [regex]::Escape($expectedAction) -or $raw -notmatch '(?i)(?:uiGeneration|generation|gen)\s*[:=]\s*'+[string]$expectedGeneration)){return 'invalid'}
  $resultLine=$raw -split "`r?\n" | Where-Object {$_ -match '(?i)\bRESULT\b.*\b(PASS|FAIL)\b'} | Select-Object -First 1
  if($resultLine -and $expectedRow){
    $resultMatch=[regex]::Match($resultLine,'(?i)\b(PASS|FAIL)\b')
    if($resultMatch.Success){return $resultMatch.Groups[1].Value.ToLowerInvariant()}
  }
  if($raw -match '(?im)terminal PASS|PASS native-roundtrip'){return 'pass'}
  if($raw -match '(?im)terminal FAIL|FAIL evidence|FAIL setup'){return 'fail'}
  'pending'
}
function Get-GameProcessState($t) {
  # PID proves liveness only; it is intentionally excluded from progress classification.
  if(-not $t.gamePid){return 'unknown'}
  $p=Get-Process -Id ([int]$t.gamePid) -ErrorAction SilentlyContinue
  if(-not $p){return 'dead'}
  'alive'
}
function Resolve-RemoteGameState([string]$ProcessId,[bool]$QuerySucceeded) {
  if($ProcessId){return 'alive'}
  if($QuerySucceeded){return 'dead'}
  'unknown'
}
function Validate-Target($t) {
  if($SyntheticFixture -and -not $GuardOnlyFixture){return ''}
  $rigName=[string]$t.rig;$rowName=[string]$t.row;$requestId=[string]$t.request;$actionId=[string]$t.uiActionId;$generation=[int]$t.uiGeneration
  if($rigName -notin @('5090','4080')){return 'target rig is outside the two trusted lanes'}
  if(-not (Test-TargetPhase $t)){return 'target phase outside allowed set'}
  if(($rigName -eq '5090' -and $t.source -ne 'local') -or ($rigName -eq '4080' -and $t.source -ne 'ssh4080')){return 'target source does not match its trusted rig route'}
  if($rowName -ne 'none' -and $rowName -notmatch '^KAH-[A-Z0-9-]+$'){return 'target row ID failed schema validation'}
  if($requestId -and $requestId -notmatch '^[A-Za-z0-9_-]+$'){return 'target request ID failed schema validation'}
  if($actionId -and $actionId -notmatch '^[A-Za-z0-9_.:|/-]{1,128}$'){return 'target UI action ID failed schema validation'}
  if($actionId -and ($generation -lt 1 -or $generation -gt 2147483647)){return 'target UI generation outside 1..2147483647'}
  if([bool]$t.receiptOnly){if(-not (Test-ReceiptOnlyTerminal $t)){return 'receipt-only terminal must be idle, complete-awaiting-next, row-pinned, and hash-pinned'}}
  elseif(($rowName -eq 'none' -and ($requestId -or $actionId -or $generation -gt 0)) -or ($rowName -ne 'none' -and (([bool]$requestId -eq [bool]$actionId) -or ($actionId -and $generation -lt 1) -or ($requestId -and $generation -gt 0)))){return 'active row must have exactly one request or UI action/generation identity'}
  if($t.lastCompletedRow -and [string]$t.lastCompletedRow -notmatch '^KAH-[A-Z0-9-]+$'){return 'last completed row ID failed schema validation'}
  if($t.lastCompletedRequest -and [string]$t.lastCompletedRequest -notmatch '^[A-Za-z0-9_-]+$'){return 'last completed request ID failed schema validation'}
  if($t.lastCompletedActionId -and [string]$t.lastCompletedActionId -notmatch '^[A-Za-z0-9_.:|/-]{1,128}$'){return 'last completed UI action ID failed schema validation'}
  if($t.lastCompletedActionId -and ([int]$t.lastCompletedGeneration -lt 1)){return 'last completed UI generation must be positive'}
  if($t.receipt -and $rowName -eq 'none' -and (-not $t.lastCompletedRow -or ((-not $t.lastCompletedRequest) -and (-not $t.lastCompletedActionId -or [int]$t.lastCompletedGeneration -lt 1) -and -not (Test-ReceiptOnlyTerminal $t)))){return 'idle terminal receipt requires a completed row and request or UI action/generation identity, or the pinned receipt-only terminal contract'}
  if([string]$t.nextCandidate -and ([string]$t.nextCandidate).Length -gt 512){return 'next candidate note exceeds bounded schema length'}
  if([string]$t.receipt){
    try{$receiptValue=[string]$t.receipt;if(-not [IO.Path]::IsPathRooted($receiptValue)){$receiptValue=Join-Path $Root $receiptValue};$receiptPath=[IO.Path]::GetFullPath($receiptValue)}catch{return 'receipt path failed canonicalization'}
    $receiptRoot=if($rigName -eq '5090'){'C:\KenshiModding\testing\live-stobe-queue\'}else{'C:\KenshiModding\pending-fixes\rig4080-validation\'}
    $receiptOnlyRoot=($rigName -eq '4080' -and [bool]$t.receiptOnly -and $receiptPath.StartsWith('C:\KenshiModding\testing\live-stobe-queue\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($receiptPath) -match '^KAH-[A-Z0-9-]+-4080-.+\.receipt\.md$')
    if(-not $receiptPath.StartsWith($receiptRoot,[StringComparison]::OrdinalIgnoreCase) -and -not $receiptOnlyRoot){return 'receipt path escaped the rig-specific workspace evidence root'}
    if(-not $SyntheticFixture -and [string]$t.receiptSha256 -notmatch '^[A-Fa-f0-9]{64}$'){return 'terminal receipt requires a pinned SHA-256'}
  }
  if($t.source -eq 'ssh4080'){
    if([string]$t.ssh.exe -ne 'C:\Windows\System32\OpenSSH\ssh.exe' -or [string]$t.ssh.host -ne '4080' -or [string]$t.ssh.expectedHostname -ne 'DESKTOP-NQQPA73' -or [string]$t.ssh.config -ne 'C:\Users\Shay\.ssh\config' -or [string]$t.nativeLog -ne 'C:\KenshiInst\3\RE_Kenshi\mods\Stobe\stobe.log' -or [string]$t.gameExe -ne 'C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe') { return '4080 target path/host/executable failed canonical isolated-i3 guard' }
  } elseif($t.source -eq 'local'){
    if([string]$t.nativeLog -ne 'D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log' -or [string]$t.gameExe -ne 'D:\Steam\steamapps\common\Kenshi\RE_Kenshi\kenshi_x64.exe'){return '5090 target path failed canonical isolated-main-i1 guard'}
  }
  ''
}
function Read-State {
  if(Test-Path -LiteralPath $statePath){
    try {
      $raw=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      $rigs=@{}
      if([int]$raw.version -in @(2,3) -and $raw.rigs){foreach($p in $raw.rigs.PSObject.Properties){$rigs[$p.Name]=@{row=[string]$p.Value.row;request=[string]$p.Value.request;uiActionId=[string]$p.Value.uiActionId;uiGeneration=[int]$p.Value.uiGeneration;cursor=[string]$p.Value.cursor;lastProgressUtc=[string]$p.Value.lastProgressUtc;rowStartedUtc=[string]$p.Value.rowStartedUtc;lastTickUtc=[string]$p.Value.lastTickUtc;ticks=[int]$p.Value.ticks;terminal=[string]$p.Value.terminal;completedKey=[string]$p.Value.completedKey;sourceAvailable=[bool]$p.Value.sourceAvailable;phase=[string]$p.Value.phase;lastEvent=[string]$p.Value.lastEvent;operator=[string]$p.Value.operator;operatorStatus=[string]$p.Value.operatorStatus;operatorHeartbeatUtc=[string]$p.Value.operatorHeartbeatUtc;gamePid=[int]$p.Value.gamePid}}}
      if($rigs.Count -gt 0){return @{version=3;rigs=$rigs;pid=[int]$raw.pid;startedUtc=[string]$raw.startedUtc;heartbeatUtc=[string]$raw.heartbeatUtc}}
    } catch {}
  }
  return @{version=3;rigs=@{};pid=$PID;startedUtc=(Get-Date).ToUniversalTime().ToString('o')}
}
function Observe {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  $state=Read-State; $targets=Get-TargetSet; $operators=Get-OperatorMap; $now=(Get-Date).ToUniversalTime()
  if(-not $SyntheticFixture){$setError=Validate-TargetSet $targets;if($setError){throw "invalid two-rig target set: $setError"}}
  foreach($t in $targets.rigs){
    $rig=[string]$t.rig; $row=[string]$t.row; $req=[string]$t.request; $actionId=[string]$t.uiActionId; $generation=[int]$t.uiGeneration
    if(-not $state.rigs.ContainsKey($rig)){$state.rigs[$rig]=@{row='';request='';uiActionId='';uiGeneration=0;cursor='';lastProgressUtc='';rowStartedUtc='';lastTickUtc='';ticks=0;terminal='';completedKey='';sourceAvailable=$false;phase='';lastEvent='';operator='';operatorStatus='';operatorHeartbeatUtc='';gamePid=0}}
    $rs=$state.rigs[$rig]; $rs.lastTickUtc=$now.ToString('o'); $rs.ticks=[int]$rs.ticks+1
    $op=$null;if($operators -and $operators.rigs){$prop=$operators.rigs.PSObject.Properties[$rig];if($prop){$op=$prop.Value}}
    if(-not $op){Emit 'OPERATOR_STATUS_UNKNOWN' $rig $row $req 'No operator heartbeat record exists; process/agent liveness is unverified.' 'warning'}
    else {
      $rs.operator=[string]$op.operator;$rs.operatorStatus=[string]$op.status;$rs.operatorHeartbeatUtc=[string]$op.updatedUtc
      $opAge=($now-(Parse-Utc ([string]$op.updatedUtc))).TotalSeconds
      if($op.status -notin @('running','active')){Emit 'OPERATOR_NOT_ACTIVE' $rig $row $req "operator=$($op.operator) status=$($op.status); $([int]$opAge)s since heartbeat." 'error'}
      elseif($opAge -ge 240){Emit 'OPERATOR_HEARTBEAT_STALE' $rig $row $req "operator=$($op.operator) status=$($op.status); heartbeat age=$([int]$opAge)s." 'error'}
    }
    $guard=Validate-Target $t
    if($guard){$rs.sourceAvailable=$false;Emit 'DEPENDENCY_BLOCKED' $rig $row $req $guard 'error';continue}
    $receipt=Get-ReceiptState $t
    if($receipt -eq 'invalid'){Emit 'DEPENDENCY_BLOCKED' $rig $row $req "receipt identity or pinned SHA-256 failed validation: $($t.receipt)" 'error';continue}
    if($receipt -ne 'pending'){
      $eventRow=$row;$eventReq=$req;$eventAction=$actionId;$eventGeneration=$generation
      if([string]$t.phase -eq 'setup_fail'){
        $receiptPath=[string]$t.receipt;if(-not [IO.Path]::IsPathRooted($receiptPath)){$receiptPath=Join-Path $Root $receiptPath}
        if([IO.Path]::GetFileName($receiptPath) -match '^(KAH-[A-Z0-9-]+)-5090-'){$eventRow=$Matches[1]}
      }
      elseif((-not $eventRow -or $eventRow -eq 'none') -and $t.lastCompletedRow){$eventRow=[string]$t.lastCompletedRow}
      if(-not $eventReq -and $t.lastCompletedRequest){$eventReq=[string]$t.lastCompletedRequest}
      if(-not $eventAction -and $t.lastCompletedActionId){$eventAction=[string]$t.lastCompletedActionId;$eventGeneration=[int]$t.lastCompletedGeneration}
      $completionKey="$eventRow|$eventReq|$eventAction|$eventGeneration|$($t.receipt)|$receipt"
      if($rs.completedKey -ne $completionKey){
        if($receipt -eq 'setup_fail'){
          Emit 'ROW_TERMINAL_SETUP_FAIL' $rig $eventRow '' "pinned setup-failure receipt=$($t.receipt); this is not a gameplay PASS or completed row." 'warning'
          if($t.nextCandidate){Emit 'SETUP_FAIL_AWAITING_NEXT' $rig $eventRow '' "setup failure recorded; next candidate: $($t.nextCandidate); no row queued by monitor." 'warning'}
        }else{
          Emit "ROW_TERMINAL_$($receipt.ToUpperInvariant())" $rig $eventRow $eventReq "receipt=$($t.receipt); outcome=$receipt; identity=$(if($t.receiptOnly){'receipt-only'}elseif($eventAction){'ui-action'}else{'chat-request'})" $(if($receipt -eq 'fail'){'warning'}else{'info'}) $eventAction $eventGeneration
          if($t.nextCandidate){Emit 'COMPLETE_AWAITING_NEXT' $rig $eventRow $eventReq "terminal=$receipt; next candidate: $($t.nextCandidate); no row queued by monitor." 'info' $eventAction $eventGeneration}
        }
        $rs.completedKey=$completionKey
      }
      $rs.row=$eventRow; $rs.request=$eventReq; $rs.uiActionId=$eventAction; $rs.uiGeneration=$eventGeneration; $rs.terminal=$receipt; $rs.phase=$(if($receipt -eq 'setup_fail'){'setup_fail'}else{'complete-awaiting-next'})
      $obs=Read-Source $t
      if($obs.ok){$rs.sourceAvailable=$true;if($obs.gamePid){$rs.gamePid=[int]$obs.gamePid};Emit 'RIG_OBSERVED' $rig $row $req "terminal receipt=$receipt; physical source=$($t.source); gameProcess=$(if($obs.gamePid){$obs.gamePid}else{$obs.gameState}); nativeLogBytes=$($obs.length).";if($obs.gameState -eq 'dead'){Emit 'GAME_PROCESS_DEAD' $rig $row $req "isolated game executable absent at verified path $($t.gameExe); no process action taken." 'error'}}
      else{$rs.sourceAvailable=$false;Emit 'RIG_OBSERVATION_BLOCKED' $rig $row $req $obs.reason 'error'}
      continue
    }
    if(-not $row -or -not $req){
      if([string]$row -eq 'none'){
        if($rs.row -ne 'none'){Emit 'IDLE_LANE' $rig 'none' '' "No active row identity is pinned; supervisor next candidate: $($t.nextCandidate). No filler is inferred or launched." 'warning'}
        $rs.row='none';$rs.request='';$rs.uiActionId='';$rs.uiGeneration=0;$rs.terminal='';$rs.phase='idle';$rs.sourceAvailable=$false;continue
      }
    }
    if($rs.row -ne $row -or $rs.request -ne $req -or $rs.uiActionId -ne $actionId -or $rs.uiGeneration -ne $generation){
      $rs.row=$row;$rs.request=$req;$rs.uiActionId=$actionId;$rs.uiGeneration=$generation;$rs.cursor='';$rs.lastProgressUtc='';$rs.rowStartedUtc=$now.ToString('o');$rs.terminal='';$rs.completedKey='';$rs.phase=[string]$t.phase
      Emit $(if($actionId){'ROW_ADOPTED_UI'}else{'ROW_ADOPTED'}) $rig $row $req $(if($actionId){"UI action=$actionId generation=$generation; awaiting exact operator readback baseline."}else{'New active row observed; first log snapshot is baseline, not progress.'}) 'info' $actionId $generation
    }
    if($actionId){
      $obs=Read-Source $t
      if(-not $obs.ok){$rs.sourceAvailable=$false;Emit 'RIG_OBSERVATION_BLOCKED' $rig $row $req $obs.reason 'error' $actionId $generation;continue}
      $rs.sourceAvailable=$true;if($obs.gamePid){$rs.gamePid=[int]$obs.gamePid}
      if($obs.gameState -eq 'dead'){Emit 'GAME_PROCESS_DEAD' $rig $row $req "isolated game executable absent at verified path $($t.gameExe); no control action taken." 'error' $actionId $generation}
      $ui=$null;if($op -and $op.uiProgress){$ui=$op.uiProgress}
      $stage=[string]$ui.stage;$readback=[string]$ui.readback
      $uiValid=($ui -and [string]$ui.actionId -eq $actionId -and [int]$ui.generation -eq $generation -and (Test-UiStage $stage) -and $readback.Length -gt 0 -and $readback.Length -le 512)
      if(-not $uiValid){
        Emit 'DEPENDENCY_BLOCKED' $rig $row $req "waiting for matching UI action/readback: expected action=$actionId generation=$generation; PID and log growth do not count." 'warning' $actionId $generation
        $age=if($rs.lastProgressUtc){($now-(Parse-Utc ([string]$rs.lastProgressUtc))).TotalSeconds}elseif($rs.rowStartedUtc){($now-(Parse-Utc ([string]$rs.rowStartedUtc))).TotalSeconds}else{0}
        if($rs.phase -ne 'complete-awaiting-next' -and $age -ge [int]$t.stallSeconds){Emit 'ROW_STALLED' $rig $row $req "no matching UI generation/readback for $([int]$age)s; action=$actionId generation=$generation." 'error' $actionId $generation}
        continue
      }
      $uiCursor=Get-TextSha256 "$actionId|$generation|$stage|$readback"
      if(-not $rs.cursor){$rs.cursor=$uiCursor;$rs.lastProgressUtc=$now.ToString('o');Emit 'ROW_UI_BASELINE' $rig $row $req "stage=$stage; readback=$readback; initial matching generation is baseline." 'info' $actionId $generation}
      elseif($uiCursor -ne [string]$rs.cursor){$rs.cursor=$uiCursor;$rs.lastProgressUtc=$now.ToString('o');Emit 'ROW_UI_PROGRESS' $rig $row $req "stage=$stage; readback=$readback" 'info' $actionId $generation}
      $age=if($rs.lastProgressUtc){($now-(Parse-Utc ([string]$rs.lastProgressUtc))).TotalSeconds}else{0}
      if($rs.lastProgressUtc -and $age -ge [int]$t.stallSeconds -and $rs.phase -ne 'complete-awaiting-next'){Emit 'ROW_STALLED' $rig $row $req "no matching UI stage/readback change for $([int]$age)s; action=$actionId generation=$generation." 'error' $actionId $generation}
      continue
    }
    $obs=Read-Source $t
    if(-not $obs.ok){
      $rs.sourceAvailable=$false;Emit 'DEPENDENCY_BLOCKED' $rig $row $req $obs.reason 'error'
      $age=if($rs.lastProgressUtc){($now-(Parse-Utc ([string]$rs.lastProgressUtc))).TotalSeconds}elseif($rs.rowStartedUtc){($now-(Parse-Utc ([string]$rs.rowStartedUtc))).TotalSeconds}else{0}
      if($rs.phase -ne 'complete-awaiting-next' -and $age -ge [int]$t.stallSeconds){Emit 'ROW_STALLED' $rig $row $req "progress source unavailable for $([int]$age)s since observed row start; dependency remains unverified." 'error'}
      continue
    }
    $rs.sourceAvailable=$true
    if($obs.gamePid){$rs.gamePid=[int]$obs.gamePid}
    $lines=@([string]$obs.tail -split "`n" | Where-Object {$_ -match [regex]::Escape($req) -and $_ -match '(CHAT_THREAD|NPC_SAY|ACTION_EXEC|CHAT_SEND_STAGE|TEST_INBOX|GENERATION|SESSION_JOIN)'} )
    $matched=$lines | Select-Object -Last 1
    $cursor=''
    if($matched){
      $lineText=([string]$matched).Trim();$sha=[Security.Cryptography.SHA256]::Create()
      try{$cursor=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($lineText)))).Replace('-','')}
      finally{$sha.Dispose()}
    }
    $cursorChanged=($cursor -and $cursor -ne [string]$rs.cursor)
    $tailAdvanced=($rs.cursor -and $cursor -and $cursorChanged)
    if(-not $cursor){
      $rs.sourceAvailable=$true;$gameState=[string]$obs.gameState
      if($gameState -eq 'unknown' -and $t.source -eq 'local'){$gameState=Get-GameProcessState $t}
      if($gameState -eq 'dead'){Emit 'GAME_PROCESS_DEAD' $rig $row $req "isolated game executable absent at verified path $($t.gameExe); no process action taken." 'error'}
      $age=if($rs.lastProgressUtc){($now-(Parse-Utc ([string]$rs.lastProgressUtc))).TotalSeconds}elseif($rs.rowStartedUtc){($now-(Parse-Utc ([string]$rs.rowStartedUtc))).TotalSeconds}else{0}
      if($rs.phase -ne 'complete-awaiting-next' -and $age -ge [int]$t.stallSeconds){Emit 'ROW_STALLED' $rig $row $req "no exact-request native event for $([int]$age)s since observed row start; gameProcess=$gameState. PID/log mtime are not progress." 'error'}
      else{Emit 'DEPENDENCY_BLOCKED' $rig $row $req 'native log tail has no exact-request event; no generic log/game activity counts as progress.' 'warning'}
      continue
    }
    if(-not $rs.cursor){$rs.cursor=$cursor;$rs.lastProgressUtc=$now.ToString('o');Emit 'ROW_BASELINE' $rig $row $req 'Initial exact-request native event stored as baseline; baseline is not a progress event.'}
    elseif($tailAdvanced){$rs.cursor=$cursor;$rs.lastProgressUtc=$now.ToString('o');Emit 'ROW_PROGRESS' $rig $row $req $cursor}
    $game='unknown';if($t.source -eq 'local'){$game=Get-GameProcessState $t}
    if($obs.gamePid){$game='alive';$rs.gamePid=[int]$obs.gamePid}
    elseif($obs.gameState -and $obs.gameState -ne 'unknown'){$game=[string]$obs.gameState}
    elseif($t.source -eq 'ssh4080' -and $obs.ok -and $obs.gameState -eq 'dead'){$game='dead'}
    if($t.phase -eq 'awaiting-poststate' -and $cursor){
      if($rs.phase -ne 'complete-awaiting-next'){Emit 'ROW_DONE_AWAITING_EVIDENCE' $rig $row $req 'Exact row speech evidence exists; row terminal gate still awaits same-target post-state and durable receipt.'}
      $rs.phase='complete-awaiting-next'
    }
    if($game -eq 'dead'){Emit 'GAME_PROCESS_DEAD' $rig $row $req "configured game PID $($t.gamePid) is absent; no control action taken." 'error'}
    $age=if($rs.lastProgressUtc){($now-(Parse-Utc ([string]$rs.lastProgressUtc))).TotalSeconds}else{0}
    if($rs.lastProgressUtc -and $age -ge [int]$t.stallSeconds -and $rs.phase -ne 'complete-awaiting-next'){Emit 'ROW_STALLED' $rig $row $req "no exact-request native progress for $([int]$age)s; gameProcess=$game (PID alone is not progress)." 'error'}
    if($game -eq 'alive' -and -not $tailAdvanced -and $row){$rs.health='game-alive-no-row-progress'}
  }
  $state.version=3;$state.heartbeatUtc=$now.ToString('o');$state.pid=$PID
  Write-AtomicJson $statePath $state
  # Publish one durable commit event per rig only after the matching state snapshot is on disk.
  foreach($t in $targets.rigs){$rig=[string]$t.rig;$rs=$state.rigs[$rig];Emit 'TICK_COMMITTED' $rig ([string]$rs.row) ([string]$rs.request) "heartbeat=$($state.heartbeatUtc); row=$($rs.row); request=$($rs.request); actionId=$($rs.uiActionId); generation=$($rs.uiGeneration); phase=$($rs.phase); sourceAvailable=$($rs.sourceAvailable); ticks=$($rs.ticks)" 'info' ([string]$rs.uiActionId) ([int]$rs.uiGeneration)}
}
function Start-WakerLock {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  for($attempt=0;$attempt -lt 3;$attempt++){
    try {
      $script:lockStream=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      $bytes=[Text.Encoding]::UTF8.GetBytes((@{pid=$PID;startedUtc=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Compress))
      $script:lockStream.Write($bytes,0,$bytes.Length);$script:lockStream.Flush();return $true
    } catch [IO.IOException] {
      Start-Sleep -Milliseconds 50
      $probe=$null
      try {$probe=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)} catch {return $false}
      try {
        $bytes=New-Object byte[] ([int]$probe.Length);[void]$probe.Read($bytes,0,$bytes.Length);$raw=[Text.Encoding]::UTF8.GetString($bytes)
        $old=$raw|ConvertFrom-Json -ErrorAction SilentlyContinue
        if($old.pid -and (Get-Process -Id ([int]$old.pid) -ErrorAction SilentlyContinue)){return $false}
      } finally {$probe.Dispose()}
      Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
  }
  $false
}
function Stop-WakerLock {if($script:lockStream){$script:lockStream.Dispose()};if(Test-Path $lockPath){try{$l=Get-Content $lockPath -Raw|ConvertFrom-Json;if([int]$l.pid -eq $PID){Remove-Item -LiteralPath $lockPath -Force}}catch{}}}

if($RemoteGameQueryFixture){Write-Output (Resolve-RemoteGameState $FixtureGamePid ([bool]$FixtureQuerySucceeded));exit 0}
if($Sha256Fixture){Write-Output (Get-Sha256Hex $FixturePath);exit 0}
if($AppendEventFixture){if(-not $FixturePath){throw 'AppendEventFixture requires FixturePath'};$eventsPath=$FixturePath;Emit 'APPEND_FIXTURE' 'both' 'none' '' 'synthetic file-sharing retry';Write-Output 'EVENT_APPEND_FIXTURE_PASS';exit 0}
if($PostOpenFailureFixture){
  if(-not $FixturePath){throw 'PostOpenFailureFixture requires FixturePath'}
  $eventsPath=$FixturePath;$prior="{`"sequence`":7,`"code`":`"PRIOR_A`"}`r`n{`"sequence`":8,`"code`":`"PRIOR_B`"}`r`n";$priorBytes=[Text.UTF8Encoding]::new($false).GetBytes($prior);[IO.File]::WriteAllBytes($eventsPath,$priorBytes);Init-EventSequence;$script:forcePartialAppendFailure=$true
  try{Emit 'PARTIAL_FIXTURE' 'both' 'none' '' 'synthetic partial write';throw 'fixture expected the post-open write failure'}catch{if(-not $script:eventAppendUnsafe -or $_.Exception.Message -notmatch 'synthetic post-open partial-write failure'){throw}}
  $before=[IO.File]::ReadAllText($eventsPath)
  try{Emit 'FORBIDDEN_AFTER_PARTIAL' 'both' 'none' '' 'must not append';throw 'unsafe event append was not blocked'}catch{if($_.Exception.Message -notmatch 'refusing further appends'){throw}}
  if([IO.File]::ReadAllText($eventsPath) -ne $before){throw 'unsafe follow-on event changed the partial tail'}
  $script:forcePartialAppendFailure=$false;$script:eventAppendUnsafe=$false;$script:eventSequence=0;Init-EventSequence
  $recoveredBytes=[IO.File]::ReadAllBytes($eventsPath);if($recoveredBytes.Length -lt $priorBytes.Length -or [Text.Encoding]::UTF8.GetString($recoveredBytes,0,$priorBytes.Length) -ne $prior){throw 'restart did not preserve all complete prior events'}
  if($recoveredBytes.Length -ne $priorBytes.Length){throw 'restart did not truncate only the malformed trailing fragment'}
  Emit 'RECOVERED_AFTER_PARTIAL' 'both' 'none' '' 'restart truncated malformed trailing fragment under exclusive ownership'
  $events=@([IO.File]::ReadAllLines($eventsPath)|ForEach-Object {try{$_|ConvertFrom-Json -ErrorAction Stop}catch{$null}}|Where-Object {$null -ne $_})
  if($events.Count -ne 3 -or $events[0].code -ne 'PRIOR_A' -or $events[1].code -ne 'PRIOR_B' -or $events[2].code -ne 'RECOVERED_AFTER_PARTIAL' -or $events[2].sequence -ne 9){throw 'restart did not preserve complete event history and recover sequence after partial tail'}
  Write-Output 'EVENT_POSTOPEN_FAILURE_FIXTURE_PASS';exit 0
}
if($InteriorCorruptionFixture){
  if(-not $FixturePath){throw 'InteriorCorruptionFixture requires FixturePath'}
  $eventsPath=$FixturePath
  $corrupt="{`"sequence`":1,`"code`":`"PRIOR`"}`r`nnot-json`r`n{`"sequence`":2,`"code`":`"AFTER`"}`r`n"
  [IO.File]::WriteAllText($eventsPath,$corrupt,[Text.UTF8Encoding]::new($false));$before=[IO.File]::ReadAllBytes($eventsPath)
  try{Init-EventSequence;throw 'interior corruption was accepted'}catch{if(-not $script:eventAppendUnsafe -or $_.Exception.Message -notmatch 'invalid non-trailing event JSONL record'){throw}}
  try{Emit 'FORBIDDEN_AFTER_CORRUPTION' 'both' 'none' '' 'must not append';throw 'unsafe append after interior corruption was not blocked'}catch{if($_.Exception.Message -notmatch 'refusing further appends'){throw}}
  $after=[IO.File]::ReadAllBytes($eventsPath)
  if($after.Length -ne $before.Length -or [Convert]::ToBase64String($after) -ne [Convert]::ToBase64String($before)){throw 'interior-corrupt journal changed after fail-closed recovery'}
  Write-Output 'EVENT_INTERIOR_CORRUPTION_FIXTURE_PASS';exit 0
}
if($ExclusiveRecoveryFixture){
  if(-not $FixturePath){throw 'ExclusiveRecoveryFixture requires FixturePath'}
  $eventsPath=$FixturePath;$valid="{`"sequence`":1,`"code`":`"PRIOR`"}`r`n";[IO.File]::WriteAllText($eventsPath,$valid,[Text.UTF8Encoding]::new($false));$before=[IO.File]::ReadAllBytes($eventsPath)
  $held=[IO.File]::Open($eventsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{
    try{Init-EventSequence;throw 'exclusive recovery succeeded while an incompatible reader held the journal'}catch{if(-not $script:eventAppendUnsafe -or $_.Exception.Message -notmatch 'IOException|being used by another process|sharing violation'){throw}}
    try{Emit 'FORBIDDEN_WHILE_READER_HELD' 'both' 'none' '' 'must not append';throw 'unsafe append after exclusive-open failure was not blocked'}catch{if($_.Exception.Message -notmatch 'refusing further appends'){throw}}
    $after=[IO.File]::ReadAllBytes($eventsPath);if($after.Length -ne $before.Length -or [Convert]::ToBase64String($after) -ne [Convert]::ToBase64String($before)){throw 'journal changed while exclusive recovery was blocked'}
  }finally{$held.Dispose()}
  Write-Output 'EVENT_EXCLUSIVE_RECOVERY_FIXTURE_PASS';exit 0
}
if($Utf8PartialSuffixFixture){
  if(-not $FixturePath){throw 'Utf8PartialSuffixFixture requires FixturePath'}
  $eventsPath=$FixturePath;$prior='{"sequence":41,"code":"PRIOR","text":"caf\u00e9"}'+"`r`n";$utf8NoBom=[Text.UTF8Encoding]::new($false);$priorBytes=$utf8NoBom.GetBytes($prior)
  $partialPrefix=$utf8NoBom.GetBytes('{"sequence":42,"code":"BROKEN","text":"');$partial=[byte[]]@($partialPrefix + [byte[]]@(0xF0,0x9F));$combined=[byte[]]@($priorBytes + $partial);[IO.File]::WriteAllBytes($eventsPath,$combined)
  Init-EventSequence;$afterRecovery=[IO.File]::ReadAllBytes($eventsPath)
  if($afterRecovery.Length -ne $priorBytes.Length -or [Convert]::ToBase64String($afterRecovery) -ne [Convert]::ToBase64String($priorBytes)){throw 'incomplete multibyte suffix was not truncated while preserving complete UTF-8 event'}
  Emit 'RECOVERED_AFTER_UTF8_PARTIAL' 'both' 'none' '' 'truncated incomplete multibyte suffix'
  $events=@([IO.File]::ReadAllLines($eventsPath)|ForEach-Object {$_|ConvertFrom-Json -ErrorAction Stop})
  if($events.Count -ne 2 -or $events[0].text -ne ('caf'+[char]0xE9) -or $events[1].sequence -ne 42){throw 'multibyte recovery failed to preserve valid record or sequence'}
  Write-Output 'EVENT_UTF8_PARTIAL_SUFFIX_FIXTURE_PASS';exit 0
}
if($ValidateTargetSetFixture){$set=Get-TargetSet;$why=Validate-TargetSet $set;if($why){Write-Output "TARGET_SET_INVALID $why";exit 2};Write-Output 'TARGET_SET_VALID';exit 0}
if($SelfTest){
  $test=Join-Path $Root 'testing\live-stobe-queue\progress-waker-selftest.ps1'
  & $test -WakerPath $PSCommandPath -Root $Root; exit $LASTEXITCODE
}
if(-not $Run -and -not $Once){throw 'Specify -Run, -Once, or -SelfTest.'}
if(-not (Start-WakerLock)){Write-Output 'WAKER_ALREADY_RUNNING';exit 0}
try {
  Init-EventSequence
  do {Observe; if($Once){break}; Start-Sleep -Seconds 120} while($true)
} catch {
  if($script:eventAppendUnsafe){[Console]::Error.WriteLine("WAKER_ERROR not appended: event JSONL tail may be partial. $($_.Exception.Message)")}
  else{try{Emit 'WAKER_ERROR' 'both' 'unknown' '' $_.Exception.Message 'error'}catch{[Console]::Error.WriteLine("WAKER_ERROR event append failed: $($_.Exception.Message)")}}
  throw
}
finally {Stop-WakerLock}

