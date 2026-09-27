## TablePlate — extracted from Combat.gd (backend restructure 2026-07-14).
## The war-table surface: a faded campaign chart inked straight onto the
## scorched table the battle is fought across — a double-ruled coast with
## sea hatching, dashed march routes, site rings, a compass, cup stains,
## and the burn creeping in along the clash band and the edges (heavier in
## later acts: the war eats the map). Seeded per encounter+act, so every
## fight's table is its own document but stable across rebuilds. Drawn
## once — sits between the dark substrate and the lane tracks.
##
## THE INK BOILS (▲1, docs/TECHNIQUE_HUNT_20260902.md). It used to be drawn once
## and frozen for the whole fight, which is the one thing a hand-inked chart
## cannot be: a line that never moves is printed, not drawn. Three seeded
## drawings now cycle on twos at 8 fps with ±0.6 px of displacement on the
## control points.
##
## WHAT BOILS AND WHAT DOES NOT is a material judgement, not a perf one. The
## LINE WORK boils — the coast, the sea hatching, the march routes, the site
## rings, the compass — because a hand redrew each of them. The BURN and the CUP
## STAINS do not: a scorch and a spill are not draughtsmanship, and wobbling them
## reads as a crawling texture rather than as ink. The lane grid outside this
## painter does not boil either, and that is the same distinction — the chart is
## hand-drawn, the grid is the printed rule of the board.
##
## The composition itself is unchanged: `_draw` reseeds its RNG from `seed_text`
## every pass, so all three drawings are the SAME chart, displaced. The boil comes
## only from `Motion.boil_offset`, which is a pure function of (point, variant).
extends Control

var seed_text := "table"
var act := 1

var _boil_v := 0          # which of the three drawings is showing
var _boil_t := 0.0
var _boil_i := 0          # running control-point index, reset each _draw
# The table used to leave ~80 procedural Canvas draw commands resident for the
# renderer to replay on EVERY combat frame. A full board therefore paid for the
# chart even while absolutely nothing about its geometry changed; the 8 fps boil
# additionally re-recorded all of those commands. Render the three authored
# drawings once into one transient atlas, then the live board is a single quad.
# The atlas belongs to this fight (no global pin), so it is released at scene exit.
var bake_mode := false     # offscreen clones draw the vector source, never recurse
var _baked_atlas: ImageTexture = null
var _baked_frame_px := Vector2i.ZERO
var _baked_for_size := Vector2i.ZERO
var _bake_busy := false
var _bake_generation := 0




func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The ONE permanent latch, and it is permanent because it cannot change at
	# runtime: a headless process has nothing to draw to, ever.
	set_process(DisplayServer.get_name() != "headless" and not bake_mode)
	if not bake_mode and DisplayServer.get_name() != "headless":
		resized.connect(_schedule_snapshot_bake)
		_schedule_snapshot_bake.call_deferred()


func _schedule_snapshot_bake() -> void:
	if bake_mode or DisplayServer.get_name() == "headless" \
			or size.x < 4.0 or size.y < 4.0:
		return
	var wanted := Vector2i(roundi(size.x), roundi(size.y))
	if _baked_atlas != null and wanted == _baked_for_size:
		return
	_bake_generation += 1
	if not _bake_busy:
		_bake_snapshots(_bake_generation)


## Capture the three boil drawings into one horizontal atlas. The Compatibility
## renderer has no pipeline baker, so this also warms the exact Canvas path that
## the fight will use. UPDATE_ONCE prevents an invisible bake viewport from
## continuing to render after its requested frame.
func _bake_snapshots(generation: int) -> void:
	_bake_busy = true
	# Anchored Controls can receive several resize notifications while their first
	# container layout settles. One frame coalesces them into the final board rect.
	await get_tree().process_frame
	if not is_inside_tree() or generation != _bake_generation:
		_bake_busy = false
		if is_inside_tree():
			_bake_snapshots(_bake_generation)
		return
	var logical_size := Vector2i(roundi(size.x), roundi(size.y))
	var frames: Array[Image] = []
	for variant in range(3):
		var image: Image = await _bake_variant(variant, logical_size)
		if not is_inside_tree():
			return
		if generation != _bake_generation:
			_bake_busy = false
			_bake_snapshots(_bake_generation)
			return
		if image == null or image.is_empty():
			_bake_busy = false
			return
		frames.append(image)
	var frame_size: Vector2i = frames[0].get_size()
	var atlas := Image.create(frame_size.x * frames.size(), frame_size.y,
		false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for i in range(frames.size()):
		atlas.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(frame_size.x * i, 0))
	_baked_atlas = ImageTexture.create_from_image(atlas)
	_baked_frame_px = frame_size
	_baked_for_size = logical_size
	_bake_busy = false
	queue_redraw()


