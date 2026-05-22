extends Node
## RunState.gd — autoload singleton. Holds the current run's persistent data.
## Generates a branching map across 3 acts. Tracks deck, relics, gold, upgrades.

# ── Hero ──
var hero_max_hp: int = 25
var hero_hp: int = 25
var gold: int = 0
var potions: int = 0

# ── Deck ──
var deck: Array[String] = []
var deck_uids: Array[int] = []
var card_upgrades: Dictionary = {}
var _next_uid: int = 0

# ── Relics ──
var relics: Array[String] = []

# ── Map ──
var map_data: Array = []
var current_act_idx: int = 0
var map_position: Dictionary = {"row": -1, "col": -1}
var current_encounter_id: String = ""
var current_node_type: String = ""
var events_seen: Array[String] = []

# ── Mana ──
var base_max_mana: int = 3

# ── Compatibility ──
var current_floor: int = 0
var run_active: bool = false
var run_seed: int = 0
var phoenix_heart_consumed: bool = false
# Ascension level chosen for this run (0..MetaState.unlocked_ascension).
# Each tier scales encounter face HP (see ASCENSION_HP_MULT). Set in
# start_new_run; never modified mid-run.
var current_ascension: int = 0
# Per-ascension HP multiplier applied to encounter face HP. Index = ascension.
const ASCENSION_HP_MULT: Array[float] = [1.0, 1.20, 1.40, 1.60, 1.80, 2.0]

const ACTS: int = 3

# ── Slay-the-Spire-style map constants ──
# 7 columns wide, 15 rows tall (rows 0..13 are explorable, row 14 = boss).
# 6 paths walk from row 0 to row 13; rest sites occupy row 13; boss is row 14.
const MAP_WIDTH: int = 7
const MAP_HEIGHT: int = 15
const BOSS_ROW: int = 14
const REST_ROW: int = 13
const NUM_PATHS: int = 4         # Fewer paths than STS (6) — fits our smaller, faster runs.
const MIN_ELITE_ROW: int = 5     # Elites/rest cannot appear before this row.

# Room-type probabilities (cumulative). Mirrors STS: combat 46%, event 22%,
# elite 10%, rest 12%, shop 10%.
const PROB_SHOP: float = 0.10
const PROB_REST: float = 0.22    # 0.10 + 0.12
const PROB_ELITE: float = 0.32   # 0.22 + 0.10
const PROB_EVENT: float = 0.54   # 0.32 + 0.22


func get_act() -> int:
	return current_act_idx + 1


# ── Run lifecycle ──

func start_new_run(starting_relic: String = "", ascension: int = -1) -> void:
	hero_max_hp = 25
	hero_hp = 25
	gold = 0
	potions = 0
	base_max_mana = 3
	# Default to player's highest unlocked tier if caller didn't pick one.
	if ascension < 0:
		current_ascension = MetaState.unlocked_ascension
	else:
		current_ascension = clampi(ascension, 0, MetaState.unlocked_ascension)
	deck = []
	deck_uids = []
	card_upgrades = {}
	_next_uid = 0
	for id in CardDB.STARTER_DECK:
		add_card(id)
	relics = []
	if starting_relic != "":
		relics.append(starting_relic)
	current_floor = 0
	current_act_idx = 0
	map_position = {"row": -1, "col": -1}
	current_encounter_id = ""
	current_node_type = ""
	events_seen = []
	run_active = true
	run_seed = randi()
	CardTextureCache.clear()
	_generate_map()


func end_run(victorious: bool) -> void:
	run_active = false
	clear_save()  # save only persists in-progress runs; ended ones are gone
	if victorious:
		MetaState.record_victory()
	else:
		MetaState.record_defeat()


# ── Deck manipulation ──

func add_card(id: String) -> int:
	deck.append(id)
	var uid = _next_uid
	deck_uids.append(uid)
	_next_uid += 1
	return uid


