extends SceneTree
## Focused contract probe for Combat's battlefield-creature hover forecast.
## Boots the real combat scene, seats deterministic cards, and exercises the
## public shape returned by `_predict_lane_strike` without resolving a clash.
##
## Run:
## Godot_console.exe --headless --path "D:\Godot" --log-file \
##   "D:\Godot\_codex_probe_combat_telegraph.log" \
##   --script res://tools/_probe_combat_telegraph.gd

const TURN_WAIT_TICKS := 60
const TICK := 0.1

var RS: Node
var CDB: Node
var SS: Node
var US: Node
var combat: Node
var _started := false
var _done := false
var _passed := 0
var _failed: Array[String] = []
var _next_probe_id := 1


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _run() -> void:
	print("[combat-telegraph] start")
	RS = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	US = root.get_node_or_null("UserSettings")
	if RS == null or CDB == null:
		print("[combat-telegraph] FATAL: required autoloads missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
		US.combat_telegraph = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	var net_match := root.get_node_or_null("NetMatch")
	if net_match != null and net_match.has_method("leave"):
		net_match.leave()

	RS.start_new_run("raider", 0, 731337)
	# No starting relic should make a synthetic attack stronger or rescue a body.
	RS.relics.clear()
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[combat-telegraph] FATAL: never reached PLAYER_TURN")
		_finish(1)
		return

	await _test_normal_targeting()
	await _test_mitigation_and_survival()
	await _test_attack_modifiers()
	await _test_disabled_and_intents()
	await _test_sniper_and_hydra()
	await _test_interpose_and_wall()
	await _test_poison_and_recoil()
	await _test_piercing_cleave_and_guardian()
	await _test_zero_attack_edges()
	await _test_rescue_wording()
	await _test_heal_projection_and_sniper_order()
	await _test_repeat_notices()
	await _test_pavise_chain_suppression()
	await _test_death_followup_wording()

	print("[combat-telegraph] ============ SUMMARY ============")
	print("[combat-telegraph] passed : %d" % _passed)
	print("[combat-telegraph] FAILED : %d %s" % [_failed.size(), str(_failed)])
	print("[combat-telegraph] DONE")
	_finish(0 if _failed.is_empty() else 2)


func _test_normal_targeting() -> void:
	print("[combat-telegraph] -- normal front / back / face")
	await _reset_board()
	var attacker = _seat_plain(false, 1, 3, 5)
	var front = _seat_plain(true, 1, 0, 5, [], combat.ROW_FRONT)
	_seat_plain(true, 1, 0, 7, [], combat.ROW_BACK)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("front row has target priority",
		read.get("target") == front and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 2, str(read))

	await _reset_board()
	attacker = _seat_plain(false, 2, 3, 5)
	var back = _seat_plain(true, 2, 0, 4, [], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	_check("exposed back row becomes the target",
		read.get("target") == back and int(read.get("target_row", -1)) == combat.ROW_BACK \
		and int(read.get("hp_after", -1)) == 1, str(read))

	await _reset_board()
	combat.enemy_hp = 20
	attacker = _seat_plain(false, 3, 3, 5)
	read = combat._predict_lane_strike(attacker)
	_check("empty column forecasts enemy face damage",
		bool(read.get("face", false)) and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 17 \
		and String(read.get("text", "")).contains("FOE HP -3"), str(read))


func _test_mitigation_and_survival() -> void:
	print("[combat-telegraph] -- Shield / Armored / Last Stand")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 4, 5)
	var target = _seat_plain(true, 0, 0, 6, ["shield"])
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Shield forecasts a break with no HP loss",
		read.get("target") == target and bool(read.get("shield_break", false)) \
		and int(read.get("damage", -1)) == 0 and int(read.get("hp_after", -1)) == 6 \
		and String(read.get("text", "")) == "SHIELD BREAKS", str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 4, 5)
	target = _seat_plain(true, 0, 0, 6, ["armored"])
	read = combat._predict_lane_strike(attacker)
	_check("Armored removes one damage",
		read.get("target") == target and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 3, str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 4, 5)
	target = _seat_plain(true, 0, 0, 3, ["last_stand"])
	read = combat._predict_lane_strike(attacker)
	_check("unused Last Stand forecasts survival at 1 HP",
		read.get("target") == target and bool(read.get("last_stand", false)) \
		and not bool(read.get("lethal", true)) and int(read.get("hp_after", -1)) == 1 \
		and String(read.get("text", "")).begins_with("LAST STAND"), str(read))


