param(
  [string]$OutDir = "artifacts/store/google-play/assets"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$output = Join-Path $root $OutDir
$screenshots = Join-Path $output "phone-screenshots"
New-Item -ItemType Directory -Force -Path $output | Out-Null
New-Item -ItemType Directory -Force -Path $screenshots | Out-Null

function Get-AssetPath {
  param([string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    $fullPath = Join-Path $root $candidate
    if (Test-Path $fullPath) {
      return (Resolve-Path $fullPath).Path
    }
  }
  throw "None of the candidate files exists: $($Candidates -join ', ')"
}

function New-Canvas {
  param([int]$Width, [int]$Height)
  $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  return @($bitmap, $graphics)
}

function Save-Png {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [string]$Path
  )
  $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Resize-Image {
  param(
    [string]$Source,
    [string]$Destination,
    [int]$Width,
    [int]$Height
  )
  $sourceImage = [System.Drawing.Image]::FromFile($Source)
  $canvas = New-Canvas $Width $Height
  $bitmap = $canvas[0]
  $graphics = $canvas[1]
  $graphics.DrawImage($sourceImage, 0, 0, $Width, $Height)
  Save-Png $bitmap $Destination
  $graphics.Dispose()
  $bitmap.Dispose()
  $sourceImage.Dispose()
}

function Crop-ImageToAspect {
  param(
    [string]$Source,
    [string]$Destination,
    [int]$Width = 1080,
    [int]$Height = 1920
  )
  $sourceImage = [System.Drawing.Image]::FromFile($Source)
  $targetAspect = $Width / $Height
  $sourceAspect = $sourceImage.Width / $sourceImage.Height

  if ($sourceAspect -gt $targetAspect) {
    $cropHeight = $sourceImage.Height
    $cropWidth = [int]($cropHeight * $targetAspect)
  } else {
    $cropWidth = $sourceImage.Width
    $cropHeight = [int]($cropWidth / $targetAspect)
  }

  $cropX = [int](($sourceImage.Width - $cropWidth) / 2)
  $cropY = [int](($sourceImage.Height - $cropHeight) / 2)
  $sourceRect = New-Object System.Drawing.Rectangle $cropX, $cropY, $cropWidth, $cropHeight
  $destRect = New-Object System.Drawing.Rectangle 0, 0, $Width, $Height

  $canvas = New-Canvas $Width $Height
  $bitmap = $canvas[0]
  $graphics = $canvas[1]
  $graphics.DrawImage($sourceImage, $destRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
  Save-Png $bitmap $Destination
  $graphics.Dispose()
  $bitmap.Dispose()
  $sourceImage.Dispose()
}

function New-FeatureGraphic {
  param(
    [string]$LogoSource,
    [string]$Destination
  )

  $canvas = New-Canvas 1024 500
  $bitmap = $canvas[0]
  $graphics = $canvas[1]
  $rect = New-Object System.Drawing.Rectangle 0, 0, 1024, 500
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.ColorTranslator]::FromHtml("#08110D")), ([System.Drawing.ColorTranslator]::FromHtml("#00A86B")), 24
  $graphics.FillRectangle($brush, $rect)

  $soft = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(34, 255, 255, 255))
  $graphics.FillEllipse($soft, 650, -160, 520, 520)
  $graphics.FillEllipse($soft, -170, 280, 420, 420)
  $soft.Dispose()

  $logo = [System.Drawing.Image]::FromFile($LogoSource)
  $graphics.DrawImage($logo, 86, 140, 220, 220)

  $titleFont = New-Object System.Drawing.Font "Segoe UI", 76, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $copyFont = New-Object System.Drawing.Font "Malgun Gothic", 30, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $white = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#FFFFFF"))
  $muted = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(226, 247, 247, 248))
  $graphics.DrawString("Verbal", $titleFont, $white, 350, 142)
  $graphics.DrawString("음성을 바로 텍스트로 바꾸는 메신저", $copyFont, $muted, 356, 238)

  $wavePen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml("#44F6A2")), 16
  $wavePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $wavePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $x = 358
  foreach ($height in @(34, 68, 98, 68, 34)) {
    $y1 = 338 - ($height / 2)
    $y2 = 338 + ($height / 2)
    $graphics.DrawLine($wavePen, $x, $y1, $x, $y2)
    $x += 30
  }

  Save-Png $bitmap $Destination
  $wavePen.Dispose()
  $muted.Dispose()
  $white.Dispose()
  $copyFont.Dispose()
  $titleFont.Dispose()
  $logo.Dispose()
  $brush.Dispose()
  $graphics.Dispose()
  $bitmap.Dispose()
}

$logoSource = Get-AssetPath @(
  "dist/logo/verbal-app-logo-neon-echo-4096-square.png",
  "dist/logo/verbal-app-logo-neon-echo-4096-rounded.png"
)

$iconPath = Join-Path $output "app-icon-512.png"
$featurePath = Join-Path $output "feature-graphic-1024x500.png"
Resize-Image $logoSource $iconPath 512 512
New-FeatureGraphic $logoSource $featurePath

$screenSources = @(
  @{
    Name = "01-home.png"
    Sources = @("artifacts/runtime/verbal_black_home_final.png", "artifacts/device_home_after_login.png")
  },
  @{
    Name = "02-voice-chat.png"
    Sources = @("artifacts/final_voice_stt_success_latest.png", "artifacts/stt-test/screen-chat.png")
  },
  @{
    Name = "03-calendar.png"
    Sources = @("artifacts/calendar-monthly-ui-final.png", "artifacts/current-calendar-preview.png")
  },
  @{
    Name = "04-create-chat.png"
    Sources = @("artifacts/device_normal_chat_picker.png", "artifacts/device_contacts_sheet.png")
  },
  @{
    Name = "05-settings-menu.png"
    Sources = @("artifacts/ui-home-menu-sheet-check.png", "artifacts/device_menu_sheet.png")
  }
)

$generatedScreenshots = @()
foreach ($item in $screenSources) {
  $source = Get-AssetPath $item.Sources
  $destination = Join-Path $screenshots $item.Name
  Crop-ImageToAspect $source $destination 1080 1920
  $generatedScreenshots += (Resolve-Path $destination).Path
}

$manifest = @{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  appIcon = (Resolve-Path $iconPath).Path.Replace($root.Path + "\", "")
  featureGraphic = (Resolve-Path $featurePath).Path.Replace($root.Path + "\", "")
  phoneScreenshots = @($generatedScreenshots | ForEach-Object { $_.Replace($root.Path + "\", "") })
  notes = @(
    "App icon is 512x512 PNG.",
    "Feature graphic is 1024x500 PNG.",
    "Phone screenshots are 1080x1920 PNG crops prepared for Play Console internal testing."
  )
}

$manifestPath = Join-Path $output "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $manifestPath
Write-Output ($manifest | ConvertTo-Json -Depth 5)
