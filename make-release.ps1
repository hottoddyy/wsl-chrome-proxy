#Requires -Version 5.1
<#
.SYNOPSIS
  Builds the release ZIP and creates a GitHub release.

.PARAMETER Tag
  The version tag, e.g. v1.3.0. Defaults to whatever is in VERSION file.

.PARAMETER Notes
  Optional release notes. Leave blank to use a default message.
#>
param(
    [string]$Tag   = ((Get-Content (Join-Path $PSScriptRoot "VERSION") -Raw).Trim()),
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# Update VERSION file
Set-Content -LiteralPath (Join-Path $root "VERSION") -Value $Tag -Encoding ASCII

# Build ZIP
$zipPath = Join-Path $root "release-$Tag.zip"
$tempDir = Join-Path $root "_release_tmp"
$pkgRoot = Join-Path $tempDir "wsl-chrome-proxy"

if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $pkgRoot | Out-Null

$items = @(
    "chrome-extension",
    "scripts",
    "wsl",
    "chrome-extension.crx",
    "chrome-extension.pem",
    "Install.cmd",
    "Install.ps1",
    "Proxy.cmd",
    "Uninstall.ps1",
    "setup.iss",
    "README.md",
    "VERSION"
)
foreach ($item in $items) {
    $src = Join-Path $root $item
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $pkgRoot -Recurse -Force
    }
}

Compress-Archive -LiteralPath $pkgRoot -DestinationPath $zipPath -Force
Remove-Item $tempDir -Recurse -Force
Write-Host "Built: $zipPath  ($([int]((Get-Item $zipPath).Length/1kb)) KB)"

# Build Inno Setup installer
$iscc    = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$exePath = Join-Path $root "WSLChromeProxy-Setup.exe"
if (Test-Path $iscc) {
    Write-Host "Building installer EXE..."
    & $iscc (Join-Path $root "setup.iss") | Out-Null
    Write-Host "Built: $exePath  ($([int]((Get-Item $exePath).Length/1kb)) KB)"
} else {
    Write-Host "Inno Setup not found - skipping EXE build." -ForegroundColor Yellow
    $exePath = $null
}

# Publish to GitHub
$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = "gh" }

if (-not $Notes) {
    $Notes = "Release $Tag. Download WSLChromeProxy-Setup.exe and run it to install."
}

$assets = @($zipPath)
if ($exePath -and (Test-Path $exePath)) { $assets += $exePath }

& $gh release create $Tag @assets --title $Tag --notes $Notes
Remove-Item $zipPath -Force
if ($exePath -and (Test-Path $exePath)) { Remove-Item $exePath -Force }
Write-Host "Released: $Tag"
