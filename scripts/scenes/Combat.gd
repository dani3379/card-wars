extends Control
## Combat.gd — design-doc combat: sequential + Swift, floop, sacrifice, spells.
## Round flow: draw → play/sacrifice/floop → Swift phase → player attacks →
## enemy attacks → deaths → discard → enemy places → passives → new round.
## Combat happens every round (no setup-only round).

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"

enum Phase { PLAYER_TURN, RESOLVING, GAME_OVER }
var phase := Phase.PLAYER_TURN
var round_number := 0

const BASE_MAX_MANA: int = 3
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
var _cards_played_this_turn: int = 0
var _last_spell_played_this_turn: Dictionary = {}
var _bonus_mana_next_turn: int = 0
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
var _escalation_active: bool = false
var _sundial_count: int = 0

# Board UI
var _board_bg: ColorRect
var _player_slots: Array[Control] = []      # front-row slots (legacy name)
var _enemy_slots: Array[Control] = []       # front-row slots (legacy name)
var _player_back_slots: Array[Control] = [] # back-row slots (4x4)
var _enemy_back_slots: Array[Control] = []  # back-row slots (4x4)
var _hand_container: Control
var _midline: ColorRect

# HUD additions for 4x4 polish.
var _deck_count_label: Label
var _discard_count_label: Label
var _floop_tutorial_shown: bool = false

# HUD
var _hud_layer: CanvasLayer
var _phase_label: Label
var _player_hp_label: Label
var _enemy_hp_label: Label
var _mana_label: Label
var _turn_label: Label
var _info_label: Label
var _floor_label: Label
var _end_turn_btn: Button
var _sacrifice_btn: Button
var _relic_panel: HBoxContainer

# Board container (no effects)
var _board_container: Control

