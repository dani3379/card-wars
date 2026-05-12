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
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]

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
var _player_slots: Array[Control] = []
var _enemy_slots: Array[Control] = []
var _hand_container: HBoxContainer
var _midline: ColorRect

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
	_setup_fight_state()
	_build_board()
	_build_hud()
	_init_decks()
	_place_starting_board()
	_start_round()


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
	## Number of starting creatures depends on encounter tier and act.
	## This creates an immediate puzzle instead of empty-lane-fill-trivially.
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")
	var act = enc.get("act", RunState.get_act())

	var starting_count := 0
	match enc_type:
		"combat":
			# Act 1: 1 starting enemy, Act 2: 2, Act 3: 2-3
			starting_count = [1, 2, 2][act - 1]
			if act == 3 and randi() % 2 == 0:
				starting_count = 3
		"elite":
			# Elites: Act 1 starts 2, Act 2-3 starts 3
			starting_count = 2 if act == 1 else 3
		"boss":
			# Bosses start with 2 (deck is deep, they ramp up)
			starting_count = 2

	# Place starting creatures from the enemy deck
	var placed := 0
	# Spread them out — prefer lanes 0, 1, 2, 3 in order for variety
	var lane_order = [0, 1, 2, 3]
	lane_order.shuffle()
	for lane_idx in lane_order:
		if placed >= starting_count:
			break
		if _enemy_deck.is_empty():
			break
		var card_data = _enemy_deck.pop_front()
		_place_enemy_card(card_data, lane_idx)
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

	# Boss phase check
	_check_boss_phase_transition()

	# Assign intents only for boss encounters
	var _enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	if _enc.get("type", "") == "boss":
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
	if _has_relic("happy_flower") and round_number > 0 and round_number % 3 == 0:
		player_max_mana += 1
	# Leyline Conduit passive: +1 mana per alive conduit
	for lane_idx in range(4):
		var c = _player_field[lane_idx]
		if c != null and c.card_data.get("passive", "") == "mana_per_turn":
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
	for lane_idx in range(4):
		var card = _player_field[lane_idx]
		if card != null and card.will_floop and card.has_floop():
			_resolve_floop_ability(card, lane_idx, false)
			card.will_floop = false
			card.has_flooped_this_turn = true
			card.has_attacked_this_turn = true
			card.update_floop_display()
			# Reactive passive: ON_PLAYER_FLOOP
			_dispatch_reactive("ON_PLAYER_FLOOP", card, lane_idx)
		var e_card = _enemy_field[lane_idx]
		if e_card != null and e_card.has_floop() and randi() % 3 == 0:
			_resolve_floop_ability(e_card, lane_idx, true)


func _resolve_floop_ability(card: Control, lane_idx: int, is_enemy: bool) -> void:
	var floop_data = card.card_data.get("floop", {})
	var times = 1
	if not is_enemy and _has_relic("echo_staff"):
		times = 2
	var friendly_field = _enemy_field if is_enemy else _player_field
	var enemy_field = _player_field if is_enemy else _enemy_field
	for _i in times:
		match floop_data.get("type", ""):
			# --- DAMAGE ---
			"damage_any":
				var targets: Array = []
				for c in enemy_field:
					if c != null:
						targets.append(c)
				if targets.size() > 0:
					targets[randi() % targets.size()].take_damage(floop_data.value)
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
				for c in enemy_field:
					if c != null:
						c.take_damage(floop_data.value)
			"damage_all":
				for c in enemy_field:
					if c != null:
						c.take_damage(floop_data.value)
				for c in friendly_field:
					if c != null and c != card:
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
					if cost_dmg > 0:
						var targets: Array = []
						for c in enemy_field:
							if c != null:
								targets.append(c)
						if targets.size() > 0:
							targets[randi() % targets.size()].take_damage(cost_dmg)

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
				for c in friendly_field:
					if c != null:
						c.current_hp = mini(c.current_hp + floop_data.value, c.card_data.hp)
						c.update_stat_display()
			"grow_atk":
				card.current_atk += floop_data.value
				card.update_stat_display()
			"grow_per_enemies":
				var count = 0
				for c in enemy_field:
					if c != null:
						count += 1
				card.current_atk += count
				card.update_stat_display()
			"buff_all_atk_permanent":
				for c in friendly_field:
					if c != null:
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
				for c in friendly_field:
					if c != null and c.card_data.get("is_token", false):
						c.temp_atk_buff += floop_data.value
						c.update_stat_display()

			# --- DEFENSE ---
			"temp_armored":
				if "armored" not in card.card_data.keywords:
					card.card_data.keywords.append("armored")
					card.set_meta("temp_armored", true)
			"grant_armored_all":
				for c in friendly_field:
					if c != null and "armored" not in c.card_data.keywords:
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
				var empty_lanes: Array[int] = []
				for i in range(4):
					if i != lane_idx and friendly_field[i] == null:
						empty_lanes.append(i)
				if empty_lanes.size() > 0:
					var new_lane = empty_lanes[randi() % empty_lanes.size()]
					friendly_field[lane_idx] = null
					friendly_field[new_lane] = card
					_place_card_in_slot(card, new_lane)
			"challenge":
				card.set_meta("challenge_any_lane", true)

			# --- SUMMONING / TRANSFORM ---
			"summon_random":
				var empty_lanes: Array[int] = []
				for i in range(4):
					if friendly_field[i] == null:
						empty_lanes.append(i)
				if empty_lanes.size() > 0:
					var l = empty_lanes[randi() % empty_lanes.size()]
					summon_token(floop_data.atk, floop_data.hp, l, is_enemy)
			"summon_token":
				var empty: Array[int] = []
				for i in range(4):
					if friendly_field[i] == null:
						empty.append(i)
				if empty.size() > 0:
					var l = empty[randi() % empty.size()]
					summon_token(floop_data.atk, floop_data.hp, l, is_enemy)
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
	print("[COMBAT] === _do_combat called, round %d ===" % round_number)
	print("[COMBAT] Player field: [%s]" % ", ".join(PackedStringArray([
		_player_field[0].card_data.name if _player_field[0] != null else "empty",
		_player_field[1].card_data.name if _player_field[1] != null else "empty",
		_player_field[2].card_data.name if _player_field[2] != null else "empty",
		_player_field[3].card_data.name if _player_field[3] != null else "empty",
	])))
	print("[COMBAT] Enemy field: [%s]" % ", ".join(PackedStringArray([
		_enemy_field[0].card_data.name if _enemy_field[0] != null else "empty",
		_enemy_field[1].card_data.name if _enemy_field[1] != null else "empty",
		_enemy_field[2].card_data.name if _enemy_field[2] != null else "empty",
		_enemy_field[3].card_data.name if _enemy_field[3] != null else "empty",
	])))
	_update_hud()

	# Snapshot which lanes are empty BEFORE combat (for face damage rules)
	var player_empty_at_start: Array[bool] = []
	var enemy_empty_at_start: Array[bool] = []
	for i in range(4):
		player_empty_at_start.append(_player_field[i] == null)
		enemy_empty_at_start.append(_enemy_field[i] == null)

	# Mark stunned creatures as already-attacked so they skip combat
	for lane_idx in range(4):
		for field in [_player_field, _enemy_field]:
			var c = field[lane_idx]
			if c != null and c.get_meta("stunned", false):
				c.has_attacked_this_turn = true

	# SWIFT PHASE: swift creatures attack first
	for lane_idx in range(4):
		_resolve_swift_attack(lane_idx, false, enemy_empty_at_start)
		_resolve_swift_attack(lane_idx, true, player_empty_at_start)

	# SEQUENTIAL PHASE: player creatures attack first, then enemy creatures
	# Player attacks (lanes 0→3)
	print("[COMBAT] === PLAYER ATTACK PHASE ===")
	for lane_idx in range(4):
		var p = _player_field[lane_idx]
		if p == null:
			continue
		if p.current_hp <= 0:
			print("[COMBAT] Lane %d: %s SKIPPED (dead, hp=%d)" % [lane_idx, p.card_data.name, p.current_hp])
			continue
		if p.has_attacked_this_turn:
			print("[COMBAT] Lane %d: %s SKIPPED (already attacked)" % [lane_idx, p.card_data.name])
			continue
		if not p.can_attack():
			print("[COMBAT] Lane %d: %s SKIPPED (can't attack, floop=%s)" % [lane_idx, p.card_data.name, str(p.will_floop)])
			continue
		var e = _enemy_field[lane_idx]
		if e != null and e.current_hp > 0:
			_creature_attacks_creature(p, e, lane_idx, false)
		elif enemy_empty_at_start[lane_idx]:
			_creature_hits_face(p, lane_idx, false)
		else:
			print("[COMBAT] Lane %d: %s has no valid target (enemy null=%s, enemy_empty_start=%s)" % [lane_idx, p.card_data.name, str(e == null), str(enemy_empty_at_start[lane_idx])])

	# Enemy attacks (lanes 0→3) — only surviving creatures
	for lane_idx in range(4):
		var e = _enemy_field[lane_idx]
		if e == null or not is_instance_valid(e) or e.current_hp <= 0 or e.has_attacked_this_turn or not e.can_attack():
			continue
		var p = _player_field[lane_idx]
		if p != null and is_instance_valid(p) and p.current_hp > 0:
			_creature_attacks_creature(e, p, lane_idx, true)
		elif player_empty_at_start[lane_idx]:
			_creature_hits_face(e, lane_idx, true)

	# Process ranged attacks
	_resolve_ranged_attacks()

	# Berserker growth
	for lane_idx in range(4):
		for field in [_player_field, _enemy_field]:
			var c = field[lane_idx]
			if c != null and c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
				c.current_atk += 1
				c.update_stat_display()

	# Clean dead
	_cleanup_dead()

	await _short_pause(0.15)
	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		_post_combat_sequence()


