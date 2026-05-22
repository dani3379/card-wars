extends Control
## Combat.gd — design-doc combat: sequential + Swift, floop, sacrifice, spells.
## Round flow: draw → play/sacrifice/floop → Swift phase → player attacks →
## enemy attacks → deaths → discard → enemy places → passives → new round.
## Combat happens every round (no setup-only round).

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"

enum Phase { PLAYER_TURN, RESOLVING, GAME_OVER }
var phase := Phase.PLAYER_TURN
var round_number := 0

const MAX_BANKED_MANA: int = 1
const HAND_DRAW_PER_TURN: int = 4
const MAX_HAND_SIZE := 10

# 4x4 field: 4 columns (lanes) x 2 rows (front, back) per side.
# Front row = closer to the midline. Back row = closer to its hero.
# Front blocks back from melee. Ranged prefers back. Piercing spills back→face.
const LANES_PER_ROW: int = 4
const ROW_FRONT: int = 0
const ROW_BACK: int = 1

# Round-flow tuning knobs (pulled out of inline magic numbers).
const ENEMY_FLOOP_CHANCE_DENOM: int = 3      # 1 in N rounds an enemy floops.
const PASSIVE_HEAL_INTERVAL: int = 3         # Sundial / Happy Flower interval.
const ESCALATION_REINFORCE_ROUND: int = 8    # Round when regular fights double-place.
const ESCALATION_ELITE_BUFF_ROUND: int = 10  # Elite +1 ATK/round trigger.
const COMBAT_PAUSE_SHORT: float = 0.15
const COMBAT_PAUSE_MEDIUM: float = 0.30
# Combat-cascade pacing — see _do_combat. All run through _short_pause(), so the
# player's anim-speed setting (Instant included) scales every beat automatically.
const LUNGE_APEX: float = 0.09       # delay from an attacker's lunge to the moment of impact
const POST_HIT_BEAT: float = 0.06    # breath after an ordinary hit before the next attacker
const HITSTOP_BEAT: float = 0.18     # longer punctuation after a kill or heavy blow
const HEAVY_HIT_DAMAGE: int = 5      # damage at/above which a hit earns the hit-stop

var player_hp: int
var player_max_hp: int
var player_mana: int = 0
var player_max_mana: int = 0
var enemy_hp: int
var enemy_max_hp: int

var _player_draw_pile: Array[String] = []
var _player_discard_pile: Array[String] = []
var _exhaust_pile: Array[String] = []
var _enemy_deck: Array[Dictionary] = []
var _reinforcement: Dictionary = {}
var _encounter_passive: String = ""
var _encounter_name: String = ""
var _encounter_passive_desc: String = ""

var _hand: Array[Control] = []
# Front rows — column-aligned with the midline (legacy name kept for compat).
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]
# Back rows — added in the 4x4 redesign. Same column ordering.
var _player_back: Array = [null, null, null, null]
var _enemy_back: Array = [null, null, null, null]

# Relic lookup cached at start of each turn (cleared on play).
var _relic_set: Dictionary = {}

var _sacrifice_used_this_turn: bool = false
var _sacrifice_mode: bool = false
var _targeting_spell: Control = null
var _targeting_data: Dictionary = {}
var _first_creature_played: bool = false
var _first_spell_this_turn: bool = false
# Set true the turn a creature is sacrificed while Butcher's Cleaver is held.
# Consumed by the next creature played this turn (which then gets +2 ATK that
# persists for 2 rounds). Resets each turn.
var _butchers_cleaver_armed: bool = false
var _cards_played_this_turn: int = 0
var _last_spell_played_this_turn: Dictionary = {}
var _bonus_mana_next_turn: int = 0
# Set true when the player confirms the end-turn warning dialog. Read+reset
# inside _on_end_turn to bypass re-prompting on the recursive re-entry.
var _end_turn_confirmed: bool = false
var _face_damage_taken_this_fight: int = 0
var _friendly_deaths_this_fight: int = 0
var _friendly_deaths_this_round: int = 0
var _last_dead_creature_id: String = ""
var _grave_pact_active: bool = false
var _soul_lantern_used_this_round: bool = false
var _starting_hp: int = 0

# Intent system
var _encounter_id: String = ""
var _boss_current_phase: int = 0
var _boss_phases: Array = []
var _reactive_passive: Dictionary = {}
var _extra_draws_this_turn: int = 0
var _last_dead_enemy_data: Dictionary = {}
var _sundial_count: int = 0

# Board UI
var _board_bg: ColorRect
var _player_slots: Array[Control] = []      # front-row slots (legacy name)
var _enemy_slots: Array[Control] = []       # front-row slots (legacy name)
var _player_back_slots: Array[Control] = [] # back-row slots (4x4)
var _enemy_back_slots: Array[Control] = []  # back-row slots (4x4)
var _hand_container: Control
var _midline: Panel

# HUD additions for 4x4 polish.
var _deck_count_label: Label
var _discard_count_label: Label
var _floop_tutorial_shown: bool = false
var _sacrifice_tutorial_shown: bool = false
var _banking_tutorial_shown: bool = false
var _intents_tutorial_shown: bool = false
var _pile_tutorial_shown: bool = false

# HUD
var _hud_layer: CanvasLayer
# Hand sits on its own layer above _hud_layer so dragged / hovered cards
# render over the board frame and HUD elements.
var _hand_layer: CanvasLayer
# Reference to the top-right enemy banner Control so the encounter title /
# round labels can be parented inside it (previously a separate scroll
# panel at top-left).
var _enemy_banner_for_info: Control = null
var _targeting_arrow: Line2D = null
var _targeting_arrow_head: Polygon2D = null
var _prediction_label: Label = null
var _intent_arrow_lines: Array[Line2D] = []
var _phase_label: Label
var _player_hp_label: Label
var _enemy_hp_label: Label
var _mana_label: Label
var _turn_label: Label
var _info_label: Label
var _floor_label: Label
var _end_turn_btn: Button
var _sacrifice_btn: Button
var _relic_panel: GridContainer
# HP bar fill tweens — kept so rapid HP changes re-target a single drain
# animation instead of stacking competing tweens.
var _player_hp_tween: Tween = null
var _enemy_hp_tween: Tween = null

# Board container (no effects)
var _board_container: Control

# Colors — local aliases for GameTheme constants used heavily in this file.
const GILT := Color(0.82, 0.66, 0.30, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)


func _ready() -> void:
	set_process(false)
	_rebuild_relic_cache()
	_floop_tutorial_shown = UserSettings.floop_tutorial_seen
	_sacrifice_tutorial_shown = UserSettings.sacrifice_tutorial_seen
	_banking_tutorial_shown = UserSettings.banking_tutorial_seen
	_intents_tutorial_shown = UserSettings.intents_tutorial_seen
	_pile_tutorial_shown = UserSettings.pile_tutorial_seen
	_setup_fight_state()
	# Music: bosses get a dedicated dramatic track, elites their own, others
	# share the standard combat loop. AudioBank no-ops if the file is missing.
	var node_type: String = RunState.current_node_type
	match node_type:
		"boss": AudioBank.play_music("combat_boss")
		"elite": AudioBank.play_music("combat_elite")
		_: AudioBank.play_music("combat")
	_build_board()
	_build_ambient_fx()
	_build_hud()
	_init_decks()
	_place_starting_board()
	# Pre-bake static-display textures for every unique card in the draw
	# pile so when _draw_card spins up a Card2D with live_baked_mode=true
	# the cache is warm. ~2 frames per uncached card; if the deck has 15
	# unique cards that's ~30 frames (~500 ms) of one-time load, with
	# enemies fully placed on the board so the player sees the setup while
	# we bake. Cards drawn before the bake completes hit the v4 fallback
	# inside _build_layout — slower but visually identical.
	await _prebake_hand_textures()
	# Boss / elite encounters get a dramatic intro banner (name + passive)
	# before the first round begins. Normal combats skip the intro.
	# node_type was already captured above for the music branch — reuse it.
	if node_type == "boss" or node_type == "elite":
		await _show_encounter_intro(node_type == "boss")
	_start_round()


func _prebake_hand_textures() -> void:
	# Build a unique-card list from _player_draw_pile (Array[String]) so we
	# bake each card identity once even if the deck has duplicates.
	var seen := {}
	var to_bake: Array = []
	for entry in _player_draw_pile:
		if seen.has(entry):
			continue
		seen[entry] = true
		to_bake.append(_resolve_card_data(_entry_id(entry), _entry_uid(entry)))
	# Enemy creatures use compact_mode on the battlefield, which doesn't pull
	# from the cache, so we skip baking them. If the design ever puts enemy
	# cards into a hand-style view we'd extend this list.
	await CardTextureCache.bake_many(to_bake)


# =====================================================================
#  SETUP
# =====================================================================

func _setup_fight_state() -> void:
	player_max_hp = RunState.hero_max_hp
	player_hp = RunState.hero_hp
	_starting_hp = player_hp
	var enc_id = RunState.current_encounter_id
	if enc_id != "":
		var enc = EncounterDB.get_encounter(enc_id)
		if not enc.is_empty():
			_encounter_id = enc_id
			enemy_max_hp = _scale_enemy_hp(enc.hp)
			_encounter_passive = enc.get("passive_id", "")
			_encounter_name = enc.get("name", "")
			_encounter_passive_desc = enc.get("passive_desc", "")
			_enemy_deck = EncounterDB.build_enemy_deck(enc_id)
			_reinforcement = EncounterDB.get_reinforcement(enc_id)
			_boss_phases = EncounterDB.get_boss_phases(enc_id)
			_reactive_passive = EncounterDB.get_reactive_passive(enc_id)
			enemy_hp = enemy_max_hp
			return
	var act = RunState.get_act()
	var node_type = RunState.current_node_type
	match node_type:
		"combat":
			enemy_max_hp = _scale_enemy_hp([12, 17, 21][act - 1] + randi() % 4)
		"elite":
			enemy_max_hp = _scale_enemy_hp([18, 26, 30][act - 1] + randi() % 4)
		"boss":
			enemy_max_hp = _scale_enemy_hp([25, 32, 40][act - 1])
	_build_legacy_enemy_deck(act)
	enemy_hp = enemy_max_hp


func _scale_enemy_hp(base: int) -> int:
	# Ascension multiplier — see RunState.ASCENSION_HP_MULT. Bosses scale too,
	# so the climb feels consistent.
	var asc: int = clampi(RunState.current_ascension, 0, RunState.ASCENSION_HP_MULT.size() - 1)
	return int(round(base * RunState.ASCENSION_HP_MULT[asc]))


func _build_legacy_enemy_deck(act: int) -> void:
	for i in range(8):
		var eid = CardDB.random_enemy_for_act(act)
		_enemy_deck.append(CardDB.get_card_data(eid))


# =====================================================================
#  4x4 FIELD HELPERS — single source of truth for row/column access.
# =====================================================================

func _row_array(is_enemy: bool, row: int) -> Array:
	# Returns the underlying array reference for a given side+row.
	if is_enemy:
		return _enemy_back if row == ROW_BACK else _enemy_field
	return _player_back if row == ROW_BACK else _player_field


func _slot_array(is_enemy: bool, row: int) -> Array:
	if is_enemy:
		return _enemy_back_slots if row == ROW_BACK else _enemy_slots
	return _player_back_slots if row == ROW_BACK else _player_slots


func _all_friendly(is_enemy: bool) -> Array:
	# Flat list (non-null) of every creature on a side, both rows.
	var out: Array = []
	for c in _row_array(is_enemy, ROW_FRONT):
		if c != null:
			out.append(c)
	for c in _row_array(is_enemy, ROW_BACK):
		if c != null:
			out.append(c)
	return out


func _all_player_creatures() -> Array:
	return _all_friendly(false)


func _all_enemy_creatures() -> Array:
	return _all_friendly(true)


func _all_creatures_both_sides() -> Array:
	return _all_player_creatures() + _all_enemy_creatures()


func _has_adjacent_royal_guard(defender: Control) -> bool:
	# Royal Guard's passive grants -1 dmg to friendly creatures sitting in
	# either of its two adjacent lanes (same row). Returns true if such a
	# Royal Guard exists for `defender`'s position.
	var pos = _find_creature_position(defender)
	if pos.is_empty():
		return false
	var defender_is_enemy: bool = pos.is_enemy
	var row: int = pos.row
	var lane: int = pos.lane
	var arr = _row_array(defender_is_enemy, row)
	for adj_lane in [lane - 1, lane + 1]:
		if adj_lane < 0 or adj_lane >= LANES_PER_ROW:
			continue
		var neighbor = arr[adj_lane]
		if neighbor != null and neighbor != defender \
				and neighbor.card_data.get("passive", "") == "royal_guard" \
				and neighbor.current_hp > 0:
			return true
	return false


func _find_creature_position(card: Control) -> Dictionary:
	# Returns {is_enemy, row, lane} or {} if not on board.
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var arr = _row_array(is_enemy, row)
			for lane in range(LANES_PER_ROW):
				if arr[lane] == card:
					return {"is_enemy": is_enemy, "row": row, "lane": lane}
	return {}


func _row_for_lane(is_enemy: bool, lane: int, prefer_front: bool = true) -> int:
	# Returns the row in this column that currently holds a creature.
	# prefer_front=true → return front row if occupied, else back; ROW_FRONT if both empty.
	var front_arr = _row_array(is_enemy, ROW_FRONT)
	var back_arr = _row_array(is_enemy, ROW_BACK)
	if prefer_front and front_arr[lane] != null:
		return ROW_FRONT
	if not prefer_front and back_arr[lane] != null:
		return ROW_BACK
	if front_arr[lane] != null:
		return ROW_FRONT
	if back_arr[lane] != null:
		return ROW_BACK
	return ROW_FRONT


func _column_has_any(is_enemy: bool, lane: int) -> bool:
	var front = _row_array(is_enemy, ROW_FRONT)
	var back = _row_array(is_enemy, ROW_BACK)
	return front[lane] != null or back[lane] != null


func _get_creature_in_column(is_enemy: bool, lane: int) -> Control:
	# Returns front-row creature if alive, else back-row creature, else null.
	var front = _row_array(is_enemy, ROW_FRONT)
	if front[lane] != null:
		return front[lane]
	var back = _row_array(is_enemy, ROW_BACK)
	return back[lane]


func _set_creature(is_enemy: bool, row: int, lane: int, card) -> void:
	_row_array(is_enemy, row)[lane] = card


func _adjacent_in_row(is_enemy: bool, row: int, lane: int) -> Array:
	# Returns alive same-row creatures at lane ±1.
	var arr = _row_array(is_enemy, row)
	var out: Array = []
	for adj in [lane - 1, lane + 1]:
		if adj >= 0 and adj < LANES_PER_ROW and arr[adj] != null:
			out.append(arr[adj])
	return out


# ── Draw/discard pile entries ──
# Pile entries are "<card_id>#<deck_uid>" so each entry carries which copy in
# RunState.deck it came from. That lets _draw_card resolve per-copy upgrades
# (Sharpen/Fortify/Imbue from rest sites) at draw time. Synthetic cards
# (curses, tokens, resurrected) use a bare id (uid -1 → no upgrade). All the
# structural pile ops (shuffle/slice/pop/erase/duplicate) treat entries as
# opaque strings, so they need no changes.
func _pile_entry(card_id: String, uid: int) -> String:
	return "%s#%d" % [card_id, uid]


func _entry_id(entry: String) -> String:
	var h := entry.rfind("#")
	return entry.substr(0, h) if h >= 0 else entry


func _entry_uid(entry: String) -> int:
	var h := entry.rfind("#")
	return entry.substr(h + 1).to_int() if h >= 0 else -1


func _resolve_card_data(card_id: String, uid: int) -> Dictionary:
	# Upgraded copies pull their modified stats/keywords from RunState; synthetic
	# or un-upgraded cards fall back to the base definition.
	if uid >= 0:
		var idx := RunState.deck_uids.find(uid)
		if idx >= 0:
			return RunState.get_upgraded_card_data(idx)
	return CardDB.get_card_data(card_id)


# ── On-enter ability support (Stray Cat / Doppelganger / Chaos Imp) ──

func _last_dead_copy_data() -> Dictionary:
	# Doppelganger's "copy last dead" — prefer the last enemy that died (the
	# interesting case), else the player's last dead creature.
	if not _last_dead_enemy_data.is_empty():
		return _last_dead_enemy_data
	if _last_dead_creature_id != "":
		return CardDB.get_card_data(_last_dead_creature_id)
	return {}


func _look_top_pick(n: int) -> void:
	# Stray Cat: examine the top n entries of the draw pile and draw the
	# cheapest (most immediately playable), leaving the rest in place.
	if _player_draw_pile.is_empty():
		return
	var count := mini(n, _player_draw_pile.size())
	var best_i := 0
	var best_cost := 9999
	for i in range(count):
		var cd := _resolve_card_data(_entry_id(_player_draw_pile[i]), _entry_uid(_player_draw_pile[i]))
		var c := int(cd.get("cost", 0))
		if c < best_cost:
			best_cost = c
			best_i = i
	var entry: String = _player_draw_pile[best_i]
	_player_draw_pile.remove_at(best_i)
	_draw_card(entry)


func cast_random_spell_free() -> void:
	# Chaos Imp: cast a random non-custom spell from the card pool for free.
	# Restricted to non-custom spell types so _resolve_spell's null-safe handlers
	# never deref a missing target; auto-targets a random valid creature.
	var candidates: Array = []
	for id in CardDB.CARD_POOL:
		var d = CardDB.CARD_POOL[id]
		if d.get("type", "") == "spell" and id != "curse":
			var st: String = d.get("spell", {}).get("type", "")
			if st != "" and st != "custom":
				candidates.append(id)
	if candidates.is_empty():
		return
	var data := CardDB.get_card_data(candidates[randi() % candidates.size()])
	var target := _auto_target_for(data.get("targeting", "none"))
	var tl: int = target.current_lane if target != null else -1
	_show_info("Chaos Imp casts %s!" % data.get("name", "a spell"))
	_resolve_spell(data, target, tl)


func _auto_target_for(targeting: String) -> Control:
	# Pick a random valid creature for an auto-cast spell (Chaos Imp / Echo).
	if targeting in ["enemy_creature", "any_creature", "any"]:
		var ep := _all_enemy_creatures()
		if ep.size() > 0:
			return ep[randi() % ep.size()]
	elif targeting == "friendly_creature":
		var fp := _all_player_creatures()
		if fp.size() > 0:
			return fp[randi() % fp.size()]
	return null


func _init_decks() -> void:
	_player_draw_pile.clear()
	_player_discard_pile.clear()
	for i in RunState.deck.size():
		_player_draw_pile.append(_pile_entry(RunState.deck[i], RunState.deck_uids[i]))
	# Mark of Pain: add 2 curses to draw pile
	if _has_relic("mark_of_pain"):
		_player_draw_pile.append("curse")
		_player_draw_pile.append("curse")
	_player_draw_pile.shuffle()


func _place_starting_board() -> void:
	## Places enemies on the field at the START of the fight (before round 1).
	## 4x4: scales starting count up a touch since there are more slots, and
	## prefers front-row placement (back-row only used as overflow).
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")
	var act = enc.get("act", RunState.get_act())

	var starting_count := 0
	match enc_type:
		"combat":
			# 4x4 has 8 enemy slots — give the starting board a bit more presence.
			starting_count = [2, 3, 3][act - 1]
			if act == 3 and randi() % 2 == 0:
				starting_count = 4
		"elite":
			starting_count = 3 if act == 1 else 4
		"boss":
			starting_count = 3

	var placed := 0
	# Pick an evenly-spread set of front-row lanes first so a 2- or 3-creature
	# start never visually clumps on one side of the board, then fall through
	# to any remaining front lanes, then to back-row overflow.
	var fill_order: Array = []
	for l in _evenly_spread_lanes(starting_count):
		fill_order.append({"row": ROW_FRONT, "lane": l})
	for l in range(LANES_PER_ROW):
		if not _slot_in_list(fill_order, ROW_FRONT, l):
			fill_order.append({"row": ROW_FRONT, "lane": l})
	var back_order = [0, 1, 2, 3]
	back_order.shuffle()
	for l in back_order:
		fill_order.append({"row": ROW_BACK, "lane": l})

	for slot in fill_order:
		if placed >= starting_count:
			break
		if _enemy_deck.is_empty():
			break
		# Defensive: never overwrite an already-occupied slot. The fill_order
		# is built without duplicates, but if any caller ever reuses this
		# logic on a non-empty board we want stacking ruled out at the source.
		if _row_array(true, slot.row)[slot.lane] != null:
			continue
		var card_data = _enemy_deck.pop_front()
		_place_enemy_card(card_data, slot.lane, slot.row)
		placed += 1


func _evenly_spread_lanes(n: int) -> Array:
	# Returns up to n lane indices spread across the 4 lanes so the starting
	# board reads as a balanced front line instead of a left-clumped huddle.
	# Picks one of two mirrored layouts at random for variety.
	match clampi(n, 0, LANES_PER_ROW):
		0: return []
		1: return [1] if randi() % 2 == 0 else [2]
		2: return [0, 2] if randi() % 2 == 0 else [1, 3]
		3: return [0, 1, 3] if randi() % 2 == 0 else [0, 2, 3]
		_: return [0, 1, 2, 3]


# =====================================================================
#  ROUND FLOW
# =====================================================================

func _start_round() -> void:
	round_number += 1
	# Tutorials — sequenced so new players see one tip per round, not a wall.
	# Intents tip on round 1 (when intent badges first appear above enemies);
	# pile tip on round 2 (when the discard pile is guaranteed non-empty).
	if round_number == 1:
		_maybe_show_intents_tutorial()
	elif round_number == 2:
		_maybe_show_pile_tutorial()
	_sacrifice_used_this_turn = false
	_first_creature_played = false
	_first_spell_this_turn = false
	_butchers_cleaver_armed = false
	# Tick down persistent ATK buffs (e.g. Butcher's Cleaver) on all creatures.
	for c in _all_creatures_both_sides():
		if c.persistent_atk_buff_rounds > 0:
			c.persistent_atk_buff_rounds -= 1
			if c.persistent_atk_buff_rounds <= 0:
				c.persistent_atk_buff = 0
			c.update_stat_display()
	_cards_played_this_turn = 0
	_last_spell_played_this_turn = {}
	_friendly_deaths_this_round = 0
	_soul_lantern_used_this_round = false
	_extra_draws_this_turn = 0
	phase = Phase.PLAYER_TURN

	KeywordEffects.dispatch_start_of_round(self)
	_dispatch_passive_start_of_round()
	_apply_start_of_round_relics()
	# Reset phantom_veil one-per-round flag.
	set_meta("phantom_veil_used", false)

	# Boss phase check
	_check_boss_phase_transition()

	# Assign + display intents for every enemy so the player can always read
	# what's coming. Non-boss enemies without intent cycles default to ATK
	# which now renders as a visible damage chip via _update_intent_display.
	_assign_intents()

	# Escalation check
	_check_escalation()

	# Mana — unspent mana carries over (banked)
	var bank_cap = player_mana if _has_relic("ice_cream") else mini(player_mana, MAX_BANKED_MANA)
	var banked = bank_cap if round_number > 1 else 0
	player_max_mana = RunState.get_max_mana() + _bonus_mana_next_turn
	if _has_relic("battle_scars") and round_number == 1:
		player_max_mana += 1
	if _has_relic("lantern") and round_number == 1:
		player_max_mana += 1
	if _has_relic("happy_flower") and round_number > 0 and round_number % PASSIVE_HEAL_INTERVAL == 0:
		player_max_mana += 1
	# Leyline Conduit passive: +1 mana per alive conduit (both rows).
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == "mana_per_turn":
			player_max_mana += 1
	_bonus_mana_next_turn = 0
	player_mana = player_max_mana + banked
	# Tutorial: first round where mana actually carries over.
	if banked > 0:
		_maybe_show_banking_tutorial()

	# Draw — staggered so cards deal in one at a time instead of fanning in
	# simultaneously. Each card already tweens from the deck into its hand slot
	# (Card2D.set_hand_target); spacing the spawns by ~80 ms makes the deal
	# read as a real motion sequence instead of a single fanned poof.
	var draw_count = HAND_DRAW_PER_TURN
	if _has_relic("couriers_bag") and round_number == 1:
		draw_count += 1
	for i in draw_count:
		if i == 0:
			draw_one()
		else:
			get_tree().create_timer(0.08 * float(i)).timeout.connect(draw_one)

	_end_turn_btn.disabled = false
	# Sacrifice button removed from the HUD; guard remaining references.
	if _sacrifice_btn != null:
		_sacrifice_btn.visible = true
		_sacrifice_btn.disabled = _sacrifice_used_this_turn
	_update_hud()
	_show_turn_banner()


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _targeting_spell != null:
		_cancel_targeting()
		return
	if _sacrifice_mode:
		_cancel_sacrifice()
		return
	# End-turn warning: if the player still has playable actions, prompt
	# before ending the turn. Most accidental end-turn clicks happen at
	# exactly these moments. _end_turn_confirmed gates the recursive
	# re-entry — set true ONLY when the player confirms in the dialog.
	if UserSettings != null and UserSettings.end_turn_warning \
			and not _end_turn_confirmed and _has_playable_action():
		GameTheme.show_confirm_dialog(self,
			"End Turn?",
			"You still have mana or an action available.",
			"END TURN",
			"KEEP PLAYING",
			Callable(self, "_on_end_turn_confirmed"))
		return
	_end_turn_confirmed = false
	_end_turn_btn.disabled = true
	if _sacrifice_btn != null:
		_sacrifice_btn.visible = false
	phase = Phase.RESOLVING
	# Art of War: if no cards played, bonus mana next turn
	if _has_relic("art_of_war") and _cards_played_this_turn == 0:
		_bonus_mana_next_turn += 1
	_update_hud()

	# Resolve floop abilities (with reactive passive check)
	_resolve_floops()

	# Resolve enemy intents (non-attack intents execute now)
	_resolve_intents()

	_do_combat()


