extends Node
## SkirmishState.gd — autoload singleton. The skirmish equivalent of RunState:
## the per-player decks / HP / mode that the combat scene reads in _ready() when
## running an online match. See docs/MULTIPLAYER_SKIRMISH_PLAN.md §6.2.
##
## Indices: slot 0 = host's player, slot 1 = client's player (mirrors
## NetMatch.local_player_index). The host knows BOTH decks (it is authoritative);
## the client only needs its own deck locally — the opponent board arrives via
## combat events.
##
## Phase 1 fills decks during the draft; Phase 2 reads them via Combat's _ctx_*
## accessors. v1 is relic-free and upgrade-free, so those fields stay empty and
## the corresponding single-player code paths in Combat.gd go inert.

enum CombatMode { SOLO, NET_HOST, NET_CLIENT }

## Deck-acquisition flows the lobby can launch. The networked COMBAT layer is
## mode-agnostic — every mode just fills the two player slots with decks and drops
## into the same combat.tscn — so a new mode is a new deck-acquisition scene plus
## an entry here. DRAFT is the original 1-of-3 ×20.
enum MatchMode { DRAFT, CONSTRUCTED, QUICK, SEALED }

const START_HP: int = 30
const BASE_MAX_MANA: int = 3
const DECK_TARGET: int = 20   # cards drafted per player
## Source-dealing rules used by the host to prove that a submitted loadout was
## actually attainable in its selected skirmish mode. Keep these in lockstep
## with the deck-acquisition screens; the pure helpers below are deliberately
## independent of scene/UI state so they form a real authority boundary.
const DECK_COPY_CAP: int = 2
const SEALED_POOL_SIZE: int = 30
const SEALED_MAX_PER_ID: int = 3
const DRAFT_REROLL_CAP: int = 2
## DEFAULT arsenal size — the fixed 3 relics + 2 potions the stage shipped with
## (2026-07-16). Since the host can now set the size in the lobby these are the
## resting values, not a rule: the LIVE counts are arsenal_relics /
## arsenal_potions below. NetMatch mirrors these two literals in its own field
## initializers (autoload order forbids reading them there) — _probe_draft_relic
## gates the pair, so a change here must be made there too.
const ARSENAL_RELIC_ROUNDS: int = 3
const ARSENAL_POTION_ROUNDS: int = 2
## Offerings on one Arsenal table — the stage is a 1-of-3 pick.
const ARSENAL_SLATE_SIZE: int = 3
## Hard ceiling on potion rounds regardless of pool size: the combat belt draws
## at most this many bottles (RunState.MAX_POTIONS, and the apothecary shelf the
## HUD builds under the player banner is laid out for that run). MEASURED, not
## inherited from RunState.MAX_POTIONS: the skirmish belt draws the drafted count
## (Combat._ctx_max_potions), and 4 slots end at x248 against the board's left
## edge at x272 — a fifth would end at 300, through the board.
const ARSENAL_POTION_BELT_CAP: int = 4

## The act whose reward ODDS the draft rolls at. Act 3 (30/50/20 common/uncommon/
## rare — see CardDB.ACT_REWARD_WEIGHTS) so a drafted warband feels like a
## late-campaign deck rather than a flat sample of the pool. See NetDraft and
## deal_weighted_triplet below.
const DRAFT_ACT: int = 3

## Skirmish has its own rarity cadence. Campaign rewards can stay generous late,
## but PvP needs fewer top-end offers per slate.
const SKIRMISH_RARITY_TIERS: Array[String] = ["common", "uncommon", "rare", "white"]
const SKIRMISH_DRAFT_WEIGHTS: Array[int] = [55, 36, 8, 1] # common/uncommon/rare/white

## MP-only rarity overrides. These cards keep their solo rarity in CardDB, but
## draft / quick / sealed treat them as the new White tier because their downside
## is materially softer in skirmish than campaign. Keep this list tiny: White is
## for "broken in MP, fine in solo", not for generically strong cards.
const SKIRMISH_RARITY_OVERRIDES: Dictionary = {}

## Mode registry: id → display name, deck-acquisition scene, and a one-line blurb.
## The lobby builds its picker from this and routes to `scene` on START. A mode is
## only OFFERED if its scene file exists in the build (see available_modes), so
## modes light up as their scenes land — the framework ships safe with only DRAFT.
const MODE_DEFS: Array = [
	{"id": MatchMode.DRAFT, "name": "Draft", "scene": "res://scenes/net_draft.tscn",
		"blurb": "Pick 1 of 3, twenty times."},
	{"id": MatchMode.CONSTRUCTED, "name": "Constructed", "scene": "res://scenes/net_constructed.tscn",
		"blurb": "Build any 20-card deck from the full pool."},
	{"id": MatchMode.QUICK, "name": "Quick Battle", "scene": "res://scenes/net_quick.tscn",
		"blurb": "Random decks — straight to the fight."},
	{"id": MatchMode.SEALED, "name": "Sealed", "scene": "res://scenes/net_sealed.tscn",
		"blurb": "Open a fixed pool and build a deck from it."},
]