# Colors
# Colors — mirror Theme autoload for local use
const PARCHMENT_BG := Color(0.12, 0.09, 0.07, 0.94)
const PARCHMENT_BORDER := Color(0.60, 0.45, 0.22, 1.0)
const GILT := Color(0.82, 0.66, 0.30, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const BOARD_BG := Color(0.075, 0.065, 0.055, 1.0)
const LANE_BORDER := Color(0.38, 0.28, 0.15, 0.85)


func _ready() -> void:
	set_process(false)
	_rebuild_relic_cache()
	_floop_tutorial_shown = UserSettings.floop_tutorial_seen
	_setup_fight_state()
	_build_board()
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
	_start_round()


func _prebake_hand_textures() -> void:
	# Build a unique-card list from _player_draw_pile (Array[String]) so we
	# bake each card identity once even if the deck has duplicates.
	var seen := {}
	var to_bake: Array = []
	for cid in _player_draw_pile:
		if seen.has(cid):
			continue
		seen[cid] = true
		to_bake.append(CardDB.get_card_data(cid))
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
			enemy_max_hp = enc.hp
			_encounter_passive = enc.get("passive_id", "")
			_encounter_name = enc.get("name", "")
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
			enemy_max_hp = [12, 17, 21][act - 1] + randi() % 4
		"elite":
			enemy_max_hp = [18, 26, 30][act - 1] + randi() % 4
		"boss":
			enemy_max_hp = [25, 32, 40][act - 1]
	_build_legacy_enemy_deck(act)
	enemy_hp = enemy_max_hp


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


func _init_decks() -> void:
	_player_draw_pile.clear()
	_player_discard_pile.clear()
	for id in RunState.deck:
		_player_draw_pile.append(id)
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
	# Fill front row first (left-to-right shuffled) then back row.
	var fill_order: Array = []
	var front_order = [0, 1, 2, 3]
	front_order.shuffle()
	for l in front_order:
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
		var card_data = _enemy_deck.pop_front()
		_place_enemy_card(card_data, slot.lane, slot.row)
		placed += 1


# =====================================================================
#  ROUND FLOW
# =====================================================================

func _start_round() -> void:
	round_number += 1
	_sacrifice_used_this_turn = false
	_first_creature_played = false
	_first_spell_this_turn = false
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

	# Draw
	var draw_count = HAND_DRAW_PER_TURN
	if _has_relic("couriers_bag") and round_number == 1:
		draw_count += 1
	for i in draw_count:
		draw_one()

	_end_turn_btn.disabled = false
	# Sacrifice button removed from the HUD; guard remaining references.
	if _sacrifice_btn != null:
		_sacrifice_btn.visible = true
		_sacrifice_btn.disabled = _sacrifice_used_this_turn
	_update_hud()


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _targeting_spell != null:
		_cancel_targeting()
		return
	if _sacrifice_mode:
		_cancel_sacrifice()
		return
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
				# Adjacent enemy lanes
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4:
						var adj_opp = enemy_field[adj_lane]
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
						var cdata = CardDB.get_card_data(idx)
						if cdata.get("type", "") == "creature":
							discard_creatures += 1
					opp.take_damage(discard_creatures)
			"discard_top_damage":
				if _player_draw_pile.size() > 0:
					var top_idx = _player_draw_pile.pop_front()
					var top_data = CardDB.get_card_data(top_idx)
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
					opp.set_meta("stunned", true)

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
						var cdata = CardDB.get_card_data(idx)
						if cdata.get("type", "") == "creature":
							creature_indices.append(idx)
					if creature_indices.size() > 0:
						var pick = creature_indices[randi() % creature_indices.size()]
						_player_discard_pile.erase(pick)
						var cdata = CardDB.get_card_data(pick)
						_draw_card(cdata.id)
			"gain_gold":
				if not is_enemy:
					RunState.gain_gold(floop_data.value)
			"gain_mana":
				if not is_enemy:
					player_mana += floop_data.value
					_update_hud()
			"buff_adjacent_atk":
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4:
						var adj = friendly_field[adj_lane]
						if adj != null:
							adj.temp_atk_buff += floop_data.value
							adj.update_stat_display()
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

	# Snapshot which lanes had a front-row blocker at start of combat. Used for
	# face-damage decisions when the blocker dies mid-combat.
	var player_front_empty_at_start: Array[bool] = []
	var enemy_front_empty_at_start: Array[bool] = []
	for i in range(LANES_PER_ROW):
		player_front_empty_at_start.append(_player_field[i] == null)
		enemy_front_empty_at_start.append(_enemy_field[i] == null)

	# Mark stunned creatures as already-attacked so they skip combat (both rows).
	for c in _all_creatures_both_sides():
		if c.get_meta("stunned", false):
			c.has_attacked_this_turn = true

	# SWIFT PHASE — front row first, then back row (back only if column front empty).
	for lane_idx in range(LANES_PER_ROW):
		_resolve_swift_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
		_resolve_swift_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		_resolve_swift_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)
		_resolve_swift_attack(lane_idx, ROW_BACK, true, player_front_empty_at_start)

	# PLAYER ATTACK PHASE — front row attacks first, back row attacks last
	# (back row only acts if its column's front is empty).
	for lane_idx in range(LANES_PER_ROW):
		_resolve_column_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		_resolve_column_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)

	# ENEMY ATTACK PHASE — mirror, also front-first.
	for lane_idx in range(LANES_PER_ROW):
		_resolve_column_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		_resolve_column_attack(lane_idx, ROW_BACK, true, player_front_empty_at_start)

	# Process ranged attacks (prefer back-row targets, then front, then face).
	_resolve_ranged_attacks()

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
	# Attempt to attack from (is_enemy, row, lane_idx). Back-row attackers only
	# act if their own front in this column is gone — front blocks back.
	var attacker_field = _row_array(is_enemy, row)
	var attacker = attacker_field[lane_idx]
	if attacker == null or not is_instance_valid(attacker):
		return
	if attacker.current_hp <= 0 or attacker.has_attacked_this_turn:
		return
	if not attacker.can_attack():
		return
	if row == ROW_BACK and _row_array(is_enemy, ROW_FRONT)[lane_idx] != null:
		# Twin Edge: player back-row can attack even with a friendly blocker.
		# Damage is halved (min 1) to keep this from being too strong.
		if not is_enemy and _has_relic("twin_edge"):
			pass  # Allow through with halving applied below.
		else:
			return  # Own front-row creature is blocking us.

	# Pick target: opposing front in this column, else opposing back, else face.
	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]
	if opp_front != null and opp_front.current_hp > 0:
		_creature_attacks_creature(attacker, opp_front, lane_idx, is_enemy)
	elif opp_back != null and opp_back.current_hp > 0:
		# Front died or never existed — back row is now exposed.
		_creature_attacks_creature(attacker, opp_back, lane_idx, is_enemy)
	elif opponent_front_empty[lane_idx]:
		# Empty column at start of combat → face damage.
		_creature_hits_face(attacker, lane_idx, is_enemy)


