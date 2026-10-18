extends Control
## Small reusable company standard used by the Spoils ceremony. Its physical
## additions are run history: wax seals for completed marches, ribbons for
## broken Generals, and mourning cloth when the Roll of the Fallen is nonempty.

var accent := Color(0.82, 0.60, 0.24)
var acts_won := 0
var generals_broken := 0
var fallen_count := 0
# The standard's many authored strokes never change while a Reward screen is
# open. Offscreen clones retain the vector source; the live painter swaps to a
# one-quad snapshot once that exact drawing has rendered.
var bake_mode := false
var _baked_texture: ImageTexture = null
var _baked_for_size := Vector2i.ZERO
var _bake_generation := 0


func configure(completed_acts: int, generals: int, fallen: int,
		banner_color: Color) -> void:
	acts_won = clampi(completed_acts, 0, 3)
	generals_broken = maxi(generals, 0)
	fallen_count = maxi(fallen, 0)
	accent = banner_color
	custom_minimum_size = Vector2(142, 104)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not bake_mode and DisplayServer.get_name() != "headless":
		resized.connect(_schedule_snapshot_bake)
		_schedule_snapshot_bake.call_deferred()
	queue_redraw()


func _schedule_snapshot_bake() -> void:
	if bake_mode or DisplayServer.get_name() == "headless" \
			or size.x < 4.0 or size.y < 4.0:
		return
	var wanted := Vector2i(roundi(size.x), roundi(size.y))
	if _baked_texture != null and wanted == _baked_for_size:
		return
	_bake_generation += 1
	_bake_snapshot(_bake_generation)


