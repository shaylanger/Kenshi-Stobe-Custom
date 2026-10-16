<#
lane-config-check.ps1 <5090|4080> [-Lane i3] [-Fix] [-Defs <registry json>] [-NoNeg: skip the live backend-env item, selftests only]
Lane CONFIG preflight (imm26): the per-lane files the game reads AT LAUNCH. Prints one line per lane and item:
  `RESULT lane-config <rig>-<lane> <item> PASS|WARN|FIXED <evidence>`   (exit 1 if any WARN, 0 otherwise; read-only unless -Fix)
Items:
  ini   RE_Kenshi\mods\Stobe\StobeCustom.ini has NO UTF-8 BOM, exactly ONE [Settings] block, EnableBoredEventConversations=1 (a single value),
        ServerPort = the lane's own backend port  (live file = BOM + 2 blocks -> the BOM hid the 1st header, the 2nd (=0) won -> EnableBoredEvents=false)
  key   activity-transport.key sits beside EVERY Stobe.dll of the lane (native Secret() reads it next to the loaded DLL; the env var is forbidden on
        lane runs): mods\Stobe\ and, if a Stobe.dll is there too, RE_Kenshi\mods\Stobe\; it must equal the lane's own SERVER key (presence + equality
        by hash only, the key is never printed)
  neg   the lane BACKEND process (php -S on the lane port) has STOBE_NEG_STOBE_LOG / STOBE_NEG_KFP_LOG / STOBE_NEG_ACTION_REQUEST in its environment and each points
        inside THIS lane's own instance dir (else contract legs read Shay's live stobe.log and action requests land in his install); fix: restart-web
  boot  info only: the last `CONFIG ... EnableBoredEvents=` value in the lane's stobe.log (a running game keeps what it read at launch)
