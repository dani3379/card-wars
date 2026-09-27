extends SceneTree
## COLD-ENTRY probe (2026-07-25). Answers the only two questions a player can
## feel when a fight opens cold:
##
##   T1 = ms from scene instantiate until the BOARD IS ON SCREEN (a body exists
##        on EITHER side and has been through a rendered frame), and
##   T2 = ms from scene instantiate until the player CAN ACT (phase ==
##        PLAYER_TURN with a dealt hand).
##
## T1 = -1 IS THE EXPECTED READING SINCE TAKE THE FIELD (2026-07-27), not a probe
## failure. Neither side has a body on the board when a fight opens: the player
## has played nothing yet and the hold does not muster until the END of round 1,
## which is past the measurement window. It counted the ENEMY side only until
## 2026-08-01 (so it could never fire at all); it now counts both, which makes it
## meaningful again for a set-piece with an authored opening — but for an ordinary
## fight, `Tf_furniture_ms` is the metric that answers "is the table set".
##
## It also records the wall-clock gap between every rendered frame across that
## window (and for a few seconds INTO the player's turn), so a "fix" that just
## relocates the stall instead of removing it shows up as a late hitch.
##
## Two cold entries run in ONE process, with CardTextureCache.clear() before
## EACH — so entry #2 is cold in the bake sense but warm in the process sense.
## If #2 is fast, the residual cost is process-level GL/font warmup, not baking.
##
## Run WINDOWED (never --headless — the bake path no-ops under the dummy
## display server and the whole measurement becomes meaningless):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       --script res://tools/_probe_coldentry.gd -- --mode=ab
##
## Modes:
##   ab       (default) two cold entries, full T1/T2 + frame-gap report
##   abandon  one cold entry, freed ~100 ms in, then idles 6 s so any
##            "Resumed function ... on freed object" error lands in stderr
##
## NOTE: probe scripts compile BEFORE autoloads register — never name Card2D /
## CardDB / Combat at compile time here (see _probe_perf.gd::_sample_drag).

const HERO := "pyromancer"
const ENC := "act1_fight1"
const RUN_SEED := 4242
const WATCH_AFTER_PLAYABLE := 3.0   # seconds of play-window frame sampling
const TIMEOUT_SEC := 40.0

