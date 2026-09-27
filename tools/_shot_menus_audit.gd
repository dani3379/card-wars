extends Node
## _shot_menus_audit.gd — renders the SECONDARY menus (settings overlay in both
## contexts, the confirm dialog, how to play, load game, skirmish lobby,
## credits) to PNG for a visual audit (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_menus_audit.tscn
## Outputs tools/screenshot/_menus_<state>.png

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

	# --- Main menu host: settings / how-to-play / load screen live over it ---
	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.4).timeout

	# Settings overlay, idle context ("SETTINGS", no run).
	GameTheme.open_settings_overlay()
	await get_tree().create_timer(0.9).timeout
	await _snap("settings")

	# Paused context ("PAUSED" + Main Menu / Abandon system row). In-memory run
	# only — the shot harness never saves.
	RunState.start_new_run("raider")
	_close_settings()
	await get_tree().create_timer(0.4).timeout
	GameTheme.open_settings_overlay()
	await get_tree().create_timer(0.9).timeout
	await _snap("settings_paused")

	# Confirm dialog (abandon-run gate) over the paused overlay.
	GameTheme.show_confirm_dialog(_scene,
		"ABANDON RUN?",
		"Your current progress will be lost and this run will be counted as a defeat. Are you sure?",
		"YES, ABANDON", "KEEP PLAYING")
	await get_tree().create_timer(0.7).timeout
	await _snap("confirm")
	RunState.run_active = false
	_close_settings()
	# The dialog parents to current_scene — which in this harness is THIS
	# node, not root. Sweep both, or the scrim dims every later shot.
	for host in [get_tree().root, self]:
		for child in host.get_children():
			if child is CanvasLayer and child.layer == 1000:
				child.queue_free()
	await get_tree().create_timer(0.4).timeout

	# Load-game slot screen — must show its slot rows within the settle window
	# (the reveal stagger no longer counts the dying menu column).
	if _scene.has_method("_show_load_screen"):
		_scene.call("_show_load_screen", false)
		await get_tree().create_timer(0.9).timeout
		await _snap("load_game")

	# How-to-play overlay (shared GameTheme builder, hosted on the menu).
	if _scene.has_method("_show_how_to_play"):
		_scene.call("_show_how_to_play")
		await get_tree().create_timer(0.9).timeout
		await _snap("how_to_play")
		var how_to := _scene.get_node_or_null("HowToPlayOverlay")
		if how_to != null:
			var keyword_tab = how_to.find_child("KeywordsTab", true, false)
			if keyword_tab is Button:
				keyword_tab.pressed.emit()
				await get_tree().create_timer(0.5).timeout
				await _snap("how_to_play_keywords")

	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Credits — the chronicle roll. Two frames: the opening state and a
	# mid-drift frame a few seconds in (proves the auto-roll moves).
	_scene = load("res://scenes/credits.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.5).timeout
	await _snap("credits")
	await get_tree().create_timer(6.0).timeout
	await _snap("credits_rolled")
	# Jump to the foot of the roll — the thanks + wax seal closer.
	_scene.set("_scroll_pos", 999999.0)
	var roll: ScrollContainer = _scene.get("_scroll")
	if roll != null:
		roll.scroll_vertical = 999999
	await get_tree().create_timer(0.5).timeout
	await _snap("credits_end")
	_scene.queue_free()
	await get_tree().process_frame

	print("MENUS_AUDIT_DONE")
	get_tree().quit()


func _close_settings() -> void:
	for child in UserSettings.get_children():
		if child.has_method("_close"):
			child.call("_close")


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_menus_%s.png" % state)
	print("SAVED ", state, " ", img.get_size())
