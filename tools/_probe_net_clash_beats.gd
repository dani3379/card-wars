extends SceneTree
## _probe_net_clash_beats.gd — THE SKIRMISH CLASH IS THE CAMPAIGN CLASH (2026-08-04).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_clash_beats.gd
##
## The campaign clash spent two passes learning to be readable: one column at a
## time under a spotlight, named ranks, a dwell spent where the information is, a
## paced corpse flush that says who fell, and a one-line ledger at the end. None of
## that reached Online Skirmish — the same creatures on the same board resolved as a
## single burst, on BOTH machines. This probe is the gate on the fix.
##
## It asserts two halves, because they fail independently:
##
##   1. THE HOST'S SCREEN. `_net_run_clash` must raise the same captions solo does,
##      move the ClashLaneFocus, flush its corpses through the paced sweep, and
##      close with the casualty ledger.
##
##   2. THE WATCHER'S SCREEN. Everything above has to reach the client, which never
##      runs a resolver. The clash LOG is the only channel, so the reel must carry
##      the caption / focus / dwell / fallen markers — and the dwell must cross as a
##      KIND, never as the host's seconds (the Clash Pause dial belongs to whoever
##      is reading the screen).
##
## The log is captured by sampling `_net_clash_log` every frame and accumulating
## before `_net_send_clash_log` clears it — with no real peer the send is a no-op,
## so this is the only way to see what a client would have received.
##
## HOUSE TRAP: all THREE terms of `is_connected_to_peer()` must be set or Combat
## boots SOLO and every net assertion here fails for a reason none of them name
## (see _probe_net_clash, and _probe_net_repos_client which fell into it).

var CDB: Node
var SS: Node
var NM: Node
var US: Node
var combat: Node
var _started := false
var _done := false
var _fails := 0

# The accumulated reel, rebuilt across the segments the host ships separately.
var _reel: Array = []
var _seen: int = 0
var _sampling := false
# Everything the host's own screen was told, in order.
var _captions: Array[String] = []
var _last_caption := ""
var _focus_moves: int = 0
var _last_focus_rect := Rect2()
# The info line is a TIMED channel (it clears itself), so the ledger has to be
# caught as it lands rather than read off the label once the dust settles.
var _info_lines: Array[String] = []


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
	if _sampling and is_instance_valid(combat):
		_sample()
	return _done


## One frame's worth of observation. The log is append-only until the host ships a
## segment and clears it, so a shrink means "a segment went out" — start counting
## the next one from zero rather than losing it.
func _sample() -> void:
	var log_now: Array = combat._net_clash_log
	if log_now.size() < _seen:
		_seen = 0
	while _seen < log_now.size():
		_reel.append(log_now[_seen])
		_seen += 1
	var cap := String(combat._phase_caption)
	if cap != "" and cap != _last_caption:
		_last_caption = cap
		_captions.append(cap)
	var f = combat._clash_lane_focus
	if f != null and is_instance_valid(f):
		var r: Rect2 = f.get("_focus_rect")
		if r.size.x > 0.0 and r != _last_focus_rect:
			_last_focus_rect = r
			_focus_moves += 1
	if combat._info_label != null and is_instance_valid(combat._info_label):
		var line := String(combat._info_label.text).strip_edges()
		if line != "" and (_info_lines.is_empty() or _info_lines[-1] != line):
			_info_lines.append(line)


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _body(tag: String, atk: int, hp: int) -> Dictionary:
	return {
		"id": "beat_%s" % tag, "name": "Beat%s" % tag,
		"type": "creature", "cost": 1, "atk": atk, "hp": hp,
		"rarity": "common", "keywords": [], "desc": "",
	}


