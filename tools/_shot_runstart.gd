extends Node
## _shot_runstart.gd — renders the RUN-OPENING FLOW (menu column → hero select
## with each lord focused → the war chest → a war-chest card picker) to PNG for
## a design audit (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_runstart.tscn
## Outputs tools/screenshot/_runstart_<state>.png

var _scene: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	# The menu column staggers its entrance; 1.4s is the settled window.
	await get_tree().create_timer(1.6).timeout
	await _snap("menu")

	# Run setup — the roster + dossier. Shoot the default focus, then two more
	# lords so the pane's per-hero content can be compared side by side.
	RunState.active_slot = 0
	_scene.call("_show_hero_select")
	await get_tree().create_timer(1.5).timeout
	await _snap("setup_hero1")

	for hid in ["acolyte", "kindler"]:
		_scene.call("_focus_hero", hid)
		await get_tree().create_timer(1.0).timeout
		await _snap("setup_" + hid)

	# Ascension pushed up the ladder — does the rules text stay legible?
	_scene.set("_selected_ascension", 5)
	if _scene.has_method("_update_asc_rules_text"):
		_scene.call("_update_asc_rules_text")
	await get_tree().create_timer(0.6).timeout
	await _snap("setup_asc5")
	_scene.set("_selected_ascension", 0)
	if _scene.has_method("_update_asc_rules_text"):
		_scene.call("_update_asc_rules_text")

	# The war chest. Needs a live run so the deck-touching tiles have a deck.
	RunState.start_new_run("raider")
	_scene.call("_show_blessing_select")
	await get_tree().create_timer(1.5).timeout
	await _snap("warchest")

	# Re-roll the tiles a few times — the pool is random, so one frame is not
	# an audit. Each shot is a different dealt slate.
	for i in range(1, 4):
		_scene.call("_show_blessing_select")
		await get_tree().create_timer(1.2).timeout
		await _snap("warchest_roll%d" % i)

	# A card picker (the "forge which card?" grid the deck-touching tiles open).
	var cands: Array = _scene.call("_blessing_upgrade_candidates")
	if not cands.is_empty():
		_scene.call("_show_blessing_card_picker", "Forge which card?", cands,
			func(_i: int) -> void: pass)
		await get_tree().create_timer(1.6).timeout
		await _snap("warchest_picker")

	print("RUNSTART_SHOT_DONE")
	get_tree().quit()


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_runstart_%s.png" % state)
	print("SAVED ", state, " ", img.get_size())
