extends Control
## _shot_frame_ab — OLD flat rule vs NEW molding, measured rather than admired.
##
## THE ORACLE IS THE PHYSICAL CLAIM, which is what keeps this from being a taste
## argument. `PlateFrame`'s whole thesis is that a frame is a solid with a
## cross-section and that the light therefore INVERTS between opposite runs. Both
## halves of that are directly measurable off the framebuffer:
##
##   PLATEAUS  — how many distinct values appear crossing the rule's width.
##               A polyline has one by construction. A molding must have several.
##   INVERSION — the profile across the TOP run against the profile across the
##               BOTTOM run, sampled at the same depth u. A symmetric stroke (or
##               a symmetric halo stack, which is the failed fix) scores ~0 here
##               no matter how many layers it has. This is the number that
##               separates "thicker line" from "object".
##
## The measured samples sit over a FLAT interior on purpose. Reading a profile
## through a painting confounds the frame with whatever the art happens to be
## doing at that row, and the top and bottom of a portrait are never the same
## colour — the inversion figure would then be measuring the painting. The
## art-backed pair beside them is for the eye only.
##
## Windowed. Zoom crops are NEAREST — a 6px molding's three values are not
## decidable at 1:1, which is the same reason the coach-device shots zoom.

const OUT_DIR := "res://tools/screenshot"
const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")

const PORTRAIT := Vector2(282, 376)
const TILE := Vector2(211, 140)
## The shell's warm-black ground, quoted from Sheen.gd's header.
const GROUND := Color(0.118, 0.094, 0.074)
## A flat mid-dark interior for the measured samples. Not black: a frame read
## against black exaggerates every value it has.
const INTERIOR := Color(0.20, 0.17, 0.14)

var _rects: Dictionary = {}     # tag -> Rect2 (CANVAS space)
## Framebuffer px per canvas px. Measured off the captured image, never assumed.
var _px := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	size = Vector2(1600, 900)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = GROUND
	add_child(bg)

	var accent := Color(0.78, 0.36, 0.22)          # a faction accent, Raider-ish
	var tile_metal := Color(0.50, 0.43, 0.31, 0.90)

	# ── measured pairs, flat interior ──
	_old_sample("old_portrait", Vector2(70, 80), PORTRAIT, accent, 2)
	_new_sample("new_portrait", Vector2(400, 80), PORTRAIT, accent,
		{"rule_w": 7.0, "chamfer": 13.0, "rebate": 3.5, "drop": 2.4})
	_old_sample("old_tile", Vector2(70, 520), TILE, tile_metal, 1)
	_new_sample("new_tile", Vector2(400, 520), TILE, tile_metal,
		{"rule_w": 4.2, "chamfer": 9.0, "rebate": 2.2, "drop": 1.6,
			"lit_gain": 0.62})

	# ── eyes only: the same frames over real art ──
	var art := _find_art()
	_old_sample("old_art", Vector2(760, 80), PORTRAIT, accent, 2, art)
	_new_sample("new_art", Vector2(1090, 80), PORTRAIT, accent,
		{"rule_w": 7.0, "chamfer": 13.0, "rebate": 3.5, "drop": 2.4}, art)
	_old_sample("old_art_tile", Vector2(760, 520), TILE, tile_metal, 1, art)
	_new_sample("new_art_tile", Vector2(1090, 520), TILE, tile_metal,
		{"rule_w": 4.2, "chamfer": 9.0, "rebate": 2.2, "drop": 1.6,
			"lit_gain": 0.62}, art)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_frame_ab.png" % OUT_DIR)
	print("SAVED _frame_ab.png ", img.get_size())

	# THE FRAMEBUFFER IS NOT THE CANVAS, and assuming it was voided this tool's
	# first run outright: the window was asked for 1600x900 and the viewport
	# texture came back 1920x1080, so every sample landed ~20% off its target and
	# the molding measured identical to the flat rule — a clean report about
	# pixels nobody was looking at. Same family as the C32 UI-scale lesson (the
	# logical canvas and the runtime surface are different numbers) and as the
	# pilot's canvas-local coordinate trap. Derive the ratio, never assume it.
	_px = float(img.get_width()) / maxf(size.x, 1.0)
	print("canvas=", size, "  framebuffer=", img.get_size(), "  scale=%.3f" % _px)
	for tag in ["old_portrait", "new_portrait", "old_tile", "new_tile"]:
		_report(img, tag)
	for tag in ["old_portrait", "new_portrait", "old_tile", "new_tile",
			"old_art", "new_art"]:
		_zoom(img, tag)
	get_tree().quit()


