extends SceneTree
## Net clash probe — verifies the CURRENT Online Skirmish combat model
## (ALTERNATING one-directional strikes + Cross-Blitz mutual trade,
## 2026-07-11 second-player opening strike):
##   · Only the OPENER's first turn is place-only (empty opposing board = free
##     face hits). The second player's first turn faces a standing line — it is
##     de facto turn 2 — so its commit STRIKES like any other turn.
##   · Every strike is one-directional, and every struck LIVE defender counters
##     its attacker for its ATK in the same beat (_net_mutual_retaliation) — so
##     evenly-matched creatures trade and BOTH fall, matching solo's simultaneity.
##
## Boots the REAL combat.tscn as NET_HOST (no sockets), forces host-first, and drives:
##   1. host (opener) places a 3/2 in lane 0, finishes → turn passes, round
##      stays 1, no clash, no damage.
##   2. client places a 3/2 in the SAME lane, finishes → its opening STRIKE
##      fires: the defender counters, BOTH 3/2s die, no face damage, and the
##      round advances to 2 for the opener.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_clash.gd

var CDB: Node
var SS: Node
var NM: Node
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


func _c32(tag: String) -> Dictionary:
	return {
		"id": "probe32_%s" % tag, "name": "Probe32%s" % tag,
		"type": "creature", "cost": 1, "atk": 3, "hp": 2,
		"rarity": "common", "keywords": [], "desc": "",
	}


func _run() -> void:
	print("[net-clash] start")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	var US = root.get_node_or_null("UserSettings")
	if CDB == null or SS == null or NM == null:
		print("[net-clash] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true

	# NET_HOST, no real peer (mirrors _probe_skirmish_combat._setup_state).
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	combat._net_first_player_override = 0   # host opens round 1 (deterministic)
	root.add_child(combat)

	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 10:
		await create_timer(0.3).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		print("[net-clash] FATAL: combat freed during boot"); _finish(1); return

	_check(int(combat._net_active_index) == 0, "round 1 opens for the host (active=0)")
	_check(int(combat._net_turn_round) == 1, "combat opens on round 1")

	# ── 1. Host places a 3/2 in lane 0 front, then finishes placing. ──
	print("\n[net-clash] === host places + finishes ===")
	var hp_host_hero: int = int(combat.player_hp)
	var hp_client_hero: int = int(combat.enemy_hp)
	combat._net_spawn_creature(_c32("host"), 5001, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.1).timeout
	await combat._net_finish_placement(0)
	await create_timer(0.2).timeout
	_check(int(combat._net_active_index) == 1, "placement passed to the client (active=1)")
	_check(int(combat._net_turn_round) == 1, "still round 1 — no clash after only ONE side placed")
	_check(int(combat.player_hp) == hp_host_hero and int(combat.enemy_hp) == hp_client_hero,
		"no face damage during placement (heroes untouched: %d / %d)" % [int(combat.player_hp), int(combat.enemy_hp)])

	# ── 2. Client (second player) places a 3/2 in the SAME lane, then commits.
	# Its opening turn faces a standing line — de facto turn 2 — so the commit
	# STRIKES: the client's 3/2 swings, the host's defender counters in the same
	# beat (Cross-Blitz mutual trade), and BOTH die in round 1. ──
	print("\n[net-clash] === client places same lane + commits → OPENING STRIKE ===")
	combat._net_spawn_creature(_c32("client"), SS.UID_SLOT_STRIDE + 0, 0, combat.ROW_FRONT, true, false)
	await create_timer(0.1).timeout
	var host_creature = combat._row_array(false, combat.ROW_FRONT)[0]
	var client_creature = combat._row_array(true, combat.ROW_FRONT)[0]
	_check(is_instance_valid(host_creature) and is_instance_valid(client_creature),
		"both 3/2 creatures seated opposite each other in lane 0")
	await combat._net_finish_placement(1)
	for _i in 12:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat) or int(combat._net_turn_round) >= 2:
			break
	if not is_instance_valid(combat):
		print("[net-clash] FATAL: combat freed during clash"); _finish(1); return

	var host_dead: bool = not is_instance_valid(host_creature) or int(host_creature.current_hp) <= 0
	var client_dead: bool = not is_instance_valid(client_creature) or int(client_creature.current_hp) <= 0
	_check(host_dead and client_dead,
		">>> OPENING STRIKE: second player's first commit struck, defender countered — BOTH died (host_dead=%s client_dead=%s)" % [str(host_dead), str(client_dead)])
	_check(not combat._net_match_over, "match still live after the mutual trade")
	_check(int(combat._net_turn_round) == 2, "round advanced to 2 after the opening strike")
	# Strict alternation: the fixed opener (host/0) opens every round.
	_check(int(combat._net_active_index) == 0, "round 2 opens with the fixed opener (active=0, strict alternation)")
	# Neither hero should have taken face damage — the lane was blocked at clash start.
	_check(int(combat.player_hp) == hp_host_hero and int(combat.enemy_hp) == hp_client_hero,
		"no face leaked through the mutual trade (heroes still %d / %d)" % [int(combat.player_hp), int(combat.enemy_hp)])

	print("\n[net-clash] %s" % ("ALL PASS" if _fails == 0 else "%d FAILURES" % _fails))
	_finish(1 if _fails > 0 else 0)
