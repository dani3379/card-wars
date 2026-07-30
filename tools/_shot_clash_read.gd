extends Node
## _shot_clash_read.gd — LOOK AT THE SERIALIZED CLASH.
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_shot_clash_read.tscn
##
## docs/COMBAT_LEGIBILITY_20260728.md §11 #1 is the only open backlog item that
## no probe can close: "play a fight and feel it". Everything in that pass is
## verified by arithmetic, by unit probes and by pixel measurement of individual
## effects — but nobody has ever watched the SERIALIZED CLASH AS A WHOLE. This
## harness is the closest a machine gets: it stages a realistic mid-game act-2
## board, runs one real clash, and captures it densely enough to judge pacing.
##
## It produces TWO things, deliberately:
##
##   1. A TRACE (clean pass, no screenshots). Sampled every rendered frame:
##      phase caption, ClashLaneFocus rect + strength, info-label text, live
##      body counts, and the number of concurrently-animating callouts/floats.
##      This is the honest pacing record — screenshot encoding perturbs wall
##      clock, so timing verdicts must come from a pass that does not shoot.
##
##   2. FRAMES (shot pass). ~110 ms apart through a second, identically staged
##      clash, plus the planning phase before it and the round-open after it.
##      These are for the taste questions the trace cannot answer: is the
##      spotlight strong enough, does the corpse naming pile up, does the ledger
##      collide with anything.
##
## ── STAGING, AND WHY IT LOOKS LIKE THIS ────────────────────────────────────
## Round 1 is a MUSTER round: TAKE THE FIELD (2026-07-27) leaves
## `_opening_muster_pending` standing so the hold arrives at the END of round 1,
## and the muster delay (2026-07-21) means nothing swings the round it lands. So
## the first board that can actually fight is ROUND 2 — never sleep for it, poll.
##
## The board is then FORCED to a fixed plan so the same clash can be run twice
## and so the outcome pattern is known in advance:
##   lane 0  mutual kill      (two corpses in one column)
##   lane 1  nothing dies     (the control lane — is its dwell distinguishable?)
##   lane 2  enemy dies front rank, our body dies to the BACK rank behind it
##   lane 3  no body of ours  -> a face strike (the diagonal the doc complains of)
## Four corpses, which also trips the `fallen_n >= 3` mass-grave beat.
##
## Encounter is `oathbroken_knights` — the one act-2 hold with `passive_id: ""`.
## A start-of-round passive would inject captions and floats that are not part
## of what is being judged here.
##
## ── HOUSE TRAPS ALREADY PAID FOR (do not "simplify" these away) ────────────
##  * `get_tree().current_scene = combat` or Card2D renders NO damage numbers,
##    NO keyword chips and NO log rows (the 24-harness bug).
##  * `set_process_input(false)` stops keystrokes but NOT hover — the real
##    desktop cursor sits in this window. Cursor parked AND
##    `gui_disable_input` set, because a stray "HELD" overlay has ruined frames.
##  * The combat-model tutorial tip writes `_info_label.text` directly and holds
##    it SEVEN SECONDS on the first end-turn. Marked seen before boot, or it
##    sits across the whole first clash.
##  * A staged blow that kills leaves a correctly-anchored numeral over an empty
##    lane. That is expected here, not a bug.

const STATE_TIMEOUT := 90.0
const POLL := 0.2
const SHOT_DIR := "res://tools/screenshot/clash_read"
## Target cadence. Actual spacing lands ~100-130 ms once the JPEG encode is
## paid; every filename carries its REAL offset so nothing is guessed.
const SHOT_CADENCE := 0.055
const ENC := "oathbroken_knights"

# The forced board. [atk, hp]; null = leave the column empty.
const ENEMY_FRONT := [[3, 3], [2, 8], [2, 3], [4, 4]]
const ENEMY_BACK := {2: [3, 2]}
const PLAYER_FRONT := [[7, 2], [2, 9], [6, 4], null]
const PLAYER_BACK := {1: [3, 5]}
const PLAYER_NAMES := ["Pikeman", "Palisade", "Outrider", ""]

