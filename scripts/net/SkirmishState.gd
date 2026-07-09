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

## The act whose reward ODDS the draft rolls at. Act 3 (30/50/20 common/uncommon/
## rare — see CardDB.ACT_REWARD_WEIGHTS) so a drafted warband feels like a
## late-campaign deck rather than a flat sample of the pool. See NetDraft and
## deal_weighted_triplet below.
const DRAFT_ACT: int = 3

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
	# Gold economy — no shop/gold in skirmish v1.
	"scavenger", "pillage",
	# Draw / discard / exhaust pile mutation that still lacks a net port.
	# (unholy_bargain came off via the EV_DRAW channel; gambit / mass_grave / turbo
	# came off via the caster-local pile path — see NET_SPELL_CUSTOMS. gravedigger +
	# bloodhound came off 2026-07-09: their draw routes through the same host→owner
	# EV_DRAW channel via _battlecry_draw, so the owner draws on its own machine.)
	# Discover / tutor — injects arbitrary cards into hand; needs pool coordination.
	"familiar", "scholar", "lost_tome", "war_council", "treasure_hunter",
	# Solo campaign systems: Old Campaigner reads the run's kill ledger and
	# Sin-Eater eats Curses — neither exists in skirmish.
	"ironclad_veteran", "sin_eater",
	# 2026-07-07 fun slate: The Volunteer rides the dismissal (hand-local in
	# net — its muster wouldn't sync), Muster the Fallen reads the run's Roll
	# of the Fallen, and Slow Match / Trebuchet lack net resolver ports
	# (hand-fuse state / start-round volley).
	"volunteer", "muster_fallen", "slow_match", "trebuchet",
]

## Draftable rarities for skirmish. Mirrors CardDB's draftable convention (starter
## + common + uncommon + rare); curses and enemy-only cards are excluded by rarity
## and filtered defensively below.
const DRAFTABLE_RARITIES: Array[String] = ["starter", "common", "uncommon", "rare"]

