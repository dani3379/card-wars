extends Node
## _shot_creature_fx.gd — the creature-trigger FX grammar, photographed.
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_creature_fx.tscn
##
## `_probe_creature_fx` proves COVERAGE (every pool effect type acknowledged,
## keystones live). It cannot prove a beat LOOKS like anything — and in this
## layer the shot is the only thing that has ever caught a defect. Frames:
##
##   aimed        a battlecry tracer crossing the board in the tribe's colour,
##                impact landing on the opposing body
##   breath       damage_all_enemies caught mid-RADIATE (impacts pour out of
##                the creature, nearest first — not the spells' L→R sweep)
##   grace        buff_ctype_hp glints over the fortified tribe-mates
##   coin         gain_gold chinking at the creature
##   mirror       copy_opposing_keywords — the line flows FROM the reflected
##                enemy TO the copier
##   nova         an on-death wave radiating from the death anchor
##   hold         Warden-Sergeant's HOLD — steel wave down the full front row
##                (real _apply_start_round_passives path)
##   encore       Bloodmoon Alpha's howl — doubled russet ring at the Alpha
##                (real _maybe_beast_encore path)
##   coven        Coven Mother's incantation hop (real spell-payoff path)
##   reap         Gravepact's grave-light wisp corpse → Wight seat (real
##                _apply_ally_death_passives path)
##
## Outputs _shot_cfx_*.png at the project root.
##
## ── WHY THIS HARNESS WAITS ON STATE, NOT ON A CLOCK (2026-07-29) ─────────────
## It used to sleep 6 s and then read `_all_enemy_creatures()`. As of TAKE THE
## FIELD (2026-07-27) that reads ZERO and the harness aborted at
## "[cfx] FAIL — need >=2 enemy bodies": `_opening_muster_pending` is left
## standing through round 1 and consumed by `_enemy_place_creatures` inside
## `_post_combat_sequence`, so the enemy line arrives at the END of round 1.
## No sleep can be tuned to fix that — the bodies do not exist yet at any time
## during round 1. Poll `round_number` + `phase` + occupancy instead; that gate
## survives the next pacing change too. (Timed waits remain only for the
## frame-scale FX peaks each shot is aimed at — those ARE the subject.)

const STATE_TIMEOUT := 60.0
const POLL := 0.2

