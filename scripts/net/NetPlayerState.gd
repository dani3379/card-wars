extends RefCounted
## Host-owned private state for the remote Skirmish player.
##
## The client renders a redacted copy of this state, but it never decides which
## cards are in hand, what they cost, or how much Command remains.  Every play is
## validated against this object before CombatNet mutates the public board.

const MAX_HAND_SIZE := 10
const HAND_REFILL_TARGET := 5
## HOW MUCH carries over for a player who has earned carryover at all — WHETHER
## any does is `_bank_cap()`, and the default is zero. Mirrors Combat's constant
## of the same name; it also rides the compatibility fingerprint, so changing it
## refuses a match against a build that banks differently rather than desyncing
## one player's Command pool halfway through a game.
const MAX_BANKED_MANA := 2
## Combat.BANK_RELIC. Restated for the same reason command_for_round() is — this
## file cannot name that script (see _relic_field) — and safe to restate because
## it is an ID rather than a magnitude: a wrong id is a relic nobody holds, which
## the parity gate reads as "the client banks when the host does not".
const BANK_RELIC := "field_chest"
# ── THE COMMAND RAMP — MIRRORED FROM Combat.gd, NOT DECIDED HERE ──────────
# Combat.COMMAND_START / COMMAND_RAMP_PER_ROUND / COMMAND_RAMP_CAP /
# LEGACY_FLAT_COMMAND and Combat.command_for_round() are the authority.
#
# This class CANNOT name that script — see _relic_value's header below: a
# preload drags the named script into a pre-autoload compile and takes the whole
# depending probe down. So the four numbers and the one formula are restated,
# and restating host-side rules is the exact trap this file was repaired for
# once already (every relic magnitude used to be a literal here while Combat
# read RelicDB — equal on the day it was written, one retune from diverging
# silently on ONE player's Command pool).
#
# The guard is that BOTH sides are static and pure, so the parity gate diffs
# command_for_round() against Combat's over a span of rounds instead of trusting
# the copy. If you change a number here, change it there, and the gate is what
# tells you that you forgot.
const COMMAND_START := 1
const COMMAND_RAMP_PER_ROUND := 1
const COMMAND_RAMP_CAP := 6
const LEGACY_FLAT_COMMAND := 3
const HAND_DRAW_PER_TURN := 2

static func command_for_round(r: int) -> int:
	return clampi(COMMAND_START + (maxi(1, r) - 1) * COMMAND_RAMP_PER_ROUND,
		COMMAND_START, COMMAND_RAMP_CAP)
const CURSE_IDS: Array[String] = ["curse", "wound", "craven",
	"deserters_mark", "grave_debt", "war_debt"]

var draw_pile: Array = []
var discard_pile: Array = []
var exhaust_pile: Array = []
var hand: Array = []
var field: Dictionary = {} # deck_uid -> private entry while that card is in play
var relics: Array[String] = []
var potions: Array[String] = []

var mana: int = 0
var max_mana: int = 3
var base_max_mana: int = 3
var bonus_mana_next_turn: int = 0
var round_number: int = 0
var skip_next_refill: bool = false
var first_spell_played: bool = false

var _spell_tome_active: bool = false
var _rng := RandomNumberGenerator.new()
var _card_resolver: Callable


