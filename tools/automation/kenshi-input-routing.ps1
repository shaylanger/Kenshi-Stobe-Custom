# Shared, side-effect-free routing for kenshi-key.ps1 / kenshi-click.ps1.
function Get-KenshiInputRoute {
  $instance = 1
  if ($env:KAH_INSTANCE) {
    if ($env:KAH_INSTANCE -notmatch '^\d+$' -or [int]$env:KAH_INSTANCE -lt 1) {
      Write-Output "INPUT FAIL invalid KAH_INSTANCE='$env:KAH_INSTANCE'"; return $null
    }
    $instance = [int]$env:KAH_INSTANCE
  }
  if ($instance -ge 2) {
    $gameDir = "D:\KenshiInst\$instance"
    $linuxDir = "/mnt/d/KenshiInst/$instance"
  } else {
    $gameDir = 'D:\Steam\steamapps\common\Kenshi'
    $linuxDir = '/mnt/d/Steam/steamapps/common/Kenshi'
  }
  $harness = Join-Path $gameDir 'mods\AutomationHarness'
  [pscustomobject]@{
    Instance = $instance
    GameDir = $gameDir
    LinuxGameDir = $linuxDir
    HarnessDir = $harness
    IsolationFile = Join-Path $harness 'input_isolation.on'
    KahDir = "$gameDir\mods\AutomationHarness"
  }
}

function Test-KenshiInputInstanceProcess {
  param([Parameter(Mandatory=$true)]$Route, [object[]]$ProcessList = $null)
  if ($null -eq $ProcessList) { $ProcessList = @(Get-Process kenshi_x64 -ErrorAction SilentlyContinue) }
  $expected = Join-Path $Route.GameDir 'kenshi_x64.exe'
  foreach ($proc in $ProcessList) {
    try { if ([string]::Equals([string]$proc.Path, $expected, [StringComparison]::OrdinalIgnoreCase)) { return $true } } catch {}
  }
  return $false
}

function Get-KenshiInputWslArgs {
  param([Parameter(Mandatory=$true)]$Route, [Parameter(Mandatory=$true)][string[]]$Command)
  # Put the route inside the Linux command explicitly: WSLENV on a nested invocation must not
  # inherit a stale/default instance, and stobe-auto preserves the supplied KAH_DIR.
  $envs = @('KAH_INSTANCE=' + $Route.Instance, 'KDIR=' + $Route.LinuxGameDir, 'KAH_DIR=' + $Route.KahDir)
  return @('-d', 'DwemerAI4Skyrim3', '-u', 'root', '--cd', '/', '--', 'env') + $envs + @('stobe-auto') + $Command
}
