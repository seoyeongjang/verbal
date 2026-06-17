param(
  [int]$Port = 55173
)

$ErrorActionPreference = 'Stop'

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

Write-Host "Starting local web demo at http://127.0.0.1:$Port"
Write-Host "Flutter: $flutter"

Push-Location $appDir
try {
  & $flutter pub get
  & $flutter run `
    -d chrome `
    --web-hostname 127.0.0.1 `
    --web-port $Port `
    --dart-define=VERBAL_DEMO=true
}
finally {
  Pop-Location
}
