extends Node
## _probe_two_process.gd — PASS 17 of docs/BUG_SWEEP_METHOD_20260829.md (class C17).
##
##   bash tools/run_two_process_match.sh
##
## THE ONE THING EVERY OTHER PASS CANNOT DO: play a match between two real
## processes over a real socket.
##
## The method doc has listed this as the standing infrastructure gap all along, and
## the reason is specific rather than general. Every net probe in this suite runs
## host and client in ONE process, which means the "wire" is a function call and a
## Dictionary handed across is THE SAME OBJECT. Three whole classes of defect are
## invisible under that arrangement and only exist here:
##
##   1. SERIALISATION. In-process, a payload never encodes. Over a socket it is
##      encoded, sized, validated by NetProtocol and decoded again — so a value that
##      does not survive the round trip (an int that is really a float, a nested
##      array past MAX_ARRAY_ITEMS, an object reference someone put in a payload)
##      fails here and nowhere else. The soak MEASURED the clash reel at 81 entries
##      against a 256 cap, but measuring a number is not the same as watching the
##      envelope actually validate — an over-cap reel is REJECTED WHOLE, and the
##      watching peer's screen cuts straight to the outcome with no fight in it.
##   2. REAL ORDERING AND TIMING. Events arrive on their own frames, in whatever
##      order the socket delivers them, interleaved with the receiving peer's own
##      animation. In-process they arrive synchronously, mid-call, always in order.
##   3. THE REAL HANDSHAKE. `is_connected_to_peer()` has three terms, and every
##      single-process probe sets all three by hand — which is exactly why the trap
##      note exists. Here they are earned.
##
## THE PROOF IS A CROSS-PROCESS DIGEST DIFF. Each side writes what it believes the
## match was — final hero HP, the board by entity id, deaths, the caption sequence —
## to its own file. The driver script diffs them. Two processes that played the same
## match must agree about it; a desync is a difference no single assertion has to
## anticipate in advance.
##
## It must run as a SCENE, not `--script`: the real match path ends in
## `_enter_combat_local` → `change_scene_to_file`, which is INERT under `--script`
## (returns OK, installs nothing). And because that call frees the current scene,
## the driving watcher reparents itself to the tree ROOT on ready, so it survives
## the swap into combat the way an autoload would.

const PORT := 7801
const HOST_ADDR := "127.0.0.1"
const STEP_TIMEOUT := 25.0
## Both peers play until this shared round, then hold. See _play_match.
const STOP_ROUND := 5
## Twenty identical cards on both sides. A symmetric deck is deliberate: with the
## same list, the same seed and mirrored boards, any asymmetry in the digest is the
## engine's, not the deal's.
const DECK := ["brute", "goblin", "brute", "goblin", "strike",
	"brute", "goblin", "brute", "goblin", "strike",
	"brute", "goblin", "brute", "goblin", "strike",
	"brute", "goblin", "brute", "goblin", "strike"]

var NM: Node
var SS: Node
var role := ""
var out_path := ""
var style := 0
var _fails := 0
var _peer_seen := false
var _both_ready := false
var _seed_from_host := -1
var _rejections: Array = []
var _combat: Node = null
var _turns_played := 0
var _captions: Array = []


func _ready() -> void:
	# THE HARNESS MUST NOT BE `current_scene`. The real match path ends in
	# `change_scene_to_file`, which FREES the current scene — and the first version
	# of this file was the current scene, so the driver silently died the instant
	# the match it was driving actually started. Reparenting cannot fix that: as the
	# main scene this node ALREADY sits on root, so the reparent was a no-op and the
	# free happened anyway. Instead, hand the work to a second node that lives on
	# root beside `current_scene`, the way an autoload does.
	if not has_meta("bm_watcher"):
		var watcher := Node.new()
		watcher.set_meta("bm_watcher", true)
		watcher.set_script(get_script())
		get_tree().root.call_deferred("add_child", watcher)
		return
	role = OS.get_environment("BM_ROLE")
	out_path = OS.get_environment("BM_OUT")
	style = int(OS.get_environment("BM_STYLE")) if OS.get_environment("BM_STYLE") != "" else 0
	_run()


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  [%s] %s" % [role, label])
	else:
		_fails += 1
		print("  FAIL  [%s] %s" % [role, label])


