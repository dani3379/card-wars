extends SceneTree
## _probe_bot_spells.gd — CAN THE PRACTICE BOT CAST A SPELL AT ALL?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_bot_spells.gd
##
## `SkirmishBot.build_deck` puts up to five spells in the bot's twenty, and
## `decide_turn` happily scores and returns IN_PLAY_SPELL intents for them
## (`_best_spell` handles damage / damage_face / AoE / buffs / heal). `_bot_take_turn`
## then charges the bot for the card — `_bot_consume_card` removes it from hand and
## adds its cost to `spent` — BEFORE handing the intent to `_bot_apply_intent`.
##
## But the spell arm lands in `_net_apply_remote_spell`, which is written for a REAL
## client and dereferences `_remote_state`. In a practice match `_remote_state` is
## null by construction (`_net_init_remote_authority` returns false the moment
## `SkirmishState.vs_bot` is set), so the function bails at its authority guard and
## the cast is dropped. The creature arm right beside it guards every authority call
## with `if not SkirmishState.vs_bot:`; the spell arm never got the same treatment.
##
## Net effect: a quarter of the bot's deck is dead weight AND it pays Command for
## cards that do nothing. Silent, too — the rejection is reported through
## `_net_reject_remote`, which is itself a no-op in a practice match.
##
## This probe hands the bot a spell it should obviously cast and checks the board.

var SS: Node
var NM: Node
var US: Node
var combat: Node

var _started := false
var _done := false
var _fails := 0


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


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _boot() -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin",
			"strike", "brute", "goblin", "brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 8080
	SS.vs_bot = true
	SS.best_of = 1
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
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 12:
		await create_timer(0.25).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	return is_instance_valid(combat)


func _run() -> void:
	print("[bot-spells] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[bot-spells] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true

	if not await _boot():
		_check(false, "booted"); _finish(1); return
	_check(combat._is_net() and combat._is_host() and SS.vs_bot,
		"booted as a practice drill (net host, vs_bot)")
	_check(combat.net._remote_state == null,
		"a practice match has no remote authority object (this is the trap)")

	# A host-side body for the bot's spell to kill, and the bot's turn open.
	var target_data: Dictionary = SS.skirmish_card_data("brute").duplicate(true)
	target_data["hp"] = 2
	target_data["atk"] = 1
	combat.net._net_spawn_creature(target_data, 4242, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.2).timeout
	var victim = NM.get_entity(4242)
	_check(victim != null and is_instance_valid(victim),
		"a host-side target is standing")
	combat._net_active_index = 1     # the bot's turn — the arm under test
	combat.phase = combat.Phase.PLAYER_TURN

	var hp_before: int = int(victim.current_hp) if victim != null else -1
	var face_before: int = int(combat.player_hp)
	# "strike" is a plain damage spell and is net-legal; this is exactly the shape
	# SkirmishBot._best_spell emits for stype == "damage".
	await combat.net._net_apply_remote_spell({
		"t": NM.IN_PLAY_SPELL, "id": "strike", "uid": 777, "target": 4242,
	})
	await create_timer(0.4).timeout
	var hp_after: int = int(victim.current_hp) if is_instance_valid(victim) else 0
	print("[bot-spells] target HP %d -> %d ; host face %d -> %d" % [
		hp_before, hp_after, face_before, int(combat.player_hp)])
	_check(hp_after < hp_before,
		"the bot's damage spell actually resolved on the board (%d -> %d)" % [
			hp_before, hp_after])

	# And an untargeted one, so the face arm is covered too.
	var face_mid: int = int(combat.player_hp)
	await combat.net._net_apply_remote_spell({
		"t": NM.IN_PLAY_SPELL, "id": "quick_shot", "uid": 778, "target": -1,
	})
	await create_timer(0.4).timeout
	_check(int(combat.player_hp) < face_mid,
		"an untargeted bot spell reached the host's face (%d -> %d)" % [
			face_mid, int(combat.player_hp)])

	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.3).timeout
	print("\n[bot-spells] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_finish(1 if _fails > 0 else 0)
