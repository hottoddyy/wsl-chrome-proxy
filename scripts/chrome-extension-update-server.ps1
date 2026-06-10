[CmdletBinding()]
param(
  [int]$Port = 18082,
  [string]$Root = (Join-Path $env:LOCALAPPDATA "WslChromeProxy\ChromeExtension")
)

$ErrorActionPreference = "Stop"

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $path = $context.Request.Url.AbsolutePath

    switch ($path) {
      "/update.xml" {
        $file = Join-Path $Root "update.xml"
        $contentType = "text/xml"
      }
      "/wsl-proxy-toggle.crx" {
        $file = Join-Path $Root "wsl-proxy-toggle.crx"
        $contentType = "application/x-chrome-extension"
      }
      default {
        $file = $null
        $contentType = "text/plain"
      }
    }

    if ($file -and (Test-Path -LiteralPath $file)) {
      $body = [System.IO.File]::ReadAllBytes($file)
      $context.Response.StatusCode = 200
      $context.Response.ContentType = $contentType
    } else {
      $body = [System.Text.Encoding]::UTF8.GetBytes("Not found")
      $context.Response.StatusCode = 404
      $context.Response.ContentType = "text/plain"
    }

    $context.Response.ContentLength64 = $body.Length
    $context.Response.OutputStream.Write($body, 0, $body.Length)
    $context.Response.OutputStream.Close()
  }
} finally {
  $listener.Stop()
}
