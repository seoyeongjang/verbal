param(
  [string]$ProjectId = "voice-messenger-jangs-260522",
  [string]$Region = "asia-northeast3"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot
try {
  $functionsJson = & node functions\scripts\firebase-cli.js functions:list --project $ProjectId --json
  $functions = ($functionsJson | ConvertFrom-Json).result
  $callables = $functions | Where-Object {
    $null -ne $_.callableTrigger -and $_.region -eq $Region
  }

  foreach ($function in $callables) {
    $serviceId = $function.runServiceId
    if (-not $serviceId) {
      throw "Callable function $($function.id) does not include a Cloud Run service id."
    }

    & gcloud run services add-iam-policy-binding $serviceId `
      --project=$ProjectId `
      --region=$Region `
      --member=allUsers `
      --role=roles/run.invoker `
      --quiet | Out-Null

    "Callable invoker is public: $($function.id) -> $serviceId"
  }
} finally {
  Pop-Location
}
