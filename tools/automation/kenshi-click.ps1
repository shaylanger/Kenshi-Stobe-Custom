# kenshi-click.ps1 <x> <y> [right]: left- (or right-) click Kenshi at client coordinates x,y
# (the pixel coordinates of a harness `screenshot`). FP mode hides/captures the cursor: `fp_mode off` first.
# Injected through the harness (`mouse_inject at x y` + `mouse_inject left|right click`): no focus, no real cursor.
# Needs input isolation on (mods\AutomationHarness\input_isolation.on); without it the click FAILS: it never focuses
# the game or moves the real mouse (tests must not take over Shay's screen).
# Example: kenshi-click.ps1 1507 902 (the orders panel BLOCK toggle at 1918x1079).
param([Parameter(Mandatory=$true)][int]$X, [Parameter(Mandatory=$true)][int]$Y, [string]$Button = 'left')
$iso = 'D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\input_isolation.on'
if (-not (Get-Process kenshi_x64 -ErrorAction SilentlyContinue)) { Write-Output 'CLICK FAIL Kenshi not running'; exit 1 }
if (-not (Test-Path $iso)) { Write-Output 'CLICK FAIL input isolation off (no real-mouse fallback)'; exit 1 }
$b = if ($Button -eq 'right') { 'right' } else { 'left' }
$r1 = (& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- stobe-auto mouse_inject at $X $Y 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Write-Output "CLICK FAIL injected move: $r1"; exit 1 }
Start-Sleep -Milliseconds 150
$r2 = (& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- stobe-auto mouse_inject $b click 80 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Write-Output "CLICK FAIL injected click: $r2"; exit 1 }
Start-Sleep -Milliseconds 200
Write-Output "CLICK OK $Button x=$X y=$Y injected ($r1)"
