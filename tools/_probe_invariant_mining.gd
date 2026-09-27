extends SceneTree
## _probe_invariant_mining.gd — PASS 22 of docs/BUG_SWEEP_METHOD_20260829.md (C22).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_invariant_mining.gd
##
## SPECIFICATION MINING — let the game tell me its rules, instead of the reverse.
##
## Every assertion in this suite is one I WROTE, which means the suite can only ever
## check properties someone already thought of. `_probe_invariants` (C14) is the
## clearest case: it watches five hand-picked properties on every frame, and it is
## blind to the hundreds nobody enumerated. That is the ceiling of hand-authored
## testing, and Daikon-style dynamic invariant detection is the published answer to
## it: run the program, record values, and MINE the properties that always held.
##
## The method here is deliberately two-phase, because a mined invariant on its own
## is worthless — trivially, everything observed once is "always" true:
##
##   PHASE 1 (LEARN): drive matches under one set of seeds/configs and, at each
##     sampled beat, record every numeric field of interest. Mine candidate
##     invariants: bounds (x >= k, x <= k), constants (x == k), and RELATIONS
##     between fields (x <= y), which are the interesting ones.
##   PHASE 2 (TEST): drive DIFFERENT seeds and configs, and check every mined
##     candidate. A candidate that breaks is one of exactly two things, and both
##     are worth a human's attention:
##       · an OVERFIT — phase 1 was too narrow, and the "rule" was a coincidence.
##       · a REAL RULE that phase 2 violates — i.e. a bug.
##
## The output is therefore not pass/fail on the mined set. It is (a) the SURVIVING
## invariants, which are a machine-written specification of the combat state worth
## reading on their own, and (b) the BROKEN ones, which need adjudicating. The one
## hard failure is a vacuity check: if phase 1 mines nothing, the pass is broken.

const LEARN_SEEDS := [11, 22, 33, 44]
const TEST_SEEDS := [55, 66, 77, 88]
const TURNS := 6

var SS: Node
var NM: Node
var US: Node
var combat: Node

var _started := false
var _done := false
var _fails := 0
## field -> {min, max, all_equal_to}
var _learned := {}
## "a<=b" pairs that always held
var _relations := {}
var _samples := 0


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


## The observable numeric state of a match at one instant. Everything here is a
## quantity a rule could plausibly constrain.
## Poll until the hand has finished ARRIVING, not just until the turn is ours.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. CombatNet routes its round starts through that
## same function, so a skirmish driver inherits the stagger exactly as a solo
## one does. See CLAUDE.md's settle-until-stable note.
##
## This probe MINES bounds, which makes it the worst possible place to read a
## half-dealt hand: an unsettled `hand_size` is not a wrong number in one row,
## it becomes a learned invariant that every later phase is checked against.
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


func _observe() -> Dictionary:
	if not is_instance_valid(combat):
		return {}
	var bodies_mine := 0
	var bodies_foe := 0
	var atk_total := 0
	var hp_total := 0
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					continue
				if is_enemy:
					bodies_foe += 1
				else:
					bodies_mine += 1
				atk_total += int(c.effective_atk())
				hp_total += int(c.current_hp)
	return {
		"player_hp": int(combat.player_hp),
		"enemy_hp": int(combat.enemy_hp),
		"player_mana": int(combat.player_mana),
		"player_max_mana": int(combat.player_max_mana),
		"hand_size": combat._hand.size(),
		"round_number": int(combat.round_number),
		"bodies_mine": bodies_mine,
		"bodies_foe": bodies_foe,
		"board_atk_total": atk_total,
		"board_hp_total": hp_total,
		"entities": NM.entities.size(),
	}