func _test_attack_modifiers() -> void:
	print("[combat-telegraph] -- Marked / Royal Guard / Archlich")
	await _reset_board()
	var attacker = _seat_plain(false, 1, 2, 5)
	var target = _seat_plain(true, 1, 0, 8)
	target.set_meta("marked", true)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Marked adds two damage",
		int(read.get("damage", -1)) == 4 and int(read.get("hp_after", -1)) == 4,
		str(read))

	await _reset_board()
	attacker = _seat_plain(false, 1, 3, 5)
	target = _seat_plain(true, 1, 0, 6)
	_seat_plain(true, 0, 1, 5, [], combat.ROW_FRONT, {"passive": "royal_guard"})
	read = combat._predict_lane_strike(attacker)
	_check("adjacent Royal Guard removes one damage",
		read.get("target") == target and int(read.get("damage", -1)) == 2 \
		and int(read.get("hp_after", -1)) == 4, str(read))

	await _reset_board()
	combat._encounter_passive = "archlich_immortal"
	attacker = _seat_plain(false, 2, 5, 5)
	target = _seat_plain(true, 2, 0, 3)
	read = combat._predict_lane_strike(attacker)
	_check("Archlich creature-attack floor forecasts 1 HP",
		read.get("target") == target and int(read.get("damage", -1)) == 2 \
		and int(read.get("hp_after", -1)) == 1 and not bool(read.get("lethal", true)),
		str(read))


func _test_disabled_and_intents() -> void:
	print("[combat-telegraph] -- Stunned / CHARGE / ENRAGE / HEAL")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 3, 5)
	_seat_plain(true, 0, 0, 6)
	attacker.state.stunned = true
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Stunned attacker has no forecast", read.is_empty(), str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 2, 5)
	_seat_plain(false, 0, 0, 8)
	attacker.set_meta("current_intent", "CHARGE")
	read = combat._predict_lane_strike(attacker)
	_check("CHARGE includes its pending +1 ATK",
		int(read.get("damage", -1)) == 3 and int(read.get("hp_after", -1)) == 5,
		str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 2, 5)
	_seat_plain(false, 0, 0, 8)
	attacker.set_meta("current_intent", "ENRAGE")
	read = combat._predict_lane_strike(attacker)
	_check("ENRAGE includes its pending +2 ATK",
		int(read.get("damage", -1)) == 4 and int(read.get("hp_after", -1)) == 4,
		str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 2, 5)
	_seat_plain(false, 0, 0, 8)
	attacker.set_meta("current_intent", "HEAL")
	read = combat._predict_lane_strike(attacker)
	_check("HEAL intent spends the attack and has no forecast", read.is_empty(), str(read))


