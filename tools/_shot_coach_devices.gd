extends Node
## _shot_coach_devices.gd — EYES on the COACHING LAYER'S DEVICES (2026-09-11).
## Windowed, editor closed:
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_coach_devices.tscn
##
## `_probe_coach_a11y` proves the coach is ALIVE — the mark exists, has area, is
## not at alpha 0, the panel clears the spotlight. Not one of its 660 checks can
## see whether the thing looks like anything. The two questions this answers are
## the owner's: WHERE THE ARROW ENDS (a tip planted in the empty wedge beside a
## rotated card's corner passes every assertion in that file) and HOW IT SHINES
## (a halo clipped on its own quad, a rim that never reaches white, a scrim hole
## that reads as a grey window instead of as a beam — all invisible to state).
##
## THE FIXTURES ARE THE REAL BOARD, not modelled rects. A hand card sits at ~8
## degrees and scale 0.72 in the fan and overlaps its neighbours; that is the
## geometry every claim in TutorialCoach's header is about, and a ColorRect
## stand-in has none of it.
##
## Frames → tools/screenshot/ (`_coach_*`). Each wide frame is followed by a
## nearest-neighbour ZOOM on the device itself, because a 2px rim and a 16px
## standoff are not decidable at 1600x900:
##   walk1 / walk1_zoom       step 1 — card + open slots lit, drag arc, panel
##   walk2 / walk2_zoom       step 2 — the commit button, arrow in from the left
##   walk3 / walk3_zoom       step 3 — the TALL lane column (hardest placement)
##   arrow_fan / *_zoom       an arrow onto a ROTATED hand card, side by side
##   arrow_auto               `from:"auto"` on the same card
##   arrow_edge               a bad `from` at three canvas edges — does it swap?
##   glow_hand / _zoom        the rim on a rotated hand card
##   glow_slot / _zoom        the rim on an empty board slot
##   glow_body                the rim on a battlefield creature
##   reduced_off / reduced_on the same fixture either side of Reduce Motion
##
## READ THEM. A PASS here is a set of files, not a verdict.
##
## It restores `reduce_motion`, `coaching_mode` and the whole seen-ledger on the
## way out — they are the developer's real profile. Run under an isolated APPDATA
## anyway: `mark_lesson_seen` writes to disk.

const OUT_DIR := "res://tools/screenshot"

var _combat: Node = null
var _saved := {}
## A CanvasLayer of deliberately-placed targets for the edge cases the real board
## has no example of (a control 30px from the left edge, one under the top rail).
var _stage: CanvasLayer = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_save_profile()
	UserSettings.reduce_motion = false
	UserSettings.reset_tutorials()
	UserSettings.set_coaching_mode(TutorialDB.COACH_FULL)

	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP (from _shot_combat_hud): Card2D._combat_vfx_target() resolves the
	# VFX host through get_tree().current_scene, so add_child alone silently
	# no-ops every float, chip and log row — and the coach's own marks sit on a
	# layer that only reads right over a live scene.
	get_tree().current_scene = _combat
	# The mouse must be parked OFF the board. A cursor resting on a hand card
	# arms Card2D's hover lift AND its lean driver, so the fixture would be a card
	# mid-tween at a rotation nothing else ever sees.
	Input.warp_mouse(Vector2(1560.0, 20.0))

	await _wait_for_round(1)
	await _shoot_walkthrough()
	await _shoot_devices()
	await _shoot_reduce_motion()

	if is_instance_valid(_stage):
		_stage.queue_free()
	if is_instance_valid(_combat):
		_combat.queue_free()
	await get_tree().process_frame
	_restore_profile()
	print("COACH_DEVICE_SHOTS_DONE")
	get_tree().quit()


# ── The guided walkthrough, driven through its own entry points ────────

