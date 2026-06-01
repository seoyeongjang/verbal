param(
  [string]$ProjectId = "voice-messenger-jangs-260522",
  [string]$ProjectNumber = "203811587610",
  [string]$PhoneNumber = "+16505550101",
  [string]$SmsCode = "123456",
  [string[]]$SmsAllowedRegions = @("KR", "US")
)

$ErrorActionPreference = "Stop"

function Invoke-IdentityToolkit {
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

& gcloud services enable identitytoolkit.googleapis.com --project=$ProjectId | Out-Null

$configUri = "https://identitytoolkit.googleapis.com/admin/v2/projects/$ProjectNumber/config"
$config = Invoke-IdentityToolkit -Method "GET" -Uri $configUri

$testPhoneNumbers = @{}
if ($config.signIn.phoneNumber.testPhoneNumbers) {
  $config.signIn.phoneNumber.testPhoneNumbers.PSObject.Properties | ForEach-Object {
    $testPhoneNumbers[$_.Name] = $_.Value
  }
}
$testPhoneNumbers[$PhoneNumber] = $SmsCode

$body = @{
  signIn = @{
    phoneNumber = @{
      enabled = $true
      testPhoneNumbers = $testPhoneNumbers
    }
  }
}

$updated = Invoke-IdentityToolkit `
  -Method "PATCH" `
  -Uri "$configUri`?updateMask=signIn.phoneNumber" `
  -Body $body

Invoke-IdentityToolkit `
  -Method "PATCH" `
  -Uri "$configUri`?updateMask=sms_region_config" `
  -Body @{
    smsRegionConfig = @{
      allowlistOnly = @{
        allowedRegions = $SmsAllowedRegions
      }
    }
  } | Out-Null

$registered = $updated.signIn.phoneNumber.testPhoneNumbers.PSObject.Properties |
  Where-Object { $_.Name -eq $PhoneNumber } |
  Select-Object -First 1

if (-not $registered) {
  throw "Failed to register Firebase Auth test phone number."
}

"Configured Firebase Auth test phone number: $PhoneNumber / $SmsCode"
"Configured Firebase Auth SMS regions: $($SmsAllowedRegions -join ', ')"
