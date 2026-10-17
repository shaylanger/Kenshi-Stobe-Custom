# testruns-sweep.ps1: find test/automation leftovers that nobody cleaned up (Shay 2026-10-10: "stuff like
# C:\KenshiTestRuns\animlab images is left around and never cleaned up; we need it cleaned or it will never go away").
#
# Lists every top-level item in C:\KenshiTestRuns, C:\KAH + C:\KenshiTestRuns on the 4080, WSL /root/animlab-work and
# leaked WSL /tmp/animlab-* temp dirs that is
#   - NOT on the keep-list (corpus, logs newest 6, queue, inflight, scenarios, agents, review-verdicts.tsv, game.lock,
#     kenshi.cfg.play, rig*.idle/state, handoff.*, spec-videos final mp4s + README, the 4080 rig scripts, files the
#     animlab scripts/docs reference),
#   - NOT named in a RUNNING agent's status/handoff file, an inflight marker or a queue file,
#   - NOT kept with -Keep (reason recorded, valid 7 days),
#   - and older than -Hours (default 6; age = newest file inside)
# => one line per item: STALE <age h> <MB> <where>:<path>, then "SWEEP stale=N old24=M MB=X".
#
# Usage:
#   testruns-sweep.ps1                         list (local + WSL + 4080; 4080 result cached 30 min)
#   testruns-sweep.ps1 -Local                  local + WSL only (no ssh)
#   testruns-sweep.ps1 check                   for the Stop hook: prints only "SWEEP ..." + the >24 h items; exit 1 if any
#   testruns-sweep.ps1 -Keep <path> "<reason>" record why something stays (like kenshi-ctl idle); <path> as printed
#   testruns-sweep.ps1 keep                    show the keep records;  keep clear <path> removes one
#   testruns-sweep.ps1 refresh4080             refresh the 4080 cache only (check starts it in the background)
#   testruns-sweep.ps1 check -Auto             PI-62 (Shay-confirmed): before judging, settle the obvious >= 24 h leftovers of finished
#                                              owners without a coordinator turn (see "Auto mode" below); list -Auto does the same
#   testruns-sweep.ps1 -Auto -DryRun           print what -Auto would do, change nothing
# Auto mode (PI-62). Only items that are already STALE (so: not on the keep-list, not named by a RUNNING/STOPPED-CONTEXT agent status,
# inflight marker or queue file) AND older than 24 h (age = newest file inside; -AutoMinHours) are touched. Never touched: corpus, inflight,
# agents, queue, logs, scenarios, game*.lock, KenshiTestFixtures, reparse points, anything outside the top level of the 5090 root.
#   AUTO-DELETE (5090 root only, every deletion logged to <root>\sweep-auto.log): selftest-run*.txt, pd (dir), *.brief.md strays, selftest-all*, scratch-*,
#     coordinator.heartbeat.*.tmp, dur_run*.sh (Shay 2026-10-16),
#     imm26-nc<N>[-suffix] trees with N <= newest NC number - 2 that no RUNNING status names (newest = highest imm26-nc<N> tree, or -NewestNC);
#     the NC rule also needs the workspace repo to have no unpushed commits (work committed and pushed).
#   AUTO-KEEP 7 days (standard reason, logged, only once per path: an expired auto-keep surfaces as a normal STALE): pi<N>-stage dirs,
#     *-report.txt / *-report.md, 4080 launch-log dumps (*before-launch, launch*.log/txt), imm26-nc<N> trees too new to delete.
#     Needs the same pushed-git gate.
#   Anything else stays a normal STALE (judgement stays with the coordinator).
# Wired in: session-start.ps1 prints the STALE list; the Stop hook (hooks/kenshi-waker-guard.ps1) blocks while items
# older than 24 h exist.
# Deleting stays a judgement: before removing a run dir, `corpus.sh add` anything a lab check / Misses row cites.
param(
    [Parameter(Position = 0)][string]$Command = 'list',
    [Parameter(Position = 1)][string]$Arg1,
    [string]$Keep,
    [Parameter(Position = 2)][string]$Reason,
    [double]$Hours = 6,
    [switch]$Local,
    [switch]$Fresh,
    [switch]$Auto,
    [switch]$DryRun,
    [double]$AutoMinHours = 24,
    [int]$NewestNC = 0,                        # 0 = highest imm26-nc<N> tree at the root
    [string]$Root = 'C:\KenshiTestRuns',       # selftest: a temp root
    [string]$WorkspaceRepo = 'C:\KenshiModding',
    [ValidateSet('auto', 'off')][string]$GitGate = 'auto',
    [switch]$NoRemote                          # selftest: no WSL, no ssh, no background 4080 refresh (the cache file is still read)
)
$runs = $Root
$ws = $WorkspaceRepo
$keepFile = Join-Path $runs 'sweep-keep.tsv'
$cache4080 = Join-Path $runs 'sweep-4080.cache'
$KEEPDAYS = 7