func _test_sniper_and_hydra() -> void:
	print("[combat-telegraph] -- Sniper / Hydra summary")
	await _reset_board()
	var sniper = _seat_plain(false, 0, 2, 4, ["sniper"])
	_seat_plain(true, 0, 0, 5)
	var weakest = _seat_plain(true, 3, 0, 1)
	var read: Dictionary = combat._predict_lane_strike(sniper)
	_check("Sniper forecasts the lowest-HP creature across lanes",
		read.get("target") == weakest and bool(read.get("lethal", false)) \
		and String(read.get("text", "")).contains("CHAINS ON KILL"), str(read))

	await _reset_board()
	var hydra = _seat_id("hydra", false, 0)
	_seat_plain(true, 0, 0, 2)
	_seat_plain(true, 1, 0, 7)
	_seat_plain(true, 2, 0, 5, ["shield"])
	read = combat._predict_lane_strike(hydra)
	var hydra_text := String(read.get("text", ""))
	_check("Hydra summarizes every opposing creature",
		bool(read.get("summary", false)) and int(read.get("target_count", -1)) == 3 \
		and int(read.get("damage", -1)) == 6 \
		and hydra_text.contains("HITS ALL 3") and hydra_text.contains("1 DIE") \
		and hydra_text.contains("1 HURT") and hydra_text.contains("1 SHIELD"),
		str(read))


func _test_interpose_and_wall() -> void:
	print("[combat-telegraph] -- Interpose / face wall")
	await _reset_board()
	combat.player_hp = 20
	var attacker = _seat_plain(true, 0, 3, 5)
	var interposer = _seat_id("shieldmaiden", false, 3)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Shieldmaiden catches an otherwise open face strike",
		read.get("target") == interposer and not bool(read.get("face", true)) \
		and int(read.get("damage", -1)) == 3 \
		and String(read.get("text", "")).begins_with("INTERPOSES"), str(read))

	await _reset_board()
	combat.player_hp = 20
	attacker = _seat_plain(true, 0, 3, 5)
	_seat_id("iron_bastion", false, 3, combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	_check("Iron Bastion reduces an open face strike by one",
		bool(read.get("face", false)) and int(read.get("damage", -1)) == 2 \
		and int(read.get("hp_after", -1)) == 18, str(read))


func _test_poison_and_recoil() -> void:
	print("[combat-telegraph] -- Poison / Virulence / Thorns recoil")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 1, 4, ["poison"])
	var target = _seat_plain(true, 0, 0, 7)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Poison forecasts lethality after a nonlethal hit",
		read.get("target") == target and bool(read.get("lethal", false)) \
		and int(read.get("damage", -1)) == 1 \
		and String(read.get("text", "")).contains("DIES - POISON"), str(read))

	await _reset_board()
	combat._virulence_active[0] = true
	attacker = _seat_plain(false, 0, 1, 4)
	target = _seat_plain(true, 0, 0, 7, ["shield"])
	read = combat._predict_lane_strike(attacker)
	_check("Virulence matches the live Shield interaction",
		read.get("target") == target and bool(read.get("lethal", false)) \
		and bool(read.get("shield_break", false)) and int(read.get("damage", -1)) == 0 \
		and String(read.get("text", "")).contains("DIES - POISON"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 1)
	_seat_plain(true, 0, 0, 5, ["thorns"])
	read = combat._predict_lane_strike(attacker)
	_check("Thorns forecasts the attacker's death",
		String(read.get("text", "")).contains("ATTACKER DIES ON RETURN"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 3)
	_seat_plain(true, 0, 0, 5, ["thorns"], combat.ROW_FRONT,
		{"venom_thorns": true})
	read = combat._predict_lane_strike(attacker)
	_check("venomous Thorns forecasts its poison kill on the attacker",
		String(read.get("text", "")).contains("ATTACKER DIES ON RETURN"), str(read))


func _test_piercing_cleave_and_guardian() -> void:
	print("[combat-telegraph] -- Piercing / Cleave / Guardian")
	await _reset_board()
	var attacker = _seat_plain(false, 1, 5, 5, ["piercing"])
	_seat_plain(true, 1, 0, 2)
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Piercing reports lethal overkill",
		bool(read.get("lethal", false)) and int(read.get("overkill", -1)) == 3 \
		and String(read.get("text", "")).contains("PIERCES 3"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 1, 2, 5, [], combat.ROW_FRONT,
		{"passive": "cleave"})
	var main_target = _seat_plain(true, 1, 0, 6)
	_seat_plain(true, 0, 0, 1)
	_seat_plain(true, 2, 0, 4)
	_seat_plain(true, 1, 0, 4, ["shield"], combat.ROW_BACK)
	read = combat._predict_lane_strike(attacker)
	var cleave_text := String(read.get("text", ""))
	_check("Cleave summarizes all three canonical-adjacent riders",
		read.get("target") == main_target and cleave_text.contains("CLEAVE HITS 3") \
		and cleave_text.contains("1 DIE") and cleave_text.contains("1 SHIELD"),
		str(read))

	await _reset_board()
	attacker = _seat_plain(false, 1, 3, 5)
	var intended = _seat_plain(true, 1, 0, 6)
	var guardian = _seat_plain(true, 0, 0, 5, ["guardian"])
	read = combat._predict_lane_strike(attacker)
	_check("Guardian redirects the forecast away from the intended target",
		read.get("target") == guardian and read.get("target") != intended,
		str(read))


func _test_zero_attack_edges() -> void:
	print("[combat-telegraph] -- zero-ATK Shield / Armored parity")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 0, 5)
	var target = _seat_plain(true, 0, 0, 5, ["shield"])
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("zero ATK still pops Shield, matching take_damage(0)",
		read.get("target") == target and bool(read.get("shield_break", false)) \
		and int(read.get("damage", -1)) == 0 \
		and String(read.get("text", "")) == "SHIELD BREAKS", str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 0, 5)
	target = _seat_plain(true, 0, 0, 5, ["armored"])
	read = combat._predict_lane_strike(attacker)
	_check("zero ATK into Armored forecasts the resolver's minimum 1",
		read.get("target") == target and int(read.get("damage", -1)) == 1 \
		and int(read.get("hp_after", -1)) == 4, str(read))


func _test_rescue_wording() -> void:
	print("[combat-telegraph] -- Reborn / Phantom Veil wording")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 5, 5)
	var target = _seat_plain(true, 0, 0, 2, [], combat.ROW_FRONT,
		{"on_death": {"type": "reborn", "atk": 1, "hp": 1}})
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Reborn replaces a misleading DIES verdict",
		read.get("target") == target and String(read.get("rescue", "")) == "REBORN" \
		and String(read.get("text", "")) == "REBORN", str(read))

	await _reset_board()
	_equip_relic("phantom_veil")
	attacker = _seat_plain(true, 0, 5, 5)
	target = _seat_plain(false, 0, 0, 2)
	read = combat._predict_lane_strike(attacker)
	_check("Phantom Veil reports its still-available conditional rescue",
		read.get("target") == target \
		and String(read.get("rescue", "")) == "PHANTOM VEIL MAY SAVE" \
		and String(read.get("text", "")) == "PHANTOM VEIL MAY SAVE", str(read))


