extends Control
## A compact illuminated record of the route just conquered. Used on boss
## rewards before RunState.advance_act clears the old campaign leg.

var _stops: Array[String] = []
var _accent := Color(0.82, 0.60, 0.24)
var _reveal := 1.0


func configure(act_map: Array, color: Color) -> void:
	_stops.clear()
	_accent = color
	for row in act_map:
		for node in row:
			if bool(node.get("visited", false)):
				_stops.append(String(node.get("type", "")))
				break
	custom_minimum_size = Vector2(760, 72)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if UserSettings != null and UserSettings.reduce_motion:
		_reveal = 1.0
		queue_redraw()
		return
	_reveal = 0.0
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_reveal = v
		queue_redraw(), 0.0, 1.0, 0.82) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if _stops.is_empty():
		return
	var y := size.y * 0.5
	var x0 := 34.0
	var x1 := size.x - 34.0
	var total := maxf(x1 - x0, 1.0)
	var end_x := lerpf(x0, x1, _reveal)
	# The old road remains as a blind-debossed rule; the conquered portion inks
	# itself in from camp to keep.
	draw_line(Vector2(x0, y), Vector2(x1, y),
		Color(0.48, 0.40, 0.28, 0.24), 7.0, true)
	draw_line(Vector2(x0, y), Vector2(end_x, y),
		Color(_accent.r, _accent.g, _accent.b, 0.86), 3.0, true)
	var count := _stops.size()
	for i in range(count):
		var t := 1.0 if count == 1 else float(i) / float(count - 1)
		if t > _reveal + 0.025:
			continue
		var p := Vector2(x0 + total * t, y)
		var kind := _stops[i]
		var col := Color(0.92, 0.78, 0.44)
		if kind == "elite":
			var diamond := PackedVector2Array([
				p + Vector2(0, -8), p + Vector2(8, 0),
				p + Vector2(0, 8), p + Vector2(-8, 0)])
			draw_colored_polygon(diamond, Color(0.66, 0.19, 0.12))
			draw_polyline(PackedVector2Array([
				diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]),
				Color(0.98, 0.75, 0.34), 1.4, true)
		elif kind == "boss":
			draw_circle(p + Vector2(2, 2), 12.0, Color(0, 0, 0, 0.28), true, -1.0, true)
			draw_circle(p, 12.0, Color(0.54, 0.09, 0.065), true, -1.0, true)
			draw_arc(p, 8.0, 0, TAU, 24, Color(1.0, 0.70, 0.30), 2.0, true)
		else:
			draw_circle(p + Vector2(1.5, 1.5), 6.0, Color(0, 0, 0, 0.26), true, -1.0, true)
			draw_circle(p, 6.0, col, true, -1.0, true)
	# The standard travels on the writing edge while the route reveals.
	var head := Vector2(end_x, y)
	draw_line(head + Vector2(0, 5), head + Vector2(0, -20),
		Color(0.13, 0.08, 0.045), 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(0, -20), head + Vector2(20, -18),
		head + Vector2(13, -12), head + Vector2(20, -7),
		head + Vector2(0, -9)]), _accent)
