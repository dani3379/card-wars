extends Node
## _probe_focus_clash.gd — the spotlight AT WORK, at two ink strengths.
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_probe_focus_clash.tscn -- --alpha=0.38
##
## `_probe_focus_alpha` sweeps the ink on a STATIC planning board, which is the
## right way to get clean numbers but the wrong board to judge on: during the
## planning phase every lane wears a bright forecast chip, and during the CLASH
## the forecast is gone and the spotlight is the only thing saying where to look.
## So this runs a real serialized clash and photographs it lane by lane.
##
## THE COMPOSITE IS HONEST HERE, unlike the sweep. The sweep reached alpha A by
## scaling `_strength`, which also scales the accent bracket (`0.62 * _strength`)
## — fine for luminance samples taken inside cards, misleading in a picture. This
## instead leaves the shipped control completely alone at `_strength = 1.0` (ink
## 0.30, bracket 0.62) and lays a TOP-UP slab over the same surround geometry at
##
##     B = 1 - (1 - A) / (1 - 0.30)
##
## so the composited surround is exactly alpha A while the bracket stays exactly
## as it ships. The top-up tracks the live `_focus_rect` every frame, so it
## follows the real clash from column to column.
##
## Frames are named with the alpha and the millisecond offset, so an A/B is a
## matter of lining up two runs.

const STATE_TIMEOUT := 90.0
const POLL := 0.2
const SHOT_DIR := "res://tools/screenshot/focus_alpha"
const SHIPPED_ALPHA := 0.30
const ENC := "oathbroken_knights"
const CADENCE := 0.075

var _combat: Node = null
var _focus: Control = null
var _topup: Control = null
var _alpha := 0.38
var _shot_i := 0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[fc] WATCHDOG"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--alpha="):
			_alpha = float(a.substr(8))
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.clash_dwell_scale = 1.0
	UserSettings.particles = true
	UserSettings.screen_shake = true
	UserSettings.combat_telegraph = true
	UserSettings.end_turn_warning = false
	for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
			"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
			"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
			"mark_sacrifice_tutorial_seen"]:
		if UserSettings.has_method(m):
			UserSettings.call(m)

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = 1
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame
	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	Input.warp_mouse(Vector2(4, 4))
	await get_tree().process_frame
	get_viewport().gui_disable_input = true

	if not await _await_state(1, false):
		return
	_combat.call("_on_end_turn")
	if not await _await_state(2, true):
		return
	await get_tree().create_timer(2.4).timeout
	_stage()
	await get_tree().create_timer(1.4).timeout

	_focus = _combat.get("_clash_lane_focus")
	if _focus == null or not is_instance_valid(_focus):
		print("[fc] ABORT — no ClashLaneFocus")
		get_tree().quit(1)
		return
	var b: float = 0.0 if _alpha <= SHIPPED_ALPHA \
		else 1.0 - (1.0 - _alpha) / (1.0 - SHIPPED_ALPHA)
	print("[fc] target surround alpha=%.2f  (shipped %.2f + top-up %.4f)" % [
		_alpha, SHIPPED_ALPHA, b])
	if _alpha < SHIPPED_ALPHA:
		print("[fc] NOTE — below the shipped ink; cannot be composited additively.")
		print("[fc]        Falling back to _strength scaling (bracket also dims).")
		_focus.set("_strength", _alpha / SHIPPED_ALPHA)
	_install_topup(b)

	print("[fc] clash begins")
	_combat.call("_on_end_turn")
	await _capture_until(3, 2.0)
	print("[fc] frames written: %d  -> %s" % [_shot_i, SHOT_DIR])
	print("[fc] FOCUS_CLASH_DONE")
	get_tree().quit()


## A bare Control on the same parent, one z above the real focus, drawing ONLY the
## four surround slabs — no bracket, no ticks. It reads the shipped node's live
## `_focus_rect` and `_strength` each frame, so it lights and clears with it and
## never draws over the active column.
func _install_topup(b: float) -> void:
	if b <= 0.0:
		return
	_topup = Control.new()
	_topup.name = "FocusTopUp"
	_topup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topup.z_index = int(_focus.z_index) + 1
	_focus.get_parent().add_child(_topup)
	_topup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_topup.draw.connect(func():
		var st := float(_focus.get("_strength"))
		var fr: Rect2 = _focus.get("_focus_rect")
		if st <= 0.001 or fr.size.x <= 0.0:
			return
		var sz: Vector2 = _topup.size
		var x0 := clampf(fr.position.x, 0.0, sz.x)
		var y0 := clampf(fr.position.y, 0.0, sz.y)
		var x1 := clampf(fr.end.x, 0.0, sz.x)
		var y1 := clampf(fr.end.y, 0.0, sz.y)
		if x1 <= x0 or y1 <= y0:
			return
		var ink := Color(0.018, 0.013, 0.010, b * st)
		if y0 > 0.0:
			_topup.draw_rect(Rect2(0.0, 0.0, sz.x, y0), ink)
		if y1 < sz.y:
			_topup.draw_rect(Rect2(0.0, y1, sz.x, sz.y - y1), ink)
		if x0 > 0.0:
			_topup.draw_rect(Rect2(0.0, y0, x0, y1 - y0), ink)
		if x1 < sz.x:
			_topup.draw_rect(Rect2(x1, y0, sz.x - x1, y1 - y0), ink))
	set_process(true)


