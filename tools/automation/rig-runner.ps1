<#
rig-runner.ps1: one daemon per rig runs that rig's batches from a queue folder, so no rig depends on an agent staying alive
(Shay 2026-10-10: "a script runs each rig, not an agent"; no rig idle or paused > 2 min while work exists). Agents only
write list files and judge results. Replaces rig-watchdog.ps1 (now a shim to this).

Use (PowerShell on the 5090; both rig loops run here, the 4080 one drives the 4080 over ssh):
  rig-runner.ps1 -Ensure                 start the 5090 and 4080 loops if not running (session-start.ps1 does this)
  rig-runner.ps1 -Status                 one line per rig + queue counts
  rig-runner.ps1 -Stop [-Rig 5090|4080]  stop the loop(s) (a running batch keeps running; a restarted loop re-adopts it)
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
  # needs: KenshiFP <sha8>|staged-latest   install that staged build (default: the newest staged build if it is newer
  #                                        than the installed DLL); needs: Harness <sha8> = installed harness must match
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
Files: C:\KenshiTestRuns\runner\<rig>.pid|.log|.state|.cur.
#>
param([ValidateSet('5090', '4080', '')][string]$Rig = '', [switch]$Ensure, [switch]$Stop, [switch]$Status, [switch]$Fake,
      [int]$IdleMin = 2, [int]$StuckMin = 2, [int]$TickSec = 60)
$runs = 'C:\KenshiTestRuns'; $auto = 'C:\KenshiModding\tools\automation'
$rd = if ($Fake) { Join-Path $runs 'runner\fake' } else { Join-Path $runs 'runner' }
$qd = if ($Fake) { Join-Path $rd 'queue' } else { Join-Path $runs 'queue' }
foreach ($d in $rd, "$qd\5090", "$qd\4080", "$qd\any", "$qd\running", "$qd\done", "$qd\failed") { New-Item -ItemType Directory -Force $d | Out-Null }
$distro = 'DwemerAI4Skyrim3'
function PidAlive([string]$r) { $f = Join-Path $rd "$r.pid"; if (Test-Path $f) { $p = [int](Get-Content $f -Raw); return [bool](Get-Process -Id $p -ErrorAction SilentlyContinue) } $false }

if ($Stop) {
    foreach ($r in $(if ($Rig) { @($Rig) } else { @('5090', '4080') })) {
        if (PidAlive $r) { Stop-Process -Id ([int](Get-Content (Join-Path $rd "$r.pid") -Raw)) -Force; "stopped runner $r" } else { "runner $r not running" }
        Remove-Item (Join-Path $rd "$r.pid") -ErrorAction SilentlyContinue
    }
    exit 0
}
if ($Status) {
    foreach ($r in '5090', '4080') {
        $st = if (Test-Path "$rd\$r.state") { (Get-Content "$rd\$r.state" -Raw).Trim() } else { '-' }
        $n = @(Get-ChildItem "$qd\$r" -Filter *.list -File -ErrorAction SilentlyContinue).Count
        "runner $r $(if (PidAlive $r) { 'up' } else { 'DOWN' }): $st | queued $r=$n"
    }
    "queued any=$(@(Get-ChildItem "$qd\any" -Filter *.list -File -ErrorAction SilentlyContinue).Count)"
    exit 0
}
if ($Ensure) {
    foreach ($r in '5090', '4080') {
        if (PidAlive $r) { "runner $r running pid=$(Get-Content (Join-Path $rd "$r.pid") -Raw)"; continue }
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Rig', $r) + $(if ($Fake) { @('-Fake') } else { @() })
        $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList $a
        "runner $r started pid=$($p.Id)"
    }
    exit 0
}
if (-not $Rig) { Get-Content $PSCommandPath -TotalCount 40; exit 2 }
if (PidAlive $Rig) { "runner $Rig already running"; exit 0 }
Set-Content (Join-Path $rd "$Rig.pid") $PID

