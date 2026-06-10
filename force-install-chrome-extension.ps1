[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$extensionId = "apchgcioodnlnhbgdokfccpojkcanjnk"
$version = "1.0.0"
$root = $PSScriptRoot
$sourceCrxPath = Join-Path $root "chrome-extension.crx"
$installRoot = Join-Path $env:LOCALAPPDATA "WslChromeProxy\ChromeExtension"
$crxPath = Join-Path $installRoot "wsl-proxy-toggle.crx"
$updatePath = Join-Path $installRoot "update.xml"
$serverPidPath = Join-Path $installRoot "update-server.pid"
$serverScript = Join-Path $root "scripts\chrome-extension-update-server.ps1"
$updateServerUrl = "http://127.0.0.1:18082/update.xml"

if (-not (Test-Path -LiteralPath $sourceCrxPath)) {
  throw "Missing packaged extension: $sourceCrxPath"
}

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceCrxPath -Destination $crxPath -Force

$crxUri = ([System.Uri]$crxPath).AbsoluteUri
$crxHttpUri = "http://127.0.0.1:18082/wsl-proxy-toggle.crx"
$updateXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
  <app appid="$extensionId">
    <updatecheck codebase="$crxHttpUri" version="$version" />
  </app>
</gupdate>
"@

Set-Content -LiteralPath $updatePath -Value $updateXml -Encoding ASCII
$updateUri = $updateServerUrl

$serverRunning = $false
if (Test-Path -LiteralPath $serverPidPath) {
  $serverPid = (Get-Content -LiteralPath $serverPidPath -Raw).Trim()
  if ($serverPid) {
    $serverRunning = [bool](Get-Process -Id ([int]$serverPid) -ErrorAction SilentlyContinue)
  }
}

if (-not $serverRunning) {
  $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$serverScript`"",
    "-Port", "18082",
    "-Root", "`"$installRoot`""
  ) -WindowStyle Hidden -PassThru
  Set-Content -LiteralPath $serverPidPath -Value $process.Id -Encoding ASCII
}

$policyRoot = "HKCU:\Software\Policies\Google\Chrome"
$forceList = Join-Path $policyRoot "ExtensionInstallForcelist"
$allowList = Join-Path $policyRoot "ExtensionInstallAllowlist"
$sourceList = Join-Path $policyRoot "ExtensionInstallSources"

New-Item -Path $forceList -Force | Out-Null
New-Item -Path $allowList -Force | Out-Null
New-Item -Path $sourceList -Force | Out-Null

Set-ItemProperty -Path $forceList -Name "1" -Value "$extensionId;$updateUri"
Set-ItemProperty -Path $allowList -Name "1" -Value $extensionId
Set-ItemProperty -Path $sourceList -Name "1" -Value "file:///*"
Set-ItemProperty -Path $sourceList -Name "2" -Value "http://127.0.0.1/*"
Set-ItemProperty -Path $sourceList -Name "3" -Value "http://127.0.0.1:18082/*"

$extensionSettings = @{
  $extensionId = @{
    installation_mode = "force_installed"
    update_url = $updateUri
  }
} | ConvertTo-Json -Compress -Depth 5

Set-ItemProperty -Path $policyRoot -Name "ExtensionSettings" -Value $extensionSettings

Write-Host "Force-installed Chrome extension policy:"
Write-Host "  $extensionId;$updateUri"
Write-Host ""
Write-Host "Close all Chrome windows and reopen Chrome. Then visit chrome://policy and click Reload policies if needed."
