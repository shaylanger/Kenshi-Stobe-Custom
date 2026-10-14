param([switch]$Run, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$base = 'C:\KenshiModding\testing\rig-progress-watchdog'
$eventsPath = Join-Path $base 'events.jsonl'
$statePath = Join-Path $base 'state.json'
$receiptPath = Join-Path $base 'producer.receipt.json'
$status5090 = 'C:\KenshiModding\testing\live-stobe-queue\5090-p0-operator.status'
$status4080 = 'C:\KenshiModding\testing\live-stobe-queue\4080-live-operator.status.md'
$remoteObserver = 'C:\KenshiModding\testing\rig-progress-watchdog\observe-4080-i3.sh'
$remoteWrapper = 'C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1'
$periodSeconds = 120

function Write-JsonAtomic([string]$Path, $Value) {
    $temp = "$Path.$PID.tmp"
    $json = ConvertTo-Json -InputObject $Value -Depth 8
    [IO.File]::WriteAllText($temp, $json + "`n", [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Read-Status([string]$Path, [string[]]$Keys) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{ available=$false; digest=''; fields=@{}; modifiedUtc=$null } }
    $raw = [IO.File]::ReadAllText($Path)
    $fields = [ordered]@{}
    foreach ($line in ($raw -split "`r?`n")) {
        foreach ($key in $Keys) {
            if ($line -match ("^(?:\*\*)?" + [regex]::Escape($key) + "\*\*?\s*[:=]\s*(.*)$")) {
                $fields[$key] = $Matches[1].Trim()
            } elseif ($line -match ("^" + [regex]::Escape($key) + "\s*[:=]\s*(.*)$")) {
                $fields[$key] = $Matches[1].Trim()
            }
        }
    }
    $semantic = ($fields.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    $sha = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes($semantic)))).Replace('-', '')
    [pscustomobject]@{ available=$true; digest=$sha; fields=$fields; modifiedUtc=(Get-Item -LiteralPath $Path).LastWriteTimeUtc.ToString('o') }
}

function Get-LocalProcess([int]$Id) {
    try {
        $p = Get-Process -Id $Id -ErrorAction Stop
        [pscustomobject]@{ pid=$p.Id; name=$p.ProcessName; startUtc=$p.StartTime.ToUniversalTime().ToString('o'); responding=$p.Responding; state='alive' }
    } catch {
        [pscustomobject]@{ pid=$Id; name=$null; startUtc=$null; responding=$false; state='missing_or_unreadable' }
    }
}

function Get-LocalHealth([int]$Port) {
    try {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
        $timer.Stop()
        [pscustomobject]@{ port=$Port; status=[int]$r.StatusCode; ms=[int]$timer.ElapsedMilliseconds; state='healthy' }
    } catch {
        [pscustomobject]@{ port=$Port; status=0; ms=$null; state='unavailable' }
    }
}

function Parse-Remote4080([string[]]$out, [int]$exit) {
    $joined = $out -join "`n"
    $health = if ($joined -match 'http=(\d+) total=([0-9.]+)') { [pscustomobject]@{ status=[int]$Matches[1]; seconds=[double]$Matches[2]; state=if ([int]$Matches[1] -eq 200) {'healthy'} else {'unhealthy'} } } else { [pscustomobject]@{ status=0; seconds=$null; state='unknown' } }
    $processes = @()
    if ($joined -match '"Id"\s*:\s*3452\s*,\s*"ProcessName"\s*:\s*"kenshi_x64"') { $processes += [pscustomobject]@{ pid=3452; name='kenshi_x64'; state='alive' } }
    if ($joined -match '"Id"\s*:\s*2260\s*,\s*"ProcessName"\s*:\s*"llama-server"') { $processes += [pscustomobject]@{ pid=2260; name='llama-server'; state='alive' } }
    $listenerPid = if ($joined -match 'LISTENER=.*:18084.*LISTENING\s+(\d+)') { [int]$Matches[1] } else { $null }
    [pscustomobject]@{ host=if ($joined -match 'DESKTOP-NQQPA73') {'DESKTOP-NQQPA73'} else {'unknown'}; exitCode=$exit; processes=$processes; listenerPid=$listenerPid; health=$health; outputTail=($out | Select-Object -Last 8) }
}

function Get-Remote4080 {
    $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $remoteWrapper -BodyPath $remoteObserver 2>&1 | ForEach-Object { [string]$_ })
    $exit = $LASTEXITCODE
    Parse-Remote4080 $out $exit
}