func _await_until(cond: Callable, what: String, limit := STEP_TIMEOUT) -> bool:
	var elapsed := 0.0
	while elapsed < limit:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	_check(false, "timed out waiting for: " + what)
	return false


func _seed_slots() -> void:
	SS.reset()
	for cid in DECK:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.rng_seed = 918273
	SS.best_of = 1
	SS.vs_bot = false
	for i in [0, 1]:
		var slot = SS.get_slot(i)
		if slot != null:
			slot.relics = []
			slot.potions = []


func _run() -> void:
	NM = get_tree().root.get_node_or_null("NetMatch")
	SS = get_tree().root.get_node_or_null("SkirmishState")
	var US := get_tree().root.get_node_or_null("UserSettings")
	if NM == null or SS == null:
		print("[2p] FATAL: autoloads missing")
		_finish(1)
		return
	if role != "host" and role != "client":
		print("[2p] FATAL: set BM_ROLE=host|client")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
	print("[2p] start role=%s style=%d" % [role, style])

	NM.peer_joined.connect(func(_id): _peer_seen = true)
	NM.connected_to_host.connect(func(): _peer_seen = true)
	NM.ready_state_changed.connect(func(): if NM.both_ready(): _both_ready = true)
	NM.match_starting.connect(func(s): _seed_from_host = s)
	# EVERY protocol rejection is a finding here. In-process there is no envelope to
	# reject; over a socket, a rejection is the peer's screen going blank on a beat.
	NM.protocol_rejected.connect(func(reason): _rejections.append(String(reason)))

	NM.match_mode = SS.MatchMode.QUICK
	_seed_slots()
	if OS.get_environment("BM_DIAG") != "":
		_diag_poll()

	if role == "host":
		await _connect_host()
	else:
		await _connect_client()
	if _fails > 0:
		_finish(1)
		return

	await _play_match()
	_write_digest()
	print("[2p] %s %s" % [role, "ALL PASS" if _fails == 0 else "%d FAILURES" % _fails])
	_finish(1 if _fails > 0 else 0)


func _diag_poll() -> void:
	var last := "?"
	for _i in 400:
		await get_tree().create_timer(0.25).timeout
		var cs := get_tree().current_scene
		var now := "<null>" if cs == null else "%s(%s)" % [cs.name, cs.get_class()]
		if now != last:
			print("[2p] diag t: current_scene %s -> %s  (root children: %d)" % [
				last, now, get_tree().root.get_child_count()])
			last = now


func _connect_host() -> void:
	var err: int = NM.host(PORT)
	_check(err == OK, "opened a server on :%d" % PORT)
	if err != OK:
		return
	if not await _await_until(func(): return _peer_seen, "the client to connect"):
		return
	NM.set_local_ready(true)
	if not await _await_until(func(): return _both_ready, "both peers ready"):
		return
	# All three terms of is_connected_to_peer() are EARNED here, not assigned — the
	# single-process probes have to set them by hand and this is the one place that
	# proves the real handshake produces them.
	_check(NM.is_connected_to_peer(),
		"the real handshake produced a genuinely connected peer")
	NM.battle_style = style
	NM.attach_combat()
	NM.start_match()
	await get_tree().create_timer(0.8).timeout


func _connect_client() -> void:
	await get_tree().create_timer(0.8).timeout
	var err: int = NM.join(HOST_ADDR, PORT)
	_check(err == OK, "join() started toward %s:%d" % [HOST_ADDR, PORT])
	if err != OK:
		return
	if not await _await_until(func(): return _peer_seen, "the connection to the host"):
		return
	NM.set_local_ready(true)
	if not await _await_until(func(): return _both_ready, "both peers ready"):
		return
	_check(NM.is_connected_to_peer(),
		"the real handshake produced a genuinely connected peer")
	NM.battle_style = style
	NM.attach_combat()
	if not await _await_until(func(): return _seed_from_host >= 0, "the match seed"):
		return
	_check(NM.match_seed == _seed_from_host,
		"the match seed crossed the socket intact (%d)" % _seed_from_host)