func _resolve_floops() -> void:
	# Player floops (both rows). Player floops are explicit (will_floop flag).
	for row in [ROW_FRONT, ROW_BACK]:
		var p_arr = _row_array(false, row)
		for lane_idx in range(LANES_PER_ROW):
			var card = p_arr[lane_idx]
			if card != null and card.will_floop and card.has_floop():
				_resolve_floop_ability(card, lane_idx, false)
				card.will_floop = false
				card.has_flooped_this_turn = true
				card.has_attacked_this_turn = true
				card.update_floop_display()
				_dispatch_reactive("ON_PLAYER_FLOOP", card, lane_idx)
	# Enemy floops (both rows). 1-in-N chance, gated by ENEMY_FLOOP_CHANCE_DENOM.
	for row in [ROW_FRONT, ROW_BACK]:
		var e_arr = _row_array(true, row)
		for lane_idx in range(LANES_PER_ROW):
			var e_card = e_arr[lane_idx]
			if e_card != null and e_card.has_floop() and randi() % ENEMY_FLOOP_CHANCE_DENOM == 0:
				_resolve_floop_ability(e_card, lane_idx, true)


func _resolve_floop_ability(card: Control, lane_idx: int, is_enemy: bool) -> void:
	var floop_data = card.card_data.get("floop", {})
	var times = 1
	if not is_enemy and _has_relic("echo_staff"):
		times = 2
	if is_instance_valid(card) and card.has_method("play_floop_pulse"):
		card.play_floop_pulse()
	# 4x4: adjacency-based floops operate within the flooping creature's row.
	# "All friendly/enemy" floops use the broad helpers below.
	var my_row: int = card.current_row
	var friendly_field = _row_array(is_enemy, my_row)
	var enemy_field = _row_array(not is_enemy, ROW_FRONT)  # opposing front (for column-aligned damage)
	var all_friendly = _all_friendly(is_enemy)
	var all_enemy = _all_friendly(not is_enemy)
	for _i in times:
		match floop_data.get("type", ""):
			# --- DAMAGE ---
			"damage_any":
				if all_enemy.size() > 0:
					all_enemy[randi() % all_enemy.size()].take_damage(floop_data.value)
			"damage_opposing":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
			"damage_opposing_splash":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
				# 4x4: splash hits the frontmost creature in each adjacent column
				# (front if alive, else back) — matching how get_opposing_card
				# resolves the direct target. The old code read enemy_field
				# directly, which is the opposing FRONT row only, so back-row
				# creatures behind empty front lanes were silently skipped.
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < LANES_PER_ROW:
						var adj_opp = _get_creature_in_column(not is_enemy, adj_lane)
						if adj_opp != null:
							adj_opp.take_damage(floop_data.value)
			"damage_opposing_heal":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
				card.current_hp = mini(card.current_hp + floop_data.get("heal", 1), card.card_data.hp)
				card.update_stat_display()
			"damage_all_enemies":
				for c in all_enemy:
					c.take_damage(floop_data.value)
			"damage_all":
				for c in all_enemy:
					c.take_damage(floop_data.value)
				for c in all_friendly:
					if c != card:
						c.take_damage(floop_data.value)
				card.take_damage(floop_data.value)
			"damage_face":
				if is_enemy:
					damage_player_hero(floop_data.value)
				else:
					damage_enemy_hero(floop_data.value)
			"damage_self_opposing":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
				card.take_damage(floop_data.get("self_damage", 1))
			"drain":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
					card.current_hp = mini(card.current_hp + floop_data.value, card.card_data.hp)
					card.update_stat_display()
			"execute":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null and opp.current_hp <= floop_data.value:
					opp.take_damage(999)
			"slay_draw":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					var hp_before = opp.current_hp
					opp.take_damage(floop_data.value)
					if opp.current_hp <= 0 and not is_enemy:
						draw_one()
			"unleash_atk":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.take_damage(card.current_atk)
			"graveyard_damage":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					var discard_creatures = 0
					for idx in _player_discard_pile:
						var cdata = CardDB.get_card_data(_entry_id(idx))
						if cdata.get("type", "") == "creature":
							discard_creatures += 1
					opp.take_damage(discard_creatures)
			"discard_top_damage":
				if _player_draw_pile.size() > 0:
					var top_idx = _player_draw_pile.pop_front()
					var top_data = CardDB.get_card_data(_entry_id(top_idx))
					_player_discard_pile.append(top_idx)
					var cost_dmg = top_data.get("cost", 0)
					if cost_dmg > 0 and all_enemy.size() > 0:
						all_enemy[randi() % all_enemy.size()].take_damage(cost_dmg)

			# --- BUFF / HEAL ---
			"heal_self":
				card.current_hp = mini(card.current_hp + floop_data.value, card.card_data.hp)
				card.update_stat_display()
			"heal_adjacent":
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						var adj_c = friendly_field[adj_lane]
						adj_c.current_hp = mini(adj_c.current_hp + floop_data.value, adj_c.card_data.hp)
						adj_c.update_stat_display()
			"heal_all_friendly":
				for c in all_friendly:
					c.current_hp = mini(c.current_hp + floop_data.value, c.card_data.hp)
					c.update_stat_display()
			"grow_atk":
				card.current_atk += floop_data.value
				card.update_stat_display()
			"grow_per_enemies":
				card.current_atk += all_enemy.size()
				card.update_stat_display()
			"buff_all_atk_permanent":
				for c in all_friendly:
					c.current_atk += floop_data.value
					c.update_stat_display()
			"buff_target_hp":
				# Buff random adjacent friendly (simplified from targeted)
				var adj: Array = []
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						adj.append(friendly_field[adj_lane])
				if adj.size() > 0:
					var target = adj[randi() % adj.size()]
					target.card_data.hp += floop_data.value
					target.current_hp += floop_data.value
					target.update_stat_display()
			"buff_tokens_atk":
				for c in all_friendly:
					if c.card_data.get("is_token", false):
						c.temp_atk_buff += floop_data.value
						c.update_stat_display()

			# --- DEFENSE ---
			"temp_armored":
				if "armored" not in card.card_data.keywords:
					card.card_data.keywords.append("armored")
					card.set_meta("temp_armored", true)
			"grant_armored_all":
				for c in all_friendly:
					if "armored" not in c.card_data.keywords:
						c.card_data.keywords.append("armored")
						c.set_meta("temp_armored", true)
			"shield_adjacent":
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						var adj_c = friendly_field[adj_lane]
						if "armored" not in adj_c.card_data.keywords:
							adj_c.card_data.keywords.append("armored")
							adj_c.set_meta("temp_armored", true)
			"buff_thorns":
				card.set_meta("bonus_thorns", card.get_meta("bonus_thorns", 0) + floop_data.value)
			"grant_thorns_adjacent":
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						var adj_c = friendly_field[adj_lane]
						if "thorns" not in adj_c.card_data.keywords:
							adj_c.card_data.keywords.append("thorns")
							adj_c.set_meta("temp_thorns", true)
			"redirect_adjacent":
				card.set_meta("redirecting", true)
			"stun_opposing":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					opp.state.stunned = true

			# --- CARD / ECONOMY ---
			"draw":
				if not is_enemy:
					for _d in range(floop_data.value):
						draw_one()
			"scry":
				if not is_enemy and _player_draw_pile.size() > 0:
					# Simplified: put top card to bottom (always cycles)
					var top = _player_draw_pile.pop_front()
					_player_draw_pile.append(top)
			"reorder_deck":
				if not is_enemy and _player_draw_pile.size() >= 2:
					# Simplified: reverse top N cards (approximation of reorder)
					var n = mini(floop_data.value, _player_draw_pile.size())
					var top_n = _player_draw_pile.slice(0, n)
					top_n.reverse()
					for idx in range(n):
						_player_draw_pile[idx] = top_n[idx]
			"filter_draw":
				if not is_enemy:
					if _hand.size() > 0:
						var discard_idx = randi() % _hand.size()
						var disc_card = _hand[discard_idx]
						_hand.remove_at(discard_idx)
						disc_card.queue_free()
					draw_one()
			"raise_dead":
				if not is_enemy and _player_discard_pile.size() > 0:
					var creature_indices: Array = []
					for idx in _player_discard_pile:
						var cdata = CardDB.get_card_data(_entry_id(idx))
						if cdata.get("type", "") == "creature":
							creature_indices.append(idx)
					if creature_indices.size() > 0:
						var pick = creature_indices[randi() % creature_indices.size()]
						_player_discard_pile.erase(pick)
						_draw_card(pick)
			"gain_gold":
				if not is_enemy:
					RunState.gain_gold(floop_data.value)
			"gain_mana":
				if not is_enemy:
					player_mana += floop_data.value
					_update_hud()
			"buff_adjacent_atk":
				# 4x4: "adjacent" = same row ±1 lane PLUS the column-mate in the
				# other row (the creature directly behind / in front of this one).
				# The old code only walked the flooper's own row, so Sprite buffed
				# its left/right neighbour but silently missed the friend stacked
				# behind it.
				var other_row: int = ROW_BACK if my_row == ROW_FRONT else ROW_FRONT
				var other_row_arr = _row_array(is_enemy, other_row)
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < LANES_PER_ROW:
						var adj = friendly_field[adj_lane]
						if adj != null:
							adj.temp_atk_buff += floop_data.value
							adj.update_stat_display()
				var column_mate = other_row_arr[lane_idx]
				if column_mate != null:
					column_mate.temp_atk_buff += floop_data.value
					column_mate.update_stat_display()
			"discount_next":
				if not is_enemy:
					set_meta("floop_discount", floop_data.value)
			"spawn_token_hand":
				if not is_enemy:
					var token_data = {
						"id": "token_hand", "name": "Cat Token", "type": "creature",
						"cost": 0, "atk": floop_data.get("atk", 1), "hp": floop_data.get("hp", 1),
						"rarity": "starter", "keywords": ["floop"], "desc": "Token. Floop: deal 1 to opposing.",
						"floop": {"type": "damage_opposing", "value": 1}, "is_token": true
					}
					_draw_card(token_data.id)

			# --- MOVEMENT ---
			"relocate":
				# 4x4: relocate within the same row.
				var empty_lanes: Array[int] = []
				for i in range(LANES_PER_ROW):
					if i != lane_idx and friendly_field[i] == null:
						empty_lanes.append(i)
				if empty_lanes.size() > 0:
					var new_lane = empty_lanes[randi() % empty_lanes.size()]
					friendly_field[lane_idx] = null
					friendly_field[new_lane] = card
					card.current_lane = new_lane
					var slots = _slot_array(is_enemy, my_row)
					_slot_take_card(slots[lane_idx], card)
					_slot_set_card(slots[new_lane], card)
			"challenge":
				card.set_meta("challenge_any_lane", true)

			# --- SUMMONING / TRANSFORM ---
			"summon_random":
				# 4x4: prefer empty in our row, fall through to the other row.
				var picked = _pick_empty_for_summon(is_enemy, my_row)
				if not picked.is_empty():
					summon_token(floop_data.atk, floop_data.hp, picked.lane, is_enemy, picked.row)
			"summon_token":
				var picked2 = _pick_empty_for_summon(is_enemy, my_row)
				if not picked2.is_empty():
					summon_token(floop_data.atk, floop_data.hp, picked2.lane, is_enemy, picked2.row)
			"kill_adjacent_summon":
				var adj: Array[int] = []
				if lane_idx > 0 and friendly_field[lane_idx - 1] != null:
					adj.append(lane_idx - 1)
				if lane_idx < 3 and friendly_field[lane_idx + 1] != null:
					adj.append(lane_idx + 1)
				if adj.size() > 0:
					var target_lane = adj[randi() % adj.size()]
					var victim = friendly_field[target_lane]
					if victim != null:
						victim.take_damage(999)
					summon_token(floop_data.atk, floop_data.hp, target_lane, is_enemy)
			"steal_atk":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null and opp.current_atk > 0:
					opp.current_atk = maxi(0, opp.current_atk - floop_data.get("value", 1))
					card.current_atk += floop_data.get("value", 1)
					opp.update_stat_display()
					card.update_stat_display()
			"devour_adjacent":
				var adj: Array[int] = []
				if lane_idx > 0 and friendly_field[lane_idx - 1] != null:
					adj.append(lane_idx - 1)
				if lane_idx < 3 and friendly_field[lane_idx + 1] != null:
					adj.append(lane_idx + 1)
				if adj.size() > 0:
					var target_lane = adj[randi() % adj.size()]
					var victim = friendly_field[target_lane]
					if victim != null:
						card.current_atk += victim.current_atk
						card.current_hp += victim.current_hp
						card.update_stat_display()
						victim.take_damage(999)
			"copy_opposing_floop":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null and opp.card_data.has("floop"):
					var copied_floop = opp.card_data.floop.duplicate(true)
					var orig_floop = card.card_data.floop
					card.card_data.floop = copied_floop
					_resolve_floop_ability(card, lane_idx, is_enemy)
					card.card_data.floop = orig_floop
			"swap_atk":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					var temp = card.current_atk
					card.current_atk = opp.current_atk
					opp.current_atk = temp
					card.update_stat_display()
					opp.update_stat_display()
					card.set_meta("swap_atk_original", temp)
					opp.set_meta("swap_atk_original", card.current_atk)
			"become_copy":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					card.current_atk = opp.current_atk
					card.current_hp = opp.current_hp
					card.update_stat_display()
					card.set_meta("is_copy", true)
			"blood_sacrifice":
				# Kill self, give adjacent +X ATK permanent
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						friendly_field[adj_lane].current_atk += floop_data.value
						friendly_field[adj_lane].update_stat_display()
				card.take_damage(999)


# =====================================================================
#  COMBAT RESOLUTION
# =====================================================================

func _do_combat() -> void:
	_update_hud()
	_clear_intent_arrows()

	# Snapshot which lanes had a front-row blocker at start of combat. Used for
	# face-damage decisions when the blocker dies mid-combat.
	var player_front_empty_at_start: Array[bool] = []
	var enemy_front_empty_at_start: Array[bool] = []
	for i in range(LANES_PER_ROW):
		player_front_empty_at_start.append(_player_field[i] == null)
		enemy_front_empty_at_start.append(_enemy_field[i] == null)

	# Mark stunned creatures as already-attacked so they skip combat (both rows).
	for c in _all_creatures_both_sides():
		if c.state.stunned:
			c.has_attacked_this_turn = true

	# SWIFT PHASE — front row first, then back row. Both rows attack regardless
	# of whether their own column's front is occupied (back is queue space, not
	# a separate combat tier). Each strike is awaited so the swing reads as a
	# lane-by-lane cascade (lunge → impact → beat) rather than one instant burst.
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_swift_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
		await _resolve_swift_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_swift_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)
		await _resolve_swift_attack(lane_idx, ROW_BACK, true, player_front_empty_at_start)

	# PLAYER ATTACK PHASE — front row attacks first so its kills are visible before
	# back row picks targets. Both rows attack each turn.
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)

	# ENEMY ATTACK PHASE — mirror, also front-first.
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_BACK, true, player_front_empty_at_start)

	# Process ranged attacks (prefer back-row targets, then front, then face).
	await _resolve_ranged_attacks()

	# Berserker growth — scan both rows on both sides.
	for c in _all_creatures_both_sides():
		if c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
			c.current_atk += 1
			c.update_stat_display()

	_cleanup_dead()

	await _short_pause(COMBAT_PAUSE_SHORT)
	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		_post_combat_sequence()


func _resolve_column_attack(lane_idx: int, row: int, is_enemy: bool,
		opponent_front_empty: Array[bool]) -> void:
	# Attempt to attack from (is_enemy, row, lane_idx). Front and back rows are
	# mechanically identical — both attack each turn, front just goes first.
	var attacker_field = _row_array(is_enemy, row)
	var attacker = attacker_field[lane_idx]
	if attacker == null or not is_instance_valid(attacker):
		return
	if attacker.current_hp <= 0 or attacker.has_attacked_this_turn:
		return
	if not attacker.can_attack():
		return

	# Pick target: opposing front in this column, else opposing back, else face.
	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]

	# Hydra: strikes every opposing creature at once (takes 1 back from each).
	if attacker.card_data.get("passive", "") == "attacks_all_lanes":
		await _resolve_hydra_attack(attacker, lane_idx, is_enemy)
		return
	# Siege Golem: a wall-breaker — only lands (face) damage through an empty
	# opposing column; blocked entirely if any creature stands opposite it.
	if attacker.card_data.get("passive", "") == "siege":
		attacker.has_attacked_this_turn = true
		if opp_front == null and opp_back == null and opponent_front_empty[lane_idx]:
			await _creature_hits_face(attacker, lane_idx, is_enemy)
		return

	if opp_front != null and opp_front.current_hp > 0:
		await _creature_attacks_creature(attacker, _redirect_target(opp_front, opp_is_enemy, lane_idx, ROW_FRONT), lane_idx, is_enemy)
	elif opp_back != null and opp_back.current_hp > 0:
		# Front died or never existed — back row is now exposed.
		await _creature_attacks_creature(attacker, _redirect_target(opp_back, opp_is_enemy, lane_idx, ROW_BACK), lane_idx, is_enemy)
	elif opponent_front_empty[lane_idx]:
		# Empty column at start of combat → face damage.
		await _creature_hits_face(attacker, lane_idx, is_enemy)


func _resolve_swift_attack(lane_idx: int, row: int, is_enemy: bool,
		opponent_front_empty: Array[bool]) -> void:
	var attacker_field = _row_array(is_enemy, row)
	var card = attacker_field[lane_idx]
	if card == null or not card.has_keyword("swift") or card.has_attacked_this_turn or not card.can_attack():
		return
	card.has_attacked_this_turn = true
	if card.has_method("play_attack_lunge"):
		card.play_attack_lunge()
	await _short_pause(LUNGE_APEX)
	if not is_instance_valid(card):
		return

	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]
	var opponent: Control = null
	if opp_front != null:
		opponent = _redirect_target(opp_front, opp_is_enemy, lane_idx, ROW_FRONT)
	elif opp_back != null:
		opponent = _redirect_target(opp_back, opp_is_enemy, lane_idx, ROW_BACK)

	if opponent != null:
		var atk = _effective_attack(card, lane_idx, is_enemy)
		_play_attack_tracer(_card_center(card), _card_center(opponent), is_enemy)
		if opponent.has_method("play_hit_recoil"):
			opponent.play_hit_recoil(is_enemy)
		_apply_thorns(opponent, card, is_enemy)
		opponent.take_damage(atk)
		var was_lethal: bool = opponent.current_hp <= 0
		if was_lethal and (card.has_keyword("piercing") or (is_enemy and _has_encounter_passive_keyword(card, "piercing"))):
			_apply_piercing_overflow(card, opponent, lane_idx, is_enemy)
		if was_lethal:
			screen_shake(6.0)
			await _short_pause(HITSTOP_BEAT)
		elif atk >= HEAVY_HIT_DAMAGE:
			await _short_pause(HITSTOP_BEAT)
		else:
			await _short_pause(POST_HIT_BEAT)
	elif opponent_front_empty[lane_idx]:
		await _creature_hits_face(card, lane_idx, is_enemy)


func _apply_piercing_overflow(attacker: Control, victim: Control, lane_idx: int, is_enemy: bool) -> void:
	# Piercing kill: overflow damage spills to the next creature in the same
	# opposing column (front→back), then to face if nothing left in column.
	var excess = abs(victim.current_hp)
	var bonus = 1 if (not is_enemy and _has_relic("piercing_crown")) else 0
	var total = excess + bonus
	if total <= 0:
		return
	# Float a "PIERCED N" chip at the attacker so the overflow is visible.
	if is_instance_valid(attacker):
		var chip_pos := attacker.global_position + Vector2(attacker.size.x * attacker.scale.x * 0.5, -12)
		spawn_floating_number(chip_pos, "PIERCED %d" % total, Color(1.0, 0.62, 0.20), false)
	# Skewer VFX: a bright lance from the attacker straight through the slain victim
	# and on into the space behind it, with a spark where it punches out.
	if is_instance_valid(attacker) and is_instance_valid(victim):
		var a := _card_center(attacker)
		var v := _card_center(victim)
		var lance_dir := v - a
		if lance_dir.length() > 1.0:
			var beyond := v + lance_dir.normalized() * 130.0
			_play_pierce_lance(a, beyond)
			spawn_ash_burst(beyond, Color(1.0, 0.86, 0.46), 14)
	var opp_is_enemy = not is_enemy
	# If we killed the front, spill to back if it exists.
	var back_card = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]
	if victim == _row_array(opp_is_enemy, ROW_FRONT)[lane_idx] and back_card != null and back_card.current_hp > 0:
		back_card.take_damage(total)
		return
	# Otherwise go face.
	if is_enemy:
		damage_player_hero(total)
	else:
		damage_enemy_hero(total)



func _creature_attacks_creature(attacker: Control, defender: Control, lane_idx: int, attacker_is_enemy: bool) -> void:
	if attacker.has_method("play_attack_lunge"):
		attacker.play_attack_lunge()
	await _short_pause(LUNGE_APEX)
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	var atk = _effective_attack(attacker, lane_idx, attacker_is_enemy)
	# Marked/enrage vulnerability bonus damage
	if defender.get_meta("marked", false):
		atk += 2
	if defender.get_meta("enrage_vulnerable", false):
		atk += 1
	_apply_thorns(defender, attacker, attacker_is_enemy)
	# Royal Guard "Adj -1 dmg" — if an adjacent friendly (same row, ±1 lane) is
	# a Royal Guard, the defender takes 1 less damage. Min 1 dmg.
	if _has_adjacent_royal_guard(defender):
		atk = maxi(1, atk - 1)
	# Archlich passive: enemy creatures can't go below 1 HP from creature attacks
	if _encounter_passive == "archlich_immortal" and not attacker_is_enemy:
		var new_hp = defender.current_hp - atk
		if new_hp < 1:
			atk = maxi(0, defender.current_hp - 1)
	var who = "ENEMY" if attacker_is_enemy else "PLAYER"
	var defender_side = "PLAYER" if attacker_is_enemy else "ENEMY"
	print("[COMBAT] %s %s (%d ATK) hits %s %s (%d/%d HP) in lane %d → %d dmg → %d HP left" % [
		who, attacker.card_data.name, atk,
		defender_side, defender.card_data.name, defender.current_hp, defender.card_data.hp,
		lane_idx, atk, maxi(0, defender.current_hp - atk)])
	# Impact lands: streak from attacker to target and the defender recoils.
	_play_attack_tracer(_card_center(attacker), _card_center(defender), attacker_is_enemy)
	if defender.has_method("play_hit_recoil"):
		defender.play_hit_recoil(attacker_is_enemy)
	defender.take_damage(atk)
	attacker.has_attacked_this_turn = true
	var was_lethal: bool = defender.current_hp <= 0

	# Royal Guard "+1 ATK when hit" — if the defender is a Royal Guard and is
	# still alive after the hit, it grows in fury.
	if defender.current_hp > 0 and defender.card_data.get("passive", "") == "royal_guard" and atk > 0:
		defender.current_atk += 1
		defender.update_stat_display()

	if defender.current_hp <= 0 and (attacker.has_keyword("piercing") or (attacker_is_enemy and _has_encounter_passive_keyword(attacker, "piercing"))):
		_apply_piercing_overflow(attacker, defender, lane_idx, attacker_is_enemy)

	# Vampire Lord passive: heal 2 and +1 ATK on kill
	if not attacker_is_enemy and attacker.card_data.get("passive", "") == "vampire_lord" and defender.current_hp <= 0:
		player_hp = mini(player_hp + 2, player_max_hp)
		attacker.current_atk += 1
		attacker.update_stat_display()

	# Weighted punctuation: a kill or heavy blow gets a stronger shake + a brief
	# hit-stop; ordinary hits take just a short breath before the next attacker.
	if was_lethal:
		screen_shake(6.0)
		await _short_pause(HITSTOP_BEAT)
	elif atk >= HEAVY_HIT_DAMAGE:
		screen_shake(4.0)
		await _short_pause(HITSTOP_BEAT)
	else:
		await _short_pause(POST_HIT_BEAT)


func _creature_hits_face(card: Control, lane_idx: int, is_enemy: bool) -> void:
	if card.has_method("play_attack_lunge"):
		card.play_attack_lunge()
	await _short_pause(LUNGE_APEX)
	if not is_instance_valid(card):
		return
	var atk = _effective_attack(card, lane_idx, is_enemy)
	if is_enemy:
		if _encounter_passive == "harpy_swift_face" and card.has_keyword("swift"):
			atk += 1
		var reduction = _get_wall_reduction(lane_idx, false)
		atk = maxi(0, atk - reduction)
		if atk > 0:
			damage_player_hero(atk)
	else:
		damage_enemy_hero(atk)

	card.has_attacked_this_turn = true
	# Hero-damage functions already shake + flash; just pace the cascade.
	await _short_pause(HITSTOP_BEAT if atk > 0 else POST_HIT_BEAT)


func _resolve_hydra_attack(attacker: Control, lane_idx: int, is_enemy: bool) -> void:
	# Hydra strikes every opposing creature (both rows) at once, taking 1 back
	# from each as it bites through the line. If nothing opposes it, it batters
	# the face like any unblocked creature.
	attacker.has_attacked_this_turn = true
	if attacker.has_method("play_attack_lunge"):
		attacker.play_attack_lunge()
	await _short_pause(LUNGE_APEX)
	if not is_instance_valid(attacker):
		return
	var atk = _effective_attack(attacker, lane_idx, is_enemy)
	var targets = _all_player_creatures() if is_enemy else _all_enemy_creatures()
	var live: Array = []
	for t in targets:
		if t != null and t.current_hp > 0:
			live.append(t)
	if live.is_empty():
		if is_enemy:
			damage_player_hero(atk)
		else:
			damage_enemy_hero(atk)
		await _short_pause(HITSTOP_BEAT)
		return
	# Bites through the whole line at once — streak + recoil on every target.
	for t in live:
		_play_attack_tracer(_card_center(attacker), _card_center(t), is_enemy)
		if t.has_method("play_hit_recoil"):
			t.play_hit_recoil(is_enemy)
		t.take_damage(atk)
		if attacker.current_hp > 0:
			attacker.take_damage(1)
	screen_shake(6.0)
	await _short_pause(HITSTOP_BEAT)


func _redirect_target(defender: Control, defender_is_enemy: bool, lane_idx: int, row: int) -> Control:
	# Royal Guard's redirect floop: a friendly Royal Guard in the same row that
	# is "redirecting" and sits adjacent to the intended defender intercepts the
	# blow in its place.
	var field = _row_array(defender_is_enemy, row)
	for adj in [lane_idx - 1, lane_idx + 1]:
		if adj >= 0 and adj < LANES_PER_ROW:
			var g = field[adj]
			if g != null and g.current_hp > 0 and g.get_meta("redirecting", false) \
					and g.card_data.get("passive", "") == "royal_guard":
				return g
	return defender