func _test_heal_projection_and_sniper_order() -> void:
	print("[combat-telegraph] -- pending HEAL projection / Sniper order")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 3, 5)
	var healer = _seat_plain(true, 0, 0, 5)
	healer.current_hp = 1
	healer.set_meta("current_intent", "HEAL")
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("pending HEAL is applied before forecast damage",
		read.get("target") == healer and int(read.get("damage", -1)) == 3 \
		and int(read.get("hp_after", -1)) == 1 and not bool(read.get("lethal", true)),
		str(read))

	await _reset_board()
	var sniper = _seat_plain(false, 3, 2, 4, ["sniper"])
	healer = _seat_plain(true, 0, 0, 5)
	healer.current_hp = 1
	healer.set_meta("current_intent", "HEAL")
	var actual_weakest = _seat_plain(true, 2, 0, 2)
	read = combat._predict_lane_strike(sniper)
	_check("Sniper compares post-HEAL HP when choosing its target",
		read.get("target") == actual_weakest and read.get("target") != healer,
		str(read))


func _test_repeat_notices() -> void:
	print("[combat-telegraph] -- Twinblade / Doubled Hour repeat notices")
	await _reset_board()
	combat.enemy_hp = 20
	var attacker = _seat_plain(false, 0, 2, 4, [], combat.ROW_FRONT,
		{"passive": "attacks_twice"})
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("Twinblade face forecast includes its later flank blow",
		bool(read.get("face", false)) \
		and String(read.get("text", "")).contains("FLANK BLOW LATER"), str(read))

	await _reset_board()
	combat.enemy_hp = 20
	combat._doubled_hour[0] = true
	attacker = _seat_plain(false, 0, 2, 4)
	read = combat._predict_lane_strike(attacker)
	_check("Doubled Hour face forecast includes its later repeat",
		bool(read.get("face", false)) \
		and String(read.get("text", "")).contains("STRIKES AGAIN LATER"), str(read))

	await _reset_board()
	attacker = _seat_plain(false, 0, 2, 1, [], combat.ROW_FRONT,
		{"passive": "attacks_twice"})
	_seat_plain(true, 0, 0, 5, ["thorns"])
	read = combat._predict_lane_strike(attacker)
	var twin_text := String(read.get("text", ""))
	_check("Twinblade flank blow is suppressed when Thorns kills it",
		not bool(read.get("attacker_survives", true)) \
		and twin_text.contains("ATTACKER DIES ON RETURN") \
		and not twin_text.contains("FLANK BLOW"), str(read))

	await _reset_board()
	combat._doubled_hour[0] = true
	attacker = _seat_plain(false, 0, 2, 2, [], combat.ROW_FRONT,
		{"passive": "attacks_all_lanes"})
	_seat_plain(true, 1, 3, 6)
	read = combat._predict_lane_strike(attacker)
	var doubled_text := String(read.get("text", ""))
	_check("Doubled repeat is suppressed when sweep return damage kills it",
		not bool(read.get("attacker_survives", true)) \
		and doubled_text.contains("ATTACKER DIES") \
		and not doubled_text.contains("STRIKES AGAIN"), str(read))


