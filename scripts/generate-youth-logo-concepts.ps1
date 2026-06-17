param(
  [string]$OutDir = "artifacts/logo-concepts-youth"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$output = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $output | Out-Null

function New-Canvas {
  $bitmap = New-Object System.Drawing.Bitmap 1024, 1024
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  return @($bitmap, $graphics)
}

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

function New-Pen {
  param([string]$Color, [float]$Width, [int]$Alpha = 255)
  $base = [System.Drawing.ColorTranslator]::FromHtml($Color)
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($Alpha, $base.R, $base.G, $base.B)), $Width
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  return $pen
}

function New-Brush {
  param([string]$Color, [int]$Alpha = 255)
  $base = [System.Drawing.ColorTranslator]::FromHtml($Color)
  return New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($Alpha, $base.R, $base.G, $base.B))
}

function Draw-AppTile {
  param(
    [System.Drawing.Graphics]$Graphics,
    [string]$Start,
    [string]$Middle,
    [string]$End
  )
  $path = New-RoundedRectPath 0 0 1024 1024 236
  $rect = New-Object System.Drawing.Rectangle 0, 0, 1024, 1024
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.ColorTranslator]::FromHtml($Start)), ([System.Drawing.ColorTranslator]::FromHtml($End)), 45
  $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
  $blend.Positions = [single[]](0, 0.52, 1)
  $blend.Colors = [System.Drawing.Color[]](([System.Drawing.ColorTranslator]::FromHtml($Start)), ([System.Drawing.ColorTranslator]::FromHtml($Middle)), ([System.Drawing.ColorTranslator]::FromHtml($End)))
  $brush.InterpolationColors = $blend
  $Graphics.FillPath($brush, $path)
  $shine = New-Brush "#FFFFFF" 38
  $Graphics.FillEllipse($shine, 112, 70, 460, 310)
  $shine.Dispose()
  $brush.Dispose()
  $path.Dispose()
}

function Draw-V {
  param(
    [System.Drawing.Graphics]$Graphics,
    [string]$Color = "#FFFFFF",
    [float]$Width = 118,
    [float]$TopY = 292,
    [float]$BottomY = 738,
    [float]$LeftX = 320,
    [float]$RightX = 704,
    [int]$Alpha = 255
  )
  $pen = New-Pen $Color $Width $Alpha
  $points = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF $LeftX, $TopY),
    (New-Object System.Drawing.PointF 512, $BottomY),
    (New-Object System.Drawing.PointF $RightX, $TopY)
  )
  $Graphics.DrawLines($pen, $points)
  $pen.Dispose()
}

function Draw-SpeechBubble {
  param([System.Drawing.Graphics]$Graphics, [float]$X, [float]$Y, [float]$W, [float]$H, [string]$Color, [int]$Alpha = 255)
  $brush = New-Brush $Color $Alpha
  $path = New-RoundedRectPath $X $Y $W $H 90
  $Graphics.FillPath($brush, $path)
  $tail = New-Object System.Drawing.Drawing2D.GraphicsPath
  $tail.AddPolygon([System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF ($X + $W * 0.24), ($Y + $H - 28)),
    (New-Object System.Drawing.PointF ($X + $W * 0.14), ($Y + $H + 96)),
    (New-Object System.Drawing.PointF ($X + $W * 0.42), ($Y + $H - 18))
  ))
  $Graphics.FillPath($brush, $tail)
  $tail.Dispose()
  $path.Dispose()
  $brush.Dispose()
}

function Draw-Waves {
  param([System.Drawing.Graphics]$Graphics, [string]$Color = "#FFFFFF", [int]$Alpha = 255, [float]$Y = 512)
  $pen = New-Pen $Color 30 $Alpha
  $Graphics.DrawLine($pen, 274, $Y, 308, $Y)
  $Graphics.DrawLine($pen, 236, $Y - 74, 282, $Y - 74)
  $Graphics.DrawLine($pen, 236, $Y + 74, 282, $Y + 74)
  $Graphics.DrawLine($pen, 716, $Y, 750, $Y)
  $Graphics.DrawLine($pen, 742, $Y - 74, 788, $Y - 74)
  $Graphics.DrawLine($pen, 742, $Y + 74, 788, $Y + 74)
  $pen.Dispose()
}

