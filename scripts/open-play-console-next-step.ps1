param(
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$nextStepPath = Join-Path $repoRoot "artifacts\next-external-step-latest.json"
$nextStepMdPath = Join-Path $repoRoot "artifacts\next-external-step-latest.md"
$copySheetPath = Join-Path $repoRoot "artifacts\play-console\verbal-app-content-copy-sheet-latest.html"
$statusPath = Join-Path $repoRoot "artifacts\launch-status-latest.md"

if (-not (Test-Path $nextStepPath)) {
  throw "Missing artifacts\next-external-step-latest.json. Run npm run guide:next-launch-step from functions first."
}

$nextStep = Get-Content -LiteralPath $nextStepPath -Raw -Encoding UTF8 | ConvertFrom-Json
$title = [string]$nextStep.nextAction.title
$blocker = [string]$nextStep.nextBlocker
$recordCommand = [string]$nextStep.nextAction.recordCommand
$playConsoleUrl = ""

if ($nextStep.nextAction.exactValues -and $nextStep.nextAction.exactValues.playConsoleAppUrl) {
  $playConsoleUrl = [string]$nextStep.nextAction.exactValues.playConsoleAppUrl
}

Write-Host "Current Verbal launch step"
Write-Host "  Blocker : $blocker"
Write-Host "  Action  : $title"
if ($recordCommand) {
  Write-Host "  Record  : $recordCommand"
}

if ($NoBrowser) {
  exit 0
}

if (Test-Path $copySheetPath) {
  Start-Process -FilePath (Resolve-Path $copySheetPath).Path
}

if (Test-Path $nextStepMdPath) {
  Start-Process -FilePath (Resolve-Path $nextStepMdPath).Path
}

if (Test-Path $statusPath) {
  Start-Process -FilePath (Resolve-Path $statusPath).Path
}

if ($playConsoleUrl) {
  Start-Process -FilePath $playConsoleUrl
} else {
  Write-Host "No direct Play Console app URL was found in the current next-step artifact."
}
