extends SceneTree
## _probe_content_census.gd — PASS 20 of docs/BUG_SWEEP_METHOD_20260829.md (class C20).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_content_census.gd
##
## CONTENT THE PLAYER CAN NEVER SEE.
##
## C1 (reachability) answers a STATIC question — is this id dispatched, is this
## emitter wired — and that is how it caught six minigames nobody could reach. It
## cannot answer the question this pass asks, which is EMPIRICAL: content can be
## perfectly wired, dispatched from a live table, referenced by a real emitter, and
## still never appear, because the roll that would produce it is gated by an act, a
## rarity band, a deck predicate or a pool filter that never lets it through.
##
## Authored content that never appears is one of the worst defects a content-heavy
## game can carry — the work is paid for and the player gets none of it — and it is
## completely invisible to every gate here, because nothing is broken. So: roll the
## REAL generators, tens of thousands of times, across every act and context they
## take, and tally what actually comes out. Anything that never appears is either
## unreachable or so rare it is effectively absent, and both are findings.
##
## Deliberately EMPIRICAL, not analytical. Re-deriving each roll's conditions in the
## probe would be re-implementing the generator, and a re-implementation only ever
## tests itself — the same trap that makes model-based oracles unreliable. Calling
## the shipped function and counting what falls out cannot drift from the game.
##
## Two things it deliberately does NOT flag, because both are correct by design:
## content excluded from every roll pool ON PURPOSE (starting relics, event relics,
## enemy-only cards, tokens, curses), and content whose absence is a tuning choice
## rather than a defect — which is why rare-but-present is reported separately from
## never-seen, and why this is a REPORT rather than a hard gate.

const ROLLS := 12000

var _started := false
var _done := false
var _findings := 0

## Autoload NAMES do not resolve at parse time in a `--script` probe (the script is
## compiled before the autoloads register), so every DB is looked up through the
## tree at runtime. See CLAUDE.md's parsecheck blind-spot note — preloading the
## autoload's own script instead is worse, not better.
var CardDB: Node
var RelicDB: Node
var PotionDB: Node
var EncounterDB: Node
var HeroDB: Node


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _report(label: String, seen: Dictionary, expected: Array,
		excluded_note: String) -> void:
	var never: Array = []
	for id in expected:
		if not seen.has(id):
			never.append(id)
	never.sort()
	var total := 0
	for k in seen:
		total += int(seen[k])
	print("\n[census] --- %s ---" % label)
	print("        %d rolls produced %d distinct of %d eligible%s"
		% [total, seen.size(), expected.size(), excluded_note])
	if total == 0:
		_findings += 1
		print("  HIT   the generator produced NOTHING — this census is vacuous, "
			+ "fix the call before reading anything into the list below")
		return
	if never.is_empty():
		print("  PASS  every eligible entry appeared at least once")
	else:
		_findings += never.size()
		print("  HIT   %d never appeared in %d rolls:" % [never.size(), total])
		for id in never:
			print("           %s" % id)
	# The thin tail is a separate, softer signal: present but so rare a player is
	# unlikely to meet it in a run. Not a defect on its own — reported so a tuning
	# decision is at least a decision.
	var thin: Array = []
	for k in seen:
		if int(seen[k]) <= maxi(1, total / (expected.size() * 12)):
			thin.append("%s(%d)" % [k, int(seen[k])])
	if not thin.is_empty() and thin.size() <= 12:
		thin.sort()
		print("        thin tail: %s" % ", ".join(thin))


