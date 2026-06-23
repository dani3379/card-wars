extends SceneTree
## Targeted regression probe for the adjacency-buff fix (Battle Drummer & kin).
##
## The bug: a creature's `adj_buff` ("Adjacent friendlies +N ATK") was applied
## only for the player side and only at attack-resolution time — never written to
## the card — so (a) an ENEMY / online-opponent Battle Drummer buffed nobody, and
## (b) the bonus never showed on the ATK numeral. This boots the REAL combat scene
## headless (NET_HOST boots cleanly without a campaign RunState), seats a vanilla
## creature, drops a Battle Drummer beside it, and asserts the neighbour's
## effective_atk() rises by the buff AND that the bonus is stored on the card
## (so it shows + rides the net snapshot). Then it kills the drummer and asserts
## the neighbour drops back.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_adj_buff.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false
var combat: Node
var SS: Node
var NM: Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()
	return _done


func _run_test() -> void:
	print("[adj-buff] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	var CDB = root.get_node_or_null("CardDB")
	if SS == null or NM == null or CDB == null:
		print("[adj-buff] FATAL: autoloads missing")
		_finish(1)
		return

	# Boot combat as a connected host so _ready builds the board without a campaign
	# RunState (mirrors _probe_skirmish_combat's setup).
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 999
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _tick in 8:
		await create_timer(0.3).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		_check(false, "combat scene survived boot")
		_finish(1)
		return

	var FRONT = combat.ROW_FRONT

	# ── ENEMY SIDE — the exact reported case (opponent's Battle Drummer) ─────────
	# Seat a vanilla creature at lane 1; measure its ATK before any neighbour.
	combat._place_enemy_card(CDB.get_card_data("brute").duplicate(true), 1, FRONT)
	var neighbour = combat._row_array(true, FRONT)[1]
	_check(neighbour != null, "vanilla enemy seated at lane 1")
	if neighbour == null:
		_finish(1)
		return
	var before: int = neighbour.effective_atk()

	# Drop a Battle Drummer in the adjacent lane 2.
	var drummer_data = CDB.get_card_data("battle_drummer").duplicate(true)
	var buff: int = int(drummer_data.get("adj_buff", {}).get("atk", 0))
	_check(buff > 0, "battle_drummer carries adj_buff.atk (=%d)" % buff)
	combat._place_enemy_card(drummer_data, 2, FRONT)
	var after: int = neighbour.effective_atk()
	_check(after - before == buff,
		"ENEMY adjacency now APPLIES: neighbour ATK %d -> %d (+%d expected)" % [before, after, buff])
	_check(neighbour.adj_atk_buff == buff,
		"buff is STORED on the card (adj_atk_buff=%d) so it shows on the numeral + nets to the client" % neighbour.adj_atk_buff)

	# The drummer's OTHER flank (lane 3) must also be buffed.
	combat._place_enemy_card(CDB.get_card_data("brute").duplicate(true), 3, FRONT)
	var other = combat._row_array(true, FRONT)[3]
	_check(other != null and other.adj_atk_buff == buff,
		"the drummer's other neighbour (lane 3) is buffed too (adj_atk_buff=%d)" % (other.adj_atk_buff if other != null else -1))

	# Kill the drummer → its neighbours lose the buff immediately.
	var drummer = combat._row_array(true, FRONT)[2]
	if drummer != null and is_instance_valid(drummer):
		drummer.current_hp = 0
		combat._cleanup_dead()
		await create_timer(0.2).timeout
	var restored: int = (neighbour.effective_atk() if is_instance_valid(neighbour) else before)
	_check(restored == before,
		"after the drummer dies the neighbour drops back to base ATK (%d)" % restored)

	if _fails == 0:
		print("[adj-buff] ALL PASS")
	else:
		print("[adj-buff] %d FAILURE(S)" % _fails)
	_finish(1 if _fails > 0 else 0)


func _finish(code: int) -> void:
	_done = true
	quit(code)
