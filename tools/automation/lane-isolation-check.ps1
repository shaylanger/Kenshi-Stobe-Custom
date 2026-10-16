<#
lane-isolation-check.ps1 <rig> [-Defs <lane-defs.<rig>.json>]
Proves that the isolated STOBE test lanes of a rig are independent, so one lane can never cause a false-positive bug in the other.
Prints ONE line per item `RESULT lane-isolation <item> PASS|FAIL <evidence>` and exits 1 if any item FAILs (2 = cannot run).
Rig 4080 only so far (lane-defs.4080.json: lanes i3, i4). Run it from the 5090 (it copies itself to the 4080 and runs there, then adds the
5090-side `markers` item) or directly on the 4080. Read-only: it never starts, stops, focuses or changes a game, backend or file
(it writes only a temp .sh under C:\KenshiTestRuns\lane-i4 for the WSL probes and deletes it).
Items:
  install-dirs     own Kenshi tree per lane, real (non-junction) mods\Stobe, mods\AutomationHarness, mods\KenshiFP, RE_Kenshi\mods\Stobe,
                   running game process of each lane inside its own dir, one process per dir
  logs             stobe.log / harness.log / KenshiFP.log are separate files inside the lane, link count 1
  harness-channel  own harness inbox/outbox dir, no shared lock, game processes listen on no port (file-based harness: no port/pipe)
  saves            "User save location=0", distinct save names, real save dirs, files not hard-linked, other lane's save absent
  backend-ports    distinct php/bridge/pg ports; each php listener runs from its own root; game Stobe.ini/StobeCustom.ini ServerPort = own port
  backend-db       separate Postgres clusters (distinct system identifier + socket + pgdata), each lane's DB name is the expected one
  backend-php      php -S per lane with its own docroot, no apache/80/443 listener, docroots outside /var/www/html, distinct log dirs
  tmp-env          distinct /tmp roots and env.sh (db name + port), manager pid/lock inside own root
  activity-key     per-lane transport key: server key differs per lane and equals the lane's game-side mods\Stobe\activity-transport.key
  windows          windowed, not on a forbidden display, never the foreground; rect overlap allowed only as stacked windows (reported as stacked=[...])
  graphics         low gfx applied, 60 fps cap file, small windowed Video Mode
  locks            own game-<n>.lock per lane, not the instance-1 game.lock
  shared-mutable   no mutable file (cfg/ini/log/dll/...) is hard-linked or reached through a junction in any lane
  llm-config       lane-llm-apply-4080.sh --check all (every connector row = C:\KAH\lane-llm.json)
  log-crosstalk    no lane's game/backend logs mention the other lane's port, save, db, root, dir
  npc-world        each running game reports its own save name (distinct saves = distinct world state)
  resources        RAM < 85% used, VRAM < 90%, per-process numbers
  markers (5090)   distinct inflight markers, present while the lane's game runs
  lane-config      WARNING lines only (never FAIL, not counted in the exit code): `RESULT lane-isolation lane-config <rig>-<lane> ini|key PASS|WARN|FIXED ...` from
                   lane-config-check.ps1 (StobeCustom.ini no BOM / one [Settings] / EnableBoredEventConversations=1; activity-transport.key beside Stobe.dll)