## A relic's magnitude, read from the SAME place `Combat._start_round` and
## `Combat._effective_cost` read it, so the host's own side and the host's model of
## the client can never be tuned apart.
##
## LOOKED UP LAZILY, AND THAT IS THE WHOLE POINT. Two shapes were tried here first
## and both broke the build in ways `_probe_parsecheck` cannot see, because it runs
## as a SCENE where autoload names resolve:
##   * a bare `RelicDB.get_relic(...)` — this class is a RefCounted that tools
##     preload, and in a `--script` run its dependencies compile BEFORE autoloads
##     register, so the identifier is a compile error that takes the whole
##     depending script down (`_probe_skirmish_combat` failed to load outright);
##   * `preload("res://scripts/data/RelicDB.gd")` — worse. It drags RelicDB.gd into
##     that same early compile, where ITS OWN `RunState` reference fails, and the
##     failure then poisons the RelicDB autoload for the entire run (every call
##     site in Combat reporting "Nonexistent function 'get_relic' in base 'Node'").
## Resolving through the tree at CALL time touches nothing at compile time, and the
## explicit fallback is the value the literal used to be — so a context with no
## autoloads still prices cards exactly as before instead of throwing.
static func _relic_value(id: String, fallback: int) -> int:
	return _relic_field(id, "value", fallback)


## Any integer field off a relic entry, resolved through the TREE at call time.
##
## Never `RelicDB.get_relic(...)` directly: this file is a plain RefCounted that
## tools `preload`, so its dependencies compile BEFORE the autoloads register and
## a bare `RelicDB` identifier is a hard compile error there — which takes the
## whole depending probe down while `parsecheck` (a SCENE, autoloads resolved)
## stays green. See CLAUDE.md's "parsecheck's ONE blind spot".
static func _relic_field(id: String, key: String, fallback: int) -> int:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return fallback
	var tree := loop as SceneTree
	if tree.root == null:
		return fallback
	var db := tree.root.get_node_or_null("RelicDB")
	if db == null or not db.has_method("get_relic"):
		return fallback
	return int(db.get_relic(id).get(key, fallback))


func setup(deck: Array, deck_uids: Array, loadout_relics: Array,
		loadout_potions: Array, seed: int, base_command: int = 3,
		card_resolver: Callable = Callable()) -> bool:
	clear()
	if deck.size() != deck_uids.size() or deck.is_empty() or not card_resolver.is_valid():
		return false
	_card_resolver = card_resolver
	base_max_mana = maxi(0, base_command)
	max_mana = base_max_mana
	for raw_relic in loadout_relics:
		relics.append(String(raw_relic))
	for raw_potion in loadout_potions:
		potions.append(String(raw_potion))
	var spell_count := 0
	for i in deck.size():
		var id := String(deck[i])
		var data := _card_data(id)
		if data.is_empty():
			clear()
			return false
		if String(data.get("type", "")) == "spell":
			spell_count += 1
		draw_pile.append(_make_entry(id, int(deck_uids[i])))
	_spell_tome_active = relics.has("spell_tome") \
		and float(spell_count) / float(deck.size()) >= 0.5
	_rng.seed = seed
	_shuffle(draw_pile)
	return true


func clear() -> void:
	draw_pile.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	hand.clear()
	field.clear()
	relics.clear()
	potions.clear()
	mana = 0
	max_mana = 3
	base_max_mana = 3
	bonus_mana_next_turn = 0
	round_number = 0
	skip_next_refill = false
	first_spell_played = false
	_spell_tome_active = false
	_card_resolver = Callable()


func predeal(count: int, include_coin: bool) -> void:
	for _i in maxi(0, count):
		draw_one()
	if include_coin and hand.size() < MAX_HAND_SIZE:
		hand.append(_make_entry("coin", -1))
	skip_next_refill = true


