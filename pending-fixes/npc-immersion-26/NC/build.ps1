# NC (N1+N2 composed) candidate build (VS2010 x64, shared tools). Source list comes from N1\CMakeLists.txt.
# Takes C:\KenshiTestRuns\inflight\build-stobe-lock (name imm26-NC) while building. Does not install anything.
param([string]$Out = (Join-Path $PSScriptRoot 'build'), [string]$SrcDir = (Join-Path $PSScriptRoot 'src'), [string]$LegacyDir = (Join-Path $PSScriptRoot 'legacy-v1'))
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$lock = 'C:\KenshiTestRuns\inflight\build-stobe-lock'
while (Test-Path $lock) { "lock held by: " + (Get-Content $lock -Raw).Trim() + "; waiting 2 min"; Start-Sleep -Seconds 120 }
Set-Content -LiteralPath $lock -Value 'imm26-NC' -Encoding ASCII
try {
$tools = 'C:\StobeBuildTools'
$vc = Join-Path $tools 'v100\Program Files(64)\Microsoft Visual Studio 10.0\VC'
$vcinc = Join-Path $tools 'v100x86\Program Files\Microsoft Visual Studio 10.0\VC\include'
$vclib = Join-Path $tools 'v100x86\Program Files\Microsoft Visual Studio 10.0\VC\lib\amd64'
$sdk71 = Join-Path $tools 'sdk71\Program Files\Microsoft SDKs\Windows\v7.1'
$sdk = 'C:\StobeBuild\sdk'; $compat = 'C:\StobeBuild\compat'; $boost = 'C:\StobeBuild\boost'
$cmakeText = Get-Content -LiteralPath (Join-Path $root 'CMakeLists.txt') -Raw
$block = [regex]::Match($cmakeText, '(?s)add_library\(Stobe SHARED(.*?)\)').Groups[1].Value
$rel = @([regex]::Matches($block, '(src|legacy-v1)/[^\s]+\.cpp') | ForEach-Object Value)
$main = @(); $legacy = @()
foreach ($r in $rel) {
  $p = if ($r.StartsWith('legacy-v1/')) { Join-Path $LegacyDir $r.Substring(10).Replace('/','\') } else { Join-Path $SrcDir $r.Substring(4).Replace('/','\') }
  if (-not (Test-Path -LiteralPath $p)) { throw "missing source $r" }
  if ($r.StartsWith('legacy-v1/')) { $legacy += $p } else { $main += $p }
}
"sources: main=$($main.Count) legacy=$($legacy.Count)"
$obj = Join-Path $Out 'obj'; $objl = Join-Path $Out 'obj-v1'; $outd = Join-Path $Out 'out'
foreach ($d in @($obj,$objl,$outd)) { if (Test-Path $d) { Get-ChildItem $d -File | Remove-Item -Force }; New-Item -ItemType Directory -Path $d -Force | Out-Null }
$env:PATH = "$vc\bin\amd64;$sdk71\Bin\x64;$sdk71\Bin;$env:PATH"
$env:INCLUDE = "$vcinc;$sdk71\Include"
$env:LIB = "$vclib;$sdk71\Lib\x64"
$cl = Join-Path $vc 'bin\amd64\cl.exe'; $link = Join-Path $vc 'bin\amd64\link.exe'
$ver = (Get-Item -LiteralPath $cl).VersionInfo.ProductVersion
if ($ver -notmatch '^10\.00\.') { throw "not VS2010: $ver" }
$common = @('/nologo','/c','/MP4','/MD','/O2','/Ob2','/GL','/GR','/EHa','/W3','/Zi',
  '/DWIN32','/D_WINDOWS','/DNDEBUG','/DUNICODE','/D_UNICODE','/DBOOST_ALL_NO_LIB',
  '/DBOOST_ERROR_CODE_HEADER_ONLY','/DBOOST_SYSTEM_NO_DEPRECATED','/DSTOBE_DIAG_PROFILE_NORMAL=1','/DStobe_EXPORTS',
  "/I$compat", "/I$SrcDir", "/I$sdk\Include", "/I$sdk\Include\ogre", "/I$sdk\Include\mygui", "/I$boost")
$log1 = Join-Path $Out 'compile.log'; $log2 = Join-Path $Out 'compile-v1.log'
& $cl @common "/Fo$obj\" "/Fd$obj\vc100.pdb" @main *> $log1
if ($LASTEXITCODE -ne 0) { Get-Content $log1 | Select-String 'error|fatal' | Select-Object -First 40; throw "compile failed (main), see $log1" }
& $cl @common "/I$LegacyDir" "/Fo$objl\" "/Fd$objl\vc100.pdb" @legacy *> $log2
if ($LASTEXITCODE -ne 0) { Get-Content $log2 | Select-String 'error|fatal' | Select-Object -First 40; throw "compile failed (legacy), see $log2" }
$objs = @(Get-ChildItem $obj,$objl -File -Filter *.obj | ForEach-Object FullName)
"objects: $($objs.Count)"
$dll = Join-Path $outd 'Stobe.dll'; $linklog = Join-Path $Out 'link.log'
& $link /nologo /DLL /LTCG /DEBUG /OPT:REF /OPT:ICF /MACHINE:X64 "/OUT:$dll" "/PDB:$outd\Stobe.pdb" @objs "$sdk\KenshiLib.lib" "$sdk\Libraries\MyGUIEngine_x64.lib" "$sdk\Libraries\OgreMain_x64.lib" winhttp.lib winmm.lib ole32.lib ws2_32.lib kernel32.lib user32.lib gdi32.lib shell32.lib advapi32.lib *> $linklog
if ($LASTEXITCODE -ne 0) { Get-Content $linklog | Select-Object -Last 40; throw "link failed, see $linklog" }
$dllText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll))
$missing = @('travel_destinations','LOCAL_TRAVEL','travel_lifecycle','world_towns','known_place','abandoned_in_danger','N2_PROXIMITY','handBackStatus','FOLLOW_EXPIRED','SpeakWhilePaused','outcome=transient') | Where-Object { -not $dllText.Contains($_) }
if ($missing) { throw ("BUILD GUARD FAILED: Stobe.dll lacks " + ($missing -join ', ')) }
$h = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
"RESULT NC-BUILD PASS compiler=$ver objects=$($objs.Count) dll=$dll sha256=$h"
} finally { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
