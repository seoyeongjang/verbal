param(
  [string]$ProjectId = "voice-messenger-jangs-260522",
  [string]$StorageLocation = "asia-northeast3"
)

$ErrorActionPreference = "Stop"

function Invoke-FirebaseRest {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Uri,
    [object]$Body = $null
  )

  $token = (& gcloud auth print-access-token).Trim()
  $headers = @{
    Authorization = "Bearer $token"
    "x-goog-user-project" = $ProjectId
  }

  if ($null -eq $Body) {
    return Invoke-RestMethod -Headers $headers -Uri $Uri -Method $Method
  }

  return Invoke-RestMethod `
    -Headers $headers `
    -Uri $Uri `
    -Method $Method `
    -Body ($Body | ConvertTo-Json -Depth 10) `
    -ContentType "application/json"
}

function Import-EnvFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
      return
    }
    $parts = $line.Split("=", 2)
    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if ($name -and -not [Environment]::GetEnvironmentVariable($name, "Process")) {
      [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$functionsDir = Join-Path $repoRoot "functions"
Import-EnvFile -Path (Join-Path $repoRoot ".env.local")
Import-EnvFile -Path (Join-Path $repoRoot ".env")

$billing = & gcloud billing projects describe $ProjectId --format="value(billingEnabled)"
if ($billing -ne "True") {
  throw "Billing is not enabled for $ProjectId. Upgrade the Firebase project to Blaze first."
}

if (-not $env:DEEPGRAM_API_KEY) {
  throw "DEEPGRAM_API_KEY is not set in this PowerShell session."
}

Push-Location $repoRoot
try {
  & gcloud services enable `
    cloudfunctions.googleapis.com `
    cloudbuild.googleapis.com `
    cloudbilling.googleapis.com `
    artifactregistry.googleapis.com `
    run.googleapis.com `
    eventarc.googleapis.com `
    secretmanager.googleapis.com `
    --project=$ProjectId

  try {
    Invoke-FirebaseRest `
      -Method "GET" `
      -Uri "https://firebasestorage.googleapis.com/v1alpha/projects/$ProjectId/defaultBucket" | Out-Null
  } catch {
    Invoke-FirebaseRest `
      -Method "POST" `
      -Uri "https://firebasestorage.googleapis.com/v1alpha/projects/$ProjectId/defaultBucket" `
      -Body @{ location = $StorageLocation } | Out-Null
  }

  Push-Location $functionsDir
  try {
    & npm run build
    & node scripts/firebase-cli.js deploy --only storage --project $ProjectId
    $env:DEEPGRAM_API_KEY | & node scripts/firebase-cli.js functions:secrets:set DEEPGRAM_API_KEY --project $ProjectId
    & node scripts/firebase-cli.js deploy --only firestore:rules,firestore:indexes --project $ProjectId
    & node scripts/firebase-cli.js deploy --only functions --project $ProjectId --force
  } finally {
    Pop-Location
  }

  & (Join-Path $PSScriptRoot "configure-callable-invokers.ps1") `
    -ProjectId $ProjectId `
    -Region $StorageLocation
} finally {
  Pop-Location
}
