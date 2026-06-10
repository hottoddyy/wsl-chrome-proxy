[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$extensionId = "apchgcioodnlnhbgdokfccpojkcanjnk"
$extensionPath = Join-Path $PSScriptRoot "chrome-extension.crx"
$manifestPath = Join-Path $PSScriptRoot "chrome-extension\manifest.json"

if (-not (Test-Path -LiteralPath $extensionPath)) {
  throw "Could not find packaged extension: $extensionPath"
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Could not find extension manifest: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$key = "HKCU:\Software\Google\Chrome\Extensions\$extensionId"

if (-not (Test-Path -LiteralPath $key)) {
  New-Item -Path $key -Force | Out-Null
}

Set-ItemProperty -Path $key -Name "path" -Value $extensionPath
Set-ItemProperty -Path $key -Name "version" -Value $manifest.version

Write-Host "Registered Chrome extension:"
Write-Host "  ID: $extensionId"
Write-Host "  CRX: $extensionPath"
Write-Host ""
Write-Host "Fully close and reopen Chrome, then check chrome://extensions."