## Render the painter's exact vector commands once. Compatibility has no
## RenderingDevice pipeline baker, so a one-shot SubViewport is the portable
## path; at 142x104 its readback is tiny and happens under Reward's deal-in.
func _bake_snapshot(generation: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or generation != _bake_generation:
		return
	var logical_size := Vector2i(roundi(size.x), roundi(size.y))
	var sub := SubViewport.new()
	sub.size = logical_size
	sub.disable_3d = true
	sub.transparent_bg = true
	sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var source := (get_script() as Script).new() as Control
	source.set("bake_mode", true)
	source.set("accent", accent)
	source.set("acts_won", acts_won)
	source.set("generals_broken", generals_broken)
	source.set("fallen_count", fallen_count)
	source.size = Vector2(logical_size)
	sub.add_child(source)
	add_child(sub)
	# Give the clone one frame to enter and one to record its custom drawing.
	for _i in 2:
		await get_tree().process_frame
		if not is_inside_tree() or generation != _bake_generation \
				or not is_instance_valid(sub):
			if is_instance_valid(sub):
				sub.queue_free()
			return
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or generation != _bake_generation \
			or not is_instance_valid(sub):
		if is_instance_valid(sub):
			sub.queue_free()
		return
	var viewport_texture: Texture2D = sub.get_texture()
	var image: Image = viewport_texture.get_image() if viewport_texture != null else null
	sub.queue_free()
	if image == null or image.is_empty():
		return
	_baked_texture = ImageTexture.create_from_image(image)
	_baked_for_size = logical_size
	queue_redraw()


## ── THE CLOTH IS SHADED, NOT FILLED (2026-09-03) ────────────────────────────
##
## This was one flat `draw_colored_polygon` plus a single highlight line, and it
## sat on the Spoils screen — seen after every fight won — beside commissioned
## relic paintings. `tools/art_lint.py` measured it at 50 distinct tones against
## 82–220 for the painters that read as objects (BalanceScale 82, CoinProp 130,
## CandleStub 220), which is the tonal-poverty signature of a flat-fill drawing.
##
## The silhouette is UNCHANGED — the same five points, so nothing in Reward's
## layout moves. What is new is material: the cloth is filled as vertical fold
## bands with a sinusoidal luminance ramp, darkest where it is lashed to the pole
## (cloth turns away from the light at its attachment) and brightest at the
## crests. The pole gets a lit edge and a dark side so it reads as a cylinder
## rather than a stroke, the finial gets a specular dot, and the march seals get
## the domed rim the house wax already uses everywhere else.
const LIGHT_WARM := Color(1.0, 0.94, 0.76)


## One fold band's colour. `t` is 0..1 along the flag; `crest` is the fold phase.
func _cloth_tone(t: float) -> Color:
	# TWO folds across 81px, and no second harmonic. A faster harmonic was tried
	# to sharpen the creases and it ALIASED against the band count — ~5 bands per
	# cycle photographed as corduroy, hard vertical stripes rather than cloth.
	# The band count is what keeps the ramp smooth; the fold shape stays simple.
	var fold: float = 0.5 + 0.5 * sin(t * TAU * 2.0 - PI * 0.28)
	var lash: float = clampf(t / 0.16, 0.0, 1.0)
	var lit: float = lerpf(0.30, 1.0, fold) * lerpf(0.48, 1.0, lash)
	var c := accent.lerp(Color(0.05, 0.03, 0.02), (1.0 - lit) * 0.62)
	return c.lerp(LIGHT_WARM, maxf(0.0, (lit - 0.72)) * 0.55)


func _draw() -> void:
	if not bake_mode and _baked_texture != null:
		draw_texture_rect(_baked_texture, Rect2(Vector2.ZERO, size), false)
		return

	var pole_x := 38.0
	var top_y := 12.0
	var foot_y := 91.0
	# Contact shadow, then the pole as a CYLINDER: a dark core with a lit edge
	# down its left, which is where the flag's own light comes from.
	draw_line(Vector2(pole_x + 3.0, top_y + 3.0),
		Vector2(pole_x + 3.0, foot_y + 3.0), Color(0, 0, 0, 0.34), 4.0, true)
	draw_line(Vector2(pole_x, top_y), Vector2(pole_x, foot_y),
		Color(0.13, 0.09, 0.055), 3.4, true)
	draw_line(Vector2(pole_x - 1.0, top_y + 1.0), Vector2(pole_x - 1.0, foot_y),
		Color(0.42, 0.31, 0.17, 0.85), 1.0, true)
	draw_line(Vector2(pole_x + 1.2, top_y + 1.0), Vector2(pole_x + 1.2, foot_y),
		Color(0.03, 0.02, 0.01, 0.55), 1.0, true)
	# Finial: a struck-brass knob, not a dot.
	draw_circle(Vector2(pole_x, top_y), 3.4, Color(0.34, 0.24, 0.09), true, -1.0, true)
	draw_circle(Vector2(pole_x, top_y), 2.6, Color(0.90, 0.73, 0.30), true, -1.0, true)
	draw_circle(Vector2(pole_x - 0.9, top_y - 0.9), 1.0, LIGHT_WARM, true, -1.0, true)

	# ── Swallow-tail banner, filled as fold bands ──
	var flag := PackedVector2Array([
		Vector2(pole_x, 18), Vector2(119, 22), Vector2(98, 38),
		Vector2(119, 54), Vector2(pole_x, 49)])
	var span := 119.0 - pole_x
	# 54 bands over 81px (~1.5px each) so the fold ramp is smooth. At 26 the
	# steps themselves were visible.
	var bands := 54
	for i in bands:
		var x0: float = pole_x + span * (float(i) / float(bands))
		var x1: float = pole_x + span * (float(i + 1) / float(bands))
		var t: float = (float(i) + 0.5) / float(bands)
		var col := _cloth_tone(t)
		# Edges of the cloth at these x, following the same outline as `flag`.
		var top0: float = 18.0 + (x0 - pole_x) * 4.0 / span
		var top1: float = 18.0 + (x1 - pole_x) * 4.0 / span
		var bot0: float = 49.0 + (x0 - pole_x) * 5.0 / span
		var bot1: float = 49.0 + (x1 - pole_x) * 5.0 / span
		# A BAND MAY STRADDLE THE NOTCH, and the first version drew neither half
		# of the one that did — leaving an undrawn column that photographed as a
		# hard dark seam straight down the middle of the cloth. Each band now
		# draws its solid part up to the notch AND its tail part past it.
		if x0 < 98.0:
			var xm: float = minf(x1, 98.0)
			var tm: float = 18.0 + (xm - pole_x) * 4.0 / span
			var bm: float = 49.0 + (xm - pole_x) * 5.0 / span
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0, top0), Vector2(xm, tm),
				Vector2(xm, bm), Vector2(x0, bot0)]), col)
		if x1 > 98.0:
			# Past the notch the cloth is two tails; shade each separately so the
			# swallow-tail keeps its bite instead of being filled in.
			var xs: float = maxf(x0, 98.0)
			var ts: float = 18.0 + (xs - pole_x) * 4.0 / span
			var bs: float = 49.0 + (xs - pole_x) * 5.0 / span
			var n0: float = 38.0 - (xs - 98.0) * 16.0 / 21.0
			var n1: float = 38.0 - (x1 - 98.0) * 16.0 / 21.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(xs, ts), Vector2(x1, top1),
				Vector2(x1, n1), Vector2(xs, n0)]), col)
			draw_colored_polygon(PackedVector2Array([
				Vector2(xs, 76.0 - n0), Vector2(x1, 76.0 - n1),
				Vector2(x1, bot1), Vector2(xs, bs)]), col)
	var closed := flag.duplicate()
	closed.append(flag[0])
	draw_polyline(closed, Color(0.12, 0.075, 0.04, 0.88), 1.5, true)
	# A hem catching the light along the top edge, and the lashing at the pole.
	draw_line(Vector2(pole_x + 2, 19.2), Vector2(116, 23.2),
		Color(1.0, 0.91, 0.62, 0.30), 1.2, true)
	for ly in [21.0, 30.0, 39.0, 47.0]:
		draw_line(Vector2(pole_x - 1.5, ly), Vector2(pole_x + 4.0, ly + 0.6),
			Color(0.10, 0.07, 0.04, 0.70), 1.4, true)
	# A small black streamer is readable even at one fallen soldier; length
	# grows only slightly so a large roll never turns into visual clutter.
	if fallen_count > 0:
		var mourning_len := minf(34.0 + float(fallen_count - 1) * 2.0, 48.0)
		var mourning := PackedVector2Array([
			Vector2(46, 49), Vector2(56, 50), Vector2(52, 50 + mourning_len),
			Vector2(47, 43 + mourning_len)])
		draw_colored_polygon(mourning, Color(0.055, 0.045, 0.042, 0.96))
	# General ribbons hang from the spear crossbar. Cap the visible count; the
	# shape communicates honors, while the reward copy carries exact numbers.
	for i in range(mini(generals_broken, 5)):
		var rx := 66.0 + float(i) * 9.0
		var ribbon_col := Color(0.74, 0.18, 0.11).lerp(
			Color(0.92, 0.66, 0.24), float(i % 2) * 0.35)
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx, 51), Vector2(rx + 6, 51), Vector2(rx + 5, 68),
			Vector2(rx + 3, 65), Vector2(rx + 1, 68)]), ribbon_col)
	# Completed marches become wax seals at the foot of the standard.
	# A DOMED seal, not a red disc: a cast shadow, a dark rim, a lit dome, a
	# pressed centre and a specular. Same reading as the wax on every card face.
	for i in range(acts_won):
		var p := Vector2(62.0 + float(i) * 23.0, 86.0)
		draw_circle(p + Vector2(2, 2), 9.0, Color(0, 0, 0, 0.24), true, -1.0, true)
		draw_circle(p, 9.0, Color(0.26, 0.045, 0.035), true, -1.0, true)
		draw_circle(p - Vector2(0.6, 0.8), 7.8, Color(0.60, 0.12, 0.085),
			true, -1.0, true)
		draw_circle(p - Vector2(1.4, 1.8), 5.4, Color(0.74, 0.19, 0.12),
			true, -1.0, true)
		draw_arc(p, 6.0, 0, TAU, 18, Color(0.30, 0.05, 0.04, 0.75), 1.4, true)
		draw_circle(p - Vector2(2.6, 3.0), 1.5, Color(1.0, 0.72, 0.55, 0.55),
			true, -1.0, true)
	# The planted foot.
	draw_line(Vector2(23, foot_y), Vector2(54, foot_y),
		Color(0.18, 0.11, 0.055, 0.82), 3.0, true)
