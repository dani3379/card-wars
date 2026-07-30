extends Node
## _shot_clash_flush.gd — the MASS GRAVE case.
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_shot_clash_flush.tscn
##
## `_shot_clash_read.gd` staged a 4-vs-5 board and got a 4-corpse clash, which the
## corpse-naming (`_name_the_fallen`) handled cleanly. But the open question in
## docs/COMBAT_LEGIBILITY_20260728.md §11 #1 is specifically *"does the corpse
## naming read as informative or as clutter AT FIVE-AT-ONCE"* — and a 4-corpse
## sample cannot answer it, least of all when three of those corpses fell in the
## same column and therefore rode the callout stacker.
##
## So this stages the worst honest case the board allows: a FULL sixteen-body
## table (4x4 both sides) where every column is lethal both ways, and shoots the
## death flush at ~60 ms. What matters is the WIDTH of the pile — names landing
## in four different columns at once, which `spawn_keyword_callout`'s stacker
## explicitly does NOT help with (it only offsets chips within 92 px).
##
## Same house traps as its sibling: current_scene assignment, input off, cursor
## parked, tutorial marked seen, round 2 reached by polling not sleeping.

const STATE_TIMEOUT := 90.0
const POLL := 0.2
const SHOT_DIR := "res://tools/screenshot/clash_read"

var _combat: Node = null
var _shot_i := 0
var _peak_chips := 0
var _peak_floats := 0
var _tracing := false
var _t0 := 0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[flush] WATCHDOG"); get_tree().quit(1))
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
	UserSettings.end_turn_warning = false
	# See _shot_clash_read: every tutorial tip holds _info_label for 7 s and four
	# fire from inside _start_round, so an isolated (fresh) user dir photographs
	# tutorial copy as if it were combat copy.
	for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
			"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
			"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
			"mark_sacrifice_tutorial_seen"]:
		if UserSettings.has_method(m):
			UserSettings.call(m)

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = 1
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "oathbroken_knights"
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
	await get_tree().create_timer(2.0).timeout
	_stage_full_board()
	await get_tree().create_timer(1.6).timeout
	_report()
	await _shoot("massgrave_before")

	_t0 = Time.get_ticks_msec()
	_tracing = true
	set_process(true)
	_combat.call("_on_end_turn")
	# The FRAMES were captured on the first run of this harness (g*.jpg) and are
	# kept; what the 14 s capture window could NOT reach was the END. A full
	# sixteen-body clash was still flushing corpses when the capture stopped, so
	# the headline pacing number for a full board was unknown. Timing it needs a
	# run that spends nothing on JPEG encoding, so this pass is trace-only.
	await _time_to_playable()
	_tracing = false
	set_process(false)
	print("[flush] peak concurrent callout chips=%d  floating numbers=%d" % [
		_peak_chips, _peak_floats])
	print("[flush] frames written: %d" % _shot_i)
	print("[flush] DONE")
	get_tree().quit()


## Every column lethal in both directions: 4 ATK against 3 HP everywhere, so the
## front ranks wipe each other and the back ranks then wipe what is left. Names
## are DISTINCT per body — a pile of four identical "FOOTMAN" chips would flatter
## the legibility question by making overlap invisible.
const YOURS := ["Pikeman", "Outrider", "Mourner", "Palisade",
	"Bowman", "Sapper", "Drummer", "Standard"]
const THEIRS := ["Squire", "Black Lancer", "Crossbow Knight", "Fallen Knight",
	"Footman", "Forsworn", "Lance Serjeant", "Oathbreaker"]


