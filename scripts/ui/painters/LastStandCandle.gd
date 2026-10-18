extends Control
## LAST STAND CANDLE — one life, held in one visible flame.
##
## The old event-scale CandleStub was never suitable for a battlefield token:
## shrinking a detailed prop made its flame sub-pixel and its dish look like a
## stat orb. This purpose-built costume is a sparse 44x68 silhouette with a
## broad flame, keyed wax column, and bracket-like dish. Card2D extinguishes it
## the instant Last Stand is consumed.
##
## Pure painter: no process loop or idle flicker. The flame is animated only by
## Card2D and therefore respects Reduce Motion there.

var seed_text := "last_stand"
var flame_strength := 1.0:
	set(v):
		flame_strength = clampf(v, 0.0, 1.0)
		queue_redraw()

const INK := Color(0.07, 0.045, 0.025, 0.96)
const BRASS_DARK := Color(0.24, 0.17, 0.075, 1.0)
const BRASS := Color(0.58, 0.43, 0.17, 1.0)
const BRASS_LIT := Color(0.90, 0.72, 0.34, 0.92)
const WAX := Color(0.88, 0.80, 0.61, 1.0)
const WAX_LIT := Color(1.0, 0.95, 0.82, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


func _draw() -> void:
	if size.x < 30.0 or size.y < 46.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	var s := minf(size.x / 44.0, size.y / 68.0)
	var cx := size.x * 0.5
	var dish_y := size.y - 10.0 * s
	var column_bottom := dish_y - 3.0 * s
	var column_top := column_bottom - 25.0 * s
	var half_w := 7.5 * s
	var lean := rng.randf_range(-1.1, 1.1) * s

	# Cast shadow, then a thick slotted dish. Its wide horizontal bracket is a
	# different silhouette from every circular stat seal on the token.
	_ellipse(Vector2(cx + 1.5 * s, dish_y + 5.0 * s), 18.5 * s, 5.0 * s,
		Color(0.0, 0.0, 0.0, 0.58))
	_ellipse(Vector2(cx, dish_y + 2.0 * s), 18.0 * s, 5.0 * s, BRASS_DARK)
	_ellipse(Vector2(cx, dish_y), 18.0 * s, 4.4 * s, BRASS)
	_ellipse(Vector2(cx - 2.0 * s, dish_y - 1.0 * s), 12.0 * s, 2.2 * s,
		BRASS_LIT)

	# Wobbled but broad wax column. The ink keyline preserves the object on pale
	# art; the wax highlight preserves it on dark art.
	var body := PackedVector2Array([
		Vector2(cx - half_w, column_bottom),
		Vector2(cx - half_w + lean * 0.2, column_top + 3.0 * s),
		Vector2(cx - half_w * 0.72 + lean, column_top),
		Vector2(cx + half_w * 0.72 + lean, column_top),
		Vector2(cx + half_w + lean * 0.2, column_bottom),
	])
	draw_colored_polygon(body, INK)
	var inner := PackedVector2Array([
		Vector2(cx - half_w + 1.8 * s, column_bottom - 1.2 * s),
		Vector2(cx - half_w + 2.0 * s + lean * 0.2, column_top + 3.2 * s),
		Vector2(cx - half_w * 0.60 + lean, column_top + 1.8 * s),
		Vector2(cx + half_w * 0.58 + lean, column_top + 1.8 * s),
		Vector2(cx + half_w - 1.8 * s + lean * 0.2, column_bottom - 1.2 * s),
	])
	draw_colored_polygon(inner, WAX)
	draw_line(Vector2(cx - half_w * 0.33 + lean, column_top + 3.0 * s),
		Vector2(cx - half_w * 0.42, column_bottom - 2.0 * s),
		WAX_LIT, 2.0 * s, true)
	# One heavy drip: readable punctuation, not event-prop microdetail.
	draw_line(Vector2(cx + half_w * 0.55 + lean, column_top + 2.0 * s),
		Vector2(cx + half_w * 0.58, column_top + 12.0 * s),
		WAX_LIT, 3.2 * s, true)
	draw_circle(Vector2(cx + half_w * 0.58, column_top + 12.0 * s),
		2.0 * s, WAX_LIT)

	var wick_base := Vector2(cx + lean, column_top + 1.0 * s)
	draw_line(wick_base, wick_base + Vector2(0.8, -6.0) * s, INK, 2.0 * s, true)
	var f := flame_strength
	if f <= 0.02:
		# The spent state is visually immediate during the short removal beat.
		draw_circle(wick_base + Vector2(0.8, -6.0) * s, 1.8 * s,
			Color(0.18, 0.15, 0.12, 0.9))
		return

	var flame_base := wick_base + Vector2(0.8, -5.0) * s
	var flame_h := (18.0 + 3.0 * f) * s * f
	# Dark keyline first: the flame remains a flame when colour is removed.
	var outer := PackedVector2Array([
		flame_base + Vector2(-6.0, 1.0) * s,
		flame_base + Vector2(-5.4, -flame_h * 0.47),
		flame_base + Vector2(1.2, -flame_h),
		flame_base + Vector2(5.5, -flame_h * 0.45),
		flame_base + Vector2(6.0, 1.0) * s,
	])
	draw_colored_polygon(outer, INK)
	var warm := PackedVector2Array([
		flame_base + Vector2(-4.1, 0.0) * s,
		flame_base + Vector2(-3.3, -flame_h * 0.43),
		flame_base + Vector2(1.0, -flame_h + 2.0 * s),
		flame_base + Vector2(3.5, -flame_h * 0.41),
		flame_base + Vector2(4.1, 0.0) * s,
	])
	draw_colored_polygon(warm, Color(1.0, 0.62, 0.16, 0.98))
	var core := PackedVector2Array([
		flame_base + Vector2(-2.0, -0.3) * s,
		flame_base + Vector2(0.5, -flame_h * 0.62),
		flame_base + Vector2(2.0, -0.3) * s,
	])
	draw_colored_polygon(core, Color(1.0, 0.96, 0.78, 1.0))
