extends Node
## RunState.gd — autoload singleton. Holds the current run's persistent data.
## Generates a branching map across 3 acts. Tracks deck, relics, gold, upgrades.

# ── Hero ──
var hero_max_hp: int = 25
var hero_hp: int = 25
var gold: int = 0
# Id of the hero picked at the start of the run. Used by the rest screen to
# pick the right silhouette / flavor strings; otherwise the run is hero-agnostic
# (deck and signature relic are baked in at start_new_run time). Falls back to
# HeroDB.DEFAULT_HERO if anyone reads this before start_new_run() ran.
var current_hero_id: String = ""
# Rest-screen counters. `rests_visited_in_act` resets when the act advances and
# powers the time-of-day shader tint (first rest = dusk, second = night). Whetstone
# also reads this to determine "first rest of act". Persisted via save_state below.
var rests_visited_in_act: int = 0
var rests_visited_total: int = 0
var whetstone_used_this_act: bool = false
# Array of potion ids the player currently holds (max 3). Each id is a key
# into PotionDB.POTIONS.
var potions: Array[String] = []
const MAX_POTIONS: int = 3

# ── Deck ──
var deck: Array[String] = []
var deck_uids: Array[int] = []
var card_upgrades: Dictionary = {}
var _next_uid: int = 0

# ── Relics ──
var relics: Array[String] = []
# Per-act choice stash for "Each act, pick X" relics. The MapView picker writes
# the choice + the act it was made for; a mismatch with get_act() re-prompts at
# the start of the next act. Empty string = no choice made yet this act.
var totem_pole_keyword: String = ""
var totem_pole_act: int = 0
var bone_hourglass_choice: String = ""
var bone_hourglass_act: int = 0
# Bottled Talisman: deck_uid the player bound at acquisition. -1 = unbound (the
# MapView/acquire-screen picker will prompt for a card). Combat pulls this uid
# into the opening hand every fight.
var bottled_talisman_uid: int = -1

# ── Map ──
var map_data: Array = []
var current_act_idx: int = 0
var map_position: Dictionary = {"row": -1, "col": -1}
var current_encounter_id: String = ""
var current_node_type: String = ""
var current_mutator_id: String = ""
# Run statistics — surfaced on the GameOver recap screen. Reset by
# start_new_run, updated by Combat on each victory / death, persisted in
# the save file so a quit-mid-run resume keeps the running counts.
var fights_won: int = 0
var mutators_survived: Array[String] = []
var cause_of_death: String = ""  # encounter name that killed the player
var events_seen: Array[String] = []

# ── Mana ──
var base_max_mana: int = 3

# ── Compatibility ──
var current_floor: int = 0
var run_active: bool = false
var run_seed: int = 0
var phoenix_heart_consumed: bool = false
# Marked One event delayed-payoff. Set by Event.gd, consumed by Combat.gd at
# the START of the next combat fight and immediately cleared. Both fields
# persist through save/load so closing the game between the event and the
# fight doesn't drop the payoff.
#   next_combat_gift_creature: {name, atk, hp, kw[]} placed in front-left lane
#   next_combat_mana_bonus: int added to max mana for the entire fight
var next_combat_gift_creature: Dictionary = {}
var next_combat_mana_bonus: int = 0
# Ascension level chosen for this run (0..MetaState.unlocked_ascension).
# Each tier scales encounter face HP (see ASCENSION_HP_MULT). Set in
# start_new_run; never modified mid-run.
var current_ascension: int = 0
# Per-ascension HP multiplier applied to encounter face HP. Index = ascension.
const ASCENSION_HP_MULT: Array[float] = [1.0, 1.20, 1.40, 1.60, 1.80, 2.0]

const ACTS: int = 3

# ── Campaign-map constants ──
# 7 columns wide, 8 rows tall (rows 0..6 are explorable, row 7 = boss).
# Shrunk from 15 rows on 2026-06-10: at ~38 sites the map reads as an
# abstract lattice; at 11–15 sites it reads as a campaign over real terrain
# (the Sicily plate in MapTerrain/MapView). _generate_act_map enforces the
# 11–15 window with an acceptance loop.
const MAP_WIDTH: int = 7
const MAP_HEIGHT: int = 8
const BOSS_ROW: int = 7
const REST_ROW: int = 6
const NUM_PATHS: int = 3
const MIN_ELITE_ROW: int = 3     # Elites/rest cannot appear before this row.

