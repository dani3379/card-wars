## DerbyBeetle — one runner in the sappers' beetle derby. Top-down-ish
## oval shell with the runner's silk band across it (`tint` — how you tell
## your money apart at a distance), head, antennae, and six legs whose
## swing is driven by `scuttle` (the scene advances it while the beetle
## moves; legs freeze mid-stride when it stops). Faces RIGHT — the race
## runs left to right. Pure painter.
extends Control

var seed_text := "beetle"
var tint := Color(0.85, 0.30, 0.22)
var scuttle := 0.0

const SHELL := Color(0.155, 0.120, 0.085)
const SHELL_LIT := Color(0.290, 0.225, 0.150)
const LEG := Color(0.10, 0.08, 0.06)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	if minf(size.x, size.y) <= 12.0:
		return
	var c := size * 0.5
	var rx := size.x * 0.30
	var ry := size.y * 0.30
	_ellipse(c + Vector2(1, ry * 0.9), rx * 1.15, ry * 0.5, Color(0, 0, 0, 0.35))
	# Legs: three a side, swinging in alternating phase off `scuttle`.
	for i in range(3):
		var lx := c.x - rx * 0.5 + float(i) * rx * 0.55
		var phase := scuttle * TAU + float(i) * 2.1
		var swing := sin(phase) * 3.5
		draw_line(Vector2(lx, c.y), Vector2(lx - 3.0 + swing, c.y - ry - 4.0),
			LEG, 1.8, true)
		draw_line(Vector2(lx, c.y), Vector2(lx - 3.0 - swing, c.y + ry + 4.0),
			LEG, 1.8, true)
	# Shell, silk band, sheen; head and antennae point the way it's going.
	_ellipse(c, rx, ry, SHELL)
	var band := PackedVector2Array([
		c + Vector2(-rx * 0.30, -ry), c + Vector2(rx * 0.05, -ry),
		c + Vector2(rx * 0.30, ry), c + Vector2(-rx * 0.05, ry)])
	draw_colored_polygon(band, Color(tint.r, tint.g, tint.b, 0.85))
	_ellipse(c + Vector2(-rx * 0.25, -ry * 0.35), rx * 0.5, ry * 0.30,
		Color(SHELL_LIT.r, SHELL_LIT.g, SHELL_LIT.b, 0.5))
	draw_line(c + Vector2(-rx, 0), c + Vector2(rx, 0),
		Color(0, 0, 0, 0.45), 1.0, true)
	_ellipse(c + Vector2(rx + 3.0, 0), 4.0, 3.4, SHELL)
	for sgn in [-1.0, 1.0]:
		draw_line(c + Vector2(rx + 5.0, sgn * 2.0),
			c + Vector2(rx + 11.0, sgn * 5.0 + sin(scuttle * TAU) * 1.5),
			LEG, 1.2, true)