# ---------- keep records ----------
function Read-Keeps {
    $h = @{}
    if (Test-Path -LiteralPath $keepFile) {
        foreach ($l in Get-Content -LiteralPath $keepFile) {
            $f = $l -split "`t"
            if ($f.Count -ge 3) {
                $t = [datetime]::MinValue; [void][datetime]::TryParse($f[0], [ref]$t)
                if ($t -gt (Get-Date).AddDays(-$KEEPDAYS)) { $h[$f[1]] = "$($f[0]) $($f[2])" }
            }
        }
    }
    $h
}
if ($Keep) {
    if (-not $Reason) { $Reason = $Arg1 }
    if (-not $Reason -and $Command -ne 'list') { $Reason = $Command }   # -Keep <path> "<reason>": the reason binds to position 0
    if (-not $Reason) { 'usage: testruns-sweep.ps1 -Keep <path> "<reason>"'; exit 2 }
    $lines = @(); if (Test-Path -LiteralPath $keepFile) { $lines = @(Get-Content -LiteralPath $keepFile | Where-Object { ($_ -split "`t")[1] -ne $Keep }) }
    $lines += "$(Get-Date -Format 'yyyy-MM-dd HH:mm')`t$Keep`t$Reason"
    $lines | Set-Content -LiteralPath $keepFile -Encoding utf8
    "kept $Keep for $KEEPDAYS days: $Reason"; exit 0
}
if ($Command -eq 'keep') {
    if ($Arg1 -eq 'clear' -and $Reason) {
        if (Test-Path -LiteralPath $keepFile) { @(Get-Content -LiteralPath $keepFile | Where-Object { ($_ -split "`t")[1] -ne $Reason }) | Set-Content -LiteralPath $keepFile -Encoding utf8 }
        "cleared $Reason"; exit 0
    }
    $k = Read-Keeps; if (-not $k.Count) { 'no keep records' }; foreach ($p in $k.Keys) { "KEEP $p : $($k[$p])" }; exit 0
}

# ---------- names that running work refers to ----------
$refText = New-Object System.Text.StringBuilder
foreach ($s in Get-ChildItem -LiteralPath (Join-Path $runs 'agents') -Filter '*.status' -File -ErrorAction SilentlyContinue) {
    $t = Get-Content -Raw -LiteralPath $s.FullName -ErrorAction SilentlyContinue
    if ($t -match '\|\s*(RUNNING|STOPPED-CONTEXT)\s*\|') {
        [void]$refText.AppendLine($t)
        foreach ($x in Get-ChildItem -LiteralPath (Join-Path $runs 'agents') -File -Filter "$($s.BaseName).*" -ErrorAction SilentlyContinue) {
            [void]$refText.AppendLine((Get-Content -Raw -LiteralPath $x.FullName -ErrorAction SilentlyContinue))
        }
    }
}
foreach ($d in 'inflight', 'queue') {
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $runs $d) -File -ErrorAction SilentlyContinue) {
        [void]$refText.AppendLine($f.Name); [void]$refText.AppendLine((Get-Content -Raw -LiteralPath $f.FullName -ErrorAction SilentlyContinue))
    }
}
$refs = $refText.ToString()
function Is-Referenced([string]$name) {
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    foreach ($n in @($name, $base) | Select-Object -Unique) {
        if ($n.Length -lt 3) { continue }
        if ($refs -match ('(?<![A-Za-z0-9_-])' + [regex]::Escape($n) + '(?![A-Za-z0-9_])')) { return $true }
    }
    return $false
}

$keeps = Read-Keeps
$now = Get-Date
$items = New-Object System.Collections.ArrayList   # objects: where, path, ageH, mb

