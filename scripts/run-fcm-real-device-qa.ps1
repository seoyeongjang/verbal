param(
  [string]$DeviceId = "",
  [string]$PackageName = "com.voicebeta.verbal",
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$artifactDir = Join-Path $repoRoot "artifacts\fcm-real-device\$runId"
$checks = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

function Add-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [object]$Detail = $null
  )
  $checks.Add([PSCustomObject]@{
    name = $Name
    ok = $Ok
    detail = $Detail
  }) | Out-Null
}

function Write-Utf8NoBomText {
  param(
    [string]$Path,
    [string]$Text
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-Utf8NoBomJson {
  param(
    [string]$Path,
    [object]$Value,
    [int]$Depth = 12
  )
  Write-Utf8NoBomText -Path $Path -Text ($Value | ConvertTo-Json -Depth $Depth)
}

function Invoke-Adb {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  $deviceArgs = @()
  if ($script:ResolvedDeviceId) {
    $deviceArgs = @('-s', $script:ResolvedDeviceId)
  }
  & $adb @deviceArgs @Args
}

function Get-AdbText {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  $output = Invoke-Adb @Args
  return ($output -join "`n").Trim()
}

function Get-Prop {
  param([string]$Name)
  try {
    return Get-AdbText shell getprop $Name
  } catch {
    return ""
  }
}

function Get-DeviceLockState {
  $trust = ""
  $window = ""
  try {
    $trust = Get-AdbText shell dumpsys trust
  } catch {}
  try {
    $window = Get-AdbText shell dumpsys window
  } catch {}

  $locked =
    ($trust -match "deviceLocked=1") -or
    ($window -match "isKeyguardShowing=true") -or
    ($window -match "mDreamingLockscreen=true")

  return [PSCustomObject]@{
    locked = [bool]$locked
    trustSignal = if ($trust -match "deviceLocked=\d") { $Matches[0] } else { "" }
    keyguardShowing = [bool]($window -match "isKeyguardShowing=true")
    dreamingLockscreen = [bool]($window -match "mDreamingLockscreen=true")
  }
}

function Pull-IfExists {
  param(
    [string]$Remote,
    [string]$Local
  )
  try {
    Invoke-Adb pull $Remote $Local | Out-Null
    return Test-Path $Local
  } catch {
    return $false
  }
}

function Resolve-ScreencapDisplayId {
  try {
    $output = Get-AdbText shell dumpsys SurfaceFlinger "--display-id"
    $match = [regex]::Match($output, 'Display\s+([0-9]+)')
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  } catch {}
  return ""
}

function Capture-Screenshot {
  param([string]$RemotePath)
  $displayId = Resolve-ScreencapDisplayId
  $captureArgs = @("shell", "screencap", "-p")
  if ($displayId) {
    $captureArgs += @("-d", $displayId)
    $captureArgs += $RemotePath
    Invoke-Adb @captureArgs | Out-Null
  } else {
    $captureArgs += $RemotePath
    Invoke-Adb @captureArgs | Out-Null
  }
  return $displayId
}

function Write-Checklist {
  param([string]$Path)
  $text = @"
# FCM Real Device QA Run / FCM 실기기 QA

Run ID: $runId
Device ID: $script:ResolvedDeviceId
Package: $PackageName

## Required Test Setup / 필수 테스트 준비

- Use a real Android device with Verbal installed.
- Sign in to Verbal on this target device.
- Use a second device/account or backend trigger to send a real message to the target account.
- Accept Android notification permission before testing.
- Do not use Android force-stop for the terminated-state test. Force-stopped apps may not receive FCM.

- Verbal이 설치된 실제 Android 기기를 사용합니다.
- 대상 기기에서 Verbal에 로그인합니다.
- 두 번째 기기/계정 또는 백엔드 트리거로 대상 계정에 실제 메시지를 보냅니다.
- 테스트 전에 Android 알림 권한을 허용합니다.
- Terminated 테스트에서는 Android force-stop을 사용하지 말고 스크립트의 `am kill` 흐름을 사용합니다.

## Required States / 필수 수신 상태

| No. | Korean state | English state | Pass/Fail | Evidence file |
|---:|---|---|---|---|
| 1 | Verbal이 화면에 열린 상태에서 알림 수신 | Foreground: Verbal is open and visible when the push arrives |  | `foreground.*` |
| 2 | Verbal이 백그라운드에 있는 상태에서 알림 수신 | Background: Verbal is in the background when the push arrives |  | `background.*` |
| 3 | `am kill`로 앱 프로세스가 종료된 상태에서 알림 수신 | Terminated: Verbal process is killed with `am kill`, not force-stopped |  | `terminated.*` |
| 4 | 휴대폰 잠금화면 상태에서 알림 수신 | Lock screen: phone is locked when the push arrives |  | `lock-screen.*` |

## Must Not Pass If / 실패 처리 기준

- The message arrives in chat but no system notification is shown for background, terminated, or lock-screen states.
- Android notification permission is denied.
- The app was force-stopped before the terminated-state test.
- The notification text is blank, broken, or belongs to another app.

- 백그라운드, 종료, 잠금화면 상태에서 채팅 메시지는 도착했지만 시스템 알림이 보이지 않으면 실패입니다.
- Android 알림 권한이 거부되어 있으면 실패입니다.
- Terminated 테스트 전에 앱을 force-stop했다면 실패입니다.
- 알림 텍스트가 비어 있거나 깨졌거나 다른 앱 알림이면 실패입니다.

## Evidence Files

- `device.json`
- `notification-settings.txt`
- `<state>.png`
- `<state>-logcat.txt`
- `<state>-notification-dump.txt`
- `result.json`

"@
  Write-Utf8NoBomText -Path $Path -Text $text
}

function Capture-StateEvidence {
  param([string]$State)
  $remoteScreenshot = "/sdcard/verbal-fcm-$State.png"
  $localScreenshot = Join-Path $artifactDir "$State.png"
  $logPath = Join-Path $artifactDir "$State-logcat.txt"
  $notificationDump = Join-Path $artifactDir "$State-notification-dump.txt"

  try {
    Capture-Screenshot -RemotePath $remoteScreenshot | Out-Null
    Pull-IfExists $remoteScreenshot $localScreenshot | Out-Null
  } catch {}

  try {
    Invoke-Adb logcat "-d" "-v" time | Set-Content -Encoding UTF8 -Path $logPath
  } catch {}

  try {
    Invoke-Adb shell dumpsys notification "--noredact" | Set-Content -Encoding UTF8 -Path $notificationDump
  } catch {}

  return [PSCustomObject]@{
    screenshot = $localScreenshot
    logcat = $logPath
    notificationDump = $notificationDump
    screenshotExists = Test-Path $localScreenshot
    logcatExists = Test-Path $logPath
    notificationDumpExists = Test-Path $notificationDump
  }
}

function Confirm-State {
  param(
    [string]$State,
    [string]$Instruction
  )
  Write-Host ""
  Write-Host "[$State]"
  Write-Host $Instruction
  Write-Host "After the push is received or the state fails, return here."
  Write-Host "푸시 알림을 받았거나 실패를 확인했으면 여기로 돌아오세요."
  $answer = Read-Host "Was the FCM notification received in this state? 이 상태에서 FCM 알림이 수신되었습니까? (y/N)"
  $ok = $answer.Trim().ToLowerInvariant() -in @("y", "yes")
  $evidence = Capture-StateEvidence -State $State
  Add-Check "fcm_$State`_verified" $ok @{
    evidence = $evidence
  }
  return [PSCustomObject]@{
    ok = $ok
    evidence = $evidence
  }
}

if (-not (Test-Path $adb)) {
  Add-Check "adb_exists" $false @{ path = $adb }
  throw "adb.exe was not found at $adb"
}
Add-Check "adb_exists" $true @{ path = $adb }

$devicesRaw = & $adb devices -l
$deviceLines = @($devicesRaw | Where-Object { $_ -match "\sdevice\s" })
$connectedDevices = @($deviceLines | ForEach-Object { ($_ -split "\s+")[0] })
Add-Check "adb_device_visible" (($connectedDevices.Count -gt 0) -or $DryRun.IsPresent) @{
  devices = $connectedDevices
  raw = ($devicesRaw -join "`n")
}

if ($DeviceId.Trim()) {
  if ($connectedDevices -notcontains $DeviceId.Trim()) {
    Add-Check "requested_device_available" $false @{ requested = $DeviceId.Trim() }
    if (-not $DryRun) {
      throw "Requested Android device was not found: $($DeviceId.Trim())"
    }
  }
  $script:ResolvedDeviceId = $DeviceId.Trim()
} elseif ($connectedDevices.Count -eq 1) {
  $script:ResolvedDeviceId = $connectedDevices[0]
} elseif ($connectedDevices.Count -gt 1) {
  Add-Check "single_device_selected" $false @{ devices = $connectedDevices }
  if (-not $DryRun) {
    throw "Multiple Android devices are connected. Rerun with -DeviceId."
  }
} else {
  $script:ResolvedDeviceId = ""
  if (-not $DryRun) {
    throw "No Android device is connected. Rerun after adb devices shows a device state."
  }
}

Write-Checklist -Path (Join-Path $artifactDir "manual-checklist.md")

$deviceInfo = [PSCustomObject]@{
  runId = $runId
  dryRun = [bool]$DryRun
  packageName = $PackageName
  requestedDeviceId = $DeviceId
  resolvedDeviceId = $script:ResolvedDeviceId
  adbPath = $adb
  connectedDevices = $connectedDevices
  collectedAt = (Get-Date).ToString("o")
}

if ($script:ResolvedDeviceId) {
  $deviceInfo | Add-Member -NotePropertyName manufacturer -NotePropertyValue (Get-Prop "ro.product.manufacturer")
  $deviceInfo | Add-Member -NotePropertyName model -NotePropertyValue (Get-Prop "ro.product.model")
  $deviceInfo | Add-Member -NotePropertyName androidRelease -NotePropertyValue (Get-Prop "ro.build.version.release")
  $deviceInfo | Add-Member -NotePropertyName sdk -NotePropertyValue (Get-Prop "ro.build.version.sdk")
  $deviceInfo | Add-Member -NotePropertyName locale -NotePropertyValue (Get-Prop "persist.sys.locale")
  $deviceInfo | Add-Member -NotePropertyName wmSize -NotePropertyValue (Get-AdbText shell wm size)
  $deviceInfo | Add-Member -NotePropertyName wmDensity -NotePropertyValue (Get-AdbText shell wm density)
  $initialLockState = Get-DeviceLockState
  $deviceInfo | Add-Member -NotePropertyName deviceLocked -NotePropertyValue $initialLockState.locked
}

Write-Utf8NoBomJson -Path (Join-Path $artifactDir "device.json") -Value $deviceInfo -Depth 8

$states = [ordered]@{
  foreground = $false
  background = $false
  terminated = $false
  lockScreen = $false
}
$stateEvidence = [ordered]@{}

if ($DryRun) {
  Add-Check "dry_run_completed" $true @{ artifactDir = $artifactDir }
} else {
  $lockState = Get-DeviceLockState
  Add-Check "device_unlocked_for_fcm_start" (-not $lockState.locked) $lockState

  if (-not $lockState.locked) {
    Invoke-Adb logcat "-c" | Out-Null
    try {
      Invoke-Adb shell cmd appops get $PackageName POST_NOTIFICATION |
        Set-Content -Encoding UTF8 -Path (Join-Path $artifactDir "notification-settings.txt")
    } catch {
      "Unable to read notification appops: $($_.Exception.Message)" |
        Set-Content -Encoding UTF8 -Path (Join-Path $artifactDir "notification-settings.txt")
    }

    Invoke-Adb shell monkey "-p" $PackageName "-c" android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 3
    $foreground = Confirm-State -State "foreground" -Instruction "Keep Verbal open on the target device. 대상 기기에서 Verbal을 열어 둔 뒤 두 번째 계정/기기에서 메시지를 보내고 foreground 알림 또는 인앱 push 처리를 확인하세요."
    $states.foreground = $foreground.ok
    $stateEvidence.foreground = $foreground.evidence

    Invoke-Adb shell input keyevent 3 | Out-Null
    Start-Sleep -Seconds 2
    $background = Confirm-State -State "background" -Instruction "Verbal is now in the background. Verbal이 백그라운드에 있습니다. 새 메시지를 보내고 시스템 알림이 도착하는지 확인하세요."
    $states.background = $background.ok
    $stateEvidence.background = $background.evidence

    Invoke-Adb shell am kill $PackageName | Out-Null
    Start-Sleep -Seconds 2
    $terminated = Confirm-State -State "terminated" -Instruction "The app process was killed with am kill, not force-stop. 앱 프로세스가 am kill로 종료되었습니다. 새 메시지를 보내고 알림이 도착하는지 확인하세요."
    $states.terminated = $terminated.ok
    $stateEvidence.terminated = $terminated.evidence

    Write-Host ""
    Write-Host "Lock the target phone screen now. 대상 휴대폰 화면을 지금 잠그세요."
    Write-Host "Send a new message from another device/account, then unlock the phone and return here."
    Write-Host "다른 기기/계정에서 새 메시지를 보낸 뒤, 휴대폰을 잠금 해제하고 여기로 돌아오세요."
    $lockScreen = Confirm-State -State "lock-screen" -Instruction "Confirm the notification was visible or delivered while the device was locked. 잠금화면 상태에서 알림이 표시 또는 수신되었는지 확인하세요."
    $states.lockScreen = $lockScreen.ok
    $stateEvidence.lockScreen = $lockScreen.evidence
  }
}

$stateChecks = @($states.foreground, $states.background, $states.terminated, $states.lockScreen)
$failed = @($checks | Where-Object { -not $_.ok })
$result = [PSCustomObject]@{
  ok = (($failed.Count -eq 0) -and ($DryRun -or ($stateChecks -notcontains $false)))
  runId = $runId
  artifactDir = $artifactDir
  packageName = $PackageName
  deviceId = $script:ResolvedDeviceId
  dryRun = [bool]$DryRun
  latestSummary = if ($DryRun) {
    "artifacts/fcm-real-device-dryrun-latest.json"
  } else {
    "artifacts/fcm-real-device-latest.json"
  }
  states = $states
  stateEvidence = $stateEvidence
  checks = $checks
  failedCount = $failed.Count
  passedCount = $checks.Count - $failed.Count
  manualChecklist = Join-Path $artifactDir "manual-checklist.md"
}

$resultPath = Join-Path $artifactDir "result.json"
Write-Utf8NoBomJson -Path $resultPath -Value $result -Depth 12
$summaryFileName = if ($DryRun) {
  "fcm-real-device-dryrun-latest.json"
} else {
  "fcm-real-device-latest.json"
}
$summaryPath = Join-Path $repoRoot "artifacts\$summaryFileName"
Write-Utf8NoBomJson -Path $summaryPath -Value $result -Depth 12

Write-Output ($result | ConvertTo-Json -Depth 12)
if (-not $result.ok) {
  exit 1
}
