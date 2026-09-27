extends SceneTree
## _probe_fuzz_wire.gd — PASS 13 of docs/BUG_SWEEP_METHOD_20260829.md (class C13).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_fuzz_wire.gd
##
## FUZZING THE TRUST BOUNDARY.
##
## Every previous pass fed the game WELL-FORMED input — a legal play, a legal
## snapshot, a legal turn. But the one place this game accepts data it did not
## create is the wire, and a peer is not obliged to be friendly. `NetProtocol`
## exists precisely to be the wall there, and it has never once been hit with
## anything except messages this codebase itself produced.
##
## So: generate hostile input on purpose and require two things that are easy to
## state and hard to satisfy —
##
##   1. THE VALIDATOR NEVER CRASHES. Whatever arrives, `validate_envelope` returns
##      a reason string. An exception here is a remote crash: a peer could kill the
##      other client by sending one bad packet.
##   2. THE VALIDATOR NEVER LIES. Anything it ACCEPTS must genuinely satisfy the
##      envelope contract, because everything downstream trusts that verdict.
##
## Then the same treatment for the layer behind the wall: garbage that the wall
## lets through is handed to the host's real intent handler, which must refuse it
## without throwing. That is the path a modified client actually takes.
##
## Shapes generated: wrong types in every field, absent fields, deep nesting past
## MAX_DEPTH, arrays past MAX_ARRAY_ITEMS, strings past MAX_STRING_BYTES, huge and
## negative and non-finite numbers, unicode, and structurally VALID envelopes whose
## payload is nonsense — the last being the interesting case, since those get past
## the shape check and reach gameplay code.

const ITERATIONS := 400

var NP
var SS: Node
var NM: Node
var combat: Node

var _rng := RandomNumberGenerator.new()
var _started := false
var _done := false
var _fails := 0
var _accepted := 0
var _rejected := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## A random Variant, biased toward the shapes that break parsers.
func _junk(depth: int = 0):
	match _rng.randi_range(0, 11 if depth < 4 else 7):
		0: return null
		1: return _rng.randi_range(-999999999, 999999999)
		2: return _rng.randf_range(-1e30, 1e30)
		3: return _rng.randi() % 2 == 0
		4: return ""
		5: return "A".repeat(_rng.randi_range(1, 40))
		6: return "\u0000\uFFFD\u202E ünïcödé \n\t\\\" %s %d {}[]"
		7: return "X".repeat(_rng.randi_range(9000, 12000))   # past MAX_STRING_BYTES
		8:
			var a: Array = []
			for _i in _rng.randi_range(0, 8):
				a.append(_junk(depth + 1))
			return a
		9:
			var big: Array = []
			for _i in 300:                                     # past MAX_ARRAY_ITEMS
				big.append(_rng.randi())
			return big
		10:
			var d := {}
			for _i in _rng.randi_range(0, 6):
				d[str(_junk(depth + 1))] = _junk(depth + 1)
			return d
		_:
			# Deliberately deep — past MAX_DEPTH.
			var nest = {}
			var cur = nest
			for _i in 14:
				var inner = {}
				cur["n"] = inner
				cur = inner
			return nest


## An envelope that is structurally plausible but semantically hostile.
## `force_kind` biases phase C, which is testing the INTENT handler specifically:
## unbiased generation put only 1 envelope in 8 on that path, so a 900-round run
## delivered six. A fuzz whose sample is six has not fuzzed anything.
func _semi_valid_envelope(session: String, force_kind: String = "") -> Dictionary:
	var kinds: Array = NP.ALLOWED_KINDS
	var kind := force_kind if force_kind != "" else String(kinds[_rng.randi() % kinds.size()])
	var payload := {}
	match kind:
		NP.KIND_INTENT:
			payload = {"intent": {"t": _junk_intent_type(), "lane": _junk(), "row": _junk(),
				"uid": _junk(), "id": _junk(), "target": _junk(), "discards": _junk()}}
		NP.KIND_EVENT:
			payload = {"event": {"t": _junk_intent_type(), "creatures": _junk(),
				"strikes": _junk(), "winner": _junk()}}
		NP.KIND_DRAFT:
			payload = {"event": {"t": "finished", "cards": _junk(), "relics": _junk()}}
		NP.KIND_READY:
			payload = {"value": _junk()}
		NP.KIND_HERO:
			payload = {"hero": _junk()}
		NP.KIND_MATCH_START:
			payload = {"seed": _junk(), "mode": _junk(), "bo": _junk(),
				"style": _junk(), "h0": _junk(), "h1": _junk()}
		NP.KIND_MATCH_CONFIG:
			payload = {"mode": _junk(), "bo": _junk(), "style": _junk()}
		NP.KIND_LAUNCH:
			payload = {} if _rng.randi() % 2 == 0 else {"x": _junk()}
	return {"pv": NP.VERSION, "sid": session, "seq": _rng.randi_range(1, 1 << 30),
		"k": kind, "p": payload}


func _junk_intent_type() -> String:
	var real: Array = [NM.IN_PLAY_CREATURE, NM.IN_PLAY_SPELL, NM.IN_END_ACTIONS,
		NM.IN_USE_POTION, NM.IN_REPOSITION, NM.IN_ORDERS, NM.IN_SNIPER_AIM,
		NM.IN_ORDER_GHOST, NM.IN_SORCERY_PASS, NM.IN_CHOICE, NM.IN_REMATCH]
	if _rng.randi() % 4 == 0:
		return "\u202Enot_a_real_intent"
	return String(real[_rng.randi() % real.size()])