## Card ids barred from the skirmish draft even though their rarity is draftable —
## cards that assume single-player context (gold economy, draw/discard/exhaust
## pile mutation that the client must mirror, or Discover-style hand enrichment;
## see plan §13.3). Curated 2026-06-16; grow as pile-sync lands post-v1.
const SKIRMISH_DENYLIST: Array[String] = [
	# Gold economy — no shop/gold in skirmish v1. (Kingpin joined 2026-07-15:
	# his Stray aura reads the run's purse.)
	"scavenger", "pillage", "kingpin",
	# Draw / discard / exhaust pile mutation that still lacks a net port.
	# (gambit / recycle / mass_grave came off via the caster-local pile path;
	# Frenzy is now host-resolved — see NET_SPELL_CUSTOMS. gravedigger +
	# bloodhound came off 2026-07-09: their draw routes through the same host→owner
	# EV_DRAW channel via _battlecry_draw, so the owner draws on its own machine.)
	# Discover / tutor — injects arbitrary cards into hand; needs pool coordination.
	"familiar", "scholar", "lost_tome", "war_council", "treasure_hunter",
	"unholy_bargain",  # campaign-only persistent consequence has no net mirror
	# Solo campaign systems: Old Campaigner reads the run's kill ledger and
	# Sin-Eater eats Curses — neither exists in skirmish.
	"ironclad_veteran", "sin_eater",
	# 2026-07-30 COUNTERORDERS slate: all three pay off an enemy INTENT badge, and
	# a human opponent has no intent cycle to read. Denylisted rather than left to
	# silently no-op — a card whose whole text is inert reads as a bug.
	"counterorders", "order_breaker", "the_interpreter",
	# 2026-07-07 fun slate: The Volunteer rides the dismissal (hand-local in
	# net — its muster wouldn't sync), Muster the Fallen reads the run's Roll
	# of the Fallen, and Slow Match / Trebuchet lack net resolver ports
	# (hand-fuse state / start-round volley).
	"volunteer", "muster_fallen", "slow_match", "trebuchet",
	# Fetch Hound reads the caster's discard pile — caster-local pile state the
	# host can't see for the client (same class as the pile spells above).
	"hound",
	# 2026-07-13 stolen-classics slate — solo-campaign designs. Pressed Man's
	# on-death heals the OTHER face (no net heal mirror yet); The Undying and
	# The Long Roll read/write RunState (mod stack / run deck); Wolf-Pits hooks
	# solo enemy placement; The Informer reads the encounter deck; Forgefire
	# mutates hand-local card data the host can't rebuild for the client.
	# (Grave Clutch stays net-legal — a plain on-death summon, same as Husk.)
	"pressed_man", "the_undying", "long_roll", "wolf_pits", "informer", "forgefire",
	# Lookout (2026-07-15 rework): its back-row scout reads the solo encounter
	# deck — same class as The Informer; a human foe's hand can't be scried.
	"lookout",
	# Bastion Lord's global struck-survivor volley remains campaign-only. The
	# three wall-cycle reactions now resolve host-side for both owners and are
	# net-legal (Iron Rampart reflection / Oathwall heal / Stockade summon).
	"bastion_lord",
	# Close Ranks (2026-07-13): lateral funnel via _flank_push — net-portable
	# (mirrors Scatter's net arm) but no net resolver added yet.
	"close_ranks",
	# 2026-07-16 interest slate: bespoke solo movement, delayed-lane, economy,
	# Roll, and multi-click effects do not yet have authoritative net mirrors.
	"sword_on_credit", "crew_mangonel", "pay_wagon", "pallbearers",
	"gallows_writ", "salted_ground", "body_snatcher", "scapegoat",
	"understudy", "mentioned_dispatches", "drill_serjeant", "crossed_orders",
	"wheeling_lancer", "rolling_tower", "flanking_order", "hook_and_chain",
]

## Draftable rarities for skirmish. Mirrors CardDB's draftable convention (starter
## + common + uncommon + rare); curses and enemy-only cards are excluded by rarity
## and filtered defensively below.
const DRAFTABLE_RARITIES: Array[String] = ["starter", "common", "uncommon", "rare"]

## Battle relics legal in the skirmish draft. Two kinds qualify:
##   1. PRIVATE RESOURCE — touches hand refill / Command / banking / card cost.
##      The host computes its own through Combat and the client's through
##      NetPlayerState; the client only renders the resulting private snapshot.
##   2. BOARD/HP, HOST-AUTHORITATIVE (2026-07-09) — the effect mutates the board or
##      a hero's HP at a hook that already runs per-side on the host, gated through
##      Combat._relic_active_for_side(owner_is_enemy, id). The host applies the
##      owner's relic to the owner's side and the board snapshot animates it on the
##      client. To add one: wire the hook to _relic_active_for_side, then list it here.
## Still OUT: gold/map/reward/deck-upgrade relics (no such systems in skirmish) and
## bespoke pile-order relics that do not yet have a NetPlayerState implementation.
const NET_RELIC_POOL: Array[String] = [
	"ember_crown",
	"pact_of_embers",
	"last_breath",
	"cavalry_sigil",
	"spell_tome",
	# mana_drunkard dropped 2026-07-25 for the same reason as ice_cream below:
	# Forced March was reshaped from a NetPlayerState resource streak into a
	# creature_played keyword GRANT, and a granted keyword has to ride the board
	# snapshot to reach the other peer. No port yet.
	"snecko_eye",
	"marathoners_sash",
	"deep_satchel",   # +1 card drawn each turn
	# ice_cream dropped 2026-07-25: reshaped from Miser's Coffer (banking, a pure
	# NetPlayerState resource tweak) into Iron Rations, a start-of-round BOARD
	# heal. Board effects need per-side host-authoritative plumbing that this
	# relic has no port for yet — same reason lantern sits out below.
	# lantern dropped 2026-07-16: reshaped into The Burnt Dispatches (caster-local
	# discard-pile manipulation, no net port yet — same class as the pile spells).
	"couriers_bag",   # +1 refill on turn 1
	"tome_of_many",   # +2 draw/turn (deck is 20, so always on — reads _ctx_deck)
	# 2026-07-08: happy_flower + mana_tide dropped here too, to match the solo relic
	# balance pass that merged them away (→ lantern / sigil_of_hunger). lantern already
	# covers the Command-trickle slot; both ids still exist in RelicDB so legacy peers
	# resolve fine — they're just no longer offered in the draft.
	# 2026-07-09 — first host-authoritative BOARD/HP relics (see _relic_active_for_side):
	"bulwark_engine",   # round start: your Armored creatures gain +1 max HP
	"gravewardens_pact",# first 3 of your creatures to die are reborn as 1/1 Imps
	"rear_guard_charm", # a front-row death buffs your back-row column-mate +1/+1
	"worn_spellbook",   # your damage spells deal +1 (net spell resolver, per caster)
]