func _resolve_swift_attack(lane_idx: int, row: int, is_enemy: bool,
		opponent_front_empty: Array[bool]) -> void:
	var attacker_field = _row_array(is_enemy, row)
	var card = attacker_field[lane_idx]
	if card == null or not card.has_keyword("swift") or card.has_attacked_this_turn or not card.can_attack():
		return
	if row == ROW_BACK and _row_array(is_enemy, ROW_FRONT)[lane_idx] != null:
		return  # Back-row swift still blocked by our own front.
	card.has_attacked_this_turn = true

	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]
	var opponent: Control = null
	if opp_front != null:
		opponent = opp_front
	elif opp_back != null:
		opponent = opp_back

	if opponent != null:
		var atk = _effective_attack(card, lane_idx, is_enemy)
		_apply_thorns(opponent, card, is_enemy)
		opponent.take_damage(atk)
		if opponent.current_hp <= 0 and (card.has_keyword("piercing") or (is_enemy and _has_encounter_passive_keyword(card, "piercing"))):
			_apply_piercing_overflow(card, opponent, lane_idx, is_enemy)
	elif opponent_front_empty[lane_idx]:
		_creature_hits_face(card, lane_idx, is_enemy)


func _apply_piercing_overflow(attacker: Control, victim: Control, lane_idx: int, is_enemy: bool) -> void:
	# Piercing kill: overflow damage spills to the next creature in the same
	# opposing column (front→back), then to face if nothing left in column.
	var excess = abs(victim.current_hp)
	var bonus = 1 if (not is_enemy and _has_relic("piercing_crown")) else 0
	var total = excess + bonus
	if total <= 0:
		return
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
	var atk = _effective_attack(attacker, lane_idx, attacker_is_enemy)
	# Marked/enrage vulnerability bonus damage
	if defender.get_meta("marked", false):
		atk += 2
	if defender.get_meta("enrage_vulnerable", false):
		atk += 1
	_apply_thorns(defender, attacker, attacker_is_enemy)
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
	defender.take_damage(atk)
	attacker.has_attacked_this_turn = true

	if defender.current_hp <= 0 and (attacker.has_keyword("piercing") or (attacker_is_enemy and _has_encounter_passive_keyword(attacker, "piercing"))):
		_apply_piercing_overflow(attacker, defender, lane_idx, attacker_is_enemy)

	# Vampire Lord passive: heal 2 and +1 ATK on kill
	if not attacker_is_enemy and attacker.card_data.get("passive", "") == "vampire_lord" and defender.current_hp <= 0:
		player_hp = mini(player_hp + 2, player_max_hp)
		attacker.current_atk += 1
		attacker.update_stat_display()


func _creature_hits_face(card: Control, lane_idx: int, is_enemy: bool) -> void:
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
				if back_targets.size() > 0:
					back_targets[randi() % back_targets.size()].take_damage(atk)
				elif front_targets.size() > 0:
					front_targets[randi() % front_targets.size()].take_damage(atk)
				else:
					if is_enemy:
						damage_player_hero(atk)
					else:
						damage_enemy_hero(atk)


