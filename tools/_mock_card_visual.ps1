param(
	[string]$OutDir = "tools/card_mockups"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path
$outAbs = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outAbs | Out-Null

function New-Color([int]$r, [int]$g, [int]$b, [int]$a = 255) {
	return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function New-Font($names, [float]$size, $style = [System.Drawing.FontStyle]::Regular) {
	foreach ($n in $names) {
		try {
			return [System.Drawing.Font]::new($n, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
		} catch {}
	}
	return [System.Drawing.Font]::new([System.Drawing.FontFamily]::GenericSerif, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function New-RoundRectPath([System.Drawing.RectangleF]$rect, [float]$radius) {
	$path = [System.Drawing.Drawing2D.GraphicsPath]::new()
	$d = $radius * 2.0
	$path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
	$path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
	$path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
	$path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
	$path.CloseFigure()
	return $path
}

function Fill-RoundRect($g, [System.Drawing.RectangleF]$rect, [float]$radius, [System.Drawing.Brush]$brush) {
	$p = New-RoundRectPath $rect $radius
	$g.FillPath($brush, $p)
	$p.Dispose()
}

function Stroke-RoundRect($g, [System.Drawing.RectangleF]$rect, [float]$radius, [System.Drawing.Pen]$pen) {
	$p = New-RoundRectPath $rect $radius
	$g.DrawPath($pen, $p)
	$p.Dispose()
}

function Draw-CoverImage($g, [System.Drawing.Image]$img, [System.Drawing.RectangleF]$dst, [float]$radius) {
	$srcRatio = [double]$img.Width / [double]$img.Height
	$dstRatio = [double]$dst.Width / [double]$dst.Height
	if ($srcRatio -gt $dstRatio) {
		$sw = [int]([double]$img.Height * $dstRatio)
		$sx = [int](($img.Width - $sw) / 2)
		$src = [System.Drawing.Rectangle]::new($sx, 0, $sw, $img.Height)
	} else {
		$sh = [int]([double]$img.Width / $dstRatio)
		$sy = [int](($img.Height - $sh) / 2)
		$src = [System.Drawing.Rectangle]::new(0, $sy, $img.Width, $sh)
	}
	$p = New-RoundRectPath $dst $radius
	$state = $g.Save()
	$g.SetClip($p)
	$g.DrawImage($img, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
	# A restrained vignette to make the art read as mounted, without burying it.
	$top = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
		$dst,
		(New-Color 0 0 0 70),
		(New-Color 0 0 0 0),
		[System.Drawing.Drawing2D.LinearGradientMode]::Vertical
	)
	$g.FillRectangle($top, $dst)
	$top.Dispose()
	$g.Restore($state)
	$p.Dispose()
}

function Draw-Centered($g, [string]$text, [System.Drawing.Font]$font, [System.Drawing.Brush]$brush, [System.Drawing.RectangleF]$rect) {
	$sf = [System.Drawing.StringFormat]::new()
	$sf.Alignment = [System.Drawing.StringAlignment]::Center
	$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
	$sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
	$g.DrawString($text, $font, $brush, $rect, $sf)
	$sf.Dispose()
}

function Wrap-Lines($g, [string]$text, [System.Drawing.Font]$font, [float]$maxWidth) {
	$words = $text -split "\s+"
	$lines = New-Object System.Collections.Generic.List[string]
	$line = ""
	foreach ($w in $words) {
		$try = if ($line.Length -eq 0) { $w } else { "$line $w" }
		$sz = $g.MeasureString($try, $font)
		if ($sz.Width -le $maxWidth -or $line.Length -eq 0) {
			$line = $try
		} else {
			$lines.Add($line)
			$line = $w
		}
	}
	if ($line.Length -gt 0) { $lines.Add($line) }
	return $lines
}

function Draw-WrappedCentered($g, [string]$text, [System.Drawing.Font]$font, [System.Drawing.Brush]$brush, [System.Drawing.RectangleF]$rect, [float]$lineHeight) {
	$lines = Wrap-Lines $g $text $font ($rect.Width - 8)
	while (($lines.Count * $lineHeight) -gt $rect.Height -and $font.Size -gt 9) {
		$font = New-Font @($font.FontFamily.Name, "Georgia", "Times New Roman") ($font.Size - 1) $font.Style
		$lines = Wrap-Lines $g $text $font ($rect.Width - 8)
		$lineHeight = [Math]::Max(10, $font.Size + 1)
	}
	$total = $lines.Count * $lineHeight
	$y = $rect.Y + (($rect.Height - $total) / 2.0)
	$sf = [System.Drawing.StringFormat]::new()
	$sf.Alignment = [System.Drawing.StringAlignment]::Center
	foreach ($line in $lines) {
		$lr = [System.Drawing.RectangleF]::new($rect.X + 4, $y, $rect.Width - 8, $lineHeight)
		$g.DrawString($line, $font, $brush, $lr, $sf)
		$y += $lineHeight
	}
	$sf.Dispose()
}

function Draw-Badge($g, [float]$x, [float]$y, [float]$d, [System.Drawing.Color]$fill, [string]$num, [string]$tag) {
	$shadow = [System.Drawing.SolidBrush]::new((New-Color 0 0 0 85))
	$g.FillEllipse($shadow, $x + 2, $y + 4, $d, $d)
	$shadow.Dispose()
	$outer = [System.Drawing.SolidBrush]::new((New-Color 56 42 20))
	$g.FillEllipse($outer, $x, $y, $d, $d)
	$outer.Dispose()
	$ring = [System.Drawing.SolidBrush]::new((New-Color 194 154 72))
	$g.FillEllipse($ring, $x + 3, $y + 3, $d - 6, $d - 6)
	$ring.Dispose()
	$inner = [System.Drawing.SolidBrush]::new($fill)
	$g.FillEllipse($inner, $x + 7, $y + 7, $d - 14, $d - 14)
	$inner.Dispose()
	$nFont = New-Font @("Cinzel", "Georgia", "Times New Roman") 22 ([System.Drawing.FontStyle]::Bold)
	$tFont = New-Font @("Kreon", "Segoe UI", "Arial") 6 ([System.Drawing.FontStyle]::Bold)
	$white = [System.Drawing.SolidBrush]::new((New-Color 255 250 226))
	$black = [System.Drawing.SolidBrush]::new((New-Color 0 0 0 160))
	Draw-Centered $g $num $nFont $black ([System.Drawing.RectangleF]::new($x + 1, $y + 3, $d, $d - 8))
	Draw-Centered $g $num $nFont $white ([System.Drawing.RectangleF]::new($x, $y + 2, $d, $d - 8))
	Draw-Centered $g $tag $tFont $white ([System.Drawing.RectangleF]::new($x, $y + $d - 18, $d, 12))
	$white.Dispose(); $black.Dispose(); $nFont.Dispose(); $tFont.Dispose()
}

function Draw-Gem($g, [float]$cx, [float]$cy, [float]$r, [System.Drawing.Color]$col) {
	$pts = @(
		[System.Drawing.PointF]::new($cx, $cy - $r),
		[System.Drawing.PointF]::new($cx + $r, $cy),
		[System.Drawing.PointF]::new($cx, $cy + $r),
		[System.Drawing.PointF]::new($cx - $r, $cy)
	)
	$dark = [System.Drawing.SolidBrush]::new((New-Color 22 16 10))
	$g.FillPolygon($dark, $pts)
	$dark.Dispose()
	$inner = @(
		[System.Drawing.PointF]::new($cx, $cy - $r + 3),
		[System.Drawing.PointF]::new($cx + $r - 3, $cy),
		[System.Drawing.PointF]::new($cx, $cy + $r - 3),
		[System.Drawing.PointF]::new($cx - $r + 3, $cy)
	)
	$b = [System.Drawing.SolidBrush]::new($col)
	$g.FillPolygon($b, $inner)
	$b.Dispose()
}

function Draw-KeywordRail($g, [string[]]$keywords, [float]$x, [float]$y, [float]$w, [float]$h) {
	$font = New-Font @("Kreon", "Segoe UI", "Arial") 9 ([System.Drawing.FontStyle]::Bold)
	$count = $keywords.Count
	if ($count -eq 0) { return }
	$chipW = [Math]::Min(44, ($w - (($count - 1) * 5)) / $count)
	$totalW = ($chipW * $count) + (5 * ($count - 1))
	$cx = $x + (($w - $totalW) / 2)
	foreach ($kw in $keywords) {
		$r = [System.Drawing.RectangleF]::new($cx, $y, $chipW, $h)
		$b = [System.Drawing.SolidBrush]::new((New-Color 32 25 16 232))
		Fill-RoundRect $g $r 9 $b
		$b.Dispose()
		$p = [System.Drawing.Pen]::new((New-Color 197 161 79), 1.0)
		Stroke-RoundRect $g $r 9 $p
		$p.Dispose()
		$tb = [System.Drawing.SolidBrush]::new((New-Color 246 224 163))
		Draw-Centered $g $kw $font $tb $r
		$tb.Dispose()
		$cx += $chipW + 5
	}
	$font.Dispose()
}

function Render-MockCard($card) {
	$pad = 14
	$cw = 225
	$ch = 300
	$bmp = [System.Drawing.Bitmap]::new($cw + ($pad * 2), $ch + ($pad * 2))
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
	$g.Clear((New-Color 30 27 33))
	$g.TranslateTransform($pad, $pad)

	$rarity = $card.RarityColor
	$shadowBrush = [System.Drawing.SolidBrush]::new((New-Color 0 0 0 95))
	Fill-RoundRect $g ([System.Drawing.RectangleF]::new(4, 7, $cw - 8, $ch - 2)) 13 $shadowBrush
	$shadowBrush.Dispose()

	$outer = [System.Drawing.RectangleF]::new(0, 0, $cw, $ch)
	$paperGrad = [System.Drawing.Drawing2D.LinearGradientBrush]::new($outer, (New-Color 224 205 159), (New-Color 172 129 71), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
	Fill-RoundRect $g $outer 12 $paperGrad
	$paperGrad.Dispose()
	$inkPen = [System.Drawing.Pen]::new((New-Color 20 16 11), 3.0)
	Stroke-RoundRect $g ([System.Drawing.RectangleF]::new(2, 2, $cw - 4, $ch - 4)) 10 $inkPen
	$inkPen.Dispose()
	$rarePen = [System.Drawing.Pen]::new($rarity, 3.0)
	Stroke-RoundRect $g ([System.Drawing.RectangleF]::new(6, 6, $cw - 12, $ch - 12)) 8 $rarePen
	$rarePen.Dispose()

	# Stronger rarity read: a metal spine plus a gem, so it survives card fan overlap.
	$spineBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(170, $rarity))
	Fill-RoundRect $g ([System.Drawing.RectangleF]::new($cw - 12, 12, 6, $ch - 24)) 3 $spineBrush
	$spineBrush.Dispose()
	Draw-Gem $g ($cw / 2.0) 10 7 $rarity

	$artPath = Join-Path $root $card.Art
	$img = [System.Drawing.Image]::FromFile($artPath)
	$artRect = [System.Drawing.RectangleF]::new(10, 17, $cw - 20, 182)
	Draw-CoverImage $g $img $artRect 6
	$img.Dispose()
	$artFrame = [System.Drawing.Pen]::new((New-Color 18 14 10), 3.0)
	Stroke-RoundRect $g $artRect 6 $artFrame
	$artFrame.Dispose()
	$goldPen = [System.Drawing.Pen]::new((New-Color 208 166 78), 1.2)
	Stroke-RoundRect $g ([System.Drawing.RectangleF]::new(13, 20, $cw - 26, 176)) 4 $goldPen
	$goldPen.Dispose()

	# Name crosses the art/rules boundary: less dead paper, stronger silhouette.
	$nameRect = [System.Drawing.RectangleF]::new(19, 169, $cw - 38, 31)
	$nameBrush = [System.Drawing.SolidBrush]::new((New-Color 31 23 15 244))
	Fill-RoundRect $g $nameRect 4 $nameBrush
	$nameBrush.Dispose()
	$namePen = [System.Drawing.Pen]::new((New-Color 213 172 82), 1.2)
	Stroke-RoundRect $g $nameRect 4 $namePen
	$namePen.Dispose()
	$nameFont = New-Font @("Cinzel", "Georgia", "Times New Roman") 14 ([System.Drawing.FontStyle]::Bold)
	$nameColor = if ($card.Forged) { New-Color 255 229 142 } else { New-Color 237 210 132 }
	$nameTextBrush = [System.Drawing.SolidBrush]::new($nameColor)
	Draw-Centered $g $card.Name $nameFont $nameTextBrush $nameRect
	$nameTextBrush.Dispose()
	$nameFont.Dispose()
	if ($card.Forged) {
		Draw-Gem $g 23 184 4 (New-Color 255 214 89)
		Draw-Gem $g ($cw - 23) 184 4 (New-Color 255 214 89)
	}

	Draw-KeywordRail $g $card.KeywordTags 21 204 ($cw - 42) 22

	$rulesRect = [System.Drawing.RectangleF]::new(19, 230, $cw - 38, 49)
	$rulesBrush = [System.Drawing.SolidBrush]::new((New-Color 236 220 177 230))
	Fill-RoundRect $g $rulesRect 4 $rulesBrush
	$rulesBrush.Dispose()
	$rulesPen = [System.Drawing.Pen]::new((New-Color 109 75 35 170), 1.0)
	Stroke-RoundRect $g $rulesRect 4 $rulesPen
	$rulesPen.Dispose()
	$bodyFont = New-Font @("Kreon", "Georgia", "Times New Roman") 11 ([System.Drawing.FontStyle]::Regular)
	$bodyBrush = [System.Drawing.SolidBrush]::new((New-Color 56 34 15))
	Draw-WrappedCentered $g $card.Rule $bodyFont $bodyBrush $rulesRect 13
	$bodyBrush.Dispose()
	$bodyFont.Dispose()

	Draw-Badge $g -8 -8 50 (New-Color 35 69 110) ([string]$card.Cost) "CMD"
	Draw-Badge $g -5 254 49 (New-Color 116 91 31) ([string]$card.Atk) "ATK"
	Draw-Badge $g ($cw - 44) 254 49 (New-Color 132 33 24) ([string]$card.Hp) "HP"

	$g.ResetTransform()
	$g.Dispose()
	return $bmp
}

$cards = @(
	[pscustomobject]@{
		Id="plague_rat"; Name="PLAGUE RAT"; Cost=1; Atk=1; Hp=2; Art="assets/creatures/plague_rat.png";
		Rule="Poison. Lifesteal."; KeywordTags=@("POI","LIFE"); RarityColor=(New-Color 226 226 214); Forged=$false;
		Current="tools/_v_kw/plague_rat.png"
	},
	[pscustomobject]@{
		Id="doom_knight"; Name="DOOM KNIGHT"; Cost=4; Atk=5; Hp=4; Art="assets/creatures/doom_knight.png";
		Rule="Piercing. Doom 3. On death, deal 4 to face."; KeywordTags=@("PRC","D3","DIE"); RarityColor=(New-Color 244 185 52); Forged=$false;
		Current="tools/_v_kw/doom_knight.png"
	},
	[pscustomobject]@{
		Id="glass_knight_plus"; Name="GLASS KNIGHT +"; Cost=2; Atk=4; Hp=1; Art="assets/creatures/glass_knight.png";
		Rule="Shield. Swift. Slay: regain Shield."; KeywordTags=@("SHD","SWF"); RarityColor=(New-Color 75 139 226); Forged=$true;
		Current="tools/_v_kw/glass_knight_PLUS.png"
	}
)

$mockPaths = @()
foreach ($card in $cards) {
	$bmp = Render-MockCard $card
	$out = Join-Path $outAbs ("mock_{0}.png" -f $card.Id)
	$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
	$bmp.Dispose()
	$mockPaths += $out
}

$fontTitle = New-Font @("Kreon", "Georgia", "Times New Roman") 28 ([System.Drawing.FontStyle]::Bold)
$fontLabel = New-Font @("Kreon", "Segoe UI", "Arial") 18 ([System.Drawing.FontStyle]::Bold)
$fontSmall = New-Font @("Kreon", "Segoe UI", "Arial") 13 ([System.Drawing.FontStyle]::Regular)

$spreadW = 1260
$rowH = 390
$spreadH = 96 + ($cards.Count * $rowH)
$spread = [System.Drawing.Bitmap]::new($spreadW, $spreadH)
$sg = [System.Drawing.Graphics]::FromImage($spread)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$sg.Clear((New-Color 22 20 24))
$titleBrush = [System.Drawing.SolidBrush]::new((New-Color 238 214 144))
$subBrush = [System.Drawing.SolidBrush]::new((New-Color 190 174 132))
$sg.DrawString("Burning Meadow card face mockup", $fontTitle, $titleBrush, 34, 22)
$sg.DrawString("Same footprint. Bigger art read, stronger rarity spine, shorter rules band, labeled stat seals.", $fontSmall, $subBrush, 38, 57)
$labelBrush = [System.Drawing.SolidBrush]::new((New-Color 231 224 197))

for ($i = 0; $i -lt $cards.Count; $i++) {
	$card = $cards[$i]
	$y = 96 + ($i * $rowH)
	$sg.DrawString("CURRENT", $fontLabel, $labelBrush, 52, $y + 4)
	$sg.DrawString("MOCKUP", $fontLabel, $labelBrush, 460, $y + 4)
	$cur = [System.Drawing.Image]::FromFile((Join-Path $root $card.Current))
	$mock = [System.Drawing.Image]::FromFile($mockPaths[$i])
	$sg.DrawImage($cur, [System.Drawing.RectangleF]::new(60, $y + 40, 253, 328))
	$sg.DrawImage($mock, [System.Drawing.RectangleF]::new(445, $y + 40, 253, 328))
	$note = switch ($card.Id) {
		"plague_rat" { "Common still feels humble, but the art and mechanic tags read faster." }
		"doom_knight" { "Rare gets a loud gold spine and the doom/last-gasp identity is legible at hand size." }
		default { "Forged cue survives the name length: bright title plus gilt side pips." }
	}
	Draw-WrappedCentered $sg $note $fontSmall $subBrush ([System.Drawing.RectangleF]::new(735, $y + 118, 430, 92)) 17
	$cur.Dispose()
	$mock.Dispose()
}

$titleBrush.Dispose(); $subBrush.Dispose(); $labelBrush.Dispose()
$fontTitle.Dispose(); $fontLabel.Dispose(); $fontSmall.Dispose()
$spreadPath = Join-Path $outAbs "bolder_writ_mockup_spread.png"
$spread.Save($spreadPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sg.Dispose()
$spread.Dispose()

Write-Host "WROTE $spreadPath"
foreach ($p in $mockPaths) { Write-Host "WROTE $p" }