func _resolve_ranged_attacks() -> void:
	# 4x4: ranged prefers back-row enemies (you can reach over the front line),
	# then front-row enemies, then face damage if the opposing side is empty.
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var attackers = _row_array(is_enemy, row)
			for lane_idx in range(LANES_PER_ROW):
				var card = attackers[lane_idx]
				if card == null or not card.has_keyword("ranged"):
					continue
				if card.has_attacked_this_turn or not card.can_attack():
					continue
				card.has_attacked_this_turn = true
				if card.has_method("play_attack_lunge"):
					card.play_attack_lunge()
				await _short_pause(LUNGE_APEX)
				if not is_instance_valid(card):
					continue
				var opp_is_enemy = not is_enemy
				# Hexagonal Shield: enemy ranged can't reach the player back row.
				var skip_back = is_enemy and _has_relic("hexagonal_shield")
				var back_targets: Array = []
				var front_targets: Array = []
				for l in range(LANES_PER_ROW):
					if not skip_back:
						var b = _row_array(opp_is_enemy, ROW_BACK)[l]
						if b != null and b.current_hp > 0:
							back_targets.append(b)
					var f = _row_array(opp_is_enemy, ROW_FRONT)[l]
					if f != null and f.current_hp > 0:
						front_targets.append(f)
				var atk = _effective_attack(card, lane_idx, is_enemy)
				var ranged_target: Control = null
				if back_targets.size() > 0:
					ranged_target = back_targets[randi() % back_targets.size()]
				elif front_targets.size() > 0:
					ranged_target = front_targets[randi() % front_targets.size()]
				if ranged_target != null and is_instance_valid(ranged_target):
					_play_attack_tracer(_card_center(card), _card_center(ranged_target), is_enemy)
					if ranged_target.has_method("play_hit_recoil"):
						ranged_target.play_hit_recoil(is_enemy)
					ranged_target.take_damage(atk)
					await _short_pause(HITSTOP_BEAT if ranged_target.current_hp <= 0 else POST_HIT_BEAT)
				else:
					if is_enemy:
						damage_player_hero(atk)
					else:
						damage_enemy_hero(atk)
					await _short_pause(POST_HIT_BEAT)


func _apply_thorns(defender: Control, attacker: Control, attacker_is_enemy: bool) -> void:
	if (defender.has_keyword("thorns") or (not attacker_is_enemy and _has_encounter_passive_keyword(defender, "thorns"))) and defender.current_hp > 0:
		var thorns_dmg = 1
		if not attacker_is_enemy and _has_relic("briar_amulet"):
			thorns_dmg = 2
		# Recoil bite: a red spark + chip on the attacker that ran onto the thorns.
		if is_instance_valid(attacker):
			spawn_ash_burst(_card_center(attacker), Color(0.85, 0.18, 0.20), 10)
			var thorn_pos := attacker.global_position + Vector2(attacker.size.x * attacker.scale.x * 0.5, -10)
			spawn_floating_number(thorn_pos, "THORNS!", Color(0.95, 0.38, 0.38), false)
		attacker.take_damage_bypass_armor(thorns_dmg)


func _effective_attack(card: Control, lane_idx: int, is_enemy: bool) -> int:
	var atk = card.effective_atk()
	if not is_enemy:
		atk += _get_adj_buff_atk(lane_idx, false)
		if card.has_keyword("swift") and _has_relic("swift_boots"):
			atk += 1
		if _has_bannerman_buff(false):
			atk += 1
		if _has_relic("glass_cannon"):
			atk += 1
		if _has_relic("stone_skin"):
			atk = maxi(0, atk - 1)
		# Vanguard Banner: front-row friendlies get +1 ATK.
		if card.current_row == ROW_FRONT and _has_relic("vanguard_banner"):
			atk += 1
	return maxi(0, atk)


func _get_adj_buff_atk(lane_idx: int, is_enemy: bool) -> int:
	# 4x4: adjacent-buff sources contribute from the same row as the attacker.
	# For now we sum both rows of the same column-1/column+1 because front and
	# back share the lane semantically — this keeps Bannerman-style cards
	# strong without needing a row-aware Card2D ref here.
	var total := 0
	for row in [ROW_FRONT, ROW_BACK]:
		var field = _row_array(is_enemy, row)
		for adj in [lane_idx - 1, lane_idx + 1]:
			if adj < 0 or adj >= LANES_PER_ROW:
				continue
			var neighbor = field[adj]
			if neighbor != null and neighbor.card_data.has("adj_buff"):
				total += neighbor.card_data.adj_buff.get("atk", 0)
				if not is_enemy and _has_relic("banner_of_unity"):
					total += 1
	return total


func _has_bannerman_buff(is_enemy: bool) -> bool:
	for c in _all_friendly(is_enemy):
		if c.card_data.get("passive", "") == "global_atk_buff":
			return true
	return false


func _has_passive_on_field(passive_name: String) -> bool:
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == passive_name:
			return true
	return false


func _get_wall_reduction(lane_idx: int, _is_enemy: bool) -> int:
	# 4x4: walls in either row contribute. "Cannot attack wall" reduces only
	# this column and its neighbors; "reduce_face_damage" reduces any face hit.
	var reduction := 0
	for c in _all_player_creatures():
		var passive = c.card_data.get("passive", "")
		if passive == "cannot_attack_wall":
			if abs(c.current_lane - lane_idx) <= 1:
				reduction += 1
		elif passive == "reduce_face_damage":
			reduction += 1
	return reduction


func _cleanup_dead() -> void:
	for row in [ROW_FRONT, ROW_BACK]:
		var p_arr = _row_array(false, row)
		var e_arr = _row_array(true, row)
		for lane_idx in range(LANES_PER_ROW):
			if p_arr[lane_idx] != null and p_arr[lane_idx].current_hp <= 0:
				# Phantom Veil: rescue the first friendly to die this round.
				if _has_relic("phantom_veil") and not get_meta("phantom_veil_used", false):
					set_meta("phantom_veil_used", true)
					p_arr[lane_idx].current_hp = 1
					p_arr[lane_idx].update_stat_display()
					continue
				var card = p_arr[lane_idx]
				KeywordEffects.dispatch_on_death(card, lane_idx, false, self)
				_on_friendly_death(card, lane_idx)
				_dispatch_encounter_on_player_death(lane_idx)
				_dispatch_reactive("ON_CREATURE_DEATH", card, lane_idx)
				if not card.is_token:
					_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))
				p_arr[lane_idx] = null
			if e_arr[lane_idx] != null and e_arr[lane_idx].current_hp <= 0:
				var card = e_arr[lane_idx]
				_last_dead_enemy_data = card.card_data.duplicate(true)
				KeywordEffects.dispatch_on_death(card, lane_idx, true, self)
				_dispatch_encounter_on_enemy_death(lane_idx)
				_dispatch_reactive("ON_CREATURE_DEATH", card, lane_idx)
				e_arr[lane_idx] = null


func _on_friendly_death(card: Control, _lane_idx: int) -> void:
	_friendly_deaths_this_fight += 1
	_friendly_deaths_this_round += 1
	_last_dead_creature_id = card.card_id
	if _friendly_deaths_this_round == 1 and _has_passive_on_field("draw_on_ally_death"):
		draw_one()
	# Corpse Eater grows on any friendly death (both rows).
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == "grow_on_ally_death":
			c.current_atk += 1
			c.update_stat_display()
	# Soul Lantern
	if _has_relic("soul_lantern") and not _soul_lantern_used_this_round:
		_soul_lantern_used_this_round = true
		_bonus_mana_next_turn += 1


func _post_combat_sequence() -> void:
	_post_combat_cleanup()
	_discard_hand()

	await _short_pause(COMBAT_PAUSE_MEDIUM)
	_enemy_place_creatures()

	# Escalation: after round N, regular fights double-place reinforcements.
	if _encounter_id != "":
		var enc = EncounterDB.get_encounter(_encounter_id)
		if enc.get("type", "") == "combat" and round_number >= ESCALATION_REINFORCE_ROUND:
			_enemy_place_creatures()

	# End-of-turn deaths (Assassin etc.) — both rows.
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == "dies_end_of_turn":
			var pos = _find_creature_position(c)
			if not pos.is_empty():
				c.take_damage(999)
				_row_array(false, pos.row)[pos.lane] = null

	_dispatch_passive_end_of_round()

	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		await _short_pause(COMBAT_PAUSE_MEDIUM)
		_start_round()


func _enemy_place_creatures() -> void:
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")
	var max_place := 1
	if round_number <= 2:
		max_place = 1
	elif enc_type == "elite" or enc_type == "boss":
		max_place = 2
	else:
		max_place = 1 if randi() % ENEMY_FLOOP_CHANCE_DENOM != 0 else 2

	var placed := 0
	# 4x4: priority is a list of {row, lane} slots — front first, then back.
	var slot_priority: Array = _get_placement_priority_4x4(enc_type)
	for slot in slot_priority:
		if placed >= max_place:
			break
		var arr = _row_array(true, slot.row)
		if arr[slot.lane] != null:
			continue
		if _enemy_deck.is_empty():
			if not _reinforcement.is_empty():
				_enemy_deck.append(_reinforcement.duplicate(true))
			else:
				var eid = CardDB.random_enemy_for_act(RunState.get_act())
				_enemy_deck.append(CardDB.get_card_data(eid))
		var card_data = _enemy_deck.pop_front()
		_place_enemy_card(card_data, slot.lane, slot.row)
		placed += 1


func _get_placement_priority_4x4(enc_type: String) -> Array:
	## Returns an ordered list of {row, lane} placement candidates.
	## Front row is always preferred (it's the active combat line).
	var slots: Array = []
	match enc_type:
		"elite":
			# Target the player's strongest creature first — same column, front row.
			var best_lane := -1
			var best_atk := -1
			for i in range(LANES_PER_ROW):
				var pf = _player_field[i]
				if pf != null and _enemy_field[i] == null:
					var atk = pf.effective_atk()
					if atk > best_atk:
						best_atk = atk
						best_lane = i
			if best_lane >= 0:
				slots.append({"row": ROW_FRONT, "lane": best_lane})
			for i in range(LANES_PER_ROW):
				if i != best_lane and _player_field[i] != null and _enemy_field[i] == null:
					slots.append({"row": ROW_FRONT, "lane": i})
		"boss":
			# Bosses spread out — prefer back-row support placement so the front
			# stays as a wall.  Then fill front.
			var bossy: Array = []
			for i in range(LANES_PER_ROW):
				if _enemy_field[i] == null:
					bossy.append({"row": ROW_FRONT, "lane": i})
			bossy.shuffle()
			slots.append_array(bossy)
		_:
			# Regular: block player columns first, then any empty front.
			for i in range(LANES_PER_ROW):
				if _player_field[i] != null and _enemy_field[i] == null:
					slots.append({"row": ROW_FRONT, "lane": i})
	# Always fall through: any open front slot, then any open back slot.
	for i in range(LANES_PER_ROW):
		if _enemy_field[i] == null and not _slot_in_list(slots, ROW_FRONT, i):
			slots.append({"row": ROW_FRONT, "lane": i})
	for i in range(LANES_PER_ROW):
		if _enemy_back[i] == null:
			slots.append({"row": ROW_BACK, "lane": i})
	return slots


func _slot_in_list(slots: Array, row: int, lane: int) -> bool:
	for s in slots:
		if s.row == row and s.lane == lane:
			return true
	return false


func _place_enemy_card(data: Dictionary, lane_idx: int, row: int = ROW_FRONT) -> void:
	var card = CARD_SCENE.instantiate()
	card.card_id = data.id
	card.is_opponent = true
	card.is_on_battlefield = true
	card.compact_mode = true   # battlefield cards use the smaller variant
	card.card_data = data
	card.current_lane = lane_idx
	card.current_row = row
	_row_array(true, row)[lane_idx] = card
	var slot = _slot_array(true, row)[lane_idx]
	_slot_set_card(slot, card)
	_play_landing_pop(card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	if _has_relic("philosophers_stone"):
		card.current_atk += 1
		card.update_stat_display()
	KeywordEffects.dispatch_on_enter(card, lane_idx, true, self)
	_dispatch_encounter_on_enter(data, lane_idx)
	# Show the freshly-placed creature's intent immediately so it's never
	# blank between placement and the next intent-assignment pass.
	_update_intent_display(card, "ATK")


func _build_ambient_fx() -> void:
	# Drifting embers across the battlefield — warm sparks rising from the
	# burning meadow. CPUParticles2D (not GPU) so it renders identically on
	# every backend. Sits above the background TextureRect but below the board
	# cards (moved to tree index 1) so cards always read clearly on top.
	var vp := get_viewport_rect().size
	var embers := CPUParticles2D.new()
	embers.name = "AmbientEmbers"
	embers.amount = 46
	embers.lifetime = 5.0
	embers.preprocess = 4.0   # start mid-stream, not empty
	embers.position = Vector2(vp.x * 0.5, vp.y + 20.0)
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(vp.x * 0.55, 30.0)
	embers.direction = Vector2(0, -1)
	embers.spread = 22.0
	embers.gravity = Vector2(0, -14.0)         # gentle upward float
	embers.initial_velocity_min = 26.0
	embers.initial_velocity_max = 64.0
	embers.angular_velocity_min = -40.0
	embers.angular_velocity_max = 40.0
	embers.scale_amount_min = 1.4
	embers.scale_amount_max = 3.2
	# Warm ember gradient: bright orange core → fade to dark red, alpha out.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.75, 0.30, 0.0))
	grad.set_color(1, Color(0.9, 0.25, 0.10, 0.0))
	grad.add_point(0.15, Color(1.0, 0.70, 0.30, 0.9))
	grad.add_point(0.7, Color(0.95, 0.40, 0.15, 0.55))
	embers.color_ramp = grad
	add_child(embers)
	move_child(embers, 1)   # just above the background, below the board


func _on_end_turn_confirmed() -> void:
	# Player accepted the end-turn warning dialog. Re-enter _on_end_turn with
	# the confirmed flag set so the warning check is bypassed.
	_end_turn_confirmed = true
	_on_end_turn()


func _has_playable_action() -> bool:
	# Returns true if the player could still do something this turn: an
	# affordable card in hand OR an unused sacrifice. Used to decide whether
	# the end-turn warning dialog should appear.
	if not _sacrifice_used_this_turn:
		# A sacrifice is technically always playable if any friendly creature exists.
		for c in _all_player_creatures():
			if c != null:
				return true
	for card in _hand:
		if card == null or not is_instance_valid(card):
			continue
		var cost: int = int(card.card_data.get("cost", 0))
		if player_mana >= cost:
			return true
	return false


func _short_pause(duration: float) -> void:
	# Scaled by UserSettings.anim_speed so the player's animation-speed pref
	# affects ALL combat pacing (draw, attack, death, end-of-turn). Speed 3.0
	# (Instant) collapses pauses to a single frame.
	var scaled: float = duration
	if UserSettings != null and UserSettings.anim_speed > 0.01:
		scaled = duration / UserSettings.anim_speed
	if scaled <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(scaled).timeout


# =====================================================================
#  CARD PLAY
# =====================================================================

func _on_card_played(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _sacrifice_mode:
		_cancel_sacrifice()
	if _targeting_spell != null:
		_cancel_targeting()

	# Velvet Choker: max 5 cards per turn
	if _has_relic("velvet_choker") and _cards_played_this_turn >= 5:
		_show_info("Velvet Choker: can't play more than 5 cards!")
		return

	var cost = card.card_data.cost
	if card.is_spell() and _has_relic("ember_crown") and not _first_spell_this_turn:
		cost = 0
	if player_mana < cost:
		_show_info("Not enough mana!")
		return

	if card.is_spell():
		_play_spell(card, cost)
	else:
		_play_creature(card, cost)


func _play_creature(card: Control, cost: int) -> void:
	if card.has_keyword("sacrifice"):
		_show_info("Click a creature to sacrifice for this card.")
		return

	# 4x4: derive both lane and row from the drop position. Use the card's CENTER
	# (not its top-left origin) so the slot we pick matches the one the drag
	# highlight lit up — `dragging` emits `global_position + size*scale*0.5`, and
	# reading the raw origin here biased every drop one row up into the front row.
	# Drops on occupied slots are rejected (no replace) — creatures stay where
	# they were placed unless an explicit effect moves them.
	var drop = _nearest_player_slot(card.global_position + card.size * card.scale * 0.5)
	var lane_idx: int = drop.lane
	var row: int = drop.row
	var field = _row_array(false, row)
	if field[lane_idx] != null:
		_show_info("That slot is occupied.")
		_layout_hand()
		return

	player_mana -= cost
	_pulse_mana_label(cost)
	_cards_played_this_turn += 1
	_hand.erase(card)
	_hand_container.remove_child(card)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")

	card.is_on_battlefield = true
	card.current_lane = lane_idx
	card.current_row = row
	# Hand → battlefield: shrink to the compact variant so the 4x4 grid fits.
	card.set_compact_mode(true)

	if not _first_creature_played and _has_relic("iron_buckler"):
		card.current_hp += 2
		card.card_data.hp += 2
	if _has_relic("veterans_medal") and card.card_data.cost == 1 and card.is_creature():
		card.current_atk += 1
		card.current_hp += 1
		card.card_data.hp += 1
	if _has_relic("glass_cannon") and card.is_creature():
		card.current_hp = maxi(1, card.current_hp - 1)
		card.card_data.hp = maxi(1, card.card_data.hp - 1)
	if _has_relic("stone_skin") and card.is_creature():
		card.current_hp += 1
		card.card_data.hp += 1

	_first_creature_played = true
	# Butcher's Cleaver — consume armed state, grant +2 ATK for 2 rounds.
	if _butchers_cleaver_armed and _has_relic("butchers_cleaver"):
		_butchers_cleaver_armed = false
		var bc_value: int = RelicDB.get_relic("butchers_cleaver").get("value", 2)
		card.persistent_atk_buff += bc_value
		card.persistent_atk_buff_rounds = 2
		card.update_stat_display()
	_place_card_in_slot(card, lane_idx, row)

	# Encounter passive: collector heals on creature played
	if _encounter_passive == "collector_heal":
		enemy_hp = mini(enemy_hp + 1, enemy_max_hp)
	elif _encounter_passive == "collector_phase2":
		enemy_hp = mini(enemy_hp + 2, enemy_max_hp)
		_buff_random_enemy_atk(1)

	# On-enter effects
	KeywordEffects.dispatch_on_enter(card, lane_idx, false, self)

	# Ironclad Veteran
	if card.card_data.get("on_enter", {}).get("type", "") == "atk_per_cards_played":
		card.current_atk += _cards_played_this_turn - 1
		card.update_stat_display()

	# Vengeful Spirit
	if card.card_data.get("passive", "") == "atk_per_face_damage":
		card.current_atk += _face_damage_taken_this_fight
		card.update_stat_display()

	# Summon keyword
	if card.has_keyword("summon"):
		KeywordEffects._do_summon(lane_idx, false, self)
		# Reactive passive: ON_PLAYER_SUMMON
		_dispatch_reactive("ON_PLAYER_SUMMON", card, lane_idx)

	card.update_stat_display()
	_update_hud()


func _play_spell(card: Control, cost: int) -> void:
	var targeting = card.card_data.get("targeting", "none")
	if targeting != "none":
		player_mana -= cost
		_pulse_mana_label(cost)
		_first_spell_this_turn = true
		_cards_played_this_turn += 1
		_hand.erase(card)
		_hand_container.remove_child(card)
		_targeting_spell = card
		_targeting_data = card.card_data
		_show_info("Click a target...")
		_show_targeting_arrow()
		_update_hud()
		return

	# Non-targeted spell: resolve immediately
	player_mana -= cost
	_pulse_mana_label(cost)
	_first_spell_this_turn = true
	_cards_played_this_turn += 1
	_hand.erase(card)
	_hand_container.remove_child(card)
	_resolve_spell(card.card_data, null, -1)
	_after_spell(card)


func _resolve_spell(data: Dictionary, target: Control, target_lane: int) -> void:
	var spell = data.get("spell", {})
	var spell_type = spell.get("type", "")
	var value = spell.get("value", 0)

	# Spell damage bonus
	if _has_relic("worn_spellbook") and spell_type == "damage":
		value += 1

	# Fire a colored burst at the spell's resolution point so every spell has
	# visible feedback (the underlying effect like take_damage shakes the target
	# but doesn't read as "you cast something").
	_play_spell_cast_vfx(spell_type, target)

	match spell_type:
		"damage":
			if target != null:
				target.take_damage(value)
		"damage_face":
			var bonus = 1 if _has_relic("pyromaniac_ring") else 0
			damage_enemy_hero(value + bonus)
		"damage_all_enemies":
			for c in _all_enemy_creatures():
				c.take_damage(value)
		"damage_all":
			for c in _all_creatures_both_sides():
				c.take_damage(value)
			_cleanup_dead()
		"buff_atk":
			if target != null:
				var bonus = 1 if _has_relic("war_horn") else 0
				if spell.get("permanent", false):
					target.current_atk += value + bonus
				else:
					target.temp_atk_buff += value + bonus
				target.update_stat_display()
		"buff_hp":
			if target != null:
				target.current_hp += value
				target.card_data.hp += value
				target.update_stat_display()
		"heal":
			if target != null:
				var before: int = target.current_hp
				target.current_hp = mini(target.current_hp + value, target.card_data.hp)
				target.update_stat_display()
				if target.has_method("show_heal_number"):
					target.show_heal_number(target.current_hp - before)
		"draw":
			for i in value:
				draw_one()
		"buff_all_atk":
			var bonus = 1 if _has_relic("war_horn") else 0
			for c in _all_player_creatures():
				if spell.get("permanent", false):
					c.current_atk += value + bonus
				else:
					c.temp_atk_buff += value + bonus
				c.update_stat_display()
		"custom":
			_resolve_custom_spell(spell.get("id", ""), target, target_lane)

	_last_spell_played_this_turn = data


func _resolve_custom_spell(spell_id: String, target: Control, _target_lane: int) -> void:
	match spell_id:
		"blood_tithe":
			var bonus = 1 if _has_relic("pyromaniac_ring") else 0
			damage_enemy_hero(2 + bonus)
			damage_player_hero(1)
		"reckless_charge":
			if target != null:
				var value = 3 + (1 if _has_relic("worn_spellbook") else 0)
				target.take_damage(value)
			draw_one()
			damage_player_hero(1)
		"shove":
			if target != null:
				# 4x4: shove the target to another empty lane in its own row.
				var pos = _find_creature_position(target)
				if pos.is_empty():
					return
				var row_arr = _row_array(pos.is_enemy, pos.row)
				var empty: Array[int] = []
				for i in range(LANES_PER_ROW):
					if row_arr[i] == null:
						empty.append(i)
				target.take_damage(1)
				if empty.size() > 0:
					var new_lane = empty[randi() % empty.size()]
					row_arr[pos.lane] = null
					row_arr[new_lane] = target
					target.current_lane = new_lane
					var slots = _slot_array(pos.is_enemy, pos.row)
					_slot_take_card(slots[pos.lane], target)
					_slot_set_card(slots[new_lane], target)
		"second_wind":
			if target != null:
				target.current_hp = target.card_data.hp
				target.current_atk += 1
				target.update_stat_display()
		"lightning":
			if target != null:
				target.take_damage(2)
			damage_enemy_hero(2)
		"offering":
			if target != null:
				target.take_damage(999)
				player_mana += 2
		"unholy_bargain":
			for i in 3:
				draw_one()
			damage_player_hero(3)
		"dark_pact":
			for c in _all_player_creatures():
				c.current_atk += 1
				c.update_stat_display()
			damage_player_hero(2)
		"kings_command":
			for c in _all_player_creatures():
				c.temp_atk_buff += 3
				c.current_hp += 1
				c.card_data.hp += 1
				c.update_stat_display()
		"mass_grave":
			var kills := 0
			for c in _all_player_creatures():
				c.take_damage(999)
				kills += 1
			# Clear arrays after the kills.
			for row in [ROW_FRONT, ROW_BACK]:
				var arr = _row_array(false, row)
				for i in range(LANES_PER_ROW):
					arr[i] = null
			damage_enemy_hero(kills * 3)
		"grave_robbery":
			if _last_dead_creature_id != "":
				_player_draw_pile.push_front(_last_dead_creature_id)
				draw_one()
		"cataclysm":
			var max_atk := 0
			for c in _all_player_creatures():
				max_atk = maxi(max_atk, c.effective_atk())
			for c in _all_enemy_creatures():
				c.take_damage(max_atk)
		"soul_swap":
			if target != null:
				var tmp = target.current_atk
				target.current_atk = target.current_hp
				target.current_hp = tmp
				target.card_data.hp = target.current_hp
				target.update_stat_display()
		"apocalypse":
			var kills := 0
			for c in _all_creatures_both_sides():
				c.take_damage(999)
				kills += 1
			for is_enemy in [false, true]:
				for row in [ROW_FRONT, ROW_BACK]:
					var arr = _row_array(is_enemy, row)
					for i in range(LANES_PER_ROW):
						arr[i] = null
			damage_player_hero(kills)
		"grave_pact":
			_grave_pact_active = true
		"fuel_the_pyre":
			if target != null:
				var atk = target.effective_atk()
				target.take_damage(999)
				var enemies = _all_enemy_creatures()
				if enemies.size() > 0:
					enemies[randi() % enemies.size()].take_damage(atk)
				else:
					damage_enemy_hero(atk)
		"pillage":
			if target != null:
				var value = 3 + (1 if _has_relic("worn_spellbook") else 0)
				target.take_damage(value)
				if target.current_hp <= 0:
					RunState.gain_gold(10)
		"war_chant":
			# Discard 2 from hand
			var discarded := 0
			while _hand.size() > 0 and discarded < 2:
				var c = _hand.pop_back()
				_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
				_hand_container.remove_child(c)
				c.queue_free()
				discarded += 1
			if discarded > 0:
				player_mana += 1
		"scrap":
			if _hand.size() > 0:
				var c = _hand.pop_back()
				_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
				_hand_container.remove_child(c)
				c.queue_free()
				player_mana += 1
		"gambit":
			var to_discard = mini(3, _hand.size())
			for i in to_discard:
				if _hand.size() > 0:
					var c = _hand.pop_back()
					_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
					_hand_container.remove_child(c)
					c.queue_free()
			for i in to_discard:
				draw_one()
		"barricade":
			if target != null:
				target.current_hp += 3
				target.card_data.hp += 3
				target.update_stat_display()
		"inferno":
			for c in _all_enemy_creatures():
				c.take_damage(4)
			damage_enemy_hero(4)
		"overwhelming_force":
			for c in _all_player_creatures():
				c.current_atk += 3
				c.update_stat_display()
		"lay_on_hands":
			if target != null:
				target.card_data.hp += 2
				target.current_hp = target.card_data.hp
				target.update_stat_display()
		"mending_light":
			player_hp = mini(player_hp + 8, player_max_hp)
			for c in _all_player_creatures():
				c.current_hp = mini(c.current_hp + 3, c.card_data.hp)
				c.update_stat_display()
		"banish":
			if target != null:
				var pos = _find_creature_position(target)
				if not pos.is_empty():
					_row_array(pos.is_enemy, pos.row)[pos.lane] = null
				target.queue_free()
		"time_snare":
			for c in _all_enemy_creatures():
				c.state.stunned = true
		"holy_smite":
			if target != null:
				var missing = target.card_data.hp - target.current_hp
				target.take_damage(maxi(0, missing))
		"adrenaline":
			player_mana += 1
			draw_one()
			draw_one()
		"bloodletting":
			damage_player_hero(2)
			player_mana += 2
		"turbo":
			player_mana += 2
			_player_discard_pile.append("curse")
		"concentrate":
			var discarded := 0
			while _hand.size() > 0 and discarded < 2:
				var c = _hand.pop_back()
				_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
				_hand_container.remove_child(c)
				c.queue_free()
				discarded += 1
			if discarded >= 2:
				player_mana += 2
		"recycle":
			# Enter targeting mode — simplified: discard highest cost card from hand
			if _hand.size() > 0:
				var best_idx := 0
				var best_cost := 0
				for i in range(_hand.size()):
					var cost = _hand[i].card_data.get("cost", 0)
					if cost > best_cost:
						best_cost = cost
						best_idx = i
				var c = _hand[best_idx]
				_hand.remove_at(best_idx)
				_hand_container.remove_child(c)
				_exhaust_pile.append(c.card_id)
				c.queue_free()
				player_mana += best_cost
		"reposition":
			# Swap two friendly creatures' positions; both gain +1 ATK this turn.
			var creatures: Array = []
			for r in [ROW_FRONT, ROW_BACK]:
				var arr = _row_array(false, r)
				for l in range(LANES_PER_ROW):
					if arr[l] != null and arr[l].current_hp > 0:
						creatures.append({"card": arr[l], "row": r, "lane": l})
			if creatures.size() >= 2:
				creatures.shuffle()
				var a = creatures[0]
				var b = creatures[1]
				_row_array(false, a.row)[a.lane] = b.card
				_row_array(false, b.row)[b.lane] = a.card
				var a_slot = _slot_array(false, a.row)[a.lane]
				var b_slot = _slot_array(false, b.row)[b.lane]
				_slot_take_card(a_slot, a.card)
				_slot_take_card(b_slot, b.card)
				_slot_set_card(b_slot, a.card)
				_slot_set_card(a_slot, b.card)
				a.card.current_lane = b.lane
				a.card.current_row = b.row
				b.card.current_lane = a.lane
				b.card.current_row = a.row
				a.card.temp_atk_buff += 1
				b.card.temp_atk_buff += 1
				a.card.update_stat_display()
				b.card.update_stat_display()
		"echo_spell":
			# Re-resolve the last spell played this turn (auto-targeted).
			var last = _last_spell_played_this_turn
			if last.is_empty():
				return
			if last.get("spell", {}).get("id", "") == "echo_spell":
				return  # Don't echo an Echo — avoids infinite regress.
			var t := _auto_target_for(last.get("targeting", "none"))
			var tlane: int = t.current_lane if t != null else -1
			_resolve_spell(last, t, tlane)
		_:
			pass

	_update_hud()


func _after_spell(card: Control) -> void:
	if card.has_keyword("exhaust"):
		_exhaust_pile.append(card.card_id)
	else:
		_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))
	card.queue_free()
	# Encounter passive: demon_spell_buff
	if _encounter_passive == "demon_spell_buff":
		_buff_random_enemy_atk(1)
	# Reactive passive: ON_PLAYER_SPELL
	_dispatch_reactive("ON_PLAYER_SPELL", null, -1)
	_cleanup_dead()
	_update_hud()


