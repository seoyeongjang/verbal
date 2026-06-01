param(
  [int]$WebPort = 55173,
  [int]$SttPort = 8787
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'apps\mobile'
$functionsDir = Join-Path $repoRoot 'functions'
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

function Get-EnvValueFromFile([string]$Path, [string]$Name) {
  if (-not (Test-Path $Path)) {
    return $null
  }
  $line = Get-Content $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
  if (-not $line) {
    return $null
  }
  return ($line -replace "^\s*$Name\s*=\s*", '').Trim().Trim('"').Trim("'")
}

$envFiles = @(
  (Join-Path $repoRoot '.env.local'),
  (Join-Path $repoRoot '.env'),
  (Join-Path $functionsDir '.env.local'),
  (Join-Path $functionsDir '.env')
)

$apiKey = $env:DEEPGRAM_API_KEY
if (-not $apiKey) {
  foreach ($envFile in $envFiles) {
    $apiKey = Get-EnvValueFromFile -Path $envFile -Name 'DEEPGRAM_API_KEY'
    if ($apiKey) {
      break
    }
  }
}

if (-not $apiKey) {
  throw "DEEPGRAM_API_KEY is missing. Create .env.local in the repo root, add DEEPGRAM_API_KEY=..., then rerun this script."
}

if (-not (Test-Path (Join-Path $functionsDir 'node_modules'))) {
  Push-Location $functionsDir
  try {
    npm install
  }
  finally {
    Pop-Location
  }
}

$logDir = Join-Path $repoRoot 'dist\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$sttListener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $SttPort -State Listen -ErrorAction SilentlyContinue
if (-not $sttListener) {
  $out = Join-Path $logDir 'local-stt-server.out.log'
  $err = Join-Path $logDir 'local-stt-server.err.log'
  $env:LOCAL_STT_PORT = "$SttPort"
  Start-Process `
    -FilePath 'node' `
    -ArgumentList @('scripts/local-stt-server.js') `
    -WorkingDirectory $functionsDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $out `
    -RedirectStandardError $err
}

$healthUrl = "http://127.0.0.1:$SttPort/health"
$ready = $false
for ($i = 0; $i -lt 20; $i += 1) {
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    if ($health.ok -eq $true) {
      $ready = $true
      break
    }
  } catch {
    Start-Sleep -Milliseconds 500
  }
}

if (-not $ready) {
  throw "Local STT server did not start. Check dist\logs\local-stt-server.err.log."
}

$endpoint = "http://127.0.0.1:$SttPort/transcribe"
Write-Host "Local STT server: $endpoint"
Write-Host "Local web app: http://127.0.0.1:$WebPort"
Write-Host "Flutter: $flutter"

Push-Location $appDir
try {
  & $flutter pub get
  & $flutter run `
    -d chrome `
    --web-hostname 127.0.0.1 `
    --web-port $WebPort `
    --dart-define=VOICE_MESSENGER_LOCAL_STT=true `
    --dart-define=LOCAL_STT_ENDPOINT=$endpoint
}
finally {
  Pop-Location
}
