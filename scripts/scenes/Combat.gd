extends Control
## Combat.gd — design-doc combat: sequential + Swift, floop, spells.
## Round flow: draw → play/floop → Swift phase → player attacks →
## enemy attacks → deaths → discard → enemy places → passives → new round.
## Combat happens every round (no setup-only round).

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"

enum Phase { PLAYER_TURN, RESOLVING, GAME_OVER }
var phase := Phase.PLAYER_TURN
var round_number := 0

const MAX_BANKED_MANA: int = 2
const HAND_DRAW_PER_TURN: int = 4
const MAX_HAND_SIZE := 10
# ── Persistent-hand A/B toggle ────────────────────────────────────────────
# true  = PERSISTENT hand: unplayed cards are KEPT at end of turn, and the
#         start-of-round draw REFILLS up to HAND_REFILL_TARGET (draw-to-N).
#         You hold cards across turns and choose when to play them.
# false = original FRESH hand: discard the whole hand each turn and draw a
#         fixed HAND_DRAW_PER_TURN. Flip this const to A/B the two loops.
const PERSISTENT_HAND := true
const HAND_REFILL_TARGET := 5
# Battlefield repositioning — how many friendly creatures the player may drag to
# a new slot per turn. The cap is the opportunity cost: you can't re-solve the
# whole board every turn, so a move is a real commitment.
const MOVES_PER_TURN: int = 2
# Living Antagonist panel footprint (left margin of the enemy half).
const PRESENCE_W: int = 200
const PRESENCE_H: int = 372

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
# Decreasing counter used by ephemeral hand cards (Discover, copies, etc.) that
# need a unique deck_uid but must NOT be registered with RunState. We use
# negative numbers so they can never collide with real RunState deck_uids
# (which always increase from 0 via RunState._next_uid).
var _ephemeral_uid_counter: int = -1
var _enemy_deck: Array[Dictionary] = []
var _reinforcement: Dictionary = {}
var _encounter_passive: String = ""
var _encounter_name: String = ""
var _encounter_passive_desc: String = ""
var _encounter_preamble: String = ""
var _encounter_script: Array = []

# ── Mutator state — derived from RunState.current_mutator_id at setup.
# Empty / zero / false when no mutator is active so combat logic is unchanged.
var _mutator_id: String = ""
var _mutator_data: Dictionary = {}
var _mutator_enemy_keyword: String = ""    # stormy/ironclad/thorny
var _mutator_enemy_atk_buff: int = 0       # feral
var _mutator_enemy_hp_buff: int = 0        # hardened
var _mutator_player_keyword: String = ""   # swift_winds
var _mutator_weaken_player_hp: int = 0     # cursed
var _mutator_burn_per_round: int = 0       # burning
var _mutator_spell_cost_increase: int = 0  # taxed
var _mutator_hand_draw_reduce: int = 0     # famine
var _mutator_max_mana_increase: int = 0    # blessed
var _mutator_double_enemy_on_death: bool = false  # frenzied
var _mutator_hand_draw_increase: int = 0   # wisdom — additive vs the reduce field
var _mutator_scarred_dmg: int = 0          # scarred — applied once at fight setup
var _mutator_enemy_doom: int = 0           # doomed — Doom N on enemy front-liners
var _mutator_enemy_regen_hp: int = 0       # overgrown — +N HP + Regenerate on enemies

var _hand: Array[Control] = []
# Front rows — column-aligned with the midline (legacy name kept for compat).
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]
# Back rows — added in the 4x4 redesign. Same column ordering.
var _player_back: Array = [null, null, null, null]
var _enemy_back: Array = [null, null, null, null]

# Relic lookup cached at start of each turn (cleared on play).
var _relic_set: Dictionary = {}

var _targeting_spell: Control = null
var _targeting_data: Dictionary = {}
# When non-negative, the player has clicked a potion in the HUD that needs a
# target; the next click on a valid target resolves the potion. Right-click
# cancels. -1 = not targeting any potion.
var _targeting_potion_idx: int = -1
# Cached container for the potion HUD bar so the per-potion buttons can be
# rebuilt in-place when a potion is consumed without redrawing the whole HUD.
var _potion_bar_root: Control = null
var _first_creature_played: bool = false
var _first_spell_this_turn: bool = false
var _spells_cast_this_turn: int = 0  # counts spells AFTER they resolve — Combo trigger
var _spells_cast_this_fight: int = 0  # lifetime count — Hexblade scaling
# Per-fight count of Tallow Dolls already played. The Nth Doll enters with
# +(N-1)/+(N-1), so each one is bigger than the last. Reset only by scene
# reload (new Combat instance) — exactly what we want, per-fight scope.
var _tallow_dolls_played: int = 0
# Per-turn flag for Standard Bearer's "first 1-cost creature each turn"
# passive. Resets at start of each round in _start_round.
var _standard_bearer_fired_this_turn: bool = false
# Set true the turn a creature is sacrificed while Butcher's Cleaver is held.
# Consumed by the next creature played this turn (which then gets +2 ATK that
# persists for 2 rounds). Resets each turn.
var _butchers_cleaver_armed: bool = false
var _cards_played_this_turn: int = 0
# Battlefield repositions used this turn (see MOVES_PER_TURN). Reset each round.
var _moves_used_this_turn: int = 0
# [PACING] temp debug — flips true once any non-ATK intent badge shows this fight.
var _pacing_any_intent_shown: bool = false
# Number of upcoming card plays that get -1 cost (Ironclad Veteran floop).
# Each card played consumes one charge; resets at start of each round.
var _card_cost_discount: int = 0
var _last_spell_played_this_turn: Dictionary = {}
# Snapshot of the target the last spell hit — Echo replays the spell against
# the SAME creature instead of picking a new random target. WeakRef so a
# dead-then-freed target safely resolves to null.
var _last_spell_target_ref: WeakRef = null
var _last_spell_target_lane: int = -1
var _bonus_mana_next_turn: int = 0

# ── New relic state (Tier-S batch) ──
# spell_tome: true when 50%+ of the run deck is spells (computed at combat start).
var _spell_tome_active: bool = false
# mana_tide: charges of "next creature costs 1 less", armed each time mana banks.
var _mana_tide_creature_discount: int = 0
# blueprint: on_enter effect dict of the previous creature played this combat.
# When the next creature plays we replay this on it, then overwrite with the
# new creature's on_enter so the chain rolls forward.
var _blueprint_last_on_enter: Dictionary = {}
# reapers_scythe: floop dict stolen from the last sacrificed creature. Granted
# to (or overwrites) the next creature played, then cleared.
var _reapers_scythe_pending_floop: Dictionary = {}

# ── Round-2 relic state ──
# Stalwart's Anvil: first time a friendly takes damage each turn arms +1 mana.
var _stalwarts_anvil_fired_this_turn: bool = false
# Sigil of Hunger: once per round, a friendly death arms "next creature -1".
var _sigil_of_hunger_charge: int = 0
var _sigil_of_hunger_fired_this_round: bool = false
# Mana Drunkard: counts consecutive "spent all mana" turn-ends. At 2 we grant
# +1 max mana for the rest of this fight (additive into _mana_drunkard_bonus).
var _mana_drunkard_streak: int = 0
var _mana_drunkard_bonus: int = 0
# Mummified Hand: once-per-spell-cast, sets a random hand creature to cost 0
# this turn. Tracked by setting Card2D.set_meta("mummified_zero", true).
var _mana_pearl_zero_cost_armed: bool = false
# Pyromancer's Scar: first spell each combat is cast twice (same target).
var _pyromancers_scar_consumed: bool = false
var _doubling_active_spell: bool = false  # reentry guard for the second cast
# Reagent Pouch: first spell each combat is auto-Sharpened (+spell.value).
var _reagent_pouch_consumed: bool = false
# Acolyte's Tome: when a spell exhausts, draw 1. No additional state needed.
# Inkpot of Many: every 5th spell cast, copy a random spell to hand.
var _inkpot_counter: int = 0
# Hourglass Sigil: pending counter incremented at end of turn. At 5: gain rare.
var _hourglass_pending: int = 0
# Pen Nib: every 10th card played, prompt the player to pick a deck creature.
var _pen_nib_counter: int = 0
# Pen Nib: deck_uid chosen this fight to become 6/6 Piercing. Applied to live
# copies immediately and to future draws of this uid (per-fight; resets with the
# Combat scene each fight). -1 = none chosen yet.
var _pen_nib_buffed_uid: int = -1
# Soul Ledger: lifetime friendly death counter (across combats, persisted via
# MetaState would be ideal but we keep it per-fight for simplicity).
var _soul_ledger_counter: int = 0
# Stygian Soul: heals 1 HP per enemy death, capped at 5 per combat.
var _stygian_soul_healed: int = 0
# Blueprint chain reset on fight start so the chain doesn't span fights.
# (Already a Dictionary, reset is in _ready via fresh var init — Combat is
# instanced per fight so this is automatic. Same for the new vars above.)
# Champions Belt: turn 1 ATK bonus latch — cleared at start of round 2.
var _champions_belt_active: bool = false
# Frost Spike: first creature each combat gets Wither-1-on-attack.
var _frost_spike_consumed: bool = false
# Death Card: count of returns to hand for each card_id this fight (for the
# +1 cost stacking each subsequent return).
var _death_card_returns: Dictionary = {}
# Brainstorm: keywords of the first creature played this combat. Each round,
# the first creature played copies them.
var _brainstorm_first_keywords: Array = []
var _brainstorm_fired_this_round: bool = false
# Steady Banner: round-survivor tracker — set on cards when they enter, marked
# "survived" at round_end so +2 ATK persistent applies on next round_start.
# Turn-1 ATK -1 is applied in _effective_attack.
var _glowing_hand_spells_cast: int = 0  # per-combat counter
var _hero_kills_this_combat: int = 0  # tracks enemy creature deaths for Stygian Soul
# Counter-HUD badges: relic_id -> Label overlaid on its HUD chip, showing the
# relic's live counter (e.g. pen_nib 7/10). Rebuilt with the relic strip,
# text refreshed each _update_hud. See COUNTER_RELICS / _relic_counter_text.
var _relic_counter_badges: Dictionary = {}

# Reaper's Scythe / Death Card / etc. all use card_data mutation which is
# per-instance safe (card_data is duplicated in _resolve_card_data).

# Marked One event delayed-payoff. Snapshot from RunState at fight start
# (which also clears the RunState field), then added to max mana every round
# of this fight only. Lives on Combat so it doesn't bleed into the next one.
var _marked_one_mana_bonus: int = 0
# Per-round latch for the Bandit Camp encounter passive: prevents the mana
# steal from firing multiple times when the enemy places multiple
# reinforcements in one round. Reset to false in start_round.
var _bandit_steal_fired_this_round: bool = false
# Set true when the player confirms the end-turn warning dialog. Read+reset
# inside _on_end_turn to bypass re-prompting on the recursive re-entry.
var _end_turn_confirmed: bool = false
var _face_damage_taken_this_fight: int = 0
# Familiar: maps deck_uid -> {"atk": int, "hp": int} of permanent buffs applied
# this fight via Familiar floops. Re-applied on draw so a buffed card retains
# its bonus through shuffle cycles.
var _familiar_buffs: Dictionary = {}
var _friendly_deaths_this_fight: int = 0
var _friendly_deaths_this_round: int = 0
var _last_dead_creature_id: String = ""
# Mirrors _last_dead_creature_id but stores the dying card's deck_uid so we can
# push a properly-formatted "card_id#uid" pile entry instead of a bare card_id
# (which would create an un-upgradable / mis-tracked copy). -1 means "no uid"
# (e.g. dying card was a token).
var _last_dead_creature_uid: int = -1
var _grave_pact_active: bool = false
var _soul_lantern_used_this_round: bool = false
var _battle_scars_triggered_this_fight: bool = false
var _resonance_crystal_used_this_fight: bool = false
var _gravewardens_rebirths: int = 0  # Gravewarden's Pact — Imp rebirths used this fight
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
var _phase_label: Label
var _player_hp_label: Label
var _incoming_dmg_label: Label  # the number inside the threat chip
var _incoming_dmg_chip: PanelContainer  # framed "incoming face damage" indicator
var _incoming_dmg_icon: TextureRect  # crossed-swords / skull glyph in the chip
var _enemy_hp_label: Label
var _mana_label: Label
var _turn_label: Label
var _info_label: Label
var _floor_label: Label
var _end_turn_btn: Button
var _relic_panel: GridContainer
# HP bar fill tweens — kept so rapid HP changes re-target a single drain
# animation instead of stacking competing tweens.
var _player_hp_tween: Tween = null
var _enemy_hp_tween: Tween = null
# ── Low-HP dread overlay (JUICE) ──
# A breathing red screen-edge vignette + soft heartbeat that engages when the
# player drops to/below the danger line and clears the moment HP recovers.
var _low_hp_active: bool = false
var _low_hp_vignette: Panel = null
var _low_hp_tween: Tween = null
var _low_hp_vignette_peak: float = 0.42  # max alpha of the breathe, deepens near 0 HP
# ── Notable-death hitstop (JUICE) ──
# Coalesces multiple deaths that land in the same frame so a wipe of several
# creatures produces ONE weighty hit-stop instead of stacking pauses. Armed by
# _note_death and consumed by a deferred call.
var _deaths_this_frame: int = 0
var _death_hitstop_armed: bool = false

# ── Living Antagonist (enemy presence) ────────────────────────────────────
# The encounter's signature creature, looming on the left of their half: lit,
# emerging from shadow, and REACTING to the fight (flinch on damage, lean-in on
# phase shifts, spoken barks). Replaces the old 84px "FOE" disc. This is the
# "someone is across the table from you" lever — see _build_enemy_presence.
var _enemy_presence: Control = null
var _presence_art: TextureRect = null
var _presence_flash: ColorRect = null         # red hit-flash overlay
var _presence_hp_fill: ColorRect = null       # antagonist health bar fill
var _presence_bark: Label = null              # spoken-line caption
var _presence_bark_scrim: Panel = null        # soft dark scrim behind the bark
var _presence_bark_tween: Tween = null
var _presence_react_tween: Tween = null

# Board container (no effects)
var _board_container: Control

# Colors — local aliases for GameTheme constants used heavily in this file.
const GILT := Color(0.82, 0.66, 0.30, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)


func _ready() -> void:
	set_process(false)
	_rebuild_relic_cache()
	_compute_spell_tome()
	_floop_tutorial_shown = UserSettings.floop_tutorial_seen
	_banking_tutorial_shown = UserSettings.banking_tutorial_seen
	_intents_tutorial_shown = UserSettings.intents_tutorial_seen
	_pile_tutorial_shown = UserSettings.pile_tutorial_seen
	_swap_background_for_act()
	_setup_fight_state()
	# Music: bosses + elites use a fixed track; standard fights pull from a
	# per-act pool so consecutive fights never start on the same song (the
	# random picker excludes the currently-playing track). Act 3 escalates to
	# heavier tracks. AudioBank no-ops if a file is missing.
	var node_type: String = RunState.current_node_type
	var act: int = RunState.get_act()
	match node_type:
		"boss":
			AudioBank.play_music("combat_boss_act3" if act >= 3 else "combat_boss")
		"elite":
			AudioBank.play_music("combat_elite")
		_:
			var pool: Array
			match act:
				2: pool = ["combat_act2", "combat_act2_b"]
				3: pool = ["combat_act3", "combat_act3_b"]
				_: pool = ["combat", "combat_act1_b"]
			AudioBank.play_music_random(pool)
	_build_board()
	_build_ambient_fx()
	# Cinematic per-act/per-encounter grade — must follow _build_ambient_fx so
	# the CombatBg / Vignette / HearthGlow / StageLight / AmbientEmbers nodes it
	# re-tones already exist.
	_build_grade_overlay()
	_apply_combat_mood()
	_build_hud()
	_init_decks()
	_place_starting_board()
	# Living Antagonist makes its entrance once the board is set.
	get_tree().create_timer(0.45).timeout.connect(presence_enter)
	# Pre-bake static-display textures for every unique card in the draw
	# pile so when _draw_card spins up a Card2D with live_baked_mode=true
	# the cache is warm. ~2 frames per uncached card; if the deck has 15
	# unique cards that's ~30 frames (~500 ms) of one-time load, with
	# enemies fully placed on the board so the player sees the setup while
	# we bake. Cards drawn before the bake completes hit the v4 fallback
	# inside _build_layout — slower but visually identical.
	await _prebake_hand_textures()
	# Gambler's Coin: once at fight start, coin flip — draw 1 extra OR deal 3
	# to a random enemy. Lives here (after enemies are placed, before round 1
	# starts) so the damage option can find a target and the draw lands before
	# the player's first turn read.
	_apply_gamblers_coin()
	# Marked One event payoff: if the player took the mark in a prior event
	# room, the gift lands here — a free creature in front-left and/or a
	# whole-fight mana bonus. Both flags clear so the next combat is clean.
	_apply_marked_one_gift()
	# Combat-start relic bundle: each guard-checks its own _has_relic so this
	# stays a single entry point for "stuff that fires once when the fight
	# begins, after enemies are placed but before round 1 draws".
	_apply_combat_start_relics()
	# Boss / elite encounters get a dramatic intro banner (name + passive)
	# before the first round begins. Normal fights get a quick one only when
	# there is something to announce — a fight passive or a mutator — so the
	# threat is read before it fires; vanilla skirmishes start instantly.
	# node_type was already captured above for the music branch — reuse it.
	if node_type == "boss" or node_type == "elite":
		await _show_encounter_intro(node_type == "boss")
	elif _encounter_passive_desc != "" or has_mutator():
		await _show_encounter_intro(false, true)
	_start_round()


func _apply_gamblers_coin() -> void:
	if not _has_relic("gamblers_coin"):
		return
	if randf() < 0.5:
		draw_one()
	else:
		var enemies = _all_enemy_creatures()
		if enemies.size() > 0:
			enemies[randi() % enemies.size()].take_damage(3)
		else:
			damage_enemy_hero(3)


func _apply_marked_one_gift() -> void:
	# Consume both Marked One flags from RunState. The mana bonus is snapshot
	# to a local var that _start_round adds to max mana every round; the
	# creature is placed via summon_token (which auto-falls-through to the
	# back row if front-left is somehow occupied — e.g. encounter structure).
	_marked_one_mana_bonus = RunState.next_combat_mana_bonus
	RunState.next_combat_mana_bonus = 0
	var gift: Dictionary = RunState.next_combat_gift_creature
	RunState.next_combat_gift_creature = {}
	if not gift.is_empty():
		var atk: int = int(gift.get("atk", 2))
		var hp: int = int(gift.get("hp", 3))
		summon_token(atk, hp, 0, false, ROW_FRONT)


func _apply_combat_start_relics() -> void:
	# Bag of Marbles: 1 damage to every enemy on the field.
	if _has_relic("bag_of_marbles"):
		var dmg: int = int(RelicDB.get_relic("bag_of_marbles").get("value", 1))
		for e in _all_enemy_creatures():
			e.take_damage(dmg)
	# Champion's Belt: turn-1-only ATK buff. The +1 is applied in
	# _effective_attack via _champions_belt_active; we just flip the latch.
	if _has_relic("champions_belt"):
		_champions_belt_active = true
	# War Drum: pull a random creature from the player's draw pile and place
	# it in lane 1 (front-left). If lane 1 is occupied, summon_token's
	# fall-through to back row covers it.
	if _has_relic("war_drum"):
		_war_drum_spawn()
	# Witch's Brew: cast a random spell from the run deck at no cost, with
	# auto-targeting via _auto_target_for (reused from Chaos Imp).
	if _has_relic("witchs_brew"):
		_witchs_brew_cast()
	# Mark of Pain: shuffle 2 curses into the draw pile at fight start.
	if _has_relic("mark_of_pain"):
		var n: int = int(RelicDB.get_relic("mark_of_pain").get("value", 1))
		for _i in 2:  # always 2 per the relic desc
			_player_draw_pile.append(_pile_entry(CardDB.random_curse_id(), _ephemeral_uid_counter))
			_ephemeral_uid_counter -= 1
		_player_draw_pile.shuffle()
	# Toolbox: open a discover-style picker for 1 of 3 extra cards.
	if _has_relic("toolbox"):
		_show_discover("any", "")
	# Bottled Talisman: pull the player-bound card into the opening hand.
	if _has_relic("bottled_talisman"):
		_bottled_talisman_open()


func _war_drum_spawn() -> void:
	# Pick a random creature from the run deck (not curses, not spells) and
	# spawn it as a token in lane 1 front. Falls through to back if occupied.
	var creature_ids: Array[String] = []
	for cid in RunState.deck:
		if CardDB.is_curse(cid):
			continue
		var d: Dictionary = CardDB.get_card_data(cid)
		if d.get("type", "") == "creature":
			creature_ids.append(cid)
	if creature_ids.is_empty():
		return
	var pick: String = creature_ids[randi() % creature_ids.size()]
	var data: Dictionary = CardDB.get_card_data(pick)
	summon_token(int(data.get("atk", 1)), int(data.get("hp", 1)), 0, false, ROW_FRONT)


func _witchs_brew_cast() -> void:
	# Cast a random spell from the run deck at no cost, auto-targeted via the
	# same helper Chaos Imp uses. Skips curses + non-spell entries.
	var spell_ids: Array[String] = []
	for cid in RunState.deck:
		if CardDB.is_curse(cid):
			continue
		var d: Dictionary = CardDB.get_card_data(cid)
		if d.get("type", "") == "spell":
			spell_ids.append(cid)
	if spell_ids.is_empty():
		return
	var pick: String = spell_ids[randi() % spell_ids.size()]
	var data: Dictionary = CardDB.get_card_data(pick)
	var target: Control = _auto_target_for(data.get("targeting", "none"))
	var tlane: int = target.current_lane if target != null else -1
	_show_info("Witch's Brew casts %s!" % data.get("name", "a spell"))
	_resolve_spell(data, target, tlane)


func _bottled_talisman_open() -> void:
	# Pull the card the player bound to Bottled Talisman into the opening hand.
	# Binding happens at acquire (Reward/Shop/Treasure) or via the MapView
	# catch-all; if somehow still unbound or the bound card was later removed
	# from the deck, skip silently.
	var uid: int = RunState.bottled_talisman_uid
	if uid < 0:
		return
	var idx: int = RunState.deck_uids.find(uid)
	if idx < 0:
		return
	# Remove the bound card's existing draw-pile entry (matched by uid) so it is
	# not BOTH pulled to the opening hand AND drawn again later as a duplicate
	# uid — _init_decks already seeded the full deck into the pile above.
	for i in _player_draw_pile.size():
		if _entry_uid(_player_draw_pile[i]) == uid:
			_player_draw_pile.remove_at(i)
			break
	_player_draw_pile.push_front(_pile_entry(RunState.deck[idx], uid))
	draw_one()


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

# Per-act combat background swap. combat.tscn ships an Act 1 painting in its
# Background TextureRect; this rebinds the texture to act 2 / act 3 paintings
# when the player is deeper in the run. Falls back to whatever combat.tscn
# already had when an act-specific painting isn't on disk yet — so missing
# assets degrade gracefully instead of crashing or showing pink.
const COMBAT_BG_PATHS := {
	2: "res://assets/backgrounds/combat_arena_act2.png",
	3: "res://assets/backgrounds/combat_arena_act3.png",
}


func _swap_background_for_act() -> void:
	var act: int = RunState.get_act()
	if not COMBAT_BG_PATHS.has(act):
		return  # Act 1 uses the .tscn default
	var path: String = COMBAT_BG_PATHS[act]
	if not ResourceLoader.exists(path):
		return
	var bg := get_node_or_null("Background") as TextureRect
	if bg == null:
		return
	bg.texture = load(path)


func _setup_fight_state() -> void:
	player_max_hp = RunState.hero_max_hp
	player_hp = RunState.hero_hp
	_starting_hp = player_hp
	_init_mutator_state()
	var enc_id = RunState.current_encounter_id
	if enc_id != "":
		var enc = EncounterDB.get_encounter(enc_id)
		if not enc.is_empty():
			_encounter_id = enc_id
			# Successor Wars cross-act borrows: scale the fight to the map
			# slot it actually landed in (kingdoms pull their faction's
			# fights from other acts; demoted bosses fight at elite band).
			var t_act: int = RunState.get_act()
			var t_type: String = RunState.current_node_type \
				if RunState.current_node_type in ["combat", "elite", "boss"] else ""
			enemy_max_hp = _scale_enemy_hp(EncounterDB.get_face_hp(enc_id, t_act, t_type))
			_encounter_passive = enc.get("passive_id", "")
			_encounter_name = enc.get("name", "")
			_encounter_passive_desc = enc.get("passive_desc", "")
			_encounter_preamble = enc.get("preamble", "")
			_enemy_deck = EncounterDB.build_enemy_deck(enc_id, t_act)
			_enemy_deck.shuffle()
			_reinforcement = EncounterDB.get_reinforcement(enc_id, t_act)
			_boss_phases = EncounterDB.get_boss_phases(enc_id)
			# Phase thresholds are authored against the kit's own face HP —
			# rescale by the act ratio so a lord fought in act 3 still turns
			# phases at the same point in the bar. (Ascension deliberately
			# does NOT rescale thresholds; that drift is live behavior.)
			# Duplicate first: get_boss_phases returns the const array.
			var base_hp: int = int(enc.hp)
			var act_scaled_hp: int = EncounterDB.get_face_hp(enc_id, t_act, t_type)
			if act_scaled_hp != base_hp and base_hp > 0 and not _boss_phases.is_empty():
				_boss_phases = _boss_phases.duplicate(true)
				for ph in _boss_phases:
					ph.threshold = int(round(float(ph.threshold) * act_scaled_hp / base_hp))
			_reactive_passive = EncounterDB.get_reactive_passive(enc_id)
			_encounter_script = EncounterDB.get_encounter_script(enc_id)
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
	var data: Dictionary
	if uid >= 0:
		var idx := RunState.deck_uids.find(uid)
		if idx >= 0:
			data = RunState.get_upgraded_card_data(idx)
		else:
			data = CardDB.get_card_data(card_id)
	else:
		data = CardDB.get_card_data(card_id)
	# Apply any pending Familiar buffs accumulated this fight.
	if uid >= 0 and _familiar_buffs.has(uid):
		var buff: Dictionary = _familiar_buffs[uid]
		if data.get("type", "") == "creature":
			data["atk"] = int(data.get("atk", 0)) + int(buff.get("atk", 0))
			data["hp"] = int(data.get("hp", 0)) + int(buff.get("hp", 0))
	return data


func _apply_familiar_buff_live(target_uid: int, atk_buf: int, hp_buf: int) -> void:
	## Apply a Familiar's +atk/+hp buff to any live copy of `target_uid` in
	## hand or on the player's battlefield. Future draws of this uid will pick
	## the buff up via _resolve_card_data + _familiar_buffs.
	for c in _hand:
		if c != null and c.deck_uid == target_uid:
			c.card_data["atk"] = int(c.card_data.get("atk", 0)) + atk_buf
			c.card_data["hp"] = int(c.card_data.get("hp", 0)) + hp_buf
			c.current_atk = int(c.card_data["atk"])
			c.current_hp = int(c.card_data["hp"])
			c.update_stat_display()
	for r in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(false, r)
		for l in range(LANES_PER_ROW):
			var c = arr[l]
			if c != null and c.deck_uid == target_uid and c.current_hp > 0:
				c.card_data["atk"] = int(c.card_data.get("atk", 0)) + atk_buf
				c.card_data["hp"] = int(c.card_data.get("hp", 0)) + hp_buf
				c.current_atk += atk_buf
				c.current_hp += hp_buf
				c.update_stat_display()


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
	# Chaos Imp: cast a random spell from the card pool for free.
	# Auto-targets a random valid creature. Custom spells are allowed but a
	# denylist excludes ones that hurt the player (Bloodletting, Unholy Bargain),
	# sacrifice your own creatures (Offering, Fuel the Pyre, Mass Grave, Apocalypse),
	# or recurse (Echo). Previously the function filtered ALL custom spells,
	# which left the candidate pool nearly empty since almost every spell in
	# CardDB now routes through type:"custom".
	const CHAOS_DENY := {
		"offering": true, "fuel_the_pyre": true,  # sacrifice cost
		"bloodletting": true, "unholy_bargain": true, "dark_pact": true,  # self-harm
		"blood_tithe": true,  # face damage to self
		"mass_grave": true, "apocalypse": true,  # board-wipe player too
		"echo_spell": true,  # recursion
		"recycle": true, "scrap": true, "gambit": true, "war_chant": true,  # need player hand input
		"grave_robbery": true, "reanimate": true,  # need last-dead state
		"turbo": true,  # adds a curse
	}
	var candidates: Array = []
	for id in CardDB.CARD_POOL:
		if CHAOS_DENY.has(id):
			continue
		var d = CardDB.CARD_POOL[id]
		if d.get("type", "") == "spell" and not CardDB.is_curse(id):
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
	# Structures aren't valid creature targets — strip them out before rolling.
	if targeting in ["enemy_creature", "any_creature", "any"]:
		var ep := _all_enemy_creatures().filter(func(c): return not c.has_keyword("structure"))
		if ep.size() > 0:
			return ep[randi() % ep.size()]
	elif targeting == "friendly_creature":
		var fp := _all_player_creatures().filter(func(c): return not c.has_keyword("structure"))
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
		_player_draw_pile.append(CardDB.random_curse_id())
		_player_draw_pile.append(CardDB.random_curse_id())
	_player_draw_pile.shuffle()


func _place_starting_board() -> void:
	## Places enemies on the field at the START of the fight (before round 1).
	## 4x4: scales starting count up a touch since there are more slots, and
	## prefers front-row placement (back-row only used as overflow).
	##
	## Variety: randomized count (±1) and formation per fight so two runs of
	## the same encounter open differently. Formations: spread front, packed
	## front, split (front+back ambush), siege (back row only).
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")
	var act = enc.get("act", RunState.get_act())

	# Structures go down FIRST — they're board objects (Pyres, Mausoleums,
	# Altars) anchored to specific back-row lanes that drive the encounter's
	# signature mechanic. The normal creature fill_order below has a
	# defensive null-check that prevents it from overwriting structures.
	_spawn_encounter_structures(enc)

	var starting_count := 0
	match enc_type:
		"combat":
			# Base count varies by act, then ±1 random for fight-to-fight variety.
			var base: int = [2, 3, 3][act - 1]
			starting_count = clampi(base + randi_range(-1, 1), 1, 4)
		"elite":
			# Elites stay scarier — never just 1 creature on the field.
			starting_count = clampi((3 if act == 1 else 4) + randi_range(-1, 1), 2, 4)
		"boss":
			starting_count = 3

	var placed := 0
	var fill_order: Array = []

	# Pick a random formation. Each shapes the opening read differently:
	#   spread  — evenly-distributed front line (classic / default)
	#   packed  — clumped on one half of front (flanking pressure)
	#   split   — half front, half back (ambush formation)
	#   siege   — back row only (creates breathing room turn 1)
	var formations: Array[String] = ["spread", "packed", "split"]
	# Siege only makes sense with >=2 creatures, and only for non-boss fights.
	if starting_count >= 2 and enc_type != "boss":
		formations.append("siege")
	# Elites get more aggressive formations.
	if enc_type == "elite":
		formations = ["spread", "packed", "split"]
	var formation: String = formations[randi() % formations.size()]

	match formation:
		"spread":
			for l in _evenly_spread_lanes(starting_count):
				fill_order.append({"row": ROW_FRONT, "lane": l})
		"packed":
			# Cluster on one side: lanes 0-1 or 2-3, then overflow inward.
			var left_side: bool = randi() % 2 == 0
			var lanes: Array = [0, 1, 2, 3] if left_side else [3, 2, 1, 0]
			for l in lanes:
				fill_order.append({"row": ROW_FRONT, "lane": l})
		"split":
			# Half front, half back — picks alternating columns.
			var cols = [0, 1, 2, 3]
			cols.shuffle()
			var front_count: int = (starting_count + 1) / 2
			for i in range(cols.size()):
				if i < front_count:
					fill_order.append({"row": ROW_FRONT, "lane": cols[i]})
				else:
					fill_order.append({"row": ROW_BACK, "lane": cols[i]})
		"siege":
			# Back row only — opening turn has no front line, telegraphs trouble.
			for l in _evenly_spread_lanes(starting_count):
				fill_order.append({"row": ROW_BACK, "lane": l})

	# Fallback / overflow — fill remaining lanes if formation runs short.
	for l in range(LANES_PER_ROW):
		if not _slot_in_list(fill_order, ROW_FRONT, l):
			fill_order.append({"row": ROW_FRONT, "lane": l})
	var back_order = [0, 1, 2, 3]
	back_order.shuffle()
	for l in back_order:
		if not _slot_in_list(fill_order, ROW_BACK, l):
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
	_dbgp("[PACING] R%d open   | P_board:%d E_board:%d | P_HP:%d E_HP:%d" % [round_number, _all_player_creatures().size(), _all_enemy_creatures().size(), player_hp, enemy_hp])
	# Champion's Belt: turn-1-only ATK buff. Clear at round 2 start so the
	# bonus stops applying after the first round of combat.
	if round_number >= 2:
		_champions_belt_active = false
	# Tutorials — sequenced so new players see one tip per round, not a wall.
	# Intents tip on round 1 (when intent badges first appear above enemies);
	# pile tip on round 2 (when the discard pile is guaranteed non-empty).
	if round_number == 1:
		_maybe_show_intents_tutorial()
	elif round_number == 2:
		_maybe_show_pile_tutorial()
	_first_creature_played = false
	_first_spell_this_turn = false
	_spells_cast_this_turn = 0
	_butchers_cleaver_armed = false
	_standard_bearer_fired_this_turn = false
	_stalwarts_anvil_fired_this_turn = false
	_sigil_of_hunger_fired_this_round = false
	_brainstorm_fired_this_round = false
	# Tick down persistent ATK buffs (e.g. Butcher's Cleaver) on all creatures.
	for c in _all_creatures_both_sides():
		if c.persistent_atk_buff_rounds > 0:
			c.persistent_atk_buff_rounds -= 1
			if c.persistent_atk_buff_rounds <= 0:
				c.persistent_atk_buff = 0
			c.update_stat_display()
	_cards_played_this_turn = 0
	_moves_used_this_turn = 0
	_card_cost_discount = 0
	_last_spell_played_this_turn = {}
	_last_spell_target_ref = null
	_last_spell_target_lane = -1
	_friendly_deaths_this_round = 0
	_soul_lantern_used_this_round = false
	_extra_draws_this_turn = 0
	phase = Phase.PLAYER_TURN

	KeywordEffects.dispatch_start_of_round(self)
	# Riteforge: each Riteforge on the field gives ALL friendlies +1 ATK (+2 if
	# upgraded) permanently.
	for _rf in _all_player_creatures():
		if _rf.card_data.get("passive", "") == "riteforge_ramp":
			var rf_gain: int = 2 if bool(_rf.card_data.get("is_upgraded", false)) else 1
			for ally in _all_player_creatures():
				ally.current_atk += rf_gain
				ally.update_stat_display()
	# Warchief: ATK becomes number of friendly creatures on the board (+1 if
	# upgraded).
	for _wc in _all_player_creatures():
		if _wc.card_data.get("passive", "") == "warchief_aura":
			var wc_base: int = _all_player_creatures().size()
			if bool(_wc.card_data.get("is_upgraded", false)):
				wc_base += 1
			_wc.current_atk = wc_base
			_wc.update_stat_display()
	_dispatch_passive_start_of_round()
	# Warlord's Standard: snowballing front-row aggro. Every round after the
	# first, front-row friendlies gain permanent +1 ATK. Round 1 is setup-only,
	# so gating on round_number >= 2 means the first buff lands going into the
	# first real combat round.
	if _has_relic("warlords_standard") and round_number >= 2:
		var ws: int = int(RelicDB.get_relic("warlords_standard").get("value", 1))
		for c in _all_player_creatures():
			if c.current_row == ROW_FRONT:
				c.persistent_atk_buff += ws
				c.persistent_atk_buff_rounds = 99  # effectively permanent this fight
				c.update_stat_display()
	# Bulwark Engine: turtle/Armored payoff. Every round, Armored friendlies gain
	# +1 max HP (and heal the point) so a wall deck thickens over time.
	if _has_relic("bulwark_engine"):
		var be: int = int(RelicDB.get_relic("bulwark_engine").get("value", 1))
		for c in _all_player_creatures():
			if c.has_keyword("armored"):
				c.card_data["hp"] = int(c.card_data.get("hp", 0)) + be
				c.current_hp += be
				c.update_stat_display()
	# Reset phantom_veil one-per-round flag.
	set_meta("phantom_veil_used", false)
	# Mutator round-start chip damage (currently "burning").
	_mutator_round_start_tick()

	# Boss phase check
	_check_boss_phase_transition()

	# Scripted encounter beats — fire any events queued for this round.
	_run_encounter_script(round_number)

	# Assign + display intents for every enemy so the player can always read
	# what's coming. Non-boss enemies without intent cycles default to ATK
	# which now renders as a visible damage chip via _update_intent_display.
	_assign_intents()
	# Mark the creature the start-of-round passive will snipe, so the threat reads
	# on the board itself — not only as text. Read-only; uses the passive's own
	# target picker.
	_refresh_passive_threat_glow()

	# Escalation check
	_check_escalation()

	# Mana — unspent mana carries over (banked)
	var bank_cap = player_mana if _has_relic("ice_cream") else mini(player_mana, MAX_BANKED_MANA)
	var banked = bank_cap if round_number > 1 else 0
	player_max_mana = RunState.get_max_mana() + _bonus_mana_next_turn
	# Mutator: "Blessed" adds permanent max-mana for the duration of this fight.
	player_max_mana += _mutator_max_mana_increase
	# Marked One: +1 max mana for every round of this fight if the player took
	# the "mark on the heart" branch in the preceding event.
	player_max_mana += _marked_one_mana_bonus
	if _has_relic("lantern") and round_number == 1:
		player_max_mana += 1
	if _has_relic("happy_flower") and round_number > 0 and round_number % PASSIVE_HEAL_INTERVAL == 0:
		player_max_mana += 1
	# Leyline Conduit passive: +1 mana per alive conduit (both rows).
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == "mana_per_turn":
			player_max_mana += 1
	# Cavalry Sigil: +1 mana per EMPTY edge column (lanes 1 & 4, both rows clear).
	if _has_relic("cavalry_sigil"):
		var cav_val: int = int(RelicDB.get_relic("cavalry_sigil").get("value", 1))
		for col in [0, LANES_PER_ROW - 1]:
			if _player_field[col] == null and _player_back[col] == null:
				player_max_mana += cav_val
	# Junk Slot: 4+ empty board slots (both rows, both sides) → +1 max mana.
	if _has_relic("junk_slot") and _empty_player_slots_count() >= 4:
		player_max_mana += int(RelicDB.get_relic("junk_slot").get("value", 1))
	# Lean Mean: +1 max mana while the deck is ≤14 cards.
	if _has_relic("lean_mean") and RunState.deck.size() <= 14:
		player_max_mana += int(RelicDB.get_relic("lean_mean").get("value", 1))
	# Marathoner's Sash: +2 max mana (read from value).
	if _has_relic("marathoners_sash"):
		player_max_mana += int(RelicDB.get_relic("marathoners_sash").get("value", 2))
	# Bone Hourglass "mana_center": +1 max mana when both center lanes (1 & 2)
	# are filled. Checks both rows of those columns for any friendly.
	if _has_relic("bone_hourglass") and RunState.bone_hourglass_choice == "mana_center":
		var center_full := true
		for col in [1, 2]:
			if _player_field[col] == null and _player_back[col] == null:
				center_full = false
				break
		if center_full:
			player_max_mana += 1
	# Mana Drunkard / Skull Throne: per-fight cumulative max-mana grants.
	player_max_mana += _mana_drunkard_bonus
	# Clamp to 0 so debuffs (Bandit Camp's mana steal) can't push max_mana
	# negative. _bonus_mana_next_turn can be negative now that the bandit
	# passive applies a real -1 each round.
	player_max_mana = maxi(0, player_max_mana)
	_bonus_mana_next_turn = 0
	_bandit_steal_fired_this_round = false
	player_mana = player_max_mana + banked
	# Marathoner's Sash partial: round 1 starts with 1 mana (the "ramp" trade
	# for +2 max). Round 2+ flows normally so the +2 ceiling actually matters.
	if _has_relic("marathoners_sash") and round_number == 1:
		player_mana = 1
	# Tutorial: first round where mana actually carries over.
	if banked > 0:
		_maybe_show_banking_tutorial()
		# Mana Tide: banking arms a "next creature costs 1 less" charge.
		if _has_relic("mana_tide"):
			_mana_tide_creature_discount += int(RelicDB.get_relic("mana_tide").get("value", 1))

	# Per-turn cost meta cleared on every retained card so last turn's tags
	# don't keep zeroing the cost of cards held over by Runic Pyramid.
	for c in _hand:
		if c != null and is_instance_valid(c):
			c.set_meta("mummified_zero", false)
			c.set_meta("pact_of_embers_zero", false)
	# Snecko Eye: re-randomize the cost of every card already in hand (retained
	# from last turn). Newly drawn cards get randomized inside _draw_card.
	if _has_relic("snecko_eye"):
		for c in _hand:
			if c != null and is_instance_valid(c):
				_snecko_randomize_card_cost(c)

	# Looking Glass: sort the draw pile by cost so the cheapest comes off the
	# top in this turn's first draw. Must fire BEFORE the draws are scheduled.
	_apply_looking_glass()

	# Draw — staggered so cards deal in one at a time instead of fanning in
	# simultaneously. Each card already tweens from the deck into its hand slot
	# (Card2D.set_hand_target); spacing the spawns by ~80 ms makes the deal
	# read as a real motion sequence instead of a single fanned poof.
	# Per-turn draw. PERSISTENT_HAND switches the model (see the const header):
	#   • persistent → REFILL up to a target (draw-to-N). Draw-boosting relics
	#     raise the target; if the hand is already at/over target, draw_count = 0.
	#   • fresh → the original fixed HAND_DRAW_PER_TURN (+ relic/mutator mods).
	var draw_count: int
	if PERSISTENT_HAND:
		var target := HAND_REFILL_TARGET
		if _has_relic("snecko_eye"):
			target = int(RelicDB.get_relic("snecko_eye").get("value", 6))
		if _has_relic("couriers_bag") and round_number == 1:
			target += 1
		if _has_relic("tome_of_many") and RunState.deck.size() >= 20:
			target += int(RelicDB.get_relic("tome_of_many").get("value", 2))
		if _mutator_hand_draw_increase > 0:
			target += _mutator_hand_draw_increase
		if _mutator_hand_draw_reduce > 0:
			target = maxi(1, target - _mutator_hand_draw_reduce)
		draw_count = maxi(0, target - _hand.size())
		# Always deal at least one fresh card per turn. With the persistent hand,
		# holding a full hand (5+ at the default target) refilled to 0 cards, so a
		# turn could open with no new option — which felt dead. Guarantee a single
		# draw instead. draw_one() still respects MAX_HAND_SIZE, so a hand already
		# at 10 simply no-ops here (no overflow).
		if draw_count == 0:
			draw_count = 1
	else:
		draw_count = HAND_DRAW_PER_TURN
		# Snecko Eye: draws 6 instead of 4 (boss-relic trade for the cost chaos).
		if _has_relic("snecko_eye"):
			draw_count = int(RelicDB.get_relic("snecko_eye").get("value", 6))
		# Mutator: "Famine" trims the per-turn draw, never below 1 card.
		if _mutator_hand_draw_reduce > 0:
			draw_count = maxi(1, draw_count - _mutator_hand_draw_reduce)
		# Mutator: "Wisdom" — opposite of Famine, bumps the per-turn draw.
		if _mutator_hand_draw_increase > 0:
			draw_count += _mutator_hand_draw_increase
		if _has_relic("couriers_bag") and round_number == 1:
			draw_count += 1
		# Tome of Many: deck has 20+ cards → +2 extra draw.
		if _has_relic("tome_of_many") and RunState.deck.size() >= 20:
			draw_count += int(RelicDB.get_relic("tome_of_many").get("value", 2))
	for i in draw_count:
		if i == 0:
			draw_one()
		else:
			get_tree().create_timer(0.08 * float(i)).timeout.connect(draw_one)

	# Pact of Embers fires AFTER the last delayed draw lands so the highest-
	# cost candidate sees the freshly drawn hand. A pinch of slack on top of
	# the last draw's timer keeps it stable across animation jitter.
	if _has_relic("pact_of_embers") and draw_count > 0:
		var delay: float = 0.08 * float(draw_count) + 0.05
		get_tree().create_timer(delay).timeout.connect(_apply_pact_of_embers)

	# Board is interactive again — the player can reposition creatures (and floop)
	# during their turn. Cleared in _on_end_turn so grabs can't start mid-combat.
	Card2D.board_interactive = true
	_end_turn_btn.disabled = false
	_update_hud()
	_show_turn_banner()


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _targeting_spell != null:
		_cancel_targeting()
		return
	# End-turn warning: if the player still has playable actions, prompt
	# before ending the turn. Most accidental end-t}rn clicks happen at
	# exactly these moments. _end_turn_confirmed gates the recursive
	# re-entry — set true ONLY when the player confirms in the dialog.
	if UserSettings != null and UserSettings.end_turn_warning \
			and not _end_turn_confirmed and _has_playable_action():
		GameTheme.show_confirm_dialog(self,
			"End Turn?",
			"You still have mana or an action available.\n(Disable in Settings)",
			"END TURN",
			"KEEP PLAYING",
			Callable(self, "_on_end_turn_confirmed"))
		return
	_end_turn_confirmed = false
	_end_turn_btn.disabled = true
	phase = Phase.RESOLVING
	_clear_threat_flags()  # JUICE: drop the pre-combat threat outlines; the clash itself now reads
	Card2D.board_interactive = false
	_dbgp("[PACING] R%d commit | played:%d | P_board:%d E_board:%d | P_HP:%d E_HP:%d" % [round_number, _cards_played_this_turn, _all_player_creatures().size(), _all_enemy_creatures().size(), player_hp, enemy_hp])
	# Art of War: if no cards played, bonus mana next turn
	if _has_relic("art_of_war") and _cards_played_this_turn == 0:
		_bonus_mana_next_turn += 1
	# Mime: at end of turn, the player picks ONE creature-with-floop in hand to
	# play for free with its floop pre-armed. Skipped when nothing qualifies.
	if _has_relic("mime"):
		await _mime_trigger_floop_from_hand()
	_update_hud()

	# Resolve enemy intents (non-attack intents execute now)
	_resolve_intents()

	await _do_combat()


func _resolve_on_play_ability(card: Control, lane_idx: int, is_enemy: bool) -> void:
	var floop_data = card.card_data.get("on_play", {})
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
				var opp = get_opposing_card(lane_idx, is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
			"damage_opposing_grow":
				# Ratling: damage opposing AND gain permanent ATK whether or not
				# there was a target. The atk gain triggers even on an empty lane.
				var opp_g = get_opposing_card(lane_idx, is_enemy)
				if opp_g != null:
					opp_g.take_damage(floop_data.value)
				card.current_atk += int(floop_data.get("atk_gain", 1))
				card.update_stat_display()
			"damage_opposing_splash":
				var opp = get_opposing_card(lane_idx, is_enemy)
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
				var opp = get_opposing_card(lane_idx, is_enemy)
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
				var opp = get_opposing_card(lane_idx, is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
				card.take_damage(floop_data.get("self_damage", 1))
			"drain":
				var opp = get_opposing_card(lane_idx, is_enemy)
				if opp != null:
					opp.take_damage(floop_data.value)
					card.current_hp = mini(card.current_hp + floop_data.value, card.card_data.hp)
					card.update_stat_display()
			"execute":
				var opp = get_opposing_card(lane_idx, is_enemy)
				if opp != null and opp.current_hp <= floop_data.value:
					opp.take_damage(999)
			"slay_draw":
				var opp = get_opposing_card(lane_idx, is_enemy)
				if opp != null:
					var hp_before = opp.current_hp
					opp.take_damage(floop_data.value)
					if opp.current_hp <= 0 and not is_enemy:
						draw_one()
			"unleash_atk":
				var opp = get_opposing_card(lane_idx, is_enemy)
				if opp != null:
					opp.take_damage(card.effective_atk())
			"graveyard_damage":
				var opp = get_opposing_card(lane_idx, is_enemy)
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
			"grant_shield_adjacent":
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						var adj_c = friendly_field[adj_lane]
						if not adj_c.state.has_shield:
							adj_c.state.has_shield = true
							if adj_c.has_method("_spawn_keyword_chip"):
								adj_c._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
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
				# Lookout: peek at the top card; player keeps it on top or sends
				# it to the bottom. Awaited so combat doesn't resolve while the
				# modal is open (otherwise the "top of deck" the player sees may
				# already have been drawn by the time they click).
				if not is_enemy and _player_draw_pile.size() > 0:
					await _show_scry_modal()
			"reorder_deck":
				# Raven: reveal the top N cards and let the player click them
				# in their desired draw order (1st click = drawn first).
				if not is_enemy and _player_draw_pile.size() >= 2:
					await _show_reorder_modal(int(floop_data.value))
			"filter_draw":
				if not is_enemy:
					# Mule: draw FIRST, then pitch the worst card you now hold — you
					# choose the discard with full information and never end down a
					# card (the old discard-then-draw-1 was card-negative on a body
					# nobody picked). Net: replace Mule with a 1/3 + a free filter.
					draw_one()
					draw_one()
					if _hand.size() > 0:
						var picked: Array = await _show_discard_picker(1,
							"Mule — discard a card")
						for c in picked:
							_hand.erase(c)
							_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
							if c.get_parent() != null:
								c.get_parent().remove_child(c)
							c.queue_free()
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
					_card_cost_discount += int(floop_data.get("value", 1))
			"spawn_token_hand":
				if not is_enemy:
					var token_data = {
						"id": "token_hand", "name": "Cat Token", "type": "creature",
						"cost": 0, "atk": floop_data.get("atk", 1), "hp": floop_data.get("hp", 1),
						"rarity": "starter", "keywords": [], "desc": "Token. When played: deal 1 damage to the opposing creature.",
						"on_play": {"type": "damage_opposing", "value": 1}, "is_token": true
					}
					_draw_card(token_data.id)
			"buff_familiar_pick":
				# Familiar floop: buff the card discovered when this Familiar
				# was played. Track the buff in _familiar_buffs (re-applied on
				# draw) and immediately apply to any live copy in hand or play.
				if not is_enemy and card.has_meta("familiar_pick_uid"):
					var target_uid: int = card.get_meta("familiar_pick_uid")
					var atk_buf: int = floop_data.get("atk", 1)
					var hp_buf: int = floop_data.get("hp", 1)
					var current_entry: Dictionary = _familiar_buffs.get(target_uid, {"atk": 0, "hp": 0})
					current_entry.atk += atk_buf
					current_entry.hp += hp_buf
					_familiar_buffs[target_uid] = current_entry
					_apply_familiar_buff_live(target_uid, atk_buf, hp_buf)

			# --- MOVEMENT ---
			"relocate":
				# 4x4: relocate within the same row. Player picks the empty lane;
				# enemy picks random (no UI for enemy decisions).
				var empty_lanes: Array[int] = []
				for i in range(LANES_PER_ROW):
					if i != lane_idx and friendly_field[i] == null:
						empty_lanes.append(i)
				if empty_lanes.size() > 0:
					var new_lane: int
					if is_enemy:
						new_lane = empty_lanes[randi() % empty_lanes.size()]
					else:
						new_lane = await _pick_empty_lane(my_row, lane_idx,
							"Harpy — click an empty lane in your row")
						if new_lane < 0:
							break  # player cancelled; skip remaining pulses too
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
				if is_enemy:
					# Enemy: random pick (no UI for enemy decisions).
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
				else:
					var victim = await _pick_adjacent_friendly(lane_idx, my_row,
						"Necromancer — click an adjacent friendly to kill")
					if victim != null and is_instance_valid(victim):
						var vlane: int = victim.current_lane
						victim.take_damage(999)
						summon_token(floop_data.atk, floop_data.hp, vlane, is_enemy)
			"steal_atk":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				# Gate the drain on effective ATK so a 0-base creature buffed
				# above 0 (War Cry, Hexblade, etc.) still counts as drainable.
				# The actual subtraction still applies to base current_atk
				# because temp_atk_buff is a separate per-turn additive.
				if opp != null and opp.effective_atk() > 0:
					opp.current_atk = maxi(0, opp.current_atk - floop_data.get("value", 1))
					card.current_atk += floop_data.get("value", 1)
					opp.update_stat_display()
					card.update_stat_display()
			"devour_adjacent":
				# Devour bumps BOTH current_hp and card_data.hp (the max-HP cap).
				# Skipping card_data.hp meant the next regen/heal tick clamped
				# current_hp back down to the original cap, silently erasing
				# the devour gains. Mirrors the enemy "devour" ability path
				# (see _resolve_enemy_ability) which already does this right.
				if is_enemy:
					var adj: Array[int] = []
					if lane_idx > 0 and friendly_field[lane_idx - 1] != null:
						adj.append(lane_idx - 1)
					if lane_idx < 3 and friendly_field[lane_idx + 1] != null:
						adj.append(lane_idx + 1)
					if adj.size() > 0:
						var target_lane = adj[randi() % adj.size()]
						var victim = friendly_field[target_lane]
						if victim != null:
							card.current_atk += victim.effective_atk()
							card.current_hp += victim.current_hp
							card.card_data.hp += victim.current_hp
							card.update_stat_display()
							victim.take_damage(999)
				else:
					var victim = await _pick_adjacent_friendly(lane_idx, my_row,
						"Corpse Eater — click an adjacent friendly to devour")
					if victim != null and is_instance_valid(victim) and is_instance_valid(card):
						card.current_atk += victim.effective_atk()
						card.current_hp += victim.current_hp
						card.card_data.hp += victim.current_hp
						card.update_stat_display()
						victim.take_damage(999)
			"copy_opposing_floop":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null and opp.card_data.has("on_play"):
					var copied_floop = opp.card_data.on_play.duplicate(true)
					var orig_floop = card.card_data.on_play
					card.card_data.on_play = copied_floop
					await _resolve_on_play_ability(card, lane_idx, is_enemy)
					if is_instance_valid(card):
						card.card_data.on_play = orig_floop
			"swap_atk":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					# Swap effective ATK so temp/persistent buffs swap with the
					# creature (previously only base current_atk was swapped,
					# leaving e.g. a +2 War Cry buff on the wrong card —
					# visually swapped numbers but the math was wrong).
					var self_eff: int = card.effective_atk()
					var opp_eff: int = opp.effective_atk()
					var self_temp: int = card.temp_atk_buff
					var self_pers: int = card.persistent_atk_buff
					var opp_temp: int = opp.temp_atk_buff
					var opp_pers: int = opp.persistent_atk_buff
					# After swap each card's effective ATK equals the OTHER's
					# original effective ATK. Achieve that by setting the new
					# base to (opp_eff - own remaining additive buffs) — we
					# preserve each card's OWN temp/persistent buff layer so
					# the buff source identity (War Cry on me stays on me)
					# isn't violated.
					card.current_atk = maxi(0, opp_eff - self_temp - self_pers)
					opp.current_atk = maxi(0, self_eff - opp_temp - opp_pers)
					card.update_stat_display()
					opp.update_stat_display()
					# Snapshot the pre-swap raw base so end-of-round cleanup
					# can revert to it.
					card.set_meta("swap_atk_original", self_eff - self_temp - self_pers)
					opp.set_meta("swap_atk_original", opp_eff - opp_temp - opp_pers)
			"become_copy":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					# Snapshot the originals so end-of-round cleanup can revert.
					if not card.has_meta("is_copy"):
						card.set_meta("become_copy_original", {
							"atk": card.current_atk,
							"hp_cap": int(card.card_data.get("hp", card.current_hp)),
							"current_hp": card.current_hp,
							"keywords": card.card_data.get("keywords", []).duplicate(),
							"passive": card.card_data.get("passive", ""),
							"floop": card.card_data.get("on_play", {}).duplicate(true) if card.card_data.has("on_play") else null,
						})
					# Become the opposing creature for the round: stats, keywords,
					# passive, and (rare-tier) floop. We deliberately don't copy
					# on_death/on_enter because firing those mid-round would be
					# chaos.
					card.current_atk = opp.current_atk
					card.current_hp = opp.current_hp
					card.card_data["hp"] = int(opp.card_data.get("hp", opp.current_hp))
					card.card_data["keywords"] = opp.card_data.get("keywords", []).duplicate()
					if opp.card_data.has("passive"):
						card.card_data["passive"] = opp.card_data["passive"]
					if opp.card_data.has("on_play"):
						card.card_data["on_play"] = opp.card_data["on_play"].duplicate(true)
					card.update_stat_display()
					card.set_meta("is_copy", true)
			"blood_sacrifice":
				# Kill self, give adjacent +X ATK permanent. Counts as a real
				# sacrifice — triggers Bone Pile, Butcher's Cleaver, ON_PLAYER_SACRIFICE.
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						friendly_field[adj_lane].current_atk += floop_data.value
						friendly_field[adj_lane].update_stat_display()
				if not is_enemy:
					_trigger_player_sacrifice(card)
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

	# Mark stunned/frozen creatures as already-attacked so they skip combat (both rows).
	for c in _all_creatures_both_sides():
		if c.state.stunned or c.state.is_frozen:
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

	_cleanup_dead()

	# SIMULTANEOUS COMBAT — both sides attack per lane so dying creatures still
	# deal damage. Front row first, then back row.
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
		await _resolve_column_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)
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
	if attacker.has_attacked_this_turn:
		return
	if not attacker.can_attack():
		return

	# Pick target: opposing front in this column, else opposing back, else face.
	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]

	# Hydra (passive) OR Charge! spell (per-turn meta): strikes every opposing
	# creature at once (takes 1 back from each).
	if attacker.card_data.get("passive", "") == "attacks_all_lanes" or attacker.get_meta("charges_this_turn", false):
		await _resolve_hydra_attack(attacker, lane_idx, is_enemy)
		return
	# Siege Golem: a wall-breaker — only lands (face) damage through an empty
	# opposing column; blocked entirely if any creature stands opposite it.
	if attacker.card_data.get("passive", "") == "siege":
		attacker.has_attacked_this_turn = true
		if opp_front == null and opp_back == null and opponent_front_empty[lane_idx]:
			await _creature_hits_face(attacker, lane_idx, is_enemy)
		return

	# Structures (Pyres, Mausoleums, Altars, etc.) are board objects, not
	# combatants — they fill back-row slots but never absorb hits. If the
	# back-row slot holds a structure, treat the column as empty for attack
	# resolution: the attacker either bypasses through to face (if the front
	# is also empty) or just hits the front normally.
	if opp_front != null and opp_front.current_hp > 0:
		await _creature_attacks_creature(attacker, _redirect_target(opp_front, opp_is_enemy, lane_idx, ROW_FRONT), lane_idx, is_enemy)
	elif opp_back != null and opp_back.current_hp > 0 and not opp_back.has_keyword("structure"):
		# Front died or never existed — back row is now exposed.
		await _creature_attacks_creature(attacker, _redirect_target(opp_back, opp_is_enemy, lane_idx, ROW_BACK), lane_idx, is_enemy)
	elif opponent_front_empty[lane_idx]:
		# Empty column at start of combat → face damage (also fires if the
		# only thing in the back is a non-attackable structure).
		await _creature_hits_face(attacker, lane_idx, is_enemy)

	# Cleave: after the main hit, deal 1 to each adjacent opposing creature
	# (front preferred, back if front empty). Splash damage; does not trigger
	# poison or piercing — it's a rider, not a real attack.
	if is_instance_valid(attacker) and attacker.card_data.get("passive", "") == "cleave":
		_apply_cleave_splash(attacker, lane_idx, is_enemy)


func _resolve_swift_attack(lane_idx: int, row: int, is_enemy: bool,
		opponent_front_empty: Array[bool]) -> void:
	var attacker_field = _row_array(is_enemy, row)
	var card = attacker_field[lane_idx]
	if card == null or card.has_attacked_this_turn or not card.can_attack():
		return
	# Swift can also come from War Cry's per-turn buff (meta flag).
	var is_swift: bool = card.has_keyword("swift") or card.get_meta("war_cry_swift", false)
	if not is_swift:
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
	elif opp_back != null and not opp_back.has_keyword("structure"):
		# Structures are board objects — Swift attackers slip past them to
		# face damage (handled below) instead of plinking the Pyre.
		opponent = _redirect_target(opp_back, opp_is_enemy, lane_idx, ROW_BACK)

	if opponent != null:
		var atk = _effective_attack(card, lane_idx, is_enemy)
		_play_attack_tracer(_card_center(card), _card_center(opponent), is_enemy)
		if opponent.has_method("play_hit_recoil"):
			opponent.play_hit_recoil(is_enemy)
		_apply_thorns(opponent, card, is_enemy)
		var swift_hp_before: int = opponent.current_hp
		opponent.take_damage(atk)
		var swift_dealt: bool = opponent.current_hp < swift_hp_before
		# Poison: swift attacker with Poison kills defender on any hit
		if opponent.current_hp > 0 and atk > 0 and card.has_keyword("poison"):
			opponent.current_hp = 0
			opponent.update_stat_display()
			if opponent.has_method("_spawn_keyword_chip"):
				opponent._spawn_keyword_chip("POISON", Color(0.40, 0.90, 0.20))
			opponent.try_die()
		var was_lethal: bool = opponent.current_hp <= 0
		if was_lethal and (card.has_keyword("piercing") or (is_enemy and _has_encounter_passive_keyword(card, "piercing")) or card.get_meta("inspire_piercing", false)):
			_apply_piercing_overflow(card, opponent, lane_idx, is_enemy)
		# Keyword riders: Lifelink (heal on damage) + Rampage (+ATK on kill).
		_apply_combat_strike_riders(card, swift_dealt, was_lethal, is_enemy)
		if was_lethal:
			screen_shake(6.0)
			await _short_pause(HITSTOP_BEAT)
		elif atk >= HEAVY_HIT_DAMAGE:
			await _short_pause(HITSTOP_BEAT)
		else:
			await _short_pause(POST_HIT_BEAT)
	elif opponent_front_empty[lane_idx]:
		await _creature_hits_face(card, lane_idx, is_enemy)


func _apply_cleave_splash(attacker: Control, lane_idx: int, is_enemy: bool) -> void:
	# Cleave Hound: after the main hit, deal 1 to each adjacent opposing
	# creature. Hits front-row if present, otherwise back-row. Pure splash;
	# doesn't trigger thorns/poison/piercing.
	if not is_instance_valid(attacker):
		return
	var opp_is_enemy = not is_enemy
	for adj in [lane_idx - 1, lane_idx + 1]:
		if adj < 0 or adj >= LANES_PER_ROW:
			continue
		var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[adj]
		var opp_back = _row_array(opp_is_enemy, ROW_BACK)[adj]
		var target: Control = null
		if opp_front != null and opp_front.current_hp > 0:
			target = opp_front
		elif opp_back != null and opp_back.current_hp > 0:
			target = opp_back
		if target != null:
			target.take_damage(1)


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


# ═══════════════════════════════════════════
#  KEYWORD RIDERS — doom / rampage / lifelink
# ═══════════════════════════════════════════

func _detonate_doom(card: Control) -> void:
	# Doom hit 0: the creature explodes. Damage = its doom_damage override, else
	# its current effective ATK, dealt to the OPPOSING face (enemy doom → player
	# face, player doom → enemy face). Then it dies through the canonical destroy
	# path (take_damage(999) → try_die → _on_card_destroyed) so on_death effects,
	# relics, and reactive passives all fire normally — no hand-rolled death.
	if card == null or not is_instance_valid(card):
		return
	var is_enemy: bool = card.is_opponent
	var dmg: int = int(card.card_data.get("doom_damage", card.effective_atk()))
	# Ember Censer (Kindler signature) — YOUR Doom creatures detonate for +1.
	# Gated to player-side detonations so the relic reads as "your Doom" and
	# doesn't buff enemy bombs aimed at the player's face.
	if not is_enemy and _has_relic("ember_censer"):
		dmg += int(RelicDB.get_relic("ember_censer").get("value", 1))
	# Doom Herald — YOUR Doom creatures detonating draws a card. Gated to
	# player-side so enemy bombs don't fuel the player's hand. Drawn before the
	# detonation destroy so a full draw pile still feels the payoff.
	if not is_enemy and _has_relic("doom_herald"):
		for _i in int(RelicDB.get_relic("doom_herald").get("value", 1)):
			draw_one()
	# LOUD telegraph payoff: a red bloom + hard shake so the clock hitting zero
	# is unmistakable.
	screen_shake(12.0)
	spawn_ash_burst(_card_center(card), Color(1.0, 0.32, 0.16), 22)
	var chip_pos := card.global_position + Vector2(card.size.x * card.scale.x * 0.5, -14)
	spawn_floating_number(chip_pos, "DOOM!", Color(1.0, 0.30, 0.18), true)
	if AudioBank != null:
		AudioBank.play_sfx("hit_hero")
	if dmg > 0:
		if is_enemy:
			damage_player_hero(dmg)
		else:
			damage_enemy_hero(dmg)
	# Canonical destroy — fires on_death / relics / reactives uniformly.
	if is_instance_valid(card) and card.current_hp > 0:
		card.take_damage(999)


func _apply_combat_strike_riders(attacker: Control, dealt_damage: bool, defender_was_killed: bool, attacker_is_enemy: bool) -> void:
	# Shared post-strike rider for every combat-damage path (column / swift /
	# ranged / hydra / face). Keeps Rampage + Lifelink behaving identically no
	# matter which attack routine landed the hit.
	#   dealt_damage  — this strike landed > 0 damage (Lifelink heals).
	#   defender_was_killed — the target died to this strike (Rampage grows).
	if attacker == null or not is_instance_valid(attacker):
		return
	# Lifelink — heal the PLAYER once per strike (not per damage point) whenever
	# a friendly creature deals combat damage. Generic, reusable version of the
	# Vampire Lord passive (which also bundles +ATK and is kill-gated).
	if dealt_damage and not attacker_is_enemy and attacker.has_keyword("lifelink") and player_hp < player_max_hp:
		var ll: int = int(attacker.card_data.get("lifelink", 1))
		# Crimson Chalice — Lifelink heals an extra point per strike.
		if _has_relic("crimson_chalice"):
			ll += int(RelicDB.get_relic("crimson_chalice").get("value", 1))
		if ll > 0:
			player_hp = mini(player_hp + ll, player_max_hp)
			_show_lifelink_heal(ll)
			_update_hud()
	# Rampage — permanent +ATK on every combat kill, for the rest of the fight.
	if defender_was_killed and attacker.has_keyword("rampage"):
		var amt: int = int(attacker.card_data.get("rampage", 1))
		if bool(attacker.card_data.get("is_upgraded", false)):
			amt += 1
		# Berserker's Totem — every Rampage trigger grows an extra point.
		if not attacker_is_enemy and _has_relic("berserkers_totem"):
			amt += int(RelicDB.get_relic("berserkers_totem").get("value", 1))
		if amt > 0:
			attacker.persistent_atk_buff += amt
			attacker.persistent_atk_buff_rounds = 99  # effectively permanent this fight
			attacker.update_stat_display()
			var rp_pos := attacker.global_position + Vector2(attacker.size.x * attacker.scale.x * 0.5, -10)
			spawn_floating_number(rp_pos, "RAMPAGE +%d" % amt, Color(1.0, 0.62, 0.20), false)


func _show_lifelink_heal(amount: int) -> void:
	# Small green heal number near the player HP medallion.
	if amount <= 0:
		return
	if _player_hp_label != null:
		spawn_floating_number(_player_hp_label.get_global_rect().get_center() + Vector2(0, -6),
			"+%d" % amount, Color(0.40, 0.95, 0.45), false)
		_punch_label(_player_hp_label, 1.12)


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
	_dbgp("[COMBAT] %s %s (%d ATK) hits %s %s (%d/%d HP) in lane %d → %d dmg → %d HP left" % [
		who, attacker.card_data.name, atk,
		defender_side, defender.card_data.name, defender.current_hp, defender.card_data.hp,
		lane_idx, atk, maxi(0, defender.current_hp - atk)])
	# Impact lands: streak from attacker to target and the defender recoils.
	_play_attack_tracer(_card_center(attacker), _card_center(defender), attacker_is_enemy)
	if defender.has_method("play_hit_recoil"):
		defender.play_hit_recoil(attacker_is_enemy)
	var hp_before: int = defender.current_hp
	defender.take_damage(atk)
	# Did this strike actually remove HP? (A Shield absorbs the whole hit, so
	# atk > 0 but no damage was dealt — Lifelink shouldn't trigger on that.)
	var strike_dealt_damage: bool = defender.current_hp < hp_before
	attacker.has_attacked_this_turn = true
	# Poison: if attacker has Poison and dealt damage, defender dies regardless
	# of remaining HP. Shield absorbing the hit means no damage was dealt.
	if defender.current_hp > 0 and atk > 0 and attacker.has_keyword("poison"):
		defender.current_hp = 0
		defender.update_stat_display()
		if defender.has_method("_spawn_keyword_chip"):
			defender._spawn_keyword_chip("POISON", Color(0.40, 0.90, 0.20))
		defender.try_die()
	var was_lethal: bool = defender.current_hp <= 0

	# Royal Guard "+1 ATK when hit" (+2 if upgraded) — if the defender is a
	# Royal Guard and is still alive after the hit, it grows in fury.
	if defender.current_hp > 0 and defender.card_data.get("passive", "") == "royal_guard" and atk > 0:
		var rg_gain: int = 2 if bool(defender.card_data.get("is_upgraded", false)) else 1
		defender.current_atk += rg_gain
		defender.update_stat_display()

	if defender.current_hp <= 0 and (attacker.has_keyword("piercing") or (attacker_is_enemy and _has_encounter_passive_keyword(attacker, "piercing")) or attacker.get_meta("inspire_piercing", false)):
		_apply_piercing_overflow(attacker, defender, lane_idx, attacker_is_enemy)

	# Vampire Lord passive: heal 2 and +1 ATK on kill (+2 ATK if upgraded).
	if not attacker_is_enemy and attacker.card_data.get("passive", "") == "vampire_lord" and defender.current_hp <= 0:
		player_hp = mini(player_hp + 2, player_max_hp)
		var vamp_gain: int = 2 if bool(attacker.card_data.get("is_upgraded", false)) else 1
		attacker.current_atk += vamp_gain
		attacker.update_stat_display()

	# Keyword riders: Lifelink (heal on damage) + Rampage (+ATK on kill).
	_apply_combat_strike_riders(attacker, strike_dealt_damage, was_lethal, attacker_is_enemy)

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
	var face_dealt: bool = false
	if is_enemy:
		if _encounter_passive == "harpy_swift_face" and card.has_keyword("swift"):
			atk += 1
		var reduction = _get_wall_reduction(lane_idx, false)
		atk = maxi(0, atk - reduction)
		if atk > 0:
			damage_player_hero(atk)
			face_dealt = true
	else:
		damage_enemy_hero(atk)
		face_dealt = atk > 0

	card.has_attacked_this_turn = true
	# Keyword riders: Lifelink heals when this creature lands face damage (no
	# defender to kill, so Rampage never fires here).
	_apply_combat_strike_riders(card, face_dealt, false, is_enemy)
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
		# Lifelink heals once for the unblocked face swing.
		_apply_combat_strike_riders(attacker, atk > 0, false, is_enemy)
		await _short_pause(HITSTOP_BEAT)
		return
	# Bites through the whole line at once — streak + recoil on every target.
	# Lifelink heals once for the swing; Rampage grows once if anything died.
	var hydra_dealt: bool = false
	var hydra_killed: bool = false
	for t in live:
		_play_attack_tracer(_card_center(attacker), _card_center(t), is_enemy)
		if t.has_method("play_hit_recoil"):
			t.play_hit_recoil(is_enemy)
		var t_hp_before: int = t.current_hp
		t.take_damage(atk)
		if t.current_hp < t_hp_before:
			hydra_dealt = true
		if t.current_hp <= 0:
			hydra_killed = true
		if attacker.current_hp > 0:
			attacker.take_damage(1)
	if is_instance_valid(attacker):
		_apply_combat_strike_riders(attacker, hydra_dealt, hydra_killed, is_enemy)
	screen_shake(6.0)
	await _short_pause(HITSTOP_BEAT)


func _redirect_target(defender: Control, defender_is_enemy: bool, lane_idx: int, row: int) -> Control:
	# Royal Guard's redirect floop: a friendly Royal Guard in the same row that
	# is "redirecting" and sits adjacent to the intended defender intercepts the
	# blow in its place.
	# Guardian keyword: permanently redirects adjacent attacks (no floop needed).
	var field = _row_array(defender_is_enemy, row)
	for adj in [lane_idx - 1, lane_idx + 1]:
		if adj >= 0 and adj < LANES_PER_ROW:
			var g = field[adj]
			if g != null and g.current_hp > 0:
				if g.get_meta("redirecting", false) and g.card_data.get("passive", "") == "royal_guard":
					return g
				if g.has_keyword("guardian"):
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
				if card == null:
					continue
				# Catapult Crew (player only, back row only): grant Ranged via the
				# combat-resolution lookup so we don't have to mutate every back-
				# row creature's keyword list on placement / row swap.
				var has_ranged: bool = card.has_keyword("ranged") \
					or (not is_enemy and row == ROW_BACK and _has_relic("catapult_crew"))
				if not has_ranged:
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
					var rng_hp_before: int = ranged_target.current_hp
					ranged_target.take_damage(atk)
					var rng_dealt: bool = ranged_target.current_hp < rng_hp_before
					var rng_killed: bool = ranged_target.current_hp <= 0
					# Keyword riders: Lifelink (heal on damage) + Rampage (+ATK on kill).
					_apply_combat_strike_riders(card, rng_dealt, rng_killed, is_enemy)
					await _short_pause(HITSTOP_BEAT if ranged_target.current_hp <= 0 else POST_HIT_BEAT)
				else:
					if is_enemy:
						damage_player_hero(atk)
					else:
						damage_enemy_hero(atk)
					# Lifelink heals on the unblocked face shot.
					_apply_combat_strike_riders(card, atk > 0, false, is_enemy)
					await _short_pause(POST_HIT_BEAT)


func _apply_thorns(defender: Control, attacker: Control, attacker_is_enemy: bool) -> void:
	# Thorns can be intrinsic, encounter-passive granted, or temp from Shield Wall.
	# Bridge Watcher / Corner Stone relics grant Thorns 2 by lane position to the
	# player's creatures — checked alongside the existing sources so the relics
	# stack with intrinsic thorns rather than replacing them.
	var defender_is_friendly: bool = attacker_is_enemy
	var has_thorns: bool = defender.has_keyword("thorns") \
		or (not attacker_is_enemy and _has_encounter_passive_keyword(defender, "thorns")) \
		or defender.get_meta("shield_wall_thorns", false) \
		or (defender_is_friendly and _has_relic("bridge_watcher") \
			and defender.current_lane in [1, 2]) \
		or (defender_is_friendly and _has_relic("corner_stone") \
			and defender.current_lane in [0, LANES_PER_ROW - 1])
	if has_thorns and defender.current_hp > 0:
		var thorns_dmg = 1
		if not attacker_is_enemy and _has_relic("briar_amulet"):
			thorns_dmg = 2
		# Bridge Watcher / Corner Stone explicitly grant Thorns 2.
		if defender_is_friendly \
				and ((_has_relic("bridge_watcher") and defender.current_lane in [1, 2]) \
					or (_has_relic("corner_stone") and defender.current_lane in [0, LANES_PER_ROW - 1])):
			thorns_dmg = maxi(thorns_dmg, 2)
		# Note: Spike Driver fires from _on_friendly_damaged regardless of
		# thorns, so don't add it here — would double-count vs thorns carriers.
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
		if _has_relic("glass_cannon"):
			atk += 1
		if _has_relic("stone_skin"):
			atk = maxi(0, atk - 1)
		# Vanguard Banner: front-row friendlies get +1 ATK.
		if card.current_row == ROW_FRONT and _has_relic("vanguard_banner"):
			atk += 1
		# Linked Banner: friendlies with 2+ adjacent friendlies get +1 ATK
		# (HP half is applied as a snapshot in _apply_linked_banner_hp).
		if _has_relic("linked_banner") and _count_adjacent_friendlies(card) >= 2:
			atk += 1
		# Champion's Belt: turn-1-only buff. Latch is cleared at round 2 start.
		if _champions_belt_active and _has_relic("champions_belt"):
			atk += int(RelicDB.get_relic("champions_belt").get("value", 1))
		# Phalanx Stone: all 4 front lanes full → every friendly gets +1 ATK.
		if _has_relic("phalanx_stone") and _front_row_full(false):
			atk += int(RelicDB.get_relic("phalanx_stone").get("value", 1))
		# The Family: 3+ creatures with the same id on the field → +1 ATK each.
		if _has_relic("the_family") and _same_id_count_on_field(card.card_id) >= 3:
			atk += int(RelicDB.get_relic("the_family").get("value", 1))
		# Du-Vu Doll: +1 ATK per Curse currently in the run deck.
		if _has_relic("du_vu_doll"):
			atk += _curse_count_in_deck() * int(RelicDB.get_relic("du_vu_doll").get("value", 1))
		# Diagonal Crest: diagonal friendlies count as adjacent (the HP +1
		# half is granted at placement via _apply_linked_banner_hp's broader
		# rescan; ATK part falls through the linked_banner branch since both
		# relics share the "needs 2 adj" condition when held together).
		# When ONLY diagonal_crest is held, the adj_buff bonus is delivered
		# via _get_adj_buff_atk through the diagonal-aware lookup below.
		# Steady Banner: turn-1 ATK debuff. The +2 persistent buff is granted
		# in _end_round to surviving creatures.
		if round_number == 1 and _has_relic("steady_banner"):
			atk = maxi(0, atk - 1)
	return maxi(0, atk)


func _front_row_full(is_enemy: bool) -> bool:
	for c in _row_array(is_enemy, ROW_FRONT):
		if c == null:
			return false
	return true


func _same_id_count_on_field(card_id: String) -> int:
	var n := 0
	for c in _all_player_creatures():
		if c.card_id == card_id:
			n += 1
	return n


func _curse_count_in_deck() -> int:
	var n := 0
	for cid in RunState.deck:
		if CardDB.is_curse(cid):
			n += 1
	return n


func _deck_creature_ratio() -> float:
	if RunState.deck.is_empty():
		return 0.0
	var creatures: int = 0
	for cid in RunState.deck:
		if CardDB.get_card_data(cid).get("type", "") == "creature":
			creatures += 1
	return float(creatures) / float(RunState.deck.size())


func _mime_trigger_floop_from_hand() -> void:
	# Mime: the player picks ONE creature-with-floop in hand; it's played for
	# free with its floop pre-armed for this turn's resolution. The card stays
	# on the board afterward (it WAS played — the relic just made it free).
	# Cancellable: closing the picker skips Mime for this turn.
	var candidates: Array[Control] = []
	for c in _hand:
		if c != null and is_instance_valid(c) and c.is_creature() and c.card_data.has("on_play"):
			candidates.append(c)
	if candidates.is_empty():
		return
	# No room to place — don't even open the picker.
	if _pick_empty_for_summon(false, ROW_FRONT).is_empty():
		return
	var candidate: Control = await _show_mime_picker(candidates)
	if candidate == null or not is_instance_valid(candidate) or not _hand.has(candidate):
		return
	var slot := _pick_empty_for_summon(false, ROW_FRONT)
	if slot.is_empty():
		return
	_hand.erase(candidate)
	if candidate.get_parent() != null:
		candidate.get_parent().remove_child(candidate)
	candidate.is_on_battlefield = true
	candidate.current_row = slot.row
	candidate.current_lane = slot.lane
	candidate.set_compact_mode(true)
	_place_card_in_slot(candidate, slot.lane, slot.row)
	_first_creature_played = true
	# Mime triggers the card's on-play ability for free.
	if candidate.card_data.has("on_play"):
		_resolve_on_play_ability(candidate, slot.lane, false)


func _show_mime_picker(candidates: Array[Control]) -> Control:
	## Mime end-of-turn picker: show the hand creatures-with-floop; the player
	## clicks one (returned) or cancels (null). Modeled on _show_recycle_modal.
	if candidates.is_empty():
		return null
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.80)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Mime — floop a creature for free"
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = mini(candidates.size(), 6)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)

	var result := {"card": null, "cancelled": false}
	for hand_card in candidates:
		var data: Dictionary = hand_card.card_data
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(220, 300)
		grid.add_child(slot)
		var display = CARD_SCENE.instantiate()
		display.card_id = hand_card.card_id
		display.card_data = data.duplicate(true)
		display.is_on_battlefield = true
		slot.add_child(display)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var captured: Control = hand_card
		btn.pressed.connect(func():
			result["card"] = captured
			overlay.queue_free()
		)
		slot.add_child(btn)

	var cancel := GameTheme.make_back_button("CANCEL", Vector2(160, 40))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func():
		result["cancelled"] = true
		overlay.queue_free()
	)
	col.add_child(cancel)

	while result["card"] == null and not result["cancelled"] and is_instance_valid(overlay):
		await get_tree().process_frame
	return result["card"]


func _empty_player_slots_count() -> int:
	var n := 0
	for row in [ROW_FRONT, ROW_BACK]:
		for c in _row_array(false, row):
			if c == null:
				n += 1
	return n


func _apply_pact_of_embers() -> void:
	# Pact of Embers: find the highest-cost card in hand RIGHT NOW (after all
	# draws settled) and zero its cost for this turn via a meta flag. Tied
	# cards: pick the first encountered (left-most in fan).
	if not _has_relic("pact_of_embers"):
		return
	var best: Control = null
	var best_cost: int = -1
	for c in _hand:
		if c == null or not is_instance_valid(c):
			continue
		var cc: int = int(c.card_data.get("cost", 0))
		if cc > best_cost:
			best_cost = cc
			best = c
	if best != null:
		best.set_meta("pact_of_embers_zero", true)
		_refresh_hand_affordability()


func _apply_looking_glass() -> void:
	# Looking Glass: the first card drawn each turn should be the cheapest in
	# the draw pile. We resolve this by SORTING the draw pile by cost ascending
	# BEFORE the turn's normal draws fire, so the cheapest naturally lands
	# first. The sort only impacts the first draw — subsequent draws come from
	# the now-cheapest-first ordered pile, but that's a one-frame artifact
	# (the pile reshuffles on its next refill anyway).
	if not _has_relic("looking_glass"):
		return
	if _player_draw_pile.is_empty():
		return
	# Stable sort by resolved cost.
	_player_draw_pile.sort_custom(func(a: String, b: String) -> bool:
		var aid := _entry_id(a)
		var auid := _entry_uid(a)
		var bid := _entry_id(b)
		var buid := _entry_uid(b)
		var ac: int = int(_resolve_card_data(aid, auid).get("cost", 99))
		var bc: int = int(_resolve_card_data(bid, buid).get("cost", 99))
		return ac < bc)


func _count_adjacent_friendlies(card: Control) -> int:
	# "Adjacent" per the design doc: ±1 column, both rows count. Same-column
	# other-row does NOT count. Used by linked_banner and any future relics
	# that gate on adjacency density.
	#
	# Sentinel Pact: empty lanes count as friendlies. Lets thin-board players
	# benefit from adjacency-density relics without forcing a wide field.
	if card == null or not is_instance_valid(card):
		return 0
	var lane: int = card.current_lane
	var count := 0
	var sentinel: bool = _has_relic("sentinel_pact")
	for adj_lane in [lane - 1, lane + 1]:
		if adj_lane < 0 or adj_lane >= LANES_PER_ROW:
			continue
		for row in [ROW_FRONT, ROW_BACK]:
			var field = _row_array(false, row)
			if field[adj_lane] != null:
				count += 1
			elif sentinel:
				count += 1
	return count


func _apply_linked_banner_hp() -> void:
	# HP half of Linked Banner: scan every friendly; any that NOW has 2+
	# adjacents and hasn't been buffed yet gets +1 max HP and +1 current HP.
	# Called after each creature placement so newly-adjacent allies catch up.
	# The buff is permanent for the rest of combat — we deliberately don't
	# pull it back when a neighbor dies (mirrors how Veteran's Medal and
	# Stone Skin grant non-revocable +HP).
	#
	# Diagonal Crest: when held alongside Linked Banner (or alone), bumps the
	# HP grant from +1 to +2. Stacks the "extra HP on adjacency" payoff cleanly
	# instead of needing its own scan.
	if not _has_relic("linked_banner") and not _has_relic("diagonal_crest"):
		return
	var bonus: int = 1
	if _has_relic("diagonal_crest"):
		bonus += int(RelicDB.get_relic("diagonal_crest").get("value", 1))
	for c in _all_player_creatures():
		if c.get_meta("linked_banner_buffed", false):
			continue
		if _count_adjacent_friendlies(c) >= 2:
			c.card_data["hp"] = int(c.card_data.get("hp", c.current_hp)) + bonus
			c.current_hp += bonus
			c.set_meta("linked_banner_buffed", true)
			c.update_stat_display()


func _get_adj_buff_atk(lane_idx: int, is_enemy: bool) -> int:
	# 4x4: adjacent-buff sources contribute from the same row as the attacker.
	# For now we sum both rows of the same column-1/column+1 because front and
	# back share the lane semantically — this keeps Bannerman-style cards
	# strong without needing a row-aware Card2D ref here.
	#
	# NOTE: adj_buff.hp is currently NOT applied anywhere. Every card in CardDB
	# sets hp:0 so the omission is harmless today, but if you author a card
	# with hp adjacency, also wire it up here AND in _on_card_destroyed so the
	# buff is removed when the source dies. See follow-up in tools/_sync_sim.py
	# for places that mirror this logic.
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
	# Most deaths flow through Card2D.take_damage → try_die → _die → destroyed
	# signal, which Combat handles in _on_card_destroyed (including on_death
	# dispatch, encounter hooks, reactive triggers, Phantom Veil, Reborn, etc.).
	# This function is a fallback for paths that mutate current_hp directly
	# without calling try_die — e.g. the poison post-hit overrides at
	# Combat.gd:_resolve_swift_attack / _creature_attacks_creature.
	for row in [ROW_FRONT, ROW_BACK]:
		for is_enemy in [false, true]:
			var arr = _row_array(is_enemy, row)
			for lane_idx in range(LANES_PER_ROW):
				var c = arr[lane_idx]
				if c != null and is_instance_valid(c) and c.current_hp <= 0:
					c.try_die()


func _on_friendly_death(card: Control, _lane_idx: int) -> void:
	_friendly_deaths_this_fight += 1
	_friendly_deaths_this_round += 1
	_last_dead_creature_id = card.card_id
	# Track the uid alongside the id so consumers (Grave Robbery, Grave Pact)
	# can push a proper "card_id#uid" pile entry. Tokens / synthetic cards
	# leave -1 here, which _resolve_card_data already handles.
	_last_dead_creature_uid = card.deck_uid
	if _friendly_deaths_this_round == 1 and _has_passive_on_field("draw_on_ally_death"):
		draw_one()
	# Corpse Eater grows on any friendly death (both rows). +2 ATK if upgraded.
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == "grow_on_ally_death":
			c.current_atk += 2 if bool(c.card_data.get("is_upgraded", false)) else 1
			c.update_stat_display()
	# Soul Lantern
	if _has_relic("soul_lantern") and not _soul_lantern_used_this_round:
		_soul_lantern_used_this_round = true
		_bonus_mana_next_turn += 1
	# Sigil of Hunger: arm a "next creature -1 mana" charge, once per round.
	if _has_relic("sigil_of_hunger") and not _sigil_of_hunger_fired_this_round:
		_sigil_of_hunger_fired_this_round = true
		_sigil_of_hunger_charge += int(RelicDB.get_relic("sigil_of_hunger").get("value", 1))
	# Skull Throne: at 5 deaths in one round, +2 max mana for the rest of the
	# fight. _friendly_deaths_this_round was incremented above already.
	if _has_relic("skull_throne") and _friendly_deaths_this_round == 5:
		_mana_drunkard_bonus += int(RelicDB.get_relic("skull_throne").get("value", 2))
	# Gravewarden's Pact: the first N non-token friendly deaths each fight are
	# reborn as 1/1 Imps in the lane/row they fell in (summon_token falls through
	# to the other row if the column is somehow occupied). Tokens are excluded so
	# reborn Imps don't chain the rebirth — it's "your 3 real creatures return".
	if _has_relic("gravewardens_pact") and not card.is_token:
		var gw_cap: int = int(RelicDB.get_relic("gravewardens_pact").get("value", 3))
		if _gravewardens_rebirths < gw_cap:
			_gravewardens_rebirths += 1
			var gw_row: int = card.current_row if card.current_row in [ROW_FRONT, ROW_BACK] else ROW_FRONT
			var gw_lane: int = card.current_lane if (card.current_lane >= 0 and card.current_lane < LANES_PER_ROW) else 0
			summon_token(1, 1, gw_lane, false, gw_row)
	# Soul Ledger: every Nth lifetime friendly death summons a 4/4 token in
	# any empty lane (front preferred, back fallback).
	if _has_relic("soul_ledger"):
		_soul_ledger_counter += 1
		var threshold: int = int(RelicDB.get_relic("soul_ledger").get("value", 5))
		if threshold > 0 and _soul_ledger_counter >= threshold:
			_soul_ledger_counter = 0
			var picked := _pick_empty_for_summon(false, ROW_FRONT)
			if not picked.is_empty():
				summon_token(4, 4, picked.lane, false, picked.row)


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
	# take_damage(999) routes through Card2D.try_die → Combat._on_card_destroyed
	# which already nulls the row slot and dispatches on_death / encounter
	# hooks. The previous manual `_row_array(...)[pos.lane] = null` here was
	# a no-op in the happy path but could double-fire ON_CREATURE_DEATH
	# reactive passives in edge cases (Last Stand preventing the actual death,
	# Phantom Veil restoring the card). Trust take_damage to do the work.
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == "dies_end_of_turn":
			c.take_damage(999)

	_dispatch_passive_end_of_round()

	# Round-end relic bundle: flanking_banner, imp_generator, hourglass_sigil,
	# mana_drunkard streak check, steady_banner survival ATK grant.
	_apply_round_end_relics()

	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		await _short_pause(COMBAT_PAUSE_MEDIUM)
		_start_round()


func _apply_round_end_relics() -> void:
	# Flanking Banner: 3 of 4 player front lanes full → enemies in the column
	# of the EMPTY player front lane take N damage.
	if _has_relic("flanking_banner"):
		var empty_lanes: Array[int] = []
		for i in range(LANES_PER_ROW):
			if _player_field[i] == null:
				empty_lanes.append(i)
		if empty_lanes.size() == 1:
			var dmg: int = int(RelicDB.get_relic("flanking_banner").get("value", 2))
			var lane: int = empty_lanes[0]
			for row in [ROW_FRONT, ROW_BACK]:
				var e = _row_array(true, row)[lane]
				if e != null:
					e.take_damage(dmg)
	# Imp Generator: summon a 1/1 in a random empty back-row lane.
	if _has_relic("imp_generator"):
		var empties: Array[int] = []
		for i in range(LANES_PER_ROW):
			if _player_back[i] == null:
				empties.append(i)
		if empties.size() > 0:
			summon_token(1, 1, empties[randi() % empties.size()], false, ROW_BACK)
	# Hourglass Sigil: bump pending; at threshold, drop a random rare into hand.
	if _has_relic("hourglass_sigil"):
		_hourglass_pending += 1
		var thresh: int = int(RelicDB.get_relic("hourglass_sigil").get("value", 5))
		if thresh > 0 and _hourglass_pending >= thresh:
			_hourglass_pending = 0
			_hourglass_grant_rare()
	# Mana Drunkard: streak tracker for "all mana spent". If we had ≥1 mana to
	# start with and ended at 0, increment streak; otherwise reset. At 2: +1
	# max mana for the rest of the fight.
	if _has_relic("mana_drunkard"):
		if player_max_mana >= 1 and player_mana == 0:
			_mana_drunkard_streak += 1
			if _mana_drunkard_streak == 2:
				_mana_drunkard_bonus += int(RelicDB.get_relic("mana_drunkard").get("value", 1))
		else:
			_mana_drunkard_streak = 0
	# Steady Banner: friendlies that survived the round earn +2 ATK persistent.
	if _has_relic("steady_banner") and round_number >= 2:
		var bonus: int = int(RelicDB.get_relic("steady_banner").get("value", 2))
		for c in _all_player_creatures():
			if not c.get_meta("steady_banner_locked", false):
				c.persistent_atk_buff += bonus
				c.persistent_atk_buff_rounds = 99  # effectively permanent this fight
				c.set_meta("steady_banner_locked", true)
				c.update_stat_display()


func _hourglass_grant_rare() -> void:
	# Drop a random rare card into hand (creature or spell). Synthetic uid keeps
	# it out of the run-deck upgrade lookup.
	if _hand.size() >= MAX_HAND_SIZE:
		return
	var pool: Array[String] = CardDB.get_pool_by_rarity("rare")
	if pool.is_empty():
		return
	var picked: String = pool[randi() % pool.size()]
	_player_draw_pile.push_front(_pile_entry(picked, _ephemeral_uid_counter))
	_ephemeral_uid_counter -= 1
	draw_one()


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
	card.will_die.connect(_on_card_will_die.bind(card))
	if _has_relic("philosophers_stone"):
		card.current_atk += 1
	# Shield keyword: grant shield on placement
	if card.has_keyword("shield"):
		card.state.has_shield = true
	# Mutator: stat/keyword bumps applied before the stat display catches up,
	# so the freshly-placed card shows its modified numbers from frame one.
	_mutator_apply_to_enemy(card)
	card.update_stat_display()
	KeywordEffects.dispatch_on_enter(card, lane_idx, true, self)
	if card.card_data.has("on_play"):
		_resolve_on_play_ability(card, lane_idx, true)
	_dispatch_encounter_on_enter(data, lane_idx)
	# Show the freshly-placed creature's intent immediately so it's never
	# blank between placement and the next intent-assignment pass.
	_update_intent_display(card, "ATK")


# ─────────────────────────────────────────────────────────────────────────
#  CINEMATIC COLOUR GRADE — per-act / per-encounter "mood"
# ─────────────────────────────────────────────────────────────────────────
# One screen-read grade shader sits above the board + HUD + hand and re-tones
# the whole frame; _apply_combat_mood() drives its params (plus the existing
# vignette / hearth-glow / stage-light / ember layers) from a small mood table,
# so every act, boss, and elite gets its own identity at ~zero cost. The param
# sets were tuned in the look-lab (tools/screenshot/_probe_look.gd) and picked
# from rendered comparisons against genre hits.
var _grade_mat: ShaderMaterial = null

const COMBAT_GRADE_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float u_sat = 1.0;
uniform float u_con = 1.0;
uniform float u_bright = 1.0;
uniform vec3 u_shadow = vec3(1.0);
uniform vec3 u_light = vec3(1.0);
uniform vec3 u_tint = vec3(1.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c *= u_bright;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 tone = mix(u_shadow, u_light, smoothstep(0.12, 0.78, l));
	c *= tone;
	c = (c - 0.5) * u_con + 0.5;
	float l2 = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l2), c, u_sat);
	c *= u_tint;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

# mood → { backdrop tint, vignette strength/outer, glow/stage tint, ember count/tint,
#          grade saturation/contrast/brightness, split-tone shadow/light, overall tint }
const COMBAT_MOODS := {
	"navy_gold": {"bg": Color(0.24, 0.27, 0.34), "vig": 0.70, "vig_out": Color(0.02, 0.03, 0.07, 0.90),
		"glow": Color(1, 0.85, 0.55), "stage": Color(1, 0.82, 0.5), "emberN": 48, "ember": Color(1, 0.82, 0.45),
		"sat": 1.05, "con": 1.12, "bright": 1.04, "sh": Vector3(0.72, 0.8, 1.0), "li": Vector3(1.1, 1.0, 0.78), "tint": Vector3(0.98, 0.99, 1.03)},
	"infernal": {"bg": Color(0.30, 0.16, 0.12), "vig": 0.86, "vig_out": Color(0.05, 0.01, 0.0, 0.96),
		"glow": Color(1, 0.5, 0.2), "stage": Color(1, 0.45, 0.18), "emberN": 80, "ember": Color(1, 0.5, 0.18),
		"sat": 1.10, "con": 1.20, "bright": 0.98, "sh": Vector3(1.0, 0.8, 0.7), "li": Vector3(1.1, 0.7, 0.5), "tint": Vector3(1.03, 0.95, 0.9)},
	"noir": {"bg": Color(0.22, 0.20, 0.20), "vig": 0.90, "vig_out": Color(0, 0, 0, 0.98),
		"glow": Color(1, 0.7, 0.45), "stage": Color(1, 0.6, 0.35), "emberN": 36, "ember": Color(1, 0.6, 0.3),
		"sat": 0.70, "con": 1.35, "bright": 0.95, "sh": Vector3(0.8, 0.78, 0.82), "li": Vector3(1.1, 1.0, 0.9), "tint": Vector3(1, 1, 1)},
	"frost": {"bg": Color(0.42, 0.46, 0.52), "vig": 0.55, "vig_out": Color(0.04, 0.06, 0.09, 0.80),
		"glow": Color(0.7, 0.85, 1.0), "stage": Color(0.8, 0.92, 1.0), "emberN": 40, "ember": Color(0.8, 0.92, 1.0),
		"sat": 0.95, "con": 1.05, "bright": 1.12, "sh": Vector3(0.85, 0.93, 1.05), "li": Vector3(0.98, 1.02, 1.1), "tint": Vector3(0.97, 1.0, 1.04)},
	"verdant": {"bg": Color(0.32, 0.38, 0.28), "vig": 0.60, "vig_out": Color(0.02, 0.04, 0.02, 0.85),
		"glow": Color(0.9, 1.0, 0.6), "stage": Color(0.85, 1.0, 0.6), "emberN": 44, "ember": Color(0.85, 1.0, 0.55),
		"sat": 1.08, "con": 1.05, "bright": 1.08, "sh": Vector3(0.85, 0.95, 0.8), "li": Vector3(1.0, 1.08, 0.85), "tint": Vector3(0.98, 1.04, 0.92)},
}


func _build_grade_overlay() -> void:
	var sh := Shader.new()
	sh.code = COMBAT_GRADE_CODE
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = sh
	var layer := CanvasLayer.new()
	layer.name = "GradeLayer"
	layer.layer = 40   # above hand (20) + HUD (12): grades the whole frame
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _grade_mat
	layer.add_child(rect)


func _resolve_combat_mood() -> String:
	# Boss / elite override everything; otherwise pick by biome keyword, then act.
	match RunState.current_node_type:
		"boss":
			return "infernal"
		"elite":
			return "noir"
	var eid: String = String(RunState.current_encounter_id).to_lower()
	for kw in ["frost", "ice", "winter", "snow", "glaci"]:
		if kw in eid:
			return "frost"
	if RunState.get_act() == 1:
		return "verdant"
	return "navy_gold"


func _apply_combat_mood() -> void:
	var m: Dictionary = COMBAT_MOODS.get(_resolve_combat_mood(), COMBAT_MOODS["navy_gold"])
	var bg = get_node_or_null("CombatBg")
	if bg != null:
		bg.self_modulate = m["bg"]
	var vig = get_node_or_null("Vignette")
	if vig != null and vig.material is ShaderMaterial:
		vig.material.set_shader_parameter("vignette_strength", float(m["vig"]))
		vig.material.set_shader_parameter("grad_outer", m["vig_out"])
	var hg = get_node_or_null("HearthGlow")
	if hg != null:
		hg.modulate = m["glow"]
	var sl = get_node_or_null("StageLight")
	if sl != null:
		sl.modulate = m["stage"]
	var em = get_node_or_null("AmbientEmbers")
	if em != null:
		em.amount = int(m["emberN"])
		em.modulate = m["ember"]
	if _grade_mat != null:
		_grade_mat.set_shader_parameter("u_sat", float(m["sat"]))
		_grade_mat.set_shader_parameter("u_con", float(m["con"]))
		_grade_mat.set_shader_parameter("u_bright", float(m["bright"]))
		_grade_mat.set_shader_parameter("u_shadow", m["sh"])
		_grade_mat.set_shader_parameter("u_light", m["li"])
		_grade_mat.set_shader_parameter("u_tint", m["tint"])


func _build_ambient_fx() -> void:
	# Focal vignette — darkens the painted backdrop toward the screen edges so
	# the eye is pulled to the lit board in the centre. Without it the hellscape
	# painting is evenly bright corner-to-corner and the scene reads flat. Sits
	# just above the background (tree index 1), below the embers and the board,
	# so ONLY the backdrop dims — board, cards and HUD keep full brightness.
	# Reuses the exact shader + "combat" mood the other screens get through
	# GameTheme.add_atmosphere; combat wires it directly because it builds its
	# own custom embers below instead of the generic ambient motes.
	# Push the painted backdrop back. The hellscape art is loud and shares the
	# cards' own red/orange palette, so at the .tscn default modulate it competed
	# with the foreground and nothing separated. Dim + slightly cool it so it
	# reads as deep-background atmosphere; the board substrate + stage glow carry
	# the lit foreground.
	var combat_bg := get_node_or_null("CombatBg") as TextureRect
	if combat_bg != null:
		combat_bg.self_modulate = Color(0.34, 0.30, 0.30, 1.0)
	var mood: Dictionary = GameTheme.SCREEN_MOODS.get("combat", {})
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.color = Color.WHITE
	var vmat := ShaderMaterial.new()
	vmat.shader = GameTheme._get_atmosphere_shader()
	# Combat overrides the shared "combat" mood with a deeper, more confident
	# vignette than the other screens. The map/shop/rest can stay gentle; the
	# fight needs the screen edges to fall off hard into shadow so the lit board
	# in the centre is unambiguously the focal zone. Subtle vignettes read flat —
	# this commits: brighter relative centre, near-black corners.
	vmat.set_shader_parameter("vignette_strength", 0.74)
	vmat.set_shader_parameter("grad_inner", Color(0.10, 0.06, 0.04, 0.10))
	vmat.set_shader_parameter("grad_outer", Color(0.01, 0.006, 0.005, 0.90))
	vignette.material = vmat
	add_child(vignette)
	move_child(vignette, 1)

	# Hearth glow — a soft pool of warm firelight rising from the bottom-centre of
	# the battlefield, additively blended so it reads as LIGHT, not paint. Gives
	# the "burning meadow" its heat and keeps the dark frameless board from going
	# flat-shadow now that the gilt frames are gone. Behind the board so it warms
	# the scene without washing out the recessed sockets or the cards on top.
	var glow_grad := Gradient.new()
	glow_grad.offsets = PackedFloat32Array([0.0, 1.0])
	glow_grad.colors = PackedColorArray([
		Color(1.0, 0.52, 0.20, 0.20), Color(1.0, 0.38, 0.12, 0.0)])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 256
	glow_tex.height = 256
	var glow := TextureRect.new()
	glow.name = "HearthGlow"
	glow.texture = glow_tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_left = 0.5
	glow.anchor_right = 0.5
	glow.anchor_top = 1.0
	glow.anchor_bottom = 1.0
	glow.offset_left = -560
	glow.offset_right = 560
	glow.offset_top = -560
	glow.offset_bottom = 120
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	add_child(glow)
	move_child(glow, 2)

	# Stage light — a broad, soft elliptical pool centred ON the board (not the
	# bottom edge like the hearth glow above). Additively blended warm light so
	# the 4×4 play field is the brightest zone on screen, with the deepened
	# vignette pulling everything else into shadow around it. This is the lever
	# that turns "cards floating on an evenly-lit photo" into "a lit stage": the
	# eye lands on the lit board first, then the framing darkness reads as depth.
	var stage_grad := Gradient.new()
	stage_grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	stage_grad.colors = PackedColorArray([
		Color(1.0, 0.72, 0.40, 0.26),
		Color(1.0, 0.58, 0.28, 0.13),
		Color(1.0, 0.45, 0.18, 0.0)])
	var stage_tex := GradientTexture2D.new()
	stage_tex.gradient = stage_grad
	stage_tex.fill = GradientTexture2D.FILL_RADIAL
	stage_tex.fill_from = Vector2(0.5, 0.5)
	stage_tex.fill_to = Vector2(1.0, 0.5)
	stage_tex.width = 256
	stage_tex.height = 256
	var stage := TextureRect.new()
	stage.name = "StageLight"
	stage.texture = stage_tex
	stage.stretch_mode = TextureRect.STRETCH_SCALE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred on the board area: wide ellipse covering the lanes, biased a touch
	# up from dead-centre so it lights the enemy rows too, not just the player half.
	stage.anchor_left = 0.5
	stage.anchor_right = 0.5
	stage.anchor_top = 0.5
	stage.anchor_bottom = 0.5
	stage.offset_left = -640
	stage.offset_right = 640
	stage.offset_top = -380
	stage.offset_bottom = 340
	var stage_mat := CanvasItemMaterial.new()
	stage_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	stage.material = stage_mat
	add_child(stage)
	move_child(stage, 3)

	# Drifting embers across the battlefield — warm sparks rising from the
	# burning meadow. CPUParticles2D (not GPU) so it renders identically on
	# every backend. Sits above the vignette + glow but below the board cards
	# (tree index 3) so cards always read clearly on top.
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
	move_child(embers, 3)   # above the vignette + hearth glow, still below the board


func _on_end_turn_confirmed() -> void:
	# Player accepted the end-turn warning dialog. Re-enter _on_end_turn with
	# the confirmed flag set so the warning check is bypassed.
	_end_turn_confirmed = true
	_on_end_turn()


func _has_playable_action() -> bool:
	# Returns true if the player has an affordable, meaningful card in hand.
	# Sacrifice is a free action but not worth nagging about.
	for card in _hand:
		if card == null or not is_instance_valid(card):
			continue
		if CardDB.is_curse(card.card_data.get("id", "")):
			continue
		var cost: int = int(card.card_data.get("cost", 0))
		if player_mana >= cost:
			var card_type = card.card_data.get("type", "")
			if card_type == "creature":
				var has_slot := false
				for row in [ROW_FRONT, ROW_BACK]:
					for lane in range(LANES_PER_ROW):
						if _row_array(false, row)[lane] == null:
							has_slot = true
							break
					if has_slot:
						break
				if not has_slot:
					continue
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

func _effective_cost(card: Control) -> int:
	## Side-effect-free computation of how much mana playing this card right
	## now will actually cost. Used by both the play-attempt check and the
	## hand-affordability visual so the two are guaranteed to agree.
	##
	## Modifier order matches _on_card_played:
	##   1. Base cost from card_data
	##   2. Taxed mutator (+N, min 1) — spells only
	##   3. Ember Crown — free first spell each turn (relic, spells only)
	##   4. Ironclad Veteran discount (-1 per charge, min 0)
	var cost: int = int(card.card_data.get("cost", 0))
	if card.is_spell() and _mutator_spell_cost_increase > 0:
		cost = maxi(1, cost + _mutator_spell_cost_increase)
	if card.is_spell() and _has_relic("ember_crown") and not _first_spell_this_turn:
		cost = 0
	if _card_cost_discount > 0 and cost > 0:
		cost = maxi(0, cost - 1)
	# Spell Tome — spell-heavy deck discounts spells by 1.
	if card.is_spell() and _spell_tome_active and cost > 0:
		cost = maxi(0, cost - 1)
	# Mana Tide — a banked-mana charge discounts the next creature by 1.
	if card.is_creature() and _mana_tide_creature_discount > 0 and cost > 0:
		cost = maxi(0, cost - 1)
	# Sigil of Hunger — discount charge from a friendly death this round.
	if card.is_creature() and _sigil_of_hunger_charge > 0 and cost > 0:
		cost = maxi(0, cost - 1)
	# Mummified Hand — per-card meta tag set when a spell cast picked this one.
	if card.get_meta("mummified_zero", false):
		cost = 0
	# Pact of Embers — turn-start tag for the highest-cost card in hand.
	if card.get_meta("pact_of_embers_zero", false):
		cost = 0
	# Trickster's Glove — hand size 4+ discounts every card by 1.
	if _has_relic("tricksters_glove") and _hand.size() >= 4 and cost > 0:
		cost = maxi(0, cost - 1)
	# Last Breath — creatures with 1 base HP cost 1 less.
	if _has_relic("last_breath") and card.is_creature() \
			and int(card.card_data.get("hp", 99)) == 1 and cost > 0:
		cost = maxi(0, cost - int(RelicDB.get_relic("last_breath").get("value", 1)))
	return cost


func _on_card_played(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
		_layout_hand()  # bounce the dragged card back into the fan
		return
	if _targeting_spell != null:
		_cancel_targeting()

	# Velvet Choker: max 5 cards per turn
	if _has_relic("velvet_choker") and _cards_played_this_turn >= 5:
		_show_info("Velvet Choker: can't play more than 5 cards!")
		_layout_hand()  # bounce the dragged card back into the fan
		return

	# Effective cost factors in mutators (Taxed +N), Ember Crown (free first
	# spell), and Ironclad Veteran's per-charge discount. _effective_cost is
	# the single source of truth — _refresh_hand_affordability calls the same
	# helper so the dimmed/affordable visual ALWAYS matches the actual play
	# check. Previously the affordability check read raw card_data.cost and
	# the play check applied the modifiers — so e.g. with Taxed +1 active,
	# a 1-cost Fireball looked "affordable" at 1 mana but failed to play.
	var cost = _effective_cost(card)
	if player_mana < cost:
		_show_info("Not enough mana!")
		_layout_hand()  # bounce the dragged card back into the fan
		return
	# Consume the Ironclad Veteran discount charge ONLY if it actually applied
	# (i.e. cost was still > 0 after mutator+Ember adjustments). _effective_cost
	# itself is side-effect free so this consumption happens here, where we
	# know the play is going through.
	if _card_cost_discount > 0:
		var pre_discount: int = int(card.card_data.get("cost", 0))
		if card.is_spell() and _mutator_spell_cost_increase > 0:
			pre_discount = maxi(1, pre_discount + _mutator_spell_cost_increase)
		if card.is_spell() and _has_relic("ember_crown") and not _first_spell_this_turn:
			pre_discount = 0
		if pre_discount > 0:
			_card_cost_discount -= 1
	# Mana Tide — playing a creature consumes one banked-mana discount charge.
	if card.is_creature() and _mana_tide_creature_discount > 0:
		_mana_tide_creature_discount -= 1
	# Sigil of Hunger — same model as mana_tide; a creature consumes the charge.
	if card.is_creature() and _sigil_of_hunger_charge > 0:
		_sigil_of_hunger_charge -= 1
	# Mummified Hand / Pact of Embers meta tags are one-shot. Clear them when
	# the tagged card is actually played so the discount doesn't carry over to
	# whatever creature/spell happens to draw the meta next turn.
	if card.get_meta("mummified_zero", false):
		card.set_meta("mummified_zero", false)
	if card.get_meta("pact_of_embers_zero", false):
		card.set_meta("pact_of_embers_zero", false)

	if card.is_spell():
		_play_spell(card, cost)
	else:
		_play_creature(card, cost)


func _play_creature(card: Control, cost: int) -> void:
	if card.has_keyword("sacrifice"):
		_show_info("Click a creature to sacrifice for this card.")
		_layout_hand()  # bounce the dragged card back into the fan
		return

	# 4x4: derive both lane and row from the drop position. Use the card's CENTER
	# (not its top-left origin) so the slot we pick matches the one the drag
	# highlight lit up — `dragging` emits `global_position + size*0.5`, and the
	# drag pivot is centred, so size*0.5 (NOT size*scale*0.5) is the true on-screen
	# centre = the cursor. Reading the raw origin biased every drop one row up.
	# Drops on occupied slots are rejected (no replace) — creatures stay where
	# they were placed unless an explicit effect moves them.
	var drop = _nearest_player_slot(card.global_position + card.size * 0.5)
	var lane_idx: int = drop.lane
	var row: int = drop.row
	var field = _row_array(false, row)
	if field[lane_idx] != null:
		_show_info("That slot is occupied.")
		_layout_hand()
		return

	# Capture hand position BEFORE remove_child so the landing arc knows where
	# this card flew in from. Once removed, global_position no longer reflects
	# the on-screen hand slot.
	var play_start_global: Vector2 = card.global_position
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
		if "last_stand" not in card.card_data.keywords:
			card.card_data.keywords.append("last_stand")
			if card.has_method("_spawn_keyword_chip"):
				card._spawn_keyword_chip("LAST STAND", Color(1.0, 0.85, 0.45))
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
	# Iron Legion: creature-heavy deck (≥60%) grants +1 HP to friendlies on entry.
	if _has_relic("iron_legion") and card.is_creature() and _deck_creature_ratio() >= 0.6:
		card.current_hp += 1
		card.card_data.hp += 1
	# Totem Pole: grant the run-picked keyword to every friendly on placement.
	if _has_relic("totem_pole") and card.is_creature() and RunState.totem_pole_keyword != "":
		var kw: String = RunState.totem_pole_keyword
		if not card.card_data.keywords.has(kw):
			card.card_data.keywords.append(kw)
			card.update_stat_display()
	# Bone Hourglass: apply the run-picked ramp on placement.
	if _has_relic("bone_hourglass") and card.is_creature():
		match RunState.bone_hourglass_choice:
			"front_atk":
				if row == ROW_FRONT:
					card.current_atk += 1
			"back_hp":
				if row == ROW_BACK:
					card.current_hp += 1
					card.card_data.hp += 1
		card.update_stat_display()

	# Hourglass of Ruin: your Doom creatures detonate sooner. Seed the per-creature
	# countdown low on placement (floored at 1 so it still gets one live round on
	# the board to threaten — "1 round sooner", not "instantly").
	if _has_relic("hourglass_of_ruin") and card.is_creature() and card.has_keyword("doom"):
		if card.has_method("_ensure_doom_init"):
			card._ensure_doom_init()
		var ruin: int = int(RelicDB.get_relic("hourglass_of_ruin").get("value", 1))
		card.doom_counter = maxi(1, card.doom_counter - ruin)
		if card.has_method("update_doom_display"):
			card.update_doom_display()

	# Shield keyword: grant shield on placement
	if card.has_keyword("shield"):
		card.state.has_shield = true
	# Mutator: extra keyword grant ("Swift Winds") or HP weaken ("Cursed") on
	# the freshly-played creature. Mirrors the enemy hook in _place_enemy_card.
	_mutator_apply_to_player_creature(card)
	_first_creature_played = true
	# Butcher's Cleaver — consume armed state, grant +2 ATK for 2 rounds.
	if _butchers_cleaver_armed and _has_relic("butchers_cleaver"):
		_butchers_cleaver_armed = false
		var bc_value: int = RelicDB.get_relic("butchers_cleaver").get("value", 2)
		card.persistent_atk_buff += bc_value
		card.persistent_atk_buff_rounds = 2
		card.update_stat_display()
	# with_arc=false: the player has already dragged the card to this slot,
	# so the arc animation would loop back over their own gesture — at the
	# slot itself it reads as a pointless circle. The scale-punch settle in
	# _play_landing_pop's no-arc path is the right amount of feedback.
	_place_card_in_slot(card, lane_idx, row, play_start_global, false)

	# Mimic Ring relic: copy one combat keyword from an adjacent friendly. We
	# look at the same-row neighbors (±1 lane) the card just landed next to,
	# collect their combat keywords, and append the first one the new card
	# doesn't already have. Skipped if no adjacent ally or no copyable keyword
	# is available.
	if _has_relic("mimic_ring") and card.is_creature():
		var neighbors: Array[Control] = []
		var same_row = _row_array(false, row)
		for adj in [lane_idx - 1, lane_idx + 1]:
			if adj >= 0 and adj < LANES_PER_ROW and same_row[adj] != null and same_row[adj] != card:
				neighbors.append(same_row[adj])
		var picked_kw := ""
		for n in neighbors:
			for kw in n.card_data.get("keywords", []):
				if kw in KeywordEffects.COMBAT_KEYWORDS \
						and not card.card_data.keywords.has(kw):
					picked_kw = kw
					break
			if picked_kw != "":
				break
		if picked_kw != "":
			card.card_data.keywords.append(picked_kw)
			if card.has_method("_spawn_keyword_chip"):
				card._spawn_keyword_chip("MIMIC", Color(0.65, 0.85, 1.0))
			card.update_stat_display()

	# Encounter passive: collector heals on creature played
	if _encounter_passive == "collector_heal":
		enemy_hp = mini(enemy_hp + 1, enemy_max_hp)
	elif _encounter_passive == "collector_phase2":
		enemy_hp = mini(enemy_hp + 2, enemy_max_hp)
		_buff_random_enemy_atk(1)

	# Linked Banner: HP-half snapshot scan. Re-check every friendly so a
	# brand-new adjacency that pushed an ally from 1→2 picks up the +1 HP.
	_apply_linked_banner_hp()

	# On-enter effects
	KeywordEffects.dispatch_on_enter(card, lane_idx, false, self)
	# On-play ability (formerly floop): fires immediately when the creature
	# lands. Fire-and-forget so any modal pickers match the on-enter convention.
	if card.card_data.has("on_play"):
		_resolve_on_play_ability(card, lane_idx, false)

	# Blueprint: replay the previously-played friendly creature's on-enter on
	# this card, then cache this card's own on-enter for the NEXT play. Chains
	# through every friendly creature played this combat. Triggered after the
	# card's own on-enter so the "echo" reads as a separate beat.
	if _has_relic("blueprint") and card.is_creature():
		if not _blueprint_last_on_enter.is_empty():
			KeywordEffects._run_on_enter(_blueprint_last_on_enter, card, lane_idx, false, self)
		if card.card_data.has("on_enter"):
			_blueprint_last_on_enter = card.card_data["on_enter"].duplicate(true)

	# Reaper's Scythe: an on-play ability stolen from a sacrificed creature is
	# grafted onto the next-played creature and fires immediately.
	if _has_relic("reapers_scythe") and card.is_creature() \
			and not _reapers_scythe_pending_floop.is_empty():
		card.card_data["on_play"] = _reapers_scythe_pending_floop.duplicate(true)
		_resolve_on_play_ability(card, lane_idx, false)
		card.update_stat_display()
		_reapers_scythe_pending_floop = {}

	# Ironclad Veteran
	if card.card_data.get("on_enter", {}).get("type", "") == "atk_per_cards_played":
		card.current_atk += _cards_played_this_turn - 1
		card.update_stat_display()

	# Hexblade — enters with ATK bonus for spells already cast this fight.
	if card.card_data.get("passive", "") == "atk_per_spell":
		card.current_atk += _spells_cast_this_fight
		card.update_stat_display()

	# Warchief — ATK = number of friendly creatures (including self, just placed).
	if card.card_data.get("passive", "") == "warchief_aura":
		card.current_atk = _all_player_creatures().size()
		card.update_stat_display()

	# Tallow Doll — gains +1/+1 for each prior Tallow Doll this fight, then
	# increments the counter so the next one is bigger. Mirrors Hearthstone's
	# Astral Automaton (per-fight here instead of per-game so it doesn't carry
	# stats into the next encounter).
	if card.card_data.get("passive", "") == "tallow_stacking":
		var prior: int = _tallow_dolls_played
		if prior > 0:
			card.current_atk += prior
			card.card_data.hp += prior
			card.current_hp += prior
			card.update_stat_display()
		_tallow_dolls_played += 1

	# Standard Bearer — first 1-cost creature each turn summons a 1/1 token.
	# Skipped if Standard Bearer itself is the card just played (it's 2-cost
	# so the cost check filters it out, but be defensive). Skipped for tokens
	# (they're cost 0 but is_token flagged).
	if int(card.card_data.get("cost", 0)) == 1 \
			and not card.is_token \
			and not _standard_bearer_fired_this_turn \
			and _has_passive_on_field("standard_bearer_summon"):
		var picked := _pick_empty_for_summon(false, ROW_FRONT)
		if not picked.is_empty():
			summon_token(1, 1, picked.lane, false, picked.row)
			_standard_bearer_fired_this_turn = true

	# Summon keyword
	if card.has_keyword("summon"):
		KeywordEffects._do_summon(lane_idx, false, self)
		# Reactive passive: ON_PLAYER_SUMMON
		_dispatch_reactive("ON_PLAYER_SUMMON", card, lane_idx)

	# Raider's Oath (class-restricted): playing a Swift creature refunds 1 mana
	# this turn. Stacks with itself — multiple Swift plays each refund.
	if _has_relic("raiders_oath") and card.is_creature() and card.has_keyword("swift"):
		player_mana += int(RelicDB.get_relic("raiders_oath").get("value", 1))
	# Bridge Watcher: center-lane (1 & 2) friendlies enter with +1 HP. Thorns 2
	# half is delivered at combat resolution via _apply_thorns.
	if _has_relic("bridge_watcher") and card.is_creature() and lane_idx in [1, 2]:
		card.card_data["hp"] = int(card.card_data.get("hp", card.current_hp)) + 1
		card.current_hp += 1
		card.update_stat_display()
	# Spotter's Glass: if the column (BOTH rows in that lane) had no other
	# friendly before this placement, the new creature gets +1 ATK permanently.
	if _has_relic("spotters_glass") and card.is_creature():
		var col_empty := true
		var other_row: int = ROW_BACK if row == ROW_FRONT else ROW_FRONT
		if _row_array(false, other_row)[lane_idx] != null:
			col_empty = false
		if col_empty:
			card.current_atk += int(RelicDB.get_relic("spotters_glass").get("value", 1))
			card.update_stat_display()

	# Frost Spike: tag the first friendly creature of the fight so its first
	# attack applies Wither 1 to the target. Meta is read inside the combat
	# resolution loop (search for "frost_spike_active").
	if _has_relic("frost_spike") and card.is_creature() and not _frost_spike_consumed:
		_frost_spike_consumed = true
		card.set_meta("frost_spike_active", true)
		if card.has_method("_spawn_keyword_chip"):
			card._spawn_keyword_chip("FROST", Color(0.65, 0.85, 1.0))

	# Brainstorm: each round, the first creature played copies the keywords of
	# the FIRST creature played this combat. Captures the seed creature on its
	# play; later rounds graft those keywords onto the round's first creature.
	if _has_relic("brainstorm") and card.is_creature():
		if _brainstorm_first_keywords.is_empty():
			_brainstorm_first_keywords = card.card_data.get("keywords", []).duplicate()
		elif not _brainstorm_fired_this_round:
			for kw in _brainstorm_first_keywords:
				if kw in KeywordEffects.COMBAT_KEYWORDS \
						and not card.card_data.keywords.has(kw):
					card.card_data.keywords.append(kw)
			_brainstorm_fired_this_round = true
			card.update_stat_display()

	# Wormwood / Spike Driver / Stalwart's Anvil react inside _on_friendly_damaged.
	# Pen Nib counts every card played (creature OR spell).
	if _has_relic("pen_nib"):
		_pen_nib_counter += 1
		var threshold: int = int(RelicDB.get_relic("pen_nib").get("value", 10))
		if threshold > 0 and _pen_nib_counter >= threshold:
			_pen_nib_counter = 0
			_pen_nib_trigger()

	card.update_stat_display()
	_update_hud()


func _play_spell(card: Control, cost: int) -> void:
	var targeting = card.card_data.get("targeting", "none")
	# Capture hand position so the cast-ghost knows where the spell card flew
	# from. For targeted spells the ghost lingers until the player clicks; for
	# non-targeted spells it dissolves immediately above the play line.
	var spell_start_global: Vector2 = card.global_position
	if targeting != "none":
		player_mana -= cost
		_pulse_mana_label(cost)
		_first_spell_this_turn = true
		_cards_played_this_turn += 1
		_hand.erase(card)
		_hand_container.remove_child(card)
		_spawn_spell_cast_ghost(card.card_data, spell_start_global, null)
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
	_spawn_spell_cast_ghost(card.card_data, spell_start_global, null)
	await _resolve_spell(card.card_data, null, -1)
	_after_spell(card)


func _resolve_spell(data: Dictionary, target: Control, target_lane: int) -> void:
	var spell = data.get("spell", {})
	var spell_type = spell.get("type", "")
	var value = spell.get("value", 0)

	# Worn Spellbook: "Your damage spells deal +1 damage." Covers both creature-
	# targeting (`damage`) and face-targeting (`damage_face`, `damage_all_enemies`,
	# `damage_all`) so a Pyromancer-style Fireball deck actually benefits from
	# its signature relic. Previously only `damage` was bumped, which silently
	# locked Fireball / Flame Bolt out of the buff.
	if _has_relic("worn_spellbook") \
			and spell_type in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		value += 1
	# Reagent Pouch: first spell each combat is Sharpened (+spell.value bonus).
	if _has_relic("reagent_pouch") and not _reagent_pouch_consumed \
			and spell_type in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		_reagent_pouch_consumed = true
		value += int(RelicDB.get_relic("reagent_pouch").get("value", 2))
	# Mana Pearl: 0-cost spells deal +3 damage. _doubling_active_spell read
	# prevents the relic counting the Pyromancer Scar re-cast against itself
	# (the doubled cast inherits cost=0 in the call path).
	var spell_cost: int = int(data.get("cost", 0))
	if _has_relic("mana_pearl") and spell_cost == 0 \
			and spell_type in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		value += int(RelicDB.get_relic("mana_pearl").get("value", 3))
	# Glowing Hand: damage spells deal +1 per spell already cast this combat,
	# capped at +5.
	if _has_relic("glowing_hand") \
			and spell_type in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		var cap: int = int(RelicDB.get_relic("glowing_hand").get("value", 5))
		value += mini(cap, _glowing_hand_spells_cast)

	# Fire a colored burst at the spell's resolution point so every spell has
	# visible feedback (the underlying effect like take_damage shakes the target
	# but doesn't read as "you cast something"). Passes the full card_data so
	# Tier-2 family dispatch can read the spell's id; falls back to type-based
	# color for any spell missing from SPELL_FAMILIES.
	_play_spell_cast_vfx(data, target)

	# JUICE — board-wide and heavy spells earn an extra jolt on cast + a brief
	# hit-stop AFTER they land, so a screen-clearing Earthquake / Apocalypse hits
	# with the weight it deserves rather than every creature's HP just dropping at
	# once. Single-target chip spells skip this so casting stays snappy. The jolt
	# fires now (with the cast VFX); the hit-stop is applied just below, after the
	# match block resolves the damage. Awaitable: all callers of _resolve_spell
	# already await it, so this never desyncs the turn.
	var _aoe_spell: bool = spell_type in ["damage_all_enemies", "damage_all", "buff_all_atk"]
	var _big_spell: bool = spell_type in ["damage", "damage_face"] and int(value) >= HEAVY_HIT_DAMAGE
	if _aoe_spell or _big_spell:
		screen_shake(10.0 if _aoe_spell else 7.0)

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
			await _resolve_custom_spell(spell.get("id", ""), target, target_lane, data)

	# JUICE (cont.) — the post-impact hit-stop for AoE / heavy spells. Lands after
	# the damage above so the player sees the board get hit, THEN feels the beat.
	if _aoe_spell or _big_spell:
		await _short_pause(HITSTOP_BEAT)

	_last_spell_played_this_turn = data
	# Echo replays against the same target. Skip the bookkeeping for Echo
	# itself so an "Echo → Echo" chain doesn't overwrite the real last target.
	if data.get("spell", {}).get("id", "") != "echo_spell":
		_last_spell_target_ref = weakref(target) if target != null else null
		_last_spell_target_lane = target_lane


func _resolve_custom_spell(spell_id: String, target: Control, _target_lane: int,
		data: Dictionary = {}) -> void:
	# Worn Spellbook ("Your damage spells deal +1 damage") applies to every
	# numeric-damage custom spell, not just the two that originally opted in.
	# Excluded by design: hex (debuff with incidental dmg), holy_smite (execute
	# scaled by missing HP), fuel_the_pyre / cataclysm (scaled by creature
	# ATK), apocalypse (999 overkill), and any spell that damages the player.
	var spell_dmg_bonus: int = 1 if _has_relic("worn_spellbook") else 0
	# Per-card "+" upgrade bonuses. The Rest screen's plus upgrade merges
	# these into card_data via RunState._apply_plus_upgrade. Resolvers that
	# care read whichever fields are relevant; the rest no-op cleanly.
	var plus_dmg: int = int(data.get("dmg_bonus", 0))
	var plus_slay_draw: int = int(data.get("slay_draw", 0))
	var plus_slay_gold: int = int(data.get("slay_gold", 0))
	var plus_slay_mana: int = int(data.get("slay_mana", 0))
	var plus_draw: int = int(data.get("extra_draw", 0))
	var plus_mana: int = int(data.get("extra_mana", 0))
	var plus_ricochet: int = int(data.get("ricochet_hits", 0))
	var is_plus: bool = bool(data.get("is_upgraded", false))
	match spell_id:
		"blood_tithe":
			var bonus = 1 if _has_relic("pyromaniac_ring") else 0
			damage_enemy_hero(3 + bonus + spell_dmg_bonus + plus_dmg)
			damage_player_hero(2)
		"reckless_charge":
			if target != null:
				target.take_damage(3 + spell_dmg_bonus + plus_dmg)
			for _i in 1 + plus_draw:
				draw_one()
			damage_player_hero(1)
		"shove":
			if target != null:
				target.take_damage(2 + spell_dmg_bonus + plus_dmg)
				# Plus version drops ATK by 2 instead of 1. Floored at 0 so the
				# upgrade never produces a negative current_atk.
				var atk_debuff: int = 2 if is_plus else 1
				if target.current_atk > 0:
					target.current_atk = maxi(0, target.current_atk - atk_debuff)
					target.update_stat_display()
		"second_wind":
			if target != null:
				target.current_hp = target.card_data.hp
				target.current_atk += 1
				target.update_stat_display()
		"lightning":
			if target != null:
				target.take_damage(2 + spell_dmg_bonus)
			damage_enemy_hero(1 + spell_dmg_bonus)
		"offering":
			if target != null:
				_trigger_player_sacrifice(target)
				target.take_damage(999)
				player_mana += 2 + plus_mana
		"unholy_bargain":
			for i in 3 + plus_draw:
				draw_one()
			damage_player_hero(3)
		"dark_pact":
			var atk_gain: int = 1 + plus_dmg
			for c in _all_player_creatures():
				c.current_atk += atk_gain
				c.update_stat_display()
			for c in _all_enemy_creatures():
				c.current_atk += atk_gain
				c.update_stat_display()
			damage_player_hero(2)
		"kings_command":
			var atk_gain2: int = 3 + plus_dmg
			var hp_gain2: int = 1 + plus_dmg
			for c in _all_player_creatures():
				c.temp_atk_buff += atk_gain2
				c.current_hp += hp_gain2
				c.card_data.hp += hp_gain2
				c.update_stat_display()
		"mass_grave":
			var pile_size = _player_discard_pile.size()
			var dmg = maxi(1, pile_size) + spell_dmg_bonus + plus_dmg
			for c in _all_enemy_creatures():
				c.take_damage(dmg)
		"plague_bell":
			# HS Defile port — deal 1 to every creature, repeat if anything died.
			# Iteration cap is a safety net against pathological infinite chains
			# (e.g. Reborn-style revives at 1 HP, which would loop forever).
			var dmg = 1 + spell_dmg_bonus + plus_dmg
			for _i in 12:
				var any_died := false
				for c in _all_creatures_both_sides():
					var hp_before: int = c.current_hp
					c.take_damage(dmg)
					if hp_before > 0 and c.current_hp <= 0:
						any_died = true
				_cleanup_dead()
				if not any_died:
					break
		"grave_robbery":
			if _last_dead_creature_id != "":
				# Pile entries are "card_id#uid" — pushing a bare id would
				# read back as uid=-1 and skip the upgrade lookup, so an
				# upgraded creature came back un-upgraded.
				_player_draw_pile.push_front(
					_pile_entry(_last_dead_creature_id, _last_dead_creature_uid))
				draw_one()
		"cataclysm":
			# Damage = highest friendly ATK. Falls back to a base 3 if you have
			# no creatures, so the spell does *something* when cast empty-board
			# (otherwise it silently fizzles, which feels broken).
			var max_atk := 0
			for c in _all_player_creatures():
				max_atk = maxi(max_atk, c.effective_atk())
			if max_atk <= 0:
				max_atk = 3
			for c in _all_enemy_creatures():
				c.take_damage(max_atk + plus_dmg)
		"soul_swap":
			if target != null:
				# Read effective ATK so temp/persistent buffs participate
				# in the swap. Strip the buff layers when writing back to
				# current_atk so the buffs aren't double-counted post-swap.
				var eff_atk: int = target.effective_atk()
				var new_atk: int = target.current_hp
				var new_hp: int = eff_atk
				target.current_atk = maxi(0, new_atk - target.temp_atk_buff - target.persistent_atk_buff)
				target.current_hp = new_hp
				target.card_data.hp = new_hp
				target.update_stat_display()
		"apocalypse":
			# Hit every creature for 999. Last Stand survivors stay alive (and
			# in their lane) — that's the point of the keyword. Face damage is
			# the count of creatures that actually died.
			var kills := 0
			for c in _all_creatures_both_sides():
				c.take_damage(999)
				if c.current_hp <= 0:
					kills += 1
			damage_player_hero(kills)
		"grave_pact":
			_grave_pact_active = true
		"fuel_the_pyre":
			if target != null:
				var atk = target.effective_atk()
				_trigger_player_sacrifice(target)
				target.take_damage(999)
				var enemies = _all_enemy_creatures()
				if enemies.size() > 0:
					enemies[randi() % enemies.size()].take_damage(atk + plus_dmg)
				else:
					damage_enemy_hero(atk + plus_dmg)
		"pillage":
			if target != null:
				target.take_damage(3 + spell_dmg_bonus + plus_dmg)
				if target.current_hp <= 0:
					RunState.gain_gold(10 + plus_slay_gold)
		"war_chant":
			# Rally: pitch cards to muster one Soldier each (3/2 if upgraded). Bodies
			# on the board beat card draw under the persistent-hand economy.
			var max_disc: int = mini(3, _hand.size())
			var picked: Array = []
			if max_disc > 0:
				picked = await _show_discard_picker(max_disc,
					"War Chant — discard up to %d to muster that many Soldiers" % max_disc, true)
					# (one Soldier summoned per pitched card, below)
				for c in picked:
					_hand.erase(c)
					_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
					if c.get_parent() != null:
						c.get_parent().remove_child(c)
					c.queue_free()
			for i in picked.size() + 1 + plus_draw:
				draw_one()
		"battle_hymn":
			for c in _all_player_creatures():
				c.temp_atk_buff += 1
				c.current_hp += 1
				c.card_data.hp += 1
				c.update_stat_display()
		"slash":
			# Cross-Blitz "Slay" — bonus payoff for kills, rewards finishers.
			if target != null:
				target.take_damage(3 + spell_dmg_bonus + plus_dmg)
				if target.current_hp <= 0:
					for _i in 1 + plus_slay_draw:
						draw_one()
		"shield_wall":
			if target != null:
				var bandage: int = 4 + plus_dmg
				target.current_hp += bandage
				target.card_data.hp += bandage
				target.set_meta("shield_wall_thorns", true)
				target.update_stat_display()
		"war_cry":
			# Rallying yell — temp ATK + Swift means your front line trades
			# UP this turn instead of just hitting a bit harder.
			var atk_gain3: int = 1 + plus_dmg
			for c in _all_player_creatures():
				c.temp_atk_buff += atk_gain3
				c.set_meta("war_cry_swift", true)
				c.update_stat_display()
		"patch_up":
			# Overheal cantrip — bandage drawn from a healthy ally is free draw.
			if target != null:
				var was_full: bool = target.current_hp >= target.card_data.hp
				target.current_hp = mini(target.current_hp + 4 + plus_dmg, target.card_data.hp)
				target.update_stat_display()
				if was_full:
					for _i in 1 + plus_draw:
						draw_one()
		"flame_bolt":
			# Combo — base 3, ramped to 5 if you've cast any spell this turn.
			# _cards_played_this_turn counts both creatures and spells, but the
			# combo specifically wants a SPELL precedent, so we check the
			# spell counter (_first_spell_this_turn flips on first spell cast).
			var dmg: int = (5 if _spells_cast_this_turn >= 1 else 3) + spell_dmg_bonus + plus_dmg
			damage_enemy_hero(dmg)
		"quick_shot":
			if target != null:
				target.take_damage(1 + spell_dmg_bonus + plus_dmg)
			else:
				damage_enemy_hero(1 + spell_dmg_bonus + plus_dmg)
			for _i in 1 + plus_draw:
				draw_one()
		"smite_spell":
			if target != null:
				target.take_damage(6 + spell_dmg_bonus + plus_dmg)
				if target.current_hp <= 0:
					player_mana += 1 + plus_slay_mana
					for _i in 1 + plus_slay_draw:
						draw_one()
		"ambush":
			for c in _all_enemy_creatures():
				c.take_damage(1 + spell_dmg_bonus + plus_dmg)
			var swift_gain: int = 1 + plus_dmg
			for c in _all_player_creatures():
				if c.has_keyword("swift"):
					c.temp_atk_buff += swift_gain
					c.update_stat_display()
		"inspire":
			var inspire_atk: int = 2 + plus_dmg
			for c in _all_player_creatures():
				c.temp_atk_buff += inspire_atk
				c.set_meta("inspire_piercing", true)
				c.update_stat_display()
		"lost_tome":
			# Discover a random common spell.
			await _show_discover("spell", "common")
		"war_council":
			# Discover any card.
			await _show_discover("any", "")
		"scrap":
			if _hand.size() > 0:
				var picked: Array = await _show_discard_picker(1, "Scrap — pick a card to discard")
				for c in picked:
					_hand.erase(c)
					_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
					if c.get_parent() != null:
						c.get_parent().remove_child(c)
					c.queue_free()
				if picked.size() > 0:
					player_mana += 1 + plus_mana
		"gambit":
			var max_discard: int = mini(3, _hand.size())
			if max_discard > 0:
				var picked: Array = await _show_discard_picker(max_discard,
					"Gambit — discard up to %d, draw that many" % max_discard, true)
				for c in picked:
					_hand.erase(c)
					_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
					if c.get_parent() != null:
						c.get_parent().remove_child(c)
					c.queue_free()
				for i in picked.size():
					draw_one()
		"barricade":
			if target != null:
				target.current_hp += 4
				target.card_data.hp += 4
				if "armored" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("armored")
				target.update_stat_display()
		"inferno":
			for c in _all_enemy_creatures():
				c.take_damage(4 + spell_dmg_bonus + plus_dmg)
			damage_enemy_hero(4 + spell_dmg_bonus + plus_dmg)
		"immolate":
			# Pyre single-target burn (card "Immolate"). Deal 4 (+bonuses) to the
			# chosen creature; if it dies, the fire jumps to the enemy face for the
			# same amount — a finisher that rewards killing blows. Fire-VFX on the
			# target so the burn reads, plus a face burst when the bonus lands.
			if target != null:
				var imm_dmg: int = 4 + spell_dmg_bonus + plus_dmg
				_vfx_fire(target.get_global_rect().get_center())
				target.take_damage(imm_dmg)
				if target.current_hp <= 0:
					if _enemy_hp_label != null:
						_vfx_fire(_enemy_hp_label.get_global_rect().get_center())
					damage_enemy_hero(imm_dmg)
		"wildfire":
			# Pyre board-clear (card "Wildfire", Exhaust). Deal 2 (+bonuses) to every
			# enemy creature, then 1 face damage for each creature that was actually
			# present to take the hit — a scaling finish that grows with their board.
			# Snapshot the list first so the per-creature face tally is stable even
			# as bodies die and _cleanup_dead prunes them.
			var wf_targets: Array = _all_enemy_creatures()
			var wf_hit: int = wf_targets.size()
			var wf_dmg: int = 2 + spell_dmg_bonus + plus_dmg
			for c in wf_targets:
				if c != null and is_instance_valid(c):
					_vfx_fire(c.get_global_rect().get_center())
					c.take_damage(wf_dmg)
			_cleanup_dead()
			if wf_hit > 0:
				if _enemy_hp_label != null:
					_vfx_fire(_enemy_hp_label.get_global_rect().get_center())
				damage_enemy_hero(wf_hit)
		"censer_light":
			# Pyre sustain anointing (card "Censer Light"). A friendly creature gains
			# Lifelink (added to its runtime keywords so the chip shows AND
			# _apply_combat_strike_riders heals off it) and +1 (+upgrade) ATK for the
			# rest of the fight via persistent_atk_buff. Reuses the same runtime
			# keyword-grant + chip pattern as Adaptable (_show_keyword_choice).
			if target != null:
				if "lifelink" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("lifelink")
				# Make sure the lifelink heal amount is at least 1 so the keyword
				# isn't a no-op on a creature that never had a lifelink value.
				if int(target.card_data.get("lifelink", 0)) < 1:
					target.card_data["lifelink"] = 1
				var cl_atk: int = 1 + plus_dmg
				target.persistent_atk_buff += cl_atk
				target.persistent_atk_buff_rounds = 99  # rest of this fight
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LIFELINK", Color(0.95, 0.35, 0.45))
				_vfx_blessing(target.get_global_rect().get_center())
				target.update_stat_display()
		"overwhelming_force":
			var of_atk: int = 3 + plus_dmg
			for c in _all_player_creatures():
				c.current_atk += of_atk
				c.update_stat_display()
		"lay_on_hands":
			if target != null:
				target.card_data.hp += 2 + plus_dmg
				target.current_hp = target.card_data.hp
				target.update_stat_display()
		"mending_light":
			player_hp = mini(player_hp + 5, player_max_hp)
			for c in _all_player_creatures():
				c.current_hp = mini(c.current_hp + 2, c.card_data.hp)
				c.update_stat_display()
		"banish":
			# Exile target — removes from play WITHOUT firing on_death triggers
			# or rescue handlers (Phantom Veil, Reborn). The whole point of
			# banishing an enemy is to avoid its death-rattle, so we skip the
			# normal death pipeline. We still restore the slot label so the
			# board doesn't show a stale name where the card used to sit.
			if target != null:
				var pos = _find_creature_position(target)
				if not pos.is_empty():
					_row_array(pos.is_enemy, pos.row)[pos.lane] = null
					var slots = _slot_array(pos.is_enemy, pos.row)
					if pos.lane < slots.size():
						_restore_slot_label(slots[pos.lane], pos.lane)
				target.queue_free()
		"time_snare":
			for c in _all_enemy_creatures():
				c.state.stunned = true
		"frost_bolt":
			if target != null:
				target.state.is_frozen = true
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
				if plus_dmg > 0:
					target.take_damage(plus_dmg)
		"holy_smite":
			if target != null:
				var missing = target.card_data.hp - target.current_hp
				target.take_damage(maxi(0, missing))
		"adrenaline":
			player_mana += 1 + plus_mana
			draw_one()
		"bloodletting":
			damage_player_hero(1)
			player_mana += 2 + plus_mana
		"turbo":
			player_mana += 2 + plus_mana
			_player_discard_pile.append(CardDB.random_curse_id())
		"recycle":
			# Recycle: player picks a card in hand to exhaust; gain mana equal
			# to its cost (+1 if upgraded). Useful for cashing in dead-weight
			# (Curses, redundant copies) the previous auto-pick-highest behavior
			# never let you do.
			if _hand.size() > 0:
				var picked: Control = await _show_recycle_modal()
				if picked != null and is_instance_valid(picked):
					var cost: int = int(picked.card_data.get("cost", 0))
					_hand.erase(picked)
					if picked.get_parent() != null:
						picked.get_parent().remove_child(picked)
					_exhaust_pile.append(picked.card_id)
					picked.queue_free()
					player_mana += cost + plus_mana
					_update_hud()
		"charge_spell":
			# Charge!: target friendly attacks ALL opposing lanes this turn
			# (Hydra-style multi-strike). Meta cleared in end-of-round cleanup.
			if target != null:
				target.set_meta("charges_this_turn", true)
		"echo_spell":
			# Re-resolve the last spell played this turn against the same target
			# it originally hit. If the original target is dead/freed, fall back
			# to auto-picking a valid new target so the cast doesn't fizzle.
			var last = _last_spell_played_this_turn
			if last.is_empty():
				return
			if last.get("spell", {}).get("id", "") == "echo_spell":
				return  # Don't echo an Echo — avoids infinite regress.
			var t: Control = null
			if _last_spell_target_ref != null:
				t = _last_spell_target_ref.get_ref()
			var tlane: int = _last_spell_target_lane
			if t == null and last.get("targeting", "none") != "none":
				t = _auto_target_for(last.get("targeting", "none"))
				tlane = t.current_lane if t != null else -1
			# Await so echoed custom spells with UI modals (war_chant, gambit,
			# recycle, scrap) finish before _after_spell increments counters.
			await _resolve_spell(last, t, tlane)
		"venom_tip":
			# Grant Poison to target friendly creature for this round.
			if target != null:
				if not target.card_data.keywords.has("poison"):
					target.card_data.keywords.append("poison")
				target.set_meta("temp_poison", true)
				target.update_stat_display()
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("POISON", Color(0.45, 0.75, 0.20))
		"reanimate":
			# Summon last dead creature as a 1/1 (2/2 if upgraded) token with
			# its keywords.
			var src = _last_dead_copy_data()
			if not src.is_empty():
				var kws: Array = src.get("keywords", []).duplicate()
				var revive_atk: int = 1 + plus_dmg
				var revive_hp: int = 1 + plus_dmg
				# Find an empty lane (front preferred, then back).
				var placed := false
				for row in [ROW_FRONT, ROW_BACK]:
					if placed:
						break
					var field = _row_array(false, row)
					for l in range(LANES_PER_ROW):
						if field[l] == null:
							var tk = CARD_SCENE.instantiate()
							tk.card_id = "token_reanimate_%s" % src.get("id", "unknown")
							tk.is_opponent = false
							tk.is_on_battlefield = true
							tk.is_token = true
							tk.compact_mode = true
							tk.card_data = {"id": tk.card_id, "name": src.get("name", "Revived"),
								"type": "creature", "cost": 0, "atk": revive_atk, "hp": revive_hp,
								"keywords": kws, "rarity": "enemy", "desc": "Reanimated."}
							tk.current_atk = revive_atk
							tk.current_hp = revive_hp
							tk.current_lane = l
							tk.current_row = row
							field[l] = tk
							var slot = _slot_array(false, row)[l]
							_slot_set_card(slot, tk)
							tk.destroyed.connect(_on_card_destroyed.bind(tk))
							tk.will_die.connect(_on_card_will_die.bind(tk))
							if tk.has_floop():
								tk.floop_clicked.connect(_on_floop_clicked.bind(tk))
							tk.update_floop_display()
							# Grant shield if the reanimated keywords include it.
							if kws.has("shield"):
								tk.state.has_shield = true
							placed = true
							break
		"hoarfrost":
			# Target friendly gains Shield; freeze the opposing enemy creature.
			if target != null:
				target.state.has_shield = true
				target.update_stat_display()
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
				var opp = get_opposing_card(target.current_lane, false)
				if opp != null:
					opp.state.is_frozen = true
					if opp.has_method("_spawn_keyword_chip"):
						opp._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
		"ricochet":
			# Deal 1 damage 4 times to random enemy creatures (+2 hits if upgraded).
			var hits: int = 4 + plus_ricochet
			for _i in hits:
				var enemies = _all_enemy_creatures()
				if enemies.is_empty():
					break
				var pick = enemies[randi() % enemies.size()]
				pick.take_damage(1 + spell_dmg_bonus)
				if pick.current_hp <= 0:
					_cleanup_dead()
		"hex":
			# Deal 2 + strip all keywords from target enemy creature.
			if target != null:
				target.take_damage(2 + plus_dmg)
				var combat_kws := KeywordEffects.COMBAT_KEYWORDS.duplicate()
				for kw in combat_kws:
					target.card_data.keywords.erase(kw)
				# Also clear non-combat keywords that grant abilities.
				for kw in ["regenerate", "wither"]:
					target.card_data.keywords.erase(kw)
				if target.card_data.has("wither"):
					target.card_data.erase("wither")
				target.update_stat_display()
		_:
			pass

	_update_hud()


func _after_spell(card: Control) -> void:
	# Pyromancer's Scar (class-restricted): the first spell each combat fires
	# a second time against the same target before bookkeeping. We snapshot
	# the spell data (in case the doubled cast mutates it) and the cached
	# last-target ref; non-targeted spells re-resolve with target=null which
	# matches their original behavior (e.g. Cataclysm hits all enemies twice).
	# _doubling_active_spell stays true through the re-entry so the second
	# pass can't re-trigger the relic recursively.
	if _has_relic("pyromancers_scar") and not _pyromancers_scar_consumed \
			and not _doubling_active_spell:
		_pyromancers_scar_consumed = true
		_doubling_active_spell = true
		var tgt: Control = null
		if _last_spell_target_ref != null:
			var maybe_tgt = _last_spell_target_ref.get_ref()
			if maybe_tgt is Control and is_instance_valid(maybe_tgt):
				tgt = maybe_tgt
		var tlane: int = _last_spell_target_lane if tgt != null else -1
		await _resolve_spell(card.card_data.duplicate(true), tgt, tlane)
		_doubling_active_spell = false
	var was_exhausted: bool = card.has_keyword("exhaust")
	if was_exhausted:
		_exhaust_pile.append(card.card_id)
	else:
		_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))
	# Acolyte's Tome (class-restricted): exhausting a spell refunds a card.
	# Hooks here so any path that exhausts (intrinsic exhaust keyword, Imbue
	# "Double + Exhaust" upgrade) counts uniformly.
	if was_exhausted and _has_relic("acolytes_tome"):
		draw_one()
	card.queue_free()
	# Pen Nib counts cards played (creatures already increment in _play_creature).
	if _has_relic("pen_nib"):
		_pen_nib_counter += 1
		var threshold: int = int(RelicDB.get_relic("pen_nib").get("value", 10))
		if threshold > 0 and _pen_nib_counter >= threshold:
			_pen_nib_counter = 0
			_pen_nib_trigger()
	# Combo counter increments AFTER resolution so Flame Bolt's combo only
	# triggers from the 2nd spell onward (the 1st sets the table).
	_spells_cast_this_turn += 1
	_spells_cast_this_fight += 1
	# Inkpot of Many: every Nth spell, copy a random spell into hand.
	if _has_relic("inkpot_of_many"):
		_inkpot_counter += 1
		var ink_threshold: int = int(RelicDB.get_relic("inkpot_of_many").get("value", 5))
		if ink_threshold > 0 and _inkpot_counter >= ink_threshold:
			_inkpot_counter = 0
			_inkpot_copy_random_spell()
	# Runebound Idol: spell-matters payoff. Each spell cast permanently buffs a
	# random friendly creature +value/+value, turning a spell-heavy deck into a
	# board-growth engine. No-op cleanly when the board is empty.
	if _has_relic("runebound_idol"):
		var ri_targets: Array = _all_player_creatures()
		if ri_targets.size() > 0:
			var ri: int = int(RelicDB.get_relic("runebound_idol").get("value", 1))
			var pick: Control = ri_targets[randi() % ri_targets.size()]
			pick.current_atk += ri
			pick.card_data["hp"] = int(pick.card_data.get("hp", 0)) + ri
			pick.current_hp += ri
			pick.update_stat_display()
			var ri_pos := pick.global_position + Vector2(pick.size.x * pick.scale.x * 0.5, -10)
			spawn_floating_number(ri_pos, "+%d/+%d" % [ri, ri], Color(0.70, 0.55, 1.0), false)
	# Mummified Hand: pick a random creature in hand and zero its cost. Marks
	# the chosen card with a meta so _effective_cost picks it up; cleared at
	# end of turn alongside the discard.
	if _has_relic("mummified_hand"):
		var creature_cards: Array[Control] = []
		for c in _hand:
			if c != null and is_instance_valid(c) and c.is_creature():
				creature_cards.append(c)
		if creature_cards.size() > 0:
			creature_cards[randi() % creature_cards.size()].set_meta("mummified_zero", true)
	# Glowing Hand counter for damage-spell bonus stacking.
	_glowing_hand_spells_cast += 1
	# Hexblade: each spell cast bumps current_atk by 1. Using += preserves any
	# other buffs (Battle Drummer adjacency, War Cry, persistent buffs) that
	# might have been applied — the previous `= base + counter` form silently
	# wiped them on every spell.
	for _hb in _all_player_creatures():
		if _hb.card_data.get("passive", "") == "atk_per_spell":
			_hb.current_atk += 1
			_hb.update_stat_display()
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
	elif _targeting_potion_idx >= 0 and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_resolve_potion_target(event.global_position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_potion_targeting()
			get_viewport().set_input_as_handled()


func _try_resolve_target(pos: Vector2) -> void:
	var targeting = _targeting_data.get("targeting", "none")
	# 4x4: scan both rows for clickable targets. Structures (Pyres, Mausoleums,
	# Altars) are board objects and can never be the target of spells — clicks
	# on them fall through to the dead-zone case below.
	#
	# IMPORTANT: _resolve_spell awaits internally for `custom` spell types and
	# any spell that triggers a discover modal. Without `await` here, the
	# _after_spell post-processing (combo counter bump, Hexblade buff,
	# ON_PLAYER_SPELL reactive, cleanup) used to fire BEFORE the spell actually
	# resolved — observable as "Hexblade gets +1 ATK but the spell didn't seem
	# to do anything." Mirror the non-targeted path at _play_spell line ~2270.
	if targeting in ["enemy_creature", "any_creature", "any"]:
		for e in _all_enemy_creatures():
			if e.has_keyword("structure"):
				continue
			if _is_click_on_card(pos, e):
				# Snapshot the in-flight spell card BEFORE awaiting — if we
				# read _targeting_spell after the await, another spell cast
				# could have replaced it (e.g. a discover reward) and we'd
				# discard the wrong card.
				var spell_card := _targeting_spell
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				_hide_targeting_arrow()
				await _resolve_spell(spell_card.card_data, e, e.current_lane)
				_after_spell(spell_card)
				return
	if targeting in ["friendly_creature", "any_creature", "any"]:
		for p in _all_player_creatures():
			if p.has_keyword("structure"):
				continue
			if _is_click_on_card(pos, p):
				var spell_card := _targeting_spell
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				_hide_targeting_arrow()
				await _resolve_spell(spell_card.card_data, p, p.current_lane)
				_after_spell(spell_card)
				return
	# "any" targeting: check if clicked enemy hero area (top of screen). Route
	# through _resolve_spell with target=null so custom spells (Quick Shot)
	# resolve their else-branch face damage, draw their card, fire reactives,
	# and pick up Worn Spellbook — the old inline path read spell.value (=0
	# for custom spells) and silently dealt no damage.
	if targeting == "any" and pos.y < get_viewport_rect().size.y * 0.15:
		var spell_card := _targeting_spell
		_targeting_spell = null
		_targeting_data = {}
		_info_label.text = ""
		_hide_targeting_arrow()
		await _resolve_spell(spell_card.card_data, null, -1)
		_after_spell(spell_card)
		return


func _use_combat_potion(index: int) -> void:
	## Click handler for a combat HUD potion slot. Cancels any in-flight spell
	## targeting (you can't target both at once). Non-targeted potions resolve
	## immediately; targeted ones enter potion-targeting mode.
	if phase != Phase.PLAYER_TURN:
		return
	if index < 0 or index >= RunState.potions.size():
		return
	if _targeting_spell != null:
		_cancel_targeting()
	var pid: String = RunState.potions[index]
	var data: Dictionary = PotionDB.get_potion(pid)
	if data.is_empty() or data.get("usable_in", "combat") == "map":
		return
	var targeting: String = data.get("targeting", "none")
	if targeting == "none":
		_resolve_combat_potion(pid, null)
		RunState.consume_potion(index)
		_rebuild_potion_bar()
		_update_hud()
	else:
		_targeting_potion_idx = index
		_info_label.text = "%s — target a %s" % [
			data.get("name", pid),
			"friendly creature" if targeting == "friendly_creature" else "creature"
		]


func _try_resolve_potion_target(pos: Vector2) -> void:
	if _targeting_potion_idx < 0:
		return
	if _targeting_potion_idx >= RunState.potions.size():
		_cancel_potion_targeting()
		return
	var pid: String = RunState.potions[_targeting_potion_idx]
	var data: Dictionary = PotionDB.get_potion(pid)
	var targeting: String = data.get("targeting", "none")
	var pool: Array = []
	if targeting in ["friendly_creature", "any_creature"]:
		pool.append_array(_all_player_creatures())
	if targeting in ["enemy_creature", "any_creature"]:
		pool.append_array(_all_enemy_creatures())
	for c in pool:
		if _is_click_on_card(pos, c):
			_resolve_combat_potion(pid, c)
			RunState.consume_potion(_targeting_potion_idx)
			_targeting_potion_idx = -1
			_info_label.text = ""
			_rebuild_potion_bar()
			_update_hud()
			return


func _cancel_potion_targeting() -> void:
	_targeting_potion_idx = -1
	_info_label.text = ""


func _resolve_combat_potion(pid: String, target: Control) -> void:
	## Apply the in-combat effect of `pid`. `target` is non-null only for
	## targeted potions. Effects mirror existing combat primitives so each
	## handler stays tiny.
	var data: Dictionary = PotionDB.get_potion(pid)
	match data.get("effect", ""):
		"heal_hp":
			RunState.heal_hero(8)
			player_hp = RunState.hero_hp
		"buff_atk":
			if target != null and target.is_creature():
				target.temp_atk_buff += 3
				target.update_stat_display()
		"gain_mana":
			player_mana += 2
		"aoe_enemies":
			for c in _all_enemy_creatures():
				c.take_damage(3)
		"draw":
			for _i in range(3):
				draw_one()
		"revive_last_dead":
			_revive_last_dead_friendly()
		"grant_rampage":
			# War Paint: bolt Rampage 2 + +1 ATK onto a friendly for the fight.
			# Adds the runtime keyword so _apply_combat_strike_riders grows it on
			# every kill, and bumps the rampage value so the trigger is +2.
			if target != null and target.is_creature():
				if "rampage" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("rampage")
				target.card_data["rampage"] = maxi(2, int(target.card_data.get("rampage", 0)))
				target.persistent_atk_buff += 1
				target.persistent_atk_buff_rounds = 99  # rest of this fight
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("RAMPAGE", Color(1.0, 0.62, 0.20))
				_vfx_fire(target.get_global_rect().get_center())
				target.update_stat_display()
		"grant_lifelink":
			# Vampiric Draught: friendly gains Lifelink 2 for the fight + a 4 HP
			# top-up now. Mirrors Censer Light's runtime keyword-grant pattern so
			# _apply_combat_strike_riders heals off it.
			if target != null and target.is_creature():
				if "lifelink" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("lifelink")
				target.card_data["lifelink"] = maxi(2, int(target.card_data.get("lifelink", 0)))
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LIFELINK", Color(0.95, 0.35, 0.45))
				_vfx_blight(target.get_global_rect().get_center())
				target.update_stat_display()
			RunState.heal_hero(4)
			player_hp = RunState.hero_hp
		"chain_lightning":
			# Chain-Lightning Flask: 4 jumps of 2 damage to random enemy creatures.
			# Re-rolls the pool each jump so it spreads across the board (and keeps
			# arcing even as bodies drop). Mirrors the Ricochet spell shape.
			for _i in range(4):
				var pool := _all_enemy_creatures()
				if pool.is_empty():
					break
				var pick: Control = pool[randi() % pool.size()]
				_vfx_shock(pick.get_global_rect().get_center())
				pick.take_damage(2)
				if pick.current_hp <= 0:
					_cleanup_dead()
		"detonate_doom_all":
			# Doomsday Draught: fire every friendly Doom creature's detonation now.
			# Snapshot the list first — _detonate_doom destroys via the canonical
			# path, mutating the field arrays mid-iteration would skip neighbours.
			var bombs: Array = []
			for c in _all_player_creatures():
				if c.has_keyword("doom"):
					bombs.append(c)
			for c in bombs:
				if is_instance_valid(c) and c.current_hp > 0:
					_detonate_doom(c)
			_cleanup_dead()
		"shield_wall":
			# Aegis Brew: every friendly creature gains Shield (one free hit).
			for c in _all_player_creatures():
				c.state.has_shield = true
				if c.has_method("_spawn_keyword_chip"):
					c._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
				_vfx_blessing(c.get_global_rect().get_center())
				c.update_stat_display()
		"summon_recruits":
			# Conscription Brew: muster two 3/3 Recruits into empty lanes (front
			# preferred). summon_token falls through to the other row of a column
			# if the front slot is taken, so this fills sensibly on a busy board.
			var made: int = 0
			for r in [ROW_FRONT, ROW_BACK]:
				if made >= 2:
					break
				var arr = _row_array(false, r)
				for l in range(LANES_PER_ROW):
					if made >= 2:
						break
					if arr[l] == null:
						summon_token(3, 3, l, false, r)
						var nt = _row_array(false, r)[l]
						if nt != null and is_instance_valid(nt):
							nt.card_data["name"] = "Recruit"
							_vfx_blessing(nt.get_global_rect().get_center())
						made += 1
		_:
			push_warning("Combat: unknown potion effect '%s'" % data.get("effect", ""))


func _revive_last_dead_friendly() -> void:
	## Phoenix Brew: return the player's last dead creature to a random empty
	## lane as a 1/1 with its keywords. Falls back to no-op if nothing died or
	## no empty slot exists.
	if _last_dead_creature_id == "":
		return
	var src: Dictionary = CardDB.get_card_data(_last_dead_creature_id)
	if src.is_empty() or src.get("type", "") != "creature":
		return
	var empties: Array = []
	for r in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(false, r)
		for l in range(LANES_PER_ROW):
			if arr[l] == null:
				empties.append({"row": r, "lane": l})
	if empties.is_empty():
		return
	var pick: Dictionary = empties[randi() % empties.size()]
	# Synthetic card_data — 1/1 body but inherits keywords and persistent
	# abilities (floop, on_death, adj_buff, passive) from the source so the
	# revived creature still "remembers" what it was.
	var token: Dictionary = src.duplicate(true)
	token["id"] = "phoenix_%s" % _last_dead_creature_id
	token["atk"] = 1
	token["hp"] = 1
	token["cost"] = 0
	token["is_token"] = true
	# Drop on-enter so reviving doesn't re-fire its play effect (often damage).
	token.erase("on_enter")
	var card = CARD_SCENE.instantiate()
	card.card_id = token["id"]
	card.is_opponent = false
	card.is_on_battlefield = true
	card.is_token = true
	card.compact_mode = true
	card.card_data = token
	card.current_atk = 1
	card.current_hp = 1
	card.current_lane = pick.lane
	card.current_row = pick.row
	_row_array(false, pick.row)[pick.lane] = card
	var slot = _slot_array(false, pick.row)[pick.lane]
	_slot_set_card(slot, card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	card.will_die.connect(_on_card_will_die.bind(card))
	if card.has_floop():
		card.floop_clicked.connect(_on_floop_clicked.bind(card))
	card.update_floop_display()


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
#  FLOOP (free toggle — click battlefield creature to activate)
# =====================================================================

func _on_floop_clicked(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
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


func _maybe_show_banking_tutorial() -> void:
	if _banking_tutorial_shown:
		return
	_banking_tutorial_shown = true
	UserSettings.mark_banking_tutorial_seen()
	_show_tutorial_tip("BANK: Unspent mana carries over to next turn (max 2). End turns early to save up.")


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
		# Scroll of Greed: +1 gold per non-normal draw. Mirrors the reactive
		# threshold so the relic only pays out on bonus draws, not the standard
		# 4-card turn open.
		if _has_relic("scroll_of_greed"):
			RunState.gain_gold(1)


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
	# Pen Nib: if this uid was chosen this fight, stamp it 6/6 Piercing before
	# the layout builds (mirrors the Snecko cost mutation below — card_data is a
	# per-card duplicate so this is safe).
	if uid >= 0 and uid == _pen_nib_buffed_uid and card.card_data.get("type", "") == "creature":
		card.card_data["atk"] = 6
		card.card_data["hp"] = 6
		if not card.card_data.keywords.has("piercing"):
			card.card_data.keywords.append("piercing")
	# Snecko Eye: every freshly-drawn card's cost is randomized 0-3 for this
	# turn. card_data is a per-card duplicate so mutating it here is safe.
	# The mutation happens BEFORE add_child below, so _build_layout reads the
	# randomized cost and the orb shows the new number on first paint.
	if _has_relic("snecko_eye"):
		card.card_data["cost"] = randi() % 4
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
	const REST_SCALE := Vector2(0.72, 0.72)
	# How far below the container's bottom edge the cards' bottom-centres
	# anchor. Cards at scale 0.72 have a rendered height of ~216 px; with
	# PEEK 76 the resting bottom-centre lands at y=966, so the card TOP sits
	# at ~y=750 -- a 13px margin below the player back row (which ends at y=737), so the
	# hand never covers back-row creature stats. ~70% of each card stays visible
	# at rest (cost + name + art); the bottom hangs off-screen below the edge.
	# Hover lifts the card by 80 px (Card2D._on_mouse_entered) bringing it
	# fully into view plus an elevation pop above its neighbours.
	const PEEK := 76.0

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
	# PERSISTENT_HAND: keep the whole hand across turns — the start-of-round
	# refill (draw-to-N) tops it up instead of redrawing fresh. When off, the
	# original fresh-hand discard runs (minus Retain / Runic Pyramid).
	if not PERSISTENT_HAND:
		# Runic Pyramid (boss relic): the whole hand is retained at end of turn.
		var keep_all: bool = _has_relic("runic_pyramid")
		var to_keep: Array[Control] = []
		for card in _hand:
			if keep_all or card.has_keyword("retain"):
				to_keep.append(card)
			else:
				_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))
				_animate_card_to_discard(card)
		_hand = to_keep
	# Reset temp buffs on every creature, both rows, both sides. (Always — this
	# is end-of-turn creature upkeep, independent of the hand model.)
	for c in _all_creatures_both_sides():
		c.temp_atk_buff = 0
		c.has_attacked_this_turn = false
		c.has_flooped_this_turn = false
		# Per-turn spell-granted flags (War Cry → Swift, Shield Wall → Thorns,
		# Inspire → Piercing).
		c.set_meta("war_cry_swift", false)
		c.set_meta("shield_wall_thorns", false)
		c.set_meta("inspire_piercing", false)
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
	# Vengeance: any friendly creature with vengeance_growth passive grows
	# +2 ATK per face-damage event (not per point of damage). +3 if upgraded.
	if amount > 0:
		for c in _all_player_creatures():
			if c.card_data.get("passive", "") == "vengeance_growth":
				c.current_atk += 3 if bool(c.card_data.get("is_upgraded", false)) else 2
				c.update_stat_display()
	# Battle Scars: first face-damage event each fight grants +2 mana this turn.
	if amount > 0 and _has_relic("battle_scars") and not _battle_scars_triggered_this_fight:
		_battle_scars_triggered_this_fight = true
		player_mana += 2
		_update_hud()
	_on_hero_damaged(amount)
	# JUICE — taking face damage is the loudest, most legible moment in the game.
	# This is the feedback that makes players STOP ignoring threats: a heavy
	# magnitude-scaled shake, a deep red vignette pulse, and a big number that
	# punches the HP counter. (The hit-stop beat is supplied by the combat
	# cascade after the hit — see the note at the end of this block.)
	if amount > 0:
		screen_shake(clampf(8.0 + amount * 3.4, 10.0, 28.0))
		_play_face_damage_flash(amount)
		presence_react_player_hit(amount)   # the foe surges as it lands the blow
		if _player_hp_label != null:
			# Bigger + gold-outlined the harder the hit; a soft punch-up tells the
			# player exactly how much life just evaporated.
			var fc := Color(1.0, 0.28, 0.22)
			spawn_floating_number(_player_hp_label.get_global_rect().get_center() + Vector2(0, -6),
				"-%d" % amount, fc, true)
			_punch_label(_player_hp_label, 1.22)
		if AudioBank != null:
			AudioBank.play_sfx("hit_hero")
		# Note: the combat cascade (_creature_hits_face / _resolve_ranged_attacks)
		# already supplies an awaited HITSTOP_BEAT after a face hit, so the pause
		# is handled there — we keep this function synchronous so every caller
		# (most of which don't await) gets the loud shake/flash/number instantly.
	else:
		presence_react_player_hit(amount)
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	# Pyre Stoker: face damage you deal this turn gets +1 if you played 3+ cards.
	# Reads _cards_played_this_turn directly so each face hit recomputes the
	# bonus — if you cross the threshold mid-turn, subsequent hits scale.
	if _has_relic("pyre_stoker") and _cards_played_this_turn >= 3 and amount > 0:
		amount += int(RelicDB.get_relic("pyre_stoker").get("value", 1))
	enemy_hp -= amount
	screen_shake(clampf(amount * 2.0, 4.0, 15.0))
	presence_flinch(amount)   # the antagonist recoils + reddens
	if _enemy_hp_label != null and amount > 0:
		spawn_floating_number(_enemy_hp_label.get_global_rect().get_center(),
			"-%d" % amount, Color(1.0, 0.45, 0.2), true)
	if AudioBank != null and amount > 0:
		AudioBank.play_sfx("hit_hero")
	_check_boss_phase_transition()
	_update_hud()
	_check_game_over()


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


func _compute_spell_tome() -> void:
	## spell_tome: if 50%+ of the run deck is spells, all spells cost 1 less.
	## Deck composition is fixed during a combat, so compute once at start.
	_spell_tome_active = false
	if not _has_relic("spell_tome"):
		return
	var total: int = RunState.deck.size()
	if total == 0:
		return
	var spells := 0
	for cid in RunState.deck:
		if CardDB.get_card_data(cid).get("type", "") == "spell":
			spells += 1
	_spell_tome_active = float(spells) / float(total) >= 0.5


func _snecko_randomize_card_cost(card: Control) -> void:
	## Snecko Eye: replace this card's cost with a fresh 0-3 roll for this turn.
	## card_data is a per-card duplicate (see _draw_card / _resolve_card_data),
	## so mutating it is safe — won't pollute CardDB or the run deck. The cost
	## orb refreshes via _refresh_hand_affordability (inside _update_hud).
	if card == null or not is_instance_valid(card):
		return
	card.card_data["cost"] = randi() % 4


func _pen_nib_trigger() -> void:
	## Pen Nib payoff: the player picks a creature in their DECK; it becomes a
	## 6/6 Piercing for the rest of this fight. The buff lands on any live copy
	## already in hand / on the board, and on future draws of the same uid via
	## _pen_nib_buffed_uid (see _draw_card). Per-fight scope — Combat reloads
	## card state from RunState each fight, so it never persists. Fired
	## fire-and-forget from the play sites so it doesn't reorder bookkeeping.
	var idx: int = await GameTheme.show_deck_picker(self,
		"Pen Nib — choose a creature to become 6/6 Piercing", "creature", false)
	if idx < 0 or idx >= RunState.deck_uids.size():
		return
	var uid: int = RunState.deck_uids[idx]
	_pen_nib_buffed_uid = uid
	for c in _hand:
		if c != null and is_instance_valid(c) and c.deck_uid == uid:
			_apply_pen_nib_buff_to_card(c)
	for c in _all_player_creatures():
		if c != null and is_instance_valid(c) and c.deck_uid == uid:
			_apply_pen_nib_buff_to_card(c)


func _apply_pen_nib_buff_to_card(card: Control) -> void:
	## Stamp a live card as 6/6 Piercing (Pen Nib). For not-yet-built draws,
	## mutate card_data directly instead (see _draw_card) — update_stat_display
	## requires the card's nodes to already exist.
	if card == null or not is_instance_valid(card) or not card.is_creature():
		return
	card.card_data["atk"] = 6
	card.card_data["hp"] = 6
	card.current_atk = 6
	card.current_hp = 6
	if not card.card_data.keywords.has("piercing"):
		card.card_data.keywords.append("piercing")
	card.update_stat_display()
	if card.has_method("_spawn_keyword_chip"):
		card._spawn_keyword_chip("PEN NIB", Color(0.95, 0.78, 0.45))


func _inkpot_copy_random_spell() -> void:
	## Inkpot of Many: drop a random spell from CardDB's draftable pool into
	## the player's hand. Uses an ephemeral deck_uid (negative) so it never
	## collides with run-deck uids and won't be tracked by upgrades.
	if _hand.size() >= MAX_HAND_SIZE:
		return
	var pool: Array[String] = []
	for id in CardDB.CARD_POOL.keys():
		var d: Dictionary = CardDB.CARD_POOL[id]
		if d.get("type", "") == "spell" and d.get("rarity", "") in ["common", "uncommon", "rare"]:
			pool.append(id)
	if pool.is_empty():
		return
	var picked: String = pool[randi() % pool.size()]
	# Build a synthetic pile entry so _draw_card can pull it via its normal
	# pipeline (this also gets us the prebake / cost-orb / animation paths).
	_player_draw_pile.push_front(_pile_entry(picked, _ephemeral_uid_counter))
	_ephemeral_uid_counter -= 1
	draw_one()


func _on_friendly_damaged(amount: int, card: Control) -> void:
	## Signal handler for the Card2D `damaged` signal on friendly creatures.
	## Dispatches every relic that reacts to "an ally got hit". Card2D guards
	## amount > 0 already so we don't have to.
	if card == null or not is_instance_valid(card):
		return
	if _has_relic("stalwarts_anvil") and not _stalwarts_anvil_fired_this_turn:
		_stalwarts_anvil_fired_this_turn = true
		player_mana += int(RelicDB.get_relic("stalwarts_anvil").get("value", 1))
		_update_hud()
	if _has_relic("spike_driver"):
		# Find the attacker that's currently swinging — Combat tracks the swing
		# via _current_attacker (set in _resolve_*_attack helpers). If none is
		# active (e.g. spell damage), hit a random opposing creature in lane.
		var lane = card.current_lane
		var opp = get_opposing_card(lane, false)
		if opp != null:
			opp.take_damage_bypass_armor(int(RelicDB.get_relic("spike_driver").get("value", 1)))
	if _has_relic("wormwood"):
		var cap: int = int(RelicDB.get_relic("wormwood").get("value", 5))
		var stacks: int = card.get_meta("wormwood_stacks", 0)
		if stacks < cap:
			card.current_atk += 1
			card.set_meta("wormwood_stacks", stacks + 1)
			card.update_stat_display()


func _trigger_player_sacrifice(victim: Control) -> void:
	## Fires every player-sacrifice hook on the given friendly target. Called
	## by ALL three sacrifice paths the design allows: the blood_sacrifice
	## floop, the Offering / Fuel the Pyre spells, and (future) the "sacrifice"
	## play cost. Caller is responsible for actually killing the victim — this
	## helper only fires triggers so the kill order can stay caller-specific
	## (some callers want to read effective_atk BEFORE the death animation).
	if victim == null or not is_instance_valid(victim):
		return
	var lane: int = victim.current_lane
	if _has_relic("bone_pile"):
		var opp = get_opposing_card(lane, false)
		if opp != null:
			opp.take_damage(victim.effective_atk())
	if _has_relic("butchers_cleaver"):
		_butchers_cleaver_armed = true
	# Reaper's Scythe: stash the victim's floop dict so the next-played
	# creature inherits (or has its own floop replaced by) it. blood_sacrifice
	# is itself a floop dict, so the chain holds; spell-sacrificed targets
	# may or may not have one, and the relic check handles both cases.
	if _has_relic("reapers_scythe") and victim.card_data.has("on_play"):
		_reapers_scythe_pending_floop = victim.card_data["on_play"].duplicate(true)
	_dispatch_reactive("ON_PLAYER_SACRIFICE", null, lane)


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
		"cost": 0, "atk": atk, "hp": token_hp, "keywords": [], "rarity": "enemy",
		"desc": "", "is_token": true}
	card.current_atk = atk
	card.current_hp = token_hp
	card.current_lane = lane_idx
	card.current_row = row
	field[lane_idx] = card
	var slot = _slot_array(is_enemy, row)[lane_idx]
	_slot_set_card(slot, card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	card.will_die.connect(_on_card_will_die.bind(card))
	if not is_enemy and card.has_floop():
		card.floop_clicked.connect(_on_floop_clicked.bind(card))
	card.update_floop_display()
	# Linked Banner: a freshly-summoned friendly bumps neighbors' adjacency
	# counts. Re-scan so any ally that just hit 2+ adjacents gets +1 HP.
	if not is_enemy:
		_apply_linked_banner_hp()


func _return_dead_to_hand(lane_idx: int) -> void:
	if _grave_pact_active and _last_dead_creature_id != "":
		# Push a proper "card_id#uid" entry so the upgrade lookup at draw
		# time fires correctly (previously this dropped the uid and the
		# revived card lost its upgrades).
		_player_draw_pile.push_front(
			_pile_entry(_last_dead_creature_id, _last_dead_creature_uid))
		draw_one()
		_grave_pact_active = false


# =====================================================================
#  DISCOVER — StS-style pick-1-of-3 overlay (Hearthstone/Cross-Blitz idea).
# =====================================================================

func _show_discover(type_filter: String, rarity_filter: String) -> int:
	## Build a pool from CARD_POOL by type and rarity, pick 3 random, show the
	## modal pick UI. Awaits the player's choice; the chosen card is added to
	## hand with a fresh deck_uid (so Rest-site upgrades can target it).
	## Returns the picked card's deck_uid, or -1 if dismissed.
	##   type_filter: "any" | "creature" | "spell"
	##   rarity_filter: "" (any draftable rarity) | "common" | "uncommon" | "rare"
	var pool: Array[String] = []
	for id in CardDB.CARD_POOL.keys():
		var d = CardDB.CARD_POOL[id]
		var rarity: String = d.get("rarity", "")
		# Exclude starters/curse/enemy from the discover pool — drafted rarities only.
		if rarity not in ["common", "uncommon", "rare"]:
			continue
		if type_filter != "any" and d.get("type", "") != type_filter:
			continue
		if rarity_filter != "" and rarity != rarity_filter:
			continue
		pool.append(id)
	if pool.size() < 3:
		return -1
	pool.shuffle()
	var picks: Array = [pool[0], pool[1], pool[2]]
	var picked_id: String = await _build_discover_overlay(picks)
	if picked_id != "":
		return _add_discovered_card_to_hand(picked_id)
	return -1


func _show_recycle_modal() -> Control:
	## Recycle spell: modal shows every card currently in hand. Player clicks
	## one to exhaust it; that card node is returned (so the caller can finish
	## the bookkeeping — exhaust + mana gain). Returns null if cancelled or
	## hand is empty.
	if _hand.is_empty():
		return null

	# Snapshot hand contents (the array can mutate during the await window
	# if we don't, since draw effects might add cards mid-modal).
	var snapshot: Array[Control] = []
	for c in _hand:
		snapshot.append(c)

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Exhaust a card for mana"
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = mini(snapshot.size(), 6)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)

	var result := {"card": null, "cancelled": false}
	for hand_card in snapshot:
		var data: Dictionary = hand_card.card_data
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(220, 300)
		grid.add_child(slot)

		var display := CARD_SCENE.instantiate()
		display.card_id = hand_card.card_id
		display.card_data = data.duplicate(true)
		display.is_on_battlefield = true
		slot.add_child(display)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var captured: Control = hand_card
		btn.pressed.connect(func():
			result["card"] = captured
			overlay.queue_free()
		)
		slot.add_child(btn)

	var cancel := GameTheme.make_back_button("CANCEL", Vector2(160, 40))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func():
		result["cancelled"] = true
		overlay.queue_free()
	)
	col.add_child(cancel)

	while result["card"] == null and not result["cancelled"] and is_instance_valid(overlay):
		await get_tree().process_frame
	return result["card"]


func _show_discard_picker(target_count: int, title_text: String, allow_fewer: bool = false) -> Array:
	## Generic "pick N cards from hand to discard" modal. Used by Gambit
	## (up to 3, allow_fewer=true), Scrap (exactly 1), War Chant (exactly 2),
	## and Mule's floop (exactly 1). Returns the array of selected Card2D
	## nodes — caller handles the discard/draw bookkeeping.
	if _hand.is_empty():
		return []
	if target_count <= 0:
		return []
	# Snapshot hand so mid-modal draws (Mule discards before drawing) don't
	# desync the displayed cards.
	var snapshot: Array[Control] = []
	for c in _hand:
		snapshot.append(c)

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Caption shows running selection count.
	var caption := Label.new()
	caption.add_theme_font_override("font", GameTheme.font_body)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)

	var grid := GridContainer.new()
	grid.columns = mini(snapshot.size(), 6)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)

	var state := {"picked": [] as Array[Control], "confirmed": false, "cancelled": false}

	# Visual markers + selection toggle for each hand card.
	var slots: Array = []
	for hand_card in snapshot:
		var data: Dictionary = hand_card.card_data
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(220, 300)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0)
		bg.border_width_left = 4
		bg.border_width_right = 4
		bg.border_width_top = 4
		bg.border_width_bottom = 4
		bg.border_color = Color(0, 0, 0, 0)
		slot.add_theme_stylebox_override("panel", bg)
		grid.add_child(slot)

		var display := CARD_SCENE.instantiate()
		display.card_id = hand_card.card_id
		display.card_data = data.duplicate(true)
		display.is_on_battlefield = true
		slot.add_child(display)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var captured: Control = hand_card
		var slot_ref: Panel = slot
		var bg_ref: StyleBoxFlat = bg
		btn.pressed.connect(func():
			if state.picked.has(captured):
				state.picked.erase(captured)
				bg_ref.border_color = Color(0, 0, 0, 0)
			else:
				if state.picked.size() >= target_count:
					# Replace the oldest selection to maintain target_count cap.
					var oldest: Control = state.picked.pop_front()
					for s in slots:
						if s.captured == oldest:
							s.bg.border_color = Color(0, 0, 0, 0)
							break
				state.picked.append(captured)
				bg_ref.border_color = Color(0.95, 0.45, 0.30, 1.0)
			caption.text = "Selected %d / %d" % [state.picked.size(), target_count]
		)
		slot.add_child(btn)
		slots.append({"captured": captured, "bg": bg_ref})

	caption.text = "Selected 0 / %d" % target_count

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var confirm_btn := GameTheme.make_themed_button("CONFIRM",
		Color(0.18, 0.30, 0.14), Vector2(180, 44), 16)
	confirm_btn.pressed.connect(func():
		# Require exactly target_count unless allow_fewer.
		if state.picked.size() == target_count or (allow_fewer and state.picked.size() > 0):
			state.confirmed = true
			overlay.queue_free()
	)
	btn_row.add_child(confirm_btn)

	if allow_fewer:
		var skip_btn := GameTheme.make_back_button("SKIP", Vector2(160, 44))
		skip_btn.pressed.connect(func():
			state.confirmed = true
			overlay.queue_free()
		)
		btn_row.add_child(skip_btn)

	while not state.confirmed and not state.cancelled and is_instance_valid(overlay):
		await get_tree().process_frame
	return state.picked


func _pick_adjacent_friendly(lane_idx: int, my_row: int, prompt: String) -> Control:
	## Used by floops that say "pick adjacent friendly" (Necromancer kill,
	## Corpse Eater devour). Highlights the candidate cards in red and waits
	## for a click. Returns null if no adjacent friendly exists or the click
	## misses. Falls through to random if there's only one candidate (no
	## decision to make).
	var candidates: Array[Control] = []
	var field := _row_array(false, my_row)
	for adj_lane in [lane_idx - 1, lane_idx + 1]:
		if adj_lane >= 0 and adj_lane < LANES_PER_ROW and field[adj_lane] != null:
			candidates.append(field[adj_lane])
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	# Overlay covers the screen but lets clicks fall through to the candidate
	# cards. A bottom banner shows the prompt; clicking outside any candidate
	# cancels.
	_show_info(prompt)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.35)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.z_index = 150
	add_child(overlay)

	# Pulse each candidate so the player sees what's pickable.
	var pulses: Array = []
	for c in candidates:
		if c.has_method("play_floop_pulse"):
			c.play_floop_pulse()
		var border_panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_width_left = 4
		sb.border_width_right = 4
		sb.border_width_top = 4
		sb.border_width_bottom = 4
		sb.border_color = Color(0.95, 0.45, 0.30, 0.9)
		border_panel.add_theme_stylebox_override("panel", sb)
		border_panel.size = c.size * c.scale
		border_panel.global_position = c.global_position
		border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border_panel.z_index = 160
		add_child(border_panel)
		pulses.append(border_panel)

	var result := {"card": null, "cancelled": false}
	# Click handler: capture viewport clicks, check which candidate was hit.
	var click_capture := ColorRect.new()
	click_capture.color = Color(0, 0, 0, 0)
	click_capture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_capture.mouse_filter = Control.MOUSE_FILTER_STOP
	click_capture.z_index = 155
	add_child(click_capture)
	click_capture.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = event.global_position
			for c in candidates:
				if not is_instance_valid(c):
					continue
				var rect := Rect2(c.global_position, c.size * c.scale)
				if rect.has_point(pos):
					result["card"] = c
					return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			result["cancelled"] = true
	)

	while result["card"] == null and not result["cancelled"]:
		await get_tree().process_frame

	for p in pulses:
		if is_instance_valid(p):
			p.queue_free()
	if is_instance_valid(overlay):
		overlay.queue_free()
	if is_instance_valid(click_capture):
		click_capture.queue_free()
	return result["card"]


func _pick_friendly_creature(exclude_card: Control, prompt: String) -> Control:
	## Used by on_enter effects that ask "pick a friendly to copy" (Copycat).
	## Highlights every friendly creature on the board except the source. Returns
	## null if there's no other friendly. Auto-returns if only one candidate.
	var candidates: Array[Control] = []
	for c in _all_player_creatures():
		if c != exclude_card and is_instance_valid(c):
			candidates.append(c)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	_show_info(prompt)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.35)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.z_index = 150
	add_child(overlay)

	var pulses: Array = []
	for c in candidates:
		if c.has_method("play_floop_pulse"):
			c.play_floop_pulse()
		var border_panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_width_left = 4
		sb.border_width_right = 4
		sb.border_width_top = 4
		sb.border_width_bottom = 4
		# Cyan border for "copy this" — distinct from green (relocate) and red
		# (adjacent kill/devour).
		sb.border_color = Color(0.35, 0.85, 0.95, 0.9)
		border_panel.add_theme_stylebox_override("panel", sb)
		border_panel.size = c.size * c.scale
		border_panel.global_position = c.global_position
		border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border_panel.z_index = 160
		add_child(border_panel)
		pulses.append(border_panel)

	var result := {"card": null, "cancelled": false}
	var click_capture := ColorRect.new()
	click_capture.color = Color(0, 0, 0, 0)
	click_capture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_capture.mouse_filter = Control.MOUSE_FILTER_STOP
	click_capture.z_index = 155
	add_child(click_capture)
	click_capture.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = event.global_position
			for c in candidates:
				if not is_instance_valid(c):
					continue
				var rect := Rect2(c.global_position, c.size * c.scale)
				if rect.has_point(pos):
					result["card"] = c
					return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			result["cancelled"] = true
	)

	while result["card"] == null and not result["cancelled"]:
		await get_tree().process_frame

	for p in pulses:
		if is_instance_valid(p):
			p.queue_free()
	if is_instance_valid(overlay):
		overlay.queue_free()
	if is_instance_valid(click_capture):
		click_capture.queue_free()
	return result["card"]


func _pick_empty_lane(my_row: int, exclude_lane: int, prompt: String) -> int:
	## Used by floops that move/place to an empty lane in the player's row
	## (Harpy relocate). Highlights empty slot positions in green, waits for a
	## click on one. Returns the chosen lane index, or -1 if there are no
	## empties / the click missed. Auto-returns the lone empty if there's only
	## one (no decision to make).
	var slots: Array = _slot_array(false, my_row)
	var field: Array = _row_array(false, my_row)
	var empty_lanes: Array[int] = []
	for i in range(LANES_PER_ROW):
		if i != exclude_lane and field[i] == null:
			empty_lanes.append(i)
	if empty_lanes.is_empty():
		return -1
	if empty_lanes.size() == 1:
		return empty_lanes[0]

	_show_info(prompt)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.35)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.z_index = 150
	add_child(overlay)

	var pulses: Array = []
	for lane in empty_lanes:
		var slot: Control = slots[lane]
		var border_panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_width_left = 4
		sb.border_width_right = 4
		sb.border_width_top = 4
		sb.border_width_bottom = 4
		# Green border for "move here" — distinct from the red "pick a friendly"
		# in `_pick_adjacent_friendly`.
		sb.border_color = Color(0.30, 0.85, 0.45, 0.9)
		border_panel.add_theme_stylebox_override("panel", sb)
		border_panel.size = slot.size
		border_panel.global_position = slot.global_position
		border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border_panel.z_index = 160
		add_child(border_panel)
		pulses.append(border_panel)

	var result := {"lane": -1, "cancelled": false}
	var click_capture := ColorRect.new()
	click_capture.color = Color(0, 0, 0, 0)
	click_capture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_capture.mouse_filter = Control.MOUSE_FILTER_STOP
	click_capture.z_index = 155
	add_child(click_capture)
	click_capture.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = event.global_position
			for lane in empty_lanes:
				var s: Control = slots[lane]
				var rect := Rect2(s.global_position, s.size)
				if rect.has_point(pos):
					result["lane"] = lane
					return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			result["cancelled"] = true
	)

	while result["lane"] == -1 and not result["cancelled"]:
		await get_tree().process_frame

	for p in pulses:
		if is_instance_valid(p):
			p.queue_free()
	if is_instance_valid(overlay):
		overlay.queue_free()
	if is_instance_valid(click_capture):
		click_capture.queue_free()
	return result["lane"]


func _show_reorder_modal(n: int) -> void:
	## Raven's reorder floop: reveal the top N cards of the draw pile. The
	## player clicks them in their desired draw order — first click = drawn
	## first. Once all N are picked, the new order is applied.
	n = mini(n, _player_draw_pile.size())
	if n <= 1:
		return

	# Snapshot the cards we're letting the player reorder.
	var top_entries: Array[String] = []
	for i in range(n):
		top_entries.append(_player_draw_pile[i])

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Reorder Top %d — click in draw order" % n
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	# Shared state across closures: the picked order (indices into top_entries).
	var picked_order: Array = []
	# Cache slot nodes so a click on card i can dim its slot and stamp a badge.
	var slots: Array[Control] = []

	for i in range(n):
		var entry: String = top_entries[i]
		var data: Dictionary = CardDB.get_card_data(_entry_id(entry))
		if data.is_empty():
			continue
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(220, 320)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(slot)
		slots.append(slot)

		var card_node = CARD_SCENE.instantiate()
		card_node.card_id = _entry_id(entry)
		card_node.card_data = data
		card_node.is_on_battlefield = true
		slot.add_child(card_node)

		# Numeric badge — hidden until this card is picked.
		var badge := Label.new()
		badge.name = "OrderBadge"
		badge.visible = false
		badge.text = ""
		badge.add_theme_font_override("font", GameTheme.font_display)
		badge.add_theme_font_size_override("font_size", 56)
		badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		badge.add_theme_constant_override("outline_size", 8)
		badge.set_anchors_preset(Control.PRESET_CENTER)
		badge.offset_left = -40; badge.offset_right = 40
		badge.offset_top = -40; badge.offset_bottom = 40
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(badge)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var captured_index: int = i
		btn.pressed.connect(func():
			if picked_order.has(captured_index):
				return
			picked_order.append(captured_index)
			badge.text = str(picked_order.size())
			badge.visible = true
			slot.modulate = Color(0.55, 0.55, 0.55, 1.0)
			btn.disabled = true
			if picked_order.size() == n:
				# Apply new order: the picked order becomes the top of the deck,
				# leaving the rest of the draw pile untouched below it.
				var new_top: Array = []
				for idx in picked_order:
					new_top.append(top_entries[idx])
				for j in range(n):
					_player_draw_pile[j] = new_top[j]
				overlay.queue_free()
		)
		slot.add_child(btn)

	# Same rationale as _show_scry_modal: block until the player finishes
	# reordering, otherwise combat resolves while the modal is still up.
	while is_instance_valid(overlay):
		await get_tree().process_frame


func _show_scry_modal() -> void:
	## Lookout's scry floop: reveal the top of the player's draw pile and let
	## them keep it on top or send it to the bottom. Runs its own input loop
	## (no await needed from the caller — the modal is self-contained).
	if _player_draw_pile.is_empty():
		return
	var top_entry: String = _player_draw_pile[0]
	var top_id: String = _entry_id(top_entry)
	var data: Dictionary = CardDB.get_card_data(top_id)
	if data.is_empty():
		return

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Top of Deck"
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var card_node = CARD_SCENE.instantiate()
	card_node.card_id = top_id
	card_node.card_data = data.duplicate(true)
	card_node.is_on_battlefield = true
	col.add_child(card_node)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 24)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var keep_btn := GameTheme.make_themed_button("Keep on Top",
		Color(0.18, 0.30, 0.14), Vector2(180, 44), 16)
	keep_btn.pressed.connect(func():
		overlay.queue_free()
	)
	btn_row.add_child(keep_btn)

	var bottom_btn := GameTheme.make_themed_button("Send to Bottom",
		Color(0.30, 0.18, 0.14), Vector2(180, 44), 16)
	bottom_btn.pressed.connect(func():
		if not _player_draw_pile.is_empty():
			var t = _player_draw_pile.pop_front()
			_player_draw_pile.append(t)
		overlay.queue_free()
	)
	btn_row.add_child(bottom_btn)

	# Block the caller until the player picks. Without this the floop dispatcher
	# returns immediately and combat resolves behind the modal, so the deck the
	# player is peeking at may already be different by the time they click.
	while is_instance_valid(overlay):
		await get_tree().process_frame


func _show_discover_linked(type_filter: String, rarity_filter: String, linker: Control) -> void:
	## Familiar variant: same as _show_discover, but stores the picked deck_uid
	## on the Familiar so its floop can find and buff the discovered card.
	var uid: int = await _show_discover(type_filter, rarity_filter)
	if uid >= 0 and is_instance_valid(linker):
		linker.set_meta("familiar_pick_uid", uid)


func _show_copy_friendly_picker(source: Control) -> void:
	## Copycat on_enter: player picks which friendly creature to copy. Same
	## fire-and-forget pattern as `_show_discover` — KeywordEffects calls this
	## without awaiting so the on_enter dispatch chain stays sync. If the player
	## cancels (right-click) or no candidates exist, Copycat keeps its base body.
	if not is_instance_valid(source):
		return
	var src: Control = await _pick_friendly_creature(source,
		"Copycat — click a friendly to copy")
	if src == null or not is_instance_valid(src) or not is_instance_valid(source):
		return
	KeywordEffects._copy_creature_onto(source, src.card_data)
	source.update_stat_display()


func _show_keyword_choice(target_card: Control) -> void:
	## Adaptable: modal overlay with 4 keyword buttons. The player's choice is
	## appended to the target card's keywords and a chip is spawned on it.
	if not is_instance_valid(target_card):
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Choose a Keyword"
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var result := {"kw": ""}
	var options := [
		{"key": "swift", "label": "SWIFT", "color": Color(0.22, 0.30, 0.18)},
		{"key": "piercing", "label": "PIERCING", "color": Color(0.30, 0.22, 0.14)},
		{"key": "armored", "label": "ARMORED", "color": Color(0.18, 0.22, 0.30)},
		{"key": "thorns", "label": "THORNS", "color": Color(0.20, 0.30, 0.18)},
	]
	for opt in options:
		var btn := GameTheme.make_themed_button(opt.label, opt.color, Vector2(160, 60), 18)
		btn.pressed.connect(func():
			result["kw"] = opt.key
			overlay.queue_free()
		)
		row.add_child(btn)

	while result["kw"] == "" and is_instance_valid(overlay):
		await get_tree().process_frame

	if result["kw"] != "" and is_instance_valid(target_card):
		var kw: String = result["kw"]
		if kw not in target_card.card_data.keywords:
			target_card.card_data.keywords.append(kw)
		var chip_color := Color(0.85, 0.85, 0.85)
		match kw:
			"swift": chip_color = Color(1.0, 0.85, 0.35)
			"piercing": chip_color = Color(1.0, 0.62, 0.20)
			"armored": chip_color = Color(0.65, 0.85, 1.0)
			"thorns": chip_color = Color(0.55, 0.85, 0.55)
		if target_card.has_method("_spawn_keyword_chip"):
			target_card._spawn_keyword_chip(kw.to_upper(), chip_color)
		target_card.update_stat_display()


func _build_discover_overlay(card_ids: Array) -> String:
	## Modal overlay: dim background + row of 3 large cards + Pick buttons.
	## Returns the chosen card's id (or "" if somehow dismissed).
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.03, 0.04, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # block input behind
	overlay.z_index = 200
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Discover"
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var result := {"id": ""}
	for cid in card_ids:
		# Snapshot `cid` into a local before connecting the lambda. Inline `cid`
		# in a `pressed.connect(func(): ...)` risks closing over the loop
		# variable in pre-4.x GDScript semantics — matching the player's
		# "every pick gives the same card" complaint. Other pickers in this
		# file (e.g. _show_discard_picker line 3560) already use this guard.
		var captured_id: String = cid
		var data := CardDB.get_card_data(cid)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 10)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(slot)

		var card_node = CARD_SCENE.instantiate()
		card_node.card_id = cid
		card_node.card_data = data.duplicate(true)
		card_node.is_on_battlefield = true  # static display, no drag
		slot.add_child(card_node)

		var pick_btn := GameTheme.make_themed_button("Pick",
			Color(0.18, 0.30, 0.14), Vector2(140, 40), 16)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick_btn.pressed.connect(func():
			result["id"] = captured_id
			overlay.queue_free()
		)
		slot.add_child(pick_btn)

	# Wait for the player to click a Pick button (or for the overlay to free).
	while result["id"] == "" and is_instance_valid(overlay):
		await get_tree().process_frame
	return result["id"]


func _add_discovered_card_to_hand(card_id: String) -> int:
	## Drop a discovered card directly into hand so the player can use it THIS
	## turn — the whole point of Discover as a tempo mechanic.
	##
	## Discover is EPHEMERAL: the card lives for this combat only. We don't
	## call RunState.add_card() so the card never enters the run's permanent
	## deck. Previously we did — which made every Lost Tome / War Council /
	## Scholar / Treasure Hunter trigger silently bloat the deck forever, plus
	## broke the discard pile counter (the card showed up in next fight's
	## draw pile out of nowhere). Returns the synthetic deck_uid (negative,
	## reserved for ephemeral cards so it can't collide with real deck uids).
	var data := CardDB.get_card_data(card_id)
	if data.is_empty():
		return -1
	# Negative uids signal "ephemeral, not in RunState.deck." _resolve_card_data
	# already treats uid < 0 as "skip the upgrade lookup, use base card_data."
	_ephemeral_uid_counter -= 1
	var uid: int = _ephemeral_uid_counter
	var card_node = CARD_SCENE.instantiate()
	card_node.card_id = card_id
	card_node.deck_uid = uid
	card_node.card_data = data.duplicate(true)
	card_node.live_baked_mode = true
	_hand_container.add_child(card_node)
	_hand.append(card_node)
	# Hook up the same signals draw_card connects — without these the card
	# sits in the hand but the played/dragging hooks are dead, so the player
	# can't actually use it. It gets swept into discard at end of round and
	# only becomes playable after the discard reshuffle, which was the user-
	# reported "teleports to a weird location, can't use, comes back later"
	# bug.
	card_node.played.connect(_on_card_played.bind(card_node))
	if card_node.is_creature():
		card_node.dragging.connect(_on_card_dragging.bind(card_node))
		card_node.drag_ended.connect(_clear_slot_highlights)
	# Spawn the card at the deck pile and let _layout_hand tween it into the
	# fan, matching how normal draws look.
	if _hand_container != null and _hand_container.global_position != Vector2.ZERO:
		var deck_screen := Vector2(100.0, 311.0)
		card_node.position = deck_screen - _hand_container.global_position - Vector2(96.0, 128.0)
		card_node.scale = Vector2(0.6, 0.6)
	_layout_hand()
	_update_hud()
	return uid


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
	# Idempotent: once we've entered GAME_OVER, ignore further calls so the
	# DEFEAT/VICTORY scene-change timer is never scheduled twice. Needed because
	# damage_enemy_hero / damage_player_hero now call us on every face hit, and
	# the same hit can produce multiple zero-HP events in a single combat phase.
	if phase == Phase.GAME_OVER:
		return
	if player_hp <= 0:
		phase = Phase.GAME_OVER
		_stop_low_hp_dread()  # JUICE: kill the heartbeat/vignette before the defeat sting
		_dbgp("[PACING] FIGHT END | %s | DEFEAT  | ended R%d | P_HP:%d E_HP:%d | intents_shown:%s" % [_encounter_name, round_number, player_hp, enemy_hp, str(_pacing_any_intent_shown)])
		_phase_label.text = "DEFEAT"
		_phase_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
		RunState.hero_hp = 0
		# Record what killed the player for the GameOver recap. Encounter name
		# is the most useful unit of "killed by" — players remember "I died
		# to the Pyre Cult," not "I died to Burning Martyr's on-death."
		RunState.cause_of_death = _encounter_name if _encounter_name != "" else "an unknown foe"
		_presence_say(_pick_bark("slay"), Color(0.95, 0.85, 0.5))   # the foe's parting line
		if AudioBank != null:
			AudioBank.play_sfx("defeat")
		get_tree().create_timer(1.5).timeout.connect(func():
			RunState.end_run(false)
			GameTheme.fade_out_then_change_scene(self, GAMEOVER_SCENE, 0.5)
		)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_stop_low_hp_dread()  # JUICE: clear dread overlay on victory
		_dbgp("[PACING] FIGHT END | %s | VICTORY | ended R%d | P_HP:%d E_HP:%d | intents_shown:%s" % [_encounter_name, round_number, player_hp, enemy_hp, str(_pacing_any_intent_shown)])
		_phase_label.text = "VICTORY!"
		_phase_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
		if AudioBank != null:
			AudioBank.play_sfx("victory")
		RunState.hero_hp = max(player_hp, 1)
		# Run-stat bookkeeping for the GameOver recap.
		RunState.fights_won += 1
		# Successor Wars: every garrison/stronghold that falls counts toward
		# opening the rival lord's keep (RunState.is_lord_gate_open).
		if RunState.current_node_type in ["combat", "elite"]:
			RunState.holds_broken_in_act += 1
		if _mutator_id != "" and not RunState.mutators_survived.has(_mutator_id):
			RunState.mutators_survived.append(_mutator_id)
		# Vulture's Feast
		if _has_relic("vultures_feast"):
			var heal = mini(_friendly_deaths_this_fight, 5)
			RunState.heal_hero(heal)
		# Lich's Bargain: lose 1 HP per friendly death this fight, capped at 3.
		if _has_relic("lichs_bargain"):
			var cost: int = mini(_friendly_deaths_this_fight, 3)
			if cost > 0:
				RunState.damage_hero(cost)
		# Coin Purse
		if _has_relic("coin_purse"):
			RunState.gain_gold(10)
		# Thief's Gloves — "Win taking 0 face damage." Previously compared
		# player_hp to _starting_hp, which Vampire Lord / Mending Light / etc.
		# could mask by healing back to full despite taking real face damage.
		# Use the explicit counter so the relic does what it says.
		if _has_relic("thiefs_gloves") and _face_damage_taken_this_fight == 0:
			RunState.gain_gold(5)
		# Gold reward
		var node_type = RunState.current_node_type
		match node_type:
			"combat": RunState.gain_gold(RunState.roll_gold_reward(30))
			"elite": RunState.gain_gold(RunState.roll_gold_reward(48))
			"boss": RunState.gain_gold(RunState.roll_gold_reward(48))

		if node_type == "boss":
			# Post-boss heal: 75% of missing HP
			var missing = RunState.hero_max_hp - RunState.hero_hp
			RunState.heal_hero(int(missing * 0.75))
			get_tree().create_timer(2.0).timeout.connect(func():
				if RunState.is_final_boss():
					RunState.end_run(true)
					GameTheme.fade_out_then_change_scene(self, GAMEOVER_SCENE, 0.5)
				else:
					# Don't advance_act here — that would clear current_node_type,
					# so Reward would render as a normal fight (wrong card pool,
					# no boss relic offer). Reward handles the act advance after
					# the player finishes picking, on its way back to the map.
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


func _update_intent_display(card: Control, intent: String) -> void:
	## Renders an intent badge above enemies for non-default intents only.
	## ATK damage is already shown by the on-card ATK orb, so we skip it here
	## to avoid the duplicate "⚔ N" chip that overlapped the artwork.
	var lbl: Label = null
	if card.has_meta("intent_label") and is_instance_valid(card.get_meta("intent_label")):
		lbl = card.get_meta("intent_label")
	if intent == "ATK" or intent == "":
		if lbl != null:
			lbl.visible = false
		return
	var label_text: String = intent
	if lbl == null:
		lbl = Label.new()
		# Intent text is the enemy's telegraph — it has to read from across the
		# board. The old 11px bare label vanished against the art on a 1080p
		# capture; a dark pill + 15px caps gives it a nameplate's presence.
		if GameTheme.font_display:
			lbl.add_theme_font_override("font", GameTheme.font_display)
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("outline_size", 4)
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(0.05, 0.04, 0.035, 0.82)
		pill.border_color = Color(0, 0, 0, 0.65)
		for k in ["border_width_top", "border_width_bottom",
				"border_width_left", "border_width_right"]:
			pill.set(k, 1)
		for k in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
			pill.set(k, 9)
		pill.content_margin_left = 8
		pill.content_margin_right = 8
		pill.content_margin_top = 1
		pill.content_margin_bottom = 1
		lbl.add_theme_stylebox_override("normal", pill)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.anchor_left = 0.0
		lbl.anchor_right = 1.0
		lbl.anchor_top = 0.0
		lbl.anchor_bottom = 0.0
		lbl.offset_left = 22
		lbl.offset_right = -22
		lbl.offset_top = -26
		lbl.offset_bottom = -2
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
	lbl.visible = true
	_pacing_any_intent_shown = true


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
			_player_discard_pile.append(CardDB.random_curse_id())
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
		# Climactic banner overlay — the boss phase IS the moment of the run.
		# Banner pulls the existing `transition_msg` as the headline and the
		# new phase's `passive_desc` as the subtitle so the player both feels
		# the beat and reads the new rules in the same overlay.
		var phase_title: String = String(phase_data.get("transition_msg", "PHASE %d" % (new_phase + 1)))
		var phase_subtitle: String = String(phase_data.get("passive_desc", ""))
		# Color ramps as phases escalate: phase 2 amber, phase 3+ crimson.
		var phase_color: Color = Color(1.0, 0.55, 0.30) if new_phase == 1 else Color(1.0, 0.30, 0.25)
		_show_combat_banner(phase_title, phase_subtitle, phase_color)
		screen_shake(15.0)
		screen_flash(Color(phase_color.r, phase_color.g, phase_color.b, 0.30), 0.35)
		presence_phase(phase_color)   # the antagonist leans in; the world tightens
		if AudioBank != null:
			AudioBank.play_sfx("spell_cast", 0.0, 2.0)
		# Also keep the info-label hint for accessibility (some players miss
		# the banner if it overlaps the boss intent reveal).
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
	EncounterEffects.dispatch_reactive(self, trigger, source_card, _lane_idx)


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
				if card.get_meta("temp_poison", false):
					card.card_data.keywords.erase("poison")
					card.remove_meta("temp_poison")
				if card.has_meta("bonus_thorns"):
					card.remove_meta("bonus_thorns")
				# stunned is now on card.state; tick_end_of_round handles it.
				card.state.tick_end_of_round()
				if card.has_meta("redirecting"):
					card.remove_meta("redirecting")
				if card.has_meta("challenge_any_lane"):
					card.remove_meta("challenge_any_lane")
				if card.has_meta("charges_this_turn"):
					card.remove_meta("charges_this_turn")
				if card.has_meta("swap_atk_original"):
					card.current_atk = card.get_meta("swap_atk_original")
					card.remove_meta("swap_atk_original")
					card.update_stat_display()
				if card.has_meta("is_copy"):
					# Doppelganger: restore the original body & abilities the
					# creature had before "become_copy". Snapshot was taken in
					# the floop handler.
					if card.has_meta("become_copy_original"):
						var orig: Dictionary = card.get_meta("become_copy_original")
						card.current_atk = int(orig.get("atk", card.current_atk))
						card.card_data["hp"] = int(orig.get("hp_cap", card.card_data.get("hp", card.current_hp)))
						card.current_hp = mini(int(orig.get("current_hp", card.current_hp)), card.card_data["hp"])
						card.card_data["keywords"] = orig.get("keywords", []).duplicate()
						if orig.get("passive", "") != "":
							card.card_data["passive"] = orig.get("passive", "")
						elif card.card_data.has("passive"):
							card.card_data.erase("passive")
						if orig.get("floop") != null:
							card.card_data["on_play"] = orig.get("floop").duplicate(true)
						card.update_stat_display()
						card.remove_meta("become_copy_original")
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
#  ENCOUNTER SCRIPTS — scripted moments per round (Slay-the-Spire style).
# =====================================================================

func _run_encounter_script(round_num: int) -> void:
	## Iterates the encounter script and fires any entries matching this
	## round. Used by regular fights to inject narrative beats (reinforcements,
	## global buffs, environmental damage) that the player can plan around.
	if _encounter_script.is_empty():
		return
	for entry in _encounter_script:
		if int(entry.get("round", -1)) != round_num:
			continue
		_show_event_banner(entry.get("msg", ""))
		_apply_script_event(entry)


func _apply_script_event(entry: Dictionary) -> void:
	## Resolves a single scripted-event entry. Keep this dispatcher focused —
	## events should be small, telegraphed, and individually understandable.
	match entry.get("event", ""):
		"summon":
			# Drop a thematic creature into the first available enemy slot.
			var card_data: Dictionary = {
				"id": "scripted_%d" % randi(),
				"name": entry.get("name", "Reinforcement"),
				"type": "creature", "cost": 0,
				"atk": int(entry.get("atk", 2)),
				"hp": int(entry.get("hp", 2)),
				"rarity": "enemy",
				"keywords": entry.get("kw", []).duplicate() if entry.has("kw") else [],
				"desc": "",
			}
			# Try front row first, then back; abort if board is full.
			for row in [ROW_FRONT, ROW_BACK]:
				var arr = _row_array(true, row)
				for lane in range(LANES_PER_ROW):
					if arr[lane] == null:
						_place_enemy_card(card_data, lane, row)
						return
		"buff_all_atk":
			var v: int = int(entry.get("value", 1))
			for c in _all_enemy_creatures():
				c.current_atk += v
				c.update_stat_display()
		"buff_all_hp":
			var v: int = int(entry.get("value", 1))
			for c in _all_enemy_creatures():
				c.card_data.hp += v
				c.current_hp += v
				c.update_stat_display()
		"grant_keyword_all":
			var kw: String = entry.get("keyword", "")
			if kw == "":
				return
			for c in _all_enemy_creatures():
				var keys = c.card_data.get("keywords", [])
				if kw not in keys:
					keys.append(kw)
					c.card_data["keywords"] = keys
		"face_damage":
			damage_player_hero(int(entry.get("value", 1)))
		"heal_all":
			var v: int = int(entry.get("value", 1))
			for c in _all_enemy_creatures():
				c.current_hp = mini(c.current_hp + v, c.card_data.hp)
				c.update_stat_display()


func _show_event_banner(msg: String) -> void:
	## Brief banner in the center of the screen announcing a scripted event.
	## Auto-dismisses; non-blocking so the round flow can continue.
	if msg == "":
		return
	var banner := Label.new()
	banner.text = msg
	banner.add_theme_font_override("font", GameTheme.font_display)
	banner.add_theme_font_size_override("font_size", 38)
	banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	banner.add_theme_constant_override("outline_size", 6)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 100
	add_child(banner)
	var tween = create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.25).from(0.0)
	tween.tween_interval(1.6)
	tween.tween_property(banner, "modulate:a", 0.0, 0.4)
	tween.tween_callback(banner.queue_free)


# =====================================================================
#  ENCOUNTER PASSIVES
# =====================================================================

func _dispatch_passive_start_of_round() -> void:
	EncounterEffects.dispatch_passive_start_of_round(self)
	# THE BELLRINGER boss (Act 2). Its doom_bell passive lives here rather than
	# in EncounterEffects so the whole signature — the toll cadence, the host
	# buff, the deploy — sits in one readable place alongside the combat helpers
	# (_find_empty_enemy_slot / _place_enemy_card / _show_combat_banner) it
	# reuses. Runs AFTER KeywordEffects.dispatch_start_of_round (which ticks the
	# existing Doomspawn countdowns), so a freshly-tolled bomb starts its clock
	# clean this round instead of losing a tick the instant it lands.
	if _encounter_passive == "doom_bell":
		_doom_bell_start_of_round()


func _dispatch_passive_end_of_round() -> void:
	EncounterEffects.dispatch_passive_end_of_round(self)


# ── THE BELLRINGER — doom_bell signature ─────────────────────────────────────
# A telegraphed doomsday clock built on the `doom` keyword. Every other round
# the bell TOLLS and deploys a "Cinder" bomb-creature (Doom 2) into an empty
# enemy lane; its on-board countdown ticks 2 → 1 → DETONATE (face damage via the
# canonical KeywordEffects doom path). The player must triage and kill it in
# time. The "ignoring it is costly" lever: while ANY Doomspawn is still ticking,
# every other enemy creature swings +1 ATK this round (the toll empowers the
# host). Round 6 cracks the bell — a DOUBLE peal drops two bombs at once.
func _doom_bell_start_of_round() -> void:
	# Setup round is combat-free; the first toll lands going into round 2.
	if round_number < 2:
		return
	# Host buff: if a bomb is currently ticking on the board, the Bellringer's
	# standing creatures hit harder this round. temp_atk_buff (cleared each
	# round) keeps it a per-round pressure beat, not permanent snowball.
	var has_live_bomb := false
	for c in _all_enemy_creatures():
		if c.has_keyword("doom"):
			has_live_bomb = true
			break
	if has_live_bomb:
		for c in _all_enemy_creatures():
			if not c.has_keyword("doom"):
				c.temp_atk_buff += 1
				c.update_stat_display()
	# Toll cadence: every other round (2, 4, 6, …). Round 6 is the cracked
	# double peal. Skip the toll if the board is full — no empty lane to drop
	# a bomb into — so it never silently no-ops mid-swarm.
	if round_number % 2 != 0:
		return
	var peals: int = 2 if round_number >= 6 else 1
	var tolled := false
	for _i in range(peals):
		var slot := _find_empty_enemy_slot()
		if slot.is_empty():
			break
		var bomb := {
			"id": "doom_bell_%d" % randi(),
			"name": "Cinder",  # reuses the torchbearer art alias (a walking fuse)
			"type": "creature", "cost": 0,
			"atk": 2, "hp": 3, "rarity": "enemy",
			"keywords": ["doom"], "doom": 2, "doom_damage": 6,
			"desc": "",
		}
		_place_enemy_card(bomb, slot.lane, slot.row)
		tolled = true
	if tolled:
		var subtitle := "Two fuses are lit." if peals >= 2 else "A fuse is lit — kill it before it blows."
		_show_combat_banner("☼ THE BELL TOLLS ☼", subtitle, Color(1.0, 0.42, 0.16))
		screen_shake(8.0)
		if AudioBank != null:
			AudioBank.play_sfx("hit_hero")


# =====================================================================
#  MUTATORS — per-fight modifiers attached to map nodes
# =====================================================================

func _init_mutator_state() -> void:
	# Reads RunState.current_mutator_id and caches the per-hook effect dicts
	# into typed combat fields. Hooks below read those fields directly so
	# combat code stays branch-light at the call site.
	_mutator_id = RunState.current_mutator_id
	if _mutator_id == "" or not MutatorDB.exists(_mutator_id):
		_mutator_id = ""
		_mutator_data = {}
		return
	_mutator_data = MutatorDB.get_mutator(_mutator_id)
	# on_enemy_enter: grant keyword OR stat buff to every enemy placed.
	var e_enter: Dictionary = _mutator_data.get("on_enemy_enter", {})
	match String(e_enter.get("kind", "")):
		"grant_keyword":
			_mutator_enemy_keyword = String(e_enter.get("value", ""))
		"buff_atk":
			_mutator_enemy_atk_buff = int(e_enter.get("value", 0))
		"buff_hp":
			_mutator_enemy_hp_buff = int(e_enter.get("value", 0))
		"grant_doom":
			# "Doomed" — front-row enemies enter as ticking bombs (handled in
			# _mutator_apply_to_enemy so back-row queue creatures stay clean).
			_mutator_enemy_doom = int(e_enter.get("value", 0))
		"buff_hp_regen":
			# "Overgrown" — +N HP AND Regenerate on every enemy.
			_mutator_enemy_regen_hp = int(e_enter.get("value", 0))
	# on_player_creature_enter: grant keyword OR weaken HP on player plays.
	var p_enter: Dictionary = _mutator_data.get("on_player_creature_enter", {})
	match String(p_enter.get("kind", "")):
		"grant_player_keyword":
			_mutator_player_keyword = String(p_enter.get("value", ""))
		"weaken_player_creature_hp":
			_mutator_weaken_player_hp = int(p_enter.get("value", 0))
	# on_round_start: most commonly per-round chip damage on the front row.
	var r_start: Dictionary = _mutator_data.get("on_round_start", {})
	if String(r_start.get("kind", "")) == "damage_player_front":
		_mutator_burn_per_round = int(r_start.get("value", 0))
	# on_combat_start: one-shot adjustments to combat globals.
	var c_start: Dictionary = _mutator_data.get("on_combat_start", {})
	match String(c_start.get("kind", "")):
		"spell_cost_increase":
			_mutator_spell_cost_increase = int(c_start.get("value", 0))
		"hand_draw_reduce":
			_mutator_hand_draw_reduce = int(c_start.get("value", 0))
		"hand_draw_increase":
			_mutator_hand_draw_increase = int(c_start.get("value", 0))
		"max_mana_increase":
			_mutator_max_mana_increase = int(c_start.get("value", 0))
		"enemy_double_on_death":
			_mutator_double_enemy_on_death = true
		"damage_player_now":
			# "Scarred" — apply a one-shot HP haircut RIGHT NOW so the fight
			# opens with the player visibly battered. Floor at 1 so it can
			# never instantly kill on entry. Propagates to RunState so the
			# damage persists past combat (the price of taking the fight).
			_mutator_scarred_dmg = int(c_start.get("value", 0))
			if _mutator_scarred_dmg > 0:
				var new_hp: int = maxi(1, player_hp - _mutator_scarred_dmg)
				var actual: int = player_hp - new_hp
				player_hp = new_hp
				RunState.hero_hp = maxi(1, RunState.hero_hp - actual)


func _mutator_apply_to_enemy(card: Control) -> void:
	# Called from _place_enemy_card for every enemy creature placed (initial
	# lineup, reinforcement, encounter scripts). No-ops when no mutator.
	if _mutator_id == "":
		return
	if _mutator_enemy_keyword != "" and not card.has_keyword(_mutator_enemy_keyword):
		card.card_data.keywords.append(_mutator_enemy_keyword)
	if _mutator_enemy_atk_buff != 0:
		card.current_atk = maxi(0, card.current_atk + _mutator_enemy_atk_buff)
	if _mutator_enemy_hp_buff != 0:
		card.current_hp += _mutator_enemy_hp_buff
		card.card_data.hp = int(card.card_data.get("hp", 1)) + _mutator_enemy_hp_buff
	# "Overgrown": +N HP and Regenerate on every enemy. Stacks on top of the
	# card's own keywords; the start-of-round Regenerate tick heals it back up.
	if _mutator_enemy_regen_hp > 0:
		card.current_hp += _mutator_enemy_regen_hp
		card.card_data.hp = int(card.card_data.get("hp", 1)) + _mutator_enemy_regen_hp
		if not card.has_keyword("regenerate"):
			card.card_data.keywords.append("regenerate")
	# "Doomed": only FRONT-row enemies become ticking bombs. Seed the doom keyword
	# + counter + a fixed detonation value so it reads the same as a real Doom
	# creature; the canonical dispatch_start_of_round tick + _detonate_doom path
	# handles the countdown and explosion. Skip if it's already a Doom creature.
	if _mutator_enemy_doom > 0 and card.current_row == ROW_FRONT and not card.has_keyword("doom"):
		card.card_data.keywords.append("doom")
		card.card_data["doom"] = _mutator_enemy_doom
		if not card.card_data.has("doom_damage"):
			card.card_data["doom_damage"] = maxi(1, card.current_atk)
		if card.has_method("_ensure_doom_init"):
			card._ensure_doom_init()
		if card.has_method("update_doom_display"):
			card.update_doom_display()


func _mutator_apply_to_player_creature(card: Control) -> void:
	# Called from _play_creature after the card has landed in its slot.
	if _mutator_id == "":
		return
	if _mutator_player_keyword != "" and not card.has_keyword(_mutator_player_keyword):
		card.card_data.keywords.append(_mutator_player_keyword)
	if _mutator_weaken_player_hp > 0:
		var new_hp: int = maxi(1, card.current_hp - _mutator_weaken_player_hp)
		card.current_hp = new_hp


func _mutator_round_start_tick() -> void:
	# Called from _start_round AFTER the standard round-start tasks. Currently
	# only "burning" uses this; future round-start mutators slot in here.
	if _mutator_id == "" or _mutator_burn_per_round <= 0:
		return
	for lane in range(LANES_PER_ROW):
		var card = _player_field[lane]
		if card != null and is_instance_valid(card) and card.current_hp > 0:
			card.take_damage_bypass_armor(_mutator_burn_per_round)


func has_mutator() -> bool:
	return _mutator_id != ""


func mutator_doubles_enemy_on_death() -> bool:
	# Exposed for KeywordEffects.dispatch_on_death so the "Frenzied" mutator
	# can amplify enemy on-death effects without needing a sentinel passive.
	return _mutator_double_enemy_on_death


# =====================================================================
#  STRUCTURES — Pyres, Mausoleums, Altars, etc.
# =====================================================================
##
## Structures are unattackable board objects placed in enemy back-row lanes
## at fight setup. They carry a `charge` counter visible above the card and
## drive the encounter's signature ritual mechanic (ignition, summon, etc.).
##
## Encounter data declares them in the optional `structures` field:
##   "structures": [
##     {"name": "Pyre", "atk": 0, "hp": 99, "kw": ["structure"],
##      "charge_max": 3, "lane": 0},
##   ]
##
## The "structure" keyword wires:
##   • Card2D.can_attack() → false (structures never swing)
##   • Combat attack resolution → bypasses structure back-row slots
##   • Spell targeting → strips structures from valid lists
## The charge counter is displayed via the existing intent badge so it sits
## above the card like other enemy intents and stays readable at the
## battlefield's compact scale.

func _spawn_encounter_structures(enc: Dictionary) -> void:
	var structures: Array = enc.get("structures", [])
	if structures.is_empty():
		return
	for s in structures:
		var lane: int = int(s.get("lane", 0))
		if lane < 0 or lane >= LANES_PER_ROW:
			continue
		if _enemy_back[lane] != null:
			continue
		# Build a real card_data dict so the rest of combat (display, dispatch,
		# death) treats this exactly like a normal creature. The structure
		# keyword + charge fields are what differentiate it.
		var data: Dictionary = EncounterDB.make_card_data(s)
		data["charge_current"] = int(s.get("charge_current", 0))
		data["charge_max"] = int(s.get("charge_max", 3))
		_place_enemy_card(data, lane, ROW_BACK)
		# Refresh the intent badge so the charge counter shows up immediately
		# instead of waiting for the first intent-assignment pass.
		var card = _enemy_back[lane]
		if card != null and is_instance_valid(card):
			_refresh_structure_charge_label(card)


func _refresh_structure_charge_label(card: Control) -> void:
	# Repurposes the intent badge above the card to show "CHARGE n/max".
	# Goes through _update_intent_display so colors/positioning match other
	# intents without duplicating the label-build code.
	if card == null or not is_instance_valid(card):
		return
	if not card.has_keyword("structure"):
		return
	var cur: int = int(card.card_data.get("charge_current", 0))
	var max_c: int = int(card.card_data.get("charge_max", 3))
	_update_intent_display(card, "CHARGE %d/%d" % [cur, max_c])


func _add_structure_charge(card: Control, amount: int) -> void:
	# Increments the charge on a structure and refreshes its badge. Triggers
	# the encounter's signature climax (ignition) when the counter crosses
	# the threshold; the climax itself is dispatched at start of round so
	# the player sees the build-up land in a single beat rather than mid-attack.
	if card == null or not is_instance_valid(card):
		return
	if not card.has_keyword("structure"):
		return
	var cur: int = int(card.card_data.get("charge_current", 0)) + amount
	var max_c: int = int(card.card_data.get("charge_max", 3))
	card.card_data["charge_current"] = cur
	_refresh_structure_charge_label(card)
	# Visual feedback for the feed — small floating chip so the player sees
	# the structure react instantly.
	if amount > 0:
		var anchor = card.global_position + card.size * card.scale * 0.5
		spawn_floating_number(anchor, "+%d CHARGE" % amount, Color(1.0, 0.62, 0.20), false)
	# When the threshold is crossed, mark the structure as ready to fire;
	# the actual fire happens at start of next round (telegraphed ignition).
	if cur >= max_c:
		card.set_meta("ready_to_ignite", true)


func _all_structures() -> Array:
	# Walks both rows for both sides and returns every live structure card.
	# Currently only enemy back row holds structures, but the iteration covers
	# everything so a future "player builds an altar" doesn't need a rewrite.
	var out: Array = []
	for row in [ROW_FRONT, ROW_BACK]:
		for arr in [_row_array(true, row), _row_array(false, row)]:
			for c in arr:
				if c != null and is_instance_valid(c) and c.has_keyword("structure"):
					out.append(c)
	return out


func _fire_pyre_ignition(pyre: Control) -> void:
	# THE climax. Big banner, screen pulse, AoE damage to every creature NOT
	# in a lane adjacent to a Pyre. Resets the Pyre's charge so the ritual
	# can re-build (though most fights end before this matters).
	if pyre == null or not is_instance_valid(pyre):
		return
	var pyre_lane: int = pyre.current_lane
	# Banner — reuses _show_encounter_intro's overlay style for the climax.
	_show_combat_banner("★ IGNITION ★", "The bonfire roars.", Color(1.0, 0.45, 0.18))
	# Particle burst at the Pyre.
	var burst_pos: Vector2 = pyre.global_position + pyre.size * pyre.scale * 0.5
	spawn_spell_burst(burst_pos, Color(1.0, 0.50, 0.15, 0.95))
	screen_shake(15.0)
	screen_flash(Color(1.0, 0.45, 0.18, 0.35), 0.3)
	if AudioBank != null:
		AudioBank.play_sfx("spell_cast", 0.0, 2.0)
	# Find which lanes are "adjacent to a Pyre" — pyre's own lane plus the
	# columns immediately to either side. Creatures in any of these lanes
	# survive the ignition.
	var safe_lanes: Array[int] = []
	for s in _all_structures():
		var sl: int = s.current_lane
		safe_lanes.append(sl)
		if sl > 0:
			safe_lanes.append(sl - 1)
		if sl < LANES_PER_ROW - 1:
			safe_lanes.append(sl + 1)
	# Damage every creature not in a safe lane. Use take_damage_bypass_armor
	# so Armored doesn't reduce the ritual (the fire is supernatural). Hits
	# both sides — even enemies that clustered away from the Pyre burn.
	for c in _all_creatures_both_sides():
		if c == null or not is_instance_valid(c):
			continue
		if c.has_keyword("structure"):
			continue
		if c.current_lane in safe_lanes:
			continue
		c.take_damage_bypass_armor(4)
	# Player face damage on top of board damage.
	damage_player_hero(3)
	# Reset the Pyre so the ritual can build again.
	pyre.card_data["charge_current"] = 0
	pyre.remove_meta("ready_to_ignite")
	_refresh_structure_charge_label(pyre)


func _fire_trebuchet_strike(trebuchet: Control) -> void:
	# Iron Warden climax. Bigger boom than the Pyre — this is artillery,
	# not ambient fire. Hits EVERY player creature (no adjacency mercy)
	# for 3 and chunks 4 face damage. Resets the Trebuchet so phase 1
	# can fire it again if the player stalls (rare in practice — phase 2
	# usually arrives first).
	if trebuchet == null or not is_instance_valid(trebuchet):
		return
	_show_combat_banner("★ TREBUCHET FIRES ★",
		"Stones rain from the keep.", Color(0.75, 0.65, 0.45))
	var burst_pos: Vector2 = trebuchet.global_position + trebuchet.size * trebuchet.scale * 0.5
	spawn_spell_burst(burst_pos, Color(0.95, 0.85, 0.55, 0.95))
	screen_shake(18.0)
	screen_flash(Color(0.95, 0.85, 0.55, 0.30), 0.32)
	if AudioBank != null:
		AudioBank.play_sfx("spell_cast", 0.0, 2.0)
	# Hit every player creature in both rows for 3.
	for c in _all_player_creatures():
		if c != null and is_instance_valid(c) and c.current_hp > 0:
			c.take_damage_bypass_armor(3)
	# Plus chunky face damage.
	damage_player_hero(4)
	trebuchet.card_data["charge_current"] = 0
	trebuchet.remove_meta("ready_to_ignite")
	_refresh_structure_charge_label(trebuchet)


func _cauldron_brew_tick() -> void:
	# Crone's Cauldron — every round, +1 charge AND one curse into discard
	# (combining the original crone_drip behavior into the structure beat
	# so there's one legible threat instead of two parallel ones). At
	# Charge 5 the Cauldron OVERFLOWS: 3 face damage, a Wraith summon in
	# a random empty lane, and 2 extra curses dumped into discard.
	var cauldron: Control = null
	for s in _all_structures():
		if String(s.card_data.get("name", "")) == "Cauldron":
			cauldron = s
			break
	if cauldron == null:
		return
	# Skip round 1 — give the player a beat to read the board first.
	if round_number <= 1:
		return
	# The drip happens every round regardless of climax — that's the boss's
	# baseline pressure. The structure climax adds the dramatic moment on top.
	_player_discard_pile.append(CardDB.random_curse_id())
	_add_structure_charge(cauldron, 1)
	if cauldron.get_meta("ready_to_ignite", false):
		_show_combat_banner("★ THE CAULDRON OVERFLOWS ★",
			"Hex-smoke fills the room.", Color(0.55, 0.18, 0.75))
		var burst_pos: Vector2 = cauldron.global_position + cauldron.size * cauldron.scale * 0.5
		spawn_spell_burst(burst_pos, Color(0.78, 0.30, 0.95, 0.95))
		screen_shake(14.0)
		screen_flash(Color(0.55, 0.18, 0.75, 0.32), 0.32)
		# Summon a Wraith in any empty front lane.
		var wraith_lane: int = -1
		for l in range(LANES_PER_ROW):
			if _enemy_field[l] == null:
				wraith_lane = l
				break
		if wraith_lane >= 0:
			var wraith: Dictionary = EncounterDB.make_card_data({
				"name": "Wraith", "atk": 3, "hp": 3, "kw": ["swift"],
			})
			_place_enemy_card(wraith, wraith_lane, ROW_FRONT)
		# Two more curses on top of the regular drip + face damage.
		_player_discard_pile.append(CardDB.random_curse_id())
		_player_discard_pile.append(CardDB.random_curse_id())
		damage_player_hero(3)
		cauldron.card_data["charge_current"] = 0
		cauldron.remove_meta("ready_to_ignite")
		_refresh_structure_charge_label(cauldron)


func _rise_from_mausoleum(mausoleum: Control) -> void:
	# Haunted Crypt climax. The Mausoleum cracks open and the Lich rises in
	# its lane — same column, but the structure is replaced by a real
	# combatant. The Lich is the fight's true threat; killing it (or holding
	# it off) is the win condition for this run-through of the encounter.
	if mausoleum == null or not is_instance_valid(mausoleum):
		return
	var lane: int = mausoleum.current_lane
	_show_combat_banner("★ THE LICH RISES ★",
		"The mausoleum cracks open.", Color(0.55, 0.95, 0.65))
	var burst_pos: Vector2 = mausoleum.global_position + mausoleum.size * mausoleum.scale * 0.5
	spawn_spell_burst(burst_pos, Color(0.55, 0.95, 0.65, 0.95))
	screen_shake(12.0)
	screen_flash(Color(0.40, 0.85, 0.55, 0.28), 0.3)
	if AudioBank != null:
		AudioBank.play_sfx("spell_cast", 0.0, 2.0)
	# Remove the structure cleanly. Card2D._die() handles the visual exit
	# (fade + ash burst); the field array is cleared on the destroyed signal.
	_enemy_back[lane] = null
	mausoleum.queue_free()
	# Spawn the Lich in the same lane. 6/6 piercing means the player can't
	# just stall; they need to kill it before it dismantles their board.
	var lich_data: Dictionary = EncounterDB.make_card_data({
		"name": "The Lich", "atk": 6, "hp": 6,
		"kw": ["piercing"],
		"on_death": {"type": "damage_face", "value": 4},
	})
	_place_enemy_card(lich_data, lane, ROW_BACK)


func _cultist_altar_tick() -> void:
	# Cultist Enclave start-of-round: the lowest-HP cultist offers itself to
	# the Altar, adding +1 charge. At charge 3 the Altar climaxes: summon a
	# Cultist Champion AND deal 3 face damage. The sacrificed creature dies
	# and triggers its on-death normally (e.g. Bleeding Heart still bombs).
	var altar: Control = null
	for s in _all_structures():
		if String(s.card_data.get("name", "")) == "Altar":
			altar = s
			break
	if altar == null:
		return
	# Pick the lowest-HP non-structure cultist. Skip the very first round so
	# the player gets a beat to read the board before the ritual starts.
	if round_number <= 1:
		return
	var victim: Control = null
	var lowest_hp: int = 99
	for c in _all_enemy_creatures():
		if c == null or not is_instance_valid(c):
			continue
		if c.has_keyword("structure"):
			continue
		if c.current_hp > 0 and c.current_hp < lowest_hp:
			lowest_hp = c.current_hp
			victim = c
	if victim != null:
		# Visual: the cultist marches to the Altar before dying.
		spawn_floating_number(
			victim.global_position + victim.size * victim.scale * 0.5,
			"SACRIFICED", Color(0.95, 0.40, 0.30), false)
		victim.take_damage_bypass_armor(99)  # the ritual kills outright
		_add_structure_charge(altar, 1)
	# If the Altar crossed threshold, fire the climax.
	if altar.get_meta("ready_to_ignite", false):
		_show_combat_banner("★ CHAMPION SUMMONED ★",
			"The Altar drinks deep.", Color(0.85, 0.30, 0.95))
		var burst_pos: Vector2 = altar.global_position + altar.size * altar.scale * 0.5
		spawn_spell_burst(burst_pos, Color(0.85, 0.30, 0.95, 0.95))
		screen_shake(12.0)
		screen_flash(Color(0.55, 0.18, 0.75, 0.30), 0.3)
		# Summon the Champion in an empty front lane.
		var champion: Dictionary = EncounterDB.make_card_data({
			"name": "Cultist Champion", "atk": 5, "hp": 6,
			"kw": ["piercing"],
			"on_enter": {"type": "damage_face", "value": 2},
		})
		var spawn_lane: int = -1
		for l in range(LANES_PER_ROW):
			if _enemy_field[l] == null:
				spawn_lane = l
				break
		if spawn_lane >= 0:
			_place_enemy_card(champion, spawn_lane, ROW_FRONT)
		else:
			# All front lanes occupied — fire face damage as a consolation
			# climax instead of swallowing the summon silently.
			damage_player_hero(5)
		damage_player_hero(3)
		altar.card_data["charge_current"] = 0
		altar.remove_meta("ready_to_ignite")
		_refresh_structure_charge_label(altar)


func _show_combat_banner(title: String, subtitle: String, color: Color) -> void:
	# Mid-fight banner overlay for climactic moments (Ignition, Lich Rises,
	# Altar Awakens). Smaller and shorter than the encounter intro banner.
	if _hud_layer == null:
		return
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 240
	holder.modulate.a = 0.0
	_hud_layer.add_child(holder)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 64)
	title_lbl.add_theme_color_override("font_color", color)
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title_lbl.add_theme_constant_override("outline_size", 8)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(title_lbl)

	if subtitle != "":
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.add_theme_font_size_override("font_size", 20)
		sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.65))
		sub_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		sub_lbl.add_theme_constant_override("outline_size", 5)
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(sub_lbl)

	var tw := holder.create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.18)
	tw.tween_interval(0.7)
	tw.tween_property(holder, "modulate:a", 0.0, 0.35)
	tw.tween_callback(holder.queue_free)


func mutator_gold_bonus() -> int:
	# Public for Reward.gd: how much extra gold this fight pays out because the
	# player took on a mutator. Returns 0 when no mutator was active.
	if _mutator_id == "":
		return 0
	return int(_mutator_data.get("gold_bonus", 0))




func _dispatch_encounter_on_enemy_death(lane_idx: int, dead_card: Control = null) -> void:
	EncounterEffects.dispatch_encounter_on_enemy_death(self, lane_idx, dead_card)


func _dispatch_encounter_on_player_death(_lane_idx: int) -> void:
	EncounterEffects.dispatch_encounter_on_player_death(self, _lane_idx)


func _dispatch_encounter_on_enter(_data: Dictionary, _lane_idx: int) -> void:
	EncounterEffects.dispatch_encounter_on_enter(self, _data, _lane_idx)


func _has_encounter_passive_keyword(card: Control, keyword: String) -> bool:
	return EncounterEffects.has_encounter_passive_keyword(self, card, keyword)


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


# The player creature currently flagged as the start-of-round passive's victim,
# so we can clear the old flag before moving it elsewhere.
var _passive_threat_marked: Control = null

func _refresh_passive_threat_glow() -> void:
	# Glow the player creature the boss's start-of-round passive will snipe, using
	# the SAME picker the passive itself calls (_highest_atk_player_creature), so
	# the warning can never disagree with what actually happens. Presentation only
	# — nothing here mutates the board.
	var target: Control = null
	if _encounter_passive == "hollow_king_snipe" or _encounter_passive == "hollow_king_phase2":
		target = _highest_atk_player_creature()
	if target == _passive_threat_marked:
		return
	if _passive_threat_marked != null and is_instance_valid(_passive_threat_marked):
		_passive_threat_marked.set_danger_marked(false)
	_passive_threat_marked = target
	if target != null and is_instance_valid(target):
		target.set_danger_marked(true, 3)


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


func _summon_one_soldier(atk: int, hp: int) -> void:
	# Summon one player token into the first empty lane (front preferred). Board
	# presence in place of card draw (Provision / War Chant) under persistent hand.
	var slot := _pick_empty_for_summon(false, ROW_FRONT)
	if not slot.is_empty():
		summon_token(atk, hp, slot.lane, false, slot.row)


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
	#   │                 в””в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”  [End Turn]    │
	#   ├────── HUD strip (HP, mana, deck/discard) anchored above hand ───────┤
	#   └────── hand container (anchored to bottom edge, fixed height) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”
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
	# Symmetric about screen centre (x=800) so the fan aligns with the board's
	# central lane / clash line instead of drifting right. Left (360) clears the
	# mana orb (ends x=354); right (1240) clears the end-turn stack (starts 1420).
	_hand_container.offset_left = 360
	_hand_container.offset_right = -360
	_hand_container.anchor_top = 1.0
	_hand_container.anchor_bottom = 1.0
	# Hand sits on top of the board's bottom edge (board_zone goes down to
	# offset_bottom = -150; the player back row ends at y=737). REST_SCALE/PEEK
	# in _layout_hand seat resting cards just below y=737 so they don't cover
	# back-row creature stats; hovered cards lift up over the board's
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
	board_zone.offset_left = 272
	board_zone.offset_right = -272
	board_zone.offset_top = 70
	board_zone.offset_bottom = -150
	board_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_container.add_child(board_zone)

	# ── Board substrate ─────────────────────────────────────────────────────
	# A near-opaque dark plate behind the lanes. THIS is the figure/ground fix:
	# the painted hellscape is loud and shares the cards' own red/orange palette,
	# so the old translucent 0.40-alpha "mat" let it read straight through and the
	# board never separated from the background. An opaque dark substrate turns
	# the play area into its own surface; the warm stage glow below re-lights its
	# centre, and the external vignette pulls the surrounding art into shadow.
	var substrate := Panel.new()
	substrate.set_anchors_preset(Control.PRESET_FULL_RECT)
	substrate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub_style := StyleBoxFlat.new()
	sub_style.bg_color = Color(0.05, 0.038, 0.032, 0.85)
	sub_style.border_color = Color(0.0, 0.0, 0.0, 0.45)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		sub_style.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		sub_style.set(k, 16)
	sub_style.shadow_color = Color(0, 0, 0, 0.55)
	sub_style.shadow_size = 18
	substrate.add_theme_stylebox_override("panel", sub_style)
	board_zone.add_child(substrate)

	# Warm stage glow ON the substrate (additive, above the dark plate but below
	# the lanes/cards) so the centre of the table is lit and the eye lands on the
	# board first. Self-contained here rather than relying on the global ambient
	# stage-light, which draws BELOW the board container and is hidden by the
	# opaque substrate.
	var bglow_grad := Gradient.new()
	bglow_grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	bglow_grad.colors = PackedColorArray([
		Color(1.0, 0.66, 0.34, 0.30),
		Color(1.0, 0.50, 0.22, 0.12),
		Color(1.0, 0.40, 0.16, 0.0)])
	var bglow_tex := GradientTexture2D.new()
	bglow_tex.gradient = bglow_grad
	bglow_tex.fill = GradientTexture2D.FILL_RADIAL
	bglow_tex.fill_from = Vector2(0.5, 0.5)
	bglow_tex.fill_to = Vector2(1.0, 0.5)
	bglow_tex.width = 256
	bglow_tex.height = 256
	var bglow := TextureRect.new()
	bglow.texture = bglow_tex
	bglow.stretch_mode = TextureRect.STRETCH_SCALE
	bglow.set_anchors_preset(Control.PRESET_FULL_RECT)
	bglow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bglow_mat := CanvasItemMaterial.new()
	bglow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bglow.material = bglow_mat
	board_zone.add_child(bglow)

	# ── Lane duel-columns ────────────────────────────────────────────────────
	# This is a lane-combat game: the unit of play is the vertical column — your
	# creature faces the enemy's directly across the clash line, with each side's
	# back row queued behind. So the board is built as 4 vertical lane tracks, NOT
	# stacked rows. Each track holds, top→bottom: enemy back, enemy front,
	# <clash gap>, player front, player back. The persistent track panel is the
	# column the player reads even when sockets are empty; ownership (warm enemy /
	# cool player) lives on the sockets, the lane itself stays neutral.
	const LANE_GUTTER := 16
	const CLASH_GAP := 30
	var lanes_row := HBoxContainer.new()
	lanes_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	lanes_row.add_theme_constant_override("separation", LANE_GUTTER)
	lanes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lanes_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_zone.add_child(lanes_row)

	for i in range(LANES_PER_ROW):
		var track := PanelContainer.new()
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_FILL
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track_style := StyleBoxFlat.new()
		track_style.bg_color = Color(0.015, 0.012, 0.01, 0.34)
		track_style.border_color = Color(GILT.r, GILT.g, GILT.b, 0.08)
		for k in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
			track_style.set(k, 1)
		for k in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
			track_style.set(k, 10)
		track.add_theme_stylebox_override("panel", track_style)
		lanes_row.add_child(track)

		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(col)

		var e_back := _make_lane_slot(true, i, ROW_BACK)
		col.add_child(e_back)
		_enemy_back_slots.append(e_back)
		var e_front := _make_lane_slot(true, i, ROW_FRONT)
		col.add_child(e_front)
		_enemy_slots.append(e_front)

		# Clash gap — the empty band the front rows fight across. The full-width
		# clash seam (built below) lands here.
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, CLASH_GAP)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(gap)

		var p_front := _make_lane_slot(false, i, ROW_FRONT)
		col.add_child(p_front)
		_player_slots.append(p_front)
		var p_back := _make_lane_slot(false, i, ROW_BACK)
		col.add_child(p_back)
		_player_back_slots.append(p_back)

	# ── Clash line ───────────────────────────────────────────────────────────
	# The front line where combat resolves, drawn full-width across the centre
	# (lands in each column's CLASH_GAP). A crisp lit gilt seam, not the old 44px
	# walnut beam that ate vertical space. It only crosses the empty gap between
	# the front rows, so it never overlaps a card.
	_midline = Panel.new()
	_midline.anchor_left = 0.0
	_midline.anchor_right = 1.0
	_midline.anchor_top = 0.5
	_midline.anchor_bottom = 0.5
	_midline.offset_top = -2
	_midline.offset_bottom = 2
	_midline.offset_left = -8
	_midline.offset_right = 8
	_midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var beam_style := StyleBoxFlat.new()
	beam_style.bg_color = Color(GILT.r, GILT.g, GILT.b, 0.55)
	beam_style.shadow_color = Color(1.0, 0.6, 0.25, 0.35)
	beam_style.shadow_size = 10
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		beam_style.set(k, 2)
	_midline.add_theme_stylebox_override("panel", beam_style)
	board_zone.add_child(_midline)


func _build_portrait_columns() -> void:
	# STS-style anchor: a vertical sliver on the far-left edge carries the
	# player and enemy hero portraits. Both placed against the corresponding
	# half of the board so the eye reads "me vs them" instantly.
	# Enemy side: the Living Antagonist (looming, lit, reactive) instead of the
	# old "FOE" disc. The player keeps the compact disc — the drama belongs to
	# the foe across the table.
	_build_enemy_presence()

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


# ═══════════════════════════════════════════════════════════════════════════
#  LIVING ANTAGONIST — enemy presence + reactions + barks
# ═══════════════════════════════════════════════════════════════════════════
#
# Atmosphere = presence + reaction, not decoration. The encounter's signature
# creature looms on the left of the enemy half — lit by the board glow, emerging
# from a dark pocket (Inscryption dread + Slay-the-Spire presence). It flinches
# and reddens when the foe-hero is hurt, surges when it hits you, leans in while
# the world tightens on a boss phase shift, and SPEAKS short barks on entry /
# pain / phase / your death (Darkest-Dungeon / Inscryption voice).

const PRESENCE_ART_ALIAS := {
	"alpha": "wolf_c", "den_mother": "wolf_c", "chief": "goblin",
	"elder_drake": "e_elder_dragon", "ancient_wyrm": "e_elder_dragon",
	"lich": "risen_lich", "devils_champion": "e_devil_champ",
	"executioner": "e_headsman", "matron": "e_wind_harpy",
	"fire_giant": "e_fire_elemental", "forsworn_champion": "e_warden_champ",
	"collectors_champion": "e_collector_champ", "mad_shepherd": "bloodhound",
	"withered_king": "whisper_king", "tusker": "troll", "nexus_core": "e_golem",
	"hollow_champion": "doom_knight", "conflagrant": "blood_pyre",
	"iron_vanguard": "e_warden_champ", "the_black_tide": "the_black_tide",
}

# Authored voice — multi-register (witchy / sly / dread / grim / eerie-funny).
const PRESENCE_BARKS := {
	"_generic": {
		"enter": ["The meadow remembers your kind.", "You should not have come this far.",
			"Another little flame, come to be snuffed."],
		"hurt": ["Is that all you carry?", "It will cost you more than that.",
			"You only make me certain."],
		"phase": ["Now you have my attention.", "Enough play.", "Let me show you the rest of me."],
		"slay": ["Lie down. The meadow is warm.", "As all the others before you.", "Rest now."],
	},
	"the_crone": {
		"enter": "Sit, child. The cauldron has been waiting for you.",
		"hurt": ["Stir, stir...", "Every little cut only sweetens the brew."],
		"phase": "DOUBLE, DOUBLE. Now it truly boils.",
		"slay": "Into the pot you go.",
	},
	"the_black_tide": {
		"enter": "You stand on the shore of something with no bottom.",
		"hurt": ["The tide does not bruise.", "More of me is already coming."],
		"phase": "THE WATER RISES.",
		"slay": "Down. Down. Down you go.",
	},
	"the_devil": {
		"enter": "I have read your whole little ledger. Shall we settle up?",
		"hurt": ["A fair price.", "You burn so brightly when you're afraid."],
		"phase": "DID YOU THINK THIS WAS THE BARGAIN?",
		"slay": "Sign here.",
	},
	"wolf_pack": {
		"enter": "The brood has not eaten. You are late — and you are meat.",
		"hurt": ["The pack closes in.", "Bleed. They can smell it now."],
		"phase": "The Mother rises.",
		"slay": "The brood feeds tonight.",
	},
	"scarecrow_field": {
		"enter": "The field has been watching you the whole way in.",
		"hurt": ["Straw grows back.", "The crows are still hungry."],
		"phase": "Caw.",
		"slay": "Stand here a while. Become a post.",
	},
	"necromancer_tower": {
		"enter": "Death is only a door I keep propping back open.",
		"hurt": ["You free them, nothing more.", "Kill it. Then watch."],
		"phase": "Rise. RISE.",
		"slay": "Welcome to the choir.",
	},
}


func _build_enemy_presence() -> void:
	if _board_container == null:
		return
	var root := Control.new()
	root.name = "EnemyPresence"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.0; root.anchor_right = 0.0
	root.anchor_top = 0.0; root.anchor_bottom = 0.0
	root.offset_left = 16
	root.offset_top = 60
	root.offset_right = 16 + PRESENCE_W
	root.offset_bottom = 60 + PRESENCE_H
	root.pivot_offset = Vector2(PRESENCE_W * 0.5, PRESENCE_H * 0.5)
	_board_container.add_child(root)
	_enemy_presence = root

	# 1) Dark pocket the antagonist emerges from — near-black fill, bronze-red
	#    rim, deep soft shadow ("lit figure in a dark alcove", not "photo on a board").
	var pocket := Panel.new()
	pocket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pocket.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.035, 0.03, 0.98)
	sb.border_color = Color(0.42, 0.16, 0.12, 1.0)
	for k in ["border_width_top", "border_width_bottom", "border_width_left", "border_width_right"]:
		sb.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		sb.set(k, 14)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	pocket.add_theme_stylebox_override("panel", sb)
	root.add_child(pocket)

	# 2) Art window (clipped; leaves a band at the bottom for the nameplate).
	var art_window := Control.new()
	art_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_window.clip_contents = true
	art_window.anchor_left = 0.0; art_window.anchor_right = 1.0
	art_window.anchor_top = 0.0; art_window.anchor_bottom = 1.0
	art_window.offset_left = 5; art_window.offset_right = -5
	art_window.offset_top = 5; art_window.offset_bottom = -66
	root.add_child(art_window)

	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := _resolve_antagonist_art()
	if tex != null:
		art.texture = tex
	# Cooled + darkened so the warm board rim-light and the red flash read as
	# light landing ON the figure.
	art.modulate = Color(0.82, 0.80, 0.86, 1.0)
	art_window.add_child(art)
	_presence_art = art

	# 3) Inner vignette — the art's edges melt into shadow (no hard rectangle).
	var vig := TextureRect.new()
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.texture = _make_presence_vignette_tex()
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	art_window.add_child(vig)

	# 4) Warm rim-light down the board-facing (right) edge — additive, so the
	#    figure looks lit from the glowing stage.
	var rim := TextureRect.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.anchor_left = 1.0; rim.anchor_right = 1.0
	rim.anchor_top = 0.0; rim.anchor_bottom = 1.0
	rim.offset_left = -36; rim.offset_right = 0
	var rim_grad := Gradient.new()
	rim_grad.offsets = PackedFloat32Array([0.0, 1.0])
	rim_grad.colors = PackedColorArray([Color(1.0, 0.62, 0.30, 0.0), Color(1.0, 0.66, 0.34, 0.5)])
	var rim_tex := GradientTexture2D.new()
	rim_tex.gradient = rim_grad
	rim_tex.fill_from = Vector2(0, 0.5); rim_tex.fill_to = Vector2(1, 0.5)
	rim_tex.width = 64; rim_tex.height = 8
	rim.texture = rim_tex
	rim.stretch_mode = TextureRect.STRETCH_SCALE
	var rim_mat := CanvasItemMaterial.new()
	rim_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rim.material = rim_mat
	art_window.add_child(rim)

	# 5) Red hit-flash overlay (hidden by default).
	var flash := ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.85, 0.10, 0.06, 1.0)
	flash.modulate = Color(1, 1, 1, 0.0)
	var flash_mat := CanvasItemMaterial.new()
	flash_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = flash_mat
	art_window.add_child(flash)
	_presence_flash = flash

	# 6) Nameplate band — encounter title in display font, blood rule, HP bar.
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.anchor_left = 0.0; plate.anchor_right = 1.0
	plate.anchor_top = 1.0; plate.anchor_bottom = 1.0
	plate.offset_top = -60; plate.offset_bottom = -6
	plate.offset_left = 5; plate.offset_right = -5
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.07, 0.05, 0.04, 0.94)
	pb.set("corner_radius_bottom_left", 10)
	pb.set("corner_radius_bottom_right", 10)
	pb.border_color = Color(0.55, 0.18, 0.14, 0.9)
	pb.set("border_width_top", 2)
	plate.add_theme_stylebox_override("panel", pb)
	root.add_child(plate)

	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = _encounter_name if _encounter_name != "" else _antagonist_name()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.anchor_left = 0.0; name_lbl.anchor_right = 1.0
	name_lbl.anchor_top = 0.0; name_lbl.anchor_bottom = 1.0
	name_lbl.offset_left = 6; name_lbl.offset_right = -6
	name_lbl.offset_top = 4; name_lbl.offset_bottom = -16
	if GameTheme.font_display != null:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", Color(0.93, 0.80, 0.42))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	name_lbl.add_theme_constant_override("outline_size", 4)
	plate.add_child(name_lbl)

	var track := ColorRect.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.color = Color(0.12, 0.05, 0.05, 0.95)
	track.anchor_left = 0.0; track.anchor_right = 1.0
	track.anchor_top = 1.0; track.anchor_bottom = 1.0
	track.offset_left = 10; track.offset_right = -10
	track.offset_top = -13; track.offset_bottom = -5
	plate.add_child(track)
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = Color(0.78, 0.16, 0.13, 1.0)
	fill.anchor_left = 0.0; fill.anchor_right = 0.0
	fill.anchor_top = 0.0; fill.anchor_bottom = 1.0
	fill.offset_left = 0; fill.offset_top = 0; fill.offset_bottom = 0
	var fw := float(PRESENCE_W - 20)
	fill.offset_right = fw
	fill.set_meta("full_w", fw)
	track.add_child(fill)
	_presence_hp_fill = fill

	# 7) Spoken-line caption to the right of the figure — frameless ivory italic
	#    over a soft scrim. Reads as the foe (the game itself) speaking, not UI.
	var scrim := Panel.new()
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.anchor_left = 0.0; scrim.anchor_right = 0.0
	scrim.anchor_top = 0.0; scrim.anchor_bottom = 0.0
	scrim.offset_left = PRESENCE_W + 24
	scrim.offset_right = PRESENCE_W + 24 + 330
	scrim.offset_top = 34
	scrim.offset_bottom = 118
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.03, 0.02, 0.02, 0.66)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		ssb.set(k, 8)
	ssb.set("border_width_left", 3)
	ssb.border_color = Color(0.62, 0.20, 0.16, 0.9)
	scrim.add_theme_stylebox_override("panel", ssb)
	scrim.modulate = Color(1, 1, 1, 0.0)
	root.add_child(scrim)
	_presence_bark_scrim = scrim

	var bark := Label.new()
	bark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bark.set_anchors_preset(Control.PRESET_FULL_RECT)
	bark.offset_left = 14; bark.offset_right = -12
	bark.offset_top = 8; bark.offset_bottom = -8
	bark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body != null:
		bark.add_theme_font_override("font", GameTheme.font_body)
	bark.add_theme_font_size_override("font_size", 16)
	bark.add_theme_color_override("font_color", Color(0.96, 0.92, 0.80))
	bark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	bark.add_theme_constant_override("outline_size", 4)
	scrim.add_child(bark)
	_presence_bark = bark

	_update_presence_hp()


func _antagonist_name() -> String:
	# The encounter's centerpiece is authored last in its deck list (Chief, Alpha,
	# Elder Drake, The Crone...). Read it from the source encounter so a shuffled
	# board never changes who "the foe" is. Falls back to the encounter title.
	if _encounter_id != "":
		var enc: Dictionary = EncounterDB.get_encounter(_encounter_id)
		var deck: Array = enc.get("deck", [])
		if deck.size() > 0:
			return String(deck[deck.size() - 1].get("name", ""))
	return _encounter_name


func _resolve_antagonist_art() -> Texture2D:
	# Mirrors Card2D's resolution chain: slugged name → e_-prefixed → alias map.
	var slug := _antagonist_name().to_lower().replace(" ", "_").replace("'", "").replace("-", "_")
	var tex: Texture2D = CardArtAliases.try_load_creature_art(slug)
	if tex == null:
		tex = CardArtAliases.try_load_creature_art("e_" + slug)
	if tex == null and PRESENCE_ART_ALIAS.has(slug):
		tex = CardArtAliases.try_load_creature_art(PRESENCE_ART_ALIAS[slug])
	return tex


func _make_presence_vignette_tex() -> GradientTexture2D:
	# Transparent core → black edges, bottom-biased so the figure's base melts
	# fully into the dark pocket.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.82, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0.02, 0.015, 0.015, 0.0),
		Color(0.03, 0.02, 0.02, 0.45), Color(0.02, 0.012, 0.012, 0.96)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.46)
	t.fill_to = Vector2(0.5, 1.04)
	t.width = 160; t.height = 256
	return t


func _update_presence_hp() -> void:
	if _presence_hp_fill == null:
		return
	var full: float = _presence_hp_fill.get_meta("full_w", float(PRESENCE_W - 20))
	var ratio := clampf(float(enemy_hp) / float(maxi(enemy_max_hp, 1)), 0.0, 1.0)
	var tw := _presence_hp_fill.create_tween()
	tw.tween_property(_presence_hp_fill, "offset_right", full * ratio, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_presence_hp_fill.color = Color(0.78, 0.16, 0.13, 1.0).lerp(Color(0.35, 0.05, 0.05, 1.0), 1.0 - ratio)


func _pick_bark(kind: String) -> String:
	var bset: Dictionary = PRESENCE_BARKS.get(_encounter_id, {})
	var lines = bset.get(kind, null)
	if lines == null:
		lines = PRESENCE_BARKS["_generic"].get(kind, null)
	if lines is String:
		return lines
	if lines is Array and not lines.is_empty():
		return String(lines[randi() % lines.size()])
	return ""


func _presence_say(text: String, col: Color = Color(0.96, 0.92, 0.80)) -> void:
	if _presence_bark == null or _presence_bark_scrim == null or text == "":
		return
	_presence_bark.text = text
	_presence_bark.add_theme_color_override("font_color", col)
	if _presence_bark_tween != null and _presence_bark_tween.is_valid():
		_presence_bark_tween.kill()
	_presence_bark_scrim.modulate.a = 0.0
	var hold := clampf(1.4 + text.length() * 0.035, 1.6, 4.5)
	_presence_bark_tween = _presence_bark_scrim.create_tween()
	_presence_bark_tween.tween_property(_presence_bark_scrim, "modulate:a", 1.0, 0.18)
	_presence_bark_tween.tween_interval(hold)
	_presence_bark_tween.tween_property(_presence_bark_scrim, "modulate:a", 0.0, 0.5)


func presence_enter() -> void:
	if _enemy_presence == null:
		return
	# Scale punch (the plate is a persistent HUD element, so no alpha fade —
	# that would blink the portrait + HP). Then the foe speaks its opening line.
	_enemy_presence.scale = Vector2(0.9, 0.9)
	var t := _enemy_presence.create_tween()
	t.tween_property(_enemy_presence, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_presence_say(_pick_bark("enter"), Color(0.96, 0.90, 0.78))


func presence_flinch(amount: int) -> void:
	if _enemy_presence == null or amount <= 0:
		return
	if _presence_flash != null:
		_presence_flash.modulate.a = 0.0
		var ft := _presence_flash.create_tween()
		ft.tween_property(_presence_flash, "modulate:a", clampf(0.30 + amount * 0.06, 0.30, 0.7), 0.05)
		ft.tween_property(_presence_flash, "modulate:a", 0.0, 0.22).set_ease(Tween.EASE_OUT)
	if _presence_react_tween != null and _presence_react_tween.is_valid():
		_presence_react_tween.kill()
	_enemy_presence.scale = Vector2.ONE
	_enemy_presence.rotation = 0.0
	var mag := clampf(0.012 + amount * 0.004, 0.012, 0.05)
	var t := _enemy_presence.create_tween()
	t.tween_property(_enemy_presence, "scale", Vector2(0.95, 0.95), 0.05)
	t.parallel().tween_property(_enemy_presence, "rotation", mag, 0.05)
	t.tween_property(_enemy_presence, "rotation", -mag, 0.06)
	t.tween_property(_enemy_presence, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_enemy_presence, "rotation", 0.0, 0.14)
	_presence_react_tween = t
	if amount >= 4:
		_presence_say(_pick_bark("hurt"), Color(1.0, 0.72, 0.62))


func presence_react_player_hit(amount: int) -> void:
	if _enemy_presence == null or amount <= 0:
		return
	if _presence_react_tween != null and _presence_react_tween.is_valid():
		return  # don't stomp an in-flight flinch
	var t := _enemy_presence.create_tween()
	t.tween_property(_enemy_presence, "scale", Vector2(1.04, 1.04), 0.10).set_trans(Tween.TRANS_SINE)
	t.tween_property(_enemy_presence, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)
	_presence_react_tween = t


func presence_phase(col: Color = Color(1.0, 0.35, 0.28)) -> void:
	if _enemy_presence == null:
		return
	if _presence_react_tween != null and _presence_react_tween.is_valid():
		_presence_react_tween.kill()
	var t := _enemy_presence.create_tween()
	t.tween_property(_enemy_presence, "scale", Vector2(1.10, 1.10), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.5)
	t.tween_property(_enemy_presence, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	_presence_react_tween = t
	var vnode := get_node_or_null("Vignette")
	if vnode != null and vnode.material != null:
		var base: float = float(vnode.material.get_shader_parameter("vignette_strength"))
		var vt := vnode.create_tween()
		vt.tween_method(func(v): vnode.material.set_shader_parameter("vignette_strength", v), base, base + 0.16, 0.2)
		vt.tween_interval(0.5)
		vt.tween_method(func(v): vnode.material.set_shader_parameter("vignette_strength", v), base + 0.16, base, 0.5)
	_presence_say(_pick_bark("phase"), col)


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

## Soft radial falloff, built once and shared by all 16 contact shadows.
static var _contact_shadow_tex: Texture2D = null


static func _get_contact_shadow_tex() -> Texture2D:
	# A radial dark→transparent gradient. Stretched into a flat ellipse by the
	# slot's ContactShadow TextureRect to read as a creature's cast shadow on the
	# ground. gl_compatibility has no cheap blur, so a baked soft gradient is the
	# grounding cue — far more convincing than the card's tight box shadow alone.
	if _contact_shadow_tex != null:
		return _contact_shadow_tex
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0, 0, 0, 0.62))
	grad.add_point(0.55, Color(0, 0, 0, 0.30))
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)  # radius = half width → circle, scaled to ellipse by the rect
	_contact_shadow_tex = tex
	return _contact_shadow_tex


## Vertical dark→transparent gradient, built once and shared by all 16 sockets.
## Layered over a socket's well to fake an inner-shadow recess.
static var _socket_shadow_tex: Texture2D = null


static func _get_socket_shadow_tex() -> Texture2D:
	if _socket_shadow_tex != null:
		return _socket_shadow_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.10), Color(0, 0, 0, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 16
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	_socket_shadow_tex = tex
	return _socket_shadow_tex


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
	const SLOT_H := 150
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.clip_contents = false

	# Carved socket — a recessed station the creature stands in, VISIBLE even when
	# empty. This is a lane game; the player must read where the 16 stations are
	# and which are filled, so the board can't hide them. Depth, not fill: a dark
	# well + faint ownership tint (warm enemy / cool player) + a subtle gilt rim,
	# with an inner-shadow gradient on top for the "pressed into the table" recess.
	# (The previous board hid sockets at ≤0.16 alpha to dodge a debug-grid look;
	# for a lane game that erased the board. The lane tracks + dark substrate do
	# the grouping work now, so the sockets are free to read as real stations.)
	var well := Panel.new()
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var well_style := StyleBoxFlat.new()
	if is_enemy:
		well_style.bg_color = Color(0.21, 0.06, 0.05, 0.50) if row == ROW_FRONT \
			else Color(0.15, 0.05, 0.045, 0.34)
	else:
		well_style.bg_color = Color(0.06, 0.10, 0.17, 0.50) if row == ROW_FRONT \
			else Color(0.05, 0.08, 0.13, 0.34)
	well_style.border_color = Color(GILT.r, GILT.g, GILT.b,
		0.18 if row == ROW_FRONT else 0.10)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		well_style.set(k, 1)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		well_style.set(k, 8)
	well.add_theme_stylebox_override("panel", well_style)
	slot.add_child(well)

	# Inner shadow — dark along the top edge fading down, so the socket reads as a
	# recess pressed into the table rather than a flat tinted rectangle.
	var inner := TextureRect.new()
	inner.texture = _get_socket_shadow_tex()
	inner.stretch_mode = TextureRect.STRETCH_SCALE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(inner)

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

	# Contact shadow — a flat dark ellipse pooled at the creature's base so it
	# reads as standing ON the lit ground, not floating. Lives in the slot (not
	# the card) so it stays planted when the card lunges forward on attack — the
	# card lifts off its shadow, which sells weight. Hidden until a card lands;
	# toggled by _slot_set_card / _slot_clear. Drawn below "Cell" so the card
	# (and its own box shadow) composite on top; only the lip below the card's
	# bottom edge shows as cast shadow on the ground.
	var contact := TextureRect.new()
	contact.name = "ContactShadow"
	contact.texture = _get_contact_shadow_tex()
	contact.stretch_mode = TextureRect.STRETCH_SCALE
	contact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contact.visible = false
	# Anchored bottom-centre: a wide, short ellipse seated at the card's feet.
	contact.anchor_left = 0.5
	contact.anchor_right = 0.5
	contact.anchor_top = 1.0
	contact.anchor_bottom = 1.0
	contact.offset_left = -92
	contact.offset_right = 92
	contact.offset_top = -34
	contact.offset_bottom = 14
	contact.modulate = Color(1, 1, 1, 0.9)
	slot.add_child(contact)

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
	var shadow = slot.get_node_or_null("ContactShadow")
	if shadow != null:
		shadow.visible = true


func _slot_clear(slot: Control) -> void:
	# Removes the card from the slot (keeping the bg + cell intact).
	var cell = _slot_cell(slot)
	if cell == null:
		return
	for child in cell.get_children():
		child.queue_free()
	var shadow = slot.get_node_or_null("ContactShadow")
	if shadow != null:
		shadow.visible = false


func _slot_take_card(slot: Control, card: Control) -> void:
	# Detaches `card` from the slot's cell so it can be re-parented elsewhere.
	var cell = _slot_cell(slot)
	if cell != null and cell.is_ancestor_of(card):
		cell.remove_child(card)
	elif slot.is_ancestor_of(card):
		slot.remove_child(card)
	var shadow = slot.get_node_or_null("ContactShadow")
	if shadow != null:
		shadow.visible = false


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
	card.will_die.connect(_on_card_will_die.bind(card))


func _place_card_in_slot(card: Control, lane_idx: int, row: int = ROW_FRONT,
		from_global: Vector2 = Vector2.ZERO, with_arc: bool = false) -> void:
	_row_array(false, row)[lane_idx] = card
	card.current_row = row
	card.current_lane = lane_idx
	var slot = _slot_array(false, row)[lane_idx]
	_slot_set_card(slot, card)
	if not card.destroyed.is_connected(_on_card_destroyed.bind(card)):
		card.destroyed.connect(_on_card_destroyed.bind(card))
	if not card.will_die.is_connected(_on_card_will_die.bind(card)):
		card.will_die.connect(_on_card_will_die.bind(card))
	if card.has_floop() and not card.is_opponent:
		if not card.floop_clicked.is_connected(_on_floop_clicked.bind(card)):
			card.floop_clicked.connect(_on_floop_clicked.bind(card))
	# Battlefield move-drag wiring (friendly creatures only). dragging/drag_ended
	# may already be connected from the card's hand days; guard so we don't
	# double-fire the slot highlight.
	if not card.is_opponent and card.is_creature():
		if not card.field_move_started.is_connected(_on_field_move_started.bind(card)):
			card.field_move_started.connect(_on_field_move_started.bind(card))
		if not card.field_move_dropped.is_connected(_on_field_move_dropped.bind(card)):
			card.field_move_dropped.connect(_on_field_move_dropped.bind(card))
		if not card.dragging.is_connected(_on_card_dragging.bind(card)):
			card.dragging.connect(_on_card_dragging.bind(card))
		if not card.drag_ended.is_connected(_clear_slot_highlights):
			card.drag_ended.connect(_clear_slot_highlights)
	# Friendly damage hook. Used by Stalwart's Anvil, Wormwood, Spike Driver,
	# and any future relic that reacts to "ally took a hit". The Card2D signal
	# fires only when amount > 0, so guard logic stays in the handler.
	if not card.is_opponent:
		if not card.damaged.is_connected(_on_friendly_damaged.bind(card)):
			card.damaged.connect(_on_friendly_damaged.bind(card))
	card.update_floop_display()
	_play_landing_pop(card, from_global, with_arc)


func _play_landing_pop(card: Control, from_global: Vector2 = Vector2.ZERO,
		with_arc: bool = false) -> void:
	# Tier 1 card-play motion. When `with_arc` is true, the card flies from
	# `from_global` (its hand position, captured before remove_child) to its
	# resting slot via a quadratic Bezier with an upward apex, finishing with a
	# scale punch. When false, falls back to the squash-only pop used for enemy
	# placements and repositions where there's no "where it came from" to draw.
	# Deferred a frame so the slot's CenterContainer has time to lay the card out.
	if not is_instance_valid(card):
		return
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var rest_scale: Vector2 = card.scale
	card.pivot_offset = card.size * 0.5

	if with_arc:
		# The card is currently parented inside its slot's CenterContainer, so
		# tweening local position would fight the container's layout pass. Detach
		# to the HUD layer for the flight, then re-attach to the cell at landing
		# so the container's layout owns the resting position again.
		var rest_global: Vector2 = card.global_position
		var rest_parent: Node = card.get_parent()
		var rest_index: int = card.get_index()
		if rest_parent != null:
			rest_parent.remove_child(card)
		var flight_parent: Node = _hud_layer if _hud_layer != null else self
		flight_parent.add_child(card)
		card.global_position = from_global
		card.scale = rest_scale * 0.92
		card.rotation = randf_range(-0.07, 0.07)
		card.z_index = 200

		var duration := 0.34
		var arc_peak_lift := 72.0
		var control: Vector2 = from_global.lerp(rest_global, 0.5) + Vector2(0, -arc_peak_lift)
		# Capture by-value so the lambda doesn't see later mutations.
		var start := from_global
		var stop := rest_global
		var ctrl := control

		var tw := card.create_tween().set_parallel(true)
		tw.tween_method(func(t: float):
			if not is_instance_valid(card):
				return
			var p1 := start.lerp(ctrl, t)
			var p2 := ctrl.lerp(stop, t)
			card.global_position = p1.lerp(p2, t)
		, 0.0, 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(card, "rotation", 0.0, duration).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", rest_scale * 1.05, duration).set_ease(Tween.EASE_OUT)

		await tw.finished
		if not is_instance_valid(card):
			return
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		if is_instance_valid(rest_parent):
			rest_parent.add_child(card)
			if rest_index >= 0 and rest_index < rest_parent.get_child_count():
				rest_parent.move_child(card, rest_index)
		card.z_index = 0

		var settle := card.create_tween()
		settle.tween_property(card, "scale", rest_scale, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		settle.tween_callback(func():
			if is_instance_valid(card) and card.has_method("enable_idle_bob"):
				card.enable_idle_bob()
		)
	else:
		card.scale = rest_scale * 1.35
		var tw := card.create_tween()
		tw.tween_property(card, "scale", rest_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			if is_instance_valid(card) and card.has_method("enable_idle_bob"):
				card.enable_idle_bob()
		)


func _on_card_will_die(card: Control) -> void:
	# Pre-death rescue handlers. Setting card.current_hp > 0 cancels the death.
	if card == null or not is_instance_valid(card):
		return
	if card.current_hp > 0:
		return
	# Phantom Veil relic: first friendly death this round survives at 1 HP.
	if not card.is_opponent and _has_relic("phantom_veil") \
			and not get_meta("phantom_veil_used", false):
		set_meta("phantom_veil_used", true)
		card.current_hp = 1
		card.update_stat_display()
		if card.has_method("_spawn_keyword_chip"):
			card._spawn_keyword_chip("RESCUED", Color(0.85, 0.95, 1.0))
		return
	# Reborn on_death: card resurrects at 1 HP once per fight.
	var od: Dictionary = card.card_data.get("on_death", {})
	if od.get("type", "") == "reborn" and not card.get_meta("reborn_used", false):
		card.set_meta("reborn_used", true)
		card.current_hp = 1
		card.update_stat_display()
		if card.has_method("_spawn_keyword_chip"):
			card._spawn_keyword_chip("REBORN", Color(0.75, 0.55, 1.0))
		return


func _on_card_destroyed(card: Control) -> void:
	# Locate the card in the field arrays so death dispatchers know lane/side/row.
	var lane: int = -1
	var was_enemy: bool = false
	var row: int = -1
	for i in range(LANES_PER_ROW):
		if _player_field[i] == card:
			lane = i; was_enemy = false; row = ROW_FRONT; break
		if _enemy_field[i] == card:
			lane = i; was_enemy = true; row = ROW_FRONT; break
		if _player_back[i] == card:
			lane = i; was_enemy = false; row = ROW_BACK; break
		if _enemy_back[i] == card:
			lane = i; was_enemy = true; row = ROW_BACK; break

	# Null arrays BEFORE dispatching so on_death effects that read the field
	# (e.g. summon-token in the dying card's lane) see the empty slot.
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

	if lane < 0:
		return

	# JUICE — register this death for the coalesced "notable kill" hit-stop so a
	# multi-creature wipe or a chunky bruiser dying lands with weight.
	_note_death(card, was_enemy)

	# Snapshot enemy data so on_death effects that look up "last dead enemy"
	# see the freshly-dead card (Doppelganger, Phoenix Feather).
	if was_enemy:
		_last_dead_enemy_data = card.card_data.duplicate(true)

	# Fire on_death effects. dispatch_on_death handles its own doubling for
	# the player passive "double_on_death" / "Frenzied" mutator.
	KeywordEffects.dispatch_on_death(card, lane, was_enemy, self)

	# Encounter-specific death hooks (Pyre/Mausoleum/Trebuchet charge feeds,
	# Wolf pack revenge, Necromancer summon, etc.).
	if was_enemy:
		_dispatch_encounter_on_enemy_death(lane, card)
	else:
		_on_friendly_death(card, lane)
		_dispatch_encounter_on_player_death(lane)

	# Reactive passive (ON_CREATURE_DEATH triggers — Necromancer Tower's
	# double_on_death, etc.).
	_dispatch_reactive("ON_CREATURE_DEATH", card, lane)

	# Rear Guard Charm relic: front-row friendly death buffs the back-row
	# column-mate +1/+1 permanently.
	if not was_enemy and row == ROW_FRONT and _has_relic("rear_guard_charm"):
		var back_mate = _player_back[lane]
		if back_mate != null and back_mate.current_hp > 0:
			back_mate.current_atk += 1
			back_mate.card_data["hp"] = int(back_mate.card_data.get("hp", 0)) + 1
			back_mate.current_hp += 1
			back_mate.update_stat_display()

	# Stygian Soul: heal 1 HP per enemy death, capped at 5 per combat.
	if was_enemy and _has_relic("stygian_soul"):
		var cap: int = int(RelicDB.get_relic("stygian_soul").get("value", 5))
		if _stygian_soul_healed < cap:
			_stygian_soul_healed += 1
			RunState.heal_hero(1)
			player_hp = RunState.hero_hp

	# Death Card: instead of going to discard, friendly non-tokens return to
	# hand with their cost bumped by 1 for each subsequent return this fight.
	# Falls through to the normal discard path if hand is full so the card
	# isn't silently lost.
	var death_card_handled := false
	if not was_enemy and not card.is_token and _has_relic("death_card") \
			and _hand.size() < MAX_HAND_SIZE:
		var returns: int = int(_death_card_returns.get(card.card_id, 0))
		_death_card_returns[card.card_id] = returns + 1
		# Re-add to draw pile so the normal _draw_card pipeline handles the build,
		# then draw it immediately. Track the cost bump via a meta on the returned
		# card during draw.
		_player_draw_pile.push_front(_pile_entry(card.card_id, card.deck_uid))
		draw_one()
		# Apply the cost bump on the freshly-drawn card (last appended to hand).
		if _hand.size() > 0:
			var fresh = _hand[_hand.size() - 1]
			if fresh != null and is_instance_valid(fresh):
				var bump: int = int(RelicDB.get_relic("death_card").get("value", 1)) * (returns + 1)
				fresh.card_data["cost"] = int(fresh.card_data.get("cost", 0)) + bump
		death_card_handled = true

	# Move friendly non-tokens to discard (skipped if Death Card handled it).
	if not was_enemy and not card.is_token and not death_card_handled:
		_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))

	# Husk: every surviving creature with grow_on_any_death grows +1/+1.
	for h in _all_player_creatures():
		if h != card and h.card_data.get("passive", "") == "grow_on_any_death":
			h.current_atk += 1
			h.current_hp += 1
			h.card_data.hp += 1
			h.update_stat_display()

	# Resonance Crystal relic: first keyword-bearing creature death this fight
	# propagates ONE of its combat keywords to every surviving friendly. We
	# pick the first matching keyword (stable across runs of the same fight)
	# and only spread keywords that actually do something in combat —
	# spreading "on_enter" or "floop" would be visual noise.
	if _has_relic("resonance_crystal") and not _resonance_crystal_used_this_fight:
		var spread_kw := ""
		for kw in card.card_data.get("keywords", []):
			if kw in KeywordEffects.COMBAT_KEYWORDS:
				spread_kw = kw
				break
		if spread_kw != "":
			_resonance_crystal_used_this_fight = true
			for ally in _all_player_creatures():
				if ally != card and not ally.card_data.keywords.has(spread_kw):
					ally.card_data.keywords.append(spread_kw)
					ally.update_stat_display()




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
	# Spells don't occupy a slot (they enter targeting on play), so lighting a
	# board slot under a dragged spell is misleading — skip it.
	if card.has_method("is_creature") and not card.is_creature():
		_clear_slot_highlights()
		return
	# Only highlight once the drag crosses into the play zone, and share the
	# EXACT play gate (Card2D.PLAY_THRESHOLD_Y) so a slot lights up precisely
	# when a release there would play. Previously this used 0.78 while the drop
	# check used 0.72 — a 6%-tall band where the slot glowed but releasing
	# snapped the card back to hand.
	var viewport_h := get_viewport_rect().size.y
	if global_pos.y >= viewport_h * Card2D.PLAY_THRESHOLD_Y:
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


# ── Battlefield creature repositioning ("move") ─────────────────────────────
# The player can drag a friendly creature already on the board to an empty
# friendly slot during their turn (up to MOVES_PER_TURN times). Card2D handles
# the click-vs-drag distinction and emits field_move_started / field_move_dropped;
# Combat owns the slot grid + hand layer, so the actual re-parenting lives here.

func _on_field_move_started(card: Control) -> void:
	# The grab lifted off its slot. Detach the card from its CenterContainer cell
	# and float it on the hand layer so it can track the cursor. The slot's
	# board-array entry keeps pointing at the card until the drop resolves, so
	# mid-drag board state stays consistent (nothing iterates it during the
	# player's idle turn).
	if not is_instance_valid(card):
		return
	var home_global: Vector2 = card.global_position
	var cell = card.get_parent()
	if cell != null:
		cell.remove_child(card)
	# Hide the contact shadow under the vacated slot while the card is lifted.
	var src_slot: Control = _slot_array(false, card.current_row)[card.current_lane]
	if src_slot != null:
		var sh = src_slot.get_node_or_null("ContactShadow")
		if sh != null:
			sh.visible = false
	_hand_container.add_child(card)
	card.global_position = home_global


func _on_field_move_dropped(card: Control, global_pos: Vector2) -> void:
	if not is_instance_valid(card):
		return
	_clear_slot_highlights()
	var moved := false
	if phase == Phase.PLAYER_TURN and _moves_used_this_turn < MOVES_PER_TURN:
		var drop := _nearest_player_slot(global_pos)
		var dest_row: int = drop.row
		var dest_lane: int = drop.lane
		var src_row: int = card.current_row
		var src_lane: int = card.current_lane
		var same_slot: bool = (dest_row == src_row and dest_lane == src_lane)
		if not same_slot and _row_array(false, dest_row)[dest_lane] == null:
			_row_array(false, src_row)[src_lane] = null
			card.current_row = dest_row
			card.current_lane = dest_lane
			_reset_card_after_drag(card)
			_slot_set_card(_slot_array(false, dest_row)[dest_lane], card)
			_row_array(false, dest_row)[dest_lane] = card
			_moves_used_this_turn += 1
			_play_landing_pop(card)
			if AudioBank != null:
				AudioBank.play_sfx("card_play")
			moved = true
		elif not same_slot:
			_show_info("That slot is occupied.")
	elif _moves_used_this_turn >= MOVES_PER_TURN:
		_show_info("No moves left this turn.")
	if not moved:
		_return_card_to_slot(card)


func _return_card_to_slot(card: Control) -> void:
	# Snap a lifted creature back into the slot it came from. current_row/
	# current_lane were never changed, and its board-array entry still points here.
	if not is_instance_valid(card):
		return
	_reset_card_after_drag(card)
	_slot_set_card(_slot_array(false, card.current_row)[card.current_lane], card)
	_row_array(false, card.current_row)[card.current_lane] = card


func _reset_card_after_drag(card: Control) -> void:
	# Detach from the transient drag parent (hand layer) and restore the neutral
	# transform a slotted creature expects before it's added to a cell.
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	card.scale = Vector2.ONE
	card.z_index = 0
	card.pivot_offset = card.size * 0.5


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
	_build_potion_bar_diegetic()
	_build_incoming_damage_chip()


func _build_incoming_damage_chip() -> void:
	# Diegetic threat indicator pinned above the player banner: a crossed-swords
	# glyph (a skull when the hit is lethal this round) beside the total face
	# damage the enemy will deal if the player doesn't block. Reads at a glance —
	# replaces the mental math of summing every enemy in a clear column. Styled
	# like a Slay-the-Spire attack intent (framed icon + numeral) instead of the
	# old starred "Incoming face damage: N" text, which read as a debug print.
	# Hidden when the total is 0 so it doesn't clutter safe turns.
	var chip := PanelContainer.new()
	chip.name = "IncomingDamageChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.05, 0.04, 0.92)
	style.border_color = Color(0.85, 0.27, 0.18, 1.0)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		style.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(k, 7)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", style)
	# Pinned directly BELOW the enemy plate (top-right) — the threat belongs next
	# to its source, so the player reads "this foe will hit me for N" in one
	# glance at the enemy corner. The enemy banner is H=304 from y=14, so it ends
	# at y=318; the chip sits just under that at y=324. (It used to be pinned at
	# y=258 from when the banner was only 240 tall — once the banner was enlarged
	# the chip ended up ON TOP of the enemy HP medallion, mashing the HP numeral
	# and the threat numeral into one unreadable blob. Keep offset_top a few px
	# below the banner's offset_bottom in _build_enemy_banner_diegetic.)
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.anchor_top = 0.0
	chip.anchor_bottom = 0.0
	chip.offset_left = -160
	chip.offset_right = -14
	chip.offset_top = 324
	chip.offset_bottom = 382
	chip.z_index = 5
	chip.visible = false

	# Two-line layout: a small "INCOMING" caption over the icon + numeral so the
	# chip explains itself. The bare "⚔ N" read as a mystery glyph to players who
	# didn't know it meant "face damage headed your way this round".
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(col)

	var caption := Label.new()
	caption.name = "ThreatCaption"
	caption.text = "INCOMING"
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", Color(0.96, 0.66, 0.46))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 3)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		caption.add_theme_font_override("font", GameTheme.font_display)
	col.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	var icon := TextureRect.new()
	icon.name = "ThreatIcon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1.0, 0.45, 0.30)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw_path := "res://assets/icons/game-icons/crossed-swords.svg"
	if ResourceLoader.exists(sw_path):
		icon.texture = load(sw_path)
	row.add_child(icon)
	_incoming_dmg_icon = icon

	var num := Label.new()
	num.name = "ThreatNum"
	num.text = ""
	num.add_theme_font_size_override("font_size", 22)
	num.add_theme_color_override("font_color", Color(1.0, 0.58, 0.40))
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	num.add_theme_constant_override("outline_size", 5)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_title_black:
		num.add_theme_font_override("font", GameTheme.font_title_black)
	row.add_child(num)
	_incoming_dmg_label = num

	_hud_layer.add_child(chip)
	_incoming_dmg_chip = chip


func _compute_incoming_face_damage() -> int:
	# Sums the ATK of every enemy creature whose attack will land on face
	# this round. An enemy attacks face when both player slots in its column
	# are empty AND its intent is ATK / CHARGE. Skips structures, frozen
	# creatures, and creatures that have already attacked.
	var total: int = 0
	for row in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(true, row)
		for lane in range(LANES_PER_ROW):
			var attacker = arr[lane]
			if attacker == null or not is_instance_valid(attacker):
				continue
			if attacker.has_keyword("structure"):
				continue
			if not attacker.can_attack():
				continue
			# Front-row enemies attack first; if a back-row enemy is in the
			# same column AND a front-row enemy occupies it, the back-row
			# enemy can't reach this round. Counting just front prevents
			# double-counting; back-row attackers in empty front columns DO
			# get to swing, so include them when no front-row partner exists.
			if row == ROW_BACK and _enemy_field[lane] != null:
				continue
			# Player column empty? Then this attacker hits face.
			if _player_field[lane] != null or _player_back[lane] != null:
				continue
			var intent: String = String(attacker.get_meta("current_intent", "ATK"))
			if intent != "ATK" and intent != "CHARGE":
				continue
			total += attacker.effective_atk()
	return total


func _refresh_incoming_damage_chip() -> void:
	if _incoming_dmg_chip == null:
		return
	var dmg: int = _compute_incoming_face_damage()
	if dmg <= 0:
		_incoming_dmg_chip.visible = false
		return
	_incoming_dmg_chip.visible = true
	_incoming_dmg_label.text = str(dmg)
	# Escalating threat read: amber swords when survivable, hot-red skull when
	# the hit is lethal this round (block or die), warm-red in between.
	var lethal: bool = dmg >= player_hp
	var num_color := Color(1.0, 0.60, 0.42)
	var icon_color := Color(1.0, 0.46, 0.30)
	var border := Color(0.80, 0.33, 0.20, 1.0)
	if lethal:
		num_color = Color(1.0, 0.34, 0.30)
		icon_color = Color(1.0, 0.30, 0.24)
		border = Color(1.0, 0.22, 0.18, 1.0)
	elif dmg >= player_hp / 2:
		num_color = Color(1.0, 0.48, 0.30)
		icon_color = Color(1.0, 0.40, 0.26)
		border = Color(0.92, 0.30, 0.18, 1.0)
	_incoming_dmg_label.add_theme_color_override("font_color", num_color)
	if _incoming_dmg_icon != null:
		_incoming_dmg_icon.modulate = icon_color
		var want := "res://assets/icons/game-icons/horned-skull.svg" if lethal \
			else "res://assets/icons/game-icons/crossed-swords.svg"
		if ResourceLoader.exists(want):
			_incoming_dmg_icon.texture = load(want)
	var st: StyleBoxFlat = _incoming_dmg_chip.get_theme_stylebox("panel")
	if st != null:
		st.border_color = border


func _portrait_art_for_card(cd: Dictionary) -> Texture2D:
	# Mirror Card2D._find_card_art's creature resolution (id → name → "e_"name)
	# so an encounter's lead creature can stand in as the enemy portrait.
	var cid := String(cd.get("id", ""))
	var name_id := String(cd.get("name", "")).to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = CardArtAliases.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art("e_" + name_id)
	return art


func _resolve_enemy_portrait() -> Texture2D:
	# Per-encounter portrait instead of one shared face. Resolution order:
	#   1. assets/portraits/boss_<encounter_id>.png  (painted splash for a
	#      specific boss/elite — e.g. boss_iron_warden, boss_collector, etc.)
	#   2. assets/portraits/boss_act<N>.png  (per-act fallback — used by bosses
	#      that don't have a bespoke splash painting yet)
	#   3. lead creature's card art (highest-HP creature in the encounter deck)
	#   4. enemy_commander.png  (last-ditch generic)
	# Elites can also opt into step 1 by dropping a boss_<eid>.png file; that's
	# how the act 2 demon_vanguard elite picks up its painted splash.
	var enc: Dictionary = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type: String = String(enc.get("type", ""))
	if _encounter_id != "" and (enc_type == "boss" or enc_type == "elite"):
		var enc_path := "res://assets/portraits/boss_%s.png" % _encounter_id
		if ResourceLoader.exists(enc_path):
			return load(enc_path)
	if enc_type == "boss":
		var bpath := "res://assets/portraits/boss_act%d.png" % RunState.get_act()
		if ResourceLoader.exists(bpath):
			return load(bpath)
	if _enemy_deck.is_empty() and _encounter_id != "":
		_enemy_deck = EncounterDB.build_enemy_deck(_encounter_id, RunState.get_act())
	if not _enemy_deck.is_empty():
		var lead: Dictionary = _enemy_deck[0]
		for cd in _enemy_deck:
			if int(cd.get("hp", 0)) > int(lead.get("hp", 0)):
				lead = cd
		var art := _portrait_art_for_card(lead)
		if art != null:
			return art
	return load("res://assets/portraits/enemy_commander.png")


func _build_enemy_banner_diegetic() -> void:
	# Top-RIGHT: enemy portrait + HP medallion ONLY. Encounter title moved to
	# a centered title strip at top-center; relics tucked underneath this
	# banner. Slim banner reads cleaner than the previous tall column that
	# stacked portrait + HP + encounter info + round counter.
	# Enlarged past the player plate so the antagonist LOOMS rather than mirrors
	# you — the foe should dominate its corner, not match yours.
	const W := 236
	const H := 304
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
	# This plate IS the Living Antagonist — reactions (flinch / lean-in) scale
	# about its centre.
	_enemy_presence = banner
	banner.pivot_offset = Vector2(W * 0.5, H * 0.5)

	# Dark backdrop so the portrait never blends into the meadow background.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.03, 0.03, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bg)

	# Portrait region: from the top down to where the HP medallion starts.
	# HP medallion lives in the bottom 72px of the banner. With H=304 (banner
	# y=14..318), the medallion spans absolute y=246..302. The incoming-damage
	# chip is pinned just below that (y=324) in _build_incoming_damage_chip — if
	# you change H here, move the chip too or it lands back on the HP numeral.
	const HP_TOP := -72
	const HP_BOTTOM := -8
	var demon_tex: Texture2D = _resolve_enemy_portrait()
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
	_presence_art = null

	# ── Living Antagonist treatment: emerge-from-shadow + reaction overlays ──
	# Inner vignette so the foe's edges melt into the dark pocket (Inscryption).
	var pvig := TextureRect.new()
	pvig.set_anchors_preset(Control.PRESET_FULL_RECT)
	pvig.offset_bottom = HP_TOP
	pvig.texture = _make_presence_vignette_tex()
	pvig.stretch_mode = TextureRect.STRETCH_SCALE
	pvig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(pvig)
	# Warm rim-light down the board-facing (left) edge — additive, "lit by the stage".
	var prim := TextureRect.new()
	prim.anchor_left = 0.0; prim.anchor_right = 0.0
	prim.anchor_top = 0.0; prim.anchor_bottom = 1.0
	prim.offset_right = 42; prim.offset_bottom = HP_TOP
	var prim_grad := Gradient.new()
	prim_grad.offsets = PackedFloat32Array([0.0, 1.0])
	prim_grad.colors = PackedColorArray([Color(1.0, 0.64, 0.32, 0.5), Color(1.0, 0.64, 0.32, 0.0)])
	var prim_tex := GradientTexture2D.new()
	prim_tex.gradient = prim_grad
	prim_tex.fill_from = Vector2(0, 0.5); prim_tex.fill_to = Vector2(1, 0.5)
	prim_tex.width = 64; prim_tex.height = 8
	prim.texture = prim_tex
	prim.stretch_mode = TextureRect.STRETCH_SCALE
	var prim_mat := CanvasItemMaterial.new()
	prim_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	prim.material = prim_mat
	prim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(prim)
	# Red hit-flash overlay (hidden; driven by presence_flinch).
	var pflash := ColorRect.new()
	pflash.set_anchors_preset(Control.PRESET_FULL_RECT)
	pflash.offset_bottom = HP_TOP
	pflash.color = Color(0.85, 0.10, 0.06, 1.0)
	pflash.modulate = Color(1, 1, 1, 0.0)
	var pflash_mat := CanvasItemMaterial.new()
	pflash_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pflash.material = pflash_mat
	pflash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(pflash)
	_presence_flash = pflash

	# Painted border wraps the WHOLE plate (portrait + HP bar) so the bar reads
	# as the base of one framed panel — not a pill hanging outside the frame.
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

	# Foe identity lives in the big encounter-name title in the center HUD
	# (_floor_label). The portrait stays a clean icon + HP medallion instead of
	# repeating the same name on a second plate right here.
	# Bar is inset inside the frame's painted border so it nests within the plate.
	var hp := _make_hp_medallion_diegetic(true, enemy_hp, enemy_max_hp)
	hp.anchor_left = 0.0
	hp.anchor_right = 1.0
	hp.anchor_top = 1.0
	hp.anchor_bottom = 1.0
	hp.offset_top = HP_TOP
	hp.offset_bottom = HP_BOTTOM - 8
	hp.offset_left = 14
	hp.offset_right = -14
	banner.add_child(hp)

	# Spoken-line caption — floats just LEFT of the foe, out into the board, so
	# its words read as coming from the figure. Frameless ivory over a soft
	# scrim; hidden until a bark fires.
	var scrim := Panel.new()
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.anchor_left = 0.0; scrim.anchor_right = 0.0
	scrim.anchor_top = 0.0; scrim.anchor_bottom = 0.0
	scrim.offset_right = -16
	scrim.offset_left = -16 - 340
	# Sits at the foe's mid-height, extending left into open board — clear of the
	# center-top encounter title + passive-description band.
	scrim.offset_top = 150
	scrim.offset_bottom = 150 + 92
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.03, 0.02, 0.02, 0.66)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		ssb.set(k, 8)
	ssb.set("border_width_right", 3)
	ssb.border_color = Color(0.62, 0.20, 0.16, 0.9)
	scrim.add_theme_stylebox_override("panel", ssb)
	scrim.modulate = Color(1, 1, 1, 0.0)
	banner.add_child(scrim)
	_presence_bark_scrim = scrim
	var bark := Label.new()
	bark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bark.set_anchors_preset(Control.PRESET_FULL_RECT)
	bark.offset_left = 14; bark.offset_right = -14
	bark.offset_top = 6; bark.offset_bottom = -6
	bark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body != null:
		bark.add_theme_font_override("font", GameTheme.font_body)
	bark.add_theme_font_size_override("font_size", 16)
	bark.add_theme_color_override("font_color", Color(0.96, 0.92, 0.80))
	bark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	bark.add_theme_constant_override("outline_size", 4)
	scrim.add_child(bark)
	_presence_bark = bark


func _build_player_banner_diegetic() -> void:
	# Bottom-LEFT: Dürer's "Knight, Death and the Devil" (1513). Pinned to the
	# bottom edge so the player portrait + HP sit RIGHT under the field (under
	# "us" — the player) rather than floating mid-screen. The mana orb sits
	# directly under this column. H bumped 230→290 so the painted knight has
	# room to breathe — the previous height cropped most of the figure.
	# W matches the enemy plate (210) so the two plates read as a mirrored pair.
	const W := 210
	const H := 290
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

	# Portrait region: top down to where the HP bar starts (bottom 64px).
	const HP_TOP := -68
	var knight: Texture2D = load("res://assets/portraits/player_knight.png")
	if knight != null:
		var img := TextureRect.new()
		img.texture = knight
		img.anchor_left = 0.0
		img.anchor_right = 1.0
		img.anchor_top = 0.0
		img.anchor_bottom = 1.0
		img.offset_bottom = HP_TOP
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(img)

	# Painted border wraps the WHOLE plate (portrait + HP bar) so the bar reads
	# as the base of one framed panel — not a pill hanging outside the frame.
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

	# Bar inset inside the frame's painted border so it nests within the plate.
	var hp := _make_hp_medallion_diegetic(false, player_hp, player_max_hp)
	hp.anchor_left = 0.0
	hp.anchor_right = 1.0
	hp.anchor_top = 1.0
	hp.anchor_bottom = 1.0
	hp.offset_top = HP_TOP
	hp.offset_bottom = -16
	hp.offset_left = 14
	hp.offset_right = -14
	banner.add_child(hp)


func _make_hp_medallion_diegetic(is_enemy: bool, hp: int, max_hp: int) -> Control:
	# Wax-sealed HP plaque: dark backing + gilt rim (gold for player, blood-
	# red for enemy), HP numeral centered. Uses a single StyleBoxFlat panel
	# rather than a NinePatchRect — the 64px-tall medallion is too short for
	# the old 52px patch margins (corners overlapped, making the frame look
	# clipped and broken).
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rim: Color = Color(0.95, 0.40, 0.25, 1.0) if is_enemy \
		else Color(0.95, 0.78, 0.32, 1.0)
	var bg: Color = Color(0.16, 0.04, 0.04, 0.94) if is_enemy \
		else Color(0.14, 0.08, 0.03, 0.94)

	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = rim
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		s.set(k, 3)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(k, 14)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	disc.add_theme_stylebox_override("panel", s)

	# Draining health bar behind the numeral. _update_hud() already tweens a
	# "Fill" node's width on every HP change — it was just never created, so the
	# plate read as a bare number. The bar turns HP into a *visual*: a glance
	# tells you each side is nearly dead or barely scratched, the way Darkest
	# Dungeon / Cross Blitz health bars do. Left corners rounded to nest inside
	# the plate's rim; right edge is the draining frontier. full_w is stored as
	# meta so the update tween scales to the actual plate, not a magic constant.
	const PAD := 6.0
	# Both plates are 210-wide banners inset 14px each side → 182px medallion;
	# the fill spans the 170px interior (182 − 2·PAD). Stored as meta so
	# _update_hud scales the drain tween to this exact width.
	var full_w: float = 170.0
	var fill_color: Color = Color(0.86, 0.20, 0.16) if is_enemy \
		else Color(0.80, 0.18, 0.15)
	var fill := Panel.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left = 0.0
	fill.anchor_right = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left = PAD
	fill.offset_top = PAD
	fill.offset_bottom = -PAD
	fill.offset_right = PAD + full_w * clampf(float(hp) / float(max(max_hp, 1)), 0.0, 1.0)
	fill.set_meta("full_w", full_w)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 10
	fill_style.corner_radius_bottom_left = 10
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_right = 3
	# Brighter top edge = a glossy highlight line so the bar reads as a filled
	# liquid/gel, not a flat block.
	fill_style.border_width_top = 2
	fill_style.border_color = Color(fill_color.r + 0.18, fill_color.g + 0.14,
		fill_color.b + 0.12, 0.85)
	fill.add_theme_stylebox_override("panel", fill_style)
	disc.add_child(fill)

	# HP numeral rides ON TOP of the crimson fill bar, so it's ivory (not red —
	# red-on-red vanished) with a heavy black outline. 40pt so it dominates the
	# hierarchy the way Hearthstone / Cross Blitz HP numerals do.
	var lbl := _make_text_label("%d / %d" % [hp, max_hp], 40,
		Color(1.0, 0.96, 0.88))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	if GameTheme.font_title_black:
		lbl.add_theme_font_override("font", GameTheme.font_title_black)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	strip.offset_left = -300
	strip.offset_right = 300
	strip.offset_top = 12
	strip.offset_bottom = 126
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(strip)

	# Soft dark scrim behind the title — a radial that's darkest at the centre
	# and fades to nothing at the edges. The title text used to dissolve into the
	# busy hellscape painting (unreadable = unfinished-looking); this seats it on
	# a pool of shadow WITHOUT a hard frame (frameless matches the rest of the
	# HUD). Additive-free plain alpha so it only darkens the backdrop.
	var scrim_grad := Gradient.new()
	scrim_grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	scrim_grad.colors = PackedColorArray([
		Color(0.02, 0.01, 0.01, 0.62),
		Color(0.02, 0.01, 0.01, 0.30),
		Color(0.02, 0.01, 0.01, 0.0)])
	var scrim_tex := GradientTexture2D.new()
	scrim_tex.gradient = scrim_grad
	scrim_tex.fill = GradientTexture2D.FILL_RADIAL
	scrim_tex.fill_from = Vector2(0.5, 0.5)
	scrim_tex.fill_to = Vector2(1.0, 0.5)
	scrim_tex.width = 256
	scrim_tex.height = 128
	var scrim := TextureRect.new()
	scrim.texture = scrim_tex
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(scrim)

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(stack)

	# Encounter name — the dominant line. Bumped to 28pt display caps; this is
	# the "what fight is this" read.
	var encounter_text := _encounter_name if _encounter_name != "" \
		else "Floor %d" % RunState.current_floor
	_floor_label = _make_text_label(encounter_text, 28, GILT)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_floor_label.add_theme_constant_override("outline_size", 5)
	stack.add_child(_floor_label)

	# Thin gilt divider flourish with a centred diamond — a touch of craft under
	# the name without boxing it in. Drawn as a centered fixed-width strip.
	var rule := CenterContainer.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(rule)
	var rule_line := ColorRect.new()
	rule_line.custom_minimum_size = Vector2(170, 2)
	rule_line.color = Color(GILT.r, GILT.g, GILT.b, 0.5)
	rule_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_child(rule_line)

	_phase_label = _make_text_label("YOUR TURN", 17, IVORY)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_phase_label.add_theme_constant_override("outline_size", 4)
	stack.add_child(_phase_label)

	_turn_label = _make_text_label("Round 1", 12, Color(0.80, 0.72, 0.52))
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_turn_label)

	if _encounter_passive != "":
		var enc = EncounterDB.get_encounter(RunState.current_encounter_id)
		# The boss's passive IS its threat — promote it from faint text to a
		# persistent ominous plaque (dark scrim + crimson underline) so it reads as
		# a standing danger every turn, not a caption you scroll past.
		var threat_frame := PanelContainer.new()
		var threat_bg := StyleBoxFlat.new()
		threat_bg.bg_color = Color(0.12, 0.03, 0.03, 0.62)
		threat_bg.set_corner_radius_all(6)
		threat_bg.border_width_bottom = 2
		threat_bg.border_color = Color(0.82, 0.22, 0.16, 0.9)
		threat_bg.content_margin_left = 18
		threat_bg.content_margin_right = 18
		threat_bg.content_margin_top = 6
		threat_bg.content_margin_bottom = 7
		threat_frame.add_theme_stylebox_override("panel", threat_bg)
		threat_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var passive := _make_text_label(enc.get("passive_desc", ""), 18,
			Color(1.0, 0.80, 0.50))
		passive.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		passive.add_theme_constant_override("outline_size", 5)
		passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		passive.custom_minimum_size = Vector2(440, 0)
		threat_frame.add_child(passive)
		stack.add_child(threat_frame)


func _build_mana_post_diegetic() -> void:
	# Bottom-LEFT, directly RIGHT of the player banner: a faceted, glowing
	# mana CRYSTAL (replacing the old flat blue disc, which read as a generic
	# UI button). A cut sapphire silhouette — two mirrored facets with a
	# vertical bright→deep gradient, a center ridge, a top "table" light-catch,
	# a specular glint, a bright outline, and a soft radial aura behind it. The
	# whole gem breathes (slow scale pulse) and the aura throbs so the resource
	# feels arcane and alive. The count rides front-and-center as a single bold
	# numeral so it's still readable from across the screen.
	const GEM_W := 124
	const GEM_H := 152
	const HW := 42.0   # crystal half-width
	const HH := 56.0   # crystal half-height
	const CY := 62.0   # crystal center Y within the post
	var post := Control.new()
	post.anchor_left = 0.0
	post.anchor_right = 0.0
	post.anchor_top = 1.0
	post.anchor_bottom = 1.0
	# Sits just right of the player banner (banner W=210, x=14..224) with a
	# small gap; pinned to the bottom edge above the hand row.
	post.offset_left = 234
	post.offset_top = -(GEM_H + 10)
	post.offset_right = 234 + GEM_W
	post.offset_bottom = -10
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(post)

	# Soft radial aura behind the crystal — sells the "glowing gem" read and
	# bleeds a little blue light onto the dark frame. Pulses via a looping tween.
	var aura_grad := Gradient.new()
	aura_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	aura_grad.colors = PackedColorArray([
		Color(0.38, 0.68, 1.0, 0.60),
		Color(0.24, 0.50, 0.96, 0.24),
		Color(0.18, 0.40, 0.92, 0.0)])
	var aura_tex := GradientTexture2D.new()
	aura_tex.gradient = aura_grad
	aura_tex.fill = GradientTexture2D.FILL_RADIAL
	aura_tex.fill_from = Vector2(0.5, 0.5)
	aura_tex.fill_to = Vector2(1.0, 0.5)
	aura_tex.width = 160
	aura_tex.height = 160
	var aura := TextureRect.new()
	aura.texture = aura_tex
	aura.stretch_mode = TextureRect.STRETCH_SCALE
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.offset_left = GEM_W / 2.0 - 84
	aura.offset_right = GEM_W / 2.0 + 84
	aura.offset_top = CY - 84
	aura.offset_bottom = CY + 84
	aura.modulate.a = 0.7
	post.add_child(aura)

	# Crystal body lives in a Node2D so the facet Polygon2D / Line2D children
	# use centered local coords and the breathing scale pivots from the middle.
	var gem := Node2D.new()
	gem.position = Vector2(GEM_W / 2.0, CY)
	post.add_child(gem)

	# Hexagonal cut-gem silhouette (taller than wide → reads as a crystal).
	var T := Vector2(0, -HH)
	var UR := Vector2(HW, -HH * 0.40)
	var LR := Vector2(HW, HH * 0.40)
	var B := Vector2(0, HH)
	var LL := Vector2(-HW, HH * 0.40)
	var UL := Vector2(-HW, -HH * 0.40)
	var MT := Vector2(0, -HH * 0.18)  # top-table apex (center, just above mid)

	# Left facet — the shaded half. Vertical gradient bright→deep via per-vertex
	# colors; slightly dimmer than the right half so the center ridge catches.
	var left_facet := Polygon2D.new()
	left_facet.polygon = PackedVector2Array([T, UL, LL, B])
	left_facet.vertex_colors = PackedColorArray([
		Color(0.40, 0.70, 0.95), Color(0.12, 0.31, 0.70),
		Color(0.05, 0.12, 0.40), Color(0.04, 0.10, 0.34)])
	left_facet.antialiased = true
	gem.add_child(left_facet)

	# Right facet — the lit half (brighter).
	var right_facet := Polygon2D.new()
	right_facet.polygon = PackedVector2Array([T, UR, LR, B])
	right_facet.vertex_colors = PackedColorArray([
		Color(0.54, 0.86, 1.0), Color(0.18, 0.43, 0.90),
		Color(0.08, 0.20, 0.52), Color(0.05, 0.13, 0.42)])
	right_facet.antialiased = true
	gem.add_child(right_facet)

	# Top "table" facet — a bright translucent diamond catching the light at the
	# crown, so the gem reads as cut, not a flat blue lozenge.
	var table_hi := Polygon2D.new()
	table_hi.polygon = PackedVector2Array([UL, T, UR, MT])
	table_hi.color = Color(0.78, 0.95, 1.0, 0.34)
	table_hi.antialiased = true
	gem.add_child(table_hi)

	# Specular glint — a small white sliver on the upper-left crown.
	var glint := Polygon2D.new()
	glint.polygon = PackedVector2Array([
		Vector2(-9, -42), Vector2(-1, -35), Vector2(-7, -27), Vector2(-15, -33)])
	glint.color = Color(0.95, 0.99, 1.0, 0.72)
	glint.antialiased = true
	gem.add_child(glint)

	# Bright facet OUTLINE around the whole silhouette.
	var outline := Line2D.new()
	outline.points = PackedVector2Array([T, UR, LR, B, LL, UL, T])
	outline.width = 2.5
	outline.default_color = Color(0.64, 0.91, 1.0, 0.95)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.antialiased = true
	gem.add_child(outline)

	# Center ridge (T→B) + the two table edges (UL→MT→UR) → the "cut" lines.
	var ridge := Line2D.new()
	ridge.points = PackedVector2Array([T, B])
	ridge.width = 1.5
	ridge.default_color = Color(0.58, 0.84, 1.0, 0.50)
	ridge.antialiased = true
	gem.add_child(ridge)

	var table_lines := Line2D.new()
	table_lines.points = PackedVector2Array([UL, MT, UR])
	table_lines.width = 1.3
	table_lines.default_color = Color(0.62, 0.88, 1.0, 0.45)
	table_lines.antialiased = true
	gem.add_child(table_lines)

	# Big numeric — current / max mana, dominant readout, centered ON the gem.
	_mana_label = _make_text_label("%d / %d" % [player_mana, player_max_mana],
		37, Color(0.93, 0.98, 1.0))
	if GameTheme.font_title_black:
		_mana_label.add_theme_font_override("font", GameTheme.font_title_black)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mana_label.anchor_left = 0.0
	_mana_label.anchor_right = 0.0
	_mana_label.anchor_top = 0.0
	_mana_label.anchor_bottom = 0.0
	_mana_label.offset_left = 0
	_mana_label.offset_right = GEM_W
	_mana_label.offset_top = CY - HH
	_mana_label.offset_bottom = CY + HH
	_mana_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mana_label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.14, 0.95))
	_mana_label.add_theme_constant_override("outline_size", 6)
	post.add_child(_mana_label)

	# Caption below ("MANA") so newcomers can identify the resource.
	var caption := _make_text_label("MANA", 12, Color(0.58, 0.82, 1.0))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -22
	caption.offset_bottom = -6
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	caption.add_theme_constant_override("outline_size", 3)
	post.add_child(caption)

	# Arcane "breathing": the gem swells/settles and the aura throbs in sync, so
	# the resource feels magical and alive instead of a static icon.
	var breathe := gem.create_tween().set_loops()
	breathe.tween_property(gem, "scale", Vector2(1.035, 1.035), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(gem, "scale", Vector2(1.0, 1.0), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var aura_tw := aura.create_tween().set_loops()
	aura_tw.tween_property(aura, "modulate:a", 0.95, 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	aura_tw.tween_property(aura, "modulate:a", 0.55, 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_piles_diegetic() -> void:
	# Deck + Discard sit side-by-side in the LEFT column below the relic
	# grid (top-left). Previously deck-left / discard-right on opposite
	# screen edges, which made tracking your draw economy harder than
	# necessary — STS keeps them visually next to each other so you can
	# glance at both counts in one read. The left column is the only large
	# free vertical strip after the encounter scroll was removed.
	# Compact card-stacks, side by side. Halved from the old 100×122 slabs (which
	# read as two full extra cards parked in the corner) to tucked 62×80 stacks
	# with a count badge — the StS/Hearthstone corner-pile scale. Caption sits
	# under each. 18px of vertical room reserved below the stack for the caption.
	const PILE_W := 62
	const PILE_H := 98
	const COL_LEFT := 16
	const COL_TOP := 128
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
	disc_box.offset_left = COL_LEFT + PILE_W + 18
	disc_box.offset_right = COL_LEFT + PILE_W * 2 + 18
	disc_box.offset_top = COL_TOP
	disc_box.offset_bottom = COL_TOP + PILE_H
	_hud_layer.add_child(disc_box)


func _build_potion_bar_diegetic() -> void:
	# Three potion slots just above the player banner — clusters consumables
	# with player resources (HP/portrait/mana) on the bottom-left, matching
	# the StS convention of "potions near player HP". Each filled slot is a
	# button that uses the potion (resolves immediately for non-targeted
	# effects, or enters potion-targeting for Bottled Fury et al). Empty
	# slots render as a shaded placeholder.
	const SLOT := 52
	const GAP := 6
	const COL_LEFT := 14
	var bar := Control.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 0.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = COL_LEFT
	bar.offset_right = COL_LEFT + (SLOT + GAP) * RunState.MAX_POTIONS
	bar.offset_top = -378  # 68px tall (SLOT + 16), 10px above player banner top
	bar.offset_bottom = -310
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(bar)
	_potion_bar_root = bar
	_rebuild_potion_bar()


func _rebuild_potion_bar() -> void:
	if _potion_bar_root == null:
		return
	for child in _potion_bar_root.get_children():
		child.queue_free()
	const SLOT := 52
	const GAP := 6
	for i in range(RunState.MAX_POTIONS):
		var pid: String = RunState.potions[i] if i < RunState.potions.size() else ""
		var slot := _make_combat_potion_slot(pid, i)
		slot.position = Vector2(i * (SLOT + GAP), 0)
		slot.size = Vector2(SLOT, SLOT)
		_potion_bar_root.add_child(slot)


func _make_combat_potion_slot(pid: String, index: int) -> Control:
	const SLOT := 52
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(SLOT, SLOT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	# Dark backing so the icon reads on any background.
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.03, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(bg)

	if pid == "":
		# Empty placeholder, slightly transparent icon.
		var ph := TextureRect.new()
		ph.texture = GameTheme.tex_hud_potion
		ph.modulate = Color(0.40, 0.35, 0.30, 0.40)
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		ph.offset_left = 6; ph.offset_right = -6
		ph.offset_top = 6; ph.offset_bottom = -6
		ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(ph)
		return wrapper

	var data: Dictionary = PotionDB.get_potion(pid)
	var icon: Texture2D = PotionDB.icon_for(pid)
	var tint: Color = data.get("color", Color.WHITE)

	var img := TextureRect.new()
	img.texture = icon
	img.modulate = tint
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.offset_left = 6; img.offset_right = -6
	img.offset_top = 6; img.offset_bottom = -6
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(img)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = "%s\n%s" % [data.get("name", pid), data.get("desc", "")]
	btn.pressed.connect(func():
		_use_combat_potion(index)
	)
	wrapper.add_child(btn)
	return wrapper


func _make_pile_panel_diegetic(caption_text: String, kind: int) -> Control:
	# Compact, frameless card-stack. The card-back art occupies the top
	# (caption reserved 18px at the bottom). Two offset "stack" rectangles behind
	# the main back give the pile real physical thickness — it reads as a deck of
	# many cards, not one flat panel — and a soft drop shadow grounds it. The
	# count rides in a dark badge over the bottom-right corner (Hearthstone/StS
	# convention) instead of being blown up to fill the whole panel. No gilt
	# NinePatch frame (that "cage everything in gold" trim was dropped from the
	# board; the piles match). Sets _deck_count_label / _discard_count_label.
	var pile := Control.new()
	pile.mouse_filter = Control.MOUSE_FILTER_PASS

	# Card-art region: everything above the caption strip.
	var art := Control.new()
	art.name = "Art"
	art.anchor_left = 0.0
	art.anchor_right = 1.0
	art.anchor_top = 0.0
	art.anchor_bottom = 1.0
	art.offset_bottom = -18
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.add_child(art)

	var card_back_path := "res://assets/ui/card_back.png"
	var cb_tex: Texture2D = null
	if ResourceLoader.exists(card_back_path):
		cb_tex = load(card_back_path)

	# Two stack cards behind the main one, nudged up-left, progressively darker —
	# a cheap, convincing "this is a thick deck" read. Drawn first so the front
	# card sits on top.
	for layer_i in [2, 1]:
		var off := float(layer_i) * 3.0
		var stack: Control
		if cb_tex != null:
			var tex_stack := TextureRect.new()
			tex_stack.texture = cb_tex
			tex_stack.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_stack.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex_stack.modulate = Color(0.45, 0.40, 0.34, 1.0)  # darkened, recedes
			stack = tex_stack
		else:
			var rect_stack := ColorRect.new()
			rect_stack.color = Color(0.06, 0.045, 0.03, 0.92)
			stack = rect_stack
		stack.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.offset_left = -off
		stack.offset_top = -off
		stack.offset_right = -off
		stack.offset_bottom = -off
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(stack)

	# Soft drop shadow under the front card so the stack sits above the board.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.06, 0.04, 0.03, 0.96)
	shadow_style.set_corner_radius_all(4)
	shadow_style.shadow_color = Color(0, 0, 0, 0.55)
	shadow_style.shadow_size = 7
	shadow_style.shadow_offset = Vector2(0, 4)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	art.add_child(shadow)

	# Front card back.
	if cb_tex != null:
		var back := TextureRect.new()
		back.texture = cb_tex
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(back)

	# Count badge — dark disc clipped to the bottom-right corner of the card.
	var badge := Panel.new()
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -30
	badge.offset_top = -30
	badge.offset_right = -2
	badge.offset_bottom = -2
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.08, 0.05, 0.035, 0.96)
	badge_style.border_color = Color(GILT.r, GILT.g, GILT.b, 0.85)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(14)
	badge_style.shadow_color = Color(0, 0, 0, 0.5)
	badge_style.shadow_size = 4
	badge.add_theme_stylebox_override("panel", badge_style)
	art.add_child(badge)

	var count_label := _make_text_label("0", 18, IVORY)
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_title_black:
		count_label.add_theme_font_override("font", GameTheme.font_title_black)
	badge.add_child(count_label)

	var caption := _make_text_label(caption_text, 10, GILT)
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -16
	caption.offset_bottom = 0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.add_child(caption)

	if kind == 0:
		_deck_count_label = count_label
	else:
		_discard_count_label = count_label

	# Transparent click target over the whole pile to open the viewer overlay.
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	# Headers use the title font (Cinzel) for a chiseled, engraved look; smaller
	# HUD text uses the body font (Nunito) for readability at small sizes.
	if sz >= 22 and GameTheme.font_title:
		lbl.add_theme_font_override("font", GameTheme.font_title)
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
	{"name": "Sacrifice", "desc": "Certain cards and abilities destroy one of your own creatures as a cost — never a free action. The dying creature's On-Death effect still triggers."},
	{"name": "Banking", "desc": "Carry up to 2 unused mana into next turn. Pay it like normal mana."},
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
	# Uses the shared GameTheme.make_settings_gear() helper so the gear looks
	# identical across all scenes (Combat / Map / Shop / Rest / Event / Reward).
	GameTheme.make_settings_gear(_hud_layer)


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
	# 3 columns: 3×64 + 2×6 = 204px wide, x=14..218 — stays clear of the board's
	# left edge (x=272). 4 columns (274px) poked ~16px into the leftmost lane.
	_relic_panel.columns = 3
	_relic_panel.anchor_left = 0.0
	_relic_panel.anchor_right = 0.0
	_relic_panel.anchor_top = 0.0
	_relic_panel.anchor_bottom = 0.0
	_relic_panel.offset_left = 14
	_relic_panel.offset_right = 218
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
	_relic_counter_badges.clear()
	for relic_id in RunState.relics:
		if RelicDB.get_relic(relic_id).is_empty():
			continue
		# Ornate tier-glow chip lives in GameTheme so the HUD, shop cards,
		# starting-pick screen, and main-menu relic list all share one frame
		# look. 64×64 (bumped from 50) so on-field relics read clearly next
		# to the deck/discard piles; 3 across in the top-left column (sized
		# to stay clear of the board's left edge at x=272).
		var chip := GameTheme.make_relic_chip(relic_id, 64)
		_relic_panel.add_child(chip)
		# Counter relics get a live numeral badge across the bottom of the chip.
		if relic_id in COUNTER_RELICS:
			var badge := _make_relic_counter_badge()
			chip.add_child(badge)
			_relic_counter_badges[relic_id] = badge
	_refresh_relic_counters()


# Relics that expose a live counter on their HUD chip. Each maps to a case in
# _relic_counter_text below.
const COUNTER_RELICS := ["pen_nib", "hourglass_sigil", "inkpot_of_many",
	"soul_ledger", "stygian_soul", "mana_drunkard", "sundial", "glowing_hand"]


func _make_relic_counter_badge() -> Label:
	## Small gilt-on-dark numeral strip across the bottom of a relic HUD chip.
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 13)
	if GameTheme.font_stat:
		badge.add_theme_font_override("font", GameTheme.font_stat)
	badge.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark rounded backing so the numerals read over any relic art.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.04, 0.88)
	bg.border_color = GameTheme.GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		bg.set(k, 1)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		bg.set(k, 5)
	badge.add_theme_stylebox_override("normal", bg)
	# Anchor an ~18px strip across the bottom of the 64px chip.
	badge.anchor_left = 0.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = 4
	badge.offset_right = -4
	badge.offset_top = -19
	badge.offset_bottom = -2
	return badge


func _relic_counter_text(relic_id: String) -> String:
	## Live counter string for a relic's HUD badge, or "" to hide it.
	match relic_id:
		"pen_nib":
			return "%d/%d" % [_pen_nib_counter,
				int(RelicDB.get_relic("pen_nib").get("value", 10))]
		"hourglass_sigil":
			return "%d/%d" % [_hourglass_pending,
				int(RelicDB.get_relic("hourglass_sigil").get("value", 5))]
		"inkpot_of_many":
			return "%d/%d" % [_inkpot_counter,
				int(RelicDB.get_relic("inkpot_of_many").get("value", 5))]
		"soul_ledger":
			return "%d/%d" % [_soul_ledger_counter,
				int(RelicDB.get_relic("soul_ledger").get("value", 5))]
		"stygian_soul":
			return "%d/%d" % [_stygian_soul_healed,
				int(RelicDB.get_relic("stygian_soul").get("value", 5))]
		"mana_drunkard":
			# Grants at a 2-turn spend-all-mana streak (hardcoded in turn-end).
			return "%d/2" % _mana_drunkard_streak
		"sundial":
			# Fires every 3 deck shuffles; show progress within the current cycle.
			return "%d/3" % (_sundial_count % 3)
		"glowing_hand":
			var g: int = mini(int(RelicDB.get_relic("glowing_hand").get("value", 5)),
				_glowing_hand_spells_cast)
			return "+%d" % g if g > 0 else ""
	return ""


func _refresh_relic_counters() -> void:
	for relic_id in _relic_counter_badges:
		var badge = _relic_counter_badges[relic_id]
		if not is_instance_valid(badge):
			continue
		var t := _relic_counter_text(relic_id)
		badge.text = t
		badge.visible = t != ""


func _update_hud() -> void:
	_player_hp_label.text = "%d / %d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "%d / %d" % [enemy_hp, enemy_max_hp]
	_refresh_incoming_damage_chip()
	# Update HP bar fills (inset by 1px from frame border)
	var p_fill = _player_hp_label.get_parent().get_node_or_null("Fill")
	if p_fill:
		var p_full: float = p_fill.get_meta("full_w", 184.0)
		var p_target := p_full * clampf(float(player_hp) / float(player_max_hp), 0.0, 1.0)
		if _player_hp_tween != null and _player_hp_tween.is_valid():
			_player_hp_tween.kill()
		_player_hp_tween = p_fill.create_tween()
		_player_hp_tween.tween_property(p_fill, "size:x", p_target, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var e_fill = _enemy_hp_label.get_parent().get_node_or_null("Fill")
	if e_fill:
		var e_full: float = e_fill.get_meta("full_w", 204.0)
		var e_target := e_full * clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
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
	_refresh_relic_counters()
	# JUICE: re-evaluate low-HP dread and enemy threat outlines on every HUD
	# refresh (i.e. after every damage / heal / board change).
	_update_low_hp_dread()
	_refresh_threat_flags()
	_turn_label.text = "Round %d" % round_number
	_update_presence_hp()
	if _deck_count_label:
		# Frozen Eye: append the top card's name to the count so the player can
		# plan around the next draw. Keep the count up front so the chip's main
		# read is unchanged for players without the relic.
		var deck_text: String = str(_player_draw_pile.size())
		if _has_relic("frozen_eye") and not _player_draw_pile.is_empty():
			var top_entry: String = _player_draw_pile[0]
			var top_id: String = _entry_id(top_entry)
			var top_name: String = CardDB.get_card_data(top_id).get("name", top_id)
			deck_text = "%s · next: %s" % [deck_text, top_name]
		_deck_count_label.text = deck_text
	if _discard_count_label:
		_discard_count_label.text = str(_player_discard_pile.size())
	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "YOUR TURN"
			_phase_label.add_theme_color_override("font_color", IVORY)
		Phase.RESOLVING:
			_phase_label.text = "FIGHT"
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


# ─────────────────────────────────────────────────────────────────────────
#  Magnitude-scaled combat hit feedback (JUICE)
#  Card2D.take_damage routes here so every creature hit shakes the screen in
#  proportion to the blow — a 1-dmg plink barely ripples, a 7-dmg haymaker
#  rocks the board. Centralized so both armor-respecting and armor-bypass hits
#  feel consistent. Purely additive: no game logic, just shake.
# ─────────────────────────────────────────────────────────────────────────

func creature_hit_feedback(amount: int) -> void:
	# Called by Card2D after a creature absorbs a hit. Light hits get a whisper of
	# shake; bigger hits ramp up so the player FEELS the weight without the screen
	# jackhammering on chip damage. Kept modest on purpose because the combat
	# cascade ALSO fires an explicit screen_shake on heavy/lethal blows
	# (_creature_attacks_creature etc.) — this layers under that, it doesn't
	# replace it. 1 dmg → ~1.6px, 3 dmg → ~3.5px, 6+ dmg → capped ~6.5px.
	if amount <= 0:
		return
	var mag: float = clampf(0.9 + float(amount) * 0.95, 1.6, 6.5)
	screen_shake(mag)


func _play_face_damage_flash(amount: int) -> void:
	# A layered crimson vignette pulse for player-face damage — louder than the
	# generic screen_flash so a hit to the hero never gets lost. Two stacked
	# ColorRects: a brief full-screen wash (alpha scales with damage) plus a
	# thick red edge frame that snaps in and fades, reading as "blood at the
	# edges of your vision." Both self-free; pure overlay, no game logic.
	var parent: Node = _hud_layer if _hud_layer != null else self
	var wash_a: float = clampf(0.18 + float(amount) * 0.045, 0.20, 0.42)
	# Full-screen red wash.
	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(0.72, 0.06, 0.04, wash_a)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.z_index = 232
	parent.add_child(wash)
	var tw := wash.create_tween()
	tw.tween_property(wash, "color:a", 0.0, 0.34).set_ease(Tween.EASE_IN)
	tw.tween_callback(wash.queue_free)
	# Hard red edge frame that hits + recedes for the "took a real blow" punch.
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 233
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.85, 0.07, 0.05, clampf(0.45 + float(amount) * 0.04, 0.45, 0.85))
	sb.set_border_width_all(int(clampf(70.0 + float(amount) * 12.0, 80.0, 180.0)))
	sb.shadow_color = Color(0.9, 0.08, 0.05, 0.5)
	sb.shadow_size = 50
	frame.add_theme_stylebox_override("panel", sb)
	parent.add_child(frame)
	var ft := frame.create_tween()
	ft.tween_property(frame, "modulate:a", 0.0, 0.40).set_ease(Tween.EASE_IN)
	ft.tween_callback(frame.queue_free)


func _punch_label(lbl: Control, amount_scale: float) -> void:
	# Quick scale-pop on a HUD label (HP counter) so a value change reads as an
	# impact, not a silent tick. Restores to the label's resting scale.
	if lbl == null or not is_instance_valid(lbl):
		return
	var rest := lbl.scale
	lbl.pivot_offset = lbl.size * 0.5
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", rest * amount_scale, 0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", rest, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ─────────────────────────────────────────────────────────────────────────
#  Notable-death weight (JUICE)
#  A heavy creature dying, or several creatures dying in the same frame, earns
#  an extra punctuation of shake on top of the per-creature death burst. Frame-
#  coalesced so a board wipe produces a single emphasis rather than a stutter.
#  Runs synchronously (no await) so it never desyncs the attack cascade — the
#  attack functions already supply the awaited HITSTOP_BEAT after a kill.
# ─────────────────────────────────────────────────────────────────────────

func _note_death(card: Control, _was_enemy: bool) -> void:
	_deaths_this_frame += 1
	var bulk: int = 1
	if is_instance_valid(card):
		bulk = maxi(int(card.card_data.get("atk", 1)), int(card.card_data.get("hp", 1)))
	# Notable if it's the 2nd+ death this frame (a wipe) OR a chunky body (a
	# 6/6+ bruiser, an elite/boss centerpiece). Emphasis fires once per frame.
	var notable: bool = _deaths_this_frame >= 2 or bulk >= 6
	# Boss / elite encounters: any death of a sizable enemy reads as a milestone.
	if not notable and _was_enemy and bulk >= 4:
		var enc_type := String(RunState.current_node_type)
		if enc_type == "boss" or enc_type == "elite":
			notable = true
	if notable and not _death_hitstop_armed:
		_death_hitstop_armed = true
		# A stronger jolt than the per-hit shake, scaled up for a multi-kill.
		var mag: float = clampf(7.0 + float(_deaths_this_frame) * 2.5 + float(bulk) * 0.6, 8.0, 18.0)
		screen_shake(mag)
		_reset_death_frame_counter.call_deferred()

func _reset_death_frame_counter() -> void:
	# Deferred to end-of-frame so all deaths in one combat step share the same
	# emphasis, then the gate reopens for the next frame's deaths.
	_deaths_this_frame = 0
	_death_hitstop_armed = false


# ─────────────────────────────────────────────────────────────────────────
#  Low-HP dread (JUICE)
#  When the player drops to/below a danger threshold, a red screen-edge
#  vignette breathes around the frame and a soft heartbeat plays. The effect
#  removes itself the instant HP recovers above the line. Driven from
#  _update_hud so every damage / heal event re-evaluates it.
# ─────────────────────────────────────────────────────────────────────────

const LOW_HP_ABS_THRESHOLD: int = 6        # at/below this HP the dread kicks in
const LOW_HP_PCT_THRESHOLD: float = 0.25   # ...or at/below 25% of max, whichever is higher

func _low_hp_danger_line() -> int:
	# The HP value at/below which dread activates: the larger of the flat floor
	# and the 25%-of-max line, so a 25-max hero and a 40-max hero both feel it.
	return maxi(LOW_HP_ABS_THRESHOLD, int(ceil(float(player_max_hp) * LOW_HP_PCT_THRESHOLD)))

func _update_low_hp_dread() -> void:
	# Toggle the persistent dread overlay based on current HP vs the danger line.
	if _hud_layer == null:
		return
	var in_danger: bool = player_hp > 0 and player_hp <= _low_hp_danger_line()
	if in_danger and not _low_hp_active:
		_start_low_hp_dread()
	elif not in_danger and _low_hp_active:
		_stop_low_hp_dread()
	elif in_danger and _low_hp_active:
		# Pitch the heartbeat up a touch as HP approaches zero so the dread
		# intensifies on the final sliver of life.
		var t: float = clampf(float(player_hp) / float(maxi(1, _low_hp_danger_line())), 0.0, 1.0)
		_low_hp_vignette_peak = lerpf(0.50, 0.30, t)  # closer to 0 HP → deeper red

func _start_low_hp_dread() -> void:
	_low_hp_active = true
	_low_hp_vignette_peak = 0.42
	# Build the vignette once. Asset-free edge-darkening: a Panel whose StyleBox
	# has a thick red border + shadow hugging the screen edge, leaving the center
	# clear. Reads as "blood creeping in at the edges of vision." Pulses alpha on
	# a looping tween so it breathes.
	if not is_instance_valid(_low_hp_vignette):
		var pan := Panel.new()
		pan.name = "LowHpVignette"
		pan.set_anchors_preset(Control.PRESET_FULL_RECT)
		pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pan.z_index = 230  # above board, below banners (245) and floating numbers
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)            # transparent center
		sb.border_color = Color(0.62, 0.04, 0.03, 1.0)
		sb.set_border_width_all(120)               # thick red frame = edge vignette
		sb.shadow_color = Color(0.85, 0.05, 0.04, 0.55)
		sb.shadow_size = 60
		# Soft inner falloff so the red bleeds toward the center instead of a hard line.
		sb.anti_aliasing = true
		pan.add_theme_stylebox_override("panel", sb)
		pan.modulate = Color(1, 1, 1, 0.0)
		_hud_layer.add_child(pan)
		_low_hp_vignette = pan
	# Looping breathe tween: fade the whole vignette in/out so it pulses like a
	# pulse. Uses a method tween so the peak can drift with HP (set above).
	if _low_hp_tween != null and _low_hp_tween.is_valid():
		_low_hp_tween.kill()
	_low_hp_vignette.visible = true
	_low_hp_tween = create_tween().set_loops()
	_low_hp_tween.tween_method(_set_low_hp_vignette_alpha, 0.12, 1.0, 0.62) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_low_hp_tween.tween_callback(_low_hp_heartbeat)
	_low_hp_tween.tween_method(_set_low_hp_vignette_alpha, 1.0, 0.12, 0.62) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_low_hp_tween.tween_interval(0.10)

func _set_low_hp_vignette_alpha(t: float) -> void:
	# t in [0,1] → scaled by the current peak so the breathe deepens near death.
	if is_instance_valid(_low_hp_vignette):
		_low_hp_vignette.modulate.a = t * _low_hp_vignette_peak

func _low_hp_heartbeat() -> void:
	# Soft thud at the crest of each pulse. Reuses the existing "hit_hero" cue at
	# low volume + low pitch so it reads as a muffled heartbeat, not a strike.
	# (No dedicated heartbeat SFX exists — flagged in the report.)
	if AudioBank != null and AudioBank.has_sfx("hit_hero"):
		AudioBank.play_sfx("hit_hero", 0.02, -16.0)

func _stop_low_hp_dread() -> void:
	_low_hp_active = false
	if _low_hp_tween != null and _low_hp_tween.is_valid():
		_low_hp_tween.kill()
		_low_hp_tween = null
	if is_instance_valid(_low_hp_vignette):
		var v := _low_hp_vignette
		var tw := create_tween()
		tw.tween_property(v, "modulate:a", 0.0, 0.35)
		tw.tween_callback(func(): if is_instance_valid(v): v.visible = false)


# ─────────────────────────────────────────────────────────────────────────
#  Threat flagging (JUICE)
#  Enemy creatures that pose an immediate threat — they will smash the player's
#  face this round, or they swing for a heavy blow — get a pulsing crimson
#  outline so the danger is visible at a glance, not buried in the numbers.
#  Re-evaluated whenever the board changes (via _update_hud).
# ─────────────────────────────────────────────────────────────────────────

const THREAT_HEAVY_ATK: int = 5   # an attacker swinging this hard gets flagged even if blocked

func _clear_threat_flags() -> void:
	# Drop every enemy threat outline (e.g. when combat begins resolving).
	for row in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(true, row)
		for lane in range(LANES_PER_ROW):
			var c = arr[lane]
			if c != null and is_instance_valid(c) and c.has_method("set_threat_flagged"):
				c.set_threat_flagged(false)

func _refresh_threat_flags() -> void:
	# Only meaningful during the player's turn — once combat resolves the board
	# is mid-flux. Skip outside PLAYER_TURN so flags don't flicker during the
	# attack cascade.
	if phase != Phase.PLAYER_TURN:
		return
	for row in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(true, row)
		for lane in range(LANES_PER_ROW):
			var c = arr[lane]
			if c == null or not is_instance_valid(c):
				continue
			if not c.has_method("set_threat_flagged"):
				continue
			var threat: bool = _enemy_is_threatening(c, lane, row)
			c.set_threat_flagged(threat)

func _enemy_is_threatening(c: Control, lane: int, row: int) -> bool:
	# A creature is "threatening" if it can attack and either (a) its column is
	# open so it will hit the player's face this round, or (b) it swings for a
	# heavy blow regardless of target. Structures / stunned / frozen never flag.
	if c.has_keyword("structure"):
		return false
	if not c.can_attack():
		return false
	var intent: String = String(c.get_meta("current_intent", "ATK"))
	# Non-attacking intents (GUARD/HEAL/RETREAT/SUMMON) aren't an incoming hit.
	if intent != "ATK" and intent != "CHARGE" and intent != "ENRAGE":
		return false
	var atk: int = c.effective_atk()
	if atk <= 0:
		return false
	# Heavy hitter — always worth flagging.
	if atk >= THREAT_HEAVY_ATK:
		return true
	# Face threat: both player slots in this column are empty, so the blow lands
	# on the hero. Back-row attacker blocked by its own front partner can't reach.
	if row == ROW_BACK and _enemy_field[lane] != null:
		return false
	if _player_field[lane] == null and _player_back[lane] == null:
		return true
	return false


func _refresh_hand_affordability() -> void:
	# Tell every card in the hand whether the current mana pool can pay its cost.
	# Card2D handles the visual change (dim when not affordable).
	#
	# Uses _effective_cost so the dim/glow state respects active mutators
	# (Taxed bumps spell cost), Ember Crown (free first spell), and Ironclad
	# Veteran discounts. Previously read raw card_data.cost — a 1-cost spell
	# under Taxed +1 would falsely look affordable at 1 mana and then fail at
	# play time with "Not enough mana!".
	for card in _hand:
		if card == null or not is_instance_valid(card):
			continue
		if not card.has_method("set_affordable"):
			continue
		var eff: int = _effective_cost(card)
		card.set_affordable(player_mana >= eff)
		# Also push the effective cost into the cost orb so the orb's number
		# matches what playing the card will actually charge.
		if card.has_method("set_display_cost"):
			card.set_display_cost(eff)


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
	if spell_type == "damage" or (spell_type == "custom" and custom_id in ["reckless_charge", "hex", "pillage", "fuel_the_pyre", "holy_smite", "shove", "slash", "smite_spell", "quick_shot"]):
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
	elif spell_type == "buff_hp":
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
	# matches the actual outcome. Worn Spellbook adds 1 to plain "damage" and
	# to every direct-damage custom spell that opts in inside
	# _resolve_custom_spell. Armored absorbs 1 per hit (clamped to 0).
	var spell_dmg_bonus: int = 1 if _has_relic("worn_spellbook") else 0
	var dmg := raw_value
	if spell_type == "damage" and _has_relic("worn_spellbook"):
		dmg += 1
	if custom_id == "reckless_charge":
		dmg = 3 + spell_dmg_bonus
	elif custom_id == "hex":
		dmg = 2  # Debuff with incidental damage — intentionally not buffed.
	elif custom_id == "pillage":
		dmg = 3 + spell_dmg_bonus
	elif custom_id == "shove":
		dmg = 2 + spell_dmg_bonus
	elif custom_id == "slash":
		dmg = 3 + spell_dmg_bonus
	elif custom_id == "smite_spell":
		dmg = 6 + spell_dmg_bonus
	elif custom_id == "quick_shot":
		dmg = 1 + spell_dmg_bonus
	elif custom_id == "fuel_the_pyre":
		dmg = 999  # Kills target outright (sets up "LETHAL!" automatically)
	elif custom_id == "holy_smite":
		# Equal to the target's missing HP — full creature takes nothing.
		dmg = maxi(0, int(card.card_data.get("hp", card.current_hp)) - int(card.current_hp))
	if card.has_method("has_keyword") and card.has_keyword("armored"):
		# Match Card2D.take_damage: Fortress Stone makes the player's own
		# armored creatures block 2 instead of 1. Without this, the predicted-
		# damage HUD over an armored ally disagreed with what actually landed.
		var reduction := 1
		if not card.is_opponent and _has_relic("fortress_stone"):
			reduction = 2
		dmg = maxi(0, dmg - reduction)
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


# Tier-2 family map. Each spell card id is routed to one of six visual families
# (FIRE / SHOCK / BLIGHT / BLESSING / EARTH / MIND), each with its own particle
# preset + accent (screen flash, lightning Line2D, target pulse, screen shake).
# Spells not listed here fall back to the legacy color-by-type burst so adding a
# new spell never breaks visually — it just lands without family flavor until
# someone tags it.
const SPELL_FAMILIES := {
	# FIRE — rising orange cone + warm screen flash
	"flame_bolt": "fire", "fireball": "fire", "inferno": "fire",
	"fuel_the_pyre": "fire",
	# SHOCK — white-blue lightning bolt + brief flash
	"lightning": "shock", "holy_smite": "shock", "time_snare": "shock",
	# BLIGHT — purple drift particles + magenta core
	"dark_pact": "blight", "mass_grave": "blight", "bloodletting": "blight",
	"apocalypse": "blight", "curse": "blight", "unholy_bargain": "blight",
	"blood_tithe": "blight", "grave_robbery": "blight", "offering": "blight",
	# BLESSING — golden upward shimmer + soft warm flash
	"patch_up": "blessing", "lay_on_hands": "blessing", "mending_light": "blessing",
	"battle_hymn": "blessing", "inspire": "blessing", "war_cry": "blessing",
	"second_wind": "blessing", "shield_wall": "blessing",
	"kings_command": "blessing",
	# EARTH — brown dust + Y-axis screen shake
	"earthquake": "earth", "shove": "earth", "reposition": "earth",
	"cataclysm": "earth", "overwhelming_force": "earth", "barricade": "earth",
	# MIND — pale cool sweep + target outline pulse
	"concentrate": "mind", "adrenaline": "mind", "gambit": "mind",
	"echo_spell": "mind", "banish": "mind", "soul_swap": "mind",
	"grave_pact": "mind", "provision": "mind", "scrap": "mind", "turbo": "mind",
	"recycle": "mind", "ambush": "mind", "war_chant": "mind",
	"reckless_charge": "mind",
}


func _play_spell_cast_vfx(card_data: Dictionary, target: Control) -> void:
	# Route a spell to its visual burst. The family map (SPELL_FAMILIES) takes
	# precedence — if the spell's card id is listed, dispatch the matching Tier-2
	# family VFX. Otherwise fall back to the legacy color-by-spell-type burst
	# (covers any spell author who hasn't been tagged into a family yet).
	var spell: Dictionary = card_data.get("spell", {})
	var spell_type: String = spell.get("type", "")
	var card_id: String = card_data.get("id", "")
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var pos := center
	if target != null and is_instance_valid(target):
		pos = target.get_global_rect().get_center()
	# Position adjustments for AoE / face-targeting spells — they should burst at
	# a meaningful spot, not the default center, when there's no explicit target.
	match spell_type:
		"damage_face":
			if _enemy_hp_label != null:
				pos = _enemy_hp_label.get_global_rect().get_center()
		"damage_all_enemies":
			if target == null:
				pos = Vector2(vp.x * 0.5, vp.y * 0.35)
		"damage_all":
			if target == null:
				pos = center
		"draw":
			if target == null:
				pos = Vector2(120.0, vp.y * 0.60)

	var family: String = SPELL_FAMILIES.get(card_id, "")
	if family != "":
		match family:
			"fire":
				_vfx_fire(pos)
			"shock":
				_vfx_shock(pos)
			"blight":
				_vfx_blight(pos)
			"blessing":
				_vfx_blessing(pos)
			"earth":
				_vfx_earth(pos)
			"mind":
				_vfx_mind(pos, target)
	else:
		# Legacy fallback — keep the old color burst so unfamilied spells still
		# read as "cast".
		spawn_spell_burst(pos, _legacy_spell_color(spell_type))
	if AudioBank != null:
		AudioBank.play_sfx("spell_cast")


func _legacy_spell_color(spell_type: String) -> Color:
	# Color table the legacy `_play_spell_cast_vfx` switch used. Kept as a helper
	# so any spell not (yet) listed in SPELL_FAMILIES still gets a sensible color
	# instead of a flat white burst.
	match spell_type:
		"damage":
			return Color(1.0, 0.40, 0.18)
		"damage_face", "damage_all_enemies":
			return Color(1.0, 0.30, 0.12)
		"damage_all":
			return Color(1.0, 0.20, 0.18)
		"buff_atk", "buff_all_atk":
			return Color(1.0, 0.85, 0.30)
		"buff_hp", "heal":
			return Color(0.50, 1.0, 0.55)
		"draw":
			return Color(0.55, 0.78, 1.0)
		"custom":
			return Color(0.80, 0.55, 1.0)
		_:
			return Color(1.0, 0.70, 0.30)


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


# =====================================================================
#  TIER 2 — Spell family VFX
#  Six families, each a CPUParticles2D preset + optional accent (screen
#  flash, lightning Line2D, target outline pulse, screen shake).
#  All CPU/Control-only — no shaders, so the GL Compatibility renderer is
#  safe. Every helper queues its own cleanup; no node leaks.
# =====================================================================

func _spawn_family_particles(global_pos: Vector2, params: Dictionary) -> void:
	# Generic CPUParticles2D emitter. `params` keys mirror the Godot 4
	# CPUParticles2D property names but with Pythonic min/max suffixes so the
	# six per-family preset dicts above stay readable.
	var burst := CPUParticles2D.new()
	burst.position = global_pos
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emitting = true
	burst.amount = int(params.get("amount", 18))
	var life: float = float(params.get("lifetime", 0.6))
	burst.lifetime = life
	burst.direction = params.get("direction", Vector2(0, -1))
	burst.spread = float(params.get("spread", 90.0))
	burst.initial_velocity_min = float(params.get("velocity_min", 90.0))
	burst.initial_velocity_max = float(params.get("velocity_max", 210.0))
	burst.gravity = params.get("gravity", Vector2(0, 140.0))
	burst.scale_amount_min = float(params.get("scale_min", 2.0))
	burst.scale_amount_max = float(params.get("scale_max", 4.5))
	burst.color = params.get("color", Color.WHITE)
	burst.z_index = int(params.get("z_index", 150))
	var parent: Node = _hud_layer if _hud_layer != null else self
	parent.add_child(burst)
	get_tree().create_timer(life + 0.5).timeout.connect(burst.queue_free)


func _vfx_fire(target_global: Vector2) -> void:
	# Rising orange cone + a hotter inner core + warm screen tint.
	_spawn_family_particles(target_global, {
		"amount": 24, "lifetime": 0.7,
		"direction": Vector2(0, -1), "spread": 35.0,
		"velocity_min": 130.0, "velocity_max": 280.0,
		"gravity": Vector2(0, -40.0),
		"scale_min": 2.5, "scale_max": 5.5,
		"color": Color(1.0, 0.55, 0.18, 1.0),
	})
	_spawn_family_particles(target_global, {
		"amount": 10, "lifetime": 0.5,
		"direction": Vector2(0, -1), "spread": 20.0,
		"velocity_min": 60.0, "velocity_max": 140.0,
		"gravity": Vector2(0, -10.0),
		"scale_min": 4.0, "scale_max": 7.0,
		"color": Color(1.0, 0.30, 0.10, 1.0),
	})
	screen_flash(Color(1.0, 0.45, 0.15, 0.18), 0.18)


func _vfx_shock(target_global: Vector2) -> void:
	# White-blue lightning bolt slamming down from above + crackle particles.
	var start := target_global + Vector2(0, -260)
	_spawn_lightning_bolt(start, target_global, Color(0.85, 0.95, 1.0, 1.0))
	_spawn_family_particles(target_global, {
		"amount": 14, "lifetime": 0.32,
		"direction": Vector2(0, 0), "spread": 180.0,
		"velocity_min": 100.0, "velocity_max": 220.0,
		"gravity": Vector2(0, 0),
		"scale_min": 2.0, "scale_max": 4.0,
		"color": Color(0.78, 0.92, 1.0, 1.0),
	})
	screen_flash(Color(0.85, 0.95, 1.0, 0.16), 0.10)


func _spawn_lightning_bolt(start_pos: Vector2, end_pos: Vector2, color: Color) -> void:
	# Line2D with mid-point jitter so each cast reads as a fresh strike rather
	# than a straight beam. Fades width + alpha over ~0.22s and self-frees.
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = color
	line.z_index = 160
	var pts: PackedVector2Array = [start_pos]
	var segments := 6
	for i in segments - 1:
		var t := float(i + 1) / segments
		var mid := start_pos.lerp(end_pos, t)
		var jitter := Vector2(randf_range(-28.0, 28.0), randf_range(-10.0, 10.0))
		pts.append(mid + jitter)
	pts.append(end_pos)
	line.points = pts
	var parent: Node = _hud_layer if _hud_layer != null else self
	parent.add_child(line)
	var tw := line.create_tween().set_parallel(true)
	tw.tween_property(line, "modulate:a", 0.0, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_property(line, "width", 1.0, 0.22).set_ease(Tween.EASE_IN)
	get_tree().create_timer(0.30).timeout.connect(line.queue_free)


func _vfx_blight(target_global: Vector2) -> void:
	# Heavy purple drift + bright magenta core. Slow-moving, oozes downward.
	_spawn_family_particles(target_global, {
		"amount": 24, "lifetime": 1.0,
		"direction": Vector2(0, 1), "spread": 80.0,
		"velocity_min": 30.0, "velocity_max": 90.0,
		"gravity": Vector2(0, 20.0),
		"scale_min": 2.5, "scale_max": 5.0,
		"color": Color(0.62, 0.22, 0.78, 0.95),
	})
	_spawn_family_particles(target_global, {
		"amount": 8, "lifetime": 0.55,
		"direction": Vector2(0, 0), "spread": 180.0,
		"velocity_min": 60.0, "velocity_max": 150.0,
		"gravity": Vector2(0, 0),
		"scale_min": 3.0, "scale_max": 6.0,
		"color": Color(0.85, 0.30, 0.95, 1.0),
	})
	screen_flash(Color(0.45, 0.10, 0.55, 0.12), 0.18)


func _vfx_blessing(target_global: Vector2) -> void:
	# Golden upward shimmer + bright inner sparkle + warm flash.
	_spawn_family_particles(target_global, {
		"amount": 20, "lifetime": 0.8,
		"direction": Vector2(0, -1), "spread": 45.0,
		"velocity_min": 80.0, "velocity_max": 180.0,
		"gravity": Vector2(0, -30.0),
		"scale_min": 2.5, "scale_max": 5.0,
		"color": Color(1.0, 0.92, 0.55, 1.0),
	})
	_spawn_family_particles(target_global, {
		"amount": 8, "lifetime": 0.4,
		"direction": Vector2(0, 0), "spread": 180.0,
		"velocity_min": 40.0, "velocity_max": 110.0,
		"gravity": Vector2(0, 0),
		"scale_min": 1.5, "scale_max": 3.5,
		"color": Color(1.0, 1.0, 0.85, 1.0),
	})
	screen_flash(Color(1.0, 0.92, 0.55, 0.14), 0.20)


func _vfx_earth(target_global: Vector2) -> void:
	# Brown dust kicked up at impact + Y-axis screen shake.
	_spawn_family_particles(target_global, {
		"amount": 26, "lifetime": 0.8,
		"direction": Vector2(0, -1), "spread": 100.0,
		"velocity_min": 80.0, "velocity_max": 200.0,
		"gravity": Vector2(0, 220.0),
		"scale_min": 3.0, "scale_max": 6.5,
		"color": Color(0.55, 0.40, 0.25, 0.9),
	})
	_spawn_family_particles(target_global, {
		"amount": 10, "lifetime": 0.6,
		"direction": Vector2(0, -1), "spread": 140.0,
		"velocity_min": 30.0, "velocity_max": 90.0,
		"gravity": Vector2(0, 80.0),
		"scale_min": 4.0, "scale_max": 7.0,
		"color": Color(0.32, 0.22, 0.15, 0.85),
	})
	screen_shake(6.0)


func _vfx_mind(target_global: Vector2, target: Control) -> void:
	# Pale cool sweep + outline pulse on the target if there is one.
	_spawn_family_particles(target_global, {
		"amount": 14, "lifetime": 0.7,
		"direction": Vector2(0, 0), "spread": 180.0,
		"velocity_min": 20.0, "velocity_max": 70.0,
		"gravity": Vector2(0, 0),
		"scale_min": 2.0, "scale_max": 4.5,
		"color": Color(0.85, 0.92, 1.0, 0.85),
	})
	if target != null and is_instance_valid(target):
		_pulse_target_outline(target, Color(0.85, 0.92, 1.0))


func _pulse_target_outline(target: Control, color: Color) -> void:
	# Brief translucent fill that expands slightly while fading — reads as the
	# target being "touched" by the cast without requiring an outline shader.
	if not is_instance_valid(target):
		return
	var rect := ColorRect.new()
	var bounds := target.get_global_rect()
	rect.position = bounds.position - Vector2(6, 6)
	rect.size = bounds.size + Vector2(12, 12)
	rect.color = Color(color.r, color.g, color.b, 0.40)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 175
	var parent: Node = _hud_layer if _hud_layer != null else self
	parent.add_child(rect)
	var tw := rect.create_tween().set_parallel(true)
	tw.tween_property(rect, "color:a", 0.0, 0.42).set_ease(Tween.EASE_IN)
	tw.tween_property(rect, "position", rect.position - Vector2(4, 4), 0.42)
	tw.tween_property(rect, "size", rect.size + Vector2(8, 8), 0.42)
	get_tree().create_timer(0.50).timeout.connect(rect.queue_free)


# =====================================================================
#  TIER 1 — Spell-card cast ghost
#  When a spell is played, the card itself is removed from the hand before
#  resolution (so the player can't drag a 2nd copy). The ghost is a faded
#  card-art puff that rises and dissolves at the hand position, so the player
#  reads "the card flew out" instead of "the card vanished."
# =====================================================================

func _spawn_spell_cast_ghost(card_data: Dictionary, start_global: Vector2,
		_target: Control) -> void:
	# Best-effort visual; if the baked texture isn't cached yet (e.g. first time
	# this card has appeared) we just skip the ghost rather than block on a bake.
	# The Tier-2 family VFX at the resolution point still fires either way.
	if CardTextureCache == null:
		return
	var tex: Texture2D = CardTextureCache.get_texture(card_data)
	if tex == null:
		return
	var ghost := TextureRect.new()
	ghost.texture = tex
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Match the in-hand card footprint roughly so the ghost reads as "the card
	# you just played" rather than a free-floating portrait.
	var ghost_size := Vector2(160.0, 220.0)
	ghost.size = ghost_size
	ghost.position = start_global - ghost_size * 0.5
	ghost.pivot_offset = ghost_size * 0.5
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.modulate = Color(1, 1, 1, 0.92)
	ghost.z_index = 180
	var parent: Node = _hud_layer if _hud_layer != null else self
	parent.add_child(ghost)
	var duration := 0.45
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "position:y", ghost.position.y - 70.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", Vector2(0.72, 0.72), duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	get_tree().create_timer(duration + 0.1).timeout.connect(ghost.queue_free)


func _show_encounter_intro(is_boss: bool, quick: bool = false) -> void:
	# Big dramatic banner with encounter name + passive description that holds
	# for ~1.6s before combat begins. Awaitable so _ready blocks on the intro
	# completing — the round banner / actual play follows after. `quick` is
	# the normal-fight variant: smaller, shorter, no type prefix — just long
	# enough to read the passive/mutator that makes this fight different.
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

	if not quick:
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
	name_label.add_theme_font_size_override("font_size",
		86 if is_boss else (54 if quick else 72))
	name_label.add_theme_color_override("font_color", IVORY)
	name_label.add_theme_color_override("font_outline_color",
		Color(0.55, 0.16, 0.04, 0.95))
	name_label.add_theme_constant_override("outline_size", 10)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(name_label)

	# Boss/elite preamble — one diegetic line of ill omen, above the mechanical
	# passive. Ambient voice only: never names the unnameable, never references
	# another encounter (each preamble is a standalone card of ill omen).
	if _encounter_preamble != "":
		var pre_label := Label.new()
		pre_label.text = _encounter_preamble
		pre_label.add_theme_font_size_override("font_size", 18)
		pre_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.92))
		pre_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		pre_label.add_theme_constant_override("outline_size", 5)
		pre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pre_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pre_label.custom_minimum_size = Vector2(vp.x * 0.6, 0)
		pre_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(pre_label)

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

	# Mutator badge: tag below the passive (or below the name when no passive),
	# with name + description so the player reads what changed this fight.
	if has_mutator():
		var mut_name := String(_mutator_data.get("name", ""))
		var mut_desc := String(_mutator_data.get("desc", ""))
		if mut_name != "":
			var mut_label := Label.new()
			mut_label.text = "★ %s ★\n%s" % [mut_name.to_upper(), mut_desc]
			mut_label.add_theme_font_size_override("font_size", 19)
			# Negative mutators (gold bonus > 0) read warning-amber;
			# positive gifts (gold bonus == 0) read auspicious-mint.
			var positive: bool = int(_mutator_data.get("gold_bonus", 0)) == 0
			var col: Color = Color(0.55, 1.0, 0.70) if positive else Color(1.0, 0.55, 0.30)
			mut_label.add_theme_color_override("font_color", col)
			mut_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
			mut_label.add_theme_constant_override("outline_size", 5)
			mut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			mut_label.custom_minimum_size = Vector2(vp.x * 0.62, 0)
			mut_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.add_child(mut_label)

	# Pivot pivot — make the title pop with a tiny scale overshoot.
	holder.pivot_offset = Vector2(vp.x * 0.5, vp.y * 0.5)
	holder.scale = Vector2(0.88, 0.88)

	if AudioBank != null:
		# Boss/elite hits louder than a normal turn cue; the quick variant
		# fires every passive/mutator fight, so it stays at normal volume.
		AudioBank.play_sfx("turn_start", 0.0, 0.0 if quick else 3.0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dim, "color:a", 0.38 if quick else 0.55, 0.28)
	tw.tween_property(holder, "modulate:a", 1.0, 0.32)
	tw.tween_property(holder, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold the intro on screen — bosses get longer for the player to read the
	# passive description; elites are quicker; the quick variant is just long
	# enough to register the one line that matters.
	var hold := 1.5 if is_boss else (0.8 if quick else 1.0)
	if _encounter_preamble != "":
		# Give the player time to actually read the ill-omen line, scaled to its
		# length and capped so it never drags.
		hold += clampf(_encounter_preamble.length() * 0.025, 1.5, 3.5)
	tw.chain().tween_interval(hold)
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


# Balance-telemetry switch — MUST stay false in release. When true, _dbgp() prints
# per-round and per-attack [PACING]/[COMBAT] lines for pacing analysis. These fire
# every round and on every attack, so they are silenced for shipping builds.
const DEBUG_PACING := false


func _dbgp(msg: String) -> void:
	if DEBUG_PACING:
		print(msg)


func _unhandled_input(event: InputEvent) -> void:
	# Tab / ? / Esc are intercepted in _input so focus traversal doesn't swallow
	# them. Only end-turn shortcut remains here.
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E, KEY_ENTER:
				_on_end_turn()