function Draw-Bars {
  param([System.Drawing.Graphics]$Graphics, [string]$Color, [int]$Alpha, [int[]]$Heights)
  $brush = New-Brush $Color $Alpha
  $x = 354
  foreach ($height in $Heights) {
    $path = New-RoundedRectPath $x (512 - $height / 2) 36 $height 18
    $Graphics.FillPath($brush, $path)
    $path.Dispose()
    $x += 58
  }
  $brush.Dispose()
}

function Save-Logo {
  param([System.Drawing.Bitmap]$Bitmap, [System.Drawing.Graphics]$Graphics, [string]$Name)
  $Graphics.Dispose()
  $path = Join-Path $output "$Name.png"
  $Bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $Bitmap.Dispose()
}

$concepts = @(
  @{ Name = "verbal-youth-01-bubble-pop"; Title = "Bubble Pop"; A = "#28F0B2"; B = "#11C8F2"; C = "#635BFF"; Color = "#11C8F2" },
  @{ Name = "verbal-youth-02-lime-chat"; Title = "Lime Chat"; A = "#B7FF3C"; B = "#23E66F"; C = "#00A86B"; Color = "#23E66F" },
  @{ Name = "verbal-youth-03-pink-mic"; Title = "Pink Mic"; A = "#FF6AD5"; B = "#FF2F88"; C = "#7B2CFF"; Color = "#FF2F88" },
  @{ Name = "verbal-youth-04-blue-pulse"; Title = "Blue Pulse"; A = "#24D8FF"; B = "#0A7CFF"; C = "#5C4DFF"; Color = "#0A7CFF" },
  @{ Name = "verbal-youth-05-yellow-voice"; Title = "Yellow Voice"; A = "#FFF24B"; B = "#FFB000"; C = "#FF6B00"; Color = "#FFB000" },
  @{ Name = "verbal-youth-06-purple-bubble"; Title = "Purple Bubble"; A = "#C66BFF"; B = "#8B5CFF"; C = "#32D6FF"; Color = "#8B5CFF" },
  @{ Name = "verbal-youth-07-coral-send"; Title = "Coral Send"; A = "#FF7A59"; B = "#FF3D6E"; C = "#FFB23F"; Color = "#FF3D6E" },
  @{ Name = "verbal-youth-08-sky-signal"; Title = "Sky Signal"; A = "#52F2FF"; B = "#17B7FF"; C = "#0570FF"; Color = "#17B7FF" },
  @{ Name = "verbal-youth-09-neon-night"; Title = "Neon Night"; A = "#24272F"; B = "#101318"; C = "#020307"; Color = "#101318" },
  @{ Name = "verbal-youth-10-mint-sticker"; Title = "Mint Sticker"; A = "#E8FFF2"; B = "#45F0A8"; C = "#00B96B"; Color = "#45F0A8" }
)