func _resolve_swift_attack(lane_idx: int, is_enemy: bool, opponent_empty: Array[bool]) -> void:
	var attacker_field = _enemy_field if is_enemy else _player_field
	var defender_field = _player_field if is_enemy else _enemy_field
	var card = attacker_field[lane_idx]
	if card == null or not card.has_keyword("swift") or card.has_attacked_this_turn or not card.can_attack():
		return
	card.has_attacked_this_turn = true
	var opponent = defender_field[lane_idx]
	if opponent != null:
		var atk = _effective_attack(card, lane_idx, is_enemy)
		_apply_thorns(opponent, card, is_enemy)
		opponent.take_damage(atk)
	
		if opponent.current_hp <= 0 and (card.has_keyword("piercing") or (is_enemy and _has_encounter_passive_keyword(card, "piercing"))):
			var excess = abs(opponent.current_hp)
			var bonus = 1 if (not is_enemy and _has_relic("piercing_crown")) else 0
			if is_enemy:
				damage_player_hero(excess + bonus)
			else:
				damage_enemy_hero(excess + bonus)
	elif opponent_empty[lane_idx]:
		_creature_hits_face(card, lane_idx, is_enemy)



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
		var excess = abs(defender.current_hp)
		var bonus = 1 if (not attacker_is_enemy and _has_relic("piercing_crown")) else 0
		if attacker_is_enemy:
			damage_player_hero(excess + bonus)
		else:
			damage_enemy_hero(excess + bonus)

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
	for lane_idx in range(4):
		for is_enemy in [false, true]:
			var field = _enemy_field if is_enemy else _player_field
			var card = field[lane_idx]
			if card == null or not card.has_keyword("ranged") or card.has_attacked_this_turn:
				continue
			card.has_attacked_this_turn = true
			var targets: Array = []
			var opp_field = _player_field if is_enemy else _enemy_field
			for c in opp_field:
				if c != null:
					targets.append(c)
			if targets.size() > 0:
				var target = targets[randi() % targets.size()]
				var atk = _effective_attack(card, lane_idx, is_enemy)
				target.take_damage(atk)


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
	return maxi(0, atk)


func _get_adj_buff_atk(lane_idx: int, is_enemy: bool) -> int:
	var field = _enemy_field if is_enemy else _player_field
	var total := 0
	for adj in [lane_idx - 1, lane_idx + 1]:
		if adj < 0 or adj > 3:
			continue
		var neighbor = field[adj]
		if neighbor != null and neighbor.card_data.has("adj_buff"):
			total += neighbor.card_data.adj_buff.get("atk", 0)
			if not is_enemy and _has_relic("banner_of_unity"):
				total += 1
	return total


func _has_bannerman_buff(is_enemy: bool) -> bool:
	var field = _enemy_field if is_enemy else _player_field
	for c in field:
		if c != null and c.card_data.get("passive", "") == "global_atk_buff":
			return true
	return false


func _has_passive_on_field(passive_name: String) -> bool:
	for c in _player_field:
		if c != null and c.card_data.get("passive", "") == passive_name:
			return true
	return false


func _get_wall_reduction(lane_idx: int, _is_enemy: bool) -> int:
	var reduction := 0
	for i in range(4):
		var c = _player_field[i]
		if c != null and c.card_data.get("passive", "") == "cannot_attack_wall":
			if i == lane_idx or abs(i - lane_idx) == 1:
				reduction += 1
		if c != null and c.card_data.get("passive", "") == "reduce_face_damage":
			reduction += 1
	return reduction


func _cleanup_dead() -> void:
	for lane_idx in range(4):
		if _player_field[lane_idx] != null and _player_field[lane_idx].current_hp <= 0:
			var card = _player_field[lane_idx]
			KeywordEffects.dispatch_on_death(card, lane_idx, false, self)
			_on_friendly_death(card, lane_idx)
			_dispatch_encounter_on_player_death(lane_idx)
			_dispatch_reactive("ON_CREATURE_DEATH", card, lane_idx)
			# Fallback: add to discard if not already handled by _on_card_destroyed
			if not card.is_token:
				_player_discard_pile.append(card.card_id)
			_player_field[lane_idx] = null
		if _enemy_field[lane_idx] != null and _enemy_field[lane_idx].current_hp <= 0:
			var card = _enemy_field[lane_idx]
			_last_dead_enemy_data = card.card_data.duplicate(true)
			KeywordEffects.dispatch_on_death(card, lane_idx, true, self)
			_dispatch_encounter_on_enemy_death(lane_idx)
			_dispatch_reactive("ON_CREATURE_DEATH", card, lane_idx)
			_enemy_field[lane_idx] = null