# Room-type probabilities (cumulative). combat 41%, event 22%, elite 10%,
# rest 12%, shop 10%, treasure 5%.
const PROB_SHOP: float = 0.10
const PROB_REST: float = 0.22    # 0.10 + 0.12
const PROB_ELITE: float = 0.32   # 0.22 + 0.10
const PROB_EVENT: float = 0.54   # 0.32 + 0.22
const PROB_TREASURE: float = 0.59  # 0.54 + 0.05


func get_act() -> int:
	return current_act_idx + 1


# ── Run lifecycle ──

## Compute today's daily-run seed from local-time YYYYMMDD. The same date
## across machines produces the same map, so daily runs are shareable.
func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


## Hash an arbitrary string into a deterministic seed. Used by custom-seed
## runs so a player can type "burningmeadow" and get the same map every time.
func seed_from_string(s: String) -> int:
	if s == "":
		return randi()
	# Simple FNV-1a-style hash so identical strings always hash identically
	# across runs (built-in `String.hash()` is also deterministic but the FNV
	# approach is easier to mentally replay if a player is debugging a seed).
	var h: int = 0x811c9dc5
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xffffffff
		h = (h * 0x01000193) & 0xffffffff
	return h


func start_new_run(hero_id: String = "", ascension: int = -1, seed_override: int = 0) -> void:
	hero_max_hp = 25
	hero_hp = 25
	gold = 100
	potions = []
	base_max_mana = 3
	# Per-run trigger flags — must be reset here, not just at declaration,
	# otherwise the value carries over from the previous run when the player
	# starts a new run from MainMenu without restarting the executable. A
	# fresh Phoenix Heart relic wouldn't have fired in that case.
	phoenix_heart_consumed = false
	next_combat_gift_creature = {}
	next_combat_mana_bonus = 0
	# Default to player's highest unlocked tier if caller didn't pick one.
	if ascension < 0:
		current_ascension = MetaState.unlocked_ascension
	else:
		current_ascension = clampi(ascension, 0, MetaState.unlocked_ascension)
	# Resolve hero. "" means "use the default" — keeps any legacy code path
	# that called start_new_run() with no args working (it'll land on Stalwart).
	var hero_key: String = hero_id if hero_id != "" else HeroDB.DEFAULT_HERO
	current_hero_id = hero_key
	rests_visited_in_act = 0
	rests_visited_total = 0
	whetstone_used_this_act = false
	totem_pole_keyword = ""
	totem_pole_act = 0
	bone_hourglass_choice = ""
	bone_hourglass_act = 0
	bottled_talisman_uid = -1
	var hero: Dictionary = HeroDB.get_hero(hero_key)
	deck = []
	deck_uids = []
	card_upgrades = {}
	_next_uid = 0
	for id in hero.get("deck", CardDB.STARTER_DECK):
		add_card(id)
	relics = []
	var hero_relic: String = hero.get("relic", "")
	if hero_relic != "":
		relics.append(hero_relic)
	current_floor = 0
	current_act_idx = 0
	map_position = {"row": -1, "col": -1}
	current_encounter_id = ""
	current_node_type = ""
	current_mutator_id = ""
	fights_won = 0
	mutators_survived = []
	cause_of_death = ""
	events_seen = []
	run_active = true
	# seed_override of 0 means "roll a fresh random seed". Non-zero values come
	# from daily_seed() / seed_from_string() so the map is reproducible.
	run_seed = seed_override if seed_override != 0 else randi()
	CardTextureCache.clear()
	_generate_map()


func end_run(victorious: bool) -> void:
	run_active = false
	_append_run_log(victorious)
	clear_save()  # save only persists in-progress runs; ended ones are gone
	if victorious:
		MetaState.record_victory()
	else:
		MetaState.record_defeat()


