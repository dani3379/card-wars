extends SceneTree
## Targeted probe for the 2026-07-05 card slate:
##   Twinblade (breaker)          — attacks_twice second swing after the clash
##   Powder Cart (ember_stalker)  — detonate_dooms chains other Doom creatures
##   Standard Bearer              — token_lord: summoned tokens enter +1/+1
##   Penance (reckless_charge)    — burns a Curse from hand for 6 instead of 2
##   Mark of Ash                  — brands Doom 2 with a spent (0) blast
##   Sin-Eater                    — eat_curse: exhaust a Curse, +2/+2, draw 1
##   Old Campaigner (ironclad_veteran) — +1/+1 per 3 kills on its run ledger
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_newslate.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false
var combat: Node
var SS: Node
var NM: Node
var CDB: Node
var RS: Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()
	return _done


func _run_test() -> void:
	print("[newslate] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	CDB = root.get_node_or_null("CardDB")
	RS = root.get_node_or_null("RunState")
	if SS == null or NM == null or CDB == null or RS == null:
		print("[newslate] FATAL: autoloads missing")
		_finish(1)
		return

	# Boot combat as a connected host (no campaign RunState needed) — the same
	# setup _probe_boringcards / _probe_adj_buff use.
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 424242
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _tick in 8:
		await create_timer(0.3).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		_check(false, "combat scene survived boot")
		_finish(1)
		return

	var FRONT = combat.ROW_FRONT
	var BACK = combat.ROW_BACK

	# ── 1. Standard Bearer (token_lord): summoned tokens enter +1/+1 ─────────
	print("— Standard Bearer (token_lord)")
	combat.summon_token(1, 1, 0, true, FRONT)
	await create_timer(0.15).timeout
	var plain_tok = combat._row_array(true, FRONT)[0]
	_check(plain_tok != null and plain_tok.current_atk == 1 and plain_tok.current_hp == 1,
		"no bearer: token is a plain 1/1")
	combat._place_enemy_card(CDB.get_card_data("standard_bearer").duplicate(true), 1, FRONT)
	await create_timer(0.15).timeout
	combat.summon_token(1, 1, 2, true, FRONT)
	await create_timer(0.15).timeout
	var led_tok = combat._row_array(true, FRONT)[2]
	_check(led_tok != null and led_tok.current_atk == 2 and led_tok.current_hp == 2,
		"bearer on side: token musters as a 2/2")

	# ── 2. Twinblade (attacks_twice): a second swing after the clash ─────────
	print("— Twinblade (attacks_twice)")
	var tb_data = CDB.get_card_data("breaker").duplicate(true)
	combat._place_enemy_card(tb_data, 3, FRONT)
	var tb = combat._row_array(true, FRONT)[3]
	var punchbag = combat._net_spawn_creature(CDB.get_card_data("iron_bastion"), 93201, 3, FRONT, false, false)
	await create_timer(0.15).timeout
	var pb_hp0: int = punchbag.current_hp
	# Simulate "already swung in the main clash" — the pass returns exactly one
	# more attack to creatures with the passive.
	tb.has_attacked_this_turn = true
	var pfe: Array[bool] = [false, false, false, false]
	var efe: Array[bool] = [false, false, false, false]
	await combat._run_twinblade_swings(pfe, efe)
	await create_timer(0.2).timeout
	# iron_bastion is Armored (-1): twinblade ATK 2 lands for 1.
	_check(punchbag.current_hp == pb_hp0 - 1,
		"second swing landed once (%d -> %d, armored -1)" % [pb_hp0, punchbag.current_hp])
	tb.take_damage(99)
	await create_timer(0.3).timeout

	# ── 3. Powder Cart (detonate_dooms): the wagon takes the bombs with it ───
	print("— Powder Cart (detonate_dooms)")
	var cart = combat._net_spawn_creature(CDB.get_card_data("ember_stalker"), 93202, 1, BACK, false, false)
	var pup = combat._net_spawn_creature(CDB.get_card_data("cinder_pup"), 93203, 2, BACK, false, false)
	await create_timer(0.15).timeout
	_check(cart != null and cart.has_keyword("doom"), "cart carries Doom itself")
	var e_hp0: int = combat.enemy_hp
	cart.take_damage(99)
	await create_timer(0.5).timeout
	_check(combat._row_array(false, BACK)[2] == null, "cinder pup detonated with the cart")
	_check(combat.enemy_hp == e_hp0 - 2, "pup's blast (ATK 2) hit the enemy face (%d -> %d)" % [e_hp0, combat.enemy_hp])

	# ── 4. Penance: 2 damage plain, 6 burning a Curse from hand ──────────────
	print("— Penance (curse burn)")
	var pen_data = CDB.get_card_data("reckless_charge")
	var tgt1 = combat._place_enemy_card(CDB.get_card_data("iron_bastion").duplicate(true), 2, BACK)
	await create_timer(0.15).timeout
	var bast1 = combat._row_array(true, BACK)[2]
	var b1_hp0: int = bast1.current_hp
	await combat._resolve_custom_spell("penance", bast1, 2, pen_data)
	await create_timer(0.15).timeout
	# iron_bastion is Armored: every hit lands -1.
	_check(bast1.current_hp == b1_hp0 - 1, "no Curse in hand: 2 damage, armored -1 (%d -> %d)" % [b1_hp0, bast1.current_hp])
	combat._draw_card("curse")
	await create_timer(0.15).timeout
	var had_curse := false
	for hc in combat._hand:
		if hc.card_id == "curse":
			had_curse = true
	_check(had_curse, "a Curse sits in hand")
	var b1_hp1: int = bast1.current_hp
	await combat._resolve_custom_spell("penance", bast1, 2, pen_data)
	await create_timer(0.15).timeout
	_check(bast1.current_hp == b1_hp1 - 5, "Curse burned: 6 damage, armored -1 (%d -> %d)" % [b1_hp1, bast1.current_hp])
	var still_curse := false
	for hc in combat._hand:
		if is_instance_valid(hc) and hc.card_id == "curse":
			still_curse = true
	_check(not still_curse, "the Curse left the hand")
	_check(combat._exhaust_pile.has("curse"), "the Curse landed in the exhaust pile")

	# ── 5. Mark of Ash: Doom 2, spent blast ──────────────────────────────────
	print("— Mark of Ash (branded Doom)")
	combat._place_enemy_card(CDB.get_card_data("e_brute").duplicate(true), 0, BACK)
	var marked = combat._row_array(true, BACK)[0]
	await combat._resolve_custom_spell("mark_of_ash", marked, 0, CDB.get_card_data("mark_of_ash"))
	await create_timer(0.15).timeout
	_check(marked.has_keyword("doom"), "target now carries Doom")
	_check(marked.doom_counter == 2, "fuse set to 2")
	_check(int(marked.card_data.get("doom_damage", -1)) == 0, "blast is spent (doom_damage 0)")
	combat._detonate_doom(marked)
	await create_timer(0.5).timeout
	_check(combat._row_array(true, BACK)[0] == null, "detonation destroyed the marked creature")

	# ── 6. Sin-Eater: eats a Curse, grows, draws ─────────────────────────────
	print("— Sin-Eater (eat_curse)")
	combat._draw_card("curse")
	await create_timer(0.15).timeout
	var se = combat._net_spawn_creature(CDB.get_card_data("sin_eater"), 93204, 0, FRONT, false, false)
	await create_timer(0.15).timeout
	combat._resolve_on_play_ability(se, 0, false)
	await create_timer(0.3).timeout
	_check(se.current_atk == 4, "Sin-Eater grew to 4 ATK (2 + 2)")
	_check(se.current_hp == 5, "Sin-Eater grew to 5 HP (3 + 2)")
	var curse_left := false
	for hc in combat._hand:
		if is_instance_valid(hc) and hc.card_id == "curse":
			curse_left = true
	_check(not curse_left, "the eaten Curse left the hand")

	# ── 7. Old Campaigner: +1/+1 per 3 kills on its ledger (solo only) ───────
	print("— Old Campaigner (atk_hp_per_own_kills)")
	var oc = combat._net_spawn_creature(CDB.get_card_data("ironclad_veteran"), 93205, 1, FRONT, false, false)
	await create_timer(0.15).timeout
	oc.deck_uid = 777
	RS.creature_kills[777] = 7
	var oc_atk_net: int = oc.current_atk
	combat._apply_play_time_passives(oc, false)
	_check(oc.current_atk == oc_atk_net, "net mode: the kill ledger is NOT read (enters plain)")
	var saved_mode = combat.combat_mode
	combat.combat_mode = combat.CombatMode.SOLO
	combat._apply_play_time_passives(oc, false)
	combat.combat_mode = saved_mode
	_check(oc.current_atk == oc_atk_net + 2, "solo: 7 kills / 3 = +2 ATK (%d -> %d)" % [oc_atk_net, oc.current_atk])
	_check(oc.current_hp == 3 + 2, "solo: +2 HP too")
	RS.creature_kills.erase(777)

	_finish(_fails)


func _finish(code: int) -> void:
	if code == 0:
		print("[newslate] ALL PASS")
	else:
		print("[newslate] FAILED: %d checks" % code)
	_done = true
	quit(code)
