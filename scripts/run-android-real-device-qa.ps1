param(
  [string]$DeviceId = "",
  [string]$PackageName = "com.voicebeta.verbal",
  [string]$FlutterPath = "C:\Users\jangs\develop\flutter\bin\flutter.bat",
  [switch]$InstallDebug,
  [switch]$SkipLaunch,
  [switch]$Interactive,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$artifactDir = Join-Path $repoRoot "artifacts\android-real-device-qa\$runId"
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

function Write-Utf8NoBomJson {
  param(
    [string]$Path,
    [object]$Value,
    [int]$Depth = 12
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth $Depth), $encoding)
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
  @"
# Android Real Device QA Run / Android 실기기 QA

Run ID: $runId
Device ID: $script:ResolvedDeviceId
Package: $PackageName

## How To Use / 사용 방법

1. Keep this file open while testing Verbal on the connected phone.
2. Mark every item as Pass or Fail and write short notes for failures.
3. Return to the PowerShell window only after all items are checked.
4. Answer `y` only if every required item passed.

1. 이 파일을 열어 둔 상태에서 연결된 휴대폰의 Verbal 앱을 테스트합니다.
2. 각 항목을 Pass/Fail로 표시하고, 실패 항목에는 짧은 메모를 남깁니다.
3. 모든 항목 확인이 끝난 뒤 PowerShell 창으로 돌아옵니다.
4. 모든 필수 항목이 통과했을 때만 `y`를 입력합니다.

## Required Manual Flow / 필수 수동 확인 항목

| No. | Korean item | English item | Pass/Fail | Notes |
|---:|---|---|---|---|
| 1 | Verbal 설치 또는 실행 | Install or launch Verbal |  |  |
| 2 | 실제 SMS 번호로 로그인 | Phone sign-in with a real SMS number |  |  |
| 3 | 이용약관, 개인정보처리방침, 커뮤니티 운영정책 동의 표시 및 저장 | Required Terms/Privacy/Community consent shown and saved |  |  |
| 4 | 프로필 설정과 사용자 ID 예약 | Profile setup and user ID reservation |  |  |
| 5 | 홈 메시지 목록 로딩 | Home message list loads |  |  |
| 6 | 1:1 대화방 생성 | Direct room creation |  |  |
| 7 | 텍스트 메시지 전송, 수정, 삭제 | Text send, edit, delete |  |  |
| 8 | 마이크 권한 팝업 표시 및 허용 | Voice recording permission prompt |  |  |
| 9 | 음성 녹음 후 자동 전송 | Voice record and auto-send |  |  |
| 10 | 음성 transcript가 누락 없이 표시되고 한글 깨짐이 없음 | Voice transcript appears without missing text or broken Korean |  |  |
| 11 | 음성 메시지 재생 | Voice playback works |  |  |
| 12 | 파일 첨부 전송 및 열람 | File attachment send and read |  |  |
| 13 | 위치 메시지 전송 및 열람 | Location send and read |  |  |
| 14 | 기본 preset 없이 예약 전송 설정 | Scheduled send without a default preset |  |  |
| 15 | 메시지 번역 동작 | Translation action |  |  |
| 16 | 음성으로 캘린더 일정 생성 | Calendar voice event create |  |  |
| 17 | 캘린더 일정 수정 및 삭제 | Calendar event edit/delete |  |  |
| 18 | 채팅방 일정 제안 생성, 투표, 확정 | Chat calendar proposal vote/finalize |  |  |
| 19 | 오픈채팅 초대 링크 생성, 입장, 나가기 | Open-chat invite link join/leave |  |  |
| 20 | 메시지 신고와 사용자 차단 | Report message and block user |  |  |
| 21 | 계정 삭제 진입점 열림 | Account deletion entry point opens |  |  |

## Must Not Pass If / 실패 처리 기준

- Korean text is broken, garbled, or shown as question marks.
- A voice message is delivered without transcript text after normal speech.
- Voice playback shows a Firebase authorization error.
- Message sending takes so long that the user cannot tell whether it was sent.
- Calendar voice input creates the wrong date/title without correction UI.

## Evidence Files

- `device.json`
- `launch.png`
- `window.xml`
- `logcat.txt`
- `result.json`

"@ | Set-Content -Encoding UTF8 -Path $Path
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
  flutterPath = $FlutterPath
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

if ($DryRun) {
  Add-Check "dry_run_completed" $true @{ artifactDir = $artifactDir }
} else {
  $lockState = Get-DeviceLockState
  Add-Check "device_unlocked_for_qa" (-not $lockState.locked) $lockState

  if ($InstallDebug) {
    if (-not (Test-Path $FlutterPath)) {
      Add-Check "flutter_exists" $false @{ path = $FlutterPath }
      throw "flutter.bat was not found at $FlutterPath"
    }
    Add-Check "flutter_exists" $true @{ path = $FlutterPath }
    Push-Location (Join-Path $repoRoot "apps\mobile")
    try {
      & $FlutterPath build apk --debug
    } finally {
      Pop-Location
    }
    $apkPath = Join-Path $repoRoot "apps\mobile\build\app\outputs\flutter-apk\app-debug.apk"
    Add-Check "debug_apk_exists" (Test-Path $apkPath) @{ path = $apkPath }
    Invoke-Adb install "-r" $apkPath | Out-Null
    Add-Check "debug_apk_installed" $true @{ path = $apkPath }
  }

  if ($lockState.locked) {
    Add-Check "launch_skipped_device_locked" $false @{
      reason = "Unlock the device before running real-device QA. Android keyguard/PIN screen prevents Verbal UI capture."
    }
  } elseif (-not $SkipLaunch) {
    Invoke-Adb shell am force-stop $PackageName | Out-Null
    Invoke-Adb logcat "-c" | Out-Null
    Invoke-Adb shell monkey "-p" $PackageName "-c" android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 4

    $remoteScreenshot = "/sdcard/verbal-launch-qa.png"
    $remoteXml = "/sdcard/verbal-launch-qa.xml"
    $launchPng = Join-Path $artifactDir "launch.png"
    $windowXml = Join-Path $artifactDir "window.xml"
    $screenshotDisplayId = Capture-Screenshot -RemotePath $remoteScreenshot
    Add-Check "launch_screenshot_captured" (Pull-IfExists $remoteScreenshot $launchPng) @{
      path = $launchPng
      displayId = $screenshotDisplayId
    }
    Invoke-Adb shell uiautomator dump $remoteXml | Out-Null
    Add-Check "window_xml_captured" (Pull-IfExists $remoteXml $windowXml) @{
      path = $windowXml
    }
  }

  if ($lockState.locked) {
    Add-Check "manual_e2e_confirmed" $false @{
      reason = "Unlock the device and rerun with -Interactive to confirm the manual checklist."
      checklist = Join-Path $artifactDir "manual-checklist.md"
    }
  } elseif ($Interactive) {
    Write-Host ""
    Write-Host "Complete the manual QA flow on the connected device."
    Write-Host "연결된 휴대폰에서 manual-checklist.md의 모든 항목을 확인해 주세요."
    Write-Host "When finished, press Enter here to capture final logcat and screenshot."
    Write-Host "완료 후 여기에서 Enter를 누르면 최종 logcat과 screenshot을 수집합니다."
    Read-Host | Out-Null
    Capture-Screenshot -RemotePath /sdcard/verbal-final-qa.png | Out-Null
    Pull-IfExists "/sdcard/verbal-final-qa.png" (Join-Path $artifactDir "final.png") | Out-Null
    $manualAnswer = Read-Host "Did every required manual QA item pass? 모든 필수 수동 QA 항목이 통과했습니까? (y/N)"
    $manualOk = $manualAnswer.Trim().ToLowerInvariant() -in @("y", "yes")
    Add-Check "manual_e2e_confirmed" $manualOk @{
      checklist = Join-Path $artifactDir "manual-checklist.md"
    }
  } else {
    Add-Check "manual_e2e_confirmed" $false @{
      reason = "Run with -Interactive and confirm the manual checklist before this can satisfy launch evidence."
      checklist = Join-Path $artifactDir "manual-checklist.md"
    }
  }

  $logPath = Join-Path $artifactDir "logcat.txt"
  Invoke-Adb logcat "-d" "-v" time | Set-Content -Encoding UTF8 -Path $logPath
  Add-Check "logcat_captured" (Test-Path $logPath) @{ path = $logPath }
}

$failed = @($checks | Where-Object { -not $_.ok })
$result = [PSCustomObject]@{
  ok = ($failed.Count -eq 0)
  runId = $runId
  artifactDir = $artifactDir
  packageName = $PackageName
  deviceId = $script:ResolvedDeviceId
  dryRun = [bool]$DryRun
  latestSummary = if ($DryRun) {
    "artifacts/android-real-device-qa-dryrun-latest.json"
  } else {
    "artifacts/android-real-device-qa-latest.json"
  }
  checks = $checks
  failedCount = $failed.Count
  passedCount = $checks.Count - $failed.Count
  manualChecklist = Join-Path $artifactDir "manual-checklist.md"
}

$resultPath = Join-Path $artifactDir "result.json"
Write-Utf8NoBomJson -Path $resultPath -Value $result -Depth 10
$summaryFileName = if ($DryRun) {
  "android-real-device-qa-dryrun-latest.json"
} else {
  "android-real-device-qa-latest.json"
}
$summaryPath = Join-Path $repoRoot "artifacts\$summaryFileName"
Write-Utf8NoBomJson -Path $summaryPath -Value $result -Depth 10

Write-Output ($result | ConvertTo-Json -Depth 10)
if (-not $result.ok) {
  exit 1
}