func begin_turn(new_round: int, empty_edge_columns: int = 0) -> void:
	round_number = maxi(1, new_round)
	first_spell_played = false
	# 2026-09-16: Command does not carry over by default on either side of the
	# wire. The cap is gated on the SAME relic id Combat._bank_cap gates on, so a
	# client and the host's model of that client cannot bank differently — which
	# would be invisible until the round the two pools disagreed about a cost.
	var banked := mini(mana, MAX_BANKED_MANA if relics.has(BANK_RELIC) else 0)
	if round_number <= 1:
		banked = 0
	# THE RAMP supplies this round's baseline; base_max_mana keeps its old
	# meaning (the flat 3 plus whatever the loadout added), so the slot field,
	# the match-config envelope and every relic arm below are untouched. Same
	# signed-delta shape as Combat._start_round — see that block.
	max_mana = command_for_round(round_number) \
		+ (base_max_mana - LEGACY_FLAT_COMMAND) + bonus_mana_next_turn
	bonus_mana_next_turn = 0
	# READ THE RELIC, DO NOT RESTATE IT. Every number below used to be a literal
	# while `Combat._start_round` — the SAME rule, applied to the host — reads it
	# out of RelicDB. Identical today, and that is exactly what makes it a trap:
	# the two would part company the moment one of these is retuned, silently, and
	# the split would land on ONE player's Command pool. CombatNet's opening
	# pre-deal already carries this warning in a comment; its siblings here were
	# left as literals. (Verified: every RelicDB value equals the literal it
	# replaced — 1/2/6/1/1/2 — so this changes no play today.)
	#
	# A `lantern` arm granting +1 max Command on round 1 was removed here. It was
	# dead twice over: `lantern` is not in SkirmishState.NET_RELIC_POOL (dropped
	# 2026-07-16) and relic loadouts are filtered against that pool, so a client
	# cannot hold one; and the relic was reshaped into The Burnt Dispatches, an
	# exhaust-pile effect that has nothing to do with the Command pool. Do not
	# restore it — it described a relic that no longer exists.
	if relics.has("cavalry_sigil"):
		# Host: += value for EACH empty edge column (0 and LANES_PER_ROW-1, both
		# rows clear). `empty_edge_columns` is that same count, taken off the
		# client's half of the host's board by _net_remote_empty_edge_columns.
		max_mana += clampi(empty_edge_columns, 0, 2) \
			* _relic_value("cavalry_sigil", 1)
	if relics.has("marathoners_sash"):
		max_mana += _relic_value("marathoners_sash", 2)
	max_mana = maxi(0, max_mana)
	mana = max_mana + banked
	if relics.has("marathoners_sash") and round_number == 1:
		mana = 1

	for entry in hand:
		entry["pact_zero"] = false
		if relics.has("snecko_eye"):
			entry["cost"] = _snecko_cost()

	if skip_next_refill:
		skip_next_refill = false
	else:
		# FIXED DRAW, mirroring Combat._start_round's block exactly: round 1
		# deals the opening hand, every round after draws HAND_DRAW_PER_TURN,
		# and the draw relics are flat ADDERS rather than refill-target raises.
		# Same rule as the mana block above — these magnitudes are the host's and
		# the host reads them out of RelicDB. (tome_of_many is gated host-side on
		# a deck of 20+; a skirmish deck is exactly SkirmishState.DECK_TARGET ==
		# 20, so the gate is always true here and restating it would only add
		# state that can never change the answer.)
		var count := HAND_REFILL_TARGET if round_number <= 1 else HAND_DRAW_PER_TURN
		if relics.has("snecko_eye"):
			count += 1
		if relics.has("deep_satchel"):
			count += _relic_value("deep_satchel", 1)
		if relics.has("couriers_bag") and round_number == 1:
			count += _relic_value("couriers_bag", 1)
		if relics.has("tome_of_many"):
			count += _relic_value("tome_of_many", 2)
		count = maxi(1, count)
		for _i in count:
			draw_one()

	if relics.has("pact_of_embers") and not hand.is_empty():
		var best: Dictionary = hand[0]
		for entry in hand:
			if int(entry.get("cost", 0)) > int(best.get("cost", 0)):
				best = entry
		best["pact_zero"] = true


func end_turn() -> void:
	# (Mana Drunkard's spend-streak retired 2026-07-25 — Forced March is now a
	# board-side Swift grant and no longer touches this resource model.)
	pass


