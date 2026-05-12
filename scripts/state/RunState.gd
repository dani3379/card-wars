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

const ACTS: int = 3

const ROW_TEMPLATES: Array = [
	["combat", "combat"],
	["combat", "event", "combat"],
	["rest", "shop"],
	["combat", "combat", "event"],
	["combat", "combat"],
	["elite", "combat"],
	["rest", "shop"],
	["boss"],
]


func get_act() -> int:
	return current_act_idx + 1


func node_type_for_floor(_floor_num: int) -> String:
	return current_node_type


# ── Run lifecycle ──

func start_new_run() -> void:
	hero_max_hp = 25
	hero_hp = 25
	gold = 0
	potions = 0
	base_max_mana = 3
	deck = []
	deck_uids = []
	card_upgrades = {}
	_next_uid = 0
	for id in CardDB.STARTER_DECK:
		add_card(id)
	relics = []
	current_floor = 0
	current_act_idx = 0
	map_position = {"row": -1, "col": -1}
	current_encounter_id = ""
	current_node_type = ""
	events_seen = []
	run_active = true
	run_seed = randi()
	_generate_map()


func end_run(victorious: bool) -> void:
	run_active = false
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


func remove_card(id: String) -> bool:
	for i in range(deck.size()):
		if deck[i] == id:
			var uid = deck_uids[i]
			deck.remove_at(i)
			deck_uids.remove_at(i)
			card_upgrades.erase(uid)
			return true
	return false


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
	var row = map_position.row
	var col = map_position.col
	if row >= act_map.size():
		return []
	var current_node = act_map[row][col]
	var next_row = row + 1
	if next_row >= act_map.size():
		return []
	var available: Array = []
	for c in current_node.connections:
		if c < act_map[next_row].size():
			available.append(act_map[next_row][c])
	return available


func visit_node(row: int, col: int) -> void:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return
	map_position = {"row": row, "col": col}
	var node = act_map[row][col]
	node.visited = true
	current_node_type = node.type
	current_encounter_id = node.get("encounter_id", "")
	current_floor += 1


func advance_act() -> void:
	current_act_idx += 1
	map_position = {"row": -1, "col": -1}
	current_encounter_id = ""
	current_node_type = ""


func is_final_boss() -> bool:
	return current_act_idx >= ACTS - 1 and current_node_type == "boss"


func is_act_complete() -> bool:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return true
	return map_position.row >= act_map.size() - 1


# ── Map generation ──

func _generate_map() -> void:
	map_data = []
	var rng = RandomNumberGenerator.new()
	rng.seed = run_seed
	for act in range(1, ACTS + 1):
		map_data.append(_generate_act_map(act, rng))


func _generate_act_map(act: int, rng: RandomNumberGenerator) -> Array:
	var rows: Array = []
	var combat_ids = EncounterDB.get_ids_for(act, "combat").duplicate()
	_shuffle_array(combat_ids, rng)
	var elite_ids = EncounterDB.get_ids_for(act, "elite").duplicate()
	_shuffle_array(elite_ids, rng)
	var boss_ids = EncounterDB.get_ids_for(act, "boss").duplicate()
	_shuffle_array(boss_ids, rng)
	var combat_idx := 0

	for row_idx in range(ROW_TEMPLATES.size()):
		var template = ROW_TEMPLATES[row_idx]
		var row: Array = []
		for col_idx in range(template.size()):
			var ntype: String = template[col_idx]
			var encounter_id := ""
			match ntype:
				"combat":
					if combat_idx < combat_ids.size():
						encounter_id = combat_ids[combat_idx]
						combat_idx += 1
					elif combat_ids.size() > 0:
						encounter_id = combat_ids[rng.randi() % combat_ids.size()]
				"elite":
					if elite_ids.size() > 0:
						encounter_id = elite_ids[0]
				"boss":
					if boss_ids.size() > 0:
						encounter_id = boss_ids[0]
			row.append({
				"type": ntype,
				"encounter_id": encounter_id,
				"visited": false,
				"connections": [],
				"row": row_idx,
				"col": col_idx,
			})
		rows.append(row)

	_connect_rows(rows, rng)
	return rows


func _connect_rows(rows: Array, rng: RandomNumberGenerator) -> void:
	for row_idx in range(rows.size() - 1):
		var cur_row = rows[row_idx]
		var next_row = rows[row_idx + 1]
		var nr = next_row.size()
		var cr = cur_row.size()
		for col_idx in range(cr):
			var target = clampi(col_idx * nr / maxi(1, cr), 0, nr - 1)
			var conns: Array = [target]
			if rng.randf() < 0.4 and nr > 1:
				var alt = target + (1 if rng.randf() < 0.5 else -1)
				alt = clampi(alt, 0, nr - 1)
				if not conns.has(alt):
					conns.append(alt)
			cur_row[col_idx].connections = conns
		for col_idx in range(nr):
			var has_incoming := false
			for node in cur_row:
				if node.connections.has(col_idx):
					has_incoming = true
					break
			if not has_incoming:
				var nearest = clampi(col_idx * cr / maxi(1, nr), 0, cr - 1)
				cur_row[nearest].connections.append(col_idx)
	if rows.size() >= 2:
		for node in rows[rows.size() - 2]:
			node.connections = [0]


func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp
