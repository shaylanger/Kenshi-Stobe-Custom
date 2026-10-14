# kenshi-click.ps1 <x> <y> [right]: inject a click into the selected isolated Kenshi instance.
# x/y are absolute client pixels measured against a KAH render screenshot, not desktop coordinates.
# The `at` step only moves the virtual cursor; the following button command is the explicit click.
# This helper never focuses Kenshi or moves the real mouse.
param([Parameter(Mandatory=$true)][int]$X, [Parameter(Mandatory=$true)][int]$Y, [ValidateSet('left','right')][string]$Button = 'left')
. (Join-Path $PSScriptRoot 'kenshi-input-routing.ps1')

$route = Get-KenshiInputRoute
if (-not $route) { exit 1 }
if (-not (Test-KenshiInputInstanceProcess -Route $route)) {
  Write-Output "CLICK FAIL no Kenshi process for instance $($route.Instance) ($($route.GameDir))"; exit 1
}
if (-not (Test-Path -LiteralPath $route.IsolationFile)) {
  Write-Output "CLICK FAIL input isolation off for instance $($route.Instance) (no real-mouse fallback)"; exit 1
}
$moveArgs = Get-KenshiInputWslArgs -Route $route -Command @('mouse_inject', 'at', "$X", "$Y")
$r1 = (& wsl.exe @moveArgs 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Write-Output "CLICK FAIL injected move: $r1"; exit 1 }
Start-Sleep -Milliseconds 150
$clickArgs = Get-KenshiInputWslArgs -Route $route -Command @('mouse_inject', $Button, 'click', '80')
$r2 = (& wsl.exe @clickArgs 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Write-Output "CLICK FAIL injected click: $r2"; exit 1 }
Start-Sleep -Milliseconds 200
Write-Output "CLICK OK $Button x=$X y=$Y instance=$($route.Instance) injected ($r1; $r2)"
