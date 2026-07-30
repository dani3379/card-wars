extends SceneTree
## _probe_counterorders.gd — the 2026-07-30 intent-counter slate.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_counterorders.gd
##
## WHY THE SLATE EXISTS: enemy intents are the most expensive legibility system in
## the game and, until this pass, no player card could act on one — the telegraph
## was information with no counterplay. Three cards now pay off an enemy that is
## WEARING AN ORDER (any intent but plain ATTACK, i.e. exactly the states that
## print a badge).
##
## The three things that could go wrong, and are therefore asserted:
##   1. The condition drifts from the badge -> all three read ONE predicate.
##   2. The card is a dead draw when the foe is simply swinging -> each floors to a
##      plain fair card, so the conditional half is a bonus, never the whole text.
##   3. It silently no-ops in skirmish, where nobody has orders -> denylisted.

var _fails: Array[String] = []
var _ran := false

const SLATE := ["counterorders", "order_breaker", "the_interpreter"]


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails.append(label)
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var CDB: Node = root.get_node_or_null("CardDB")
	var SK: Node = root.get_node_or_null("SkirmishState")
	if CDB == null or SK == null:
		print("[counterorders] autoloads missing")
		quit(1)
		return true

	print("— the slate exists, is draftable, and every card has a forge")
	for cid in SLATE:
		var cd: Dictionary = CDB.get_card_data(cid)
		_check(not cd.is_empty(), "%s exists" % cid)
		if cd.is_empty():
			continue
		_check(CDB.UPGRADES.has(cid), "%s has a hand-crafted '+' entry" % cid)
		_check(cd.get("draftable", true) == true, "%s is draftable" % cid)
		# One of each rarity — the slate is an ARC (learn the verb, then commit),
		# not three variants of one card.
		_check(String(cd.get("rarity", "")) in ["common", "uncommon", "rare"],
			"%s sits on the draftable ladder" % cid)
	var rarities: Array = []
	for cid in SLATE:
		rarities.append(String(CDB.get_card_data(cid).get("rarity", "")))
	_check(rarities.size() == 3 and rarities[0] != rarities[1] \
		and rarities[1] != rarities[2] and rarities[0] != rarities[2],
		"the slate spans three different rarities")

	print("— none of the three is a dead draw against a plain attacker")
	# The floor test, stated as data rather than as prose: the common still deals
	# its base damage, and both bodies are honest statlines on their own.
	var co: Dictionary = CDB.get_card_data("counterorders")
	_check(String(co.get("desc", "")).begins_with("Deal 3"),
		"Counterorders states its unconditional half FIRST")
	for cid in ["order_breaker", "the_interpreter"]:
		var cd: Dictionary = CDB.get_card_data(cid)
		var cost: int = int(cd.get("cost", 0))
		var atk: int = int(cd.get("atk", 0))
		var hp: int = int(cd.get("hp", 0))
		# The house curve is ~2 stat points per Command for a conditional body.
		_check(atk + hp >= cost * 2,
			"%s is a fair body before its condition (%d/%d for %d)" % [cid, atk, hp, cost])

	print("— all three are barred from skirmish, where nobody wears an order")
	for cid in SLATE:
		_check(SK.SKIRMISH_DENYLIST.has(cid), "%s is skirmish-denylisted" % cid)

	print("— the condition is ONE predicate, and it is the badge on screen")
	var src := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	var ke := FileAccess.get_file_as_string("res://scripts/data/KeywordEffects.gd")
	_check("func _wears_an_order(" in src, "Combat owns the predicate")
	var pred := src.split("func _wears_an_order(")
	if pred.size() >= 2:
		var body: String = pred[1].split("\nfunc ")[0]
		# It must key off current_intent — the same field _update_intent_display
		# renders — and it must exclude plain ATK and scenery.
		_check("current_intent" in body, "the predicate reads the live intent")
		_check('!= "ATK"' in body, "plain ATTACK is not an order")
		_check("_is_fortification" in body, "scenery never counts as under orders")
	# All three consumers go through it; nobody re-derives the condition.
	# The declaration plus both in-file consumers (the spell and the keystone). The
	# third consumer is the on-enter, which reaches it through the ctx below.
	_check(src.count("_wears_an_order(") >= 3,
		"every in-file consumer calls the shared predicate")
	_check("ctx._wears_an_order(order_t)" in ke,
		"the on-enter reads it through the ctx rather than re-deriving")

	print("— each card is actually wired to a resolver")
	_check('"counterorders":' in src, "the spell has an arm in _resolve_custom_spell")
	_check('"strike_the_order":' in ke, "the on-enter type is dispatched")
	_check('"strike_the_order":' in src, "the on-enter has a TRIGGER_FX_ENTER beat")
	_check('"read_the_orders"' in src, "the keystone passive is read in Combat")
	# The keystone rides the on-kill funnel every damage path converges on, not one
	# strike routine — that is how Rampage and Head-Money avoid drifting apart.
	var riders := src.split("func _apply_combat_strike_riders(")
	if riders.size() >= 2:
		var rbody: String = riders[1].split("\nfunc ")[0]
		_check("read_the_orders" in rbody,
			"the keystone is hosted at the shared on-kill funnel")
		# Split on the GUARD, not on the bare id — the id also appears in the
		# comment above it, and slicing from there reads 500 chars of prose.
		var promo: PackedStringArray = rbody.split('_has_passive_on_side("read_the_orders"')
		_check(promo.size() >= 2 and "persistent_atk_buff" in promo[1].left(400),
			"its promotion is permanent, not a this-round buff")

	if _fails.is_empty():
		print("[counterorders] ALL PASS")
		quit(0)
	else:
		print("[counterorders] FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("  x ", f)
		quit(1)
	return true
