extends SceneTree
## Relic pool cut + fun slate probe (2026-07-07). Verifies the 14 cuts are gone,
## the 5 in-place reshapes carry their new identities, the 6 new relics exist
## with icons, and unit-drives the new combat behaviors on the real combat
## scene: Sharpened Pitchforks (2/1 tokens), Man-Trap (thorns-death splash),
## Poisoned Rations (first reinforcement dies), Dregs (bottle throw),
## Deserter's Toll (first discard strikes), Sellsword's Retainer (gold-gated
## hireling), Letters Patent (epithet fold), Sutler's Marker (double buy-back).
##
## Run: Godot_console.exe --headless --path "D:\Godot" --script res://tools/_probe_relic_slate.gd

var combat: Node
var _started := false
var _done := false
var _pass := 0
var _fail := 0

const CUT_IDS := ["fortress_stone", "pyromaniac_ring", "stone_skin",
	"scroll_of_greed", "art_of_war", "sundial", "frozen_eye", "looking_glass",
	"spike_driver", "frost_spike", "berserkers_totem", "crimson_chalice",
	"skull_throne", "hourglass_sigil"]
const RESHAPED := {
	"briar_amulet": ["Man-Trap", "man_trap"],
	"piercing_crown": ["Bodkin Points", "always_overflow"],
	"hexagonal_shield": ["Pavise", "pavise"],
	"scavengers_pouch": ["Sutler's Marker", "sell_double"],
	"the_family": ["Sharpened Pitchforks", "token_pitchforks"],
}
const NEW_IDS := ["letters_patent", "deserters_toll", "drovers_whip",
	"dregs", "poisoned_rations", "sellswords_retainer"]


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
		print("[relic_slate]   PASS  %s" % label)
	else:
		_fail += 1
		print("[relic_slate]   FAIL  %s   %s" % [label, detail])


