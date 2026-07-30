extends Node
## _shot_menu.gd — renders the main menu (title column) and the run-setup
## state (hero picker + detail pane + slot rows) to PNG for panel-kit audits
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_menu.tscn
## Outputs tools/screenshot/_menu_<state>.png

var _scene: Node = null


func _ready() -> void:
	print("[shotmenu] ready")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[shotmenu] frames ok")
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	print("[shotmenu] window ok")

	_scene = load("res://scenes/main_menu.tscn").instantiate()
	print("[shotmenu] menu instantiated")
	get_tree().root.add_child(_scene)
	print("[shotmenu] menu added")
	await get_tree().create_timer(1.4).timeout
	print("[shotmenu] settle done")
	await _snap("title")

	# Run setup: jump straight to the hero-select build (the panel-heavy state).
	# NOT _on_new_run — that claims a save slot via clear_save, and a shot
	# harness must never touch save files.
	if _scene.has_method("_show_hero_select"):
		_scene.call("_show_hero_select")
		await get_tree().create_timer(1.0).timeout
		await _snap("run_setup")

	# Deck-strip states: focus a hero (mini-card loadout band), then float the
	# full-size hover preview the way a mini mouse-over would.
	if _scene.has_method("_focus_hero"):
		_scene.call("_focus_hero", "stalwart")
		await get_tree().create_timer(0.9).timeout
		await _snap("hero_focus")
		var det = _scene.get("_hero_detail")
		var deck: Array = HeroDB.get_hero("stalwart").get("deck", [])
		if det != null and not deck.is_empty() and _scene.has_method("_show_deck_preview"):
			_scene.call("_show_deck_preview", String(deck[0]), det)
			await get_tree().create_timer(0.6).timeout
			await _snap("hero_preview")
		# Kindler carries the widest muster (6 unique cards) — the band's
		# worst-case width check.
		_scene.call("_focus_hero", "kindler")
		await get_tree().create_timer(0.9).timeout
		await _snap("hero_kindler")

		# Ascension-unlocked footer: bump the tier IN MEMORY ONLY (never saved to
		# meta.save) so the MARCH ORDERS stepper + cumulative rules readout render
		# — the worst case for the footer crowding the TAKE THE FIELD button.
		MetaState.unlocked_ascension = maxi(MetaState.unlocked_ascension, 5)
		_scene.set("_selected_ascension", 3)
		_scene.call("_show_hero_select")
		await get_tree().create_timer(0.9).timeout
		await _snap("hero_ascension")

	print("MENU_SHOTS_DONE")
	get_tree().quit()


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_menu_%s.png" % state)
	print("SAVED ", state, " ", img.get_size())
