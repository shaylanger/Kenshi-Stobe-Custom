@echo off
setlocal EnableDelayedExpansion
set ROOT=%~dp0
set TOOLS=C:\StobeBuildTools
set VC64=%TOOLS%\v100\Program Files(64)\Microsoft Visual Studio 10.0\VC
set VCINC=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\include
set VCLIB=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\lib\amd64
set SDK=%TOOLS%\sdk71\Program Files\Microsoft SDKs\Windows\v7.1
set STOBESDK=C:\StobeBuild\sdk
set BOOST=C:\StobeBuild\boost
set PATH=%VC64%\bin\amd64;%SDK%\Bin\x64;%SDK%\Bin;%PATH%
set INCLUDE=%VCINC%;%SDK%\Include
set LIB=%VCLIB%;%SDK%\Lib\x64
where cl >nul 2>nul || exit /b 2

if exist "%ROOT%obj" rmdir /s /q "%ROOT%obj"
if not exist "%ROOT%out" mkdir "%ROOT%out"
mkdir "%ROOT%obj"

set CFLAGS=/nologo /c /MD /O2 /Ob2 /GL /GR /EHa /W3 /Zi /DWIN32 /D_WINDOWS /DNDEBUG /DUNICODE /D_UNICODE /DBOOST_ALL_NO_LIB /DBOOST_ERROR_CODE_HEADER_ONLY /DBOOST_SYSTEM_NO_DEPRECATED
set INCS=/I"%ROOT%src" /I"%STOBESDK%\Include" /I"%STOBESDK%\Include\ogre" /I"%STOBESDK%\Include\mygui" /I"%BOOST%"

echo [compile] ProfessionGearCore.cpp
cl %CFLAGS% %INCS% /Fo"%ROOT%obj\ProfessionGearCore.obj" "%ROOT%src\ProfessionGearCore.cpp"
if errorlevel 1 exit /b 1
echo [compile] ProfessionGearPlugin.cpp
cl %CFLAGS% %INCS% /Fo"%ROOT%obj\ProfessionGearPlugin.obj" "%ROOT%src\ProfessionGearPlugin.cpp"
if errorlevel 1 exit /b 1

echo [link] ProfessionGearProgression.dll
link /nologo /DLL /LTCG /DEBUG /OPT:REF /OPT:ICF /MACHINE:X64 /OUT:"%ROOT%out\ProfessionGearProgression.dll" /PDB:"%ROOT%out\ProfessionGearProgression.pdb" ^
 "%ROOT%obj\ProfessionGearCore.obj" "%ROOT%obj\ProfessionGearPlugin.obj" "%STOBESDK%\KenshiLib.lib" ^
 "%STOBESDK%\Libraries\MyGUIEngine_x64.lib" "%STOBESDK%\Libraries\OgreMain_x64.lib" ^
 kernel32.lib user32.lib advapi32.lib
if errorlevel 1 exit /b 1
dumpbin /nologo /exports "%ROOT%out\ProfessionGearProgression.dll" > "%ROOT%out\exports.txt"
echo BUILD OK