func _learn(obs: Dictionary) -> void:
	if obs.is_empty():
		return
	_samples += 1
	for k in obs:
		var v: int = int(obs[k])
		if not _learned.has(k):
			_learned[k] = {"min": v, "max": v}
		else:
			_learned[k]["min"] = mini(int(_learned[k]["min"]), v)
			_learned[k]["max"] = maxi(int(_learned[k]["max"]), v)
	# Pairwise <= relations. These are the mined properties with actual content —
	# "hand_size <= player_max_mana" would be a coincidence worth knowing about,
	# "bodies_mine <= 8" is the board shape stated back to you.
	var keys: Array = obs.keys()
	for i in keys.size():
		for j in keys.size():
			if i == j:
				continue
			var key := "%s <= %s" % [keys[i], keys[j]]
			var holds: bool = int(obs[keys[i]]) <= int(obs[keys[j]])
			if _samples == 1:
				_relations[key] = holds
			elif _relations.get(key, false) and not holds:
				_relations[key] = false


func _test(obs: Dictionary, broken: Dictionary) -> void:
	if obs.is_empty():
		return
	for k in obs:
		if not _learned.has(k):
			continue
		var v: int = int(obs[k])
		if v < int(_learned[k]["min"]):
			broken["%s >= %d" % [k, int(_learned[k]["min"])]] = \
				"saw %d" % v
		if v > int(_learned[k]["max"]):
			broken["%s <= %d" % [k, int(_learned[k]["max"])]] = \
				"saw %d" % v
	for key in _relations:
		if not bool(_relations[key]):
			continue
		var parts: PackedStringArray = String(key).split(" <= ")
		if not obs.has(parts[0]) or not obs.has(parts[1]):
			continue
		if int(obs[parts[0]]) > int(obs[parts[1]]):
			broken[key] = "saw %d vs %d" % [int(obs[parts[0]]), int(obs[parts[1]])]


func _boot(seed_val: int, style: int) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin",
			"strike", "brute", "goblin", "brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
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


func _drive(seed_val: int, style: int, sink: Callable) -> void:
	if not await _boot(seed_val, style):
		return
	var turns := 0
	var stalls := 0
	while turns < TURNS and is_instance_valid(combat) and not combat._net_match_over:
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
			if stalls > 300:
				break
			await create_timer(0.05).timeout
			continue
		stalls = 0
		turns += 1
		# BEFORE the observation, not after: `hand_size` is one of the fields
		# mined here, so reading it mid-deal teaches the miner a lower bound the
		# game never has (1 instead of the round-1 five).
		await _settle_hand()
		if not is_instance_valid(combat):
			break
		sink.call(_observe())
		for _p in 6:
			if not is_instance_valid(combat):
				break
			var played := false
			for card in combat._hand.duplicate():
				if card == null or not is_instance_valid(card) or not card.is_creature():
					continue
				if combat._effective_cost(card) > combat.player_mana:
					continue
				var slot := _first_empty_slot()
				if slot == null:
					break
				card.global_position = slot.get_global_rect().get_center() \
					- card.size * 0.5
				combat._on_card_played(card)
				await create_timer(0.05).timeout
				played = true
				break
			if not played:
				break
		sink.call(_observe())
		if is_instance_valid(combat):
			combat._net_on_done_placing()
			await create_timer(0.3).timeout
		sink.call(_observe())
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.25).timeout


