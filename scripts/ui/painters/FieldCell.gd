## FieldCell — one square of the sappers' sand table (the field_game
## stage). States: "hidden" (raked sand mound, unstepped), "stepped"
## (pressed flat with a boot print — the engine overlays the chalked
## adjacency number), "blown" (the pinch of powder went off: crater and
## soot), "charge" (revealed powder button — the honest show after a bust,
## or the derby crowd's scouted chalk flag when `flagged`). Pure painter;
## the Event scene owns all motion.
extends Control

var seed_text := "cell"
var state := "hidden"
var flagged := false

const SAND := Color(0.760, 0.690, 0.545)
const SAND_LIT := Color(0.835, 0.775, 0.640)
const SAND_DARK := Color(0.600, 0.535, 0.410)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _blob(center: Vector2, rx: float, ry: float, n: int = 14) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + 0.08 * sin(a * 3.0 + ph) + 0.05 * sin(a * 6.0 + ph * 1.7)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry) * w)
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 12.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text + "_grain")
	var c := size * 0.5
	match state:
		"hidden":
			# A raked mound — soft dome, lit from above, grain flecks.
			draw_colored_polygon(_blob(c + Vector2(1.5, 3.0),
				size.x * 0.44, size.y * 0.34), Color(0, 0, 0, 0.22))
			draw_colored_polygon(_blob(c, size.x * 0.44, size.y * 0.36), SAND)
			draw_colored_polygon(_blob(c + Vector2(-2, -4),
				size.x * 0.30, size.y * 0.20, 10), SAND_LIT)
			for _i in range(7):
				draw_circle(c + Vector2(rng.randf_range(-size.x * 0.3, size.x * 0.3),
					rng.randf_range(-size.y * 0.24, size.y * 0.28)), 1.1,
					Color(SAND_DARK.r, SAND_DARK.g, SAND_DARK.b, 0.7), true, -1.0, true)
			# The rake's teeth, three faint furrows.
			for i in range(3):
				var y := c.y - 6.0 + float(i) * 6.0
				draw_line(Vector2(c.x - size.x * 0.30, y),
					Vector2(c.x + size.x * 0.30, y + 1.5),
					Color(SAND_DARK.r, SAND_DARK.g, SAND_DARK.b, 0.35), 1.2, true)
		"stepped":
			# Pressed flat: a shallow pit, and the boot that proved it safe.
			draw_colored_polygon(_blob(c, size.x * 0.44, size.y * 0.36), SAND_DARK)
			draw_colored_polygon(_blob(c + Vector2(0, 1),
				size.x * 0.38, size.y * 0.30, 12),
				Color(SAND.r * 0.88, SAND.g * 0.88, SAND.b * 0.88))
			# Boot print: sole + heel, toed toward the finish (right).
			var sole := _blob(c + Vector2(3, -2), size.x * 0.14, size.y * 0.16, 10)
			draw_colored_polygon(sole, Color(0.38, 0.33, 0.25, 0.55))
			draw_colored_polygon(_blob(c + Vector2(-7, 2),
				size.x * 0.08, size.y * 0.09, 8), Color(0.38, 0.33, 0.25, 0.5))
		"blown":
			# The crater: scorched pit, soot rays, a few thrown clods.
			draw_colored_polygon(_blob(c, size.x * 0.46, size.y * 0.38), SAND_DARK)
			draw_colored_polygon(_blob(c, size.x * 0.34, size.y * 0.27, 12),
				Color(0.16, 0.13, 0.10))
			draw_colored_polygon(_blob(c + Vector2(0, 2),
				size.x * 0.20, size.y * 0.15, 10), Color(0.08, 0.07, 0.06))
			for i in range(7):
				var a := TAU * float(i) / 7.0 + rng.randf() * 0.4
				draw_line(c + Vector2(cos(a), sin(a) * 0.7) * size.x * 0.20,
					c + Vector2(cos(a), sin(a) * 0.7) * size.x * rng.randf_range(0.38, 0.52),
					Color(0.12, 0.10, 0.08, 0.7), 2.0, true)
			for _i in range(4):
				draw_circle(c + Vector2(rng.randf_range(-size.x * 0.4, size.x * 0.4),
					rng.randf_range(-size.y * 0.3, size.y * 0.34)), 1.6,
					Color(0.20, 0.17, 0.13), true, -1.0, true)
		"charge":
			# The honest show: the buried powder button, uncovered.
			draw_colored_polygon(_blob(c, size.x * 0.44, size.y * 0.36), SAND)
			draw_colored_polygon(_blob(c + Vector2(0, 1),
				size.x * 0.26, size.y * 0.20, 10), SAND_DARK)
			draw_circle(c, size.x * 0.11, Color(0.14, 0.12, 0.10), true, -1.0, true)
			draw_circle(c + Vector2(-1.5, -1.5), size.x * 0.045,
				Color(0.45, 0.42, 0.38), true, -1.0, true)
			# The fuse thread.
			draw_line(c + Vector2(size.x * 0.06, -size.y * 0.06),
				c + Vector2(size.x * 0.18, -size.y * 0.20),
				Color(0.30, 0.26, 0.20), 1.6, true)
	if flagged:
		# The derby crowd's chalk flag: a stroke and a pennant.
		var base := Vector2(c.x + size.x * 0.24, c.y + size.y * 0.20)
		var top := base + Vector2(4, -size.y * 0.62)
		draw_line(base, top, Color(0.90, 0.90, 0.86, 0.95), 2.2, true)
		draw_colored_polygon(PackedVector2Array([top,
			top + Vector2(13, 4), top + Vector2(0, 9)]),
			Color(0.90, 0.90, 0.86, 0.92))
