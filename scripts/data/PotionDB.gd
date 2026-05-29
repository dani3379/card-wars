extends Node
## PotionDB.gd — potion definitions.
##
## Each potion entry:
##   id          unique string id
##   name        display name
##   desc        tooltip text
##   usable_in   "map" | "combat" | "both"
##   targeting   "none" | "friendly_creature" | "enemy_creature" | "any_creature"
##   effect      effect id string (matched by MapView._use_map_potion /
##               Combat._use_combat_potion)
##   color       tint for the potion icon
##
## Used by:
##   - RunState.potions: Array[String] of potion ids
##   - Shop.gd to roll a random potion to sell
##   - MapView.gd to render and apply heal-type potions outside combat
##   - Combat.gd to render the potion bar and apply combat-only effects

const POTIONS: Dictionary = {
	"healing": {
		"id": "healing", "name": "Healing Potion",
		"desc": "Heal 8 HP.",
		"usable_in": "both", "targeting": "none",
		"effect": "heal_hp", "color": Color(0.85, 0.30, 0.30)},
	"bottled_fury": {
		"id": "bottled_fury", "name": "Bottled Fury",
		"desc": "Target friendly creature gains +3 ATK this turn.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "buff_atk", "color": Color(0.95, 0.45, 0.10)},
	"mana_surge": {
		"id": "mana_surge", "name": "Mana Surge",
		"desc": "Gain 2 mana this turn.",
		"usable_in": "combat", "targeting": "none",
		"effect": "gain_mana", "color": Color(0.30, 0.55, 0.95)},
	"inferno_vial": {
		"id": "inferno_vial", "name": "Inferno Vial",
		"desc": "Deal 3 damage to all enemy creatures.",
		"usable_in": "combat", "targeting": "none",
		"effect": "aoe_enemies", "color": Color(0.90, 0.25, 0.10)},
	"insight_tonic": {
		"id": "insight_tonic", "name": "Insight Tonic",
		"desc": "Draw 3 cards.",
		"usable_in": "combat", "targeting": "none",
		"effect": "draw", "color": Color(0.80, 0.65, 0.95)},
	"phoenix_brew": {
		"id": "phoenix_brew", "name": "Phoenix Brew",
		"desc": "Summon the last friendly creature to die as a 1/1 in a random empty lane (keeps its keywords).",
		"usable_in": "combat", "targeting": "none",
		"effect": "revive_last_dead", "color": Color(1.00, 0.70, 0.25)},
}


static func get_potion(id: String) -> Dictionary:
	if POTIONS.has(id):
		return POTIONS[id]
	push_warning("PotionDB: unknown potion id '%s'" % id)
	return {}


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for id in POTIONS.keys():
		result.append(id)
	return result


# Weighted roll for shop / event grants. Healing stays the most common (it's
# the safety-net potion); the combat-only ones are rarer rewards.
static func roll_random_potion() -> String:
	var weighted: Array[String] = []
	for id in POTIONS.keys():
		var weight = 3 if id == "healing" else 1
		for _i in range(weight):
			weighted.append(id)
	return weighted[randi() % weighted.size()]


static func icon_for(id: String) -> Texture2D:
	# Convention: assets/icons/potions/<id>.png. Falls back to the generic
	# painted HUD potion if no per-type art exists yet.
	var path := "res://assets/icons/potions/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return GameTheme.tex_hud_potion