# =====================================================================
#  TARGETING MODE
# =====================================================================

func _input(event: InputEvent) -> void:
	# Glossary hotkeys are handled here (before UI focus traversal) so Tab and
	# ? are not consumed by button focus navigation.
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB, KEY_QUESTION, KEY_SLASH:
				_toggle_glossary()
				get_viewport().set_input_as_handled()
				return
			KEY_ESCAPE:
				if _glossary_layer != null and is_instance_valid(_glossary_layer):
					_close_glossary()
					get_viewport().set_input_as_handled()
					return
				if _pile_viewer_layer != null and is_instance_valid(_pile_viewer_layer):
					_close_pile_viewer()
					get_viewport().set_input_as_handled()
					return
			KEY_F1:
				if phase != Phase.GAME_OVER:
					_debug_auto_win()
					get_viewport().set_input_as_handled()
					return
	if _targeting_spell != null and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_resolve_target(event.global_position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_targeting()
			get_viewport().set_input_as_handled()
	elif _sacrifice_mode and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_sacrifice_target(event.global_position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_sacrifice()
			get_viewport().set_input_as_handled()


func _try_resolve_target(pos: Vector2) -> void:
	var targeting = _targeting_data.get("targeting", "none")
	# 4x4: scan both rows for clickable targets.
	if targeting in ["enemy_creature", "any_creature", "any"]:
		for e in _all_enemy_creatures():
			if _is_click_on_card(pos, e):
				_resolve_spell(_targeting_data, e, e.current_lane)
				_after_spell(_targeting_spell)
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				_hide_targeting_arrow()
				return
	if targeting in ["friendly_creature", "any_creature", "any"]:
		for p in _all_player_creatures():
			if _is_click_on_card(pos, p):
				_resolve_spell(_targeting_data, p, p.current_lane)
				_after_spell(_targeting_spell)
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				_hide_targeting_arrow()
				return
	# "any" targeting: check if clicked enemy hero area (top of screen)
	if targeting == "any" and pos.y < get_viewport_rect().size.y * 0.15:
		var spell = _targeting_data.get("spell", {})
		var value = spell.get("value", 0)
		if _has_relic("worn_spellbook") and spell.get("type", "") == "damage":
			value += 1
		damage_enemy_hero(value)
		_after_spell(_targeting_spell)
		_targeting_spell = null
		_targeting_data = {}
		_info_label.text = ""
		_hide_targeting_arrow()
		return


func _cancel_targeting() -> void:
	if _targeting_spell == null:
		return
	# Return spell to hand
	player_mana += _targeting_data.cost
	_cards_played_this_turn -= 1
	_hand_container.add_child(_targeting_spell)
	_hand.append(_targeting_spell)
	_targeting_spell.played.connect(_on_card_played.bind(_targeting_spell))
	_targeting_spell = null
	_targeting_data = {}
	_info_label.text = ""
	_hide_targeting_arrow()
	_layout_hand()
	_update_hud()


func _is_click_on_card(pos: Vector2, card: Control) -> bool:
	var rect = Rect2(card.global_position, card.size)
	return rect.has_point(pos)


# =====================================================================
#  SACRIFICE
# =====================================================================

func _on_sacrifice_pressed() -> void:
	if phase != Phase.PLAYER_TURN or _sacrifice_used_this_turn:
		return
	if _targeting_spell != null:
		_cancel_targeting()
	_sacrifice_mode = true
	_sacrifice_btn.text = "CANCEL [X]"
	_show_info("Click a creature to sacrifice...")
	_maybe_show_sacrifice_tutorial()


func _cancel_sacrifice() -> void:
	_sacrifice_mode = false
	_sacrifice_btn.text = "SACRIFICE [S]"
	_info_label.text = ""


func _try_sacrifice_target(pos: Vector2) -> void:
	# 4x4: any of the 8 player slots can be the sacrifice target.
	for card in _all_player_creatures():
		if _is_click_on_card(pos, card):
			var pos_info = _find_creature_position(card)
			if not pos_info.is_empty():
				_sacrifice_creature(pos_info.lane, pos_info.row)
			return


func _sacrifice_creature(lane_idx: int, row: int = ROW_FRONT) -> void:
	var card = _row_array(false, row)[lane_idx]
	if card == null:
		return
	_sacrifice_used_this_turn = true
	_sacrifice_mode = false
	_sacrifice_btn.text = "SACRIFICE [S]"
	_sacrifice_btn.disabled = true

	# Bone Pile relic
	if _has_relic("bone_pile"):
		var opp = get_opposing_card(lane_idx, false)
		if opp != null:
			opp.take_damage(card.effective_atk())

	# Butcher's Cleaver relic — arm for next creature played this turn.
	if _has_relic("butchers_cleaver"):
		_butchers_cleaver_armed = true

	# Sacrifice ritual: a crimson veil, a rising ember burst, and an altar shake as
	# the body is given up. mark_sacrifice_death() makes the card ash away upward
	# (Card2D._die) instead of the ordinary shrink-and-fade.
	if card.has_method("mark_sacrifice_death"):
		card.mark_sacrifice_death()
	screen_flash(Color(0.62, 0.06, 0.05, 0.42), 0.5)
	spawn_ash_burst(_card_center(card), Color(1.0, 0.45, 0.12), 34)
	screen_shake(7.0)
	if AudioBank != null:
		AudioBank.play_sfx("sacrifice")
	KeywordEffects.dispatch_on_death(card, lane_idx, false, self)
	_on_friendly_death(card, lane_idx)
	card.take_damage(999)
	# _on_card_destroyed handles adding to discard pile and nulling field
	_restore_slot_label(_slot_array(false, row)[lane_idx], lane_idx)
	# Reactive passive: ON_PLAYER_SACRIFICE
	_dispatch_reactive("ON_PLAYER_SACRIFICE", null, lane_idx)
	_info_label.text = ""
	_update_hud()


# =====================================================================
#  FLOOP (free toggle — click battlefield creature to activate)
# =====================================================================

func _on_floop_clicked(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _sacrifice_mode:
		# Click during sacrifice mode → sacrifice this creature (any row).
		var pos = _find_creature_position(card)
		if not pos.is_empty() and not pos.is_enemy:
			_sacrifice_creature(pos.lane, pos.row)
		return
	if _targeting_spell != null:
		return
	if not card.has_floop():
		return
	card.toggle_floop()
	if card.will_floop:
		_show_info(card.card_data.name + " set to floop!")
		_maybe_show_floop_tutorial()
	else:
		_show_info("Floop cancelled.")
	_update_hud()


func _maybe_show_floop_tutorial() -> void:
	# Tier 1 onboarding: one-time popup the first time a player toggles a floop.
	if _floop_tutorial_shown:
		return
	_floop_tutorial_shown = true
	UserSettings.mark_floop_tutorial_seen()
	_show_tutorial_tip("FLOOP: Skip this creature's attack to use its special ability instead.")


func _maybe_show_sacrifice_tutorial() -> void:
	if _sacrifice_tutorial_shown:
		return
	_sacrifice_tutorial_shown = true
	UserSettings.mark_sacrifice_tutorial_seen()
	_show_tutorial_tip("SACRIFICE: Destroy a friendly creature to trigger its on-death ability. Free, once per turn.")


func _maybe_show_banking_tutorial() -> void:
	if _banking_tutorial_shown:
		return
	_banking_tutorial_shown = true
	UserSettings.mark_banking_tutorial_seen()
	_show_tutorial_tip("BANK: Unspent mana carries over to next turn (max 1). End turns early to save up.")


func _maybe_show_intents_tutorial() -> void:
	if _intents_tutorial_shown:
		return
	_intents_tutorial_shown = true
	UserSettings.mark_intents_tutorial_seen()
	_show_tutorial_tip("INTENT BADGES: Numbers above enemies show what they'll do this turn. Plan your blocks.")


func _maybe_show_pile_tutorial() -> void:
	if _pile_tutorial_shown:
		return
	_pile_tutorial_shown = true
	UserSettings.mark_pile_tutorial_seen()
	_show_tutorial_tip("TIP: Click your deck or discard pile (bottom-left) to see what's in it.")


func _show_tutorial_tip(msg: String) -> void:
	# Longer dwell than _show_info — new players need time to actually read.
	# Falls back to the standard info channel if _info_label isn't built yet.
	if _info_label == null:
		return
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	get_tree().create_timer(6.0).timeout.connect(func():
		# Only clear if the tip is still showing (don't stomp on later messages).
		if _info_label != null and _info_label.text == msg:
			_info_label.text = "")


# =====================================================================
#  HAND & DECK
# =====================================================================

func draw_one() -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	if _player_draw_pile.is_empty():
		if _player_discard_pile.is_empty():
			return
		_player_draw_pile = _player_discard_pile.duplicate()
		_player_draw_pile.shuffle()
		_player_discard_pile.clear()
		# Sundial: every 3 shuffles gain 2 mana
		if _has_relic("sundial"):
			_sundial_count += 1
			if _sundial_count % 3 == 0:
				player_mana += 2
				_update_hud()
	if _player_draw_pile.is_empty():
		return
	_draw_card(_player_draw_pile.pop_front())
	_extra_draws_this_turn += 1
	# Reactive passive: ON_PLAYER_DRAW (triggers only on extra draws beyond 5)
	if _extra_draws_this_turn > HAND_DRAW_PER_TURN:
		_dispatch_reactive("ON_PLAYER_DRAW", null, -1)


func _draw_card(entry: String) -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	if AudioBank != null:
		AudioBank.play_sfx("card_draw")
	var card = CARD_SCENE.instantiate()
	var card_id := _entry_id(entry)
	var uid := _entry_uid(entry)
	card.card_id = card_id
	card.deck_uid = uid
	card.card_data = _resolve_card_data(card_id, uid)
	# Use the baked-overlay layout if CardTextureCache has the texture; falls
	# back to v4 silently on cache miss (rare — happens only if the card was
	# added to the draw pile after _prebake_hand_textures ran).
	card.live_baked_mode = true
	_hand_container.add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))
	# Light up the closest player slot while the card is being dragged so the
	# player can see exactly where it'll land. Spells use targeting arrows
	# instead, so only creatures get the drop-zone highlight.
	if card.is_creature():
		card.dragging.connect(_on_card_dragging.bind(card))
		card.drag_ended.connect(_clear_slot_highlights)
	# Deal the card in from the deck pile: start it small at the deck's screen
	# position so the hand-reflow tween (in Card2D.set_hand_target) slides it
	# into the fan. _hand_container is a plain Control, so manual position sticks.
	if _hand_container != null and _hand_container.global_position != Vector2.ZERO:
		var deck_screen := Vector2(100.0, 311.0)
		card.position = deck_screen - _hand_container.global_position - Vector2(96.0, 128.0)
		card.scale = Vector2(0.6, 0.6)
	_layout_hand()


# ─────────────────────────────────────────────────────────────────────────
# Hand layout — Hearthstone-lite fan
# ─────────────────────────────────────────────────────────────────────────
#
# Cards arc along a shallow circle: bottom-centres trace the arc, rotation
# tangents to it, so the right cards lean clockwise and the left cards
# counter-clockwise. With few cards the spread is wide (cards don't touch);
# at MAX_HAND_SIZE (10) cards overlap by ~50% so the whole hand still fits
# inside the container width. Pivot per card is bottom-centre (set in
# Card2D.set_hand_target) so the rotation visually swings the TOP of the
# card outward while the bottom stays anchored to the arc.
#
# Called any time _hand changes size: after _draw_card, _discard_hand, the
# play-to-lane flow, and the various retain / exile paths.
func _layout_hand() -> void:
	if _hand_container == null:
		return
	var n: int = _hand.size()
	if n == 0:
		return

	var area := _hand_container.size
	const CARD_W := 225.0
	const CARD_H := 300.0
	# Resting scale — cards in the hand render at 80% of their native size
	# so more cards fit comfortably and the fan is less cramped at the
	# 10-card cap. Hover scales back to 1.15 (a 1.44x visual pop). Combined
	# with the peek-below positioning, this is the Hearthstone-on-Switch
	# silhouette: a row of trimmed thumbnails at the bottom that leap up
	# and grow when you mouse one.
	const REST_SCALE := Vector2(0.85, 0.85)
	# How far below the container's bottom edge the cards' bottom-centres
	# anchor. Cards at scale 0.85 have a rendered height of ~255 px; with
	# the bottom 60 px past the container edge, roughly 70% of the card
	# stays visible at rest, art + name + cost. The ATK/HP orbs hang past
	# the card silhouette by another ~7 px scaled, so they're hidden too.
	# Hover lifts the card by 80 px (Card2D._on_mouse_entered) bringing it
	# fully into view plus an elevation pop above its neighbours.
	const PEEK := 60.0

	# Card-to-card centre spacing. Wide when there's room (cards don't touch);
	# clamps when n is large so the hand fits the container width minus a
	# half-card margin on each side. Tightened relative to the all-1.0-scale
	# pass since each card now renders 34 px narrower (0.85 × 225 = 191 vs 225).
	const SPREAD_MAX := 140.0
	const SPREAD_MIN := 65.0
	var spread: float = SPREAD_MAX
	if n > 1:
		var max_total: float = area.x - CARD_W
		spread = clamp(max_total / float(n - 1), SPREAD_MIN, SPREAD_MAX)

	# Fan parameters — subtle preset:
	#   total_angle: max angular spread across the whole hand (radians)
	#   arc_drop:    Y offset of the outermost cards (parabolic curve)
	# Both scale with card count so a 2-card hand barely fans, a full hand
	# fans noticeably.
	var total_angle: float = deg_to_rad(min(float(n - 1) * 2.4, 12.0))
	var arc_drop: float = min(float(n - 1) * 3.2, 18.0)

	# Anchor: bottom-centre of the hand area sits PEEK pixels past the
	# container's bottom edge so cards visibly hang off the screen at rest.
	var anchor_x: float = area.x * 0.5
	var anchor_y: float = area.y + PEEK

	for i in range(n):
		var card = _hand[i]
		if card == null or not is_instance_valid(card):
			continue
		# t ∈ [0, 1]; t = 0.5 is the centre of the hand.
		var t: float = 0.5 if n == 1 else float(i) / float(n - 1)
		var x_offset: float = (t - 0.5) * spread * float(n - 1)
		# Parabolic drop: (2|t-0.5|)^2 peaks at 1 on the outermost cards.
		var y_offset: float = pow(abs(t - 0.5) * 2.0, 2.0) * arc_drop
		var rot: float = (t - 0.5) * total_angle
		# Card's bottom-centre target. The card's pivot is its bottom-centre
		# (set in set_hand_target) so the position we pass is the bottom-
		# centre minus (W/2, H) to land the top-left. The pivot stays fixed
		# under the rest-scale, so spacing math uses unscaled card width —
		# what matters for collision-free spacing is the rendered width,
		# which is what SPREAD_MIN/MAX above are calibrated for.
		var bottom_center := Vector2(anchor_x + x_offset, anchor_y + y_offset)
		var top_left := bottom_center - Vector2(CARD_W * 0.5, CARD_H)
		card.set_hand_target(top_left, rot, REST_SCALE)


func _discard_hand() -> void:
	var to_keep: Array[Control] = []
	for card in _hand:
		if card.has_keyword("retain"):
			to_keep.append(card)
		else:
			_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))
			_animate_card_to_discard(card)
	_hand = to_keep
	# Reset temp buffs on every creature, both rows, both sides.
	for c in _all_creatures_both_sides():
		c.temp_atk_buff = 0
		c.has_attacked_this_turn = false
		c.has_flooped_this_turn = false
		c.update_stat_display()


func _animate_card_to_discard(card: Control) -> void:
	# End-of-turn sweep: each discarded card flies to the discard pile (bottom-
	# right) while shrinking + fading, then frees. Cards are already out of
	# _hand, so _layout_hand won't fight this tween.
	if not is_instance_valid(card):
		return
	if _hand_container == null:
		card.queue_free()
		return
	var vp := get_viewport_rect().size
	var disc_screen := Vector2(vp.x - 100.0, 291.0)
	var target_local := disc_screen - _hand_container.global_position - Vector2(96.0, 128.0)
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position", target_local, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "rotation", randf_range(-0.6, 0.6), 0.32)
	tw.tween_property(card, "scale", Vector2(0.45, 0.45), 0.32)
	tw.tween_property(card, "modulate:a", 0.0, 0.32).set_delay(0.08)
	tw.chain().tween_callback(card.queue_free)


# =====================================================================
#  PUBLIC API (used by KeywordEffects)
# =====================================================================

func damage_player_hero(amount: int) -> void:
	player_hp -= amount
	_face_damage_taken_this_fight += amount
	if _has_relic("bloodstone_relic"):
		for c in _all_player_creatures():
			c.temp_atk_buff += 1
			c.update_stat_display()
	_on_hero_damaged(amount)
	screen_shake(clampf(amount * 3.0, 6.0, 25.0))
	screen_flash(Color(0.8, 0.1, 0.05, 0.25), 0.2)
	if _player_hp_label != null and amount > 0:
		spawn_floating_number(_player_hp_label.get_global_rect().get_center(),
			"-%d" % amount, Color(1.0, 0.3, 0.25), true)
	if AudioBank != null and amount > 0:
		AudioBank.play_sfx("hit_hero")
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	enemy_hp -= amount
	screen_shake(clampf(amount * 2.0, 4.0, 15.0))
	if _enemy_hp_label != null and amount > 0:
		spawn_floating_number(_enemy_hp_label.get_global_rect().get_center(),
			"-%d" % amount, Color(1.0, 0.45, 0.2), true)
	if AudioBank != null and amount > 0:
		AudioBank.play_sfx("hit_hero")
	_check_boss_phase_transition()
	_update_hud()


func get_opposing_card(lane_idx: int, from_enemy_perspective: bool) -> Control:
	# 4x4: targeting "the creature across from you" prefers front, falls through to back.
	# Most callers (on-enter damage, floops, spells) want the front-row defender;
	# if the front column is empty, they hit whatever's in the back of that column.
	var opp_is_enemy = not from_enemy_perspective
	return _get_creature_in_column(opp_is_enemy, lane_idx)


func _has_relic(id: String) -> bool:
	# Cached lookup — _relic_set is rebuilt at combat start and on relic acquisition.
	# Falls back to RunState on cache miss so this never breaks after live mutation.
	if _relic_set.is_empty():
		_rebuild_relic_cache()
	return _relic_set.has(id)


func _rebuild_relic_cache() -> void:
	_relic_set.clear()
	for rid in RunState.relics:
		_relic_set[rid] = true


func _apply_start_of_round_relics() -> void:
	# Rear Guard Charm: back-row friendlies regen 1 HP each round.
	if _has_relic("rear_guard_charm"):
		for c in _player_back:
			if c != null:
				c.current_hp = mini(c.current_hp + 1, c.card_data.hp)
				c.update_stat_display()