func remove_card_at(index: int) -> bool:
	if index < 0 or index >= deck.size():
		return false
	var uid = deck_uids[index]
	deck.remove_at(index)
	deck_uids.remove_at(index)
	card_upgrades.erase(uid)
	return true


# ── Card upgrades ──

func upgrade_card(deck_index: int, path: String, keyword: String = "") -> void:
	if deck_index < 0 or deck_index >= deck_uids.size():
		return
	var uid = deck_uids[deck_index]
	card_upgrades[uid] = {"path": path, "keyword": keyword}


func get_card_upgrade(deck_index: int) -> Dictionary:
	if deck_index < 0 or deck_index >= deck_uids.size():
		return {}
	var uid = deck_uids[deck_index]
	return card_upgrades.get(uid, {})


func is_card_upgraded(deck_index: int) -> bool:
	return not get_card_upgrade(deck_index).is_empty()


func get_upgraded_card_data(deck_index: int) -> Dictionary:
	if deck_index < 0 or deck_index >= deck.size():
		return {}
	var base = CardDB.get_card_data(deck[deck_index])
	var upgrade = get_card_upgrade(deck_index)
	if upgrade.is_empty():
		return base
	return _apply_upgrade(base, upgrade)


func _apply_upgrade(data: Dictionary, upgrade: Dictionary) -> Dictionary:
	var d = data.duplicate(true)
	var bonus = 3 if has_relic("blacksmiths_hammer") else 2
	match upgrade.path:
		"sharpen":
			if d.type == "creature":
				d.atk += bonus
			else:
				if d.has("spell") and d.spell.has("value"):
					d.spell.value += bonus
		"fortify":
			if d.type == "creature":
				d.hp += bonus
			else:
				d.cost = maxi(0, d.cost - 1)
		"imbue":
			if d.type == "creature":
				var kw = upgrade.get("keyword", "")
				if kw != "" and not d.keywords.has(kw):
					d.keywords.append(kw)
			else:
				var kw = upgrade.get("keyword", "")
				if kw == "retain":
					if not d.keywords.has("retain"):
						d.keywords.append("retain")
				else:
					if d.has("spell") and d.spell.has("value"):
						d.spell.value *= 2
					if not d.keywords.has("exhaust"):
						d.keywords.append("exhaust")
	d.name = d.name + " +"
	return d


# ── Relic manipulation ──

func add_relic(id: String) -> void:
	if not relics.has(id):
		relics.append(id)


func has_relic(id: String) -> bool:
	return relics.has(id)


# ── Hero HP ──

func damage_hero(amount: int) -> void:
	hero_hp = maxi(0, hero_hp - amount)


func heal_hero(amount: int) -> void:
	hero_hp = mini(hero_max_hp, hero_hp + amount)


func gain_gold(amount: int) -> void:
	if has_downside("no_gold"):
		return
	gold += amount


func get_max_mana() -> int:
	return base_max_mana + RelicDB.get_boss_mana_bonus(relics)


func has_downside(downside: String) -> bool:
	return RelicDB.has_downside(relics, downside)


# ── Potions ──

func use_potion() -> bool:
	if potions <= 0:
		return false
	potions -= 1
	heal_hero(8)
	return true


# ── Map navigation ──

func get_current_act_map() -> Array:
	if current_act_idx < map_data.size():
		return map_data[current_act_idx]
	return []


func get_available_nodes() -> Array:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return []
	if map_position.row == -1:
		return act_map[0].duplicate()
	var row: int = map_position.row
	var col: int = map_position.col
	if row >= act_map.size():
		return []
	var current_node: Dictionary = _find_node_by_col(act_map[row], col)
	if current_node.is_empty():
		return []
	var next_row: int = row + 1
	if next_row >= act_map.size():
		return []
	var available: Array = []
	for target_col in current_node.connections:
		var n = _find_node_by_col(act_map[next_row], target_col)
		if not n.is_empty():
			available.append(n)
	return available