var RS: Node
var EDB: Node
var US: Node
var CTC: Node
var SP: Node
var combat: Node
var _started := false
var _done := false
var _lines: Array[String] = []
var _enc_id := ENC


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _mode() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--mode="):
			return String(a).substr(7)
	return "ab"


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	CTC = root.get_node_or_null("CardTextureCache")
	SP = root.get_node_or_null("ScenePreload")
	if RS == null or EDB == null or CTC == null:
		_log("[cold] FATAL autoloads missing")
		_finish()
		return
	if US != null:
		# Honest wall-clock: leave animation timing at 1.0 so T2 includes the
		# real intro hold the player actually sits through. Only the end-turn
		# nag is disabled (it can block the round loop waiting on input).
		US.anim_speed = 1.0
		US.end_turn_warning = false
		var tier := "?"
		if US.has_method("effective_graphics_tier"):
			tier = String(US.effective_graphics_tier())
		_log("[cold] graphics tier=%s anim_speed=%s reduce_motion=%s" % [
			tier, str(US.anim_speed), str(US.get("reduce_motion"))])

	if not EDB.ENCOUNTERS.has(_enc_id):
		for id in EDB.ENCOUNTERS.keys():
			var d: Dictionary = EDB.ENCOUNTERS[id]
			if int(d.get("act", 1)) == 1 and String(d.get("type", "combat")) == "combat":
				_enc_id = String(id)
				break
	_log("[cold] encounter=%s  bake_scale=%d  mode=%s" % [
		_enc_id, CTC.gameplay_bake_scale(), _mode()])

	# Model the REAL entry: the player has already sat on the menu/map, so
	# ScenePreload's scene queue and its one-time card-pipeline prewarm (glyph
	# atlases + first bake-viewport render) have long since finished. Waiting
	# for them here keeps the session-level warmup OUT of the measurement, so
	# what T1/T2 catch is genuinely the fight's own cost.
	#
	# --mode=raw SKIPS that wait, reproducing _probe_perf.gd's conditions: the
	# fight boots while ScenePreload's worker threads are still parsing scenes
	# and decoding multi-MB backgrounds. That is a probe artifact, not a player
	# path (the player always crosses a menu and a map first) — but it is the
	# condition the original "2 second freeze" number was measured under, so it
	# is worth measuring on purpose rather than by accident.
	if _mode() != "raw":
		await _wait_for_preload()
	else:
		_log("[cold] RAW mode: NOT waiting for ScenePreload (queue done=%s, pipeline warmed=%s)" % [
			str(SP == null or bool(SP.is_warmup_complete())),
			str(SP == null or bool(SP.get("_prewarmed")))])

	if _mode() == "abandon":
		await _abandon_test()
		_finish()
		return
	if _mode() == "viamap":
		await _via_map()
		_finish()
		return
	if _mode() == "raw":
		var r := await _cold_entry("COLD RAW (ScenePreload still in flight — _probe_perf's condition)")
		if is_instance_valid(combat):
			combat.queue_free()
		combat = null
		_log("[cold] ================ SUMMARY (raw) ================")
		for k in ["ready_sync_ms", "T1_board_ms", "T2_playable_ms", "max_gap_ms",
				"max_gap_pre_T2_ms", "max_gap_post_T2_ms", "gaps_over_100ms",
				"gaps_over_100ms_post_T2", "gaps_over_250ms", "frames"]:
			_log("[cold] %-24s %10s" % [k, str(r.get(k, "-"))])
		_log("[cold] DONE")
		_finish()
		return

	var a := await _cold_entry("COLD #1 (fresh process, empty texture cache)")
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(1.2).timeout
	var b := await _cold_entry(
		"COLD #2 (SAME process, texture AND art caches cleared)", true)
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null

	_log("[cold] ================ SUMMARY ================")
	_log("[cold] METRIC              COLD#1     COLD#2")
	for k in ["ready_sync_ms", "T0_first_frame_ms", "T0_first_frame_nodes",
			"Tf_furniture_ms", "T1_board_ms", "T1_opaque_ms",
			"T2_playable_ms", "baked_at_T2", "baked_at_end",
			"max_gap_ms", "max_gap_pre_T2_ms", "max_gap_post_T2_ms",
			"gaps_over_100ms", "gaps_over_100ms_post_T2", "frames"]:
		_log("[cold] %-19s %8s   %8s" % [k, str(a.get(k, "-")), str(b.get(k, "-"))])
	_log("[cold] DONE")
	_finish()


func _wait_for_preload() -> void:
	var waited := 0.0
	while waited < 20.0:
		var q_done: bool = SP == null or not SP.has_method("is_warmup_complete") \
			or bool(SP.is_warmup_complete())
		var pre_done: bool = SP == null or bool(SP.get("_prewarmed"))
		if q_done and pre_done:
			break
		await create_timer(0.1).timeout
		waited += 0.1
	# Extra settle so the prewarm's own bakes are fully retired.
	await create_timer(1.0).timeout
	_log("[cold] preload settled after %.1fs (scene queue done=%s, card pipeline warmed=%s, cache=%d)" % [
		waited,
		str(SP == null or bool(SP.is_warmup_complete())),
		str(SP == null or bool(SP.get("_prewarmed"))),
		CTC._cache.size()])


func _arm_run() -> void:
	RS.start_new_run(HERO, 0, RUN_SEED)
	RS.current_encounter_id = _enc_id
	RS.current_node_type = "combat"
	# --deck=N pads the starting 10 up to N DISTINCT draftable cards. The hero
	# starter deck has only 10 unique identities, so it under-states the prebake
	# by 2-3x compared with a real act-2/act-3 deck — and the prebake is exactly
	# the work the fire-and-forget change relocates. Padding tests whether that
	# relocated work stays inside the intro or spills into the player's turn.
	var want := 0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--deck="):
			want = int(String(a).substr(7))
	if want <= RS.deck.size():
		return
	var CDB := root.get_node_or_null("CardDB")
	if CDB == null:
		return
	var added := 0
	for id_v in CDB.CARD_POOL.keys():
		if RS.deck.size() >= want:
			break
		var id := String(id_v)
		if RS.deck.has(id):
			continue
		var card: Dictionary = CDB.CARD_POOL[id]
		var rar := String(card.get("rarity", ""))
		if rar == "enemy" or rar == "":
			continue
		RS.add_card(id)
		added += 1
	_log("[cold] deck padded to %d cards (%d added) for a realistic prebake load"
		% [RS.deck.size(), added])


