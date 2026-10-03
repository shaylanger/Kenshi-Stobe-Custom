@echo off
rem Build Stobe.dll with the MSVC 2010 x64 compiler (Windows SDK 7.1 + VC 2010 SP1 compiler update).
rem Mirrors CMakeLists.txt (Release, STOBE_DIAG_PROFILE=normal). Output: C:\StobeBuild\out\Stobe.dll
setlocal EnableDelayedExpansion
set ROOT=%~dp0
set SETENV=C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.cmd
if not exist "%SETENV%" (
  echo ERROR: Windows SDK 7.1 SetEnv.cmd not found at "%SETENV%"
  exit /b 2
)
call "%SETENV%" /x64 /Release >nul
where cl >nul 2>nul || (echo ERROR: cl.exe not on PATH after SetEnv & exit /b 2)
cl 2>&1 | findstr /C:"Version 16." >nul || (echo ERROR: cl.exe is not the VS2010 compiler: & cl 2>&1 | findstr /C:"Version" & exit /b 2)

if exist "%ROOT%obj" rmdir /s /q "%ROOT%obj"
if not exist "%ROOT%out" mkdir "%ROOT%out"
mkdir "%ROOT%obj"

set SOURCES=AudioPlayback AutonomyController AutonomyExecutor AutonomyMonitor AutonomyProtocol AutonomySafetyProbe AutonomySafetyProbePolicy ChatUI ChatUIGlobals ChatBox Interaction Comm PlaythroughSession Context DialogueMenuTts Functions Globals KenshiAiCompat JournalWindow StartingWindow SupportReportLauncher AiNpcInfoWindow KenshiBuildingStatus KenshiRvaCompat KenshiTownIdentity PlayerBaseState StobeIdentityRename StobeChatMode StobeText StobeTiming StobeEventPolicy main StobeHarnessBridge SettingsWindow Utils VoiceCapture WelcomeWindow WorldStateRuntime

set CFLAGS=/nologo /c /MD /O2 /Ob2 /GR /EHa /W3 /Zi /DWIN32 /D_WINDOWS /DNDEBUG /DUNICODE /D_UNICODE /DBOOST_ALL_NO_LIB /DBOOST_ERROR_CODE_HEADER_ONLY /DBOOST_SYSTEM_NO_DEPRECATED /DSTOBE_DIAG_PROFILE_NORMAL=1 /DStobe_EXPORTS
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
link /nologo /DLL /DEBUG /OPT:REF /OPT:ICF /MACHINE:X64 /OUT:"%ROOT%out\Stobe.dll" /PDB:"%ROOT%out\Stobe.pdb" ^
  "%ROOT%obj\*.obj" "%ROOT%sdk\KenshiLib.lib" "%ROOT%sdk\Libraries\MyGUIEngine_x64.lib" "%ROOT%sdk\Libraries\OgreMain_x64.lib" ^
  winhttp.lib winmm.lib ole32.lib ws2_32.lib kernel32.lib user32.lib gdi32.lib shell32.lib advapi32.lib > "%ROOT%obj\link.log" 2>&1
if errorlevel 1 (type "%ROOT%obj\link.log" & echo BUILD FAILED during link & exit /b 1)

dumpbin /nologo /imports "%ROOT%out\Stobe.dll" > "%ROOT%out\imports.txt"
dumpbin /nologo /exports "%ROOT%out\Stobe.dll" > "%ROOT%out\exports.txt"
echo BUILD OK: %ROOT%out\Stobe.dll
exit /b 0
