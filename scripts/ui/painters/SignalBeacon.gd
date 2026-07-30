## SignalBeacon — one cresset in The Signal Line (signal_game). An iron
## fire-basket on a standard: lit = a warm flame + halo, dark = cold
## coals and a thread of smoke. The engine flips `lit` and pops `flare`
## (0..1) on a toggle for the catch-of-flame. Pure painter; the Event
## scene owns motion and hit-testing. (2026-07-20 craft pass: riveted
## strap basket instead of a trapezoid, a standard with feet, and the
## house tracer flame — white-hot core inside the ember tongue.)
extends Control

var seed_text := "beacon"
var lit := false
var flare := 0.0   # 0..1 toggle pop, engine-tweened
var preview := false   # hover-telegraph: this beacon would flip on the strike

const IRON := Color(0.205, 0.180, 0.155)
const IRON_LIT := Color(0.44, 0.38, 0.31)
const IRON_EDGE := Color(0.065, 0.058, 0.050)
const COAL := Color(0.15, 0.12, 0.10)
const EMBER := Color(0.72, 0.30, 0.12)
const FLAME_LO := Color(0.88, 0.42, 0.12)
const FLAME_MID := Color(0.98, 0.72, 0.28)
const FLAME_CORE := Color(1.0, 0.97, 0.86)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _tongue(cx: float, base_y: float, w: float, fh: float, swayx: float,
		lobes: int) -> PackedVector2Array:
	# A licked flame outline: rounded base, waisted middle, a leaning tip.
	var pts := PackedVector2Array()
	pts.append(Vector2(cx - w * 0.5, base_y))
	pts.append(Vector2(cx - w * 0.46, base_y - fh * 0.28))
	if lobes > 1:
		pts.append(Vector2(cx - w * 0.30, base_y - fh * 0.40))
		pts.append(Vector2(cx - w * 0.34, base_y - fh * 0.62))
	pts.append(Vector2(cx - w * 0.12, base_y - fh * 0.72))
	pts.append(Vector2(cx + swayx, base_y - fh))
	pts.append(Vector2(cx + w * 0.16, base_y - fh * 0.60))
	if lobes > 1:
		pts.append(Vector2(cx + w * 0.36, base_y - fh * 0.52))
		pts.append(Vector2(cx + w * 0.28, base_y - fh * 0.34))
	pts.append(Vector2(cx + w * 0.46, base_y - fh * 0.24))
	pts.append(Vector2(cx + w * 0.5, base_y))
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 12.0:
		return
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# Hover-telegraph: a dashed ring marking a cresset a strike would flip.
	if preview:
		var pc := Color(0.96, 0.86, 0.52, 0.85)
		draw_arc(Vector2(cx, h * 0.44), w * 0.44, 0.0, TAU, 22, pc, 2.0, true)
	# Warm halo behind a lit cresset — double layer, breathing with flare.
	if lit:
		draw_circle(Vector2(cx, h * 0.40), w * (0.66 + 0.12 * flare),
			Color(EMBER.r, EMBER.g, EMBER.b, 0.10 + 0.10 * flare), true, -1.0, true)
		draw_circle(Vector2(cx, h * 0.42), w * (0.44 + 0.08 * flare),
			Color(FLAME_MID.r, FLAME_MID.g, FLAME_MID.b, 0.10 + 0.12 * flare),
			true, -1.0, true)

	# ── the standard: contact shadow, feet, shaft with a collar ─────────
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - w * 0.20, h * 0.965), Vector2(cx + w * 0.20, h * 0.965),
		Vector2(cx + w * 0.15, h * 0.995), Vector2(cx - w * 0.15, h * 0.995)]),
		Color(0, 0, 0, 0.30))
	for s in [-1.0, 1.0]:
		draw_line(Vector2(cx, h * 0.86), Vector2(cx + s * w * 0.16, h * 0.965),
			IRON, 3.2, true)
		draw_line(Vector2(cx, h * 0.86), Vector2(cx + s * w * 0.16, h * 0.965),
			Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.30), 1.2, true)
	draw_line(Vector2(cx, h * 0.60), Vector2(cx, h * 0.90), IRON, 4.0, true)
	draw_line(Vector2(cx - 1.2, h * 0.60), Vector2(cx - 1.2, h * 0.90),
		Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.45), 1.2, true)
	# Collar bead on the shaft.
	draw_rect(Rect2(cx - 3.5, h * 0.72, 7.0, 3.0), IRON_LIT)
	draw_rect(Rect2(cx - 3.5, h * 0.72 + 2.2, 7.0, 1.0), IRON_EDGE)

	# ── the basket: strapped iron bowl with rivets and a rim bar ────────
	var top_y := h * 0.46
	var bot_y := h * 0.635
	var bowl := PackedVector2Array([
		Vector2(cx - w * 0.30, top_y), Vector2(cx + w * 0.30, top_y),
		Vector2(cx + w * 0.20, bot_y), Vector2(cx - w * 0.20, bot_y)])
	draw_colored_polygon(bowl, IRON_LIT if lit else IRON)
	# Vertical straps.
	for i in range(5):
		var t := float(i) / 4.0
		var x0 := cx - w * 0.27 + w * 0.54 * t
		var x1 := cx - w * 0.18 + w * 0.36 * t
		draw_line(Vector2(x0, top_y + 1), Vector2(x1, bot_y - 1), IRON_EDGE, 2.0, true)
	# One horizontal belly strap with rivets.
	var belly := lerpf(top_y, bot_y, 0.52)
	draw_line(Vector2(cx - w * 0.255, belly), Vector2(cx + w * 0.255, belly),
		IRON_EDGE, 2.2, true)
	for i in range(3):
		var t2 := float(i) / 2.0
		draw_circle(Vector2(cx - w * 0.21 + w * 0.42 * t2, belly), 1.4,
			Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.9), true, -1.0, true)
	# Rim bar: the basket's mouth, lit by the fire it holds.
	draw_line(Vector2(cx - w * 0.31, top_y), Vector2(cx + w * 0.31, top_y),
		IRON_EDGE, 2.6, true)
	if lit:
		draw_line(Vector2(cx - w * 0.28, top_y - 1.0), Vector2(cx + w * 0.28, top_y - 1.0),
			Color(FLAME_MID.r, FLAME_MID.g, FLAME_MID.b, 0.55), 1.6, true)

	if lit:
		# ── the tracer flame: ember tongue → gold body → white-hot core ──
		var base_y := top_y + 2.0
		var fh := h * (0.34 + 0.07 * flare)
		var swayx := (rng.randf() - 0.5) * w * 0.10
		draw_colored_polygon(_tongue(cx, base_y, w * 0.46, fh, swayx, 2), FLAME_LO)
		draw_colored_polygon(_tongue(cx + swayx * 0.2, base_y, w * 0.30,
			fh * 0.74, swayx * 0.7, 2), FLAME_MID)
		draw_colored_polygon(_tongue(cx + swayx * 0.35, base_y, w * 0.15,
			fh * 0.46, swayx * 0.45, 1),
			FLAME_CORE.lerp(Color(1, 1, 1), flare * 0.5))
		# Coal glow at the flame root.
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w * 0.22, base_y), Vector2(cx + w * 0.22, base_y),
			Vector2(cx + w * 0.14, base_y + 4.0), Vector2(cx - w * 0.14, base_y + 4.0)]),
			Color(EMBER.r, EMBER.g, EMBER.b, 0.75))
		# Sparks spitting up.
		for i in range(3):
			var ex := cx + (rng.randf() - 0.5) * w * 0.34
			var ey := base_y - fh * rng.randf_range(0.5, 1.15)
			draw_circle(Vector2(ex, ey), rng.randf_range(1.0, 1.7),
				Color(FLAME_CORE.r, FLAME_CORE.g, FLAME_CORE.b, 0.85), true, -1.0, true)
	else:
		# Cold: heaped coals with one dying ember eye, and a smoke thread.
		for i in range(5):
			var cp := Vector2(cx - w * 0.16 + w * 0.08 * float(i),
				top_y + 3.0 + (1.5 if i % 2 == 0 else 0.0))
			draw_circle(cp, 3.0, COAL, true, -1.0, true)
			draw_arc(cp, 3.0, PI * 1.1, PI * 1.9, 6, Color(0.32, 0.28, 0.24, 0.5),
				1.0, true)
		draw_circle(Vector2(cx + w * 0.06, top_y + 4.0), 1.2,
			Color(EMBER.r, EMBER.g, EMBER.b, 0.55), true, -1.0, true)
		var sm := PackedVector2Array()
		for i in range(5):
			var t := float(i) / 4.0
			sm.append(Vector2(cx - t * w * 0.10 + sin(t * 5.0) * 2.0,
				top_y - t * h * 0.16))
		draw_polyline(sm, Color(0.5, 0.5, 0.5, 0.16), 2.0, true)