func _run() -> void:
	print("[relic_slate] start")
	var RS = root.get_node_or_null("RunState")
	var US = root.get_node_or_null("UserSettings")
	var CDB = root.get_node_or_null("CardDB")
	var RDB: GDScript = load("res://scripts/data/RelicDB.gd")
	if RS == null or CDB == null:
		print("[relic_slate] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	var SS = root.get_node_or_null("SkirmishState")
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	# ── 1. Catalog integrity ────────────────────────────────────────────────
	for id in CUT_IDS:
		_ck("cut id gone: %s" % id, not RDB.RELICS.has(id))
	for id in RESHAPED:
		var entry: Dictionary = RDB.RELICS.get(id, {})
		_ck("reshaped %s -> %s" % [id, RESHAPED[id][0]],
			entry.get("name", "") == RESHAPED[id][0]
			and entry.get("effect", "") == RESHAPED[id][1],
			"got name=%s effect=%s" % [entry.get("name", "?"), entry.get("effect", "?")])
	for id in NEW_IDS:
		var e: Dictionary = RDB.RELICS.get(id, {})
		_ck("new relic present: %s" % id,
			not e.is_empty() and String(e.get("desc", "")) != "" and e.get("tier", "") == "combat")
	# Every relic id has an icon on disk (png painting or svg silhouette).
	var icons_ok := true
	for id in RDB.RELICS.keys():
		if not (ResourceLoader.exists("res://assets/icons/relics/%s.png" % id)
				or ResourceLoader.exists("res://assets/icons/relics/%s.svg" % id)):
			print("  missing icon: ", id)
			icons_ok = false
	_ck("every relic has an icon file (%d relics)" % RDB.RELICS.size(), icons_ok)

	# ── 2. Letters Patent fold (RunState.get_upgraded_card_data) ───────────
	RS.start_new_run("raider", 0, 777)
	var uid: int = RS.deck_uids[0]
	var base_atk: int = int(CDB.get_card_data(RS.deck[0]).get("atk", 0))
	RS.creature_kills[uid] = 3
	var no_relic: Dictionary = RS.get_upgraded_card_data(uid)
	RS.relics.append("letters_patent")
	var with_relic: Dictionary = RS.get_upgraded_card_data(uid)
	_ck("epithet folds without knighthood at 3 kills",
		int(no_relic.get("atk", -1)) == base_atk and "the" in String(no_relic.get("name", "")).to_lower())
	_ck("Letters Patent folds +1/+1 at 3 kills",
		int(with_relic.get("atk", -1)) == base_atk + 1,
		"atk %d vs base %d" % [int(with_relic.get("atk", -1)), base_atk])
	RS.creature_kills.erase(uid)
	RS.relics.erase("letters_patent")

	# ── 3. Sutler's Marker doubles the buy-back ────────────────────────────
	var shop = load("res://scripts/scenes/Shop.gd").new()
	var plain_curse: int = shop._sell_price("curse")
	var plain_card: int = shop._sell_price(RS.deck[0])
	RS.relics.append("scavengers_pouch")
	_ck("Sutler's Marker doubles a card", shop._sell_price(RS.deck[0]) == plain_card * 2)
	_ck("Sutler's Marker doubles a curse", shop._sell_price("curse") == plain_curse * 2)
	RS.relics.erase("scavengers_pouch")
	shop.free()

	# ── 4. Combat-scene behaviors ───────────────────────────────────────────
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	var ok := false
	for _i in 40:
		await create_timer(0.1).timeout
		if not is_instance_valid(combat):
			break
		if combat.phase == combat.Phase.PLAYER_TURN:
			ok = true
			break
	if not ok:
		print("[relic_slate] FATAL: never reached PLAYER_TURN"); _finish(1); return
	# Let the staggered opening hand deal finish before touching _hand. The deal
	# lands card-by-card (~80ms apart) after the intro banner clears, so a fixed
	# wait races it — poll until the count is non-zero AND stable across two ticks.
	var deal_n := -1
	for _dtick in 30:
		await create_timer(0.4).timeout
		if not is_instance_valid(combat):
			break
		var dn: int = combat._hand.size()
		if dn > 0 and dn == deal_n and combat.phase == combat.Phase.PLAYER_TURN:
			break
		deal_n = dn

	# Combat caches the relic set at fight start (_relic_set) — every live
	# mutation below must rebuild it or _has_relic keeps the stale snapshot.
	# Sharpened Pitchforks: requested 1/1 tokens muster as 2/1.
	RS.relics.append("the_family")
	combat._rebuild_relic_cache()
	combat.summon_token(1, 1, 0, false, 1)   # player back-left
	var pf = combat._player_back[0]
	_ck("Pitchforks: 1/1 token musters as 2/1",
		pf != null and pf.current_atk == 2 and pf.current_hp == 1,
		"got %s" % ("null" if pf == null else "%d/%d" % [pf.current_atk, pf.current_hp]))
	RS.relics.erase("the_family")
	combat._rebuild_relic_cache()

	# Sellsword's Retainer: 150+ gold fields a 3/3 in the back row.
	RS.relics.append("sellswords_retainer")
	combat._rebuild_relic_cache()
	RS.gold = 200
	combat._apply_combat_start_relics()
	var sw = null
	for c in combat._all_player_creatures():
		if String(c.card_data.get("name", "")) == "Sellsword":
			sw = c
	_ck("Sellsword hired at 200 gold (3/3)",
		sw != null and sw.current_atk == 3 and sw.current_hp == 3)
	RS.relics.erase("sellswords_retainer")
	combat._rebuild_relic_cache()

	# Man-Trap: an enemy dying on player thorns splashes its same-row neighbors.
	# Clear the enemy board first so the test tokens land on known-empty lanes —
	# the goblin_scouts opener otherwise occupies back lanes and the summons
	# collide (falling to the front row, so _enemy_back[n] reads a stale goblin).
	for c in combat._all_enemy_creatures():
		c.take_damage(999)
	RS.relics.append("briar_amulet")
	combat._rebuild_relic_cache()
	combat.summon_token(1, 1, 1, true, 1)    # doomed striker, enemy back lane 1
	combat.summon_token(3, 3, 2, true, 1)    # its neighbor, enemy back lane 2
	combat.summon_token(1, 5, 3, false, 0, {}, "Thornwall", ["thorns"])
	var striker = combat._enemy_back[1]
	var neighbor = combat._enemy_back[2]
	var wall = combat._player_field[3]
	if striker != null and neighbor != null and wall != null \
			and striker.current_atk == 1 and neighbor.current_hp == 3:
		combat._apply_thorns(wall, striker, true)
		_ck("Man-Trap: thorns kill splashes the neighbor for 2",
			is_instance_valid(neighbor) and neighbor.current_hp == 1,
			"neighbor hp %s" % ("dead" if not is_instance_valid(neighbor) else str(neighbor.current_hp)))
	else:
		_ck("Man-Trap: test tokens landed on clean lanes", false,
			"striker=%s neighbor=%s wall=%s" % [striker, neighbor, wall])
	RS.relics.erase("briar_amulet")
	combat._rebuild_relic_cache()

	# Poisoned Rations: the FIRST tagged reinforcement arrives dead; later ones live.
	RS.relics.append("poisoned_rations")
	combat._rebuild_relic_cache()
	var rf_data: Dictionary = CDB.get_card_data("goblin").duplicate(true)
	if rf_data.is_empty():
		rf_data = {"id": "probe_rf", "name": "Probe", "type": "creature",
			"cost": 1, "atk": 2, "hp": 3, "keywords": [], "rarity": "enemy", "desc": ""}
	rf_data["is_reinforcement"] = true
	var rf_lane := -1
	for i in 4:
		if combat._enemy_field[i] == null:
			rf_lane = i
			break
	if rf_lane >= 0:
		combat._place_enemy_card(rf_data.duplicate(true), rf_lane, 0)
		var first = combat._enemy_field[rf_lane]
		_ck("Poisoned Rations: first reinforcement arrives dead",
			combat._poisoned_rations_fired and (first == null or first.current_hp <= 0))
		var rf_lane2 := -1
		for i in 4:
			if combat._enemy_field[i] == null:
				rf_lane2 = i
				break
		if rf_lane2 >= 0:
			combat._place_enemy_card(rf_data.duplicate(true), rf_lane2, 0)
			var second = combat._enemy_field[rf_lane2]
			_ck("Poisoned Rations: second reinforcement lives",
				second != null and second.current_hp > 0)
	else:
		_ck("Poisoned Rations: no empty enemy lane to test", false)
	RS.relics.erase("poisoned_rations")
	combat._rebuild_relic_cache()

	# Dregs: drinking throws the bottle — 2 damage to a random enemy. Clear the
	# field down to one fat target so the random pick is deterministic. Deaths
	# defer (clash contract), so purge the corpses before summoning the lone
	# target — otherwise the random throw can splash a dead-but-uncleaned body.
	for c in combat._all_enemy_creatures():
		c.take_damage(999)
	combat._cleanup_dead()
	await create_timer(0.1).timeout
	combat.summon_token(1, 10, 0, true, 0)
	var fat = combat._enemy_field[0]
	RS.relics.append("dregs")
	combat._rebuild_relic_cache()
	combat._dregs_bottle_throw()
	_ck("Dregs: bottle hits the only enemy for 2",
		fat != null and fat.current_hp == 8, "hp %s" % ("null" if fat == null else str(fat.current_hp)))
	RS.relics.erase("dregs")
	combat._rebuild_relic_cache()

	# Deserter's Toll: the first marked discard strikes for its Command cost.
	# Force a known costed card into hand — in this headless probe the staggered
	# opening deal may not have populated _hand yet, and every prior test summons
	# tokens rather than drawing. fat (the Dregs token, hp 8) is the lone enemy,
	# so the relic's random pick is deterministic.
	RS.relics.append("deserters_toll")
	combat._rebuild_relic_cache()
	var toll_card = null
	for hc in combat._hand:
		if int(hc.card_data.get("cost", 0)) > 0 and not CDB.is_curse(hc.card_id):
			toll_card = hc
			break
	if toll_card == null:
		for di in RS.deck.size():
			var cid: String = RS.deck[di]
			var cd: Dictionary = CDB.get_card_data(cid)
			if int(cd.get("cost", 0)) > 0 and not CDB.is_curse(cid):
				combat._draw_card(combat._pile_entry(cid, RS.deck_uids[di]))
				break
		for hc in combat._hand:
			if int(hc.card_data.get("cost", 0)) > 0 and not CDB.is_curse(hc.card_id):
				toll_card = hc
				break
	if toll_card != null and fat != null and is_instance_valid(fat):
		var cost: int = int(toll_card.card_data.get("cost", 0))
		var hp_before: int = fat.current_hp
		toll_card.marked_for_discard = true
		combat._flush_marked_discards()
		_ck("Deserter's Toll: discard strikes for its cost (%d)" % cost,
			fat.current_hp == hp_before - cost,
			"hp %d -> %d" % [hp_before, fat.current_hp])
	else:
		_ck("Deserter's Toll: could not stage a costed card (hand size %d)" % combat._hand.size(),
			false)
	RS.relics.erase("deserters_toll")
	combat._rebuild_relic_cache()

	# COUNTER_RELICS no longer carries the cut counters.
	_ck("COUNTER_RELICS purged of sundial/hourglass",
		not ("sundial" in combat.COUNTER_RELICS) and not ("hourglass_sigil" in combat.COUNTER_RELICS))

	print("[relic_slate] done: %d passed, %d failed" % [_pass, _fail])
	_finish(0 if _fail == 0 else 1)