func _shoot_walkthrough() -> void:
	# The walkthrough starts itself: `_start_round` defers `_begin_first_battle_
	# tutorial` on round 1. Wait for the STAGE rather than for a clock.
	var ok := await _wait_stage(1)   # PLAY_CREATURE
	print("[coach] step 1 reached: ", ok, " stage=",
		_combat.get("_first_battle_tutorial_stage"))
	await _settle_coach()
	var img := await _shoot("walk1")
	var card: Control = _combat.get("_first_battle_tutorial_card")
	if card != null and is_instance_valid(card):
		_report_marks("step 1")
		_crop(img, "walk1_zoom", TutorialCoach.visual_rect(card).get_center()
			+ Vector2(60.0, -110.0), Vector2(520.0, 380.0), 2.0)

	# Step 2 — play the marked card onto the nearest open slot, exactly the way
	# the step asks the player to.
	var slots: Array[Control] = _combat.get("_player_slots")
	if card != null and is_instance_valid(card) and not slots.is_empty():
		card.global_position = slots[1].get_global_rect().get_center() \
			- card.size * 0.5
		_combat.call("_on_card_played", card)
	await _wait_stage(2)   # END_TURN
	await _settle_coach()
	img = await _shoot("walk2")
	_report_marks("step 2")
	var coach2 = _combat.get("_coach")
	if coach2 != null and is_instance_valid(coach2):
		_crop_arrows(img, "walk2", coach2, 3.0)
	var btn: Control = _combat.get("_end_turn_btn")
	if btn != null and is_instance_valid(btn):
		_crop(img, "walk2_zoom",
			TutorialCoach.visual_rect(btn).get_center() - Vector2(120.0, 0.0),
			Vector2(560.0, 300.0), 2.0)

	# Step 3 — commit, let the hold muster, and catch the TALL lane column. This
	# is the placement case `_place_panel`'s narrowing branch exists for.
	_combat.call("_on_end_turn")
	await _wait_for_round(2)
	await _wait_stage(4)   # READ_BOARD
	await _settle_coach()
	img = await _shoot("walk3")
	_report_marks("step 3")
	var coach = _combat.get("_coach")
	if coach != null and is_instance_valid(coach) and not coach._scrim_holes.is_empty():
		var block: Rect2 = coach._scrim_holes[0]
		for h in coach._scrim_holes:
			block = block.merge(h)
		print("[coach] step 3 column opening %s · panel %s" % [str(block),
			str(Rect2(coach._panel.position, coach._panel.size))
				if coach._panel != null else "<none>"])
		_crop(img, "walk3_zoom", block.get_center(),
			Vector2(maxf(block.size.x + 200.0, 420.0), block.size.y + 60.0), 1.6)

	_combat.call("_finish_first_battle_tutorial")
	await _frames(4)
	await _shoot_tall_column()


## THE HARDEST PLACEMENT IN THE GAME, staged deliberately because the shipping
## step-3 column depends on the hold happening to muster opposite the player: a
## lane opened from the enemy's back row down to yours is ~630px of a 900px
## canvas, which leaves no room above it, none below it, and side gutters
## narrower than the panel's preferred width. That is the case `_place_panel`'s
## narrowing branch exists for, and the case where a wrong answer parks the copy
## across the two creatures the sentence is comparing.
func _shoot_tall_column() -> void:
	var lane := 2
	var column: Array = []
	for arr_name in ["_enemy_back_slots", "_enemy_slots", "_player_slots",
			"_player_back_slots"]:
		var arr: Array = _combat.get(arr_name)
		if arr.size() > lane and is_instance_valid(arr[lane]):
			column.append(arr[lane])
	if column.size() < 4:
		print("[coach] tall column skipped — only %d slots" % column.size())
		return
	var coach = _new_coach()
	coach.focus(column, 0.60)
	for i in column.size():
		coach.mark(column[i], {"color": Color(1.0, 0.58, 0.30, 0.95) if i < 2
			else Color(1.0, 0.86, 0.40, 0.95), "pad": 24.0, "corner": 9.0,
			"spread": 22.0, "rim": 3.0, "delay": 0.08 * float(i)})
	coach.show_panel(TutorialDB.title("walk_lane"), TutorialDB.body("walk_lane"),
		"GOT IT", 3, 3)
	await _settle_panel(coach)
	await _frames(24)
	var img := await _shoot("column_tall")
	var block: Rect2 = coach._scrim_holes[0] if not coach._scrim_holes.is_empty() \
		else Rect2()
	for h in coach._scrim_holes:
		block = block.merge(h)
	var pr := Rect2(coach._panel.position, coach._panel.size) \
		if coach._panel != null and is_instance_valid(coach._panel) else Rect2()
	print("[coach] tall column: opening %s · panel %s · overlaps=%s"
		% [str(block), str(pr), str(pr.intersects(block))])
	_crop(img, "column_tall_zoom", block.get_center() + Vector2(90.0, 0.0),
		Vector2(520.0, 700.0), 1.3)
	coach.dismiss()
	coach.queue_free()
	await _frames(3)


# ── The devices on their own, over the live board ──────────────────────

