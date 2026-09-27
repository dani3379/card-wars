extends Node
## _shot_tutorial_tips.gd — EYES on the re-sequenced tutorial ladder (2026-08-01).
## Windowed, editor closed:
##   Godot.exe --path "D:\Godot" res://tools/_shot_tutorial_tips.tscn
##
## The bug this guards is invisible to a headless probe: a tip whose FLAG is set,
## whose Label text is set, and which is nevertheless not on screen — erased by
## the round banner, clipped, or drawn under something. Two frames:
##   r1  the MUSTER tip, on the round with no enemy line (the new one)
##   r2  the intents tip, on the first round that HAS badges and forecast chips
## Outputs tools/screenshot/_tips_r1.png / _tips_r2.png — READ THEM.
##
## Restores the profile's tutorial flags on the way out: they are once-EVER
## settings and a shot harness has no business spending the developer's.

var _combat: Node = null
var _saved := {}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	for k in ["muster_tutorial_seen", "intents_tutorial_seen", "pile_tutorial_seen",
			"banking_tutorial_seen", "combat_model_tutorial_seen",
			"dismiss_tutorial_seen", "first_battle_tutorial_complete"]:
		_saved[k] = UserSettings.get(k)
	# `reset_tutorials` also clears `lessons_seen` and the registry-era lessons
	# live in there, so the named flags above are no longer the whole state —
	# without this the shot tool would spend the developer's coaching every run.
	# `coaching_mode` is forced FULL for the same reason the flags are cleared:
	# a developer with coaching off would otherwise photograph an empty screen.
	_saved["lessons_seen"] = UserSettings.lessons_seen.duplicate(true)
	_saved["coaching_mode"] = UserSettings.coaching_mode
	UserSettings.reset_tutorials()
	UserSettings.set_coaching_mode(TutorialDB.COACH_FULL)

	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP (from _shot_combat_hud): Card2D._combat_vfx_target() resolves the
	# VFX host through get_tree().current_scene, so add_child alone silently
	# no-ops every float, chip and log row.
	get_tree().current_scene = _combat

	# Round 1: shoot as soon as the hand is dealt plus a beat for the ROUND banner
	# to come and go — the banner is exactly what used to erase the tip, so
	# shooting BEFORE it would prove nothing.
	await _wait_for_round(1)
	await get_tree().create_timer(2.2).timeout
	await _shoot("r1")
	print("[tips] r1 tutorial stage = %s" % _combat.get(
		"_first_battle_tutorial_stage"))
	var chosen: Control = _combat.get("_first_battle_tutorial_card")
	var slots: Array[Control] = _combat.get("_player_slots")
	if chosen != null and is_instance_valid(chosen) and not slots.is_empty():
		chosen.global_position = slots[0].get_global_rect().get_center() - chosen.size * 0.5
		_combat.call("_on_card_played", chosen)
	await get_tree().create_timer(0.8).timeout
	await _shoot("r1_commit")

	# Commit, let the hold muster, then capture the round-two board lesson.
	_combat.call("_on_end_turn")


	# Round 2: end the turn, let the hold muster and the clash resolve. The wait
	# is deliberate — a tip holds the channel for 7 s and a real player spends
	# longer than that on their first turn, so ending instantly would shoot round
	# 2 with round 1's tip still up and prove nothing about the second rung.
	await _wait_for_round(2)
	await get_tree().create_timer(2.0).timeout
	Input.warp_mouse(Vector2(8, 8))
	await get_tree().process_frame
	await _shoot("r2")
	print("[tips] r2 tutorial stage = %s" % _combat.get(
		"_first_battle_tutorial_stage"))

	_combat.call("_finish_first_battle_tutorial")
	for k in _saved:
		UserSettings.set(k, _saved[k])
	UserSettings.save()
	print("TUTORIAL_TIP_SHOTS_DONE")
	get_tree().quit()


func _label_text() -> String:
	var lbl = _combat.get("_info_label")
	if lbl == null or not is_instance_valid(lbl):
		return "<no label>"
	return "\"%s\" (visible=%s alpha=%.2f)" % [
		lbl.text, str(lbl.is_visible_in_tree()), lbl.modulate.a]


func _wait_for_round(n: int) -> void:
	var waited := 0
	while waited < 600:
		if is_instance_valid(_combat) and _combat.round_number >= n \
				and not _combat._hand.is_empty():
			return
		await get_tree().create_timer(0.05).timeout
		waited += 1


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_tips_%s.png" % tag)
	print("SAVED tips_", tag, " ", img.get_size())
