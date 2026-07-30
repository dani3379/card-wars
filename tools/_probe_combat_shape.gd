extends SceneTree
## Read-only STATS dump for the 2026-07-27 combat-shape review: what the card
## economy and the enemy keyword load actually are, measured off the live DBs
## rather than eyeballed. Prints only — changes nothing.
##
##   Godot.exe --headless --path . --script res://tools/_probe_combat_shape.gd

var _done := false
var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _pct(n: int, tot: int) -> String:
	return "%5.1f%%" % (100.0 * float(n) / maxf(1.0, float(tot)))


func _run() -> void:
	var CDB = root.get_node_or_null("CardDB")
	var EDB = root.get_node_or_null("EncounterDB")
	if CDB == null or EDB == null:
		print("FATAL: CardDB/EncounterDB missing")
		_done = true
		quit(1)
		return

	# ── 1. player card economy ───────────────────────────────────────────────
	var by_rar := {}
	var cost_all := {}
	var type_cost := {"creature": {}, "spell": {}}
	var total := 0
	var pool: Array = CDB.CARD_POOL.values() if CDB.CARD_POOL is Dictionary \
		else Array(CDB.CARD_POOL)
	for cd in pool:
		if not (cd is Dictionary):
			continue
		var rar := String(cd.get("rarity", ""))
		if rar == "enemy" or rar == "":
			continue
		if bool(cd.get("is_curse", false)) or String(cd.get("id", "")).begins_with("curse"):
			continue
		var c := int(cd.get("cost", 0))
		var t := String(cd.get("type", ""))
		total += 1
		cost_all[c] = int(cost_all.get(c, 0)) + 1
		if not by_rar.has(rar):
			by_rar[rar] = {}
		by_rar[rar][c] = int(by_rar[rar].get(c, 0)) + 1
		if type_cost.has(t):
			type_cost[t][c] = int(type_cost[t].get(c, 0)) + 1

	print("=== PLAYER CARD ECONOMY (n=%d draftable, curses excluded) ===" % total)
	var keys := cost_all.keys()
	keys.sort()
	var cheap := 0
	for c in keys:
		print("  cost %d : %3d  %s" % [c, cost_all[c], _pct(cost_all[c], total)])
		if int(c) <= 1:
			cheap += int(cost_all[c])
	print("  --> cost<=1 is %s of the pool" % _pct(cheap, total))
	print("")
	for rar in ["starter", "common", "uncommon", "rare"]:
		if not by_rar.has(rar):
			continue
		var cc: Dictionary = by_rar[rar]
		var ks := cc.keys()
		ks.sort()
		var t := 0
		for k in ks:
			t += int(cc[k])
		var line := ""
		for k in ks:
			line += "%d:%d  " % [k, cc[k]]
		print("  %-9s n=%3d   %s" % [rar, t, line])
	print("")
	for t in ["creature", "spell"]:
		var cc: Dictionary = type_cost[t]
		var ks := cc.keys()
		ks.sort()
		var n := 0
		for k in ks:
			n += int(cc[k])
		var line := ""
		for k in ks:
			line += "%d:%d  " % [k, cc[k]]
		print("  %-9s n=%3d   %s" % [t, n, line])

	# ── 2. how much can actually be PLAYED per turn ─────────────────────────
	print("")
	print("=== PLAYS PER TURN (Command 3 base, banks <=2, hand refills to 5) ===")
	# Cheapest-first: how many cards can 3 / 4 / 5 Command buy from the average
	# hand? Approximate by the pool's cost distribution.
	var costs: Array[int] = []
	for c in keys:
		for _i in range(int(cost_all[c])):
			costs.append(int(c))
	costs.sort()
	var mean := 0.0
	for c in costs:
		mean += float(c)
	mean /= maxf(1.0, float(costs.size()))
	print("  mean printed cost : %.2f" % mean)
	print("  median            : %d" % costs[costs.size() / 2])
	for budget in [3, 4, 5]:
		# greedy cheapest-first over a random-ish 5-card hand = pool order
		var spent := 0
		var played := 0
		for c in costs:
			if spent + c <= budget:
				spent += c
				played += 1
			if played >= 5:
				break
		print("  Command %d -> up to %d cards if the hand is cheap" % [budget, played])

	# ── 3. enemy keyword load ────────────────────────────────────────────────
	print("")
	print("=== ENEMY KEYWORD LOAD (per creature entry in every encounter deck) ===")
	var kw_hist := {}
	var per_act := {1: [0, 0], 2: [0, 0], 3: [0, 0]}   # [creatures, keywords]
	var worst := []
	for enc_id in EDB.ENCOUNTERS.keys():
		var enc: Dictionary = EDB.ENCOUNTERS[enc_id]
		var act := int(enc.get("act", 1))
		for entry in enc.get("deck", []):
			var kws: Array = entry.get("kw", [])
			var n: int = kws.size()
			kw_hist[n] = int(kw_hist.get(n, 0)) + 1
			if per_act.has(act):
				per_act[act][0] += 1
				per_act[act][1] += n
			if n >= 3:
				worst.append("%s / %s (%d): %s" % [
					enc_id, String(entry.get("name", "?")), n, str(kws)])
	var kk := kw_hist.keys()
	kk.sort()
	var kwtot := 0
	for k in kk:
		kwtot += int(kw_hist[k])
	for k in kk:
		print("  %d keyword(s) : %3d creatures  %s" % [k, kw_hist[k], _pct(kw_hist[k], kwtot)])
	print("")
	for a in [1, 2, 3]:
		var c: int = per_act[a][0]
		var w: int = per_act[a][1]
		print("  act %d : %3d creatures, %.2f keywords each" % [a, c, float(w) / maxf(1.0, float(c))])
	print("")
	print("  creatures carrying 3+ keywords: %d" % worst.size())
	for line in worst:
		print("    " + String(line))

	_done = true
	quit(0)