func _shoot_devices() -> void:
	# An arrow onto a ROTATED hand card is the whole "where do arrows end"
	# question. Two cards, two sides, so the pair can be compared in one frame.
	var hand: Array = _combat.get("_hand")
	var lefty: Control = null
	var righty: Control = null
	for c in hand:
		if c is Control and is_instance_valid(c):
			if lefty == null:
				lefty = c
			righty = c
	if lefty != null and righty != null and lefty != righty:
		var coach = _new_coach()
		coach.point_at(lefty, {"from": "left"})
		coach.point_at(righty, {"from": "right"})
		coach.mark(lefty, {"pad": 18.0, "corner": 10.0, "spread": 15.0, "rim": 3.4})
		await _frames(26)
		var img := await _shoot("arrow_fan")
		_dump_arrow(coach, "arrow_fan")
		_crop_arrows(img, "arrow_fan", coach, 3.0)
		_crop(img, "arrow_fan_zoom",
			TutorialCoach.visual_rect(lefty).get_center() - Vector2(70.0, 30.0),
			Vector2(520.0, 400.0), 2.0)
		coach.queue_free()
		await _frames(2)

		coach = _new_coach()
		coach.point_at(lefty, {"from": "auto"})
		coach.point_at(righty, {"from": "auto"})
		await _frames(26)
		await _shoot("arrow_auto")
		_dump_arrow(coach, "arrow_auto")
		coach.queue_free()
		await _frames(2)

	# THE EDGE CASE THE BOARD HAS NO EXAMPLE OF. Three targets hard against three
	# canvas edges, each asked for the arrow from the side that has no room. If
	# the preference is honoured blindly, these draw off-canvas head-first.
	_stage = CanvasLayer.new()
	_stage.layer = 25
	_combat.add_child(_stage)
	var canvas := get_viewport().get_visible_rect()
	var edges := [
		{"r": Rect2(canvas.position + Vector2(26.0, 300.0), Vector2(96.0, 60.0)),
			"from": "left"},
		{"r": Rect2(canvas.position + Vector2(canvas.size.x * 0.5 - 48.0, 18.0),
			Vector2(96.0, 56.0)), "from": "up"},
		{"r": Rect2(canvas.position + canvas.size - Vector2(126.0, 96.0),
			Vector2(96.0, 60.0)), "from": "right"},
	]
	var probes: Array[Control] = []
	var ecoach = _new_coach()
	for e in edges:
		var t := ColorRect.new()
		t.color = Color(0.30, 0.26, 0.20, 0.92)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.position = (e["r"] as Rect2).position
		t.size = (e["r"] as Rect2).size
		_stage.add_child(t)
		probes.append(t)
	await _frames(2)
	for i in probes.size():
		ecoach.point_at(probes[i], {"from": String(edges[i]["from"])})
	await _frames(26)
	await _shoot("arrow_edge")
	_dump_arrow(ecoach, "arrow_edge")
	ecoach.queue_free()
	await _frames(2)

	# THE RIM, on the three grounds it has to survive: a tilted hand card (lit
	# parchment, overlapping neighbours), an empty slot (dark wood), and a
	# battlefield body (parchment on wood, and the one that idles).
	var slots: Array[Control] = _combat.get("_player_slots")
	var body: Control = null
	for b in _combat.call("_all_player_creatures"):
		if is_instance_valid(b):
			body = b
			break
	if lefty != null:
		var gc = _new_coach()
		gc.focus([lefty], 0.60)
		gc.mark(lefty, {"color": Color(1.0, 0.88, 0.44, 1.0), "pad": 18.0,
			"corner": 10.0, "spread": 15.0, "rim": 3.4})
		await _frames(30)
		var img2 := await _shoot("glow_hand")
		_crop(img2, "glow_hand_zoom",
			TutorialCoach.visual_rect(lefty).get_center(),
			Vector2(360.0, 420.0), 2.0)
		gc.queue_free()
		await _frames(2)
	if not slots.is_empty():
		var sc = _new_coach()
		var empty: Control = slots[slots.size() - 1]
		sc.focus([empty], 0.62)
		sc.mark(empty, {"color": Color(0.98, 0.78, 0.34, 0.92), "pad": 20.0,
			"corner": 8.0, "spread": 15.0, "rim": 2.0})
		await _frames(30)
		var img3 := await _shoot("glow_slot")
		_crop(img3, "glow_slot_zoom",
			TutorialCoach.visual_rect(empty).get_center(),
			Vector2(400.0, 360.0), 2.0)
		sc.queue_free()
		await _frames(2)
	if body != null:
		var bc = _new_coach()
		bc.focus([body], 0.60)
		bc.mark(body, {"color": Color(1.0, 0.86, 0.40, 0.95), "pad": 26.0,
			"corner": 9.0, "spread": 24.0, "rim": 3.0})
		if lefty != null:
			bc.gesture(lefty, body)
		await _frames(30)
		await _shoot("glow_body")
		bc.queue_free()
		await _frames(2)


