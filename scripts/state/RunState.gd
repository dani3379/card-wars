extends Node
## RunState.gd — autoload singleton. Holds the current run's persistent data
## as you move between Combat / Reward / Map scenes.
##
## Cleared and re-initialized each time a new run begins.
##
## Add to autoload as "RunState" in Project Settings.

# ── Hero ──
var hero_max_hp: int = 25
var hero_hp: int = 25
var gold: int = 0

# ── Deck ──
# Each entry is a card id (String). Duplicates allowed.
var deck: Array[String] = []

# ── Relics ──
# Each entry is a relic id (String).
var relics: Array[String] = []

# ── Map progression ──
var current_floor: int = 0   # 0 = pre-run, 1..N = floors traversed
var run_active: bool = false
var run_seed: int = 0


# ── Once-per-run flags ──
var phoenix_heart_consumed: bool = false


# ── Run lifecycle ──
func start_new_run() -> void:
	hero_max_hp = 25
	hero_hp = 25
	gold = 0
	deck = []
	for id in CardDB.STARTER_DECK:
		deck.append(id)
	relics = []
	current_floor = 0
	run_active = true
	run_seed = randi()
	# Apply meta-unlocks here later if any persistent bonuses exist.


func end_run(victorious: bool) -> void:
	run_active = false
	if victorious:
		MetaState.record_victory()
	else:
		MetaState.record_defeat()


# ── Deck manipulation ──
func add_card(id: String) -> void:
	deck.append(id)


func remove_card(id: String) -> bool:
	for i in range(deck.size()):
		if deck[i] == id:
			deck.remove_at(i)
			return true
	return false


# ── Relic manipulation ──
func add_relic(id: String) -> void:
	if not relics.has(id):
		relics.append(id)


func has_relic(id: String) -> bool:
	return relics.has(id)


# ── Hero HP ──
func damage_hero(amount: int) -> void:
	hero_hp = max(0, hero_hp - amount)


func heal_hero(amount: int) -> void:
	hero_hp = min(hero_max_hp, hero_hp + amount)


# ── Floor progression ──
func advance_floor() -> void:
	current_floor += 1


# ── Map structure ──
# A run has 8 floors. Each floor has a node type. Last is always boss.
const FLOOR_COUNT: int = 8

func node_type_for_floor(floor_num: int) -> String:
	# 1 = combat, 8 = boss, 4 = elite, others combat
	# This is intentionally simple. Replace with real map gen later.
	if floor_num == FLOOR_COUNT:
		return "boss"
	if floor_num == 4 or floor_num == 7:
		return "elite"
	return "combat"
