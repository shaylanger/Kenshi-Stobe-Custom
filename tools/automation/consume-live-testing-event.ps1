param(
  [string]$EventsPath = 'C:\KenshiModding\testing\live-stobe-queue\progress-waker\events.jsonl',
  [string]$CursorPath = 'C:\KenshiModding\testing\live-stobe-queue\progress-waker\consumer.cursor',
  [string]$ReadyPath = 'C:\KenshiModding\testing\live-stobe-queue\progress-waker\consumer.ready',
  [long]$InitialCursor = 0,
  [int]$Timeout = 110,
  [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'

function Read-NextUnseen([string]$Path, [long]$AfterSequence) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  for($attempt=0;$attempt -lt 4;$attempt++){
    $stream=$null;$reader=$null
    try {
      $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
      $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
      while($null -ne ($line=$reader.ReadLine())){
        if (-not $line.Trim()) { continue }
        try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($null -ne $event.sequence -and [long]$event.sequence -gt $AfterSequence) { return $event }
      }
      return $null
    } catch [IO.IOException] {
      if($attempt -eq 3){return $null}
      Start-Sleep -Milliseconds (20 * ($attempt + 1))
    } finally { if($reader){$reader.Dispose()} elseif($stream){$stream.Dispose()} }
  }
  return $null
}

function Save-Cursor([string]$Path, [long]$Sequence) {
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $temp = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($temp, "$Sequence`n", [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Publish-Ready([string]$Path) {
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $temp = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($temp, "pid=$PID`nreadyUtc=$([DateTime]::UtcNow.ToString('o'))`n", [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Wait-ForUnseenEvent {
  param(
    [string]$Path, [long]$AfterSequence, [string]$Ready,
    [int]$TimeoutSeconds,
    [scriptblock]$OnArmed = $null,
    [scriptblock]$AfterInitialScan = $null
  )
  $full = [IO.Path]::GetFullPath($Path)
  $dir = Split-Path -Parent $full
  $leaf = Split-Path -Leaf $full
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "events directory missing: $dir" }
  if ($Ready -and (Test-Path -LiteralPath $Ready)) { Remove-Item -LiteralPath $Ready -Force }
  $watcher = New-Object IO.FileSystemWatcher $dir, $leaf
  $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
  $id = "live-events-$PID-$([guid]::NewGuid().ToString('N'))"
  try {
    foreach ($kind in 'Changed','Created','Renamed') {
      Register-ObjectEvent -InputObject $watcher -EventName $kind -SourceIdentifier "$id-$kind" | Out-Null
    }
    $watcher.EnableRaisingEvents = $true
    if ($OnArmed) { & $OnArmed }
    if ($Ready) { Publish-Ready $Ready }

    # The watcher is live before READY. The mandatory rescan closes the gap between
    # a caller's previous cursor read and watcher startup; later appends stay queued.
    $event = Read-NextUnseen $full $AfterSequence
    if ($event) { return $event }
    if ($AfterInitialScan) { & $AfterInitialScan }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
      $event = Read-NextUnseen $full $AfterSequence
      if ($event) { return $event }
      $remaining = ($deadline - [DateTime]::UtcNow).TotalSeconds
      $wait = [Math]::Max(0.05, [Math]::Min(1.0, $remaining))
      $signaled = Wait-Event -SourceIdentifier "$id-Changed" -Timeout $wait
      if (-not $signaled) { $signaled = Wait-Event -SourceIdentifier "$id-Created" -Timeout 0.01 }
      if (-not $signaled) { $signaled = Wait-Event -SourceIdentifier "$id-Renamed" -Timeout 0.01 }
      if ($signaled) { Remove-Event -EventIdentifier $signaled.EventIdentifier -ErrorAction SilentlyContinue }
    }
    return $null
  } finally {
    $watcher.EnableRaisingEvents = $false
    Get-EventSubscriber -ErrorAction SilentlyContinue | Where-Object { $_.SourceIdentifier -like "$id-*" } | Unregister-Event -ErrorAction SilentlyContinue
    Get-Event -ErrorAction SilentlyContinue | Where-Object { $_.SourceIdentifier -like "$id-*" } | Remove-Event -ErrorAction SilentlyContinue
    $watcher.Dispose()
  }
}

if ($SelfTest) {
  $testRoot = Join-Path ([IO.Path]::GetTempPath()) "live-event-consumer-selftest-$PID"
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
  $events = Join-Path $testRoot 'events.jsonl'; $cursor = Join-Path $testRoot 'cursor'; $ready = Join-Path $testRoot 'ready'
  $script:checks = 0
  function Assert([bool]$Ok, [string]$Name) { $script:checks++; if (-not $Ok) { throw "FAIL $Name" } }
  function Add-TestEvent([string]$Path, [long]$Sequence) { [IO.File]::AppendAllText($Path, ((@{sequence=$Sequence;code="SYNTH_$Sequence"}|ConvertTo-Json -Compress)+"`n"), [Text.UTF8Encoding]::new($false)) }
  try {
    # Append before watcher startup: the post-READY rescan must acknowledge it immediately.
    Add-TestEvent $events 1
    $e = Wait-ForUnseenEvent -Path $events -AfterSequence 0 -Ready $ready -TimeoutSeconds 1
    Assert ($e.sequence -eq 1) 'append-before-watcher-startup'
    Save-Cursor $cursor ([long]$e.sequence)
    Assert ((Get-Content $cursor -Raw).Trim() -eq '1') 'immediate-ack-before-block'

    # Append while the watcher is being armed, before READY and the rescan.
    Remove-Item $ready -Force
    $duringArm = { Add-TestEvent $events 2 }.GetNewClosure()
    $e = Wait-ForUnseenEvent -Path $events -AfterSequence 1 -Ready $ready -TimeoutSeconds 1 -OnArmed $duringArm
    Assert ($e.sequence -eq 2) 'append-during-watcher-arming'
    Save-Cursor $cursor ([long]$e.sequence)

    # Append after READY and the first empty rescan; the armed watcher must wake it.
    Remove-Item $ready -Force
    $afterScan = { Start-Sleep -Milliseconds 120; Add-TestEvent $events 3 }.GetNewClosure()
    $e = Wait-ForUnseenEvent -Path $events -AfterSequence 2 -Ready $ready -TimeoutSeconds 2 -AfterInitialScan $afterScan
    Assert ($e.sequence -eq 3) 'append-after-watcher-armed'
    Save-Cursor $cursor ([long]$e.sequence)

    # A writer may briefly deny reads while closing the append. The consumer retries next scan.
    Add-TestEvent $events 4
    $held=[IO.File]::Open($events,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { $e=Read-NextUnseen $events 3; Assert ($null -eq $e) 'concurrent-writer-lock-does-not-crash' }
    finally { $held.Dispose() }
    $e=Read-NextUnseen $events 3
    Assert ($e.sequence -eq 4) 'consumer-recovers-after-writer-closes'
    Save-Cursor $cursor ([long]$e.sequence)

    # Restart at the acknowledged cursor: the same event must not be delivered twice.
    Remove-Item $ready -Force
    $e = Wait-ForUnseenEvent -Path $events -AfterSequence ([long](Get-Content $cursor -Raw).Trim()) -Ready $ready -TimeoutSeconds 0
    Assert ($null -eq $e) 'restart-does-not-duplicate-ack'
    Assert ($script:checks -eq 7) 'all-race-cases-counted'
    "LIVE_EVENT_CONSUMER_SELFTEST PASS checks=$script:checks before=1 during=2 after=3 sharing=4 cursor=4 duplicate=false"
  } finally { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
  exit 0
}

if ($Timeout -lt 1 -or $Timeout -gt 120) { throw 'Timeout must be 1..120 seconds' }
if ($InitialCursor -lt 0) { throw 'InitialCursor must be nonnegative' }
$cursor = 0L
if (Test-Path -LiteralPath $CursorPath) {
  $rawCursor = (Get-Content -LiteralPath $CursorPath -Raw).Trim()
  if ($rawCursor -notmatch '^\d+$') { throw "invalid durable cursor: $rawCursor" }
  $cursor = [long]$rawCursor
} else { $cursor = $InitialCursor; Save-Cursor $CursorPath $cursor }
$event = Wait-ForUnseenEvent -Path $EventsPath -AfterSequence $cursor -Ready $ReadyPath -TimeoutSeconds $Timeout
if (-not $event) { "TIMEOUT cursor=$cursor"; exit 1 }
if ([long]$event.sequence -le $cursor) { throw 'event sequence did not advance beyond cursor' }
Save-Cursor $CursorPath ([long]$event.sequence)
"ACK sequence=$($event.sequence) code=$($event.code) cursor=$($event.sequence)"
exit 0