func _on_friendly_death(card: Control, _lane_idx: int) -> void:
	_friendly_deaths_this_fight += 1
	_friendly_deaths_this_round += 1
	_last_dead_creature_id = card.card_id
	# Gravedigger
	if _friendly_deaths_this_round == 1 and _has_passive_on_field("draw_on_ally_death"):
		draw_one()
	# Corpse Eater
	for i in range(4):
		var c = _player_field[i]
		if c != null and c.card_data.get("passive", "") == "grow_on_ally_death":
			c.current_atk += 1
			c.update_stat_display()
	# Soul Lantern
	if _has_relic("soul_lantern") and not _soul_lantern_used_this_round:
		_soul_lantern_used_this_round = true
		_bonus_mana_next_turn += 1


func _post_combat_sequence() -> void:
	# Cleanup temporary effects from intents and floops
	_post_combat_cleanup()

	# Discard hand (retain cards stay)
	_discard_hand()

	# Enemy places creatures
	await _short_pause(0.3)
	_enemy_place_creatures()

	# Escalation: after round 8, regular fights place extra reinforcement
	if _encounter_id != "":
		var enc = EncounterDB.get_encounter(_encounter_id)
		if enc.get("type", "") == "combat" and round_number >= 8:
			_enemy_place_creatures()  # Second placement

	# Assassin dies at end of turn
	for i in range(4):
		var c = _player_field[i]
		if c != null and c.card_data.get("passive", "") == "dies_end_of_turn":
			c.take_damage(999)
			_player_field[i] = null

	_dispatch_passive_end_of_round()

	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		await _short_pause(0.3)
		_start_round()


func _enemy_place_creatures() -> void:
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")
	var max_place := 1
	# Determine how many to place this round
	if round_number <= 2:
		max_place = 1
	elif enc_type == "elite" or enc_type == "boss":
		max_place = 2
	else:
		max_place = 1 if randi() % 3 != 0 else 2  # 33% chance of placing 2

	var placed := 0
	# Determine lane priority based on encounter tier
	var lane_priority: Array[int] = _get_placement_priority(enc_type)
	for lane_idx in lane_priority:
		if placed >= max_place:
			break
		if _enemy_field[lane_idx] != null:
			continue
		if _enemy_deck.is_empty():
			if not _reinforcement.is_empty():
				_enemy_deck.append(_reinforcement.duplicate(true))
			else:
				var eid = CardDB.random_enemy_for_act(RunState.get_act())
				_enemy_deck.append(CardDB.get_card_data(eid))
		var card_data = _enemy_deck.pop_front()
		_place_enemy_card(card_data, lane_idx)
		placed += 1


func _get_placement_priority(enc_type: String) -> Array[int]:
	## Returns lane indices in priority order for enemy placement.
	## Regular: fill opposing player creatures first, then empty lanes
	## Elite: target player's highest-ATK creature lane
	## Boss: spread out (randomized)
	var lanes: Array[int] = []
	match enc_type:
		"elite":
			# Target player's strongest creature
			var best_lane := -1
			var best_atk := -1
			for i in range(4):
				if _player_field[i] != null and _enemy_field[i] == null:
					var atk = _player_field[i].current_atk + _player_field[i].temp_atk_buff
					if atk > best_atk:
						best_atk = atk
						best_lane = i
			if best_lane >= 0:
				lanes.append(best_lane)
			# Then fill other occupied lanes
			for i in range(4):
				if i != best_lane and _player_field[i] != null and _enemy_field[i] == null:
					lanes.append(i)
			# Then empty lanes
			for i in range(4):
				if _enemy_field[i] == null and not lanes.has(i):
					lanes.append(i)
		"boss":
			# Randomized spread
			var available: Array[int] = []
			for i in range(4):
				if _enemy_field[i] == null:
					available.append(i)
			available.shuffle()
			lanes = available
		_:
			# Regular: prefer lanes opposing player creatures (block face)
			for i in range(4):
				if _player_field[i] != null and _enemy_field[i] == null:
					lanes.append(i)
			# Then fill empty lanes (try to apply pressure)
			for i in range(4):
				if _enemy_field[i] == null and not lanes.has(i):
					lanes.append(i)
	if lanes.is_empty():
		lanes = [0, 1, 2, 3]
	return lanes


