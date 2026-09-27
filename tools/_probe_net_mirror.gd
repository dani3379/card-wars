extends SceneTree
## _probe_net_mirror.gd — DO THE TWO PLAYERS SEE THE SAME FIGHT? (2026-08-04)
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_mirror.gd
##
## Every other net probe checks ONE side. `_probe_net_clash_beats` proves the host
## ships a complete reel; `_probe_net_client_replay` proves the client can play one.
## Neither answers the question the complaint actually asked — *do the two screens
## agree* — because nothing had ever put a host clash and its client replay side by
## side and diffed them.
##
## So this runs BOTH, in one process, over ONE fight:
##
##   PHASE A — boot a HOST, stage a board, run a real `_net_run_clash`, and record
##             what the host's own screen was told plus the exact reel it shipped.
##   PHASE B — tear that down, re-boot as a CLIENT with the MIRRORED board and the
##             same entity ids, feed it that captured reel, and record the same things.
##   PHASE C — diff.
##
## WHAT "THE SAME" MEANS HERE, and what it deliberately does not:
##
##   * The BOARD must end identical, body for body, by entity id. This is the one
##     assertion with no tolerance: if a blow went missing on the watcher's screen the
##     two players are looking at different fights.
##   * The CAPTION sequence must be identical. Same fight, same named phases.
##   * The LEDGER must be MIRRORED, not copied — "ours" is whoever is reading.
##   * The VISIBLE BEAT COUNT (`_visible_beat_seq`, the counter every chip / float /
##     banner / ring funnel bumps) is the direct measure of the original complaint,
##     "a lot of the effects are just not there". It is compared as a RATIO with a
##     floor rather than for equality: the host runs resolvers the client never will,
##     so a handful of host-only beats is correct and expected. A client at a small
##     fraction of the host is the bug.
##
## HOUSE TRAP: all THREE terms of `is_connected_to_peer()` on BOTH boots, or Combat
## comes up SOLO and the whole comparison silently measures the campaign path twice.

var SS: Node
var NM: Node
var US: Node
var combat: Node

var _started := false
var _done := false
var _fails := 0

# What each side's own screen was told.
var _captions: Array[String] = []
var _info_lines: Array[String] = []
var _last_caption := ""
var _sampling := false
# The reel the host shipped, accumulated across the segments it sends separately.
var _reel: Array = []
var _seen: int = 0

var _host_captions: Array[String] = []
var _host_info: Array[String] = []
var _host_board: Dictionary = {}
var _host_beats: int = 0
var _host_sync: Dictionary = {}


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


func _sample() -> void:
	var log_now: Array = combat._net_clash_log
	if log_now.size() < _seen:
		_seen = 0          # a segment shipped and the log cleared — keep counting
	while _seen < log_now.size():
		_reel.append(log_now[_seen])
		_seen += 1
	var cap := String(combat._phase_caption)
	if cap != "" and cap != _last_caption:
		_last_caption = cap
		_captions.append(cap)
	if combat._info_label != null and is_instance_valid(combat._info_label):
		var line := String(combat._info_label.text).strip_edges()
		if line != "" and (_info_lines.is_empty() or _info_lines[-1] != line):
			_info_lines.append(line)


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _body(tag: String, atk: int, hp: int) -> Dictionary:
	return {
		"id": "mir_%s" % tag, "name": "Mirror%s" % tag,
		"type": "creature", "cost": 1, "atk": atk, "hp": hp,
		"rarity": "common", "keywords": [], "desc": "",
	}


## The staged fight, identical on both boots. `is_enemy` is written from the HOST's
## point of view; phase B flips it, which is the whole mirror.
##
## Lane 0: a mutual kill (5/1 into 5/1). Lane 1: a survivable trade (1/9 into 1/9).
## Lane 2: a one-sided kill with a Thorns biter, so a keyword chip fires mid-clash.
## Lane 3 (back): a plain pair.
func _stage(flip: bool) -> void:
	var thorny := _body("thorn", 1, 6)
	thorny["keywords"] = ["thorns"]
	var plan: Array = [
		[_body("h0", 5, 1), 6001, 0, combat.ROW_FRONT, false],
		[_body("h1", 1, 9), 6002, 1, combat.ROW_FRONT, false],
		[_body("h2", 6, 9), 6003, 2, combat.ROW_FRONT, false],
		[_body("h3", 4, 4), 6004, 3, combat.ROW_BACK, false],
		[_body("c0", 5, 1), 7001, 0, combat.ROW_FRONT, true],
		[_body("c1", 1, 9), 7002, 1, combat.ROW_FRONT, true],
		[thorny,            7003, 2, combat.ROW_FRONT, true],
		[_body("c3", 2, 2), 7004, 3, combat.ROW_BACK, true],
	]
	for p in plan:
		var is_enemy: bool = bool(p[4]) != flip     # phase B sees the board mirrored
		combat._net_spawn_creature(p[0], int(p[1]), int(p[2]), int(p[3]), is_enemy, false)