## Battle potions legal in the skirmish draft. The host owns both players'
## remaining potions and resolves Command, draw, board, and HP effects. A client
## sends only IN_USE_POTION {pid,target?}; accepted results return in its private
## state plus the public board snapshot. Targeted bottles send the picked creature
## as an entity_id (the same handle targeted spells use), so friendly buffs,
## enemy strikes, and sacrifices resolve once with animation.
## Only grave_diggers_nip stays out — it
## purges Curses, which skirmish decks never carry, so it would drink for nothing.
const NET_POTION_POOL: Array[String] = [
	"inferno_vial",
	"chain_flask",
	"aegis_brew",
	"conscript_brew",
	"phoenix_brew",
	"healing",         # heal 8 HP (host-authoritative)
	"mana_surge",      # Rallying Horn — +2 Command this turn (caster-local)
	"insight_tonic",   # draw 3 cards (caster-local)
	# 2026-07-09 — net-aware potion targeting + host board resolvers:
	"bottled_fury",    # Sapper's Charge — 4 to a target enemy + its lane-mate
	"war_paint",       # Rampage +1 ATK on a target friendly (fight)
	"vampiric_draught",# Lifesteal on a target friendly + 4 HP caster heal
	"butchers_dram",   # sacrifice a target friendly → +3 Command (caster-local)
	"doomsday_draught",# detonate all your Doom creatures (non-targeted)
]

## Relics the PRACTICE BOT drafts from (2026-07-16, arsenal stage): only the
## host-authoritative BOARD/HP relics — they apply via slot reads on the host,
## so they work without the bot's turn machine honoring them (it runs flat
## 3+bank2 Command and never reads resource-local relics). The bot drafts NO
## potions: it never drinks, and an inert bottle on the foe rail would be a
## lying threat display.
const BOT_RELIC_POOL: Array[String] = [
	"bulwark_engine",
	"gravewardens_pact",
	"rear_guard_charm",
	"worn_spellbook",
]

## ── Net-playable spells (single source of truth) ────────────────────────────
## A spell is draftable in skirmish ONLY if the host can resolve it over the wire,
## so the draft never offers a card the player then can't play. Combat.gd reads the
## same lists via is_net_playable_spell() for its play-time gate, and
## tools/_probe_skirmish.gd verifies every custom id is a real draftable card.
##
## Built-in spell.type handlers (Combat._net_resolve_spell).
const NET_SPELL_TYPES: Array[String] = [
	"damage", "damage_face", "damage_all_enemies", "damage_all",
	"buff_atk", "buff_hp", "heal", "buff_all_atk",
]
## type:"custom" spell ids playable over the wire. Most resolve host-authoritatively
## in Combat._net_resolve_custom_spell; draw/Command/grave/pile/hand consequences
## for the client mutate the host-owned private state and return as EV_HAND_SET.
## Still OUT: gold economy (no shop) and Discover/tutor
## (needs shared-pool coordination) — see SKIRMISH_DENYLIST.
const NET_SPELL_CUSTOMS: Array[String] = [
	# NOTE: these are SPELL ids (card_data.spell.id), not card ids — the 2026-07-02
	# card overhaul renamed four (lay_on_hands→virulence, overwhelming_force→rout,
	# time_snare→doubled_hour, grave_pact→last_rites); keep this list on the NEW ids.
	"shove", "hex", "soul_swap", "testudo", "censer_light", "virulence",
	"immolate", "cataclysm", "inferno", "wildfire", "ambush", "plague_bell", "earthquake", "petard",
	# 2026-07-09 removal slate — pure board ops (_flank_push is side-agnostic and
	# "nearest flank" is symmetric, so no perspective flip; bolt's face spill uses
	# the caster channel like any face hit). All host-authoritative.
	"sappers_charge", "ballista_bolt", "scatter_line",
	"dark_pact", "apocalypse", "blood_tithe", "kings_command", "war_cry",
	"turncoat", "rout", "flame_bolt",
	# Board / utility spells — damage, summon, face, and formation effects resolved with the
	# primitives the net engine already has. Last Rites is plain conditional damage.
	"holy_smite", "ricochet", "provision", "baggage_train", "last_rites",
	# Temp-state spells: the net attack resolver honours freeze/stun/charge/poison and
	# the per-side round flags (Virulence / Doubled Hour); _net_decay_side_states
	# expires them at the end of the owning side's turn and the board snapshot ships
	# frz/stn/shd so the client renders the state.
	"doubled_hour", "frost_bolt", "hoarfrost", "venom_tip", "charge_spell",
	# Targeted tactical spells. Board effects stay host-authoritative; Quick Shot's
	# conditional draw returns through EV_DRAW to the caster's own machine.
	# (reckless_charge left this list 2026-07-05 — its Penance rework reads the
	# caster's hand for Curses, which skirmish decks never carry. unholy_bargain
	# left 2026-07-11: its rework pays the end-of-turn bill at the SOLO commit
	# only, so in net the surge would never be billed — it is SKIRMISH_DENYLISTed
	# and must not be declared net-playable.)
	"quick_shot", "slash", "patch_up", "smite_spell", "turbo",
	# Sacrifice spells — kill the caster's own target. Offering marks its repeatable
	# on-death effect for one extra resolution before the host-authoritative kill.
	"offering", "fuel_the_pyre",
	# Grave / exile spells — host-authoritative. Banish exiles (no on-death, no
	# discard); Reanimate raises the caster's last corpse; Grave Robbery returns a
	# corpse to the caster's hand (per-side death tracking + the EV_GIVE_CARD caster
	# channel); Echo re-resolves the caster's last host-resolved spell.
	"banish", "reanimate", "grave_robbery", "echo_spell",
	# Caster-local pile / hand spells — the hand, piles, and draws resolve on
	# the caster's OWN machine (_net_play_caster_local_spell); War Chant / Mass Grave
	# also forward a board consequence (Soldier count / fallen count) to the host.
	"recycle", "gambit", "war_chant", "mass_grave",
]


## True if a spell's card data resolves over the wire (built-in type or ported
## custom). Creatures always return false here — callers gate spells only.
func is_net_playable_spell(card_data: Dictionary) -> bool:
	var spell: Dictionary = card_data.get("spell", {})
	var stype: String = String(spell.get("type", ""))
	if stype in NET_SPELL_TYPES:
		return true
	if stype == "custom" and String(spell.get("id", "")) in NET_SPELL_CUSTOMS:
		return true
	return false


