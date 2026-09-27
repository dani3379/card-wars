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
	# ALL THREE terms. is_connected_to_peer() is
	# `vs_bot or (_connected and remote_present and _compatibility_confirmed)`,
	# and Combat._ready falls back to SOLO when it is false — so a two-term fake
	# boots the CAMPAIGN arm while every label here still says skirmish.
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
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
	#
	# WHERE NET-INERTNESS ACTUALLY LIVES. This block used to seed the relic with
	# `SS.get_slot(0).relics.append("diagonal_crest")` and then assert the widening
	# did nothing. That assertion was never sound in either direction:
	#   · while the probe silently booted SOLO (a two-term net fake), `_has_relic`
	#     read the empty campaign RunState, so NOTHING was held and it passed
	#     vacuously — the relic id in the slot was never even consulted;
	#   · booted for real as NET, `_has_relic` returns `slot.relics.has(id)`
	#     verbatim, so the hand-seeded relic IS held, `_adjacent_creatures` widens,
	#     and the diagonal gets buffed. The "inert" assertion fails.
	# Neither run tested the contract, because the contract is not enforced inside
	# `_has_relic` or `_adjacent_creatures` at all — it is enforced ONE LAYER UP,
	# at pool membership: diagonal_crest is not in NET_RELIC_POOL, and
	# `validate_loadout_event` rejects any loadout naming an off-pool relic, so it
	# can never reach a slot in a real match. Seeding it directly forged a state
	# the wire refuses to produce.
	#
	# So assert the real gate instead, and stop pretending a forged slot proves
	# anything. (The relic's actual widening is SOLO behaviour and belongs in a
	# solo probe — nothing here can or should cover it.)
	_check(not SS.NET_RELIC_POOL.has("diagonal_crest"),
		">>> DIAGONAL CREST is out of NET_RELIC_POOL — the gate that keeps a widened adjacency off the wire")
	var forged_deck: Array = []
	var legal_pool: Array = SS.skirmish_legal_pool()
	for i in range(SS.DECK_TARGET):
		forged_deck.append(String(legal_pool[i % legal_pool.size()]))
	var verdict: String = SS.validate_loadout_event({
		"cards": forged_deck, "relics": ["diagonal_crest"], "potions": [],
	})
	_check(verdict == "loadout_relic_illegal",
		"a loadout naming it is REFUSED at the wire (verdict='%s')" % verdict)
	# ...and the same validator accepts the loadout once the relic is dropped, so
	# the refusal above is about THIS relic and not a malformed fixture.
	var clean_verdict: String = SS.validate_loadout_event({
		"cards": forged_deck, "relics": [], "potions": [],
	})
	_check(clean_verdict == "",
		"the same loadout without it is legal — the refusal is the relic, not the fixture (verdict='%s')" % clean_verdict)

	if _fails == 0:
		print("[adj-buff] ALL PASS")
	else:
		print("[adj-buff] %d FAILURE(S)" % _fails)
	_finish(1 if _fails > 0 else 0)


func _finish(code: int) -> void:
	_done = true
	quit(code)