func _apply_thorns(defender: Control, attacker: Control, attacker_is_enemy: bool) -> void:
	if (defender.has_keyword("thorns") or (not attacker_is_enemy and _has_encounter_passive_keyword(defender, "thorns"))) and defender.current_hp > 0:
		var thorns_dmg = 1
		if not attacker_is_enemy and _has_relic("briar_amulet"):
			thorns_dmg = 2
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
					_player_discard_pile.append(card.card_id)
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
					var atk = pf.current_atk + pf.temp_atk_buff
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
	card.summoned_this_turn = true
	card.current_lane = lane_idx
	card.current_row = row
	_row_array(true, row)[lane_idx] = card
	var slot = _slot_array(true, row)[lane_idx]
	_slot_set_card(slot, card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	if _has_relic("philosophers_stone"):
		card.current_atk += 1
		card.update_stat_display()
	KeywordEffects.dispatch_on_enter(card, lane_idx, true, self)
	_dispatch_encounter_on_enter(data, lane_idx)
	# Show the freshly-placed creature's intent immediately so it's never
	# blank between placement and the next intent-assignment pass.
	_update_intent_display(card, "ATK")


func _short_pause(_duration: float) -> void:
	await get_tree().process_frame


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

	# 4x4: derive both lane and row from the drop position. If the targeted slot
	# is occupied, replace the creature there (mirrors pre-4x4 behavior).
	var drop = _nearest_player_slot(card.global_position)
	var lane_idx: int = drop.lane
	var row: int = drop.row
	var field = _row_array(false, row)
	if field[lane_idx] != null:
		var old = field[lane_idx]
		_player_discard_pile.append(old.card_id)
		old.queue_free()
		field[lane_idx] = null

	player_mana -= cost
	_cards_played_this_turn += 1
	_hand.erase(card)
	_hand_container.remove_child(card)

	card.is_on_battlefield = true
	card.summoned_this_turn = true
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
		_first_spell_this_turn = true
		_cards_played_this_turn += 1
		_hand.erase(card)
		_hand_container.remove_child(card)
		_targeting_spell = card
		_targeting_data = card.card_data
		_show_info("Click a target...")
		_update_hud()
		return

	# Non-targeted spell: resolve immediately
	player_mana -= cost
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
				target.current_hp = mini(target.current_hp + value, target.card_data.hp)
				target.update_stat_display()
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
				_player_discard_pile.append(c.card_id)
				_hand_container.remove_child(c)
				c.queue_free()
				discarded += 1
			if discarded > 0:
				player_mana += 1
		"scrap":
			if _hand.size() > 0:
				var c = _hand.pop_back()
				_player_discard_pile.append(c.card_id)
				_hand_container.remove_child(c)
				c.queue_free()
				player_mana += 1
		"gambit":
			var to_discard = mini(3, _hand.size())
			for i in to_discard:
				if _hand.size() > 0:
					var c = _hand.pop_back()
					_player_discard_pile.append(c.card_id)
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
				_player_discard_pile.append(c.card_id)
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
		_:
			pass

	_update_hud()


func _after_spell(card: Control) -> void:
	if card.has_keyword("exhaust"):
		_exhaust_pile.append(card.card_id)
	else:
		_player_discard_pile.append(card.card_id)
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
				return
	if targeting in ["friendly_creature", "any_creature", "any"]:
		for p in _all_player_creatures():
			if _is_click_on_card(pos, p):
				_resolve_spell(_targeting_data, p, p.current_lane)
				_after_spell(_targeting_spell)
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
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

	# Butcher's Cleaver relic
	if _has_relic("butchers_cleaver"):
		# Next creature this turn gets +2 ATK
		pass  # Simplified: handled via flag

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
	_show_info("FLOOP: Skip this creature's attack to use its special ability instead.")


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


func _draw_card(card_id: String) -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.card_data = CardDB.get_card_data(card_id)
	# Use the baked-overlay layout if CardTextureCache has the texture; falls
	# back to v4 silently on cache miss (rare — happens only if the card was
	# added to the draw pile after _prebake_hand_textures ran).
	card.live_baked_mode = true
	_hand_container.add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))
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
	const CARD_W := 180.0
	const CARD_H := 252.0
	# Resting scale — cards in the hand render at 80% of their native size
	# so more cards fit comfortably and the fan is less cramped at the
	# 10-card cap. Hover scales back to 1.15 (a 1.44x visual pop). Combined
	# with the peek-below positioning, this is the Hearthstone-on-Switch
	# silhouette: a row of trimmed thumbnails at the bottom that leap up
	# and grow when you mouse one.
	const REST_SCALE := Vector2(0.8, 0.8)
	# How far below the container's bottom edge the cards' bottom-centres
	# anchor. Cards at scale 0.8 have a rendered height of ~202 px; with
	# the bottom 60 px past the container edge, roughly 70% of the card
	# stays visible at rest, art + name + cost. The ATK/HP orbs hang past
	# the card silhouette by another ~7 px scaled, so they're hidden too.
	# Hover lifts the card by 80 px (Card2D._on_mouse_entered) bringing it
	# fully into view plus an elevation pop above its neighbours.
	const PEEK := 60.0

	# Card-to-card centre spacing. Wide when there's room (cards don't touch);
	# clamps when n is large so the hand fits the container width minus a
	# half-card margin on each side. Tightened relative to the all-1.0-scale
	# pass since each card now renders 36 px narrower (0.8 × 180).
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
			_player_discard_pile.append(card.card_id)
			card.queue_free()
	_hand = to_keep
	# Reset temp buffs on every creature, both rows, both sides.
	for c in _all_creatures_both_sides():
		c.temp_atk_buff = 0
		c.has_attacked_this_turn = false
		c.has_flooped_this_turn = false
		c.summoned_this_turn = false
		c.update_stat_display()


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
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	enemy_hp -= amount
	screen_shake(clampf(amount * 2.0, 4.0, 15.0))
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
		token_hp += 1
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
	card.summoned_this_turn = true
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