func skirmish_rarity_for(card_id: String) -> String:
	var override: String = String(SKIRMISH_RARITY_OVERRIDES.get(card_id, ""))
	if override != "":
		return override
	return String(CardDB.get_card_data(card_id).get("rarity", ""))


func skirmish_card_data(card_id: String) -> Dictionary:
	var data: Dictionary = CardDB.get_card_data(card_id)
	if data.is_empty():
		return data
	var base_rarity := String(data.get("rarity", "common"))
	var mp_rarity := skirmish_rarity_for(card_id)
	if mp_rarity != "":
		data["solo_rarity"] = base_rarity
		data["rarity"] = mp_rarity
	return data

## One per player. deck is an Array[String] of CardDB ids; deck_uids parallels it.
## HP/mana defaults are set by reset() from the constants above (kept off the
## field initializers so the inner class needn't reach back into the autoload).
class PlayerSlot:
	var deck: Array = []
	var deck_uids: Array = []
	var hero_hp: int = 30
	var hero_max_hp: int = 30
	var base_max_mana: int = 3
	var relics: Array = []          # drafted battle relic(s) — see NET_RELIC_POOL
	var potions: Array = []         # drafted battle potion(s) — see NET_POTION_POOL
	var card_upgrades: Dictionary = {}   # empty in v1
	## Lord identity (HeroDB id) picked in the lobby — cosmetic only (the plate
	## portrait + emote voice); never touches decks, HP, or rules.
	var hero_id: String = ""


var combat_mode: int = CombatMode.SOLO
## ONE-SHOT: a skirmish launch is in flight. Set by NetMatch._enter_combat_local
## immediately before its DEFERRED change_scene_to_file, and CONSUMED by the
## first Combat._ready that follows.
##
## It exists because `combat_mode` alone cannot distinguish the two states that
## reach Combat with a dead connection: a genuine campaign fight carrying a stale
## `combat_mode` from an earlier skirmish, and a skirmish whose connection was
## torn down inside the deferred swap. Those want opposite answers, and guessing
## wrong opens the player's live campaign run by accident — see the note at the
## mode decision in Combat._ready.
var launch_armed: bool = false
## True when the "opponent" is the local practice bot (no network peer). The host
## path runs exactly as in a real match; Combat just drives slot 1 via SkirmishBot
## instead of waiting for remote intents, and NetMatch emulates the peer handshake.
var vs_bot: bool = false
var rng_seed: int = 0
var slots: Array[PlayerSlot] = []
## Index into `slots` for the local player (== NetMatch.local_player_index).
var local_index: int = -1

## ── Match format (Best-of-N series) ─────────────────────────────────────────
## best_of is 1 (single game) or 3 (first to 2). Set from NetMatch.best_of in
## begin_session so the choice survives the deck-acquisition scene → combat. The
## series tallies persist across the per-game combat-scene relaunches because this
## autoload is NOT reset between games — only the heroes/board reset, via
## NetMatch._enter_combat_local. The Best-of-3 combat code reads these.
var best_of: int = 1
var series_wins: Array[int] = [0, 0]
var series_game: int = 1

## ── Arsenal size (host-chosen, one pair for BOTH players) ───────────────────
## How many battle-relic / battle-potion picks the shared Arsenal stage offers
## each side. Set from NetMatch.arsenal_relics / .arsenal_potions in
## begin_session for the same reason best_of is: this autoload is NOT reset
## between the games of a series, so the number survives the deck screen →
## combat → rematch relaunches. Every consumer reads THESE — the stage that
## deals the slates (NetDeckBuilder._begin_arsenal) and the host's own authority
## boundary (arsenal_source_offers / validate_loadout_event) — so the offers a
## peer could have seen and the offers it is allowed to keep cannot drift apart.
var arsenal_relics: int = ARSENAL_RELIC_ROUNDS
var arsenal_potions: int = ARSENAL_POTION_ROUNDS


## The most rounds the lobby may offer, and the clamp every consumer applies.
## BOTH ARE DERIVED — nothing here is a number somebody liked the look of, and
## the limits below are the MEASURED points where something actually breaks.
##
## RELICS stop at the pool size because a relic is held or not held: duplicates
## are refused by validate_loadout_event and `_has_relic` is a membership test,
## so a round past the pool's last distinct id cannot add anything. (Tables stay
## full all the way there — see deal_arsenal_slate's lap rule.) Measured against
## the HUD at the ceiling: Combat's left relic rail lays 14 chips as 5x3 at its
## own 44px legibility floor, ending at x264 against the board's edge at 272.
##
## POTIONS stop at the belt. The combat belt is the drafted count, and its shelf
## is 16 + n*52 + (n-1)*6 wide against that same x272: n=4 ends at 248, n=5 at
## 300 — through the board. The pool (13) would allow more; the geometry does not.
func arsenal_relic_max() -> int:
	return NET_RELIC_POOL.size()


func arsenal_potion_max() -> int:
	return mini(NET_POTION_POOL.size(), ARSENAL_POTION_BELT_CAP)


## Deal one Arsenal table from `pool`, carrying the cross-round block list in
## `seen` (mutated). THE LAP RULE: an offered id never re-deals — UNTIL the
## unseen remainder can no longer fill a whole table, at which point the block
## list is cleared and a new lap begins.
##
## Without it the stage is hard-capped at pool/3 rounds: a 5th relic table would
## be dealt SHORT (2 tiles) and a 6th EMPTY, and an empty table auto-passes a
## whole category the header just promised. With it, every table is full at any
## setting the ceilings above allow. At the shipped 3+2 no lap ever triggers, so
## the default stage deals exactly what it has always dealt.
##
## It is deliberately CHOICE-INDEPENDENT — a function of (rng stream, pool) and
## nothing else. The host must rebuild the identical tables in
## arsenal_source_offers to validate a peer's picks, and blocking ids the player
## already HOLDS would make the deal depend on their takes; passes are invisible
## on the wire, so the host could not reproduce it without enumerating every
## placement. The stage handles the consequence (a second lap may re-offer
## something you already took) by marking that tile as held and refusing it.
func deal_arsenal_slate(pool: Array, rng: RandomNumberGenerator,
		seen: Array) -> Array[String]:
	if pool.size() - seen.size() < ARSENAL_SLATE_SIZE:
		seen.clear()
	var offered: Array[String] = deal_unique_cards(pool, ARSENAL_SLATE_SIZE, rng, seen)
	seen.append_array(offered)
	return offered