func _run() -> void:
	print("[mine] PASS 22 — mine the rules, then try to break them\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[mine] FATAL: autoloads missing"); _done = true; quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false

	print("[mine] PHASE 1 — learning from %d matches" % LEARN_SEEDS.size())
	var learn_sink := func(obs): _learn(obs)
	for i in LEARN_SEEDS.size():
		await _drive(int(LEARN_SEEDS[i]), i % 2, learn_sink)
	print("[mine] %d samples; %d fields, %d surviving relations" % [
		_samples, _learned.size(), _surviving_relations().size()])
	# VACUITY: a phase that mined nothing would make phase 2 pass unconditionally.
	_check(_samples > 0 and _learned.size() > 0,
		"phase 1 observed real state to mine from")
	_check(_surviving_relations().size() > 0,
		"phase 1 mined at least one relation between fields")

	print("\n[mine] the mined specification (bounds):")
	var names: Array = _learned.keys()
	names.sort()
	for k in names:
		print("        %-18s in [%d .. %d]" % [k, int(_learned[k]["min"]),
			int(_learned[k]["max"])])
	print("[mine] mined relations that always held:")
	for r in _surviving_relations():
		print("        %s" % r)

	print("\n[mine] PHASE 2 — testing them against %d unseen matches"
		% TEST_SEEDS.size())
	var broken := {}
	var test_sink := func(obs): _test(obs, broken)
	for i in TEST_SEEDS.size():
		await _drive(int(TEST_SEEDS[i]), (i + 1) % 2, test_sink)

	# SEPARATE THE TWO KINDS OF BREAK, because they mean different things and
	# lumping them together is what makes a mined-invariant report unreadable.
	# A RANGE that widens is the expected cost of learning from a finite sample —
	# phase 2 simply saw a bigger board or a lower HP. A RELATION between two
	# fields breaking is the interesting one: it was a structural claim, and it
	# turned out to be a coincidence of the learn set (or a real rule violated).
	var widened: Array = []
	var relations_broken: Array = []
	for b in broken:
		if String(b).find(" <= ") >= 0 and String(b).split(" <= ")[1].is_valid_int():
			widened.append("%s (%s)" % [b, broken[b]])
		elif String(b).find(" >= ") >= 0 and String(b).split(" >= ")[1].is_valid_int():
			widened.append("%s (%s)" % [b, broken[b]])
		else:
			relations_broken.append("%s (%s)" % [b, broken[b]])
	print("        %d range(s) widened, %d relation(s) broken"
		% [widened.size(), relations_broken.size()])
	for w in widened:
		print("           range   %s" % w)
	for r in relations_broken:
		print("           RELATION %s" % r)

	# THE DURABLE ARTIFACT. An invariant that survived BOTH an unseen seed set and
	# an unseen battle style is a machine-written specification of this game's
	# combat state — the properties nobody thought to assert but that hold anyway.
	# These are the ones worth promoting into a hand-written gate.
	var confirmed: Array = []
	for r in _surviving_relations():
		if not broken.has(r):
			confirmed.append(r)
	print("\n[mine] CONFIRMED SPECIFICATION — %d relation(s) held across both the"
		% confirmed.size())
	print("[mine] learn set and %d unseen matches. Promote any of these that state a"
		% TEST_SEEDS.size())
	print("[mine] real rule into an explicit assertion:")
	# RANK BY INFORMATION, not by count. Most surviving relations are true only
	# because one side is a hero HP in the twenties and the other is a body count
	# under ten — "hand_size <= player_hp" is arithmetic, not a rule. A relation is
	# INFORMATIVE when the two fields' observed ranges actually overlap, because
	# then it could plausibly have gone the other way and did not.
	var informative: Array = []
	for c in confirmed:
		var parts: PackedStringArray = String(c).split(" <= ")
		if not _learned.has(parts[0]) or not _learned.has(parts[1]):
			continue
		var lo_a: int = int(_learned[parts[0]]["min"])
		var hi_a: int = int(_learned[parts[0]]["max"])
		var lo_b: int = int(_learned[parts[1]]["min"])
		var hi_b: int = int(_learned[parts[1]]["max"])
		# Overlapping ranges: the left could have exceeded the right and never did.
		if hi_a >= lo_b and hi_b >= lo_a:
			informative.append("%s   [%d..%d] vs [%d..%d]" % [c, lo_a, hi_a, lo_b, hi_b])
		else:
			print("        (trivial) %s" % c)
	print("\n[mine] INFORMATIVE — the two fields' ranges overlap, so these could have")
	print("[mine] been violated and were not. This is the part worth reading:")
	for i in informative:
		print("        %s" % i)
	_check(confirmed.size() > 0,
		"at least one mined relation survived unseen input (else the mining is noise)")

	print("\n[mine] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)


func _surviving_relations() -> Array:
	var out: Array = []
	for k in _relations:
		if bool(_relations[k]):
			out.append(k)
	out.sort()
	return out
