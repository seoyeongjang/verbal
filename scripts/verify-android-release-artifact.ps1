param(
  [string]$ExpectedPackageName = "com.voicebeta.verbal",
  [string]$ExpectedAppName = "Verbal"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path -Parent $PSScriptRoot
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$artifactDir = Join-Path $repoRoot 'artifacts'
$resultPath = Join-Path $artifactDir "android-release-verification-$runId.json"
$latestPath = Join-Path $artifactDir 'android-release-verification-latest.json'
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

function Read-Text {
  param([string]$Path)
  return [System.IO.File]::ReadAllText((Resolve-Path $Path), [System.Text.Encoding]::UTF8)
}

function Read-Properties {
  param([string]$Path)
  $props = @{}
  if (-not (Test-Path $Path)) {
    return $props
  }
  Get-Content -Encoding UTF8 $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      return
    }
    $idx = $line.IndexOf('=')
    if ($idx -le 0) {
      return
    }
    $key = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim()
    $props[$key] = $value
  }
  return $props
}

function Get-Sha256 {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return ""
  }
  return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-RelativeDisplayPath {
  param([string]$Path)
  if (-not $Path) {
    return ""
  }
  $rootFull = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
  $targetFull = [System.IO.Path]::GetFullPath($Path)
  if ($targetFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $targetFull.Substring($rootFull.Length)
  }
  return $targetFull
}

function Invoke-KeytoolList {
  param(
    [string]$KeytoolPath,
    [string]$KeystorePath,
    [string]$Alias,
    [string]$StorePassword
  )
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
  $process.StartInfo.FileName = $KeytoolPath
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  $process.StartInfo.CreateNoWindow = $true
  $args = @(
    "-list",
    "-v",
    "-keystore",
    $KeystorePath,
    "-alias",
    $Alias,
    "-storepass",
    $StorePassword
  )
  $process.StartInfo.Arguments = ($args | ForEach-Object {
    $arg = [string]$_
    if ($arg -match '[\s"]') {
      '"' + ($arg -replace '"', '\"') + '"'
    } else {
      $arg
    }
  }) -join ' '
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  return [PSCustomObject]@{
    exitCode = $process.ExitCode
    output = "$stdout`n$stderr"
  }
}

function Get-LatestSourceMtime {
  param([string[]]$Paths)
  $latest = [PSCustomObject]@{ path = ""; lastWriteTimeUtc = [datetime]'1970-01-01T00:00:00Z' }
  foreach ($item in $Paths) {
    $full = Join-Path $repoRoot $item
    if (-not (Test-Path $full)) {
      continue
    }
    $files = @()
    if ((Get-Item $full).PSIsContainer) {
      $files = Get-ChildItem -Path $full -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch '\\(\.dart_tool|build)\\' }
    } else {
      $files = @(Get-Item $full)
    }
    foreach ($file in $files) {
      if ($file.LastWriteTimeUtc -gt $latest.lastWriteTimeUtc) {
        $latest = [PSCustomObject]@{
          path = Resolve-Path -Relative $file.FullName
          lastWriteTimeUtc = $file.LastWriteTimeUtc
        }
      }
    }
  }
  return $latest
}

$gradlePath = Join-Path $repoRoot 'apps\mobile\android\app\build.gradle.kts'
$googleServicesPath = Join-Path $repoRoot 'apps\mobile\android\app\google-services.json'
$keyPropertiesPath = Join-Path $repoRoot 'apps\mobile\android\key.properties'
$pubspecPath = Join-Path $repoRoot 'apps\mobile\pubspec.yaml'
$distAabPath = Join-Path $repoRoot 'dist\android\app-release.aab'
$buildAabPath = Join-Path $repoRoot 'apps\mobile\build\app\outputs\bundle\release\app-release.aab'

$gradle = Read-Text $gradlePath
$googleServices = Get-Content -Raw -Encoding UTF8 $googleServicesPath | ConvertFrom-Json
$pubspec = Read-Text $pubspecPath
$keyProps = Read-Properties $keyPropertiesPath

