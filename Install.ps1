#Requires -Version 5.1
<#
.SYNOPSIS
  Installs WSL Chrome Proxy - including WSL and Ubuntu if needed.

.DESCRIPTION
  Handles everything from scratch:
    - Installs WSL 2 + Ubuntu if not present (self-elevates for that step only,
      then continues as the current user for all other steps)
    - Copies proxy files to %LOCALAPPDATA%\WslChromeProxy\
    - Starts a local CRX update server so Chrome installs the extension
      automatically, with no Developer mode required
    - Writes Chrome extension policy to HKCU (no admin)
    - Starts the HTTP/HTTPS proxy inside WSL Ubuntu
    - Registers an autostart entry so the proxy restarts after login

.PARAMETER InstallWslOnly
  Internal flag. When set the script runs elevated to install WSL + Ubuntu,
  then exits. Do not pass this yourself.

.PARAMETER ProxyPort
  Port the Python proxy listens on inside WSL (default 18080).

.PARAMETER UpdateServerPort
  Port for the local CRX HTTP server (default 18082).

.PARAMETER Distro
  WSL distro to use (default Ubuntu).
#>
[CmdletBinding()]
param(
    [switch]$InstallWslOnly,
    [switch]$NoPause,
    [int]$ProxyPort        = 18080,
    [int]$UpdateServerPort = 18082,
    [string]$Distro        = "Ubuntu"
)

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
#  LOGGING + CRASH CAPTURE
#  The setup EXE runs us with -NoPause, so an unhandled error would otherwise
#  close the window before it can be read. Log everything to a file and trap any
#  terminating error so the user (and we) can see exactly what failed.
# ──────────────────────────────────────────────────────────────────────────────
$script:LogPath = Join-Path $env:TEMP "wsl-chrome-proxy-install.log"
if (-not $InstallWslOnly) {
    try { Start-Transcript -Path $script:LogPath -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
}

trap {
    Write-Host ""
    Write-Host "  !! Installation failed with an unexpected error:" -ForegroundColor Red
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host "     at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  A full log was saved to:" -ForegroundColor Yellow
    Write-Host "     $script:LogPath" -ForegroundColor White
    Write-Host ""
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    # Always pause on failure so the error is readable, even under -NoPause (EXE).
    Read-Host "Press Enter to close"
    exit 1
}

# ?????????????????????????????????????????????????????????????????????????????
#  ELEVATED PHASE  (only reached when -InstallWslOnly is passed)
#  Installs WSL features + Ubuntu, then exits.
#  The parent process (running as the current user) waits for this and
#  then continues with all the HKCU / proxy steps.
# ?????????????????????????????????????????????????????????????????????????????
if ($InstallWslOnly) {
    Write-Host ""
    Write-Host "  [Elevated] Installing WSL 2 + Ubuntu..." -ForegroundColor Cyan

    # wsl --install handles enabling features + downloading Ubuntu in one go.
    # --no-launch skips the first-run username/password prompt; the proxy
    # runs fine as root until a user chooses to configure one.
    $installArgs = @("--install", "-d", $Distro)

    # --no-launch is supported on Windows 10 21H2+ / Windows 11
    $wslHelp = & wsl.exe --help 2>&1
    if ($wslHelp -match "no-launch") {
        $installArgs += "--no-launch"
    }

    Write-Host "  Running: wsl.exe $($installArgs -join ' ')" -ForegroundColor DarkGray
    & wsl.exe @installArgs

    # Did we get here without a forced reboot? Signal success to the parent.
    exit 0
}

# ?????????????????????????????????????????????????????????????????????????????
#  HELPERS
# ?????????????????????????????????????????????????????????????????????????????
function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   ! $msg" -ForegroundColor Yellow }
function Write-Fail {
    param($msg)
    Write-Host ""
    Write-Host "  !! $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host "  A full log was saved to: $script:LogPath" -ForegroundColor Yellow
    Write-Host ""
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    # Always pause on failure so the error is readable, even under -NoPause (EXE).
    Read-Host "Press Enter to close"
    exit 1
}

function Test-WslDistro {
    param([string]$Name)
    try {
        # wsl.exe emits UTF-16 output; when PowerShell reads it with the wrong
        # encoding every other byte is a null char, so strip them before matching.
        $list = ((& wsl.exe --list --quiet 2>&1) -join "`n") -replace "`0", ""
        if ($LASTEXITCODE -ne 0) { return $false }
        return $list -match [regex]::Escape($Name)
    } catch { return $false }
}

function Test-WslWorks {
    param([string]$Name)
    try {
        $out = & wsl.exe -d $Name echo "ok" 2>&1
        return ($out -join "") -match "ok"
    } catch { return $false }
}

function ConvertTo-WslPath {
    param([string]$WinPath)
    $esc    = "'" + ($WinPath -replace "'", "'\''") + "'"
    $result = (& wsl.exe -d $Distro wslpath -a $esc 2>$null | Select-Object -First 1).Trim()
    if (-not $result) { throw "Could not convert to WSL path: $WinPath" }
    return $result
}

function Copy-IntoWsl {
    # Pushes a Windows text file into WSL's own filesystem at
    # $HOME/.wsl-chrome-proxy/<DestName>, stripping CR and any BOM. Uses base64
    # over stdin so it never touches the /mnt/c drvfs mount - which can hide
    # newly-created folders and mangle line endings.
    param([string]$WinPath, [string]$DestName, [string]$DistroName)
    $text  = [System.IO.File]::ReadAllText($WinPath) -replace "`r", ""
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $b64   = [Convert]::ToBase64String($bytes)
    $cmd   = "mkdir -p `$HOME/.wsl-chrome-proxy && printf '%s' '$b64' | base64 -d > `$HOME/.wsl-chrome-proxy/$DestName"
    & wsl.exe -d $DistroName sh -c $cmd
}

function Test-PendingReboot {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

# ?????????????????????????????????????????????????????????????????????????????
#  HEADER
# ?????????????????????????????????????????????????????????????????????????????
Write-Host ""
Write-Host "  WSL Chrome Proxy  -  Installer" -ForegroundColor White
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host ""

# ?????????????????????????????????????????????????????????????????????????????
#  0. Stop any existing instance (makes re-running / updating safe)
# ?????????????????????????????????????????????????????????????????????????????
$installRoot   = Join-Path $env:LOCALAPPDATA "WslChromeProxy"
$extDir        = Join-Path $installRoot "ChromeExtension"
$serverPidPath = Join-Path $extDir "update-server.pid"
$scriptsDir    = Join-Path $installRoot "scripts"
$startupScript = Join-Path $installRoot "Start-WslChromeProxy.ps1"

Write-Step "Stopping any existing instance..."
# Stop update server
if (Test-Path -LiteralPath $serverPidPath) {
    $savedPid = (Get-Content -LiteralPath $serverPidPath -Raw -ErrorAction SilentlyContinue).Trim()
    if ($savedPid) {
        Stop-Process -Id ([int]$savedPid) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $serverPidPath -Force -ErrorAction SilentlyContinue
}
# Stop WSL proxy (kill by script name to catch any port). Wrapped because on a
# brand-new machine wsl.exe may be missing or have no distro yet - that's fine,
# there's nothing to stop.
try {
    & wsl.exe -d $Distro sh -lc "pkill -f 'local-http-proxy.py' 2>/dev/null; rm -f /tmp/wsl-chrome-proxy/proxy.pid" 2>$null | Out-Null
} catch { }

# A stale netsh portproxy rule (from older versions of this tool) hijacks
# 127.0.0.1:$ProxyPort ahead of WSL2 localhost forwarding and resets every
# connection. Deleting it needs admin, so only elevate when one is found.
$portproxyOut = (netsh interface portproxy show v4tov4 2>$null) -join "`n"
if ($portproxyOut -match "127\.0\.0\.1\s+$ProxyPort\s") {
    Write-Warn "Found a stale portproxy rule on port $ProxyPort - removing it (Windows will ask for admin)..."
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
        "-NoProfile", "-Command",
        "netsh interface portproxy delete v4tov4 listenport=$ProxyPort listenaddress=127.0.0.1"
    )
}
Write-OK "Clean slate."

# ?????????????????????????????????????????????????????????????????????????????
#  1. WSL + Ubuntu  (elevates only if needed)
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Checking WSL + Ubuntu..."

$wslReady = Test-WslDistro $Distro

if (-not $wslReady) {
    Write-Warn "WSL Ubuntu not found. Will install it now."
    Write-Warn "Windows will ask for Administrator permission for this step."
    Write-Host ""

    # Re-launch this script elevated with -InstallWslOnly.
    # We pass the distro name so it installs the right one.
    $elevatedArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-InstallWslOnly",
        "-Distro", $Distro
    )

    $proc = Start-Process powershell.exe `
        -ArgumentList $elevatedArgs `
        -Verb RunAs `
        -PassThru `
        -Wait

    if ($proc.ExitCode -ne 0) {
        Write-Fail ("WSL installation did not complete successfully (exit $($proc.ExitCode)).`n" +
                    "  If you declined the UAC prompt, run Install.cmd again and accept it.")
    }

    Write-Host ""

    # Check if a reboot is now required
    if (Test-PendingReboot) {
        Write-Host ""
        Write-Host "  Windows needs to reboot to finish enabling WSL." -ForegroundColor Yellow
        Write-Host "  After rebooting, double-click Install.cmd again to complete setup." -ForegroundColor Yellow
        Write-Host ""
        $r = Read-Host "  Reboot now? (y/N)"
        if ($r -match '^[yY]') {
            Restart-Computer -Force
        }
        exit 0
    }

    # Give WSL a moment to finish first-time initialisation
    Write-Host "  Waiting for Ubuntu to initialise..." -ForegroundColor DarkGray
    $attempts = 0
    do {
        Start-Sleep -Seconds 3
        $wslReady = Test-WslDistro $Distro
        $attempts++
    } while (-not $wslReady -and $attempts -lt 10)

    if (-not $wslReady) {
        Write-Fail ("Ubuntu was installed but is not showing up yet.`n" +
                    "  Try closing this window and running Install.cmd again.")
    }
}

# Verify we can actually execute commands in the distro
if (-not (Test-WslWorks $Distro)) {
    Write-Fail ("WSL '$Distro' is listed but cannot run commands.`n" +
                "  Try running: wsl -d $Distro`n" +
                "  If it asks to set up a username, complete that, then run Install.cmd again.")
}

Write-OK "WSL '$Distro' is ready."

# Make sure python3 is available (it ships with Ubuntu but just in case)
Write-Step "Checking Python 3 in WSL..."
$pyCheck = (& wsl.exe -d $Distro sh -lc "python3 --version 2>&1" | Select-Object -First 1).Trim()
if ($pyCheck -notmatch "Python 3") {
    Write-Warn "python3 not found. Installing it now (this may take a minute)..."
    & wsl.exe -d $Distro sh -lc "apt-get update -qq && apt-get install -y -qq python3 2>&1" | Out-Null
    $pyCheck = (& wsl.exe -d $Distro sh -lc "python3 --version 2>&1" | Select-Object -First 1).Trim()
    if ($pyCheck -notmatch "Python 3") {
        Write-Fail "Could not install python3 inside WSL. Check your internet connection and try again."
    }
}
Write-OK $pyCheck

# ?????????????????????????????????????????????????????????????????????????????
#  2. Install directories
# ?????????????????????????????????????????????????????????????????????????????
$wslDir = Join-Path $installRoot "wsl"

$extensionId      = "apchgcioodnlnhbgdokfccpojkcanjnk"
$extensionVersion = "1.0.0"

Write-Step "Creating install directories..."
foreach ($d in @($installRoot, $wslDir, $extDir, $scriptsDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}
Write-OK $installRoot

# ?????????????????????????????????????????????????????????????????????????????
#  3. Copy files
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Copying files..."
$copies = @(
    @{ Src = "wsl\local-http-proxy.py";                    Dst = Join-Path $wslDir     "local-http-proxy.py" },
    @{ Src = "wsl\start-proxy.sh";                         Dst = Join-Path $wslDir     "start-proxy.sh" },
    @{ Src = "scripts\chrome-extension-update-server.ps1"; Dst = Join-Path $scriptsDir "chrome-extension-update-server.ps1" },
    @{ Src = "chrome-extension.crx";                       Dst = Join-Path $extDir     "wsl-proxy-toggle.crx" },
    @{ Src = "scripts\proxy-control.ps1";                  Dst = Join-Path $scriptsDir "proxy-control.ps1" }
)
foreach ($c in $copies) {
    $src = Join-Path $PSScriptRoot $c.Src
    if (-not (Test-Path -LiteralPath $src)) { Write-Fail "Missing source file: $src" }
    # When run from the install dir itself (e.g. by the setup EXE), source and
    # destination can be the same file - skip those.
    if ((Resolve-Path -LiteralPath $src).Path -ne $c.Dst) {
        Copy-Item -LiteralPath $src -Destination $c.Dst -Force
    }
}
Write-OK "Files copied."

# ?????????????????????????????????????????????????????????????????????????????
#  4. update.xml for the local CRX server
# ?????????????????????????????????????????????????????????????????????????????
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
Write-OK "update.xml ready."

# ?????????????????????????????????????????????????????????????????????????????
#  5. Start local CRX update server
# ?????????????????????????????????????????????????????????????????????????????
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

# ?????????????????????????????????????????????????????????????????????????????
#  6. Chrome extension policy - HKCU, no admin
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Writing Chrome policy (HKCU - no admin needed)..."
$policyRoot = "HKCU:\Software\Policies\Google\Chrome"
$forceList  = "$policyRoot\ExtensionInstallForcelist"
$allowList  = "$policyRoot\ExtensionInstallAllowlist"
$sourceList = "$policyRoot\ExtensionInstallSources"

$extSettings = @{
    $extensionId = @{ installation_mode = "force_installed"; update_url = $updateUrl }
} | ConvertTo-Json -Compress -Depth 5

# HKCU\Software\Policies\Google\Chrome can carry a restricted ACL when IT Group
# Policy manages Chrome. Try the normal write first; if access is denied, do one
# elevated pass. UAC elevation stays under the same user account, so HKCU still
# refers to this user's hive.
$policyWritten = $false
try {
    foreach ($key in @($forceList, $allowList, $sourceList)) {
        New-Item -Path $key -Force -ErrorAction Stop | Out-Null
    }
    Set-ItemProperty -Path $forceList  -Name "1" -Value "$extensionId;$updateUrl" -ErrorAction Stop
    Set-ItemProperty -Path $allowList  -Name "1" -Value $extensionId -ErrorAction Stop
    Set-ItemProperty -Path $sourceList -Name "1" -Value "http://127.0.0.1/*" -ErrorAction Stop
    Set-ItemProperty -Path $sourceList -Name "2" -Value "http://127.0.0.1:$UpdateServerPort/*" -ErrorAction Stop
    Set-ItemProperty -Path $policyRoot -Name "ExtensionSettings" -Value $extSettings -ErrorAction Stop
    $policyWritten = $true
} catch {
    Write-Warn "Chrome policy key is access-restricted (IT-managed). Elevating for this step..."
}

if (-not $policyWritten) {
    # Quoting JSON through reg.exe / -Command is unreliable; write a temp script
    # and run it elevated with -File instead. Set-ItemProperty keeps the JSON
    # string intact (reg.exe strips the quote characters).
    $elevScript = Join-Path $installRoot "write-policy-elevated.ps1"
    @"
`$ErrorActionPreference = "Stop"
foreach (`$key in @(
    "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallForcelist",
    "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallAllowlist",
    "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallSources"
)) {
    if (-not (Test-Path `$key)) { New-Item -Path `$key -Force | Out-Null }
}
Set-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallForcelist" -Name "1" -Value "$extensionId;$updateUrl"
Set-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallAllowlist" -Name "1" -Value "$extensionId"
Set-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallSources" -Name "1" -Value "http://127.0.0.1/*"
Set-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome\ExtensionInstallSources" -Name "2" -Value "http://127.0.0.1:$UpdateServerPort/*"
Set-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome" -Name "ExtensionSettings" -Value '$extSettings'
exit 0
"@ | Set-Content -LiteralPath $elevScript -Encoding ASCII

    $proc = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$elevScript`""
    )
    Remove-Item -LiteralPath $elevScript -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) {
        Write-Fail "Could not write the Chrome extension policy, even elevated. Check with your IT admin."
    }
}
Write-OK "Chrome will install the extension automatically (no Developer mode needed)."

# ?????????????????????????????????????????????????????????????????????????????
#  7. Push proxy files into WSL's own filesystem
#
#  Running scripts straight off /mnt/c is fragile: drvfs can hide freshly
#  created folders from WSL and rewrites line endings. Copying into the WSL
#  home dir sidesteps all of that and is faster too.
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Installing proxy into WSL..."
try {
    Copy-IntoWsl -WinPath (Join-Path $wslDir "start-proxy.sh")       -DestName "start-proxy.sh"       -DistroName $Distro
    Copy-IntoWsl -WinPath (Join-Path $wslDir "local-http-proxy.py")  -DestName "local-http-proxy.py"  -DistroName $Distro
} catch {
    Write-Fail "Could not copy proxy files into WSL: $_"
}
Write-OK "Proxy files installed in WSL."

# ?????????????????????????????????????????????????????????????????????????????
#  8. Start WSL proxy
#
#  WSL2 localhost-forwarding (on by default) makes 0.0.0.0:$ProxyPort inside
#  WSL available at 127.0.0.1:$ProxyPort on Windows - no portproxy/admin needed.
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Starting WSL proxy (port $ProxyPort)..."
& wsl.exe -d $Distro sh -lc "sh `$HOME/.wsl-chrome-proxy/start-proxy.sh $ProxyPort `$HOME/.wsl-chrome-proxy/local-http-proxy.py" 2>$null | Out-Null
Start-Sleep -Milliseconds 500

$portCheck = (& wsl.exe -d $Distro sh -lc "ss -ltn 2>/dev/null | grep -c ':$ProxyPort '" 2>$null |
              Select-Object -First 1).Trim()
if ([int]$portCheck -gt 0) {
    Write-OK "Proxy running: Ubuntu:$ProxyPort  ->  Windows 127.0.0.1:$ProxyPort"
} else {
    Write-Warn "Port check inconclusive - proxy may take a moment to start."
}

# ?????????????????????????????????????????????????????????????????????????????
#  9. Autostart via HKCU\Run
#
#  All the start logic lives in proxy-control.ps1 (a committed file - no fragile
#  here-string escaping). We just record the config and point Run at it.
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Registering autostart..."

$configContent = @(
    "ProxyPort=$ProxyPort",
    "Distro=$Distro",
    "UpdateServerPort=$UpdateServerPort"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $installRoot "config.txt") -Value $configContent -Encoding ASCII

$proxyCtrl = Join-Path $scriptsDir "proxy-control.ps1"
$runKey    = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$runValue  = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$proxyCtrl`" start"
Set-ItemProperty -Path $runKey -Name "WslChromeProxy" -Value $runValue
Write-OK "Proxy will restart automatically after login."

# ?????????????????????????????????????????????????????????????????????????????
#  10. Permanent Proxy.cmd shim in %USERPROFILE%\bin  (on PATH)
#      This means 'Proxy start/stop/status/update' works from any CMD window
#      regardless of where the repo was cloned or whether it still exists.
# ?????????????????????????????????????????????????????????????????????????????
Write-Step "Installing Proxy command..."
$binDir      = Join-Path $env:USERPROFILE "bin"
$proxyCmdDst = Join-Path $binDir "Proxy.cmd"
$proxyCtrl   = Join-Path $scriptsDir "proxy-control.ps1"

if (-not (Test-Path -LiteralPath $binDir)) {
    New-Item -ItemType Directory -Path $binDir | Out-Null
}

# Write a shim that always points at the installed proxy-control.ps1
$shimContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$proxyCtrl`" %*`r`n"
Set-Content -LiteralPath $proxyCmdDst -Value $shimContent -Encoding ASCII

# Add %USERPROFILE%\bin to PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$parts    = $userPath -split ";" | Where-Object { $_ }
if ($parts -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable("Path", ($parts + $binDir -join ";"), "User")
    Write-OK "Added $binDir to your PATH (open a new CMD window to use it)."
} else {
    Write-OK "Proxy command installed at $proxyCmdDst"
}

# ?????????????????????????????????????????????????????????????????????????????
#  11. Write version.txt so 'Proxy update' knows what is installed
# ?????????????????????????????????????????????????????????????????????????????
# Try to read the version from a VERSION file next to Install.ps1 (written by
# make-release.ps1), or fall back to the extension version string.
$versionFile  = Join-Path $PSScriptRoot "VERSION"
$installedVer = if (Test-Path $versionFile) {
    (Get-Content $versionFile -Raw).Trim()
} else {
    "v$extensionVersion"
}
Set-Content -LiteralPath (Join-Path $installRoot "version.txt") -Value $installedVer -Encoding ASCII

# ?????????????????????????????????????????????????????????????????????????????
#  Done
# ?????????????????????????????????????????????????????????????????????????????
Write-Host ""
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Proxy:     127.0.0.1:$ProxyPort" -ForegroundColor White
Write-Host "  Autostart: enabled" -ForegroundColor White
Write-Host ""
Write-Host "  --> Fully close and reopen Chrome." -ForegroundColor Yellow
Write-Host "      The WSL Proxy Toggle extension will appear in your toolbar." -ForegroundColor White
Write-Host ""
Write-Host "  Day-to-day (from any CMD window):" -ForegroundColor DarkGray
Write-Host "    Proxy          start / restart" -ForegroundColor DarkGray
Write-Host "    Proxy stop     stop everything" -ForegroundColor DarkGray
Write-Host "    Proxy status   show current state" -ForegroundColor DarkGray
Write-Host "    Proxy update   download and install latest from GitHub" -ForegroundColor DarkGray
Write-Host ""
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
if (-not $NoPause) { Read-Host "Press Enter to close" }
