extends SceneTree
## Probe: card-offer randomness should be varied without losing determinism.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_card_randomness.gd

var _fails := 0
var _ran := false


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("[card-randomness] start")

	var ss = root.get_node_or_null("SkirmishState")
	var cdb = root.get_node_or_null("CardDB")
	var bot = root.get_node_or_null("SkirmishBot")
	if ss == null or cdb == null or bot == null:
		print("[card-randomness] FATAL: autoloads missing")
		quit(1)
		return true

	var legal: Array = ss.skirmish_legal_pool()
	_check(legal.size() >= ss.DECK_TARGET * 3,
		"skirmish pool can support 20 unique triplets (%d cards)" % legal.size())

	_test_draft_triplets(legal, ss, cdb)
	_test_quick_deck(legal, ss)
	_test_sealed_pool(legal, ss)
	_test_campaign_rewards(cdb)
	_test_bot_deck(bot, ss)

	if _fails == 0:
		print("[card-randomness] ALL PASS")
	else:
		print("[card-randomness] %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _test_draft_triplets(legal: Array, ss: Node, cdb: Node) -> void:
	print("-- draft triplets (act-3 weighted odds)")
	var buckets: Dictionary = ss.rarity_buckets(legal)
	_check(not (buckets["common"] as Array).is_empty()
			and not (buckets["uncommon"] as Array).is_empty()
			and not (buckets["rare"] as Array).is_empty(),
		"legal pool splits into all three reward tiers")
	_check(not buckets.has("starter"),
		"weighted buckets carry no starter tier (act rewards never offer starters)")

	var weights: Array = cdb.act_rarity_weights(ss.DRAFT_ACT)
	_check(weights == [30, 50, 20], "draft rolls at act-3 weights 30/50/20 (got %s)" % str(weights))

	# Reproducible from the seed: same seed → identical opening triplet.
	var rng_a := RandomNumberGenerator.new(); rng_a.seed = 777
	var rng_b := RandomNumberGenerator.new(); rng_b.seed = 777
	var first_a: Array = ss.deal_weighted_triplet(buckets, {}, rng_a, weights)
	var first_b: Array = ss.deal_weighted_triplet(buckets, {}, rng_b, weights)
	_check(first_a == first_b and first_a.size() == 3,
		"same seed → identical triplet (deterministic): %s" % str(first_a))

	# Tally the rarity mix over a long run of triplets; it should land near 30/50/20.
	var rng := RandomNumberGenerator.new(); rng.seed = 123456
	var bags: Dictionary = {}
	var counts := {"common": 0, "uncommon": 0, "rare": 0}
	var total := 0
	var dup_in_triplet := false
	for _pick in range(1500):
		var triplet: Array = ss.deal_weighted_triplet(buckets, bags, rng, weights)
		if _unique_count(triplet) != triplet.size():
			dup_in_triplet = true
		for id in triplet:
			var r := String(cdb.get_card_data(String(id)).get("rarity", ""))
			if counts.has(r):
				counts[r] += 1
			total += 1
	_check(not dup_in_triplet, "no triplet contains a duplicate card")
	_check(total > 0, "weighted draft produced cards")
	var denom := maxf(total, 1)
	var pc := 100.0 * float(counts["common"]) / denom
	var pu := 100.0 * float(counts["uncommon"]) / denom
	var pr := 100.0 * float(counts["rare"]) / denom
	print("     rarity mix over %d draws: %.1f%% common / %.1f%% uncommon / %.1f%% rare"
		% [total, pc, pu, pr])
	_check(absf(pc - 30.0) <= 6.0, "commons land near 30%% (got %.1f%%)" % pc)
	_check(absf(pu - 50.0) <= 6.0, "uncommons land near 50%% (got %.1f%%)" % pu)
	_check(absf(pr - 20.0) <= 6.0, "rares land near 20%% (got %.1f%%)" % pr)


func _test_quick_deck(legal: Array, ss: Node) -> void:
	print("-- quick battle")
	ss.rng_seed = 424242
	ss.local_index = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = ss.rng_seed ^ ((ss.local_index + 1) * 0x6C62272E)
	var deck: Array[String] = ss.deal_unique_cards(legal, ss.DECK_TARGET, rng)
	_check(deck.size() == ss.DECK_TARGET,
		"quick battle builds a full deck")
	_check(_max_count(deck) == 1,
		"quick battle random deck is unique-first")


func _test_sealed_pool(legal: Array, ss: Node) -> void:
	print("-- sealed pool")
	ss.rng_seed = 98765
	ss.local_index = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = ss.rng_seed ^ ((ss.local_index + 1) * 0x6C62272E)
	var opened: Array[String] = ss.deal_unique_cards(legal, min(30, legal.size()), rng)
	_check(opened.size() == min(30, legal.size()),
		"sealed opens the expected number of distinct ids")
	_check(_max_count(opened) == 1,
		"sealed pool is unique-first when the legal pool is large enough")


func _test_campaign_rewards(cdb: Node) -> void:
	print("-- campaign card rewards")
	for act in [1, 2, 3]:
		for _i in range(20):
			var offer: Array = cdb.roll_card_reward(act, false, false, 8)
			_check(offer.size() == 8,
				"act %d recruit slate fills all 8 roll slots" % act)
			_check(_unique_count(offer) == offer.size(),
				"act %d recruit slate has no duplicate ids" % act)
	var boss_offer: Array = cdb.roll_card_reward(3, false, true, 3)
	_check(boss_offer.size() == 3, "boss card reward fills 3 rare slots")
	_check(_unique_count(boss_offer) == boss_offer.size(),
		"boss card reward has no duplicate ids")


func _test_bot_deck(bot: Node, ss: Node) -> void:
	print("-- practice bot")
	var deck: Array = bot.build_deck(24680)
	_check(deck.size() == ss.DECK_TARGET,
		"bot builds a full deck")
	_check(_max_count(deck) <= 2,
		"bot respects the max-copy fallback")
	_check(_unique_count(deck) >= min(18, deck.size()),
		"bot deck is varied (unique ids: %d)" % _unique_count(deck))


func _count_map(ids: Array) -> Dictionary:
	var counts := {}
	for raw_id in ids:
		var id := String(raw_id)
		counts[id] = int(counts.get(id, 0)) + 1
	return counts


func _unique_count(ids: Array) -> int:
	return _count_map(ids).size()


func _max_count(ids: Array) -> int:
	return _dict_max_count(_count_map(ids))


func _dict_max_count(counts: Dictionary) -> int:
	var max_seen := 0
	for value in counts.values():
		max_seen = maxi(max_seen, int(value))
	return max_seen
