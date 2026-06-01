param(
  [int]$Port = 55173
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $repoRoot 'apps\mobile\build\web'
$indexHtml = Join-Path $webRoot 'index.html'

if (-not (Test-Path $indexHtml)) {
  throw "Web build not found. Run .\scripts\build-local-web.ps1 first."
}

Write-Host "Serving built web app at http://127.0.0.1:$Port"
Write-Host "Web root: $webRoot"

Push-Location $webRoot
try {
  py -3 -m http.server $Port --bind 127.0.0.1
}
finally {
  Pop-Location
}