func _run() -> void:
	print("[net-beats] start")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if CDB == null or SS == null or NM == null:
		print("[net-beats] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true

	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 24680
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true   # the third term — or Combat boots SOLO
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 10:
		await create_timer(0.3).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		print("[net-beats] FATAL: combat freed during boot"); _finish(1); return
	_check(combat._is_net(), "combat booted as a NET match (not SOLO)")

	# ── A board worth watching: four contested columns, front and back. Lane 0 is
	# a mutual kill, lane 1 a survivable trade, lane 2 a one-sided kill, lane 3 a
	# back-rank pair. That is >=3 corpses, which is also the mass-grave threshold.
	combat._net_spawn_creature(_body("h0", 5, 1), 6001, 0, combat.ROW_FRONT, false, false)
	combat._net_spawn_creature(_body("h1", 1, 9), 6002, 1, combat.ROW_FRONT, false, false)
	combat._net_spawn_creature(_body("h2", 6, 9), 6003, 2, combat.ROW_FRONT, false, false)
	combat._net_spawn_creature(_body("h3", 4, 4), 6004, 3, combat.ROW_BACK, false, false)
	combat._net_spawn_creature(_body("c0", 5, 1), 7001, 0, combat.ROW_FRONT, true, false)
	combat._net_spawn_creature(_body("c1", 1, 9), 7002, 1, combat.ROW_FRONT, true, false)
	combat._net_spawn_creature(_body("c2", 1, 2), 7003, 2, combat.ROW_FRONT, true, false)
	combat._net_spawn_creature(_body("c3", 2, 2), 7004, 3, combat.ROW_BACK, true, false)
	await create_timer(0.2).timeout
	# The muster delay holds every arrival for the round it landed in. Stand them
	# all up so the clash below is a real exchange and not eight bodies forming up.
	for c in combat._all_creatures_both_sides():
		c.state.ready_to_swing = true
		c.has_attacked_this_turn = false
	_check(combat._all_creatures_both_sides().size() == 8, "eight bodies staged")

	# Hook the corpse naming so the probe sees WHO the flush announced. Same funnel
	# the campaign uses (`_name_the_fallen` -> `spawn_keyword_callout`), read here
	# off the callout the flush spawns rather than by re-deriving the dead.
	var before_names: Array = []
	for c in combat._all_creatures_both_sides():
		before_names.append(String(c.card_data.get("name", "")))

	print("\n[net-beats] === one host-side clash ===")
	_sampling = true
	await combat._net_run_clash(-1)   # both sides strike (the sealed/simultaneous form)
	await create_timer(0.6).timeout
	_sampling = false

	print("[net-beats] captions: %s" % str(_captions))
	print("[net-beats] reel: %d entries" % _reel.size())

	# ── 1. THE HOST'S SCREEN ──────────────────────────────────────────────
	print("\n[net-beats] --- the host's screen ---")
	_check(_captions.has("FRONT ROW ATTACKS"),
		"the front row is NAMED (the clash has phase boundaries, not one 'CLASH')")
	_check(_captions.has("THE FALLEN"),
		"the corpses are announced BEFORE they go")
	_check(_focus_moves >= 2,
		"the spotlight moved across columns (%d moves)" % _focus_moves)
	_check(combat._all_creatures_both_sides().size() < 8,
		"the clash actually killed something (%d bodies left)" %
			combat._all_creatures_both_sides().size())
	var ledger := ""
	for line in _info_lines:
		if line.contains("down") or line.contains("holds"):
			ledger = line
	_check(ledger != "",
		"the clash closes with the casualty ledger (info lines: %s)" % str(_info_lines))

	# ── 2. THE WATCHER'S SCREEN — everything above, on the wire ───────────
	print("\n[net-beats] --- what the client would receive ---")
	var kinds := {}
	for e in _reel:
		for k in e.keys():
			kinds[k] = int(kinds.get(k, 0)) + 1
	print("[net-beats] reel keys: %s" % str(kinds))
	_check(kinds.has("cap"), "the reel carries the phase captions")
	_check(kinds.has("fo"), "the reel carries the spotlight column")
	_check(kinds.has("dw"), "the reel carries the per-column dwell")
	_check(kinds.has("fal"), "the reel carries the corpse-flush marker")
	_check(kinds.has("d") or kinds.has("f"), "the reel still carries the strikes themselves")

	var reel_caps: Array = []
	var dwell_kinds := {}
	var focus_clear := false
	for e in _reel:
		if e.has("cap"):
			reel_caps.append(String(e["cap"]))
		if e.has("dw"):
			dwell_kinds[int(e["dw"])] = true
		if e.has("fo") and int(e["fo"]) < 0:
			focus_clear = true
	_check(reel_caps.has("FRONT ROW ATTACKS") and reel_caps.has("THE FALLEN"),
		"the SAME captions the host raised reach the reel: %s" % str(reel_caps))
	_check(focus_clear, "the reel ends by taking the spotlight OFF the board")

	# The closing sentence. The two death tallies are only ever incremented by a
	# resolver, which a client does not run, so the watcher's clash used to end with
	# nothing summing it up. It crosses as COUNTS — a finished string would tell the
	# player who just lost four bodies that their line held.
	var ledger_entry := {}
	for e in _reel:
		if e.has("led"):
			ledger_entry = e
	_check(not ledger_entry.is_empty(), "the reel carries the closing casualty ledger")
	_check(ledger_entry.get("led", []) is Array and ledger_entry.get("led", []).size() == 2,
		"the ledger crosses as the two COUNTS, never as the host's finished sentence")

	# The dwell must cross as a CHOICE, not a duration: a float would impose the
	# host's Clash Pause preference on the other player's screen.
	var all_ints := true
	for e in _reel:
		if e.has("dw") and typeof(e["dw"]) != TYPE_INT:
			all_ints = false
	_check(all_ints, "the dwell crosses as a KIND (int), never as the host's seconds")
	var valid_kinds := true
	for k in dwell_kinds:
		if k < 0 or k > 2:
			valid_kinds = false
	_check(valid_kinds, "every dwell kind is one of MINOR/NORMAL/KILL: %s" % str(dwell_kinds.keys()))
	_check(dwell_kinds.has(2),
		"a column that produced a corpse asked for the KILL dwell")

	# ── 3. THE BLOW'S WEIGHT CLASS ────────────────────────────────────────
	#
	# The host punctuates a strike off its PRE-mitigation size (_strike_stop /
	# _strike_read / the tracer width / the spark spray); `n` is only what survived
	# Armored, a Shield or an HP floor. A client working from `n` alone therefore ran a
	# different weight class for the same blow — an 8-ATK swing a Shield ate whole is
	# still a heavy swing — so the two peers punctuated one strike differently.
	var strike_entries: Array = []
	for e in _reel:
		if e.has("d"):
			strike_entries.append(e)
	var all_weighed := not strike_entries.is_empty()
	for e in strike_entries:
		if not e.has("p") or typeof(e["p"]) != TYPE_INT or int(e["p"]) <= 0:
			all_weighed = false
	_check(all_weighed,
		"every logged strike carries the blow's weight class (%d entries)" % strike_entries.size())

	# ── 4. A SHOT IS MARKED AS A SHOT ─────────────────────────────────────
	#
	# The tracer draws tighter and colder for a ranged attack so a marksman does not
	# read like a melee attacker. The client can only know from the log, so without
	# `rng` every skirmish sniper shot came out as a warm melee slash.
	print("\n[net-beats] === a second clash, with a marksman ===")
	_reel.clear()
	_seen = 0
	var sniper := _body("sniper", 3, 6)
	sniper["keywords"] = ["sniper"]
	combat._net_spawn_creature(sniper, 6101, 0, combat.ROW_BACK, false, false)
	combat._net_spawn_creature(_body("quarry", 1, 4), 7101, 3, combat.ROW_FRONT, true, false)
	await create_timer(0.2).timeout
	for c in combat._all_creatures_both_sides():
		c.state.ready_to_swing = true
		c.has_attacked_this_turn = false
	_sampling = true
	await combat._net_run_clash(-1)
	await create_timer(0.6).timeout
	_sampling = false
	var ranged_hits: int = 0
	for e in _reel:
		if e.has("d") and bool(e.get("rng", false)):
			ranged_hits += 1
	_check(ranged_hits > 0,
		"the marksman's shot is logged as RANGED (%d of %d strike entries)" %
			[ranged_hits, _reel.size()])

	# Creature-trigger parity: the fx queue is the client's only route to a
	# battlecry/deathrattle beat, so a `trig` entry must be shippable.
	var has_trig_support: bool = load("res://scripts/net/CombatNet.gd").source_code \
		.contains("_net_replay_trigger_fx")
	_check(has_trig_support, "the client has a trigger-FX replay path at all")

	if _fails == 0:
		print("\n[net-beats] ALL PASS")
	else:
		print("\n[net-beats] %d FAILURES" % _fails)
	_finish(1 if _fails > 0 else 0)
