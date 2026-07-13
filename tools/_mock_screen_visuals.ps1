param(
	[string]$OutDir = "tools/screen_mockups"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$ErrorActionPreference = "Stop"
$root = (Resolve-Path ".").Path
$outAbs = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outAbs | Out-Null

function C([int]$r, [int]$g, [int]$b, [int]$a = 255) {
	return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function FontAny($names, [float]$size, $style = [System.Drawing.FontStyle]::Regular) {
	foreach ($n in $names) {
		try {
			return [System.Drawing.Font]::new($n, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
		} catch {}
	}
	return [System.Drawing.Font]::new([System.Drawing.FontFamily]::GenericSansSerif, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function RoundPath([System.Drawing.RectangleF]$r, [float]$radius) {
	$p = [System.Drawing.Drawing2D.GraphicsPath]::new()
	$d = $radius * 2.0
	$p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
	$p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
	$p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
	$p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
	$p.CloseFigure()
	return $p
}

function FillRR($g, [System.Drawing.RectangleF]$r, [float]$radius, [System.Drawing.Color]$col) {
	$p = RoundPath $r $radius
	$b = [System.Drawing.SolidBrush]::new($col)
	$g.FillPath($b, $p)
	$b.Dispose()
	$p.Dispose()
}

function StrokeRR($g, [System.Drawing.RectangleF]$r, [float]$radius, [System.Drawing.Color]$col, [float]$w = 2.0) {
	$p = RoundPath $r $radius
	$pen = [System.Drawing.Pen]::new($col, $w)
	$g.DrawPath($pen, $p)
	$pen.Dispose()
	$p.Dispose()
}

function DrawCenter($g, [string]$text, [System.Drawing.Font]$font, [System.Drawing.Color]$col, [System.Drawing.RectangleF]$r) {
	$sf = [System.Drawing.StringFormat]::new()
	$sf.Alignment = [System.Drawing.StringAlignment]::Center
	$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
	$sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
	$b = [System.Drawing.SolidBrush]::new($col)
	$g.DrawString($text, $font, $b, $r, $sf)
	$b.Dispose()
	$sf.Dispose()
}

function DrawText($g, [string]$text, [System.Drawing.Font]$font, [System.Drawing.Color]$col, [float]$x, [float]$y) {
	$b = [System.Drawing.SolidBrush]::new($col)
	$g.DrawString($text, $font, $b, $x, $y)
	$b.Dispose()
}

function DrawMultiline($g, [string]$text, [System.Drawing.Font]$font, [System.Drawing.Color]$col, [System.Drawing.RectangleF]$r) {
	$sf = [System.Drawing.StringFormat]::new()
	$sf.Alignment = [System.Drawing.StringAlignment]::Near
	$sf.LineAlignment = [System.Drawing.StringAlignment]::Near
	$sf.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
	$b = [System.Drawing.SolidBrush]::new($col)
	$g.DrawString($text, $font, $b, $r, $sf)
	$b.Dispose()
	$sf.Dispose()
}

function DrawShade($g, [int]$w, [int]$h, [int]$alpha = 145) {
	$b = [System.Drawing.SolidBrush]::new((C 0 0 0 $alpha))
	$g.FillRectangle($b, 0, 0, $w, $h)
	$b.Dispose()
}

function DrawShelf($g, [float]$x, [float]$y, [float]$w, [float]$h) {
	FillRR $g ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) 8 (C 24 17 12 248)
	StrokeRR $g ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) 8 (C 176 126 54 205) 2
	$pen = [System.Drawing.Pen]::new((C 229 180 80 95), 1)
	$g.DrawLine($pen, $x + 24, $y + 18, $x + $w - 24, $y + 18)
	$g.DrawLine($pen, $x + 24, $y + $h - 18, $x + $w - 24, $y + $h - 18)
	$pen.Dispose()
}

function DrawPill($g, [string]$text, [float]$x, [float]$y, [float]$w, [float]$h, [System.Drawing.Color]$fill, [System.Drawing.Color]$edge) {
	FillRR $g ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) ($h / 2) $fill
	StrokeRR $g ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) ($h / 2) $edge 2
	$f = FontAny @("Kreon", "Segoe UI", "Arial") 18 ([System.Drawing.FontStyle]::Bold)
	DrawCenter $g $text $f (C 255 238 176) ([System.Drawing.RectangleF]::new($x, $y - 1, $w, $h))
	$f.Dispose()
}

function Crop($img, [int]$x, [int]$y, [int]$w, [int]$h) {
	$bmp = [System.Drawing.Bitmap]::new($w, $h)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.DrawImage($img, [System.Drawing.Rectangle]::new(0, 0, $w, $h), [System.Drawing.Rectangle]::new($x, $y, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
	$g.Dispose()
	return $bmp
}

function SavePng($bmp, [string]$name) {
	$p = Join-Path $outAbs $name
	$bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
	return $p
}

function NewCanvasFrom($path) {
	$src = [System.Drawing.Image]::FromFile((Join-Path $root $path))
	$bmp = [System.Drawing.Bitmap]::new($src.Width, $src.Height)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
	$g.DrawImage($src, 0, 0, $src.Width, $src.Height)
	return @($src, $bmp, $g)
}

function MockCombat {
	$tuple = NewCanvasFrom "tools/screenshot/combat_open.png"
	$src = $tuple[0]; $bmp = $tuple[1]; $g = $tuple[2]
	$W = $bmp.Width; $H = $bmp.Height
	DrawShade $g $W $H 60

	# Left inventory rail: consolidate scattered deck, potions, portrait, HP.
	FillRR $g ([System.Drawing.RectangleF]::new(18, 135, 250, 895)) 10 (C 12 10 8 246)
	StrokeRR $g ([System.Drawing.RectangleF]::new(18, 135, 250, 895)) 10 (C 205 156 63 145) 2
	$title = FontAny @("Kreon", "Georgia", "Times New Roman") 24 ([System.Drawing.FontStyle]::Bold)
	$body = FontAny @("Kreon", "Segoe UI", "Arial") 18
	DrawCenter $g "WAR KIT" $title (C 239 208 118) ([System.Drawing.RectangleF]::new(38, 154, 210, 38))
	DrawPill $g "DECK 9" 42 215 86 42 (C 36 29 20 232) (C 207 162 73)
	DrawPill $g "ASH 0" 142 215 86 42 (C 36 29 20 232) (C 207 162 73)
	DrawPill $g "POTIONS" 42 286 186 42 (C 35 24 20 232) (C 207 90 52)
	$hero = Crop $src 18 724 238 248
	$g.DrawImage($hero, [System.Drawing.RectangleF]::new(39, 615, 204, 213))
	$hero.Dispose()
	StrokeRR $g ([System.Drawing.RectangleF]::new(39, 615, 204, 213)) 6 (C 216 166 74 185) 2
	DrawPill $g "24 / 25 HP" 42 852 186 58 (C 121 27 22 238) (C 235 196 84)
	DrawPill $g "3 / 3 COMMAND" 42 928 186 58 (C 25 68 118 238) (C 111 178 255)

	# Enemy dossier rail: make portrait and incoming damage one object.
	FillRR $g ([System.Drawing.RectangleF]::new(1616, 28, 276, 352)) 10 (C 12 10 8 220)
	StrokeRR $g ([System.Drawing.RectangleF]::new(1616, 28, 276, 352)) 10 (C 205 156 63 150) 2
	$enemy = Crop $src 1640 18 262 196
	$g.DrawImage($enemy, [System.Drawing.RectangleF]::new(1635, 47, 238, 178))
	$enemy.Dispose()
	DrawCenter $g "THE FIRST CUT" $title (C 239 208 118) ([System.Drawing.RectangleF]::new(1634, 236, 240, 34))
	DrawPill $g "11 / 11" 1654 282 198 58 (C 130 31 23 238) (C 242 113 74)
	DrawCenter $g "INCOMING: 4" $body (C 255 206 107) ([System.Drawing.RectangleF]::new(1638, 342, 230, 30))

	# Top state banner: smaller, denser, less floating text.
	FillRR $g ([System.Drawing.RectangleF]::new(688, 22, 544, 92)) 8 (C 17 12 9 250)
	StrokeRR $g ([System.Drawing.RectangleF]::new(688, 22, 544, 92)) 8 (C 206 156 63 165) 2
	DrawCenter $g "YOUR TURN" $title (C 246 222 145) ([System.Drawing.RectangleF]::new(720, 35, 480, 34))
	DrawCenter $g "Round 1 - set your line" $body (C 187 170 117) ([System.Drawing.RectangleF]::new(720, 72, 480, 28))
	$title.Dispose(); $body.Dispose()
	$g.Dispose(); $src.Dispose()
	return SavePng $bmp "combat_hud_mockup.png"
}

function MockShop {
	$tuple = NewCanvasFrom "tools/screenshot/audit/shop.png"
	$src = $tuple[0]; $bmp = $tuple[1]; $g = $tuple[2]
	$W = $bmp.Width; $H = $bmp.Height
	DrawShade $g $W $H 150
	$btop = [System.Drawing.SolidBrush]::new((C 0 0 0 170))
	$g.FillRectangle($btop, 0, 0, $W, 145)
	$btop.Dispose()

	$title = FontAny @("Kreon", "Georgia", "Times New Roman") 44 ([System.Drawing.FontStyle]::Bold)
	$head = FontAny @("Kreon", "Georgia", "Times New Roman") 26 ([System.Drawing.FontStyle]::Bold)
	$body = FontAny @("Kreon", "Segoe UI", "Arial") 19
	DrawCenter $g "THE SUTLER'S TABLE" $title (C 246 218 116) ([System.Drawing.RectangleF]::new(0, 30, $W, 62))
	DrawCenter $g "999 gold" $head (C 255 221 119) ([System.Drawing.RectangleF]::new(0, 88, $W, 38))

	DrawShelf $g 270 145 1380 462
	DrawCenter $g "CARDS FOR SALE" $head (C 230 205 144) ([System.Drawing.RectangleF]::new(270, 158, 1380, 38))

	$cardRects = @(
		@(364, 160, 275, 370, "BUY 50g"),
		@(665, 160, 275, 370, "BUY 50g"),
		@(966, 170, 280, 360, "BUY 50g"),
		@(1265, 160, 285, 370, "BUY 75g")
	)
	$x = 335
	foreach ($cr in $cardRects) {
		$c = Crop $src $cr[0] $cr[1] $cr[2] $cr[3]
		$g.DrawImage($c, [System.Drawing.RectangleF]::new($x, 212, 238, 320))
		$c.Dispose()
		DrawPill $g $cr[4] ($x + 25) 535 188 46 (C 39 49 78 240) (C 227 184 84)
		$x += 310
	}

	DrawShelf $g 410 660 1100 238
	DrawCenter $g "RELICS AND SERVICES" $head (C 230 205 144) ([System.Drawing.RectangleF]::new(410, 675, 1100, 34))
	$services = @(
		@("TOOLBOX", "100g", "Start each fight with an extra choice.", 485),
		@("INFERNO VIAL", "40g", "Deal 3 to all enemy creatures.", 815),
		@("BUY-BACK", "+ gold", "Sell one card. Curses pay less.", 1145)
	)
	foreach ($s in $services) {
		FillRR $g ([System.Drawing.RectangleF]::new($s[3], 725, 290, 132)) 8 (C 41 27 18 232)
		StrokeRR $g ([System.Drawing.RectangleF]::new($s[3], 725, 290, 132)) 8 (C 215 135 68 195) 2
		DrawCenter $g $s[0] $head (C 245 212 122) ([System.Drawing.RectangleF]::new($s[3] + 18, 740, 254, 30))
		DrawMultiline $g $s[2] $body (C 231 217 178) ([System.Drawing.RectangleF]::new($s[3] + 28, 782, 234, 48))
		DrawCenter $g $s[1] $body (C 255 207 96) ([System.Drawing.RectangleF]::new($s[3] + 18, 826, 254, 28))
	}
	DrawPill $g "LEAVE SHOP" 835 960 250 54 (C 35 27 21 240) (C 218 174 82)

	$title.Dispose(); $head.Dispose(); $body.Dispose()
	$g.Dispose(); $src.Dispose()
	return SavePng $bmp "shop_layout_mockup.png"
}

function MockCamp {
	$tuple = NewCanvasFrom "tools/screenshot/audit/rest.png"
	$src = $tuple[0]; $bmp = $tuple[1]; $g = $tuple[2]
	$W = $bmp.Width; $H = $bmp.Height
	DrawShade $g $W $H 70
	$btop = [System.Drawing.SolidBrush]::new((C 0 0 0 120))
	$g.FillRectangle($btop, 0, 0, $W, 160)
	$btop.Dispose()
	# Hide the current low-contrast choice row and build a cleaner camp ledger.
	FillRR $g ([System.Drawing.RectangleF]::new(260, 615, 1400, 340)) 16 (C 9 8 7 210)
	StrokeRR $g ([System.Drawing.RectangleF]::new(260, 615, 1400, 340)) 16 (C 202 154 67 170) 2

	$title = FontAny @("Kreon", "Georgia", "Times New Roman") 44 ([System.Drawing.FontStyle]::Bold)
	$head = FontAny @("Kreon", "Georgia", "Times New Roman") 28 ([System.Drawing.FontStyle]::Bold)
	$body = FontAny @("Kreon", "Segoe UI", "Arial") 20
	DrawCenter $g "MAKE CAMP" $title (C 247 220 116) ([System.Drawing.RectangleF]::new(0, 34, $W, 64))
	DrawCenter $g "18 / 25 HP" $head (C 238 218 160) ([System.Drawing.RectangleF]::new(0, 105, $W, 36))

	$choices = @(
		@("REST", "Heal to 25 / 25", "The road weighs heavy. Sleep under watch.", 315, "HP"),
		@("FORGE", "Choose a card to upgrade", "Sharpen one soldier before the next fight.", 765, "+"),
		@("REFORGE", "Forge two cards", "Whetstone is ready. Twice the heat.", 1215, "II")
	)
	foreach ($c in $choices) {
		FillRR $g ([System.Drawing.RectangleF]::new($c[3], 675, 390, 210)) 8 (C 28 21 15 238)
		StrokeRR $g ([System.Drawing.RectangleF]::new($c[3], 675, 390, 210)) 8 (C 221 175 81 210) 2
		FillRR $g ([System.Drawing.RectangleF]::new($c[3] + 24, 722, 108, 108)) 54 (C 224 199 135 230)
		DrawCenter $g $c[4] $title (C 36 25 14) ([System.Drawing.RectangleF]::new($c[3] + 24, 716, 108, 108))
		DrawText $g $c[0] $head (C 255 226 124) ($c[3] + 155) 710
		DrawText $g $c[1] $body (C 238 221 174) ($c[3] + 155) 752
		DrawMultiline $g $c[2] $body (C 178 165 129) ([System.Drawing.RectangleF]::new($c[3] + 155, 788, 200, 60))
	}
	DrawPill $g "RETURN TO ROAD" 835 960 250 54 (C 35 27 21 240) (C 218 174 82)
	$title.Dispose(); $head.Dispose(); $body.Dispose()
	$g.Dispose(); $src.Dispose()
	return SavePng $bmp "camp_choices_mockup.png"
}

$combat = MockCombat
$shop = MockShop
$camp = MockCamp

$labelFont = FontAny @("Kreon", "Georgia", "Times New Roman") 26 ([System.Drawing.FontStyle]::Bold)
$smallFont = FontAny @("Kreon", "Segoe UI", "Arial") 15
$sheetW = 1600
$rowH = 500
$sheetH = 90 + ($rowH * 3)
$sheet = [System.Drawing.Bitmap]::new($sheetW, $sheetH)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$sg.Clear((C 20 18 22))
$titleFont = FontAny @("Kreon", "Georgia", "Times New Roman") 34 ([System.Drawing.FontStyle]::Bold)
DrawText $sg "Burning Meadow screen mockups" $titleFont (C 245 218 139) 34 20
DrawText $sg "Cleaner layout experiments on real screenshots. These are not production UI yet." $smallFont (C 189 174 129) 36 57

$rows = @(
	@("COMBAT HUD", "tools/screenshot/combat_open.png", $combat, "Consolidate scattered status into two rails and a compact turn banner."),
	@("SHOP", "tools/screenshot/audit/shop.png", $shop, "Make the shop feel like a table: cards on one shelf, services on another."),
	@("CAMP", "tools/screenshot/audit/rest.png", $camp, "Replace oversized icons and grey copy with three clean decisions.")
)
for ($i = 0; $i -lt $rows.Count; $i++) {
	$y = 92 + ($i * $rowH)
	$row = $rows[$i]
	DrawText $sg $row[0] $labelFont (C 245 222 151) 34 ($y + 4)
	DrawText $sg "CURRENT" $smallFont (C 225 211 169) 44 ($y + 36)
	DrawText $sg "MOCKUP" $smallFont (C 225 211 169) 820 ($y + 36)
	DrawText $sg $row[3] $smallFont (C 177 164 126) 44 ($y + 455)
	$cur = [System.Drawing.Image]::FromFile((Join-Path $root $row[1]))
	$mk = [System.Drawing.Image]::FromFile($row[2])
	$sg.DrawImage($cur, [System.Drawing.RectangleF]::new(44, $y + 66, 720, 405))
	$sg.DrawImage($mk, [System.Drawing.RectangleF]::new(820, $y + 66, 720, 405))
	$cur.Dispose(); $mk.Dispose()
}
$spread = SavePng $sheet "screen_mockup_spread.png"
$sg.Dispose(); $sheet.Dispose()
$labelFont.Dispose(); $smallFont.Dispose(); $titleFont.Dispose()

Write-Host "WROTE $spread"
Write-Host "WROTE $combat"
Write-Host "WROTE $shop"
Write-Host "WROTE $camp"
