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
		"desc": "A friendly creature gains +3 ATK this turn.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "buff_atk", "color": Color(0.95, 0.45, 0.10)},
	"mana_surge": {
		"id": "mana_surge", "name": "Rallying Horn",
		"desc": "Gain 2 Command this turn.",
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
		"desc": "Summon the last friendly creature to die as a 1/1 in a random empty lane. Keeps its keywords.",
		"usable_in": "combat", "targeting": "none",
		"effect": "revive_last_dead", "color": Color(1.00, 0.70, 0.25)},

	# ── Combat swingers (added) ──────────────────────────────────────────────
	# Each is built to visibly tilt a fight: a buff that snowballs, a burst that
	# clears a wing, a synergy payoff, a panic button. Targeted ones reuse the
	# potion-targeting flow; the rest resolve on click.
	"war_paint": {
		"id": "war_paint", "name": "War Paint",
		"desc": "A friendly creature gains Rampage 2 and +1 ATK for the rest of the fight. Every kill makes it bigger.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "grant_rampage", "color": Color(0.85, 0.30, 0.18)},
	"vampiric_draught": {
		"id": "vampiric_draught", "name": "Vampiric Draught",
		"desc": "A friendly creature gains Lifelink 2 for the fight. Heal 4 HP now.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "grant_lifelink", "color": Color(0.55, 0.10, 0.20)},
	"chain_flask": {
		"id": "chain_flask", "name": "Chain-Lightning Flask",
		"desc": "Loose a bolt that arcs 4 times, dealing 2 damage to a random enemy creature each jump.",
		"usable_in": "combat", "targeting": "none",
		"effect": "chain_lightning", "color": Color(0.55, 0.80, 1.00)},
	"doomsday_draught": {
		"id": "doomsday_draught", "name": "Doomsday Draught",
		"desc": "Every friendly Doom creature detonates right now. No more waiting for the clock.",
		"usable_in": "combat", "targeting": "none",
		"effect": "detonate_doom_all", "color": Color(1.00, 0.32, 0.16)},
	"aegis_brew": {
		"id": "aegis_brew", "name": "Aegis Brew",
		"desc": "Raise a shield wall: every friendly creature gains Shield, blocking the next hit it takes.",
		"usable_in": "combat", "targeting": "none",
		"effect": "shield_wall", "color": Color(0.70, 0.85, 1.00)},
	"conscript_brew": {
		"id": "conscript_brew", "name": "Conscription Brew",
		"desc": "Two 3/3 Recruits muster into your empty lanes. Bodies on demand.",
		"usable_in": "combat", "targeting": "none",
		"effect": "summon_recruits", "color": Color(0.65, 0.55, 0.40)},
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
