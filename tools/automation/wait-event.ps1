# wait-event.ps1: block in ONE process until something happens, instead of a loop of ls / wsl.exe / ssh checks
# (Shay 2026-10-10 ~22:05: agents polling every few seconds kept spawning wsl/powershell/ssh processes = constant CPU churn).
# Local paths use FileSystemWatchers (Wait-Event), plus a cheap re-check every -Poll s (default 30: watchers miss events on
# /mnt/c written from WSL and on \\wsl.localhost paths). 4080 conditions use ONE long-lived ssh running a remote watcher.
# Keep -Timeout <= 120 (CLAUDE.md waker rule: stay reachable); a TIMEOUT just means "wait again".
#
# Conditions (any one firing ends the wait; comma lists allowed; paths may be C:\..., /mnt/c/... or WSL /root/...):
#   -File <p,..>         p exists (already existing counts at once; add -New to need it created/written after the start)
#   -Match <regex>       with -File: the file must also contain this regex (e.g. -File x.result -Match 'PASS|FAIL')
#   -Changed <p,..>      p's size/mtime/existence differs from the start (e.g. C:\KenshiTestRuns\staged\KenshiFP-latest.txt)
#   -Glob <dir\pat,..>   a file matching pat in dir is created/written after the start (e.g. C:\KenshiTestRuns\agents\me.note-from-*)
#   -Status <name,..>    C:\KenshiTestRuns\agents\<name>.status reaches -Want (regex, default DONE|FAILED|STOPPED-CONTEXT)
#   -Remote4080 <p,..>   p exists on the 4080 (one ssh for the whole wait; the remote side checks every 5 s)
# Liveness (a dead or stuck producer must not hide behind a quiet wait; checked after the conditions):
#   -Pid <n|wsl:n>       Windows pid, or wsl:<pid> in DwemerAI4Skyrim3: gone (or reused) => PRODUCER GONE
#   -Producer <x>        inflight marker name (C:\KenshiTestRuns\inflight\<x>; its first line = out dir, "4080:<path>" = on the
#                        4080), an out dir (batch.pid / pipeline.pid inside give the pid), a pid file, or a log file.
#                        PRODUCER GONE = pid ended / marker deleted while the out dir has no DONE; STALE = nothing in the out
#                        dir (depth 2) / the log changed for -StaleMin minutes (default 20). A DONE in the out dir = producer
#                        finished: liveness checks stop, the wait goes on for the condition (consumers like the rig runner lag).
# Output: ONE line; exit code   0 EVENT <what>   1 TIMEOUT <s>s   2 PRODUCER GONE <why>   3 STALE <n> min <path>   4 usage/error
# Examples:
#   wait-event.ps1 -File C:\KenshiTestRuns\queue\done\03-twohand.list.SUMMARY.txt -Producer runner-5090 -Timeout 110
#   wait-event.ps1 -Changed C:\KenshiTestRuns\staged\KenshiFP-latest.txt -Producer kfp-pipeline-run-1010-2206 -Timeout 110
#   wait-event.ps1 -Status kfp-fixer -Glob 'C:\KenshiTestRuns\agents\coordinator.note-from-*' -Timeout 110
#   wait-event.ps1 -Remote4080 C:\KenshiTestRuns\twohand-4080\DONE -Producer kfp-twohand -Timeout 110
# WSL callers: bash tools/automation/wait-event.sh <same args>
param(
    [string[]]$File = @(), [string]$Match = '', [switch]$New,
    [string[]]$Changed = @(), [string[]]$Glob = @(),
    [string[]]$Status = @(), [string]$Want = 'DONE|FAILED|STOPPED-CONTEXT',
    [string[]]$Remote4080 = @(),
    [Alias("Pid")][string]$ProcId = '', [string]$Producer = '', [int]$StaleMin = 20,
    [int]$Timeout = 110, [int]$Poll = 30
)
$ErrorActionPreference = 'Continue'
$distro = 'DwemerAI4Skyrim3'
$runs = 'C:\KenshiTestRuns'
function Split-List([string[]]$a) { @($a | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
function To-Win([string]$p) {
    $p = $p.Trim()
    if ($p -match '^/mnt/([a-zA-Z])/(.*)$') { return ($Matches[1].ToUpper() + ':\' + ($Matches[2] -replace '/', '\')) }
    if ($p -match '^/') { return ("\\wsl.localhost\$distro" + ($p -replace '/', '\')) }
    $p
}
$File = @(Split-List $File | ForEach-Object { To-Win $_ }); $Changed = @(Split-List $Changed | ForEach-Object { To-Win $_ })
$Glob = @(Split-List $Glob | ForEach-Object { To-Win $_ }); $Status = @(Split-List $Status); $Remote4080 = @(Split-List $Remote4080)
if (-not ($File.Count + $Changed.Count + $Glob.Count + $Status.Count + $Remote4080.Count) -and -not $ProcId -and -not $Producer) {
    'ERROR usage: give -File/-Changed/-Glob/-Status/-Remote4080 and/or -Pid/-Producer (header of wait-event.ps1)'; exit 4
}
$t0 = Get-Date
$deadline = $t0.AddSeconds($Timeout)
function Snap([string]$p) { $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; if ($i) { "$($i.LastWriteTimeUtc.Ticks)|$($i.Length)" } else { 'none' } }
$snaps = @{}; foreach ($p in $Changed) { $snaps[$p] = Snap $p }

# ---- producer resolution ----
$prodDir = $null; $prodLog = $null; $marker = $null; $remoteProd = $null; $wslPid = $null; $winPid = $null
$pidLabel = ''
if ($ProcId -match '^wsl:(\d+)$') { $wslPid = [int]$Matches[1] } elseif ($ProcId -match '^\d+$') { $winPid = [int]$ProcId } elseif ($ProcId) { "ERROR bad -Pid '$ProcId' (n or wsl:n)"; exit 4 }
if ($Producer) {
    $mp = Join-Path "$runs\inflight" $Producer
    $pw = To-Win $Producer
    if ((Test-Path -LiteralPath $mp -PathType Leaf) -or ($pw -like "$runs\inflight\*" -and (Test-Path -LiteralPath $pw -PathType Leaf))) {
        $marker = if (Test-Path -LiteralPath $mp -PathType Leaf) { $mp } else { $pw }
        $first = ((Get-Content -LiteralPath $marker -TotalCount 1 -ErrorAction SilentlyContinue) -as [string])
        $first = if ($first) { $first.Trim() } else { '' }
        if ($first -match '^4080:(\S+)') { $remoteProd = $Matches[1] }
        elseif ($first -match '^(/\S+|[A-Za-z]:[\\/]\S*)') { $d = To-Win $Matches[1]; if (Test-Path -LiteralPath $d -PathType Container) { $prodDir = $d } elseif (Test-Path -LiteralPath $d -PathType Leaf) { $prodLog = $d } }
    } elseif (Test-Path -LiteralPath $pw -PathType Container) { $prodDir = $pw }
    elseif (Test-Path -LiteralPath $pw -PathType Leaf) {
        if ($pw -match '\.pid$') { $prodDir = Split-Path $pw -Parent } else { $prodLog = $pw }
    } else { "PRODUCER GONE '$Producer' not found (no inflight marker, dir or file)"; exit 2 }
    if ($prodDir -and -not $ProcId) {
        foreach ($pf in 'batch.pid', 'pipeline.pid') {
            $f = Join-Path $prodDir $pf
            if (Test-Path -LiteralPath $f) {
                $x = ((Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue) -as [string]).Trim() -split '\s+'
                # run-batch.sh writes "<wsl/msys pid> <winpid>"; on this PC batches run in WSL (no winpid)
                if ($x.Count -ge 2 -and $x[1] -match '^\d+$') { $winPid = [int]$x[1] } elseif ($x[0] -match '^\d+$') { $wslPid = [int]$x[0] }
                break
            }
        }
    }
}
function Wsl-Cmd([int]$n) { try { [IO.File]::ReadAllText("\\wsl.localhost\$distro\proc\$n\cmdline") } catch { $null } }
$wslCmd0 = $null; $winStart0 = $null
if ($wslPid) { $wslCmd0 = Wsl-Cmd $wslPid; $pidLabel = "wsl pid $wslPid" }
if ($winPid) { $pp = Get-Process -Id $winPid -ErrorAction SilentlyContinue; if ($pp) { try { $winStart0 = $pp.StartTime } catch {} }; $pidLabel = "pid $winPid" }
$pidDeadAtStart = ($wslPid -and -not $wslCmd0) -or ($winPid -and -not (Get-Process -Id $winPid -ErrorAction SilentlyContinue))

# ---- remote 4080 watcher: one ssh for the whole wait ----
$rproc = $null; $rout = $null
if ($Remote4080.Count -or $remoteProd) {
    function Q([string]$s) { "'" + ($s -replace "'", "''") + "'" }
    $fl = ($Remote4080 | ForEach-Object { Q $_ }) -join ','
    $rs = @"
`$files=@($fl); `$pd=$(Q ([string]$remoteProd)); `$stale=$StaleMin; `$end=(Get-Date).AddSeconds($($Timeout + 10)); `$wp=`$null; `$ws=`$null; `$n=0
function Pd { if(-not `$pd){return `$true}; `$s=`$pd -replace '\.[A-Za-z0-9]+$',''; (Test-Path "`$pd.DONE") -or (Test-Path "`$s.DONE") -or (Test-Path "`$pd\DONE") }
function Ev { foreach(`$f in `$files){ if(Test-Path -LiteralPath `$f){ "EVENT 4080 file `$f"; exit 0 } } }
if(`$pd -and (Test-Path "`$pd\batch.pid")){ `$x=(Get-Content "`$pd\batch.pid" -Raw).Trim() -split '\s+'; if(`$x.Count -ge 2 -and `$x[1] -match '^\d+$'){ `$wp=[int]`$x[1]; `$p=Get-Process -Id `$wp -EA SilentlyContinue; if(`$p){`$ws=`$p.StartTime} } }
'READY'
while(`$true){ Ev
 if(-not (Pd)){
  if(`$wp){ `$p=Get-Process -Id `$wp -EA SilentlyContinue; if(-not `$p -or (`$ws -and `$p.StartTime -ne `$ws)){ Start-Sleep 3; Ev; if(-not (Pd)){ "PRODUCER GONE 4080 pid `$wp (`$pd) ended without DONE"; exit 2 } } }
  if(`$n % 6 -eq 0){ `$nw=`$null; if(Test-Path -LiteralPath `$pd -PathType Container){ `$nw=Get-ChildItem -LiteralPath `$pd -Recurse -Depth 2 -File -EA SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object LastWriteTime } elseif(Test-Path -LiteralPath `$pd){ `$nw=(Get-Item -LiteralPath `$pd).LastWriteTime }
   if(`$nw){ `$a=((Get-Date)-`$nw).TotalMinutes; if(`$a -ge `$stale){ "STALE `$([int]`$a) min 4080:`$pd"; exit 3 } } }
 }
 if((Get-Date) -ge `$end){ 'TIMEOUT'; exit 1 }; `$n++; Start-Sleep 5 }
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($rs))
    $psi = New-Object Diagnostics.ProcessStartInfo 'ssh', "-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=30 4080 powershell -NoProfile -NonInteractive -EncodedCommand $b64"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $rproc = New-Object Diagnostics.Process; $rproc.StartInfo = $psi; $rproc.EnableRaisingEvents = $true
    $rout = New-Object Collections.Concurrent.ConcurrentQueue[string]
    Register-ObjectEvent -InputObject $rproc -EventName OutputDataReceived -SourceIdentifier 'we-rout' -MessageData $rout -Action { if ($EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } } | Out-Null
    Register-ObjectEvent -InputObject $rproc -EventName Exited -SourceIdentifier 'we-rexit' | Out-Null
    [void]$rproc.Start(); $rproc.BeginOutputReadLine()
}
function Stop-Remote { if ($rproc -and -not $rproc.HasExited) { try { $rproc.Kill() } catch {} } }
function Finish([string]$line, [int]$code) { Stop-Remote; Get-EventSubscriber -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue; $line; exit $code }

# ---- local watchers ----
$i = 0
$watch = @()
foreach ($p in @($File + $Changed + $Glob + @($Status | ForEach-Object { "$runs\agents\$_.status" }))) { $watch += , @((Split-Path $p -Parent), (Split-Path $p -Leaf)) }
if ($marker) { $watch += , @((Split-Path $marker -Parent), (Split-Path $marker -Leaf)) }
foreach ($w in $watch) {
    if (-not $w[0] -or -not (Test-Path -LiteralPath $w[0] -PathType Container)) { continue }
    try {
        $fw = New-Object IO.FileSystemWatcher $w[0], $w[1]
        $fw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
        foreach ($ev in 'Created', 'Changed', 'Renamed', 'Deleted') { Register-ObjectEvent -InputObject $fw -EventName $ev -SourceIdentifier "we-$i-$ev" | Out-Null }
        $fw.EnableRaisingEvents = $true; $i++
    } catch {}
}

function Check-Conditions {
    foreach ($p in $File) {
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it) { continue }
        if ($New -and $it.LastWriteTime -le $t0) { continue }
        if ($Match -and -not (Select-String -LiteralPath $p -Pattern $Match -Quiet -ErrorAction SilentlyContinue)) { continue }
        return "EVENT file $p"
    }
    foreach ($p in $Changed) { if ((Snap $p) -ne $snaps[$p]) { return "EVENT changed $p" } }
    foreach ($g in $Glob) {
        $hit = Get-ChildItem -Path (Split-Path $g -Parent) -Filter (Split-Path $g -Leaf) -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $t0 } | Select-Object -First 1
        if ($hit) { return "EVENT new $($hit.FullName)" }
    }
    foreach ($n in $Status) {
        $l = (Get-Content -LiteralPath "$runs\agents\$n.status" -TotalCount 1 -ErrorAction SilentlyContinue) -as [string]
        if ($l) { $st = ($l -split '\|')[1]; if ($st -and $st.Trim() -match "^($Want)$") { return "EVENT status $n=$($st.Trim())" } }
    }
    if ($rout) { $r = $null; while ($rout.TryDequeue([ref]$r)) { if ($r -like 'EVENT*') { return $r } elseif ($r -match '^(PRODUCER GONE|STALE)') { return "R:$r" } } }
    if ($rproc -and $rproc.HasExited -and $rproc.ExitCode -ne 1) {
        Start-Sleep -Milliseconds 300; $r = $null; while ($rout.TryDequeue([ref]$r)) { if ($r -like 'EVENT*') { return $r } elseif ($r -match '^(PRODUCER GONE|STALE)') { return "R:$r" } }
        $err = ($rproc.StandardError.ReadToEnd() -replace '\s+', ' ').Trim()
        return "R:ERROR 4080 watcher ended rc=$($rproc.ExitCode) $($err.Substring(0, [Math]::Min(150, $err.Length)))"
    }
    $null
}
function ProdDone { $prodDir -and ((Test-Path -LiteralPath (Join-Path $prodDir 'DONE')) -or (Test-Path -LiteralPath (Join-Path $prodDir 'GAMEDONE'))) }
function Check-Producer {
    if (ProdDone) { return $null }
    if ($wslPid) { $c = Wsl-Cmd $wslPid; if (-not $c -or ($wslCmd0 -and $c -ne $wslCmd0)) { return "PRODUCER GONE $pidLabel ended$(if ($prodDir) { " ($prodDir has no DONE)" })" } }
    if ($winPid) {
        $pp = Get-Process -Id $winPid -ErrorAction SilentlyContinue; $s = $null; if ($pp) { try { $s = $pp.StartTime } catch {} }
        if (-not $pp -or ($winStart0 -and $s -and $s -ne $winStart0)) { return "PRODUCER GONE $pidLabel ended$(if ($prodDir) { " ($prodDir has no DONE)" })" }
    }
    if ($marker -and -not $remoteProd -and -not (Test-Path -LiteralPath $marker)) { return "PRODUCER GONE marker $(Split-Path $marker -Leaf) removed without the event$(if ($prodDir) { " ($prodDir has no DONE)" })" }
    $nw = $null; $what = $null
    if (((Get-Date) - $script:lastStale).TotalSeconds -lt 30) { return $null }   # the stale listing runs at most every 30 s
    $script:lastStale = Get-Date
    if ($prodDir) { $what = $prodDir; $nw = Get-ChildItem -LiteralPath $prodDir -Recurse -Depth 2 -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object LastWriteTime; if (-not $nw) { $nw = (Get-Item -LiteralPath $prodDir).LastWriteTime } }
    elseif ($prodLog) { $what = $prodLog; $it = Get-Item -LiteralPath $prodLog -ErrorAction SilentlyContinue; if ($it) { $nw = $it.LastWriteTime } else { return "PRODUCER GONE log $prodLog deleted" } }
    if ($nw) { $a = ((Get-Date) - $nw).TotalMinutes; if ($a -ge $StaleMin) { return "STALE $([int]$a) min $what" } }
    $null
}
function Out-Result([string]$r) {
    if ($r -like 'R:*') { $r = $r.Substring(2) }
    if ($r -like 'EVENT*') { Finish $r 0 } elseif ($r -like 'PRODUCER GONE*') { Finish $r 2 } elseif ($r -like 'STALE*') { Finish $r 3 } else { Finish $r 4 }
}

if ($pidDeadAtStart) { $r = Check-Conditions; if ($r) { Out-Result $r }; Out-Result "PRODUCER GONE $pidLabel not running at the start" }
$script:lastStale = [datetime]::MinValue
# a Windows producer pid wakes the wait the moment it exits; a WSL pid is re-checked every 10 s (one 9p stat, no process)
if ($winPid) { try { $wp = Get-Process -Id $winPid -ErrorAction Stop; $wp.EnableRaisingEvents = $true; Register-ObjectEvent -InputObject $wp -EventName Exited -SourceIdentifier 'we-pexit' | Out-Null } catch {} }
if ($wslPid -and $Poll -gt 10) { $Poll = 10 }
while ($true) {
    $r = Check-Conditions; if ($r) { Out-Result $r }
    if ($ProcId -or $Producer) {
        $r = Check-Producer
        if ($r) { Start-Sleep 3; $c = Check-Conditions; if ($c) { Out-Result $c }; if (-not ($r -like 'PRODUCER GONE*' -and (ProdDone))) { Out-Result $r } }
    }
    $rem = ($deadline - (Get-Date)).TotalSeconds
    if ($rem -le 0) { Finish "TIMEOUT ${Timeout}s (nothing fired; wait again)" 1 }
    $slice = [int][Math]::Ceiling([Math]::Min($rem, $Poll))
    $e = Wait-Event -Timeout $slice
    if ($e) { Start-Sleep -Milliseconds 200; Get-Event -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue }
}
