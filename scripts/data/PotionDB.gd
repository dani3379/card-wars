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
	# Reworked 2026-07-04 (was Bottled Fury, +3 ATK one creature one turn — a
	# no-decision number). Same id so mid-run saves migrate silently; the lane
	# game's only column-targeting effect.
	"bottled_fury": {
		"id": "bottled_fury", "name": "Sapper's Charge",
		"desc": "Deal 4 damage to an enemy creature and the other creature in its lane.",
		"usable_in": "combat", "targeting": "enemy_creature",
		"effect": "column_strike", "color": Color(0.95, 0.62, 0.28)},
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
		"desc": "Summon the last friendly creature to die as a 1/1 in your foremost empty lane. Keeps its keywords.",
		"usable_in": "combat", "targeting": "none",
		"effect": "revive_last_dead", "color": Color(1.00, 0.70, 0.25)},

	# ── Combat swingers (added) ──────────────────────────────────────────────
	# Each is built to visibly tilt a fight: a buff that snowballs, a burst that
	# clears a wing, a synergy payoff, a panic button. Targeted ones reuse the
	# potion-targeting flow; the rest resolve on click.
	"war_paint": {
		"id": "war_paint", "name": "War Paint",
		"desc": "A friendly creature gains Rampage and +1 ATK this fight.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "grant_rampage", "color": Color(0.85, 0.30, 0.18)},
	"vampiric_draught": {
		"id": "vampiric_draught", "name": "Vampiric Draught",
		"desc": "A friendly creature heals you 2 whenever it deals battle damage this fight. Heal 4 HP now.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "grant_lifelink", "color": Color(0.82, 0.24, 0.32)},
	"chain_flask": {
		"id": "chain_flask", "name": "Chain-Lightning Flask",
		"desc": "A bolt arcs 4 times, dealing 2 damage to a random enemy creature each jump.",
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
		"effect": "summon_recruits", "color": Color(0.82, 0.70, 0.48)},

	# ── System-benders (2026-07-04) ──────────────────────────────────────────
	# Potions that touch Burning Meadow's own machinery — the sacrifice-hook
	# web and the branded curse pack — instead of generic card-game verbs.
	"butchers_dram": {
		"id": "butchers_dram", "name": "Butcher's Dram",
		"desc": "Sacrifice a friendly creature: gain 3 Command this turn.",
		"usable_in": "combat", "targeting": "friendly_creature",
		"effect": "sacrifice_for_command", "color": Color(0.88, 0.36, 0.30)},
	"grave_diggers_nip": {
		"id": "grave_diggers_nip", "name": "Grave-Digger's Nip",
		"desc": "Bury every Curse in your hand. Draw a card for each one buried.",
		"usable_in": "combat", "targeting": "none",
		"effect": "purge_hand_curses", "color": Color(0.62, 0.78, 0.52)},
}


static var _icon_cache: Dictionary = {}
static var _painted_icon_cache: Dictionary = {}


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


# Weighted roll for shop / event / fight-spoils grants. Healing stays the most
# common (it's the safety-net potion); archetype potions only roll for decks
# that can actually use them (no dead rewards).
static func roll_random_potion() -> String:
	var weighted: Array[String] = []
	for id in POTIONS.keys():
		if not _roll_allowed(id):
			continue
		var weight = 3 if id == "healing" else 1
		for _i in range(weight):
			weighted.append(id)
	return weighted[randi() % weighted.size()]


# Archetype gates: a Doomsday Draught in a doomless deck (or a curse-burier
# with a clean deck) is a dead slot — the same state-gating the event pool
# uses. Healing is always allowed, so the pool can never come up empty.
static func _roll_allowed(id: String) -> bool:
	match id:
		"doomsday_draught":
			for cid in RunState.deck:
				if "doom" in CardDB.get_card_data(cid).get("keywords", []):
					return true
			return false
		"grave_diggers_nip":
			var curses := 0
			for cid in RunState.deck:
				if CardDB.is_curse(cid):
					curses += 1
			return curses >= 2
	return true


static func icon_for(id: String) -> Texture2D:
	# Convention: assets/icons/potions/<id>.{png,svg} — PNG wins so painted
	# art auto-replaces the silhouette once it lands (same deal as RelicDB).
	# The SVGs are the white game-icons kit: render them tinted by the
	# potion's `color` (callers check is_painted_icon to decide).
	if _icon_cache.has(id):
		return _icon_cache[id]
	var png_path := "res://assets/icons/potions/%s.png" % id
	if ResourceLoader.exists(png_path):
		_icon_cache[id] = load(png_path) as Texture2D
		return _icon_cache[id]
	var svg_path := "res://assets/icons/potions/%s.svg" % id
	if ResourceLoader.exists(svg_path):
		_icon_cache[id] = load(svg_path) as Texture2D
		return _icon_cache[id]
	_icon_cache[id] = GameTheme.tex_hud_potion
	return _icon_cache[id]


static func is_painted_icon(id: String) -> bool:
	if not _painted_icon_cache.has(id):
		_painted_icon_cache[id] = ResourceLoader.exists("res://assets/icons/potions/%s.png" % id)
	return bool(_painted_icon_cache[id])
