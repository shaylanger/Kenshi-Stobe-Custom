<#
kenshi-ctl.ps1 (workspace): the harness repo's kenshi-ctl.ps1 with this PC's
paths; also archives stobe.log, KenshiFP.log and ProfessionGear.log/affixes
(all reset or rewritten on launch).
Commands: status | launch [-Save x] | stop | restart [-Save x] | health | screenshot [-Save n] | lock | release

Game lock (C:\KenshiTestRuns\game.lock): only one session drives Kenshi.
launch/stop/restart take the lock for $env:KAH_OWNER (default 'coordinator')
and refuse if another owner holds it. `release` frees it (owner only),
`lock` shows it. See MASTER_TEST_PLAN.md "How this works".

Background runs (default for launch/restart, Shay 2026-10-07): the game opens on
-Monitor (default $env:KENSHI_MONITOR, else DISPLAY1) without taking the focus
(if it grabs it during the launch, it goes back to the window that had it),
and starts with harness input isolation ON: real keys/mouse ignored, cursor
never clipped, input only via `stobe-auto key_inject|mouse_inject` (kenshi-key.ps1 /
kenshi-click.ps1 switch to those by themselves), game keeps running unfocused.
-Play: a normal launch for Shay (no monitor move, focus allowed, isolation off).
Also: monitors | place [-Monitor x] | window (which monitor, who has the focus).

Windowed test runs (Shay, 2026-10-08: m72 ran exclusive-fullscreen on DISPLAY2 and
interrupted him): every non -Play launch first sets kenshi.cfg to Full Screen=No,
Video Mode=1600 x 900 (fits DISPLAY2, 1920x1080) and keeps Shay's own values in
C:\KenshiTestRuns\kenshi.cfg.play; -Play (and `cfg play`, also run by gfx-mods.sh on)
writes them back. `cfg status|test|play` shows/applies the two modes.
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Save = '',
  [int]$TimeoutSec = 300,
  [string]$Monitor = $(if ($env:KENSHI_MONITOR) { $env:KENSHI_MONITOR } else { 'DISPLAY2' }),
  [switch]$Play,
  [Parameter(Position = 1)][string]$Mode = 'status'
)
$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
$LockFile = 'C:\KenshiTestRuns\game.lock'
$Owner = if ($env:KAH_OWNER) { $env:KAH_OWNER } else { 'coordinator' }
$Cfg = "$Kenshi\kenshi.cfg"
$CfgPlay = 'C:\KenshiTestRuns\kenshi.cfg.play'
$TestCfg = @{ 'Full Screen' = 'No'; 'Video Mode' = '1600 x 900 @ 32-bit colour [0]' }

function Get-CfgValues {
  $v = @{}
  foreach ($line in Get-Content $Cfg) { foreach ($k in $TestCfg.Keys) { if ($line -like "$k=*") { $v[$k] = $line.Substring($k.Length + 1) } } }
  $v
}
function Set-CfgValues([hashtable]$Want) {
  $out = foreach ($line in Get-Content $Cfg) {
    $hit = $null; foreach ($k in $Want.Keys) { if ($line -like "$k=*") { $hit = $k } }
    if ($hit) { "$hit=$($Want[$hit])" } else { $line }
  }
  Set-Content -Path $Cfg -Value $out -Encoding Ascii
}
function Cfg-Status {
  $cur = Get-CfgValues
  $isTest = $true; foreach ($k in $TestCfg.Keys) { if ($cur[$k] -ne $TestCfg[$k]) { $isTest = $false } }
  $saved = if (Test-Path $CfgPlay) { (Get-Content $CfgPlay) -join '; ' } else { 'none' }
  "kenshi.cfg: $(if ($isTest) { 'TEST (windowed)' } else { 'PLAY' }) Full Screen=$($cur['Full Screen']) Video Mode=$($cur['Video Mode']); saved play values: $saved"
}
function Cfg-Test {   # windowed for automated runs; remember Shay's values once (never overwrite them with test values)
  $cur = Get-CfgValues
  $isTest = $true; foreach ($k in $TestCfg.Keys) { if ($cur[$k] -ne $TestCfg[$k]) { $isTest = $false } }
  if ($isTest) { return "kenshi.cfg already windowed for tests" }
  Set-Content -Path $CfgPlay -Value @($cur.Keys | ForEach-Object { "$_=$($cur[$_])" }) -Encoding Ascii
  Set-CfgValues $TestCfg
  "kenshi.cfg set to windowed 1600x900 for tests (play values saved: $((Get-Content $CfgPlay) -join '; '))"
}
function Cfg-Play {   # Shay's values back
  if (-not (Test-Path $CfgPlay)) { return "kenshi.cfg: no saved play values ($CfgPlay), left as is: $(Cfg-Status)" }
  $want = @{}; foreach ($line in Get-Content $CfgPlay) { $i = $line.IndexOf('='); if ($i -gt 0) { $want[$line.Substring(0, $i)] = $line.Substring($i + 1) } }
  Set-CfgValues $want
  "kenshi.cfg restored for play: $(($want.Keys | ForEach-Object { "$_=$($want[$_])" }) -join '; ')"
}

