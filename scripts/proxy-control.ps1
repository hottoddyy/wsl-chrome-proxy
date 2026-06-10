#Requires -Version 5.1
<#
.SYNOPSIS
  Controls the WSL Chrome Proxy.

.PARAMETER Command
  start   Start (or restart) the proxy and update server.
  stop    Stop both.
  status  Show current state.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet("start","stop","status","")]
    [string]$Command = "start"
)

$ErrorActionPreference = "SilentlyContinue"

$installRoot   = Join-Path $env:LOCALAPPDATA "WslChromeProxy"
$startupScript = Join-Path $installRoot "Start-WslChromeProxy.ps1"
$extDir        = Join-Path $installRoot "ChromeExtension"
$serverPidPath = Join-Path $extDir "update-server.pid"
$scriptsDir    = Join-Path $installRoot "scripts"

function Get-ServerPid {
    if (-not (Test-Path $serverPidPath)) { return $null }
    $p = (Get-Content $serverPidPath -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $p) { return $null }
    $proc = Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue
    return $proc
}

function Stop-Proxy {
    # Stop update server
    $proc = Get-ServerPid
    if ($proc) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Remove-Item $serverPidPath -Force -ErrorAction SilentlyContinue
        Write-Host "Extension update server stopped." -ForegroundColor Yellow
    }

    # Stop WSL proxy (read config from startup script to find port/distro)
    $proxyPort = 18080
    $distro    = "Ubuntu"
    if (Test-Path $startupScript) {
        $content = Get-Content $startupScript -Raw
        if ($content -match '`\$ProxyPort\s*=\s*(\d+)') { $proxyPort = [int]$Matches[1] }
        if ($content -match '`\$Distro\s*=\s*"([^"]+)"') { $distro = $Matches[1] }
    }

    & wsl.exe -d $distro sh -lc "pkill -f 'local-http-proxy.py.*--port $proxyPort' 2>/dev/null; rm -f /tmp/wsl-chrome-proxy/proxy.pid" 2>$null | Out-Null
    Write-Host "WSL proxy stopped." -ForegroundColor Yellow
}

function Start-Proxy {
    if (-not (Test-Path $startupScript)) {
        Write-Host "Not installed. Run Install.cmd first." -ForegroundColor Red
        exit 1
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startupScript
    Write-Host "Proxy started." -ForegroundColor Green
}

function Show-Status {
    $serverProc = Get-ServerPid
    if ($serverProc) {
        Write-Host "Extension update server: running (PID $($serverProc.Id))" -ForegroundColor Green
    } else {
        Write-Host "Extension update server: stopped" -ForegroundColor Yellow
    }

    $proxyPort = 18080
    $distro    = "Ubuntu"
    if (Test-Path $startupScript) {
        $content = Get-Content $startupScript -Raw
        if ($content -match '`\$ProxyPort\s*=\s*(\d+)') { $proxyPort = [int]$Matches[1] }
        if ($content -match '`\$Distro\s*=\s*"([^"]+)"') { $distro = $Matches[1] }
    }

    $portCheck = (& wsl.exe -d $distro sh -lc "ss -ltn 2>/dev/null | grep -c ':$proxyPort '" 2>$null |
                  Select-Object -First 1).Trim()
    if ([int]$portCheck -gt 0) {
        Write-Host "WSL proxy (127.0.0.1:$proxyPort): running" -ForegroundColor Green
    } else {
        Write-Host "WSL proxy (127.0.0.1:$proxyPort): stopped" -ForegroundColor Yellow
    }
}

switch ($Command.ToLower()) {
    "stop"   { Stop-Proxy }
    "status" { Show-Status }
    default  { Start-Proxy }
}
