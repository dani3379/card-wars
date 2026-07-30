extends Node
## _probe_presentation_audit.gd — the other three blind changes of 2026-07-29.
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_probe_presentation_audit.tscn
##
## Three changes shipped without anyone looking at them. Each gets a measurement
## whose failure mode is stated up front, so "it moved" cannot be mistaken for
## "it is right".
##
## A. THE MORTAL SLUMP  (`Card2D._mark_mortally_struck`, deepened to
##    `0.30,0.27,0.26` @ 0.78 alpha, was `0.42,0.38,0.36` @ 1.0).
##    The stated intent is that a spent body RECEDES from the living line while
##    remaining present — it still owes retaliation, so reading as "removed"
##    would be a lie. The honest test therefore needs THREE populations in one
##    frame, not two: a LIVING card, a SLUMPED corpse, and an EMPTY SLOT. The
##    failure is not "the corpse is dark", it is "the corpse is closer to the
##    empty slot than to the living card". That is reported as a position on the
##    living->empty axis, so the verdict is a number and not an adjective.
##
## B. THE PHASE CAPTION  (`_spawn_phase_pulse`, vp.y*0.245 -> vp.y*0.455).
##    It used to be drawn across the enemy back row. Confirm it no longer covers
##    a card — and check the new home, which is the clash seam where the two
##    lines meet and where floating numbers and keyword chips rise out of both
##    front rows. Measured live during a real clash: the caption's rect against
##    every card rect and against every HUD float/chip that exists while it is on
##    screen.
##
## C. THE FACE-DAMAGE WASH  (`clamp(0.18 + dmg*0.045, 0.20, 0.42)` ->
##    `clamp(0.07 + dmg*0.038, 0.09, 0.38)`, decay 0.34 s -> 0.19 s).
##    Two opposite failures: a 1-damage hit that no longer registers at all
##    (it is real damage and must be visible), and a big hit that no longer
##    lands. Board redness is sampled every frame from the flash call, so both
##    the peak and the time-above-threshold are measured, for 1 / 3 / 8 / 14.
##
## House traps paid: current_scene assigned, input off, cursor parked, tutorials
## marked seen, round 2 reached by polling.

const STATE_TIMEOUT := 90.0
const POLL := 0.2
const SHOT_DIR := "res://tools/screenshot/presentation"
const ENC := "oathbroken_knights"

var _combat: Node = null
var _fail := 0
# caption watch
var _watch_caption := false
var _cap_t0 := 0
var _cap_rows: Array[Dictionary] = []


