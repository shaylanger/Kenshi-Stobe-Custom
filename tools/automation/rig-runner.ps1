<#
rig-runner.ps1: one daemon per rig runs that rig's batches from a queue folder, so no rig depends on an agent staying alive
(Shay 2026-10-10: "a script runs each rig, not an agent"; no rig idle or paused > 2 min while work exists). Agents only
write list files and judge results. Replaces rig-watchdog.ps1 (now a shim to this).

Use (PowerShell on the 5090; both rig loops run here, the 4080 one drives the 4080 over ssh):
  rig-runner.ps1 -Ensure                 start the 5090 and 4080 loops if not running (session-start.ps1 does this)
  rig-runner.ps1 -Status                 one line per rig + queue counts
  rig-runner.ps1 -Stop [-Rig 5090|4080]  stop the loop(s) and keep them stopped (<rig>.stopped: -Ensure skips it; a
                                         running batch keeps running; a restarted loop re-adopts it only if it is its own)
  rig-runner.ps1 -Start [-Rig 5090|4080] clear the stopped flag and start (= -Ensure -Force)
  rig-runner.ps1 -Restart [-Rig X]       deploy an edited rig-runner.ps1: the loop re-spawns itself at its next list boundary
  rig-runner.ps1 -Rig 5090|4080 [-Fake]  run one loop in the foreground (what -Ensure starts hidden)
  -Fake: test mode on a fake game: queue/runner dirs under C:\KenshiTestRuns\runner\fake\, no lock/install/launch, the
         "batch" is dryrun.sh over the list (writes DONE + SUMMARY.txt); tests pickup, FIFO, gating, done/failed, alerts.
  Pause a rig (no new batch, no alert): kenshi-ctl.ps1 idle "<reason>" / idle4080 "<reason>" (60 min), as before.

Queue: C:\KenshiTestRuns\queue\5090\, queue\4080\, queue\any\ ; one ready batch = one *.list file (run-batch.sh list
format), taken FIFO by file name: the rig's own folder first, then any\ (lists with Stobe rows - STOBE-*, tests/ingame/stobe,
*.txt scenarios - or "# rig: 5090" only go to the 5090). Header comments (all optional):
  # owner: <agent>            gets the notes (agents\<owner>.note-from-rig-runner); default coordinator
  # out: <name>               out dir C:\KenshiTestRuns\<name> (on that rig); default <list name>-<MMdd-HHmm>
  # launch: <save>            save to launch; default the first row's save ("home" -> auto-home); "-" rows need launch:
  # needs: KenshiFP latest                 (the default to write) install THE newest staged build, resolved at the batch
  #                                        boundary (no header: the newest staged build if it is newer than the installed DLL)
  # needs: KenshiFP <sha8>                 that build; if staging replaced it, the newest staged build that includes every
  #                                        patch of it (manifest patches line, runner\staged-history.tsv), else the installed
  #                                        one if it does, with a log line; fails only if none does. Harness <sha8> = must match
  #                                        (rig-runner.ps1 -Rig <rig> -Resolve "KenshiFP <sha8>|latest" shows the choice)
  # nodryrun: <row> <reason>  leave that row out of the dry run (fake-game gap); every other row must pass dryrun.sh
  # rig: 5090|4080            (any\ lists) only that rig takes it
  {CR} in rows = POSIX root of C: on the rig (/mnt/c on the 5090, /c on the 4080); {OUT} = the out dir (run-batch.sh).
States: queue\running\<rig>__<list> (running), queue\done\<list> + <list>.result (+ .SUMMARY.txt), queue\failed\<list> +
<list>.result (dryrun/install/setup failure: the owner gets a note, the runner goes on with the next list).
Per batch: list -> running\, stop Kenshi + install staged DLL if needed (SHA checked), dryrun.sh the list, snapshot
run-batch.sh into the out dir and run it (5090: --launch <save> --stop, lock owner runner-5090; 4080: kcfg test + ctl.ps1
launch -Owner rig4080 + input isolation, then run-batch.sh via C:\KAH\itrun.ps1, stop after DONE), inflight marker
runner-5090 / 4080-runner. When DONE: list -> done\, note to the owner, next list at once.
Every tick (60 s) during a batch: rig-runner-probe.sh. Stuck = Kenshi gone, crash dump, not in the world, harness silent,
or game time not moving, held >= 2 min (a row's STALL_MIN=<min> word raises it; launch/first load 15 min) AND no file in
the out dir changed for as long: kill the row's step (crash: kill the game; run-batch.sh relaunches), ALERT-<rig>.txt,
note to the owner; a second hit on the same row kills the game. Batch process gone without DONE: list -> failed\.
Queue empty (or 4080 unreachable with lists waiting) for >= 2 min: ALERT-<rig>.txt + note to the coordinator (rig-health.sh
and the Stop hook block on ALERT files); the ALERT clears when the rig works again.
Filler: both queues empty -> a COPY of the least recently started eligible queue\filler\*.list (needs: met by the installed
build, never installs; not running on the other rig; not benched) runs; rotation in runner\filler-rotation.tsv.
A filler never blocks real work: a list arriving in queue\<rig>\ or any\ writes <out>\PREEMPT; run-batch.sh stops after the
current row (BATCH PREEMPTED + rows not run in SUMMARY.txt), the copy goes to done\ (result "preempted"), the list starts.
-Fake "# fakesec: <n>" header: the fake batch runs n s (tests preemption).
No relaunch gap: Kenshi stays up between lists (5090 always, 4080 when a next list is queued); run-batch.sh --reuse loads
the save in place; Kenshi is stopped only for a DLL install. Fast setup FAIL: a list with no PASS whose RESULTs are all
setup/dryrun FAILs (or none / aborted) within -FastMin (15) min, or 3 instant setup FAILs in a row, writes the sticky
ALERT-<rig>-setup.txt (Stop hook; delete once handled, expires in 30 min); the runner goes on with the next list.
Stale queue\running\<rig>__* entries (no <rig>.cur/.tail naming them, no live run-batch.sh) are removed each tick.
Files: C:\KenshiTestRuns\runner\<rig>.pid|.log|.state|.cur, filler-rotation.tsv.
#>
param([ValidateSet('5090', '4080', '')][string]$Rig = '', [switch]$Ensure, [switch]$Stop, [switch]$Start, [switch]$Restart, [switch]$Keep4080, [switch]$Force, [switch]$Status, [switch]$Fake,
      [int]$IdleMin = 2, [int]$StuckMin = 2, [int]$TickSec = 60, [int]$FastMin = 15, [string]$Resolve = '')
$runs = 'C:\KenshiTestRuns'; $auto = 'C:\KenshiModding\tools\automation'
$rd = if ($Fake) { Join-Path $runs 'runner\fake' } else { Join-Path $runs 'runner' }
$qd = if ($Fake) { Join-Path $rd 'queue' } else { Join-Path $runs 'queue' }
foreach ($d in $rd, "$qd\5090", "$qd\4080", "$qd\any", "$qd\filler", "$qd\running", "$qd\done", "$qd\failed") { New-Item -ItemType Directory -Force $d | Out-Null }
$distro = 'DwemerAI4Skyrim3'
function PidAlive([string]$r) { $f = Join-Path $rd "$r.pid"; if (Test-Path $f) { $p = [int](Get-Content $f -Raw); return [bool](Get-Process -Id $p -ErrorAction SilentlyContinue) } $false }

# -Stop persists (2026-10-10: session-start's -Ensure restarted a loop the coordinator had just stopped): <rig>.stopped
# makes -Ensure skip that rig until -Start (or -Ensure -Force); a loop that sees the flag exits at its next tick.
function StopFlag([string]$r) { Join-Path $rd "$r.stopped" }
if ($Stop) {
    foreach ($r in $(if ($Rig) { @($Rig) } else { @('5090', '4080') })) {
        Set-Content (StopFlag $r) "$(Get-Date -Format s) by $(if ($env:KAH_OWNER) { $env:KAH_OWNER } else { 'coordinator' })"
        if (PidAlive $r) { Stop-Process -Id ([int](Get-Content (Join-Path $rd "$r.pid") -Raw)) -Force; "stopped runner $r (stays stopped: rig-runner.ps1 -Start -Rig $r)" } else { "runner $r not running (marked stopped)" }
        Remove-Item (Join-Path $rd "$r.pid") -ErrorAction SilentlyContinue
    }
    exit 0
}
# shared-mode reads/writes (2026-10-10: a `tail -F` on 5090.log made every Add-Content fail silently for an hour, and the
# state line went stale the same way): FileShare ReadWrite|Delete, a few retries
function ReadShared([string]$p) {
    for ($i = 0; $i -lt 5; $i++) {
        try { $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite, Delete'); try { return (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Close() } }
        catch [IO.FileNotFoundException] { return $null } catch [IO.DirectoryNotFoundException] { return $null } catch { Start-Sleep -Milliseconds 200 }
    }
    $null
}
function WriteShared([string]$p, [string]$text, [switch]$Append) {
    $b = [Text.Encoding]::UTF8.GetBytes($text)
    for ($i = 0; $i -lt 10; $i++) {
        try { $fs = [IO.File]::Open($p, $(if ($Append) { 'Append' } else { 'Create' }), 'Write', 'ReadWrite, Delete'); try { $fs.Write($b, 0, $b.Length) } finally { $fs.Close() }; return $true }
        catch { Start-Sleep -Milliseconds 200 }
    }
    $false
}
if ($Status) {
    # the state line is cross-checked with the runner's current files (2026-10-10: -Status showed "running rg-05 ... 21:17"
    # after the runner had moved on): <rig>.cur names the batch in its game part, <rig>.tail.* the ones still analysing
    foreach ($r in '5090', '4080') {
        $st = ReadShared "$rd\$r.state"; $st = if ($st) { $st.Trim() } else { '-' }
        $sf = Get-Item "$rd\$r.state" -ErrorAction SilentlyContinue
        $cur = ReadShared "$rd\$r.cur"; $cl = if ($cur) { @($cur -split "`r?`n") } else { @() }
        if ($cl.Count -ge 6 -and $cl[5]) {
            if ($st -notmatch [regex]::Escape($cl[5])) { $st = "running $($cl[5]) since $(try { ([datetime]$cl[4]).ToString('HH:mm') } catch { '?' }) (state line stale: '$st')" }
        } elseif ($st -match '^\d\d:\d\d (running|starting) ') { $st = "between lists (no batch in its game part; last state '$st')" }
        $age = if ($sf) { [int]((Get-Date) - $sf.LastWriteTime).TotalMinutes } else { -1 }
        if ($age -ge 3 -and (PidAlive $r)) { $st += " [state file $age min old: loop slow or stuck? see $r.log]" }
        $tl = @(Get-ChildItem $rd -Filter "$r.tail.*" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.Substring("$r.tail.".Length) })
        if ($tl.Count) { $st += " | analysing: $($tl -join ', ')" }
        $n = @(Get-ChildItem "$qd\$r" -Filter *.list -File -ErrorAction SilentlyContinue).Count
        $up = if (PidAlive $r) { 'up' } elseif (Test-Path (StopFlag $r)) { "STOPPED since $((Get-Content (StopFlag $r) -Raw).Trim()) (rig-runner.ps1 -Start -Rig $r)" } else { 'DOWN' }
        "runner $r ${up}: $st | queued $r=$n"
    }
    "queued any=$(@(Get-ChildItem "$qd\any" -Filter *.list -File -ErrorAction SilentlyContinue).Count) filler=$(@(Get-ChildItem "$qd\filler" -Filter *.list -File -ErrorAction SilentlyContinue).Count)"
    if (Test-Path "$rd\filler-rotation.tsv") { Get-Content "$rd\filler-rotation.tsv" | ForEach-Object { $p = $_ -split "`t"; "  filler $($p[0]) last=$($p[1]) rig=$($p[2])$(if ($p.Count -ge 4 -and $p[3]) { " benched-until=$($p[3]) ($($p[4]))" })" } }
    Get-ChildItem $runs -Filter 'ALERT-*.txt' -File -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name): $((Get-Content $_.FullName -Raw).Trim())" }
    exit 0
}
if ($Restart) {   # deploy a new rig-runner.ps1 at the next list boundary (never mid-batch): the loop re-spawns itself there
    foreach ($r in $(if ($Rig) { @($Rig) } else { @('5090', '4080') })) { Set-Content (Join-Path $rd "$r.restart") (Get-Date -Format s); "runner $r restarts at its next list boundary$(if (-not (PidAlive $r)) { ' (not running now: use -Start)' })" }
    exit 0
}
if ($Start) { $Ensure = $true; $Force = $true }
if ($Ensure) {
    foreach ($r in $(if ($Rig) { @($Rig) } else { @('5090', '4080') })) {
        if (PidAlive $r) { "runner $r running pid=$(Get-Content (Join-Path $rd "$r.pid") -Raw)"; continue }
        if (Test-Path (StopFlag $r)) {
            if (-not $Force) { "runner $r STOPPED since $((Get-Content (StopFlag $r) -Raw).Trim()): not started (rig-runner.ps1 -Start -Rig $r)"; continue }
            Remove-Item (StopFlag $r) -ErrorAction SilentlyContinue
        }
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Rig', $r) + $(if ($Fake) { @('-Fake') } else { @() })
        $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList $a
        "runner $r started pid=$($p.Id)"
    }
    exit 0
}
if (-not $Rig) { Get-Content $PSCommandPath -TotalCount 40; exit 2 }
if (-not $Resolve) {
    if (PidAlive $Rig) { "runner $Rig already running"; exit 0 }
    if ((Test-Path (StopFlag $Rig)) -and -not $Force) { "runner $Rig is STOPPED ($((Get-Content (StopFlag $Rig) -Raw).Trim())): rig-runner.ps1 -Start -Rig $Rig"; exit 0 }
    Set-Content (Join-Path $rd "$Rig.pid") $PID
}