#>
param([Parameter(Position = 0, Mandatory = $true)][string]$Rig, [string]$Defs = '')
$ErrorActionPreference = 'Continue'
$rigHost = 'DESKTOP-NQQPA73'
function Out-R([string]$item, [bool]$ok, [string]$ev) { $script:nfail += $(if ($ok) { 0 } else { 1 }); "RESULT lane-isolation $item $(if ($ok) { 'PASS' } else { 'FAIL' }) $ev" }
$script:nfail = 0
# lane-config-check.ps1 (ini: no BOM / one [Settings] / EnableBoredEventConversations=1; key beside Stobe.dll): WARNING lines only, never a FAIL
$script:laneCfgDir = Split-Path -Parent $MyInvocation.MyCommand.Path
function Emit-LaneConfigWarn([string]$r) {
  $cc = Join-Path $script:laneCfgDir 'lane-config-check.ps1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $cc $r 2>&1 | Where-Object { $_ -match '^RESULT lane-config' -and $_ -notmatch ' boot ' } | ForEach-Object { ("$_" -replace '^RESULT lane-config', 'RESULT lane-isolation lane-config') }
}
if ($Rig -eq '5090') { & "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\lane-isolation-check-5090.ps1" @(if ($Defs) { '-Registry'; $Defs }); $rc5 = $LASTEXITCODE; if (-not $Defs) { Emit-LaneConfigWarn '5090' }; exit $rc5 }
if ($Rig -ne '4080') { "RESULT lane-isolation setup FAIL rig '$Rig' has no lane definitions (4080, 5090)"; exit 2 }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------- 5090 side: push to the 4080, run there, add the marker item ----------------
if ($env:COMPUTERNAME -ne $rigHost) {
  $d = if ($Defs) { $Defs } else { Join-Path $here 'lane-defs.4080.json' }
  $dd = Get-Content $d -Raw | ConvertFrom-Json
  & scp -q "$here\lane-isolation-check.ps1" $d "$here\lane-llm-apply-4080.sh" 4080:C:/KenshiTestRuns/lane-i4/
  $remote = & ssh -o BatchMode=yes 4080 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiTestRuns\lane-i4\lane-isolation-check.ps1 4080 -Defs C:\KenshiTestRuns\lane-i4\lane-defs.4080.json'
  $rc = $LASTEXITCODE
  $remote
  # markers: files on THIS PC (the coordinator/session-start/Stop hook read C:\KenshiTestRuns\inflight\4080-*)
  $running = @{}
  foreach ($l in $remote) { if ($l -match '^RUNNING (\S+)') { $running[$Matches[1]] = $true } }
  $mk = @{}; $bad = @(); $ev = @()
  foreach ($p in $dd.lanes.PSObject.Properties) {
    $f = $p.Value.marker
    $mk[$p.Name] = $f
    $ex = Test-Path $f
    $ev += "$($p.Name)=$(Split-Path $f -Leaf)($(if ($ex) { 'present' } else { 'absent' }))"
    if ($running.ContainsKey($p.Name) -and -not $ex) { $bad += "$($p.Name) game running but marker $f missing" }
  }
  if (@($mk.Values | Select-Object -Unique).Count -ne $mk.Count) { $bad += 'two lanes share one marker file' }
  Out-R 'markers' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { $ev -join ' ' }))
  if (-not $Defs) { Emit-LaneConfigWarn '4080' }
  exit $(if ($rc -ne 0 -or $script:nfail -gt 0) { 1 } else { 0 })
}

# ---------------- 4080 side ----------------
if (-not $Defs) { $Defs = 'C:\KenshiTestRuns\lane-i4\lane-defs.4080.json' }
$D = Get-Content $Defs -Raw | ConvertFrom-Json
$lanes = @($D.lanes.PSObject.Properties | ForEach-Object { $o = $_.Value; $o | Add-Member -NotePropertyName id -NotePropertyValue $_.Name -Force -PassThru })
$distro = $D.wsl_distro
$inst1 = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi'
Add-Type @'
using System; using System.IO; using System.Runtime.InteropServices;
public static class KLaneLinks {
  [StructLayout(LayoutKind.Sequential)] struct BHFI { public uint a, c1, c2, la1, la2, lw1, lw2, vsn, sh, sl, n, ih, il; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h, out BHFI i);
  public static int Count(string p) { try { using (var fs = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) { BHFI i; return GetFileInformationByHandle(fs.SafeFileHandle, out i) ? (int)i.n : -1; } } catch { return -2; } }
}
'@
function IsReparse([string]$p) { $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; [bool]($i -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) }
function WslRun([string]$bash) {
  $f = "C:\KenshiTestRuns\lane-i4\tmp-$([guid]::NewGuid().ToString('N').Substring(0, 10)).sh"
  [IO.File]::WriteAllText($f, ($bash -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
  $w = '/mnt/c/KenshiTestRuns/lane-i4/' + (Split-Path $f -Leaf)
  $out = & wsl.exe -d $distro -u root --cd / -- bash $w 2>&1
  Remove-Item $f -Force -ErrorAction SilentlyContinue
  @($out | ForEach-Object { "$_" })
}
# Get-Process .Path is null over ssh (other session); the CIM/WMI process table always carries ExecutablePath
$procs = @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; ExecutablePath = $_.ExecutablePath } })
# ',' keeps a single match an array (a lone pscustomobject has no .Count)
function LaneProcs($L) { $pre = $L.dir.TrimEnd('\') + '\'; ,@($procs | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) }) }
foreach ($L in $lanes) { if ((LaneProcs $L).Count) { "RUNNING $($L.id) pid=$(((LaneProcs $L) | ForEach-Object ProcessId) -join ',')" } }

# 1 install-dirs
$bad = @(); $ev = @()
$paths = @($lanes | ForEach-Object { $_.dir.ToLower() })
if (@($paths | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'lane dirs not distinct' }
foreach ($L in $lanes) {
  if (-not (Test-Path "$($L.dir)\kenshi_x64.exe")) { $bad += "$($L.id): no kenshi_x64.exe in $($L.dir)"; continue }
  if ($L.dir.ToLower() -eq $inst1.ToLower()) { $bad += "$($L.id) is the Steam install" }
  foreach ($rel in 'mods\Stobe', 'mods\AutomationHarness', 'mods\KenshiFP', 'RE_Kenshi\mods\Stobe') {
    $p = Join-Path $L.dir $rel
    if (-not (Test-Path $p)) { $bad += "$($L.id): missing $rel" } elseif (IsReparse $p) { $bad += "$($L.id): $rel is a junction" }
  }
  $pr = LaneProcs $L; if ($pr.Count -gt 1) { $bad += "$($L.id): $($pr.Count) game processes" }
  $ev += "$($L.id)=$($L.dir) real-dirs=4 pid=$(if ($pr.Count) { $pr[0].ProcessId } else { 'not-running' })"
}
foreach ($p in $procs) { $own = @($lanes | Where-Object { $p.ExecutablePath -and $p.ExecutablePath.StartsWith($_.dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }); if (-not $own.Count -and $p.ExecutablePath -notlike "$inst1*") { $bad += "stray kenshi pid $($p.ProcessId) $($p.ExecutablePath)" } }
Out-R 'install-dirs' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { $ev -join ' ' }))

# 2 logs
$bad = @(); $ev = @(); $seen = @{}
foreach ($L in $lanes) {
  foreach ($rel in 'RE_Kenshi\mods\Stobe\stobe.log', 'mods\AutomationHarness\harness.log', 'KenshiFP.log') {
    $p = Join-Path $L.dir $rel; $key = $p.ToLower()
    if ($seen[$key]) { $bad += "log path shared: $p" }; $seen[$key] = 1
    if (Test-Path $p) { $n = [KLaneLinks]::Count($p); if ($n -ne 1) { $bad += "$p link count $n" } } else { $ev += "$($L.id):$(Split-Path $rel -Leaf)=absent(ok before first run)" }
  }
}
Out-R 'logs' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "6 distinct log paths, link count 1 where present; $($ev -join ' ')" }))