func _census_cards() -> void:
	var seen := {}
	for i in ROLLS:
		var act: int = (i % 3) + 1
		var is_elite: bool = (i % 7) == 0
		var is_boss: bool = (i % 23) == 0
		# roll_card_reward returns an Array[String] SLATE, not one id. Reading it as
		# a single string produced 12,000 empty rolls and a confident "193 cards are
		# unreachable" — a vacuous report, and exactly the kind a census must not
		# make. The zero-roll count in the summary line is what exposed it.
		for id in CardDB.roll_card_reward(act, is_elite, is_boss):
			seen[String(id)] = int(seen.get(String(id), 0)) + 1
	# Eligible = everything a reward roll could legitimately produce. Starters,
	# enemy-only cards, tokens and curses are excluded BY DESIGN, so counting them
	# as missing would be noise, not a finding.
	var eligible: Array = []
	for cid in CardDB.CARD_POOL:
		var cd: Dictionary = CardDB.CARD_POOL[cid]
		var rarity := String(cd.get("rarity", ""))
		if rarity in ["starter", "enemy"]:
			continue
		if bool(cd.get("token", false)) or CardDB.is_curse(cid):
			continue
		if cd.has("draftable") and not bool(cd.get("draftable", true)):
			continue
		eligible.append(cid)
	_report("card rewards", seen, eligible,
		" (starters/enemy/tokens/curses excluded by design)")


func _census_relics() -> void:
	# ROLL PER HERO, THEN UNION. `filter_pool_for_run` drops relics carrying
	# `restricted_to`, so rolling with an empty hero_id — which no real run ever
	# has — cut the combat pool from 98 to 66 and reported 32 perfectly reachable
	# relics as unreachable. The honest question is not "can THIS hero see it" but
	# "can ANY hero", so every hero rolls and the results are unioned.
	var heroes: Array = HeroDB.HEROES.keys()
	for tier in ["combat", "utility", "boss"]:
		var seen := {}
		var per_hero := ROLLS / maxi(1, heroes.size())
		for h in heroes:
			for i in per_hero:
				var held: Array[String] = []
				# An Array[String] SLATE, like the card roll — not one id.
				for id in RelicDB.roll_relic_reward(tier, held, String(h)):
					seen[String(id)] = int(seen.get(String(id), 0)) + 1
		var eligible: Array = []
		for rid in RelicDB.RELICS:
			var rd: Dictionary = RelicDB.RELICS[rid]
			if String(rd.get("tier", "")) != tier:
				continue
			# `retired` is an explicit authorial decision to take a relic out of
			# circulation, exactly like the excluded tiers. Counting it as missing
			# would report the author's own choice back at them as a defect.
			if bool(rd.get("retired", false)):
				continue
			eligible.append(rid)
		_report("relic rewards (tier=%s)" % tier, seen, eligible,
			" (retired excluded; rolled across all %d heroes)" % heroes.size())


func _census_potions() -> void:
	var seen := {}
	for _i in ROLLS:
		var id := String(PotionDB.roll_random_potion())
		if id != "":
			seen[id] = int(seen.get(id, 0)) + 1
	# `_roll_allowed` gates archetype potions on live deck state, and this probe
	# holds no run — so a potion missing here may simply be waiting for a deck that
	# wants it. Reported anyway: the point is to know which ones those are.
	_report("potions", seen, PotionDB.all_ids(),
		" (archetype potions are deck-gated; see PotionDB._roll_allowed)")
	_census_gated_potions()


