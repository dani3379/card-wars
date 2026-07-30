extends SceneTree
## Post-reprice honesty check (2026-07-27). Answers three questions I asserted
## but had not measured:
##   A. Which "+" upgrades now produce a ZERO-cost card? (the reprice leaking back)
##   B. What does Discover hand out now? (its -2 discount vs a 2-centred pool)
##   C. How many cards does each opening deck actually PLAY per turn?
## Prints only; changes nothing.

var _started := false
var _done := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var CDB = root.get_node_or_null("CardDB")
	var HDB = root.get_node_or_null("HeroDB")
	if CDB == null or HDB == null:
		print("FATAL")
		_done = true
		quit(1)
		return

	print("=== A. UPGRADES that produce a 0-cost card ===")
	var leaks := 0
	for cid in CDB.UPGRADES.keys():
		var up: Dictionary = CDB.UPGRADES[cid]
		if not up.has("cost"):
			continue
		var base: Dictionary = CDB.get_card_data(String(cid))
		if base.is_empty():
			continue
		var b := int(base.get("cost", 0))
		var delta := int(up["cost"])
		var after: int = maxi(0, b + delta)
		var flag := "   <-- FREE" if after == 0 else ""
		if after == 0:
			leaks += 1
		print("  %-18s %d %+d -> %d%s" % [cid, b, delta, after, flag])
	print("  total upgrades producing a free card: %d" % leaks)

	print("")
	print("=== B. Discover pool (mirrors _add_discovered_card_to_hand) ===")
	var free_finds := 0
	var tot := 0
	for cd in CDB.CARD_POOL.values():
		if not (cd is Dictionary):
			continue
		var rar := String(cd.get("rarity", ""))
		if rar == "enemy" or rar == "" or rar == "starter":
			continue
		tot += 1
		# Must track Combat._add_discovered_card_to_hand exactly: -1, floored at 1,
		# and a printed 0/1 keeps its cost rather than being pushed up.
		var fc := int(cd.get("cost", 0))
		var after: int = fc if fc <= 1 else maxi(1, fc - 1)
		if after == 0:
			free_finds += 1
	print("  draftable non-starter cards: %d" % tot)
	print("  ...that a Discover would hand over FREE: %d (%.1f%%)" % [
		free_finds, 100.0 * float(free_finds) / maxf(1.0, float(tot))])

	print("")
	print("=== C. plays per turn, per opening deck (Cmd 3, bank<=2, refill 5) ===")
	for hid in HDB.HEROES.keys():
		var h: Dictionary = HDB.HEROES[hid]
		_sim(String(h.get("name", hid)), h.get("deck", []), CDB)
		var alt: Dictionary = h.get("deck_alt", {})
		if not alt.is_empty():
			_sim("  alt " + String(alt.get("name", "?")), alt.get("deck", []), CDB)
	_done = true
	quit(0)


func _sim(label: String, deck: Array, CDB) -> void:
	## Greedy cheapest-first over 400 sampled fights of 6 rounds.
	var costs: Array[int] = []
	for cid in deck:
		var cd: Dictionary = CDB.get_card_data(String(cid))
		if not cd.is_empty():
			costs.append(int(cd.get("cost", 0)))
	if costs.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var total_plays := 0.0
	var total_turns := 0
	var leftover := 0.0
	for _fight in range(400):
		var draw: Array[int] = costs.duplicate()
		draw.shuffle()
		var hand: Array[int] = []
		var banked := 0
		for _r in range(6):
			while hand.size() < 5:
				if draw.is_empty():
					draw = costs.duplicate()
					draw.shuffle()
				hand.append(draw.pop_back())
			var cmd: int = 3 + banked
			hand.sort()
			var played := 0
			var i := 0
			while i < hand.size():
				if hand[i] <= cmd:
					cmd -= hand[i]
					hand.remove_at(i)
					played += 1
				else:
					i += 1
			banked = mini(cmd, 2)
			leftover += float(cmd)
			total_plays += float(played)
			total_turns += 1
	print("  %-32s plays/turn %.2f   unspent %.2f" % [
		label, total_plays / float(total_turns), leftover / float(total_turns)])
