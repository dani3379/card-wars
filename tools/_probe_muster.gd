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

	print("— the pact is dealt into the slot BESIDE the term it escalates")
	# The pact's whole legibility claim is that its price reads as an exchange
	# rate against the quiet version of itself. That only works if the two are
	# adjacent: appended, roughly half of all deals put the pair at index 0 and
	# index 3, opposite ends of the row with two unrelated terms between them.
	# The screen has no legend explaining the relationship any more, so adjacency
	# is now the only thing that states it.
	for s in range(1, 60):
		var prng := RandomNumberGenerator.new()
		prng.seed = s ^ 0x57524954
		var pslate: Array = wdb.roll_slate(prng)
		var pact_at := -1
		var twin_at := -1
		var twin_id := ""
		for i in pslate.size():
			if bool((pslate[i] as Dictionary).get("is_pact", false)):
				pact_at = i
				twin_id = String((pslate[i] as Dictionary).get("twin", ""))
		for i in pslate.size():
			if String((pslate[i] as Dictionary).get("id", "")) == twin_id:
				twin_at = i
		_check(pact_at >= 0 and twin_at >= 0 and pact_at == twin_at + 1,
			"seed %d: the pact sits directly after its twin (pact %d, twin %d)"
				% [s, pact_at, twin_at])
	# Slot I must stay the first tile whatever the pact does to the order, because
	# _refresh_muster_deals auto-selects slate[0] as the standing choice.
	for s in range(1, 40):
		var orng := RandomNumberGenerator.new()
		orng.seed = s ^ 0x57524954
		var oslate: Array = wdb.roll_slate(orng)
		_check(String((oslate[0] as Dictionary).get("slot", "")) == "roll",
			"seed %d: the auto-selected default tile is still THE ROLL" % s)

	print("— slot furniture exists for all four slots")
	for slot in ["roll", "arsenal", "purse", "pact"]:
		_check(wdb.SLOT_LABELS.has(slot), "slot '%s' has a label" % slot)
		_check(wdb.SLOT_HINTS.has(slot), "slot '%s' has a hint" % slot)

	print("— screen chrome is DB copy the wording lint can see")
	# `terms_rule_text` was retired 2026-07-31 with the three-step split: it was
	# a legend teaching the player to read four tiles that each already print
	# their own slot rule, and the terms step has the width to let them.
	# `host_step_desc_text` / `banner_step_desc_text` went the same way 2026-08-01
	# — each restated something already printed on its own step. The banner
	# keys went with the banner system 2026-09-16. Only the bonus screen still
	# heads a desc line, because "choose one" is a rule no tile states.
	for key in ["title", "subtitle", "host_head_text", "column_head_text",
			"terms_head_text",
			"terms_step_desc_text",
			"seed_tooltip_text", "terms_screen_desc_text"]:
		_check(String(wdb.MUSTER_COPY.get(key, "")) != "",
			"opening copy key '%s' is authored" % key)
	print("— every house word on a dealt slate is defined on the screen")
	# The gloss is screen-scoped, so the contract is: if any dealt term uses a
	# glossed word, the screen prints exactly one definition; if none does, it
	# prints nothing rather than an empty line's worth of gap.
	for key in wdb.GLOSSARY_ORDER:
		_check(String(wdb.GLOSSARY.get("%s_text" % key, "")) != "",
			"house word '%s' has a definition" % key)
	var glossed_seeds := 0
	for s in range(1, 60):
		var grng := RandomNumberGenerator.new()
		grng.seed = s ^ 0x57524954
		var gslate: Array = wdb.roll_slate(grng)
		var joined := ""
		for e in gslate:
			joined += String((e as Dictionary).get("desc", "")).to_lower() + " "
		var wants := false
		for key in wdb.GLOSSARY_ORDER:
			if joined.contains(String(key)):
				wants = true
		var got: String = wdb.gloss_for_slate(gslate)
		_check(wants == (got != ""),
			"seed %d: a slate using a house word gets exactly one gloss" % s)
		if got != "":
			glossed_seeds += 1
	_check(glossed_seeds > 0, "the gloss is reachable at all on ordinary seeds")

	# One screen, one name. The centre band and slot I were both "THE ROLL".
	_check(String(wdb.MUSTER_COPY.get("column_head_text", "")) \
		!= String(wdb.SLOT_LABELS.get("roll", "")).split("·")[-1].strip_edges(),
		"the centre band is not named the same as slot I")

	_check_openers(root)
	_check_preview_matches_commit(root)
	_check_determinism()
	_check_rematch_carries_picks()
	_check_arsenal_preview(root)

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