# ---------------------------------------------------------------- helpers
$log = Join-Path $rd "$Rig.log"; $stateF = Join-Path $rd "$Rig.state"; $curF = Join-Path $rd "$Rig.cur"
$alertF = if ($Fake) { Join-Path $rd "ALERT-$Rig.txt" } else { Join-Path $runs "ALERT-$Rig.txt" }
$owner4 = 'rig4080'; $owner5 = 'runner-5090'
function Log([string]$m) { if ($Resolve) { Write-Host "LOG $m"; return }; $null = WriteShared $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m`r`n" -Append }
function State([string]$m) { $null = WriteShared $stateF "$((Get-Date).ToString('HH:mm')) $m`r`n" }
function Note([string]$who, [string]$m) {
    if ($Fake) { $who = "fake-$who" }
    Add-Content (Join-Path $runs "agents\$who.note-from-rig-runner") "$((Get-Date).ToString('MM-dd HH:mm')) rig-runner $Rig`: $m"
}
function Alert([string]$m) { Set-Content $alertF "ALERT $Rig $((Get-Date).ToString('HH:mm')) $m"; Log "ALERT $m" }
function ClearAlert { if (Test-Path $alertF) { Remove-Item $alertF -ErrorAction SilentlyContinue; Log 'alert cleared' } }
# sticky alert for setup-FAIL idling: NOT cleared when the next list starts (else the Stop hook never sees it); expires after 30 min
$fastF = Join-Path $(if ($Fake) { $rd } else { $runs }) "ALERT-$Rig-setup.txt"
function FastAlert([string]$m) { Set-Content $fastF "ALERT $Rig $((Get-Date).ToString('HH:mm')) $m"; Log "ALERT(setup) $m" }
$script:keep4080 = [bool]$Keep4080   # -Keep4080: handed over by a -Restart with the 4080 game kept up
# 4080 deferred sync (coordinator 2026-10-10: never overwrite a script a running batch executes): at a list start every take
# script is synced except those a still-running 4080 process (background analyses after GAMEDONE, anything else) uses:
# the repo files in the running command lines (C:\KAH\runner\procpaths.ps1) + every synced file they reference, transitively
# (basename; python "import x"/"from x"). Deferred files (runner\4080.deferred) sync at the next list start where nothing uses
# them. A new list that needs a deferred file runs on the 4080's old copy: runner\4080.oldcopy.<list> -> its result line.
function SyncCandidates {   # repo-relative path -> full path, the files rig4080/setup.sh copies
    $m = 'C:\KenshiModding'; $h = @{}
    $g = @("$m\tools\automation\rig-env.sh", "$m\tools\automation\review-pack.py", "$m\Kenshi-Automation-Harness\client\kah.py") +
         @(Get-ChildItem "$m\components\KenshiFP\animlab\*" -File -Include *.sh, *.py, *.txt -ErrorAction SilentlyContinue | ForEach-Object FullName) +
         @(Get-ChildItem "$m\components\KenshiFP\animlab\weapons\*" -File -Include *.list, *.json -ErrorAction SilentlyContinue | ForEach-Object FullName) +
         @(Get-ChildItem "$m\components\KenshiFP\tests\ingame\*" -File -Include *.sh, *.py -ErrorAction SilentlyContinue | ForEach-Object FullName) +
         @(Get-ChildItem "$m\Kenshi-Automation-Harness\tools\animlab\*.py" -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
    foreach ($f in $g) { if (Test-Path -LiteralPath $f -PathType Leaf) { $h[($f.Substring($m.Length + 1) -replace '\\', '/')] = $f } }
    $h
}
function UsedClosure([string]$text, [hashtable]$cand, [switch]$SeedsOnly) {   # synced files named in $text, plus everything they reference
    $seen = @{}; $todo = New-Object Collections.Queue
    foreach ($mm in [regex]::Matches($text, 'KenshiModding[\\/]+([^\s"''|;,)]+)')) { $r = $mm.Groups[1].Value -replace '\\', '/' -replace '/+', '/'; if ($cand.ContainsKey($r) -and -not $seen[$r]) { $seen[$r] = 1; $todo.Enqueue($r) } }
    if ($SeedsOnly) { return @($seen.Keys | Sort-Object) }
    $byBase = @{}; foreach ($k in $cand.Keys) { $b = Split-Path $k -Leaf; if (-not $byBase[$b]) { $byBase[$b] = @() }; $byBase[$b] += $k }
    while ($todo.Count) {
        $r = $todo.Dequeue(); $t = try { [IO.File]::ReadAllText($cand[$r]) } catch { '' }
        foreach ($b in $byBase.Keys) {
            $hit = $t.Contains($b) -and $t -match "(?<![\w.-])$([regex]::Escape($b))(?![\w-])"
            if (-not $hit -and $b -like '*.py') { $st = [regex]::Escape($b.Substring(0, $b.Length - 3)); $hit = $t -match "(?m)^\s*(import|from)\s+([\w.]+\s*,\s*)*$st\b" }
            if ($hit) { foreach ($k in $byBase[$b]) { if (-not $seen[$k]) { $seen[$k] = 1; $todo.Enqueue($k) } } }
        }
    }
    @($seen.Keys | Sort-Object)
}
function Sync4080([string]$name, [string]$listText) {
    $cand = SyncCandidates
    $cl = if ($Fake) { if (Test-Path "$rd\fake-procs.txt") { @(Get-Content "$rd\fake-procs.txt") } else { @() } } else { @(Ssh4Ps 'C:\KAH\runner\procpaths.ps1' @()) }
    if (-not $Fake -and -not ($cl -contains 'PROCPATHS-END')) { Log "4080 sync SKIPPED: 4080 process list unreadable ($(($cl | Select-Object -Last 1)); nothing overwritten, the 4080 keeps its current scripts"; return }
    $defer = @(UsedClosure ($cl -join "`n") $cand)
    $df = Join-Path $rd '4080.deferred'
    $prev = if (Test-Path $df) { @(Get-Content $df | Where-Object { $_ }) } else { @() }
    foreach ($x in $defer) { Log "4080 sync DEFERRED $x (used by a running 4080 process)" }
    foreach ($x in $prev) { if ($defer -notcontains $x) { Log "4080 sync $x synced now (was deferred)" } }
    [IO.File]::WriteAllText($df, (($defer -join "`n") + $(if ($defer.Count) { "`n" } else { '' })))
    $dfp = '/c/' + ($df.Substring(3) -replace '\\', '/')
    $so = & 'C:\Program Files\Git\bin\bash.exe' -lc "bash /c/KenshiModding/tools/automation/rig4080/setup.sh $(if ($Fake) { '--dry ' })--defer $dfp" 2>&1 | ForEach-Object { "$_" }
    foreach ($l in $so) { if ($l -match '^SCPFAIL') { Log "4080 sync: $l" } }
    Log "4080 sync: $(($so | Select-Object -Last 1))$(if ($Fake) { " copies=$(@($so | Where-Object { $_ -like 'COPY *' }).Count)" })"
    $old = @(UsedClosure $listText $cand | Where-Object { $defer -contains $_ })
    $of = Join-Path $rd "4080.oldcopy.$name"
    if ($old.Count) {
        $dir = @(UsedClosure $listText $cand -SeedsOnly | Where-Object { $defer -contains $_ } | ForEach-Object { Split-Path $_ -Leaf })
        Set-Content $of "$($old.Count) files ($(if ($dir.Count) { ($dir -join ',') + ' + ' })the files they use; full list in runner\4080.log)"; Log "4080 $name runs on the 4080's OLD copy of: $($old -join ', ') (in use by a running analysis)" }
    else { Remove-Item $of -ErrorAction SilentlyContinue }
}
# queue\running\ entries of this rig that no runner file (<rig>.cur / <rig>.tail.*) names and no live run-batch.sh runs:
# leftovers of a killed loop (2026-10-10). Filler copies are deleted, other lists go to failed\ (owner noted).
function CleanRunning {
    $refs = @(Get-ChildItem $rd -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$Rig.cur" -or $_.Name -like "$Rig.tail.*" } | ForEach-Object { (Get-Content $_.FullName -TotalCount 1) })
    $rb = $null
    foreach ($r in @(Get-ChildItem "$qd\running" -Filter "${Rig}__*" -File -ErrorAction SilentlyContinue)) {
        if ($refs -contains $r.FullName) { continue }
        $base = [IO.Path]::GetFileNameWithoutExtension(($r.Name -replace "^${Rig}__(filler__)?", ''))
        $outN = Header $r.FullName 'out'; if (-not $outN) { $outN = $base }
        if ($Rig -eq '5090' -and -not $Fake) {
            if ($null -eq $rb) { $rb = @(Wsl @('pgrep', '-af', 'run-batch.sh') | Where-Object { $_ -match '^\d+ .*run-batch\.sh' }) }
            if (@($rb | Where-Object { $_ -match [regex]::Escape("/$outN") }).Count) { continue }   # a live batch on it: leave it
        }
        $own = Header $r.FullName 'owner'; if (-not $own) { $own = 'coordinator' }
        if ($r.Name -like '*__filler__*') { Remove-Item -LiteralPath $r.FullName -ErrorAction SilentlyContinue; Log "STALE running\$($r.Name) (filler copy) removed"; continue }
        $nm = $r.Name -replace "^${Rig}__", ''; $dst = Join-Path "$qd\failed" $nm
        Move-Item -LiteralPath $r.FullName $dst -Force -ErrorAction SilentlyContinue
        Set-Content "$dst.result" "STALE $Rig $(Get-Date -Format s) running\ entry with no runner state and no live run-batch.sh (loop killed mid-start?)"
        Log "STALE running\$($r.Name) -> failed\"
        Note $own "list $nm sat in queue\running\ with no live batch (stale; moved to queue\failed\). Requeue it if it still needs to run."
    }
}
function Wsl([string[]]$a) { & wsl.exe -d $distro -u root --cd / -- @a 2>&1 | ForEach-Object { "$_" } }
function WslPath([string]$w) { '/mnt/' + $w.Substring(0, 1).ToLower() + ($w.Substring(2) -replace '\\', '/') }
function Ssh([string[]]$a) { & ssh.exe -n -o BatchMode=yes -o ConnectTimeout=10 4080 @a 2>&1 | ForEach-Object { "$_" } }
function Ssh4Ps([string]$file, [string[]]$a) { Ssh (@('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file) + $a) }
function Ssh4Bash([string[]]$a) { Ssh (@('C:\PROGRA~1\Git\bin\bash.exe', '-l') + $a) }
function Scp4([string[]]$src, [string]$dst) { & scp -q -o BatchMode=yes @src "4080:$dst" 2>&1 | ForEach-Object { "$_" }; $LASTEXITCODE -eq 0 }
function IdleReason {
    $f = Join-Path $runs "rig$Rig.idle"
    if ((Test-Path $f) -and (Get-Item $f).LastWriteTime -gt (Get-Date).AddMinutes(-60)) { return ((Get-Content $f -Raw).Trim()) }
    $null
}
function Header([string]$path, [string]$key) {
    $l = Get-Content $path | Where-Object { $_ -match "^\s*#\s*$key\s*:\s*(.+?)\s*$" } | Select-Object -First 1
    if ($l) { $null = $l -match "^\s*#\s*$key\s*:\s*(.+?)\s*$"; return $Matches[1] } $null
}
function Rows([string]$path) { @(Get-Content $path | Where-Object { $_ -notmatch '^\s*(#|$)' }) }
function StobeRows([string]$path) { @(Rows $path | Where-Object { ($_ -split '\|')[-1] -match 'STOBE-|tests/ingame/stobe|\.txt(\s|$)' }).Count -gt 0 }
# rows left out of the dry run: "# nodryrun: <row>[/<row>,...] <reason>" (several lines allowed; "SWA/T6 rows: ..." = SWA + T6)
function NoDryRows([string]$path) {
    @(Get-Content $path | Where-Object { $_ -match '^\s*#\s*nodryrun\s*:\s*(\S+)' } | ForEach-Object {
        $null = $_ -match '^\s*#\s*nodryrun\s*:\s*(\S+)'; $Matches[1].TrimEnd(':') -split '[/,]' | Where-Object { $_ } })
}
# FILLER (Shay 2026-10-10: rigs must never sit idle): queue\filler\ is a shared rotating regression backlog, used only when
# queue\<rig>\ and queue\any\ are empty (and preempted at the next row boundary once one is not: Preempt). A filler list is COPIED (never consumed) to
# running\<rig>__filler__<name>; rotation state runner\filler-rotation.tsv (name, last start, rig, benched until, why):
# least recently started first. Skipped: lists the other rig is running, benched lists (dryrun FAIL, fast setup FAIL, died:
# 3 h), lists whose "needs:" the installed build doesn't meet (a filler never installs a DLL: no restart, no downgrade).
$rotF = Join-Path $rd 'filler-rotation.tsv'
function RotRead { $h = @{}; if (Test-Path $rotF) { foreach ($l in Get-Content $rotF) { $p = @($l -split "`t"); if ($p.Count -ge 2 -and $p[0]) { while ($p.Count -lt 5) { $p += '' }; $h[$p[0]] = $p } } }; $h }
function RotSet([string]$name, [hashtable]$set) {   # both rig loops write it: retry on a sharing clash
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $h = RotRead; $p = if ($h[$name]) { [string[]]$h[$name] } else { [string[]]@($name, '', '', '', '') }
            foreach ($k in $set.Keys) { $p[[int]$k] = ([string]$set[$k]) -replace "[`t`r`n]", ' ' }
            $h[$name] = $p
            [IO.File]::WriteAllLines($rotF, [string[]]@($h.Keys | Sort-Object | ForEach-Object { $h[$_] -join "`t" })); return
        } catch { Start-Sleep -Milliseconds 300 }
    }
    Log "could not write $rotF"
}
function Bench([string]$name, [double]$hours, [string]$why) { RotSet $name @{ 3 = (Get-Date).AddHours($hours).ToString('s'); 4 = $why }; Log "FILLER bench $name ${hours}h: $why" }
$kfpDst5 = 'C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll'
$harn5 = 'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll'
$script:instCache = $null; $script:instAt = [datetime]::MinValue
function InstalledHashes {   # @{ K = KenshiFP sha8; H = harness sha8 } installed on this rig (4080: ssh, cached 3 min)
    if ($script:instCache -and ((Get-Date) - $script:instAt).TotalMinutes -lt 3) { return $script:instCache }
    $r = @{ K = '?'; H = '?' }
    if ($Fake) {   # fake rig: runner\fake\installed.txt "K=<sha8> H=<sha8>"
        $t = if (Test-Path "$rd\installed.txt") { Get-Content "$rd\installed.txt" -Raw } else { '' }
        if ($t -match 'K=(\w+)') { $r.K = $Matches[1].ToUpper() }; if ($t -match 'H=(\w+)') { $r.H = $Matches[1].ToUpper() }
    } elseif ($Rig -eq '5090') {
        $r.K = (Get-FileHash $kfpDst5).Hash.Substring(0, 8); $r.H = (Get-FileHash $harn5).Hash.Substring(0, 8)
    } else {
        $a = Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @() | Select-Object -Last 1; if ($a -match 'installed=(\w{8})') { $r.K = $Matches[1].ToUpper() }
        $b = Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @('-Harness') | Select-Object -Last 1; if ($b -match 'HARNESS (\w{8})') { $r.H = $Matches[1].ToUpper() }
    }
    $script:instCache = $r; $script:instAt = Get-Date; $r
}
function FillerUnmet([string]$path) {   # why the installed build doesn't meet the list's "needs:", or $null
    $need = Header $path 'needs'; if (-not $need) { return $null }
    $ih = InstalledHashes
    if ($need -match 'KenshiFP\s+(\w{8})\b' -and $ih.K -ne $Matches[1].ToUpper()) {
        $pin = $Matches[1].ToUpper(); $mi = if ($ih.K -ne '?') { Missing $pin $ih.K } else { $null }   # a filler never installs: the installed build must include the pinned one's patches
        if ($null -eq $mi -or $mi.Count) { return "needs KenshiFP $pin, installed $($ih.K)$(if ($mi.Count) { " (lacks $($mi -join ','))" })" }
    }
    if ($need -match 'Harness\s+(\w{8})\b' -and $ih.H -ne $Matches[1].ToUpper()) { return "needs Harness $($Matches[1]), installed $($ih.H)" }
    $null
}
$script:fillerSkips = @(); $script:skipNoted = @{}
function FillerLists {   # eligible filler lists for this rig, least recently started first
    $rot = RotRead; $now = Get-Date; $skips = @()
    $busy = @(Get-ChildItem "$qd\running" -File -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Name -match '__filler__(.+)$') { $Matches[1] } })
    $c = foreach ($f in @(Get-ChildItem "$qd\filler" -Filter *.list -File -ErrorAction SilentlyContinue)) {
        $want = Header $f.FullName 'rig'
        if ($want -and $want -ne $Rig) { continue }
        if ($Rig -eq '4080' -and (StobeRows $f.FullName)) { continue }
        if ($busy -contains $f.Name) { continue }
        $p = $rot[$f.Name]
        if ($p -and $p[3] -and ([datetime]$p[3]) -gt $now) { $skips += "$($f.Name) benched until $(([datetime]$p[3]).ToString('HH:mm')) ($($p[4]))"; continue }
        $u = FillerUnmet $f.FullName
        if (-not $u -and (CachedVerdict $f) -eq 'FAIL') { Bench $f.Name 3 'dry run FAIL'; Note $(if ($o = Header $f.FullName 'owner') { $o } else { 'coordinator' }) "filler $($f.Name) fails dryrun.sh: benched 3 h (runner\predry\ has the output). Fix the list."; $u = 'dry run FAIL (benched)' }
        if ($u) {
            $skips += "$($f.Name) $u"
            if (-not $script:skipNoted["$($f.Name)|$u"]) { $script:skipNoted["$($f.Name)|$u"] = 1; Log "FILLER skip $($f.Name): $u" }
            continue
        }
        $f
    }
    $script:fillerSkips = $skips
    @($c) | Sort-Object @{ e = { $p = $rot[$_.Name]; if ($p -and $p[1]) { [datetime]$p[1] } else { [datetime]::MinValue } } }, Name
}
function QueuedLists {   # every list this rig may take, FIFO order (own folder first, then any\, then filler\ if both empty)
    $real = @(RealLists); if ($real.Count) { return $real }
    FillerLists
}
function RealLists {
    foreach ($src in "$qd\$Rig", "$qd\any") {
        foreach ($f in @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if ($src -like '*\any') {
                $want = Header $f.FullName 'rig'
                if ($want -and $want -ne $Rig) { continue }
                if ($Rig -eq '4080' -and (StobeRows $f.FullName)) { continue }
            }
            $f
        }
    }
}
function NextList { QueuedLists | Select-Object -First 1 }
function Fail-List([string]$runPath, [string]$name, [string]$own, [string]$why, [string[]]$detail) {
    $dst = Join-Path "$qd\failed" $name
    Move-Item -LiteralPath $runPath $dst -Force -ErrorAction SilentlyContinue
    Set-Content "$dst.result" (@("FAILED $Rig $(Get-Date -Format s) $why") + $detail)
    Log "FAILED $name : $why"
    if ((Split-Path $runPath -Leaf) -like '*__filler__*') { Bench $name 3 $why }
    Note $own "list $name NOT run ($why); details $dst.result. Fix it and put it back into queue\$Rig\ (or any\)."
}
# ---------------------------------------------------------------- staged builds (2026-10-10: "# needs: KenshiFP <sha>" failed
# at install twice because kfp-pipeline had replaced that sha). "# needs: KenshiFP latest" = the newest staged build,
# resolved at the batch boundary. A pinned sha that is gone is served by the newest staged build if that build's patches
# line includes every patch of the pinned one (else by the installed build if it does), with a log line; only otherwise
# the list fails. The pipeline deletes superseded manifests, so the runner remembers sha -> patches of every manifest it
# sees in runner\staged-history.tsv (fallback: the "PIPELINE PASS <sha> patches=" lines in /root/kfp-pipeline/*/pipeline.log).
$stDir = if ($Fake) { Join-Path $rd 'staged' } else { Join-Path $runs 'staged' }
$histF = Join-Path $rd 'staged-history.tsv'; $script:noPatches = @{}
function HistRead { $h = @{}; foreach ($l in @((ReadShared $histF) -split "`r?`n")) { $p = $l -split "`t"; if ($p.Count -ge 2 -and $p[0]) { $h[$p[0]] = $p[1] } }; $h }
function ManifestPatches([string]$path) {   # "patches a,b,c" line of a KenshiFP-*.txt manifest ('' = base build), $null if none
    $t = ReadShared $path; if ($null -eq $t) { return $null }
    $l = @($t -split "`r?`n" | Where-Object { $_ -match '^patches(\s|$)' })[0]; if ($null -eq $l) { return $null }
    ($l -replace '^patches\s*', '').Trim()
}
function StagedRecord {   # remember the patches of every staged manifest (cheap: a few small files per tick)
    $h = HistRead; $add = @()
    foreach ($m in @(Get-ChildItem $stDir -Filter 'KenshiFP-*.txt' -File -ErrorAction SilentlyContinue)) {
        $sha = if ($m.Name -eq 'KenshiFP-latest.txt') { $l1 = (ReadShared $m.FullName); if ($l1 -match '^KenshiFP (\w{8})') { $Matches[1].ToUpper() } else { $null } } elseif ($m.BaseName -match '^KenshiFP-(\w{8})$') { $Matches[1].ToUpper() } else { $null }
        if (-not $sha -or $h.ContainsKey($sha)) { continue }
        $pp = ManifestPatches $m.FullName; if ($null -eq $pp) { continue }
        $h[$sha] = $pp; $add += "$sha`t$pp`t$(Get-Date -Format s)"
    }
    if ($add.Count) { $null = WriteShared $histF (($add -join "`r`n") + "`r`n") -Append; foreach ($a in $add) { Log "staged-history + $(($a -split "`t")[0])" } }
}
function PatchesOf([string]$sha) {   # patch list of a build (string, '' = base), $null if unknown
    $sha = $sha.ToUpper(); $m = Join-Path $stDir "KenshiFP-$sha.txt"
    if (Test-Path $m) { $pp = ManifestPatches $m; if ($null -ne $pp) { return $pp } }
    $h = HistRead; if ($h.ContainsKey($sha)) { return $h[$sha] }
    if ($Fake -or $script:noPatches[$sha]) { return $null }
    $script:noPatches[$sha] = 1   # one pipeline-log lookup per unknown sha per loop
    $g = @(Wsl @('bash', '-c', "grep -ho 'PIPELINE PASS $sha patches=[^ ]*' /root/kfp-pipeline/*/pipeline.log 2>/dev/null | tail -1"))
    if ($g.Count -and $g[-1] -match "PIPELINE PASS $sha patches=(\S*)") { $pp = $Matches[1]; $null = WriteShared $histF "$sha`t$pp`t$(Get-Date -Format s) (pipeline.log)`r`n" -Append; return $pp }
    $null
}
function LatestStaged {   # sha8 of THE staged build (KenshiFP-latest.txt line 1 if its DLL is there, else the newest DLL)
    $l = ReadShared (Join-Path $stDir 'KenshiFP-latest.txt')
    if ($l -match '^KenshiFP (\w{8})' -and (Test-Path (Join-Path $stDir "KenshiFP-$($Matches[1].ToUpper()).dll"))) { return $Matches[1].ToUpper() }
    $f = Get-ChildItem (Join-Path $stDir 'KenshiFP-*.dll') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.BaseName.Substring(9).ToUpper() } $null
}
function Missing([string]$want, [string]$have) {   # patches of $want that $have lacks ($null = $have unknown)
    $hp = PatchesOf $have; $wp = PatchesOf $want; if ($null -eq $hp -or $null -eq $wp) { return $null }
    $hs = @($hp -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $m = @(($wp -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $hs -notcontains $_ })
    , $m   # keep an empty array an array (else PowerShell returns $null = "unknown")
}
# pinned sha8 -> the build to use: @{ sha = <sha8 or $null = keep the installed one>; why = <log text> } or @{ fail = <reason> }
function ResolvePinned([string]$pin, [string]$installed) {
    $pin = $pin.ToUpper()
    if ($installed -eq $pin) { return @{ sha = $null; why = "KenshiFP $pin is installed" } }
    if (Test-Path (Join-Path $stDir "KenshiFP-$pin.dll")) { return @{ sha = $pin; why = "KenshiFP $pin staged" } }
    if ($null -eq (PatchesOf $pin)) { return @{ fail = "needs KenshiFP ${pin}: no longer staged and its patch list is unknown (no manifest, not in runner\staged-history.tsv / pipeline logs); use '# needs: KenshiFP latest'" } }
    $lat = LatestStaged
    if ($lat) {
        $miss = Missing $pin $lat
        if ($null -ne $miss -and -not $miss.Count) { return @{ sha = $(if ($lat -eq $installed) { $null } else { $lat }); why = "needs KenshiFP $pin, which is no longer staged: the newest staged build $lat includes all its patches -> $(if ($lat -eq $installed) { 'already installed' } else { "installing $lat" })" } }
    }
    if ($installed -and $installed -ne '?') {
        $mi = Missing $pin $installed
        if ($null -ne $mi -and -not $mi.Count) { return @{ sha = $null; why = "needs KenshiFP $pin, which is no longer staged: the installed build $installed includes all its patches -> runs on it" } }
    }
    @{ fail = "needs KenshiFP ${pin}: no longer staged, and neither the newest staged build ($(if ($lat) { "$lat lacks: $((Missing $pin $lat) -join ',')" } else { 'none' })) nor the installed $installed includes all its patches" }
}
# installed vs staged KenshiFP; returns $null (nothing to do), the sha8 to install, or 'FAIL' ($script:instWhy = reason)
function StagedWanted([string]$need) {
    $sd = if ($Rig -eq '5090') { "$runs\staged" } else { $null }
    $script:instWhy = ''
    if ($need -and $need -notmatch '^(staged-)?latest$') {
        $script:instCache = $null; $ik = (InstalledHashes).K
        $r = ResolvePinned $need $ik
        if ($r.fail) { $script:instWhy = $r.fail; return 'FAIL' }
        if ($r.why -notmatch ' is installed$| staged$') { Log $r.why }
        return $r.sha
    }
    if ($Fake) { $l = LatestStaged; if ($l -and $l -ne (InstalledHashes).K -and $need) { return $l }; return $null }
    if ($Rig -eq '5090') {
        $h = LatestStaged; if (-not $h) { return $null }   # THE build (KenshiFP-latest.txt), even if an older one is kept
        $f = Get-Item "$sd\KenshiFP-$h.dll"
        $dst = $kfpDst5
        if ((Get-FileHash $dst).Hash.Substring(0, 8) -eq $h) { return $null }
        if ($need -or $f.LastWriteTime -gt (Get-Item $dst).LastWriteTime) { return $h }
        return $null
    }
    # 4080: newest staged there vs installed (one ssh call)
    $r = Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @() | Select-Object -Last 1
    if ($r -match '^NEWEST (\w+) newer=(\d)') { if ($need -or $Matches[2] -eq '1') { return $Matches[1] } }
    $null
}

# ---------------------------------------------------------------- background pre-dry-run (2026-10-10: the 4080 sat with
# Kenshi closed 2.5 min while the next list dry-ran after DONE). While a batch runs, the next queued list for this rig is
# dry-run in the background; Start-Batch uses the cached verdict. Key = rig + the dry-run list text + name/size/mtime of
# the dry-run tool, the take scripts/libs, the lab tools and every file a row names: any change = stale = run again.
$pdd = Join-Path $rd 'predry'; New-Item -ItemType Directory -Force $pdd | Out-Null
function DryListText([string]$path) {
    $cr = if ($Rig -eq '5090') { '/mnt/c' } else { '/c' }
    $txt = (Get-Content $path) -replace '\{CR\}', $cr
    $skip = NoDryRows $path
    $drl = $txt | Where-Object { $r = $_; if ($r -match '^\s*(#|$)') { return $true }; -not ($skip -contains (($r -split '\|')[0].Trim())) }
    ($drl -join "`n") + "`n"
}
function DryKey([string]$path) {
    $t = DryListText $path
    $files = @(Get-ChildItem "$auto\dryrun" -Recurse -File -Include *.sh, *.py, *.json -ErrorAction SilentlyContinue) +
             @(Get-ChildItem "$auto\dryrun.sh", "$auto\run-batch.sh", "$auto\rig-env.sh" -ErrorAction SilentlyContinue) +
             @(Get-ChildItem 'C:\KenshiModding\components\KenshiFP\tests\ingame' -File -Filter *.sh -ErrorAction SilentlyContinue) +
             @(Get-ChildItem 'C:\KenshiModding\components\KenshiFP\animlab' -File -Include *.py, *.sh -Recurse -Depth 0 -ErrorAction SilentlyContinue) +
             @(Get-ChildItem 'C:\KenshiModding\Kenshi-Automation-Harness\tools\animlab' -File -Filter *.py -ErrorAction SilentlyContinue)
    foreach ($m in [regex]::Matches($t, '(?:/mnt/c|/c)(/[^\s''"|;]+)')) {
        $w = 'C:' + ($m.Groups[1].Value -replace '/', '\'); if (Test-Path -LiteralPath $w -PathType Leaf) { $files += Get-Item -LiteralPath $w }
    }
    $sb = New-Object Text.StringBuilder; $null = $sb.Append("$Rig`n$t")
    foreach ($f in ($files | Sort-Object FullName -Unique)) { $null = $sb.Append("$($f.FullName)|$($f.Length)|$($f.LastWriteTimeUtc.Ticks)`n") }
    $h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    $Rig + '-' + (($h[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
}
function PreDryRunning([string]$key) { $p = Join-Path $pdd "$key.pid"; (Test-Path $p) -and -not (Test-Path (Join-Path $pdd "$key.rc")) -and [bool](Get-Process -Id ([int](Get-Content $p -Raw)) -ErrorAction SilentlyContinue) }
function PreDryStart([string]$path, [string]$key) {
    $d = Join-Path $pdd $key; New-Item -ItemType Directory -Force $d | Out-Null
    [IO.File]::WriteAllText((Join-Path $d 'list.dryrun.txt'), (DryListText $path))
    $dw = WslPath $d; $pw = WslPath $pdd
    Remove-Item (Join-Path $pdd "$key.rc"), (Join-Path $pdd "$key.out") -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText((Join-Path $d 'run.sh'), "#!/bin/bash`ncd /`nnice -n 15 timeout 1200 bash $(WslPath $auto)/dryrun.sh --rig $Rig --out $dw/dryrun $dw/list.dryrun.txt > $pw/$key.out.tmp 2>&1`nrc=`$?`nmv $pw/$key.out.tmp $pw/$key.out; echo `$rc > $pw/$key.rc`n")
    if ($Fake) { $null = Wsl @('bash', "$dw/run.sh"); return }
    $p = Start-Process wsl.exe -WindowStyle Hidden -PassThru -ArgumentList @('-d', $distro, '-u', 'root', '--cd', '/', '--', 'bash', "$dw/run.sh")
    Set-Content (Join-Path $pdd "$key.pid") $p.Id
    Log "predry start $(Split-Path $path -Leaf) key=$key"
}
function PreDryWait([string]$key, [int]$sec) {
    $t0 = Get-Date
    while (-not (Test-Path (Join-Path $pdd "$key.rc"))) {
        if (((Get-Date) - $t0).TotalSeconds -ge $sec) { return $false }
        if (-not (PreDryRunning $key) -and -not (Test-Path (Join-Path $pdd "$key.rc"))) { Start-Sleep 2; if (-not (Test-Path (Join-Path $pdd "$key.rc"))) { return $false } }
        Start-Sleep -Seconds 2
    }
    $true
}
function CachedVerdict($f) {   # PASS | FAIL | PENDING | $null for a queued list file
    $key = DryKey $f.FullName
    $rc = Join-Path $pdd "$key.rc"
    if (Test-Path $rc) {
        $sum = @(Get-Content (Join-Path $pdd "$key.out") -ErrorAction SilentlyContinue | Where-Object { $_ -like 'DRYRUN-SUMMARY*' })[-1]
        if ((Get-Content $rc -Raw).Trim() -eq '0' -and $sum -cmatch '^DRYRUN-SUMMARY pass=\d+ fail=0 ') { return 'PASS' } else { return 'FAIL' }
    }
    if (PreDryRunning $key) { return 'PENDING' }
    $null
}
# which list to start at a boundary (2026-10-10: the 5090 sat 5 min while the FIFO head dry-ran and then FAILED):
# a list whose cached verdict is FAIL first (fails at once, owner noted), else the first cached PASS, else the FIFO head
function PickList {
    $ls = @(QueuedLists); if (-not $ls.Count) { return $null }
    if ($ls.Count -eq 1) { return $ls[0] }
    if ($ls[0].DirectoryName -like '*\filler') { return $ls[0] }   # filler: strict rotation (a cached-PASS preference starved the rest)
    $v = @{}; foreach ($l in $ls) { $v[$l.Name] = CachedVerdict $l }
    $x = $ls | Where-Object { $v[$_.Name] -eq 'FAIL' } | Select-Object -First 1; if ($x) { return $x }
    $x = $ls | Where-Object { $v[$_.Name] -eq 'PASS' } | Select-Object -First 1; if ($x) { if ($x.Name -ne $ls[0].Name -and $script:lastPick -ne $x.Name) { $script:lastPick = $x.Name; Log "pick $($x.Name) (dry run PASS cached) before $($ls[0].Name) ($(if ($v[$ls[0].Name]) { $v[$ls[0].Name] } else { 'not dry-run yet' }))" }; return $x }
    $ls[0]
}
function PreDryNext {
    # one background dry run per rig at a time: the first queued list (FIFO) whose verdict is not cached yet
    if (@(Get-ChildItem $pdd -Filter "$Rig-*.pid" -File -ErrorAction SilentlyContinue | Where-Object { PreDryRunning $_.BaseName }).Count) { return }
    foreach ($f in @(@(RealLists) + @(FillerLists))) {   # filler too: its first pick then starts on a cached verdict
        $key = DryKey $f.FullName
        if (Test-Path (Join-Path $pdd "$key.rc")) { continue }   # PASS or FAIL cached for this exact state
        PreDryStart $f.FullName $key; break
    }
    Get-ChildItem $pdd -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-12) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- start a batch
function Start-Batch($f) {
    $name = $f.Name; $filler = $f.DirectoryName -like '*\filler'
    $run = Join-Path "$qd\running" "${Rig}__$(if ($filler) { 'filler__' })$name"
    if ($filler) {   # copy, never consume: the backlog stays whole; rotation state records the start
        if (Test-Path $run) { Log "could not take filler $name (already running here)"; return $false }
        Copy-Item -LiteralPath $f.FullName $run; RotSet $name @{ 1 = (Get-Date).ToString('s'); 2 = $Rig }
    } else { try { Move-Item -LiteralPath $f.FullName $run -ErrorAction Stop } catch { Log "could not take $name (another runner?)"; return $false } }
    $own = Header $run 'owner'; if (-not $own) { $own = 'coordinator' }
    $outN = Header $run 'out'; if (-not $outN) { $outN = "$($f.BaseName)-$(Get-Date -Format 'MMdd-HHmm')" }
    if ($filler) { if (Header $run 'out') { $outN = "$outN-$(Get-Date -Format 'MMdd-HHmm')" }; Log "FILLER $name (queue\$Rig\ and any\ empty) owner=$own" }
    $outN = $outN -replace '[^A-Za-z0-9_.-]', '_'
    $launch = Header $run 'launch'
    if (-not $launch) { $s = (((Rows $run | Select-Object -First 1) -split '\|')[1]); if ($s) { $launch = $s.Trim() } }
    if ($launch -eq 'home') { $launch = 'auto-home' }
    if (-not $Fake -and (-not $launch -or $launch -eq '-')) { Fail-List $run $name $own 'no save to launch: add "# launch: <save>" or a save in the first row' @(); return $true }
    $cr = if ($Rig -eq '5090') { '/mnt/c' } else { '/c' }
    $outW = Join-Path $(if ($Fake) { $rd } else { $runs }) $outN
    $i = 2; while ((Test-Path $outW) -and $Rig -eq '5090') { $outW = Join-Path (Split-Path $outW) "$outN-$i"; $i++ }
    $outP = if ($Rig -eq '5090' -or $Fake) { WslPath $outW } else { "/c/KenshiTestRuns/$outN" }   # path the batch sees
    $tmp = if ($Rig -eq '5090' -or $Fake) { $outW } else { Join-Path $rd "4080-$outN" }        # local copy of out files
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $txt = (Get-Content $run) -replace '\{CR\}', $cr
    [IO.File]::WriteAllText((Join-Path $tmp 'list.txt'), (($txt -join "`n") + "`n"))
    $skip = NoDryRows $run
    $drl = $txt | Where-Object { $r = $_; if ($r -match '^\s*(#|$)') { return $true }; -not ($skip -contains (($r -split '\|')[0].Trim())) }
    [IO.File]::WriteAllText((Join-Path $tmp 'list.dryrun.txt'), (($drl -join "`n") + "`n"))
    Set-Content $curF @($run, $outW, $outP, $own, (Get-Date -Format s), $name, $tmp)
    State "starting $name -> $outW (owner $own)"; Log "START $name owner=$own out=$outW launch=$launch"
    ClearAlert

    # dry run (fake game): the verdict cached by the background pre-dry-run while the previous batch ran, else run it now
    $key = DryKey $run
    $cached = Test-Path (Join-Path $pdd "$key.rc")
    if (-not $cached) { if (-not (PreDryRunning $key)) { PreDryStart $run $key }; $null = PreDryWait $key 1200 }
    $dr = if (Test-Path (Join-Path $pdd "$key.out")) { @(Get-Content (Join-Path $pdd "$key.out")) } else { @() }
    $drc = if (Test-Path (Join-Path $pdd "$key.rc")) { [int]((Get-Content (Join-Path $pdd "$key.rc") -Raw).Trim()) } else { 124 }
    $sum = ($dr | Where-Object { $_ -like 'DRYRUN-SUMMARY*' } | Select-Object -Last 1)
    Log "dryrun $name $(if ($cached) { '(cached, pre-run in the background)' } else { '(now)' }) key=$key rc=$drc : $sum"
    # a FAIL stays cached: the key changes with the list or any script it runs, so the same state would fail again
    if ($drc -ne 0 -or $sum -cnotmatch '^DRYRUN-SUMMARY pass=\d+ fail=0 ') {   # dryrun.sh exits 1 on any FAIL row
        Fail-List $run $name $own "dryrun failed: $sum" @($dr | Where-Object { $_ -match '^DRYRUN .* FAIL' }); Remove-Item $curF; return $true
    }
    if ($Fake) {   # fake batch: the dryrun result is the batch result
        if ($Rig -eq '4080') { Sync4080 $name (($txt -join "`n")) }   # deferred-sync planning against runner\fake\fake-procs.txt (setup.sh --dry)
        $res = @($dr | Where-Object { $_ -like 'DRYRUN *' } | ForEach-Object { $_ -replace '^DRYRUN (\S+) (PASS|FAIL|SKIP)', 'RESULT $1 $2' })
        $fsec = Header $run 'fakesec'   # "# fakesec: <n>": the fake batch takes n s (first RESULT at once, the rest at the end; PREEMPT ends it)
        if ($fsec -match '^\d+$') {
            Set-Content (Join-Path $outW 'SUMMARY.txt') (@("BATCH START $(Get-Date -Format 'yyyy-MM-dd HH:mm') list=$name (fake, $fsec s)") + @($res | Select-Object -First 1))
            Set-Content (Join-Path $outW 'fake.sec') @($fsec, (Get-Date -Format s)); Set-Content (Join-Path $outW 'fake.rest') @($res | Select-Object -Skip 1)
            State "running $name -> $outW (owner $own, fake)"; Note $own "started $name (fake, $fsec s) out=$outW"; return $true
        }
        Set-Content (Join-Path $outW 'SUMMARY.txt') (@("BATCH START $(Get-Date -Format 'yyyy-MM-dd HH:mm') list=$name (fake)") + $res + "BATCH END $(Get-Date -Format 'yyyy-MM-dd HH:mm') (fake)")
        New-Item -ItemType File (Join-Path $outW 'DONE') -Force | Out-Null
        Note $own "started $name (fake) out=$outW"; return $true
    }

    # stop Kenshi, install the wanted staged KenshiFP, check the harness
    $need = Header $run 'needs'
    $needK = if ($need -match 'KenshiFP\s+(\S+)') { $Matches[1].TrimEnd(',', ';') } elseif ($need -match '(staged-)?latest') { 'latest' } else { $null }
    $needH = if ($need -match 'Harness\s+(\w{8})') { $Matches[1].ToUpper() } else { $null }
    $inst = if ($filler) { $null } else { StagedWanted $needK }   # filler: runs on the installed build (needs checked at pick)
    if ($inst -eq 'FAIL') { Fail-List $run $name $own $script:instWhy @(); Remove-Item $curF; return $true }
    if ($Rig -eq '5090') {
        $env:KAH_OWNER = $owner5
        $lk = Join-Path $runs 'game.lock'
        if (Test-Path $lk) { $h = (Get-Content $lk -TotalCount 1).Trim(); if ($h -ne $owner5) { Log "lock taken over from $h"; Note $h "the 5090 was idle >= $IdleMin min: rig-runner took the game lock over (now $owner5). Queue your next batches as list files in queue\5090\ instead of launching yourself." } }
        Set-Content $lk @($owner5, (Get-Date -Format s)) -Encoding utf8
        # no relaunch gap (2026-10-10): the previous batch leaves Kenshi up (no --stop); stop it only for a DLL install,
        # else run-batch.sh --reuse loads the save in place
        $hd = 'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll'
        $hInst = $needH -and (Get-FileHash $hd).Hash.Substring(0, 8) -ne $needH
        if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) {
            if ($inst -or $hInst) { Log "stop Kenshi for the install (KenshiFP $inst$(if ($hInst) { ", Harness $needH" }))"; & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-ctl.ps1" stop | Out-Null }
            else { Log "REUSE $name : Kenshi stays up, $launch loads in place (no DLL install needed)" }
        }
        if ($inst) {
            $o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\install-dll.ps1" KenshiFP -Staged -Hash $inst 2>&1 | ForEach-Object { "$_" }
            Log "install KenshiFP $inst : $($o -join ' / ')"
            if ($LASTEXITCODE -ne 0 -or -not ($o -match 'installed')) { Fail-List $run $name $own "KenshiFP $inst install failed" $o; Remove-Item $curF; return $true }
        }
        if ($needH) {
            $hd = 'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\AutomationHarness.dll'
            if ((Get-FileHash $hd).Hash.Substring(0, 8) -ne $needH) {
                $o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\install-dll.ps1" Harness 2>&1 | ForEach-Object { "$_" }
                if ((Get-FileHash $hd).Hash.Substring(0, 8) -ne $needH) { Fail-List $run $name $own "needs Harness $needH, installed $((Get-FileHash $hd).Hash.Substring(0, 8)) (build out has another hash)" $o; Remove-Item $curF; return $true }
                Log "install Harness $needH"
            }
        }
        Copy-Item "$auto\run-batch.sh" (Join-Path $outW '.run-batch.sh') -Force
        $st = "#!/bin/bash`nexport KAH_OWNER=$owner5 WSLENV=KAH_OWNER`ncd /`nsetsid nohup bash $outP/.run-batch.sh --launch $launch --reuse --no-dryrun 'rig-runner dry-ran the list' $outP/list.txt $outP >/dev/null 2>&1 </dev/null &`nsleep 5`n"
        [IO.File]::WriteAllText((Join-Path $outW '.start.sh'), $st)
        Set-Content (Join-Path $runs 'inflight\runner-5090') $outP
        Wsl @('bash', "$outP/.start.sh") | Out-Null
    } else {
        $lk = (Ssh4Ps 'C:\KAH\ctl.ps1' @('lock') | Select-Object -First 1)
        if ($lk -and $lk -ne 'free' -and $lk.Trim() -ne $owner4) { Fail-List $run $name $own "4080 lock held by $lk" @(); Remove-Item $curF; return $true }
        # no relaunch gap (2026-10-10): the previous list left Kenshi up for this one (keep4080): run-batch.sh --reuse loads
        # the save in place, unless a DLL must be installed (stop + launch as before)
        $reuse = $false
        $k = Ssh @('tasklist', '/nh')
        if (($k -join ' ') -match 'kenshi_x64') {
            $hOk = (-not $needH) -or ((Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @('-Harness') | Select-Object -Last 1) -match $needH)
            if ($script:keep4080 -and -not $inst -and $hOk) { $reuse = $true; Log "REUSE $name : 4080 Kenshi stays up, $launch loads in place (no DLL install needed)" }
            else { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null }
        }
        $script:keep4080 = $false
        if ($inst) {
            $o = Ssh4Ps 'C:\KAH\inst-staged.ps1' @('-Hash', $inst); Log "4080 install KenshiFP $inst : $($o -join ' / ')"
            if (-not ($o -match 'installed')) { Fail-List $run $name $own "4080 KenshiFP $inst install failed" $o; Remove-Item $curF; return $true }
        }
        if ($needH) {
            $hh = (Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @('-InstallHarness', $needH) | Select-Object -Last 1); Log "4080 harness (need $needH, installs C:\KAH\staged\AutomationHarness-$needH.dll if present): $hh"
            if ($hh -notmatch $needH) { Fail-List $run $name $own "4080 needs Harness $needH, installed $hh" @(); Remove-Item $curF; return $true }
        }
        # take scripts + lab modules on the 4080 = this tree (rig4080/setup.sh): without it the 4080 ran stale scripts
        # (zsfist4080 fists lab: "No module named recfmt", 2026-10-10); files a running analysis uses are deferred (Sync4080)
        Sync4080 $name (($txt -join "`n"))
        $null = Ssh @('mkdir', "C:\KenshiTestRuns\$outN")
        Copy-Item "$auto\run-batch.sh" (Join-Path $tmp '.run-batch.sh') -Force
        $ok = Scp4 @((Join-Path $tmp 'list.txt'), (Join-Path $tmp '.run-batch.sh')) "C:/KenshiTestRuns/$outN/"
        $ok = $ok -and (Scp4 @("$auto\rig-runner-probe.sh", "$auto\batch-excerpts.sh", "$auto\batch-health.sh", "$auto\rig-env.sh") 'C:/KenshiModding/tools/automation/')
        if (-not $ok) { Fail-List $run $name $own '4080 copy (scp) failed' @(); Remove-Item $curF; return $true }
        if (-not $reuse) {
            $o = Ssh4Ps 'C:\KAH\kcfg.ps1' @('test'); Log "4080 kcfg: $($o -join ' / ')"
            $o = Ssh4Ps 'C:\KAH\ctl.ps1' @('launch', '-Save', $launch, '-Owner', $owner4); Log "4080 launch $launch : $(($o | Select-Object -Last 3) -join ' / ')"
        }
        $o = Ssh4Bash @('/c/KAH/bin/stobe-auto', 'input_isolation', 'on'); Log "4080 isolation: $($o -join ' ')"
        $rl = if ($reuse) { "--launch $launch --reuse " } else { '' }
        Set-Content (Join-Path $runs 'inflight\4080-runner') "4080:C:\KenshiTestRuns\$outN"
        # itrun -Cmd must be one token (ssh joins the args with spaces): a start script in the out dir
        [IO.File]::WriteAllText((Join-Path $tmp '.start.sh'), "#!/bin/bash`nexport KAH_OWNER=$owner4`nexec bash $outP/.run-batch.sh $rl--no-dryrun 'rig-runner dry-ran the list' $outP/list.txt $outP`n")
        $null = Scp4 @((Join-Path $tmp '.start.sh')) "C:/KenshiTestRuns/$outN/"
        $o = Ssh4Ps 'C:\KAH\itrun.ps1' @('-Log', "C:\KenshiTestRuns\$outN.itrun.out", '-Cmd', "$outP/.start.sh")
        Log "4080 itrun: $($o -join ' ')"
    }
    State "running $name -> $outW (owner $own)"
    Note $own "started $name on ${Rig}: out=$(if ($Rig -eq '4080') { "4080:C:\KenshiTestRuns\$outN" } else { $outW }) (launch $launch$(if ($inst) { ", KenshiFP $inst installed" }))."
    $true
}

# ---------------------------------------------------------------- finish / probe
function Probe([string]$outP, [string]$act = '') {
    $a = @($outP) + $(if ($act) { @($act) } else { @() })
    $r = if ($Rig -eq '5090') { Wsl (@('bash', "$(WslPath $auto)/rig-runner-probe.sh") + $a) } else { Ssh4Bash (@('/c/KenshiModding/tools/automation/rig-runner-probe.sh') + $a) }
    if ($act) { return ($r -join ' ') }
    $l = $r | Where-Object { $_ -like 'PROBE *' } | Select-Object -Last 1
    if (-not $l) { return $null }
    $h = @{}; foreach ($kv in ($l.Substring(6) -split ' ')) { $p = $kv -split '=', 2; if ($p.Count -eq 2) { $h[$p[0]] = $p[1] } }
    $h
}
function FakeProbe([string[]]$c) {   # -Fake: a "# fakesec:" batch runs for n s and honours PREEMPT like run-batch.sh
    $o = $c[1]; $fs = Join-Path $o 'fake.sec'
    if ((Test-Path (Join-Path $o 'DONE')) -or -not (Test-Path $fs)) { return @{ done = '1' } }
    $sec, $t0 = @(Get-Content $fs); $S = Join-Path $o 'SUMMARY.txt'
    if (Test-Path (Join-Path $o 'PREEMPT')) {
        Add-Content $S @("BATCH PREEMPTED $(Get-Date -Format 'yyyy-MM-dd HH:mm') before row 2: $((Get-Content (Join-Path $o 'PREEMPT') -TotalCount 1))", "NOTE preempted: not run: $((@(Get-Content (Join-Path $o 'fake.rest')) | ForEach-Object { ($_ -split ' ')[1] }) -join ' ')", "BATCH END $(Get-Date -Format 'yyyy-MM-dd HH:mm') (fake)")
        New-Item -ItemType File (Join-Path $o 'DONE') -Force | Out-Null; return @{ done = '1' }
    }
    if (((Get-Date) - [datetime]$t0).TotalSeconds -ge [int]$sec) {
        Add-Content $S (@(Get-Content (Join-Path $o 'fake.rest')) + "BATCH END $(Get-Date -Format 'yyyy-MM-dd HH:mm') (fake)"); New-Item -ItemType File (Join-Path $o 'DONE') -Force | Out-Null; return @{ done = '1' }
    }
    @{ done = '0'; gamedone = '0'; alive = '1'; started = '1'; kenshi = '1'; launched = '1'; phase = 'world'; gh = "$((Get-Date).Ticks)"; step = 'fake'; age = '0'; bpid = '-' }
}
# FILLER PREEMPTION (Shay 2026-10-10: a 40-min filler held the turret+sword refilms until the coordinator killed it by hand):
# a real list in queue\<rig>\ or any\ while a filler runs -> <out>\PREEMPT; run-batch.sh ends the batch at the next row
# boundary (the running row finishes its RESULT line; "BATCH PREEMPTED" + the rows not run in SUMMARY.txt; background
# analyses still collected), touches GAMEDONE, and the runner starts the real list at once on the running Kenshi (--reuse).
$script:preempted = @{}
function Preempt([string[]]$c, [string]$by) {
    $name = $c[5]; if ($script:preempted[$name]) { return }; $script:preempted[$name] = 1
    $snap = if ($Rig -eq '4080' -and -not $Fake) { Join-Path $c[6] '.run-batch.sh' } else { Join-Path $c[1] '.run-batch.sh' }
    if (-not $Fake -and -not (Select-String -LiteralPath $snap -Pattern 'PREEMPT' -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
        Log "PREEMPT $name for $by not possible: its run-batch.sh snapshot predates PREEMPT support (runs to its end)"; return }
    $txt = "$by $(Get-Date -Format s)"
    if ($Rig -eq '4080' -and -not $Fake) {
        $lf = Join-Path $c[6] 'PREEMPT'; Set-Content $lf $txt
        if (-not (Scp4 @($lf) "C:/KenshiTestRuns/$(Split-Path $c[2] -Leaf)/")) { $script:preempted.Remove($name); Log "PREEMPT ${name}: scp to the 4080 failed (retry next tick)"; return }
    } else { Set-Content (Join-Path $c[1] 'PREEMPT') $txt }
    Log "PREEMPT filler ${name}: $by is queued; the batch ends after its current row"
    State "running $name (filler, preempted by ${by}: ends after the current row)"
}
function Finish-Batch([string[]]$c, [string]$how, [string]$file = $curF, [switch]$Tail, [string]$Why = '') {
    $run, $outW, $outP, $own, $t0, $name, $tmp = $c
    if ($how -ne 'DONE' -and -not $Tail -and -not $Fake) {
        # a dead/lost batch gives the rig back: marker, lock (only if ours), and a game it left open (DIED only, not LOST)
        if ($Rig -eq '5090') {
            Remove-Item (Join-Path $runs 'inflight\runner-5090') -ErrorAction SilentlyContinue
            $lk = Join-Path $runs 'game.lock'
            if ((Test-Path $lk) -and (Get-Content $lk -TotalCount 1).Trim() -eq $owner5) {
                if ($how -eq 'DIED' -and (Get-Process kenshi_x64 -ErrorAction SilentlyContinue)) { $env:KAH_OWNER = $owner5; & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-ctl.ps1" stop | Out-Null }
                Remove-Item $lk -ErrorAction SilentlyContinue; Log "lock released ($how $name)"
            }
        }   # 4080: stopped (DIED) / marker removed below
    }
    $sumL = Join-Path "$qd\done" "$name.SUMMARY.txt"
    if ($Rig -eq '4080' -and -not $Fake) {
        & scp -q -o BatchMode=yes "4080:C:/KenshiTestRuns/$(Split-Path $outP -Leaf)/SUMMARY.txt" $sumL 2>$null
        if (-not $Tail) {
            if ($how -eq 'DONE' -and @(QueuedLists).Count) { $script:keep4080 = $true; Log "4080 Kenshi stays up for the next list" }
            elseif ($how -ne 'LOST') { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null; $script:keep4080 = $false }
            Remove-Item (Join-Path $runs 'inflight\4080-runner') -ErrorAction SilentlyContinue
        }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    } else { Copy-Item (Join-Path $outW 'SUMMARY.txt') $sumL -ErrorAction SilentlyContinue }
    $sum = if (Test-Path $sumL) { Get-Content $sumL } else { @() }
    $nf = @($sum | Where-Object { $_ -match '^RESULT \S+ FAIL' }).Count; $np = @($sum | Where-Object { $_ -match '^RESULT \S+ PASS' }).Count
    $where = if ($Rig -eq '4080' -and -not $Fake) { "4080:C:\KenshiTestRuns\$(Split-Path $outP -Leaf)" } else { $outW }
    $dest = if ($how -eq 'DONE') { "$qd\done" } else { "$qd\failed" }
    $isFill = (Split-Path $run -Leaf) -like '*__filler__*'
    $pre = @($sum | Where-Object { $_ -like 'BATCH PREEMPTED*' }) | Select-Object -First 1
    if ($pre -and -not $Why) { $Why = "preempted: $(($pre -replace '^BATCH PREEMPTED \S+ \S+ ', '').Trim())" }
    if ($isFill -and $how -eq 'DONE' -and $pre) { Move-Item -LiteralPath $run (Join-Path $dest $name) -Force -ErrorAction SilentlyContinue }   # the copy -> done\ (preempted), filler\ keeps the original
    elseif ($isFill -and $how -eq 'DONE') { Remove-Item -LiteralPath $run -ErrorAction SilentlyContinue }   # a copy: the original stays in filler\
    else { Move-Item -LiteralPath $run (Join-Path $dest $name) -Force -ErrorAction SilentlyContinue; if ($isFill) { Bench $name 3 "$how $Why" } }
    # fast setup FAIL = idle (Shay 2026-10-10): nothing passed, every RESULT is a setup/dryrun FAIL (or none / batch aborted)
    # within FastMin: sticky ALERT-<rig>-setup.txt (the Stop hook blocks on it; deleted by hand once handled, or after 30 min)
    $dur = try { ((Get-Date) - [datetime]$t0).TotalMinutes } catch { 999 }
    $nset = @($sum | Where-Object { $_ -match '^RESULT \S+ FAIL (setup|dryrun)' }).Count
    $abort = @($sum | Where-Object { $_ -match '^BATCH (ABORTED|REFUSED)' }).Count
    if ($how -ne 'LOST' -and -not $pre -and $np -eq 0 -and $dur -lt $FastMin -and ($abort -or $nf -eq 0 -or $nset -eq $nf)) {
        $fw = "list $name ended in $([int]$dur) min with no PASS ($nf FAIL, $nset setup/dryrun$(if ($abort) { ', batch aborted' })): the rig was effectively idle"
        FastAlert "$fw. SUMMARY $sumL. Fix the setup or pull the list, then delete this file."
        Note $own "$fw on ${Rig}. Fix the setup (RESULT lines in $sumL) before requeueing."
        if ($own -ne 'coordinator') { Note 'coordinator' "$fw on $Rig (owner $own)." }
        if ($isFill -and $how -eq 'DONE') { Bench $name 3 'fast setup FAIL' }
    }
    $ocf = Join-Path $rd "$Rig.oldcopy.$name"; $oc = if (Test-Path $ocf) { (Get-Content $ocf -Raw).Trim() } else { '' }; Remove-Item $ocf -ErrorAction SilentlyContinue
    Set-Content (Join-Path $dest "$name.result") @("$how $Rig start=$t0 end=$(Get-Date -Format s) out=$where pass=$np fail=$nf summary=$sumL$(if ($Why) { " why=$Why" })$(if ($oc) { " oldcopy=$oc (ran on the 4080's old copy: in use by a running analysis at the start)" })")
    Remove-Item $file -ErrorAction SilentlyContinue
    Log "$how $name pass=$np fail=$nf out=$where$(if ($Why) { " ($Why)" })"
    $more = if ($how -eq 'DONE') { 'Judge it, queue the next list.' } else { "The list is in queue\failed\ ($Why): fix or requeue it." }
    Note $own "$how $name on ${Rig}: pass=$np fail=$nf; SUMMARY $sumL (out $where). $more"
}

if ($Resolve) {   # rig-runner.ps1 -Rig <rig> -Resolve "KenshiFP <sha8>|latest" [-Fake]: what a list's needs: would install
    StagedRecord; $ik = (InstalledHashes).K
    if ($Resolve -match 'KenshiFP\s+(\w{8})\b') { $r = ResolvePinned $Matches[1] $ik; if ($r.fail) { "RESOLVE FAIL $($r.fail)" } else { "RESOLVE $(if ($r.sha) { "install $($r.sha)" } else { "keep installed $ik" }) : $($r.why)" } }
    else { $l = LatestStaged; "RESOLVE latest = $l (installed $ik)$(if ($l -and $l -ne $ik) { " -> install $l" } else { ' -> keep' })" }
    exit 0
}

# ---------------------------------------------------------------- loop
Log "start pid=$PID fake=$Fake idle>=${IdleMin}m stuck>=${StuckMin}m tick=${TickSec}s"
if ($Rig -eq '4080' -and -not $Fake) {
    $null = Ssh @('mkdir', 'C:\KAH\runner')
    if (-not (Scp4 @("$auto\rig4080\staged-state.ps1", "$auto\rig4080\procpaths.ps1") 'C:/KAH/runner/')) { Log 'could not copy staged-state.ps1/procpaths.ps1 to the 4080 (unreachable?)' }
}
$idleSince = $null; $condSince = $null; $lastGh = $null; $hits = @{}; $alerted = $false; $unreach = $null; $anaSince = $null; $anaWarned = @{}; $probeFail = 0; $deadHits = @{}
while ($true) {
    if (Test-Path (StopFlag $Rig)) { Log "stopped flag set ($((Get-Content (StopFlag $Rig) -Raw).Trim())): exit"; Remove-Item (Join-Path $rd "$Rig.pid") -ErrorAction SilentlyContinue; State "STOPPED"; exit 0 }
    try {
        if ((Test-Path $fastF) -and (Get-Item $fastF).LastWriteTime -lt (Get-Date).AddMinutes(-30)) { Remove-Item $fastF -ErrorAction SilentlyContinue; Log 'setup alert expired (30 min)' }
        try { CleanRunning } catch { Log "cleanrunning error: $($_.Exception.Message)" }
        try { StagedRecord } catch { Log "staged-history error: $($_.Exception.Message)" }
        if ((Test-Path $curF) -and -not $Fake) { try { PreDryNext } catch { Log "predry error: $($_.Exception.Message)" } }
        # batches past their game part (GAMEDONE) whose background analyses still run: finish them when DONE
        foreach ($tf in @(Get-ChildItem $rd -Filter "$Rig.tail.*" -File -ErrorAction SilentlyContinue)) {
            $tc = @(Get-Content $tf.FullName); $tp = if ($Fake) { @{ done = '1' } } else { Probe $tc[2] }
            if ($tp -and $tp.done -eq '1') { Finish-Batch $tc 'DONE' $tf.FullName -Tail }
            elseif ($tp -and $tp.alive -eq '0') {   # DIED only after 3 probes with the pid gone and still no DONE (DONE lands as run-batch exits)
                $k = "tail/$($tc[5])"; $deadHits[$k] = 1 + [int]$deadHits[$k]
                if (Test-Path (Join-Path $tc[1] 'DONE')) { Finish-Batch $tc 'DONE' $tf.FullName -Tail; $deadHits.Remove($k) }
                elseif ($deadHits[$k] -ge 3) { Alert "batch $($tc[5]) died in its background analyses (no DONE, pid gone 3 probes)"; Finish-Batch $tc 'DIED' $tf.FullName -Tail -Why 'run-batch.sh gone without DONE after GAMEDONE'; $deadHits.Remove($k) }
                else { Log "tail $($tc[5]): run-batch.sh pid gone, no DONE yet ($($deadHits[$k])/3)" }
            } elseif ($tp) { $deadHits.Remove("tail/$($tc[5])") }
        }
        if (Test-Path $curF) {
            $c = @(Get-Content $curF)
            $p = if ($Fake) { FakeProbe $c } else { Probe $c[2] }
            if ($p) { $probeFail = 0 } else { $probeFail++ }
            # a filler in its game part gives way to real work at the next row boundary
            if ($p -and $p.done -ne '1' -and $p.gamedone -ne '1' -and (Split-Path $c[0] -Leaf) -like '*__filler__*' -and -not $script:preempted[$c[5]] -and -not (IdleReason)) {
                $rl = @(RealLists); if ($rl.Count) { Preempt $c $rl[0].Name }
            }
            # ownership (2026-10-10 phantom: a restarted loop adopted the coordinator's hand run in the same out dir and held
            # the lock): the batch.pid seen first must be written within 10 min of our start command; later it must not change
            $foreign = $null
            if ($p -and $p.started -eq '1' -and $p.bpid -and $p.bpid -ne '-' -and $p.bmt -match '^\d+$') {   # old probe copies (4080): no bpid
                $tok = "$($p.bpid)@$($p.bmt)"
                if ($c.Count -ge 8 -and $c[7]) { if ($c[7] -ne $tok) { $foreign = "batch.pid is now $tok, ours was $($c[7])" } }
                else {
                    $t0e = ([DateTimeOffset][datetime]$c[4]).ToUnixTimeSeconds(); $d = [long]$p.bmt - $t0e
                    if ($d -lt -30 -or $d -gt 600) { $foreign = "batch.pid ($tok) written $d s from our start: not our batch" }
                    else { Add-Content $curF $tok; $c += $tok }
                }
            }
            if ($foreign) { Alert "batch $($c[5]): out dir taken over by another run ($foreign); runner lets it go"; Finish-Batch $c 'LOST' -Why "out dir taken over by another run-batch ($foreign); not killed"; $condSince = $null; $hits = @{}; continue }
            if (-not $p) {
                Log "probe failed for $($c[5]) ($probeFail)"; State "running $($c[5]): probe failed $probeFail tick(s)"
                if ($Rig -eq '4080') { if (-not $unreach) { $unreach = Get-Date } elseif (((Get-Date) - $unreach).TotalMinutes -ge 10) { Alert "4080 unreachable for 10 min during $($c[5])" } }
                elseif ($probeFail -ge 3) {
                    # 5090 probe broken 3 ticks: decide from Windows (DONE file, a run-batch.sh on this out dir) instead of waiting forever
                    $rb = @(Wsl @('pgrep', '-af', 'run-batch.sh') | Where-Object { $_ -match [regex]::Escape($c[2]) })
                    if (Test-Path (Join-Path $c[1] 'DONE')) { Finish-Batch $c 'DONE'; $probeFail = 0; continue }
                    if (-not $rb) { Alert "batch $($c[5]): probe failed $probeFail ticks and no run-batch.sh runs on $($c[2])"; Finish-Batch $c 'DIED' -Why "probe failed $probeFail ticks, no run-batch.sh process, no DONE"; $probeFail = 0; continue }
                }
            }
            elseif ($p.done -eq '1') { $unreach = $null; ClearAlert; Finish-Batch $c 'DONE'; $condSince = $null; $hits = @{}; continue }
            elseif ($p.started -eq '0' -and ((Get-Date) - [datetime]$c[4]).TotalMinutes -ge 3) {
                Alert "batch $($c[5]) never started (no batch.pid 3 min after the start command)"; Finish-Batch $c 'DIED' -Why 'never started (no batch.pid 3 min after the start command)'; continue
            }
            elseif ($p.gamedone -eq '1') {
                # game part over (Kenshi stopped on the 5090 by --stop): free the rig now, collect the analyses later
                Move-Item $curF (Join-Path $rd "$Rig.tail.$($c[5])") -Force
                if ($Rig -eq '4080') {
                    if (@(QueuedLists).Count) { $script:keep4080 = $true; Log "4080 Kenshi stays up for the next list" }   # no relaunch gap
                    else { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null; $script:keep4080 = $false }
                    Remove-Item (Join-Path $runs 'inflight\4080-runner') -ErrorAction SilentlyContinue
                }
                else { Remove-Item (Join-Path $runs 'inflight\runner-5090') -ErrorAction SilentlyContinue }
                Log "GAMEDONE $($c[5]): rig free, background analyses continue"; ClearAlert; $condSince = $null; $hits = @{}; $anaSince = $null; continue
            }
            elseif ($p.alive -eq '0') {
                $k = "cur/$($c[5])"; $deadHits[$k] = 1 + [int]$deadHits[$k]
                if (Test-Path (Join-Path $c[1] 'DONE')) { $deadHits.Remove($k); Finish-Batch $c 'DONE'; continue }
                if ($deadHits[$k] -ge 3) { $deadHits.Remove($k); Alert "batch $($c[5]) died without DONE (run-batch.sh process gone 3 probes)"; Finish-Batch $c 'DIED' -Why 'run-batch.sh process gone without DONE'; continue }
                Log "$($c[5]): run-batch.sh pid gone, no DONE yet ($($deadHits[$k])/3)"
                State "running $($c[5]): run-batch.sh process gone, no DONE yet (check $($deadHits[$k])/3, then DIED)"
            }
            else {
                $unreach = $null
                $lim = if ($p.launched -eq '0') { 15 } elseif ($p.stallmin -match '^\d+$') { [int]$p.stallmin } else { $StuckMin }
                $why = if ($p.kenshi -eq '0') { 'Kenshi not running' } elseif ($p.crash -eq '1') { 'Kenshi crashed (dump)' }
                       elseif ($p.gh -eq '-') { 'harness not answering' } elseif ($p.phase -ne 'world' -and $p.launched -eq '1') { "not in the world ($($p.phase))" }
                       elseif ($lastGh -and $p.gh -eq $lastGh) { "game time stuck at $($p.gh) h (paused?)" } else { $null }
                $lastGh = $p.gh
                # game idle while the row analyses in the foreground (no recording): ALERT + note, once per row
                if ($p.ana -eq '1') {
                    if (-not $anaSince) { $anaSince = Get-Date }
                    if (((Get-Date) - $anaSince).TotalMinutes -ge $StuckMin -and -not $anaWarned["$($c[5])/$($p.step)"]) {
                        $anaWarned["$($c[5])/$($p.step)"] = 1
                        Alert "$($c[5]) row $($p.step): the game sits idle $([int]((Get-Date) - $anaSince).TotalMinutes) min while the row runs its lab analysis in the foreground. The take script must call pf_game_done (take-preflight.sh) after its game part so run-batch.sh moves on."
                        Note $c[3] "row $($p.step) of $($c[5]) left the game idle >= $StuckMin min during its offline analysis: add pf_game_done (take-preflight.sh) after the recording/game evidence in that script."
                    }
                } else { $anaSince = $null }
                # instant setup-FAIL streak = idle (Shay 2026-10-10): >= 3 rows in a row FAILed setup < 90 s apart: ALERT + notes once per batch
                if ($p.setupstreak -match '^\d+$' -and [int]$p.setupstreak -ge 3 -and -not $anaWarned["$($c[5])/setup"]) {
                    $anaWarned["$($c[5])/setup"] = 1
                    FastAlert "$($c[5]): $($p.setupstreak) rows in a row FAILed setup within seconds: the rig is effectively idle. Fix the setup or pull the list, then delete this file."
                    Note $c[3] "$($c[5]) on ${Rig}: $($p.setupstreak) rows in a row FAILed setup within seconds (counts as idle). Check the RESULT lines and fix the setup / requeue."
                    Note 'coordinator' "$($c[5]) on ${Rig} (owner $($c[3])): $($p.setupstreak) instant setup FAILs in a row: the rig is effectively idle."
                }
                # game idle between rows (Shay 2026-10-10: no rig idle > 2 min): Kenshi up, no row running, out dir still for
                # >= StuckMin: ALERT + note once per gap (no kill: run-batch.sh may be doing excerpts/waits; stuck rules still apply)
                if ($p.kenshi -eq '1' -and $p.launched -eq '1' -and $p.step -eq '-' -and [int]$p.age -ge $StuckMin * 60) {
                    if (-not $noRowWarned) {
                        $noRowWarned = $true
                        Alert "$($c[5]): game idle, Kenshi up but no row running and the out dir unchanged $([int]([int]$p.age / 60)) min (run-batch.sh between rows?)"
                        Note $c[3] "$($c[5]) on ${Rig}: the game sat idle >= $StuckMin min between rows (no row running, no output). Check batch.log."
                    }
                } elseif ($p.step -ne '-') { $noRowWarned = $false }
                if (-not $why) { $condSince = $null; if ([int]$p.age -lt 120) { ClearAlert } }
                else {
                    if (-not $condSince) { $condSince = Get-Date }
                    $held = ((Get-Date) - $condSince).TotalMinutes
                    if ($held -ge $lim -and [int]$p.age -ge $lim * 60) {
                        $key = "$($p.step)"; $hits[$key] = 1 + [int]$hits[$key]
                        $act = if ($p.crash -eq '1' -or $hits[$key] -ge 2 -or $p.step -eq '-') { 'kill-game' } else { 'kill-step' }
                        $r = Probe $c[2] $act
                        Alert "$($c[5]) stuck $([int]$held) min ($why; out dir unchanged $([int]([int]$p.age / 60)) min, row $($p.step)): $act -> $r"
                        Note $c[3] "$($c[5]) row $($p.step) was stuck ($why); I did $act ($r). The batch goes on; check that row."
                        $condSince = $null
                    }
                }
                State "running $($c[5]) row=$($p.step) age=$($p.age)s gh=$($p.gh) $(if ($why) { "COND: $why" })$(if ($script:preempted[$c[5]]) { ' PREEMPTED: ends after this row' })"
            }
        } else {
            if (Test-Path (Join-Path $rd "$Rig.restart")) {   # list boundary: hand over to a fresh copy of the (new) script
                Remove-Item (Join-Path $rd "$Rig.restart"), (Join-Path $rd "$Rig.pid") -ErrorAction SilentlyContinue
                $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Rig', $Rig, '-Force') + $(if ($Fake) { @('-Fake') } else { @() }) + $(if ($script:keep4080) { @('-Keep4080') } else { @() })
                $np = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList $a
                Log "restart at the list boundary: new loop pid=$($np.Id)$(if ($script:keep4080) { ' (4080 Kenshi kept up for the next list)' })"; exit 0
            }
            $reason = IdleReason
            $f = PickList
            $s = if ($Fake) { 'IDLE' } elseif ($Rig -eq '5090') { [string](& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig5090-state.ps1" 2>$null | Select-Object -First 1) } else { [string](& powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\rig4080-state.ps1" -Fresh 2>$null | Select-Object -First 1) }
            # someone else's job holds the rig: a running batch/marker (BUSY), but not "BUSY between batches" (the last one is
            # DONE: start at once) and not a 4080 Kenshi left open with no job (taken after IdleMin)
            $open4 = ($Rig -eq '4080' -and $s -like 'BUSY kenshi=yes*')
            $other = ($s -like 'BUSY*') -and ($s -notlike 'BUSY between*') -and -not $open4
            if ($Rig -eq '5090' -and -not $Fake -and -not $other) {
                # a run-batch.sh still in its game part (no GAMEDONE in its out dir, the last argument)
                foreach ($l in @(Wsl @('pgrep', '-af', 'run-batch.sh') | Where-Object { $_ -match '^\d+ .*run-batch\.sh' })) {
                    $o = ($l.Trim() -split '\s+')[-1]
                    if ($o -match '^/mnt/c/') { $ow = 'C:\' + ($o.Substring(7) -replace '/', '\'); if (-not (Test-Path (Join-Path $ow 'GAMEDONE')) -and -not (Test-Path (Join-Path $ow 'DONE'))) { $other = $true } } else { $other = $true }
                }
            }
            if ($other -or $s -like 'UNREACHABLE*') { $idleSince = $null }
            elseif (-not $idleSince) { $idleSince = Get-Date }
            $idleFor = if ($idleSince) { ((Get-Date) - $idleSince).TotalMinutes } else { 0 }
            if ($s -like 'UNREACHABLE*' -and $f) {
                if (-not $unreach) { $unreach = Get-Date } elseif (((Get-Date) - $unreach).TotalMinutes -ge $IdleMin) { if (-not (Test-Path $alertF)) { Alert "4080 unreachable with $($f.Name) queued" } }
                State "unreachable, $($f.Name) waiting"
            } elseif ($reason) { State "paused: $reason"; ClearAlert; $alerted = $false }
            elseif ($other) { State "rig busy with other work ($s)$(if ($f) { "; next $($f.Name)" })" }
            elseif ($f) {
                # the rig is free: start at once if Kenshi is closed / we own it, else after IdleMin of an idle open game
                # free rig with a list waiting: start at once (the previous batch is DONE/GAMEDONE or Kenshi is closed);
                # only a 4080 Kenshi left open with no job waits IdleMin (someone may be using it by hand)
                $ours = $Fake -or -not $open4 -or ($idleFor -ge $IdleMin)
                if ($Rig -eq '5090' -and -not $Fake) { $lk = Join-Path $runs 'game.lock'; if ((Test-Path $lk) -and (Get-Content $lk -TotalCount 1).Trim() -eq $owner5) { $ours = $true } }
                if ($script:keep4080) { $ours = $true }   # the open 4080 game is the one we kept up for this list
                if ($ours) { $unreach = $null; $alerted = $false; $idleSince = $null; $lastGh = $null; $condSince = $null; $hits = @{}; if (Start-Batch $f) { continue } }
                else { State "waiting for idle rig ($s), $($f.Name) next in $([int]($IdleMin - $idleFor)) min" }
            } else {
                State "queue empty ($s)"
                if ($idleFor -ge $IdleMin -and -not $alerted) {
                    $fs = if ($script:fillerSkips.Count) { " Filler skipped: $($script:fillerSkips -join '; ')." } else { ' queue\filler\ has nothing for this rig.' }
                    Alert "$Rig idle $([int]$idleFor) min and its queue is empty (queue\$Rig\ and queue\any\ have no *.list).$fs Put the next batch list there now, or record kenshi-ctl.ps1 idle$(if ($Rig -eq '4080') { '4080' }) `"<reason>`"."
                    if ($Rig -eq '4080' -and $script:keep4080 -and -not $Fake) { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null; $script:keep4080 = $false; Log '4080 Kenshi stopped (queue empty)' }
                    Note 'coordinator' "$Rig idle and queue empty: write the next list into queue\$Rig\ (or any\)."
                    $alerted = $true
                    if ($Rig -eq '4080' -and -not $Fake -and $s -like 'IDLE kenshi=no*') { Ssh4Ps 'C:\KAH\kcfg.ps1' @('play') | Out-Null }
                    # give the 5090 lock back when the runner has nothing to do (it takes it again with the next list)
                    if ($Rig -eq '5090' -and -not $Fake) {
                        $lk = Join-Path $runs 'game.lock'; if ((Test-Path $lk) -and (Get-Content $lk -TotalCount 1).Trim() -eq $owner5) {
                            # batches no longer --stop: close the game the runner left up, then release
                            if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { $env:KAH_OWNER = $owner5; & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-ctl.ps1" stop | Out-Null; Log 'Kenshi stopped (queue empty)' }
                            Remove-Item $lk; Log 'lock released (queue empty)' } }
                }
            }
        }
    } catch { Log "error: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" }
    Start-Sleep -Seconds $TickSec
}
