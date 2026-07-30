## LaneAftermath — S5 of docs/SPELL_FX_PLAN_20260717.md.
## The persistent spells lived on as mechanics and VANISHED as visuals: a
## salted lane blocked enemy arrivals with nothing on the table saying so, a
## condemned column had no writ hanging over it, and dug wolf-pits were
## forgotten the moment the info line faded. This paints the standing state on
## the war table itself — children of the board container, so it all shakes in
## lockstep with the field (★6's contract).
##
## TWO INSTANCES of this one painter, split by z (shot-verified necessity):
##   ground (draw_marks=false) — salt stipple, the condemned column's wash and
##     jagged writ borders. Added before the lane rows: true ground, under
##     creatures and station furniture.
##   marks (draw_ground=false) — the quartermaster tags (salt pips, the noose)
##     and the covered pits: physical OBJECTS on the table. Added after the
##     clash-line beam, because the gold rule is painted late and covered
##     everything drawn at its own height in the first two cuts.
##
## INFORMATIONAL by the reduce-motion contract: carries live game state, so it
## always renders and holds steady — no pulsing. Combat rebuilds the spec via
## _refresh_lane_aftermath() at every state change; everything is seeded
## per-position so redraws never shimmer.
extends Control

# Spec set by Combat, in THIS control's local space:
#   salted:    [{"rect": Rect2, "rounds_left": int}]
#   condemned: [{"rect": Rect2, "tag_pos": Vector2}]
#   pits:      [Vector2]   (covered-pit centres, one per waiting charge)
var salted: Array = []
var condemned: Array = []
var pits: Array = []
var scars: Array = []
var draw_ground := true
var draw_marks := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(p_salted: Array, p_condemned: Array, p_pits: Array,
		p_scars: Array = []) -> void:
	salted = p_salted
	condemned = p_condemned
	pits = p_pits
	scars = p_scars
	queue_redraw()


func _draw() -> void:
	if draw_ground:
		for scar in scars:
			_draw_scar(scar)
	for s in salted:
		_draw_salted(s["rect"] as Rect2, int(s.get("rounds_left", 1)))
	for c in condemned:
		_draw_condemned(c["rect"] as Rect2,
			c.get("tag_pos", (c["rect"] as Rect2).get_center()) as Vector2)
	if draw_marks:
		for p in pits:
			_draw_pit(p as Vector2)



func _draw_scar(spec: Dictionary) -> void:
	# A death leaves quiet physical evidence for the rest of the fight. Nothing
	# animates: this is table history, not another effect competing for attention.
	var r: Rect2 = spec.get("rect", Rect2()) as Rect2
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var kind := String(spec.get("kind", "enemy"))
	var inset := r.grow(-maxf(5.0, minf(r.size.x, r.size.y) * 0.10))
	if kind == "gate":
		# Broken gate sections leave blocky masonry and two heavier arch shards.
		var stone := Color(0.43, 0.34, 0.24, 0.34)
		var edge := Color(0.12, 0.08, 0.05, 0.42)
		for i in range(11):
			var c := Vector2(rng.randf_range(inset.position.x, inset.end.x),
				rng.randf_range(inset.position.y, inset.end.y))
			var w := rng.randf_range(8.0, 20.0)
			var h := rng.randf_range(5.0, 12.0)
			var skew := rng.randf_range(-4.0, 4.0)
			var block := PackedVector2Array([
				c + Vector2(-w * 0.5, -h * 0.5),
				c + Vector2(w * 0.5, -h * 0.5 + skew),
				c + Vector2(w * 0.5, h * 0.5),
				c + Vector2(-w * 0.5, h * 0.5 - skew)])
			draw_colored_polygon(block, stone)
			draw_polyline(PackedVector2Array([
				block[0], block[1], block[2], block[3], block[0]]), edge, 1.0, true)
		for side in [-1.0, 1.0]:
			var ac := r.get_center() + Vector2(side * r.size.x * 0.20, r.size.y * 0.12)
			draw_arc(ac, r.size.x * 0.16, PI, TAU, 10,
				Color(0.50, 0.38, 0.25, 0.30), 3.0, true)
		return
	# Ordinary casualties leave a muted ash stain and scattered snapped gear.
	var ash := Color(0.18, 0.10, 0.07, 0.18) if kind == "enemy" \
		else Color(0.08, 0.12, 0.16, 0.17)
	draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.18, ash)
	var shard := Color(0.52, 0.39, 0.24, 0.28)
	for i in range(5):
		var p := Vector2(rng.randf_range(inset.position.x, inset.end.x),
			rng.randf_range(inset.position.y, inset.end.y))
		var d := Vector2.from_angle(rng.randf_range(0.0, TAU)) \
			* rng.randf_range(6.0, 15.0)
		draw_line(p - d * 0.5, p + d * 0.5, shard, rng.randf_range(1.0, 2.2), true)

