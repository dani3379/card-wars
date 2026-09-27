extends Node
## _probe_terms.gd — gates THE TERMS (step III of the run opening) against the
## three defects the 2026-08-01 audit found in WritDB's four-slot model.
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_terms.tscn
##
## Sibling of tools/_probe_muster.gd, which owns the STRUCTURAL contract (four
## slots filled, the roll reproducible, no curses / boss relics / lump sums, the
## pact adjacent to its twin, every effect id resolved in MainMenu). Nothing here
## duplicates that. This probe owns the three things _probe_muster cannot see:
##
##   1. THE AXES MUST STAY DISTINCT. The pact is by construction the escalated
##      twin of the ROLL or PURSE tile, so ONE axis is always doubled — that is
##      the design, and it is legible while the three free tiles are genuinely
##      three different axes. It stops being legible the moment two slots print
##      the same verb: on the old data seed 1 dealt "Forge 1 card" (ROLL),
##      "forge 2 cards at camp" (PURSE) and "Forge 2 cards" (PACT), so THREE of
##      four tiles said forge under a slot label that said "the road".
##      Gate: no dealt slate may print the same house verb on more than 2 tiles.
##
##   2. THE PURSE MUST BE A PURSE. Two of its four entries granted deck power
##      (collectors_tome: "Take 2 cards at each Recruit Camp"; whetstone:
##      "Reforge ... to upgrade 2 cards"). Gate: every relic a PURSE entry
##      grants must read, IN RELICDB'S OWN TEXT, as a rule about money, the
##      shop or the body — never about cards, forging or recruiting. The check
##      deliberately reads RelicDB rather than a list authored here, so it
##      cannot be satisfied by relabelling.
##
##   3. THE PACT'S TWO HALVES MUST COST THE SAME FOR THE SAME. Every pact bills
##      the identical 6 max HP, but the deck half bought one extra one-shot
##      action while the road half bought a whole second permanent relic.
##      Gate: WritDB.pact_delta_worth() must land inside the band declared in
##      WritDB (PACT_WORTH_MIN..MAX), and the two halves' means must agree.

const PROBE_NAME := "terms"

## House verbs, as the PLAYER reads them off the four tiles. Derived from prose,
## not from the declared `verb` field, so a mislabelled entry cannot hide a
## collapse — this is the check that fails on the old seed-1 slate.
const HOUSE_VERBS := [
	"forge", "strike", "enlist", "rarity", "relic", "recruit",
	"shop", "sell", "gold", "heal",
]

## A relic granted by THE PURSE must say at least one of these and none of the
## next list. Both are read against RelicDB's own desc.
const ROAD_WORDS := ["gold", "shop", "cost", "sell", "pays", "hp", "heal"]
const DECK_WORDS := [
	"upgrade", "forge", "reforge", "recruit", "rarity",
	"cards at", "card reward", "draft", "epithet", "kills instead",
]

## Tribe / hero words that would make a road rule inert for some openers
## (feedback_no_dead_rewards). A purse relic must be alive for all five hosts.
const GATED_WORDS := [
	"soldier", "beast", "dead ", "warlock", "bastion", "stray",
	"doom", "spell", "potion",
]

var _fails: Array[String] = []
var _checks := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(label)


func _ready() -> void:
	var wdb: Node = get_node_or_null("/root/WritDB")
	var rdb: Node = get_node_or_null("/root/RelicDB")
	if wdb == null or rdb == null:
		printerr("[terms] autoloads missing")
		get_tree().quit(1)
		return

	_dump_slates(wdb)
	_check_declared_verbs(wdb)
	_check_no_verb_collapse(wdb)
	_check_purse_is_a_purse(wdb, rdb)
	_check_granted_relics(wdb, rdb)
	_check_slot_vocabulary(wdb)
	_check_pact_band(wdb)

	print("[terms] %d checks" % _checks)
	if _fails.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for f in _fails:
		printerr("[terms] FAIL: " + f)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, _fails.size()])
	get_tree().quit(1)


## Informational. Prints the dealt row exactly as THE TERMS paints it, for the
## same seed expression MainMenu._refresh_muster_deals uses.
func _dump_slates(wdb: Node) -> void:
	for s in [1, 2, 3, 7, 99]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s ^ 0x57524954
		var slate: Array = wdb.roll_slate(rng)
		var line := "[terms] seed %d:" % s
		for e in slate:
			line += "\n    %-14s %-28s %s" % [
				String((e as Dictionary).get("slot", "?")).to_upper(),
				String((e as Dictionary).get("name", "?")),
				String((e as Dictionary).get("desc", ""))]
		print(line)


