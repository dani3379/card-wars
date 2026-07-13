## StationMark — extracted from Combat.gd (backend restructure 2026-07-14).
## A unit station drawn ON the war chart: corner brackets, a hairline
## rule, a faint ownership wash, and a small center cross — positions
## marked on the map, not holes carved into it. Replaces the old full-size
## dark wells, which covered nearly the whole table and turned the board
## into 16 voids. The drawn marks stay quiet when empty and disappear
## behind a creature when filled; Highlight/ContactShadow/Cell (the slot's
## behavioral children) are untouched.
extends Control

var warm := true       # enemy half (warm) vs player half (cool) wash
var strong := true     # front row reads stronger than back

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if size.x < 20.0 or size.y < 20.0:
		return
	# Front and back rows now read as TWO DISTINCT station kinds rather than
	# the same mark at two opacities — the old back-row a_mul=0.62 just made
	# the rear line fade into the dark table. Front = a solid mustered post
	# (filled bracket corners, full wash, survey cross). Back = a reserve
	# bay drawn the same strength but as a dashed inset frame, so it reads as
	# "staging ground, not the firing line" by SHAPE, not by faintness.
	# Both are emphatic enough to parse the whole 4×4 grid before a fight.
	var wash := Color(0.52, 0.15, 0.10, 0.20) if warm \
		else Color(0.14, 0.27, 0.48, 0.20)
	var ink := Color(0.84, 0.68, 0.40)   # gilt rule ink
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), wash, true)
	# Hairline inset rule — the station footprint.
	draw_rect(Rect2(Vector2(3.5, 3.5), size - Vector2(7, 7)),
		Color(ink.r, ink.g, ink.b, 0.35), false, 1.0, true)
	if strong:
		# FRONT — corner brackets, the drawn firing-line post.
		var bk := Color(ink.r, ink.g, ink.b, 0.85)
		var L := 17.0
		for cx in [0.0, 1.0]:
			for cy in [0.0, 1.0]:
				var corner := Vector2(cx * size.x, cy * size.y)
				var dx := 1.0 if cx == 0.0 else -1.0
				var dy := 1.0 if cy == 0.0 else -1.0
				draw_line(corner + Vector2(0, dy * 1.5),
					corner + Vector2(dx * L, dy * 1.5), bk, 2.5, true)
				draw_line(corner + Vector2(dx * 1.5, 0),
					corner + Vector2(dx * 1.5, dy * L), bk, 2.5, true)
		# Survey cross — where this unit will stand.
		var c := size * 0.5
		var fc := Color(ink.r, ink.g, ink.b, 0.30)
		draw_line(c - Vector2(9, 0), c + Vector2(9, 0), fc, 1.5, true)
		draw_line(c - Vector2(0, 9), c + Vector2(0, 9), fc, 1.5, true)
	else:
		# BACK — a dashed reserve bay. Same ink weight as the front so it
		# stays legible, but the broken line says "staging, not line".
		var dash := Color(ink.r, ink.g, ink.b, 0.55)
		var rect := Rect2(Vector2(7, 7), size - Vector2(14, 14))
		var step := 11.0
		# Top + bottom dashed edges.
		var x := rect.position.x
		while x < rect.end.x:
			var x2: float = minf(x + 6.0, rect.end.x)
			draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), dash, 1.5, true)
			draw_line(Vector2(x, rect.end.y), Vector2(x2, rect.end.y), dash, 1.5, true)
			x += step
		# Left + right dashed edges.
		var y := rect.position.y
		while y < rect.end.y:
			var y2: float = minf(y + 6.0, rect.end.y)
			draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, y2), dash, 1.5, true)
			draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, y2), dash, 1.5, true)
			y += step
