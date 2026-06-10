[CmdletBinding()]
param(
  [switch]$SkipWslFeatureInstall
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevated {
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
  if ($SkipWslFeatureInstall) {
    $args += "-SkipWslFeatureInstall"
  }

  Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args
}

if (-not (Test-IsAdmin)) {
  Write-Host "Opening Administrator installer..."
  Invoke-SelfElevated
  return
}

$root = $PSScriptRoot
$installRoot = Join-Path $env:LOCALAPPDATA "WslChromeProxy"

Write-Host "Installing WSL Chrome Proxy from:"
Write-Host "  $root"
Write-Host ""

if (-not $SkipWslFeatureInstall) {
  try {
    $wslStatus = & wsl.exe --status 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "WSL is not ready. Enabling Windows WSL features..."
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "install-wsl-windows-features.ps1")
      Write-Host ""
      Write-Host "If Windows requested a restart, reboot, then run this installer again."
    }
  } catch {
    Write-Host "Could not check WSL status. Enabling WSL features..."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "install-wsl-windows-features.ps1")
  }
}

Write-Host "Installing CMD command..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "install.ps1")

Write-Host "Installing CMD alias..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "install-cmd-alias.ps1")

Write-Host "Installing Chrome extension policy and updater..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "force-install-chrome-extension.ps1")

Write-Host "Starting proxy backend..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts\wsl-proxy.ps1") -Start

Write-Host ""
Write-Host "Install complete."
Write-Host "Open a new CMD window and use:"
Write-Host "  WSL"
Write-Host "  WSL status"
Write-Host "  WSL stop"
Write-Host ""
Write-Host "Restart Chrome, then enable WSL Proxy Toggle."
Write-Host "State/log folder:"
Write-Host "  $installRoot"