# ── Reduce Motion: the same fixture, both ways ─────────────────────────

func _shoot_reduce_motion() -> void:
	var hand: Array = _combat.get("_hand")
	var card: Control = null
	for c in hand:
		if c is Control and is_instance_valid(c):
			card = c
			break
	var body: Control = null
	for b in _combat.call("_all_player_creatures"):
		if is_instance_valid(b):
			body = b
			break
	if card == null or body == null:
		print("[coach] reduce-motion frames skipped — no card/body fixture")
		return

	for on in [false, true]:
		UserSettings.reduce_motion = on
		var coach = _new_coach()
		coach.focus([card, body], 0.60)
		coach.mark(card, {"color": Color(1.0, 0.88, 0.44, 1.0), "pad": 18.0,
			"corner": 10.0, "spread": 15.0, "rim": 3.4})
		coach.mark(body, {"color": Color(1.0, 0.84, 0.38, 0.95), "pad": 24.0,
			"corner": 9.0, "spread": 22.0, "rim": 3.0})
		coach.point_at(card, {"from": "auto"})
		coach.gesture(card, body)
		coach.show_panel("PLAY A CREATURE",
			"Drag a creature from your hand onto any open slot on your side of "
			+ "the field. Both rows fight every round.", "", 1, 3,
			{"note": "Settings › Coaching turns this off or plays it again."})
		await _settle_panel(coach)
		await _frames(22)
		await _shoot("reduced_on" if on else "reduced_off")
		coach.dismiss()
		coach.queue_free()
		await _frames(3)
	UserSettings.reduce_motion = false


# ── Plumbing ───────────────────────────────────────────────────────────

func _new_coach():
	var c := TutorialCoach.new()
	c.name = "ShotCoach"
	_combat.add_child(c)
	return c


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _wait_for_round(n: int) -> void:
	for _i in 600:
		if is_instance_valid(_combat) and _combat.round_number >= n \
				and not _combat.get("_hand").is_empty():
			return
		await get_tree().create_timer(0.05).timeout


## Wait for a walkthrough STAGE rather than for a clock: the steps are driven by
## deferred calls and timers whose length is the machine's, not the design's.
func _wait_stage(want: int) -> bool:
	for _i in 400:
		if is_instance_valid(_combat) \
				and int(_combat.get("_first_battle_tutorial_stage")) == want:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


## POLL UNTIL IT HOLDS. `_place_panel` is a coroutine that itself waits for the
## openings to stop moving, so a fixed timer after `show_panel` photographs a
## panel that has not been placed. The board's idle bob is +/-3px forever, so the
## signature is the PANEL's rect (which does settle) plus the openings rounded
## into 8px buckets (which the bob cannot cross).
func _settle_coach() -> void:
	var coach = _combat.get("_coach")
	if coach == null or not is_instance_valid(coach):
		await _frames(20)
		return
	await _settle_panel(coach)
	# One more beat so the marks' 0.20s fade-in and the staggered slot delays are
	# all the way up — the frame is about how they LOOK, not that they exist.
	await _frames(24)


func _settle_panel(coach) -> void:
	var prev := ""
	var held := 0
	for _i in 150:
		await get_tree().process_frame
		if not is_instance_valid(coach):
			return
		var now := _coach_signature(coach)
		if now == prev and now != "":
			held += 1
			if held >= 4:
				return
		else:
			held = 0
		prev = now


func _coach_signature(coach) -> String:
	var out := ""
	var p = coach._panel
	if p != null and is_instance_valid(p):
		out += "%d,%d,%d,%d|" % [roundi(p.position.x), roundi(p.position.y),
			roundi(p.size.x), roundi(p.size.y)]
	for r in coach._scrim_holes:
		out += "%d,%d,%d,%d;" % [roundi(r.position.x / 8.0),
			roundi(r.position.y / 8.0), roundi(r.size.x / 8.0),
			roundi(r.size.y / 8.0)]
	return out


