extends SceneTree
## Correctness probe for the 2026-07-15 interest slate — 18 boring/repetitive
## cards replaced with new effects (ids kept). Static checks pin the CardDB
## shapes; runtime checks boot real SOLO combat and drive each new mechanic
## through its real resolver/hook:
##   hero_pay (Bloodsworn)          — the owner's hero pays the blood price
##   buff_per_ctype (Heartwood)     — arrives +1/+1 per other friendly Beast
##   per_ctype breath (Hatchling)   — AoE scales with the pack
##   swell_on_ally_death (Gravedigger) — your-turn deaths grow him +1/+1
##   vampire_feed (Vampire Lord)    — drinks a dead Dead's ATK
##   betray_opposing (Tallow Doll) — the opposing enemy turns on its own side
##   gain_gold / bonus_mana_next_turn (Scavenger / Mourner) — on-death payouts
##   ram_row_back (The Leveler)     — the enemy front line falls back or crashes
##   buff_ctype_hp (Warding Stone) — all friendly Bastions gain max/current HP
##   spark_on_spell / shield_on_spell (Cinder Acolyte / Ember Warden)
## (bodyguard is covered in _probe_boringcards, column_ward in
## _probe_skirmish_combat, tonic_vigor in _probe_boring_swap, kingpin's gold
## aura in _probe_type_keystones.)
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_interest_slate.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
var RS: Node
var US: Node
var SS: Node
var CDB: Node
var KE: Node
var combat: Node
var _started := false
var _pass := 0
var _fail: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[interest] start")
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	CDB = root.get_node_or_null("CardDB")
	KE = root.get_node_or_null("KeywordEffects")
	if RS == null or CDB == null or KE == null:
		print("[interest] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	_static_checks()

	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[interest] FATAL no player turn"); quit(1); return

	await _test_hero_pay()
	await _test_buff_per_ctype()
	await _test_beast_breath()
	await _test_swell_on_ally_death()
	await _test_vampire_feed()
	await _test_tallow_betrayal()
	await _test_death_payouts()
	await _test_ram_row_back()
	await _test_warding_stone()
	await _test_wall_cycle_reactions()
	await _test_spell_payoffs()

	print("[interest] ============ SUMMARY ============")
	print("[interest] passed : %d" % _pass)
	print("[interest] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[interest] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _static_checks() -> void:
	var P: Dictionary = CDB.CARD_POOL
	var U: Dictionary = CDB.UPGRADES
	_assert("static: mourner pays Command on death",
		String(P["mourner"]["on_death"]["type"]) == "bonus_mana_next_turn")
	# Tests the INTENT (back row = the scout mode), not one exact phrasing. The
	# literal "next arrival" broke the day a copy pass reworded the card to
	# "next ENEMY arrival" — a substring match on prose is a tripwire under the
	# copy team, so match the two load-bearing words instead.
	_assert("static: lookout back mode is the scout (desc)",
		"Back row" in String(P["lookout"]["desc"])
		and "arrival" in String(P["lookout"]["desc"]))
	_assert("static: Warding Stone is the 1-cost Bastion fortifier",
		int(P["warding_stone"]["cost"]) == 1
		and int(P["warding_stone"]["atk"]) == 0
		and int(P["warding_stone"]["hp"]) == 3
		and String(P["warding_stone"]["on_enter"]["type"]) == "buff_ctype_hp"
		and int(P["warding_stone"]["on_enter"]["value"]) == 2)
	_assert("static: squire_captain is the Oathbound Squire bodyguard",
		P["squire_captain"]["name"] == "Oathbound Squire"
		and String(P["squire_captain"].get("passive", "")) == "bodyguard"
		and not P["squire_captain"].has("on_play"))
	_assert("static: gravedigger swells on ally death",
		String(P["gravedigger"].get("passive", "")) == "swell_on_ally_death")
	_assert("static: scavenger pays gold on death",
		String(P["scavenger"]["on_death"]["type"]) == "gain_gold"
		and not P["scavenger"].has("passive"))
	_assert("static: heartwood_elder arrives per-Beast",
		String(P["heartwood_elder"]["on_enter"]["type"]) == "buff_per_ctype"
		and not P["heartwood_elder"].has("passive"))
	_assert("static: Tallow Doll is the 2-cost 2/2 betrayal curse",
		int(P["tallow_doll"]["cost"]) == 2
		and int(P["tallow_doll"]["atk"]) == 2 and int(P["tallow_doll"]["hp"]) == 2
		and String(P["tallow_doll"]["on_death"]["type"]) == "betray_opposing")
	_assert("static: the remaining wall cycle has its final costs and bodies",
		P["ironhide_anvil"]["name"] == "Iron Rampart"
		and int(P["ironhide_anvil"]["cost"]) == 1
		and int(P["ironhide_anvil"]["hp"]) == 3
		and String(P["ironhide_anvil"]["passive"]) == "reflect_strike"
		and int(P["bramble_stockade"]["cost"]) == 1 and int(P["bramble_stockade"]["hp"]) == 3
		and P["siegewright"]["name"] == "War Fortress"
		and int(P["siegewright"]["cost"]) == 2 and int(P["siegewright"]["hp"]) == 6)
	_assert("static: forged Warding Stone fortifies for +3 HP",
		int(U["warding_stone"].get("on_enter_value", 0)) == 1)
	_assert("static: iron_bastion is the Honor Guard rare (c4, column_ward)",
		P["iron_bastion"]["name"] == "Honor Guard"
		and P["iron_bastion"]["rarity"] == "rare"
		and int(P["iron_bastion"]["cost"]) == 4
		and String(P["iron_bastion"].get("passive", "")) == "column_ward")
	_assert("static: the_apothecary drinks along",
		String(P["the_apothecary"].get("passive", "")) == "tonic_vigor")
	_assert("static: dragon_hatchling breath scales with Beasts, Swift dropped",
		String(P["dragon_hatchling"]["on_enter"].get("per_ctype", "")) == "beast"
		and not P["dragon_hatchling"]["keywords"].has("swift"))
	# The 2026-07-24 Stray rework RETIRED the gold spine outright: no pool card
	# carries `per_gold` any more, and the Free Company Captain became the larceny
	# keystone (`defection` — loot a keyword off a corpse, or free-redeploy). This
	# assertion still described the old gold aura, so it did not merely fail — it
	# threw, reading `type_buff` off a dictionary that no longer has the key.
	_assert("static: kingpin is the larceny keystone, gold aura retired",
		String(P["kingpin"].get("passive", "")) == "defection"
		and not P["kingpin"].has("type_buff")
		and not P["kingpin"].has("on_enter"))
	_assert("static: vampire_lord feeds on friendly Dead deaths",
		String(P["vampire_lord"].get("passive", "")) == "vampire_feed")
	_assert("static: the_leveler rams the front line",
		String(P["the_leveler"]["on_enter"]["type"]) == "ram_row_back")
	_assert("static: bloodsworn pays the blood price at 4/4",
		String(P["bloodsworn"]["on_enter"]["type"]) == "hero_pay"
		and int(P["bloodsworn"]["atk"]) == 4 and int(P["bloodsworn"]["hp"]) == 4)
	_assert("static: cinder_acolyte is the common spark caster",
		P["cinder_acolyte"]["rarity"] == "common"
		and String(P["cinder_acolyte"].get("passive", "")) == "spark_on_spell")
	_assert("static: ember_warden shields on cast",
		String(P["ember_warden"].get("passive", "")) == "shield_on_spell")
	for uid in ["mourner", "lookout", "warding_stone", "squire_captain",
			"gravedigger", "scavenger", "heartwood_elder",
			"tallow_doll", "iron_bastion", "the_apothecary", "dragon_hatchling",
			"kingpin", "vampire_lord", "the_leveler", "bloodsworn",
			"cinder_acolyte", "ember_warden"]:
		_assert("static: UPGRADES entry for %s" % uid, U.has(uid))
	if SS != null:
		_assert("static: kingpin + lookout skirmish-denylisted, heartwood freed",
			SS.SKIRMISH_DENYLIST.has("kingpin") and SS.SKIRMISH_DENYLIST.has("lookout")
			and not SS.SKIRMISH_DENYLIST.has("heartwood_elder"))
		_assert("static: wall cycle and Tallow are net legal",
			not SS.SKIRMISH_DENYLIST.has("ironhide_anvil")
			and not SS.SKIRMISH_DENYLIST.has("bramble_stockade")
			and not SS.SKIRMISH_DENYLIST.has("warding_stone")
			and not SS.SKIRMISH_DENYLIST.has("tallow_doll"))


func _test_hero_pay() -> void:
	_clear_all()
	var tok = _place(4, 4, 0, false, combat.ROW_FRONT)
	var hp0: int = int(combat.player_hp)
	KE._run_on_enter({"type": "hero_pay", "value": 2}, tok, 0, false, combat)
	_assert("hero_pay: the hero paid 2 HP", int(combat.player_hp) == hp0 - 2)
	combat.player_hp = hp0


func _test_buff_per_ctype() -> void:
	_clear_all()
	var b1 = _place(1, 1, 1, false, combat.ROW_FRONT)
	b1.card_data["ctype"] = "beast"
	var b2 = _place(1, 1, 2, false, combat.ROW_FRONT)
	b2.card_data["ctype"] = "beast"
	var hw = _place(2, 3, 0, false, combat.ROW_FRONT)
	hw.card_data["ctype"] = "beast"
	KE._run_on_enter({"type": "buff_per_ctype", "ctype": "beast", "atk": 1, "hp": 1},
		hw, 0, false, combat)
	_assert("buff_per_ctype: 2 packmates -> Heartwood lands 4/5",
		int(hw.current_atk) == 4 and int(hw.current_hp) == 5)


func _test_beast_breath() -> void:
	_clear_all()
	var b1 = _place(1, 1, 1, false, combat.ROW_FRONT)
	b1.card_data["ctype"] = "beast"
	var b2 = _place(1, 1, 2, false, combat.ROW_FRONT)
	b2.card_data["ctype"] = "beast"
	var dh = _place(4, 6, 0, false, combat.ROW_FRONT)
	dh.card_data["ctype"] = "beast"
	var foe = _place(1, 5, 3, true, combat.ROW_FRONT)
	KE._run_on_enter({"type": "damage_all_enemies", "value": 1, "per_ctype": "beast"},
		dh, 0, false, combat)
	_assert("beast breath: base 1 + 2 packmates = 3 to every enemy",
		int(foe.current_hp) == 2)
	# The shipped card (2026-07-15 sweep tune): bonus capped at +2 and the
	# blast strafes the FRONT line only — the back row hides from the fire.
	var b3 = _place(1, 1, 3, false, combat.ROW_BACK)
	b3.card_data["ctype"] = "beast"
	var hidden = _place(1, 5, 2, true, combat.ROW_BACK)
	KE._run_on_enter(CDB.CARD_POOL["dragon_hatchling"]["on_enter"], dh, 0, false, combat)
	_assert("beast breath: shipped writ caps at 3 despite 3 packmates (front foe 2 -> -1)",
		int(foe.current_hp) <= 0 or not is_instance_valid(foe))
	_assert("beast breath: the back row hides from the front-line strafe",
		is_instance_valid(hidden) and int(hidden.current_hp) == 5)


func _test_swell_on_ally_death() -> void:
	_clear_all()
	var gd = _place(1, 3, 0, false, combat.ROW_BACK)
	gd.card_data["passive"] = "swell_on_ally_death"
	var chaff = _place(1, 1, 1, false, combat.ROW_FRONT)
	chaff.take_damage(999)
	await create_timer(0.2).timeout
	_assert("swell: a your-turn friendly death grew Gravedigger +1/+1 (2/4)",
		int(gd.current_atk) == 2 and int(gd.current_hp) == 4)


func _test_vampire_feed() -> void:
	_clear_all()
	var vamp = _place(3, 4, 0, false, combat.ROW_BACK)
	vamp.card_data["passive"] = "vampire_feed"
	var meal = _place(3, 2, 1, false, combat.ROW_FRONT)
	meal.card_data["ctype"] = "dead"
	meal.take_damage(999)
	await create_timer(0.2).timeout
	_assert("vampire_feed: drank the fallen Dead's 3 ATK (3 -> 6)",
		int(vamp.current_atk) == 6)
	var chaff = _place(2, 2, 2, false, combat.ROW_FRONT)   # untyped — no meal
	chaff.take_damage(999)
	await create_timer(0.2).timeout
	_assert("vampire_feed: an untyped death is no meal (stays 6)",
		int(vamp.current_atk) == 6)


func _test_tallow_betrayal() -> void:
	_clear_all()
	# Two allies are one step away. Same-row lane 1 wins the deterministic tie
	# over the column-mate in back lane 2, then counters the compelled 4-ATK hit.
	var traitor = _place(4, 6, 2, true, combat.ROW_FRONT)
	var same_row = _place(2, 5, 1, true, combat.ROW_FRONT)
	var column_mate = _place(3, 5, 2, true, combat.ROW_BACK)
	var doll = _place(2, 2, 2, false, combat.ROW_FRONT)
	doll.card_data["on_death"] = {"type": "betray_opposing"}
	doll.take_damage(999)
	await create_timer(0.2).timeout
	_assert("betrayal: nearest same-row ally took the compelled 4 damage",
		int(same_row.current_hp) == 1 and int(column_mate.current_hp) == 5)
	_assert("betrayal: the chosen ally countered for 2",
		int(traitor.current_hp) == 4)

	_clear_all()
	var lone = _place(3, 5, 1, true, combat.ROW_FRONT)
	var face0: int = int(combat.enemy_hp)
	var doll2 = _place(2, 2, 1, false, combat.ROW_FRONT)
	doll2.card_data["on_death"] = {"type": "betray_opposing"}
	doll2.take_damage(999)
	await create_timer(0.2).timeout
	_assert("betrayal: a lone opposing enemy struck its own face",
		is_instance_valid(lone) and int(combat.enemy_hp) == face0 - 3)


func _test_death_payouts() -> void:
	_clear_all()
	var gold0: int = int(RS.gold)
	var scav = _place(2, 1, 0, false, combat.ROW_FRONT)
	scav.card_data["on_death"] = {"type": "gain_gold", "value": 4}
	scav.take_damage(999)
	await create_timer(0.2).timeout
	_assert("gain_gold: the scavenger's pockets paid 4 gold",
		int(RS.gold) == gold0 + 4)
	var mana0: int = int(combat._bonus_mana_next_turn)
	var mo = _place(1, 2, 1, false, combat.ROW_FRONT)
	mo.card_data["on_death"] = {"type": "bonus_mana_next_turn", "value": 1}
	mo.take_damage(999)
	await create_timer(0.2).timeout
	_assert("bonus_mana_next_turn: the Mourner banked 1 Command for next turn",
		int(combat._bonus_mana_next_turn) == mana0 + 1)


func _test_ram_row_back() -> void:
	_clear_all()
	var free_foe = _place(1, 4, 0, true, combat.ROW_FRONT)   # back seat empty
	var jam_front = _place(1, 5, 1, true, combat.ROW_FRONT)  # back seat blocked
	var jam_back = _place(1, 5, 1, true, combat.ROW_BACK)
	var lev = _place(6, 6, 0, false, combat.ROW_FRONT)
	KE._run_on_enter({"type": "ram_row_back", "value": 3}, lev, 0, false, combat)
	await create_timer(0.2).timeout
	_assert("ram: an open lane falls back (front empty, body in the back row)",
		combat._row_array(true, combat.ROW_FRONT)[0] == null
		and combat._row_array(true, combat.ROW_BACK)[0] == free_foe)
	_assert("ram: a jammed lane crashes for 3 on both bodies",
		int(jam_front.current_hp) == 2 and int(jam_back.current_hp) == 2)


func _test_warding_stone() -> void:
	_clear_all()
	var wall = _place(0, 4, 1, false, combat.ROW_BACK)
	wall.card_data["ctype"] = "bastion"
	var pike = _place(2, 3, 2, false, combat.ROW_FRONT)
	pike.card_data["ctype"] = "soldier"
	var stone = _place(0, 3, 0, false, combat.ROW_FRONT)
	stone.card_data["ctype"] = "bastion"
	KE._run_on_enter({"type": "buff_ctype_hp", "ctype": "bastion", "value": 2},
		stone, 0, false, combat)
	_assert("Warding Stone: includes itself (+2 max/current HP)",
		int(stone.card_data.hp) == 5 and int(stone.current_hp) == 5)
	_assert("Warding Stone: fortifies a Bastion in the other row",
		int(wall.card_data.hp) == 6 and int(wall.current_hp) == 6)
	_assert("Warding Stone: does not fortify a non-Bastion",
		int(pike.card_data.hp) == 3 and int(pike.current_hp) == 3)


func _test_wall_cycle_reactions() -> void:
	_clear_all()
	# A lethal five-power strike removes only the Rampart's three real HP, so
	# exactly three reflects — not the raw five and not zero on death.
	var rampart = _place(0, 3, 0, false, combat.ROW_FRONT)
	rampart.card_data["passive"] = "reflect_strike"
	var striker = _place(5, 8, 0, true, combat.ROW_FRONT)
	await combat._creature_attacks_creature(striker, rampart, 0, true)
	await create_timer(0.2).timeout
	_assert("Iron Rampart: lethal strike reflected actual HP lost (3)",
		is_instance_valid(striker) and int(striker.current_hp) == 5)

	_clear_all()
	var stockade = _place(0, 3, 1, false, combat.ROW_FRONT)
	stockade.card_data["passive"] = "anvil_spawn"
	stockade.card_data["keywords"] = ["guardian", "thorns"]
	var hitter2 = _place(1, 6, 1, true, combat.ROW_FRONT)
	await combat._creature_attacks_creature(hitter2, stockade, 1, true)
	var spawned := false
	for c in combat._all_player_creatures():
		if c != stockade and is_instance_valid(c) and int(c.current_atk) == 1 \
				and int(c.current_hp) == 1:
			spawned = true
	_assert("Bramble Stockade: a survived strike summoned an adjacent 1/1", spawned)


func _test_spell_payoffs() -> void:
	_clear_all()
	var ac = _place(1, 3, 0, false, combat.ROW_FRONT)
	ac.card_data["passive"] = "spark_on_spell"
	var foe = _place(1, 5, 0, true, combat.ROW_FRONT)
	var ew = _place(1, 4, 1, false, combat.ROW_FRONT)
	ew.card_data["passive"] = "shield_on_spell"
	combat._record_spell_cast_board_payoffs()
	_assert("spark_on_spell: the cast sparked 1 at the enemy opposing her (5 -> 4)",
		int(foe.current_hp) == 4)
	_assert("shield_on_spell: the cast wrapped the warden in Shield",
		bool(ew.state.has_shield))


# --- helpers (same kit as _probe_boring_swap) ---

func _place(atk: int, hp: int, lane: int, is_enemy: bool, row: int):
	var arr: Array = combat._row_array(is_enemy, row)
	if arr[lane] != null and is_instance_valid(arr[lane]):
		arr[lane].queue_free()
		arr[lane] = null
	combat.summon_token(atk, hp, lane, is_enemy, row)
	return combat._row_array(is_enemy, row)[lane]


func _clear_all() -> void:
	for is_e in [true, false]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_e, row)
			for l in range(combat.LANES_PER_ROW):
				if arr[l] != null and is_instance_valid(arr[l]):
					arr[l].queue_free()
					arr[l] = null


func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("[interest] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[interest] FAIL  %s" % name)


func _wait_for_player_turn() -> bool:
	# Wait for PLAYER_TURN *and* the dealt opening hand: the round-1
	# _start_round() lands late (after the intro cascade) and resets
	# _bonus_mana_next_turn — racing it flakes the Mourner assert. The refill
	# runs after that reset inside _start_round, so a dealt hand proves the
	# opener has fully landed.
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN and combat._hand.size() >= 4:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false