function Add-Item([string]$where, [string]$path, [double]$ageH, [double]$mb) {
    [void]$items.Add([pscustomobject]@{ where = $where; path = $path; ageH = [math]::Round($ageH, 1); mb = [math]::Round($mb, 1) })
}
function Scan-Win([string]$where, [string]$root, [string[]]$keepNames, [string[]]$keepGlobs) {
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($it in Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue) {
        $n = $it.Name
        if ($keepNames -contains $n) { continue }
        if (@($keepGlobs | Where-Object { $n -like $_ }).Count) { continue }
        if (Is-Referenced $n) { continue }
        if ($it.PSIsContainer) {
            $files = @(Get-ChildItem -LiteralPath $it.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
            $newest = if ($files.Count) { ($files | Measure-Object LastWriteTime -Maximum).Maximum } else { $it.LastWriteTime }
            $mb = (($files | Measure-Object Length -Sum).Sum) / 1MB
        } else { $newest = $it.LastWriteTime; $mb = $it.Length / 1MB }
        Add-Item $where $it.FullName (($now - $newest).TotalHours) $mb
    }
}

# --- 5090 C:\KenshiTestRuns ---
$keepTop = 'corpus', 'logs', 'queue', 'inflight', 'scenarios', 'agents', 'spec-videos', 'review-verdicts.tsv', 'game.lock',
    'kenshi.cfg.play', 'rig5090.idle', 'rig4080.idle', 'rig4080.state', 'rig4080.markerdone', 'rig4080.markerrun', 'display-keeper.beat', 'sweep-keep.tsv', 'sweep-4080.cache'
Scan-Win '5090' $runs $keepTop @('handoff.*')
# logs: newest 6 launch archives stay
Get-ChildItem -LiteralPath (Join-Path $runs 'logs') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 6 | ForEach-Object {
    $mb = ((Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB
    Add-Item '5090' $_.FullName (($now - $_.LastWriteTime).TotalHours) $mb
}
# spec-videos: only the decided mp4s + README stay
Scan-Win '5090' (Join-Path $runs 'spec-videos') @('README.txt', 'README.md') @('*.mp4')

# --- WSL: /root/animlab-work items no animlab script/doc names, leaked /tmp/animlab-* temp dirs ---
$wslScript = @'
H=$(cat /mnt/c/KenshiModding/components/KenshiFP/animlab/*.sh /mnt/c/KenshiModding/components/KenshiFP/animlab/*.py \
  /mnt/c/KenshiModding/components/KenshiFP/animlab/*.tsv /mnt/c/KenshiModding/components/KenshiFP/animlab/taste/* \
  /mnt/c/KenshiModding/Kenshi-Automation-Harness/docs/animlab/*.md /mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab/*.py \
  /mnt/c/KenshiTestRuns/corpus/MANIFEST.tsv 2>/dev/null | tr -d '\0')
now=$(date +%s)
emit(){ p=$1; t=$(find "$p" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1); [ -z "$t" ] && t=$(stat -c %Y "$p"); k=$(du -sk "$p" 2>/dev/null | cut -f1); echo "$p|$(( (now-${t%.*})/60 ))|$k"; }
cd /root/animlab-work 2>/dev/null && for f in *; do [ -e "$f" ] || continue; b=${f%.*}
  case "$f" in fists|pools|takes|kept|rec) continue;; esac
  printf '%s' "$H" | grep -qF -- "$f" && continue; printf '%s' "$H" | grep -qF -- "$b" && continue
  emit "/root/animlab-work/$f"; done
for p in /tmp/animlab-pool-* /tmp/animlab-sweep-* /tmp/animlab-gate-* /tmp/animlab-test-*; do [ -e "$p" ] && emit "$p"; done | awk -F'|' '{n++; if($2>m||m=="")m=$2; if(mn==""||$2<mn)mn=$2; k+=$3} END{if(n) print "/tmp/animlab-*-* (" n " leaked temp dirs)|" mn "|" k}'
'@
if (-not $NoRemote) { try {
    $OutputEncoding = New-Object System.Text.UTF8Encoding $false
    # PS 5.1 pipes with a BOM and CRLF: the guard line absorbs a BOM, CRs are stripped
    $out = (": bom-guard`n" + ($wslScript -replace "`r", "")) | wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s 2>$null
    foreach ($l in $out) {
        $f = $l -split '\|'
        if ($f.Count -ge 3 -and -not (Is-Referenced ([IO.Path]::GetFileName($f[0])))) { Add-Item 'wsl' $f[0] ([double]$f[1] / 60) ([double]$f[2] / 1024) }
    }
} catch { } }

# --- 4080: C:\KAH + C:\KenshiTestRuns (ssh, cached 30 min) ---
if (-not $Local -or $NoRemote) {
    $useCache = (-not $Fresh) -and ($Command -ne 'refresh4080') -and (Test-Path -LiteralPath $cache4080) -and ((Get-Item -LiteralPath $cache4080).LastWriteTime -gt $now.AddMinutes(-30))
    if ($NoRemote) { $useCache = $true }
    if (-not $useCache -and $Command -eq 'check') {
        # the Stop hook must stay fast: refresh the 4080 cache in the background, judge with the old one now
        Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, 'refresh4080' | Out-Null
        $useCache = $true
    }
    if (-not $useCache) {
        # one statement per line: `powershell -Command -` runs stdin line by line
        $rs = @'
$now=Get-Date
$kah='bin','client','displaycheck','itrun','vdd','vddtools','vm','scenarios','tools','pg','fp','ctl.ps1','itrun.ps1','kcfg.ps1','display-check.ps1','keep-display-on.bat','keep-display-on-task.cmd','keep-display-on.log','hide.vbs','inst.ps1','insth.ps1','mods.cfg.full'
$ktr='logs','queue','inflight','scenarios','game.lock','kenshi.cfg.play','corpus','agents'
function S($root,$keep){ foreach($it in Get-ChildItem -LiteralPath $root -Force -EA 0){ if($keep -contains $it.Name){continue}; if($it.PSIsContainer){$fs=@(Get-ChildItem -LiteralPath $it.FullName -Recurse -File -Force -EA 0); $nw=if($fs.Count){($fs|Measure-Object LastWriteTime -Maximum).Maximum}else{$it.LastWriteTime}; $mb=(($fs|Measure-Object Length -Sum).Sum)/1MB}else{$nw=$it.LastWriteTime;$mb=$it.Length/1MB}; '{0}|{1:N1}|{2:N1}' -f $it.FullName,($now-$nw).TotalHours,$mb } }
S 'C:\KAH' $kah; S 'C:\KenshiTestRuns' $ktr
Get-ChildItem -LiteralPath 'C:\KenshiTestRuns\logs' -EA 0 | Sort-Object LastWriteTime -Desc | Select-Object -Skip 6 | % { '{0}|{1:N1}|{2:N1}' -f $_.FullName,($now-$_.LastWriteTime).TotalHours,((Get-ChildItem -LiteralPath $_.FullName -Recurse -File -EA 0|Measure-Object Length -Sum).Sum/1MB) }
'@
        try {
            # first line absorbs the BOM PS 5.1 puts on piped stdin
            $r = ('$null = 0' + "`n" + ($rs -replace "`r", "")) | ssh -o ConnectTimeout=5 -o BatchMode=yes 4080 'powershell -NoProfile -Command -' 2>$null
            $r = @($r | Where-Object { $_ -match '^[A-Za-z]:\\.*\|' })
            if ($r.Count) { ($r -join "`n") | Set-Content -LiteralPath $cache4080 -Encoding utf8 }
        } catch { }
    }
    if ($Command -eq 'refresh4080') { exit 0 }
    if (Test-Path -LiteralPath $cache4080) {
        foreach ($l in Get-Content -LiteralPath $cache4080) {
            $f = $l -split '\|'
            if ($f.Count -ge 3 -and -not (Is-Referenced ([IO.Path]::GetFileName($f[0])))) { Add-Item '4080' $f[0] ([double]($f[1] -replace ',', '')) ([double]($f[2] -replace ',', '')) }
        }
    }
}

# ---------- Auto mode (PI-62) ----------
$autoLog = Join-Path $runs 'sweep-auto.log'
$script:autoDeleted = 0; $script:autoKept = 0
function Write-AutoLog([string]$kind, $it, [string]$why) {
    $line = "{0}`t{1}`t{2}h`t{3}MB`t{4}:{5}`t{6}{7}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $kind, $it.ageH, $it.mb, $it.where, $it.path, $why, $(if ($DryRun) { ' (dry-run)' } else { '' })
    try { Add-Content -LiteralPath $autoLog -Value $line -Encoding utf8 } catch { }
}
function Test-GitPushed {
    if ($GitGate -eq 'off') { return $true }
    try {
        $n = (& git -C $ws rev-list --count '@{u}..HEAD' 2>$null)
        return ($LASTEXITCODE -eq 0 -and [string]$n -eq '0')
    } catch { return $false }
}
function Test-AutoProtected($it) {
    $p = [string]$it.path
    if ($p -match '(?i)KenshiTestFixtures|[\\/]corpus([\\/]|$)|[\\/]inflight([\\/]|$)') { return $true }
    $leaf = [IO.Path]::GetFileName($p.TrimEnd('\', '/'))
    if ($leaf -match '(?i)^(corpus|inflight|agents|queue|logs|scenarios|KenshiTestFixtures|handoff\..*|sweep-.*)$' -or $leaf -match '(?i)^game.*\.lock$') { return $true }
    if (Is-Referenced $leaf) { return $true }
    return $false
}
function Invoke-AutoSweep([object[]]$cands) {
    $newestNc = $NewestNC
    if ($newestNc -le 0) {
        foreach ($d in Get-ChildItem -LiteralPath $runs -Directory -Force -ErrorAction SilentlyContinue) {
            if ($d.Name -match '^imm26-nc(\d{1,3})(?![0-9])' -and [int]$Matches[1] -gt $newestNc) { $newestNc = [int]$Matches[1] }
        }
    }
    $gate = $null   # lazily evaluated: one git call per run
    $rootTrim = $runs.TrimEnd('\')
    foreach ($it in $cands) {
        if ($it.ageH -lt $AutoMinHours) { continue }
        if (Test-AutoProtected $it) { continue }
        $p = [string]$it.path
        $leaf = [IO.Path]::GetFileName($p.TrimEnd('\', '/'))
        $isRoot5090 = ($it.where -eq '5090') -and ((Split-Path -Parent $p) -ieq $rootTrim)
        $isDir = $false
        if ($isRoot5090 -and (Test-Path -LiteralPath $p)) {
            $gi = Get-Item -LiteralPath $p -Force
            if ($gi.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $isDir = [bool]$gi.PSIsContainer
        }
        $action = $null; $why = ''
        $ncN = -1
        if ($leaf -match '^imm26-nc(\d{1,3})(?![0-9])(?:[a-z]|-[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)?)?$') { $ncN = [int]$Matches[1] }
        if ($isRoot5090 -and $leaf -like 'selftest-run*.txt' -and -not $isDir) { $action = 'DELETE'; $why = 'allow-list selftest-run*.txt' }
        elseif ($isRoot5090 -and $leaf -ceq 'pd' -and $isDir) { $action = 'DELETE'; $why = 'allow-list pd dir' }
        elseif ($isRoot5090 -and $leaf -like '*.brief.md' -and -not $isDir) { $action = 'DELETE'; $why = 'allow-list stray *.brief.md' }
        elseif ($isRoot5090 -and $leaf -like 'selftest-all*') { $action = 'DELETE'; $why = 'allow-list selftest-all*' }
        elseif ($isRoot5090 -and $leaf -like 'scratch-*') { $action = 'DELETE'; $why = 'allow-list scratch-*' }
        elseif ($isRoot5090 -and $leaf -like 'coordinator.heartbeat.*.tmp' -and -not $isDir) { $action = 'DELETE'; $why = 'allow-list coordinator.heartbeat.*.tmp' }
        elseif ($isRoot5090 -and $leaf -like 'dur_run*.sh' -and -not $isDir) { $action = 'DELETE'; $why = 'allow-list dur_run*.sh' }
        elseif ($isRoot5090 -and $ncN -ge 0 -and $newestNc -gt 0) {
            if ($null -eq $gate) { $gate = Test-GitPushed }
            if ($gate) {
                if ($ncN -le ($newestNc - 2)) {
                    if ($refs -notmatch ('(?i)(?<![A-Za-z0-9])nc' + $ncN + '(?![0-9])')) { $action = 'DELETE'; $why = "allow-list imm26-nc$ncN <= newest nc$newestNc - 2, repo pushed, no RUNNING status names it" }
                } else { $action = 'KEEP'; $why = "AUTO(PI-62): recent NC tree (nc$ncN, newest nc$newestNc), repo pushed, owner not RUNNING" }
            }
        }
        elseif ($isRoot5090 -and $leaf -match '^pi\d+-stage$' -and $isDir) { $action = 'KEEP'; $why = 'AUTO(PI-62): finished PI stage dir, repo pushed, owner not RUNNING' }
        elseif ($isRoot5090 -and $leaf -match '-report\.(txt|md)$' -and -not $isDir) { $action = 'KEEP'; $why = 'AUTO(PI-62): finished agent report file, repo pushed, owner not RUNNING' }
        elseif ($it.where -eq '4080' -and $leaf -match '(?i)(^|-)before-launch$|^launch.*\.(log|txt)$') { $action = 'KEEP'; $why = 'AUTO(PI-62): 4080 launch-log dump, repo pushed, owner not RUNNING' }
        if (-not $action) { continue }
        if ($action -eq 'KEEP') {
            if ($null -eq $gate) { $gate = Test-GitPushed }
            if (-not $gate) { continue }
            $key = if ($it.where -eq '5090') { $p } else { "$($it.where):$p" }
            # only once per path: an expired auto-keep record means a human should look
            $prior = $false
            if (Test-Path -LiteralPath $keepFile) {
                $prior = [bool](@(Get-Content -LiteralPath $keepFile | Where-Object { $f = $_ -split "`t"; $f.Count -ge 3 -and $f[1] -eq $key -and $f[2] -like 'AUTO(PI-62)*' }).Count)
            }
            if ($prior) { continue }
            Write-AutoLog 'KEEP' $it $why
            $script:autoKept++
            if (-not $DryRun) {
                $lines = @(); if (Test-Path -LiteralPath $keepFile) { $lines = @(Get-Content -LiteralPath $keepFile) }
                $lines += "$(Get-Date -Format 'yyyy-MM-dd HH:mm')`t$key`t$why"
                $lines | Set-Content -LiteralPath $keepFile -Encoding utf8
            }
            $keeps[$key] = "auto $why"
        } else {
            Write-AutoLog 'DELETE' $it $why
            if (-not $DryRun) {
                try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
                catch {
                    Add-Content -LiteralPath $autoLog -Value ("{0}`tDELETE-FAILED`t{1}`t{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $p, $_.Exception.Message) -Encoding utf8
                    continue
                }
            }
            $script:autoDeleted++
            [void]$items.Remove($it)
        }
    }
}

# ---------- report ----------
if ($Auto) { Invoke-AutoSweep @($items | Where-Object { $_.ageH -ge $Hours -and -not $keeps.ContainsKey($_.path) -and -not $keeps.ContainsKey("$($_.where):$($_.path)") }) }
$stale = @($items | Where-Object { $_.ageH -ge $Hours -and -not $keeps.ContainsKey($_.path) -and -not $keeps.ContainsKey("$($_.where):$($_.path)") } | Sort-Object mb -Descending)
$old = @($stale | Where-Object { $_.ageH -ge 24 })
$sum = "SWEEP stale=$($stale.Count) old24=$($old.Count) MB=$([math]::Round((($stale | Measure-Object mb -Sum).Sum), 0))"
if ($Command -eq 'check') {
    $sum
    if ($Auto -and ($script:autoDeleted + $script:autoKept)) { 'AUTO deleted={0} kept={1}{2}' -f $script:autoDeleted, $script:autoKept, $(if ($DryRun) { ' (dry-run)' } else { '' }) }
    $old | Select-Object -First 15 | ForEach-Object { "STALE {0}h {1}MB {2}:{3}" -f $_.ageH, $_.mb, $_.where, $_.path }
    if ($old.Count -gt 15) { "... $($old.Count - 15) more (testruns-sweep.ps1)" }
    exit ([int]($old.Count -gt 0))
}
$stale | ForEach-Object { "STALE {0}h {1}MB {2}:{3}" -f $_.ageH, $_.mb, $_.where, $_.path }
$kept = @($items | Where-Object { $keeps.ContainsKey($_.path) -or $keeps.ContainsKey("$($_.where):$($_.path)") })
$kept | ForEach-Object { $k = if ($keeps.ContainsKey($_.path)) { $keeps[$_.path] } else { $keeps["$($_.where):$($_.path)"] }; "KEPT {0}:{1} ({2})" -f $_.where, $_.path, $k }
$sum
if ($Auto) { 'AUTO deleted={0} kept={1}{2}' -f $script:autoDeleted, $script:autoKept, $(if ($DryRun) { ' (dry-run)' } else { '' }) }
exit 0
