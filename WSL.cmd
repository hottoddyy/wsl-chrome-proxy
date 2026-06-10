@echo off
setlocal

set "SCRIPT=%~dp0scripts\wsl-proxy.ps1"

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  ) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%*'"
  )
  exit /b %ERRORLEVEL%
)

if /I "%~1"=="stop" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Stop
  exit /b %ERRORLEVEL%
)

if /I "%~1"=="status" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Status
  exit /b %ERRORLEVEL%
)

if /I "%~1"=="foreground" (
  shift
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RunServer %*
  exit /b %ERRORLEVEL%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Start %*
exit /b %ERRORLEVEL%
