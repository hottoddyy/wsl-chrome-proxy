#Requires -Version 5.1
<#
.SYNOPSIS
  Installs WSL Chrome Proxy. Does not require Administrator.

.DESCRIPTION
  - Copies proxy files to %LOCALAPPDATA%\WslChromeProxy\
  - Starts a local CRX update server so Chrome can install the extension
    without Developer mode
  - Writes Chrome extension policy to HKCU (no admin needed)
  - Starts the HTTP/HTTPS proxy inside WSL Ubuntu
  - Registers an autostart entry in HKCU\Run so the proxy comes back
    after a reboot

.PARAMETER ProxyPort
  Port the Python proxy listens on inside WSL (default 18080).
  WSL2 localhost-forwarding makes this available at 127.0.0.1:<ProxyPort>
  from Windows with no portproxy or admin rights.

.PARAMETER UpdateServerPort
  Port for the local CRX HTTP server (default 18082).

.PARAMETER Distro
  WSL distro name (default Ubuntu).
#>
[CmdletBinding()]
param(
    [int]$ProxyPort        = 18080,
    [int]$UpdateServerPort = 18082,
    [string]$Distro        = "Ubuntu"
)

$ErrorActionPreference = "Stop"

# ── constants ────────────────────────────────────────────────────────────────
$extensionId      = "apchgcioodnlnhbgdokfccpojkcanjnk"
$extensionVersion = "1.0.0"

# ── install paths ─────────────────────────────────────────────────────────────
$installRoot   = Join-Path $env:LOCALAPPDATA "WslChromeProxy"
$wslDir        = Join-Path $installRoot "wsl"
$extDir        = Join-Path $installRoot "ChromeExtension"
$scriptsDir    = Join-Path $installRoot "scripts"
$serverPidPath = Join-Path $extDir "update-server.pid"
$startupScript = Join-Path $installRoot "Start-WslChromeProxy.ps1"

