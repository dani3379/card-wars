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
# Per-act campaign-plate cache (NOT saved): MapTerrain parks its generated
# mesh arrays + baked geography texture here, so re-opening the map after a
# room restores in one frame instead of regenerating ~hundreds of ms of
# terrain. Keyed by act index (1-3). Cleared on new run / load / act change.
var map_plate_cache: Dictionary = {}
var current_encounter_id: String = ""
var current_node_type: String = ""
var current_mutator_id: String = ""
# Phase 2.5 — the visited node's route terrain ("meadow"/"woods"/"pass"/
# "ash"; "" before the plate has tagged the act) and whether the road in
# crosses a river bridge. Event/Recruit read these to lean their offers.
var current_terrain: String = ""
var current_bridge: bool = false
# Run statistics — surfaced on the GameOver recap screen. Reset by
# start_new_run, updated by Combat on each victory / death, persisted in
# the save file so a quit-mid-run resume keeps the running counts.
var fights_won: int = 0
var mutators_survived: Array[String] = []
var cause_of_death: String = ""  # encounter name that killed the player
var events_seen: Array[String] = []

# ── Successor Wars: rivals & kingdoms ──
# The three rival lords this run marches on (hero ids; index = act_idx) and
# the spared fourth who waits on the throne as the finale amalgam. act_faction
# mirrors rival_lords with each lord's faction id — the kingdom each act
# takes place in. All dealt by _select_rivals() from run_seed; empty arrays
# mean a legacy save (pre-conquest), and consumers must fall back gracefully.
var rival_lords: Array[String] = []
var finale_rival: String = ""
var act_faction: Array[String] = []
# Combat/elite victories this act. The rival lord's keep unlocks at
# HOLDS_TO_OPEN_LORD broken holds (incremented by Combat on victory, reset by
# advance_act). Kept in RunState so it saves with the run.
var holds_broken_in_act: int = 0
# The boss gate (§15.1 #5): the keep is visible from the first step but
# locked until this many holds have fallen. Map generation guarantees every
# route to the keep carries at least this many fight nodes (no softlock).
const HOLDS_TO_OPEN_LORD: int = 2
# 0 = the three marches; 1 = the throne. After the act-3 rival falls, a
# conquest run routes into one last fight — the spared rival as an amalgam
# (amalgam_<finale_rival>) — before the real victory. Set by enter_finale,
# persisted so a quit at the throne door resumes into the fight (MapView
# redirects stage-1 resumes back into Combat; the throne is not a map node).
var finale_stage: int = 0


## False only while a conquest run still owes holds this act. Legacy runs
## (no rival deal) keep the old always-open keep.
func is_lord_gate_open() -> bool:
	if rival_lords.is_empty():
		return true
	return holds_broken_in_act >= HOLDS_TO_OPEN_LORD

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
# 7 columns wide, 10 rows tall (rows 0..8 are explorable, row 9 = keep).
# History: 15 rows → 8 on 2026-06-10 (at ~38 sites the map read as an
# abstract lattice, not a campaign over the plate) → 10 on 2026-06-12
# (the road-to-the-keep pass: fight count stays constant, the two new
# rows are wayside tissue — the Kaycee's-Mod length lesson: a road grows
# in verbs, not violence). _generate_act_map enforces a 14–19-site
# window with an acceptance loop.
const MAP_WIDTH: int = 7
const MAP_HEIGHT: int = 10
const BOSS_ROW: int = 9
const REST_ROW: int = 8
const NUM_PATHS: int = 3