func _check_game_over() -> void:
	if player_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "DEFEAT"
		_phase_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
		RunState.hero_hp = 0
		get_tree().create_timer(1.5).timeout.connect(func():
			RunState.end_run(false)
			get_tree().change_scene_to_file(GAMEOVER_SCENE)
		)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "VICTORY!"
		_phase_label.add_theme_color_override("font_color", Color(0.30, 0.92, 0.40))
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
					get_tree().change_scene_to_file(GAMEOVER_SCENE)
				else:
					RunState.advance_act()
					get_tree().change_scene_to_file(REWARD_SCENE)
			)
		else:
			get_tree().create_timer(1.0).timeout.connect(func():
				get_tree().change_scene_to_file(REWARD_SCENE)
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


func _update_intent_display(card: Control, intent: String) -> void:
	## Renders an intent badge above every enemy creature so the player can
	## always read "what is this thing about to do." STS shows attack damage
	## for ATK; everything else gets the same colored chip.
	var label_text: String = intent
	if intent == "ATK" or intent == "":
		# Default attack shows damage instead of the word — much more useful.
		var dmg: int = card.current_atk + card.temp_atk_buff
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
			pass
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
				if card.has_meta("stunned"):
					card.remove_meta("stunned")
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
				damage_player_hero(highest.current_atk + highest.temp_atk_buff)


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
				return (card.current_atk + card.temp_atk_buff) >= 4
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
		var atk = c.current_atk + c.temp_atk_buff
		if atk > best_atk:
			best_atk = atk
			best = c
	return best


func _highest_atk_enemy_creature() -> Control:
	var best: Control = null
	var best_atk := -1
	for c in _all_enemy_creatures():
		var atk = c.current_atk + c.temp_atk_buff
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
	_hand_container.offset_left = 215
	_hand_container.offset_right = -215
	_hand_container.anchor_top = 1.0
	_hand_container.anchor_bottom = 1.0
	_hand_container.offset_top = -280
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
	_board_container.add_child(_hand_container)

	# ── Board zone: occupies the center between the corner banners.
	# Left edge clears the enemy/player banner column (x≈14–194 + buffer).
	# Right edge clears the encounter scroll (top-right, ≈x = width-334)
	# and the mana post + discard pile column.
	var board_zone := Control.new()
	board_zone.anchor_left = 0.0
	board_zone.anchor_right = 1.0
	board_zone.anchor_top = 0.0
	board_zone.anchor_bottom = 1.0
	board_zone.offset_left = 220
	board_zone.offset_right = -340
	board_zone.offset_top = 24
	board_zone.offset_bottom = -290
	board_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_container.add_child(board_zone)

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
	enemy_inner.add_theme_constant_override("separation", 4)
	enemy_zone.add_child(enemy_inner)

	var enemy_back_lanes := _make_row_container("BACK", Color(0.85, 0.45, 0.35, 0.35))
	enemy_inner.add_child(enemy_back_lanes)

	var enemy_front_lanes := _make_row_container("FRONT", Color(0.85, 0.55, 0.40, 0.65))
	enemy_inner.add_child(enemy_front_lanes)

	# Midline — sits exactly between the two halves of board_zone. z_index
	# is set negative so it sits behind cards instead of cutting across them.
	_midline = ColorRect.new()
	_midline.anchor_left = 0.0
	_midline.anchor_right = 1.0
	_midline.anchor_top = 0.5
	_midline.anchor_bottom = 0.5
	_midline.offset_top = -2
	_midline.offset_bottom = 2
	_midline.color = Color(GILT.r, GILT.g, GILT.b, 0.0)
	_midline.z_index = -1
	_midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	player_inner.add_theme_constant_override("separation", 4)
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
	const SLOT_W := 140
	const SLOT_H := 145
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.clip_contents = false

	# (Interior "well" ColorRect removed — empty slots now show the painted
	# battlefield background through them. Only the faint frame outline remains.)

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
		# Frames are almost invisible — just enough to hint at slot positions
		# so the player can read where to drop a card. The painted battlefield
		# is the dominant visual.
		var tint: Color
		if is_enemy:
			tint = Color(0.90, 0.45, 0.32, 0.15) if row == ROW_FRONT \
				else Color(0.62, 0.34, 0.24, 0.10)
		else:
			tint = Color(0.95, 0.78, 0.32, 0.15) if row == ROW_FRONT \
				else Color(0.68, 0.55, 0.22, 0.10)
		frame.modulate = tint
		slot.add_child(frame)

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
	var cell = _slot_cell(slot)
	if cell == null:
		slot.add_child(card)
		return
	for child in cell.get_children():
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
	card.summoned_this_turn = true
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


# =====================================================================
#  HUD
# =====================================================================

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 12
	add_child(_hud_layer)
	_build_left_info_column()
	_build_end_turn_button()


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
	# Top-left: Vrubel's "Demon Seated" (1890) cropped to a vertical banner,
	# with the enemy HP medallion at its base.
	const W := 180
	const H := 220
	var banner := Control.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 0.0
	banner.anchor_top = 0.0
	banner.anchor_bottom = 0.0
	banner.offset_left = 14
	banner.offset_top = 14
	banner.offset_right = 14 + W
	banner.offset_bottom = 14 + H
	banner.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(banner)

	var demon_tex: Texture2D = load("res://assets/portraits/enemy_demon.jpg")
	if demon_tex != null:
		var img := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = demon_tex
		# Demon's torso + head, center-right of the landscape painting.
		atlas.region = Rect2(900, 0, 1500, 1712)
		img.texture = atlas
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(img)

	# Painted border so the banner reads as a framed portrait, not a clipped
	# screenshot. Reuses the existing slot frame for consistency.
	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	hp.offset_top = -56
	hp.offset_bottom = -10
	hp.offset_left = 14
	hp.offset_right = -14
	banner.add_child(hp)


func _build_player_banner_diegetic() -> void:
	# Bottom-left: Dürer's "Knight, Death and the Devil" (1513). Full
	# engraving — knight, Death-with-hourglass, demon, skull — establishes
	# the player's identity in one master print.
	const W := 180
	const H := 220
	var banner := Control.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 0.0
	banner.anchor_top = 1.0
	banner.anchor_bottom = 1.0
	banner.offset_left = 14
	banner.offset_top = -(H + 300)
	banner.offset_right = 14 + W
	banner.offset_bottom = -300
	banner.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(banner)

	var knight: Texture2D = load("res://assets/portraits/player_knight.jpg")
	if knight != null:
		var img := TextureRect.new()
		img.texture = knight
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(img)

	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	hp.offset_top = -56
	hp.offset_bottom = -10
	hp.offset_left = 14
	hp.offset_right = -14
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

	var lbl := _make_text_label("%d / %d" % [hp, max_hp], 22, IVORY)
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
	# Top-right: parchment crop (sheet music + blue ribbon from Gijsbrechts'
	# 1662 Vanitas) holding the encounter name + passive description.
	const W := 320
	const H := 200
	var scroll := Control.new()
	scroll.anchor_left = 1.0
	scroll.anchor_right = 1.0
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 0.0
	scroll.offset_left = -(W + 14)
	scroll.offset_top = 14
	scroll.offset_right = -14
	scroll.offset_bottom = 14 + H
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(scroll)

	var vanitas: Texture2D = load("res://assets/portraits/vanitas_source.jpg")
	if vanitas != null:
		var img := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = vanitas
		# Sheet music + blue-ribbon scroll, center-bottom of the painting.
		atlas.region = Rect2(1700, 2600, 2400, 1300)
		img.texture = atlas
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.add_child(img)

	# Slight dark wash so text reads against the parchment crop.
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0.25)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(fade)

	if _slot_frame_tex != null:
		var frame := NinePatchRect.new()
		frame.texture = _slot_frame_tex
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.patch_margin_left = 52
		frame.patch_margin_right = 52
		frame.patch_margin_top = 52
		frame.patch_margin_bottom = 52
		frame.draw_center = false
		frame.modulate = Color(0.85, 0.65, 0.30, 0.85)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.add_child(frame)

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 22
	stack.offset_right = -22
	stack.offset_top = 18
	stack.offset_bottom = -18
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(stack)

	var encounter_text := _encounter_name if _encounter_name != "" \
		else "Floor %d" % RunState.current_floor
	_floor_label = _make_text_label(encounter_text, 16, GILT)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_floor_label)

	_phase_label = _make_text_label("ROUND 1", 20, IVORY)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_phase_label)

	if _encounter_passive != "":
		var enc = EncounterDB.get_encounter(RunState.current_encounter_id)
		var passive := _make_text_label(enc.get("passive_desc", ""), 12,
			Color(0.95, 0.85, 0.55))
		passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(passive)

	_turn_label = _make_text_label("Round 1", 11, Color(0.78, 0.70, 0.50))
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_turn_label)


