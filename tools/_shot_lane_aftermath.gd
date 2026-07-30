extends Node
## _shot_lane_aftermath.gd — S5 aftermath (docs/SPELL_FX_PLAN_20260717.md).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_lane_aftermath.tscn
##
## The persistent spells' STANDING state, painted on the table:
##   - lane 1 (enemy side) salted, 2 rounds left  → bone stipple + 2 pips
##   - lane 2 condemned (both sides)              → blood-ink writ + noose
##   - 2 wolf-pit charges waiting                 → covered pits past the line
##   - a hand card carrying a 3-knot burning fuse (Slow Match's banked charge)
##
## One full-frame shot + a 2× zoom on the enemy columns + one on the hand.
## Outputs _shot_aftermath_*.png at the project root.

var _combat: Node = null


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[aftermath] WATCHDOG fired — _ready never completed")
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

	# Stage the standing state directly and repaint.
	var rn: int = int(_combat.get("round_number"))
	_combat.get("_salted_lanes")[1] = rn + 1        # 2 rounds left
	_combat.get("_condemned_lanes")[2] = rn + 1     # falls next round
	var pits: Array = _combat.get("_pit_traps")
	pits.append(3)
	pits.append(3)
	_combat.call("_refresh_lane_aftermath")
	print("[aftermath] layer present: %s" % [_combat.get("_lane_aftermath") != null])

	# Fuse cord on a hand card (the painter under test; any writ will do).
	var hand: Array = _combat.get("_hand")
	if not hand.is_empty() and is_instance_valid(hand[0]):
		hand[0].set_fuse_glow(3)
		print("[aftermath] fuse staged on: %s" % String(hand[0].card_id))

	await get_tree().create_timer(0.5).timeout
	await _snap("res://_shot_aftermath_full.png", "full board")

	# 2× zoom crops for the visibility check (the rule that killed ★3/★4b:
	# judge the effect at the size it's DRAWN, then bigger). PROPORTIONAL
	# crops — the OS may hand the window a different pixel size than asked
	# (first run rendered 1920x1080 against an assumed 1600x900 and the "hand"
	# crop caught the board instead).
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var board := img.get_region(Rect2i(int(w * 0.17), int(h * 0.24),
		int(w * 0.66), int(h * 0.42)))
	board.resize(board.get_width() * 2, board.get_height() * 2,
		Image.INTERPOLATE_NEAREST)
	board.save_png("res://_shot_aftermath_board_zoom.png")
	print("[aftermath] wrote _shot_aftermath_board_zoom.png (%dx%d source)" % [w, h])
	var handcrop := img.get_region(Rect2i(int(w * 0.15), int(h * 0.70),
		int(w * 0.62), int(h * 0.30) - 2))
	handcrop.resize(handcrop.get_width() * 2, handcrop.get_height() * 2,
		Image.INTERPOLATE_NEAREST)
	handcrop.save_png("res://_shot_aftermath_hand_zoom.png")
	print("[aftermath] wrote _shot_aftermath_hand_zoom.png")

	print("[aftermath] DONE")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


func _snap(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[aftermath] wrote %s — %s" % [path.get_file(), label])