# Row skeleton (Kaycee's-Mod model, 2026-06-12): every row carries a fixed
# BEAT — fight rows alternate with wayside rows — so the road's rhythm is
# guaranteed by construction and the within-row choice becomes "which
# flavor of this beat" (fights differ by terrain/kit, waysides by verb).
# This replaced the per-node probability table + sibling/consecutive rules:
# the skeleton can't deal a corridor of five straight fights, fight count
# per act is CONSTANT (4 + 1 elite + keep), and the road's extra length is
# all between-fights tissue. See _assign_node_types for the band content.
const FIGHT_ROWS: Array[int] = [0, 2, 6]   # plain holds (R4 = elite band)
const ELITE_ROW: int = 4                   # the act's mid-road spike


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
	map_plate_cache.clear()
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
	current_terrain = ""
	current_bridge = false
	fights_won = 0
	mutators_survived = []
	cause_of_death = ""
	events_seen = []
	holds_broken_in_act = 0
	finale_stage = 0
	run_active = true
	# seed_override of 0 means "roll a fresh random seed". Non-zero values come
	# from daily_seed() / seed_from_string() so the map is reproducible.
	run_seed = seed_override if seed_override != 0 else randi()
	_select_rivals()
	CardTextureCache.clear()
	_generate_map()


## Successor Wars rival deal. The pool is every hero the player didn't pick;
## a run_seed-derived shuffle deals the first three as act bosses (index =
## act_idx) and spares the fourth for the throne. Seeded order for now — the
## player-chosen order screen (CONQUEST_REDESIGN.md §15.1 #4) will re-deal
## the remaining acts at each act transition once it exists.
func _select_rivals() -> void:
	rival_lords = []
	act_faction = []
	finale_rival = ""
	var exclude: String = current_hero_id if HeroDB.has_hero(current_hero_id) \
		else HeroDB.DEFAULT_HERO
	var pool: Array = []
	for hid in HeroDB.HERO_ORDER:
		if hid != exclude:
			pool.append(hid)
	if pool.size() < ACTS + 1:
		# Roster shrank below 5 — leave rivals empty; map gen and boss wiring
		# fall back to the legacy unfiltered pools.
		push_warning("RunState: rival pool too small (%d), running legacy bosses" % pool.size())
		return
	var rng := RandomNumberGenerator.new()
	# Sub-seed (same trick as _generate_act_map) so the rival deal and the map
	# generator draw from independent streams of the same run seed.
	rng.seed = run_seed ^ 0x52495641
	_shuffle_array(pool, rng)
	for i in range(ACTS):
		rival_lords.append(String(pool[i]))
		act_faction.append(HeroDB.get_faction(String(pool[i])))
	finale_rival = String(pool[ACTS])


## Faction id of the kingdom the current act takes place in ("" on legacy
## runs with no rival deal — callers treat that as "no faction filter").
func get_act_faction() -> String:
	if current_act_idx < act_faction.size():
		return act_faction[current_act_idx]
	return ""


## The rival lord (hero id) ruling the current act's kingdom, "" on legacy runs.
func get_act_rival() -> String:
	if current_act_idx < rival_lords.size():
		return rival_lords[current_act_idx]
	return ""


## Successor Wars: the player picks which remaining rival to march on next
## (boss Reward, between acts — the player-chosen rival order). Swaps that
## lord into the next act's slot and keeps act_faction mirrored. No map regen
## needed — boss kits and kingdom pools read the deal late, at visit time.
func choose_next_rival(hero_id: String) -> void:
	var next_idx := current_act_idx + 1
	for i in range(next_idx, rival_lords.size()):
		if rival_lords[i] == hero_id:
			if i != next_idx:
				rival_lords[i] = rival_lords[next_idx]
				rival_lords[next_idx] = hero_id
				act_faction[i] = HeroDB.get_faction(rival_lords[i])
				act_faction[next_idx] = HeroDB.get_faction(hero_id)
			return
	push_warning("RunState: choose_next_rival('%s') not in remaining deal" % hero_id)


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
## The rival columns feed the Successor Wars matchup matrix (the project's
## dominant balancing cost): every dev run records who was marched on, in
## what order, who was spared, and how many holds the act had fallen.
const _RUN_LOG_HEADER: String = ("ended_at,result,hero,ascension,seed,act," +
	"floor,hp,max_hp,gold,fights_won,deck_size,relics,cause_of_death," +
	"rival_act1,rival_act2,rival_act3,finale_rival,holds_broken")


