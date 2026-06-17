param(
  [string]$ProjectId = "voice-messenger-jangs-260522",
  [string]$Region = "asia-northeast3",
  [string]$ServiceName = "verbal-deepgram-relay",
  [string]$SourceDir = "services/deepgram-relay",
  [switch]$RequireOpenAI
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot $SourceDir

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
    (Join-Path $sourcePath '.env.local'),
    (Join-Path $sourcePath '.env')
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

function Test-SecretExists([string]$Name) {
  $previousErrorActionPreference = $ErrorActionPreference
  $previousNativeErrorPreference = $null
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $previousNativeErrorPreference = $Global:PSNativeCommandUseErrorActionPreference
    $Global:PSNativeCommandUseErrorActionPreference = $false
  }
  try {
    $ErrorActionPreference = 'Continue'
    & gcloud secrets describe $Name --project $ProjectId --format='value(name)' *> $null
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($null -ne $previousNativeErrorPreference) {
      $Global:PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }
  }
}

function Set-SecretValue([string]$Name, [string]$Value) {
  if (-not $Value.Trim()) {
    return
  }
  if (Test-SecretExists $Name) {
    $Value | & gcloud secrets versions add $Name --project $ProjectId --data-file=-
    return
  }
  $Value | & gcloud secrets create $Name --project $ProjectId --replication-policy=automatic --data-file=-
}

if (-not (Test-Path $sourcePath)) {
  throw "Relay source directory was not found: $sourcePath"
}

$deepgramKey = Import-EnvValue 'DEEPGRAM_API_KEY'
$openAiKey = Import-EnvValue 'OPENAI_API_KEY'

if ($deepgramKey) {
  Set-SecretValue -Name 'DEEPGRAM_API_KEY' -Value $deepgramKey
} elseif (-not (Test-SecretExists 'DEEPGRAM_API_KEY')) {
  throw "DEEPGRAM_API_KEY is missing. Add it to .env.local or Secret Manager."
}

if ($openAiKey) {
  Set-SecretValue -Name 'OPENAI_API_KEY' -Value $openAiKey
} elseif ($RequireOpenAI) {
  throw "OPENAI_API_KEY is missing. Add it to .env.local or this PowerShell session."
}

$secretBindings = @('DEEPGRAM_API_KEY=DEEPGRAM_API_KEY:latest')
if (Test-SecretExists 'OPENAI_API_KEY') {
  $secretBindings += 'OPENAI_API_KEY=OPENAI_API_KEY:latest'
}

$envVars = @(
  'DEEPGRAM_MODEL=nova-3',
  'DEEPGRAM_LANGUAGE=ko',
  'DEEPGRAM_SAMPLE_RATE=16000',
  'DEEPGRAM_ENDPOINTING_MS=150',
  'DEEPGRAM_NO_DELAY=true',
  'DEEPGRAM_STREAMING_SMART_FORMAT=true',
  'DEEPGRAM_STREAMING_PUNCTUATE=true',
  'DEEPGRAM_STREAMING_NUMERALS=true',
  'OPENAI_REALTIME_CONNECT_MODEL=gpt-realtime-2',
  'OPENAI_REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper',
  'OPENAI_TRANSCRIPTION_DELAY=minimal',
  'OPENAI_COMMIT_INTERVAL_MS=150'
)

& gcloud run deploy $ServiceName `
  --source $sourcePath `
  --region $Region `
  --project $ProjectId `
  --allow-unauthenticated `
  --set-secrets ($secretBindings -join ',') `
  --set-env-vars ($envVars -join ',') `
  --quiet

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$serviceUrl = (& gcloud run services describe $ServiceName `
  --project $ProjectId `
  --region $Region `
  --format='value(status.url)').Trim()

if (-not $serviceUrl) {
  throw "Cloud Run service URL was not found."
}

$health = Invoke-RestMethod -Uri "$serviceUrl/" -TimeoutSec 15
$health | ConvertTo-Json -Depth 8

if ($RequireOpenAI -and $health.providers.openai -ne $true) {
  throw "Relay deployed, but OpenAI provider is not enabled. Check OPENAI_API_KEY secret binding."
}