# ── samples ────────────────────────────────────────────────────────────────

func _body(at: Vector2, sz: Vector2, art: Texture2D) -> Control:
	var host := Control.new()
	host.position = at
	host.size = sz
	host.custom_minimum_size = sz
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	if art != null:
		var clip := Control.new()
		clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(clip)
		var t := TextureRect.new()
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.texture = art
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(t)
	else:
		var fill := ColorRect.new()
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.color = INTERIOR
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(fill)
	return host


## The frame exactly as it ships today: a transparent-bg ChartPanelStyle, i.e.
## the metal rule alone. This is the live call-site shape from MainMenu.
func _old_sample(tag: String, at: Vector2, sz: Vector2, metal: Color,
		w: int, art: Texture2D = null) -> void:
	var host := _body(at, sz, art)
	var edge := Panel.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
		Color(0, 0, 0, 0.0), metal, w, 3, false))
	host.add_child(edge)
	_rects[tag] = Rect2(at, sz)


func _new_sample(tag: String, at: Vector2, sz: Vector2, metal: Color,
		opts: Dictionary, art: Texture2D = null) -> void:
	var host := _body(at, sz, art)
	PlateFrame.over(host, metal, opts)
	_rects[tag] = Rect2(at, sz)


func _find_art() -> Texture2D:
	for p in ["res://assets/portraits/hero_portrait_raider.png",
			"res://assets/creatures/goblin.png"]:
		if ResourceLoader.exists(p):
			return load(p)
	var dir := DirAccess.open("res://assets/creatures")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".png"):
				return load("res://assets/creatures/%s" % f)
	return null


# ── the oracle ─────────────────────────────────────────────────────────────

## Luminance profile crossing a run of the frame, outer -> inner.
func _profile(img: Image, x: int, y0: int, dir: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var y := y0 + dir * i
		if y < 0 or y >= img.get_height() or x < 0 or x >= img.get_width():
			out.append(0.0)
			continue
		out.append(img.get_pixel(x, y).get_luminance())
	return out


func _report(img: Image, tag: String) -> void:
	var r: Rect2 = _rects[tag]
	var x := int((r.position.x + r.size.x * 0.5) * _px)
	var span := int(round(14.0 * _px))
	var lead := int(round(3.0 * _px))
	# Start 3px OUTSIDE the plate so the ground and the drop are in frame.
	var top := _profile(img, x, int(r.position.y * _px) - lead, 1, span)
	var bot := _profile(img, x, int(r.end.y * _px) + lead, -1, span)

	var levels: Dictionary = {}
	for v in top:
		levels[snappedf(v, 0.02)] = true
	# The inversion figure: same depth u, opposite runs.
	var asym := 0.0
	for i in range(span):
		asym = maxf(asym, absf(float(top[i]) - float(bot[i])))

	print("── ", tag)
	print("   top    ", _fmt(top))
	print("   bottom ", _fmt(bot))
	print("   plateaus=%d  peak=%.3f  INVERSION=%.3f" % [
		levels.size(), _peak(top), asym])


func _fmt(a: Array) -> String:
	var s := ""
	for v in a:
		s += "%.2f " % float(v)
	return s


func _peak(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


func _zoom(img: Image, tag: String) -> void:
	var r: Rect2 = _rects[tag]
	# The top-left corner: one shot carrying a run of the top molding, a run of
	# the left molding, the chamfer between them and a corner tack.
	_crop(img, tag + "_corner", (r.position + Vector2(26, 22)) * _px,
		Vector2(78, 62) * _px, 8.0)
	# A span of the BOTTOM run at the same scale — the half of the claim that a
	# single corner shot cannot show.
	_crop(img, tag + "_bottom",
		Vector2(r.position.x + r.size.x * 0.5, r.end.y - 10) * _px,
		Vector2(78, 34) * _px, 8.0)


func _crop(img: Image, tag: String, center: Vector2, sz: Vector2, zoom: float) -> void:
	var full := Rect2i(Vector2i.ZERO, img.get_size())
	var rr := Rect2i(Vector2i((center - sz * 0.5).round()),
		Vector2i(sz.round())).intersection(full)
	if rr.size.x < 4 or rr.size.y < 4:
		return
	var sub := img.get_region(rr)
	sub.resize(int(rr.size.x * zoom), int(rr.size.y * zoom), Image.INTERPOLATE_NEAREST)
	sub.save_png("%s/_frame_%s.png" % [OUT_DIR, tag])
	print("SAVED _frame_", tag, " ", sub.get_size())
