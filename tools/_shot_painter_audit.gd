extends Node
## _shot_painter_audit.gd — a CONTACT SHEET of every procedural painter
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_painter_audit.tscn
## Outputs tools/screenshot/_painters_<n>.png
##
## WHY THIS EXISTS (2026-09-03). `scripts/ui/painters/` holds 51 classes that
## draw themselves in code, and they are the reason the shell reads unevenly:
## a hand-coded polygon sits on the same screen as a commissioned painting, and
## the eye goes straight to the polygon. Nothing rendered them TOGETHER, so
## "which ones actually look bad" was a matter of opinion rather than a list.
##
## Each cell is the painter at a plausible size on the game's own dark ground,
## captioned with its class name. `configure()` is called where the signature is
## known (the table below); everything else draws its default state, which is
## what most of them do anyway. A cell that comes out EMPTY is not a bug in the
## painter — it means that one needs state this harness does not give it, and it
## is simply out of scope for a look-and-rank pass.

const DIR := "res://scripts/ui/painters/"
const COLS := 8
const CELL := Vector2(190, 118)
const PAD := Vector2(10, 26)

## Painters whose default state draws nothing useful. Keyed by class file stem;
## the value is a Callable taking the instance.
var _seed_state := {
	"CampaignStandard": func(n): n.configure(2, 3, 2, Color(0.82, 0.60, 0.24)),
}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	var names := _painter_names()
	print("[painters] %d painter(s)" % names.size())
	var per_page := COLS * 6
	var page := 0
	var i := 0
	while i < names.size():
		var slice: Array = names.slice(i, mini(i + per_page, names.size()))
		await _draw_page(slice, page)
		i += per_page
		page += 1
	await _emit_singles(names)
	print("PAINTER_AUDIT_DONE")
	get_tree().quit()


## ── ONE TRANSPARENT PNG PER PAINTER, for `tools/art_lint.py` ────────────────
##
## The contact sheet is for a human; this is for the linter. It must be
## TRANSPARENT-backed: art_lint's every measurement is taken over the DRAWN
## pixels only (alpha > 32), and a painter shot against the sheet's opaque dark
## ground would have the whole cell counted as drawn — so a flat triangle on a
## flat background would measure as "textured" by the contrast between them,
## which is precisely backwards.
func _emit_singles(names: Array) -> void:
	var dir := "res://tools/screenshot/painters"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var wrote := 0
	for stem_v in names:
		var stem := String(stem_v)
		var scr = load(DIR + stem + ".gd")
		if scr == null:
			continue
		var inst = scr.new()
		if not (inst is Control):
			if inst is Node:
				inst.free()
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(int(CELL.x), int(CELL.y))
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var c: Control = inst
		vp.add_child(c)
		c.position = Vector2.ZERO
		c.size = CELL
		c.custom_minimum_size = CELL
		if _seed_state.has(stem):
			(_seed_state[stem] as Callable).call(c)
			c.size = CELL
		c.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		if img != null:
			img.save_png("%s/%s.png" % [dir, stem])
			wrote += 1
		vp.queue_free()
		await get_tree().process_frame
	print("[painters] wrote %d single PNG(s) to %s" % [wrote, dir])


func _painter_names() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(f.get_basename())
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _draw_page(names: Array, page: int) -> void:
	var host := ColorRect.new()
	host.color = Color(0.07, 0.055, 0.045)
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(host)

	for idx in names.size():
		var stem := String(names[idx])
		var col := idx % COLS
		var row := idx / COLS
		var origin := Vector2(14, 20) + Vector2(
			col * (CELL.x + PAD.x), row * (CELL.y + PAD.y))

		var cap := Label.new()
		cap.text = stem
		cap.position = origin + Vector2(0, CELL.y + 2)
		cap.size = Vector2(CELL.x, 20)
		cap.add_theme_font_size_override("font_size", 11)
		cap.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
		host.add_child(cap)

		var scr = load(DIR + stem + ".gd")
		if scr == null:
			continue
		var inst = scr.new()
		if not (inst is Control):
			if inst is Node:
				inst.free()
			continue
		var c: Control = inst
		host.add_child(c)
		c.position = origin
		c.size = CELL
		c.custom_minimum_size = CELL
		if _seed_state.has(stem):
			(_seed_state[stem] as Callable).call(c)
			# configure() may stamp its own minimum size — keep the cell honest.
			c.size = CELL
		if c.has_method("queue_redraw"):
			c.queue_redraw()

	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_painters_%d.png" % page)
	print("SAVED page %d (%d cells)" % [page, names.size()])
	host.queue_free()
	await get_tree().process_frame