func _place_enemy_card(data: Dictionary, lane_idx: int) -> void:
	var card = CARD_SCENE.instantiate()
	card.card_id = data.id
	card.is_opponent = true
	card.is_on_battlefield = true
	card.card_data = data
	card.summoned_this_turn = true
	card.current_lane = lane_idx
	_enemy_field[lane_idx] = card
	var slot = _enemy_slots[lane_idx]
	for child in slot.get_children():
		child.queue_free()
	slot.add_child(card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	# Philosopher's Stone: all enemies get +1 ATK
	if _has_relic("philosophers_stone"):
		card.current_atk += 1
		card.update_stat_display()
	KeywordEffects.dispatch_on_enter(card, lane_idx, true, self)
	_dispatch_encounter_on_enter(data, lane_idx)


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
		# Need to sacrifice first — enter sacrifice-to-play mode
		_show_info("Click a creature to sacrifice for this card.")
		return

	var lane_idx = _nearest_lane_index(card.global_position)
	if _player_field[lane_idx] != null:
		# Replace creature: old goes to discard
		var old = _player_field[lane_idx]
		_player_discard_pile.append(old.card_id)
		old.queue_free()
		_player_field[lane_idx] = null

	player_mana -= cost
	_cards_played_this_turn += 1
	_hand.erase(card)
	_hand_container.remove_child(card)

	card.is_on_battlefield = true
	card.summoned_this_turn = true
	card.current_lane = lane_idx

	# Relic buffs on play
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
	_place_card_in_slot(card, lane_idx)

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
			for c in _enemy_field:
				if c != null:
					c.take_damage(value)
		"damage_all":
			for c in _player_field + _enemy_field:
				if c != null:
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
			for c in _player_field:
				if c != null:
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
				var empty: Array[int] = []
				for i in range(4):
					if _enemy_field[i] == null and _enemy_field[i] != target:
						empty.append(i)
				target.take_damage(1)
				if empty.size() > 0:
					var old_lane = -1
					for i in range(4):
						if _enemy_field[i] == target:
							old_lane = i
							break
					var new_lane = empty[randi() % empty.size()]
					if old_lane >= 0:
						_enemy_field[old_lane] = null
						_enemy_field[new_lane] = target
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
			for c in _player_field:
				if c != null:
					c.current_atk += 1
					c.update_stat_display()
			damage_player_hero(2)
		"kings_command":
			for c in _player_field:
				if c != null:
					c.temp_atk_buff += 3
					c.current_hp += 1
					c.card_data.hp += 1
					c.update_stat_display()
		"mass_grave":
			var kills := 0
			for i in range(4):
				if _player_field[i] != null:
					_player_field[i].take_damage(999)
					_player_field[i] = null
					kills += 1
			damage_enemy_hero(kills * 3)
		"grave_robbery":
			if _last_dead_creature_id != "":
				_player_draw_pile.push_front(_last_dead_creature_id)
				draw_one()
		"cataclysm":
			var max_atk := 0
			for c in _player_field:
				if c != null:
					max_atk = maxi(max_atk, c.effective_atk())
			for c in _enemy_field:
				if c != null:
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
			for field in [_player_field, _enemy_field]:
				for i in range(4):
					if field[i] != null:
						field[i].take_damage(999)
						field[i] = null
						kills += 1
			damage_player_hero(kills)
		"grave_pact":
			_grave_pact_active = true
		"fuel_the_pyre":
			if target != null:
				var atk = target.effective_atk()
				target.take_damage(999)
				# Next target click for damage... simplified: hit random enemy
				var enemies: Array = []
				for c in _enemy_field:
					if c != null:
						enemies.append(c)
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
			# 4 damage to ALL enemy creatures + 4 face damage
			for i in range(4):
				if _enemy_field[i] != null:
					_enemy_field[i].take_damage(4)
			damage_enemy_hero(4)
		"overwhelming_force":
			# All friendly creatures +3 ATK permanently
			for i in range(4):
				var c = _player_field[i]
				if c != null:
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
	# Check if clicked on a creature
	for lane_idx in range(4):
		if targeting in ["enemy_creature", "any_creature", "any"]:
			var e = _enemy_field[lane_idx]
			if e != null and _is_click_on_card(pos, e):
				_resolve_spell(_targeting_data, e, lane_idx)
				_after_spell(_targeting_spell)
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				return
		if targeting in ["friendly_creature", "any_creature", "any"]:
			var p = _player_field[lane_idx]
			if p != null and _is_click_on_card(pos, p):
				_resolve_spell(_targeting_data, p, lane_idx)
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
	for lane_idx in range(4):
		var card = _player_field[lane_idx]
		if card != null and _is_click_on_card(pos, card):
			_sacrifice_creature(lane_idx)
			return


func _sacrifice_creature(lane_idx: int) -> void:
	var card = _player_field[lane_idx]
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
	_restore_slot_label(_player_slots[lane_idx], lane_idx)
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
		# In sacrifice mode, clicking a creature sacrifices it instead of toggling floop
		for i in range(4):
			if _player_field[i] == card:
				_sacrifice_creature(i)
				return
		return
	if _targeting_spell != null:
		return  # In spell targeting mode, don't toggle floop
	if not card.has_floop():
		return
	card.toggle_floop()
	if card.will_floop:
		_show_info(card.card_data.name + " set to floop!")
	else:
		_show_info("Floop cancelled.")
	_update_hud()


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
	_hand_container.add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))


func _discard_hand() -> void:
	var to_keep: Array[Control] = []
	for card in _hand:
		if card.has_keyword("retain"):
			to_keep.append(card)
		else:
			_player_discard_pile.append(card.card_id)
			card.queue_free()
	_hand = to_keep
	# Reset temp buffs on all battlefield creatures
	for field in [_player_field, _enemy_field]:
		for c in field:
			if c != null:
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
		for c in _player_field:
			if c != null:
				c.temp_atk_buff += 1
				c.update_stat_display()
	_on_hero_damaged(amount)
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	enemy_hp -= amount
	# Check boss phase transition on HP loss
	_check_boss_phase_transition()
	_update_hud()


func get_opposing_card(lane_idx: int, from_enemy_perspective: bool) -> Control:
	if from_enemy_perspective:
		return _player_field[lane_idx]
	return _enemy_field[lane_idx]


func summon_token(atk: int, hp: int, lane_idx: int, is_enemy: bool) -> void:
	var field = _enemy_field if is_enemy else _player_field
	if field[lane_idx] != null:
		return
	var token_hp = hp
	if not is_enemy and _has_relic("conscription_relic"):
		token_hp += 1
	var card = CARD_SCENE.instantiate()
	card.card_id = "token_%d_%d" % [atk, token_hp]
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.card_data = {"id": card.card_id, "name": "Token", "type": "creature",
		"cost": 0, "atk": atk, "hp": token_hp, "keywords": [], "rarity": "enemy", "desc": ""}
	card.current_atk = atk
	card.current_hp = token_hp
	card.summoned_this_turn = true
	card.current_lane = lane_idx
	field[lane_idx] = card
	var slot = _enemy_slots[lane_idx] if is_enemy else _player_slots[lane_idx]
	for child in slot.get_children():
		child.queue_free()
	slot.add_child(card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	# Connect floop click for player tokens that have floop
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
	## intent cycle. If no cycle, defaults to ATK. Stores as meta on the card.
	for lane_idx in range(4):
		var card = _enemy_field[lane_idx]
		if card == null:
			continue
		var intents = card.card_data.get("intents", [])
		if intents.is_empty():
			card.set_meta("current_intent", "ATK")
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
	## Updates the visual intent indicator on enemy creature cards.
	## ATK shows no icon (reduce noise). Others show colored text indicator.
	if intent == "ATK":
		if card.has_meta("intent_label"):
			var lbl = card.get_meta("intent_label")
			if is_instance_valid(lbl):
				lbl.text = ""
		return
	var lbl: Label
	if card.has_meta("intent_label") and is_instance_valid(card.get_meta("intent_label")):
		lbl = card.get_meta("intent_label")
	else:
		lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.z_index = 5
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lbl)
		card.set_meta("intent_label", lbl)
	var color := Color.WHITE
	match intent:
		"CHARGE": color = Color(0.95, 0.25, 0.25)
		"GUARD": color = Color(0.5, 0.7, 1.0)
		"RALLY": color = Color(1.0, 0.85, 0.2)
		"HEAL": color = Color(0.3, 0.95, 0.4)
		"ENRAGE": color = Color(1.0, 0.4, 0.1)
		"RETREAT": color = Color(0.7, 0.7, 0.7)
		"SUMMON": color = Color(0.8, 0.5, 1.0)
		"ABILITY": color = Color(1.0, 0.8, 0.0)
	lbl.add_theme_color_override("font_color", color)
	lbl.text = intent