# 3 harness-channel
$bad = @(); $ev = @()
$hd = @($lanes | ForEach-Object { (Join-Path $_.dir 'mods\AutomationHarness').ToLower() })
if (@($hd | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'harness dirs not distinct' }
foreach ($L in $lanes) {
  $h = Join-Path $L.dir 'mods\AutomationHarness'
  foreach ($f in 'inbox.txt', 'inbox.txt.lock', 'outbox.txt') { $p = Join-Path $h $f; if (Test-Path $p) { $n = [KLaneLinks]::Count($p); if ($n -ne 1) { $bad += "$p link count $n" } } }
  $pr = LaneProcs $L
  foreach ($p in $pr) {
    $ls = @(Get-NetTCPConnection -State Listen -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue)
    if ($ls.Count) { $bad += "$($L.id) game pid $($p.ProcessId) listens on $((($ls | ForEach-Object LocalPort) | Select-Object -Unique) -join ',')" }
  }
  $ev += "$($L.id)=$h"
}
Out-R 'harness-channel' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "file-based inbox/outbox per lane, no TCP listener, no pipe: $($ev -join ' ')" }))

# 4 saves
$bad = @(); $ev = @()
$names = @($lanes | ForEach-Object { $_.save.ToLower() })
if (@($names | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'save names not distinct' }
foreach ($L in $lanes) {
  $set = (Get-Content (Join-Path $L.dir 'settings.cfg') | Where-Object { $_ -like 'User save location=*' }) -join ''
  if ($set -ne 'User save location=0') { $bad += "$($L.id): settings.cfg '$set'" }
  $sd = Join-Path $L.dir "save\$($L.save)"
  if (-not (Test-Path $sd)) { $bad += "$($L.id): save dir $sd missing"; continue }
  if (IsReparse $sd) { $bad += "$($L.id): save dir is a junction" }
  $nf = 0; foreach ($f in Get-ChildItem $sd -Recurse -File -ErrorAction SilentlyContinue) { $nf++; if ([KLaneLinks]::Count($f.FullName) -gt 1) { $bad += "$($L.id): save file hard-linked $($f.Name)"; break } }
  foreach ($O in $lanes) { if ($O.id -ne $L.id -and (Test-Path (Join-Path $L.dir "save\$($O.save)"))) { $bad += "$($L.id) holds the other lane's save $($O.save)" } }
  $ev += "$($L.id)=$($L.save)($nf files)"
}
Out-R 'saves' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "own save dirs, link count 1, user-save-location=0: $($ev -join ' ')" }))

