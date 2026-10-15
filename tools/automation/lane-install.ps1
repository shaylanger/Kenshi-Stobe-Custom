<#
lane-install.ps1 -Lane i4|i5 [-FromLane i3] [-Check]: make the isolated 5090 imm26 lane's Kenshi copy match lane i3's tested build and point it at its OWN backend.
Prerequisite: `kenshi-instance.ps1 sync -Instance <n>` ran once (creates D:\KenshiInst\<n> from the Steam install, read-only on the Steam side).
Then this script (game of that lane must be closed; i3 is never written, only read):
  - copies from the template lane (default i3) the files that make it the imm26 test build: mods\Stobe\Stobe.dll, mods\KenshiFP\KenshiFP.{dll,ini},
    data\mods.cfg (the trimmed test mod list), mods\Stobe\Stobe.ini, RE_Kenshi\mods\Stobe\StobeCustom.ini (then ServerPort := the lane's backend_port)
  - gfx-off state like i3 (Dust RE_Kenshi.json and dxgi.dll renamed *.gfxoff)
  - removes live-install leftovers the sync mirrored: mods\Stobe\activity-transport.key, Stobe.dll.pre-* backups, crash dumps
  - copies the template lane's fixture save (kah-imm26-5090-ready) to the lane's own save_name (never shared)
  - writes C:\KenshiTestRuns\lanes\install-<lane>.json (hashes of what was installed)
-Check = read-only: prints what differs from the template, changes nothing.
Registry: C:\KenshiTestRuns\lanes\lanes-5090.json
#>
param([Parameter(Mandatory)][ValidateSet('i3', 'i4', 'i5')][string]$Lane, [string]$FromLane = 'i3', [string]$SrcSave = 'kah-imm26-5090-ready', [switch]$Check)
$ErrorActionPreference = 'Stop'
if ($Lane -eq 'i3') { throw 'i3 is the operator lane: never rewritten by this script' }
$reg = Get-Content 'C:\KenshiTestRuns\lanes\lanes-5090.json' -Raw | ConvertFrom-Json
$L = $reg.lanes | Where-Object id -eq $Lane; $T = $reg.lanes | Where-Object id -eq $FromLane
if (-not $L -or -not $T) { throw 'lane not in registry' }
if (-not (Test-Path "$($L.dir)\instance.txt")) { throw "run kenshi-instance.ps1 sync -Instance $($L.instance) first" }
$run = Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($L.dir + '\', [StringComparison]::OrdinalIgnoreCase) }
if ($run -and -not $Check) { throw "lane $Lane game is running (pid $($run.ProcessId))" }
function Hsh($p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p).Hash.Substring(0, 12) } else { '-' } }
$files = 'mods\Stobe\Stobe.dll', 'mods\Stobe\Stobe.ini', 'mods\KenshiFP\KenshiFP.dll', 'mods\KenshiFP\KenshiFP.ini', 'data\mods.cfg', 'RE_Kenshi\mods\Stobe\StobeCustom.ini'
$rec = [ordered]@{ lane = $Lane; from = $FromLane; at = (Get-Date -Format s); files = [ordered]@{} }
foreach ($f in $files) {
  $s = Join-Path $T.dir $f; $d = Join-Path $L.dir $f
  if (-not (Test-Path -LiteralPath $s)) { "SKIP $f (not in template)"; continue }
  $same = (Hsh $s) -eq (Hsh $d)
  if ($f -like '*StobeCustom.ini') { $same = $false }
  "{0} {1} template={2} lane={3}" -f $(if ($same) { 'same ' } else { 'COPY ' }), $f, (Hsh $s), (Hsh $d)
  if ($Check -or $same) { $rec.files[$f] = Hsh $d; continue }
  if ($f -like 'data\*') { $dd = Split-Path $d; if ((Get-Item $dd -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$dd is a junction into the Steam install: refusing to write" } }
  [IO.File]::Copy($s, $d, $true); $rec.files[$f] = Hsh $d
}
# port edit: ServerPort only (every [Settings] occurrence), ServerHost stays 127.0.0.1
$ini = $L.ini
if (-not $Check) {
  $txt = [IO.File]::ReadAllText($ini)
  $txt = [regex]::Replace($txt, '(?m)^ServerPort=.*$', "ServerPort=$($L.backend_port)")
  $txt = [regex]::Replace($txt, '(?m)^ServerHost=.*$', 'ServerHost=127.0.0.1')
  [IO.File]::WriteAllText($ini, $txt, (New-Object Text.UTF8Encoding $false))
  $rec.files['RE_Kenshi\mods\Stobe\StobeCustom.ini'] = Hsh $ini
}
"ini ServerPort lines: " + ((Select-String -Path $ini -Pattern '^Server(Host|Port)=' | ForEach-Object { $_.Line }) -join ' ')
# gfx-off like the template (Dust + ReShade), only when the template has them off
foreach ($pair in @(@('mods\Dust\RE_Kenshi.json', 'mods\Dust\RE_Kenshi.json.gfxoff'), @('dxgi.dll', 'dxgi.dll.gfxoff'))) {
  $tOff = Test-Path -LiteralPath (Join-Path $T.dir $pair[1]); $lOn = Test-Path -LiteralPath (Join-Path $L.dir $pair[0])
  if ($tOff -and $lOn) { "gfxoff {0}" -f $pair[0]; if (-not $Check) { Move-Item -LiteralPath (Join-Path $L.dir $pair[0]) (Join-Path $L.dir $pair[1]) -Force } }
}
# live leftovers
$junk = @(Get-ChildItem "$($L.dir)\mods\Stobe" -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'activity-transport.key' -or $_.Name -like 'Stobe.dll.pre-*' })
$junk += @(Get-ChildItem $L.dir -Force -File -Filter 'crashDump*' -ErrorAction SilentlyContinue)
foreach ($j in $junk) { "remove leftover $($j.Name)"; if (-not $Check) { Remove-Item -LiteralPath $j.FullName -Force } }
# fixture save: own copy under the lane's own save name
$from = Join-Path $T.save_dir $SrcSave; $to = Join-Path $L.save_dir $L.save_name
if (Test-Path -LiteralPath $from) {
  if (Test-Path -LiteralPath $to) { "save $($L.save_name) exists" }
  else { "save $SrcSave -> $($L.save_name)"; if (-not $Check) { $null = robocopy $from $to /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP; if ($LASTEXITCODE -ge 8) { throw "robocopy $LASTEXITCODE" } } }
} else { "SKIP save: template save $SrcSave missing" }
if (-not $Check) { New-Item -ItemType Directory -Force "$($L.harness_dir)" | Out-Null; ($rec | ConvertTo-Json -Depth 4) | Set-Content "C:\KenshiTestRuns\lanes\install-$Lane.json" -Encoding UTF8; "RESULT lane-install $Lane PASS installed from $FromLane (receipt install-$Lane.json)" }
else { "RESULT lane-install $Lane CHECK done (nothing changed)" }
