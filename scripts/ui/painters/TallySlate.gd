## TallySlate — the counting game's open book: a chalked slate showing how
## many chits of each value are still IN the satchel. `remaining` is the
## live array (index 0 = value 1); the Event scene updates it and calls
## queue_redraw(). This is the whole skill of the game made visible —
## the odds are never hidden, only unread. Pure painter.
extends Control

var seed_text := "slate"
var remaining: Array = [3, 3, 3, 3, 3, 3]

const SLATE := Color(0.130, 0.140, 0.145)
const FRAME := Color(0.240, 0.175, 0.110)
const CHALK := Color(0.870, 0.880, 0.860, 0.90)
const CHALK_DIM := Color(0.870, 0.880, 0.860, 0.28)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if minf(size.x, size.y) <= 30.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# Wood frame, slate face, a chalk rule under the header row.
	draw_rect(Rect2(Vector2(2, 6), size - Vector2(4, 8)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(Vector2.ZERO, size - Vector2(4, 4)), FRAME)
	draw_rect(Rect2(Vector2(5, 5), size - Vector2(14, 14)), SLATE)
	var cols := 6
	var x0 := 14.0
	var pitch := (size.x - 28.0) / float(cols)
	var head_y := 22.0
	draw_line(Vector2(10, head_y + 10), Vector2(size.x - 14, head_y + 10),
		CHALK_DIM, 1.5, true)
	for i in range(cols):
		var cx := x0 + pitch * (float(i) + 0.5)
		# Header: the value as chalk pips (a die face, not a numeral — the
		# slate speaks the same language as the chits).
		var v := i + 1
		var s := 4.6
		var offs: Array = []
		match v:
			1: offs = [Vector2.ZERO]
			2: offs = [Vector2(-s, -s), Vector2(s, s)]
			3: offs = [Vector2(-s, -s), Vector2.ZERO, Vector2(s, s)]
			4: offs = [Vector2(-s, -s), Vector2(s, -s), Vector2(-s, s), Vector2(s, s)]
			5: offs = [Vector2(-s, -s), Vector2(s, -s), Vector2.ZERO,
				Vector2(-s, s), Vector2(s, s)]
			6: offs = [Vector2(-s, -s), Vector2(s, -s), Vector2(-s, 0),
				Vector2(s, 0), Vector2(-s, s), Vector2(s, s)]
		for o in offs:
			draw_circle(Vector2(cx, head_y) + o, 1.7, CHALK, true, -1.0, true)
		# Tally strokes below: one chalk stroke per chit still in the bag,
		# rubbed-out stubs for the drawn ones.
		var have: int = 0
		if i < remaining.size():
			have = int(remaining[i])
		for j in range(3):
			var ty := head_y + 24.0 + float(j) * 14.0
			var lean := rng.randf_range(-1.5, 1.5)
			if j < have:
				draw_line(Vector2(cx - 4.0 + lean, ty),
					Vector2(cx + 4.0 - lean, ty + 9.0), CHALK, 2.2, true)
			else:
				draw_line(Vector2(cx - 3.0 + lean, ty + 3.0),
					Vector2(cx + 3.0 - lean, ty + 6.0), CHALK_DIM, 1.4, true)
