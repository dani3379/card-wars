extends Node
## _probe_clash_trace.gd — THE CLASH, MEASURED (2026-07-28).
##
## `--combat_trace` (Combat._trace) stamps the OPENING only: 16 call sites, all
## inside _ready / _build_hud, the last of which is "round 1 started". Nothing
## in the clash is instrumented. This probe fills that hole from OUTSIDE Combat:
## it boots the real combat scene, stands a busy board on both sides, ends the
## turn, and samples the LIVE SCENE TREE every frame, stamping monotonic
## Time.get_ticks_msec() against every beat a player could actually see:
##
##   LUNGE    a Card2D's _lunge_tween goes live (the swing starts)
##   FLOAT    a floating combat number is parented to the HUD layer (its text
##            is recorded verbatim, and its LIFETIME is measured to its free)
##   HP       a creature's current_hp changes (the damage actually applied)
##   DEATH    a creature leaves the board arrays
##   CAPTION  _phase_label.text changes (SWIFT STRIKES / CLASH / THE FALLEN)
##   PULSE    the center-screen sub-phase title punch spawns
##   STATUS   a Card2D status-rail signature changes
##   SHAKE    GameTheme's trauma reservoir gets an impulse
##   LOG      a new battle-log row (Combat's own _log_event funnel)
##   FRAME    inserted implicitly — every event carries the frame it landed on
##
## NO GAMEPLAY CODE IS MODIFIED. Everything above is read from public-by-
## convention members on Combat / Card2D / GameTheme.
##
## Run WINDOWED (never --headless: floating numbers, tweens and the render loop
## are the whole point):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_probe_clash_trace.tscn -- --mode=trace
##
## Modes:
##   trace   (default) pure observation — no screenshot stalls
##   shots   same clash, but grab a PNG every ~100 ms through the resolution.
##           Screenshots STALL the frame, so the gap table from this mode is
##           NOT comparable with --mode=trace. Read timings from trace only.
##
## Extra args:  --shotdir=<abs dir>   where mode=shots writes its PNGs
##
## HOUSE TRAP THIS PROBE HAD TO FIX: Card2D._combat_vfx_target() resolves the
## VFX host via get_tree().current_scene.has_method("spawn_floating_number").
## Every existing harness does root.add_child(combat) and leaves current_scene
## pointing at the harness — so damage numbers NEVER SPAWNED in _shot_battle_log
## or _shot_creature_fx. This probe assigns get_tree().current_scene = combat.

const HERO := "raider"
const ENC := "act1_fight1"
const RUN_SEED := 90210

var _combat: Node = null
var _t0: int = 0
var _frame: int = 0
var _armed := false
var _events: Array = []          # {t, frame, kind, who, text}

# ── per-frame observer memory ────────────────────────────────────────────
var _seen_lunge := {}            # card instance id -> bool (tween running)
var _seen_hp := {}               # card instance id -> int
var _seen_status := {}           # card instance id -> String
var _known_cards := {}           # card instance id -> name
var _float_nodes := {}           # label instance id -> {t, text}
var _last_caption := ""
var _last_log_rows := 0
var _last_trauma := 0.0
var _last_pulse_id := 0
var _last_frame_us := 0
var _max_gap := 0.0
var _gaps: Array = []


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with(prefix):
			return String(a).substr(prefix.length())
	return fallback


func _mode() -> String:
	return _arg("--mode=", "trace")