# ---------------------------------------------------------------- helpers
$log = Join-Path $rd "$Rig.log"; $stateF = Join-Path $rd "$Rig.state"; $curF = Join-Path $rd "$Rig.cur"
$alertF = if ($Fake) { Join-Path $rd "ALERT-$Rig.txt" } else { Join-Path $runs "ALERT-$Rig.txt" }
$owner4 = 'rig4080'; $owner5 = 'runner-5090'
function Log([string]$m) { Add-Content $log "$((Get-Date).ToString('MM-dd HH:mm:ss')) $m" }
function State([string]$m) { Set-Content $stateF "$((Get-Date).ToString('HH:mm')) $m" }
function Note([string]$who, [string]$m) {
    if ($Fake) { $who = "fake-$who" }
    Add-Content (Join-Path $runs "agents\$who.note-from-rig-runner") "$((Get-Date).ToString('MM-dd HH:mm')) rig-runner $Rig`: $m"
}
function Alert([string]$m) { Set-Content $alertF "ALERT $Rig $((Get-Date).ToString('HH:mm')) $m"; Log "ALERT $m" }
function ClearAlert { if (Test-Path $alertF) { Remove-Item $alertF -ErrorAction SilentlyContinue; Log 'alert cleared' } }
function Wsl([string[]]$a) { & wsl.exe -d $distro -u root --cd / -- @a 2>&1 | ForEach-Object { "$_" } }
function WslPath([string]$w) { '/mnt/' + $w.Substring(0, 1).ToLower() + ($w.Substring(2) -replace '\\', '/') }
function Ssh([string[]]$a) { & ssh -n -o BatchMode=yes -o ConnectTimeout=10 4080 @a 2>&1 | ForEach-Object { "$_" } }
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
function NextList {
    foreach ($src in "$qd\$Rig", "$qd\any") {
        foreach ($f in @(Get-ChildItem $src -Filter *.list -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if ($src -like '*\any') {
                $want = Header $f.FullName 'rig'
                if ($want -and $want -ne $Rig) { continue }
                if ($Rig -eq '4080' -and (StobeRows $f.FullName)) { continue }
            }
            return $f
        }
    }
    $null
}
function Fail-List([string]$runPath, [string]$name, [string]$own, [string]$why, [string[]]$detail) {
    $dst = Join-Path "$qd\failed" $name
    Move-Item -LiteralPath $runPath $dst -Force -ErrorAction SilentlyContinue
    Set-Content "$dst.result" (@("FAILED $Rig $(Get-Date -Format s) $why") + $detail)
    Log "FAILED $name : $why"
    Note $own "list $name NOT run ($why); details $dst.result. Fix it and put it back into queue\$Rig\ (or any\)."
}
# installed vs staged KenshiFP; returns $null (nothing to do) or the sha8 to install
function StagedWanted([string]$need) {
    $sd = if ($Rig -eq '5090') { "$runs\staged" } else { $null }
    if ($need -and $need -notmatch 'staged-latest') { return $need.ToUpper() }
    if ($Rig -eq '5090') {
        $f = Get-ChildItem "$sd\KenshiFP-*.dll" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $f) { return $null }
        $dst = 'C:\Users\Shay\AppData\Roaming\Vortex\kenshi\mods\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\KenshiFP\KenshiFP.dll'
        $h = $f.BaseName.Substring(9)
        if ((Get-FileHash $dst).Hash.Substring(0, 8) -eq $h) { return $null }
        if ($need -or $f.LastWriteTime -gt (Get-Item $dst).LastWriteTime) { return $h }
        return $null
    }
    # 4080: newest staged there vs installed (one ssh call)
    $r = Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @() | Select-Object -Last 1
    if ($r -match '^NEWEST (\w+) newer=(\d)') { if ($need -or $Matches[2] -eq '1') { return $Matches[1] } }
    $null
}