func _resolve_intents() -> void:
	## Resolves all non-ATK intents for enemy creatures BEFORE combat.
	## ATK is default behavior (normal attack). Other intents modify combat.
	for lane_idx in range(4):
		var card = _enemy_field[lane_idx]
		if card == null:
			continue
		var intent = card.get_meta("current_intent", "ATK")
		match intent:
			"ATK":
				pass  # Normal attack happens in combat
			"CHARGE":
				# +1 ATK this round
				card.temp_atk_buff += 1
			"GUARD":
				# Gain Armored this round
				if "armored" not in card.card_data.keywords:
					card.card_data.keywords.append("armored")
					card.set_meta("temp_armored", true)
			"RALLY":
				# Adjacent allies gain +1 ATK this turn
				for adj in [lane_idx - 1, lane_idx + 1]:
					if adj >= 0 and adj < 4 and _enemy_field[adj] != null:
						_enemy_field[adj].temp_atk_buff += 1
						_enemy_field[adj].update_stat_display()
			"HEAL":
				# Heal self 3, skip attack
				card.current_hp = mini(card.current_hp + 3, card.card_data.hp)
				card.has_attacked_this_turn = true  # Skips combat
				card.update_stat_display()
			"ENRAGE":
				# +2 ATK permanently, but take +1 damage this round
				card.current_atk += 2
				card.set_meta("enrage_vulnerable", true)
				card.update_stat_display()
			"RETREAT":
				# Move to different lane after combat (handled post-combat)
				card.set_meta("will_retreat", true)
			"SUMMON":
				# Summon reinforcement in adjacent empty lane, skip attack
				var adj_empty: Array[int] = []
				for adj in [lane_idx - 1, lane_idx + 1]:
					if adj >= 0 and adj < 4 and _enemy_field[adj] == null:
						adj_empty.append(adj)
				if adj_empty.size() > 0:
					var target_lane = adj_empty[randi() % adj_empty.size()]
					if not _reinforcement.is_empty():
						var data = _reinforcement.duplicate(true)
						data.id = "summon_%d" % randi()
						_place_enemy_card(data, target_lane)
				card.has_attacked_this_turn = true
			"ABILITY":
				# Use creature's special ability
				_resolve_enemy_ability(card, lane_idx)
				card.has_attacked_this_turn = true


func _resolve_enemy_ability(card: Control, lane_idx: int) -> void:
	## Resolves the creature-specific ability telegraphed by ABILITY intent.
	var ability = card.card_data.get("ability", {})
	var ability_type = ability.get("type", "")
	match ability_type:
		"warcry":
			# All enemy creatures +1 ATK permanently
			for c in _enemy_field:
				if c != null:
					c.current_atk += ability.get("value", 1)
					c.update_stat_display()
		"steal_atk":
			# Steal ATK from opposing player creature
			var opp = _player_field[lane_idx]
			if opp != null and opp.current_atk > 0:
				var steal = ability.get("value", 1)
				opp.current_atk = maxi(0, opp.current_atk - steal)
				card.current_atk += steal
				opp.update_stat_display()
				card.update_stat_display()
		"curse":
			# Add Curse card to player's discard pile
			_player_discard_pile.append("curse")
		"devour":
			# Destroy adjacent friendly enemy, gain its stats
			var adj: Array[int] = []
			if lane_idx > 0 and _enemy_field[lane_idx - 1] != null:
				adj.append(lane_idx - 1)
			if lane_idx < 3 and _enemy_field[lane_idx + 1] != null:
				adj.append(lane_idx + 1)
			if adj.size() > 0:
				var target_lane = adj[randi() % adj.size()]
				var victim = _enemy_field[target_lane]
				if victim != null:
					card.current_atk += victim.current_atk
					card.current_hp += victim.current_hp
					card.card_data.hp += victim.current_hp
					victim.take_damage(999)
					_enemy_field[target_lane] = null
					card.update_stat_display()
		"terrify":
			# Move opposing player creature to a random different lane
			var opp = _player_field[lane_idx]
			if opp != null:
				var empty_lanes: Array[int] = []
				for i in range(4):
					if i != lane_idx and _player_field[i] == null:
						empty_lanes.append(i)
				if empty_lanes.size() > 0:
					var new_lane = empty_lanes[randi() % empty_lanes.size()]
					_player_field[lane_idx] = null
					opp.current_lane = new_lane
					_place_card_in_slot(opp, new_lane)
					_restore_slot_label(_player_slots[lane_idx], lane_idx)
		"hex":
			# Remove all keywords from opposing player creature
			var opp = _player_field[lane_idx]
			if opp != null:
				opp.card_data.keywords.clear()
				opp.update_stat_display()
		"mark":
			# Opposing player creature takes +2 damage this round
			var opp = _player_field[lane_idx]
			if opp != null:
				opp.set_meta("marked", true)
		"resurrect":
			# Summon the last dead enemy creature as a 1/1 in empty lane
			if not _last_dead_enemy_data.is_empty():
				var empty: Array[int] = []
				for i in range(4):
					if _enemy_field[i] == null:
						empty.append(i)
				if empty.size() > 0:
					var lane = empty[randi() % empty.size()]
					var data = _last_dead_enemy_data.duplicate(true)
					data.atk = 1
					data.hp = 1
					data.id = "resurrected_%d" % randi()
					_place_enemy_card(data, lane)
		"heal_all":
			# Heal all enemy creatures by value
			var value = ability.get("value", 2)
			for c in _enemy_field:
				if c != null:
					c.current_hp = mini(c.current_hp + value, c.card_data.hp)
					c.update_stat_display()
		"drain":
			# Deal 2 to opposing, heal self 2
			var opp = _player_field[lane_idx]
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
		# Update passive
		_encounter_passive = phase_data.passive_id
		# Show transition message
		if phase_data.has("transition_msg"):
			_show_info(phase_data.transition_msg)
		# Execute transition effect
		if phase_data.has("transition_effect"):
			_execute_phase_transition(phase_data.transition_effect)
		# Reset all intent cycles
		for c in _enemy_field:
			if c != null:
				c.set_meta("intent_cycle_pos", 0)


