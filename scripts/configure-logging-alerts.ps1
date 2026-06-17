param(
  [string]$ProjectId = "voice-messenger-jangs-260522"
)

$ErrorActionPreference = "Stop"

function Upsert-LogMetric {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string]$Filter
  )

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & gcloud logging metrics describe $Name --project=$ProjectId *> $null
  $exists = $LASTEXITCODE -eq 0
  $ErrorActionPreference = $previousErrorActionPreference

  if ($exists) {
    & gcloud logging metrics update $Name `
      --project=$ProjectId `
      --description=$Description `
      --log-filter=$Filter | Out-Null
    "Updated log metric: $Name"
  } else {
    & gcloud logging metrics create $Name `
      --project=$ProjectId `
      --description=$Description `
      --log-filter=$Filter | Out-Null
    "Created log metric: $Name"
  }
}

function Ensure-LogAlertPolicy {
  param(
    [Parameter(Mandatory = $true)][string]$DisplayName,
    [Parameter(Mandatory = $true)][string]$Filter
  )

  $policiesRaw = & gcloud monitoring policies list --project=$ProjectId --format=json
  $policies = if ($policiesRaw) { $policiesRaw | ConvertFrom-Json } else { @() }
  $existingPolicy = $policies | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
  $existing = if ($existingPolicy) { $existingPolicy.name } else { "" }

  if ($existing) {
    "Alert policy already exists: $DisplayName"
    return
  }

  $policy = @{
    displayName = $DisplayName
    enabled = $true
    combiner = "OR"
    conditions = @(
      @{
        displayName = $DisplayName
        conditionMatchedLog = @{
          filter = $Filter
        }
      }
    )
    alertStrategy = @{
      notificationRateLimit = @{
        period = "300s"
      }
      autoClose = "1800s"
    }
  }

  $path = Join-Path $env:TEMP "$($DisplayName.Replace(' ', '-')).json"
  $policy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
  & gcloud monitoring policies create --project=$ProjectId --policy-from-file=$path | Out-Null
  Remove-Item -LiteralPath $path -Force
  "Created alert policy: $DisplayName"
}

$functionErrorFilter = 'resource.type="cloud_run_revision" AND severity>=ERROR'
$deepgramErrorFilter = 'resource.type="cloud_run_revision" AND (textPayload:"Deepgram" OR jsonPayload.message:"Deepgram") AND severity>=ERROR'

Upsert-LogMetric `
  -Name "verbal_function_errors" `
  -Description "Verbal Cloud Functions and Cloud Run error logs." `
  -Filter $functionErrorFilter

Upsert-LogMetric `
  -Name "verbal_deepgram_errors" `
  -Description "Verbal Deepgram STT error logs." `
  -Filter $deepgramErrorFilter

Ensure-LogAlertPolicy `
  -DisplayName "Verbal Function Errors" `
  -Filter $functionErrorFilter

Ensure-LogAlertPolicy `
  -DisplayName "Verbal Deepgram Errors" `
  -Filter $deepgramErrorFilter
