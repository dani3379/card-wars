extends SceneTree
## _probe_net_relic_parity.gd — DO BOTH PLAYERS PLAY BY THE SAME RELIC NUMBERS?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_relic_parity.gd
##
## A skirmish runs the SAME relic through TWO different implementations. The host's
## own side goes through `Combat._start_round` / `Combat._effective_cost`, which read
## every magnitude out of RelicDB. The client's side is modelled host-side by
## `NetPlayerState.begin_turn` / `.effective_cost`, which used to restate those
## magnitudes as literals — `target += 1` for Deep Satchel, `cost - 1` for Last
## Breath, `max_mana += 2` for the Sash, and so on.
##
## Identical today, which is exactly what made it dangerous: retuning any one of
## those relics would have moved the host's numbers and left the client's behind,
## silently, for that relic only, on one player's Command pool or opening hand. No
## existing probe compared the two — `_probe_net_authority` exercises NetPlayerState
## alone, and every combat probe exercises Combat alone.
##
## So this runs both, per relic, and diffs:
##   * MAX COMMAND and HAND SIZE after a turn opens (begin_turn vs _start_round)
##   * EFFECTIVE COST of a sample card under that relic
##
## Both sides start from an empty board and the same deck, so any difference is the
## two implementations disagreeing rather than the two game states differing.

var SS: Node
var NM: Node
var US: Node
var RDB: Node
var combat: Node

var _started := false
var _done := false
var _fails := 0

const DECK: Array = ["brute", "goblin", "brute", "goblin", "strike", "brute",
	"goblin", "brute", "goblin", "strike", "brute", "goblin",
	"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin", "strike"]
# One creature and one spell, so cost arms that key on type are both exercised.
const COST_SAMPLES: Array = ["brute", "strike"]


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


## Boot a net HOST whose LOCAL slot carries exactly `relic`, open a turn, and report
## what Combat decided. All three terms of is_connected_to_peer() or it boots SOLO.
func _host_side(relic: String) -> Dictionary:
	SS.reset()
	for cid in DECK:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 31337
	SS.vs_bot = true
	SS.best_of = 1
	var slot = SS.get_slot(0)
	if slot != null and relic != "":
		slot.relics = [relic]
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
	# Host goes FIRST, so its opening hand is dealt by the natural round-1
	# `_start_round` and no Coin is added. Read that deal rather than forcing a
	# second `_start_round`: clearing `_hand` does not put the cards back in the
	# draw pile, so a re-run refills from a partly spent pile and measures the
	# harness instead of the rule. (First cut of this probe did exactly that and
	# reported the host at 6 cards for ten relics that do not touch draw at all.)
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	# WAIT FOR THE DEAL TO SETTLE, not for its first card. `_layout_hand` deals one
	# card at a time with a per-card delay, so breaking on `size() > 0` catches the
	# hand mid-flight and reports 1. Poll until the count has held steady.
	var last := -1
	var stable := 0
	for _i in 60:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat):
			return {}
		var n: int = combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 4:
			break
	if not is_instance_valid(combat):
		return {}
	var costs: Dictionary = {}
	for cid in COST_SAMPLES:
		var probe = combat.CARD_SCENE.instantiate()
		probe.card_data = SS.skirmish_card_data(cid).duplicate(true)
		probe.card_id = cid
		combat.add_child(probe)
		costs[cid] = int(combat._effective_cost(probe))
		probe.queue_free()
	var out := {
		"max_mana": int(combat.player_max_mana),
		"hand": int(combat._hand.size()),
		"costs": costs,
	}
	combat.queue_free()
	await create_timer(0.35).timeout
	return out


## The same turn, through the host's model of the CLIENT.
func _client_side(relic: String) -> Dictionary:
	var st = load("res://scripts/net/NetPlayerState.gd").new()
	var uids: Array = []
	for i in DECK.size():
		uids.append(100000 + i)
	var relic_list: Array = [] if relic == "" else [relic]
	if not st.setup(DECK, uids, relic_list, [], 31337, SS.BASE_MAX_MANA,
			Callable(SS, "skirmish_card_data")):
		return {}
	# Empty board on both edge columns — what Combat._start_round also sees above.
	st.begin_turn(1, 2)
	var costs: Dictionary = {}
	for cid in COST_SAMPLES:
		var data: Dictionary = SS.skirmish_card_data(cid)
		var entry: Dictionary = {"id": cid, "uid": -1, "cost": int(data.get("cost", 0))}
		costs[cid] = int(st.effective_cost(entry, data, false))
	return {
		"max_mana": int(st.max_mana),
		"hand": int(st.hand.size()),
		"costs": costs,
	}