func _bake_variant(variant: int, logical_size: Vector2i) -> Image:
	var sub := SubViewport.new()
	sub.size = logical_size
	sub.disable_3d = true
	sub.transparent_bg = true
	sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var clone = (get_script() as Script).new()
	clone.bake_mode = true
	clone.seed_text = seed_text
	clone.act = act
	clone._boil_v = variant
	clone.size = Vector2(logical_size)
	sub.add_child(clone)
	add_child(sub)
	# Let the clone enter, resolve its Control size and record the custom drawing.
	for _i in 2:
		await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(sub):
			return null
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or not is_instance_valid(sub):
		return null
	var viewport_texture: Texture2D = sub.get_texture()
	if viewport_texture == null:
		sub.queue_free()
		return null
	var image := viewport_texture.get_image()
	sub.queue_free()
	return image


## Decorative by the house contract, so Reduce Motion holds drawing 0 — and
## because variant 0 is the undisplaced one, holding it renders precisely the
## chart this painter drew before the boil existed.
func _process(delta: float) -> void:
	# REDUCE MOTION HOLDS, IT DOES NOT STOP.
	#
	# The first version called `set_process(false)` here, which was a one-way
	# latch: the settings overlay opens over a live board, so a player who turned
	# Reduce Motion on and then back OFF got a chart that never breathed again for
	# the rest of the fight. Nothing would have reported it — the ink simply
	# stopped. Holding costs one bool per frame on one node, which is far less
	# than the redraw it is guarding.
	if UserSettings != null and UserSettings.reduce_motion:
		if _boil_v != 0:
			_boil_v = 0
			queue_redraw()
		return
	_boil_t += delta
	var v := Motion.boil_variant(_boil_t)
	if v != _boil_v:
		_boil_v = v
		queue_redraw()


## Displace one control point. `_boil_i` advances per point so neighbours on the
## same polyline move independently — a shared offset would translate the whole
## line, which is a shake.
func _b(p: Vector2) -> Vector2:
	_boil_i += 1
	return p + Motion.boil_offset(_boil_i, _boil_v)

func _coast_y(t: float, y0: float, amp: float, ph1: float, ph2: float) -> float:
	return y0 + sin(t * 4.2 + ph1) * amp * 0.55 + sin(t * 9.7 + ph2) * amp * 0.30