# ── helpers ───────────────────────────────────────────────────────────────────
function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   ! $msg" -ForegroundColor Yellow }
function Write-Fail {
    param($msg)
    Write-Host "  !! $msg" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

# ── header ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  WSL Chrome Proxy  -  Installer" -ForegroundColor White
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host ""

# ── 1. Check WSL + distro ─────────────────────────────────────────────────────
Write-Step "Checking WSL..."
try {
    $wslOut = & wsl.exe --list --quiet 2>&1
    if ($LASTEXITCODE -ne 0) { throw "wsl.exe --list returned exit code $LASTEXITCODE" }
    $found = ($wslOut | Where-Object { $_ -match [regex]::Escape($Distro) }).Count -gt 0
    if (-not $found) {
        Write-Host ""
        Write-Fail ("WSL distro '$Distro' not found.`n" +
                    "  Run the following once (requires admin), then run Install.cmd again:`n`n" +
                    "    wsl.exe --install -d Ubuntu`n")
    }
    Write-OK "WSL distro '$Distro' is ready."
} catch {
    Write-Host ""
    Write-Fail ("WSL is not available on this PC.`n" +
                "  To enable WSL (requires admin, once):`n`n" +
                "    wsl.exe --install -d Ubuntu`n`n" +
                "  Reboot when prompted, then run Install.cmd again.`n")
}

# ── 2. Create install directories ─────────────────────────────────────────────
Write-Step "Creating directories..."
foreach ($d in @($installRoot, $wslDir, $extDir, $scriptsDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}
Write-OK $installRoot

# ── 3. Copy files ─────────────────────────────────────────────────────────────
Write-Step "Copying files..."
$copies = @(
    @{ Src = "wsl\local-http-proxy.py";                     Dst = Join-Path $wslDir     "local-http-proxy.py" },
    @{ Src = "wsl\start-proxy.sh";                          Dst = Join-Path $wslDir     "start-proxy.sh" },
    @{ Src = "scripts\chrome-extension-update-server.ps1";  Dst = Join-Path $scriptsDir "chrome-extension-update-server.ps1" },
    @{ Src = "chrome-extension.crx";                        Dst = Join-Path $extDir     "wsl-proxy-toggle.crx" }
)
foreach ($c in $copies) {
    $src = Join-Path $PSScriptRoot $c.Src
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Fail "Missing source file: $src"
    }
    Copy-Item -LiteralPath $src -Destination $c.Dst -Force
}
Write-OK "Files ready."

# ── 4. Generate update.xml ────────────────────────────────────────────────────
Write-Step "Writing extension update manifest..."
$crxUrl    = "http://127.0.0.1:$UpdateServerPort/wsl-proxy-toggle.crx"
$updateUrl = "http://127.0.0.1:$UpdateServerPort/update.xml"
$updateXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
  <app appid="$extensionId">
    <updatecheck codebase="$crxUrl" version="$extensionVersion" />
  </app>
</gupdate>
"@
Set-Content -LiteralPath (Join-Path $extDir "update.xml") -Value $updateXml -Encoding ASCII
Write-OK "update.xml written."

# ── 5. Start CRX update server ────────────────────────────────────────────────
Write-Step "Starting extension update server (port $UpdateServerPort)..."
$serverRunning = $false
if (Test-Path -LiteralPath $serverPidPath) {
    $savedPid = (Get-Content -LiteralPath $serverPidPath -Raw).Trim()
    if ($savedPid) {
        $serverRunning = [bool](Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue)
    }
}
if (-not $serverRunning) {
    $serverPs = Join-Path $scriptsDir "chrome-extension-update-server.ps1"
    $proc = Start-Process powershell.exe -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$serverPs`"",
        "-Port", $UpdateServerPort,
        "-Root", "`"$extDir`""
    ) -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $serverPidPath -Value $proc.Id -Encoding ASCII
    Write-OK "Update server started (PID $($proc.Id))."
} else {
    Write-OK "Update server already running."
}

# ── 6. Chrome extension policy (HKCU — no admin) ─────────────────────────────
Write-Step "Writing Chrome policy..."
$policyRoot = "HKCU:\Software\Policies\Google\Chrome"
$forceList  = "$policyRoot\ExtensionInstallForcelist"
$allowList  = "$policyRoot\ExtensionInstallAllowlist"
$sourceList = "$policyRoot\ExtensionInstallSources"

foreach ($key in @($forceList, $allowList, $sourceList)) {
    New-Item -Path $key -Force | Out-Null
}
Set-ItemProperty -Path $forceList  -Name "1" -Value "$extensionId;$updateUrl"
Set-ItemProperty -Path $allowList  -Name "1" -Value $extensionId
Set-ItemProperty -Path $sourceList -Name "1" -Value "http://127.0.0.1/*"
Set-ItemProperty -Path $sourceList -Name "2" -Value "http://127.0.0.1:$UpdateServerPort/*"

$extSettings = @{
    $extensionId = @{
        installation_mode = "force_installed"
        update_url        = $updateUrl
    }
} | ConvertTo-Json -Compress -Depth 5
Set-ItemProperty -Path $policyRoot -Name "ExtensionSettings" -Value $extSettings
Write-OK "Chrome will install the extension automatically (no Developer mode needed)."

# ── 7. Resolve WSL paths ──────────────────────────────────────────────────────
Write-Step "Resolving WSL file paths..."
function ConvertTo-WslPath {
    param([string]$WinPath)
    $esc    = "'" + ($WinPath -replace "'", "'\''") + "'"
    $result = (& wsl.exe -d $Distro wslpath -a $esc 2>$null | Select-Object -First 1).Trim()
    if (-not $result) { throw "Could not convert to WSL path: $WinPath" }
    return $result
}
try {
    $wslShPath = ConvertTo-WslPath (Join-Path $wslDir "start-proxy.sh")
    $wslPyPath = ConvertTo-WslPath (Join-Path $wslDir "local-http-proxy.py")
} catch {
    Write-Fail "WSL path conversion failed: $_"
}
Write-OK "WSL paths resolved."

