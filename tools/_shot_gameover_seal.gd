extends Node
# THE CLOSING SEAL (2026-09-10). The run's last image, shot at the three instants
# that decide whether the press reads as wax or as a node that scaled.
#
#   Godot.exe --path "D:\Godot" res://tools/_shot_gameover_seal.tscn
#
# Frames, per verdict (won = RunState.hero_hp > 0, which is the whole switch):
#   descent  — mid-fall. The matrix must be FULLY OPAQUE here. It used to ramp
#              alpha across the descent, which is the defect that cost the
#              lightning two rebuilds: no instant at which it was ever at full
#              strength.
#   contact  — the blow. Squeeze-out past the matrix edge, the displaced-wax
#              rings in the WAX's colour rather than the kit's white, spatter,
#              and the impact frame.
#   settled  — ~0.9s later. The squeeze has flowed back, the gloss has crossed
#              and gone (wax cools), and the dent in the page is still there —
#              it is the one mark that must NOT fade.
#
# Timing is read off `_stamp_closing_seal`: a 0.55s hold, then a 0.16s descent,
# so contact lands at ~0.71s after the page settles. The harness waits for the
# seal NODE rather than trusting that arithmetic, because the seal parks itself
# only after two process frames of layout.

const HERO_ID := "raider"
const SHOT_SEED := 20260804


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	var verdicts: Array[bool] = [true, false]
	if OS.get_cmdline_user_args().has("--win-only"):
		verdicts = [true]
	elif OS.get_cmdline_user_args().has("--loss-only"):
		verdicts = [false]
	for won in verdicts:
		await _shoot_verdict(won)

	print("SHOTS_DONE")
	get_tree().quit()


func _shoot_verdict(won: bool) -> void:
	RunState.start_new_run(HERO_ID, -1, SHOT_SEED)
	# The only thing the screen reads to pick a verdict. Set AFTER start_new_run,
	# which resets it to full.
	RunState.hero_hp = 24 if won else 0
	RunState.fights_won = 11
	RunState.gold = 250
	await get_tree().process_frame

	var scene: Node = load("res://scenes/game_over.tscn").instantiate()
	get_tree().root.add_child(scene)
	var tag := "win" if won else "loss"

	# Wait for the seal to exist and be parked, then sample from THAT instant —
	# a fixed sleep from scene-add measures the machine, not the animation.
	var seal: Node = null
	var guard := 0
	while seal == null and guard < 900:
		guard += 1
		await get_tree().process_frame
		seal = scene.get_node_or_null("ClosingSeal")
	if seal == null:
		print("SHOT FAIL: no ClosingSeal for ", tag)
		scene.queue_free()
		return

	var sc := seal as Control
	# WAIT FOR THE PRESS TO BE ARMED, NOT MERELY FOR THE NODE TO EXIST.
	# `_stamp_closing_seal` creates the host, THEN awaits two process frames for
	# the page to settle before parking and animating it, so a harness that polls
	# on `get_node_or_null` samples an unpositioned seal at (0,0) and reports a
	# placement bug that does not exist.
	#
	# ALPHA IS THE WRONG SIGNAL and cost a second run to learn: a fresh Control
	# defaults to modulate.a = 1.0, so "wait until it is visible" passes on the
	# very first frame — before the code that sets it to 0 has even run. The
	# armed SCALE is the honest one: nothing sets 2.4 except the press itself.
	guard = 0
	while sc.scale.x < 2.0 and guard < 900:
		guard += 1
		await get_tree().process_frame

	# Mid-descent: poll the scale, never the clock. Starts at 2.4, drives to 1.06.
	guard = 0
	while sc.scale.x > 2.0 and guard < 900:
		guard += 1
		await get_tree().process_frame
	await _snap("_shot_seal_%s_descent.png" % tag)

	# Contact: the descent bottoms out at the squeeze (1.06) before flowing back.
	guard = 0
	while sc.scale.x > 1.10 and guard < 900:
		guard += 1
		await get_tree().process_frame
	print("[seal:%s] gpos=%s scale=%s mod=%s"
		% [tag, str(sc.global_position), str(sc.scale), str(sc.modulate)])
	await _snap("_shot_seal_%s_contact.png" % tag)

	await get_tree().create_timer(0.9).timeout
	await _snap("_shot_seal_%s_settled.png" % tag)

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://" + path)
	print("SAVED ", path)
