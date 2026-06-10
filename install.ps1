[CmdletBinding()]
param(
  [string]$CommandDirectory = (Join-Path $env:USERPROFILE "bin"),
  [switch]$SkipPathUpdate
)

$ErrorActionPreference = "Stop"

$source = Join-Path $PSScriptRoot "WSL.cmd"
if (-not (Test-Path -LiteralPath $source)) {
  throw "Could not find WSL.cmd beside this installer."
}

if (-not (Test-Path -LiteralPath $CommandDirectory)) {
  New-Item -ItemType Directory -Path $CommandDirectory | Out-Null
}

$target = Join-Path $CommandDirectory "WSL.cmd"
$scriptPath = Join-Path $PSScriptRoot "scripts\wsl-proxy.ps1"
$content = @"
@echo off
setlocal

set "SCRIPT=$scriptPath"

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
"@

Set-Content -LiteralPath $target -Value $content -Encoding ASCII
Write-Host "Installed CMD command: $target"

if (-not $SkipPathUpdate) {
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = $userPath -split ";" | Where-Object { $_ }
  if ($parts -notcontains $CommandDirectory) {
    [Environment]::SetEnvironmentVariable("Path", ($parts + $CommandDirectory -join ";"), "User")
    Write-Host "Added $CommandDirectory to your user PATH. Open a new CMD window before typing WSL."
  } else {
    Write-Host "$CommandDirectory is already on your user PATH."
  }
}

Write-Host "Load the Chrome extension from: $(Join-Path $PSScriptRoot 'chrome-extension')"
