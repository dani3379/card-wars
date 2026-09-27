extends Node
## _probe_modal_scrim.gd — C28 follow-up: does a modal's scrim actually DRAW?
##
##   Godot.exe --path "D:\Godot" res://tools/_probe_modal_scrim.tscn
##   (WINDOWED on purpose — it measures pixels, so it needs a real framebuffer.)
##
## Combat's pile viewer and glossary both build their backdrop the same way:
##
##     var backdrop := Button.new()
##     backdrop.flat = true
##     var dim := StyleBoxFlat.new()
##     dim.bg_color = Color(0, 0, 0, 0.7)
##     backdrop.add_theme_stylebox_override("normal", dim)
##
## Those two lines contradict each other. **A flat Button does not draw its
## stylebox** — that is what `flat` means — so the dim is built, themed onto three
## states, and never painted. The modal then opens over a fully lit battlefield:
## board, HUD and hand all stay at full brightness behind the card grid, and the
## viewer's own title lands on top of the HUD's phase caption.
##
## THE ORACLE IS LUMINANCE, NOT THE SCENE TREE. The scrim node exists either way,
## reports `visible = true`, and carries a 0.7-alpha stylebox — so every
## tree-walking check agrees the screen is dimmed. Only the pixels disagree. This
## is why C28's geometric oracles cleared these screens: an occluder that does not
## paint is not an occluder, and the defect is that it FAILS to occlude.

## SAMPLE WHERE THE MODAL DOES NOT PAINT, and that is a narrower place than it
## looks. The pile viewer's card grid carries `custom_minimum_size.x = 1600`, so
## it spreads across the WHOLE canvas — a strip chosen at the far left edge is
## still under column one, and its bright parchment made the region read 192%
## BRIGHTER with the modal open, which says nothing about the scrim either way.
## The one band the viewer never paints is above its own title (offset_top 40).
const REGION := Rect2i(200, 2, 1200, 32)     # 1600x900 canvas space
const MIN_DARKENING := 0.30                  # a 0.7 scrim must beat this comfortably

var _hits := 0
var _cb: Node = null


func _ready() -> void:
	UserSettings.anim_speed = 3.0
	UserSettings.end_turn_warning = false
	seed(4242)
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_node_type = "combat"
	_cb = load("res://scenes/combat.tscn").instantiate()
	add_child(_cb)
	await get_tree().create_timer(6.0).timeout

	print("[scrim] does a modal backdrop actually darken the screen?\n")
	var base := await _luma("closed")

	# ── the pile viewer ───────────────────────────────────────────────────
	if _cb._player_discard_pile.is_empty():
		for i in mini(8, RunState.deck.size()):
			_cb._player_discard_pile.append(RunState.deck[i])
	_cb._show_pile_viewer(1)
	await get_tree().create_timer(1.4).timeout
	_report("pile viewer", base, await _luma("pile"))
	_cb._close_pile_viewer()
	await get_tree().create_timer(0.8).timeout

	# ── the glossary ──────────────────────────────────────────────────────
	if _cb.has_method("_reset_glossary_layer"):
		_cb._reset_glossary_layer(0.56)
		await get_tree().create_timer(1.2).timeout
		_report("glossary", base, await _luma("glossary"))

	print("\n[scrim] %s" % ("PASS" if _hits == 0 else "%d HIT(S)" % _hits))
	get_tree().quit(1 if _hits > 0 else 0)


func _report(what: String, base: float, now: float) -> void:
	if base <= 0.0 or now < 0.0:
		print("  skip  %s (could not sample)" % what)
		return
	var drop: float = 1.0 - (now / base)
	print("  %-12s board luma %.4f -> %.4f  (%.0f%% darker)" % [
		what, base, now, drop * 100.0])
	if drop < MIN_DARKENING:
		_hits += 1
		print("  HIT   %s: the scrim is in the tree and paints NOTHING." % what)
		print("        `backdrop.flat = true` cancels the stylebox override that")
		print("        carries the dim, so the fight stays fully lit behind the")
		print("        modal — and the modal's title is printed over the HUD's")
		print("        own caption, with both left unreadable.")


func _luma(tag: String) -> float:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/_shot_scrim_%s.png" % tag)
	var scale := float(img.get_width()) / 1600.0
	var rr := Rect2i(
		int(REGION.position.x * scale), int(REGION.position.y * scale),
		int(REGION.size.x * scale), int(REGION.size.y * scale))
	rr = rr.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rr.size.x <= 0 or rr.size.y <= 0:
		return -1.0
	var total := 0.0
	var n := 0
	for y in range(rr.position.y, rr.end.y, 3):
		for x in range(rr.position.x, rr.end.x, 3):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return -1.0 if n == 0 else total / float(n)