func _append_run_log(victorious: bool) -> void:
	var path := "user://runs.csv"
	# Schema change (rival columns): a file written with the old header can't
	# take the new rows — shelve it under a timestamped name and start fresh
	# rather than mixing two schemas in one CSV.
	if FileAccess.file_exists(path):
		var probe := FileAccess.open(path, FileAccess.READ)
		if probe != null:
			var first_line := probe.get_line()
			probe.close()
			if first_line != _RUN_LOG_HEADER:
				DirAccess.rename_absolute(ProjectSettings.globalize_path(path),
					ProjectSettings.globalize_path("user://runs_legacy_%d.csv"
						% int(Time.get_unix_time_from_system())))
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path,
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	if exists:
		f.seek_end()
	else:
		f.store_line(_RUN_LOG_HEADER)
	var r1: String = rival_lords[0] if rival_lords.size() > 0 else ""
	var r2: String = rival_lords[1] if rival_lords.size() > 1 else ""
	var r3: String = rival_lords[2] if rival_lords.size() > 2 else ""
	f.store_line("%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%d" % [
		Time.get_datetime_string_from_system(),
		"victory" if victorious else "defeat",
		current_hero_id, current_ascension, run_seed,
		get_act(), current_floor, hero_hp, hero_max_hp, gold,
		fights_won, deck.size(), relics.size(),
		cause_of_death.replace(",", ";"),
		r1, r2, r3, finale_rival, holds_broken_in_act])
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
			# The boss gate: the keep stays painted on the plate but its road
			# doesn't open until enough holds have fallen. Filtering here is
			# the single source of truth — buttons, road tint, and the pulse
			# overlay all read availability from this list. No softlock:
			# _generate_act_map guarantees every route carries enough fights.
			if String(n.type) == "boss" and not is_lord_gate_open():
				continue
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
			current_terrain = String(n.get("terrain", ""))
			current_bridge = bool(n.get("bridge", false))
			current_floor += 1
			save_run()  # checkpoint: player is committing to enter a room
			return


func _find_node_by_col(row_nodes: Array, col: int) -> Dictionary:
	for n in row_nodes:
		if n.col == col:
			return n
	return {}


