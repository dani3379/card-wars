extends RefCounted
## Host-owned private state for the remote Skirmish player.
##
## The client renders a redacted copy of this state, but it never decides which
## cards are in hand, what they cost, or how much Command remains.  Every play is
## validated against this object before CombatNet mutates the public board.

const MAX_HAND_SIZE := 10
const HAND_REFILL_TARGET := 5
const MAX_BANKED_MANA := 2
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
	# 2026-07-25: uncapped banking retired with Miser's Coffer — one cap for all.
	var banked := mini(mana, MAX_BANKED_MANA)
	if round_number <= 1:
		banked = 0
	max_mana = base_max_mana + bonus_mana_next_turn
	bonus_mana_next_turn = 0
	if relics.has("lantern") and round_number == 1:
		max_mana += 1
	if relics.has("cavalry_sigil"):
		max_mana += clampi(empty_edge_columns, 0, 2)
	if relics.has("marathoners_sash"):
		max_mana += 2
	max_mana = maxi(0, max_mana)
	mana = max_mana + banked
	if relics.has("marathoners_sash") and round_number == 1:
		mana = 1

	for entry in hand:
		entry["pact_zero"] = false
		if relics.has("snecko_eye"):
			entry["cost"] = _rng.randi_range(0, 3)

	if skip_next_refill:
		skip_next_refill = false
	else:
		var target := HAND_REFILL_TARGET
		if relics.has("snecko_eye"):
			target = 6
		if relics.has("deep_satchel"):
			target += 1
		if relics.has("couriers_bag") and round_number == 1:
			target += 1
		if relics.has("tome_of_many"):
			target += 2
		var count := maxi(0, target - hand.size())
		if count == 0:
			count = 1
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
		entry["cost"] = _rng.randi_range(0, 3)
	hand.append(entry)
	return true


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
	if not is_spell and relics.has("last_breath") \
			and int(data.get("hp", 99)) == 1 and cost > 0:
		cost = maxi(0, cost - 1)
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
