[CmdletBinding(DefaultParameterSetName = "Start")]
param(
  [Parameter(ParameterSetName = "Start")]
  [switch]$Start,

  [Parameter(ParameterSetName = "Stop")]
  [switch]$Stop,

  [Parameter(ParameterSetName = "Status")]
  [switch]$Status,

  [Parameter(ParameterSetName = "RunServer")]
  [switch]$RunServer,

  [int]$ListenPort = 18080,
  [int]$ProxyPort = 18081,
  [string]$ListenHost = "127.0.0.1",
  [string]$Distro = "Ubuntu",
  [switch]$SkipWslProxy
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "WslChromeProxy"
$pidPath = Join-Path $stateDir "connector.pid"
$statusPath = Join-Path $stateDir "status.json"
$logPath = Join-Path $stateDir "connector.log"
$wslProxyScript = Join-Path (Split-Path -Parent $PSScriptRoot) "wsl\local-http-proxy.py"
$wslStartScript = Join-Path (Split-Path -Parent $PSScriptRoot) "wsl\start-proxy.sh"

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-StateDir {
  if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
  }
}

function Write-Log {
  param([string]$Message)
  Ensure-StateDir
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -LiteralPath $logPath -Value "[$stamp] $Message"
}

function Get-RunningConnector {
  if (-not (Test-Path -LiteralPath $pidPath)) {
    return $null
  }

  $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
  if (-not $pidText) {
    return $null
  }

  try {
    return Get-Process -Id ([int]$pidText) -ErrorAction Stop
  } catch {
    return $null
  }
}

function Get-WslIpAddress {
  $command = "hostname -I | awk '{print `$1}'"
  $args = @()
  if ($Distro.Trim().Length -gt 0) {
    $args += @("-d", $Distro)
  }
  $args += @("sh", "-lc", $command)

  $ip = (& wsl.exe @args 2>$null | Select-Object -First 1).Trim()
  if (-not $ip) {
    throw "Could not read a WSL IP address. Start your WSL distro, then run WSL again."
  }

  return $ip.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[0]
}

function ConvertTo-BashSingleQuoted {
  param([string]$Value)
  return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-WslShell {
  param([string]$Command)

  $args = @()
  if ($Distro.Trim().Length -gt 0) {
    $args += @("-d", $Distro)
  }
  $args += @("sh", "-lc", $Command)
  return & wsl.exe @args
}

function Get-WslPath {
  param([string]$WindowsPath)

  $quoted = ConvertTo-BashSingleQuoted $WindowsPath
  $path = (Invoke-WslShell "wslpath -a $quoted" | Select-Object -First 1).Trim()
  if (-not $path) {
    throw "Could not convert $WindowsPath to a WSL path."
  }
  return $path
}

function Start-UbuntuProxy {
  if ($SkipWslProxy) {
    return
  }

  if (-not (Test-Path -LiteralPath $wslProxyScript)) {
    throw "Could not find the WSL proxy script at $wslProxyScript."
  }

  if (-not (Test-Path -LiteralPath $wslStartScript)) {
    throw "Could not find the WSL proxy starter at $wslStartScript."
  }

  $wslScript = Get-WslPath $wslProxyScript
  $wslStarter = Get-WslPath $wslStartScript
  $starterArg = ConvertTo-BashSingleQuoted $wslStarter
  $scriptArg = ConvertTo-BashSingleQuoted $wslScript

  Invoke-WslShell "sh $starterArg $ProxyPort $scriptArg" | Out-Null
  Write-Log "Started Ubuntu proxy in distro '$Distro' on port $ProxyPort."
}

function Stop-UbuntuProxy {
  if ($SkipWslProxy) {
    return
  }

  try {
    $command = @"
if [ -f /tmp/wsl-chrome-proxy/proxy.pid ]; then
  pid="`$(cat /tmp/wsl-chrome-proxy/proxy.pid)"
  kill "`$pid" 2>/dev/null || true
  rm -f /tmp/wsl-chrome-proxy/proxy.pid
fi
pkill -f "[l]ocal-http-proxy.py.*--port $ProxyPort" 2>/dev/null || true
"@
    Invoke-WslShell $command | Out-Null
    Write-Log "Stopped Ubuntu proxy in distro '$Distro'."
  } catch {
    Write-Log "Could not stop Ubuntu proxy: $($_.Exception.Message)"
  }
}

function Save-Status {
  param(
    [string]$State,
    [int]$ProcessId = 0,
    [string]$TargetIp = "",
    [string]$Message = ""
  )

  Ensure-StateDir
  $data = [ordered]@{
    state = $State
    pid = $ProcessId
    listenHost = $ListenHost
    listenPort = $ListenPort
    targetHost = $TargetIp
    targetPort = $ProxyPort
    updatedAt = (Get-Date).ToString("o")
    message = $Message
  }

  $data | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
}

function Start-Connector {
  Ensure-StateDir
  if (-not (Test-IsAdmin)) {
    throw "Starting the Windows portproxy requires Administrator. Run WSL from CMD and approve the UAC prompt."
  }

  $running = Get-RunningConnector
  if ($running) {
    Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
  }

  Start-UbuntuProxy
  $targetIp = Get-WslIpAddress

  $ipHelper = Get-Service -Name iphlpsvc -ErrorAction SilentlyContinue
  if ($ipHelper -and $ipHelper.Status -ne "Running") {
    Start-Service -Name iphlpsvc
  }

  & netsh interface portproxy delete v4tov4 listenaddress=$ListenHost listenport=$ListenPort | Out-Null
  & netsh interface portproxy add v4tov4 listenaddress=$ListenHost listenport=$ListenPort connectaddress=$targetIp connectport=$ProxyPort | Out-Null

  Save-Status -State "running" -ProcessId 0 -TargetIp $targetIp -Message "Portproxy forwarding $ListenHost`:$ListenPort to $targetIp`:$ProxyPort."
  Write-Log "Configured portproxy forwarding $ListenHost`:$ListenPort to $targetIp`:$ProxyPort."
  Write-Host "WSL proxy connector started on $ListenHost`:$ListenPort."
  Write-Host "Ubuntu proxy target: $Distro at $targetIp`:$ProxyPort."
  Write-Host "Chrome extension proxy target: $ListenHost`:$ListenPort."
}

function Stop-Connector {
  if (-not (Test-IsAdmin)) {
    throw "Stopping the Windows portproxy requires Administrator. Run WSL stop from CMD and approve the UAC prompt."
  }

  $running = Get-RunningConnector
  if ($running) {
    Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
  & netsh interface portproxy delete v4tov4 listenaddress=$ListenHost listenport=$ListenPort | Out-Null
  Stop-UbuntuProxy
  Save-Status -State "stopped" -Message "Connector stopped."
  Write-Host "WSL proxy connector stopped."
}

function Show-Status {
  $running = Get-RunningConnector
  if ($running) {
    Write-Host "WSL proxy connector is running. PID $($running.Id)."
  } else {
    $portproxy = (& netsh interface portproxy show v4tov4) -join "`n"
    if ($portproxy -match [regex]::Escape($ListenHost) -and $portproxy -match "\s$ListenPort\s") {
      Write-Host "WSL proxy connector is running via Windows portproxy."
    } else {
      Write-Host "WSL proxy connector is not running."
    }
  }

  if (Test-Path -LiteralPath $statusPath) {
    Get-Content -LiteralPath $statusPath
  }
}

switch ($PSCmdlet.ParameterSetName) {
  "Stop" { Stop-Connector }
  "Status" { Show-Status }
  "RunServer" { Start-Connector }
  default { Start-Connector }
}
