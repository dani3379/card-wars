extends SceneTree
## _probe_coverage.gd — PASS 26 of docs/BUG_SWEEP_METHOD_20260829.md (class C26).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_coverage.gd
##
## COVERAGE-GUIDED: measure what the TESTS reach, not whether the game is right.
##
## Twenty-five classes all ask a question about the game. This one asks a question
## about the suite: **which behaviours has any of it ever actually executed?**
##
## That question stopped being academic in Pass 25. A mutant halving MAX_BANKED_MANA
## escaped the golden corpus entirely — not because the digest was insensitive, but
## because no scenario ever banked Command, so the constant was never load-bearing
## in anything being measured. Every gate in this suite is vacuous over the code it
## never runs, and until now nothing has said which code that is. The automated-
## playtesting literature converges on the same instrument: measure coverage, then
## point the testing at what is uncovered.
##
## GDScript ships no line-coverage tool, so this measures BEHAVIOURAL coverage,
## which for a card game is the more useful axis anyway: the dispatch surface is the
## content. It plays random decks from the whole pool and records what actually
## FIRES — not what was dealt, but what resolved:
##
##   · which cards were really played onto a board
##   · which spell effect `type`s resolved
##   · which on-enter / on-death effect types dispatched
##   · which keywords appeared on a card that was actually played
##
## Then it diffs each against the full set the DBs define. The output is a map of
## the suite's blind spots — the effect types no test in this repository has ever
## executed once, where a bug could live untouched behind 25 green gates.
##
## It is a REPORT, not a gate. Low coverage is not a defect; it is a statement about
## where to spend the next effort, and pretending otherwise would make it noise.

const MATCHES := 14
const ROUND_CAP := 30

var SS: Node
var NM: Node
var US: Node
var CardDB: Node
var KeywordEffects: Node
var combat: Node

var _rng := RandomNumberGenerator.new()
var _started := false
var _done := false
var _fails := 0

var _played_cards := {}
var _spell_types := {}
var _enter_types := {}
var _death_types := {}
var _keywords := {}


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


## Record everything a played card COULD dispatch. This is an over-count relative
## to "the branch executed" — a card with an on_death only dispatches it when it
## dies — so the honest reading is: anything NOT here was certainly never reached,
## while something here was reachable. For a blind-spot map that asymmetry is the
## right one: it never claims coverage the suite does not have.
func _record_play(cd: Dictionary) -> void:
	var cid := String(cd.get("id", ""))
	if cid == "":
		return
	_played_cards[cid] = true
	for k in cd.get("keywords", []):
		_keywords[String(k)] = true
	var sp = cd.get("spell", null)
	if typeof(sp) == TYPE_DICTIONARY:
		var t := String((sp as Dictionary).get("type", ""))
		if t == "custom":
			t = "custom:%s" % String((sp as Dictionary).get("id", "?"))
		if t != "":
			_spell_types[t] = true
	var oe = cd.get("on_enter", null)
	if typeof(oe) == TYPE_DICTIONARY:
		_enter_types[String((oe as Dictionary).get("type", "?"))] = true
	var od = cd.get("on_death", null)
	if typeof(od) == TYPE_DICTIONARY:
		_death_types[String((od as Dictionary).get("type", "?"))] = true