func _execute_phase_transition(effect: Dictionary) -> void:
	## Executes a boss phase transition effect.
	match effect.get("type", ""):
		"summon":
			var empty: Array[int] = []
			for i in range(4):
				if _enemy_field[i] == null:
					empty.append(i)
			if empty.size() > 0:
				var lane = empty[randi() % empty.size()]
				var data = {
					"id": "phase_summon_%d" % randi(),
					"name": effect.get("name", "Minion"),
					"type": "creature", "cost": 0,
					"atk": effect.get("atk", 2), "hp": effect.get("hp", 3),
					"rarity": "enemy",
					"keywords": effect.get("kw", []).duplicate(),
					"desc": "",
				}
				_place_enemy_card(data, lane)
		"summon_multiple":
			var count = effect.get("count", 2)
			for _i in range(count):
				var empty: Array[int] = []
				for j in range(4):
					if _enemy_field[j] == null:
						empty.append(j)
				if empty.is_empty():
					break
				var lane = empty[randi() % empty.size()]
				var data = {
					"id": "phase_summon_%d" % randi(),
					"name": effect.get("name", "Minion"),
					"type": "creature", "cost": 0,
					"atk": effect.get("atk", 2), "hp": effect.get("hp", 3),
					"rarity": "enemy", "keywords": [], "desc": "",
				}
				_place_enemy_card(data, lane)
		"heal_all_enemies":
			var value = effect.get("value", 2)
			for c in _enemy_field:
				if c != null:
					c.current_hp = mini(c.current_hp + value, c.card_data.hp)
					c.update_stat_display()
		"buff_all_enemies_atk":
			var value = effect.get("value", 1)
			for c in _enemy_field:
				if c != null:
					c.current_atk += value
					c.update_stat_display()
		"debuff_all_player_atk":
			var value = effect.get("value", 1)
			for c in _player_field:
				if c != null:
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
			# Find Chieftain on enemy field, buff it
			for c in _enemy_field:
				if c != null and c.card_data.get("name", "") == "Chieftain":
					c.current_atk += 1
					c.update_stat_display()
					break
		"double_on_death":
			# Already handled in on-death dispatch — this is a flag check
			pass
		"face_damage":
			var value = _reactive_passive.get("value", 2)
			damage_player_hero(value)
		"damage_flooper":
			var value = _reactive_passive.get("value", 1)
			if source_card != null and is_instance_valid(source_card):
				source_card.take_damage(value)
		"summon_puppet":
			var atk = _reactive_passive.get("atk", 2)
			var hp = _reactive_passive.get("hp", 2)
			_summon_enemy_token(atk, hp)
		"heal_all_enemies":
			var value = _reactive_passive.get("value", 1)
			for c in _enemy_field:
				if c != null:
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
			# After round 10: all enemies +1 ATK permanently each round
			if round_number >= 10:
				for c in _enemy_field:
					if c != null:
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
	for lane_idx in range(4):
		for field in [_player_field, _enemy_field]:
			var card = field[lane_idx]
			if card == null:
				continue
			# Remove temp armored
			if card.get_meta("temp_armored", false):
				card.card_data.keywords.erase("armored")
				card.remove_meta("temp_armored")
			# Remove temp thorns
			if card.get_meta("temp_thorns", false):
				card.card_data.keywords.erase("thorns")
				card.remove_meta("temp_thorns")
			# Clear bonus thorns
			if card.has_meta("bonus_thorns"):
				card.remove_meta("bonus_thorns")
			# Clear stun
			if card.has_meta("stunned"):
				card.remove_meta("stunned")
			# Clear redirecting
			if card.has_meta("redirecting"):
				card.remove_meta("redirecting")
			# Clear challenge
			if card.has_meta("challenge_any_lane"):
				card.remove_meta("challenge_any_lane")
			# Clear swap_atk_original
			if card.has_meta("swap_atk_original"):
				card.current_atk = card.get_meta("swap_atk_original")
				card.remove_meta("swap_atk_original")
				card.update_stat_display()
			# Clear become_copy
			if card.has_meta("is_copy"):
				card.remove_meta("is_copy")
			# Clear enrage vulnerability
			if card.has_meta("enrage_vulnerable"):
				card.remove_meta("enrage_vulnerable")
			# Clear marked
			if card.has_meta("marked"):
				card.remove_meta("marked")
			# Handle RETREAT intent
			if card.get_meta("will_retreat", false):
				card.remove_meta("will_retreat")
				_execute_retreat(card, lane_idx, field == _enemy_field)


func _execute_retreat(card: Control, lane_idx: int, is_enemy: bool) -> void:
	## Moves a creature to a random different lane (RETREAT intent).
	var field = _enemy_field if is_enemy else _player_field
	var empty_lanes: Array[int] = []
	for i in range(4):
		if i != lane_idx and field[i] == null:
			empty_lanes.append(i)
	if empty_lanes.size() > 0:
		var new_lane = empty_lanes[randi() % empty_lanes.size()]
		field[lane_idx] = null
		field[new_lane] = card
		card.current_lane = new_lane
		var slots = _enemy_slots if is_enemy else _player_slots
		# Move card to new slot
		var old_slot = slots[lane_idx]
		old_slot.remove_child(card)
		_restore_slot_label(old_slot, lane_idx)
		var new_slot = slots[new_lane]
		for child in new_slot.get_children():
			child.queue_free()
		new_slot.add_child(card)


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
			for field in [_player_field, _enemy_field]:
				for c in field:
					if c != null:
						c.take_damage(1)
		"hollow_king_snipe":
			var highest = _highest_atk_player_creature()
			if highest != null:
				highest.take_damage(3)
		"void_exile":
			if not _player_draw_pile.is_empty():
				_player_draw_pile.pop_front()
		"nexus_rotation":
			var cycle = (round_number - 1) % 3
			match cycle:
				0:
					for c in _enemy_field:
						if c != null:
							c.current_atk += 1
							c.update_stat_display()
				1:
					for c in _enemy_field:
						if c != null:
							c.current_hp = mini(c.current_hp + 2, c.card_data.hp)
							c.update_stat_display()
				2:
					pass  # Thorns handled in combat resolution
		"dragon_lair_periodic":
			if round_number > 1 and (round_number - 1) % 3 == 0:
				for c in _player_field:
					if c != null:
						c.take_damage(3)
		"devil_cycle":
			var cycle = (round_number - 1) % 3
			match cycle:
				0:
					damage_player_hero(2)
				1:
					var count := 0
					for c in _enemy_field:
						if c != null:
							count += 1
					enemy_hp = mini(enemy_hp + count, enemy_max_hp)
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
			# Two highest-ATK player creatures take 3 damage
			var sorted_creatures: Array = []
			for c in _player_field:
				if c != null:
					sorted_creatures.append(c)
			sorted_creatures.sort_custom(func(a, b): return a.current_atk > b.current_atk)
			for i in range(mini(2, sorted_creatures.size())):
				sorted_creatures[i].take_damage(3)
			# Add Curse to player deck each round
			_player_discard_pile.append("curse")
		"dragon_lord_phase2":
			# All enemies +1 ATK (phase 2 passive on top of piercing)
			for c in _enemy_field:
				if c != null:
					c.current_atk += 1
					c.update_stat_display()
		"collector_phase2":
			pass  # Handled in creature play hook
		"devil_phase2":
			# Doubled cycle: 4 face, heal 2/enemy, 6 to highest
			var cycle = (round_number - 1) % 3
			match cycle:
				0: damage_player_hero(4)
				1:
					var count := 0
					for c in _enemy_field:
						if c != null:
							count += 1
					enemy_hp = mini(enemy_hp + count * 2, enemy_max_hp)
				2:
					var highest = _highest_atk_player_creature()
					if highest != null:
						highest.take_damage(6)
		"devil_phase3":
			# Desperation: 3 face + summon + all enemies +1 ATK
			damage_player_hero(3)
			_summon_enemy_token(3, 3)
			for c in _enemy_field:
				if c != null:
					c.current_atk += 1
					c.update_stat_display()


func _dispatch_passive_end_of_round() -> void:
	match _encounter_passive:
		"iron_warden_burn":
			damage_player_hero(2)
		"iron_warden_siege":
			# Phase 2: 3 face damage + grant Armored to all enemies
			damage_player_hero(3)
			for c in _enemy_field:
				if c != null and "armored" not in c.card_data.keywords:
					c.card_data.keywords.append("armored")
		"mushroom_heal":
			for c in _enemy_field:
				if c != null:
					c.current_hp = mini(c.current_hp + 1, c.card_data.hp)
					c.update_stat_display()
		"executioner_face":
			var highest = _highest_atk_enemy_creature()
			if highest != null:
				damage_player_hero(highest.current_atk + highest.temp_atk_buff)


