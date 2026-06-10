[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$logDir = Join-Path $env:LOCALAPPDATA "WslChromeProxy"
if (-not (Test-Path -LiteralPath $logDir)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}
$logPath = Join-Path $logDir "install-wsl-features.log"
Start-Transcript -LiteralPath $logPath -Force | Out-Null

Write-Host "Enabling Windows Subsystem for Linux..."
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart

Write-Host "Enabling Virtual Machine Platform..."
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart

Write-Host "Trying to set WSL 2 as the default version..."
try {
  wsl.exe --set-default-version 2
} catch {
  Write-Host "WSL default version could not be set yet. This is normal before reboot on some Windows 10 installs."
}

Write-Host ""
Write-Host "Windows WSL features are enabled. Reboot Windows if prompted, then run:"
Write-Host "  wsl.exe --install -d Ubuntu"
Write-Host "Log: $logPath"

Stop-Transcript | Out-Null