## Phase 2.5 — once the plate has tagged this act's holds with terrain
## (MapTerrain._derive_terrain_tags, first open of the act), re-DEAL the
## already-dealt encounters onto terrain-matching nodes. The multiset of
## fights never changes — the player meets the same kits either way — they
## just land on coherent ground: ambush kits in the woods, armor on the
## pass, doom in the ash, the lightest deal on the meadow road. Pure
## function of (dealt multiset, tags): greedy over a total order, no RNG,
## so re-running it is idempotent. Gated to untouched acts so a mid-act
## save from before tagging never shuffles fights the player has already
## scouted via tooltips.
func apply_terrain_redeal() -> void:
	var act_map := get_current_act_map()
	if act_map.is_empty():
		return
	for row in act_map:
		for n in row:
			if bool(n.get("visited", false)):
				return
	var order := {"ash": 0, "woods": 1, "pass": 2, "meadow": 3}
	for node_type in ["combat", "elite"]:
		var nodes: Array = []
		for row in act_map:
			for n in row:
				if String(n.get("type", "")) == node_type \
						and String(n.get("terrain", "")) != "" \
						and String(n.get("encounter_id", "")) != "":
					nodes.append(n)
		if nodes.size() < 2:
			continue
		var pool: Array = []
		for n in nodes:
			pool.append(String(n.encounter_id))
		# Stage 0 (combat only) — the landing is always light: row-0 holds
		# take the lightest kits in the deal outright, terrain be damned.
		# The act opens like an invasion (skirmishes at the beachhead) and
		# the heavy deals are pushed up-road by construction.
		var rest_nodes: Array = []
		if node_type == "combat":
			var landing: Array = []
			for n in nodes:
				if int(n.row) == 0:
					landing.append(n)
				else:
					rest_nodes.append(n)
			landing.sort_custom(func(a, b): return int(a.col) < int(b.col))
			for n in landing:
				var li := 0
				for i in range(pool.size()):
					var wi: int = EncounterDB.kit_weight(pool[i])
					var wl: int = EncounterDB.kit_weight(pool[li])
					if wi < wl or (wi == wl and pool[i] < pool[li]):
						li = i
				n["encounter_id"] = pool[li]
				pool.remove_at(li)
		else:
			rest_nodes = nodes
		# Stage 1 — terrain claims the rest: ash holds pick first (rarest
		# ground, loudest theme), then woods, pass, meadow; (row, col)
		# breaks ties so the order is total.
		rest_nodes.sort_custom(func(a, b):
			var ta: int = order.get(String(a.terrain), 3)
			var tb: int = order.get(String(b.terrain), 3)
			if ta != tb:
				return ta < tb
			if int(a.row) != int(b.row):
				return int(a.row) < int(b.row)
			return int(a.col) < int(b.col))
		for n in rest_nodes:
			var best_i := 0
			var best_s: int = -(1 << 30)
			for i in range(pool.size()):
				var s: int = EncounterDB.terrain_affinity(pool[i], String(n.terrain))
				# Tie-break on the id itself, NOT pool position — the pool is
				# rebuilt in row-major node order on every call, so a position
				# tie-break made equal-scoring kits swap on a second pass
				# (idempotence is the whole determinism guarantee here).
				if s > best_s or (s == best_s and pool[i] < pool[best_i]):
					best_s = s
					best_i = i
			n["encounter_id"] = pool[best_i]
			pool.remove_at(best_i)
		# Stage 2 — escalation within terrain: every node in a terrain group
		# scores identically wherever its kit lands (affinity is a function
		# of kit x terrain alone), so permuting INSIDE a group is free.
		# Sort each group's kits light→heavy and lay them down the road in
		# row order: the deal sharpens as the keep nears.
		var groups: Dictionary = {}
		for n in rest_nodes:
			var t: String = String(n.terrain)
			if not groups.has(t):
				groups[t] = []
			groups[t].append(n)
		for t in groups:
			var grp: Array = groups[t]
			if grp.size() < 2:
				continue
			var kits: Array = []
			for n in grp:
				kits.append(String(n.encounter_id))
			kits.sort_custom(func(a, b):
				var wa: int = EncounterDB.kit_weight(a)
				var wb: int = EncounterDB.kit_weight(b)
				return wa < wb if wa != wb else a < b)
			grp.sort_custom(func(a, b):
				if int(a.row) != int(b.row):
					return int(a.row) < int(b.row)
				return int(a.col) < int(b.col))
			for i in range(grp.size()):
				grp[i]["encounter_id"] = kits[i]


func advance_act() -> void:
	current_act_idx += 1
	map_position = {"row": -1, "col": -1}
	# Last act's plate (mesh + ~23MB geo texture) can't be revisited — drop it.
	map_plate_cache.clear()
	current_encounter_id = ""
	current_node_type = ""
	current_mutator_id = ""
	current_terrain = ""
	current_bridge = false
	# Per-act rest counters reset so the time-of-day shader tint (dusk → night)
	# restarts each act, and Whetstone's "first rest of act" payoff re-arms.
	rests_visited_in_act = 0
	whetstone_used_this_act = false
	# Fresh kingdom, fresh siege: the next rival's keep starts locked.
	holds_broken_in_act = 0
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