func _draw_salted(r: Rect2, rounds_left: int) -> void:
	# Salt is SALT — bone-pale grains strewn over the earth, not a colour wash.
	# (The spell is blight-family for its cast FX, but the thing left on the
	# ground is white; purple ground would read as a puddle, not a curse.)
	if draw_ground:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(int(r.position.x), int(r.position.y)))
		draw_rect(r, Color(0.90, 0.87, 0.78, 0.05), true)
		# Grain drifts: denser along the centre line of the column, like a
		# hand sowing from a sack as it walked the row.
		for i in range(90):
			var gx: float = r.position.x + rng.randf() * r.size.x
			var pull: float = (r.position.x + r.size.x * 0.5 - gx) * 0.35
			var gy: float = r.position.y + rng.randf() * r.size.y
			var gp := Vector2(gx + pull * rng.randf(), gy)
			var ga: float = rng.randf_range(0.25, 0.62)
			draw_circle(gp, rng.randf_range(0.8, 1.9),
				Color(0.93, 0.90, 0.81, ga), true, -1.0, true)
		# A few short strewn streaks — thrown salt skids.
		for i in range(7):
			var sx: float = r.position.x + rng.randf() * (r.size.x - 14.0)
			var sy: float = r.position.y + rng.randf() * r.size.y
			draw_line(Vector2(sx, sy), Vector2(sx + rng.randf_range(6.0, 13.0),
				sy + rng.randf_range(-2.0, 2.0)),
				Color(0.90, 0.87, 0.78, 0.35), 1.2, true)
	if draw_marks:
		# Expiry pips ride a quartermaster's TAG at the column's foot. Two shot
		# lessons: the column TOP is covered by the encounter banner, and the
		# glyph needs its own dark canvas (the ★3 lesson, inverted — ADD the
		# canvas) or the table furniture washes it out.
		var pn: int = clampi(rounds_left, 1, 4)
		# +22 centres the tag on the clash rule — the marks layer draws over
		# the rule, and a chit tacked over the painted line is the diegesis.
		var tag_c := Vector2(r.position.x + r.size.x * 0.5, r.end.y + 22.0)
		_draw_table_tag(tag_c, Vector2(22.0 + float(pn) * 17.0, 30.0))
		for i in range(pn):
			var px: float = tag_c.x + (float(i) - (float(pn) - 1.0) * 0.5) * 17.0
			var pp := PackedVector2Array([
				Vector2(px, tag_c.y - 7.0), Vector2(px + 5.6, tag_c.y),
				Vector2(px, tag_c.y + 7.0), Vector2(px - 5.6, tag_c.y)])
			draw_colored_polygon(pp, Color(0.95, 0.92, 0.83, 0.97))


func _draw_table_tag(c: Vector2, sz: Vector2) -> void:
	# A small oiled-leather chit tacked to the table — the dark backing that
	# lets a pale glyph read over ANY furniture underneath (wood, gold rule,
	# station ink). Brass tack top-left, like the map sheet's corner pins.
	var r := Rect2(c - sz * 0.5, sz)
	draw_rect(r.grow(2.0), Color(0.0, 0.0, 0.0, 0.60), true)   # drop shadow
	draw_rect(r, Color(0.15, 0.10, 0.06, 0.97), true)
	draw_rect(r, Color(0.52, 0.38, 0.20, 0.95), false, 1.6, true)
	draw_circle(r.position + Vector2(6.0, 6.0), 2.6, Color(0.80, 0.64, 0.32, 1.0), true, -1.0, true)
	draw_circle(r.position + Vector2(5.3, 5.3), 1.2, Color(1.0, 0.94, 0.66, 1.0), true, -1.0, true)


