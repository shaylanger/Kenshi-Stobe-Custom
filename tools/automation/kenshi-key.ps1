# kenshi-key.ps1 <vk-hex> [holdMs]: inject one key into the selected isolated Kenshi instance.
# Input is always routed through that instance's AutomationHarness. This helper never changes focus or sends real keys.
param([Parameter(Mandatory=$true)][string]$Vk, [ValidateRange(1,5000)][int]$HoldMs = 200)
. (Join-Path $PSScriptRoot 'kenshi-input-routing.ps1')

$route = Get-KenshiInputRoute
if (-not $route) { exit 1 }
if (-not (Test-KenshiInputInstanceProcess -Route $route)) {
  Write-Output "KEY FAIL no Kenshi process for instance $($route.Instance) ($($route.GameDir))"; exit 1
}
if (-not (Test-Path -LiteralPath $route.IsolationFile)) {
  Write-Output "KEY FAIL input isolation off for instance $($route.Instance) (no real-key fallback)"; exit 1
}
$wslArgs = Get-KenshiInputWslArgs -Route $route -Command @('key_inject', $Vk, 'tap', "$HoldMs")
$r = (& wsl.exe @wslArgs 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { Write-Output "KEY FAIL injected vk=$Vk instance=$($route.Instance): $r"; exit 1 }
Start-Sleep -Milliseconds ($HoldMs + 100)
Write-Output "KEY OK vk=$Vk instance=$($route.Instance) injected ($r)"