func visit_node(row: int, col: int) -> void:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return
	map_position = {"row": row, "col": col}
	for n in act_map[row]:
		if n.col == col:
			n.visited = true
			current_node_type = n.type
			current_encounter_id = n.get("encounter_id", "")
			current_floor += 1
			save_run()  # checkpoint: player is committing to enter a room
			return


func _find_node_by_col(row_nodes: Array, col: int) -> Dictionary:
	for n in row_nodes:
		if n.col == col:
			return n
	return {}


func advance_act() -> void:
	current_act_idx += 1
	map_position = {"row": -1, "col": -1}
	current_encounter_id = ""
	current_node_type = ""


func is_final_boss() -> bool:
	return current_act_idx >= ACTS - 1 and current_node_type == "boss"


# ── Map generation ──

func _generate_map() -> void:
	map_data = []
	var rng = RandomNumberGenerator.new()
	rng.seed = run_seed
	for act in range(1, ACTS + 1):
		map_data.append(_generate_act_map(act, rng))


## Generates a single act map. Implements the Slay-the-Spire algorithm:
##   1. Walk NUM_PATHS paths from row 0 up to REST_ROW, ±1 column per step,
##      with a no-crossing constraint.
##   2. Assign room types per the STS probability table, respecting the
##      "no consecutive elite/shop/rest", "no rest before MIN_ELITE_ROW",
##      "no rest on row REST_ROW-1", and "siblings must differ" rules.
##   3. Add a single boss node at the BOSS_ROW center, with every populated
##      REST_ROW node connecting up to it.
##   4. Walk through and assign encounter IDs to combat/elite/boss nodes.
func _generate_act_map(act: int, rng: RandomNumberGenerator) -> Array:
	var grid: Array = []
	for r in range(MAP_HEIGHT):
		var row: Array = []
		for c in range(MAP_WIDTH):
			row.append(null)
		grid.append(row)

	_generate_paths(grid, rng)
	_assign_node_types(grid, rng)
	_add_boss_node(grid)
	_assign_encounters(grid, act, rng)
	return _flatten_grid(grid)


func _generate_paths(grid: Array, rng: RandomNumberGenerator) -> void:
	var starts: Array[int] = []
	for p in range(NUM_PATHS):
		var start_col: int = _pick_start_col(rng, starts, p)
		starts.append(start_col)
		_walk_path(grid, start_col, rng)


func _pick_start_col(rng: RandomNumberGenerator, prev_starts: Array,
		path_idx: int) -> int:
	# STS rule: the first two paths must originate from different columns so
	# the player always has a meaningful first choice.
	var avail: Array[int] = []
	for c in range(MAP_WIDTH):
		if path_idx == 1 and prev_starts.size() > 0 and c == prev_starts[0]:
			continue
		avail.append(c)
	return avail[rng.randi() % avail.size()]


func _walk_path(grid: Array, start_col: int,
		rng: RandomNumberGenerator) -> void:
	var cur_col: int = start_col
	if grid[0][cur_col] == null:
		grid[0][cur_col] = _make_node(cur_col, 0)
	for r in range(REST_ROW):
		var next_col: int = _pick_next_col(grid, r, cur_col, rng)
		if grid[r + 1][next_col] == null:
			grid[r + 1][next_col] = _make_node(next_col, r + 1)
		var conns: Array = grid[r][cur_col]["connections"]
		if not conns.has(next_col):
			conns.append(next_col)
		cur_col = next_col


func _make_node(col: int, row: int) -> Dictionary:
	return {
		"type": "",
		"encounter_id": "",
		"visited": false,
		"connections": [],
		"row": row,
		"col": col,
	}