func _board_count(require_visible: bool) -> int:
	## Both sides — see the T1 note in the header. Reading only the enemy side
	## made T1 permanently -1 once the hold stopped being pre-seated.
	return _side_count(false, require_visible) + _side_count(true, require_visible)


func _side_count(is_enemy: bool, require_visible: bool) -> int:
	if not is_instance_valid(combat):
		return 0
	var n := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(is_enemy, row):
			if c == null or not is_instance_valid(c):
				continue
			if require_visible:
				# "Painted" means more than parented: in the tree, visible, and
				# not still faded out by an entrance tween.
				if not c.is_visible_in_tree():
					continue
				if c.modulate.a < 0.85:
					continue
			n += 1
	return n


func _via_map() -> void:
	# The REAL player path, which neither _probe_perf nor plain cold mode models:
	# open the war chart, let MapView's idle warm run for --click_at ms, then
	# commit to the fight. Combat inherits whatever the warm managed to bake —
	# which is the entire point of the warm. This is the only measurement that
	# can prove a warm change helps the player rather than a probe.
	var click_at := 1500.0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--click_at="):
			click_at = float(String(a).substr(11))
	CTC.clear()
	var CAA = load("res://scripts/data/CardArtAliases.gd")
	if CAA != null and CAA.has_method("clear_runtime_caches"):
		CAA.clear_runtime_caches()
	SP.invalidate_encounter_art_warm_state()
	SP.set("_deck_warm_busy", false)
	_arm_run()

	var map_scene = load("res://scenes/map.tscn")
	var combat_scene = load("res://scenes/combat.tscn")
	await process_frame
	var mv = map_scene.instantiate()
	root.add_child(mv)
	var tm := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - tm) / 1000.0 < click_at:
		await process_frame
	var baked_at_click: int = CTC._cache.size()
	# MapView._ready deliberately CLEARS these on arrival (it is a checkpoint),
	# so re-arm the fight identity at commit time, exactly like visit_node does.
	RS.current_encounter_id = _enc_id
	RS.current_node_type = "combat"
	SP.begin_warm_encounter_art(_enc_id)
	await SP.wait_for_encounter_art(_enc_id)
	mv.free()

	var t0 := Time.get_ticks_usec()
	combat = combat_scene.instantiate()
	root.add_child(combat)
	var t_board := -1
	var t_play := -1
	var prev := t0
	var max_gap := 0.0
	var deadline := t0 + int(TIMEOUT_SEC * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		max_gap = maxf(max_gap, _ms(now - prev))
		prev = now
		if not is_instance_valid(combat):
			break
		if t_board < 0 and _board_count(true) >= 1:
			t_board = now
		if t_play < 0 and combat.phase == combat.Phase.PLAYER_TURN \
				and combat._hand.size() > 0:
			t_play = now
			break
	_log("[cold] VIAMAP click_at=%.0fms | baked at click=%d | T1 board=%.1f ms | T2 playable=%.1f ms | worst stall=%.1f ms" % [
		click_at, baked_at_click, _rel(t_board, t0), _rel(t_play, t0), max_gap])
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null


func _rel(t: int, t0: int) -> float:
	return _ms(t - t0) if t > 0 else -1.0


func _descendants(n: Node) -> int:
	var total := n.get_child_count()
	for c in n.get_children():
		total += _descendants(c)
	return total


func _cold_entry(label: String, deep: bool = false) -> Dictionary:
	# TRULY cold: drop every baked texture (hand + battlefield classes) and
	# never call ScenePreload.warm_run_deck. Only the process-level pipeline
	# warm above is allowed to persist.
	CTC.clear()
	if deep:
		# ...and drop the ART caches too. Without this, a second cold entry in
		# the same process still has every creature painting decoded and pinned,
		# so "the 2nd entry is fast" would be evidence about a resource cache,
		# not about GL/font warmup. Clearing both isolates the process-level part.
		var CAA = load("res://scripts/data/CardArtAliases.gd")
		if CAA != null and CAA.has_method("clear_runtime_caches"):
			CAA.clear_runtime_caches()
		var SPn := root.get_node_or_null("ScenePreload")
		if SPn != null and SPn.has_method("invalidate_encounter_art_warm_state"):
			SPn.invalidate_encounter_art_warm_state()
	_arm_run()
	var scene = load("res://scenes/combat.tscn")
	await process_frame
	await process_frame

	var t0 := Time.get_ticks_usec()
	combat = scene.instantiate()
	var t_inst := Time.get_ticks_usec()
	root.add_child(combat)
	var t_ready := Time.get_ticks_usec()

	var stamps: Array[int] = []
	# Gap accounting starts at t0, NOT at t_ready. A long SYNCHRONOUS block
	# inside add_child() is a frame the player loses just as surely as a slow
	# rendered frame — measuring from t_ready would silently forgive it and
	# make "do more work before the first await" look free.
	var prev := t0
	var t_first_frame := -1
	var first_frame_nodes := -1
	var cache_at_T2 := -1
	var t_furniture := -1
	var t_board := -1
	var t_opaque := -1
	var t_play := -1
	var deadline := t_ready + int(TIMEOUT_SEC * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		stamps.append(now)
		prev = now
		if not is_instance_valid(combat):
			break
		if t_first_frame < 0:
			t_first_frame = now
			first_frame_nodes = _descendants(combat)
		# "Furniture" = the board plate + HUD actually exist on screen. The
		# combat.tscn shell is only a background + a few nodes; _build_board and
		# _build_hud add hundreds. This is the metric that tests the engineer's
		# claim of "shows the set table instead of a blank freeze".
		if t_furniture < 0 and _descendants(combat) >= 150:
			t_furniture = now
		if t_board < 0 and _board_count(false) >= 1:
			t_board = now
		if t_opaque < 0 and _board_count(true) >= 1:
			t_opaque = now
		if t_play < 0 and combat.phase == combat.Phase.PLAYER_TURN \
				and combat._hand.size() > 0:
			t_play = now
			# Was the prebake still running when the player got the board? This
			# is the whole question for the fire-and-forget change: work that
			# has not finished by T2 is work moved INTO the play window.
			cache_at_T2 = CTC._cache.size()
		if t_play > 0 and float(now - t_play) / 1_000_000.0 >= WATCH_AFTER_PLAYABLE:
			break

	var res := {}
	res["ready_sync_ms"] = _ms(t_ready - t_inst)
	res["instantiate_ms"] = _ms(t_inst - t0)
	res["T0_first_frame_ms"] = _ms(t_first_frame - t0) if t_first_frame > 0 else -1.0
	res["T0_first_frame_nodes"] = first_frame_nodes
	res["Tf_furniture_ms"] = _ms(t_furniture - t0) if t_furniture > 0 else -1.0
	res["T1_board_ms"] = _ms(t_board - t0) if t_board > 0 else -1.0
	res["T1_opaque_ms"] = _ms(t_opaque - t0) if t_opaque > 0 else -1.0
	res["T2_playable_ms"] = _ms(t_play - t0) if t_play > 0 else -1.0
	res["baked_at_T2"] = cache_at_T2
	res["baked_at_end"] = CTC._cache.size()
	res["frames"] = stamps.size()

	var max_gap := 0.0
	var max_pre := 0.0
	var max_post := 0.0
	var over100 := 0
	var over100_post := 0
	var over250 := 0
	var worst_at := 0.0
	var p := t0
	var big: Array[String] = []
	for s in stamps:
		var g := _ms(s - p)
		p = s
		if g > max_gap:
			max_gap = g
			worst_at = _ms(s - t0)
		if t_play > 0 and s > t_play:
			max_post = maxf(max_post, g)
			if g > 100.0:
				over100_post += 1
		else:
			max_pre = maxf(max_pre, g)
		if g > 100.0:
			over100 += 1
			if big.size() < 14:
				big.append("%.0f@%.0f" % [g, _ms(s - t0)])
		if g > 250.0:
			over250 += 1
	res["max_gap_ms"] = snappedf(max_gap, 0.1)
	res["max_gap_pre_T2_ms"] = snappedf(max_pre, 0.1)
	res["max_gap_post_T2_ms"] = snappedf(max_post, 0.1)
	res["gaps_over_100ms"] = over100
	res["gaps_over_100ms_post_T2"] = over100_post
	res["gaps_over_250ms"] = over250

	_log("[cold] ---- %s ----" % label)
	_log("[cold]   instantiate=%.1fms  _ready sync (add_child)=%.1fms" % [
		res["instantiate_ms"], res["ready_sync_ms"]])
	_log("[cold]   T0 first rendered frame = %.1f ms  (scene had %d descendant nodes)" % [
		res["T0_first_frame_ms"], first_frame_nodes])
	_log("[cold]   Tf board+HUD furniture  = %.1f ms" % res["Tf_furniture_ms"])
	_log("[cold]   T1 board on screen      = %.1f ms  (opaque: %.1f ms)" % [
		res["T1_board_ms"], res["T1_opaque_ms"]])
	_log("[cold]   T2 player can act       = %.1f ms" % res["T2_playable_ms"])
	_log("[cold]   frames=%d  max gap=%.1fms @%.0fms  (pre-T2 %.1f / post-T2 %.1f)" % [
		res["frames"], max_gap, worst_at, max_pre, max_post])
	_log("[cold]   gaps >100ms: %d total, %d AFTER T2 | >250ms: %d" % [
		over100, over100_post, over250])
	_log("[cold]   big gaps (ms@ms-since-instantiate): %s" % ", ".join(big))
	return res


func _ms(usec: int) -> float:
	return snappedf(float(usec) / 1000.0, 0.1)


func _abandon_test() -> void:
	# Task D: does the un-awaited _prebake_hand_textures coroutine survive its
	# object being freed? Cold-enter, kill the scene ~100 ms in (mid-bake), then
	# sit idle and let stderr collect whatever the engine says about it.
	CTC.clear()
	_arm_run()
	var scene = load("res://scenes/combat.tscn")
	_log("[cold] ABANDON: cold-entering, will free the scene mid-flight")
	combat = scene.instantiate()
	root.add_child(combat)
	var t0 := Time.get_ticks_usec()
	# Free at the HARSHEST possible instant: while CardTextureCache is actually
	# mid-bake (_bake_busy true) AND at least one bake has already landed, i.e.
	# the prebake coroutine is provably in flight and has more work queued.
	# Freeing between bakes would prove nothing.
	var min_cache := 2
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--min_cache="):
			min_cache = int(String(a).substr(12))
	var waited_frames := 0
	while waited_frames < 1200:
		await process_frame
		waited_frames += 1
		if bool(CTC.get("_bake_busy")) and CTC._cache.size() >= min_cache:
			break
	var uniq := 0
	if is_instance_valid(combat):
		var seen := {}
		for e in combat._player_draw_pile:
			seen[e] = true
		uniq = seen.size()
	var cache_at_free: int = CTC._cache.size()
	var busy_at_free: bool = bool(CTC.get("_bake_busy"))
	_log("[cold] ABANDON: draw pile=%d entries, %d unique to bake" % [
		(combat._player_draw_pile.size() if is_instance_valid(combat) else -1), uniq])
	_log("[cold] ABANDON: freeing at %.0fms (cache=%d, _bake_busy=%s)" % [
		_ms(Time.get_ticks_usec() - t0), cache_at_free, str(busy_at_free)])
	combat.free()   # IMMEDIATE free — the harshest version of "player left"
	combat = null
	_log("[cold] ABANDON: freed. idling 6s, watching for orphan-coroutine errors...")
	var t1 := Time.get_ticks_usec()
	var samples: Array[String] = []
	while float(Time.get_ticks_usec() - t1) / 1_000_000.0 < 6.0:
		await create_timer(0.5).timeout
		samples.append("%.1fs:cache=%d,busy=%s,orphans=%d" % [
			float(Time.get_ticks_usec() - t1) / 1_000_000.0,
			CTC._cache.size(), str(CTC.get("_bake_busy")),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	_log("[cold] ABANDON timeline: %s" % " | ".join(samples))
	_log("[cold] ABANDON: final _bake_busy=%s (stuck TRUE would deadlock every future bake)" % [
		str(CTC.get("_bake_busy"))])
	_log("[cold] ABANDON: post-free bake still works? testing...")
	var probe_card: Dictionary = root.get_node("CardDB").get_card_data(
		root.get_node("RunState").deck[0])
	var tex = await CTC.bake(probe_card)
	_log("[cold] ABANDON: bake after abandonment returned %s" % (
		"a texture (OK)" if tex != null else "NULL (BROKEN)"))


func _finish() -> void:
	var f := FileAccess.open("user://_probe_coldentry.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	_done = true
	quit()