$applicationId = ([Regex]::Match($gradle, 'applicationId\s*=\s*"([^"]+)"')).Groups[1].Value
$namespace = ([Regex]::Match($gradle, 'namespace\s*=\s*"([^"]+)"')).Groups[1].Value
$pubspecVersion = ([Regex]::Match($pubspec, '(?m)^version:\s*([^\s]+)')).Groups[1].Value
$versionParts = $pubspecVersion -split '\+'
$versionName = $versionParts[0]
$versionCode = if ($versionParts.Count -gt 1) { $versionParts[1] } else { "" }
$firebasePackage = $googleServices.client[0].client_info.android_client_info.package_name
$firebaseAppId = $googleServices.client[0].client_info.mobilesdk_app_id
$firebaseProjectId = $googleServices.project_info.project_id

Add-Check "application_id_matches_expected" ($applicationId -eq $ExpectedPackageName) @{
  applicationId = $applicationId
  expected = $ExpectedPackageName
}
Add-Check "namespace_matches_application_id" ($namespace -eq $applicationId) @{
  namespace = $namespace
  applicationId = $applicationId
}
Add-Check "firebase_package_matches_application_id" ($firebasePackage -eq $applicationId) @{
  firebasePackage = $firebasePackage
  applicationId = $applicationId
}
Add-Check "firebase_project_present" ([bool]$firebaseProjectId) @{
  firebaseProjectId = $firebaseProjectId
  firebaseAppId = $firebaseAppId
}
Add-Check "pubspec_version_present" ([bool]$versionName -and [bool]$versionCode) @{
  version = $pubspecVersion
  versionName = $versionName
  versionCode = $versionCode
}

$distAab = if (Test-Path $distAabPath) { Get-Item $distAabPath } else { $null }
$buildAab = if (Test-Path $buildAabPath) { Get-Item $buildAabPath } else { $null }
$distSha = Get-Sha256 $distAabPath
$buildSha = Get-Sha256 $buildAabPath
Add-Check "dist_release_aab_exists" ($null -ne $distAab) @{
  path = Get-RelativeDisplayPath $distAabPath
}
Add-Check "dist_release_aab_size_plausible" ($null -ne $distAab -and $distAab.Length -gt 40MB) @{
  bytes = if ($distAab) { $distAab.Length } else { 0 }
}
Add-Check "build_release_aab_exists" ($null -ne $buildAab) @{
  path = Get-RelativeDisplayPath $buildAabPath
}
Add-Check "dist_aab_matches_build_output" ([bool]$distSha -and $distSha -eq $buildSha) @{
  distSha256 = $distSha
  buildSha256 = $buildSha
}

$latestSource = Get-LatestSourceMtime @(
  'apps\mobile\lib',
  'apps\mobile\android\app\build.gradle.kts',
  'apps\mobile\android\app\google-services.json',
  'apps\mobile\pubspec.yaml'
)
Add-Check "dist_aab_newer_than_app_sources" ($null -ne $distAab -and $distAab.LastWriteTimeUtc -ge $latestSource.lastWriteTimeUtc) @{
  aabLastWriteTimeUtc = if ($distAab) { $distAab.LastWriteTimeUtc.ToString("o") } else { "" }
  latestSource = $latestSource
}

$storeFileValue = if ($keyProps.ContainsKey('storeFile')) { $keyProps['storeFile'] } else { "" }
$keyAlias = if ($keyProps.ContainsKey('keyAlias')) { $keyProps['keyAlias'] } else { "" }
$keystorePath = if ($storeFileValue) {
  if ([System.IO.Path]::IsPathRooted($storeFileValue)) {
    $storeFileValue
  } else {
    Join-Path (Join-Path $repoRoot 'apps\mobile\android\app') $storeFileValue
  }
} else {
  ""
}