## uid = slot_index * UID_SLOT_STRIDE + draft_position. Deterministic so the host
## and the client compute the SAME uid for the same physical card without any
## negotiation — both draft each slot in the same pick order. The host keys all
## per-card combat state by uid, and the client references its hand cards by uid
## in play intents, so the two id spaces MUST agree.
const UID_SLOT_STRIDE: int = 100000


## Read the launch latch and clear it in the same breath. Reading is what spends
## it, so a launch can only ever be claimed by ONE Combat boot.
func consume_launch_armed() -> bool:
	var armed := launch_armed
	launch_armed = false
	return armed


func reset() -> void:
	combat_mode = CombatMode.SOLO
	launch_armed = false
	vs_bot = false
	rng_seed = 0
	local_index = -1
	arsenal_relics = ARSENAL_RELIC_ROUNDS
	arsenal_potions = ARSENAL_POTION_ROUNDS
	slots = []
	for _i in 2:
		var s := PlayerSlot.new()
		s.hero_hp = START_HP
		s.hero_max_hp = START_HP
		s.base_max_mana = BASE_MAX_MANA
		slots.append(s)


## Restore both heroes to full HP without touching the drafted decks/uids — used
## by a REMATCH so the same warbands fight again from a clean slate.
func refresh_heroes() -> void:
	for s in slots:
		s.hero_hp = START_HP
		s.hero_max_hp = START_HP


## Configure a fresh session from the live NetMatch connection. EVERY
## deck-acquisition scene (draft / constructed / quick / sealed) calls this first
## in _ready: it clears the slots, sets the net combat mode + local index + shared
## seed, copies the chosen match format, and zeroes the series. After this the
## scene fills the LOCAL deck (and exchanges with the opponent), then the host
## calls NetMatch.launch_combat.
func begin_session() -> void:
	reset()
	vs_bot = NetMatch.vs_bot   # carry the practice-bot flag past reset() into combat
	combat_mode = CombatMode.NET_HOST if NetMatch.is_host else CombatMode.NET_CLIENT
	local_index = NetMatch.local_player_index
	rng_seed = NetMatch.match_seed
	best_of = NetMatch.best_of
	# The host's arsenal size, adopted identically on both machines (it rode the
	# match-start envelope). Clamped here rather than trusted: this is the number
	# the host's own loadout authority will later validate the peer against.
	arsenal_relics = clampi(NetMatch.arsenal_relics, 0, arsenal_relic_max())
	arsenal_potions = clampi(NetMatch.arsenal_potions, 0, arsenal_potion_max())
	# Lord identities: both picks were exchanged in the lobby (and the match-start
	# envelope carried the canonical pair), so each machine seats them by index.
	if local_index >= 0 and local_index < slots.size():
		slots[local_index].hero_id = NetMatch.local_hero
		slots[1 - local_index].hero_id = NetMatch.remote_hero
	reset_series()


## Lord id for a slot, defaulting to the roster's default lord so a pick that
## never happened (old builds, probes) still resolves a portrait + emote voice.
func hero_for(index: int) -> String:
	if index >= 0 and index < slots.size() and slots[index].hero_id != "":
		return slots[index].hero_id
	return HeroDB.DEFAULT_HERO


# ── Match-format helpers (Best-of-N) ────────────────────────────────────────

func reset_series() -> void:
	series_wins = [0, 0]
	series_game = 1

## Games one side must win to take the match (Bo1 → 1, Bo3 → 2).
func games_to_win() -> int:
	return best_of / 2 + 1

## Record a finished game's winner by slot index (0/1); -1 (draw) advances the
## game counter without crediting either side.
func record_game_winner(winner_index: int) -> void:
	if winner_index == 0 or winner_index == 1:
		series_wins[winner_index] += 1
	series_game += 1

## Slot index that has clinched the series (>= games_to_win), or -1 if still live.
func series_leader() -> int:
	var need := games_to_win()
	for i in 2:
		if series_wins[i] >= need:
			return i
	return -1


# ── Mode-registry helpers ───────────────────────────────────────────────────

static func mode_def(mode: int) -> Dictionary:
	for d in MODE_DEFS:
		if int(d.get("id", -1)) == mode:
			return d
	return MODE_DEFS[0]

static func mode_scene(mode: int) -> String:
	return String(mode_def(mode).get("scene", MODE_DEFS[0]["scene"]))

static func mode_name(mode: int) -> String:
	return String(mode_def(mode).get("name", "Draft"))

static func mode_blurb(mode: int) -> String:
	return String(mode_def(mode).get("blurb", ""))

## Mode ids whose scene file exists in this build. The lobby only offers these, so
## a mode whose scene hasn't been built yet simply doesn't appear (each lights up
## as its scene lands). DRAFT is guaranteed as a fallback.
static func available_modes() -> Array:
	var out: Array = []
	for d in MODE_DEFS:
		if ResourceLoader.exists(String(d.get("scene", ""))):
			out.append(int(d.get("id", 0)))
	if out.is_empty():
		out.append(MatchMode.DRAFT)
	return out


## Append a drafted card id to a player's deck with a deterministic uid (see
## UID_SLOT_STRIDE). Returns the uid, or -1 on a bad slot index.
func add_card_to(slot_index: int, card_id: String) -> int:
	if slot_index < 0 or slot_index >= slots.size():
		return -1
	var pos: int = slots[slot_index].deck.size()
	var uid: int = slot_index * UID_SLOT_STRIDE + pos
	slots[slot_index].deck.append(card_id)
	slots[slot_index].deck_uids.append(uid)
	return uid


func get_slot(slot_index: int) -> PlayerSlot:
	if slot_index < 0 or slot_index >= slots.size():
		return null
	return slots[slot_index]


