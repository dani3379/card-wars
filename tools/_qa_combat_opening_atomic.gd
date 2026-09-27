extends SceneTree
## Frame-by-frame regression for Combat's atomic opening cover.
##
## Run windowed so the normal-motion case can observe the release fade:
##   Godot --path D:\Godot --script res://tools/_qa_combat_opening_atomic.gd
##   Godot --path D:\Godot --script res://tools/_qa_combat_opening_atomic.gd -- --reduced

const TIMEOUT_MS := 20000
const SHOT_PATH := "res://tools/screenshot/combat_opening_cover_qa.png"

var _started := false
var _failures := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var reduced := OS.get_cmdline_user_args().has("--reduced")
	var mode := "Reduce Motion" if reduced else "animated"
	var run_state: Node = root.get_node("RunState")
	var settings: Node = root.get_node("UserSettings")
	run_state.set("active_slot", -1)
	settings.set("reduce_motion", reduced)
	settings.set("particles", false)
	settings.set("anim_speed", 1.0)
	settings.set("end_turn_warning", false)
	settings.set("coaching_mode", 2)
	run_state.start_new_run("stalwart", 0, 20260928)
	run_state.set("active_slot", -1)
	run_state.set("current_encounter_id", "goblin_scouts")
	run_state.set("current_node_type", "combat")
	run_state.set("current_setpiece_id", "")
	run_state.set("current_mutator_id", "")

	var combat: Node = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	current_scene = combat

	# _ready reaches its first await only after the scene-owned cover is mounted.
	var layer: CanvasLayer = combat.get("_opening_cover_layer")
	var cover: Control = combat.get("_opening_cover_root")
	_check(bool(combat.get_meta("_combat_opening_cover_active", false)),
		"%s opening gate is active before add_child returns" % mode)
	_check(layer != null and is_instance_valid(layer),
		"%s cover exists before the first rendered frame" % mode)
	_check(layer != null and layer.layer == 220,
		"%s cover owns the high presentation layer" % mode)
	_check(cover != null and cover.mouse_filter == Control.MOUSE_FILTER_STOP,
		"%s cover catches pointer input while the field builds" % mode)

	# Direct method calls are harsher than keyboard routing: even they must not
	# let the initial enum value masquerade as a live player turn.
	var round_before := int(combat.get("round_number"))
	var phase_before := int(combat.get("phase"))
	combat.call("_on_end_turn")
	combat.call("_request_space_end_turn")
	_check(int(combat.get("round_number")) == round_before
		and int(combat.get("phase")) == phase_before,
		"%s End Turn is inert throughout opening construction" % mode)

	await RenderingServer.frame_post_draw
	layer = combat.get("_opening_cover_layer")
	cover = combat.get("_opening_cover_root")
	_check(layer != null and cover != null and cover.is_visible_in_tree(),
		"%s first painted frame contains the opening cover" % mode)
	if cover != null:
		_check(cover.size.x >= 1599.0 and cover.size.y >= 899.0,
			"%s first painted cover fills the 1600x900 canvas" % mode)
		_check(cover.modulate.a >= 0.999,
			"%s first painted cover is fully opaque" % mode)
	if not reduced:
		var image: Image = root.get_texture().get_image()
		var err := image.save_png(SHOT_PATH)
		_check(err == OK, "animated opening screenshot is captured")

	var alpha_steps: Array[float] = []
	var saw_release_fade := false
	var first_fade_was_settled := true
	var all_buttons_locked := true
	var cover_was_topmost := true
	_append_alpha(alpha_steps, 1.0)
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while bool(combat.get_meta("_combat_opening_cover_active", false)) \
			and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		layer = combat.get("_opening_cover_layer")
		cover = combat.get("_opening_cover_root")
		var end_button: Button = combat.get("_end_turn_btn")
		if end_button != null and is_instance_valid(end_button) and not end_button.disabled:
			all_buttons_locked = false
		if layer != null and is_instance_valid(layer):
			cover_was_topmost = cover_was_topmost and _is_topmost_layer(combat, layer)
		if cover != null and is_instance_valid(cover):
			var alpha := cover.modulate.a
			_append_alpha(alpha_steps, alpha)
			if alpha < 0.999:
				saw_release_fade = true
				first_fade_was_settled = first_fade_was_settled \
					and _screen_is_settled(combat)

	_check(Time.get_ticks_msec() < deadline,
		"%s opening cover releases before the timeout" % mode)
	_check(all_buttons_locked,
		"%s primary action stays disabled until the cover has lifted" % mode)
	_check(cover_was_topmost,
		"%s cover remains above every Combat CanvasLayer" % mode)
	_check(_screen_is_settled(combat),
		"%s revealed screen has a complete board, HUD, and truthful piles" % mode)
	_check(first_fade_was_settled,
		"%s underlying screen is complete before the first translucent frame" % mode)

	if reduced:
		_check(not saw_release_fade,
			"Reduce Motion removes the cover atomically without a fade")
	else:
		_check(saw_release_fade and _has_intermediate_alpha(alpha_steps),
			"normal motion releases the settled field with a real coordinated fade")

	for _i in 2:
		await process_frame
	_check(combat.get("_opening_cover_layer") == null,
		"%s cover reference retires after reveal" % mode)
	print("[combat-opening] mode=%s alpha=%s failures=%d" % [
		mode, str(alpha_steps), _failures])
	quit(1 if _failures > 0 else 0)


func _screen_is_settled(combat: Node) -> bool:
	var hud: CanvasLayer = combat.get("_hud_layer")
	var board: Control = combat.get("_board_container")
	var draw_label: Label = combat.get("_deck_count_label")
	var discard_label: Label = combat.get("_discard_count_label")
	var exhaust_label: Label = combat.get("_exhaust_count_label")
	var draw_art: Control = combat.get("_deck_pile_art")
	var discard_art: Control = combat.get("_discard_pile_art")
	var exhaust_art: Control = combat.get("_exhaust_pile_art")
	if hud == null or not is_instance_valid(hud) \
			or board == null or not is_instance_valid(board):
		return false
	if (combat.get("_player_slots") as Array).size() != 4 \
			or (combat.get("_player_back_slots") as Array).size() != 4 \
			or (combat.get("_enemy_slots") as Array).size() != 4 \
			or (combat.get("_enemy_back_slots") as Array).size() != 4:
		return false
	if draw_label == null or discard_label == null or exhaust_label == null:
		return false
	if draw_art == null or discard_art == null or exhaust_art == null:
		return false
	return draw_label.text == str((combat.get("_player_draw_pile") as Array).size()) \
		and discard_label.text == str((combat.get("_player_discard_pile") as Array).size()) \
		and exhaust_label.text == str((combat.get("_exhaust_pile") as Array).size())


func _is_topmost_layer(combat: Node, opening: CanvasLayer) -> bool:
	for child in combat.get_children():
		if child is CanvasLayer and child != opening and child.layer >= opening.layer:
			return false
	return true


func _append_alpha(values: Array[float], value: float) -> void:
	var snapped := snappedf(value, 0.01)
	if values.is_empty() or not is_equal_approx(values[-1], snapped):
		values.append(snapped)


func _has_intermediate_alpha(values: Array[float]) -> bool:
	for value in values:
		if value > 0.01 and value < 0.99:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[combat-opening] PASS ", message)
	else:
		_failures += 1
		push_error("[combat-opening] FAIL " + message)