func _run() -> void:
	print("[relic-parity] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	RDB = root.get_node_or_null("RelicDB")
	if SS == null or NM == null or RDB == null:
		print("[relic-parity] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false

	var relics: Array = [""]           # "" = the no-relic baseline
	relics.append_array(SS.NET_RELIC_POOL)
	for relic_v in relics:
		var relic := String(relic_v)
		var tag := relic if relic != "" else "(no relic)"
		var h: Dictionary = await _host_side(relic)
		if h.is_empty():
			_check(false, "%s: host side booted" % tag)
			continue
		var c: Dictionary = _client_side(relic)
		if c.is_empty():
			_check(false, "%s: client authority accepted the loadout" % tag)
			continue
		var ok_mana: bool = int(h["max_mana"]) == int(c["max_mana"])
		var ok_hand: bool = int(h["hand"]) == int(c["hand"])
		var cost_notes: Array = []
		var ok_cost := true
		for cid in COST_SAMPLES:
			if int(h["costs"][cid]) != int(c["costs"][cid]):
				ok_cost = false
				cost_notes.append("%s host=%d client=%d" % [
					cid, int(h["costs"][cid]), int(c["costs"][cid])])
		_check(ok_mana, "%s: max Command agrees (host=%d client=%d)" % [
			tag, int(h["max_mana"]), int(c["max_mana"])])
		_check(ok_hand, "%s: opening hand size agrees (host=%d client=%d)" % [
			tag, int(h["hand"]), int(c["hand"])])
		_check(ok_cost, "%s: card costs agree%s" % [
			tag, "" if ok_cost else " — " + ", ".join(PackedStringArray(cost_notes))])

	# ── THE COMMAND RAMP: two implementations, one formula (2026-09-16) ──────
	# Combat.command_for_round() is the authority; NetPlayerState restates it,
	# because a RefCounted that tools preload cannot name that script without
	# dragging it into a pre-autoload compile. Both were written static and pure
	# precisely so this diff is possible — an unguarded restatement here is the
	# same shape as the relic literals this whole probe was built to catch.
	# Loaded at RUNTIME, never named at parse time: this is a --script probe.
	var combat_script := load("res://scripts/scenes/Combat.gd")
	var net_script := load("res://scripts/net/NetPlayerState.gd")
	var ramp_ok := true
	var ramp_rows: Array[String] = []
	for r in range(1, 13):
		var a: int = int(combat_script.command_for_round(r))
		var b: int = int(net_script.command_for_round(r))
		ramp_rows.append("r%d=%d" % [r, a])
		if a != b:
			ramp_ok = false
			ramp_rows.append("<<host %d != client %d>>" % [a, b])
	_check(ramp_ok, "Command ramp agrees across both implementations — %s"
		% [" ".join(PackedStringArray(ramp_rows))])
	var shared := ["COMMAND_START", "COMMAND_RAMP_PER_ROUND", "COMMAND_RAMP_CAP",
		"LEGACY_FLAT_COMMAND", "HAND_DRAW_PER_TURN", "HAND_REFILL_TARGET",
		"MAX_BANKED_MANA", "MAX_HAND_SIZE"]
	var drift: Array[String] = []
	for k in shared:
		var ca = combat_script.get(k)
		var na = net_script.get(k)
		if ca == null or na == null or int(ca) != int(na):
			drift.append("%s host=%s client=%s" % [k, ca, na])
	_check(drift.is_empty(), "economy constants agree across both implementations%s"
		% ["" if drift.is_empty() else " — " + ", ".join(PackedStringArray(drift))])

	print("\n[relic-parity] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_finish(1 if _fails > 0 else 0)