func _test_pavise_chain_suppression() -> void:
	print("[combat-telegraph] -- enemy Sniper / Pavise chain suppression")
	await _reset_board()
	_equip_relic("hexagonal_shield")
	var sniper = _seat_plain(true, 0, 2, 3, ["sniper"])
	var back_target = _seat_plain(false, 2, 0, 1, [], combat.ROW_BACK)
	_seat_plain(false, 1, 0, 5)
	var read: Dictionary = combat._predict_lane_strike(sniper)
	var text := String(read.get("text", ""))
	_check("Pavise kills an enemy Sniper after its back-row shot and stops the chain",
		read.get("target") == back_target and bool(read.get("lethal", false)) \
		and not bool(read.get("attacker_survives", true)) \
		and text.contains("ATTACKER DIES ON RETURN") \
		and not text.contains("CHAINS ON KILL"), str(read))


func _test_death_followup_wording() -> void:
	print("[combat-telegraph] -- Griffin / Death Card / Gravewarden's Pact")
	await _reset_board()
	var attacker = _seat_plain(false, 0, 5, 5)
	var enemy_griffin = _seat_id("griffin", true, 0)
	enemy_griffin.current_hp = 2
	var read: Dictionary = combat._predict_lane_strike(attacker)
	_check("solo enemy Griffin does not promise a return to the player's hand",
		read.get("target") == enemy_griffin \
		and String(read.get("death_followup", "")) == "" \
		and not String(read.get("text", "")).contains("RETURNS TO HAND"), str(read))

	await _reset_board()
	attacker = _seat_plain(true, 0, 5, 5)
	var friendly_griffin = _seat_id("griffin", false, 0)
	friendly_griffin.current_hp = 2
	friendly_griffin.deck_uid = 91001
	read = combat._predict_lane_strike(attacker)
	_check("friendly Griffin forecasts its once-per-fight hand return",
		read.get("target") == friendly_griffin \
		and String(read.get("death_followup", "")) == "RETURNS TO HAND" \
		and String(read.get("text", "")) == "RETURNS TO HAND", str(read))

	await _reset_board()
	_equip_relic("death_card")
	attacker = _seat_plain(true, 0, 5, 5)
	var death_card_target = _seat_plain(false, 0, 0, 2)
	death_card_target.deck_uid = 91002
	read = combat._predict_lane_strike(attacker)
	_check("Death Card forecasts a friendly non-token returning to hand",
		read.get("target") == death_card_target \
		and String(read.get("death_followup", "")) == "RETURNS TO HAND" \
		and String(read.get("text", "")) == "RETURNS TO HAND", str(read))

	await _reset_board()
	_equip_relic("gravewardens_pact")
	attacker = _seat_plain(true, 0, 5, 5)
	var pact_target = _seat_plain(false, 0, 0, 2)
	pact_target.deck_uid = 91003
	read = combat._predict_lane_strike(attacker)
	_check("Gravewarden's Pact names the 1/1 Imp rebirth after death",
		read.get("target") == pact_target \
		and String(read.get("death_followup", "")) == "REBORN AS A 1/1 IMP" \
		and String(read.get("text", "")).contains("DIES") \
		and String(read.get("text", "")).contains("REBORN AS A 1/1 IMP"), str(read))