## Boot combat on THIS peer.
##
## Deliberately NOT via `NetMatch.launch_combat()`. That path ends in
## `change_scene_to_file`, and under this harness the swapped-in scene was observed
## appearing and then being torn down again a moment later — a scene-transition
## problem in the harness, not in the wire, and this pass is about the wire. The
## scene swap already has its own gate (`_probe_net_rematch` asserts the state
## handed across the relaunch boundary), so nothing is lost by standing in for it
## here the way every other net probe does. Everything downstream — intents, events,
## the clash reel, the envelopes — is the real socket.
func _boot_combat() -> bool:
	SS.combat_mode = SS.CombatMode.NET_HOST if role == "host" \
		else SS.CombatMode.NET_CLIENT
	SS.local_index = NM.local_player_index
	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(_combat):
		return false
	# The hand is dealt one card at a time — a probe that breaks on size() > 0
	# measures the deal mid-flight. Poll until the count HOLDS.
	var last := -1
	var stable := 0
	for _i in 60:
		await get_tree().create_timer(0.2).timeout
		if not is_instance_valid(_combat):
			return false
		var n: int = _combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 3:
			break
	return is_instance_valid(_combat)


func _first_empty_slot() -> Control:
	for row in [_combat.ROW_FRONT, _combat.ROW_BACK]:
		var arr = _combat._row_array(false, row)
		for lane in range(_combat.LANES_PER_ROW):
			if arr[lane] == null:
				return _combat._slot_array(false, row)[lane]
	return null


func _my_window() -> bool:
	if not is_instance_valid(_combat):
		return false
	if _combat.phase != _combat.Phase.PLAYER_TURN:
		return false
	if style == NM.STYLE_SEALED:
		return _combat._sorcery_active == NM.local_player_index \
			or (_combat._sorcery_active < 0 and not _combat._sealed_await_foe)
	return _combat._net_active_index == NM.local_player_index


func _play_turn() -> void:
	for _pass in 8:
		if not is_instance_valid(_combat):
			return
		var played := false
		for card in _combat._hand.duplicate():
			if card == null or not is_instance_valid(card) or not card.is_creature():
				continue
			if _combat._effective_cost(card) > _combat.player_mana:
				continue
			var slot := _first_empty_slot()
			if slot == null:
				break
			card.global_position = slot.get_global_rect().get_center() - card.size * 0.5
			_combat._on_card_played(card)
			await get_tree().create_timer(0.08).timeout
			played = true
			break
		if not played:
			break
	if is_instance_valid(_combat):
		_combat._net_on_done_placing()
		await get_tree().create_timer(0.4).timeout


