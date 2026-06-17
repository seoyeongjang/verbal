param(
  [string]$OutDir = "artifacts/logo-concepts-pictorial"
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

function RoundedPath {
  param([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R)
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $R * 2
  $p.AddArc($X, $Y, $d, $d, 180, 90)
  $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
  $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
  $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Brush {
  param([string]$Color, [int]$Alpha = 255)
  $c = [System.Drawing.ColorTranslator]::FromHtml($Color)
  return New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($Alpha, $c.R, $c.G, $c.B))
}

function Pen {
  param([string]$Color, [float]$Width, [int]$Alpha = 255)
  $c = [System.Drawing.ColorTranslator]::FromHtml($Color)
  $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($Alpha, $c.R, $c.G, $c.B)), $Width
  $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  return $p
}

function DrawTile {
  param([System.Drawing.Graphics]$G, [string]$A, [string]$B, [string]$C)
  $rect = New-Object System.Drawing.Rectangle 0, 0, 1024, 1024
  $path = RoundedPath 0 0 1024 1024 236
  $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.ColorTranslator]::FromHtml($A)), ([System.Drawing.ColorTranslator]::FromHtml($C)), 45
  $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
  $blend.Positions = [single[]](0, 0.55, 1)
  $blend.Colors = [System.Drawing.Color[]](([System.Drawing.ColorTranslator]::FromHtml($A)), ([System.Drawing.ColorTranslator]::FromHtml($B)), ([System.Drawing.ColorTranslator]::FromHtml($C)))
  $grad.InterpolationColors = $blend
  $G.FillPath($grad, $path)
  $grad.Dispose()
  $path.Dispose()
}

function DrawBars {
  param([System.Drawing.Graphics]$G, [float]$CenterX, [float]$CenterY, [int[]]$Heights, [string]$Color, [int]$Alpha = 255, [float]$BarW = 34, [float]$Gap = 22)
  $b = Brush $Color $Alpha
  $total = $Heights.Count * $BarW + ($Heights.Count - 1) * $Gap
  $x = $CenterX - $total / 2
  foreach ($h in $Heights) {
    $path = RoundedPath $x ($CenterY - $h / 2) $BarW $h ($BarW / 2)
    $G.FillPath($b, $path)
    $path.Dispose()
    $x += $BarW + $Gap
  }
  $b.Dispose()
}

function DrawBubble {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [float]$W, [float]$H, [string]$Color, [int]$Alpha = 255)
  $b = Brush $Color $Alpha
  $path = RoundedPath $X $Y $W $H 112
  $G.FillPath($b, $path)
  $tail = New-Object System.Drawing.Drawing2D.GraphicsPath
  $tail.AddPolygon([System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF ($X + $W * 0.22), ($Y + $H - 36)),
    (New-Object System.Drawing.PointF ($X + $W * 0.14), ($Y + $H + 116)),
    (New-Object System.Drawing.PointF ($X + $W * 0.44), ($Y + $H - 20))
  ))
  $G.FillPath($b, $tail)
  $tail.Dispose()
  $path.Dispose()
  $b.Dispose()
}

function SaveConcept {
  param([System.Drawing.Bitmap]$Bitmap, [System.Drawing.Graphics]$G, [string]$Name)
  $G.Dispose()
  $path = Join-Path $output "$Name.png"
  $Bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $Bitmap.Dispose()
}

$concepts = @(
  @{ Name = "verbal-pictorial-01-voice-wing"; Title = "Voice Wing"; A = "#7DF9FF"; B = "#14B8FF"; C = "#647BFF" },
  @{ Name = "verbal-pictorial-02-chat-splash"; Title = "Chat Splash"; A = "#7CFFB2"; B = "#00D084"; C = "#00A1FF" },
  @{ Name = "verbal-pictorial-03-echo-drop"; Title = "Echo Drop"; A = "#FF85D5"; B = "#FF3A8B"; C = "#8B5CFF" },
  @{ Name = "verbal-pictorial-04-sound-comet"; Title = "Sound Comet"; A = "#FFF06A"; B = "#FFB000"; C = "#FF6B00" },
  @{ Name = "verbal-pictorial-05-talk-spark"; Title = "Talk Spark"; A = "#B066FF"; B = "#715CFF"; C = "#22D3EE" },
  @{ Name = "verbal-pictorial-06-headset-bubble"; Title = "Headset Bubble"; A = "#31F7C5"; B = "#00B96B"; C = "#006BFF" },
  @{ Name = "verbal-pictorial-07-signal-pebble"; Title = "Signal Pebble"; A = "#FF8A66"; B = "#FF3E70"; C = "#FFB347" },
  @{ Name = "verbal-pictorial-08-ribbon-wave"; Title = "Ribbon Wave"; A = "#47F1FF"; B = "#0B9BFF"; C = "#4E5BFF" },
  @{ Name = "verbal-pictorial-09-neon-echo"; Title = "Neon Echo"; A = "#252936"; B = "#10131A"; C = "#05070A" },
  @{ Name = "verbal-pictorial-10-orbit-chat"; Title = "Orbit Chat"; A = "#E8FFF2"; B = "#4BF0A7"; C = "#00B070" }
)

