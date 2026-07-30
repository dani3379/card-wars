extends SceneTree
## Adversarial checks for the private half of Online Skirmish authority.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_authority.gd

const NetPlayerStateScript = preload("res://scripts/net/NetPlayerState.gd")

var _fails := 0
var _started := false
var _done := false
var SS: Node


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	SS = root.get_node_or_null("SkirmishState")
	if SS == null:
		print("[net-authority-probe] FATAL: SkirmishState autoload missing")
		quit(1)
		return
	print("[net-authority-probe] start")
	_test_loadout_validation()
	_test_private_state_validation()
	if _fails == 0:
		print("[net-authority-probe] ALL PASS")
	else:
		print("[net-authority-probe] %d FAILURES" % _fails)
	_done = true
	quit(1 if _fails > 0 else 0)


func _test_loadout_validation() -> void:
	print("— submitted loadouts are bounded and legal")
	var pool: Array = SS.skirmish_legal_pool()
	var cards: Array = []
	for i in SS.DECK_TARGET:
		cards.append(String(pool[i]))
	var valid := {"t": "finished", "cards": cards, "relics": [], "potions": []}
	_check(SS.validate_loadout_event(valid, SS.MatchMode.CONSTRUCTED) == "",
		"a legal 20-card constructed loadout is accepted")
	var short := valid.duplicate(true)
	short.cards.pop_back()
	_check(SS.validate_loadout_event(short, SS.MatchMode.CONSTRUCTED) == "loadout_deck_size",
		"a 19-card submission is rejected")
	var illegal := valid.duplicate(true)
	illegal.cards[0] = "definitely_not_a_card"
	_check(SS.validate_loadout_event(illegal, SS.MatchMode.CONSTRUCTED) == "loadout_card_illegal",
		"an unknown card id is rejected")
	var copies := valid.duplicate(true)
	for i in copies.cards.size():
		copies.cards[i] = String(pool[0])
	_check(SS.validate_loadout_event(copies, SS.MatchMode.CONSTRUCTED) == "loadout_copy_cap",
		"a forged over-copy deck is rejected")
	var too_many_relics := valid.duplicate(true)
	too_many_relics.relics = ["a", "b", "c", "d"]
	_check(SS.validate_loadout_event(too_many_relics, SS.MatchMode.DRAFT) == "loadout_arsenal_size",
		"an oversized relic slate is rejected")
	var duplicate_relic := valid.duplicate(true)
	var relic_id := String(SS.NET_RELIC_POOL[0])
	duplicate_relic.relics = [relic_id, relic_id]
	_check(SS.validate_loadout_event(duplicate_relic, SS.MatchMode.DRAFT) == "loadout_relic_illegal",
		"duplicate relic ids are rejected")
	var bad_potion := valid.duplicate(true)
	bad_potion.potions = ["not_a_potion"]
	_check(SS.validate_loadout_event(bad_potion, SS.MatchMode.DRAFT) == "loadout_potion_illegal",
		"unknown potion ids are rejected")


func _test_private_state_validation() -> void:
	print("— host-owned hand, Command, zones, and consumables reject forged intents")
	var deck: Array = []
	var uids: Array = []
	for i in SS.DECK_TARGET:
		deck.append("brute")
		uids.append(SS.UID_SLOT_STRIDE + i)
	var potion_id := String(SS.NET_POTION_POOL[0])
	var state = NetPlayerStateScript.new()
	_check(state.setup(deck, uids, [], [potion_id], 8675309, SS.BASE_MAX_MANA,
		Callable(SS, "skirmish_card_data")), "private authority accepted a valid deck fixture")
	state.begin_turn(1)
	_check(state.hand.size() == state.HAND_REFILL_TARGET and state.mana == SS.BASE_MAX_MANA,
		"host dealt the hand and opened the Command pool")
	var public_draw: Array = state.state_payload().draw
	var draw_order_redacted := true
	for i in range(1, public_draw.size()):
		if int(public_draw[i - 1].uid) > int(public_draw[i].uid):
			draw_order_redacted = false
	_check(draw_order_redacted, "published draw-pile composition is canonical, not secret RNG order")

	var entry: Dictionary = state.hand[0]
	var uid := int(entry.uid)
	var forged: Dictionary = state.validate_play(uid, "goblin")
	_check(not bool(forged.get("ok", false)) and forged.reason == "card_not_in_hand",
		"a real uid paired with a forged card id is rejected")
	var legal: Dictionary = state.validate_play(uid, "brute")
	_check(bool(legal.get("ok", false)), "the actual in-hand uid/id pair is accepted")
	var committed: Dictionary = state.commit_play(legal, true)
	_check(not committed.is_empty() and state.field.has(uid),
		"one accepted play moves the card into the host-owned field zone")
	var replay: Dictionary = state.validate_play(uid, "brute")
	_check(not bool(replay.get("ok", false)) and replay.reason == "card_not_in_hand",
		"replaying the same card uid is rejected")

	state.mana = 0
	var costly: Dictionary = state.hand[0]
	var overspend: Dictionary = state.validate_play(int(costly.uid), "brute")
	_check(not bool(overspend.get("ok", false)) and overspend.reason == "not_enough_command",
		"a play that overspends authoritative Command is rejected")

	var discard_uid := int(state.hand[0].uid)
	var hand_before: int = state.hand.size()
	var wrong_shape: Dictionary = state.discard_cards("not-an-array")
	_check(wrong_shape.reason == "discard_type" and state.hand.size() == hand_before,
		"a malformed discard field is rejected without a runtime type error")
	var bad_discard: Dictionary = state.discard_cards([discard_uid, 99999999])
	_check(not bool(bad_discard.get("ok", false)) and state.hand.size() == hand_before
		and not state.discard_pile.any(func(e): return int(e.uid) == discard_uid),
		"a mixed valid/forged discard is rejected atomically")
	var duplicate_discard: Dictionary = state.discard_cards([discard_uid, discard_uid])
	_check(duplicate_discard.reason == "discard_duplicate" and state.hand.size() == hand_before,
		"duplicate discard uids are rejected")
	var good_discard: Dictionary = state.discard_cards([discard_uid])
	_check(bool(good_discard.get("ok", false)) and state.hand.size() == hand_before - 1,
		"a real marked uid moves to the authoritative discard")

	state.field_card_left(uid, "brute", false)
	_check(not state.field.has(uid)
		and state.discard_pile.any(func(e): return int(e.uid) == uid),
		"a dead field card returns to the authoritative discard")
	_check(state.consume_potion(potion_id) and not state.consume_potion(potion_id),
		"a potion can be consumed exactly once")

	var total: int = state.hand.size() + state.draw_pile.size() \
		+ state.discard_pile.size() + state.exhaust_pile.size() + state.field.size()
	_check(total == SS.DECK_TARGET, "all 20 submitted card uids remain in exactly one zone")