for ($i = 0; $i -lt $concepts.Count; $i++) {
  $c = $concepts[$i]
  $canvas = New-Canvas
  $bitmap = $canvas[0]
  $graphics = $canvas[1]
  Draw-AppTile $graphics $c.A $c.B $c.C

  switch ($i) {
    0 {
      Draw-SpeechBubble $graphics 228 266 568 420 "#FFFFFF" 46
      Draw-V $graphics "#FFFFFF" 112 312 742 316 708
      Draw-Bars $graphics "#08A880" 255 @(76, 142, 218, 142, 76)
      $dot = New-Brush "#FF4FD8"; $graphics.FillEllipse($dot, 724, 662, 88, 88); $dot.Dispose()
    }
    1 {
      Draw-SpeechBubble $graphics 252 292 520 362 "#FFFFFF" 58
      Draw-V $graphics "#FFFFFF" 124 284 748 324 700
      Draw-Waves $graphics "#008E61" 255 514
      $heart = New-Brush "#FFFFFF"; $graphics.FillEllipse($heart, 718, 678, 70, 70); $heart.Dispose()
    }
    2 {
      Draw-V $graphics "#FFFFFF" 128 286 756 304 720
      $body = New-Brush "#B81274"; $graphics.FillPath($body, (New-RoundedRectPath 448 276 128 330 64)); $body.Dispose()
      $mic = New-Brush "#FFFFFF"; $graphics.FillPath($mic, (New-RoundedRectPath 476 222 72 388 36)); $mic.Dispose()
      $arc = New-Pen "#FFFFFF" 34 255; $graphics.DrawArc($arc, 392, 390, 240, 240, 0, 180); $graphics.DrawLine($arc, 512, 630, 512, 706); $arc.Dispose()
    }
    3 {
      Draw-V $graphics "#FFFFFF" 126 292 750 300 724
      $pulse = New-Pen "#001F8F" 30 205
      $graphics.DrawLines($pulse, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF 300, 512),
        (New-Object System.Drawing.PointF 376, 512),
        (New-Object System.Drawing.PointF 420, 424),
        (New-Object System.Drawing.PointF 484, 624),
        (New-Object System.Drawing.PointF 560, 392),
        (New-Object System.Drawing.PointF 628, 512),
        (New-Object System.Drawing.PointF 724, 512)
      ))
      $pulse.Dispose()
    }
    4 {
      Draw-V $graphics "#FFFFFF" 126 314 748 306 718
      Draw-Bars $graphics "#FF6B00" 230 @(56, 132, 230, 132, 56)
      $spark = New-Brush "#FFFFFF"; $graphics.FillEllipse($spark, 706, 268, 76, 76); $spark.Dispose()
    }
    5 {
      Draw-SpeechBubble $graphics 244 276 536 384 "#FFFFFF" 60
      Draw-V $graphics "#FFFFFF" 122 294 742 314 710
      Draw-Waves $graphics "#3C1BA8" 220 510
      $mini = New-Brush "#FFFFFF"; $graphics.FillEllipse($mini, 700, 694, 84, 84); $mini.Dispose()
    }
    6 {
      Draw-V $graphics "#FFFFFF" 122 298 746 310 714
      $send = New-Object System.Drawing.Drawing2D.GraphicsPath
      $send.AddPolygon([System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF 360, 530),
        (New-Object System.Drawing.PointF 694, 392),
        (New-Object System.Drawing.PointF 552, 708)
      ))
      $sendBrush = New-Brush "#FFFFFF" 64; $graphics.FillPath($sendBrush, $send); $sendBrush.Dispose(); $send.Dispose()
      $line = New-Pen "#B6174D" 30 210; $graphics.DrawLine($line, 388, 532, 576, 540); $line.Dispose()
    }
    7 {
      Draw-V $graphics "#FFFFFF" 126 306 752 304 720
      $ring = New-Pen "#FFFFFF" 26 92
      $graphics.DrawEllipse($ring, 236, 236, 552, 552)
      $graphics.DrawEllipse($ring, 308, 308, 408, 408)
      $ring.Dispose()
      Draw-Bars $graphics "#005BEA" 225 @(86, 180, 254, 180, 86)
    }
    8 {
      Draw-V $graphics "#FFFFFF" 124 294 744 310 714
      Draw-Bars $graphics "#00F0A8" 255 @(70, 150, 236, 150, 70)
      $pink = New-Pen "#FF47D6" 26 255; $graphics.DrawArc($pink, 218, 230, 588, 588, 205, 130); $pink.Dispose()
      $cyan = New-Brush "#2EF2FF"; $graphics.FillEllipse($cyan, 706, 672, 78, 78); $cyan.Dispose()
    }
    9 {
      $cloud = New-Brush "#FFFFFF" 72
      $graphics.FillEllipse($cloud, 234, 254, 560, 460)
      $cloud.Dispose()
      Draw-V $graphics "#FFFFFF" 124 292 744 310 714
      Draw-Waves $graphics "#00A86B" 225 514
      $sticker = New-Pen "#FFFFFF" 34 255; $graphics.DrawArc($sticker, 240, 236, 550, 550, 28, 124); $sticker.Dispose()
    }
  }

  Save-Logo $bitmap $graphics $c.Name
}

