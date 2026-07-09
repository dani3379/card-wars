extends Node
## EncounterDB.gd — Premade fight lineups from the master design document.
## Each encounter has an ordered creature deck, reinforcement, HP, and optional passive.

var _enc_counter: int = 0


func get_encounter(id: String) -> Dictionary:
	if ENCOUNTERS.has(id):
		return ENCOUNTERS[id]
	push_warning("EncounterDB: unknown encounter '%s'" % id)
	return {}


func get_ids_for(act: int, type: String, faction: String = "") -> Array:
	# Optional faction filter (Successor Wars): "" keeps the legacy behavior,
	# a faction id narrows the pool to that kingdom's fights.
	# Rival-lord kits (rival_*) and throne amalgams (amalgam_*) never enter
	# random pools — rivals are placed by direct lookup in
	# RunState._boss_encounter_for_act, amalgams by RunState.enter_finale.
	var result: Array = []
	for id in ENCOUNTERS:
		if String(id).begins_with("rival_") or String(id).begins_with("amalgam_"):
			continue
		var enc = ENCOUNTERS[id]
		if enc.act == act and enc.type == type:
			if faction != "" and String(enc.get("faction", "")) != faction:
				continue
			result.append(id)
	return result


## Successor Wars: the fight pool for one kingdom act. The faction's own-act
## fights come first; thin pools borrow the faction's fights from neighboring
## acts (consumers rescale them via get_face_hp / build_enemy_deck's
## target_act). Elite pools short even after borrowing pull the faction's
## BOSSES as capital-stronghold stand-ins (the worksheet's demotion: rival
## lords took the act-boss slot, so the old bosses become elite-plus fights
## inside their kingdom). A last-resort top-up from the unfiltered act pool
## keeps a kingdom playable while a faction's bench is still being authored
## (lanternhall, per the worksheet gap list).
func get_kingdom_pool(act: int, type: String, faction: String) -> Array:
	if faction == "":
		return get_ids_for(act, type)
	var pool: Array = get_ids_for(act, type, faction)
	var need: int = 4 if type == "combat" else 2
	for dist in [1, 2]:
		if pool.size() >= need:
			return pool
		for other_act in [act - dist, act + dist]:
			if other_act < 1 or other_act > 3:
				continue
			for id in get_ids_for(other_act, type, faction):
				if not pool.has(id):
					pool.append(id)
	if type == "elite" and pool.size() < need:
		for boss_act in [act, act - 1, act + 1, act - 2, act + 2]:
			if boss_act < 1 or boss_act > 3 or pool.size() >= need:
				continue
			for id in get_ids_for(boss_act, "boss", faction):
				if not pool.has(id):
					pool.append(id)
	if pool.size() < 2:
		for id in get_ids_for(act, type):
			if not pool.has(id):
				pool.append(id)
	return pool


## Phase 2.5 — terrain affinity (flavour-only weighting, §15.1 #9). How well
## an authored kit fits the ground its hold sits on: woods favors ambush
## kits, the pass favors armor, ash favors doom/burn, meadow favors the
## lightest deck in the deal. Scores are only ever compared WITHIN one
## terrain (RunState.apply_terrain_redeal assigns one terrain at a time),
## so the scales don't need to agree across terrains.
const TERRAIN_KW := {
	"woods": ["swift", "piercing"],
	"pass": ["armored", "thorns", "shield", "last_stand", "formation"],
	"ash": ["doom", "rampage", "overrun"],
}
var _terrain_aff_cache: Dictionary = {}


## Total statline + body count of an authored kit — the "how heavy is this
## deal" read used by the meadow affinity AND the road's escalation sort
## (light kits land at the landing, heavy kits near the keep).
func kit_weight(enc_id: String) -> int:
	var enc: Dictionary = ENCOUNTERS.get(enc_id, {})
	var deck: Array = enc.get("deck", [])
	var stats := 0
	for c in deck:
		stats += int(c.get("atk", 0)) + int(c.get("hp", 0))
	return stats + deck.size() * 4


func terrain_affinity(enc_id: String, terrain: String) -> int:
	var key := enc_id + "/" + terrain
	if _terrain_aff_cache.has(key):
		return _terrain_aff_cache[key]
	var enc: Dictionary = ENCOUNTERS.get(enc_id, {})
	var deck: Array = enc.get("deck", [])
	var score := 0
	if terrain == "meadow":
		# Lighter deal = better fit: open country carries the act's easy road.
		score = 200 - kit_weight(enc_id)
	else:
		var kws: Array = TERRAIN_KW.get(terrain, [])
		for c in deck:
			for kw in c.get("kw", []):
				if kw in kws:
					score += 3   # one bump per body, not per keyword
					break
		# A reinforcement that fits keeps the theme alive late — half weight.
		for kw in enc.get("reinforcement", {}).get("kw", []):
			if kw in kws:
				score += 1
				break
	_terrain_aff_cache[key] = score
	return score


# Face-HP norms per act band, read off the live ENCOUNTERS data (A1 combats
# run 9–13, elites 18, bosses 21–23; A2 15–18 / 23–25 / 29–31; A3 19–22 /
# 24–29 / 32–36). Used to rescale fights placed outside their authored act —
# index = act - 1.
const ACT_FACE_HP_NORM: Dictionary = {
	"combat": [11.4, 16.4, 20.7],
	"elite": [18.0, 24.0, 26.8],
	"boss": [22.0, 30.0, 34.0],
}


## Face HP for an encounter as fought at `target_act` / `target_type` (the
## map slot it actually landed in). Same act + type = the authored value.
## Cross-act borrows and boss→elite demotions scale by the band norms above.
## Phase thresholds stay absolute — phases just fire proportionally earlier
## or later, the same drift ascension HP scaling already ships with.
func get_face_hp(encounter_id: String, target_act: int, target_type: String = "") -> int:
	var enc = get_encounter(encounter_id)
	if enc.is_empty():
		return 0
	var hp: int = int(enc.hp)
	var from_act: int = clampi(int(enc.get("act", 1)), 1, 3)
	var from_type: String = String(enc.get("type", "combat"))
	var to_type: String = target_type if ACT_FACE_HP_NORM.has(target_type) else from_type
	if target_act < 1 or target_act > 3:
		return hp
	if from_act == target_act and to_type == from_type:
		return hp
	var from_norm: float = ACT_FACE_HP_NORM[from_type][from_act - 1]
	var to_norm: float = ACT_FACE_HP_NORM[to_type][target_act - 1]
	return maxi(4, int(round(hp * to_norm / from_norm)))


## ±1 ATK / ±1 HP per act step for creatures fighting outside their authored
## band. 0-ATK utility bodies stay 0; HP floors at 1. First-cut tuning — the
## per-faction content pass will replace the worst offenders with hand-tuned
## variants (worksheet §3: "re-level before authoring net-new").
func _act_scale_creature(data: Dictionary, delta: int) -> Dictionary:
	if delta == 0:
		return data
	if int(data.get("atk", 0)) > 0:
		data.atk = maxi(1, int(data.atk) + delta)
	data.hp = maxi(1, int(data.get("hp", 1)) + delta)
	return data


func make_card_data(creature: Dictionary) -> Dictionary:
	_enc_counter += 1
	var safe_name = creature.name.to_lower().replace(" ", "_").replace("'", "")
	var data: Dictionary = {
		"id": "enc_%s_%d" % [safe_name, _enc_counter],
		"name": creature.name,
		"type": "creature",
		"cost": 0,
		"atk": creature.atk,
		"hp": creature.hp,
		"rarity": "enemy",
		"keywords": creature.get("kw", []).duplicate(),
		"desc": "",
	}
	for key in ["on_enter", "on_death", "on_play", "adj_buff"]:
		if creature.has(key):
			data[key] = creature[key].duplicate(true)
	if creature.has("wither"):
		data["wither"] = creature.wither
	if bool(creature.get("sniper", false)) and not data["keywords"].has("sniper"):
		data["keywords"].append("sniper")
	# Doom bombs: the countdown rides the card data (Card2D seeds doom_counter
	# from card_data.doom; Combat reads doom_damage on detonation). Without
	# this passthrough a deck-authored Cinder lands at Doom 0 and blows on its
	# first tick instead of granting its full fuse.
	if creature.has("doom"):
		data["doom"] = int(creature.doom)
	if creature.has("doom_damage"):
		data["doom_damage"] = int(creature.doom_damage)
	if creature.has("intents"):
		data["intents"] = creature.intents.duplicate()
	if creature.has("ability"):
		data["ability"] = creature.ability.duplicate(true)
	return data


func build_enemy_deck(encounter_id: String, target_act: int = 0) -> Array[Dictionary]:
	var enc = get_encounter(encounter_id)
	if enc.is_empty():
		return []
	# Composition variants: if the encounter defines a `deck_variants` array of
	# alternate deck lists, pick one at random. The author can also keep the
	# base `deck` and add `deck_variants` for additional flavors — we treat the
	# base as one of the options so existing encounters get more variety for
	# free as soon as a single variant is added.
	var source_deck: Array = enc.deck
	var variants: Array = enc.get("deck_variants", [])
	if variants.size() > 0:
		var options: Array = [enc.deck]
		for v in variants:
			options.append(v)
		source_deck = options[randi() % options.size()]
	# Cross-act borrow (Successor Wars): a fight placed outside its authored
	# act scales each body by the act delta. target_act 0 = authored act.
	var delta: int = 0
	if target_act >= 1 and target_act <= 3:
		delta = target_act - clampi(int(enc.get("act", target_act)), 1, 3)
	var deck: Array[Dictionary] = []
	for creature in source_deck:
		deck.append(_act_scale_creature(make_card_data(creature), delta))
	return deck


func get_reinforcement(encounter_id: String, target_act: int = 0) -> Dictionary:
	var enc = get_encounter(encounter_id)
	if enc.is_empty():
		return {}
	var delta: int = 0
	if target_act >= 1 and target_act <= 3:
		delta = target_act - clampi(int(enc.get("act", target_act)), 1, 3)
	# Reinforcement pool: same pattern as deck variants. If the encounter has
	# a `reinforcement_pool` list, pick one at random; otherwise fall back to
	# the single `reinforcement` field. Empty pool = stick with base.
	var pool: Array = enc.get("reinforcement_pool", [])
	if pool.size() > 0:
		var options: Array = [enc.reinforcement]
		for p in pool:
			options.append(p)
		return _act_scale_creature(make_card_data(options[randi() % options.size()]), delta)
	return _act_scale_creature(make_card_data(enc.reinforcement), delta)


func get_boss_phases(encounter_id: String) -> Array:
	if BOSS_PHASES.has(encounter_id):
		return BOSS_PHASES[encounter_id]
	return []


func get_reactive_passive(encounter_id: String) -> Dictionary:
	if REACTIVE_PASSIVES.has(encounter_id):
		return REACTIVE_PASSIVES[encounter_id]
	return {}


func get_encounter_script(encounter_id: String) -> Array:
	## Returns scripted-event entries for an encounter, in order.
	## Each entry: {round: int, msg: String, event: String, params...}
	## Combat.gd plays them at start of the matching round.
	if ENCOUNTER_SCRIPTS.has(encounter_id):
		return ENCOUNTER_SCRIPTS[encounter_id]
	return []