var _combat: Node = null


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[cfx] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# This machine's saved settings have Reduce Motion ON — force it off or the
	# harness photographs the degraded fallback (known trap).
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0
		UserSettings.particles = true
		# A windowed harness sits in the live desktop session with its window
		# foregrounded, so stray keystrokes really do reach Combat._input. Shut the
		# confirm dialog off at the source rather than papering over it per shot.
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
	# The harness drives every beat by direct call, so Combat never needs raw
	# input here — and with it off the glossary hotkeys cannot open a primer over
	# the frame being photographed.
	_combat.set_process_input(false)

	# Round 1 opens against an EMPTY hold (see header). End it so the opening
	# muster resolves, then wait for round 2, when the enemy line is really there.
	if not await _await_state(1, false, "round 1 player turn"):
		return
	_combat.call("_on_end_turn")
	if not await _await_state(2, true, "round 2 player turn with a live hold"):
		return

	var enemies: Array = _combat.call("_all_enemy_creatures")
	print("[cfx] enemy bodies on board: %d  (round %d)" % [
		enemies.size(), int(_combat.get("round_number"))])
	if enemies.size() < 2:
		print("[cfx] FAIL — need >=2 enemy bodies")
		get_tree().quit(1)
		return

	# Muster a player line to fire triggers from. Tribes stamped per token so
	# every tribe colour photographs.
	for lane in range(4):
		_combat.call("summon_token", 2, 3, lane, false, 0)
	_combat.call("summon_token", 2, 3, 1, false, 1)
	await get_tree().process_frame
	var front: Array = []
	for lane in range(4):
		front.append(_combat.call("_row_array", false, 0)[lane])
	var backer = _combat.call("_row_array", false, 1)[1]
	if front.any(func(c): return c == null) or backer == null:
		print("[cfx] FAIL — token muster incomplete")
		get_tree().quit(1)
		return
	front[0].card_data["ctype"] = "beast"
	front[1].card_data["ctype"] = "bastion"
	front[2].card_data["ctype"] = "warlock"
	front[3].card_data["ctype"] = "stray"
	backer.card_data["ctype"] = "bastion"
	await get_tree().create_timer(0.6).timeout

	# ── 0. CONTROL — a known-photographed spell FX through the same layer ─
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("inferno"), null)
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_cfx_control_spell.png", "CONTROL — Inferno (spell grammar)")
	await get_tree().create_timer(1.2).timeout

	# ── 1. Aimed battlecry — russet tracer + landed impact ──────────────
	_combat.call("_play_trigger_fx", {"type": "damage_opposing", "value": 2},
		front[0], 0, false, "enter")
	await get_tree().create_timer(0.05).timeout
	await _shoot("res://_shot_cfx_aimed_flight.png", "aimed — tracer in flight (beast russet)")
	await get_tree().create_timer(0.07).timeout
	await _shoot("res://_shot_cfx_aimed_land.png", "aimed — impact on the opposing body")
	await get_tree().create_timer(1.0).timeout

	# ── 2. The breath — radiates out of the body, nearest first ─────────
	_combat.call("_play_trigger_fx", {"type": "damage_all_enemies", "value": 1},
		front[0], 0, false, "enter")
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_cfx_breath.png", "breath — mid-radiate over the enemy line")
	await get_tree().create_timer(1.0).timeout

	# ── 3. Grace — the fortified tribe glints ───────────────────────────
	_combat.call("_play_trigger_fx",
		{"type": "buff_ctype_hp", "value": 2, "ctype": "bastion"},
		front[1], 1, false, "enter")
	await get_tree().create_timer(0.10).timeout
	await _shoot("res://_shot_cfx_grace.png", "grace — bronze glints over the bastions")
	await get_tree().create_timer(1.0).timeout

	# ── 4. Coin — the purse chinks ──────────────────────────────────────
	_combat.call("_play_trigger_fx", {"type": "gain_gold", "value": 15},
		front[3], 3, false, "enter")
	await get_tree().create_timer(0.14).timeout
	await _shoot("res://_shot_cfx_coin.png", "coin — gold chink at the stray")
	await get_tree().create_timer(1.0).timeout

	# ── 5. Mirror — the reflection flows INTO the copier ────────────────
	_combat.call("_play_trigger_fx", {"type": "copy_opposing_keywords"},
		front[2], 2, false, "enter")
	await get_tree().create_timer(0.05).timeout
	await _shoot("res://_shot_cfx_mirror.png", "mirror — line flows from the enemy to the copier")
	await get_tree().create_timer(1.0).timeout

	# ── 6. Death nova — radiates from where the body fell ───────────────
	var anchor: Vector2 = enemies[0].get_global_rect().get_center()
	_combat.call("_play_trigger_fx", {"type": "damage_all_enemies", "value": 1},
		enemies[0], enemies[0].current_lane, true, "death", anchor)
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_cfx_nova.png", "nova — on-death wave from the anchor")
	await get_tree().create_timer(1.0).timeout

	# ══ Keystone signatures, REAL paths ══════════════════════════════════
	# ── 7. Warden-Sergeant's HOLD — full front row, steel wave ──────────
	for c in front:
		c.card_data["ctype"] = "soldier"
	front[1].card_data["passive"] = "warden_line"
	_combat.call("_apply_start_round_passives", false)
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_cfx_hold.png", "HOLD — steel wave down the wall")
	await get_tree().create_timer(1.0).timeout
	front[1].card_data["passive"] = ""

	# ── 8. Bloodmoon Alpha's ENCORE — the howl ──────────────────────────
	front[0].card_data["passive"] = "beast_encore"
	front[3].card_data["ctype"] = "beast"
	front[3].card_data["on_enter"] = {"type": "damage_opposing", "value": 1}
	_combat.call("_maybe_beast_encore", front[3], false)
	await get_tree().create_timer(0.10).timeout
	await _shoot("res://_shot_cfx_encore.png", "ENCORE — doubled russet howl at the Alpha")
	await get_tree().create_timer(0.28).timeout
	await _shoot("res://_shot_cfx_encore_echo.png", "ENCORE — the delayed echo beat")
	await get_tree().create_timer(1.0).timeout
	front[0].card_data["passive"] = ""

	# ── 9. Coven Mother — the incantation hops sister to sister ─────────
	front[2].card_data["passive"] = "coven_spell"
	front[2].card_data["ctype"] = "warlock"
	front[1].card_data["ctype"] = "warlock"
	backer.card_data["ctype"] = "warlock"
	_combat.call("_record_spell_cast_board_payoffs")
	await get_tree().create_timer(0.10).timeout
	await _shoot("res://_shot_cfx_coven.png", "coven — violet hop across the warlocks")
	await get_tree().create_timer(1.0).timeout
	front[2].card_data["passive"] = ""

	# ── 10. Gravepact's REAP — wisp from the corpse to the Wight seat ───
	front[0].card_data["passive"] = "reap_on_ally_death"
	front[0].card_data["ctype"] = "dead"
	# The reap requires a non-token casualty; the harness fakes one.
	front[3].is_token = false
	_combat.call("_apply_ally_death_passives", false, front[3])
	await get_tree().create_timer(0.10).timeout
	await _shoot("res://_shot_cfx_reap.png", "reap — grave-light wisp corpse → Wight seat")
	await get_tree().create_timer(0.8).timeout

	print("[cfx] DONE")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)


## Poll until the fight really is at `min_round`, back in the player's hands, and
## (when `want_enemies`) actually has an enemy line standing. `phase` alone is not
## enough — _run_opening_muster and the clash both flip it — and a frame-count
## wait rides on whatever the pacing constants happen to be this week.
func _await_state(min_round: int, want_enemies: bool, what: String) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[cfx] ABORT — combat scene gone while waiting for ", what)
			get_tree().quit(1)
			return false
		var rn: int = int(_combat.get("round_number"))
		if rn >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[cfx] ABORT — timed out waiting for ", what,
		"  (round=", _combat.get("round_number"), " phase=", _combat.get("phase"),
		" enemies=", (_combat.call("_all_enemy_creatures") as Array).size(), ")")
	get_tree().quit(1)
	return false


func _shoot(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[cfx] wrote %s — %s" % [path.get_file(), label])
