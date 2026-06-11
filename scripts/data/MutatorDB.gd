extends Node
## Encounter mutators — per-fight modifiers that attach to combat / elite map
## nodes. Each mutator tweaks the fight (mostly a tax, sometimes a gift) and
## carries a gold-reward bump so taking the harder fights pays back.
##
## Hook points used by Combat.gd:
##   on_enemy_enter(card)        — granted to every enemy creature on placement
##   on_round_start(combat)      — fires at the start of each round
##   on_player_creature_enter()  — when the player plays a creature
##   on_kill(killer_was_player)  — when ANY creature dies in combat
##
## A mutator effect is a dictionary with the format:
##   {"kind": "...", "value": int|str|...}
## Combat reads `kind` and applies the side-effect. Adding a new kind = one
## case in the dispatcher in Combat.gd.

const MUTATORS: Dictionary = {
	# ═══════════════════════════════════════════
	#  Negative — pay a tax, get gold bonus
	# ═══════════════════════════════════════════
	"stormy": {
		"name": "Stormy",
		"desc": "All enemies gain Swift.",
		"icon": "swift",
		"on_enemy_enter": {"kind": "grant_keyword", "value": "swift"},
		"gold_bonus": 20,
		"weight": 10,
	},
	"ironclad": {
		"name": "Ironclad",
		"desc": "All enemies gain Armored.",
		"icon": "armored",
		"on_enemy_enter": {"kind": "grant_keyword", "value": "armored"},
		"gold_bonus": 25,
		"weight": 10,
	},
	"thorny": {
		"name": "Thorny",
		"desc": "All enemies gain Thorns.",
		"icon": "thorns",
		"on_enemy_enter": {"kind": "grant_keyword", "value": "thorns"},
		"gold_bonus": 20,
		"weight": 10,
	},
	"feral": {
		"name": "Feral",
		"desc": "Enemy creatures enter with +1 ATK.",
		"icon": "sword",
		"on_enemy_enter": {"kind": "buff_atk", "value": 1},
		"gold_bonus": 20,
		"weight": 12,
	},
	"hardened": {
		"name": "Hardened",
		"desc": "Enemy creatures enter with +1 HP.",
		"icon": "shield",
		"on_enemy_enter": {"kind": "buff_hp", "value": 1},
		"gold_bonus": 15,
		"weight": 12,
	},
	"burning": {
		"name": "Burning",
		"desc": "Start of each round: your front-row creatures take 1 damage.",
		"icon": "fire",
		"on_round_start": {"kind": "damage_player_front", "value": 1},
		"gold_bonus": 25,
		"weight": 8,
	},
	"taxed": {
		"name": "Taxed",
		"desc": "Spells cost 1 more Command, minimum 1.",
		"icon": "book",
		"on_combat_start": {"kind": "spell_cost_increase", "value": 1},
		"gold_bonus": 25,
		"weight": 8,
	},
	"cursed": {
		"name": "Cursed",
		"desc": "Creatures you play enter with -1 HP.",
		"icon": "skull",
		"on_player_creature_enter": {"kind": "weaken_player_creature_hp", "value": 1},
		"gold_bonus": 25,
		"weight": 8,
	},
	"famine": {
		"name": "Famine",
		"desc": "You draw 1 fewer card per turn.",
		"icon": "skull",
		"on_combat_start": {"kind": "hand_draw_reduce", "value": 1},
		"gold_bonus": 30,
		"weight": 6,
	},
	"frenzied": {
		"name": "Frenzied",
		"desc": "Enemy On-Death effects trigger twice.",
		"icon": "skull",
		"on_combat_start": {"kind": "enemy_double_on_death", "value": 1},
		"gold_bonus": 25,
		"weight": 6,
	},
	"lethal": {
		"name": "Lethal",
		"desc": "All enemies gain Piercing.",
		"icon": "sword",
		"on_enemy_enter": {"kind": "grant_keyword", "value": "piercing"},
		"gold_bonus": 25,
		"weight": 8,
	},
	"scarred": {
		"name": "Scarred",
		"desc": "Start the fight at -3 HP.",
		"icon": "heart",
		"on_combat_start": {"kind": "damage_player_now", "value": 3},
		"gold_bonus": 20,
		"weight": 8,
	},
	"doomed": {
		"name": "Doomed",
		"desc": "Enemy front-liners enter with Doom 3. Kill them before the clock runs out, or the blast hits your face.",
		"icon": "skull",
		"on_enemy_enter": {"kind": "grant_doom", "value": 3},
		"gold_bonus": 25,
		"weight": 7,
	},
	"overgrown": {
		"name": "Overgrown",
		"desc": "Enemy creatures enter with +2 HP and Regenerate. Whatever you don't finish knits itself back together.",
		"icon": "shield",
		"on_enemy_enter": {"kind": "buff_hp_regen", "value": 2},
		"gold_bonus": 30,
		"weight": 6,
	},

	# ═══════════════════════════════════════════
	#  Positive — gifts the player can stumble into
	# ═══════════════════════════════════════════
	"bountiful": {
		"name": "Bountiful",
		"desc": "Earn +25 gold from this fight. No other effect.",
		"icon": "diamond",
		"gold_bonus": 25,
		"weight": 6,
	},
	"diamond": {
		"name": "Diamond Vein",
		"desc": "Earn +50 gold from this fight.",
		"icon": "diamond",
		"gold_bonus": 50,
		"weight": 3,
	},
	"swift_winds": {
		"name": "Swift Winds",
		"desc": "Your creatures gain Swift this fight.",
		"icon": "swift",
		"on_player_creature_enter": {"kind": "grant_player_keyword", "value": "swift"},
		"gold_bonus": 0,
		"weight": 4,
	},
	"blessed": {
		"name": "Blessed",
		"desc": "Start the fight with +1 max Command.",
		"icon": "crown",
		"on_combat_start": {"kind": "max_mana_increase", "value": 1},
		"gold_bonus": 0,
		"weight": 4,
	},
	"wisdom": {
		"name": "Wisdom",
		"desc": "Draw 1 extra card per turn.",
		"icon": "book",
		"on_combat_start": {"kind": "hand_draw_increase", "value": 1},
		"gold_bonus": 0,
		"weight": 4,
	},
	"vampiric": {
		"name": "Vampiric",
		"desc": "Your creatures have Lifelink. Every drop they spill heals you a little.",
		"icon": "heart",
		"on_player_creature_enter": {"kind": "grant_player_keyword", "value": "lifelink"},
		"gold_bonus": 0,
		"weight": 4,
	},
	"bloodthirsty": {
		"name": "Bloodthirsty",
		"desc": "Your creatures have Rampage — every kill they land makes them permanently stronger this fight.",
		"icon": "sword",
		"on_player_creature_enter": {"kind": "grant_player_keyword", "value": "rampage"},
		"gold_bonus": 0,
		"weight": 4,
	},
}


## Returns mutator id or "" for no mutator. Weighted random across the table.
## `density` controls how often a fight has any mutator at all (0.0 = never,
## 1.0 = always). Combat nodes use ~0.35; elites use ~0.65.
func roll(density: float, rng: RandomNumberGenerator) -> String:
	if rng.randf() >= density:
		return ""
	var ids: Array = MUTATORS.keys()
	var total_weight: int = 0
	for id in ids:
		total_weight += int(MUTATORS[id].get("weight", 1))
	if total_weight <= 0:
		return ""
	var pick: int = rng.randi() % total_weight
	for id in ids:
		var w: int = int(MUTATORS[id].get("weight", 1))
		if pick < w:
			return id
		pick -= w
	return ""


func get_mutator(id: String) -> Dictionary:
	return MUTATORS.get(id, {})


## True if the mutator id is real (used as a gate for callers).
func exists(id: String) -> bool:
	return id != "" and MUTATORS.has(id)
