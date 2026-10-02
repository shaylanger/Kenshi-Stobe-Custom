<#
build-stobe.ps1: copy changed Stobe sources from WSL /root/STOBE-src/src to
C:\StobeBuild\src, then run build_portable.bat. Prints the copied files, the
build result, compile errors and the new DLL hash. Exit 1 on failure.
#>
$ErrorActionPreference = 'Stop'
$src = '\\wsl.localhost\DwemerAI4Skyrim3\root\STOBE-src\src'
$dst = 'C:\StobeBuild\src'
$copied = @()
foreach ($f in Get-ChildItem $src -File | Where-Object { $_.Extension -in '.cpp', '.h' }) {
  $target = Join-Path $dst $f.Name
  if (-not (Test-Path $target) -or (Get-FileHash $f.FullName).Hash -ne (Get-FileHash $target).Hash) {
    Copy-Item $f.FullName $target -Force
    $copied += $f.Name
  }
}
"copied: " + ($(if ($copied) { $copied -join ', ' } else { '(nothing changed)' }))
$out = & cmd /c "C:\StobeBuild\build_portable.bat" 2>&1
$out | Select-Object -Last 1
if (($out -join "`n") -notmatch 'BUILD OK') {
  Get-ChildItem 'C:\StobeBuild\obj\*.log' | Select-String -Pattern ' error ' | Select-Object -First 8 | ForEach-Object { $_.Line }
  exit 1
}
"Stobe.dll " + (Get-FileHash 'C:\StobeBuild\out\Stobe.dll').Hash.Substring(0, 8)
