param(
  [string]$ProjectId = "voice-messenger-jangs-260522",
  [string]$ProjectNumber = "203811587610",
  [string]$BillingAccountId = "019D7D-328A8B-D6DB84",
  [string]$DisplayName = "Firebase Project voice-messenger-jangs-260522",
  [int]$BudgetKrw = 50000
)

$ErrorActionPreference = "Stop"

function Invoke-BudgetApi {
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

& gcloud services enable billingbudgets.googleapis.com --project=$ProjectId | Out-Null

$parent = "billingAccounts/$BillingAccountId"
$listUri = "https://billingbudgets.googleapis.com/v1/$parent/budgets"
$existing = Invoke-BudgetApi -Method "GET" -Uri $listUri
$budget = $existing.budgets | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1

$body = @{
  displayName = $DisplayName
  budgetFilter = @{
    projects = @("projects/$ProjectNumber")
    creditTypesTreatment = "INCLUDE_ALL_CREDITS"
    calendarPeriod = "MONTH"
  }
  amount = @{
    specifiedAmount = @{
      currencyCode = "KRW"
      units = "$BudgetKrw"
    }
  }
  thresholdRules = @(
    @{ thresholdPercent = 0.5; spendBasis = "CURRENT_SPEND" },
    @{ thresholdPercent = 0.8; spendBasis = "CURRENT_SPEND" },
    @{ thresholdPercent = 1.0; spendBasis = "CURRENT_SPEND" },
    @{ thresholdPercent = 1.0; spendBasis = "FORECASTED_SPEND" }
  )
  notificationsRule = @{
    disableDefaultIamRecipients = $false
    enableProjectLevelRecipients = $true
  }
}

if ($budget) {
  $body.name = $budget.name
  if ($budget.etag) {
    $body.etag = $budget.etag
  }
  $updateMask = "displayName,budgetFilter,amount,thresholdRules,notificationsRule"
  $updated = Invoke-BudgetApi `
    -Method "PATCH" `
    -Uri "https://billingbudgets.googleapis.com/v1/$($budget.name)?updateMask=$updateMask" `
    -Body $body
  "Updated budget alert: $($updated.name) KRW $BudgetKrw"
} else {
  $created = Invoke-BudgetApi -Method "POST" -Uri $listUri -Body $body
  "Created budget alert: $($created.name) KRW $BudgetKrw"
}