## Every entry declares the axis it moves, and a pact may never introduce an
## axis its twin does not already stand on. This is the machine-readable half of
## "the pact is the escalated twin" — without it a pact can quietly bolt a
## second, unrelated permanent onto a tile (the old Pact of the Armourer paid
## "camps forge 2 cards, AND shop goods cost a quarter less": two rules, two
## axes, one price).
func _check_declared_verbs(wdb: Node) -> void:
	print("— every term declares its axis, and no pact invents a new one")
	for id in wdb.WRITS:
		var w: Dictionary = wdb.WRITS[id]
		_check(String(w.get("verb", "")) != "", "writ '%s' declares a verb" % id)
	for id in wdb.PACTS:
		var p: Dictionary = wdb.PACTS[id]
		var twin: Dictionary = wdb.WRITS.get(id, {})
		_check(String(p.get("verb", "")) != "", "pact '%s' declares a verb" % id)
		_check(not twin.is_empty(), "pact '%s' has its twin in WRITS" % id)
		if twin.is_empty():
			continue
		_check(String(p.get("verb", "")) == String(twin.get("verb", "")),
			"pact '%s' moves the same axis as its twin (%s vs %s)"
				% [id, p.get("verb", ""), twin.get("verb", "")])
	# The other direction: a writ with no twin can be dealt into a slate whose
	# pact then has nothing to escalate. (_probe_muster asserts this for roll and
	# purse; repeated here only because the worth math below reads both halves.)
	for id in wdb.WRITS:
		if String(wdb.WRITS[id].get("slot", "")) in ["roll", "purse"]:
			_check(wdb.PACTS.has(id), "writ '%s' has a pact twin" % id)


## THE COLLAPSE GATE. Reads the four dealt descs as a player does and counts
## house verbs across tiles. Two tiles sharing a verb is the pact standing beside
## its twin, which is the whole design. Three is the bug.
func _check_no_verb_collapse(wdb: Node) -> void:
	print("— no dealt slate prints the same verb on more than two tiles")
	var worst := 0
	for s in range(1, 400):
		var rng := RandomNumberGenerator.new()
		rng.seed = s ^ 0x57524954
		var slate: Array = wdb.roll_slate(rng)
		var counts: Dictionary = {}
		for e in slate:
			var low := String((e as Dictionary).get("desc", "")).to_lower()
			for verb in HOUSE_VERBS:
				if low.contains(verb):
					counts[verb] = int(counts.get(verb, 0)) + 1
		for verb in counts:
			worst = maxi(worst, int(counts[verb]))
			_check(int(counts[verb]) <= 2,
				"seed %d: '%s' is printed on %d of 4 tiles (%s)"
					% [s, verb, int(counts[verb]), _slate_names(slate)])
	print("    worst verb repeat across 399 seeds: %d tiles" % worst)


func _slate_names(slate: Array) -> String:
	var out: Array[String] = []
	for e in slate:
		out.append(String((e as Dictionary).get("name", "?")))
	return " / ".join(out)


## THE SLOT LABEL MUST NOT LIE. Read against RelicDB's own desc, so it cannot be
## satisfied by rewording the tile.
func _check_purse_is_a_purse(wdb: Node, rdb: Node) -> void:
	print("— every PURSE entry grants an economy rule, not deck power")
	var purse_ids: Array = wdb.ids_in_slot("purse")
	_check(purse_ids.size() >= 3, "THE PURSE offers at least 3 terms")
	for id in purse_ids:
		var w: Dictionary = wdb.WRITS[id]
		_check(String(w.get("effect", "")) == "purse",
			"purse writ '%s' grants a standing rule, not a one-shot" % id)
		_audit_road_rule(rdb, String(w.get("relic", "")), "purse writ '%s'" % id)
	# The pact half grants the SAME kind of goods, so it is audited identically.
	for id in wdb.PACTS:
		var p: Dictionary = wdb.PACTS[id]
		if not String(p.get("effect", "")).begins_with("purse"):
			continue
		for key in ["relic", "relic2"]:
			var rid := String(p.get(key, ""))
			if rid != "":
				_audit_road_rule(rdb, rid, "pact '%s'" % id)
		_check(String(p.get("relic", "")) != String(p.get("relic2", "")),
			"pact '%s' grants two different rules" % id)


func _audit_road_rule(rdb: Node, rid: String, tag: String) -> void:
	var relic: Dictionary = rdb.get_relic(rid)
	_check(not relic.is_empty(), "%s names a relic that exists (%s)" % [tag, rid])
	if relic.is_empty():
		return
	var low := String(relic.get("desc", "")).to_lower()
	var road := false
	for word in ROAD_WORDS:
		if low.contains(word):
			road = true
	_check(road, "%s: '%s' reads as a road rule (desc: %s)"
		% [tag, rid, relic.get("desc", "")])
	for word in DECK_WORDS:
		_check(not low.contains(word),
			"%s: '%s' is DECK POWER, not economy — its desc says '%s' (%s)"
				% [tag, rid, word, relic.get("desc", "")])
	for word in GATED_WORDS:
		_check(not low.contains(word),
			"%s: '%s' is gated on '%s' and can be a dead reward for some hosts"
				% [tag, rid, word])


