param(
  [string]$DownloadDir = "$env:USERPROFILE\Downloads"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$distLogo = Join-Path $repoRoot "dist\logo"
New-Item -ItemType Directory -Force -Path $distLogo | Out-Null
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

function New-RoundedRectPath {
  param([float]$X, [float]$Y, [float]$Width, [float]$Height, [float]$Radius)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $diameter = $Radius * 2
  $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
  $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
  $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

function New-Brush {
  param([string]$Color, [int]$Alpha = 255)
  $base = [System.Drawing.ColorTranslator]::FromHtml($Color)
  return New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($Alpha, $base.R, $base.G, $base.B))
}

function Save-NeonEchoLogo {
  param(
    [int]$Size,
    [string]$Path,
    [bool]$RoundedTransparent = $true
  )

  $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

  $logoBlack = [System.Drawing.ColorTranslator]::FromHtml("#111111")
  if ($RoundedTransparent) {
    $graphics.Clear([System.Drawing.Color]::Transparent)
  } else {
    $graphics.Clear($logoBlack)
  }

  $scale = $Size / 1024.0
  $backgroundBrush = New-Object System.Drawing.SolidBrush $logoBlack

  if ($RoundedTransparent) {
    $tile = New-RoundedRectPath 0 0 $Size $Size (236 * $scale)
    $graphics.FillPath($backgroundBrush, $tile)
    $tile.Dispose()
  } else {
    $graphics.FillRectangle($backgroundBrush, 0, 0, $Size, $Size)
  }
  $backgroundBrush.Dispose()

  $barBrush = New-Brush "#00F0A8"
  $centerX = 512 * $scale
  $centerY = 512 * $scale
  $barWidth = 68 * $scale
  $gap = 22 * $scale
  $heights = @(136, 248, 304, 248, 136)
  $totalWidth = ($heights.Count * $barWidth) + (($heights.Count - 1) * $gap)
  $x = $centerX - ($totalWidth / 2)
  foreach ($heightBase in $heights) {
    $height = $heightBase * $scale
    $bar = New-RoundedRectPath $x ($centerY - $height / 2) $barWidth $height ($barWidth / 2)
    $graphics.FillPath($barBrush, $bar)
    $bar.Dispose()
    $x += $barWidth + $gap
  }
  $barBrush.Dispose()

  $directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
}

function Copy-ResizedPng {
  param(
    [int]$Size,
    [string]$Path,
    [bool]$RoundedTransparent = $true
  )
  Save-NeonEchoLogo -Size $Size -Path $Path -RoundedTransparent $RoundedTransparent
}

function New-IcoFile {
  param(
    [int[]]$Sizes,
    [string]$Path
  )
  $pngEntries = @()
  foreach ($size in $Sizes) {
    $tempPath = Join-Path $env:TEMP "verbal-icon-$size.png"
    Save-NeonEchoLogo -Size $size -Path $tempPath -RoundedTransparent $true
    $bytes = [System.IO.File]::ReadAllBytes($tempPath)
    Remove-Item -LiteralPath $tempPath -Force
    $pngEntries += [pscustomobject]@{ Size = $size; Bytes = $bytes }
  }

  $stream = New-Object System.IO.MemoryStream
  $writer = New-Object System.IO.BinaryWriter $stream
  $writer.Write([UInt16]0)
  $writer.Write([UInt16]1)
  $writer.Write([UInt16]$pngEntries.Count)
  $offset = 6 + (16 * $pngEntries.Count)
  foreach ($entry in $pngEntries) {
    $dimensionByte = if ($entry.Size -ge 256) { 0 } else { [byte]$entry.Size }
    $writer.Write([byte]$dimensionByte)
    $writer.Write([byte]$dimensionByte)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$entry.Bytes.Length)
    $writer.Write([UInt32]$offset)
    $offset += $entry.Bytes.Length
  }
  foreach ($entry in $pngEntries) {
    $writer.Write($entry.Bytes)
  }
  [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
  $writer.Dispose()
  $stream.Dispose()
}

$highResRounded = Join-Path $distLogo "verbal-app-logo-neon-echo-4096-rounded.png"
$highResSquare = Join-Path $distLogo "verbal-app-logo-neon-echo-4096-square.png"
Save-NeonEchoLogo -Size 4096 -Path $highResRounded -RoundedTransparent $true
Save-NeonEchoLogo -Size 4096 -Path $highResSquare -RoundedTransparent $false
Copy-Item -LiteralPath $highResRounded -Destination (Join-Path $DownloadDir "verbal-app-logo-neon-echo-4096-rounded.png") -Force
Copy-Item -LiteralPath $highResSquare -Destination (Join-Path $DownloadDir "verbal-app-logo-neon-echo-4096-square.png") -Force

$androidRoot = Join-Path $repoRoot "apps\mobile\android\app\src\main\res"
$androidIcons = @{
  "mipmap-mdpi\ic_launcher.png" = 48
  "mipmap-hdpi\ic_launcher.png" = 72
  "mipmap-xhdpi\ic_launcher.png" = 96
  "mipmap-xxhdpi\ic_launcher.png" = 144
  "mipmap-xxxhdpi\ic_launcher.png" = 192
}
foreach ($relativePath in $androidIcons.Keys) {
  Copy-ResizedPng -Size $androidIcons[$relativePath] -Path (Join-Path $androidRoot $relativePath) -RoundedTransparent $false
}

$iosRoot = Join-Path $repoRoot "apps\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset"
$iosContentsPath = Join-Path $iosRoot "Contents.json"
$iosContents = Get-Content -Raw $iosContentsPath | ConvertFrom-Json
foreach ($image in $iosContents.images) {
  if (-not $image.filename) {
    continue
  }
  $pointSize = [double]($image.size -replace "x.*$", "")
  $scale = [double]($image.scale -replace "x", "")
  $pixelSize = [int][Math]::Round($pointSize * $scale)
  Copy-ResizedPng -Size $pixelSize -Path (Join-Path $iosRoot $image.filename) -RoundedTransparent $false
}

$webRoot = Join-Path $repoRoot "apps\mobile\web"
Copy-ResizedPng -Size 32 -Path (Join-Path $webRoot "favicon.png") -RoundedTransparent $true
Copy-ResizedPng -Size 192 -Path (Join-Path $webRoot "icons\Icon-192.png") -RoundedTransparent $false
Copy-ResizedPng -Size 512 -Path (Join-Path $webRoot "icons\Icon-512.png") -RoundedTransparent $false
Copy-ResizedPng -Size 192 -Path (Join-Path $webRoot "icons\Icon-maskable-192.png") -RoundedTransparent $false
Copy-ResizedPng -Size 512 -Path (Join-Path $webRoot "icons\Icon-maskable-512.png") -RoundedTransparent $false

$windowsIconPath = Join-Path $repoRoot "apps\mobile\windows\runner\resources\app_icon.ico"
New-IcoFile -Sizes @(16, 32, 48, 64, 128, 256) -Path $windowsIconPath

Copy-ResizedPng -Size 1024 -Path (Join-Path $repoRoot "artifacts\logo-concepts-pictorial\verbal-pictorial-09-neon-echo.png") -RoundedTransparent $true

[pscustomobject]@{
  HighResRounded = $highResRounded
  HighResSquare = $highResSquare
  DownloadRounded = Join-Path $DownloadDir "verbal-app-logo-neon-echo-4096-rounded.png"
  DownloadSquare = Join-Path $DownloadDir "verbal-app-logo-neon-echo-4096-square.png"
  AndroidIcons = $androidIcons.Count
  IosIcons = ($iosContents.images | Where-Object { $_.filename }).Count
  WebIcons = 5
  WindowsIcon = $windowsIconPath
} | Format-List
