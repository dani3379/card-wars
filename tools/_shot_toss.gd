extends Node
## Shoots the skirmish turn-order toss: the coin mid-spin and the settled choice
## screen. A settled shot alone can't tell a real spin from a static coin, so the
## burst samples the arc too.

var _combat = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_act_idx = 0
	await get_tree().process_frame
	_combat = load("res://scenes/combat.tscn").instantiate()
	add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	var waited := 0
	while waited < 400:
		if is_instance_valid(_combat) and _combat.round_number >= 1:
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1

	# Drive the modal directly — booting a real two-peer match just to see a
	# screen is not worth it, and the modal owns its own presentation.
	_combat._net_show_order_choice()
	for i in 7:
		await _capture("toss_%d" % i)
		await get_tree().create_timer(0.11).timeout
	await get_tree().create_timer(0.9).timeout
	await _capture("toss_settled")

	# Sealed Orders asks a DIFFERENT question (initiative, not turn order), so
	# shoot that variant too — the copy branches and only a render proves it.
	for c in _combat.get_children():
		if c is CanvasLayer and c.layer == 30:
			c.queue_free()
	await get_tree().process_frame
	# _is_sealed() requires _is_net(), and this harness boots a SOLO combat — so
	# force the mode too, else the sealed branch silently renders alternating
	# copy (which is exactly what happened the first time).
	NetMatch.battle_style = NetMatch.STYLE_SEALED
	_combat.combat_mode = _combat.CombatMode.NET_HOST
	_combat._net_show_order_choice()
	await get_tree().create_timer(2.0).timeout
	await _capture("toss_sealed")
	get_tree().quit(0)


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_LANCZOS)
	image.save_png("res://tools/screenshot/_%s.png" % tag)
	print("  SAVED  ", tag)
