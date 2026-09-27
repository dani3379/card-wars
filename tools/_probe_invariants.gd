extends SceneTree
## _probe_invariants.gd — PASS 14 of docs/BUG_SWEEP_METHOD_20260829.md (class C14).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_invariants.gd
##
## CONTINUOUS INVARIANTS — checking the game WHILE it moves.
##
## Every pass so far inspects a QUIESCENT state: the board before a clash, the run
## after a verdict, a screen that has finished laying out. That is a real blind
## spot, because a great many defects exist only in transit — a slot briefly holding
## two bodies, a registry pointing at something already freed, a hand momentarily
## over its cap — and the game tidies up before any end-state assertion looks.
## Those are precisely the states a player can click into.
##
## So this asserts a set of ALWAYS-TRUE properties on EVERY FRAME of a real match:
## mid-clash, mid-animation, mid-reveal, mid-teardown. It is the same idea as a
## debug assertion, run as a gate over a driven game.
##
## THE DESIGNED TRANSIENTS MUST BE ENCODED, or this is a noise generator. Two are
## load-bearing in this codebase and are exempted explicitly below:
##   * `Card2D.defer_deaths` deliberately holds dead-but-standing corpses on the
##     board so mutual kills trade — so "no body with hp <= 0" is FALSE by design
##     while it is set.
##   * Sealed-orders stand-ins occupy a row array without being registered
##     entities, because the order is a private commitment until the reveal.

const MAX_HAND := 10

var SS: Node
var NM: Node
var US: Node
var combat: Node
## LOADED AT RUNTIME, NEVER NAMED AT PARSE TIME. Writing `Card2D.defer_deaths`
## directly in a `--script` probe drags Card2D.gd into the compile that happens
## BEFORE the autoloads register; its own autoload references then fail, the script
## does not compile, and `card_2d.tscn` instantiates as a bare PanelContainer. The
## match still runs — badly — and this audit reported ALL PASS over a build where
## no card had its script. The tell was two error classes the soaks never produce:
## "Nonexistent function 'reset_clash_pitch' in base 'GDScript'" and "Invalid
## assignment of property 'card_id' ... on a base object of type 'PanelContainer'".
## Same family as the `preload`-the-autoload trap already recorded in CLAUDE.md.
var CardCls

var _started := false
var _done := false
var _fails := 0
var _frames := 0
var _violations: Dictionary = {}     # invariant -> {count, first_detail}


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _violate(name: String, detail: String) -> void:
	if not _violations.has(name):
		_violations[name] = {"count": 0, "first": detail}
	_violations[name]["count"] += 1


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	if is_instance_valid(combat) and combat.is_inside_tree():
		_frames += 1
		_audit()
	return _done


