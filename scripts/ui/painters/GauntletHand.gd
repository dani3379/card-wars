## GauntletHand — a thrown hand for the flash-of-fingers (the morra_game
## stage). Same school as EventHelm: table furniture, cabinet-projection
## contact shadow, seeded blob silhouette. `fingers` = how many are up
## (0 = the resting fist, drawn with a clenched-thumb knuckle ridge so it
## reads as a FIST, not a mound). `bony` draws the dead pikeman's hand;
## `maimed` caps the ring and little fingers as healed stubs — a maimed
## hand can only ever throw with index, middle, and thumb, which is the
## game's posted arithmetic, so the stubs must stay legible at 130px.
## Pure painter — the Event scene owns all motion; call queue_redraw()
## after changing `fingers`.
extends Control

var seed_text := "hand"
var fingers := 0
var bony := false
var maimed := false

const BONE := Color(0.885, 0.855, 0.775)
const SKIN := Color(0.780, 0.625, 0.470)
const INK := Color(0.20, 0.16, 0.11, 0.95)

# Extension order: a living hand counts index → little, thumb last; the
# maimed hand has only index, middle, and thumb left to count with.
const ORDER_FULL := ["index", "middle", "ring", "little", "thumb"]
const ORDER_MAIMED := ["index", "middle", "thumb"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _blob(center: Vector2, rx: float, ry: float, n: int = 18) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var amp := 0.045 + rng.randf() * 0.030
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + amp * sin(a * 3.0 + ph) + amp * 0.5 * sin(a * 7.0 + ph * 1.7)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry) * w)
	return pts


func _capsule(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * w * 0.5
	var pts := PackedVector2Array()
	for i in range(7):
		var t := PI * float(i) / 6.0
		pts.append(b + n.rotated(-t))
	for i in range(7):
		var t := PI * float(i) / 6.0
		pts.append(a + (-n).rotated(-t))
	return pts


func _draw_digit(a: Vector2, b: Vector2, w: float, flesh: Color) -> void:
	var pts := _capsule(a, b, w)
	draw_colored_polygon(pts, flesh)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INK, 1.8, true)
	# Joint creases — two faint lines across the digit; on the bony hand
	# they read as knuckle seams and sell the skeleton without more geometry.
	var seam := Color(0.42, 0.35, 0.26, 0.55) if not bony \
		else Color(0.55, 0.50, 0.40, 0.78)
	for t in [0.42, 0.70]:
		var p: Vector2 = a.lerp(b, t)
		var n := (b - a).normalized().orthogonal() * w * 0.34
		draw_line(p - n, p + n, seam, 1.2, true)
	# A cold rim of light up the left flank — the one lamp, answering.
	var lift := (b - a).normalized().orthogonal() * w * 0.38
	draw_line(a - lift + (b - a) * 0.12, b - lift * 0.6 + (a - b) * 0.10,
		Color(1, 1, 1, 0.22), 1.4, true)


