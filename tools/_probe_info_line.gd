extends Node
## _probe_info_line.gd — WHO OWNS THE INFO LINE AT A ROUND TURN?
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_probe_info_line.tscn
##
## 2026-07-29: `_show_turn_banner()` was given `_clear_info_queue()` plus a hard
## `_info_label.text = ""`, so the post-clash ledger ("2 of ours down, 3 of
## theirs.") could no longer be buried under 70 px of "ROUND N".
##
## That fix is aimed at ONE writer, but the wipe is indiscriminate and it fires
## from the LAST line of `_start_round` — after every other round-open writer has
## already spoken. This probe measures what each writer actually gets:
##
##   * the ledger (posted during THE FALLEN, before the round turns) — the
##     message the fix exists to protect. Must survive its full INFO_LINE_HOLD.
##   * the encounter's start-of-round passive (`chieftain_rally` on `orc_warband`
##     speaks from round 2 on) — posted INSIDE `_start_round`, ~250 ms before the
##     banner. 26 `_show_info` calls across 20 of the 33 start-of-round passive
##     arms in EncounterEffects sit on this path.
##   * escalation's "The General presses the attack" (`_check_escalation`, also
##     inside `_start_round`).
##   * the four `_show_tutorial_tip` writers that fire from `_start_round`
##     (intents / pile / dismiss / banking). These bypass the queue entirely and
##     write `_info_label.text` directly for SEVEN SECONDS, so `_clear_info_queue`
##     does not touch them — only the raw `text = ""` does.
##
## Method: sample `_info_label.text` every rendered frame and reduce to spans.
## The banner's own arrival is timestamped by watching the HUD layer for the
## z_index-250 "ROUND N" Label, so a span that ends within a couple of frames of
## that node appearing is attributable to the wipe rather than to its own timer.
##
## House traps paid: current_scene assigned (else Card2D draws nothing), input
## off, cursor parked, and — because this probe is meant to be run against an
## ISOLATED user dir — the tutorial flags are explicitly NOT marked seen for the
## tutorial arm of the test, which is the point of run mode `tips`.

const STATE_TIMEOUT := 90.0
const POLL := 0.2
## `forge_heat` (The Forge That Eats, act 2) is the cleanest available witness for
## the start-of-round path: its arm speaks on EVERY round with no round gate and
## no RNG, needing only one live player creature — so a span that fails to appear
## is the wipe and not a passive that declined to fire. It is one of 20 of the 33
## start-of-round arms in EncounterEffects that call `_show_info`.
const ENC := "fire_giants_forge"
const ACT_IDX := 1

