extends SceneTree
## Targeted probe for the 2026-07-03 boring-card overhaul:
##   Oathbound Squire (squire_captain) — bodyguard ward redirects the column-mate's damage
##   Plague Rat                    — haul_front pulls the back-row enemy forward
##   Oathkeeper (gravecaller)      — atk_hp_per_fallen reads its side's ROUND tally
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
	# ALL THREE terms, or Combat._ready boots SOLO — see _probe_adj_buff.
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
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

	# ── 1. Oathbound Squire (2026-07-15 rework): damage its column-mate would
	# take strikes the Squire instead. State-derived ward — refresh, hit the
	# mate, and the Squire bleeds. Board layout matters downstream: the drummer
	# test reads front[1] as its neighbour and front[0] as the far lane, and the
	# Siege Golem test reuses front[0] — keep the brute at lane 0 + a goblin at
	# lane 1, like the old Drillmaster fixture did.
	print("— Oathbound Squire (bodyguard)")
	combat._place_enemy_card(CDB.get_card_data("brute").duplicate(true), 0, FRONT)
	var ward_mate = combat._row_array(true, FRONT)[0]
	combat._place_enemy_card(CDB.get_card_data("goblin").duplicate(true), 1, FRONT)
	combat._place_enemy_card(CDB.get_card_data("squire_captain").duplicate(true), 0, BACK)
	var sq = combat._row_array(true, BACK)[0]
	await create_timer(0.2).timeout
	combat._refresh_adjacency_buffs()
	var wm_hp: int = int(ward_mate.current_hp)
	var sq_hp: int = int(sq.current_hp)
	ward_mate.take_damage(2)
	_check(int(ward_mate.current_hp) == wm_hp, "bodyguard: the column-mate took nothing")
	_check(int(sq.current_hp) == sq_hp - 2, "bodyguard: the Squire took the 2 instead (%d -> %d)" % [sq_hp, sq.current_hp])
	sq.take_damage(99)   # clear the ward; a kill-convention hit always lands
	await create_timer(0.2).timeout
	combat._refresh_adjacency_buffs()
	ward_mate.take_damage(1)
	_check(int(ward_mate.current_hp) == wm_hp - 1, "bodyguard: the ward died, the mate bleeds again")

	# (Plague Rat was reverted to plain "Poison." — simple commons are a
	# feature, not a bug; no on-play test needed.)

	# ── 2. Oathkeeper: +1/+1 per friendly fallen THIS ROUND on its own side ──
	print("— Oathkeeper (atk_hp_per_fallen)")
	combat._enemy_deaths_this_round = 3
	var ok_data = CDB.get_card_data("gravecaller").duplicate(true)
	combat._place_enemy_card(ok_data, 3, BACK)
	var ok = combat._row_array(true, BACK)[3]
	combat._apply_play_time_passives(ok, true)
	await create_timer(0.15).timeout
	_check(ok.current_atk == int(ok_data.atk) + 3, "Oathkeeper ATK %d (+3 from 3 fallen)" % ok.current_atk)
	_check(ok.current_hp == int(CDB.get_card_data("gravecaller").hp) + 3, "Oathkeeper HP grew +3 too")
	combat._enemy_deaths_this_round = 0

	# ── 4. Battle Drummer: adjacent friendlies hold Swift while it beats ─────
	print("— Battle Drummer (drummer_swift)")
	combat._place_enemy_card(CDB.get_card_data("battle_drummer").duplicate(true), 2, FRONT)
	var drum = combat._row_array(true, FRONT)[2]
	combat._refresh_adjacency_buffs()
	var neigh = combat._row_array(true, FRONT)[1]   # the Drillmaster, lane 1
	var far = combat._row_array(true, FRONT)[0]     # lane 0 — NOT adjacent
	_check(neigh.state.drummer_swift, "adjacent creature holds drummer Swift")
	_check(combat._is_swift_attacker(neigh), "_is_swift_attacker sees the granted Swift")
	_check(not far.state.drummer_swift, "two lanes away: no Swift")
	drum.take_damage(99)
	await create_timer(0.3).timeout
	combat._refresh_adjacency_buffs()
	_check(not neigh.state.drummer_swift, "drum dies -> the Swift grant dies with it")

	# ── 5. Siege Golem: On-Enter — its fellow Engines gain Thorns ────────────
	# (The old "unstoppable ram" design left in the 2026-07-10 rare rework; the
	# golem is the engine-line armorer now — grant sharpened Armored→Thorns
	# 2026-07-13, since half the engine line already prints Armored.)
	print("— Siege Golem (engine armorer)")
	# Wall-cycle cards now print Thorns; Crystal Sentry is the clean no-Thorns
	# Bastion fixture for testing Siege Golem's grant.
	var eng_ally = CDB.get_card_data("crystal_sentry").duplicate(true)
	combat._place_enemy_card(eng_ally, 2, FRONT)
	var eng_wall = combat._row_array(true, FRONT)[2]
	var beast_ally = combat._row_array(true, FRONT)[0]   # the lane-0 brute from test 1
	_check(eng_wall != null and not eng_wall.has_keyword("thorns"),
		"the Bastion starts without Thorns")
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
