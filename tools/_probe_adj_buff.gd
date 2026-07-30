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

	# Drop a Torchbearer in the adjacent lane 2. (Battle Drummer used to be the
	# adj_buff carrier here — it now grants adjacent Swift instead, so the
	# torchbearer is the canonical +ATK aura for this test.)
	var torch_data = CDB.get_card_data("torchbearer").duplicate(true)
	var buff: int = int(torch_data.get("adj_buff", {}).get("atk", 0))
	_check(buff > 0, "torchbearer carries adj_buff.atk (=%d)" % buff)
	combat._place_enemy_card(torch_data, 2, FRONT)
	var after: int = neighbour.effective_atk()
	_check(after - before == buff,
		"ENEMY adjacency now APPLIES: neighbour ATK %d -> %d (+%d expected)" % [before, after, buff])
	_check(neighbour.adj_atk_buff == buff,
		"buff is STORED on the card (adj_atk_buff=%d) so it shows on the numeral + nets to the client" % neighbour.adj_atk_buff)

	# The torchbearer's OTHER flank (lane 3) must also be buffed.
	combat._place_enemy_card(CDB.get_card_data("brute").duplicate(true), 3, FRONT)
	var other = combat._row_array(true, FRONT)[3]
	_check(other != null and other.adj_atk_buff == buff,
		"the torchbearer's other neighbour (lane 3) is buffed too (adj_atk_buff=%d)" % (other.adj_atk_buff if other != null else -1))

	# CANONICAL ADJACENCY (2026-07-10): "adjacent" now means row AND column. The
	# seat directly BEHIND the torchbearer (same lane 2, back row) is its column-mate
	# and must be buffed too — this is the seat the old row-only reading missed.
	combat._place_enemy_card(CDB.get_card_data("brute").duplicate(true), 2, combat.ROW_BACK)
	var mate = combat._row_array(true, combat.ROW_BACK)[2]
	_check(mate != null and mate.adj_atk_buff == buff,
		">>> COLUMN-MATE (back row, same lane) is buffed: adj_atk_buff=%d (+%d expected)" % [(mate.adj_atk_buff if mate != null else -1), buff])

	# Kill the drummer → its neighbours lose the buff immediately.
	var drummer = combat._row_array(true, FRONT)[2]
	if drummer != null and is_instance_valid(drummer):
		drummer.current_hp = 0
		combat._cleanup_dead()
		await create_timer(0.2).timeout
	var restored: int = (neighbour.effective_atk() if is_instance_valid(neighbour) else before)
	_check(restored == before,
		"after the drummer dies the neighbour drops back to base ATK (%d)" % restored)

	# ── DIAGONAL CREST (player relic): "Diagonal friendlies count as adjacent." ──
	# A plain column/row neighbour reading would NOT buff a diagonal; with the relic
	# held, _adjacent_creatures must widen to the two diagonal seats too. Player side
	# only (slot 0). Placed on the HOST's own side (is_enemy=false) so the not-is_enemy
	# gate applies. A DIAGONAL vanilla (front lane 1 torch → back lane 2) is the seat.
	SS.get_slot(0).relics.append("diagonal_crest")
	# Vanilla on the player BACK row lane 2 — diagonal to a front-lane-1 torchbearer.
	var pv = combat._net_spawn_creature(CDB.get_card_data("brute").duplicate(true), 91001, 2, combat.ROW_BACK, false, false)
	await create_timer(0.1).timeout
	var pv_before: int = pv.effective_atk() if is_instance_valid(pv) else 0
	# Player torchbearer on FRONT lane 1 (its diagonals are back lanes 0 and 2).
	combat._net_spawn_creature(CDB.get_card_data("torchbearer").duplicate(true), 91002, 1, combat.ROW_FRONT, false, false)
	combat._refresh_adjacency_buffs()
	await create_timer(0.1).timeout
	# THIS IS A NET FIXTURE, AND DIAGONAL CREST IS DELIBERATELY NET-INERT.
	# Combat._adjacent_creatures says so in as many words: the relic is not in
	# NET_RELIC_POOL, so `_has_relic` is false in skirmish and BOTH PEERS read the
	# plain row+column set — which is the whole point, since a widened adjacency
	# on one peer only would desync every adjacency verb in the game.
	# This block used to assert the buff LANDED here, i.e. it demanded the exact
	# behaviour the design forbids, and had been failing ever since. Flipped to
	# lock the real contract: holding the relic must change NOTHING in net.
	# (The relic's actual widening is solo behaviour and belongs in a solo probe.)
	_check(is_instance_valid(pv) and pv.adj_atk_buff == 0,
		">>> DIAGONAL CREST is NET-INERT: the diagonal stays unbuffed in skirmish even while the relic is held (adj_atk_buff=%d)" \
			% (pv.adj_atk_buff if is_instance_valid(pv) else -1))
	# Dropping it must likewise change nothing — no hidden net path reads it.
	SS.get_slot(0).relics.erase("diagonal_crest")
	combat._refresh_adjacency_buffs()
	await create_timer(0.1).timeout
	_check(is_instance_valid(pv) and pv.adj_atk_buff == 0,
		"...and dropping the relic is equally inert (adj_atk_buff=%d)" % (pv.adj_atk_buff if is_instance_valid(pv) else -1))

	if _fails == 0:
		print("[adj-buff] ALL PASS")
	else:
		print("[adj-buff] %d FAILURE(S)" % _fails)
	_finish(1 if _fails > 0 else 0)


func _finish(code: int) -> void:
	_done = true
	quit(code)