Add-Check "key_properties_exists" (Test-Path $keyPropertiesPath) @{
  path = Get-RelativeDisplayPath $keyPropertiesPath
}
Add-Check "release_keystore_exists" ($keystorePath -and (Test-Path $keystorePath)) @{
  storeFile = $storeFileValue
  resolvedPath = $keystorePath
}
Add-Check "release_key_alias_present" ([bool]$keyAlias) @{
  keyAlias = $keyAlias
}
Add-Check "release_passwords_configured" ($keyProps.ContainsKey('storePassword') -and $keyProps.ContainsKey('keyPassword')) @{
  storePasswordConfigured = $keyProps.ContainsKey('storePassword')
  keyPasswordConfigured = $keyProps.ContainsKey('keyPassword')
}
Add-Check "release_build_does_not_fallback_to_debug" ((Test-Path $keyPropertiesPath) -and $keystorePath -and (Test-Path $keystorePath)) @{
  keyProperties = Test-Path $keyPropertiesPath
  keystore = $keystorePath
}

$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
$keytoolPath = if ($keytoolCommand) { $keytoolCommand.Source } else { "" }
$fingerprints = @{}
if ($keytoolPath -and (Test-Path $keystorePath) -and $keyProps.ContainsKey('storePassword') -and $keyAlias) {
  try {
    $keytoolResult = Invoke-KeytoolList $keytoolPath $keystorePath $keyAlias $keyProps['storePassword']
    $sha1Match = [Regex]::Match($keytoolResult.output, 'SHA1:\s*([0-9A-Fa-f:]+)')
    $sha256Match = [Regex]::Match($keytoolResult.output, 'SHA256:\s*([0-9A-Fa-f:]+)')
    $sha1 = if ($sha1Match.Success) { $sha1Match.Groups[1].Value.Trim() } else { "" }
    $sha256 = if ($sha256Match.Success) { $sha256Match.Groups[1].Value.Trim() } else { "" }
    $fingerprints = @{
      sha1 = $sha1
      sha256 = $sha256
    }
    Add-Check "release_keystore_readable_by_keytool" ([bool]$sha256) @{
      keytool = $keytoolPath
      keyAlias = $keyAlias
      sha1 = $sha1
      sha256 = $sha256
    }
  } catch {
    Add-Check "release_keystore_readable_by_keytool" $false @{
      keytool = $keytoolPath
      keyAlias = $keyAlias
      error = $_.Exception.Message
    }
  }
} else {
  Add-Check "release_keystore_readable_by_keytool" $false @{
    keytool = $keytoolPath
    keyAlias = $keyAlias
  }
}

$failed = @($checks | Where-Object { -not $_.ok })
$result = [PSCustomObject]@{
  ok = ($failed.Count -eq 0)
  checkedAt = (Get-Date).ToString("o")
  expectedAppName = $ExpectedAppName
  expectedPackageName = $ExpectedPackageName
  android = [PSCustomObject]@{
    applicationId = $applicationId
    namespace = $namespace
    version = $pubspecVersion
    versionName = $versionName
    versionCode = $versionCode
  }
  firebase = [PSCustomObject]@{
    projectId = $firebaseProjectId
    appId = $firebaseAppId
    packageName = $firebasePackage
  }
  release = [PSCustomObject]@{
    distAab = Get-RelativeDisplayPath $distAabPath
    buildAab = Get-RelativeDisplayPath $buildAabPath
    sha256 = $distSha
    bytes = if ($distAab) { $distAab.Length } else { 0 }
    lastWriteTimeUtc = if ($distAab) { $distAab.LastWriteTimeUtc.ToString("o") } else { "" }
  }
  signing = [PSCustomObject]@{
    keyAlias = $keyAlias
    storeFile = $storeFileValue
    sha1 = $fingerprints.sha1
    sha256 = $fingerprints.sha256
  }
  checks = $checks
  failedCount = $failed.Count
  passedCount = $checks.Count - $failed.Count
  artifact = Get-RelativeDisplayPath $resultPath
}

$json = $result | ConvertTo-Json -Depth 12
$json | Set-Content -Encoding UTF8 -Path $resultPath
$json | Set-Content -Encoding UTF8 -Path $latestPath
Write-Output $json

if (-not $result.ok) {
  exit 1
}