func _dispatch_encounter_on_enemy_death(lane_idx: int) -> void:
	match _encounter_passive:
		"wolf_pack_revenge":
			for adj in [lane_idx - 1, lane_idx + 1]:
				if adj >= 0 and adj < 4 and _enemy_field[adj] != null:
					_enemy_field[adj].temp_atk_buff += 1
					_enemy_field[adj].update_stat_display()
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
	var enemies: Array = []
	for c in _enemy_field:
		if c != null:
			enemies.append(c)
	if enemies.is_empty():
		return null
	return enemies[randi() % enemies.size()]


func _highest_atk_player_creature() -> Control:
	var best: Control = null
	var best_atk := -1
	for c in _player_field:
		if c != null:
			var atk = c.current_atk + c.temp_atk_buff
			if atk > best_atk:
				best_atk = atk
				best = c
	return best


func _highest_atk_enemy_creature() -> Control:
	var best: Control = null
	var best_atk := -1
	for c in _enemy_field:
		if c != null:
			var atk = c.current_atk + c.temp_atk_buff
			if atk > best_atk:
				best_atk = atk
				best = c
	return best


func _summon_enemy_token(atk: int, hp: int) -> void:
	var empty_lanes: Array = []
	for i in range(4):
		if _enemy_field[i] == null:
			empty_lanes.append(i)
	if empty_lanes.is_empty():
		return
	var lane = empty_lanes[randi() % empty_lanes.size()]
	summon_token(atk, hp, lane, true)


func _summon_enemy_token_with_keyword(atk: int, hp: int, keyword: String) -> void:
	var empty_lanes: Array = []
	for i in range(4):
		if _enemy_field[i] == null:
			empty_lanes.append(i)
	if empty_lanes.is_empty():
		return
	var lane = empty_lanes[randi() % empty_lanes.size()]
	var data = {
		"id": "token_%s" % keyword, "name": "Ghost" if keyword == "swift" else "Token",
		"type": "creature", "cost": 0, "atk": atk, "hp": hp,
		"rarity": "token", "keywords": [keyword], "desc": "",
	}
	_place_enemy_card(data, lane)


# =====================================================================
#  RELIC HELPERS
# =====================================================================

func _has_relic(id: String) -> bool:
	return RunState.has_relic(id)


# =====================================================================
#  BOARD LAYOUT
# =====================================================================

func _build_board() -> void:
	_board_container = Control.new()
	_board_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_board_container)

	_board_bg = ColorRect.new()
	_board_bg.color = Color(BOARD_BG.r, BOARD_BG.g, BOARD_BG.b, 0.25)
	_board_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_container.add_child(_board_bg)

	# Atmosphere: vignette + gradient + embers (no frame — HUD overlaps edges)
	GameTheme.add_atmosphere(_board_container, "combat", false)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.anchor_top = 0.16
	main_vbox.anchor_bottom = 1.0
	main_vbox.anchor_left = 0.08
	main_vbox.anchor_right = 0.92
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_container.add_child(main_vbox)

	# Enemy territory — dark red tint background behind the row
	var enemy_zone := PanelContainer.new()
	enemy_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ez_style := StyleBoxFlat.new()
	ez_style.bg_color = Color(0.14, 0.05, 0.04, 0.40)
	ez_style.border_color = Color(0.55, 0.22, 0.15, 0.40)
	ez_style.border_width_bottom = 1
	ez_style.corner_radius_top_left = 8
	ez_style.corner_radius_top_right = 8
	ez_style.content_margin_left = 4
	ez_style.content_margin_right = 4
	ez_style.content_margin_top = 2
	ez_style.content_margin_bottom = 2
	enemy_zone.add_theme_stylebox_override("panel", ez_style)
	main_vbox.add_child(enemy_zone)

	var enemy_inner := VBoxContainer.new()
	enemy_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_inner.add_theme_constant_override("separation", 2)
	enemy_zone.add_child(enemy_inner)

	var enemy_label := Label.new()
	enemy_label.text = "ENEMY"
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_label.add_theme_font_size_override("font_size", 11)
	enemy_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35, 0.55))
	enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_inner.add_child(enemy_label)

	var enemy_row := HBoxContainer.new()
	enemy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_row.add_theme_constant_override("separation", 10)
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_inner.add_child(enemy_row)

	# Midline — thicker, with border styling
	_midline = ColorRect.new()
	_midline.custom_minimum_size = Vector2(0, 4)
	_midline.color = GILT
	_midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_midline)

	# Player territory — dark green tint background
	var player_zone := PanelContainer.new()
	player_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pz_style := StyleBoxFlat.new()
	pz_style.bg_color = Color(0.04, 0.12, 0.06, 0.35)
	pz_style.border_color = Color(0.18, 0.45, 0.22, 0.40)
	pz_style.border_width_top = 1
	pz_style.corner_radius_bottom_left = 8
	pz_style.corner_radius_bottom_right = 8
	pz_style.content_margin_left = 4
	pz_style.content_margin_right = 4
	pz_style.content_margin_top = 2
	pz_style.content_margin_bottom = 2
	player_zone.add_theme_stylebox_override("panel", pz_style)
	main_vbox.add_child(player_zone)

	var player_inner := VBoxContainer.new()
	player_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_inner.add_theme_constant_override("separation", 2)
	player_zone.add_child(player_inner)

	var player_label := Label.new()
	player_label.text = "YOUR SIDE"
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.add_theme_font_size_override("font_size", 11)
	player_label.add_theme_color_override("font_color", Color(0.35, 0.70, 0.45, 0.50))
	player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_inner.add_child(player_label)

	var player_row := HBoxContainer.new()
	player_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_row.add_theme_constant_override("separation", 10)
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	player_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_inner.add_child(player_row)

	for i in range(4):
		var e_slot := _make_lane_slot(true, i)
		enemy_row.add_child(e_slot)
		_enemy_slots.append(e_slot)
		var p_slot := _make_lane_slot(false, i)
		player_row.add_child(p_slot)
		_player_slots.append(p_slot)

	_hand_container = HBoxContainer.new()
	_hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_container.add_theme_constant_override("separation", -16)
	_hand_container.custom_minimum_size = Vector2(0, 210)
	_hand_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_hand_container)


func _make_lane_slot(is_enemy: bool, lane_idx: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(158, 0)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_theme_stylebox_override("panel", GameTheme.make_slot_style(is_enemy, lane_idx))
	var lbl := Label.new()
	lbl.text = "Lane %d" % (lane_idx + 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.30, 0.35))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot


