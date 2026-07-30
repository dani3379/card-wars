extends Node
## _shot_battle_log.gd — verifies the three 2026-07-08 combat-readability
## features (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_battle_log.tscn
##
##   status   enemy tokens with mid-fight statuses granted (Shield / Frozen /
##            Stunned / granted Armored) — the live status rail must show them
##   log      after a real creature-vs-creature clash, the battle-log drawer
##            open with genuine illustrated lines
##   hover    a card-bearing log row hovered, floating the full baked card
##
## Outputs tools/screenshot/_battle_log_*.png
##
## ── WHY THIS HARNESS WAITS ON STATE, NOT ON A CLOCK ──────────────────────────
## It used to sleep 6 s after adding the combat scene and then hang statuses on
## `_all_enemy_creatures()`. That printed "enemy tokens on board: 0" and shot an
## EMPTY board: the frames proved nothing, and the harness reported success while
## rendering none of what it exists to check.
##
## The cause is TAKE THE FIELD (2026-07-27, Combat.gd `_run_opening_muster` and
## the block above `await _start_round()`): the hold no longer forms up before
## the player may act. `_opening_muster_pending` is left standing through round 1
## and consumed by `_enemy_place_creatures` inside `_post_combat_sequence`, so the
## enemy line arrives at the END of round 1. Combined with the muster delay
## (2026-07-21 — an arrival does not swing the round it lands), the first board
## with live enemy bodies on it that are also allowed to fight is ROUND 2.
##
## So: no sleeps for game state. `_await_state` polls `round_number` + `phase` +
## board occupancy, which is the gate that survives the next pacing change too.
## (Timed waits remain only for the ~frame-scale UI settles — the status-rail
## poll, the drawer's open tween — which are not game state.)

const STATE_TIMEOUT := 60.0
const POLL := 0.2
## The "ROUND N" banner (_show_turn_banner) pops, holds 0.55 s and fades over
## 0.38 s — ~1.2 s of 70px type across the middle of the board. Shooting the
## instant the phase flips buries the thing being photographed under it.
const SETTLE := 1.8

