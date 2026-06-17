param(
  [string]$ProjectId = "voice-messenger-jangs-260522",
  [string]$ProjectNumber = "203811587610",
  [string]$BillingAccountId = "019D7D-328A8B-D6DB84",
  [string]$Region = "asia-northeast3"
)

$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Assert-Ok {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if ($Condition) {
    "PASS $Message"
  } else {
    "FAIL $Message"
    $failures.Add($Message) | Out-Null
  }
}

function Invoke-GoogleApi {
  param(
    [Parameter(Mandatory = $true)][string]$Uri
  )

  $token = (& gcloud auth print-access-token).Trim()
  $headers = @{
    Authorization = "Bearer $token"
    "x-goog-user-project" = $ProjectId
  }
  return Invoke-RestMethod -Headers $headers -Uri $Uri -Method "GET"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot
try {
  $billingEnabled = (& gcloud billing projects describe $ProjectId --format="value(billingEnabled)").Trim()
  Assert-Ok ($billingEnabled -eq "True") "Firebase Blaze billing is enabled."

  $authConfig = Invoke-GoogleApi -Uri "https://identitytoolkit.googleapis.com/admin/v2/projects/$ProjectNumber/config"
  Assert-Ok ($authConfig.signIn.phoneNumber.enabled -eq $true) "Firebase Phone Number sign-in is enabled."
  Assert-Ok ($null -ne $authConfig.signIn.phoneNumber.testPhoneNumbers."+16505550101") "Firebase Auth test phone number is configured."
  Assert-Ok ($null -ne $authConfig.signIn.phoneNumber.testPhoneNumbers."+16505550102") "Firebase Auth E2E sender test phone number is configured."
  Assert-Ok ($null -ne $authConfig.signIn.phoneNumber.testPhoneNumbers."+16505550103") "Firebase Auth E2E receiver test phone number is configured."
  $smsAllowedRegions = @($authConfig.smsRegionConfig.allowlistOnly.allowedRegions)
  Assert-Ok ($smsAllowedRegions -contains "KR") "Firebase Auth SMS region KR is allowed."
  Assert-Ok ($smsAllowedRegions -contains "US") "Firebase Auth SMS region US is allowed for emulator test phone."

  $buckets = & gcloud storage buckets list --project=$ProjectId --format="value(name)"
  Assert-Ok ($buckets -contains "$ProjectId.firebasestorage.app") "Default Cloud Storage for Firebase bucket exists."

  $secretState = (& gcloud secrets versions list DEEPGRAM_API_KEY --project=$ProjectId --format="value(state)" | Select-Object -First 1).Trim()
  Assert-Ok ($secretState -eq "enabled") "DEEPGRAM_API_KEY secret has an enabled version."

  $functionsOutput = & node functions\scripts\firebase-cli.js functions:list --project $ProjectId
  $requiredFunctions = @(
    "getOperationalHealth",
    "addFriendByHandle",
    "createRoomInvite",
    "joinRoomByInvite",
    "createTranscriptionDraft",
    "createCalendarIntentDraft",
    "createCalendarEvent",
    "updateCalendarEvent",
    "deleteCalendarEvent",
    "createCalendarProposal",
    "voteCalendarProposal",
    "finalizeCalendarProposal",
    "addFinalizedProposalToMyCalendar",
    "cancelCalendarProposal",
    "sendVoiceMessage",
    "sendInstantVoiceMessage",
    "finalizeClientVoiceMessage",
    "rollupUsageAndCost",
    "deliverScheduledMessages",
    "expireVoiceAudio",
    "onMessageCreated"
  )
  foreach ($name in $requiredFunctions) {
    Assert-Ok (($functionsOutput | Select-String -SimpleMatch $name).Count -gt 0) "Function $name is deployed."
  }
  Assert-Ok (($functionsOutput | Select-String -SimpleMatch $Region).Count -gt 0) "Functions are deployed in $Region."

  $functionsJson = & node functions\scripts\firebase-cli.js functions:list --project $ProjectId --json
  $callables = (($functionsJson | ConvertFrom-Json).result | Where-Object {
    $null -ne $_.callableTrigger -and $_.region -eq $Region
  })
  foreach ($function in $callables) {
    $policyJson = & gcloud run services get-iam-policy $function.runServiceId --project=$ProjectId --region=$Region --format=json
    $policy = $policyJson | ConvertFrom-Json
    $publicInvoker = $false
    foreach ($binding in @($policy.bindings)) {
      if ($binding.role -eq "roles/run.invoker" -and @($binding.members) -contains "allUsers") {
        $publicInvoker = $true
      }
    }
    Assert-Ok $publicInvoker "Callable function $($function.id) allows public Cloud Run invocation."
  }

  $budgetList = Invoke-GoogleApi -Uri "https://billingbudgets.googleapis.com/v1/billingAccounts/$BillingAccountId/budgets"
  $projectBudget = $budgetList.budgets | Where-Object {
    $_.budgetFilter.projects -contains "projects/$ProjectNumber"
  } | Select-Object -First 1
  Assert-Ok ($null -ne $projectBudget) "Project-scoped budget alert exists."

  $loggingMetrics = & gcloud logging metrics list --project=$ProjectId --format="value(name)"
  Assert-Ok ($loggingMetrics -contains "verbal_function_errors") "Function error log metric exists."
  Assert-Ok ($loggingMetrics -contains "verbal_deepgram_errors") "Deepgram error log metric exists."

  $alertPolicies = & gcloud monitoring policies list --project=$ProjectId --format="value(displayName)"
  Assert-Ok ($alertPolicies -contains "Verbal Function Errors") "Function error alert policy exists."
  Assert-Ok ($alertPolicies -contains "Verbal Deepgram Errors") "Deepgram error alert policy exists."

  & node functions\scripts\firebase-cli.js deploy --only firestore:rules,firestore:indexes --project $ProjectId --dry-run | Out-Null
  Assert-Ok $true "Firestore rules and indexes compile in dry-run."

  if ($failures.Count -gt 0) {
    throw "Production backend verification failed: $($failures -join '; ')"
  }

  "Production backend verification passed."
} finally {
  Pop-Location
}