func _stamp(kind: String, who: String, text: String = "") -> void:
	_events.append({
		"t": Time.get_ticks_msec() - _t0,
		"frame": _frame,
		"kind": kind,
		"who": who,
		"text": text,
	})


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		print("[clash] WATCHDOG — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# The measurement must be of the SHIPPING feel, not this machine's saved
	# accessibility settings (known trap: reduce_motion is ON in the local save).
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true
	UserSettings.end_turn_warning = false
	UserSettings.screen_shake = true

	RunState.start_new_run(HERO, 0, RUN_SEED)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# CRITICAL — see the header note. Without this the real damage-number path
	# silently no-ops and the trace would report a clash with no numbers at all.
	get_tree().current_scene = _combat

	if not await _wait_for_player_turn(90.0):
		print("[clash] FAIL — never reached the player's turn")
		get_tree().quit(1)
		return
	print("[clash] player turn reached, round=%d" % int(_combat.round_number))

	# ── ROUND 1 = MUSTER. Stand a line; nobody may swing this round. ──
	_muster_player_line()
	await get_tree().create_timer(0.8).timeout
	_combat.call("_on_end_turn")
	if not await _wait_for_player_turn(90.0, 2):
		print("[clash] FAIL — never reached round 2")
		get_tree().quit(1)
		return
	print("[clash] round 2 reached — both lines are formed up and READY")

	# Top the board up so the clash is BUSY: refill any player gaps, and make
	# sure the enemy front is full so every column has a real trade.
	_muster_player_line()
	_muster_enemy_line()
	await get_tree().create_timer(1.0).timeout
	_report_board()

	# Park the OS cursor off the board before the clash. Without this the shots
	# carry whatever hover state the pointer happened to be sitting in, and it
	# is impossible to tell a live hover from an overlay that failed to clear.
	if _arg("--nowarp", "") == "":
		Input.warp_mouse(Vector2(20, 880))
		await get_tree().create_timer(0.4).timeout

	# ── ARM THE OBSERVER, THEN END THE TURN ───────────────────────────────
	_t0 = Time.get_ticks_msec()
	_last_frame_us = Time.get_ticks_usec()
	_prime_observer()
	_armed = true
	set_process(true)
	_stamp("BEGIN", "-", "end turn pressed")
	_combat.call("_on_end_turn")

	if _mode() == "shots":
		await _shoot_loop()
	else:
		await _wait_for_resolution(40.0)

	_armed = false
	set_process(false)
	_report()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


# ══ BOARD SETUP ═══════════════════════════════════════════════════════════

func _muster_player_line() -> void:
	# Varied stat lines on purpose: lane 0 is a mutual kill, lane 1 a survivor
	# taking chip damage, lane 2 an overkill blow (the 2026-07-28 rule), lane 3
	# a big body that lives. Back row is queue space that still swings.
	#
	# The house pattern (every existing probe) musters the player side with
	# summon_token, whose synthetic id is "token_A_H" — no art alias, so all
	# eight player bodies wear the SAME fallback painting. That is fine for a
	# rules probe and useless for a legibility one, so each token is re-dressed
	# with a real CardDB identity (id + data + rebuild_face) before the clash.
	var spec := [
		{"atk": 4, "hp": 3, "id": "pikeman"},
		{"atk": 2, "hp": 6, "id": "shieldmaiden"},
		{"atk": 7, "hp": 4, "id": "berserker"},
		{"atk": 3, "hp": 7, "id": "royal_guard"},
	]
	for lane in range(4):
		if _combat.call("_row_array", false, 0)[lane] == null:
			var s: Dictionary = spec[lane]
			_combat.call("summon_token", int(s.atk), int(s.hp), lane, false, 0)
			_dress(_combat.call("_row_array", false, 0)[lane], String(s.id))
	for lane in range(4):
		if _combat.call("_row_array", false, 1)[lane] == null:
			_combat.call("summon_token", 2, 2, lane, false, 1)
			_dress(_combat.call("_row_array", false, 1)[lane], "goblin")


## Re-skin a summoned token as a real card WITHOUT changing its statline, so the
## board photographs like a real board. Keeps keywords empty on purpose — this
## probe measures the clash's presentation, not keyword interactions.
func _dress(card: Node, card_id: String) -> void:
	if card == null or not is_instance_valid(card):
		return
	var src: Dictionary = CardDB.get_card_data(card_id)
	if src.is_empty():
		return
	var atk: int = int(card.current_atk)
	var hp: int = int(card.current_hp)
	var d: Dictionary = src.duplicate(true)
	d["atk"] = atk
	d["hp"] = hp
	d["keywords"] = []
	d.erase("on_enter")
	d.erase("on_death")
	d.erase("passive")
	d.erase("adj_buff")
	card.card_id = card_id
	card.card_data = d
	card.current_atk = atk
	card.current_hp = hp
	if card.has_method("rebuild_face"):
		card.rebuild_face()


func _muster_enemy_line() -> void:
	# The enemy side gets real card data through the real arrival path, so it
	# already paints with proper art.
	for lane in range(4):
		if _combat.call("_row_array", true, 0)[lane] == null:
			_combat.call("_place_enemy_card",
				CardDB.get_card_data("brute").duplicate(true), lane, 0)
	for lane in range(4):
		if _combat.call("_row_array", true, 1)[lane] == null:
			_combat.call("_place_enemy_card",
				CardDB.get_card_data("e_archer").duplicate(true), lane, 1)


func _report_board() -> void:
	var n := 0
	for is_enemy in [false, true]:
		for row in [0, 1]:
			var line: Array = []
			for c in _combat.call("_row_array", is_enemy, row):
				if c == null or not is_instance_valid(c):
					line.append("--")
				else:
					n += 1
					line.append("%s %d/%d%s" % [
						String(c.card_data.get("name", "?")),
						int(c.call("effective_atk")), int(c.current_hp),
						"" if c.call("can_attack") else " (MUSTERING)"])
			print("[clash] %-6s row%d: %s" % [
				"ENEMY" if is_enemy else "PLAYER", row, ", ".join(line)])
	print("[clash] bodies on board: %d" % n)


func _wait_for_player_turn(limit: float, want_round: int = 1) -> bool:
	var waited := 0.0
	while waited < limit:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if not is_instance_valid(_combat):
			return false
		# Gate on round_number >= 1: phase == PLAYER_TURN is enum 0, the default,
		# and is therefore TRUE before the fight has actually begun.
		if int(_combat.round_number) >= want_round and int(_combat.phase) == 0:
			return true
	return false


func _wait_for_resolution(limit: float) -> void:
	# Watch the clash out: back to the player's turn (the next round) or over.
	var waited := 0.0
	while waited < limit:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not is_instance_valid(_combat):
			return
		if int(_combat.phase) == 2:   # GAME_OVER
			return
		if int(_combat.round_number) >= 3 and int(_combat.phase) == 0:
			# Let the trailing beats (round banner, refill) land, then stop.
			await get_tree().create_timer(0.6).timeout
			return


# ══ THE OBSERVER ══════════════════════════════════════════════════════════

## Card2D carries NO side flag — Combat tracks the side by which array holds
## the body — so the walk stamps it as it goes.
func _all_board_cards() -> Array:
	var out: Array = []
	for is_enemy in [false, true]:
		for row in [0, 1]:
			for c in _combat.call("_row_array", is_enemy, row):
				if c != null and is_instance_valid(c):
					out.append({"c": c, "enemy": is_enemy, "row": row})
	return out


func _card_tag(c: Node, is_enemy: bool, row: int) -> String:
	return "%s %s L%d%s" % ["FOE" if is_enemy else "YOU",
		String(c.card_data.get("name", "?")),
		int(c.current_lane), "b" if row == 1 else "f"]


func _prime_observer() -> void:
	for rec in _all_board_cards():
		var c: Node = rec.c
		var k: int = c.get_instance_id()
		_known_cards[k] = _card_tag(c, bool(rec.enemy), int(rec.row))
		_seen_hp[k] = int(c.current_hp)
		_seen_lunge[k] = false
		_seen_status[k] = String(c.call("_status_signature"))
	var lst = _combat.get("_battle_log_list")
	_last_log_rows = lst.get_child_count() if lst != null else 0
	var pl = _combat.get("_phase_label")
	_last_caption = String(pl.text) if pl != null else ""
	_last_trauma = float(GameTheme.get("_shake_trauma"))


func _process(_dt: float) -> void:
	if not _armed or not is_instance_valid(_combat):
		return
	_frame += 1
	var now_us := Time.get_ticks_usec()
	var gap := float(now_us - _last_frame_us) / 1000.0
	_last_frame_us = now_us
	_gaps.append(gap)
	_max_gap = maxf(_max_gap, gap)

	# 1. CAPTION
	var pl = _combat.get("_phase_label")
	if pl != null and String(pl.text) != _last_caption:
		_last_caption = String(pl.text)
		_stamp("CAPTION", "hud", "\"%s\"" % _last_caption)

	# 2. PULSE (center-screen sub-phase title)
	var pulse = _combat.get("_phase_pulse_node")
	if pulse != null and is_instance_valid(pulse) and pulse.get_instance_id() != _last_pulse_id:
		_last_pulse_id = pulse.get_instance_id()
		_stamp("PULSE", "center", "\"%s\"" % _last_caption)

	# 3. Board cards — lunge / hp / status / arrival
	var live := {}
	for rec in _all_board_cards():
		var c: Node = rec.c
		var k: int = c.get_instance_id()
		live[k] = true
		var tag := _card_tag(c, bool(rec.enemy), int(rec.row))
		if not _known_cards.has(k):
			_known_cards[k] = tag
			_seen_hp[k] = int(c.current_hp)
			_seen_lunge[k] = false
			_seen_status[k] = String(c.call("_status_signature"))
			_stamp("ARRIVE", tag, "%d/%d" % [int(c.call("effective_atk")), int(c.current_hp)])
			continue
		var tw = c.get("_lunge_tween")
		var running: bool = tw != null and tw.is_valid() and tw.is_running()
		if running and not bool(_seen_lunge.get(k, false)):
			_stamp("LUNGE", tag, "atk %d" % int(c.call("effective_atk")))
		_seen_lunge[k] = running
		var hp := int(c.current_hp)
		if hp != int(_seen_hp.get(k, hp)):
			var d: int = hp - int(_seen_hp[k])
			_stamp("HP", tag, "%s%d  -> %d hp" % ["+" if d > 0 else "", d, hp])
			_seen_hp[k] = hp
		var sig := String(c.call("_status_signature"))
		if sig != String(_seen_status.get(k, sig)):
			_stamp("STATUS", tag, "rail: '%s'" % sig)
			_seen_status[k] = sig
	for k in _known_cards.keys():
		if not live.has(k):
			_stamp("DEATH", String(_known_cards[k]), "left the board")
			_known_cards.erase(k)

	# 4. FLOATING NUMBERS — the only on-screen statement of how much was dealt
	var hud = _combat.get("_hud_layer")
	if hud != null and is_instance_valid(hud):
		var seen_now := {}
		for ch in hud.get_children():
			# spawn_floating_number stamps z_index = 200; every other Label
			# parked on the HUD layer (POTIONS / RELICS / the round banner) is
			# furniture, and counting it as a combat number would be a lie.
			if not (ch is Label) or int(ch.z_index) != 200:
				continue
			var k: int = ch.get_instance_id()
			seen_now[k] = true
			if not _float_nodes.has(k):
				var txt := String(ch.text)
				_float_nodes[k] = {"t": Time.get_ticks_msec() - _t0, "text": txt}
				_stamp("FLOAT", "screen", "\"%s\"  (size %d)" % [
					txt, int(ch.get_theme_font_size("font_size"))])
		for k in _float_nodes.keys():
			if not seen_now.has(k):
				var rec: Dictionary = _float_nodes[k]
				_stamp("FLOAT_GONE", "screen", "\"%s\" lived %d ms" % [
					String(rec.text), (Time.get_ticks_msec() - _t0) - int(rec.t)])
				_float_nodes.erase(k)

	# 5. SHAKE impulses
	var tr := float(GameTheme.get("_shake_trauma"))
	if tr > _last_trauma + 0.02:
		_stamp("SHAKE", "screen", "trauma %.2f -> %.2f" % [_last_trauma, tr])
	_last_trauma = tr

	# 6. BATTLE LOG rows (Combat's own beat funnel)
	var lst = _combat.get("_battle_log_list")
	if lst != null and is_instance_valid(lst):
		var n: int = lst.get_child_count()
		if n > _last_log_rows:
			for i in range(_last_log_rows, n):
				_stamp("LOG", "chronicle", _row_text(lst.get_child(i)))
			_last_log_rows = n


func _row_text(row: Node) -> String:
	var parts: Array = []
	for rt in _find_rich(row):
		var t := String(rt.get_parsed_text()).strip_edges()
		if t != "":
			parts.append(t)
	return " | ".join(parts) if not parts.is_empty() else "<no text>"


func _find_rich(n: Node) -> Array:
	var out: Array = []
	if n is RichTextLabel:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_rich(c))
	return out