func _build_mana_post_diegetic() -> void:
	# Bottom-right (above End Turn): row of 3 candles cropped from the Vanitas
	# painting, representing mana. Currently static — lit/dim animation TBD.
	const W := 180
	const H := 150
	var post := Control.new()
	post.anchor_left = 1.0
	post.anchor_right = 1.0
	post.anchor_top = 1.0
	post.anchor_bottom = 1.0
	post.offset_left = -(W + 14)
	post.offset_top = -(H + 86)
	post.offset_right = -14
	post.offset_bottom = -86
	post.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(post)

	var vanitas: Texture2D = load("res://assets/portraits/vanitas_source.jpg")
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 0.0
	row.anchor_bottom = 1.0
	row.offset_bottom = -28
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.add_child(row)

	for i in range(3):
		var candle := TextureRect.new()
		if vanitas != null:
			var atlas := AtlasTexture.new()
			atlas.atlas = vanitas
			# Brass candlestick + lit candle with flame at top, right of the skull.
			atlas.region = Rect2(2820, 1180, 480, 1100)
			candle.texture = atlas
		candle.custom_minimum_size = Vector2(48, 122)
		candle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		candle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		candle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(candle)

	_mana_label = _make_text_label("%d / %d" % [player_mana, player_max_mana],
		18, GameTheme.MANA_BLUE)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_label.anchor_left = 0.0
	_mana_label.anchor_right = 1.0
	_mana_label.anchor_top = 1.0
	_mana_label.anchor_bottom = 1.0
	_mana_label.offset_top = -26
	_mana_label.offset_bottom = -2
	post.add_child(_mana_label)


