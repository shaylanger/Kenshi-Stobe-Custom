# Offline mocked test for per-instance injection routing; no WSL, game, focus, or mouse APIs are called.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'kenshi-input-routing.ps1')
$oldInstance = $env:KAH_INSTANCE
try {
  $env:KAH_INSTANCE = '3'
  $route = Get-KenshiInputRoute
  if ($route.Instance -ne 3 -or $route.GameDir -ne 'D:\KenshiInst\3' -or
      $route.HarnessDir -ne 'D:\KenshiInst\3\mods\AutomationHarness' -or
      $route.IsolationFile -ne 'D:\KenshiInst\3\mods\AutomationHarness\input_isolation.on') {
    throw "D3 route mismatch: $($route | ConvertTo-Json -Compress)"
  }
  $matching = [pscustomobject]@{ Path = 'D:\KenshiInst\3\kenshi_x64.exe' }
  $other = [pscustomobject]@{ Path = 'D:\Steam\steamapps\common\Kenshi\kenshi_x64.exe' }
  if (-not (Test-KenshiInputInstanceProcess -Route $route -ProcessList @($other, $matching))) { throw 'D3 process was not selected' }
  if (Test-KenshiInputInstanceProcess -Route $route -ProcessList @($other)) { throw 'Steam instance was incorrectly selected as D3' }

  $wslArgs = Get-KenshiInputWslArgs -Route $route -Command @('key_inject', '0xBF', 'tap', '200')
  $joined = $wslArgs -join ' '
  foreach ($expected in @('KAH_INSTANCE=3', 'KDIR=/mnt/d/KenshiInst/3', 'KAH_DIR=D:\KenshiInst\3\mods\AutomationHarness', 'stobe-auto key_inject 0xBF tap 200')) {
    if ($joined -notlike "*$expected*") { throw "nested WSL route missing '$expected': $joined" }
  }

  # The mocked injection boundary records the exact command while a sentinel foreground/mouse state is observed.
  $desktop = [pscustomobject]@{ Foreground = 'user-app'; MouseX = 413; MouseY = 287; MouseButtons = 'up' }
  $before = $desktop | ConvertTo-Json -Compress
  $script:MockedInvocation = $null
  $mockWsl = { param([string[]]$Arguments) $script:MockedInvocation = @($Arguments); 'mock injection accepted' }
  $mockResult = & $mockWsl -Arguments $wslArgs
  if ($mockResult -ne 'mock injection accepted' -or $null -eq $script:MockedInvocation) { throw 'mock injection boundary was not called' }
  if (($desktop | ConvertTo-Json -Compress) -ne $before) { throw 'foreground or mouse state changed in the mocked test' }

  foreach ($file in @('kenshi-key.ps1','kenshi-click.ps1')) {
    $source = Get-Content (Join-Path $PSScriptRoot $file) -Raw
    if ($source -match 'AppActivate|SetForegroundWindow|BringWindowToTop|keybd_event|SendInput|SetCursorPos|mouse_event') {
      throw "$file contains a focus-steal or physical-input fallback"
    }
  }
  foreach ($file in @('kenshi-key.ps1','kenshi-click.ps1','kenshi-input-routing.ps1','kenshi-input-routing-selftest.ps1')) {
    $tokens = $null; $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw "$file parse error: $($parseErrors[0].Message)" }
  }
  $ctl = Get-Content (Join-Path $PSScriptRoot 'kenshi-ctl.ps1') -Raw
  if ($ctl -notmatch '\[switch\]\$Play' -or $ctl -notmatch 'if \(\$Play\)') { throw 'normal -Play handling was not found' }
  'KENSHI-INPUT-ROUTING-SELFTEST PASS instance=3 process=isolated nested-env=explicit foreground=user-app mouse=413,287 unchanged'
} finally {
  if ($null -eq $oldInstance) { Remove-Item Env:KAH_INSTANCE -ErrorAction SilentlyContinue } else { $env:KAH_INSTANCE = $oldInstance }
}