# ---- WSL probes (backends) ----
$specs = ($lanes | ForEach-Object { "$($_.id):$($_.backend_root):$($_.php_port):$($_.bridge_port):$($_.pg_port):$($_.db)" }) -join ' '
$probe = @'
for spec in "$@"; do IFS=: read id root php br pg db <<<"$spec"
 echo "L $id root_real=$(readlink -f $root) site_real=$(readlink -f $root/site) site_link=$([ -L $root/site ] && echo 1 || echo 0) log_real=$(readlink -f $root/site/log)"
 for kind in php br; do p=${!kind}; pid=$(ss -ltnpH "sport = :$p" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1)
   echo "L $id ${kind}_listen=${pid:-none} ${kind}_cmd=$( [ -n "$pid" ] && tr '\0' ' ' </proc/$pid/cmdline || true)"; done
 echo "L $id pg_sock=$([ -S $root/socket/.s.PGSQL.$pg ] && echo 1 || echo 0) pgdata_real=$(readlink -f $root/pgdata) pg_ident=$(/usr/lib/postgresql/15/bin/pg_controldata $root/pgdata 2>/dev/null | awk -F: '/system identifier/{gsub(/ /,"",$2);print $2}')"
 echo "L $id db_now=$(runuser -u postgres -- psql -h $root/socket -p $pg -d $db -Atc 'select current_database()' 2>&1 | head -1) pg_port_setting=$(runuser -u postgres -- psql -h $root/socket -p $pg -d $db -Atc "select setting from pg_settings where name='port'" 2>&1 | head -1)"
 echo "L $id health=$(curl -s -m 8 http://127.0.0.1:$php/health.php | grep -oE '"status":"[a-z]+"' | head -1)"
 echo "L $id env=$(grep -oE 'STOBE_DB_NAME=[^ ]+|PGPORT=[0-9]+|STOBE_DB_HOST=[^ ]+' $root/env.sh 2>/dev/null | tr '\n' ',')"
 echo "L $id keysha=$(sha256sum $root/activity-transport.key 2>/dev/null | cut -c1-16)"
 mp=$(cat $root/manager.pid 2>/dev/null || true); echo "L $id manager_pid=${mp:-none} manager_cmd=$( [ -n "$mp" ] && tr '\0' ' ' </proc/$mp/cmdline 2>/dev/null || true) lockfile=$([ -f $root/manager.lock ] && echo 1 || echo 0)"
done
echo "G apache_procs=$(pgrep -c apache2 || true) listen80_443=$(ss -ltnH 'sport = :80 or sport = :443' 2>/dev/null | wc -l)"
'@
$probe = "set +e`n" + $probe + "`n"
$pf = "C:\KenshiTestRuns\lane-i4\tmp-probe-$([guid]::NewGuid().ToString('N').Substring(0, 8)).sh"
[IO.File]::WriteAllText($pf, ($probe -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$wp = '/mnt/c/KenshiTestRuns/lane-i4/' + (Split-Path $pf -Leaf)
$po = @(& wsl.exe -d $distro -u root --cd / -- bash $wp @($specs -split ' ') 2>&1 | ForEach-Object { "$_" })
Remove-Item $pf -Force -ErrorAction SilentlyContinue
$W = @{}; $G = ''
foreach ($l in $po) {
  if ($l -match '^L (\S+) (.*)$') { $id = $Matches[1]; if (-not $W[$id]) { $W[$id] = @{} }; foreach ($m in [regex]::Matches($Matches[2], '(\w+)=(.*?)(?=\s\w+=|$)')) { $W[$id][$m.Groups[1].Value] = $m.Groups[2].Value.Trim() } }
  elseif ($l -match '^G (.*)$') { $G = $Matches[1] }
}
function Wv($id, $k) { if ($W[$id] -and $W[$id].ContainsKey($k)) { $W[$id][$k] } else { '' } }

# 5 backend-ports
$bad = @(); $ev = @()
$allp = @($lanes | ForEach-Object { $_.php_port; $_.bridge_port; $_.pg_port })
if (@($allp | Select-Object -Unique).Count -ne $allp.Count) { $bad += 'ports not distinct' }
foreach ($L in $lanes) {
  if ((Wv $L.id 'php_cmd') -notmatch [regex]::Escape("-t $($L.backend_root)/site")) { $bad += "$($L.id): php :$($L.php_port) listener is not from $($L.backend_root)/site ($(Wv $L.id 'php_cmd'))" }
  if ((Wv $L.id 'br_listen') -eq 'none') { $bad += "$($L.id): bridge :$($L.bridge_port) not listening" }
  if ((Wv $L.id 'health') -ne '"status":"ok"') { $bad += "$($L.id): health.php '$(Wv $L.id 'health')'" }
  foreach ($ini in 'Stobe.ini', 'StobeCustom.ini') {
    $f = Join-Path $L.dir "RE_Kenshi\mods\Stobe\$ini"
    $pp = ((Get-Content $f -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ServerPort=' }) -replace 'ServerPort=', '' | Select-Object -First 1)
    if ("$pp".Trim() -ne "$($L.php_port)") { $bad += "$($L.id): $ini ServerPort='$pp' want $($L.php_port)" }
  }
  $ev += "$($L.id)=php:$($L.php_port)/bridge:$($L.bridge_port)/pg:$($L.pg_port)"
}
Out-R 'backend-ports' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "$($ev -join ' ') distinct, listeners from own roots, health ok, game ini ServerPort = own php port" }))

# 6 backend-db
$bad = @(); $ev = @()
$ids = @($lanes | ForEach-Object { Wv $_.id 'pg_ident' })
if (@($ids | Select-Object -Unique).Count -ne $lanes.Count -or ($ids -contains '')) { $bad += "cluster system identifiers not distinct/readable: $($ids -join ',')" }
$pgd = @($lanes | ForEach-Object { Wv $_.id 'pgdata_real' }); if (@($pgd | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'pgdata dirs not distinct' }
foreach ($L in $lanes) {
  if ((Wv $L.id 'db_now') -ne $L.db) { $bad += "$($L.id): current_database '$(Wv $L.id 'db_now')' want $($L.db)" }
  if ((Wv $L.id 'pg_port_setting') -ne "$($L.pg_port)") { $bad += "$($L.id): cluster port '$(Wv $L.id 'pg_port_setting')'" }
  if ((Wv $L.id 'pg_sock') -ne '1') { $bad += "$($L.id): no unix socket for port $($L.pg_port)" }
  $ev += "$($L.id)=$($L.db)@$($L.pg_port) ident=$((Wv $L.id 'pg_ident').Substring(0, [Math]::Min(8, (Wv $L.id 'pg_ident').Length)))"
}
Out-R 'backend-db' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "separate clusters: $($ev -join ' ')" }))

