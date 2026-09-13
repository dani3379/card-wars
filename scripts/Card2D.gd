extends PanelContainer
class_name Card2D
## Card2D.gd — the live campaign-writ hand card and compact battlefield token.
## Cached cards use the same writ as a static texture plus live stat overlays.

signal played
signal destroyed
# Fired when current_hp would drop the card to dead. Listeners (Phantom Veil
# relic, Reborn on_death) can set current_hp back > 0 to cancel the death.
# If no listener rescues, _die() runs and destroyed fires.
signal will_die
## Fired the moment Last Stand saves this creature (once per fight) — Combat
## listens for rally passives (Paladin).
signal last_stand_fired
# Fires AFTER current_hp is reduced (any path: combat, spell, thorns, on-death
# damage). amount is the post-armor damage actually applied. Used by relics
# like Stalwart's Anvil, Wormwood, Spike Driver that need to react to a
# friendly being hit.
signal damaged(amount: int)
# Drag lifecycle — Combat listens so it can light up the slot the player is
# about to drop on. `dragging` fires each time the cursor moves while the
# card is held; `drag_ended` fires once when the mouse is released, before
# `played` (so highlights are cleared whether or not the drop is valid).
signal dragging(global_pos: Vector2)
signal drag_ended
# Right-click on a HAND card: ask Combat to dismiss it to the discard (the
# player-driven churn valve of the persistent hand). Combat gates the rest.
signal dismiss_requested
# Battlefield repositioning ("move"). A friendly creature already on the board
# can be dragged to an empty friendly slot during the player's turn. Combat
# owns the slot grid + hand layer, so Card2D only signals intent:
#   field_move_started — the grab crossed the move threshold and lifted off its
#       slot; Combat re-parents the card onto the free-layout hand layer so it
#       can follow the cursor (slot cells are CenterContainers that would fight
#       manual positioning).
#   field_move_dropped — released after a lift; Combat resolves it to the
#       nearest empty friendly slot or snaps it back home.
signal field_move_started
signal field_move_dropped(global_pos: Vector2)
#   aim_clear_requested — right-click on a friendly battlefield creature; Combat
#       lifts a sniper's standing aim order (no-op for unmarked creatures).
signal aim_clear_requested

# ── Writ-kit painters (scripts/ui/painters/, extracted 2026-07-14) ──────────
# Self-contained draw-only Controls for the card's physical material. The
# const names match the old inner classes, so internal call sites and
# Combat's `Card2D.WaxSeal` read unchanged.
const WritLeaf := preload("res://scripts/ui/painters/WritLeaf.gd")
const InkCartouche := preload("res://scripts/ui/painters/InkCartouche.gd")
const WaxSeal := preload("res://scripts/ui/painters/WaxSeal.gd")
const StatCaret := preload("res://scripts/ui/painters/StatCaret.gd")
const ParchmentPlate := preload("res://scripts/ui/painters/ParchmentPlate.gd")
const TallyMarks := preload("res://scripts/ui/painters/TallyMarks.gd")
const EmptyPlateSigil := preload("res://scripts/ui/painters/EmptyPlateSigil.gd")
const WritDetailDiamond := preload("res://scripts/ui/painters/WritDetailDiamond.gd")
const GemOrb := preload("res://scripts/ui/painters/StatGem.gd")
const ArmoredEdge := preload("res://scripts/ui/painters/ArmoredEdge.gd")
const LastStandCandle := preload("res://scripts/ui/painters/LastStandCandle.gd")


@export var card_id: String = ""
# Identity of this card's copy within RunState.deck (deck_uids). -1 for cards
# with no deck origin (tokens, curses, copies). Lets the combat draw pile carry
# per-copy upgrades through the play→death→discard→reshuffle lifecycle.
var deck_uid: int = -1
# Online Skirmish: stable cross-wire handle for a board creature, issued by the
# host (NetMatch.issue_entity_id) at placement. -1 in single-player / in hand —
# see docs/MULTIPLAYER_SKIRMISH_PLAN.md §8.
var entity_id: int = -1
var state: CreatureInstance = CreatureInstance.new()
@export var is_opponent: bool:
	get: return state.is_opponent
	set(value): state.is_opponent = value
@export var is_on_battlefield: bool:
	get: return state.is_on_battlefield
	set(value): state.is_on_battlefield = value
# When true, the card is being rendered in a non-interactive context
# (Card Gallery, Deck Viewer, Reward preview, etc.). Set BEFORE add_child
# so it's seen by _ready → _build_layout. Large gallery grids stay static and
# avoid scheduling presentation work that cannot be seen.
@export var static_display: bool = false
# When true, the live writ renderer builds empty stat seals. Used by
# CardTextureCache.bake() — the snapshot becomes a card with
# blank cost/ATK/HP discs, and the live overlay layer painted over the top
# fills in the actual numbers. Without this flag the baked numerals would
# show through and clash with the live overlay text on any stat change.
@export var bake_strip_stats: bool = false
# Sibling of bake_strip_stats for the RULES TEXT. The bake omits the description
# (StS model: bake the frame + art, but draw the text LIVE on top), so the baked
# texture never burns in a low-res raster of the rules — the live overlay in
# _build_baked_overlay_layout draws the same text with the font renderer, staying
# razor-sharp at any zoom. Without this the baked text would show through, doubled.
@export var bake_strip_desc: bool = false
# Sibling of bake_strip_desc for the card NAME. The bake paints the swallowtail
# cartouche furniture but leaves the name text BLANK; the live overlay draws the
# name with the font renderer (MSDF) so it stays razor-sharp at any zoom, instead
# of being a downscaled bitmap baked into the texture. Same StS model as the rules.
@export var bake_strip_name: bool = false
# Internal CardTextureCache mode: render only the compact field token's static
# art/gradient/blank seals. Live cards overlay stats, statuses, Doom and effects.
@export var compact_static_bake: bool = false
# When true, _build_layout dispatches to _build_baked_overlay_layout instead
# of the full live writ layout. That layout is just a TextureRect (pulled from
# CardTextureCache) plus a handful of live overlay nodes (cost / atk / hp /
# floop). update_stat_display still works through the same _cost_label /
# _atk_label / _hp_label refs, so combat logic is unchanged. Falls back to
# the live writ renderer if CardTextureCache has not pre-baked this card yet.
@export var live_baked_mode: bool = false
# Collection uses a native-resolution, non-mipmapped cache class. Keeping this
# explicit prevents its cheap gallery snapshot from masquerading as a 3x hand
# bake while letting the same lightweight overlay layout display either class.
@export var gallery_baked_mode: bool = false
# Foreground card slates set this only while Motion.deal_card holds the face at
# alpha zero. The overlay tree and final pixels stay identical, but the expensive
# RichTextLabel parse/shape moves to the next frame instead of sharing the card's
# construction frame. Reduce Motion callers leave it false because their cards
# are revealed immediately.
@export var defer_baked_rules_text: bool = false
var _pending_baked_rules: Array = []
# When true, a card whose card_data carries no `desc` (enemy-only creatures from
# EncounterDB are terse — {name,atk,hp,kw}) synthesises its rules text from its
# triggers + keywords so the face isn't blank. Opt-in: ONLY the battle-log hover
# preview sets it, so real in-hand/battlefield/reward faces keep the
# no-glossary-on-face rule (teaching stays in tooltips). See _synthesized_rules_text.
@export var synth_desc_if_empty: bool = false
# Per-card font override (used by Collection gallery font A/B test).
# When set, this Font replaces GameTheme.font_display for the name banner
# and stat orbs on this card. Bypasses CardTextureCache (override is per-
# instance, cache is keyed by card data — collisions would mix fonts).
@export var display_font_override: Font = null

var card_data: Dictionary = {}
var current_hp: int:
	get: return state.current_hp
	set(value): state.current_hp = value
var current_atk: int:
	get: return state.current_atk
	set(value): state.current_atk = value
var current_lane: int:
	get: return state.lane
	set(value): state.lane = value
# Sentinel for "ATK never displayed yet" — used by update_stat_display to
# emit a buff/debuff popup only on subsequent changes, not the first paint.
var _displayed_effective_atk: int = -999
# Same sentinel for HP (C2): the first paint of a fresh card must not read as
# a heal. See update_stat_display for the gain-only float rule.
var _displayed_hp: int = -999
var current_row: int:
	get: return state.row
	set(value): state.row = clampi(value, 0, 1)
var has_attacked_this_turn: bool:
	get: return state.has_attacked_this_turn
	set(value): state.has_attacked_this_turn = value
var will_floop: bool:
	get: return state.will_floop
	set(value): state.will_floop = value
var has_flooped_this_turn: bool:
	get: return state.has_flooped_this_turn
	set(value): state.has_flooped_this_turn = value
var last_stand_used: bool:
	get: return state.last_stand_used
	set(value): state.last_stand_used = value
var is_token: bool:
	get: return state.is_token
	set(value): state.is_token = value
# Oathbound Squire (bodyguard): the ward standing in this creature's column —
# damage this creature would take strikes the ward instead. State-derived by
# Combat._refresh_adjacency_buffs at every board mutation (null when unguarded,
# and always null on the net client, whose damage arrives pre-resolved).
var _ward_ref: WeakRef = null
var ward_by: Control:
	get:
		return _ward_ref.get_ref() as Control if _ward_ref != null else null
	set(value):
		_ward_ref = weakref(value) if value != null else null
var temp_atk_buff: int:
	get: return state.temp_atk_buff
	set(value): state.temp_atk_buff = value
# Persistent ATK buff (e.g. from Butcher's Cleaver) — counted in effective_atk
# but NOT wiped at end of turn. `persistent_atk_buff_rounds` decrements at
# start of each round (in Combat); when it reaches 0 the bonus is removed.
var persistent_atk_buff: int:
	get: return state.persistent_atk_buff
	set(value): state.persistent_atk_buff = value
var persistent_atk_buff_rounds: int:
	get: return state.persistent_atk_buff_rounds
	set(value): state.persistent_atk_buff_rounds = maxi(0, value)
# Adjacency ATK buff (Battle Drummer / Bannerman / Wolf Pack, etc.) — the live
# sum of neighbouring `adj_buff` sources, recomputed by Combat whenever the board
# changes (Combat._refresh_adjacency_buffs). Stored here so it shows on the ATK
# numeral, rides the net board snapshot (which serialises effective_atk), and
# applies to BOTH sides. Combat owns the value; the client leaves it 0 and reads
# the host's already-buffed atk straight off the snapshot.
var adj_atk_buff: int:
	get: return state.adjacency_atk_buff
	set(value): state.adjacency_atk_buff = value
# Relic ATK bonus — the live sum of the six relics that change what a creature
# swings for (swift_boots, glass_cannon, linked_banner, champions_belt,
# phalanx_stone, and steady_banner's round-1 −1). It lives here for one reason:
# until 2026-07-28 those six were added inside Combat._effective_attack, OUTSIDE
# this card, so the wax ATK seal and the hover provenance line both printed a
# number the creature did not actually swing for whenever the player held one
# (§4 #2 of COMBAT_LEGIBILITY_20260728 — "not a missing cue, a false one").
# Combat owns the value and rewrites it in _refresh_adjacency_buffs at every
# board mutation, exactly like adj_atk_buff above; the net client leaves it 0 and
# reads the host's already-folded atk off the snapshot. It may be NEGATIVE
# (steady_banner) — effective_atk() floors the TOTAL, never the component.
var relic_atk_buff: int:
	get: return state.relic_atk_buff
	set(value): state.relic_atk_buff = value
# Doom keyword — per-creature countdown to detonation. Lazily seeded from
# card_data.doom the first time it's needed (card_data is often assigned AFTER
# _ready, e.g. enemy placement), via _ensure_doom_init(). -999 = "not yet seeded".
var doom_counter: int:
	get: return state.doom_counter
	set(value): state.doom_counter = value
# Doom badge widgets, built in the compact battlefield layout. The badge shows
# the live countdown; the panel gives the red disc its frame.
var _doom_badge: Control = null
var _doom_label: Label = null
# The compact layout's root control, kept so a mid-fight Doom grant (Mark of
# Ash) can build the countdown badge late — it's normally built with the layout.
var _compact_root: Control = null
# The battlefield token's baked body (one TextureRect). Null on cards that
# aren't compact-with-cache — the death burn falls back when it is.
var _compact_face: TextureRect = null
# Live status rail (battlefield tokens): the top-right keyword roundels are
# rebuilt whenever the creature's keywords or transient statuses change, so a
# mid-fight Shield / Frozen / war-school Armored is visible on the token.
var _status_orbs: Array = []          # the roundel Panels currently on the rail
var _status_rail_sig: String = ""     # last-rendered signature (dirty check)
var _status_poll_accum: float = 0.0   # throttles the shared-clock rail poll
# One-node status roundels: the shared shader is immutable, while materials are
# cached per immutable rim/glyph pair (no Compatibility instance uniforms).
static var _status_roundel_shader_cache: Shader = null
static var _status_roundel_material_cache: Dictionary = {}
# Passive battlefield visuals used to give every seated Card2D its own _process
# callback. A full 4x4 board therefore ran 16 script callbacks and wrote 16
# transforms every rendered frame just for the decorative breathe. Compact live
# cards now share one 30 Hz clock. Weak refs keep this registry from owning cards;
# the elected driver hands the timer to another survivor when it leaves the tree.
const BATTLEFIELD_VISUAL_TICK_SEC := 1.0 / 30.0
static var _battlefield_visual_refs: Array = []
static var _battlefield_visual_driver: WeakRef = null
var _battlefield_visual_timer: Timer = null
# Battlefield cards render at ~73% size so 4 rows fit on screen without
# clipping. Hand cards stay full size for readability. Set before _ready
# (e.g. on instantiate) or via set_compact_mode() after.
var compact_mode: bool = false
# Armed by set_compact_mode(true) on a card that was a HAND card a moment ago,
# consumed the next time the card enters the tree (see _start_compact_morph).
var _compact_morph_pending: bool = false

# ── The flight's scale escrow (2026-08-03) ─────────────────────────────
# `Combat._play_landing_pop` is the ONE writer of this card's `scale` while it is
# in the air, and it establishes its rest pose by READING `card.scale` a frame
# after the placement. That read is only honest on a card at rest — and a card
# can be re-landed while a flight is still live (an on-enter that redeploys it, a
# push, a swap all call the landing again). Before the flight carried the writ's
# TURN that misread cost a couple of percent and nobody ever saw it; now the
# close takes `scale.x` most of the way to zero, so a second landing that
# mistook a mid-turn pose for "rest" would settle the card at a sliver of its
# width — a permanently invisible body on the board. The flight parks the truth
# here for its duration and hands it back on landing; a re-entrant landing reads
# the escrow instead of the pose. Deliberately NOT a full flight registry: the
# two-overlapping-flights case has its own (green, timing-dependent) behaviour in
# _play_landing_pop and this pass does not disturb it — it only guarantees that
# whatever happens, the pose the card is left in is a rest pose.
var flight_in_air: bool = false
var flight_rest_scale: Vector2 = Vector2.ONE

var _name_label: Label
var _atk_label: Label
var _hp_label: Label
var _cost_label: Label
var _desc_label: Label
var _type_label: Label
var _floop_indicator: Label  # inert: created hidden by layouts; floop UI is dead
# Bottom-of-card type plate (rarity gem + type text). Always present on both
# spells and creatures, mirrors the StS "Skill" tag. For creatures it's
# hidden when the FLOOP indicator activates — see update_floop_display.
var _type_plate: Control
var _rarity_strip: ColorRect
var _art_rect: Control
var _cost_badge: Control  # Panel (v3/legacy) or GemOrb (v4/compact) — both Control
var _frame_tex: TextureRect
var _atk_badge: HBoxContainer
var _hp_badge: HBoxContainer
var _default_border_color: Color
# v4 stat plates carry their own base text colour (dark-on-gold for ATK,
# light-on-red for HP). Cache the colours at build time so update_stat_display
# can restore them without forcing the legacy Color.WHITE that would render
# invisible against the gold shield.
var _atk_base_color: Color = Color.WHITE
var _hp_base_color: Color = Color.WHITE
var _atk_caret: Control = null   # ▲/▼ shape cue beside a buffed/debuffed ATK seal

var _is_hovered := false
var _is_being_dragged := false
# Hover-lift motion state: the quick rise tween and the elevation shadow that
# deepens as the card leaves the table. The shadow lives in a wrapper Control
# because Card2D is a PanelContainer — container layout stomps a direct
# child's inset offsets on every layout pass.
var _hover_tween: Tween = null
var _lift_shadow: Control = null
# The pick-up settle (see _start_drag). Its own slot rather than a reuse of
# _hover_tween: the hover tween is killed AT the grab, and this one has to
# outlive that kill by ~90 ms while the card firms up under the cursor.
var _grab_tween: Tween = null
# Desaturating wash shown over a hand card the current Command pool can't
# afford. Lazily built (see _ensure_unplayable_veil); toggled by set_affordable.
# A full-rect direct child so container layout fits it to the card automatically.
var _unplayable_veil: ColorRect = null
# The last thing set_affordable was told. Kept because the resting tint is now
# folded from TWO states (see _apply_hand_tint) and the discard mark can be
# toggled between two affordability refreshes.
var _affordable: bool = true
# Static flag: true while ANY Card2D is being dragged anywhere. Hand siblings
# read this in _on_mouse_entered to suppress their hover-pop animation —
# without it, dragging a card over the rest of the hand made each neighbour
# leap up in turn, which is visually noisy and obscures the drop target.
static var _any_card_dragging: bool = false
# NOTE (2026-08-25): a `_is_playing` latch used to be declared here and tested in
# four guards (the hover lift, the hover enter/exit pair and _start_drag) — but it
# was NEVER ASSIGNED anywhere in the file, so every one of those tests was a
# constant false and the protection they advertised did not exist. The reads are
# gone rather than left lying: what actually stops a card being re-grabbed in
# flight is `is_on_battlefield`, which Combat stamps at placement and which
# _start_drag already tests beside it. If a real "in flight, hands off" latch is
# ever wanted, it needs SETTING at played.emit() and CLEARING when the flight
# resolves — reinstating the variable alone would restore the same lie.
var _drag_offset := Vector2.ZERO

# ── Card lean (C1 of docs/ANIMATION_AUDIT_20260716.md §6) ─────────────
# The card leans into the hand it's held by. Two drivers, one damped owner:
# a DRAG leans into cursor velocity (you're swinging a piece of card stock
# around — it should trail), and a HOVER tilts toward the cursor's offset
# from the card's centre (you're pressing a finger on one corner of it).
# Both are the same technique every reference title uses (Balatro, HS, Snap,
# MTGA) and the thing that makes a card read as an object instead of a decal
# stuck to the pointer.
#
# OWNERSHIP: `rotation` has exactly one writer at a time. `_process` owns it
# only while `_lean_active` (a hand card being dragged or hovered) — the
# hover/hand tweens never tween rotation during that window, and the handoff
# back is clean: mouse-exit disables the lean and lets the existing
# hover-exit tween carry rotation from wherever the lean left it home to
# `_hand_target_rotation` (an interruption a tween handles fine because it
# reads the live value). Decorative: Reduce Motion never arms it.
const LEAN_DRAG_PER_VEL: float = 0.00040  # rad per px/sec of cursor speed
const LEAN_DRAG_MAX: float = 0.35         # rad — the doc's ±0.35 clamp
const LEAN_HOVER_MAX: float = 0.10        # rad — a tilt, not a spin
const LEAN_DAMP_DRAG: float = 14.0        # e-fold rate; higher = snappier
const LEAN_DAMP_HOVER: float = 9.0        # hover settles softer than drag
var _lean_active := false
var _lean_target := 0.0
var _lean_last_mouse_x := 0.0
# Battlefield move-drag state — distinct from the hand "play" drag above.
var _field_grabbing := false      # a left-press is active on a board creature
var _field_lifted := false        # the grab crossed the threshold → real drag
var _field_grab_start := Vector2.ZERO
const FIELD_MOVE_THRESHOLD := 10.0  # px the cursor must travel to start a move
# Gate for board interaction (move-drag). Combat sets this false while combat
# resolves / the enemy acts, so the player can't grab mid-swing.
static var board_interactive := true

# Witch-Shot (bridge_watcher relic, 2026-07-16): Combat raises this around a
# damage-spell resolve so take_damage lets the hit pass through ENEMY Armored
# and Shield. Static so every custom resolver's take_damage call is covered
# without threading a parameter through dozens of sites; Combat clears it after
# the resolve and defensively at every turn start.
static var spell_pierce_active: bool = false
# WHITELIST flag for effect-immune creatures (The Old King's Body, 2026-07-20).
# `take_damage` has ~120 call sites and no source parameter, so asking "was this
# an effect?" is unanswerable — but the INVERSE has exactly two answer points:
# the strike and the counter-strike inside _creature_attacks_creature. Combat
# raises this around those two lines only, so an effect_immune creature rejects
# everything else BY DEFAULT and no future effect can accidentally slip through.
# Same scoped-flag shape as spell_pierce_active above, including the defensive
# clear at every turn start.
static var strike_damage_active: bool = false
# Gate for playing cards OUT of hand (the play-drag). In skirmish Combat sets
# this false during the opponent's turn so hand cards can't be lifted (paired
# with the grey "unplayable" veil) — you shouldn't be able to grab a card while
# your foe is acting. Always true in solo (the phase gate covers that path);
# Combat re-arms it to true at the start of every combat scene so a locked net
# match can't leak the lock into a later solo fight.
static var hand_interactive := true
# Net mirror for the Last Stand save: the flare below is Card2D-local (it only
# ever shows on the machine that ran take_damage — the HOST in skirmish), so the
# host combat scene installs a callback here (_net_begin_combat) and the flare
# site calls it with the survivor. Hooked AT the flare so coverage is by
# construction — tokens, granted keywords, copies: anything that flares, mirrors.
# is_valid() is false for an unset callable AND for a freed combat scene, so solo
# and stale-scene cases are no-ops.
static var net_last_stand_cb: Callable = Callable()
# SIMULTANEOUS CLASH contract. Combat sets this true for the duration of a combat
# clash (Swift phase, main clash) so a creature that takes a LETHAL hit does NOT
# die on the spot — it sits at current_hp<=0, stays in the board array, and can
# still land its own already-scheduled strike (can_attack() ignores HP). Combat
# flushes the held deaths with _cleanup_dead() once both sides have swung, so
# mutual kills resolve together. False everywhere else → spells/abilities kill
# immediately as before. This is what makes the clash actually simultaneous
# instead of handing a de-facto Swift to whoever strikes first.
static var defer_deaths := false
var _hand_target_position := Vector2.ZERO
var _hand_target_rotation := 0.0
# Resting scale for hand cards. Set via set_hand_target by Combat._layout_hand
# (currently 0.8 for the Hearthstone-style smaller-cards-at-rest look). Hover
# scales to 1.15 — a 1.15/0.8 ≈ 1.44x visual pop relative to rest. Restored
# on _on_mouse_exited and _end_drag-not-played.
var _hand_target_scale := Vector2.ONE
# Tween that slides the card to its hand slot (draw / reflow). Killed when the
# card is hovered, dragged, or re-targeted so those snappy interactions win.
var _hand_tween: Tween = null

# ▲3 — the hand's reflow runs on a SPRING, position channel only.
#
# Rotation and scale stay on `_hand_tween`, deliberately. `_process` is the LEAN
# driver and `rotation` has exactly one writer at a time by construction (C1); a
# spring on the same channel would be a second writer during hover and drag, which
# is the one thing that contract forbids. Position has no such owner in the hand.
var _hand_spring: Motion.Spring = null
var _hand_spring_active := false
var _hand_spring_delay := 0.0
# The last value the spring itself wrote. If `position` no longer matches it,
# SOMETHING ELSE has taken the channel and the spring yields — see
# `_tick_hand_spring`. The spring is the least authoritative writer of the three
# and must always be the one that gives way.
var _hand_spring_wrote := Vector2.INF
var _lunge_tween: Tween = null
var _lunge_scale_tween: Tween = null

# ▲2 THE SMEAR — see _play_strike_smear.
#
# THE STRETCH IS DERIVED, NOT CHOSEN, and the first build got this wrong in the
# way ★3 exists to prevent: do the arithmetic before the painter.
#
# A smear covers the ground the body crossed, so its length is BODY + TRAVEL. The
# drive is 7 px of pull-back plus 26·strength forward — 33 px against a 150 px
# token, so the honest figure is 1 + 33/150 = **1.22**, not the 1.55 the pitch
# guessed. Over-stretching is what made the first version read as a doubled card
# rather than a streak: a ghost longer than the distance travelled has no motion
# to explain it, so the eye files it as a second object.
#
# It is computed per blow from the real travel (`_smear_stretch`) so a heavy
# strike, which genuinely covers more ground, genuinely smears longer.
#
# ALPHA 0.16, not 0.30. At 0.30 a full-art copy is legible AS A CARD; the whole
# technique depends on the ghost being read as motion and never resolved as an
# object. Halving it is what turns the double-exposure into weight.
const SMEAR_ALPHA: float = 0.16
const SMEAR_PINCH: float = 0.96   # a token barely narrows over 33 px of travel


## Body + travel, over body. Clamped so a glancing tap still reads and a heavy
## blow never turns the token into a ribbon.
static func _smear_stretch(travel_px: float, body_px: float) -> float:
	if body_px <= 1.0:
		return 1.0
	return clampf(1.0 + absf(travel_px) / body_px, 1.10, 1.45)
var _recoil_tween: Tween = null
# True while hold_lunge_apex has the lunge tweens PAUSED (★8 killing blow).
# _combat_tween_active must treat the held lunge as live — a paused tween
# reports is_running() == false, and the idle bob would otherwise reclaim
# position.y mid-hold and drag the frozen killer back toward its rest bob.
var _lunge_hold_active: bool = false
# Set true just before a sacrificed creature is destroyed so _die() plays the
# "ash away upward" ritual variant instead of the normal shrink-and-fade.
var _sacrifice_death: bool = false
# Latched the first time _die() runs. Combat nulls the field slot synchronously on
# the destroyed signal, so the corpse is normally unreachable — but any path that
# holds a direct reference across the kill and calls take_damage/try_die again
# would otherwise re-emit destroyed and double-fire every on-death payoff
# (on_death effect, coin_landed gold, encounter death hooks). Cheap insurance.
var _dead: bool = false
# Set by Combat when the clash path already sounded the kill at the moment of
# impact (play_sfx("creature_death")). _die() checks it so the deferred-death
# flush doesn't play a second death cue for the same kill.
var death_cue_played: bool = false

const CARD_W := 225
const CARD_H := 300
const CARD_SIZE := Vector2(CARD_W, CARD_H)
# Battlefield (compact) cards switch to a LANDSCAPE aspect — creature art
# is generally wider than tall, so a landscape on-field token uses slot
# space far better than a shrunken portrait. The hand layout (drag, hover,
# detail panel) still uses portrait CARD_SIZE; only the slot occupant
# resizes to BATTLEFIELD_SIZE in _apply_compact_layout.
const BATTLEFIELD_W := 200
const BATTLEFIELD_H := 150
const BATTLEFIELD_SIZE := Vector2(BATTLEFIELD_W, BATTLEFIELD_H)
const COMPACT_SCALE := 0.50
# Single source of truth for the board/hand seam — also read by Combat's slot
# highlight so the slot lights up EXACTLY when a release there would play (no
# dead band). A hand card is "played" when its CENTRE is released above this
# fraction of viewport height; below it (over the resting hand) the drag
# cancels back to hand. Wildfrost-style: the WHOLE board is a live drop zone,
# so this sits at the board's bottom edge (≈ back-row bottom / hand top), NOT
# up at mid-screen. The old 0.72 demanded the card centre clear y≈648 on the
# 1600×900 design space — above the entire board (back row ends at y≈737) — so
# the player had to overshoot the board to drop on the back row. Raise toward
# 1.0 to shrink the cancel band; lower to force a longer drag before a drop
# counts.
const PLAY_THRESHOLD_Y := 0.82

# ── The play gesture's beat clock (2026-08-03) ─────────────────────────
# GRAB → HOLD → RELEASE, and the release has THREE distinct endings the player
# must be able to tell apart at a glance: the card is played (Combat's flight +
# play_wax_press take over), the player changed their mind and set it back down
# (_end_drag's put-down), or Combat REFUSED it (play_return_to_hand). The first
# two used to be indistinguishable snaps and the third was indistinguishable
# from a routine reflow — so the whole gesture ended in three ways that all
# looked like the same shrug.
#
# These stay OFF Motion.time() on purpose. The scaling policy is "combat FLOW"
# (Motion.gd's own words) — the clash, the pacing Combat awaits on. This is the
# player's own hand moving, in the same family as the hover lift and the fan
# reflow, neither of which is scaled either; speeding it up with the combat
# setting would make the game harder to hold, not faster to watch. The BOARD
# half of the gesture (play_wax_press) is combat flow and IS scaled.
const DRAG_SCALE := Vector2(0.85, 0.85)
# Shorter than Motion.SETTLE (0.18) by design: a grab is a snatch, a put-down
# is a placement. Both use the house BACK-out so the card overshoots and firms.
const GRAB_SETTLE := 0.09
const PUTDOWN_BEAT := 0.16
const REFUSAL_BEAT := 0.28
# A dragged card is held ABOVE the board, so it keeps the hover's elevation
# shadow — a little under full, since it rides lower and smaller than a hovered
# card. Before this the grab ZEROED the shadow and a picked-up card stopped
# being an object and became a decal stuck to the pointer.
const DRAG_SHADOW_A := 0.72

# ── The board's half of the gesture: the wax press's bite ──────────────
# How long play_wax_press squashes before the seal makes contact. Two rungs
# because the press has two jobs depending on how the card arrived: a plain
# drop-in only has a 12% squash to travel (PRESS_BITE), while a card that flew
# in TURNED has to open out of its foreshortening first (PRESS_BITE_TURN) — and
# 70 ms from edge-on to flat is a pop-in, not a turn. 0.13 is deliberately the
# same figure Motion.flip_out spends on a half turn: the house already priced
# this beat once and the press should not be cheaper than the reveal.
#
# Combat is the caller and owns which rung a given landing gets (it is the only
# code that knows the flight's reach), and it reads these names rather than
# keeping its own copies — the ground ring has to fire on the BITE, and a second
# copy of the number kept in step by comment is how that drifts.
const PRESS_BITE := 0.07
const PRESS_BITE_TURN := 0.13

# Painted-frame zone rects, in pixel coords of the 300x400 source frame
# (assets/frames/frame_creature_*.png). Each rect is the readable interior of a
# painted region — change a number here, the corresponding label moves. This is
# the single source of truth for text positioning on the v3 (PNG-frame) layout.
# v4 (procedural) uses normalized 0–1 anchors instead and does not consume these.
const FRAME_REF_SIZE := Vector2(300, 400)
# Card scaled to 225x300 from the 300x400 ref → 0.75 ratio.
const FRAME_TO_CARD_SCALE := 0.75

# ─────────────────────────────────────────────────────────────────────────
# CARD TEXT POSITIONS (read this before changing any number below)
# ─────────────────────────────────────────────────────────────────────────
#
# Each label (cost, name, type, desc, ATK, HP, FLOOP) is placed by anchoring
# to a single POINT_* (the painted-region center, in 300x400 frame ref coords)
# via _center_at_point(label, point, size). The helper sets symmetric offsets
# so the label rect is centered on the point — change a POINT_ and the label
# moves; change a SIZE_ and only the label's text-fit box changes.
#
# HOW TO RE-DERIVE THESE NUMBERS:
#   1. Run:   python tools/measure_frame.py
#   2. The script reads the frame PNG pixel-by-pixel, finds the bbox of each
#      painted region (red orbs by color, banner by dark gray, scroll by gold,
#      well by parchment tan), and prints a Vector2 for each center.
#   3. Paste the printed values into the POINT_* constants below.
#
# DO NOT EYEBALL THESE VALUES.  Earlier guesses put POINT_NAME ~20px above
# where the banner actually is — the gold ornament on top of the banner made
# it visually appear higher. The script measures pixel data, so it can't be
# fooled the same way. If you tweak any value by hand, re-run the script first
# to know the true painted center, then adjust from there.
#
# WHY POINT+SIZE (NOT ANCHOR RECTS):
#   - Godot's Label.vertical_alignment=CENTER misaligns when the rect is
#     smaller than the font's line box (known Godot 4 bug, see forum thread
#     "vertical-alignment-center-wont-center"). Generous SIZE_* avoids this.
#   - Asymmetric anchor rects also bias where horizontal_alignment=CENTER
#     computes the visual midpoint. Point+symmetric-offsets sidesteps that.
#
# FONT OPTICAL CENTERING:
#   - Caps-only text (NAME, CREATURE, FLOOP, all stat numerals) sits visually
#     above geometric center because the font's line box reserves descender
#     space the glyphs don't use.
#   - GameTheme wraps Cinzel in FontVariations with spacing_bottom = -3,
#     which shrinks the line box and shifts centered text ~1.5px down to its
#     optical center. If text still looks high after re-measuring, push that
#     value more negative; if it looks low, push toward 0.
## v5 frame layout (frame_v5_b — gold trim variant). Pixel-measured from
## the actual PNG: art window y=16-177, banner y=197-223 (center 210),
## text well y=252-357 (center 304). Orbs use direct corner anchors —
## POINT_COST/ATK/HP are kept for fallback only, the orb positioning code
## hangs them past the card edges via offsets instead.
const POINT_COST    := Vector2(35.0, 35.0)     # legacy — orbs use direct anchors
const POINT_NAME    := Vector2(150.0, 210.0)   # cream ribbon banner center
const POINT_TYPE    := Vector2(150.0, 235.0)   # below banner — keyword strip
const POINT_DESC    := Vector2(150.0, 304.0)   # text well center
const POINT_ATK     := Vector2(30.0, 378.0)    # legacy — orbs use direct anchors
const POINT_HP      := Vector2(270.0, 378.0)   # legacy — orbs use direct anchors
const POINT_FLOOP   := Vector2(150.0, 390.0)   # between bottom orbs (creatures)
# Spell cards have no bottom orbs, so the targeting tag ("FRIENDLY" / "ENEMY" /
# "ANY CREATURE" / "ANY TARGET") used to sit at POINT_FLOOP and clip out of the
# 400px card frame. Anchor it inside the text-well lower band instead — fully
# visible without overlapping the description (well ends at y≈354).
const POINT_SPELL_TARGET := Vector2(150.0, 372.0)

const SIZE_COST     := Vector2(48, 36)
const SIZE_NAME     := Vector2(210, 38)
const SIZE_TYPE     := Vector2(170, 26)
# Text well is 105px tall × ~220px wide (pixel-measured frame_v5_b at y=252-357).
# SIZE_DESC fills it completely so wrap has more room and font isn't cramped.
const SIZE_DESC     := Vector2(240, 100)
const SIZE_STAT     := Vector2(48, 36)    # shared by ATK and HP
const SIZE_FLOOP    := Vector2(150, 24)

# Vertical pixel nudge applied to the cost / ATK / HP numeral labels inside
# their stat seal containers. Positive = move text DOWN, negative = move UP.
# Why this exists: Godot's Label vertical_alignment = CENTER centers on the
# font's full line box (ascent + descent), but caps/digits don't occupy the
# descender region — they visually sit in the UPPER portion of the line box,
# so the rendered character appears HIGH inside the orb. The stat seal's
# drop shadow below the sphere also shifts the painted "visual center" of
# the orb DOWNWARD relative to the container's geometric center. Both
# effects compound to put numerals visibly above the orb's bright center.
# This offset bypasses Godot's font-metric-driven centering with a direct
# pixel shift. Tune by eye: bigger value pushes numerals further down.
const ORB_NUMERAL_Y_OFFSET := 3


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	# _process is the card LEAN's driver (C1) and nothing else — it stays OFF
	# until a drag/hover arms it, so the hand, the board, the gallery and the
	# bake pipeline don't pay N per-frame callbacks for a transform that isn't
	# moving. Same discipline as the shared battlefield visual timer.
	set_process(false)
	if compact_mode:
		_apply_compact_layout()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if card_data.is_empty() and card_id != "":
		card_data = CardDB.get_card_data(card_id)
	if card_data.size() > 0:
		if is_creature():
			current_hp = card_data.hp
			current_atk = card_data.atk

	_build_style()
	_build_layout()


func set_compact_mode(enabled: bool) -> void:
	# Switch a card between hand-size (full) and battlefield-size (compact-token).
	# Swaps BOTH the dimensions AND the internal layout tree — the two modes
	# have entirely different visual identities (full card vs art token).
	if compact_mode == enabled:
		return
	if not enabled:
		_idle_bob_enabled = false
		_unregister_battlefield_visuals()
	# HAND → BOARD IS A HARD CUT (2026-08-03). This tears down the 225×300 writ
	# and rebuilds a 200×150 landscape token in a single frame, OFF-TREE, in the
	# middle of the play gesture — the player watches the sheet they were holding
	# get swapped for a different object before the flight has even started. It
	# cannot be tweened from here (create_tween needs the node in the tree, and
	# Combat calls this between remove_child and add_child), so arm it and let the
	# card stamp its new face in when it is seated. Scoped to the hand→board
	# transition on purpose: enemy placements, summons, bakes and previews are all
	# built compact from the start (`compact_mode = true` before _ready) and never
	# had a face to lose.
	var morphing: bool = enabled and not compact_mode and not static_display
	compact_mode = enabled
	_apply_compact_layout()
	# Null cached widget references first, then free children. Otherwise any
	# update_stat_display / update_floop_display call between teardown and
	# rebuild would touch freed nodes.
	_name_label = null
	_atk_label = null
	_hp_label = null
	_cost_label = null
	_desc_label = null
	_type_label = null
	_floop_indicator = null
	_type_plate = null
	_rarity_strip = null
	_art_rect = null
	_cost_badge = null
	_frame_tex = null
	_atk_badge = null
	_hp_badge = null
	_doom_badge = null
	_doom_label = null
	_compact_root = null
	_compact_face = null
	_baked_face = null
	_gilt_mat = null
	# The hand-only furniture is a child too, so the free() loop below takes it —
	# and these three were left holding freed references (rebuild_face already
	# nulls them; this path never did). Every consumer happens to guard with
	# is_instance_valid, but the drag now LIGHTS the lift shadow on its way to the
	# board, so a played card reaches here with a live one every single time.
	_lift_shadow = null
	_unplayable_veil = null
	_discard_mark = null
	for child in get_children():
		child.free()
	_build_layout()
	if morphing:
		_compact_morph_pending = true
		# Normally the card is out of tree here (Combat calls this between
		# remove_child and add_child) and NOTIFICATION_ENTER_TREE arms the beat.
		# A caller that switches an already-seated card gets it immediately —
		# without this the flag would sit armed and fire on some unrelated later
		# re-parent.
		if is_inside_tree():
			_start_compact_morph.call_deferred()


## The new face is STRUCK IN rather than cut in, so hand → board reads as the
## writ being sealed onto the board instead of swapped for a different object
## (see set_compact_mode).
##
## Two constraints decide the whole shape of this. (1) It animates _compact_root
## — Card2D's OWN child — and never the card: Combat owns `scale` / `position` /
## `rotation` on a card in flight (_play_landing_pop's arc, then play_wax_press),
## and a second writer there is exactly the class of bug this file keeps warning
## about. (2) It rides `modulate` and NOTHING else, because Card2D is a
## PanelContainer and Container.fit_child_in_rect RESETS a child Control's
## `scale` and `rotation` to identity on every sort — measured, not assumed. A
## scale swell here would be silently zeroed by whichever layout pass happened to
## land inside the beat. `modulate` survives a sort, so the morph is a hot flash
## fading to true colour: the forge/seal language Motion.forge_strike already
## speaks, and the one channel that cannot be stomped.
func _start_compact_morph() -> void:
	if not _compact_morph_pending:
		return
	_compact_morph_pending = false
	if not compact_mode or not is_inside_tree() or static_display:
		return
	if _compact_root == null or not is_instance_valid(_compact_root):
		return
	# Decorative — the token arriving is the information, and it arrives either
	# way. Headless probes skip it for the same reason Motion's FX primitives do.
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if DisplayServer.get_name() == "headless":
		return
	var root: Control = _compact_root
	# Starts hot and PARTLY transparent, not at zero alpha: the writ vanishes out
	# of the hand in the same frame, so fading up from nothing reads as a blink in
	# the middle of the gesture rather than one object becoming another.
	root.modulate = Color(1.75, 1.55, 1.20, 0.40)
	# Tween owned by root, so the cached-bake swap (_on_battlefield_texture_ready
	# frees and rebuilds _compact_root) takes it with it instead of leaving a
	# tween writing at a dead object.
	var tw := root.create_tween()
	tw.tween_property(root, "modulate", Color(1.28, 1.18, 1.04, 1.0),
		Motion.time(0.09)).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate", Color.WHITE, Motion.time(0.22)) \
		.set_ease(Tween.EASE_OUT)


func rebuild_face() -> void:
	# Re-render a HAND card whose card_data changed in place (Forgefire's
	# in-combat "+"). Same teardown recipe as set_compact_mode: null every
	# cached widget ref, free the children, rebuild from the live data. The
	# baked frame/art is keyed by card id (unchanged); name, rules text and
	# stats render live, so the forged numbers land on the rebuilt face.
	_hide_detail_panel()
	_name_label = null
	_atk_label = null
	_hp_label = null
	_cost_label = null
	_desc_label = null
	_type_label = null
	_floop_indicator = null
	_type_plate = null
	_rarity_strip = null
	_art_rect = null
	_cost_badge = null
	_frame_tex = null
	_atk_badge = null
	_hp_badge = null
	_doom_badge = null
	_doom_label = null
	_compact_root = null
	_compact_face = null
	_baked_face = null
	_gilt_mat = null
	_lift_shadow = null
	_unplayable_veil = null
	_discard_mark = null
	for child in get_children():
		child.free()
	if is_creature():
		current_hp = card_data.hp
		current_atk = card_data.atk
	_build_style()
	_build_layout()


func _apply_compact_layout() -> void:
	# Battlefield cards swap to LANDSCAPE dimensions — internal layout uses
	# anchor-based positioning (anchor_left = 0.06 etc.) so children rescale
	# automatically to the new aspect. Avoid touching `scale` here: Container
	# parents fight with it and the slot reservation desyncs from the visual
	# footprint.
	var target_size: Vector2 = BATTLEFIELD_SIZE if compact_mode else CARD_SIZE
	custom_minimum_size = target_size
	size = target_size
	# Hand-card transforms (0.8x rest scale, bottom-centre pivot, fan
	# rotation) need to reset when the card moves to the battlefield — the
	# slot positions cards at scale 1 / rotation 0 / pivot top-left.
	scale = Vector2.ONE
	rotation = 0.0
	pivot_offset = Vector2.ZERO
	_hand_target_scale = Vector2.ONE
	_hand_target_position = Vector2.ZERO
	_hand_target_rotation = 0.0


func is_creature() -> bool:
	return card_data.get("type", "creature") == "creature"

func is_spell() -> bool:
	return card_data.get("type", "") == "spell"

func is_armament() -> bool:
	return card_data.get("type", "") == "armament"

func has_keyword(kw: String) -> bool:
	if not card_data.has("keywords"):
		return false
	return card_data.keywords.has(kw)


## One-line spell footer (2026-07-10): "{contract} · {economy}".
## Contract = the targeting mode, or an authored CardDB `scope` string on
## untargeted board spells ("ALL ENEMIES"). Economy = EXHAUST / RETAIN — now
## visible on targeted spells too (Banish, Offering, Cataclysm...), where the
## old single-slot footer buried it in the prose. The "SPELL —" prefix was
## dropped 2026-07-10 (a grid of spells all repeating it was pure noise, and
## the footer line itself is spell-only furniture): the type word prints only
## as the fallback when there is no contract and no economy to declare. The
## retired INSTANT filler named a timing distinction this game doesn't have.
func _spell_footer_text() -> String:
	if is_armament():
		return "ARMAMENT · ALLY · EXHAUST"
	if CardDB.is_curse(String(card_data.get("id", ""))):
		return "CURSE"
	var contract := ""
	match String(card_data.get("targeting", "none")):
		"enemy_creature":    contract = "TARGET ENEMY"
		"friendly_creature": contract = "TARGET ALLY"
		"any_creature":      contract = "ANY CREATURE"
		"any":               contract = "ANY TARGET"
		"lane":              contract = "TARGET LANE"
		"friendly_then_enemy": contract = "ALLY · ENEMY"
		"two_enemies":       contract = "TWO ENEMIES"
		"friendly_lane":     contract = "ALLY · LANE"
		_:                   contract = String(card_data.get("scope", ""))
	var parts: Array[String] = []
	if contract != "":
		parts.append(contract)
	var kws: Array = card_data.get("keywords", [])
	if "exhaust" in kws:
		parts.append("EXHAUST")
	elif "retain" in kws:
		parts.append("RETAIN")
	if parts.is_empty():
		return "SPELL"
	return " · ".join(parts)


func _spell_target_label() -> String:
	# Maps the spell data's `targeting` field to a short display string. Returns
	# empty for "none" so non-targeted spells leave the bottom strip clean.
	# Plain text — the display font (Lilita One) doesn't ship the U+2192 arrow
	# or U+2726 star glyphs we used earlier, so they rendered as tofu boxes.
	match String(card_data.get("targeting", "")):
		"enemy_creature":    return "ENEMY"
		"friendly_creature": return "FRIENDLY"
		"any_creature":      return "ANY CREATURE"
		"any":               return "ANY TARGET"
		"lane":              return "LANE"
		"friendly_then_enemy": return "ALLY THEN ENEMY"
		"two_enemies":       return "TWO ENEMIES"
		"friendly_lane":     return "ALLY THEN LANE"
		_:                   return ""

func has_floop() -> bool:
	# Vestigial: no card carries a `floop` key (always false). Kept because a
	# local screenshot tool still probes it.
	return card_data.has("floop")

## Swift is the muster delay's exception — the Cross Blitz "Swiftstrike" role.
## It keeps its existing meaning (strikes in the pre-phase, before the main
## clash) and gains a second one: a Swift body is ready the round it arrives.
## The two readings agree — Swift has always meant "this one is already moving."
## Swift and Charge both fight the round they arrive; they differ in REACH.
##   Swift  — strikes in the pre-phase (before the clash), bodies only.
##   Charge — no pre-phase, but it may reach the enemy themselves.
## So Swift is the better trader and Charge is the better closer, and neither is
## strictly the other's upgrade.
func ignores_muster_delay() -> bool:
	return has_keyword("swift") or has_keyword("charge") \
		or bool(state.war_cry_swift) or bool(state.drummer_swift)


## Force the status rail to re-read after the muster sweep. The rail is
## signature-polled, but the sweep runs at the top of the round when nothing
## else about the body changes — without this the Mustering mark lingers for a
## poll after the creature is actually ready, which is the kind of stale badge
## players correctly report as a bug.
func refresh_muster_mark() -> void:
	_refresh_status_rail()


## An INERT structure is scenery: it fills a back-row slot, holds a charge
## counter, and nothing can touch it. An ATTACKABLE one (card_data.attackable) is
## a real obstacle — it still never swings, but creatures can hit it and spells
## can target it, so the charge counter it displays is an affordance the player
## can actually race.
##
## Added 2026-07-28. The Trebuchet shipped as a 0/99 inert structure that
## displayed a live "CHARGE n/3" badge — a visible, incrementing threat with no
## way to interact with it at all. That is the worst shape a mechanic can take:
## it teaches the player to look for counterplay and then punishes them for
## looking. Prefer attackable for anything that shows a countdown.
func is_inert_structure() -> bool:
	if not has_keyword("structure"):
		return false
	return not bool(card_data.get("attackable", false))


func can_attack() -> bool:
	# The muster delay: a body that entered play this round has not formed up and
	# does not swing in the clash that ends its arrival round.
	if not state.ready_to_swing and not ignores_muster_delay(): return false
	if has_attacked_this_turn: return false
	if will_floop: return false
	if has_flooped_this_turn: return false
	if state.is_frozen: return false
	# Structures are board objects (Pyres, Mausoleums, Altars) — they hold
	# charge counters and trigger encounter effects but never swing themselves.
	if has_keyword("structure"): return false
	# Fortifications are attackable battlefield objectives, not soldiers.
	# They block a lane and take damage but never initiate or counter a strike.
	if bool(card_data.get("fortification", false)): return false
	if card_data.get("passive", "") == "cannot_attack_wall": return false
	if card_data.get("passive", "") == "siege": return true
	return true

## What this creature ACTUALLY swings for — the one number the seal, the hover
## provenance line and every strike site are allowed to disagree about never.
## `relic_atk_buff` joined the sum on 2026-07-28; it is the only component that
## can be negative (steady_banner's round-1 −1), so the total is floored here
## rather than at the call sites. Combat._effective_attack already ended in
## maxi(0, atk), so this only moves the floor to where the number is BORN: a seal
## reading "-1" would be a fresh lie, and `take_damage(effective_atk())` — a real
## call shape in six places — would have HEALED its target on a negative.
func effective_atk() -> int:
	return maxi(0, current_atk + temp_atk_buff + persistent_atk_buff
		+ adj_atk_buff + relic_atk_buff)


# ═══════════════════════════════════════════
#  CARD BACKGROUND
# ═══════════════════════════════════════════

func _build_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Color(0, 0, 0, 0)
	s.set_border_width_all(0)
	s.set_corner_radius_all(0)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	# Drop shadow lifts the card off the scene background. shadow_size 6
	# fits inside CardTextureCache's 12px BAKE_PAD so it survives baking.
	# Offset (0,3) puts the shadow below the card — natural light-from-above.
	# Without this the painted card edge dissolved into the dark scene bg.
	s.shadow_color = Color(0, 0, 0, 0.70)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", s)
	_default_border_color = Color(0, 0, 0, 0)


# ═══════════════════════════════════════════
#  LAYOUT — layered: art → frame → banner → content
# ═══════════════════════════════════════════

func _find_card_art() -> Texture2D:
	var cid = card_data.get("id", "")
	var name_id = card_data.get("name", "").to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = null
	if is_spell() or is_armament():
		art = CardArtAliases.try_load_spell_art(cid)
		if art == null:
			art = CardArtAliases.try_load_spell_art(name_id)
	if art == null:
		art = CardArtAliases.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art("e_" + name_id)
	return art


func _build_layout() -> void:
	if card_data.is_empty():
		return
	_atk_base_color = Color.WHITE
	_hp_base_color = Color.WHITE
	if compact_mode:
		_build_compact_layout()
	elif live_baked_mode and (
			CardTextureCache.has_gallery(card_data) if gallery_baked_mode
			else CardTextureCache.has(card_data)):
		_build_baked_overlay_layout()
	else:
		_build_chart_proto()


# ═══════════════════════════════════════════
#  COMPACT (BATTLEFIELD) LAYOUT — token style
#  Full-card art, corner stats only. No name banner, no description, no
#  rarity strip — just the visual identity needed to recognize a creature
#  on the field. Hand-style detail panel still appears on hover.
# ═══════════════════════════════════════════

func _build_compact_layout() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_compact_root = root
	if not compact_static_bake:
		var cached_background: Texture2D = \
			CardTextureCache.get_battlefield_texture(card_data)
		if cached_background != null:
			_build_compact_cached_background(root, cached_background)
			_build_compact_stat_layer(root, false)
			_finish_compact_live_layout(root)
			return
		elif DisplayServer.get_name() != "headless":
			# Synthetic summons can be authored at runtime and therefore miss all
			# route/deck warmers. Render the normal face for two frames, request one
			# shared snapshot, then swap this live token onto it when ready.
			if not CardTextureCache.battlefield_texture_ready.is_connected(
					_on_battlefield_texture_ready):
				CardTextureCache.battlefield_texture_ready.connect(
					_on_battlefield_texture_ready)
			CardTextureCache.bake_battlefield(card_data)

	var card_art: Texture2D = _find_card_art()
	if card_art == null:
		var placeholder_path := "res://assets/creatures/kindling_alt.png"
		if ResourceLoader.exists(placeholder_path):
			card_art = load(placeholder_path)
	var art_clip := Control.new()
	art_clip.clip_contents = true
	art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_clip.anchor_left = 0.04
	art_clip.anchor_right = 0.96
	art_clip.anchor_top = 0.04
	art_clip.anchor_bottom = 0.96
	root.add_child(art_clip)
	_art_rect = art_clip
	if card_art:
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)

	# Dark gradient overlay at the bottom so corner badges read against any art.
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.anchor_left = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_top = 0.70
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	# Compact battlefield stat orbs — same GemOrb class as hand cards,
	# scaled down. Shape encodes the stat (hex=cost, shield=ATK, drop=HP),
	# so we drop the kenney sword/heart silhouettes that read "cheap" at
	# 18px. The number sits on the gem directly, Hearthstone-style.

	# Compact battlefield stat orbs — round gems matching the hand-card
	# trio. Shape uniformity reads cleaner than polygons at this scale;
	# position + colour disambiguate ATK/HP.
	#
	# No cost orb on the battlefield: mana cost is a "what does it take to
	# play this" stat, and the card has already been played. Leaving it on
	# the token confused the read (looked like another stat). Cost still
	# shows on the hover detail panel. _cost_badge/_cost_label stay null —
	# set_display_cost guards on is_on_battlefield + a null check.

	# Bottom-left ATK and bottom-right HP gems (creatures only).
	# 38px orbs / 18px light-faced numerals: at battlefield distance the old
	# 32px orb + 14px dark-on-gold numeral washed into the gem's gloss
	# highlight (verified on a 1920×1080 capture — ATK was illegible while
	# the light-on-red HP read fine). White-with-dark-outline reads on any
	# fill, which is why every AAA card game stamps stats that way.
	if is_creature():
		# v7 chart material: matte wax seals (same 38px boxes + 18px light
		# numerals — the verified battlefield-legibility setup — only the
		# glossy sphere paint changed).
		var token_metal := Color(0.62, 0.50, 0.26)
		var c_atk := _chart_seal(GameTheme.ATK_GOLD_SHIELD, token_metal, true)
		c_atk.anchor_left = 0.0; c_atk.anchor_right = 0.0
		c_atk.anchor_top = 1.0;  c_atk.anchor_bottom = 1.0
		c_atk.offset_left = 3;   c_atk.offset_right = 41
		c_atk.offset_top = -41;  c_atk.offset_bottom = -3
		root.add_child(c_atk)
		_atk_base_color = Color(1, 0.98, 0.90)
		if not bake_strip_stats:
			_atk_label = _build_orb_number_label(str(current_atk), 18, true)
			c_atk.add_child(_atk_label)
		_atk_badge = null

		var c_hp := _chart_seal(GameTheme.HEALTH_RED_DROP, token_metal, true)
		c_hp.anchor_left = 1.0; c_hp.anchor_right = 1.0
		c_hp.anchor_top = 1.0;  c_hp.anchor_bottom = 1.0
		c_hp.offset_left = -41; c_hp.offset_right = -3
		c_hp.offset_top = -41;  c_hp.offset_bottom = -3
		root.add_child(c_hp)
		_hp_base_color = Color(1, 0.97, 0.92)
		if not bake_strip_stats:
			_hp_label = _build_orb_number_label(str(current_hp), 18, true)
			c_hp.add_child(_hp_label)
		_hp_badge = null
	if compact_static_bake:
		return

	# Floop indicator (only shown when the player has toggled floop on).
	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 10)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_floop_indicator.add_theme_constant_override("outline_size", 4)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.anchor_left = 0.0
	_floop_indicator.anchor_right = 1.0
	_floop_indicator.anchor_top = 0.0
	_floop_indicator.anchor_bottom = 0.0
	_floop_indicator.offset_top = 30
	_floop_indicator.offset_bottom = 46
	_floop_indicator.visible = false
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floop_indicator)

	# Keyword + status roundels along the top-right so Swift / Piercing /
	# Armored etc. stay readable at a glance on battlefield tokens. The rail is
	# LIVE — a keyword or status gained mid-fight (war-school Armored, a granted
	# Shield, Frozen/Stunned) re-renders it; see _refresh_status_rail.
	_refresh_status_rail(true)
	_build_fortification_tag(root)
	# The rail re-checks itself on a throttled shared-clock poll (cheap signature
	# diff) so the ~30 keyword-mutation sites in Combat.gd don't each need an
	# explicit refresh call. Register even in reduce-motion / no-bob paths so the
	# status fallback remains alive without a per-card frame callback.
	_register_battlefield_visuals()

	# Doom countdown badge — a big red disc in the TOP-LEFT (keyword orbs own
	# top-right, ATK/HP own the bottom corners). THIS is the telegraph: a boss
	# "Doom 2" must read as a scary clock from across the board.
	if has_keyword("doom"):
		_build_doom_badge(root)

	# rampage / lifelink / overrun / formation all ship SVG icons now, so the
	# icon rail above already shows them. The old cryptic RMP/OVR/FRM/LL violet
	# text chips were redundant duplicates of those icons (and unreadable as
	# 3-letter codes), so they were removed — keyword detail still lives in the
	# hover tooltip.


# ═══════════════════════════════════════════
#  LIVE STATUS RAIL — battlefield keyword/effect roundels
# ═══════════════════════════════════════════
#
# The top-right icon rail re-renders whenever the creature's keyword list or
# transient statuses (Shield, Frozen, Stunned, this-round Armored/Thorns)
# change, so an effect gained mid-fight shows on the token itself, not just in
# the hover panel. Printed/granted keywords keep the gilt ink-roundel voice;
# transient statuses speak in their own tint so "will expire" reads apart from
# "is part of the card". Refresh triggers: update_stat_display (most mutation
# sites already call it) + a throttled _process signature poll for the rest.

func _build_compact_cached_background(root: Control, texture: Texture2D) -> void:
	# The snapshot includes an 8 px logical gutter so edge shading and wax
	# seals never clip. The live token keeps its 200x150 lane footprint.
	var face := TextureRect.new()
	face.name = "CompactFace"
	face.texture = texture
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = -8.0
	face.offset_top = -8.0
	face.offset_right = 8.0
	face.offset_bottom = 8.0
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(face)
	# The token's whole body in ONE CanvasItem — which is what lets the death
	# burn be a shader at all (see Motion.burn_away). Held so _die can set it
	# alight without walking the tree.
	_compact_face = face
	# Art is already flattened into the cached face.
	_art_rect = null


func _on_battlefield_texture_ready(key: String) -> void:
	# A bake landing on a DYING card would free _compact_root — and with it the
	# face the death burn is tweening — so the burn's queue_free would never
	# fire and the corpse would linger on the board forever. The card is on its
	# way out; it has no use for a fresh face.
	if _dead:
		return
	if not compact_mode or compact_static_bake or not is_inside_tree() \
			or key != CardTextureCache.battlefield_cache_key(card_data):
		return
	if _compact_root == null or not is_instance_valid(_compact_root):
		return
	if CardTextureCache.battlefield_texture_ready.is_connected(
			_on_battlefield_texture_ready):
		CardTextureCache.battlefield_texture_ready.disconnect(
			_on_battlefield_texture_ready)
	# Replace only the compact face. Threat flags and other Combat-owned direct
	# children remain intact while every cached widget reference is refreshed.
	_compact_root.free()
	_compact_root = null
	_compact_face = null
	_baked_face = null
	_gilt_mat = null
	_atk_label = null
	_hp_label = null
	_atk_badge = null
	_hp_badge = null
	_atk_caret = null
	_floop_indicator = null
	_status_orbs.clear()
	_status_rail_sig = ""
	_doom_badge = null
	_doom_label = null
	_build_compact_layout()
	update_stat_display()


func _build_compact_stat_layer(root: Control, paint_seals: bool) -> void:
	if not is_creature():
		return
	var token_metal := Color(0.62, 0.50, 0.26)
	var c_atk: Control
	var c_hp: Control
	if paint_seals:
		c_atk = _chart_seal(GameTheme.ATK_GOLD_SHIELD, token_metal, true)
		c_hp = _chart_seal(GameTheme.HEALTH_RED_DROP, token_metal, true)
	else:
		# Cached faces already contain the blank seals. These transparent
		# anchors carry only live numerals, so buffs and damage stay cheap.
		c_atk = Control.new()
		c_hp = Control.new()
		c_atk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c_atk.anchor_left = 0.0
	c_atk.anchor_right = 0.0
	c_atk.anchor_top = 1.0
	c_atk.anchor_bottom = 1.0
	c_atk.offset_left = 3
	c_atk.offset_right = 41
	c_atk.offset_top = -41
	c_atk.offset_bottom = -3
	root.add_child(c_atk)
	_atk_base_color = Color(1, 0.98, 0.90)
	_atk_label = _build_orb_number_label(str(current_atk), 18, true)
	c_atk.add_child(_atk_label)
	_atk_badge = null

	c_hp.anchor_left = 1.0
	c_hp.anchor_right = 1.0
	c_hp.anchor_top = 1.0
	c_hp.anchor_bottom = 1.0
	c_hp.offset_left = -41
	c_hp.offset_right = -3
	c_hp.offset_top = -41
	c_hp.offset_bottom = -3
	root.add_child(c_hp)
	_hp_base_color = Color(1, 0.97, 0.92)
	_hp_label = _build_orb_number_label(str(current_hp), 18, true)
	c_hp.add_child(_hp_label)
	_hp_badge = null


func _finish_compact_live_layout(root: Control) -> void:
	# Floop intent, keyword/status roundels, and Doom all change during combat,
	# so they deliberately remain outside the cached face.
	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 10)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_floop_indicator.add_theme_constant_override("outline_size", 4)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.anchor_left = 0.0
	_floop_indicator.anchor_right = 1.0
	_floop_indicator.anchor_top = 0.0
	_floop_indicator.anchor_bottom = 0.0
	_floop_indicator.offset_top = 30
	_floop_indicator.offset_bottom = 46
	_floop_indicator.visible = false
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floop_indicator)
	_refresh_status_rail(true)
	_build_fortification_tag(root)
	_register_battlefield_visuals()
	if has_keyword("doom"):
		_build_doom_badge(root)



func _build_fortification_tag(root: Control) -> void:
	# Compact cards normally omit names, so an objective gets one short live
	# label that survives both cached and uncached battlefield rendering.
	if not bool(card_data.get("fortification", false)):
		return
	var tag := Label.new()
	tag.text = "GATE"
	tag.anchor_left = 0.22
	tag.anchor_right = 0.78
	tag.anchor_top = 0.0
	tag.anchor_bottom = 0.0
	tag.offset_top = 7.0
	tag.offset_bottom = 32.0
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 18)
	if GameTheme.font_title != null:
		tag.add_theme_font_override("font", GameTheme.font_title)
	tag.add_theme_color_override("font_color", Color(1.0, 0.91, 0.66))
	tag.add_theme_color_override("font_outline_color", Color(0.04, 0.025, 0.015, 0.98))
	tag.add_theme_constant_override("outline_size", 5)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)

const _STATUS_RAIL_CAP := 5

func _status_signature() -> String:
	# Cheap change-detector for the rail. Anything that should alter the rail
	# must be folded in here.
	# Match the set the rail actually RENDERS (include_badged=false). Doom is
	# badged separately and never appears in the rail, so folding its live value
	# into the signature only forced a needless teardown+rebuild of an identical
	# rail on every doom tick.
	var parts: PackedStringArray = []
	for entry in _active_effect_entries(false):
		parts.append("%s:%s" % [String(entry.get("id", "")), String(entry.get("display", ""))])
	return ",".join(parts)


func _active_effect_entries(include_badged: bool = true) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	if state.has_shield:
		_add_active_effect(out, seen, "shield")
	if state.is_frozen:
		_add_active_effect(out, seen, "frozen")
	if state.stunned:
		_add_active_effect(out, seen, "stunned")
	# The muster delay. Same family as Frozen/Stunned — "does not swing this
	# round" — and it MUST be shown: a body that silently refuses to fight reads
	# as a bug, which is the whole reason this rail exists.
	if is_on_battlefield and not state.ready_to_swing and not ignores_muster_delay():
		_add_active_effect(out, seen, "mustering")

	# ROUND-SCOPED RIDERS (2026-07-28). A spell or a passive can rewrite what a
	# body DOES for a round — strike in the Swift pre-phase, hit every opposing
	# lane, swing twice, soak an ally's blow — and until now NONE of it touched
	# the token. The rule changed and the card said nothing, which is the same
	# defect the muster mark above was added to fix: a body that behaves
	# differently from what it prints reads as a bug. They ride this rail rather
	# than inventing a second surface, and each names its own device because the
	# id is a STATE, not a registered keyword.
	if is_on_battlefield:
		if (state.war_cry_swift or state.drummer_swift) \
				and not card_data.get("keywords", []).has("swift"):
			_add_active_effect(out, seen, "granted_swift", "", "swift")
		if state.charges_this_turn:
			_add_active_effect(out, seen, "charging", "", "charge")
		if state.battle_order_second_strike:
			_add_active_effect(out, seen, "double_strike", "", "rampage")
		if state.redirecting:
			_add_active_effect(out, seen, "redirecting", "", "guardian")
		if state.challenge_any_lane:
			_add_active_effect(out, seen, "challenging", "", "overrun")
		if state.hp_floor:
			_add_active_effect(out, seen, "warded", "", "last_stand")
		# ward_by is hp_floor's SIBLING — Honor Guard's column_ward floors the HP,
		# Oathbound Squire's bodyguard eats the blow outright — and shipping one
		# marked while the other stayed invisible would be worse than marking
		# neither: the player would learn to read the absence of a mark as "no
		# protection here" and be wrong half the time.
		if ward_by != null and is_instance_valid(ward_by) and ward_by.current_hp > 0:
			_add_active_effect(out, seen, "guarded", "", "guardian")
		# Sword on Credit's bill. The sword is already in the line and the
		# reckoning lands NEXT round — a cost the player must plan Command around
		# while it is still avoidable, which makes it exactly the wrong thing to
		# reveal only at the moment it is charged.
		if int(state.credit_due_round) < 999999:
			_add_active_effect(out, seen, "debt_due", "", "sacrifice")
		# The Old King's Body. This one is the player's MONEY: every spell,
		# potion and ability aimed at it is thrown away, so the refusal has to be
		# legible BEFORE the cast, not discovered by wasting a card on it.
		if state.effect_immune:
			_add_active_effect(out, seen, "effect_immune", "", "structure")
		# THE FIGHT'S OWN RULE (2026-07-29, COMBAT_LEGIBILITY §4 #10). An encounter
		# passive can lend the enemy line Piercing or Thorns — the Nexus's bristle
		# round, the boar herd's charge, a Mercenary that crosses 4 ATK — and the
		# grant is resolved by LOOKUP at the moment of the blow, so until now it
		# reached no device and no orb: the token was pixel-identical to an
		# unbuffed one. Combat mirrors the live answer into `encounter_grants` (its
		# own card_data key, deliberately NOT `keywords` — see
		# Combat._refresh_encounter_keyword_grants for the reasons), and this is its
		# only reader.
		#
		# Enemy-side only, because the rule is: a deserter carries its whole
		# card_data across to your banner (Combat._desert_enemy_to_player), and an
		# orb promising a rule that no longer applies to that body is the same lie
		# pointed the other way.
		if is_opponent:
			var printed: Array = card_data.get("keywords", [])
			for g in card_data.get("encounter_grants", []):
				var gid := String(g)
				# A body that already PRINTS the keyword takes its own gilt device
				# from the keyword loop below — two orbs for one rule reads as two
				# rules (the same guard granted Swift makes against War Cry).
				if printed.has(gid):
					continue
				_add_active_effect(out, seen, "granted_%s" % gid, "", gid)

	# Armaments live on the creature's combat copy. Keep a named entry in the
	# hover/status data so the attachment remains visible even when its effect
	# is not itself a keyword (Bell, Witchbrand, Forked Spear, Arbalest).
	var gear: Dictionary = card_data.get("equipped_armament", {})
	if not gear.is_empty():
		var gear_id := "armament_%s" % String(gear.get("id", "equipped"))
		var icon_kw := String(gear.get("icon", ""))
		out.append({
			"id": gear_id,
			"display": String(gear.get("name", "Armament")),
			"desc": String(gear.get("desc", "Equipped for this fight.")),
			"tex": GameTheme.get_keyword_icon(icon_kw),
			"glyph": GameTheme.GILT_BRIGHT,
			"rim": Color(0.72, 0.52, 0.22, 0.92),
		})
		seen[gear_id] = true

	# TRIGGER MARKS (2026-07-25). A battlefield token is 104×136 and prints stats
	# + keyword devices only — a creature's on_death / passive / aura rules were
	# invisible on the board, which is the "I can't tell what the enemy's cards
	# do" complaint. These marks are deliberately FUTURE-FACING: on_enter and
	# on_play have already resolved by the time a body is standing, so surfacing
	# them would be history, not a threat. Hand cards print their full rules text
	# and need none of this, hence the is_on_battlefield gate.
	if is_on_battlefield:
		_add_trigger_effect_entries(out, seen)

	var kws: Array = card_data.get("keywords", [])
	if state.temp_armored and not kws.has("armored"):
		_add_active_effect(out, seen, "armored", " (this round)")
	# Venom Tip's grant. It reached the rail through the keyword loop below, which
	# meant a one-round envenoming printed as a PERMANENT rule — the rail claiming
	# a card is something it isn't is worse than the rail staying quiet.
	if state.temp_poison:
		_add_active_effect(out, seen, "poison", " (this round)")
	if (state.temp_thorns or state.bonus_thorns > 0 \
			or state.shield_wall_thorns) and not kws.has("thorns"):
		_add_active_effect(out, seen, "thorns", " (this round)")
	# Pike Square's Thorns is not "this round" — it holds exactly as long as the
	# square stays closed, so it gets its own suffix rather than a false clock.
	elif state.square_thorns and not kws.has("thorns"):
		_add_active_effect(out, seen, "thorns", " (square held)")

	for kw in kws:
		var k := String(kw)
		if seen.has(k):
			continue
		if k == "floop":
			continue
		if k == "doom" and not include_badged:
			continue
		if not _keyword_is_active_on_board(k):
			continue
		_add_active_effect(out, seen, k)
	return out


## Rail entries for standing rules that are NOT keywords, so nothing else on a
## battlefield token can show them. `wither` / `doom` are registered keywords and
## get their own orbs from the keyword loop — adding them here would double-stamp
## the rail, so they are deliberately absent.
##
## `on_death` is the exception, and it is why this used to lie (2026-07-27). It IS
## a registered keyword, so a PLAYER card printing it gets its orb from that loop.
## An ENEMY never does: `EncounterDB.make_card_data` builds `keywords` from the
## `kw` list alone while copying `on_death` into its own key — so 118 of 653 enemy
## entries carried a death trigger that was STRUCTURALLY incapable of reaching the
## rail (the act-2 Standard Bearer debuffs your whole line's ATK when it dies, and
## nothing on the token ever said so). We mark it here only when the keyword loop
## won't, so the two paths can never double-stamp.
##
## Only standing/future effects qualify: on_enter and on_play have already
## resolved by the time a body is standing, so surfacing them would be history
## rather than a threat.
func _add_trigger_effect_entries(out: Array, seen: Dictionary) -> void:
	# One shared rim/glyph pair keeps these a family, distinct from the transient
	# status tints above and the gilt printed keywords below.
	var rim := Color(0.68, 0.46, 0.60, 0.92)
	var glyph := Color(0.94, 0.80, 0.92)
	var kws: Array = card_data.get("keywords", [])
	var marks: Array = []
	# `passive` is a bare String field with no keyword and no device — a Royal
	# Guard's or Siegewright's standing order was completely unreadable on board.
	if String(card_data.get("passive", "")) != "":
		marks.append({"id": "trig_passive", "kw": "formation", "display": "Standing Order"})
	# The death rider. Guarded on `kws` so a player card that prints the keyword
	# takes the keyword loop's orb instead and this never fires — see the block
	# comment above for why the enemy always falls through.
	# A SPENT Reborn is not a death rider any more. Reborn is a once-per-body
	# on_death `type` rather than a keyword, so the dict stays on the card after
	# it has already fired — and the mark went on promising a revive that could
	# never happen again. Same family as the temp-grant lie: a mark claiming an
	# effect the body no longer has is worse than no mark at all.
	var death_rider: Dictionary = card_data.get("on_death", {})
	var reborn_spent: bool = String(death_rider.get("type", "")) == "reborn" \
		and state.reborn_used
	if not kws.has("on_death") and not death_rider.is_empty() and not reborn_spent:
		marks.append({
			"id": "trig_on_death", "kw": "on_death",
			"display": str(KeywordEffects.KEYWORDS.get("on_death", {}).get("display", "On-Death")),
			"desc": str(KeywordEffects.KEYWORDS.get("on_death", {}).get("desc", "")),
		})
	# The aura fields only earn a mark when the card doesn't already print the
	# adj_buff keyword (several do), or the rail would show the same device twice.
	if not kws.has("adj_buff"):
		if not Dictionary(card_data.get("adj_buff", {})).is_empty():
			marks.append({"id": "trig_adj_buff", "kw": "adj_buff", "display": "Bannered Aura"})
		elif not Dictionary(card_data.get("type_buff", {})).is_empty():
			marks.append({"id": "trig_type_buff", "kw": "adj_buff", "display": "Warchief's Aura"})
	for m in marks:
		var mid := String(m["id"])
		if seen.has(mid):
			continue
		var tex: Texture2D = GameTheme.get_keyword_icon(String(m["kw"]))
		if tex == null:
			continue   # unregistered device — the rail drops null-texture entries anyway
		# Enemy card_data carries an empty `desc`, so a mark that can land on an
		# enemy must bring its own or the hover reads blank.
		out.append({
			"id": mid,
			"display": String(m["display"]),
			"desc": String(m.get("desc", card_data.get("desc", ""))),
			"tex": tex,
			"glyph": glyph,
			"rim": rim,
		})
		seen[mid] = true


## `icon_id` names the device to borrow when the entry's own id is a STATE rather
## than a registered keyword (the round-scoped riders). The rail drops
## null-texture entries, so an id with no device of its own would silently never
## appear — which is exactly the failure these entries exist to fix.
func _add_active_effect(out: Array, seen: Dictionary, id: String,
		display_suffix: String = "", icon_id: String = "") -> void:
	if id == "" or seen.has(id):
		return
	var colors := _active_effect_colors(id)
	var display := _active_effect_display(id) + display_suffix
	out.append({
		"id": id,
		"display": display,
		"desc": _active_effect_desc(id),
		"tex": GameTheme.get_keyword_icon(icon_id if icon_id != "" else id),
		"glyph": colors["glyph"],
		"rim": colors["rim"],
	})
	seen[id] = true


func _keyword_is_active_on_board(id: String) -> bool:
	match id:
		"shield":
			return state.has_shield
		"last_stand":
			return not last_stand_used
		"summon", "on_enter", "sacrifice", "exhaust", "retain", "adjacent":
			return false
	return KeywordEffects.KEYWORDS.has(id)


func _active_effect_display(id: String) -> String:
	match id:
		"frozen":
			return "Frozen"
		"stunned":
			return "Stunned"
		"mustering":
			return "Forming Up"
		"granted_swift":
			return "Swift"
		"granted_piercing":
			return "Piercing"
		"granted_thorns":
			return "Thorns"
		"charging":
			return "Charging"
		"double_strike":
			return "Battle Order"
		"redirecting":
			return "Covering"
		"challenging":
			return "Challenging"
		"warded":
			return "Warded"
		"guarded":
			return "Guarded"
		"debt_due":
			return "Bill Due"
		"effect_immune":
			return "Untouchable"
		"doom":
			return "Doom %d" % _live_doom_value()
		"wither":
			return "Wither %d" % int(card_data.get("wither", 0))
	if KeywordEffects.KEYWORDS.has(id):
		return str(KeywordEffects.KEYWORDS[id].get("display", id.capitalize()))
	return id.capitalize()


func _active_effect_desc(id: String) -> String:
	match id:
		"frozen":
			return "Skips combat this round, then thaws."
		"stunned":
			return "Skips combat this round."
		"mustering":
			return "Cannot attack this round. Can attack next round."
		"granted_swift":
			return "Strikes in the Swift pre-phase this round, before the clash."
		"granted_piercing":
			return "The fight's own rule lends it Piercing: a killing blow reads on past the body it fells."
		"granted_thorns":
			return "The fight's own rule lends it Thorns: it bites back at whatever strikes it."
		"charging":
			return "Attacks every opposing lane this round. Each target strikes back."
		"double_strike":
			return "Attacks twice this round. Each target strikes back."
		"redirecting":
			return "Takes the blows aimed at the creatures beside it this round."
		"challenging":
			return "May attack any lane this round, not just the one across."
		"warded":
			return "Its HP cannot be driven below 1 while the ward stands."
		"guarded":
			return "A bodyguard in its column takes the blows aimed at it."
		"debt_due":
			return "The reckoning for this sword comes due next round."
		"effect_immune":
			return "Only a creature's strike touches it. Spells, abilities, keywords, potions and relics do nothing."
	if KeywordEffects.KEYWORDS.has(id):
		return str(KeywordEffects.KEYWORDS[id].get("desc", ""))
	return ""


func _active_effect_colors(id: String) -> Dictionary:
	match id:
		"shield":
			return {"glyph": Color(0.65, 0.85, 1.0), "rim": Color(0.55, 0.75, 0.95, 0.9)}
		"frozen":
			return {"glyph": Color(0.78, 0.94, 1.0), "rim": Color(0.60, 0.85, 1.0, 0.9)}
		"stunned":
			return {"glyph": Color(1.0, 0.80, 0.32), "rim": Color(0.95, 0.72, 0.28, 0.9)}
		"mustering":
			# Cold bone — a body waiting, not a body harmed. Deliberately away
			# from Stunned's amber so "not ready yet" never reads as "crippled".
			return {"glyph": Color(0.82, 0.78, 0.68), "rim": Color(0.66, 0.62, 0.52, 0.9)}
		"armored":
			return {"glyph": Color(0.72, 0.82, 0.95), "rim": Color(0.60, 0.72, 0.90, 0.9)}
		"thorns":
			return {"glyph": Color(0.72, 0.92, 0.60), "rim": Color(0.58, 0.82, 0.50, 0.9)}
		# The round-scoped riders share ONE hot ember tint so they read as a family
		# — "this body is doing something extra this round" — distinct from the
		# cold transient statuses above and the gilt printed keywords below.
		# granted_piercing / granted_thorns are the encounter's LENT keywords. They
		# take the ember family rather than their own keyword tints (Thorns' green,
		# Piercing's gilt) on purpose: the whole point of the orb is that this rule
		# is not printed on the card, and matching the printed colour would hide it.
		"granted_swift", "charging", "double_strike", "challenging", "granted_piercing", "granted_thorns":
			return {"glyph": Color(1.0, 0.72, 0.36), "rim": Color(0.95, 0.58, 0.24, 0.92)}
		# Protective riders take the shield family's blue instead — a ward is not
		# an attack, and colouring it like one would mislead at a glance.
		"redirecting", "warded", "guarded", "effect_immune":
			return {"glyph": Color(0.74, 0.88, 1.0), "rim": Color(0.58, 0.78, 0.98, 0.92)}
		# A bill is neither an attack nor a protection — it is a LIABILITY, and it
		# gets the only warning colour on the rail so it cannot be mistaken for
		# either family at a glance.
		"debt_due":
			return {"glyph": Color(1.0, 0.52, 0.42), "rim": Color(0.92, 0.40, 0.30, 0.92)}
	return {"glyph": GameTheme.GILT_BRIGHT, "rim": Color(0.62, 0.50, 0.26, 0.85)}


func _live_doom_value() -> int:
	if doom_counter != -999:
		return doom_counter
	return int(card_data.get("doom", 0))


## Ids whose glossary line names the BEAT but not the EFFECT. "On-Death: effect
## triggers when this creature dies" tells the player a rite is armed and nothing
## whatsoever about what it does — and on a battlefield token, which prints no
## rules text at all, that was the entire read. These get the card's own printed
## rules appended so the mark answers "what happens", not just "when".
const _TRIGGER_RAIL_IDS := {
	"on_death": true, "doom": true, "wither": true, "adj_buff": true,
	"trig_passive": true, "trig_adj_buff": true, "trig_type_buff": true,
}


func _active_effect_tooltip(entry: Dictionary) -> String:
	var display := String(entry.get("display", ""))
	var desc := String(entry.get("desc", ""))
	if is_on_battlefield and _TRIGGER_RAIL_IDS.has(String(entry.get("id", ""))):
		var rules := String(card_data.get("desc", ""))
		# Skip when the rules ARE the glossary line (a vanilla keyword-only card)
		# so the tooltip never prints the same sentence twice.
		if rules != "" and rules != desc:
			desc = rules if desc == "" else "%s\n%s" % [desc, rules]
	if desc == "":
		return "Active now: %s" % display
	return "Active now: %s\n%s" % [display, desc]


# ── KEYWORD COSTUMES ───────────────────────────────────────────────────────
# A keyword whose only expression is a chip flying past has to be re-learned
# every single time it fires. A COSTUME inverts that trade: the rule becomes a
# visible property of the BODY before it ever triggers, so firing is a CHANGE TO
# A FAMILIAR OBJECT rather than the arrival of an unfamiliar one. That is why
# Divine Shield reads with no text on it, and a costume costs ZERO at fire time.
#
# The status rail cannot do this job and it is worth writing down why: its
# roundel is 30px with a 6px inset, so the glyph inside is 18px — below this
# project's own documented ~20px mush floor. The rail is an inventory you HOVER,
# not a costume you read across the board.
#
# A costume must therefore break the SILHOUETTE, own a LARGE contiguous area, or
# alter an object already >= 38px. Both costumes here take the third route, which
# is also why neither needed new art.
var _shield_seal: Control = null
var _swift_rake: Control = null
var _armored_edge: Control = null
var _last_stand_candle: Control = null


func _refresh_costumes() -> void:
	if _compact_root == null or not is_instance_valid(_compact_root):
		return
	if not is_on_battlefield or static_display:
		return

	# ARMORED is part of the body's construction, not a fact that arrives only
	# after the hit. Printed and round-scoped grants both reach has_keyword()
	# because the latter are added to the live card_data for their duration.
	var want_armored: bool = has_keyword("armored")
	var have_armored: bool = _armored_edge != null and is_instance_valid(_armored_edge)
	if want_armored and not have_armored:
		_build_armored_edge()
	elif not want_armored and have_armored:
		_clear_armored_edge()

	# LAST STAND is one visible reserve. The candle exists only while that save
	# remains armed; consuming it changes the active-effect signature and gutters
	# it on this same refresh.
	var want_candle: bool = has_keyword("last_stand") and not last_stand_used
	var have_candle: bool = _last_stand_candle != null \
		and is_instance_valid(_last_stand_candle)
	if want_candle and not have_candle:
		_build_last_stand_candle()
	elif not want_candle and have_candle:
		_clear_last_stand_candle(last_stand_used)

	var want_seal: bool = state.has_shield
	var have_seal: bool = _shield_seal != null and is_instance_valid(_shield_seal)
	if want_seal and not have_seal:
		_build_shield_seal()
	elif not want_seal and have_seal:
		_break_shield_seal()

	# SWIFT is the one rider that earns a costume rather than a rail orb, and the
	# reason is scale: War Cry moves the WHOLE LINE into the pre-phase, so the
	# question the player is asking is not "what does this one body do" but "who
	# strikes first this round" — a board-wide question the 18px rail glyph
	# cannot answer (see the costume header). A granted-Swift body therefore grows
	# a hard bright bar down its LEADING edge, pointing the way it will strike.
	# Granted only: a body that PRINTS Swift is a known quantity the player drafted
	# and already reads by its keyword device — the costume is for the CHANGE.
	var want_rake: bool = (state.war_cry_swift or state.drummer_swift) \
		and not card_data.get("keywords", []).has("swift")
	var have_rake: bool = _swift_rake != null and is_instance_valid(_swift_rake)
	if want_rake and not have_rake:
		_build_swift_rake()
	elif not want_rake and have_rake:
		_clear_swift_rake()


## SHIELD — the writ is SEALED SHUT. 52px of wax at full opacity, deliberately
## off-centre and off-axis like a real seal pressed by a hand in a hurry.
##
## This reverses a documented revert. The previous attempt drew an 8px crack
## INSIDE the 38px HP stat seal, which was unreadable and was pulled. The lesson
## was not "seals don't work" — it was CHANGE THE SILHOUETTE, don't add detail
## inside something already small. So this is its own 52px blob carrying no
## numeral, and when it goes it goes by BREAKING, which is a silhouette event.
func _build_shield_seal() -> void:
	var s: Control = WaxSeal.new()
	s.name = "ShieldSeal"
	# Cold seal-blue, DARK and desaturated. The first pass used a light saturated
	# blue and read as a glossy plastic pill — the exact "jelly button" failure
	# WaxSeal's own header says the 2026-07-19 rework existed to kill. Wax is a
	# dark matte material that earns its highlight from one ridge, so the base
	# colour has to sit well below the lit edge it is about to grow.
	s.wax = Color(0.17, 0.29, 0.44)
	s.seed_text = "shield_%s" % String(card_data.get("id", "x"))
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ON THE SCRIM, not over the art. The token carries a 118x45 dark band between
	# the ATK and HP seals that exists for badge legibility and that nothing has
	# ever used. Putting the seal there costs ZERO art occlusion — the player
	# recognises a creature by its painting, and the first pass sat squarely on
	# this one's face — and the dark ground gives the wax its best contrast.
	# STRADDLING the art/scrim boundary, and larger than the 38px stat seals. On
	# the scrim alone, at stat-seal size and in line with them, it read as a THIRD
	# STAT — an empty blue orb beside ATK and HP. A seal is not a circle in a row
	# of circles: it is pressed across an edge, at its own size, off the axis
	# everything else is aligned to.
	s.position = Vector2(76, 86)
	s.size = Vector2(48, 48)
	s.pivot_offset = Vector2(24, 24)
	s.rotation = -0.26
	s.z_index = 6
	_compact_root.add_child(s)
	_shield_seal = s
	# Decorative entrance only — the seal's PRESENCE is the information and it is
	# already on screen by the end of this frame either way.
	if not (UserSettings != null and UserSettings.reduce_motion):
		s.scale = Vector2(1.45, 1.45)
		s.modulate.a = 0.0
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "scale", Vector2.ONE, Motion.time(0.13)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "modulate:a", 1.0, Motion.time(0.10))


## GRANTED SWIFT — the body is already leaning into the charge.
##
## Takes the "own a LARGE contiguous area" route rather than the silhouette one,
## because a granted-Swift beat can land on eight bodies at once and eight
## changed silhouettes would read as a board glitch rather than an order. A full-
## height bar on the LEADING edge (right for your line, left for the foe's) is
## large enough to survive the mush floor, points the direction the blow travels,
## and costs no art occlusion — the token's edge carries nothing.
func _build_swift_rake() -> void:
	var bar := Panel.new()
	bar.name = "SwiftRake"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# The rider family's ember, run hot at the striking edge and falling away —
	# a flat bar reads as UI chrome, a graded one reads as speed.
	sb.bg_color = Color(1.0, 0.78, 0.42, 0.95)
	sb.border_color = Color(1.0, 0.55, 0.18, 0.85)
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(1.0, 0.50, 0.14, 0.55)
	sb.shadow_size = 7
	bar.add_theme_stylebox_override("panel", sb)
	# Leading edge: the side the blow travels toward. An enemy body strikes left.
	var lead_right: bool = not is_opponent
	bar.anchor_top = 0.0
	bar.anchor_bottom = 1.0
	bar.anchor_left = 1.0 if lead_right else 0.0
	bar.anchor_right = bar.anchor_left
	bar.offset_left = -5.0 if lead_right else 0.0
	bar.offset_right = 0.0 if lead_right else 5.0
	bar.offset_top = 6.0
	bar.offset_bottom = -6.0
	bar.z_index = 7
	_compact_root.add_child(bar)
	_swift_rake = bar
	# Decorative entrance only — the bar's PRESENCE is the information, so under
	# Reduce Motion it simply exists from this frame.
	if not (UserSettings != null and UserSettings.reduce_motion):
		bar.modulate.a = 0.0
		bar.scale = Vector2(1.0, 0.55)
		bar.pivot_offset = Vector2(2.5, bar.size.y * 0.5)
		var tw := bar.create_tween().set_parallel(true)
		tw.tween_property(bar, "modulate:a", 1.0, Motion.time(0.12))
		tw.tween_property(bar, "scale", Vector2.ONE, Motion.time(0.18)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _clear_swift_rake() -> void:
	if _swift_rake == null or not is_instance_valid(_swift_rake):
		_swift_rake = null
		return
	var bar := _swift_rake
	_swift_rake = null
	if UserSettings != null and UserSettings.reduce_motion:
		bar.queue_free()
		return
	var tw := bar.create_tween()
	tw.tween_property(bar, "modulate:a", 0.0, Motion.time(0.14))
	tw.tween_callback(bar.queue_free)


## The seal is BROKEN. Originally two clip_contents halves flying apart — but
## clipping is unreliable on gl_compatibility (this project already learned that
## with clip_children), and unclipped each "half" drew a WHOLE seal on top of the
## other, so a shot of the break was indistinguishable from the intact seal.
##
## So: no clipping. The wax bulges once under the strain, splits along a bright
## fracture, and bursts into fragments. It reads as "that seal is gone" without
## depending on a renderer feature this backend does not honour.
func _break_shield_seal() -> void:
	var old := _shield_seal
	_shield_seal = null
	if old == null or not is_instance_valid(old):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		old.queue_free()
		return
	var host: Node = _compact_root if _compact_root != null else self
	var centre: Vector2 = old.global_position + old.size * 0.5 * old.scale
	# THE FRACTURE, and it was wrong twice over. A Line2D has uniform opacity
	# across its width, so a 3px stroke reads as a wire rather than as light
	# catching a broken lip — and a crack is not STRAIGHT. Wax splits along a
	# jagged path, and the midpoint displacement that draws the lightning
	# channel draws this too: they are the same fractal at two scales.
	#
	# Built as a SPLIT rather than a line — a dark gap with a bright lip over
	# it, the same idiom the ground fracture uses, because that is what a break
	# actually looks like: the hole is dark and only its edges catch light.
	var a0: Vector2 = old.position + Vector2(6, 30)
	var a1: Vector2 = old.position + Vector2(42, 16)
	var pts := _jagged_span(a0, a1, 3, 0.13)
	var gap := Motion.beam_line(pts, Color(0.04, 0.06, 0.11, 0.88), 7.0,
		"streak", 0.0, "", Color(0.04, 0.06, 0.11))
	gap.z_index = 6
	host.add_child(gap)
	var lip := Motion.beam_line(pts, Color(0.86, 0.94, 1.0, 0.95), 4.0, "bolt")
	lip.z_index = 7
	host.add_child(lip)
	# `modulate` CANNOT fade these. beam_material writes COLOR outright, so the
	# node's modulate never reaches the fragment — the old `modulate:a` tween
	# would have left both strokes standing at full alpha until queue_free cut
	# them dead. The shader's own `fade` uniform is the handle.
	for seg: Line2D in [gap, lip]:
		var m: ShaderMaterial = seg.material as ShaderMaterial
		var stw: Tween = seg.create_tween()
		stw.tween_method(func(f: float):
			if m != null:
				m.set_shader_parameter("fade", f),
			1.0, 0.0, Motion.time(0.20))
		stw.parallel().tween_property(seg, "width", seg.width * 0.35,
			Motion.time(0.16))
		stw.tween_callback(seg.queue_free)
	# The wax gives: a brief bulge, then the blob drops away broken.
	var tw := old.create_tween()
	tw.tween_property(old, "scale", Vector2(1.18, 0.86), Motion.time(0.07)) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(old, "scale", Vector2(0.72, 1.16), Motion.time(0.20)) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(old, "modulate:a", 0.0, Motion.time(0.20)) 		.set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(old, "rotation", old.rotation + 0.5, Motion.time(0.20))
	tw.tween_callback(old.queue_free)
	# Fragments, through the one burst funnel — seal-blue so they read as the wax
	# that just failed rather than as another spark.
	Motion.burst(host, centre, "impact", {
		"color": Color(0.42, 0.62, 0.84), "amount": 14,
		"spread": 180.0, "velocity_max": 190.0,
	})


## Midpoint displacement between two points — the same construction as Combat's
## `_lightning_path`, and deliberately so: a crack and a bolt are the SAME
## fractal, which is why a fracture drawn as a straight segment reads as a
## scratch on the lens rather than as something breaking.
##
## `spread` is a FRACTION OF THE RUN, not a pixel count, so the jag stays in
## proportion at any seal size; the amplitude halves each pass, which is what
## keeps the later subdivisions reading as detail instead of as noise.
func _jagged_span(a: Vector2, b: Vector2, depth: int,
		spread: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	var amp: float = a.distance_to(b) * spread
	for _d in depth:
		var next := PackedVector2Array()
		for i in range(pts.size() - 1):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var mid: Vector2 = (p0 + p1) * 0.5
			var n: Vector2 = (p1 - p0).normalized().orthogonal()
			next.append(p0)
			next.append(mid + n * randf_range(-amp, amp))
		next.append(pts[pts.size() - 1])
		pts = next
		amp *= 0.5
	return pts


## The old battlefield status roundel was a circular StyleBoxFlat Panel plus a
## child TextureRect. On the deterministic full board that meant 36 draws and
## 36 Canvas objects for 18 small icons. This shader composites shadow, rim,
## field, and the existing white icon texture into one quad without changing
## tooltip ownership or the mid-fight pop tween.
static func _status_roundel_shader() -> Shader:
	if _status_roundel_shader_cache != null:
		return _status_roundel_shader_cache
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 rim_color : source_color = vec4(0.65, 0.53, 0.30, 1.0);
uniform vec4 glyph_color : source_color = vec4(0.95, 0.90, 0.76, 1.0);

void fragment() {
	vec4 inherited = COLOR;
	vec2 center = vec2(0.5);
	float d = length(UV - center);
	float aa = max(fwidth(d) * 1.35, 0.0015);
	float shadow_d = length(UV - (center + vec2(0.0, 0.030)));
	float shadow = (1.0 - smoothstep(0.455, 0.505, shadow_d)) * 0.45;
	float disc = 1.0 - smoothstep(0.438, 0.438 + aa, d);
	float field = 1.0 - smoothstep(0.405, 0.405 + aa, d);
	vec4 body = vec4(0.105, 0.088, 0.066, 0.97);
	vec4 disc_color = mix(rim_color, body, field);
	vec4 out_color = vec4(0.0, 0.0, 0.0, shadow);
	out_color.rgb = mix(out_color.rgb, disc_color.rgb, disc * disc_color.a);
	out_color.a = max(out_color.a, disc * disc_color.a);

	// The source icon used to occupy an 18x18 child inside the 30px seat.
	// The render quad includes a 2px shadow pad, so the same icon is 18/34.
	vec2 glyph_uv = (UV - vec2(0.235)) / 0.53;
	float inside = step(0.0, glyph_uv.x) * step(glyph_uv.x, 1.0)
		* step(0.0, glyph_uv.y) * step(glyph_uv.y, 1.0);
	float glyph_alpha = texture(TEXTURE, clamp(glyph_uv, vec2(0.0), vec2(1.0))).a
		* inside * glyph_color.a;
	out_color.rgb = mix(out_color.rgb, glyph_color.rgb, glyph_alpha);
	out_color.a = max(out_color.a, glyph_alpha);
	COLOR = out_color * inherited;
}
"""
	_status_roundel_shader_cache = shader
	return _status_roundel_shader_cache


static func _status_roundel_material(rim: Color, glyph: Color) -> ShaderMaterial:
	var key := "%s|%s" % [rim.to_html(true), glyph.to_html(true)]
	if _status_roundel_material_cache.has(key):
		return _status_roundel_material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = _status_roundel_shader()
	material.set_shader_parameter("rim_color", rim)
	material.set_shader_parameter("glyph_color", glyph)
	_status_roundel_material_cache[key] = material
	return material
func _refresh_status_rail(initial_build: bool = false) -> void:
	if _compact_root == null or not is_instance_valid(_compact_root):
		return
	var sig := _status_signature()
	# Presentation context is not part of the rail signature. Refresh these
	# idempotent checks before the early-out so a card compacted after its face
	# was built can never leave a live costume missing.
	_refresh_costumes()
	if not initial_build and sig == _status_rail_sig:
		return
	_status_rail_sig = sig
	for o in _status_orbs:
		if is_instance_valid(o):
			o.queue_free()
	_status_orbs.clear()

	# Collect rail entries — transient statuses FIRST (they're what the player
	# must react to this turn), then printed/granted keywords. Both come from
	# _active_effect_entries (its keyword loop appends the active printed ones);
	# floop/doom/shield are already excluded there or badged separately.
	var entries: Array = _active_effect_entries(false)
	entries = entries.filter(func(e): return e["tex"] != null)
	if entries.size() > _STATUS_RAIL_CAP:
		entries.resize(_STATUS_RAIL_CAP)
	if entries.is_empty():
		return

	# v7 chart material: ink roundels with a metal rim + tinted glyph (same
	# 30px seats as the old violet gems — statuses read at a glance, in the
	# same material family as the hand card's rail).
	var kw_orb := 30.0
	var kw_gap := 4.0
	var kw_total := float(entries.size()) * kw_orb + float(entries.size() - 1) * kw_gap
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var korb := TextureRect.new()
		korb.texture = e["tex"]
		korb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		korb.stretch_mode = TextureRect.STRETCH_SCALE
		korb.material = _status_roundel_material(e["rim"], e["glyph"])
		korb.anchor_left = 1.0; korb.anchor_right = 1.0
		korb.anchor_top = 0.0; korb.anchor_bottom = 0.0
		# Two pixels around the 30px seat retain the old StyleBox shadow without
		# changing rail pitch; neighbouring padded quads meet inside the 4px gap.
		korb.offset_left = -6.0 - kw_total + float(i) * (kw_orb + kw_gap)
		korb.offset_right = korb.offset_left + kw_orb + 4.0
		korb.offset_top = 2.0
		korb.offset_bottom = 6.0 + kw_orb
		korb.mouse_filter = Control.MOUSE_FILTER_PASS
		korb.tooltip_text = _active_effect_tooltip(e)
		_compact_root.add_child(korb)
		_status_orbs.append(korb)
		# A mid-fight change pops the rail in so the new effect draws the eye;
		# the initial build renders quietly with the token.
		if not initial_build and not static_display:
			korb.pivot_offset = Vector2(17.0, 17.0)
			korb.scale = Vector2(0.4, 0.4)
			var tw := korb.create_tween()
			tw.tween_property(korb, "scale", Vector2.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ═══════════════════════════════════════════
#  BAKED OVERLAY LAYOUT — texture + live stat labels
# ═══════════════════════════════════════════
#
# Fast path for hand cards (and any other context where a pre-baked texture
# exists in CardTextureCache). The full writ frame, art, banner, well, and
# stat-seal visuals are flattened into a single ImageTexture; only the
# dynamic numerals (cost/atk/hp), floop indicator, and an invisible border
# panel remain as live nodes. Per-card render cost drops from ~40 sub-draws
# to ~6 (1 TextureRect quad + ~3 Label glyph batches + 1 Panel border).
#
# Anchor positions for the overlay labels mirror the live stat seals exactly.

func _build_baked_overlay_layout() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Pre-baked texture (cache hit guaranteed by _build_layout's gate).
	var tex: Texture2D = CardTextureCache.get_gallery_texture(card_data) \
		if gallery_baked_mode else CardTextureCache.get_texture(card_data)

	var tex_rect := TextureRect.new()
	tex_rect.texture = tex
	# The bake is supersampled (SUPERSAMPLE× TEX_W/H pixels). SCALE it down to fill
	# the 249×324 logical rect; IGNORE_SIZE is REQUIRED so the texture's native pixel
	# size doesn't force the rect bigger than the card (that bug showed only the art).
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Centre the 249×324 texture over the 225×300 card. The 12 px padding on
	# each side carries the cost/ATK/HP orb overhang past the card edge —
	# same visual as the v4 live layout's intentional orb-overhang.
	tex_rect.anchor_left = 0.5; tex_rect.anchor_right = 0.5
	tex_rect.anchor_top = 0.5; tex_rect.anchor_bottom = 0.5
	tex_rect.offset_left = -float(CardTextureCache.TEX_W) * 0.5
	tex_rect.offset_right = float(CardTextureCache.TEX_W) * 0.5
	tex_rect.offset_top = -float(CardTextureCache.TEX_H) * 0.5
	tex_rect.offset_bottom = float(CardTextureCache.TEX_H) * 0.5
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ★2 — a rare's gilt catches the light as the card tilts. Held so the lean
	# driver can sweep the highlight; see _apply_gilt_foil.
	_baked_face = tex_rect
	_apply_gilt_foil()
	root.add_child(tex_rect)

	# ── Live overlay: cost orb numeral ──
	# Wrapper Control concentric with the cost stat seal painted into the baked
	# texture. The bake uses the v3 layout, whose orbs are 56px (anchor 0,0 with
	# -9..47 offsets, sphere center at card-local 19px) — so the slot MUST use
	# the same 56px box, not the old v4 44px box (-9..35), or the numeral lands
	# above/left of the sphere. The label inside uses PRESET_FULL_RECT so it
	# centres inside the sphere painted underneath.
	var cost_slot := Control.new()
	cost_slot.anchor_left = 0.0; cost_slot.anchor_right = 0.0
	cost_slot.anchor_top = 0.0; cost_slot.anchor_bottom = 0.0
	cost_slot.offset_left = -9; cost_slot.offset_right = 47
	cost_slot.offset_top = -9; cost_slot.offset_bottom = 47
	cost_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cost_slot)
	_cost_label = _make_stat_number(str(card_data.get("cost", 0)),
		Color(1, 0.98, 0.90), 0,
		Color(0.30, 0.65, 1.00, 0.45))
	cost_slot.add_child(_cost_label)
	# _cost_badge is read externally by some hover code paths — point it at
	# the overlay anchor so hover effects still have a Control to grab.
	_cost_badge = cost_slot

	if is_creature():
		# ── Live overlay: ATK orb numeral (bottom-left) ──
		# 56px box concentric with the v3 ATK sphere (anchor 0,1, -9..47 / -47..9,
		# sphere center at card-local (19, h-19)). Old v4 44px box left the numeral
		# below the sphere center — the worst-offset "bottom orb" case.
		var atk_slot := Control.new()
		atk_slot.anchor_left = 0.0; atk_slot.anchor_right = 0.0
		atk_slot.anchor_top = 1.0; atk_slot.anchor_bottom = 1.0
		atk_slot.offset_left = -9; atk_slot.offset_right = 47
		atk_slot.offset_top = -47; atk_slot.offset_bottom = 9
		atk_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(atk_slot)
		# Light cream on the v7 burnished-bronze wax seal (the old dark-on-gold
		# was tuned for the bright v3/v6 sphere and vanishes on the seal).
		_atk_base_color = Color(1.000, 0.957, 0.839)
		_atk_label = _make_stat_number(str(current_atk), _atk_base_color, 0,
			Color(1.00, 0.78, 0.20, 0.50))
		atk_slot.add_child(_atk_label)
		_atk_badge = null

		# ── Live overlay: HP orb numeral (bottom-right) ──
		# 56px box concentric with the v3 HP sphere (anchor 1,1, -47..9 / -47..9,
		# sphere center at card-local (w-19, h-19)).
		var hp_slot := Control.new()
		hp_slot.anchor_left = 1.0; hp_slot.anchor_right = 1.0
		hp_slot.anchor_top = 1.0; hp_slot.anchor_bottom = 1.0
		hp_slot.offset_left = -47; hp_slot.offset_right = 9
		hp_slot.offset_top = -47; hp_slot.offset_bottom = 9
		hp_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(hp_slot)
		_hp_base_color = Color(1, 0.97, 0.92)
		_hp_label = _make_stat_number(str(current_hp), _hp_base_color, 0,
			Color(1.00, 0.30, 0.20, 0.50))
		hp_slot.add_child(_hp_label)
		_hp_badge = null

	# ── Live overlay: RULES TEXT (StS model — drawn live, not baked) ──
	# Same geometry the v9 live layout (_build_chart_proto) uses for its desc, so it
	# lands exactly on the blank vellum panel baked underneath. Because it's the font
	# renderer (not a baked raster), it stays razor-sharp when the card is lifted or
	# zoomed — the fix for "I can't read the card text." Drawn at every scale,
	# including the 0.36 deck strip: a 2026-07-21 pass filled this well with a
	# re-cropped copy of the card art instead, but a landscape painting has nothing
	# left to show below the art window, so the second crop only read as the same
	# picture stamped twice ("the pictures are glitched"). Crisp small text beats a
	# duplicated image — and a deck the player is reading wants its rules visible.
	var od_clip := Control.new()
	od_clip.clip_contents = true
	od_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	od_clip.anchor_left = 0.0; od_clip.anchor_right = 1.0
	od_clip.anchor_top = 0.0; od_clip.anchor_bottom = 0.0
	od_clip.offset_left = 17; od_clip.offset_right = -17
	# MUST match _build_chart_proto's desc_clip (176 → rule_bot-2: 258, spells
	# 265 since the one-line footer) so the live text lands on the vellum panel
	# baked underneath by chart_proto.
	od_clip.offset_top = 176
	od_clip.offset_bottom = 265 if not is_creature() else 258
	root.add_child(od_clip)
	var od_center := CenterContainer.new()
	od_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	od_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	od_clip.add_child(od_center)
	var od_rt := RichTextLabel.new()
	od_rt.bbcode_enabled = true
	od_rt.hint_underlined = false  # keyword hints hover-only, no underline ink
	od_rt.fit_content = true
	od_rt.scroll_active = false
	od_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# PASS (not IGNORE): the [hint] glossary that used to live on the margin
	# roundels now rides the keyword words — PASS lets hover reach the hints
	# while clicks/drags still fall through to the card panel.
	od_rt.mouse_filter = Control.MOUSE_FILTER_PASS
	# Lockstep twin of the chart-proto width — see the note at desc_rt.
	od_rt.custom_minimum_size = Vector2(182, 0)
	# Match _build_chart_proto's tightened leading so wrapping/fit is identical.
	od_rt.add_theme_constant_override("line_separation", -2)
	var od_font: Font = GameTheme.font_card_body if GameTheme.font_card_body != null \
		else GameTheme.font_body
	var od_bold: Font = GameTheme.font_card_body_bold if GameTheme.font_card_body_bold != null \
		else od_font
	if od_font:
		od_rt.add_theme_font_override("normal_font", od_font)
		od_rt.add_theme_font_override("bold_font", od_bold if od_bold else od_font)
	var od_raw: String = card_data.get("desc", "")
	if od_raw == "" and synth_desc_if_empty:
		od_raw = _synthesized_rules_text()
	# Body copy matches the live renderer: a fixed 18px reading size.
	var od_sz := 18
	od_rt.add_theme_font_size_override("normal_font_size", od_sz)
	od_rt.add_theme_font_size_override("bold_font_size", od_sz)
	od_rt.add_theme_color_override("default_color", GameTheme.PARCHMENT_TEXT)
	# decorate_keywords = gild + inline device stamps + [hint] glossary. Stamp
	# size keys to the ramp, mirroring the chart_proto desc block. Drawn at every
	# thumbnail scale (down to the 0.36 deck strip): the vector text stays crisp
	# and legible where a re-cropped copy of the art only read as a duplication.
	var od_max_h := 87.0 if not is_creature() else 80.0
	if defer_baked_rules_text:
		od_center.add_child(od_rt)
		_pending_baked_rules = [od_rt, od_raw, od_sz, od_max_h]
	else:
		var od_bb := KeywordEffects.decorate_keywords(od_raw, od_sz - 3).replace(
			KeywordEffects.KEYWORD_GOLD, "#7a4f10")
		var od_text := "[center]%s[/center]" % od_bb
		od_rt.text = od_text
		od_center.add_child(od_rt)
		_fit_desc_to_box.call_deferred(od_rt, od_max_h)

	# ── Live overlay: NAME (StS model — drawn live over the baked cartouche) ──
	# The bake paints the swallowtail banner but blanks the name (bake_strip_name);
	# drawing it live with the font renderer keeps it razor-sharp at any zoom like
	# the rules text, instead of a downscaled bitmap. Mirrors the name block in
	# _build_chart_proto so it lands exactly on the baked cartouche (center y=164
	# real → 218.67 in _center_at_point's 300×400 space).
	var nm_is_curse := CardDB.is_curse(String(card_data.get("id", "")))
	var nm_is_upg := bool(card_data.get("is_upgraded", false)) and not nm_is_curse
	var nm_font: Font = GameTheme.font_title_black \
		if GameTheme.font_title_black != null else GameTheme.font_display
	var nm_col := Color(0.93, 0.82, 0.55)
	if nm_is_curse:
		nm_col = Color(0.74, 0.72, 0.66)
	elif nm_is_upg:
		nm_col = Color(1.0, 0.886, 0.541)
	var nm_text := String(card_data.get("name", ""))
	var nm_size := 16
	if nm_text.length() > 17:
		nm_size = 14
	elif nm_text.length() > 13:
		nm_size = 15
	_name_label = _make_styled_label(nm_text, nm_font, nm_size, nm_col)
	_name_label.add_theme_constant_override("outline_size", 0)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_name_label.add_theme_constant_override("shadow_offset_x", 0)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Must match _build_chart_proto's cartouche center (y=157 real → 209.33).
	_center_at_point(_name_label, Vector2(150, 209.33), SIZE_NAME)
	root.add_child(_name_label)

	# ── Live overlay: TRIBE FOOTER (stripped by the same bake_strip_name) ──
	# The name's sibling: bake_strip_name blanks BOTH letterpress bands, so both
	# must be redrawn here. Only the name half was ever written — see
	# _make_ctype_footer_label for what that cost.
	var ct_lbl := _make_ctype_footer_label()
	if ct_lbl != null:
		root.add_child(ct_lbl)

	# Floop display is a no-op, and the old invisible compatibility Labels had
	# no readers. Keep only the real visible name/rules/stat nodes above; this
	# removes five Controls from every cached card without changing its pixels.
	_art_rect = null


func complete_deferred_baked_rules() -> void:
	if _pending_baked_rules.is_empty():
		return
	var rt_obj: Variant = _pending_baked_rules[0]
	var raw_text: String = String(_pending_baked_rules[1])
	var font_size: int = int(_pending_baked_rules[2])
	var max_h: float = float(_pending_baked_rules[3])
	_pending_baked_rules.clear()
	_set_deferred_baked_rules(rt_obj, raw_text, font_size, max_h)


func _set_deferred_baked_rules(rt_obj: Variant, raw_text: String,
		font_size: int,
		max_h: float) -> void:
	# A dealt card can be rebuilt/freed before its delayed text turn (reroll,
	# purchase, scene exit). Untyped for the same freed-object reason as the fitter.
	if not is_instance_valid(rt_obj):
		return
	var rt := rt_obj as RichTextLabel
	if rt == null:
		return
	var bb := KeywordEffects.decorate_keywords(raw_text, font_size - 3).replace(
		KeywordEffects.KEYWORD_GOLD, "#7a4f10")
	var text := "[center]%s[/center]" % bb
	rt.text = text
	_fit_desc_to_box.call_deferred(rt, max_h)

# ═══════════════════════════════════════════
#  FULL (HAND) LAYOUT — name banner, art, description, footer stats
# ═══════════════════════════════════════════

func _chart_metal(rarity: String) -> Color:
	if CardDB.is_curse(String(card_data.get("id", ""))):
		return Color(0.55, 0.52, 0.45)            # weathered bone
	if rarity == "white":
		return Color(0.88, 0.96, 1.00)
	# Widened separation so rarity reads at a glance: the warm metals (bronze/
	# gold) used to sit too close. Rare is now the brightest + most saturated
	# gold, uncommon the coolest silver-blue, starter the darkest pewter, common
	# a mid aged bronze — value AND hue step between every tier.
	match rarity:
		"rare":     return Color(0.97, 0.75, 0.22)  # bright gold — rare pops loudest
		"uncommon": return Color(0.64, 0.76, 0.90)  # cool silver-blue
		"starter":  return Color(0.47, 0.46, 0.44)  # dark pewter
	return Color(0.62, 0.45, 0.25)                 # common — aged bronze


## A rectangular rule (border only) inset uniformly from the card edge.
func _chart_rule(parent: Control, inset: float, width: int, col: Color,
		radius: int) -> void:
	var r := Panel.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.offset_left = inset
	r.offset_top = inset
	r.offset_right = -inset
	r.offset_bottom = -inset
	var st := StyleBoxFlat.new()
	st.draw_center = false
	st.border_color = col
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	r.add_theme_stylebox_override("panel", st)
	parent.add_child(r)


## A small rotated-square finial — the cartouche diamond, sized for cards.
func _chart_diamond(parent: Control, center: Vector2, size_px: float,
		col: Color) -> void:
	var d := Panel.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.border_color = Color(0.05, 0.04, 0.03, 0.9)
	st.set_border_width_all(1)
	d.add_theme_stylebox_override("panel", st)
	d.size = Vector2(size_px, size_px)
	d.pivot_offset = d.size * 0.5
	d.rotation_degrees = 45.0
	d.position = center - d.pivot_offset
	parent.add_child(d)


## A pressed wax seal (see WaxSeal). The caller seats it (56px box on the
## hand card, 38px on the field token) and parents the numeral label onto
## it. The metal param is kept for call-site compatibility — real wax sits
## directly on the paper, no metal bezel.
func _chart_seal(wax: Color, _metal: Color, simple: bool = false) -> Control:
	var seal := WaxSeal.new()
	seal.wax = wax
	seal.simple_mode = simple
	# Seed per card AND per stat color so the three seals on one card cool
	# into three different blobs, but every bake of the same card matches.
	seal.seed_text = String(card_data.get("id", "?")) + wax.to_html(false)
	return seal


## Keyword devices, writ edition: a centered row of ink-stamped roundels
## in the document's bottom margin — printed ON the paper, never pinned
## over the painting (the art plate stays clean; that was v7's mistake).
func _kw_stamp_row(root: Control, meds: Array, metal: Color,
		total_meds: int = -1, kw_ids: Array = []) -> void:
	var n: int = min(meds.size(), 3)
	if n == 0:
		return
	# How many icon-bearing keywords the card actually has (the caller may pass
	# only the first 3 textures). When it exceeds the 3 shown, we append a "+N"
	# overflow roundel so the player knows there are more devices.
	var total: int = total_meds if total_meds >= 0 else meds.size()
	var overflow: int = maxi(total - n, 0)
	var slots: int = n + (1 if overflow > 0 else 0)
	var box := 25.0
	var gap := 6.0
	var inset: float = box * 0.20
	var row_w := box * float(slots) + gap * float(slots - 1)
	var x0 := 112.5 - row_w * 0.5
	for i in range(n):
		var stamp := Panel.new()
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sst := StyleBoxFlat.new()
		sst.bg_color = Color(0.165, 0.133, 0.098, 0.96)
		sst.border_color = Color(metal.r, metal.g, metal.b, 0.80)
		sst.set_border_width_all(1)
		sst.set_corner_radius_all(999)
		sst.shadow_color = Color(0.10, 0.06, 0.02, 0.30)
		sst.shadow_size = 2
		sst.shadow_offset = Vector2(0, 1)
		stamp.add_theme_stylebox_override("panel", sst)
		stamp.position = Vector2(x0 + float(i) * (box + gap), 260.5)
		stamp.size = Vector2(box, box)
		root.add_child(stamp)
		if i < kw_ids.size():
			# Hover reminder on the live keyword roundel (previously mute). PASS so
			# the card's own drag/hover still works underneath.
			stamp.mouse_filter = Control.MOUSE_FILTER_PASS
			stamp.tooltip_text = KeywordEffects.tooltip_for(String(kw_ids[i]))
		var glyph := TextureRect.new()
		glyph.texture = meds[i]
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.offset_left = inset
		glyph.offset_right = -inset
		glyph.offset_top = inset
		glyph.offset_bottom = -inset
		glyph.modulate = GameTheme.GILT_BRIGHT
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.add_child(glyph)
	if overflow > 0:
		# "+N" overflow roundel — same ink mount, a gilt count instead of a
		# device, so the player sees the card carries more keywords than fit.
		var more := Panel.new()
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mst := StyleBoxFlat.new()
		mst.bg_color = Color(0.165, 0.133, 0.098, 0.96)
		mst.border_color = Color(metal.r, metal.g, metal.b, 0.80)
		mst.set_border_width_all(1)
		mst.set_corner_radius_all(999)
		mst.shadow_color = Color(0.10, 0.06, 0.02, 0.30)
		mst.shadow_size = 2
		mst.shadow_offset = Vector2(0, 1)
		more.add_theme_stylebox_override("panel", mst)
		more.position = Vector2(x0 + float(n) * (box + gap), 260.5)
		more.size = Vector2(box, box)
		root.add_child(more)
		var more_lbl := _make_styled_label("+%d" % overflow,
			GameTheme.font_stat if GameTheme.font_stat != null \
			else GameTheme.font_display, 11, GameTheme.GILT_BRIGHT)
		more_lbl.add_theme_constant_override("outline_size", 3)
		more_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		more_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		more.add_child(more_lbl)


# The final fit is deterministic for a given rendered string, geometry and font.
# Card faces repeat across hand, reward, shop, collection and Game Over screens;
# retain the exact winning leading/size pair instead of reflowing identical text.
static var _desc_fit_cache: Dictionary = {}


func _fit_desc_to_box(rt_obj: Variant, max_h: float) -> void:
	# Rules text is fixed at the 18px reading floor. The deferred check reports
	# clip box. RichTextLabel.get_content_height() validates the line cache, so
	# overflow but never makes the player trade readability for fitting.
	# legibility floor on the ~225px card — at the real windowed (1600×900,
	# no global scaling) size the rules text was the #1 "too small to read"
	# complaint, so we'd rather clip the rare 5-line card than render any
	# The taller rules box + tightened leading keep the rewritten short copy
	# _build_chart_proto) means even long cards rarely need to step down this far.
	# at the same 18px size on every card.
	# very wordy cards — most cards render at their full ramp size.
	# rt_obj is deliberately UNTYPED: this runs via call_deferred, and a layout
	# rebuild in the same frame (chart proto → baked overlay swap) frees the
	# label first — a freed object fails a typed-parameter conversion at
	# dispatch, erroring before any in-body is_instance_valid guard can run.
	if not is_instance_valid(rt_obj):
		return
	var rt := rt_obj as RichTextLabel
	if rt == null:
		return
	# 2026-07-30 — THIS FUNCTION HAD NEVER ONCE SHRUNK ANYTHING.
	#
	# Every card sets dsz = 18, and the loop's own first act was `if cur <= 18:
	# return`, so it bailed on iteration one, every time, on every card. The
	# "shrink-to-fit safety net" was decorative; long rules text simply clipped
	# (measured on Fuse Tender in the Collection, which ends mid-sentence at
	# "this fight and 1 round").
	#
	# The 18px floor it was protecting is CORRECT and stays absolute — COPY_STYLE
	# §11 sets the reading floor at 18 and `tools/_probe_text_floor.gd` enforces
	# it. But that floor governs GLYPH SIZE, which is what legibility depends on.
	# LEADING is a separate budget, and this card is already running -2 against
	# Alegreya's generous default. Tightening it further is free vertical space
	# that costs no readability, so overflow now buys height there instead of
	# stealing it from the letterforms.
	#
	# -2 → -5 over three steps claws back ~9px on a four-line card, which covers
	# every card in the pool that currently overruns. If a card still overflows
	# at -5 it is genuinely too wordy and belongs in front of a copy editor, not
	# a smaller font — so we stop, and it clips loudly enough to be noticed.
	# ORDER MATTERS: spend the free budget first, the costly one last.
	#   1. LEADING, -2 down to -5. Costs nothing legible — this is whitespace
	#      between lines, not letterform size.
	#   2. Then, and only then, ONE font step 18 -> 17.
	#
	# That single step is a deliberate, narrow exception to the 18px reading
	# floor, taken because the alternative is worse by any measure: a clipped
	# card conveys NOTHING, while a 17px card conveys everything slightly
	# smaller. 17 still sits inside COPY_STYLE §11's 15-17 caption band and far
	# above the 14px hard floor that _probe_text_floor enforces, so no gate is
	# weakened. It is capped at one step precisely so it can never become the
	# old 15/14/13 ramp that was the #1 "too small to read" complaint.
	#
	# Anything still overflowing after both is genuinely over-written and wants
	# a copy editor, not a smaller font — so we stop and let it clip loudly.
	var initial_size := int(rt.get_theme_font_size("normal_font_size"))
	var initial_bold_size := int(rt.get_theme_font_size("bold_font_size"))
	var initial_lead := int(rt.get_theme_constant("line_separation"))
	var normal_font: Font = rt.get_theme_font("normal_font")
	var bold_font: Font = rt.get_theme_font("bold_font")
	var fit_key := "%s\u001f%.3f|%.3f|%d|%d|%d|%d|%d" % [
		rt.text, max_h, rt.custom_minimum_size.x,
		initial_size, initial_bold_size, initial_lead,
		normal_font.get_instance_id() if normal_font != null else 0,
		bold_font.get_instance_id() if bold_font != null else 0,
	]
	var cached: Variant = _desc_fit_cache.get(fit_key, null)
	if cached is Vector2i:
		var cached_fit := cached as Vector2i
		rt.add_theme_constant_override("line_separation", cached_fit.y)
		rt.add_theme_font_size_override("normal_font_size", cached_fit.x)
		rt.add_theme_font_size_override("bold_font_size", cached_fit.x)
		return

	var guard := 0
	while guard < 6:
		if rt.get_content_height() <= max_h:
			break
		var lead := int(rt.get_theme_constant("line_separation"))
		if lead > -5:
			rt.add_theme_constant_override("line_separation", lead - 1)
		else:
			var cur := int(rt.get_theme_font_size("normal_font_size"))
			if cur <= 17:
				break
			rt.add_theme_font_size_override("normal_font_size", cur - 1)
			rt.add_theme_font_size_override("bold_font_size", cur - 1)
		guard += 1
	_desc_fit_cache[fit_key] = Vector2i(
		int(rt.get_theme_font_size("normal_font_size")),
		int(rt.get_theme_constant("line_separation")))


func _build_chart_proto() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var rarity := String(card_data.get("rarity", "common"))
	# Armaments use the statless document geometry, just like spells, while their
	# own footer/type line keeps the gameplay distinction explicit.
	var is_sp := not is_creature()
	var is_curse_card := CardDB.is_curse(String(card_data.get("id", "")))
	# Forged-card glance cue (P3): RunState stamps is_upgraded:true when a card
	# is "+"-forged. The lone " +" name suffix can be ellipsized away, so we add
	# non-text cues below (gilded name + forge pips flanking the cartouche).
	var is_upg := bool(card_data.get("is_upgraded", false)) and not is_curse_card
	var metal := _chart_metal(rarity)
	var metal_dim := Color(metal.r, metal.g, metal.b, 0.78)

	# ── seat shadow (neutral, same as v6) ────────────────────────────────
	var seat := Panel.new()
	seat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seat.anchor_left = 0.06
	seat.anchor_right = 0.94
	seat.anchor_top = 0.04
	seat.anchor_bottom = 0.965
	var seat_st := StyleBoxFlat.new()
	seat_st.bg_color = Color(0, 0, 0, 0.0)
	seat_st.set_corner_radius_all(22)
	seat_st.shadow_color = Color(0, 0, 0, 0.55)
	seat_st.shadow_size = 18
	seat_st.shadow_offset = Vector2(0, 4)
	seat.add_theme_stylebox_override("panel", seat_st)
	root.add_child(seat)

	# ── rarity glow halo (quieter than v6 — the metal carries rarity too) ─
	var glow_size := 3
	var glow_col: Color = GameTheme.rarity_color(rarity)
	if rarity == "white":
		glow_col = Color(0.86, 0.96, 1.0)
	elif rarity == "rare":
		glow_col = Color(0.95, 0.72, 0.25)
	match rarity:
		"white":    glow_size = 16
		"rare":     glow_size = 13
		"uncommon": glow_size = 8
		"common":   glow_size = 3
		"starter":  glow_size = 2
	if not is_curse_card:
		var glow := Panel.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.anchor_left = 0.035
		glow.anchor_right = 0.965
		glow.anchor_top = 0.02
		glow.anchor_bottom = 0.985
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(0, 0, 0, 0.0)
		gs.set_corner_radius_all(20)
		gs.shadow_color = Color(glow_col.r, glow_col.g, glow_col.b, 0.55)
		gs.shadow_size = glow_size
		glow.add_theme_stylebox_override("panel", gs)
		root.add_child(glow)

	# ── the leaf: aged parchment — the SAME paper the campaign chart and
	# the tooltips are printed on, cut with a deckled organic edge. WritLeaf
	# draws silhouette + contour + toast along one wobbled path: a StyleBox
	# rounded rect reads as UI precisely because its corners are perfect.
	var leaf := WritLeaf.new()
	leaf.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaf.seed_text = String(card_data.get("id", "?"))
	if is_curse_card:
		leaf.paper = Color(0.769, 0.749, 0.655)
		leaf.edge_ink = Color(0.138, 0.148, 0.100)
		leaf.toast = Color(0.196, 0.216, 0.118)
		leaf.toast_strength = 1.7
	root.add_child(leaf)
	# Paper tooth: the interior ageing painter (washes/foxing/fibers),
	# clipped at 3px inset so the big wash circles stay on the sheet.
	var tooth := ParchmentPlate.new()
	tooth.clip_contents = true
	tooth.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooth.offset_left = 3
	tooth.offset_top = 3
	tooth.offset_right = -3
	tooth.offset_bottom = -3
	tooth.seed_text = String(card_data.get("id", "?"))
	if is_curse_card:
		# The document itself is corrupted: murk-green staining, heavier.
		tooth.stain = Color(0.282, 0.318, 0.196)
		tooth.fox = Color(0.255, 0.282, 0.137)
		tooth.strength = 1.7
	root.add_child(tooth)
	# A whisper of fiber noise on top of the painter's washes.
	if GameTheme.tex_card_grain:
		var bgn := TextureRect.new()
		bgn.texture = GameTheme.tex_card_grain
		bgn.stretch_mode = TextureRect.STRETCH_TILE
		bgn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgn.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgn.offset_left = 3
		bgn.offset_top = 3
		bgn.offset_right = -3
		bgn.offset_bottom = -3
		bgn.modulate = Color(0.42, 0.30, 0.16, 0.10)
		bgn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bgn)

	# ── metal rules: ink keyline + heavy outer + hairline inner — the
	# cartouche language; the dark keyline sets the metal INTO the paper ──
	_chart_rule(root, 4.0, 1, Color(0.165, 0.125, 0.082, 0.50), 8)
	_chart_rule(root, 5.0, 2, metal, 7)
	_chart_rule(root, 9.0, 1, Color(metal.r * 0.80, metal.g * 0.80,
		metal.b * 0.80, 0.80), 5)

	# ── art mounted as a plate: ink mat + gilt fillet + inner shadow. The
	# painting is the best thing on the card — it gets the most area (the
	# plate runs to half the leaf) and nothing is ever pinned over it. ─────
	var card_art: Texture2D = _find_card_art()
	# NOTE: the card control is natively 225x300 — these offsets are REAL
	# pixels (the 300x400 numbers some layouts use only exist inside
	# _center_at_point's design-space mapping).
	var mat := Panel.new()
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.anchor_left = 0.0
	mat.anchor_right = 1.0
	mat.anchor_top = 0.0
	mat.anchor_bottom = 0.0
	mat.offset_left = 9
	mat.offset_right = -9
	mat.offset_top = 9
	# Art plate gives up ~6px at the bottom so the rules band can grow taller —
	# the painting still occupies ~44% of the leaf, the most area of any element.
	mat.offset_bottom = 140
	var mat_st := StyleBoxFlat.new()
	mat_st.bg_color = Color(0.118, 0.096, 0.072)
	mat.add_theme_stylebox_override("panel", mat_st)
	root.add_child(mat)
	var art_clip := Control.new()
	art_clip.clip_contents = true
	art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_clip.anchor_left = 0.0
	art_clip.anchor_right = 1.0
	art_clip.anchor_top = 0.0
	art_clip.anchor_bottom = 0.0
	art_clip.offset_left = 11
	art_clip.offset_right = -11
	art_clip.offset_top = 11
	art_clip.offset_bottom = 138
	root.add_child(art_clip)
	_art_rect = art_clip
	if card_art:
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)
	else:
		# Sealed empty plate: an aged-parchment field (the same paper the leaf
		# is cut from), tooth texture, and a small engraved gilt sigil — NOT a
		# giant near-black initial letter (that read as a broken placeholder).
		# A quiet centered device on warm paper reads as intentional chart
		# furniture: "no portrait drawn for this entry," not "art failed to load."
		var ph := Panel.new()
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		var phst := StyleBoxFlat.new()
		phst.bg_color = Color(0.808, 0.749, 0.620) if not is_curse_card \
			else Color(0.612, 0.604, 0.522)
		ph.add_theme_stylebox_override("panel", phst)
		art_clip.add_child(ph)
		# Inner ink mat line so the empty plate still reads as a mounted frame.
		var ph_rule := Panel.new()
		ph_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph_rule.set_anchors_preset(Control.PRESET_FULL_RECT)
		ph_rule.offset_left = 4; ph_rule.offset_top = 4
		ph_rule.offset_right = -4; ph_rule.offset_bottom = -4
		var ph_rst := StyleBoxFlat.new()
		ph_rst.draw_center = false
		ph_rst.border_color = Color(0.255, 0.188, 0.118, 0.45)
		ph_rst.set_border_width_all(1)
		ph_rule.add_theme_stylebox_override("panel", ph_rst)
		ph.add_child(ph_rule)
		# Aged tooth on the empty paper (washes/foxing) so it matches the leaf.
		var ph_tooth := ParchmentPlate.new()
		ph_tooth.clip_contents = true
		ph_tooth.set_anchors_preset(Control.PRESET_FULL_RECT)
		ph_tooth.seed_text = String(card_data.get("id", "?")) + "_plate"
		if is_curse_card:
			ph_tooth.stain = Color(0.282, 0.318, 0.196)
			ph_tooth.fox = Color(0.255, 0.282, 0.137)
			ph_tooth.strength = 1.4
		ph.add_child(ph_tooth)
		# The engraved device, centered on the plate.
		var sigil := EmptyPlateSigil.new()
		sigil.is_spell_sigil = is_sp
		if is_curse_card:
			sigil.ink = Color(0.45, 0.46, 0.34, 0.55)
		sigil.set_anchors_preset(Control.PRESET_FULL_RECT)
		sigil.offset_left = 20; sigil.offset_top = 16
		sigil.offset_right = -20; sigil.offset_bottom = -16
		ph.add_child(sigil)
	if GameTheme.tex_card_vignette:
		# Inner shadow so the painting reads mounted INTO the board.
		var avg := TextureRect.new()
		avg.texture = GameTheme.tex_card_vignette
		avg.stretch_mode = TextureRect.STRETCH_SCALE
		avg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avg.set_anchors_preset(Control.PRESET_FULL_RECT)
		avg.modulate = Color(0, 0, 0, 0.34)
		avg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(avg)
	# Gilt fillet rule around the mat — the plate's outer frame line.
	var fillet := Panel.new()
	fillet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fillet.anchor_left = 0.0
	fillet.anchor_right = 1.0
	fillet.anchor_top = 0.0
	fillet.anchor_bottom = 0.0
	fillet.offset_left = 8
	fillet.offset_right = -8
	fillet.offset_top = 8
	fillet.offset_bottom = 141
	var fst := StyleBoxFlat.new()
	fst.draw_center = false
	fst.border_color = metal_dim
	fst.set_border_width_all(1)
	fillet.add_theme_stylebox_override("panel", fst)
	root.add_child(fillet)
	# Plate marks: small metal squares on the fillet corners — the mounting
	# hardware that makes the painting read as a fixed museum plate.
	for pm in [Vector2(8, 8), Vector2(217, 8), Vector2(8, 141), Vector2(217, 141)]:
		var mark := Panel.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mst := StyleBoxFlat.new()
		mst.bg_color = metal
		mst.border_color = Color(0.10, 0.08, 0.05, 0.9)
		mst.set_border_width_all(1)
		mark.add_theme_stylebox_override("panel", mst)
		mark.position = (pm as Vector2) - Vector2(2.5, 2.5)
		mark.size = Vector2(5, 5)
		root.add_child(mark)

	# ── rarity gem at top-center: a faceted diamond SET into an ink mount on the
	# rules. Now drawn on EVERY card (was uncommon/rare only — common/starter had
	# no positive cue, so they were the hardest to tell apart) with a clearly
	# distinct colour per tier: pewter starter, pale silver common, sapphire
	# uncommon, gold rare. Rare/uncommon sit a touch larger so the top tiers also
	# read by size. Curses keep their own bone/murk identity, no gem. ──────────
	if not is_curse_card:
		var gem_col: Color
		match rarity:
			"white":    gem_col = Color(0.92, 0.98, 1.00)   # cold white
			"rare":     gem_col = Color(0.97, 0.72, 0.16)   # gold
			"uncommon": gem_col = Color(0.36, 0.62, 0.96)   # sapphire
			"starter":  gem_col = Color(0.55, 0.53, 0.49)   # pewter grey
			_:          gem_col = Color(0.88, 0.90, 0.92)   # common — pale silver
		var gem_r: float = 10.5 if (rarity == "white" or rarity == "rare" or rarity == "uncommon") else 8.5
		_chart_diamond(root, Vector2(112.5, 7.5), gem_r + 6.0, Color(0.10, 0.082, 0.060))
		_chart_diamond(root, Vector2(112.5, 7.5), gem_r, gem_col)
		_chart_diamond(root, Vector2(112.5, 5.9), gem_r * 0.38,
			Color(minf(gem_col.r * 1.4, 1.0), minf(gem_col.g * 1.4, 1.0),
			minf(gem_col.b * 1.4, 1.0)))

	# ── name cartouche: swallowtail ink banner, metal-edged — the name
	# moment is crafted furniture now, not a flat full-width bar ──────────
	var plate := InkCartouche.new()
	plate.anchor_left = 0.0
	plate.anchor_right = 1.0
	plate.anchor_top = 0.0
	plate.anchor_bottom = 0.0
	plate.offset_left = 12
	plate.offset_right = -12
	# Cartouche follows the art plate up (was 150→178) so the freed space lands
	# in the rules band below, not as dead air between art and name.
	plate.offset_top = 143
	plate.offset_bottom = 171
	plate.metal = metal
	root.add_child(plate)
	# A stripped bake needs the painted cartouche above, but its deliberately blank
	# Label contributes no pixels. Do not build that dead text node; the visible
	# baked-overlay card recreates the live name after the snapshot lands.
	if not bake_strip_name:
		var name_font: Font = GameTheme.font_title_black \
			if GameTheme.font_title_black != null else GameTheme.font_display
		var name_col := Color(0.93, 0.82, 0.55)
		if is_curse_card:
			name_col = Color(0.74, 0.72, 0.66)
		elif is_upg:
			# Forged: lift the name to a brighter struck-gilt so an upgraded card
			# reads as upgraded at a glance, independent of the " +" suffix.
			name_col = Color(1.0, 0.886, 0.541)
		# Cinzel caps run wide — long names step down instead of ellipsizing.
		var nm := String(card_data.get("name", ""))
		var nm_size := 16
		if nm.length() > 17:
			nm_size = 14
		elif nm.length() > 13:
			nm_size = 15
		_name_label = _make_styled_label(nm, name_font, nm_size, name_col)
		_name_label.add_theme_constant_override("outline_size", 0)
		_name_label.add_theme_color_override("font_shadow_color",
			Color(0, 0, 0, 0.55))
		_name_label.add_theme_constant_override("shadow_offset_x", 0)
		_name_label.add_theme_constant_override("shadow_offset_y", 1)
		_name_label.clip_text = true
		_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# Cartouche center y=157 real → 209.33 in _center_at_point's 300x400 space.
		_center_at_point(_name_label, Vector2(150, 209.33), SIZE_NAME)
		root.add_child(_name_label)
	if is_upg:
		# Gilt forge finials flank the name cartouche (real-px coords, like the
		# rulebox ticks). Always visible regardless of rarity or name length —
		# the redundant non-text half of the forged glance cue.
		var forge_gilt := Color(1.0, 0.835, 0.4)
		_chart_diamond(root, Vector2(21, 163), 5.0, forge_gilt)
		_chart_diamond(root, Vector2(204, 163), 5.0, forge_gilt)

	# ── keyword devices ──────────────────────────────────────────────────
	# The bottom-margin roundel row (_kw_stamp_row) was retired here 2026-07-10:
	# it repeated the rules text an inch away, and its hover glossary moved onto
	# the words themselves ([hint] via KeywordEffects.decorate_keywords below).
	# Battlefield tokens keep their live icon rail — there it's the only display.

	# ── clean inscribed-vellum panel under the rules text ────────────────
	# The procedural ParchmentPlate ages the whole leaf with sepia washes +
	# foxing; over a stain the dark body ink and bronze keyword gold drop below
	# readable contrast. Lay a subtle sheet of cleaner stock over just the rules
	# band so the writing always sits on fresh vellum — reads as an intentional
	# inscribed panel, not a pasted rectangle. (Curse cards keep their murk.)
	if not is_curse_card:
		var stock := Panel.new()
		stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stock.anchor_left = 0.0
		stock.anchor_right = 1.0
		stock.anchor_top = 0.0
		stock.anchor_bottom = 0.0
		stock.offset_left = 16
		stock.offset_right = -16
		# Taller, higher vellum band (was 183→256) — the rules text now starts
		# ~8px higher and runs ~4px lower for ~13px more height, so the larger
		# fixed 18px body fits without shrinking on the typical card.
		stock.offset_top = 175
		stock.offset_bottom = 266 if is_sp else 259
		var sst := StyleBoxFlat.new()
		sst.bg_color = Color(0.901, 0.843, 0.690, 0.62)  # clean warm vellum
		sst.set_corner_radius_all(3)
		stock.add_theme_stylebox_override("panel", sst)
		root.add_child(stock)

	# ── ruled text region: the page itself carries the rules text. A fine
	# ink hairline box with metal corner ticks — chart-legend language —
	# instead of v7's floating tooltip-like well. ─────────────────────────
	# Spells run the box ~7px lower: the footer collapsed to one line
	# (2026-07-10 furniture pass) and the freed height goes to the rules text —
	# exactly where long spell descs used to clip. MUST stay in lockstep with
	# the baked-overlay clip below.
	var rule_bot := 267 if is_sp else 260
	# DOES THIS CARD ACTUALLY HAVE RULES? (2026-07-30)
	#
	# A ruled box with metal corner ticks drawn around NOTHING reads as a card
	# that failed to load, not as a card with no abilities — Curtain Wall and
	# Hexwright both shipped a big empty frame (11 entries carry an empty desc;
	# the other 9 are enemy-only and never wear this layout). MTG's vanilla
	# creatures are the precedent: the text area simply isn't there, and the
	# blank field reads as deliberate.
	#
	# Deliberately keyed off card_data, NOT the stripped `raw_desc` below —
	# bake_strip_desc blanks the text for the bake while the live overlay draws
	# it, so testing the stripped value would delete the box from every baked
	# card in the game.
	var _own_desc: String = String(card_data.get("desc", "")).strip_edges()
	var has_rules: bool = _own_desc != "" \
		or (synth_desc_if_empty and _synthesized_rules_text().strip_edges() != "")
	var rulebox := Panel.new()
	rulebox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rulebox.anchor_left = 0.0
	rulebox.anchor_right = 1.0
	rulebox.anchor_top = 0.0
	rulebox.anchor_bottom = 0.0
	rulebox.offset_left = 15
	rulebox.offset_right = -15
	rulebox.offset_top = 174
	rulebox.offset_bottom = rule_bot
	var pst := StyleBoxFlat.new()
	pst.draw_center = false
	pst.border_color = Color(0.255, 0.188, 0.118, 0.80) if not is_curse_card \
		else Color(0.255, 0.275, 0.180, 0.85)
	pst.set_border_width_all(1)
	rulebox.add_theme_stylebox_override("panel", pst)
	if has_rules:
		root.add_child(rulebox)
		_chart_diamond(root, Vector2(15, 174), 3.6, metal_dim)
		_chart_diamond(root, Vector2(210, 174), 3.6, metal_dim)
		_chart_diamond(root, Vector2(15, rule_bot), 3.6, metal_dim)
		_chart_diamond(root, Vector2(210, rule_bot), 3.6, metal_dim)
	else:
		rulebox.queue_free()

	# ── description (dark ink written on the page) ───────────────────────
	if not bake_strip_desc:
		var desc_clip := Control.new()
		desc_clip.clip_contents = true
		desc_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_clip.anchor_left = 0.0
		desc_clip.anchor_right = 1.0
		desc_clip.anchor_top = 0.0
		desc_clip.anchor_bottom = 0.0
		desc_clip.offset_left = 17
		desc_clip.offset_right = -17
	# Text region grows with the band (was 184→255 = 71px → 176→258 = 82px;
	# spells run to the taller rule_bot band since the one-line footer).
		desc_clip.offset_top = 176
		desc_clip.offset_bottom = rule_bot - 2
		root.add_child(desc_clip)
		var center_box := CenterContainer.new()
		center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
		desc_clip.add_child(center_box)
		var desc_rt := RichTextLabel.new()
		desc_rt.bbcode_enabled = true
	# The [hint] glossary must not underline every keyword — that's reading
	# noise on the parchment. Hover DOES still work, but only because of the
	# filter below; it did not before 2026-08-01.
		desc_rt.hint_underlined = false
		desc_rt.fit_content = true
		desc_rt.scroll_active = false
		desc_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# PASS, not IGNORE — matching _build_baked_overlay_layout's `od_rt`, whose
	# comment already states the reason. IGNORE means the label never receives
	# mouse events at all, so `meta_hover_started` cannot fire and every [hint]
	# in the rules text is DEAD. Card2D has two render paths — this live one and
	# the baked-overlay one, chosen by whether CardTextureCache is warm — and
	# they disagreed, so the same card silently stopped explaining its own
	# keywords on a cold cache. The comment two lines up asserted "hover still
	# works" while this line prevented it. PASS lets hover reach the hints and
	# still drops clicks and drags through to the card panel underneath.
		desc_rt.mouse_filter = Control.MOUSE_FILTER_PASS
	# 182, not 170 (2026-07-30). desc_clip spans offset 17 → -17 on a natively
	# 225px card, i.e. 191px of usable line — the label was pinned 21px narrower
	# than its own container and had been for the life of the layout. That
	# wasted ~11% of every line in the game and is what pushed wordy cards
	# (Fuse Tender) onto an extra line and off the bottom of the band. Widening
	# costs no glyph size, no geometry and no readability; it just stops
	# throwing the width away. Leaves ~4.5px inside the clip and ~6.5px inside
	# the ruled border, so the text still never touches the rule.
	# MUST stay in lockstep with the baked-overlay path (od_rt, ~line 2005).
		desc_rt.custom_minimum_size = Vector2(182, 0)
	# Tighten Alegreya's generous default leading so the larger ramp still fits
	# the band. -2px/line claws back ~6px on a 4-line card without touching
	# legibility. Keep identical in the baked-overlay path below.
		desc_rt.add_theme_constant_override("line_separation", -2)
	# The writ writes its rules in a book hand (Alegreya) — a modern rounded
	# sans on period paper breaks the document fiction. Serif sizes run +1
	# on the sans scale: hairline serifs need it at these px sizes.
		var desc_font: Font = GameTheme.font_card_body \
			if GameTheme.font_card_body != null else GameTheme.font_body
		var desc_bold_font: Font = GameTheme.font_card_body_bold \
			if GameTheme.font_card_body_bold != null else GameTheme.font_body_bold
		if desc_font:
			desc_rt.add_theme_font_override("normal_font", desc_font)
			desc_rt.add_theme_font_override("bold_font",
				desc_bold_font if desc_bold_font else desc_font)
	# bake_strip_desc: leave the rules region BLANK in the bake — the live overlay
	# (_build_baked_overlay_layout) draws the text with the font renderer so it stays
	# crisp at any zoom (the StS model). The vellum panel above is still baked.
		var raw_desc: String = card_data.get("desc", "")
		if raw_desc == "" and synth_desc_if_empty:
			raw_desc = _synthesized_rules_text()
	# Bigger, more readable body text. The 15/14/13 ramp was still the #1
	# "too small to read" complaint at the real windowed (1600×900, no global
	# scaling) card size. Rewritten descriptions now use a fixed 18px size;
	# the fitter below is an overflow check, not a shrinking path.
	# The taller band + tightened leading above absorb the
	# growth. Keep this ramp IDENTICAL to the baked-overlay path below — they
	# draw the same live text and must not diverge.
		var dsz := 18
		desc_rt.add_theme_font_size_override("normal_font_size", dsz)
		desc_rt.add_theme_font_size_override("bold_font_size", dsz)
		desc_rt.add_theme_color_override("default_color", GameTheme.PARCHMENT_TEXT)
	# The keyword gold (#e8b547) is tuned for dark wells and disappears on
	# paper. Re-ink the same markup in dark bronze — keyword identity kept,
	# document contrast won (~5.5:1 on the leaf). decorate_keywords also
	# ink-stamps each keyword's device inline before its first mention
	# (2026-07-10 — replaces the bottom-margin roundel row). Written at every
	# scale, including the 0.36 deck strip: a deck strip hits this live path
	# whenever CardTextureCache is still cold (a freshly opened run-setup screen),
	# and small crisp text reads better than the duplicated art it used to show.
		var desc_bbcode := KeywordEffects.decorate_keywords(
			raw_desc, dsz - 3).replace(KeywordEffects.KEYWORD_GOLD, "#7a4f10")
		desc_rt.text = "[center]%s[/center]" % desc_bbcode
		center_box.add_child(desc_rt)
	# Shrink-to-fit safety net: once laid out, if the written text overflows the
	# clip box, report it while preserving the 18px reading floor.
	# so a line is never cut top or bottom by the CenterContainer clip.
		_fit_desc_to_box.call_deferred(desc_rt, 87.0 if is_sp else 80.0)

	# ── stats as wax seals OR the spell footer line ──────────────────────
	var stat_font: Font = GameTheme.font_stat
	var seal_metal := Color(0.62, 0.50, 0.26)
	if is_creature():
		var cost_seal := _chart_seal(GameTheme.COST_BLUE_GEM, seal_metal)
		cost_seal.anchor_left = 0.0
		cost_seal.anchor_right = 0.0
		cost_seal.anchor_top = 0.0
		cost_seal.anchor_bottom = 0.0
		cost_seal.offset_left = -9
		cost_seal.offset_right = 47
		cost_seal.offset_top = -9
		cost_seal.offset_bottom = 47
		root.add_child(cost_seal)
		# Stat numerals (P3): bumped 15→18px with a pure-white fill and a deep
		# 5px dark outline so they read crisply against the textured pressed-wax
		# face. The 56px seal box offsets are untouched — they are the
		# bake-overlay contract (see CLAUDE.md).
		if not bake_strip_stats:
			_cost_label = _make_styled_label(
				str(card_data.get("cost", 0)), stat_font, 19, Color(1, 1, 1))
			_cost_label.add_theme_color_override("font_outline_color",
				Color(0, 0, 0, 1.0))
			_cost_label.add_theme_constant_override("outline_size", 6)
			_cost_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
			_cost_label.add_theme_constant_override("shadow_offset_x", 1)
			_cost_label.add_theme_constant_override("shadow_offset_y", 1)
			_cost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_cost_label.offset_top = ORB_NUMERAL_Y_OFFSET
			_cost_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
			_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cost_seal.add_child(_cost_label)

		var atk_seal := _chart_seal(GameTheme.ATK_GOLD_SHIELD, seal_metal)
		atk_seal.anchor_left = 0.0
		atk_seal.anchor_right = 0.0
		atk_seal.anchor_top = 1.0
		atk_seal.anchor_bottom = 1.0
		atk_seal.offset_left = -9
		atk_seal.offset_right = 47
		atk_seal.offset_top = -47
		atk_seal.offset_bottom = 9
		root.add_child(atk_seal)
		if not bake_strip_stats:
			_atk_label = _make_styled_label(
				str(current_atk), stat_font, 19, Color(1, 1, 1))
			_atk_label.add_theme_color_override("font_outline_color",
				Color(0, 0, 0, 1.0))
			_atk_label.add_theme_constant_override("outline_size", 6)
			_atk_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
			_atk_label.add_theme_constant_override("shadow_offset_x", 1)
			_atk_label.add_theme_constant_override("shadow_offset_y", 1)
			_atk_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_atk_label.offset_top = ORB_NUMERAL_Y_OFFSET
			_atk_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
			_atk_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			atk_seal.add_child(_atk_label)

		var hp_seal := _chart_seal(GameTheme.HEALTH_RED_DROP, seal_metal)
		hp_seal.anchor_left = 1.0
		hp_seal.anchor_right = 1.0
		hp_seal.anchor_top = 1.0
		hp_seal.anchor_bottom = 1.0
		hp_seal.offset_left = -47
		hp_seal.offset_right = 9
		hp_seal.offset_top = -47
		hp_seal.offset_bottom = 9
		root.add_child(hp_seal)
		if not bake_strip_stats:
			_hp_label = _make_styled_label(
				str(current_hp), stat_font, 19, Color(1, 1, 1))
			_hp_label.add_theme_color_override("font_outline_color",
				Color(0, 0, 0, 1.0))
			_hp_label.add_theme_constant_override("outline_size", 6)
			_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
			_hp_label.add_theme_constant_override("shadow_offset_x", 1)
			_hp_label.add_theme_constant_override("shadow_offset_y", 1)
			_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_hp_label.offset_top = ORB_NUMERAL_Y_OFFSET
			_hp_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
			_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hp_seal.add_child(_hp_label)

		# Campaign memory: kill tallies scratched down the left page margin
		# (the strip between the art plate's foot and the ATK seal — marginalia
		# space, never over the painting). veteran_kills rides the folded card
		# data, so hand cards, deck viewers and Rest previews all show the record.
		var vk_kills: int = int(card_data.get("veteran_kills", 0))
		if vk_kills > 0:
			var tally := TallyMarks.new()
			tally.kills = vk_kills
			tally.seed_text = String(card_data.get("id", "?")) + str(deck_uid)
			tally.position = Vector2(3.5, 148.0)
			tally.size = Vector2(9.0, 102.0)
			tally.tooltip_text = "%d kills on campaign" % vk_kills
			tally.mouse_filter = Control.MOUSE_FILTER_PASS
			root.add_child(tally)
		# Creature type tag (2026-07-10): the letterpress footer slot carries
		# the creature's type — the tag ctype effects read (Warchief's
		# Soldiers, Siege Golem's Engines). No type, no filler.
		# Built through the shared funnel — see _make_ctype_footer_label.
		var ct_lbl := _make_ctype_footer_label()
		if ct_lbl != null:
			root.add_child(ct_lbl)
	else:
		# Spells still pay a cost — the seal stays; the bottom carries the
		# letterspaced footer line instead of ATK/HP.
		var sp_cost := _chart_seal(GameTheme.COST_BLUE_GEM, seal_metal)
		sp_cost.anchor_left = 0.0
		sp_cost.anchor_right = 0.0
		sp_cost.anchor_top = 0.0
		sp_cost.anchor_bottom = 0.0
		sp_cost.offset_left = -9
		sp_cost.offset_right = 47
		sp_cost.offset_top = -9
		sp_cost.offset_bottom = 47
		root.add_child(sp_cost)
		if not bake_strip_stats:
			_cost_label = _make_styled_label(
				str(card_data.get("cost", 0)), stat_font, 19, Color(1, 1, 1))
			_cost_label.add_theme_color_override("font_outline_color",
				Color(0, 0, 0, 1.0))
			_cost_label.add_theme_constant_override("outline_size", 6)
			_cost_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
			_cost_label.add_theme_constant_override("shadow_offset_x", 1)
			_cost_label.add_theme_constant_override("shadow_offset_y", 1)
			_cost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_cost_label.offset_top = ORB_NUMERAL_Y_OFFSET
			_cost_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
			_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sp_cost.add_child(_cost_label)

		# One honest line (2026-07-10): "SPELL — TARGET ENEMY · EXHAUST". The old
		# two-line block (a spaced-out SPELL over the contract) hid Exhaust and
		# Retain whenever the spell was targeted, and padded untargeted spells
		# with INSTANT — a timing word this game has no timing system for. The
		# freed line went to the rules band above (rule_bot). The explicit SPELL
		# word survives on the line: creature-vs-spell must not be readable only
		# by omission (3 seals vs 1).
		var footer_text := _spell_footer_text()
		# Short badges (SPELL / CURSE) keep the letterpress char-spacing; full
		# contract lines are already wide and print plain.
		if footer_text.length() <= 8:
			var spaced := ""
			for ci in range(footer_text.length()):
				spaced += footer_text[ci]
				if ci < footer_text.length() - 1:
					spaced += " "
			footer_text = spaced
		# Fit by measure, not char count: the footer well is ~166 real px between
		# the flanking diamonds; step the size down (floor 10) until it fits.
		var foot_font: Font = GameTheme.font_title \
			if GameTheme.font_title != null else GameTheme.font_display
		var fsz := 14
		while fsz > 10 and foot_font != null and foot_font.get_string_size(
				footer_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsz).x > 166.0:
			fsz -= 1
		# Letterpress ink on the paper (the gilt-on-dark v7 color washes out
		# against parchment).
		var foot_col := Color(0.302, 0.224, 0.133, 0.95)
		if is_curse_card:
			foot_col = Color(0.318, 0.310, 0.255, 0.95)
		var ftl := _make_styled_label(footer_text, foot_font, fsz, foot_col)
		ftl.add_theme_constant_override("outline_size", 0)
		ftl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		ftl.add_theme_constant_override("shadow_offset_y", 1)
		_center_at_point(ftl, Vector2(150, 374), Vector2(230, 24))
		root.add_child(ftl)
		_chart_diamond(root, Vector2(24, 280.5), 5.0, metal_dim)
		_chart_diamond(root, Vector2(201, 280.5), 5.0, metal_dim)


# ═══════════════════════════════════════════
#  V4 LAYOUT — procedural frame, no PNG dependency.
#  Per docs/prompts/card_design_doc.md §5/§15:
#    • 225×300 card (aspect 0.75, matches Hearthstone/MtG conventions)
#    • Cost = blue hex / ATK = yellow shield / HP = red drop (Hearthstone-canonical)
#    • Rarity gem at art-bottom; gold trim only on `rare`
#    • Art window 48% of card height (Hearthstone band)
#    • Description on light-tan parchment well at 10pt (≥WCAG AAA contrast)
#    • Spell cards: pentagonal peak above banner + SPELL tag at bottom
# ═══════════════════════════════════════════

func _make_stat_number(text: String, color: Color, vertical_offset: int = 0,
		glow_color: Color = Color(0, 0, 0, 0)) -> Label:
	# Numeral overlay for a stat orb. Cinzel Black on top of a coloured
	# halo: `font_shadow_color` at offset (0, 0) with a generous
	# `shadow_outline_size` renders as a soft colored bloom around each
	# glyph — the same trick CSS uses for "neon" text, free in Godot's
	# Label theme. This is what makes the numbers stop reading as plain.
	#
	# Layering (back → front):
	#   1. Shadow glow — expanded glyph silhouette, glow_color tint.
	#   2. Outline — sharp black border keeping the glyph legible against
	#      the sphere's directional gradient.
	#   3. Glyph fill — `color` (cream / dark).
	#
	# `vertical_offset` nudges the label vs geometric centre — unused for
	# symmetric spheres but kept for future asymmetric overlays.
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_stat:
		lbl.add_theme_font_override("font", GameTheme.font_stat)
	# 18 pt sized for the 44 px sphere.
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	# 4 px outline (scaled from 5 to match smaller glyph) pushes the AA
	# edge of every glyph into solid black, guaranteeing legibility on
	# top of the sphere's directional gradient.
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.98))
	lbl.add_theme_constant_override("outline_size", 4)
	# Colored halo via shadow_outline_size — only kicks in if the caller
	# passes a glow_color. Centred (offset 0,0) so it bleeds equally on all
	# sides. Dialed back 7→4 px (2026-06-22): the big bright bloom "poked at
	# the eyes"; a tighter halo keeps the subtle mana/blood/gold tint that AAA
	# card games use without the numbers glaring. (Caller alphas were also
	# lowered in _build_baked_overlay_layout.)
	if glow_color.a > 0.001:
		lbl.add_theme_color_override("font_shadow_color", glow_color)
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", 0)
		lbl.add_theme_constant_override("shadow_outline_size", 4)
	else:
		# Fallback: traditional offset drop shadow, no glow.
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Apply ORB_NUMERAL_Y_OFFSET unconditionally so every _make_stat_number
	# caller (baked overlay, v4 layout, v5 layout) gets the same optical-
	# centering nudge. `vertical_offset` callers add on top of that for any
	# additional asymmetric overlay needs.
	var total_y_offset := ORB_NUMERAL_Y_OFFSET + vertical_offset
	lbl.offset_top = total_y_offset
	lbl.offset_bottom = total_y_offset
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _center_at_point(c: Control, point: Vector2, size: Vector2) -> void:
	# Place `c` with its rect CENTERED on `point` (in 300x400 frame ref coords),
	# at `size` (also in ref coords, scaled to card pixels by FRAME_TO_CARD_SCALE).
	# Anchor x/y are identical for left/right and top/bottom — the rect is built
	# entirely by the symmetric offsets, so it's always centered on `point`
	# regardless of card size or container layout.
	c.anchor_left = point.x / FRAME_REF_SIZE.x
	c.anchor_right = c.anchor_left
	c.anchor_top = point.y / FRAME_REF_SIZE.y
	c.anchor_bottom = c.anchor_top
	var half_w := size.x * FRAME_TO_CARD_SCALE * 0.5
	var half_h := size.y * FRAME_TO_CARD_SCALE * 0.5
	c.offset_left = -half_w
	c.offset_right = half_w
	c.offset_top = -half_h
	c.offset_bottom = half_h


# Map of name/id keywords → subtype label. First match wins; later entries
# are more specific overrides for the earlier generic buckets. Used by
# _creature_type_text when card_data has no explicit "subtype" field.
# Heuristic only — letting designers refine via card_data.subtype later
# without changing this table.
const _SUBTYPE_HINTS: Array = [
	["dragon", "DRAGON"], ["drake", "DRAGON"], ["wyrm", "DRAGON"],
	["hatchling", "DRAGON"],
	["vampire", "VAMPIRE"],  # avoid "blood" — matches Bloodhound (BEAST)
	["demon", "DEMON"], ["imp", "DEMON"], ["devil", "DEMON"],
	["fiend", "DEMON"], ["infernal", "DEMON"], ["chaos", "DEMON"],
	["ghost", "SPIRIT"], ["spirit", "SPIRIT"], ["wraith", "SPIRIT"],
	["shade", "SPIRIT"], ["specter", "SPIRIT"], ["banshee", "SPIRIT"],
	["vengeful", "SPIRIT"], ["phantom", "SPIRIT"],
	["skeleton", "UNDEAD"], ["lich", "UNDEAD"], ["necro", "UNDEAD"],
	["bone", "UNDEAD"], ["corpse", "UNDEAD"], ["grave", "UNDEAD"],
	["warden", "UNDEAD"], ["risen", "UNDEAD"],
	["archmage", "MAGE"], ["mage", "MAGE"], ["wizard", "MAGE"],
	["witch", "MAGE"], ["warlock", "MAGE"], ["sorcer", "MAGE"],
	["acolyte", "CULTIST"], ["cultist", "CULTIST"], ["zealot", "CULTIST"],
	["fanatic", "CULTIST"],
	["titan", "GIANT"], ["giant", "GIANT"],
	["golem", "CONSTRUCT"], ["siege", "CONSTRUCT"], ["bastion", "CONSTRUCT"],
	["iron", "CONSTRUCT"], ["stone", "CONSTRUCT"],
	["paladin", "KNIGHT"], ["doom", "KNIGHT"], ["knight", "KNIGHT"],
	["royal", "KNIGHT"], ["guard", "KNIGHT"], ["veteran", "KNIGHT"],
	["champion", "KNIGHT"], ["templar", "KNIGHT"],
	["assassin", "ROGUE"], ["bandit", "ROGUE"], ["thief", "ROGUE"],
	["scout", "ROGUE"], ["shadow", "ROGUE"],
	["ranger", "ARCHER"], ["archer", "ARCHER"], ["sharpshoot", "ARCHER"],
	["berserker", "MARAUDER"], ["orc", "MARAUDER"], ["goblin", "MARAUDER"],
	["ratling", "MARAUDER"], ["barbarian", "MARAUDER"],
	["wolf", "BEAST"], ["hound", "BEAST"], ["hydra", "BEAST"],
	["beast", "BEAST"], ["thorn", "BEAST"], ["spore", "BEAST"],
	["bog", "BEAST"], ["lurker", "BEAST"],
	["harpy", "HARPY"], ["matron", "HARPY"],
	["doppelganger", "MIMIC"], ["mirror", "MIMIC"], ["puppet", "MIMIC"],
	["reflection", "MIMIC"],
	["sprite", "FAE"], ["fae", "FAE"], ["pixie", "FAE"],
]


func _make_type_pill(text: String, text_color: Color,
		top_anchor: float, bottom_anchor: float,
		left_anchor: float, right_anchor: float) -> CenterContainer:
	# StS / Hearthstone / MtG convention: type tags sit on a small dark
	# "pill" so their contrast is independent of the card body colour.
	# Our previous text-only tag lost contrast against the variable bottom
	# strip (dark walnut behind some keywords, lighter where the parchment
	# well's drop shadow lifts; rare cards have a warm wash; uncommons cool).
	# The pill puts the same neutral dark backdrop behind every card type
	# so the gold/purple text always reads.
	#
	# Layout: CenterContainer anchored to the bottom strip wraps a tight
	# PanelContainer; the panel auto-sizes to the Label inside via the
	# StyleBoxFlat's content_margin. Result: a pill that grows with the
	# text and stays centered, regardless of how long the subtype is.
	var wrap := CenterContainer.new()
	wrap.anchor_left = left_anchor
	wrap.anchor_right = right_anchor
	wrap.anchor_top = top_anchor
	wrap.anchor_bottom = bottom_anchor
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := StyleBoxFlat.new()
	# Dark walnut at 92% alpha — opaque enough to override card body hue,
	# the small transparency lets the body's grain show through faintly so
	# the pill still feels painted on, not pasted on.
	pill_style.bg_color = Color(0.055, 0.035, 0.020, 0.92)
	# Warm gold trim ties the pill to the card's gilt accents; subtle so
	# the dark fill is what the eye reads as contrast.
	pill_style.border_color = Color(0.55, 0.42, 0.18, 0.85)
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(7)
	pill_style.content_margin_left = 7
	pill_style.content_margin_right = 7
	pill_style.content_margin_top = 1
	pill_style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", pill_style)
	wrap.add_child(pill)

	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", text_color)
	# Thinner outline than before — the dark pill provides the bulk of the
	# contrast, so the outline's only job is crisping AA-edges. A heavy
	# outline + pill bg would crush the glyphs into mush.
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)
	return wrap


func _creature_type_text() -> String:
	# Subtype shown on the creature bottom badge. Designers can set
	# card_data.subtype explicitly; otherwise we infer from name + id
	# keywords via _SUBTYPE_HINTS. Falls back to "CREATURE" so unknown
	# entries still get a label.
	var st: String = String(card_data.get("subtype", ""))
	if st != "":
		return st.to_upper()
	var name_lower: String = String(card_data.get("name", "")).to_lower()
	var id_lower: String = String(card_data.get("id", "")).to_lower()
	var search: String = name_lower + " " + id_lower
	for entry in _SUBTYPE_HINTS:
		var needle: String = entry[0]
		if needle in search:
			return entry[1]
	return "CREATURE"


## The letterpress tribe footer ("B E A S T") — the ONE writer of that band's
## text, metrics and placement. Returns null when there is nothing to print.
##
## It has to be built from TWO layouts, and that is the whole point of the
## funnel. The bake STRIPS this band along with the name (bake_strip_name) so the
## font renderer can draw it live and stay razor-sharp down at the 0.36–0.72 deck
## strip, exactly like the name and the rules text (the StS model). But from
## 2026-07-10 until 2026-08-04 only the STRIP half existed — nothing ever redrew
## it — so `_build_baked_overlay_layout` printed an empty band. That is every
## card face in real play: hand cards, Reward, Shop, Recruit, Rest, Event, the
## deck viewer, THE COLUMN. The tag was visible only in the frame or two before
## the bake landed, which is why it survived in screenshots and nowhere else.
##
## Keep both layouts on this funnel so the halves cannot drift apart again.
func _make_ctype_footer_label() -> Label:
	# `bake_strip_name` means THIS instance is the bake — leave the band bare and
	# let the display card's overlay draw it.
	if bake_strip_name or not is_creature():
		return null
	var ct_id := String(card_data.get("ctype", ""))
	if ct_id == "":
		return null
	var ct_text := ct_id.to_upper()
	var ct_spaced := ""
	for ci in range(ct_text.length()):
		ct_spaced += ct_text[ci]
		if ci < ct_text.length() - 1:
			ct_spaced += " "
	var ct_lbl := _make_styled_label(ct_spaced,
		GameTheme.font_title if GameTheme.font_title != null else GameTheme.font_display,
		12, Color(0.302, 0.224, 0.133, 0.85))
	ct_lbl.add_theme_constant_override("outline_size", 0)
	ct_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	ct_lbl.add_theme_constant_override("shadow_offset_y", 1)
	# Same ref-space point in both layouts: 374/400 of the card height = the
	# real y=280.5 band the flanking chart diamonds sit on.
	_center_at_point(ct_lbl, Vector2(150, 374), Vector2(230, 24))
	return ct_lbl


func _make_styled_label(text: String, font: Font, font_size: int,
		color: Color) -> Label:
	# Standard card-text label: centered horizontally and vertically inside its
	# anchor rect, with a black outline for readability over the painted frame
	# art. Callers can override outline color/size after (e.g. parchment text
	# uses a warm outline instead of black).
	var lbl := Label.new()
	lbl.text = text
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _build_placeholder_art(parent: Control, al: float, ar: float,
		at: float, ab: float) -> Control:
	# Plain hash-tinted gradient. No silhouette/icon overlay — board-game
	# icons (chess pieces, swords, etc.) clashed hard with the painterly
	# style of cards that DO have art. Better to be quietly minimalist than
	# loudly mismatched. Cards with dedicated illustrations look painted;
	# cards without look like unrevealed glyphs.
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.anchor_left = al
	wrap.anchor_right = ar
	wrap.anchor_top = at
	wrap.anchor_bottom = ab
	parent.add_child(wrap)

	# Two-tone vertical gradient: dark hash-tinted at the bottom, slightly
	# lighter at the top. Gives the placeholder some visual depth without
	# competing with real card art elsewhere on the screen.
	var hue := float(abs(card_id.hash()) % 360) / 360.0
	var sat := 0.45 if not is_opponent else 0.28
	var top_bg := ColorRect.new()
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_bg.color = Color.from_hsv(hue, sat * 0.6, 0.18)
	wrap.add_child(top_bg)
	var bottom_bg := ColorRect.new()
	bottom_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bg.anchor_left = 0.0
	bottom_bg.anchor_right = 1.0
	bottom_bg.anchor_top = 0.45
	bottom_bg.anchor_bottom = 1.0
	bottom_bg.color = Color.from_hsv(hue, sat, 0.09)
	wrap.add_child(bottom_bg)
	return wrap


func _make_circle_badge(color: Color, sz: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.lightened(0.3)
	s.border_color.a = 0.4
	var r := int(sz * 0.5)
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	p.add_theme_stylebox_override("panel", s)
	return p


func _make_badge_label(text: String, font_sz: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# Engraved-style number for a GemOrb. Same emboss recipe as the hand-card
# stat orbs — thick dark outline (separation from facet shading), soft drop
# shadow (number reads as raised, not painted on), heavy stat font for the
# numeral weight every AAA card game uses (Cinzel Black / Beleren Bold).
#
# light_face=true  → bright cream face on dark gems (cost blue, HP red).
# light_face=false → deep brown face with cream outline on the gold ATK
#                    shield — "stamped into metal" treatment.
func _build_orb_number_label(text: String, font_sz: int,
		light_face: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_stat:
		lbl.add_theme_font_override("font", GameTheme.font_stat)
	elif GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", font_sz)
	if light_face:
		# Battlefield stat numerals must read over dark art on a dark table —
		# the whole "can't evaluate the trade" problem. Stamp them the way the
		# floating combat numbers are stamped (pure-white face + a heavy fully
		# opaque black outline, ~6px on the 26-38px float labels): the outline
		# carries the legibility, so the fill never has to fight the wax. Scaled
		# to the 18px seal numeral, a 5px outline + a thicker drop shadow gives
		# the same readable-on-anything punch without going garish.
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_color_override("font_outline_color",
			Color(0, 0, 0, 1.0))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.add_theme_color_override("font_shadow_color",
			Color(0, 0, 0, 0.70))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	else:
		lbl.add_theme_color_override("font_color",
			Color(0.118, 0.078, 0.024))
		lbl.add_theme_color_override("font_outline_color",
			Color(1, 0.96, 0.78, 0.85))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_shadow_color",
			Color(0, 0, 0, 0.45))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Same optical-centering nudge as the hand orbs — see ORB_NUMERAL_Y_OFFSET.
	# Field orbs are smaller (30 px vs 56 px), but the cap-high-in-line-box
	# phenomenon is font-metric driven so it applies at every size; the
	# painted shadow ratio is similar too. One value works for both.
	lbl.offset_top = ORB_NUMERAL_Y_OFFSET
	lbl.offset_bottom = ORB_NUMERAL_Y_OFFSET
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ═══════════════════════════════════════════
#  STAT UPDATES
# ═══════════════════════════════════════════

func update_stat_display() -> void:
	if _hp_label:
		# A GAIN in HP (heal, +N/+N buff, Regenerate tick, a keystone aura
		# landing) had no beat at all before C2 — the numeral just was a
		# different number next frame, so the thing the tribe keystones exist to
		# do was the thing the board never showed. Losses are NOT floated here:
		# every path that lowers HP runs through take_damage /
		# take_damage_bypass_armor, which spawn their own damage number, and a
		# second float would double-count the hit.
		if _displayed_hp != -999 and current_hp != _displayed_hp:
			if current_hp > _displayed_hp:
				_spawn_hp_change_popup(current_hp - _displayed_hp)
			_punch_seal(_hp_label)
		_displayed_hp = current_hp
		_hp_label.text = str(max(current_hp, 0))
		if current_hp < card_data.hp:
			_hp_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
		else:
			_hp_label.add_theme_color_override("font_color", _hp_base_color)
	if _atk_label:
		var display_atk = effective_atk()
		if _displayed_effective_atk != -999 and display_atk != _displayed_effective_atk:
			_spawn_atk_change_popup(display_atk - _displayed_effective_atk)
			_punch_seal(_atk_label)
		_displayed_effective_atk = display_atk
		_atk_label.text = str(display_atk)
		if display_atk > card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.ATK_BUFFED)
			_set_atk_caret(1)
		elif display_atk < card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
			_set_atk_caret(-1)
		else:
			_atk_label.add_theme_color_override("font_color", _atk_base_color)
			_set_atk_caret(0)
	# Most keyword/status mutation sites in Combat.gd call update_stat_display
	# right after — piggyback the status-rail dirty check here so a granted
	# keyword shows the same frame the stats refresh (the _process poll is only
	# the fallback for sites that don't).
	_refresh_status_rail()


func _set_atk_caret(state: int) -> void:
	# state: 1 = buffed (▲ gold), -1 = debuffed (▼ red), 0 = none. The drawn caret
	# is the non-colour redundancy for the ATK recolour (colour-blind safety).
	if _atk_label == null:
		return
	if _atk_caret == null:
		if state == 0:
			return
		var seal := _atk_label.get_parent()
		if seal == null:
			return
		var c := StatCaret.new()
		c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		c.offset_left = -15
		c.offset_right = -3
		c.offset_top = 2
		c.offset_bottom = 13
		c.z_index = 6
		seal.add_child(c)
		_atk_caret = c
	var caret := _atk_caret as StatCaret
	if state == 0:
		caret.visible = false
		return
	caret.visible = true
	caret.up = state > 0
	caret.col = GameTheme.cb_color(GameTheme.ATK_BUFFED if state > 0 else GameTheme.HP_DAMAGED)
	caret.queue_redraw()


func update_floop_display() -> void:
	# Floop is fully vestigial dead code: no card carries a `floop` key and
	# will_floop is read by zero combat logic. Kept as a no-op stub because
	# Combat.gd still calls it on placement/turn-flip; the (permanently hidden)
	# _floop_indicator label is still created inert by the layout builders. If
	# floop is ever revived, restore the badge/border rendering from git history.
	pass


# ═══════════════════════════════════════════
#  DOOM — ticking-bomb countdown badge
# ═══════════════════════════════════════════

func _ensure_doom_init() -> void:
	# Seed doom_counter from card_data.doom the first time it's read. card_data
	# is frequently assigned after _ready (enemy placement, tokens), so we can't
	# rely on a constructor — lazy-init on first display/tick instead.
	if doom_counter == -999:
		doom_counter = int(card_data.get("doom", 0))


func _build_doom_badge(parent: Control) -> void:
	# The countdown disc + numeral. Called from the compact layout build, and
	# late via ensure_doom_badge when a spell brands Doom mid-fight.
	_ensure_doom_init()
	var doom_box := 38.0
	_doom_badge = GemOrb.new()
	_doom_badge.shape = "circle"
	_doom_badge.style = "smooth"
	_doom_badge.fill_color = Color(0.78, 0.10, 0.10)  # alarm red
	_doom_badge.gloss = 0.9
	_doom_badge.anchor_left = 0.0; _doom_badge.anchor_right = 0.0
	_doom_badge.anchor_top = 0.0; _doom_badge.anchor_bottom = 0.0
	_doom_badge.offset_left = 3.0
	_doom_badge.offset_right = 3.0 + doom_box
	_doom_badge.offset_top = 3.0
	_doom_badge.offset_bottom = 3.0 + doom_box
	_doom_badge.pivot_offset = Vector2(doom_box * 0.5, doom_box * 0.5)
	_doom_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_doom_badge)
	_doom_label = Label.new()
	_doom_label.text = str(maxi(doom_counter, 0))
	if GameTheme.font_stat:
		_doom_label.add_theme_font_override("font", GameTheme.font_stat)
	elif GameTheme.font_display:
		_doom_label.add_theme_font_override("font", GameTheme.font_display)
	_doom_label.add_theme_font_size_override("font_size", 18)
	_doom_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_doom_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_doom_label.add_theme_constant_override("outline_size", 4)
	_doom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_doom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_doom_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_doom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doom_badge.add_child(_doom_label)


var _fuse_cord: Control = null

func set_fuse_glow(n: int) -> void:
	# Slow Match (S5 of docs/SPELL_FX_PLAN_20260717.md): the writ IS a slow
	# match, and the fuse it banks while waiting in hand was invisible outside
	# the targeting hover — the card hits harder every round and nothing on the
	# face said so. A burning cord creeps across the top margin, one glowing
	# knot per banked point (cap 4), the lit head marching toward the cost
	# seal. INFORMATIONAL by the reduce-motion contract (it carries game
	# state), so it always renders; only the flicker breathe gates.
	if n <= 0:
		if _fuse_cord != null and is_instance_valid(_fuse_cord):
			_fuse_cord.visible = false
		return
	if _fuse_cord == null or not is_instance_valid(_fuse_cord):
		_fuse_cord = Control.new()
		_fuse_cord.name = "FuseCord"
		_fuse_cord.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fuse_cord.position = Vector2.ZERO
		_fuse_cord.size = Vector2(size.x, 34.0)
		_fuse_cord.draw.connect(_draw_fuse_cord)
		add_child(_fuse_cord)
		if not (UserSettings != null and UserSettings.reduce_motion):
			var tw := _fuse_cord.create_tween().set_loops()
			tw.tween_property(_fuse_cord, "modulate:a", 0.72, Motion.LOOP * 0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(_fuse_cord, "modulate:a", 1.0, Motion.LOOP * 0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fuse_cord.visible = true
	_fuse_cord.set_meta("fuse_n", n)
	_fuse_cord.queue_redraw()


func _draw_fuse_cord() -> void:
	if _fuse_cord == null or not is_instance_valid(_fuse_cord):
		return
	var n: int = int(_fuse_cord.get_meta("fuse_n", 0))
	if n <= 0:
		return
	# Cord runs right→left along the top margin, tied near the top-right
	# corner (inboard of it — the hand fan overlaps neighbours' corners),
	# burning toward the wax cost seal. Lit head position = charge gauge.
	# Sizes are generous: rest-state hand cards render well under full scale
	# and the first cut's 9px ember vanished at rest (shot-verified).
	var y := 17.0
	var x_start: float = size.x - 28.0
	var x_end := 66.0   # stops short of the 56px cost-seal corner box
	var lit_x: float = lerpf(x_start, x_end, clampf(float(n) / 4.0, 0.0, 1.0))
	# Unburnt cord ahead of the flame — dark line with a slight rope sag.
	var cord := Color(0.16, 0.12, 0.09, 0.92)
	var prev := Vector2(lit_x, y)
	for i in range(1, 9):
		var f := float(i) / 8.0
		var p := Vector2(lerpf(lit_x, x_end, f), y + sin(f * PI) * 3.5)
		_fuse_cord.draw_line(prev, p, cord, 3.4, true)
		prev = p
	# Charred tail behind the head: one glowing knot per banked point (the lit
	# head is the last), so the COUNT reads without a numeral. The hover
	# prediction already prints the exact total (card-honesty rule).
	for i in range(n):
		var kx: float = lerpf(x_start, lit_x, (float(i) + 1.0) / float(n))
		var head: bool = i == n - 1
		var kp := Vector2(kx, y)
		# SMOOTH, NOT STEPPED. These were three concentric filled discs at
		# r13/r7.5/r4 and alpha 0.26/0.65/1.00 — a hand-rolled falloff in three
		# jumps, which reads as two visible RINGS on the one thing in the frame
		# that is meant to be a burning coal. `draw_glow` is the same intent with
		# a real radial falloff, so the ember has no edge at any radius.
		if head:
			Motion.draw_glow(_fuse_cord, kp, 15.0,
				Color(1.0, 0.52, 0.16, 0.97), 0.34, 1.15)
		else:
			Motion.draw_glow(_fuse_cord, kp, 7.0,
				Color(0.94, 0.44, 0.13, 0.88), 0.40, 1.25)
	# Ash flecks between knots — the cord has visibly BURNED, not just lit.
	var ash := Color(0.38, 0.33, 0.28, 0.55)
	for i in range(3):
		var bx: float = lerpf(x_start, lit_x, (float(i) + 0.5) / 3.0)
		_fuse_cord.draw_circle(Vector2(bx, y + 2.5), 1.8, ash, true, -1.0, true)


func ensure_doom_badge() -> void:
	# Mark of Ash brands Doom onto a creature mid-fight — the badge is normally
	# built with the compact layout, so build it late here. No-op off the
	# battlefield or when the badge already exists.
	if _doom_badge != null and is_instance_valid(_doom_badge):
		return
	if _compact_root == null or not is_instance_valid(_compact_root):
		return
	_build_doom_badge(_compact_root)


func update_doom_display() -> void:
	# Refresh the red countdown badge. Built lazily so it works no matter which
	# layout this card uses; only meaningful on battlefield tokens (the compact
	# layout owns the badge node).
	if not has_keyword("doom"):
		if _doom_badge != null and is_instance_valid(_doom_badge):
			_doom_badge.visible = false
		return
	_ensure_doom_init()
	if _doom_label != null and is_instance_valid(_doom_label):
		_doom_label.text = str(maxi(doom_counter, 0))
		if _doom_badge != null and is_instance_valid(_doom_badge):
			_doom_badge.visible = true


func flash_doom_tick() -> void:
	# LOUD per-tick telegraph: a red punch + shake on the badge (and a light
	# body flash) so the player feels the clock advance each round. The final
	# tick (counter at 1, or 0 on the detonation round) escalates — bigger
	# punch, deeper wash, lower-louder tick — so "about to blow" is unmissable.
	if static_display:
		return
	_ensure_doom_init()
	var final_tick: bool = doom_counter <= 1
	if AudioBank != null:
		# Clock tick each round. Pitched down hard while button_click stands in
		# for the cue (SFX_FALLBACKS) — a UI click at full pitch reads as a
		# misclick, not a clock; a real clip plays near-straight.
		var tick_base: float = 1.0 if AudioBank.has_own_sfx("doom_tick") else 0.72
		AudioBank.play_sfx("doom_tick", 0.03, -2.0 if final_tick else -8.0,
			tick_base * (0.82 if final_tick else 1.0))
	if _doom_badge != null and is_instance_valid(_doom_badge):
		var punch: float = 1.9 if final_tick else 1.5
		var tw := create_tween()
		tw.tween_property(_doom_badge, "scale", Vector2(punch, punch), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_doom_badge, "scale", Vector2(1.0, 1.0), 0.18).set_ease(Tween.EASE_OUT)
	# A brief red wash on the card body underscores the danger.
	var base := modulate
	var btw := create_tween()
	if final_tick:
		btw.tween_property(self, "modulate", Color(base.r * 1.9, base.g * 0.40, base.b * 0.35, base.a), 0.10)
		btw.tween_property(self, "modulate", base, 0.40).set_ease(Tween.EASE_OUT)
	else:
		btw.tween_property(self, "modulate", Color(base.r * 1.6, base.g * 0.55, base.b * 0.5, base.a), 0.08)
		btw.tween_property(self, "modulate", base, 0.24).set_ease(Tween.EASE_OUT)


# ═══════════════════════════════════════════
#  DAMAGE
# ═══════════════════════════════════════════

## Bulwark Novice (shield_rage): losing the Shield stokes it — +2 ATK this fight
## (+3 upgraded). Self-contained on the card so every shield-pop path (normal
## hits, armor-bypass hits) pays out identically.
func _apply_shield_rage() -> void:
	if card_data.get("passive", "") != "shield_rage":
		return
	var rage: int = 3 if bool(card_data.get("is_upgraded", false)) else 2
	current_atk += rage
	_spawn_keyword_chip("RAGE +%d" % rage, Color(1.0, 0.55, 0.25))


func take_damage(amount: int, from_ward: bool = false) -> void:
	# The Old King's Body (effect_immune): ONLY a creature's strike lands. Combat
	# raises strike_damage_active around the two strike lines and nowhere else, so
	# spells, battlecries, on-deaths, Thorns, Poison, potions and relics all bounce
	# here without any of them needing to know this creature exists. The 99+ kill
	# convention is deliberately NOT exempted — "unaffected by effects" has to beat
	# Offering and the ritual outlets too, or it is not the promise it prints.
	if state.effect_immune and not strike_damage_active:
		return
	var siege_blow := bool(card_data.get("fortification", false)) and amount >= 99
	# Oathbound Squire (ward_by): a bodyguard in this creature's column takes
	# the hit instead. One hop only (from_ward), so two squires sharing a column
	# swap hits rather than bouncing one forever. Kill-convention damage (99+ —
	# rituals, Offering's 999) always lands: a sacrifice cannot be bodyguarded.
	if not from_ward and amount < 99 and ward_by != null and is_instance_valid(ward_by) \
			and ward_by.current_hp > 0:
		# NAME THE PROTECTOR (COMBAT_LEGIBILITY_20260728 §4 #3). This redirect used
		# to be `ward_by.take_damage(); return` and nothing else: you struck card A
		# and card B silently lost HP, with no chip, no log row and no cause named
		# anywhere on screen — the worst kind of defect, since the player's model of
		# the board is simply wrong afterwards. The chip fires on the WARD because
		# the ward is the body the player just watched lose life; the struck body
		# already carries the standing "Guarded" orb on its status rail, so the two
		# halves of the rule read from opposite ends. INFORMATIONAL — it always
		# plays (Combat.spawn_keyword_callout never gates on Reduce Motion) and
		# _spawn_keyword_chip mirrors it into the chronicle through log_status.
		# Deliberately carries NO number: the ward prints its own damage numeral for
		# what it actually lost (it may be Armored, or Shielded), and a raw-blow
		# figure beside it would put two different numbers for one hit on one body —
		# the same arithmetic-must-add-up rule as the OVERKILL note below.
		# Only when there is something to take: a 0-ATK body still calls in here,
		# and a chip announcing a redirect of nothing is noise in a channel whose
		# whole problem is quantity.
		if amount > 0:
			ward_by._spawn_keyword_chip("TAKES IT", Color(0.65, 0.85, 1.0), "guardian")
		ward_by.take_damage(amount, true)
		return
	# Kill-convention damage represents banish, sacrifice or unconditional
	# destruction. It cannot be bodyguarded; against a fortification it becomes
	# four raw damage, exactly 3 through the gate's printed Armored.
	if siege_blow:
		amount = 4
		_spawn_keyword_chip("SIEGE 3", Color(0.94, 0.72, 0.32))
	# Witch-Shot (bridge_watcher id): while the player's damage spell resolves,
	# ENEMY Armored and Shield are ignored — the shot passes straight through
	# (the Shield is NOT consumed; the spell never touched it). Enemy-only so
	# recoil landing on the player's own wards during the cast can't pierce.
	var pierced: bool = spell_pierce_active and is_opponent and not siege_blow
	if pierced and amount > 0:
		_spawn_keyword_chip("PIERCED", Color(0.80, 0.55, 1.0))
	# Shield: absorb the entire first hit, then pop the shield.
	if state.has_shield and not pierced:
		state.has_shield = false
		_spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0), "shield", true)
		_apply_shield_rage()
		update_stat_display()
		_flash_hit()
		return
	var original := amount
	if has_keyword("armored") and not pierced:
		amount = maxi(1, amount - 1)
		var blocked: int = original - amount
		if blocked > 0:
			_spawn_keyword_chip("BLOCKED %d" % blocked,
				Color(0.55, 0.78, 1.0), "armored", true)
	if card_data.get("extra_damage", 0) > 0:
		amount += card_data.extra_damage
	# OVERKILL HONESTY (2026-07-28). The floating numeral must show what this body
	# actually ABSORBED, not the raw blow. Before overkill shipped the excess
	# vanished, so over-printing was harmless; now _apply_piercing_overflow deals
	# that excess to the body behind, which prints its OWN numeral — so a 6-ATK
	# killing a 2-HP blocker and carrying 4 read "-6" and "-4" on screen: ten
	# damage from a six-power attacker. The arithmetic was visibly wrong, and the
	# rule is only learnable from the numbers if the numbers add up.
	var hp_before: int = current_hp
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
		_spawn_keyword_chip("LAST STAND",
			Color(1.0, 0.85, 0.20), "last_stand", true)
		_play_last_stand_flare()
		last_stand_fired.emit()
		if net_last_stand_cb.is_valid():
			net_last_stand_cb.call(self)
	# Honor Guard: the guarded column-mate cannot fall below 1.
	# Repeatable (unlike Last Stand) — the flag is re-derived at every board
	# mutation and clears the moment the guard dies. Kill-convention damage
	# (99+) and Poison's direct current_hp writes still land.
	if current_hp <= 0 and amount < 99 and state.hp_floor:
		current_hp = 1
		_spawn_keyword_chip("HELD", Color(1.0, 0.85, 0.20))
	update_stat_display()
	# Absorbed = the life this body actually lost. Reading current_hp AFTER the
	# Last Stand / hp_floor clamps makes those cases honest for free (a Last Stand
	# body at 2 HP taking 6 shows "-1", because that is what it lost). The raw blow
	# still drives the shake — the haymaker was real even if the body was small.
	_spawn_damage_number(hp_before - maxi(current_hp, 0), amount)
	if amount > 0:
		damaged.emit(amount)
	if current_hp <= 0:
		# During a simultaneous clash the death is HELD (see defer_deaths) so this
		# creature still gets its retaliation; Combat._cleanup_dead flushes it after.
		if not defer_deaths:
			try_die()
		else:
			_mark_mortally_struck()
	else:
		_flash_hit()


func take_damage_bypass_armor(amount: int) -> void:
	# Effect-immune: every caller of this path (Thorns recoil, venom) is a keyword
	# effect, never a strike — so it never touches the Body. See take_damage.
	if state.effect_immune:
		return
	# Bypasses Armored, but Shield still absorbs the whole hit and pops.
	# (No bodyguard redirect here: recoil damage — Thorns, venom — belongs to
	# the body that caused it, not its ward.)
	if bool(card_data.get("fortification", false)) and amount >= 99:
		amount = 3
		_spawn_keyword_chip("SIEGE 3", Color(0.94, 0.72, 0.32))
	if state.has_shield and not (spell_pierce_active and is_opponent):
		state.has_shield = false
		_spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0), "shield", true)
		_apply_shield_rage()
		update_stat_display()
		_flash_hit()
		return
	# Mirror take_damage: Berserker's extra_damage ("+1 from all sources") must
	# apply here too, or it's silently lost on Thorns/piercing/poison hits.
	if int(card_data.get("extra_damage", 0)) > 0:
		amount += int(card_data.extra_damage)
	# See take_damage: the numeral prints life actually lost, not the raw blow.
	var hp_before: int = current_hp
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
		_spawn_keyword_chip("LAST STAND",
			Color(1.0, 0.85, 0.20), "last_stand", true)
		_play_last_stand_flare()
		last_stand_fired.emit()
		if net_last_stand_cb.is_valid():
			net_last_stand_cb.call(self)
	# Honor Guard (hp_floor) holds on this path too — see take_damage.
	if current_hp <= 0 and amount < 99 and state.hp_floor:
		current_hp = 1
		_spawn_keyword_chip("HELD", Color(1.0, 0.85, 0.20))
	update_stat_display()
	_spawn_damage_number(hp_before - maxi(current_hp, 0), amount)
	if amount > 0:
		damaged.emit(amount)
	if current_hp <= 0:
		# Held during a simultaneous clash (see defer_deaths / take_damage).
		if not defer_deaths:
			try_die()
		else:
			_mark_mortally_struck()
	else:
		_flash_hit()


# Public death entry point. Gives rescue listeners (Phantom Veil, Reborn) a
# chance to set current_hp back > 0 before _die() runs. Call this anywhere
# you've directly set current_hp <= 0 without going through take_damage —
# e.g. poison kills (Combat.gd:1455/1567).
func try_die() -> void:
	will_die.emit()
	if current_hp > 0:
		update_stat_display()
		# A rescue (Phantom Veil, Reborn) pulled it back — undo the mortal slump
		# so the survivor doesn't stand around in corpse gray.
		_recover_from_mortal_slump()
		return
	_die()


## `costumed` = this keyword states itself ON THE BODY (see _refresh_costumes), so
## the floating chip would be a second channel for one fact. The chronicle entry
## below still lands either way, which is why retiring a chip never loses
## anything — accountability is in the log, attribution is on the token.
func _spawn_keyword_chip(text: String, color: Color, kw_id: String = "",
		costumed: bool = false) -> void:
	# Floats a labeled chip above the card so hidden keyword math (Armored
	# blocking, Last Stand triggering, Piercing carrying) reads on-screen. Routes
	# through Combat.spawn_keyword_callout — a styled pill carrying the keyword's
	# own icon, visually distinct from a bare damage number — when available.
	if static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	# Battle log: keyword math that fires as a chip (SHIELD pop, ARMORED block,
	# LAST STAND, POISON) is exactly what the chronicle should remember.
	if vfx.has_method("log_status"):
		vfx.log_status(self, text)
	if costumed:
		return
	var anchor := global_position + Vector2(size.x * scale.x * 0.5, size.y * scale.y * 0.06)
	if vfx.has_method("spawn_keyword_callout"):
		var icon: Texture2D = GameTheme.get_keyword_icon(kw_id) if kw_id != "" else null
		vfx.spawn_keyword_callout(anchor, text, color, icon)
	else:
		vfx.spawn_floating_number(anchor, text, color, false)


# ─────────────────────────────────────────────────────────────────────────
#  Combat juice — damage numbers, hit flash, death flourish, heal pulse
# ─────────────────────────────────────────────────────────────────────────

func _combat_vfx_target() -> Node:
	# The Combat scene exposes spawn_floating_number(); other scenes (gallery,
	# bake viewport) don't, so we no-op there.
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var scn := tree.current_scene
	if scn != null and scn.has_method("spawn_floating_number"):
		return scn
	return null


## ── FLOAT ANCHORING (2026-07-28) ───────────────────────────────────────────
## Combat.spawn_floating_number rises its numeral by a fixed number of SCREEN
## pixels — 54, or 72 when `big` — over a 0.9 s life. That travel knows nothing
## about how tall the body underneath it is, and a battlefield token is only
## ~136 px tall, so a number spawned at 0.30 of its own card height had climbed
## clear of that card before it faded. The frame capture caught it: at t=454 ms a
## "−1" was floating over a DIFFERENT creature's art, which makes the numeral
## worse than absent — it attributes the damage to the wrong body.
##
## The fix is placement, not duration: 0.9 s is right, so the SPAWN is set low
## enough that the END of the rise lands back on the body that took the blow. The
## numeral now travels from about the belt line to the shoulders and never leaves
## the token's own footprint. These constants must track spawn_floating_number's
## `rise` — they are the one place that knows the coupling.
const FLOAT_RISE := 54.0        # Combat.spawn_floating_number, normal numeral
const FLOAT_RISE_BIG := 72.0    # Combat.spawn_floating_number, `big` numeral
const FLOAT_END_FRAC := 0.16    # where the rise ENDS, as a fraction of card height


## Y offset from this card's top edge at which a float must START so the end of
## its rise still sits on this body. Clamped so a tall hand card can't spawn its
## numeral off the bottom edge and a small token can't spawn it under the seals.
func _float_anchor_y(big: bool) -> float:
	var card_h: float = maxf(size.y * scale.y, 1.0)
	var rise: float = FLOAT_RISE_BIG if big else FLOAT_RISE
	return clampf(card_h * FLOAT_END_FRAC + rise, card_h * 0.30, card_h * 0.84)


## `amount` is the life this body actually LOST — what gets printed. `blow` is the
## raw incoming damage, which may be far larger when the body was too small to
## absorb it. The split matters because what the player READS has to add up
## (see take_damage's OVERKILL HONESTY note) while what the player FEELS should
## still carry the true force of the swing. Defaults to the honest value.
func _spawn_damage_number(amount: int, blow: int = -1) -> void:
	if amount <= 0 or static_display:
		return
	if blow < amount:
		blow = amount
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	# JUICE — scale the number's prominence to the blow so a 1-dmg plink and a
	# 7-dmg haymaker don't read identically. Heavy hits get the "big" treatment
	# (larger font in spawn_floating_number) and a hotter, gold-shifted red.
	# Keyed off the PRINTED value: a big glyph over a small number reads as a
	# mismatch, and overkill's drama belongs to the strike mark, not to inflating
	# a numeral that says 2.
	# Read BEFORE the anchor: a big numeral rises further, so it has to start
	# lower to finish in the same place (see _float_anchor_y).
	var heavy: bool = amount >= 5
	var anchor := global_position + Vector2(size.x * scale.x * 0.5, _float_anchor_y(heavy))
	var col := Color(1.0, 0.38, 0.26) if not heavy else Color(1.0, 0.62, 0.20)
	vfx.spawn_floating_number(anchor, "-%d" % amount, col, heavy)
	# Magnitude-scaled board shake routed through Combat so light chip damage
	# barely ripples while big blows rock the screen. Guarded by has_method so
	# non-combat scenes (gallery/bake) stay silent. Uses the RAW blow — a 9-power
	# swing into a 2 HP body still hit like a 9-power swing.
	if vfx.has_method("creature_hit_feedback"):
		vfx.creature_hit_feedback(blow)


func _spawn_death_burst() -> void:
	# A one-shot particle pop at the dying creature's body — Card2D's own death
	# tween only fades + shrinks, which felt flat against the rest of the juice.
	# Color flavors by the creature's vibe so a skeleton ashes bone-white, an
	# undead ghosts pale green, a fire creature spits embers, etc.; default is
	# dust brown so anything unclassified still gets a body to its exit.
	var vfx := _combat_vfx_target()
	if vfx == null or not vfx.has_method("spawn_spell_burst"):
		return
	var color := Color(0.78, 0.55, 0.32, 0.95)  # default: ash/dust brown
	var id := String(card_data.get("id", ""))
	var name := String(card_data.get("name", "")).to_lower()
	var kw: Array = card_data.get("keywords", [])
	if "bone" in id or "skeleton" in name or "warden_of_graves" in id:
		color = Color(0.92, 0.88, 0.74, 0.95)  # bone white
	elif "ghost" in name or "spirit" in name or "wraith" in name or "vengeful_spirit" in id:
		color = Color(0.70, 0.92, 0.85, 0.95)  # pale green ghost
	elif "fire" in id or "kindling" in id or "blood_pyre" in id or "torchbearer" in id:
		color = Color(1.0, 0.50, 0.18, 0.95)  # ember orange
	elif "demon" in name or "devil" in name or "imp" in id or "vampire" in name:
		color = Color(0.85, 0.18, 0.20, 0.95)  # devil red
	elif "thorn" in id or "sprite" in id or "naga" in id or "hydra" in id:
		color = Color(0.55, 0.85, 0.45, 0.95)  # plant green
	elif "blood" in id or "pyre" in id or kw.has("wither"):
		color = Color(0.78, 0.20, 0.25, 0.95)  # blood red
	var burst_pos := global_position + size * scale * 0.5
	vfx.spawn_spell_burst(burst_pos, color)
	# JUICE — a bigger creature dies bigger. Scale a rising ash/ember burst to
	# the body's max stat (a 1/1 token puffs; a 6/8 bruiser erupts) so death
	# weight reads at a glance. Only when the combat scene exposes the helper.
	if vfx.has_method("spawn_ash_burst"):
		var bulk: int = maxi(int(card_data.get("atk", 1)), int(card_data.get("hp", 1)))
		var ash_amount: int = int(clampf(10.0 + float(bulk) * 2.4, 12.0, 40.0))
		vfx.spawn_ash_burst(burst_pos, color, ash_amount)


func _spawn_atk_change_popup(delta: int) -> void:
	# Floating "+N ATK" / "-N ATK" so silent buffs (Battle Drummer, War Cry,
	# Curse, Steal, Royal Guard's on-hit, Inspire, etc.) read on-screen instead
	# of just nudging the orb numeral. Anchored slightly above and to the left
	# of the card so it doesn't visually fight the damage number (which spawns
	# center).
	if delta == 0 or static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	# Anchored through _float_anchor_y for the same reason as the damage numeral:
	# spawning at 0.12 of the card height meant this one ended its rise a clear
	# 38 px ABOVE the token, over whatever body stood behind it. The x split
	# (left of centre, HP right of centre) is kept — that is what stops a +2/+2
	# from stacking its two floats on one another.
	var anchor := global_position + Vector2(size.x * scale.x * 0.25, _float_anchor_y(false))
	var text: String
	var color: Color
	if delta > 0:
		text = "+%d ATK" % delta
		color = GameTheme.ATK_BUFFED
	else:
		text = "%d ATK" % delta  # delta is already negative
		color = Color(1.0, 0.42, 0.32)
	vfx.spawn_floating_number(anchor, text, color, false)


func _spawn_hp_change_popup(delta: int) -> void:
	# Floating "+N HP" for every HP GAIN — heals, +N/+N buffs, Regenerate ticks,
	# a keystone aura landing. Anchored right-of-centre (mirroring the ATK
	# popup's left) so the two never overlap when a +2/+2 lands both at once,
	# and clear of the damage number that spawns dead centre.
	# Losses are NOT floated: they all run through take_damage /
	# take_damage_bypass_armor, which own the damage number (see
	# update_stat_display).
	if delta <= 0 or static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	# See _spawn_atk_change_popup: same rise, same anchoring rule, mirrored x.
	var anchor := global_position + Vector2(size.x * scale.x * 0.75, _float_anchor_y(false))
	vfx.spawn_floating_number(anchor, "+%d HP" % delta, GameTheme.HEALTH_GREEN, false)


func _punch_seal(lbl: Label) -> void:
	# The wax seal takes the news: a scale punch on the numeral's seal whenever
	# the stat it carries changes (C2). Decorative emphasis — Motion.punch gates
	# Reduce Motion itself, and the NUMBER still changes either way, so the
	# information never depends on the beat. The seal is the label's parent (the
	# same node _set_atk_caret hangs the caret on).
	if static_display or lbl == null or not is_instance_valid(lbl):
		return
	var seal := lbl.get_parent()
	if seal is Control:
		Motion.punch(seal, 1.16)


func show_heal_number(amount: int) -> void:
	# The HEAL beat: a green wash over the body, so a heal reads differently
	# from a generic stat gain. The "+N HP" float is NOT spawned here —
	# update_stat_display owns every stat float by construction (C2), and both
	# call sites refresh the display before calling this, so floating one here
	# too would double-report the same heal.
	if amount <= 0 or static_display:
		return
	var base := modulate
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(base.r * 0.6, base.g * 1.5, base.b * 0.6, base.a), 0.08)
	tw.tween_property(self, "modulate", base, 0.25)


# ── The clash phrase (C5) ──────────────────────────────────────────────
# Strike audio climbs through a round's exchange. Static because the phrase
# belongs to the CLASH, not to any one card — every struck creature reads the
# same rising step. Combat owns the reset (once per round, at the top of the
# round); if it ever stops calling reset_clash_pitch the step just saturates at
# the cap rather than climbing forever, so a missed reset can't shriek.
const CLASH_PITCH_STEP: float = 0.045  # per strike — a shade under a semitone
const CLASH_PITCH_MAX: float = 0.28    # cap ≈ +4 semitones over ~6 strikes
static var _clash_pitch_step: int = 0

static func reset_clash_pitch() -> void:
	_clash_pitch_step = 0


static func _next_clash_pitch() -> float:
	# Static: the phrase is the clash's, not any card's — and it keeps the step
	# testable without standing up a Card2D (which drags CardDB in at compile
	# time, before autoloads exist under --script).
	var p: float = 1.0 + minf(float(_clash_pitch_step) * CLASH_PITCH_STEP, CLASH_PITCH_MAX)
	_clash_pitch_step += 1
	return p


func _flash_hit() -> void:
	if static_display:
		return
	if not _flash_face_hit():
		# Fallback (hand cards, uncached tokens, headless): the historical
		# red-tint punch on modulate. It can only fake red by DARKENING green
		# and blue — modulate multiplies — which is exactly the defect ★4 fixes
		# wherever a baked face exists.
		var base := modulate
		var tw := create_tween()
		tw.tween_property(self, "modulate",
			Color(base.r * 1.8, base.g * 0.5, base.b * 0.45, base.a), Motion.time(0.06))
		tw.tween_property(self, "modulate", base, Motion.time(0.22)).set_ease(Tween.EASE_OUT)
	if AudioBank != null:
		# "hit_creature" is the bespoke creature-impact cue; it falls back to the
		# generic "hit" until clips land (AudioBank.SFX_FALLBACKS). This is the
		# SOLE owner of struck-survivor audio — Combat's clash path plays no hit
		# cue of its own, or every strike would sound twice.
		#
		# The cue RISES through a clash (C5): each successive strike in a round
		# plays a step higher, so a long exchange reads as a building phrase
		# instead of the same thump N times — Balatro's rising per-card scoring
		# note, which is why its chains feel like they're going somewhere. The
		# ±jitter still rides on top so equal steps never sound sequenced.
		# Combat resets the step at each round's start (Card2D.reset_clash_pitch).
		AudioBank.play_sfx("hit_creature", 0.05, 0.0, _next_clash_pitch())


var _baked_face: TextureRect = null
var _gilt_mat: ShaderMaterial = null
var _gilt_tween: Tween = null
# Matched to the hover-exit / put-down settle (0.14 / PUTDOWN_BEAT) so the leaf's
# highlight and the sheet's angle come home together.
const GILT_SETTLE := 0.15

func _apply_gilt_foil() -> void:
	# ★2 — only rares and uncommons carry leaf, and only in the hand. The shine
	# must stay INFORMATION ("this pull is good"), never wallpaper: if every
	# card glinted, a rare would look like a common again, which is the whole
	# defect this fixes. Same reasoning as rarity_reveal's commons no-op.
	_gilt_mat = null
	if _baked_face == null or not is_instance_valid(_baked_face):
		return
	if static_display or gallery_baked_mode:
		return
	if DisplayServer.get_name() == "headless":
		return
	var rarity := String(card_data.get("rarity", ""))
	var strength := 0.0
	if rarity == "rare":
		strength = 1.0
	elif rarity == "uncommon":
		strength = 0.5
	if strength <= 0.0:
		return
	_gilt_mat = Motion.gilt_material(strength)
	_baked_face.material = _gilt_mat


func _sweep_gilt(tilt: float) -> void:
	# Called from the lean driver — the ONLY time the highlight needs to move
	# (gold leaf doesn't shimmer on its own; it catches light when you move it).
	if _gilt_mat != null:
		_gilt_mat.set_shader_parameter("tilt", tilt)


## THE LIGHT HAS TO COME BACK DOWN TOO (2026-08-03).
## `_sweep_gilt` was driven from `_process` and nowhere else, and `_disarm_lean`
## just stopped the process — so the foil froze at whatever angle the cursor left
## it. A rare you hovered and released sat lit from the side, permanently, until
## the next hover; the leaf's whole claim is that it answers the card's ANGLE,
## and a card at rest is not tilted. The card's own rotation is already easing
## home over the settle beat, so the light rides the same beat rather than
## snapping — otherwise the sheet straightens while its highlight teleports.
##
## Not a second writer: `_process` owns the tilt only while `_lean_active`, and
## this tween is created the instant that flag drops and killed the instant it
## comes back up (`_arm_lean`). The windows cannot overlap.
##
## AND THE REST ITSELF MOVES (2026-08-04). Returning the foil at `_disarm_lean`
## covers only the half of the bug that the hand is holding. The foil's rest is
## `_hand_target_rotation`, and `set_hand_target` is that value's ONE writer —
## Combat re-fans on every draw, play, refusal and discard mark, so the angle
## slides out from under a card that is sitting perfectly still. Measured on a
## card that had never been hovered at all: sheet at −0.104 rad, foil at 0.000,
## i.e. `pos` 0.500 against the 0.323 the sheet's angle asks for — 13% of the
## `band`'s 1.35 range, on the outermost cards of every fan in the game. So
## `set_hand_target` re-rests the light over the SAME duration it moves the
## sheet, which is this function's existing argument applied to the other half.
## Not new gilt behaviour (that is R5's territory) — the same rest, arriving.
func _settle_gilt_home(dur: float = GILT_SETTLE) -> void:
	if _gilt_mat == null:
		return
	if _gilt_tween != null and _gilt_tween.is_valid():
		_gilt_tween.kill()
	var rest_tilt: float = _hand_target_rotation
	if UserSettings != null and UserSettings.reduce_motion:
		# Decorative, but the END STATE is not optional — a card left mis-lit is
		# wrong however the player has their settings.
		_sweep_gilt(rest_tilt)
		return
	if not is_inside_tree():
		_sweep_gilt(rest_tilt)
		return
	if dur <= 0.0:
		_sweep_gilt(rest_tilt)
		return
	_gilt_tween = create_tween()
	_gilt_tween.tween_method(_sweep_gilt, float(_gilt_mat.get_shader_parameter("tilt")),
		rest_tilt, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


var _flash_mat: ShaderMaterial = null
var _flash_tween: Tween = null

## THE INK DARKENS AS THE PAPER LIGHTS (2026-07-28 legibility capture, item 4).
## A cached battlefield token carries its WAX SEALS baked into the face texture —
## only the numerals ride on top as live labels (see _build_compact_stat_layer's
## "cached faces already contain the blank seals"). So flashing the face toward
## white took the seals with it, and the capture caught the result at t=958 ms: a
## struck survivor's "7 / 1" rendered near-white ink on a near-white seal at the
## precise instant the new HP is the thing the player needs to read. The blow's
## own feedback erased the blow's own consequence.
##
## The numerals are therefore driven from the SAME tween value as the flash —
## paper up, ink down, one clock — so their contrast cannot drift out of step
## whatever the animation-speed setting does to the timing. The flash keeps its
## full 0.75 strength: this is a contrast fix, not a volume cut.
const FLASH_INK := Color(0.20, 0.17, 0.14, 1.0)


## Applies one point of the flash curve to both halves of the effect.
func _apply_hit_flash(v: float) -> void:
	if _flash_mat != null:
		_flash_mat.set_shader_parameter("flash", v)
	# modulate multiplies, so this darkens the glyph while leaving its black
	# outline black — dark ink + black outline on hot paper reads at any point of
	# the curve. Nothing else writes label modulate, so no state needs restoring
	# beyond the tween's own return to white.
	var ink := Color(1, 1, 1, 1).lerp(FLASH_INK, clampf(v, 0.0, 1.0))
	for node in [_atk_label, _hp_label, _atk_caret]:
		if node != null and is_instance_valid(node):
			node.modulate = ink


func _flash_face_hit() -> bool:
	# ★4 — the sheet takes the blow: a real flash TOWARD hot white on the baked
	# face, instead of a modulate tint that could only darken its way to "red".
	# The ink (live numerals) deliberately does NOT flash — paper catches the
	# light, writing doesn't.
	#
	# Returns false when there's no baked face to shade, so _flash_hit keeps its
	# historical fallback. Never runs while the card is burning: the death shader
	# owns the face's material from _die onward, and re-materialising it here
	# would erase the burn mid-frontier.
	if _compact_face == null or not is_instance_valid(_compact_face) or _dead:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	if _flash_mat == null:
		_flash_mat = Motion.flash_material()
	# Re-arm on the material we own — a card struck twice in a clash must
	# re-flash from full, not stack two tweens onto one parameter.
	if _compact_face.material != _flash_mat:
		_compact_face.material = _flash_mat
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# Re-armed from zero, which also snaps the numerals back to full ink — a card
	# struck twice in one clash must not inherit half a curve.
	_apply_hit_flash(0.0)
	_flash_tween = _compact_face.create_tween()
	# 0.75, not a full wash: at 0.85 a bright card went ghost-white and read as
	# a render error rather than a blow (caught in _shot_burn_seals).
	_flash_tween.tween_method(_apply_hit_flash, 0.0, 0.75, Motion.time(0.05))
	_flash_tween.tween_method(_apply_hit_flash, 0.75, 0.0, Motion.time(0.22)) \
		.set_ease(Tween.EASE_OUT)
	return true


var _mortal_slumped: bool = false
var _mortal_slump_base: Color = Color(1, 1, 1, 1)

func _mark_mortally_struck() -> void:
	# A killed creature's death is HELD during a simultaneous clash (defer_deaths)
	# so it still gets its retaliation — but with no feedback the fatal blow read
	# as a MISS: the card kept idling at 0 HP until the flush, seconds later. Red
	# impact punch settling into a drained corpse-gray slump, held until _die()'s
	# flourish takes over (or a rescue restores the living tint — see try_die).
	if static_display or _mortal_slumped:
		return
	_mortal_slumped = true
	_mortal_slump_base = modulate
	var b := _mortal_slump_base
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(b.r * 1.8, b.g * 0.5, b.b * 0.45, b.a),
		Motion.time(0.06))
	# Deepened 2026-07-29. The clash is now serialized and a full board can hold its
	# corpses for ~10 s before the flush, so "slightly gray" was not enough
	# separation — a shot of the mass grave read as fourteen LIVE cards standing in
	# ranks at 0 HP. Darker and part-transparent so spent bodies visibly RECEDE from
	# the line while still being present (they must be: they still owe retaliation).
	tw.tween_property(self, "modulate", Color(0.30, 0.27, 0.26, b.a * 0.78),
		Motion.time(0.30)).set_ease(Tween.EASE_OUT)


func _recover_from_mortal_slump() -> void:
	if not _mortal_slumped:
		return
	_mortal_slumped = false
	var tw := create_tween()
	tw.tween_property(self, "modulate", _mortal_slump_base, 0.25).set_ease(Tween.EASE_OUT)


func _die() -> void:
	if _dead:
		return
	_dead = true
	destroyed.emit()
	# Skipped when the clash path already sounded "creature_death" at the impact
	# beat (death_cue_played) — the flush is the visual flourish, not a second hit.
	if AudioBank != null and not death_cue_played:
		AudioBank.play_sfx("death")
	# The field arrays are already nulled by the destroyed signal / _cleanup_dead,
	# so the lingering node the flourish animates is invisible to combat logic.
	play_death_flourish()


## THE BODY GOING, WITHOUT THE DEATH (extracted 2026-08-04).
##
## `_die()` is death: it emits `destroyed`, which is what runs on-death dispatch,
## encounter hooks and ally-death passives. A SKIRMISH CLIENT must never do any of
## that — the host resolved it and the client only renders the outcome — so the
## client's despawn path deliberately frees its nodes without emitting.
##
## The consequence was that `_net_despawn_creature` hand-rolled a death animation,
## and the one it hand-rolled was a verbatim copy of the FALLBACK below: the
## shrink-spin-fade that `_play_burn_death` was written to replace, described in its
## own header as "the most generic beat in a game whose whole identity is paper and
## ink". So the writ burned on the host's screen and shrank on the client's — two
## players in one match watching different deaths — and the client also missed the
## death burst and never stopped the clash tweens still writing `position`.
##
## So the FLOURISH is now its own funnel and the two callers share it. Adding a beat
## to a creature's exit belongs here; anything that must only happen on a real death
## stays in `_die`.
func play_death_flourish() -> void:
	if static_display or not is_inside_tree():
		queue_free()
		return
	# Idle bob and the clash choreography both write `position`/`scale`; a body dies
	# mid-lunge on every mutual trade and mid-recoil on nearly every kill, so both
	# have to stop before the exit takes those properties over.
	_idle_bob_enabled = false
	for tw in [_lunge_tween, _lunge_scale_tween, _recoil_tween, _brace_tween,
			_lunge_arc_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_lunge_hold_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	z_index = maxi(z_index, 40)
	_spawn_death_burst()
	if _sacrifice_death:
		# Sacrifice ritual: the body ashes away UPWARD — rises, stretches thin, and
		# burns out to amber. Combat._sacrifice_creature plays the crimson veil,
		# ember burst, and altar shake around it; this is the body dissolving.
		# (Never reached on a skirmish client: sacrifice is host-resolved, so the
		# flag is only ever set on the machine that ran the ritual.)
		var rise := Motion.time(0.6)
		var stw := create_tween()
		stw.set_parallel(true)
		stw.tween_property(self, "position:y", position.y - 48.0, rise).set_ease(Tween.EASE_OUT)
		stw.tween_property(self, "modulate", Color(1.0, 0.55, 0.20, 0.0), rise).set_ease(Tween.EASE_IN)
		stw.tween_property(self, "scale", scale * Vector2(0.85, 1.15), rise).set_ease(Tween.EASE_IN)
		stw.tween_property(self, "rotation", rotation + randf_range(-0.12, 0.12), rise)
		stw.chain().tween_callback(queue_free)
		return
	if _play_burn_death():
		return
	# Fallback flourish — hand cards, uncached compact tokens, headless: fade to
	# a dark red while shrinking + spinning slightly, then free.
	var flourish := Motion.time(0.34)
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(self, "modulate", Color(0.35, 0.08, 0.08, 0.0), flourish).set_ease(Tween.EASE_IN)
	tw2.tween_property(self, "scale", scale * 0.45, flourish).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw2.tween_property(self, "rotation", rotation + randf_range(-0.5, 0.5), flourish)
	tw2.chain().tween_callback(queue_free)


func _play_burn_death() -> bool:
	# ★1 — the writ burns. The parchment catches from below and is eaten upward
	# behind an ember frontier, instead of the old shrink-spin-fade (which was
	# the most generic beat in a game whose whole identity is paper and ink —
	# and whose title is Burning Meadow).
	#
	# Returns false when it can't run (no baked face, headless) so _die falls
	# back to the historical flourish — death must ALWAYS resolve and free.
	#
	# Reduce Motion: NOT gated. Death is informational by the contract — the
	# board must show that this creature is gone — and this replaces an
	# animation that was never gated either. It rides Motion.time() so the
	# animation-speed setting still scales it.
	if _compact_face == null or not is_instance_valid(_compact_face):
		return false
	# The hit flash (★4) and the burn both own the face's material. Death wins:
	# stop the flash before burn_away re-materialises the face, or a strike
	# landing on the same frame would keep driving a parameter on a material
	# that's no longer mounted.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_mat = null
	var burn := Motion.time(0.52)
	var ember_hot := Color(1.0, 0.92, 0.55)
	var ember_cool := Color(1.0, 0.36, 0.07)
	if is_opponent:
		# The foe's writ burns oxblood where yours burns gilt — the same side
		# language the log rims and arsenal chips already speak.
		ember_hot = Color(1.0, 0.74, 0.42)
		ember_cool = Color(0.86, 0.18, 0.10)
	var tw := Motion.burn_away(_compact_face, burn, ember_hot, ember_cool)
	if tw == null:
		return false
	# Card2D is a PanelContainer and paints its OWN panel behind the face. The
	# shader discards consumed pixels, so without this the card burns away to
	# reveal a black rounded rectangle — its own backing board — instead of the
	# battlefield. Strip the panel so the hole is a real hole. (Verified in
	# _shot_card_burn: this is exactly what the first capture showed.)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# The ink goes first: numerals, seals and badges are the least of the sheet
	# and would otherwise hang in the air over a hole. They're siblings of the
	# face, so they can't ride the shader — fade them out ahead of the frontier.
	for child in _compact_root.get_children():
		if child == _compact_face or not (child is CanvasItem):
			continue
		var ink := (child as CanvasItem).create_tween()
		ink.tween_property(child, "modulate:a", 0.0, Motion.time(0.20)) \
			.set_ease(Tween.EASE_IN)
	# Heat lifts the sheet a little as it goes. No spin, no shrink — paper
	# doesn't recoil, it rises and is consumed.
	var lift := create_tween()
	lift.tween_property(self, "position:y", position.y - 14.0, burn) \
		.set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(queue_free)
	# Belt and braces: the burn tween lives on a CHILD node, so anything that
	# frees the face mid-burn would take the queue_free with it and strand a
	# corpse on the board. A death must ALWAYS resolve — this timer is the one
	# guarantee that doesn't depend on the face surviving. (Double queue_free is
	# a safe no-op.)
	get_tree().create_timer(burn + 0.6).timeout.connect(func():
		if is_instance_valid(self):
			queue_free())
	return true


# ═══════════════════════════════════════════
#  HAND POSITIONING + HOVER
# ═══════════════════════════════════════════

func set_hand_target(pos: Vector2, rot: float, scl: Vector2 = Vector2.ONE) -> void:
	_hand_target_position = pos
	_hand_target_rotation = rot
	_hand_target_scale = scl
	# Pivot at bottom-centre of the card. Two reasons: (1) the fan rotation
	# in Combat._layout_hand wants the card's bottom anchored to the arc
	# while the top swings outward — pivot bottom-centre IS that behaviour.
	# (2) hover scale uses the same pivot so the card grows UPWARD from the
	# hand baseline, never sinking below where the bottom orbs sit.
	#
	# Through _repivot_preserving_pose, not a raw write: this line is the first
	# thing a REJECTED card meets (Combat refuses the drop → _layout_hand), and
	# the card is still wearing the drag's centre pivot at scale 0.85. A bare
	# swap teleports the sheet ~22 px up in one frame before the return even
	# starts. The DRAG keeps its own pivot — a reflow that fires mid-drag must
	# not steal it, or the cursor stops tracking the card's middle and the drop
	# point Combat computes drifts off the card. _end_drag hands it back.
	if not _is_being_dragged:
		_repivot_preserving_pose(Vector2(size.x * 0.5, size.y))
	if not _is_hovered and not _is_being_dragged:
		# Smoothly slide to the new slot instead of snapping. This is what makes
		# draws "deal in", plays make the hand close the gap, and discards reflow
		# — all for free, since _layout_hand calls this on every hand change.
		# Hover / drag kill this tween (see _on_mouse_entered / _start_drag) so
		# those interactions stay instant.
		if _hand_tween != null and _hand_tween.is_valid():
			_hand_tween.kill()
		var deal_delay := 0.0
		var deal_pop := false
		if has_meta("hand_deal_delay"):
			deal_delay = float(get_meta("hand_deal_delay"))
			remove_meta("hand_deal_delay")
		if has_meta("hand_deal_pop"):
			deal_pop = bool(get_meta("hand_deal_pop"))
			remove_meta("hand_deal_pop")
		var dur := 0.24 if deal_pop else 0.17
		_hand_tween = create_tween()
		_hand_tween.set_parallel(true)
		_hand_tween.set_trans(Tween.TRANS_CUBIC if deal_pop else Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
		# POSITION is the spring's (▲3); the tween keeps rotation, scale and alpha.
		# A reflow that interrupts another reflow now carries its velocity through
		# instead of restarting from a standstill — which is the case this hand
		# meets constantly (hover, drag, draw, play, discard all relayout it).
		_arm_hand_spring(deal_delay, deal_pop)
		_hand_tween.tween_property(self, "rotation", _hand_target_rotation, dur) \
			.set_delay(deal_delay)
		_hand_tween.tween_property(self, "scale", _hand_target_scale, dur) \
			.set_delay(deal_delay)
		if deal_pop:
			modulate.a = 0.0
			_hand_tween.tween_property(self, "modulate:a", 1.0, 0.16) \
				.set_delay(deal_delay)
		elif modulate.a < 0.999:
			# The deal-in alpha ramp above rides _hand_tween, and hand_deal_pop is
			# one-shot — so a relayout during the deal window (draw bursts, the net
			# pre-deal, hand-count reflows) kills the fade and the replacement tween
			# has no alpha track. The card strands translucent over the dark table,
			# reading as permanently "dimmed". Whenever we own the reflow tween and
			# the card isn't fully opaque, finish the fade.
			_hand_tween.tween_property(self, "modulate:a", 1.0, 0.16)
		# The fan angle just moved, so the leaf's rest moved with it. Guarded on
		# `_lean_active` rather than on the hover/drag flags this branch already
		# tested, because `_lean_active` is the actual authority on who owns the
		# tilt — and it rides `dur` so the light and the sheet arrive together
		# (the same reason _settle_gilt_home tweens instead of snapping). No-ops
		# on commons: _gilt_mat is null unless _apply_gilt_foil built one.
		if not _lean_active:
			_settle_gilt_home(dur)


## Move `pivot_offset` without moving the card on screen.
##
## A Control renders as T(pivot)·R·S·T(-pivot) with `position` added on, so its
## world top-left is `position + pivot - R·S·pivot` — which means changing the
## pivot MOVES the sheet unless the scale is exactly 1 and the rotation exactly
## 0. Neither holds during the play gesture: the drag runs at 0.85 with a live
## lean, and both the hand fan and the return want the bottom-centre pivot back.
## Compensating `position` by the exact delta makes the swap invisible, so the
## only thing the player sees move is the tween that follows.
func _repivot_preserving_pose(new_pivot: Vector2) -> void:
	var d: Vector2 = pivot_offset - new_pivot
	if not d.is_zero_approx():
		# R·S·d — scale then rotate, matching Transform2D.set_rotation_and_scale,
		# which is how Control builds its internal transform.
		position += d - Vector2(d.x * scale.x, d.y * scale.y).rotated(rotation)
	pivot_offset = new_pivot


## THE REFUSAL (2026-08-03). Combat turns a drop down — wrong phase, not enough
## Command, an occupied slot, a Curse, closed ground — and the card has to come
## home. Until now it came home on the PLAIN reflow tween (the refusal paths just
## call `_layout_hand()`), which is the exact motion a card makes when a NEIGHBOUR
## is drawn: a rejection was indistinguishable from a shuffle. That is an
## INFORMATIONAL failure, not a decorative one, so this beat always plays —
## Reduce Motion drops only the head-shake, which is the part a motion-sensitive
## player would actually object to, and keeps the recoil that carries the meaning.
##
## The shape is the house SETTLE (BACK-out) pushed hard against the reflow's flat
## QUAD-out: the sheet is thrown back at the fan, slams past its slot and springs
## up into it. The put-down in `_end_drag` is deliberately the OTHER curve — a
## cancel is the player's decision and must not look like the game saying no.
##
## CONTRACT FOR COMBAT: call `_layout_hand()` FIRST (it computes this card's slot
## into `_hand_target_*`), then `card.play_return_to_hand()`. The beat IS
## `_hand_tween`, so a hover, a fresh grab, or the next reflow all cancel it
## through the paths that already own that tween — no new ownership rules.
##
## DECLARED ROTATION WRITER. This is one of the few functions in the file allowed
## to tween `rotation`, and it is safe for the same reason `_on_mouse_exited` is:
## a refusal can only reach a card whose drag has already ENDED (`_end_drag`
## disarms the lean before `played` is even emitted), so the driver has let go of
## the baton before the tween picks it up. It has to be named in
## tools/_probe_card_play.gd's ROTATION_TWEEN_OWNERS list.
func play_return_to_hand() -> void:
	if static_display or is_on_battlefield or not is_inside_tree():
		return
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	if _grab_tween != null and _grab_tween.is_valid():
		_grab_tween.kill()
	# The card may still be wearing the drag's centre pivot if Combat refused
	# without a reflow in between; either way this lands on the fan's pivot
	# without a jump, and is a no-op once _layout_hand has already done it.
	if not _is_being_dragged:
		_repivot_preserving_pose(Vector2(size.x * 0.5, size.y))
	if _lift_shadow != null and is_instance_valid(_lift_shadow):
		_lift_shadow.modulate.a = 0.0
	_hand_tween = create_tween()
	_hand_tween.set_parallel(true)
	_hand_tween.tween_property(self, "position", _hand_target_position, REFUSAL_BEAT) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hand_tween.tween_property(self, "scale", _hand_target_scale, REFUSAL_BEAT) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if modulate.a < 0.999:
		# Same guard as the reflow above: never strand a card translucent because
		# a refusal killed the tween that owed it the tail of its deal-in fade.
		_hand_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	if UserSettings != null and UserSettings.reduce_motion:
		_hand_tween.tween_property(self, "rotation", _hand_target_rotation,
			REFUSAL_BEAT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return
	# The head-shake, as a damped swing written by ONE owner. `rotation` has a
	# single writer at a time and the lean is already disarmed here (_end_drag
	# calls _disarm_lean before Combat can refuse anything), so the tween owns it.
	# A tween_method rather than three chained tween_propertys because the swing
	# has to land EXACTLY on _hand_target_rotation: sin(TAU · 1.5) is 0 and the
	# (1 - t) damp is 0 at t = 1, so the card cannot end up parked off-angle.
	# Peak deflection is kick · max|sin(t·TAU·1.5)·(1 - t)| = kick · 0.833, so
	# 0.12 rad of kick swings ~5.7° at the top of the shake. Sized against the
	# things it must not be confused with: the whole hand FAN spans 12°, and the
	# drag lean clamps at 20°. It also leads AWAY from the slot the card is
	# heading for, so the shake and the travel read as one movement.
	var kick: float = 0.12
	if position.x > _hand_target_position.x:
		kick = -kick
	var rest_rot: float = _hand_target_rotation
	var swing := func(t: float):
		rotation = rest_rot + sin(t * TAU * 1.5) * kick * (1.0 - t)
	# Bound to a name so the tween call is one plain line — the rotation-owner
	# scan in tools/_probe_card_play.gd matches a tween call and the literal
	# "rotation" on the SAME line, and a lambda that assigns it further down would
	# slip that guard silently, which is worse than tripping it.
	_hand_tween.tween_method(swing, 0.0, 1.0, REFUSAL_BEAT)  # writes "rotation"


## Lazily builds the elevation shadow used by the hand hover-lift: a soft
## wide drop shadow that fades in as the card rises off the table. Sits at
## child index 0 so every layout (chart, baked overlay) renders above it.
func _ensure_lift_shadow() -> void:
	if _lift_shadow != null and is_instance_valid(_lift_shadow):
		return
	_lift_shadow = Control.new()
	_lift_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := Panel.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	# Invisible body, shadow-only — the same trick as the chart layout's
	# seat/glow panels.
	st.bg_color = Color(0, 0, 0, 0.0)
	st.set_corner_radius_all(14)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 26
	st.shadow_offset = Vector2(0, 14)
	body.add_theme_stylebox_override("panel", st)
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 14
	body.offset_right = -14
	body.offset_top = 12
	body.offset_bottom = -4
	_lift_shadow.add_child(body)
	_lift_shadow.modulate.a = 0.0
	add_child(_lift_shadow)
	move_child(_lift_shadow, 0)


## The wax-press landing: the card comes down onto the board and PRESSES —
## quick squash, a radiating impression ring, then a small back-out release.
## Replaces a plain outward scale pop: in the writ fiction, playing a card
## is pressing a seal, not inflating a balloon. Combat calls this at the end
## of _play_landing_pop for both player flights and enemy drop-ins.
##
## ── IT IS ALSO THE SECOND HALF OF THE WRIT'S TURN (2026-08-03) ────────────
## An arced arrival now lands FORESHORTENED — the flight closes the writ toward
## edge-on (Motion.turn_face), deeply for a long deal, barely for a near-slot
## seat. Nothing here had to change to open it out again: this tween interpolates
## from whatever pose the card is in, so a card that lands turned is carried from
## edge-on to the squash and then to rest, which is precisely the second half of
## the turn. That is the whole reason the turn was hung on the flight rather than
## added as its own animation — a flip tween here would be a SECOND writer of
## `scale` in a window this function already owns outright, which is the bug the
## feature was blocked on for a year.
##
## `bite` is how long the squash takes before the seal makes contact. It is a
## parameter rather than a constant because the turn's second half has further to
## travel than a bare 12% squash does: opening from edge-on in 70 ms is a pop-in,
## not a turn. Combat scales it with the same `reach` the close was scaled by and
## passes the SAME number to _play_slot_claim_vfx, so the ground ring stays
## welded to the bite instead of being a second copy of the number that has to be
## kept in step by comment.
func play_wax_press(rest_scale: Vector2 = Vector2.ONE,
		bite: float = PRESS_BITE) -> void:
	if static_display or not is_inside_tree():
		return
	pivot_offset = size * 0.5
	# Reduce Motion: the press is DECORATIVE — the card has already arrived, and
	# THAT is the information — so snap to the resting pose. `enable_idle_bob`
	# must still be called on this path: its first act is
	# _register_battlefield_visuals, and for a player-side card this landing
	# callback is the only in-tree opportunity to join the shared status clock
	# (it was compacted while detached from the hand). Registration is not
	# decorative; the bob itself declines on its own under Reduce Motion.
	if UserSettings != null and UserSettings.reduce_motion:
		scale = rest_scale
		enable_idle_bob()
		return
	var tw := create_tween()
	# THE ARRIVAL IS THE LOUDEST BEAT OF THE GESTURE (2026-08-03). Everything
	# before it is the player's own hand moving; this is the BOARD answering, and
	# it was the quietest thing in the sequence — a 6%/10% squash over 0.07 s, a
	# smaller deflection than the recoil a creature makes when it takes 1 damage.
	# Deepened to a real stamp. It also now rides Motion.time() like every other
	# combat-visible tween in this file: the landing was the one beat that ignored
	# the animation-speed setting, so at Instant the whole clash collapsed around
	# a press still running at full length.
	tw.tween_property(self, "scale",
		Vector2(rest_scale.x * 1.12, rest_scale.y * 0.86), Motion.time(bite)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_spawn_press_ring)
	# Release with the house overshoot, then hand off to the idle bob.
	tw.tween_property(self, "scale", rest_scale, Motion.time(Motion.SETTLE)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if has_method("enable_idle_bob"):
			enable_idle_bob()
	)


## One-shot impression halo for the wax press: a warm gilt outline radiating off
## the card's edge and fading, like the ring a seal leaves in soft wax.
##
## 2026-08-03: this was a hand-rolled ring Panel, which was wrong twice over.
## The house has ONE ring engine (Motion.ring) and hand-rolling one skips the
## headless gate it does for free; worse, a Panel is a CONTROL, and Card2D is a
## PanelContainer — container layout re-fits every Control child on any layout
## pass, so a halo mid-flight could be snapped back to the card rect underneath
## it. Motion.ring draws a Line2D (a Node2D, which containers do not sort), and
## the `oval` key squashes it to this card's aspect so the halo still reads as
## THIS sheet's edge spreading rather than a generic pulse.
func _spawn_press_ring() -> void:
	if not is_inside_tree():
		return
	Motion.ring(self, size * 0.5, Color(0.95, 0.84, 0.58, 0.85), {
		"radius": size.x * 0.5, "start_scale": 1.0, "end_scale": 1.26,
		"duration": 0.30, "scale_time": true,
		"width": 2.0, "width_end": 0.7,
		"oval": Vector2(1.0, size.y / maxf(size.x, 1.0)),
		"z_index": 30,
	})


## True while this card's lunge or hit-recoil tween is mid-flight. The idle bob
## (shared visual tick) checks this and yields position.y to the combat tween so the two
## don't fight — see the note there. Scale-only tweens are intentionally excluded
## (the bob writes position.y, not scale, so they can't conflict).
func _combat_tween_active() -> bool:
	if _lunge_hold_active:
		return true
	if _lunge_tween != null and _lunge_tween.is_valid() and _lunge_tween.is_running():
		return true
	if _recoil_tween != null and _recoil_tween.is_valid() and _recoil_tween.is_running():
		return true
	return false


func play_attack_lunge(strength: float = 1.0) -> void:
	# Quick wind-up → thrust toward the opponent's side → recoil back. Player
	# creatures lunge up, enemy creatures lunge down. The brief anticipation
	# pull-back (away from the target) before the strike makes simultaneous combat
	# read as DISCRETE clashes — you see a creature cock back and snap forward —
	# rather than numbers silently changing. Kept fast so the forward apex still
	# lands near the combat code's LUNGE_APEX (0.09s) impact beat, and position is
	# restored exactly so the slot's CenterContainer layout is unaffected.
	#
	# The idle bob yields position.y for the duration (see _combat_tween_active) so
	# the strike stays perfectly clean instead of fighting the breathe each frame.
	if static_display or not is_inside_tree():
		return
	# A brace may still be easing home — it owns `position` until it isn't, and
	# reading position mid-brace would capture a leaned pose as this tween's
	# "rest" and walk the card out of its slot. See play_defend_brace.
	if _brace_tween != null and _brace_tween.is_valid():
		_brace_tween.kill()
	var dir := 1.0 if is_opponent else -1.0
	var rest := position
	var rest_scale := scale
	pivot_offset = size * 0.5
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	_lunge_tween = create_tween()
	# Anticipation: a small hop backward (away from the foe) — very short so the
	# strike still peaks on time. Durations come from the shared Motion clock
	# (Combat awaits Motion.LUNGE_APEX = anticipation + strike, so the impact
	# beat lands exactly at full extension) and scale with anim_speed.
	_lunge_tween.tween_property(self, "position", rest - Vector2(0, dir * 7.0),
			Motion.time(Motion.LUNGE_ANTICIPATION)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Strike: drive forward into the target. `strength` scales the drive so a
	# heavy blow visibly travels deeper before snapping back (Combat passes
	# _lunge_strength(atk); 1.0 = the historical 26px).
	#
	# EXPO-out, not QUAD-out (2026-07-30, STRIKE_DESIGN §2.2). QUAD-out means the
	# blow is at its SLOWEST when it lands, which is the most common feel error in
	# the medium — the strike decelerates into the target like a cushion. EXPO
	# front-loads the distance so the last ~20ms covers only a few pixels: the
	# card is effectively STOPPED at the contact frame. That reads as an impact
	# instead of an arrival, and it buys a perceived hitstop on every blow for
	# zero milliseconds and no freeze.
	_lunge_tween.tween_property(self, "position", rest + Vector2(0, dir * 26.0 * strength),
			Motion.time(Motion.LUNGE_STRIKE)) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Settle home.
	_lunge_tween.tween_property(self, "position", rest, Motion.time(Motion.LUNGE_SETTLE)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Secondary motion (own tween so it can't perturb the position timing above):
	# a subtle squash-&-stretch — the body stretches along the line of travel as it
	# drives in (weight behind the blow), then settles. Scale is bob-independent so
	# this never fights the breathe, and it complements the defender's recoil squash
	# for a readable, juicy clash.
	if _lunge_scale_tween != null and _lunge_scale_tween.is_valid():
		_lunge_scale_tween.kill()
	_lunge_scale_tween = create_tween()
	var stretch := Vector2(1.0 - 0.04 * strength, 1.0 + 0.07 * strength)
	# Stretch peaks at the apex (anticipation + strike), same clock as position.
	_lunge_scale_tween.tween_property(self, "scale", rest_scale * stretch,
			Motion.time(Motion.LUNGE_APEX)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_scale_tween.tween_property(self, "scale", rest_scale, Motion.time(0.17)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ── THE ARC AND THE ROLL (STRIKE_DESIGN §3) ─────────────────────────────
	# The lunge was a straight vertical translate. Everything in animation says a
	# blow travels an ARC and rotates into it — and `rotation` turns out to be
	# unowned on a battlefield token (the lean driver's only call sites are
	# _start_drag and a hover handler guarded by `if not is_on_battlefield:`;
	# every other writer is an EXIT, and the one arrival writer, Combat's
	# _play_landing_pop, is separated from striking by the MUSTER DELAY — a body
	# that lands in round N cannot swing until N+1).
	#
	# Two axes on different easings is what bends the path: no Bezier, no path
	# object, just longitudinal (EXPO, above) against lateral (SINE) while the
	# roll runs to +0.07. At 0.055 rad the leading corner travels ~27% further
	# than the trailing one, which IS the lever read the material lens wanted
	# without touching pivot_offset (shared by six paths; changing it mid-flight
	# teleports the node by half its size).
	#
	# Lateral sign converges the four lanes INWARD on the seam, so the front
	# reads as a line collapsing on the point of contact rather than four
	# independent twitches. Roll sign flips by side — yours rear up from below,
	# theirs bear down from above — which is a geometric, colourblind-safe side
	# cue. Its own tween, like the scale twin, so it can never perturb the
	# position timing the conductor awaits.
	if _lunge_arc_tween != null and _lunge_arc_tween.is_valid():
		_lunge_arc_tween.kill()
	# Decorative by the contract: under Reduce Motion the strike degrades to the
	# straight vertical lunge, which is a shipped, legible motion — informational
	# content (who swung, how hard) lives in the drive and the numeral, not here.
	var arc: float = 0.0 if (UserSettings != null and UserSettings.reduce_motion) else 1.0
	var lane_sign := signf(1.5 - float(current_lane)) * arc
	if lane_sign == 0.0 and arc != 0.0:
		lane_sign = 1.0
	var rest_x := position.x
	var rest_rot := rotation
	var roll := 0.055 * clampf(strength, 0.6, 1.4) * arc
	_lunge_arc_tween = create_tween()
	_lunge_arc_tween.tween_property(self, "position:x",
			rest_x + lane_sign * 7.0 * strength, Motion.time(Motion.LUNGE_ANTICIPATION)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_lunge_arc_tween.parallel().tween_property(self, "rotation",
			rest_rot - dir * roll, Motion.time(Motion.LUNGE_ANTICIPATION)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_lunge_arc_tween.chain().tween_property(self, "position:x",
			rest_x - lane_sign * 5.0 * strength, Motion.time(Motion.LUNGE_STRIKE)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_lunge_arc_tween.parallel().tween_property(self, "rotation",
			rest_rot + dir * roll * 1.3, Motion.time(Motion.LUNGE_STRIKE)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_arc_tween.chain().tween_property(self, "position:x", rest_x,
			Motion.time(Motion.LUNGE_SETTLE)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The roll comes home 40ms AFTER the position does. That lag is the
	# follow-through — the angle trailing the body is what makes the return read
	# as recovery rather than rewind.
	_lunge_arc_tween.parallel().tween_property(self, "rotation", rest_rot,
			Motion.time(Motion.LUNGE_SETTLE + 0.04)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_play_strike_smear(rest, dir, strength)


## ▲2 — THE SMEAR (docs/TECHNIQUE_HUNT_20260902.md).
##
## In hand-drawn animation a fast move is not drawn sharp on every frame: at peak
## velocity the artist draws ONE elongated, low-contrast frame occupying the whole
## path. The eye reads it as speed. Without it a fast move reads as TELEPORTING —
## which is what a 26 px drive crossed in two frames does.
##
## WHEN, and the doc's own number was wrong. The pitch said t −55 → −22 before
## contact, copied from STRIKE_DESIGN's generic exposure sheet. But the drive is
## **EXPO-out over 90 ms**, which front-loads the distance deliberately (§2.2: the
## card is effectively stopped at the contact frame). Solving it: by t −55 the body
## has already travelled 1 − 2^(−10·0.39) ≈ **93 %** of the way and is in the slow
## tail — smearing there would draw a speed line on a body that has stopped. Peak
## velocity is the FIRST two frames of the drive, so that is where this fires.
## **Read the easing before choosing the frame.**
##
## WHAT, and why it survives §4's arbitration. The smear is the attacker's own
## already-baked face, so it adds **no new actor and no new propositional
## content** — it is the same body rendered with its velocity, the identical
## distinction that lets the buckle survive as "a *transform*, not a drawn line".
## It is also gone before t=0, so it never enters the fused CONTACT window, and
## Slot 1's single travelling mark remains the RubricStroke. It is NOT the
## rejected blade arc: an arc invents a weapon, a smear only draws the body that
## is already moving.
##
## `top_level` is what makes this safe. The ghost is a CHILD of the card — so it
## cannot perturb the slot's CenterContainer layout the way a sibling would, and
## it is freed with the card — while `top_level = true` detaches it from the
## card's transform so it stays put in the world instead of riding along, which
## is the whole difference between a smear and a second card.
##
## Decorative: the lunge itself carries "who swung, how hard" (Tier A), so Reduce
## Motion drops this exactly as it drops the arc and roll above.
func _play_strike_smear(rest: Vector2, dir: float, strength: float) -> void:
	if static_display or not is_inside_tree():
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if DisplayServer.get_name() == "headless":
		return
	var src: TextureRect = _compact_face
	if src == null or not is_instance_valid(src) or src.texture == null:
		src = _baked_face
	if src == null or not is_instance_valid(src) or src.texture == null:
		return
	var tex: Texture2D = src.texture
	var parent := get_parent()
	if parent == null or not (parent is Control):
		return

	await get_tree().create_timer(Motion.time(Motion.LUNGE_ANTICIPATION)).timeout
	# Suspended across a real timer, so everything below may be gone (C19).
	if not is_instance_valid(self) or not is_inside_tree() or _dead:
		return
	# AND `parent` MUST BE RE-VALIDATED, not just `self`. It was captured before
	# the wind-up, and a body can be reparented or freed inside 90 ms — a
	# relocate, a summon reflow, a death sweep. Reading `global_position` off a
	# freed node is a hard error, and it would only ever fire in a WINDOWED
	# session: the smear is disabled headless, so the campaign soak can never
	# see it. Re-read the parent instead of trusting the captured one.
	var host := get_parent()
	if host == null or not is_instance_valid(host) or not (host is Control):
		return
	if host != parent:
		return          # reparented mid-wind-up; `rest` describes the old slot

	# The span the body crosses in those two frames: from the pull-back pose to
	# ~92 % of full extension. Centre the ghost on it.
	var back: float = -dir * 7.0
	var reach: float = dir * 26.0 * strength * 0.92
	var mid_local: Vector2 = rest + Vector2(0, (back + reach) * 0.5)
	# A Sprite2D, NOT a TextureRect, and this is the load-bearing choice.
	#
	# `top_level` does not save a CONTROL child here. It detaches the canvas
	# transform, but a Control is still LAID OUT by its parent: when the card's
	# rect moves, the child re-anchors and the ghost drifts along behind it. It
	# was verified placing correctly at spawn (380, 311.54) and being dragged to
	# (392, 270.29) twelve milliseconds later — riding the card for the rest of
	# the drive, which is the exact second-card look this technique avoids.
	# A Node2D is not laid out by anything, so `top_level` on it means what it says.
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.centered = true
	# NOT a negative z. "Behind the body" and "behind the board" are the same
	# place in a flat z=0 canvas: at -1 the ghost sank under the table plate and
	# rendered nowhere at all. It rides at the body's own z and draws just after
	# it by tree order — which is what every 2D smear does anyway, since at alpha
	# 0.30 a speed line reads as motion whether it is over or under the object.
	ghost.z_index = 0
	ghost.modulate = Color(1.0, 1.0, 1.0, SMEAR_ALPHA)
	add_child(ghost)
	ghost.top_level = true
	# `rest` is a Control `position`, i.e. a TOP-LEFT, and a centred Sprite2D is
	# placed by its MIDDLE — so the half-size that was wrong to subtract earlier is
	# exactly right to add here.
	ghost.global_position = (parent as Control).global_position + mid_local + size * 0.5
	# The face is baked at supersampled resolution (432x332 behind a 200x150
	# token), so bring it back to the body's footprint first, THEN elongate along
	# the line of travel and pinch across it. Volume is roughly preserved, which is
	# what keeps a smear reading as the same object rather than a bigger one.
	var tex_size: Vector2 = tex.get_size()
	var fit := Vector2.ONE
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		fit = size / tex_size
	var stretch := _smear_stretch(reach - back, size.y)
	ghost.scale = Vector2(fit.x * SMEAR_PINCH, fit.y * stretch)

	# Two frames. A smear you can watch is a ghost; the whole technique is that it
	# is gone before the eye resolves it.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(ghost):
		ghost.queue_free()


## THE STRIKE STOP (STRIKE_DESIGN §2.4) — a REAL freeze, not a scheduler wait.
##
## Combat's "hold" was `await _short_pause(...)`, which suspends the COROUTINE
## while every tween keeps playing. So the 186ms comprehension window on a chip
## hit was 186ms of the attacker sliding home over a number that had finished
## rendering on frame one. Nothing was ever held.
##
## This pauses the running tweens instead — the same idiom hold_lunge_apex uses
## for the fight-ending blow, so the lunge stays the sole owner of `position`
## and time simply stops for it. Called on BOTH bodies, because a freeze on the
## attacker alone reads as a stutter and on the defender alone as a hitch; the
## world stopping is what reads as impact.
##
## INFORMATIONAL, and deliberately the opposite call from hold_lunge_apex, which
## gates itself off under Reduce Motion because the verdict banner carries that
## information independently. Here the freeze IS the comprehension window — the
## same reasoning that reclassified ClashLaneFocus and _lane_dwell on 2026-07-28.
## Write that difference down or someone will "fix" it.
func hold_strike_frame(seconds: float) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		return
	var held: Array[Tween] = []
	for tw in [_lunge_tween, _lunge_scale_tween, _lunge_arc_tween, _recoil_tween]:
		if tw != null and tw.is_valid() and tw.is_running():
			tw.pause()
			held.append(tw)
	if held.is_empty():
		return
	get_tree().create_timer(Motion.time(seconds)).timeout.connect(func():
		for tw in held:
			if tw != null and tw.is_valid():
				tw.play())


func hold_lunge_apex(extra: float) -> void:
	# ★8 (docs/ANIMATION_COOL_PITCH_20260717.md §5b): the blow that ends the
	# fight holds the killer at FULL EXTENSION while the world stops. This
	# PAUSES the running lunge tweens rather than adding a second writer on
	# position/scale — the lunge stays the sole owner, time simply stops for it
	# and resumes. Call it right after the lethal damage lands (the strike is
	# just entering its settle phase, so the pause catches peak extension).
	# Decorative emphasis by the reduce-motion contract: the verdict banner
	# carries the information, so Reduce Motion skips the hold entirely.
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if extra <= 0.0 or not is_inside_tree():
		return
	if _lunge_tween == null or not _lunge_tween.is_valid() \
			or not _lunge_tween.is_running():
		return
	_lunge_hold_active = true
	_lunge_tween.pause()
	if _lunge_scale_tween != null and _lunge_scale_tween.is_valid() \
			and _lunge_scale_tween.is_running():
		_lunge_scale_tween.pause()
	# Capture the tweens + a weakref so the resume can't touch a freed card
	# (the scene may fade to GameOver/Reward while the hold is pending).
	var tw_pos := _lunge_tween
	var tw_scale := _lunge_scale_tween
	var me: WeakRef = weakref(self)
	get_tree().create_timer(Motion.time(extra)).timeout.connect(func():
		var live := me.get_ref() as Card2D
		if live != null:
			live._lunge_hold_active = false
		if tw_pos != null and tw_pos.is_valid():
			tw_pos.play()
		if tw_scale != null and tw_scale.is_valid():
			tw_scale.play())


var _lunge_arc_tween: Tween = null
var _brace_tween: Tween = null

## THE BRACE (docs/STRIKE_DESIGN_20260730.md §2.1) — the defender leans INTO the
## blow during the attacker's wind-up.
##
## The clash's wind-up was a monologue: 90ms in which exactly one card moved 7px
## while the body about to be hit sat perfectly inert until after it had been
## hit. That is the mechanical source of the "damage from nowhere" read — only
## one of the two parties in a trade was ever identified before the blow landed.
## This is the cheapest fix in the whole design because it spends NO time: it
## fills a window that already exists.
##
## IT MUST BE HOME BEFORE CONTACT. The lean completes and returns inside
## ~140ms against a LUNGE_APEX of 180, so the card is back at true rest when
## play_hit_recoil (or the counter's play_attack_lunge) captures `position` as
## its own rest. Getting this wrong is the documented drift bug — a tween that
## captures a mid-move point as "rest" walks the card out of its slot and
## compounds over every trade — which is also why both of those functions now
## kill this tween before reading position.
##
## Decorative by the reduce-motion contract: the lunge already says who is
## swinging, and the numeral says what it did.
func play_defend_brace(from_below: bool) -> void:
	if static_display or not is_inside_tree():
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if _brace_tween != null and _brace_tween.is_valid():
		_brace_tween.kill()
	var dir := 1.0 if from_below else -1.0
	var rest := position
	_brace_tween = create_tween()
	# Toward the attacker, not away — a body setting itself, not flinching.
	_brace_tween.tween_property(self, "position", rest + Vector2(0, dir * 4.0),
			Motion.time(0.07)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_brace_tween.tween_property(self, "position", rest, Motion.time(0.07)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func play_hit_recoil(push_down: bool) -> void:
	# The struck creature snaps back along the hit axis (away from the attacker)
	# and pops slightly, then settles — the second half of the "collision" the
	# attacker's lunge starts. Mirrors the lunge's position-tween approach so it
	# coexists with idle bob the same proven way; restores to the captured rest.
	if static_display or not is_inside_tree():
		return
	# Same single-writer guard as play_attack_lunge — see play_defend_brace. The
	# arc tween owns position:x and rotation, so it must go too or it will fight
	# the recoil for the same node.
	if _brace_tween != null and _brace_tween.is_valid():
		_brace_tween.kill()
	if _lunge_arc_tween != null and _lunge_arc_tween.is_valid():
		_lunge_arc_tween.kill()
	var dir := 1.0 if push_down else -1.0
	var rest := position
	var rest_scale := scale
	pivot_offset = size * 0.5
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = create_tween()
	_recoil_tween.set_parallel(true)
	# Shove away from the attacker, then ease home. Same shared clock as the
	# lunge so recoil scales with anim_speed in step with the pacing pauses.
	_recoil_tween.tween_property(self, "position", rest + Vector2(0, dir * 13.0),
			Motion.time(Motion.RECOIL_SHOVE)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(self, "position", rest,
			Motion.time(Motion.RECOIL_SETTLE)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Quick scale punch for the impact pop (scale isn't touched by idle bob).
	_recoil_tween.tween_property(self, "scale", rest_scale * Vector2(1.12, 0.9),
			Motion.time(Motion.RECOIL_SHOVE)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(self, "scale", rest_scale, Motion.time(0.20)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_last_stand_flare() -> void:
	# A bright heroic flare the instant Last Stand saves the creature at 1 HP.
	# White overbright flash + a slow scale pulse so the clutch survival reads.
	if static_display or not is_inside_tree():
		return
	var base := modulate
	var rest_scale := scale
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.9, 1.8, 1.3, base.a), 0.08) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", rest_scale * 1.18, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "modulate", base, 0.42).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", rest_scale, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


var _danger_tween: Tween = null
var _danger_overlay: Control = null

func set_danger_marked(on: bool, amount: int = 0) -> void:
	# Persistent danger mark: a bright crimson ring around the creature PLUS a
	# high-contrast badge above it showing the HP it will lose to the boss's
	# start-of-round passive. The badge (bold text + heavy dark outline) is what
	# makes it read against the red board. Pure overlay children with their own
	# z_index — they never touch the card's size / slot, so they can't fight the
	# lane container or the idle bob.
	if static_display:
		return
	if on:
		if is_instance_valid(_danger_overlay):
			return
		var ov := Control.new()
		ov.name = "DangerMark"
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.z_index = 7
		add_child(ov)
		var ring := Panel.new()
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.55, 0.04, 0.03, 0.0)
		sb.set_border_width_all(4)
		sb.border_color = Color(1.0, 0.26, 0.18)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(1.0, 0.18, 0.10, 0.6)
		sb.shadow_size = 11
		ring.add_theme_stylebox_override("panel", sb)
		ov.add_child(ring)
		var badge := Label.new()
		badge.text = ("-%d" % amount) if amount > 0 else "!"
		badge.add_theme_font_size_override("font_size", 17)
		badge.add_theme_color_override("font_color", Color(1.0, 0.52, 0.40))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.96))
		badge.add_theme_constant_override("outline_size", 6)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.set_anchors_preset(Control.PRESET_TOP_WIDE)
		badge.offset_top = -26
		badge.offset_bottom = -4
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.add_child(badge)
		_danger_overlay = ov
		if UserSettings.reduce_motion:
			ov.modulate.a = 1.0
		else:
			var tw := create_tween().set_loops()
			tw.tween_property(ov, "modulate:a", 0.5, 0.55).set_trans(Tween.TRANS_SINE)
			tw.tween_property(ov, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
			_danger_tween = tw
	else:
		if _danger_tween != null:
			_danger_tween.kill()
			_danger_tween = null
		if is_instance_valid(_danger_overlay):
			_danger_overlay.queue_free()
			_danger_overlay = null


var _threat_flagged: bool = false
var _threat_tween: Tween = null
var _threat_overlay: Control = null
var _threat_dmg_label: Label = null

func set_threat_flagged(on: bool, damage: int = 0) -> void:
	# JUICE — a pulsing crimson outline on enemy attackers that pose an immediate
	# threat (will smash the player's face this round, or swing a heavy blow).
	# Lets the player SEE danger instead of reading it out of the numbers. This
	# is intentionally distinct from set_danger_marked (boss start-of-round
	# passive, which carries a "-N" badge) — threat flags are a lighter, badge-
	# less ring and use their own overlay so the two can coexist. Idempotent.
	if static_display:
		return
	# If a boss danger-mark ring is already on this creature, don't stack a second
	# ring — the danger mark (with its "-N" badge) is the stronger read. Clear any
	# existing threat ring so the danger mark cleanly supersedes it.
	if on and is_instance_valid(_danger_overlay):
		if _threat_flagged:
			set_threat_flagged(false)
		return
	if on == _threat_flagged:
		return
	_threat_flagged = on
	if on:
		if not is_instance_valid(_threat_overlay):
			var ov := Control.new()
			ov.name = "ThreatFlag"
			ov.set_anchors_preset(Control.PRESET_FULL_RECT)
			ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ov.z_index = 6  # below DangerMark (7) so a boss badge still reads on top
			add_child(ov)
			# Dark keyline UNDER the crimson ring. Warm fights (infernal grade,
			# red-lit paintings) swallow a bare red border into the art — the
			# dark separation is what keeps the flag legible on any painting,
			# instead of stacking even more red on red.
			var keyline := Panel.new()
			keyline.set_anchors_preset(Control.PRESET_FULL_RECT)
			keyline.offset_left = -1
			keyline.offset_top = -1
			keyline.offset_right = 1
			keyline.offset_bottom = 1
			keyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ksb := StyleBoxFlat.new()
			ksb.draw_center = false
			ksb.set_border_width_all(5)
			ksb.border_color = Color(0.06, 0.02, 0.02, 0.85)
			ksb.set_corner_radius_all(12)
			keyline.add_theme_stylebox_override("panel", ksb)
			ov.add_child(keyline)
			var ring := Panel.new()
			ring.set_anchors_preset(Control.PRESET_FULL_RECT)
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.55, 0.05, 0.04, 0.0)
			sb.set_border_width_all(3)
			sb.border_color = Color(1.0, 0.30, 0.22)
			sb.set_corner_radius_all(10)
			sb.shadow_color = Color(1.0, 0.22, 0.14, 0.38)
			sb.shadow_size = 5
			ring.add_theme_stylebox_override("panel", sb)
			ov.add_child(ring)
			# Shape AND number, not just hue: a danger chip at the top edge with a
			# sword glyph + the predicted hit. Dark fill with a warning-amber edge
			# so it reads on ANY mood grade (infernal red, noir, frost) — a red-on-
			# red board can't swallow a near-black chip with a bright numeral.
			var badge := Panel.new()
			badge.anchor_left = 0.5
			badge.anchor_right = 0.5
			badge.anchor_top = 0.0
			badge.anchor_bottom = 0.0
			badge.offset_left = -23
			badge.offset_right = 23
			badge.offset_top = -12
			badge.offset_bottom = 14
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Color(0.08, 0.03, 0.025, 0.97)
			bsb.border_color = Color(1.0, 0.55, 0.25, 0.96)
			bsb.set_border_width_all(2)
			bsb.set_corner_radius_all(8)
			bsb.shadow_color = Color(0, 0, 0, 0.55)
			bsb.shadow_size = 3
			badge.add_theme_stylebox_override("panel", bsb)
			ov.add_child(badge)
			if GameTheme.tex_icon_sword != null:
				var sw := TextureRect.new()
				sw.texture = GameTheme.tex_icon_sword
				sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				sw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				sw.anchor_left = 0.0
				sw.anchor_right = 0.0
				sw.anchor_top = 0.0
				sw.anchor_bottom = 1.0
				sw.offset_left = 4
				sw.offset_right = 22
				sw.offset_top = 3
				sw.offset_bottom = -3
				sw.modulate = Color(1.0, 0.62, 0.42)
				sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
				badge.add_child(sw)
			# The predicted hit — bold and bright, updated on every refresh below.
			var dmg_lbl := Label.new()
			dmg_lbl.anchor_left = 0.0
			dmg_lbl.anchor_right = 1.0
			dmg_lbl.anchor_top = 0.0
			dmg_lbl.anchor_bottom = 1.0
			dmg_lbl.offset_left = 20
			dmg_lbl.offset_right = -3
			dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dmg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dmg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if GameTheme.font_stat != null:
				dmg_lbl.add_theme_font_override("font", GameTheme.font_stat)
			dmg_lbl.add_theme_font_size_override("font_size", 17)
			dmg_lbl.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
			dmg_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
			dmg_lbl.add_theme_constant_override("outline_size", 4)
			badge.add_child(dmg_lbl)
			_threat_dmg_label = dmg_lbl
			_threat_overlay = ov
		_threat_overlay.visible = true
		# Refresh the predicted-hit numeral each time the flag is (re)applied — the
		# cached overlay otherwise keeps a stale number when the attacker's ATK changes.
		if is_instance_valid(_threat_dmg_label):
			if damage > 0:
				_threat_dmg_label.text = str(damage)
				_threat_dmg_label.visible = true
			else:
				_threat_dmg_label.visible = false
		if _threat_tween != null and _threat_tween.is_valid():
			_threat_tween.kill()
			_threat_tween = null
		if UserSettings.reduce_motion:
			# Reduce Motion: keep the threat overlay visible (informational) but
			# hold it steady — the alpha oscillation is the decorative part.
			_threat_overlay.modulate.a = 1.0
		else:
			# Gentler pulse floor — the old 0.35 trough strobed against warm art.
			_threat_tween = create_tween().set_loops()
			_threat_tween.tween_property(_threat_overlay, "modulate:a", 0.55, 0.50).set_trans(Tween.TRANS_SINE)
			_threat_tween.tween_property(_threat_overlay, "modulate:a", 1.0, 0.50).set_trans(Tween.TRANS_SINE)
	else:
		if _threat_tween != null:
			_threat_tween.kill()
			_threat_tween = null
		if is_instance_valid(_threat_overlay):
			_threat_overlay.visible = false


func mark_sacrifice_death() -> void:
	_sacrifice_death = true


var _idle_bob_enabled: bool = false
var _bob_time: float = 0.0
var _bob_phase: float = 0.0
var _bob_base_y: float = 0.0
var _bob_amplitude: float = 3.0
var _bob_freq: float = 1.6


func _register_battlefield_visuals() -> void:
	# Compact static bakes/previews deliberately stay inert. Real battlefield
	# cards register automatically, including compact cards hosted outside Combat
	# by focused probes or future board-like scenes.
	if static_display or not compact_mode or not is_on_battlefield \
			or not is_inside_tree():
		return
	var kept: Array = []
	var already_registered := false
	for ref_variant in _battlefield_visual_refs:
		var ref = ref_variant as WeakRef
		var card = ref.get_ref() if ref != null else null
		if card == null or not is_instance_valid(card):
			continue
		kept.append(ref)
		if card == self:
			already_registered = true
	_battlefield_visual_refs = kept
	if not already_registered:
		_battlefield_visual_refs.append(weakref(self))
	# Card2D no longer owns a per-instance _process loop. Explicitly turn off any
	# stale process flag left by a layout built before this card joined the clock.
	set_process(false)
	var driver = _battlefield_visual_driver.get_ref() \
		if _battlefield_visual_driver != null else null
	if driver == null or not is_instance_valid(driver) \
			or not driver.is_inside_tree() or driver.is_queued_for_deletion():
		_become_battlefield_visual_driver()


func _become_battlefield_visual_driver() -> void:
	if not is_inside_tree() or is_queued_for_deletion() \
			or static_display or not compact_mode or not is_on_battlefield:
		return
	_battlefield_visual_driver = weakref(self)
	if _battlefield_visual_timer != null \
			and is_instance_valid(_battlefield_visual_timer):
		_battlefield_visual_timer.stop()
		_battlefield_visual_timer.queue_free()
	_battlefield_visual_timer = Timer.new()
	_battlefield_visual_timer.name = "BattlefieldVisualClock"
	_battlefield_visual_timer.wait_time = BATTLEFIELD_VISUAL_TICK_SEC
	_battlefield_visual_timer.one_shot = false
	_battlefield_visual_timer.timeout.connect(_dispatch_battlefield_visual_tick)
	add_child(_battlefield_visual_timer)
	_battlefield_visual_timer.start()


func _unregister_battlefield_visuals() -> void:
	var kept: Array = []
	for ref_variant in _battlefield_visual_refs:
		var ref = ref_variant as WeakRef
		var card = ref.get_ref() if ref != null else null
		if card != null and is_instance_valid(card) and card != self:
			kept.append(ref)
	_battlefield_visual_refs = kept
	var driver = _battlefield_visual_driver.get_ref() \
		if _battlefield_visual_driver != null else null
	if driver != self:
		return
	_battlefield_visual_driver = null
	if _battlefield_visual_timer != null \
			and is_instance_valid(_battlefield_visual_timer):
		_battlefield_visual_timer.stop()
		# During PREDELETE the timer is already leaving with its owner. Outside that
		# path (e.g. compact mode disabled), release it explicitly.
		if not is_queued_for_deletion():
			_battlefield_visual_timer.queue_free()
	_battlefield_visual_timer = null
	_promote_battlefield_visual_driver()


func _promote_battlefield_visual_driver() -> void:
	for ref_variant in _battlefield_visual_refs:
		var ref = ref_variant as WeakRef
		var card = ref.get_ref() if ref != null else null
		if card == null or not is_instance_valid(card) \
				or not card.is_inside_tree() or card.is_queued_for_deletion():
			continue
		if card.static_display or not card.compact_mode or not card.is_on_battlefield:
			continue
		card._become_battlefield_visual_driver()
		return


func _dispatch_battlefield_visual_tick() -> void:
	var kept: Array = []
	var driver_survives := false
	for ref_variant in _battlefield_visual_refs:
		var ref = ref_variant as WeakRef
		var card = ref.get_ref() if ref != null else null
		if card == null or not is_instance_valid(card) \
				or not card.is_inside_tree() or card.is_queued_for_deletion():
			continue
		if card.static_display or not card.compact_mode or not card.is_on_battlefield:
			card._idle_bob_enabled = false
			continue
		kept.append(ref)
		driver_survives = driver_survives or card == self
		card._battlefield_visual_tick(BATTLEFIELD_VISUAL_TICK_SEC)
	_battlefield_visual_refs = kept
	if driver_survives:
		return
	# A card can leave battlefield mode without being freed. Hand the single clock
	# over immediately so the remaining board never loses its status fallback.
	_battlefield_visual_driver = null
	if _battlefield_visual_timer != null \
			and is_instance_valid(_battlefield_visual_timer):
		_battlefield_visual_timer.stop()
		_battlefield_visual_timer.queue_free()
	_battlefield_visual_timer = null
	_promote_battlefield_visual_driver()


func enable_idle_bob() -> void:
	# Battlefield-only subtle breathing/bob. Each card gets a randomized phase so
	# the board doesn't move in lockstep — feels like several creatures alive on
	# their own rhythms. The container that holds the card (CenterContainer in
	# the slot cell) doesn't re-layout unless children change, so writing
	# position.y on each shared visual tick sticks.
	# Register BEFORE Reduce Motion exits. Player cards are compacted while
	# detached from the hand tree, so their layout-time registration cannot take;
	# the post-seat landing callback is the first in-tree opportunity to join the
	# shared status clock even when the decorative bob itself stays disabled.
	_register_battlefield_visuals()
	if _idle_bob_enabled or static_display:
		return
	if UserSettings.reduce_motion:
		# Reduce Motion: the idle breathing bob is purely decorative — never start it.
		return
	if not is_on_battlefield:
		return
	# Never anchor the bob while this card is lifted for a reposition: position.y is
	# then a transient drag value (in the hand layer's space, not the slot cell's),
	# so capturing it as the base would freeze the card off its slot when it lands.
	# The placement (play_wax_press / Combat re-anchor) arms the bob afterwards.
	if _field_grabbing or _field_lifted:
		return
	_idle_bob_enabled = true
	_bob_phase = randf_range(0.0, TAU)
	_bob_freq = 1.4 + randf_range(-0.3, 0.5)
	_bob_amplitude = 2.5 + randf_range(-0.5, 1.5)
	_bob_base_y = position.y


func _battlefield_visual_tick(delta: float) -> void:
	# Live status rail fallback poll: a cheap signature diff 4x/sec catches the
	# keyword/status mutation sites that don't route through update_stat_display.
	# All compact cards reach this method from one shared timer callback.
	if is_on_battlefield and _compact_root != null:
		_status_poll_accum += delta
		if _status_poll_accum >= 0.25:
			_status_poll_accum = 0.0
			_refresh_status_rail()
	if not _idle_bob_enabled:
		return
	# Field repositioning owns position.y while a board creature is lifted — the bob
	# must NOT write it then or it pins the card to its anchor Y while only X tracks
	# the cursor (that was the "moves jump to a random place" multiplayer bug).
	if _is_being_dragged or _field_grabbing:
		return
	# A lunge or hit-recoil tween owns position.y for its whole duration. If the
	# idle bob also writes position.y every frame the two fight, superimposing a
	# tremor on the strike (the "not quite buttery" combat motion). Yield to the
	# combat tween; _bob_time is frozen while we skip (it advances below this
	# guard), so when the tween finishes the breathe resumes exactly where it
	# paused — seamless, no pop.
	if _combat_tween_active():
		return
	if not is_on_battlefield:
		# Card just left the battlefield — stop bobbing.
		_idle_bob_enabled = false
		return
	_bob_time += delta
	position.y = _bob_base_y + sin(_bob_time * _bob_freq + _bob_phase) * _bob_amplitude


## Re-arm the idle bob one frame from now, after the slot cell's CenterContainer
## has re-centered this card. Combat calls this for placements that don't run a
## landing pop (e.g. a returned/cancelled reposition); the landing pop re-arms the
## bob itself. The bob owns position.y, so its base must be re-captured from the
## freshly centered position or the card freezes off-slot.
func rearm_idle_bob_next_frame() -> void:
	if static_display or not is_on_battlefield:
		return
	_idle_bob_enabled = false
	await get_tree().process_frame
	if not is_inside_tree() or not is_on_battlefield:
		return
	enable_idle_bob()


## PARCHMENT OUT OF THE LAMPLIGHT GOES BROWNER, NEVER BLUER (2026-08-04, ✦4).
##
## Measured on the worst-case art the old header names — Inferno, at the fan's
## rest scale, mean over the mounted art plate:
##
##   affordable            r−b +0.307   HSV S 0.634   luma 0.306
##   the old blue-grey     r−b +0.052   HSV S 0.345   luma 0.219
##   this wash             r−b +0.131   HSV S 0.405   luma 0.236
##
## The old pair was the ONE surface in the card's whole material kit with
## INVERTED hue order (modulate r−b −0.10, veil −0.09) against `WritLeaf.paper`
## at +0.18 and the gilt shader's measured parchment at +0.21 — and on cooler
## art it dragged the entire sheet across zero: Hexwright measured −0.053 and
## Frost Bolt −0.029, which is a document turning into a greyed-out UI control.
## Both constants are warm-ordered now (+0.04 and +0.09) and no card in the study
## composites below +0.05.
##
## THE VEIL IS LIGHTER THAN THE FACE IT DARKENS, AND THAT IS THE POINT. Darkening
## is the MODULATE's job. The veil's job is to collapse varied art toward one
## flat tone, and the only way it can do that is by lifting the shadows — and
## because `modulate` is hierarchical it multiplies the veil too, so this tan
## renders at roughly (0.35, 0.32, 0.28) on screen. Do NOT "fix" the constant by
## darkening it to match what you see: a dark warm veil preserves the art's own
## channel ratios and stops desaturating altogether (one measured in the study
## left Inferno at S 0.616 against the affordable card's 0.634 — no flattening
## at all, which is exactly the failure the veil was added to prevent).
##
## THE HONEST COST, since the header was right to demand a photograph. A warm
## wash cannot flatten warm art as hard as a blue-grey one, because blue-grey
## works by fighting the flames' own hue; Inferno keeps S 0.405 here against
## 0.345 before. What pays for it is that nothing else moved: the darkening is
## unchanged (whole-card luma 0.474 affordable → 0.280 before → 0.287 now) and
## the rules well keeps 84% of the old ink/paper separation. Flatter candidates
## were built and rejected on that last number — they bought 0.03 more
## desaturation with a third of the card's readable text, and an unplayable card
## is still a card the player has to read. The state is carried by luma and
## flatness, never by hue, which is what keeps it honest under `colorblind_mode`.
const UNPLAYABLE_DIM := Color(0.56, 0.545, 0.52, 1.0)
const UNPLAYABLE_VEIL := Color(0.62, 0.58, 0.53, 0.45)


func set_affordable(can_afford: bool) -> void:
	# Slay-the-Spire / Hearthstone readability: a card the current Command pool
	# can't pay for reads as clearly DISABLED — a darken PLUS a desaturating veil
	# that drains the art's colour. Darkening alone left vivid art (e.g. Inferno's
	# flames) looking merely "a bit dark" next to its neighbours; the veil flattens
	# the colour so unplayable cards are unmistakable at a glance.
	# Skip battlefield/static cards (no cost concept) and mid-drag (the drag owns
	# modulate during the drag → release flow).
	if is_on_battlefield or static_display:
		return
	if _is_being_dragged:
		return
	_affordable = can_afford
	if not can_afford:
		_ensure_unplayable_veil()
	if _unplayable_veil != null and is_instance_valid(_unplayable_veil):
		_unplayable_veil.visible = not can_afford
	_apply_hand_tint()


## THE RESTING TINT OF A HAND CARD HAS EXACTLY ONE WRITER (2026-08-04).
## `modulate` was claimed independently by affordability and by the discard mark,
## and neither read the other, so whichever wrote last won. Both directions were
## live and both were caught by driving the real methods:
##   · mark a card, then let ANY `_update_hud` fire — `_refresh_hand_affordability`
##     wrote `Color.WHITE` over the mark's dim (0.80 → 1.00) and the sunk card
##     came back to full brightness wearing only its band;
##   · un-mark an unaffordable card — `set_discard_marked(false)` wrote
##     `Color.WHITE` while the veil stayed visible (0.60 → 1.00, veil on), which
##     is the worse of the two now that the veil's own job is flattening rather
##     than darkening: without its modulate the wash nearly disappears and an
##     unplayable card reads as playable. `_on_card_dismiss_requested` calls
##     `_layout_hand` and not `_refresh_hand_affordability`, so nothing repaired
##     it until the next HUD refresh.
## Unaffordable outranks marked because it is the INFORMATIONAL half — the mark
## already prints its own band across the sheet, and it is the player's own
## decision, while "you cannot pay for this" is the game refusing.
func _apply_hand_tint() -> void:
	if not _affordable:
		modulate = UNPLAYABLE_DIM
	elif marked_for_discard:
		modulate = DISCARD_DIM
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)


func _ensure_unplayable_veil() -> void:
	# Full-rect + mouse-ignore so it never eats input; z_index 5 sits above the
	# card face but below the battlefield threat flag (6). See UNPLAYABLE_VEIL
	# for why the constant is lighter than the result it produces.
	if _unplayable_veil != null and is_instance_valid(_unplayable_veil):
		return
	var veil := ColorRect.new()
	veil.color = UNPLAYABLE_VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 5
	add_child(veil)
	_unplayable_veil = veil


func set_display_cost(effective_cost: int) -> void:
	# Hearthstone convention: the cost orb shows the actual mana cost to play
	# this card RIGHT NOW, with color encoding whether it differs from the
	# printed base cost:
	#   green = cheaper than printed (Ember Crown free spell, Ironclad discount)
	#   red   = more expensive than printed (Taxed mutator)
	#   white = matches printed
	# This is the single fix for "Fireball says cost 1 but the game won't let
	# me play it" — players can now see the real cost on the orb itself.
	if is_on_battlefield or static_display:
		return
	if _cost_label == null:
		return
	_cost_label.text = str(effective_cost)
	var base_cost: int = int(card_data.get("cost", 0))
	if effective_cost < base_cost:
		_cost_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.50))
	elif effective_cost > base_cost:
		_cost_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	else:
		_cost_label.remove_theme_color_override("font_color")


func play_floop_pulse() -> void:
	# Golden flash + small scale punch when a floop ability resolves on this card.
	# Lets the player track which creature just acted in a busy board state.
	if static_display or not is_inside_tree():
		return
	if AudioBank != null:
		AudioBank.play_sfx("floop")
	var base := modulate
	var rest_scale := scale
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate",
		Color(min(base.r * 1.4, 1.0), min(base.g * 1.25, 1.0), base.b * 0.55, base.a), 0.10)
	tw.tween_property(self, "scale", rest_scale * 1.12, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "modulate", base, 0.28) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", rest_scale, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_mouse_entered() -> void:
	if _is_being_dragged or _any_card_dragging:
		return
	_is_hovered = true
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_set_border_color(GameTheme.GILT_BRIGHT)
	if not is_on_battlefield:
		z_index = 10
		# Hover-lift: a fast tween instead of a snap — still feels instant at
		# 0.11s, but the card visibly RISES off the table, and the elevation
		# shadow deepening underneath sells the lift. Cubic-out so it leads
		# with speed and lands soft.
		_ensure_lift_shadow()
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = create_tween().set_parallel(true)
		_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_hover_tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.11)
		# Rotation is NOT tweened here: the lean (C1) owns it while hovered and
		# damps the fan angle out toward the cursor tilt, which subsumes the old
		# "straighten to 0" beat. Reduce Motion doesn't arm the lean, so restore
		# the historical straighten in that case — the card must not sit fanned
		# under a hover with nothing to level it.
		if _lean_can_arm():
			_arm_lean()
		else:
			_hover_tween.tween_property(self, "rotation", 0.0, 0.11)
		# -96 tracks Combat._layout_hand's PEEK 92 (was -80 at PEEK 76): the
		# resting fan tucked 16px lower, so the lift grew 16px to keep the
		# hovered pose at the same screen height.
		_hover_tween.tween_property(self, "position",
			_hand_target_position + Vector2(0, -96), 0.11)
		_hover_tween.tween_property(_lift_shadow, "modulate:a", 1.0, 0.13)
		# Hover killed _hand_tween above — if that tween still owed this card the
		# tail of its deal-in fade, finish it here so the lifted card is always
		# fully opaque and readable.
		if modulate.a < 0.999:
			_hover_tween.tween_property(self, "modulate:a", 1.0, 0.11)
	# Honour the tooltip delay setting — 0 = show instantly. The lift/scale
	# still happens immediately; only the detail panel is deferred so brief
	# cursor sweeps don't spam popup creation+free.
	var delay := 0.0
	if UserSettings != null:
		delay = UserSettings.tooltip_delay
	if delay <= 0.001:
		_show_detail_panel()
	else:
		# Wait `delay` seconds then check we're still hovered before showing.
		var t := get_tree().create_timer(delay)
		await t.timeout
		if _is_hovered and is_inside_tree() and not _is_being_dragged:
			_show_detail_panel()


func _on_mouse_exited() -> void:
	if _is_being_dragged:
		return
	_is_hovered = false
	# Hand `rotation` back to the settle tween below, which carries it from
	# wherever the tilt left it home to _hand_target_rotation (C1).
	_disarm_lean()
	# Floop is hard-gated dead code (see update_floop_display, P1#10): the old
	# will_floop / has_floop() cyan-border branches here are removed so a stray
	# floop key can never paint a cyan affordance on hover-out. Always restore
	# the default frame tint.
	_set_border_color(_get_default_frame_tint())
	if not is_on_battlefield:
		z_index = 0
		# Settle back to the resting hand pose set by set_hand_target. A
		# touch slower than the rise — picking up is eager, putting down is
		# gentle. If the hand re-lays-out mid-settle, set_hand_target's own
		# tween is created later and wins per-property, so they can't fight.
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = create_tween().set_parallel(true)
		_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_hover_tween.tween_property(self, "scale", _hand_target_scale, 0.14)
		_hover_tween.tween_property(self, "rotation", _hand_target_rotation, 0.14)
		_hover_tween.tween_property(self, "position", _hand_target_position, 0.14)
		if _lift_shadow != null and is_instance_valid(_lift_shadow):
			_hover_tween.tween_property(_lift_shadow, "modulate:a", 0.0, 0.12)
	_hide_detail_panel()


func _get_default_frame_tint() -> Color:
	return _default_border_color


func _set_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


# ═══════════════════════════════════════════
#  DRAG TO PLAY
# ═══════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_on_battlefield and not is_opponent and is_creature() \
					and not has_keyword("structure") \
					and field_move_dropped.get_connections().size() > 0:
				# Friendly board creature whose move-drag is wired by Combat →
				# begin a potential move. A press that releases without travelling
				# stays a floop click (below). The connection check means creatures
				# Combat didn't wire (e.g. tokens) fall through instead of lifting
				# off into a handler-less drag.
				_begin_field_grab(event.global_position)
			elif not is_on_battlefield:
				_start_drag(event.global_position)
		else:
			if _field_grabbing:
				_end_field_grab(event.global_position)
			else:
				_end_drag()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		# Hand cards only — battlefield/opponent/static cards ignore it. Going
		# through _gui_input (not Combat._input) means any modal overlay with
		# MOUSE_FILTER_STOP naturally shields the hand from stray dismissals.
		if not is_on_battlefield and not is_opponent and not static_display \
				and not _is_being_dragged:
			dismiss_requested.emit()
		elif is_on_battlefield and not is_opponent and not static_display \
				and not _field_grabbing:
			# Friendly board creature: right-click lifts a sniper's aim order.
			aim_clear_requested.emit()
	elif event is InputEventMouseMotion:
		if _field_grabbing:
			_update_field_grab(event.global_position)
		elif _is_being_dragged:
			_update_drag(event.global_position)


## Freeze the hand-fan/hover motion so an external flight tween (dismissal's
## arc to the discard pile) owns this card's transform until it frees. The
## fan and hover tweens write position/scale every frame and would fight any
## outside animation — same reason _start_drag kills them.
func begin_flight() -> void:
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	# The pick-up settle writes `scale` too — same reason as the other two.
	if _grab_tween != null and _grab_tween.is_valid():
		_grab_tween.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centre pivot so the flight's shrink happens about the card's middle — but
	# through the compensating swap. A resting hand card wears the fan's
	# bottom-centre pivot at scale 0.72, so the bare assignment this replaced
	# teleported the sheet 42 px DOWN in the frame before the discard arc even
	# started, which is why a dismissal looked like it lurched before it flew.
	_repivot_preserving_pose(size * 0.5)


## ── Marked-for-discard (2026-07-07 discard rework) ─────────────────────────
## Right-click toggles this via Combat._on_card_dismiss_requested; every marked
## card is flushed to the discard pile when the turn ends. The card stays fully
## playable while marked — grabbing it to play rescinds the mark (_start_drag).
var marked_for_discard: bool = false
var _discard_mark: Control = null
# The mark's own dim. Warm, like every other de-emphasis on this sheet — it is
# the same "the lamp is off this one" statement UNPLAYABLE_DIM makes, one stop
# shallower because a marked card is still playable.
const DISCARD_DIM := Color(0.80, 0.75, 0.68, 1.0)


func set_discard_marked(on: bool) -> void:
	if marked_for_discard == on:
		return
	marked_for_discard = on
	if not on:
		if _discard_mark != null and is_instance_valid(_discard_mark):
			_discard_mark.queue_free()
		_discard_mark = null
		# Through the funnel, never a bare `modulate = WHITE`: this card may be
		# unaffordable, and whitening it there hands a "you can play this" read to
		# a card the player cannot pay for. See _apply_hand_tint.
		_apply_hand_tint()
		return
	# The writ's ink drains (dim) and a discard band is laid across it. The band
	# stamps DOWN into place (scale 1.35 → 1) so marking reads as an act, not a
	# state flip; Combat._layout_hand additionally sinks the card in the fan.
	# The band rides the card's UPPER third (anchor 0.26), NOT its centre: the
	# resting hand hangs most of each card below the screen fold (cards lift on
	# hover), and a sunk marked card shows only its top — a centre band would be
	# off-screen, hiding the very label that says the card is marked.
	_apply_hand_tint()
	_discard_mark = Control.new()
	_discard_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_discard_mark)

	var band := Panel.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.26
	band.anchor_bottom = 0.26
	band.offset_left = -8.0
	band.offset_right = 8.0
	band.offset_top = -21.0
	band.offset_bottom = 21.0
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.26, 0.09, 0.07, 0.93)      # oxblood seal-wax band
	st.border_color = Color(0.82, 0.68, 0.44, 0.85)  # gilt edge, kit standard
	st.set_border_width_all(2)
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 8
	band.add_theme_stylebox_override("panel", st)
	_discard_mark.add_child(band)

	var lbl := Label.new()
	lbl.text = "DISCARD"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display != null:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.93, 0.86, 0.72))
	lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.03, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	band.add_child(lbl)

	_discard_mark.pivot_offset = size * 0.5
	_discard_mark.scale = Vector2(1.35, 1.35)
	_discard_mark.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_discard_mark, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_discard_mark, "modulate:a", 1.0, 0.12)


func _start_drag(mouse_pos: Vector2) -> void:
	if is_on_battlefield or is_opponent:
		return
	# Not your turn (skirmish): the hand is locked — don't even lift the card.
	# The grey unplayable veil is already showing; this makes it truly inert.
	if not hand_interactive:
		return
	# Grabbing a marked card rescinds its discard — playing it is the clearest
	# possible "I changed my mind" (and the band must never ride onto the board).
	if marked_for_discard:
		set_discard_marked(false)
	_is_being_dragged = true
	_any_card_dragging = true
	_is_hovered = false
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	# The grab takes over scale/rotation below — a live hover-lift tween would
	# keep writing them every frame and fight the drag (and it also owns the
	# lift shadow's alpha, which the grab re-lights immediately after).
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	# A HELD CARD STILL CASTS A SHADOW. The grab used to ZERO the elevation
	# shadow, so the instant you picked a card up it stopped being an object
	# above the table and became a decal stuck to the pointer — and then the
	# release had nothing to collapse, which is half of why a drop had no
	# landing. Keep it lit at DRAG_SHADOW_A; _end_drag decides how it goes out,
	# hard on a play and soft on a cancel.
	_ensure_lift_shadow()
	_lift_shadow.modulate.a = DRAG_SHADOW_A
	# Straighten the card on grab. Hand cards carry a fan rotation; a tilted
	# card stuck under the cursor reads as a glitch. This used to be a bare
	# `rotation = 0.0` on every path — but when the LEAN arms it is already the
	# owner of `rotation` and damps out of the fan angle on its own over ~150 ms,
	# which is the card righting itself in your hand rather than blinking
	# straight. Under Reduce Motion the lean never arms, so the snap stays: the
	# rule that `rotation` always has exactly one owner is what is being held
	# here, not the snap.
	if _lean_can_arm():
		_arm_lean()
	else:
		rotation = 0.0
	# Pivot to centre so the dragged card scales around its middle, then place
	# that middle under the cursor. With a CENTRED pivot the card's on-screen
	# centre is global_position + size*0.5 INDEPENDENT of scale — so the offset
	# must use the UNSCALED half-size. The old -size*scale*0.5 left the card
	# floating ~(17,22)px down-right of the cursor and, worse, disagreeing with
	# the drop point Combat computed from the `dragging` signal (the highlight
	# lit one slot while the card dropped toward another). Keep this in lockstep
	# with _update_drag / _end_drag below — all three read size*0.5.
	pivot_offset = size * 0.5
	_drag_offset = -size * 0.5
	global_position = mouse_pos + _drag_offset
	z_index = 20
	# THE GRAB. Scale DOWN to 0.85 while dragging so the card doesn't obscure the
	# board it's being dropped on (hover is 1.15, a pop while it sits in hand;
	# 0.85 matches Hearthstone/Cross Blitz, where the picked card is a touch
	# smaller than its hover preview). This was a one-frame SNAP — the
	# cheapest-feeling beat in the whole play gesture: the card didn't get picked
	# up, it teleported into a different size. One BACK-out settle fixes it, and
	# the house overshoot does the work in BOTH directions by construction:
	# coming down off a hover it dips under 0.85 and springs back (a snatch),
	# coming up off the resting fan it swells past and settles (a lift). The
	# centred pivot means the card's middle stays welded to the cursor
	# throughout, so the drop-point maths never sees the settle at all.
	if UserSettings != null and UserSettings.reduce_motion:
		scale = DRAG_SCALE
	else:
		if _grab_tween != null and _grab_tween.is_valid():
			_grab_tween.kill()
		_grab_tween = create_tween()
		_grab_tween.tween_property(self, "scale", DRAG_SCALE, GRAB_SETTLE) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_drag(mouse_pos: Vector2) -> void:
	global_position = mouse_pos + _drag_offset
	# Centre is scale-independent because the drag pivot is centred (see
	# _start_drag); reporting size*0.5 makes the highlight + drop point track
	# the cursor exactly, with no (17,22)px skew.
	dragging.emit(global_position + size * 0.5)


# ── Lean driver (C1) ──────────────────────────────────────────────────

func _lean_can_arm() -> bool:
	# Decorative — Reduce Motion leaves the card rigid, and callers fall back to
	# the historical tweened rotation so `rotation` still has an owner.
	if static_display:
		return false
	if UserSettings != null and UserSettings.reduce_motion:
		return false
	return true


func _arm_lean() -> void:
	if not _lean_can_arm():
		return
	# The driver is about to own the foil's tilt again; a settle tween still
	# easing it home would be a second writer for its remaining life.
	if _gilt_tween != null and _gilt_tween.is_valid():
		_gilt_tween.kill()
	_lean_active = true
	_lean_target = 0.0
	_lean_last_mouse_x = get_global_mouse_position().x
	set_process(true)


## ▲3 — arm the reflow spring toward `_hand_target_position`.
##
## TUNED FROM MEASUREMENT, not from taste — the numbers are the ones that land in
## the same time the tween took, because a hand that became continuous but SLOWER
## would be a downgrade dressed as a feature.
##
##   reflow  f 5.4 / zeta 0.68 -> settles 0.167 s (tween: 0.17)  overshoot 0.2 px
##   deal    f 4.6 / zeta 0.70 -> settles 0.250 s (tween: 0.24)  overshoot 0.6 px
##
## The first guess (f 3.6 / zeta 0.78) measured 0.30 s — nearly twice the tween.
## Note that raising `f` alone barely helps: the settle is governed by the
## exponential tail, so it is the DAMPING that had to come down. The residual
## sub-pixel overshoot is deliberate on both, and is the thing a tween cannot do.
func _arm_hand_spring(delay: float, deal_pop: bool) -> void:
	if _hand_spring == null:
		_hand_spring = Motion.Spring.new()
	if deal_pop:
		_hand_spring.configure(4.6, 0.70, 0.0)
	else:
		_hand_spring.configure(5.4, 0.68, 0.0)
	# Seed from where the card ACTUALLY is, and keep whatever velocity it already
	# had — inheriting that is the entire point. Re-seeding `vel` to zero here
	# would reproduce the tween's restart-from-a-standstill and buy nothing.
	_hand_spring.value = position
	_hand_spring_delay = maxf(delay, 0.0)
	if not _hand_spring_active:
		_hand_spring.vel = Vector2.ZERO
	_hand_spring_active = true
	_hand_spring_wrote = position   # re-baseline, or the yield guard trips at once
	set_process(true)


## Returns true while it still owns `position`.
func _tick_hand_spring(delta: float) -> bool:
	if not _hand_spring_active or _hand_spring == null:
		return false
	# Hover and drag are instant by contract — they killed the tween before, and
	# they stand the spring down now for the same reason.
	if _is_hovered or _is_being_dragged:
		_hand_spring_active = false
		return false
	# A card that has left the hand is not the spring's business any more.
	if compact_mode or is_on_battlefield or static_display:
		_hand_spring_active = false
		return false
	# SOMEBODY ELSE IS WRITING `position` — yield the channel.
	#
	# This is a general guard rather than a list of call sites, because the list
	# is long and open-ended: the refusal beat and the put-down beat both tween
	# position on `_hand_tween`, and Combat's DISCARD FLY-AWAY tweens a still-
	# uncompacted hand card all the way to the pile. That last one is the case
	# that matters — an armed spring would have hauled a discarded card back to
	# its hand slot mid-flight, and no existing gate covers it. Comparing against
	# our own last write catches every such writer, including ones added later.
	if _hand_spring_wrote.is_finite() \
			and position.distance_squared_to(_hand_spring_wrote) > 0.25:
		_hand_spring_active = false
		return false
	if _hand_spring_delay > 0.0:
		# A staggered deal must actually stagger: hold the card where it is until
		# its turn. The tween expressed this with set_delay; the spring waits.
		_hand_spring_delay -= delta
		_hand_spring_wrote = position
		return true
	position = _hand_spring.update(delta, _hand_target_position)
	_hand_spring_wrote = position
	if _hand_spring.is_settled(_hand_target_position):
		position = _hand_target_position     # land exactly on the slot
		_hand_spring.vel = Vector2.ZERO
		_hand_spring_active = false
		return false
	return true


func _disarm_lean() -> void:
	# Hands `rotation` back to the tweens (hover-exit / _end_drag restore it
	# from wherever the lean left it — no snap, and no second writer).
	_lean_active = false
	_lean_target = 0.0
	# NOT an unconditional stop any more: the reflow spring may still own
	# `position`, and killing `_process` here would strand a card mid-flight
	# between two slots. The driver stops when BOTH are idle.
	set_process(_hand_spring_active)
	# ...and hands the GILT back the same way. The driver is the foil's only
	# writer while it runs, so this is the one moment the light can be returned
	# to rest without fighting it. See _settle_gilt_home.
	_settle_gilt_home()


## TWO drivers now share this callback, on DIFFERENT channels: the lean owns
## `rotation`, the reflow spring owns `position`. They are still one-writer-each
## by construction — and the spring stands itself down the moment a hover or drag
## begins, which is exactly when the lean takes over.
func _process(delta: float) -> void:
	var spring_busy := _tick_hand_spring(delta)
	if not _lean_active:
		set_process(spring_busy)
		return
	if _is_being_dragged:
		# Lean into cursor VELOCITY: the card trails the hand that swings it.
		var mx := get_global_mouse_position().x
		var vel_x := (mx - _lean_last_mouse_x) / maxf(delta, 0.0001)
		_lean_last_mouse_x = mx
		_lean_target = clampf(vel_x * LEAN_DRAG_PER_VEL, -LEAN_DRAG_MAX, LEAN_DRAG_MAX)
	elif _is_hovered:
		# Tilt toward the CURSOR's offset from centre: press a corner, that
		# corner dips. Normalised by half-width so the tilt is size-agnostic.
		var centre_x: float = global_position.x + size.x * scale.x * 0.5
		var off: float = (get_global_mouse_position().x - centre_x) \
			/ maxf(size.x * scale.x * 0.5, 1.0)
		_lean_target = clampf(off, -1.0, 1.0) * LEAN_HOVER_MAX
	else:
		_disarm_lean()
		return
	# Frame-rate-independent exponential damp toward the target — the card
	# never snaps to a lean, it eases into and out of one, and a direction
	# reversal mid-drag is handled natively (no tween to kill and restart).
	var rate: float = LEAN_DAMP_DRAG if _is_being_dragged else LEAN_DAMP_HOVER
	rotation = lerpf(rotation, _lean_target, 1.0 - exp(-rate * delta))
	# The leaf catches the light off the SAME angle (★2) — the lean is already
	# the one place per frame that knows how the card is moving, so the foil
	# rides it for free rather than arming a second driver.
	_sweep_gilt(rotation)


func _end_drag() -> void:
	if not _is_being_dragged:
		return
	_is_being_dragged = false
	_any_card_dragging = false
	_disarm_lean()
	z_index = 0
	drag_ended.emit()
	# The pick-up settle must not outlive the pick-up. On the play branch this
	# matters most: Combat calls set_compact_mode() in the SAME frame as
	# played.emit(), and _apply_compact_layout writes `scale = ONE` — a grab
	# tween still running would keep writing scale afterwards and fight the
	# landing arc for the rest of the flight.
	if _grab_tween != null and _grab_tween.is_valid():
		_grab_tween.kill()
	var viewport_h = get_viewport_rect().size.y
	# Wildfrost-style drop: the whole board above the resting hand is a live
	# drop zone. Release with the card's CENTRE on the board → play (Combat
	# snaps it to the nearest slot); release down over the resting hand →
	# cancel. No "drag past mid-screen" gate. Centre is global_position +
	# size*0.5 (scale-independent — the drag pivot is centred, see _start_drag).
	var card_center_y: float = global_position.y + size.y * 0.5
	if card_center_y < viewport_h * PLAY_THRESHOLD_Y:
		# COMMITTED. The card is handed off untouched — Combat reads its live
		# global_position as the flight's origin and owns every transform from
		# here (arc → set_compact_mode → play_wax_press), so anything started
		# now would be a second writer on a card in flight. The one beat that IS
		# ours is the shadow: it snaps shut, because the sheet has left the hand.
		# (set_compact_mode frees it a frame later either way — cutting it here
		# means the last thing the player sees of the held card is it letting go,
		# not the shadow vanishing with the rest of the layout.)
		if _lift_shadow != null and is_instance_valid(_lift_shadow):
			_lift_shadow.modulate.a = 0.0
		played.emit()
	else:
		# RELEASED OVER NOTHING — the player changed their mind. This used to
		# snap all four transforms home in a single frame, which reads as the
		# card being deleted and redrawn rather than set back down. A short
		# QUAD-out put-down instead: gentler than the grab (you pick a card up
		# eagerly and put it down carefully), and DELIBERATELY not the refusal's
		# BACK-out overshoot — a cancel is the player's own decision and must
		# never look like the game saying no (see play_return_to_hand).
		_repivot_preserving_pose(Vector2(size.x * 0.5, size.y))
		# Rotation is the one property that still SNAPS here, deliberately: the
		# drag straightened the card and the lean was disarmed two lines ago, so
		# the whole delta is the ≤6° fan angle Combat._layout_hand assigns — worth
		# nothing as motion, and worth a lot as an invariant. Every function in
		# this file that tweens `rotation` is one more place a second writer could
		# appear during a drag; the cancel keeps itself out of that set entirely.
		rotation = _hand_target_rotation
		if UserSettings != null and UserSettings.reduce_motion:
			scale = _hand_target_scale
			position = _hand_target_position
			if _lift_shadow != null and is_instance_valid(_lift_shadow):
				_lift_shadow.modulate.a = 0.0
			return
		if _hand_tween != null and _hand_tween.is_valid():
			_hand_tween.kill()
		_hand_tween = create_tween()
		_hand_tween.set_parallel(true)
		_hand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_tween.tween_property(self, "scale", _hand_target_scale, PUTDOWN_BEAT)
		_hand_tween.tween_property(self, "position", _hand_target_position, PUTDOWN_BEAT)
		if _lift_shadow != null and is_instance_valid(_lift_shadow):
			_hand_tween.tween_property(_lift_shadow, "modulate:a", 0.0, PUTDOWN_BEAT)


# ═══════════════════════════════════════════
#  DRAG TO MOVE (battlefield repositioning)
# ═══════════════════════════════════════════

func _begin_field_grab(mouse_pos: Vector2) -> void:
	if not board_interactive:
		return
	_field_grabbing = true
	_field_lifted = false
	_field_grab_start = mouse_pos


func _update_field_grab(mouse_pos: Vector2) -> void:
	if not board_interactive:
		return
	if not _field_lifted:
		if mouse_pos.distance_to(_field_grab_start) <= FIELD_MOVE_THRESHOLD:
			return
		# Cross the threshold → lift off the slot. Combat re-parents us onto the
		# free-layout hand layer (slot cells centre their child and would fight
		# manual positioning).
		_field_lifted = true
		_any_card_dragging = true
		# The idle bob owns position.y; switch it off for the lift so it can't fight
		# the cursor (it would otherwise hold the card at its anchor Y while only X
		# followed the mouse). The landing re-arms it at the new slot's centered Y.
		_idle_bob_enabled = false
		# Centre pivot + unscaled half-size offset (same as the hand drag) so the
		# card's visual centre == cursor regardless of any future drag scale.
		pivot_offset = size * 0.5
		_drag_offset = -size * 0.5
		z_index = 50
		field_move_started.emit()
	global_position = mouse_pos + _drag_offset
	dragging.emit(global_position + size * 0.5)


func _end_field_grab(_mouse_pos: Vector2) -> void:
	_field_grabbing = false
	_any_card_dragging = false
	if _field_lifted:
		_field_lifted = false
		drag_ended.emit()
		field_move_dropped.emit(global_position + size * 0.5)


# ═══════════════════════════════════════════
#  HOVER DETAIL PANEL
# ═══════════════════════════════════════════

static var _detail_popup: Control = null
static var _detail_owner = null
# Per-card cached writ inspector. The panel is ~30-40 nodes including the
# procedural parchment painters (WritLeaf/ParchmentPlate/WaxSeal), so rebuilding
# it on every hover-sweep was the dominant "spike when moving cards". It is built
# once per card and reused while its displayed content is unchanged; because it
# lives on the SHARED popup layer (not under this card) it is freed explicitly in
# NOTIFICATION_PREDELETE so a drawn-then-discarded card can't orphan it.
var _detail_cache: Control = null
var _detail_cache_key := ""

func _show_detail_panel() -> void:
	if card_data.is_empty():
		return
	# Only one inspector shows at a time: hide the one another card left up.
	# Hide, don't free — that card keeps it cached for its own next hover.
	if _detail_popup != null and is_instance_valid(_detail_popup) and _detail_owner != self:
		_detail_popup.visible = false
	_detail_owner = self

	var vp = get_viewport()
	if not vp:
		return
	# Parent the popup to a dedicated CanvasLayer ABOVE the combat HUD (layer 12)
	# so it can't be drawn over. Previously it was added to the scene root (canvas
	# layer 0), so the right-column HUD — the enemy Command seal, wave chip — drew
	# on top of the popup's rules text ("the card text appears under the enemy
	# mana so I can't see anything"). Layer 90 sits above the HUD and frame-grade
	# (40) but below the modal pile / glossary viewers (100), and works in every
	# scene that uses Card2D. The popup is transient (only up while hovering), so
	# briefly overlapping the enemy stats is the right trade for readability.
	var host := _detail_host_layer(vp)
	if not host:
		return

	# Build-once / reuse, keyed by the displayed content (card_data + live atk/hp).
	# A battlefield creature that took damage or grew re-keys and rebuilds; a static
	# hand card builds once and is reused for the whole turn. The panel docks at a
	# FIXED screen position (see _wd_build tail), so a reused panel needs no move.
	var key := str(card_data.hash()) + "|" + str(effective_atk()) + "|" \
		+ str(current_hp) + "|" + _status_signature()
	var reused: bool = _detail_cache != null and is_instance_valid(_detail_cache) \
		and _detail_cache_key == key
	if reused:
		_detail_popup = _detail_cache
		if _detail_popup.get_parent() == null:
			host.add_child(_detail_popup)
		_detail_popup.visible = true
	else:
		if _detail_cache != null and is_instance_valid(_detail_cache):
			_detail_cache.queue_free()
		_detail_cache = _build_detail()
		_detail_cache_key = key
		_detail_popup = _detail_cache
		host.add_child(_detail_popup)

	_detail_popup.modulate.a = 0.0
	var tw = _detail_popup.create_tween()
	tw.tween_property(_detail_popup, "modulate:a", 1.0, 0.12)

	# A reused panel was already laid out + clamped on its first build, so skip the
	# frame-deferred clamp below — re-hovers stay allocation- and await-free.
	if reused:
		return

	# Once Godot has laid the popup out, clamp it so a tall popup never runs off
	# the bottom of the screen. The writ slip docks mid-LEFT (see _wd_build), which
	# already clamps above the hero portrait; this is the final viewport safety net.
	var tree := get_tree()
	if tree == null:
		return
	var my_popup := _detail_popup
	await tree.process_frame
	if not is_instance_valid(my_popup):
		return
	var vph := 900.0
	if get_viewport() != null:
		vph = get_viewport().get_visible_rect().size.y
	var max_y := vph - my_popup.size.y - 16.0
	if my_popup.position.y > max_y:
		my_popup.position.y = maxf(12.0, max_y)


func _hide_detail_panel() -> void:
	if _detail_owner != self:
		return
	# Hide (not free): the panel stays cached on this card for the next hover.
	if _detail_popup and is_instance_valid(_detail_popup):
		_detail_popup.visible = false
	_detail_popup = null
	_detail_owner = null


func _notification(what: int) -> void:
	# A card compacted for the board was rebuilt while detached (Combat does it
	# between remove_child and add_child), so being seated is the first moment its
	# new face can animate. Deferred: children get ENTER_TREE after their parent,
	# so _compact_root is not yet a legal tween host at this instant.
	if what == NOTIFICATION_ENTER_TREE and _compact_morph_pending:
		_start_compact_morph.call_deferred()
	# The cached inspector lives on the shared popup layer, not under this card, so
	# free it explicitly when the card is deleted — otherwise every drawn-then-
	# discarded card would orphan a hidden panel on that layer.
	if what == NOTIFICATION_PREDELETE:
		_unregister_battlefield_visuals()
		if _detail_owner == self:
			_detail_owner = null
			_detail_popup = null
		if _detail_cache != null and is_instance_valid(_detail_cache):
			_detail_cache.queue_free()
			_detail_cache = null


func _detail_host_layer(vp: Viewport) -> CanvasLayer:
	## Find-or-create the shared high-layer host for hover detail popups, so the
	## popup draws above scene HUD CanvasLayers instead of behind them. Looked up
	## by a fixed name under the scene root so every Card2D reuses ONE layer
	## rather than spawning a new CanvasLayer per hover.
	const LAYER_NAME := "CardDetailPopupLayer"
	var root := vp.get_child(0) if vp.get_child_count() > 0 else null
	if root == null:
		return null
	var existing := root.get_node_or_null(NodePath(LAYER_NAME))
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	# 110, ABOVE the modal pile / glossary viewers (100), not below them.
	#
	# This used to be 90, chosen so the inspector could not cover those viewers.
	# That reasoning only holds while the modals contain no cards — and the pile
	# viewer is a six-column grid of real Card2D instances. `_on_mouse_entered`
	# has no `static_display` guard, so those cards hover, lift, gild, and raise
	# an inspector ten layers BENEATH the viewer that owns the card being pointed
	# at: the player asks what a card in their discard pile does and gets a lift
	# with no rules text. z_index cannot reach across a CanvasLayer.
	#
	# Above 100 is the correct side, because a modal's full-screen backdrop eats
	# the mouse: while one is open, the only card that CAN be hovered is a card
	# inside it, so a popup that exists at all belongs on top. (Before the
	# backdrop scrims were repaired this hid itself — the "dim" never painted, so
	# the buried popup was still legible wherever it missed a card.)
	layer.layer = 110
	root.add_child(layer)
	return layer


func _build_detail() -> Control:
	# v9 "illuminated writ" hover inspector — the panel is cut from the SAME aged
	# parchment as the cards (deckled WritLeaf + ParchmentPlate ageing, swallowtail
	# name cartouche, pressed wax-seal stats, ink rules text in the Alegreya book
	# hand), so hovering reads as turning to a page in the same codex instead of a
	# flat dark UI box bolted onto the board. Docked on the wide-open MID-LEFT so it
	# clears the dense enemy HUD on the right (the old right dock collided with it).
	#
	# Live-stat injection: a battlefield creature that has grown (Hexblade,
	# Corpse Eater, buffs) or taken damage must read its CURRENT atk/hp, not the
	# printed base. effective_atk() folds temp+persistent buffs; current_hp tracks
	# damage. For a hand card these equal the base, so it's identical there.
	var cd := card_data.duplicate(true)
	if is_creature():
		cd["atk"] = effective_atk()
		cd["hp"] = current_hp
	return _wd_build(cd)


# ── The writ inspector builder. Self-contained: reads only GameTheme /
#    KeywordEffects / the shared card material classes (WritLeaf / ParchmentPlate
#    / InkCartouche / WaxSeal). Returns a Control sized + positioned ready to drop
#    on the popup host layer. ────────────────────────────────────────────────
func _wd_build(cd: Dictionary) -> Control:
	const PW := 300.0
	const PAD := 18.0          # page margin to the leaf edge
	const TXT_L := PAD + 6.0   # inset for written text inside the page
	const INK := Color(0.141, 0.094, 0.063)   # #241810 body ink
	# Match the board/hand seal family exactly (ATK=bronze, HP=oxblood, Cost=navy)
	# — these were previously inverted (ATK read red, HP read green), so red meant
	# HP on the card face but ATK in this inspector. Unified to the canonical
	# GameTheme constants so one colour means one stat everywhere.
	const WAX_ATK := Color(0.471, 0.376, 0.157)  # burnished bronze (ATK_GOLD_SHIELD)
	const WAX_HP := Color(0.510, 0.137, 0.106)   # oxblood (HEALTH_RED_DROP)
	const WAX_COST := Color(0.149, 0.255, 0.404) # navy command (COST_BLUE_GEM)

	var rarity: String = String(cd.get("rarity", "common"))
	var is_creature_card: bool = String(cd.get("type", "")) == "creature"
	var metal: Color = GameTheme.rarity_color(rarity)
	var metal_dim := Color(metal.r, metal.g, metal.b, 0.85)

	var body_font: Font = GameTheme.font_card_body if GameTheme.font_card_body != null \
		else GameTheme.font_body
	var body_bold: Font = GameTheme.font_card_body_bold if GameTheme.font_card_body_bold != null \
		else body_font
	const DESC_SZ := 15
	const KW_SZ := 14
	var text_w := PW - TXT_L * 2.0

	var desc_text: String = str(cd.get("desc", ""))
	# Descless cards (some enemy-only creatures) synthesise their trigger text so
	# the page is never blank.
	if desc_text == "":
		var ex: Array[String] = []
		if cd.has("on_enter") and cd.on_enter.has("type"):
			ex.append("On-Enter: " + _describe_trigger(cd.on_enter))
		if cd.has("on_death") and cd.on_death.has("type"):
			ex.append("On-Death: " + _describe_trigger(cd.on_death))
		if cd.has("adj_buff"):
			var ab = cd.adj_buff
			var parts: Array[String] = []
			if ab.get("atk", 0) != 0: parts.append("+%d ATK" % ab.atk)
			if ab.get("hp", 0) != 0: parts.append("+%d HP" % ab.hp)
			if parts.size() > 0: ex.append("Adjacent: %s" % ", ".join(parts))
		desc_text = "\n".join(ex)
	var live_effect_readout := compact_mode and not static_display and is_creature_card
	var active_lines: Array[String] = []
	if live_effect_readout:
		active_lines = _wd_active_effect_lines()
		if active_lines.is_empty():
			active_lines.append("None: no keyword or combat status is active.")
	var kw_lines: Array[String] = []
	if not live_effect_readout:
		kw_lines = _wd_keyword_lines(cd)
	var service_line := _wd_veteran_line(cd)

	# ── pre-measure the writing so the slip grows to fit (no scrollbars) ──
	var write_h := 0.0
	if live_effect_readout:
		write_h += _wd_wrapped_height("ACTIVE NOW", body_bold, KW_SZ, text_w) + 2.0
		for ln in active_lines:
			write_h += _wd_wrapped_height(ln, body_bold, KW_SZ, text_w) + 6.0
		if desc_text != "":
			write_h += 8.0 + _wd_wrapped_height("CARD TEXT", body_bold, KW_SZ, text_w)
	if desc_text != "":
		write_h += _wd_wrapped_height(desc_text, body_font, DESC_SZ, text_w)
	if service_line != "":
		write_h += 10.0 + _wd_wrapped_height(service_line, body_bold, KW_SZ, text_w)
	if kw_lines.size() > 0:
		write_h += 10.0
		for ln in kw_lines:
			write_h += _wd_wrapped_height(ln, body_bold, KW_SZ, text_w) + 6.0

	# vertical skeleton (real px down the slip)
	var y_gem := 14.0
	var y_cart := 30.0
	var cart_h := 32.0
	var y_type := y_cart + cart_h + 9.0
	var type_h := 20.0
	var y_seals := y_type + type_h + 10.0
	var seal_d := 60.0
	var y_after_seals := y_seals + (seal_d + 12.0 if is_creature_card else 4.0)
	var y_writebox := y_after_seals
	var write_pad := 14.0
	var box_h: float = max(write_h + write_pad * 2.0, 56.0)
	var panel_h := y_writebox + box_h + PAD

	# ── root + drop shadow ──
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = Vector2(PW, panel_h)
	root.size = Vector2(PW, panel_h)
	root.z_index = 100

	var seat := Panel.new()
	seat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seat.position = Vector2(4, 5)
	seat.size = Vector2(PW - 8, panel_h - 8)
	var seat_st := StyleBoxFlat.new()
	seat_st.bg_color = Color(0, 0, 0, 0.0)
	seat_st.set_corner_radius_all(12)
	seat_st.shadow_color = Color(0, 0, 0, 0.55)
	seat_st.shadow_size = 16
	seat_st.shadow_offset = Vector2(0, 5)
	seat.add_theme_stylebox_override("panel", seat_st)
	root.add_child(seat)

	# quiet rarity glow halo
	var glow_size := 3
	match rarity:
		"white": glow_size = 13
		"rare": glow_size = 11
		"uncommon": glow_size = 7
		"common": glow_size = 3
		"starter": glow_size = 2
	var glow := Panel.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2(3, 3)
	glow.size = Vector2(PW - 6, panel_h - 6)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0, 0, 0, 0.0)
	gs.set_corner_radius_all(10)
	var gcol: Color = metal
	if rarity == "white":
		gcol = Color(0.86, 0.96, 1.0)
	elif rarity == "rare":
		gcol = Color(0.95, 0.72, 0.25)
	gs.shadow_color = Color(gcol.r, gcol.g, gcol.b, 0.50)
	gs.shadow_size = glow_size
	glow.add_theme_stylebox_override("panel", gs)
	root.add_child(glow)

	# ── the leaf: deckled parchment, the SAME stock the cards are cut from ──
	var leaf := WritLeaf.new()
	leaf.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaf.seed_text = String(cd.get("id", "?")) + "_writ"
	leaf.corner_radius = 10.0
	root.add_child(leaf)

	var tooth := ParchmentPlate.new()
	tooth.clip_contents = true
	tooth.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooth.offset_left = 3; tooth.offset_top = 3
	tooth.offset_right = -3; tooth.offset_bottom = -3
	tooth.seed_text = String(cd.get("id", "?")) + "_writ"
	tooth.strength = 0.85
	root.add_child(tooth)

	if GameTheme.tex_card_grain:
		var bgn := TextureRect.new()
		bgn.texture = GameTheme.tex_card_grain
		bgn.stretch_mode = TextureRect.STRETCH_TILE
		bgn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgn.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgn.offset_left = 3; bgn.offset_top = 3
		bgn.offset_right = -3; bgn.offset_bottom = -3
		bgn.modulate = Color(0.42, 0.30, 0.16, 0.09)
		bgn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bgn)

	# metal rules: ink keyline + heavy outer + hairline inner (the card language)
	_wd_rule_ring(root, 4.0, 1, Color(0.165, 0.125, 0.082, 0.50), 9)
	_wd_rule_ring(root, 5.0, 2, metal, 8)
	_wd_rule_ring(root, 9.0, 1, Color(metal.r * 0.8, metal.g * 0.8, metal.b * 0.8, 0.80), 6)

	# ── rarity gem, top-center ──
	var gem_col: Color
	match rarity:
		"white": gem_col = Color(0.92, 0.98, 1.00)
		"rare": gem_col = Color(0.97, 0.72, 0.16)
		"uncommon": gem_col = Color(0.36, 0.62, 0.96)
		"starter": gem_col = Color(0.55, 0.53, 0.49)
		_: gem_col = Color(0.88, 0.90, 0.92)
	var gem_r: float = 9.0 if (rarity == "white" or rarity == "rare" or rarity == "uncommon") else 7.5
	var cx := PW * 0.5
	_wd_diamond(root, Vector2(cx, y_gem), gem_r + 5.0, Color(0.10, 0.082, 0.060))
	_wd_diamond(root, Vector2(cx, y_gem), gem_r, gem_col)
	_wd_diamond(root, Vector2(cx, y_gem - 1.4), gem_r * 0.38,
		Color(minf(gem_col.r * 1.4, 1), minf(gem_col.g * 1.4, 1), minf(gem_col.b * 1.4, 1)))

	# ── cost: a small navy wax seal, top-left of the page ──
	var cost_seal := WaxSeal.new()
	cost_seal.wax = WAX_COST
	cost_seal.seed_text = String(cd.get("id", "?")) + "_cost"
	cost_seal.position = Vector2(PAD - 2.0, y_cart - 4.0)
	cost_seal.size = Vector2(38, 38)
	cost_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cost_seal)
	_wd_numeral(cost_seal, str(int(cd.get("cost", 0))), 20)

	# ── name cartouche: swallowtail ink banner, metal-edged ──
	var cart := InkCartouche.new()
	cart.metal = metal
	cart.position = Vector2(PAD + 30.0, y_cart)
	cart.size = Vector2(PW - (PAD + 30.0) - PAD, cart_h)
	root.add_child(cart)
	var name_font: Font = GameTheme.font_title_black if GameTheme.font_title_black != null \
		else GameTheme.font_display
	var nm := String(cd.get("name", ""))
	var nm_size := 20
	if nm.length() > 18: nm_size = 15
	elif nm.length() > 13: nm_size = 17
	var name_lbl := _wd_label(nm, name_font, nm_size, Color(0.95, 0.85, 0.58))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	name_lbl.position = Vector2(cart.position.x + 9.0, cart.position.y)
	name_lbl.size = Vector2(cart.size.x - 18.0, cart_h)
	root.add_child(name_lbl)

	# ── type • rarity line ── (sepia ink, not the rarity metal: the gem + glow +
	# cartouche already carry rarity, and grey starter-metal washes out on vellum)
	var type_text := "Creature"
	match String(cd.get("type", "")):
		"spell": type_text = "Spell"
		"armament": type_text = "Armament"
	var tl := _wd_label("%s   •   %s" % [type_text, rarity.capitalize()], body_font, 14,
		Color(0.31, 0.22, 0.11))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.position = Vector2(PAD, y_type)
	tl.size = Vector2(text_w + 12.0, type_h)
	root.add_child(tl)

	var head_rule := ColorRect.new()
	head_rule.color = Color(metal.r, metal.g, metal.b, 0.38)
	head_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_rule.position = Vector2(PAD + 24.0, y_type + type_h + 2.0)
	head_rule.size = Vector2(PW - (PAD + 24.0) * 2.0, 1.0)
	root.add_child(head_rule)

	# ── wax seals: ATK (oxblood) + HP (forest), creatures only ──
	if is_creature_card:
		var gap := 40.0
		var pair_w := seal_d * 2.0 + gap
		var sx := cx - pair_w * 0.5
		var atk_seal := WaxSeal.new()
		atk_seal.wax = WAX_ATK
		atk_seal.seed_text = String(cd.get("id", "?")) + "_atk"
		atk_seal.position = Vector2(sx, y_seals)
		atk_seal.size = Vector2(seal_d, seal_d)
		atk_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(atk_seal)
		_wd_numeral(atk_seal, str(int(cd.get("atk", 0))), 30)
		_wd_caption(root, "ATK", Vector2(sx, y_seals + seal_d - 1.0), seal_d, WAX_ATK)

		var hx := sx + seal_d + gap
		var hp_seal := WaxSeal.new()
		hp_seal.wax = WAX_HP
		hp_seal.seed_text = String(cd.get("id", "?")) + "_hp"
		hp_seal.position = Vector2(hx, y_seals)
		hp_seal.size = Vector2(seal_d, seal_d)
		hp_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(hp_seal)
		_wd_numeral(hp_seal, str(int(cd.get("hp", 0))), 30)
		_wd_caption(root, "HP", Vector2(hx, y_seals + seal_d - 1.0), seal_d, WAX_HP)

	# ── inscribed sub-panel: cleaner vellum + gilt hairline + corner ticks ──
	var box_x := PAD - 2.0
	var box_w := PW - box_x * 2.0
	var stock := Panel.new()
	stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock.position = Vector2(box_x, y_writebox)
	stock.size = Vector2(box_w, box_h)
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0.901, 0.843, 0.690, 0.50)
	sst.set_corner_radius_all(3)
	stock.add_theme_stylebox_override("panel", sst)
	root.add_child(stock)
	var rbox := Panel.new()
	rbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rbox.position = Vector2(box_x, y_writebox)
	rbox.size = Vector2(box_w, box_h)
	var rst := StyleBoxFlat.new()
	rst.draw_center = false
	rst.border_color = Color(0.255, 0.188, 0.118, 0.75)
	rst.set_border_width_all(1)
	rbox.add_theme_stylebox_override("panel", rst)
	root.add_child(rbox)
	for corner in [Vector2(box_x, y_writebox), Vector2(box_x + box_w, y_writebox),
			Vector2(box_x, y_writebox + box_h), Vector2(box_x + box_w, y_writebox + box_h)]:
		_wd_diamond(root, corner, 3.4, metal_dim)

	# ── the writing: rules in ink, keyword defs in paper-gold ──
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 5)
	vbox.position = Vector2(TXT_L, y_writebox + write_pad)
	vbox.size = Vector2(text_w, box_h - write_pad * 2.0)
	root.add_child(vbox)

	if live_effect_readout:
		var live_head := _wd_section_heading("ACTIVE NOW", body_bold, KW_SZ, text_w,
			Color(0.45, 0.19, 0.10))
		vbox.add_child(live_head)
		for ln in active_lines:
			vbox.add_child(_wd_kw_label(ln, body_bold, KW_SZ, text_w))
		if desc_text != "":
			var live_div := ColorRect.new()
			live_div.color = Color(metal.r, metal.g, metal.b, 0.22)
			live_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
			live_div.custom_minimum_size = Vector2(text_w, 1)
			vbox.add_child(live_div)
			vbox.add_child(_wd_section_heading("CARD TEXT", body_bold, KW_SZ, text_w,
				Color(0.31, 0.22, 0.11)))

	if desc_text != "":
		var dl := _wd_label(desc_text, body_font, DESC_SZ, INK)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(text_w, 0)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(dl)

	if service_line != "":
		var sdiv := ColorRect.new()
		sdiv.color = Color(metal.r, metal.g, metal.b, 0.22)
		sdiv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sdiv.custom_minimum_size = Vector2(text_w, 1)
		vbox.add_child(sdiv)
		vbox.add_child(_wd_kw_label(service_line, body_bold, KW_SZ, text_w))

	if kw_lines.size() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 3)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(spacer)
		var kdiv := ColorRect.new()
		kdiv.color = Color(metal.r, metal.g, metal.b, 0.30)
		kdiv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kdiv.custom_minimum_size = Vector2(text_w, 1)
		vbox.add_child(kdiv)
		for ln in kw_lines:
			vbox.add_child(_wd_kw_label(ln, body_bold, KW_SZ, text_w))

	# ── dock: mid-LEFT, clear of the dense enemy HUD on the right and clamped to
	# sit above the hero portrait/HP cluster (bottom-left). Transient hover, so a
	# brief overlap of the relic column is the right trade for legibility.
	var band_bottom := 632.0
	root.position = Vector2(34.0, clampf(300.0, 16.0, maxf(16.0, band_bottom - panel_h)))
	return root


# Keyword definition lines: "<display>: <desc>" — skip pure trigger-labels
# (on_enter / on_death / adj_buff / adjacent) which the desc already spells out.
# Doom / Wither show the card's live N.
func _wd_active_effect_lines() -> Array[String]:
	var out: Array[String] = []
	for entry in _active_effect_entries(true):
		var display := String(entry.get("display", ""))
		var desc := String(entry.get("desc", ""))
		if desc == "":
			out.append("%s: active now." % display)
		else:
			out.append("%s: %s" % [display, desc])
	return out


func _wd_keyword_lines(cd: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var skip := ["on_enter", "on_death", "adj_buff", "adjacent"]
	for kw in cd.get("keywords", []):
		var k := String(kw)
		if k in skip or not KeywordEffects.KEYWORDS.has(k):
			continue
		var kdef: Dictionary = KeywordEffects.KEYWORDS[k]
		var disp := str(kdef.get("display", ""))
		if k == "doom":
			disp = "Doom %d" % int(cd.get("doom", 0))
		elif k == "wither":
			disp = "Wither %d" % int(cd.get("wither", 0))
		out.append("%s: %s" % [disp, str(kdef.get("desc", ""))])
	return out


func _wd_veteran_line(cd: Dictionary) -> String:
	if String(cd.get("type", "")) != "creature":
		return ""
	var kills := int(cd.get("veteran_kills", 0))
	if kills <= 0:
		return ""
	if kills < RunState.veteran_epithet_kills():
		return "Campaign: %d kills, %d to an earned name and a war school." % [
			kills, RunState.veteran_epithet_kills() - kills]
	if kills < RunState.VETERAN_RANK_KILLS:
		return "Campaign: %d kills, %d to +1/+1." % [
			kills, RunState.VETERAN_RANK_KILLS - kills]
	if kills < RunState.veteran_doctrine_kills():
		return "Campaign: %d kills, %d to a doctrine." % [
			kills, RunState.veteran_doctrine_kills() - kills]
	return "Campaign: %d kills, fully trained." % kills


func _wd_label(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# A keyword line: bold paper-gold term, lighter brown definition body — one
# RichTextLabel so the term reads as a heading without a second control.
func _wd_section_heading(text: String, font: Font, size: int, w: float, col: Color) -> Label:
	var l := _wd_label(text, font, size, col)
	l.custom_minimum_size = Vector2(w, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _wd_kw_label(line: String, font: Font, size: int, w: float) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.custom_minimum_size = Vector2(w, 0)
	if font:
		rt.add_theme_font_override("normal_font", font)
		rt.add_theme_font_override("bold_font", font)
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_font_size_override("bold_font_size", size)
	rt.add_theme_color_override("default_color", Color(0.36, 0.24, 0.06))
	var colon := line.find(":")
	if colon > 0:
		rt.text = "[color=#7a4f10][b]%s[/b][/color]:%s" % [line.substr(0, colon), line.substr(colon + 1)]
	else:
		rt.text = "[color=#7a4f10]%s[/color]" % line
	return rt


# Cream numeral centered over a seal, dark outline so it pops off the wax.
func _wd_numeral(seal: Control, txt: String, size: int) -> void:
	var l := Label.new()
	l.text = txt
	var f: Font = GameTheme.font_stat if GameTheme.font_stat != null else GameTheme.font_display
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82))
	l.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(l)


# Small engraved caption under a seal ("ATK" / "HP").
func _wd_caption(root: Control, txt: String, pos: Vector2, w: float, tint: Color) -> void:
	var l := _wd_label(txt, GameTheme.font_display, 11,
		Color(tint.r * 0.75 + 0.10, tint.g * 0.55 + 0.08, tint.b * 0.55 + 0.06, 0.95))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = Vector2(w, 16)
	root.add_child(l)


# A rounded-rect border ring — the card's metal-rule language.
func _wd_rule_ring(root: Control, inset: float, width: int, col: Color, radius: int) -> void:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = inset; p.offset_top = inset
	p.offset_right = -inset; p.offset_bottom = -inset
	var st := StyleBoxFlat.new()
	st.draw_center = false
	st.border_color = col
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", st)
	root.add_child(p)


func _wd_diamond(root: Control, center: Vector2, r: float, col: Color) -> void:
	var d := WritDetailDiamond.new()
	d.col = col
	d.r = r
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.position = center - Vector2(r, r)
	d.size = Vector2(r * 2.0, r * 2.0)
	root.add_child(d)


# Wrapped-text height so the slip grows to fit its writing.
func _wd_wrapped_height(text: String, font: Font, size: int, w: float) -> float:
	if font == null:
		return float(size) + 4.0
	var lh: float = font.get_height(size) + 2.0
	var lines := 1
	var cur := ""
	for word in text.split(" "):
		var trial := word if cur == "" else cur + " " + word
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
			lines += 1
			cur = word
		else:
			cur = trial
	return lh * float(lines)


func _describe_trigger(data: Dictionary) -> String:
	var t = data.get("type", "")
	var v = data.get("value", 0)
	match t:
		"damage_opposing": return "Deal %d damage to the opposing creature" % v
		"damage_random_player": return "Deal %d damage to a random friendly creature" % v
		"damage_all_enemies": return "Deal %d damage to all enemy creatures" % v
		"damage_face": return "Deal %d damage to enemy face" % v
		"draw": return "Draw a card" if v == 1 else "Draw %d cards" % v
		"gain_gold": return "Gain %d gold" % v
		"debuff_opposing_atk": return "The opposing creature gets -%d ATK" % v
		"discard_random": return "Discard a random card" if v == 1 \
			else "Discard %d random cards" % v
		"damage_opposing_lane": return "Deal %d damage to the opposing lane" % v
		"summon": return "Summon a %d/%d token" % [data.get("atk", 1), data.get("hp", 1)]
		"bonus_mana": return "Gain %d bonus Command" % v
		"debuff_all_player_atk": return "All friendlies get -%d ATK" % v
		"damage_adjacent": return "Deal %d damage to adjacent creatures" % v
		"buff_ctype_hp": return "Your %s gain +%d HP this fight" % [String(data.get("ctype", "creature")).capitalize(), v]
		"betray_opposing": return "The opposing enemy attacks its nearest ally or its own face"
		"damage_any": return "Deal %d damage to any target" % v
		"summon_random": return "Summon a random creature"
		"kill_adjacent_summon": return "Kill adjacent, summon in its place"
		"steal_atk": return "Steal %d ATK from the opposing creature" % v
		"heal_all_friendly": return "Heal all friendlies %d HP" % v
		"summon_token": return "Summon a token creature"
	return t.replace("_", " ").capitalize()


## Compose face rules text for a descless card (enemy-only creatures carry no
## `desc`). Trigger lines first — the custom rules a keyword device can't show —
## then keyword glossary lines. Only used when synth_desc_if_empty is set (the
## battle-log hover preview), so it's a teaching surface like the detail panel.
func _synthesized_rules_text() -> String:
	var lines: Array[String] = []
	if card_data.has("on_enter") and card_data.on_enter is Dictionary and card_data.on_enter.has("type"):
		lines.append("On enter: %s." % _describe_trigger(card_data.on_enter))
	if card_data.has("on_death") and card_data.on_death is Dictionary and card_data.on_death.has("type"):
		lines.append("On death: %s." % _describe_trigger(card_data.on_death))
	if card_data.has("adj_buff") and card_data.adj_buff is Dictionary:
		var ab: Dictionary = card_data.adj_buff
		var parts: Array[String] = []
		if int(ab.get("atk", 0)) != 0: parts.append("+%d ATK" % int(ab.atk))
		if int(ab.get("hp", 0)) != 0: parts.append("+%d HP" % int(ab.hp))
		if parts.size() > 0:
			lines.append("Adjacent friendlies: %s." % ", ".join(parts))
	for kw in card_data.get("keywords", []):
		var k := String(kw)
		if k in ["on_enter", "on_death", "adj_buff", "adjacent"]:
			continue
		if not KeywordEffects.KEYWORDS.has(k):
			continue
		var kdef: Dictionary = KeywordEffects.KEYWORDS[k]
		var disp := str(kdef.get("display", ""))
		if k == "doom":
			disp = "Doom %d" % int(card_data.get("doom", 0))
		elif k == "wither":
			disp = "Wither %d" % int(card_data.get("wither", 0))
		var kd := str(kdef.get("desc", ""))
		lines.append("%s — %s" % [disp, kd] if kd != "" else disp)
	return "\n".join(lines)


## ARMORED: the writ is strapped into a riveted edge. The painter carries the
## rule in repeated hardware and edge silhouette, so it survives grayscale and
## compact-token scale without occupying the creature's identifying artwork.
func _build_armored_edge() -> void:
	var edge := ArmoredEdge.new()
	edge.name = "ArmoredEdge"
	edge.seed_text = "armored_%s" % String(card_data.get("id", "x"))
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.z_index = 0
	_compact_root.add_child(edge)
	_armored_edge = edge
	# The state is present immediately. A short material settle only calls
	# attention to a mid-fight grant and is omitted under Reduce Motion.
	if not (UserSettings != null and UserSettings.reduce_motion):
		edge.modulate.a = 0.0
		var tw := edge.create_tween()
		tw.tween_property(edge, "modulate:a", 1.0, Motion.time(0.12))


func _clear_armored_edge() -> void:
	if _armored_edge == null or not is_instance_valid(_armored_edge):
		_armored_edge = null
		return
	# Protection is already gone in the rules, so its frame leaves immediately
	# rather than lying for the duration of a decorative fade.
	_armored_edge.queue_free()
	_armored_edge = null


## LAST STAND: a purpose-built token candle mounted on the trailing edge. It
## clears the leading edge for granted Swift and avoids Doom/keyword furniture
## at the top plus the stat seals at the bottom.
func _build_last_stand_candle() -> void:
	var candle := LastStandCandle.new()
	candle.name = "LastStandCandle"
	candle.seed_text = "last_stand_%s" % String(card_data.get("id", "x"))
	candle.size = Vector2(44, 68)
	candle.position = Vector2(164, 40) if is_opponent else Vector2(-8, 40)
	candle.pivot_offset = candle.size * 0.5
	candle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	candle.z_index = 5
	_compact_root.add_child(candle)
	_last_stand_candle = candle
	if not (UserSettings != null and UserSettings.reduce_motion):
		candle.modulate.a = 0.0
		candle.scale = Vector2(0.86, 0.86)
		var tw := candle.create_tween().set_parallel(true)
		tw.tween_property(candle, "modulate:a", 1.0, Motion.time(0.10))
		tw.tween_property(candle, "scale", Vector2.ONE, Motion.time(0.16)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _clear_last_stand_candle(spent: bool) -> void:
	if _last_stand_candle == null or not is_instance_valid(_last_stand_candle):
		_last_stand_candle = null
		return
	var old := _last_stand_candle
	_last_stand_candle = null
	if spent:
		# Information changes on the first frame: the flame is out before the
		# spent hardware fades, so the brief exit can never imply a second save.
		old.set("flame_strength", 0.0)
	if UserSettings != null and UserSettings.reduce_motion:
		old.queue_free()
		return
	var tw := old.create_tween()
	tw.tween_property(old, "modulate:a", 0.0, Motion.time(0.16))
	tw.tween_callback(old.queue_free)
