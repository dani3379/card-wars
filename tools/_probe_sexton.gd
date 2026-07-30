extends SceneTree
## The Sexton — live-fire regression probe (2026-07-24).
##
## Proves the "arming trick": playing The Sexton (Dead RARE) sets a
## Combat-scoped flag (_grave_armed[side]) rather than a per-creature flag, so
## the Second Wave engine keeps firing even after the Sexton itself has died.
## Drives the REAL res://scenes/combat.tscn headless and exercises the death
## path directly (take_damage(999) → try_die → _on_card_destroyed →
## _on_friendly_death → _apply_ally_death_passives) so every check is a true
## end-to-end fire, not a unit stub.
##
## Checks:
##   1. CardDB the_sexton fields (ctype dead / on_enter arm_grave / rare).
##   2. Sexton on-enter arms _grave_armed[0] on the PLAYER side.
##   3. 3 OTHER non-token friendly deaths → three 2/2 Wights in the back row,
##      soul counter reset to 0.
##   4. CRITICAL: kill the Sexton, then kill 3 more → a NEW wave still rises
##      (the engine survives the Sexton's death — the whole doctrine).
##   5. A token death does NOT bank a soul.
##   6. Floor path: back row full → no new token, a friendly Dead gains +1/+1.
##
## Gotchas honoured (from project memory / the relic-slate template):
##   - Drive the real combat scene; poll for PLAYER_TURN before touching state.
##   - defer_deaths is a Card2D static, false in PLAYER_TURN, so take_damage(999)
##     resolves the death SYNCHRONOUSLY (destroyed.emit at the top of _die).
##   - take_damage(999) does NOT end the fight (victory gates on enemy face HP),
##     so we can freely kill creatures to test death triggers.
##   - Real (non-token) bodies are required for the soul checks: summon_token
##     stamps is_token=true, which the soul gate excludes — so we place real
##     Card2D creatures the way _place_enemy_card does, but on the player side.
##   - Headless auto-resolves modals, so nothing stalls.
##
## Run:
##   Godot_v4.6.2-stable_win64_console.exe --headless --path "D:\Godot" \
##       --script res://tools/_probe_sexton.gd

var combat: Node
var CDB: Node
var KE: Node   # the KeywordEffects autoload (Node) — set in _run. Never load()
               # the .gd here: recompiling it in the tool context (no CardDB
               # global) corrupts the shared script the autoload also uses.
var _started := false
var _done := false
var _pass := 0
var _fail := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[sexton] PASS %s" % label)
	else:
		_fail += 1
		print("[sexton] FAIL %s   %s" % [label, detail])


# ── helpers ────────────────────────────────────────────────────────────────

func _mk(id: String, atk: int, hp: int, ctype: String = "soldier") -> Dictionary:
	return {"id": id, "name": id, "type": "creature", "ctype": ctype,
		"cost": 1, "atk": atk, "hp": hp, "keywords": [], "rarity": "common",
		"desc": ""}


## Places a REAL (non-token) friendly creature on the player board, registered
## in the field array + slot and wired to the death signals — mirrors
## _place_enemy_card but for the player side. Returns the Card2D.
func _place_friendly(data: Dictionary, lane: int, row: int) -> Control:
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", "probe"))
	card.is_opponent = false
	card.is_token = false
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data
	card.deck_uid = -1
	card.current_lane = lane
	card.current_row = row
	combat._row_array(false, row)[lane] = card
	var slot = combat._slot_array(false, row)[lane]
	combat._slot_set_card(slot, card)   # add_child → _ready sets current_hp/atk from data
	card.current_atk = int(data.get("atk", 1))
	card.current_hp = int(data.get("hp", 1))
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card


## Places a real Sexton and fires its on-enter (arm_grave) exactly the way the
## place/play path does via KeywordEffects.dispatch_on_enter.
func _place_sexton(lane: int) -> Control:
	var data: Dictionary = CDB.get_card_data("the_sexton").duplicate(true)
	var card := _place_friendly(data, lane, combat.ROW_FRONT)
	KE.dispatch_on_enter(card, lane, false, combat)
	return card


func _player_back_wights() -> Array:
	var out: Array = []
	for c in combat._player_back:
		if c != null and is_instance_valid(c):
			out.append(c)
	return out


func _clear_board() -> void:
	# Disarm first so tearing down real bodies doesn't bank stray souls.
	combat._grave_armed[0] = 0
	combat._grave_armed[1] = 0
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			c.take_damage(999)
	combat._cleanup_dead()
	await create_timer(0.05).timeout
	combat._grave_souls[0] = 0
	combat._grave_souls[1] = 0