if ($SelfTest) {
    $fixture = @('DESKTOP-NQQPA73','PROCESS=[{"Id":3452,"ProcessName":"kenshi_x64","Responding":true},{"Id":2260,"ProcessName":"llama-server","Responding":true}]','LISTENER=  TCP    127.0.0.1:18084        0.0.0.0:0              LISTENING       3532','HEALTH=http=200 total=0.128332')
    $parsed = Parse-Remote4080 $fixture 0
    if ($parsed.host -ne 'DESKTOP-NQQPA73' -or $parsed.exitCode -ne 0 -or $parsed.processes.Count -ne 2 -or $parsed.listenerPid -ne 3532 -or $parsed.health.status -ne 200) { throw '4080 observer parse fixture failed' }
    'RESULT RIG-PROGRESS-PARSER PASS processes=2 listenerPid=3532 health=200'
    exit 0
}
if (-not $Run) { throw 'Usage: rig-progress-producer.ps1 -Run (detached, hidden, read-only paired observer) | -SelfTest' }
if (-not (Test-Path -LiteralPath $base -PathType Container)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
$mutex = New-Object Threading.Mutex($false, 'Local\KenshiRigProgressProducerI3')
if (-not $mutex.WaitOne(0)) { throw 'A paired progress producer already owns the mutex' }
try {
    $self = Get-Process -Id $PID -ErrorAction Stop
    $producerStart = $self.StartTime.ToUniversalTime().ToString('o')
    $shaAlgorithm = [Security.Cryptography.SHA256]::Create()
    try { $scriptHash = ([BitConverter]::ToString($shaAlgorithm.ComputeHash([IO.File]::ReadAllBytes($PSCommandPath)))).Replace('-', '') } finally { $shaAlgorithm.Dispose() }
    $receipt = [ordered]@{ schema=1; pid=$PID; startUtc=$producerStart; script=$PSCommandPath; scriptSha256=$scriptHash; intervalSeconds=$periodSeconds; status5090=$status5090; status4080=$status4080; remoteObserver=$remoteObserver; remoteWrapper=$remoteWrapper; owner5090='/root/5090_p0_game_operator'; owner4080='/root/4080_corrected_session_diagnostic_operator'; startedUtc=[DateTime]::UtcNow.ToString('o') }
    Write-JsonAtomic $receiptPath $receipt
    $seq = 0
    if (Test-Path -LiteralPath $eventsPath -PathType Leaf) {
        $lastEvent = Get-Content -LiteralPath $eventsPath -Tail 1 -ErrorAction SilentlyContinue
        if ($lastEvent) { try { $seq = [long](($lastEvent | ConvertFrom-Json -ErrorAction Stop).sequence) } catch { throw 'Existing event tail is malformed; refusing to append' } }
    }
    $previous = @{}
    while ($true) {
        $started = [DateTime]::UtcNow
        $a = Read-Status $status5090 @('stage','actual_progress','last_case','session','backend','provider','actor_candidate','next','receipt')
        $b = Read-Status $status4080 @('Owner','Task','Current step','Outputs','Current game','Next','Fresh evidence','Parallel owners','Progress','request','row','terminal')
        $rig5090 = [pscustomobject]@{ game=(Get-LocalProcess 26972); model=(Get-LocalProcess 97588); adapter=(Get-LocalProcess 29152); endpoint18098=(Get-LocalHealth 18098); endpoint14725='operator-reported WSL/Linux route; not observable from this Windows probe'; operatorStatus=$a; activeRequestIds=@(); taskEvidence='No active request/stream reported by operator' }
        $rig4080 = [pscustomobject]@{ remote=(Get-Remote4080); operatorStatus=$b; activeRequestIds=@(); taskEvidence='Correlate request/model/native progress from operator receipt' }
        $seq++
        $current = [ordered]@{ schema=1; sequence=$seq; atUtc=$started.ToString('o'); producerPid=$PID; producerStartUtc=$producerStart; rigs=[ordered]@{ '5090'=$rig5090; '4080'=$rig4080 } }
        Write-JsonAtomic $statePath $current
        $codes = @()
        foreach ($name in '5090','4080') {
            $r = $current.rigs[$name]
            $digest = if ($name -eq '5090') { $r.operatorStatus.digest } else { $r.operatorStatus.digest }
            $alive = if ($name -eq '5090') { $r.game.state -eq 'alive' } else { @($r.remote.processes | Where-Object { $_.pid -eq 3452 -and $_.state -eq 'alive' }).Count -gt 0 }
            $healthOk = if ($name -eq '5090') { $r.endpoint18098.status -eq 200 } else { $r.remote.health.status -eq 200 }
            $progress = if ($previous.ContainsKey($name)) { $digest -ne $previous[$name].digest } else { $false }
            $codes += [pscustomobject]@{ rig=$name; processAlive=$alive; endpointHealthy=$healthOk; semanticStatusChanged=$progress; semanticDigest=$digest; correlatedNativeOrRequestProgress='unverified' }
            $previous[$name] = @{ digest=$digest; alive=$alive; healthOk=$healthOk }
        }
        $event = [ordered]@{ sequence=$seq; atUtc=$started.ToString('o'); code='PAIRED_OBSERVATION'; producerPid=$PID; producerStartUtc=$producerStart; snapshotSequence=$seq; rigs=$codes; buildProducer='not-yet-reported' }
        [IO.File]::AppendAllText($eventsPath, ((ConvertTo-Json -InputObject $event -Depth 8 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        $remaining = [Math]::Max(1, $periodSeconds - [int]([DateTime]::UtcNow - $started).TotalSeconds)
        Start-Sleep -Seconds $remaining
    }
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