func local_slot() -> PlayerSlot:
	return get_slot(local_index)


func opponent_index() -> int:
	return 1 - local_index if local_index >= 0 else -1


## The curated set of CardDB ids legal to draft in skirmish v1. Every draftable
## creature/spell (DRAFTABLE_RARITIES), minus SKIRMISH_DENYLIST, minus curses and
## anything that isn't a creature/spell. Armaments stay campaign-only until the
## net intent/replay protocol has an explicit equip action. The host and client
## both call this to
## build identical triplet pools from the shared seed, so the order MUST be
## stable across machines — get_pool_by_rarity walks an unordered Dictionary, so
## we sort the final list.
func skirmish_legal_pool() -> Array:
	var pool: Array[String] = []
	for rarity in DRAFTABLE_RARITIES:
		for id in CardDB.get_pool_by_rarity(rarity):
			if SKIRMISH_DENYLIST.has(id):
				continue
			if CardDB.is_curse(id):
				continue
			var d := CardDB.get_card_data(id)
			var dtype: String = String(d.get("type", ""))
			# Spells must be net-playable (the host can resolve them); a drafted card
			# the player can't cast is worse than not offering it. Creatures always pass.
			if dtype == "spell" and not is_net_playable_spell(d):
				continue
			if dtype in ["creature", "spell"]:
				pool.append(id)
	pool.sort()
	return pool


## Validate the only peer-supplied persistent combat input: its finished deck
## and arsenal.  The UI constrains these already; this is the authority boundary
## for modified clients and malformed relay traffic.
func validate_loadout_event(event: Dictionary, mode: int = -1) -> String:
	if typeof(event.get("cards", null)) != TYPE_ARRAY:
		return "loadout_cards_type"
	if typeof(event.get("relics", [])) != TYPE_ARRAY \
			or typeof(event.get("potions", [])) != TYPE_ARRAY:
		return "loadout_arsenal_type"
	var cards: Array = event.get("cards", [])
	var loadout_relics: Array = event.get("relics", [])
	var loadout_potions: Array = event.get("potions", [])
	if cards.size() != DECK_TARGET:
		return "loadout_deck_size"
	# The cap is THIS match's arsenal size, not the old fixed 3+2 — a peer may
	# never submit more items than the stage it was actually shown could hand out.
	if loadout_relics.size() > arsenal_relics or loadout_potions.size() > arsenal_potions:
		return "loadout_arsenal_size"

	var legal: Dictionary = {}
	for legal_id in skirmish_legal_pool():
		legal[String(legal_id)] = true
	var counts: Dictionary = {}
	for raw_id in cards:
		if typeof(raw_id) != TYPE_STRING:
			return "loadout_card_type"
		var id := String(raw_id)
		if not legal.has(id):
			return "loadout_card_illegal"
		counts[id] = int(counts.get(id, 0)) + 1
	var copy_cap := 0
	if mode in [MatchMode.CONSTRUCTED, MatchMode.QUICK]:
		copy_cap = DECK_COPY_CAP
	elif mode == MatchMode.SEALED:
		copy_cap = SEALED_MAX_PER_ID
	if copy_cap > 0:
		for count in counts.values():
			if int(count) > copy_cap:
				return "loadout_copy_cap"

	var seen: Dictionary = {}
	for raw_relic in loadout_relics:
		if typeof(raw_relic) != TYPE_STRING:
			return "loadout_relic_type"
		var relic_id := String(raw_relic)
		if relic_id not in NET_RELIC_POOL or seen.has(relic_id):
			return "loadout_relic_illegal"
		seen[relic_id] = true
	seen.clear()
	for raw_potion in loadout_potions:
		if typeof(raw_potion) != TYPE_STRING:
			return "loadout_potion_type"
		var potion_id := String(raw_potion)
		if potion_id not in NET_POTION_POOL or seen.has(potion_id):
			return "loadout_potion_illegal"
		seen[potion_id] = true
	return ""


## Prove that a structurally valid submitted loadout could actually have been
## earned from the deterministic sources of the active mode. This runs on the
## host before it accepts the peer's final handoff; clients never supply the
## seed, side, or Quick/Sealed configuration used here.
func validate_loadout_provenance(event: Dictionary, mode: int,
		match_seed_value: int, slot_index: int,
		source_config: Dictionary = {}) -> String:
	if slot_index < 0 or slot_index >= 2:
		return "loadout_source_side"
	if typeof(event.get("cards", null)) != TYPE_ARRAY \
			or typeof(event.get("relics", [])) != TYPE_ARRAY \
			or typeof(event.get("potions", [])) != TYPE_ARRAY:
		return "loadout_source_type"
	var cards: Array = event.get("cards", [])
	var relics: Array = event.get("relics", [])
	var potions: Array = event.get("potions", [])
	var arsenal_reason := _validate_arsenal_source(relics, potions,
		match_seed_value, slot_index)
	if arsenal_reason != "":
		return arsenal_reason
	match mode:
		MatchMode.QUICK:
			if not _source_config_is_valid(source_config):
				return "loadout_source_config"
			var expected := quick_source_deck(match_seed_value, slot_index,
				bool(source_config.get("mirror", false)), int(source_config.get("seed", 0)))
			if cards != expected:
				return "loadout_quick_source"
		MatchMode.SEALED:
			if not _source_config_is_valid(source_config):
				return "loadout_source_config"
			var avail := sealed_source_pool(match_seed_value, slot_index,
				bool(source_config.get("mirror", false)), int(source_config.get("seed", 0)))
			var used: Dictionary = {}
			for raw_id in cards:
				var id := String(raw_id)
				used[id] = int(used.get(id, 0)) + 1
				if int(used[id]) > int(avail.get(id, 0)):
					return "loadout_sealed_source"
		MatchMode.DRAFT:
			if not _draft_cards_attainable(cards, match_seed_value, slot_index):
				return "loadout_draft_source"
	return ""


func _source_config_is_valid(source_config: Dictionary) -> bool:
	return typeof(source_config.get("mirror", null)) == TYPE_BOOL \
		and typeof(source_config.get("seed", null)) == TYPE_INT