## THE DENOMINATOR MUST MATCH WHAT THE DRIVER CAN REACH. Building it from the whole
## CARD_POOL counted hero-retinue and campaign-only spells — `starter_*` customs that
## are `draftable: false` and appear in no skirmish deck — as blind spots of a
## skirmish driver, which is not what they are. That is the same mistake the
## encounter census made when its eligible set came from the same wrong query as its
## observations; here it inflates the gap instead of hiding it, but a number that
## does not mean what it says is useless either way. `restrict_to` scopes it.
func _universe(restrict_to: Dictionary) -> Dictionary:
	var cards := {}
	var spells := {}
	var enters := {}
	var deaths := {}
	var kws := {}
	for cid in CardDB.CARD_POOL:
		var cd: Dictionary = CardDB.CARD_POOL[cid]
		if String(cd.get("rarity", "")) == "enemy" or bool(cd.get("token", false)):
			continue
		if not restrict_to.is_empty() and not restrict_to.has(cid):
			continue
		cards[cid] = true
		for k in cd.get("keywords", []):
			kws[String(k)] = true
		var sp = cd.get("spell", null)
		if typeof(sp) == TYPE_DICTIONARY:
			var t := String((sp as Dictionary).get("type", ""))
			if t == "custom":
				t = "custom:%s" % String((sp as Dictionary).get("id", "?"))
			if t != "":
				spells[t] = true
		var oe = cd.get("on_enter", null)
		if typeof(oe) == TYPE_DICTIONARY:
			enters[String((oe as Dictionary).get("type", "?"))] = true
		var od = cd.get("on_death", null)
		if typeof(od) == TYPE_DICTIONARY:
			deaths[String((od as Dictionary).get("type", "?"))] = true
	return {"cards": cards, "spells": spells, "enters": enters,
		"deaths": deaths, "keywords": kws}


func _report(label: String, seen: Dictionary, all: Dictionary) -> void:
	var missing: Array = []
	for k in all:
		if not seen.has(k):
			missing.append(k)
	missing.sort()
	var pct := 0.0
	if all.size() > 0:
		pct = 100.0 * float(all.size() - missing.size()) / float(all.size())
	print("\n[cov] %-22s %3d/%3d exercised (%.0f%%)" % [
		label, all.size() - missing.size(), all.size(), pct])
	if missing.is_empty():
		print("        everything in this category was reached")
		return
	print("        NEVER EXERCISED (%d):" % missing.size())
	var line := "        "
	for m in missing:
		if line.length() + String(m).length() > 96:
			print(line)
			line = "        "
		line += String(m) + "  "
	if line.strip_edges() != "":
		print(line)


func _boot(seed_val: int, style: int, pool: Array) -> bool:
	SS.reset()
	for _s in 2:
		var idx := _s
		for _i in 20:
			SS.add_card_to(idx, String(pool[_rng.randi() % pool.size()]))
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = seed_val
	SS.vs_bot = true
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.battle_style = style
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	var last := -1
	var stable := 0
	for _i in 30:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat):
			return false
		var n: int = combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 3:
			break
	return is_instance_valid(combat)