# 7 backend-php
$bad = @()
if ($G -notmatch 'apache_procs=0\b') { $bad += "apache2 running ($G)" }
if ($G -notmatch 'listen80_443=0\b') { $bad += "a listener on 80/443 ($G)" }
$sr = @($lanes | ForEach-Object { Wv $_.id 'site_real' }); if (@($sr | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'docroots not distinct' }
$lg = @($lanes | ForEach-Object { Wv $_.id 'log_real' }); if (@($lg | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'log dirs not distinct' }
foreach ($L in $lanes) { $s = Wv $L.id 'site_real'; if ($s -like '/var/www/*' -or $s -notlike "$($L.backend_root)*") { $bad += "$($L.id): docroot $s" }; if ((Wv $L.id 'site_link') -ne '0') { $bad += "$($L.id): site is a symlink" } }
Out-R 'backend-php' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "php -S per lane, docroots $($sr -join ' , '), $G" }))

# 8 tmp-env
$bad = @()
$rr = @($lanes | ForEach-Object { Wv $_.id 'root_real' }); if (@($rr | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'backend roots not distinct' }
foreach ($L in $lanes) {
  $e = Wv $L.id 'env'
  if ($e -notmatch "STOBE_DB_NAME=$($L.db)\b") { $bad += "$($L.id): env.sh db ($e)" }
  if ($e -notmatch "PGPORT=$($L.pg_port)\b") { $bad += "$($L.id): env.sh PGPORT ($e)" }
  if ($e -notmatch [regex]::Escape("STOBE_DB_HOST=$($L.backend_root)/socket")) { $bad += "$($L.id): env.sh socket ($e)" }
  $mc = Wv $L.id 'manager_cmd'; if ($mc -notmatch [regex]::Escape("$($L.backend_root)/manager.sh")) { $bad += "$($L.id): manager not from own root ($mc)" }
}
Out-R 'tmp-env' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "roots $($rr -join ' , '), own env.sh/socket/manager" }))

# 9 activity-key
$bad = @(); $ev = @()
$ks = @($lanes | ForEach-Object { Wv $_.id 'keysha' }); if (@($ks | Select-Object -Unique).Count -ne $lanes.Count -or ($ks -contains '')) { $bad += "server keys not distinct/readable ($($ks -join ','))" }
foreach ($L in $lanes) {
  $kf = Join-Path $L.dir 'mods\Stobe\activity-transport.key'
  if (-not (Test-Path $kf)) { $bad += "$($L.id): no game-side key"; continue }
  $gs = (Get-FileHash $kf -Algorithm SHA256).Hash.ToLower().Substring(0, 16)
  if ($gs -ne (Wv $L.id 'keysha')) { $bad += "$($L.id): game key $gs != server key $(Wv $L.id 'keysha')" }
  if ([KLaneLinks]::Count($kf) -ne 1) { $bad += "$($L.id): game key file is hard-linked" }
  $ev += "$($L.id)=$gs"
}
Out-R 'activity-key' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "server key = game key per lane, distinct: $($ev -join ' ') (sha256 prefix only)" }))