func _draw_condemned(r: Rect2, tag_pos: Vector2) -> void:
	# The Gallows Writ hangs over the column: a blood-ink stain, a jagged
	# proclamation border, and the noose on a tag at the column's foot.
	if draw_ground:
		draw_rect(r, Color(0.34, 0.07, 0.05, 0.14), true)
		# Jagged writ border — hand-torn, not ruled. Deterministic zigzag.
		var ink := Color(0.62, 0.14, 0.10, 0.60)
		var step := 16.0
		var pts := PackedVector2Array()
		var x := r.position.x
		var flip := true
		while x < r.end.x:
			pts.append(Vector2(x, r.position.y + (2.0 if flip else 6.0)))
			flip = not flip
			x += step
		pts.append(Vector2(r.end.x, r.position.y + 2.0))
		draw_polyline(pts, ink, 1.8, true)
		var pts_b := PackedVector2Array()
		x = r.position.x
		flip = false
		while x < r.end.x:
			pts_b.append(Vector2(x, r.end.y - (2.0 if flip else 6.0)))
			flip = not flip
			x += step
		pts_b.append(Vector2(r.end.x, r.end.y - 2.0))
		draw_polyline(pts_b, ink, 1.8, true)
		draw_line(r.position + Vector2(2, 2), Vector2(r.position.x + 2, r.end.y - 2), ink, 1.8, true)
		draw_line(Vector2(r.end.x - 2, r.position.y + 2), r.end - Vector2(2, 2), ink, 1.8, true)
	if draw_marks:
		# The execution order's noose, big enough to survive 1× (the ~20px
		# icon-mush floor): loop ~26px across on a 52px tag.
		var rope := Color(0.78, 0.60, 0.35, 1.0)
		var rope_dark := Color(0.24, 0.16, 0.08, 0.95)
		var cx: float = tag_pos.x
		var cy: float = tag_pos.y
		_draw_table_tag(Vector2(cx, cy), Vector2(52.0, 46.0))
		var loop_c := Vector2(cx, cy + 7.0)
		draw_arc(loop_c, 13.0, 0.0, TAU, 26, rope, 3.4, true)
		draw_arc(loop_c, 8.6, PI * 0.15, PI * 0.85, 12, rope_dark, 2.0, true)
		# The knot at the loop's crown, coils stacked.
		for i in range(3):
			draw_line(Vector2(cx - 5.5, cy - 12.0 + float(i) * 3.4),
				Vector2(cx + 5.5, cy - 12.0 + float(i) * 3.4), rope, 2.6, true)


func _draw_pit(c: Vector2) -> void:
	# A covered wolf-pit: a black mouth under a lattice of FRESH-CUT branches.
	# First cut used aged-earth tones and vanished into the wood table — the
	# ink-spatter lesson again (camouflage): the read needs the pit's own
	# value contrast. Fresh-cut wood is PALE; a dug hole is BLACK. Both are
	# material-honest and both separate from the dark table.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(c.x), int(c.y)))
	# The mouth — a genuinely black ellipse (the one hole in the table).
	draw_set_transform(c, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 19.0, Color(0.015, 0.01, 0.008, 0.92), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Rim of freshly turned pale earth catching the lamplight.
	draw_arc(c + Vector2(0, -1.0), 19.0, PI * 1.02, PI * 1.98, 20,
		Color(0.62, 0.50, 0.32, 0.9), 2.8, true)
	# Fresh-cut branch lattice over the mouth — pale wood, bright cut ends.
	for i in range(5):
		var a: float = rng.randf_range(-0.45, 0.45) + (PI * 0.5 if i % 2 == 0 else 0.0)
		var l: float = rng.randf_range(13.0, 20.0)
		var d := Vector2(cos(a), sin(a) * 0.42) * l
		var o := Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-3.0, 3.0))
		draw_line(c + o - d, c + o + d,
			Color(0.80, 0.68, 0.46, rng.randf_range(0.8, 0.98)), 2.4, true)
		draw_circle(c + o + d, 1.5, Color(0.94, 0.86, 0.64, 0.95), true, -1.0, true)
	# One sharpened stake tip betraying the trap to its owner.
	draw_line(c + Vector2(-2.0, 4.0), c + Vector2(1.0, -7.0),
		Color(0.97, 0.90, 0.68, 1.0), 2.0, true)
