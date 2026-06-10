#Requires -Version 5.1
<#
.SYNOPSIS
  Removes WSL Chrome Proxy completely.
#>
[CmdletBinding()]
param(
    [switch]$Confirm,
    # Set when invoked by the Inno Setup uninstaller. Leaves Inno's own
    # unins000.* files (and the directory) in place so Inno can finish and
    # deregister the Apps & Features entry. A standalone run wipes everything.
    [switch]$KeepInstallDir
)

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
# Note: HKCU\Software\Policies\Google\Chrome has a restricted ACL when IT Group
# Policy manages it. Try normally first; if any fail, do one elevated pass for all.
$policyRoot  = "HKCU:\Software\Policies\Google\Chrome"
$subKeys     = @("ExtensionInstallForcelist","ExtensionInstallAllowlist","ExtensionInstallSources")
$needElevate = $false

foreach ($sub in $subKeys) {
    try {
        Remove-Item -Path "$policyRoot\$sub" -Recurse -Force -ErrorAction Stop
    } catch { $needElevate = $true }
}

# Try removing ExtensionSettings value normally
try {
    Remove-ItemProperty -Path $policyRoot -Name "ExtensionSettings" -ErrorAction Stop
} catch { $needElevate = $true }

if ($needElevate) {
    $cmds = ($subKeys | ForEach-Object {
        "reg delete `"HKCU\Software\Policies\Google\Chrome\$_`" /f 2>`$null"
    }) -join "; "
    $cmds += "; reg delete `"HKCU\Software\Policies\Google\Chrome`" /v `"ExtensionSettings`" /f 2>`$null"
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmds
    )
}
Write-Host "  Removed Chrome extension policy." -ForegroundColor DarkGray

# Remove install directory
if ($KeepInstallDir) {
    # Inno is mid-uninstall and running unins000.exe from this folder. Delete
    # everything except its uninstaller files so it can finish and deregister.
    Get-ChildItem -LiteralPath $installRoot -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "unins000.*" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Cleaned $installRoot (Inno will remove the rest)." -ForegroundColor DarkGray
} else {
    Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed $installRoot" -ForegroundColor DarkGray
}

# Remove Proxy.cmd shim from %USERPROFILE%\bin
$binDir   = Join-Path $env:USERPROFILE "bin"
$proxyCmd = Join-Path $binDir "Proxy.cmd"
Remove-Item -LiteralPath $proxyCmd -Force -ErrorAction SilentlyContinue
Write-Host "  Removed Proxy.cmd shim." -ForegroundColor DarkGray

# Legacy cleanup: old WSL.cmd shim and doskey AutoRun alias (pre-v1 installer)
$oldWslCmd = Join-Path $binDir "WSL.cmd"
if (Test-Path $oldWslCmd) {
    Remove-Item -LiteralPath $oldWslCmd -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed legacy WSL.cmd shim." -ForegroundColor DarkGray
}
$autoRunPath  = "HKCU:\Software\Microsoft\Command Processor"
$autoRunValue = (Get-ItemProperty -Path $autoRunPath -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
if ($autoRunValue -and $autoRunValue -match 'WSL') {
    Remove-ItemProperty -Path $autoRunPath -Name AutoRun -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed legacy doskey WSL alias from AutoRun." -ForegroundColor DarkGray
}

# Legacy cleanup: netsh portproxy rule on the proxy port (pre-v1 installer).
# A stale rule hijacks 127.0.0.1:<port> ahead of WSL2 localhost forwarding and
# resets every connection. Deleting it needs admin, so only elevate when found.
$portproxyOut = (netsh interface portproxy show v4tov4) -join "`n"
if ($portproxyOut -match "127\.0\.0\.1\s+$proxyPort\s") {
    Write-Host "  Found legacy portproxy rule on port $proxyPort - removing (needs admin)..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
        "-NoProfile", "-Command",
        "netsh interface portproxy delete v4tov4 listenport=$proxyPort listenaddress=127.0.0.1"
    )
    Write-Host "  Removed legacy portproxy rule." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Done. Restart Chrome to remove the extension." -ForegroundColor Green
Write-Host ""
if (-not $Confirm) { Read-Host "Press Enter to close" }
