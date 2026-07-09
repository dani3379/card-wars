extends Control
## Combat.gd — design-doc combat: sequential + Swift, floop, spells.
## Round flow: draw → play/floop → Swift phase → player attacks →
## enemy attacks → deaths → discard → enemy places → passives → new round.
## Combat happens every round (no setup-only round).

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"
const MAP_SCENE = "res://scenes/map.tscn"

enum Phase { PLAYER_TURN, RESOLVING, GAME_OVER }
var phase := Phase.PLAYER_TURN
var round_number := 0

# Online Skirmish (docs/MULTIPLAYER_SKIRMISH_PLAN.md). SOLO = the campaign,
# entirely unchanged — every _is_net() branch is false in solo play. NET_HOST /
# NET_CLIENT drive the online 1-v-1. Member order matches SkirmishState.CombatMode
# so the int values line up. Set at the very top of _ready().
enum CombatMode { SOLO, NET_HOST, NET_CLIENT }
var combat_mode: int = CombatMode.SOLO

# Online-skirmish runtime state (see the net section near EOF). All unused in SOLO.
var _net_active_index: int = 0          # whose turn it is (0 = host, 1 = client)
# Test hook: force the opening player (0/1) instead of the seed coin flip. -1 = use
# the coin flip (production). Probes set this so the turn-loop tests are deterministic.
var _net_first_player_override: int = -1
# Practice bot (SkirmishState.vs_bot): slot 1's virtual hand + Command, drawn and
# spent locally so the bot plays as a stand-in for an absent client.
var _bot_hand: Array = []               # [{uid:int, id:String, data:Dictionary}]
var _bot_deck_cursor: int = 0
var _bot_banked_mana: int = 0
var _bot_turns_taken: int = 0
var _net_turn_round: int = 0            # combat ROUND counter (one simultaneous clash per round)
# Place-then-simultaneous-clash model: each round BOTH players take a placement turn
# (in sequence), then the host runs ONE simultaneous clash over both boards. The
# first placer alternates each round to blunt the second placer's board-read edge.
var _net_first_placer: int = 0          # whose placement turn opens each round (fixed = coin-flip winner → strict alternation)
var _net_placed_count: int = 0          # placement turns finished this round (0/1/2 → clash)
var _net_spells_this_turn: int = 0      # spells the active side has cast this turn (flame_bolt combo)
var _net_last_spell_data: Dictionary = {}   # last host-resolved spell this turn (for Echo)
var _net_last_spell_target_eid: int = -1    # its target entity id (Echo re-aims here)
var _net_token_id_next: int = 1000000   # token/summon entity ids live above any uid
var _net_match_over: bool = false
var _net_signals_wired: bool = false
var _net_skip_draw_this_round: bool = false   # set when an opening hand was pre-dealt
var _net_rematch_local: bool = false          # this side pressed REMATCH on the result screen
var _net_rematch_remote: bool = false         # the other side wants a rematch
var _net_result_panel: Control = null         # the post-match REMATCH / LEAVE overlay
# Opponent hand presence: a small fan of FACE-DOWN card backs, the way other card
# games show it — placed in the gap just LEFT of the enemy plate (top-right), so it
# reads as the foe's held hand, next to the foe, clear of the centred title and the
# board. You see THAT they hold cards and how many, never what they are. Driven by
# _net_opp_hand_count, broadcast each time the active side's hand changes.
var _net_opp_hand_box: Control = null          # fan container in the gap by the enemy plate
var _net_opp_hand_row: Control = null          # holds the card-back fan
var _net_card_back_tex: Texture2D = null       # the shared face-down card art
# Opponent's Command (skirmish only): the foe's current/max resource, synced over
# the wire alongside the hand count and shown as a wax Command seal mirroring the
# player's own. Reads 0/<base> until the foe's first turn-begin broadcast lands.
var _net_opp_mana: int = 0
var _net_opp_max_mana: int = 0
var _net_opp_mana_label: Label = null          # numeral pressed into the foe's seal
var _net_opp_mana_post: Control = null         # the whole foe Command instrument

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
# Refill target back to 5 (2026-07-07 discard rework): the 6-card refill is now
# a RELIC payoff (Deep Satchel, +1 target) instead of the baseline, and the hand's
# churn valve is the unlimited end-of-turn discard below — mark any number of
# cards with right-click and they're thrown out when the turn ends.
const HAND_REFILL_TARGET := 5
# Battlefield repositioning — how many friendly creatures the player may drag to
# a new slot per turn. The cap is the opportunity cost: you can't re-solve the
# whole board every turn, so a move is a real commitment.
const MOVES_PER_TURN: int = 2
# Hand discards (2026-07-07 rework, replaces the 1/turn instant dismissal):
# right-click MARKS a card for discard (right-click again unmarks); every marked
# card is flushed to the discard pile in one cascade when the turn ends. No cap —
# the cost is timing: marks only cash out at end of turn, so the thrown-away
# cards aren't replaced until the next refill deals their successors.
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
const PASSIVE_HEAL_INTERVAL: int = 3         # Happy Flower interval.
# Anti-stall escalation tiers. These used to sit at 8/10/12 — far past the
# 2-4 rounds a real fight lasts, so they NEVER fired. Pulled into reachable
# range so every fight gets a visible "second wind" beat, not just the rare
# grind. WAVE_SCHEDULE_CUTOFF_ROUND stays high so authored faction waves
# (§15.2) still run their full 1-7 schedule before the generic drip takes over.
const ESCALATION_REINFORCE_ROUND: int = 4       # Round a generic hold commits reserves (double-place).
const ESCALATION_REINFORCE_BUFF_ROUND: int = 7  # Round drip reinforcements start gaining +1/+1.
const ESCALATION_ELITE_BUFF_ROUND: int = 6      # Elite +1 ATK/round trigger.
const ESCALATION_BOSS_STALL_ROUND: int = 7      # Boss force-phase if stalled this long.
const WAVE_SCHEDULE_CUTOFF_ROUND: int = 8       # Round authored faction waves end and the drip resumes.
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
# Skirmish: how many potion slots the belt draws (frozen at the drafted count
# on fight start so a consumed potion leaves an empty slot, not a shrinking bar).
var _net_potion_slots: int = 0
var _first_creature_played: bool = false
var _iron_buckler_used_this_fight: bool = false
# 2026-07-03 relic interest pass — once-per-fight latches for the reshaped
# trigger relics (Combat is re-instantiated per fight, so declaration defaults
# are the per-fight reset).
var _vanguard_cry_used_this_fight: bool = false
var _war_horn_blown_this_fight: bool = false
var _swift_boots_drawn_this_fight: bool = false
var _first_spell_this_turn: bool = false
var _spells_cast_this_turn: int = 0  # counts spells AFTER they resolve — Combo trigger
var _spells_cast_this_fight: int = 0  # lifetime count — Hexblade scaling
# Per-fight count of Tallow Dolls already played. The Nth Doll enters with
# +(N-1)/+(N-1), so each one is bigger than the last. Reset only by scene
# reload (new Combat instance) — exactly what we want, per-fight scope.
var _tallow_dolls_played: int = 0
# Set true the turn a creature is sacrificed while Butcher's Cleaver is held.
# Consumed by the next creature played this turn (which then gets +2 ATK that
# persists for 2 rounds). Resets each turn.
var _butchers_cleaver_armed: bool = false
var _cards_played_this_turn: int = 0
var _dismiss_tutorial_shown: bool = false
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
# Enemy-side mirror of the fight tally — in NET the client's fallen creatures land
# here (host arrays), so caster-side Morbid checks (Inspire) work for both players.
var _enemy_deaths_this_fight: int = 0
# Per-round enemy-side death tally — the NET mirror of _friendly_deaths_this_round,
# used as the "up to twice per round" cap for the client's own Gravedigger draws.
var _enemy_deaths_this_round: int = 0
var _last_dead_creature_id: String = ""
# Mirrors _last_dead_creature_id but stores the dying card's deck_uid so we can
# push a properly-formatted "card_id#uid" pile entry instead of a bare card_id
# (which would create an un-upgradable / mis-tracked copy). -1 means "no uid"
# (e.g. dying card was a token).
var _last_dead_creature_uid: int = -1
# Round-scoped spell states, per side (0 = player/host, 1 = enemy/client) — the
# strike code is shared between solo and net, so one pair of arrays serves both.
# Solo clears them at player-turn start; net clears per side in _net_decay_side_states.
var _virulence_active: Array = [false, false]  # Unclean Blessing: this side's attacks are poisonous this round
var _doubled_hour: Array = [false, false]      # The Doubled Hour: this side's creatures attack twice this round
# Griffin's "return to hand ONCE per fight" guard (solo) — deck uids already floated
# back, so a returned-and-replayed Griffin can't loop. Fresh per fight (new scene).
# Net keeps its own per-side guard in _net_return_once_used.
var _griffin_returned_uids: Dictionary = {}
# ── NET (skirmish) per-OWNER death/exile bookkeeping ─────────────────────────
# The solo _last_dead_* trackers only watch the PLAYER side; over the wire each
# caster needs the last corpse on ITS OWN side. Index 0 = host side, 1 = client
# side (host POV). Each entry is {id, uid, data} or {} when nothing has died yet.
var _net_last_dead: Array = [{}, {}]
# Griffin's "return to hand ONCE per fight" guard — deck uids that have already been
# floated back, per caster side, so a returned-and-replayed Griffin can't loop.
var _net_return_once_used: Array = [{}, {}]
# Per-side counters so client-owned "enter with a bonus" passives read the CLIENT's
# own state instead of the host's (the solo globals only track the player side).
var _net_spells_fight: Array = [0, 0]   # spells cast this FIGHT, per side (Hexblade)
var _net_cards_played: Array = [0, 0]   # cards played this TURN, per side (Ironclad Veteran)
# The client's unspent Command as stamped on its latest IN_PLAY_CREATURE intent
# (post-payment) — read by _apply_play_time_passives for Condottiere.
var _net_client_unspent_mana: int = 0
var _net_tallow_played: Array = [0, 0]  # Tallow Dolls seated this fight, per side
# Entity ids removed by Banish (exile) — the host stamps these into the NEXT board
# sync so the client drops them WITHOUT recycling them to discard (exile ≠ death).
var _net_exiled_eids: Array = []
# Visual-parity FX queue: keyword combat callouts (POISON/THORNS/PIERCING …) the
# host spawned since the last sync. The host never runs the resolver on the client,
# so these labels would otherwise only ever show on the host's screen. Each entry is
# {eid:int, label:String, col:[r,g,b]}; the host ships+clears them in _net_sync_board
# and the client replays each on its matching entity (survivors only — a callout on a
# creature that died this sync is dropped; its death burst already reads the kill).
var _net_fx_queue: Array = []
var _soul_lantern_used_this_round: bool = false
var _verse_of_you_used_this_round: bool = false
var _battle_scars_triggered_this_fight: bool = false
var _resonance_crystal_used_this_fight: bool = false
## Gravewarden's Pact — Imp rebirths used this fight, per side [0]=host/solo player,
## [1]=client. Per-side so a Player-2 Pact spends its own cap in skirmish.
var _gravewardens_rebirths: Array[int] = [0, 0]
var _starting_hp: int = 0

# Intent system
var _encounter_id: String = ""
var _boss_current_phase: int = 0
var _boss_phases: Array = []
var _reactive_passive: Dictionary = {}
# ── Successor Wars: per-faction reinforcement wave schedules (§15.2). ──
# Faction tag of the current encounter ("" = legacy/untagged). The schedule
# only ARMS for normal holds — elites/bosses/rival lords keep their kit pacing.
var _encounter_faction: String = ""
var _wave_schedule_active: bool = false
# The Owed: enemy deaths banked since the last wave ("every death is a deposit").
var _wave_deaths_banked: int = 0
# The Everflame: one-time surge when the hold is first half-broken.
var _wave_surge_fired: bool = false
# "NEXT WAVE" telegraph chip (lazy-built; mirrors the incoming-damage chip).
var _wave_chip: PanelContainer = null
var _wave_chip_caption: Label = null
var _wave_chip_num: Label = null
var _wave_chip_icon: TextureRect = null
var _extra_draws_this_turn: int = 0
# How many draws count as this turn's "free" hand refill (start-of-round draws
# plus the per-turn refill). Scroll of Greed / the ON_PLAYER_DRAW reactive fire
# only when _extra_draws_this_turn climbs ABOVE this ceiling, so a big draw-to-N
# refill (empty hand, Snecko Eye) can't trip them on its own.
var _refill_draws_this_turn: int = 0
var _last_dead_enemy_data: Dictionary = {}

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
var _exhaust_count_label: Label
var _exhaust_box: Control                    # exhaust pile panel (hidden while empty)
var _phase_caption: String = ""              # active combat-phase caption (SWIFT / CLASH / …)
var _info_token: int = 0                     # generation guard so a stale _show_info timer can't wipe a newer message
var _mana_bank_pips: Array = []              # banking carry-over pips under the Command seal
var _banking_tutorial_shown: bool = false
var _intents_tutorial_shown: bool = false
var _pile_tutorial_shown: bool = false
var _combat_model_tutorial_shown: bool = false

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
# Combat telegraph: hover a battlefield creature to see who it strikes and the
# outcome. A thin arrow (source→target) + a DIES/-N/SURVIVES chip, both on the
# HUD layer. Built lazily in _build_combat_telegraph; driven from _process.
var _telegraph_arrow: Line2D = null
var _telegraph_head: Polygon2D = null
var _telegraph_chip: Label = null
var _telegraph_hovered: Control = null  # the card currently driving the read
var _lane_forecast_nodes: Array = []    # always-on enemy strike forecast layer
var _phase_pulse_node: Control = null    # short sub-phase title punch during clash resolution
# Change-detection for the per-frame telegraph: the last cursor position we fully
# resolved. On my own (solo/host) turn the board is static between frames unless I
# act — and acting moves the cursor — so a still cursor means last frame's read is
# still valid and the whole scan + strike-prediction + curve rebuild can be skipped.
# Sentinel keeps it from matching a real position on the first active frame.
var _telegraph_last_mouse := Vector2(-1.0e9, -1.0e9)
# Same change-detection for the spell-targeting arrow + damage prediction (the
# telegraph's twin). While a targeted spell is in flight the board is frozen on
# player input, so a still cursor means the arc, arrowhead and "-N / LETHAL"
# chip from last frame are still correct — skip the bezier rebuild + scan.
# Reset to the sentinel in _hide_targeting_arrow so each new cast redraws once.
var _targeting_last_mouse := Vector2(-1.0e9, -1.0e9)
var _phase_label: Label
var _player_hp_label: Label
var _incoming_dmg_label: Label  # the number inside the threat chip
var _incoming_dmg_chip: PanelContainer  # framed "incoming face damage" indicator
var _incoming_dmg_icon: TextureRect  # crossed-swords / skull glyph in the chip
var _enemy_hp_label: Label
var _mana_label: Label
var _gold_label: Label = null   # combat gold readout (campaign only; absent in skirmish)
var _gold_displayed: int = -1   # last shown gold, for the change-flash
var _mana_seal_post: Control = null   # player Command instrument (hover → tooltip)
var _bank_pips: HBoxContainer = null  # carryover dots on the seal's plinth shelf
var _turn_label: Label

var _info_label: Label
var _floor_label: Label
var _end_turn_btn: Button
var _relic_panel: GridContainer
var _relic_caption: Label
# ── Battle log (Hearthstone-style chronicle) ──────────────────────────────
# A collapsible feed pinned to the left edge that remembers the fight beat by
# beat: plays, strikes, deaths, face damage, keyword pops, potions. Entries
# are BBCode lines fed through _log_event; a round divider is stamped lazily
# on the first event of each round. The tab pulses when new lines land while
# the panel is closed.
var _battle_log_panel: PanelContainer = null
var _battle_log_scroll: ScrollContainer = null
var _battle_log_list: VBoxContainer = null
var _battle_log_tab: Button = null
var _battle_log_open: bool = false
var _battle_log_round_marked: int = -1
# Hover machinery: entries carrying a card snapshot show the full card beside
# the drawer while hovered (Hearthstone history). Shared row styleboxes so 90
# rows don't allocate 180 StyleBoxes.
var _log_preview_card: Control = null
var _log_hover_row: Control = null
var _log_row_plain: StyleBox = null
var _log_row_hover: StyleBox = null
const _LOG_MAX_LINES := 90
const _LOG_THUMB := 34.0
const _LOG_PLAYER_COL := "#e8c06a"   # warm gilt — your side
const _LOG_ENEMY_COL := "#e07858"    # ember — the foe's side
const _LOG_DIM_COL := "#a08a54"      # dividers / connective tissue
# HP bar fill tweens — kept so rapid HP changes re-target a single drain
# animation instead of stacking competing tweens.
var _player_hp_tween: Tween = null
var _enemy_hp_tween: Tween = null
var _player_hp_bar_target := -1.0
var _enemy_hp_bar_target := -1.0
var _incoming_dmg_style_key := ""
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


# ─────────────────────────────────────────────────────────────────────────
#  ONLINE SKIRMISH — mode helpers & context indirection
#  (docs/MULTIPLAYER_SKIRMISH_PLAN.md §12.1-12.2)
#
#  These are the *only* hooks the campaign cares about: in SOLO every _is_net()
#  is false, so all of this is dead weight that the optimizer skips. In net mode
#  they redirect the handful of RunState reads (HP / deck / mana / card-data)
#  that would otherwise pull the wrong player's run, and they force every
#  relic/mutator path inert so a leftover campaign RunState can't bleed in.
# ─────────────────────────────────────────────────────────────────────────

func _is_net() -> bool:    return combat_mode != CombatMode.SOLO
func _is_host() -> bool:   return combat_mode == CombatMode.NET_HOST
func _is_client() -> bool: return combat_mode == CombatMode.NET_CLIENT


# ─────────────────────────────────────────────────────────────────────────
# PlayLog hooks — structured per-action telemetry (see scripts/state/PlayLog.gd).
# Solo campaign only (skirmish/net excluded). Snapshots are taken at DECISION
# time so each record is a usable state→action pair for analysis / bot training.
# ─────────────────────────────────────────────────────────────────────────
var _pl_combat_logged: bool = false
var _pl_spell_pending: Dictionary = {}
var _pl_last_end_turn_round: int = -1

func _pl_card_brief(c) -> Dictionary:
	if c == null or not is_instance_valid(c):
		return {}
	var d: Dictionary = c.card_data if c.card_data != null else {}
	return {"id": c.card_id, "atk": c.effective_atk(), "hp": c.current_hp,
		"kw": d.get("keywords", [])}

func _pl_board(is_enemy: bool) -> Array:
	# 8 slots in read order [front 0..3, back 0..3]; null where the slot is empty.
	var out: Array = []
	for row in [0, 1]:
		var arr = _row_array(is_enemy, row)
		for lane in range(4):
			var c = arr[lane] if lane < arr.size() else null
			out.append(_pl_card_brief(c) if c != null else null)
	return out

func _pl_hand() -> Array:
	var out: Array = []
	for c in _hand:
		if c == null or not is_instance_valid(c):
			continue
		var d: Dictionary = c.card_data if c.card_data != null else {}
		out.append({"id": c.card_id, "cost": int(d.get("cost", 0)),
			"type": d.get("type", "")})
	return out

func _pl_snapshot() -> Dictionary:
	return {"round": round_number, "php": player_hp, "ehp": enemy_hp,
		"mana": player_mana, "max_mana": player_max_mana,
		"hand": _pl_hand(),
		"player_board": _pl_board(false), "enemy_board": _pl_board(true)}

func _pl_log(type: String, action: Dictionary, snap = null) -> void:
	# Central emit. Skips net/skirmish; lazily emits combat_start once per fight.
	if _is_net():
		return
	if not _pl_combat_logged:
		_pl_combat_logged = true
		PlayLog.log_event("combat_start", {
			"encounter": _encounter_id, "name": _encounter_name,
			"act": RunState.get_act(), "mutator": _mutator_id,
			"node_type": RunState.current_node_type, "enemy_max_hp": enemy_max_hp})
	var rec: Dictionary = {}
	rec.merge(action, true)
	rec["state"] = snap if snap != null else _pl_snapshot()
	PlayLog.log_event(type, rec)

## The local player's index (0 = host slot, 1 = client slot). -1 in solo.
func _net_my_index() -> int:
	return NetMatch.local_player_index

## The local player's SkirmishState slot (deck / HP / mana). Null in solo.
func _net_my_slot() -> SkirmishState.PlayerSlot:
	return SkirmishState.get_slot(_net_my_index())

## Which player (0 host / 1 client) takes the FIRST turn this game. It is a COIN
## FLIP from the shared match seed — NOT "the host always opens" — so nothing about
## the turn order reveals which side is player 1. It also alternates each game of a
## Best-of-N series, so neither side opens every game. Both machines derive it from
## the same SkirmishState.rng_seed (= NetMatch.match_seed) and the same series_game
## counter (recorded in lockstep on both sides), so they always agree without any
## negotiation — only the host then acts on it to drive the authoritative turn loop.
func _net_first_player() -> int:
	if _net_first_player_override >= 0:
		return _net_first_player_override
	var rng := RandomNumberGenerator.new()
	rng.seed = SkirmishState.rng_seed
	var base: int = rng.randi() & 1
	# Alternate the opener each game (game 1 = base, game 2 = the other, …).
	return base ^ ((SkirmishState.series_game - 1) & 1)

## True if `player_index` (0/1) takes the SECOND turn — the going-second player gets
## the +1 opening card and pre-deals their hand. Complement of _net_first_player.
func _net_goes_second(player_index: int) -> bool:
	return player_index != _net_first_player()

## Map a global owner index (0 host / 1 client) to THIS screen's board side.
## Each client renders itself on the bottom (player side, is_enemy=false) and the
## opponent on top (enemy side, is_enemy=true), so "enemy" is purely a local
## rendering fact keyed off who owns the creature.
func _side_for_owner(owner_index: int) -> bool:
	return owner_index != _net_my_index()

# ── Context accessors: deck / HP / mana / card-data source ──

func _ctx_hero_hp() -> int:
	return _net_my_slot().hero_hp if _is_net() else RunState.hero_hp

func _ctx_hero_max_hp() -> int:
	return _net_my_slot().hero_max_hp if _is_net() else RunState.hero_max_hp

func _ctx_deck() -> Array:
	return _net_my_slot().deck if _is_net() else RunState.deck

func _ctx_deck_uids() -> Array:
	return _net_my_slot().deck_uids if _is_net() else RunState.deck_uids

func _ctx_max_mana() -> int:
	return _net_my_slot().base_max_mana if _is_net() else RunState.get_max_mana()

## Drafted battle potions (skirmish) vs the campaign potion belt (solo).
func _ctx_potions() -> Array:
	return _net_my_slot().potions if _is_net() else RunState.potions

## How many potion slots the belt draws. Solo shows the full MAX_POTIONS belt
## (consumed slots go empty); skirmish shows exactly what was drafted this match.
func _ctx_max_potions() -> int:
	return _net_potion_slots if _is_net() else RunState.MAX_POTIONS

## Consume the potion at `index` from whichever belt is live.
func _ctx_consume_potion(index: int) -> void:
	if _is_net():
		var pots: Array = _net_my_slot().potions
		if index >= 0 and index < pots.size():
			pots.remove_at(index)
	else:
		RunState.consume_potion(index)


func _ready() -> void:
	set_process(false)
	# Re-arm the hand-play gate every combat: a skirmish that locked the hand on
	# the foe's turn must not leak that lock into a later solo fight (statics live
	# for the whole app run). Net turns toggle it from here on.
	Card2D.hand_interactive = true
	# Decide combat mode FIRST — everything downstream branches on it. Gated on a
	# live NetMatch connection so a stale SkirmishState left over from a previous
	# skirmish can never make a campaign fight think it's networked.
	if SkirmishState.combat_mode != SkirmishState.CombatMode.SOLO \
			and NetMatch.is_connected_to_peer():
		combat_mode = SkirmishState.combat_mode   # int values align with CombatMode
	else:
		combat_mode = CombatMode.SOLO
	_rebuild_relic_cache()
	_compute_spell_tome()
	_banking_tutorial_shown = UserSettings.banking_tutorial_seen
	_intents_tutorial_shown = UserSettings.intents_tutorial_seen
	_pile_tutorial_shown = UserSettings.pile_tutorial_seen
	_combat_model_tutorial_shown = UserSettings.combat_model_tutorial_seen
	_dismiss_tutorial_shown = UserSettings.dismiss_tutorial_seen
	_swap_background_for_act()
	_setup_fight_state()
	# Warm the enemy art cache now, before _place_starting_board lays the opening
	# formation — otherwise each creature's art disk-loads on the frame it appears.
	_prewarm_enemy_art()
	# Music: every fight class rotates a pool (the picker excludes the
	# currently-playing track, and play_music resumes saved positions). Acts
	# escalate to heavier books. AudioBank no-ops if a file is missing.
	var node_type: String = RunState.current_node_type
	var act: int = RunState.get_act()
	if _is_net():
		# Skirmish has no acts or node types — the solo run state read below
		# is stale here. Rotate the whole combat book instead, so each game
		# of a Bo3 gets a fresh song.
		AudioBank.play_music_random([
			"combat", "combat_act1_b", "combat_act1_c", "combat_act1_d",
			"combat_act2", "combat_act2_b", "combat_act2_c", "combat_act2_d",
			"combat_act3", "combat_act3_b", "combat_act3_c", "combat_act3_d"])
	else:
		match node_type:
			"boss":
				# Act 3 keeps its fixed heavyweight; earlier lords rotate between
				# the two boss themes so rival-keep fights don't share one song.
				if act >= 3:
					AudioBank.play_music("combat_boss_act3")
				else:
					AudioBank.play_music_random(["combat_boss", "combat_boss_b"])
			"elite":
				AudioBank.play_music_random(
					["combat_elite", "combat_elite_b", "combat_elite_c"])
			_:
				var pool: Array
				match act:
					2: pool = ["combat_act2", "combat_act2_b", "combat_act2_c", "combat_act2_d"]
					3: pool = ["combat_act3", "combat_act3_b", "combat_act3_c", "combat_act3_d"]
					_: pool = ["combat", "combat_act1_b", "combat_act1_c", "combat_act1_d"]
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
	if not _is_net():
		_place_starting_board()   # no AI enemy in skirmish — the opponent is a player
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
	# Online skirmish takes over here: no relic combat-start bundle, no encounter
	# intro, no solo round loop. The host drives the turn sequence; the client
	# waits for events. Everything below is campaign-only.
	if _is_net():
		_net_begin_combat()
		return
	# Gambler's Coin: once at fight start, coin flip — draw 1 extra OR deal 3
	# to a random enemy. Lives here (after enemies are placed, before round 1
	# starts) so the damage option can find a target and the draw lands before
	# the player's first turn read.
	_apply_gamblers_coin()
	_apply_conscription_muster()
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
	# there is something to announce — a fight passive, a mutator, or a
	# faction wave schedule (the intro names the kingdom's engine, §15.2) —
	# so the threat is read before it fires; untagged vanilla skirmishes
	# still start instantly.
	# node_type was already captured above for the music branch — reuse it.
	if node_type == "boss" or node_type == "elite":
		await _show_encounter_intro(node_type == "boss")
	elif _encounter_passive_desc != "" or has_mutator() or _wave_schedule_active \
			or _pursuit_tier() >= 1 or _encounter_preamble != "":
		await _show_encounter_intro(false, true)
	else:
		await _show_encounter_intro(false, true)
	_start_round()


func _sound_war_horn() -> void:
	# War Horn (redesigned 2026-07-03): the FIRST ATK-buff spell each fight
	# rallies the whole line (+1 ATK this round) instead of an invisible +1 on
	# the spell. Called from the buff_atk / buff_all_atk resolvers.
	if not _has_relic("war_horn") or _war_horn_blown_this_fight or _is_net():
		return
	_war_horn_blown_this_fight = true
	for c in _all_player_creatures():
		c.temp_atk_buff += 1
		c.update_stat_display()
	_show_info("WAR HORN — the whole line surges: +1 ATK this round!")


func _apply_conscription_muster() -> void:
	# Conscription (redesigned 2026-07-03): a 1/1 Conscript reports to the back
	# row at the start of every fight — a visible body instead of only the
	# invisible token-HP bonus (which the relic also keeps).
	if not _has_relic("conscription_relic") or _is_net():
		return
	summon_token(1, 1, randi() % LANES_PER_ROW, false, ROW_BACK)
	_show_info("Conscription — a recruit reports for the fight.")


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
	if _is_net():
		return   # campaign event payoff — never in skirmish
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
		# The gift keeps its given name and any promised keywords (the Patent
		# Ladder's Armored, the Garrison Shade's Last Stand) — events that
		# advertise "(0/7, Armored)" deliver exactly that.
		summon_token(atk, hp, 0, false, ROW_FRONT, {},
			String(gift.get("name", "")), gift.get("kw", []))


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
	# Sellsword's Retainer: a fat purse hires muscle — 150+ gold fields a 3/3
	# Sellsword in the back row. His fee settles at victory (see the victory
	# block): 10 gold if he lives; the dead collect nothing.
	if _has_relic("sellswords_retainer") and not _is_net() \
			and RunState.gold >= int(RelicDB.get_relic("sellswords_retainer").get("value", 150)):
		for sw_lane in range(LANES_PER_ROW):
			if _player_back[sw_lane] == null:
				summon_token(3, 3, sw_lane, false, ROW_BACK, {}, "Sellsword")
				break


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
	# Headless guard: CardTextureCache.bake_many awaits RenderingServer.
	# frame_post_draw, which never fires under the dummy display server — so
	# _ready would park here forever in automated headless runs (probes/tests).
	# There is nothing to draw to headless, and uncached cards fall back to the
	# live layout path (visually identical), so skipping the bake only affects
	# off-screen test runs, never the real windowed game.
	if DisplayServer.get_name() == "headless":
		return
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


func _prewarm_enemy_art() -> void:
	# First placement of an enemy creature otherwise does a synchronous disk read +
	# decode + mipmap of its art ON the gameplay frame it appears — the opening
	# formation and every reinforcement wave hitch as a result. Enemy creatures
	# render in compact_mode, which CardTextureCache deliberately skips, so warm the
	# static art cache here instead: pre-load every art the encounter deck +
	# reinforcement can show so _place_enemy_card → _find_card_art is a cache hit.
	# Headless probes never render, so warming there is pure wasted I/O — skip it and
	# leave placement's existing lazy load unchanged.
	if DisplayServer.get_name() == "headless":
		return
	var roster: Array = _enemy_deck.duplicate()
	if not _reinforcement.is_empty():
		roster.append(_reinforcement)
	var seen := {}
	for cd in roster:
		if typeof(cd) != TYPE_DICTIONARY or cd.is_empty():
			continue
		var cid := String(cd.get("id", ""))
		if seen.has(cid):
			continue
		seen[cid] = true
		_prewarm_one_art(cd)
	# Named MID-FIGHT spawns are the remaining decode hitch: fight-passive waves
	# ("Alpha Wolf"), amalgam transition summons ("Star-Reader"), reactive spawns,
	# and on-death bequests all synthesize card data on the fly, so their painting
	# would otherwise disk-load + decode on the very frame the creature appears.
	# Walk the encounter definition, the armed reactive passive, and each deck
	# card's nested effect dicts for anything name-shaped and warm those too.
	# Over-collecting is fine — misses are memoized as a few exists() probes.
	var names := {}
	_collect_spawn_names(EncounterDB.get_encounter(_encounter_id), names)
	_collect_spawn_names(_reactive_passive, names)
	for cd in roster:
		_collect_spawn_names(cd, names)
	for n in names:
		if not seen.has(n):
			seen[n] = true
			_prewarm_one_art({"name": n, "type": "creature"})


## Recursively collect every "name"/"id" string inside nested dicts/arrays —
## the superset of identifiers a summon/wave/transition/bequest could resolve
## art with. Deliberately shape-agnostic so new encounter fields keep working.
func _collect_spawn_names(v, out: Dictionary) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				var val = v[k]
				if (k == "name" or k == "id") and typeof(val) == TYPE_STRING \
						and val != "":
					out[val] = true
				else:
					_collect_spawn_names(val, out)
		TYPE_ARRAY:
			for item in v:
				_collect_spawn_names(item, out)


func _prewarm_one_art(cd: Dictionary) -> void:
	# Mirror Card2D._find_card_art's resolution order + short-circuit exactly so we
	# warm the same cache keys it will look up, and no extra ones.
	var cid := String(cd.get("id", ""))
	var name_id := String(cd.get("name", "")).to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = null
	if String(cd.get("type", "creature")) == "spell":
		art = CardArtAliases.try_load_spell_art(cid)
		if art == null:
			art = CardArtAliases.try_load_spell_art(name_id)
	if art == null:
		art = CardArtAliases.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art(name_id)
	if art == null and name_id != "":
		CardArtAliases.try_load_creature_art("e_" + name_id)


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
	# The backdrop node is "CombatBg" (see combat.tscn + the mood code, which
	# modulates "CombatBg"). This used to look up "Background" — a node that does
	# not exist — so it silently no-op'd and EVERY act kept the act-1 default red
	# burning-meadow hellscape. The cooler act-2 / act-3 backdrops never showed,
	# which made the whole game read as monochrome red.
	var bg := get_node_or_null("CombatBg") as TextureRect
	if bg == null:
		return
	bg.texture = load(path)


func _setup_fight_state() -> void:
	if _is_net():
		_setup_net_fight_state()
		return
	player_max_hp = RunState.hero_max_hp
	player_hp = RunState.hero_hp
	_starting_hp = player_hp
	_init_mutator_state()
	var enc_id = RunState.current_encounter_id
	if enc_id != "":
		var enc = EncounterDB.get_encounter(enc_id)
		if not enc.is_empty():
			_encounter_id = enc_id
			# Successor Wars: per-faction reinforcement wave schedules arm for
			# NORMAL holds only — elites/bosses/rival lords keep their kit
			# pacing (§15.2: true slow-burn belongs to strongholds and lords),
			# and untagged fights keep the legacy uniform drip exactly.
			_encounter_faction = String(enc.get("faction", ""))
			_wave_schedule_active = String(enc.get("type", "")) == "combat" \
				and FACTION_WAVE_SCHEDULES.has(_encounter_faction)
			# Successor Wars cross-act borrows: scale the fight to the map
			# slot it actually landed in (kingdoms pull their faction's
			# fights from other acts; demoted bosses fight at elite band).
			var t_act: int = RunState.get_act()
			var t_type: String = RunState.current_node_type \
				if RunState.current_node_type in ["combat", "elite", "boss"] else ""
			enemy_max_hp = _scale_enemy_hp(EncounterDB.get_face_hp(enc_id, t_act, t_type), t_type)
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
			enemy_max_hp = _scale_enemy_hp([12, 17, 21][act - 1] + randi() % 4, "combat")
		"elite":
			enemy_max_hp = _scale_enemy_hp([18, 26, 30][act - 1] + randi() % 4, "elite")
		"boss":
			enemy_max_hp = _scale_enemy_hp([25, 32, 40][act - 1], "boss")
	_build_legacy_enemy_deck(act)
	enemy_hp = enemy_max_hp


func _scale_enemy_hp(base: int, fight_type: String = "") -> int:
	# Global enemy-HP tuning: every keep faces +20% HP.
	var scaled: float = base * 1.20
	# Ascension no longer sponges every face (see RunState.ASCENSION_RULES).
	# Only A5 "Kings at bay" touches HP, and only at the lords' keeps (stacks
	# on top of the global bump).
	if RunState.asc_active(5) and fight_type == "boss":
		scaled *= 1.25
	return int(round(scaled))


func _esc_round(base: int) -> int:
	# A1 "Pressed marches" — every escalation beat lands one round earlier.
	return base - 1 if RunState.asc_active(1) else base


func _fight_class() -> String:
	# "combat" / "elite" / "boss" — prefers the encounter's own type, falls back
	# to the map node type for legacy random fights.
	if _encounter_id != "":
		return String(EncounterDB.get_encounter(_encounter_id).get("type", "combat"))
	return String(RunState.current_node_type) if RunState.current_node_type != "" else "combat"


func _build_legacy_enemy_deck(act: int) -> void:
	for i in range(8):
		var eid = CardDB.random_enemy_for_act(act)
		_enemy_deck.append(CardDB.get_card_data(eid))


func _setup_net_fight_state() -> void:
	## Skirmish fight setup (docs/MULTIPLAYER_SKIRMISH_PLAN.md §12.1-12.2). The
	## "enemy" is the remote player, not an EncounterDB lineup — so there is no
	## encounter, no AI deck, no passive/boss/reactive machinery, and no enemy
	## reinforcement drip (the opponent supplies their own board via intents).
	## Both heroes start at SkirmishState.START_HP in v1.
	player_max_hp = _ctx_hero_max_hp()
	player_hp = _ctx_hero_hp()
	_starting_hp = player_hp
	_init_mutator_state()              # clears to empty in net mode
	enemy_max_hp = SkirmishState.START_HP
	enemy_hp = enemy_max_hp
	_encounter_id = ""
	_encounter_faction = ""
	_wave_schedule_active = false
	_encounter_passive = ""
	_encounter_name = "Skirmish"
	_encounter_passive_desc = ""
	_encounter_preamble = ""
	_enemy_deck = []                   # remote-driven; never AI-dealt
	_reinforcement = {}
	_boss_phases = []
	_reactive_passive = {}
	_encounter_script = []


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


func _get_creature_in_column(is_enemy: bool, lane: int) -> Control:
	# Returns front-row creature if alive, else back-row creature, else null.
	# Guards against (and scrubs) a stale FREED reference left in a slot — a
	# back-row creature can die without its slot being nulled on every path, and
	# returning the freed instance crashes callers like get_opposing_card.
	var front = _row_array(is_enemy, ROW_FRONT)
	if front[lane] != null:
		if is_instance_valid(front[lane]):
			return front[lane]
		front[lane] = null
	var back = _row_array(is_enemy, ROW_BACK)
	if back[lane] != null:
		if is_instance_valid(back[lane]):
			return back[lane]
		back[lane] = null
	return null


func _relocate_creature(card: Control, side_is_enemy: bool, dest_row: int, dest_lane: int) -> bool:
	# Move an on-board creature to an empty slot on its OWN side (board-
	# manipulation verbs: Shove pushes an enemy front→back, Hook pulls back→
	# front). Mirrors the proven reposition sequence in _on_field_move_dropped:
	# clear the source array cell, update the card's row/lane, re-slot the visual
	# node, and write the destination cell. Returns false (no-op) if the card is
	# invalid, the destination is out of range, occupied, or the same slot.
	if not is_instance_valid(card):
		return false
	if dest_lane < 0 or dest_lane >= LANES_PER_ROW:
		return false
	if _row_array(side_is_enemy, dest_row)[dest_lane] != null:
		return false
	var src_row: int = card.current_row
	var src_lane: int = card.current_lane
	if src_row == dest_row and src_lane == dest_lane:
		return false
	_row_array(side_is_enemy, src_row)[src_lane] = null
	# Detach the card from its SOURCE cell (+ hide that slot's contact shadow) before
	# re-slotting. _slot_set_card clears only the DESTINATION cell, so without this
	# detach `cell.add_child(card)` fails ("already has a parent") and the visual node
	# stays stuck in the old slot while the board array points to the new one — the
	# real "mirrors _on_field_move_dropped" step (it calls _reset_card_after_drag too).
	var src_slot: Control = _slot_array(side_is_enemy, src_row)[src_lane]
	if src_slot != null:
		var sh = src_slot.get_node_or_null("ContactShadow")
		if sh != null:
			sh.visible = false
	card.current_row = dest_row
	card.current_lane = dest_lane
	_reset_card_after_drag(card)
	_slot_set_card(_slot_array(side_is_enemy, dest_row)[dest_lane], card)
	_row_array(side_is_enemy, dest_row)[dest_lane] = card
	_play_landing_pop(card)
	return true


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
	# Online skirmish (v1) has no card upgrades and uses SkirmishState uids that
	# don't index RunState — resolve straight from the base definition. (Even
	# without this guard the RunState.deck_uids.find below would miss and fall
	# back to CardDB; the guard makes that explicit and dodges a stray uid
	# collision with a leftover campaign deck.)
	if _is_net():
		return CardDB.get_card_data(card_id)
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
	# sacrifice your own creatures (Offering, Fuel the Pyre, Dark Pact),
	# or recurse (Echo). Previously the function filtered ALL custom spells,
	# which left the candidate pool nearly empty since almost every spell in
	# CardDB now routes through type:"custom".
	const CHAOS_DENY := {
		"offering": true, "fuel_the_pyre": true, "dark_pact": true,  # sacrifice cost
		"bloodletting": true, "unholy_bargain": true,  # self-harm
		"blood_tithe": true,  # face damage to self
		"mass_grave": true, "apocalypse": true,  # board-wipe player too
		"echo_spell": true,  # recursion
		"recycle": true, "scrap": true, "gambit": true, "war_chant": true,  # need player hand input
		"grave_robbery": true, "reanimate": true,  # need last-dead state
		"turbo": true,  # adds a curse
		"coin": true,  # the going-second system card — not a real campaign spell
	}
	var candidates: Array = []
	for id in CardDB.CARD_POOL:
		if CHAOS_DENY.has(id):
			continue
		var d = CardDB.CARD_POOL[id]
		# Cap the roll at cheap spells (cost 1 or less): a 1-mana 1/2 free-casting a
		# 4-cost Inferno was a pure high-roll. Keeps the chaos fun, not a blowout.
		if d.get("type", "") == "spell" and not CardDB.is_curse(id) and int(d.get("cost", 0)) <= 1:
			candidates.append(id)
	if candidates.is_empty():
		return
	var data := CardDB.get_card_data(candidates[randi() % candidates.size()])
	var target := _auto_target_for(data.get("targeting", "none"))
	var tl: int = target.current_lane if target != null else -1
	_show_info("Chaos Imp casts %s!" % data.get("name", "a spell"))
	# Show the actual card — a random cast used to be a mystery (you saw the
	# effect but never which spell). Fire-and-forget; it doesn't gate the resolve.
	_reveal_cast_card(data, "CHAOS IMP CASTS")
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
	# Context-routed deck: campaign → RunState; skirmish → the local SkirmishState
	# slot. The opponent's draw pile lives on the host and is never built here.
	var deck: Array = _ctx_deck()
	var deck_uids: Array = _ctx_deck_uids()
	for i in deck.size():
		_player_draw_pile.append(_pile_entry(deck[i], deck_uids[i]))
	# NOTE: Mark of Pain's 2 curses are added once, in _apply_combat_start_relics()
	# (the canonical combat-start relic entry point, with proper _pile_entry uids).
	# A second add here used to stack them to 4 — double the relic's stated cost.
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
		_place_enemy_card(card_data, slot.lane, slot.row, true)
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
	# Slow Match: every copy that WAITED in hand through a full turn banks +1
	# damage on its fuse (cap +4) — charged before the refill so fresh draws
	# start cold. The hover prediction reads the same card_data key, so the
	# number the player sees is the number that lands.
	if round_number >= 2:
		for _fc in _hand:
			if is_instance_valid(_fc) and String(_fc.card_id) == "slow_match":
				var _fuse: int = int(_fc.card_data.get("fuse", 0))
				if _fuse < 4:
					_fc.card_data["fuse"] = _fuse + 1
					spawn_floating_number(_fc.global_position + Vector2(_fc.size.x * _fc.scale.x * 0.5, -8), "FUSE +1", Color(1.0, 0.62, 0.25), false)
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
	# Round-scoped spell states expire with the round they were cast for (solo;
	# net decays per side in _net_decay_side_states after the clash instead).
	if not _is_net():
		_virulence_active = [false, false]
		_doubled_hour = [false, false]
	_butchers_cleaver_armed = false
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
	_enemy_deaths_this_round = 0
	_soul_lantern_used_this_round = false
	_verse_of_you_used_this_round = false
	_extra_draws_this_turn = 0
	_refill_draws_this_turn = 0
	phase = Phase.PLAYER_TURN

	# War school (veterancy rung 3) — solo only, fired at the top of the player
	# phase so the modal never lands mid-clash. Round 1 sweeps the deck for
	# veterans who crossed 10 kills on a fight's LAST kill (or on an old save).
	# Fire-and-forget coroutine: the overlay blocks all input until the pick.
	if not _is_net():
		if round_number == 1:
			_queue_war_school_catchup()
		if not _war_school_queue.is_empty():
			_offer_war_school()

	# Start-of-round keyword ticks (Regenerate heal / Wither ATK-decay / Doom
	# countdown) are HOST-AUTHORITATIVE in net. The client must NOT run them on its
	# own placement turn: its _start_round is non-authoritative, so a local tick
	# DOUBLE-applied the effect — a spurious REGEN/WITHER callout + hp/atk flicker on
	# the client's own turn, and a doom counter the snapshot couldn't reconcile
	# (it isn't in the board dict). The host runs it once per round; the results
	# reach the client via the snapshot (hp/atk + the new doom counter) and the
	# regen/wither callouts ride the fx queue (spawn_keyword_callout_kw enqueues
	# host-side). Solo is unaffected (_is_client() is always false there).
	if not _is_client():
		KeywordEffects.dispatch_start_of_round(self)
	# Riteforge ramp + Warchief aura + Summoner muster — HOST-AUTHORITATIVE in net,
	# same as the keyword ticks above. The host runs the client's side here via
	# _net_start_turn's `_apply_start_round_passives(true)` hook and ships the result
	# in the snapshot; the client must NOT run it on its own placement turn. For the
	# ATK ramps it was merely redundant (the snapshot overwrites current_atk), but
	# Summoner's `summon_each_round` calls summon_token(), which spawns a LOCAL token
	# node the client never registers — the board-sync reconcile only despawns
	# REGISTERED entities, so that phantom is permanent and accumulates one per round
	# (a whole extra creature on the client's board the host never shows). Solo is
	# unaffected (_is_client() is always false there).
	if not _is_client():
		_apply_start_round_passives(false)
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
	# (Bulwark Engine moved to _apply_start_round_passives so it fires per-side —
	# host-authoritative for the client's copy too in skirmish.)
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

	# Successor Wars: telegraph what the faction's wave schedule musters at
	# the end of this round — the persistent chip under the enemy plate owns
	# this readout. Only the RARE surge still gets a center call-out (it's a
	# dramatic beat); the routine per-round "wave musters" toast duplicated
	# the chip and was center-screen noise every round.
	_update_wave_telegraph()
	if _next_wave_count() >= 2 and _wave_surge_pending():
		_show_info("Fire on the water — the Everflame surges")

	# Escalation check
	_check_escalation()

	# Mana — unspent mana carries over (banked)
	var bank_cap = player_mana if _has_relic("ice_cream") else mini(player_mana, MAX_BANKED_MANA)
	var banked = bank_cap if round_number > 1 else 0
	player_max_mana = _ctx_max_mana() + _bonus_mana_next_turn
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
	# Teach the dismissal once, on the first turn that actually HOLDS cards
	# over (round 2+): that's the moment the persistent hand becomes visible.
	if round_number == 2 and not _is_net():
		_maybe_show_dismiss_tutorial()
	player_mana = player_max_mana + banked
	# Marathoner's Sash partial: round 1 starts with 1 mana (the "ramp" trade
	# for +2 max). Round 2+ flows normally so the +2 ceiling actually matters.
	if _has_relic("marathoners_sash") and round_number == 1:
		player_mana = 1
	# Warm Knucklebone (event relic): 1 in 6 turns the bones come up warm.
	# After the Sash override so the bonus survives a round-1 ramp.
	if _has_relic("warm_knucklebone") and randi() % 6 == 0:
		player_mana += int(RelicDB.get_relic("warm_knucklebone").get("value", 1))
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
		# Deep Satchel: the refill target itself grows by 1 (5 → 6) — the old
		# baseline-6 hand as a relic payoff. Net-safe: the refill runs per-peer.
		if _has_relic("deep_satchel"):
			target += int(RelicDB.get_relic("deep_satchel").get("value", 1))
		if _has_relic("couriers_bag") and round_number == 1:
			target += 1
		if _has_relic("tome_of_many") and _ctx_deck().size() >= 20:
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
		if _has_relic("tome_of_many") and _ctx_deck().size() >= 20:
			draw_count += int(RelicDB.get_relic("tome_of_many").get("value", 2))
	# Skirmish: when an opening hand was pre-dealt at match start (so the player
	# going second can see it during the opener — and pick up the +1 going-second
	# card), skip this turn's draw so the pre-dealt hand isn't topped up again.
	if _is_net() and _net_skip_draw_this_round:
		_net_skip_draw_this_round = false
		_refill_draws_this_turn = _extra_draws_this_turn
	else:
		# Everything drawn up to and including this refill is "free"; the
		# reactive/relic only pay out on genuinely extra draws past it.
		_refill_draws_this_turn = _extra_draws_this_turn + draw_count
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
	# Skirmish: the end-turn button is the DONE (finish placing) button. Once both
	# sides have placed, the host runs one simultaneous clash. Host finishes its own
	# placement directly; the client asks the host to.
	if _is_net():
		_net_on_done_placing()
		return
	# PlayLog: record end-of-turn (deduped per round so the confirm re-entry
	# and the warning path don't double-log).
	if round_number != _pl_last_end_turn_round:
		_pl_last_end_turn_round = round_number
		_pl_log("end_turn", {})
	# End-turn warning: if the player still has playable actions, prompt
	# before ending the turn. Most accidental end-t}rn clicks happen at
	# exactly these moments. _end_turn_confirmed gates the recursive
	# re-entry — set true ONLY when the player confirms in the dialog.
	if UserSettings != null and UserSettings.end_turn_warning \
			and not _end_turn_confirmed and _has_playable_action():
		GameTheme.show_confirm_dialog(self,
			"End Turn?",
			"You still have Command or an action available.\n(Disable in Settings)",
			"END TURN",
			"KEEP PLAYING",
			Callable(self, "_on_end_turn_confirmed"))
		return
	_end_turn_confirmed = false
	# First-run teaching: the simultaneous-combat model, taught the instant the
	# player commits their first clash (before the swing resolves).
	_maybe_show_combat_model_tutorial()
	_end_turn_btn.disabled = true
	phase = Phase.RESOLVING
	_clear_threat_flags()  # JUICE: drop the pre-combat threat outlines; the clash itself now reads
	Card2D.board_interactive = false
	# Marked discards cash out now — AFTER the phase flip (a second [E] press
	# during the cascade's pause must not re-enter and double-run the clash).
	# The cascade gets a short beat of its own so the cards visibly peel away
	# before the lines meet.
	var shed := _flush_marked_discards()
	if shed > 0:
		await _short_pause(0.15 + 0.09 * float(mini(shed, 4)))
	_dbgp("[PACING] R%d commit | played:%d | P_board:%d E_board:%d | P_HP:%d E_HP:%d" % [round_number, _cards_played_this_turn, _all_player_creatures().size(), _all_enemy_creatures().size(), player_hp, enemy_hp])
	# Mime: at end of turn, the player picks ONE creature-with-floop in hand to
	# play for free with its floop pre-armed. Skipped when nothing qualifies.
	if _has_relic("mime"):
		await _mime_trigger_floop_from_hand()
	_update_hud()

	# Resolve enemy intents (non-attack intents execute now)
	_resolve_intents()

	await _do_combat()


## Command / draws earned by a CREATURE BATTLECRY (on-enter / on-play / on-death),
## granted to the side that OWNS the creature. `is_enemy` = the creature's side from
## the resolving instance's POV.
##   Solo — only the player side (is_enemy=false) has these resources; enemy
##          battlecries no-op, exactly as the old `if not is_enemy` guards did.
##   Net  — the HOST resolves EVERY battlecry, so route through the same
##          EV_MANA / EV_DRAW caster channel the spell resolver already uses.
##          Without this the CLIENT's "gain Command" / "draw" battlecries silently
##          vanished: `if not is_enemy` is the host's own side, so a client creature's
##          Errand Sprite / Witch / Leyline gave the client no Command and its
##          Lookout / Bloodhound drew it nothing. The client never resolves
##          battlecries itself (its creatures arrive via the host's board snapshot),
##          so guarding on _is_host() is correct.
func _battlecry_gain_command(is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if _is_net():
		if _is_host():
			_net_caster_gain_mana(is_enemy, n)
	elif not is_enemy:
		player_mana += n
		_update_hud()


func _battlecry_draw(is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if _is_net():
		if _is_host():
			_net_caster_draw(is_enemy, n)
	elif not is_enemy:
		for _i in n:
			draw_one()


## Mourner's on-death "bonus_mana": +n max Command on the owner's NEXT turn.
## Rides _bonus_mana_next_turn (above the banking cap), so it can't ship through
## the immediate EV_MANA grant — the client's own _start_round must fold it in.
## Ownership split matches _battlecry_gain_command: solo enemy deaths no-op; in
## net the host applies its own side locally and ships a CLIENT death's bump
## over EV_MANA with next=true.
func _battlecry_bonus_mana_next_turn(is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if _is_net():
		if not _is_host():
			return
		if is_enemy:
			NetMatch.send_to_client({"t": NetMatch.EV_MANA, "n": n, "next": true})
		else:
			_bonus_mana_next_turn += n
	elif not is_enemy:
		_bonus_mana_next_turn += n


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
			# --- BOARD MANIPULATION (4x4 position verbs) ---
			"shove_back":
				# Shove: push the opposing FRONT creature into its own back row,
				# clearing your lane to reach the back line or face. If its back
				# lane is blocked (or the front is empty) it can't be moved, so
				# deal `value` to the column's target instead — never a dead play.
				var front_opp = _row_array(not is_enemy, ROW_FRONT)[lane_idx]
				var pushed := false
				if front_opp != null and is_instance_valid(front_opp):
					pushed = _relocate_creature(front_opp, not is_enemy, ROW_BACK, lane_idx)
					if pushed:
						spawn_floating_number(front_opp.global_position \
							+ Vector2(front_opp.size.x * front_opp.scale.x * 0.5, -10),
							"SHOVED", Color(0.75, 0.85, 1.0), false)
				if not pushed:
					var t = get_opposing_card(lane_idx, is_enemy)
					if t != null:
						t.take_damage(floop_data.value)
			"buff_row_atk":
				# Drillmaster: the row drills as one — every OTHER friendly in
				# this creature's row gains +value ATK for the fight. Row choice
				# is the decision: plant him where the line is longest.
				var drill_row = _row_array(is_enemy, card.current_row)
				for dc in drill_row:
					if dc != null and is_instance_valid(dc) and dc != card \
							and dc.current_hp > 0:
						dc.current_atk += int(floop_data.value)
						dc.update_stat_display()
						spawn_floating_number(dc.global_position \
							+ Vector2(dc.size.x * dc.scale.x * 0.5, -10),
							"+%d ATK" % int(floop_data.value),
							Color(1.0, 0.84, 0.35), false)
			"haul_front":
				# Hook: drag the opposing BACK-row creature to the front, exposing a
				# hidden Ranged / support body to combat, and deal `value` to it. If
				# the front is occupied or the back is empty, just deal `value` to
				# whatever the lane would hit.
				var back_opp = _row_array(not is_enemy, ROW_BACK)[lane_idx]
				var pulled := false
				if back_opp != null and is_instance_valid(back_opp):
					pulled = _relocate_creature(back_opp, not is_enemy, ROW_FRONT, lane_idx)
					if pulled:
						spawn_floating_number(back_opp.global_position \
							+ Vector2(back_opp.size.x * back_opp.scale.x * 0.5, -10),
							"HOOKED", Color(1.0, 0.82, 0.4), false)
						back_opp.take_damage(floop_data.value)
						# Harpy: the hauled creature lands winded — it forfeits its
						# attack this round (the assisted-assassination window).
						if bool(floop_data.get("stun", false)) \
								and is_instance_valid(back_opp) and back_opp.current_hp > 0:
							back_opp.state.stunned = true
							if back_opp.has_method("_spawn_keyword_chip"):
								back_opp._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
				if not pulled:
					# No hook landed (front held / back empty): the talons rake the
					# lane's front instead — same damage, same winding, never a dead
					# On-Enter just because the enemy keeps no reserve.
					var t2 = get_opposing_card(lane_idx, is_enemy)
					if t2 != null:
						t2.take_damage(floop_data.value)
						if bool(floop_data.get("stun", false)) and is_instance_valid(t2) and t2.current_hp > 0:
							t2.state.stunned = true
							if t2.has_method("_spawn_keyword_chip"):
								t2._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
			"vanguard_split":
				# Vanguard: placement is the decision. Played to the FRONT row it
				# gains +value ATK for the fight; played to the BACK row it draws a
				# card (the watcher reports in). current_row is set at placement.
				if card.current_row == ROW_FRONT:
					card.current_atk += int(floop_data.value)
					card.update_stat_display()
					spawn_floating_number(card.global_position \
						+ Vector2(card.size.x * card.scale.x * 0.5, -10),
						"VANGUARD +%d" % int(floop_data.value), Color(1.0, 0.78, 0.25), false)
				else:
					# Back row → the watcher reports in: the OWNER draws (the client
					# over the wire in skirmish).
					_battlecry_draw(is_enemy, 1)
			"summon_back":
				# Rat Piper: a rat scurries into the same lane's back seat
				# (one size bigger once the piper is forged); if the back seat
				# is taken, summon_token's fall-through finds the front instead.
				var rp_a: int = int(floop_data.get("atk", 1))
				var rp_h: int = int(floop_data.get("hp", 1))
				if bool(card.card_data.get("is_upgraded", false)):
					rp_a += 1
					rp_h += 1
				summon_token(rp_a, rp_h, lane_idx, is_enemy, ROW_BACK, {}, "Rat")
			"snipe_back":
				# Snipe: pick off a random enemy BACK-row creature (support dies
				# first); if the back row is empty, hit a random front body instead.
				var snipe_pool: Array = []
				for c in _row_array(not is_enemy, ROW_BACK):
					if c != null and is_instance_valid(c):
						snipe_pool.append(c)
				if snipe_pool.is_empty():
					for c in _row_array(not is_enemy, ROW_FRONT):
						if c != null and is_instance_valid(c):
							snipe_pool.append(c)
				if snipe_pool.size() > 0:
					snipe_pool[randi() % snipe_pool.size()].take_damage(floop_data.value)
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
					opp.take_damage(floop_data.value)
					if opp.current_hp <= 0:
						_battlecry_draw(is_enemy, 1)
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
				_battlecry_draw(is_enemy, int(floop_data.value))
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
				# Battlecry Command grant → goes to the creature's OWNER (the client
				# over the wire in skirmish), not always the local player.
				_battlecry_gain_command(is_enemy, int(floop_data.value))
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
			"eat_curse":
				# Sin-Eater: swallow a Curse from hand — exhaust it, grow +2/+2
				# (+3/+3 upgraded), draw 1. No Curse in hand = a plain body; the
				# hand read is player-only (enemy copies enter plain).
				if not is_enemy:
					for hc in _hand:
						if is_instance_valid(hc) and CardDB.is_curse(hc.card_id):
							_hand.erase(hc)
							if hc.get_parent() != null:
								hc.get_parent().remove_child(hc)
							_exhaust_pile.append(hc.card_id)
							hc.queue_free()
							var se_grow: int = int(floop_data.get("value", 2))
							card.current_atk += se_grow
							card.card_data.hp = int(card.card_data.get("hp", card.current_hp)) + se_grow
							card.current_hp += se_grow
							card.update_stat_display()
							draw_one()
							spawn_floating_number(card.global_position \
								+ Vector2(card.size.x * card.scale.x * 0.5, -10),
								"SIN EATEN +%d/+%d" % [se_grow, se_grow],
								Color(0.72, 0.95, 0.62), false)
							break
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
			"blood_sacrifice":
				# Kill self, give adjacent +X ATK permanent. Counts as a real
				# sacrifice — triggers Bone Pile, Butcher's Cleaver, ON_PLAYER_SACRIFICE.
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane >= 0 and adj_lane < 4 and friendly_field[adj_lane] != null:
						friendly_field[adj_lane].current_atk += floop_data.value
						friendly_field[adj_lane].update_stat_display()
				if not is_enemy:
					_trigger_player_sacrifice(card)
					# Blood Pyre cantrips: draw 1 so the sacrifice replaces its own body.
					draw_one()
				card.take_damage(999)


# =====================================================================
#  COMBAT RESOLUTION
# =====================================================================

func _do_combat() -> void:
	_phase_caption = ""   # fresh phase narration each combat (no stale-caption leak)
	_update_hud()
	_refresh_adjacency_buffs()

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

	# PHASE NARRATION: caption a sub-phase only when it will actually do
	# something, so the phase line never names an empty beat. Swift is named
	# only if a Swift creature is poised to strike (granted Swift — War Cry,
	# Battle Drummer — counts too, so the caption matches the real phase).
	for c in _all_creatures_both_sides():
		if _is_swift_attacker(c) and c.can_attack() and not c.has_attacked_this_turn:
			_set_phase_caption("SWIFT STRIKES")
			break

	# SWIFT PHASE — front row first, then back row. Both rows attack regardless
	# of whether their own column's front is occupied (back is queue space, not
	# a separate combat tier). Each strike is awaited so the swing reads as a
	# lane-by-lane cascade (lunge → impact → beat) rather than one instant burst.
	# Deaths are HELD for the whole phase (see Card2D.defer_deaths) so a Swift
	# creature slain by another Swift creature still trades its blow — Swift-vs-
	# Swift resolves simultaneously, while Swift-vs-normal still denies retaliation
	# (the normal creature isn't a Swift attacker, so it never swings this phase).
	# Swift Boots: the fight's first Swift phase with a friendly striker pays a
	# card — the pre-scan mirrors the caption check above.
	if _has_relic("swift_boots") and not _swift_boots_drawn_this_fight:
		for sb_c in _all_player_creatures():
			if _is_swift_attacker(sb_c) and sb_c.can_attack() and not sb_c.has_attacked_this_turn:
				_swift_boots_drawn_this_fight = true
				draw_one()
				_show_info("Swift Boots — first blood to the fast: draw 1.")
				break
	Card2D.defer_deaths = true
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_swift_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
		await _resolve_swift_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_swift_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)
		await _resolve_swift_attack(lane_idx, ROW_BACK, true, player_front_empty_at_start)
	Card2D.defer_deaths = false

	_cleanup_dead()

	# CLASH caption (guarded) — show only if someone is still poised to strike.
	# Snapshot the headcount so we can tell afterward whether anyone fell.
	var _alive_before_clash := _all_creatures_both_sides().size()
	for c in _all_creatures_both_sides():
		if c.can_attack() and not c.has_attacked_this_turn:
			_set_phase_caption("CLASH")
			break

	# SIMULTANEOUS COMBAT — both sides attack per lane and deaths are HELD until
	# the whole clash resolves (Card2D.defer_deaths), so a creature slain by the
	# first striker still lands its own already-scheduled blow. A mutual kill drops
	# BOTH creatures; nobody gets a de-facto Swift for attacking first. Front row
	# first, then back row. _cleanup_dead below flushes the held deaths together.
	Card2D.defer_deaths = true
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_FRONT, false, enemy_front_empty_at_start)
		await _resolve_column_attack(lane_idx, ROW_FRONT, true, player_front_empty_at_start)
	for lane_idx in range(LANES_PER_ROW):
		await _resolve_column_attack(lane_idx, ROW_BACK, false, enemy_front_empty_at_start)
		await _resolve_column_attack(lane_idx, ROW_BACK, true, player_front_empty_at_start)
	Card2D.defer_deaths = false
	# Flush the held mutual kills together (on_death, slot clear, adjacency) BEFORE
	# Ranged, so snipers reach over a settled board and chain on their own real kills.
	_cleanup_dead()

	# THE DOUBLED HOUR — a side whose hour was doubled strikes a second time
	# before the ranged phase. Stunned/frozen stay benched; deaths held so the
	# second wave still resolves simultaneously.
	await _run_doubled_hour_swing(player_front_empty_at_start, enemy_front_empty_at_start)
	# Twinblade — creatures that attack twice take their second swing here.
	await _run_twinblade_swings(player_front_empty_at_start, enemy_front_empty_at_start)

	# Process Sniper attacks (lowest-HP enemy, any lane, chaining on each kill).
	await _resolve_ranged_attacks()
	# The Doubled Hour also lets that side's snipers loose a second volley.
	await _run_doubled_hour_snipe()

	# Berserker growth — scan both rows on both sides. `grow` = per-attack ATK gain.
	for c in _all_creatures_both_sides():
		if c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
			c.current_atk += int(c.card_data.get("grow", 1))
			c.update_stat_display()

	_cleanup_dead()

	# THE FALLEN — name the death beat, but only if the clash actually killed
	# something, so the caption never lies about a bloodless trade.
	var fallen_n: int = _alive_before_clash - _all_creatures_both_sides().size()
	if fallen_n > 0:
		_set_phase_caption("THE FALLEN")
	# A mass grave is a beat, not a blink: 3+ dead in one clash gets a heavier
	# shake and holds the settled carnage a moment longer. Deliberately NOT
	# Engine.time_scale — that is global, would fight the player's anim-speed
	# preference (which already scales _short_pause), and would stretch the MP
	# replay clocks.
	if fallen_n >= 3:
		screen_shake(11.0)
		await _short_pause(HITSTOP_BEAT * 2.0)

	await _short_pause(COMBAT_PAUSE_SHORT)
	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		_post_combat_sequence()


## The Doubled Hour: re-run the column-attack pass for each side whose hour was
## doubled this round. Creatures that already swung get their attack flag back
## (stunned/frozen stay benched); deaths are held so the second wave resolves
## simultaneously, same as the main clash. Shared by solo _do_combat and
## _net_run_clash — the flag arrays are per side (0 = player/host, 1 = enemy/client).
func _run_doubled_hour_swing(player_front_empty: Array[bool],
		enemy_front_empty: Array[bool]) -> void:
	for dh_enemy in [false, true]:
		if not _doubled_hour[1 if dh_enemy else 0]:
			continue
		_set_phase_caption("THE DOUBLED HOUR")
		_net_log_caption("THE DOUBLED HOUR")   # mirror the caption to the client's replay
		for c in _all_friendly(dh_enemy):
			if is_instance_valid(c) and not c.state.stunned and not c.state.is_frozen:
				c.has_attacked_this_turn = false
		Card2D.defer_deaths = true
		for lane_idx in range(LANES_PER_ROW):
			await _resolve_column_attack(lane_idx, ROW_FRONT, dh_enemy,
				player_front_empty if dh_enemy else enemy_front_empty)
		for lane_idx in range(LANES_PER_ROW):
			await _resolve_column_attack(lane_idx, ROW_BACK, dh_enemy,
				player_front_empty if dh_enemy else enemy_front_empty)
		Card2D.defer_deaths = false
		_cleanup_dead()


## The Doubled Hour, sniper edition: after the normal ranged phase, un-flag the
## doubled side's snipers so a second _resolve_ranged_attacks pass fires only them.
func _run_doubled_hour_snipe() -> void:
	if not (_doubled_hour[0] or _doubled_hour[1]):
		return
	var any_sniper := false
	for dh_enemy in [false, true]:
		if not _doubled_hour[1 if dh_enemy else 0]:
			continue
		for c in _all_friendly(dh_enemy):
			if is_instance_valid(c) and _is_sniper(c, dh_enemy, c.current_row) \
					and not c.state.stunned and not c.state.is_frozen:
				c.has_attacked_this_turn = false
				any_sniper = true
	if any_sniper:
		await _resolve_ranged_attacks()


## Twinblade (attacks_twice): after the main clash (and any Doubled Hour), each
## creature with the passive that already swung gets its attack back and swings
## once more. Deaths held so second swings resolve simultaneously. Shared by
## solo _do_combat and the net clash, same as the Doubled Hour passes.
func _run_twinblade_swings(player_front_empty: Array[bool],
		enemy_front_empty: Array[bool]) -> void:
	var any := false
	for tb_enemy in [false, true]:
		for c in _all_friendly(tb_enemy):
			if is_instance_valid(c) and c.card_data.get("passive", "") == "attacks_twice" \
					and c.has_attacked_this_turn \
					and not c.state.stunned and not c.state.is_frozen:
				c.has_attacked_this_turn = false
				any = true
	if not any:
		return
	Card2D.defer_deaths = true
	for tb_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			for lane_idx in range(LANES_PER_ROW):
				var c = _row_array(tb_enemy, row)[lane_idx]
				if c != null and is_instance_valid(c) \
						and c.card_data.get("passive", "") == "attacks_twice" \
						and not c.has_attacked_this_turn:
					await _resolve_column_attack(lane_idx, row, tb_enemy,
						player_front_empty if tb_enemy else enemy_front_empty)
	Card2D.defer_deaths = false
	_cleanup_dead()


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
	# Snipers don't fight their own column — they resolve later in the dedicated
	# ranged phase (_resolve_ranged_attacks), striking the lowest-HP enemy and
	# chaining on kills. Skipping here is what makes Sniper actually fire: before
	# this guard, snipers attacked their column first, set has_attacked_this_turn,
	# and were then skipped by the ranged phase — so the snipe never happened.
	if _is_sniper(attacker, is_enemy, row):
		return

	# Pick target: opposing front in this column, else opposing back, else face.
	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]

	# Hydra (passive) OR Charge! spell (per-turn meta): strikes every opposing
	# creature at once (Hydra takes each defender's counter back; Charge! takes 1).
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
		await _creature_attacks_creature(attacker, _redirect_target(opp_front, opp_is_enemy, lane_idx, ROW_FRONT, attacker), lane_idx, is_enemy)
	elif opp_back != null and opp_back.current_hp > 0 and not opp_back.has_keyword("structure"):
		# Front died or never existed — back row is now exposed.
		await _creature_attacks_creature(attacker, _redirect_target(opp_back, opp_is_enemy, lane_idx, ROW_BACK, attacker), lane_idx, is_enemy)
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
	# Swift can also be granted: War Cry's per-turn rally or a Battle Drummer
	# beating beside this creature (both meta flags — see _is_swift_attacker).
	if not _is_swift_attacker(card):
		return
	card.has_attacked_this_turn = true
	if card.has_method("play_attack_lunge"):
		card.play_attack_lunge(
			_lunge_strength(_effective_attack(card, lane_idx, is_enemy)))
	_net_log_lunge(card)
	await _short_pause(LUNGE_APEX)
	if not is_instance_valid(card):
		return

	var opp_is_enemy = not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane_idx]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane_idx]
	var opponent: Control = null
	if opp_front != null:
		opponent = _redirect_target(opp_front, opp_is_enemy, lane_idx, ROW_FRONT, card)
	elif opp_back != null and not opp_back.has_keyword("structure"):
		# Structures are board objects — Swift attackers slip past them to
		# face damage (handled below) instead of plinking the Pyre.
		opponent = _redirect_target(opp_back, opp_is_enemy, lane_idx, ROW_BACK, card)

	if opponent != null:
		var atk = _effective_attack(card, lane_idx, is_enemy)
		# Marked/enrage vulnerability bonus damage (mirror the column-attack path)
		if opponent.get_meta("marked", false):
			atk += 2
		if opponent.get_meta("enrage_vulnerable", false):
			atk += 1
		_play_attack_tracer(_card_center(card), _card_center(opponent), is_enemy)
		if opponent.has_method("play_hit_recoil"):
			opponent.play_hit_recoil(is_enemy)
		_apply_thorns(opponent, card, is_enemy)
		var swift_hp_before: int = opponent.current_hp
		_log_event("%s strikes %s for [color=#f2e6c8]%d[/color]." \
			% [_log_card_ref(card), _log_card_ref(opponent), atk],
			_log_data(card), _log_side(card))
		opponent.take_damage(atk)
		var swift_dealt: bool = opponent.current_hp < swift_hp_before
		# Poison: swift attacker with Poison kills defender on any hit.
		# Virulence (Unclean Blessing) makes the whole side's attacks poisonous.
		if opponent.current_hp > 0 and atk > 0 \
				and (card.has_keyword("poison") or _virulence_active[1 if is_enemy else 0]):
			opponent.current_hp = 0
			opponent.update_stat_display()
			spawn_keyword_callout_kw(opponent, "poison")
			if not Card2D.defer_deaths:
				opponent.try_die()
		_net_log_hit(card, opponent, swift_hp_before)
		var was_lethal: bool = opponent.current_hp <= 0
		if is_instance_valid(card) and is_instance_valid(opponent):
			_spawn_impact_burst(_card_center(opponent),
				_card_center(opponent) - _card_center(card), float(atk), was_lethal)
		if was_lethal and (card.has_keyword("piercing") or (is_enemy and _has_encounter_passive_keyword(card, "piercing")) or card.get_meta("inspire_piercing", false) or (not is_enemy and _has_relic("piercing_crown"))):
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
			var splash_hp_before: int = int(target.current_hp)
			target.take_damage(1)
			_net_log_hit(attacker, target, splash_hp_before)


func _apply_piercing_overflow(attacker: Control, victim: Control, lane_idx: int,
		is_enemy: bool, victim_pos: Dictionary = {}) -> void:
	# Piercing kill: overflow damage spills to the next creature in the same
	# opposing column (front→back), then to face if nothing left in column.
	var excess = abs(victim.current_hp)
	var total = excess
	if total <= 0:
		return
	# Float a "PIERCING N" chip at the attacker so the overflow is visible.
	if is_instance_valid(attacker):
		var pierce_pos := attacker.global_position + Vector2(attacker.size.x * attacker.scale.x * 0.5, -12)
		spawn_keyword_callout(pierce_pos, "PIERCING %d" % total,
			_CALLOUT_STYLE["piercing"]["col"], GameTheme.get_keyword_icon("piercing"))
		# Visual parity: replay this on the client too, anchored on the attacker eid
		# (it survives a piercing kill, so it's a reliable anchor — see _net_fx_queue).
		if _is_host() and int(attacker.entity_id) >= 0:
			var pc: Color = _CALLOUT_STYLE["piercing"]["col"]
			_net_fx_queue.append({
				"eid": int(attacker.entity_id), "label": "PIERCING %d" % total,
				"col": [pc.r, pc.g, pc.b],
			})
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
			_net_log_pierce(attacker, victim)   # replay the skewer on the client
	var opp_is_enemy = not is_enemy
	# Spill into the VICTIM's own column, not the attacker's lane. A Guardian /
	# redirecting Royal Guard pulls the hit one lane over, so the slain blocker can
	# sit in a different column than lane_idx — trusting lane_idx there spilled the
	# overflow to face instead of the creature standing behind the blocker. The
	# victim is still in the board arrays at this point (death cleanup runs later),
	# so _find_creature_position resolves it; fall back to lane_idx if it doesn't.
	var spill_lane: int = lane_idx
	var spill_is_enemy: bool = opp_is_enemy
	var victim_is_front: bool = true
	var vpos := victim_pos if not victim_pos.is_empty() else _find_creature_position(victim)
	if not vpos.is_empty():
		spill_lane = int(vpos["lane"])
		spill_is_enemy = bool(vpos["is_enemy"])
		victim_is_front = int(vpos["row"]) == ROW_FRONT
	# If we killed a front-row creature, spill to the back creature in its column.
	var back_card = _row_array(spill_is_enemy, ROW_BACK)[spill_lane]
	if victim_is_front and back_card != null and back_card.current_hp > 0:
		var spill_hp_before: int = int(back_card.current_hp)
		back_card.take_damage(total)
		_net_log_hit(attacker, back_card, spill_hp_before)
		return
	# Otherwise go face. Attack damage, not an effect (piercing spill rides the
	# strike that caused it) — grows_on_burn wardens don't feed on it.
	if is_enemy:
		damage_player_hero(total, false)
	else:
		damage_enemy_hero(total, false)


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
	# (Ember Warden's old feeds_on_doom hook lived here; its 2026-07-02 redesign
	# is grows_on_burn — the detonation's face damage below feeds it generically
	# through damage_enemy_hero's from_effect path instead.)
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
		if ll > 0:
			player_hp = mini(player_hp + ll, player_max_hp)
			_show_lifelink_heal(ll)
			_stoke_acolytes(false)
			_update_hud()
	# Net mirror: the CLIENT's Lifelink heals the client's hero (the host's enemy hero).
	elif dealt_damage and attacker_is_enemy and _is_net() and attacker.has_keyword("lifelink"):
		var llc: int = int(attacker.card_data.get("lifelink", 1))
		if llc > 0:
			_net_heal_hero(true, llc)
			_update_hud()
	# Rampage — permanent +ATK on every combat kill, for the rest of the fight.
	if defender_was_killed and attacker.has_keyword("rampage"):
		var amt: int = int(attacker.card_data.get("rampage", 1))
		if bool(attacker.card_data.get("is_upgraded", false)):
			amt += 1
		if amt > 0:
			attacker.persistent_atk_buff += amt
			attacker.persistent_atk_buff_rounds = 99  # effectively permanent this fight
			attacker.update_stat_display()
			var rp_pos := attacker.global_position + Vector2(attacker.size.x * attacker.scale.x * 0.5, -10)
			spawn_floating_number(rp_pos, "RAMPAGE +%d" % amt, Color(1.0, 0.62, 0.20), false)
	# Headhunter (draw_on_slay): a confirmed kill reports back — the OWNER draws
	# 1 (2 upgraded). Rides every combat path (swift / column / ranged / doubled);
	# _battlecry_draw routes the draw to the right hand in net and no-ops for
	# solo enemies (no hand to draw to).
	if defender_was_killed and attacker.card_data.get("passive", "") == "draw_on_slay":
		var hh_n: int = 2 if bool(attacker.card_data.get("is_upgraded", false)) else 1
		_battlecry_draw(attacker_is_enemy, hh_n)
		spawn_trigger_callout(attacker.global_position \
			+ Vector2(attacker.size.x * attacker.scale.x * 0.5, -12),
			"SLAY — DRAW %d" % hh_n if hh_n > 1 else "SLAY — DRAW",
			false, int(attacker.entity_id))
	if defender_was_killed and not attacker_is_enemy and not _is_net() \
			and attacker.card_data.get("passive", "") == "slay_gold":
		var sg_n: int = int(attacker.card_data.get("slay_gold", 5))
		RunState.gain_gold(sg_n)
		spawn_trigger_callout(attacker.global_position \
			+ Vector2(attacker.size.x * attacker.scale.x * 0.5, -12),
			"SLAY — +%d GOLD" % sg_n, false, int(attacker.entity_id))
	if defender_was_killed and attacker.card_data.get("passive", "") == "shield_on_slay":
		if not attacker.state.has_shield:
			attacker.state.has_shield = true
			if attacker.has_method("_spawn_keyword_chip"):
				attacker._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0), "shield")
		attacker.update_stat_display()
	# Campaign memory (docs/CAMPAIGN_MEMORY.md): a combat kill by a real deck
	# creature goes on its service record — tally scratches on the writ, an
	# earned name at 3, the veteran's +1/+1 at 6 (folded at next draw; the
	# live body is promoted on the spot so the moment is felt this fight).
	# Solo campaign only; tokens have no identity (uid -1).
	if defender_was_killed and not attacker_is_enemy and not _is_net() \
			and not attacker.is_token and int(attacker.deck_uid) >= 0:
		var vk: int = RunState.record_kill(int(attacker.deck_uid))
		var vk_pos := attacker.global_position \
			+ Vector2(attacker.size.x * attacker.scale.x * 0.5, -12)
		if vk == RunState.VETERAN_EPITHET_KILLS:
			spawn_trigger_callout(vk_pos, ("BLOODED — %s"
				% RunState.veteran_epithet(int(attacker.deck_uid))).to_upper(), false)
			# Letters Patent: the earned name comes with a grant of arms — +1/+1
			# permanently. The live body is promoted on the spot; the matching
			# fold in RunState.get_upgraded_card_data carries it to future draws.
			if _has_relic("letters_patent"):
				attacker.current_atk += 1
				attacker.current_hp += 1
				attacker.card_data.hp = int(attacker.card_data.get("hp", attacker.current_hp)) + 1
				attacker.update_stat_display()
				spawn_trigger_callout(vk_pos + Vector2(0, -30), "KNIGHTED +1/+1", false)
		elif vk == RunState.VETERAN_RANK_KILLS:
			attacker.current_atk += 1
			attacker.current_hp += 1
			attacker.card_data.hp = int(attacker.card_data.get("hp", attacker.current_hp)) + 1
			attacker.update_stat_display()
			spawn_trigger_callout(vk_pos, "VETERAN +1/+1", false)
		elif vk == RunState.VETERAN_SCHOOL_KILLS:
			# Rung 3 — the war school. The CHOICE fires at the top of the next
			# player phase (never mid-clash); if this was the fight's last kill,
			# the round-1 catch-up sweep re-queues it next fight.
			_war_school_queue.append(int(attacker.deck_uid))
			spawn_trigger_callout(vk_pos, "MASTER OF THE FIELD", false)


## Cinder Acolyte (grows_on_heal): every hero-heal EVENT on the owner's side
## stokes its acolytes — +1 ATK this fight (+2 upgraded). Callers only fire this
## when HP actually rose; a heal at full is not a heal.
func _stoke_acolytes(owner_is_enemy: bool = false) -> void:
	for c in _all_friendly(owner_is_enemy):
		if is_instance_valid(c) and c.card_data.get("passive", "") == "grows_on_heal":
			var ac_gain: int = 2 if bool(c.card_data.get("is_upgraded", false)) else 1
			c.current_atk += ac_gain
			c.update_stat_display()
			spawn_floating_number(c.global_position \
				+ Vector2(c.size.x * c.scale.x * 0.5, -10),
				"+%d ATK" % ac_gain, Color(1.0, 0.62, 0.20), false)
			_net_fx_text(c, "+%d ATK" % ac_gain, Color(1.0, 0.62, 0.20))


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
		attacker.play_attack_lunge(
			_lunge_strength(_effective_attack(attacker, lane_idx, attacker_is_enemy)))
	_net_log_lunge(attacker)
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
	# Impact lands: streak from attacker to target.
	_play_attack_tracer(_card_center(attacker), _card_center(defender), attacker_is_enemy)
	var hp_before: int = defender.current_hp
	# Cross-Blitz mutual trade: if this defender is about to counter (see
	# _apply_mutual_retaliation), make it LUNGE back into the attacker instead of just
	# recoiling — so both creatures visibly clash in the middle and the return blow
	# reads as a real attack, not damage from nowhere. Otherwise (solo / sealed / a
	# defender that can't answer) it recoils as before.
	var will_counter: bool = _net_mutual_retaliation and hp_before > 0 \
		and _defender_will_counter(defender)
	if will_counter and defender.has_method("play_attack_lunge"):
		defender.play_attack_lunge(
			_lunge_strength(_effective_attack(defender, defender.current_lane, defender.is_opponent)))
	elif defender.has_method("play_hit_recoil"):
		defender.play_hit_recoil(attacker_is_enemy)
	_log_event("%s strikes %s for [color=#f2e6c8]%d[/color]." \
		% [_log_card_ref(attacker), _log_card_ref(defender), atk],
		_log_data(attacker), _log_side(attacker))
	defender.take_damage(atk)
	# Did this strike actually remove HP? (A Shield absorbs the whole hit, so
	# atk > 0 but no damage was dealt — Lifelink shouldn't trigger on that.)
	var strike_dealt_damage: bool = defender.current_hp < hp_before
	attacker.has_attacked_this_turn = true
	# Poison: if attacker has Poison and dealt damage, defender dies regardless
	# of remaining HP. Shield absorbing the hit means no damage was dealt.
	# Virulence (Unclean Blessing) makes the whole side's attacks poisonous.
	if defender.current_hp > 0 and atk > 0 \
			and (attacker.has_keyword("poison") or _virulence_active[1 if attacker_is_enemy else 0]):
		defender.current_hp = 0
		defender.update_stat_display()
		spawn_keyword_callout_kw(defender, "poison")
		if not Card2D.defer_deaths:
			defender.try_die()
	_net_log_hit(attacker, defender, hp_before)
	var was_lethal: bool = defender.current_hp <= 0

	# Contact-point spark at the defender's struck edge, same visual beat as the
	# tracer/recoil above (sub-frame ordering, invisible to the player).
	if is_instance_valid(attacker) and is_instance_valid(defender):
		_spawn_impact_burst(_card_center(defender),
			_card_center(defender) - _card_center(attacker), float(atk), was_lethal)

	# Audio: the kill cue fires HERE, at the impact beat, not seconds later when
	# the deferred death flushes (defer_deaths). death_cue_played stops _die()
	# from sounding the same kill twice at the flush. Struck SURVIVORS already
	# sound inside take_damage (Card2D._flash_hit plays "hit_creature") — a cue
	# here too would double every ordinary strike. "creature_death" falls back
	# to "death" until bespoke clips land (AudioBank.SFX_FALLBACKS).
	if strike_dealt_damage and was_lethal and not defender._dead:
		defender.death_cue_played = true
		AudioBank.play_sfx("creature_death", 0.05)

	# Royal Guard "+1 ATK when hit" (+2 if upgraded) — if the defender is a
	# Royal Guard and is still alive after the hit, it grows in fury.
	if defender.current_hp > 0 and defender.card_data.get("passive", "") == "royal_guard" and atk > 0:
		var rg_gain: int = 2 if bool(defender.card_data.get("is_upgraded", false)) else 1
		defender.current_atk += rg_gain
		defender.update_stat_display()

	# Berserker "rage on hit" — surviving a hit stokes the fury: +2 ATK (+3 upgraded).
	if defender.current_hp > 0 and defender.card_data.get("passive", "") == "rage_on_hit" and atk > 0:
		var rage_gain: int = 3 if bool(defender.card_data.get("is_upgraded", false)) else 2
		defender.current_atk += rage_gain
		defender.update_stat_display()

	# Bodkin Points: every killing blow by a player creature punches through the
	# column, as if Piercing (rides the same overflow machinery + callout).
	if defender.current_hp <= 0 and (attacker.has_keyword("piercing") or (attacker_is_enemy and _has_encounter_passive_keyword(attacker, "piercing")) or attacker.get_meta("inspire_piercing", false) or (not attacker_is_enemy and _has_relic("piercing_crown"))):
		_apply_piercing_overflow(attacker, defender, lane_idx, attacker_is_enemy)

	# Vampire Lord passive: heal 2 and +1 ATK on kill (+2 ATK if upgraded). The heal
	# goes to the attacker's OWN hero — solo only fires for the player; net mirrors it
	# so a Player-2 Vampire Lord heals Player 2 (the host's enemy hero).
	if attacker.card_data.get("passive", "") == "vampire_lord" and defender.current_hp <= 0:
		var vamp_gain: int = 2 if bool(attacker.card_data.get("is_upgraded", false)) else 1
		if not attacker_is_enemy:
			if player_hp < player_max_hp:
				player_hp = mini(player_hp + 2, player_max_hp)
				_stoke_acolytes(false)
			attacker.current_atk += vamp_gain
			attacker.update_stat_display()
		elif _is_net():
			enemy_hp = mini(enemy_hp + 2, SkirmishState.START_HP)
			attacker.current_atk += vamp_gain
			attacker.update_stat_display()

	# Keyword riders: Lifelink (heal on damage) + Rampage (+ATK on kill).
	_apply_combat_strike_riders(attacker, strike_dealt_damage, was_lethal, attacker_is_enemy)

	# Cross-Blitz mutual trade: in the MP one-directional clash the just-struck
	# defender fires its ATK straight back at the attacker, so an even fight kills
	# both. Only armed for that pass (_net_mutual_retaliation); solo/sealed already
	# resolve simultaneously. hp_before > 0 confirms the defender was alive when hit
	# (the caller only engages living creatures, so this is belt-and-suspenders).
	if _net_mutual_retaliation and hp_before > 0:
		_apply_mutual_retaliation(attacker, defender, attacker_is_enemy)

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


## Can this defender answer a hit with a counter right now? Shared gate so the strike's
## choreography (defender lunges back vs just recoils) and the actual counter agree.
## Frozen/stunned = incapacitated (no counter); a spent defender already answered this
## clash; a 0-ATK body has nothing to hit back with.
func _defender_will_counter(defender: Control) -> bool:
	if defender == null or not is_instance_valid(defender):
		return false
	if defender.get_meta("counter_spent_this_clash", false):
		return false
	if defender.state.is_frozen or defender.state.stunned:
		return false
	return _effective_attack(defender, defender.current_lane, defender.is_opponent) > 0


## Cross-Blitz counterstrike (MP one-directional clash only). The defender that just
## took a hit deals its own ATK back to the attacker in the same beat — the return
## half of a mutual trade. This is NOT a full attack: it does not spend the defender's
## own-turn swing (has_attacked_this_turn), grow Rampage, feed veterancy, or re-apply
## Thorns (the attacker already ate the defender's Thorns on its way in). Each defender
## counters ONCE per clash (counter_spent_this_clash), against the first creature to
## engage it — mirroring solo, where a creature deals its ATK just once per combat and
## only to the front foe across from it. Deaths stay deferred, so an even trade drops
## both. Poison/Virulence on the defender carries through the counter (a real trade).
## The defender's return LUNGE is already playing (started in _creature_attacks_creature
## when will_counter was set), so this only lands the damage + tracer.
func _apply_mutual_retaliation(attacker: Control, defender: Control, attacker_is_enemy: bool) -> void:
	if not _defender_will_counter(defender):
		return
	if not is_instance_valid(attacker) or attacker.current_hp <= 0:
		return
	var defender_is_enemy: bool = not attacker_is_enemy
	# lane arg is unused by _effective_attack (adjacency is baked into effective_atk),
	# so the defender's own stored lane is enough for the buff/relic lookups.
	var retal: int = _effective_attack(defender, defender.current_lane, defender_is_enemy)
	if retal <= 0:
		return
	defender.set_meta("counter_spent_this_clash", true)
	# Return blow: a tracer from the defender back to its attacker. Do NOT call
	# play_hit_recoil on the attacker here — it is STILL MID-LUNGE (its lunge tween
	# is running), and a recoil tween fights it for `position`/`scale`, capturing a
	# mid-lunge point as "rest" and leaving the card drifted out of its slot (which
	# compounds every trade). take_damage() below already flashes the struck attacker
	# (_flash_hit / _mark_mortally_struck), so the counter still reads without a
	# second position tween. The defender's own bite-back is shown by its lunge (above).
	_play_attack_tracer(_card_center(defender), _card_center(attacker), defender_is_enemy)
	var a_hp_before: int = attacker.current_hp
	_log_event("%s strikes back at %s for [color=#f2e6c8]%d[/color]." \
		% [_log_card_ref(defender), _log_card_ref(attacker), retal],
		_log_data(defender), _log_side(defender))
	attacker.take_damage(retal)
	var counter_dealt: bool = attacker.current_hp < a_hp_before
	# Poison / Virulence: a countering defender with Poison finishes the attacker.
	if attacker.current_hp > 0 and retal > 0 \
			and (defender.has_keyword("poison") or _virulence_active[1 if defender_is_enemy else 0]):
		attacker.current_hp = 0
		attacker.update_stat_display()
		spawn_keyword_callout_kw(attacker, "poison")
		if not Card2D.defer_deaths:
			attacker.try_die()
	# Log the counter as a strike from defender→attacker so the client replays it
	# (tracer + damage chip + kill cue). is_counter=true tells the replay to skip the
	# position recoil on the (still-lunging) attacker — same reason as above.
	_net_log_hit(defender, attacker, a_hp_before, true)
	var counter_lethal: bool = attacker.current_hp <= 0
	if is_instance_valid(defender) and is_instance_valid(attacker):
		_spawn_impact_burst(_card_center(attacker),
			_card_center(attacker) - _card_center(defender), float(retal), counter_lethal)
	# Kill cue at the impact beat (parity with the forward strike); death_cue_played
	# stops the deferred flush from sounding the same kill twice.
	if counter_dealt and counter_lethal and not attacker._dead:
		attacker.death_cue_played = true
		AudioBank.play_sfx("creature_death", 0.05)


func _creature_hits_face(card: Control, lane_idx: int, is_enemy: bool) -> void:
	if card.has_method("play_attack_lunge"):
		card.play_attack_lunge(
			_lunge_strength(_effective_attack(card, lane_idx, is_enemy)))
	_net_log_lunge(card)
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
			damage_player_hero(atk, false)
			face_dealt = true
	else:
		# Host/player attacker → defender is the enemy/client. In net the CLIENT's walls
		# blunt the hit (solo enemies have no wall passives, so this is a no-op there).
		if _is_net():
			atk = maxi(0, atk - _get_wall_reduction(lane_idx, true))
		if atk > 0:
			damage_enemy_hero(atk, false)
		face_dealt = atk > 0

	card.has_attacked_this_turn = true
	# Keyword riders: Lifelink heals when this creature lands face damage (no
	# defender to kill, so Rampage never fires here).
	_apply_combat_strike_riders(card, face_dealt, false, is_enemy)
	# Hero-damage functions already shake + flash; just pace the cascade.
	await _short_pause(HITSTOP_BEAT if atk > 0 else POST_HIT_BEAT)


func _resolve_hydra_attack(attacker: Control, lane_idx: int, is_enemy: bool) -> void:
	# Hydra strikes every opposing creature (both rows) at once, taking each
	# defender's counterattack back as it bites through the line (its Armored
	# softens each). If nothing opposes it, it batters the face like any
	# unblocked creature.
	attacker.has_attacked_this_turn = true
	if attacker.has_method("play_attack_lunge"):
		attacker.play_attack_lunge()
	_net_log_lunge(attacker)
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
			damage_player_hero(atk, false)
		else:
			damage_enemy_hero(atk, false)
		# Lifelink heals once for the unblocked face swing.
		_apply_combat_strike_riders(attacker, atk > 0, false, is_enemy)
		await _short_pause(HITSTOP_BEAT)
		return
	# Bites through the whole line at once — streak + recoil on every target.
	# Lifelink heals once for the swing; Rampage fires PER KILL (a full-line
	# sweep is the Hydra's whole payoff — 3 kills = 3 Rampage triggers).
	var hydra_dealt: bool = false
	var hydra_kills: int = 0
	for t in live:
		_play_attack_tracer(_card_center(attacker), _card_center(t), is_enemy)
		if t.has_method("play_hit_recoil"):
			t.play_hit_recoil(is_enemy)
		var t_hp_before: int = t.current_hp
		_log_event("%s bites %s for [color=#f2e6c8]%d[/color]." \
			% [_log_card_ref(attacker), _log_card_ref(t), atk],
			_log_data(attacker), _log_side(attacker))
		t.take_damage(atk)
		if t.current_hp < t_hp_before:
			hydra_dealt = true
		if t.current_hp <= 0:
			hydra_kills += 1
		if attacker.current_hp > 0:
			# Hydra passive takes each bitten defender's FULL counterattack back
			# (Armored on the Hydra softens each blow); the Charge! spell, which
			# borrows this sweep for one turn, keeps the gentler flat-1 recoil.
			var recoil: int = 1
			if attacker.card_data.get("passive", "") == "attacks_all_lanes":
				recoil = _effective_attack(t, t.current_lane, t.is_opponent)
			if recoil > 0:
				attacker.take_damage(recoil)
		_net_log_hit(attacker, t, t_hp_before)
	if is_instance_valid(attacker):
		_apply_combat_strike_riders(attacker, hydra_dealt, hydra_kills > 0, is_enemy)
		# Extra kills beyond the first re-fire the kill-gated riders only
		# (dealt=false keeps Lifelink at once per swing).
		for _hk in range(maxi(0, hydra_kills - 1)):
			if not is_instance_valid(attacker):
				break
			_apply_combat_strike_riders(attacker, false, true, is_enemy)
	screen_shake(6.0)
	await _short_pause(HITSTOP_BEAT)


func _redirect_target(defender: Control, defender_is_enemy: bool, lane_idx: int, row: int,
		attacker: Control = null) -> Control:
	# Royal Guard's redirect floop: a friendly Royal Guard in the same row that
	# is "redirecting" and sits adjacent to the intended defender intercepts the
	# blow in its place.
	# Guardian keyword: permanently redirects adjacent attacks (no floop needed).
	# Siege Golem (unstoppable): the ram hits what it aims at — no interception.
	if attacker != null and is_instance_valid(attacker) \
			and bool(attacker.card_data.get("unstoppable", false)):
		return defender
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


## Swift can be intrinsic (keyword), rallied for the turn by War Cry, or held
## from an adjacent Battle Drummer — one check for every Swift-phase site so
## granted Swift and printed Swift never disagree.
func _is_swift_attacker(c: Control) -> bool:
	return c.has_keyword("swift") or bool(c.get_meta("war_cry_swift", false)) \
		or bool(c.get_meta("drummer_swift", false))


func _resolve_ranged_attacks(side_filter: int = -1) -> void:
	# 4x4: ranged prefers back-row enemies (you can reach over the front line),
	# then front-row enemies, then face damage if the opposing side is empty.
	# side_filter: -1 = both sides (solo simultaneous combat); 0 = player side
	# only, 1 = enemy side only (skirmish one-directional clash).
	var sides: Array = [false, true]
	if side_filter == 0:
		sides = [false]
	elif side_filter == 1:
		sides = [true]
	for is_enemy in sides:
		for row in [ROW_FRONT, ROW_BACK]:
			var attackers = _row_array(is_enemy, row)
			for lane_idx in range(LANES_PER_ROW):
				var card = attackers[lane_idx]
				if card == null:
					continue
				if not _is_sniper(card, is_enemy, row):
					continue
				if card.has_attacked_this_turn or not card.can_attack():
					continue
				card.has_attacked_this_turn = true
				if card.has_method("play_attack_lunge"):
					card.play_attack_lunge()
				_net_log_lunge(card)
				await _short_pause(LUNGE_APEX)
				if not is_instance_valid(card):
					continue
				await _sniper_fire(card, lane_idx, is_enemy)


func _is_sniper(card: Control, is_enemy: bool, row: int) -> bool:
	# Sniper is a real keyword. Catapult Crew still grants it dynamically to the
	# player's back row, and the legacy `sniper` flag is honored for old saves.
	if card == null or not is_instance_valid(card):
		return false
	if card.has_keyword("sniper"):
		return true
	if bool(card.card_data.get("sniper", false)):
		return true
	if not is_enemy and row == ROW_BACK and _has_relic("catapult_crew"):
		return true
	return false


func _sniper_pick_lowest(opp_is_enemy: bool, skip_back: bool) -> Control:
	# Lowest-HP living enemy creature (structures aren't valid targets). Ties:
	# first found (front row before back).
	var best: Control = null
	for r in [ROW_FRONT, ROW_BACK]:
		if skip_back and r == ROW_BACK:
			continue
		for l in range(LANES_PER_ROW):
			var c = _row_array(opp_is_enemy, r)[l]
			if c != null and is_instance_valid(c) and c.current_hp > 0 \
					and not c.has_keyword("structure"):
				if best == null or c.current_hp < best.current_hp:
					best = c
	return best


func _sniper_can_keep_firing(card: Control) -> bool:
	# _resolve_ranged_attacks marks the sniper as spent before entering the shot
	# loop, so Card2D.can_attack() would always reject the actual shot. Re-check
	# the real incapacitating states here without reading has_attacked_this_turn.
	if card == null or not is_instance_valid(card) or card.current_hp <= 0:
		return false
	if card.will_floop or card.has_flooped_this_turn:
		return false
	if card.state.is_frozen or card.state.stunned:
		return false
	if card.has_keyword("structure"):
		return false
	if card.card_data.get("passive", "") == "cannot_attack_wall":
		return false
	return true


func _sniper_fire(card: Control, lane_idx: int, is_enemy: bool) -> void:
	# Sniper: fire at the lowest-HP enemy; if the shot kills, fire again at the
	# next-weakest — a marksman cleaning up a softened line. ATK is recomputed per
	# shot so Rampage (+ATK on kill) compounds down the chain; Lifelink heals per
	# hit. Each shot kills (shrinking the pool) or stops, so it always terminates.
	var opp_is_enemy := not is_enemy
	for _shot in range(8):
		if not _sniper_can_keep_firing(card):
			return
		var target := _sniper_pick_lowest(opp_is_enemy, false)
		var atk := _effective_attack(card, lane_idx, is_enemy)
		if target == null:
			# Nothing to shoot: only the OPENING shot carries to face (a chain that
			# already cleared the board doesn't keep plinking the hero).
			if _shot == 0:
				if is_enemy:
					damage_player_hero(atk, false)
				else:
					damage_enemy_hero(atk, false)
				_apply_combat_strike_riders(card, atk > 0, false, is_enemy)
				await _short_pause(POST_HIT_BEAT)
			return
		_play_attack_tracer(_card_center(card), _card_center(target), is_enemy)
		if target.has_method("play_hit_recoil"):
			target.play_hit_recoil(is_enemy)
		var t_pos := _find_creature_position(target)
		var target_lane: int = int(t_pos.get("lane", lane_idx)) if not t_pos.is_empty() else lane_idx
		atk = _effective_attack(card, lane_idx, is_enemy)
		if target.get_meta("marked", false):
			atk += 2
		if target.get_meta("enrage_vulnerable", false):
			atk += 1
		_apply_thorns(target, card, is_enemy)
		if _has_adjacent_royal_guard(target):
			atk = maxi(1, atk - 1)
		if _encounter_passive == "archlich_immortal" and not is_enemy:
			var new_hp: int = target.current_hp - atk
			if new_hp < 1:
				atk = maxi(0, target.current_hp - 1)
		var hp_before: int = target.current_hp
		_log_event("%s looses at %s for [color=#f2e6c8]%d[/color]." \
			% [_log_card_ref(card), _log_card_ref(target), atk],
			_log_data(card), _log_side(card))
		target.take_damage(atk)
		var dealt: bool = target.current_hp < hp_before
		if target.current_hp > 0 and dealt \
				and (card.has_keyword("poison") or _virulence_active[1 if is_enemy else 0]):
			target.current_hp = 0
			target.update_stat_display()
			spawn_keyword_callout_kw(target, "poison")
			if not Card2D.defer_deaths:
				target.try_die()
		_net_log_hit(card, target, hp_before)
		var killed: bool = not is_instance_valid(target) or target.current_hp <= 0
		if is_instance_valid(card) and is_instance_valid(target):
			_spawn_impact_burst(_card_center(target),
				_card_center(target) - _card_center(card), float(atk), killed)
		if dealt and killed and is_instance_valid(target) and not target._dead:
			target.death_cue_played = true
			AudioBank.play_sfx("creature_death", 0.05)
		if is_instance_valid(target) and target.current_hp > 0 \
				and target.card_data.get("passive", "") == "royal_guard" and atk > 0:
			var rg_gain: int = 2 if bool(target.card_data.get("is_upgraded", false)) else 1
			target.current_atk += rg_gain
			target.update_stat_display()
		if is_instance_valid(target) and target.current_hp > 0 \
				and target.card_data.get("passive", "") == "rage_on_hit" and atk > 0:
			var rage_gain: int = 3 if bool(target.card_data.get("is_upgraded", false)) else 2
			target.current_atk += rage_gain
			target.update_stat_display()
		if killed and (card.has_keyword("piercing") or (is_enemy and _has_encounter_passive_keyword(card, "piercing")) or card.get_meta("inspire_piercing", false) or (not is_enemy and _has_relic("piercing_crown"))):
			_apply_piercing_overflow(card, target, target_lane, is_enemy, t_pos)
		_apply_combat_strike_riders(card, dealt, killed, is_enemy)
		# Pavise: an enemy sniper's shot that lands on the player's BACK row is
		# answered — the shieldwall's return bolt hits the marksman for 3. A
		# dead sniper's chain ends with him. (Position captured pre-shot so a
		# killed target still reads as the back-row hit it was.)
		if is_enemy and _has_relic("hexagonal_shield") and not t_pos.is_empty() \
				and int(t_pos["row"]) == ROW_BACK:
			var pv: int = int(RelicDB.get_relic("hexagonal_shield").get("value", 3))
			spawn_floating_number(_card_center(card) + Vector2(0, -14),
				"PAVISE %d" % pv, Color(0.55, 0.78, 1.0), false)
			card.take_damage_bypass_armor(pv)
			if not is_instance_valid(card) or card.current_hp <= 0:
				return
		await _short_pause(HITSTOP_BEAT if killed else POST_HIT_BEAT)
		if not killed:
			return   # the chain only continues on a kill


func _apply_thorns(defender: Control, attacker: Control, attacker_is_enemy: bool) -> void:
	# Thorns can be intrinsic, encounter-passive granted, or temp from Shield Wall.
	# Bridge Watcher / Corner Stone relics grant Thorns 2 by lane position to the
	# player's creatures — checked alongside the existing sources so the relics
	# stack with intrinsic thorns rather than replacing them.
	# Siege Golem (unstoppable): no sting touches the ram — all Thorns sources
	# (intrinsic, granted, relic-lane, venomous) are ignored against it.
	if attacker != null and is_instance_valid(attacker) \
			and bool(attacker.card_data.get("unstoppable", false)):
		return
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
		# Bridge Watcher / Corner Stone explicitly grant Thorns 2.
		if defender_is_friendly \
				and ((_has_relic("bridge_watcher") and defender.current_lane in [1, 2]) \
					or (_has_relic("corner_stone") and defender.current_lane in [0, LANES_PER_ROW - 1])):
			thorns_dmg = maxi(thorns_dmg, 2)
		# Recoil bite: a red spark + chip on the attacker that ran onto the thorns.
		if is_instance_valid(attacker):
			spawn_ash_burst(_card_center(attacker), Color(0.85, 0.18, 0.20), 10)
			spawn_keyword_callout_kw(attacker, "thorns")
		var trap_pos := _find_creature_position(attacker)
		var pre_thorns_hp: int = attacker.current_hp
		attacker.take_damage_bypass_armor(thorns_dmg)
		# Basilisk (venom_thorns): its thorns are poisonous — a striker that bled
		# on them dies outright. A Shield that soaked the recoil blocks the venom
		# too (same "must deal damage" rule as Poison strikes).
		if bool(defender.card_data.get("venom_thorns", false)) \
				and is_instance_valid(attacker) and attacker.current_hp > 0 \
				and attacker.current_hp < pre_thorns_hp:
			attacker.current_hp = 0
			attacker.update_stat_display()
			spawn_keyword_callout_kw(attacker, "poison")
			if not Card2D.defer_deaths:
				attacker.try_die()
		# Man-Trap: an enemy that DIES on the player's thorns (the sting or the
		# venom rider above) springs the trap — its same-row neighbors take 2.
		# Position was captured before the sting, so a body already swept from
		# the arrays still reads as the lane it fell in.
		if attacker_is_enemy and _has_relic("briar_amulet") \
				and (not is_instance_valid(attacker) or attacker.current_hp <= 0) \
				and not trap_pos.is_empty() and bool(trap_pos["is_enemy"]):
			var trap_dmg: int = int(RelicDB.get_relic("briar_amulet").get("value", 2))
			var trap_arr = _row_array(true, int(trap_pos["row"]))
			for trap_adj in [int(trap_pos["lane"]) - 1, int(trap_pos["lane"]) + 1]:
				if trap_adj >= 0 and trap_adj < LANES_PER_ROW \
						and trap_arr[trap_adj] != null and trap_arr[trap_adj].current_hp > 0:
					spawn_floating_number(_card_center(trap_arr[trap_adj]) + Vector2(0, -14),
						"MAN-TRAP %d" % trap_dmg, Color(0.62, 0.80, 0.35), false)
					trap_arr[trap_adj].take_damage(trap_dmg)


func _effective_attack(card: Control, lane_idx: int, is_enemy: bool) -> int:
	# Adjacency buffs are baked into effective_atk() via the stored adj_atk_buff
	# (kept fresh by _refresh_adjacency_buffs), so they apply to BOTH sides and
	# show on the numeral — do NOT re-add them here or it double-counts.
	var atk = card.effective_atk()
	if not is_enemy:
		# Granted Swift (War Cry rally, Battle Drummer aura) counts: the boots
		# reward striking in the pre-phase, however the speed was come by.
		if _is_swift_attacker(card) and _has_relic("swift_boots"):
			atk += 1
		if _has_relic("glass_cannon"):
			atk += 1
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
		# Du-Vu Doll: +1 ATK per Curse currently in the run deck.
		if _has_relic("du_vu_doll"):
			atk += _curse_count_in_deck() * int(RelicDB.get_relic("du_vu_doll").get("value", 1))
		# Diagonal Crest: diagonal friendlies count as adjacent (the HP +1
		# half is granted at placement via _apply_linked_banner_hp's broader
		# rescan; ATK part falls through the linked_banner branch since both
		# relics share the "needs 2 adj" condition when held together).
		# (Neither uses the card adj_buff path — that is Battle Drummer's keyword,
		# now baked into effective_atk via adj_atk_buff; see the top of this func.)
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
	# Mime: the player picks ONE creature with an on-play battlecry in hand (floop
	# was folded into on_play — see _resolve_on_play_ability); it's played for free
	# with that battlecry triggered. The card stays on the board afterward (it WAS
	# played — the relic just made it free). Cancellable: closing the picker skips
	# Mime for this turn. (Headless/automation note: this awaits a picker click, so
	# test harnesses must not grant Mime — there is no one to dismiss it.)
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
	# 4x4: adjacent-buff sources contribute from the same column-1/column+1 in
	# EITHER row, because front and back share the lane semantically — this keeps
	# Bannerman-style cards strong without needing a row-aware Card2D ref here.
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
			if neighbor != null and is_instance_valid(neighbor) and neighbor.card_data.has("adj_buff"):
				total += int(neighbor.card_data.adj_buff.get("atk", 0))
				# (Banner of Unity's old "+1 to adjacency" bonus lived here —
				# redesigned 2026-07-03 into the flanked-play rally in
				# _play_creature, so adjacency math is clean again.)
	return total


## Re-tally every creature's adjacency ATK buff from scratch and push it onto the
## card so it (a) shows on the ATK numeral with a "+N ATK" pop, (b) rides the net
## board snapshot (which serialises effective_atk), and (c) applies to BOTH sides
## — an enemy/opponent Battle Drummer buffs ITS neighbours too. Called at every
## board-mutation choke point; cheap (16 slots) and only repaints cards whose
## value actually changed, so redundant calls are harmless.
##
## The net CLIENT never runs this: its creatures' current_atk already carries the
## host's buffed effective_atk straight off the snapshot, so recomputing locally
## would double-count.
func _refresh_adjacency_buffs() -> void:
	if _is_client():
		return
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var arr = _row_array(is_enemy, row)
			for lane in range(LANES_PER_ROW):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					continue
				var bonus := _get_adj_buff_atk(lane, is_enemy)
				if c.adj_atk_buff != bonus:
					c.adj_atk_buff = bonus
					if c.has_method("update_stat_display"):
						c.update_stat_display()
	# Battle Drummer (drummer_swift): adjacent friendlies (same row, ±1 lane)
	# hold Swift while the drum beats. Meta-flag grant on War Cry's channel,
	# cleared and re-derived at every board mutation so the aura moves with
	# the drummer and dies with it — see _is_swift_attacker.
	for c0 in _all_creatures_both_sides():
		if is_instance_valid(c0):
			c0.set_meta("drummer_swift", false)
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var arr = _row_array(is_enemy, row)
			for lane in range(LANES_PER_ROW):
				var dr = arr[lane]
				if dr == null or not is_instance_valid(dr) or dr.current_hp <= 0:
					continue
				if String(dr.card_data.get("passive", "")) != "drummer_swift":
					continue
				for nl in [lane - 1, lane + 1]:
					if nl < 0 or nl >= LANES_PER_ROW:
						continue
					var nb = arr[nl]
					if nb != null and is_instance_valid(nb):
						nb.set_meta("drummer_swift", true)
	# Warchief (warchief_aura): "its ATK is ALWAYS 2 plus your other creatures" —
	# recompute live at every board mutation (this runs at combat start, after
	# each death flush, and on placements), so it swings with the count as the
	# line grows or falls, not with a stale start-of-round snapshot.
	for is_enemy in [false, true]:
		var side: Array = _all_friendly(is_enemy)
		for c in side:
			if is_instance_valid(c) and c.card_data.get("passive", "") == "warchief_aura":
				var wc_atk: int = 2 + maxi(0, side.size() - 1)
				if bool(c.card_data.get("is_upgraded", false)):
					wc_atk += 1
				if c.current_atk != wc_atk:
					c.current_atk = wc_atk
					c.update_stat_display()


func _has_passive_on_field(passive_name: String) -> bool:
	for c in _all_player_creatures():
		if c.card_data.get("passive", "") == passive_name:
			return true
	return false


## Start-of-round ATK engines for one side: Riteforge (all allies +N permanently per
## round) and Warchief (ATK = 2 + other allies). Solo runs it for the player; the net
## turn machine also runs it host-side for the client (_net_open_placement, active==1).
func _apply_start_round_passives(owner_is_enemy: bool) -> void:
	var mine: Array = _all_friendly(owner_is_enemy)
	for _rf in mine:
		if _rf.card_data.get("passive", "") == "riteforge_ramp":
			var rf_gain: int = 2 if bool(_rf.card_data.get("is_upgraded", false)) else 1
			for ally in mine:
				ally.current_atk += rf_gain
				ally.update_stat_display()
	for _wc in mine:
		if _wc.card_data.get("passive", "") == "warchief_aura":
			var wc_base: int = 2 + maxi(0, mine.size() - 1)
			if bool(_wc.card_data.get("is_upgraded", false)):
				wc_base += 1
			_wc.current_atk = wc_base
			_wc.update_stat_display()
	# Summoner (summon_each_round): musters a 1/1 (2/2 upgraded) in an adjacent
	# empty column each round — front row preferred, back as fallback.
	for _sm in mine:
		if _sm.card_data.get("passive", "") != "summon_each_round":
			continue
		if not is_instance_valid(_sm):
			continue
		var sm_n: int = 2 if bool(_sm.card_data.get("is_upgraded", false)) else 1
		var sm_done := false
		for adj_lane in [_sm.current_lane - 1, _sm.current_lane + 1]:
			if sm_done or adj_lane < 0 or adj_lane >= LANES_PER_ROW:
				continue
			for adj_row in [ROW_FRONT, ROW_BACK]:
				if _row_array(owner_is_enemy, adj_row)[adj_lane] == null:
					summon_token(sm_n, sm_n, adj_lane, owner_is_enemy, adj_row)
					spawn_trigger_callout(_sm.global_position \
						+ Vector2(_sm.size.x * _sm.scale.x * 0.5, -12),
						"MUSTER", false, int(_sm.entity_id))
					sm_done = true
					break
	# Trebuchet (trebuchet_volley): pays 3 face (4 forged) each round it HOLDS
	# the back row — the wall deck's clock. Standing in the front silences it.
	for _tb in mine:
		if not is_instance_valid(_tb) or _tb.card_data.get("passive", "") != "trebuchet_volley":
			continue
		if _tb.current_row != ROW_BACK:
			continue
		var tb_dmg: int = 4 if bool(_tb.card_data.get("is_upgraded", false)) else 3
		if owner_is_enemy:
			damage_player_hero(tb_dmg)
		else:
			damage_enemy_hero(tb_dmg)
		spawn_trigger_callout(_tb.global_position + Vector2(_tb.size.x * _tb.scale.x * 0.5, -12), "VOLLEY %d" % tb_dmg, false, int(_tb.entity_id))
	# Bulwark Engine (board relic, host-authoritative in net): Armored friendlies on
	# this side gain +1 max HP (and heal the point) each round, so a wall thickens.
	# Lives here — the per-side start-round chokepoint — so the client's own copy
	# fires host-side and rides the board snapshot; see _relic_active_for_side.
	if _relic_active_for_side(owner_is_enemy, "bulwark_engine"):
		var be: int = int(RelicDB.get_relic("bulwark_engine").get("value", 1))
		for c in mine:
			if is_instance_valid(c) and c.has_keyword("armored"):
				c.card_data["hp"] = int(c.card_data.get("hp", 0)) + be
				c.current_hp += be
				c.update_stat_display()


# ── Enter-with-a-bonus passives, per owner side (Wave: passive parity) ──
# Per-side counter accessors: solo reads the player-side globals; net reads the
# _net_*[side] counters so a Player-2 creature reads PLAYER 2's spell / card / Tallow
# counts, not the host's.
func _pt_cards_played(owner_is_enemy: bool) -> int:
	return int(_net_cards_played[1 if owner_is_enemy else 0]) if _is_net() else _cards_played_this_turn
func _pt_spells_fight(owner_is_enemy: bool) -> int:
	return int(_net_spells_fight[1 if owner_is_enemy else 0]) if _is_net() else _spells_cast_this_fight
func _pt_tallow_count(owner_is_enemy: bool) -> int:
	return int(_net_tallow_played[1 if owner_is_enemy else 0]) if _is_net() else _tallow_dolls_played
## Enter-with-a-bonus passives for a freshly-played creature owned by owner_is_enemy's
## side: Old Campaigner (+1/+1 per kills on its run ledger), Hexblade (+ATK per spell
## this fight), Warchief (ATK = 2 + other allies), Tallow Doll (+1/+1 per prior Tallow).
## Solo calls it with owner=false (reads the player globals); _net_spawn_creature calls
## it per side so Player 2's creatures scale off Player 2's own state.
func _apply_play_time_passives(card: Control, owner_is_enemy: bool) -> void:
	if not is_instance_valid(card):
		return
	# Old Campaigner (atk_hp_per_own_kills): enters wearing its service record —
	# +1/+1 per 3 kills THIS card has made across the run (per 2 upgraded). Solo
	# campaign memory only: skirmish decks have no kill ledger (the card is
	# denylisted there), and tokens/copies (uid -1) enter plain.
	if String(card.card_data.get("on_enter", {}).get("type", "")) == "atk_hp_per_own_kills":
		if not _is_net() and int(card.deck_uid) >= 0:
			var oc_per: int = 2 if bool(card.card_data.get("is_upgraded", false)) else 3
			var oc_vet: int = int(RunState.get_kills(int(card.deck_uid)) / oc_per)
			if oc_vet > 0:
				card.current_atk += oc_vet
				card.card_data.hp = int(card.card_data.get("hp", card.current_hp)) + oc_vet
				card.current_hp += oc_vet
				card.update_stat_display()
				spawn_floating_number(card.global_position \
					+ Vector2(card.size.x * card.scale.x * 0.5, -10),
					"+%d/+%d" % [oc_vet, oc_vet], Color(1.0, 0.84, 0.35), false)
	# Condottiere (atk_hp_per_unspent_mana): paid in coin — enters with +1/+1 this
	# fight per unspent Command. Solo/host reads the local pool (this runs after
	# the card's own cost is paid); a client play carries its pool on the intent.
	if String(card.card_data.get("on_enter", {}).get("type", "")) == "atk_hp_per_unspent_mana":
		var cd_unspent: int = player_mana
		if _is_net() and owner_is_enemy:
			cd_unspent = _net_client_unspent_mana
		if cd_unspent > 0:
			card.current_atk += cd_unspent
			card.card_data.hp = int(card.card_data.get("hp", card.current_hp)) + cd_unspent
			card.current_hp += cd_unspent
			card.update_stat_display()
			spawn_floating_number(card.global_position \
				+ Vector2(card.size.x * card.scale.x * 0.5, -10),
				"+%d/+%d" % [cd_unspent, cd_unspent], Color(1.0, 0.84, 0.35), false)
			_net_fx_text(card, "+%d/+%d" % [cd_unspent, cd_unspent], Color(1.0, 0.84, 0.35))
	# Oathkeeper (atk_hp_per_fallen): sworn on the roll of the dead — enters
	# with +1/+1 this fight per fallen friendly. Each side reads its own
	# ledger, so a copied/stolen Oathkeeper counts its controller's losses.
	if String(card.card_data.get("on_enter", {}).get("type", "")) == "atk_hp_per_fallen":
		var ok_fallen: int = _enemy_deaths_this_fight if owner_is_enemy \
			else _friendly_deaths_this_fight
		if ok_fallen > 0:
			card.current_atk += ok_fallen
			card.card_data.hp = int(card.card_data.get("hp", card.current_hp)) + ok_fallen
			card.current_hp += ok_fallen
			card.update_stat_display()
			spawn_floating_number(card.global_position \
				+ Vector2(card.size.x * card.scale.x * 0.5, -10),
				"+%d/+%d" % [ok_fallen, ok_fallen], Color(1.0, 0.84, 0.35), false)
			_net_fx_text(card, "+%d/+%d" % [ok_fallen, ok_fallen], Color(1.0, 0.84, 0.35))
	if card.card_data.get("passive", "") == "atk_per_spell":
		card.current_atk += _pt_spells_fight(owner_is_enemy)
		card.update_stat_display()
	if card.card_data.get("passive", "") == "warchief_aura":
		card.current_atk = 2 + maxi(0, _all_friendly(owner_is_enemy).size() - 1)
		if bool(card.card_data.get("is_upgraded", false)):
			card.current_atk += 1
		card.update_stat_display()
	# Paladin (paladin_rally): wire its Last Stand moment to the rally handler,
	# owner-side bound (Card2D emits last_stand_fired when Last Stand saves it).
	if card.card_data.get("passive", "") == "paladin_rally" and card.has_signal("last_stand_fired"):
		card.last_stand_fired.connect(_on_paladin_last_stand.bind(card, owner_is_enemy))
	# Riteforge (riteforge_ramp): the desc promises an ON-ENTER pulse too — all
	# friendlies (itself included) get the +1 the moment it lands, so a Riteforge
	# played the turn the fight ends never did literally nothing.
	if card.card_data.get("passive", "") == "riteforge_ramp":
		var rf_enter: int = 2 if bool(card.card_data.get("is_upgraded", false)) else 1
		for ally in _all_friendly(owner_is_enemy):
			if is_instance_valid(ally):
				ally.current_atk += rf_enter
				ally.update_stat_display()
		spawn_trigger_callout(card.global_position \
			+ Vector2(card.size.x * card.scale.x * 0.5, -12),
			"FORGE +%d ATK" % rf_enter, false, int(card.entity_id))
	if card.card_data.get("passive", "") == "tallow_stacking":
		var prior: int = _pt_tallow_count(owner_is_enemy)
		if prior > 0:
			card.current_atk += prior
			card.card_data.hp += prior
			card.current_hp += prior
			card.update_stat_display()
		if _is_net():
			_net_tallow_played[1 if owner_is_enemy else 0] += 1
		else:
			_tallow_dolls_played += 1
	# (Standard Bearer's old first-1-cost summon lived here; its 2026-07-05
	# rework is token_lord — summoned tokens enter bigger, hooked in
	# summon_token itself so every token path pays out.)


## Paladin (paladin_rally): its Last Stand moment rallies the whole warband —
## every friendly gains +2 ATK this fight (+3 upgraded) and the owner's hero
## heals 3. Fired by Card2D.last_stand_fired at the survival beat itself.
func _on_paladin_last_stand(card: Control, owner_is_enemy: bool) -> void:
	if not is_instance_valid(card) or card.card_data.get("passive", "") != "paladin_rally":
		return
	var rally: int = 3 if bool(card.card_data.get("is_upgraded", false)) else 2
	for c in _all_friendly(owner_is_enemy):
		if is_instance_valid(c):
			c.current_atk += rally
			c.update_stat_display()
	_heal_owner_hero(owner_is_enemy, 3)
	# Trigger-callout (not a bare float) so the moment reads as an ability firing
	# AND replays on the net client via the fx queue.
	spawn_trigger_callout(card.global_position \
		+ Vector2(card.size.x * card.scale.x * 0.5, -12),
		"RALLY +%d ATK" % rally, false, int(card.entity_id))
	_update_hud()


## Side-aware variant for net per-side passive checks (false = player/host side, the
## same set _has_passive_on_field walks; true = the client's side).
func _has_passive_on_side(passive_name: String, is_enemy: bool) -> bool:
	for c in _all_friendly(is_enemy):
		if c.card_data.get("passive", "") == passive_name:
			return true
	return false


func _get_wall_reduction(lane_idx: int, defender_is_enemy: bool) -> int:
	# 4x4: walls in either row contribute. "Cannot attack wall" reduces only this
	# column and its neighbors; "reduce_face_damage" reduces any face hit. Walls belong
	# to the DEFENDING side — solo only ever defends the player; net also defends the
	# client (so a Player-2 Iron Bastion blunts the host's attacks).
	var reduction := 0
	for c in _all_friendly(defender_is_enemy):
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
	# A death removes a buff source / changes neighbours — re-tally adjacency so the
	# survivors' ATK drops in step (and pops a "-N ATK" so it reads on-screen).
	_refresh_adjacency_buffs()


func _on_friendly_death(card: Control, _lane_idx: int) -> void:
	_friendly_deaths_this_fight += 1
	_friendly_deaths_this_round += 1
	# Campaign memory: a real deck creature falling is written into the Roll of
	# the Fallen — name as worn at death (epithet included), where, and when.
	# Solo campaign only; tokens have no identity to mourn.
	if not _is_net() and not card.is_token and int(card.deck_uid) >= 0:
		RunState.record_fall(int(card.deck_uid), card.card_id,
			String(card.card_data.get("name", card.card_id)),
			_encounter_name if _encounter_name != "" else "the road",
			round_number)
		# A named veteran's fall is a campaign moment, not a stat tick: call the
		# worn name (the epithet is already folded into card_data at draw) over
		# the spot where they fell, in the death-styled honor banner. The forge's
		# " +" suffix is trimmed — "PIKEMAN THE GRIM + HAS FALLEN" reads as a typo.
		if RunState.get_kills(int(card.deck_uid)) >= RunState.VETERAN_EPITHET_KILLS:
			var worn := String(card.card_data.get("name", card.card_id)).trim_suffix(" +")
			var fall_pos := card.global_position \
				+ Vector2(card.size.x * card.scale.x * 0.5, card.size.y * card.scale.y * 0.30)
			spawn_trigger_callout(fall_pos, "%s HAS FALLEN" % worn.to_upper(), true)
	_last_dead_creature_id = card.card_id
	# Track the uid alongside the id so consumers (Grave Robbery, Grave Pact)
	# can push a proper "card_id#uid" pile entry. Tokens / synthetic cards
	# leave -1 here, which _resolve_card_data already handles.
	_last_dead_creature_uid = card.deck_uid
	# Gravedigger's draw_on_ally_death now lives in _apply_ally_death_passives so it
	# fires side-aware + net-aware (host draws for itself, EV_DRAW for the client) —
	# see the block there. The player-side call below covers solo + net-host.
	# Corpse Eater / Husk / Carrion Priest — grow/drain payoffs for the player side.
	# Extracted into _apply_ally_death_passives so the net death hook can run the same
	# for the CLIENT's side (a Player-2 Corpse Eater grows on Player-2 deaths, etc.).
	_apply_ally_death_passives(false, card)
	# Soul Lantern
	if _has_relic("soul_lantern") and not _soul_lantern_used_this_round:
		_soul_lantern_used_this_round = true
		_bonus_mana_next_turn += 1
	# A Verse of You (event relic): the first friendly death each round sings
	# a card up out of the deck. Same once-per-round cadence as Soul Lantern.
	if _has_relic("verse_of_you") and not _verse_of_you_used_this_round:
		_verse_of_you_used_this_round = true
		draw_one()
	# Sigil of Hunger: arm a "next creature -1 mana" charge, once per round.
	if _has_relic("sigil_of_hunger") and not _sigil_of_hunger_fired_this_round:
		_sigil_of_hunger_fired_this_round = true
		_sigil_of_hunger_charge += int(RelicDB.get_relic("sigil_of_hunger").get("value", 1))
	# (Gravewarden's Pact moved to _apply_ally_death_passives so it fires per-side —
	# host-authoritative for the client's copy too in skirmish.)
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


## Grow / drain payoffs that fire when a creature on owner_is_enemy's side dies:
## Corpse Eater (grow_on_ally_death), Husk (grow_on_any_death), Carrion Priest
## (drain_on_ally_death → reach + heal). Solo calls it for the player side only; the
## net death hook also calls it for the client's side. dead_card is the fallen
## creature and is skipped so it never profits from its own death.
func _apply_ally_death_passives(owner_is_enemy: bool, dead_card: Control = null) -> void:
	for c in _all_friendly(owner_is_enemy):
		if c == dead_card:
			continue   # the fallen don't profit from their own death
		match c.card_data.get("passive", ""):
			"grow_on_ally_death":
				var ge_gain: int = 2 if bool(c.card_data.get("is_upgraded", false)) else 1
				c.current_atk += ge_gain
				c.update_stat_display()
				spawn_floating_number(c.global_position \
					+ Vector2(c.size.x * c.scale.x * 0.5, -10),
					"+%d ATK" % ge_gain, Color(1.0, 0.62, 0.20), false)
				_net_fx_text(c, "+%d ATK" % ge_gain, Color(1.0, 0.62, 0.20))
			"grow_on_any_death":
				c.current_atk += 1
				c.update_stat_display()
				spawn_floating_number(c.global_position \
					+ Vector2(c.size.x * c.scale.x * 0.5, -10),
					"+1 ATK", Color(1.0, 0.62, 0.20), false)
				_net_fx_text(c, "+1 ATK", Color(1.0, 0.62, 0.20))
			"drain_on_ally_death":
				_hurt_opposing_hero(owner_is_enemy, 2 if bool(c.card_data.get("is_upgraded", false)) else 1)
				_heal_owner_hero(owner_is_enemy, 1)
				spawn_trigger_callout(c.global_position \
					+ Vector2(c.size.x * c.scale.x * 0.5, -12),
					"DRAIN", true, int(c.entity_id))
	# Gravedigger — "when one of your creatures dies, draw 1 (up to twice per round)."
	# Draws once per death (not per Gravedigger). The draw routes through
	# _battlecry_draw so it lands on the OWNER: solo → local draw_one; net-host →
	# host draws locally / client gets EV_DRAW. The per-side death tally is the
	# "twice per round" cap (this death is already counted in it), and the fallen
	# card is out of the field arrays by now, so it can't draw off its own death.
	var side_round_deaths: int = _enemy_deaths_this_round if owner_is_enemy else _friendly_deaths_this_round
	if side_round_deaths <= 2:
		for c in _all_friendly(owner_is_enemy):
			if c == dead_card:
				continue
			if c.card_data.get("passive", "") == "draw_on_ally_death":
				_battlecry_draw(owner_is_enemy, 1)
				break
	# Gravewarden's Pact (board relic, host-authoritative in net): the first N
	# non-token friendly deaths each fight are reborn as 1/1 Imps where they fell.
	# Per-side cap so each warband's Pact spends its own; the reborn Imp rides the
	# board snapshot to the client. Tokens excluded so rebirths don't chain.
	var gw_side: int = 1 if owner_is_enemy else 0
	if dead_card != null and is_instance_valid(dead_card) and not dead_card.is_token \
			and _relic_active_for_side(owner_is_enemy, "gravewardens_pact"):
		var gw_cap: int = int(RelicDB.get_relic("gravewardens_pact").get("value", 3))
		if _gravewardens_rebirths[gw_side] < gw_cap:
			_gravewardens_rebirths[gw_side] += 1
			var gw_row: int = dead_card.current_row if dead_card.current_row in [ROW_FRONT, ROW_BACK] else ROW_FRONT
			var gw_lane: int = dead_card.current_lane if (dead_card.current_lane >= 0 and dead_card.current_lane < LANES_PER_ROW) else 0
			summon_token(1, 1, gw_lane, owner_is_enemy, gw_row)


## The Apothecary (plague_doctor): apothecaries on the side OPPOSITE the just-dead
## creature ping the dead creature's hero. Solo: a player apothecary profits from enemy
## deaths. Net mirrors it both ways (a Player-2 apothecary profits from host deaths).
func _apply_plague_doctor(dyer_is_enemy: bool) -> void:
	for pd in _all_friendly(not dyer_is_enemy):
		if pd.card_data.get("passive", "") == "plague_doctor":
			var n: int = 2 if bool(pd.card_data.get("is_upgraded", false)) else 1
			if _is_net():
				_net_damage_hero(dyer_is_enemy, n)
			else:
				damage_enemy_hero(n)


func _post_combat_sequence() -> void:
	_post_combat_cleanup()
	_discard_hand()

	# Name the reinforcement beat so a fresh enemy creature appearing reads as
	# "they brought up reserves," not a silent board change.
	if not _enemy_deck.is_empty() or not _reinforcement.is_empty():
		_set_phase_caption("ENEMY REINFORCES")
	await _short_pause(COMBAT_PAUSE_MEDIUM)
	await _enemy_place_creatures()

	# Escalation: once a generic hold has worn on past ESCALATION_REINFORCE_ROUND
	# it commits reserves — a second placement this round, telegraphed so it reads
	# as a turning point and not a silent board change. Faction holds are skipped
	# (their authored wave schedule already supplies the escalation); this is the
	# generic-fight answer to the old, never-reached round-8 tier.
	if _encounter_id != "":
		var enc = EncounterDB.get_encounter(_encounter_id)
		if enc.get("type", "") == "combat" and not _wave_schedule_active \
				and round_number >= _esc_round(ESCALATION_REINFORCE_ROUND):
			if not _escalation_banner_shown:
				_escalation_banner_shown = true
				_show_combat_banner("THE TIDE TURNS",
					"The hold commits its reserves", Color(0.85, 0.3, 0.15))
			await _enemy_place_creatures()

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

	# Round-end relic bundle: flanking_banner, imp_generator, mana_drunkard
	# streak check, steady_banner survival ATK grant.
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


# =====================================================================
#  SUCCESSOR WARS — PER-FACTION REINFORCEMENT WAVE SCHEDULES (§15.2)
# =====================================================================
# Replaces the uniform 1/round drip in NORMAL holds whose encounter carries a
# faction tag — the last structural "fights feel samey" lever. Keyed by the
# encounter's faction tag. A wave lands at the END of a round and fights from
# the next round on; normal holds end by round 2-3, so every schedule shows
# its face by round 2 (R1-end musters: grasswake 2 / last_wall 1 / owed 0 /
# lanternhall 1 / everflame 0). Elites, bosses, and untagged encounters keep
# the live drip exactly, and every schedule yields to the legacy anti-stall
# escalation at ESCALATION_REINFORCE_ROUND.
#
#   waves        — per-round wave sizes; index 0 = the wave at the end of
#                  round 1.
#   after        — wave size once `waves` runs out (default 1).
#   cycle        — true: loop `waves` forever instead of falling to `after`.
#   collect      — true: wave size = enemy deaths banked since the last wave
#                  (capped at `cap`); ignores `waves`/`after`. Uncollected
#                  deaths stay banked.
#   cap          — max bodies per collected wave (collect mode only).
#   tough_hp     — rider: every wave body arrives with +N HP.
#   surge_bonus  — one-time +N wave the first time the hold is half-broken
#                  (face HP at or below half).
const FACTION_WAVE_SCHEDULES: Dictionary = {
	# The Grasswake (Overrun) — floods early, then the wake passes and they
	# run dry: 2, 2, then nothing. Empty lanes are their highway; outlast the
	# crest and you push into open grass.
	"grasswake": {"waves": [2, 2], "after": 0},
	# The Last Wall (Formation) — trickles forever, every body tough: exactly
	# 1 per round, no flood rolls ever, and each relief arrives +1 HP.
	"last_wall": {"waves": [], "after": 1, "tough_hp": 1},
	# The Owed (the Tithe) — they re-raise from their own dead: each enemy
	# death banks a deposit; every round they collect up to 2. Kill nothing
	# and nothing comes back.
	"owed": {"collect": true, "cap": 2},
	# The Lanternhall (Foresight) — barely reinforces (casts instead): one
	# body every other round, nothing between.
	"lanternhall": {"waves": [1, 0], "cycle": true},
	# The Everflame (the Fuse) — nothing pays now, everything pays later,
	# bigger: 0, 1, then 2 a round — plus a one-time surge the first time
	# the hold is half-broken.
	"everflame": {"waves": [0, 1], "after": 2, "surge_bonus": 1},
}

# Wave-chip captions per faction (caps to match the HUD chip voice — the
# INCOMING caption, the intent pills). "wave" = bodies muster, "none" = the
# schedule rests this round, "surge" = the Everflame's fuse moment.
const FACTION_WAVE_CAPTIONS: Dictionary = {
	"grasswake": {"wave": "THE WAKE CRESTS", "none": "THE WAKE HAS PASSED"},
	"last_wall": {"wave": "FRESH RANKS — TOUGHER", "none": "THE WALL HOLDS"},
	"owed": {"wave": "THE OWED COLLECT", "none": "NO DEBTS TO COLLECT"},
	"lanternhall": {"wave": "A MIRROR FLASHES", "none": "THE HALL ONLY WATCHES"},
	"everflame": {"wave": "THE FUSE BURNS DOWN", "none": "THE EVERFLAME HOLDS",
		"surge": "FIRE ON THE WATER"},
}


func _wave_schedule() -> Dictionary:
	return FACTION_WAVE_SCHEDULES.get(_encounter_faction, {})


func _wave_surge_pending() -> bool:
	# The Everflame's one-time surge: pending while the hold is half-broken
	# and the surge hasn't been spent. Read by both the telegraph and the
	# placement, so the warning can never disagree with what actually lands.
	var bonus: int = int(_wave_schedule().get("surge_bonus", 0))
	return bonus > 0 and not _wave_surge_fired and enemy_hp * 2 <= enemy_max_hp


func _next_wave_count() -> int:
	# Bodies the faction schedule will place at the END of the current round
	# (they fight from next round on). -1 = no schedule applies → callers use
	# the legacy uniform drip. The round-start telegraph and the end-of-round
	# placement both call this with the same round_number, so the chip always
	# matches the muster.
	if not _wave_schedule_active or round_number >= WAVE_SCHEDULE_CUTOFF_ROUND:
		return -1
	var sched: Dictionary = _wave_schedule()
	if sched.is_empty():
		return -1
	var n: int = 0
	if bool(sched.get("collect", false)):
		n = clampi(_wave_deaths_banked, 0, int(sched.get("cap", 2)))
	else:
		var waves: Array = sched.get("waves", [])
		var idx: int = round_number - 1
		if idx >= 0 and idx < waves.size():
			n = int(waves[idx])
		elif bool(sched.get("cycle", false)) and waves.size() > 0:
			n = int(waves[idx % waves.size()])
		else:
			n = int(sched.get("after", 1))
	if _wave_surge_pending():
		n += int(sched.get("surge_bonus", 0))
	return n


func _update_wave_telegraph() -> void:
	# Successor Wars legibility hook: the "next wave" chip pinned under the
	# incoming-damage chip telegraphs what the faction schedule will muster at
	# the end of this round — same diegetic-threat language as the INCOMING
	# chip, same color vocabulary as the intent pills (gray RETREAT = nothing
	# comes, purple SUMMON = a body musters, hot amber/red = a flood). Hidden
	# for legacy/elite/boss fights and once the round-8 escalation takes over.
	# Also re-run when the Owed bank a death, so the chip doubles as the
	# visible Tithe corpse-counter.
	if _hud_layer == null:
		return
	var n: int = _next_wave_count()
	if n < 0:
		if _wave_chip != null:
			_wave_chip.visible = false
		return
	if _wave_chip == null:
		_build_wave_chip()
	_wave_chip.visible = true
	_wave_chip_num.text = str(n)
	var caps: Dictionary = FACTION_WAVE_CAPTIONS.get(_encounter_faction, {})
	var caption: String
	if n > 0 and _wave_surge_pending() and caps.has("surge"):
		caption = String(caps.get("surge"))
	elif n > 0:
		caption = String(caps.get("wave", "A WAVE MUSTERS"))
	else:
		caption = String(caps.get("none", "THE LINES HOLD"))
	_wave_chip_caption.text = caption
	# Fit long faction captions ("THE HALL ONLY WATCHES") inside the plaque —
	# at the standard 18pt several of them overflow the 236px chip width.
	var cap_font: Font = _wave_chip_caption.get_theme_font("font")
	var cap_size := 18
	while cap_size > 12 and cap_font != null and \
			cap_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1,
				cap_size).x > 204.0:
		cap_size -= 1
	_wave_chip_caption.add_theme_font_size_override("font_size", cap_size)
	# One warm threat ramp shared with the INCOMING chip (quiet bone → ember →
	# crimson): the muster reads on the same scale as the face damage instead of
	# adding a third (purple) color voice to the rail. The caption keeps the
	# rail's fixed gilt small-cap voice; only numeral/icon/border heat up.
	var col := Color(0.72, 0.66, 0.54)
	if n == 1:
		col = Color(1.0, 0.62, 0.30)
	elif n == 2:
		col = Color(1.0, 0.47, 0.26)
	elif n >= 3:
		col = Color(1.0, 0.34, 0.28)
	_wave_chip_num.add_theme_color_override("font_color", col)
	if _wave_chip_icon != null:
		_wave_chip_icon.modulate = col
	var st: GameTheme.ChartPanelStyle = _wave_chip.get_theme_stylebox("panel")
	if st != null:
		st.border_color = Color(col.r, col.g, col.b, 0.72) if n > 0 \
			else Color(0.42, 0.33, 0.20, 0.85)


func _build_wave_chip() -> void:
	# Built lazily on the first scheduled round — legacy fights never pay for
	# it. Mirrors _build_incoming_damage_chip: a framed chip pinned in the
	# enemy corner with a caption + icon + numeral that reads in one glance.
	var chip := PanelContainer.new()
	chip.name = "NextWaveChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Same warm ink-plaque family as the incoming chip, now on the chart
	# document kit; the border color is overwritten per wave count, so only
	# the base material changes here.
	var style := GameTheme.make_panel_style(
		Color(0.10, 0.062, 0.046, 0.94), Color(0.42, 0.33, 0.20, 0.85), 1, 4, true)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", style)
	# Pinned directly below the incoming-damage chip (y 324-398) in the enemy
	# corner — the muster belongs next to its source. Full banner width so
	# the faction captions fit on one line.
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.anchor_top = 0.0
	chip.anchor_bottom = 0.0
	chip.offset_left = -250
	chip.offset_right = -14
	chip.offset_top = 406
	chip.offset_bottom = 478
	chip.z_index = 5
	chip.visible = false

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(col)

	var caption := _make_rail_caption("NEXT WAVE")
	caption.name = "WaveCaption"
	col.add_child(caption)
	_wave_chip_caption = caption

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	var icon := TextureRect.new()
	icon.name = "WaveIcon"
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(0.72, 0.66, 0.54)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = GameTheme.tex_node_recruit
	row.add_child(icon)
	_wave_chip_icon = icon

	var num := Label.new()
	num.name = "WaveNum"
	num.text = ""
	num.add_theme_font_size_override("font_size", 34)
	num.add_theme_color_override("font_color", Color(0.72, 0.66, 0.54))
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	num.add_theme_constant_override("outline_size", 5)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_title_black:
		num.add_theme_font_override("font", GameTheme.font_title_black)
	row.add_child(num)
	_wave_chip_num = num

	# Quiet fixed suffix — context, not payload. Dim bone so the numeral owns
	# the row (it used to shout at 19pt lilac beside a purple numeral).
	var suffix := Label.new()
	suffix.name = "WaveSuffix"
	suffix.text = "NEXT ROUND"
	suffix.add_theme_font_size_override("font_size", 16)
	suffix.add_theme_color_override("font_color", Color(0.70, 0.63, 0.50))
	suffix.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	suffix.add_theme_constant_override("outline_size", 3)
	suffix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	suffix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		suffix.add_theme_font_override("font", GameTheme.font_display)
	row.add_child(suffix)

	_hud_layer.add_child(chip)
	_wave_chip = chip


## Pursuit ("the road answers the march", 2026-06-12): once the lord's gate
## threshold falls, the rival's response rides out to every hold still
## standing. Tier 0 below 2 broken holds; tier 1 at 2 (one outrider body on
## round 2); tier 2 at 3+ (again on round 4). Normal holds only — lords and
## their stronghold elites keep their authored kit pacing (§15.2). This is
## the act's tempo decision: rush the open gate, or farm the remaining
## holds knowing they harden.
func _pursuit_tier() -> int:
	if RunState.current_node_type != "combat":
		return 0
	if RunState.holds_broken_in_act >= 3:
		return 2
	if RunState.holds_broken_in_act >= 2:
		return 1
	return 0

var _pursuit_banner_shown: bool = false
var _escalation_banner_shown: bool = false


func _enemy_place_creatures() -> void:
	var enc = EncounterDB.get_encounter(_encounter_id) if _encounter_id != "" else {}
	var enc_type = enc.get("type", "combat")
	var max_place := 1
	# Successor Wars: a faction wave schedule overrides the uniform drip in
	# normal holds (rounds 1-7). _next_wave_count() returns -1 when no
	# schedule applies — untagged/elite/boss fights and the round-8+
	# anti-stall escalation keep the exact legacy behavior below.
	var wave_n: int = _next_wave_count()
	if wave_n >= 0:
		max_place = wave_n
		if _wave_surge_pending():
			# Spend the Everflame's one-time surge and give the spike the
			# climax-banner treatment (rides _show_combat_banner like
			# Ignition / Lich Rises) so it never reads as random.
			_wave_surge_fired = true
			_show_combat_banner("THE FUSE CATCHES",
				"The hold is half-broken — the Everflame surges", Color(1.0, 0.45, 0.20))
	elif round_number <= 2:
		max_place = 1
	elif enc_type == "elite" or enc_type == "boss":
		max_place = 2
	else:
		max_place = 1 if randi() % ENEMY_FLOOP_CHANCE_DENOM != 0 else 2
	# Pursuit — one extra body on the outrider rounds. Stacks on faction
	# waves by design: the wave is the kingdom's engine, the outriders are
	# the rival's answer. The banner fires on the first outrider beat so
	# the spike never reads as random (same rule as the Everflame surge).
	var pt: int = _pursuit_tier()
	if pt >= 1 and (round_number == 2 or (round_number == 4 and pt >= 2)):
		max_place += 1
		if not _pursuit_banner_shown:
			_pursuit_banner_shown = true
			_show_combat_banner("OUTRIDERS",
				"The rival reinforces the hold — the road has eyes",
				Color(0.85, 0.25, 0.18))

	var tough_hp: int = int(_wave_schedule().get("tough_hp", 0)) if wave_n >= 0 else 0
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
				var rf: Dictionary = _reinforcement.duplicate(true)
				rf["is_reinforcement"] = true   # Poisoned Rations reads this tag
				_enemy_deck.append(rf)
			else:
				var eid = CardDB.random_enemy_for_act(RunState.get_act())
				_enemy_deck.append(CardDB.get_card_data(eid))
		var card_data = _enemy_deck.pop_front()
		# The Last Wall's rider: every scheduled body arrives a touch tougher.
		if tough_hp > 0:
			card_data = card_data.duplicate(true)
			card_data["hp"] = int(card_data.get("hp", 1)) + tough_hp
		_place_enemy_card(card_data, slot.lane, slot.row, true)
		placed += 1
		if AudioBank != null:
			AudioBank.play_sfx("card_play", 0.05, -3.0, 0.96)
		# Deal a multi-body wave one card at a time (windowed only) so each
		# landing is seen and heard, instead of a simultaneous teleport.
		if placed < max_place and DisplayServer.get_name() != "headless":
			await _short_pause(0.16)
	# The Owed collect their banked dead — only as many as actually mustered;
	# anything uncollected (board full) stays banked for the next round.
	if wave_n >= 0 and bool(_wave_schedule().get("collect", false)):
		_wave_deaths_banked = maxi(0, _wave_deaths_banked - placed)


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


# One-shot per combat: the first creature a boss/General fields lands as a
# physical beat, so the entrance is felt on the board, not just read on the
# intro banner.
var _entrance_slam_done: bool = false
# Poisoned Rations relic: only the FIRST tagged reinforcement dies on arrival.
var _poisoned_rations_fired: bool = false

func _place_enemy_card(data: Dictionary, lane_idx: int, row: int = ROW_FRONT,
		arc_in: bool = false) -> void:
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
	# Dealt creatures (opening board, reinforcement waves) arc in from above
	# the enemy line so placement reads as an act, not a teleport. Cosmetic
	# only — the card is already seated in the arrays, so combat logic never
	# waits on the flight. Encounter-effect spawns (lich, wraiths, bombs)
	# keep the plain drop-in.
	if arc_in and DisplayServer.get_name() != "headless" \
			and not (UserSettings != null and UserSettings.reduce_motion):
		var slot_center: Vector2 = slot.global_position + slot.size * 0.5
		_play_landing_pop(card,
			Vector2(slot_center.x + randf_range(-60.0, 60.0), -170.0), true)
	else:
		_play_landing_pop(card)
	if not _entrance_slam_done and not _is_net() and _fight_class() in ["elite", "boss"]:
		_entrance_slam_done = true
		screen_shake(14.0 if _fight_class() == "boss" else 10.0)
		if AudioBank != null:
			# The regular card-play sound, pitched deep = the lord's opener
			# hitting the table harder than a common soldier.
			AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	card.will_die.connect(_on_card_will_die.bind(card))
	_log_event("The foe fields %s." % _log_card_ref(card),
		_log_data(card), _log_side(card))
	if _has_relic("philosophers_stone"):
		card.current_atk += 1
	# A4 "Veteran garrisons" — Generals' and lords' creatures enter with +1 ATK.
	# Solo only: net opponents are real players, not garrisons.
	if not _is_net() and RunState.asc_active(4) and _fight_class() in ["elite", "boss"]:
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
	# Enemy/opponent adjacency works too — a foe's Battle Drummer buffs its own
	# line. Re-tally so the buffed numerals show and the strike math is correct.
	_refresh_adjacency_buffs()
	# Poisoned Rations: the FIRST tagged reinforcement each fight arrives
	# dead — placed, seen, then dropped through the canonical destroy path so
	# its On-Death still fires (that clause is the relic's double edge).
	if bool(data.get("is_reinforcement", false)) and not _poisoned_rations_fired \
			and _has_relic("poisoned_rations") and not _is_net():
		_poisoned_rations_fired = true
		spawn_floating_number(_card_center(card) + Vector2(0, -16),
			"POISONED RATIONS", Color(0.55, 0.85, 0.40), false)
		card.take_damage(999)


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
		"glow": Color(1, 0.85, 0.55), "stage": Color(1, 0.82, 0.5), "emberN": 34, "ember": Color(1, 0.82, 0.45),
		"sat": 1.05, "con": 1.12, "bright": 1.04, "sh": Vector3(0.72, 0.8, 1.0), "li": Vector3(1.1, 1.0, 0.78), "tint": Vector3(0.98, 0.99, 1.03)},
	# Softened 2026-06-22: still firelit, but no longer a saturated red FLOOD —
	# sat 1.10→1.0 and the red tint push removed (1.03,0.95,0.9 → near-neutral),
	# highlights/shadows de-reddened, glow pulled from blood-orange toward gold,
	# ember count nearly halved. Reads "lamplit hall over embers", not "red screen".
	"infernal": {"bg": Color(0.26, 0.18, 0.16), "vig": 0.80, "vig_out": Color(0.05, 0.02, 0.01, 0.95),
		"glow": Color(1, 0.62, 0.34), "stage": Color(1, 0.58, 0.32), "emberN": 50, "ember": Color(1, 0.6, 0.3),
		"sat": 1.0, "con": 1.16, "bright": 1.0, "sh": Vector3(0.95, 0.85, 0.78), "li": Vector3(1.06, 0.86, 0.7), "tint": Vector3(1.0, 0.98, 0.97)},
	"noir": {"bg": Color(0.22, 0.20, 0.20), "vig": 0.90, "vig_out": Color(0, 0, 0, 0.98),
		"glow": Color(1, 0.7, 0.45), "stage": Color(1, 0.6, 0.35), "emberN": 26, "ember": Color(1, 0.6, 0.3),
		"sat": 0.70, "con": 1.35, "bright": 0.95, "sh": Vector3(0.8, 0.78, 0.82), "li": Vector3(1.1, 1.0, 0.9), "tint": Vector3(1, 1, 1)},
	"frost": {"bg": Color(0.42, 0.46, 0.52), "vig": 0.55, "vig_out": Color(0.04, 0.06, 0.09, 0.80),
		"glow": Color(0.7, 0.85, 1.0), "stage": Color(0.8, 0.92, 1.0), "emberN": 40, "ember": Color(0.8, 0.92, 1.0),
		"sat": 0.95, "con": 1.05, "bright": 1.12, "sh": Vector3(0.85, 0.93, 1.05), "li": Vector3(0.98, 1.02, 1.1), "tint": Vector3(0.97, 1.0, 1.04)},
	"verdant": {"bg": Color(0.32, 0.38, 0.28), "vig": 0.60, "vig_out": Color(0.02, 0.04, 0.02, 0.85),
		"glow": Color(0.9, 1.0, 0.6), "stage": Color(0.85, 1.0, 0.6), "emberN": 44, "ember": Color(0.85, 1.0, 0.55),
		"sat": 1.08, "con": 1.05, "bright": 1.08, "sh": Vector3(0.85, 0.95, 0.8), "li": Vector3(1.0, 1.08, 0.85), "tint": Vector3(0.98, 1.04, 0.92)},
}

# Successor Wars: normal holds wear their kingdom's mood (§15.2 — per-faction
# combat presets; the mood system was per-act before). Maps faction tag →
# COMBAT_MOODS key. Boss/elite overrides in _resolve_combat_mood still win,
# and untagged fights keep the act/biome pick.
const FACTION_COMBAT_MOODS := {
	"grasswake": "verdant",    # storm over green country
	"last_wall": "navy_gold",  # stone, standards, lamplight
	"owed": "noir",            # the rot drains the color out
	"lanternhall": "frost",    # frost & star
	"everflame": "infernal",   # fire country
}


func _build_grade_overlay() -> void:
	# Reduce Motion doubles as a performance mode: the cinematic grade is a
	# full-screen `hint_screen_texture` pass, which forces a whole-frame
	# framebuffer COPY + shader every frame (above the HUD) — the single most
	# expensive per-frame GPU cost in combat. Skipping it (alongside the embers +
	# idle bob, which already honor Reduce Motion) turns combat into a light,
	# near-static scene for low-end / editor-embedded play. The look goes a touch
	# flatter (no split-tone/contrast grade); the default path is unchanged.
	# _grade_mat stays null → _apply_combat_mood's `if _grade_mat != null` no-ops.
	if UserSettings != null and UserSettings.reduce_motion:
		return
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
	# Successor Wars: a tagged hold wears its kingdom's colors so the five
	# factions read as different enemies before a card is played.
	if FACTION_COMBAT_MOODS.has(_encounter_faction):
		return FACTION_COMBAT_MOODS[_encounter_faction]
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
	#
	# Gated on the player's settings: this is a continuously-emitting particle
	# field, so it forces a full-scene redraw EVERY frame (the scene never idles)
	# and adds CPU sim + overdraw on top. "Particles: Off" should mean off — it
	# used to leak through here (only the combat burst FX honored the flag), so
	# players who lowered settings to fight lag still paid for the ambient field.
	# Reduce Motion suppresses it too (a calm, static backdrop). Skipping creation
	# is safe: _apply_combat_mood null-checks the "AmbientEmbers" node.
	if (UserSettings != null and not UserSettings.particles) \
			or (UserSettings != null and UserSettings.reduce_motion):
		return
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
	# Witch (first_spell_discount): your first spell each turn costs 1 less while
	# she stands on your field. Persistent engine — no charge to consume; once the
	# first spell resolves, _first_spell_this_turn flips and the discount rests.
	if card.is_spell() and not _first_spell_this_turn and cost > 0 \
			and _has_passive_on_field("first_spell_discount"):
		cost = maxi(0, cost - 1)
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
	# Skirmish: you may only play on your own turn (full-alternating model).
	if _is_net() and _net_active_index != NetMatch.local_player_index:
		_show_info("Not your turn.")
		_layout_hand()
		return
	if _targeting_spell != null:
		_cancel_targeting()

	# Curses: "Can't be played" is enforced HERE, not just written on the card.
	# (Before this gate a dragged Curse resolved as a free no-op spell and
	# cycled to discard — the card text was a lie.) Playable-at-a-price curses
	# (Cowardice) carry curse_playable and fall through to the normal cost check.
	if CardDB.is_curse(String(card.card_data.get("id", ""))) \
			and not bool(card.card_data.get("curse_playable", false)):
		_show_info("%s can't be played — it clogs the hand until the fight ends." \
			% String(card.card_data.get("name", "The Curse")))
		_layout_hand()  # bounce the dragged card back into the fan
		return

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
		_show_info("Not enough Command!")
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

	# Witch (first_spell_discount): flash her cut when it actually paid out, so the
	# cheaper cast is attributable. _effective_cost is side-effect-free, so probing
	# "what would this cost without the first-spell discount" via the flag is safe.
	# (Skipped under Ember Crown — the relic already made the first spell free.)
	if card.is_spell() and not _first_spell_this_turn \
			and _has_passive_on_field("first_spell_discount") and not _has_relic("ember_crown"):
		_first_spell_this_turn = true
		var witch_undiscounted: int = _effective_cost(card)
		_first_spell_this_turn = false
		if witch_undiscounted > cost:
			for _wi in _all_player_creatures():
				if _wi.card_data.get("passive", "") == "first_spell_discount":
					spawn_floating_number(_wi.global_position \
						+ Vector2(_wi.size.x * _wi.scale.x * 0.5, -10),
						"-1 COMMAND", Color(0.55, 0.78, 1.0), false)
					break

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

	# ── SEALED ORDERS: a play during the orders phase is a PRIVATE commitment —
	# nothing seats for real and nothing crosses the wire but a face-down ghost
	# at the lane. Both bundles seat together at the reveal. ──
	if _is_sealed():
		if not _sealed_in_orders():
			_show_info("Orders are sealed — creatures wait for the next muster.")
			_layout_hand()
			return
		_sealed_commit_creature(card, cost, lane_idx, row)
		return

	# ── Skirmish CLIENT: don't seat locally. Spend Command, drop the hand card,
	# and send a play intent — the creature reappears on this screen via the next
	# board snapshot from the host (which runs its on-enter authoritatively). ──
	if _is_client():
		if _net_active_index != NetMatch.local_player_index:
			_show_info("Not your turn.")
			_layout_hand()
			return
		var c_uid: int = card.deck_uid
		var c_id: String = card.card_id
		# Capture the fly-in origin + face BEFORE freeing the hand card — the cosmetic
		# arc below needs them, and global_position is meaningless once it's removed.
		var fly_origin: Vector2 = card.global_position + card.size * 0.5
		var fly_data: Dictionary = card.card_data.duplicate(true)
		player_mana -= cost
		_pulse_mana_label(cost)
		_hand.erase(card)
		_hand_container.remove_child(card)
		card.queue_free()
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
		# Send the intent FIRST (no animation latency on the authoritative play), then
		# bridge the visual gap with a fire-and-forget fly-in to the destination slot.
		NetMatch.send_intent({
			"t": NetMatch.IN_PLAY_CREATURE, "uid": c_uid, "id": c_id,
			"lane": lane_idx, "row": row,
			# Unspent Command AFTER paying this card — the host reads it for
			# play-time passives that scale off the caster's pool (Condottiere).
			"mana": player_mana,
		})
		_net_broadcast_hand_count()
		_layout_hand()
		_update_hud()
		_client_animate_own_play(fly_data, lane_idx, row, fly_origin)
		return

	# PlayLog: record the play with pre-mutation state (state→action pair).
	_pl_log("play_creature", {"card": card.card_id, "uid": card.deck_uid,
		"cost": cost, "lane": lane_idx, "row": row})
	_log_event("You field %s." % _log_card_ref(card),
		_log_data(card), _log_side(card))

	# Capture hand position BEFORE remove_child so the landing arc knows where
	# this card flew in from. Once removed, global_position no longer reflects
	# the on-screen hand slot.
	var play_start_global: Vector2 = card.global_position
	player_mana -= cost
	_pulse_mana_label(cost)
	_cards_played_this_turn += 1
	if _is_net():
		_net_cards_played[0] += 1   # host's per-side card tally (Ironclad Veteran)
	# Flag BEFORE remove_child: pulling a hovered card out of the hand can
	# fire its mouse_exited, and the exit handler's return-to-hand-pose
	# branch must already see "this is a battlefield card" or it writes
	# hand-fan coordinates onto a card being seated into a slot.
	card.is_on_battlefield = true
	card.current_lane = lane_idx
	card.current_row = row
	_hand.erase(card)
	_hand_container.remove_child(card)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Hand → battlefield: shrink to the compact variant so the 4x4 grid fits.
	card.set_compact_mode(true)

	if _has_relic("iron_buckler") and not _iron_buckler_used_this_fight:
		_iron_buckler_used_this_fight = true
		if "last_stand" not in card.card_data.keywords:
			card.card_data.keywords.append("last_stand")
			if card.has_method("_spawn_keyword_chip"):
				card._spawn_keyword_chip("LAST STAND", Color(1.0, 0.85, 0.45))
	# Vanguard's Cry — the fight's first creature bellows across the line:
	# 2 damage to whatever stands in its column. Positional: WHERE you open
	# matters now (was an invisible "+1 to On-Enter damage").
	if _has_relic("vanguards_cry") and not _vanguard_cry_used_this_fight \
			and card.is_creature() and not _is_net():
		_vanguard_cry_used_this_fight = true
		var cry_target = _get_creature_in_column(true, lane_idx)
		if cry_target != null and is_instance_valid(cry_target):
			_show_info("Vanguard's Cry — the first banner strikes fear: 2 damage across the line!")
			cry_target.take_damage(int(RelicDB.get_relic("vanguards_cry").get("value", 2)))
	# Banner of Unity — closing a rank is a moment: a creature played BETWEEN
	# two friendlies rallies all three (+1 ATK this fight). Was an invisible
	# "+1 to Adj. Buff effects".
	if _has_relic("banner_of_unity") and card.is_creature() and not _is_net():
		var band_row = _row_array(false, row)
		var band_left = band_row[lane_idx - 1] if lane_idx > 0 else null
		var band_right = band_row[lane_idx + 1] if lane_idx < LANES_PER_ROW - 1 else null
		if band_left != null and is_instance_valid(band_left) \
				and band_right != null and is_instance_valid(band_right):
			for band_c in [band_left, card, band_right]:
				band_c.current_atk += 1
				band_c.update_stat_display()
			_show_info("Banner of Unity — the rank closes: +1 ATK to all three!")
	if _has_relic("veterans_medal") and card.card_data.cost == 1 and card.is_creature():
		card.current_atk += 1
		card.current_hp += 1
		card.card_data.hp += 1
	if _has_relic("glass_cannon") and card.is_creature():
		card.current_hp = maxi(1, card.current_hp - 1)
		card.card_data.hp = maxi(1, card.card_data.hp - 1)
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

	# On-enter effects + the Summon keyword (single dispatch point; the
	# ON_PLAYER_SUMMON reactive fires from inside it as well).
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

	# Enter-with-a-bonus passives (Ironclad / Hexblade / Warchief / Tallow Doll) plus
	# Standard Bearer's first-1-cost summon. Extracted so the net spawn path runs the
	# SAME for the CLIENT's creatures, reading the client's per-side counters.
	_apply_play_time_passives(card, false)

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

	# Wormwood / Stalwart's Anvil react inside _on_friendly_damaged.
	# Pen Nib counts every card played (creature OR spell).
	if _has_relic("pen_nib"):
		_pen_nib_counter += 1
		var threshold: int = int(RelicDB.get_relic("pen_nib").get("value", 10))
		if threshold > 0 and _pen_nib_counter >= threshold:
			_pen_nib_counter = 0
			_pen_nib_trigger()

	card.update_stat_display()
	_update_hud()

	# ── Skirmish HOST: the host played its own creature (real local Card2D, real
	# on-enter above). Stamp its network id (= deck uid) and push the new board to
	# the client so the opponent sees it. ──
	if _is_host():
		card.entity_id = card.deck_uid
		NetMatch.register_entity(card.entity_id, card)
		_net_broadcast_hand_count()
		_net_sync_board()


func _play_spell(card: Control, cost: int) -> void:
	# Skirmish routes spells through the host-authoritative net resolver.
	if _is_net():
		_net_play_spell(card, cost)
		return
	# PlayLog: stash pre-cast snapshot; emitted at _after_spell with the target.
	_pl_spell_pending = {"card": card.card_id, "uid": card.deck_uid, "cost": cost,
		"targeting": card.card_data.get("targeting", "none"), "snap": _pl_snapshot()}
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
		# Persistent, named prompt — set DIRECTLY (not via _show_info, whose 2s
		# timer would wipe it while targeting is still armed). Names the spell, the
		# legal target, and the cancel gesture. Cleared on resolve/cancel.
		_info_token += 1   # invalidate any pending _show_info clear-timer
		_info_label.text = "%s — choose %s    ·    right-click to cancel" % [
			String(card.card_data.get("name", "Spell")), _targeting_human(targeting)]
		_info_label.modulate = Color(1, 1, 1, 1)
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

	# Battle log — the cast is the beat to remember (a doubled Echo/Doubled
	# Hour cast logs twice, which is the truth). Solo only: in net the resolver
	# runs host-side for both players, so "You cast" could name the wrong hand.
	if not _is_net():
		var cast_line := "You cast [color=%s]%s[/color]" \
			% [_LOG_PLAYER_COL, String(data.get("name", "a spell"))]
		if target != null and is_instance_valid(target):
			cast_line += " on %s" % _log_card_ref(target)
		_log_event(cast_line + ".", data, 0)

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
			damage_enemy_hero(value)
		"damage_all_enemies":
			for c in _all_enemy_creatures():
				c.take_damage(value)
		"damage_all":
			for c in _all_creatures_both_sides():
				c.take_damage(value)
			_cleanup_dead()
		"buff_atk":
			if target != null:
				_sound_war_horn()
				if spell.get("permanent", false):
					target.current_atk += value
				else:
					target.temp_atk_buff += value
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
			_sound_war_horn()
			for c in _all_player_creatures():
				if spell.get("permanent", false):
					c.current_atk += value
				else:
					c.temp_atk_buff += value
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
	var is_plus: bool = bool(data.get("is_upgraded", false))
	match spell_id:
		"blood_tithe":
			damage_enemy_hero(4 + spell_dmg_bonus + plus_dmg)
			damage_player_hero(2)
		"petard":
			# The Petard: a real placed bomb now. It can still hit either side,
			# but the player chooses the body and owns the splash risk.
			if target != null:
				var pd_pos: Dictionary = _find_creature_position(target)
				var pd_main: int = 5 + spell_dmg_bonus + plus_dmg
				var pd_splash: int = 2 + spell_dmg_bonus + plus_dmg
				target.take_damage(pd_main)
				if not pd_pos.is_empty():
					var pd_row = _row_array(bool(pd_pos.is_enemy), int(pd_pos.row))
					for pd_lane in [int(pd_pos.lane) - 1, int(pd_pos.lane) + 1]:
						if pd_lane >= 0 and pd_lane < LANES_PER_ROW:
							var pd_adj = pd_row[pd_lane]
							if pd_adj != null and is_instance_valid(pd_adj) and pd_adj.current_hp > 0:
								pd_adj.take_damage(pd_splash)
		"slow_match":
			# Slow Match: base 2 + the fuse banked while it waited in hand
			# (_start_round caps the charge at +4). The hover prediction reads
			# the same card_data key, so the shown number is the landed number.
			if target != null:
				target.take_damage(2 + int(data.get("fuse", 0)) + spell_dmg_bonus + plus_dmg)
		"muster_fallen":
			# Muster the Fallen: the run's Roll of the Fallen marches once
			# more — a Shade per name (max 4, floor 1), front lanes first.
			var mf_size: int = 2 if is_plus else 1
			var mf_left: int = clampi(RunState.fallen.size(), 1, 4)
			for mf_row in [ROW_FRONT, ROW_BACK]:
				for mf_lane in range(LANES_PER_ROW):
					if mf_left > 0 and _row_array(false, mf_row)[mf_lane] == null:
						summon_token(mf_size, mf_size, mf_lane, false, mf_row, {}, "Shade")
						mf_left -= 1
		"penance":
			# Burn a Curse from hand for a bigger blast. Auto-eats the first
			# Curse found — no picker; most hands carry at most one.
			var pen_burned := false
			for hc in _hand:
				if is_instance_valid(hc) and CardDB.is_curse(hc.card_id):
					_hand.erase(hc)
					if hc.get_parent() != null:
						hc.get_parent().remove_child(hc)
					_exhaust_pile.append(hc.card_id)
					hc.queue_free()
					pen_burned = true
					break
			var pen_dmg: int = (6 if pen_burned else 2) + spell_dmg_bonus + plus_dmg
			if target != null:
				target.take_damage(pen_dmg)
			else:
				damage_enemy_hero(pen_dmg)
		"mark_of_ash":
			# Removal on a fuse: the target gains Doom (2, or 1 upgraded) with a
			# SPENT blast — doom_damage 0 — so the detonation only takes the
			# creature, never the player's face (enemy dooms blast the opposing
			# face by default, see _detonate_doom).
			if target != null:
				if target.has_keyword("doom"):
					_detonate_doom(target)
				else:
					if not target.card_data.get("keywords", []).has("doom"):
						target.card_data["keywords"].append("doom")
					target.card_data["doom_damage"] = 0
					target.doom_counter = 1 if is_plus else 2
					target.card_data["doom"] = target.doom_counter
					if target.has_method("ensure_doom_badge"):
						target.ensure_doom_badge()
					if target.has_method("update_doom_display"):
						target.update_doom_display()
					if target.has_method("flash_doom_tick"):
						target.flash_doom_tick()
		"shove":
			if target != null:
				var shoved: bool = false
				if target.current_row == ROW_FRONT:
					shoved = _relocate_creature(target, true, ROW_BACK, target.current_lane)
				if not shoved and is_instance_valid(target):
					target.state.stunned = true
					if target.has_method("_spawn_keyword_chip"):
						target._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
					if plus_dmg > 0:
						target.take_damage(plus_dmg + spell_dmg_bonus)
		"provision":
			# Summon one 2/1 Soldier in an empty lane — a body that actually
			# threatens a trade and feeds sacrifice/Overrun (the "+" drops Exhaust).
			_summon_one_soldier(2, 1)
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
				player_mana += 2
				for _i in plus_draw:
					draw_one()
		"unholy_bargain":
			var bargain_draws: int = 2 + plus_draw
			if _friendly_deaths_this_fight > 0:
				bargain_draws += 1
			for i in bargain_draws:
				draw_one()
			damage_player_hero(2)
		"dark_pact":
			if target != null:
				var pact_gain: int = 1 + plus_dmg
				_trigger_player_sacrifice(target)
				target.take_damage(999)
				for c in _all_player_creatures():
					if c == target or not is_instance_valid(c) or c.current_hp <= 0:
						continue
					c.current_atk += pact_gain
					c.card_data.hp += pact_gain
					c.current_hp += pact_gain
					c.update_stat_display()
		"kings_command":
			# Go-wide crown: +1/+1 this fight PER friendly creature ("+" adds +1/+1
			# more) — dead on a thin board, a coronation on a full one.
			var kc_g: int = _all_player_creatures().size() + plus_dmg
			for c in _all_player_creatures():
				c.current_atk += kc_g
				c.card_data.hp += kc_g
				c.current_hp += kc_g
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
			if target != null:
				var cat_dmg: int = target.effective_atk() + plus_dmg
				var first_lane: int = maxi(0, target.current_lane - 1)
				var last_lane: int = mini(LANES_PER_ROW - 1, target.current_lane + 1)
				for lane in range(first_lane, last_lane + 1):
					for row in [ROW_FRONT, ROW_BACK]:
						var victim = _row_array(true, row)[lane]
						if victim != null and is_instance_valid(victim) and victim.current_hp > 0:
							victim.take_damage(cat_dmg)
		"soul_swap":
			if target != null:
				# Read effective ATK so temp/persistent buffs participate
				# in the swap. Strip the buff layers when writing back to
				# current_atk so the buffs aren't double-counted post-swap.
				var eff_atk: int = target.effective_atk()
				var new_atk: int = target.current_hp
				# Floor the swapped HP at 1: a 0-ATK body (Wither'd / debuffed) would
				# otherwise come out at 0 HP and be silently culled by _cleanup_dead,
				# so Soul Swap would destroy your own creature with no telegraph.
				var new_hp: int = maxi(1, eff_atk)
				target.current_atk = maxi(0, new_atk - target.temp_atk_buff - target.persistent_atk_buff)
				target.current_hp = new_hp
				target.card_data.hp = new_hp
				target.update_stat_display()
				# Upgraded Soul Swap (dmg_bonus): a parting blow on the post-swap body,
				# so the "+ takes 2 damage" the card promises actually lands.
				if plus_dmg > 0:
					target.take_damage(plus_dmg)
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
		"last_rites":
			# Morbid removal: 3 damage — 6 once a friendly has fallen this fight
			# (same counter the vengeance-rally Inspire reads).
			if target != null:
				target.take_damage((6 if _friendly_deaths_this_fight > 0 else 3)
					+ spell_dmg_bonus + plus_dmg)
		"fuel_the_pyre":
			if target != null:
				var atk = target.effective_atk()
				var pyre_lane: int = target.current_lane
				_trigger_player_sacrifice(target)
				target.take_damage(999)
				# Deterministic revenge: the flame leaps to whatever stands across
				# the victim's own lane; only an empty column scatters it.
				var pyre_opp: Control = get_opposing_card(pyre_lane, false)
				if pyre_opp != null:
					pyre_opp.take_damage(atk + plus_dmg)
				else:
					var enemies = _all_enemy_creatures()
					if enemies.size() > 0:
						enemies[randi() % enemies.size()].take_damage(atk + plus_dmg)
					else:
						damage_enemy_hero(atk + plus_dmg)
		"pillage":
			if target != null:
				var pillage_dmg: int = 2 + spell_dmg_bonus + plus_dmg
				target.take_damage(pillage_dmg)
				damage_enemy_hero(1 + plus_dmg)
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
			# Muster one Soldier per pitched card (3/2 if upgraded, else 2/1) —
			# bodies on the board, NOT card draw.
			var wc_atk: int = 3 if is_plus else 2
			var wc_hp: int = 2 if is_plus else 1
			for i in picked.size():
				_summon_one_soldier(wc_atk, wc_hp)
		"battle_hymn":
			for c in _all_player_creatures():
				c.temp_atk_buff += 1
				c.current_hp += 1
				c.card_data.hp += 1
				c.update_stat_display()
		"earthquake":
			var quake_dmg: int = 2 + spell_dmg_bonus + plus_dmg
			for c in _all_creatures_both_sides():
				if c != null and is_instance_valid(c):
					c.take_damage(quake_dmg)
			_cleanup_dead()
			for quake_lane in range(LANES_PER_ROW):
				var quake_enemy = _enemy_field[quake_lane]
				if quake_enemy != null and is_instance_valid(quake_enemy) and quake_enemy.current_hp > 0:
					_relocate_creature(quake_enemy, true, ROW_BACK, quake_lane)
			_refresh_adjacency_buffs()
		"slash":
			if target != null:
				var can_blast_move: bool = target.current_row == ROW_FRONT \
					and _row_array(true, ROW_BACK)[target.current_lane] == null
				var slash_dmg: int = 2 + spell_dmg_bonus + plus_dmg
				if not can_blast_move:
					slash_dmg += 2
				target.take_damage(slash_dmg)
				if is_instance_valid(target) and target.current_hp > 0 and can_blast_move:
					_relocate_creature(target, true, ROW_BACK, target.current_lane)
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
			# Rallying yell — the whole warband strikes in the Swift pre-phase
			# this round ("+" adds +1 ATK while they charge). Free simultaneity
			# tech: your line trades before the enemy's normal blows land.
			for c in _all_player_creatures():
				c.set_meta("war_cry_swift", true)
				if plus_dmg > 0:
					c.temp_atk_buff += plus_dmg
				c.update_stat_display()
		"patch_up":
			# Field Surgery: full triage, real cost — the patient is off the
			# table for the round. The decision is WHEN: a wounded fatty healed
			# mid-fight forfeits its swing, so timing the surgery matters. The
			# cantrip keeps it from sitting dead in a hand mid-rush.
			if target != null:
				target.current_hp = int(target.card_data.get("hp", target.current_hp))
				target.state.stunned = true
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("RESTING", Color(0.85, 0.78, 0.45))
				target.update_stat_display()
				draw_one()
		"flame_bolt":
			# Combo — base 3, ramped to 5 if you've cast any spell this turn.
			# _cards_played_this_turn counts both creatures and spells, but the
			# combo specifically wants a SPELL precedent, so we check the
			# spell counter (_first_spell_this_turn flips on first spell cast).
			var dmg: int = (5 if _spells_cast_this_turn >= 1 else 3) + spell_dmg_bonus + plus_dmg
			damage_enemy_hero(dmg)
		"quick_shot":
			var qs_slay: bool = false
			if target != null:
				target.take_damage(1 + spell_dmg_bonus + plus_dmg)
				qs_slay = target.current_hp <= 0
			else:
				damage_enemy_hero(1 + spell_dmg_bonus + plus_dmg)
			if qs_slay:
				for _i in 1 + plus_slay_draw:
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
				# "Your Swift creatures" includes granted Swift (War Cry,
				# Battle Drummer) — they strike in the pre-phase this round,
				# so the ambush bonus honestly belongs to them too.
				if _is_swift_attacker(c):
					c.temp_atk_buff += swift_gain
					c.update_stat_display()
		"inspire":
			for c in _all_player_creatures():
				c.set_meta("war_cry_swift", true)
				c.set_meta("inspire_piercing", true)
				if plus_dmg > 0:
					c.temp_atk_buff += plus_dmg
				c.update_stat_display()
		"lost_tome":
			# Discover a random common spell.
			await _show_discover("spell", "common")
		"war_council":
			# Discover any card.
			await _show_discover("any", "")
		"scrap":
			if _hand.size() > 0:
				var max_scrap: int = mini(2, _hand.size())
				var picked: Array = await _show_discard_picker(max_scrap,
					"Cinders — discard up to %d for Command" % max_scrap, true)
				for c in picked:
					_hand.erase(c)
					_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
					if c.get_parent() != null:
						c.get_parent().remove_child(c)
					c.queue_free()
				if picked.size() > 0:
					player_mana += picked.size() * (1 + plus_mana)
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
			# Pyre board-clear (card "Wildfire", Exhaust). Face damage only counts
			# creatures killed by the blast, so it rewards finishing the burn.
			var wf_targets: Array = _all_enemy_creatures()
			var wf_kills: int = 0
			var wf_dmg: int = 2 + spell_dmg_bonus + plus_dmg
			for c in wf_targets:
				if c != null and is_instance_valid(c):
					_vfx_fire(c.get_global_rect().get_center())
					var hp_before: int = c.current_hp
					c.take_damage(wf_dmg)
					if hp_before > 0 and c.current_hp <= 0:
						wf_kills += 1
			_cleanup_dead()
			if wf_kills > 0:
				if _enemy_hp_label != null:
					_vfx_fire(_enemy_hp_label.get_global_rect().get_center())
				damage_enemy_hero(wf_kills)
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
		"rout":
			# The enemy line breaks and runs: every enemy creature is driven into
			# its back row, takes damage, and forfeits its attack this round.
			# Blocked back slots just mean the creature holds ground — still stunned.
			var rout_dmg: int = 1 + plus_dmg
			for c in _all_enemy_creatures():
				if not is_instance_valid(c):
					continue
				if c.current_row == ROW_FRONT:
					if _relocate_creature(c, true, ROW_BACK, c.current_lane):
						spawn_floating_number(c.global_position \
							+ Vector2(c.size.x * c.scale.x * 0.5, -10),
							"ROUTED", Color(0.85, 0.78, 0.45), false)
				c.state.stunned = true
				if c.has_method("_spawn_keyword_chip"):
					c._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
				c.take_damage(rout_dmg)
			_refresh_adjacency_buffs()
		"virulence":
			# One round where the warband's blades drip — every friendly strike
			# is poisonous. Side-scoped flag (not per-card) so creatures played
			# AFTER the cast are envenomed too; strike code reads it directly.
			_virulence_active[0] = true
			for c in _all_player_creatures():
				spawn_keyword_callout_kw(c, "poison")
		"mending_light":
			if player_hp < player_max_hp:
				player_hp = mini(player_hp + 5, player_max_hp)
				_stoke_acolytes(false)
			for c in _all_player_creatures():
				c.current_hp = mini(c.current_hp + 2, c.card_data.hp)
				c.update_stat_display()
		"banish":
			if target != null:
				var banish_limit: int = 4 + plus_dmg
				if target.current_hp <= banish_limit:
					var pos = _find_creature_position(target)
					if not pos.is_empty():
						_row_array(pos.is_enemy, pos.row)[pos.lane] = null
						var slots = _slot_array(pos.is_enemy, pos.row)
						if pos.lane < slots.size():
							_restore_slot_label(slots[pos.lane], pos.lane)
					target.queue_free()
				else:
					target.take_damage(banish_limit)
				for _i in plus_draw:
					draw_one()
		"doubled_hour":
			# The hour strikes twice: this round the player's creatures attack
			# twice (_do_combat runs a second swing pass; snipers re-snipe).
			_doubled_hour[0] = true
			draw_one()
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
				target.take_damage(maxi(3, missing) + plus_dmg)  # floor 3: never a dead draw on a healthy target
				if target.current_hp <= 0:
					for _i in 1 + plus_slay_draw:
						draw_one()
		"adrenaline":
			player_mana += 2
			for _i in 1 + plus_draw:
				draw_one()
		"coin":
			# The Coin (going-second compensation). Solo never grants it, but keep a
			# resolver arm so it's never a dead card if a future effect hands it over.
			player_mana += 1
		"bloodletting":
			damage_player_hero(1)
			player_mana += 2 + plus_mana
			if _friendly_deaths_this_fight > 0:
				draw_one()
		"turbo":
			player_mana += 2
			for _i in plus_draw:
				draw_one()
			_player_discard_pile.append(CardDB.random_curse_id())
		"recycle":
			# Recycle: player picks a card in hand to exhaust; gain mana equal
			# to its cost. Upgraded draws after the burn. Useful for cashing in dead-weight
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
					player_mana += cost
					for _i in plus_draw:
						draw_one()
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
				spawn_keyword_callout_kw(target, "poison")
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
			var rc_back_dmg: int = 2 + spell_dmg_bonus + plus_dmg
			var rc_fallback_dmg: int = 1 + spell_dmg_bonus + plus_dmg
			var rc_hit_any: bool = false
			for enemy in _enemy_back:
				if enemy != null and is_instance_valid(enemy) and enemy.current_hp > 0:
					enemy.take_damage(rc_back_dmg)
					rc_hit_any = true
			if not rc_hit_any:
				var rc_pool: Array = _all_enemy_creatures()
				if rc_pool.size() > 0:
					rc_pool[randi() % rc_pool.size()].take_damage(rc_fallback_dmg)
			_cleanup_dead()
		"hex":
			if target != null:
				var had_keywords: bool = not target.card_data.get("keywords", []).is_empty()
				target.take_damage((4 if had_keywords else 1) + plus_dmg)
				if is_instance_valid(target):
					var combat_kws := KeywordEffects.COMBAT_KEYWORDS.duplicate()
					for kw in combat_kws:
						target.card_data.keywords.erase(kw)
						if kw == "sniper":
							target.card_data.erase("sniper")
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
	# PlayLog: emit the player's spell play (stashed at _play_spell) with the
	# resolved target, using the pre-cast snapshot for a clean state→action pair.
	if not _pl_spell_pending.is_empty():
		var tgt_brief = null
		if _last_spell_target_ref != null:
			var mt = _last_spell_target_ref.get_ref()
			if mt != null and is_instance_valid(mt):
				var side := "enemy" if (_enemy_field.has(mt) or _enemy_back.has(mt)) else "player"
				tgt_brief = {"id": mt.card_id, "lane": mt.current_lane,
					"row": mt.current_row, "side": side}
		_pl_log("play_spell", {
			"card": _pl_spell_pending.get("card", ""),
			"uid": _pl_spell_pending.get("uid", -1),
			"cost": _pl_spell_pending.get("cost", 0),
			"targeting": _pl_spell_pending.get("targeting", "none"),
			"target": tgt_brief,
		}, _pl_spell_pending.get("snap"))
		_pl_spell_pending = {}

	# Pyromancer's Scar (class-restricted): the first spell each combat fires
	# a second time against the same target before bookkeeping. We snapshot
	# the spell data (in case the doubled cast mutates it) and the cached
	# last-target ref; non-targeted spells re-resolve with target=null, while
	# targeted spells reuse the original target if it is still valid.
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
		var ex_anchor := card.global_position \
			+ Vector2(card.size.x * card.scale.x * 0.5, card.size.y * card.scale.y * 0.10)
		spawn_keyword_callout(ex_anchor, "EXHAUST",
			_CALLOUT_STYLE["exhaust"]["col"], GameTheme.get_keyword_icon("exhaust"))
		if AudioBank != null:
			AudioBank.play_sfx("card_discard", 0.06, -6.0, 0.74)
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
	# Emberwright (ember_per_spell): each spell cast pings the enemy face — the
	# spell-matters board-pressure payoff that companions Hexblade's ATK scaling.
	for _ew in _all_player_creatures():
		if _ew.card_data.get("passive", "") == "ember_per_spell":
			damage_enemy_hero(3 if bool(_ew.card_data.get("is_upgraded", false)) else 2)
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
				# Debug builds only — in an exported release this key must be dead,
				# or every player who brushes F1 instant-wins the fight.
				if OS.is_debug_build() and phase != Phase.GAME_OVER:
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
				if _is_net():
					_net_cast_targeted(spell_card, e)
					return
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
				if _is_net():
					_net_cast_targeted(spell_card, p)
					return
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
		if _is_net():
			_net_cast_targeted(spell_card, null)
			return
		await _resolve_spell(spell_card.card_data, null, -1)
		_after_spell(spell_card)
		return


func _use_combat_potion(index: int) -> void:
	## Click handler for a combat HUD potion slot. Cancels any in-flight spell
	## targeting (you can't target both at once). Non-targeted potions resolve
	## immediately; targeted ones enter potion-targeting mode.
	if phase != Phase.PLAYER_TURN:
		return
	# Net: only on your own active turn (the belt draws no potions the foe owns).
	if _is_net() and _net_active_index != _net_my_index():
		return
	var belt: Array = _ctx_potions()
	if index < 0 or index >= belt.size():
		return
	if _targeting_spell != null:
		_cancel_targeting()
	var pid: String = String(belt[index])
	var data: Dictionary = PotionDB.get_potion(pid)
	if data.is_empty() or data.get("usable_in", "combat") == "map":
		return
	# Grave-Digger's Nip with a clean hand would drink for nothing — refuse
	# instead of consuming (targeted potions can't waste; this one could).
	if data.get("effect", "") == "purge_hand_curses" \
			and not _hand.any(func(c): return CardDB.is_curse(c.card_id)):
		_show_info("No Curses in hand to bury.")
		return
	_pl_log("potion", {"potion": pid})
	# Skirmish: non-targeted potions route straight through the net dispatcher
	# (host-authoritative board/HP / caster-local Command + draw); targeted ones
	# enter potion-targeting mode exactly like solo, then resolve on the click via
	# _try_resolve_potion_target → _net_use_potion with the picked entity.
	if _is_net():
		var net_targeting: String = String(data.get("targeting", "none"))
		if net_targeting == "none":
			_net_use_potion(pid, index)
		else:
			_targeting_potion_idx = index
			_info_label.text = "%s — target a %s" % [
				data.get("name", pid),
				"friendly creature" if net_targeting == "friendly_creature" else "creature"
			]
		return
	var targeting: String = data.get("targeting", "none")
	if targeting == "none":
		_resolve_combat_potion(pid, null)
		RunState.consume_potion(index)
		_dregs_bottle_throw()
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
	# _ctx_potions() is the belt for BOTH modes (RunState in solo, the net slot in
	# skirmish), so the index resolves against the same list the click drew from.
	var belt: Array = _ctx_potions()
	if _targeting_potion_idx >= belt.size():
		_cancel_potion_targeting()
		return
	var pid: String = String(belt[_targeting_potion_idx])
	var data: Dictionary = PotionDB.get_potion(pid)
	var targeting: String = data.get("targeting", "none")
	var pool: Array = []
	if targeting in ["friendly_creature", "any_creature"]:
		pool.append_array(_all_player_creatures())
	if targeting in ["enemy_creature", "any_creature"]:
		pool.append_array(_all_enemy_creatures())
	for c in pool:
		if _is_click_on_card(pos, c):
			if _is_net():
				# Net: the host-authoritative resolver applies + board-syncs; the
				# belt consume + foe drink-beat ride inside _net_use_potion.
				_net_use_potion(pid, _targeting_potion_idx, c)
			else:
				_resolve_combat_potion(pid, c)
				RunState.consume_potion(_targeting_potion_idx)
				_dregs_bottle_throw()
			_targeting_potion_idx = -1
			_info_label.text = ""
			_rebuild_potion_bar()
			_update_hud()
			return


func _cancel_potion_targeting() -> void:
	_targeting_potion_idx = -1
	_info_label.text = ""


func _dregs_bottle_throw() -> void:
	## Dregs relic: the drained bottle follows the draught — 2 damage to a
	## random enemy creature, or the enemy face if the field is clear. Fired
	## from both drink paths (instant + targeted), after the potion resolves.
	if not _has_relic("dregs") or _is_net():
		return
	var dmg: int = int(RelicDB.get_relic("dregs").get("value", 2))
	var pool: Array = _all_enemy_creatures()
	if pool.size() > 0:
		var t: Control = pool[randi() % pool.size()]
		spawn_floating_number(_card_center(t) + Vector2(0, -14),
			"DREGS %d" % dmg, Color(0.55, 0.85, 0.45), false)
		t.take_damage(dmg)
	else:
		damage_enemy_hero(dmg)


func _resolve_combat_potion(pid: String, target: Control) -> void:
	## Apply the in-combat effect of `pid`. `target` is non-null only for
	## targeted potions. Effects mirror existing combat primitives so each
	## handler stays tiny.
	var data: Dictionary = PotionDB.get_potion(pid)
	var quaff_line := "You quaff the [color=%s]%s[/color]" \
		% [_LOG_PLAYER_COL, String(data.get("name", pid))]
	if target != null and is_instance_valid(target):
		quaff_line += " on %s" % _log_card_ref(target)
	# Potion glyph in the margin: painted PNG shows untinted, the white
	# silhouette kit renders tinted by the potion's colour (same rule as Shop).
	var pot_icon: Texture2D = PotionDB.icon_for(pid)
	var pot_tint: Color = Color.WHITE if PotionDB.is_painted_icon(pid) \
		else data.get("color", Color(0.7, 0.7, 0.7))
	_log_event(quaff_line + ".", {}, 0, pot_icon, pot_tint)
	match data.get("effect", ""):
		"heal_hp":
			var pot_before: int = player_hp
			RunState.heal_hero(8)
			player_hp = RunState.hero_hp
			if player_hp > pot_before:
				_show_lifelink_heal(player_hp - pot_before)
				_stoke_acolytes(false)
		"column_strike":
			# Sapper's Charge: collapse a column — the target and whoever shares
			# its lane in the other row both take 4. Grab the lane-mate BEFORE
			# damage so a dying target can't orphan the second hit.
			if target != null and target.is_creature():
				var sap_lane: int = target.current_lane
				var sap_other: int = ROW_BACK if target.current_row == ROW_FRONT else ROW_FRONT
				var sap_mate: Control = _row_array(true, sap_other)[sap_lane]
				_vfx_fire(target.get_global_rect().get_center())
				target.take_damage(4)
				if sap_mate != null and is_instance_valid(sap_mate):
					_vfx_fire(sap_mate.get_global_rect().get_center())
					sap_mate.take_damage(4)
				_cleanup_dead()
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
			# Vampiric Draught: friendly heals you for 2 on battle damage this
			# fight, plus a 4 HP top-up now. Mirrors Censer Light's runtime
			# keyword-grant pattern so _apply_combat_strike_riders heals off it.
			if target != null and target.is_creature():
				if "lifelink" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("lifelink")
				target.card_data["lifelink"] = maxi(2, int(target.card_data.get("lifelink", 0)))
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LIFELINK", Color(0.95, 0.35, 0.45))
				_vfx_blight(target.get_global_rect().get_center())
				target.update_stat_display()
			var elx_before: int = player_hp
			RunState.heal_hero(4)
			player_hp = RunState.hero_hp
			if player_hp > elx_before:
				_show_lifelink_heal(player_hp - elx_before)
				_stoke_acolytes(false)
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
		"sacrifice_for_command":
			# Butcher's Dram: pay a body, seize the turn. Routes through the
			# canonical sacrifice trigger (Bone Pile / Cleaver / Scythe / the
			# ON_PLAYER_SACRIFICE reactive all fire), then the 999 kill mirrors
			# the Offering spell.
			if target != null and target.is_creature():
				_trigger_player_sacrifice(target)
				target.take_damage(999)
				player_mana += 3
		"purge_hand_curses":
			# Grave-Digger's Nip: bury (exhaust) every Curse-family card in hand,
			# draw one per burial — the hand-exhaust flow mirrors Recycle. Note
			# the replacement draws can sting (curse_on_draw fires as normal);
			# the ground gives as good as it gets.
			var buried: int = 0
			for nip_card in _hand.duplicate():
				if CardDB.is_curse(nip_card.card_id):
					_hand.erase(nip_card)
					if nip_card.get_parent() != null:
						nip_card.get_parent().remove_child(nip_card)
					_exhaust_pile.append(nip_card.card_id)
					nip_card.queue_free()
					buried += 1
			for _i in range(buried):
				draw_one()
			_layout_hand()
			if buried > 0:
				_show_info("Buried %d — drew %d." % [buried, buried])
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
	## Phoenix Brew: return the player's last dead creature to the foremost
	## empty lane as a 1/1 with its keywords. Falls back to no-op if nothing
	## died or no empty slot exists.
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
	# Front-preferred, left-to-right (empties was built front row first) —
	# same fill as Conscription Brew. A random lane threw away the one
	# placement read the revive could offer.
	var pick: Dictionary = empties[0]
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


func _targeting_human(targeting: String) -> String:
	# Plain-language name of a spell's legal target set, for the targeting prompt.
	match targeting:
		"enemy_creature": return "an enemy creature"
		"friendly_creature": return "a friendly creature"
		"any_creature": return "any creature"
		"any": return "any creature — or click the enemy banner to hit their face"
		_: return "a target"


func _is_click_on_card(pos: Vector2, card: Control) -> bool:
	var rect = Rect2(card.global_position, card.size)
	return rect.has_point(pos)


func _maybe_show_banking_tutorial() -> void:
	if _banking_tutorial_shown:
		return
	_banking_tutorial_shown = true
	UserSettings.mark_banking_tutorial_seen()
	_show_tutorial_tip("BANK — unspent Command carries over (max 2). End early to save up.")


func _maybe_show_intents_tutorial() -> void:
	if _intents_tutorial_shown:
		return
	_intents_tutorial_shown = true
	UserSettings.mark_intents_tutorial_seen()
	_show_tutorial_tip("READ THE LINE — four lanes, front guards back. Forecast chips show what enemy strikes will do.")


func _maybe_show_pile_tutorial() -> void:
	if _pile_tutorial_shown:
		return
	_pile_tutorial_shown = true
	UserSettings.mark_pile_tutorial_seen()
	_show_tutorial_tip("TIP: Click your deck or discard pile (bottom-left) to see what's in it.")


## Right-click discard marking (2026-07-07 rework): toggles a hand card's
## marked-for-discard state. No cap — mark as many as you like; every marked
## card is flushed to the discard pile when the turn ends (see
## _flush_marked_discards). Works in net too — the flush is hand-LOCAL (own
## hand, own discard pile; each peer owns its piles); the opponent gets an
## EV_DISCARD_FX beat plus the standard EV_HAND_COUNT tick-down. Curses are
## exempt — clogging is their whole job, and Cowardice already sells an exit.
func _on_card_dismiss_requested(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _is_net():
		if _net_match_over:
			return
		# Sealed orders: both sides act at once — marking is open while our own
		# orders window is (not yet sealed). Alternating: only during MY window,
		# same gate as playing a card.
		if _is_sealed():
			if _sealed_await_foe:
				return
		elif _net_active_index != NetMatch.local_player_index:
			return
	if _targeting_spell != null or _targeting_potion_idx >= 0:
		return
	if not _hand.has(card):
		return
	if CardDB.is_curse(card.card_id):
		_show_info("A curse cannot be discarded — it must be endured.")
		return
	var turn_on: bool = not card.marked_for_discard
	card.set_discard_marked(turn_on)
	if turn_on:
		spawn_floating_number(card.global_position
			+ Vector2(card.size.x * card.scale.x * 0.5, -6),
			"DISCARDS AT TURN'S END", Color(0.78, 0.72, 0.62), false)
	AudioBank.play_sfx("card_discard", 0.04, -6.0, 0.9 if turn_on else 1.12)
	_layout_hand()


## End-of-turn flush: every marked card leaves the hand for the discard pile in
## one staggered cascade (the choosing was the turn's quiet business; this is
## the payoff beat). Returns the number discarded. Called from the solo end-turn,
## the alternating DONE/STRIKE, and the sealed SEAL/PASS commits — always inside
## the local player's own acting window, so the hand-local mutation is safe in net.
func _flush_marked_discards() -> int:
	var marked: Array[Control] = []
	for c in _hand:
		if c != null and is_instance_valid(c) and c.marked_for_discard:
			marked.append(c)
	if marked.is_empty():
		return 0
	# Deserter's Toll: the FIRST card discarded each turn strikes on its way
	# out — a random enemy creature takes its Command cost in damage (0-cost
	# cards just leave quietly). Solo only, same rationale as the Volunteer
	# below: discards are hand-local in net and the hit wouldn't replay.
	if _has_relic("deserters_toll") and not _is_net():
		var toll: int = int(marked[0].card_data.get("cost", 0))
		var toll_pool: Array = _all_enemy_creatures()
		if toll > 0 and toll_pool.size() > 0:
			var toll_t: Control = toll_pool[randi() % toll_pool.size()]
			spawn_floating_number(_card_center(toll_t) + Vector2(0, -14),
				"DESERTER'S TOLL %d" % toll, Color(0.78, 0.72, 0.62), false)
			toll_t.take_damage(toll)
	for c in marked:
		_hand.erase(c)
		_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
		# The Volunteer (dismiss_muster): being thrown away IS deployment — a copy
		# (a token wearing its current printed stats, so a forged one arrives
		# forged) reports to the first open lane, front row first, just ahead of
		# the clash. The card itself still cycles through the discard. Solo only —
		# discards are hand-local in net and the muster wouldn't sync (skirmish
		# denylists it).
		if bool(c.card_data.get("dismiss_muster", false)) and not _is_net():
			var vol_done := false
			for vol_row in [ROW_FRONT, ROW_BACK]:
				for vol_lane in range(LANES_PER_ROW):
					if not vol_done and _row_array(false, vol_row)[vol_lane] == null:
						summon_token(int(c.card_data.get("atk", 2)), int(c.card_data.get("hp", 3)), vol_lane, false, vol_row, {}, String(c.card_data.get("name", "The Volunteer")))
						vol_done = true
			if vol_done:
				spawn_floating_number(c.global_position + Vector2(c.size.x * c.scale.x * 0.5, -30), "VOLUNTEERED", Color(1.0, 0.84, 0.35), false)
	var head: Control = marked[0]
	spawn_floating_number(head.global_position
		+ Vector2(head.size.x * head.scale.x * 0.5, -6),
		"DISCARDED" if marked.size() == 1 else "DISCARDED ×%d" % marked.size(),
		Color(0.78, 0.72, 0.62), false)
	for i in marked.size():
		marked[i].set_discard_marked(false)   # drop the ribbon before the flight
		_animate_dismiss(marked[i], 0.09 * float(i))
	_layout_hand()
	_update_hud()
	if _is_net():
		_net_send_discard_fx(marked.size())
		_net_broadcast_hand_count()
	return marked.size()


## The discard flight: the writ arcs down to the discard pile, shrinking
## and fading onto the stack, then frees. The pile's counter ticking at the
## landing beat is what tells the player WHERE the card went — the old
## instant vanish read as a bug, not an action. `delay` staggers a multi-card
## cascade so the flush reads as cards peeling off one by one.
func _animate_dismiss(card: Control, delay: float = 0.0) -> void:
	if card.has_method("begin_flight"):
		card.begin_flight()
	card.z_index = 140
	var target := Vector2(150.0, 640.0)
	if _discard_count_label != null and is_instance_valid(_discard_count_label):
		target = _discard_count_label.global_position + Vector2(-52.0, -70.0)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func():
			if AudioBank != null:
				AudioBank.play_sfx("card_discard", 0.08, -4.0))
	else:
		AudioBank.play_sfx("card_discard")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "global_position", target, 0.38) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(delay)
	tw.tween_property(card, "scale", Vector2(0.22, 0.22), 0.38) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(delay)
	tw.tween_property(card, "rotation", -0.30, 0.38) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(delay)
	tw.tween_property(card, "modulate:a", 0.10, 0.38) \
		.set_ease(Tween.EASE_IN).set_delay(delay)
	tw.chain().tween_callback(card.queue_free)


func _maybe_show_dismiss_tutorial() -> void:
	if _dismiss_tutorial_shown:
		return
	_dismiss_tutorial_shown = true
	UserSettings.mark_dismiss_tutorial_seen()
	_show_tutorial_tip("RIGHT-CLICK hand cards to mark them for discard — as many as you like. They're thrown out when your turn ends.")


func _maybe_show_combat_model_tutorial() -> void:
	# Fired on the first End Turn — the simultaneous-combat model is the rule new
	# players least expect, and it only becomes visible the moment the lines clash.
	if _combat_model_tutorial_shown:
		return
	_combat_model_tutorial_shown = true
	UserSettings.mark_combat_model_tutorial_seen()
	_show_tutorial_tip("BOTH ARMIES STRIKE AT ONCE — Swift goes first, then front ranks hit before the back ranks.")


func _show_tutorial_tip(msg: String) -> void:
	# Longer dwell than _show_info — new players need time to actually read.
	# Falls back to the standard info channel if _info_label isn't built yet.
	if _info_label == null:
		return
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	get_tree().create_timer(7.0).timeout.connect(func():
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
	if _player_draw_pile.is_empty():
		return
	_draw_card(_player_draw_pile.pop_front())
	_extra_draws_this_turn += 1
	# Reactive passive: ON_PLAYER_DRAW (triggers only on extra draws beyond 5)
	if _extra_draws_this_turn > _refill_draws_this_turn:
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
	# Pen Nib: if this uid was marked this fight, stamp it 6/6 Piercing before
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
	# Hand cards use the BAKED-overlay path: the frame + art + furniture are a single
	# pre-baked 3× texture (cheap to draw and to drag), while the name, rules text and
	# stats are drawn LIVE on top with the MSDF font renderer so they stay razor-sharp
	# at any scale. This keeps card-dragging smooth — a full live render (chart_proto)
	# re-composites ~20-40 sub-draws PER card every frame, which is what made dragging
	# a hand choppy (×4 under supersampling). On a bake cache-miss (a card drawn before
	# the pre-bake ran) _build_layout falls back to the live chart_proto render anyway,
	# so nothing ever renders wrong — it's just not the cheap path until the next draw.
	card.live_baked_mode = true
	_hand_container.add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))
	card.dismiss_requested.connect(_on_card_dismiss_requested.bind(card))
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
	# Branded-curse draw sting (Deserter's Mark / Grave-Debt / War-Debt): fires
	# the moment the curse lands in hand, with floating text at the draw pile so
	# the pain is attributed to the card, not to mystery. Solo only — the
	# skirmish draft pool can't contain curses, and net hands are host-driven.
	if not _is_net():
		_apply_curse_draw_sting(card.card_data)


func _apply_curse_draw_sting(card_data: Dictionary) -> void:
	var sting: Dictionary = card_data.get("curse_on_draw", {})
	if sting.is_empty():
		return
	var value: int = int(sting.get("value", 1))
	var cname: String = String(card_data.get("name", "Curse"))
	# Float the sting at the draw pile's screen spot (where the card just rose).
	var float_pos := Vector2(160.0, 300.0)
	match String(sting.get("type", "")):
		"lose_command":
			var taken: int = mini(value, player_mana)
			player_mana = maxi(0, player_mana - value)
			spawn_floating_number(float_pos, "-%d COMMAND" % value, Color(0.55, 0.78, 1.0))
			_show_info("%s — you lose %d Command this turn." % [cname, value])
			if taken > 0:
				_update_hud()
		"hero_damage":
			spawn_floating_number(float_pos, "-%d" % value, Color(0.95, 0.35, 0.30))
			_show_info("%s bites — %d damage." % [cname, value])
			damage_player_hero(value)
		"lose_gold":
			var paid: int = mini(value, RunState.gold)
			RunState.gold = maxi(0, RunState.gold - value)
			spawn_floating_number(float_pos, "-%d GOLD" % paid, Color(0.95, 0.80, 0.35))
			_show_info("%s — the ledger collects %d gold." % [cname, paid])
			_update_hud()


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
	# PEEK 92 the resting bottom-centre lands at y=982, so the card TOP sits
	# at ~y=766 — a 29px margin below the player back row (which ends at y=737).
	# Tuned so the screen-edge crop lands at the TOP of the rules-text box:
	# at the old PEEK 76 the edge cut rules text mid-sentence, which read as a
	# layout bug. At rest a card shows cost + name + art (the identity read);
	# the rules live in the hover detail panel anyway. Hover lifts the card by
	# 96 px (Card2D._on_mouse_entered — raised in step with this +16) so the
	# hovered pose is unchanged on screen.
	const PEEK := 92.0

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
		# Marked-for-discard cards sink out of the fan line — already halfway
		# to the pile. The ribbon + dim (Card2D.set_discard_marked) do the rest.
		# Kept gentle (was 34) so the card's upper third — which now carries the
		# DISCARD band — stays clear of the screen fold on a resting hand.
		if card.marked_for_discard:
			y_offset += 20.0
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
	if AudioBank != null:
		# Soft paper-slip per departing card; wide jitter so a multi-card
		# sweep flutters instead of machine-gunning one sample.
		AudioBank.play_sfx("card_discard", 0.10, -8.0)
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

func damage_player_hero(amount: int, from_effect: bool = true) -> void:
	player_hp -= amount
	_face_damage_taken_this_fight += amount
	# Clash replay: a face hit is a logged beat (owner 0 = the host's hero).
	if _net_clash_recording and amount > 0:
		_net_clash_log.append({"f": 0, "fhp": int(player_hp), "n": int(amount)})
	# Ember Warden (grows_on_burn), mirrored: effect damage to the PLAYER's face
	# stokes wardens on the opposing side (net client wardens; solo enemy wardens
	# only if an encounter deck fields one). Creature strikes pass from_effect=false.
	if from_effect and amount > 0:
		for _we in _all_friendly(true):
			if is_instance_valid(_we) and _we.card_data.get("passive", "") == "grows_on_burn":
				var we_gain: int = 2 if bool(_we.card_data.get("is_upgraded", false)) else 1
				_we.current_atk += we_gain
				_we.update_stat_display()
				spawn_floating_number(_we.global_position \
					+ Vector2(_we.size.x * _we.scale.x * 0.5, -10),
					"+%d ATK" % we_gain, Color(1.0, 0.62, 0.20), false)
				_net_fx_text(_we, "+%d ATK" % we_gain, Color(1.0, 0.62, 0.20))
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
		_log_event("You take [color=#e06a50]%d[/color] — [color=#f2e6c8]%d[/color] life left." \
			% [amount, maxi(player_hp, 0)])
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


func damage_enemy_hero(amount: int, from_effect: bool = true) -> void:
	# Pyre Stoker: face damage you deal this turn gets +1 if you played 3+ cards.
	# Reads _cards_played_this_turn directly so each face hit recomputes the
	# bonus — if you cross the threshold mid-turn, subsequent hits scale.
	if _has_relic("pyre_stoker") and _cards_played_this_turn >= 3 and amount > 0:
		amount += int(RelicDB.get_relic("pyre_stoker").get("value", 1))
	enemy_hp -= amount
	# Clash replay: owner 1 = the client's hero (amount is post-Pyre-Stoker).
	if _net_clash_recording and amount > 0:
		_net_clash_log.append({"f": 1, "fhp": int(enemy_hp), "n": int(amount)})
	# Ember Warden (grows_on_burn): the enemy face burning from a spell or effect
	# (never a plain creature strike — those pass from_effect=false) stokes the
	# player's wardens: +1 ATK this fight, +2 upgraded.
	if from_effect and amount > 0:
		for _ww in _all_friendly(false):
			if is_instance_valid(_ww) and _ww.card_data.get("passive", "") == "grows_on_burn":
				var ww_gain: int = 2 if bool(_ww.card_data.get("is_upgraded", false)) else 1
				_ww.current_atk += ww_gain
				_ww.update_stat_display()
				spawn_floating_number(_ww.global_position \
					+ Vector2(_ww.size.x * _ww.scale.x * 0.5, -10),
					"+%d ATK" % ww_gain, Color(1.0, 0.62, 0.20), false)
				_net_fx_text(_ww, "+%d ATK" % ww_gain, Color(1.0, 0.62, 0.20))
	# Net mirror of damage_player_hero's Vengeance: in skirmish enemy_hp is the CLIENT's
	# hero, so a face hit here grows the client's Vengeance creatures (+2, +3 upgraded).
	if _is_net() and amount > 0:
		for _vg in _all_friendly(true):
			if _vg.card_data.get("passive", "") == "vengeance_growth":
				_vg.current_atk += 3 if bool(_vg.card_data.get("is_upgraded", false)) else 2
				_vg.update_stat_display()
	if amount > 0:
		_log_event("The foe takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
			% [amount, maxi(enemy_hp, 0)])
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
	# Online skirmish: the ONLY relics that exist are the drafted battle relic(s)
	# in the player's own SkirmishState slot — resource-local effects by
	# construction (SkirmishState.NET_RELIC_POOL), applied per-peer inside each
	# side's own _start_round. A leftover campaign RunState.relics from a prior
	# run in the same session still can't leak into a net fight.
	if _is_net():
		var slot = _net_my_slot()
		return slot != null and slot.relics.has(id)
	# Cached lookup — _relic_set is rebuilt at combat start and on relic acquisition.
	# Falls back to RunState on cache miss so this never breaks after live mutation.
	if _relic_set.is_empty():
		_rebuild_relic_cache()
	return _relic_set.has(id)


## Side-aware, host-authoritative relic check for board/HP relics whose effect must
## resolve for BOTH warbands in a skirmish. `owner_is_enemy` names the side the hook
## is firing for (false = the host's own / the solo player, true = the client). The
## effect itself is applied HOST-SIDE and rides the board snapshot to the client, so
## this returns false on the client (it never applies board relics locally — the host
## does + syncs) and false for the enemy side in solo (enemies own no relics). Wire a
## board relic here instead of _has_relic at any hook that already runs per-side
## (e.g. _apply_start_round_passives / _apply_ally_death_passives), then add the id to
## SkirmishState.NET_RELIC_POOL. Resource-local relics stay on _has_relic (each peer
## applies its own).
func _relic_active_for_side(owner_is_enemy: bool, id: String) -> bool:
	if not _is_net():
		return (not owner_is_enemy) and _has_relic(id)
	if not _is_host():
		return false
	var slot = SkirmishState.get_slot(1 if owner_is_enemy else 0)
	return slot != null and slot.relics.has(id)


func _rebuild_relic_cache() -> void:
	_relic_set.clear()
	if _is_net():
		return   # net reads the SkirmishState slot directly in _has_relic — no cache
	for rid in RunState.relics:
		_relic_set[rid] = true


func _compute_spell_tome() -> void:
	## spell_tome: if 50%+ of the run deck is spells, all spells cost 1 less.
	## Deck composition is fixed during a combat, so compute once at start.
	_spell_tome_active = false
	if not _has_relic("spell_tome"):
		return
	var deck: Array = _ctx_deck()
	var total: int = deck.size()
	if total == 0:
		return
	var spells := 0
	for cid in deck:
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
	## Pen Nib payoff: the leftmost creature in hand becomes 6/6 Piercing for
	## the rest of this fight. No picker, no deck interruption.
	for c in _hand:
		if c != null and is_instance_valid(c) and c.is_creature():
			_pen_nib_buffed_uid = c.deck_uid
			_apply_pen_nib_buff_to_card(c)
			return


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
	_pl_log("sacrifice", {"card": victim.card_id, "lane": victim.current_lane,
		"row": victim.current_row})
	var lane: int = victim.current_lane
	if victim.has_method("mark_sacrifice_death"):
		victim.mark_sacrifice_death()
	spawn_keyword_callout_kw(victim, "sacrifice")
	spawn_ash_burst(_card_center(victim), Color(1.0, 0.30, 0.16), 18)
	screen_shake(5.0)
	if AudioBank != null:
		AudioBank.play_sfx("spell_cast", 0.04, -3.0, 0.72)
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


func summon_token(atk: int, hp: int, lane_idx: int, is_enemy: bool, row: int = ROW_FRONT,
		bequest: Dictionary = {}, token_name: String = "",
		extra_keywords: Array = []) -> void:
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
	var token_atk = atk
	if not is_enemy and _has_relic("conscription_relic"):
		token_hp += RelicDB.get_relic("conscription_relic").get("value", 1)
	# Sharpened Pitchforks: the player's 1/1 rabble muster as 2/1. Checked
	# against the REQUESTED statline so riders that fatten tokens (Conscription
	# HP, Standard Bearer) still count as "1/1 rabble" underneath.
	if not is_enemy and atk == 1 and hp == 1 and _has_relic("the_family"):
		token_atk += int(RelicDB.get_relic("the_family").get("value", 1))
	# Standard Bearer (token_lord): the banner musters every summoned token of
	# its side bigger — +1/+1 (+2/+2 upgraded). Strongest single bearer applies;
	# hooked here so every token path (Provision, War Chant, Necromancer, Old
	# Bones' risen, on-death summons) pays out identically.
	var tl_bonus := 0
	for tl in _all_friendly(is_enemy):
		if is_instance_valid(tl) and tl.card_data.get("passive", "") == "token_lord":
			tl_bonus = maxi(tl_bonus, 2 if bool(tl.card_data.get("is_upgraded", false)) else 1)
	token_atk += tl_bonus
	token_hp += tl_bonus
	var card = CARD_SCENE.instantiate()
	card.card_id = "token_%d_%d" % [token_atk, token_hp]
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.compact_mode = true
	card.card_data = {"id": card.card_id, "name": "Token", "type": "creature",
		"cost": 0, "atk": token_atk, "hp": token_hp, "keywords": [], "rarity": "enemy",
		"desc": "", "is_token": true}
	if not bequest.is_empty():
		# Old Bones: the risen body inherits a diminishing On-Death of its own,
		# so it keeps getting back up — one size smaller each time.
		card.card_data["on_death"] = bequest.duplicate(true)
		card.card_data["keywords"] = ["on_death"]
	# Named gifts (event/wayside/wake payoffs): the token wears the name it was
	# given — "Patent Ladder", not "Token" — and any promised keywords are real.
	# Keywords ride card_data.keywords, the same field every combat check reads
	# (Armored in take_damage, Swift in the pre-phase, Thorns on retaliation).
	if token_name != "":
		card.card_data["name"] = token_name
	for kw in extra_keywords:
		if not card.card_data["keywords"].has(kw):
			card.card_data["keywords"].append(kw)
	card.current_atk = token_atk
	card.current_hp = token_hp
	card.current_lane = lane_idx
	card.current_row = row
	field[lane_idx] = card
	var slot = _slot_array(is_enemy, row)[lane_idx]
	_slot_set_card(slot, card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	card.will_die.connect(_on_card_will_die.bind(card))
	# Linked Banner: a freshly-summoned friendly bumps neighbors' adjacency
	# counts. Re-scan so any ally that just hit 2+ adjacents gets +1 HP.
	if not is_enemy:
		_apply_linked_banner_hp()
	# A summoned body sits next to existing creatures — re-tally so it picks up any
	# adjacent Battle Drummer / Bannerman buff (and the numeral shows it).
	_refresh_adjacency_buffs()


## Griffin: float the just-dead creature back to the player's hand, ONCE per fight
## per card instance — independent of Grave Pact (which is a separate spell). Reads
## the dying card directly (the shared _last_dead_creature_* trackers are set AFTER
## on_death dispatch, so they'd point at the previous corpse). Pushes a proper
## "card_id#uid" entry so the returned card keeps its upgrades at draw time.
func _griffin_return_to_hand(card: Control) -> void:
	if card == null or card.is_token:
		return
	var uid: int = int(card.deck_uid)
	if uid < 0:
		return   # synthetic / tokenless bodies have no deck identity to return
	if _griffin_returned_uids.has(uid):
		return   # already came back once this fight
	_griffin_returned_uids[uid] = true
	_player_draw_pile.push_front(_pile_entry(card.card_id, uid))
	draw_one()


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
	title.text = "Exhaust a card for Command"
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
	if not state.picked.is_empty() and AudioBank != null:
		# Every caller discards the picks, and they vanish from hand instantly —
		# one paper-slip per batch marks the discard beat audibly.
		AudioBank.play_sfx("card_discard", 0.08, -6.0)
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
	# Net host's OWN Copycat: the initial play already board-synced (un-copied), so
	# push the copied body now that the pick is in (the client's own Copycat takes the
	# _net_client_show_choice path instead).
	if _is_host():
		_net_sync_board()


func _show_keyword_choice(target_card: Control) -> void:
	## Adaptable: modal overlay with 4 keyword buttons. The player's choice is
	## appended to the target card's keywords and a chip is spawned on it. In net the
	## host applies its OWN creature's pick here, then syncs it to the client (the
	## client's own Adaptable is handled via _net_client_show_choice → IN_CHOICE).
	if not is_instance_valid(target_card):
		return
	var kw: String = await _keyword_choice_overlay()
	if kw != "" and is_instance_valid(target_card):
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
		if _is_host():
			_net_sync_board()


## One option tile for the keyword / war-school modals — the game's chart-choice
## language (dark-ink panel, tan/accent rule, engraved keyword sigil, rules text)
## instead of a flat colored rectangle. Returns a PanelContainer with a full-tile
## click Button named "Click"; the caller wires .pressed. The sigil is a FIXED
## 48px (no SIZE_FILL stretch), so it never blows the tile out of shape.
func _keyword_pick_tile(label: String, accent: Color, desc: String,
		icon_path: String) -> PanelContainer:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(250, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.048, 0.040, 0.97)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.60)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	root.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vb)

	if ResourceLoader.exists(icon_path):
		var icon_box := Control.new()
		icon_box.custom_minimum_size = Vector2(48, 48)
		icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex: Texture2D = load(icon_path)
		for layer in range(2):
			var t := TextureRect.new()
			t.texture = tex
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.set_anchors_preset(Control.PRESET_FULL_RECT)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if layer == 0:
				for p in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
					t.set(p, 2.0)
				t.modulate = Color(0, 0, 0, 0.55)
			else:
				t.modulate = Color(accent.r, accent.g, accent.b, 0.92)
			icon_box.add_child(t)
		vb.add_child(icon_box)

	var name_lbl := Label.new()
	name_lbl.text = label
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", accent)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	desc_lbl.add_theme_color_override("font_color", Color(0.88, 0.84, 0.72))
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(desc_lbl)

	var click := Button.new()
	click.name = "Click"
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	for st in ["normal", "hover", "pressed", "focus"]:
		click.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	root.add_child(click)
	click.mouse_entered.connect(func(): root.modulate = Color(1.12, 1.10, 1.03))
	click.mouse_exited.connect(func(): root.modulate = Color.WHITE)
	return root


## Build the Adaptable keyword-choice modal and await the player's pick. Returns the
## chosen keyword key ("swift"/"piercing"/"armored"/"thorns") or "" if dismissed.
## Shared by the host/solo apply path (_show_keyword_choice) and the net CLIENT path
## (_net_client_show_choice), which sends the pick to the host instead of applying it.
func _keyword_choice_overlay() -> String:
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

	var sub := Label.new()
	sub.text = "Teach this soldier one keyword — for the rest of the fight."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", GameTheme.IVORY)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("outline_size", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var result := {"kw": ""}
	var options := [
		{"key": "swift", "label": "SWIFT", "color": Color(1.0, 0.85, 0.35)},
		{"key": "piercing", "label": "PIERCING", "color": Color(1.0, 0.62, 0.20)},
		{"key": "armored", "label": "ARMORED", "color": Color(0.65, 0.85, 1.0)},
		{"key": "thorns", "label": "THORNS", "color": Color(0.55, 0.85, 0.55)},
	]
	for opt in options:
		var kw_desc := String(KeywordEffects.KEYWORDS.get(opt.key, {}).get("desc", ""))
		var tile := _keyword_pick_tile(opt.label, opt.color, kw_desc,
			"res://assets/icons/keywords/%s.svg" % opt.key)
		tile.size_flags_vertical = Control.SIZE_FILL   # all four match the tallest
		tile.get_node("Click").pressed.connect(func():
			result["kw"] = opt.key
			overlay.queue_free()
		)
		row.add_child(tile)

	while result["kw"] == "" and is_instance_valid(overlay):
		await get_tree().process_frame
	return result["kw"]


# ── The war school (veterancy rung 3, campaign memory) ──────────────────────
# At VETERAN_SCHOOL_KILLS (10) a deck creature earns a CHOSEN keyword —
# Armored, Swift, or Thorns — written as a permanent "war_school" mod entry.
# The kill handler queues the uid; _start_round fires the offer at the top of
# the player phase. Solo campaign only (kills are only recorded solo).

var _war_school_queue: Array[int] = []

const WAR_SCHOOLS := [
	{"kw": "armored", "school": "THE LOW GUARD", "color": Color(0.18, 0.22, 0.30),
		"chip": Color(0.65, 0.85, 1.0)},
	{"kw": "swift", "school": "THE FIRST STEP", "color": Color(0.30, 0.26, 0.12),
		"chip": Color(1.0, 0.85, 0.35)},
	{"kw": "thorns", "school": "THE ANSWERED BLOW", "color": Color(0.20, 0.30, 0.18),
		"chip": Color(0.55, 0.85, 0.55)},
]


## Round-1 sweep: queue any deck creature at 10+ kills that never got its
## school — the threshold can be crossed on a fight's last kill (no next
## player phase to ask in), and pre-rung saves can carry old ten-kill heroes.
func _queue_war_school_catchup() -> void:
	for i in range(RunState.deck.size()):
		var uid: int = RunState.deck_uids[i] if i < RunState.deck_uids.size() else -1
		if uid < 0 or RunState.get_kills(uid) < RunState.VETERAN_SCHOOL_KILLS:
			continue
		if RunState.has_upgrade_path(i, "war_school"):
			continue
		if CardDB.get_card_data(RunState.deck[i]).get("type", "") != "creature":
			continue
		if not _war_school_queue.has(uid):
			_war_school_queue.append(uid)


## Drain the queue one veteran at a time. Async fire-and-forget from
## _start_round: the overlay blocks all input while the player phase idles.
func _offer_war_school() -> void:
	while not _war_school_queue.is_empty():
		var uid: int = _war_school_queue.pop_front()
		var idx: int = RunState.deck_uids.find(uid)
		if idx < 0 or RunState.has_upgrade_path(idx, "war_school"):
			continue
		var data: Dictionary = RunState.get_upgraded_card_data(idx)
		if data.get("type", "") != "creature":
			continue
		var have: Array = data.get("keywords", [])
		var schools: Array = []
		for s in WAR_SCHOOLS:
			if not have.has(s.kw):
				schools.append(s)
		if schools.is_empty():
			# Already carries all three — the rank is honorary, never re-asked.
			RunState.apply_wayside_upgrade(idx, {"path": "war_school", "keyword": ""})
			continue
		var pick: String
		if DisplayServer.get_name() == "headless":
			# Probe/autorun safety: an awaited overlay with nobody to click it
			# would hang the harness. Deterministic first-school pick instead.
			pick = String(schools[0].kw)
		else:
			pick = await _war_school_overlay(String(data.get("name", "The veteran")), schools)
		if pick == "":
			continue
		idx = RunState.deck_uids.find(uid)  # re-resolve: the await is long
		if idx < 0:
			continue
		RunState.apply_wayside_upgrade(idx, {"path": "war_school", "keyword": pick})
		# Promote the live body on the spot so the rung is felt THIS fight.
		for c in _all_player_creatures():
			if is_instance_valid(c) and int(c.deck_uid) == uid:
				if pick not in c.card_data.keywords:
					c.card_data.keywords.append(pick)
				for s in WAR_SCHOOLS:
					if String(s.kw) == pick and c.has_method("_spawn_keyword_chip"):
						c._spawn_keyword_chip(pick.to_upper(), s.chip)
				c.update_stat_display()


## The school-choice modal — same scaffold as the Adaptable overlay, but the
## buttons are the Pensioned Master's three schools and there is no dismiss:
## ten kills bought this choice, it will not be lost to a stray click.
func _war_school_overlay(veteran_name: String, schools: Array) -> String:
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
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "%s — 10 KILLS" % veteran_name.to_upper()
	title.add_theme_font_override("font", GameTheme.font_display)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := Label.new()
	sub.text = "Choose the war school. The lesson is permanent."
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", GameTheme.IVORY)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("outline_size", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var result := {"kw": ""}
	for s in schools:
		var school: Dictionary = s
		var disp := String(KeywordEffects.KEYWORDS.get(school.kw, {}) \
			.get("display", String(school.kw).capitalize()))
		var kw_desc := String(KeywordEffects.KEYWORDS.get(school.kw, {}).get("desc", ""))
		var accent: Color = school.get("chip", GameTheme.GILT_BRIGHT)
		var tile := _keyword_pick_tile(String(school.school),
			accent, "%s — %s" % [disp, kw_desc],
			"res://assets/icons/keywords/%s.svg" % school.kw)
		tile.custom_minimum_size = Vector2(262, 170)
		tile.size_flags_vertical = Control.SIZE_FILL
		tile.get_node("Click").pressed.connect(func():
			result["kw"] = String(school.kw)
			overlay.queue_free()
		)
		row.add_child(tile)

	while result["kw"] == "" and is_instance_valid(overlay):
		await get_tree().process_frame
	return result["kw"]


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
	card_node.live_baked_mode = true   # baked frame+art, live text (see _draw_card note)
	_hand_container.add_child(card_node)
	_hand.append(card_node)
	# Hook up the same signals draw_card connects — without these the card
	# sits in the hand but the played/dragging hooks are dead, so the player
	# can't actually use it. It gets swept into discard at end of round and
	# only becomes playable after the discard reshuffle, which was the user-
	# reported "teleports to a weird location, can't use, comes back later"
	# bug.
	card_node.played.connect(_on_card_played.bind(card_node))
	card_node.dismiss_requested.connect(_on_card_dismiss_requested.bind(card_node))
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
	# Skirmish has no RunState run to write back to, no reward/map flow, and the
	# match-over verdict is host-authoritative. Route to the net resolver instead
	# of the campaign victory/defeat path (which would advance the map & rewards).
	if _is_net():
		if _is_host():
			_net_host_check_match_over()
		return
	if player_hp <= 0:
		phase = Phase.GAME_OVER
		PlayLog.log_event("combat_end", {"encounter": _encounter_id,
			"result": "defeat", "round": round_number,
			"player_hp": 0, "enemy_hp": enemy_hp})
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
			AudioBank.duck_music(-8.0, 1.3)
			AudioBank.play_sfx("defeat")
		get_tree().create_timer(1.5).timeout.connect(func():
			RunState.end_run(false)
			GameTheme.fade_out_then_change_scene(self, GAMEOVER_SCENE, 0.5)
		)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		PlayLog.log_event("combat_end", {"encounter": _encounter_id,
			"result": "victory", "round": round_number,
			"player_hp": player_hp, "enemy_hp": 0})
		_stop_low_hp_dread()  # JUICE: clear dread overlay on victory
		_dbgp("[PACING] FIGHT END | %s | VICTORY | ended R%d | P_HP:%d E_HP:%d | intents_shown:%s" % [_encounter_name, round_number, player_hp, enemy_hp, str(_pacing_any_intent_shown)])
		# The banner + victory sting are DEFERRED ~0.45s (scheduled below, once
		# the gold line is known) so the killing blow's death burst and shake get
		# a held beat — they used to swap in the very frame the last creature died.
		var victory_banner := "VICTORY!"
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
		# Sellsword's Retainer — the surviving hireling collects his 10 gold.
		if _has_relic("sellswords_retainer"):
			for sw in _all_player_creatures():
				if is_instance_valid(sw) and sw.is_token \
						and String(sw.card_data.get("name", "")) == "Sellsword":
					RunState.gold = maxi(0, RunState.gold - 10)
					_show_info("The Sellsword collects his fee — 10 gold.")
					break
		# Thief's Gloves — "Win taking 0 face damage." Previously compared
		# player_hp to _starting_hp, which Vampire Lord / Mending Light / etc.
		# could mask by healing back to full despite taking real face damage.
		# Use the explicit counter so the relic does what it says.
		if _has_relic("thiefs_gloves") and _face_damage_taken_this_fight == 0:
			# The perfect raid: real gold + a head start on the next job. The
			# old 5g payout made an actual challenge worthless to chase.
			RunState.gain_gold(int(RelicDB.get_relic("thiefs_gloves").get("value", 15)))
			RunState.next_combat_mana_bonus += 1
			_show_info("Thief's Gloves — a clean job: +15 gold, +1 Command next fight.")
		# Gold reward — fights pay ground, not cards (Successor Wars Phase 4):
		# the card drip moved to recruit stops, so the gold base is bumped to
		# keep the shop a real deck-growth lever.
		var node_type = RunState.current_node_type
		var gold_won: int = 0
		match node_type:
			"combat": gold_won = RunState.roll_gold_reward(40)
			"elite": gold_won = RunState.roll_gold_reward(60)
			"boss": gold_won = RunState.roll_gold_reward(55)
		if gold_won > 0:
			RunState.gain_gold(gold_won)
			victory_banner = "VICTORY!  +%d gold" % gold_won
		# Spoils potion — StS-style drop with a pity ladder: 40% base, +10% per
		# dry fight, reset on a drop. Rolled only when a slot is free (no dead
		# rewards; can_add_potion also respects the Temperance Vow) and never
		# on the boss — the act transition pays its own way.
		if node_type in ["combat", "elite"] and RunState.can_add_potion():
			if randi() % 100 < 40 + RunState.potion_drop_misses * 10:
				var drop_pid: String = PotionDB.roll_random_potion()
				RunState.add_potion(drop_pid)
				RunState.potion_drop_misses = 0
				_show_info("Spoils: %s" % PotionDB.get_potion(drop_pid).get("name", drop_pid))
			else:
				RunState.potion_drop_misses += 1
		# Mutator bonus pays out here now (Reward no longer fronts normal
		# fights). Clear the id so a save/reload can't double-pay. Gated on
		# current_mutator_id so the Daily March omen (which fills EVERY fight
		# via _init_mutator_state's fallback) doesn't pay its bonus per fight —
		# only true node mutators front gold.
		if _mutator_id != "" and RunState.current_mutator_id != "" \
				and MutatorDB.exists(_mutator_id):
			var mut_bonus: int = int(MutatorDB.get_mutator(_mutator_id).get("gold_bonus", 0))
			if mut_bonus > 0:
				RunState.gain_gold(mut_bonus)
				_show_info("★ Mutator bonus: +%d gold" % mut_bonus)
			RunState.current_mutator_id = ""
		# Cursed Key: the curse lands on victory (used to ride the Reward roll).
		if RunState.has_downside("curse_on_reward"):
			RunState.add_card(CardDB.random_curse_id())

		# The held beat: banner text + sting land together after the final death
		# has breathed. Well inside the earliest scene fade (elite, 1.0s).
		get_tree().create_timer(0.45).timeout.connect(func():
			if is_instance_valid(_phase_label):
				_phase_label.text = victory_banner
				_phase_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
			if AudioBank != null:
				# Dip the combat track under the sting so the fanfare reads
				# over the music instead of fighting it.
				AudioBank.duck_music(-7.0, 1.1)
				AudioBank.play_sfx("victory")
		)

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
					# so Reward would render as a normal fight (no boss relic
					# offer). Reward handles the act advance after the player
					# finishes picking, on its way back to the map.
					GameTheme.fade_out_then_change_scene(self, REWARD_SCENE, 0.35)
			)
		elif node_type == "elite":
			# Elites still detour through Reward for their relic pick.
			get_tree().create_timer(1.0).timeout.connect(func():
				GameTheme.fade_out_then_change_scene(self, REWARD_SCENE, 0.35)
			)
		else:
			# Normal holds pay out inline and march straight back to the map —
			# no card pick, no interstitial screen. Pace is the point.
			get_tree().create_timer(1.2).timeout.connect(func():
				GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.35)
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
	## Renders an intent badge above enemies for non-default intents (CHARGE,
	## GUARD, RALLY, …). The default ATK case gets its own compact red down-chevron
	## via _update_attack_marker — so a plain attacker (by far the most common
	## case, and the one that used to telegraph NOTHING) now reads as "this will
	## swing," without re-printing the ATK-orb numeral that overlapped the art.
	_update_attack_marker(card, intent)
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
		# capture; a dark pill + bold 22px caps gives it a nameplate's presence
			# so this CHARGE / GUARD / RALLY telegraph reads from across the board.
			# (size set on the lbl just below)
		if GameTheme.font_display:
			lbl.add_theme_font_override("font", GameTheme.font_display)
		lbl.add_theme_font_size_override("font_size", 22)
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


func _update_attack_marker(card: Control, intent: String) -> void:
	## The default-attack telegraph: a small red down-chevron on every enemy that
	## will simply swing this turn — the case named-intent pills skip. Kept in its
	## own marker node so it never duplicates the ATK orb or the intent pill.
	var show_fang := (intent == "ATK" or intent == "")
	# Only flag a creature that can actually strike (skip stunned / 0-ATK / etc.).
	if show_fang and card.has_method("can_attack") and not card.can_attack():
		show_fang = false
	# The louder "⚔ N" threat badge already telegraphs this swing (with its number),
	# so a face-threat enemy carries ONE signal, not two stacked at its top edge.
	# The chevron is the quiet fallback for attackers the threat flag skips (a
	# blocked lane / a light hitter). _refresh_threat_flags re-syncs us on toggle.
	if show_fang and bool(card.get("_threat_flagged")):
		show_fang = false
	var m: Control = null
	if card.has_meta("atk_marker") and is_instance_valid(card.get_meta("atk_marker")):
		m = card.get_meta("atk_marker")
	if not show_fang:
		if m != null:
			m.visible = false
		return
	if m == null:
		m = _make_attack_fang()
		card.add_child(m)
		card.set_meta("atk_marker", m)
	m.visible = true


func _make_attack_fang() -> Control:
	## A down-pointing red chevron pinned to the enemy card's top edge. Drawn with
	## Polygon2D so it is font-independent (the UI font carries no ⚔/▼ glyph), and
	## small so eight of them never crowd the board.
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	holder.offset_left = -12
	holder.offset_right = 12
	holder.offset_top = -15
	holder.offset_bottom = 7
	holder.z_index = 6
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark backing chevron (slightly larger, drawn first → reads as an outline).
	var back := Polygon2D.new()
	back.polygon = PackedVector2Array([Vector2(-11, 0), Vector2(11, 0), Vector2(0, 15)])
	back.color = Color(0, 0, 0, 0.85)
	back.position = Vector2(12, 1)
	holder.add_child(back)
	# Crimson fill chevron.
	var tri := Polygon2D.new()
	tri.polygon = PackedVector2Array([Vector2(-8.5, 0), Vector2(8.5, 0), Vector2(0, 11.5)])
	tri.color = Color(0.93, 0.30, 0.26, 0.97)
	tri.position = Vector2(12, 1)
	holder.add_child(tri)
	return holder


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
					card.current_atk += victim.effective_atk()
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
				opp.card_data.erase("sniper")
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
					"rarity": "enemy",
					"keywords": effect.get("kw", []).duplicate(), "desc": "",
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
			# Drip reinforcements harden as the fight wears on. The round-N
			# double-place itself lives in _post_combat_sequence; this is the
			# later "they're sending tougher bodies now" tier.
			if round_number >= _esc_round(ESCALATION_REINFORCE_BUFF_ROUND):
				_reinforcement["atk"] = _reinforcement.get("atk", 1) + 1
				_reinforcement["hp"] = _reinforcement.get("hp", 1) + 1
		"elite":
			if round_number >= _esc_round(ESCALATION_ELITE_BUFF_ROUND):
				for c in _all_enemy_creatures():
					c.current_atk += 1
					c.update_stat_display()
		"boss":
			# Boss escalation handled by phase transitions
			# Auto-transition if stalled 10+ rounds in Phase 1
			if round_number >= _esc_round(ESCALATION_BOSS_STALL_ROUND) and _boss_current_phase == 0 and not _boss_phases.is_empty():
				_boss_current_phase = 1
				var phase_data = _boss_phases[1] if _boss_phases.size() > 1 else _boss_phases[0]
				_encounter_passive = phase_data.passive_id
				if phase_data.has("transition_msg"):
					_show_info(phase_data.transition_msg)
				# Mirror the normal HP-threshold transition: a stall-forced phase
				# change must still run the phase's board effect, or the player who
				# stalls in gets a half-applied (weaker) boss.
				if phase_data.has("transition_effect"):
					_execute_phase_transition(phase_data.transition_effect)


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
	# Online skirmish (v1) runs mutator-free — clear and bail so a leftover
	# campaign mutator can't arm enemy buffs in a net fight.
	if _is_net():
		_mutator_id = ""
		_mutator_data = {}
		return
	_mutator_id = RunState.current_mutator_id
	# Daily March: today's omen fills every fight that didn't roll its own
	# node mutator, so the whole run carries the day's weather. Node mutators
	# (and their gold bonus) still win when present.
	if _mutator_id == "" and RunState.is_daily_run \
			and MutatorDB.exists(RunState.daily_mutator_id):
		_mutator_id = RunState.daily_mutator_id
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
	# Altar start-of-round (Cultist Enclave's "Altar", the Owed's "Furnace
	# Altar"): the lowest-HP creature offers itself, adding +1 charge. At
	# charge 3 the altar climaxes: summon a champion AND deal 3 face damage.
	# Against the Owed the champion is "Paid in Full" — ledger language. The
	# sacrificed creature dies and triggers its on-death normally (e.g.
	# Bleeding Heart still bombs).
	var altar: Control = null
	for s in _all_structures():
		if String(s.card_data.get("name", "")) in ["Altar", "Furnace Altar"]:
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
		var is_owed: bool = _encounter_faction == "owed"
		if is_owed:
			_show_combat_banner("★ PAID IN FULL ★",
				"The ledger balances.", Color(0.85, 0.30, 0.95))
		else:
			_show_combat_banner("★ CHAMPION SUMMONED ★",
				"The Altar drinks deep.", Color(0.85, 0.30, 0.95))
		var burst_pos: Vector2 = altar.global_position + altar.size * altar.scale * 0.5
		spawn_spell_burst(burst_pos, Color(0.85, 0.30, 0.95, 0.95))
		screen_shake(12.0)
		screen_flash(Color(0.55, 0.18, 0.75, 0.30), 0.3)
		# Summon the champion in an empty front lane.
		var champion: Dictionary = EncounterDB.make_card_data({
			"name": "Paid in Full" if is_owed else "Cultist Champion",
			"atk": 5, "hp": 6,
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


## Show a spell card the player did NOT play by hand — Chaos Imp's random cast,
## an Echo / Inkpot copy, or (in skirmish) the OPPONENT's spell — as a real,
## READABLE card face, held center-screen for a beat. Before this, an auto-cast
## or a foe's spell only flashed its EFFECT, so "what did they even play?" was a
## mystery. The card's own effect resolves elsewhere; this is pure feedback, so
## the overlay is click-through (mouse-ignore) and never blocks the turn.
func _reveal_cast_card(card_data: Dictionary, caption: String,
		accent: Color = Color(0.96, 0.84, 0.40)) -> void:
	if _hud_layer == null or card_data.is_empty():
		return
	# Warm the shared bake cache so the live card below renders via the cheap
	# baked-frame path (random / opponent spells aren't in the run-deck pre-bake).
	# bake() is idempotent and awaits ~2 frames; on a miss the card falls back to a
	# full live render, so the face reads correctly either way.
	if CardTextureCache != null and not CardTextureCache.has(card_data):
		await CardTextureCache.bake(card_data)
	if _hud_layer == null or not is_instance_valid(_hud_layer):
		return   # combat torn down during the await
	var vp := get_viewport_rect().size
	var center := Vector2(vp.x * 0.5, vp.y * 0.45)

	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 250
	holder.modulate.a = 0.0
	_hud_layer.add_child(holder)

	# Soft radial pool of shadow so the card pops off the busy board (plain
	# alpha, no additive — it only darkens the backdrop, like the title scrim).
	var scrim_grad := Gradient.new()
	scrim_grad.offsets = PackedFloat32Array([0.0, 1.0])
	scrim_grad.colors = PackedColorArray([
		Color(0.02, 0.01, 0.01, 0.66), Color(0.02, 0.01, 0.01, 0.0)])
	var scrim_tex := GradientTexture2D.new()
	scrim_tex.gradient = scrim_grad
	scrim_tex.fill = GradientTexture2D.FILL_RADIAL
	scrim_tex.fill_from = Vector2(0.5, 0.5)
	scrim_tex.fill_to = Vector2(1.0, 0.9)
	scrim_tex.width = 256
	scrim_tex.height = 256
	var scrim := TextureRect.new()
	scrim.texture = scrim_tex
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw := 780.0
	var sh := 560.0
	scrim.position = center - Vector2(sw, sh) * 0.5
	scrim.size = Vector2(sw, sh)
	holder.add_child(scrim)

	# Caption above the card — who cast it / why it's appearing.
	var cap := _make_text_label(caption, 24, accent)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	cap.add_theme_constant_override("outline_size", 6)
	cap.size = Vector2(540, 36)
	cap.position = center + Vector2(-270, -212)
	holder.add_child(cap)

	# The card face — a full, LIVE Card2D, NOT a bare baked TextureRect. The shared
	# CardTextureCache bake intentionally strips the NAME and RULES TEXT (the hand
	# redraws them with the live font renderer so they stay razor-sharp at any zoom),
	# so painting the raw baked texture shows a frame + art with a BLANK banner and an
	# EMPTY rules box. That was the "spell text doesn't appear on the card" bug on the
	# skirmish OPPONENT-cast reveal (and on Chaos Imp / Echo casts in solo). A real
	# Card2D in the same baked-overlay mode the hand uses paints the frame/art from the
	# bake AND draws name + rules + stats live on top.
	var pic := CARD_SCENE.instantiate()
	pic.card_id = String(card_data.get("id", ""))
	pic.card_data = card_data.duplicate(true)
	pic.live_baked_mode = true   # baked frame+art + live text — identical to a hand card
	pic.static_display = true    # freeze per-frame animation in this transient overlay
	holder.add_child(pic)
	# Card2D._ready resets mouse_filter to STOP; force IGNORE *after* add_child so the
	# reveal never grabs hover/clicks (its mouse_entered isn't gated on static_display).
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Card2D is natively 225×300. Centre it on `center` (scale about its own centre via
	# pivot_offset) and blow it up slightly to the lifted-hand reveal size.
	var reveal_scale := 1.10
	pic.pivot_offset = Vector2(112.5, 150.0)
	pic.position = center - Vector2(112.5, 150.0)
	# Pop the card in with a small back-eased scale as the holder fades up.
	pic.scale = Vector2(reveal_scale * 0.80, reveal_scale * 0.80)
	var ptw := pic.create_tween()
	ptw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ptw.tween_property(pic, "scale", Vector2(reveal_scale, reveal_scale), 0.26)

	var tw := holder.create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.15)
	tw.tween_property(holder, "modulate:a", 0.0, 0.40)
	tw.tween_callback(holder.queue_free)


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

## A unit station drawn ON the war chart: corner brackets, a hairline
## rule, a faint ownership wash, and a small center cross — positions
## marked on the map, not holes carved into it. Replaces the old full-size
## dark wells, which covered nearly the whole table and turned the board
## into 16 voids. The drawn marks stay quiet when empty and disappear
## behind a creature when filled; Highlight/ContactShadow/Cell (the slot's
## behavioral children) are untouched.
class StationMark extends Control:
	var warm := true       # enemy half (warm) vs player half (cool) wash
	var strong := true     # front row reads stronger than back

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x < 20.0 or size.y < 20.0:
			return
		# Front and back rows now read as TWO DISTINCT station kinds rather than
		# the same mark at two opacities — the old back-row a_mul=0.62 just made
		# the rear line fade into the dark table. Front = a solid mustered post
		# (filled bracket corners, full wash, survey cross). Back = a reserve
		# bay drawn the same strength but as a dashed inset frame, so it reads as
		# "staging ground, not the firing line" by SHAPE, not by faintness.
		# Both are emphatic enough to parse the whole 4×4 grid before a fight.
		var wash := Color(0.52, 0.15, 0.10, 0.20) if warm \
			else Color(0.14, 0.27, 0.48, 0.20)
		var ink := Color(0.84, 0.68, 0.40)   # gilt rule ink
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), wash, true)
		# Hairline inset rule — the station footprint.
		draw_rect(Rect2(Vector2(3.5, 3.5), size - Vector2(7, 7)),
			Color(ink.r, ink.g, ink.b, 0.35), false, 1.0, true)
		if strong:
			# FRONT — corner brackets, the drawn firing-line post.
			var bk := Color(ink.r, ink.g, ink.b, 0.85)
			var L := 17.0
			for cx in [0.0, 1.0]:
				for cy in [0.0, 1.0]:
					var corner := Vector2(cx * size.x, cy * size.y)
					var dx := 1.0 if cx == 0.0 else -1.0
					var dy := 1.0 if cy == 0.0 else -1.0
					draw_line(corner + Vector2(0, dy * 1.5),
						corner + Vector2(dx * L, dy * 1.5), bk, 2.5, true)
					draw_line(corner + Vector2(dx * 1.5, 0),
						corner + Vector2(dx * 1.5, dy * L), bk, 2.5, true)
			# Survey cross — where this unit will stand.
			var c := size * 0.5
			var fc := Color(ink.r, ink.g, ink.b, 0.30)
			draw_line(c - Vector2(9, 0), c + Vector2(9, 0), fc, 1.5, true)
			draw_line(c - Vector2(0, 9), c + Vector2(0, 9), fc, 1.5, true)
		else:
			# BACK — a dashed reserve bay. Same ink weight as the front so it
			# stays legible, but the broken line says "staging, not line".
			var dash := Color(ink.r, ink.g, ink.b, 0.55)
			var rect := Rect2(Vector2(7, 7), size - Vector2(14, 14))
			var step := 11.0
			# Top + bottom dashed edges.
			var x := rect.position.x
			while x < rect.end.x:
				var x2: float = minf(x + 6.0, rect.end.x)
				draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), dash, 1.5, true)
				draw_line(Vector2(x, rect.end.y), Vector2(x2, rect.end.y), dash, 1.5, true)
				x += step
			# Left + right dashed edges.
			var y := rect.position.y
			while y < rect.end.y:
				var y2: float = minf(y + 6.0, rect.end.y)
				draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, y2), dash, 1.5, true)
				draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, y2), dash, 1.5, true)
				y += step


## The war-table surface: a faded campaign chart inked straight onto the
## scorched table the battle is fought across — a double-ruled coast with
## sea hatching, dashed march routes, site rings, a compass, cup stains,
## and the burn creeping in along the clash band and the edges (heavier in
## later acts: the war eats the map). Seeded per encounter+act, so every
## fight's table is its own document but stable across rebuilds. Drawn
## once; static — sits between the dark substrate and the lane tracks.
class TablePlate extends Control:
	var seed_text := "table"
	var act := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _coast_y(t: float, y0: float, amp: float, ph1: float, ph2: float) -> float:
		return y0 + sin(t * 4.2 + ph1) * amp * 0.55 + sin(t * 9.7 + ph2) * amp * 0.30

	func _draw() -> void:
		if size.x < 80.0 or size.y < 80.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_text)
		var ink := Color(0.74, 0.58, 0.34)
		# 1 — the coast: a double-ruled wandering line (the chart idiom).
		var ph1 := rng.randf() * TAU
		var ph2 := rng.randf() * TAU
		var y0 := size.y * (0.30 + rng.randf() * 0.40)
		var amp := size.y * 0.14
		var coast := PackedVector2Array()
		var n := 26
		for i in range(n + 1):
			var t := float(i) / float(n)
			coast.append(Vector2(t * size.x, _coast_y(t, y0, amp, ph1, ph2)))
		draw_polyline(coast, Color(ink.r, ink.g, ink.b, 0.15), 2.2, true)
		var coast2 := PackedVector2Array()
		for p in coast:
			coast2.append(p + Vector2(0, 6))
		draw_polyline(coast2, Color(ink.r, ink.g, ink.b, 0.09), 1.1, true)
		# Sea hatching seaward of the coast.
		for i in range(26):
			var t := rng.randf()
			var hy := _coast_y(t, y0, amp, ph1, ph2) + 12.0 + rng.randf() * 46.0
			if hy > size.y - 8.0:
				continue
			draw_line(Vector2(t * size.x, hy),
				Vector2(t * size.x + 10.0 + rng.randf() * 8.0, hy),
				Color(ink.r, ink.g, ink.b, 0.055 + rng.randf() * 0.04), 1.0, true)
		# 2 — march routes: two dashed tracks wandering across the land.
		for r in range(2):
			var ry := size.y * (0.12 + rng.randf() * 0.66)
			var rph := rng.randf() * TAU
			var seg_on := true
			var x := rng.randf() * 40.0
			while x < size.x - 12.0:
				var x2 := minf(x + 14.0, size.x - 8.0)
				if seg_on:
					var ya := ry + sin(x / size.x * 5.0 + rph) * size.y * 0.05
					var yb := ry + sin(x2 / size.x * 5.0 + rph) * size.y * 0.05
					draw_line(Vector2(x, ya), Vector2(x2, yb),
						Color(ink.r, ink.g, ink.b, 0.115), 1.4, true)
				seg_on = not seg_on
				x = x2
		# 3 — site rings: held positions marked on the chart.
		for i in range(5):
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			draw_arc(p, 4.0 + rng.randf() * 5.0, 0, TAU, 18,
				Color(ink.r, ink.g, ink.b, 0.13), 1.2, true)
			draw_circle(p, 1.2, Color(ink.r, ink.g, ink.b, 0.16), true, -1.0, true)
		# 4 — compass cross, upper-right quadrant.
		var cp := Vector2(size.x * (0.74 + rng.randf() * 0.16),
			size.y * (0.12 + rng.randf() * 0.14))
		var cr := 16.0 + rng.randf() * 8.0
		draw_arc(cp, cr, 0, TAU, 26, Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
		draw_line(cp + Vector2(0, -cr * 1.45), cp + Vector2(0, cr * 1.45),
			Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
		draw_line(cp + Vector2(-cr * 1.45, 0), cp + Vector2(cr * 1.45, 0),
			Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
		# 5 — cup ring stains: someone set their drink on the orders.
		for i in range(2):
			var sp := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var a0 := rng.randf() * TAU
			draw_arc(sp, 13.0 + rng.randf() * 9.0, a0, a0 + TAU * 0.8, 30,
				Color(0.30, 0.20, 0.10, 0.10), 2.6, true)
		# 6 — the burn: scorch along the clash band + creeping from the
		# top/bottom edges; later acts burn hotter.
		var burn := Color(0.04, 0.02, 0.012)
		for i in range(7 + act * 3):
			var bp: Vector2
			if rng.randf() < 0.55:
				bp = Vector2(rng.randf() * size.x,
					size.y * 0.5 + (rng.randf() - 0.5) * size.y * 0.16)
			else:
				bp = Vector2(rng.randf() * size.x,
					size.y * (0.04 + 0.92 * float(rng.randi() % 2)) \
					+ (rng.randf() - 0.5) * size.y * 0.07)
			var br := 14.0 + rng.randf() * 34.0
			draw_circle(bp, br, Color(burn.r, burn.g, burn.b,
				0.09 + rng.randf() * 0.11), true, -1.0, true)
			draw_circle(bp, br * 0.55, Color(burn.r, burn.g, burn.b,
				0.08 + rng.randf() * 0.10), true, -1.0, true)


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
	# Lamplit wood-brown, near-opaque. The play surface must sit VISIBLY
	# lighter than the dark room around it (the Hearthstone value structure)
	# — at the old 0.05 near-black the table and the void were one tone and
	# the whole midscreen read empty.
	sub_style.bg_color = Color(0.118, 0.088, 0.062, 0.96)
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

	# ── The war table itself ────────────────────────────────────────────────
	# The bare substrate read as a void between the HUD edges. Dress it as the
	# campaign table the war is being run from: wood grain, a faded chart of
	# the theater inked straight on it, and a quiet bronze fillet — the same
	# furniture language as the cards and the map plate. All static, all
	# under the lanes, so it costs nothing per frame.
	if GameTheme.tex_card_wood_grain:
		var wood := TextureRect.new()
		wood.texture = GameTheme.tex_card_wood_grain
		wood.stretch_mode = TextureRect.STRETCH_TILE
		wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wood.set_anchors_preset(Control.PRESET_FULL_RECT)
		wood.offset_left = 6
		wood.offset_top = 6
		wood.offset_right = -6
		wood.offset_bottom = -6
		wood.modulate = Color(0.78, 0.56, 0.34, 0.22)
		wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_zone.add_child(wood)
	if GameTheme.tex_card_grain:
		var fiber := TextureRect.new()
		fiber.texture = GameTheme.tex_card_grain
		fiber.stretch_mode = TextureRect.STRETCH_TILE
		fiber.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fiber.set_anchors_preset(Control.PRESET_FULL_RECT)
		fiber.offset_left = 6
		fiber.offset_top = 6
		fiber.offset_right = -6
		fiber.offset_bottom = -6
		fiber.modulate = Color(0.55, 0.40, 0.24, 0.10)
		fiber.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_zone.add_child(fiber)
	var chart := TablePlate.new()
	chart.clip_contents = true
	chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart.offset_left = 6
	chart.offset_top = 6
	chart.offset_right = -6
	chart.offset_bottom = -6
	chart.seed_text = "%s_act%d" % [String(RunState.current_encounter_id),
		RunState.get_act()]
	chart.act = RunState.get_act()
	board_zone.add_child(chart)
	var table_fillet := Panel.new()
	table_fillet.set_anchors_preset(Control.PRESET_FULL_RECT)
	table_fillet.offset_left = 4
	table_fillet.offset_top = 4
	table_fillet.offset_right = -4
	table_fillet.offset_bottom = -4
	table_fillet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fillet_st := StyleBoxFlat.new()
	fillet_st.draw_center = false
	fillet_st.border_color = Color(GILT.r, GILT.g, GILT.b, 0.16)
	fillet_st.set_border_width_all(1)
	fillet_st.set_corner_radius_all(12)
	table_fillet.add_theme_stylebox_override("panel", fillet_st)
	board_zone.add_child(table_fillet)

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
		track_style.bg_color = Color(0.015, 0.012, 0.01, 0.14)
		# Stronger lane keylines so the four columns read as distinct lanes at a
		# glance — at 0.08 the dividers vanished against the dark table and the
		# board looked like one undifferentiated field. The side borders carry
		# the column read; top/bottom stay hairline.
		track_style.border_color = Color(GILT.r, GILT.g, GILT.b, 0.22)
		track_style.border_width_left = 2
		track_style.border_width_right = 2
		track_style.border_width_top = 1
		track_style.border_width_bottom = 1
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
	# (lands in each column's CLASH_GAP). A charred furrow under a crisp lit
	# gilt seam — the front has burned itself into the table. It only crosses
	# the empty gap between the front rows, so it never overlaps a card.
	var furrow := Panel.new()
	furrow.anchor_left = 0.0
	furrow.anchor_right = 1.0
	furrow.anchor_top = 0.5
	furrow.anchor_bottom = 0.5
	furrow.offset_top = -7
	furrow.offset_bottom = 7
	furrow.offset_left = 10
	furrow.offset_right = -10
	furrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fur_st := StyleBoxFlat.new()
	fur_st.bg_color = Color(0.015, 0.008, 0.004, 0.55)
	fur_st.set_corner_radius_all(5)
	furrow.add_theme_stylebox_override("panel", fur_st)
	board_zone.add_child(furrow)
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

	# Successor Wars rival lords — each voiced by the island age his kingdom
	# channels (the horse-conquest, the legion, the merchant-god city, the
	# geometer's city, the liquid fire). Throne amalgams reuse these via the
	# amalgam_ → rival_ fallback in _pick_bark.
	"rival_raider": {
		"enter": "I came over the water with nothing. Look at everything you have brought me.",
		"hurt": ["A toll. Every road has one.", "I have been unhorsed before. I land riding."],
		"phase": "EVERY OPEN GATE IS MINE.",
		"slay": "Your land now. It was always going to be somebody's.",
	},
	"rival_stalwart": {
		"enter": "You are not the first to reach this wall. You are not even this morning's first.",
		"hurt": ["The line holds.", "Close the rank. Step over him."],
		"phase": "CLOSE RANKS.",
		"slay": "Stand down. The wall stands.",
	},
	"rival_acolyte": {
		"enter": "Sit. The ledger has a line for you — it has had one for years.",
		"hurt": ["Noted.", "An expense. It will be recouped."],
		"phase": "ALL ACCOUNTS COME DUE.",
		"slay": "Paid in full.",
	},
	"rival_pyromancer": {
		"enter": "I measured this fight last winter. Proceed.",
		"hurt": ["Within tolerance.", "An error of one degree. Corrected."],
		"phase": "NOW THE MIRRORS TURN.",
		"slay": "Do not disturb my circles.",
	},
	"rival_kindler": {
		"enter": "You came for the recipe. It is not written down. It is poured.",
		"hurt": ["Feed it to the fire.", "It burns on water. What were you hoping?"],
		"phase": "NOW IT POURS.",
		"slay": "Burn gently. You were kindling all along.",
	},
}


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
	if bset.is_empty():
		# Throne amalgams speak with their lord's rival-kit voice.
		bset = PRESENCE_BARKS.get(_encounter_id.replace("amalgam_", "rival_"), {})
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

	# Station drawn ON the chart — corner brackets + hairline + faint
	# ownership wash + survey cross (see StationMark). The old carved wells
	# were full-size dark fills: with 16 of them they COVERED the table and
	# the board read as a grid of voids — the user's "still dark and empty".
	# A lane game needs the 16 stations readable, but readable means marked,
	# not excavated: the table material now runs continuously underneath.
	var station := StationMark.new()
	station.name = "Station"
	station.set_anchors_preset(Control.PRESET_FULL_RECT)
	station.warm = is_enemy
	station.strong = row == ROW_FRONT
	# Stations rest dim: 16 full-ink marks made an empty round-1 board read as
	# a spreadsheet of dashed boxes. Player-side marks wake to full ink while a
	# drag is in the play zone (_set_stations_lit) — the mark's DESIGN is
	# untouched, only its resting weight.
	station.modulate.a = STATION_REST_ALPHA
	slot.add_child(station)

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
	# A new creature changes adjacency — re-tally so it gets/grants the buff and
	# the numerals (its own + its neighbours') update with a "+N ATK" pop.
	_refresh_adjacency_buffs()


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

		# Landing = the wax press (squash + impression ring + release). It
		# re-arms the idle bob itself when the press settles.
		if card.has_method("play_wax_press"):
			card.play_wax_press(rest_scale)
	else:
		# Drop-in entrance (enemy placements / repositions): arrive slightly
		# large, then the shared wax press stamps it onto the board.
		card.scale = rest_scale * 1.22
		if card.has_method("play_wax_press"):
			card.play_wax_press(rest_scale)


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
	# Reborn on_death: card resurrects at full HP once per fight (revenant's
	# identity — a sticky body, vs griffin's flexible return-to-hand).
	var od: Dictionary = card.card_data.get("on_death", {})
	if od.get("type", "") == "reborn" and not card.get_meta("reborn_used", false):
		card.set_meta("reborn_used", true)
		card.current_hp = maxi(1, int(card.card_data.get("hp", 1)))
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

	# NET: record the last corpse on each OWNER side (host POV: was_enemy → client
	# side 1, else host side 0) so the caster-side resurrection spells reach the
	# right grave, and honour Grave Pact (the armed side's next real death floats
	# back to that caster's hand). Host-authoritative; solo is untouched.
	if _is_host():
		var owner_side: int = 1 if was_enemy else 0
		_net_last_dead[owner_side] = {
			"id": card.card_id, "uid": int(card.deck_uid),
			"data": card.card_data.duplicate(true),
		}

	# JUICE — register this death for the coalesced "notable kill" hit-stop so a
	# multi-creature wipe or a chunky bruiser dying lands with weight.
	_note_death(card, was_enemy)

	# The slot arrays were nulled above — re-tally adjacency so neighbours of the
	# fallen card lose its buff immediately (any on_death summon below re-tallies).
	_refresh_adjacency_buffs()

	# The Coin, Landed (event relic): every fall pays, either side of the
	# field. Structures are furniture, not dead — they don't flip the coin.
	if _has_relic("coin_landed") and not card.has_keyword("structure"):
		RunState.gain_gold(int(RelicDB.get_relic("coin_landed").get("value", 2)))

	# Snapshot enemy data so on_death effects that look up "last dead enemy"
	# see the freshly-dead card (Doppelganger, Phoenix Feather).
	if was_enemy:
		_last_dead_enemy_data = card.card_data.duplicate(true)
		# Successor Wars (the Owed): every fallen enemy banks a deposit that
		# the wave schedule collects at end of round. Structures are
		# furniture, not dead. Refreshing the chip here keeps the visible
		# corpse-count live as the round plays out.
		if _wave_schedule_active and bool(_wave_schedule().get("collect", false)) \
				and not card.has_keyword("structure"):
			_wave_deaths_banked += 1
			_update_wave_telegraph()

	# Fire on_death effects. dispatch_on_death handles its own doubling for
	# the player passive "double_on_death" / "Frenzied" mutator. Pass row so
	# damage_adjacent hits only the dead creature's own row (not both).
	KeywordEffects.dispatch_on_death(card, lane, was_enemy, self, row)

	# Encounter-specific death hooks (Pyre/Mausoleum/Trebuchet charge feeds,
	# Wolf pack revenge, Necromancer summon, etc.).
	if was_enemy:
		_enemy_deaths_this_fight += 1
		_dispatch_encounter_on_enemy_death(lane, card)
		# The Apothecary (plague_doctor): a friendly turns every enemy death into a
		# clock — deal damage to the dead foe's hero. (poison kills, AoE, Doom, and
		# ordinary trades all feed it.)
		_apply_plague_doctor(true)
	else:
		_on_friendly_death(card, lane)
		_dispatch_encounter_on_player_death(lane)
	# NET mirror: the client's side gets the same death payoffs from its perspective —
	# its allies' deaths grow/drain ITS passives, and its apothecaries profit when a
	# host creature falls. Solo never enters here (player-side handled above).
	if _is_net():
		if was_enemy:
			# Count the client's death for its own Gravedigger cap before the payoffs
			# read it (mirrors _on_friendly_death incrementing before its false call).
			_enemy_deaths_this_round += 1
			_apply_ally_death_passives(true, card)
		else:
			_apply_plague_doctor(false)

	# Reactive passive (ON_CREATURE_DEATH triggers — Necromancer Tower's
	# double_on_death, etc.).
	_dispatch_reactive("ON_CREATURE_DEATH", card, lane)

	# Rear Guard Charm relic: a front-row friendly death buffs the back-row
	# column-mate +1/+1 permanently. Side-aware + host-authoritative in net (the
	# owner's own Charm fires for the owner's side and rides the board snapshot);
	# in solo only the player side owns it, so was_enemy=true resolves to false.
	if row == ROW_FRONT and _relic_active_for_side(was_enemy, "rear_guard_charm"):
		var back_mate = _row_array(was_enemy, ROW_BACK)[lane]
		if back_mate != null and is_instance_valid(back_mate) and back_mate.current_hp > 0:
			back_mate.current_atk += 1
			back_mate.card_data["hp"] = int(back_mate.card_data.get("hp", 0)) + 1
			back_mate.current_hp += 1
			back_mate.update_stat_display()

	# Stygian Soul: heal 1 HP per enemy death, capped at 5 per combat.
	if was_enemy and _has_relic("stygian_soul"):
		var cap: int = int(RelicDB.get_relic("stygian_soul").get("value", 5))
		if _stygian_soul_healed < cap:
			_stygian_soul_healed += 1
			var sty_before: int = player_hp
			RunState.heal_hero(1)
			player_hp = RunState.hero_hp
			if player_hp > sty_before:
				_stoke_acolytes(false)

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

	# Resonance Crystal relic: first keyword-bearing creature death this fight
	# propagates ONE of its combat keywords to every surviving friendly. We
	# pick the first matching keyword (stable across runs of the same fight)
	# and only spread keywords that actually do something in combat —
	# spreading "on_enter" or "floop" would be visual noise.
	if _has_relic("resonance_crystal") and not _resonance_crystal_used_this_fight and not card.is_opponent:
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
	# Swap only the per-slot glow here — NOT _clear_slot_highlights(), which
	# also rests the station marks and would flicker them on every lane change
	# mid-drag. The stations stay lit for the whole in-zone stretch.
	if _highlighted_slot != null and is_instance_valid(_highlighted_slot):
		_set_slot_highlight(_highlighted_slot, false)
	_set_slot_highlight(slot, true)
	_highlighted_slot = slot
	_set_stations_lit(true)


func _clear_slot_highlights() -> void:
	if _highlighted_slot != null and is_instance_valid(_highlighted_slot):
		_set_slot_highlight(_highlighted_slot, false)
	_highlighted_slot = null
	_set_stations_lit(false)


const STATION_REST_ALPHA := 0.62
var _stations_lit: bool = false

func _set_stations_lit(lit: bool) -> void:
	# Wakes the player-side station marks to full ink while a drag sits in the
	# play zone (they're the drop targets), and lets them rest dim otherwise.
	# Guarded so the per-frame drag handler never re-tweens.
	if _stations_lit == lit:
		return
	_stations_lit = lit
	for row in [ROW_FRONT, ROW_BACK]:
		for slot in _slot_array(false, row):
			if slot == null or not is_instance_valid(slot):
				continue
			var station: Control = slot.get_node_or_null("Station") as Control
			if station != null:
				var tw: Tween = station.create_tween()
				tw.tween_property(station, "modulate:a",
					1.0 if lit else STATION_REST_ALPHA, 0.12)


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


func _on_field_move_dropped(global_pos: Vector2, card: Control) -> void:
	# Param order matters: the signal emits global_pos and .bind(card)
	# APPENDS the card — (signal args..., bound args). The reversed
	# signature hard-errored on arg conversion, the handler never ran, and
	# every field move stranded its creature on the hand layer at the raw
	# drop position (the "played cards end up in Timbuktu" bug).
	if not is_instance_valid(card):
		return
	_clear_slot_highlights()
	if _is_net():
		_net_field_move_dropped(global_pos, card)
		return
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
			# Drover's Whip: the moved creature arrives angry — +1 ATK this round.
			if _has_relic("drovers_whip"):
				var whip: int = int(RelicDB.get_relic("drovers_whip").get("value", 1))
				card.temp_atk_buff += whip
				card.update_stat_display()
				spawn_floating_number(_card_center(card) + Vector2(0, -14),
					"DROVER'S WHIP +%d" % whip, Color(1.0, 0.72, 0.35), false)
			_play_landing_pop(card)
			if AudioBank != null:
				AudioBank.play_sfx("card_play")
			moved = true
			# Moving a creature re-shapes both the vacated and the new neighbourhood —
			# re-tally adjacency for everyone affected.
			_refresh_adjacency_buffs()
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
	# The lift turned the idle bob off (it owns position.y). This path has no landing
	# pop to re-arm it, so re-anchor it to the re-centered slot next frame.
	if card.has_method("rearm_idle_bob_next_frame"):
		card.rearm_idle_bob_next_frame()


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
	_build_emote_button()
	_build_settings_gear_button()
	_build_targeting_arrow()
	_build_combat_telegraph()

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
	_build_battle_log()


# ═══════════════════════════════════════════
#  BATTLE LOG — the fight's chronicle (Hearthstone-style history feed)
# ═══════════════════════════════════════════
#
# A collapsible drawer on the left edge. Every meaningful beat — plays,
# strikes, deaths, face damage, keyword pops, potions — lands as one BBCode
# line via _log_event; the first event of each round stamps a divider first.
# Closed by default (combat space is precious); the tab pulses when lines
# arrive unseen so the player knows the chronicle is being written.

func _build_battle_log() -> void:
	# The drawer — left edge, vertically centred, above the board plates.
	_battle_log_panel = PanelContainer.new()
	_battle_log_panel.name = "BattleLogPanel"
	var pstyle := GameTheme.make_panel_style(
		Color(0.075, 0.058, 0.045, 0.94), Color(0.60, 0.51, 0.34, 0.90), 1, 4, true)
	pstyle.content_margin_left = 12
	pstyle.content_margin_right = 8
	pstyle.content_margin_top = 8
	pstyle.content_margin_bottom = 10
	_battle_log_panel.add_theme_stylebox_override("panel", pstyle)
	# Top-left drawer, opening DOWN over the pile/relic rail (static info the
	# player can re-glance after closing) rather than over the board or hand.
	_battle_log_panel.anchor_left = 0.0
	_battle_log_panel.anchor_right = 0.0
	_battle_log_panel.anchor_top = 0.0
	_battle_log_panel.anchor_bottom = 0.0
	_battle_log_panel.offset_left = 10
	_battle_log_panel.offset_right = 346
	_battle_log_panel.offset_top = 124
	_battle_log_panel.offset_bottom = 574
	_battle_log_panel.z_index = 80
	_battle_log_panel.visible = false
	_hud_layer.add_child(_battle_log_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_battle_log_panel.add_child(col)

	var header := _make_rail_caption("BATTLE LOG")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(header)

	_battle_log_scroll = ScrollContainer.new()
	_battle_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_battle_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_battle_log_scroll)

	_battle_log_list = VBoxContainer.new()
	_battle_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_log_list.add_theme_constant_override("separation", 2)
	_battle_log_scroll.add_child(_battle_log_list)

	# The tab — always visible, pinned just above the drawer so open/closed
	# reads as one instrument. Quill glyph + word, rail-caption voice.
	_battle_log_tab = Button.new()
	_battle_log_tab.name = "BattleLogTab"
	_battle_log_tab.text = "LOG"
	_battle_log_tab.focus_mode = Control.FOCUS_NONE
	_battle_log_tab.add_theme_font_size_override("font_size", 18)
	_battle_log_tab.add_theme_color_override("font_color", GILT)
	_battle_log_tab.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.70))
	_battle_log_tab.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.70))
	_battle_log_tab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_battle_log_tab.add_theme_constant_override("outline_size", 4)
	if GameTheme.font_title != null:
		var fv := FontVariation.new()
		fv.base_font = GameTheme.font_title
		fv.spacing_glyph = 2
		_battle_log_tab.add_theme_font_override("font", fv)
	var tstyle := GameTheme.make_panel_style(
		Color(0.10, 0.062, 0.046, 0.94), Color(0.60, 0.51, 0.34, 0.90), 1, 4, true)
	tstyle.content_margin_left = 12
	tstyle.content_margin_right = 12
	tstyle.content_margin_top = 4
	tstyle.content_margin_bottom = 4
	var thover := GameTheme.make_panel_style(
		Color(0.14, 0.095, 0.062, 0.96), Color(0.72, 0.61, 0.40, 1.0), 1, 4, true)
	thover.content_margin_left = 12
	thover.content_margin_right = 12
	thover.content_margin_top = 4
	thover.content_margin_bottom = 4
	_battle_log_tab.add_theme_stylebox_override("normal", tstyle)
	_battle_log_tab.add_theme_stylebox_override("hover", thover)
	_battle_log_tab.add_theme_stylebox_override("pressed", thover)
	_battle_log_tab.add_theme_stylebox_override("focus", tstyle)
	# Above the deck pile, below the settings gear — the one clear pocket on
	# the left rail (the mid-rail spot collided with the gold chip).
	_battle_log_tab.anchor_left = 0.0
	_battle_log_tab.anchor_right = 0.0
	_battle_log_tab.anchor_top = 0.0
	_battle_log_tab.anchor_bottom = 0.0
	_battle_log_tab.offset_left = 10
	_battle_log_tab.offset_right = 108
	_battle_log_tab.offset_top = 84
	_battle_log_tab.offset_bottom = 118
	_battle_log_tab.z_index = 81
	_battle_log_tab.pressed.connect(_toggle_battle_log)
	_hud_layer.add_child(_battle_log_tab)


func _toggle_battle_log() -> void:
	_battle_log_open = not _battle_log_open
	if _battle_log_panel != null and is_instance_valid(_battle_log_panel):
		_battle_log_panel.visible = _battle_log_open
	if _battle_log_open:
		_scroll_log_to_bottom()
	if AudioBank != null:
		AudioBank.play_sfx("button_click")


## One chronicle line. `bb` is BBCode (names pre-tinted via _log_card_ref).
## `data` is the card behind the beat — its art becomes the entry's thumbnail
## and hovering the entry shows the full card beside the drawer (Hearthstone
## history). `side` tints the thumbnail rim: 0 = yours (gilt), 1 = the foe's
## (ember), -1 = neutral bronze. `icon_override`/`icon_tint` swap the art for
## a non-card glyph (potions). Stamps a "— ROUND N —" divider before the
## first event of each round.
func _log_event(bb: String, data: Dictionary = {}, side: int = -1,
		icon_override: Texture2D = null, icon_tint: Color = Color.WHITE) -> void:
	if _battle_log_list == null or not is_instance_valid(_battle_log_list):
		return
	# Solo tracks round_number; net's turn machine tracks _net_turn_round (synced to
	# both peers via EV_TURN_BEGIN) — read the right one so the dividers advance on
	# the client too, not just the host.
	var rn: int = _net_turn_round if _is_net() else round_number
	if rn != _battle_log_round_marked:
		_battle_log_round_marked = rn
		if rn >= 1:
			_append_log_divider("— ROUND %d —" % rn)
		else:
			# Events before round 1 are the opening deal — the muster, not a round.
			_append_log_divider("— THE LINES FORM —")
	_append_log_line(bb, data, side, icon_override, icon_tint)
	if not _battle_log_open:
		_pulse_log_tab()


func _make_log_text(bb: String) -> RichTextLabel:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_size_override("normal_font_size", 16)
	if GameTheme.font_body != null:
		lbl.add_theme_font_override("normal_font", GameTheme.font_body)
	lbl.add_theme_color_override("default_color", Color(0.83, 0.78, 0.68))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = bb
	return lbl


func _append_log_divider(text: String) -> void:
	var lbl := _make_log_text("[center][color=%s]%s[/color][/center]" \
		% [_LOG_DIM_COL, text])
	_battle_log_list.add_child(lbl)
	_trim_log_lines()


func _log_row_styles() -> Array:
	if _log_row_plain == null:
		var p := StyleBoxEmpty.new()
		p.content_margin_left = 3
		p.content_margin_right = 3
		p.content_margin_top = 2
		p.content_margin_bottom = 2
		_log_row_plain = p
		var h := StyleBoxFlat.new()
		h.bg_color = Color(0.85, 0.70, 0.40, 0.12)
		h.set_corner_radius_all(5)
		h.content_margin_left = 3
		h.content_margin_right = 3
		h.content_margin_top = 2
		h.content_margin_bottom = 2
		_log_row_hover = h
	return [_log_row_plain, _log_row_hover]


func _append_log_line(bb: String, data: Dictionary = {}, side: int = -1,
		icon_override: Texture2D = null, icon_tint: Color = Color.WHITE) -> void:
	var styles := _log_row_styles()
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", styles[0])
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	if not data.is_empty():
		# Snapshot NOW — the live card mutates (buffs) and may be freed; the
		# hover preview should show the card as it was at this beat.
		row.set_meta("log_card", data.duplicate(true))
	row.mouse_entered.connect(_on_log_row_hover.bind(row, true))
	row.mouse_exited.connect(_on_log_row_hover.bind(row, false))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	var art: Texture2D = icon_override
	if art == null and not data.is_empty():
		art = _log_art_for(data)
	if art != null:
		var rim := Color(0.62, 0.50, 0.26, 0.90)
		if side == 0:
			rim = Color(0.91, 0.75, 0.42, 0.95)
		elif side == 1:
			rim = Color(0.88, 0.47, 0.34, 0.95)
		var thumb := Panel.new()
		thumb.custom_minimum_size = Vector2(_LOG_THUMB, _LOG_THUMB)
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		thumb.clip_contents = true
		var tst := StyleBoxFlat.new()
		tst.bg_color = Color(0.055, 0.045, 0.038, 0.95)
		tst.border_color = rim
		tst.set_border_width_all(1)
		tst.set_corner_radius_all(6)
		thumb.add_theme_stylebox_override("panel", tst)
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(thumb)
		var tr := TextureRect.new()
		tr.texture = art
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		if icon_override != null:
			# Glyph (potion silhouette): centred with breathing room, tinted.
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.offset_left = 5; tr.offset_right = -5
			tr.offset_top = 5; tr.offset_bottom = -5
			tr.modulate = icon_tint
		else:
			# Card art: centre-cropped portrait chip.
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.offset_left = 1; tr.offset_right = -1
			tr.offset_top = 1; tr.offset_bottom = -1
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.add_child(tr)

	h.add_child(_make_log_text(bb))
	_battle_log_list.add_child(row)
	_trim_log_lines()
	if _battle_log_open:
		_scroll_log_to_bottom()


func _trim_log_lines() -> void:
	while _battle_log_list.get_child_count() > _LOG_MAX_LINES:
		var old := _battle_log_list.get_child(0)
		if old == _log_hover_row:
			_log_hover_row = null
			_hide_log_preview()
		_battle_log_list.remove_child(old)
		old.free()


func _on_log_row_hover(row: PanelContainer, entered: bool) -> void:
	if row == null or not is_instance_valid(row):
		return
	var styles := _log_row_styles()
	row.add_theme_stylebox_override("panel", styles[1] if entered else styles[0])
	if entered:
		_log_hover_row = row
		if row.has_meta("log_card"):
			_show_log_preview(row.get_meta("log_card"), row)
	else:
		if _log_hover_row == row:
			_log_hover_row = null
		_hide_log_preview()


## Full-card hover preview beside the drawer — same LIVE Card2D recipe as
## _reveal_cast_card (baked frame+art when cached, live name/rules text; a
## cache miss falls back to the full render, so enemy-only cards read too).
func _show_log_preview(data: Dictionary, row: Control) -> void:
	_hide_log_preview()
	if _hud_layer == null or data.is_empty():
		return
	var pic := CARD_SCENE.instantiate()
	pic.card_id = String(data.get("id", ""))
	pic.card_data = data.duplicate(true)
	pic.live_baked_mode = true
	pic.static_display = true
	# Enemy-only creatures carry no `desc` — synthesise rules text from their
	# triggers + keywords so the previewed card reads instead of showing blank.
	pic.synth_desc_if_empty = true
	_hud_layer.add_child(pic)
	# Card2D._ready resets mouse_filter to STOP; force IGNORE after add_child so
	# the preview never steals the row's hover (instant flicker loop otherwise).
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.z_index = 220
	var vp := get_viewport_rect().size
	# Card2D is natively 225×300; sit it just right of the drawer, vertically
	# tracking the hovered row, clamped on-screen.
	var py := clampf(row.get_global_rect().get_center().y - 150.0, 12.0, vp.y - 312.0)
	pic.position = Vector2(_battle_log_panel.get_global_rect().end.x + 12.0, py)
	pic.pivot_offset = Vector2(112.5, 150.0)
	pic.scale = Vector2(0.92, 0.92)
	pic.modulate.a = 0.0
	var tw := pic.create_tween()
	tw.set_parallel(true)
	tw.tween_property(pic, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pic, "modulate:a", 1.0, 0.10)
	_log_preview_card = pic


func _hide_log_preview() -> void:
	if _log_preview_card != null and is_instance_valid(_log_preview_card):
		_log_preview_card.queue_free()
	_log_preview_card = null


## Art lookup for the entry thumbnail — same fallback chain as
## Card2D._find_card_art (id → name → enemy-prefixed name).
func _log_art_for(data: Dictionary) -> Texture2D:
	var cid := String(data.get("id", ""))
	var name_id := String(data.get("name", "")).to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = null
	if String(data.get("type", "")) == "spell":
		art = CardArtAliases.try_load_spell_art(cid)
		if art == null and name_id != "":
			art = CardArtAliases.try_load_spell_art(name_id)
	if art == null:
		art = CardArtAliases.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art("e_" + name_id)
	return art


func _scroll_log_to_bottom() -> void:
	if _battle_log_scroll == null or not is_instance_valid(_battle_log_scroll):
		return
	# Two deferred frames: fit_content labels report their height one frame
	# after entering the tree, and the scrollbar's max updates the frame after.
	await get_tree().process_frame
	await get_tree().process_frame
	if _battle_log_scroll == null or not is_instance_valid(_battle_log_scroll):
		return
	_battle_log_scroll.scroll_vertical = int(_battle_log_scroll.get_v_scroll_bar().max_value)


var _log_tab_tween: Tween = null
func _pulse_log_tab() -> void:
	# New-line pulse on the closed tab. Skipped under reduce-motion.
	if _battle_log_tab == null or not is_instance_valid(_battle_log_tab):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if _log_tab_tween != null and _log_tab_tween.is_valid():
		_log_tab_tween.kill()
		_battle_log_tab.scale = Vector2.ONE
	_battle_log_tab.pivot_offset = _battle_log_tab.size * 0.5
	_log_tab_tween = _battle_log_tab.create_tween()
	_log_tab_tween.tween_property(_battle_log_tab, "scale", Vector2(1.10, 1.10), 0.08)
	_log_tab_tween.tween_property(_battle_log_tab, "scale", Vector2.ONE, 0.16)


## A creature's name tinted by side — gilt for yours, ember for the foe's.
func _log_card_ref(card: Control) -> String:
	if card == null or not is_instance_valid(card):
		return "[color=%s]?[/color]" % _LOG_DIM_COL
	var col: String = _LOG_ENEMY_COL if card.is_opponent else _LOG_PLAYER_COL
	return "[color=%s]%s[/color]" % [col, String(card.card_data.get("name", "?"))]


## Thumbnail rim side for a card: 0 = yours (gilt), 1 = the foe's (ember).
func _log_side(card: Control) -> int:
	if card == null or not is_instance_valid(card):
		return -1
	return 1 if card.is_opponent else 0


## Live card_data of a battlefield token, safe on a freed card (returns {}).
func _log_data(card: Control) -> Dictionary:
	if card == null or not is_instance_valid(card):
		return {}
	return card.card_data


## Public: Card2D's keyword chips (SHIELD pop, ARMORED block, LAST STAND…)
## mirror themselves into the chronicle through this.
func log_status(card: Control, text: String) -> void:
	if card == null or not is_instance_valid(card):
		return
	_log_event("%s — [color=#d8c9a8]%s[/color]" % [_log_card_ref(card), text],
		_log_data(card), _log_side(card))


## Net spell-cast log — the local caster ("You cast X on Y") and the foe's cast
## ("The foe casts X on Y"). Solo casts log inside _resolve_spell instead; these
## two funnel the net paths, where the host resolves BOTH sides so the solo line
## can't tell whose hand it was. `data` is the spell (thumbnail + hover preview).
func _net_log_local_cast(data: Dictionary, target: Control) -> void:
	var line := "You cast [color=%s]%s[/color]" \
		% [_LOG_PLAYER_COL, String(data.get("name", "a spell"))]
	if target != null and is_instance_valid(target):
		line += " on %s" % _log_card_ref(target)
	_log_event(line + ".", data, 0)


func _net_log_foe_cast(data: Dictionary, target: Control) -> void:
	var line := "The foe casts [color=%s]%s[/color]" \
		% [_LOG_ENEMY_COL, String(data.get("name", "a spell"))]
	if target != null and is_instance_valid(target):
		line += " on %s" % _log_card_ref(target)
	_log_event(line + ".", data, 1)


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
	_build_gold_chip_diegetic()
	_build_potion_bar_diegetic()
	_build_incoming_damage_chip()


## One caption voice for every HUD instrument (INCOMING / NEXT WAVE / COMMAND):
## a letterspaced small-cap line in dim gilt over a black outline. The payload
## under a caption carries any semantic color; the caption itself never does —
## three differently-tinted caption styles was a big part of the "every chip
## its own product" read. Caller anchors/parents the label.
func _make_rail_caption(text: String) -> Label:
	var caption := Label.new()
	caption.text = text
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", GILT)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 4)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_title != null:
		var fv := FontVariation.new()
		fv.base_font = GameTheme.font_title
		fv.spacing_glyph = 2
		caption.add_theme_font_override("font", fv)
	return caption


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
	# Warm ink-board family (the cards' mat / the map tooltips) on the chart
	# document kit — a plaque, not an app pill. The border keeps its crimson
	# threat ramp at hairline weight, matching every other plaque on the rail.
	var style := GameTheme.make_panel_style(
		Color(0.10, 0.062, 0.046, 0.94), Color(0.85, 0.27, 0.18, 1.0), 1, 4, true)
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
	# Full column width (-250..-14), matching the enemy plate and the wave
	# chip above/below it — the ragged right rail (three different widths)
	# was a big part of the "unfinished building" read.
	chip.offset_left = -250
	chip.offset_right = -14
	chip.offset_top = 324
	chip.offset_bottom = 398
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

	var caption := _make_rail_caption("INCOMING")
	caption.name = "ThreatCaption"
	col.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	var icon := TextureRect.new()
	icon.name = "ThreatIcon"
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1.0, 0.45, 0.30)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = GameTheme.tex_node_combat
	row.add_child(icon)
	_incoming_dmg_icon = icon

	var num := Label.new()
	num.name = "ThreatNum"
	num.text = ""
	num.add_theme_font_size_override("font_size", 34)
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
			# Both rows attack independently every turn (see _resolve_column_attack):
			# over an open player column, the front AND back enemy each land a
			# separate face hit, so both are summed here. They're distinct
			# creatures — counting both is the real total, not double-counting.
			# Player column empty? Then this attacker hits face.
			if _player_field[lane] != null or _player_back[lane] != null:
				continue
			var intent: String = String(attacker.get_meta("current_intent", "ATK"))
			# ATK/CHARGE/ENRAGE all swing this round (GUARD/HEAL/RETREAT/SUMMON
			# don't) — must match _enemy_is_threatening or the flag and the chip
			# disagree on enrage hits. Counted at current atk; the CHARGE/ENRAGE
			# buff lands at combat start, so this still slightly under-states.
			if intent != "ATK" and intent != "CHARGE" and intent != "ENRAGE":
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
	var dmg_text := str(dmg)
	if _incoming_dmg_label.text != dmg_text:
		_incoming_dmg_label.text = dmg_text
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
	var style_key := "lethal" if lethal else ("wounded" if dmg >= player_hp / 2 else "warm")
	if _incoming_dmg_style_key != style_key:
		_incoming_dmg_style_key = style_key
		_incoming_dmg_label.add_theme_color_override("font_color", num_color)
		var st: GameTheme.ChartPanelStyle = _incoming_dmg_chip.get_theme_stylebox("panel")
		if st != null:
			st.border_color = border
	if _incoming_dmg_icon != null:
		_incoming_dmg_icon.modulate = icon_color
		var want_tex := GameTheme.tex_node_elite if lethal else GameTheme.tex_node_combat
		if _incoming_dmg_icon.texture != want_tex:
			_incoming_dmg_icon.texture = want_tex


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

	# Ink-board backing with a dark edge — the same plate material the cards
	# mount their art on, so the antagonist reads as a framed instrument of
	# the war room rather than a photo on a void.
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_st := StyleBoxFlat.new()
	bg_st.bg_color = Color(0.075, 0.052, 0.042, 0.95)
	bg_st.border_color = Color(0.02, 0.012, 0.01, 0.9)
	bg_st.set_border_width_all(1)
	bg_st.set_corner_radius_all(4)
	bg_st.shadow_color = Color(0, 0, 0, 0.5)
	bg_st.shadow_size = 10
	bg_st.shadow_offset = Vector2(0, 4)
	bg.add_theme_stylebox_override("panel", bg_st)
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

	# ── Living Antagonist reaction overlay ──
	# The foe portrait is presented CLEAN — exactly like the player's plate in
	# _build_player_banner_diegetic (just image + fillet + HP). The old vignette
	# wash + warm rim-light made this corner read as a differently-treated photo
	# instead of the same instrument; both portraits already sit on black-bg art,
	# so they blend into their plates without help. Only the hidden hit-flash
	# stays — it's invisible at rest and just adds juice when the foe is struck
	# (driven by _presence_flinch).
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

	# Metal fillet wraps the WHOLE plate (portrait + HP plaque) — the card
	# art-plate language, in the foe's oxblood metal. (The old tinted
	# nine-patch read as a thin smudge and was the "unfinished" tell here.)
	var fillet := Panel.new()
	fillet.set_anchors_preset(Control.PRESET_FULL_RECT)
	fillet.offset_left = 4
	fillet.offset_top = 4
	fillet.offset_right = -4
	fillet.offset_bottom = -4
	var fil_st := StyleBoxFlat.new()
	fil_st.draw_center = false
	fil_st.border_color = Color(0.60, 0.24, 0.18, 0.85)
	fil_st.set_border_width_all(1)
	fil_st.set_corner_radius_all(2)
	fillet.add_theme_stylebox_override("panel", fil_st)
	fillet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(fillet)

	# Foe identity lives in the big encounter-name title in the center HUD
	# (_floor_label). The portrait stays a clean icon + HP medallion instead of
	# repeating the same name on a second plate right here.
	# Bar is inset inside the frame's painted border so it nests within the plate.
	# medallion_w = banner width minus the 14px inset on each side (offset_left/right
	# below). The wider foe plate gets a wider bar so a full bar reaches the rim.
	var hp := _make_hp_medallion_diegetic(true, enemy_hp, enemy_max_hp, float(W - 28))
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
	bark.add_theme_font_size_override("font_size", 18)
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

	# Ink-board backing with a dark edge — mirrors the enemy plate's material
	# so the two columns read as a matched pair of instruments.
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_st := StyleBoxFlat.new()
	bg_st.bg_color = Color(0.062, 0.048, 0.038, 0.95)
	bg_st.border_color = Color(0.02, 0.012, 0.01, 0.9)
	bg_st.set_border_width_all(1)
	bg_st.set_corner_radius_all(4)
	bg_st.shadow_color = Color(0, 0, 0, 0.5)
	bg_st.shadow_size = 10
	bg_st.shadow_offset = Vector2(0, 4)
	bg.add_theme_stylebox_override("panel", bg_st)
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

	# Metal fillet wraps the WHOLE plate — the player's bronze to the foe's
	# oxblood (same card art-plate language on both columns).
	var fillet := Panel.new()
	fillet.set_anchors_preset(Control.PRESET_FULL_RECT)
	fillet.offset_left = 4
	fillet.offset_top = 4
	fillet.offset_right = -4
	fillet.offset_bottom = -4
	var fil_st := StyleBoxFlat.new()
	fil_st.draw_center = false
	fil_st.border_color = Color(0.62, 0.48, 0.26, 0.85)
	fil_st.set_border_width_all(1)
	fil_st.set_corner_radius_all(2)
	fillet.add_theme_stylebox_override("panel", fil_st)
	fillet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(fillet)

	# Bar inset inside the frame's painted border so it nests within the plate.
	# medallion_w = banner width minus the 14px inset on each side (below). For the
	# 210px player plate this resolves to the historical 170px interior.
	var hp := _make_hp_medallion_diegetic(false, player_hp, player_max_hp, float(W - 28))
	hp.anchor_left = 0.0
	hp.anchor_right = 1.0
	hp.anchor_top = 1.0
	hp.anchor_bottom = 1.0
	hp.offset_top = HP_TOP
	hp.offset_bottom = -16
	hp.offset_left = 14
	hp.offset_right = -14
	banner.add_child(hp)


func _make_hp_medallion_diegetic(is_enemy: bool, hp: int, max_hp: int, medallion_w: float) -> Control:
	# Wax-sealed HP plaque: dark backing + gilt rim (gold for player, blood-
	# red for enemy), HP numeral centered. Uses a single StyleBoxFlat panel
	# rather than a NinePatchRect — the 64px-tall medallion is too short for
	# the old 52px patch margins (corners overlapped, making the frame look
	# clipped and broken).
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Ink plaque, not a UI pill: warm ink board, a restrained metal rim
	# (bronze for the player, oxblood for the foe), square-ish document
	# corners. The old 14px-radius lozenge with a saturated 3px rim was the
	# single loudest "unfinished mobile UI" read on the screen.
	var rim: Color = Color(0.66, 0.20, 0.15, 0.95) if is_enemy \
		else Color(0.62, 0.48, 0.26, 0.95)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.092, 0.070, 0.052, 0.96)
	s.border_color = rim
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		s.set(k, 2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(k, 5)
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
	# The fill spans the medallion's interior — its mounted width minus PAD on each
	# side. full_w MUST track the real plate width: the foe plate is wider (236) than
	# the player's (210), so the old hardcoded 170 left the enemy bar ~26px short of
	# full — it read as a permanently-not-full (glitched) health bar even at full HP.
	# Stored as meta so _update_hud scales the drain tween to this exact width.
	var full_w: float = maxf(medallion_w - 2.0 * PAD, 1.0)
	# Sealing-wax bar, matte: oxblood with a faint cooled-sheen top line —
	# the bar IS the wax poured into the plaque's channel. (The old fill was
	# saturated crimson with a glossy gel highlight.)
	var fill_color: Color = Color(0.55, 0.135, 0.10) if is_enemy \
		else Color(0.50, 0.125, 0.10)
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
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_right = 2
	fill_style.border_width_top = 1
	fill_style.border_color = Color(minf(fill_color.r * 1.35, 1.0),
		minf(fill_color.g * 1.35, 1.0), minf(fill_color.b * 1.35, 1.0), 0.50)
	fill.add_theme_stylebox_override("panel", fill_style)
	disc.add_child(fill)

	# HP numeral rides ON TOP of the crimson fill bar, so it's ivory (not red —
	# red-on-red vanished) with a black outline. 30pt: still the boldest read in the
	# HUD, but at 40pt the glyphs (plus their outline) nearly overflowed the ~54px
	# plate and the health plaque loomed larger than the portrait above it.
	var lbl := _make_text_label("%d / %d" % [hp, max_hp], 30,
		Color(1.0, 0.96, 0.88))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 4)
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
	# Widened (was 540px) and lengthened (was 94px) so the now-larger title /
	# phase / turn / EDICT stack reads without crowding or overflowing the rect.
	# The flanking plates (relic strip far-left, enemy banner far-right) start at
	# ~x=218 and ~x=-250, so a 640px centred strip stays well clear of both.
	strip.offset_left = -320
	strip.offset_right = 320
	strip.offset_top = 8
	strip.offset_bottom = 150
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
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(stack)

	# Encounter name — quiet identity, not a shout: the fight-start intro
	# banner already announces it big, and the player flagged the old 34pt
	# four-tier stack as floating-text clutter over the lanes. 26pt gilt with
	# the scrim + outline still reads from the couch.
	var encounter_text := _encounter_name if _encounter_name != "" \
		else "Floor %d" % RunState.current_floor
	_floor_label = _make_text_label(encounter_text, 26, GILT)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_floor_label.add_theme_constant_override("outline_size", 5)
	stack.add_child(_floor_label)

	# Phase + round/instruction share ONE row — "YOUR TURN   Round 1 · Set
	# your line" — halving the stack's depth. The two labels stay separate
	# controls (every call site updates them independently); only the layout
	# merged. Phase keeps the loud gilt Cinzel, the instruction rides beside
	# it in near-white.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 18)
	status_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(status_row)
	_phase_label = _make_text_label("YOUR TURN", 24, GameTheme.GILT_BRIGHT)
	if GameTheme.font_title != null:
		_phase_label.add_theme_font_override("font", GameTheme.font_title)
	_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_phase_label.add_theme_constant_override("outline_size", 5)
	status_row.add_child(_phase_label)
	_turn_label = _make_text_label("Round 1 · Set your line", 20, Color(1.0, 0.97, 0.86))
	_turn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_turn_label.add_theme_constant_override("outline_size", 5)
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_label.size_flags_vertical = Control.SIZE_FILL
	status_row.add_child(_turn_label)

	if _encounter_passive != "":
		var enc = EncounterDB.get_encounter(RunState.current_encounter_id)
		# The encounter's standing rule, on the same dark ink plaque as every
		# other HUD instrument (INCOMING / NEXT WAVE chips, HP plates), rimmed
		# in muted oxblood to mark it as the foe's law. It used to be a bright
		# parchment notice — the ONE light object on a dark HUD, which read as
		# a stray tooltip stuck over the lanes and was the loudest "every
		# element its own style" note on the screen. Its prominence now comes
		# from position (dead center under the title), not a second material.
		var threat_frame := PanelContainer.new()
		# The plaque hangs near the enemy back-row slot tops — IGNORE so it
		# never eats hovers/clicks meant for cards under it (PanelContainer
		# defaults to STOP, which silently dead-zoned that strip of board).
		threat_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var threat_bg := GameTheme.make_panel_style(
			Color(0.10, 0.062, 0.046, 0.92), Color(0.55, 0.22, 0.15, 0.9), 1, 4, true)
		threat_bg.content_margin_left = 12
		threat_bg.content_margin_right = 12
		threat_bg.content_margin_top = 4
		threat_bg.content_margin_bottom = 5
		threat_frame.add_theme_stylebox_override("panel", threat_bg)
		threat_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# Still the fight's permanent threat and the ONLY place the rule lives
		# (the intro banner defers to this line). 18pt (the reading floor) on a
		# 620px measure so nearly every rule fits ONE line — at the old
		# 20pt/560px most wrapped to two, and the taller box draped over the
		# enemy back-row slot frames like a tooltip stuck open (the single
		# loudest layout note on the screen). The ink box itself stays: it is
		# the contrast guarantee when a bright parchment card sits behind it.
		var rule_text: String = enc.get("passive_desc", "")
		var passive := _make_text_label(rule_text, 18, Color(0.93, 0.88, 0.76))
		if GameTheme.font_card_body_bold != null:
			passive.add_theme_font_override("font", GameTheme.font_card_body_bold)
		passive.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		passive.add_theme_constant_override("outline_size", 3)
		passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# The box hugs the ink: only force the 620px wrap width when the rule
		# genuinely needs two lines — a short rule in a full-width box is the
		# "stuck tooltip" read all over again.
		var rule_font: Font = passive.get_theme_font("font")
		var rule_w: float = rule_font.get_string_size(
			rule_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		passive.custom_minimum_size = Vector2(minf(rule_w + 2.0, 620.0), 0)
		threat_frame.add_child(passive)
		stack.add_child(threat_frame)


func _build_mana_post_diegetic() -> void:
	# The player's own Command instrument. The foe's mirror seal is SKIRMISH-
	# ONLY (built in _net_begin_combat, fed by the real synced pool): the old
	# solo copy displayed a synthetic number the enemy never actually spends —
	# a second glowing COMMAND instrument that cluttered the rail and made the
	# player's own readout ambiguous. Solo enemy pressure is already told by
	# the INCOMING and NEXT WAVE chips, which show real consequences.
	_build_command_seal_post(false)


## Paint a wax COMMAND SEAL — the per-turn resource readout — for one side. A big
## pressed disc of sealing-wax navy (the same wax every card's cost seal is pressed
## in, so "blue wax = Command" reads as one system). The campaign fiction is a
## commander stamping writs at a war table, so the per-turn resource is the signet
## itself. Card2D.WaxSeal paints the blob (seeded deckle, stamp ring, sheen); a dim
## lamp-glow behind it flickers like the table light. The count rides front-and-
## center as a single bold numeral so it's still readable from across the screen.
##
## is_opp=false → the PLAYER's seal (bottom-left, beside the player banner; its
## numeral is _mana_label, pulsed on spend). is_opp=true → the OPPONENT's mirror
## (top-right corner, under the enemy banner), fed by _net_opp_mana — SKIRMISH
## ONLY, where it shows the real synced peer pool. Same wax material, same
## furniture — built "the same way" for both sides; player=navy, opponent=red.
func _build_command_seal_post(is_opp: bool) -> void:
	const GEM_W := 124
	const GEM_H := 152
	const HH := 56.0   # instrument half-height (plinth band + numeral box anchor)
	const CY := 62.0   # seal center Y within the post
	var post := Control.new()
	if is_opp:
		# Enemy column, top-RIGHT (skirmish only): tucked under the foe's
		# portrait/HP banner so the peer's resource groups with its other
		# vitals. The muster/wave chip never builds in skirmish, so the rail
		# below the incoming-damage chip (y324..398) is free.
		post.anchor_left = 1.0
		post.anchor_right = 1.0
		post.anchor_top = 0.0
		post.anchor_bottom = 0.0
		post.offset_left = -194      # centered under the W=236 enemy banner
		var seal_top: int = 404
		post.offset_top = seal_top
		post.offset_right = -70
		post.offset_bottom = seal_top + GEM_H
	else:
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
	# The instrument is a hover target so a new commander can learn what the
	# blue wax MEANS (the numeral alone teaches nothing). The opponent's mirror
	# is hoverable too — same lesson, framed as "what the foe can spend".
	post.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_opp:
		post.tooltip_text = "FOE'S COMMAND\nWhat your enemy can spend this turn. The bigger it grows, the heavier the line they can field."
	else:
		post.tooltip_text = _command_tooltip_text()
		_mana_seal_post = post
	_hud_layer.add_child(post)

	# Soft lamp-glow behind the seal — warm table light, not arcane radiance.
	# Kept dim so the wax stays matte; a looping tween flickers it gently.
	# Player: warm amber candlelight. Opponent: ember/red so the corner reads
	# immediately as the enemy's instrument, not a duplicate of the player's.
	var aura_grad := Gradient.new()
	aura_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	if is_opp:
		aura_grad.colors = PackedColorArray([
			Color(0.82, 0.18, 0.10, 0.28),
			Color(0.70, 0.14, 0.08, 0.12),
			Color(0.55, 0.10, 0.06, 0.0)])
	else:
		aura_grad.colors = PackedColorArray([
			Color(1.0, 0.76, 0.42, 0.26),
			Color(0.92, 0.62, 0.30, 0.11),
			Color(0.80, 0.50, 0.24, 0.0)])
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

	# Round-seal radius. 48 (96px disc) — wide enough that the wax bottom
	# reaches the plinth band at CY+HH-10 (a round seal is shorter than the
	# old crystal; at the crystal-derived 42 it floated 4px clear of the
	# band), while the 96px face still clears the 124px post side margins.
	var seal_r := 48.0

	# Ink plinth under the seal — the wax is MOUNTED on the rail like the
	# other instruments, not floating in the dark. Sits behind the seal's
	# bottom edge; the caption hangs just below it.
	var plinth := Panel.new()
	plinth.offset_left = GEM_W / 2.0 - 40
	plinth.offset_right = GEM_W / 2.0 + 40
	# Top tucks well behind the wax: the seal blob is inset ~1.5px in its rect
	# and its deckle wobbles up to ~7%, so its visual bottom sits ~5px above
	# the rect edge. The band draws BEFORE the seal, so the overlap is hidden
	# and the visible strip always meets the wax with no float gap.
	plinth.offset_top = CY + seal_r - 14
	plinth.offset_bottom = CY + HH + 10
	plinth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plinth_st := StyleBoxFlat.new()
	plinth_st.bg_color = Color(0.092, 0.070, 0.052, 0.96)
	plinth_st.border_color = Color(0.62, 0.48, 0.26, 0.75)
	plinth_st.set_border_width_all(1)
	plinth_st.set_corner_radius_all(3)
	plinth_st.shadow_color = Color(0, 0, 0, 0.5)
	plinth_st.shadow_size = 5
	plinth_st.shadow_offset = Vector2(0, 2)
	plinth.add_theme_stylebox_override("panel", plinth_st)
	post.add_child(plinth)

	# The pressed seal itself. Card2D.WaxSeal draws a seeded irregular wax
	# blob with a stamp-impression ring — the exact painter the cards use for
	# their cost seals, in the exact cost wax (#264167), scaled up to an
	# instrument. seal_r is set above the plinth block, which seats against
	# the wax's bottom edge.
	# Player seal = navy (same blue as card cost seals — "blue wax = Command").
	# Opponent seal = vermilion red so the two sides read as team colours at
	# a glance: navy=player, red=enemy.
	var seal := Card2D.WaxSeal.new()
	seal.wax = GameTheme.COMMAND_RED_GEM if is_opp else GameTheme.COST_BLUE_GEM
	seal.seed_text = "command_post_opp" if is_opp else "command_post"
	seal.position = Vector2(GEM_W / 2.0 - seal_r, CY - seal_r)
	seal.size = Vector2(seal_r * 2.0, seal_r * 2.0)
	post.add_child(seal)

	# Big numeric — current / max Command, dominant readout, pressed INTO the
	# wax face: cream numeral + deep-navy outline, same ink as card cost seals.
	var cur_val: int = _net_opp_mana if is_opp else player_mana
	var max_val: int = _net_opp_max_mana if is_opp else player_max_mana
	var lbl := _make_text_label("%d / %d" % [cur_val, max_val],
		37, Color(0.996, 0.941, 0.800))
	if GameTheme.font_title_black:
		lbl.add_theme_font_override("font", GameTheme.font_title_black)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left = 0
	lbl.offset_right = GEM_W
	lbl.offset_top = CY - HH
	lbl.offset_bottom = CY + HH
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.16, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	post.add_child(lbl)
	if is_opp:
		_net_opp_mana_label = lbl
	else:
		_mana_label = lbl

	# Caption below — the shared rail-caption voice (letterspaced small caps
	# in dim gilt), same label style as the INCOMING / NEXT WAVE chips.
	var caption := _make_rail_caption("COMMAND")
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -27
	caption.offset_bottom = -3
	post.add_child(caption)

	# Carryover pips — small dots on the plinth shelf showing how much unspent
	# Command will BANK into next turn (up to MAX_BANKED_MANA). Teaches the bank
	# rule by sight: spend down and the lit dots wink out. Player seal only.
	if not is_opp:
		var pips := HBoxContainer.new()
		pips.alignment = BoxContainer.ALIGNMENT_CENTER
		pips.add_theme_constant_override("separation", 5)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.offset_left = 0
		pips.offset_right = GEM_W
		pips.offset_top = CY + seal_r - 2     # on the plinth band, just below the wax
		pips.offset_bottom = CY + seal_r + 14
		post.add_child(pips)
		_bank_pips = pips
		_update_bank_pips()

	# Lamp flicker: the wax is inert (no arcane breathing) — only the table
	# light moves. Uneven up/down times keep the loop from reading metronomic.
	if UserSettings.reduce_motion:
		aura.modulate.a = 0.9   # steady lamplight, no flicker
	else:
		var aura_tw := aura.create_tween().set_loops()
		aura_tw.tween_property(aura, "modulate:a", 0.95, 1.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		aura_tw.tween_property(aura, "modulate:a", 0.55, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if is_opp:
		_net_opp_mana_post = post


## Hover text for the player's Command seal — teaches the resource from scratch:
## what it is, that it refills each turn, and that unspent Command banks. Rebuilt
## live (max / cap can grow mid-run) so the lesson never goes stale.
func _command_tooltip_text() -> String:
	var bank_line: String
	if _has_relic("ice_cream"):
		bank_line = "Unspent Command ALL carries over (Ice Cream)."
	else:
		bank_line = "Up to %d unspent Command carries over — the lit dots on the shelf." % MAX_BANKED_MANA
	return "COMMAND — your turn resource.\nSpend it to play creatures and spells. Refills to %d at the start of each turn.\n%s" % [player_max_mana, bank_line]


## Set a Command-seal numeral, auto-shrinking the font so the whole string
## stays on the ~96px wax blob. "3 / 3" keeps the full 37px; double-digit
## readouts ("12 / 12" late-run) step down a few px instead of overhanging
## the seal. Width is measured with the label's actual font; the floor keeps
## the worst case legible rather than microscopic.
func _set_seal_readout(lbl: Label, text: String) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.text = text
	var f: Font = lbl.get_theme_font("font")
	if f == null:
		return
	var fs := 37
	while fs > 20 and f.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 100.0:
		fs -= 1
	lbl.add_theme_font_size_override("font_size", fs)


## Repaint the carryover dots: `lit` of `cap` filled, where lit = what you'd bank
## right now (current Command, capped). Called on build and on every HUD refresh.
func _update_bank_pips() -> void:
	if _bank_pips == null or not is_instance_valid(_bank_pips):
		return
	for c in _bank_pips.get_children():
		c.queue_free()
	var cap: int = player_mana if _has_relic("ice_cream") else MAX_BANKED_MANA
	cap = clampi(cap, 0, 6)   # bound the row so a fat Ice Cream bank can't overflow
	var lit: int = clampi(player_mana, 0, cap)
	for i in range(cap):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(5)
		st.set_border_width_all(1)
		if i < lit:
			# Lit = will carry over: warm gilt, like banked coin on the shelf.
			st.bg_color = Color(0.93, 0.74, 0.36, 0.96)
			st.border_color = Color(0.25, 0.16, 0.05, 0.9)
		else:
			# Empty bank slot: hollow and dim.
			st.bg_color = Color(0.10, 0.08, 0.06, 0.55)
			st.border_color = Color(0.55, 0.44, 0.26, 0.6)
		dot.add_theme_stylebox_override("panel", st)
		_bank_pips.add_child(dot)
	# Keep the hover lesson current with the live max / cap.
	if _mana_seal_post != null and is_instance_valid(_mana_seal_post):
		_mana_seal_post.tooltip_text = _command_tooltip_text()


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

	# EXHAUST — third stack, charred paper. Hidden until a card is actually
	# exhausted (Exhaust keyword / exhaust-a-card effects), so it teaches itself
	# by appearing the moment a card leaves play "for good" instead of vanishing.
	var exhaust_box := _make_pile_panel_diegetic("EXHAUST", 2)
	exhaust_box.anchor_left = 0.0
	exhaust_box.anchor_right = 0.0
	exhaust_box.anchor_top = 0.0
	exhaust_box.anchor_bottom = 0.0
	exhaust_box.offset_left = COL_LEFT + (PILE_W + 18) * 2
	exhaust_box.offset_right = COL_LEFT + (PILE_W + 18) * 2 + PILE_W
	exhaust_box.offset_top = COL_TOP
	exhaust_box.offset_bottom = COL_TOP + PILE_H
	exhaust_box.visible = false
	_exhaust_box = exhaust_box
	_hud_layer.add_child(exhaust_box)


func _build_gold_chip_diegetic() -> void:
	# Combat gold readout — gold accrues mid-fight (Coin / Scroll of Greed relics,
	# slay-gold, gain_gold effects) but was never shown in combat. Small struck
	# coin + numeral in the left column under the piles. Campaign only (skirmish
	# has no RunState gold context).
	if _is_net():
		return
	var chip := Control.new()
	chip.name = "GoldChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.anchor_left = 0.0
	chip.anchor_right = 0.0
	chip.anchor_top = 0.0
	chip.anchor_bottom = 0.0
	chip.offset_left = 16
	chip.offset_right = 16 + 130
	chip.offset_top = 232
	chip.offset_bottom = 232 + 28
	_hud_layer.add_child(chip)
	# Struck-coin disc: gilt fill, dark milled rim, a faint inner ring so it reads
	# as a coin rather than a plain dot.
	var coin := Panel.new()
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.85, 0.66, 0.22)
	cs.border_color = Color(0.28, 0.18, 0.05)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(999)
	coin.add_theme_stylebox_override("panel", cs)
	coin.position = Vector2(0, 3)
	coin.size = Vector2(22, 22)
	chip.add_child(coin)
	var coin_inner := Panel.new()
	coin_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cis := StyleBoxFlat.new()
	cis.bg_color = Color(0, 0, 0, 0.0)
	cis.border_color = Color(0.30, 0.20, 0.05, 0.6)
	cis.set_border_width_all(1)
	cis.set_corner_radius_all(999)
	coin_inner.add_theme_stylebox_override("panel", cis)
	coin_inner.position = Vector2(4, 4)
	coin_inner.size = Vector2(14, 14)
	coin.add_child(coin_inner)
	var lbl := _make_text_label(str(RunState.gold), 18, Color(0.98, 0.86, 0.46))
	if GameTheme.font_title_black:
		lbl.add_theme_font_override("font", GameTheme.font_title_black)
	lbl.position = Vector2(30, 0)
	lbl.size = Vector2(100, 28)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	_gold_label = lbl
	_gold_displayed = RunState.gold


func _build_potion_bar_diegetic() -> void:
	# Skirmish: the belt shows the drafted battle potion(s) (0 = no draft/declined,
	# so no belt). Solo shows the full MAX_POTIONS belt. Freeze the net slot count
	# now so consuming a potion mid-fight leaves an empty slot, not a shrinking bar.
	if _is_net():
		_net_potion_slots = _net_my_slot().potions.size()
		if _net_potion_slots == 0:
			return
	# Three potion slots just above the player banner — clusters consumables
	# with player resources (HP/portrait/mana) on the bottom-left, matching
	# the StS convention of "potions near player HP". Each filled slot is a
	# button that uses the potion (resolves immediately for non-targeted
	# effects, or enters potion-targeting for Bottled Fury et al). Empty
	# slots render as a shaded placeholder.
	const SLOT := 52
	const GAP := 6
	const COL_LEFT := 14
	# Caption in the one rail voice, mirroring the RELICS strip up the column —
	# the unframed icon row read as three stray glyphs floating over the wood.
	var caption := _make_rail_caption("POTIONS")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.anchor_left = 0.0
	caption.anchor_right = 0.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_left = COL_LEFT + 2
	caption.offset_right = COL_LEFT + 200
	caption.offset_top = -404
	caption.offset_bottom = -382
	_hud_layer.add_child(caption)
	var bar := Control.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 0.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = COL_LEFT
	bar.offset_right = COL_LEFT + (SLOT + GAP) * _ctx_max_potions()
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
	var belt: Array = _ctx_potions()
	for i in range(_ctx_max_potions()):
		var pid: String = String(belt[i]) if i < belt.size() else ""
		var slot := _make_combat_potion_slot(pid, i)
		slot.position = Vector2(i * (SLOT + GAP), 0)
		slot.size = Vector2(SLOT, SLOT)
		_potion_bar_root.add_child(slot)


func _make_combat_potion_slot(pid: String, index: int) -> Control:
	const SLOT := 52
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(SLOT, SLOT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	# Framed slot in the relic-chip material family (dark backing, bronze rim,
	# rounded) — the old naked ColorRect vanished into the dark table, which
	# made the belt read as three stray icons. Filled slots get a potion-color
	# halo, the same "type glow" language the relic chips use for tiers.
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.055, 0.045, 0.038, 0.94)
	frame.set_corner_radius_all(7)
	if pid == "":
		frame.border_color = Color(0.30, 0.24, 0.14, 0.55)
		frame.set_border_width_all(1)
	else:
		frame.border_color = Color(0.45, 0.36, 0.20, 0.95)
		frame.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", frame)
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
	# Silhouette kit = tint by potion colour; painted art (PNG) = untinted.
	var tint: Color = data.get("color", Color.WHITE)
	if PotionDB.is_painted_icon(pid):
		tint = Color.WHITE
	frame.shadow_color = Color(tint.r, tint.g, tint.b, 0.30)
	frame.shadow_size = 5

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
	# PASS so the wrapper underneath still sees hover for the rich tip; the
	# button keeps the click. No tooltip_text — the rich tip replaces it.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.pressed.connect(func():
		_use_combat_potion(index)
	)
	wrapper.add_child(btn)
	# Same StS-style hover as relic chips: pop + name/rules tip. The tag also
	# teaches the click affordance, which nothing on screen said before.
	var tag := "Potion · click, then pick a target" \
		if str(data.get("targeting", "none")) != "none" else "Potion · click to drink"
	GameTheme.attach_rich_hover(wrapper, data.get("name", pid), data.get("desc", ""),
		tag, tint)
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
	art.offset_bottom = -22
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.add_child(art)

	# Writ-stack: the piles are stacks of the same parchment the hand cards
	# are cut from — the deck is your sealed orders (wax dot on the top
	# leaf), the discard is the spent dispatches (cooler, grayer paper).
	# Replaces the dark ornate card-back texture, which read as a separate
	# product from the v9 parchment writs fanned right next to it.
	var is_discard := kind == 1
	var is_exhaust := kind == 2
	# Two back leaves nudged up-left — the stack's physical thickness.
	for layer_i in [2, 1]:
		var off := float(layer_i) * 3.0
		var leaf := Panel.new()
		leaf.set_anchors_preset(Control.PRESET_FULL_RECT)
		leaf.offset_left = -off
		leaf.offset_top = -off
		leaf.offset_right = -off
		leaf.offset_bottom = -off
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lst := StyleBoxFlat.new()
		var shade := 0.78 - float(layer_i) * 0.09
		if is_exhaust:
			lst.bg_color = Color(0.34 * shade, 0.30 * shade, 0.295 * shade)
		elif is_discard:
			lst.bg_color = Color(0.760 * shade, 0.730 * shade, 0.660 * shade)
		else:
			lst.bg_color = Color(0.851 * shade, 0.792 * shade, 0.671 * shade)
		lst.border_color = Color(0.165, 0.125, 0.082, 0.9)
		lst.set_border_width_all(1)
		lst.set_corner_radius_all(2)
		leaf.add_theme_stylebox_override("panel", lst)
		art.add_child(leaf)

	# Soft drop shadow under the front leaf so the stack sits above the rail.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.06, 0.04, 0.03, 0.96)
	shadow_style.set_corner_radius_all(2)
	shadow_style.shadow_color = Color(0, 0, 0, 0.55)
	shadow_style.shadow_size = 7
	shadow_style.shadow_offset = Vector2(0, 4)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	art.add_child(shadow)

	# Front leaf: clean writ paper with a bronze hairline; the deck's carries
	# a small oxblood wax seal (orders still sealed), the discard's stays
	# bare and cooler (already opened and spent).
	var front := Panel.new()
	front.set_anchors_preset(Control.PRESET_FULL_RECT)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fst := StyleBoxFlat.new()
	if is_exhaust:
		fst.bg_color = Color(0.33, 0.29, 0.285)   # spent ash — reads as "gone for good"
	elif is_discard:
		fst.bg_color = Color(0.745, 0.718, 0.648)
	else:
		fst.bg_color = Color(0.851, 0.792, 0.671)
	fst.border_color = Color(0.165, 0.125, 0.082)
	fst.set_border_width_all(1)
	fst.set_corner_radius_all(2)
	front.add_theme_stylebox_override("panel", fst)
	art.add_child(front)
	var front_rule := Panel.new()
	front_rule.set_anchors_preset(Control.PRESET_FULL_RECT)
	front_rule.offset_left = 4
	front_rule.offset_top = 4
	front_rule.offset_right = -4
	front_rule.offset_bottom = -4
	front_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frst := StyleBoxFlat.new()
	frst.draw_center = false
	frst.border_color = Color(GILT.r, GILT.g, GILT.b, 0.35)
	frst.set_border_width_all(1)
	front_rule.add_theme_stylebox_override("panel", frst)
	front.add_child(front_rule)
	if kind == 0:
		var seal := Panel.new()
		seal.anchor_left = 0.5
		seal.anchor_right = 0.5
		seal.anchor_top = 0.0
		seal.anchor_bottom = 0.0
		seal.offset_left = -9
		seal.offset_right = 9
		seal.offset_top = 22
		seal.offset_bottom = 40
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sst := StyleBoxFlat.new()
		sst.bg_color = Color(0.52, 0.13, 0.10)
		sst.border_color = Color(0.34, 0.08, 0.06, 0.9)
		sst.set_border_width_all(1)
		sst.set_corner_radius_all(999)
		sst.shadow_color = Color(0, 0, 0, 0.35)
		sst.shadow_size = 2
		sst.shadow_offset = Vector2(0, 1)
		seal.add_theme_stylebox_override("panel", sst)
		front.add_child(seal)

	# Count badge — dark disc clipped to the bottom-right corner of the card.
	var badge := Panel.new()
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -34
	badge.offset_top = -34
	badge.offset_right = -1
	badge.offset_bottom = -1
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.08, 0.05, 0.035, 0.97)
	badge_style.border_color = Color(GILT.r, GILT.g, GILT.b, 0.9)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(16)
	badge_style.shadow_color = Color(0, 0, 0, 0.55)
	badge_style.shadow_size = 4
	badge.add_theme_stylebox_override("panel", badge_style)
	art.add_child(badge)

	var count_label := _make_text_label("0", 22, IVORY)
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_title_black:
		count_label.add_theme_font_override("font", GameTheme.font_title_black)
	badge.add_child(count_label)

	# Caption ("DECK" / "DISCARD" / "EXHAUST"). No letter-spacing: at small HUD sizes
	# the inserted spaces thin the word and hurt legibility — kept tight and bigger.
	var caption := _make_text_label(caption_text, 18,
		Color(GILT.r, GILT.g, GILT.b, 1.0))
	if GameTheme.font_title != null:
		caption.add_theme_font_override("font", GameTheme.font_title)
	caption.add_theme_constant_override("outline_size", 4)
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -21
	caption.offset_bottom = 1
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.add_child(caption)

	if kind == 0:
		_deck_count_label = count_label
	elif kind == 2:
		_exhaust_count_label = count_label
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
	elif kind == 2:
		entries = _exhaust_pile.duplicate()
		title_text = "EXHAUSTED (%d) — removed for the rest of this fight" % entries.size()
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

const QUICK_HELP: Array = [
	{"name": "Lanes", "desc": "Four lanes. Creatures attack straight across their opposing lane."},
	{"name": "Rows", "desc": "Front guards back. Front attacks first and is hit first."},
	{"name": "Forecast", "desc": "Lane markers preview enemy strikes before CLASH: DIES, TAKES N, BACK DIES, or HP -N."},
	{"name": "Swift", "desc": "Swift creatures strike before the main clash."},
	{"name": "Hand", "desc": "Unplayed cards stay. Right-click cards to discard them at turn end."},
]

const MECHANICS_HELP: Array = [
	{"name": "Four lanes", "desc": "Each side has 4 lanes. A creature attacks its opposing lane: front creature first, then back, then face if the lane is empty."},
	{"name": "Forecast chips", "desc": "During your turn, lane markers and chips preview enemy strikes before CLASH: TAKES N, DIES, BACK DIES, or HP -N."},
	{"name": "Sacrifice", "desc": "Some cards destroy one of your own creatures as a cost — never free. Its On-Death effect still triggers."},
	{"name": "Banking", "desc": "Carry up to 2 unused Command into next turn. Pay it like normal Command."},
	{"name": "Front / Back row", "desc": "Both rows attack each turn — front goes first and is hit first. Back is queue space, not a separate tier."},
	{"name": "Swift phase", "desc": "Creatures with Swift attack BEFORE simultaneous combat resolves. They strike first and take damage normally."},
	{"name": "Command", "desc": "Your orders for the turn — 3 per turn baseline, spent to play creatures and spells. Relics can grow your pool."},
	{"name": "Your hand", "desc": "Unplayed cards stay in hand. Each turn tops your hand back up to 5, max 10. Right-click cards to mark them for discard at turn end."},
]


func _toggle_glossary() -> void:
	if _glossary_layer != null and is_instance_valid(_glossary_layer):
		_close_glossary()
	else:
		_show_glossary()


func _show_glossary() -> void:
	_show_combat_primer()


func _reset_glossary_layer(dim_alpha: float = 0.56) -> Button:
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
	dim.bg_color = Color(0, 0, 0, dim_alpha)
	backdrop.add_theme_stylebox_override("normal", dim)
	backdrop.add_theme_stylebox_override("hover", dim)
	backdrop.add_theme_stylebox_override("pressed", dim)
	backdrop.pressed.connect(_close_glossary)
	_glossary_layer.add_child(backdrop)
	return backdrop


func _show_combat_primer() -> void:
	_reset_glossary_layer(0.48)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_right = -70
	panel.offset_top = -310
	panel.offset_bottom = 310
	panel.custom_minimum_size = Vector2(450, 620)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.065, 0.050, 0.040, 0.97)
	ps.border_color = Color(0.72, 0.52, 0.22, 0.95)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(5)
	ps.shadow_color = Color(0, 0, 0, 0.50)
	ps.shadow_size = 10
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 16
	ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	_glossary_layer.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := _make_text_label("FIELD CARD", 28, GILT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := _make_text_label("The five things you need before pressing CLASH.", 15, IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.82)
	root.add_child(sub)

	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.46, 0.20, 0.72)
	rule.custom_minimum_size = Vector2(0, 2)
	root.add_child(rule)

	for e in QUICK_HELP:
		root.add_child(_make_glossary_row(String(e.name), String(e.desc), 360))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(buttons)
	var kw_btn := _make_glossary_action_button("KEYWORDS")
	kw_btn.pressed.connect(_show_keyword_glossary)
	buttons.add_child(kw_btn)
	var full_btn := _make_glossary_action_button("FULL RULES")
	full_btn.pressed.connect(_show_full_glossary)
	buttons.add_child(full_btn)
	var close_btn := _make_glossary_action_button("CLOSE")
	close_btn.pressed.connect(_close_glossary)
	buttons.add_child(close_btn)

	var hint := _make_text_label("[Tab] / [?] to toggle", 13, IVORY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.70)
	root.add_child(hint)


func _show_full_glossary() -> void:
	_reset_glossary_layer(0.72)

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


func _show_keyword_glossary() -> void:
	_reset_glossary_layer(0.66)

	var title := _make_text_label("KEYWORDS", 34, IVORY)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 36
	title.offset_bottom = 84
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glossary_layer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.5
	scroll.anchor_right = 0.5
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = -330
	scroll.offset_right = 330
	scroll.offset_top = 102
	scroll.offset_bottom = -100
	_glossary_layer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	col.custom_minimum_size = Vector2(640, 0)
	scroll.add_child(col)
	for k in KeywordEffects.KEYWORDS.keys():
		var entry = KeywordEffects.KEYWORDS[k]
		col.add_child(_make_glossary_row(entry.display, entry.desc, 560))

	var back := _make_glossary_action_button("FIELD CARD")
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -190
	back.offset_right = -20
	back.offset_top = -62
	back.offset_bottom = -26
	back.pressed.connect(_show_combat_primer)
	_glossary_layer.add_child(back)

	var close := _make_glossary_action_button("CLOSE")
	close.anchor_left = 0.5
	close.anchor_right = 0.5
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	close.offset_left = 20
	close.offset_right = 190
	close.offset_top = -62
	close.offset_bottom = -26
	close.pressed.connect(_close_glossary)
	_glossary_layer.add_child(close)


func _close_glossary() -> void:
	if _glossary_layer != null and is_instance_valid(_glossary_layer):
		_glossary_layer.queue_free()
		_glossary_layer = null


func _make_glossary_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(124, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_title:
		btn.add_theme_font_override("font", GameTheme.font_title)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.86, 0.78, 0.60))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	btn.add_theme_constant_override("outline_size", 3)
	var normal := GameTheme.make_panel_style(
		Color(0.12, 0.075, 0.048, 0.96), GILT, 1, 3, true)
	var hover := GameTheme.make_panel_style(
		Color(0.20, 0.12, 0.065, 0.98), GameTheme.GILT_BRIGHT, 1, 3, true)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus", normal)
	return btn


func _make_glossary_row(entry_name: String, desc: String,
		desc_width: int = 400) -> PanelContainer:
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
	desc_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	desc_lbl.add_theme_color_override("font_color", IVORY)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(desc_width, 0)
	desc_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	desc_lbl.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	v.add_child(desc_lbl)
	return row


func _build_end_turn_button() -> void:
	# Pinned bottom-right, sits beside the HUD strip above the hand. This is the
	# PRIMARY action — the one button the player presses every turn — so unlike
	# the frameless minor buttons it gets a real raised plate (warm ink fill +
	# gilt rim) so it reads unmistakably as "click here to advance." The old
	# frameless gilt text dissolved into the dark board (the button looked
	# absent). Enlarged hit area + 24pt Cinzel so it's the loudest control.
	var btn := Button.new()
	btn.text = "END TURN  [E]"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -210
	btn.offset_top = -244
	btn.offset_right = -20
	btn.offset_bottom = -192
	btn.pressed.connect(_on_end_turn)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_display:
		btn.add_theme_font_override("font", GameTheme.font_display)
	btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.80))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.99, 0.90))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	btn.add_theme_color_override("font_disabled_color", Color(0.66, 0.60, 0.50, 0.55))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	btn.add_theme_constant_override("outline_size", 5)
	btn.add_theme_font_size_override("font_size", 24)  # primary action — loudest control
	# Raised plate styleboxes — the chart document kit (chamfered plate, gilt
	# rule, soft drop shadow), warm ink fill so the primary action stays loud.
	var et_normal := GameTheme.make_panel_style(
		Color(0.14, 0.085, 0.052, 0.96), GameTheme.GILT_BRIGHT, 2, 4, true)
	var et_hover := GameTheme.make_panel_style(
		Color(0.22, 0.13, 0.07, 0.98), Color(1.0, 0.92, 0.62), 2, 4, true)
	var et_pressed := GameTheme.make_panel_style(
		Color(0.10, 0.06, 0.04, 0.98), GameTheme.GILT_BRIGHT, 2, 4, true)
	var et_disabled := GameTheme.make_panel_style(
		Color(0.10, 0.075, 0.06, 0.80), Color(0.45, 0.36, 0.22, 0.55), 2, 4, true)
	btn.add_theme_stylebox_override("normal", et_normal)
	btn.add_theme_stylebox_override("hover", et_hover)
	btn.add_theme_stylebox_override("pressed", et_pressed)
	btn.add_theme_stylebox_override("focus", et_normal)
	btn.add_theme_stylebox_override("disabled", et_disabled)
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


# ═════════════════════════════════════════════════════════════════════════
#  EMOTES — Hearthstone-style canned phrases (solo + skirmish)
#
#  A speech-bubble orb by the player's portrait opens a short menu of set lines.
#  Firing one floats a bubble over your own portrait; in skirmish it also ships
#  EV_EMOTE so the opponent sees the SAME line over your (their-foe) plate. In
#  solo / vs-bot the enemy sometimes barks a menacing reply, so the board never
#  feels one-sided. Presentation only — emotes never touch game state. A short
#  cooldown throttles spam (the Hearthstone squelch, minus the mute button).
# ═════════════════════════════════════════════════════════════════════════

## The lines the player can send. The INDEX is the wire payload (EV_EMOTE.idx),
## so both machines read the same string from this list — keep the order stable.
const EMOTES: Array = [
	"Steel greets steel.",         # greeting
	"Well fought.",                # salute
	"A kindness, remembered.",     # thanks (the ledger never forgets)
	"Etna felt that one.",         # wow
	"Blame the levy.",             # oops (a lord never errs — his conscripts do)
	"You will burn.",              # threat (title drop)
]
## The enemy's answering barks — solo / vs-bot only, chosen at random. A darker
## register than the player's courtly lines (this is a war, and it wants you dead).
const ENEMY_EMOTES: Array = [
	"Kneel.",
	"The meadow is patient.",
	"This ground is mine.",
	"Burn with the rest.",
	"Another lord, another pyre.",
	"Your bones feed the meadow.",
]

var _emote_btn: Button = null
var _emote_menu: Control = null
var _emote_bubble_player: Control = null
var _emote_bubble_foe: Control = null
var _emote_cooldown_until: int = 0   # msec (Time.get_ticks_msec); throttles spam


func _build_emote_button() -> void:
	# Speech orb pinned by the player's portrait (bottom-LEFT), the mirror of the
	# glossary orb bottom-right. Sits just right of the player banner and above the
	# hand strip. Same round gilt-rimmed disc language as the "?" orb.
	const SIZE := 48
	var btn := Button.new()
	btn.name = "EmoteButton"
	btn.text = "…"   # body font renders the ellipsis; reads as "say something"
	btn.anchor_left = 0.0
	btn.anchor_right = 0.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = 232          # just right of the 210px player banner (ends ~x224)
	btn.offset_right = 232 + SIZE
	btn.offset_top = -(SIZE + 220) # bottom lands 220px up — clear of the hand (~-210)
	btn.offset_bottom = -220
	btn.tooltip_text = "Emote"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_body:
		btn.add_theme_font_override("font", GameTheme.font_body)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_font_size_override("font_size", 30)
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
	btn.pressed.connect(_toggle_emote_menu)
	_emote_btn = btn
	_hud_layer.add_child(btn)


func _toggle_emote_menu() -> void:
	if _emote_menu != null and is_instance_valid(_emote_menu):
		_close_emote_menu()
	else:
		_open_emote_menu()


func _open_emote_menu() -> void:
	if _hud_layer == null or (_emote_menu != null and is_instance_valid(_emote_menu)):
		return
	# Never pop the list mid-target: a stray click would resolve the spell/potion.
	if _targeting_spell != null or _targeting_potion_idx >= 0:
		return
	if AudioBank != null:
		AudioBank.play_sfx("button_click", 0.04, -4.0)

	# Full-screen catcher — a click anywhere off the menu dismisses it (and is
	# swallowed so it never leaks to the board underneath).
	var catcher := Control.new()
	catcher.name = "EmoteMenu"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.z_index = 60
	catcher.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_emote_menu()
	)
	_hud_layer.add_child(catcher)
	_emote_menu = catcher

	# The card of lines, stacked above the orb. Manual size so placement doesn't
	# depend on a layout pass (mirrors the codebase's point-anchored UI style).
	const LINE_H := 40.0
	const SEP := 4.0
	const MENU_W := 210.0
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", int(SEP))
	catcher.add_child(panel)
	for i in EMOTES.size():
		var b := Button.new()
		b.text = String(EMOTES[i])
		b.custom_minimum_size = Vector2(MENU_W, LINE_H)
		_style_emote_menu_button(b)
		var idx := i
		b.pressed.connect(func():
			_close_emote_menu()
			_player_emote(idx)
		)
		panel.add_child(b)

	var total_h: float = float(EMOTES.size()) * LINE_H + float(EMOTES.size() - 1) * SEP
	var orb := _emote_btn.get_global_rect() if _emote_btn != null else Rect2(232, 620, 48, 48)
	panel.global_position = Vector2(orb.position.x, orb.position.y - total_h - 8.0)


func _style_emote_menu_button(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if GameTheme.font_body:
		b.add_theme_font_override("font", GameTheme.font_body)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	b.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 3)
	var st := GameTheme.make_panel_style(
		Color(0.10, 0.078, 0.060, 0.97), Color(0.55, 0.45, 0.28, 0.9), 1, 4, true)
	var hov := GameTheme.make_panel_style(
		Color(0.17, 0.11, 0.07, 0.98), GameTheme.GILT_BRIGHT, 1, 4, true)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", st)


func _close_emote_menu() -> void:
	if _emote_menu != null and is_instance_valid(_emote_menu):
		_emote_menu.queue_free()
	_emote_menu = null


## Fire the player's chosen line: float it over our own portrait, then either
## ship it to the real opponent (skirmish) or nudge the AI to bark back (solo).
func _player_emote(idx: int) -> void:
	if idx < 0 or idx >= EMOTES.size():
		return
	var now := Time.get_ticks_msec()
	if now < _emote_cooldown_until:
		return   # throttle — one line every ~2.5s so bubbles never stack/spam
	_emote_cooldown_until = now + 2500
	_show_emote_bubble(false, String(EMOTES[idx]))
	if AudioBank != null:
		AudioBank.play_sfx("button_click", 0.05, -2.0, 1.25)
	if _is_net() and not NetMatch.vs_bot:
		_net_send_emote(idx)          # the real opponent sees it over the wire
	else:
		_maybe_enemy_emote_reply()    # solo / vs-bot: the foe sometimes answers


## Skirmish: tell the opponent which line we sent. Host → event, client → intent,
## the same both-directions channel EV_POTION_FX / EV_DISCARD_FX ride.
func _net_send_emote(idx: int) -> void:
	var msg := {"t": NetMatch.EV_EMOTE, "idx": idx}
	if _is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)


## The opponent sent emote #idx — float their line over the enemy plate.
func _net_show_foe_emote(idx: int) -> void:
	if idx < 0 or idx >= EMOTES.size():
		return
	_show_emote_bubble(true, String(EMOTES[idx]))
	if AudioBank != null:
		AudioBank.play_sfx("button_click", 0.05, -4.0, 1.05)


## Solo / practice only: the foe answers about half the time, after a short beat,
## so emoting isn't shouting into the void — the way Hearthstone's AI bosses talk.
func _maybe_enemy_emote_reply() -> void:
	if phase == Phase.GAME_OVER:
		return
	if randf() > 0.55:
		return
	var line := String(ENEMY_EMOTES[randi() % ENEMY_EMOTES.size()])
	get_tree().create_timer(0.85).timeout.connect(func():
		if not is_instance_valid(self) or phase == Phase.GAME_OVER:
			return
		_show_emote_bubble(true, line)
		if AudioBank != null:
			AudioBank.play_sfx("button_click", 0.05, -4.0, 0.9)
	)


## A speech bubble over a portrait — player's own floats up from the bottom-left
## banner (gilt rim), the foe's drops below the top plate (ember rim). One bubble
## per side at a time (a new line frees the old). Pure presentation; self-frees.
func _show_emote_bubble(is_foe: bool, text: String) -> void:
	if _hud_layer == null or not is_instance_valid(_hud_layer):
		return
	# One speaker, one bubble — clear any line still up on this side.
	var prev: Control = _emote_bubble_foe if is_foe else _emote_bubble_player
	if prev != null and is_instance_valid(prev):
		prev.queue_free()

	var vp: Vector2 = get_viewport_rect().size
	var est_w: float = clampf(float(text.length()) * 11.0 + 30.0, 96.0, 330.0)
	const BUB_H := 48.0

	# Placement + tail direction. The player's plate is bottom-LEFT (bubble floats
	# ABOVE it, tail down). The foe's plate is pinned top-RIGHT with its threat /
	# edict chips stacked directly below it in solo (and the opp-hand fan above it
	# in skirmish) — so the foe bubble sits to the LEFT of the plate, tail pointing
	# right, which clears the furniture in BOTH modes.
	var pos: Vector2      # bubble top-left
	var tail_dir: String  # "down" (you) / "right" (foe by plate) / "up" (opp-hand fallback)
	if is_foe:
		tail_dir = "right"
		if _enemy_hp_label != null and is_instance_valid(_enemy_hp_label):
			var c: Vector2 = _enemy_hp_label.get_global_rect().get_center()
			# Right edge 14px left of the plate (HP label centred in a ~236 plate),
			# vertically centred on the plate; the bubble grows leftward.
			pos = Vector2((c.x - 122.0) - 14.0 - est_w, c.y - BUB_H * 0.5 + 2.0)
		elif _net_opp_hand_box != null and is_instance_valid(_net_opp_hand_box):
			tail_dir = "up"
			var oc: Vector2 = _net_opp_hand_box.global_position \
				+ Vector2(_net_opp_hand_box.size.x * 0.5, 100.0)
			pos = Vector2(oc.x - est_w * 0.5, oc.y)
		else:
			pos = Vector2(vp.x * 0.85 - est_w * 0.5, 150.0)
	else:
		tail_dir = "down"
		if _player_hp_label != null and is_instance_valid(_player_hp_label):
			var c: Vector2 = _player_hp_label.get_global_rect().get_center()
			pos = Vector2(c.x - est_w * 0.5, (c.y - 208.0) - BUB_H * 0.5)
		else:
			pos = Vector2(vp.x * 0.13 - est_w * 0.5, vp.y - 260.0)

	# Keep the whole bubble on-screen (the portraits sit near the screen edges).
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - est_w - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - BUB_H - 8.0))

	var bubble := Control.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 210
	bubble.size = Vector2(est_w, BUB_H)
	bubble.pivot_offset = Vector2(est_w * 0.5, BUB_H * 0.5)
	bubble.global_position = pos
	_hud_layer.add_child(bubble)

	# Body — parchment ink with a rim tinted by speaker (gilt = you, ember = foe),
	# matching the battle log's side colours.
	var rim: Color = Color(0.74, 0.34, 0.24, 0.95) if is_foe else GameTheme.GILT_BRIGHT
	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_stylebox_override("panel",
		GameTheme.make_panel_style(Color(0.10, 0.078, 0.060, 0.97), rim, 2, 7, true))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(body)

	# Tail — a small triangle pointing back at the portrait.
	var tail := Polygon2D.new()
	tail.color = Color(0.10, 0.078, 0.060, 0.97)
	var mx: float = est_w * 0.5
	var my: float = BUB_H * 0.5
	match tail_dir:
		"right":
			tail.polygon = PackedVector2Array([
				Vector2(est_w - 2.0, my - 9.0), Vector2(est_w - 2.0, my + 9.0),
				Vector2(est_w + 13.0, my)])
		"up":
			tail.polygon = PackedVector2Array([
				Vector2(mx - 9.0, 2.0), Vector2(mx + 9.0, 2.0), Vector2(mx, -13.0)])
		_:  # "down"
			tail.polygon = PackedVector2Array([
				Vector2(mx - 9.0, BUB_H - 2.0), Vector2(mx + 9.0, BUB_H - 2.0),
				Vector2(mx, BUB_H + 13.0)])
	bubble.add_child(tail)

	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color",
		Color(1.0, 0.90, 0.84) if is_foe else Color(1.0, 0.96, 0.86))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	bubble.add_child(lbl)

	if is_foe:
		_emote_bubble_foe = bubble
	else:
		_emote_bubble_player = bubble

	# Pop in, hold ~2s, then drift up and fade.
	bubble.scale = Vector2(0.6, 0.6)
	bubble.modulate.a = 0.0
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "scale", Vector2.ONE, UserSettings.anim_time(0.18)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bubble, "modulate:a", 1.0, UserSettings.anim_time(0.14))
	tw.tween_interval(2.0)
	tw.tween_property(bubble, "global_position:y",
		bubble.global_position.y - 22.0, UserSettings.anim_time(0.5)).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(bubble, "modulate:a", 0.0, UserSettings.anim_time(0.5))
	tw.tween_callback(bubble.queue_free)


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
	btn.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)


func _build_relic_display() -> void:
	# Relic grid sits on the LEFT column below the deck+discard piles. The
	# card-hover detail popup moved to the right under the enemy banner —
	# that swap puts active-info (hovered card details) on the right where
	# the eye is reading enemy stats, and persistent-info (your relics) on
	# the left next to your other deck stats. Piles end at y~260; the strip's
	# caption starts just below, the grid under it. A caption in the one rail
	# voice names the cluster — the bare floating grid read as random icons.
	_relic_caption = _make_rail_caption("RELICS")
	_relic_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_relic_caption.anchor_left = 0.0
	_relic_caption.anchor_right = 0.0
	_relic_caption.anchor_top = 0.0
	_relic_caption.anchor_bottom = 0.0
	_relic_caption.offset_left = 16
	_relic_caption.offset_right = 218
	_relic_caption.offset_top = 266
	_relic_caption.offset_bottom = 288
	_relic_caption.visible = false
	_hud_layer.add_child(_relic_caption)
	_relic_panel = GridContainer.new()
	_relic_panel.columns = 3
	_relic_panel.anchor_left = 0.0
	_relic_panel.anchor_right = 0.0
	_relic_panel.anchor_top = 0.0
	_relic_panel.anchor_bottom = 0.0
	_relic_panel.offset_left = 14
	_relic_panel.offset_right = 218
	_relic_panel.offset_top = 292
	_relic_panel.offset_bottom = 292
	_relic_panel.add_theme_constant_override("h_separation", 6)
	_relic_panel.add_theme_constant_override("v_separation", 6)
	_relic_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_relic_panel)
	_refresh_relic_display()


func _refresh_relic_display() -> void:
	for child in _relic_panel.get_children():
		child.queue_free()
	_relic_counter_badges.clear()
	var ids: Array = []
	if _is_net():
		# Skirmish: only the drafted battle relic shows — the campaign's leftover
		# relics never appear in a net fight.
		var slot = _net_my_slot()
		if slot != null:
			for rid in slot.relics:
				if not RelicDB.get_relic(String(rid)).is_empty():
					ids.append(String(rid))
	else:
		for relic_id in RunState.relics:
			if not RelicDB.get_relic(relic_id).is_empty():
				ids.append(relic_id)
	_relic_caption.visible = not ids.is_empty()
	# Adaptive density: chips shrink / columns widen as the hoard grows so the
	# grid never collides with the POTIONS cluster above the player banner
	# (~y 470). Column widths stay clear of the board's left edge (x=272).
	# Rich hover pops any chip back to full readability, so small chips are
	# an index, not the reading copy — same trade StS makes.
	var chip_size := 60
	var cols := 3
	if ids.size() > 20:
		chip_size = 36
		cols = 5
	elif ids.size() > 16:
		chip_size = 40
		cols = 5
	elif ids.size() > 9:
		chip_size = 48
		cols = 4
	_relic_panel.columns = cols
	for relic_id in ids:
		# Ornate tier-glow chip lives in GameTheme so the HUD, shop cards,
		# starting-pick screen, and main-menu relic list all share one frame
		# look (and the StS-style hover pop + tooltip that comes with it).
		var chip := GameTheme.make_relic_chip(relic_id, chip_size)
		_relic_panel.add_child(chip)
		# Counter relics get a live numeral badge across the bottom of the chip.
		if relic_id in COUNTER_RELICS:
			var badge := _make_relic_counter_badge()
			chip.add_child(badge)
			_relic_counter_badges[relic_id] = badge
	_refresh_relic_counters()


# Relics that expose a live counter on their HUD chip. Each maps to a case in
# _relic_counter_text below.
const COUNTER_RELICS := ["pen_nib", "inkpot_of_many",
	"soul_ledger", "stygian_soul", "mana_drunkard", "glowing_hand"]


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
		if not is_equal_approx(_player_hp_bar_target, p_target):
			_player_hp_bar_target = p_target
			if _player_hp_tween != null and _player_hp_tween.is_valid():
				_player_hp_tween.kill()
			_player_hp_tween = p_fill.create_tween()
			_player_hp_tween.tween_property(p_fill, "size:x", p_target, 0.35) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var e_fill = _enemy_hp_label.get_parent().get_node_or_null("Fill")
	if e_fill:
		var e_full: float = e_fill.get_meta("full_w", 204.0)
		var e_target := e_full * clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
		if not is_equal_approx(_enemy_hp_bar_target, e_target):
			_enemy_hp_bar_target = e_target
			if _enemy_hp_tween != null and _enemy_hp_tween.is_valid():
				_enemy_hp_tween.kill()
			_enemy_hp_tween = e_fill.create_tween()
			_enemy_hp_tween.tween_property(e_fill, "size:x", e_target, 0.35) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Always the plain "cur / max" form — a banked surplus reads from cur > max,
	# the lit shelf pips, and the seal tooltip. The old "(+N)" suffix ran twice
	# the wax's width and spilled onto the hand fan.
	_set_seal_readout(_mana_label, "%d / %d" % [player_mana, player_max_mana])
	_update_bank_pips()
	_refresh_hand_affordability()
	_refresh_relic_counters()
	# JUICE: re-evaluate low-HP dread and enemy threat outlines on every HUD
	# refresh (i.e. after every damage / heal / board change).
	_update_low_hp_dread()
	_refresh_threat_flags()
	_refresh_lane_forecast()
	# Round 1 is the muster beat — set your line before the lines clash.
	# IMPORTANT: combat runs EVERY round (there is no setup-only turn), so the
	# copy must NOT imply turn 1 is consequence-free — ending it triggers the
	# first clash. The one-time combat-model tip (fired on first End Turn) and
	# the SWIFT/CLASH phase captions drive that home.
	if round_number == 1:
		_turn_label.text = "Round 1 · Set your line"
	else:
		_turn_label.text = "Round %d" % round_number
	# The primary button names its consequence: ending a turn with ANY creature
	# fielded triggers the simultaneous clash (there is no setup-only round), so
	# the commit moment reads as one. Empty board = a plain END TURN. Net keeps
	# its own DONE label (_net_local_turn_begin owns it there).
	if _end_turn_btn != null and not _is_net():
		_end_turn_btn.text = "CLASH  [E]" if not _all_creatures_both_sides().is_empty() \
			else "END TURN  [E]"
	_update_presence_hp()
	if _deck_count_label:
		_deck_count_label.text = str(_player_draw_pile.size())
	if _discard_count_label:
		_discard_count_label.text = str(_player_discard_pile.size())
	if _exhaust_count_label:
		_exhaust_count_label.text = str(_exhaust_pile.size())
	if _exhaust_box:
		# The exhaust stack only exists on-screen once something has been removed
		# for the fight — so an empty pile never sits there as a mystery.
		_exhaust_box.visible = not _exhaust_pile.is_empty()
	if _gold_label != null and RunState.gold != _gold_displayed:
		_gold_displayed = RunState.gold
		_gold_label.text = str(RunState.gold)
		_punch_label(_gold_label, 1.18)
	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "YOUR TURN"
			_phase_label.add_theme_color_override("font_color", IVORY)
		Phase.RESOLVING:
			# Narrate the sub-phase the loop is in (SWIFT STRIKES / CLASH / THE
			# FALLEN / ENEMY REINFORCES) instead of one flat "FIGHT". _do_combat
			# fills _phase_caption as it advances; fall back to "FIGHT".
			_phase_label.text = _phase_caption if _phase_caption != "" else "FIGHT"
			_phase_label.add_theme_color_override("font_color", Color(1.00, 0.60, 0.25))
		Phase.GAME_OVER:
			pass
	_refresh_combat_process()


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
	tw.tween_property(flash, "color:a", 0.0, UserSettings.anim_time(duration))
	tw.tween_callback(flash.queue_free)


# ─────────────────────────────────────────────────────────────────────────
#  Keyword callouts (LEGIBILITY)
#  The core fix for "combat reads as samey / players ignore effects": when a
#  keyword actually FIRES (Thorns reflects, Armored blocks, Poison kills, a
#  creature Regenerates, a Last Stand saves it), pop a chip that is visually
#  DISTINCT from damage numbers — a dark pill with the keyword's own silhouette
#  icon and a colored keyline — so "THORNS reflected 1" never reads the same as
#  a bare "-1". Per-keyword colour + display label live in one table so every
#  call site stays a one-liner. Purely presentational; no game logic here.
# ─────────────────────────────────────────────────────────────────────────
const _CALLOUT_STYLE := {
	"thorns":     {"col": Color(0.62, 0.86, 0.46), "label": "THORNS"},
	"poison":     {"col": Color(0.58, 0.93, 0.34), "label": "POISON"},
	"armored":    {"col": Color(0.62, 0.80, 1.00), "label": "ARMORED"},
	"shield":     {"col": Color(0.66, 0.86, 1.00), "label": "SHIELD"},
	"last_stand": {"col": Color(1.00, 0.86, 0.30), "label": "LAST STAND"},
	"piercing":   {"col": Color(1.00, 0.58, 0.30), "label": "PIERCING"},
	"regenerate": {"col": Color(0.50, 0.92, 0.60), "label": "REGEN"},
	"wither":     {"col": Color(0.80, 0.58, 0.90), "label": "WITHER"},
	"swift":      {"col": Color(0.58, 0.90, 1.00), "label": "SWIFT"},
	"guardian":   {"col": Color(0.88, 0.80, 0.56), "label": "GUARDIAN"},
	"sacrifice":  {"col": Color(1.00, 0.36, 0.22), "label": "SACRIFICE"},
	"exhaust":    {"col": Color(0.76, 0.70, 0.62), "label": "EXHAUST"},
}
var _active_callouts: Array = []

## Convenience: spawn a keyword callout at `card`, looking up colour/label/icon
## from _CALLOUT_STYLE by keyword id. `suffix` appends a magnitude (" +1", " -2").
func spawn_keyword_callout_kw(card: Control, kw_id: String, suffix: String = "") -> void:
	if card == null or not is_instance_valid(card):
		return
	var style: Dictionary = _CALLOUT_STYLE.get(kw_id,
		{"col": Color(1, 1, 1), "label": kw_id.to_upper()})
	# Visual parity: the host re-broadcasts this callout so the client replays it on
	# the same creature (the client never runs the resolver, so it would otherwise see
	# only the HP delta, not WHY). eid<0 (an unsynced fresh token) can't be matched — skip.
	if _is_host() and int(card.entity_id) >= 0:
		var col: Color = style["col"]
		_net_fx_queue.append({
			"eid": int(card.entity_id), "label": String(style["label"]) + suffix,
			"col": [col.r, col.g, col.b],
		})
	var anchor: Vector2 = card.global_position + Vector2(
		card.size.x * card.scale.x * 0.5, card.size.y * card.scale.y * 0.06)
	log_status(card, String(style["label"]) + suffix)
	spawn_keyword_callout(anchor, String(style["label"]) + suffix,
		style["col"], GameTheme.get_keyword_icon(kw_id))


## Trigger callout for an on-ENTER (battlecry) or on-DEATH (deathrattle) ability.
## Ties the visible result (a card drawn, a creature summoned, the foe's face
## ticking down) back to its CAUSE — the creature that just entered or died.
## Cyan = enter, bone = death, so these read as one family, apart from the
## per-keyword reaction chips. No-ops on an empty label (unmapped effect type).
const _TRIGGER_ENTER_COL := Color(0.42, 0.86, 0.95)  # play-cyan (battlecry)
const _TRIGGER_DEATH_COL := Color(0.86, 0.78, 0.60)  # bone (deathrattle)
func spawn_trigger_callout(global_pos: Vector2, text: String, is_death: bool, eid: int = -1) -> void:
	if text == "":
		return
	var col: Color = _TRIGGER_DEATH_COL if is_death else _TRIGGER_ENTER_COL
	# Visual parity: re-broadcast battlecry/deathrattle labels to the client by eid (the
	# caller passes the firing creature's entity_id). On-enter labels anchor on a live
	# creature and replay; on-death labels usually have no anchor left (the creature's
	# gone from the next snapshot) and are dropped — the death burst already reads it.
	if _is_host() and eid >= 0:
		_net_fx_queue.append({"eid": eid, "label": text, "col": [col.r, col.g, col.b]})
	spawn_keyword_callout(global_pos, text, col, null)


## A styled "a keyword fired" chip — DISTINCT from the bare floating damage
## numbers so the player can read the mechanic, not just the math. Pops in,
## rises, holds long enough to read the word, then fades. Stacks above any
## sibling chips already live near the same anchor so they never overlap.
func spawn_keyword_callout(global_pos: Vector2, text: String, color: Color,
		icon_tex: Texture2D = null) -> void:
	var parent: Node = _hud_layer if _hud_layer != null else self
	_play_keyword_pulse_for(text, global_pos, color)
	_active_callouts = _active_callouts.filter(func(c): return is_instance_valid(c))
	var stack := 0
	for c in _active_callouts:
		if absf(c.position.x - global_pos.x) < 92.0 \
				and absf(c.position.y - global_pos.y) < 70.0:
			stack += 1
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.z_index = 210
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.05, 0.90)
	sb.border_color = Color(color.r, color.g, color.b, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(7)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.content_margin_left = 7
	sb.content_margin_right = 8
	chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	if icon_tex != null:
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.custom_minimum_size = Vector2(18, 18)
		# The keyword device SVGs are 512² — without IGNORE_SIZE the TextureRect
		# adopts that as its minimum and the chip balloons. Pin it to 18px.
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.modulate = Color(color.r, color.g, color.b, 1.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(
		minf(color.r * 1.25, 1.0), minf(color.g * 1.25, 1.0),
		minf(color.b * 1.25, 1.0)))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	lbl.add_theme_constant_override("outline_size", 4)
	if GameTheme.font_title_black != null:
		lbl.add_theme_font_override("font", GameTheme.font_title_black)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	chip.position = global_pos + Vector2(-42, -16 - float(stack) * 30.0)
	chip.scale = Vector2(0.6, 0.6)
	chip.pivot_offset = Vector2(42, 14)
	parent.add_child(chip)
	_active_callouts.append(chip)
	# Center horizontally on the anchor once the container has sized to its text.
	_recenter_callout.call_deferred(chip, global_pos.x)
	var tw := chip.create_tween()
	tw.set_parallel(true)
	tw.tween_property(chip, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "position:y", chip.position.y - 30.0, 0.95) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "modulate:a", 0.0, 0.40) \
		.set_ease(Tween.EASE_IN).set_delay(0.66)
	tw.chain().tween_callback(chip.queue_free)


func _recenter_callout(chip: Control, center_x: float) -> void:
	if is_instance_valid(chip):
		chip.position.x = center_x - chip.size.x * 0.5


func _play_keyword_pulse_for(text: String, global_pos: Vector2, color: Color) -> void:
	var key := text.to_upper()
	var strong := key.begins_with("BLOCKED") or key.begins_with("ARMORED") \
		or key.begins_with("SHIELD") or key.begins_with("PIERCING") \
		or key.begins_with("SACRIFICE") or key.begins_with("EXHAUST")
	if not strong or _hud_layer == null:
		return
	var ring := Line2D.new()
	ring.width = 3.0
	ring.antialiased = true
	ring.z_index = 208
	ring.default_color = Color(color.r, color.g, color.b, 0.74)
	var pts := PackedVector2Array()
	var r := 24.0
	for i in range(33):
		var a := TAU * float(i) / 32.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	ring.points = pts
	ring.position = global_pos
	_hud_layer.add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	var end_scale := Vector2(1.35, 1.35)
	if UserSettings != null and UserSettings.reduce_motion:
		end_scale = Vector2(1.05, 1.05)
	tw.tween_property(ring, "scale", end_scale, 0.28).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


func spawn_floating_number(global_pos: Vector2, text: String, color: Color, big: bool = false) -> void:
	# Floating combat text (damage / heal / gold). Parented to the HUD layer so
	# it survives the source node's death and rides the screen-shake offset.
	# Rises while fading; pops in with a slight back-eased scale.
	var parent: Node = _hud_layer if _hud_layer != null else self
	# Colour-blind: remap the float colour centrally so heal greens read distinct
	# from damage reds under deuteranopia/protanopia (no-op when colorblind is off).
	color = GameTheme.cb_color(color)
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
	tw.tween_property(lbl, "scale", Vector2.ONE, UserSettings.anim_time(0.16)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position:y", lbl.position.y + rise, UserSettings.anim_time(0.72)).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, UserSettings.anim_time(0.72)).set_ease(Tween.EASE_IN).set_delay(UserSettings.anim_time(0.18))
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
	if is_instance_valid(card):
		_log_event("%s falls." % _log_card_ref(card),
			_log_data(card), _log_side(card))
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
	if UserSettings.reduce_motion:
		# Reduce Motion: hold the dread vignette steady instead of the breathing
		# heartbeat pulse. Still signals low HP (informational), no oscillation.
		_set_low_hp_vignette_alpha(0.75)
		return
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
	# low volume, pitched well down so it reads as a muffled heartbeat, not a
	# strike. Rises slightly as HP falls (the vignette peak deepens on the same
	# slide), so the pulse tightens in character near death.
	if AudioBank != null and AudioBank.has_sfx("hit_hero"):
		var urgency: float = clampf(inverse_lerp(0.30, 0.50, _low_hp_vignette_peak), 0.0, 1.0)
		AudioBank.play_sfx("hit_hero", 0.02, -16.0, lerpf(0.52, 0.62, urgency))

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
	_clear_lane_forecast()
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
			# Pass the swing magnitude so the flag shows "this enemy hits for N" —
			# the number reads at a glance without hovering the telegraph.
			if threat:
				c.set_threat_flagged(true, c.effective_atk())
			else:
				c.set_threat_flagged(false)
			# Keep the default-attack chevron in sync with the badge: it hides
			# beneath a threat flag and reappears the moment the flag clears.
			_update_attack_marker(c, String(c.get_meta("current_intent", "ATK")))

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
	# on the hero. Front and back rows attack independently every turn (see
	# _resolve_column_attack) — a back-row enemy reaches face on an open column
	# regardless of its own front partner, so both rows flag here.
	if _player_field[lane] == null and _player_back[lane] == null:
		return true
	return false


func _clear_lane_forecast() -> void:
	for n in _lane_forecast_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_lane_forecast_nodes.clear()


func _refresh_lane_forecast() -> void:
	# Always-on enemy strike read for the planning phase. This reuses the same
	# predictor as the hover arrow so the quiet board-wide chips and the loud
	# hover read can never disagree.
	_clear_lane_forecast()
	if _hud_layer == null:
		return
	if phase != Phase.PLAYER_TURN or not Card2D.board_interactive:
		return
	if _targeting_spell != null or _targeting_potion_idx >= 0:
		return
	if UserSettings != null and not UserSettings.combat_telegraph:
		return
	for row in [ROW_FRONT, ROW_BACK]:
		var arr = _row_array(true, row)
		for lane in range(LANES_PER_ROW):
			var attacker = arr[lane]
			if attacker == null or not is_instance_valid(attacker):
				continue
			if not _forecast_attacker_can_strike(attacker):
				continue
			var read := _predict_lane_strike(attacker)
			if read.is_empty():
				continue
			_add_lane_forecast(attacker, read)


func _forecast_attacker_can_strike(attacker: Control) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	if attacker.has_keyword("structure") or not attacker.can_attack():
		return false
	var intent: String = String(attacker.get_meta("current_intent", "ATK"))
	if not (intent == "ATK" or intent == "CHARGE" or intent == "ENRAGE" \
			or intent.begins_with("CHARGE")):
		return false
	return attacker.effective_atk() > 0


func _add_lane_forecast(attacker: Control, read: Dictionary) -> void:
	var dst: Vector2 = read["point"]
	var danger: Color = Color(1.0, 0.36, 0.20, 0.62) if bool(read.get("face", false)) \
		else Color(1.0, 0.72, 0.34, 0.48)
	if bool(read.get("face", false)):
		_add_lane_forecast_face_marker(dst, read, danger)
		_add_lane_forecast_label(dst, read)
		return

	var src := _card_center(attacker)
	_add_lane_forecast_target_ring(dst, read, danger)
	var line := Line2D.new()
	line.width = 3.0
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 176
	line.default_color = danger
	var mid := (src + dst) * 0.5 + Vector2(0, -22)
	var pts := PackedVector2Array()
	for i in range(13):
		pts.append(_bezier_quad(src, mid, dst, float(i) / 12.0))
	line.points = pts
	_hud_layer.add_child(line)
	_lane_forecast_nodes.append(line)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(-12, -5), Vector2(-12, 5)
	])
	head.color = danger
	head.z_index = 177
	head.position = dst
	if pts.size() >= 2:
		var tangent: Vector2 = pts[pts.size() - 1] - pts[pts.size() - 2]
		if tangent.length_squared() > 0.01:
			head.rotation = tangent.angle()
	_hud_layer.add_child(head)
	_lane_forecast_nodes.append(head)

	_add_lane_forecast_label(dst, read)


func _add_lane_forecast_label(dst: Vector2, read: Dictionary) -> void:
	var label := Label.new()
	label.text = _forecast_chip_text(read)
	label.add_theme_font_size_override("font_size", 19)
	if GameTheme.font_title != null:
		label.add_theme_font_override("font", GameTheme.font_title)
	label.add_theme_color_override("font_color", read.get("color", Color(1, 0.7, 0.3)))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 178
	_hud_layer.add_child(label)
	_lane_forecast_nodes.append(label)
	label.reset_size()
	var s: Vector2 = label.size
	label.position = Vector2(dst.x - s.x * 0.5, dst.y - s.y - 10.0)


func _add_lane_forecast_face_marker(dst: Vector2, read: Dictionary, danger: Color) -> void:
	# Face damage is a lane breakthrough, not a line drawn to the HP widget.
	# Mark the empty column locally so the board says where the blow comes from.
	_add_lane_forecast_target_ring(dst, read, danger)
	var dir := -1.0 if bool(read.get("target_is_enemy", false)) else 1.0
	for i in range(2):
		var chevron := Line2D.new()
		chevron.width = 3.6 - float(i) * 0.8
		chevron.antialiased = true
		chevron.joint_mode = Line2D.LINE_JOINT_ROUND
		chevron.begin_cap_mode = Line2D.LINE_CAP_ROUND
		chevron.end_cap_mode = Line2D.LINE_CAP_ROUND
		chevron.z_index = 177
		chevron.default_color = Color(danger.r, danger.g, danger.b, 0.64 - float(i) * 0.20)
		var step := float(i) * 17.0 * -dir
		chevron.points = PackedVector2Array([
			Vector2(-26, -dir * 12 + step),
			Vector2(0, dir * 16 + step),
			Vector2(26, -dir * 12 + step),
		])
		chevron.position = dst
		_hud_layer.add_child(chevron)
		_lane_forecast_nodes.append(chevron)


func _add_lane_forecast_target_ring(dst: Vector2, read: Dictionary, danger: Color) -> void:
	# A quiet target reticle at the impact point makes the always-on lane forecast
	# readable even when the curved arrow crosses a busy row of cards.
	if _hud_layer == null:
		return
	var radius: float = 34.0 if bool(read.get("face", false)) else 50.0
	var ring := Line2D.new()
	ring.width = 2.5
	ring.antialiased = true
	ring.z_index = 175
	ring.default_color = Color(danger.r, danger.g, danger.b, minf(danger.a + 0.12, 0.72))
	var pts := PackedVector2Array()
	for i in range(41):
		var a := TAU * float(i) / 40.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	ring.position = dst
	_hud_layer.add_child(ring)
	_lane_forecast_nodes.append(ring)

	var cross := Line2D.new()
	cross.width = 2.0
	cross.antialiased = true
	cross.z_index = 176
	cross.default_color = Color(danger.r, danger.g, danger.b, 0.42)
	cross.points = PackedVector2Array([
		Vector2(-radius * 0.54, 0), Vector2(radius * 0.54, 0),
		Vector2(0, 0),
		Vector2(0, -radius * 0.54), Vector2(0, radius * 0.54),
	])
	cross.position = dst
	_hud_layer.add_child(cross)
	_lane_forecast_nodes.append(cross)


func _forecast_chip_text(read: Dictionary) -> String:
	var text := String(read.get("text", ""))
	if bool(read.get("face", false)):
		return "HP -%d" % int(read.get("damage", 0))
	if text.begins_with("-"):
		text = "TAKES %s" % text.substr(1)
	if int(read.get("target_row", ROW_FRONT)) == ROW_BACK:
		return "BACK %s" % text
	return text


func _refresh_hand_affordability() -> void:
	# Tell every card in the hand whether the current mana pool can pay its cost.
	# Card2D handles the visual change (dim when not affordable).
	#
	# Uses _effective_cost so the dim/glow state respects active mutators
	# (Taxed bumps spell cost), Ember Crown (free first spell), and Ironclad
	# Veteran discounts. Previously read raw card_data.cost — a 1-cost spell
	# under Taxed +1 would falsely look affordable at 1 mana and then fail at
	# play time with "Not enough Command!".
	# On the opponent's turn (skirmish) the hand is locked — Card2D.hand_interactive
	# is false — so grey EVERY card rather than showing affordable-looking cards you
	# can't actually play right now. hand_interactive stays true in solo and on your
	# own turn, where per-card Command decides affordability as before.
	var hand_locked: bool = not Card2D.hand_interactive
	for card in _hand:
		if card == null or not is_instance_valid(card):
			continue
		if not card.has_method("set_affordable"):
			continue
		var eff: int = _effective_cost(card)
		card.set_affordable((not hand_locked) and player_mana >= eff)
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
	# Re-arm the cursor-static gate so the next cast rebuilds the arc at least once.
	_targeting_last_mouse = Vector2(-1.0e9, -1.0e9)
	_refresh_combat_process()


func _process(_delta: float) -> void:
	if _targeting_spell != null and _targeting_arrow != null and _targeting_arrow.visible:
		# Skip the whole rebuild (bezier arc + arrowhead + damage-prediction scan)
		# when the cursor is static — the board is frozen on player input, so last
		# frame's arrow/chip still reads correctly.
		var mp := get_viewport().get_mouse_position()
		if not (is_equal_approx(mp.x, _targeting_last_mouse.x) \
				and is_equal_approx(mp.y, _targeting_last_mouse.y)):
			_targeting_last_mouse = mp
			_update_targeting_arrow()
			_update_damage_prediction()
			# Spell targeting owns the screen while active — hide the hover telegraph
			# so the two arrows never fight over the cursor.
			_hide_combat_telegraph()
		return
	_update_combat_telegraph()
	if not _combat_process_needed():
		set_process(false)


func _combat_process_needed() -> bool:
	if _targeting_spell != null and _targeting_arrow != null and _targeting_arrow.visible:
		return true
	if _telegraph_arrow == null:
		return false
	if UserSettings != null and not UserSettings.combat_telegraph:
		return false
	var my_turn: bool = phase == Phase.PLAYER_TURN and Card2D.board_interactive
	var opp_turn: bool = _is_net() and not _net_match_over \
			and _net_active_index != NetMatch.local_player_index \
			and phase != Phase.RESOLVING
	return my_turn or opp_turn


func _refresh_combat_process() -> void:
	set_process(_combat_process_needed())


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
	if not UserSettings.particles:
		return
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


func _lunge_strength(atk: int) -> float:
	# Maps a blow's size to the attacker's lunge drive (Card2D.play_attack_lunge):
	# 2 ATK or less = the historical 26px, HEAVY_HIT_DAMAGE ≈ 1.6×, capped 1.7×.
	return clampf(1.0 + (float(atk) - 2.0) * 0.2, 1.0, 1.7)


func _spawn_impact_burst(global_pos: Vector2, strike_dir: Vector2, power: float,
		lethal: bool) -> void:
	# Contact-point punctuation for a creature strike: a short spark spray at the
	# defender's struck edge, back along the line of the blow. The lunge and
	# tracer say "a strike travelled"; this says "it landed HERE". Heavier blows
	# spray harder; kills flash white-hot. Sparks fall (gravity down) where the
	# ash burst's embers rise — different material, so kills still read distinct.
	if not UserSettings.particles:
		return
	var parent: Node = _hud_layer if _hud_layer != null else self
	var p := CPUParticles2D.new()
	p.position = global_pos
	p.z_index = 216
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(clampf(8.0 + power * 3.0, 8.0, 24.0)) + (10 if lethal else 0)
	p.lifetime = 0.32
	p.direction = -strike_dir.normalized() if strike_dir.length() > 0.01 else Vector2(0, -1)
	p.spread = 55.0
	p.gravity = Vector2(0, 240.0)
	p.initial_velocity_min = 130.0
	p.initial_velocity_max = 240.0 + power * 30.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	p.color = Color(1.0, 0.98, 0.88) if lethal else Color(1.0, 0.86, 0.52)
	p.emitting = true
	parent.add_child(p)
	get_tree().create_timer(p.lifetime + 0.25).timeout.connect(p.queue_free)


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
	# Upgraded damage spells carry a flat dmg_bonus their resolvers add — include it
	# or an upgraded Slash reads "-3" (and never "LETHAL!") while it actually hits 5.
	var plus_dmg: int = int(_targeting_data.get("dmg_bonus", 0))
	var text := ""
	var color := Color(1.0, 0.85, 0.30)
	if spell_type == "damage" or (spell_type == "custom" and custom_id in ["penance", "hex", "pillage", "fuel_the_pyre", "holy_smite", "shove", "slash", "smite_spell", "quick_shot", "last_rites", "slow_match", "banish", "petard"]):
		var dmg: int = _predicted_damage_against(hovered_card, spell_type, custom_id, raw_value, plus_dmg)
		if dmg <= 0:
			_prediction_label.visible = false
			return
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


func _predicted_damage_against(card: Control, spell_type: String, custom_id: String, raw_value: int, plus_dmg: int = 0) -> int:
	# Mirror the relic / armored math from _resolve_spell so the prediction
	# matches the actual outcome. Worn Spellbook adds 1 to plain "damage" and
	# to every direct-damage custom spell that opts in inside
	# _resolve_custom_spell. plus_dmg is the card's "+" upgrade dmg_bonus (the
	# same value each resolver below adds). Armored absorbs 1 per hit (clamped to 0).
	var spell_dmg_bonus: int = 1 if _has_relic("worn_spellbook") else 0
	var dmg := raw_value
	if spell_type == "damage" and _has_relic("worn_spellbook"):
		dmg += 1
	if custom_id == "penance":
		var pen_curse := false
		for hc in _hand:
			if is_instance_valid(hc) and CardDB.is_curse(hc.card_id):
				pen_curse = true
				break
		dmg = (6 if pen_curse else 2) + spell_dmg_bonus + plus_dmg
	elif custom_id == "hex":
		var has_keywords: bool = not card.card_data.get("keywords", []).is_empty()
		dmg = (4 if has_keywords else 1) + plus_dmg
	elif custom_id == "pillage":
		dmg = 2 + spell_dmg_bonus + plus_dmg
	elif custom_id == "shove":
		var can_move: bool = card.current_row == ROW_FRONT \
			and _row_array(true, ROW_BACK)[card.current_lane] == null
		dmg = 0 if can_move or plus_dmg <= 0 else plus_dmg + spell_dmg_bonus
	elif custom_id == "slash":
		var can_blast_move: bool = card.current_row == ROW_FRONT \
			and _row_array(true, ROW_BACK)[card.current_lane] == null
		dmg = 2 + spell_dmg_bonus + plus_dmg + (0 if can_blast_move else 2)
	elif custom_id == "smite_spell":
		dmg = 6 + spell_dmg_bonus + plus_dmg
	elif custom_id == "quick_shot":
		dmg = 1 + spell_dmg_bonus + plus_dmg
	elif custom_id == "slow_match":
		# Base 2 + the banked fuse — the hover must show the TRUE hit
		# (card-honesty rule; the fuse charge is otherwise invisible).
		dmg = 2 + int(_targeting_data.get("fuse", 0)) + spell_dmg_bonus + plus_dmg
	elif custom_id == "petard":
		dmg = 5 + spell_dmg_bonus + plus_dmg
	elif custom_id == "fuel_the_pyre":
		dmg = 999  # Kills target outright (sets up "LETHAL!" automatically)
	elif custom_id == "last_rites":
		# Morbid: 3 base, 6 once a friendly has fallen this fight.
		dmg = (6 if _friendly_deaths_this_fight > 0 else 3) + spell_dmg_bonus + plus_dmg
	elif custom_id == "holy_smite":
		# Equal to the target's missing HP — full creature takes nothing.
		dmg = maxi(3, int(card.card_data.get("hp", card.current_hp)) - int(card.current_hp)) + plus_dmg
	elif custom_id == "banish":
		var limit: int = 4 + plus_dmg
		dmg = card.current_hp if card.current_hp <= limit else limit
	var banish_exiles: bool = custom_id == "banish" and card.current_hp <= 4 + plus_dmg
	if not banish_exiles and card.has_method("has_keyword") and card.has_keyword("armored"):
		# Match Card2D.take_damage: Armored floors damage at 1, never fully negates,
		# so the lethal/non-lethal read can't disagree with the actual hit.
		dmg = maxi(1, dmg - 1)
	return dmg


# ─────────────────────────────────────────────────────────────────────────────
#  COMBAT TELEGRAPH — hover a battlefield creature to read who it strikes and
#  whether the trade kills it. The only forward read the board had was the
#  aggregate INCOMING-face chip; this answers "what happens in THIS lane" before
#  the player commits. Computed with the real combat rules (same-column target
#  priority front→back→face, effective_atk + banners, Armored/Shield/Last Stand).
# ─────────────────────────────────────────────────────────────────────────────

func _build_combat_telegraph() -> void:
	# A slimmer cousin of the spell targeting arrow — quieter ink so it reads as
	# a "preview" rather than an active cast. Parented to the HUD layer; cards
	# live in the board layer but map 1:1 onto it (see _card_center).
	_telegraph_arrow = Line2D.new()
	_telegraph_arrow.width = 4.0
	_telegraph_arrow.antialiased = true
	_telegraph_arrow.joint_mode = Line2D.LINE_JOINT_ROUND
	_telegraph_arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_telegraph_arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_telegraph_arrow.z_index = 235
	_telegraph_arrow.visible = false
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.80, 0.42, 0.30))
	grad.set_color(1, Color(0.96, 0.50, 0.22, 0.92))
	_telegraph_arrow.gradient = grad
	_hud_layer.add_child(_telegraph_arrow)
	_telegraph_head = Polygon2D.new()
	_telegraph_head.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(-16, -7), Vector2(-16, 7)
	])
	_telegraph_head.color = Color(0.96, 0.46, 0.18, 0.95)
	_telegraph_head.z_index = 236
	_telegraph_head.visible = false
	_hud_layer.add_child(_telegraph_head)
	_telegraph_chip = Label.new()
	_telegraph_chip.add_theme_font_size_override("font_size", 26)
	if GameTheme.font_title != null:
		_telegraph_chip.add_theme_font_override("font", GameTheme.font_title)
	_telegraph_chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_telegraph_chip.add_theme_constant_override("outline_size", 6)
	_telegraph_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_telegraph_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_telegraph_chip.z_index = 237
	_telegraph_chip.visible = false
	_hud_layer.add_child(_telegraph_chip)
	_refresh_combat_process()


func _hide_combat_telegraph() -> void:
	_telegraph_hovered = null
	if _telegraph_arrow != null:
		_telegraph_arrow.visible = false
	if _telegraph_head != null:
		_telegraph_head.visible = false
	if _telegraph_chip != null:
		_telegraph_chip.visible = false


func _update_combat_telegraph() -> void:
	# Shows during the player's own turn (solo or net) AND — in a net match — during
	# the OPPONENT's turn, so the player can read the incoming strike before it lands
	# the same way they preview their own. Respects the setting; skip while dragging a
	# card (the drop preview owns the cursor).
	if _telegraph_arrow == null:
		return
	if (UserSettings != null and not UserSettings.combat_telegraph) \
			or Card2D._any_card_dragging:
		_telegraph_last_mouse = Vector2(-1.0e9, -1.0e9)
		_hide_combat_telegraph()
		return
	# My own active turn — the historical gate (solo play and my own net turn both
	# satisfy board_interactive + PLAYER_TURN).
	var my_turn: bool = phase == Phase.PLAYER_TURN and Card2D.board_interactive
	# The opponent's net turn: my board is locked, but the forward read stays useful
	# while they develop. Drop it once the clash actually resolves (the host flips to
	# RESOLVING; the client never does, so its coarse v1 animation keeps a live read).
	var opp_turn: bool = _is_net() and not _net_match_over \
			and _net_active_index != NetMatch.local_player_index \
			and phase != Phase.RESOLVING
	if not (my_turn or opp_turn):
		_telegraph_last_mouse = Vector2(-1.0e9, -1.0e9)
		_hide_combat_telegraph()
		return
	var mouse_pos := get_viewport().get_mouse_position()
	# Skip the entire recompute (hover-scan + strike prediction + curve rebuild) if
	# the cursor hasn't moved since we last resolved — last frame's arrow/chip/hidden
	# state is still correct. The opponent's net turn mutates the board without my
	# cursor, so it always recomputes (the reset above re-arms us on every turn flip).
	if not opp_turn \
			and is_equal_approx(mouse_pos.x, _telegraph_last_mouse.x) \
			and is_equal_approx(mouse_pos.y, _telegraph_last_mouse.y):
		return
	_telegraph_last_mouse = mouse_pos
	var hovered := _find_hovered_battlefield_creature(mouse_pos)
	if hovered == null:
		_hide_combat_telegraph()
		return
	_telegraph_hovered = hovered
	# Resolve who this creature would strike, and the outcome of that strike.
	var read := _predict_lane_strike(hovered)
	if read.is_empty():
		# Nothing to hit this turn (can't attack, or no target + no open column).
		_hide_combat_telegraph()
		return
	var dst: Vector2 = read["point"]
	if bool(read.get("face", false)):
		# Face reads use the lane-local breakthrough marker from the quiet forecast.
		# The loud hover layer only adds the outcome chip; no arrow to the HUD.
		_telegraph_arrow.visible = false
		_telegraph_head.visible = false
		_telegraph_chip.text = read["text"]
		_telegraph_chip.add_theme_color_override("font_color", read["color"])
		_telegraph_chip.visible = true
		_telegraph_chip.size = Vector2.ZERO
		_telegraph_chip.reset_size()
		var face_lbl_size: Vector2 = _telegraph_chip.size
		_telegraph_chip.position = Vector2(
			dst.x - face_lbl_size.x * 0.5, dst.y - face_lbl_size.y - 28)
		return

	var src := _card_center(hovered)
	# Slim curved arrow source→target so it reads as a thrown blow, not a ruler.
	var mid := (src + dst) * 0.5 + Vector2(0, -36)
	var points := PackedVector2Array()
	var steps := 20
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		points.append(_bezier_quad(src, mid, dst, t))
	_telegraph_arrow.points = points
	_telegraph_arrow.visible = true
	_telegraph_head.position = dst
	if points.size() >= 2:
		var tangent: Vector2 = points[points.size() - 1] - points[points.size() - 2]
		if tangent.length_squared() > 0.01:
			_telegraph_head.rotation = tangent.angle()
	_telegraph_head.visible = true
	# Outcome chip, anchored above the target point.
	_telegraph_chip.text = read["text"]
	_telegraph_chip.add_theme_color_override("font_color", read["color"])
	_telegraph_chip.visible = true
	_telegraph_chip.size = Vector2.ZERO
	_telegraph_chip.reset_size()
	var lbl_size: Vector2 = _telegraph_chip.size
	_telegraph_chip.position = Vector2(dst.x - lbl_size.x * 0.5, dst.y - lbl_size.y - 22)


func _find_hovered_battlefield_creature(pos: Vector2) -> Control:
	# Any living creature on either side under the cursor. Both sides are valid
	# so the player can also read what the enemy line will do to them.
	for c in _all_creatures_both_sides():
		if c == null or not is_instance_valid(c):
			continue
		if c.current_hp <= 0:
			continue
		if _is_click_on_card(pos, c):
			return c
	return null


func _predict_lane_strike(attacker: Control) -> Dictionary:
	# Mirror _resolve_column_attack's targeting + the Card2D.take_damage math so
	# the hover read matches the real clash. Returns:
	#   { point: Vector2, text: String, color: Color }  or {} if no strike.
	if attacker == null or not is_instance_valid(attacker):
		return {}
	if not attacker.can_attack():
		# Flooping / structure / stunned / frozen — nothing to telegraph.
		return {}
	var is_enemy: bool = attacker.is_opponent
	var lane: int = attacker.current_lane
	if lane < 0 or lane >= LANES_PER_ROW:
		return {}
	var atk: int = _effective_attack(attacker, lane, is_enemy)
	var opp_is_enemy := not is_enemy
	var opp_front = _row_array(opp_is_enemy, ROW_FRONT)[lane]
	var opp_back = _row_array(opp_is_enemy, ROW_BACK)[lane]
	var target: Control = null
	var target_row := ROW_FRONT
	if opp_front != null and is_instance_valid(opp_front) and opp_front.current_hp > 0:
		target = _redirect_target(opp_front, opp_is_enemy, lane, ROW_FRONT, attacker)
	elif opp_back != null and is_instance_valid(opp_back) and opp_back.current_hp > 0 \
			and not opp_back.has_keyword("structure"):
		target = _redirect_target(opp_back, opp_is_enemy, lane, ROW_BACK, attacker)
		target_row = ROW_BACK
	if target == null or not is_instance_valid(target):
		# Empty opposing column → this attacker swings at the hero face.
		var face_pt := _face_lane_point(opp_is_enemy, lane)
		var color := Color(1.0, 0.40, 0.20) if not is_enemy else Color(1.0, 0.55, 0.30)
		var verb := "FACE" if not is_enemy else "YOUR HP"
		return {
			"point": face_pt,
			"text": "%s -%d" % [verb, atk],
			"color": color,
			"face": true,
			"damage": atk,
			"lane": lane,
			"target_is_enemy": opp_is_enemy,
		}
	# A creature trade — predict the target's HP after this single blow.
	var dmg := _telegraph_damage_to(target, atk)
	var hp_after: int = target.current_hp - dmg
	var text := ""
	var color := Color(0.85, 0.78, 0.55)
	if dmg <= 0:
		text = "NO DMG"
		color = Color(0.70, 0.78, 0.92)
	elif hp_after <= 0:
		# Last Stand survives a lethal blow once.
		if target.has_keyword("last_stand") and not target.last_stand_used:
			text = "LAST STAND"
			color = Color(1.0, 0.85, 0.30)
		else:
			text = "DIES"
			color = Color(1.0, 0.32, 0.22)
	else:
		text = "-%d" % dmg
		color = Color(1.0, 0.55, 0.28)
	return {
		"point": _card_center(target),
		"text": text,
		"color": color,
		"face": false,
		"damage": dmg,
		"target_row": target.current_row,
	}


func _telegraph_damage_to(target: Control, atk: int) -> int:
	# Single-blow damage after the target's mitigation. Mirrors Card2D.take_damage:
	# Shield eats the whole hit; Armored knocks 1 off (2 for the player's own under
	# Fortress Stone); extra_damage adds on. Clamped at 0.
	if target == null or not is_instance_valid(target):
		return 0
	if target.state.has_shield:
		return 0
	var dmg := atk
	if target.has_keyword("armored"):
		dmg = maxi(1, dmg - 1)
	dmg += int(target.card_data.get("extra_damage", 0))
	return maxi(0, dmg)


func _face_lane_point(target_is_enemy: bool, lane: int) -> Vector2:
	# Face damage still comes through a lane. Keep the read on the board edge
	# instead of firing a line into the HUD's HP medallion.
	var slots := _slot_array(target_is_enemy, ROW_FRONT)
	if lane >= 0 and lane < slots.size():
		var slot: Control = slots[lane]
		if slot != null and is_instance_valid(slot) and slot.is_inside_tree():
			var rect := slot.get_global_rect()
			var dir := -1.0 if target_is_enemy else 1.0
			return rect.get_center() + Vector2(0, dir * maxf(42.0, rect.size.y * 0.36))
	return _hero_face_point(target_is_enemy)


func _hero_face_point(target_is_enemy: bool) -> Vector2:
	# Legacy fallback for direct hero-facing effects. Face-strike forecasts use
	# _face_lane_point instead so they stay on the board.
	var lbl: Control = _enemy_hp_label if target_is_enemy else _player_hp_label
	if lbl != null and is_instance_valid(lbl) and lbl.is_inside_tree():
		return lbl.get_global_rect().get_center()
	var vp := get_viewport_rect().size
	return Vector2(vp.x * 0.5, 40.0 if target_is_enemy else vp.y - 220.0)


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
	"fuel_the_pyre": "fire", "petard": "fire",
	# SHOCK — white-blue lightning bolt + brief flash
	"lightning": "shock", "holy_smite": "shock", "time_snare": "shock",
	# BLIGHT — purple drift particles + magenta core
	"dark_pact": "blight", "mass_grave": "blight", "bloodletting": "blight",
	"apocalypse": "blight", "curse": "blight", "unholy_bargain": "blight",
	"blood_tithe": "blight", "grave_robbery": "blight", "offering": "blight",
	"lay_on_hands": "blight", "grave_pact": "blight",   # Unclean Blessing / Last Rites
	# BLESSING — golden upward shimmer + soft warm flash
	"patch_up": "blessing", "mending_light": "blessing",
	"battle_hymn": "blessing", "inspire": "blessing", "war_cry": "blessing",
	"second_wind": "blessing", "shield_wall": "blessing",
	"kings_command": "blessing",
	# EARTH — brown dust + Y-axis screen shake
	"earthquake": "earth", "shove": "earth", "reposition": "earth",
	"cataclysm": "earth", "overwhelming_force": "earth", "barricade": "earth",
	# MIND — pale cool sweep + target outline pulse
	"concentrate": "mind", "adrenaline": "mind", "gambit": "mind",
	"echo_spell": "mind", "banish": "mind", "soul_swap": "mind",
	"provision": "mind", "scrap": "mind", "turbo": "mind",
	"recycle": "mind", "ambush": "mind", "war_chant": "mind", "ricochet": "mind",
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
	if not UserSettings.particles:
		return
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
	if not UserSettings.particles:
		return
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


func _encounter_intro_accent(is_boss: bool) -> Color:
	var faction := _encounter_faction
	if faction == "":
		faction = RunState.get_act_faction()
	if faction != "":
		var fac: Dictionary = HeroDB.faction_info(faction)
		if not fac.is_empty():
			var col: Color = fac.get("color", Color(1.0, 0.74, 0.36))
			return col.lerp(Color.WHITE, 0.20 if is_boss else 0.34)
	return Color(1.0, 0.48, 0.20) if is_boss else Color(1.0, 0.82, 0.36)


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

	var intro_accent := _encounter_intro_accent(is_boss)
	var stage_band := ColorRect.new()
	stage_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_band.offset_top = vp.y * 0.34
	stage_band.offset_bottom = -(vp.y * 0.34)
	stage_band.color = Color(intro_accent.r, intro_accent.g, intro_accent.b, 0.0)
	stage_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_band.z_index = 245
	_hud_layer.add_child(stage_band)
	var top_rule := ColorRect.new()
	top_rule.color = Color(intro_accent.r, intro_accent.g, intro_accent.b, 0.0)
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_rule.z_index = 246
	top_rule.size = Vector2(vp.x * 0.58, 3)
	top_rule.position = Vector2(vp.x * 0.21, vp.y * 0.40)
	_hud_layer.add_child(top_rule)
	var bottom_rule := ColorRect.new()
	bottom_rule.color = Color(intro_accent.r, intro_accent.g, intro_accent.b, 0.0)
	bottom_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_rule.z_index = 246
	bottom_rule.size = Vector2(vp.x * 0.58, 3)
	bottom_rule.position = Vector2(vp.x * 0.21, vp.y * 0.60)
	_hud_layer.add_child(bottom_rule)

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
		prefix_label.text = "— BOSS —" if is_boss else "— GENERAL —"
		prefix_label.add_theme_font_size_override("font_size", 32)
		if GameTheme.font_display:
			prefix_label.add_theme_font_override("font", GameTheme.font_display)
		prefix_label.add_theme_color_override("font_color",
			Color(1.0, 0.52, 0.26) if is_boss else Color(1.0, 0.82, 0.36))
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

	if quick and _encounter_passive_desc == "" and not has_mutator() \
			and not _wave_schedule_active and _pursuit_tier() < 1:
		var identity_label := Label.new()
		identity_label.text = "Break the line. Front guards back."
		identity_label.add_theme_font_size_override("font_size", 18)
		identity_label.add_theme_color_override("font_color", Color(0.92, 0.84, 0.62))
		identity_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		identity_label.add_theme_constant_override("outline_size", 5)
		identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		identity_label.custom_minimum_size = Vector2(vp.x * 0.58, 0)
		identity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(identity_label)

	# Successor Wars: quick intros name the kingdom and its engine (§15.2 —
	# legibility is half the faction work). Tinted with the faction's banner
	# color so the five kingdoms read as different enemies, not just
	# different names.
	if quick and _wave_schedule_active and _encounter_faction != "":
		var fac: Dictionary = HeroDB.faction_info(_encounter_faction)
		if not fac.is_empty():
			var eng_label := Label.new()
			eng_label.text = "%s — %s" % [String(fac.get("name", "")).to_upper(),
				String(fac.get("engine_line", ""))]
			eng_label.add_theme_font_size_override("font_size", 18)
			var fac_col: Color = fac.get("color", Color(0.9, 0.85, 0.8))
			eng_label.add_theme_color_override("font_color", fac_col.lerp(Color.WHITE, 0.55))
			eng_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
			eng_label.add_theme_constant_override("outline_size", 5)
			eng_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			eng_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			eng_label.custom_minimum_size = Vector2(vp.x * 0.6, 0)
			eng_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.add_child(eng_label)

	# Boss/elite preamble — one diegetic line of ill omen, above the mechanical
	# passive. Ambient voice only: never names the unnameable, never references
	# another encounter (each preamble is a standalone card of ill omen). Shown for
	# BOSSES only now — routine General intros stay name-first to cut the text wall.
	if is_boss and _encounter_preamble != "":
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

	# When this encounter posts a passive, the full rule lives LOUD in the
	# standing EDICT banner (built in the HUD, on screen all fight) — so the intro
	# only nods at it with one muted line instead of re-stacking the wall. If
	# there's a desc but no posted edict (no passive_id → no banner), show the rule
	# itself, but small, so the intro never silently drops a threat read.
	# Only when there is NO permanent EDICT banner (no passive_id) does the intro
	# carry the rule — otherwise the standing edict in the HUD already shows it, so
	# the intro no longer re-stacks a redundant "see the posted edict" line.
	if _encounter_passive_desc != "" and (quick or _encounter_passive == ""):
		var rule_tag := Label.new()
		rule_tag.text = _encounter_passive_desc
		rule_tag.add_theme_font_size_override("font_size", 18)
		rule_tag.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55, 0.95))
		rule_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		rule_tag.add_theme_constant_override("outline_size", 4)
		rule_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rule_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule_tag.custom_minimum_size = Vector2(vp.x * 0.6, 0)
		rule_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(rule_tag)

	# Pursuit tag — the road has hardened since the march began. Read before
	# the fight starts, mirrored by the OUTRIDERS banner when the body lands.
	if quick and _pursuit_tier() >= 1:
		var pur_label := Label.new()
		pur_label.text = "OUTRIDERS — extra reinforcement round 2%s." \
			% (" & 4" if _pursuit_tier() >= 2 else "")
		pur_label.add_theme_font_size_override("font_size", 18)
		pur_label.add_theme_color_override("font_color", Color(1.0, 0.52, 0.42))
		pur_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		pur_label.add_theme_constant_override("outline_size", 5)
		pur_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pur_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pur_label.custom_minimum_size = Vector2(vp.x * 0.6, 0)
		pur_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(pur_label)

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
		if quick:
			AudioBank.play_sfx("turn_start", 0.0, 0.0)
		else:
			# Boss/General entrance is a distinct war-horn moment, not just a
			# louder round cue: the boss_intro sting rides over a music dip.
			# While the turn horn stands in for the cue (SFX_FALLBACKS) it plays
			# pitched down so the entrance sounds deeper than a round flip; a
			# real stinger in assets/audio/sfx/boss_intro/ plays straight.
			var horn_pitch: float = 1.0 if AudioBank.has_own_sfx("boss_intro") \
				else (0.68 if is_boss else 0.80)
			AudioBank.play_sfx("boss_intro", 0.0, 3.0, horn_pitch)
			AudioBank.duck_music(-6.0, 1.6 if is_boss else 1.0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dim, "color:a", 0.38 if quick else 0.55, 0.28)
	tw.tween_property(stage_band, "color:a", 0.16 if quick else 0.22, 0.28)
	tw.tween_property(top_rule, "color:a", 0.70 if quick else 0.95, 0.28)
	tw.tween_property(bottom_rule, "color:a", 0.70 if quick else 0.95, 0.28)
	tw.tween_property(holder, "modulate:a", 1.0, 0.32)
	tw.tween_property(holder, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold the intro on screen — bosses get longer for the player to read the
	# passive description; elites are quicker; the quick variant is just long
	# enough to register the one line that matters.
	var hold := 1.5 if is_boss else (0.8 if quick else 1.0)
	if is_boss and _encounter_preamble != "":
		# Give the player time to read the ill-omen line, scaled to its length
		# and capped tight — the heavy passive wall now lives in the standing
		# edict banner, so the intro doesn't need to hold for it. (Bosses only —
		# General intros no longer show the preamble, so they don't hold for it.)
		hold += clampf(_encounter_preamble.length() * 0.022, 1.0, 2.2)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(dim, "color:a", 0.0, 0.32)
	tw.parallel().tween_property(stage_band, "color:a", 0.0, 0.32)
	tw.parallel().tween_property(top_rule, "color:a", 0.0, 0.32)
	tw.parallel().tween_property(bottom_rule, "color:a", 0.0, 0.32)
	tw.parallel().tween_property(holder, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(dim.queue_free)
	tw.parallel().tween_callback(stage_band.queue_free)
	tw.parallel().tween_callback(top_rule.queue_free)
	tw.parallel().tween_callback(bottom_rule.queue_free)
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
	# Generation guard: only THIS message's timer may clear the label. A newer
	# _show_info (or a persistent targeting prompt, which bumps the token) keeps
	# a stale 2s timer from wiping a message the player is still meant to read.
	_info_token += 1
	var my_token := _info_token
	get_tree().create_timer(2.0).timeout.connect(func():
		if _info_token == my_token and _info_label != null:
			_info_label.text = "")


func _set_phase_caption(t: String) -> void:
	# Drive the phase line through the combat sub-phases (SWIFT / CLASH / THE
	# FALLEN / ENEMY REINFORCES). _update_hud's RESOLVING case also reads
	# _phase_caption, so the caption survives a HUD refresh mid-combat.
	var changed: bool = _phase_caption != t
	_phase_caption = t
	if _phase_label != null:
		_phase_label.text = t
		_phase_label.add_theme_color_override("font_color", Color(1.00, 0.60, 0.25))
	if changed:
		_spawn_phase_pulse(t)


func _spawn_phase_pulse(t: String) -> void:
	# A brief center-screen title for sub-phases. The top HUD label changes too,
	# but during a busy clash the eye is on the board; this puts the beat where
	# the action is without pausing or changing combat flow.
	if _hud_layer == null or t == "":
		return
	if is_instance_valid(_phase_pulse_node):
		_phase_pulse_node.queue_free()
	var vp := get_viewport_rect().size
	var accent := _phase_accent(t)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 238
	panel.custom_minimum_size = Vector2(440, 54)
	panel.size = Vector2(440, 54)
	panel.position = Vector2(vp.x * 0.5 - 220.0, vp.y * 0.245)
	panel.pivot_offset = Vector2(220, 27)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.86, 0.86)
	var sb := GameTheme.make_panel_style(
		Color(0.055, 0.040, 0.032, 0.90),
		Color(accent.r, accent.g, accent.b, 0.92),
		2, 4, true, true)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = t
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 27)
	if GameTheme.font_display != null:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.18))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	_hud_layer.add_child(panel)
	_phase_pulse_node = panel

	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.12)
	if UserSettings != null and UserSettings.reduce_motion:
		tw.tween_property(panel, "scale", Vector2.ONE, 0.12)
		tw.chain().tween_interval(0.28)
	else:
		tw.tween_property(panel, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_interval(0.34)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.26).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(panel.queue_free)


func _phase_accent(t: String) -> Color:
	match t:
		"SWIFT STRIKES":
			return Color(0.62, 0.92, 1.0)
		"CLASH":
			return Color(1.0, 0.62, 0.26)
		"THE FALLEN":
			return Color(0.86, 0.34, 0.24)
		"THE DOUBLED HOUR":
			return Color(0.76, 0.58, 1.0)
		"ENEMY REINFORCES":
			return Color(1.0, 0.74, 0.32)
		_:
			return Color(1.0, 0.82, 0.42)


# Balance-telemetry switch: MUST stay false in release. When true, _dbgp() prints
# per-round and per-attack [PACING]/[COMBAT] lines for pacing analysis.
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
			KEY_ESCAPE:
				# Esc backs out one level: cancel an in-flight spell/potion target
				# first, otherwise open the pause/Settings overlay (its own Esc
				# handler closes it again). Glossary + pile viewer already consume
				# Esc up in _input, so they never reach here.
				if _targeting_spell != null:
					_cancel_targeting()
				elif _targeting_potion_idx >= 0:
					_cancel_potion_targeting()
				else:
					GameTheme.open_settings_overlay()
				get_viewport().set_input_as_handled()


# ═════════════════════════════════════════════════════════════════════════
#  ONLINE SKIRMISH — combat networking (docs/MULTIPLAYER_SKIRMISH_PLAN.md §12-13)
#
#  Architecture (v1): HOST-AUTHORITATIVE with FULL BOARD-SNAPSHOT SYNC.
#   • Draw + Command are local per side (each player draws their own deck on
#     their own turn — the existing _start_round machinery, with all relic /
#     mutator / encounter branches inert in net mode).
#   • Placement, on-enter / on-death effects, and the attack clash are computed
#     ONLY on the host. After every authoritative mutation the host pushes a full
#     board snapshot (_net_sync_board); the client reconciles its board to it.
#   • The client never resolves combat — it sends intents and renders snapshots.
#   • Turn model: FULL-ALTERNATING. One active player at a time; on ATTACK the
#     active side strikes the other side one direction, then the turn passes.
#   • entity_id == the card's deck uid for drafted creatures (both machines agree
#     without negotiation); tokens get host-issued ids above any uid.
#
#  v1 scope: CREATURES (place + on-enter + Swift/column/Ranged clash + on-death),
#  SPELLS (curated set, perspective-aware host resolver), match-over, mid-match
#  disconnect, coarse client clash animation. DEFERRED: combat-time floop toggles
#  + reposition (board interaction stays off), exotic pile/draw/Discover spells
#  (denylisted in draft), per-strike clash replay, a dedicated opp-hand widget.
# ═════════════════════════════════════════════════════════════════════════

var _net_opp_hand_count: int = 0


func _net_issue_token_id() -> int:
	var id := _net_token_id_next
	_net_token_id_next += 1
	return id


# ── Match lifecycle ──────────────────────────────────────────────────────

func _net_begin_combat() -> void:
	if _net_signals_wired:
		return
	_net_signals_wired = true
	NetMatch.combat_event_received.connect(_on_net_event)
	if _is_host():
		NetMatch.combat_intent_received.connect(_on_net_intent)
		# Last Stand mirror: the flare fires inside Card2D.take_damage, which only
		# ever runs on the host — install the hook so the save ships to the client
		# via the eid-anchored fx channel (rides the next board sync).
		Card2D.net_last_stand_cb = _net_on_last_stand_saved
	# Mid-match disconnect: bail to the menu rather than hang (plan §15).
	NetMatch.peer_left.connect(func(_id): _net_on_peer_lost())
	NetMatch.host_closed.connect(_net_on_peer_lost)
	# Open-hand spectating: build the face-up "opponent's hand" strip up top now so
	# it's ready when the first EV_HAND_COUNT (which now carries the cards) lands.
	_net_build_opp_hand_ui()
	# Foe's Command seal (mirror of the player's): seed its max from the opponent's
	# slot so it reads "0 / <base>" until their first turn-begin sync, then build it.
	var opp_slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(SkirmishState.opponent_index())
	if opp_slot != null:
		_net_opp_max_mana = opp_slot.base_max_mana
	if _net_opp_mana_post == null:
		_build_command_seal_post(true)
	phase = Phase.PLAYER_TURN
	# ── SEALED ORDERS style: no opener, no Coin — both sides give orders blind,
	# so there is nothing to compensate. Initiative (reveal order + sorcery
	# opener) starts on the seed coin flip and alternates per round. ──
	if _is_sealed():
		_net_initiative = _net_first_player()
		_show_info("Sealed Orders — both lines are set in secret.")
		# Listeners are wired and the scene is built — replay any opening messages
		# the peer sent while we were still booting (see NetMatch.attach_combat).
		NetMatch.attach_combat()
		if _is_host():
			if SkirmishState.vs_bot:
				_bot_refill_hand()
				_bot_sync_hand_display()
				_net_prebake_bot_textures()
			await get_tree().create_timer(0.6).timeout
			_sealed_begin_round(1)
		return
	# Who opens is a COIN FLIP from the shared seed (never "the host"), so gameplay
	# never reveals which side is player 1. The opening experience keys off going
	# first / second, not host / client — both roles are identical and swap with it.
	var first_index: int = _net_first_player()
	var i_go_first: bool = first_index == NetMatch.local_player_index
	if i_go_first:
		# Going first: the opening turn is place-only (no free attack into an empty
		# board); the hand is drawn on turn-start, not pre-dealt.
		_show_info("Skirmish — you have the first move.")
	else:
		# Going second: pre-deal the opening hand NOW so it's readable during the
		# opponent's opener (otherwise the second player stares at an empty hand),
		# at the normal refill PLUS a single Coin — the going-second compensation. A
		# raw extra card proved too strong, so the second player now gets a one-time
		# +1 Command (the Coin) instead. The skip flag stops this side's first
		# _start_round from topping the pre-dealt hand up again.
		_net_set_local_active(false)
		# The pre-deal honours the drafted battle relic (Deep Satchel) — without
		# this, the going-second player's skip-draw flag would push its +1 refill
		# to turn 2 while the going-first player enjoys it from turn 1.
		var predeal: int = HAND_REFILL_TARGET
		if _has_relic("deep_satchel"):
			predeal += int(RelicDB.get_relic("deep_satchel").get("value", 1))
		for _i in predeal:
			draw_one()
		# _draw_card adds the Coin as a synthetic hand card (uid -1) so it never enters
		# a draw/discard pile or reshuffles — it just vanishes once cast.
		_draw_card("coin")
		_net_skip_draw_this_round = true
		_layout_hand()
		# Share the pre-dealt opening hand so the opponent's foe-readout is correct.
		_net_broadcast_hand_count()
		_show_info("Skirmish — your opponent moves first. Plan your opening hand…")
	# Listeners are wired and this side's opening (foe seal + any going-second
	# pre-deal) is done — replay any opening messages the peer sent while we were
	# still booting (texture prebake). Without this, a going-first client that was
	# slow to boot lost the host's very first EV_TURN_BEGIN and both sides
	# deadlocked at round 1 (see NetMatch.attach_combat). Must run BEFORE the host
	# opens round 1, so a buffered client intent is delivered in order.
	NetMatch.attach_combat()
	# Only the HOST drives the authoritative turn machine — but it opens the match for
	# WHOEVER the coin flip chose (first_index), host or client alike.
	if _is_host():
		# Practice bot: deal its opening hand now so the human sees the opponent
		# holding cards through the opener (the +1 going-second card is folded into
		# _bot_refill_hand only when the bot is the side going second — no double draw
		# when its first _bot_take_turn tops the same hand up to the same target), and
		# warm its deck's card faces (fire-and-forget — ready by the bot's first play).
		if SkirmishState.vs_bot:
			_bot_refill_hand()
			_bot_sync_hand_display()
			_net_prebake_bot_textures()
		await get_tree().create_timer(0.6).timeout
		_net_begin_round(1)


## HOST: open a new combat ROUND. Both players take a placement turn (opener first,
## then the other side), each striking one-directionally as its turn ends.
## The coin-flip winner opens EVERY round, so turns strictly alternate
## (P0, P1, P0, P1 …). We used to flip the opener each round — but with a "round"
## being BOTH players' placements, that made whoever placed second also place first
## the next round: two turns back-to-back at every round boundary, which read as a
## confusing "extra turn" (you commit your line and, instead of the foe answering,
## you just go again). Going first is the tempo edge; the going-second player's
## one-time Coin is the compensation — the standard card-game model.
func _net_begin_round(round_no: int) -> void:
	if _net_match_over or not _is_host():
		return
	_net_turn_round = round_no
	_net_first_placer = _net_first_player()   # fixed opener → strict alternation
	_net_placed_count = 0
	_net_open_placement(_net_first_placer)


# ═══════════════════════════════════════════════════════════════════════════
#  SEALED ORDERS battle style (plan §16.2)
#  Round = ORDERS (both place simultaneously in private; the foe sees only
#  face-down ghosts at lane positions) → REVEAL (host seats both bundles,
#  initiative side first) → SORCERY (two sequential open spell steps) →
#  CLASH (_net_run_clash(-1), the verified simultaneous pass). Perfect
#  symmetry: no opener, no Coin. Initiative = seed coin flip, alternates.
# ═══════════════════════════════════════════════════════════════════════════

var _sealed_pending: Array = []      # my uncommitted orders: {id,uid,lane,row,node}
var _sealed_await_foe: bool = false  # I sealed; waiting on the opponent
var _sealed_bundles: Dictionary = {} # HOST: side(int) -> {list:Array, mana:int}
var _sealed_ghosts: Array = []       # the foe's face-down ghosts over my enemy rows
var _net_initiative: int = 0         # reveal order + sorcery opener this round
var _sorcery_active: int = -1        # whose spell step is open (-1 = not in window)
var _sorcery_passes: int = 0


func _is_sealed() -> bool:
	return _is_net() and NetMatch.battle_style == NetMatch.STYLE_SEALED


func _sealed_in_orders() -> bool:
	return _is_sealed() and phase == Phase.PLAYER_TURN \
		and _sorcery_active < 0 and not _sealed_await_foe


## HOST: open a sealed round — both sides give orders at once.
func _sealed_begin_round(round_no: int) -> void:
	if _net_match_over or not _is_host():
		return
	_net_turn_round = round_no
	if round_no <= 1:
		_net_initiative = _net_first_player()
	else:
		_net_initiative = 1 - _net_initiative
	_sealed_bundles.clear()
	_sorcery_active = -1
	_sorcery_passes = 0
	_net_active_index = -1   # nobody "has the turn" — the existing turn gates
							 # (client creature/spell paths) block by construction
	NetMatch.send_to_client({"t": NetMatch.EV_ORDERS_PHASE,
		"round": round_no, "init": _net_initiative})
	# Host-authoritative per-round passives for the CLIENT side (its local
	# _start_round is non-authoritative) — same contract as _net_open_placement.
	_apply_start_round_passives(true)
	_sealed_open_orders_local()
	_net_sync_board()
	if SkirmishState.vs_bot:
		_bot_sealed_orders()


## BOTH machines: enter the orders phase locally (draw + Command + private board).
func _sealed_open_orders_local() -> void:
	phase = Phase.PLAYER_TURN
	_sealed_pending.clear()
	_sealed_await_foe = false
	_sorcery_active = -1
	_moves_used_this_turn = 0
	_net_spells_this_turn = 0
	_start_round()
	Card2D.board_interactive = false   # no reposition drags in sealed v1
	Card2D.hand_interactive = true     # both sides give orders at once
	_refresh_hand_affordability()
	if _end_turn_btn != null:
		_end_turn_btn.disabled = false
		_end_turn_btn.text = "SEAL ORDERS  [E]"
	var init_line: String = "You hold the initiative." \
		if _net_initiative == NetMatch.local_player_index else "The foe holds the initiative."
	_show_combat_banner("SEALED ORDERS", "Set your line in secret — " + init_line,
		Color(0.98, 0.86, 0.55))
	if AudioBank != null:
		AudioBank.play_sfx("turn_start", 0.03, -2.0)
	_show_info("Round %d — orders are sealed until both sides commit." % _net_turn_round)
	_net_broadcast_hand_count()


## A creature play during the orders phase: a PRIVATE commitment. Nothing crosses
## the wire but a face-down ghost at the lane; the bundle ships at SEAL.
func _sealed_commit_creature(card: Control, cost: int, lane_idx: int, row: int) -> void:
	var uid: int = card.deck_uid
	var cid: String = card.card_id
	var data: Dictionary = card.card_data.duplicate(true)
	player_mana -= cost
	_pulse_mana_label(cost)
	_hand.erase(card)
	_hand_container.remove_child(card)
	card.queue_free()
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Display-only stand-in: seats visually + occupies the row array (so a second
	# order can't take the slot) but is NOT registered / entered — the reveal frees
	# it and the authoritative spawn takes its place. _net_sync_board skips it.
	var stand := CARD_SCENE.instantiate()
	stand.card_id = cid
	stand.is_on_battlefield = true
	stand.compact_mode = true
	stand.card_data = data
	stand.current_lane = lane_idx
	stand.current_row = row
	stand.set_meta("sealed_pending", true)
	_row_array(false, row)[lane_idx] = stand
	_slot_set_card(_slot_array(false, row)[lane_idx], stand)
	_play_landing_pop(stand)
	_sealed_pending.append({"id": cid, "uid": uid, "lane": lane_idx, "row": row, "node": stand})
	# The foe learns only WHERE: a face-down ghost at the slot.
	if _is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_ORDER_GHOST, "lane": lane_idx, "row": row})
	else:
		NetMatch.send_intent({"t": NetMatch.IN_ORDER_GHOST, "lane": lane_idx, "row": row})
	_net_broadcast_hand_count()
	_layout_hand()
	_update_hud()


## The foe committed an order at {lane,row} — show a face-down card back there.
func _sealed_show_ghost(lane: int, row: int) -> void:
	if lane < 0 or lane >= LANES_PER_ROW or row < ROW_FRONT or row > ROW_BACK:
		return
	if _net_card_back_tex == null:
		_net_card_back_tex = load("res://assets/ui/card_back.png") as Texture2D
	var slot: Control = _slot_array(true, row)[lane]
	if slot == null or not is_instance_valid(slot) or _net_card_back_tex == null:
		return
	var g := TextureRect.new()
	g.texture = _net_card_back_tex
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.size = Vector2(104, 136)
	g.global_position = slot.get_global_rect().get_center() - g.size * 0.5
	g.z_index = 5
	g.modulate.a = 0.0
	var g_parent: Node = _hud_layer if _hud_layer != null else self
	g_parent.add_child(g)
	var tw: Tween = g.create_tween()
	tw.tween_property(g, "modulate:a", 0.92, 0.2)
	_sealed_ghosts.append(g)


## The button in sealed play: SEAL ORDERS during the orders phase, PASS in sorcery.
func _sealed_on_button() -> void:
	if _net_match_over:
		return
	if _sorcery_active >= 0:
		if _sorcery_active != NetMatch.local_player_index:
			return
		# Cards marked during the open spell step discard as we pass.
		_flush_marked_discards()
		if _end_turn_btn != null:
			_end_turn_btn.disabled = true
		if _is_host():
			_sealed_sorcery_pass(0)
		else:
			NetMatch.send_intent({"t": NetMatch.IN_SORCERY_PASS})
		return
	if _sealed_await_foe or phase != Phase.PLAYER_TURN:
		return
	# Marked discards leave with the sealed orders (hand-local, so the foe
	# learns the count — never the faces — via the fx beat inside the flush).
	_flush_marked_discards()
	_sealed_await_foe = true
	# Orders committed — lock the hand until the reveal / your spell step.
	Card2D.hand_interactive = false
	_refresh_hand_affordability()
	if _end_turn_btn != null:
		_end_turn_btn.disabled = true
		_end_turn_btn.text = "AWAITING THE FOE"
	var list: Array = []
	for p in _sealed_pending:
		list.append({"id": p.id, "uid": p.uid, "lane": p.lane, "row": p.row})
	_show_info("Orders sealed. Awaiting the foe…")
	if _is_host():
		_sealed_store_bundle(0, list, player_mana)
	else:
		NetMatch.send_intent({"t": NetMatch.IN_ORDERS, "list": list, "mana": player_mana})


## HOST: hold a side's sealed bundle; reveal once both are in.
func _sealed_store_bundle(side: int, list: Array, unspent: int) -> void:
	if not _is_host() or _net_match_over:
		return
	if _sealed_bundles.has(side):
		return   # duplicate seal — ignore
	_sealed_bundles[side] = {"list": list, "mana": unspent}
	if _sealed_bundles.size() >= 2:
		await _sealed_reveal()


## HOST: both bundles are in — the orders break open. Initiative side's whole
## bundle seats first (deterministic on-enter order), through the SAME
## authoritative spawn path client plays already use.
func _sealed_reveal() -> void:
	if not _is_host() or _net_match_over:
		return
	phase = Phase.RESOLVING
	NetMatch.send_to_client({"t": NetMatch.EV_REVEAL})
	_sealed_clear_pending_local()
	_show_combat_banner("THE ORDERS BREAK OPEN", "", Color(1.0, 0.78, 0.35))
	if AudioBank != null:
		AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
	_net_cards_played[0] = 0
	_net_cards_played[1] = 0
	for side in [_net_initiative, 1 - _net_initiative]:
		var b: Dictionary = _sealed_bundles.get(side, {})
		# Condottiere reads the caster's unspent pool: the client's rides its
		# bundle; the host's own pool is live in player_mana.
		_net_client_unspent_mana = int(b.get("mana", 0)) if side == 1 else 0
		for o_raw in b.get("list", []):
			var o: Dictionary = o_raw
			var data := CardDB.get_card_data(String(o.get("id", "")))
			if data.is_empty():
				continue
			var lane := int(o.get("lane", -1))
			var row := int(o.get("row", ROW_FRONT))
			if lane < 0 or lane >= LANES_PER_ROW or row < ROW_FRONT or row > ROW_BACK:
				continue
			if _row_array(side == 1, row)[lane] != null:
				continue   # conflicting/stale order — dropped (host is authoritative)
			_net_cards_played[side] += 1
			_net_spawn_creature(data, int(o.get("uid", _net_issue_token_id())),
				lane, row, side == 1, true)
			await _short_pause(0.12)
	_net_sync_board()
	await _short_pause(COMBAT_PAUSE_SHORT)
	if _net_match_over:
		return   # an on-enter chain ended it
	_sealed_open_sorcery()


## BOTH machines: drop my pending stand-ins + the foe's ghosts. The authoritative
## board arrives via the reveal spawns (host) / trailing snapshot (client).
func _sealed_clear_pending_local() -> void:
	for g in _sealed_ghosts:
		if g != null and is_instance_valid(g):
			g.queue_free()
	_sealed_ghosts.clear()
	for p in _sealed_pending:
		var n = p.get("node")
		if n != null and is_instance_valid(n):
			var r: int = int(p.get("row", 0))
			var l: int = int(p.get("lane", 0))
			if _row_array(false, r)[l] == n:
				_row_array(false, r)[l] = null
			n.queue_free()
	_sealed_pending.clear()
	_sealed_await_foe = false


## HOST: open the sorcery window — two sequential open spell steps, initiative first.
## (Sequential, not per-cast alternation: caster-local spells never reach the host,
## so only the explicit PASS can end a step.)
func _sealed_open_sorcery() -> void:
	if not _is_host() or _net_match_over:
		return
	_sorcery_passes = 0
	_sealed_set_sorcery(_net_initiative)
	NetMatch.send_to_client({"t": NetMatch.EV_SORCERY, "who": _net_initiative})
	if SkirmishState.vs_bot and _net_initiative == 1:
		_bot_sealed_sorcery()


## BOTH machines: reflect whose spell step is open.
func _sealed_set_sorcery(who: int) -> void:
	_sorcery_active = who
	phase = Phase.PLAYER_TURN
	_net_active_index = who   # the existing "not your turn" spell gates now work
	var mine: bool = who == NetMatch.local_player_index
	# Only the caster whose spell step is open may play from hand.
	Card2D.hand_interactive = mine
	_refresh_hand_affordability()
	if _end_turn_btn != null:
		_end_turn_btn.disabled = not mine
		_end_turn_btn.text = "PASS  [E]"
	if mine:
		_set_phase_caption("YOUR SPELL STEP")
		_show_info("Your spell step — cast freely over the revealed lines, then pass.")
	else:
		_set_phase_caption("FOE'S SPELL STEP")
		_show_info("The foe weighs its spells…")


## HOST: a side passed its spell step. Second pass → the lines clash.
func _sealed_sorcery_pass(side: int) -> void:
	if not _is_host() or _net_match_over or _sorcery_active != side:
		return
	_sorcery_passes += 1
	if _sorcery_passes >= 2:
		_sorcery_active = -1
		_net_active_index = -1
		await _net_run_clash(-1)
		if not _net_match_over:
			_sealed_begin_round(_net_turn_round + 1)
		return
	var nxt: int = 1 - side
	_sealed_set_sorcery(nxt)
	NetMatch.send_to_client({"t": NetMatch.EV_SORCERY, "who": nxt})
	if SkirmishState.vs_bot and nxt == 1:
		_bot_sealed_sorcery()


## Practice bot, sealed style: build its bundle from the same heuristic the
## alternating bot uses, ping ghosts as it "commits", then seal.
func _bot_sealed_orders() -> void:
	if not SkirmishState.vs_bot or _net_match_over:
		return
	await _short_pause(0.8)
	_bot_refill_hand()
	var mana: int = SkirmishState.BASE_MAX_MANA + _bot_banked_mana
	_bot_sync_hand_display(mana)
	var plays: Array = SkirmishBot.decide_turn(self, _bot_hand, mana)
	var list: Array = []
	var spent := 0
	for intent in plays:
		if String(intent.get("t", "")) != NetMatch.IN_PLAY_CREATURE:
			continue   # v1: the sealed bot fields creatures only
		var lane := int(intent.get("lane", -1))
		var row := int(intent.get("row", ROW_FRONT))
		spent += _bot_consume_card(int(intent.get("uid", -1)))
		_bot_sync_hand_display(mana - spent)
		list.append({"id": String(intent.get("id", "")),
			"uid": int(intent.get("uid", -1)), "lane": lane, "row": row})
		_sealed_show_ghost(lane, row)
		await _short_pause(0.25)
	_bot_banked_mana = clampi(mana - spent, 0, MAX_BANKED_MANA)
	_bot_turns_taken += 1
	await _short_pause(0.5)
	_sealed_store_bundle(1, list, mana - spent)


func _bot_sealed_sorcery() -> void:
	await _short_pause(0.5)
	_sealed_sorcery_pass(1)   # v1: the bot casts no spells in the window


## HOST: open a PLACEMENT turn for `active_index` (0 = host, 1 = client) and tell the
## client. The placer develops their board; ending the turn sends THEIR line across
## the board (one-directional — see _net_finish_placement; round 1 is place-only).
func _net_open_placement(active_index: int) -> void:
	if _net_match_over or not _is_host():
		return
	_net_active_index = active_index
	phase = Phase.PLAYER_TURN
	# Reset the host-side reposition budget so it tracks WHOEVER is active this
	# turn (the host's own turns also reset it via _start_round; this covers the
	# client's turns, where the host validates the client's reposition intents).
	_moves_used_this_turn = 0
	_net_spells_this_turn = 0   # per-turn spell tally (flame_bolt combo)
	_net_last_spell_data = {}   # Echo only reaches back within the current turn
	_net_last_spell_target_eid = -1
	# Per-turn passive counters for the side whose turn is opening (Ironclad's cards-
	# this-turn).
	_net_cards_played[active_index] = 0
	NetMatch.send_to_client({
		"t": NetMatch.EV_TURN_BEGIN, "active": active_index, "round": _net_turn_round,
	})
	if active_index == 0:
		_net_local_turn_begin()
	else:
		_net_set_local_active(false)
		_show_info(_net_opp_turn_msg())
		# Host-authoritative per-round passive recompute for the CLIENT's side — its own
		# _start_round runs non-authoritatively, so the host applies Riteforge/Warchief
		# for Player 2 here and the snapshot below carries the result.
		_apply_start_round_passives(true)
	_net_sync_board()
	# Practice bot: no remote client will send intents for slot 1 — drive it locally.
	if SkirmishState.vs_bot and active_index == 1 and not _net_match_over:
		_bot_take_turn()


## HOST: the active side finished its turn. ALTERNATING battle style — ending
## YOUR turn sends YOUR line across the board (one-directional; the defender
## answers on its own turn). Round 1 is place-only for BOTH sides: the opener
## can't free-hit an empty board, and the second player gets the first
## contested strike on round 2 (alongside the Coin). The both-sides
## simultaneous pass lives on as _net_run_clash(-1) for the SEALED style.
func _net_finish_placement(who: int) -> void:
	if _net_match_over or not _is_host():
		return
	if _net_active_index != who:
		return   # stale / duplicate DONE — ignore
	_net_placed_count += 1
	if _net_turn_round > 1:
		await _net_run_clash(who)
	if _net_match_over:
		return
	if _net_placed_count < 2:
		_net_open_placement(1 - who)
	else:
		_net_begin_round(_net_turn_round + 1)


## Runs on whichever side just became active: draw + Command + enable the board.
func _net_local_turn_begin() -> void:
	_net_set_local_active(true)
	# The handoff is a felt beat, not just an info line: banner sweep + the turn
	# horn. Runs on whichever machine just became active (host 1st-turn included);
	# solo never routes through here.
	_show_combat_banner("YOUR TURN", "", Color(0.98, 0.86, 0.55))
	if AudioBank != null:
		AudioBank.play_sfx("turn_start", 0.03, -2.0)
	# _start_round = the per-turn draw + Command + banking. Its solo-only tail
	# (enemy intents on the mirrored opponent, waves, boss phases) is inert here.
	_start_round()
	# The active player may reposition this turn — _start_round already re-enabled
	# board_interactive.
	Card2D.board_interactive = true
	# The button names its consequence (mirrors solo's CLASH label): from round 2
	# ending your turn sends your line across the board; round 1 is place-only.
	if _end_turn_btn != null:
		_end_turn_btn.text = "STRIKE  [E]" if _net_turn_round > 1 else "DONE  [E]"
	_net_broadcast_hand_count()


## CLIENT: react to the host's turn-begin event.
func _net_client_turn_begin(active: int, rnd: int) -> void:
	_net_active_index = active
	_net_turn_round = rnd
	if active == NetMatch.local_player_index:
		_net_local_turn_begin()
	else:
		_net_set_local_active(false)
		_show_info(_net_opp_turn_msg())


func _net_set_local_active(active: bool) -> void:
	# The active player may reposition their own board creatures (board_interactive);
	# the inactive player's board is locked. Hand plays + spell targeting still
	# route through _input regardless.
	Card2D.board_interactive = active
	# Lock the HAND on the foe's turn: cards can't be lifted (hand_interactive)
	# and _refresh_hand_affordability greys them all, so you can't try to spend
	# Command while it isn't your turn.
	Card2D.hand_interactive = active
	_refresh_hand_affordability()
	if _end_turn_btn != null:
		_end_turn_btn.disabled = not active
	if active:
		phase = Phase.PLAYER_TURN


# ── DONE / CLASH (the end-turn button's skirmish role) ───────────────────

## The DONE button finishes THIS side's placement turn. It no longer attacks — the
## clash is a separate simultaneous pass the host runs once BOTH sides have placed.
func _net_on_done_placing() -> void:
	# Sealed style: the button is SEAL ORDERS / PASS, never a turn hand-off.
	if _is_sealed():
		_sealed_on_button()
		return
	if _net_match_over or _net_active_index != NetMatch.local_player_index:
		return
	# Marked discards cash out as the turn is committed (hand-local; the foe
	# gets the EV_DISCARD_FX beat + hand-count tick from inside the flush).
	_flush_marked_discards()
	if _is_host():
		_net_finish_placement(0)
	else:
		_net_set_local_active(false)
		_show_info("Ready — waiting for the clash…")
		NetMatch.send_intent({"t": NetMatch.IN_END_ACTIONS})


# ── Clash replay log (host → EV_CLASH → client paced replay) ─────────────
#  The client never runs the clash resolver — before this channel it watched the
#  fight as one-frame board snapshots while the host got the full sequenced
#  cinematic (lunges, paced blows, kill cues). While _net_clash_recording is on,
#  the strike funnels log one entry per beat; _net_send_clash_log ships each
#  segment AHEAD of its outcome snapshot so the client replays the fight first
#  and the deaths still flush with the trailing sync (the deferred-deaths feel).
#  Entry shapes: {l} attacker lunge · {a,o,ahp,d,hp,n} creature hit (post-
#  mitigation HP is authoritative — Armored/Shield/Poison math ships pre-solved;
#  ahp carries Thorns/self-bite chip) · {f,fhp,n} face hit by owner index.
var _net_clash_recording: bool = false
var _net_clash_log: Array = []
var _net_clash_banner_sent: bool = false
# Cross-Blitz mutual trade: true only during the MP one-directional MAIN clash, so
# a struck defender hits its attacker straight back (see _apply_mutual_retaliation).
# Solo/sealed are already simultaneous, so this stays false there.
var _net_mutual_retaliation: bool = false


func _net_log_lunge(attacker: Control) -> void:
	if not _net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return   # mid-clash tokens have no eid yet — the snapshot reconciles them
	# "latk" = the swing's weight, so the client's replay lunges with the same
	# drive (effective_atk is close enough to the host's lane-aware value for a
	# purely cosmetic scale).
	var entry := {"l": int(attacker.entity_id)}
	if attacker.has_method("effective_atk"):
		entry["latk"] = int(attacker.effective_atk())
	_net_clash_log.append(entry)


func _net_log_hit(attacker: Control, defender: Control, hp_before: int, is_counter: bool = false) -> void:
	if not _net_clash_recording:
		return
	if defender == null or not is_instance_valid(defender) or int(defender.entity_id) < 0:
		return
	var entry := {
		"d": int(defender.entity_id),
		"hp": int(defender.current_hp),
		"n": maxi(0, hp_before - int(defender.current_hp)),
	}
	if attacker != null and is_instance_valid(attacker) and int(attacker.entity_id) >= 0:
		entry["a"] = int(attacker.entity_id)
		entry["o"] = 1 if attacker.is_opponent else 0
		entry["ahp"] = int(attacker.current_hp)
	# Counter (Cross-Blitz return blow): the victim is the still-lunging attacker, so
	# the client must NOT play a position recoil on it (it would fight the lunge tween
	# and drift the card) — the flash from the hit is enough. See _net_replay_creature_hit.
	if is_counter:
		entry["ctr"] = true
	_net_clash_log.append(entry)


## Log the sub-phase caption the host flips mid-clash (only THE DOUBLED HOUR reaches
## the net clash) so the client's phase line matches instead of going blank.
func _net_log_caption(text: String) -> void:
	if _net_clash_recording:
		_net_clash_log.append({"cap": text})


## Log a piercing kill's skewer so the client draws the same lance. Both eids survive
## the beat (attacker lives through a pierce; victim isn't flushed until the snapshot),
## so the client can reconstruct the lance from its own card centres.
func _net_log_pierce(attacker: Control, victim: Control) -> void:
	if not _net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return
	if victim == null or not is_instance_valid(victim) or int(victim.entity_id) < 0:
		return
	_net_clash_log.append({"pl": int(attacker.entity_id), "pv": int(victim.entity_id)})


## Buffer a floating text callout (e.g. a warden's "+N ATK" pump) onto a creature by
## eid so it replays on the client via the fx channel — the host spawns these at world
## positions the client can't reuse. Rides the next board sync like every other fx.
func _net_fx_text(creature: Control, label: String, color: Color) -> void:
	if not _is_host() or creature == null or not is_instance_valid(creature):
		return
	if int(creature.entity_id) < 0:
		return
	_net_fx_queue.append({
		"eid": int(creature.entity_id), "label": label,
		"col": [color.r, color.g, color.b],
	})


## HOST: a creature just cheated death via Last Stand (Card2D's flare site calls
## this through the net_last_stand_cb static hook). The chip + overbright flare are
## Card2D-local — host screen only — so mirror the moment over the fx channel;
## _net_replay_fx special-cases the label to reproduce the same presentation
## (icon pill + _play_last_stand_flare) on the client's copy of the survivor.
func _net_on_last_stand_saved(card: Control) -> void:
	_net_fx_text(card, "LAST STAND", Color(1.0, 0.85, 0.20))


# Which side is striking in the pass being recorded (-1 = both, simultaneous).
# Shipped with each EV_CLASH so the client's banner names the striker.
var _net_clash_attacking_side: int = -1

func _net_send_clash_log() -> void:
	_net_clash_recording = false
	if _net_clash_log.is_empty():
		return
	if _is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_CLASH,
			"strikes": _net_clash_log.duplicate(true),
			"atk": _net_clash_attacking_side,
			"banner": not _net_clash_banner_sent})
		_net_clash_banner_sent = true
	_net_clash_log.clear()


## HOST: the attack pass. In the both-sides form (-1) every attacker lands its
## blow and a creature slain by the first striker still retaliates (Card2D.defer_deaths
## holds deaths until the phase flushes), so nobody gets a de-facto Swift. This is the
## net analogue of solo's _do_combat clash: Swift pre-phase, main column strike, then
## Ranged. Thorns / Piercing / Armored / Last Stand / Lifelink / Rampage
## / on-death all come free from the shared campaign resolvers.
## Resolve an attack pass. attacking_side: -1 = BOTH sides strike simultaneously
## (the SEALED battle style's resolution + the pre-2026-07 legacy clash);
## 0 (host) / 1 (client) = ONE-DIRECTIONAL — only that side's creatures attack,
## the defender answers on its own turn (the ALTERNATING battle style).
func _net_run_clash(attacking_side: int = -1) -> void:
	if _net_match_over or not _is_host():
		return
	phase = Phase.RESOLVING
	Card2D.board_interactive = false
	if _end_turn_btn != null:
		_end_turn_btn.disabled = true
	if attacking_side < 0:
		_show_info("The lines clash!")
	elif attacking_side == 0:
		_show_info("Your line strikes!")
	else:
		_show_info("The foe's line strikes!")
	# Clash replay: from here every strike beat is logged for the client's paced
	# replay (see the EV_CLASH block above). Recording stays on through each
	# segment's death flush so on-death face chips keep their place in the reel.
	_net_clash_log.clear()
	_net_clash_banner_sent = false
	_net_clash_attacking_side = attacking_side
	_net_clash_recording = true
	# Adjacency current before the strike math reads effective_atk for both warbands.
	_refresh_adjacency_buffs()
	# Stunned/frozen creatures forfeit their swing (can_attack honours is_frozen
	# but not stunned — mirror solo's _do_combat pre-mark). Only sides that will
	# actually swing are pre-marked: marking the passive defender would hand its
	# stunned Twinblades a phantom "already attacked" flag.
	var host_strikes: bool = attacking_side != 1
	var client_strikes: bool = attacking_side != 0
	if host_strikes:
		_net_premark_skip_attack(false)
	if client_strikes:
		_net_premark_skip_attack(true)
	# Cross-Blitz mutual trade (ONE-DIRECTIONAL passes only): a struck defender fires
	# its ATK straight back at its attacker in the same beat, so evenly-matched
	# creatures trade and both fall — matching solo's simultaneous clash instead of
	# handing the turn player a free first-strike kill. Each defender counters ONCE
	# per clash (its single swing); reset the per-clash latch here.
	for c in _all_creatures_both_sides():
		if is_instance_valid(c):
			c.remove_meta("counter_spent_this_clash")
	# Snapshot which columns had a front-row blocker at clash start (face-damage rule).
	# is_enemy=false is the HOST/player side (0); is_enemy=true is the CLIENT side (1).
	var player_front_empty: Array[bool] = []
	var enemy_front_empty: Array[bool] = []
	for i in range(LANES_PER_ROW):
		player_front_empty.append(_row_array(false, ROW_FRONT)[i] == null)
		enemy_front_empty.append(_row_array(true, ROW_FRONT)[i] == null)
	# SWIFT PHASE — striking sides only, deaths HELD so Swift-vs-Swift trades
	# (see _do_combat).
	Card2D.defer_deaths = true
	for lane_idx in range(LANES_PER_ROW):
		if host_strikes:
			await _resolve_swift_attack(lane_idx, ROW_FRONT, false, enemy_front_empty)
		if client_strikes:
			await _resolve_swift_attack(lane_idx, ROW_FRONT, true, player_front_empty)
	for lane_idx in range(LANES_PER_ROW):
		if host_strikes:
			await _resolve_swift_attack(lane_idx, ROW_BACK, false, enemy_front_empty)
		if client_strikes:
			await _resolve_swift_attack(lane_idx, ROW_BACK, true, player_front_empty)
	Card2D.defer_deaths = false
	_cleanup_dead()
	_net_send_clash_log()   # ship the Swift beats AHEAD of their outcome snapshot
	_net_sync_board()   # let the client see the Swift results before the main clash
	_net_clash_recording = true
	# MAIN PASS — striking sides per lane, deaths HELD so mutual kills drop both.
	# In a one-directional pass this is where the Cross-Blitz counterstrike lives:
	# the struck defender hits back inside _creature_attacks_creature (gated below).
	# A both-sides pass (sealed) is already simultaneous, so it stays off there.
	_net_mutual_retaliation = attacking_side >= 0
	Card2D.defer_deaths = true
	for lane_idx in range(LANES_PER_ROW):
		if host_strikes:
			await _resolve_column_attack(lane_idx, ROW_FRONT, false, enemy_front_empty)
		if client_strikes:
			await _resolve_column_attack(lane_idx, ROW_FRONT, true, player_front_empty)
	for lane_idx in range(LANES_PER_ROW):
		if host_strikes:
			await _resolve_column_attack(lane_idx, ROW_BACK, false, enemy_front_empty)
		if client_strikes:
			await _resolve_column_attack(lane_idx, ROW_BACK, true, player_front_empty)
	_net_mutual_retaliation = false
	Card2D.defer_deaths = false
	_cleanup_dead()
	# THE DOUBLED HOUR / Ranged: in a one-directional pass the DEFENDER's armed
	# Doubled Hour must not fire (it swings on its own turn) — stash its flag
	# around the shared helpers. Twinblade + Berserker self-filter (they key on
	# has_attacked_this_turn, which only strikers carry).
	var _dh_stash: bool = false
	if attacking_side >= 0:
		_dh_stash = _doubled_hour[1 - attacking_side]
		_doubled_hour[1 - attacking_side] = false
	await _run_doubled_hour_swing(player_front_empty, enemy_front_empty)
	# Twinblade — second swings (shared helper with solo).
	await _run_twinblade_swings(player_front_empty, enemy_front_empty)
	# Ranged archers reach over the line (side_filter -1 = everyone).
	await _resolve_ranged_attacks(attacking_side)
	await _run_doubled_hour_snipe()
	if attacking_side >= 0:
		_doubled_hour[1 - attacking_side] = _dh_stash
	# Berserker growth — scan both rows on both sides. `grow` = per-attack ATK gain.
	for c in _all_creatures_both_sides():
		if is_instance_valid(c) and c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
			c.current_atk += int(c.card_data.get("grow", 1))
			c.update_stat_display()
	_cleanup_dead()
	# Clear per-turn attack flags so both sides can swing again next round.
	for c in _all_creatures_both_sides():
		if is_instance_valid(c):
			c.has_attacked_this_turn = false
	# Decay per-round temp states (stun, freeze, the Charge! rider, temp Poison).
	# One-directional pass: only the STRIKING side's turn is ending, so only its
	# states expire — the defender's freeze/stun must hold through the strike it
	# was cast to deny. Both-sides pass: everyone's round ends together.
	if host_strikes:
		_net_decay_side_states(false)
	if client_strikes:
		_net_decay_side_states(true)
	# Assassin (dies_end_of_turn): dies when ITS OWN side's turn ends — striking
	# sides only. Collected first so deaths don't mutate the array mid-iterate.
	var _eot_dying: Array = []
	for _ase in _all_creatures_both_sides():
		if not is_instance_valid(_ase):
			continue
		if _ase.card_data.get("passive", "") != "dies_end_of_turn":
			continue
		var _ase_side_strikes: bool = client_strikes if _ase.is_opponent else host_strikes
		if _ase_side_strikes:
			_eot_dying.append(_ase)
	for _ase in _eot_dying:
		if is_instance_valid(_ase):
			_ase.take_damage(999)
	if not _eot_dying.is_empty():
		_cleanup_dead()
	await _short_pause(COMBAT_PAUSE_SHORT)
	_net_send_clash_log()   # ship the main-clash beats AHEAD of the final snapshot
	_update_hud()
	_net_sync_board()
	_net_host_check_match_over()
	# Flow control (whose turn / which round comes next) belongs to the CALLER:
	# the alternating style strikes mid-round at each turn's end, the sealed
	# style clashes once per round — neither wants a round advance baked in here.


## Stunned/frozen creatures forfeit their swing. can_attack() honours is_frozen but
## NOT stunned, so mirror solo's _do_combat pre-mark for the active side here.
func _net_premark_skip_attack(is_enemy: bool) -> void:
	for c in _all_friendly(is_enemy):
		if is_instance_valid(c) and (c.state.stunned or c.state.is_frozen):
			c.has_attacked_this_turn = true


## End-of-turn temp-state decay for ONE side — the full-alternating net analogue of
## solo's _post_combat_cleanup. In net each side attacks on its own turn, so a
## creature's per-turn states expire when ITS side finishes attacking (the moment it
## would have swung): stun, freeze, the Charge! rider, and temp Poison.
func _net_decay_side_states(is_enemy: bool) -> void:
	# Round-scoped side flags (Unclean Blessing / The Doubled Hour) expire with
	# the clash they were cast for.
	_virulence_active[1 if is_enemy else 0] = false
	_doubled_hour[1 if is_enemy else 0] = false
	for c in _all_friendly(is_enemy):
		if not is_instance_valid(c):
			continue
		c.state.stunned = false
		c.state.is_frozen = false
		if c.get_meta("temp_poison", false):
			c.card_data.keywords.erase("poison")
			c.remove_meta("temp_poison")
			c.update_stat_display()
		if c.has_meta("charges_this_turn"):
			c.remove_meta("charges_this_turn")


## HOST: declare the match over if a hero has fallen. Idempotent.
func _net_host_check_match_over() -> void:
	if _net_match_over:
		return
	if player_hp > 0 and enemy_hp > 0:
		return
	# winner by GLOBAL index: host = 0 (player side), client = 1 (enemy side).
	var winner: int = -1
	if player_hp <= 0 and enemy_hp <= 0:
		winner = -1
	elif enemy_hp <= 0:
		winner = 0
	else:
		winner = 1
	NetMatch.send_to_client({"t": NetMatch.EV_MATCH_OVER, "winner": winner})
	_net_sync_board()
	_net_show_result(winner)


func _net_show_result(winner_index: int) -> void:
	if _net_match_over:
		return   # one result per game — guards the Best-of-N tally against double-count
	_net_match_over = true
	phase = Phase.GAME_OVER
	Card2D.board_interactive = false
	if _end_turn_btn != null:
		_end_turn_btn.disabled = true
	# The face-up opponent-hand strip is meaningless once the game is over; hide it
	# so it doesn't sit over the result / rematch panel.
	if _net_opp_hand_box != null and is_instance_valid(_net_opp_hand_box):
		_net_opp_hand_box.visible = false
	var me: int = NetMatch.local_player_index

	# ── Best-of-N series ────────────────────────────────────────────────────
	# Both peers run this symmetrically (host via _net_host_check_match_over, client
	# via the EV_MATCH_OVER event), so record the game on each side; the SkirmishState
	# tally stays in sync. Then either roll into the next game or crown the series.
	if SkirmishState.best_of > 1:
		SkirmishState.record_game_winner(winner_index)
		if SkirmishState.series_leader() == -1:
			_net_show_series_interstitial(winner_index)   # series live → next game
			return
		var series_won := SkirmishState.series_leader() == me
		var sverdict := "SERIES WON" if series_won else "SERIES LOST"
		if _phase_label != null:
			_phase_label.text = sverdict
		_show_info("%s  (%s)  —  rematch, or leave?" % [sverdict, _net_series_score_str()])
		if AudioBank != null:
			AudioBank.play_sfx("victory" if series_won else "defeat")
		_net_build_result_panel(sverdict)
		return

	# ── Single game (Bo1): the original behaviour. ──
	var verdict := "DRAW"
	if winner_index == me:
		verdict = "VICTORY!"
	elif winner_index >= 0:
		verdict = "DEFEAT"
	if _phase_label != null:
		_phase_label.text = verdict
	_show_info(verdict + "  —  rematch with the same decks, or leave?")
	if AudioBank != null:
		AudioBank.play_sfx("victory" if winner_index == me else "defeat")
	# Stay connected: offer a rematch (same drafted decks, fresh HP/board) instead
	# of auto-dropping to the menu. The connection is held open until someone leaves.
	_net_build_result_panel(verdict)


## "You N – M Opponent" from the local player's POV (Best-of-N standing).
func _net_series_score_str() -> String:
	var me: int = NetMatch.local_player_index
	var opp: int = 1 - me
	return "You %d – %d Opponent" % [
		SkirmishState.series_wins[me], SkirmishState.series_wins[opp]]


## A live series game just ended: show this game's verdict + the running score, then
## auto-roll into the next game by driving the SAME rematch handshake both sides use
## (each side flags itself + signals the peer → the host relaunches; HP/board reset
## via NetMatch._enter_combat_local; the kept decks and series tally carry over).
func _net_show_series_interstitial(winner_index: int) -> void:
	var me: int = NetMatch.local_player_index
	var game_verdict := "DRAW"
	if winner_index == me:
		game_verdict = "GAME WON"
	elif winner_index >= 0:
		game_verdict = "GAME LOST"
	if _phase_label != null:
		_phase_label.text = game_verdict
	_show_info("%s  ·  %s  ·  first to %d  —  next game…" % [
		game_verdict, _net_series_score_str(), SkirmishState.games_to_win()])
	if AudioBank != null:
		AudioBank.play_sfx("victory" if winner_index == me else "defeat")
	# Hold the standing on screen, then advance. The host only relaunches once BOTH
	# sides have signalled, so a small clock skew between the two timers is harmless.
	await get_tree().create_timer(2.2).timeout
	if not _net_match_over:
		return   # peer left during the pause; _net_on_peer_lost already handled it
	_net_rematch_local = true
	if _is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_REMATCH})
	else:
		NetMatch.send_intent({"t": NetMatch.IN_REMATCH})
	_net_try_start_rematch()


# ── Rematch (keep both peers connected; replay with the same decks) ──────────

## Build the post-match overlay: a verdict line + REMATCH / LEAVE buttons.
func _net_build_result_panel(verdict: String) -> void:
	if _net_result_panel != null and is_instance_valid(_net_result_panel):
		_net_result_panel.queue_free()
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 14)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = -90
	panel.offset_bottom = 90
	var v_lbl := _make_text_label(verdict, 40, Color(1.0, 0.85, 0.45))
	v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(v_lbl)
	var rematch_btn := Button.new()
	rematch_btn.text = "REMATCH"
	rematch_btn.custom_minimum_size = Vector2(280, 50)
	_style_button(rematch_btn)
	rematch_btn.add_theme_font_size_override("font_size", 22)
	rematch_btn.pressed.connect(_net_request_rematch)
	panel.add_child(rematch_btn)
	var leave_btn := Button.new()
	leave_btn.text = "LEAVE TO MENU"
	leave_btn.custom_minimum_size = Vector2(280, 44)
	_style_button(leave_btn)
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.pressed.connect(_net_leave_to_menu)
	panel.add_child(leave_btn)
	_net_result_panel = panel
	_hud_layer.add_child(panel)


## This side wants a rematch: flag it, tell the peer, and start if both agree.
func _net_request_rematch() -> void:
	if _net_rematch_local:
		return
	# After a decided series, REMATCH starts a FRESH best-of-N (both sides reset
	# symmetrically as each presses; the tally otherwise persists between games).
	if SkirmishState.best_of > 1 and SkirmishState.series_leader() != -1:
		SkirmishState.reset_series()
	_net_rematch_local = true
	if _net_result_panel != null and is_instance_valid(_net_result_panel):
		# Disable the REMATCH button + relabel so the player knows we're waiting.
		for c in _net_result_panel.get_children():
			if c is Button and c.text == "REMATCH":
				c.disabled = true
				c.text = "WAITING FOR OPPONENT…"
	if _is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_REMATCH})
	else:
		NetMatch.send_intent({"t": NetMatch.IN_REMATCH})
	_net_try_start_rematch()


## The peer signalled it wants a rematch.
func _net_on_remote_rematch() -> void:
	_net_rematch_remote = true
	if not _net_rematch_local:
		_show_info("Opponent wants a rematch — press REMATCH to play again.")
	_net_try_start_rematch()


## When BOTH sides want a rematch, the HOST relaunches combat (host-authoritative,
## both peers transition together; _enter_combat_local resets HP + the board).
func _net_try_start_rematch() -> void:
	if not (_net_rematch_local and _net_rematch_remote):
		return
	if _is_host():
		_show_info("Rematch — redrawing the line…")
		NetMatch.launch_combat()


func _net_leave_to_menu() -> void:
	# Dropping the connection bounces the opponent to the menu via peer_left.
	NetMatch.leave()
	GameTheme.fade_out_then_change_scene(self, "res://scenes/main_menu.tscn", 0.5)


# ── Board snapshot (host → client) ───────────────────────────────────────

## HOST: serialize the whole board + both hero HPs and push it to the client.
func _net_sync_board() -> void:
	if not _is_host():
		return
	# This fires after every authoritative mutation, so it's the one place that
	# guarantees the snapshot's per-creature atk (serialised from effective_atk
	# below) reflects current adjacency — for BOTH sides, on the client's screen.
	_refresh_adjacency_buffs()
	var creatures: Array = []
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var arr = _row_array(is_enemy, row)
			for lane in range(LANES_PER_ROW):
				var c = arr[lane]
				if c == null or not is_instance_valid(c) or c.current_hp <= 0:
					continue
				# Sealed-orders stand-ins are PRIVATE commitments — shipping one
				# in a snapshot would leak the order to the foe before the reveal.
				if c.get_meta("sealed_pending", false):
					continue
				if c.entity_id < 0:
					c.entity_id = _net_issue_token_id()
					NetMatch.register_entity(c.entity_id, c)
				creatures.append({
					"eid": c.entity_id,
					"owner": (1 if is_enemy else 0),
					"lane": lane, "row": row,
					"id": String(c.card_id),
					"atk": int(c.effective_atk()),
					"hp": int(c.current_hp),
					"mhp": int(c.card_data.get("hp", c.current_hp)),
					"kw": c.card_data.get("keywords", []),
					"floop": bool(c.will_floop),
					"token": bool(c.is_token),
					# Temp combat states (freeze/stun/shield) — so the client can render
					# WHY one of its creatures isn't swinging, not just that it didn't.
					"frz": bool(c.state.is_frozen),
					"stn": bool(c.state.stunned),
					"shd": bool(c.state.has_shield),
					# Doom countdown — authoritative on the host (the client no longer
					# ticks it locally). -1 for non-doom creatures. maxi(0,…) so a bomb
					# mid-detonation reads 0, never the -999 sentinel.
					"doom": maxi(0, int(c.doom_counter)) if c.has_keyword("doom") else -1,
				})
	NetMatch.send_to_client({
		"t": NetMatch.EV_BOARD_SYNC,
		"creatures": creatures,
		"host_hp": player_hp,
		"client_hp": enemy_hp,
		"active": _net_active_index,
		# Entities removed by exile (Banish) this sync — the client drops them WITHOUT
		# recycling to discard, since an exiled creature is gone, not dead.
		"exiled": _net_exiled_eids.duplicate(),
		# Keyword combat callouts (POISON/THORNS/PIERCING) the host spawned since the
		# last sync — the client replays each on its matching entity for VFX parity.
		"fx": _net_fx_queue.duplicate(),
	})
	_net_exiled_eids.clear()
	_net_fx_queue.clear()


## CLIENT: reconcile the local board to a host snapshot.
func _net_apply_board_sync(ev: Dictionary) -> void:
	var me: int = NetMatch.local_player_index
	var seen: Dictionary = {}
	for cd in ev.get("creatures", []):
		var eid: int = int(cd.get("eid", -1))
		if eid < 0:
			continue
		seen[eid] = true
		var is_enemy_local: bool = int(cd.get("owner", 0)) != me
		var existing = NetMatch.get_entity(eid)
		if existing != null and is_instance_valid(existing):
			_net_update_creature(existing, cd)
		else:
			var data := _net_display_data_from_sync(cd)
			_net_spawn_creature(data, eid, int(cd.get("lane", 0)), int(cd.get("row", 0)), is_enemy_local, false)
	# Entities the host exiled (Banish) this sync — drop these without recycling.
	var exiled: Dictionary = {}
	for e in ev.get("exiled", []):
		exiled[int(e)] = true
	# Drop any creature that vanished from the snapshot (deaths / clears / exile).
	var despawned_n: int = 0
	for eid in NetMatch.entities.keys():
		if seen.has(eid):
			continue
		var node = NetMatch.get_entity(eid)
		if node != null and is_instance_valid(node):
			# Battle log — a vanished creature fell (log BEFORE despawn frees it).
			# Exiled (Banished) creatures skip the "falls" line, same as they skip
			# the death recycle. Tokens read fine here (they have a real name).
			if not exiled.has(eid):
				_log_event("%s falls." % _log_card_ref(node),
					_log_data(node), _log_side(node))
			_net_despawn_creature(node, exiled.has(eid))
			despawned_n += 1
		NetMatch.unregister_entity(eid)
	# Mass-grave parity with the solo clash's 3+-fallen beat: the client's deaths
	# flush here (trailing snapshot), so the heavier shake lands here too.
	if despawned_n >= 3:
		screen_shake(11.0)
	var prev_player_hp: int = player_hp
	var prev_enemy_hp: int = enemy_hp
	if me == 0:
		player_hp = int(ev.get("host_hp", player_hp))
		enemy_hp = int(ev.get("client_hp", enemy_hp))
	else:
		player_hp = int(ev.get("client_hp", player_hp))
		enemy_hp = int(ev.get("host_hp", enemy_hp))
	_net_active_index = int(ev.get("active", _net_active_index))
	_update_hud()
	# Face-damage feedback (the client only learns hero HP from the snapshot).
	# NOTE: a clash's face blows are already applied+logged in _net_replay_face_hit
	# (it sets player_hp/enemy_hp directly), so the delta here is zero for those —
	# this block only fires for NON-clash face damage (spell to face), which is
	# exactly what should be logged here to avoid double-counting the clash.
	if enemy_hp < prev_enemy_hp and _enemy_hp_label != null:
		spawn_floating_number(_enemy_hp_label.get_global_rect().get_center(),
			"-%d" % (prev_enemy_hp - enemy_hp), Color(0.95, 0.5, 0.3), true)
		_log_event("The foe takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
			% [prev_enemy_hp - enemy_hp, maxi(enemy_hp, 0)])
	if player_hp < prev_player_hp:
		screen_shake(7.0)
		if _player_hp_label != null:
			spawn_floating_number(_player_hp_label.get_global_rect().get_center(),
				"-%d" % (prev_player_hp - player_hp), Color(0.95, 0.38, 0.38), true)
		_log_event("You take [color=#e06a50]%d[/color] — [color=#f2e6c8]%d[/color] life left." \
			% [prev_player_hp - player_hp, maxi(player_hp, 0)])
	# VFX parity: replay the host's keyword combat callouts on the matching local
	# entities now that the board is reconciled (survivors are at their final slots).
	_net_replay_fx(ev)


# ── Clash replay (client) ────────────────────────────────────────────────
#  The host streams its clash as a per-strike log (EV_CLASH) AHEAD of the
#  outcome snapshot. Replaying it here gives the watcher the same fight the
#  host saw — lunges, tracers, paced blows, damage numbers, kill cues — instead
#  of a one-frame snap to the result. HP values in the log are authoritative
#  (mitigation pre-solved host-side), so the trailing snapshot reconciles with
#  zero deltas and the deaths still flush with it (despawn + ash burst), which
#  mirrors the host's deferred-deaths rhythm.
var _net_replay_active: bool = false
var _net_event_backlog: Array = []


func _net_replay_clash(ev: Dictionary) -> void:
	_net_replay_active = true
	if bool(ev.get("banner", false)):
		var atk_side: int = int(ev.get("atk", -1))
		if atk_side < 0:
			_show_info("The lines clash!")
		elif atk_side == NetMatch.local_player_index:
			_show_info("Your line strikes!")
		else:
			_show_info("The foe's line strikes!")
	for s_raw in ev.get("strikes", []):
		var s: Dictionary = s_raw
		if s.has("l"):        # attacker wind-up
			var lunger = NetMatch.get_entity(int(s.get("l", -1)))
			if lunger != null and is_instance_valid(lunger) and lunger.has_method("play_attack_lunge"):
				lunger.play_attack_lunge(_lunge_strength(int(s.get("latk", 2))))
			await _short_pause(LUNGE_APEX)
		elif s.has("cap"):    # a mid-clash phase caption (THE DOUBLED HOUR)
			_set_phase_caption(String(s.get("cap", "")))
		elif s.has("pl"):     # a piercing kill's skewer
			_net_replay_pierce(int(s.get("pl", -1)), int(s.get("pv", -1)))
		elif s.has("f"):      # a hero took the blow
			await _net_replay_face_hit(int(s.get("f", 0)), int(s.get("fhp", 0)), int(s.get("n", 0)))
		elif s.has("d"):      # a creature took the blow
			await _net_replay_creature_hit(s)
	_net_replay_active = false
	_net_flush_backlog()


func _net_flush_backlog() -> void:
	while not _net_event_backlog.is_empty():
		if _net_replay_active:
			return   # a queued clash log started a new replay — it owns the flush now
		_net_process_event(_net_event_backlog.pop_front())


func _net_replay_creature_hit(s: Dictionary) -> void:
	var victim = NetMatch.get_entity(int(s.get("d", -1)))
	if victim == null or not is_instance_valid(victim):
		return   # a mid-clash token we never saw — the snapshot reconciles it
	var striker = NetMatch.get_entity(int(s.get("a", -1)))
	var attacker_is_foe: bool = int(s.get("o", 0)) != NetMatch.local_player_index
	var dmg: int = int(s.get("n", 0))
	var hp_after: int = int(s.get("hp", victim.current_hp))
	# Battle log — the client learns each blow only from this replay stream; mirror
	# the host's strike line (counters read "strikes back at", matching
	# _apply_mutual_retaliation). The trailing snapshot logs the resulting deaths.
	if striker != null and is_instance_valid(striker):
		var verb: String = "strikes back at" if bool(s.get("ctr", false)) else "strikes"
		_log_event("%s %s %s for [color=#f2e6c8]%d[/color]." \
			% [_log_card_ref(striker), verb, _log_card_ref(victim), dmg],
			_log_data(striker), _log_side(striker))
	if striker != null and is_instance_valid(striker):
		# Cross-Blitz counter: the striker is the defender biting back — lunge it into
		# the attacker so the return blow reads as a real attack (mirrors the host's
		# will_counter lunge). Forward strikes keep their existing lunge (logged as a
		# separate {l} entry), so only the counter needs one synthesized here.
		if bool(s.get("ctr", false)) and striker.has_method("play_attack_lunge"):
			striker.play_attack_lunge(_lunge_strength(maxi(dmg, 1)))
		_play_attack_tracer(_card_center(striker), _card_center(victim), attacker_is_foe)
		# Thorns / Hydra self-bite: the attacker's own chip rides the same entry.
		if s.has("ahp") and int(s.get("ahp", 0)) < int(striker.current_hp):
			var sting: int = int(striker.current_hp) - int(s.get("ahp", 0))
			striker.current_hp = int(s.get("ahp", 0))
			striker.update_stat_display()
			if striker.has_method("_flash_hit"):
				striker._flash_hit()
			spawn_floating_number(_card_center(striker), "-%d" % sting, Color(0.95, 0.38, 0.38), false)
	victim.current_hp = hp_after
	victim.update_stat_display()
	# Counter blows land on the still-lunging attacker — a position recoil there fights
	# its lunge tween and drifts the card out of its slot (mirrors the host-side guard in
	# _apply_mutual_retaliation). The _flash_hit below still shows the hit. Forward
	# strikes recoil normally (the victim is a static defender).
	if not bool(s.get("ctr", false)) and victim.has_method("play_hit_recoil"):
		victim.play_hit_recoil(attacker_is_foe)
	# Contact-point spark parity with the host's strike path. Power uses the
	# post-mitigation damage (all the log carries) — cosmetic-only divergence
	# from the host's pre-mitigation atk on Armored/Shield hits.
	if striker != null and is_instance_valid(striker):
		_spawn_impact_burst(_card_center(victim),
			_card_center(victim) - _card_center(striker), float(maxi(dmg, 1)), hp_after <= 0)
	if dmg > 0:
		spawn_floating_number(_card_center(victim), "-%d" % dmg, Color(0.95, 0.38, 0.38), false)
	if hp_after > 0:
		# Survivor contract: _flash_hit owns the red punch AND the "hit_creature" cue.
		if dmg > 0 and victim.has_method("_flash_hit"):
			victim._flash_hit()
		await _short_pause(HITSTOP_BEAT if dmg >= HEAVY_HIT_DAMAGE else POST_HIT_BEAT)
	else:
		# Kill contract: the cue sounds at the impact beat; the corpse slumps and
		# stands until the trailing snapshot flushes it — the deferred-deaths feel.
		AudioBank.play_sfx("creature_death", 0.05)
		if victim.has_method("_mark_mortally_struck"):
			victim._mark_mortally_struck()
		screen_shake(6.0)
		await _short_pause(HITSTOP_BEAT)


## CLIENT: redraw a piercing kill's lance from the host's log. Both entities are still
## alive on the board here (the victim is mortally struck but not flushed until the
## trailing snapshot), so the client reconstructs the same skewer + spark from its own
## card centres — the world coords the host drew at are meaningless on a mirrored board.
func _net_replay_pierce(attacker_eid: int, victim_eid: int) -> void:
	var attacker = NetMatch.get_entity(attacker_eid)
	var victim = NetMatch.get_entity(victim_eid)
	if attacker == null or not is_instance_valid(attacker) \
			or victim == null or not is_instance_valid(victim):
		return
	var a := _card_center(attacker)
	var v := _card_center(victim)
	var lance_dir := v - a
	if lance_dir.length() > 1.0:
		var beyond := v + lance_dir.normalized() * 130.0
		_play_pierce_lance(a, beyond)
		spawn_ash_burst(beyond, Color(1.0, 0.86, 0.46), 14)


func _net_replay_face_hit(owner_idx: int, hp_after: int, dmg: int) -> void:
	# Mirrors the juice of damage_player_hero (own face — loud) and
	# damage_enemy_hero (foe face — lighter) for whichever hero the log names.
	var mine: bool = owner_idx == NetMatch.local_player_index
	if mine:
		player_hp = hp_after
		if dmg > 0:
			screen_shake(clampf(8.0 + dmg * 3.4, 10.0, 28.0))
			_play_face_damage_flash(dmg)
			if _player_hp_label != null:
				spawn_floating_number(_player_hp_label.get_global_rect().get_center() + Vector2(0, -6),
					"-%d" % dmg, Color(1.0, 0.28, 0.22), true)
				_punch_label(_player_hp_label, 1.22)
			if AudioBank != null:
				AudioBank.play_sfx("hit_hero")
			_log_event("You take [color=#e06a50]%d[/color] — [color=#f2e6c8]%d[/color] life left." \
				% [dmg, maxi(hp_after, 0)])
	else:
		enemy_hp = hp_after
		if dmg > 0:
			screen_shake(clampf(dmg * 2.0, 4.0, 15.0))
			if _enemy_hp_label != null:
				spawn_floating_number(_enemy_hp_label.get_global_rect().get_center(),
					"-%d" % dmg, Color(1.0, 0.45, 0.2), true)
			if AudioBank != null:
				AudioBank.play_sfx("hit_hero")
			_log_event("The foe takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
				% [dmg, maxi(hp_after, 0)])
	_update_hud()
	await _short_pause(HITSTOP_BEAT if dmg > 0 else POST_HIT_BEAT)


## CLIENT: re-spawn the keyword callouts (POISON/THORNS/PIERCING) the host buffered
## into this snapshot, each on its own creature by entity_id. A callout whose creature
## died this sync has no anchor left — skipped; the death burst already shows the kill.
func _net_replay_fx(ev: Dictionary) -> void:
	for fx in ev.get("fx", []):
		var node = NetMatch.get_entity(int(fx.get("eid", -1)))
		if node == null or not is_instance_valid(node):
			continue
		var c: Array = fx.get("col", [1, 1, 1])
		var col := Color(float(c[0]), float(c[1]), float(c[2])) if c.size() >= 3 else Color(1, 1, 1)
		var anchor: Vector2 = node.global_position + Vector2(
			node.size.x * node.scale.x * 0.5, node.size.y * node.scale.y * 0.06)
		# Battle log — mirror the host's status line (the host logs these via
		# spawn_keyword_callout_kw → log_status; the client re-plays them here).
		log_status(node, String(fx.get("label", "")))
		# Last Stand: reproduce the host's exact presentation — the keyword-icon
		# pill (what _spawn_keyword_chip shows there) plus the overbright flare on
		# the surviving card itself, not just a bare text callout.
		if String(fx.get("label", "")) == "LAST STAND":
			spawn_keyword_callout(anchor, "LAST STAND", col,
				GameTheme.get_keyword_icon("last_stand"))
			if node.has_method("_play_last_stand_flare"):
				node._play_last_stand_flare()
			continue
		spawn_keyword_callout(anchor, String(fx.get("label", "")), col)


func _net_display_data_from_sync(cd: Dictionary) -> Dictionary:
	var base := CardDB.get_card_data(String(cd.get("id", "")))
	var data: Dictionary
	if base.is_empty():
		data = {"id": String(cd.get("id", "token")), "name": "Token", "type": "creature", "cost": 0}
	else:
		data = base.duplicate(true)
	data["atk"] = int(cd.get("atk", data.get("atk", 0)))
	data["hp"] = int(cd.get("mhp", data.get("hp", 1)))
	data["cur_hp"] = int(cd.get("hp", data.get("hp", 1)))
	data["keywords"] = cd.get("kw", data.get("keywords", []))
	# Carry the temp combat states through so a creature that spawns into a frozen/
	# stunned/shielded state on the client renders it (the spawn path reads these).
	for k in ["frz", "stn", "shd"]:
		if cd.has(k):
			data[k] = cd[k]
	return data


func _net_update_creature(node: Control, cd: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Reposition reconcile: if the host says this entity is in a different slot than
	# we have it locally, re-slot it on the correct local side before updating stats.
	var me: int = NetMatch.local_player_index
	var is_enemy_local: bool = int(cd.get("owner", 0)) != me
	var new_lane: int = int(cd.get("lane", node.current_lane))
	var new_row: int = int(cd.get("row", node.current_row))
	if new_lane != node.current_lane or new_row != node.current_row:
		_net_reslot(node, new_lane, new_row, is_enemy_local)
	var old_hp: int = int(node.current_hp)
	var new_hp: int = int(cd.get("hp", node.current_hp))
	node.current_atk = int(cd.get("atk", node.current_atk))
	node.current_hp = new_hp
	# Propagate keyword + max-HP changes (hex/buff) to an already-spawned client
	# node — the spawn path applies these, but the update path used to skip them,
	# leaving the client's glossary/chips stale on a mutated creature.
	node.card_data["keywords"] = cd.get("kw", node.card_data.get("keywords", []))
	node.card_data["hp"] = int(cd.get("mhp", node.card_data.get("hp", new_hp)))
	node.will_floop = bool(cd.get("floop", node.will_floop))
	_net_apply_creature_states(node, cd)
	# Doom counter is host-authoritative (the client no longer ticks it locally, so
	# it can't drift). Flash on a decrement so the bomb still visibly counts down.
	if int(cd.get("doom", -1)) >= 0 and node.has_method("update_doom_display"):
		var old_doom: int = int(node.doom_counter)
		node.doom_counter = int(cd["doom"])
		node.update_doom_display()
		if node.doom_counter < old_doom and old_doom >= 0 and node.has_method("flash_doom_tick"):
			node.flash_doom_tick()
	if node.has_method("update_stat_display"):
		node.update_stat_display()
	if node.has_method("update_floop_display"):
		node.update_floop_display()
	# Snapshots carry only final stats, so animate the delta for clash feel — the
	# client never runs the resolver, this is its only combat feedback (v1 coarse).
	if new_hp < old_hp:
		if node.has_method("play_hit_recoil"):
			node.play_hit_recoil(bool(node.is_opponent))
		spawn_floating_number(_card_center(node), "-%d" % (old_hp - new_hp), Color(0.95, 0.38, 0.38), false)
	elif new_hp > old_hp:
		spawn_floating_number(_card_center(node), "+%d" % (new_hp - old_hp), Color(0.45, 0.9, 0.5), false)


## CLIENT: mirror a creature's temp combat states (freeze / stun / shield) from a
## host snapshot, and pop a one-shot chip when freeze or stun NEWLY turns on so the
## player sees why their creature is about to forfeit a swing. Absent keys preserve
## the current value (host-side spawns omit them — a fresh body defaults to clear).
func _net_apply_creature_states(node: Control, cd: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	var was_frozen: bool = node.state.is_frozen
	var was_stunned: bool = node.state.stunned
	node.state.is_frozen = bool(cd.get("frz", node.state.is_frozen))
	node.state.stunned = bool(cd.get("stn", node.state.stunned))
	node.state.has_shield = bool(cd.get("shd", node.state.has_shield))
	if node.has_method("_spawn_keyword_chip"):
		if node.state.is_frozen and not was_frozen:
			node._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
		elif node.state.stunned and not was_stunned:
			node._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))


## CLIENT: relocate an already-spawned creature to a new slot to match a host
## snapshot (the visible half of a reposition). Clears the old board-array cell,
## re-parents into the destination slot on the correct local side.
func _net_reslot(node: Control, new_lane: int, new_row: int, is_enemy_local: bool) -> void:
	if new_lane < 0 or new_lane >= LANES_PER_ROW or new_row < ROW_FRONT or new_row > ROW_BACK:
		return
	var old_arr = _row_array(is_enemy_local, node.current_row)
	if node.current_lane >= 0 and node.current_lane < old_arr.size() and old_arr[node.current_lane] == node:
		old_arr[node.current_lane] = null
	node.current_lane = new_lane
	node.current_row = new_row
	_reset_card_after_drag(node)
	_slot_set_card(_slot_array(is_enemy_local, new_row)[new_lane], node)
	_row_array(is_enemy_local, new_row)[new_lane] = node
	_play_landing_pop(node)


func _net_despawn_creature(node: Control, exiled: bool = false) -> void:
	# A creature vanished from the host's authoritative snapshot — for the local
	# player's OWN board cards that means death, so recycle them into the discard
	# pile exactly as the solo death pipeline does (see line ~9878). The host
	# already discards its own fallen creatures via _cleanup_dead; this is the
	# client-side mirror so BOTH warbands' decks cycle their creatures across a
	# long match. Tokens/summons (deck_uid < 0) and the opponent's creatures
	# (tracked in their own deck, on their own machine) are skipped — and so is an
	# EXILED creature (Banish removes it from the game, it does not go to discard).
	if not exiled and is_instance_valid(node) and not node.is_opponent and node.deck_uid >= 0:
		_player_discard_pile.append(_pile_entry(node.card_id, node.deck_uid))
	for is_enemy in [false, true]:
		for row in [ROW_FRONT, ROW_BACK]:
			var arr = _row_array(is_enemy, row)
			for lane in range(LANES_PER_ROW):
				if arr[lane] == node:
					arr[lane] = null
	if is_instance_valid(node):
		spawn_ash_burst(_card_center(node), Color(0.62, 0.60, 0.66), 18)
		node.queue_free()


## Materialize a board creature from card data on a given side. On the host
## (run_on_enter=true) the on-enter fires authoritatively; on the client it never
## does (the client only renders the snapshot the host already resolved).
func _net_spawn_creature(data: Dictionary, entity_id: int, lane: int, row: int,
		is_enemy_side: bool, run_on_enter: bool) -> Control:
	var card = CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", ""))
	card.is_opponent = is_enemy_side
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data.duplicate(true)
	card.entity_id = entity_id
	card.deck_uid = entity_id if entity_id < _net_token_id_base() else -1
	card.current_lane = lane
	card.current_row = row
	if is_enemy_side:
		_row_array(true, row)[lane] = card
		var slot = _slot_array(true, row)[lane]
		_slot_set_card(slot, card)
		card.destroyed.connect(_on_card_destroyed.bind(card))
		card.will_die.connect(_on_card_will_die.bind(card))
		_play_landing_pop(card)
	else:
		_place_card_in_slot(card, lane, row, Vector2.ZERO, false)
	# Card2D._ready inits stats from card_data on add_child; override with the
	# exact atk / current-hp the caller specified (covers buffed/damaged sync).
	if data.has("atk"):
		card.current_atk = int(data["atk"])
	if data.has("cur_hp"):
		card.current_hp = int(data["cur_hp"])
	elif data.has("hp"):
		card.current_hp = int(data["hp"])
	_net_apply_creature_states(card, data)
	card.update_stat_display()
	NetMatch.register_entity(entity_id, card)
	# Battle log — a genuine hand placement (drafted creatures have entity_id ==
	# deck_uid < the token base; summoned tokens are ≥ it and don't log a "fields"
	# line, matching solo). This single hook covers the client's own + foe plays
	# (both arrive via board sync) AND the host's view of the foe's play (applied
	# via _net_apply_remote_creature). The host's OWN play logs in _play_creature.
	if entity_id < _net_token_id_base():
		if is_enemy_side:
			_log_event("The foe fields %s." % _log_card_ref(card),
				_log_data(card), _log_side(card))
		else:
			_log_event("You field %s." % _log_card_ref(card),
				_log_data(card), _log_side(card))
	if run_on_enter:
		KeywordEffects.dispatch_on_enter(card, lane, is_enemy_side, self)
		if card.card_data.has("on_play"):
			_resolve_on_play_ability(card, lane, is_enemy_side)
		# Enter-with-a-bonus passives for this side (Ironclad / Hexblade / Warchief /
		# Tallow / Standard Bearer) — run for the client's creatures too, reading the
		# client's per-side counters (the solo path only ran them for the host's plays).
		_apply_play_time_passives(card, is_enemy_side)
	return card


func _net_token_id_base() -> int:
	return 1000000


# ── Intents (client → host) ──────────────────────────────────────────────

# A client creature play now animates (the same hand-fan arc the bot gets),
# which suspends intent processing for the flight. Intents arriving mid-flight
# queue here and apply FIFO after — without this, an IN_END_ACTIONS racing the
# flight would end the turn and silently DROP the animated play (the client
# already paid Command and discarded the card → board desync). Mirrors the
# client's _net_event_backlog contract.
var _net_intent_busy: bool = false
var _net_intent_backlog: Array = []

func _on_net_intent(sender_id: int, intent: Dictionary) -> void:
	if not _is_host():
		return
	# Rematch requests arrive AFTER the match is over — handle them before the
	# match-over gate below (which would otherwise swallow them).
	if String(intent.get("t", "")) == NetMatch.IN_REMATCH:
		_net_on_remote_rematch()
		return
	if _net_match_over:
		return
	if _net_intent_busy:
		_net_intent_backlog.append(intent)
		return
	_net_intent_busy = true
	await _net_process_intent(intent)
	while not _net_intent_backlog.is_empty():
		if _net_match_over:
			_net_intent_backlog.clear()
			break
		await _net_process_intent(_net_intent_backlog.pop_front())
	_net_intent_busy = false


func _net_process_intent(intent: Dictionary) -> void:
	match String(intent.get("t", "")):
		NetMatch.IN_PLAY_CREATURE:
			# animate=true — a human opponent's play arcs from the foe's hand fan,
			# the same ceremony the bot already had. The ghost bails headless, so
			# probe-driven intents resume synchronously.
			await _net_apply_remote_creature(intent, true)
		NetMatch.IN_PLAY_SPELL:
			_net_apply_remote_spell(intent)
		NetMatch.IN_REPOSITION:
			_net_apply_remote_reposition(intent)
		NetMatch.IN_USE_POTION:
			# The client drank a host-authoritative potion. Apply it to the
			# client's side (enemy side from the host's view) + re-sync. A targeted
			# bottle carries its target as an entity_id.
			var pid := String(intent.get("pid", ""))
			if pid != "":
				var pot_target: Control = null
				var pot_eid: int = int(intent.get("target", -1))
				if pot_eid >= 0:
					var pn = NetMatch.get_entity(pot_eid)
					if pn != null and is_instance_valid(pn):
						pot_target = pn
				_net_apply_host_potion(pid, true, pot_target)
				_net_sync_board()
			elif String(intent.get("effect", "")) == "heal_hp":
				# Legacy payload shape from the first net-potion pass.
				_net_heal_hero(true, int(intent.get("value", 8)))
				_net_sync_board()
		NetMatch.IN_END_ACTIONS:
			if _net_active_index == 1:
				_net_finish_placement(1)
		NetMatch.IN_CHOICE:
			# The client picked an option for its own Copycat / Adaptable — apply + sync.
			_net_apply_client_choice(intent)
		NetMatch.IN_ORDERS:
			# Sealed style: the client's whole creature bundle. Awaited so the
			# reveal (once both bundles are in) sequences ahead of queued intents.
			await _sealed_store_bundle(1, intent.get("list", []), int(intent.get("mana", 0)))
		NetMatch.IN_ORDER_GHOST:
			_sealed_show_ghost(int(intent.get("lane", -1)), int(intent.get("row", 0)))
		NetMatch.IN_SORCERY_PASS:
			_sealed_sorcery_pass(1)
		NetMatch.EV_HAND_COUNT:
			_net_opp_hand_count = int(intent.get("n", 0))
			_net_refresh_opp_hand()
			_net_set_opp_mana(int(intent.get("mana", _net_opp_mana)),
				int(intent.get("maxmana", _net_opp_max_mana)))
		NetMatch.EV_DISCARD_FX:
			# The client threw cards away at its turn commit — show the beat.
			_net_show_foe_discard_fx(int(intent.get("n", 0)))
		NetMatch.EV_POTION_FX:
			# The client drank a potion — show the drink beat over its portrait.
			_net_show_foe_potion_fx(String(intent.get("pid", "")))
		NetMatch.EV_EMOTE:
			# The client sent an emote — float their line over the enemy plate.
			_net_show_foe_emote(int(intent.get("idx", -1)))
		_:
			pass


## HOST: seat the client's creature on the host's ENEMY side, run its on-enter
## authoritatively, then snapshot the new board to the client.
func _net_apply_remote_creature(intent: Dictionary, animate: bool = false) -> void:
	if _net_active_index != 1:
		return   # not the client's turn
	var lane: int = int(intent.get("lane", -1))
	var row: int = int(intent.get("row", ROW_FRONT))
	if lane < 0 or lane >= LANES_PER_ROW or row < ROW_FRONT or row > ROW_BACK:
		return
	if _row_array(true, row)[lane] != null:
		return   # slot occupied — drop the play (client mis-synced)
	var data := CardDB.get_card_data(String(intent.get("id", "")))
	if data.is_empty():
		return
	var uid: int = int(intent.get("uid", _net_issue_token_id()))
	if animate:
		# Foe play (bot or human opponent): throw the card from the foe's hand
		# into the slot before seating it.
		await _bot_animate_creature_play(data, lane, row)
		# The throw awaited a few frames — re-validate the turn/slot before committing.
		if _net_match_over or _net_active_index != 1:
			return
		if _row_array(true, row)[lane] != null:
			return
	_net_cards_played[1] += 1   # client's per-side card tally (Ironclad Veteran), pre-spawn
	# The client stamps its unspent Command (post-payment) on the intent so
	# play-time passives that scale off the caster's pool (Condottiere) read the
	# CLIENT's pool, not the host's. Bot intents omit it → 0 (vanilla body).
	_net_client_unspent_mana = int(intent.get("mana", 0))
	_net_spawn_creature(data, uid, lane, row, true, true)
	_net_sync_board()


# ── Reposition (battlefield "move") over the wire ────────────────────────
#
#  The active player drags one of their OWN board creatures to an empty friendly
#  slot (Card2D.board_interactive is on during their turn; floop stays off). The
#  HOST is authoritative: it applies its own moves directly + snapshots, and it
#  validates + applies the client's move from an IN_REPOSITION intent. The client
#  never moves its board directly — it sends the intent and the host's board
#  snapshot performs the visible move (reconciled in _net_update_creature).

func _net_field_move_dropped(global_pos: Vector2, card: Control) -> void:
	var active_local: bool = _net_active_index == NetMatch.local_player_index
	if not active_local or phase != Phase.PLAYER_TURN or _net_match_over:
		_return_card_to_slot(card)
		return
	if _moves_used_this_turn >= MOVES_PER_TURN:
		_show_info("No moves left this turn.")
		_return_card_to_slot(card)
		return
	var drop := _nearest_player_slot(global_pos)
	var dest_row: int = drop.row
	var dest_lane: int = drop.lane
	var src_row: int = card.current_row
	var src_lane: int = card.current_lane
	if dest_row == src_row and dest_lane == src_lane:
		_return_card_to_slot(card)
		return
	if _row_array(false, dest_row)[dest_lane] != null:
		_show_info("That slot is occupied.")
		_return_card_to_slot(card)
		return
	if _is_host():
		# Authoritative local move (mirrors the solo path), then snapshot.
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
		_net_sync_board()
	else:
		# Client: count it locally for the UI budget, tell the host, and return the
		# card home — the host's snapshot will perform the actual move.
		_moves_used_this_turn += 1
		NetMatch.send_intent({
			"t": NetMatch.IN_REPOSITION, "eid": int(card.entity_id),
			"lane": dest_lane, "row": dest_row,
		})
		_return_card_to_slot(card)


## HOST: validate + apply the client's reposition (its creatures sit on the host's
## ENEMY side), then snapshot so both sides see the move.
func _net_apply_remote_reposition(intent: Dictionary) -> void:
	if _net_active_index != 1:
		return   # not the client's turn
	if _moves_used_this_turn >= MOVES_PER_TURN:
		return
	var dest_lane: int = int(intent.get("lane", -1))
	var dest_row: int = int(intent.get("row", ROW_FRONT))
	if dest_lane < 0 or dest_lane >= LANES_PER_ROW or dest_row < ROW_FRONT or dest_row > ROW_BACK:
		return
	var node = NetMatch.get_entity(int(intent.get("eid", -1)))
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		return   # unknown entity or not the client's own creature
	if _row_array(true, dest_row)[dest_lane] != null:
		return   # destination occupied — drop the move (client mis-synced)
	var src_row: int = node.current_row
	var src_lane: int = node.current_lane
	if dest_row == src_row and dest_lane == src_lane:
		return
	_row_array(true, src_row)[src_lane] = null
	node.current_row = dest_row
	node.current_lane = dest_lane
	_reset_card_after_drag(node)
	_slot_set_card(_slot_array(true, dest_row)[dest_lane], node)
	_row_array(true, dest_row)[dest_lane] = node
	_moves_used_this_turn += 1
	_play_landing_pop(node)
	_net_sync_board()


# ─────────────────────────────────────────────────────────────────────────
#  PRACTICE BOT — drives slot 1 in a vs-bot match (SkirmishState.vs_bot).
#  The bot stands in for an absent client: it keeps its own hand drawn from slot
#  1's deck and a flat Command budget (3 + bank 2), asks SkirmishBot for an
#  ordered list of plays, applies each through the SAME host intent path a remote
#  client would hit, then ends actions (which resolves its strike + passes turn).
# ─────────────────────────────────────────────────────────────────────────

func _bot_refill_hand() -> void:
	var slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(1)
	if slot == null:
		return
	# The bot refills to the standard target. Its going-second compensation is the
	# Coin — a one-time +1 Command on its opening turn (granted in _bot_take_turn),
	# mirroring the human's Coin card rather than the old raw extra card.
	var target: int = HAND_REFILL_TARGET
	while _bot_hand.size() < target and _bot_deck_cursor < slot.deck.size():
		var id := String(slot.deck[_bot_deck_cursor])
		var uid: int = int(slot.deck_uids[_bot_deck_cursor]) \
			if _bot_deck_cursor < slot.deck_uids.size() else _net_issue_token_id()
		_bot_hand.append({"uid": uid, "id": id, "data": CardDB.get_card_data(id)})
		_bot_deck_cursor += 1


func _bot_take_turn() -> void:
	await _short_pause(COMBAT_PAUSE_SHORT)
	if _net_match_over or _net_active_index != 1:
		return
	_bot_refill_hand()
	var mana: int = SkirmishState.BASE_MAX_MANA + _bot_banked_mana
	# The Coin: the side going second gets a one-time +1 Command on its opening turn.
	# The bot can't hold/play a card the way the human does, so the tempo is granted
	# directly here — same net effect as casting the Coin on turn one.
	if _bot_turns_taken == 0 and _net_goes_second(1):
		mana += 1
	_bot_sync_hand_display(mana)   # the foe's hand fills up + Command seal lights
	var plays: Array = SkirmishBot.decide_turn(self, _bot_hand, mana)
	var spent := 0
	for intent in plays:
		if _net_match_over or _net_active_index != 1:
			break
		await _short_pause(COMBAT_PAUSE_SHORT)
		spent += _bot_consume_card(int(intent.get("uid", -1)))
		# Drop the card from the visible fan BEFORE the play animates, so the throw
		# reads as that card leaving the hand (not a phantom extra).
		_bot_sync_hand_display(mana - spent)
		await _bot_apply_intent(intent)
	_bot_banked_mana = clampi(mana - spent, 0, MAX_BANKED_MANA)
	_bot_turns_taken += 1
	await _short_pause(COMBAT_PAUSE_SHORT)
	if not _net_match_over and _net_active_index == 1:
		_net_finish_placement(1)


## Remove the played card from the bot's hand and return its Command cost.
func _bot_consume_card(uid: int) -> int:
	for i in _bot_hand.size():
		if int(_bot_hand[i].get("uid", -2)) == uid:
			var cost := int((_bot_hand[i].get("data", {}) as Dictionary).get("cost", 0))
			_bot_hand.remove_at(i)
			return cost
	return 0


func _bot_apply_intent(intent: Dictionary) -> void:
	match String(intent.get("t", "")):
		NetMatch.IN_PLAY_CREATURE:
			# animate=true → the card arcs from the foe's hand into its slot first.
			await _net_apply_remote_creature(intent, true)
		NetMatch.IN_PLAY_SPELL:
			await _net_apply_remote_spell(intent)
		NetMatch.IN_REPOSITION:
			await _net_apply_remote_reposition(intent)


## Push the bot's virtual hand (count) and Command budget to the readouts the human
## watches — the face-down fan up top and the foe Command seal — so the bot reads as
## an opponent who holds, then spends, a real hand. `mana_now` is the bot's REMAINING
## budget this turn (-1 = recompute the full turn budget, e.g. on the opening deal).
func _bot_sync_hand_display(mana_now: int = -1) -> void:
	_net_opp_hand_count = _bot_hand.size()
	_net_refresh_opp_hand()
	if mana_now < 0:
		mana_now = SkirmishState.BASE_MAX_MANA + _bot_banked_mana
	_net_set_opp_mana(maxi(0, mana_now), SkirmishState.BASE_MAX_MANA)


## Warm the CardTextureCache for the bot's whole deck so its played creatures fly in
## showing their real FACE (not the fallback card back). Mirrors _prebake_hand_textures:
## the same headless guard skips it in automated runs (bake_many parks on the
## RenderingServer frames that never fire under the dummy display server). Fired
## (not awaited) at match start, so it warms during the human's opening turn.
func _net_prebake_bot_textures() -> void:
	if DisplayServer.get_name() == "headless" or CardTextureCache == null:
		return
	var slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(1)
	if slot == null:
		return
	var seen := {}
	var to_bake: Array = []
	for id in slot.deck:
		var sid := String(id)
		if seen.has(sid):
			continue
		seen[sid] = true
		to_bake.append(CardDB.get_card_data(sid))
	await CardTextureCache.bake_many(to_bake)


## Cosmetic: a ghost of the card the foe (bot OR human opponent) is about to play
## arcs from the opponent's hand (top) down to its destination slot, so a foe
## creature reads as "taken from hand and set down" rather than teleported onto
## the board. Awaited by _net_apply_remote_creature before the real creature is
## seated. Shows the card FACE when its texture is already baked (the bot's deck
## is warmed at match start via _net_prebake_bot_textures), and the face-down
## card back otherwise. It NEVER awaits bake() — that blocks on RenderingServer
## frames which never fire headless, and this is purely cosmetic, so it must not
## be able to stall the foe's turn.
func _bot_animate_creature_play(data: Dictionary, lane: int, row: int) -> void:
	# Headless bail BEFORE any await: probe-driven plays must seat synchronously
	# (awaiting a coroutine that never suspends resumes the caller in-line).
	if DisplayServer.get_name() == "headless":
		return
	if _hud_layer == null or not is_instance_valid(_hud_layer):
		return
	var slots: Array = _slot_array(true, row)
	if lane < 0 or lane >= slots.size() or slots[lane] == null \
			or not is_instance_valid(slots[lane]):
		return
	var dest: Vector2 = slots[lane].get_global_rect().get_center()
	# Origin = the opponent's hand fan (top-right); fall back to the top-right corner.
	var origin := Vector2(get_viewport_rect().size.x - 150.0, 56.0)
	if _net_opp_hand_box != null and is_instance_valid(_net_opp_hand_box) \
			and _net_opp_hand_box.visible:
		origin = _net_opp_hand_box.get_global_rect().get_center()
	var tex: Texture2D = null
	if CardTextureCache != null:
		tex = CardTextureCache.get_texture(data)   # sync read; null if not yet baked
	if tex == null:
		tex = _net_card_back_tex                    # face-down fallback (always loaded)
	var travel := Vector2(132, 172)   # readable card in flight
	var land := Vector2(104, 136)     # settles toward the board-token footprint
	var ghost := TextureRect.new()
	if tex != null:
		ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 220
	ghost.size = travel
	ghost.pivot_offset = travel * 0.5   # rotate/settle about the card's centre
	ghost.position = origin - travel * 0.5
	ghost.modulate.a = 0.0
	_hud_layer.add_child(ghost)

	var duration := 0.42
	# Bow the path downward — the foe reaches up out of its hand and sets the card down.
	var ctrl := origin.lerp(dest, 0.5) + Vector2(0, -86.0)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var p1 := origin.lerp(ctrl, t)
		var p2 := ctrl.lerp(dest, t)
		var sz: Vector2 = travel.lerp(land, t)
		ghost.size = sz
		ghost.position = p1.lerp(p2, t) - sz * 0.5
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ghost, "modulate:a", 1.0, 0.12)
	tw.tween_property(ghost, "rotation", 0.0, duration).from(randf_range(-0.12, 0.12)) \
		.set_ease(Tween.EASE_OUT)
	# Gate on a real timer (NOT tw.finished) so the bot's turn can never stall on a
	# tween — the tween only drives the cosmetics in parallel; the timer is the clock.
	await _short_pause(duration)
	if is_instance_valid(ghost):
		ghost.queue_free()
	if AudioBank != null:
		AudioBank.play_sfx("card_play")


## CLIENT: a cosmetic ghost of the client's OWN creature play, arcing from the hand
## up to the destination slot. The real creature still arrives via the host snapshot
## (the client never seats locally), so this only bridges the visual gap the HOST gets
## for free from its local seat — without it, a Player-2 creature just pops into the
## slot. Fire-and-forget: it never gates the intent (sent before this is called).
func _client_animate_own_play(data: Dictionary, lane: int, row: int, origin: Vector2) -> void:
	if _hud_layer == null or not is_instance_valid(_hud_layer):
		return
	var slots: Array = _slot_array(false, row)
	if lane < 0 or lane >= slots.size() or slots[lane] == null or not is_instance_valid(slots[lane]):
		return
	var dest: Vector2 = slots[lane].get_global_rect().get_center()
	var tex: Texture2D = null
	if CardTextureCache != null:
		tex = CardTextureCache.get_texture(data)   # sync read; null if not yet baked
	if tex == null:
		tex = _net_card_back_tex
	var travel := Vector2(132, 172)
	var land := Vector2(104, 136)
	var ghost := TextureRect.new()
	if tex != null:
		ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 220
	ghost.size = travel
	ghost.pivot_offset = travel * 0.5
	ghost.position = origin - travel * 0.5
	ghost.modulate.a = 0.0
	_hud_layer.add_child(ghost)
	var duration := 0.34
	# Bow the path UP toward the board — the player lifts the card from hand onto the line.
	var ctrl := origin.lerp(dest, 0.5) + Vector2(0, -64.0)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var p1 := origin.lerp(ctrl, t)
		var p2 := ctrl.lerp(dest, t)
		var sz: Vector2 = travel.lerp(land, t)
		ghost.size = sz
		ghost.position = p1.lerp(p2, t) - sz * 0.5
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ghost, "modulate:a", 1.0, 0.10)
	# Real timer, never tw.finished (unreliable headless), mirroring the bot ghost.
	await _short_pause(duration)
	if is_instance_valid(ghost):
		ghost.queue_free()


# ── Events (host → client) ───────────────────────────────────────────────

func _on_net_event(event: Dictionary) -> void:
	if _is_host():
		return   # host is authoritative; it never consumes its own broadcasts
	# While a clash replay is animating, every incoming event queues behind it —
	# otherwise the outcome snapshot would snap the fight's result in under the
	# replay, and the next turn-begin would start play mid-cinematic.
	if _net_replay_active:
		_net_event_backlog.append(event)
		return
	_net_process_event(event)


## The event dispatch body — reached live via _on_net_event or deferred via
## _net_flush_backlog once a clash replay finishes.
func _net_process_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		NetMatch.EV_TURN_BEGIN:
			_net_client_turn_begin(int(event.get("active", 0)), int(event.get("round", 0)))
		NetMatch.EV_ORDERS_PHASE:
			_net_turn_round = int(event.get("round", 1))
			_net_initiative = int(event.get("init", 0))
			_sealed_open_orders_local()
		NetMatch.EV_ORDER_GHOST:
			_sealed_show_ghost(int(event.get("lane", -1)), int(event.get("row", 0)))
		NetMatch.EV_REVEAL:
			phase = Phase.RESOLVING
			_sealed_clear_pending_local()
			_show_combat_banner("THE ORDERS BREAK OPEN", "", Color(1.0, 0.78, 0.35))
			if AudioBank != null:
				AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
		NetMatch.EV_SORCERY:
			_sealed_set_sorcery(int(event.get("who", 0)))
		NetMatch.EV_CLASH:
			# The host's per-strike clash log — replay it paced (lunges, blows,
			# numbers, kill cues). Fire-and-forget coroutine: everything that
			# arrives while it runs queues in the backlog and applies after.
			_net_replay_clash(event)
		NetMatch.EV_BOARD_SYNC:
			_net_apply_board_sync(event)
		NetMatch.EV_HAND_COUNT:
			_net_opp_hand_count = int(event.get("n", 0))
			_net_refresh_opp_hand()
			_net_set_opp_mana(int(event.get("mana", _net_opp_mana)),
				int(event.get("maxmana", _net_opp_max_mana)))
		NetMatch.EV_DISCARD_FX:
			# The host threw cards away at its turn commit — show the beat.
			_net_show_foe_discard_fx(int(event.get("n", 0)))
		NetMatch.EV_POTION_FX:
			# The host drank a potion — show the drink beat over its portrait.
			_net_show_foe_potion_fx(String(event.get("pid", "")))
		NetMatch.EV_EMOTE:
			# The host sent an emote — float their line over the enemy plate.
			_net_show_foe_emote(int(event.get("idx", -1)))
		NetMatch.EV_SPELL:
			# The host cast a spell — show its arrow + thrown card + target burst so we
			# see exactly what they pointed at (client casts are shown host-side).
			_net_on_opp_spell_event(event)
		NetMatch.EV_DRAW:
			# A spell we cast told us to draw from our own pile (host resolved it).
			for _i in int(event.get("n", 0)):
				draw_one()
			_layout_hand()
			_net_broadcast_hand_count()
			_update_hud()
		NetMatch.EV_GIVE_CARD:
			# The host returned a specific card to our hand (Grave Robbery / Grave Pact).
			_net_give_card_local(String(event.get("id", "")), int(event.get("uid", -1)))
		NetMatch.EV_MANA:
			if bool(event.get("next", false)):
				# Next-turn max-Command grant (Mourner's on-death). Our own
				# _start_round folds it in at the next turn-begin, above the
				# banking cap — same as the host's side of the same effect.
				_bonus_mana_next_turn += int(event.get("n", 0))
			else:
				# A spell we cast granted us Command on our own side.
				player_mana += int(event.get("n", 0))
				_update_hud()
				_net_broadcast_hand_count()   # push the bumped Command to the foe's seal
		NetMatch.EV_MATCH_OVER:
			_net_show_result(int(event.get("winner", -1)))
		NetMatch.EV_REMATCH:
			_net_on_remote_rematch()
		NetMatch.EV_CHOICE:
			# Host asked us to pick an option for one of our own creatures (Copycat /
			# Adaptable). Show the picker; the answer goes back as an IN_CHOICE intent.
			_net_client_show_choice(int(event.get("eid", -1)), String(event.get("kind", "")))
		_:
			pass


## Tell the opponent our hand SIZE (a number; never the cards — they only see how
## many we hold, as face-down backs). Host → event, client → intent; the receiver
## stores it in _net_opp_hand_count and refreshes the face-down fan up top.
func _net_broadcast_hand_count() -> void:
	# The hand count rides with our live Command (current + max) so the opponent's
	# foe-Command seal tracks what we can afford. This fires on every hand/mana
	# change (turn-begin refill, each play, spell draw/Command rewards), so the
	# foe's readout stays current without a separate channel.
	var msg := {"t": NetMatch.EV_HAND_COUNT, "n": _hand.size(),
		"mana": player_mana, "maxmana": player_max_mana}
	if _is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)


## Tell the opponent we just discarded N cards (count only — never the faces),
## so their side shows the beat instead of the fan silently shrinking. Sent
## from _flush_marked_discards ahead of the hand-count update; the channel is
## reliable and ordered, so the fx always lands before the fan ticks down.
func _net_send_discard_fx(n: int) -> void:
	if n <= 0:
		return
	var msg := {"t": NetMatch.EV_DISCARD_FX, "n": n}
	if _is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)


## The foe discarded N cards: peel that many card-backs off their face-down fan
## and flick them away (down-right, spinning, fading) with a labelled beat, so
## the opponent's churn is a visible act — the mirror of our own discard cascade.
func _net_show_foe_discard_fx(n: int) -> void:
	if n <= 0 or _hud_layer == null:
		return
	if _net_opp_hand_box == null or not is_instance_valid(_net_opp_hand_box):
		return
	var origin: Vector2 = _net_opp_hand_box.global_position \
		+ Vector2(_net_opp_hand_box.size.x * 0.5, 40.0)
	for i in mini(n, 6):   # cap the volley — past 6 backs it's just confetti
		var back := _net_make_card_back(Vector2(46.0, 64.0))
		_hud_layer.add_child(back)
		back.z_index = 30
		back.global_position = origin + Vector2(float(i - 1) * 10.0, 0.0)
		var dest: Vector2 = origin + Vector2(randf_range(60.0, 140.0), randf_range(120.0, 180.0))
		var delay := 0.10 * float(i)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(back, "global_position", dest, 0.42) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(delay)
		tw.tween_property(back, "rotation", randf_range(0.5, 1.1), 0.42) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(delay)
		tw.tween_property(back, "modulate:a", 0.0, 0.42) \
			.set_ease(Tween.EASE_IN).set_delay(delay + 0.06)
		tw.chain().tween_callback(back.queue_free)
		get_tree().create_timer(delay).timeout.connect(func():
			if AudioBank != null:
				AudioBank.play_sfx("card_discard", 0.08, -6.0))
	spawn_floating_number(origin + Vector2(0.0, -18.0),
		"FOE DISCARDS %d" % n, Color(0.78, 0.72, 0.62), false)


## Skirmish potion resolution. Command and draw resolve on the caster's machine;
## HP/board effects route through the host, targeted bottles send an entity_id,
## then the local belt consumes the potion and the foe gets a drink beat.
func _net_use_potion(pid: String, index: int, target: Control = null) -> void:
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect := String(data.get("effect", ""))
	# Caster-local resource rider: Butcher's Dram's +3 Command lands on the
	# drinker's OWN machine (each peer owns its Command); its accompanying
	# sacrifice is the host-side board mutation routed below.
	if effect == "sacrifice_for_command":
		player_mana += 3
	match effect:
		"gain_mana":
			player_mana += 2
		"draw":
			for _i in range(3):
				draw_one()
		_:
			if _net_potion_needs_host(effect):
				if _is_host():
					_net_apply_host_potion(pid, false, target)
					_net_sync_board()
				else:
					# The target rides as an entity_id — the cross-wire handle
					# targeted spells use (host resolves via NetMatch.get_entity).
					var msg := {"t": NetMatch.IN_USE_POTION, "pid": pid}
					if target != null and is_instance_valid(target):
						msg["target"] = int(target.entity_id)
					NetMatch.send_intent(msg)
					if effect == "heal_hp":
						var heal: int = int(data.get("value", 8)) if data.has("value") else 8
						_show_lifelink_heal(heal) # optimistic; the sync sets true HP
			else:
				push_warning("Combat: net potion effect '%s' is not supported" % effect)
	_net_send_potion_fx(pid)
	_ctx_consume_potion(index)
	_rebuild_potion_bar()
	_update_hud()
	_net_broadcast_hand_count()


func _net_potion_needs_host(effect: String) -> bool:
	return effect in [
		"heal_hp",
		"aoe_enemies",
		"chain_lightning",
		"shield_wall",
		"summon_recruits",
		"revive_last_dead",
		# 2026-07-09 targeted + board bottles (net-aware potion targeting):
		"column_strike",        # Sapper's Charge — target enemy + lane-mate
		"grant_rampage",        # War Paint — target friendly
		"grant_lifelink",       # Vampiric Draught — target friendly + caster heal
		"sacrifice_for_command",# Butcher's Dram — sac target friendly (Command is caster-local)
		"detonate_doom_all",    # Doomsday Draught — non-targeted, caster's Doom bombs
	]


func _net_apply_host_potion(pid: String, caster_is_enemy: bool, target: Control = null) -> void:
	var data: Dictionary = PotionDB.get_potion(pid)
	match String(data.get("effect", "")):
		"heal_hp":
			var heal: int = int(data.get("value", 8)) if data.has("value") else 8
			var before: int = enemy_hp if caster_is_enemy else player_hp
			_net_heal_hero(caster_is_enemy, heal)
			if not caster_is_enemy and player_hp > before:
				_show_lifelink_heal(player_hp - before)
		"aoe_enemies":
			for c in _net_side_creatures(not caster_is_enemy):
				c.take_damage(3)
			_cleanup_dead()
		"chain_lightning":
			for _i in range(4):
				var pool := _net_side_creatures(not caster_is_enemy)
				if pool.is_empty():
					break
				var pick: Control = pool[randi() % pool.size()]
				pick.take_damage(2)
				if pick.current_hp <= 0:
					_cleanup_dead()
		"shield_wall":
			for c in _net_side_creatures(caster_is_enemy):
				c.state.has_shield = true
				if c.has_method("_spawn_keyword_chip"):
					c._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
				c.update_stat_display()
		"summon_recruits":
			var made := 0
			for row in [ROW_FRONT, ROW_BACK]:
				if made >= 2:
					break
				var arr := _row_array(caster_is_enemy, row)
				for lane in range(LANES_PER_ROW):
					if made >= 2:
						break
					if arr[lane] == null:
						summon_token(3, 3, lane, caster_is_enemy, row)
						var recruit = _row_array(caster_is_enemy, row)[lane]
						if recruit != null and is_instance_valid(recruit):
							recruit.card_data["name"] = "Recruit"
							if recruit.has_method("_spawn_keyword_chip"):
								recruit._spawn_keyword_chip("RECRUIT", Color(0.82, 0.70, 0.48))
							recruit.update_stat_display()
						made += 1
		"revive_last_dead":
			var side := 1 if caster_is_enemy else 0
			var grave: Dictionary = _net_last_dead[side]
			if not grave.is_empty():
				var gd: Dictionary = grave.get("data", {})
				var keywords: Array = gd.get("keywords", [])
				_net_place_token(caster_is_enemy, 1, 1,
					String(gd.get("name", "Revived")), keywords)
		"column_strike":
			# Sapper's Charge: 4 to the target creature + its lane-mate in the other
			# row. target.is_opponent picks the correct side array regardless of
			# which peer cast (it lives on the caster's FOE side).
			if target != null and is_instance_valid(target) and target.is_creature():
				var sap_lane: int = target.current_lane
				var sap_other: int = ROW_BACK if target.current_row == ROW_FRONT else ROW_FRONT
				var sap_mate: Control = _row_array(target.is_opponent, sap_other)[sap_lane]
				target.take_damage(4)
				if sap_mate != null and is_instance_valid(sap_mate):
					sap_mate.take_damage(4)
				_cleanup_dead()
		"grant_rampage":
			# War Paint: Rampage 2 + +1 ATK on the caster's own creature for the
			# fight. The keyword + effective ATK both ride the board snapshot, so
			# the foe sees the chip and the buffed stat.
			if target != null and is_instance_valid(target) and target.is_creature():
				if "rampage" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("rampage")
				target.card_data["rampage"] = maxi(2, int(target.card_data.get("rampage", 0)))
				target.persistent_atk_buff += 1
				target.persistent_atk_buff_rounds = 99
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("RAMPAGE", Color(1.0, 0.62, 0.20))
				target.update_stat_display()
		"grant_lifelink":
			# Vampiric Draught: Lifelink 2 on a friendly for the fight + a 4 HP
			# caster top-up (host-authoritative HP).
			if target != null and is_instance_valid(target) and target.is_creature():
				if "lifelink" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("lifelink")
				target.card_data["lifelink"] = maxi(2, int(target.card_data.get("lifelink", 0)))
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LIFELINK", Color(0.95, 0.35, 0.45))
				target.update_stat_display()
			_net_heal_hero(caster_is_enemy, 4)
		"sacrifice_for_command":
			# Butcher's Dram: kill the caster's own target (the +3 Command already
			# landed caster-side in _net_use_potion). The 999 mirrors the Offering
			# spell; solo's relic/reactive sacrifice hooks don't exist in skirmish,
			# so a plain kill is faithful.
			if target != null and is_instance_valid(target) and target.is_creature():
				target.take_damage(999)
				_cleanup_dead()
		"detonate_doom_all":
			# Doomsday Draught: fire every one of the caster's own Doom creatures
			# now. _detonate_doom attributes face damage by is_opponent, so on the
			# host it hits the correct hero for either caster.
			var bombs: Array = []
			for c in _net_side_creatures(caster_is_enemy):
				if c.has_keyword("doom"):
					bombs.append(c)
			for c in bombs:
				if is_instance_valid(c) and c.current_hp > 0:
					_detonate_doom(c)
			_cleanup_dead()


func _net_side_creatures(is_enemy: bool) -> Array:
	var out: Array = []
	for row in [ROW_FRONT, ROW_BACK]:
		for c in _row_array(is_enemy, row):
			if c != null and is_instance_valid(c) and c.current_hp > 0:
				out.append(c)
	return out


## Tell the opponent we drank potion `pid` so their side shows a drink beat (the
## potion never touches THEIR state — this is presentation only, the mirror of
## our own drink). Host → event, client → intent, like the discard beat.
func _net_send_potion_fx(pid: String) -> void:
	var msg := {"t": NetMatch.EV_POTION_FX, "pid": pid}
	if _is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)


## The foe drank a potion: a labelled beat over their portrait, tinted by the
## potion's own colour — so the opponent's swing isn't a silent HP/hand jump.
func _net_show_foe_potion_fx(pid: String) -> void:
	if _hud_layer == null:
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var nm: String = String(data.get("name", "a potion"))
	var col: Color = data.get("color", Color(0.82, 0.74, 0.58))
	var anchor := Vector2(get_viewport_rect().size.x * 0.5, 120.0)
	if _enemy_hp_label != null and is_instance_valid(_enemy_hp_label):
		anchor = _enemy_hp_label.get_global_rect().get_center() + Vector2(0.0, 34.0)
	elif _net_opp_hand_box != null and is_instance_valid(_net_opp_hand_box):
		anchor = _net_opp_hand_box.global_position \
			+ Vector2(_net_opp_hand_box.size.x * 0.5, 40.0)
	spawn_floating_number(anchor, "FOE DRINKS: %s" % nm.to_upper(), col, false)
	if AudioBank != null:
		AudioBank.play_sfx("potion_use", 0.06, -3.0)


## Store the opponent's synced Command and refresh the foe's wax seal numeral.
## Mirrors _update_hud's player-mana formatting (banked carryover shown as "(+N)").
func _net_set_opp_mana(cur: int, mx: int) -> void:
	_net_opp_mana = cur
	_net_opp_max_mana = mx
	if _net_opp_mana_label == null or not is_instance_valid(_net_opp_mana_label):
		return
	_set_seal_readout(_net_opp_mana_label,
		"%d / %d" % [_net_opp_mana, _net_opp_max_mana])


## The "Opponent's turn" line, annotated with their hand size when we know it.
func _net_opp_turn_msg() -> String:
	if _net_opp_hand_count > 0:
		return "Opponent's turn — %d in hand" % _net_opp_hand_count
	return "Opponent's turn…"


# ── Opponent's hand (face-down fan by the enemy plate) ───────────────────────
#
#  A small fan of face-down card backs, the way other card games show the foe's
#  hand. Placed in the gap just LEFT of the enemy plate (top-right): next to the
#  foe, clear of the centred title, above the board. You see THAT they hold cards
#  and how many — never what they are. Driven by _net_opp_hand_count.

func _net_build_opp_hand_ui() -> void:
	if _hud_layer == null or _net_opp_hand_box != null:
		return
	if _net_card_back_tex == null:
		_net_card_back_tex = load("res://assets/ui/card_back.png") as Texture2D

	# Box sits in the gap between the centred title (right edge ~x1100) and the
	# enemy plate (left edge x1350). Right-anchored so it tracks the plate.
	_net_opp_hand_box = Control.new()
	_net_opp_hand_box.name = "NetOppHand"
	_net_opp_hand_box.anchor_left = 1.0
	_net_opp_hand_box.anchor_right = 1.0
	_net_opp_hand_box.anchor_top = 0.0
	_net_opp_hand_box.anchor_bottom = 0.0
	_net_opp_hand_box.offset_left = -494   # ~x1106
	_net_opp_hand_box.offset_right = -250  # x1350 (the plate's left edge)
	_net_opp_hand_box.offset_top = 0.0
	_net_opp_hand_box.offset_bottom = 96.0
	_net_opp_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_opp_hand_box.z_index = 6
	_net_opp_hand_box.visible = false
	_hud_layer.add_child(_net_opp_hand_box)

	var label := Label.new()
	label.text = "OPPONENT"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.90, 0.80, 0.60, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_top = 74.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		label.add_theme_font_override("font", GameTheme.font_display)
	_net_opp_hand_box.add_child(label)

	_net_opp_hand_row = Control.new()
	_net_opp_hand_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_net_opp_hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_opp_hand_box.add_child(_net_opp_hand_row)


## Rebuild the face-down fan from _net_opp_hand_count. Cheap (a few TextureRects
## sharing one texture), so we rebuild on every hand-count change.
func _net_refresh_opp_hand() -> void:
	if _net_opp_hand_row == null or not is_instance_valid(_net_opp_hand_row):
		return
	if _net_opp_hand_box != null:
		_net_opp_hand_box.visible = _net_opp_hand_count > 0
	for child in _net_opp_hand_row.get_children():
		child.queue_free()
	var n: int = _net_opp_hand_count
	if n <= 0:
		return
	const BACK_W := 46.0
	const BACK_H := 64.0
	const BASE_Y := 6.0
	var area_w: float = _net_opp_hand_box.size.x if _net_opp_hand_box != null else 244.0
	# Overlapping fan, centred in the gap. Tighten the spacing as the hand grows so
	# a big hand still fits the narrow gap.
	var spacing: float = BACK_W * 0.62
	var usable: float = area_w - BACK_W - 6.0
	if n > 1 and spacing * float(n - 1) > usable:
		spacing = usable / float(n - 1)
	var total: float = spacing * float(n - 1)
	var start_x: float = (area_w - total) * 0.5
	var mid: float = float(n - 1) * 0.5
	for i in range(n):
		var back := _net_make_card_back(Vector2(BACK_W, BACK_H))
		_net_opp_hand_row.add_child(back)
		var off: float = float(i) - mid                 # signed distance from centre
		var norm: float = 0.0 if mid <= 0.0 else off / mid
		# A hand held at the top hangs DOWN: edges ride a little lower, middle highest,
		# with the cards splayed outward (rotated about their bottom-centre).
		var x: float = start_x + float(i) * spacing - BACK_W * 0.5
		var y: float = BASE_Y + norm * norm * 7.0
		back.position = Vector2(x, y)
		back.rotation = off * 0.085


## One face-down card: the shared card-back art, rotated about its bottom-centre
## (the held point of a fanned hand). A soft shadow lifts it off the board.
func _net_make_card_back(sz: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = sz
	holder.size = sz
	holder.pivot_offset = Vector2(sz.x * 0.5, sz.y)   # rotate around the bottom-centre
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0.02, 0.015, 0.01, 0.0)
	sst.set_corner_radius_all(4)
	sst.shadow_color = Color(0, 0, 0, 0.5)
	sst.shadow_size = 4
	shadow.add_theme_stylebox_override("panel", sst)
	holder.add_child(shadow)

	if _net_card_back_tex != null:
		var pic := TextureRect.new()
		pic.texture = _net_card_back_tex
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # shrink the big art into sz
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pic)
	else:
		# No card-back art — a gilt-edged dark plate still reads as "a card".
		var plate := Panel.new()
		plate.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pst := StyleBoxFlat.new()
		pst.bg_color = Color(0.16, 0.07, 0.06, 0.96)
		pst.border_color = Color(GILT.r, GILT.g, GILT.b, 0.55)
		pst.set_border_width_all(2)
		pst.set_corner_radius_all(4)
		plate.add_theme_stylebox_override("panel", pst)
		holder.add_child(plate)
	return holder


# ── Opponent spell telegraph (arrow + thrown card to the target) ─────────────
#
#  When the opponent casts, we show what they pointed at: a gold arrow from their
#  hand (top) to the struck target, a thrown ghost of the spell card, and the
#  spell's family burst on the target. The casting side already saw its own arrow
#  during target selection, so this only fires for the WATCHER.

## CLIENT: the host announced a spell (EV_SPELL). Resolve the target locally (the
## entity registry is shared by eid) and play the telegraph. Fires before the board
## snapshot, so the target node is still alive even for a lethal spell.
func _net_on_opp_spell_event(event: Dictionary) -> void:
	var data := CardDB.get_card_data(String(event.get("id", "")))
	if data.is_empty():
		return
	var teid: int = int(event.get("target", -1))
	var tnode: Control = null
	var tcenter := Vector2.ZERO
	var has_t := false
	if teid >= 0:
		var n = NetMatch.get_entity(teid)
		if n != null and is_instance_valid(n):
			tnode = n
			tcenter = n.get_global_rect().get_center()
			has_t = true
	_net_spell_telegraph(data, tcenter, has_t, tnode)


func _net_spell_telegraph(card_data: Dictionary, target_center: Vector2,
		has_target: bool, target_node: Control) -> void:
	if _hud_layer == null:
		return
	var vp := get_viewport_rect().size
	# The opponent casts from their corner — origin at the enemy plate (top-right),
	# so the arrow + thrown card visibly come from the foe.
	var origin := Vector2(vp.x - 130.0, 150.0)
	if _enemy_banner_for_info != null and is_instance_valid(_enemy_banner_for_info):
		origin = _enemy_banner_for_info.get_global_rect().get_center()
	var dest := target_center if has_target else Vector2(vp.x * 0.5, vp.y * 0.4)
	if has_target:
		_net_flash_arrow(origin, dest)
	# Show the opponent's actual card, held readably center-screen. The old quick
	# thrown-ghost (fly-from-corner + shrink in 0.4s) was too fast to read — the
	# whole point of the telegraph is "what did the foe just play?", so reveal the
	# real face. The arrow still carries the from-foe / to-target directionality.
	_reveal_cast_card(card_data, "OPPONENT CASTS", Color(0.96, 0.56, 0.34))
	# Battle log — this fires on the peer WATCHING the opponent cast (client sees the
	# host's EV_SPELL; host sees the client's IN_PLAY_SPELL), so it's the foe's cast
	# on both sides. The local caster's own line comes from _net_log_local_cast.
	_net_log_foe_cast(card_data, target_node if (has_target and target_node != null \
		and is_instance_valid(target_node)) else null)
	# Burst at the struck point — reuse the family VFX while we still have the node.
	if target_node != null and is_instance_valid(target_node):
		_play_spell_cast_vfx(card_data, target_node)
	elif has_target:
		spawn_spell_burst(dest,
			_legacy_spell_color(String(card_data.get("spell", {}).get("type", ""))))
	else:
		_play_spell_cast_vfx(card_data, null)


## A one-shot version of the targeting arrow (the live one tracks the cursor): a
## gold bezier from the opponent's hand to the target that fades in, holds, fades.
func _net_flash_arrow(from: Vector2, to: Vector2) -> void:
	if _hud_layer == null:
		return
	var line := Line2D.new()
	line.width = 7.0
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 239
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 0.55))
	grad.set_color(1, Color(1.0, 0.45, 0.15, 1.0))
	line.gradient = grad
	# Bow the curve downward — the opponent throws the spell down at our board.
	var dir := to - from
	var ctrl1 := from + Vector2(dir.x * 0.15, 150.0)
	var ctrl2 := to + Vector2(0.0, -70.0)
	var points := PackedVector2Array()
	var steps := 26
	for i in range(steps + 1):
		points.append(_bezier_cubic(from, ctrl1, ctrl2, to, float(i) / float(steps)))
	line.points = points
	line.modulate.a = 0.0
	_hud_layer.add_child(line)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(0, 0), Vector2(-22, -10), Vector2(-22, 10)])
	head.color = Color(1.0, 0.40, 0.12, 1.0)
	head.z_index = 240
	head.position = to
	head.modulate.a = 0.0
	if points.size() >= 2:
		var tangent: Vector2 = points[points.size() - 1] - points[points.size() - 2]
		if tangent.length_squared() > 0.01:
			head.rotation = tangent.angle()
	_hud_layer.add_child(head)

	var tw := create_tween()
	# Fade in (line + head together), hold, fade out (together), then free.
	tw.tween_property(line, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(head, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.45)
	tw.tween_property(line, "modulate:a", 0.0, 0.30)
	tw.parallel().tween_property(head, "modulate:a", 0.0, 0.30)
	tw.tween_callback(func():
		if is_instance_valid(line): line.queue_free()
		if is_instance_valid(head): head.queue_free())


## The other peer dropped — end cleanly and return to the menu. Handles both the
## mid-match case and the post-match case (opponent declined the rematch / left
## the result screen), which the plain _net_match_over guard would otherwise eat.
func _net_on_peer_lost() -> void:
	if _net_match_over:
		# Already on the result screen: the opponent left rather than rematch.
		if _net_result_panel != null and is_instance_valid(_net_result_panel):
			_net_result_panel.queue_free()
			_net_result_panel = null
			if _phase_label != null:
				_phase_label.text = "OPPONENT LEFT"
			_show_info("Opponent left — returning to menu…")
			get_tree().create_timer(2.0).timeout.connect(func():
				NetMatch.leave()
				GameTheme.fade_out_then_change_scene(self, "res://scenes/main_menu.tscn", 0.5))
		return
	_net_match_over = true
	phase = Phase.GAME_OVER
	Card2D.board_interactive = false
	if _end_turn_btn != null:
		_end_turn_btn.disabled = true
	if _phase_label != null:
		_phase_label.text = "OPPONENT LEFT"
	_show_info("Opponent disconnected — returning to menu…")
	get_tree().create_timer(2.5).timeout.connect(func():
		NetMatch.leave()
		GameTheme.fade_out_then_change_scene(self, "res://scenes/main_menu.tscn", 0.5)
	)


# ── Spells over the wire ─────────────────────────────────────────────────
#
#  Both players' spells resolve on the HOST through _net_resolve_spell, which is
#  perspective-aware (caster_index 0 = host, 1 = client). Explicitly-targeted
#  spells carry their perspective in the target entity_id (take_damage on a node
#  is side-agnostic), so only face / board-wide effects need the caster flip.
#  Spell VFX are coarse in v1 (the client just sees the resulting board snapshot).
#  Supported set is gated at play time so unsupported spells never silently fizzle.

func _net_spell_supported(data: Dictionary) -> bool:
	# The Coin is a granted system card (going-second compensation), not part of the
	# draftable spell economy — always castable, independent of the lists below. It's
	# deliberately kept out of NET_SPELL_CUSTOMS so the draft pool never offers it.
	if String(data.get("id", "")) == "coin":
		return true
	# Single source of truth lives in SkirmishState so the draft pool and this
	# play-time gate can never drift (see SkirmishState.NET_SPELL_TYPES / CUSTOMS).
	return SkirmishState.is_net_playable_spell(data)


## Recycle a just-played skirmish spell into the local player's pile so each side's
## deck cycles exactly as in solo (_play_spell line ~5349): exhaust-keyword spells
## are removed to the exhaust pile, everything else returns to the discard pile to
## be reshuffled. Both the host AND the client call this for their OWN spell, so
## neither warband's deck silently shrinks over a long match. Synthetic/token
## spells (deck_uid < 0) aren't real deck cards and are skipped.
func _net_recycle_spell(card: Control) -> void:
	if card == null or not is_instance_valid(card) or card.deck_uid < 0:
		return
	if card.has_keyword("exhaust"):
		_exhaust_pile.append(card.card_id)
	else:
		_player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))


## Spells whose hand / pile / Command / draw effects resolve on the CASTER's own
## machine (those resources never leave the caster). War Chant & Mass Grave also
## forward a board consequence to the host; the rest are fully caster-local.
const _NET_CASTER_LOCAL_SPELLS: Array[String] = [
	"recycle", "gambit", "turbo", "war_chant", "mass_grave",
]


## Pitch one hand card to the caster's own discard (a card the player chose to
## discard). Real cards keep their uid; tokens/synthetic cards just vanish.
func _net_pitch_card(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	_hand.erase(c)
	if c.get_parent() != null:
		c.get_parent().remove_child(c)
	if c.deck_uid >= 0:
		_player_discard_pile.append(_pile_entry(c.card_id, c.deck_uid))
	c.queue_free()


## Caster-LOCAL pile/hand spells. The hand, piles, Command and draw all live on the
## caster's machine, so the caster resolves those here (with its own picker UI)
## rather than round-tripping the host. War Chant / Mass Grave forward only their
## BOARD consequence (Soldier count / discard size) for the host to apply. Mirrors
## the solo resolver branches, kept compact so no solo-only spell state is dragged in.
func _net_play_caster_local_spell(card: Control, cost: int) -> void:
	var id: String = card.card_id
	var sid: String = String(card.card_data.get("spell", {}).get("id", ""))
	var plus_draw: int = int(card.card_data.get("extra_draw", 0))
	_net_log_local_cast(card.card_data, null)   # "You cast X." (hand/pile spell)
	# Spend Command + pull the card from hand up front (matches the generic path).
	player_mana -= cost
	_pulse_mana_label(cost)
	_first_spell_this_turn = true   # Witch's first-spell discount rests (parity w/ solo)
	_hand.erase(card)
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	var board_n: int = 0          # board consequence to forward (War Chant / Mass Grave)
	match sid:
		"recycle":
			if _hand.size() > 0:
				var rp: Control = await _show_recycle_modal()
				if rp != null and is_instance_valid(rp):
					var rcost: int = int(rp.card_data.get("cost", 0))
					_hand.erase(rp)
					if rp.get_parent() != null:
						rp.get_parent().remove_child(rp)
					_exhaust_pile.append(rp.card_id)
					rp.queue_free()
					player_mana += rcost
					for _i in plus_draw:
						draw_one()
		"gambit":
			var gmax: int = mini(3, _hand.size())
			if gmax > 0:
				var gp: Array = await _show_discard_picker(gmax,
					"Gambit — discard up to %d, draw that many" % gmax, true)
				for c in gp:
					_net_pitch_card(c)
				for _gi in gp.size():
					draw_one()
		"turbo":
			player_mana += 2
			for _i in plus_draw:
				draw_one()
			_player_discard_pile.append(CardDB.random_curse_id())
		"war_chant":
			var wmax: int = mini(3, _hand.size())
			if wmax > 0:
				var wp: Array = await _show_discard_picker(wmax,
					"War Chant — discard up to %d to muster that many Soldiers" % wmax, true)
				for c in wp:
					_net_pitch_card(c)
				board_n = wp.size()
		"mass_grave":
			board_n = _player_discard_pile.size()
	# Forward the board consequence: host resolves locally + syncs; client ships the
	# count as an IN_PLAY_SPELL the host applies via _net_resolve_custom_spell.
	if sid == "war_chant" or sid == "mass_grave":
		if _is_host():
			var hdata: Dictionary = card.card_data.duplicate(true)
			hdata["_net_picks"] = board_n
			_net_resolve_spell(hdata, -1, 0)
			NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": id, "target": -1})
			_net_sync_board()
		else:
			NetMatch.send_intent({"t": NetMatch.IN_PLAY_SPELL, "uid": card.deck_uid,
				"id": id, "target": -1, "n": board_n})
	# Recycle the spell card itself, then refresh the local UI / hand count.
	_net_recycle_spell(card)
	if is_instance_valid(card):
		card.queue_free()
	_net_broadcast_hand_count()
	_layout_hand()
	_update_hud()


## Local entry for a spell play (host or client). Non-targeted resolve/send now;
## targeted spells enter the normal targeting mode and finish in _try_resolve_target.
func _net_play_spell(card: Control, cost: int) -> void:
	# SEALED ORDERS: deployment is secret, spellcraft is open — spells belong to
	# the sorcery window after the reveal, and only on your own step. (This is
	# the one gate that covers the HOST too; the client is also caught by the
	# _net_active_index turn gates.)
	if _is_sealed():
		if _sorcery_active < 0:
			_show_info("Spells wait for the reveal — creatures only while orders are sealed.")
			_layout_hand()
			return
		if _sorcery_active != NetMatch.local_player_index:
			_show_info("The foe's spell step — yours comes next.")
			_layout_hand()
			return
	var data: Dictionary = card.card_data
	if not _net_spell_supported(data):
		_show_info("That spell isn't in skirmish yet.")
		_layout_hand()
		return
	# Caster-local pile/hand spells resolve their hand part on the caster's own
	# machine (the hand/piles/Command live here, not on the host) — route them out.
	if String(data.get("spell", {}).get("id", "")) in _NET_CASTER_LOCAL_SPELLS:
		await _net_play_caster_local_spell(card, cost)
		return
	var targeting: String = String(data.get("targeting", "none"))
	var uid: int = card.deck_uid
	var id: String = card.card_id
	player_mana -= cost
	_pulse_mana_label(cost)
	_first_spell_this_turn = true   # Witch's first-spell discount rests (parity w/ solo)
	_hand.erase(card)
	_hand_container.remove_child(card)
	if targeting == "none":
		_net_log_local_cast(data, null)   # "You cast X." (non-targeted)
		if _is_host():
			_net_resolve_spell(data, -1, 0)
			# Tell the client what we cast (no target) — sent before the board snapshot
			# so its telegraph plays, then the result reconciles.
			NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": id, "target": -1})
			_net_sync_board()
		else:
			NetMatch.send_intent({"t": NetMatch.IN_PLAY_SPELL, "uid": uid, "id": id, "target": -1})
		_net_recycle_spell(card)
		card.queue_free()
		_net_broadcast_hand_count()
		_update_hud()
	else:
		# Hold the card in targeting mode; _net_cast_targeted finishes the cast.
		_targeting_spell = card
		_targeting_data = data
		_show_info("Click a target...")
		_show_targeting_arrow()
		_update_hud()


## Finish a targeted skirmish spell once the player clicked a target (or face).
func _net_cast_targeted(spell_card: Control, target: Control) -> void:
	var eid: int = -1
	if target != null and is_instance_valid(target):
		eid = int(target.entity_id)
	_net_log_local_cast(spell_card.card_data, target)   # "You cast X on Y."
	if _is_host():
		_net_resolve_spell(spell_card.card_data, eid, 0)
		# Tell the client which target we pointed at — sent before the board snapshot
		# so the arrow + thrown card play, then the result reconciles.
		NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": spell_card.card_id, "target": eid})
		_net_sync_board()
	else:
		NetMatch.send_intent({
			"t": NetMatch.IN_PLAY_SPELL, "uid": spell_card.deck_uid,
			"id": spell_card.card_id, "target": eid,
		})
	_net_recycle_spell(spell_card)
	if is_instance_valid(spell_card):
		spell_card.queue_free()
	_net_broadcast_hand_count()
	_update_hud()


## HOST: apply the client's spell intent (caster perspective = index 1).
func _net_apply_remote_spell(intent: Dictionary) -> void:
	if _net_active_index != 1:
		return
	var data := CardDB.get_card_data(String(intent.get("id", "")))
	if data.is_empty() or not _net_spell_supported(data):
		return
	# Caster-local pile spells (War Chant / Mass Grave) resolve their hand part on the
	# client and forward only the board consequence as a pick/size count.
	if intent.has("n"):
		data = data.duplicate(true)
		data["_net_picks"] = int(intent.get("n", 0))
	var target_eid: int = int(intent.get("target", -1))
	# Capture the target's screen position BEFORE resolving — _net_resolve_spell
	# runs _cleanup_dead, which can free the node a lethal spell just killed.
	var tnode: Control = null
	var tcenter := Vector2.ZERO
	var has_t := false
	if target_eid >= 0:
		var n = NetMatch.get_entity(target_eid)
		if n != null and is_instance_valid(n):
			tnode = n
			tcenter = n.get_global_rect().get_center()
			has_t = true
	_net_resolve_spell(data, target_eid, 1)
	# The host is the watcher of the client's spell — show its arrow + thrown card.
	_net_spell_telegraph(data, tcenter, has_t,
		tnode if (tnode != null and is_instance_valid(tnode)) else null)
	_net_sync_board()


## HOST-only, perspective-aware spell resolution. caster_index: 0 = host (player
## side), 1 = client (enemy side, host POV). Target effects use the node directly
## (side-agnostic); face / board-wide effects key off the caster's side.
func _net_resolve_spell(data: Dictionary, target_eid: int, caster_index: int) -> void:
	if not _is_host():
		return
	var caster_is_enemy: bool = caster_index == 1
	var spell: Dictionary = data.get("spell", {})
	var stype: String = String(spell.get("type", ""))
	var value: int = int(spell.get("value", 0))
	# Worn Spellbook (board relic, host-authoritative): the caster's damage spells
	# deal +1. Built-in damage types here; custom damage spells fold it into `plus`
	# in _net_resolve_custom_spell. Mirrors the solo path (see _resolve_spell).
	if _relic_active_for_side(caster_is_enemy, "worn_spellbook") \
			and stype in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		value += 1
	var permanent: bool = bool(spell.get("permanent", false))
	var target: Control = null
	if target_eid >= 0:
		var node = NetMatch.get_entity(target_eid)
		if node != null and is_instance_valid(node):
			target = node
	var caster_friendlies: Array = _all_friendly(caster_is_enemy)
	var caster_foes: Array = _all_friendly(not caster_is_enemy)
	match stype:
		"damage":
			if target != null:
				target.take_damage(value)
		"damage_face":
			_net_damage_hero(not caster_is_enemy, value)
		"damage_all_enemies":
			for c in caster_foes:
				c.take_damage(value)
		"damage_all":
			for c in _all_creatures_both_sides():
				c.take_damage(value)
		"buff_atk":
			if target != null:
				if permanent:
					target.current_atk += value
				else:
					target.temp_atk_buff += value
				target.update_stat_display()
		"buff_hp":
			if target != null:
				target.current_hp += value
				target.card_data.hp = int(target.card_data.get("hp", target.current_hp)) + value
				target.update_stat_display()
		"heal":
			if target != null:
				target.current_hp = mini(target.current_hp + value, int(target.card_data.get("hp", target.current_hp)))
				target.update_stat_display()
		"buff_all_atk":
			for c in caster_friendlies:
				if permanent:
					c.current_atk += value
				else:
					c.temp_atk_buff += value
				c.update_stat_display()
		"custom":
			_net_resolve_custom_spell(String(spell.get("id", "")), target, caster_is_enemy, data)
	_cleanup_dead()
	# Remember the last host-resolved spell (and its target) for Echo — but never
	# Echo itself, so a chain of Echoes can't form. Caster-local pile spells don't
	# pass through here, so Echo only ever copies a board/damage/buff spell.
	if String(spell.get("id", "")) != "echo_spell":
		_net_last_spell_data = data.duplicate(true)
		_net_last_spell_target_eid = target_eid
	# Count this cast for the active side's combo spells (flame_bolt). Incremented
	# AFTER resolution so a combo spell reads the count of PRIOR spells this turn.
	_net_spells_this_turn += 1
	# Per-spell passives for the CASTER's side (the solo spell path's Hexblade /
	# Emberwright loops never run over the wire). Hexblade grows +1 ATK per spell;
	# Emberwright pings the caster's enemy face. The per-side fight tally lets a
	# freshly-played Hexblade read its owner's spell count (_apply_play_time_passives).
	_net_spells_fight[caster_index] += 1
	_net_cards_played[caster_index] += 1   # spells count as cards this turn (Ironclad)
	for _sp in _all_friendly(caster_is_enemy):
		match _sp.card_data.get("passive", ""):
			"atk_per_spell":
				_sp.current_atk += 1
				_sp.update_stat_display()
			"ember_per_spell":
				_hurt_opposing_hero(caster_is_enemy, 3 if bool(_sp.card_data.get("is_upgraded", false)) else 2)


func _net_resolve_custom_spell(spell_id: String, target: Control, caster_is_enemy: bool, data: Dictionary) -> void:
	# Perspective-aware ports of the solo custom spells that need NO draw / pile /
	# gold / Command-gain / sacrifice / Discover / hand-picker — those resolve wrong
	# host-only and stay deferred until pile+draw sync lands. Keep this match in sync
	# with SkirmishState.NET_SPELL_CUSTOMS (tools/_probe_skirmish.gd checks parity).
	#
	# caster_is_enemy = the caster sits on the HOST's enemy side (i.e. the client).
	# Target effects operate on the node directly (the node carries its own side, so
	# no flip). Side-relative effects use the caster's own / enemy side:
	#   friendlies = the caster's creatures   foes = the caster's opponents
	#   caster's enemy face  = _net_damage_hero(not caster_is_enemy, v)
	#   caster's own   face  = _net_damage_hero(caster_is_enemy, v)
	var plus: int = int(data.get("dmg_bonus", 0))
	# Worn Spellbook (board relic): +1 to the caster's PURE-damage custom spells.
	# Folded into `plus` — safe because for every id below `plus` is used ONLY on
	# damage expressions (never an ATK/heal/buff line). Mirrors the solo
	# spell_dmg_bonus inclusion set: excludes hex (debuff), holy_smite (execute),
	# cataclysm / fuel_the_pyre (ATK-scaled), apocalypse (999), and self-face hits.
	if _relic_active_for_side(caster_is_enemy, "worn_spellbook") and spell_id in [
			"immolate", "inferno", "wildfire", "petard", "earthquake", "blood_tithe",
			"flame_bolt", "ricochet", "quick_shot", "slash", "smite_spell"]:
		plus += 1
	var plus_draw: int = int(data.get("extra_draw", 0))
	var is_plus: bool = bool(data.get("is_upgraded", false))
	var friendlies: Array = _all_friendly(caster_is_enemy)
	var foes: Array = _all_friendly(not caster_is_enemy)
	match spell_id:
		"shove":
			if target != null:
				var net_shoved: bool = false
				if target.current_row == ROW_FRONT:
					net_shoved = _relocate_creature(target, not caster_is_enemy, ROW_BACK, target.current_lane)
				if not net_shoved and is_instance_valid(target):
					target.state.stunned = true
					if target.has_method("_spawn_keyword_chip"):
						target._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
					if plus > 0:
						target.take_damage(plus)
		"hex":
			if target != null:
				var had_keywords: bool = not target.card_data.get("keywords", []).is_empty()
				target.take_damage((4 if had_keywords else 1) + plus)
				if is_instance_valid(target):
					target.card_data["keywords"] = []
					target.card_data.erase("sniper")
					target.update_stat_display()
		"second_wind":
			if target != null:
				target.current_hp = int(target.card_data.get("hp", target.current_hp))
				target.current_atk += 1
				target.update_stat_display()
		"soul_swap":
			if target != null:
				var eff_atk: int = target.effective_atk()
				var new_atk: int = target.current_hp
				# Floor swapped HP at 1 (see single-player soul_swap): a 0-ATK body
				# would otherwise swap to 0 HP and be culled silently.
				var new_hp: int = maxi(1, eff_atk)
				target.current_atk = maxi(0, new_atk - target.temp_atk_buff - target.persistent_atk_buff)
				target.current_hp = new_hp
				target.card_data.hp = new_hp
				target.update_stat_display()
				# Upgraded Soul Swap: the promised "+ takes 2 damage" parting blow.
				if plus > 0:
					target.take_damage(plus)
		"shield_wall":
			if target != null:
				var bandage: int = 4 + plus
				target.current_hp += bandage
				target.card_data.hp = int(target.card_data.get("hp", target.current_hp)) + bandage
				target.set_meta("shield_wall_thorns", true)
				target.update_stat_display()
		"barricade":
			if target != null:
				target.current_hp += 4
				target.card_data.hp = int(target.card_data.get("hp", target.current_hp)) + 4
				if "armored" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("armored")
				target.update_stat_display()
		"censer_light":
			if target != null:
				if "lifelink" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("lifelink")
				if int(target.card_data.get("lifelink", 0)) < 1:
					target.card_data["lifelink"] = 1
				target.persistent_atk_buff += 1 + plus
				target.persistent_atk_buff_rounds = 99
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LIFELINK", Color(0.95, 0.35, 0.45))
				target.update_stat_display()
		"virulence":
			# The caster's side attacks poisonously this round — the shared strike
			# code reads the per-side flag, so it covers later plays too. Decays in
			# _net_decay_side_states after the clash.
			_virulence_active[1 if caster_is_enemy else 0] = true
			for c in friendlies:
				spawn_keyword_callout_kw(c, "poison")
		"lightning":
			if target != null:
				target.take_damage(2 + plus)
			_net_damage_hero(not caster_is_enemy, 1 + plus)
		"immolate":
			if target != null:
				var imm: int = 4 + plus
				target.take_damage(imm)
				if target.current_hp <= 0:
					_net_damage_hero(not caster_is_enemy, imm)
		"cataclysm":
			if target != null:
				var cat_hit: int = target.effective_atk() + plus
				var first_lane: int = maxi(0, target.current_lane - 1)
				var last_lane: int = mini(LANES_PER_ROW - 1, target.current_lane + 1)
				for lane in range(first_lane, last_lane + 1):
					for row in [ROW_FRONT, ROW_BACK]:
						var victim = _row_array(not caster_is_enemy, row)[lane]
						if victim != null and is_instance_valid(victim) and victim.current_hp > 0:
							victim.take_damage(cat_hit)
		"inferno":
			for c in foes:
				c.take_damage(4 + plus)
			_net_damage_hero(not caster_is_enemy, 4 + plus)
		"wildfire":
			var wf_kills: int = 0
			for c in foes:
				if is_instance_valid(c):
					var hp_before: int = c.current_hp
					c.take_damage(2 + plus)
					if hp_before > 0 and c.current_hp <= 0:
						wf_kills += 1
			if wf_kills > 0:
				_net_damage_hero(not caster_is_enemy, wf_kills)
		"ambush":
			for c in foes:
				c.take_damage(1 + plus)
			for c in friendlies:
				# Mirrors solo: granted Swift (War Cry / Battle Drummer) counts.
				if _is_swift_attacker(c):
					c.temp_atk_buff += 1 + plus
					c.update_stat_display()
		"plague_bell":
			for _i in 12:
				var any_died := false
				for c in _all_creatures_both_sides():
					var hp_before: int = c.current_hp
					c.take_damage(1 + plus)
					if hp_before > 0 and c.current_hp <= 0:
						any_died = true
				_cleanup_dead()
				if not any_died:
					break
		"petard":
			if target != null:
				var pd_pos: Dictionary = _find_creature_position(target)
				var pd_main: int = 5 + plus
				var pd_splash: int = 2 + plus
				target.take_damage(pd_main)
				if not pd_pos.is_empty():
					var pd_row = _row_array(bool(pd_pos.is_enemy), int(pd_pos.row))
					for pd_lane in [int(pd_pos.lane) - 1, int(pd_pos.lane) + 1]:
						if pd_lane >= 0 and pd_lane < LANES_PER_ROW:
							var pd_adj = pd_row[pd_lane]
							if pd_adj != null and is_instance_valid(pd_adj) and pd_adj.current_hp > 0:
								pd_adj.take_damage(pd_splash)
		"dark_pact":
			if target != null:
				var dp_gain: int = 1 + plus
				target.take_damage(999)
				for c in friendlies:
					if c == target or not is_instance_valid(c) or c.current_hp <= 0:
						continue
					c.current_atk += dp_gain
					c.card_data.hp = int(c.card_data.get("hp", c.current_hp)) + dp_gain
					c.current_hp += dp_gain
					c.update_stat_display()
		"apocalypse":
			var kills := 0
			for c in _all_creatures_both_sides():
				c.take_damage(999)
				if c.current_hp <= 0:
					kills += 1
			_net_damage_hero(caster_is_enemy, kills)
		"blood_tithe":
			# Desc + solo: 4 to the enemy face, 2 self-harm (the self hit never
			# takes `plus` — Worn Spellbook sharpens the tithe, not the cost).
			_net_damage_hero(not caster_is_enemy, 4 + plus)
			_net_damage_hero(caster_is_enemy, 2)
		"kings_command":
			# Go-wide crown, mirroring the solo resolver: +1/+1 this fight per
			# friendly creature ("+" adds +1/+1 more).
			var kc_g: int = friendlies.size() + plus
			for c in friendlies:
				c.current_atk += kc_g
				c.current_hp += kc_g
				c.card_data.hp = int(c.card_data.get("hp", c.current_hp)) + kc_g
				c.update_stat_display()
		"battle_hymn":
			for c in friendlies:
				c.temp_atk_buff += 1
				c.current_hp += 1
				c.card_data.hp = int(c.card_data.get("hp", c.current_hp)) + 1
				c.update_stat_display()
		"earthquake":
			var quake_hit: int = 2 + plus
			for c in _all_creatures_both_sides():
				if c != null and is_instance_valid(c):
					c.take_damage(quake_hit)
			_cleanup_dead()
			for quake_lane in range(LANES_PER_ROW):
				var quake_foe = _row_array(not caster_is_enemy, ROW_FRONT)[quake_lane]
				if quake_foe != null and is_instance_valid(quake_foe) and quake_foe.current_hp > 0:
					_relocate_creature(quake_foe, not caster_is_enemy, ROW_BACK, quake_lane)
			_refresh_adjacency_buffs()
		"war_cry":
			# Swift-only rally ("+" adds +1 ATK while they charge) — mirrors solo.
			for c in friendlies:
				c.set_meta("war_cry_swift", true)
				if plus > 0:
					c.temp_atk_buff += plus
				c.update_stat_display()
		"inspire":
			for c in friendlies:
				c.set_meta("war_cry_swift", true)
				c.set_meta("inspire_piercing", true)
				if plus > 0:
					c.temp_atk_buff += plus
				c.update_stat_display()
		"rout":
			# Drive the caster's foes into their back row; they forfeit their swing
			# this round. Mirrors solo; stun is honoured by
			# _net_premark_skip_attack before the clash.
			var rout_hit: int = 1 + plus
			for c in foes:
				if not is_instance_valid(c):
					continue
				if c.current_row == ROW_FRONT:
					_relocate_creature(c, not caster_is_enemy, ROW_BACK, c.current_lane)
				c.state.stunned = true
				if c.has_method("_spawn_keyword_chip"):
					c._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
				c.take_damage(rout_hit)
			_refresh_adjacency_buffs()
		"flame_bolt":
			# Combo: ramps to 5 if the caster already cast a spell THIS turn.
			var fb: int = (5 if _net_spells_this_turn >= 1 else 3) + plus
			_net_damage_hero(not caster_is_enemy, fb)
		"mending_light":
			_net_heal_hero(caster_is_enemy, 5)
			for c in friendlies:
				c.current_hp = mini(c.current_hp + 2, int(c.card_data.get("hp", c.current_hp)))
				c.update_stat_display()
		"holy_smite":
			# Execute scaling: hit for the target's missing HP, floored at 3 so it's
			# never a dead draw on a healthy body.
			if target != null:
				var missing: int = int(target.card_data.get("hp", target.current_hp)) - target.current_hp
				target.take_damage(maxi(3, missing) + plus)
				if target.current_hp <= 0:
					_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"ricochet":
			var rc_back_hit: int = 2 + plus
			var rc_fallback_hit: int = 1 + plus
			var rc_hit_any: bool = false
			for victim in _row_array(not caster_is_enemy, ROW_BACK):
				if victim != null and is_instance_valid(victim) and victim.current_hp > 0:
					victim.take_damage(rc_back_hit)
					rc_hit_any = true
			if not rc_hit_any and foes.size() > 0:
				foes[randi() % foes.size()].take_damage(rc_fallback_hit)
			_cleanup_dead()
		"provision":
			# Muster a 2/1 body in the caster's first open lane (front, then back).
			# entity_id stays -1 so the trailing _net_sync_board registers + ships it.
			var prov_placed := false
			for prow in [ROW_FRONT, ROW_BACK]:
				if prov_placed:
					break
				var pfield = _row_array(caster_is_enemy, prow)
				for pl in range(LANES_PER_ROW):
					if pfield[pl] == null:
						summon_token(2, 1, pl, caster_is_enemy, prow)
						prov_placed = true
						break
		"adrenaline":
			_net_caster_gain_mana(caster_is_enemy, 2)
			_net_caster_draw(caster_is_enemy, 1 + plus_draw)
		"coin":
			# Going-second compensation: a one-time +1 Command (Hearthstone's Coin).
			_net_caster_gain_mana(caster_is_enemy, 1)
		"bloodletting":
			_net_damage_hero(caster_is_enemy, 1)   # self-harm cost (caster's own face)
			_net_caster_gain_mana(caster_is_enemy, 2 + int(data.get("extra_mana", 0)))
			var bl_fallen: int = _enemy_deaths_this_fight if caster_is_enemy else _friendly_deaths_this_fight
			if bl_fallen > 0:
				_net_caster_draw(caster_is_enemy, 1)
		# ── Draw / Command spells (use the EV_DRAW / EV_MANA caster channel) ──
		"quick_shot":
			var qs_slay: bool = false
			if target != null:
				target.take_damage(1 + plus)
				qs_slay = target.current_hp <= 0
			else:
				_net_damage_hero(not caster_is_enemy, 1 + plus)
			if qs_slay:
				_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"slash":
			if target != null:
				var can_blast_move: bool = target.current_row == ROW_FRONT \
					and _row_array(not caster_is_enemy, ROW_BACK)[target.current_lane] == null
				var slash_dmg: int = 2 + plus
				if not can_blast_move:
					slash_dmg += 2
				target.take_damage(slash_dmg)
				if is_instance_valid(target) and target.current_hp > 0 and can_blast_move:
					_relocate_creature(target, not caster_is_enemy, ROW_BACK, target.current_lane)
				if target.current_hp <= 0:
					_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"patch_up":
			# Field Surgery — mirrors solo: full heal + a draw, patient sits the round out.
			if target != null:
				target.current_hp = int(target.card_data.get("hp", target.current_hp))
				target.state.stunned = true
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("RESTING", Color(0.85, 0.78, 0.45))
				target.update_stat_display()
				_net_caster_draw(caster_is_enemy, 1)
		"smite_spell":
			if target != null:
				target.take_damage(6 + plus)
				if target.current_hp <= 0:
					_net_caster_gain_mana(caster_is_enemy, 1 + int(data.get("slay_mana", 0)))
					_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"unholy_bargain":
			var ub_fallen: int = _enemy_deaths_this_fight if caster_is_enemy else _friendly_deaths_this_fight
			var ub_draws: int = 2 + int(data.get("extra_draw", 0)) + (1 if ub_fallen > 0 else 0)
			_net_caster_draw(caster_is_enemy, ub_draws)
			_net_damage_hero(caster_is_enemy, 2)
		# ── Sacrifice spells (kill the caster's own target = take_damage 999) ──
		"offering":
			if target != null:
				target.take_damage(999)
				_net_caster_gain_mana(caster_is_enemy, 2)
				_net_caster_draw(caster_is_enemy, plus_draw)
		"fuel_the_pyre":
			if target != null:
				var fp_atk: int = target.effective_atk()
				var fp_lane: int = target.current_lane
				target.take_damage(999)
				# Deterministic revenge (mirrors solo): hit whatever stands across
				# the victim's lane; only an empty column scatters the flame.
				var fp_opp: Control = get_opposing_card(fp_lane, caster_is_enemy)
				if fp_opp != null:
					fp_opp.take_damage(fp_atk + plus)
				elif foes.size() > 0:
					foes[randi() % foes.size()].take_damage(fp_atk + plus)
				else:
					_net_damage_hero(not caster_is_enemy, fp_atk + plus)
		# ── Temp-state spells (freeze / stun / poison / charge) ──────────────
		# The shared attack resolver already HONOURS these (can_attack reads
		# is_frozen; _resolve_column_attack reads charges_this_turn; the strike
		# applies poison) — the only net-specific work is decay, which
		# _net_decay_side_states does at the end of the owning side's attack turn.
		"doubled_hour":
			# The caster's creatures attack twice this round — _net_run_clash runs
			# the second swing per side; decays in _net_decay_side_states.
			_doubled_hour[1 if caster_is_enemy else 0] = true
			_net_caster_draw(caster_is_enemy, 1)
		"frost_bolt":
			if target != null:
				target.state.is_frozen = true
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
				if plus > 0:
					target.take_damage(plus)
		"hoarfrost":
			# Target friendly gains Shield; the creature opposing it freezes.
			if target != null:
				target.state.has_shield = true
				target.update_stat_display()
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
				var hf_lane: int = target.current_lane
				var hf_foe: bool = not caster_is_enemy
				var hf_opp = _row_array(hf_foe, ROW_FRONT)[hf_lane]
				if hf_opp == null:
					hf_opp = _row_array(hf_foe, ROW_BACK)[hf_lane]
				if hf_opp != null:
					hf_opp.state.is_frozen = true
					if hf_opp.has_method("_spawn_keyword_chip"):
						hf_opp._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
		"venom_tip":
			# Grant Poison to a friendly for this round (decayed via temp_poison).
			if target != null:
				if not target.card_data.keywords.has("poison"):
					target.card_data.keywords.append("poison")
				target.set_meta("temp_poison", true)
				target.update_stat_display()
				spawn_keyword_callout_kw(target, "poison")
		"charge_spell":
			# Target friendly strikes every opposing lane on the caster's turn
			# (the strike pass reads charges_this_turn; decay clears it after).
			if target != null:
				target.set_meta("charges_this_turn", true)
		# ── Pile / grave / exile spells (host-authoritative; see Phase B) ─────
		"banish":
			if target != null:
				var banish_limit: int = 4 + plus
				if target.current_hp <= banish_limit:
					var beid: int = int(target.entity_id)
					if beid >= 0:
						_net_exiled_eids.append(beid)
					for b_e in [false, true]:
						for b_r in [ROW_FRONT, ROW_BACK]:
							var b_arr = _row_array(b_e, b_r)
							for b_ln in range(LANES_PER_ROW):
								if b_arr[b_ln] == target:
									b_arr[b_ln] = null
									var b_slots = _slot_array(b_e, b_r)
									if b_ln < b_slots.size():
										_restore_slot_label(b_slots[b_ln], b_ln)
					if beid >= 0:
						NetMatch.unregister_entity(beid)
					target.queue_free()
					_refresh_adjacency_buffs()
				else:
					target.take_damage(banish_limit)
				if int(data.get("extra_draw", 0)) > 0:
					_net_caster_draw(caster_is_enemy, int(data.get("extra_draw", 0)))
		"reanimate":
			# Revive the CASTER's last corpse as a 1/1 (2/2 if upgraded) on the caster's
			# side, keeping its keywords. Reads the per-side grave so the client's cast
			# raises the client's dead, not the host's.
			var grave_re: Dictionary = _net_last_dead[1 if caster_is_enemy else 0]
			if not grave_re.is_empty():
				var gd: Dictionary = grave_re.get("data", {})
				var rev_n: int = 1 + plus
				_net_place_token(caster_is_enemy, rev_n, rev_n,
					String(gd.get("name", "Revived")), gd.get("keywords", []))
		"grave_robbery":
			# Float the caster's last REAL corpse (uid >= 0; tokens have no hand
			# identity) back to its hand via the caster channel.
			var grave_gr: Dictionary = _net_last_dead[1 if caster_is_enemy else 0]
			if not grave_gr.is_empty() and int(grave_gr.get("uid", -1)) >= 0:
				_net_caster_give_card(caster_is_enemy,
					String(grave_gr.get("id", "")), int(grave_gr.get("uid", -1)))
		"last_rites":
			# Morbid removal, caster-side: 6 once one of the CASTER's creatures has
			# fallen this fight (client deaths land in the enemy tally — see inspire).
			if target != null:
				var lr_fallen: int = _enemy_deaths_this_fight if caster_is_enemy else _friendly_deaths_this_fight
				target.take_damage((6 if lr_fallen > 0 else 3) + plus)
		"echo_spell":
			# Re-resolve the caster's last host-resolved spell this turn, same target.
			# (Echo isn't recorded as last-spell, so it can't echo an echo.)
			if not _net_last_spell_data.is_empty():
				_net_resolve_spell(_net_last_spell_data, _net_last_spell_target_eid,
					1 if caster_is_enemy else 0)
		"war_chant":
			# The caster pitched _net_picks cards on its own machine; muster one Soldier
			# per pitch (2/1, or 3/2 upgraded) on the caster's side.
			var wc_atk: int = 3 if is_plus else 2
			var wc_hp: int = 2 if is_plus else 1
			for _wi in int(data.get("_net_picks", 0)):
				var wc_s := _pick_empty_for_summon(caster_is_enemy, ROW_FRONT)
				if wc_s.is_empty():
					break
				summon_token(wc_atk, wc_hp, wc_s.lane, caster_is_enemy, wc_s.row)
		"mass_grave":
			# Damage every caster foe by the caster's discard size (sent as _net_picks).
			var mg_dmg: int = maxi(1, int(data.get("_net_picks", 0))) + plus
			for c in foes:
				c.take_damage(mg_dmg)


## Place a keyword-carrying token on a side (net Reanimate). Returns the node, or
## null if the caster's board is full. entity_id stays -1 so the trailing board sync
## registers and ships it to the other peer.
func _net_place_token(is_enemy: bool, atk: int, hp: int, tname: String, keywords: Array) -> Control:
	var slot := _pick_empty_for_summon(is_enemy, ROW_FRONT)
	if slot.is_empty():
		return null
	var card = CARD_SCENE.instantiate()
	card.card_id = "token_revive_%d_%d" % [atk, hp]
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.compact_mode = true
	card.card_data = {"id": card.card_id, "name": tname, "type": "creature", "cost": 0,
		"atk": atk, "hp": hp, "keywords": keywords.duplicate(), "rarity": "enemy",
		"desc": "Reanimated.", "is_token": true}
	card.current_atk = atk
	card.current_hp = hp
	card.current_lane = slot.lane
	card.current_row = slot.row
	_row_array(is_enemy, slot.row)[slot.lane] = card
	_slot_set_card(_slot_array(is_enemy, slot.row)[slot.lane], card)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	card.will_die.connect(_on_card_will_die.bind(card))
	if keywords.has("shield"):
		card.state.has_shield = true
	_refresh_adjacency_buffs()
	return card


## Damage a hero by host-side: is_enemy_side true → the host's enemy (client),
## false → the host's own hero. Lets a spell hit "the caster's enemy face."
func _net_damage_hero(is_enemy_side: bool, value: int) -> void:
	if is_enemy_side:
		damage_enemy_hero(value)
	else:
		damage_player_hero(value)


## Heal a hero by host-side, capped at the skirmish starting HP. is_enemy_side
## true → the host's enemy (client) hero; false → the host's own hero.
func _net_heal_hero(is_enemy_side: bool, value: int) -> void:
	var cap: int = SkirmishState.START_HP
	if is_enemy_side:
		var nb_e: int = enemy_hp
		enemy_hp = mini(enemy_hp + value, cap)
		if enemy_hp > nb_e:
			_stoke_acolytes(true)
	else:
		var nb_p: int = player_hp
		player_hp = mini(player_hp + value, cap)
		if player_hp > nb_p:
			_stoke_acolytes(false)


# ── Owner-relative hero routing for per-side passives (Wave: passive parity) ──
# Player passives only ran for the host's side (the combat engine reads
# `_all_player_creatures()` / `if not is_enemy`). These route a passive's hero effect
# to the creature's OWN side so a Player-2 Vampire Lord heals Player 2, etc. In solo
# they're only ever called with owner_is_enemy=false, so solo behaviour is unchanged.

## Sides whose creatures run player-passive logic. Solo: the player only (enemies use
## EncounterEffects). Net: BOTH warbands — the host is authoritative for each side.
func _passive_sides() -> Array:
	return [false, true] if _is_net() else [false]

## Heal the hero that OWNS owner_is_enemy's side.
func _heal_owner_hero(owner_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if _is_net():
		_net_heal_hero(owner_is_enemy, n)
	elif player_hp < player_max_hp:
		var healed: int = mini(n, player_max_hp - player_hp)
		player_hp += healed
		_show_lifelink_heal(healed)   # green +N at the HP medallion — any hero heal, not just Lifelink
		_stoke_acolytes(false)
		_update_hud()

## Damage the hero OPPOSING owner_is_enemy's side (a drain / reach payoff).
func _hurt_opposing_hero(owner_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if _is_net():
		_net_damage_hero(not owner_is_enemy, n)
	else:
		damage_enemy_hero(n)


## Make the CASTER draw n cards from THEIR OWN pile. The host can only draw into
## its own hand, so when the client is the caster (caster_is_enemy) it sends an
## EV_DRAW event and the client draws locally; when the host casts, it draws here.
func _net_caster_draw(caster_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if caster_is_enemy:
		NetMatch.send_to_client({"t": NetMatch.EV_DRAW, "n": n})
	else:
		for _i in n:
			draw_one()
		_layout_hand()
		_net_broadcast_hand_count()
		_update_hud()


## Return a SPECIFIC card to the caster's hand (Grave Robbery / Grave Pact). Same
## host→caster split as the draw channel: the client gets it via EV_GIVE_CARD; the
## host adds it locally. The card goes to the front of the caster's draw pile and is
## drawn, so it respects the hand-size cap exactly like solo's return-to-hand.
func _net_caster_give_card(caster_is_enemy: bool, id: String, uid: int) -> void:
	if id == "":
		return
	if caster_is_enemy:
		NetMatch.send_to_client({"t": NetMatch.EV_GIVE_CARD, "id": id, "uid": uid})
	else:
		_net_give_card_local(id, uid)


## Caster-side: push {id,uid} onto the front of our own draw pile and draw it, so a
## returned creature lands in hand carrying its real deck identity (upgrades, uid).
func _net_give_card_local(id: String, uid: int) -> void:
	if id == "":
		return
	_player_draw_pile.push_front(_pile_entry(id, uid))
	draw_one()
	_layout_hand()
	_net_broadcast_hand_count()
	_update_hud()


## Grant the CASTER n Command. Same split as the draw channel — the client gains it
## on its own side via EV_MANA; the host gains it locally.
func _net_caster_gain_mana(caster_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if caster_is_enemy:
		NetMatch.send_to_client({"t": NetMatch.EV_MANA, "n": n})
	else:
		player_mana += n
		_update_hud()
		_net_broadcast_hand_count()   # push the bumped Command to the foe's seal


# ─────────────────────────────────────────────────────────────────────────
#  CLIENT-OWNED CREATURE EFFECTS — perspective-correct ports of the on-enter /
#  on-death effects that solo only ever ran for the player side. The host
#  resolves a CLIENT creature with is_enemy=true; these route the result to the
#  right owner so Player 2's Doppelganger / Chaos Imp / Griffin / Copycat /
#  Adaptable behave identically to Player 1's.
# ─────────────────────────────────────────────────────────────────────────

## Doppelganger: the CASTER's most-recent corpse (per-side grave), as card_data.
## side_is_enemy = the caster sits on the host's enemy side (the client).
func _net_last_dead_copy_data(side_is_enemy: bool) -> Dictionary:
	var side: int = 1 if side_is_enemy else 0
	var entry: Dictionary = _net_last_dead[side]
	return entry.get("data", {}) if not entry.is_empty() else {}


## Griffin: float the just-dead creature back to its OWNER's hand, once per fight.
## Reads the per-side grave (recorded in _on_card_destroyed BEFORE on_death fires),
## guards against a re-return of the same uid, and routes via the caster channel.
func _net_return_dead_to_caster(was_enemy: bool) -> void:
	if not _is_host():
		return
	var side: int = 1 if was_enemy else 0
	var entry: Dictionary = _net_last_dead[side]
	if entry.is_empty():
		return
	var uid: int = int(entry.get("uid", -1))
	if uid < 0:
		return   # tokens have no deck identity to return
	if _net_return_once_used[side].has(uid):
		return   # already came back once this fight
	_net_return_once_used[side][uid] = true
	_net_caster_give_card(was_enemy, String(entry.get("id", "")), uid)


## Chaos Imp: cast a random NET-PLAYABLE spell for free with the caster's perspective.
## caster_is_enemy = the imp is the client's. Picks a self-resolving spell (no picker /
## pile / self-harm / sacrifice), auto-targets the caster's side, and resolves through
## the authoritative net resolver; the result rides the trailing board-sync.
func _net_cast_random_spell_free(caster_is_enemy: bool) -> void:
	if not _is_host():
		return
	# Exclude spells that need the caster's hand/pile, harm the caster, or recurse —
	# mirrors solo cast_random_spell_free's CHAOS_DENY, intersected with net-playable.
	var deny := {
		"offering": true, "fuel_the_pyre": true, "bloodletting": true,
		"unholy_bargain": true, "dark_pact": true, "blood_tithe": true,
		"mass_grave": true, "apocalypse": true, "echo_spell": true,
		"reanimate": true, "grave_robbery": true, "banish": true,
		# (grave_pact used to sit here when it armed a pile-return; its Last Rites
		# redesign is a clean damage bolt, so the imp may sling it.)
	}
	var candidates: Array = []
	for id in CardDB.CARD_POOL:
		var d: Dictionary = CardDB.CARD_POOL[id]
		if String(d.get("type", "")) != "spell" or CardDB.is_curse(id):
			continue
		if not SkirmishState.is_net_playable_spell(d):
			continue
		var sid: String = String(d.get("spell", {}).get("id", ""))
		if sid in _NET_CASTER_LOCAL_SPELLS or deny.has(id) or deny.has(sid):
			continue
		if int(d.get("cost", 0)) > 1:   # cap the roll at cheap spells (no 4-cost blowout)
			continue
		candidates.append(id)
	if candidates.is_empty():
		return
	var data: Dictionary = CardDB.get_card_data(candidates[randi() % candidates.size()])
	var targeting: String = String(data.get("targeting", "none"))
	var target_eid: int = _net_auto_target_for(targeting, caster_is_enemy)
	# A targeted spell that finds no legal target just fizzles (never resolve wrong-side).
	if targeting in ["enemy_creature", "friendly_creature", "any_creature", "any"] and target_eid < 0:
		return
	_show_info("Chaos Imp casts %s!" % data.get("name", "a spell"))
	_net_resolve_spell(data, target_eid, 1 if caster_is_enemy else 0)


## Pick a random valid target ENTITY id for an auto-cast net spell, from the caster's
## perspective: enemy/any → a random foe creature; friendly → a random own creature.
## Structures are never valid targets. Returns -1 when no legal target exists.
func _net_auto_target_for(targeting: String, caster_is_enemy: bool) -> int:
	var pool: Array = []
	if targeting in ["enemy_creature", "any_creature", "any"]:
		pool = _all_friendly(not caster_is_enemy)
	elif targeting == "friendly_creature":
		pool = _all_friendly(caster_is_enemy)
	var valid: Array = []
	for c in pool:
		if is_instance_valid(c) and not c.has_keyword("structure"):
			valid.append(c)
	if valid.is_empty():
		return -1
	return int(valid[randi() % valid.size()].entity_id)


# ── Networked choice (Copycat / Adaptable): the OWNER always makes the pick ──

## HOST: a CLIENT creature's on-enter needs a player choice. Ask the client to pick (it
## has the creature on its own board via the board sync); the answer returns as an
## IN_CHOICE intent and _net_apply_client_choice applies it host-authoritatively.
func _net_request_client_choice(card, kind: String) -> void:
	if not _is_host() or card == null or not is_instance_valid(card):
		return
	NetMatch.send_to_client({"t": NetMatch.EV_CHOICE, "eid": int(card.entity_id), "kind": kind})


## HOST: apply the client's pick for an EV_CHOICE prompt, then board-sync so both sides
## see the result. Validates the entity is still the client's own creature.
func _net_apply_client_choice(intent: Dictionary) -> void:
	if not _is_host() or _net_active_index != 1:
		return
	var eid: int = int(intent.get("eid", -1))
	var node = NetMatch.get_entity(eid)
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		return
	match String(intent.get("kind", "")):
		"keyword":
			var kw: String = String(intent.get("pick", ""))
			if kw in ["swift", "piercing", "armored", "thorns"]:
				if kw not in node.card_data.keywords:
					node.card_data.keywords.append(kw)
				node.update_stat_display()
				_net_sync_board()
		"copy_friendly":
			var src_eid: int = int(intent.get("pick", -1))
			if src_eid == eid:
				return   # can't copy itself
			var src = NetMatch.get_entity(src_eid)
			if src != null and is_instance_valid(src) and src.is_opponent:
				KeywordEffects._copy_creature_onto(node, src.card_data)
				node.update_stat_display()
				_net_sync_board()


## CLIENT: an EV_CHOICE arrived for one of our creatures — show the picker and send the
## answer back as IN_CHOICE. We never apply locally; the host applies + syncs the result.
func _net_client_show_choice(eid: int, kind: String) -> void:
	if not _is_client():
		return
	var node = NetMatch.get_entity(eid)
	match kind:
		"keyword":
			var kw: String = await _keyword_choice_overlay()
			if kw != "":
				NetMatch.send_intent({"t": NetMatch.IN_CHOICE, "eid": eid, "kind": "keyword", "pick": kw})
		"copy_friendly":
			var src = await _pick_friendly_creature(node, "Changeling — click a friendly to copy")
			if src != null and is_instance_valid(src):
				NetMatch.send_intent({"t": NetMatch.IN_CHOICE, "eid": eid,
					"kind": "copy_friendly", "pick": int(src.entity_id)})