## Rebuild the trailing board snapshot the host ships after a clash (the shape
## `_net_sync_board` sends). The comparison NEEDS this: the client's corpses belong to
## that snapshot, not to the reel — it holds them standing on purpose so their names
## can be read first — so a client diffed before it lands is correctly still holding
## four bodies the host has already swept. That is the deferred-deaths feel working,
## not a mismatch, and the first cut of this probe mistook one for the other.
func _capture_sync() -> Dictionary:
	var creatures: Array = []
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				var c = arr[lane]
				if c == null or not is_instance_valid(c) or c.current_hp <= 0:
					continue
				creatures.append({
					"eid": int(c.entity_id),
					"owner": (1 if is_enemy else 0),
					"lane": lane, "row": row,
					"id": String(c.card_id),
					"atk": int(c.effective_atk()),
					"hp": int(c.current_hp),
					"mhp": int(c.card_data.get("hp", c.current_hp)),
					"kw": c.card_data.get("keywords", []),
					"floop": bool(c.will_floop),
					"token": bool(c.is_token),
					"state": c.state.to_replication_snapshot(),
				})
	return {
		"t": NM.EV_BOARD_SYNC,
		"creatures": creatures,
		"host_hp": int(combat.player_hp),
		"client_hp": int(combat.enemy_hp),
		"active": 0,
	}


## Board state keyed by entity id — the thing that must match exactly. Side is
## recorded as "mine / theirs" from the LOCAL player's view, so a correct mirror
## produces the same dictionary on both peers.
func _board_state() -> Dictionary:
	var out := {}
	for c in combat._all_creatures_both_sides():
		if not is_instance_valid(c) or int(c.entity_id) < 0:
			continue
		out[int(c.entity_id)] = {
			"hp": int(c.current_hp),
			"mine": not bool(c.is_opponent),
			"dead": int(c.current_hp) <= 0,
		}
	return out


func _boot(as_host: bool) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST if as_host else SS.CombatMode.NET_CLIENT
	SS.local_index = 0 if as_host else 1
	SS.rng_seed = 24680
	NM.is_host = as_host
	NM.local_player_index = 0 if as_host else 1
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true   # the third term — or Combat boots SOLO
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	# HOUSE TRAP (see _shot_net_client_death's header): Card2D resolves its VFX host
	# through `get_tree().current_scene` (_combat_vfx_target), so without this every
	# damage numeral, chip and burst a CARD raises silently no-ops.
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 10:
		await create_timer(0.3).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		print("[mirror] FATAL: combat freed during boot")
		return false
	return true