func _process(_dt: float) -> void:
	if _topup != null and is_instance_valid(_topup):
		_topup.queue_redraw()


func _capture_until(target_round: int, tail: float) -> void:
	var t := Time.get_ticks_msec()
	var deadline := -1
	while true:
		Input.warp_mouse(Vector2(4, 4))
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - t
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s/clash_a%03d_%05dms.jpg" % [
			SHOT_DIR, int(round(_alpha * 100.0)), ms], 0.94)
		_shot_i += 1
		if deadline < 0 and int(_combat.get("round_number")) >= target_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN:
			deadline = ms + int(tail * 1000.0)
		if deadline >= 0 and ms >= deadline:
			return
		if ms > 30000:
			return
		await get_tree().create_timer(CADENCE).timeout


## Same designed outcome pattern as `_shot_clash_read`: lane 0 mutual kill,
## lane 1 nothing dies, lane 2 a kill plus overkill onto the body behind, lane 3
## an open face strike. Four corpses across three columns.
func _stage() -> void:
	var ef := [[3, 3], [2, 8], [2, 3], [4, 4]]
	var eb := {2: [3, 2]}
	var pf := [[7, 2], [2, 9], [6, 4], null]
	var pn := ["Pikeman", "Palisade", "Outrider", ""]
	for lane in range(4):
		var e = _cell(true, 0, lane)
		if e == null:
			_combat.call("_place_enemy_card", EncounterDB.make_card_data(
				{"name": "Footman", "atk": ef[lane][0], "hp": ef[lane][1], "kw": []}),
				lane, 0, false)
			e = _cell(true, 0, lane)
		_force(e, ef[lane][0], ef[lane][1])
	for lane in eb.keys():
		var e2 = _cell(true, 1, int(lane))
		if e2 == null:
			_combat.call("_place_enemy_card", EncounterDB.make_card_data(
				{"name": "Squire", "atk": eb[lane][0], "hp": eb[lane][1], "kw": []}),
				int(lane), 1, false)
			e2 = _cell(true, 1, int(lane))
		_force(e2, eb[lane][0], eb[lane][1])
	for lane in range(4):
		if pf[lane] == null:
			continue
		var p = _cell(false, 0, lane)
		if p == null:
			_combat.call("summon_token", pf[lane][0], pf[lane][1], lane, false, 0,
				{}, pn[lane], [])
			p = _cell(false, 0, lane)
		_force(p, pf[lane][0], pf[lane][1])
	for c in (_combat.call("_all_creatures_both_sides") as Array):
		c.state.ready_to_swing = true
		c.has_attacked_this_turn = false
		if c.is_opponent:
			c.state.current_intent = "ATK"
			_combat.call("_update_intent_display", c, "ATK")
	_combat.call("_refresh_adjacency_buffs")
	_combat.set("_friendly_deaths_this_round", 0)
	_combat.set("_enemy_deaths_this_round", 0)
	_combat.call("_update_hud")


func _cell(is_enemy: bool, row: int, lane: int):
	var c = (_combat.call("_row_array", is_enemy, row))[lane]
	return c if (c != null and is_instance_valid(c)) else null


func _force(card, atk: int, hp: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	for kw in ["last_stand", "regenerate"]:
		if card.card_data.get("keywords", []).has(kw):
			card.card_data["keywords"].erase(kw)
	card.card_data.erase("adj_buff")
	card.card_data["atk"] = atk
	card.card_data["hp"] = hp
	card.current_atk = atk
	card.current_hp = hp
	card.state.temp_atk_buff = 0
	card.state.persistent_atk_buff = 0
	card.state.adjacency_atk_buff = 0
	card.call("update_stat_display")


func _await_state(min_round: int, want_enemies: bool) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if int(_combat.get("round_number")) >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[fc] ABORT — timed out waiting for round ", min_round)
	get_tree().quit(1)
	return false
