@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_sdk_symbols.ps1"
exit /b %errorlevel%
