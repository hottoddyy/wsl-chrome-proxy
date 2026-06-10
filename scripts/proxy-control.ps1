#Requires -Version 5.1
<#
.SYNOPSIS
  Controls the WSL Chrome Proxy.

.PARAMETER Command
  start    Start (or restart) the proxy and update server.
  stop     Stop both.
  status   Show current state.
  update   Download the latest release from GitHub and re-install.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet("start","stop","status","update","")]
    [string]$Command = "start"
)

$ErrorActionPreference = "SilentlyContinue"

$repoOwner   = "hottoddyy"
$repoName    = "wsl-chrome-proxy"
$installRoot = Join-Path $env:LOCALAPPDATA "WslChromeProxy"

$startupScript = Join-Path $installRoot "Start-WslChromeProxy.ps1"
$extDir        = Join-Path $installRoot "ChromeExtension"
$serverPidPath = Join-Path $extDir "update-server.pid"
$scriptsDir    = Join-Path $installRoot "scripts"

# ── helpers ───────────────────────────────────────────────────────────────────
function Get-ServerPid {
    if (-not (Test-Path $serverPidPath)) { return $null }
    $p = (Get-Content $serverPidPath -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $p) { return $null }
    return Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue
}

function Get-ProxyConfig {
    $port   = 18080
    $distro = "Ubuntu"
    if (Test-Path $startupScript) {
        $c = Get-Content $startupScript -Raw
        if ($c -match '\$ProxyPort\s*=\s*(\d+)')    { $port   = [int]$Matches[1] }
        if ($c -match '\$Distro\s*=\s*"([^"]+)"')   { $distro = $Matches[1] }
    }
    return @{ Port = $port; Distro = $distro }
}

# ── commands ──────────────────────────────────────────────────────────────────
function Stop-Proxy {
    $proc = Get-ServerPid
    if ($proc) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Remove-Item $serverPidPath -Force -ErrorAction SilentlyContinue
        Write-Host "Extension update server stopped." -ForegroundColor Yellow
    }

    $cfg = Get-ProxyConfig
    & wsl.exe -d $cfg.Distro sh -lc "pkill -f 'local-http-proxy.py' 2>/dev/null; rm -f /tmp/wsl-chrome-proxy/proxy.pid" 2>$null | Out-Null
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
        Write-Host "Update server:  running (PID $($serverProc.Id))" -ForegroundColor Green
    } else {
        Write-Host "Update server:  stopped" -ForegroundColor Yellow
    }

    $cfg        = Get-ProxyConfig
    $portCheck  = (& wsl.exe -d $cfg.Distro sh -lc "ss -ltn 2>/dev/null | grep -c ':$($cfg.Port) '" 2>$null |
                   Select-Object -First 1).Trim()
    if ([int]$portCheck -gt 0) {
        Write-Host "WSL proxy:      running  (127.0.0.1:$($cfg.Port))" -ForegroundColor Green
    } else {
        Write-Host "WSL proxy:      stopped  (127.0.0.1:$($cfg.Port))" -ForegroundColor Yellow
    }

    # Show installed version if recorded
    $verFile = Join-Path $installRoot "version.txt"
    if (Test-Path $verFile) {
        Write-Host "Installed:      $(Get-Content $verFile -Raw)" -ForegroundColor DarkGray
    }
}

function Update-Proxy {
    Write-Host ""
    Write-Host "  Checking for updates..." -ForegroundColor Cyan

    # Fetch latest release metadata from GitHub API
    $ErrorActionPreference = "Stop"
    try {
        $apiUrl  = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    } catch {
        Write-Host "  Could not reach GitHub: $_" -ForegroundColor Red
        exit 1
    }

    $latestTag = $release.tag_name
    Write-Host "  Latest release: $latestTag" -ForegroundColor White

    # Compare with installed version
    $verFile = Join-Path $installRoot "version.txt"
    if (Test-Path $verFile) {
        $installed = (Get-Content $verFile -Raw).Trim()
        if ($installed -eq $latestTag) {
            Write-Host "  Already up to date ($installed)." -ForegroundColor Green
            exit 0
        }
        Write-Host "  Installed: $installed  ->  $latestTag" -ForegroundColor White
    }

    # Find the ZIP asset
    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if (-not $asset) {
        Write-Host "  No ZIP asset found in release $latestTag." -ForegroundColor Red
        exit 1
    }

    Write-Host "  Downloading $($asset.name)..." -ForegroundColor Cyan
    $zipPath     = Join-Path $env:TEMP "wsl-chrome-proxy-update.zip"
    $extractPath = Join-Path $env:TEMP "wsl-chrome-proxy-update"

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing

    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    # Find Install.ps1 inside the extracted folder
    $installer = Get-ChildItem $extractPath -Recurse -Filter "Install.ps1" | Select-Object -First 1
    if (-not $installer) {
        Write-Host "  Install.ps1 not found in the downloaded archive." -ForegroundColor Red
        exit 1
    }

    Write-Host "  Installing $latestTag..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer.FullName

    # Clean up temp files
    Remove-Item $zipPath     -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# ── dispatch ──────────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "stop"   { Stop-Proxy }
    "status" { Show-Status }
    "update" { Update-Proxy }
    default  { Start-Proxy }
}