func _place_lane_card(card_id: String, lane_idx: int, is_opponent: bool) -> void:
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.is_opponent = is_opponent
	card.is_on_battlefield = true
	card.card_data = CardDB.get_card_data(card_id)
	card.summoned_this_turn = true
	card.current_lane = lane_idx

	if is_opponent:
		_enemy_field[lane_idx] = card
		var slot = _enemy_slots[lane_idx]
		for child in slot.get_children():
			child.queue_free()
		slot.add_child(card)
	else:
		_player_field[lane_idx] = card
		var slot = _player_slots[lane_idx]
		for child in slot.get_children():
			child.queue_free()
		slot.add_child(card)
	card.destroyed.connect(_on_card_destroyed.bind(card))


func _place_card_in_slot(card: Control, lane_idx: int) -> void:
	_player_field[lane_idx] = card
	var slot = _player_slots[lane_idx]
	for child in slot.get_children():
		child.queue_free()
	slot.add_child(card)
	if not card.destroyed.is_connected(_on_card_destroyed.bind(card)):
		card.destroyed.connect(_on_card_destroyed.bind(card))
	# Connect floop click for toggling
	if card.has_floop() and not card.is_opponent:
		if not card.floop_clicked.is_connected(_on_floop_clicked.bind(card)):
			card.floop_clicked.connect(_on_floop_clicked.bind(card))
	# Show floop hint on battlefield creatures
	card.update_floop_display()


func _on_card_destroyed(card: Control) -> void:
	for i in range(4):
		if _player_field[i] == card:
			# Dead creatures are removed from the fight entirely (not recycled)
			_player_field[i] = null
			_restore_slot_label(_player_slots[i], i)
		if _enemy_field[i] == card:
			_enemy_field[i] = null
			_restore_slot_label(_enemy_slots[i], i)


func _restore_slot_label(slot: PanelContainer, lane_idx: int) -> void:
	await get_tree().process_frame
	if slot.get_child_count() == 0:
		var lbl := Label.new()
		lbl.text = "Lane %d" % (lane_idx + 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.30, 0.35))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)


func _nearest_lane_index(screen_pos: Vector2) -> int:
	var best_idx := 0
	var best_dist := INF
	for i in range(4):
		var slot_center = _player_slots[i].global_position + _player_slots[i].size * 0.5
		var d = abs(screen_pos.x - slot_center.x)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


# =====================================================================
#  HUD
# =====================================================================

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 12
	add_child(_hud_layer)

	# Top center: encounter name + phase
	var top := _make_panel(Vector2(0.5, 0.0), Vector2(-160, 10), Vector2(320, 68))
	_hud_layer.add_child(top)
	var floor_text = _encounter_name if _encounter_name != "" else "Floor %d" % RunState.current_floor
	_floor_label = _make_text_label(floor_text, 14, GILT)
	_floor_label.position = Vector2(0, 6)
	_floor_label.size = Vector2(320, 20)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_floor_label)
	_phase_label = _make_text_label("ROUND 1", 24, IVORY)
	_phase_label.position = Vector2(0, 28)
	_phase_label.size = Vector2(320, 34)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_phase_label)

	# Enemy HP bar — top center below encounter name
	var enemy_panel := _make_panel(Vector2(0.5, 0.0), Vector2(-100, 84), Vector2(200, 40))
	_hud_layer.add_child(enemy_panel)
	var enemy_bar = GameTheme.make_hp_bar(enemy_hp, enemy_max_hp, 180.0, 22.0, Color(0.95, 0.40, 0.25))
	enemy_bar.position = Vector2(10, 12)
	enemy_panel.add_child(enemy_bar)
	_enemy_hp_label = enemy_bar.get_node("Label")

	if _encounter_passive != "":
		var enc = EncounterDB.get_encounter(RunState.current_encounter_id)
		var passive_label = _make_text_label(enc.get("passive_desc", ""),
			11, Color(0.90, 0.65, 0.35))
		passive_label.anchors_preset = Control.PRESET_TOP_WIDE
		passive_label.position = Vector2(500, 128)
		passive_label.size = Vector2(600, 20)
		passive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud_layer.add_child(passive_label)

	# Player HP bar — bottom left
	var hp_panel := _make_panel(Vector2(0.0, 1.0), Vector2(16, -78), Vector2(170, 62))
	_hud_layer.add_child(hp_panel)
	var hp_caption := _make_text_label("HEALTH", 10, GILT)
	hp_caption.position = Vector2(10, 4)
	hp_caption.size = Vector2(150, 14)
	hp_panel.add_child(hp_caption)
	var player_bar = GameTheme.make_hp_bar(player_hp, player_max_hp, 150.0, 22.0, GameTheme.BLOOD_RED)
	player_bar.position = Vector2(10, 24)
	hp_panel.add_child(player_bar)
	_player_hp_label = player_bar.get_node("Label")

	# Mana pips — bottom left, next to HP
	var mana_panel := _make_panel(Vector2(0.0, 1.0), Vector2(196, -78), Vector2(170, 62))
	_hud_layer.add_child(mana_panel)
	var mana_caption := _make_text_label("MANA", 10, GILT)
	mana_caption.position = Vector2(10, 4)
	mana_caption.size = Vector2(150, 14)
	mana_panel.add_child(mana_caption)
	var pips = GameTheme.make_mana_pips(player_mana, player_max_mana)
	pips.position = Vector2(10, 26)
	mana_panel.add_child(pips)
	_mana_label = _make_text_label("%d / %d" % [player_mana, player_max_mana],
		14, GameTheme.MANA_BLUE)
	_mana_label.position = Vector2(10, 46)
	_mana_label.size = Vector2(150, 16)
	mana_panel.add_child(_mana_label)

	# Round counter — bottom right
	var turn_panel := _make_panel(Vector2(1.0, 1.0), Vector2(-140, -78), Vector2(120, 30))
	_hud_layer.add_child(turn_panel)
	_turn_label = _make_text_label("Round 1", 13, GILT)
	_turn_label.position = Vector2(0, 5)
	_turn_label.size = Vector2(120, 20)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_panel.add_child(_turn_label)

	_build_end_turn_button()
	_build_sacrifice_button()

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
	var btn := Button.new()
	btn.text = "END TURN  [E]"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -170
	btn.offset_top = -42
	btn.offset_right = -16
	btn.offset_bottom = -10
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
	btn.offset_left = -170
	btn.offset_top = -78
	btn.offset_right = -16
	btn.offset_bottom = -46
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
	_relic_panel = HBoxContainer.new()
	_relic_panel.anchor_left = 0.0
	_relic_panel.anchor_top = 0.0
	_relic_panel.offset_left = 16
	_relic_panel.offset_top = 16
	_relic_panel.offset_right = 400
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

func screen_shake(_amount: float) -> void:
	pass


func freeze_frame(_duration: float) -> void:
	pass


func screen_flash(_color: Color, _duration: float) -> void:
	pass


func _show_info(msg: String) -> void:
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	get_tree().create_timer(2.0).timeout.connect(func(): _info_label.text = "")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E, KEY_ENTER:
				_on_end_turn()
			KEY_S:
				if phase == Phase.PLAYER_TURN:
					if _sacrifice_mode:
						_cancel_sacrifice()
					else:
						_on_sacrifice_pressed()
