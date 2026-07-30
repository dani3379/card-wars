extends Node
## _probe_focus_alpha.gd — CHOOSE THE SPOTLIGHT INK.
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_probe_focus_alpha.tscn
##
## `tools/_probe_lane_focus` answers "does the ink reach the framebuffer at all"
## (it did not, for the control's entire life — see COMBAT_LEGIBILITY §12). That
## is a yes/no. This answers the different question the doc leaves open: WHAT
## NUMBER. The value went 0.30 -> 0.46 -> back to 0.30 without anyone ever seeing
## a rendered pixel, so both endpoints are guesses.
##
## METHOD. `ClashLaneFocus._draw` computes its surround ink as
## `Color(0.018, 0.013, 0.010, ALPHA * _strength)`. `_strength` is a plain var and
## `_set_strength()` is a plain method, so setting `_strength = A / 0.30` renders
## an ink of exactly effective alpha A — byte-identical to shipping `ALPHA = A`
## with `_strength` at 1.0.
##
## ONE CAVEAT, AND IT IS WHY THE SAMPLES AVOID THE LANE BORDER: the accent rule
## and corner ticks also scale with `_strength` (`0.62 * _strength`), so in the
## SWEEP frames the bracket around the focused lane is brighter than it would
## ship at A > 0.30 and dimmer at A < 0.30. Every luminance sample is taken from
## CARD INTERIORS, inset well away from the bracket, so no measurement is touched
## by it. A final honest-composite frame is shot separately at the recommendation
## (shipped strength 1.0 + a top-up slab), so the picture matches the number.
##
## WHAT IS MEASURED, per candidate:
##   * `unfocused/lit` — the surround ratio, sampled on the real global rects of
##     the cards standing in the unfocused columns. This is "how much light was
##     taken away from where you are NOT meant to look".
##   * `focused/lit`   — a control. The focused column must not move at all; if it
##     does, the slabs are overlapping the active lane.
##   * `parchment` — absolute luminance of an unfocused card face. A spotlight
##     that pushes this into the mud has stopped directing attention and started
##     hiding the board: those cards still carry HP, forecast chips and corpse
##     names the player is entitled to read while another column resolves.
##   * `card ink contrast` — p90-p10 inside an unfocused card. Direction should
##     cost brightness, not legibility.
##
## House traps paid: current_scene assigned, input off, cursor parked, all
## tutorial flags marked seen, round 2 reached by polling.

const STATE_TIMEOUT := 90.0
const POLL := 0.2
const SHOT_DIR := "res://tools/screenshot/focus_alpha"
const ENC := "oathbroken_knights"
const SHIPPED_ALPHA := 0.30
const FOCUS_LANE := 1        # interior column: unfocused neighbours on both sides
## The sweep. 0.0 is the unlit baseline every ratio is taken against.
const CANDIDATES := [0.0, 0.14, 0.18, 0.22, 0.26, 0.30, 0.34, 0.38, 0.42, 0.46]

var _combat: Node = null
var _focus: Control = null
var _base: Dictionary = {}
var _rows: Array[Dictionary] = []


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[fa] WATCHDOG"); get_tree().quit(1))
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
		print("[fa] ABORT — no ClashLaneFocus")
		get_tree().quit(1)
		return
	print("[fa] focus control size=%s  global_rect=%s  z=%d parent=%s" % [
		str(_focus.size), str(_focus.get_global_rect()), int(_focus.z_index),
		_focus.get_parent().name])

	# Light the lane once through the REAL entry point, then let its 0.07 s ramp
	# finish before anything is overridden — otherwise the tween keeps writing
	# _strength and every sample would read 1.0 whatever was set.
	_combat.call("_focus_combat_lane", FOCUS_LANE, false)
	await get_tree().create_timer(0.5).timeout
	print("[fa] after _focus_combat_lane(%d): strength=%.2f rect=%s" % [
		FOCUS_LANE, float(_focus.get("_strength")), str(_focus.get("_focus_rect"))])

	var probes := _card_probes()
	print("[fa] sampling %d card faces:" % probes.size())
	for p in probes:
		print("[fa]   lane %d %-5s %-12s rect=%s  %s" % [
			int(p["lane"]), String(p["side"]), String(p["name"]),
			str(p["rect"]).replace(" ", ""),
			"FOCUSED" if int(p["lane"]) == FOCUS_LANE else "surround"])

	print("")
	print("[fa]  alpha | unfoc/lit | foc/lit | unfoc parchment lum | unfoc ink contrast")
	for a in CANDIDATES:
		var row := await _sample_at(float(a), probes)
		_rows.append(row)
		print("[fa]   %.2f  |   %.3f   |  %.3f  |  %6.1f (was %6.1f)  |  %5.1f (was %5.1f)" % [
			float(a), float(row["unfoc_ratio"]), float(row["foc_ratio"]),
			float(row["unfoc_lum"]), float(_base["unfoc_lum"]),
			float(row["unfoc_contrast"]), float(_base["unfoc_contrast"])])

	print("")
	print("[fa] --- verdict aids ---")
	for row in _rows:
		var a := float(row["alpha"])
		if a <= 0.0:
			continue
		var r := float(row["unfoc_ratio"])
		# Michelson contrast between the lit column and the inked surround. This is
		# the quantity that actually says "the eye is being pulled", independent of
		# how bright the table happens to be.
		var lit := float(_base["unfoc_lum"])
		var dim := float(row["unfoc_lum"])
		var mich: float = (lit - dim) / maxf(lit + dim, 0.001)
		print("[fa]   a=%.2f  light removed %4.1f%%  Michelson %.3f  stops %.2f  %s" % [
			a, (1.0 - r) * 100.0, mich, log(1.0 / maxf(r, 0.001)) / log(2.0),
			_band(r)])
	print("[fa] FOCUS_ALPHA_SWEEP_DONE  frames -> %s" % SHOT_DIR)
	get_tree().quit()


