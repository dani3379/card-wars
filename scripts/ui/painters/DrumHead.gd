## DrumHead — one field drum of the Drummer's Tattoo (drum_game), seen
## from the table's camera pitch: the skin is an ELLIPSE (cabinet
## projection, wider than tall), rope-laced to a wooden shell. The engine
## drives `glow` (0..1, a struck flash it tweens down) and flips `wrong`
## for a missed echo. Pure painter; the Event scene owns all motion and
## hit-testing. (Reworked 2026-07-20 — the first pass candy-tinted the
## whole head pastel. The identity colour now rides the painted RIM BAND
## and a tick device I·II·III·IIII on the near shell — a second,
## colour-free channel — while the head stays aged vellum.)
extends Control

var seed_text := "drum"
var tint := Color(0.80, 0.72, 0.55)   # the drum's identity colour
var index := 0                         # 0-based drum number → tick device
var glow := 0.0                        # struck brightness, engine-tweened
var wrong := false                     # a missed beat — red flash

const RIM := Color(0.235, 0.165, 0.105)
const RIM_LIT := Color(0.40, 0.30, 0.19)
const EDGE_INK := Color(0.07, 0.05, 0.035)
const ROPE := Color(0.68, 0.58, 0.40)
const ROPE_DK := Color(0.38, 0.31, 0.20)
const SKIN := Color(0.845, 0.785, 0.660)
const SKIN_DK := Color(0.700, 0.635, 0.510)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ellipse(center: Vector2, rx: float, ry: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 14.0:
		return
	var c := size * 0.5
	var rx := size.x * 0.46
	var ry := size.y * 0.40
	var lit := clampf(glow, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# Age the identity colour toward the camp's palette; the pure value is
	# reserved for the struck halo.
	var ident := tint.lerp(Color(0.45, 0.38, 0.30), 0.30)

	# Contact shadow, wide and soft — the drum sits on the table.
	draw_colored_polygon(_ellipse(c + Vector2(2, ry * 0.44), rx * 1.04, ry * 0.74),
		Color(0, 0, 0, 0.32))

	# ── the shell: side wall below the head, then the rim hoop ──────────
	var wall := PackedVector2Array()
	for i in range(15):
		var a := PI * float(i) / 14.0
		wall.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	for i in range(14, -1, -1):
		var a := PI * float(i) / 14.0
		wall.append(c + Vector2(cos(a) * rx, sin(a) * ry + size.y * 0.16))
	draw_colored_polygon(wall, RIM.lerp(RIM_LIT, lit * 0.4))
	draw_colored_polygon(_ellipse(c + Vector2(0, 2), rx, ry),
		RIM.lerp(RIM_LIT, 0.25 + lit * 0.4))
	# Identity band painted around the shell wall.
	var band := PackedVector2Array()
	for i in range(15):
		var a := PI * float(i) / 14.0
		band.append(c + Vector2(cos(a) * rx, sin(a) * ry + size.y * 0.055))
	for i in range(14, -1, -1):
		var a := PI * float(i) / 14.0
		band.append(c + Vector2(cos(a) * rx, sin(a) * ry + size.y * 0.115))
	draw_colored_polygon(band, Color(ident.r, ident.g, ident.b, 0.85))
	draw_colored_polygon(band, Color(0, 0, 0, 0.10))

	# ── rope tension V-lacing over wall and band ─────────────────────────
	var laces := 9
	for i in range(laces):
		var a := PI * (float(i) + 0.5) / float(laces)
		var top := c + Vector2(cos(a) * rx * 0.97, sin(a) * ry * 0.97)
		var bot := c + Vector2(cos(a) * rx * 1.00, sin(a) * ry + size.y * 0.15)
		var nxt := PI * (float(i) + 1.0) / float(laces)
		var bot2 := c + Vector2(cos(nxt) * rx * 1.00, sin(nxt) * ry + size.y * 0.15)
		draw_line(top, bot, ROPE_DK, 2.6, true)
		draw_line(top, bot, ROPE, 1.4, true)
		draw_line(top, bot2, Color(ROPE_DK.r, ROPE_DK.g, ROPE_DK.b, 0.55), 1.8, true)

	# ── the head: aged vellum, only a whisper of the identity ───────────
	var skin := SKIN.lerp(ident, 0.14)
	if wrong:
		skin = Color(0.62, 0.20, 0.16)
	var flash := skin.lerp(Color(1, 0.97, 0.9), lit * 0.7)
	draw_colored_polygon(_ellipse(c, rx * 0.84, ry * 0.84), flash)
	# Vellum modeling: shaded lower rim, top-lit sheen, mottle, stick wear.
	draw_colored_polygon(_ellipse(c + Vector2(0, ry * 0.16), rx * 0.76, ry * 0.62),
		Color(SKIN_DK.r, SKIN_DK.g, SKIN_DK.b, 0.30))
	draw_colored_polygon(_ellipse(c + Vector2(-rx * 0.12, -ry * 0.26),
		rx * 0.46, ry * 0.28), Color(1, 1, 1, 0.13 + lit * 0.22))
	for i in range(4):
		var mp := c + Vector2(rng.randf_range(-0.4, 0.4) * rx,
			rng.randf_range(-0.35, 0.4) * ry)
		draw_colored_polygon(_ellipse(mp, rng.randf_range(3.0, 7.0),
			rng.randf_range(2.0, 4.0), 12), Color(SKIN_DK.r, SKIN_DK.g, SKIN_DK.b, 0.18))
	# The stick-worn heart of the head.
	draw_colored_polygon(_ellipse(c + Vector2(0, ry * 0.05), rx * 0.24, ry * 0.20),
		Color(SKIN_DK.r * 0.9, SKIN_DK.g * 0.9, SKIN_DK.b * 0.9, 0.35))
	draw_colored_polygon(_ellipse(c + Vector2(0, ry * 0.05), rx * 0.13, ry * 0.11),
		Color(0.50, 0.44, 0.35, 0.30))
	# Flesh hoop: the tension ring pinning the vellum.
	draw_arc(c, rx * 0.84, 0.0, TAU, 32, EDGE_INK, 2.2, true)
	draw_arc(c + Vector2(0, -1), rx * 0.84, PI * 1.05, PI * 1.85, 14,
		Color(1, 1, 0.92, 0.22), 1.2, true)

	# ── the tick device: I · II · III · IIII on the near shell wall ─────
	var ticks := clampi(index + 1, 1, 4)
	var t0 := c + Vector2(-float(ticks - 1) * 4.0, ry + size.y * 0.075)
	for i in range(ticks):
		var tp := t0 + Vector2(float(i) * 8.0, 0)
		draw_line(tp + Vector2(0, -5), tp + Vector2(0, 5),
			Color(0.92, 0.88, 0.78, 0.90), 2.2, true)
		draw_line(tp + Vector2(1.4, -5), tp + Vector2(1.4, 5),
			Color(0, 0, 0, 0.30), 1.0, true)

	# Struck halo: a bright rim of the drum's own TRUE colour.
	if lit > 0.02:
		draw_arc(c, rx * 0.88, 0.0, TAU, 32,
			Color(tint.r, tint.g, tint.b, lit * 0.85), 3.0 + lit * 2.0, true)
