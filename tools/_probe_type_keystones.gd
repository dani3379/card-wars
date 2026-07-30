extends SceneTree
## _probe_type_keystones.gd — runtime proof the 3 type keystones FIRE (2026-07-15).
## Boots combat as NET_HOST (the host runs the authoritative engine where on-enter,
## friendly-death, and start-of-round passives resolve), seats controlled boards,
## and asserts each keystone's effect:
##   Gravepact       — a friendly death raises a 1/1 Wight (ctype dead) in its back row, once/round.
##   Warden-Sergeant — a FULL front row grants friendly Soldiers Armored + Thorns (not on a half line).
##   Bloodmoon Alpha — a Beast's on-enter fires twice (goblin's 1 face -> 2).
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_type_keystones.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false
var CDB: Node
var SS: Node
var NM: Node
var combat: Node
var _eid: int = 700000

func _check(cond: bool, label: String) -> void:
	if cond: print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done

func _finish(code: int) -> void:
	print("[keystones] FAILED : %d" % _fails)
	_done = true
	quit(code if code != 0 else (1 if _fails > 0 else 0))

func _seat(id: String, lane: int, row: int, is_enemy: bool, run_on_enter: bool = false) -> Node:
	var data: Dictionary = CDB.CARD_POOL[id].duplicate(true)
	_eid += 1
	return combat._net_spawn_creature(data, _eid, lane, row, is_enemy, run_on_enter)

func _clear_board() -> void:
	for is_e in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_e, row)
			for i in range(arr.size()):
				var c = arr[i]
				arr[i] = null
				if c != null and is_instance_valid(c) and c.get_parent() != null:
					c.get_parent().remove_child(c)

func _count_back(is_e: bool) -> int:
	var n := 0
	for c in combat._row_array(is_e, combat.ROW_BACK):
		if c != null: n += 1
	return n