-Fix rewrites the ini (lane-ini-lib.ps1) and copies the lane's server key beside the DLL(s); it never starts/stops a game (relaunch to apply).
Rig 4080 from the 5090: copies itself + lib + defs to the 4080 (C:\KenshiTestRuns\lane-i4) and runs there over ssh.
Callable from shell: powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\lane-config-check.ps1 5090
Registries: C:\KenshiTestRuns\lanes\lanes-5090.json, tools\automation\lane-defs.4080.json.   Selftest: lane-config-selftest.ps1
#>
param([Parameter(Position = 0, Mandatory = $true)][ValidateSet('5090', '4080')][string]$Rig, [string]$Lane = '', [switch]$Fix, [string]$Defs = '', [switch]$NoNeg)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lane-ini-lib.ps1')
$rigHost = 'DESKTOP-NQQPA73'
if ($Rig -eq '4080' -and $env:COMPUTERNAME -ne $rigHost) {
  $d = if ($Defs) { $Defs } else { Join-Path $here 'lane-defs.4080.json' }
  & scp -q "$here\lane-config-check.ps1" "$here\lane-ini-lib.ps1" $d 4080:C:/KenshiTestRuns/lane-i4/
  $a = "-Rig 4080 -Defs C:\KenshiTestRuns\lane-i4\$(Split-Path -Leaf $d)"
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiTestRuns\lane-i4\lane-config-check.ps1 4080 -Defs C:\KenshiTestRuns\lane-i4\$(Split-Path -Leaf $d)" + $(if ($Lane) { " -Lane $Lane" }) + $(if ($Fix) { ' -Fix' })
  & ssh -o BatchMode=yes 4080 $cmd; exit $LASTEXITCODE
}
# ---- normalise both registries to {id, dir, port, keyWsl, distro} ----
$lanes = @()
if ($Rig -eq '5090') {
  $r = Get-Content $(if ($Defs) { $Defs } else { 'C:\KenshiTestRuns\lanes\lanes-5090.json' }) -Raw | ConvertFrom-Json
  foreach ($l in $r.lanes) { $lanes += [pscustomobject]@{ id = $l.id; dir = $l.dir; port = [int]$l.backend_port; keyWsl = $l.key_file; distro = 'DwemerAI4Skyrim3' } }
} else {
  $r = Get-Content $(if ($Defs) { $Defs } else { Join-Path $here 'lane-defs.4080.json' }) -Raw | ConvertFrom-Json
  foreach ($p in $r.lanes.PSObject.Properties) { $l = $p.Value; $lanes += [pscustomobject]@{ id = $p.Name; dir = $l.dir; port = [int]$l.php_port; keyWsl = "$($l.backend_root)/activity-transport.key"; distro = $r.wsl_distro } }
}
if ($Lane) { $lanes = @($lanes | Where-Object id -eq $Lane) }
$warn = 0
function Emit($lane, $item, $state, $ev) { if ($state -eq 'WARN') { $script:warn++ }; "RESULT lane-config $Rig-$lane $item $state $ev" }
function KeyHash([string]$t) { $sha = [Security.Cryptography.SHA256]::Create(); -join ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($t.Trim())) | ForEach-Object { $_.ToString('x2') }) }
foreach ($l in $lanes) {
  $id = $l.id
  # ---- ini ----
  $ini = Join-Path $l.dir 'RE_Kenshi\mods\Stobe\StobeCustom.ini'
  $bad = @(Test-LaneIni -Path $ini -Port $l.port)
  if ($bad.Count -and $Fix -and (Test-Path -LiteralPath $ini)) {
    $null = Write-LaneIni -Path $ini -Port $l.port; $bad2 = @(Test-LaneIni -Path $ini -Port $l.port)
    if ($bad2.Count) { Emit $id ini WARN "fix failed: $($bad2 -join '; ')" } else { Emit $id ini FIXED "was: $($bad -join '; '); now no BOM, one [Settings], EnableBoredEventConversations=1, ServerPort=$($l.port) (relaunch the lane to apply)" }
  } elseif ($bad.Count) { Emit $id ini WARN ($bad -join '; ') }
  else { Emit $id ini PASS "no BOM, one [Settings], EnableBoredEventConversations=1, ServerPort=$($l.port)" }
  # ---- key beside every Stobe.dll ----
  $srv = ''
  try { $srv = ((& wsl.exe -d $l.distro -u root --cd / -- cat $l.keyWsl 2>$null) -join '').Trim() } catch { }
  if ($srv -notmatch '^[0-9a-f]{64}$') { Emit $id key WARN "lane server key $($l.keyWsl) unreadable (backend not provisioned?)" }
  else {
    $sh = KeyHash $srv; $probs = @(); $okc = 0; $fixed = @()
    foreach ($rel in 'mods\Stobe', 'RE_Kenshi\mods\Stobe') {
      $dd = Join-Path $l.dir $rel
      if (-not (Test-Path -LiteralPath (Join-Path $dd 'Stobe.dll'))) { continue }
      $kf = Join-Path $dd 'activity-transport.key'
      $have = if (Test-Path -LiteralPath $kf) { [IO.File]::ReadAllText($kf).Trim() } else { $null }
      if ($null -ne $have -and (KeyHash $have) -eq $sh) { $okc++; continue }
      if ($Fix) { if (Test-Path -LiteralPath $kf) { Remove-Item -LiteralPath $kf -Force }; [IO.File]::WriteAllText($kf, $srv, (New-Object Text.ASCIIEncoding)); $fixed += $rel }
      else { $probs += "$rel\ $(if ($null -eq $have) { 'key missing' } else { 'key differs from the lane server key' })" }
    }
    if ($probs.Count) { Emit $id key WARN ($probs -join '; ') }
    elseif ($fixed.Count) { Emit $id key FIXED "wrote lane server key (sha256 $($sh.Substring(0,8))) beside Stobe.dll in $($fixed -join ', ') (relaunch to apply)" }
    else { Emit $id key PASS "key beside $okc Stobe.dll dir(s) equals the lane server key (sha256 $($sh.Substring(0,8)))" }
  }
  # ---- neg: the lane BACKEND process must carry its OWN negotiation paths (a lane without them verifies contract legs against Shay's live stobe.log and writes stobe_action.request into his install) ----
  if (-not $NoNeg) {
  $wd = ($l.dir -replace '\\', '/'); $wd = '/mnt/' + $wd.Substring(0, 1).ToLower() + $wd.Substring(2)
  $want = @{ STOBE_NEG_STOBE_LOG = "$wd/RE_Kenshi/mods/Stobe/stobe.log"; STOBE_NEG_KFP_LOG = "$wd/KenshiFP.log"; STOBE_NEG_ACTION_REQUEST = "$wd/RE_Kenshi/mods/Stobe/stobe_action.request" }
  $sc = 'p=$(pgrep -f ''^php -S 127.0.0.1:' + $l.port + ' '' | head -1); if [ -z $p ]; then echo NOPROC; else tr ''\0'' ''\n'' < /proc/$p/environ | grep ''^STOBE_NEG_''; fi'
  $envOut = @(); try { $envOut = @(($sc + ' #') | & wsl.exe -d $l.distro -u root --cd / -- bash -s 2>$null) } catch { }  # script via stdin: wsl.exe would expand $vars of a -c string itself
  if ($envOut -contains 'NOPROC') { Emit $id neg WARN "no php -S backend process on port $($l.port) (start the lane backend)" }
  else {
    $have = @{}; foreach ($ln in $envOut) { $k, $v = "$ln".Trim() -split '=', 2; if ($k) { $have[$k] = $v } }
    $np = @(); foreach ($k in $want.Keys) {
      if (-not $have.ContainsKey($k)) { $np += "$k missing" } elseif ($have[$k] -ne $want[$k]) { $np += "$k=$($have[$k]) (want $($want[$k]))" }
    }
    if ($np.Count) { Emit $id neg WARN ("backend env on :$($l.port): " + ($np -join '; ') + " -> run lane-backend.sh|stobe-lane-backend.sh restart-web <lane>") }
    else { Emit $id neg PASS "backend :$($l.port) STOBE_NEG_STOBE_LOG/KFP_LOG/ACTION_REQUEST all inside $wd" }
  }
  }
  # ---- boot (info) ----
  $log = Join-Path $l.dir 'RE_Kenshi\mods\Stobe\stobe.log'
  $c = if (Test-Path -LiteralPath $log) { (Select-String -LiteralPath $log -Pattern 'EnableBoredEvents=(true|false)' | Select-Object -Last 1) } else { $null }
  Emit $id boot PASS $(if ($c) { "last launch logged EnableBoredEvents=$($c.Matches[0].Groups[1].Value)" } else { 'no CONFIG line in stobe.log' })
}
exit $(if ($warn) { 1 } else { 0 })
