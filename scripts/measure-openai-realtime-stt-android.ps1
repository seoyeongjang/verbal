param(
  [string]$DeviceId = "",
  [int]$RelayPort = 8792,
  [switch]$Mock,
  [switch]$SkipSetup,
  [int]$RecordSeconds = 2,
  [int]$MaxBubbleMs = 1000,
  [int]$MaxTranscriptMs = 1000,
  [string]$SpeakText = ""
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$DefaultSpeakTextChars = @(
  0xC624, 0xB298, 0x20, 0xC624, 0xD6C4, 0x20, 0xC138, 0xC2DC, 0xC5D0,
  0x20, 0xD68C, 0xC758, 0x20, 0xAC00, 0xB2A5, 0xD569, 0xB2C8, 0xB2E4
)
if (-not $SpeakText.Trim()) {
  $SpeakText = -join ($DefaultSpeakTextChars | ForEach-Object { [char]$_ })
}


$repoRoot = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$logDir = Join-Path $repoRoot 'dist\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$labelVoiceRecord = "$([char]0xC74C)$([char]0xC131) $([char]0xB179)$([char]0xC74C)"
$labelSend = "$([char]0xC804)$([char]0xC1A1)"
$labelRoomYaya = "$([char]0xC57C)$([char]0xC57C)"
$labelRoomPark = "$([char]0xBC15)$([char]0xC11C)$([char]0xC900)"
$labelRoomMinji = "$([char]0xAE40)$([char]0xBBFC)$([char]0xC9C0)"

if (-not (Test-Path $adb)) {
  throw "adb.exe was not found at $adb"
}

if (-not $SkipSetup) {
  $setupArgs = @{ RelayPort = $RelayPort }
  if ($DeviceId.Trim()) {
    $setupArgs.DeviceId = $DeviceId.Trim()
  }
  if ($Mock.IsPresent) {
    $setupArgs.Mock = $true
  }
  & (Join-Path $PSScriptRoot 'run-openai-realtime-stt-android.ps1') @setupArgs
}

$adbDeviceArgs = @()
if ($DeviceId.Trim()) {
  $adbDeviceArgs = @('-s', $DeviceId.Trim())
}

function Invoke-Adb {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  & $adb @adbDeviceArgs @Args
}

function Get-WindowXml {
  $remote = '/sdcard/verbal_window.xml'
  $local = Join-Path $logDir 'verbal_window.xml'
  Invoke-Adb shell uiautomator dump $remote | Out-Null
  Invoke-Adb pull $remote $local | Out-Null
  return $local
}

function Get-CenterForNode {
  param(
    [string]$XmlPath,
    [string[]]$Patterns
  )
  $xml = Get-Content -Raw -Encoding UTF8 $XmlPath
  foreach ($pattern in $Patterns) {
    $escaped = [Regex]::Escape($pattern)
    $regex = "<node\b[^>]*(?:text|content-desc)=""[^""]*$escaped[^""]*""[^>]*bounds=""\[(\d+),(\d+)\]\[(\d+),(\d+)\]"""
    $match = [Regex]::Match($xml, $regex)
    if ($match.Success) {
      $left = [int]$match.Groups[1].Value
      $top = [int]$match.Groups[2].Value
      $right = [int]$match.Groups[3].Value
      $bottom = [int]$match.Groups[4].Value
      return [PSCustomObject]@{
        X = [int](($left + $right) / 2)
        Y = [int](($top + $bottom) / 2)
        Pattern = $pattern
      }
    }
  }
  return $null
}

function Tap-NodeOrFallback {
  param(
    [string[]]$Patterns,
    [int]$FallbackX,
    [int]$FallbackY
  )
  $xml = Get-WindowXml
  $node = Get-CenterForNode -XmlPath $xml -Patterns $Patterns
  if ($node -ne $null) {
    Invoke-Adb shell input tap $node.X $node.Y | Out-Null
    return $node
  }
  Invoke-Adb shell input tap $FallbackX $FallbackY | Out-Null
  return [PSCustomObject]@{ X = $FallbackX; Y = $FallbackY; Pattern = 'fallback' }
}

function Parse-Metric {
  param([string]$Line, [string]$Name)
  $match = [Regex]::Match($Line, "$Name=(-?\d+)")
  if (-not $match.Success) {
    return $null
  }
  return [int]$match.Groups[1].Value
}

function ConvertTo-Utf8Base64 {
  param([string]$Value)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  return [Convert]::ToBase64String($bytes)
}

Invoke-Adb shell am force-stop com.voicebeta.verbal | Out-Null
& $adb @adbDeviceArgs shell monkey '-p' 'com.voicebeta.verbal' '-c' 'android.intent.category.LAUNCHER' '1' | Out-Null
Start-Sleep -Seconds 2

$xml = Get-WindowXml
$xmlText = Get-Content -Raw -Encoding UTF8 $xml
if (-not $xmlText.Contains($labelVoiceRecord)) {
  Invoke-Adb shell input tap 240 975 | Out-Null
  Start-Sleep -Seconds 1
  $xml = Get-WindowXml
  $xmlText = Get-Content -Raw -Encoding UTF8 $xml
  if (-not $xmlText.Contains($labelVoiceRecord)) {
    Invoke-Adb shell input tap 240 1420 | Out-Null
    Start-Sleep -Seconds 1
  }
}

& $adb @adbDeviceArgs logcat '-c' | Out-Null
Tap-NodeOrFallback -Patterns @($labelVoiceRecord) -FallbackX 684 -FallbackY 2394 | Out-Null
if ($SpeakText.Trim()) {
  Start-Sleep -Milliseconds 550
  $encodedSpeakText = ConvertTo-Utf8Base64 -Value $SpeakText.Trim()
  & $adb @adbDeviceArgs shell am start `
    -a com.voicebeta.verbal.DEBUG_SPEAK `
    -n com.voicebeta.verbal/.MainActivity `
    --es textBase64 $encodedSpeakText `
    --es language ko-KR | Out-Null
}
Start-Sleep -Seconds $RecordSeconds
Invoke-Adb shell input tap 960 2394 | Out-Null
Start-Sleep -Seconds 8

$logPath = Join-Path $logDir "voice-stt-measure-$((Get-Date).ToString('yyyyMMdd-HHmmss')).log"
& $adb @adbDeviceArgs logcat '-d' '-t' '5000' '-v' 'time' > $logPath
$timingLine = Select-String -Path $logPath -Pattern 'voice_send_client_timing' | Select-Object -Last 1
if (-not $timingLine) {
  throw "voice_send_client_timing log was not found. Log saved at $logPath"
}

$line = $timingLine.Line
$bubbleMs = Parse-Metric -Line $line -Name 'sendTapToPendingBubbleMs'
$transcriptMs = Parse-Metric -Line $line -Name 'sendTapToTranscriptAvailableMs'
$finalReady = $line -match 'finalTranscriptReadyBeforeSend=true'
$provider = if ($line -match 'sttProvider=([^ ]+)') { $Matches[1] } else { 'unknown' }
$messageId = if ($line -match 'messageId=([^ ]+)') { $Matches[1] } else { '' }
$lateTranscriptMs = $null
if ($messageId) {
  $lateLine = Select-String -Path $logPath -Pattern "voice_send_late_transcript messageId=$messageId " |
    Select-Object -First 1
  if ($lateLine) {
    $lateTranscriptMs = Parse-Metric -Line $lateLine.Line -Name 'sendTapToLateTranscriptMs'
  }
  if ($lateTranscriptMs -eq $null) {
    $inlineLine = Select-String -Path $logPath -Pattern "voice_send_inline_stt_completed messageId=$messageId " |
      Where-Object {
        $length = Parse-Metric -Line $_.Line -Name 'transcriptLength'
        $length -ne $null -and $length -gt 0
      } |
      Select-Object -First 1
    if ($inlineLine) {
      $lateTranscriptMs = Parse-Metric -Line $inlineLine.Line -Name 'totalMs'
    }
  }
  if ($lateTranscriptMs -eq $null) {
    $finalizeLine = Select-String -Path $logPath -Pattern "voice_send_finalize_completed messageId=$messageId " |
      Where-Object { $_.Line -match 'sttStatus=completed' } |
      Select-Object -First 1
    if ($finalizeLine) {
      $lateTranscriptMs = Parse-Metric -Line $finalizeLine.Line -Name 'totalFinalizeMs'
    }
  }
}
$effectiveTranscriptMs = $transcriptMs
if (($effectiveTranscriptMs -eq $null -or $effectiveTranscriptMs -lt 0) -and
    $lateTranscriptMs -ne $null) {
  $effectiveTranscriptMs = $lateTranscriptMs
}
$transcriptObserved = $finalReady -or
  ($lateTranscriptMs -ne $null -and $lateTranscriptMs -ge 0)

$result = [PSCustomObject]@{
  provider = $provider
  messageId = $messageId
  sendTapToPendingBubbleMs = $bubbleMs
  sendTapToTranscriptAvailableMs = $transcriptMs
  lateTranscriptMs = $lateTranscriptMs
  effectiveTranscriptMs = $effectiveTranscriptMs
  finalTranscriptReadyBeforeSend = $finalReady
  transcriptObservedAfterSend = $transcriptObserved
  passBubble = ($bubbleMs -ne $null -and $bubbleMs -le $MaxBubbleMs)
  passTranscript = ($effectiveTranscriptMs -ne $null -and $effectiveTranscriptMs -ge 0 -and $effectiveTranscriptMs -le $MaxTranscriptMs -and $transcriptObserved)
  logPath = $logPath
}

Write-Output "STT latency measurement"
Write-Output "provider=$($result.provider)"
Write-Output "sendTapToPendingBubbleMs=$($result.sendTapToPendingBubbleMs)"
Write-Output "sendTapToTranscriptAvailableMs=$($result.sendTapToTranscriptAvailableMs)"
Write-Output "lateTranscriptMs=$($result.lateTranscriptMs)"
Write-Output "effectiveTranscriptMs=$($result.effectiveTranscriptMs)"
Write-Output "finalTranscriptReadyBeforeSend=$($result.finalTranscriptReadyBeforeSend)"
Write-Output "transcriptObservedAfterSend=$($result.transcriptObservedAfterSend)"
Write-Output "passBubble=$($result.passBubble)"
Write-Output "passTranscript=$($result.passTranscript)"
Write-Output "logPath=$($result.logPath)"
Write-Output ($result | ConvertTo-Json -Compress)

if (-not $result.passBubble -or -not $result.passTranscript) {
  exit 1
}
