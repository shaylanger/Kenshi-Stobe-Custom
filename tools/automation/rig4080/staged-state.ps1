<#
staged-state.ps1 (4080 rig, C:\KAH\runner\staged-state.ps1; copied there by rig-runner.ps1 -Rig 4080 at start):
  (no args)  NEWEST <sha8> newer=0|1 installed=<sha8>   newest staged KenshiFP in C:\KAH\staged vs the installed DLL
             (newer=1: not installed and staged later than the installed file was written); NONE installed=<sha8> if none
  -Harness   HARNESS <sha8>  installed AutomationHarness.dll
  -InstallHarness <sha8>  copy C:\KAH\staged\AutomationHarness-<sha8>.dll over the installed harness (Kenshi closed, SHA checked),
             then print HARNESS <sha8> like -Harness
#>
param([switch]$Harness, [string]$InstallHarness = '')
$k = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi'
if ($InstallHarness) {
    $src = "C:\KAH\staged\AutomationHarness-$($InstallHarness.ToUpper()).dll"; $hd = "$k\mods\AutomationHarness\AutomationHarness.dll"
    if ((Get-FileHash $hd).Hash.Substring(0, 8) -ne $InstallHarness.ToUpper() -and (Test-Path $src) -and
        (Get-FileHash $src).Hash.Substring(0, 8) -eq $InstallHarness.ToUpper() -and -not (Get-Process kenshi_x64 -ErrorAction SilentlyContinue)) {
        Copy-Item $src $hd -Force }
    $Harness = $true
}
if ($Harness) { "HARNESS $((Get-FileHash "$k\mods\AutomationHarness\AutomationHarness.dll").Hash.Substring(0, 8))"; exit 0 }
$dst = "$k\mods\KenshiFP\KenshiFP.dll"
$ih = (Get-FileHash $dst).Hash.Substring(0, 8)
$f = Get-ChildItem 'C:\KAH\staged\KenshiFP-*.dll' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $f) { "NONE installed=$ih"; exit 0 }
$h = $f.BaseName.Substring(9).ToUpper()
$newer = if ($h -ne $ih -and $f.LastWriteTime -gt (Get-Item $dst).LastWriteTime) { 1 } else { 0 }
"NEWEST $h newer=$newer installed=$ih"
