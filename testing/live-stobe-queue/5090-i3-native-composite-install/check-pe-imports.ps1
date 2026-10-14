[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$DllPath,
  [Parameter(Mandatory=$true)][string]$GameRoot,
  [string]$SystemRoot = "$env:WINDIR\System32",
  [Parameter(Mandatory=$true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$Dumpbin
)
$ErrorActionPreference = 'Stop'

function Invoke-Dumpbin([string[]]$Arguments) {
  $text = @(& $Dumpbin @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "dumpbin failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($text -join "`n")" }
  return $text
}
function Get-Machine([string]$Path) {
  $h = Invoke-Dumpbin @('/nologo','/headers',$Path)
  if (($h -join "`n") -match '(?m)^\s*8664 machine \(x64\)') { return 'x64' }
  if (($h -join "`n") -match '(?m)^\s*14C machine \(x86\)') { return 'x86' }
  return 'unknown'
}
function Get-ExportNames([string]$Path) {
  $exports = Invoke-Dumpbin @('/nologo','/exports',$Path)
  $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($line in $exports) {
    # The RVA column is blank for forwarded system exports, so accept either
    # the normal (8-hex RVA) or forwarded (name immediately after hint) form.
    if ($line -match '^\s*\d+\s+[0-9A-Fa-f]+\s+(?:[0-9A-Fa-f]{8}\s+)?(\S+)') { [void]$set.Add($Matches[1]) }
  }
  return ,$set
}
function Get-ImportMap([string]$Path) {
  $lines = Invoke-Dumpbin @('/nologo','/imports',$Path)
  $map = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)
  $module = $null
  $inSymbols = $false
  foreach ($line in $lines) {
    if ($line -match '^\s*([A-Za-z0-9_.+-]+\.dll)\s*$') {
      $module = $Matches[1]
      if (-not $map.Contains($module)) { $map.Add($module, [Collections.Generic.List[string]]::new()) }
      $inSymbols = $false
      continue
    }
    if (-not $module) { continue }
    if ($line -match 'Index of first forwarder reference') { $inSymbols = $true; continue }
    if ($inSymbols -and $line -match '^\s*[0-9A-Fa-f]{1,8}\s+([A-Za-z_?][A-Za-z0-9_?$@.]*)\s*$') { $map[$module].Add($Matches[1]) }
  }
  return ,$map
}

if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) { throw "Candidate DLL missing: $DllPath" }
if (-not (Test-Path -LiteralPath $GameRoot -PathType Container)) { throw "Game root missing: $GameRoot" }
if (-not (Test-Path -LiteralPath $SystemRoot -PathType Container)) { throw "System DLL root missing: $SystemRoot" }
if ((Get-Machine $DllPath) -cne 'x64') { throw 'Candidate is not x64; refusing plugin import audit.' }
$candidateHash = (Get-FileHash -LiteralPath $DllPath -Algorithm SHA256).Hash.ToUpperInvariant()
$candidateExports = Get-ExportNames $DllPath
$pluginEntry = '?startPlugin@@YAXXZ'
if (-not $candidateExports.Contains($pluginEntry)) { throw "Required plugin entry export missing: $pluginEntry" }
$imports = Get-ImportMap $DllPath
$missing = [Collections.Generic.List[string]]::new()
$symbolCount = 0
"CANDIDATE sha256=$candidateHash machine=x64 pluginEntry=$pluginEntry PASS"
foreach ($module in $imports.Keys) {
  $dep = Join-Path $GameRoot $module
  if (-not (Test-Path -LiteralPath $dep -PathType Leaf)) { $dep = Join-Path $SystemRoot $module }
  if (-not (Test-Path -LiteralPath $dep -PathType Leaf)) {
    $missing.Add("$module (dependency DLL unresolved in game root or system root)")
    continue
  }
  $depMachine = Get-Machine $dep
  if ($depMachine -cne 'x64') { $missing.Add("$module ($depMachine dependency architecture at $dep)"); continue }
  $depHash = (Get-FileHash -LiteralPath $dep -Algorithm SHA256).Hash.ToUpperInvariant()
  $exportSet = Get-ExportNames $dep
  $symbols = @($imports[$module] | Sort-Object -Unique)
  $symbolCount += $imports[$module].Count
  $moduleMissing = 0
  foreach ($symbol in $symbols) {
    if (-not $exportSet.Contains($symbol)) { $missing.Add("$module!$symbol"); $moduleMissing++ }
  }
  "DEPENDENCY $module sha256=$depHash imported=$($imports[$module].Count) missing=$moduleMissing path=$dep"
}
if ($missing.Count) {
  $missing | ForEach-Object { "UNRESOLVED $_" }
  "FAIL imports=$symbolCount dependencies=$($imports.Count) unresolved=$($missing.Count)"
  exit 1
}
"PASS imports=$symbolCount dependencies=$($imports.Count) unresolved=0"
