extends Node
## _probe_encounter_seed.gd — THE ARMY YOU FACE IS PART OF THE SEED.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_encounter_seed.tscn
##
## Runs as a SCENE so the autoload identifiers (EncounterDB / RunState / HeroDB)
## resolve, and so it can boot the real combat scene at the end.
##
## THE BUG THIS GATES (fixed 2026-08-01). Many encounters carry authored
## `deck_variants` (alternate lineups) and `reinforcement_pool` (alternate
## infinite backup bodies). Both picks used to be rolled with a bare `randi()`,
## i.e. on Godot's GLOBAL stream — which is stirred by every unrelated cosmetic
## call and is not seeded from the run at all. So two players on the same Daily
## March seed got the same map, the same opening hand and the same opening
## gifts, and then fought DIFFERENT armies. Same class of bug as the
## writ-resolution seeding pass.
##
## THE FIX HAS TWO HALVES AND A NAIVE TEST ONLY SEES ONE. Pinning everyone to
## `options[0]` would pass any "same seed twice" check while quietly deleting
## every authored variant from the game. So each half is asserted separately:
##
##   A. INVENTORY — how many encounters actually have alternatives. If this is
##      zero the whole probe is vacuous, so it fails loudly.
##   B. THE DATA LAYER TAKES A STREAM — same rng seed twice gives the same
##      lineup, AND sweeping seeds reaches EVERY authored option (observed set
##      == authored set, in both directions: nothing pinned, nothing invented).
##      The `rng == null` path still rolls globally, because the offline
##      analysis probes (_probe_sweep2, _probe_encwin, _probe_perf) pass two
##      args and want variety across repeats.
##   C. SOURCE GUARD — no bare `randi()` survives in EncounterDB, and every
##      Combat call site hands a stream in. This is the half that catches a
##      REGRESSION with certainty; a behavioural test on a 2-option encounter
##      would false-pass half the time.
##   D. THE REAL HELPER — Combat._encounter_roll_stream driven with real run
##      seeds: pure function of (run seed x fight), reaches every variant, and
##      is NOT perturbed by prior _combat_ops draws (the whole reason it is a
##      derived stream instead of a ride on the shared one).
##   E. THE LIVE PATH — boot combat.tscn twice on one seed and assert the fight
##      that actually got set up is identical, and matches what the helper
##      predicts. A fix that never reached _setup_fight_state would pass A-D.

const COMBAT_SCENE := "res://scenes/combat.tscn"
const COMBAT_SCRIPT := "res://scripts/scenes/Combat.gd"
const ENCOUNTER_DB_SRC := "res://scripts/data/EncounterDB.gd"
const COMBAT_SRC := "res://scripts/scenes/Combat.gd"

## Enough seeds that missing an option means it is genuinely unreachable, not
## unlucky: the thinnest pool here is 2 options, the widest 4.
const SWEEP := 600

var _fails := 0
var _deck_encounters: Array[String] = []      # ids carrying deck_variants
var _reinf_encounters: Array[String] = []     # ids carrying reinforcement_pool
var _fixture := ""                            # act-1 combat with deck_variants


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_fails += 1


# ── signatures ────────────────────────────────────────────────────────────
# make_card_data stamps a MONOTONIC counter into `id`, so ids are never equal
# across two builds of the same deck. Identity is the authored NAME (plus the
# printed body for the reinforcement, which act-scaling can move).
func _names(deck: Array) -> String:
	var parts: Array[String] = []
	for cd in deck:
		parts.append(String((cd as Dictionary).get("name", "?")))
	return "|".join(parts)


func _raw_names(option: Array) -> String:
	var parts: Array[String] = []
	for raw in option:
		parts.append(String((raw as Dictionary).get("name", "?")))
	return "|".join(parts)


func _body(cd: Dictionary) -> String:
	return "%s/%d/%d" % [String(cd.get("name", "?")),
		int(cd.get("atk", 0)), int(cd.get("hp", 0))]