func _first_empty_slot() -> Control:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			if arr[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


## Poll until the hand has finished ARRIVING, not just until input is accepted.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. A driver that starts there is playing a hand the
## game has not finished dealing it: on round 1 that is ONE card of five, and at
## Command 1 a single 2-drop means the whole turn plays nothing.
##
## Rounds 2+ hide it, because the hand is PERSISTENT and carries unplayed stock
## forward — so the fault is worst exactly where round-1 measurements live. It
## cost `_probe_deploy_curve` a published number before it was found; see
## CLAUDE.md's settle-until-stable note.
##
## Stability polling, NOT a computed deal window: draw_count is the ramp plus
## four relics plus two mutators, and restating that arithmetic in a probe is
## the duplicate-rule pathology. Bounded, because an unbounded `while await`
## spins to the harness timeout and reports NOTHING at all.
func _settle_hand() -> void:
	const SETTLE_TICK := 0.03    # poll interval
	const STABLE_TICKS := 5      # 0.15s unchanged, a 1.9x margin on the 0.08s gap
	const SETTLE_BUDGET := 40    # ~1.2s ceiling
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _play_turn() -> void:
	for _pass in 10:
		if not is_instance_valid(combat):
			return
		var acted := false
		for card in combat._hand.duplicate():
			if card == null or not is_instance_valid(card):
				continue
			if combat._effective_cost(card) > combat.player_mana:
				continue
			var cd: Dictionary = card.card_data.duplicate(true)
			if card.is_creature():
				var slot := _first_empty_slot()
				if slot == null:
					continue
				card.global_position = slot.get_global_rect().get_center() \
					- card.size * 0.5
				combat._on_card_played(card)
			else:
				combat._on_card_played(card)
				await create_timer(0.05).timeout
				if is_instance_valid(combat) and combat._targeting_spell != null:
					var foes = combat._all_enemy_creatures()
					var mine = combat._all_player_creatures()
					if not foes.is_empty():
						combat._try_resolve_target(combat._card_center(foes[0]))
					elif not mine.is_empty():
						combat._try_resolve_target(combat._card_center(mine[0]))
					else:
						combat._cancel_targeting()
			_record_play(cd)
			await create_timer(0.05).timeout
			acted = true
			break
		if not acted:
			break
	if is_instance_valid(combat):
		combat._net_on_done_placing()
		await create_timer(0.35).timeout


func _run() -> void:
	print("[cov] PASS 26 — what has the suite actually executed?\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	CardDB = root.get_node_or_null("CardDB")
	if SS == null or NM == null or CardDB == null:
		print("[cov] FATAL: autoloads missing"); _done = true; quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
	_rng.seed = 424242

	var pool: Array = SS.skirmish_legal_pool()
	var ran := 0
	for m in MATCHES:
		var style: int = m % 2
		if not await _boot(50000 + m * 977, style, pool):
			continue
		ran += 1
		var stalls := 0
		while is_instance_valid(combat) and not combat._net_match_over \
				and int(combat.round_number) < ROUND_CAP:
			var mine: bool
			if style == NM.STYLE_SEALED:
				mine = combat._sorcery_active == NM.local_player_index \
					or (combat._sorcery_active < 0 and not combat._sealed_await_foe \
						and combat.phase == combat.Phase.PLAYER_TURN)
			else:
				mine = combat._net_active_index == NM.local_player_index \
					and combat.phase == combat.Phase.PLAYER_TURN
			if not mine:
				stalls += 1
				if stalls > 400:
					break
				await create_timer(0.05).timeout
				continue
			stalls = 0
			await _settle_hand()
			await _play_turn()
		if is_instance_valid(combat):
			combat.queue_free()
		await create_timer(0.25).timeout

	print("[cov] %d matches driven with random decks from a %d-card pool"
		% [ran, pool.size()])
	_check(ran > 0, "matches actually ran")
	_check(_played_cards.size() > 20,
		"cards were actually PLAYED, not merely dealt (%d distinct)"
			% _played_cards.size())

	# The denominator is the SKIRMISH-LEGAL pool throughout: a campaign-only card is
	# not a blind spot of a skirmish driver, it is out of scope.
	var legal := {}
	for id in pool:
		legal[String(id)] = true
	var u := _universe(legal)
	var whole := _universe({})
	_report("skirmish cards", _played_cards, legal)
	_report("spell effect types", _spell_types, u["spells"])
	_report("on-enter effects", _enter_types, u["enters"])
	_report("on-death effects", _death_types, u["deaths"])
	_report("keywords", _keywords, u["keywords"])

	# AND THE SURFACE THIS DRIVER CANNOT REACH AT ALL, which is a finding in its own
	# right: the campaign has no coverage driver, so these effect types are executed
	# by nothing anywhere in the repository.
	var campaign_only := 0
	for t in whole["spells"]:
		if not (u["spells"] as Dictionary).has(t):
			campaign_only += 1
	print("\n[cov] %d further spell effect types are CAMPAIGN-ONLY and outside this"
		% campaign_only)
	print("[cov] driver's reach. `_probe_autorun` soaks campaign combat, so some are")
	print("[cov] likely covered there — but no pass MEASURES that, so it is unknown")
	print("[cov] rather than uncovered. A campaign-side twin of this pass would say.")

	print("\n[cov] REPORT ONLY, AND READ THE SCOPE. This is the reach of ONE driver")
	print("[cov] over %d matches, not of the whole suite — a card absent here may" % ran)
	print("[cov] simply not have been drawn, and other probes exercise things this")
	print("[cov] one does not. What it does establish is a floor: an effect type no")
	print("[cov] random-deck match ever triggered is surface where the other gates")
	print("[cov] have nothing to say, and that is where a bug hides behind green.")
	print("\n[cov] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
