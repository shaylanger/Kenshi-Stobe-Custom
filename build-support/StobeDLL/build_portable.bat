@echo off
rem Same as build.bat, but uses the extracted VS2010 x64 compiler + SDK 7.1 in C:\StobeBuildTools
rem (the installed SDK 7.1 that build.bat expects is no longer present). Output: C:\StobeBuild\out\Stobe.dll
setlocal EnableDelayedExpansion
set ROOT=%~dp0
set TOOLS=C:\StobeBuildTools
set VC64=%TOOLS%\v100\Program Files(64)\Microsoft Visual Studio 10.0\VC
set VCINC=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\include
set VCLIB=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\lib\amd64
set SDK=%TOOLS%\sdk71\Program Files\Microsoft SDKs\Windows\v7.1
set PATH=%VC64%\bin\amd64;%SDK%\Bin\x64;%SDK%\Bin;%PATH%
set INCLUDE=%VCINC%;%SDK%\Include
set LIB=%VCLIB%;%SDK%\Lib\x64
where cl >nul 2>nul || (echo ERROR: cl.exe not on PATH & exit /b 2)
cl 2>&1 | findstr /C:"Version 16." >nul || (echo ERROR: cl.exe is not the VS2010 compiler: & cl 2>&1 | findstr /C:"Version" & exit /b 2)

if exist "%ROOT%obj" rmdir /s /q "%ROOT%obj"
if not exist "%ROOT%out" mkdir "%ROOT%out"
mkdir "%ROOT%obj"

set SOURCES=AudioPlayback AutonomyController AutonomyExecutor AutonomyMonitor AutonomyProtocol AutonomySafetyProbe AutonomySafetyProbePolicy ChatUI ChatUIGlobals ChatBox Interaction Comm PlaythroughSession Context DialogueMenuTts Functions Globals KenshiAiCompat JournalWindow StartingWindow SupportReportLauncher AiNpcInfoWindow KenshiBuildingStatus KenshiRvaCompat KenshiTownIdentity PlayerBaseState StobeIdentityRename StobeChatMode StobeText StobeTiming StobeEventPolicy main TestAutomation SettingsWindow Utils VoiceCapture WelcomeWindow WorldStateRuntime

set CFLAGS=/nologo /c /MD /O2 /Ob2 /GL /GR /EHa /W3 /Zi /DWIN32 /D_WINDOWS /DNDEBUG /DUNICODE /D_UNICODE /DBOOST_ALL_NO_LIB /DBOOST_ERROR_CODE_HEADER_ONLY /DBOOST_SYSTEM_NO_DEPRECATED /DSTOBE_DIAG_PROFILE_NORMAL=1 /DStobe_EXPORTS
set INCS=/I"%ROOT%compat" /I"%ROOT%src" /I"%ROOT%sdk\Include" /I"%ROOT%sdk\Include\ogre" /I"%ROOT%sdk\Include\mygui" /I"%ROOT%boost"

set FAILED=0
for %%S in (%SOURCES%) do (
  echo [compile] %%S.cpp
  cl %CFLAGS% %INCS% /Fo"%ROOT%obj\%%S.obj" /Fd"%ROOT%obj\vc100.pdb" "%ROOT%src\%%S.cpp" > "%ROOT%obj\%%S.log" 2>&1
  if errorlevel 1 (
    set FAILED=1
    echo ERROR compiling %%S.cpp:
    findstr /R /C:"error" "%ROOT%obj\%%S.log"
  )
)
if "%FAILED%"=="1" (echo BUILD FAILED during compile & exit /b 1)

echo [link] Stobe.dll
link /nologo /DLL /LTCG /DEBUG /OPT:REF /OPT:ICF /MACHINE:X64 /OUT:"%ROOT%out\Stobe.dll" /PDB:"%ROOT%out\Stobe.pdb" ^
  "%ROOT%obj\*.obj" "%ROOT%sdk\KenshiLib.lib" "%ROOT%sdk\Libraries\MyGUIEngine_x64.lib" "%ROOT%sdk\Libraries\OgreMain_x64.lib" ^
  winhttp.lib winmm.lib ole32.lib ws2_32.lib kernel32.lib user32.lib gdi32.lib shell32.lib advapi32.lib > "%ROOT%obj\link.log" 2>&1
if errorlevel 1 (type "%ROOT%obj\link.log" & echo BUILD FAILED during link & exit /b 1)

dumpbin /nologo /imports "%ROOT%out\Stobe.dll" > "%ROOT%out\imports.txt"
dumpbin /nologo /exports "%ROOT%out\Stobe.dll" > "%ROOT%out\exports.txt"
echo BUILD OK: %ROOT%out\Stobe.dll
exit /b 0