func _build_piles_diegetic() -> void:
	# Deck pile on the left edge, anchored just below the enemy banner so it
	# sits in the gap between the two banners regardless of screen height.
	# Discard pile mirrors on the right edge below the encounter scroll.
	var deck_box := _make_pile_panel_diegetic("DECK", 0)
	deck_box.anchor_left = 0.0
	deck_box.anchor_right = 0.0
	deck_box.anchor_top = 0.0
	deck_box.anchor_bottom = 0.0
	deck_box.offset_left = 50
	deck_box.offset_right = 50 + 100
	deck_box.offset_top = 250
	deck_box.offset_bottom = 250 + 122
	_hud_layer.add_child(deck_box)

	var disc_box := _make_pile_panel_diegetic("DISCARD", 1)
	disc_box.anchor_left = 1.0
	disc_box.anchor_right = 1.0
	disc_box.anchor_top = 0.0
	disc_box.anchor_bottom = 0.0
	disc_box.offset_left = -(50 + 100)
	disc_box.offset_right = -50
	disc_box.offset_top = 230
	disc_box.offset_bottom = 230 + 122
	_hud_layer.add_child(disc_box)


func _make_pile_panel_diegetic(caption_text: String, kind: int) -> Control:
	# Small card-stack panel: dark inset with a painted border, numeric count
	# overlaid, caption below. Sets _deck_count_label / _discard_count_label
	# so _update_hud() can keep them current.
	var pile := Control.new()
	pile.mouse_filter = Control.MOUSE_FILTER_PASS

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
	return pile