for ($i = 0; $i -lt $concepts.Count; $i++) {
  $c = $concepts[$i]
  $canvas = New-Canvas
  $bmp = $canvas[0]
  $g = $canvas[1]
  DrawTile $g $c.A $c.B $c.C

  switch ($i) {
    0 {
      $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
      $shape.AddBezier(282, 594, 394, 246, 672, 238, 762, 448)
      $shape.AddBezier(762, 448, 662, 430, 540, 478, 426, 610)
      $shape.AddBezier(426, 610, 520, 616, 616, 662, 694, 750)
      $shape.AddBezier(694, 750, 542, 724, 376, 674, 282, 594)
      $white = Brush "#FFFFFF"; $g.FillPath($white, $shape); $white.Dispose(); $shape.Dispose()
      DrawBars $g 504 522 @(72, 132, 206, 132, 72) "#00A18C" 255 30 18
    }
    1 {
      DrawBubble $g 228 286 566 398 "#FFFFFF" 235
      DrawBars $g 512 504 @(68, 126, 198, 126, 68) "#00A86B" 255 34 22
      $drop = Brush "#10B7FF"; $g.FillEllipse($drop, 692, 620, 92, 92); $drop.Dispose()
    }
    2 {
      $drop = New-Object System.Drawing.Drawing2D.GraphicsPath
      $drop.AddBezier(512, 238, 712, 400, 726, 584, 512, 782)
      $drop.AddBezier(298, 584, 312, 400, 512, 238, 512, 238)
      $drop.CloseFigure()
      $white = Brush "#FFFFFF"; $g.FillPath($white, $drop); $white.Dispose(); $drop.Dispose()
      $p1 = Pen "#FF3A8B" 28 230; $g.DrawArc($p1, 382, 394, 260, 260, 205, 130); $g.DrawArc($p1, 318, 330, 388, 388, 205, 130); $p1.Dispose()
      DrawBars $g 512 514 @(70, 150, 220, 150, 70) "#8B2CFF" 230 28 20
    }
    3 {
      $comet = New-Object System.Drawing.Drawing2D.GraphicsPath
      $comet.AddBezier(276, 590, 398, 248, 766, 284, 748, 520)
      $comet.AddBezier(748, 520, 736, 686, 546, 796, 366, 668)
      $comet.AddBezier(366, 668, 462, 646, 548, 596, 612, 508)
      $comet.AddBezier(612, 508, 494, 538, 390, 568, 276, 590)
      $white = Brush "#FFFFFF"; $g.FillPath($white, $comet); $white.Dispose(); $comet.Dispose()
      $tail = Pen "#FF6B00" 34 220; $g.DrawLine($tail, 272, 418, 418, 462); $g.DrawLine($tail, 248, 520, 390, 528); $g.DrawLine($tail, 284, 628, 420, 594); $tail.Dispose()
    }
    4 {
      DrawBubble $g 246 286 532 380 "#FFFFFF" 238
      $spark = Pen "#715CFF" 34 230; $g.DrawLine($spark, 512, 358, 512, 470); $g.DrawLine($spark, 456, 414, 568, 414)
      $spark.Dispose()
      DrawBars $g 512 552 @(58, 108, 164, 108, 58) "#7B45FF" 240 30 20
      $dot = Brush "#22D3EE"; $g.FillEllipse($dot, 700, 660, 78, 78); $dot.Dispose()
    }
    5 {
      $circle = Brush "#FFFFFF" 235; $g.FillEllipse($circle, 246, 246, 532, 532); $circle.Dispose()
      $hp = Pen "#00A86B" 42 250; $g.DrawArc($hp, 330, 346, 364, 312, 200, 140); $g.DrawLine($hp, 338, 522, 338, 628); $g.DrawLine($hp, 686, 522, 686, 628); $hp.Dispose()
      DrawBars $g 512 576 @(64, 120, 188, 120, 64) "#006BFF" 220 30 18
    }
    6 {
      $pebble = Brush "#FFFFFF" 238
      $g.FillPath($pebble, (RoundedPath 268 332 488 360 180))
      $pebble.Dispose()
      $arc = Pen "#FF3E70" 34 235; $g.DrawArc($arc, 326, 378, 360, 260, 205, 130); $g.DrawArc($arc, 398, 430, 216, 160, 205, 130); $arc.Dispose()
      DrawBars $g 512 512 @(60, 120, 190, 120, 60) "#FF7A36" 230 28 18
    }
    7 {
      $ribbon = New-Object System.Drawing.Drawing2D.GraphicsPath
      $ribbon.AddBezier(226, 542, 348, 320, 520, 322, 794, 456)
      $ribbon.AddBezier(794, 456, 646, 470, 530, 558, 414, 742)
      $ribbon.AddBezier(414, 742, 394, 634, 318, 574, 226, 542)
      $white = Brush "#FFFFFF"; $g.FillPath($white, $ribbon); $white.Dispose(); $ribbon.Dispose()
      DrawBars $g 514 522 @(62, 144, 230, 144, 62) "#0B63FF" 220 30 20
      $p = Pen "#FFFFFF" 32 120; $g.DrawArc($p, 278, 262, 468, 468, 205, 130); $p.Dispose()
    }
    8 {
      DrawBars $g 512 512 @(136, 248, 304, 248, 136) "#00F0A8" 255 68 22
    }
    9 {
      DrawBubble $g 250 282 526 392 "#FFFFFF" 210
      $orbit = Pen "#FFFFFF" 238; $g.DrawArc($orbit, 292, 332, 440, 344, 26, 128); $orbit.Dispose()
      DrawBars $g 512 516 @(62, 132, 204, 132, 62) "#00A86B" 245 32 20
      $dot = Brush "#FFFFFF"; $g.FillEllipse($dot, 706, 620, 76, 76); $dot.Dispose()
    }
  }

  SaveConcept $bmp $g $c.Name
}