$previewWidth = 1640
$previewHeight = 980
$preview = New-Object System.Drawing.Bitmap $previewWidth, $previewHeight
$g = [System.Drawing.Graphics]::FromImage($preview)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.ColorTranslator]::FromHtml("#F7FAFC"))
$titleFont = New-Object System.Drawing.Font "Arial", 28, ([System.Drawing.FontStyle]::Bold)
$subFont = New-Object System.Drawing.Font "Arial", 14, ([System.Drawing.FontStyle]::Regular)
$labelFont = New-Object System.Drawing.Font "Arial", 13, ([System.Drawing.FontStyle]::Bold)
$bodyFont = New-Object System.Drawing.Font "Arial", 12, ([System.Drawing.FontStyle]::Regular)
$dark = New-Brush "#101318"
$gray = New-Brush "#65736D"
$card = New-Brush "#FFFFFF"
$shadow = New-Brush "#003C26" 20
$g.DrawString("Verbal youth logo concepts", $titleFont, $dark, 40, 30)
$g.DrawString("Rounded, bright, social-app style icons for teens and twenties.", $subFont, $gray, 42, 72)

for ($i = 0; $i -lt $concepts.Count; $i++) {
  $row = [Math]::Floor($i / 5)
  $col = $i % 5
  $x = 40 + $col * 315
  $y = 120 + $row * 410
  $sp = New-RoundedRectPath ($x + 4) ($y + 10) 274 350 28
  $g.FillPath($shadow, $sp)
  $sp.Dispose()
  $cp = New-RoundedRectPath $x $y 274 350 28
  $g.FillPath($card, $cp)
  $cp.Dispose()
  $img = [System.Drawing.Image]::FromFile((Join-Path $output "$($concepts[$i].Name).png"))
  $g.DrawImage($img, $x + 28, $y + 24, 218, 218)
  $img.Dispose()
  $g.DrawString(("{0:D2} {1}" -f ($i + 1), $concepts[$i].Title), $labelFont, $dark, $x + 24, $y + 268)
  $g.DrawString("V + voice/chat mark", $bodyFont, $gray, $x + 24, $y + 298)
}

$previewPath = Join-Path $output "preview-youth.png"
$preview.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$preview.Dispose()
$titleFont.Dispose()
$subFont.Dispose()
$labelFont.Dispose()
$bodyFont.Dispose()
$dark.Dispose()
$gray.Dispose()
$card.Dispose()
$shadow.Dispose()

$readme = @"
# Verbal Youth Logo Concepts

Rounded, young, trendy app logo candidates inspired by the visual grammar of social app icons.

Requirements:
- Rounded square app-icon silhouette.
- Youthful 10s-20s mood: bright color, simple mark, easy recognition.
- V remains the core design base.
- Voice-message messenger signal through waveform, microphone, speech bubble, pulse, send, or signal motifs.

Generated assets:
- verbal-youth-01-bubble-pop.png
- verbal-youth-02-lime-chat.png
- verbal-youth-03-pink-mic.png
- verbal-youth-04-blue-pulse.png
- verbal-youth-05-yellow-voice.png
- verbal-youth-06-purple-bubble.png
- verbal-youth-07-coral-send.png
- verbal-youth-08-sky-signal.png
- verbal-youth-09-neon-night.png
- verbal-youth-10-mint-sticker.png

Preview:
- preview-youth.png
"@
[System.IO.File]::WriteAllText((Join-Path $output "README.md"), $readme, [System.Text.UTF8Encoding]::new($false))

Get-ChildItem $output -Filter "*.png" | Sort-Object Name | Select-Object Name, Length
