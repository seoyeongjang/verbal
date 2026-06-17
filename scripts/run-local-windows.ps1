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

Write-Host "Starting local Windows desktop demo"
Write-Host "Flutter: $flutter"

$developerMode = Get-ItemPropertyValue `
  -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
  -Name 'AllowDevelopmentWithoutDevLicense' `
  -ErrorAction SilentlyContinue

if ($developerMode -ne 1) {
  Write-Warning "Windows Developer Mode is not enabled. Flutter plugins need it for symlink support."
  Write-Host "Open Settings > System > For developers, enable Developer Mode, then rerun this script."
}

Push-Location $appDir
try {
  & $flutter config --enable-windows-desktop
  & $flutter pub get
  & $flutter run `
    -d windows `
    --dart-define=VERBAL_DEMO=true
}
finally {
  Pop-Location
}