## True when the act-3 rival just fell and the throne still waits: the run
## should route into the amalgam finale instead of ending. False on legacy
## runs and when the spared rival's amalgam kit isn't authored yet — those
## runs end at the act-3 boss exactly as before.
func should_enter_finale() -> bool:
	return finale_stage == 0 and current_act_idx >= ACTS - 1 \
		and current_node_type == "boss" and finale_rival != "" \
		and EncounterDB.ENCOUNTERS.has("amalgam_" + finale_rival)


## Routes the run into the throne fight. Saves immediately — the checkpoint
## at the throne door survives a quit.
func enter_finale() -> void:
	finale_stage = 1
	current_encounter_id = "amalgam_" + finale_rival
	current_mutator_id = ""
	save_run()


func is_final_boss() -> bool:
	if finale_stage == 1:
		return true
	return current_act_idx >= ACTS - 1 and current_node_type == "boss" \
		and not should_enter_finale()


# ── Map generation ──

func _generate_map() -> void:
	map_data = []
	var rng = RandomNumberGenerator.new()
	rng.seed = run_seed
	for act in range(1, ACTS + 1):
		map_data.append(_generate_act_map(act, rng))


## Generates a single act map:
##   1. Walk NUM_PATHS paths from row 0 up to REST_ROW, ±1 column per step,
##      with a no-crossing constraint and a 3x merge bias (trunk + branches).
##   2. Stamp the Kaycee's-Mod row skeleton over the lattice — fight rows
##      alternating with wayside bands; guarantees placed, not rolled
##      (see _assign_node_types).
##   3. Add a single boss node at the BOSS_ROW center, with every populated
##      REST_ROW node connecting up to it.
##   4. Walk through and assign encounter IDs to combat/elite/boss nodes.
func _generate_act_map(act: int, rng: RandomNumberGenerator) -> Array:
	# Acceptance loop: only acts with 14–19 sites (incl. boss) read as a
	# campaign over the plate — fewer is degenerate, more re-grows the
	# lattice. One value is drawn from the shared rng per act so later acts
	# stay deterministic regardless of how many attempts this act needed.
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
		# Site-count window AND boss-gate guarantee: the worst route a player
		# can walk must still pass HOLDS_TO_OPEN_LORD fight nodes, or the
		# locked keep could softlock the act. (The skeleton makes the fight
		# minimum 4 by construction — the DFS check stays as a tripwire.)
		if n >= 14 and n <= 19 and _min_fights_to_rest(flat) >= HOLDS_TO_OPEN_LORD:
			return flat
	return flat


## Minimum number of combat/elite nodes along ANY root→rest-row route — the
## fewest fights a player can reach the keep with. Memoized DFS over the DAG.
func _min_fights_to_rest(flat: Array) -> int:
	if flat.is_empty() or (flat[0] as Array).is_empty():
		return 0
	var memo: Dictionary = {}
	var best: int = 999
	for start in flat[0]:
		best = mini(best, _min_fights_from(flat, 0, int(start.col), memo))
	return best


