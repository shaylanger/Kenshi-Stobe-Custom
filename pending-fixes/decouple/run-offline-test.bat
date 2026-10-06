@echo off
rem Builds + runs the StobeGoals offline test with the v100 x64 toolchain. Arg 1: Stobe src dir (Windows path).
setlocal
set TOOLS=C:\StobeBuildTools
set VC64=%TOOLS%\v100\Program Files(64)\Microsoft Visual Studio 10.0\VC
set VCINC=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\include
set VCLIB=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\lib\amd64
set SDK=%TOOLS%\sdk71\Program Files\Microsoft SDKs\Windows\v7.1
set PATH=%VC64%\bin\amd64;%SDK%\Bin\x64;%SDK%\Bin;%PATH%
set INCLUDE=%VCINC%;%SDK%\Include
set LIB=%VCLIB%;%SDK%\Lib\x64
set OUT=C:\StobeBuildDecouple\test
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%\t\tests\cpp" & mkdir "%OUT%\t\src"
copy /y "%~1\StobeGoals.cpp" "%OUT%\t\src\" >nul & copy /y "%~1\StobeGoals.h" "%OUT%\t\src\" >nul
copy /y "%~dp0stobe_goals_offline_test.cpp" "%OUT%\t\tests\cpp\" >nul
cl /nologo /MD /O2 /EHa /W3 /I"%OUT%\t\src" /Fe"%OUT%\stobe_goals_offline_test.exe" /Fo"%OUT%\\" "%OUT%\t\tests\cpp\stobe_goals_offline_test.cpp" user32.lib > "%OUT%\build.log" 2>&1 || (type "%OUT%\build.log" & exit /b 1)
"%OUT%\stobe_goals_offline_test.exe"