func _reset_board() -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				var card = arr[lane]
				arr[lane] = null
				if card != null and is_instance_valid(card):
					card.queue_free()
	combat._encounter_passive = ""
	combat._virulence_active = [false, false]
	combat._doubled_hour = [false, false]
	combat._gravewardens_rebirths[0] = 0
	combat._gravewardens_rebirths[1] = 0
	combat._griffin_returned_uids.clear()
	combat._death_card_returns.clear()
	combat._cards_played_this_turn = 0
	RS.relics.clear()
	combat._rebuild_relic_cache()
	if combat.has_meta("phantom_veil_used"):
		combat.remove_meta("phantom_veil_used")
	combat.enemy_hp = 30
	combat.player_hp = 30
	combat.player_max_hp = 30
	combat.phase = combat.Phase.PLAYER_TURN
	await process_frame


func _equip_relic(id: String) -> void:
	RS.relics.clear()
	RS.relics.append(id)
	combat._rebuild_relic_cache()


func _seat_id(id: String, is_enemy: bool, lane: int, row: int = 0):
	return _seat_data(CDB.get_card_data(id).duplicate(true), is_enemy, lane, row)


func _seat_plain(is_enemy: bool, lane: int, atk: int, hp: int,
		keywords: Array = [], row: int = 0, extra: Dictionary = {}):
	var data := {
		"id": "telegraph_probe_%d" % _next_probe_id,
		"name": "Forecast Probe",
		"type": "creature",
		"ctype": "soldier",
		"cost": 1,
		"atk": atk,
		"hp": hp,
		"rarity": "common",
		"keywords": keywords.duplicate(),
		"desc": "",
	}
	_next_probe_id += 1
	for key in extra:
		data[key] = extra[key]
	return _seat_data(data, is_enemy, lane, row)


func _seat_data(data: Dictionary, is_enemy: bool, lane: int, row: int):
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", "telegraph_probe"))
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data
	card.current_lane = lane
	card.current_row = row
	card.current_hp = int(data.get("hp", 1))
	card.current_atk = int(data.get("atk", 0))
	combat._row_array(is_enemy, row)[lane] = card
	var slot = combat._slot_array(is_enemy, row)[lane]
	combat._slot_set_card(slot, card)
	if (data.get("keywords", []) as Array).has("shield"):
		card.state.has_shield = true
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[combat-telegraph] PASS  %s" % label)
	else:
		_failed.append(label)
		print("[combat-telegraph] FAIL  %s  %s" % [label, detail])


func _wait_for_player_turn() -> bool:
	for _tick in range(TURN_WAIT_TICKS):
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.PLAYER_TURN:
			return true
		await create_timer(TICK).timeout
	return false
