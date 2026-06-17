param(
  [int]$SttPort = 8787
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'apps\mobile'
$localProperties = Join-Path $appDir 'android\local.properties'
$flutter = 'flutter'

if (Test-Path $localProperties) {
  $sdkLine = Get-Content $localProperties | Where-Object { $_ -like 'flutter.sdk=*' } | Select-Object -First 1
  if ($sdkLine) {
    $sdkPath = ($sdkLine -replace '^flutter.sdk=', '').Replace('\\', '\')
    $candidate = Join-Path $sdkPath 'bin\flutter.bat'
    if (Test-Path $candidate) {
      $flutter = $candidate
    }
  }
}

$endpoint = "http://127.0.0.1:$SttPort/transcribe"

Write-Host "Building local STT web demo"
Write-Host "Local STT endpoint: $endpoint"
Write-Host "Flutter: $flutter"

Push-Location $appDir
try {
  & $flutter pub get
  & $flutter build web `
    --dart-define=VERBAL_LOCAL_STT=true `
    --dart-define=LOCAL_STT_ENDPOINT=$endpoint
}
finally {
  Pop-Location
}
