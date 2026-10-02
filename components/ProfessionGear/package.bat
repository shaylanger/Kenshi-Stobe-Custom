@echo off
setlocal
set ROOT=%~dp0
set DEST=%ROOT%out\package\ProfessionGearProgression
if not exist "%ROOT%out\ProfessionGearProgression.dll" (
  echo ERROR: build the DLL first with build_portable.bat
  exit /b 1
)
if exist "%DEST%" rmdir /s /q "%DEST%"
mkdir "%DEST%"
copy /y "%ROOT%out\ProfessionGearProgression.dll" "%DEST%\ProfessionGearProgression.dll" >nul
copy /y "%ROOT%mod\RE_Kenshi.json" "%DEST%\RE_Kenshi.json" >nul
copy /y "%ROOT%mod\mod.info" "%DEST%\mod.info" >nul
copy /y "%ROOT%mod\ProfessionGear.ini" "%DEST%\ProfessionGear.ini" >nul
copy /y "%ROOT%mod\ProfessionGear.rules" "%DEST%\ProfessionGear.rules" >nul
echo PACKAGE OK: %DEST%