func _run() -> void:
	print("[mirror] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[mirror] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		# IDENTICAL dials on both peers. The pacing is deliberately the reader's own,
		# so a comparison run has to hold it equal or it measures the settings.
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
		US.clash_dwell_scale = 1.0

	# ── PHASE A — the HOST fights it ─────────────────────────────────────
	print("\n[mirror] === PHASE A: the host's fight ===")
	if not await _boot(true):
		_finish(1); return
	_check(combat._is_net() and combat._is_host(), "phase A booted as a NET HOST (not SOLO)")
	_stage(false)
	await create_timer(0.2).timeout
	for c in combat._all_creatures_both_sides():
		c.state.ready_to_swing = true      # the muster delay would hold every arrival
		c.has_attacked_this_turn = false
	var beats_before: int = int(combat._visible_beat_seq)
	_sampling = true
	await combat._net_run_clash(-1)
	await create_timer(0.6).timeout
	_sampling = false

	_host_beats = int(combat._visible_beat_seq) - beats_before
	_host_captions = _captions.duplicate()
	_host_info = _info_lines.duplicate()
	_host_board = _board_state()
	_host_sync = _capture_sync()
	print("[mirror] host: %d visible beats, %d reel entries, board %d bodies" % [
		_host_beats, _reel.size(), _host_board.size()])
	print("[mirror] host captions: %s" % str(_host_captions))
	_check(_host_beats > 0, "the host's clash produced visible beats at all")
	_check(not _reel.is_empty(), "the host shipped a reel")

	combat.queue_free()
	await create_timer(0.6).timeout

	# ── PHASE B — the CLIENT watches the same fight ──────────────────────
	print("\n[mirror] === PHASE B: the watcher's fight ===")
	_captions.clear()
	_info_lines.clear()
	_last_caption = ""
	if not await _boot(false):
		_finish(1); return
	_check(combat._is_net() and combat._is_client(), "phase B booted as a NET CLIENT (not SOLO)")
	_stage(true)
	await create_timer(0.2).timeout
	var cl_beats_before: int = int(combat._visible_beat_seq)
	_sampling = true
	await combat._net_replay_clash({"strikes": _reel, "atk": -1, "banner": true})
	await create_timer(0.6).timeout
	# The corpses go with the trailing snapshot, exactly as in a real match — the reel
	# names them, the snapshot sweeps them.
	var held_before_sync: int = combat._all_creatures_both_sides().size()
	combat._net_apply_board_sync(_host_sync)
	await create_timer(0.8).timeout
	_sampling = false
	var client_beats: int = int(combat._visible_beat_seq) - cl_beats_before
	var client_board: Dictionary = _board_state()
	_check(held_before_sync > client_board.size(),
		"the watcher HELD its corpses through the reel and swept them with the snapshot (%d → %d)" % [
			held_before_sync, client_board.size()])
	print("[mirror] client: %d visible beats, board %d bodies" % [
		client_beats, client_board.size()])
	print("[mirror] client captions: %s" % str(_captions))

	# ── PHASE C — the diff ───────────────────────────────────────────────
	print("\n[mirror] === PHASE C: do the two screens agree? ===")

	# 1. THE BOARD. No tolerance: a body that ended on different HP means the two
	#    players watched different fights.
	var board_same := _host_board.size() == client_board.size()
	var board_diff: Array[String] = []
	for eid in _host_board:
		var h: Dictionary = _host_board[eid]
		var c2 = client_board.get(eid, null)
		if c2 == null:
			board_same = false
			board_diff.append("eid %d missing on the client" % eid)
			continue
		if int(h["hp"]) != int(c2["hp"]):
			board_same = false
			board_diff.append("eid %d: host %d HP, client %d HP" % [eid, h["hp"], c2["hp"]])
		# The mirror: a body the host calls friendly is the client's foe.
		if bool(h["mine"]) == bool(c2["mine"]):
			board_same = false
			board_diff.append("eid %d is on the SAME side on both peers — not mirrored" % eid)
	_check(board_same, "every body ends on the same HP, on the mirrored side%s" % (
		"" if board_diff.is_empty() else " — " + str(board_diff)))

	# 2. THE CAPTIONS. Same fight, same named phases, same order.
	_check(_captions == _host_captions,
		"the watcher's phase captions match the host's exactly\n         host:   %s\n         client: %s" % [
			str(_host_captions), str(_captions)])

	# 3. THE LEDGER — mirrored, never copied.
	var host_ledger := ""
	for line in _host_info:
		if line.contains("down") or line.contains("holds"):
			host_ledger = line
	var client_ledger := ""
	for line in _info_lines:
		if line.contains("down") or line.contains("holds"):
			client_ledger = line
	_check(host_ledger != "" and client_ledger != "",
		"both screens close on a casualty ledger (host: '%s' / client: '%s')" % [
			host_ledger, client_ledger])
	_check(host_ledger != client_ledger,
		"the ledger is MIRRORED, not copied — 'ours' is whoever is reading it")

	# 4. THE EFFECTS THEMSELVES — the original complaint ("a lot of the effects are
	#    just not there"), gated as KIND COVERAGE rather than as a count.
	#
	#    A raw `_visible_beat_seq` ratio was tried first and is NOT a usable gate: the
	#    two paths are instrumented unevenly, because the client's replay calls
	#    `Combat.spawn_floating_number` directly (which bumps the counter on its first
	#    line) while the host's numerals go through `Card2D._spawn_damage_number`, which
	#    returns early when it cannot resolve a VFX host. So it reads ~400% at perfect
	#    parity. The counts are printed below as information; they are not asserted.
	#
	#    What IS assertable, and is the real question, is whether every CLASS of beat
	#    the host raises has a channel to the watcher at all. A missing kind is a whole
	#    category of effect the second player cannot see — which is exactly the shape of
	#    the original complaint, and exactly what each of these keys was added to fix.
	print("[mirror] visible beats — host %d, client %d (instrumented unevenly; not asserted)" % [
		_host_beats, client_beats])
	var kinds := {}
	for e in _reel:
		for k in e.keys():
			kinds[k] = int(kinds.get(k, 0)) + 1
	print("[mirror] reel kinds: %s" % str(kinds))
	var required := {
		"l":   "the attacker's wind-up (and the defender's brace rides it)",
		"d":   "creature strikes",
		"p":   "the blow's weight class — the hitstop and spark are weighed by it",
		"dt":  "who is about to be hit, so the brace can land before contact",
		"fo":  "the spotlight column",
		"dw":  "the per-column dwell",
		"fal": "the corpse-flush marker",
		"cap": "the phase captions",
		"kw":  "keyword chips, in place rather than batched onto the snapshot",
		"led": "the closing casualty ledger",
	}
	var missing: Array[String] = []
	for k in required:
		if not kinds.has(k):
			missing.append("%s (%s)" % [k, required[k]])
	_check(missing.is_empty(),
		"every class of beat the host raises has a channel to the watcher%s" % (
			"" if missing.is_empty() else " — MISSING: " + str(missing)))

	# ── PHASE D — the surfaces either side of the clash ──────────────────
	#
	# Source-inspected: each of these is a one-sided CEREMONY, and the difference
	# between a ceremony playing and not playing is invisible to a state assertion —
	# both ways end with the same board. They are the same failure shape as the client
	# death that hand-rolled `_die`'s fallback: the watcher silently takes the
	# bookkeeping path where the host takes the authored one.
	print("\n[mirror] === PHASE D: the opener, the series, the sealed reveal ===")
	var net_src: String = load("res://scripts/net/CombatNet.gd").source_code

	# THE TOSS. The winner watched the Old King's coin spin over a dimmed board; the
	# loser got one info line and up to ninety seconds of a static board while somebody
	# else decided how the match opens. Both now watch the same coin — literally the
	# same, since CoinProp is seeded off the shared rng_seed.
	var wait_fn := _fn_body(net_src, "_net_show_order_wait")
	_check(wait_fn != "", "the toss LOSER has a ceremony at all (_net_show_order_wait)")
	_check(wait_fn.contains("_net_play_coin_toss"),
		"the loser watches the same coin toss the winner does")
	_check(wait_fn.contains("toss_%d"),
		"and it is the SAME coin — seeded off the shared rng_seed, not a lookalike")
	_check(_fn_body(net_src, "_net_open_skirmish").contains("_net_show_order_wait")
			or net_src.contains("await _net_show_order_wait()"),
		"the toss branch actually calls it")

	# THE SERIES. A game inside a Bo3 was the one fight-ending in the game with no
	# ceremony — a caption swap and a sting, which is what _show_battle_verdict exists
	# to replace. Both peers run this path, so adding it keeps the screens identical.
	var inter := _fn_body(net_src, "_net_show_series_interstitial")
	_check(inter.contains("_show_battle_verdict"),
		"a game inside a series ends on the verdict banner, like every other fight")
	_check(inter.contains("winner_index >= 0"),
		"...and not on a DRAW, which is neither of the two words the banner can say")

	# THE SEALED REVEAL. `_sealed_clear_pending_local`'s own header says the flip
	# "belongs to the REVEAL only" — and the reveal was the one caller that did not
	# pass it, so the watcher's ghosts blinked out where the host's turned edge-on.
	var rev_client := ""
	var ev_at: int = net_src.find("NetMatch.EV_REVEAL:")
	if ev_at >= 0:
		rev_client = net_src.substr(ev_at, 900)
	_check(rev_client.contains("_sealed_clear_pending_local(true)"),
		"the watcher's sealed reveal plays the authored FLIP, not the bookkeeping clear")
	var reveal_fn := _fn_body(net_src, "_sealed_reveal")
	_check(reveal_fn.count("_net_sync_board()") >= 2,
		"the reveal ships each order AS IT LANDS, so the watcher sees them stamp down one at a time")

	# ── PHASE E — THE ANIMATION INVENTORY ────────────────────────────────
	#
	# The standing rule this pass established: a visual anchored on a POSITION cannot
	# cross the wire, because positions describe the host's board and the client's is
	# the mirror. So every net-reachable resolver must raise its beat through a funnel
	# that ships IDENTITY instead — an entity id, or a slot coordinate plus a side.
	#
	# These four resolvers are the tribe keystone signatures named in CLAUDE.md, they
	# all run host-authoritative, and every one of them shipped its CHIP and kept its
	# ANIMATION local. That is the failure mode worth pinning: the watcher read the word
	# (HOLD, VOLLEY, STAMPEDE, ENCORE, REAP) with nothing happening under it, which
	# reads as a quiet beat rather than a missing one and is why it survived two passes.
	print("\n[mirror] === PHASE E: the animation inventory ===")
	var combat_src2: String = load("res://scripts/scenes/Combat.gd").source_code
	for fn_name in ["ring_over", "grace_wave_over", "wisp_between_slots"]:
		var f := _fn_body(combat_src2, fn_name)
		_check(f != "" and f.contains("_net_queue_fx_chip"),
			"Combat.%s ships its beat as identity, not as screen position" % fn_name)
	for pair in [["_maybe_stampede", "the Dire Alpha's charge"],
			["_maybe_beast_encore", "the Alpha's howl"],
			["_apply_ally_death_passives", "the Gravepact reap wisp"]]:
		var body := _fn_body(combat_src2, String(pair[0]))
		var direct: bool = body.contains("_trigger_fx_ring(") \
			or body.contains("_spawn_vfx_streak(")
		_check(body != "" and not direct,
			"%s crosses to the watcher (%s)" % [pair[1], pair[0]])
	# THE RESULT MUST NOT OUTRUN ITS CAUSE. `_net_host_check_match_over` is reached
	# SYNCHRONOUSLY from damage_enemy_hero -> _check_game_over, i.e. mid-clash, while the
	# reel holding the killing blow is still unsent (it ships when the clash ends). So
	# the watcher used to get EV_MATCH_OVER first, show the verdict over a settled board,
	# and only then replay the fight that produced it. Flushing the reel first lets the
	# client's own backlog hold the verdict behind the replay.
	#
	# Matched on the CALL, not the word: the rationale comment above the fix names
	# EV_MATCH_OVER in prose, and the first cut of this check found that instead and
	# failed. Same trap `_probe_net_client_replay` records for `_play_burn_death`.
	var over_fn := _fn_body(net_src, "_net_host_check_match_over")
	var flush_at: int = over_fn.find("_net_send_clash_log()")
	var send_at: int = over_fn.find('send_to_client({"t": NetMatch.EV_MATCH_OVER')
	_check(flush_at >= 0 and send_at >= 0 and flush_at < send_at,
		"the clash reel is shipped BEFORE the verdict — the result cannot outrun its cause")

	# ONE ROUTER, OR THE FIX IS PARTIAL. `_net_queue_fx_chip` is what decides whether a
	# beat rides the reel (in place, mid-clash) or the fx queue (with the trailing
	# snapshot). Anything appending to `_net_fx_queue` directly opts out of that choice
	# and lands in the post-clash batch — which is the bug, not the fix. The ONE
	# sanctioned exception is `_play_trigger_fx`'s `{trig}` entry: the client replays it
	# in two passes split around the board reconcile (death before the despawn loop,
	# enter/play after), and that anchoring contract is the snapshot's, not the reel's.
	var direct_writes: Array[String] = []
	for pair in [["Combat.gd", combat_src2], ["CombatNet.gd", net_src]]:
		var src: String = String(pair[1])
		var at: int = 0
		while true:
			at = src.find("_net_fx_queue.append", at)
			if at < 0:
				break
			var line_start: int = src.rfind("\n", at) + 1
			var seg: String = src.substr(line_start, 240).strip_edges()
			# Two sanctioned writes: the `{trig}` entry (above) and the ROUTER'S OWN
			# else-branch, which is the queue arm it exists to choose.
			if not seg.contains("\"trig\"") and not seg.begins_with("combat._net_fx_queue.append(entry)"):
				direct_writes.append("%s @%d" % [String(pair[0]), at])
			at += 1
	_check(direct_writes.is_empty(),
		"every mirrored beat goes through the ONE router (stray direct queue writes: %s)"
			% str(direct_writes))

	# And the receiving half knows all three entry kinds.
	var chip_fn := _fn_body(net_src, "_net_render_fx_chip")
	for kind in ["ring", "wisp", "wave"]:
		_check(chip_fn.contains('fx.has("%s")' % kind),
			"the watcher's chip renderer handles a {%s} entry" % kind)

	if _fails == 0:
		print("\n[mirror] ALL PASS — the two screens agree")
	else:
		print("\n[mirror] %d FAILURES" % _fails)
	_finish(1 if _fails > 0 else 0)


## Slice one function out of a script's source. Both markers are "\nfunc " so a local
## lambda or a nested string cannot end the slice early.
func _fn_body(src: String, fn_name: String) -> String:
	var head: int = src.find("func %s(" % fn_name)
	if head < 0:
		return ""
	var tail: int = src.find("\nfunc ", head + 1)
	return src.substr(head, (tail - head) if tail > head else -1)