func _run() -> void:
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if CDB == null or SS == null or NM == null:
		print("[keystones] FATAL autoloads missing"); _finish(1); return

	SS.reset()
	for cid in ["goblin", "brute", "goblin", "brute", "strike", "goblin", "brute", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	# All three terms of is_connected_to_peer() — Combat._ready gates combat_mode
	# on it, so leaving _compatibility_confirmed false silently boots SOLO and
	# every keystone below gets asserted against the wrong engine.
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _t in 8:
		await create_timer(0.4).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		_check(false, "combat booted"); _finish(1); return
	_check(combat.combat_mode == combat.CombatMode.NET_HOST, "booted NET_HOST")

	var FRONT: int = combat.ROW_FRONT
	var BACK: int = combat.ROW_BACK

	# ── GRAVEPACT ─────────────────────────────────────────────────────────
	print("— Gravepact: a friendly death raises a Wight")
	_clear_board()
	var gp = _seat("gravepact", 1, FRONT, false)
	var victim = _seat("pikeman", 2, FRONT, false)
	_check(gp != null and String(gp.card_data.get("ctype", "")) == "dead",
		"gravepact seated as ctype dead")
	combat._apply_ally_death_passives(false, victim)
	var wight = combat._row_array(false, BACK)[1]
	_check(wight != null, "a body was raised in gravepact's back-row lane")
	if wight != null:
		_check(String(wight.card_data.get("name", "")) == "Wight",
			"the raised body is a Wight (got '%s')" % String(wight.card_data.get("name", "")))
		_check(String(wight.card_data.get("ctype", "")) == "dead",
			"the Wight is ctype dead (re-feeds the machine)")
		_check(int(wight.current_atk) == 1 and int(wight.current_hp) == 1, "the Wight is 1/1")
	var back_after_first := _count_back(false)
	combat._apply_ally_death_passives(false, victim)
	_check(_count_back(false) == back_after_first, "gravepact reaps ONCE per round (2nd death raised nothing)")

	# ── WARDEN-SERGEANT ───────────────────────────────────────────────────
	print("— Warden-Sergeant: a full front line grows teeth")
	_clear_board()
	_seat("warden_sergeant", 0, FRONT, false)
	_seat("pikeman", 1, FRONT, false)
	_seat("shieldbearer", 2, FRONT, false)
	_seat("skirmisher", 3, FRONT, false)
	combat._apply_start_round_passives(false)
	var all_armored := true
	var all_thorns := true
	for c in combat._row_array(false, FRONT):
		if c == null: continue
		if not c.card_data.get("keywords", []).has("armored"): all_armored = false
		if not c.card_data.get("keywords", []).has("thorns"): all_thorns = false
	_check(all_armored, "full line: every front Soldier gained Armored")
	_check(all_thorns, "full line: every front Soldier gained Thorns")
	_clear_board()
	_seat("warden_sergeant", 0, FRONT, false)
	var lone = _seat("pikeman", 1, FRONT, false)
	combat._apply_start_round_passives(false)
	_check(not lone.card_data.get("keywords", []).has("armored"),
		"half line (2/4): no Armored granted — the condition holds")

	# ── BLOODMOON ALPHA ───────────────────────────────────────────────────
	print("— Bloodmoon Alpha: a Beast's arrival hits twice")
	_clear_board()
	_seat("bloodmoon_alpha", 0, FRONT, false)
	var face0 := int(combat.enemy_hp)
	_seat("goblin", 1, FRONT, false, true)   # goblin on_enter: 1 to face, doubled -> 2
	_check(int(combat.enemy_hp) == face0 - 2,
		"with Bloodmoon out, goblin's face hit doubled (%d -> %d, want -2)" % [face0, int(combat.enemy_hp)])
	_clear_board()
	var face1 := int(combat.enemy_hp)
	_seat("goblin", 1, FRONT, false, true)
	_check(int(combat.enemy_hp) == face1 - 1,
		"without Bloodmoon, goblin hits face once (%d -> %d, want -1)" % [face1, int(combat.enemy_hp)])

	# ── COVEN MOTHER (Warlock) ────────────────────────────────────────────
	print("— Coven Mother: casting a spell grows the coven")
	_clear_board()
	var cm = _seat("coven_mother", 0, FRONT, false)
	var wl2 = _seat("witch", 1, FRONT, false)   # witch = warlock
	combat._record_spell_cast_board_payoffs()   # simulate a resolved spell
	_check(int(wl2.persistent_atk_buff) >= 1, "Coven Mother: a spell buffed a fellow Warlock (+ATK for the fight)")
	_check(int(cm.persistent_atk_buff) >= 1, "Coven Mother: the buff hits the whole coven")

	# ── SIEGEWRIGHT (Bastion) ─────────────────────────────────────────────
	print("— War Fortress: the walls learn to hit back")
	_clear_board()
	var sw = _seat("siegewright", 0, FRONT, false)   # bastion
	var bs2 = _seat("bramble_stockade", 1, FRONT, false)     # bastion, 0 ATK
	combat._apply_start_round_passives(false)
	_check(int(bs2.persistent_atk_buff) >= 1, "War Fortress: a 0-ATK Bastion ramped +ATK at round start")
	_check(int(sw.persistent_atk_buff) >= 1, "War Fortress: the ramp hits the whole siege")

	# ── FREE COMPANY CAPTAIN (Stray) ──────────────────────────────────────
	# (2026-07-24 rework: the paymaster's per_gold aura retired with the rest of
	# the Stray gold spine — the tribe is MOBILITY + LARCENY now. DEFECTION: the
	# Captain loots a keyword off a corpse it kills, or free-redeploys when
	# there's nothing worth taking; while it stands, every other friendly Stray
	# free-redeploys on a kill. Driven here through the same two helpers
	# _apply_combat_strike_riders calls on every strike path.)
	print("— Defection: the crew loots the corpse and slips the line")
	_clear_board()
	var kp = _seat("kingpin", 0, FRONT, false)        # the Captain
	# (_seat reads CARD_POOL, so the corpse is a pool card seated enemy-side —
	# ENEMY_POOL ids like e_golem are NOT reachable from here.)
	var corpse = _seat("corpse_eater", 0, FRONT, true)   # keywords ["piercing"]
	_check(String(kp.card_data.get("passive", "")) == "defection",
		"the Captain carries the defection passive")
	_check(combat._stray_defection_active(kp, false), "Defection: the Captain may Defect on its own")
	combat._resolve_defection(kp, corpse, false)
	_check(kp.card_data.get("keywords", []).has("piercing"),
		"Defection: the Captain looted Piercing off the corpse")
	# A fellow Stray Defects only while a Captain stands — and only ever moves.
	var st2 = _seat("treasure_hunter", 1, FRONT, false)   # stray, no passive
	_check(combat._stray_defection_active(st2, false),
		"Defection: a fellow Stray turns on while the Captain stands")
	var st2_kw: int = st2.card_data.get("keywords", []).size()
	var st2_from := Vector2i(int(st2.current_row), int(st2.current_lane))
	combat._resolve_defection(st2, corpse, false)
	_check(Vector2i(int(st2.current_row), int(st2.current_lane)) != st2_from,
		"Defection: the fellow Stray free-redeployed to a new slot")
	_check(st2.card_data.get("keywords", []).size() == st2_kw,
		"Defection: only the Captain loots — the crew just moves")
	kp.current_hp = 0   # the Captain falls
	_check(not combat._stray_defection_active(st2, false),
		"Defection: no Captain, no turn-on")
	# Nothing worth taking: the Captain moves instead, so the kill is never dead.
	_clear_board()
	var kp2 = _seat("kingpin", 0, FRONT, false)
	var bare = _seat("goblin", 0, FRONT, true)   # no stealable keyword
	var kp2_from := Vector2i(int(kp2.current_row), int(kp2.current_lane))
	combat._resolve_defection(kp2, bare, false)
	_check(Vector2i(int(kp2.current_row), int(kp2.current_lane)) != kp2_from,
		"Defection: with nothing to loot, the Captain redeploys instead")

	_finish(0)
