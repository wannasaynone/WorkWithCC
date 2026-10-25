@echo off
setlocal
rem Usage: drag a project folder onto this file, or run it and type the path.
set "TARGET=%~1"
if "%TARGET%"=="" set /p "TARGET=Target project folder: "
set "TARGET=%TARGET:"=%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" -Target "%TARGET%" -WhatIf
pause