func _pick_next_col(grid: Array, r: int, cur_col: int,
		rng: RandomNumberGenerator) -> int:
	# Step diagonally to ±1 or stay in the same column. Never produce an edge
	# that crosses an existing one (no X-shaped intersections). Candidates
	# whose destination cell is already populated get double weight, so paths
	# prefer to merge into existing nodes — this reduces total node count and
	# gives the map a more organic feel (STS2-style convergent landmarks).
	var candidates: Array[int] = []
	for d in [-1, 0, 1]:
		var nc: int = cur_col + d
		if nc < 0 or nc >= MAP_WIDTH:
			continue
		if _would_cross(grid, r, cur_col, nc):
			continue
		candidates.append(nc)
		if grid[r + 1][nc] != null:
			candidates.append(nc)
	if candidates.is_empty():
		return cur_col
	return candidates[rng.randi() % candidates.size()]


func _would_cross(grid: Array, r: int, from_col: int, to_col: int) -> bool:
	# Two diagonals form an X when the cell at the destination column already
	# has an edge pointing to our source column. Straight-up steps never cross.
	if to_col == from_col:
		return false
	var partner = grid[r][to_col]
	if partner == null:
		return false
	return partner["connections"].has(from_col)


func _assign_node_types(grid: Array, rng: RandomNumberGenerator) -> void:
	# Row 0 → all combat (always a real fight to start). Row REST_ROW → all
	# rest sites (the breather before the boss).
	for c in range(MAP_WIDTH):
		if grid[0][c] != null:
			grid[0][c]["type"] = "combat"
		if grid[REST_ROW][c] != null:
			grid[REST_ROW][c]["type"] = "rest"
	for r in range(1, REST_ROW):
		for c in range(MAP_WIDTH):
			if grid[r][c] == null:
				continue
			grid[r][c]["type"] = _pick_room_type(grid, r, c, rng)


func _pick_room_type(grid: Array, r: int, c: int,
		rng: RandomNumberGenerator) -> String:
	# Retry until placement satisfies every rule, then fall back to combat
	# if 200 attempts can't find a valid alternative.
	for _attempt in range(200):
		var roll: float = rng.randf()
		var t: String
		if roll < PROB_SHOP:
			t = "shop"
		elif roll < PROB_REST:
			t = "rest"
		elif roll < PROB_ELITE:
			t = "elite"
		elif roll < PROB_EVENT:
			t = "event"
		else:
			t = "combat"
		if (t == "elite" or t == "rest") and r < MIN_ELITE_ROW:
			continue
		if t == "rest" and r == REST_ROW - 1:
			continue
		if _is_consecutive_violation(grid, t, r, c):
			continue
		if _has_sibling_with_type(grid, t, r, c):
			continue
		return t
	return "combat"


func _is_consecutive_violation(grid: Array, t: String, r: int,
		c: int) -> bool:
	# STS: elite/shop/rest can't follow the same type on any incoming path.
	if t != "elite" and t != "shop" and t != "rest":
		return false
	if r == 0:
		return false
	for pc in range(MAP_WIDTH):
		var parent = grid[r - 1][pc]
		if parent == null:
			continue
		if not parent["connections"].has(c):
			continue
		if parent.get("type", "") == t:
			return true
	return false


func _has_sibling_with_type(grid: Array, t: String, r: int,
		c: int) -> bool:
	# STS: a parent with multiple outgoing edges must point to distinct types,
	# so the player's choice between siblings is always meaningful.
	if r == 0:
		return false
	for pc in range(MAP_WIDTH):
		var parent = grid[r - 1][pc]
		if parent == null:
			continue
		if not parent["connections"].has(c):
			continue
		for sc in parent["connections"]:
			if sc == c:
				continue
			var sibling = grid[r][sc]
			if sibling == null:
				continue
			if sibling.get("type", "") == t:
				return true
	return false


func _add_boss_node(grid: Array) -> void:
	var boss_col: int = MAP_WIDTH / 2
	grid[BOSS_ROW][boss_col] = _make_node(boss_col, BOSS_ROW)
	grid[BOSS_ROW][boss_col]["type"] = "boss"
	for c in range(MAP_WIDTH):
		if grid[REST_ROW][c] != null:
			grid[REST_ROW][c]["connections"] = [boss_col]


