extends Node
## _shot_killing_blow.gd — ★8 "the killing blow"
## (docs/ANIMATION_COOL_PITCH_20260717.md §5b).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_killing_blow.tscn
##
## The world-stop on the fight-ending blow: colour drains out of the whole
## frame (u_sat on the existing cinematic grade), the table takes its heaviest
## hit, the music dips. Frames shot:
##
##   defeat_drain   staged _play_killing_blow_moment(false) mid-drain — the
##                  world grey; DEFEAT ink must still read blood-red later
##   victory_drain  REAL _debug_auto_win() path at +0.30 — drained beat
##   victory_stamp  +0.75 — the VICTORY stamp landing as colour floods back
##
## The killer-held-at-extension half is covered by _probe_anim_clock (pause/
## resume mechanics) — a shot can't reliably stage a lethal strike mid-clash.
## Outputs _shot_killblow_*.png at the project root. Quits BEFORE the victory
## path's +1.2s scene change so the harness never leaves combat.

var _combat: Node = null


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[killblow] WATCHDOG fired — _ready never completed")
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

	print("[killblow] grade mat present: %s" % [_combat.get("_grade_mat") != null])

	# ── 1. Staged DEFEAT drain (no phase change, no scene-change fallout). ──
	_combat.call("_play_killing_blow_moment", false)
	await get_tree().create_timer(0.35).timeout
	await _snap("res://_shot_killblow_defeat.png", "defeat drain @0.35")
	# Let the partial recover finish, then reset the grade to the mood baseline
	# so the victory pass starts from clean colour.
	await get_tree().create_timer(1.2).timeout
	_combat.call("_apply_combat_mood")
	await get_tree().create_timer(0.3).timeout

	# ── 2. REAL victory path — the full funnel, timers and all. ──
	_combat.call("_debug_auto_win")
	await get_tree().create_timer(0.30).timeout
	await _snap("res://_shot_killblow_victory_drain.png", "victory drain @0.30")
	await get_tree().create_timer(0.45).timeout
	await _snap("res://_shot_killblow_victory_stamp.png", "victory stamp @0.75")

	# Quit before the +1.2s reward transition fires.
	print("[killblow] DONE")
	get_tree().quit(0)


func _snap(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[killblow] wrote %s — %s" % [path.get_file(), label])