## Anything the opening puts on the relic rail has to be a real, live, unrestricted
## permanent. _probe_muster already bans boss and event tiers; this adds the three
## ways a grant can be silently inert.
func _check_granted_relics(wdb: Node, rdb: Node) -> void:
	print("— every granted relic is live, unrestricted and actually wired")
	var sources: Array[String] = _script_bodies()
	var ids: Array[String] = []
	for id in wdb.WRITS:
		_collect_relics(wdb.WRITS[id], ids)
	for id in wdb.PACTS:
		_collect_relics(wdb.PACTS[id], ids)
	for rid in ids:
		var relic: Dictionary = rdb.get_relic(rid)
		if relic.is_empty():
			continue
		_check(not bool(relic.get("retired", false)),
			"granted relic '%s' is not retired" % rid)
		_check(String(relic.get("restricted_to", "")) == "",
			"granted relic '%s' is not locked to one host" % rid)
		_check(int(relic.get("mana_cap_cost", 0)) == 0,
			"granted relic '%s' spends no Command-cap credit" % rid)
		var wired := false
		for body in sources:
			if body.contains('"%s"' % rid):
				wired = true
				break
		_check(wired, "granted relic '%s' is read somewhere in scripts/" % rid)


func _collect_relics(entry: Dictionary, out: Array[String]) -> void:
	for key in ["relic", "relic2"]:
		var rid := String(entry.get(key, ""))
		if rid != "" and not (rid in out):
			out.append(rid)


## Every .gd under scripts/ except the two databases that merely DECLARE relics.
func _script_bodies() -> Array[String]:
	var bodies: Array[String] = []
	var stack: Array[String] = ["res://scripts"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd") and name != "RelicDB.gd" and name != "WritDB.gd":
				bodies.append(FileAccess.get_file_as_string(full))
			name = dir.get_next()
		dir.list_dir_end()
	return bodies


## The slot words have to mean what they say: no ROLL term may promise a road
## rule, and no PURSE term may promise deck surgery.
func _check_slot_vocabulary(wdb: Node) -> void:
	print("— the slot labels tell the truth about their own terms")
	var roll_words := ["forge", "strike", "enlist", "rarity"]
	var road_words := ["shop", "gold", "sell"]
	for id in wdb.ids_in_slot("purse"):
		var low := String(wdb.WRITS[id].get("desc", "")).to_lower()
		for word in roll_words:
			_check(not low.contains(word),
				"purse term '%s' promises a deck verb ('%s') under 'the road'" % [id, word])
	for id in wdb.ids_in_slot("roll"):
		var low := String(wdb.WRITS[id].get("desc", "")).to_lower()
		for word in road_words:
			_check(not low.contains(word),
				"roll term '%s' promises a road rule ('%s') under 'your deck'" % [id, word])


## THE PRICING GATE. See WritDB's PACT_WORTH_* block for the unit and its
## derivation from the game's own posted prices; this only asserts the table
## stays inside the band and that the two halves agree.
func _check_pact_band(wdb: Node) -> void:
	print("— every pact buys the same amount for the same 6 max HP")
	var lo: float = float(wdb.PACT_WORTH_MIN)
	var hi: float = float(wdb.PACT_WORTH_MAX)
	_check(lo > 0.0 and hi > lo, "the band is a real interval")
	var deck_half: Array[float] = []
	var road_half: Array[float] = []
	for id in wdb.PACTS:
		var delta: float = float(wdb.pact_delta_worth(String(id)))
		var slot := String(wdb.WRITS.get(id, {}).get("slot", ""))
		print("    %-20s %+.2f forges  (%s)" % [id, delta, slot])
		_check(delta >= lo - 0.001 and delta <= hi + 0.001,
			"pact '%s' buys %.2f forges, outside the band %.2f..%.2f"
				% [id, delta, lo, hi])
		if slot == "roll":
			deck_half.append(delta)
		elif slot == "purse":
			road_half.append(delta)
	_check(not deck_half.is_empty(), "the deck half of the pact table is populated")
	_check(not road_half.is_empty(), "the road half of the pact table is populated")
	if deck_half.is_empty() or road_half.is_empty():
		return
	var deck_mean := _mean(deck_half)
	var road_mean := _mean(road_half)
	print("    deck half mean %.2f  ·  road half mean %.2f" % [deck_mean, road_mean])
	# 20% is the tolerance the band itself implies: two halves whose means differ
	# by more than a fifth of a forge-equivalent are not selling the same thing.
	_check(absf(deck_mean - road_mean) <= 0.20 * maxf(deck_mean, road_mean),
		"the two halves of the pact table agree (deck %.2f vs road %.2f)"
			% [deck_mean, road_mean])
	# And no pact may be more than the band's own spread dearer than another —
	# the failure the four-slot model exists to retire is one tile being the
	# always-take.
	var all: Array[float] = deck_half.duplicate()
	all.append_array(road_half)
	var mn: float = all[0]
	var mx: float = all[0]
	for v in all:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	_check(mx <= mn * (hi / lo) + 0.001,
		"dearest pact (%.2f) is within %.1fx of the cheapest (%.2f)"
			% [mx, hi / lo, mn])


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())