func _min_fights_from(flat: Array, row: int, col: int, memo: Dictionary) -> int:
	var node: Dictionary = _find_node_by_col(flat[row], col)
	if node.is_empty():
		return 999
	var key: int = row * 100 + col
	if memo.has(key):
		return memo[key]
	var self_cost: int = 1 if String(node.type) in ["combat", "elite"] else 0
	if row >= REST_ROW:
		memo[key] = self_cost
		return self_cost
	var best: int = 999
	for nc in node.connections:
		best = mini(best, _min_fights_from(flat, row + 1, int(nc), memo))
	var total: int = self_cost + (best if best < 999 else 0)
	memo[key] = total
	return total


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
	# The row skeleton. Fight rows and the rest row are uniform; the elite
	# band gets exactly one elite (the act's stronghold spike — forced onto
	# every route when the band is a single merge point, avoidable when the
	# row is wider); wayside rows deal their band's flavors round-robin so
	# siblings differ wherever the row has width.
	#   R0 fight (the landing — lightest deal, see apply_terrain_redeal)
	#   R1 wayside: events
	#   R2 fight
	#   R3 wayside: the muster band — recruit guaranteed, shop beside it
	#   R4 fight: the elite band
	#   R5 wayside: events, sometimes a second muster
	#   R6 fight
	#   R7 wayside: the spoils band — treasure guaranteed
	#   R8 rest (the war-council breather)   R9 keep
	for c in range(MAP_WIDTH):
		if grid[REST_ROW][c] != null:
			grid[REST_ROW][c]["type"] = "rest"
	for r in FIGHT_ROWS:
		for node in _row_nodes(grid, r):
			node["type"] = "combat"
	var band: Array = _row_nodes(grid, ELITE_ROW)
	for node in band:
		node["type"] = "combat"
	if not band.is_empty():
		band[rng.randi() % band.size()]["type"] = "elite"
	_fill_wayside_row(grid, 1, ["event", "recruit"], rng)
	_fill_wayside_row(grid, 3, ["shop", "event"], rng)
	_fill_wayside_row(grid, 5, ["event", "event", "recruit"], rng)
	_fill_wayside_row(grid, 7, ["shop", "event"], rng)
	# A row offers at most one muster — R1's two-flavor pool can round-robin
	# recruit twice across a 3-wide row. Demoting duplicates to events keeps
	# camps at one per band (early/mid/late => never more than 3 per act).
	for r in [1, 3, 5, 7]:
		var seen_recruit := false
		for node in _row_nodes(grid, r):
			if String(node["type"]) == "recruit":
				if seen_recruit:
					node["type"] = "event"
				seen_recruit = true
	# Placed guarantees (not prayed-for rolls): the muster camp, the
	# treasure, and at least one shop somewhere on the road. R1/R5 pools
	# can add a second or third muster — deck growth lives at camps in the
	# conquest economy (fights pay gold, not cards), so expected musters
	# stay ~2 per act (range 1-3), matching the old early/mid/late bands.
	_force_one(grid, 3, "recruit", rng)
	_force_one(grid, 7, "treasure", rng)
	if _count_type(grid, "shop") == 0:
		for r in [7, 3, 5]:
			if _force_one(grid, r, "shop", rng):
				break


func _row_nodes(grid: Array, r: int) -> Array:
	var out: Array = []
	for c in range(MAP_WIDTH):
		if grid[r][c] != null:
			out.append(grid[r][c])
	return out


## Deal a wayside band's flavors across the row, round-robin from a random
## offset — siblings differ whenever the row is wider than one site.
func _fill_wayside_row(grid: Array, r: int, pool: Array,
		rng: RandomNumberGenerator) -> void:
	var i: int = rng.randi() % pool.size()
	for node in _row_nodes(grid, r):
		node["type"] = pool[i % pool.size()]
		i += 1


## Stamp `t` onto one PLAIN node (event/shop) of row `r` — never onto an
## already-placed guarantee (a single-site muster row must not lose its
## recruit to the shop fallback). Returns false if the row has no plain slot.
func _force_one(grid: Array, r: int, t: String,
		rng: RandomNumberGenerator) -> bool:
	var plain: Array = []
	for node in _row_nodes(grid, r):
		if String(node["type"]) in ["event", "shop"]:
			plain.append(node)
	if plain.is_empty():
		return false
	plain[rng.randi() % plain.size()]["type"] = t
	return true


func _count_type(grid: Array, t: String) -> int:
	var n: int = 0
	for r in range(MAP_HEIGHT):
		for c in range(MAP_WIDTH):
			if grid[r][c] != null and String(grid[r][c]["type"]) == t:
				n += 1
	return n


func _add_boss_node(grid: Array) -> void:
	var boss_col: int = MAP_WIDTH / 2
	grid[BOSS_ROW][boss_col] = _make_node(boss_col, BOSS_ROW)
	grid[BOSS_ROW][boss_col]["type"] = "boss"
	for c in range(MAP_WIDTH):
		if grid[REST_ROW][c] != null:
			grid[REST_ROW][c]["connections"] = [boss_col]