## The numbers behind the pixels: where every arrow decided to end, and how far
## that is from the rect it is naming. A still frame says "that looks close"; this
## says whether the tip is on the card's real edge or in the wedge beside it.
func _dump_arrow(coach, tag: String) -> void:
	for m in coach._marks:
		if String(m.get("kind", "")) != "arrow":
			continue
		var n = m.get("node")
		var t = (m["ref"] as WeakRef).get_ref()
		if n == null or not is_instance_valid(n) or t == null:
			continue
		var c: Control = t
		var aabb := TutorialCoach.visual_rect(c)
		var xf := c.get_global_transform()
		# Distance from the tip to the card's REAL (rotated) rect, measured in the
		# card's own space — negative means the tip is inside the card.
		var local: Vector2 = xf.affine_inverse() * n._tip
		var half := c.size * 0.5
		var d := Vector2(absf(local.x - half.x) - half.x,
			absf(local.y - half.y) - half.y)
		var outside: float = maxf(d.x, d.y)
		print("[%s] %s side=%s dir=%s tip=%s · rot=%.1f deg scale=%.2f · "
			% [tag, c.name, n.side, str(n._dir.round()),
				str(n._tip.round()), rad_to_deg(xf.get_rotation()),
				xf.get_scale().x]
			+ "standoff-from-real-edge=%.1fpx · aabb=%s" % [outside, str(aabb)])


## A TIGHT ZOOM ON EACH ARROW, centred on the stroke rather than on the target.
## The seam between the shaft and the head is ~8px of a 1600px frame; it cannot
## be judged at any scale where the whole board is visible, and it is the single
## thing most likely to make the mark read as programmer art.
func _crop_arrows(img: Image, tag: String, coach, zoom: float) -> void:
	var n := 0
	for m in coach._marks:
		if String(m.get("kind", "")) != "arrow":
			continue
		var node = m.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var mid: Vector2 = node._tip - node._dir * (node.length * 0.5)
		_crop(img, "%s_head%d" % [tag, n], mid,
			Vector2(node.length + 90.0, node.length * 0.8 + 70.0), zoom)
		n += 1


func _report_marks(tag: String) -> void:
	var coach = _combat.get("_coach")
	if coach == null or not is_instance_valid(coach):
		print("[coach] %s: no coach" % tag)
		return
	var kinds := {}
	for m in coach._marks:
		var k := String(m.get("kind", "?"))
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("[coach] %s: marks=%s · holes=%d · panel=%s" % [tag, str(kinds),
		coach._scrim_holes.size(),
		str(Rect2(coach._panel.position, coach._panel.size))
			if coach._panel != null and is_instance_valid(coach._panel)
			else "<none>"])
	_dump_arrow(coach, tag)


func _shoot(tag: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_coach_%s.png" % [OUT_DIR, tag])
	print("SAVED _coach_", tag, " ", img.get_size())
	return img


## A NEAREST-NEIGHBOUR ZOOM, not a resample. A 2.4px rim and a 16px standoff are
## the subject; a smooth filter would invent the smoothness being judged.
func _crop(img: Image, tag: String, center: Vector2, size: Vector2,
		zoom: float) -> void:
	if img == null:
		return
	var full := Rect2i(Vector2i.ZERO, img.get_size())
	var r := Rect2i(Vector2i((center - size * 0.5).round()),
		Vector2i(size.round())).intersection(full)
	if r.size.x < 8 or r.size.y < 8:
		return
	var sub := img.get_region(r)
	sub.resize(int(r.size.x * zoom), int(r.size.y * zoom),
		Image.INTERPOLATE_NEAREST)
	sub.save_png("%s/_coach_%s.png" % [OUT_DIR, tag])
	print("SAVED _coach_", tag, " ", sub.get_size(), " from ", r)


# ── Profile hygiene ────────────────────────────────────────────────────

func _save_profile() -> void:
	for k in ["muster_tutorial_seen", "intents_tutorial_seen", "pile_tutorial_seen",
			"banking_tutorial_seen", "combat_model_tutorial_seen",
			"dismiss_tutorial_seen", "first_battle_tutorial_complete"]:
		_saved[k] = UserSettings.get(k)
	_saved["lessons_seen"] = UserSettings.lessons_seen.duplicate(true)
	_saved["coaching_mode"] = UserSettings.coaching_mode
	_saved["reduce_motion"] = UserSettings.reduce_motion


func _restore_profile() -> void:
	for k in _saved:
		UserSettings.set(k, _saved[k])
	UserSettings.save()