$preview = New-Object System.Drawing.Bitmap 1640, 980
$pg = [System.Drawing.Graphics]::FromImage($preview)
$pg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$pg.Clear([System.Drawing.ColorTranslator]::FromHtml("#F7FAFC"))
$titleFont = New-Object System.Drawing.Font "Arial", 28, ([System.Drawing.FontStyle]::Bold)
$subFont = New-Object System.Drawing.Font "Arial", 14, ([System.Drawing.FontStyle]::Regular)
$labelFont = New-Object System.Drawing.Font "Arial", 13, ([System.Drawing.FontStyle]::Bold)
$bodyFont = New-Object System.Drawing.Font "Arial", 12, ([System.Drawing.FontStyle]::Regular)
$dark = Brush "#101318"
$gray = Brush "#65736D"
$card = Brush "#FFFFFF"
$shadow = Brush "#003C26" 20
$pg.DrawString("Verbal pictorial logo concepts", $titleFont, $dark, 40, 30)
$pg.DrawString("No alphabet marks. Rounded social-app symbols for voice messaging.", $subFont, $gray, 42, 72)

for ($i = 0; $i -lt $concepts.Count; $i++) {
  $row = [Math]::Floor($i / 5)
  $col = $i % 5
  $x = 40 + $col * 315
  $y = 120 + $row * 410
  $sp = RoundedPath ($x + 4) ($y + 10) 274 350 28
  $pg.FillPath($shadow, $sp)
  $sp.Dispose()
  $cp = RoundedPath $x $y 274 350 28
  $pg.FillPath($card, $cp)
  $cp.Dispose()
  $img = [System.Drawing.Image]::FromFile((Join-Path $output "$($concepts[$i].Name).png"))
  $pg.DrawImage($img, $x + 28, $y + 24, 218, 218)
  $img.Dispose()
  $pg.DrawString(("{0:D2} {1}" -f ($i + 1), $concepts[$i].Title), $labelFont, $dark, $x + 24, $y + 268)
  $pg.DrawString("pictorial voice mark", $bodyFont, $gray, $x + 24, $y + 298)
}

$previewPath = Join-Path $output "preview-pictorial.png"
$preview.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
$pg.Dispose()
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
# Verbal Pictorial Logo Concepts

Ten non-letter logo candidates for Verbal, inspired by memorable pictorial social app marks.

Requirements:
- No alphabet or wordmark inside the icon.
- Rounded square app-icon silhouette.
- Youthful 10s-20s social-app mood.
- Voice-message messenger signal through chat, waveform, audio, signal, ribbon, or orbit motifs.

Preview:
- preview-pictorial.png
"@
[System.IO.File]::WriteAllText((Join-Path $output "README.md"), $readme, [System.Text.UTF8Encoding]::new($false))

Get-ChildItem $output -Filter "*.png" | Sort-Object Name | Select-Object Name, Length