## Every property that must hold at ALL times, checked once per frame.
func _audit() -> void:
	# 1 — a slot holds at most one body, and the body agrees about where it is.
	var seen_nodes: Dictionary = {}
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c == null:
					continue
				if not is_instance_valid(c):
					_violate("freed node still in a board slot",
						"side=%s row=%d lane=%d" % [str(is_enemy), row, lane])
					continue
				if seen_nodes.has(c):
					_violate("one body occupies two slots",
						"%s at %s and %s" % [str(c.card_id), seen_nodes[c],
							"%s/%d/%d" % [str(is_enemy), row, lane]])
				seen_nodes[c] = "%s/%d/%d" % [str(is_enemy), row, lane]
				if int(c.current_lane) != lane or int(c.current_row) != row:
					_violate("a body disagrees with the slot holding it",
						"%s thinks %d,%d but sits at %d,%d" % [
							str(c.card_id), int(c.current_lane), int(c.current_row),
							lane, row])
				# DEFERRED DEATHS ARE BY DESIGN — corpses are held so mutual kills
				# trade. Only flag a dead body standing OUTSIDE that window.
				if int(c.current_hp) <= 0 and not bool(CardCls.defer_deaths):
					_violate("a body with no HP is still on the board",
						"%s hp=%d" % [str(c.card_id), int(c.current_hp)])

	# 2 — the entity registry never points at something freed, and never maps two
	#     ids onto one node.
	var by_node: Dictionary = {}
	for eid in NM.entities.keys():
		var n = NM.entities[eid]
		if n == null or not is_instance_valid(n):
			_violate("the entity registry holds a freed node", "eid=%s" % str(eid))
			continue
		if by_node.has(n):
			_violate("one node registered under two entity ids",
				"eids %s and %s" % [str(by_node[n]), str(eid)])
		by_node[n] = eid

	# 3 — resources stay inside their declared bounds.
	if int(combat.player_mana) < 0:
		_violate("Command went negative", "mana=%d" % int(combat.player_mana))
	if combat._hand.size() > MAX_HAND:
		_violate("the hand exceeded its cap",
			"%d > %d" % [combat._hand.size(), MAX_HAND])
	if int(combat.player_hp) > int(combat._ctx_hero_max_hp()):
		_violate("hero HP above maximum",
			"%d > %d" % [int(combat.player_hp), int(combat._ctx_hero_max_hp())])

	# 4 — the hand never holds the same card twice.
	var uids: Dictionary = {}
	for card in combat._hand:
		if card == null or not is_instance_valid(card):
			_violate("a freed card is still in the hand", "—")
			continue
		var u := int(card.deck_uid)
		if u >= 0:
			if uids.has(u):
				_violate("the same deck uid is in hand twice", "uid=%d" % u)
			uids[u] = true


func _boot(style: int) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin",
			"strike", "brute", "goblin", "brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 271_828
	SS.vs_bot = true
	SS.best_of = 1
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
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
	for _i in 40:
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


func _play_and_commit() -> void:
	for _pass in 8:
		if not is_instance_valid(combat):
			return
		var played := false
		for card in combat._hand.duplicate():
			if card == null or not is_instance_valid(card) or not card.is_creature():
				continue
			if combat._effective_cost(card) > combat.player_mana:
				continue
			var slot := _first_empty_slot()
			if slot == null:
				break
			card.global_position = slot.get_global_rect().get_center() - card.size * 0.5
			combat._on_card_played(card)
			await create_timer(0.05).timeout
			played = true
			break
		if not played:
			break
	if is_instance_valid(combat):
		combat._net_on_done_placing()
		await create_timer(0.35).timeout


func _run() -> void:
	print("[invariants] PASS 14 — properties that must hold on every frame\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[invariants] FATAL: autoloads missing"); _done = true; quit(1); return
	# Runtime load, AFTER the autoloads exist — see the note on CardCls.
	CardCls = load("res://scripts/Card2D.gd")
	if CardCls == null:
		print("[invariants] FATAL: Card2D did not compile"); _done = true; quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false

	for spec in [[NM.STYLE_ALTERNATING, "ALTERNATING"], [NM.STYLE_SEALED, "SEALED"]]:
		var style: int = int(spec[0])
		print("[invariants] --- driving a %s match under audit ---" % String(spec[1]))
		if not await _boot(style):
			_check(false, "%s booted" % String(spec[1]))
			continue
		var turns := 0
		var stalls := 0
		while turns < 40 and is_instance_valid(combat) and not combat._net_match_over:
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
			turns += 1
			await _settle_hand()
			await _play_and_commit()
		print("        %s: %d turns, %d frames audited" % [
			String(spec[1]), turns, _frames])
		if is_instance_valid(combat):
			combat.queue_free()
		await create_timer(0.5).timeout

	print("\n[invariants] %d frames audited across two matches" % _frames)
	_check(_frames > 500, "the audit actually ran over a real match (%d frames)" % _frames)
	if _violations.is_empty():
		print("  PASS  every invariant held on every frame")
	else:
		for name in _violations:
			_fails += 1
			print("  FAIL  %s — %d frame(s)" % [name, int(_violations[name]["count"])])
			print("          first: %s" % String(_violations[name]["first"]))

	print("\n[invariants] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