func draw_one() -> bool:
	if hand.size() >= MAX_HAND_SIZE:
		return false
	if draw_pile.is_empty() and not discard_pile.is_empty():
		draw_pile = discard_pile.duplicate(true)
		discard_pile.clear()
		_shuffle(draw_pile)
	if draw_pile.is_empty():
		return false
	var entry: Dictionary = draw_pile.pop_front()
	entry["pact_zero"] = false
	if relics.has("snecko_eye"):
		entry["cost"] = _snecko_cost()
	hand.append(entry)
	return true


## Basilisk Eye's cost roll, READ OFF THE RELIC like every other magnitude in
## this file. Both bounds moved with the 2026-09-16 cost rescale; a literal here
## would have kept the client rolling 0-3 against a host rolling 1-5, which is a
## silent divergence on one player's whole hand.
func _snecko_cost() -> int:
	return _rng.randi_range(
		_relic_field("snecko_eye", "cost_lo", 1),
		_relic_field("snecko_eye", "cost_hi", 5))


func draw_cards(count: int) -> void:
	for _i in clampi(count, 0, MAX_HAND_SIZE):
		draw_one()


func gain_mana(amount: int) -> void:
	mana = maxi(0, mana + clampi(amount, -20, 20))


func validate_play(uid: int, id: String, has_first_spell_discount: bool = false) -> Dictionary:
	var index := _hand_index(uid, id)
	if index < 0:
		return {"ok": false, "reason": "card_not_in_hand"}
	var entry: Dictionary = hand[index]
	var data := _card_data(id)
	if data.is_empty():
		return {"ok": false, "reason": "card_unknown"}
	var cost := effective_cost(entry, data, has_first_spell_discount)
	if mana < cost:
		return {"ok": false, "reason": "not_enough_command"}
	return {"ok": true, "index": index, "cost": cost, "entry": entry, "data": data}


func commit_play(check: Dictionary, to_field: bool) -> Dictionary:
	if not bool(check.get("ok", false)):
		return {}
	var index := int(check.get("index", -1))
	if index < 0 or index >= hand.size():
		return {}
	var entry: Dictionary = hand.pop_at(index)
	mana = maxi(0, mana - int(check.get("cost", 0)))
	var data: Dictionary = check.get("data", {})
	if String(data.get("type", "")) == "spell":
		first_spell_played = true
	if to_field and int(entry.get("uid", -1)) >= 0:
		field[int(entry.uid)] = entry
	elif int(entry.get("uid", -1)) >= 0:
		if Array(data.get("keywords", [])).has("exhaust"):
			exhaust_pile.append(entry)
		else:
			discard_pile.append(entry)
	return entry


func effective_cost(entry: Dictionary, data: Dictionary,
		has_first_spell_discount: bool = false) -> int:
	var cost := maxi(0, int(entry.get("cost", data.get("cost", 0))))
	var is_spell := String(data.get("type", "")) == "spell"
	if is_spell and relics.has("ember_crown") and not first_spell_played:
		cost = 0
	if is_spell and not first_spell_played and has_first_spell_discount and cost > 0:
		cost -= 1
	if is_spell and _spell_tome_active and cost > 0:
		cost -= 1
	if bool(entry.get("pact_zero", false)):
		cost = 0
	# Read the relic, as Combat._effective_cost does (same reason as begin_turn's
	# block: a retune would otherwise price the client's cards differently from
	# the host's for the identical card and relic). Verified equal today: 1.
	if not is_spell and relics.has("last_breath") \
			and int(data.get("hp", 99)) == 1 and cost > 0:
		cost = maxi(0, cost - _relic_value("last_breath", 1))
	return cost


func discard_cards(uids: Variant) -> Dictionary:
	return move_hand_cards(uids, false)