var _combat: Node = null
var _problems: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# A windowed harness sits in the real desktop session with the window
	# foregrounded, so stray keystrokes and clicks DO land on it. A previous run
	# shot all three frames with the FIELD CARD primer (Tab/?/slash in
	# Combat._input) and an "End Turn?" confirm covering the board. Both are shut
	# off at the source rather than papered over per shot.
	if UserSettings != null:
		UserSettings.end_turn_warning = false

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
	# Kills the glossary hotkeys without touching gameplay: the harness drives
	# every action by direct call, so Combat never needs raw input here.
	_combat.set_process_input(false)

	# ── Round 1: the player's turn opens against an EMPTY hold (see header) ──
	if not await _await_state(1, false, "round 1 player turn"):
		return
	_report_board("round 1 open")

	# Field two soldiers now so they are swept ready_to_swing at the top of round
	# 2 and the round-2 clash is a real creature-vs-creature trade.
	_combat.call("summon_token", 3, 4, 0, false, 0, {}, "Pikeman")
	_combat.call("summon_token", 2, 3, 1, false, 0, {}, "Bowman")
	await get_tree().create_timer(0.6).timeout

	# End round 1 — the clash resolves, then _post_combat_sequence consumes the
	# pending opening muster and the hold finally takes the field.
	_combat.call("_on_end_turn")
	if not await _await_state(2, true, "round 2 player turn with a live hold"):
		return
	_report_board("round 2 open")

	# ── Grant mid-fight statuses to the seated enemy line ──
	var enemies: Array = _combat.call("_all_enemy_creatures")
	print("enemy tokens on board: ", enemies.size())
	print("stunned icon loaded: ", GameTheme.get_keyword_icon("stunned") != null)
	print("frozen icon loaded: ", GameTheme.get_keyword_icon("frozen") != null)
	if enemies.is_empty():
		_problems.append("no enemy bodies to hang statuses on")
	# Lane order, then the OUTERMOST two bodies: the encounter-passive banner sits
	# across the top-centre of the arena and half-covers the rails of the middle
	# lanes. The outer lanes photograph clean.
	enemies.sort_custom(func(a, b): return int(a.current_lane) < int(b.current_lane))
	if enemies.size() >= 1:
		enemies[0].state.has_shield = true
		enemies[0].card_data.keywords.append("armored")   # granted keyword
	if enemies.size() >= 2:
		var far = enemies[enemies.size() - 1]
		far.state.is_frozen = true
		far.state.stunned = true                          # two statuses side by side
	# No update_stat_display on purpose — the _process poll must catch these.
	await get_tree().create_timer(0.6).timeout
	var railed := 0
	for e in enemies:
		var orbs: int = (e.get("_status_orbs") as Array).size()
		if orbs > 0:
			railed += 1
		print("  %s (lane %d) rail orbs: %d  sig: %s" % [
			String(e.card_data.get("name", "?")), int(e.current_lane), orbs,
			String(e.call("_status_signature"))])
	if railed < 2:
		_problems.append("fewer than two enemy bodies carry a live status rail (%d)" % railed)
	await get_tree().create_timer(SETTLE).timeout
	await _shoot("status")

	# ── Round 2's clash is the real one: both lines are ready to swing, so the
	# chronicle fills with strike / counter / death lines rather than arrivals. ──
	_combat.call("_on_end_turn")
	if not await _await_state(3, false, "round 3 player turn"):
		return
	_report_board("round 3 open")
	await get_tree().create_timer(SETTLE).timeout

	_combat.call("_toggle_battle_log")
	print("immediately post-toggle open: ", _combat.get("_battle_log_open"))
	# Robust: ensure the drawer is open for the shot regardless of timing.
	if not _combat.get("_battle_log_open"):
		_combat.call("_toggle_battle_log")
		print("re-toggled, now open: ", _combat.get("_battle_log_open"))
	await get_tree().create_timer(0.5).timeout
	var panel: Control = _combat.get("_battle_log_panel")
	var list: Control = _combat.get("_battle_log_list")
	print("log open: ", _combat.get("_battle_log_open"),
		"  panel visible: ", panel.visible if panel != null else "NULL",
		"  panel rect: ", panel.get_global_rect() if panel != null else "-",
		"  lines: ", list.get_child_count() if list != null else -1)
	# Count how many rows carry a thumbnail + a hover snapshot.
	var thumbs := 0
	var hoverable: Control = null
	if list != null:
		for r in list.get_children():
			if r.has_meta("log_card"):
				thumbs += 1
				# Prefer a card that actually HAS rules (keywords/triggers) so the
				# synthesised-text path is exercised, not a vanilla creature.
				var cd: Dictionary = r.get_meta("log_card")
				var has_rules: bool = (cd.get("keywords", []) as Array).size() > 0 \
					or cd.has("on_enter") or cd.has("on_death") or cd.has("adj_buff")
				if hoverable == null or (has_rules and not hoverable.get_meta("log_card").has("_rules_pick")):
					if has_rules:
						cd["_rules_pick"] = true
						r.set_meta("log_card", cd)
						hoverable = r
					elif hoverable == null:
						hoverable = r
	print("rows with card thumbnail/hover: ", thumbs)
	if list == null or list.get_child_count() < 5:
		_problems.append("battle log holds fewer than 5 rows")
	if thumbs < 2:
		_problems.append("fewer than 2 illustrated (card-bearing) log rows")
	if hoverable != null:
		print("hovering card: ", hoverable.get_meta("log_card").get("name", "?"),
			" kw: ", hoverable.get_meta("log_card").get("keywords", []))
	await _shoot("log")

	# ── Hover a card-bearing row: the full card preview must appear beside the
	# drawer (Hearthstone history hover). ──
	if hoverable == null:
		_problems.append("no card-bearing log row to hover")
	elif _combat.has_method("_on_log_row_hover"):
		_combat.call("_on_log_row_hover", hoverable, true)
		await get_tree().create_timer(0.4).timeout
		# The real desktop cursor is loose in this window; if it happens to sit
		# over the drawer its own mouse_exited can tear the preview down between
		# the call and the shot. Re-arm once rather than shoot an empty frame.
		if _combat.get("_log_preview_card") == null:
			print("  preview vanished before the shot — re-arming the hover")
			_combat.call("_on_log_row_hover", hoverable, true)
			await get_tree().create_timer(0.4).timeout
		var prev = _combat.get("_log_preview_card")
		print("hover preview spawned: ", prev != null,
			"  at: ", prev.global_position if prev != null else "-")
		if prev != null:
			print("  preview synth text: '", prev.call("_synthesized_rules_text"), "'")
			for rt in _find_richtext(prev):
				var t := String(rt.text).strip_edges()
				if t != "":
					print("  preview rendered label: '", t, "'")
		else:
			_problems.append("hover preview card never spawned")
		await _shoot("hover")

	# THE POINT OF THE 2026-07-29 REWRITE. This harness used to print
	# "enemy tokens on board: 0", shoot three frames of an empty arena and exit 0.
	# A shot harness that reports success while rendering nothing is worse than no
	# harness, so the things it exists to photograph are now asserted, and a
	# missing one is a loud non-zero exit.
	if _problems.is_empty():
		print("BATTLE_LOG_SHOTS_DONE  (all three frames carry live content)")
		get_tree().quit()
	else:
		for p in _problems:
			print("BATTLE_LOG_SHOTS FAIL: ", p)
		print("BATTLE_LOG_SHOTS_INCOMPLETE — the frames above do not prove what they claim")
		get_tree().quit(1)


## Poll until the fight really is at `min_round`, back in the player's hands, and
## (when `want_enemies`) actually has an enemy line standing. `phase` alone is not
## enough: _run_opening_muster and the clash both flip it, and a frame-count wait
## rides on whatever the pacing constants happen to be this week.
func _await_state(min_round: int, want_enemies: bool, what: String) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("HARNESS ABORT: combat scene gone while waiting for ", what)
			get_tree().quit(1)
			return false
		var rn: int = int(_combat.get("round_number"))
		var ready: bool = rn >= min_round \
			and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
			and (not want_enemies or (_combat.call("_all_enemy_creatures") as Array).size() > 0)
		if ready:
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("HARNESS ABORT: timed out waiting for ", what,
		"  (round=", _combat.get("round_number"), " phase=", _combat.get("phase"),
		" enemies=", (_combat.call("_all_enemy_creatures") as Array).size(), ")")
	get_tree().quit(1)
	return false


func _report_board(tag: String) -> void:
	print("[%s] round=%d  your bodies=%d  enemy bodies=%d" % [tag,
		int(_combat.get("round_number")),
		(_combat.call("_all_player_creatures") as Array).size(),
		(_combat.call("_all_enemy_creatures") as Array).size()])


func _find_richtext(n: Node) -> Array:
	var out: Array = []
	if n is RichTextLabel:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_richtext(c))
	return out


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_battle_log_%s.png" % tag)
	print("SAVED battle_log_", tag, " ", img.get_size())