func _draw() -> void:
	if size.x < 80.0 or size.y < 80.0:
		return
	if not bake_mode and _baked_atlas != null \
			and _baked_frame_px.x > 0 and _baked_frame_px.y > 0:
		var frame := clampi(_boil_v, 0, 2)
		draw_texture_rect_region(_baked_atlas, Rect2(Vector2.ZERO, size),
			Rect2(Vector2(frame * _baked_frame_px.x, 0),
				Vector2(_baked_frame_px)))
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	_boil_i = 0
	var ink := Color(0.74, 0.58, 0.34)
	# 1 — the coast: a double-ruled wandering line (the chart idiom).
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var y0 := size.y * (0.30 + rng.randf() * 0.40)
	var amp := size.y * 0.14
	var coast := PackedVector2Array()
	var n := 26
	for i in range(n + 1):
		var t := float(i) / float(n)
		coast.append(_b(Vector2(t * size.x, _coast_y(t, y0, amp, ph1, ph2))))
	draw_polyline(coast, Color(ink.r, ink.g, ink.b, 0.15), 2.2, true)
	# The second rule is a SEPARATE pass of the pen, so it gets its own
	# displacement rather than inheriting the first line's — two hand-drawn
	# parallel rules never wobble in lockstep, and inheriting reads as one thick
	# line rather than two.
	var coast2 := PackedVector2Array()
	for p in coast:
		coast2.append(_b(p + Vector2(0, 6)))
	draw_polyline(coast2, Color(ink.r, ink.g, ink.b, 0.09), 1.1, true)
	# Sea hatching seaward of the coast.
	for i in range(26):
		var t := rng.randf()
		var hy := _coast_y(t, y0, amp, ph1, ph2) + 12.0 + rng.randf() * 46.0
		if hy > size.y - 8.0:
			continue
		draw_line(_b(Vector2(t * size.x, hy)),
			_b(Vector2(t * size.x + 10.0 + rng.randf() * 8.0, hy)),
			Color(ink.r, ink.g, ink.b, 0.055 + rng.randf() * 0.04), 1.0, true)
	# 2 — march routes: two dashed tracks wandering across the land.
	for r in range(2):
		var ry := size.y * (0.12 + rng.randf() * 0.66)
		var rph := rng.randf() * TAU
		var seg_on := true
		var x := rng.randf() * 40.0
		while x < size.x - 12.0:
			var x2 := minf(x + 14.0, size.x - 8.0)
			if seg_on:
				var ya := ry + sin(x / size.x * 5.0 + rph) * size.y * 0.05
				var yb := ry + sin(x2 / size.x * 5.0 + rph) * size.y * 0.05
				draw_line(_b(Vector2(x, ya)), _b(Vector2(x2, yb)),
					Color(ink.r, ink.g, ink.b, 0.115), 1.4, true)
			seg_on = not seg_on
			x = x2
	# 3 — site rings: held positions marked on the chart.
	for i in range(5):
		# A ring this small (r 4–9) is one stroke of the pen, so it is displaced
		# as a whole — per-vertex wobble on a 4 px circle is noise, not a hand.
		# Its dot is a SECOND touch of the nib and gets its own offset.
		var p := _b(Vector2(rng.randf() * size.x, rng.randf() * size.y))
		draw_arc(p, 4.0 + rng.randf() * 5.0, 0, TAU, 18,
			Color(ink.r, ink.g, ink.b, 0.13), 1.2, true)
		draw_circle(_b(p), 1.2, Color(ink.r, ink.g, ink.b, 0.16), true, -1.0, true)
	# 4 — compass cross, upper-right quadrant.
	var cp := Vector2(size.x * (0.74 + rng.randf() * 0.16),
		size.y * (0.12 + rng.randf() * 0.14))
	var cr := 16.0 + rng.randf() * 8.0
	# Three strokes: the rose, then each arm. Each gets its own displacement at
	# both ends, so the cross swims very slightly against its own circle.
	draw_arc(_b(cp), cr, 0, TAU, 26, Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
	draw_line(_b(cp + Vector2(0, -cr * 1.45)), _b(cp + Vector2(0, cr * 1.45)),
		Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
	draw_line(_b(cp + Vector2(-cr * 1.45, 0)), _b(cp + Vector2(cr * 1.45, 0)),
		Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
	# 5 — cup ring stains: someone set their drink on the orders.
	# NOT boiled, and NOT for cost: a spill is not draughtsmanship. Nobody
	# redrew it, so nothing about it should move.
	for i in range(2):
		var sp := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var a0 := rng.randf() * TAU
		draw_arc(sp, 13.0 + rng.randf() * 9.0, a0, a0 + TAU * 0.8, 30,
			Color(0.30, 0.20, 0.10, 0.10), 2.6, true)
	# 6 — the burn: scorch along the clash band + creeping from the
	# top/bottom edges; later acts burn hotter. Not boiled, same reason as the
	# stains — a scorch is damage to the paper, not a mark made on it. Wobbling
	# these large soft discs would read as a crawling texture and would be the
	# most visible thing on the board, which is exactly backwards.
	var burn := Color(0.04, 0.02, 0.012)
	for i in range(7 + act * 3):
		var bp: Vector2
		if rng.randf() < 0.55:
			bp = Vector2(rng.randf() * size.x,
				size.y * 0.5 + (rng.randf() - 0.5) * size.y * 0.16)
		else:
			bp = Vector2(rng.randf() * size.x,
				size.y * (0.04 + 0.92 * float(rng.randi() % 2)) \
				+ (rng.randf() - 0.5) * size.y * 0.07)
		var br := 14.0 + rng.randf() * 34.0
		draw_circle(bp, br, Color(burn.r, burn.g, burn.b,
			0.09 + rng.randf() * 0.11), true, -1.0, true)
		draw_circle(bp, br * 0.55, Color(burn.r, burn.g, burn.b,
			0.08 + rng.randf() * 0.10), true, -1.0, true)