func summon_token(atk: int, hp: int, lane_idx: int, is_enemy: bool, row: int = ROW_FRONT) -> void:
	# 4x4: if the requested slot is taken, fall through to the other row of the same column.
	var field = _row_array(is_enemy, row)
	if field[lane_idx] != null:
		var other_row = ROW_BACK if row == ROW_FRONT else ROW_FRONT
		var alt = _row_array(is_enemy, other_row)
		if alt[lane_idx] != null:
			return
		row = other_row
		field = alt
	var token_hp = hp
	if not is_enemy and _has_relic("conscription_relic"):
		token_hp += RelicDB.get_relic("conscription_relic").get("value", 1)
	var card = CARD_SCENE.instantiate()
	card.card_id = "token_%d_%d" % [atk, token_hp]
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.compact_mode = true
	card.card_data = {"id": card.card_id, "name": "Token", "type": "creature",
		"cost": 0, "atk": atk, "hp": token_hp, "keywords": [], "rarity": "enemy", "desc": ""}
	card.current_atk = atk
	card.current_hp = token_hp
	card.current_lane = lane_idx
	card.current_row = row
	field[lane_idx] = card
	var slot = _slot_array(is_enemy, row)[lane_idx]
	_slot_set_card(slot, card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	if not is_enemy and card.has_floop():
		card.floop_clicked.connect(_on_floop_clicked.bind(card))
	card.update_floop_display()


func _return_dead_to_hand(lane_idx: int) -> void:
	if _grave_pact_active and _last_dead_creature_id != "":
		_player_draw_pile.push_front(_last_dead_creature_id)
		draw_one()
		_grave_pact_active = false


func _on_hero_damaged(amount: int) -> void:
	if player_hp <= 0 and _has_relic("phoenix_heart") and not RunState.phoenix_heart_consumed:
		RunState.phoenix_heart_consumed = true
		player_hp = 1


# =====================================================================
#  GAME OVER
# =====================================================================

func _debug_auto_win() -> void:
	# Debug hotkey (F1): instant-win the current combat. Routes through the
	# normal victory path so gold rewards, relic hooks, and scene transition
	# all fire exactly as if the player had killed the last enemy.
	enemy_hp = 0
	_info_label.text = "[debug] auto-win"
	_check_game_over()


func _check_game_over() -> void:
	if player_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "DEFEAT"
		_phase_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
		RunState.hero_hp = 0
		if AudioBank != null:
			AudioBank.play_sfx("defeat")
		get_tree().create_timer(1.5).timeout.connect(func():
			RunState.end_run(false)
			GameTheme.fade_out_then_change_scene(self, GAMEOVER_SCENE, 0.5)
		)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "VICTORY!"
		_phase_label.add_theme_color_override("font_color", Color(0.30, 0.92, 0.40))
		if AudioBank != null:
			AudioBank.play_sfx("victory")
		RunState.hero_hp = max(player_hp, 1)
		# Vulture's Feast
		if _has_relic("vultures_feast"):
			var heal = mini(_friendly_deaths_this_fight, 5)
			RunState.heal_hero(heal)
		# Coin Purse
		if _has_relic("coin_purse"):
			RunState.gain_gold(10)
		# Thief's Gloves
		if _has_relic("thiefs_gloves") and player_hp == _starting_hp:
			RunState.gain_gold(5)
		# Gold reward
		var node_type = RunState.current_node_type
		match node_type:
			"combat": RunState.gain_gold(25)
			"elite": RunState.gain_gold(40)
			"boss": RunState.gain_gold(40)

		if node_type == "boss":
			# Post-boss heal: 75% of missing HP
			var missing = RunState.hero_max_hp - RunState.hero_hp
			RunState.heal_hero(int(missing * 0.75))
			get_tree().create_timer(2.0).timeout.connect(func():
				if RunState.is_final_boss():
					RunState.end_run(true)
					GameTheme.fade_out_then_change_scene(self, GAMEOVER_SCENE, 0.5)
				else:
					RunState.advance_act()
					GameTheme.fade_out_then_change_scene(self, REWARD_SCENE, 0.35)
			)
		else:
			get_tree().create_timer(1.0).timeout.connect(func():
				GameTheme.fade_out_then_change_scene(self, REWARD_SCENE, 0.35)
			)


# =====================================================================
#  INTENT SYSTEM
# =====================================================================

func _assign_intents() -> void:
	## Assigns an intent to each enemy creature on the field based on their
	## intent cycle. 4x4: scans both rows. Default ATK still gets a visible
	## damage badge so the player can always read what's coming.
	for card in _all_enemy_creatures():
		var intents = card.card_data.get("intents", [])
		if intents.is_empty():
			card.set_meta("current_intent", "ATK")
			_update_intent_display(card, "ATK")
			continue
		# Get current cycle position (stored on card, incremented each round)
		var cycle_pos = card.get_meta("intent_cycle_pos", 0)
		var intent = intents[cycle_pos % intents.size()]
		# Anti-repetition: no same non-ATK intent more than 2 rounds in a row
		var consecutive = card.get_meta("intent_consecutive", 0)
		var last_intent = card.get_meta("last_intent", "ATK")
		if intent != "ATK" and intent == last_intent:
			consecutive += 1
			if consecutive >= 2:
				intent = "ATK"
				consecutive = 0
		else:
			consecutive = 0
		card.set_meta("current_intent", intent)
		card.set_meta("last_intent", intent)
		card.set_meta("intent_consecutive", consecutive)
		card.set_meta("intent_cycle_pos", cycle_pos + 1)
		# Update visual display
		_update_intent_display(card, intent)
	_redraw_intent_arrows()


func _clear_intent_arrows() -> void:
	for line in _intent_arrow_lines:
		if is_instance_valid(line):
			line.queue_free()
	_intent_arrow_lines.clear()


func _redraw_intent_arrows() -> void:
	# Thin line from each attacking enemy to the lane it will hit so the player
	# can read targeting at a glance on the 4x4 board. Cleared when combat starts.
	_clear_intent_arrows()
	if _hud_layer == null:
		return
	for enemy in _all_enemy_creatures():
		var intent: String = enemy.get_meta("current_intent", "ATK")
		if intent in ["HEAL", "RETREAT", "SUMMON", "ABILITY"]:
			continue
		if not enemy.can_attack():
			continue
		var pos = _find_creature_position(enemy)
		if pos.is_empty():
			continue
		var lane_idx: int = pos.lane
		var target_pos: Vector2
		var pf = _row_array(false, ROW_FRONT)[lane_idx]
		var pb = _row_array(false, ROW_BACK)[lane_idx]
		if pf != null and pf.current_hp > 0:
			target_pos = pf.get_global_rect().get_center()
		elif pb != null and pb.current_hp > 0:
			target_pos = pb.get_global_rect().get_center()
		elif _player_hp_label != null:
			target_pos = _player_hp_label.get_global_rect().get_center()
		else:
			continue
		var start_pos: Vector2 = enemy.get_global_rect().get_center()
		start_pos.y += enemy.size.y * enemy.scale.y * 0.40
		var line := Line2D.new()
		line.add_point(start_pos)
		line.add_point(target_pos)
		line.width = 2.0
		line.default_color = _intent_arrow_color(intent)
		line.z_index = 5
		line.antialiased = true
		_hud_layer.add_child(line)
		_intent_arrow_lines.append(line)


func _intent_arrow_color(intent: String) -> Color:
	match intent:
		"CHARGE": return Color(1.0, 0.45, 0.20, 0.50)
		"ENRAGE": return Color(1.0, 0.30, 0.10, 0.55)
		"GUARD": return Color(0.50, 0.78, 1.0, 0.40)
		"RALLY": return Color(1.0, 0.88, 0.30, 0.40)
	return Color(0.95, 0.40, 0.30, 0.45)


func _update_intent_display(card: Control, intent: String) -> void:
	## Renders an intent badge above every enemy creature so the player can
	## always read "what is this thing about to do." STS shows attack damage
	## for ATK; everything else gets the same colored chip.
	var label_text: String = intent
	if intent == "ATK" or intent == "":
		# Default attack shows damage instead of the word — much more useful.
		var dmg: int = card.effective_atk()
		label_text = "⚔ %d" % dmg
	var lbl: Label
	if card.has_meta("intent_label") and is_instance_valid(card.get_meta("intent_label")):
		lbl = card.get_meta("intent_label")
	else:
		lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.anchor_left = 0.0
		lbl.anchor_right = 1.0
		lbl.anchor_top = 0.0
		lbl.anchor_bottom = 0.0
		lbl.offset_top = -16
		lbl.offset_bottom = 0
		lbl.z_index = 5
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lbl)
		card.set_meta("intent_label", lbl)
	var color := Color(0.95, 0.40, 0.30)  # default ATK red
	match intent:
		"CHARGE": color = Color(1.0, 0.45, 0.20)
		"GUARD": color = Color(0.50, 0.78, 1.0)
		"RALLY": color = Color(1.0, 0.88, 0.30)
		"HEAL": color = Color(0.40, 0.95, 0.45)
		"ENRAGE": color = Color(1.0, 0.40, 0.10)
		"RETREAT": color = Color(0.75, 0.75, 0.75)
		"SUMMON": color = Color(0.80, 0.55, 1.0)
		"ABILITY": color = Color(1.0, 0.85, 0.10)
	lbl.add_theme_color_override("font_color", color)
	lbl.text = label_text


func _resolve_intents() -> void:
	## Resolves all non-ATK intents for enemy creatures BEFORE combat.
	## 4x4: iterates both rows. Lane index drives same-row adjacency for RALLY/SUMMON.
	for row in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(true, row)
		for lane_idx in range(LANES_PER_ROW):
			var card = arr[lane_idx]
			if card == null:
				continue
			var intent = card.get_meta("current_intent", "ATK")
			match intent:
				"ATK":
					pass
				"CHARGE":
					card.temp_atk_buff += 1
				"GUARD":
					if "armored" not in card.card_data.keywords:
						card.card_data.keywords.append("armored")
						card.set_meta("temp_armored", true)
				"RALLY":
					# Same-row adjacency buff.
					for adj_card in _adjacent_in_row(true, row, lane_idx):
						adj_card.temp_atk_buff += 1
						adj_card.update_stat_display()
				"HEAL":
					card.current_hp = mini(card.current_hp + 3, card.card_data.hp)
					card.has_attacked_this_turn = true
					card.update_stat_display()
				"ENRAGE":
					card.current_atk += 2
					card.set_meta("enrage_vulnerable", true)
					card.update_stat_display()
				"RETREAT":
					card.set_meta("will_retreat", true)
				"SUMMON":
					# Adjacent empty in the same row.
					var adj_empty: Array[int] = []
					for adj in [lane_idx - 1, lane_idx + 1]:
						if adj >= 0 and adj < LANES_PER_ROW and arr[adj] == null:
							adj_empty.append(adj)
					if adj_empty.size() > 0:
						var target_lane = adj_empty[randi() % adj_empty.size()]
						if not _reinforcement.is_empty():
							var data = _reinforcement.duplicate(true)
							data.id = "summon_%d" % randi()
							_place_enemy_card(data, target_lane, row)
					card.has_attacked_this_turn = true
				"ABILITY":
					_resolve_enemy_ability(card, lane_idx)
					card.has_attacked_this_turn = true


func _resolve_enemy_ability(card: Control, lane_idx: int) -> void:
	## Resolves the creature-specific ability telegraphed by ABILITY intent.
	## 4x4: opposing-column lookups front-preferred; "all enemy" iterates both rows.
	var ability = card.card_data.get("ability", {})
	var ability_type = ability.get("type", "")
	match ability_type:
		"warcry":
			for c in _all_enemy_creatures():
				c.current_atk += ability.get("value", 1)
				c.update_stat_display()
		"steal_atk":
			var opp = _get_creature_in_column(false, lane_idx)
			if opp != null and opp.current_atk > 0:
				var steal = ability.get("value", 1)
				opp.current_atk = maxi(0, opp.current_atk - steal)
				card.current_atk += steal
				opp.update_stat_display()
				card.update_stat_display()
		"curse":
			_player_discard_pile.append("curse")
		"devour":
			# Same-row adjacency.
			var pos = _find_creature_position(card)
			if pos.is_empty():
				return
			var row = pos.row
			var arr = _row_array(true, row)
			var adj: Array[int] = []
			if lane_idx > 0 and arr[lane_idx - 1] != null:
				adj.append(lane_idx - 1)
			if lane_idx < LANES_PER_ROW - 1 and arr[lane_idx + 1] != null:
				adj.append(lane_idx + 1)
			if adj.size() > 0:
				var target_lane = adj[randi() % adj.size()]
				var victim = arr[target_lane]
				if victim != null:
					card.current_atk += victim.current_atk
					card.current_hp += victim.current_hp
					card.card_data.hp += victim.current_hp
					victim.take_damage(999)
					arr[target_lane] = null
					card.update_stat_display()
		"terrify":
			var opp = _get_creature_in_column(false, lane_idx)
			if opp != null:
				var opp_pos = _find_creature_position(opp)
				if not opp_pos.is_empty():
					var opp_row = opp_pos.row
					var opp_arr = _row_array(false, opp_row)
					var empty_lanes: Array[int] = []
					for i in range(LANES_PER_ROW):
						if i != lane_idx and opp_arr[i] == null:
							empty_lanes.append(i)
					if empty_lanes.size() > 0:
						var new_lane = empty_lanes[randi() % empty_lanes.size()]
						opp_arr[lane_idx] = null
						_place_card_in_slot(opp, new_lane, opp_row)
						_restore_slot_label(_slot_array(false, opp_row)[lane_idx], lane_idx)
		"hex":
			var opp = _get_creature_in_column(false, lane_idx)
			if opp != null:
				opp.card_data.keywords.clear()
				opp.update_stat_display()
		"mark":
			var opp = _get_creature_in_column(false, lane_idx)
			if opp != null:
				opp.set_meta("marked", true)
		"resurrect":
			if not _last_dead_enemy_data.is_empty():
				var slot = _find_empty_enemy_slot()
				if not slot.is_empty():
					var data = _last_dead_enemy_data.duplicate(true)
					data.atk = 1
					data.hp = 1
					data.id = "resurrected_%d" % randi()
					_place_enemy_card(data, slot.lane, slot.row)
		"heal_all":
			var value = ability.get("value", 2)
			for c in _all_enemy_creatures():
				c.current_hp = mini(c.current_hp + value, c.card_data.hp)
				c.update_stat_display()
		"drain":
			var opp = _get_creature_in_column(false, lane_idx)
			if opp != null:
				opp.take_damage(2)
			card.current_hp = mini(card.current_hp + 2, card.card_data.hp)
			card.update_stat_display()


# =====================================================================
#  BOSS PHASE SYSTEM
# =====================================================================

func _check_boss_phase_transition() -> void:
	## Check if enemy HP has dropped below a phase threshold.
	## If so, transition to the next phase.
	if _boss_phases.is_empty():
		return
	# Find current phase based on HP thresholds
	var new_phase := 0
	for i in range(_boss_phases.size()):
		if enemy_hp <= _boss_phases[i].threshold:
			new_phase = i + 1
	if new_phase > _boss_current_phase and new_phase < _boss_phases.size():
		_boss_current_phase = new_phase
		var phase_data = _boss_phases[new_phase]
		_encounter_passive = phase_data.passive_id
		if phase_data.has("transition_msg"):
			_show_info(phase_data.transition_msg)
		if phase_data.has("transition_effect"):
			_execute_phase_transition(phase_data.transition_effect)
		for c in _all_enemy_creatures():
			c.set_meta("intent_cycle_pos", 0)


func _execute_phase_transition(effect: Dictionary) -> void:
	## Executes a boss phase transition effect.
	match effect.get("type", ""):
		"summon":
			var slot = _find_empty_enemy_slot()
			if not slot.is_empty():
				var data = {
					"id": "phase_summon_%d" % randi(),
					"name": effect.get("name", "Minion"),
					"type": "creature", "cost": 0,
					"atk": effect.get("atk", 2), "hp": effect.get("hp", 3),
					"rarity": "enemy",
					"keywords": effect.get("kw", []).duplicate(),
					"desc": "",
				}
				_place_enemy_card(data, slot.lane, slot.row)
		"summon_multiple":
			var count = effect.get("count", 2)
			for _i in range(count):
				var slot2 = _find_empty_enemy_slot()
				if slot2.is_empty():
					break
				var data = {
					"id": "phase_summon_%d" % randi(),
					"name": effect.get("name", "Minion"),
					"type": "creature", "cost": 0,
					"atk": effect.get("atk", 2), "hp": effect.get("hp", 3),
					"rarity": "enemy", "keywords": [], "desc": "",
				}
				_place_enemy_card(data, slot2.lane, slot2.row)
		"heal_all_enemies":
			var value = effect.get("value", 2)
			for c in _all_enemy_creatures():
				c.current_hp = mini(c.current_hp + value, c.card_data.hp)
				c.update_stat_display()
		"buff_all_enemies_atk":
			var value = effect.get("value", 1)
			for c in _all_enemy_creatures():
				c.current_atk += value
				c.update_stat_display()
		"debuff_all_player_atk":
			var value = effect.get("value", 1)
			for c in _all_player_creatures():
				c.current_atk = maxi(0, c.current_atk - value)
				c.update_stat_display()


# =====================================================================
#  REACTIVE PASSIVES
# =====================================================================

func _dispatch_reactive(trigger: String, source_card: Control, _lane_idx: int) -> void:
	## Dispatches reactive passive effects based on player actions.
	if _reactive_passive.is_empty():
		return
	if _reactive_passive.get("trigger", "") != trigger:
		return
	var effect = _reactive_passive.get("effect", "")
	match effect:
		"buff_chieftain_atk":
			for c in _all_enemy_creatures():
				if c.card_data.get("name", "") == "Chieftain":
					c.current_atk += 1
					c.update_stat_display()
					break
		"double_on_death":
			# Necromancer Tower: re-fire the dying card's on_death once more.
			# Run the effect directly (not via dispatch_on_death) to avoid the
			# reactive loop calling itself.
			if source_card != null and is_instance_valid(source_card):
				var data: Dictionary = source_card.card_data
				if not data.is_empty() and data.has("on_death"):
					KeywordEffects._run_on_death(data.on_death, _lane_idx, true, self)
		"face_damage":
			damage_player_hero(_reactive_passive.get("value", 2))
		"damage_flooper":
			var value = _reactive_passive.get("value", 1)
			if source_card != null and is_instance_valid(source_card):
				source_card.take_damage(value)
		"summon_puppet":
			_summon_enemy_token(_reactive_passive.get("atk", 2), _reactive_passive.get("hp", 2))
		"heal_all_enemies":
			var value = _reactive_passive.get("value", 1)
			for c in _all_enemy_creatures():
				c.current_hp = mini(c.current_hp + value, c.card_data.hp)
				c.update_stat_display()
		"face_damage_per_draw":
			damage_player_hero(1)
		"summon_shard":
			var atk = _reactive_passive.get("atk", 1)
			var hp = _reactive_passive.get("hp", 1)
			_summon_enemy_token(atk, hp)
		"exile_card":
			if not _player_draw_pile.is_empty():
				_player_draw_pile.pop_front()


# =====================================================================
#  ESCALATION MECHANICS
# =====================================================================

func _check_escalation() -> void:
	## Checks if escalation timer has triggered and applies buffs.
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")

	match enc_type:
		"combat":
			# After round 8: place 2 reinforcements per round
			# After round 12: reinforcements gain +1/+1
			if round_number >= 12:
				_reinforcement["atk"] = _reinforcement.get("atk", 1) + 1
				_reinforcement["hp"] = _reinforcement.get("hp", 1) + 1
		"elite":
			if round_number >= ESCALATION_ELITE_BUFF_ROUND:
				for c in _all_enemy_creatures():
					c.current_atk += 1
					c.update_stat_display()
		"boss":
			# Boss escalation handled by phase transitions
			# Auto-transition if stalled 10+ rounds in Phase 1
			if round_number >= 10 and _boss_current_phase == 0 and not _boss_phases.is_empty():
				_boss_current_phase = 1
				var phase_data = _boss_phases[1] if _boss_phases.size() > 1 else _boss_phases[0]
				_encounter_passive = phase_data.passive_id
				if phase_data.has("transition_msg"):
					_show_info(phase_data.transition_msg)


# =====================================================================
#  POST-COMBAT CLEANUP (temp effects from intents and floops)
# =====================================================================

func _post_combat_cleanup() -> void:
	## Cleans up temporary effects from intents and floops at end of round.
	## 4x4: iterate both rows on both sides.
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var field = _row_array(is_enemy, row)
			for lane_idx in range(LANES_PER_ROW):
				var card = field[lane_idx]
				if card == null:
					continue
				if card.get_meta("temp_armored", false):
					card.card_data.keywords.erase("armored")
					card.remove_meta("temp_armored")
				if card.get_meta("temp_thorns", false):
					card.card_data.keywords.erase("thorns")
					card.remove_meta("temp_thorns")
				if card.has_meta("bonus_thorns"):
					card.remove_meta("bonus_thorns")
				# stunned is now on card.state; tick_end_of_round handles it.
				card.state.tick_end_of_round()
				if card.has_meta("redirecting"):
					card.remove_meta("redirecting")
				if card.has_meta("challenge_any_lane"):
					card.remove_meta("challenge_any_lane")
				if card.has_meta("swap_atk_original"):
					card.current_atk = card.get_meta("swap_atk_original")
					card.remove_meta("swap_atk_original")
					card.update_stat_display()
				if card.has_meta("is_copy"):
					card.remove_meta("is_copy")
				if card.has_meta("enrage_vulnerable"):
					card.remove_meta("enrage_vulnerable")
				if card.has_meta("marked"):
					card.remove_meta("marked")
				if card.get_meta("will_retreat", false):
					card.remove_meta("will_retreat")
					_execute_retreat(card, lane_idx, row, is_enemy)


func _execute_retreat(card: Control, lane_idx: int, row: int, is_enemy: bool) -> void:
	## Moves a creature to a random different lane in the same row (RETREAT intent).
	var field = _row_array(is_enemy, row)
	var slots = _slot_array(is_enemy, row)
	var empty_lanes: Array[int] = []
	for i in range(LANES_PER_ROW):
		if i != lane_idx and field[i] == null:
			empty_lanes.append(i)
	if empty_lanes.size() > 0:
		var new_lane = empty_lanes[randi() % empty_lanes.size()]
		field[lane_idx] = null
		field[new_lane] = card
		card.current_lane = new_lane
		_slot_take_card(slots[lane_idx], card)
		_slot_set_card(slots[new_lane], card)


# =====================================================================
#  ENCOUNTER PASSIVES
# =====================================================================

func _dispatch_passive_start_of_round() -> void:
	match _encounter_passive:
		"orc_random_buff":
			_buff_random_enemy_atk(1)
		"cultist_buff":
			var target = _random_enemy_creature()
			if target != null:
				target.current_atk += 1
				target.current_hp = mini(target.current_hp + 1, target.card_data.hp + 1)
				target.card_data.hp += 1
				target.update_stat_display()
		"forge_burn_all":
			for c in _all_creatures_both_sides():
				c.take_damage(1)
		"hollow_king_snipe":
			var highest = _highest_atk_player_creature()
			if highest != null:
				highest.take_damage(3)
		"void_exile":
			if not _player_draw_pile.is_empty():
				_player_draw_pile.pop_front()
		"nexus_rotation":
			var cycle = (round_number - 1) % PASSIVE_HEAL_INTERVAL
			match cycle:
				0:
					for c in _all_enemy_creatures():
						c.current_atk += 1
						c.update_stat_display()
				1:
					for c in _all_enemy_creatures():
						c.current_hp = mini(c.current_hp + 2, c.card_data.hp)
						c.update_stat_display()
				2:
					pass  # Thorns handled in combat resolution
		"dragon_lair_periodic":
			if round_number > 1 and (round_number - 1) % PASSIVE_HEAL_INTERVAL == 0:
				for c in _all_player_creatures():
					c.take_damage(3)
		"devil_cycle":
			var cycle = (round_number - 1) % PASSIVE_HEAL_INTERVAL
			match cycle:
				0:
					damage_player_hero(2)
				1:
					enemy_hp = mini(enemy_hp + _all_enemy_creatures().size(), enemy_max_hp)
				2:
					var highest = _highest_atk_player_creature()
					if highest != null:
						highest.take_damage(3)
		"puppet_keyword_copy":
			var source = _highest_atk_player_creature()
			var target = _random_enemy_creature()
			if source != null and target != null:
				for kw in source.card_data.get("keywords", []):
					if not target.card_data.keywords.has(kw):
						target.card_data.keywords.append(kw)
				target.update_stat_display()
		# Phase 2 passives
		"hollow_king_phase2":
			# Two highest-ATK player creatures take 3 damage (any row).
			var sorted_creatures: Array = _all_player_creatures()
			sorted_creatures.sort_custom(func(a, b): return a.current_atk > b.current_atk)
			for i in range(mini(2, sorted_creatures.size())):
				sorted_creatures[i].take_damage(3)
			_player_discard_pile.append("curse")
		"dragon_lord_phase2":
			for c in _all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()
		"collector_phase2":
			pass  # Handled in creature play hook
		"devil_phase2":
			var cycle = (round_number - 1) % PASSIVE_HEAL_INTERVAL
			match cycle:
				0: damage_player_hero(4)
				1:
					enemy_hp = mini(enemy_hp + _all_enemy_creatures().size() * 2, enemy_max_hp)
				2:
					var highest = _highest_atk_player_creature()
					if highest != null:
						highest.take_damage(6)
		"devil_phase3":
			damage_player_hero(3)
			_summon_enemy_token(3, 3)
			for c in _all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()


func _dispatch_passive_end_of_round() -> void:
	match _encounter_passive:
		"iron_warden_burn":
			damage_player_hero(2)
		"iron_warden_siege":
			damage_player_hero(3)
			for c in _all_enemy_creatures():
				if "armored" not in c.card_data.keywords:
					c.card_data.keywords.append("armored")
		"mushroom_heal":
			for c in _all_enemy_creatures():
				c.current_hp = mini(c.current_hp + 1, c.card_data.hp)
				c.update_stat_display()
		"executioner_face":
			var highest = _highest_atk_enemy_creature()
			if highest != null:
				damage_player_hero(highest.effective_atk())
		"crone_drip":
			_player_discard_pile.append("curse")
		"crone_lash":
			_player_discard_pile.append("curse")
			damage_player_hero(_curses_in_deck())
		"crone_doom":
			_player_discard_pile.append("curse")
			_player_discard_pile.append("curse")
			damage_player_hero(_curses_in_deck())
			_summon_enemy_token_with_keyword(2, 3, "swift")
		"tide_swell":
			if _all_enemy_creatures().size() < 4:
				_summon_enemy_token(2, 3)
		"tide_surge":
			if _all_enemy_creatures().size() < 4:
				_summon_enemy_token(2, 3)
			for c in _all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()
		"tide_drown":
			if _all_enemy_creatures().size() < 4:
				_summon_enemy_token(2, 3)
			for c in _all_enemy_creatures():
				c.current_atk += 1
				c.update_stat_display()
			var weakest := _lowest_hp_player_creature()
			if weakest != null:
				weakest.take_damage(3)


func _curses_in_deck() -> int:
	var n := 0
	for entry in _player_draw_pile:
		if _entry_id(entry) == "curse":
			n += 1
	for entry in _player_discard_pile:
		if _entry_id(entry) == "curse":
			n += 1
	for c in _hand:
		if c.card_id == "curse":
			n += 1
	return n


func _lowest_hp_player_creature() -> Control:
	var creatures = _all_player_creatures()
	if creatures.is_empty():
		return null
	var best: Control = creatures[0]
	for c in creatures:
		if c.current_hp < best.current_hp:
			best = c
	return best


func _dispatch_encounter_on_enemy_death(lane_idx: int) -> void:
	# 4x4: lane_idx is the column. Wolf-pack revenge buffs same-row neighbors
	# in the front row, since that's where most fights take place; if you want
	# back-row revenge too, also buff back-row adjacents.
	match _encounter_passive:
		"wolf_pack_revenge":
			for row in [ROW_FRONT, ROW_BACK]:
				for adj_card in _adjacent_in_row(true, row, lane_idx):
					adj_card.temp_atk_buff += 1
					adj_card.update_stat_display()
		"necro_death_summon":
			_summon_enemy_token(1, 2)
		"crypt_ghost":
			_summon_enemy_token_with_keyword(1, 1, "swift")
		"mirror_instant_place":
			pass  # handled in player death below


func _dispatch_encounter_on_player_death(_lane_idx: int) -> void:
	match _encounter_passive:
		"mirror_instant_place":
			_enemy_place_creatures()


func _dispatch_encounter_on_enter(_data: Dictionary, _lane_idx: int) -> void:
	if _encounter_passive == "bandit_mana_steal":
		_bonus_mana_next_turn = maxi(0, _bonus_mana_next_turn - 1)


func _has_encounter_passive_keyword(card: Control, keyword: String) -> bool:
	match _encounter_passive:
		"dragon_lord_piercing":
			return keyword == "piercing"
		"dragon_lord_phase2":
			return keyword == "piercing"
		"swamp_thorns":
			return keyword == "thorns"
		"merc_piercing":
			if keyword == "piercing" and card != null:
				return card.effective_atk() >= 4
		"stone_armor":
			if keyword == "armored" and card != null:
				return card.card_data.get("keywords", []).has("armored")
		"harpy_swift_face":
			return false
		"nexus_rotation":
			if keyword == "thorns":
				return (round_number - 1) % 3 == 2
	return false


func _buff_random_enemy_atk(amount: int) -> void:
	var target = _random_enemy_creature()
	if target != null:
		target.current_atk += amount
		target.update_stat_display()


func _random_enemy_creature() -> Control:
	var enemies = _all_enemy_creatures()
	if enemies.is_empty():
		return null
	return enemies[randi() % enemies.size()]


func _highest_atk_player_creature() -> Control:
	var best: Control = null
	var best_atk := -1
	for c in _all_player_creatures():
		var atk = c.effective_atk()
		if atk > best_atk:
			best_atk = atk
			best = c
	return best


