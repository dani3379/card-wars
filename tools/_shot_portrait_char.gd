extends Node
## _shot_portrait_char.gd — ★7 "the portrait takes the war"
## (docs/ANIMATION_COOL_PITCH_20260717.md §5b).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_portrait_char.tscn
##
## This is a shader on a UI element that is ALWAYS on screen, so a mistake here
## is the most visible kind in the game. Four HP levels in one pass:
##
##   full   30/30 — the panel must be UNTOUCHED (a whole hero must look whole)
##   half   ~60%  — just past the singe threshold
##   low    ~30%  — clearly scorched
##   dying  1/30  — maximum soot, and CRUCIALLY still a panel, not a hole
##                  (consume = 0; a hole in the HUD would read as a bug)
##
## Outputs _shot_portrait_*.png at the project root.

var _combat: Node = null


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[portrait] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0

	RunState.start_new_run("raider")
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	await get_tree().create_timer(6.0).timeout

	print("[portrait] player rect bound: %s | enemy rect bound: %s" % [
		_combat.get("_player_portrait_rect") != null,
		_combat.get("_enemy_portrait_rect") != null])
	# The burn curve, independent of rendering — cheap to assert here.
	print("[portrait] burn @ full=%.3f  half=%.3f  quarter=%.3f  dead=%.3f" % [
		_combat.call("_portrait_burn_for", 1.0),
		_combat.call("_portrait_burn_for", 0.5),
		_combat.call("_portrait_burn_for", 0.25),
		_combat.call("_portrait_burn_for", 0.0)])

	await _at_hp(30, "full", "res://_shot_portrait_full.png")
	await _at_hp(18, "half (60%)", "res://_shot_portrait_half.png")
	await _at_hp(9, "low (30%)", "res://_shot_portrait_low.png")
	await _at_hp(1, "dying (3%)", "res://_shot_portrait_dying.png")

	print("[portrait] DONE")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


func _at_hp(hp: int, label: String, path: String) -> void:
	_combat.set("player_hp", hp)
	# Char the FOE in step too, so one pass proves both panels.
	_combat.set("enemy_hp", int(round(float(_combat.get("enemy_max_hp")) \
		* float(hp) / 30.0)))
	_combat.call("_update_hud")
	# The char CREEPS (0.45s tween) — wait it out or the shot catches it partway.
	await get_tree().create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[portrait] wrote %s — %s" % [path.get_file(), label])
