param(
  [string]$DeviceId = "",
  [int]$RelayPort = 8788,
  [switch]$Mock,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$DefaultMockTranscriptChars = @(
  0xC624, 0xB298, 0x20, 0xC624, 0xD6C4, 0x20, 0xC138, 0xC2DC, 0xC5D0,
  0x20, 0xD68C, 0xC758, 0x20, 0xAC00, 0xB2A5, 0xD569, 0xB2C8, 0xB2E4,
  0x2E
)
$DefaultMockTranscript = -join (
  $DefaultMockTranscriptChars | ForEach-Object { [char]$_ }
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'apps\mobile'
$relayDir = Join-Path $repoRoot 'services\deepgram-relay'
$localProperties = Join-Path $appDir 'android\local.properties'
$flutter = 'flutter'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'

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

if (-not (Test-Path $adb)) {
  throw "adb.exe was not found at $adb"
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

function Import-EnvValue([string]$Name) {
  $current = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ($current) {
    return $current
  }
  $envFiles = @(
    (Join-Path $repoRoot '.env.local'),
    (Join-Path $repoRoot '.env'),
    (Join-Path $relayDir '.env.local'),
    (Join-Path $relayDir '.env')
  )
  foreach ($envFile in $envFiles) {
    $value = Get-EnvValueFromFile -Path $envFile -Name $Name
    if ($value) {
      [Environment]::SetEnvironmentVariable($Name, $value, 'Process')
      return $value
    }
  }
  return $null
}

$openAiApiKey = Import-EnvValue 'OPENAI_API_KEY'
if (-not $openAiApiKey -and -not $Mock) {
  throw "OPENAI_API_KEY is missing. Add OPENAI_API_KEY=... to .env.local, then rerun this script."
}

$deepgramApiKey = Import-EnvValue 'DEEPGRAM_API_KEY'
if ($deepgramApiKey) {
  [Environment]::SetEnvironmentVariable('DEEPGRAM_API_KEY', $deepgramApiKey, 'Process')
}

if (-not (Test-Path (Join-Path $relayDir 'node_modules'))) {
  Push-Location $relayDir
  try {
    npm install
  }
  finally {
    Pop-Location
  }
}

$logDir = Join-Path $repoRoot 'dist\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $RelayPort -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
  $out = Join-Path $logDir 'openai-realtime-relay.out.log'
  $err = Join-Path $logDir 'openai-realtime-relay.err.log'
  [Environment]::SetEnvironmentVariable('PORT', "$RelayPort", 'Process')
  [Environment]::SetEnvironmentVariable('OPENAI_REALTIME_CONNECT_MODEL', 'gpt-realtime-2', 'Process')
  [Environment]::SetEnvironmentVariable('OPENAI_REALTIME_TRANSCRIPTION_MODEL', 'gpt-realtime-whisper', 'Process')
  [Environment]::SetEnvironmentVariable('OPENAI_TRANSCRIPTION_DELAY', 'minimal', 'Process')
  [Environment]::SetEnvironmentVariable('OPENAI_COMMIT_INTERVAL_MS', '150', 'Process')
  if ($Mock) {
    [Environment]::SetEnvironmentVariable('MOCK_OPENAI_REALTIME', 'true', 'Process')
    if (-not [Environment]::GetEnvironmentVariable('MOCK_OPENAI_TRANSCRIPT', 'Process')) {
      [Environment]::SetEnvironmentVariable('MOCK_OPENAI_TRANSCRIPT', $DefaultMockTranscript, 'Process')
    }
  }
  Start-Process `
    -FilePath 'node' `
    -ArgumentList @('server.js') `
    -WorkingDirectory $relayDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $out `
    -RedirectStandardError $err
}

$healthUrl = "http://127.0.0.1:$RelayPort/healthz"
$ready = $false
for ($i = 0; $i -lt 30; $i += 1) {
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    if ($health.ok -eq $true -and $health.providers.openai -eq $true) {
      $ready = $true
      break
    }
  } catch {
    Start-Sleep -Milliseconds 500
  }
}

if (-not $ready) {
  throw "OpenAI realtime relay did not become ready. If a previous relay is already using port $RelayPort, stop it or choose another -RelayPort. Check dist\logs\openai-realtime-relay.err.log."
}

$adbDeviceArgs = @()
if ($DeviceId.Trim()) {
  $adbDeviceArgs = @('-s', $DeviceId.Trim())
}

& $adb @adbDeviceArgs reverse "tcp:$RelayPort" "tcp:$RelayPort"

$relayUrl = "http://127.0.0.1:$RelayPort/openai-stt"
$apkPath = Join-Path $appDir 'build\app\outputs\flutter-apk\app-debug.apk'

Push-Location $appDir
try {
  if (-not $SkipBuild) {
    & $flutter build apk --debug `
      --dart-define=VERBAL_REALTIME_STT_PROVIDER=openai `
      --dart-define=VERBAL_DEEPGRAM_RELAY_URL=$relayUrl `
      --dart-define=VERBAL_DEEPGRAM_STREAMING_STT=true `
      --dart-define=VERBAL_USE_REALTIME_STT_FOR_KO=true
  }
}
finally {
  Pop-Location
}

& $adb @adbDeviceArgs install -r $apkPath
& $adb @adbDeviceArgs shell am force-stop com.voicebeta.verbal
& $adb @adbDeviceArgs shell monkey -p com.voicebeta.verbal -c android.intent.category.LAUNCHER 1

Write-Host "OpenAI realtime STT relay: $relayUrl"
Write-Host "ADB reverse: tcp:$RelayPort -> tcp:$RelayPort"
Write-Host "Installed app: com.voicebeta.verbal"
if ($Mock) {
  Write-Host "Mock mode: enabled. This validates app streaming latency without calling OpenAI."
}