func _highest_atk_enemy_creature() -> Control:
	var best: Control = null
	var best_atk := -1
	for c in _all_enemy_creatures():
		var atk = c.effective_atk()
		if atk > best_atk:
			best_atk = atk
			best = c
	return best


func _find_empty_enemy_slot() -> Dictionary:
	# 4x4: fill front-row first, then back-row. Returns {row, lane} or {}.
	for row in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(true, row)
		var empties: Array[int] = []
		for i in range(LANES_PER_ROW):
			if arr[i] == null:
				empties.append(i)
		if not empties.is_empty():
			return {"row": row, "lane": empties[randi() % empties.size()]}
	return {}


func _pick_empty_for_summon(is_enemy: bool, preferred_row: int) -> Dictionary:
	# Prefer the requested row; fall through to the other row.
	var other = ROW_BACK if preferred_row == ROW_FRONT else ROW_FRONT
	for row in [preferred_row, other]:
		var arr = _row_array(is_enemy, row)
		var empties: Array[int] = []
		for i in range(LANES_PER_ROW):
			if arr[i] == null:
				empties.append(i)
		if not empties.is_empty():
			return {"row": row, "lane": empties[randi() % empties.size()]}
	return {}


func _summon_enemy_token(atk: int, hp: int) -> void:
	var slot = _find_empty_enemy_slot()
	if slot.is_empty():
		return
	summon_token(atk, hp, slot.lane, true, slot.row)


func _summon_enemy_token_with_keyword(atk: int, hp: int, keyword: String) -> void:
	var slot = _find_empty_enemy_slot()
	if slot.is_empty():
		return
	var data = {
		"id": "token_%s" % keyword, "name": "Ghost" if keyword == "swift" else "Token",
		"type": "creature", "cost": 0, "atk": atk, "hp": hp,
		"rarity": "token", "keywords": [keyword], "desc": "",
	}
	_place_enemy_card(data, slot.lane, slot.row)


# =====================================================================
#  BOARD LAYOUT
# =====================================================================

func _build_board() -> void:
	# Layout strategy (anchor-based, no competing VBox shares):
	#
	#   ┌──────────── top HUD (Combat._build_hud) — anchored to top ──────────┐
	#   │                                                                     │
	#   │ enemy_portrait  ┌─ board container (fills middle) ──┐                │
	#   │   (left edge)   │  enemy back row                   │                │
	#   │                 │  enemy front row                  │                │
	#   │                 │  ─── midline ─────────────────────│                │
	#   │ player_portrait │  player front row                 │                │
	#   │   (left edge)   │  player back row                  │                │
	#   │                 └───────────────────────────────────┘  [End Turn]    │
	#   ├────── HUD strip (HP, mana, deck/discard) anchored above hand ───────┤
	#   └────── hand container (anchored to bottom edge, fixed height) ───────┘
	_board_container = Control.new()
	_board_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_board_container)

	_board_bg = ColorRect.new()
	_board_bg.color = Color(0, 0, 0, 0.0)
	_board_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_container.add_child(_board_bg)

	# ── Hand container: bottom-anchored, fixed height. Always visible. ──
	# Plain Control (not HBoxContainer) — cards are positioned manually by
	# _layout_hand() to produce a slight Hearthstone-style fan: centred,
	# subtle outward rotation, parabolic Y-drop at the edges. Spans from
	# past the left info column out to the right margin (leaving room for
	# the End Turn button stack); fixed 280 px tall so the highest point
	# of a hovered card (which scales 1.15x past the top edge) doesn't get
	# clipped by the board zone above.
	_hand_container = Control.new()
	_hand_container.anchor_left = 0.0
	_hand_container.anchor_right = 1.0
	# Pull hand inward so it doesn't sit on top of the player banner + mana
	# orb (left edge ends ~x=344) or the end-turn / pile column (right). The
	# centered hand fans cleanly in the gap between the bottom-corner UI.
	_hand_container.offset_left = 360
	_hand_container.offset_right = -240
	_hand_container.anchor_top = 1.0
	_hand_container.anchor_bottom = 1.0
	# Hand sits on top of the board's bottom edge (board_zone now goes down to
	# offset_bottom = -80). The hand's top edge at -210 overlaps the board's
	# bottom ~130px — cards fan ON TOP of the field, the way Hearthstone /
	# Cross Blitz layer them, instead of in a separate stripe below.
	_hand_container.offset_top = -210
	_hand_container.offset_bottom = -10
	_hand_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Re-layout on resize so window resize / scaling reflows the fan.
	_hand_container.resized.connect(_layout_hand)
	# Any time a card leaves the hand (played, discarded, exiled, exhausted)
	# the remaining cards need to re-fan. _hand.erase() is called BEFORE
	# remove_child() everywhere, so by the time this signal fires _hand is
	# already trimmed; defer one frame so the removed node is fully out of
	# the tree before we run.
	_hand_container.child_exiting_tree.connect(
		func(_n): call_deferred("_layout_hand"))
	# Hand lives in its OWN CanvasLayer at layer=20 — above the HUD (layer=12)
	# so cards draw over the board frame edge, encounter scroll, relic strip,
	# and all other UI. The card drag system uses screen-space global_position
	# which works identically inside a CanvasLayer as outside.
	_hand_layer = CanvasLayer.new()
	_hand_layer.layer = 20
	add_child(_hand_layer)
	_hand_layer.add_child(_hand_container)

	# ── Board zone: uses most of the screen between left/right columns and
	# the title strip on top. Left clears the gear+pile column (ends x=234);
	# right clears the enemy banner (starts at x=width-234). Top clears the
	# centered encounter title strip (ends y=90) plus a small margin.
	# Bottom extends ~30px behind the hand strip so hovered/raised cards
	# visibly layer over the field edge.
	var board_zone := Control.new()
	board_zone.anchor_left = 0.0
	board_zone.anchor_right = 1.0
	board_zone.anchor_top = 0.0
	board_zone.anchor_bottom = 1.0
	board_zone.offset_left = 242
	board_zone.offset_right = -242
	board_zone.offset_top = 100
	board_zone.offset_bottom = -180
	board_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_container.add_child(board_zone)

	# ── Board mat ──────────────────────────────────────────────────────────
	# A single dark, gilt-trimmed panel sitting behind every slot so the whole
	# 4 lanes × 4 rows reads as one playing field instead of "creatures floating
	# over the meadow." Added first so all slots draw on top of it.
	var mat := Panel.new()
	mat.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Heavy gilt frame around the entire 4×4 board. 8px border (was 4px) +
	# fully opaque deeper-gold trim makes the mat read as a physical table
	# instead of a thin-edged rectangle floating over the meadow background.
	# Corner radius dropped 14→8 so the silhouette is squarer, like a wooden
	# game board instead of a rounded card.
	var mat_style := StyleBoxFlat.new()
	# Heavily translucent so the background painting reads through the board —
	# previously 0.97 (essentially opaque). 0.55 gives a tinted wash that still
	# anchors the slot grid but lets the meadow art show.
	mat_style.bg_color = Color(0.07, 0.05, 0.04, 0.55)
	mat_style.border_color = Color(0.78, 0.62, 0.30, 1.0)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		mat_style.set(k, 8)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		mat_style.set(k, 8)
	mat_style.shadow_color = Color(0, 0, 0, 0.65)
	mat_style.shadow_size = 24
	mat_style.shadow_offset = Vector2(0, 8)
	mat.add_theme_stylebox_override("panel", mat_style)
	board_zone.add_child(mat)

	# Faint vertical dividers between the 4 lanes — anchored at 0.25 / 0.50 /
	# 0.75 of the mat width so they always line up with the slot columns no
	# matter the window size.
	for frac in [0.25, 0.50, 0.75]:
		var col_line := ColorRect.new()
		col_line.anchor_left = frac
		col_line.anchor_right = frac
		col_line.anchor_top = 0.0
		col_line.anchor_bottom = 1.0
		col_line.offset_left = -1
		col_line.offset_right = 1
		col_line.offset_top = 12
		col_line.offset_bottom = -12
		col_line.color = Color(0.85, 0.70, 0.34, 0.16)
		col_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat.add_child(col_line)

	# Faint horizontal dividers between the 4 rows (enemy back / front, then
	# the midline, then player front / back).
	for frac in [0.25, 0.75]:
		var row_line := ColorRect.new()
		row_line.anchor_left = 0.0
		row_line.anchor_right = 1.0
		row_line.anchor_top = frac
		row_line.anchor_bottom = frac
		row_line.offset_left = 18
		row_line.offset_right = -18
		row_line.offset_top = -1
		row_line.offset_bottom = 1
		row_line.color = Color(0.85, 0.70, 0.34, 0.14)
		row_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat.add_child(row_line)

	# Enemy half (top of board zone, dark red tint)
	var enemy_zone := PanelContainer.new()
	enemy_zone.anchor_left = 0.0
	enemy_zone.anchor_right = 1.0
	enemy_zone.anchor_top = 0.0
	enemy_zone.anchor_bottom = 0.5
	enemy_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ez_style := StyleBoxFlat.new()
	ez_style.bg_color = Color(0, 0, 0, 0)
	ez_style.border_color = Color(0.55, 0.22, 0.15, 0.0)
	ez_style.border_width_bottom = 0
	ez_style.corner_radius_top_left = 8
	ez_style.corner_radius_top_right = 8
	ez_style.content_margin_left = 4
	ez_style.content_margin_right = 4
	ez_style.content_margin_top = 2
	ez_style.content_margin_bottom = 2
	enemy_zone.add_theme_stylebox_override("panel", ez_style)
	board_zone.add_child(enemy_zone)

	var enemy_inner := VBoxContainer.new()
	enemy_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Larger separation between back & front rows so they read as distinct
	# rather than a continuous block of red squares.
	enemy_inner.add_theme_constant_override("separation", 14)
	enemy_zone.add_child(enemy_inner)

	var enemy_back_lanes := _make_row_container("BACK", Color(0.85, 0.45, 0.35, 0.35))
	enemy_inner.add_child(enemy_back_lanes)

	var enemy_front_lanes := _make_row_container("FRONT", Color(0.85, 0.55, 0.40, 0.65))
	enemy_inner.add_child(enemy_front_lanes)

	# Midline — a thick wooden beam separating enemy and player territory.
	# Was a 12px translucent gold strip; now a 28px opaque dark-walnut bar
	# with gilt edge trim (top + bottom borders). Reads as a physical divider
	# you play across, not just a faint line. z_index negative so cards still
	# draw on top of it when they straddle the midline during placement.
	_midline = Panel.new()
	_midline.anchor_left = 0.0
	_midline.anchor_right = 1.0
	_midline.anchor_top = 0.5
	_midline.anchor_bottom = 0.5
	# Beam thickened 28 → 44px so the midline reads as a proper wooden divider
	# instead of a trim line. Sits behind the slot grid via z_index=-1.
	_midline.offset_top = -22
	_midline.offset_bottom = 22
	_midline.offset_left = 10
	_midline.offset_right = -10
	_midline.z_index = -1
	_midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var beam_style := StyleBoxFlat.new()
	beam_style.bg_color = Color(0.14, 0.09, 0.05, 1.0)
	beam_style.border_color = Color(GILT.r, GILT.g, GILT.b, 0.95)
	beam_style.border_width_top = 2
	beam_style.border_width_bottom = 2
	beam_style.border_width_left = 0
	beam_style.border_width_right = 0
	_midline.add_theme_stylebox_override("panel", beam_style)
	board_zone.add_child(_midline)

	# Player half (bottom of board zone, dark green tint)
	var player_zone := PanelContainer.new()
	player_zone.anchor_left = 0.0
	player_zone.anchor_right = 1.0
	player_zone.anchor_top = 0.5
	player_zone.anchor_bottom = 1.0
	player_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pz_style := StyleBoxFlat.new()
	pz_style.bg_color = Color(0, 0, 0, 0)
	pz_style.border_color = Color(0.18, 0.45, 0.22, 0.0)
	pz_style.border_width_top = 0
	pz_style.corner_radius_bottom_left = 8
	pz_style.corner_radius_bottom_right = 8
	pz_style.content_margin_left = 4
	pz_style.content_margin_right = 4
	pz_style.content_margin_top = 2
	pz_style.content_margin_bottom = 2
	player_zone.add_theme_stylebox_override("panel", pz_style)
	board_zone.add_child(player_zone)

	var player_inner := VBoxContainer.new()
	player_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_inner.add_theme_constant_override("separation", 14)
	player_zone.add_child(player_inner)

	var player_front_lanes := _make_row_container("FRONT", Color(0.45, 0.80, 0.55, 0.65))
	player_inner.add_child(player_front_lanes)

	var player_back_lanes := _make_row_container("BACK", Color(0.35, 0.70, 0.45, 0.35))
	player_inner.add_child(player_back_lanes)

	for i in range(LANES_PER_ROW):
		var e_back := _make_lane_slot(true, i, ROW_BACK)
		enemy_back_lanes.add_child(e_back)
		_enemy_back_slots.append(e_back)
		var e_front := _make_lane_slot(true, i, ROW_FRONT)
		enemy_front_lanes.add_child(e_front)
		_enemy_slots.append(e_front)
		var p_front := _make_lane_slot(false, i, ROW_FRONT)
		player_front_lanes.add_child(p_front)
		_player_slots.append(p_front)
		var p_back := _make_lane_slot(false, i, ROW_BACK)
		player_back_lanes.add_child(p_back)
		_player_back_slots.append(p_back)
	# Standalone portrait columns removed — both portraits now live inside
	# the left info column built in _build_left_info_column().


func _build_portrait_columns() -> void:
	# STS-style anchor: a vertical sliver on the far-left edge carries the
	# player and enemy hero portraits. Both placed against the corresponding
	# half of the board so the eye reads "me vs them" instantly.
	var enemy_portrait := _make_portrait_card(true)
	enemy_portrait.anchor_left = 0.0
	enemy_portrait.anchor_right = 0.0
	enemy_portrait.anchor_top = 0.0
	enemy_portrait.anchor_bottom = 0.0
	enemy_portrait.offset_left = 12
	enemy_portrait.offset_top = 160
	enemy_portrait.offset_right = 96
	enemy_portrait.offset_bottom = 280
	_board_container.add_child(enemy_portrait)

	var player_portrait := _make_portrait_card(false)
	player_portrait.anchor_left = 0.0
	player_portrait.anchor_right = 0.0
	player_portrait.anchor_top = 1.0
	player_portrait.anchor_bottom = 1.0
	player_portrait.offset_left = 12
	player_portrait.offset_top = -450
	player_portrait.offset_right = 96
	player_portrait.offset_bottom = -330
	_board_container.add_child(player_portrait)


func _make_portrait_card(is_enemy: bool) -> Panel:
	# Compact portrait disc: dark inked circle with the appropriate icon
	# tinted gold (player) or red (enemy). Acts as the "you are here"
	# anchor on the side of the board.
	var p := Panel.new()
	var rim_color := Color(0.95, 0.30, 0.20, 1.0) if is_enemy \
		else Color(0.95, 0.78, 0.30, 1.0)
	var bg_color := Color(0.10, 0.07, 0.04, 0.94)
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.border_color = rim_color
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		s.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(k, 14)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	icon.anchor_left = 0.5
	icon.anchor_right = 0.5
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = -28
	icon.offset_right = 28
	icon.offset_top = -28
	icon.offset_bottom = 28
	icon.modulate = rim_color
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_enemy:
		icon.texture = GameTheme.tex_node_boss
	else:
		var helm_path := "res://assets/icons/game-icons/horned-helm.svg"
		if ResourceLoader.exists(helm_path):
			icon.texture = load(helm_path)
		else:
			icon.texture = GameTheme.tex_hud_heart
	p.add_child(icon)

	# Small caption underneath: "YOU" / "FOE".
	var caption := Label.new()
	caption.text = "FOE" if is_enemy else "YOU"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -22
	caption.offset_bottom = -4
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", rim_color)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	caption.add_theme_constant_override("outline_size", 4)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(caption)
	return p


func _make_row_container(_label_text: String, _label_color: Color) -> HBoxContainer:
	# Lane row: HBox of 4 slots. No label text — position vs midline + slot
	# styling are the only signals needed. Caller uses the returned reference
	# directly (no get_node-by-name lookup, since two siblings can't share
	# the same name without Godot renaming one of them).
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## Loaded once at first call so each of the 16 slots reuses the same texture.
static var _slot_frame_tex: Texture2D = null


func _make_lane_slot(is_enemy: bool, lane_idx: int, row: int = ROW_FRONT) -> Control:
	# Slot composition (back-to-front draw order):
	#   1. dark interior ColorRect (the "well" — gives empty slots a visible bottom)
	#   2. painterly NinePatchRect frame (256x256 source, tinted gilt for front
	#      vs muted bronze for back). Single texture used for all 16 slots.
	#   3. CenterContainer named "Cell" — anchors the played card to the middle.
	# Landscape slots match the on-field card aspect (Card2D.BATTLEFIELD_SIZE
	# = 200×150). Creature art is wider than tall, so landscape uses each
	# lane's horizontal real estate without the squashed-square look that
	# left big gutters when slots were square. SHRINK_CENTER pins the slot
	# at its minimum size; HBox ALIGNMENT_CENTER then clusters the four
	# slots centered with the row separation as the gap. Sized to fill the
	# expanded board (offset_left/right=242, board ~1116×706 in a 1600×900
	# window) without overflowing four rows + midline.
	const SLOT_W := 204
	const SLOT_H := 154
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.clip_contents = false

	# Interior "well" — a subtly tinted, slightly darker rectangle that makes
	# each empty slot read as a distinct placement zone even when nothing's in
	# it. Without this, empty lanes look like background and the player can't
	# tell the board has 4 lanes × 2 rows.
	var well := ColorRect.new()
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Warm (enemy red) vs cool (player blue) — pushed to higher saturation +
	# alpha than the original muted values so "mine vs theirs" reads at a glance,
	# matching the complementary-tint convention used in Cross Blitz and similar
	# lane-combat titles. Front rows are richer than back rows to reinforce
	# depth.
	var well_color: Color
	if is_enemy:
		well_color = Color(0.34, 0.06, 0.05, 0.68) if row == ROW_FRONT \
			else Color(0.22, 0.05, 0.05, 0.54)
	else:
		well_color = Color(0.06, 0.14, 0.28, 0.66) if row == ROW_FRONT \
			else Color(0.04, 0.10, 0.20, 0.52)
	well.color = well_color
	slot.add_child(well)

	# Painterly 9-patch frame — same source texture for all 16 slots; row +
	# side tint is the only thing that varies.
	if _slot_frame_tex == null:
		var path := "res://assets/spells/painterly-3/frame-0-grey.png"
		if ResourceLoader.exists(path):
			_slot_frame_tex = load(path) as Texture2D
	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Source is 256×256 with a chunky painterly border. ~52px margin keeps
		# the corners undistorted while the middle stretches to fit the slot.
		frame.patch_margin_left = 52
		frame.patch_margin_right = 52
		frame.patch_margin_top = 52
		frame.patch_margin_bottom = 52
		frame.draw_center = false  # corners + edges only; interior shows the well
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Visible enough to read as a real frame around each lane — was at 0.10
		# alpha before, which made the slots look like empty space and creatures
		# look like they were floating top-left of nowhere.
		var tint: Color
		if is_enemy:
			tint = Color(1.0, 0.42, 0.28, 0.80) if row == ROW_FRONT \
				else Color(0.82, 0.36, 0.22, 0.62)
		else:
			tint = Color(0.36, 0.66, 1.0, 0.82) if row == ROW_FRONT \
				else Color(0.28, 0.50, 0.84, 0.64)
		frame.modulate = tint
		slot.add_child(frame)

	# Drop-target highlight overlay — only visible (alpha tweened up by
	# _set_slot_highlight) while the player is dragging a creature card over
	# this slot. Sits below "Cell" so a creature placed in the slot draws on
	# top of any lingering glow without us having to clear it explicitly.
	# Player slots get a gold highlight; enemy slots get a red one (used by
	# spell-targeting logic so it doesn't need its own overlay).
	var highlight := ColorRect.new()
	highlight.name = "Highlight"
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	if is_enemy:
		highlight.color = Color(1.0, 0.45, 0.30, 0.0)
	else:
		highlight.color = Color(1.0, 0.86, 0.40, 0.0)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(highlight)

	# Centering wrapper for the played card.
	var cell := CenterContainer.new()
	cell.name = "Cell"
	cell.set_anchors_preset(Control.PRESET_FULL_RECT)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cell)
	return slot


func _slot_cell(slot: Control) -> CenterContainer:
	# Returns the centering child of a lane slot. All placement code should
	# add cards into this, not directly onto the slot, so cards center
	# instead of pinning to a corner.
	var cell = slot.get_node_or_null("Cell")
	return cell as CenterContainer


func _slot_set_card(slot: Control, card: Control) -> void:
	# Clears any existing card from the slot and places `card` centered inside.
	# Use this instead of slot.add_child(card) — the slot has a Panel bg child
	# that must be preserved when we swap cards.
	# remove_child() detaches the old occupant *this frame* before queue_free
	# schedules its deletion; if we only queue_free, the old card stays in the
	# cell for the rest of the frame and renders stacked on top of the new one
	# (which looked like "two creatures combining their stats" on placement).
	var cell = _slot_cell(slot)
	if cell == null:
		slot.add_child(card)
		return
	for child in cell.get_children():
		cell.remove_child(child)
		child.queue_free()
	cell.add_child(card)


func _slot_clear(slot: Control) -> void:
	# Removes the card from the slot (keeping the bg + cell intact).
	var cell = _slot_cell(slot)
	if cell == null:
		return
	for child in cell.get_children():
		child.queue_free()


func _slot_take_card(slot: Control, card: Control) -> void:
	# Detaches `card` from the slot's cell so it can be re-parented elsewhere.
	var cell = _slot_cell(slot)
	if cell != null and cell.is_ancestor_of(card):
		cell.remove_child(card)
	elif slot.is_ancestor_of(card):
		slot.remove_child(card)


func _restore_slot_label(_slot: Control, _lane_idx: int) -> void:
	# Empty slots no longer carry placeholder labels (they bled through cards
	# on placement). The slot's outlined style is the empty state. Kept as a
	# stub so existing callsites keep compiling.
	pass


func _place_lane_card(card_id: String, lane_idx: int, is_opponent: bool) -> void:
	# Legacy helper retained for test/worktree compat; routes through the
	# centered slot helpers so cards don't pin to a corner.
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.is_opponent = is_opponent
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = CardDB.get_card_data(card_id)
	card.current_lane = lane_idx
	if is_opponent:
		_enemy_field[lane_idx] = card
		_slot_set_card(_enemy_slots[lane_idx], card)
	else:
		_player_field[lane_idx] = card
		_slot_set_card(_player_slots[lane_idx], card)
	card.destroyed.connect(_on_card_destroyed.bind(card))


func _place_card_in_slot(card: Control, lane_idx: int, row: int = ROW_FRONT) -> void:
	_row_array(false, row)[lane_idx] = card
	card.current_row = row
	card.current_lane = lane_idx
	var slot = _slot_array(false, row)[lane_idx]
	_slot_set_card(slot, card)
	if not card.destroyed.is_connected(_on_card_destroyed.bind(card)):
		card.destroyed.connect(_on_card_destroyed.bind(card))
	if card.has_floop() and not card.is_opponent:
		if not card.floop_clicked.is_connected(_on_floop_clicked.bind(card)):
			card.floop_clicked.connect(_on_floop_clicked.bind(card))
	card.update_floop_display()
	_play_landing_pop(card)