## Quick and Sealed share the same host-selected source seed formula.
func _source_effective_seed(match_seed_value: int, slot_index: int,
		mirror: bool, sub_seed: int) -> int:
	var base := match_seed_value
	if sub_seed != 0:
		base = base ^ (sub_seed * 0x9E3779B9)
	if not mirror:
		base = base ^ ((slot_index + 1) * 0x6C62272E)
	return base


## Exact Quick deck, including the order that feeds deterministic card UIDs and
## draw shuffling. Reproduces NetQuick._regenerate_deck without scene state.
func quick_source_deck(match_seed_value: int, slot_index: int,
		mirror: bool, sub_seed: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _source_effective_seed(match_seed_value, slot_index, mirror, sub_seed)
	var source: Array = skirmish_legal_pool()
	var out: Array[String] = deal_weighted_cards(source, DECK_TARGET, rng,
		SKIRMISH_DRAFT_WEIGHTS)
	if out.size() >= DECK_TARGET:
		return out
	var counts: Dictionary = {}
	for existing_id in out:
		counts[existing_id] = int(counts.get(existing_id, 0)) + 1
	var guard := 0
	while out.size() < DECK_TARGET and guard < 4000:
		guard += 1
		if source.is_empty():
			break
		var pick_id := String(source[rng.randi() % source.size()])
		var count := int(counts.get(pick_id, 0))
		if count < DECK_COPY_CAP:
			out.append(pick_id)
			counts[pick_id] = count + 1
	return out


## Deterministic Sealed pool, returned as id -> opened copies. Reproduces
## NetSealed._regenerate_pool without trusting the submitting peer.
func sealed_source_pool(match_seed_value: int, slot_index: int,
		mirror: bool, sub_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _source_effective_seed(match_seed_value, slot_index, mirror, sub_seed)
	var source: Array = skirmish_legal_pool()
	var out: Dictionary = {}
	var opened: Array[String] = deal_weighted_cards(source,
		mini(SEALED_POOL_SIZE, source.size()), rng, SKIRMISH_DRAFT_WEIGHTS)
	for opened_id in opened:
		out[opened_id] = 1
	var rolled := opened.size()
	var guard := 0
	while rolled < SEALED_POOL_SIZE and guard < 6000 and not source.is_empty():
		guard += 1
		var roll_id := String(source[rng.randi() % source.size()])
		var count := int(out.get(roll_id, 0))
		if count < SEALED_MAX_PER_ID:
			out[roll_id] = count + 1
			rolled += 1
	return out


## Rebuild this match's Arsenal slates for one side (arsenal_relics relic rounds
## then arsenal_potions potion rounds — the host's lobby pick, which both peers
## adopted at match start, so the two machines rebuild the SAME offers off the
## same seed). Final relic/potion lists retain
## chronological choice order, so they must fit these offers as a subsequence;
## skipped slates are allowed, forged never-offered items are not.
func arsenal_source_offers(match_seed_value: int, slot_index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed_value ^ (0xA25E * (slot_index + 1))
	# ONE BLOCK LIST PER CATEGORY. They used to share one — harmless while the
	# rule was only "never re-deal" (the pools are disjoint, so a potion id could
	# never block a relic), but the lap rule reads seen.SIZE against a pool size,
	# and a shared list counts the other category's ids into that arithmetic.
	var relic_seen: Array = []
	var potion_seen: Array = []
	var relic_rounds: Array = []
	# Same dealer the live stage runs, lap rule included — this reconstruction is
	# only an authority boundary if it is the SAME rule, not a second copy of it.
	for _round in arsenal_relics:
		relic_rounds.append(deal_arsenal_slate(NET_RELIC_POOL, rng, relic_seen))
	var potion_rounds: Array = []
	for _round in arsenal_potions:
		potion_rounds.append(deal_arsenal_slate(NET_POTION_POOL, rng, potion_seen))
	return {"relics": relic_rounds, "potions": potion_rounds}


func _validate_arsenal_source(relics: Array, potions: Array,
		match_seed_value: int, slot_index: int) -> String:
	var offers := arsenal_source_offers(match_seed_value, slot_index)
	if not _source_choices_fit_rounds(relics, offers.get("relics", [])):
		return "loadout_relic_source"
	if not _source_choices_fit_rounds(potions, offers.get("potions", [])):
		return "loadout_potion_source"
	return ""


func _source_choices_fit_rounds(choices: Array, rounds: Array) -> bool:
	var round_index := 0
	for raw_id in choices:
		var id := String(raw_id)
		var found := false
		while round_index < rounds.size():
			var offered: Array = rounds[round_index]
			round_index += 1
			if offered.has(id):
				found = true
				break
		if not found:
			return false
	return true


## Return all twenty draft slates for one explicit placement of up to two
## rerolls. The UI never transmits rerolls, so host validation below enumerates
## every legal placement rather than trusting a client-supplied transcript.
func draft_offers_for_rerolls(match_seed_value: int, slot_index: int,
		first_reroll_pick: int = -1, second_reroll_pick: int = -1) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed_value + (slot_index + 1) * 0x9E3779B1
	var source: Array = skirmish_legal_pool()
	var buckets := rarity_buckets(source)
	var bags: Dictionary = {}
	var out: Array = []
	for pick_index in DECK_TARGET:
		var deals := 1
		if pick_index == first_reroll_pick:
			deals += 1
		if pick_index == second_reroll_pick:
			deals += 1
		var offered: Array[String] = []
		for _deal in deals:
			offered = deal_weighted_triplet(buckets, bags, rng,
				SKIRMISH_DRAFT_WEIGHTS)
		out.append(offered)
	return out


func _draft_cards_match_reroll_plan(cards: Array, match_seed_value: int,
		slot_index: int, first_reroll_pick: int, second_reroll_pick: int) -> bool:
	var offers := draft_offers_for_rerolls(match_seed_value, slot_index,
		first_reroll_pick, second_reroll_pick)
	if offers.size() != cards.size():
		return false
	for i in cards.size():
		var offered: Array = offers[i]
		if not offered.has(String(cards[i])):
			return false
	return true


func _draft_cards_attainable(cards: Array, match_seed_value: int,
		slot_index: int) -> bool:
	if cards.size() != DECK_TARGET:
		return false
	if _draft_cards_match_reroll_plan(cards, match_seed_value, slot_index, -1, -1):
		return true
	if DRAFT_REROLL_CAP < 1:
		return false
	for first in DECK_TARGET:
		if _draft_cards_match_reroll_plan(cards, match_seed_value, slot_index, first, -1):
			return true
	if DRAFT_REROLL_CAP < 2:
		return false
	# With the fixed two-reroll budget this covers the 210 ways to spend both
	# rerolls (including both on the same slate), for 231 deterministic paths total.
	for first in DECK_TARGET:
		for second in range(first, DECK_TARGET):
			if _draft_cards_match_reroll_plan(cards, match_seed_value, slot_index,
					first, second):
				return true
	return false

## Deterministic bag helpers for skirmish card generation. The old generated
## deck modes sampled from the full pool every time, so a fair seed could still
## clump the same few ids. These helpers deal without replacement first; callers
## can opt into copy fallback only when the source pool is genuinely too small.
func shuffled_card_bag(source: Array, rng: RandomNumberGenerator,
		blocked: Array = []) -> Array[String]:
	var bag: Array[String] = []
	for raw_id in source:
		var id := String(raw_id)
		if blocked.has(id):
			continue
		bag.append(id)
	for i in range(bag.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: String = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	return bag


func deal_unique_cards(source: Array, count: int, rng: RandomNumberGenerator,
		blocked: Array = []) -> Array[String]:
	var bag := shuffled_card_bag(source, rng, blocked)
	var out: Array[String] = []
	while out.size() < count and not bag.is_empty():
		out.append(String(bag.pop_back()))
	return out


## ── Rarity-weighted draft dealing ───────────────────────────────────────────
## The draft's answer to "make the odds like act 3": instead of a flat bag over
## the whole pool (whose rarity mix just mirrored how many of each exist), each
## triplet slot rolls a RARITY against the act reward weights, then draws an id of
## that rarity. See NetDraft._roll_triplet + CardDB.act_rarity_weights.

## Split a legal id list into the three reward tiers (common / uncommon / rare).
## STARTER cards are deliberately dropped — act rewards, whose odds the draft
## mirrors, never offer them. Returns {"common":[...], "uncommon":[...], "rare":[...]}.
func rarity_buckets(source: Array) -> Dictionary:
	var out: Dictionary = {}
	for tier in SKIRMISH_RARITY_TIERS:
		out[tier] = []
	for raw_id in source:
		var id := String(raw_id)
		var rarity := skirmish_rarity_for(id)
		if out.has(rarity):
			out[rarity].append(id)
	return out


## Deal one weighted triplet: three DISTINCT ids, each slot's rarity rolled against
## `weights` [common, uncommon, rare] out of 100, then an id drawn from that
## rarity's bag WITHOUT replacement. `buckets` is the rarity→ids map from
## rarity_buckets(); `bags` is the caller's running draw-down state (rarity→shuffled
## ids), mutated here and refilled from `buckets` when a tier empties — so across a
## whole draft a rarity's ids don't recur until its bag cycles. Falls back to any
## non-empty tier if the rolled one is dry. Deterministic over `rng` (the salted
## per-player stream), so the slate is reproducible from the match seed.
func deal_weighted_triplet(buckets: Dictionary, bags: Dictionary,
		rng: RandomNumberGenerator, weights: Array) -> Array[String]:
	var out: Array[String] = []
	var guard := 0
	while out.size() < 3 and guard < 500:
		guard += 1
		var id := _draw_weighted_bag(_roll_rarity(rng, weights), buckets, bags, rng)
		if id == "":
			id = _draw_any_bag(buckets, bags, rng)   # rolled tier ran dry
		if id == "":
			break                                    # pool genuinely exhausted
		if not out.has(id):
			out.append(id)
	return out


func deal_weighted_cards(source: Array, count: int, rng: RandomNumberGenerator,
		weights: Array, blocked: Array = []) -> Array[String]:
	var filtered: Array[String] = []
	for raw_id in source:
		var id := String(raw_id)
		if blocked.has(id):
			continue
		filtered.append(id)
	var buckets := rarity_buckets(filtered)
	var bags: Dictionary = {}
	var out: Array[String] = []
	var guard := 0
	var guard_limit: int = maxi(500, count * 80)
	while out.size() < count and guard < guard_limit:
		guard += 1
		var id := _draw_weighted_bag(_roll_rarity(rng, weights), buckets, bags, rng)
		if id == "":
			id = _draw_any_bag(buckets, bags, rng)
		if id == "":
			break
		if not out.has(id):
			out.append(id)
	return out


## Roll a rarity name against [common, uncommon, rare] weights (percentages).
func _roll_rarity(rng: RandomNumberGenerator, weights: Array) -> String:
	var c: int = int(weights[0]) if weights.size() > 0 else 0
	var u: int = int(weights[1]) if weights.size() > 1 else 0
	var r: int = int(weights[2]) if weights.size() > 2 else 0
	var roll: int = rng.randi() % 100
	if roll < c:
		return "common"
	elif roll < c + u:
		return "uncommon"
	elif weights.size() <= 3 or roll < c + u + r:
		return "rare"
	return "white"


## Pop one id from a rarity's draw bag, refilling+shuffling it from `buckets` when
## empty. Returns "" only if that rarity has no legal cards at all.
func _draw_weighted_bag(rarity: String, buckets: Dictionary, bags: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var bag: Array = bags.get(rarity, [])
	if bag.is_empty():
		bag = shuffled_card_bag(buckets.get(rarity, []), rng)
		bags[rarity] = bag
		if bag.is_empty():
			return ""
	return String(bag.pop_back())


## Fallback for a dry rolled tier: try the reward tiers in a fixed order.
func _draw_any_bag(buckets: Dictionary, bags: Dictionary,
		rng: RandomNumberGenerator) -> String:
	for rarity in SKIRMISH_RARITY_TIERS:
		var id := _draw_weighted_bag(rarity, buckets, bags, rng)
		if id != "":
			return id
	return ""