var _combat: Node = null
var _samples: Array[Dictionary] = []
var _watching := false
var _t0 := 0
var _banner_ms := -1
var _banners: Array[int] = []       # every "ROUND N" arrival, not just the first
var _banner_seen := {}
var _fail := 0
var _tips_mode := false


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[info] WATCHDOG"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a == "--tips":
			_tips_mode = true
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.clash_dwell_scale = 1.0
	UserSettings.end_turn_warning = false
	# In the default mode every tutorial is marked seen, so the spans measured are
	# real combat copy. In `--tips` mode they are deliberately left UNSEEN so the
	# four `_start_round` tutorial writers fire and can be timed against the wipe.
	if not _tips_mode:
		for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
				"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
				"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
				"mark_sacrifice_tutorial_seen"]:
			if UserSettings.has_method(m):
				UserSettings.call(m)

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = ACT_IDX
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

	print("[info] encounter=%s  passive=%s  INFO_LINE_HOLD=%s  mode=%s" % [
		ENC, String(_combat.get("_encounter_passive")),
		str(_combat.get_script().get_script_constant_map().get("INFO_LINE_HOLD")),
		"tips (fresh profile)" if _tips_mode else "combat copy only"])

	# Watch from BOOT, not from the clash. Four of the writers under test
	# (`_maybe_show_intents_tutorial` r1, `_maybe_show_pile_tutorial` r2,
	# `_maybe_show_dismiss_tutorial` r2, `_maybe_show_banking_tutorial`) fire from
	# inside `_start_round` on the OPENING rounds — starting the watch at the clash
	# would miss every one of them and make the wipe look narrower than it is.
	_start_watch()
	if not await _await_state(1, false):
		return
	_combat.call("_on_end_turn")                    # round 1 -> the muster round
	if not await _await_state(2, true):
		return
	await get_tree().create_timer(2.5).timeout

	# Give both lines something to kill so the post-clash LEDGER actually posts.
	_stage()
	await get_tree().create_timer(1.2).timeout

	print("")
	print("[info] ===== end turn -> round 3 =====")
	_combat.call("_on_end_turn")
	await _await_state(3, false)
	await get_tree().create_timer(3.0).timeout
	_stop_watch()
	_report()

	print("[info] %s" % ("ALL PASS" if _fail == 0 else "%d FINDING(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


## Three columns that kill both ways, so the ledger has a non-zero count on BOTH
## sides — the "the line holds" branch would be silent and prove nothing. Column 3
## is left ALIVE on both sides on purpose: `forge_heat` needs at least one live
## player creature at the top of the next round or the passive declines to speak,
## and a silent passive would be indistinguishable from a wiped one.
func _stage() -> void:
	for lane in range(4):
		var e = _cell(true, 0, lane)
		if e == null:
			_combat.call("_place_enemy_card", EncounterDB.make_card_data(
				{"name": "Warrior", "atk": 4, "hp": 3, "kw": []}), lane, 0, false)
			e = _cell(true, 0, lane)
		var p = _cell(false, 0, lane)
		if p == null:
			_combat.call("summon_token", 4, 3, lane, false, 0, {}, "Pikeman", [])
			p = _cell(false, 0, lane)
		if lane == 3:
			_force(e, 1, 40)      # the survivor pair — nothing dies in this column
			_force(p, 1, 40)
		else:
			_force(e, 4, 3)
			_force(p, 4, 3)
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


func _start_watch() -> void:
	_samples.clear()
	_banner_ms = -1
	_banner_seen.clear()
	_t0 = Time.get_ticks_msec()
	_watching = true
	set_process(true)


func _stop_watch() -> void:
	_watching = false
	set_process(false)


func _process(_dt: float) -> void:
	if not _watching or _combat == null or not is_instance_valid(_combat):
		return
	var lbl: Label = _combat.get("_info_label")
	var ms := Time.get_ticks_msec() - _t0
	# The banner is a bare Label at z_index 250 whose text begins "ROUND ". It is
	# spawned on the LAST line of _start_round, immediately after the wipe, so its
	# first frame is the wipe's timestamp to within one frame.
	var hud = _combat.get("_hud_layer")
	if hud != null and is_instance_valid(hud):
		for ch in hud.get_children():
			if ch is Label and int(ch.z_index) == 250 \
					and String(ch.text).begins_with("ROUND"):
				if not _banner_seen.has(ch.get_instance_id()):
					_banner_seen[ch.get_instance_id()] = true
					_banners.append(ms)
					if _banner_ms < 0:
						_banner_ms = ms
	_samples.append({
		"ms": ms,
		"t": String(lbl.text) if (lbl != null and is_instance_valid(lbl)) else "<null>",
		"q": (_combat.get("_info_queue") as Array).size(),
		"showing": bool(_combat.get("_info_showing")),
		"rn": int(_combat.get("round_number")),
		"cap": String(_combat.get("_phase_caption")),
	})


func _report() -> void:
	print("[info] 'ROUND N' banners rendered at: %s ms" % str(_banners))
	print("[info] --- info-label spans ---")
	print("[info]   start    end   dur | rn | text")
	var cur := ""
	var start := 0
	var start_rn := 0
	var spans: Array[Dictionary] = []
	for s in _samples:
		var t := String(s["t"])
		if t != cur:
			if cur != "":
				spans.append({"t": cur, "a": start, "b": int(s["ms"]),
					"rn": start_rn})
			cur = t
			start = int(s["ms"])
			start_rn = int(s["rn"])
	if cur != "" and _samples.size() > 0:
		spans.append({"t": cur, "a": start, "b": int(_samples[-1]["ms"]),
			"rn": start_rn})
	var hold_ms := int(2.0 * 1000.0)
	for sp in spans:
		var dur: int = int(sp["b"]) - int(sp["a"])
		var flag := ""
		# A span that ends within 2 frames of ANY banner appearing was ENDED by
		# the wipe, not by its own 2 s timer.
		var cut := false
		for b in _banners:
			if absi(int(sp["b"]) - b) <= 40:
				cut = true
				break
		# Tutorial tips bypass the queue and get a 7 s hold of their own, so they
		# are owed far more than INFO_LINE_HOLD; judge them against that.
		var owed: int = 7000 if String(sp["t"]).begins_with("TIP") \
			or String(sp["t"]).begins_with("READ THE BOARD") \
			or String(sp["t"]).begins_with("RIGHT-CLICK") \
			or String(sp["t"]).begins_with("BANK COMMAND") \
			or String(sp["t"]).begins_with("BOTH SIDES") else hold_ms
		if cut and dur < owed - 150:
			flag = "  <== CUT BY THE ROUND BANNER (owed %d ms, got %d)" % [
				owed, dur]
			_fail += 1
		elif dur < owed - 250 and String(sp["t"]).length() > 3:
			flag = "  <== short (%d ms < %d ms hold)" % [dur, hold_ms]
		print("[info] %7d %6d %5d | %2d | \"%s\"%s" % [
			int(sp["a"]), int(sp["b"]), dur, int(sp["rn"]),
			String(sp["t"]).substr(0, 62), flag])
	if _banner_ms < 0:
		print("[info] (no banner observed in the watched window)")
		return
	# What was still QUEUED (never shown at all) when the banner cleared?
	var q_at_banner := -1
	for s in _samples:
		if _banner_ms >= 0 and int(s["ms"]) >= _banner_ms - 20:
			q_at_banner = int(s["q"])
			break
	print("[info] info_queue depth just before the wipe: %d" % q_at_banner)
	if q_at_banner > 0:
		print("[info] FINDING — %d queued line(s) were DISCARDED unshown by _clear_info_queue()"
			% q_at_banner)
		_fail += 1
	if spans.is_empty():
		print("[info] FINDING — the info line never carried anything at all")
		_fail += 1


func _await_state(min_round: int, want_enemies: bool) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[info] ABORT — combat gone")
			get_tree().quit(1)
			return false
		if int(_combat.get("round_number")) >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[info] ABORT — timed out waiting for round ", min_round)
	get_tree().quit(1)
	return false