# Boss phase definitions: each phase has threshold, passive_id, passive_desc,
# and an optional transition effect.
const BOSS_PHASES: Dictionary = {
	"amalgam_acolyte": [
		{"threshold": 27, "passive_id": "throne_husks",
			"passive_desc": "Start of each round: summon a 2/2 Swift creature in an empty enemy lane."},
		{"threshold": 14, "passive_id": "formation_drill",
			"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1.",
			"transition_msg": "THE WALL YOU BURNED CLOSES RANKS!",
			"transition_effect": {"type": "summon_multiple", "name": "Shieldbearer",
				"atk": 2, "hp": 4, "count": 2, "kw": ["armored"]}},
		{"threshold": 0, "passive_id": "doom_bell",
			"passive_desc": "Every other round the throne tolls: a ticking Cinder drops in, and other enemies gain +1 ATK while it ticks.",
			"transition_msg": "THE EVERFLAME ANSWERS THE THRONE!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"amalgam_raider": [
		{"threshold": 27, "passive_id": "formation_drill",
			"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1."},
		{"threshold": 14, "passive_id": "crypt_ghost",
			"passive_desc": "When an enemy creature dies: summon a 1/1 Swift Ghost in a random empty enemy lane.",
			"transition_msg": "EVERY KINGDOM'S DEAD RIDE WITH HIM!",
			"transition_effect": {"type": "summon_multiple", "name": "Repossessed",
				"atk": 2, "hp": 2, "count": 2, "kw": ["last_stand"]}},
		{"threshold": 0, "passive_id": "doom_bell",
			"passive_desc": "Every other round the throne tolls: a ticking Cinder drops in, and other enemies gain +1 ATK while it ticks.",
			"transition_msg": "THE LAST KINGDOM BURNS WITH HIM!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"amalgam_stalwart": [
		{"threshold": 27, "passive_id": "formation_drill",
			"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1."},
		{"threshold": 14, "passive_id": "void_exile",
			"passive_desc": "Start of your turn: the top card of your draw pile is exiled (removed from this fight).",
			"transition_msg": "THE LANTERNHALL READS YOUR LAST PAGES!",
			"transition_effect": {"type": "summon", "name": "Star-Reader",
				"atk": 2, "hp": 3, "kw": []}},
		{"threshold": 0, "passive_id": "forge_burn_all",
			"passive_desc": "Start of each round: deal 1 damage to every creature on the board (both sides).",
			"transition_msg": "THE EVERFLAME TAKES THE HALL!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"amalgam_pyromancer": [
		{"threshold": 27, "passive_id": "throne_husks",
			"passive_desc": "Start of each round: summon a 2/2 Swift creature in an empty enemy lane."},
		{"threshold": 14, "passive_id": "formation_drill",
			"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1.",
			"transition_msg": "THE BROKEN WALL REBUILDS ITSELF!",
			"transition_effect": {"type": "summon_multiple", "name": "Shieldbearer",
				"atk": 2, "hp": 4, "count": 2, "kw": ["armored"]}},
		{"threshold": 0, "passive_id": "hollow_king_snipe",
			"passive_desc": "Start of each round: deal 3 damage to your highest-ATK creature.",
			"transition_msg": "THE OWED COLLECT WHAT YOU BURIED!",
			"transition_effect": {"type": "debuff_all_player_atk", "value": 1}},
	],
	"amalgam_kindler": [
		{"threshold": 27, "passive_id": "void_exile",
			"passive_desc": "Start of your turn: the top card of your draw pile is exiled (removed from this fight)."},
		{"threshold": 14, "passive_id": "crypt_ghost",
			"passive_desc": "When an enemy creature dies: summon a 1/1 Swift Ghost in a random empty enemy lane.",
			"transition_msg": "EVERY FUNERAL YOU SOLD COMES HOME!",
			"transition_effect": {"type": "summon", "name": "Vault Warden",
				"atk": 2, "hp": 6, "kw": ["armored", "last_stand"]}},
		{"threshold": 0, "passive_id": "formation_lockstep",
			"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1, and enemy front-row creatures gain Armored.",
			"transition_msg": "THE WALL YOU BROKE STANDS WITH HIM!",
			"transition_effect": {"type": "summon_multiple", "name": "Shieldbearer",
				"atk": 2, "hp": 4, "count": 2, "kw": ["armored"]}},
	],
	"rival_stalwart": [
		# Phase 0 documents the STARTING passive only (it's never a transition
		# target — transitions go to index >=1). Kept in sync with the encounter's
		# passive_id (formation_muster, the gentler act-1 cadence); the threshold
		# 11 here is what triggers the endgame jump to lockstep below.
		{"threshold": 11, "passive_id": "formation_muster",
			"passive_desc": "From round 3: each FRONT-rank enemy standing beside another gains +1/+1."},
		{"threshold": 0, "passive_id": "formation_lockstep",
			"passive_desc": "The drill continues, and enemy front-row creatures gain Armored.",
			"transition_msg": "THE WALL CLOSES RANKS!",
			"transition_effect": {"type": "summon", "name": "Shieldbearer",
				"atk": 2, "hp": 5, "kw": ["armored", "thorns"]}},
	],
	"rival_raider": [
		{"threshold": 10, "passive_id": "harpy_swift_face",
			"passive_desc": "Enemy Swift creatures deal +1 face damage when attacking through empty lanes."},
		{"threshold": 0, "passive_id": "throne_husks",
			"passive_desc": "Start of each round: summon a 2/2 Swift creature in an empty enemy lane.",
			"transition_msg": "THE WHOLE HORIZON RIDES!",
			"transition_effect": {"type": "summon_multiple", "name": "Rider",
				"atk": 2, "hp": 2, "count": 2, "kw": ["swift"]}},
	],
	"rival_acolyte": [
		{"threshold": 10, "passive_id": "altar_sacrifice",
			"passive_desc": "Start of each round: the Altar claims the weakest enemy (+1 Charge). At 3, summon Paid in Full (5/6) and deal 3 face damage."},
		{"threshold": 0, "passive_id": "crypt_ghost",
			"passive_desc": "When an enemy creature dies: summon a 1/1 Swift Ghost in a random empty enemy lane.",
			"transition_msg": "THE DEBT COMES DUE!",
			"transition_effect": {"type": "summon_multiple", "name": "Repossessed",
				"atk": 2, "hp": 2, "count": 2, "kw": ["last_stand"]}},
	],
	"rival_pyromancer": [
		{"threshold": 10, "passive_id": "void_exile",
			"passive_desc": "Start of your turn: the top card of your draw pile is exiled (removed from this fight)."},
		{"threshold": 0, "passive_id": "puppet_keyword_copy",
			"passive_desc": "Start of each round: copy the keywords from your highest-ATK creature onto a random enemy.",
			"transition_msg": "HE HAS ALREADY SEEN YOUR HAND!",
			"transition_effect": {"type": "summon", "name": "Glass Sentinel",
				"atk": 2, "hp": 4, "kw": ["armored"]}},
	],
	"rival_kindler": [
		{"threshold": 11, "passive_id": "forge_burn_all",
			"passive_desc": "Start of each round: deal 1 damage to every creature on the board (both sides)."},
		{"threshold": 0, "passive_id": "doom_bell",
			"passive_desc": "Every other round a ticking Cinder (Doom 2) drops in. While it ticks, other enemies gain +1 ATK.",
			"transition_msg": "EVERYTHING PAYS AT ONCE!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"iron_warden": [
		{"threshold": 13, "passive_id": "", "passive_desc": ""},
		{"threshold": 0, "passive_id": "iron_warden_siege", "passive_desc": "All enemies gain Armored. End of each round: take 3 damage.",
			"transition_msg": "The Warden enters Siege Mode!",
			"transition_effect": {"type": "summon", "name": "Iron Guard", "atk": 2, "hp": 5, "kw": ["armored"]}},
	],
	"dragon_lord": [
		{"threshold": 12, "passive_id": "dragon_lord_piercing", "passive_desc": "All enemy creatures have Piercing."},
		{"threshold": 0, "passive_id": "dragon_lord_phase2", "passive_desc": "All enemy creatures have Piercing and gain +1 ATK.",
			"transition_msg": "The Dragon Lord roars!",
			"transition_effect": {"type": "heal_all_enemies", "value": 2}},
	],
	"collector": [
		{"threshold": 17, "passive_id": "collector_heal", "passive_desc": "When you play a creature: the Collector heals 1 HP."},
		{"threshold": 0, "passive_id": "collector_phase2", "passive_desc": "When you play a creature: the Collector heals 2 HP and a random enemy gains +1 ATK.",
			"transition_msg": "The Collector unveils his gallery!",
			"transition_effect": {"type": "summon_multiple", "name": "Trinket", "atk": 2, "hp": 3, "count": 2}},
	],
	"hollow_king": [
		{"threshold": 16, "passive_id": "hollow_king_snipe", "passive_desc": "Start of each round: deal 3 damage to your highest-ATK creature."},
		{"threshold": 0, "passive_id": "hollow_king_phase2", "passive_desc": "Start of each round: deal 3 damage to your two highest-ATK creatures and add a Curse to your discard pile.",
			"transition_msg": "The Hollow King's void spreads!",
			"transition_effect": {"type": "debuff_all_player_atk", "value": 1}},
	],
	"the_devil": [
		{"threshold": 20, "passive_id": "devil_cycle", "passive_desc": "Repeating cycle. R1: deal 2 face damage. R2: heal 1 HP per enemy. R3: deal 3 damage to your highest-ATK creature."},
		{"threshold": 10, "passive_id": "devil_phase2", "passive_desc": "The three-round cycle's effects double. All enemy creatures gain +1 ATK.",
			"transition_msg": "THE DEVIL REVEALS HIS TRUE FORM!",
			"transition_effect": {"type": "summon", "name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"]}},
		{"threshold": 0, "passive_id": "devil_phase3", "passive_desc": "DESPERATION. Each round: deal 3 face damage, summon a creature, and all enemies gain +1 ATK.",
			"transition_msg": "THE DEVIL UNLEASHES HIS FULL POWER!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"the_crone": [
		{"threshold": 24, "passive_id": "crone_drip", "passive_desc": "End of each round: add 1 Curse to your discard pile."},
		{"threshold": 12, "passive_id": "crone_lash", "passive_desc": "End of each round: add 1 Curse to your discard pile and deal 1 face damage for each Curse in your deck.",
			"transition_msg": "The Crone's voice cracks the air!",
			"transition_effect": {"type": "summon", "name": "Wraith", "atk": 2, "hp": 3, "kw": ["swift"]}},
		{"threshold": 0, "passive_id": "crone_doom", "passive_desc": "End of each round: add 2 Curses to your discard pile, deal 1 face damage per Curse in your deck, and summon a Wraith.",
			"transition_msg": "THE CRONE BURIES YOU IN HER GRAVE-DIRT!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"the_black_tide": [
		{"threshold": 26, "passive_id": "tide_swell", "passive_desc": "End of each round: if there are fewer than 4 enemy creatures on the board, summon a 2/3 Deepling."},
		{"threshold": 13, "passive_id": "tide_surge", "passive_desc": "End of each round: summon a Deepling and all enemy creatures gain +1 ATK.",
			"transition_msg": "The tide rises higher!",
			"transition_effect": {"type": "summon", "name": "Anglerfish", "atk": 4, "hp": 3}},
		{"threshold": 0, "passive_id": "tide_drown", "passive_desc": "All previous effects continue. Each round: deal 3 damage to your weakest creature.",
			"transition_msg": "THE BLACK TIDE DRAGS YOU UNDER!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 2}},
	],
}


# Encounter scripts: scripted moments at specific rounds that change the
# fight dynamic. Modeled after Slay the Spire's elite/boss patterns where
# specific turns have predictable but impactful events the player learns
# to plan around (Hexaghost lighting candles, Lagavulin waking up).
#
# Each entry: {round: int, msg: String, event: String, ...params}
# Events handled in Combat.gd._run_encounter_script:
#   - summon: places a named creature (params: name, atk, hp, kw[])
#   - buff_all_atk: all enemy creatures gain +N ATK permanent (params: value)
#   - buff_all_hp: all enemy creatures gain +N HP (params: value)
#   - grant_keyword_all: grant a keyword to all enemy creatures (params: keyword)
#   - face_damage: direct damage to player face (params: value)
#   - heal_all: heal all enemy creatures (params: value)
const ENCOUNTER_SCRIPTS: Dictionary = {
	# ── Act 1 ────────────────────────────────────────────────────────────
	"goblin_scouts": [
		{"round": 3, "msg": "The goblins call for backup!",
			"event": "summon", "name": "Goblin", "atk": 2, "hp": 2},
		{"round": 5, "msg": "GOBLIN AMBUSH!",
			"event": "grant_keyword_all", "keyword": "swift"},
	],
	"wolf_pack": [
		{"round": 2, "msg": "The wolves howl — pack frenzy!",
			"event": "buff_all_atk", "value": 1},
		{"round": 4, "msg": "The Alpha emerges!",
			"event": "summon", "name": "Alpha Wolf", "atk": 4, "hp": 5},
	],
	"bandit_camp": [
		{"round": 3, "msg": "The bandits draw blades!",
			"event": "grant_keyword_all", "keyword": "swift"},
		{"round": 5, "msg": "Bandit reinforcements arrive!",
			"event": "summon", "name": "Bandit Captain", "atk": 3, "hp": 4},
	],
	"mushroom_grove": [
		{"round": 2, "msg": "Spores fill the air…",
			"event": "face_damage", "value": 2},
		{"round": 4, "msg": "The grove awakens!",
			"event": "buff_all_hp", "value": 2},
	],
	"stone_sentinels": [
		{"round": 3, "msg": "The sentinels harden their shells!",
			"event": "grant_keyword_all", "keyword": "armored"},
	],
	"harpy_nest": [
		{"round": 2, "msg": "The harpies take flight!",
			"event": "grant_keyword_all", "keyword": "swift"},
		{"round": 4, "msg": "Mother Harpy descends!",
			"event": "summon", "name": "Mother Harpy", "atk": 3, "hp": 5},
	],
	"boar_herd": [
		{"round": 3, "msg": "The herd charges!",
			"event": "buff_all_atk", "value": 1},
	],
	"scarecrow_field": [
		{"round": 2, "msg": "The crows arrive!",
			"event": "summon", "name": "Crow", "atk": 2, "hp": 2},
		{"round": 4, "msg": "Harvest moon rises!",
			"event": "buff_all_atk", "value": 1},
	],
	# ── Act 2 ────────────────────────────────────────────────────────────
	"cultist_enclave": [
		{"round": 3, "msg": "The cultists begin the ritual!",
			"event": "face_damage", "value": 3},
		{"round": 5, "msg": "An acolyte ascends!",
			"event": "summon", "name": "Ritual Acolyte", "atk": 3, "hp": 5},
	],
	"swamp_horror": [
		{"round": 2, "msg": "The swamp churns!",
			"event": "heal_all", "value": 2},
		{"round": 4, "msg": "The Horror surfaces!",
			"event": "summon", "name": "Bog Tendril", "atk": 4, "hp": 4},
	],
	"mercenary_company": [
		{"round": 3, "msg": "The captain rallies the line!",
			"event": "buff_all_atk", "value": 1},
	],
	"haunted_crypt": [
		{"round": 2, "msg": "Cold wind from the crypt…",
			"event": "face_damage", "value": 2},
		{"round": 4, "msg": "The dead rise!",
			"event": "summon", "name": "Risen Skeleton", "atk": 3, "hp": 3},
	],
	"fire_giants_forge": [
		{"round": 3, "msg": "The forge roars to life!",
			"event": "grant_keyword_all", "keyword": "swift"},
	],
	"ash_hounds": [
		{"round": 2, "msg": "The hounds catch your scent!",
			"event": "buff_all_atk", "value": 1},
		{"round": 4, "msg": "The pack masters arrive!",
			"event": "summon", "name": "Ash Master", "atk": 4, "hp": 4},
	],
	# ── Act 3 ────────────────────────────────────────────────────────────
	"mirror_temple": [
		{"round": 3, "msg": "Your reflection turns hostile!",
			"event": "buff_all_atk", "value": 2},
	],
	"elemental_nexus": [
		{"round": 2, "msg": "The leylines surge!",
			"event": "grant_keyword_all", "keyword": "piercing"},
		{"round": 4, "msg": "A greater elemental manifests!",
			"event": "summon", "name": "Storm Elemental", "atk": 4, "hp": 5},
	],
	"executioners_block": [
		{"round": 3, "msg": "The Executioner raises his axe!",
			"event": "face_damage", "value": 4},
	],
	"dragons_lair": [
		{"round": 2, "msg": "Dragon-fire scorches the field!",
			"event": "face_damage", "value": 3},
		{"round": 4, "msg": "The dragon's wrath grows!",
			"event": "buff_all_atk", "value": 1},
	],
	"pyre_cult": [
		{"round": 3, "msg": "The pyre flares!",
			"event": "buff_all_atk", "value": 2},
	],
	"withered_court": [
		{"round": 2, "msg": "The court whispers curses…",
			"event": "face_damage", "value": 2},
		{"round": 4, "msg": "The Withered King appears!",
			"event": "summon", "name": "Withered King", "atk": 5, "hp": 6},
	],
	"killing_choir": [
		{"round": 3, "msg": "The choir reaches its crescendo!",
			"event": "buff_all_atk", "value": 1},
	],
}


# Reactive passives: trigger on specific player actions.
# "trigger": what player action triggers it
# "effect": what happens when triggered
const REACTIVE_PASSIVES: Dictionary = {
	"cultist_enclave": {"trigger": "ON_PLAYER_SACRIFICE", "effect": "face_damage",
		"value": 2, "desc": "Deal 2 face damage when player sacrifices."},
	"haunted_crypt": {"trigger": "ON_PLAYER_SPELL", "effect": "face_damage",
		"value": 1, "desc": "Deal 1 face damage when you cast a spell."},
	"demon_vanguard": {"trigger": "ON_PLAYER_SPELL", "effect": "face_damage",
		"value": 1, "desc": "Deal 1 face damage when you cast a spell."},
	"puppeteer": {"trigger": "ON_PLAYER_SUMMON", "effect": "summon_puppet",
		"atk": 2, "hp": 2, "desc": "Summon a 2/2 Puppet when player summons."},
	# THE ACOLYTE (rival lord): your funerals are deposits in HIS ledger too.
	"rival_acolyte": {"trigger": "ON_PLAYER_SACRIFICE", "effect": "face_damage",
		"value": 2, "desc": "Deal 2 face damage when player sacrifices."},
}


# =====================================================================
#  ENCOUNTER DATA
# =====================================================================

const ENCOUNTERS: Dictionary = {

	# =================== RIVAL LORDS (Successor Wars) ====================
	# One kit per hero — under conquest the act bosses are the heroes you
	# didn't pick. Kits are authored at the act-1 band; get_face_hp /
	# build_enemy_deck scale a lord up when his kingdom is invaded in act 2
	# or 3, so a rival faced late is the same lord with deeper ranks (the §9
	# Phase-7 scaling requirement, answered by the cross-act rails).
	# All five lords are authored; RunState._boss_encounter_for_act's
	# faction stand-in path remains only as a safety net.

	"rival_stalwart": {
		# THE STALWART — Lord of the Last Wall (Formation). His age of the
		# island is the legion: drill, line-relief, the eagle that must not
		# fall. The wall grows while it stands: each body holding a line
		# beside another gains +1/+1 at the top of every round (from round 2
		# — the player gets one clean read of the board first). Phase 2
		# closes ranks: the drill continues AND the front row goes Armored.
		# Counterplay is reading the line — kill the middle, isolate the
		# ends, never let two of his walls stand touching for free.
		"name": "THE STALWART", "act": 1, "type": "boss", "faction": "last_wall", "hp": 23,
		"passive_id": "formation_muster",
		"passive_desc": "From round 3: each FRONT-rank enemy standing beside another gains +1/+1.",
		"preamble": "He has lost battles in every age and not one war. Stone does not argue — it drills. Leave his wall standing and it stands harder.",
		"deck": [
			{"name": "Pikeman", "atk": 1, "hp": 4, "kw": ["thorns"]},
			{"name": "Shieldbearer", "atk": 1, "hp": 5, "kw": ["armored"]},
			{"name": "Eagle-Bearer", "atk": 1, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0},
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Veteran", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Centurion", "atk": 2, "hp": 5, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Pikeman", "atk": 1, "hp": 4, "kw": ["thorns"]},
			{"name": "First Spear", "atk": 4, "hp": 4, "kw": ["armored", "last_stand"]},
		],
		"reinforcement": {"name": "Recruit", "atk": 2, "hp": 3, "kw": ["armored"]},
		"reinforcement_pool": [
			{"name": "Pikeman", "atk": 1, "hp": 4, "kw": ["thorns"]},
		],
	},

	"rival_raider": {
		# THE RAIDER — Lord of the Grasswake (Overrun). His age of the island
		# is the horse-conquest: landless brothers over the water, forty
		# lances to a kingdom. The empty lane is his highway: the whole
		# warband is Swift and chips face on entry, and the harpy_swift_face
		# passive pays his riders +1 face damage for every attack that sails
		# through an open lane. Phase 2 stops caring whether you walled up —
		# the wake keeps summoning Swift bodies into his empty lanes.
		# Counterplay is holding all four gates: every lane you leave open is
		# a toll you pay twice.
		"name": "THE RAIDER", "act": 1, "type": "boss", "faction": "grasswake", "hp": 22,
		"passive_id": "harpy_swift_face",
		"passive_desc": "Enemy Swift creatures deal +1 face damage when attacking through empty lanes.",
		"preamble": "He crossed the water with forty lances and was crowned at a dead gallop. Every lane you leave open is a road home, and his riders know them all.",
		"deck": [
			{"name": "Outrider", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Salt Harpy", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
			{"name": "Banner-Bearer", "atk": 1, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Wake Hound", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			{"name": "Pennon Griffin", "atk": 3, "hp": 3, "kw": ["swift", "piercing"]},
			{"name": "First Ashore", "atk": 4, "hp": 4, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0},
				"on_enter": {"type": "damage_face", "value": 1}},
		],
		"reinforcement": {"name": "Rider", "atk": 2, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
			{"name": "Outrider", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
		],
	},

	"rival_acolyte": {
		# THE ACOLYTE — Lord of the Owed (the Tithe). His age of the island
		# is the merchant-god city: hired spears, the furnace altar, the
		# ledger that always balances. Deaths are deposits: a back-row
		# Furnace Altar takes the weakest of his own creatures every round
		# (+1 Charge — their on-deaths still fire), and at 3 Charges it cashes
		# the lot out as Paid in Full (a 5/6) plus face damage. Half his
		# bodies pay out on death, so killing them and sparing them both feed
		# the ledger. Phase 2 stops banking — every death raises a Ghost on
		# the spot. The ON_PLAYER_SACRIFICE reactive taxes your own rituals
		# 2 face. The altar's Charge badge is the fight's visible
		# corpse-counter.
		"name": "THE ACOLYTE", "act": 1, "type": "boss", "faction": "owed", "hp": 22,
		"passive_id": "altar_sacrifice",
		"passive_desc": "Start of each round: the Altar claims the weakest enemy (+1 Charge). At 3, summon Paid in Full (5/6) and deal 3 face damage.",
		"preamble": "He keeps his kingdom's books, and the books are graves. Everything that dies near him is banked and spent again. You are already in the ledger.",
		"structures": [
			{"name": "Furnace Altar", "atk": 0, "hp": 99,
				"kw": ["structure"], "charge_max": 3, "lane": 1},
		],
		"deck": [
			{"name": "Initiate", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Debtor", "atk": 2, "hp": 1, "kw": ["last_stand"]},
			{"name": "Collateral", "atk": 2, "hp": 2, "kw": ["last_stand"],
				"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			{"name": "Bleeding Heart", "atk": 2, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Furnace Priest", "atk": 2, "hp": 4, "kw": ["regenerate"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Vault Warden", "atk": 2, "hp": 6, "kw": ["armored", "last_stand"]},
			{"name": "Tithe Collector", "atk": 3, "hp": 5, "kw": ["piercing"],
				"on_death": {"type": "damage_face", "value": 2}},
		],
		"reinforcement": {"name": "Repossessed", "atk": 2, "hp": 2, "kw": ["last_stand"]},
		"reinforcement_pool": [
			{"name": "Initiate", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Debtor", "atk": 2, "hp": 1, "kw": ["last_stand"]},
		],
	},

	"rival_pyromancer": {
		# THE PYROMANCER — Lord of the Lanternhall (Foresight). His age of
		# the island is the geometer's city: burning mirrors, the harbor
		# claw, circles in the sand. The fire lord who learned the colder
		# arithmetic: void_exile reads (and removes) the top of your draw
		# pile every turn, his Claw Adepts shake the ATK out of whatever they
		# face on entry, and the back row snipes past your wall. Phase 2 he
		# stops reading and starts rewriting — your best creature's keywords
		# get copied onto his pieces every round. Kill the fight fast; every
		# stalled turn costs a card you might have needed.
		"name": "THE PYROMANCER", "act": 1, "type": "boss", "faction": "lanternhall", "hp": 28,
		"passive_id": "void_exile",
		"passive_desc": "Start of your turn: the top card of your draw pile is exiled (removed from this fight).",
		"preamble": "He came up burning things, then the library taught him the colder arithmetic: mirrors, circles, endings read a season early. He has already read yours.",
		"deck": [
			{"name": "Star-Reader", "atk": 2, "hp": 2, "kw": []},
			{"name": "Claw Adept", "atk": 1, "hp": 3, "kw": [],
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Burning Glass", "atk": 4, "hp": 2, "kw": ["piercing"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Ink Beast", "atk": 3, "hp": 4,
				"on_enter": {"type": "discard_random"}},
			{"name": "Hall-Watcher", "atk": 1, "hp": 6, "kw": ["thorns", "armored"]},
			{"name": "Cold Lector", "atk": 4, "hp": 4, "kw": [],
				"intents": ["ATK", "ABILITY", "ATK", "ABILITY"],
				"ability": {"type": "steal_atk", "value": 1}},
		],
		"reinforcement": {"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Star-Reader", "atk": 2, "hp": 2, "kw": []},
			{"name": "Burning Glass", "atk": 3, "hp": 2, "kw": ["piercing"]},
		],
	},

	"rival_kindler": {
		# THE KINDLER — Lord of the Everflame (the Fuse). His age of the
		# island is the liquid fire: the sealed recipe, the siphons, fire
		# that burns on water. Nothing pays now, everything pays later:
		# forge_burn_all cooks both boards 1 a round (his armored and
		# regenerating bodies shrug it; your chaff doesn't), ticking Cinders
		# ride the deck AND the reinforcement drip, and his martyrs detonate
		# on death. Phase 2 the slow burn becomes the detonation — the
		# doom_bell toll drops fresh bombs every other round while the host
		# swings harder. Race him or defuse him; turtling pays his interest.
		"name": "THE KINDLER", "act": 1, "type": "boss", "faction": "everflame", "hp": 23,
		"passive_id": "forge_burn_all",
		"passive_desc": "Start of each round: deal 1 damage to every creature on the board (both sides).",
		"preamble": "The recipe is sealed behind his teeth, and what it makes burns on water. Every bomb and martyr is a debt rolled forward to a louder day. You have arrived on the due date.",
		"deck": [
			{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
			{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
			{"name": "Siphon Imp", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Burning Martyr", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Ash Hound", "atk": 4, "hp": 2, "kw": ["swift", "piercing"], "wither": 1},
			{"name": "Pitch Hulk", "atk": 2, "hp": 5, "kw": ["thorns", "armored"]},
			{"name": "Pyre Tender", "atk": 3, "hp": 5, "kw": ["regenerate"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Cinder Sprite", "atk": 1, "hp": 1, "kw": ["swift"],
			"on_enter": {"type": "damage_face", "value": 1}},
		"reinforcement_pool": [
			{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
			{"name": "Burning Martyr", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
		],
	},

	# =================== THE THRONE (amalgam finales) ====================
	# One per hero — fought when that hero is the SPARED rival (the one you
	# never invaded), waiting on the throne empowered by the three kingdoms
	# you burned. Pre-authored MVP (§6): three phases channel the other
	# kingdoms' engines under the spared lord's banner. Keyed
	# amalgam_<hero>; RunState.enter_finale places them, never random pools.
	# All five lords have a throne kit, so every conquest run now ends at
	# the amalgam (should_enter_finale still guards on the kit existing).

	"amalgam_acolyte": {
		# THE ACOLYTE ASCENDANT — the Owed on the throne. You handed him
		# three kingdoms' worth of funerals, and the dead still hold office:
		# phase 1 raises the fallen as a Swift trickle (the riderless dead),
		# phase 2 the burned Wall closes ranks (formation_drill, the same
		# engine THE STALWART drills), phase 3 the Everflame answers with
		# ticking Cinders (the doom_bell toll). Each phase is a kingdom the
		# player already learned to fight — now stacked into one climb.
		"name": "THE ACOLYTE ASCENDANT", "act": 3, "type": "boss", "faction": "owed", "hp": 40,
		"passive_id": "throne_husks",
		"passive_desc": "Start of each round: summon a 2/2 Swift creature in an empty enemy lane.",
		"preamble": "You burned three kingdoms to reach this chair, and he thanks you for every funeral — they all marched here ahead of you. Win, and everything the throne owes comes with it.",
		"deck": [
			{"name": "Wraith", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Debtor", "atk": 2, "hp": 1, "kw": ["last_stand"]},
			{"name": "Collateral", "atk": 2, "hp": 2, "kw": ["last_stand"],
				"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			{"name": "Pikeman", "atk": 1, "hp": 4, "kw": ["thorns", "armored"]},
			{"name": "Shieldbearer", "atk": 1, "hp": 5, "kw": ["armored"]},
			{"name": "Vault Warden", "atk": 2, "hp": 6, "kw": ["armored", "last_stand"]},
			{"name": "Risen Lich", "atk": 4, "hp": 4, "kw": ["piercing"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
		],
		"reinforcement": {"name": "Repossessed", "atk": 2, "hp": 2, "kw": ["last_stand"]},
	},

	"amalgam_raider": {
		# THE RAIDER ASCENDANT — the Grasswake on the throne. The lord who
		# never stood still now sits, and the kingdoms you broke ride escort:
		# phase 1 the burned Wall drills his line (+1/+1 for standing
		# together), phase 2 the Owed raise a Ghost from every death, phase 3
		# the Everflame tolls ticking Cinders. The horde itself stays Swift
		# and face-hungry the whole climb.
		"name": "THE RAIDER ASCENDANT", "act": 3, "type": "boss", "faction": "grasswake", "hp": 40,
		"passive_id": "formation_drill",
		"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1.",
		"preamble": "You broke three kingdoms getting here, and he watched from horseback — fewer fences every time you won. Everything you tore down rides under his banner now. Win, if you can make it stand still.",
		"deck": [
			{"name": "Salt Harpy", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Outrider", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
			{"name": "Banner-Bearer", "atk": 1, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Shieldbearer", "atk": 1, "hp": 5, "kw": ["armored"]},
			{"name": "Wraith", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "First Ashore", "atk": 4, "hp": 4, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0},
				"on_enter": {"type": "damage_face", "value": 2}},
		],
		"reinforcement": {"name": "Rider", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	"amalgam_stalwart": {
		# THE STALWART ASCENDANT — the Last Wall on the throne. The wall
		# learned from every kingdom it outlasted: phase 1 the riderless dead
		# trickle in Swift, phase 2 the Lanternhall reads your dwindling deck
		# (top card exiled each turn), phase 3 the Everflame burns the whole
		# hall — and his Armored line shrugs the 1-a-round burn while your
		# chaff cooks. Break the wall before the fire does his work for him.
		"name": "THE STALWART ASCENDANT", "act": 3, "type": "boss", "faction": "last_wall", "hp": 40,
		"passive_id": "formation_drill",
		"passive_desc": "Start of each round: each enemy creature standing beside another gains +1/+1.",
		"preamble": "You burned three kingdoms to rubble, and rubble is just stone waiting for a mason. He built the war you fought into the wall around this chair. Win, and everything it held back comes with it.",
		"deck": [
			{"name": "Pikeman", "atk": 1, "hp": 4, "kw": ["thorns", "armored"]},
			{"name": "Shieldbearer", "atk": 1, "hp": 5, "kw": ["armored"]},
			{"name": "Veteran", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Centurion", "atk": 2, "hp": 5, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Wraith", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Vault Warden", "atk": 2, "hp": 6, "kw": ["armored", "last_stand"]},
			{"name": "First Spear", "atk": 4, "hp": 4, "kw": ["armored", "last_stand"]},
		],
		"reinforcement": {"name": "Recruit", "atk": 2, "hp": 3, "kw": ["armored"]},
	},

	"amalgam_pyromancer": {
		# THE PYROMANCER ASCENDANT — the Lanternhall on the throne. The
		# coldest ending he ever read is his own coronation: phase 1 the
		# riderless dead trickle in Swift, phase 2 the burned Wall rebuilds
		# itself around his readers (+1/+1 drill), phase 3 the Owed collect —
		# the void executes your strongest creature every round. His own
		# bench is glass and starlight: Ranged, chilling, copying your tricks.
		"name": "THE PYROMANCER ASCENDANT", "act": 3, "type": "boss", "faction": "lanternhall", "hp": 40,
		"passive_id": "throne_husks",
		"passive_desc": "Start of each round: summon a 2/2 Swift creature in an empty enemy lane.",
		"preamble": "He read each kingdom's ending a season before you wrote it. What is left of them sits beside him now, cold and catalogued and pointed at you. He has already seen whether you win.",
		"deck": [
			{"name": "Star-Reader", "atk": 2, "hp": 3, "kw": []},
			{"name": "Burning Glass", "atk": 3, "hp": 2, "kw": ["piercing"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Claw Adept", "atk": 1, "hp": 3, "kw": [],
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Hall-Watcher", "atk": 1, "hp": 6, "kw": ["thorns", "armored"]},
			{"name": "Ink Beast", "atk": 3, "hp": 5,
				"on_enter": {"type": "discard_random"}},
			{"name": "Cold Lector", "atk": 4, "hp": 5, "kw": []},
		],
		"reinforcement": {"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	"amalgam_kindler": {
		# THE KINDLER ASCENDANT — the Everflame on the throne. The fire that
		# was promised, wearing the kingdoms you fed it: phase 1 the
		# Lanternhall reads your deck down (top card exiled each turn),
		# phase 2 the Owed raise a Ghost from every death — and his bombs and
		# martyrs die constantly — phase 3 the broken Wall stands with him,
		# Armored and drilling. The bench is pure fuse: Cinders, martyrs, and
		# bodies that pay out on the way down.
		"name": "THE KINDLER ASCENDANT", "act": 3, "type": "boss", "faction": "everflame", "hp": 40,
		"passive_id": "void_exile",
		"passive_desc": "Start of your turn: the top card of your draw pile is exiled (removed from this fight).",
		"preamble": "You burned three kingdoms to get here, which he takes as flattery — it was his trick first. Their ashes are stacked as kindling around his chair. Everything burns on a timer, even thrones.",
		"deck": [
			{"name": "Cinder", "atk": 1, "hp": 3, "kw": ["doom"], "doom": 2, "doom_damage": 5},
			{"name": "Cinder", "atk": 1, "hp": 3, "kw": ["doom"], "doom": 2, "doom_damage": 5},
			{"name": "Burning Martyr", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Ash Hound", "atk": 4, "hp": 2, "kw": ["swift", "piercing"], "wither": 1},
			{"name": "Pitch Hulk", "atk": 2, "hp": 5, "kw": ["thorns", "armored"]},
			{"name": "Siphon Imp", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Conflagrant", "atk": 5, "hp": 5, "kw": ["piercing"],
				"on_death": {"type": "damage_face", "value": 3}},
		],
		"reinforcement": {"name": "Cinder Sprite", "atk": 1, "hp": 1, "kw": ["swift"],
			"on_enter": {"type": "damage_face", "value": 1}},
	},

	# =================== ACT 1 — COMBAT ===========================

	"goblin_scouts": {
		# Goblin Scouts — AMBUSH AND SCATTER. Almost everything is Swift (the
		# whole pack swings before player creatures resolve), most carry a
		# small chip-damage on_enter or random-player ping. Low HP, easy to
		# clear — but the first round HURTS if you didn't expect a wave.
		"name": "The First Cut", "act": 1, "type": "combat", "faction": "grasswake", "hp": 11,
		"preamble": "The smallest blade the war owns, sent ahead to see if you bleed like the last lot. First cuts take your measure.",
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Runt", "atk": 1, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			{"name": "Sneak", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
			{"name": "Pyro", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Looter", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Banner-Bearer", "atk": 1, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Chief", "atk": 3, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
		],
		"deck_variants": [
			# Variant: knife-eared swarm — all-swift, all-low, drowns you in chip.
			[
				{"name": "Runt", "atk": 1, "hp": 2, "kw": ["swift"],
					"on_death": {"type": "summon", "atk": 1, "hp": 1}},
				{"name": "Sneak", "atk": 2, "hp": 2, "kw": ["swift"]},
				{"name": "Sneak", "atk": 2, "hp": 2, "kw": ["swift"]},
				{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
				{"name": "Pyro", "atk": 2, "hp": 2, "kw": ["swift"],
					"on_enter": {"type": "damage_random_player", "value": 1}},
				{"name": "Chief", "atk": 3, "hp": 3, "kw": ["swift"],
					"on_enter": {"type": "damage_face", "value": 1}},
			],
			# Variant: slinger line — ranged-heavy, less swift up close.
			[
				{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
				{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
				{"name": "Looter", "atk": 2, "hp": 2, "kw": ["swift"],
					"on_enter": {"type": "damage_face", "value": 1}},
				{"name": "Pyro", "atk": 2, "hp": 2, "kw": ["swift"],
					"on_enter": {"type": "damage_random_player", "value": 1}},
				{"name": "Banner-Bearer", "atk": 1, "hp": 3,
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Runt", "atk": 1, "hp": 2, "kw": ["swift"],
					"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			],
		],
		"reinforcement": {"name": "Whelp", "atk": 1, "hp": 1, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Sneak", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
		],
	},

	"wolf_pack": {
		# Wolf Pack — DENSITY MATTERS. Most wolves carry adj_buff, so a clumped
		# pack hits much harder than a spread one. The revenge passive rages
		# adjacents when one falls; killing the buffer in the middle is the
		# puzzle, not killing the front-row chaff.
		"name": "The Den Mother's Brood", "act": 1, "type": "combat", "faction": "grasswake", "hp": 13,
		"preamble": "The grass was a hunting ground before it was a road, and her brood has not forgotten which of you is meat.",
		"passive_id": "wolf_pack_revenge",
		"passive_desc": "When an enemy creature dies: adjacent enemies gain +1 ATK this round.",
		"deck": [
			{"name": "Cub", "atk": 1, "hp": 2, "kw": ["last_stand"]},
			{"name": "Stalker", "atk": 2, "hp": 2, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Flanker", "atk": 2, "hp": 2, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Pack Wolf", "atk": 2, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Den Mother", "atk": 1, "hp": 5,
				"adj_buff": {"atk": 0, "hp": 1},
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Bloodfang", "atk": 3, "hp": 3, "kw": ["piercing"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Alpha", "atk": 3, "hp": 5, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"deck_variants": [
			# Variant: glass-cannon pack — all-swift, low HP, hits hard.
			[
				{"name": "Cub", "atk": 1, "hp": 2, "kw": ["last_stand"]},
				{"name": "Stalker", "atk": 2, "hp": 2, "kw": ["swift"],
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Stalker", "atk": 2, "hp": 2, "kw": ["swift"],
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Bloodfang", "atk": 3, "hp": 3, "kw": ["piercing"],
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Bloodfang", "atk": 3, "hp": 3, "kw": ["piercing"],
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Alpha", "atk": 3, "hp": 5, "kw": ["swift"],
					"adj_buff": {"atk": 1, "hp": 0}},
			],
			# Variant: brood-heavy pack — slow, summoner-leaning.
			[
				{"name": "Cub", "atk": 1, "hp": 2, "kw": ["last_stand"]},
				{"name": "Cub", "atk": 1, "hp": 2, "kw": ["last_stand"]},
				{"name": "Pack Wolf", "atk": 2, "hp": 3,
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Den Mother", "atk": 1, "hp": 5,
					"adj_buff": {"atk": 0, "hp": 1},
					"on_death": {"type": "summon", "atk": 2, "hp": 2}},
				{"name": "Den Mother", "atk": 1, "hp": 5,
					"adj_buff": {"atk": 0, "hp": 1},
					"on_death": {"type": "summon", "atk": 2, "hp": 2}},
				{"name": "Alpha", "atk": 3, "hp": 5, "kw": ["swift"],
					"adj_buff": {"atk": 1, "hp": 0}},
			],
		],
		"reinforcement": {"name": "Yearling", "atk": 2, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Stalker", "atk": 2, "hp": 2, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Pack Wolf", "atk": 2, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0}},
		],
	},

	"bandit_camp": {
		"name": "The Toll-Takers", "act": 1, "type": "combat", "faction": "grasswake", "hp": 13,
		"preamble": "Every road has a price, and these men appointed themselves to collect it — in coin, in teeth, in whatever comes loose.",
		"passive_id": "bandit_mana_steal",
		"passive_desc": "When the enemy places its first reinforcement each round: you lose 1 Command next turn.",
		# Bandit Camp — mixed combat archetypes. Cutpurse (eco), Archer (range),
		# Brawler (front), Hexer (debuff), Captain (lead), Saboteur (curse).
		# Bandit Camp — STEAL AND STING. Every bandit chips at face on entry
		# or carries Ranged for sniping. Brawler is the only real wall — kill
		# him and you eat hits, kill the snipers first and you eat the wall.
		"deck": [
			{"name": "Cutpurse", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Brawler", "atk": 3, "hp": 3, "kw": ["armored"]},
			{"name": "Archer", "atk": 2, "hp": 2, "kw": [],
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Hexer", "atk": 1, "hp": 3, "kw": [],
				"on_enter": {"type": "debuff_opposing_atk", "value": 1}},
			{"name": "Saboteur", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Camp Mutt", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Captain", "atk": 3, "hp": 4, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"deck_variants": [
			# Variant: ranged outlaws — two archers + crossbow, fewer melee.
			[
				{"name": "Cutpurse", "atk": 2, "hp": 2,
					"on_enter": {"type": "damage_face", "value": 1}},
				{"name": "Archer", "atk": 2, "hp": 2, "kw": [],
					"on_enter": {"type": "damage_random_player", "value": 1}},
				{"name": "Crossbowman", "atk": 2, "hp": 2, "kw": []},
				{"name": "Crossbowman", "atk": 2, "hp": 2, "kw": []},
				{"name": "Camp Mutt", "atk": 2, "hp": 2, "kw": ["swift"]},
				{"name": "Captain", "atk": 3, "hp": 4,
					"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			],
			# Variant: curse-heavy crew — two saboteurs, no archer.
			[
				{"name": "Cutpurse", "atk": 2, "hp": 2,
					"on_enter": {"type": "damage_face", "value": 1}},
				{"name": "Saboteur", "atk": 2, "hp": 2,
					"intents": ["ATK", "ABILITY", "ATK", "ATK"],
					"ability": {"type": "curse"}},
				{"name": "Saboteur", "atk": 2, "hp": 2,
					"intents": ["ATK", "ABILITY", "ATK", "ATK"],
					"ability": {"type": "curse"}},
				{"name": "Hexer", "atk": 1, "hp": 3,
					"intents": ["ATK", "ABILITY", "ATK", "ABILITY"],
					"ability": {"type": "steal_atk", "value": 1}},
				{"name": "Brawler", "atk": 3, "hp": 3, "kw": ["armored"]},
				{"name": "Captain", "atk": 3, "hp": 4,
					"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			],
		],
		"reinforcement": {"name": "Thug", "atk": 2, "hp": 2},
		"reinforcement_pool": [
			{"name": "Camp Mutt", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Cutpurse", "atk": 2, "hp": 2,
				"on_enter": {"type": "damage_face", "value": 1}},
		],
	},

	"mushroom_grove": {
		"name": "The Spore-Cathedral", "act": 1, "type": "combat", "faction": "owed", "hp": 9,
		"preamble": "Something soft and patient has been preaching down here, and the dead make a devout congregation. Breathe shallow.",
		"passive_id": "mushroom_heal",
		"passive_desc": "End of each round: heal every enemy creature 1 HP.",
		# Mushroom Grove — IT JUST GROWS BACK. Almost every fungus regenerates
		# or seeds another on death; the grove passive heals everything at
		# round-end. The damage is low but trading is futile. AoE clears
		# faster than spot-killing.
		"deck": [
			{"name": "Sprout", "atk": 1, "hp": 3, "kw": ["regenerate"]},
			{"name": "Puffer", "atk": 1, "hp": 2, "kw": ["regenerate"],
				"on_death": {"type": "damage_all_enemies", "value": 1}},
			{"name": "Spore Beast", "atk": 2, "hp": 4, "kw": ["regenerate"],
				"on_death": {"type": "summon", "atk": 1, "hp": 2}},
			{"name": "Thornveil", "atk": 1, "hp": 4, "kw": ["thorns", "regenerate"]},
			{"name": "Cap Lasher", "atk": 3, "hp": 2, "kw": ["thorns"]},
			{"name": "Bloom Husk", "atk": 2, "hp": 3, "kw": ["regenerate"],
				"adj_buff": {"atk": 0, "hp": 1}},
			{"name": "Mycelium", "atk": 2, "hp": 5, "kw": ["regenerate"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
		],
		"deck_variants": [
			# Variant: thorny wall — multiple Thornveils discourage free trades.
			[
				{"name": "Sprout", "atk": 1, "hp": 3, "kw": ["regenerate"]},
				{"name": "Thornveil", "atk": 1, "hp": 4, "kw": ["thorns"]},
				{"name": "Thornveil", "atk": 1, "hp": 4, "kw": ["thorns"]},
				{"name": "Bloom Husk", "atk": 2, "hp": 3,
					"adj_buff": {"atk": 0, "hp": 1}},
				{"name": "Bloom Husk", "atk": 2, "hp": 3,
					"adj_buff": {"atk": 0, "hp": 1}},
				{"name": "Mycelium", "atk": 2, "hp": 5,
					"on_death": {"type": "damage_all_enemies", "value": 1},
					"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
			],
			# Variant: bomb grove — Puffers and Spore Beasts everywhere.
			[
				{"name": "Puffer", "atk": 1, "hp": 2,
					"on_death": {"type": "damage_all_enemies", "value": 1}},
				{"name": "Puffer", "atk": 1, "hp": 2,
					"on_death": {"type": "damage_all_enemies", "value": 1}},
				{"name": "Spore Beast", "atk": 2, "hp": 4,
					"on_death": {"type": "summon", "atk": 1, "hp": 2}},
				{"name": "Spore Beast", "atk": 2, "hp": 4,
					"on_death": {"type": "summon", "atk": 1, "hp": 2}},
				{"name": "Cap Lasher", "atk": 3, "hp": 2},
				{"name": "Mycelium", "atk": 2, "hp": 5,
					"on_death": {"type": "damage_all_enemies", "value": 1},
					"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
			],
		],
		"reinforcement": {"name": "Spore", "atk": 1, "hp": 2, "kw": ["regenerate"]},
		"reinforcement_pool": [
			{"name": "Puffer", "atk": 1, "hp": 2,
				"on_death": {"type": "damage_all_enemies", "value": 1}},
			{"name": "Sprout", "atk": 1, "hp": 3, "kw": ["regenerate"]},
		],
	},

	"stone_sentinels": {
		"name": "The Tooth-Stones", "act": 1, "type": "combat", "faction": "last_wall", "hp": 11,
		"preamble": "They were set in the ground to mark a border no living man remembers drawing. They still mean to hold it.",
		"passive_id": "",
		"passive_desc": "",
		# Stone Sentinels — heavy fortress: walls, hurlers, breakers, an animator.
		# Stone Sentinels — STONE THAT BITES BACK. Every sentinel is armored
		# or thorns or both. Spells get through fine; weapon trades are
		# punishing. Players learn to bring AoE / piercing for this fight or
		# eat thorns chip damage on every hit.
		"deck": [
			{"name": "Pebble", "atk": 1, "hp": 3, "kw": ["thorns"],
				"on_death": {"type": "damage_opposing_lane", "value": 1}},
			{"name": "Bastion", "atk": 1, "hp": 5, "kw": ["armored", "thorns"]},
			{"name": "Stone Hurler", "atk": 2, "hp": 3, "kw": ["armored"]},
			{"name": "Granite Guard", "atk": 2, "hp": 4, "kw": ["armored"]},
			{"name": "Earthshaker", "atk": 3, "hp": 3, "kw": ["armored"],
				"on_enter": {"type": "damage_random_player", "value": 2}},
			{"name": "Quarry Brute", "atk": 4, "hp": 3, "kw": ["thorns"]},
			{"name": "Stone Sentinel", "atk": 2, "hp": 5, "kw": ["armored", "thorns"]},
		],
		"reinforcement": {"name": "Fragment", "atk": 1, "hp": 2, "kw": ["armored", "thorns"]},
		"reinforcement_pool": [
			{"name": "Granite Guard", "atk": 2, "hp": 4, "kw": ["armored"]},
			{"name": "Pebble", "atk": 1, "hp": 3, "kw": ["thorns"],
				"on_death": {"type": "damage_opposing_lane", "value": 1}},
		],
	},

	"harpy_nest": {
		# Harpy Nest — DIVE AND VANISH. Almost every flyer is Swift, several
		# are also Ranged (back-row preference) so blocking a lane doesn't
		# stop the next dive. The matron buffs adjacents — kill her early or
		# the whole flock hits harder.
		"name": "The Stooping Wings", "act": 1, "type": "combat", "faction": "grasswake", "hp": 12,
		"preamble": "They nest where the road runs thin and the drop runs long. The screaming starts once they are already on you.",
		"passive_id": "harpy_swift_face",
		"passive_desc": "Enemy Swift creatures deal +1 face damage when attacking through empty lanes.",
		"deck": [
			{"name": "Chick", "atk": 1, "hp": 1, "kw": ["swift", "last_stand"]},
			{"name": "Wind Harpy", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Storm Harpy", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Plunderer", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Brood Harpy", "atk": 1, "hp": 3, "kw": [],
				"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			{"name": "Sky Stalker", "atk": 3, "hp": 3, "kw": ["swift", "piercing"]},
			{"name": "Matron", "atk": 2, "hp": 5, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Fledgling", "atk": 2, "hp": 1, "kw": ["swift"]},
	},

	"boar_herd": {
		# Boar Herd — STAMPEDE. Almost every boar is Swift, Piercing, or
		# Thorns — they're built to overwhelm, charge through, and gore on
		# the way out. High ATK, low HP. Trades hurt both ways, which is
		# the point: ignoring them costs face damage, killing them costs
		# board.
		"name": "The Trampling Hour", "act": 1, "type": "combat", "faction": "grasswake", "hp": 12,
		"preamble": "There is an hour near dusk when the herd comes through and the ground belongs to it. You arrived at that hour.",
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Piglet", "atk": 1, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Boar", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Razorback", "atk": 2, "hp": 3, "kw": ["thorns", "swift"]},
			{"name": "Sow", "atk": 2, "hp": 5, "kw": ["thorns"]},
			{"name": "Bristleback", "atk": 3, "hp": 3, "kw": ["thorns"],
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Charging Ram", "atk": 4, "hp": 2, "kw": ["swift", "piercing"]},
			{"name": "Tusker", "atk": 4, "hp": 4, "kw": ["piercing"],
				"on_death": {"type": "damage_opposing_lane", "value": 3}},
		],
		"reinforcement": {"name": "Yearling Boar", "atk": 2, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Boar", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Razorback", "atk": 2, "hp": 3, "kw": ["thorns", "swift"]},
		],
	},

	"scarecrow_field": {
		# Scarecrow Field — DRESSED IN THORNS. Half the field is straw-stuffed
		# walls that hurt to touch (thorns), the rest decay (wither) or peck
		# at your face (Crow swift). The Crow Witch is the sustain LEVER: she
		# telegraphs a heal-the-whole-field ABILITY every couple rounds — kill
		# her and the field stops growing back. The heal is a creature you can
		# answer, not an invisible passive (no more phantom mushroom_heal).
		"name": "The Field That Watches Back", "act": 1, "type": "combat", "faction": "owed", "hp": 10,
		"preamble": "Someone planted these to frighten the crows. The crows left years ago. The field kept watching anyway.",
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Scarecrow", "atk": 1, "hp": 5, "kw": ["thorns"]},
			{"name": "Straw Man", "atk": 2, "hp": 3, "kw": ["thorns"], "wither": 1},
			{"name": "Pumpkin Head", "atk": 3, "hp": 2, "kw": ["thorns"],
				"on_death": {"type": "damage_opposing_lane", "value": 2}},
			{"name": "Field Mouse", "atk": 1, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Stitched Hand", "atk": 2, "hp": 3, "kw": ["thorns", "regenerate"]},
			{"name": "Crow", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Crow Witch", "atk": 2, "hp": 5, "kw": ["thorns"],
				"intents": ["ATK", "ABILITY", "ATK", "ABILITY"],
				"ability": {"type": "heal_all", "value": 2}},
		],
		"reinforcement": {"name": "Scrap Crow", "atk": 2, "hp": 1, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Field Mouse", "atk": 1, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Straw Man", "atk": 2, "hp": 3, "kw": ["thorns"], "wither": 1},
		],
	},

	"powderkeg_run": {
		# The Powderkeg Run (Act 1 combat) — KILL THE KEGS OR EAT THE BLAST.
		# A goblin demolition crew. The signature is the Doom keyword introduced
		# at the normal-fight level: two "Cinder" walking bombs carry Doom 2 — a
		# loud on-board countdown (2 → 1 → BOOM into your face for 4). Low HP, so
		# you CAN defuse them, but the swift goblins crowd your lanes and make you
		# choose between blocking the rush and reaching the fuse. Fast, snappy,
		# and the player's first lesson in the clock that the Bellringer will
		# later weaponise. No passive — the bombs telegraph themselves.
		"name": "The Powderkeg Run", "act": 1, "type": "combat", "faction": "everflame", "hp": 12,
		"preamble": "Everything here is packed, fused, and stacked too close together. This fight only asks who lights it first.",
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Runt", "atk": 1, "hp": 2, "kw": ["swift"]},
			{"name": "Sneak", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
			{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
			{"name": "Kobold Hurler", "atk": 2, "hp": 2, "kw": []},
			{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
			{"name": "Chief", "atk": 3, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
		],
		"deck_variants": [
			# Variant: demolition surplus — three live kegs, fewer bodies. The
			# whole fight becomes a triage drill: which fuse do you reach first?
			[
				{"name": "Runt", "atk": 1, "hp": 2, "kw": ["swift"]},
				{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
				{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
				{"name": "Cinder", "atk": 2, "hp": 3, "kw": ["doom"], "doom": 3, "doom_damage": 5},
				{"name": "Slinger", "atk": 1, "hp": 2, "kw": ["swift"]},
				{"name": "Chief", "atk": 3, "hp": 3, "kw": ["swift"],
					"on_enter": {"type": "damage_face", "value": 1}},
			],
		],
		"reinforcement": {"name": "Whelp", "atk": 1, "hp": 1, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Sneak", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Cinder", "atk": 1, "hp": 2, "kw": ["doom"], "doom": 2, "doom_damage": 4},
		],
	},

	# =================== ACT 1 — ELITE ============================

	"orc_warband": {
		# Orc Warband (Act 1 elite) — BARBARIC RALLY. Inspired by Total War orc
		# waves: small grunts get permanent +1 ATK every round (orc_random_buff
		# passive), so the longer the fight runs the more dangerous the chaff
		# gets. Every orc carries Swift or Piercing — there's nowhere safe to
		# stall. Kill the Chieftain fast or the buffs land on the wrong guys.
		"name": "The Long Drumming", "act": 1, "type": "elite", "faction": "grasswake", "hp": 18,
		"preamble": "You hear them before the road bends — the drum that keeps a warband in step. It does not stop for parley.",
		"passive_id": "orc_random_buff",
		"passive_desc": "Start of each round: a random enemy creature gains +1 ATK for the rest of the fight.",
		"deck": [
			{"name": "Warrior", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Warrior", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Brute", "atk": 3, "hp": 4, "kw": ["piercing"]},
			{"name": "Brute", "atk": 3, "hp": 4, "kw": ["piercing"]},
			{"name": "Bannerman", "atk": 1, "hp": 3, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Chieftain", "atk": 4, "hp": 4, "kw": ["swift", "piercing"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Grunt", "atk": 2, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Warrior", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Brute", "atk": 3, "hp": 4, "kw": ["piercing"]},
		],
	},

	"necromancer_tower": {
		# Necromancer's Tower (Act 1 elite) — ENDLESS DEAD. Inspired by StS
		# Slime Boss: every kill makes the board WORSE — the necro_death_summon
		# passive spawns a Skeleton every time anything dies. Most creatures
		# have Last Stand or summon on death. The reactive double_on_death
		# already amplifies enemy deaths. Spell AoE > spot-killing.
		"name": "Where the Dead Come Back", "act": 1, "type": "elite", "faction": "owed", "hp": 15,
		"preamble": "Up in the tower a clerk keeps tallying, and down here the tally keeps standing back up. Outpace the count.",
		"passive_id": "necro_death_summon",
		"passive_desc": "When a non-Skeleton enemy dies: summon a 1/1 Skeleton in a random empty enemy lane.",
		"deck": [
			{"name": "Skeleton", "atk": 1, "hp": 1, "kw": ["last_stand"]},
			{"name": "Skeleton", "atk": 1, "hp": 1, "kw": ["last_stand"]},
			{"name": "Bone Knight", "atk": 2, "hp": 3, "kw": ["last_stand"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Bone Knight", "atk": 2, "hp": 3, "kw": ["last_stand"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Dark Acolyte", "atk": 1, "hp": 3, "kw": ["regenerate"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Lich", "atk": 3, "hp": 4, "kw": ["regenerate", "last_stand"],
				"on_death": {"type": "summon", "atk": 3, "hp": 3}},
		],
		"reinforcement": {"name": "Risen Bones", "atk": 1, "hp": 2, "kw": ["last_stand"]},
		"reinforcement_pool": [
			{"name": "Skeleton", "atk": 1, "hp": 1, "kw": ["last_stand"]},
			{"name": "Bone Knight", "atk": 2, "hp": 3, "kw": ["last_stand"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
		],
	},

	# =================== ACT 1 — BOSS =============================

	"iron_warden": {
		# Iron Warden (Act 1 boss) — THE SIEGE ENGINE CHARGES. Inspired by
		# StS Hexaghost: a back-row Trebuchet structure ticks up each round
		# (player_creature_enter feeds it via the pyre_ritual reactive
		# pattern — see EncounterEffects). When it crosses Charge 3, the
		# trebuchet IGNITION fires for AoE + face damage. Phase 2 (HP < 13)
		# adds the iron_warden_siege passive that armors every enemy.
		# Two clocks: the siege, and the phase shift. Plan for both.
		"name": "The Iron Warden", "act": 1, "type": "boss", "faction": "last_wall", "hp": 23,
		"passive_id": "siege_ritual",
		"passive_desc": "Each enemy death loads the Trebuchet (+1 Charge). At 3 it FIRES: deal 3 damage to all your creatures and 4 face damage.",
		"preamble": "It was built to hold a wall that no longer stands, and no one has told it the siege is over. Every death you hand it only loads it again.",
		"structures": [
			{"name": "Trebuchet", "atk": 0, "hp": 99,
				"kw": ["structure"], "charge_max": 3, "lane": 1},
		],
		"deck": [
			{"name": "Iron Sentinel", "atk": 3, "hp": 3, "kw": ["armored"]},
			{"name": "Iron Sentinel", "atk": 3, "hp": 3, "kw": ["armored"]},
			{"name": "Iron Guard", "atk": 2, "hp": 4, "kw": ["armored", "thorns"]},
			{"name": "Warden's Champion", "atk": 4, "hp": 3, "kw": ["swift", "piercing"]},
			{"name": "Iron Vanguard", "atk": 4, "hp": 4, "kw": ["armored", "last_stand"]},
			{"name": "Bombardier", "atk": 2, "hp": 2, "kw": ["armored"]},
		],
		"reinforcement": {"name": "Iron Recruit", "atk": 2, "hp": 2, "kw": ["armored"]},
	},

	"dragon_lord": {
		# Dragon Lord (Act 1 boss) — TWO BREATHS, TWO FORMS. Inspired by
		# Cuphead's dragon: phase 1 every enemy has Piercing (dragon_lord_piercing
		# passive), phase 2 (HP < 12) every enemy gets +1 ATK AND keeps
		# piercing (dragon_lord_phase2). The phase shift banner fires the
		# "ROAR" beat. Drakes are the chaff with claws; Wyrms heal back up;
		# Elder Drake is the centerpiece.
		"name": "The Wyrm-Father", "act": 1, "type": "boss", "faction": "everflame", "hp": 21,
		"passive_id": "dragon_lord_piercing",
		"passive_desc": "All enemy creatures have Piercing.",
		"preamble": "Something old coils across the road and calls it a nest. It has guarded this way longer than the meadow has burned, and it does not need your name.",
		"deck": [
			{"name": "Drake", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Drake", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Drake", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Wyrm", "atk": 3, "hp": 4, "kw": ["regenerate"]},
			{"name": "Wyrm", "atk": 3, "hp": 4, "kw": ["regenerate"]},
			{"name": "Hatchling Brood", "atk": 1, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Elder Drake", "atk": 4, "hp": 5, "kw": ["armored"],
				"on_enter": {"type": "damage_all_enemies", "value": 2}},
		],
		"reinforcement": {"name": "Whelp", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	# =================== ACT 2 — COMBAT ===========================

	"cultist_enclave": {
		# Cultist theme — DEATHS CASCADE. Every cultist goes out with a bang:
		# damage on death, debuffs on death, summons on death. Killing one
		# triggers another beat. The easy kills hurt you the most.
		"name": "The Bleeding-Heart Cell", "act": 2, "type": "combat", "faction": "owed", "hp": 16,
		"preamble": "They love you, the way a knife loves the whetstone. Every wound they take is one they meant to give away.",
		"passive_id": "cultist_buff",
		"passive_desc": "Start of each round: a random Cultist gains +1/+1.",
		"deck": [
			{"name": "Initiate", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Bleeding Heart", "atk": 2, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Hexer", "atk": 1, "hp": 3, "kw": ["thorns"],
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Zealot", "atk": 3, "hp": 3, "kw": ["piercing"],
				"on_death": {"type": "damage_face", "value": 2}},
			{"name": "Dark Priest", "atk": 2, "hp": 4, "kw": ["regenerate"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Devotee", "atk": 2, "hp": 2,
				"on_death": {"type": "damage_opposing", "value": 3}},
			{"name": "Fanatic", "atk": 4, "hp": 4, "kw": ["piercing"],
				"on_death": {"type": "damage_all_enemies", "value": 3}},
		],
		"deck_variants": [
			# Variant: bomb cell — three Bleeding Hearts, every kill bites back.
			[
				{"name": "Initiate", "atk": 2, "hp": 2, "kw": ["swift"],
					"on_death": {"type": "damage_face", "value": 1}},
				{"name": "Bleeding Heart", "atk": 2, "hp": 3,
					"on_death": {"type": "damage_all_enemies", "value": 2}},
				{"name": "Bleeding Heart", "atk": 2, "hp": 3,
					"on_death": {"type": "damage_all_enemies", "value": 2}},
				{"name": "Bleeding Heart", "atk": 2, "hp": 3,
					"on_death": {"type": "damage_all_enemies", "value": 2}},
				{"name": "Zealot", "atk": 3, "hp": 3, "kw": ["piercing"],
					"on_death": {"type": "damage_face", "value": 2}},
				{"name": "Fanatic", "atk": 4, "hp": 4, "kw": ["piercing"],
					"on_death": {"type": "damage_all_enemies", "value": 3}},
			],
			# Variant: cursed congregation — heavy on hex/curse cascades.
			[
				{"name": "Hexer", "atk": 1, "hp": 3, "kw": ["thorns"],
					"on_death": {"type": "debuff_all_player_atk", "value": 1}},
				{"name": "Hexer", "atk": 1, "hp": 3, "kw": ["thorns"],
					"on_death": {"type": "debuff_all_player_atk", "value": 1}},
				{"name": "Dark Priest", "atk": 2, "hp": 4, "kw": ["regenerate"],
					"on_death": {"type": "summon", "atk": 2, "hp": 2}},
				{"name": "Devotee", "atk": 2, "hp": 2,
					"on_death": {"type": "damage_opposing", "value": 3}},
				{"name": "Devotee", "atk": 2, "hp": 2,
					"on_death": {"type": "damage_opposing", "value": 3}},
				{"name": "Fanatic", "atk": 4, "hp": 4, "kw": ["piercing"],
					"on_death": {"type": "damage_all_enemies", "value": 3}},
			],
		],
		"reinforcement": {"name": "Devotee", "atk": 2, "hp": 2,
			"on_death": {"type": "damage_opposing", "value": 3}},
		"reinforcement_pool": [
			{"name": "Initiate", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Bleeding Heart", "atk": 2, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
		],
	},

	"swamp_horror": {
		# Swamp Horror — THE SWAMP HEALS ITSELF. With the swamp_thorns passive
		# every creature already has Thorns; most also Regenerate so chip
		# damage doesn't stick. The fight rewards big single hits over slow
		# grinds. Drowned is the only true wall (armored).
		"name": "The Drowned Garden", "act": 2, "type": "combat", "faction": "owed", "hp": 16,
		"preamble": "Someone kept a garden here before the water came up to stay. It is still growing. It has only changed what it grows.",
		"passive_id": "swamp_thorns",
		"passive_desc": "All enemy creatures have Thorns.",
		"deck": [
			{"name": "Mosquito", "atk": 2, "hp": 1, "kw": ["swift"]},
			{"name": "Bog Slime", "atk": 1, "hp": 3, "kw": ["regenerate"],
				"on_death": {"type": "summon", "atk": 1, "hp": 2}},
			{"name": "Tendril", "atk": 3, "hp": 2, "kw": ["regenerate"]},
			{"name": "Drowned", "atk": 2, "hp": 6, "kw": ["armored", "regenerate"]},
			{"name": "Mire Druid", "atk": 1, "hp": 3, "kw": ["regenerate"],
				"adj_buff": {"atk": 0, "hp": 1}},
			{"name": "Leech", "atk": 2, "hp": 3, "kw": ["regenerate"]},
			{"name": "Bog Beast", "atk": 4, "hp": 5, "kw": ["regenerate"]},
		],
		"deck_variants": [
			# Variant: regen wall — three regen creatures, very slow grind.
			[
				{"name": "Mosquito", "atk": 2, "hp": 1, "kw": ["swift"]},
				{"name": "Bog Slime", "atk": 1, "hp": 3, "kw": ["regenerate"],
					"on_death": {"type": "summon", "atk": 1, "hp": 2}},
				{"name": "Bog Slime", "atk": 1, "hp": 3, "kw": ["regenerate"],
					"on_death": {"type": "summon", "atk": 1, "hp": 2}},
				{"name": "Drowned", "atk": 2, "hp": 6, "kw": ["armored"]},
				{"name": "Leech", "atk": 1, "hp": 3, "kw": ["regenerate"]},
				{"name": "Bog Beast", "atk": 4, "hp": 5, "kw": ["regenerate"]},
			],
			# Variant: ambush pool — swift + ranged-heavy, no big bruiser.
			[
				{"name": "Mosquito", "atk": 2, "hp": 1, "kw": ["swift"]},
				{"name": "Mosquito", "atk": 2, "hp": 1, "kw": ["swift"]},
				{"name": "Tendril", "atk": 3, "hp": 2, "kw": []},
				{"name": "Tendril", "atk": 3, "hp": 2, "kw": []},
				{"name": "Mire Druid", "atk": 1, "hp": 3,
					"adj_buff": {"atk": 0, "hp": 1}},
				{"name": "Witch Doctor", "atk": 2, "hp": 3,
					"intents": ["ATK", "ABILITY", "ATK", "ABILITY"],
					"ability": {"type": "heal_all", "value": 2}},
				{"name": "Drowned", "atk": 2, "hp": 6, "kw": ["armored"]},
			],
		],
		"reinforcement": {"name": "Leech", "atk": 1, "hp": 3, "kw": ["regenerate"]},
		"reinforcement_pool": [
			{"name": "Mosquito", "atk": 2, "hp": 1, "kw": ["swift"]},
			{"name": "Tendril", "atk": 3, "hp": 2, "kw": []},
		],
	},

	"mercenary_company": {
		# Mercenary Company — DISCIPLINED RANKS. Buffer-heavy: Lieutenant /
		# Standard Bearer / Captain make weak soldiers strong. The merc_piercing
		# passive turns any 4+ ATK creature (buffed or natural) into a face
		# threat. Kill the buffers first or trade horribly with the puffed-up
		# line.
		"name": "The Coin-Sworn", "act": 2, "type": "combat", "faction": "last_wall", "hp": 15,
		"preamble": "They have no quarrel with you, only a contract — and a paid man, unlike an angry one, has nothing left to talk down.",
		"passive_id": "merc_piercing",
		"passive_desc": "Enemy creatures with 4 or more ATK have Piercing.",
		"deck": [
			{"name": "Recruit", "atk": 2, "hp": 3, "kw": ["armored"]},
			{"name": "Pikeman", "atk": 1, "hp": 4, "kw": ["thorns", "armored"]},
			{"name": "Crossbowman", "atk": 2, "hp": 2, "kw": []},
			{"name": "Lieutenant", "atk": 1, "hp": 4, "kw": ["armored"],
				"adj_buff": {"atk": 2, "hp": 0}},
			{"name": "Standard Bearer", "atk": 1, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0},
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Veteran", "atk": 3, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Captain", "atk": 2, "hp": 5, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Camp Follower", "atk": 1, "hp": 3,
			"adj_buff": {"atk": 1, "hp": 0}},
		"reinforcement_pool": [
			{"name": "Recruit", "atk": 2, "hp": 3, "kw": ["armored"]},
			{"name": "Crossbowman", "atk": 2, "hp": 2, "kw": []},
		],
	},

	"haunted_crypt": {
		# Crypt theme — THE DEAD KEEP RISING. Every creature either summons
		# more on death, survives lethal hits (last_stand), or is itself a
		# summon from another dying enemy. Killing makes the board WORSE.
		# Players have to learn to leave certain creatures alive.
		"name": "The Crypt That Will Not Stay Shut", "act": 2, "type": "combat", "faction": "owed", "hp": 17,
		"preamble": "The door was sealed for a reason, and the reason is still inside, working the latch. It does not care to be read to.",
		"passive_id": "crypt_ghost",
		"passive_desc": "When an enemy creature dies: summon a 1/1 Swift Ghost in a random empty enemy lane.",
		"deck": [
			{"name": "Bone Walker", "atk": 2, "hp": 2, "kw": ["last_stand"],
				"on_death": {"type": "summon", "atk": 1, "hp": 1}},
			{"name": "Skeleton", "atk": 2, "hp": 1, "kw": ["last_stand"]},
			{"name": "Crypt Spider", "atk": 3, "hp": 2, "kw": ["piercing", "swift"]},
			{"name": "Wraith", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Banshee", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Gravewarden", "atk": 2, "hp": 6, "kw": ["armored", "last_stand"]},
			{"name": "Risen Lich", "atk": 4, "hp": 4, "kw": ["piercing"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
		],
		"reinforcement": {"name": "Risen", "atk": 2, "hp": 2, "kw": ["last_stand"]},
		"reinforcement_pool": [
			{"name": "Skeleton", "atk": 2, "hp": 1, "kw": ["last_stand"]},
			{"name": "Wraith", "atk": 3, "hp": 3, "kw": ["swift"]},
		],
	},

	"fire_giants_forge": {
		# Fire Giant's Forge — HOT TO TOUCH, HOT TO HIT. Nearly every creature
		# has Armored or Thorns (forged metal / glowing coals); chip damage
		# rains down from forge_burn_all + Slag Heap detonations. Even
		# ignoring the board drains HP fast.
		"name": "The Forge That Eats", "act": 2, "type": "combat", "faction": "everflame", "hp": 18,
		"preamble": "The fire here is never allowed to die, and it is always a little hungry. The smiths feed it what the road sends.",
		"passive_id": "forge_heat",
		"passive_desc": "Start of each round: deal 1 damage to all your creatures (2 from round 3), bypassing armor. The forge's own do not burn.",
		"deck": [
			{"name": "Apprentice", "atk": 1, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Ember", "atk": 2, "hp": 1, "kw": ["swift"]},
			{"name": "Coal Carrier", "atk": 1, "hp": 4, "kw": ["thorns", "armored"]},
			{"name": "Forgeling", "atk": 3, "hp": 3, "kw": ["armored", "thorns"]},
			{"name": "Hammerer", "atk": 3, "hp": 3, "kw": ["armored"],
				"on_enter": {"type": "damage_opposing", "value": 2}},
			{"name": "Slag Heap", "atk": 0, "hp": 6, "kw": ["armored", "thorns"],
				"on_death": {"type": "damage_opposing_lane", "value": 3}},
			{"name": "Fire Giant", "atk": 4, "hp": 5, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Cinder Sprite", "atk": 1, "hp": 1, "kw": ["swift"],
			"on_enter": {"type": "damage_face", "value": 1}},
		"reinforcement_pool": [
			{"name": "Ember", "atk": 2, "hp": 1, "kw": ["swift"]},
			{"name": "Forgeling", "atk": 3, "hp": 3, "kw": ["armored", "thorns"]},
		],
	},

	"oathbroken_knights": {
		# Oath-Broken Knights — ARMORED AND VENGEFUL. Every knight is Armored
		# or carries Piercing (or both). The flock has a Standard Bearer
		# buffing adjacents, a Fallen Paladin healing, and a Forsworn Champion
		# that refuses to die clean (Last Stand). Slow but punishing trades.
		"name": "The Faithless Lances", "act": 2, "type": "combat", "faction": "last_wall", "hp": 17,
		"preamble": "They swore the oaths you would want at your back, broke them somewhere on this road, and found the breaking suited them.",
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Squire", "atk": 2, "hp": 2, "kw": ["armored"]},
			{"name": "Black Lancer", "atk": 4, "hp": 2, "kw": ["swift", "piercing"]},
			{"name": "Crossbow Knight", "atk": 2, "hp": 3, "kw": ["armored"]},
			{"name": "Fallen Knight", "atk": 3, "hp": 5, "kw": ["armored", "piercing"]},
			{"name": "Standard Bearer", "atk": 1, "hp": 4, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0},
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Fallen Paladin", "atk": 2, "hp": 4, "kw": ["armored", "regenerate"]},
			{"name": "Forsworn Champion", "atk": 4, "hp": 5, "kw": ["armored", "last_stand"]},
		],
		"reinforcement": {"name": "Footman", "atk": 2, "hp": 3, "kw": ["armored"]},
		"reinforcement_pool": [
			{"name": "Squire", "atk": 2, "hp": 2, "kw": ["armored"]},
			{"name": "Crossbow Knight", "atk": 2, "hp": 3, "kw": ["armored"]},
		],
	},

	"ash_hounds": {
		# Ash Hounds — BURNING PACK. Every hound is Swift (chase) and most
		# carry Thorns or Piercing (burning to touch / fangs through armor).
		# Forge_burn_all chip damage burns them too, but they're disposable
		# — the pack is built to rush you down before round 4.
		"name": "The Cinder-Hounds", "act": 2, "type": "combat", "faction": "everflame", "hp": 16,
		"preamble": "They were dogs once, before the burning got into them. Now they run where the smoke runs, always downwind of dying.",
		"passive_id": "pack_hunt",
		"passive_desc": "When one of your creatures dies: all Swift enemies gain +1 ATK this round.",
		"deck": [
			{"name": "Cinder Pup", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Ash Hound", "atk": 4, "hp": 2, "kw": ["swift", "piercing"], "wither": 1},
			{"name": "Smoldering Crow", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Char-Hide", "atk": 1, "hp": 5, "kw": ["thorns", "armored"]},
			{"name": "Pack-Master", "atk": 2, "hp": 4, "kw": ["swift"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Ember Stalker", "atk": 3, "hp": 3, "kw": ["swift", "piercing"]},
			{"name": "Houndmaster", "atk": 3, "hp": 5, "kw": ["swift"],
				"on_death": {"type": "damage_face", "value": 3}},
		],
		"reinforcement": {"name": "Cinder Pup", "atk": 2, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Ash Hound", "atk": 4, "hp": 2, "kw": ["swift", "piercing"], "wither": 1},
			{"name": "Smoldering Crow", "atk": 2, "hp": 2, "kw": ["swift"]},
		],
	},

	"carrion_choir": {
		# The Carrion Choir (Act 2 combat) — DEATH FROM THE BACK ROW, AND IT
		# SCREAMS. A murder of carrion birds + scavengers that lives in the back
		# row: almost everything is Ranged (the flock snipes past your blockers),
		# and every bird shrieks a chip of face damage when it dies (on_death
		# damage_face), so trading INTO them costs you life too. The cultist_buff
		# passive makes a random bird swell +1/+1 each round — the murder grows
		# louder the longer you let it sing. Distinct from the crypt (no endless
		# summons) and the act-3 Killing Choir (no snipe): here the threat is
		# pure back-row volume you have to reach and silence. Push damage onto the
		# singers fast or get pecked to death.
		"name": "The Carrion Choir", "act": 2, "type": "combat", "faction": "owed", "hp": 16,
		"preamble": "They have followed the column for days, singing the only hymn they know. They are very good at it, and it is nearly done.",
		"passive_id": "dirge_swell",
		"passive_desc": "Start of each round: each surviving crow deals 1 face damage. Silence the choir.",
		"deck": [
			{"name": "Crow", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Raven", "atk": 2, "hp": 2, "kw": [],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Raven", "atk": 2, "hp": 2, "kw": [],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Smoldering Crow", "atk": 3, "hp": 3, "kw": [],
				"on_death": {"type": "damage_face", "value": 2}},
			{"name": "Stitched Hand", "atk": 2, "hp": 4, "kw": ["thorns"]},
			{"name": "Gravedigger", "atk": 2, "hp": 4, "kw": [],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Maestro", "atk": 3, "hp": 5, "kw": [],
				"on_death": {"type": "damage_all_enemies", "value": 2}},
		],
		"deck_variants": [
			# Variant: open grave — scavengers up front, fewer fliers. The
			# corpse-eaters wall while the back row still shrieks.
			[
				{"name": "Crow", "atk": 2, "hp": 2, "kw": ["swift"],
					"on_death": {"type": "damage_face", "value": 1}},
				{"name": "Raven", "atk": 2, "hp": 2, "kw": [],
					"on_death": {"type": "damage_face", "value": 1}},
				{"name": "Husk", "atk": 3, "hp": 4, "kw": ["thorns"]},
				{"name": "Husk", "atk": 3, "hp": 4, "kw": ["thorns"]},
				{"name": "Smoldering Crow", "atk": 3, "hp": 3, "kw": [],
					"on_death": {"type": "damage_face", "value": 2}},
				{"name": "Maestro", "atk": 3, "hp": 5, "kw": [],
					"on_death": {"type": "damage_all_enemies", "value": 2}},
			],
		],
		"reinforcement": {"name": "Crow", "atk": 2, "hp": 2, "kw": ["swift"],
			"on_death": {"type": "damage_face", "value": 1}},
		"reinforcement_pool": [
			{"name": "Raven", "atk": 2, "hp": 2, "kw": [],
				"on_death": {"type": "damage_face", "value": 1}},
			{"name": "Smoldering Crow", "atk": 3, "hp": 3, "kw": [],
				"on_death": {"type": "damage_face", "value": 2}},
		],
	},

	# ── 2026-07-03 act-2 pool widening: the middle act had 8 combats to act 1's
	# 12 (the samey-est stretch of the run), and NONE flying grasswake or
	# lanternhall colors — a player marching on those lords fought only
	# borrowed fights. Four new lineups, all reusing PROVEN passive handlers
	# (harpy_swift_face / wolf_pack_revenge / mirror_instant_place /
	# glass_refract) and art-backed creature names, so no new Combat.gd code.

	"outriders_hour": {
		# Grasswake tempo — THE EMPTY LANE IS THEIR HIGHWAY. Swift riders that
		# punch face harder wherever you leave a column open. The fight teaches
		# act-2 board discipline: hold every lane or bleed for the gaps. Bodies
		# are lean (they trade badly) — the threat is the tempo, not the stats.
		"name": "The Outriders' Hour", "act": 2, "type": "combat", "faction": "grasswake", "hp": 16,
		"preamble": "You hear them before you see them, and you see them exactly once. The grass bends the wrong way, and then the hour is theirs.",
		"passive_id": "harpy_swift_face",
		"passive_desc": "Enemy Swift creatures deal +1 face damage when attacking through empty lanes.",
		"deck": [
			{"name": "Flanker", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Flanker", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Stalker", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Bloodfang", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Slinger", "atk": 2, "hp": 3, "kw": [],
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Captain", "atk": 3, "hp": 5, "kw": [],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"deck_variants": [
			# Variant: the double column — two captains drumming two wings.
			[
				{"name": "Flanker", "atk": 3, "hp": 2, "kw": ["swift"]},
				{"name": "Stalker", "atk": 2, "hp": 3, "kw": ["swift"]},
				{"name": "Captain", "atk": 3, "hp": 5, "kw": [],
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Captain", "atk": 3, "hp": 5, "kw": [],
					"adj_buff": {"atk": 1, "hp": 0}},
				{"name": "Bloodfang", "atk": 4, "hp": 3, "kw": ["swift"]},
			],
		],
		"reinforcement": {"name": "Flanker", "atk": 3, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Stalker", "atk": 2, "hp": 3, "kw": ["swift"]},
		],
	},

	"grass_that_hunts": {
		# Grasswake pack — GRIEF IS A WHETSTONE. Every death sharpens the wolves
		# beside it (wolf_pack_revenge), so sweeping the pack left-to-right walks
		# your own damage into ever-angrier teeth. Kill from the EDGES in, or
		# burst the Den Mother before the pack notices. Act-2 sequel to act 1's
		# Den Mother's Brood — the cubs grew up.
		"name": "The Grass That Hunts", "act": 2, "type": "combat", "faction": "grasswake", "hp": 17,
		"preamble": "The brood you scattered in the foothills had an older litter. It has been following you at exactly the pace you march.",
		"passive_id": "wolf_pack_revenge",
		"passive_desc": "When an enemy creature dies: adjacent enemies gain +1 ATK this round.",
		"deck": [
			{"name": "Pack Wolf", "atk": 3, "hp": 3, "kw": []},
			{"name": "Pack Wolf", "atk": 3, "hp": 3, "kw": []},
			{"name": "Yearling", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Alpha", "atk": 4, "hp": 4, "kw": [],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Bloodfang", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Den Mother", "atk": 3, "hp": 6, "kw": ["regenerate"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
		],
		"reinforcement": {"name": "Pack Wolf", "atk": 3, "hp": 3, "kw": []},
		"reinforcement_pool": [
			{"name": "Yearling", "atk": 2, "hp": 3, "kw": ["swift"]},
		],
	},

	"borrowed_faces": {
		# Lanternhall foresight — THEY SAW THIS TRADE COMING. Every death on
		# YOUR side is answered instantly (mirror_instant_place), so chump-
		# blocking and cheap sacrifices hand the Hall free tempo. Keep your
		# creatures alive and the mirror stays quiet. Lighter act-2 cousin of
		# act 3's Hall of Wrong Reflections.
		"name": "The Borrowed Faces", "act": 2, "type": "combat", "faction": "lanternhall", "hp": 16,
		"preamble": "The watchers wear faces one march out of date. Yours is among them, worn slightly wrong, listening to your orders before you give them.",
		"passive_id": "mirror_instant_place",
		"passive_desc": "When a friendly creature dies: the enemy draws and places a creature immediately.",
		"deck": [
			{"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": []},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": []},
			{"name": "Doppel", "atk": 3, "hp": 3, "kw": [],
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Hall-Watcher", "atk": 2, "hp": 5, "kw": ["armored"]},
			{"name": "Shattered Twin", "atk": 4, "hp": 2, "kw": ["piercing"]},
		],
		"reinforcement": {"name": "Reflection", "atk": 2, "hp": 3, "kw": []},
		"reinforcement_pool": [
			{"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
		],
	},

	"signal_glass": {
		# Lanternhall glass — THE MIRRORS KEEP MAKING KNIVES. From round 2 a
		# 3/1 Swift shard forms in an empty enemy lane every round
		# (glass_refract): brittle bodies you must keep sweeping or they cut
		# face. Board-wipe value swings this fight; so does simply killing the
		# face before the glass adds up. Combat-scale preview of act 3's
		# Glass Menagerie.
		"name": "The Signal Glass", "act": 2, "type": "combat", "faction": "lanternhall", "hp": 17,
		"preamble": "On the ridge a mirror turns, catching the sun in slow code. Down here, everything it spells arrives edge-first.",
		"passive_id": "glass_refract",
		"passive_desc": "Start of each round (from round 2): a 3/1 Swift glass shard forms in an empty enemy lane.",
		"deck": [
			{"name": "Glass Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Glass Sniper", "atk": 2, "hp": 2, "kw": [], "sniper": true},
			{"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": []},
			{"name": "Glass Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
		],
		"reinforcement": {"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	# =================== ACT 2 — ELITE ============================

	"demon_vanguard": {
		# Demon Vanguard (Act 2 elite) — SPELLS FEED THE WAR. Inspired by MtG
		# Phyrexian War: the demon_spell_buff passive permanently buffs a
		# random enemy every time you cast. The roster is deliberately varied
		# so EVERY enemy is scary to buff — there's no "safe" target the
		# spell buff can land on. Soldiers wall, Hellhounds chase, Pit Fiend
		# grows, Infernal nukes. The fight says "every spell is a tradeoff."
		"name": "The Threshold Choir", "act": 2, "type": "elite", "faction": "everflame", "hp": 25,
		"preamble": "This is the door the deeper war keeps, held by things never born on your side of it. Past here, no prayer answers.",
		"passive_id": "demon_spell_buff",
		"passive_desc": "When you cast a spell: a random enemy creature gains +1 ATK for the rest of the fight.",
		"deck": [
			{"name": "Demon Soldier", "atk": 2, "hp": 5, "kw": ["armored"]},
			{"name": "Demon Soldier", "atk": 2, "hp": 5, "kw": ["armored"]},
			{"name": "Hellhound", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Hellhound", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Pit Fiend", "atk": 3, "hp": 6, "kw": ["regenerate"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Imp", "atk": 1, "hp": 3, "kw": [],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Infernal", "atk": 4, "hp": 4, "kw": ["piercing"],
				"on_death": {"type": "damage_face", "value": 3}},
		],
		"reinforcement": {"name": "Imp", "atk": 1, "hp": 3, "kw": [],
			"on_enter": {"type": "damage_face", "value": 1}},
		"reinforcement_pool": [
			{"name": "Hellhound", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Demon Soldier", "atk": 2, "hp": 5, "kw": ["armored"]},
		],
	},

	"puppeteer": {
		# The Puppeteer (Act 2 elite) — PUPPETS ON STRINGS. Inspired by Hollow
		# Knight Mantis Lords and Inscryption's clockwork puppets: marionettes
		# clog every lane, and the puppet_keyword_copy passive steals YOUR
		# best keywords each round and slaps them onto an enemy. Built tall
		# (lots of bodies), buffed wide (passive). Sweep wide, not deep.
		"name": "The Puppeteer", "act": 2, "type": "elite", "faction": "lanternhall", "hp": 23,
		"preamble": "Every soldier you raise, it counts as a gift. The strings are already knotted — you simply cannot see them yet.",
		"passive_id": "puppet_keyword_copy",
		"passive_desc": "Start of each round: copy the keywords from your highest-ATK creature onto a random enemy.",
		"deck": [
			{"name": "Marionette", "atk": 2, "hp": 3,
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Marionette", "atk": 2, "hp": 3,
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Marionette", "atk": 2, "hp": 3,
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Marionette", "atk": 2, "hp": 3,
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Puppet Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Puppet Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Shadow Double", "atk": 3, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Puppeteer's Guard", "atk": 3, "hp": 5, "kw": ["armored", "thorns"]},
		],
		"reinforcement": {"name": "String Wraith", "atk": 1, "hp": 2, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Marionette", "atk": 2, "hp": 3,
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Shadow Double", "atk": 3, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
		],
	},

	"horse_lords_toll": {
		# Grasswake elite (2026-07-03, part of the act-2 widening — the act had
		# only everflame/lanternhall Generals). EVERY LOSS FEEDS THE CHARGE:
		# pack_hunt turns each of YOUR deaths into +1 ATK on all Swift enemies
		# this round, and most of the column is Swift. Trading bodies into the
		# riders arms them; the fight rewards Armored walls, healing, and
		# killing the Chief (the adj-buff heart) before the toll compounds.
		"name": "The Horse-Lords' Toll", "act": 2, "type": "elite", "faction": "grasswake", "hp": 24,
		"preamble": "The toll here is not coin. The riders count what falls on your side of the line and pay themselves accordingly.",
		"passive_id": "pack_hunt",
		"passive_desc": "When one of your creatures dies: all Swift enemies gain +1 ATK this round.",
		"deck": [
			{"name": "Flanker", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Flanker", "atk": 3, "hp": 3, "kw": ["swift"]},
			{"name": "Bloodfang", "atk": 4, "hp": 4, "kw": ["swift"]},
			{"name": "Chief", "atk": 3, "hp": 7, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Alpha", "atk": 4, "hp": 5, "kw": [],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Stalker", "atk": 2, "hp": 4, "kw": ["swift"]},
			{"name": "Banner-Bearer", "atk": 2, "hp": 5, "kw": [],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Flanker", "atk": 3, "hp": 3, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Stalker", "atk": 2, "hp": 4, "kw": ["swift"]},
		],
	},

	# =================== ACT 2 — BOSS =============================

	"collector": {
		# The Collector (Act 2 boss) — DON'T PLAY YOUR HAND. Inspired by
		# Inscryption's Leshy: every creature you play heals the Collector
		# (collector_heal passive). Phase 2 doubles the heal AND buffs a
		# random enemy ATK. The fight rewards SPELL decks; punishes wide
		# board strategies. Deck is full of slow walls and an armored
		# Display Case — they don't kill you fast, but every turn you build
		# board, you lose your win condition (the boss heals back up).
		"name": "The Collector", "act": 2, "type": "boss", "faction": "lanternhall", "hp": 31,
		"passive_id": "collector_heal",
		"passive_desc": "When you play a creature from your hand: the Collector heals 1 HP.",
		"preamble": "It keeps things. Faces, mostly — the ones the road wears out. It has been saving a place for yours, and it is patient about filling it.",
		"deck": [
			{"name": "Collector Golem", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Collector Golem", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Collector Golem", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Display Case", "atk": 2, "hp": 5, "kw": ["armored", "thorns"]},
			{"name": "Collector's Pride", "atk": 4, "hp": 4, "kw": ["armored"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Soul Cage", "atk": 3, "hp": 3, "kw": ["regenerate"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Collector's Champion", "atk": 4, "hp": 5, "kw": ["swift", "armored"]},
		],
		"reinforcement": {"name": "Trinket", "atk": 2, "hp": 3, "kw": ["armored"]},
	},

	"hollow_king": {
		# Hollow King (Act 2 boss) — THE EYE THAT JUDGES. Inspired by
		# Bloodborne's One Reborn: every round, the hollow_king_snipe
		# passive deals 3 damage to your highest-ATK creature. Wide-board
		# strategies survive; tall single-threat strategies bleed. Phase 2
		# (hollow_king_phase2) snipes the TOP TWO and adds a Curse to your
		# discard. Deck: chaff bodies that don't matter if they die — the
		# pressure is the passive, not the creatures.
		"name": "The Hollow King", "act": 2, "type": "boss", "faction": "owed", "hp": 31,
		"passive_id": "hollow_king_snipe",
		"passive_desc": "Start of each round: deal 3 damage to your highest-ATK creature.",
		"preamble": "There is an eye here that decides what gets to continue. It has looked at you before and found you wanting. It is willing to look again.",
		"deck": [
			{"name": "Hollow Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Hollow Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Hollow Knight", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Void Guard", "atk": 1, "hp": 5, "kw": ["armored", "regenerate"]},
			{"name": "Shadow Blade", "atk": 3, "hp": 2, "kw": ["swift", "piercing"]},
			{"name": "Shadow Blade", "atk": 3, "hp": 2, "kw": ["swift", "piercing"]},
			{"name": "Hollow Champion", "atk": 4, "hp": 4, "kw": ["last_stand", "piercing"]},
		],
		"reinforcement": {"name": "Shade Knight", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	"the_bellringer": {
		# THE BELLRINGER (Act 2 boss) — THE BELL TOLLS, THE CLOCK STARTS.
		# The signature, telegraphed mechanic, built entirely on the `doom`
		# keyword. The Bellringer is a doomsday zealot who rings a great cracked
		# bell: the doom_bell passive (handler in Combat.gd's
		# _dispatch_passive_start_of_round wrapper) makes him DEPLOY a "Doomspawn"
		# bomb-creature into an empty lane every other round. Each Doomspawn shows
		# an unmistakable on-board countdown — Doom 2 → 1 → it DETONATES straight
		# into your face for 6. They have low HP, so you CAN defuse them in time
		# — but while any Doomspawn is ticking, every other enemy gets +1 ATK
		# (the toll empowers the host), so ignoring the clock is doubly costly.
		# At round 6 the bell cracks wide open and tolls a DOUBLE peal (two bombs
		# at once). The standing deck — demons and reapers — punishes you for
		# turtling, so you can't just hide behind walls and wait the fuses out.
		# Triage or die: the loudest clock in the game.
		"name": "THE BELLRINGER", "act": 2, "type": "boss", "faction": "everflame", "hp": 30,
		"passive_id": "doom_bell",
		"passive_desc": "Every other round the Bell TOLLS: a Doomspawn (Doom 2) drops in. While one ticks, all other enemies gain +1 ATK.",
		"preamble": "He has rung for the end since before you were born, and he is nearly finished. Every toll is a number, and the numbers only go down.",
		"deck": [
			{"name": "Demon Soldier", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4, "kw": ["armored"]},
			{"name": "Hellfire Imp", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 1}},
			{"name": "Cinder", "atk": 1, "hp": 3, "kw": ["doom"], "doom": 2, "doom_damage": 5},
			{"name": "Soul Reaper", "atk": 3, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["regenerate"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Dark Priest", "atk": 2, "hp": 5, "kw": ["thorns"],
				"on_death": {"type": "damage_face", "value": 3}},
		],
		"reinforcement": {"name": "Lesser Demon", "atk": 3, "hp": 3, "kw": ["piercing"]},
	},

	# =================== ACT 3 — COMBAT ===========================

	"mirror_temple": {
		# Mirror Temple — YOUR OWN POWER REFLECTED. Reflection copies your
		# keywords, Shattered Twin spawns more glass on death, the temple
		# refills lanes the instant your creatures die. Defensive trades
		# barely work — every kill triggers a fresh enemy beat.
		"name": "The Hall of Wrong Reflections", "act": 3, "type": "combat", "faction": "lanternhall", "hp": 20,
		"preamble": "Every surface shows you back a little wrong, a little ahead. By the time you tell which reflection lies, it has moved.",
		"passive_id": "mirror_instant_place",
		"passive_desc": "When a friendly creature dies: the enemy draws and places a creature immediately.",
		"deck": [
			{"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Glass Sniper", "atk": 3, "hp": 2, "kw": ["piercing"], "sniper": true},
			{"name": "Hall-Watcher", "atk": 1, "hp": 6, "kw": ["thorns", "armored"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Chorus of Echoes", "atk": 1, "hp": 4,
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Shattered Twin", "atk": 3, "hp": 3, "kw": ["piercing"],
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Doppel", "atk": 2, "hp": 4, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
		],
		"deck_variants": [
			# Variant: house of doubles — reflections and shattered twins stack,
			# meaning the player's own keywords get mirrored back fast.
			[
				{"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
				{"name": "Reflection", "atk": 2, "hp": 3,
					"on_enter": {"type": "copy_opposing_keywords"}},
				{"name": "Reflection", "atk": 2, "hp": 3,
					"on_enter": {"type": "copy_opposing_keywords"}},
				{"name": "Shattered Twin", "atk": 3, "hp": 3,
					"on_death": {"type": "summon", "atk": 2, "hp": 2}},
				{"name": "Shattered Twin", "atk": 3, "hp": 3,
					"on_death": {"type": "summon", "atk": 2, "hp": 2}},
				{"name": "Doppel", "atk": 2, "hp": 4,
					"intents": ["ATK", "ABILITY", "ATK", "ABILITY"],
					"ability": {"type": "steal_atk", "value": 2}},
			],
		],
		"reinforcement": {"name": "Glass Shard", "atk": 2, "hp": 2},
		"reinforcement_pool": [
			{"name": "Mirror Wisp", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Glass Sniper", "atk": 3, "hp": 2, "kw": [], "sniper": true},
		],
	},

	"elemental_nexus": {
		# Elemental Nexus — EVERY KEYWORD AT ONCE. Each sprite embodies one
		# element via its keyword (Flame=swift, Ice=armored, Storm=piercing,
		# Tide=regen, Stone=thorns, Shadow=swift+on_enter chip). The nexus_rotation
		# passive amps the whole board on a 3-round cycle. The puzzle is "no
		# single counter covers all of them."
		"name": "The Storm Made Flesh", "act": 3, "type": "combat", "faction": "grasswake", "hp": 21,
		"preamble": "The weather over the high passes grew tired of being weather. It has taken a shape, and the shape is walking down.",
		"passive_id": "nexus_rotation",
		"passive_desc": "Repeating cycle. R1: all enemies gain +1 ATK. R2: all enemies heal 2 HP. R3: all enemies gain Thorns this round.",
		"deck": [
			{"name": "Flame Sprite", "atk": 4, "hp": 1, "kw": ["swift", "piercing"],
				"on_death": {"type": "damage_all_enemies", "value": 1}},
			{"name": "Ice Sprite", "atk": 1, "hp": 5, "kw": ["armored", "thorns"]},
			{"name": "Storm Sprite", "atk": 2, "hp": 2, "kw": ["piercing"]},
			{"name": "Tide Sprite", "atk": 2, "hp": 3, "kw": ["regenerate"]},
			{"name": "Stone Sprite", "atk": 1, "hp": 4, "kw": ["thorns", "armored"]},
			{"name": "Shadow Sprite", "atk": 3, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "damage_random_player", "value": 2}},
			{"name": "Nexus Core", "atk": 2, "hp": 5, "kw": ["armored"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"deck_variants": [
			# Variant: fire-coil — fire/shadow leaning, no regen, hits hard early.
			[
				{"name": "Flame Sprite", "atk": 4, "hp": 1, "kw": ["swift"],
					"on_death": {"type": "damage_all_enemies", "value": 1}},
				{"name": "Flame Sprite", "atk": 4, "hp": 1, "kw": ["swift"],
					"on_death": {"type": "damage_all_enemies", "value": 1}},
				{"name": "Storm Sprite", "atk": 2, "hp": 2, "kw": ["piercing"]},
				{"name": "Shadow Sprite", "atk": 3, "hp": 2,
					"on_enter": {"type": "damage_random_player", "value": 2}},
				{"name": "Shadow Sprite", "atk": 3, "hp": 2,
					"on_enter": {"type": "damage_random_player", "value": 2}},
				{"name": "Nexus Core", "atk": 2, "hp": 5,
					"adj_buff": {"atk": 1, "hp": 0},
					"intents": ["RALLY", "ATK", "ABILITY", "RALLY"],
					"ability": {"type": "warcry", "value": 1}},
			],
		],
		"reinforcement": {"name": "Spark", "atk": 2, "hp": 1, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Flame Sprite", "atk": 4, "hp": 1, "kw": ["swift"],
				"on_death": {"type": "damage_all_enemies", "value": 1}},
			{"name": "Stone Sprite", "atk": 1, "hp": 4, "kw": ["thorns"]},
		],
	},

	"executioners_block": {
		# Executioner's Block — EVERYTHING PIERCES. Torture chamber: every
		# enemy carries Piercing (the executioner's blade goes through armor)
		# or detonates on death (Bound Prisoner's hidden bomb). The passive
		# adds face damage from the highest ATK each round, so trades that
		# leave their heavy hitter alive bleed you out fast.
		"name": "The Executioner's Block", "act": 3, "type": "combat", "faction": "last_wall", "hp": 19,
		"preamble": "The wood is dark and certain, and the man beside it never asks what you did. He only asks whether you will kneel.",
		"passive_id": "executioner_face",
		"passive_desc": "Each round: the highest-ATK enemy also deals its ATK as face damage.",
		"deck": [
			{"name": "Jailer", "atk": 2, "hp": 3, "kw": ["piercing"]},
			{"name": "Crossbow Guard", "atk": 2, "hp": 2, "kw": ["piercing"]},
			{"name": "Tormentor", "atk": 4, "hp": 3, "kw": ["swift", "piercing"],
				"on_enter": {"type": "damage_face", "value": 2}},
			{"name": "Iron Maiden", "atk": 1, "hp": 6, "kw": ["thorns", "armored"]},
			{"name": "Inquisitor", "atk": 2, "hp": 4, "kw": ["piercing"],
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Bound Prisoner", "atk": 0, "hp": 5,
				"on_death": {"type": "damage_opposing", "value": 4}},
			{"name": "Executioner", "atk": 5, "hp": 5, "kw": ["piercing"]},
		],
		"deck_variants": [
			# Variant: gallows trap — Bound Prisoners stack as living bombs.
			[
				{"name": "Jailer", "atk": 2, "hp": 3},
				{"name": "Whipman", "atk": 2, "hp": 3},
				{"name": "Bound Prisoner", "atk": 0, "hp": 5,
					"on_death": {"type": "damage_opposing", "value": 4}},
				{"name": "Bound Prisoner", "atk": 0, "hp": 5,
					"on_death": {"type": "damage_opposing", "value": 4}},
				{"name": "Iron Maiden", "atk": 1, "hp": 6, "kw": ["thorns", "armored"]},
				{"name": "Inquisitor", "atk": 2, "hp": 4,
					"intents": ["ATK", "ABILITY", "ATK", "ABILITY"],
					"ability": {"type": "mark"}},
				{"name": "Executioner", "atk": 5, "hp": 5, "kw": ["piercing"]},
			],
		],
		"reinforcement": {"name": "Whipman", "atk": 2, "hp": 3},
		"reinforcement_pool": [
			{"name": "Jailer", "atk": 2, "hp": 3},
			{"name": "Crossbow Guard", "atk": 2, "hp": 2, "kw": []},
		],
	},

	"dragons_lair": {
		# Dragon's Lair — SCALES AND CLAWS. Every dragon carries Armored
		# (thick scales) or Piercing (claws/teeth through anything). The
		# whelps and kobolds are the only chaff; the rest are statline
		# threats. The periodic AoE passive punishes stalling.
		"name": "Where the Old Drake Sleeps", "act": 3, "type": "combat", "faction": "everflame", "hp": 22,
		"preamble": "The young one guarded a road. This one remembers when the whole island was its road. It sleeps lightly, and it sleeps here.",
		"passive_id": "drake_breath",
		"passive_desc": "Start of each round (from round 2): deal 1 damage to each of your creatures, +1 more for every creature beyond the second.",
		"deck": [
			{"name": "Hatchling", "atk": 2, "hp": 2, "kw": ["swift", "piercing"]},
			{"name": "Kobold Hurler", "atk": 2, "hp": 2, "kw": []},
			{"name": "Hoard Guardian", "atk": 1, "hp": 7, "kw": ["armored", "thorns"]},
			{"name": "Egg Mother", "atk": 1, "hp": 4, "kw": ["armored"],
				"on_death": {"type": "summon", "atk": 3, "hp": 3}},
			{"name": "Drake", "atk": 4, "hp": 5, "kw": ["armored", "piercing"]},
			{"name": "Lava Drake", "atk": 3, "hp": 4, "kw": ["regenerate", "piercing"],
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Ancient Wyrm", "atk": 5, "hp": 6, "kw": ["piercing", "armored"], "wither": 1},
		],
		"deck_variants": [
			# Variant: nest of whelps — two egg mothers, lots of hatchlings.
			[
				{"name": "Hatchling", "atk": 2, "hp": 2, "kw": ["swift"]},
				{"name": "Hatchling", "atk": 2, "hp": 2, "kw": ["swift"]},
				{"name": "Egg Mother", "atk": 1, "hp": 4,
					"on_death": {"type": "summon", "atk": 3, "hp": 3}},
				{"name": "Egg Mother", "atk": 1, "hp": 4,
					"on_death": {"type": "summon", "atk": 3, "hp": 3}},
				{"name": "Kobold Hurler", "atk": 2, "hp": 2, "kw": []},
				{"name": "Lava Drake", "atk": 3, "hp": 4, "kw": ["regenerate"],
					"on_death": {"type": "damage_all_enemies", "value": 2}},
				{"name": "Ancient Wyrm", "atk": 5, "hp": 6, "kw": ["piercing"], "wither": 1},
			],
		],
		"reinforcement": {"name": "Whelp", "atk": 2, "hp": 3, "kw": ["piercing"]},
		"reinforcement_pool": [
			{"name": "Hatchling", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Kobold Hurler", "atk": 2, "hp": 2, "kw": []},
		],
	},

	"pyre_cult": {
		# Pyre theme — FIRE THAT SPREADS. Every cultist either pierces (fire
		# burns through walls), burns on contact (thorns), or explodes on death
		# (chain damage). The forge_burn_all passive keeps ambient chip damage
		# flowing every round. No structures — the deck IS the theme.
		"name": "The Pyre Cult", "act": 3, "type": "combat", "faction": "everflame", "hp": 20,
		"preamble": "They believe the world ends in fire, and they have volunteered to help. Faith like that does not flinch or stop.",
		"passive_id": "pyre_spread",
		"passive_desc": "When an enemy creature dies: deal 1 damage to the opposing creature and 1 face damage.",
		"deck": [
			{"name": "Cinder Whelp", "atk": 1, "hp": 2, "kw": ["swift", "piercing"]},
			{"name": "Ember Mystic", "atk": 2, "hp": 2, "kw": ["piercing"]},
			{"name": "Coal Hulk", "atk": 2, "hp": 5, "kw": ["thorns", "armored"]},
			{"name": "Kindler", "atk": 3, "hp": 3, "kw": ["piercing"],
				"on_enter": {"type": "damage_face", "value": 2}},
			{"name": "Pyromancer", "atk": 2, "hp": 4, "kw": ["thorns"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Burning Martyr", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Conflagrant", "atk": 5, "hp": 5, "kw": ["piercing"],
				"on_death": {"type": "damage_face", "value": 3}},
		],
		"reinforcement": {"name": "Cinder Whelp", "atk": 1, "hp": 2, "kw": ["swift", "piercing"]},
		"reinforcement_pool": [
			{"name": "Burning Martyr", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Ember Mystic", "atk": 2, "hp": 2, "kw": ["piercing"]},
		],
	},

	"withered_court": {
		# Withered Court — WHISPERS AND WITHER. Every courtier debuffs the
		# player on enter (opposing -ATK, random discard, AoE debuff) or
		# carries Wither / Thorns. The court doesn't kill quickly — it
		# strangles your board into uselessness. Spell-heavy decks shred
		# this fight; creature-heavy decks struggle.
		"name": "The Withered Court", "act": 3, "type": "combat", "faction": "owed", "hp": 22,
		"preamble": "The court never adjourned; it only dried out where it sat. It will receive you warmly, and keep a little of your warmth.",
		"passive_id": "court_wither",
		"passive_desc": "Start of each round (from round 2): your creatures lose 1 ATK this round.",
		"deck": [
			{"name": "Court Jester", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "discard_random"}},
			{"name": "Crossbow Lady", "atk": 2, "hp": 3, "kw": []},
			{"name": "Court Hexer", "atk": 2, "hp": 3, "kw": ["thorns"],
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Pale Handmaid", "atk": 1, "hp": 5, "kw": ["thorns"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Mourner Knight", "atk": 3, "hp": 5, "kw": ["thorns"], "wither": 1},
			{"name": "Whisper-King", "atk": 2, "hp": 4, "kw": ["thorns"],
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Withered King", "atk": 4, "hp": 6, "kw": ["last_stand", "thorns"],
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
		],
		"reinforcement": {"name": "Court Mourner", "atk": 1, "hp": 3,
			"on_enter": {"type": "discard_random"}},
		"reinforcement_pool": [
			{"name": "Court Hexer", "atk": 2, "hp": 3, "kw": ["thorns"],
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Court Jester", "atk": 2, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "discard_random"}},
		],
	},

	"killing_choir": {
		# Killing Choir — SONG REACHES EVERYWHERE. The choir sings from the
		# back: most singers are Ranged (their voice carries), and the
		# Hymn Bearer / Conductor buff adjacent voices. The snipe passive
		# silences your strongest creature each round. Push damage onto the
		# back-row singers fast or get sung to death.
		"name": "The Killing Choir", "act": 3, "type": "combat", "faction": "owed", "hp": 21,
		"preamble": "They sing in numbers, not notes — a count that runs one way. Stand in the aisle too long and you join the song.",
		"passive_id": "hollow_king_snipe",
		"passive_desc": "Start of each round: deal 3 damage to your highest-ATK creature.",
		"deck": [
			{"name": "Echo Twin", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Soprano", "atk": 2, "hp": 2, "kw": ["piercing"]},
			{"name": "Tenor", "atk": 3, "hp": 2, "kw": ["piercing"]},
			{"name": "Hymn Bearer", "atk": 1, "hp": 5,
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Conductor", "atk": 2, "hp": 3, "kw": [],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Cantor", "atk": 2, "hp": 4, "kw": [],
				"on_death": {"type": "damage_all_enemies", "value": 2}},
			{"name": "Maestro", "atk": 3, "hp": 5, "kw": [],
				"on_death": {"type": "summon", "atk": 3, "hp": 3}},
		],
		"reinforcement": {"name": "Hummer", "atk": 2, "hp": 2, "kw": []},
		"reinforcement_pool": [
			{"name": "Echo Twin", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Soprano", "atk": 2, "hp": 2, "kw": ["piercing"]},
		],
	},

	# =================== ACT 3 — ELITE ============================

	"archlich": {
		# Archlich (Act 3 elite) — STEEL DOES NOTHING. Inspired by Dark Souls
		# Gravelord Nito: archlich_immortal blocks creature attacks from
		# pushing enemies below 1 HP. Different obstacles to spell-kill: a
		# Bone Dragon that pierces back at you, a Lich Acolyte that summons,
		# a Phylactery wall, Skeleton Knights that just keep coming. The
		# puzzle is "which one do I spend my limited spells on first."
		"name": "The Bone-Crowned", "act": 3, "type": "elite", "faction": "owed", "hp": 29,
		"preamble": "He spends death the way he spent life: collecting. The crown is bone now, the court as well, and he is not yet finished.",
		"passive_id": "archlich_immortal",
		"passive_desc": "Creature attacks can't reduce enemies below 1 HP — only spells and effects finish them.",
		"deck": [
			{"name": "Skeleton Knight", "atk": 3, "hp": 4},
			{"name": "Skeleton Knight", "atk": 3, "hp": 4},
			{"name": "Bone Walker", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Bone Dragon", "atk": 4, "hp": 5, "kw": ["piercing"]},
			{"name": "Lich Acolyte", "atk": 1, "hp": 3,
				"adj_buff": {"atk": 1, "hp": 0},
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Phylactery", "atk": 0, "hp": 8, "kw": ["thorns", "armored"]},
		],
		"reinforcement": {"name": "Risen", "atk": 2, "hp": 3},
		"reinforcement_pool": [
			{"name": "Skeleton Knight", "atk": 3, "hp": 4},
			{"name": "Bone Walker", "atk": 2, "hp": 3, "kw": ["swift"]},
		],
	},

	"void_walker": {
		# Void Walker (Act 3 elite) — RACE THE CLOCK. Inspired by StS Time
		# Eater: the void_exile passive deletes the top of your deck every
		# turn (permanently). Sustained-card decks lose by attrition before
		# they can stabilize. The Void Maw shreds your hand on top. The
		# fight pressures you to kill fast — every stalled turn costs you a
		# card you might've needed.
		"name": "The One Who Walks Sideways", "act": 3, "type": "elite", "faction": "lanternhall", "hp": 28,
		"preamble": "It comes not at you but around you, through a corner the road did not have a breath ago. Geometry is on its side.",
		"passive_id": "void_exile",
		"passive_desc": "Start of your turn: the top card of your draw pile is exiled (removed from this fight).",
		"deck": [
			{"name": "Void Spawn", "atk": 3, "hp": 4, "kw": ["swift"]},
			{"name": "Void Spawn", "atk": 3, "hp": 4, "kw": ["swift"]},
			{"name": "Rift Stalker", "atk": 4, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Rift Stalker", "atk": 4, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Null Beast", "atk": 3, "hp": 5,
				"on_enter": {"type": "discard_random"}},
			{"name": "Null Beast", "atk": 3, "hp": 5,
				"on_enter": {"type": "discard_random"}},
			{"name": "Void Maw", "atk": 6, "hp": 6, "kw": ["piercing"],
				"on_enter": {"type": "discard_random"}},
		],
		"reinforcement": {"name": "Fragment", "atk": 5, "hp": 4, "kw": ["swift", "piercing"]},
		"reinforcement_pool": [
			{"name": "Rift Stalker", "atk": 4, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Void Spawn", "atk": 3, "hp": 4, "kw": ["swift"]},
		],
	},

	"corrupted_shepherd": {
		# Corrupted Shepherd (Act 3 elite) — THE MASTER, THEN THE FLOCK.
		# Inspired by Bloodborne beast hunts (Cleric Beast / Vicar Amelia):
		# the Shepherd is the buff hub, the Whisperer is the healer, the
		# rams and lambs are disposable but they SCALE when allies die
		# (wolf_pack_revenge). Kill the front-row flock first and the
		# remaining beasts rage; kill the buffers first and the front
		# collapses. Real target-order puzzle.
		"name": "The Shepherd Who Lost His Sheep", "act": 3, "type": "elite", "faction": "owed", "hp": 31,
		"preamble": "He kept the flock long after it stopped breathing. He cannot tell the living from the led now, and he is reaching for you.",
		"passive_id": "flock_enrage",
		"passive_desc": "When an enemy creature dies: enemies beside it gain +1 ATK for the rest of the fight.",
		"deck": [
			{"name": "Maggot-Lamb", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Maggot-Lamb", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Stray Lamb", "atk": 2, "hp": 2, "kw": ["swift"]},
			{"name": "Bone-Ram", "atk": 5, "hp": 4, "kw": ["piercing"]},
			{"name": "Bone-Ram", "atk": 5, "hp": 4, "kw": ["piercing"]},
			{"name": "Flock Whisperer", "atk": 2, "hp": 5, "kw": ["regenerate"],
				"adj_buff": {"atk": 0, "hp": 1},
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Mad Shepherd", "atk": 4, "hp": 6, "kw": ["last_stand"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Stray Lamb", "atk": 4, "hp": 3, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Maggot-Lamb", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Bone-Ram", "atk": 5, "hp": 4, "kw": ["piercing"]},
		],
	},

	"glass_menagerie": {
		# The Glass Menagerie (Act 3 elite) — EVERYTHING HITS LIKE A TRUCK AND
		# DIES LIKE A WINDOW. A hall of living glass: nearly every creature is a
		# high-ATK / 1-2-HP glass cannon (Piercing or Swift) that you can pop
		# with a feather — but it'll gut you first if you don't, and several are
		# Ranged so blocking a lane doesn't save your face. The executioner_face
		# passive turns the single biggest shard into face damage every round, so
		# a stalled board bleeds you out. The counter-pressure: a couple of
		# fragile copycats that mirror YOUR keywords, so your buffs come back as
		# glass. This is a RACE, not a grind — the opposite of the act's other
		# elites (the immortal Bone-Crowned, the attrition Void Walker). Trade
		# fast, sweep wide, end it before the menagerie reflects your whole deck.
		"name": "The Glass Menagerie", "act": 3, "type": "elite", "faction": "lanternhall", "hp": 24,
		"preamble": "Each was blown to one perfect purpose and cooled around it. They do not bleed — they break, into a handful of new edges.",
		"passive_id": "glass_refract",
		"passive_desc": "Start of each round (from round 2): a 3/1 Swift glass shard forms in an empty enemy lane.",
		"deck": [
			{"name": "Glass Sniper", "atk": 4, "hp": 1, "kw": ["piercing"], "sniper": true},
			{"name": "Glass Sniper", "atk": 4, "hp": 1, "kw": ["piercing"], "sniper": true},
			{"name": "Mirror Wisp", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Shattered Twin", "atk": 4, "hp": 2, "kw": ["swift", "piercing"],
				"on_death": {"type": "summon", "atk": 2, "hp": 1}},
			{"name": "Reflection", "atk": 3, "hp": 2, "kw": ["swift"],
				"on_enter": {"type": "copy_opposing_keywords"}},
			{"name": "Hall-Watcher", "atk": 1, "hp": 6, "kw": ["thorns", "armored"]},
			{"name": "Glass Knight", "atk": 6, "hp": 3, "kw": ["piercing"],
				"on_death": {"type": "damage_opposing_lane", "value": 3}},
		],
		"deck_variants": [
			# Variant: house of mirrors — copycats stack, so a buffed player deck
			# gets its own keywords flung back across the glass.
			[
				{"name": "Glass Sniper", "atk": 4, "hp": 1, "kw": ["piercing"], "sniper": true},
				{"name": "Reflection", "atk": 3, "hp": 2, "kw": ["swift"],
					"on_enter": {"type": "copy_opposing_keywords"}},
				{"name": "Doppel", "atk": 3, "hp": 3, "kw": ["swift"],
					"on_enter": {"type": "copy_opposing_keywords"}},
				{"name": "Shattered Twin", "atk": 4, "hp": 2, "kw": ["swift", "piercing"],
					"on_death": {"type": "summon", "atk": 2, "hp": 1}},
				{"name": "Mirror Wisp", "atk": 3, "hp": 2, "kw": ["swift"]},
				{"name": "Glass Knight", "atk": 6, "hp": 3, "kw": ["piercing"],
					"on_death": {"type": "damage_opposing_lane", "value": 3}},
			],
		],
		"reinforcement": {"name": "Glass Shard", "atk": 3, "hp": 1, "kw": ["swift"]},
		"reinforcement_pool": [
			{"name": "Glass Sniper", "atk": 4, "hp": 1, "kw": ["piercing"], "sniper": true},
			{"name": "Mirror Wisp", "atk": 3, "hp": 2, "kw": ["swift"]},
		],
	},

	# =================== ACT 3 — BOSS =============================

	"the_devil": {
		# The Devil (Act 3 boss) — THREE FACES. Inspired by Persona 5's
		# boss reveals: the devil_cycle passive rotates effect each round
		# (R1 face, R2 heal, R3 snipe). Phase 2 (HP < 20) DOUBLES the cycle
		# and summons a Pit Fiend with the existing banner reveal. Phase 3
		# (HP < 10) is DESPERATION — 3 face per round, +1 ATK to all, summon.
		# The 3 phases already exist; deck is variety of demons that all
		# play differently so the cycle hits different things.
		"name": "THE DEVIL", "act": 3, "type": "boss", "faction": "everflame", "hp": 36,
		"passive_id": "devil_cycle",
		"passive_desc": "Repeating cycle. R1: deal 2 face damage. R2: heal 1 HP per enemy. R3: deal 3 damage to your highest-ATK creature.",
		"preamble": "It deals fairly — that is the worst of it. Everything it offers, it takes back with interest, and you signed a long walk ago. It is only here to collect.",
		"deck": [
			{"name": "Demon Soldier", "atk": 3, "hp": 4, "kw": ["armored", "piercing"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4, "kw": ["armored", "piercing"]},
			{"name": "Hellfire Imp", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 2}},
			{"name": "Hellfire Imp", "atk": 2, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_face", "value": 2}},
			{"name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"]},
			{"name": "Soul Reaper", "atk": 3, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Devil's Champion", "atk": 5, "hp": 6, "kw": ["piercing", "last_stand"],
				"adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Iron Vanguard", "atk": 4, "hp": 5, "kw": ["armored", "last_stand"]},
		],
		"reinforcement": {"name": "Lesser Demon", "atk": 3, "hp": 3, "kw": ["piercing"]},
	},

	"the_crone": {
		# The Crone (Act 3 boss) — THE CAULDRON BREWS. Inspired by MtG
		# Liliana and Hand of Fate hag bosses: a back-row Cauldron structure
		# tracks how many curses she's brewed. Phase 1 (crone_drip) drips
		# one curse per round. Phase 2 (crone_lash) starts dealing face per
		# curse in your deck. Phase 3 (crone_doom) is the climax — every
		# round adds two curses + face damage + a Wraith summon. Aggressive
		# removal decks shred this; slow decks drown in curses.
		"name": "THE CRONE", "act": 3, "type": "boss", "faction": "owed", "hp": 32,
		"passive_id": "cauldron_brew",
		"passive_desc": "End of each round: the Cauldron gains 1 Charge and adds 1 Curse to your discard. At 5 it OVERFLOWS — summon a Wraith, add 2 Curses, deal 3 face damage.",
		"preamble": "She was old when the meadow was green, and she has never once been wrong about the ending. The kettle is already warm.",
		"structures": [
			{"name": "Cauldron", "atk": 0, "hp": 99,
				"kw": ["structure"], "charge_max": 5, "lane": 1},
		],
		"deck": [
			{"name": "Skeleton", "atk": 2, "hp": 2, "kw": ["last_stand"]},
			{"name": "Skeleton", "atk": 2, "hp": 2, "kw": ["last_stand"]},
			{"name": "Wraith", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Wraith", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Bone Crone", "atk": 3, "hp": 4, "kw": ["thorns"],
				"on_enter": {"type": "damage_face", "value": 2}},
			{"name": "Marrow Knight", "atk": 4, "hp": 5, "kw": ["armored", "piercing"]},
			{"name": "Soul Drinker", "atk": 3, "hp": 5, "kw": ["regenerate"]},
			{"name": "The Crone", "atk": 5, "hp": 7, "kw": ["regenerate", "last_stand"],
				"adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Specter", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	"the_black_tide": {
		# Swarm boss: keeps refilling its board and eventually buffs every wave.
		# The player needs board clears (Earthquake / Apocalypse / Inferno) and
		# enough single-target damage to finish off the high-HP centerpieces.
		"name": "THE BLACK TIDE", "act": 3, "type": "boss", "faction": "owed", "hp": 34,
		"passive_id": "tide_swell",
		"passive_desc": "End of each round: if there are fewer than 4 enemy creatures, summon a 2/3 Deepling.",
		"preamble": "It is not water, though it rises like water. It has climbed toward this place one drowned thing at a time, and it is patient about the rest of you.",
		# Black Tide (Act 3 boss) — THE WATER RISES. Inspired by Subnautica
		# deep-horror + MtG Emrakul: the tide_swell passive summons a Deepling
		# every round you don't keep the board full. Phase 2 (tide_surge)
		# also gives every enemy +1 ATK per round. Phase 3 (tide_drown)
		# damages your weakest creature. Every wave brings something different:
		# Tide Spawn chaff, Deeplings tanks, Anglerfish ambush, Tentacle regen,
		# the Tide itself the unkillable centerpiece.
		"deck": [
			{"name": "Tide Spawn", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Tide Spawn", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Deepling", "atk": 3, "hp": 4, "kw": ["regenerate"]},
			{"name": "Deepling", "atk": 3, "hp": 4, "kw": ["regenerate"]},
			{"name": "Drowned", "atk": 3, "hp": 5, "kw": ["armored", "last_stand"]},
			{"name": "Tentacle", "atk": 2, "hp": 6, "kw": ["thorns", "regenerate"]},
			{"name": "Anglerfish", "atk": 4, "hp": 3, "kw": ["swift", "piercing"],
				"on_enter": {"type": "damage_opposing", "value": 2}},
			{"name": "The Black Tide", "atk": 6, "hp": 8, "kw": ["piercing", "regenerate"]},
		],
		"reinforcement": {"name": "Spawn", "atk": 2, "hp": 2, "kw": ["swift"]},
	},
}
