<#
build-stobe.ps1: build Stobe.dll with the shared VS2010 x64 tools. The source list is read from
<Root>\CMakeLists.txt (add_library(Stobe SHARED ...): src/*.cpp and legacy-v1/*.cpp entries), never
from a hard-coded list (2026-10-15: the old build_portable.bat SOURCES= line was stale and dropped
files that the CMake list had gained).

  build-stobe.ps1                      default: Root = WSL /root/STOBE-src. Changed *.cpp/*.h from Root\src
                                       (and Root\legacy-v1) are copied to C:\StobeBuild\src (\legacy-v1);
                                       objects in C:\StobeBuild\obj + obj-v1; output C:\StobeBuild\out\Stobe.dll.
                                       Takes inflight\build-stobe-lock while building.
  build-stobe.ps1 -Root <dir> [-Out <dir>]
                                       scratch build straight from <dir> (needs CMakeLists.txt, src\, and
                                       legacy-v1\ if the list names it, e.g. a copy of components\STOBE or
                                       pending-fixes\npc-immersion-26\NC). Nothing is copied into
                                       C:\StobeBuild\src and C:\StobeBuild\out is untouched; output goes to
                                       <Out>\out\Stobe.dll (default C:\StobeBuild\scratch\<leaf of Root>).
  -Guard a,b,c                         extra strings the DLL must contain (added to the standing four:
                                       travel_destinations LOCAL_TRAVEL travel_lifecycle world_towns).
Never installs anything. Prints the build result, compile errors and the DLL SHA256. Exit 1 on failure.
#>
param(
  [string]$Root = '',
  [string]$Out = '',
  [string[]]$Guard = @()
)
$ErrorActionPreference = 'Stop'
$Guard = @($Guard | ForEach-Object { $_ -split ',' } | Where-Object { $_ })  # -File passes a,b,c as one string
$sb = 'C:\StobeBuild'
$scratch = [bool]$Root
if (-not $Root) { $Root = '\\wsl.localhost\DwemerAI4Skyrim3\root\STOBE-src' }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'CMakeLists.txt'))) { "ERROR: no CMakeLists.txt in $Root"; exit 1 }
if (-not $Out) { $Out = if ($scratch) { Join-Path $sb ('scratch\' + (Split-Path $Root -Leaf)) } else { $sb } }

# Source list from the CMake target.
$cmakeText = Get-Content -LiteralPath (Join-Path $Root 'CMakeLists.txt') -Raw
$block = [regex]::Match($cmakeText, '(?s)add_library\(Stobe SHARED(.*?)\)').Groups[1].Value
$rel = @([regex]::Matches($block, '(src|legacy-v1)/[^\s]+\.cpp') | ForEach-Object Value)
if ($rel.Count -eq 0) { 'ERROR: no sources found in the add_library(Stobe SHARED ...) block'; exit 1 }

# Where the sources are compiled from.
if ($scratch) {
  $srcDir = Join-Path $Root 'src'; $legDir = Join-Path $Root 'legacy-v1'
} else {
  $srcDir = Join-Path $sb 'src'; $legDir = Join-Path $sb 'legacy-v1'
  $copied = @()
  foreach ($pair in @(@((Join-Path $Root 'src'), $srcDir), @((Join-Path $Root 'legacy-v1'), $legDir))) {
    if (-not (Test-Path -LiteralPath $pair[0])) { continue }
    if (-not (Test-Path -LiteralPath $pair[1])) { New-Item -ItemType Directory -Path $pair[1] -Force | Out-Null }
    foreach ($f in Get-ChildItem -LiteralPath $pair[0] -File | Where-Object { $_.Extension -in '.cpp', '.h' }) {
      $target = Join-Path $pair[1] $f.Name
      if (-not (Test-Path $target) -or (Get-FileHash $f.FullName).Hash -ne (Get-FileHash $target).Hash) {
        Copy-Item $f.FullName $target -Force
        $copied += $f.Name
      }
    }
  }
  "copied: " + ($(if ($copied) { $copied -join ', ' } else { '(nothing changed)' }))
}
$main = @(); $legacy = @()
foreach ($r in $rel) {
  $isLeg = $r.StartsWith('legacy-v1/')
  $p = if ($isLeg) { Join-Path $legDir $r.Substring(10).Replace('/', '\') } else { Join-Path $srcDir $r.Substring(4).Replace('/', '\') }
  if (-not (Test-Path -LiteralPath $p)) { "ERROR: CMake lists $r but $p is missing"; exit 1 }
  if ($isLeg) { $legacy += $p } else { $main += $p }
}
"sources: main=$($main.Count) legacy-v1=$($legacy.Count) (from $Root\CMakeLists.txt)"

$lock = 'C:\KenshiTestRuns\inflight\build-stobe-lock'
if (-not $scratch) {
  while (Test-Path $lock) { "build lock held by: " + (Get-Content $lock -Raw).Trim() + "; waiting 60 s"; Start-Sleep -Seconds 60 }
  Set-Content -LiteralPath $lock -Value 'build-stobe.ps1' -Encoding ASCII
}
try {
  $tools = 'C:\StobeBuildTools'
  $vc = Join-Path $tools 'v100\Program Files(64)\Microsoft Visual Studio 10.0\VC'
  $vcinc = Join-Path $tools 'v100x86\Program Files\Microsoft Visual Studio 10.0\VC\include'
  $vclib = Join-Path $tools 'v100x86\Program Files\Microsoft Visual Studio 10.0\VC\lib\amd64'
  $sdk71 = Join-Path $tools 'sdk71\Program Files\Microsoft SDKs\Windows\v7.1'
  $sdk = Join-Path $sb 'sdk'
  $env:PATH = "$vc\bin\amd64;$sdk71\Bin\x64;$sdk71\Bin;$env:PATH"
  $env:INCLUDE = "$vcinc;$sdk71\Include"
  $env:LIB = "$vclib;$sdk71\Lib\x64"
  $cl = Join-Path $vc 'bin\amd64\cl.exe'; $link = Join-Path $vc 'bin\amd64\link.exe'
  $ver = (Get-Item -LiteralPath $cl).VersionInfo.ProductVersion
  if ($ver -notmatch '^10\.00\.') { "ERROR: cl.exe is not the VS2010 compiler: $ver"; exit 2 }

  $obj = Join-Path $Out 'obj'; $objl = Join-Path $Out 'obj-v1'; $outd = Join-Path $Out 'out'
  foreach ($d in @($obj, $objl, $outd)) {
    if (Test-Path $d) { Get-ChildItem $d -File | Remove-Item -Force } else { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
  $common = @('/nologo', '/c', '/MP4', '/MD', '/O2', '/Ob2', '/GL', '/GR', '/EHa', '/W3', '/Zi',
    '/DWIN32', '/D_WINDOWS', '/DNDEBUG', '/DUNICODE', '/D_UNICODE', '/DBOOST_ALL_NO_LIB',
    '/DBOOST_ERROR_CODE_HEADER_ONLY', '/DBOOST_SYSTEM_NO_DEPRECATED', '/DSTOBE_DIAG_PROFILE_NORMAL=1', '/DStobe_EXPORTS',
    "/I$sb\compat", "/I$srcDir", "/I$sdk\Include", "/I$sdk\Include\ogre", "/I$sdk\Include\mygui", "/I$sb\boost")
  $log1 = Join-Path $Out 'compile.log'; $log2 = Join-Path $Out 'compile-v1.log'
  & $cl @common "/Fo$obj\" "/Fd$obj\vc100.pdb" @main *> $log1
  if ($LASTEXITCODE -ne 0) { Get-Content $log1 | Select-String 'error|fatal' | Select-Object -First 20 | ForEach-Object { $_.Line }; 'BUILD FAILED during compile (src)'; exit 1 }
  if ($legacy.Count) {
    & $cl @common "/I$legDir" "/Fo$objl\" "/Fd$objl\vc100.pdb" @legacy *> $log2
    if ($LASTEXITCODE -ne 0) { Get-Content $log2 | Select-String 'error|fatal' | Select-Object -First 20 | ForEach-Object { $_.Line }; 'BUILD FAILED during compile (legacy-v1)'; exit 1 }
  }
  $objs = @(Get-ChildItem $obj, $objl -File -Filter *.obj | ForEach-Object FullName)
  $dll = Join-Path $outd 'Stobe.dll'; $linklog = Join-Path $Out 'link.log'
  & $link /nologo /DLL /LTCG /DEBUG /OPT:REF /OPT:ICF /MACHINE:X64 "/OUT:$dll" "/PDB:$outd\Stobe.pdb" @objs "$sdk\KenshiLib.lib" "$sdk\Libraries\MyGUIEngine_x64.lib" "$sdk\Libraries\OgreMain_x64.lib" winhttp.lib winmm.lib ole32.lib ws2_32.lib kernel32.lib user32.lib gdi32.lib shell32.lib advapi32.lib *> $linklog
  if ($LASTEXITCODE -ne 0) { Get-Content $linklog | Select-Object -Last 20; 'BUILD FAILED during link'; exit 1 }
  & (Join-Path $vc 'bin\amd64\dumpbin.exe') /nologo /imports $dll > (Join-Path $outd 'imports.txt') 2>$null
  & (Join-Path $vc 'bin\amd64\dumpbin.exe') /nologo /exports $dll > (Join-Path $outd 'exports.txt') 2>$null
  "BUILD OK: $dll (objects=$($objs.Count))"
} finally {
  if (-not $scratch) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
}
# Build guard (2026-10-15): the 2026-10-14 19:37 DLL was built from a tree without the native
# travel code and shipped with no "travel_destinations" at all. Fail when the DLL lacks it.
$dllText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll))
$missing = @('travel_destinations', 'LOCAL_TRAVEL', 'travel_lifecycle', 'world_towns') + $Guard | Where-Object { -not $dllText.Contains($_) }
if ($missing) {
  "BUILD GUARD FAILED: Stobe.dll lacks " + ($missing -join ', ') + " (native travel code not built in; check the add_library list in $Root\CMakeLists.txt and the sources it names)"
  exit 1
}
"Stobe.dll " + (Get-FileHash $dll).Hash.Substring(0, 8) + " sha256=" + (Get-FileHash $dll -Algorithm SHA256).Hash