func _run() -> void:
	print("[sexton] start")
	var RS = root.get_node_or_null("RunState")
	var US = root.get_node_or_null("UserSettings")
	CDB = root.get_node_or_null("CardDB")
	KE = root.get_node_or_null("KeywordEffects")
	if RS == null or CDB == null or KE == null:
		print("[sexton] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	var SS = root.get_node_or_null("SkirmishState")
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	# ── 1. Catalog integrity ────────────────────────────────────────────────
	var sx: Dictionary = CDB.get_card_data("the_sexton")
	var on_enter: Dictionary = sx.get("on_enter", {})
	_ck("CardDB the_sexton exists", not sx.is_empty())
	_ck("the_sexton is a rare Dead creature",
		String(sx.get("type", "")) == "creature"
		and String(sx.get("ctype", "")) == "dead"
		and String(sx.get("rarity", "")) == "rare",
		"type=%s ctype=%s rarity=%s" % [sx.get("type", "?"), sx.get("ctype", "?"), sx.get("rarity", "?")])
	_ck("the_sexton on_enter is arm_grave + has on_enter keyword",
		String(on_enter.get("type", "")) == "arm_grave"
		and sx.get("keywords", []).has("on_enter"),
		"on_enter=%s keywords=%s" % [on_enter, sx.get("keywords", [])])

	# ── Boot the real combat scene ──────────────────────────────────────────
	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	var ok := false
	for _i in 60:
		await create_timer(0.1).timeout
		if not is_instance_valid(combat):
			break
		if combat.phase == combat.Phase.PLAYER_TURN:
			ok = true
			break
	if not ok:
		print("[sexton] FATAL: never reached PLAYER_TURN"); _finish(1); return
	# Let the intro settle so defer_deaths is down and the board is live.
	await create_timer(0.3).timeout

	# ── 2. Sexton on-enter arms the grave (player side = index 0) ───────────
	_ck("grave starts disarmed", int(combat._grave_armed[0]) == 0,
		"armed=%s" % str(combat._grave_armed))
	var sexton := _place_sexton(0)   # player front lane 0
	_ck("Sexton on-enter arms _grave_armed[0] >= 1",
		int(combat._grave_armed[0]) >= 1,
		"armed=%s (souls=%s)" % [str(combat._grave_armed), str(combat._grave_souls)])

	# ── 3. Three OTHER non-token deaths raise three 2/2 Wights ──────────────
	combat._grave_souls[0] = 0
	var v1 := _place_friendly(_mk("probe_v1", 1, 5), 1, combat.ROW_FRONT)
	var v2 := _place_friendly(_mk("probe_v2", 1, 5), 2, combat.ROW_FRONT)
	var v3 := _place_friendly(_mk("probe_v3", 1, 5), 3, combat.ROW_FRONT)
	v1.take_damage(999)   # soul 1
	v2.take_damage(999)   # soul 2
	v3.take_damage(999)   # soul 3 → WAVE, reset to 0
	var wave := _player_back_wights()
	var wave_ok := wave.size() == 3
	var stats_ok := true
	for w in wave:
		if w.current_atk != 2 or w.current_hp != 2 \
				or String(w.card_data.get("ctype", "")) != "dead" or not w.is_token:
			stats_ok = false
	_ck("3rd friendly death raises exactly three back-row Wights",
		wave_ok, "back-row bodies=%d" % wave.size())
	_ck("the risen Wights are 2/2 Dead tokens",
		wave_ok and stats_ok)
	_ck("soul counter reset to 0 after the wave",
		int(combat._grave_souls[0]) == 0, "souls=%s" % str(combat._grave_souls))

	# ── 4. THE DOCTRINE: kill the Sexton, engine keeps rising waves ─────────
	await _clear_board()
	var sexton2 := _place_sexton(0)   # re-arm with a fresh Sexton
	var w1 := _place_friendly(_mk("probe_w1", 1, 5), 1, combat.ROW_FRONT)
	var w2 := _place_friendly(_mk("probe_w2", 1, 5), 2, combat.ROW_FRONT)
	var w3 := _place_friendly(_mk("probe_w3", 1, 5), 3, combat.ROW_FRONT)
	sexton2.take_damage(999)   # the Sexton itself dies — soul 1
	var armed_after_death := int(combat._grave_armed[0]) >= 1
	var sexton_gone := combat._player_field[0] == null
	_ck("grave stays armed after the Sexton dies",
		armed_after_death and sexton_gone,
		"armed=%s sexton_slot=%s" % [str(combat._grave_armed), str(combat._player_field[0])])
	w1.take_damage(999)   # soul 2
	w2.take_damage(999)   # soul 3 → NEW WAVE despite the Sexton being dead
	w3.take_damage(999)   # soul 1
	var wave2 := _player_back_wights()
	_ck("a NEW wave rises after the Sexton's death (the doctrine)",
		wave2.size() == 3 and int(combat._grave_armed[0]) >= 1,
		"back-row bodies=%d armed=%s" % [wave2.size(), str(combat._grave_armed)])

	# ── 5. Token deaths do NOT bank souls ───────────────────────────────────
	await _clear_board()
	combat._grave_armed[0] = 1
	combat._grave_souls[0] = 0
	combat.summon_token(2, 2, 0, false, combat.ROW_FRONT, {}, "Wight")   # a token
	var tok = combat._player_field[0]
	var souls_before := int(combat._grave_souls[0])
	if tok != null and is_instance_valid(tok):
		tok.take_damage(999)
	_ck("a token death banks no soul",
		int(combat._grave_souls[0]) == souls_before and souls_before == 0,
		"souls %d -> %d" % [souls_before, int(combat._grave_souls[0])])

	# ── 6. Floor path: back row full → no token, a Dead gains +1/+1 ─────────
	await _clear_board()
	combat._grave_armed[0] = 1
	combat._grave_souls[0] = 0
	for lane in range(4):
		combat.summon_token(2, 2, lane, false, combat.ROW_BACK, {}, "Wight")
	var observer := _place_friendly(_mk("probe_dead", 2, 2, "dead"), 0, combat.ROW_FRONT)
	var count_before: int = combat._all_player_creatures().size()
	var atk_before := int(observer.current_atk)
	var hp_before := int(observer.current_hp)
	combat._second_wave_rise(false)   # back row full → floor reinforcement
	var count_after: int = combat._all_player_creatures().size()
	_ck("full back row → no new token summoned",
		count_after == count_before,
		"count %d -> %d" % [count_before, count_after])
	_ck("full back row → a friendly Dead gains +1/+1",
		int(observer.current_atk) == atk_before + 1
		and int(observer.current_hp) == hp_before + 1,
		"%d/%d -> %d/%d" % [atk_before, hp_before, int(observer.current_atk), int(observer.current_hp)])

	print("[sexton] done: %d passed, %d failed" % [_pass, _fail])
	_finish(0 if _fail == 0 else 1)