var _combat: Node = null
var _tracing := false
var _t0 := 0
var _trace: Array[Dictionary] = []
var _shot_i := 0
var _problems: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(func():
		print("[clash] WATCHDOG — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# SHIP SETTINGS, NOT THIS MACHINE'S. The saved profile on the dev box has
	# Reduce Motion on; photographing the accessibility fallback would answer a
	# different question than the one asked.
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.clash_dwell_scale = 1.0     # "Normal" — the shipping default
	UserSettings.particles = true
	UserSettings.screen_shake = true         # judged as shipped, shake included
	UserSettings.combat_telegraph = true     # the forecast is question #6
	UserSettings.end_turn_warning = false
	# ALL of them, not just the combat model (2026-07-29). Every one of these writes
	# `_info_label.text` DIRECTLY for SEVEN SECONDS (_show_tutorial_tip), and four of
	# them fire from inside `_start_round`. On a machine whose profile has seen them
	# it does not matter; run this harness against an ISOLATED user dir (the way a
	# probe must, so it cannot clobber run_0.save) and the profile is fresh, so the
	# intents tip sits across the whole first clash and the pile tip across the
	# second. Both would be photographed as if they were combat copy.
	for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
			"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
			"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
			"mark_sacrifice_tutorial_seen"]:
		if UserSettings.has_method(m):
			UserSettings.call(m)

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = 1              # ACT 2 — the doc's representative board
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	_park_cursor()
	await get_tree().process_frame
	get_viewport().gui_disable_input = true

	# Constants are not properties — Object.get() returns null for them, which
	# would have printed a confident "LANE_DWELL=0.00" and invalidated the whole
	# pacing verdict. Read the script's constant map instead.
	var K: Dictionary = _combat.get_script().get_script_constant_map()
	print("[clash] anim_speed=%.2f dwell_scale=%.2f reduce_motion=%s" % [
		UserSettings.anim_speed, UserSettings.clash_dwell_scale,
		str(UserSettings.reduce_motion)])
	print("[clash] LANE_DWELL=%s LANE_DWELL_KILL=%s DEATH_BEAT=%s POST_HIT_BEAT=%s HITSTOP_BEAT=%s" % [
		str(K.get("LANE_DWELL")), str(K.get("LANE_DWELL_KILL")),
		str(K.get("DEATH_BEAT")), str(K.get("POST_HIT_BEAT")),
		str(K.get("HITSTOP_BEAT"))])

	if not await _await_state(1, false, "round 1 player turn"):
		return
	_combat.call("_on_end_turn")                       # round 1: the muster round
	if not await _await_state(2, true, "round 2 player turn with a live hold"):
		return
	await get_tree().create_timer(2.0).timeout          # let the ROUND 2 banner clear

	# ── PASS 1 — clean pacing trace, no screenshots ────────────────────────
	_stage_board("pass 1")
	await get_tree().create_timer(1.6).timeout
	print("")
	print("[clash] ===== PASS 1 (trace only, unperturbed) =====")
	_start_trace()
	_combat.call("_on_end_turn")
	await _await_state(3, false, "round 3 player turn")
	await get_tree().create_timer(2.6).timeout
	_stop_trace()
	_dump_trace("pass1")

	# ── PASS 2 — the same clash, photographed ──────────────────────────────
	await get_tree().create_timer(1.0).timeout
	_stage_board("pass 2")
	await get_tree().create_timer(1.8).timeout
	print("")
	print("[clash] ===== PASS 2 (dense frame capture) =====")
	_report_board("staged for the shot pass")

	# The planning phase FIRST — question #6 is about forecast clutter on a full
	# board, and that read only exists while the player still holds the turn.
	_combat.call("_request_lane_forecast_refresh")
	await get_tree().create_timer(0.5).timeout
	var fc: int = (_combat.get("_lane_forecast_nodes") as Array).size()
	print("[clash] forecast nodes on the full board: %d" % fc)
	print("[clash]   chips(labels)=%d rings/arrows=%d" % [
		_count_forecast(Label), fc - _count_forecast(Label)])
	await _shoot_png("plan_full")
	# The same board with the player's own line suppressed, as an A/B for the
	# "narrow it back to enemy-only?" question. Restored immediately.
	await _shoot_enemy_only_forecast()

	_start_trace()
	_combat.call("_on_end_turn")
	await _capture_until_round(4, 3.2)
	_stop_trace()
	_dump_trace("pass2")

	print("")
	print("[clash] frames written: %d  ->  %s" % [_shot_i, SHOT_DIR])
	if _problems.is_empty():
		print("[clash] CLASH_READ_DONE")
		get_tree().quit()
	else:
		for p in _problems:
			print("[clash] PROBLEM: ", p)
		print("[clash] CLASH_READ_INCOMPLETE")
		get_tree().quit(1)


# ── staging ────────────────────────────────────────────────────────────────

## Force the board to the fixed plan. Additive where it can be (an empty slot is
## filled) and corrective where it must be (an occupied slot is re-statted), so
## it can be run twice in one fight without ever removing a live body — removing
## one would fire on_death, the reactive hooks and the death counters, all of
## which would pollute the very beats being measured.
func _stage_board(tag: String) -> void:
	var placed := 0
	for lane in range(4):
		var want = ENEMY_FRONT[lane]
		if want == null:
			continue
		var c = _ecard(true, 0, lane)
		if c == null:
			_combat.call("_place_enemy_card", _mk("Footman", want[0], want[1]), lane, 0, false)
			c = _ecard(true, 0, lane)
			placed += 1
		_force(c, want[0], want[1])
	for lane in ENEMY_BACK.keys():
		var want2 = ENEMY_BACK[lane]
		var c2 = _ecard(true, 1, int(lane))
		if c2 == null:
			_combat.call("_place_enemy_card", _mk("Squire", want2[0], want2[1]), int(lane), 1, false)
			c2 = _ecard(true, 1, int(lane))
			placed += 1
		_force(c2, want2[0], want2[1])
	# Any enemy body the muster or the drip put somewhere the plan does not name
	# is left standing but made inert-ish (it will swing, it will not decide a
	# lane), so the plan's four columns still read the way they were designed to.
	for c3 in (_combat.call("_all_enemy_creatures") as Array):
		if _planned(true, int(c3.current_row), int(c3.current_lane)):
			continue
		_force(c3, 1, 6)

	for lane in range(4):
		var pw = PLAYER_FRONT[lane]
		if pw == null:
			continue
		var p = _ecard(false, 0, lane)
		if p == null:
			_combat.call("summon_token", pw[0], pw[1], lane, false, 0, {},
				PLAYER_NAMES[lane], [])
			p = _ecard(false, 0, lane)
			placed += 1
		_force(p, pw[0], pw[1])
	for lane in PLAYER_BACK.keys():
		var pw2 = PLAYER_BACK[lane]
		var p2 = _ecard(false, 1, int(lane))
		if p2 == null:
			_combat.call("summon_token", pw2[0], pw2[1], int(lane), false, 1, {},
				"Bowman", [])
			p2 = _ecard(false, 1, int(lane))
			placed += 1
		_force(p2, pw2[0], pw2[1])

	# Everything on the table forms up and takes orders. `ready_to_swing` is the
	# muster delay's state and `_start_round` is what normally sweeps it — doing
	# it here is exactly what the round-open does, not a cheat around the rule.
	for c4 in (_combat.call("_all_creatures_both_sides") as Array):
		c4.state.ready_to_swing = true
		c4.has_attacked_this_turn = false
		if c4.is_opponent:
			c4.state.current_intent = "ATK"
			_combat.call("_update_intent_display", c4, "ATK")
	_combat.call("_refresh_adjacency_buffs")
	# The stage's own top-ups must not be billed to the clash's ledger.
	_combat.set("_friendly_deaths_this_round", 0)
	_combat.set("_enemy_deaths_this_round", 0)
	_combat.call("_update_hud")
	print("[clash] staged (%s): %d bodies added" % [tag, placed])
	_report_board(tag)


func _planned(is_enemy: bool, row: int, lane: int) -> bool:
	if not is_enemy:
		return true
	if row == 0:
		return lane >= 0 and lane < 4 and ENEMY_FRONT[lane] != null
	return ENEMY_BACK.has(lane)


func _ecard(is_enemy: bool, row: int, lane: int):
	var arr = _combat.call("_row_array", is_enemy, row)
	var c = arr[lane]
	return c if (c != null and is_instance_valid(c)) else null


func _mk(nm: String, atk: int, hp: int) -> Dictionary:
	return EncounterDB.make_card_data({"name": nm, "atk": atk, "hp": hp, "kw": []})


## Pin a body's ATK/HP to the plan. Keywords are left alone (Armored / Thorns /
## Piercing are part of the visual load being judged) except `last_stand` and
## `regenerate`, which would silently turn a "this lane kills" column into one
## that does not and make the whole capture unreadable against its own plan.
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


# ── trace ──────────────────────────────────────────────────────────────────

func _start_trace() -> void:
	_trace.clear()
	_t0 = Time.get_ticks_msec()
	_tracing = true
	set_process(true)


func _stop_trace() -> void:
	_tracing = false
	set_process(false)


func _process(_dt: float) -> void:
	if not _tracing or _combat == null or not is_instance_valid(_combat):
		return
	var focus = _combat.get("_clash_lane_focus")
	var fr := Rect2()
	var fs := 0.0
	if focus != null and is_instance_valid(focus):
		fr = focus.get("_focus_rect")
		fs = float(focus.get("_strength"))
	var info: Label = _combat.get("_info_label")
	var hud = _combat.get("_hud_layer")
	var floats := 0
	var chips := 0
	if hud != null and is_instance_valid(hud):
		for ch in hud.get_children():
			if ch is Label and int(ch.z_index) == 200:
				floats += 1
			elif ch is PanelContainer and int(ch.z_index) == 210:
				chips += 1
	_trace.append({
		"ms": Time.get_ticks_msec() - _t0,
		"phase": int(_combat.get("phase")),
		"cap": String(_combat.get("_phase_caption")),
		"fx": (fr.position.x + fr.size.x * 0.5) if fr.size.x > 0.0 else -1.0,
		"fw": fr.size.x,
		"fs": fs,
		"info": String(info.text) if (info != null and is_instance_valid(info)) else "",
		"p": (_combat.call("_all_player_creatures") as Array).size(),
		"e": (_combat.call("_all_enemy_creatures") as Array).size(),
		"down": int(_combat.call("_downed_count")),
		"fl": floats, "ch": chips,
		"php": int(_combat.get("player_hp")), "ehp": int(_combat.get("enemy_hp")),
	})


## Print one row whenever anything a player could SEE changes, plus the peak
## concurrent-actor count per segment. A per-frame dump would be 600 lines of
## noise; the transitions are the pacing.
func _dump_trace(tag: String) -> void:
	print("[trace:%s] %d frames over %d ms" % [
		tag, _trace.size(), int(_trace[-1]["ms"]) if _trace.size() > 0 else 0])
	print("[trace:%s]   ms | cap                | lane-focus (cx/str) | P/E | dn | fl+ch | HP" % tag)
	var prev := {}
	var last_ms := 0
	var peak_fl := 0
	var peak_ch := 0
	for r in _trace:
		peak_fl = maxi(peak_fl, int(r["fl"]))
		peak_ch = maxi(peak_ch, int(r["ch"]))
		var key := "%s|%d|%s|%d|%d|%d|%d|%d" % [
			r["cap"], int(round(float(r["fx"]) / 10.0)), r["info"],
			r["p"], r["e"], r["down"], r["php"], r["ehp"]]
		var pkey := String(prev.get("_k", "<none>"))
		if key == pkey:
			continue
		var gap: int = int(r["ms"]) - last_ms
		last_ms = int(r["ms"])
		print("[trace:%s] %5d (+%4d) | %-18s | cx=%6.1f w=%5.1f s=%.2f | %d/%d | %d | %d+%d | %d/%d  %s" % [
			tag, int(r["ms"]), gap, r["cap"], float(r["fx"]), float(r["fw"]),
			float(r["fs"]), int(r["p"]), int(r["e"]), int(r["down"]),
			int(r["fl"]), int(r["ch"]), int(r["php"]), int(r["ehp"]),
			('info="%s"' % r["info"]) if String(r["info"]) != "" else ""])
		prev = {"_k": key}
	print("[trace:%s] peak concurrent floating numbers=%d  callout chips=%d  (MOT limit is ~4)" % [
		tag, peak_fl, peak_ch])
	# Lane-focus dwell census — the direct answer to "does each column get a
	# readable rest". One entry per contiguous run of the same focus rect.
	print("[trace:%s] --- lane focus dwell census ---" % tag)
	var run_start := -1
	var run_cx := -999.0
	var run_down_start := 0
	for r in _trace:
		var cx := float(r["fx"])
		if absf(cx - run_cx) > 2.0:
			if run_start >= 0 and run_cx >= 0.0:
				print("[trace:%s]   focus cx=%6.1f  held %4d ms  (corpses %d -> %d)" % [
					tag, run_cx, int(r["ms"]) - run_start, run_down_start, int(r["down"])])
			run_start = int(r["ms"])
			run_cx = cx
			run_down_start = int(r["down"])
	if run_start >= 0 and run_cx >= 0.0 and _trace.size() > 0:
		print("[trace:%s]   focus cx=%6.1f  held %4d ms  (corpses %d -> %d)" % [
			tag, run_cx, int(_trace[-1]["ms"]) - run_start, run_down_start,
			int(_trace[-1]["down"])])
	# Caption census — did each rank caption land BEFORE its rank resolved?
	print("[trace:%s] --- caption census ---" % tag)
	var cap := "<none>"
	for r in _trace:
		if String(r["cap"]) != cap:
			cap = String(r["cap"])
			print("[trace:%s]   %5d ms  cap='%s'  (corpses down=%d, P/E=%d/%d)" % [
				tag, int(r["ms"]), cap, int(r["down"]), int(r["p"]), int(r["e"])])
	print("[trace:%s] --- info line census ---" % tag)
	var inf := "<none>"
	for r in _trace:
		if String(r["info"]) != inf:
			inf = String(r["info"])
			if inf != "":
				print("[trace:%s]   %5d ms  info='%s'  (cap='%s')" % [
					tag, int(r["ms"]), inf, String(r["cap"])])


# ── capture ────────────────────────────────────────────────────────────────

func _capture_until_round(target_round: int, tail: float) -> void:
	var t_start := Time.get_ticks_msec()
	var tail_deadline := -1
	while true:
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - t_start
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s/f%03d_%05dms.jpg" % [SHOT_DIR, _shot_i, ms], 0.93)
		_shot_i += 1
		var rn: int = int(_combat.get("round_number"))
		var ph = _combat.get("phase")
		if tail_deadline < 0 and rn >= target_round and ph == _combat.Phase.PLAYER_TURN:
			tail_deadline = ms + int(tail * 1000.0)
		if tail_deadline >= 0 and ms >= tail_deadline:
			break
		if ms > 40000:
			_problems.append("capture ran 40 s without reaching round %d" % target_round)
			break
		await get_tree().create_timer(SHOT_CADENCE).timeout


## Rebuild the forecast with the player's own line suppressed, shoot it, restore.
## This is the A/B the doc's §11 #5 asks for by implication: it says the dial, if
## the both-lines read is cluttered, is "narrow to decisive lanes, NOT revert to
## enemy-only" — so the enemy-only frame is the thing that has to be argued
## against, and it has to exist to be argued against.
func _shoot_enemy_only_forecast() -> void:
	var both: int = (_combat.get("_lane_forecast_nodes") as Array).size()
	# Rebuild the layer through the REAL primitives (_clear_lane_forecast /
	# _predict_lane_strike / _add_lane_forecast) with only the enemy loop run.
	# A geometry heuristic ("hide anything in the top half") was the first draft
	# and it is wrong: a Line2D carries its geometry in `points`, so its own
	# `position` is (0,0) and every arrow would have been classed as friendly.
	_combat.call("_clear_lane_forecast")
	var enemy_reads := 0
	for row in [0, 1]:
		var arr = _combat.call("_row_array", true, row)
		for lane in range(4):
			var a = arr[lane]
			if a == null or not is_instance_valid(a):
				continue
			if not bool(_combat.call("_forecast_attacker_can_strike", a)):
				continue
			var rd: Dictionary = _combat.call("_predict_lane_strike", a)
			if rd.is_empty():
				continue
			_combat.call("_add_lane_forecast", a, rd)
			enemy_reads += 1
	await get_tree().process_frame
	var only: int = (_combat.get("_lane_forecast_nodes") as Array).size()
	print("[clash] forecast A/B — both lines: %d nodes | enemy-only: %d nodes (%d enemy reads)" % [
		both, only, enemy_reads])
	await _shoot_png("plan_enemy_only")
	# Restore. The signature cache would otherwise decide nothing changed.
	_combat.set("_lane_forecast_signature", "")
	_combat.call("_refresh_lane_forecast")
	await get_tree().process_frame


func _count_forecast(cls) -> int:
	var n := 0
	for x in (_combat.get("_lane_forecast_nodes") as Array):
		if is_instance_valid(x) and is_instance_of(x, cls):
			n += 1
	return n


# ── plumbing ───────────────────────────────────────────────────────────────

func _await_state(min_round: int, want_enemies: bool, what: String) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[clash] ABORT — combat scene gone waiting for ", what)
			get_tree().quit(1)
			return false
		if int(_combat.get("round_number")) >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[clash] ABORT — timed out waiting for ", what)
	get_tree().quit(1)
	return false


func _report_board(tag: String) -> void:
	var lines: Array[String] = []
	for is_enemy in [true, false]:
		for row in [0, 1]:
			var arr = _combat.call("_row_array", is_enemy, row)
			var cells: Array[String] = []
			for lane in range(4):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					cells.append("  --  ")
					continue
				cells.append("%s %d/%d" % [String(c.card_data.get("name", "?")).substr(0, 9),
					int(c.effective_atk()), int(c.current_hp)])
			lines.append("%s %s: %s" % ["FOE" if is_enemy else "YOU",
				"front" if row == 0 else " back", " | ".join(cells)])
	print("[clash] [%s] round=%d  P_HP=%d E_HP=%d" % [tag,
		int(_combat.get("round_number")), int(_combat.get("player_hp")),
		int(_combat.get("enemy_hp"))])
	for l in lines:
		print("[clash]   ", l)


func _park_cursor() -> void:
	Input.warp_mouse(Vector2(4, 4))


func _shoot_png(tag: String) -> void:
	_park_cursor()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
	print("[clash] SAVED %s.png %s" % [tag, str(img.get_size())])
