extends SceneTree
## Focused logic probe for the 2026-07-16 relic/reward structural pass.
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relic_rework.gd

var RS: Node
var RDB: Node
var CDB: Node
var _ran := false
var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _one(id: String) -> Array[String]:
	return [id]


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	RS = root.get_node_or_null("RunState")
	RDB = root.get_node_or_null("RelicDB")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or RDB == null or CDB == null:
		print("[relic-rework] FATAL: autoloads missing")
		quit(1)
		return true
	print("[relic-rework] start")
	RS.start_new_run("stalwart", 0, 761607)
	_test_slate()
	_test_reward_classes()
	_test_offer_gates()
	_test_boss_pool()
	_test_map_spoils()
	_test_veterancy_thresholds()
	_test_changed_scripts_compile()
	_test_damage_spell_contract()
	_test_pandora_floor()
	print("[relic-rework] ALL PASS" if _fails == 0 \
		else "[relic-rework] %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _test_slate() -> void:
	print("— final slate")
	for id in ["heads_on_pikes", "powder_horn", "familiars_quill", "head_money",
			"old_meg", "portcullis", "second_rank", "sextons_spade",
			"forlorn_hope", "cerecloth", "drill_book", "articles_of_war"]:
		_check(RDB.RELICS.has(id) and not bool(RDB.RELICS[id].get("retired", false)),
			"%s is live" % id)
	_check(String(RDB.RELICS.worn_spellbook.effect) == "repeat_spellbook",
		"Worn Spellbook is the repeat engine")
	_check(String(RDB.RELICS.du_vu_doll.effect) == "curse_poppet",
		"Maledetto Poppet is the Curse intercept")
	_check(not RDB.RELICS.has("slip_the_leash"), "Slip the Leash remains held")


func _test_reward_classes() -> void:
	print("— reward classes")
	var foundation: Array = RDB.roll_foundation_relics(1, RS.relics, RS.current_hero_id)
	_check(foundation.size() == 1 and foundation[0] in RDB.FOUNDATION_RELICS,
		"War Chest returns one Foundation relic")
	var field: Array = RDB.roll_field_relics(2, RS.relics, RS.current_hero_id)
	_check(field.size() == 2, "General returns two Field choices")
	_check(field[0] in RDB.FOUNDATION_RELICS,
		"first non-signature Field offer contains a Foundation relic")
	var campaign: Array = RDB.roll_campaign_relics(1, RS.relics, RS.current_hero_id)
	_check(campaign.size() == 1 \
		and String(RDB.RELICS[campaign[0]].tier) == "utility",
		"shop Campaign slot reaches the utility tier")


func _test_offer_gates() -> void:
	print("— offer gates")
	_check(RDB.filter_pool_for_run(_one("heads_on_pikes"), RS.current_hero_id,
		RS.relics).is_empty(), "Heads on Pikes hidden before a General")
	RS.generals_broken_run = 1
	_check(RDB.filter_pool_for_run(_one("heads_on_pikes"), RS.current_hero_id,
		RS.relics) == ["heads_on_pikes"], "Heads on Pikes opens after a General")
	_check(RDB.filter_pool_for_run(_one("cerecloth"), RS.current_hero_id,
		RS.relics).is_empty(), "Cerecloth hidden before the Roll has a name")
	RS.fallen.append({"id": "levy_spearman", "name": "A Name"})
	_check(RDB.filter_pool_for_run(_one("cerecloth"), RS.current_hero_id,
		RS.relics) == ["cerecloth"], "Cerecloth opens after a fall")
	_check(RDB.filter_pool_for_run(_one("du_vu_doll"), RS.current_hero_id,
		RS.relics).is_empty(), "Poppet hidden without a Curse")
	RS.add_card("curse")
	_check(RDB.filter_pool_for_run(_one("du_vu_doll"), RS.current_hero_id,
		RS.relics) == ["du_vu_doll"], "Poppet opens with a Curse")
	for id in ["swift_boots", "glass_cannon", "hexagonal_shield", "last_breath",
			"cavalry_sigil", "bag_of_marbles", "iron_legion", "mana_pearl",
			"linked_banner", "doom_herald"]:
		_check(RDB.filter_pool_for_run(_one(id), RS.current_hero_id,
			RS.relics).is_empty(), "%s is out of rewards" % id)


func _test_boss_pool() -> void:
	print("— positive boss pool")
	var bosses: Array = RDB.roll_boss_relics(RS.relics, RS.current_hero_id)
	_check(bosses.size() == 3, "boss reward returns three choices")
	for id in bosses:
		var d: Dictionary = RDB.RELICS[id]
		_check(not bool(d.get("retired", false)) and String(d.get("downside", "")) == "",
			"%s has no downside" % id)


func _test_map_spoils() -> void:
	print("— map spoils")
	for ai in RS.map_data.size():
		var reliquaries := 0
		var arsenals := 0
		for row in RS.map_data[ai]:
			for node in row:
				if String(node.get("type", "")) == "treasure":
					reliquaries += 1
				elif String(node.get("type", "")) == "arsenal":
					arsenals += 1
		_check(reliquaries == 1 and arsenals == 1,
			"act %d has one Reliquary and one Arsenal" % (ai + 1))


## THE LADDER MOVED ON 2026-07-30 AND THIS TEST DID NOT (fixed 2026-08-05).
##
## The war school used to sit at 10 kills. It was pulled FORWARD onto the
## epithet's rung because most runs never reached it, and the move was made by
## turning `veteran_school_kills()` into a literal alias of
## `veteran_epithet_kills()` — one edit instead of thirteen call sites. The
## 10 (7 with Drill Book) it vacated went to the new `veteran_doctrine_kills()`.
##
## So `veteran_school_kills() == 10` has been false for a week, and both
## assertions here have been red ever since — testing an old design rather than
## a broken one. Re-pointed at the live three-rung ladder, and now covering the
## doctrine rung the rework introduced, which nothing was checking at all.
func _test_veterancy_thresholds() -> void:
	print("— Drill Book")
	_check(RS.veteran_epithet_kills() == 3 and RS.veteran_school_kills() == 3,
		"base: epithet and war school share the 3-kill rung")
	_check(RS.veteran_doctrine_kills() == 10,
		"base: the tribe doctrine sits at 10 kills")
	RS.add_relic("drill_book")
	_check(RS.veteran_epithet_kills() == 2 and RS.veteran_school_kills() == 2,
		"Drill Book pulls the epithet/school rung to 2")
	_check(RS.veteran_doctrine_kills() == 7,
		"Drill Book shortens the WHOLE ladder — doctrine to 7, not just its front half")


func _test_damage_spell_contract() -> void:
	print("— damage-spell contract")
	var combat = load("res://scripts/scenes/Combat.gd").new()
	var damage_cards := {
		"hex": "hex", "holy_smite": "holy_smite", "cataclysm": "cataclysm",
		"fuel_the_pyre": "fuel_the_pyre", "rout": "overwhelming_force",
		"sappers_charge": "sappers_charge", "wolf_pits": "wolf_pits",
	}
	for label in damage_cards:
		_check(combat._is_relic_damage_spell(CDB.get_card_data(damage_cards[label])),
			"%s receives damage-relic bonuses" % label)
	combat.free()


func _test_changed_scripts_compile() -> void:
	print("— changed scene scripts")
	for path in [
			"res://scripts/scenes/Combat.gd", "res://scripts/scenes/Reward.gd",
			"res://scripts/scenes/Treasure.gd", "res://scripts/scenes/Shop.gd",
			"res://scripts/scenes/MapView.gd", "res://scripts/scenes/MapTerrain.gd",
			"res://scripts/scenes/MainMenu.gd", "res://scripts/scenes/GameOver.gd",
			"res://scripts/Card2D.gd", "res://scripts/GameTheme.gd",
	]:
		var script: Script = load(path)
		_check(script != null and script.can_instantiate(),
			"%s compiles" % path.get_file())


func _test_pandora_floor() -> void:
	print("— positive fallback")
	RS.deck.assign(["slash"])
	RS.deck_uids.assign([991607])
	RS.card_upgrades.clear()
	RS._pandoras_box_transform()
	var added: Dictionary = CDB.get_card_data(RS.deck.back())
	_check(RS.deck.size() == 2 and String(added.get("type", "")) == "creature" \
		and String(added.get("rarity", "")) == "rare",
		"Conjurer's Coffer is positive after all starters are gone")