# ══ SHOTS ═════════════════════════════════════════════════════════════════

func _shoot_loop() -> void:
	# save_png of a 1920x1080 frame costs ~400 ms, which turned a 100 ms cadence
	# into a 650 ms one. Frames are therefore GRABBED into memory during the
	# clash and written to disk afterwards; only get_image()'s GPU flush stays
	# inside the window. Even so, the readback stalls the loop — the timing
	# numbers in the report belong to --mode=trace, never to this mode.
	var dir := _arg("--shotdir=", "user://clashshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var grabs: Array = []
	var t_start := Time.get_ticks_msec()
	var next_at := 0
	while Time.get_ticks_msec() - t_start < 9000 and grabs.size() < 80:
		if not is_instance_valid(_combat):
			break
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - _t0
		if ms >= next_at:
			grabs.append({"ms": ms, "img": get_viewport().get_texture().get_image()})
			next_at = ms + 100
		if int(_combat.phase) == 0 and int(_combat.round_number) >= 3:
			break
	var i := 0
	for g in grabs:
		var img: Image = g.img
		var p := "%s/clash_%02d_%05dms.png" % [dir, i, int(g.ms)]
		img.save_png(p)
		print("[clash] SHOT %s  %s  nonblack=%s" % [p.get_file(), str(img.get_size()),
			str(_looks_painted(img))])
		i += 1


func _looks_painted(img: Image) -> bool:
	# Guard against the known windowed-GL white/blank capture failure.
	var uniq := {}
	for y in range(0, img.get_height(), 47):
		for x in range(0, img.get_width(), 53):
			uniq[img.get_pixel(x, y).to_rgba32()] = true
	return uniq.size() > 12


# ══ REPORT ════════════════════════════════════════════════════════════════

func _report() -> void:
	print("")
	print("[clash] ============ CLASH EVENT TRACE (t=0 at end-turn) ============")
	print("[clash]   t(ms)   +gap  frm  KIND        WHO                          WHAT")
	var prev := 0
	for e in _events:
		print("[clash] %7d %+6d %4d  %-11s %-28s %s" % [
			int(e.t), int(e.t) - prev, int(e.frame),
			String(e.kind), String(e.who), String(e.text)])
		prev = int(e.t)
	print("[clash] ---------------------------------------------------------------")
	print("[clash] events=%d  span=%d ms  frames=%d  max frame gap=%.1f ms" % [
		_events.size(), (int(_events[-1].t) if not _events.is_empty() else 0),
		_frame, _max_gap])

	# DENSITY — the 500 ms window with the most visible beats in it.
	var visible: Array = []
	for e in _events:
		if String(e.kind) in ["LUNGE", "FLOAT", "HP", "DEATH", "CAPTION", "PULSE",
				"SHAKE", "STATUS", "ARRIVE"]:
			visible.append(e)
	print("[clash] visible (non-LOG) beats: %d" % visible.size())
	var best: Array = []
	for i in range(visible.size()):
		var t0i := int(visible[i].t)
		var win: Array = []
		for j in range(i, visible.size()):
			if int(visible[j].t) - t0i > 500:
				break
			win.append(visible[j])
		best.append({"t": t0i, "n": win.size(), "kinds": win})
	best.sort_custom(func(a, b): return int(a.n) > int(b.n))
	print("[clash] --- THE THREE BUSIEST HALF-SECONDS ---")
	var shown := 0
	var used: Array = []
	for b in best:
		var clash_ok := true
		for u in used:
			if absi(int(b.t) - int(u)) < 500:
				clash_ok = false
		if not clash_ok:
			continue
		used.append(int(b.t))
		var tally := {}
		for e in b.kinds:
			tally[String(e.kind)] = int(tally.get(String(e.kind), 0)) + 1
		print("[clash]   t=%d..%d ms : %d beats  %s" % [int(b.t), int(b.t) + 500,
			int(b.n), str(tally)])
		shown += 1
		if shown >= 3:
			break
	print("[clash] DONE")