func _draw() -> void:
	if minf(size.x, size.y) <= 20.0:
		return
	var u := size.x / 120.0
	var flesh := BONE if bony else SKIN
	var flesh_dark := Color(0.70, 0.66, 0.56) if bony else Color(0.58, 0.44, 0.32)
	# Ground pool — wide and flat, the table's one light overhead.
	var pool := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pool.append(Vector2(60.0 * u, 138.0 * u)
			+ Vector2(cos(a) * 48.0 * u, sin(a) * 10.0 * u))
	draw_colored_polygon(pool, Color(0, 0, 0, 0.32))
	# Cuff: leather for the living, a rotted sleeve for the dead.
	var cuff := PackedVector2Array([
		Vector2(36.0 * u, 106.0 * u), Vector2(84.0 * u, 106.0 * u),
		Vector2(92.0 * u, 140.0 * u), Vector2(28.0 * u, 140.0 * u)])
	draw_colored_polygon(cuff,
		Color(0.34, 0.30, 0.24) if bony else Color(0.32, 0.25, 0.18))
	draw_line(Vector2(36.0 * u, 108.0 * u), Vector2(84.0 * u, 108.0 * u),
		Color(1, 1, 1, 0.14), 2.0 * u, true)
	draw_line(Vector2(34.0 * u, 114.0 * u), Vector2(86.0 * u, 114.0 * u),
		Color(0, 0, 0, 0.35), 1.6 * u, true)
	# Which digits stand for this count.
	var order: Array = ORDER_MAIMED if maimed else ORDER_FULL
	var up: Array = order.slice(0, clampi(fingers, 0, order.size()))
	# Digit geometry (u-space): four finger slots across the palm top + the
	# thumb off the left side. Lengths differ so the count reads as a hand,
	# not a comb.
	var slots := {
		"index": [Vector2(43, 76), Vector2(40, 34), 11.5],
		"middle": [Vector2(57, 73), Vector2(57, 28), 12.0],
		"ring": [Vector2(71, 75), Vector2(73, 33), 11.0],
		"little": [Vector2(83, 79), Vector2(87, 46), 9.5],
		"thumb": [Vector2(38, 92), Vector2(16, 62), 12.5],
	}
	# Standing digits draw BEHIND the palm blob so their bases root inside it.
	for name in up:
		var g: Array = slots[name]
		_draw_digit((g[0] as Vector2) * u, (g[1] as Vector2) * u,
			(g[2] as float) * u, flesh)
	# The stubs — the maimed hand's two healed losses. Always shown on that
	# hand, up or down: they ARE the posted rule that he throws one to three.
	if maimed:
		for name in ["ring", "little"]:
			var g: Array = slots[name]
			var base: Vector2 = (g[0] as Vector2) * u
			var tip: Vector2 = base.lerp((g[1] as Vector2) * u, 0.34)
			_draw_digit(base, tip, (g[2] as float) * u, flesh_dark)
			# The healed seam across the cap.
			var dir := (tip - base).normalized()
			var n := dir.orthogonal() * (g[2] as float) * u * 0.44
			draw_line(tip - n, tip + n, INK, 2.0, true)
	# The fist/palm.
	var palm := _blob(Vector2(60.0 * u, 90.0 * u), 30.0 * u, 25.0 * u)
	draw_colored_polygon(palm, flesh)
	# Side shade pinches the palm the way the knucklebone waist does.
	draw_colored_polygon(_blob(Vector2(76.0 * u, 95.0 * u), 11.0 * u, 15.0 * u, 12),
		Color(flesh_dark.r, flesh_dark.g, flesh_dark.b, 0.38))
	var closed := palm.duplicate()
	closed.append(palm[0])
	draw_polyline(closed, INK, 2.0, true)
	# Lamplight along the palm's upper-left shoulder.
	draw_arc(Vector2(58.0 * u, 88.0 * u), 26.0 * u, PI * 1.05, PI * 1.75, 12,
		Color(1, 1, 1, 0.18), 2.4 * u, true)
	# Folded digits read as a knuckle RIDGE along the fist's top edge — four
	# hard bumps, inked, so the closed hand is a fist and not a loaf.
	for name in order:
		if name in up or (maimed and (name == "ring" or name == "little")):
			continue
		if name == "thumb":
			continue
		var g: Array = slots[name]
		var kx: float = (g[0] as Vector2).x * u
		var ky := 70.0 * u
		draw_circle(Vector2(kx, ky), 6.0 * u, flesh, true, -1.0, true)
		draw_arc(Vector2(kx, ky), 6.0 * u, PI * 0.95, TAU * 1.02, 10, INK, 1.8, true)
		draw_arc(Vector2(kx, ky - 1.0 * u), 4.2 * u, PI * 1.15, PI * 1.85, 8,
			Color(1, 1, 1, 0.20), 1.4, true)
	# The clenched thumb bars across the fist front when it is not thrown —
	# the closed hand's strongest tell.
	if not ("thumb" in up):
		var ta := Vector2(36.0 * u, 97.0 * u)
		var tb := Vector2(76.0 * u, 103.0 * u)
		var pts := _capsule(ta, tb, 11.0 * u)
		draw_colored_polygon(pts, flesh)
		var tcl := pts.duplicate()
		tcl.append(pts[0])
		draw_polyline(tcl, INK, 1.8, true)
		draw_line(Vector2(48.0 * u, 94.0 * u), Vector2(50.0 * u, 106.0 * u),
			Color(0, 0, 0, 0.25), 1.2, true)
	# Bony hands get tendon lines fanning over the back of the fist.
	if bony:
		for name in up:
			if name == "thumb":
				continue
			var g: Array = slots[name]
			draw_line(Vector2(60.0 * u, 98.0 * u), (g[0] as Vector2) * u,
				Color(0.58, 0.53, 0.43, 0.5), 1.4 * u, true)