func _play_landing_pop(card: Control) -> void:
	# Squash-and-stretch arrival: the card overshoots big, then settles to its
	# resting scale. Reads as the creature "slamming" onto the battlefield.
	# Deferred so it runs after the slot container has laid the card out.
	if not is_instance_valid(card):
		return
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var rest: Vector2 = card.scale
	card.pivot_offset = card.size * 0.5
	card.scale = rest * 1.35
	var tw := card.create_tween()
	tw.tween_property(card, "scale", rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Once the landing settles, start the idle bob so the creature reads as
	# "alive" on the field instead of frozen between turns.
	tw.tween_callback(func():
		if is_instance_valid(card) and card.has_method("enable_idle_bob"):
			card.enable_idle_bob()
	)


func _on_card_destroyed(card: Control) -> void:
	for i in range(LANES_PER_ROW):
		if _player_field[i] == card:
			_player_field[i] = null
			_restore_slot_label(_player_slots[i], i)
		if _enemy_field[i] == card:
			_enemy_field[i] = null
			_restore_slot_label(_enemy_slots[i], i)
		if _player_back[i] == card:
			_player_back[i] = null
			if i < _player_back_slots.size():
				_restore_slot_label(_player_back_slots[i], i)
		if _enemy_back[i] == card:
			_enemy_back[i] = null
			if i < _enemy_back_slots.size():
				_restore_slot_label(_enemy_back_slots[i], i)




func _nearest_lane_index(screen_pos: Vector2) -> int:
	# Legacy helper retained for callers that only care about the column.
	return _nearest_player_slot(screen_pos).lane


func _nearest_player_slot(screen_pos: Vector2) -> Dictionary:
	# 4x4: pick the closest player slot by 2D distance across both rows.
	# Drag-to-play UX: drop on the front row to put the creature in front,
	# drop on the back row (further from the midline) to slot it in back.
	var best := {"row": ROW_FRONT, "lane": 0}
	var best_dist := INF
	for row in [ROW_FRONT, ROW_BACK]:
		var slots = _slot_array(false, row)
		for i in range(LANES_PER_ROW):
			if i >= slots.size():
				continue
			var slot = slots[i]
			var center = slot.global_position + slot.size * 0.5
			var d = (screen_pos - center).length()
			if d < best_dist:
				best_dist = d
				best = {"row": row, "lane": i}
	return best


# ── Slot drop-target highlighting ──────────────────────────────────────────
# Cards being dragged emit a `dragging` signal each frame; we light up the
# closest player slot so the player can see exactly where the creature will
# land. Highlights are cleared on drop or cancel via `drag_ended`.

# The card currently being dragged with an active highlight. Tracked so the
# clear-all helper can be called blind (e.g. on game-over) without leaking.
var _highlighted_slot: Control = null


func _on_card_dragging(global_pos: Vector2, card: Control) -> void:
	if card == null or not is_instance_valid(card):
		return
	# Drag must have actually crossed into the play zone — otherwise mousing
	# inside the hand bands lit-up slots while the player wasn't even trying
	# to play yet. Use the same threshold the drop check uses.
	var viewport_h := get_viewport_rect().size.y
	if global_pos.y >= viewport_h * 0.78:
		_clear_slot_highlights()
		return
	var drop := _nearest_player_slot(global_pos)
	var slot: Control = _slot_array(false, drop.row)[drop.lane]
	if slot == _highlighted_slot:
		return
	_clear_slot_highlights()
	_set_slot_highlight(slot, true)
	_highlighted_slot = slot


func _clear_slot_highlights() -> void:
	if _highlighted_slot != null and is_instance_valid(_highlighted_slot):
		_set_slot_highlight(_highlighted_slot, false)
	_highlighted_slot = null


func _set_slot_highlight(slot: Control, on: bool) -> void:
	if slot == null:
		return
	# Toggles the alpha of the slot's dedicated highlight overlay (added in
	# _make_lane_slot). Using a separate child keeps the well's color and the
	# frame's tint untouched, so clearing the highlight just hides the glow
	# rather than trying to remember the original modulate of every child.
	var hl: ColorRect = slot.get_node_or_null("Highlight") as ColorRect
	if hl == null:
		return
	var c := hl.color
	c.a = 0.42 if on else 0.0
	hl.color = c


# =====================================================================
#  HUD
# =====================================================================

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 12
	add_child(_hud_layer)
	_build_left_info_column()
	_build_end_turn_button()
	_build_glossary_button()
	_build_settings_gear_button()
	_build_targeting_arrow()

	_info_label = _make_text_label("", 22, Color(1, 0.78, 0.40))
	_info_label.set_anchors_preset(Control.PRESET_CENTER)
	_info_label.position = Vector2(-200, -30)
	_info_label.size = Vector2(400, 60)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_info_label.add_theme_constant_override("outline_size", 6)
	_hud_layer.add_child(_info_label)

	_build_relic_display()


func _build_left_info_column() -> void:
	# Diegetic HUD: painted master-art banners at the corners, no left rail.
	# Populates the same field references _update_hud() expects so the rest of
	# the update flow keeps working unchanged: _phase_label, _floor_label,
	# _enemy_hp_label, _player_hp_label, _mana_label, _deck_count_label,
	# _discard_count_label, _turn_label.
	_build_enemy_banner_diegetic()
	_build_player_banner_diegetic()
	_build_encounter_scroll_diegetic()
	_build_mana_post_diegetic()
	_build_piles_diegetic()


func _build_enemy_banner_diegetic() -> void:
	# Top-RIGHT: enemy portrait + HP medallion ONLY. Encounter title moved to
	# a centered title strip at top-center; relics tucked underneath this
	# banner. Slim banner reads cleaner than the previous tall column that
	# stacked portrait + HP + encounter info + round counter.
	const W := 220
	const H := 240
	var banner := Control.new()
	banner.anchor_left = 1.0
	banner.anchor_right = 1.0
	banner.anchor_top = 0.0
	banner.anchor_bottom = 0.0
	banner.offset_left = -(14 + W)
	banner.offset_top = 14
	banner.offset_right = -14
	banner.offset_bottom = 14 + H
	banner.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(banner)
	_enemy_banner_for_info = banner

	# Dark backdrop so the portrait never blends into the meadow background.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.03, 0.03, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)

	# Portrait region: from the top down to where the HP medallion starts.
	# HP medallion lives in the bottom 72px of the banner. With H=240, HP
	# spans y=168..234 of the banner box.
	const HP_TOP := -72
	const HP_BOTTOM := -8
	var demon_tex: Texture2D = load("res://assets/portraits/enemy_commander.png")
	if demon_tex != null:
		var img := TextureRect.new()
		img.texture = demon_tex
		img.anchor_left = 0.0
		img.anchor_right = 1.0
		img.anchor_top = 0.0
		img.anchor_bottom = 1.0
		img.offset_bottom = HP_TOP
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(img)

	# Painted border around the portrait region only.
	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.anchor_left = 0.0
		frame.anchor_right = 1.0
		frame.anchor_top = 0.0
		frame.anchor_bottom = 1.0
		frame.offset_bottom = HP_TOP
		frame.patch_margin_left = 52
		frame.patch_margin_right = 52
		frame.patch_margin_top = 52
		frame.patch_margin_bottom = 52
		frame.draw_center = false
		frame.modulate = Color(0.85, 0.30, 0.20, 0.90)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(frame)

	var hp := _make_hp_medallion_diegetic(true, enemy_hp, enemy_max_hp)
	hp.anchor_left = 0.0
	hp.anchor_right = 1.0
	hp.anchor_top = 1.0
	hp.anchor_bottom = 1.0
	hp.offset_top = HP_TOP
	hp.offset_bottom = HP_BOTTOM
	hp.offset_left = 4
	hp.offset_right = -4
	banner.add_child(hp)


func _build_player_banner_diegetic() -> void:
	# Bottom-LEFT: Dürer's "Knight, Death and the Devil" (1513). Pinned to the
	# bottom edge so the player portrait + HP sit RIGHT under the field (under
	# "us" — the player) rather than floating mid-screen. The mana orb sits
	# directly under this column.
	const W := 200
	const H := 230
	var banner := Control.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 0.0
	banner.anchor_top = 1.0
	banner.anchor_bottom = 1.0
	banner.offset_left = 14
	# Banner top sits ~10px above the hand strip start (-210), with the HP
	# medallion bolted to its bottom — total column ends at the bottom edge.
	banner.offset_top = -(H + 10)
	banner.offset_right = 14 + W
	banner.offset_bottom = -10
	banner.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(banner)

	# Dark backdrop behind the portrait so it doesn't blend into the meadow.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.04, 0.03, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)

	var knight: Texture2D = load("res://assets/portraits/player_knight.png")
	if knight != null:
		var img := TextureRect.new()
		img.texture = knight
		# Portrait fills the TOP portion only — leaves the bottom 70px clear
		# for the HP medallion to sit under it (under "us" — the player).
		img.anchor_left = 0.0
		img.anchor_right = 1.0
		img.anchor_top = 0.0
		img.anchor_bottom = 1.0
		img.offset_bottom = -78
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(img)

	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		# Frame wraps just the portrait area, not the HP medallion below it.
		frame.anchor_left = 0.0
		frame.anchor_right = 1.0
		frame.anchor_top = 0.0
		frame.anchor_bottom = 1.0
		frame.offset_bottom = -78
		frame.patch_margin_left = 52
		frame.patch_margin_right = 52
		frame.patch_margin_top = 52
		frame.patch_margin_bottom = 52
		frame.draw_center = false
		frame.modulate = Color(0.95, 0.78, 0.32, 0.90)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(frame)

	var hp := _make_hp_medallion_diegetic(false, player_hp, player_max_hp)
	hp.anchor_left = 0.0
	hp.anchor_right = 1.0
	hp.anchor_top = 1.0
	hp.anchor_bottom = 1.0
	hp.offset_top = -68
	hp.offset_bottom = -4
	hp.offset_left = 4
	hp.offset_right = -4
	banner.add_child(hp)


func _make_hp_medallion_diegetic(is_enemy: bool, hp: int, max_hp: int) -> Control:
	# Wax-sealed HP disc: dark background, painterly border, HP numeral
	# centered. Sets _enemy_hp_label / _player_hp_label so _update_hud()
	# can update the numeral on damage / heal.
	var disc := Control.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.16, 0.04, 0.04, 0.92) if is_enemy \
		else Color(0.14, 0.08, 0.03, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(bg)

	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.patch_margin_left = 52
		frame.patch_margin_right = 52
		frame.patch_margin_top = 52
		frame.patch_margin_bottom = 52
		frame.draw_center = false
		frame.modulate = Color(0.95, 0.40, 0.25, 0.95) if is_enemy \
			else Color(0.95, 0.78, 0.32, 0.95)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(frame)

	# HP is the player's single most-important readout — pushed to 48pt red ink
	# with a heavy black outline so it dominates the visual hierarchy the way
	# Hearthstone / Cross Blitz HP numerals do. The old 22pt ivory lost the
	# hierarchy race to its own medallion frame.
	var lbl := _make_text_label("%d / %d" % [hp, max_hp], 48,
		Color(1.0, 0.22, 0.18))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(lbl)

	if is_enemy:
		_enemy_hp_label = lbl
	else:
		_player_hp_label = lbl
	return disc


func _build_encounter_scroll_diegetic() -> void:
	# Slim title strip pinned to the top-CENTER of the screen — encounter
	# name on top, phase/round below it. No background panel (frameless
	# matches the rest of the HUD); the relic strip / enemy banner / gear
	# icon flank it on either side without crowding.
	var strip := Control.new()
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.anchor_top = 0.0
	strip.anchor_bottom = 0.0
	strip.offset_left = -260
	strip.offset_right = 260
	strip.offset_top = 16
	strip.offset_bottom = 90
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(strip)

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(stack)

	var encounter_text := _encounter_name if _encounter_name != "" \
		else "Floor %d" % RunState.current_floor
	_floor_label = _make_text_label(encounter_text, 22, GILT)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_floor_label)

	_phase_label = _make_text_label("ROUND 1", 18, IVORY)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_phase_label)

	_turn_label = _make_text_label("Round 1", 12, Color(0.78, 0.70, 0.50))
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_turn_label)

	if _encounter_passive != "":
		var enc = EncounterDB.get_encounter(RunState.current_encounter_id)
		var passive := _make_text_label(enc.get("passive_desc", ""), 11,
			Color(0.95, 0.85, 0.55))
		passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(passive)


func _build_mana_post_diegetic() -> void:
	# Bottom-LEFT, directly RIGHT of the player banner: a big blue gem-like
	# orb showing current/max mana — Hearthstone/STS readout style. Previous
	# version used three candle textures with a tiny "3 / 3" caption below
	# that the player had to squint at; this one puts the count front and
	# center as a single 36pt numeral on a glowing disc so it can be read
	# from across the screen.
	const SIZE := 120
	var post := Control.new()
	post.anchor_left = 0.0
	post.anchor_right = 0.0
	post.anchor_top = 1.0
	post.anchor_bottom = 1.0
	# Sits just right of the player banner (banner W=200, x=14..214) with a
	# small gap; pinned to the bottom edge above the hand row.
	post.offset_left = 224
	post.offset_top = -(SIZE + 10)
	post.offset_right = 224 + SIZE
	post.offset_bottom = -10
	post.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(post)

	# Glowing blue disc — the "mana crystal" silhouette.
	var orb := Panel.new()
	orb.set_anchors_preset(Control.PRESET_FULL_RECT)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var orb_style := StyleBoxFlat.new()
	orb_style.bg_color = Color(0.08, 0.18, 0.42, 0.95)
	orb_style.border_color = Color(0.40, 0.72, 1.00, 1.0)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		orb_style.set(k, 4)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		orb_style.set(k, SIZE / 2)
	orb_style.shadow_color = Color(0.35, 0.65, 1.0, 0.55)
	orb_style.shadow_size = 14
	orb.add_theme_stylebox_override("panel", orb_style)
	post.add_child(orb)

	# Big numeric — current / max mana, dominant readout.
	_mana_label = _make_text_label("%d / %d" % [player_mana, player_max_mana],
		38, Color(0.85, 0.95, 1.0))
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mana_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mana_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_mana_label.add_theme_constant_override("outline_size", 6)
	post.add_child(_mana_label)

	# Caption below ("MANA") so newcomers can identify the resource.
	var caption := _make_text_label("MANA", 12, Color(0.55, 0.78, 1.0))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -22
	caption.offset_bottom = -6
	post.add_child(caption)


func _build_piles_diegetic() -> void:
	# Deck + Discard sit side-by-side in the LEFT column below the relic
	# grid (top-left). Previously deck-left / discard-right on opposite
	# screen edges, which made tracking your draw economy harder than
	# necessary — STS keeps them visually next to each other so you can
	# glance at both counts in one read. The left column is the only large
	# free vertical strip after the encounter scroll was removed.
	const PILE_W := 100
	const PILE_H := 122
	const COL_LEFT := 14
	const COL_TOP := 130  # below the relic grid (relics start y=14, ~3 rows max ~120)
	var deck_box := _make_pile_panel_diegetic("DECK", 0)
	deck_box.anchor_left = 0.0
	deck_box.anchor_right = 0.0
	deck_box.anchor_top = 0.0
	deck_box.anchor_bottom = 0.0
	deck_box.offset_left = COL_LEFT
	deck_box.offset_right = COL_LEFT + PILE_W
	deck_box.offset_top = COL_TOP
	deck_box.offset_bottom = COL_TOP + PILE_H
	_hud_layer.add_child(deck_box)

	var disc_box := _make_pile_panel_diegetic("DISCARD", 1)
	disc_box.anchor_left = 0.0
	disc_box.anchor_right = 0.0
	disc_box.anchor_top = 0.0
	disc_box.anchor_bottom = 0.0
	disc_box.offset_left = COL_LEFT + PILE_W + 16
	disc_box.offset_right = COL_LEFT + PILE_W * 2 + 16
	disc_box.offset_top = COL_TOP
	disc_box.offset_bottom = COL_TOP + PILE_H
	_hud_layer.add_child(disc_box)


func _make_pile_panel_diegetic(caption_text: String, kind: int) -> Control:
	# Small card-stack panel: dark inset with a painted border, numeric count
	# overlaid, caption below. Sets _deck_count_label / _discard_count_label
	# so _update_hud() can keep them current.
	var pile := Control.new()
	pile.mouse_filter = Control.MOUSE_FILTER_PASS

	var card_back_path := "res://assets/ui/card_back.png"
	if ResourceLoader.exists(card_back_path):
		var cb_tex: Texture2D = load(card_back_path)
		var back := TextureRect.new()
		back.texture = cb_tex
		back.anchor_left = 0.0
		back.anchor_right = 1.0
		back.anchor_top = 0.0
		back.anchor_bottom = 1.0
		back.offset_bottom = -22
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(back)
	else:
		var back := ColorRect.new()
		back.anchor_left = 0.0
		back.anchor_right = 1.0
		back.anchor_top = 0.0
		back.anchor_bottom = 1.0
		back.offset_bottom = -22
		back.color = Color(0.10, 0.07, 0.04, 0.92)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(back)

	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.anchor_left = 0.0
		frame.anchor_right = 1.0
		frame.anchor_top = 0.0
		frame.anchor_bottom = 1.0
		frame.offset_bottom = -22
		frame.patch_margin_left = 52
		frame.patch_margin_right = 52
		frame.patch_margin_top = 52
		frame.patch_margin_bottom = 52
		frame.draw_center = false
		frame.modulate = Color(0.85, 0.65, 0.30, 0.85)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(frame)

	var count_label := _make_text_label("0", 26, IVORY)
	count_label.anchor_left = 0.0
	count_label.anchor_right = 1.0
	count_label.anchor_top = 0.0
	count_label.anchor_bottom = 1.0
	count_label.offset_bottom = -22
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pile.add_child(count_label)

	var caption := _make_text_label(caption_text, 11, GILT)
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -20
	caption.offset_bottom = -2
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile.add_child(caption)

	if kind == 0:
		_deck_count_label = count_label
	else:
		_discard_count_label = count_label

	# Make the pile clickable to open the viewer overlay. A transparent
	# Button child fills the pile so clicks land regardless of where on
	# the panel the user taps.
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.anchor_left = 0.0
	click_btn.anchor_right = 1.0
	click_btn.anchor_top = 0.0
	click_btn.anchor_bottom = 1.0
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.pressed.connect(_show_pile_viewer.bind(kind))
	pile.add_child(click_btn)
	return pile


# ── Pile viewer overlay ──
# Modal that lists the contents of a pile (0 = draw, 1 = discard). Cards are
# sorted by cost then name so the player can quickly see what's coming, not
# the random draw order. Click the backdrop or Close to dismiss.
var _pile_viewer_layer: CanvasLayer = null

func _show_pile_viewer(kind: int) -> void:
	if _pile_viewer_layer != null and is_instance_valid(_pile_viewer_layer):
		_pile_viewer_layer.queue_free()
		_pile_viewer_layer = null
	var entries: Array = []
	var title_text: String
	if kind == 0:
		entries = _player_draw_pile.duplicate()
		title_text = "DRAW PILE (%d)" % entries.size()
	else:
		entries = _player_discard_pile.duplicate()
		title_text = "DISCARD PILE (%d)" % entries.size()

	_pile_viewer_layer = CanvasLayer.new()
	_pile_viewer_layer.layer = 100
	add_child(_pile_viewer_layer)

	# Backdrop — full-screen dim that catches clicks to close.
	var backdrop := Button.new()
	backdrop.flat = true
	backdrop.focus_mode = Control.FOCUS_NONE
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.7)
	backdrop.add_theme_stylebox_override("normal", dim)
	backdrop.add_theme_stylebox_override("hover", dim)
	backdrop.add_theme_stylebox_override("pressed", dim)
	backdrop.pressed.connect(_close_pile_viewer)
	_pile_viewer_layer.add_child(backdrop)

	# Title centered near the top.
	var title := _make_text_label(title_text, 36, IVORY)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 40
	title.offset_bottom = 90
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pile_viewer_layer.add_child(title)

	# Sort by (cost, name) so similar cards cluster — easier to scan than the
	# raw draw order.
	var sorted_entries: Array = []
	for entry in entries:
		var card_id := _entry_id(entry)
		var uid := _entry_uid(entry)
		var data := _resolve_card_data(card_id, uid)
		sorted_entries.append({
			"id": card_id,
			"uid": uid,
			"data": data,
			"cost": int(data.get("cost", 0)),
			"name": String(data.get("name", card_id)),
		})
	sorted_entries.sort_custom(func(a, b):
		if a.cost != b.cost:
			return a.cost < b.cost
		return a.name < b.name)

	# Visual grid of Card2D instances (STS-style "view your deck" overlay) —
	# previously a spreadsheet of text rows. Six columns fit comfortably at
	# 225×300 portrait card size with 16px spacing; rows wrap automatically.
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.5
	scroll.anchor_right = 0.5
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = -800
	scroll.offset_right = 800
	scroll.offset_top = 110
	scroll.offset_bottom = -110
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pile_viewer_layer.add_child(scroll)

	if sorted_entries.is_empty():
		var empty_lbl := _make_text_label("(empty)", 24, GameTheme.IVORY)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.custom_minimum_size = Vector2(1600, 60)
		scroll.add_child(empty_lbl)
	else:
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 16)
		grid.custom_minimum_size = Vector2(1600, 0)
		scroll.add_child(grid)

		for e in sorted_entries:
			# Mini wrapper sized to the static card so the grid lays them out
			# at uniform spacing without the cards stretching. 225×300 matches
			# Card2D's hand size (CARD_SIZE).
			var wrapper := Control.new()
			wrapper.custom_minimum_size = Vector2(225, 300)
			var card = CARD_SCENE.instantiate()
			card.static_display = true
			card.card_data = e.data
			wrapper.add_child(card)
			grid.add_child(wrapper)

	# Close button at the bottom.
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(160, 44)
	close_btn.anchor_left = 0.5
	close_btn.anchor_right = 0.5
	close_btn.anchor_top = 1.0
	close_btn.anchor_bottom = 1.0
	close_btn.offset_left = -80
	close_btn.offset_right = 80
	close_btn.offset_top = -80
	close_btn.offset_bottom = -36
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_close_pile_viewer)
	_pile_viewer_layer.add_child(close_btn)


func _close_pile_viewer() -> void:
	if _pile_viewer_layer != null and is_instance_valid(_pile_viewer_layer):
		_pile_viewer_layer.queue_free()
		_pile_viewer_layer = null


func _make_text_label(text: String, sz: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	# Headers use the display font (Cinzel) for chiseled look; smaller HUD text
	# uses the body font (Nunito) for readability at small sizes.
	if sz >= 22 and GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	elif GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# =====================================================================
#  GLOSSARY OVERLAY — Tab / ? to toggle, Esc to close.
# =====================================================================

var _glossary_layer: CanvasLayer = null

const MECHANICS_HELP: Array = [
	{"name": "Floop", "desc": "Skip a creature's attack this turn to use its special ability. Toggle the indicator before ending your turn."},
	{"name": "Sacrifice", "desc": "Kill one of your own creatures as a free action (once per turn). Triggers its On-Death effect."},
	{"name": "Banking", "desc": "Carry up to 1 unused mana into next turn. Pay it like normal mana."},
	{"name": "Front / Back row", "desc": "Both rows attack each turn — front goes first and is attacked first. Back is queue space, not a separate combat tier."},
	{"name": "Swift phase", "desc": "Creatures with Swift attack BEFORE simultaneous combat resolves. They strike first and take damage normally."},
	{"name": "Mana", "desc": "3 per turn baseline. Spent on creatures and spells. Relics can grow your pool."},
	{"name": "Draw", "desc": "4 cards per turn, max hand size 10. Unplayed cards discard at end of turn unless they have Retain."},
]


func _toggle_glossary() -> void:
	if _glossary_layer != null and is_instance_valid(_glossary_layer):
		_close_glossary()
	else:
		_show_glossary()


func _show_glossary() -> void:
	if _glossary_layer != null and is_instance_valid(_glossary_layer):
		_glossary_layer.queue_free()
	_glossary_layer = CanvasLayer.new()
	_glossary_layer.layer = 100
	add_child(_glossary_layer)

	var backdrop := Button.new()
	backdrop.flat = true
	backdrop.focus_mode = Control.FOCUS_NONE
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.78)
	backdrop.add_theme_stylebox_override("normal", dim)
	backdrop.add_theme_stylebox_override("hover", dim)
	backdrop.add_theme_stylebox_override("pressed", dim)
	backdrop.pressed.connect(_close_glossary)
	_glossary_layer.add_child(backdrop)

	var title := _make_text_label("GLOSSARY", 36, IVORY)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 36
	title.offset_bottom = 86
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glossary_layer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.5
	scroll.anchor_right = 0.5
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = -460
	scroll.offset_right = 460
	scroll.offset_top = 104
	scroll.offset_bottom = -100
	_glossary_layer.add_child(scroll)

	var root_hbox := HBoxContainer.new()
	root_hbox.add_theme_constant_override("separation", 20)
	root_hbox.custom_minimum_size = Vector2(900, 0)
	scroll.add_child(root_hbox)

	var kw_col := VBoxContainer.new()
	kw_col.add_theme_constant_override("separation", 6)
	kw_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_hbox.add_child(kw_col)
	var kw_header := _make_text_label("KEYWORDS", 22, GILT)
	kw_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kw_col.add_child(kw_header)
	for k in KeywordEffects.KEYWORDS.keys():
		var entry = KeywordEffects.KEYWORDS[k]
		kw_col.add_child(_make_glossary_row(entry.display, entry.desc))

	var mech_col := VBoxContainer.new()
	mech_col.add_theme_constant_override("separation", 6)
	mech_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_hbox.add_child(mech_col)
	var mech_header := _make_text_label("MECHANICS", 22, GILT)
	mech_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mech_col.add_child(mech_header)
	for m in MECHANICS_HELP:
		mech_col.add_child(_make_glossary_row(m.name, m.desc))

	var hint := _make_text_label("[Tab] / [?] to toggle  ·  [Esc] or click backdrop to close", 14, IVORY)
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -56
	hint.offset_bottom = -28
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glossary_layer.add_child(hint)


func _close_glossary() -> void:
	if _glossary_layer != null and is_instance_valid(_glossary_layer):
		_glossary_layer.queue_free()
		_glossary_layer = null