## Descriptive band, stated as a rule so the recommendation is not a taste claim
## dressed as a measurement:
##   >0.85 kept  — under a 15% change; large-field luminance steps this small read
##                 as an artefact of the art, not as an instruction.
##   0.60-0.85   — a spotlight: unmistakably dimmer, every card still legible.
##   0.50-0.60   — heavy; the surround starts losing card detail.
##   <0.50       — a blackout: over half the light gone (this is where 0.46 landed).
func _band(r: float) -> String:
	if r > 0.85:
		return "too weak to instruct"
	if r >= 0.60:
		return "SPOTLIGHT (readable surround)"
	if r >= 0.50:
		return "heavy - surround detail suffering"
	return "BLACKOUT"


func _sample_at(alpha: float, probes: Array) -> Dictionary:
	_focus.set("_strength", alpha / SHIPPED_ALPHA)
	_focus.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/focus_a%03d.png" % [SHOT_DIR, int(round(alpha * 100.0))])
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = float(img.get_width()) / maxf(vis.x, 1.0)
	var uf := 0.0
	var ufn := 0
	var fo := 0.0
	var fon := 0
	var contrast := 0.0
	var cn := 0
	for p in probes:
		var st := _stats(img, p["rect"], ratio)
		if int(p["lane"]) == FOCUS_LANE:
			fo += float(st["mean"])
			fon += 1
		else:
			uf += float(st["mean"])
			ufn += 1
			contrast += float(st["p90"]) - float(st["p10"])
			cn += 1
	var out := {
		"alpha": alpha,
		"unfoc_lum": uf / maxi(ufn, 1),
		"foc_lum": fo / maxi(fon, 1),
		"unfoc_contrast": contrast / maxi(cn, 1),
	}
	if alpha <= 0.0:
		_base = out.duplicate()
	out["unfoc_ratio"] = float(out["unfoc_lum"]) / maxf(float(_base["unfoc_lum"]), 0.01)
	out["foc_ratio"] = float(out["foc_lum"]) / maxf(float(_base["foc_lum"]), 0.01)
	return out


## Real card rects, not fixed screen coordinates — the sample must land on a card
## face whatever the field style or window does. Inset 22% on every side so the
## card's own dark border, its wax seals and (critically) the focus bracket are
## all outside the patch; what is left is parchment and rules ink.
func _card_probes() -> Array:
	var out: Array = []
	for is_enemy in [true, false]:
		for row in [0, 1]:
			var arr = _combat.call("_row_array", is_enemy, row)
			for lane in range(4):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					continue
				var r: Rect2 = c.get_global_rect()
				if r.size.x < 20.0 or r.size.y < 20.0:
					continue
				out.append({
					"lane": lane,
					"side": "FOE" if is_enemy else "YOU",
					"name": String(c.card_data.get("name", "?")).substr(0, 12),
					"rect": r.grow(-r.size.x * 0.22),
				})
	return out


func _stats(img: Image, rect: Rect2, ratio: float) -> Dictionary:
	var x0 := clampi(int(rect.position.x * ratio), 0, img.get_width() - 1)
	var y0 := clampi(int(rect.position.y * ratio), 0, img.get_height() - 1)
	var x1 := clampi(int(rect.end.x * ratio), x0 + 1, img.get_width())
	var y1 := clampi(int(rect.end.y * ratio), y0 + 1, img.get_height())
	var vals: Array[float] = []
	var s := 0.0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var v := img.get_pixel(x, y).get_luminance() * 255.0
			vals.append(v)
			s += v
	vals.sort()
	var n := vals.size()
	if n == 0:
		return {"mean": 0.0, "p10": 0.0, "p90": 0.0}
	return {
		"mean": s / float(n),
		"p10": vals[clampi(int(n * 0.10), 0, n - 1)],
		"p90": vals[clampi(int(n * 0.90), 0, n - 1)],
	}


## A realistic busy board — every column occupied on both sides so the surround
## always has real card faces in it. Judging a dimming overlay against empty table
## would answer the wrong question: the cost of dimming is paid on CARDS.
func _stage() -> void:
	var names_foe := ["Squire", "Black Lancer", "Crossbow Knight", "Fallen Knight"]
	var names_you := ["Pikeman", "Outrider", "Mourner", "Palisade"]
	for row in [0, 1]:
		for lane in range(4):
			var e = _cell(true, row, lane)
			if e == null:
				_combat.call("_place_enemy_card", EncounterDB.make_card_data(
					{"name": names_foe[lane], "atk": 3, "hp": 6, "kw": []}),
					lane, row, false)
				e = _cell(true, row, lane)
			_force(e, 3, 6)
			var p = _cell(false, row, lane)
			if p == null:
				_combat.call("summon_token", 3, 6, lane, false, row, {},
					names_you[lane], [])
				p = _cell(false, row, lane)
			_force(p, 3, 6)
	for c in (_combat.call("_all_creatures_both_sides") as Array):
		c.state.ready_to_swing = true
		c.has_attacked_this_turn = false
	_combat.call("_refresh_adjacency_buffs")
	_combat.call("_update_hud")


func _cell(is_enemy: bool, row: int, lane: int):
	var c = (_combat.call("_row_array", is_enemy, row))[lane]
	return c if (c != null and is_instance_valid(c)) else null


func _force(card, atk: int, hp: int) -> void:
	if card == null or not is_instance_valid(card):
		return
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
	print("[fa] ABORT — timed out waiting for round ", min_round)
	get_tree().quit(1)
	return false