## Local balance telemetry: one CSV row per finished run (user://runs.csv).
## Turns playtests into data — where runs die, on what, with which hero —
## instead of vibes. Local file only; never leaves the machine.
func _append_run_log(victorious: bool) -> void:
	var path := "user://runs.csv"
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path,
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	if exists:
		f.seek_end()
	else:
		f.store_line("ended_at,result,hero,ascension,seed,act,floor,hp," +
			"max_hp,gold,fights_won,deck_size,relics,cause_of_death")
	f.store_line("%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
		Time.get_datetime_string_from_system(),
		"victory" if victorious else "defeat",
		current_hero_id, current_ascension, run_seed,
		get_act(), current_floor, hero_hp, hero_max_hp, gold,
		fights_won, deck.size(), relics.size(),
		cause_of_death.replace(",", ";")])
	f.close()


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
		"plus":
			# Per-card "+" upgrade. Reads CardDB.UPGRADES and merges every
			# defined delta into the card data. Blacksmith's Hammer bumps
			# stat-style deltas by +1 (so a Brute+ goes from +1/+1 to +2/+2),
			# matching the way the relic boosted the legacy Sharpen/Fortify
			# paths. The is_upgraded flag is read by Combat.gd custom-spell
			# resolvers (dmg_bonus, slay_draw, etc.) and by Card2D to pick
			# the upgraded rarity tint.
			d = _apply_plus_upgrade(d)
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
		"fortify_neg":
			# Event-only "negative fortify" — used by the debuff_starters event
			# (Event.gd:420) to drop a starter creature's max HP by 1 permanently.
			# Floored at 1 so we never store a non-positive HP that would crash
			# combat (a 0-hp card would die instantly on placement).
			if d.type == "creature":
				d.hp = maxi(1, d.hp - 1)
		"butcher":
			# Butcher event payoff: +2 ATK and Wither 1 on a creature. The Event
			# screen advertises both halves — previously we only applied the ATK
			# half via the "sharpen" path so the downside was free-skipped.
			if d.type == "creature":
				d.atk += 2
				if not d.keywords.has("wither"):
					d.keywords.append("wither")
				d.wither = maxi(1, int(d.get("wither", 0)))
		"mirror_twin":
			# Mirror-Twin event payoff: a glass-cannon trade — HP drops to 1, ATK
			# gains a flat +4. Capped (not "ATK += old HP") so a 2/10 wall can't
			# become a 12/1 freight train; this stays a calculated risk, not an
			# auto-pick on tank cards.
			if d.type == "creature":
				d.atk += 4
				d.hp = 1
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
					# "Double effect + Exhaust" — only apply the Exhaust downside
					# when the doubling actually landed. Custom spells (Echo,
					# War Chant, Reanimate, etc.) don't read spell.value, so they
					# can't be doubled — and giving them Exhaust without the
					# upside was strictly worse than skipping the upgrade.
					var doubled := false
					if d.has("spell") and d.spell.has("value"):
						d.spell.value *= 2
						doubled = true
					if doubled and not d.keywords.has("exhaust"):
						d.keywords.append("exhaust")
	d.name = d.name + " +"
	return d


# Applies a CardDB.UPGRADES delta to a card's data dict. Every field is
# optional; missing fields silently no-op. Stat deltas (atk/hp) get +1 from
# Blacksmith's Hammer; numeric sub-effect bumps and dmg_bonus do not — those
# are tuned per-card and should stay at their authored value.
# Public preview of the "+" upgrade for a given card data dict, used by the
# Rest screen to render the comparison without mutating deck state. Pure
# function — caller passes a copy or accepts that the return shares no refs
# with the input (we deep-duplicate before merging). Mirrors the " +" name
# suffix that _apply_upgrade tacks on for live cards so the preview matches.
func preview_plus_upgrade(data: Dictionary) -> Dictionary:
	var out: Dictionary = _apply_plus_upgrade(data.duplicate(true))
	out.name = String(out.get("name", "")) + " +"
	return out