func _assign_encounters(grid: Array, act: int,
		rng: RandomNumberGenerator) -> void:
	var combat_ids: Array = EncounterDB.get_ids_for(act, "combat").duplicate()
	_shuffle_array(combat_ids, rng)
	var elite_ids: Array = EncounterDB.get_ids_for(act, "elite").duplicate()
	_shuffle_array(elite_ids, rng)
	var boss_ids: Array = EncounterDB.get_ids_for(act, "boss").duplicate()
	_shuffle_array(boss_ids, rng)
	var combat_idx: int = 0
	var elite_idx: int = 0
	for r in range(MAP_HEIGHT):
		for c in range(MAP_WIDTH):
			var node = grid[r][c]
			if node == null:
				continue
			match node["type"]:
				"combat":
					if combat_ids.size() > 0:
						node["encounter_id"] = combat_ids[combat_idx % combat_ids.size()]
						combat_idx += 1
				"elite":
					if elite_ids.size() > 0:
						node["encounter_id"] = elite_ids[elite_idx % elite_ids.size()]
						elite_idx += 1
				"boss":
					if boss_ids.size() > 0:
						node["encounter_id"] = boss_ids[0]


func _flatten_grid(grid: Array) -> Array:
	# Compact the sparse grid into per-row arrays of only the populated nodes.
	# Each node keeps its grid `col` for visuals and for connection lookups.
	var rows: Array = []
	for r in range(MAP_HEIGHT):
		var row_nodes: Array = []
		for c in range(MAP_WIDTH):
			if grid[r][c] != null:
				row_nodes.append(grid[r][c])
		rows.append(row_nodes)
	return rows


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp


# ════════════════════════════════════════════════════════════════════
#  SAVE / RESUME
# ════════════════════════════════════════════════════════════════════
# Persists the in-progress run as JSON across SAVE_SLOTS slots. The save is
# written every time the player commits to a map node (`visit_node`), so
# quitting and relaunching restores them on the map at the room they were
# about to enter. The save is cleared on death or victory (end_run).

const SAVE_VERSION: int = 1
const SAVE_SLOTS: int = 3
const LEGACY_SAVE_PATH: String = "user://run.save"

# Which slot the current in-memory run reads from / writes to. -1 means
# "no slot picked yet" (e.g. the player is in the main menu before starting).
var active_slot: int = -1


func _save_path_for_slot(slot: int) -> String:
	return "user://run_%d.save" % slot


# Migrates a pre-multislot save (user://run.save) into slot 0 so existing
# players don't lose their in-progress run. Idempotent: no-op once migrated.
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var target := _save_path_for_slot(0)
	if FileAccess.file_exists(target):
		# Slot 0 already has a save — drop the legacy file rather than overwrite.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH))
		return
	var src := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	var dst := FileAccess.open(target, FileAccess.WRITE)
	if dst == null:
		return
	dst.store_string(text)
	dst.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH))


func _ready() -> void:
	_migrate_legacy_save()