func _deck_options(enc: Dictionary) -> Array:
	var out: Array = [enc.deck]
	for v in enc.get("deck_variants", []):
		out.append(v)
	return out


func _reinf_options(enc: Dictionary) -> Array:
	var out: Array = [enc.reinforcement]
	for p in enc.get("reinforcement_pool", []):
		out.append(p)
	return out


func _ready() -> void:
	_inventory()
	_data_layer()
	_source_guard()
	_real_helper()
	await _live_path()

	print("[encounter-seed] %s" % ("ALL PASS" if _fails == 0
		else "%d FAILURES" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


# ── A. inventory ──────────────────────────────────────────────────────────
func _inventory() -> void:
	print("\n[encounter-seed] ===== A. what actually varies =====")
	var deck_opts := 0
	var reinf_opts := 0
	for id in EncounterDB.ENCOUNTERS:
		var eid := String(id)
		var enc: Dictionary = EncounterDB.ENCOUNTERS[eid]
		if (enc.get("deck_variants", []) as Array).size() > 0:
			_deck_encounters.append(eid)
			deck_opts += _deck_options(enc).size()
			if _fixture == "" and int(enc.get("act", 0)) == 1 \
					and String(enc.get("type", "")) == "combat":
				_fixture = eid
		if (enc.get("reinforcement_pool", []) as Array).size() > 0:
			_reinf_encounters.append(eid)
			reinf_opts += _reinf_options(enc).size()
	print("[encounter-seed] %d encounters total" % EncounterDB.ENCOUNTERS.size())
	print("[encounter-seed] %d carry deck_variants (%d lineups in play):"
		% [_deck_encounters.size(), deck_opts])
	for eid in _deck_encounters:
		var e: Dictionary = EncounterDB.ENCOUNTERS[eid]
		print("    %-22s act%d %-7s %d lineups"
			% [eid, int(e.get("act", 0)), String(e.get("type", "")),
				_deck_options(e).size()])
	print("[encounter-seed] %d carry reinforcement_pool (%d bodies in play)"
		% [_reinf_encounters.size(), reinf_opts])
	var by_act := {}
	for eid in _reinf_encounters:
		var a := int((EncounterDB.ENCOUNTERS[eid] as Dictionary).get("act", 0))
		by_act[a] = int(by_act.get(a, 0)) + 1
	print("[encounter-seed]   by act: %s" % str(by_act))

	_check(_deck_encounters.size() > 0, "A: some encounter carries deck_variants")
	_check(_reinf_encounters.size() > 0, "A: some encounter carries reinforcement_pool")
	_check(_fixture != "", "A: found an act-1 combat fixture with variants (%s)" % _fixture)


# ── B. the data layer takes a stream ──────────────────────────────────────
func _data_layer() -> void:
	print("\n[encounter-seed] ===== B. EncounterDB honours a supplied stream =====")
	var rng := RandomNumberGenerator.new()

	# --- decks ---
	var stuck: Array[String] = []
	var leaked: Array[String] = []
	var unstable: Array[String] = []
	for eid in _deck_encounters:
		var enc: Dictionary = EncounterDB.ENCOUNTERS[eid]
		var want := {}
		for opt in _deck_options(enc):
			want[_raw_names(opt)] = true
		var seen := {}
		for s in range(SWEEP):
			rng.seed = 9000 + s * 131
			seen[_names(EncounterDB.build_enemy_deck(eid, 0, rng))] = true
		for sig in seen:
			if not want.has(sig):
				leaked.append(eid)
				break
		for sig in want:
			if not seen.has(sig):
				stuck.append(eid)
				break
		# Determinism: one seed, two builds.
		for s in [11, 5150, 987654]:
			rng.seed = s
			var a := _names(EncounterDB.build_enemy_deck(eid, 0, rng))
			rng.seed = s
			var b := _names(EncounterDB.build_enemy_deck(eid, 0, rng))
			if a != b:
				unstable.append(eid)
				break
	_check(unstable.is_empty(),
		"B: same rng seed builds the same lineup twice (%d encounters)"
			% _deck_encounters.size())
	_check(stuck.is_empty(),
		"B: every authored lineup is still reachable across seeds%s"
			% ("" if stuck.is_empty() else " — UNREACHABLE: %s" % str(stuck)))
	_check(leaked.is_empty(),
		"B: no lineup appears that was never authored%s"
			% ("" if leaked.is_empty() else " — %s" % str(leaked)))

	# --- reinforcements ---
	var r_stuck: Array[String] = []
	var r_leaked: Array[String] = []
	var r_unstable: Array[String] = []
	for eid in _reinf_encounters:
		var enc: Dictionary = EncounterDB.ENCOUNTERS[eid]
		var want := {}
		for opt in _reinf_options(enc):
			want[String((opt as Dictionary).get("name", "?"))] = true
		var seen := {}
		for s in range(SWEEP):
			rng.seed = 400000 + s * 977
			seen[String(EncounterDB.get_reinforcement(eid, 0, rng).get("name", "?"))] = true
		for sig in seen:
			if not want.has(sig):
				r_leaked.append(eid)
				break
		for sig in want:
			if not seen.has(sig):
				r_stuck.append(eid)
				break
		for s in [77, 31337, 6060842]:
			rng.seed = s
			var a := _body(EncounterDB.get_reinforcement(eid, 0, rng))
			rng.seed = s
			var b := _body(EncounterDB.get_reinforcement(eid, 0, rng))
			if a != b:
				r_unstable.append(eid)
				break
	_check(r_unstable.is_empty(),
		"B: same rng seed rolls the same reinforcement twice (%d encounters)"
			% _reinf_encounters.size())
	_check(r_stuck.is_empty(),
		"B: every authored reinforcement body is still reachable%s"
			% ("" if r_stuck.is_empty() else " — UNREACHABLE: %s" % str(r_stuck)))
	_check(r_leaked.is_empty(),
		"B: no reinforcement appears that was never authored%s"
			% ("" if r_leaked.is_empty() else " — %s" % str(r_leaked)))

	# --- the null path still works, and still varies ---
	# _probe_sweep2 / _probe_encwin / _probe_perf / _probe_conquest_scaffold all
	# call with two args. A default that broke them would be a silent tax.
	var null_ok := true
	var null_seen := {}
	for eid in _deck_encounters:
		var d: Array = EncounterDB.build_enemy_deck(eid, 2)
		if d.is_empty():
			null_ok = false
	for i in range(SWEEP):
		null_seen[_names(EncounterDB.build_enemy_deck(_deck_encounters[0], 0))] = true
	_check(null_ok, "B: the no-rng call still builds a deck (offline probes keep working)")
	_check(null_seen.size() > 1,
		"B: the no-rng call still rolls globally (%d lineups over %d calls)"
			% [null_seen.size(), SWEEP])


# ── C. source guard ───────────────────────────────────────────────────────
func _source_guard() -> void:
	print("\n[encounter-seed] ===== C. no route back to the global stream =====")
	var edb := FileAccess.get_file_as_string(ENCOUNTER_DB_SRC)
	_check(edb != "", "C: read EncounterDB source")
	# A BARE `randi()` (and `Array.shuffle()`, same thing) is the global stream:
	# no run seeds it and no second machine can reproduce it. `<stream>.randi()`
	# is a seeded draw and is fine. The one sanctioned bare call is _roll_index's
	# documented `rng == null` fallback, excused below by its exact text.
	const NULL_RNG_FALLBACK := "return randi() % size"
	var offenders: Array[String] = []
	var ln := 0
	for line in edb.split("\n"):
		ln += 1
		var raw := String(line)
		var code := raw.strip_edges()
		if code.begins_with("#") or code == NULL_RNG_FALLBACK:
			continue
		var bad := raw.find(".shuffle()") != -1
		var at := raw.find("randi()")
		while at != -1:
			if at == 0 or raw[at - 1] != ".":
				bad = true
			at = raw.find("randi()", at + 1)
		if bad:
			offenders.append("L%d: %s" % [ln, code])
	_check(offenders.is_empty(),
		"C: EncounterDB has no unseeded roll left%s"
			% ("" if offenders.is_empty() else " — %s" % str(offenders)))

	var combat_src := FileAccess.get_file_as_string(COMBAT_SRC)
	_check(combat_src != "", "C: read Combat source")
	for fn in ["EncounterDB.build_enemy_deck(", "EncounterDB.get_reinforcement("]:
		var from := 0
		var sites := 0
		var bare := 0
		while true:
			var at := combat_src.find(fn, from)
			if at == -1:
				break
			sites += 1
			from = at + fn.length()
			# The call spans two lines; look far enough ahead to see the argument.
			if combat_src.substr(at, 260).find("_encounter_roll_stream") == -1:
				bare += 1
		_check(sites > 0, "C: Combat still calls %s (%d sites)" % [fn, sites])
		_check(bare == 0,
			"C: every %s site in Combat hands in a seeded stream (%d bare)"
				% [fn, bare])


# ── D. the real helper ────────────────────────────────────────────────────
func _real_helper() -> void:
	print("\n[encounter-seed] ===== D. Combat._encounter_roll_stream =====")
	if _fixture == "":
		_check(false, "D: no fixture encounter")
		return
	# A bare instance, never added to the tree: _ready (the whole combat boot)
	# never fires, but _combat_seed / _encounter_roll_stream are pure reads of
	# RunState and combat_mode (SOLO by declaration default).
	var c: Control = (load(COMBAT_SCRIPT) as GDScript).new()
	var salt_deck: int = c.ENC_ROLL_SALT_DECK
	var salt_reinf: int = c.ENC_ROLL_SALT_REINFORCEMENT
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_encounter_id = _fixture
	RunState.current_node_type = "combat"
	RunState.current_floor = 3

	var enc: Dictionary = EncounterDB.ENCOUNTERS[_fixture]
	var deck_want := {}
	for opt in _deck_options(enc):
		deck_want[_raw_names(opt)] = true
	var reinf_want := {}
	for opt in _reinf_options(enc):
		reinf_want[String((opt as Dictionary).get("name", "?"))] = true

	var deck_seen := {}
	var reinf_seen := {}
	var pairs := {}
	var unstable := 0
	var seed_to_deck := {}
	for s in range(SWEEP):
		RunState.run_seed = 500 + s * 7
		var d := _names(EncounterDB.build_enemy_deck(_fixture, 1,
			c._encounter_roll_stream(salt_deck)))
		var r := String(EncounterDB.get_reinforcement(_fixture, 1,
			c._encounter_roll_stream(salt_reinf)).get("name", "?"))
		# Pure function of the run seed: ask twice, and stir the SHARED gameplay
		# stream in between. That second half is the point of the derived stream
		# — a composition roll must not move because some upstream beat happened
		# to draw one more time from _combat_ops.
		for _i in range(5):
			c._combat_ops.rangei(0, 999)
		var d2 := _names(EncounterDB.build_enemy_deck(_fixture, 1,
			c._encounter_roll_stream(salt_deck)))
		if d != d2:
			unstable += 1
		deck_seen[d] = true
		reinf_seen[r] = true
		pairs["%s##%s" % [d, r]] = true
		if not seed_to_deck.has(d):
			seed_to_deck[d] = int(RunState.run_seed)
	_check(unstable == 0,
		"D: the roll is a pure function of (run seed x fight), unmoved by prior "
			+ "_combat_ops draws (%d/%d drifted)" % [unstable, SWEEP])
	_check(deck_seen.size() == deck_want.size(),
		"D: all %d authored lineups reached through the real helper (saw %d)"
			% [deck_want.size(), deck_seen.size()])
	for sig in deck_seen:
		if not deck_want.has(sig):
			_check(false, "D: helper produced an unauthored lineup")
			break
	_check(reinf_seen.size() == reinf_want.size(),
		"D: all %d authored reinforcements reached through the real helper (saw %d)"
			% [reinf_want.size(), reinf_seen.size()])
	# The two salts must not lock the picks together, or one authored dimension
	# of variety silently collapses into the other.
	_check(pairs.size() > maxi(deck_want.size(), reinf_want.size()),
		"D: deck and reinforcement rolls are independent (%d distinct pairs, "
			% pairs.size() + "%d x %d possible)" % [deck_want.size(), reinf_want.size()])
	print("[encounter-seed] fixture %s: lineups=%d reinforcements=%d pairs=%d"
		% [_fixture, deck_seen.size(), reinf_seen.size(), pairs.size()])
	c.free()


# ── E. the live path ──────────────────────────────────────────────────────
func _live_path() -> void:
	print("\n[encounter-seed] ===== E. the fight combat actually sets up =====")
	if _fixture == "":
		_check(false, "E: no fixture encounter")
		return
	var a := await _boot(1234567)
	var b := await _boot(1234567)
	_check(not a.is_empty() and not b.is_empty(), "E: booted the real combat scene twice")
	if a.is_empty() or b.is_empty():
		return
	_check(a.deck == b.deck,
		"E: same run seed sets up the same enemy deck\n           A %s\n           B %s"
			% [a.deck, b.deck])
	_check(a.reinf == b.reinf,
		"E: same run seed sets up the same reinforcement (%s vs %s)"
			% [a.reinf, b.reinf])
	# And the live setup agrees with what the helper predicts — i.e. the fix
	# actually reached _setup_fight_state rather than living in a side path.
	_check(a.reinf == a.predicted_reinf,
		"E: _setup_fight_state's reinforcement matches the seeded prediction "
			+ "(%s vs %s)" % [a.reinf, a.predicted_reinf])
	_check(a.deck_is_subset,
		"E: the dealt lineup is the seeded prediction's lineup")


func _boot(seed_v: int) -> Dictionary:
	RunState.start_new_run("stalwart", 0, seed_v)
	RunState.current_encounter_id = _fixture
	RunState.current_node_type = "combat"
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame
	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Gate on round + hand, never on phase — PLAYER_TURN is enum 0, which is also
	# the uninitialised default (the readiness trap _probe_muster_delay documents).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	if not is_instance_valid(combat) or combat.round_number < 1:
		return {}
	# Remaining deck only — the opening muster has already dealt some bodies out,
	# and on-enter summons can add creatures that never came from the deck.
	var remaining: Array[String] = []
	for cd in combat._enemy_deck:
		remaining.append(String((cd as Dictionary).get("name", "?")))
	var reinf: String = _body(combat._reinforcement)
	var predicted_deck: Array = EncounterDB.build_enemy_deck(_fixture,
		RunState.get_act(), combat._encounter_roll_stream(combat.ENC_ROLL_SALT_DECK))
	var predicted_reinf: String = _body(EncounterDB.get_reinforcement(_fixture,
		RunState.get_act(),
		combat._encounter_roll_stream(combat.ENC_ROLL_SALT_REINFORCEMENT)))
	var bag := {}
	for cd in predicted_deck:
		var n := String((cd as Dictionary).get("name", "?"))
		bag[n] = int(bag.get(n, 0)) + 1
	var subset := true
	for n in remaining:
		if int(bag.get(n, 0)) <= 0:
			subset = false
			break
		bag[n] = int(bag[n]) - 1
	var out := {
		"deck": ",".join(remaining), "reinf": reinf,
		"predicted_reinf": predicted_reinf, "deck_is_subset": subset,
	}
	remove_child(combat)
	combat.queue_free()
	for _i in range(6):
		await get_tree().process_frame
	return out
