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
var NM: Node


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
	NM = root.get_node_or_null("NetMatch")
	if SS == null or NM == null:
		print("[net-authority-probe] FATAL: SkirmishState or NetMatch autoload missing")
		quit(1)
		return
	print("[net-authority-probe] start")
	_test_loadout_validation()
	_test_loadout_provenance()
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


func _arsenal_fixture(match_seed_value: int, slot_index: int) -> Dictionary:
	var offers: Dictionary = SS.arsenal_source_offers(match_seed_value, slot_index)
	var relics: Array = []
	for raw_round in offers.get("relics", []):
		var offered: Array = raw_round
		if not offered.is_empty():
			relics.append(String(offered[0]))
	var potions: Array = []
	for raw_round in offers.get("potions", []):
		var offered: Array = raw_round
		if not offered.is_empty():
			potions.append(String(offered[0]))
	return {"relics": relics, "potions": potions}


func _deck_from_sealed_pool(avail: Dictionary) -> Array:
	var ids: Array = avail.keys()
	ids.sort()
	var out: Array = []
	for raw_id in ids:
		var id := String(raw_id)
		for _copy in int(avail.get(id, 0)):
			if out.size() >= SS.DECK_TARGET:
				return out
			out.append(id)
	return out


func _deck_from_draft_offers(offers: Array) -> Array:
	var out: Array = []
	for raw_offer in offers:
		var offered: Array = raw_offer
		if offered.is_empty():
			return []
		out.append(String(offered[0]))
	return out


