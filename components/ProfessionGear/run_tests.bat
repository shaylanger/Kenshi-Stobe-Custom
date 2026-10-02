@echo off
setlocal
set ROOT=%~dp0
set TOOLS=C:\StobeBuildTools
set VC64=%TOOLS%\v100\Program Files(64)\Microsoft Visual Studio 10.0\VC
set VCINC=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\include
set VCLIB=%TOOLS%\v100x86\Program Files\Microsoft Visual Studio 10.0\VC\lib\amd64
set SDK=%TOOLS%\sdk71\Program Files\Microsoft SDKs\Windows\v7.1
set PATH=%VC64%\bin\amd64;%SDK%\Bin\x64;%SDK%\Bin;%PATH%
set INCLUDE=%VCINC%;%SDK%\Include
set LIB=%VCLIB%;%SDK%\Lib\x64
if not exist "%ROOT%out" mkdir "%ROOT%out"
cl /nologo /MD /O2 /EHsc /I"%ROOT%src" "%ROOT%src\ProfessionGearCore.cpp" "%ROOT%tests\test_profession_gear.cpp" /Fe"%ROOT%out\ProfessionGearTests.exe"
if errorlevel 1 exit /b 1
"%ROOT%out\ProfessionGearTests.exe"