## Re-derive the envelope contract independently, so "accepted" can be audited
## without asking the validator to mark its own homework.
func _truly_valid(w) -> bool:
	if typeof(w) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = w
	if int(d.get("pv", -1)) != NP.VERSION:
		return false
	if typeof(d.get("sid", null)) != TYPE_STRING:
		return false
	var sid := String(d["sid"])
	if sid.is_empty() or sid.length() > 64:
		return false
	if typeof(d.get("seq", null)) != TYPE_INT or int(d["seq"]) <= 0:
		return false
	if typeof(d.get("k", null)) != TYPE_STRING or String(d["k"]) not in NP.ALLOWED_KINDS:
		return false
	if typeof(d.get("p", null)) != TYPE_DICTIONARY:
		return false
	return true


func _run() -> void:
	print("[fuzz] PASS 13 — hostile input at the wire\n")
	NP = load("res://scripts/net/NetProtocol.gd")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if NP == null or SS == null or NM == null:
		print("[fuzz] FATAL: missing deps"); _done = true; quit(1); return
	_rng.seed = 0xF0DDED

	# ── A. pure garbage ───────────────────────────────────────────────────
	print("[fuzz] --- A: %d rounds of pure garbage ---" % ITERATIONS)
	var lied := 0
	for i in ITERATIONS:
		var w = _junk()
		var reason := String(NP.validate_envelope(w, ""))
		if reason == "":
			_accepted += 1
			if not _truly_valid(w):
				lied += 1
				if lied <= 3:
					print("          ACCEPTED NON-ENVELOPE: %s" % str(w).substr(0, 120))
		else:
			_rejected += 1
	print("        %d rejected, %d accepted" % [_rejected, _accepted])
	_check(lied == 0, "the validator never accepted something that is not an envelope")

	# ── B. structurally valid, semantically hostile ───────────────────────
	print("\n[fuzz] --- B: %d well-formed envelopes with hostile payloads ---" % ITERATIONS)
	var sess := "f".repeat(32)
	var b_lied := 0
	var b_accepted := 0
	for i in ITERATIONS:
		var w := _semi_valid_envelope(sess)
		var reason := String(NP.validate_envelope(w, sess))
		if reason == "":
			b_accepted += 1
			if not _truly_valid(w):
				b_lied += 1
	print("        %d of %d passed the wall" % [b_accepted, ITERATIONS])
	_check(b_lied == 0, "every accepted envelope really satisfies the contract")
	_check(b_accepted > 0, "the wall is not simply rejecting everything (would be vacuous)")

	# ── C. what gets through, handed to the real host handler ─────────────
	# The wall's job is shape, not meaning — so hostile-but-well-formed intents
	# DO reach gameplay code. This is the path a modified client takes.
	print("\n[fuzz] --- C: accepted intents delivered to the live host ---")
	if not await _boot():
		_check(false, "C booted a host")
	else:
		var delivered := 0
		var reboots := 0
		for i in 900:
			# SOME INTENTS LEGITIMATELY END THE MATCH. `end_actions` runs a clash and
			# `rematch` relaunches, so the scene disappears under the fuzz — the first
			# version of this loop simply broke there and reported a PASS on a sample
			# of ONE. Re-boot instead, so the run keeps feeding the handler.
			if not is_instance_valid(combat):
				if reboots >= 8:
					break
				reboots += 1
				if not await _boot():
					break
			var w := _semi_valid_envelope(sess, NP.KIND_INTENT)
			if String(NP.validate_envelope(w, sess)) != "":
				continue
			var payload: Dictionary = w["p"]
			if not (payload.get("intent", null) is Dictionary):
				continue
			combat._net_active_index = 1          # pretend it is the client's turn
			await combat.net._net_process_intent(payload["intent"])
			delivered += 1
			# A THROWN COERCION ABORTS THE CALLER TOO. When `int({})` raised inside
			# `_net_apply_remote_creature`, the abort propagated up through this
			# loop and it stopped after ONE intent while still reporting PASS. So
			# require the run to reach a real sample size — a fuzz pass that
			# delivered one message has tested nothing.
			if delivered % 60 == 0:
				await create_timer(0.05).timeout
		print("        %d hostile intents processed (%d host re-boots)" % [delivered, reboots])
		_check(delivered >= 40,
			"the fuzz reached a real sample size (%d intents delivered)" % delivered)
		_check(is_instance_valid(combat), "the host survived every hostile intent")
		_check(combat.player_hp <= SS.START_HP and combat.enemy_hp <= SS.START_HP,
			"no hostile intent inflated a hero above its maximum (%d/%d)" % [
				combat.player_hp, combat.enemy_hp])
		if is_instance_valid(combat):
			combat.queue_free()
		await create_timer(0.4).timeout

	print("\n[fuzz] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)


func _boot() -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 99177
	SS.vs_bot = true
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.battle_style = NM.STYLE_ALTERNATING
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.6).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	await create_timer(1.2).timeout
	return is_instance_valid(combat)