func _play_match() -> void:
	if not await _boot_combat():
		_check(false, "combat booted on this peer")
		return
	_check(true, "combat booted on this peer")
	_check(_combat._is_net(), "combat came up in NET mode, not solo")
	_check(_combat._is_client() == (role == "client"),
		"this peer took the %s side" % ("client" if role == "client" else "host"))

	# STOP ON A SHARED CLOCK, NOT A LOCAL ONE. Counting local turns made the two
	# peers stop at different moments, and the one that finished first tore the
	# socket down — which froze the other mid-match and then showed up in the diff
	# as a board desync. It was not one: the two digests were snapshots of
	# different instants. The round number is state both peers share, so stopping
	# on it is the only way the two digests describe the same moment.
	var stalls := 0
	while is_instance_valid(_combat) and _combat.round_number < STOP_ROUND \
			and not _combat._net_match_over:
		if not _my_window():
			stalls += 1
			if stalls > 900:      # ~45s with no window at all
				break
			await get_tree().create_timer(0.05).timeout
			continue
		stalls = 0
		_turns_played += 1
		await _play_turn()
		if is_instance_valid(_combat):
			var cap := String(_combat._phase_caption)
			if cap != "" and (_captions.is_empty() or _captions[-1] != cap):
				_captions.append(cap)
	_check(_turns_played >= 2,
		"this peer actually got turns over the wire (%d)" % _turns_played)
	# QUIESCE BEFORE MEASURING. The loop exits the instant the shared round counter
	# ticks over, which on one peer can be mid-clash while the other is still
	# replaying the reel. Hold both sides still — and keep the socket UP while
	# doing it, since a peer that leaves early ends the other's match — so the two
	# digests are taken over the same settled board.
	var quiet := 0.0
	while quiet < 8.0 and is_instance_valid(_combat) and not _combat._net_match_over:
		await get_tree().create_timer(0.25).timeout
		quiet += 0.25
		# In Sealed Orders, also wait out any half-finished orders phase: a digest
		# taken while local stand-ins are still on the board compares a preview
		# against the other peer's authoritative board and calls the difference a
		# desync. Give the reveal time to land before measuring.
		if quiet >= 3.0 and style == NM.STYLE_SEALED \
				and _combat._sealed_pending.is_empty():
			break
	# THE HEADLINE ASSERTION OF THIS PASS. Every beat of the match crossed a real
	# envelope; a single rejection means the other peer's screen lost that beat.
	_check(_rejections.is_empty(),
		"nothing was rejected by the protocol (%s)" % (
			"clean" if _rejections.is_empty() else ", ".join(_rejections)))


## What this peer believes the match was. The driver diffs the two files.
func _digest() -> Dictionary:
	var d := {"role": role, "style": style, "turns": _turns_played,
		"rejections": _rejections, "fails": _fails}
	if not is_instance_valid(_combat):
		d["board"] = []
		return d
	d["player_hp"] = int(_combat.player_hp)
	d["enemy_hp"] = int(_combat.enemy_hp)
	# SEALED STAND-INS ARE NOT DESYNCS. A body with entity_id -1 on a client board
	# is legitimate mid-orders: `_sealed_pending` holds local previews that carry no
	# network identity until the reveal spawns the authoritative ones. So record
	# whether the sealed phase is actually quiescent, and which of those bodies are
	# still TRACKED as pending — an untracked -1 is an orphan and a real defect,
	# a tracked one is just a snapshot taken mid-phase.
	var pending_nodes := {}
	for p in _combat._sealed_pending:
		var n = p.get("node")
		if n != null and is_instance_valid(n):
			pending_nodes[n] = true
	d["sealed_pending"] = _combat._sealed_pending.size()
	d["sealed_await_foe"] = bool(_combat._sealed_await_foe)
	var orphans: Array = []
	# Board by ENTITY ID, which is the one identity both peers share — positions
	# describe the host's board and the client's is its mirror, so a positional
	# digest would report a false desync on every single run.
	var board: Array = []
	for is_enemy in [false, true]:
		for row in [_combat.ROW_FRONT, _combat.ROW_BACK]:
			var arr = _combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					continue
				if int(c.entity_id) < 0 and not pending_nodes.has(c):
					orphans.append("%s r%d l%d %s" % [
						"foe" if is_enemy else "mine", row, lane,
						String(c.card_data.get("id", "?"))])
				board.append("%d:%s:%d/%d" % [int(c.entity_id), String(c.card_data.get("id", "?")),
					int(c.effective_atk()), int(c.current_hp)])
	board.sort()
	d["board"] = board
	d["orphans"] = orphans
	return d


func _write_digest() -> void:
	if out_path == "":
		return
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("[2p] could not write digest to %s" % out_path)
		return
	f.store_string(JSON.stringify(_digest(), "  "))
	f.close()
	print("[2p] digest written to %s" % out_path)


func _finish(code: int) -> void:
	if NM != null:
		NM.leave()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(code)
