## StrongboxDial — one brass combination ward on the Fourth's paychest
## (box_game). A knurled dial mounted face-on to the iron faceplate; the
## engine overlays the numeral as a Label child and flips `active` for the
## ward currently under the hand. Pure painter; the Event scene owns motion.
extends Control

var active := false
var locked := false   # once cracked, the wards glow warm and hold

const IRON := Color(0.16, 0.15, 0.14)
const BRASS := Color(0.70, 0.57, 0.30)
const BRASS_LIT := Color(0.90, 0.76, 0.44)
const BRASS_DIM := Color(0.44, 0.34, 0.17)
const WELL := Color(0.11, 0.09, 0.07)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 2.0
	if r <= 8.0:
		return
	var c := size * 0.5
	var hot := active or locked
	# Iron mounting collar behind the dial.
	draw_circle(c + Vector2(0, 2), r + 3.0, Color(0, 0, 0, 0.35), true, -1.0, true)
	draw_circle(c, r + 2.0, IRON, true, -1.0, true)
	# Brass dial body, top-lit.
	draw_circle(c, r, BRASS_DIM, true, -1.0, true)
	draw_circle(c, r * 0.96, (BRASS_LIT if hot else BRASS).lerp(BRASS_LIT, 0.0), true, -1.0, true)
	draw_circle(c + Vector2(-r * 0.18, -r * 0.22), r * 0.62,
		Color(BRASS_LIT.r, BRASS_LIT.g, BRASS_LIT.b, 0.45), true, -1.0, true)
	# Knurled rim ticks.
	var n := 20
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.80, c + d * r * 0.94,
			Color(BRASS_DIM.r, BRASS_DIM.g, BRASS_DIM.b, 0.8), 1.4, true)
	# The numeral well (the engine's Label sits here).
	draw_circle(c, r * 0.60, WELL, true, -1.0, true)
	draw_arc(c, r * 0.60, 0.0, TAU, 28,
		Color(BRASS_DIM.r, BRASS_DIM.g, BRASS_DIM.b, 0.9), 1.6, true)
	# Active/locked halo.
	if hot:
		var col := Color(0.95, 0.78, 0.40) if locked else Color(0.86, 0.90, 0.96)
		draw_arc(c, r * 0.99, 0.0, TAU, 30, Color(col.r, col.g, col.b, 0.9),
			2.6, true)
	# The index notch at top — where the read line falls.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3, -r - 1), c + Vector2(3, -r - 1), c + Vector2(0, -r + 6)]),
		BRASS_LIT if hot else BRASS)