func _make_column_divider() -> ColorRect:
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(GILT.r, GILT.g, GILT.b, 0.40)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return div


func _make_inline_portrait(is_enemy: bool) -> Control:
	# Compact 88px-tall portrait that fits inside the left info column.
	# Uses the encounter boss icon for enemies, horned-helm for the player.
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.07, 0.04, 0.94)
	s.border_color = Color(0.95, 0.30, 0.20, 1.0) if is_enemy \
		else Color(0.95, 0.78, 0.30, 1.0)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		s.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(k, 8)
	bg.add_theme_stylebox_override("panel", s)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(bg)
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
	icon.modulate = Color(0.95, 0.30, 0.20) if is_enemy \
		else Color(0.95, 0.78, 0.30)
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
	return p

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


func _make_panel(anchor: Vector2, offset: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = anchor.x
	panel.anchor_right = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_bottom = anchor.y
	panel.offset_left = offset.x
	panel.offset_top = offset.y
	panel.offset_right = offset.x + sz.x
	panel.offset_bottom = offset.y + sz.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.tex_panel_9p:
		panel.add_theme_stylebox_override("panel", GameTheme.make_panel_textured())
	else:
		panel.add_theme_stylebox_override("panel", GameTheme.make_panel_style())
	return panel


func _make_text_label(text: String, sz: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


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
	_end_turn_btn = btn
	_hud_layer.add_child(btn)


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
	var normal = GameTheme.make_btn_style(Color(0.18, 0.10, 0.05, 0.92))
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.18, 0.06, 0.98)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.06, 0.03, 0.98)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.10, 0.07, 0.05, 0.55)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.78))
	btn.add_theme_color_override("font_disabled_color", Color(0.7, 0.65, 0.55, 0.6))
	btn.add_theme_font_size_override("font_size", 14)


func _build_relic_display() -> void:
	# Sits along the top edge between the enemy banner (ends ~x=194) and
	# the encounter scroll (starts ~x=width-334). Anchored to top-left with
	# enough horizontal room to grow as relics accumulate.
	_relic_panel = HBoxContainer.new()
	_relic_panel.anchor_left = 0.0
	_relic_panel.anchor_top = 0.0
	_relic_panel.offset_left = 210
	_relic_panel.offset_top = 16
	_relic_panel.offset_right = 600
	_relic_panel.offset_bottom = 42
	_relic_panel.add_theme_constant_override("separation", 6)
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
		var chip := PanelContainer.new()
		var style = GameTheme.make_panel_style(
			Color(0.10, 0.075, 0.060, 0.85), GameTheme.PARCHMENT_BORDER, 1, 4, false)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", style)
		chip.tooltip_text = relic.desc
		var lbl := Label.new()
		lbl.text = relic.name
		lbl.add_theme_color_override("font_color", GILT)
		lbl.add_theme_font_size_override("font_size", 11)
		chip.add_child(lbl)
		_relic_panel.add_child(chip)


func _update_hud() -> void:
	_player_hp_label.text = "%d / %d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "%d / %d" % [enemy_hp, enemy_max_hp]
	# Update HP bar fills (inset by 1px from frame border)
	var p_fill = _player_hp_label.get_parent().get_node_or_null("Fill")
	if p_fill:
		p_fill.size.x = 148.0 * clampf(float(player_hp) / float(player_max_hp), 0.0, 1.0)
	var e_fill = _enemy_hp_label.get_parent().get_node_or_null("Fill")
	if e_fill:
		e_fill.size.x = 178.0 * clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
	if player_mana > player_max_mana:
		_mana_label.text = "%d / %d (+%d)" % [player_mana, player_max_mana, player_mana - player_max_mana]
	else:
		_mana_label.text = "%d / %d" % [player_mana, player_max_mana]
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


func freeze_frame(duration: float) -> void:
	get_tree().paused = true
	await get_tree().create_timer(duration, true, false, true).timeout
	get_tree().paused = false


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


func _show_info(msg: String) -> void:
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	get_tree().create_timer(2.0).timeout.connect(func(): _info_label.text = "")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E, KEY_ENTER:
				_on_end_turn()