# ── 8. Start WSL proxy ────────────────────────────────────────────────────────
#
#  WSL2 localhost forwarding (on by default) makes any port bound to
#  0.0.0.0 inside WSL accessible at 127.0.0.1:<port> on Windows.
#  No netsh portproxy or admin rights needed.
#
Write-Step "Starting WSL proxy on Ubuntu port $ProxyPort..."
$startCmd = "sh '$wslShPath' $ProxyPort '$wslPyPath'"
& wsl.exe -d $Distro sh -lc $startCmd 2>$null | Out-Null
Start-Sleep -Milliseconds 500

$portCheck = (& wsl.exe -d $Distro sh -lc "ss -ltn 2>/dev/null | grep -c ':$ProxyPort '" 2>$null |
              Select-Object -First 1).Trim()
if ([int]$portCheck -gt 0) {
    Write-OK "Proxy listening on Ubuntu:$ProxyPort -> Windows:127.0.0.1:$ProxyPort"
} else {
    Write-Warn "Port check inconclusive — proxy may take a moment to start."
}

# ── 9. Write startup script + HKCU\Run ───────────────────────────────────────
Write-Step "Registering autostart..."

# We bake the resolved WSL paths in so the startup script needs no discovery.
$startupContent = @"
`$ErrorActionPreference = "SilentlyContinue"

# Extension update server
`$extDir          = "$extDir"
`$serverPidPath   = Join-Path `$extDir "update-server.pid"
`$serverPs        = "$scriptsDir\chrome-extension-update-server.ps1"
`$UpdateServerPort = $UpdateServerPort

`$running = `$false
if (Test-Path `$serverPidPath) {
    `$p = (Get-Content `$serverPidPath -Raw).Trim()
    if (`$p) { `$running = [bool](Get-Process -Id ([int]`$p) -ErrorAction SilentlyContinue) }
}
if (-not `$running) {
    `$proc = Start-Process powershell.exe -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"`$serverPs`"",
        "-Port", `$UpdateServerPort,
        "-Root", "`"`$extDir`""
    ) -WindowStyle Hidden -PassThru
    Set-Content `$serverPidPath -Value `$proc.Id -Encoding ASCII
}

# WSL proxy
`$wslShPath = "$wslShPath"
`$wslPyPath = "$wslPyPath"
`$ProxyPort = $ProxyPort
`$Distro    = "$Distro"
& wsl.exe -d `$Distro sh -lc "sh '`$wslShPath' `$ProxyPort '`$wslPyPath'" 2>`$null | Out-Null
"@

Set-Content -LiteralPath $startupScript -Value $startupContent -Encoding UTF8

$runKey   = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$runValue = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startupScript`""
Set-ItemProperty -Path $runKey -Name "WslChromeProxy" -Value $runValue
Write-OK "Proxy will restart automatically after login."

# ── done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Proxy running at  127.0.0.1:$ProxyPort" -ForegroundColor White
Write-Host "  Autostart         enabled" -ForegroundColor White
Write-Host ""
Write-Host "  --> Fully close and reopen Chrome." -ForegroundColor Yellow
Write-Host "      The WSL Proxy Toggle extension will appear in your toolbar." -ForegroundColor White
Write-Host ""
Write-Host "  Day-to-day:" -ForegroundColor DarkGray
Write-Host "    Proxy.cmd start    start or restart the proxy" -ForegroundColor DarkGray
Write-Host "    Proxy.cmd stop     stop the proxy" -ForegroundColor DarkGray
Write-Host "    Proxy.cmd status   show current state" -ForegroundColor DarkGray
Write-Host ""
Read-Host "Press Enter to close"