func _apply_plus_upgrade(d: Dictionary) -> Dictionary:
	var card_id: String = String(d.get("id", ""))
	var u: Dictionary = CardDB.get_plus_upgrade(card_id)
	if u.is_empty():
		return d
	var stat_bonus: int = 1 if has_relic("blacksmiths_hammer") else 0
	# Creature stats
	if d.get("type", "") == "creature":
		if u.has("atk"):
			d.atk = maxi(0, int(d.get("atk", 0)) + int(u.atk) + (stat_bonus if int(u.atk) > 0 else 0))
		if u.has("hp"):
			d.hp = maxi(1, int(d.get("hp", 1)) + int(u.hp) + (stat_bonus if int(u.hp) > 0 else 0))
		if u.has("adj_buff_atk") and d.has("adj_buff"):
			d.adj_buff.atk = int(d.adj_buff.get("atk", 0)) + int(u.adj_buff_atk)
		if u.has("adj_buff_hp") and d.has("adj_buff"):
			d.adj_buff.hp = int(d.adj_buff.get("hp", 0)) + int(u.adj_buff_hp)
		if u.has("wither"):
			d.wither = maxi(0, int(d.get("wither", 0)) + int(u.wither))
		if u.has("extra_damage"):
			d.extra_damage = int(d.get("extra_damage", 0)) + int(u.extra_damage)
		if u.has("on_enter_value") and d.has("on_enter") and d.on_enter.has("value"):
			d.on_enter.value = int(d.on_enter.value) + int(u.on_enter_value)
		if u.has("on_death_value") and d.has("on_death") and d.on_death.has("value"):
			d.on_death.value = int(d.on_death.value) + int(u.on_death_value)
		if u.has("on_death_atk") and d.has("on_death") and d.on_death.has("atk"):
			d.on_death.atk = int(d.on_death.atk) + int(u.on_death_atk)
		if u.has("on_death_hp") and d.has("on_death") and d.on_death.has("hp"):
			d.on_death.hp = int(d.on_death.hp) + int(u.on_death_hp)
		if u.has("on_play_value") and d.has("on_play") and d.on_play.has("value"):
			d.on_play.value = int(d.on_play.value) + int(u.on_play_value)
		if u.has("on_play_atk_gain") and d.has("on_play") and d.on_play.has("atk_gain"):
			d.on_play.atk_gain = int(d.on_play.atk_gain) + int(u.on_play_atk_gain)
		if u.has("on_play_atk") and d.has("on_play") and d.on_play.has("atk"):
			d.on_play.atk = int(d.on_play.atk) + int(u.on_play_atk)
		if u.has("on_play_hp") and d.has("on_play") and d.on_play.has("hp"):
			d.on_play.hp = int(d.on_play.hp) + int(u.on_play_hp)
		if u.has("on_play_heal") and d.has("on_play") and d.on_play.has("heal"):
			d.on_play.heal = int(d.on_play.heal) + int(u.on_play_heal)
	# Cost (any card)
	if u.has("cost"):
		d.cost = maxi(0, int(d.get("cost", 0)) + int(u.cost))
	# Spell value (non-custom spells with a value field)
	if u.has("value") and d.has("spell") and d.spell.has("value"):
		d.spell.value = int(d.spell.value) + int(u.value)
	# Keywords add/remove
	if u.has("add_keywords"):
		var kw_list: Array = d.get("keywords", [])
		for kw in u.add_keywords:
			if not kw_list.has(kw):
				kw_list.append(kw)
		d.keywords = kw_list
	if u.has("remove_keywords"):
		var kw_list2: Array = d.get("keywords", [])
		for kw in u.remove_keywords:
			kw_list2.erase(kw)
		d.keywords = kw_list2
	# Tail-effect bonus fields that custom resolvers consult by name. These
	# only matter if the card's resolver reads them — declaring them here is
	# free for cards that don't (it's just a no-op merge).
	for k in ["dmg_bonus", "slay_draw", "slay_gold", "slay_mana",
			"extra_draw", "extra_mana", "ricochet_hits"]:
		if u.has(k):
			d[k] = int(u[k])
	# Description override — applied last so it wins over any auto-generated
	# desc. Card2D reads card_data.desc verbatim.
	if u.has("desc"):
		d.desc = String(u.desc)
	# Flag for Card2D / Combat to detect the upgrade visually + behaviorally.
	d.is_upgraded = true
	return d


# ── Relic manipulation ──

func add_relic(id: String) -> void:
	if relics.has(id):
		return
	relics.append(id)
	_apply_relic_on_acquire(id)


# Side effects that fire the moment a relic enters the player's collection.
# Lives here (not in Combat.gd) so Reward / Shop / Treasure / Event all share
# the same logic. Keep this branch SMALL — most relics react to combat hooks,
# not acquisition, and belong in Combat.gd instead.
func _apply_relic_on_acquire(id: String) -> void:
	match id:
		"pandoras_box":
			_pandoras_box_transform()
		"calling_bell":
			_calling_bell_grant()
		# totem_pole / bone_hourglass deliberately do NOTHING on acquire: their
		# "each act, pick" choice is prompted by the MapView picker at the start of
		# every act (see MapView._resolve_meta_pickers). bottled_talisman likewise
		# binds via a picker (acquire screen or MapView catch-all), not here.


func _pandoras_box_transform() -> void:
	# Replace every starter-rarity CREATURE in the deck with a random rare
	# creature id. Spells and any later additions (commons/uncommons/rares,
	# curses, tokens) are untouched so the deck stops looking like "hero starter".
	# card_upgrades is keyed by deck_uid: erase the entry for each replaced
	# slot so prior upgrade payloads don't carry onto the new card identity.
	var rare_creatures: Array[String] = []
	for cid in CardDB.get_pool_by_rarity("rare"):
		if CardDB.get_card_data(cid).get("type", "") == "creature":
			rare_creatures.append(cid)
	if rare_creatures.is_empty():
		return
	for i in deck.size():
		var entry: String = deck[i]
		var data: Dictionary = CardDB.get_card_data(entry)
		if data.get("type", "") == "creature" and data.get("rarity", "") == "starter":
			deck[i] = rare_creatures[randi() % rare_creatures.size()]
			card_upgrades.erase(deck_uids[i])


