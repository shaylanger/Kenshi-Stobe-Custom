<#
lane-isolation-check-5090.ps1 [-Lanes i3,i4,i5] [-Registry C:\KenshiTestRuns\lanes\lanes-5090.json]
5090 branch of lane-isolation-check.ps1 (that script dispatches here for rig 5090). Read-only: never starts, stops, focuses or changes a game,
backend or file. Spec: C:\KenshiTestRuns\agents\out\lane-isolation-spec.md. WSL facts come from lane-isolation-probe.py, window rects from lane-window.ps1.
Prints ONE line per item `RESULT lane-isolation <item> PASS|FAIL <evidence>` and `RESULT lane-isolation SUMMARY PASS|FAIL n_fail=<n>`; exit 1 on any FAIL.
A lane that is not running is checked on config/files only (live parts print "skipped").
Items: install-dir logs harness-channel saves backend-port database php-server wsl-tmp-env activity-key stobe-ini-route windows
       markers-locks shared-mutable log-crosstalk gfx-cap input-isolation llm-config not-live
#>
param([string[]]$Lanes = @(), [string]$Registry = 'C:\KenshiTestRuns\lanes\lanes-5090.json')
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:nfail = 0
function Emit([string]$item, [bool]$ok, [string]$ev) { if (-not $ok) { $script:nfail++ }; "RESULT lane-isolation $item $(if ($ok) { 'PASS' } else { 'FAIL' }) $ev" }
function Res([string]$item, $bad, $good) { Emit $item (@($bad).Count -eq 0) $(if (@($bad).Count) { @($bad) -join '; ' } else { $good }) }
$reg = Get-Content $Registry -Raw | ConvertFrom-Json
$all = @($reg.lanes)
$SEL = @($all | Where-Object { -not $Lanes.Count -or $Lanes -contains $_.id })
$distro = 'DwemerAI4Skyrim3'
$steam = 'D:\Steam\steamapps\common\Kenshi'
Add-Type @'
using System; using System.IO; using System.Runtime.InteropServices;
public static class KLaneLinks5090 {
  [StructLayout(LayoutKind.Sequential)] struct BHFI { public uint a, c1, c2, la1, la2, lw1, lw2, vsn, sh, sl, n, ih, il; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h, out BHFI i);
  public static int Count(string p) { try { using (var fs = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) { BHFI i; return GetFileInformationByHandle(fs.SafeFileHandle, out i) ? (int)i.n : -1; } } catch { return -2; } }
}
'@
function IsReparse([string]$p) { $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; [bool]($i -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) }
function Wsl([string]$bash, [string[]]$a = @()) {
  $f = "C:\KenshiTestRuns\lanes\tmp-iso-$([guid]::NewGuid().ToString('N').Substring(0, 8)).sh"
  [IO.File]::WriteAllText($f, "set +e`n" + ($bash -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
  $out = & wsl.exe -d $distro -u root --cd / -- bash ('/mnt/c/KenshiTestRuns/lanes/' + (Split-Path $f -Leaf)) @a 2>&1
  Remove-Item $f -Force -ErrorAction SilentlyContinue
  @($out | ForEach-Object { "$_" })
}
$procs = @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { $_.ExecutablePath })
function LaneProcs($l) { $pre = $l.dir.TrimEnd('\') + '\'; @($procs | Where-Object { $_.ExecutablePath.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) }) }
function Running($l) { @(LaneProcs $l).Count -gt 0 }
function Pids($l) { (@(LaneProcs $l | ForEach-Object ProcessId) -join ',') }

# ---- WSL facts (probe) ----
$regW = '/mnt/c/' + ($Registry.Substring(3) -replace '\\', '/')
$pj = (Wsl "python3 /mnt/c/KenshiModding/tools/automation/lane-isolation-probe.py $regW") | Where-Object { $_ -like '{*' } | Select-Object -Last 1
$PRB = $null; if ($pj) { try { $PRB = $pj | ConvertFrom-Json } catch {} }
if (-not $PRB) { Emit 'setup' $false 'WSL probe produced no JSON'; "RESULT lane-isolation SUMMARY FAIL n_fail=$script:nfail"; exit 1 }
function PL($l) { $PRB.lanes.($l.id) }

# DB / PG facts
$dbsh = @'
for spec in "$@"; do IFS=: read id root pg db bp <<<"$spec"
 q() { runuser -u postgres -- psql -h $root/socket -p $pg -d $db -Atc "$1" 2>&1 | head -1; }
 echo "D $id db=$(q 'select current_database()') port=$(q "select setting from pg_settings where name='port'") sysid=$(/usr/lib/postgresql/15/bin/pg_controldata $root/pgdata 2>/dev/null | awk -F: '/system identifier/{gsub(/ /,"",$2);print $2}') dbs=$(q 'select array_to_string(array_agg(datname),chr(44)) from pg_database') health=$(curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:$bp/health.php)"
done
echo "G apache=$(pgrep -c apache2) l80=$(ss -ltnH 'sport = :80 or sport = :443' | wc -l)"
'@
$specs = ($SEL | ForEach-Object { "$($_.id):$($_.wsl_root):$($_.pg_port):$($_.db):$($_.backend_port)" }) -join ' '
$dbo = Wsl ($dbsh + "`n") @($specs -split ' ')
$DB = @{}; $GG = ''
foreach ($dline in $dbo) {
  if ($dline -match '^D (\S+) (.*)$') { $id = $Matches[1]; $DB[$id] = @{}; foreach ($m in [regex]::Matches($Matches[2], '(\w+)=(.*?)(?=\s\w+=|$)')) { $DB[$id][$m.Groups[1].Value] = $m.Groups[2].Value.Trim() } }
  elseif ($dline -match '^G (.*)$') { $GG = $Matches[1] }
}

# 1 install-dir
$bad = @(); $ev = @()
if (@($SEL | ForEach-Object { $_.dir.ToLower() } | Select-Object -Unique).Count -ne $SEL.Count) { $bad += 'lane dirs not distinct' }
foreach ($l in $SEL) {
  if (-not (Test-Path "$($l.dir)\kenshi_x64.exe")) { $bad += "$($l.id): no kenshi_x64.exe"; continue }
  if ($l.dir.TrimEnd('\').ToLower() -eq $steam.ToLower()) { $bad += "$($l.id) is the Steam install" }
  foreach ($rel in 'mods\Stobe', 'mods\AutomationHarness', 'mods\KenshiFP', 'RE_Kenshi\mods\Stobe') {
    $p = Join-Path $l.dir $rel
    if (-not (Test-Path $p)) { $bad += "$($l.id): missing $rel" } elseif (IsReparse $p) { $bad += "$($l.id): $rel is a junction" }
  }
  if (@(LaneProcs $l).Count -gt 1) { $bad += "$($l.id): more than one game process" }
  $ev += "$($l.id)=$($l.dir) pid=$(if (Running $l) { Pids $l } else { 'not-running' })"
}
foreach ($p in $procs) { if (-not ($all | Where-Object { $p.ExecutablePath.StartsWith($_.dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) })) { $bad += "game pid $($p.ProcessId) outside every lane dir: $($p.ExecutablePath)" } }
Res 'install-dir' $bad ($ev -join ' ')

# 2 logs
$bad = @(); $seen = @{}; $n = 0
foreach ($l in $SEL) { foreach ($k in 'stobe_log', 'harness_log', 'kfp_log') {
  $p = $l.$k; $key = $p.ToLower(); if ($seen[$key]) { $bad += "log shared: $p" }; $seen[$key] = 1
  if (-not $p.StartsWith($l.dir, [StringComparison]::OrdinalIgnoreCase)) { $bad += "$($l.id) $k outside lane dir" }
  if (Test-Path $p) { $c = [KLaneLinks5090]::Count($p); $n++; if ($c -ne 1) { $bad += "$p link count $c" } }
} }
Res 'logs' $bad "$($SEL.Count * 3) distinct log paths inside own dirs, $n present, link count 1"

# 3 harness-channel
$bad = @(); $ev = @()
if (@($SEL | ForEach-Object { $_.harness_dir.ToLower() } | Select-Object -Unique).Count -ne $SEL.Count) { $bad += 'harness dirs not distinct' }
foreach ($l in $SEL) {
  foreach ($f in 'outbox.txt', 'inbox.txt', 'framecap.txt', 'enabled.flag') { $p = Join-Path $l.harness_dir $f; if (Test-Path $p) { $c = [KLaneLinks5090]::Count($p); if ($c -ne 1) { $bad += "$p link count $c" } } }
  foreach ($p in @(LaneProcs $l)) { $ls = @(Get-NetTCPConnection -State Listen -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue); if ($ls.Count) { $bad += "$($l.id) game pid $($p.ProcessId) listens on $((($ls | ForEach-Object LocalPort) | Select-Object -Unique) -join ',')" } }
  $ev += "$($l.id)=$($l.harness_dir)"
}
Res 'harness-channel' $bad "file-based inbox/outbox per lane, game processes listen on no port: $($ev -join ' ')"

# 4 saves
$bad = @(); $ev = @()
if (@($SEL | ForEach-Object { $_.save_name.ToLower() } | Select-Object -Unique).Count -ne $SEL.Count) { $bad += 'save names not distinct' }
foreach ($l in $SEL) {
  $set = (Get-Content (Join-Path $l.dir 'settings.cfg') -ErrorAction SilentlyContinue | Where-Object { $_ -like 'User save location=*' }) -join ''
  if ($set -ne 'User save location=0') { $bad += "$($l.id): settings.cfg '$set'" }
  $sd = Join-Path $l.save_dir $l.save_name
  if (-not (Test-Path $sd)) { $bad += "$($l.id): save $sd missing"; continue }
  if (IsReparse $sd) { $bad += "$($l.id): save dir is a junction" }
  $nf = 0; foreach ($f in Get-ChildItem $sd -Recurse -File -ErrorAction SilentlyContinue) { $nf++; if ([KLaneLinks5090]::Count($f.FullName) -gt 1) { $bad += "$($l.id): save file hard-linked $($f.Name)"; break } }
  foreach ($o in $all) { if ($o.id -ne $l.id -and (Test-Path (Join-Path $l.save_dir $o.save_name))) { $bad += "$($l.id) holds $($o.id)'s save $($o.save_name)" } }
  $ev += "$($l.id)=$($l.save_name)($nf files)"
}
Res 'saves' $bad "own save dirs, link count 1, User save location=0: $($ev -join ' ')"

# 5 backend-port
$bad = @(); $ev = @()
$ports = @($all | ForEach-Object { $_.backend_port; $_.bridge_port; $_.pg_port })
if (@($ports | Select-Object -Unique).Count -ne $ports.Count) { $bad += 'ports not distinct' }
foreach ($l in $SEL) {
  $bp = (PL $l).ports.backend_port
  if ($bp.Count -ne 1) { $bad += "$($l.id): $($bp.Count) listeners on $($l.backend_port)" }
  else {
    if ($bp[0].host -ne '127.0.0.1') { $bad += "$($l.id): listens on $($bp[0].host) (not loopback only)" }
    if ($bp[0].cmd -notlike "*$($l.wsl_root)/site*") { $bad += "$($l.id): listener cmd not own root: $($bp[0].cmd)" }
  }
  if ($DB[$l.id].health -ne '200') { $bad += "$($l.id): health.php $($DB[$l.id].health)" }
  $ev += "$($l.id)=php:$($l.backend_port)/health$($DB[$l.id].health)"
}
Res 'backend-port' $bad "distinct ports, loopback only, own docroot: $($ev -join ' ')"

# 6 database
$bad = @(); $ev = @()
$ids = @($SEL | ForEach-Object { $DB[$_.id].sysid })
if (@($ids | Select-Object -Unique).Count -ne $SEL.Count -or ($ids -contains '')) { $bad += "pg system identifiers not distinct: $($ids -join ',')" }
if (@($all | ForEach-Object { $_.db } | Select-Object -Unique).Count -ne $all.Count) { $bad += 'db names not distinct' }
foreach ($l in $SEL) {
  $d = $DB[$l.id]
  if ($d.db -ne $l.db) { $bad += "$($l.id): current_database '$($d.db)' != $($l.db)" }
  if ($d.port -ne "$($l.pg_port)") { $bad += "$($l.id): pg port setting '$($d.port)'" }
  if (",$($d.dbs)," -match ",$($reg.live.live_db),") { $bad += "$($l.id): cluster holds the live db '$($reg.live.live_db)'" }
  if (-not (PL $l).pg_socket_exists) { $bad += "$($l.id): no private socket dir" }
  $ev += "$($l.id)=$($l.db)@$($l.pg_port) sysid=$($d.sysid)"
}
Res 'database' $bad "separate postgres clusters (own pgdata/socket/port): $($ev -join ' ')"

# 7 php-server
$bad = @(); $ev = @()
if ([int](($GG -replace '.*apache=(\d+).*', '$1')) -ne 0) { $bad += 'apache2 processes running' }
if ([int](($GG -replace '.*l80=(\d+).*', '$1')) -ne 0) { $bad += 'listener on 80/443' }
foreach ($l in $SEL) {
  $pd = PL $l
  if ($pd.site_real -notlike "$($l.wsl_root)/*") { $bad += "$($l.id): docroot resolves to $($pd.site_real)" }
  if ($pd.site_real -like '/var/www/*') { $bad += "$($l.id): docroot under /var/www" }
  if ($pd.site_log_real -notlike "$($l.wsl_root)/*") { $bad += "$($l.id): log dir resolves to $($pd.site_log_real)" }
  $ev += "$($l.id)=$($pd.site_real)"
}
Res 'php-server' $bad "php -S per lane on own docroot+log dir, no apache/80/443: $($ev -join ' ')"

# 8 wsl-tmp-env
$bad = @(); $ev = @()
if (@($all | ForEach-Object { $_.wsl_root } | Select-Object -Unique).Count -ne $all.Count) { $bad += 'wsl roots not distinct' }
foreach ($l in $SEL) {
  $pd = PL $l
  if (-not $pd.root_exists) { $bad += "$($l.id): root missing"; continue }
  if ($pd.env -notmatch "STOBE_DB_NAME=$($l.db)(\s|$)") { $bad += "$($l.id): env.sh db name != $($l.db)" }
  if ($pd.env -notmatch "PGPORT=$($l.pg_port)(\s|$)") { $bad += "$($l.id): env.sh PGPORT != $($l.pg_port)" }
  if ($pd.env -notmatch [regex]::Escape("STOBE_DB_HOST=$($l.wsl_root)/socket")) { $bad += "$($l.id): env.sh socket host not own root" }
  if ($pd.env -notmatch 'STOBE_NO_BACKGROUND_PROCESSOR=1') { $bad += "$($l.id): background processor not disabled" }
  $ev += "$($l.id)=$($l.wsl_root)"
}
Res 'wsl-tmp-env' $bad "distinct /tmp roots, env.sh db+PGPORT+socket own, bg processor off: $($ev -join ' ')"

# 9 activity-key
$bad = @(); $ev = @()
$fps = @($SEL | ForEach-Object { (PL $_).key_fp })
if (@($fps | Select-Object -Unique).Count -ne $SEL.Count -or ($fps -contains $null)) { $bad += "server keys not distinct: $($fps -join ',')" }
foreach ($l in $SEL) {
  $g = Join-Path $l.dir 'mods\Stobe\activity-transport.key'
  if (Test-Path $g) { $gf = (Get-FileHash $g -Algorithm SHA256).Hash.Substring(0, 8).ToLower(); if ($gf -ne (PL $l).key_fp) { $bad += "$($l.id): game key $gf != own server key $((PL $l).key_fp)" }; $ev += "$($l.id)=server:$((PL $l).key_fp)=game:$gf" }
  else { $ev += "$($l.id)=server:$((PL $l).key_fp)=game:none(transport unused by this build; the live key is not copied in)" }
}
foreach ($sc in 'Machine', 'User', 'Process') { if ([Environment]::GetEnvironmentVariable('STOBE_ACTIVITY_TRANSPORT_SECRET', $sc)) { $bad += "STOBE_ACTIVITY_TRANSPORT_SECRET set in $sc environment (would reach every game)" } }
Res 'activity-key' $bad "per-lane server key (distinct), game-side key absent or own, no key in the Windows environment (sha256[:8]): $($ev -join ' ')"

# 10 stobe-ini-route
$bad = @(); $ev = @()
foreach ($l in $SEL) {
  $ports = @(Get-ChildItem (Split-Path $l.ini) -Filter *.ini | ForEach-Object { Get-Content $_.FullName | Where-Object { $_ -match '^\s*ServerPort\s*=' } | ForEach-Object { [int](($_ -split '=')[1].Trim()) } })
  $hosts = @(Get-ChildItem (Split-Path $l.ini) -Filter *.ini | ForEach-Object { Get-Content $_.FullName | Where-Object { $_ -match '^\s*ServerHost\s*=' } | ForEach-Object { ($_ -split '=')[1].Trim() } })
  if (-not $ports.Count -or @($ports | Where-Object { $_ -ne $l.backend_port }).Count) { $bad += "$($l.id): ServerPort $($ports -join ',') != $($l.backend_port)" }
  if (@($hosts | Where-Object { $_ -ne '127.0.0.1' }).Count) { $bad += "$($l.id): ServerHost $($hosts -join ',')" }
  $ev += "$($l.id)=127.0.0.1:$($ports | Select-Object -First 1)"
}
Res 'stobe-ini-route' $bad "each game's ini routes to its own backend port: $($ev -join ' ')"

# 11 windows
$bad = @(); $ev = @()
$wo = & powershell -NoProfile -ExecutionPolicy Bypass -File "$here\lane-window.ps1" -Lane all -Action show 2>&1 | ForEach-Object { "$_" }
foreach ($l in $SEL) {
  $row = $wo | Where-Object { $_ -like "$($l.id) *" } | Select-Object -First 1
  if ($row -like '*not running*') { $ev += "$($l.id)=not-running"; continue }
  if ($row -notmatch 'overlap=\[\]') { $bad += "$($l.id): $row" }
  if ($row -notmatch 'forbidden=no') { $bad += "$($l.id): on a forbidden display: $row" }
  if ($row -notmatch 'screen=DISPLAY[12]') { $bad += "$($l.id): not wholly on DISPLAY1/2: $row" }
  $ev += ($row -replace '^(\S+) pid=\d+ rect=(\S+) .*screen=(\S+) .*', '$1=$2@$3')
}
$fg = $wo | Where-Object { $_ -like 'foreground*' } | Select-Object -First 1
if ($fg -match 'foreground pid=(\d+)') { $fpid = [int]$Matches[1]; foreach ($l in $SEL) { if (@(LaneProcs $l).ProcessId -contains $fpid) { $bad += "$($l.id) game is the foreground window" } } }
Res 'windows' $bad "windowed, non-overlapping, DISPLAY1/2 only, none foreground: $($ev -join ' ')"

# 12 markers-locks
$bad = @(); $ev = @()
foreach ($k in 'inflight', 'lock', 'lock_owner') { if (@($all | ForEach-Object { $_.$k } | Select-Object -Unique).Count -ne $all.Count) { $bad += "two lanes share $k" } }
foreach ($l in $SEL) {
  $mk = Test-Path $l.inflight; $lk = Test-Path $l.lock
  if (Running $l) {
    if (-not $mk) { $bad += "$($l.id) running but marker $($l.inflight) missing" }
    if (-not $lk) { $bad += "$($l.id) running but lock $($l.lock) missing" } elseif ((Get-Content $l.lock -Raw) -notmatch [regex]::Escape($l.lock_owner)) { $bad += "$($l.id): lock owner is not $($l.lock_owner)" }
  }
  if ($l.lock -match 'game\.lock$') { $bad += "$($l.id) uses the instance-1 game.lock" }
  $ev += "$($l.id)=marker:$(if ($mk) { 'present' } else { 'absent' }),lock:$(if ($lk) { 'present' } else { 'absent' })"
}
Res 'markers-locks' $bad "own marker + game-<n>.lock + owner per lane: $($ev -join ' ')"

# 13 shared-mutable
$bad = @(); $n = 0
foreach ($l in $SEL) {
  foreach ($rel in 'kenshi.cfg', 'settings.cfg', 'RE_Kenshi\mods\Stobe\StobeCustom.ini', 'mods\AutomationHarness\framecap.txt', 'mods\AutomationHarness\enabled.flag', 'mods\AutomationHarness\input_isolation.on', 'mods\AutomationHarness\AutomationHarness.dll', 'mods\Stobe\activity-transport.key') {
    $p = Join-Path $l.dir $rel
    if (Test-Path $p) { $n++; $c = [KLaneLinks5090]::Count($p); if ($c -ne 1) { $bad += "$p link count $c" } }
  }
  foreach ($d in 'mods', 'RE_Kenshi', 'RE_Kenshi\mods', 'save', 'data') { $p = Join-Path $l.dir $d; if ((Test-Path $p) -and (IsReparse $p)) { $bad += "$p is a junction" } }
}
Res 'shared-mutable' $bad "$n mutable files link count 1, no junctioned mods/save/data dirs"

# 14 log-crosstalk
$bad = @(); $ev = @()
foreach ($l in $SEL) { foreach ($o in $all) { if ($o.id -ne $l.id) { $c = (PL $l).crosstalk.($o.id); if ($c.count -gt 0) { $bad += "$($l.id) logs mention $($o.id): $($c.examples -join ' | ')" } } } }
Res 'log-crosstalk' $bad 'no lane log (game, harness, KenshiFP, php, manager) names another lane port, db, save, root or dir'

# 15 gfx-cap
$bad = @(); $ev = @()
foreach ($l in $SEL) {
  $cfg = Get-Content (Join-Path $l.dir 'kenshi.cfg') -ErrorAction SilentlyContinue
  $fs = ($cfg | Where-Object { $_ -like 'Full Screen=*' }) -join ''; $vm = (($cfg | Where-Object { $_ -like 'Video Mode=*' }) -join '') -replace '^Video Mode=', ''
  if ($fs -ne 'Full Screen=No') { $bad += "$($l.id): $fs" }
  if ($vm -notlike "$($l.video_mode)*") { $bad += "$($l.id): Video Mode '$vm' != $($l.video_mode)" }
  if ($vm -match '^(\d+) x') { if ([int]$Matches[1] -lt 1024) { $bad += "$($l.id): mode $vm < 1024 wide (800x600 falls back to 4096x2160)" } }
  $fcp = Join-Path $l.harness_dir 'framecap.txt'; $fc = if (Test-Path $fcp) { (Get-Content $fcp -Raw).Trim() } else { '' }
  if ($fc -ne "$($l.framecap)") { $bad += "$($l.id): framecap.txt '$fc' != $($l.framecap)" }
  $ev += "$($l.id)=$vm cap$fc"
}
Res 'gfx-cap' $bad "windowed low-gfx, >=1024-wide mode, frame cap file matches registry: $($ev -join ' ')"

# 16 input-isolation
$bad = @(); $ev = @()
foreach ($l in $SEL) {
  $f = Join-Path $l.harness_dir 'input_isolation.on'
  if (-not (Test-Path $f)) { $bad += "$($l.id): input_isolation.on missing" } else { $ev += "$($l.id)=on" }
  if (Running $l) { $hl = Get-Content $l.harness_log -Tail 4000 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'input isolation: DirectInput' }; if (-not $hl) { $bad += "$($l.id): no 'input isolation: DirectInput' line in harness.log (hook not active)" } }
}
Res 'input-isolation' $bad "per-lane input isolation flag on, DirectInput hooked in running games: $($ev -join ' ')"

# 17 llm-config
$lo = Wsl "bash /mnt/c/KenshiModding/tools/automation/lane-llm-apply.sh --check all 2>&1 | tail -8"
$mm = @($lo | Where-Object { $_ -match 'MISMATCH' }); $ma = @($lo | Where-Object { $_ -match 'MATCH' -and $_ -notmatch 'MISMATCH' })
Emit 'llm-config' ($mm.Count -eq 0 -and $ma.Count -ge $SEL.Count) $(if ($mm.Count) { $mm -join '; ' } else { "lane-llm-apply --check: $($ma.Count) lanes MATCH lane-llm.json ($((($ma | Select-Object -First 3) -join ' | ')))" })

# 18 not-live
$bad = @(); $ev = @()
foreach ($l in $SEL) {
  if ($l.db -eq $reg.live.live_db) { $bad += "$($l.id) uses the live db" }
  if ($reg.live.ports -contains $l.backend_port -or $reg.live.ports -contains $l.pg_port) { $bad += "$($l.id) uses a live port" }
  if ($l.dir.StartsWith($steam, [StringComparison]::OrdinalIgnoreCase)) { $bad += "$($l.id) dir under Steam install" }
  if ($l.wsl_root -like '/var/www/*' -or $l.wsl_root -notlike '/tmp/*') { $bad += "$($l.id) root $($l.wsl_root) not under /tmp" }
}
foreach ($p in $procs) { if ($p.ExecutablePath.StartsWith($steam, [StringComparison]::OrdinalIgnoreCase)) { $bad += "Steam-install game running: pid $($p.ProcessId) (not ours: reported, not stopped)" } }
Res 'not-live' $bad "lane dirs/roots/ports/db all outside the Steam install, /var/www StobeServer, live db and ports $(@($reg.live.ports) -join '/')"

"RESULT lane-isolation SUMMARY $(if ($script:nfail) { 'FAIL' } else { 'PASS' }) n_fail=$script:nfail"
exit $(if ($script:nfail) { 1 } else { 0 })
