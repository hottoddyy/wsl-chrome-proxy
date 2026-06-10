[CmdletBinding()]
param(
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Split-Path -Parent $root) "wsl-chrome-proxy-installer.zip"
}
$tempRoot = Join-Path $env:TEMP ("wsl-chrome-proxy-package-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $tempRoot "wsl-chrome-proxy"

New-Item -ItemType Directory -Path $packageRoot | Out-Null

$items = @(
  "chrome-extension",
  "scripts",
  "wsl",
  "chrome-extension.crx",
  "chrome-extension.pem",
  "force-install-chrome-extension.ps1",
  "install-all.ps1",
  "install-chrome-extension.ps1",
  "install-cmd-alias.ps1",
  "install-wsl-windows-features.ps1",
  "INSTALL-FROM-ZIP.txt",
  "install.ps1",
  "README.md",
  "WSL.cmd"
)

foreach ($item in $items) {
  $source = Join-Path $root $item
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination $packageRoot -Recurse -Force
  }
}

if (Test-Path -LiteralPath $OutputPath) {
  Remove-Item -LiteralPath $OutputPath -Force
}

Compress-Archive -LiteralPath $packageRoot -DestinationPath $OutputPath -Force
Remove-Item -LiteralPath $tempRoot -Recurse -Force

Write-Host "Created:"
Write-Host "  $OutputPath"