func _calling_bell_grant() -> void:
	# Roll up to 3 boss relics the player doesn't already own and add them
	# directly (no UI pick — this IS the payoff). Recurses through add_relic
	# so each rolled relic gets its OWN acquire-side-effect chance. Then
	# pad the deck with 3 random curses as the cost.
	var picks: Array[String] = RelicDB.roll_boss_relics(relics, current_hero_id)
	for new_id in picks:
		add_relic(new_id)
	for _i in 3:
		add_card(CardDB.random_curse_id())


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


## Jittered fight reward (±25% around `base`) so payouts land on odd numbers, not fixed amounts.
func roll_gold_reward(base: int) -> int:
	var spread: int = int(round(base * 0.25))
	return base + randi_range(-spread, spread)


func get_max_mana() -> int:
	return base_max_mana + RelicDB.get_boss_mana_bonus(relics)


func has_downside(downside: String) -> bool:
	return RelicDB.has_downside(relics, downside)


# ── Potions ──

func can_add_potion() -> bool:
	return potions.size() < MAX_POTIONS and not has_downside("no_potions")


func add_potion(id: String) -> bool:
	if not can_add_potion():
		return false
	if not PotionDB.POTIONS.has(id):
		push_warning("RunState.add_potion: unknown id '%s'" % id)
		return false
	potions.append(id)
	return true


func consume_potion(index: int) -> String:
	## Removes and returns the potion id at `index`. Used by callers that
	## resolve the effect themselves (Combat has gameplay context; MapView
	## handles map-applicable effects). Returns "" if index is invalid.
	if index < 0 or index >= potions.size():
		return ""
	var id: String = potions[index]
	potions.remove_at(index)
	return id


func first_potion_index(id: String) -> int:
	return potions.find(id)


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
			current_mutator_id = n.get("mutator_id", "")
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
	current_mutator_id = ""
	# Per-act rest counters reset so the time-of-day shader tint (dusk → night)
	# restarts each act, and Whetstone's "first rest of act" payoff re-arms.
	rests_visited_in_act = 0
	whetstone_used_this_act = false
	# Centaur Heart: reaching Act 2 (current_act_idx now == 1) grants +5 max HP
	# and heals to full. Fires once per relic — guard via meta flag held on
	# the relic id so a re-entry doesn't keep re-applying.
	if has_relic("centaur_heart") and current_act_idx == 1:
		hero_max_hp += 5
		hero_hp = hero_max_hp


## Called by Rest.gd when the player commits to staying at a rest node (any
## option — Heal/Upgrade/Remove/Reforge). Increments both counters so the next
## rest screen knows it's not the first of the act. Saves immediately because
## the scene transition that follows can drop these values otherwise (the next
## save normally fires on the *next* map-node visit_node, which is too late if
## the player force-quits between rest and the map screen — Whetstone could
## otherwise be re-spent because whetstone_used_this_act never persisted).
func register_rest_visit() -> void:
	rests_visited_in_act += 1
	rests_visited_total += 1
	save_run()


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
	# Acceptance loop: only acts with 11–15 sites (incl. boss) read as a
	# campaign map — fewer is degenerate, more re-grows the lattice. One
	# value is drawn from the shared rng per act so later acts stay
	# deterministic regardless of how many attempts this act needed.
	var base_seed: int = rng.randi()
	var flat: Array = []
	for attempt in range(60):
		var arng := RandomNumberGenerator.new()
		arng.seed = base_seed + attempt * 7919
		var grid: Array = []
		for r in range(MAP_HEIGHT):
			var row: Array = []
			for c in range(MAP_WIDTH):
				row.append(null)
			grid.append(row)
		_generate_paths(grid, arng)
		_assign_node_types(grid, arng)
		_add_boss_node(grid)
		_assign_encounters(grid, act, arng)
		flat = _flatten_grid(grid)
		var n: int = 0
		for row_nodes in flat:
			n += (row_nodes as Array).size()
		if n >= 11 and n <= 15:
			return flat
	return flat


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
		"mutator_id": "",
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
			# Strong merge bias (3×): paths converge into a trunk road with
			# branches — the validated campaign-map look.
			candidates.append(nc)
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
		elif roll < PROB_TREASURE:
			t = "treasure"
		else:
			t = "combat"
		if (t == "elite" or t == "rest") and r < MIN_ELITE_ROW:
			continue
		if t == "treasure" and r < MIN_ELITE_ROW:
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
	# STS: elite/shop/rest/treasure can't follow the same type on any incoming path.
	if t != "elite" and t != "shop" and t != "rest" and t != "treasure":
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
					node["mutator_id"] = MutatorDB.roll(0.35, rng)
				"elite":
					if elite_ids.size() > 0:
						node["encounter_id"] = elite_ids[elite_idx % elite_ids.size()]
						elite_idx += 1
					node["mutator_id"] = MutatorDB.roll(0.65, rng)
				"boss":
					if boss_ids.size() > 0:
						node["encounter_id"] = boss_ids[0]
					# Bosses keep their own complex passives — no mutator on boss
					# fights to avoid stacking too many parallel rule changes.


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