func _assign_encounters(grid: Array, act: int,
		rng: RandomNumberGenerator) -> void:
	# Successor Wars: every hold in the kingdom belongs to the act's faction
	# (the rival being marched on). Thin factions borrow their own fights
	# from other acts — Combat rescales them via the target_act rails. On a
	# legacy run with no rival deal, faction is "" and the pools fall back
	# to the unfiltered act lists (get_kingdom_pool passes through).
	var faction: String = act_faction[act - 1] if act - 1 < act_faction.size() else ""
	var combat_ids: Array = EncounterDB.get_kingdom_pool(act, "combat", faction)
	_shuffle_array(combat_ids, rng)
	var elite_ids: Array = EncounterDB.get_kingdom_pool(act, "elite", faction)
	_shuffle_array(elite_ids, rng)
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
					node["encounter_id"] = _boss_encounter_for_act(act, rng)
					# Bosses keep their own complex passives — no mutator on boss
					# fights to avoid stacking too many parallel rule changes.


## The act's boss fight: the rival lord's kit if authored (rival_<hero>),
## else a stand-in boss from his own faction (nearest act first, rescaled by
## the cross-act rails), else the legacy unfiltered act roll. Stand-ins keep
## runs completable while the five lord kits are authored one at a time.
func _boss_encounter_for_act(act: int, rng: RandomNumberGenerator) -> String:
	var rival: String = rival_lords[act - 1] if act - 1 < rival_lords.size() else ""
	if rival != "":
		var kit_id := "rival_%s" % rival
		if EncounterDB.ENCOUNTERS.has(kit_id):
			return kit_id
		var stand_ins: Array = EncounterDB.get_kingdom_pool(
			act, "boss", HeroDB.get_faction(rival))
		# get_kingdom_pool can top up from the unfiltered act pool when a
		# faction has no boss anywhere (grasswake) — that's fine here too:
		# better an off-banner boss than no keep to take.
		if not stand_ins.is_empty():
			return stand_ins[rng.randi() % stand_ins.size()]
	var boss_ids: Array = EncounterDB.get_ids_for(act, "boss")
	if boss_ids.is_empty():
		return ""
	_shuffle_array(boss_ids, rng)
	return boss_ids[0]


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
# v3: Successor Wars — rival_lords / finale_rival / act_faction /
# holds_broken_in_act enter the schema. A v2 save has no rival deal, so its
# kingdoms and boss would silently fall back to legacy pools mid-run; retire.
const SAVE_VERSION: int = 3
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
		"current_terrain": current_terrain,
		"current_bridge": current_bridge,
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
		"rival_lords": rival_lords,
		"finale_rival": finale_rival,
		"act_faction": act_faction,
		"holds_broken_in_act": holds_broken_in_act,
		"finale_stage": finale_stage,
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
	map_plate_cache.clear()
	current_act_idx = int(data.get("current_act_idx", 0))
	map_position = data.get("map_position", {"row": -1, "col": -1})
	current_encounter_id = String(data.get("current_encounter_id", ""))
	current_node_type = String(data.get("current_node_type", ""))
	current_mutator_id = String(data.get("current_mutator_id", ""))
	current_terrain = String(data.get("current_terrain", ""))
	current_bridge = bool(data.get("current_bridge", false))
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
	rival_lords = []
	for hid in data.get("rival_lords", []):
		rival_lords.append(String(hid))
	finale_rival = String(data.get("finale_rival", ""))
	act_faction = []
	for fid in data.get("act_faction", []):
		act_faction.append(String(fid))
	holds_broken_in_act = int(data.get("holds_broken_in_act", 0))
	finale_stage = int(data.get("finale_stage", 0))
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