func _stage_full_board() -> void:
	var i := 0
	for row in [0, 1]:
		for lane in range(4):
			var c = _cell(true, row, lane)
			if c == null:
				_combat.call("_place_enemy_card",
					EncounterDB.make_card_data({"name": THEIRS[i], "atk": 4, "hp": 3,
						"kw": []}), lane, row, false)
				c = _cell(true, row, lane)
			else:
				c.card_data["name"] = THEIRS[i]
			_force(c, 4, 3)
			var p = _cell(false, row, lane)
			if p == null:
				_combat.call("summon_token", 4, 3, lane, false, row, {}, YOURS[i], [])
				p = _cell(false, row, lane)
			_force(p, 4, 3)
			i += 1
	for c2 in (_combat.call("_all_creatures_both_sides") as Array):
		c2.state.ready_to_swing = true
		c2.has_attacked_this_turn = false
		if c2.is_opponent:
			c2.state.current_intent = "ATK"
			_combat.call("_update_intent_display", c2, "ATK")
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
	for kw in ["last_stand", "regenerate", "armored", "thorns"]:
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


func _process(_dt: float) -> void:
	if not _tracing or _combat == null or not is_instance_valid(_combat):
		return
	var hud = _combat.get("_hud_layer")
	if hud == null or not is_instance_valid(hud):
		return
	var fl := 0
	var ch := 0
	for c in hud.get_children():
		if c is Label and int(c.z_index) == 200:
			fl += 1
		elif c is PanelContainer and int(c.z_index) == 210:
			ch += 1
	if ch > _peak_chips or fl > _peak_floats:
		_peak_chips = maxi(_peak_chips, ch)
		_peak_floats = maxi(_peak_floats, fl)
		print("[flush] %5d ms  chips=%d floats=%d  cap='%s'  down=%d  P/E=%d/%d" % [
			Time.get_ticks_msec() - _t0, ch, fl,
			String(_combat.get("_phase_caption")), int(_combat.call("_downed_count")),
			(_combat.call("_all_player_creatures") as Array).size(),
			(_combat.call("_all_enemy_creatures") as Array).size()])


## Poll (cheaply) from the commit until the board is handed back, printing every
## caption transition and the corpse count as it drains. This is the honest
## "end turn -> playable" figure for a FULL board, the one Nielsen's 10 s limit
## is measured against.
func _time_to_playable() -> void:
	var t := Time.get_ticks_msec()
	var cap := ""
	var rn := int(_combat.get("round_number"))
	while Time.get_ticks_msec() - t < 60000:
		await get_tree().process_frame
		var c := String(_combat.get("_phase_caption"))
		if c != cap:
			cap = c
			print("[flush] %6d ms  cap='%s'  down=%d  P/E=%d/%d" % [
				Time.get_ticks_msec() - t, cap, int(_combat.call("_downed_count")),
				(_combat.call("_all_player_creatures") as Array).size(),
				(_combat.call("_all_enemy_creatures") as Array).size()])
		if int(_combat.get("round_number")) > rn \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN:
			print("[flush] %6d ms  ROUND %d — board handed back (END TURN -> PLAYABLE)" % [
				Time.get_ticks_msec() - t, int(_combat.get("round_number"))])
			return
	print("[flush] never became playable inside 60 s")


func _capture(ms_total: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms_total:
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - t
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s/g%03d_%05dms.jpg" % [SHOT_DIR, _shot_i, ms], 0.93)
		_shot_i += 1
		await get_tree().create_timer(0.02).timeout


func _report() -> void:
	for is_enemy in [true, false]:
		for row in [0, 1]:
			var cells: Array[String] = []
			for lane in range(4):
				var c = _cell(is_enemy, row, lane)
				cells.append("--" if c == null else "%s %d/%d" % [
					String(c.card_data.get("name", "?")).substr(0, 10),
					int(c.effective_atk()), int(c.current_hp)])
			print("[flush] %s %s: %s" % ["FOE" if is_enemy else "YOU",
				"front" if row == 0 else " back", " | ".join(cells)])


func _shoot(tag: String) -> void:
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
	print("[flush] SAVED %s.png" % tag)


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
	print("[flush] ABORT — timed out")
	get_tree().quit(1)
	return false