func save_run() -> void:
	if not run_active:
		return
	if active_slot < 0 or active_slot >= SAVE_SLOTS:
		push_warning("RunState.save_run: invalid active_slot %d, defaulting to 0" % active_slot)
		active_slot = 0
	# JSON converts integer dict keys to strings, so card_upgrades keys come
	# back as Strings on load — we convert back in load_run().
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"hero_max_hp": hero_max_hp,
		"hero_hp": hero_hp,
		"gold": gold,
		"potions": potions,
		"deck": deck,
		"deck_uids": deck_uids,
		"card_upgrades": card_upgrades,
		"next_uid": _next_uid,
		"relics": relics,
		"map_data": map_data,
		"current_act_idx": current_act_idx,
		"map_position": map_position,
		"current_encounter_id": current_encounter_id,
		"current_node_type": current_node_type,
		"events_seen": events_seen,
		"base_max_mana": base_max_mana,
		"current_floor": current_floor,
		"run_seed": run_seed,
		"phoenix_heart_consumed": phoenix_heart_consumed,
		"current_ascension": current_ascension,
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	var path := _save_path_for_slot(active_slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("RunState.save_run: could not open %s for write" % path)
		return
	f.store_string(JSON.stringify(payload))
	f.close()


# All three slot accessors take an optional slot. -1 means "use the active
# slot" so existing call sites that don't know about slots keep working.
func has_save(slot: int = -1) -> bool:
	var s: int = slot if slot >= 0 else active_slot
	if s < 0 or s >= SAVE_SLOTS:
		return false
	return FileAccess.file_exists(_save_path_for_slot(s))


func clear_save(slot: int = -1) -> void:
	var s: int = slot if slot >= 0 else active_slot
	if s < 0 or s >= SAVE_SLOTS:
		return
	var path := _save_path_for_slot(s)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# Loads and parses a save file, returning the raw Dictionary or {} on failure.
# Shared by load_run() and get_slot_summary() so summary headers don't have
# to duplicate the parse/version-check logic.
func _read_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= SAVE_SLOTS:
		return {}
	var path := _save_path_for_slot(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		return {}
	return data


# Returns a small summary of a slot for the menu's slot picker:
#   {has_save: bool, act: int, floor: int, hp: int, max_hp: int,
#    gold: int, ascension: int, saved_at: int}
# If the slot is empty or corrupt, has_save is false and other fields are 0.
func get_slot_summary(slot: int) -> Dictionary:
	var data := _read_slot(slot)
	if data.is_empty():
		return {"has_save": false}
	return {
		"has_save": true,
		"act": int(data.get("current_act_idx", 0)) + 1,
		"floor": int(data.get("current_floor", 0)),
		"hp": int(data.get("hero_hp", 0)),
		"max_hp": int(data.get("hero_max_hp", 25)),
		"gold": int(data.get("gold", 0)),
		"ascension": int(data.get("current_ascension", 0)),
		"saved_at": int(data.get("saved_at", 0)),
	}


func load_run(slot: int = -1) -> bool:
	var s: int = slot if slot >= 0 else active_slot
	var data := _read_slot(s)
	if data.is_empty():
		return false

	hero_max_hp = int(data.get("hero_max_hp", 25))
	hero_hp = int(data.get("hero_hp", 25))
	gold = int(data.get("gold", 0))
	potions = int(data.get("potions", 0))
	# Rebuild typed arrays from the plain JSON arrays.
	deck = []
	for id in data.get("deck", []):
		deck.append(String(id))
	deck_uids = []
	for uid in data.get("deck_uids", []):
		deck_uids.append(int(uid))
	# JSON int-keyed dicts come back as String keys — convert.
	card_upgrades = {}
	var raw_upgrades: Dictionary = data.get("card_upgrades", {})
	for k in raw_upgrades:
		card_upgrades[int(k)] = raw_upgrades[k]
	_next_uid = int(data.get("next_uid", deck.size()))
	relics = []
	for id in data.get("relics", []):
		relics.append(String(id))
	map_data = data.get("map_data", [])
	current_act_idx = int(data.get("current_act_idx", 0))
	map_position = data.get("map_position", {"row": -1, "col": -1})
	current_encounter_id = String(data.get("current_encounter_id", ""))
	current_node_type = String(data.get("current_node_type", ""))
	events_seen = []
	for id in data.get("events_seen", []):
		events_seen.append(String(id))
	base_max_mana = int(data.get("base_max_mana", 3))
	current_floor = int(data.get("current_floor", 0))
	run_seed = int(data.get("run_seed", 0))
	phoenix_heart_consumed = bool(data.get("phoenix_heart_consumed", false))
	current_ascension = int(data.get("current_ascension", 0))
	run_active = true
	active_slot = s
	CardTextureCache.clear()
	return true