# v2: campaign-map act shrink (15→8 rows, 11–15 sites). v1 saves carry
# 15-row map_data the Sicily plate was never sized for; the strict version
# check below retires them as empty slots rather than migrating.
const SAVE_VERSION: int = 2
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
		"current_mutator_id": current_mutator_id,
		"fights_won": fights_won,
		"mutators_survived": mutators_survived,
		"cause_of_death": cause_of_death,
		"events_seen": events_seen,
		"base_max_mana": base_max_mana,
		"current_floor": current_floor,
		"run_seed": run_seed,
		"phoenix_heart_consumed": phoenix_heart_consumed,
		"next_combat_gift_creature": next_combat_gift_creature,
		"next_combat_mana_bonus": next_combat_mana_bonus,
		"current_ascension": current_ascension,
		"current_hero_id": current_hero_id,
		"rests_visited_in_act": rests_visited_in_act,
		"rests_visited_total": rests_visited_total,
		"whetstone_used_this_act": whetstone_used_this_act,
		"totem_pole_keyword": totem_pole_keyword,
		"totem_pole_act": totem_pole_act,
		"bone_hourglass_choice": bone_hourglass_choice,
		"bone_hourglass_act": bone_hourglass_act,
		"bottled_talisman_uid": bottled_talisman_uid,
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
	# potions was an int (count of generic heal potions) in older saves; new
	# saves store an Array[String] of potion ids. Migrate legacy saves by
	# expanding the int into N healing potions so existing runs don't lose them.
	var raw_potions = data.get("potions", [])
	potions = []
	if typeof(raw_potions) == TYPE_ARRAY:
		for pid in raw_potions:
			potions.append(String(pid))
	else:
		var n: int = int(raw_potions)
		for _i in range(n):
			potions.append("healing")
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
	current_mutator_id = String(data.get("current_mutator_id", ""))
	fights_won = int(data.get("fights_won", 0))
	mutators_survived = []
	for m in data.get("mutators_survived", []):
		mutators_survived.append(String(m))
	cause_of_death = String(data.get("cause_of_death", ""))
	events_seen = []
	for id in data.get("events_seen", []):
		events_seen.append(String(id))
	base_max_mana = int(data.get("base_max_mana", 3))
	current_floor = int(data.get("current_floor", 0))
	run_seed = int(data.get("run_seed", 0))
	phoenix_heart_consumed = bool(data.get("phoenix_heart_consumed", false))
	next_combat_gift_creature = data.get("next_combat_gift_creature", {})
	next_combat_mana_bonus = int(data.get("next_combat_mana_bonus", 0))
	current_ascension = int(data.get("current_ascension", 0))
	current_hero_id = String(data.get("current_hero_id", HeroDB.DEFAULT_HERO))
	rests_visited_in_act = int(data.get("rests_visited_in_act", 0))
	rests_visited_total = int(data.get("rests_visited_total", 0))
	whetstone_used_this_act = bool(data.get("whetstone_used_this_act", false))
	totem_pole_keyword = String(data.get("totem_pole_keyword", ""))
	totem_pole_act = int(data.get("totem_pole_act", 0))
	bone_hourglass_choice = String(data.get("bone_hourglass_choice", ""))
	bone_hourglass_act = int(data.get("bone_hourglass_act", 0))
	bottled_talisman_uid = int(data.get("bottled_talisman_uid", -1))
	run_active = true
	active_slot = s
	CardTextureCache.clear()
	return true