# ---- desktop-session probes (windows) ----
function Ctl([string[]]$a) { @(& powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\ctl.ps1 @a 2>&1 | ForEach-Object { "$_" }) }
$mon = Ctl @('monitors')
$mons = @(); foreach ($l in $mon) { if ($l -match '\\\\\.\\(DISPLAY\d+)\s+(-?\d+),(-?\d+)\s+(\d+)x(\d+)') { $mons += [pscustomobject]@{ n = $Matches[1]; x = [int]$Matches[2]; y = [int]$Matches[3]; w = [int]$Matches[4]; h = [int]$Matches[5] } } }
$rects = @{}
foreach ($L in $lanes) {
  if ((LaneProcs $L).Count) {
    $w = (Ctl @('window', '-Instance', "$($L.instance)")) -join ' '
    if ($w -match 'rect=(-?\d+),(-?\d+) (\d+)x(\d+)') { $rects[$L.id] = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]) }
    $rects["fg-$($L.id)"] = $w
  }
}
# 10 windows
$bad = @(); $ev = @(); $stk = @()
foreach ($L in $lanes) {
  $cfg = (Get-Content (Join-Path $L.dir 'kenshi.cfg') | Where-Object { $_ -like 'Full Screen=*' }) -join ''
  if ($cfg -ne 'Full Screen=No') { $bad += "$($L.id): kenshi.cfg '$cfg' (must be windowed; applies at next launch)" }
  $r = $rects[$L.id]
  if (-not $r) { $sz = $L.window_size -split 'x'; $pos = $L.window_pos -split ','; $r = @([int]$pos[0], [int]$pos[1], [int]$sz[0], [int]$sz[1]); $ev += "$($L.id)=configured $($r -join ',')" } else { $ev += "$($L.id)=live $($r -join ',')" }
  $rects["use-$($L.id)"] = $r
  foreach ($m in $mons) { if ($D.displays_allowed -notcontains $m.n -and ($r[0] -lt $m.x + $m.w -and $r[0] + $r[2] -gt $m.x -and $r[1] -lt $m.y + $m.h -and $r[1] + $r[3] -gt $m.y)) { $bad += "$($L.id) rect overlaps forbidden display $($m.n)" } }
  if ($rects["fg-$($L.id)"] -match 'foreground=\S*kenshi') { $bad += "$($L.id): game holds the foreground" }
}
for ($i = 0; $i -lt $lanes.Count; $i++) { for ($j = $i + 1; $j -lt $lanes.Count; $j++) {
  $a = $rects["use-$($lanes[$i].id)"]; $b = $rects["use-$($lanes[$j].id)"]
  if ($a[0] -lt $b[0] + $b[2] -and $a[0] + $a[2] -gt $b[0] -and $a[1] -lt $b[1] + $b[3] -and $a[1] + $a[3] -gt $b[1]) {   # stacked windows (imm26-winstack): allowed unless one of the two holds the foreground (forbidden-display check above is unchanged)
    $fgs = @($lanes[$i].id, $lanes[$j].id | Where-Object { $rects["fg-$_"] -match 'foreground=\S*kenshi' })
    if ($fgs.Count) { $bad += "rects of $($lanes[$i].id) and $($lanes[$j].id) overlap and $($fgs -join ',') holds the foreground" } else { $stk += "$($lanes[$i].id)>$($lanes[$j].id)" } } } }
Out-R 'windows' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "windowed, off forbidden displays, overlap only as stacked windows (monitors: $(($mons | ForEach-Object { $_.n }) -join ',')): stacked=[$($stk -join ',')] $($ev -join ' ')" }))

# 11 graphics
$bad = @(); $ev = @()
foreach ($L in $lanes) {
  $ga = Join-Path $L.dir 'gfx.applied'; $mode = if (Test-Path $ga) { (Get-Content $ga -TotalCount 1).Trim() } else { 'none' }
  $cf = Join-Path $L.dir 'mods\AutomationHarness\framecap.txt'; $cap = if (Test-Path $cf) { (Get-Content $cf -TotalCount 1).Trim() } else { 'off' }
  $vm = ((Get-Content (Join-Path $L.dir 'kenshi.cfg') | Where-Object { $_ -like 'Video Mode=*' }) -replace 'Video Mode=', '')
  if ($mode -ne 'low') { $bad += "$($L.id): gfx.applied=$mode (want low)" }
  if ($cap -ne '60') { $bad += "$($L.id): frame cap $cap (want 60)" }
  if ($vm -match '^(\d+) x ') { if ([int]$Matches[1] -gt 1600) { $bad += "$($L.id): Video Mode $vm" } }
  $ev += "$($L.id)=gfx:$mode cap:$cap vm:$vm"
}
Out-R 'graphics' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { $ev -join ' ' }))