func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(func():
		print("[pa] WATCHDOG"); get_tree().quit(1))
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.clash_dwell_scale = 1.0
	UserSettings.particles = true
	UserSettings.screen_shake = true
	UserSettings.end_turn_warning = false
	for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
			"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
			"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
			"mark_sacrifice_tutorial_seen"]:
		if UserSettings.has_method(m):
			UserSettings.call(m)

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = 1
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame
	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	Input.warp_mouse(Vector2(4, 4))
	await get_tree().process_frame
	get_viewport().gui_disable_input = true

	if not await _await_state(1, false):
		return
	_combat.call("_on_end_turn")
	if not await _await_state(2, true):
		return
	await get_tree().create_timer(2.4).timeout

	await _test_c_face_wash()
	await _test_a_slump()
	await _test_b_caption()

	print("")
	print("[pa] %s" % ("ALL PASS" if _fail == 0 else "%d FINDING(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


# ── C. face-damage wash ────────────────────────────────────────────────────

func _test_c_face_wash() -> void:
	print("")
	print("[pa] ===== C. FACE-DAMAGE WASH =====")
	# Sample a wide band across the BOARD (not the HUD corners, which carry their
	# own red plaques). Redness = R - (G+B)/2, which isolates the crimson wash from
	# a general brightness change; the table is already warm, so plain luminance
	# would count the lamplight as flash.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# TWO BANDS, because `_play_face_damage_flash` draws TWO overlays and only ONE
	# of them was retuned:
	#   WASH   — full-screen ColorRect, alpha clamp(0.07 + dmg*0.038, 0.09, 0.38),
	#            decay 0.19 s.  <-- this is the layer the 2026-07-29 change edited.
	#   BORDER — a Panel whose StyleBox border is clamp(70 + dmg*12, 80, 180) px
	#            thick at alpha clamp(0.45 + dmg*0.04, 0.45, 0.85), decay 0.40 s.
	#            UNTOUCHED by the retune.
	# The border can be up to 180 px thick, so a CENTRE band (inset 200 px on every
	# side) sees only the wash, and an EDGE band sees the border. Measuring one
	# band across the whole board — which is what a first pass does — reports the
	# border's numbers and credits them to the wash.
	var centre := Rect2(vp.x * 0.26, vp.y * 0.26, vp.x * 0.48, vp.y * 0.46)
	var edge := Rect2(vp.x * 0.02, vp.y * 0.40, vp.x * 0.06, vp.y * 0.20)
	var rest_c := _redness(centre)
	var rest_e := _redness(edge)
	print("[pa] centre band %s  resting redness %.2f" % [str(centre), rest_c])
	print("[pa] edge   band %s  resting redness %.2f" % [str(edge), rest_e])
	print("[pa]        |------------- WASH (retuned) -------------|--- BORDER (untouched) ---|")
	print("[pa]  dmg   | peak  amp  t_peak  vis_ms  printed_alpha | peak   amp   vis_ms")
	var results := {}
	for dmg in [1, 3, 8, 14]:
		var series: Array[Dictionary] = []
		_combat.call("_play_face_damage_flash", dmg)
		# Name every overlay this call actually put on screen, with its real rect
		# and alpha. Inferring the layer split from pixels alone was wrong once
		# already (a first pass credited the border's numbers to the wash), and a
		# full-screen red rect is exactly the kind of thing another system can add
		# without the caller knowing.
		var hud = _combat.get("_hud_layer")
		if hud != null and is_instance_valid(hud):
			for ch in hud.get_children():
				if ch is Control and int((ch as Control).z_index) >= 230:
					var cr := ch as Control
					var col := "-"
					if cr is ColorRect:
						col = str((cr as ColorRect).color).replace(" ", "")
					print("[pa]    overlay dmg=%d: %-10s z=%d rect=%s mod_a=%.2f color=%s" % [
						dmg, cr.get_class(), int(cr.z_index),
						str(cr.get_global_rect()).replace(" ", ""),
						cr.modulate.a, col])
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 900:
			await RenderingServer.frame_post_draw
			series.append({"ms": Time.get_ticks_msec() - t0,
				"c": _redness(centre), "e": _redness(edge)})
		var pc := rest_c
		var pe := rest_e
		var tpc := 0
		for s in series:
			if float(s["c"]) > pc:
				pc = float(s["c"])
				tpc = int(s["ms"])
			pe = maxf(pe, float(s["e"]))
		var vis_c := 0
		var vis_e := 0
		for s in series:
			if float(s["c"]) - rest_c >= 1.0:
				vis_c = int(s["ms"])
			if float(s["e"]) - rest_e >= 1.0:
				vis_e = int(s["ms"])
		var printed: float = clampf(0.07 + float(dmg) * 0.038, 0.09, 0.38)
		results[dmg] = {"amp": pc - rest_c, "vis": vis_c,
			"bamp": pe - rest_e, "bvis": vis_e}
		print("[pa]  %3d   | %5.1f %5.1f %5d ms %6d ms  %.3f        | %5.1f %5.1f %6d ms" % [
			dmg, pc, pc - rest_c, tpc, vis_c, printed, pe, pe - rest_e, vis_e])
		await get_tree().create_timer(1.0).timeout
	var a1: float = float(results[1]["amp"])
	var a8: float = float(results[8]["amp"])
	var a14: float = float(results[14]["amp"])
	print("[pa] WASH scaling  1->8 = %.2fx, 1->14 = %.2fx   (printed alpha ratio 0.108->0.374 = 3.46x)" % [
		a8 / maxf(a1, 0.01), a14 / maxf(a1, 0.01)])
	print("[pa] BORDER scaling 1->8 = %.2fx   (printed alpha 0.49->0.77 = 1.57x, width 82->166 px)" % [
		float(results[8]["bamp"]) / maxf(float(results[1]["bamp"]), 0.01)])
	# A 1-damage hit is REAL DAMAGE. If its wash cannot be told from the resting
	# board it has stopped being punctuation and become nothing.
	if a1 < 1.5:
		print("[pa] FINDING — a 1-damage WASH peaks only %.2f over rest: below a visible step." % a1)
		_fail += 1
	else:
		print("[pa] pass — a 1-damage wash is still measurably above the resting board (%.2f)." % a1)
	if a8 < 8.0:
		print("[pa] FINDING — an 8-damage WASH peaks only %.2f over rest: no longer lands." % a8)
		_fail += 1
	else:
		print("[pa] pass — an 8-damage wash still lands hard (%.2f over rest)." % a8)
	# The retune's stated goal was a decay short enough to fuse with the blow
	# instead of sitting across the next one. The wash's own 0.19 s achieves that;
	# whether the PLAYER gets it depends on the border beside it, which still fades
	# over 0.40 s and is the brighter of the two.
	print("[pa] visible-duration check — wash vs the border that shares its beat:")
	for dmg in [1, 8, 14]:
		print("[pa]   dmg %2d  wash %3d ms | border %3d ms  %s" % [
			dmg, int(results[dmg]["vis"]), int(results[dmg]["bvis"]),
			"<== the border outlasts the wash, so the retune's decay is not what is seen"
				if int(results[dmg]["bvis"]) > int(results[dmg]["vis"]) + 40 else ""])
	if int(results[8]["bvis"]) > int(results[8]["vis"]) + 40:
		print("[pa] FINDING — the wash was retuned but the border frame beside it was not:")
		print("[pa]           it is brighter, wider with damage, and fades over 0.40 s vs the wash's 0.19 s.")
		_fail += 1


func _redness(rect: Rect2) -> float:
	var img: Image = get_viewport().get_texture().get_image()
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = float(img.get_width()) / maxf(vis.x, 1.0)
	var x0 := clampi(int(rect.position.x * ratio), 0, img.get_width() - 1)
	var y0 := clampi(int(rect.position.y * ratio), 0, img.get_height() - 1)
	var x1 := clampi(int(rect.end.x * ratio), x0 + 1, img.get_width())
	var y1 := clampi(int(rect.end.y * ratio), y0 + 1, img.get_height())
	var s := 0.0
	var n := 0
	for y in range(y0, y1, 6):
		for x in range(x0, x1, 6):
			var c := img.get_pixel(x, y)
			s += (c.r - (c.g + c.b) * 0.5) * 255.0
			n += 1
	return s / maxi(n, 1)


# ── A. the mortal slump ────────────────────────────────────────────────────

func _test_a_slump() -> void:
	print("")
	print("[pa] ===== A. THE MORTAL SLUMP =====")
	# Stage one frame holding all three populations at once: living bodies,
	# mortally-struck bodies held by defer_deaths, and empty slots.
	var names := ["Pikeman", "Outrider", "Mourner", "Palisade"]
	for lane in range(4):
		var p = _cell(false, 0, lane)
		if p == null:
			_combat.call("summon_token", 3, 6, lane, false, 0, {}, names[lane], [])
			p = _cell(false, 0, lane)
		_force(p, 3, 6)
		var e = _cell(true, 0, lane)
		if e == null:
			_combat.call("_place_enemy_card", EncounterDB.make_card_data(
				{"name": "Squire", "atk": 3, "hp": 6, "kw": []}), lane, 0, false)
			e = _cell(true, 0, lane)
		_force(e, 3, 6)
	# Clear the back rows so there are genuine EMPTY slots in the same frame.
	await get_tree().create_timer(0.8).timeout

	# Kill lanes 1 and 3 the way the clash does: defer_deaths on, hp to 0, mark.
	var was: bool = Card2D.defer_deaths
	Card2D.defer_deaths = true
	for lane in [1, 3]:
		for is_enemy in [true, false]:
			var c = _cell(is_enemy, 0, lane)
			if c == null:
				continue
			c.current_hp = 0
			c.call("update_stat_display")
			c.call("_mark_mortally_struck")
	await get_tree().create_timer(0.7).timeout
	await _shoot("slump_mixed")

	var img: Image = get_viewport().get_texture().get_image()
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = float(img.get_width()) / maxf(vis.x, 1.0)
	var live := []
	var dead := []
	for lane in range(4):
		for is_enemy in [true, false]:
			var c = _cell(is_enemy, 0, lane)
			if c == null:
				continue
			var r: Rect2 = c.get_global_rect().grow(-c.get_global_rect().size.x * 0.20)
			var m := _mean(img, r, ratio)
			if lane in [1, 3]:
				dead.append(m)
			else:
				live.append(m)
			print("[pa]   lane %d %-3s %-9s hp=%d  mean lum %6.2f  modulate=%s" % [
				lane, "FOE" if is_enemy else "YOU",
				String(c.card_data.get("name", "?")).substr(0, 9),
				int(c.current_hp), m, str(c.modulate).replace(" ", "")])
	# Empty slots: the back rows, sampled at the same geometry as a card would be.
	var empty := []
	for lane in range(4):
		var ref = _cell(false, 0, lane)
		if ref == null:
			continue
		var rr: Rect2 = ref.get_global_rect()
		# One row DOWN from the player's front row = the empty back-row slot.
		var slot := Rect2(rr.position + Vector2(0.0, rr.size.y * 1.28), rr.size)
		empty.append(_mean(img, slot.grow(-rr.size.x * 0.20), ratio))
	var l := _avg(live)
	var d := _avg(dead)
	var e := _avg(empty)
	print("[pa]   LIVING card      mean lum %6.2f  (n=%d)" % [l, live.size()])
	print("[pa]   SLUMPED corpse   mean lum %6.2f  (n=%d)" % [d, dead.size()])
	print("[pa]   EMPTY slot       mean lum %6.2f  (n=%d)" % [e, empty.size()])
	var span: float = l - e
	# 0.0 = indistinguishable from a living card; 1.0 = indistinguishable from
	# bare table. The design intent ("recedes but is present") wants the corpse
	# nearer the middle than either end.
	var pos: float = (l - d) / maxf(span, 0.01)
	print("[pa]   corpse sits %.0f%% of the way from LIVING to EMPTY" % (pos * 100.0))
	print("[pa]   living->corpse step %.2f | corpse->empty step %.2f" % [l - d, d - e])
	if pos >= 0.80:
		print("[pa] FINDING — the corpse reads as REMOVED: it is within %.0f%% of bare table, but it is still on the board and still owes retaliation." % ((1.0 - pos) * 100.0))
		_fail += 1
	elif pos <= 0.25:
		print("[pa] FINDING — the corpse barely recedes (%.0f%%); it still reads as part of the living line." % (pos * 100.0))
		_fail += 1
	else:
		print("[pa] pass — the corpse is separated from BOTH the living line and bare table.")

	# ── the sweep ──────────────────────────────────────────────────────────
	# A verdict of "too dark" is only half an answer; the other half is a number.
	# Drive the same four corpses through candidate modulates and measure each, so
	# whatever is chosen has been seen rather than reasoned about. The target band
	# is stated in advance: land BETWEEN the empty slot and the living line, i.e.
	# strictly brighter than bare table (or the corpse reads as a hole in the
	# board) and clearly below the living cards (or it does not recede at all).
	print("[pa]   --- candidate sweep (target: above EMPTY %.1f, below LIVING %.1f) ---" % [e, l])
	print("[pa]   modulate                       | corpse lum | vs empty | pos on living->empty")
	var cands := [
		Color(0.30, 0.27, 0.26, 0.78),   # SHIPPED 2026-07-29
		Color(0.42, 0.38, 0.36, 1.00),   # the value it replaced
		Color(0.50, 0.46, 0.44, 1.00),
		Color(0.58, 0.54, 0.52, 1.00),
		Color(0.66, 0.62, 0.60, 1.00),
		Color(0.62, 0.58, 0.56, 0.92),
		Color(0.74, 0.70, 0.68, 1.00),
	]
	for cand in cands:
		for lane in [1, 3]:
			for ie in [true, false]:
				var cc = _cell(ie, 0, lane)
				if cc != null:
					cc.modulate = cand
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var im: Image = get_viewport().get_texture().get_image()
		var vals := []
		for lane in [1, 3]:
			for ie in [true, false]:
				var cc = _cell(ie, 0, lane)
				if cc == null:
					continue
				var rc: Rect2 = cc.get_global_rect()
				vals.append(_mean(im, rc.grow(-rc.size.x * 0.20), ratio))
		var m := _avg(vals)
		var p: float = (l - m) / maxf(span, 0.01)
		var verdict := "reads as a HOLE (darker than bare table)" if m < e \
			else ("too close to LIVING" if p < 0.30 else "in band")
		print("[pa]   %-30s | %10.2f | %+8.2f | %5.0f%%  %s" % [
			str(cand).replace(" ", ""), m, m - e, p * 100.0, verdict])
	Card2D.defer_deaths = was


func _mean(img: Image, rect: Rect2, ratio: float) -> float:
	var x0 := clampi(int(rect.position.x * ratio), 0, img.get_width() - 1)
	var y0 := clampi(int(rect.position.y * ratio), 0, img.get_height() - 1)
	var x1 := clampi(int(rect.end.x * ratio), x0 + 1, img.get_width())
	var y1 := clampi(int(rect.end.y * ratio), y0 + 1, img.get_height())
	var s := 0.0
	var n := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			s += img.get_pixel(x, y).get_luminance() * 255.0
			n += 1
	return s / maxi(n, 1)


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


# ── B. the phase caption ───────────────────────────────────────────────────

func _test_b_caption() -> void:
	print("")
	print("[pa] ===== B. THE PHASE CAPTION =====")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var old_rect := Rect2(vp.x * 0.5 - 220.0, vp.y * 0.245, 440.0, 54.0)
	var new_rect := Rect2(vp.x * 0.5 - 220.0, vp.y * 0.455, 440.0, 54.0)
	print("[pa] viewport=%s" % str(vp))
	print("[pa]   OLD (0.245): %s" % str(old_rect))
	print("[pa]   NEW (0.455): %s" % str(new_rect))
	for c in (_combat.call("_all_creatures_both_sides") as Array):
		var r: Rect2 = c.get_global_rect()
		var o := old_rect.intersects(r)
		var n := new_rect.intersects(r)
		if o or n:
			print("[pa]   card %-10s %s  old_overlap=%s new_overlap=%s" % [
				String(c.card_data.get("name", "?")).substr(0, 10),
				str(r).replace(" ", ""), str(o), str(n)])
	# Now the live test: run a clash and watch the caption panel against every
	# HUD float and chip that shares the screen with it.
	_stage_clash()
	await get_tree().create_timer(1.2).timeout
	_cap_rows.clear()
	_cap_t0 = Time.get_ticks_msec()
	_watch_caption = true
	set_process(true)
	_combat.call("_on_end_turn")
	await _await_state(3, false)
	await get_tree().create_timer(1.5).timeout
	_watch_caption = false
	set_process(false)
	var frames_with_panel := 0
	var worst_card := 0
	var worst_float := 0
	var collisions: Array[String] = []
	for r in _cap_rows:
		if not bool(r["panel"]):
			continue
		frames_with_panel += 1
		worst_card = maxi(worst_card, int(r["cards"]))
		worst_float = maxi(worst_float, int(r["floats"]))
		if int(r["cards"]) > 0 or int(r["floats"]) > 0:
			collisions.append("%5d ms cap='%s' cards=%d floats/chips=%d  %s" % [
				int(r["ms"]), String(r["cap"]), int(r["cards"]), int(r["floats"]),
				String(r["who"])])
	print("[pa] caption on screen for %d sampled frames" % frames_with_panel)
	print("[pa] worst simultaneous overlaps: cards=%d  floats/chips=%d" % [
		worst_card, worst_float])
	for c in collisions.slice(0, 24):
		print("[pa]   COLLIDE ", c)
	if worst_card > 0:
		print("[pa] FINDING — the caption panel still covers %d card(s) at its new home." % worst_card)
		_fail += 1
	else:
		print("[pa] pass — the caption no longer overlaps any card.")
	if worst_float > 0:
		print("[pa] FINDING — the caption collides with %d floating number(s)/chip(s) rising from the front rows." % worst_float)
		_fail += 1
	else:
		print("[pa] pass — no float/chip collision observed at the seam.")


func _process(_dt: float) -> void:
	if not _watch_caption or _combat == null or not is_instance_valid(_combat):
		return
	var p = _combat.get("_phase_pulse_node")
	var row := {"ms": Time.get_ticks_msec() - _cap_t0, "panel": false,
		"cards": 0, "floats": 0, "cap": String(_combat.get("_phase_caption")),
		"who": ""}
	if p != null and is_instance_valid(p) and (p as Control).visible \
			and (p as Control).modulate.a > 0.05:
		row["panel"] = true
		var pr: Rect2 = (p as Control).get_global_rect()
		var who: Array[String] = []
		for c in (_combat.call("_all_creatures_both_sides") as Array):
			if pr.intersects(c.get_global_rect()):
				row["cards"] = int(row["cards"]) + 1
				who.append("card:" + String(c.card_data.get("name", "?")).substr(0, 8))
		var hud = _combat.get("_hud_layer")
		if hud != null and is_instance_valid(hud):
			for ch in hud.get_children():
				if not (ch is Control):
					continue
				var z := int((ch as Control).z_index)
				if z != 200 and z != 210:
					continue
				if (ch as Control).modulate.a <= 0.05:
					continue
				if pr.intersects((ch as Control).get_global_rect()):
					row["floats"] = int(row["floats"]) + 1
					who.append("fx:" + String((ch as Control).name).substr(0, 10))
		row["who"] = ", ".join(who)
	_cap_rows.append(row)


func _stage_clash() -> void:
	var ef := [[3, 3], [2, 8], [2, 3], [4, 4]]
	var pf := [[7, 2], [2, 9], [6, 4], [5, 5]]
	for lane in range(4):
		var e = _cell(true, 0, lane)
		if e == null:
			_combat.call("_place_enemy_card", EncounterDB.make_card_data(
				{"name": "Footman", "atk": ef[lane][0], "hp": ef[lane][1], "kw": []}),
				lane, 0, false)
			e = _cell(true, 0, lane)
		_force(e, ef[lane][0], ef[lane][1])
		var p = _cell(false, 0, lane)
		if p == null:
			_combat.call("summon_token", pf[lane][0], pf[lane][1], lane, false, 0,
				{}, "Pikeman", [])
			p = _cell(false, 0, lane)
		_force(p, pf[lane][0], pf[lane][1])
	for c in (_combat.call("_all_creatures_both_sides") as Array):
		c.state.ready_to_swing = true
		c.has_attacked_this_turn = false
		if c.is_opponent:
			c.state.current_intent = "ATK"
			_combat.call("_update_intent_display", c, "ATK")
	_combat.call("_refresh_adjacency_buffs")
	_combat.call("_update_hud")


# ── plumbing ───────────────────────────────────────────────────────────────

func _cell(is_enemy: bool, row: int, lane: int):
	var c = (_combat.call("_row_array", is_enemy, row))[lane]
	return c if (c != null and is_instance_valid(c)) else null


func _force(card, atk: int, hp: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	for kw in ["last_stand", "regenerate"]:
		if card.card_data.get("keywords", []).has(kw):
			card.card_data["keywords"].erase(kw)
	card.card_data.erase("adj_buff")
	card.card_data["atk"] = atk
	card.card_data["hp"] = hp
	card.current_atk = atk
	card.current_hp = hp
	card.state.temp_atk_buff = 0
	card.state.persistent_atk_buff = 0
	card.state.adjacency_atk_buff = 0
	card.call("update_stat_display")


func _shoot(tag: String) -> void:
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
	print("[pa] SAVED %s.png" % tag)


func _await_state(min_round: int, want_enemies: bool) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if int(_combat.get("round_number")) >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[pa] ABORT — timed out waiting for round ", min_round)
	get_tree().quit(1)
	return false