func _test_loadout_provenance() -> void:
	print("— deterministic source provenance rejects legal-but-unearned loadouts")
	var match_seed: int = 0x51A1
	var sub_seed: int = 0x1B3
	var remote_slot: int = 1
	var source_cfg := {"mirror": false, "seed": sub_seed}
	var arsenal := _arsenal_fixture(match_seed, remote_slot)
	var pool: Array = SS.skirmish_legal_pool()

	var quick_cards: Array = SS.quick_source_deck(match_seed, remote_slot, false, sub_seed)
	var quick := {"t": "finished", "cards": quick_cards,
		"relics": arsenal.relics, "potions": arsenal.potions}
	_check(SS.validate_loadout_provenance(quick, SS.MatchMode.QUICK,
		match_seed, remote_slot, source_cfg) == "",
		"the exact deterministic Quick deck and arsenal are accepted")
	var forged_quick: Dictionary = quick.duplicate(true)
	var forged_quick_cards: Array = quick_cards.duplicate()
	if forged_quick_cards.size() >= 2:
		var first: String = String(forged_quick_cards[0])
		forged_quick_cards[0] = forged_quick_cards[1]
		forged_quick_cards[1] = first
	forged_quick["cards"] = forged_quick_cards
	_check(SS.validate_loadout_event(forged_quick, SS.MatchMode.QUICK) == ""
		and SS.validate_loadout_provenance(forged_quick, SS.MatchMode.QUICK,
			match_seed, remote_slot, source_cfg) == "loadout_quick_source",
		"a legal Quick deck with forged order/source is rejected")

	var sealed_avail: Dictionary = SS.sealed_source_pool(match_seed, remote_slot,
		false, sub_seed)
	var sealed_cards := _deck_from_sealed_pool(sealed_avail)
	var sealed := {"t": "finished", "cards": sealed_cards,
		"relics": arsenal.relics, "potions": arsenal.potions}
	_check(sealed_cards.size() == SS.DECK_TARGET
		and SS.validate_loadout_provenance(sealed, SS.MatchMode.SEALED,
			match_seed, remote_slot, source_cfg) == "",
		"a Sealed deck using only its generated pool is accepted")
	var sealed_absent := ""
	for raw_id in pool:
		var candidate := String(raw_id)
		if not sealed_avail.has(candidate):
			sealed_absent = candidate
			break
	var forged_sealed: Dictionary = sealed.duplicate(true)
	var forged_sealed_cards: Array = sealed_cards.duplicate()
	if sealed_absent != "" and not forged_sealed_cards.is_empty():
		forged_sealed_cards[0] = sealed_absent
	forged_sealed["cards"] = forged_sealed_cards
	_check(sealed_absent != ""
		and SS.validate_loadout_provenance(forged_sealed, SS.MatchMode.SEALED,
			match_seed, remote_slot, source_cfg) == "loadout_sealed_source",
		"a legal card not opened in the remote Sealed pool is rejected")

	var draft_cards := _deck_from_draft_offers(
		SS.draft_offers_for_rerolls(match_seed, remote_slot))
	var draft := {"t": "finished", "cards": draft_cards,
		"relics": arsenal.relics, "potions": arsenal.potions}
	_check(draft_cards.size() == SS.DECK_TARGET
		and SS.validate_loadout_provenance(draft, SS.MatchMode.DRAFT,
			match_seed, remote_slot) == "",
		"a deck picked from the deterministic Draft slates is accepted")
	var double_reroll_cards := _deck_from_draft_offers(
		SS.draft_offers_for_rerolls(match_seed, remote_slot, 0, 0))
	var double_reroll := {"t": "finished", "cards": double_reroll_cards,
		"relics": arsenal.relics, "potions": arsenal.potions}
	_check(SS.validate_loadout_provenance(double_reroll, SS.MatchMode.DRAFT,
		match_seed, remote_slot) == "",
		"a Draft deck attainable after both allowed rerolls is accepted")
	var forged_draft_reason := ""
	for raw_id in pool:
		var candidate := String(raw_id)
		var candidate_cards: Array = draft_cards.duplicate()
		candidate_cards[0] = candidate
		var candidate_draft := {"t": "finished", "cards": candidate_cards,
			"relics": arsenal.relics, "potions": arsenal.potions}
		var candidate_reason: String = SS.validate_loadout_provenance(candidate_draft,
			SS.MatchMode.DRAFT, match_seed, remote_slot)
		if candidate_reason == "loadout_draft_source":
			forged_draft_reason = candidate_reason
			break
	_check(forged_draft_reason == "loadout_draft_source",
		"a legal Draft card not attainable from any two-reroll path is rejected")

	var arsenal_offers: Dictionary = SS.arsenal_source_offers(match_seed, remote_slot)
	var offered_relics: Dictionary = {}
	for raw_round in arsenal_offers.get("relics", []):
		for raw_id in raw_round:
			offered_relics[String(raw_id)] = true
	var unavailable_relic := ""
	for raw_id in SS.NET_RELIC_POOL:
		var candidate := String(raw_id)
		if not offered_relics.has(candidate):
			unavailable_relic = candidate
			break
	var forged_arsenal: Dictionary = quick.duplicate(true)
	var forged_relics: Array = arsenal.relics.duplicate()
	if unavailable_relic != "" and not forged_relics.is_empty():
		forged_relics[0] = unavailable_relic
	forged_arsenal["relics"] = forged_relics
	_check(unavailable_relic != ""
		and SS.validate_loadout_provenance(forged_arsenal, SS.MatchMode.QUICK,
			match_seed, remote_slot, source_cfg) == "loadout_relic_source",
		"a net-legal relic never offered by the Arsenal is rejected")

	var old_host := bool(NM.get("is_host"))
	var old_bot := bool(NM.get("vs_bot"))
	var old_mode := int(NM.get("match_mode"))
	var old_seed := int(NM.get("match_seed"))
	var old_received := bool(NM.get("_remote_loadout_received"))
	var old_config: Dictionary = NM.get("_loadout_source_config").duplicate(true)
	NM.set("is_host", true)
	NM.set("vs_bot", false)
	NM.set("match_mode", SS.MatchMode.QUICK)
	NM.set("match_seed", match_seed)
	NM.set("_remote_loadout_received", false)
	NM.call("set_loadout_source_config", false, sub_seed)
	NM.call("_apply_draft_event", quick)
	var valid_ingress_committed := bool(NM.get("_remote_loadout_received"))
	NM.set("_remote_loadout_received", false)
	NM.call("_apply_draft_event", forged_quick)
	_check(valid_ingress_committed and not bool(NM.get("_remote_loadout_received")),
		"NetMatch accepts the sourced Quick deck but blocks the forged one before commit")
	NM.set("is_host", old_host)
	NM.set("vs_bot", old_bot)
	NM.set("match_mode", old_mode)
	NM.set("match_seed", old_seed)
	NM.set("_remote_loadout_received", old_received)
	NM.set("_loadout_source_config", old_config)

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
	# THE COMMAND RAMP (2026-09-16) made the per-round pool a function of the
	# ROUND, so round 1 opens on COMMAND_START (1) — not on base_max_mana, which
	# is now the run's flat-3-era baseline that the ramp is a signed delta from.
	# Asserted against the CONSTANT rather than against command_for_round(), so
	# this claim does not merely agree with the implementation it is testing.
	_check(state.hand.size() == state.HAND_REFILL_TARGET
		and state.mana == state.COMMAND_START,
		"host dealt the hand and opened the Command pool at the ramp's first rung")
	# The ramp's SHAPE, walked independently: +1 a round off COMMAND_START, held
	# at COMMAND_RAMP_CAP. A flat pool passes none of these past round 1, and a
	# runaway ramp fails the ceiling.
	var ramp_ok := true
	var ramp_seen: Array[int] = []
	for r in range(1, 10):
		var want: int = mini(state.COMMAND_START
			+ (r - 1) * state.COMMAND_RAMP_PER_ROUND, state.COMMAND_RAMP_CAP)
		var got: int = state.command_for_round(r)
		ramp_seen.append(got)
		if got != want:
			ramp_ok = false
	_check(ramp_ok, "Command ramp climbs +1/round to its ceiling: %s" % [ramp_seen])
	var public_draw: Array = state.state_payload().draw
	var draw_order_redacted := true
	for i in range(1, public_draw.size()):
		if int(public_draw[i - 1].uid) > int(public_draw[i].uid):
			draw_order_redacted = false
	_check(draw_order_redacted, "published draw-pile composition is canonical, not secret RNG order")

	# THE PLAY-AUTHORITY TESTS RUN ON ROUND 2, and the reason is the point of the
	# ramp rather than a harness convenience: the fixture deck is all `brute` at
	# cost 2, and round 1 now grants COMMAND_START = 1, so validate_play answers
	# "not_enough_command" and all three checks below fail for a reason that has
	# nothing to do with hand ownership. Round 2 is the first round a 2-cost card
	# is affordable. (Before 2026-09-16 every round granted a flat 3.)
	state.begin_turn(2)
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
