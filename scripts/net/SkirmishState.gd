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

const START_HP: int = 25
const BASE_MAX_MANA: int = 3
const DECK_TARGET: int = 20   # cards drafted per player

## Card ids barred from the skirmish draft even though their rarity is draftable —
## cards that assume single-player context (gold economy, draw/discard/exhaust
## pile mutation that the client must mirror, or Discover-style hand enrichment;
## see plan §13.3). Curated 2026-06-16; grow as pile-sync lands post-v1.
const SKIRMISH_DENYLIST: Array[String] = [
	# Gold economy — no shop/gold in skirmish v1.
	"scavenger", "pillage",
	# Draw / discard / exhaust pile mutation — needs per-deck pile sync (deferred).
	# (unholy_bargain came OFF this list — pure draw, now handled by the EV_DRAW channel.)
	"gravedigger", "bloodhound", "gambit", "mass_grave", "turbo",
	# Discover / tutor — injects arbitrary cards into hand; needs pool coordination.
	"familiar", "scholar", "lost_tome", "war_council", "treasure_hunter",
]

## Draftable rarities for skirmish. Mirrors CardDB's draftable convention (starter
## + common + uncommon + rare); curses and enemy-only cards are excluded by rarity
## and filtered defensively below.
const DRAFTABLE_RARITIES: Array[String] = ["starter", "common", "uncommon", "rare"]

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
## type:"custom" spell ids with a perspective-aware handler in
## Combat._net_resolve_custom_spell. Faithful ports only — anything needing draw,
## pile mutation, gold, Command-gain, sacrifice, Discover, or a hand picker stays
## OUT (it would resolve wrong host-only) until pile+draw sync lands post-v1.
const NET_SPELL_CUSTOMS: Array[String] = [
	"shove", "hex", "soul_swap", "shield_wall", "censer_light", "lay_on_hands",
	"immolate", "cataclysm", "inferno", "wildfire", "ambush", "plague_bell",
	"dark_pact", "apocalypse", "blood_tithe", "kings_command", "war_cry",
	"inspire", "overwhelming_force", "flame_bolt",
	# Draw / Command spells — resolved via the host→caster EV_DRAW / EV_MANA channel
	# (the caster draws/gains on its OWN client). No hand-picker or pile reads needed.
	"reckless_charge", "quick_shot", "slash", "patch_up", "smite_spell", "unholy_bargain",
	# Sacrifice spells — kill the caster's own target (the inert relic/reactive hooks
	# solo's sacrifice path fires don't exist in skirmish, so a plain kill is faithful).
	"offering", "fuel_the_pyre",
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
	var hero_hp: int = 25
	var hero_max_hp: int = 25
	var base_max_mana: int = 3
	var relics: Array = []          # empty in v1
	var card_upgrades: Dictionary = {}   # empty in v1


var combat_mode: int = CombatMode.SOLO
var rng_seed: int = 0
var slots: Array[PlayerSlot] = []
## Index into `slots` for the local player (== NetMatch.local_player_index).
var local_index: int = -1

## uid = slot_index * UID_SLOT_STRIDE + draft_position. Deterministic so the host
## and the client compute the SAME uid for the same physical card without any
## negotiation — both draft each slot in the same pick order. The host keys all
## per-card combat state by uid, and the client references its hand cards by uid
## in play intents, so the two id spaces MUST agree.
const UID_SLOT_STRIDE: int = 100000


func reset() -> void:
	combat_mode = CombatMode.SOLO
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