func _make_glossary_row(entry_name: String, desc: String) -> PanelContainer:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.85)
	style.border_color = Color(0.55, 0.40, 0.18, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	var name_lbl := _make_text_label(entry_name, 18, GILT)
	v.add_child(name_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", IVORY)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(400, 0)
	desc_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	desc_lbl.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	v.add_child(desc_lbl)
	return row


func _build_end_turn_button() -> void:
	# Pinned bottom-right, sits beside the HUD strip above the hand.
	var btn := Button.new()
	btn.text = "END TURN  [E]"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -180
	btn.offset_top = -230
	btn.offset_right = -20
	btn.offset_bottom = -194
	btn.pressed.connect(_on_end_turn)
	_style_button(btn)
	btn.add_theme_font_size_override("font_size", 20)  # primary action — larger than the rest
	_end_turn_btn = btn
	_hud_layer.add_child(btn)


func _build_glossary_button() -> void:
	# "?" orb above the end-turn button. A circular gilt-rimmed disc (matches
	# the relic strip styling) so the button is clearly identifiable as
	# interactive — previously bare gold text floated against the background
	# and was nearly invisible.
	const SIZE := 48
	var btn := Button.new()
	btn.text = "?"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -(SIZE + 24)
	btn.offset_top = -(SIZE + 254)
	btn.offset_right = -24
	btn.offset_bottom = -254
	btn.tooltip_text = "Glossary  (Tab / ?)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_display:
		btn.add_theme_font_override("font", GameTheme.font_display)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_font_size_override("font_size", 22)
	# Build the orb stylebox (dark fill + gilt rim, fully round corners).
	var orb_style := StyleBoxFlat.new()
	orb_style.bg_color = Color(0.10, 0.075, 0.060, 0.92)
	orb_style.border_color = GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		orb_style.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		orb_style.set(k, SIZE / 2)
	orb_style.shadow_color = Color(0, 0, 0, 0.6)
	orb_style.shadow_size = 6
	var hover_style := orb_style.duplicate()
	hover_style.border_color = GameTheme.GILT_BRIGHT
	btn.add_theme_stylebox_override("normal", orb_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", orb_style)
	btn.add_theme_stylebox_override("focus", orb_style)
	btn.pressed.connect(_toggle_glossary)
	_hud_layer.add_child(btn)


func _build_settings_gear_button() -> void:
	# Settings gear at the top-LEFT corner — canonical position in most card
	# games (Hearthstone, Cross Blitz, Marvel Snap). Opens the existing
	# SettingsOverlay attached to the UserSettings autoload.
	const SIZE := 48
	var btn := Button.new()
	btn.text = "⚙"
	btn.anchor_left = 0.0
	btn.anchor_right = 0.0
	btn.anchor_top = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left = 14
	btn.offset_right = 14 + SIZE
	btn.offset_top = 14
	btn.offset_bottom = 14 + SIZE
	btn.tooltip_text = "Settings"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_font_size_override("font_size", 26)
	var orb_style := StyleBoxFlat.new()
	orb_style.bg_color = Color(0.10, 0.075, 0.060, 0.92)
	orb_style.border_color = GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		orb_style.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		orb_style.set(k, SIZE / 2)
	orb_style.shadow_color = Color(0, 0, 0, 0.6)
	orb_style.shadow_size = 6
	var hover_style := orb_style.duplicate()
	hover_style.border_color = GameTheme.GILT_BRIGHT
	btn.add_theme_stylebox_override("normal", orb_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", orb_style)
	btn.add_theme_stylebox_override("focus", orb_style)
	btn.pressed.connect(_open_settings_overlay)
	_hud_layer.add_child(btn)


func _open_settings_overlay() -> void:
	# Finds and opens the SettingsOverlay attached to the UserSettings autoload
	# (same mechanism MainMenu uses for its settings button).
	for child in UserSettings.get_children():
		if child.has_method("_open"):
			child._open()
			return
		elif child.has_method("open"):
			child.open()
			return


func _build_sacrifice_button() -> void:
	var btn := Button.new()
	btn.text = "SACRIFICE [S]"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -180
	btn.offset_top = -290
	btn.offset_right = -20
	btn.offset_bottom = -254
	btn.pressed.connect(_on_sacrifice_pressed)
	_style_button(btn)
	_sacrifice_btn = btn
	_hud_layer.add_child(btn)


func _style_button(btn: Button) -> void:
	# Frameless gilt-text styling, matching the main menu: no filled box — the
	# label brightens to gold on hover. A dark outline keeps it legible over the
	# battlefield, and the display font ties it to the menu's chiseled look. The
	# button's (invisible) rect is still the hit area, so clicks near the label
	# register normally.
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_display:
		btn.add_theme_font_override("font", GameTheme.font_display)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	btn.add_theme_color_override("font_disabled_color", Color(0.65, 0.60, 0.50, 0.5))
	btn.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	btn.add_theme_constant_override("outline_size", 5)
	btn.add_theme_font_size_override("font_size", 14)


func _build_relic_display() -> void:
	# Relic grid sits on the LEFT column below the deck+discard piles. The
	# card-hover detail popup moved to the right under the enemy banner —
	# that swap puts active-info (hovered card details) on the right where
	# the eye is reading enemy stats, and persistent-info (your relics) on
	# the left next to your other deck stats. Piles end at y~260; relics
	# start ~10px below.
	_relic_panel = GridContainer.new()
	_relic_panel.columns = 4
	_relic_panel.anchor_left = 0.0
	_relic_panel.anchor_right = 0.0
	_relic_panel.anchor_top = 0.0
	_relic_panel.anchor_bottom = 0.0
	_relic_panel.offset_left = 14
	_relic_panel.offset_right = 230
	_relic_panel.offset_top = 270
	_relic_panel.offset_bottom = 270
	_relic_panel.add_theme_constant_override("h_separation", 6)
	_relic_panel.add_theme_constant_override("v_separation", 6)
	_relic_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_relic_panel)
	_refresh_relic_display()


func _refresh_relic_display() -> void:
	for child in _relic_panel.get_children():
		child.queue_free()
	for relic_id in RunState.relics:
		var relic = RelicDB.get_relic(relic_id)
		if relic.is_empty():
			continue
		# Each relic: 40×40 dark disc with a gilt rim, icon centered. Smaller
		# than the previous 52px chips so 5 fit per row in the top-left column
		# without spilling into the board zone. Tooltip carries name+desc.
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(40, 40)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = "%s — %s" % [relic.name, relic.desc]
		var disc_style := StyleBoxFlat.new()
		disc_style.bg_color = Color(0.10, 0.075, 0.060, 0.92)
		disc_style.border_color = GILT
		for k in ["border_width_top", "border_width_bottom",
				"border_width_left", "border_width_right"]:
			disc_style.set(k, 2)
		for k in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
			disc_style.set(k, 20)
		disc_style.shadow_color = Color(0, 0, 0, 0.6)
		disc_style.shadow_size = 4
		chip.add_theme_stylebox_override("panel", disc_style)

		var icon := RelicDB.get_relic_icon(relic_id)
		if icon != null:
			var tex := TextureRect.new()
			tex.texture = icon
			tex.anchor_left = 0.5
			tex.anchor_right = 0.5
			tex.anchor_top = 0.5
			tex.anchor_bottom = 0.5
			tex.offset_left = -12
			tex.offset_right = 12
			tex.offset_top = -12
			tex.offset_bottom = 12
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.modulate = GILT
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(tex)
		else:
			var letter := Label.new()
			letter.text = relic.name.substr(0, 1).to_upper()
			letter.set_anchors_preset(Control.PRESET_FULL_RECT)
			letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			letter.add_theme_font_size_override("font_size", 18)
			letter.add_theme_color_override("font_color", GILT)
			letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(letter)
		_relic_panel.add_child(chip)


func _update_hud() -> void:
	_player_hp_label.text = "%d / %d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "%d / %d" % [enemy_hp, enemy_max_hp]
	# Update HP bar fills (inset by 1px from frame border)
	var p_fill = _player_hp_label.get_parent().get_node_or_null("Fill")
	if p_fill:
		var p_target := 148.0 * clampf(float(player_hp) / float(player_max_hp), 0.0, 1.0)
		if _player_hp_tween != null and _player_hp_tween.is_valid():
			_player_hp_tween.kill()
		_player_hp_tween = p_fill.create_tween()
		_player_hp_tween.tween_property(p_fill, "size:x", p_target, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var e_fill = _enemy_hp_label.get_parent().get_node_or_null("Fill")
	if e_fill:
		var e_target := 178.0 * clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
		if _enemy_hp_tween != null and _enemy_hp_tween.is_valid():
			_enemy_hp_tween.kill()
		_enemy_hp_tween = e_fill.create_tween()
		_enemy_hp_tween.tween_property(e_fill, "size:x", e_target, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if player_mana > player_max_mana:
		_mana_label.text = "%d / %d (+%d)" % [player_mana, player_max_mana, player_mana - player_max_mana]
	else:
		_mana_label.text = "%d / %d" % [player_mana, player_max_mana]
	_refresh_hand_affordability()
	_turn_label.text = "Round %d" % round_number
	if _deck_count_label:
		_deck_count_label.text = str(_player_draw_pile.size())
	if _discard_count_label:
		_discard_count_label.text = str(_player_discard_pile.size())
	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "ROUND %d — YOUR TURN" % round_number
			_phase_label.add_theme_color_override("font_color", IVORY)
		Phase.RESOLVING:
			_phase_label.text = "COMBAT"
			_phase_label.add_theme_color_override("font_color", Color(1.00, 0.60, 0.25))
		Phase.GAME_OVER:
			pass


# =====================================================================
#  GAME FEEL
# =====================================================================

func screen_shake(amount: float) -> void:
	if not UserSettings.screen_shake:
		return
	if not _hud_layer:
		return
	var tw := create_tween()
	var duration := 0.3
	var steps := 8
	var step_time := duration / steps
	for i in steps:
		var decay := 1.0 - (float(i) / steps)
		var offset := Vector2(
			randf_range(-amount, amount) * decay,
			randf_range(-amount, amount) * decay)
		tw.tween_property(_hud_layer, "offset", offset, step_time)
	tw.tween_property(_hud_layer, "offset", Vector2.ZERO, step_time)


func screen_flash(color: Color, duration: float) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _hud_layer:
		_hud_layer.add_child(flash)
	else:
		add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, duration)
	tw.tween_callback(flash.queue_free)


func spawn_floating_number(global_pos: Vector2, text: String, color: Color, big: bool = false) -> void:
	# Floating combat text (damage / heal / gold). Parented to the HUD layer so
	# it survives the source node's death and rides the screen-shake offset.
	# Rises while fading; pops in with a slight back-eased scale.
	var parent: Node = _hud_layer if _hud_layer != null else self
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 38 if big else 26)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 200
	lbl.scale = Vector2(0.5, 0.5)
	# Center the label on the anchor: shift left/up by half its (font-driven)
	# size. Use a fixed nominal half-width since size isn't known pre-layout.
	lbl.position = global_pos + Vector2(-14, -8) + Vector2(randf_range(-10, 10), 0)
	lbl.pivot_offset = Vector2(14, 14)
	parent.add_child(lbl)
	var rise := -54.0 if not big else -72.0
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position:y", lbl.position.y + rise, 0.72).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.72).set_ease(Tween.EASE_IN).set_delay(0.18)
	tw.chain().tween_callback(lbl.queue_free)


func _refresh_hand_affordability() -> void:
	# Tell every card in the hand whether the current mana pool can pay its cost.
	# Card2D handles the visual change (dim when not affordable).
	for card in _hand:
		if card == null or not is_instance_valid(card):
			continue
		if not card.has_method("set_affordable"):
			continue
		var cost: int = int(card.card_data.get("cost", 0))
		card.set_affordable(player_mana >= cost)


func _build_targeting_arrow() -> void:
	# Hearthstone-style glowing curve from the cast source to the cursor. Lives
	# on the HUD layer so it draws above everything; hidden until targeting begins.
	_targeting_arrow = Line2D.new()
	_targeting_arrow.width = 7.0
	_targeting_arrow.default_color = Color(1.0, 0.78, 0.30, 0.95)
	_targeting_arrow.antialiased = true
	_targeting_arrow.joint_mode = Line2D.LINE_JOINT_ROUND
	_targeting_arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_targeting_arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_targeting_arrow.z_index = 240
	_targeting_arrow.visible = false
	# Width taper: thick at the cursor, slim at the source, like a chargeable beam.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	_targeting_arrow.width_curve = curve
	# Soft gradient: warm gold body fading to orange tip for the "spell about to
	# strike" read.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 0.55))
	grad.set_color(1, Color(1.0, 0.45, 0.15, 1.0))
	_targeting_arrow.gradient = grad
	_hud_layer.add_child(_targeting_arrow)
	# Arrowhead — triangular Polygon2D rotated to face the cursor.
	_targeting_arrow_head = Polygon2D.new()
	_targeting_arrow_head.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(-22, -10), Vector2(-22, 10)
	])
	_targeting_arrow_head.color = Color(1.0, 0.40, 0.12, 1.0)
	_targeting_arrow_head.z_index = 241
	_targeting_arrow_head.visible = false
	_hud_layer.add_child(_targeting_arrow_head)
	# Prediction label — appears above the hovered target during spell targeting.
	# Shows "-N" or "LETHAL!" so the player can read the outcome before clicking.
	_prediction_label = Label.new()
	_prediction_label.add_theme_font_size_override("font_size", 36)
	_prediction_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.20))
	_prediction_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_prediction_label.add_theme_constant_override("outline_size", 7)
	_prediction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prediction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prediction_label.z_index = 242
	_prediction_label.visible = false
	_hud_layer.add_child(_prediction_label)


func _show_targeting_arrow() -> void:
	if _targeting_arrow == null:
		return
	_targeting_arrow.visible = true
	_targeting_arrow_head.visible = true
	set_process(true)


func _hide_targeting_arrow() -> void:
	if _targeting_arrow == null:
		return
	_targeting_arrow.visible = false
	_targeting_arrow_head.visible = false
	if _prediction_label != null:
		_prediction_label.visible = false
	# Only stop _process if no other system needs it (currently nothing else does).
	if _targeting_spell == null:
		set_process(false)


func _process(_delta: float) -> void:
	if _targeting_spell != null and _targeting_arrow != null and _targeting_arrow.visible:
		_update_targeting_arrow()
		_update_damage_prediction()


func _update_targeting_arrow() -> void:
	# Cubic-bezier curve from a "spell hand" anchor (bottom-center of the screen)
	# up to the cursor. Curving rather than straight reads like a thrown spell
	# rather than a laser pointer.
	var vp := get_viewport_rect().size
	var origin := Vector2(vp.x * 0.5, vp.y - 60.0)
	var target := get_viewport().get_mouse_position()
	var dir := target - origin
	# Control points bow the curve toward the source so it arcs upward — feels
	# more like a casting gesture than a laser.
	var ctrl1 := origin + Vector2(dir.x * 0.15, -180.0)
	var ctrl2 := target + Vector2(0.0, 80.0)
	var points := PackedVector2Array()
	var steps := 28
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var pt := _bezier_cubic(origin, ctrl1, ctrl2, target, t)
		points.append(pt)
	_targeting_arrow.points = points
	# Position + rotate the arrowhead at the tip, facing the curve's tangent.
	_targeting_arrow_head.position = target
	if points.size() >= 2:
		var tangent: Vector2 = points[points.size() - 1] - points[points.size() - 2]
		if tangent.length_squared() > 0.01:
			_targeting_arrow_head.rotation = tangent.angle()


func _bezier_cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3


func _bezier_quad(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return (u * u) * p0 + (2.0 * u * t) * p1 + (t * t) * p2


func _card_center(card: Control) -> Vector2:
	# Screen-space centre of a battlefield card. Cards live in the board layer but
	# their global_position maps 1:1 onto the HUD CanvasLayer (which only carries a
	# shake offset), so this is also the correct point for HUD-parented VFX.
	return card.global_position + card.size * card.scale * 0.5


func _play_attack_tracer(from_pos: Vector2, to_pos: Vector2, attacker_is_enemy: bool) -> void:
	# A brief, bowed streak from attacker to target so the eye can follow each blow
	# during the now-staggered swing. Gold = player strike, ember-red = enemy.
	# Self-frees; no await needed by the caller.
	if _hud_layer == null:
		return
	var line := Line2D.new()
	line.width = 6.0
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 230
	line.default_color = Color(1.0, 0.42, 0.28, 0.95) if attacker_is_enemy else Color(1.0, 0.82, 0.34, 0.95)
	# Thin at the attacker, fat at the target — reads as a thrown strike landing.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
	var mid := (from_pos + to_pos) * 0.5
	var perp := (to_pos - from_pos).orthogonal().normalized() * 22.0
	var ctrl := mid + perp
	var pts := PackedVector2Array()
	var steps := 16
	for i in range(steps + 1):
		pts.append(_bezier_quad(from_pos, ctrl, to_pos, float(i) / float(steps)))
	line.points = pts
	_hud_layer.add_child(line)
	var tw := line.create_tween()
	tw.tween_interval(0.05)
	tw.tween_property(line, "modulate:a", 0.0, 0.16).set_ease(Tween.EASE_IN)
	tw.tween_callback(line.queue_free)


func _play_pierce_lance(from_pos: Vector2, to_pos: Vector2) -> void:
	# A bright, dead-straight lance for a piercing kill — skewers through the slain
	# victim and carries on into the column behind it, then thins out and fades.
	if _hud_layer == null:
		return
	var line := Line2D.new()
	line.width = 5.0
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 232
	line.default_color = Color(1.0, 0.96, 0.72, 1.0)
	line.points = PackedVector2Array([from_pos, to_pos])
	_hud_layer.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "width", 1.0, 0.18)
	tw.parallel().tween_property(line, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(line.queue_free)


func spawn_ash_burst(global_pos: Vector2, color: Color, amount: int = 26) -> void:
	# One-shot rising ember/ash burst, parented to the HUD layer so it survives the
	# source card being freed. Used by the sacrifice ritual and piercing exit spark.
	var parent: Node = _hud_layer if _hud_layer != null else self
	var p := CPUParticles2D.new()
	p.position = global_pos
	p.z_index = 215
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = amount
	p.lifetime = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 38.0
	p.gravity = Vector2(0, -45.0)  # embers drift upward
	p.initial_velocity_min = 45.0
	p.initial_velocity_max = 120.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = color
	p.emitting = true
	parent.add_child(p)
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _update_damage_prediction() -> void:
	# While targeting, peek at the card the cursor is over and show "-N" or
	# "LETHAL!" above it so the player can read the outcome before clicking.
	if _prediction_label == null or _targeting_data.is_empty():
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var hovered_card: Control = _find_hovered_target_card(mouse_pos)
	if hovered_card == null:
		_prediction_label.visible = false
		return
	var spell := _targeting_data.get("spell", {}) as Dictionary
	var spell_type: String = spell.get("type", "")
	var custom_id: String = spell.get("id", "")
	var raw_value: int = int(spell.get("value", 0))
	var text := ""
	var color := Color(1.0, 0.85, 0.30)
	if spell_type == "damage" or (spell_type == "custom" and custom_id in ["reckless_charge", "lightning", "pillage", "fuel_the_pyre", "holy_smite"]):
		var dmg: int = _predicted_damage_against(hovered_card, spell_type, custom_id, raw_value)
		if dmg >= hovered_card.current_hp:
			text = "LETHAL!"
			color = Color(1.0, 0.30, 0.20)
		else:
			text = "-%d" % dmg
			color = Color(1.0, 0.40, 0.20)
	elif spell_type == "heal":
		var miss: int = int(hovered_card.card_data.get("hp", hovered_card.current_hp)) - int(hovered_card.current_hp)
		var heal: int = mini(raw_value, miss)
		text = "+%d HP" % heal
		color = Color(0.50, 1.0, 0.55)
	elif spell_type == "buff_atk":
		text = "+%d ATK" % raw_value
		color = Color(1.0, 0.85, 0.30)
	elif spell_type == "buff_hp" or custom_id == "barricade":
		text = "+%d HP" % raw_value
		color = Color(0.55, 0.85, 1.0)
	else:
		_prediction_label.visible = false
		return
	_prediction_label.text = text
	_prediction_label.add_theme_color_override("font_color", color)
	_prediction_label.visible = true
	# Anchor above the target card's center.
	var rect := hovered_card.get_global_rect()
	# Wait until the label has measured its text so we can center it.
	_prediction_label.size = Vector2.ZERO
	_prediction_label.reset_size()
	var lbl_size: Vector2 = _prediction_label.size
	_prediction_label.position = Vector2(
		rect.get_center().x - lbl_size.x * 0.5,
		rect.position.y - lbl_size.y - 8)


func _find_hovered_target_card(pos: Vector2) -> Control:
	# Returns the first card under the cursor that matches the active spell's
	# targeting rules, or null if the cursor isn't over a valid target.
	var targeting: String = _targeting_data.get("targeting", "none")
	if targeting in ["enemy_creature", "any_creature", "any"]:
		for e in _all_enemy_creatures():
			if _is_click_on_card(pos, e):
				return e
	if targeting in ["friendly_creature", "any_creature", "any"]:
		for p in _all_player_creatures():
			if _is_click_on_card(pos, p):
				return p
	return null


func _predicted_damage_against(card: Control, spell_type: String, custom_id: String, raw_value: int) -> int:
	# Mirror the relic / armored math from _resolve_spell so the prediction
	# matches the actual outcome. Worn Spellbook adds 1 to plain "damage", and
	# Armored absorbs 1 per hit (clamped to 0).
	var dmg := raw_value
	if spell_type == "damage" and _has_relic("worn_spellbook"):
		dmg += 1
	if custom_id == "reckless_charge":
		dmg = 3 + (1 if _has_relic("worn_spellbook") else 0)
	elif custom_id == "lightning":
		dmg = 2
	elif custom_id == "pillage":
		dmg = 3 + (1 if _has_relic("worn_spellbook") else 0)
	elif custom_id == "fuel_the_pyre":
		dmg = 999  # Kills target outright (sets up "LETHAL!" automatically)
	elif custom_id == "holy_smite":
		# Equal to the target's missing HP — full creature takes nothing.
		dmg = maxi(0, int(card.card_data.get("hp", card.current_hp)) - int(card.current_hp))
	if card.has_method("has_keyword") and card.has_keyword("armored"):
		dmg = maxi(0, dmg - 1)
	return dmg


func _pulse_mana_label(amount: int) -> void:
	# Brief blue flash + scale punch on the mana counter so a spend reads as a
	# deliberate cost paid, not just a number that quietly ticked.
	if _mana_label == null or amount <= 0:
		return
	var rest_color: Color = _mana_label.get_theme_color("font_color")
	var rest_scale := _mana_label.scale
	_mana_label.pivot_offset = _mana_label.size * 0.5
	var tw := _mana_label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_mana_label, "scale", rest_scale * 1.25, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c: Color):
			_mana_label.add_theme_color_override("font_color", c),
		Color(0.55, 0.80, 1.0), rest_color, 0.32)
	tw.chain().tween_property(_mana_label, "scale", rest_scale, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Floating "-N" near the orb.
	var pos := _mana_label.get_global_rect().get_center() + Vector2(0, -10)
	spawn_floating_number(pos, "-%d" % amount, Color(0.55, 0.80, 1.0), false)


func _play_spell_cast_vfx(spell_type: String, target: Control) -> void:
	# Route a spell to its visual burst. Color/position pick the spot that reads
	# best for that effect: targeted spells burst on the target, AoE bursts at
	# screen center, face-damage at the enemy hero label, etc. Non-attack spells
	# also briefly flash the screen so buff/heal/draw feel like a "cast".
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var pos := center
	var color := Color(1.0, 0.55, 0.2)
	if target != null and is_instance_valid(target):
		pos = target.get_global_rect().get_center()
	match spell_type:
		"damage":
			color = Color(1.0, 0.40, 0.18)
		"damage_face", "damage_all_enemies":
			color = Color(1.0, 0.30, 0.12)
			if spell_type == "damage_face" and _enemy_hp_label != null:
				pos = _enemy_hp_label.get_global_rect().get_center()
			elif spell_type == "damage_all_enemies":
				pos = Vector2(vp.x * 0.5, vp.y * 0.35)
		"damage_all":
			color = Color(1.0, 0.20, 0.18)
			pos = center
		"buff_atk", "buff_all_atk":
			color = Color(1.0, 0.85, 0.30)
		"buff_hp", "heal":
			color = Color(0.50, 1.0, 0.55)
		"draw":
			color = Color(0.55, 0.78, 1.0)
			pos = Vector2(120.0, vp.y * 0.60)
		"custom":
			# Custom spells handle their own per-id flavor below; default burst
			# at target so the cast still reads.
			color = Color(0.80, 0.55, 1.0)
		_:
			color = Color(1.0, 0.70, 0.30)
	spawn_spell_burst(pos, color)
	if AudioBank != null:
		AudioBank.play_sfx("spell_cast")


func spawn_spell_burst(global_pos: Vector2, color: Color) -> void:
	# One-shot particle pop where a spell resolves. CPUParticles so it renders on
	# every backend. Self-frees once the burst finishes.
	var burst := CPUParticles2D.new()
	burst.position = global_pos
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emitting = true
	burst.amount = 18
	burst.lifetime = 0.55
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.initial_velocity_min = 90.0
	burst.initial_velocity_max = 210.0
	burst.gravity = Vector2(0, 140.0)
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.5
	burst.color = color
	burst.z_index = 150
	var parent: Node = _hud_layer if _hud_layer != null else self
	parent.add_child(burst)
	get_tree().create_timer(1.0).timeout.connect(burst.queue_free)


func _show_encounter_intro(is_boss: bool) -> void:
	# Big dramatic banner with encounter name + passive description that holds
	# for ~1.6s before combat begins. Awaitable so _ready blocks on the intro
	# completing — the round banner / actual play follows after.
	if _hud_layer == null:
		return
	var vp := get_viewport_rect().size

	# Backdrop dimmer for theatre — fades in, holds, fades out with the banner.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 245
	_hud_layer.add_child(dim)

	# Container that holds name + subtitle. Stack vertically, centered.
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 14)
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 246
	holder.modulate.a = 0.0
	_hud_layer.add_child(holder)

	var prefix_label := Label.new()
	prefix_label.text = "— BOSS —" if is_boss else "— ELITE —"
	prefix_label.add_theme_font_size_override("font_size", 26)
	prefix_label.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.20) if is_boss else Color(1.0, 0.78, 0.30))
	prefix_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	prefix_label.add_theme_constant_override("outline_size", 6)
	prefix_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prefix_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(prefix_label)

	var name_label := Label.new()
	name_label.text = _encounter_name if _encounter_name != "" else "UNKNOWN FOE"
	name_label.add_theme_font_size_override("font_size", 86 if is_boss else 72)
	name_label.add_theme_color_override("font_color", IVORY)
	name_label.add_theme_color_override("font_outline_color",
		Color(0.55, 0.16, 0.04, 0.95))
	name_label.add_theme_constant_override("outline_size", 10)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(name_label)

	if _encounter_passive_desc != "":
		var desc_label := Label.new()
		desc_label.text = _encounter_passive_desc
		desc_label.add_theme_font_size_override("font_size", 20)
		desc_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.65))
		desc_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		desc_label.add_theme_constant_override("outline_size", 5)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(vp.x * 0.62, 0)
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(desc_label)

	# Pivot pivot — make the title pop with a tiny scale overshoot.
	holder.pivot_offset = Vector2(vp.x * 0.5, vp.y * 0.5)
	holder.scale = Vector2(0.88, 0.88)

	if AudioBank != null:
		AudioBank.play_sfx("turn_start", 0.0, 3.0)  # louder than normal turn

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dim, "color:a", 0.55, 0.28)
	tw.tween_property(holder, "modulate:a", 1.0, 0.32)
	tw.tween_property(holder, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold the intro on screen — bosses get longer for the player to read the
	# passive description; elites are quicker.
	tw.chain().tween_interval(1.5 if is_boss else 1.0)
	tw.chain().tween_property(dim, "color:a", 0.0, 0.32)
	tw.parallel().tween_property(holder, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(dim.queue_free)
	tw.parallel().tween_callback(holder.queue_free)
	await tw.finished


func _show_turn_banner() -> void:
	# Big "ROUND N" title that pops in, holds, and fades — the beat that tells
	# the player a fresh turn has begun. Lives on the HUD layer, ignores input.
	if _hud_layer == null:
		return
	if AudioBank != null:
		AudioBank.play_sfx("turn_start")
	var vp := get_viewport_rect().size
	var banner := Label.new()
	banner.text = "ROUND %d" % round_number
	banner.add_theme_font_size_override("font_size", 70)
	banner.add_theme_color_override("font_color", IVORY)
	banner.add_theme_color_override("font_outline_color", Color(0.55, 0.16, 0.04, 0.95))
	banner.add_theme_constant_override("outline_size", 9)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 250
	banner.size = Vector2(vp.x, 96)
	banner.position = Vector2(0, vp.y * 0.30)
	banner.pivot_offset = Vector2(vp.x * 0.5, 48)
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.82, 0.82)
	_hud_layer.add_child(banner)
	var tw := banner.create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.55)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.38)
	tw.chain().tween_callback(banner.queue_free)


func _show_info(msg: String) -> void:
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	get_tree().create_timer(2.0).timeout.connect(func(): _info_label.text = "")


func _unhandled_input(event: InputEvent) -> void:
	# Tab / ? / Esc are intercepted in _input so focus traversal doesn't swallow
	# them. Only end-turn shortcut remains here.
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E, KEY_ENTER:
				_on_end_turn()