# 12 locks
$bad = @(); $ev = @()
$lk = @($lanes | ForEach-Object { $_.lock.ToLower() }); if (@($lk | Select-Object -Unique).Count -ne $lanes.Count) { $bad += 'lock files not distinct' }
foreach ($L in $lanes) {
  if ($L.lock -like '*\game.lock') { $bad += "$($L.id) uses the instance-1 game.lock" }
  $run = (LaneProcs $L).Count -gt 0; $ex = Test-Path $L.lock
  if ($run -and -not $ex) { $bad += "$($L.id): game running but $($L.lock) missing" }
  $ev += "$($L.id)=$(Split-Path $L.lock -Leaf)($(if ($ex) { 'held by ' + (Get-Content $L.lock -TotalCount 1) } else { 'free' }))"
}
Out-R 'locks' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { $ev -join ' ' }))

# 13 shared-mutable
$mut = @('.cfg', '.ini', '.txt', '.json', '.log', '.sc', '.zip', '.dll', '.exe', '.asi', '.tsv', '.flag', '.bolt', '.csv', '.def', '.bat', '.hkt', '.xml', '.key')
$skip = @('save', 'logs', '_screens')
$bad = @(); $ev = @()
foreach ($L in $lanes) {
  $nl = 0; $nj = 0; $stack = New-Object System.Collections.Stack; $stack.Push('')
  while ($stack.Count) {
    $rel = $stack.Pop(); $dir = if ($rel) { Join-Path $L.dir $rel } else { $L.dir }
    foreach ($c in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
      $r = if ($rel) { "$rel\$($c.Name)" } else { $c.Name }
      if ($skip -contains $r) { continue }
      if ($c.PSIsContainer) {
        if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) {
          $nj++; $t = "$($c.Target)"
          if ($t -notlike "$inst1*") { $bad += "$($L.id): junction $r -> $t (not into the Steam install)"; continue }
          $m = $null; foreach ($f in [IO.Directory]::EnumerateFiles($c.FullName, '*', [IO.SearchOption]::AllDirectories)) { if ($mut -contains [IO.Path]::GetExtension($f).ToLower()) { $m = $f; break } }
          if ($m) { $bad += "$($L.id): junction $r reaches mutable file $m" }
        } else { $stack.Push($r) }
        continue
      }
      if ($mut -contains $c.Extension.ToLower() -and $c.Length -gt 0) { $n = [KLaneLinks]::Count($c.FullName); if ($n -gt 1) { $bad += "$($L.id): mutable file hard-linked ($n): $r" } }
      $nl++
    }
  }
  $ev += "$($L.id)=$nj junctions(read-only content) $nl files scanned"
}
Out-R 'shared-mutable' ($bad.Count -eq 0) ($(if ($bad.Count) { ($bad | Select-Object -First 6) -join '; ' } else { $ev -join ' ' }))

# 14 llm-config
$lo = @(WslRun "bash /mnt/c/KenshiTestRuns/lane-i4/lane-llm-apply-4080.sh --check all --defs /mnt/c/KenshiTestRuns/lane-i4/lane-defs.4080.json")
$lr = @($lo | Where-Object { $_ -like 'RESULT lane-llm*' })
$ok = ($lr.Count -eq $lanes.Count) -and (@($lr | Where-Object { $_ -notlike '* PASS *' }).Count -eq 0)
Out-R 'llm-config' $ok ($(if ($lr.Count) { ($lr | ForEach-Object { $_ -replace '^RESULT lane-llm ', '' }) -join ' | ' } else { ($lo | Select-Object -First 2) -join ' ' }))

