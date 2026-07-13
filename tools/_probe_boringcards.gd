extends SceneTree
## Targeted probe for the 2026-07-03 boring-card overhaul:
##   Drillmaster (squire_captain)  — buff_row_atk battlecry buffs the row
##   Plague Rat                    — haul_front pulls the back-row enemy forward
##   Oathkeeper (gravecaller)      — atk_hp_per_fallen reads its side's ledger
##   Battle Drummer                — drummer_swift meta grant on adjacency refresh
##   Siege Golem                   — unstoppable skips Guardian redirect + Thorns
##   Old Bones                     — diminishing on-death summon chain 3/3→2/2→1/1
## (Field Surgery's new full-heal+stun is covered net-side in
## _probe_skirmish_combat's magnitude-parity test.)
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_boringcards.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false
var combat: Node
var SS: Node
var NM: Node
var CDB: Node


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
	print("[boringcards] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	CDB = root.get_node_or_null("CardDB")
	if SS == null or NM == null or CDB == null:
		print("[boringcards] FATAL: autoloads missing")
		_finish(1)
		return

	# Boot combat as a connected host (no campaign RunState needed) — the same
	# setup _probe_adj_buff / _probe_skirmish_combat use.
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 999
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

	# ── 1. Drillmaster: +1 ATK THIS ROUND to the OTHER creatures in its row ──
	# (The buff moved to the this-round bucket — temp_atk_buff — in the
	# this-round-vs-this-fight pass; read effective_atk, not current_atk.)
	print("— Drillmaster (buff_row_atk)")
	combat._place_enemy_card(CDB.get_card_data("brute").duplicate(true), 0, FRONT)
	combat._place_enemy_card(CDB.get_card_data("goblin").duplicate(true), 3, FRONT)
	var mate0 = combat._row_array(true, FRONT)[0]
	var mate3 = combat._row_array(true, FRONT)[3]
	var m0_before: int = mate0.effective_atk()
	var m3_before: int = mate3.effective_atk()
	combat._place_enemy_card(CDB.get_card_data("squire_captain").duplicate(true), 1, FRONT)
	var dm = combat._row_array(true, FRONT)[1]
	await create_timer(0.2).timeout
	_check(mate0.effective_atk() == m0_before + 1, "row-mate lane 0 got +1 ATK this round (%d -> %d)" % [m0_before, mate0.effective_atk()])
	_check(mate3.effective_atk() == m3_before + 1, "row-mate lane 3 got +1 ATK this round (non-adjacent, same row)")
	_check(dm.effective_atk() == int(CDB.get_card_data("squire_captain").atk), "Drillmaster did not buff itself")

	# (Plague Rat was reverted to plain "Poison." — simple commons are a
	# feature, not a bug; no on-play test needed.)

	# ── 2. Oathkeeper: +1/+1 per fallen friendly on its own side ─────────────
	print("— Oathkeeper (atk_hp_per_fallen)")
	combat._enemy_deaths_this_fight = 3
	var ok_data = CDB.get_card_data("gravecaller").duplicate(true)
	combat._place_enemy_card(ok_data, 3, BACK)
	var ok = combat._row_array(true, BACK)[3]
	combat._apply_play_time_passives(ok, true)
	await create_timer(0.15).timeout
	_check(ok.current_atk == int(ok_data.atk) + 3, "Oathkeeper ATK %d (+3 from 3 fallen)" % ok.current_atk)
	_check(ok.current_hp == int(CDB.get_card_data("gravecaller").hp) + 3, "Oathkeeper HP grew +3 too")
	combat._enemy_deaths_this_fight = 0

	# ── 4. Battle Drummer: adjacent friendlies hold Swift while it beats ─────
	print("— Battle Drummer (drummer_swift)")
	combat._place_enemy_card(CDB.get_card_data("battle_drummer").duplicate(true), 2, FRONT)
	var drum = combat._row_array(true, FRONT)[2]
	combat._refresh_adjacency_buffs()
	var neigh = combat._row_array(true, FRONT)[1]   # the Drillmaster, lane 1
	var far = combat._row_array(true, FRONT)[0]     # lane 0 — NOT adjacent
	_check(bool(neigh.get_meta("drummer_swift", false)), "adjacent creature holds drummer Swift")
	_check(combat._is_swift_attacker(neigh), "_is_swift_attacker sees the granted Swift")
	_check(not bool(far.get_meta("drummer_swift", false)), "two lanes away: no Swift")
	drum.take_damage(99)
	await create_timer(0.3).timeout
	combat._refresh_adjacency_buffs()
	_check(not bool(neigh.get_meta("drummer_swift", false)), "drum dies -> the Swift grant dies with it")

	# ── 5. Siege Golem: On-Enter — its fellow Engines gain Thorns ────────────
	# (The old "unstoppable ram" design left in the 2026-07-10 rare rework; the
	# golem is the engine-line armorer now — grant sharpened Armored→Thorns
	# 2026-07-13, since half the engine line already prints Armored.)
	print("— Siege Golem (engine armorer)")
	var eng_ally = CDB.get_card_data("stone_wall").duplicate(true)
	combat._place_enemy_card(eng_ally, 2, FRONT)
	var eng_wall = combat._row_array(true, FRONT)[2]
	var beast_ally = combat._row_array(true, FRONT)[0]   # the lane-0 brute from test 1
	_check(eng_wall != null and not eng_wall.has_keyword("thorns"),
		"the engine wall starts without Thorns")
	var golem_data = CDB.get_card_data("siege_golem").duplicate(true)
	combat._place_enemy_card(golem_data, 0, BACK)
	var golem = combat._row_array(true, BACK)[0]
	await create_timer(0.15).timeout
	_check(eng_wall != null and eng_wall.has_keyword("thorns"),
		"Siege Golem armed its fellow Engine with Thorns")
	_check(beast_ally == null or not beast_ally.has_keyword("thorns"),
		"the beast row-mate got nothing — the grant is Engines-only")
	_check(golem != null and not golem.has_keyword("thorns"),
		"the golem arms the OTHERS, not itself")

	# ── 6. Old Bones: dies into a 2/2, which dies into a 1/1, which stays dead ─
	print("— Old Bones (diminishing rise)")
	var ob_data = CDB.get_card_data("old_bones").duplicate(true)
	combat._place_enemy_card(ob_data, 3, FRONT)
	var ob = combat._row_array(true, FRONT)[3]
	ob.take_damage(99)
	await create_timer(0.4).timeout
	var rise1 = combat._row_array(true, FRONT)[3]
	_check(rise1 != null and rise1.current_atk == 2 and rise1.current_hp == 2,
		"first rise: a 2/2 stands in the lane")
	if rise1 != null:
		_check(rise1.card_data.has("on_death"), "the 2/2 carries its own diminishing On-Death")
		rise1.take_damage(99)
		await create_timer(0.4).timeout
		var rise2 = combat._row_array(true, FRONT)[3]
		_check(rise2 != null and rise2.current_atk == 1 and rise2.current_hp == 1,
			"second rise: a 1/1 stands in the lane")
		if rise2 != null:
			_check(not rise2.card_data.has("on_death"), "the 1/1 has NO further rise")
			rise2.take_damage(99)
			await create_timer(0.4).timeout
			_check(combat._row_array(true, FRONT)[3] == null, "the 1/1 stays dead — chain ends")

	_finish(_fails)


func _finish(code: int) -> void:
	if code == 0:
		print("[boringcards] ALL PASS")
	else:
		print("[boringcards] FAILED: %d checks" % code)
	_done = true
	quit(code)