## The opener contract: the hero's ten cards, for every hero x doctrine
## crossing, with enough of a board and enough face reach that no crossing is a
## trap. Uses the pure static so this costs no map generation.
##
## It used to read "10 hero cards + exactly one banner card" over hero x banner.
## The banner system was cut 2026-09-16; an opener is the deck HeroDB prints.
func _check_openers(tree_root: Node) -> void:
	print("— every hero opener is 10 cards and can still fight")
	var rs: Node = tree_root.get_node_or_null("RunState")
	var hdb: Node = tree_root.get_node_or_null("HeroDB")
	var cdb: Node = tree_root.get_node_or_null("CardDB")
	if rs == null or hdb == null or cdb == null:
		_fails.append("RunState/HeroDB autoload missing")
		return
	for hid in hdb.HERO_ORDER:
		for alt in [false, true]:
			var deck: Array = rs.opening_deck_for(String(hid), alt)
			var tag := "%s%s" % [hid, " (alt)" if alt else ""]
			_check(deck.size() == 10, tag + ": opener is 10 cards")
			var creatures := 0
			var reach := 0
			for cid in deck:
				var cd: Dictionary = cdb.get_card_data(String(cid))
				if String(cd.get("type", "")) == "creature":
					creatures += 1
				if _reaches_face(cd):
					reach += 1
			_check(creatures >= 5, tag + ": at least 5 creatures (%d)" % creatures)
			_check(reach >= 2, tag + ": at least 2 sources of face reach (%d)" % reach)
	# The opener strip is the first card art a player ever sees in a run, and a
	# card with no painting renders the empty-plate sigil. Checked over every
	# opener, because a new hero retinue card lands on the same strip.
	print("— every card that can appear in an opener resolves a painting")
	var art_seen: Dictionary = {}
	for hid in hdb.HERO_ORDER:
		for alt in [false, true]:
			for cid in rs.opening_deck_for(String(hid), alt):
				if art_seen.has(cid):
					continue
				art_seen[cid] = true
				var cd: Dictionary = cdb.get_card_data(String(cid))
				_check(not cd.is_empty(), "opener card '%s' exists" % cid)
				if cd.is_empty():
					continue
				_check(CardArtAliases.card_art_path(cd) != "",
					"opener card '%s' (%s) has art, not the empty sigil"
						% [cid, cd.get("name", "?")])

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
	for run_seed in [20260730, 913]:
		rs.start_new_run("raider", 0, run_seed)
		var tag := "seed %d" % run_seed
		var tribes: Array = rs.preview_season_tribes(run_seed)
		_check(Array(rs.season_tribes) == tribes,
			tag + ": previewed season equals the committed season")
		_check(rs.season_line_for(tribes) == rs.season_line(),
			tag + ": previewed season LINE equals the committed one")
		_check(tribes.size() == 2 and String(tribes[0]) != String(tribes[1]),
			tag + ": the season deals two DIFFERENT tribes")
		var deal: Dictionary = rs.preview_rival_deal("raider", run_seed)
		_check(Array(deal.get("rival_lords", [])) == Array(rs.rival_lords),
			tag + ": previewed road lords equal the committed ones")
		_check(String(deal.get("finale_rival", "")) == String(rs.finale_rival),
			tag + ": previewed last claimant equals the committed one")


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


## MARCH AGAIN never opens the screen, so every pick it does not carry is
## silently reverted to a default. The doctrine pair learned this the hard way.
func _check_rematch_carries_picks() -> void:
	print("— MARCH AGAIN carries the hero and the doctrine into RUN SETUP")
	var go := FileAccess.get_file_as_string("res://scripts/scenes/GameOver.gd")
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenu.gd")
	_check('"hero": RunState.current_hero_id' in go,
		"GameOver stashes the hero in rematch_request")
	_check('req.get("signature_relic"' in mm,
		"MainMenu._start_rematch restores the doctrine")
	# It is not enough to restore the picks: the rematch must enter THE MUSTER,
	# because _show_hero_select is the ONLY place that rolls _muster_random_seed
	# and the only place that deals _muster_writ_slate. Committing straight from
	# _start_rematch left both at their defaults — every rematch ran seed 1 (the
	# declaration default, randomised nowhere else) and dealt no opening term at
	# all, because `chosen` came back empty and the code faded to the map.
	_check("_show_hero_select(3)" in mm,
		"a rematch enters RUN SETUP (fresh seed + a dealt slate), not the commit")
	# _begin_run_with must have exactly ONE call site — TAKE THE FIELD. A second
	# one is how the rematch came to commit with no seed and no dealt slate.
	_check(mm.count("\t_begin_run_with(") == 1,
		"_begin_run_with has exactly one call site (the bonus tile)")


## THE ARSENAL prints the three relics it will offer BEFORE the run exists, so
## the tile stops being a blind pick beside three transparent ones. It has to
## reproduce _pick_blessing's roll exactly — same stream seed, same hero, same
## relics-already-held — or the screen names three relics the picker then does
## not deal, which is worse than printing nothing.
func _check_arsenal_preview(tree_root: Node) -> void:
	print("— THE ARSENAL's previewed relics are the ones it will actually offer")
	var rs: Node = tree_root.get_node_or_null("RunState")
	var hdb: Node = tree_root.get_node_or_null("HeroDB")
	var rdb: Node = tree_root.get_node_or_null("RelicDB")
	if rs == null or hdb == null or rdb == null:
		_fails.append("RunState/HeroDB/RelicDB autoload missing")
		return
	for hid in hdb.HERO_ORDER:
		for run_seed in [11, 20260731, 777]:
			var tag := "%s / seed %d" % [hid, run_seed]
			# The screen's side: pure inputs, no run in existence.
			var prng := RandomNumberGenerator.new()
			prng.seed = run_seed ^ 0x57524954 ^ 0x5245534F
			var signature := String(hdb.get_hero(String(hid)).get("relic", ""))
			var held: Array[String] = []
			if signature != "":
				held.append(signature)
			var previewed: Array = rdb.roll_foundation_relics(3, held, String(hid), prng)
			# The resolver's side: a real committed run.
			rs.start_new_run(String(hid), 0, run_seed)
			_check(Array(rs.relics) == held,
				tag + ": a fresh run holds exactly the signature relic")
			# The same expression _writ_rng() builds, off the COMMITTED seed.
			var rrng := RandomNumberGenerator.new()
			rrng.seed = int(rs.run_seed) ^ 0x57524954 ^ 0x5245534F
			var dealt: Array = rdb.roll_foundation_relics(
				3, Array(rs.relics), String(hid), rrng)
			_check(previewed.size() == 3, tag + ": three relics are offered")
			_check(previewed == dealt,
				tag + ": the previewed relics equal the dealt ones (%s vs %s)"
					% [previewed, dealt])