func move_hand_cards(uids: Variant, to_exhaust: bool) -> Dictionary:
	if typeof(uids) != TYPE_ARRAY:
		return {"ok": false, "reason": "discard_type"}
	var uid_list: Array = uids
	var wanted: Dictionary = {}
	for raw_uid in uid_list:
		var uid := int(raw_uid)
		if wanted.has(uid):
			return {"ok": false, "reason": "discard_duplicate"}
		wanted[uid] = true
	var indexes: Array[int] = []
	for uid_var in wanted:
		var uid := int(uid_var)
		var index := _hand_index(uid, "")
		if index < 0:
			return {"ok": false, "reason": "discard_not_in_hand"}
		var entry: Dictionary = hand[index]
		if String(entry.get("id", "")) in CURSE_IDS:
			return {"ok": false, "reason": "discard_curse"}
		indexes.append(index)
	indexes.sort()
	indexes.reverse()
	for index in indexes:
		var entry: Dictionary = hand.pop_at(index)
		if to_exhaust:
			exhaust_pile.append(entry)
		else:
			discard_pile.append(entry)
	return {"ok": true, "count": indexes.size()}


func hand_entry(uid: int) -> Dictionary:
	var index := _hand_index(uid, "")
	return hand[index] if index >= 0 else {}


func field_card_left(uid: int, id: String, exiled: bool = false) -> void:
	if uid < 0 or not field.has(uid):
		return
	var entry: Dictionary = field[uid]
	field.erase(uid)
	if not exiled and String(entry.get("id", "")) == id:
		discard_pile.append(entry)


func give_card(id: String, uid: int) -> bool:
	if id.is_empty() or hand.size() >= MAX_HAND_SIZE:
		return false
	var entry := _take_uid_from_all_zones(uid, id)
	if entry.is_empty():
		entry = _make_entry(id, uid)
	hand.append(entry)
	return true


func consume_potion(id: String) -> bool:
	var index := potions.find(id)
	if index < 0:
		return false
	potions.remove_at(index)
	return true


func state_payload() -> Dictionary:
	return {
		"hand": _public_entries(hand),
		# The owner may inspect draw-pile composition, but never its secret order.
		# Client combat does not draw locally; future hands arrive in this payload.
		"draw": _public_unordered_entries(draw_pile),
		"discard": _public_entries(discard_pile),
		"exhaust": _public_entries(exhaust_pile),
		"mana": mana,
		"max_mana": max_mana,
		"potions": potions.duplicate(),
	}


func _make_entry(id: String, uid: int) -> Dictionary:
	var data := _card_data(id)
	return {
		"id": id,
		"uid": uid,
		"cost": maxi(0, int(data.get("cost", 0))),
		"pact_zero": false,
	}


func _card_data(id: String) -> Dictionary:
	if not _card_resolver.is_valid():
		return {}
	var value: Variant = _card_resolver.call(id)
	return value if value is Dictionary else {}


func _public_entries(source: Array) -> Array:
	var out: Array = []
	for raw_entry in source:
		var entry: Dictionary = raw_entry
		out.append({
			"id": String(entry.get("id", "")),
			"uid": int(entry.get("uid", -1)),
			"cost": int(entry.get("cost", 0)),
			"pact_zero": bool(entry.get("pact_zero", false)),
		})
	return out


func _public_unordered_entries(source: Array) -> Array:
	var out := _public_entries(source)
	out.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.get("uid", -1)) < int(b.get("uid", -1)))
	return out


func _hand_index(uid: int, id: String) -> int:
	for i in hand.size():
		var entry: Dictionary = hand[i]
		if int(entry.get("uid", -2)) == uid \
				and (id.is_empty() or String(entry.get("id", "")) == id):
			return i
	return -1


func _take_uid_from_all_zones(uid: int, id: String) -> Dictionary:
	for zone in [hand, draw_pile, discard_pile, exhaust_pile]:
		for i in zone.size():
			var entry: Dictionary = zone[i]
			if int(entry.get("uid", -2)) == uid and String(entry.get("id", "")) == id:
				return zone.pop_at(i)
	if field.has(uid):
		var entry: Dictionary = field[uid]
		field.erase(uid)
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
