param(
  [string]$DeviceId = "",
  [string]$PackageName = "com.voicebeta.verbal",
  [string]$ExpectedVersionCode = "1",
  [string]$ExpectedVersionName = "1.0.0"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$artifactDir = Join-Path $repoRoot "artifacts\android-real-device-precheck\$runId"
$checks = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]

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

function Add-Warning {
  param(
    [string]$Name,
    [object]$Detail = $null
  )
  $warnings.Add([PSCustomObject]@{
    name = $Name
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

function Write-Utf8NoBomJson {
  param(
    [string]$Path,
    [object]$Value,
    [int]$Depth = 12
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth $Depth), $encoding)
}

function Extract-FirstMatch {
  param(
    [string]$Text,
    [string]$Pattern
  )
  $match = [regex]::Match($Text, $Pattern)
  if ($match.Success -and $match.Groups.Count -gt 1) {
    return $match.Groups[1].Value
  }
  return ""
}

function Extract-PermissionGranted {
  param(
    [string]$Text,
    [string]$Permission
  )
  $escaped = [regex]::Escape($Permission)
  $pattern = "$escaped`: granted=(true|false)"
  $match = [regex]::Match($Text, $pattern)
  if ($match.Success) {
    return $match.Groups[1].Value -eq "true"
  }
  return $null
}

if (-not (Test-Path $adb)) {
  Add-Check "adb_exists" $false @{ path = $adb }
  throw "adb.exe was not found at $adb"
}
Add-Check "adb_exists" $true @{ path = $adb }

$devicesRaw = & $adb devices -l
$deviceLines = @($devicesRaw | Where-Object { $_ -match "\sdevice\s" })
$connectedDevices = @($deviceLines | ForEach-Object { ($_ -split "\s+")[0] })
Add-Check "adb_device_visible" ($connectedDevices.Count -gt 0) @{
  devices = $connectedDevices
  raw = ($devicesRaw -join "`n")
}

if ($DeviceId.Trim()) {
  if ($connectedDevices -notcontains $DeviceId.Trim()) {
    Add-Check "requested_device_available" $false @{ requested = $DeviceId.Trim() }
    throw "Requested Android device was not found: $($DeviceId.Trim())"
  }
  $script:ResolvedDeviceId = $DeviceId.Trim()
} elseif ($connectedDevices.Count -eq 1) {
  $script:ResolvedDeviceId = $connectedDevices[0]
} elseif ($connectedDevices.Count -gt 1) {
  Add-Check "single_device_selected" $false @{ devices = $connectedDevices }
  throw "Multiple Android devices are connected. Rerun with -DeviceId."
} else {
  throw "No Android device is connected. Rerun after adb devices shows a device state."
}

$deviceInfo = [PSCustomObject]@{
  runId = $runId
  packageName = $PackageName
  expectedVersionCode = $ExpectedVersionCode
  expectedVersionName = $ExpectedVersionName
  requestedDeviceId = $DeviceId
  resolvedDeviceId = $script:ResolvedDeviceId
  adbPath = $adb
  connectedDevices = $connectedDevices
  collectedAt = (Get-Date).ToString("o")
  manufacturer = Get-Prop "ro.product.manufacturer"
  model = Get-Prop "ro.product.model"
  androidRelease = Get-Prop "ro.build.version.release"
  sdk = Get-Prop "ro.build.version.sdk"
  locale = Get-Prop "persist.sys.locale"
  wmSize = Get-AdbText shell wm size
  wmDensity = Get-AdbText shell wm density
}

$powerDump = Get-AdbText shell dumpsys power
$wakefulness = Extract-FirstMatch $powerDump "mWakefulness=([^\r\n]+)"
$deviceInfo | Add-Member -NotePropertyName wakefulness -NotePropertyValue $wakefulness
$lockState = Get-DeviceLockState
$deviceInfo | Add-Member -NotePropertyName deviceLocked -NotePropertyValue $lockState.locked
if ($wakefulness -and $wakefulness -ne "Awake") {
  Add-Warning "device_not_awake" @{
    wakefulness = $wakefulness
    note = "Turn on and unlock the phone before interactive QA so screenshots and permission prompts are visible."
  }
}

if ($lockState.locked) {
  Add-Warning "device_locked" @{
    note = "Unlock the Android device before real-device QA. Locked devices only capture System UI/keyguard, not Verbal."
    lockState = $lockState
  }
}

$packageList = Get-AdbText shell pm list packages $PackageName
$packageInstalled = $packageList -match [regex]::Escape("package:$PackageName")
Add-Check "package_installed" $packageInstalled @{
  packageName = $PackageName
  packageList = $packageList
}

$packageDump = ""
$permissions = [ordered]@{}
$packageMeta = [ordered]@{}
if ($packageInstalled) {
  $packageDump = Get-AdbText shell dumpsys package $PackageName
  $packageDump | Set-Content -Encoding UTF8 -Path (Join-Path $artifactDir "package-dump.txt")

  $packageMeta.versionCode = Extract-FirstMatch $packageDump "versionCode=([0-9]+)"
  $packageMeta.versionName = Extract-FirstMatch $packageDump "versionName=([^\s]+)"
  $packageMeta.firstInstallTime = Extract-FirstMatch $packageDump "firstInstallTime=([^\r\n]+)"
  $packageMeta.lastUpdateTime = Extract-FirstMatch $packageDump "lastUpdateTime=([^\r\n]+)"
  $packageMeta.stopped = Extract-FirstMatch $packageDump "stopped=([^\s]+)"
  $packageMeta.notLaunched = Extract-FirstMatch $packageDump "notLaunched=([^\s]+)"

  Add-Check "version_code_matches_expected" ($packageMeta.versionCode -eq $ExpectedVersionCode) @{
    actual = $packageMeta.versionCode
    expected = $ExpectedVersionCode
  }
  Add-Check "version_name_matches_expected" ($packageMeta.versionName -eq $ExpectedVersionName) @{
    actual = $packageMeta.versionName
    expected = $ExpectedVersionName
  }

  foreach ($permission in @(
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.CAMERA"
  )) {
    $permissions[$permission] = Extract-PermissionGranted $packageDump $permission
  }

  if ($permissions["android.permission.POST_NOTIFICATIONS"] -ne $true) {
    Add-Warning "notification_permission_not_granted" @{
      permission = "android.permission.POST_NOTIFICATIONS"
      granted = $permissions["android.permission.POST_NOTIFICATIONS"]
    }
  }
  if ($permissions["android.permission.RECORD_AUDIO"] -ne $true) {
    Add-Warning "microphone_permission_not_granted_yet" @{
      permission = "android.permission.RECORD_AUDIO"
      note = "This is acceptable before manual QA if the tester verifies the permission prompt and grants it during voice recording."
    }
  }
}

$remoteScreenshot = "/sdcard/verbal-precheck.png"
$localScreenshot = Join-Path $artifactDir "precheck.png"
try {
  $screenshotDisplayId = Capture-Screenshot -RemotePath $remoteScreenshot
  Add-Check "device_screenshot_captured" (Pull-IfExists $remoteScreenshot $localScreenshot) @{
    path = $localScreenshot
    displayId = $screenshotDisplayId
    wakefulness = $wakefulness
  }
} catch {
  Add-Check "device_screenshot_captured" $false @{ error = $_.Exception.Message }
}

Add-Check "precheck_completed" $true @{ artifactDir = $artifactDir }

$failed = @($checks | Where-Object { -not $_.ok })
$result = [PSCustomObject]@{
  ok = ($failed.Count -eq 0)
  runId = $runId
  artifactDir = $artifactDir
  packageName = $PackageName
  deviceId = $script:ResolvedDeviceId
  device = $deviceInfo
  package = $packageMeta
  permissions = $permissions
  warnings = $warnings
  checks = $checks
  failedCount = $failed.Count
  passedCount = $checks.Count - $failed.Count
  latestSummary = "artifacts/android-real-device-precheck-latest.json"
}

Write-Utf8NoBomJson -Path (Join-Path $artifactDir "device.json") -Value $deviceInfo -Depth 10
Write-Utf8NoBomJson -Path (Join-Path $artifactDir "result.json") -Value $result -Depth 12
Write-Utf8NoBomJson -Path (Join-Path $repoRoot "artifacts\android-real-device-precheck-latest.json") -Value $result -Depth 12

Write-Output ($result | ConvertTo-Json -Depth 12)
if (-not $result.ok) {
  exit 1
}