## Battle relics legal in the skirmish draft. Two kinds qualify:
##   1. RESOURCE-LOCAL — touches only the owner's hand refill / Command / banking /
##      card cost, which each peer computes for itself inside its own _start_round
##      (net turns route through it). Combat._has_relic reads the local slot.
##   2. BOARD/HP, HOST-AUTHORITATIVE (2026-07-09) — the effect mutates the board or
##      a hero's HP at a hook that already runs per-side on the host, gated through
##      Combat._relic_active_for_side(owner_is_enemy, id). The host applies the
##      owner's relic to the owner's side and the board snapshot animates it on the
##      client. To add one: wire the hook to _relic_active_for_side, then list it here.
## Still OUT: gold/map/reward/deck-upgrade relics (no such systems in skirmish) and
## pile/draw relics owned by the client (need caster-local routing like the draw spells).
const NET_RELIC_POOL: Array[String] = [
	"ember_crown",
	"pact_of_embers",
	"last_breath",
	"cavalry_sigil",
	"spell_tome",
	"mana_drunkard",
	"snecko_eye",
	"marathoners_sash",
	"deep_satchel",   # hand refills to 6 instead of 5
	"ice_cream",      # Miser's Coffer — banking uncapped
	"lantern",        # +1 Command on turn 1
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

## Battle potions legal in the skirmish draft. Command and draw are pure
## caster-local (each peer owns its hand/Command); every board/HP effect is
## host-authoritative, routed through IN_USE_POTION → _net_apply_host_potion and
## board-synced back. TARGETED bottles came in 2026-07-09: the caster ships the
## picked creature to the host as an entity_id (the same handle targeted spells
## use), so friendly buffs / enemy strikes / sacrifices all resolve for both peers
## with animation. Combat reads the drafted potion(s) from the local slot
## (_ctx_potions) and consumes them there. Only grave_diggers_nip stays out — it
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
	"vampiric_draught",# Lifelink on a target friendly + 4 HP caster heal
	"butchers_dram",   # sacrifice a target friendly → +3 Command (caster-local)
	"doomsday_draught",# detonate all your Doom creatures (non-targeted)
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
## in Combat._net_resolve_custom_spell; draw/Command spells use the EV_DRAW/EV_MANA
## caster channel; grave spells use per-side death tracking + EV_GIVE_CARD; and the
## caster-local pile/hand spells resolve on the caster's own machine via
## _net_play_caster_local_spell. Still OUT: gold economy (no shop) and Discover/tutor
## (needs shared-pool coordination) — see SKIRMISH_DENYLIST.
const NET_SPELL_CUSTOMS: Array[String] = [
	# NOTE: these are SPELL ids (card_data.spell.id), not card ids — the 2026-07-02
	# card overhaul renamed four (lay_on_hands→virulence, overwhelming_force→rout,
	# time_snare→doubled_hour, grave_pact→last_rites); keep this list on the NEW ids.
	"shove", "hex", "soul_swap", "shield_wall", "censer_light", "virulence",
	"immolate", "cataclysm", "inferno", "wildfire", "ambush", "plague_bell", "earthquake", "petard",
	"dark_pact", "apocalypse", "blood_tithe", "kings_command", "war_cry",
	"inspire", "rout", "flame_bolt",
	# Board / utility spells — pure damage / summon / face / Command resolved with the
	# primitives the net engine already has. Last Rites is plain conditional damage.
	"holy_smite", "ricochet", "provision", "adrenaline", "last_rites",
	# Temp-state spells: the net attack resolver honours freeze/stun/charge/poison and
	# the per-side round flags (Virulence / Doubled Hour); _net_decay_side_states
	# expires them at the end of the owning side's turn and the board snapshot ships
	# frz/stn/shd so the client renders the state.
	"doubled_hour", "frost_bolt", "hoarfrost", "venom_tip", "charge_spell",
	# Draw / Command spells — resolved via the host→caster EV_DRAW / EV_MANA channel
	# (the caster draws/gains on its OWN client). No hand-picker or pile reads needed.
	# (reckless_charge left this list 2026-07-05 — its Penance rework reads the
	# caster's hand for Curses, which skirmish decks never carry.)
	"quick_shot", "slash", "patch_up", "smite_spell", "unholy_bargain",
	# Sacrifice spells — kill the caster's own target (the inert relic/reactive hooks
	# solo's sacrifice path fires don't exist in skirmish, so a plain kill is faithful).
	"offering", "fuel_the_pyre",
	# Grave / exile spells — host-authoritative. Banish exiles (no on-death, no
	# discard); Reanimate raises the caster's last corpse; Grave Robbery returns a
	# corpse to the caster's hand (per-side death tracking + the EV_GIVE_CARD caster
	# channel); Echo re-resolves the caster's last host-resolved spell.
	"banish", "reanimate", "grave_robbery", "echo_spell",
	# Caster-local pile / hand spells — the hand, piles, Command and draw resolve on
	# the caster's OWN machine (_net_play_caster_local_spell); War Chant / Mass Grave
	# also forward a board consequence (Soldier count / discard size) to the host.
	"recycle", "gambit", "turbo", "war_chant", "mass_grave",
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


var combat_mode: int = CombatMode.SOLO
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

## uid = slot_index * UID_SLOT_STRIDE + draft_position. Deterministic so the host
## and the client compute the SAME uid for the same physical card without any
## negotiation — both draft each slot in the same pick order. The host keys all
## per-card combat state by uid, and the client references its hand cards by uid
## in play intents, so the two id spaces MUST agree.
const UID_SLOT_STRIDE: int = 100000


func reset() -> void:
	combat_mode = CombatMode.SOLO
	vs_bot = false
	rng_seed = 0
	local_index = -1
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
	reset_series()


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
## anything that isn't a creature/spell. The host and client both call this to
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
	var out: Dictionary = {"common": [], "uncommon": [], "rare": []}
	for raw_id in source:
		var id := String(raw_id)
		var rarity := String(CardDB.get_card_data(id).get("rarity", ""))
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


## Roll a rarity name against [common, uncommon, rare] weights (percentages).
func _roll_rarity(rng: RandomNumberGenerator, weights: Array) -> String:
	var c: int = int(weights[0]) if weights.size() > 0 else 0
	var u: int = int(weights[1]) if weights.size() > 1 else 0
	var roll: int = rng.randi() % 100
	if roll < c:
		return "common"
	elif roll < c + u:
		return "uncommon"
	return "rare"


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
	for rarity in ["common", "uncommon", "rare"]:
		var id := _draw_weighted_bag(rarity, buckets, bags, rng)
		if id != "":
			return id
	return ""