# ---------------------------------------------------------------- start a batch
function Start-Batch($f) {
    $name = $f.Name; $run = Join-Path "$qd\running" "${Rig}__$name"
    try { Move-Item -LiteralPath $f.FullName $run -ErrorAction Stop } catch { Log "could not take $name (another runner?)"; return $false }
    $own = Header $run 'owner'; if (-not $own) { $own = 'coordinator' }
    $outN = Header $run 'out'; if (-not $outN) { $outN = "$($f.BaseName)-$(Get-Date -Format 'MMdd-HHmm')" }
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
    $skip = @(Get-Content $run | Where-Object { $_ -match '^\s*#\s*nodryrun\s*:\s*(\S+)' } | ForEach-Object { $null = $_ -match '^\s*#\s*nodryrun\s*:\s*(\S+)'; $Matches[1] })
    $drl = $txt | Where-Object { $r = $_; if ($r -match '^\s*(#|$)') { return $true }; -not ($skip -contains (($r -split '\|')[0].Trim())) }
    [IO.File]::WriteAllText((Join-Path $tmp 'list.dryrun.txt'), (($drl -join "`n") + "`n"))
    Set-Content $curF @($run, $outW, $outP, $own, (Get-Date -Format s), $name, $tmp)
    State "starting $name -> $outW (owner $own)"; Log "START $name owner=$own out=$outW launch=$launch"
    ClearAlert

    # dry run (seconds; fake game)
    $tw = WslPath $tmp
    $dr = Wsl @('timeout', '1200', 'bash', "$(WslPath $auto)/dryrun.sh", '--rig', $Rig, '--out', "$tw/dryrun", "$tw/list.dryrun.txt")
    $sum = ($dr | Where-Object { $_ -like 'DRYRUN-SUMMARY*' } | Select-Object -Last 1)
    Log "dryrun $name : $sum"
    $drc = $LASTEXITCODE
    if ($drc -ne 0 -or $sum -cnotmatch '^DRYRUN-SUMMARY pass=\d+ fail=0 ') {   # dryrun.sh exits 1 on any FAIL row
        Fail-List $run $name $own "dryrun failed: $sum" @($dr | Where-Object { $_ -match '^DRYRUN .* FAIL' }); Remove-Item $curF; return $true
    }
    if ($Fake) {   # fake batch: the dryrun result is the batch result
        Set-Content (Join-Path $outW 'SUMMARY.txt') (@("BATCH START $(Get-Date -Format 'yyyy-MM-dd HH:mm') list=$name (fake)") + @($dr | Where-Object { $_ -like 'DRYRUN *' } | ForEach-Object { $_ -replace '^DRYRUN (\S+) (PASS|FAIL|SKIP)', 'RESULT $1 $2' }) + "BATCH END $(Get-Date -Format 'yyyy-MM-dd HH:mm') (fake)")
        New-Item -ItemType File (Join-Path $outW 'DONE') -Force | Out-Null
        Note $own "started $name (fake) out=$outW"; return $true
    }

    # stop Kenshi, install the wanted staged KenshiFP, check the harness
    $need = Header $run 'needs'
    $needK = if ($need -match 'KenshiFP\s+(\S+)') { $Matches[1] } elseif ($need -match 'staged-latest') { 'staged-latest' } else { $null }
    $needH = if ($need -match 'Harness\s+(\w{8})') { $Matches[1].ToUpper() } else { $null }
    $inst = StagedWanted $needK
    if ($Rig -eq '5090') {
        $env:KAH_OWNER = $owner5
        $lk = Join-Path $runs 'game.lock'
        if (Test-Path $lk) { $h = (Get-Content $lk -TotalCount 1).Trim(); if ($h -ne $owner5) { Log "lock taken over from $h"; Note $h "the 5090 was idle >= $IdleMin min: rig-runner took the game lock over (now $owner5). Queue your next batches as list files in queue\5090\ instead of launching yourself." } }
        Set-Content $lk @($owner5, (Get-Date -Format s)) -Encoding utf8
        if (Get-Process kenshi_x64 -ErrorAction SilentlyContinue) { & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\kenshi-ctl.ps1" stop | Out-Null }
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
        $st = "#!/bin/bash`nexport KAH_OWNER=$owner5 WSLENV=KAH_OWNER`ncd /`nsetsid nohup bash $outP/.run-batch.sh --launch $launch --stop --no-dryrun 'rig-runner dry-ran the list' $outP/list.txt $outP >/dev/null 2>&1 </dev/null &`nsleep 5`n"
        [IO.File]::WriteAllText((Join-Path $outW '.start.sh'), $st)
        Set-Content (Join-Path $runs 'inflight\runner-5090') $outP
        Wsl @('bash', "$outP/.start.sh") | Out-Null
    } else {
        $lk = (Ssh4Ps 'C:\KAH\ctl.ps1' @('lock') | Select-Object -First 1)
        if ($lk -and $lk -ne 'free' -and $lk.Trim() -ne $owner4) { Fail-List $run $name $own "4080 lock held by $lk" @(); Remove-Item $curF; return $true }
        $k = Ssh @('tasklist', '/nh'); if (($k -join ' ') -match 'kenshi_x64') { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null }
        if ($inst) {
            $o = Ssh4Ps 'C:\KAH\inst-staged.ps1' @('-Hash', $inst); Log "4080 install KenshiFP $inst : $($o -join ' / ')"
            if (-not ($o -match 'installed')) { Fail-List $run $name $own "4080 KenshiFP $inst install failed" $o; Remove-Item $curF; return $true }
        }
        if ($needH) {
            $hh = (Ssh4Ps 'C:\KAH\runner\staged-state.ps1' @('-Harness') | Select-Object -Last 1)
            if ($hh -notmatch $needH) { Fail-List $run $name $own "4080 needs Harness $needH, installed $hh" @(); Remove-Item $curF; return $true }
        }
        $null = Ssh @('mkdir', "C:\KenshiTestRuns\$outN")
        Copy-Item "$auto\run-batch.sh" (Join-Path $tmp '.run-batch.sh') -Force
        $ok = Scp4 @((Join-Path $tmp 'list.txt'), (Join-Path $tmp '.run-batch.sh')) "C:/KenshiTestRuns/$outN/"
        $ok = $ok -and (Scp4 @("$auto\rig-runner-probe.sh", "$auto\batch-excerpts.sh", "$auto\batch-health.sh", "$auto\rig-env.sh") 'C:/KenshiModding/tools/automation/')
        if (-not $ok) { Fail-List $run $name $own '4080 copy (scp) failed' @(); Remove-Item $curF; return $true }
        $o = Ssh4Ps 'C:\KAH\kcfg.ps1' @('test'); Log "4080 kcfg: $($o -join ' / ')"
        $o = Ssh4Ps 'C:\KAH\ctl.ps1' @('launch', '-Save', $launch, '-Owner', $owner4); Log "4080 launch $launch : $(($o | Select-Object -Last 3) -join ' / ')"
        $o = Ssh4Bash @('/c/KAH/bin/stobe-auto', 'input_isolation', 'on'); Log "4080 isolation: $($o -join ' ')"
        Set-Content (Join-Path $runs 'inflight\4080-runner') "4080:C:\KenshiTestRuns\$outN"
        # itrun -Cmd must be one token (ssh joins the args with spaces): a start script in the out dir
        [IO.File]::WriteAllText((Join-Path $tmp '.start.sh'), "#!/bin/bash`nexport KAH_OWNER=$owner4`nexec bash $outP/.run-batch.sh --no-dryrun 'rig-runner dry-ran the list' $outP/list.txt $outP`n")
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
function Finish-Batch([string[]]$c, [string]$how, [string]$file = $curF, [switch]$Tail) {
    $run, $outW, $outP, $own, $t0, $name, $tmp = $c
    $sumL = Join-Path "$qd\done" "$name.SUMMARY.txt"
    if ($Rig -eq '4080' -and -not $Fake) {
        & scp -q -o BatchMode=yes "4080:C:/KenshiTestRuns/$(Split-Path $outP -Leaf)/SUMMARY.txt" $sumL 2>$null
        if (-not $Tail) { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null; Remove-Item (Join-Path $runs 'inflight\4080-runner') -ErrorAction SilentlyContinue }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    } else { Copy-Item (Join-Path $outW 'SUMMARY.txt') $sumL -ErrorAction SilentlyContinue }
    $sum = if (Test-Path $sumL) { Get-Content $sumL } else { @() }
    $nf = @($sum | Where-Object { $_ -match '^RESULT \S+ FAIL' }).Count; $np = @($sum | Where-Object { $_ -match '^RESULT \S+ PASS' }).Count
    $where = if ($Rig -eq '4080' -and -not $Fake) { "4080:C:\KenshiTestRuns\$(Split-Path $outP -Leaf)" } else { $outW }
    $dest = if ($how -eq 'DONE') { "$qd\done" } else { "$qd\failed" }
    Move-Item -LiteralPath $run (Join-Path $dest $name) -Force -ErrorAction SilentlyContinue
    Set-Content (Join-Path $dest "$name.result") @("$how $Rig start=$t0 end=$(Get-Date -Format s) out=$where pass=$np fail=$nf summary=$sumL")
    Remove-Item $file -ErrorAction SilentlyContinue
    Log "$how $name pass=$np fail=$nf out=$where"
    Note $own "$how $name on ${Rig}: pass=$np fail=$nf; SUMMARY $sumL (out $where). Judge it, queue the next list."
}

# ---------------------------------------------------------------- loop
Log "start pid=$PID fake=$Fake idle>=${IdleMin}m stuck>=${StuckMin}m tick=${TickSec}s"
if ($Rig -eq '4080' -and -not $Fake) {
    $null = Ssh @('mkdir', 'C:\KAH\runner')
    if (-not (Scp4 @("$auto\rig4080\staged-state.ps1") 'C:/KAH/runner/')) { Log 'could not copy staged-state.ps1 to the 4080 (unreachable?)' }
}
$idleSince = $null; $condSince = $null; $lastGh = $null; $hits = @{}; $alerted = $false; $unreach = $null; $anaSince = $null; $anaWarned = @{}
while ($true) {
    try {
        # batches past their game part (GAMEDONE) whose background analyses still run: finish them when DONE
        foreach ($tf in @(Get-ChildItem $rd -Filter "$Rig.tail.*" -File -ErrorAction SilentlyContinue)) {
            $tc = @(Get-Content $tf.FullName); $tp = if ($Fake) { @{ done = '1' } } else { Probe $tc[2] }
            if ($tp -and $tp.done -eq '1') { Finish-Batch $tc 'DONE' $tf.FullName -Tail }
            elseif ($tp -and $tp.alive -eq '0') { Alert "batch $($tc[5]) died in its background analyses (no DONE)"; Finish-Batch $tc 'DIED' $tf.FullName -Tail }
        }
        if (Test-Path $curF) {
            $c = @(Get-Content $curF)
            $p = if ($Fake) { @{ done = '1' } } else { Probe $c[2] }
            if (-not $p) { Log "probe failed for $($c[5])"; if ($Rig -eq '4080') { if (-not $unreach) { $unreach = Get-Date } elseif (((Get-Date) - $unreach).TotalMinutes -ge 10) { Alert "4080 unreachable for 10 min during $($c[5])" } } }
            elseif ($p.done -eq '1') { $unreach = $null; ClearAlert; Finish-Batch $c 'DONE'; $condSince = $null; $hits = @{}; continue }
            elseif ($p.started -eq '0' -and ((Get-Date) - [datetime]$c[4]).TotalMinutes -ge 3) {
                Alert "batch $($c[5]) never started (no batch.pid 3 min after the start command)"; Finish-Batch $c 'DIED'; continue
            }
            elseif ($p.gamedone -eq '1') {
                # game part over (Kenshi stopped on the 5090 by --stop): free the rig now, collect the analyses later
                Move-Item $curF (Join-Path $rd "$Rig.tail.$($c[5])") -Force
                if ($Rig -eq '4080') { Ssh4Ps 'C:\KAH\ctl.ps1' @('stop', '-Owner', $owner4) | Out-Null; Remove-Item (Join-Path $runs 'inflight\4080-runner') -ErrorAction SilentlyContinue }
                else { Remove-Item (Join-Path $runs 'inflight\runner-5090') -ErrorAction SilentlyContinue }
                Log "GAMEDONE $($c[5]): rig free, background analyses continue"; ClearAlert; $condSince = $null; $hits = @{}; $anaSince = $null; continue
            }
            elseif ($p.alive -eq '0') { Alert "batch $($c[5]) died without DONE (run-batch.sh process gone)"; Finish-Batch $c 'DIED'; continue }
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
                State "running $($c[5]) row=$($p.step) age=$($p.age)s gh=$($p.gh) $(if ($why) { "COND: $why" })"
            }
        } else {
            $reason = IdleReason
            $f = NextList
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
                if ($ours) { $unreach = $null; $alerted = $false; $idleSince = $null; $lastGh = $null; $condSince = $null; $hits = @{}; if (Start-Batch $f) { continue } }
                else { State "waiting for idle rig ($s), $($f.Name) next in $([int]($IdleMin - $idleFor)) min" }
            } else {
                State "queue empty ($s)"
                if ($idleFor -ge $IdleMin -and -not $alerted) {
                    Alert "$Rig idle $([int]$idleFor) min and its queue is empty (queue\$Rig\ and queue\any\ have no *.list). Put the next batch list there now, or record kenshi-ctl.ps1 idle$(if ($Rig -eq '4080') { '4080' }) `"<reason>`"."
                    Note 'coordinator' "$Rig idle and queue empty: write the next list into queue\$Rig\ (or any\)."
                    $alerted = $true
                    if ($Rig -eq '4080' -and -not $Fake -and $s -like 'IDLE kenshi=no*') { Ssh4Ps 'C:\KAH\kcfg.ps1' @('play') | Out-Null }
                    # give the 5090 lock back when the runner has nothing to do (it takes it again with the next list)
                    if ($Rig -eq '5090' -and -not $Fake -and -not (Get-Process kenshi_x64 -ErrorAction SilentlyContinue)) {
                        $lk = Join-Path $runs 'game.lock'; if ((Test-Path $lk) -and (Get-Content $lk -TotalCount 1).Trim() -eq $owner5) { Remove-Item $lk; Log 'lock released (queue empty)' } }
                }
            }
        }
    } catch { Log "error: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" }
    Start-Sleep -Seconds $TickSec
}
