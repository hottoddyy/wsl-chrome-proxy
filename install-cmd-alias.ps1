[CmdletBinding()]
param(
  [string]$CommandPath = (Join-Path $env:USERPROFILE "bin\WSL.cmd")
)

$ErrorActionPreference = "Stop"

$key = "HKCU:\Software\Microsoft\Command Processor"
$alias = "doskey WSL=`"$CommandPath`" `$*"

if (-not (Test-Path -LiteralPath $key)) {
  New-Item -Path $key -Force | Out-Null
}

$current = (Get-ItemProperty -Path $key -Name AutoRun -ErrorAction SilentlyContinue).AutoRun

if ([string]::IsNullOrWhiteSpace($current)) {
  $next = $alias
} elseif ($current -like "*doskey WSL=*") {
  $next = $current -replace 'doskey WSL=.*?(\s*&\s*|$)', ''
  $next = (($next.Trim(" ", "&")) + " & " + $alias).Trim(" ", "&")
} else {
  $next = "$current & $alias"
}

Set-ItemProperty -Path $key -Name AutoRun -Value $next
Write-Host "Installed CMD alias:"
Write-Host "  $alias"
Write-Host "Open a new CMD window, then type WSL."