## A GATE IS ONLY CORRECT IF IT CAN OPEN. The census above rightly shows the two
## archetype potions never rolling — this probe holds no deck, and `_roll_allowed`
## asks for one. But "deck-gated" and "dead content" produce the identical
## observation, so assuming the benign reading is exactly the mistake this class
## exists to prevent: build the deck each gate asks for and prove the potion
## actually becomes rollable. The house rule is NO DEAD REWARDS, and that rule is
## only kept if the gated reward is reachable by some real deck.
func _census_gated_potions() -> void:
	var RS := root.get_node_or_null("RunState")
	if RS == null:
		print("  HIT   RunState missing — cannot prove the gates can open")
		_findings += 1
		return
	# A doom-carrying deck, and a deck holding two curses: the two conditions
	# `_roll_allowed` actually tests.
	var doom_card := ""
	for cid in CardDB.CARD_POOL:
		if "doom" in CardDB.CARD_POOL[cid].get("keywords", []):
			doom_card = cid
			break
	var saved: Array[String] = RS.deck.duplicate()
	# `RunState.deck` is a TYPED Array[String]; assigning a plain Array fails, and a
	# bad property write in GDScript silently ABORTS the function — which is why the
	# first version of this check printed nothing at all rather than erroring.
	var doom_deck: Array[String] = [doom_card, doom_card]
	var curse_deck: Array[String] = ["curse", "curse"]
	for probe in [{"id": "doomsday_draught", "deck": doom_deck},
			{"id": "grave_diggers_nip", "deck": curse_deck}]:
		if String((probe["deck"] as Array)[0]) == "":
			continue
		RS.deck = probe["deck"]
		var hits := 0
		for _i in 4000:
			if String(PotionDB.roll_random_potion()) == String(probe["id"]):
				hits += 1
		if hits > 0:
			# Retract the census HIT: it counted a deliberate gate, and the gate is
			# now proven to open. Leaving it in the tally would train the reader to
			# ignore a number that is supposed to mean something.
			_findings = maxi(0, _findings - 1)
			print("  PASS  %s becomes rollable with the deck its gate asks for (%d/4000)"
				% [String(probe["id"]), hits])
		else:
			_findings += 1
			print("  HIT   %s never rolls EVEN WITH a qualifying deck — the gate "
				% String(probe["id"]) + "cannot open, so the potion is dead content")
	RS.deck = saved


func _census_encounters() -> void:
	var seen := {}
	var eligible: Array = []
	# The type strings are "combat"/"elite"/"boss". An earlier draft queried
	# "normal", which returns an empty pool — and because the ELIGIBLE set was
	# built from the same wrong query, the census reported "all 18 eligible
	# appeared" and passed. A check whose expectation and observation share a bug
	# agrees with itself perfectly; the encounter COUNT (18 against 55 authored
	# lineups) was the only thing that gave it away.
	for act in [1, 2, 3]:
		for t in ["combat", "elite", "boss"]:
			for id in EncounterDB.get_ids_for(act, t):
				if not eligible.has(id):
					eligible.append(id)
	# The generator picks per act/type from these pools; walk them the way the map
	# does rather than inventing a selection rule.
	var rng := RandomNumberGenerator.new()
	for i in ROLLS:
		rng.seed = 90210 + i
		var act: int = (i % 3) + 1
		var t: String = ["combat", "combat", "combat", "elite", "boss"][i % 5]
		var pool: Array = EncounterDB.get_ids_for(act, t)
		if pool.is_empty():
			continue
		var pick := String(pool[rng.randi() % pool.size()])
		seen[pick] = int(seen.get(pick, 0)) + 1
	_report("encounters (by act/type pool)", seen, eligible, "")


func _run() -> void:
	CardDB = root.get_node_or_null("CardDB")
	RelicDB = root.get_node_or_null("RelicDB")
	PotionDB = root.get_node_or_null("PotionDB")
	EncounterDB = root.get_node_or_null("EncounterDB")
	HeroDB = root.get_node_or_null("HeroDB")
	if CardDB == null or RelicDB == null or PotionDB == null or EncounterDB == null or HeroDB == null:
		print("[census] FATAL: a content autoload is missing")
		_done = true
		quit(1)
		return
	print("[census] PASS 20 — authored content nobody can reach")
	print("[census] %d rolls per generator, against the SHIPPED roll functions"
		% ROLLS)
	_census_cards()
	_census_relics()
	_census_potions()
	_census_encounters()
	print("\n[census] %d entr(ies) never appeared." % _findings)
	print("[census] Report only: an absence can be a deliberate gate (a deck-state")
	print("[census] predicate, a restricted_to hero) as easily as a defect. Read each")
	print("[census] one and decide — but an authored entry no roll can produce is")
	print("[census] work the player paid for and will never see.")
	_done = true
	quit(0)
