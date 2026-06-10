#Requires -Version 5.1
<#
.SYNOPSIS
  Removes WSL Chrome Proxy completely.
#>
[CmdletBinding()]
param([switch]$Confirm)

$ErrorActionPreference = "SilentlyContinue"

if (-not $Confirm) {
    $answer = Read-Host "This will remove WSL Chrome Proxy. Continue? (y/N)"
    if ($answer -notmatch '^[yY]') { Write-Host "Cancelled."; exit 0 }
}

$installRoot   = Join-Path $env:LOCALAPPDATA "WslChromeProxy"
$extDir        = Join-Path $installRoot "ChromeExtension"
$serverPidPath = Join-Path $extDir "update-server.pid"
$scriptsDir    = Join-Path $installRoot "scripts"
$startupScript = Join-Path $installRoot "Start-WslChromeProxy.ps1"

Write-Host ""
Write-Host "  Uninstalling WSL Chrome Proxy..." -ForegroundColor White
Write-Host ""

# Stop update server
if (Test-Path $serverPidPath) {
    $p = (Get-Content $serverPidPath -Raw).Trim()
    if ($p) { Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue }
    Remove-Item $serverPidPath -Force -ErrorAction SilentlyContinue
}
Write-Host "  Stopped extension update server." -ForegroundColor DarkGray

# Stop WSL proxy
$proxyPort = 18080
$distro    = "Ubuntu"
if (Test-Path $startupScript) {
    $content = Get-Content $startupScript -Raw
    if ($content -match '`\$ProxyPort\s*=\s*(\d+)') { $proxyPort = [int]$Matches[1] }
    if ($content -match '`\$Distro\s*=\s*"([^"]+)"') { $distro = $Matches[1] }
}
& wsl.exe -d $distro sh -lc "pkill -f 'local-http-proxy.py.*--port $proxyPort' 2>/dev/null; rm -rf /tmp/wsl-chrome-proxy" 2>$null | Out-Null
Write-Host "  Stopped WSL proxy." -ForegroundColor DarkGray

# Remove HKCU\Run autostart
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WslChromeProxy" -ErrorAction SilentlyContinue
Write-Host "  Removed autostart." -ForegroundColor DarkGray

# Remove Chrome policy
$policyRoot = "HKCU:\Software\Policies\Google\Chrome"
foreach ($key in @(
    "$policyRoot\ExtensionInstallForcelist",
    "$policyRoot\ExtensionInstallAllowlist",
    "$policyRoot\ExtensionInstallSources"
)) {
    Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-ItemProperty -Path $policyRoot -Name "ExtensionSettings" -ErrorAction SilentlyContinue
Write-Host "  Removed Chrome extension policy." -ForegroundColor DarkGray

# Remove install directory
Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  Removed $installRoot" -ForegroundColor DarkGray

Write-Host ""
Write-Host "  Done. Restart Chrome to remove the extension." -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