if ($Command -eq 'cfg') {
  switch ($Mode) { 'test' { Cfg-Test } 'play' { Cfg-Play } default { Cfg-Status } }
  exit 0
}

if ($Command -eq 'lock') {
  if (Test-Path $LockFile) { Get-Content $LockFile } else { 'free' }
  exit 0
}
if ($Command -eq 'release') {
  if (Test-Path $LockFile) {
    $held = (Get-Content $LockFile -TotalCount 1).Trim()
    if ($held -ne $Owner) { "lock held by '$held', not '$Owner'"; exit 1 }
    Remove-Item $LockFile -Force
  }
  'released'
  exit 0
}
if ($Command -in @('launch', 'stop', 'restart')) {
  if (Test-Path $LockFile) {
    $held = (Get-Content $LockFile -TotalCount 1).Trim()
    if ($held -ne $Owner) { "Kenshi is locked by '$held' (set KAH_OWNER or ask that session to release)"; exit 1 }
  } else {
    Set-Content -Path $LockFile -Value @($Owner, (Get-Date -Format s)) -Encoding utf8
  }
}

$bg = @{}
if (-not $Play) { $bg = @{ Monitor = $Monitor; Background = $true; Isolate = $true } }
if ($Command -in @('launch', 'restart')) {
  if ($Play) { Cfg-Play } else {
    # never open a test game on Shay's screen: refuse when the test monitor is off/disconnected (2026-10-08: DISPLAY1/2
    # vanished from the monitor list mid-session and the windowed game landed on the primary)
    $mons = & 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' monitors -Kenshi $Kenshi
    $want = '\\.\' + ($Monitor -replace '^\\\\\.\\', '').ToUpper()
    $list = @($mons -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($mons -notmatch [regex]::Escape($want) + ' ') {
      # Shay 2026-10-08: windowed + background is what matters, the monitor is a preference: when the preferred one is
      # off use the first one that is on (a single screen: that one)
      $Monitor = ($list[0] -split ' ')[0]; "test monitor $want is off: using $Monitor (windowed, background)"; $bg.Monitor = $Monitor
    }
    Cfg-Test
  }
}
& 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' $Command -Save $Save -TimeoutSec $TimeoutSec @bg `
  -Kenshi $Kenshi -ArchiveRoot 'C:\KenshiTestRuns' `
  -ExtraLogs @("$Kenshi\RE_Kenshi\mods\Stobe\stobe.log", "$Kenshi\KenshiFP.log", "$Kenshi\RE_Kenshi\mods\Stobe\stobe_goals.log",
               "$Kenshi\mods\ProfessionGearProgression\ProfessionGear.log",
               "$Kenshi\mods\ProfessionGearProgression\profession_gear_affixes.tsv")
$rc = $LASTEXITCODE
if ($rc -eq 0 -and -not $Play -and $Command -in @('launch', 'restart')) {
  # Ogre moves/resizes its window again after the launch waits (2026-10-08: ended on DISPLAY1): re-place it without
  # activating, a few times, and report where it is and who has the focus
  $ctl = 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1'
  foreach ($i in 1..3) {
    Start-Sleep -Seconds 3
    & $ctl place -Monitor $Monitor -Kenshi $Kenshi | Out-Null
  }
  "placed: $(& $ctl window -Kenshi $Kenshi)"
}
exit $rc