# 15 log-crosstalk
$bad = @(); $ev = @()
function Tokens($O) {
  $sv = [regex]::Escape($O.save); $dbn = [regex]::Escape($O.db); $rt = [regex]::Escape($O.backend_root)
  $dr = [regex]::Escape($O.dir); $drf = [regex]::Escape(($O.dir -replace '\\', '/'))
  @{ port = "(127\.0\.0\.1|localhost):($($O.php_port)|$($O.bridge_port))(?!\d)|ServerPort=$($O.php_port)(?!\d)"; save = "(?<![\w-])$sv(?![\w-])"; db = "(?<![\w-])$dbn(?![\w-])"; root = "$rt(?![\w-])"; dir = "(?i)($dr|$drf)(?![\w-])" }
}
$lines = 0
foreach ($L in $lanes) {
  foreach ($O in $lanes) {
    if ($O.id -eq $L.id) { continue }
    $tk = Tokens $O
    foreach ($rel in 'RE_Kenshi\mods\Stobe\stobe.log', 'RE_Kenshi\mods\Stobe\stobe_goals.log', 'mods\AutomationHarness\harness.log', 'KenshiFP.log') {
      $p = Join-Path $L.dir $rel; if (-not (Test-Path $p)) { continue }
      foreach ($name in $tk.Keys) {
        $re = New-Object Text.RegularExpressions.Regex($tk[$name], 'IgnoreCase')
        $hit = $null
        $fs = New-Object IO.FileStream($p, 'Open', 'Read', 'ReadWrite,Delete'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        try { while (($ln = $sr.ReadLine()) -ne $null) { $lines++; if ($re.IsMatch($ln)) { $hit = $ln; break } } } finally { $sr.Dispose() }
        if ($hit) { $bad += "$($L.id) $(Split-Path $rel -Leaf) mentions $($O.id) $($name): $($hit.Substring(0, [Math]::Min(100, $hit.Length)))" }
      }
    }
    # backend logs (WSL)
    $script = "cd $($L.backend_root)`nfor f in php.log site/log/php_error.log site/log/output_to_plugin.log site/log/context_sent_to_llm.log site/log/chat_llm_full_capture.log site/log/stobeserver.log; do [ -f `$f ] || continue`n"
    $pairs = @(@('port', "127\.0\.0\.1:($($O.php_port)|$($O.bridge_port))([^0-9]|$)|ServerPort=$($O.php_port)([^0-9]|$)"), @('save', "(^|[^A-Za-z0-9_-])$([regex]::Escape($O.save))([^A-Za-z0-9_-]|$)"), @('db', "(^|[^A-Za-z0-9_-])$($O.db)([^A-Za-z0-9_-]|$)"), @('root', "$($O.backend_root)([^A-Za-z0-9_-]|$)"))
    foreach ($pr in $pairs) { $script += " c=`$(grep -aEc '$($pr[1])' `$f 2>/dev/null); [ `"`${c:-0}`" -gt 0 ] && echo `"HIT `$f $($pr[0]) `$c`"`n" }
    $script += "done`necho SCAN_DONE`n"
    $bo = @(WslRun $script)
    if ($bo -notcontains 'SCAN_DONE') { $bad += "$($L.id): backend log scan failed ($($bo -join ' '))" }
    foreach ($h in ($bo | Where-Object { $_ -like 'HIT *' })) { $bad += "$($L.id) backend $h (other lane $($O.id))" }
  }
}
Out-R 'log-crosstalk' ($bad.Count -eq 0) ($(if ($bad.Count) { ($bad | Select-Object -First 5) -join '; ' } else { "game logs ($lines lines) + backend logs of each lane never mention the other lane's port/save/db/root/dir" }))

# 16 npc-world
$bad = @(); $ev = @()
foreach ($L in $lanes) {
  if (-not (LaneProcs $L).Count) { $ev += "$($L.id)=not running (configured save $($L.save))"; continue }
  $env:KAH_DIR = Join-Path $L.dir 'mods\AutomationHarness'
  $st = (& python C:\KAH\client\kah.py status 2>&1 | Select-Object -First 1) -join ''
  if ($st -match 'save=(\S+)') { if ($Matches[1] -ne $L.save) { $bad += "$($L.id): game reports save '$($Matches[1])' want $($L.save)" } else { $ev += "$($L.id)=$($Matches[1])" } } else { $bad += "$($L.id): status gave no save ($st)" }
}
Remove-Item Env:\KAH_DIR -ErrorAction SilentlyContinue
Out-R 'npc-world' ($bad.Count -eq 0) ($(if ($bad.Count) { $bad -join '; ' } else { "each game reports its own save (separate copies, link count 1, no shared world file): $($ev -join ' ')" }))

# 17 resources
$os = Get-CimInstance Win32_OperatingSystem
$tot = $os.TotalVisibleMemorySize / 1024; $used = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024; $pct = [int](100 * $used / $tot)
$gpu = (& nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>$null) -split ',\s*'
$vp = if ($gpu.Count -ge 2) { [int](100 * [double]$gpu[0] / [double]$gpu[1]) } else { -1 }
$cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
$pp = @(Get-Process kenshi_x64, llama-server -ErrorAction SilentlyContinue | ForEach-Object { "$($_.ProcessName)#$($_.Id)=ws$([int]($_.WorkingSet64/1MB))MB/priv$([int]($_.PrivateMemorySize64/1MB))MB" })
Out-R 'resources' ($pct -lt 85 -and $vp -lt 90) ("ram=$([int]$used)/$([int]$tot)MB($pct%) vram=$($gpu[0])/$($gpu[1])MB($vp%) gpu_util=$($gpu[2])% cpu=$([int]$cpu)% $($pp -join ' ')")
exit $(if ($script:nfail -gt 0) { 1 } else { 0 })
