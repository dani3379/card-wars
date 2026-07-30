extends Control
## ARMORED EDGE — the battlefield writ has been strapped into a riveted frame.
##
## This is a persistent rule costume, not a hit effect. Armored changes every
## strike by one point, so the player needs to see it before committing the
## blow. The read is deliberately carried by silhouette, repeated rivet heads,
## and an inset metal lip; colour is secondary. It is sized for Card2D's
## 200x150 compact token and remains useful after canvas scaling.
##
## Pure painter: Card2D owns lifetime and any entrance emphasis.

var seed_text := "armored"

const IRON_DARK := Color(0.105, 0.095, 0.080, 0.96)
const IRON := Color(0.37, 0.34, 0.29, 0.98)
const IRON_LIT := Color(0.72, 0.66, 0.53, 0.92)
const RIVET := Color(0.55, 0.51, 0.43, 1.0)
const RIVET_LIT := Color(0.90, 0.84, 0.68, 0.90)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _plate(poly: PackedVector2Array) -> void:
	var shadow := PackedVector2Array()
	for p in poly:
		shadow.append(p + Vector2(1.5, 1.8))
	draw_colored_polygon(shadow, Color(0.02, 0.015, 0.01, 0.72))
	draw_colored_polygon(poly, IRON)
	draw_polyline(poly, IRON_DARK, 1.8, true)


func _rivet(p: Vector2, slot_angle: float) -> void:
	# A broad dark socket and slotted head survive desaturation and downscaling;
	# the tiny highlight only supplies material, never the rule read.
	draw_circle(p + Vector2(0.8, 1.2), 4.2, Color(0.02, 0.015, 0.01, 0.78))
	draw_circle(p, 3.35, RIVET)
	draw_circle(p + Vector2(-0.9, -1.0), 1.05, RIVET_LIT)
	var d := Vector2(cos(slot_angle), sin(slot_angle)) * 1.7
	draw_line(p - d, p + d, IRON_DARK, 1.25, true)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 80.0 or h < 60.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	# Side straps own most of the silhouette. Their notched ends keep this from
	# reading as another generic UI outline or selection rectangle.
	var left := PackedVector2Array([
		Vector2(2, 12), Vector2(6, 7), Vector2(11, 12),
		Vector2(10, h - 46), Vector2(7, h - 40), Vector2(2, h - 44),
	])
	var right := PackedVector2Array([
		Vector2(w - 11, 12), Vector2(w - 6, 7), Vector2(w - 2, 12),
		Vector2(w - 2, h - 44), Vector2(w - 7, h - 40),
		Vector2(w - 10, h - 46),
	])
	_plate(left)
	_plate(right)

	# Two cross-straps brace the frame while leaving the top-right status rail
	# and bottom-corner stat seals unobscured.
	var top := PackedVector2Array([
		Vector2(12, 2), Vector2(w * 0.42, 3),
		Vector2(w * 0.46, 9), Vector2(11, 10),
	])
	var bottom := PackedVector2Array([
		Vector2(45, h - 9), Vector2(w - 45, h - 9),
		Vector2(w - 48, h - 2), Vector2(48, h - 2),
	])
	_plate(top)
	_plate(bottom)

	# An inner lit lip is the "plate thickness" cue. Against pale art the dark
	# strap carries contrast; against dark art this light edge does.
	draw_line(Vector2(11, 15), Vector2(10, h - 48), IRON_LIT, 1.8, true)
	draw_line(Vector2(w - 11, 15), Vector2(w - 10, h - 48), IRON_LIT, 1.8, true)
	draw_line(Vector2(14, 10), Vector2(w * 0.43, 9), IRON_LIT, 1.5, true)
	draw_line(Vector2(48, h - 10), Vector2(w - 48, h - 10), IRON_LIT, 1.5, true)

	# Repetition is the non-colour identifier: even at small scale, six round
	# fasteners on two hard rails read as armour rather than a rarity frame.
	for side_x in [6.4, w - 6.4]:
		for t in [0.22, 0.48, 0.73]:
			var y := lerpf(16.0, h - 50.0, t)
			_rivet(Vector2(side_x, y), rng.randf_range(-0.65, 0.65))
	_rivet(Vector2(w * 0.23, 6.4), rng.randf_range(-0.65, 0.65))
	_rivet(Vector2(w * 0.50, h - 5.6), rng.randf_range(-0.65, 0.65))
	_rivet(Vector2(w * 0.75, h - 5.6), rng.randf_range(-0.65, 0.65))
