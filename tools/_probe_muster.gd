extends SceneTree
## _probe_muster.gd — gates THE WAR CHEST's four-slot writ model.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_muster.gd
##
## The old blessing pool failed in ways a data probe can catch, so each of those
## failures is an assertion here (see docs/RUN_OPENING_REDESIGN_20260728.md):
##   * four tiles in four unrelated currencies  -> every slate fills all 4 slots
##   * a "RISKY" tile that was the always-take  -> no boss relics anywhere
##   * an invisible, unrecoverable curse price  -> no curse can be granted
##   * the same seed dealing different gifts    -> the roll is reproducible
##   * a priced tile with no visible twin       -> the pact's twin is on screen

var _fails: Array[String] = []
var _ran := false


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails.append(label)


## _process, not _init: in a SceneTree script the autoloads do not exist yet
## during _init and quit() there does not take. This is the house probe shape.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var wdb: Node = root.get_node_or_null("WritDB")
	var rdb: Node = root.get_node_or_null("RelicDB")
	if wdb == null or rdb == null:
		print("[muster-probe] autoloads missing")
		quit(1)
		return true

	print("— slot pools are non-empty")
	for slot in ["roll", "arsenal", "purse"]:
		var ids: Array = wdb.ids_in_slot(slot)
		_check(not ids.is_empty(), "slot '%s' has at least one writ" % slot)

	print("— every slate fills all four slots, across 40 seeds")
	for s in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = s * 7919 + 13
		var slate: Array = wdb.roll_slate(rng)
		var slots: Array = []
		for e in slate:
			slots.append(String(e.get("slot", "")))
		var tag := "seed %d" % s
		_check(slate.size() == 4, tag + ": four tiles dealt")
		for want in ["roll", "arsenal", "purse", "pact"]:
			_check(want in slots, tag + ": slot '%s' present" % want)

		# The pact must escalate a tile the player can actually SEE. A price
		# whose twin is off-screen is the mystery the old RISKY chip was.
		for e in slate:
			if not bool(e.get("is_pact", false)):
				continue
			var twin := String(e.get("twin", ""))
			_check(twin != "", tag + ": pact names its twin")
			_check(twin in slots or _has_id(slate, twin),
				tag + ": pact's twin '%s' is on screen" % twin)

	print("— the roll is reproducible (Daily March fairness)")
	for s in [1, 99, 20260728]:
		var a := RandomNumberGenerator.new()
		var b := RandomNumberGenerator.new()
		a.seed = s
		b.seed = s
		var sa: Array = wdb.roll_slate(a)
		var sb: Array = wdb.roll_slate(b)
		var ida: Array = []
		var idb: Array = []
		for e in sa:
			ida.append(String(e.get("id", "")))
		for e in sb:
			idb.append(String(e.get("id", "")))
		_check(ida == idb, "seed %d deals the same four tiles twice" % s)

	print("— no curses, no boss relics, no lump sums")
	var boss_ids: Array = []
	for rid in rdb.RELICS:
		if String(rdb.RELICS[rid].get("tier", "")) == "boss":
			boss_ids.append(String(rid))
	var all_entries: Array = []
	for id in wdb.WRITS:
		all_entries.append(wdb.WRITS[id])
	for id in wdb.PACTS:
		all_entries.append(wdb.PACTS[id])
	for e in all_entries:
		var nm := String(e.get("name", e.get("desc", "?")))
		for key in ["relic", "relic2"]:
			var rid := String(e.get(key, ""))
			if rid == "":
				continue
			_check(not (rid in boss_ids), "%s grants no boss relic" % nm)
			_check(not rdb.get_relic(rid).is_empty(),
				"%s grants a relic that exists (%s)" % [nm, rid])
			_check(String(rdb.get_relic(rid).get("tier", "")) != "event",
				"%s grants no event-tier relic" % nm)
		var blob := (String(e.get("desc", "")) + " " + String(e.get("effect", ""))).to_lower()
		_check(not ("curse" in blob), "%s never mentions a curse" % nm)
		_check(not ("gold" in blob and "gain" in blob),
			"%s is not a flat gold lump" % nm)

	print("— every effect id has a resolver arm in MainMenu")
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenu.gd")
	for e in all_entries:
		var eff := String(e.get("effect", ""))
		_check(eff != "", "writ declares an effect")
		if eff == "":
			continue
		_check('"%s"' % eff in mm,
			"MainMenu._pick_blessing handles effect '%s'" % eff)

	print("— every pact prices in exactly one currency")
	_check(int(wdb.PACT_COST_MAX_HP) > 0, "the pact cost is a positive number")
	for id in wdb.PACTS:
		var d := String(wdb.PACTS[id].get("desc", ""))
		_check("max HP" in d, "pact '%s' states its price in the desc" % id)

	print("— every writ has a twin, so any dealt tile can be escalated")
	for id in wdb.WRITS:
		if String(wdb.WRITS[id].get("slot", "")) in ["roll", "purse"]:
			_check(wdb.PACTS.has(id), "writ '%s' has a pact twin" % id)

	print("— slot furniture exists for all four slots")
	for slot in ["roll", "arsenal", "purse", "pact"]:
		_check(wdb.SLOT_LABELS.has(slot), "slot '%s' has a label" % slot)
		_check(wdb.SLOT_HINTS.has(slot), "slot '%s' has a hint" % slot)

	print("— screen chrome is DB copy the wording lint can see")
	for key in ["title", "subtitle", "host_head_text", "column_head_text",
			"banner_head_text", "terms_head_text", "terms_rule_text",
			"seed_tooltip_text", "banner_card_fallback_text"]:
		_check(String(wdb.MUSTER_COPY.get(key, "")) != "",
			"opening copy key '%s' is authored" % key)
	# One screen, one name. The centre band and slot I were both "THE ROLL".
	_check(String(wdb.MUSTER_COPY.get("column_head_text", "")) \
		!= String(wdb.SLOT_LABELS.get("roll", "")).split("·")[-1].strip_edges(),
		"the centre band is not named the same as slot I")

	_check_banners(root)
	_check_openers(root)
	_check_preview_matches_commit(root)
	_check_determinism()
	_check_rematch_carries_banner()

	if _fails.is_empty():
		print("[muster-probe] ALL PASS")
		quit(0)
	else:
		print("[muster-probe] FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("  x ", f)
		quit(1)
	return true


func _has_id(slate: Array, id: String) -> bool:
	for e in slate:
		if String(e.get("id", "")) == id:
			return true
	return false


## THE BANNER is direction, not a second hero power. Every one of the six adds
## exactly one authored card, and that card must be unreachable from any draft
## pool — a banner card that leaked into Recruit would be a starter-rarity gift
## competing with the pool commons the starter contract exists to outrank.
func _check_banners(tree_root: Node) -> void:
	print("— every banner adds one authored, undraftable starter card")
	var bdb: Node = tree_root.get_node_or_null("BannerDB")
	var cdb: Node = tree_root.get_node_or_null("CardDB")
	if bdb == null or cdb == null:
		_fails.append("BannerDB/CardDB autoload missing")
		return
	_check(bdb.BANNER_ORDER.size() == 6, "six banners are offered")
	var seen_cards: Array[String] = []
	for bid in bdb.BANNER_ORDER:
		var b: Dictionary = bdb.BANNERS.get(bid, {})
		var tag := "banner '%s'" % bid
		_check(String(b.get("name", "")) != "", tag + " is named")
		_check(String(b.get("line_text", "")) != "", tag + " states its direction")
		var cid := String(b.get("card_id", ""))
		_check(cid != "", tag + " names a card")
		if cid == "":
			continue
		_check(not (cid in seen_cards), tag + " does not share a card with another")
		seen_cards.append(cid)
		var cd: Dictionary = cdb.get_card_data(cid)
		_check(not cd.is_empty(), tag + " card '%s' exists in CardDB" % cid)
		if cd.is_empty():
			continue
		_check(String(cd.get("rarity", "")) == "starter",
			tag + " card is starter rarity")
		_check(not bool(cd.get("draftable", true)),
			tag + " card is draftable: false")
		# The banner declares a tribe; its card must actually BE that tribe or the
		# declaration is decorative.
		_check(String(cd.get("ctype", "")) == String(bid),
			tag + " card carries the banner's own tribe")
		_check(cdb.UPGRADES.has(cid), tag + " card has a hand-crafted '+' entry")


## The opener contract: 10 hero cards + exactly one banner card, for every
## hero × banner crossing, and enough of a board and enough face reach that no
## crossing is a trap. Uses the pure static so this costs no map generation.
func _check_openers(tree_root: Node) -> void:
	print("— every hero x banner opener is 11 cards and can still fight")
	var rs: Node = tree_root.get_node_or_null("RunState")
	var hdb: Node = tree_root.get_node_or_null("HeroDB")
	var cdb: Node = tree_root.get_node_or_null("CardDB")
	var bdb: Node = tree_root.get_node_or_null("BannerDB")
	if rs == null or hdb == null or cdb == null or bdb == null:
		_fails.append("RunState/HeroDB autoload missing")
		return
	for hid in hdb.HERO_ORDER:
		for bid in bdb.BANNER_ORDER:
			for alt in [false, true]:
				var deck: Array = rs.opening_deck_for(String(hid), alt, String(bid))
				var tag := "%s / %s%s" % [hid, bid, " (alt)" if alt else ""]
				_check(deck.size() == 11, tag + ": opener is 11 cards")
				var creatures := 0
				var reach := 0
				var banner_copies := 0
				for cid in deck:
					var cd: Dictionary = cdb.get_card_data(String(cid))
					if String(cd.get("type", "")) == "creature":
						creatures += 1
					if String(cid) == bdb.card_id(String(bid)):
						banner_copies += 1
					if _reaches_face(cd):
						reach += 1
				_check(creatures >= 5, tag + ": at least 5 creatures (%d)" % creatures)
				_check(reach >= 2, tag + ": at least 2 sources of face reach (%d)" % reach)
				_check(banner_copies == 1,
					tag + ": exactly one copy of the banner card (%d)" % banner_copies)


## "Face reach" = this card can put damage on the enemy hero without needing a
## board to already be winning. Deliberately generous; it is a trap detector, not
## a power measure.
func _reaches_face(cd: Dictionary) -> bool:
	if cd.is_empty():
		return false
	if String(cd.get("type", "")) == "creature":
		# A body with ATK reaches the face once its lane clears.
		return int(cd.get("atk", 0)) > 0
	var spell: Dictionary = cd.get("spell", {})
	var stype := String(spell.get("type", ""))
	if stype in ["damage", "damage_face", "damage_all_enemies", "damage_any"]:
		return true
	return String(cd.get("targeting", "")) == "any"


## The screen prints the season and the rival deal BEFORE commit, from pure
## statics that duplicate the committing code. Duplication is the right call for
## a preview (re-calling start_new_run to back out re-rolls the seed, reopens the
## PlayLog session and drops the texture warm) — but duplication drifts, and a
## drifted preview is a lie printed on the one screen that promises it is not
## final yet. So compare the two sides against one real committed run.
func _check_preview_matches_commit(tree_root: Node) -> void:
	print("— the previewed season and rival deal equal the committed ones")
	var rs: Node = tree_root.get_node_or_null("RunState")
	if rs == null:
		_fails.append("RunState autoload missing")
		return
	# start_new_run writes no disk (see the save-safety note in the harness docs).
	for banner in ["soldier", "stray"]:
		rs.pending_banner_tribe = banner
		rs.start_new_run("raider", 0, 20260730)
		var tag := "banner '%s'" % banner
		var tribes: Array = rs.preview_season_tribes(20260730, banner)
		_check(Array(rs.season_tribes) == tribes,
			tag + ": previewed season equals the committed season")
		_check(rs.season_line_for(tribes) == rs.season_line(),
			tag + ": previewed season LINE equals the committed one")
		_check(tribes.size() == 2 and String(tribes[0]) == banner,
			tag + ": the declared tribe holds slot zero")
		var deal: Dictionary = rs.preview_rival_deal("raider", 20260730)
		_check(Array(deal.get("rival_lords", [])) == Array(rs.rival_lords),
			tag + ": previewed road lords equal the committed ones")
		_check(String(deal.get("finale_rival", "")) == String(rs.finale_rival),
			tag + ": previewed last claimant equals the committed one")
		_check(rs.current_banner_tribe == banner,
			tag + ": the run records the declaration it marched under")


## The three writ RESOLUTION rolls used the global stream until 2026-07-30, so a
## Daily March reproduced the four tiles and then dealt different consequences.
## Asserted against the source because the resolvers open modal pickers and
## cannot be driven headless.
func _check_determinism() -> void:
	print("— writ resolution rolls against the seeded stream, not the global one")
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenu.gd")
	_check("func _writ_rng()" in mm, "MainMenu owns a _writ_rng() stream")
	for site in [
			"_seeded_shuffle(pool, _writ_rng())",
			"pool[_writ_rng().randi() % pool.size()]",
			"RunState.current_hero_id, _writ_rng())"]:
		_check(site in mm, "seeded at: %s" % site)
	# The two globals these replaced must not come back.
	_check(not ("\tpool.shuffle()" in mm),
		"no writ path calls the global Array.shuffle()")
	_check(not ("pool[randi() % pool.size()]" in mm),
		"no writ path calls the global randi()")


## MARCH AGAIN never opens the screen, so every declaration it does not carry is
## silently reverted to a default. The doctrine pair learned this the hard way;
## the banner is the third field with the same failure mode.
func _check_rematch_carries_banner() -> void:
	print("— MARCH AGAIN carries the banner, not just the doctrine")
	var go := FileAccess.get_file_as_string("res://scripts/scenes/GameOver.gd")
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenu.gd")
	_check('"banner_tribe": RunState.current_banner_tribe' in go,
		"GameOver stashes the banner in rematch_request")
	_check('req.get("banner_tribe"' in mm,
		"MainMenu._start_rematch restores the banner")
