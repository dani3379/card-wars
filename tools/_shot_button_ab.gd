extends Control
## _shot_button_ab — the OLD flat-rule button vs the NEW struck plaque, measured.
##
## THE ORACLE IS INHERITED ON PURPOSE. `_shot_frame_ab` already established the
## two numbers that separate "a thicker line" from "an object", and the defect
## here is the same defect one control over, so re-deriving a second oracle would
## only make the two passes incomparable:
##
##   PLATEAUS  — distinct values crossing the edge's width. A polyline has one by
##               construction. A molding must have several.
##   INVERSION — the profile across the TOP run against the profile across the
##               BOTTOM run at equal depth u. A symmetric stroke scores ~0 here
##               however many layers are stacked behind it, which is exactly why
##               `ChartPanelStyle`'s halo-under-rule could never have worked.
##
## Plus one this pass needs and the frame pass did not, because a frame is hollow
## and a button has a FACE:
##
##   FACE TILT — the luminance at the up-left third of the plate's face against
##               the down-right third. The old fill ramps top-to-bottom, so it
##               scores ~0 along the lamp's own axis while the molding beside it
##               is lit up-left: one control, two suns. A face lit by the same
##               lamp as its edge must score positive.
##
## And the state claim, which is the whole reason a solid beats a rectangle:
##
##   PRESS DROP — ink OUTSIDE the plate's silhouette (its cast shadow) at rest
##               against the same at press. A rectangle cannot move this at all;
##               it can only change its fill. A plate driven flush must lose it.
##
## Windowed, and the zoom crops are NEAREST — a 5px molding's three values are
## not decidable at 1:1. Same reason the coach-device shots zoom.

const OUT_DIR := "res://tools/screenshot"
const PlaqueStyle := preload("res://scripts/ui/painters/PlaqueStyle.gd")

## The shell's warm-black ground, quoted from Sheen.gd's header.
const GROUND := Color(0.118, 0.094, 0.074)
## The two real geometries: MainMenu's primary action (NAV_PRIMARY_W x 46) and a
## themed button's default min_size.
const PRIMARY := Vector2(340, 46)
const THEMED := Vector2(160, 44)
## THE SHIPPED CTA, AND ITS ABSENCE HERE WAS A REAL HARNESS FAULT.
##
## `MainMenu._make_begin_button` sets `custom_minimum_size = (470, 56)` and NO
## horizontal size flag, and it is added to an HBox — so it FILLS the row at
## roughly 800px. Every fixture in this tool was 340 or 160 wide, so a defect
## whose magnitude scales with WIDTH (the specular was sized off the plate's long
## axis) was invisible by construction: it looked like a believable lobe at 340
## and shipped as a pale wedge across half the real button.
##
## The general form is worth keeping: A FIXTURE THAT IS NOT THE SHIPPED GEOMETRY
## CANNOT SEE A DEFECT THAT SCALES WITH GEOMETRY. Same family as C26's
## denominator lesson — measure the thing the player actually gets.
const CTA := Vector2(800, 56)

var _rects: Dictionary = {}     # tag -> Rect2 (CANVAS space)
## tag -> the edge's nominal width in canvas px.
##
## NEEDED BECAUSE THE FIRST RUN'S INVERSION FIGURE WAS CONFOUNDED BY THE FACE.
## A frame is HOLLOW, so `_shot_frame_ab` could profile 14px inward over a flat
## interior and read nothing but molding. A button is FILLED: past the metal the
## same profile runs onto the plate's own graded face, and the face is graded, so
## top and bottom differ there for a reason that has nothing to do with a
## cross-section. The old flat-rule button scored 0.128 that way while its rule
## measured 0.52 on BOTH runs — i.e. an edge inversion of zero, reported as
## 0.128 by an oracle that had wandered off the edge it was asking about. The
## band is clipped to the metal now, and the face is a SEPARATE number.
var _edge_w: Dictionary = {}
## Framebuffer px per canvas px. MEASURED off the captured image, never assumed —
## this is the trap that voided the frame pass's first run outright (a window
## asked for 1600x900 came back 1920x1080, every sample landed 20% off, and the
## molding measured identical to the flat rule: a clean report about pixels
## nobody was looking at).
var _px := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	size = Vector2(1600, 900)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = GROUND
	add_child(bg)

	# ── the measured pairs. Same colours both arms, so nothing in the numbers is
	# a palette change: these are the literals `make_primary_button` shipped.
	var gilt := Color(0.80, 0.61, 0.30, 0.82)
	var field := Color(0.125, 0.068, 0.032, 0.93)

	_old("old_primary", Vector2(80, 70), PRIMARY, gilt, field)
	_new("new_primary", Vector2(80, 150), PRIMARY, gilt, field,
		PlaqueStyle.REST, {"tacks": true, "rule_width": 5.5})
	_new("new_primary_hover", Vector2(80, 230), PRIMARY, GameTheme.GILT_BRIGHT,
		Color(0.20, 0.105, 0.042, 0.97), PlaqueStyle.HOVER,
		{"tacks": true, "rule_width": 5.5})
	_new("new_primary_press", Vector2(80, 310), PRIMARY,
		Color(0.86, 0.68, 0.34), Color(0.085, 0.048, 0.026, 0.98),
		PlaqueStyle.PRESS, {"tacks": true, "rule_width": 5.5})

	# The old button's PRESSED state, from `make_primary_button`'s own literals.
	# THE STATE CLAIM IS A WITHIN-ARM COMPARISON, and it has to be: the old
	# style's edge toast is drawn at `rule_width + 9` px straddling the path, so
	# ~5px of it lies OUTSIDE the control's rect and lands in any band sampled
	# just under the plate. Measured across arms that spill reads as the old
	# button having a BRIGHTER-than-ground shadow (+0.057), which is an artifact
	# of where the stroke goes, not a fact about shadows. Compared rest-to-press
	# inside one arm it cancels exactly, and what is left is the only thing being
	# claimed: a rectangle cannot change how it sits on the page, and a solid can.
	_old("old_primary_press", Vector2(80, 390), PRIMARY,
		Color(0.88, 0.70, 0.35), Color(0.090, 0.050, 0.027, 0.98))

	# THE REAL CTA WIDTH, rest and hovered. This is the pair that would have
	# caught the wedge.
	_new("cta_rest", Vector2(560, 640), CTA,
		Color(0.84, 0.64, 0.32, 0.86), Color(0.135, 0.072, 0.034, 0.94),
		PlaqueStyle.REST, {"tacks": true, "rule_width": 6.0, "chamfer": 11.0,
			"engrave": false})
	_new("cta_hot", Vector2(560, 710), CTA,
		GameTheme.GILT_BRIGHT, Color(0.235, 0.120, 0.048, 0.98),
		PlaqueStyle.REST, {"tacks": true, "rule_width": 6.0, "chamfer": 11.0,
			"engrave": false, "hover_t": 1.0})

	_old("old_themed", Vector2(560, 70), THEMED, GameTheme.GILT, field)
	_new("new_themed", Vector2(560, 150), THEMED, GameTheme.GILT, field,
		PlaqueStyle.REST, {"rule_width": 4.0})

	# ── THE TRANSITION. Discrete staged states cannot show it: the whole claim
	# is that the plate MOVES between them, so the strip steps `hover_t` and
	# renders the in-between poses that used to be unreachable (Godot swapped a
	# whole stylebox, so there was no such thing as half-hovered). The last tile
	# adds press on top of full hover — the case a single 0..1 "activation"
	# cannot express and the reason there are two numbers.
	_strip_row(Vector2(80, 470))

	# ── eyes only: a real row of live factory buttons, so the shot catches
	# anything the numbers cannot (a cartouche landing on a descender, a tack
	# sitting on a letter, a sweep washing out the type).
	_live_row(Vector2(560, 250))

	# ── THE TYPE EXPERIMENT. `Button` has no shadow theme item that I can
	# confirm from memory, and a struck-looking label would be worth having, so
	# ASK THE ENGINE rather than guess: set one and print whether ThemeDB thinks
	# a Button has it at all. Cheap, and it belongs in the tool that already
	# renders the thing.
	_probe_font_shadow()
	await _verify_tween()

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_button_ab.png" % OUT_DIR)
	print("SAVED _button_ab.png ", img.get_size())
	_px = float(img.get_width()) / maxf(size.x, 1.0)
	print("canvas=", size, "  framebuffer=", img.get_size(), "  scale=%.3f" % _px)

	for tag in ["old_primary", "new_primary", "new_primary_hover",
			"new_primary_press", "old_themed", "new_themed"]:
		_report(img, tag)
	print("")
	print("── the state claim: cast shadow, rest vs pressed, within each arm ──")
	_press_drop(img)
	for tag in ["old_primary", "new_primary", "new_primary_hover",
			"new_primary_press"]:
		_zoom(img, tag)
	# THE STRUCK WORD, at 6x. A 1.6px directional shadow under a glyph is not
	# decidable at 1:1 — and the failure mode it has to be checked for is a
	# DOUBLE PRINT (the ghost landing off its caster), which at 1:1 just looks
	# like slightly heavier type.
	_crop(img, "engrave", Vector2(730, 273) * _px, Vector2(190, 36) * _px, 6.0)
	get_tree().quit()


# ── samples ────────────────────────────────────────────────────────────────

func _host(at: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = at
	p.size = sz
	p.custom_minimum_size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


## The button exactly as it shipped this morning: `make_panel_style`, which is a
## flat gradient fill under seam + toast + halo + rule, all four symmetric.
func _old(tag: String, at: Vector2, sz: Vector2, metal: Color,
		field: Color) -> void:
	var p := _host(at, sz)
	p.add_theme_stylebox_override("panel",
		GameTheme.make_panel_style(field, metal, 2, 5, false))
	_rects[tag] = Rect2(at, sz)
	# `make_panel_style(..., border_w = 2)` -> `rule_width = 2`, and the crisp
	# rule floors at 1.4px. 2 is the metal's whole width.
	_edge_w[tag] = 2.0


func _new(tag: String, at: Vector2, sz: Vector2, metal: Color, field: Color,
		state: int, opts: Dictionary = {}) -> void:
	var p := _host(at, sz)
	p.add_theme_stylebox_override("panel",
		GameTheme.make_plaque_style(metal, field, state, opts))
	_rects[tag] = Rect2(at, sz)
	_edge_w[tag] = float(opts.get("rule_width", 5.0))


## `hover_t` stepped across a row, plus one pressed-while-hovered tile.
func _strip_row(at: Vector2) -> void:
	var steps := [0.0, 0.25, 0.5, 0.75, 1.0]
	for i in range(steps.size()):
		var p := _host(at + Vector2(0, float(i) * 56.0), PRIMARY)
		var plate := GameTheme.make_plaque_style(
			Color(0.80, 0.61, 0.30, 0.82), Color(0.125, 0.068, 0.032, 0.93),
			PlaqueStyle.REST, {"rule_width": 5.5})
		plate.set("metal_hot", GameTheme.GILT_BRIGHT)
		plate.set("fill_hot", Color(0.215, 0.112, 0.045, 0.97))
		plate.set("hover_t", float(steps[i]))
		p.add_theme_stylebox_override("panel", plate)
	var pp := _host(at + Vector2(0, 5.0 * 56.0), PRIMARY)
	var pressed_plate := GameTheme.make_plaque_style(
		Color(0.80, 0.61, 0.30, 0.82), Color(0.125, 0.068, 0.032, 0.93),
		PlaqueStyle.REST, {"rule_width": 5.5})
	pressed_plate.set("metal_hot", GameTheme.GILT_BRIGHT)
	pressed_plate.set("hover_t", 1.0)
	pressed_plate.set("press_t", 1.0)
	pp.add_theme_stylebox_override("panel", pressed_plate)
	_rects["strip_rest"] = Rect2(at, PRIMARY)
	_rects["strip_mid"] = Rect2(at + Vector2(0, 112.0), PRIMARY)
	_rects["strip_hot"] = Rect2(at + Vector2(0, 224.0), PRIMARY)
	_edge_w["strip_rest"] = 5.5
	_edge_w["strip_mid"] = 5.5
	_edge_w["strip_hot"] = 5.5


## Live factory output — not a staged stylebox. This is the arm that would catch
## a wiring mistake the staged pairs cannot see.
func _live_row(at: Vector2) -> void:
	var col := VBoxContainer.new()
	col.position = at
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	col.add_child(GameTheme.make_primary_button("START RUN", PRIMARY, 20))
	col.add_child(GameTheme.make_primary_button("TAKE THE FIELD", PRIMARY, 20))
	col.add_child(GameTheme.make_themed_button("Buy  50g", GameTheme.GILT, THEMED))
	var dis := GameTheme.make_themed_button("Buy  50g", GameTheme.GILT, THEMED)
	dis.disabled = true
	col.add_child(dis)


## DOES A TWEEN ACTUALLY DRIVE A STYLEBOX PROPERTY ON A LIVE BUTTON?
##
## The whole transition rests on it: a StyleBox is a Resource, so
## `tween_property(plate, "hover_t", ...)` should work and `emit_changed()`
## should repaint. "Should" is not a measurement, and the failure would be
## SILENT — the plate would simply keep snapping and look exactly like the
## version before this pass.
##
## So drive the REAL signal on a REAL factory button and sample the property
## mid-flight. A value strictly between 0 and 1 is the proof; 0 means nothing is
## driving it and 1 means it snapped.
func _verify_tween() -> void:
	# REDUCE MOTION IS THE FIRST THING TO ASK, because `arm_transitions` snaps by
	# DESIGN when it is on — a state transition is informational, so the contract
	# says hold it instantly rather than drop it. A harness running with the
	# setting on therefore reports a perfectly correct implementation as broken,
	# which is what happened here. Print it, then test the moving path with it
	# off, and the snap path with it on.
	var us := get_node_or_null("/root/UserSettings")
	var had: bool = us != null and bool(us.get("reduce_motion"))
	print("")
	print("── the transition (tween on a StyleBox property) ──")
	print("   harness reduce_motion=", had)
	if us != null:
		us.set("reduce_motion", false)
	# ── SLOW THE CLOCK, DO NOT LENGTHEN THE TWEEN.
	#
	# Second oracle fault in a row, and the opposite of the first. Per-frame
	# sampling fixed the wall-clock assumption and then reported 0.99 on the
	# FIRST frame — because this tool builds ~20 clipped-polygon plates and
	# renders at a few fps, so a single frame's delta swallows a 130ms tween
	# whole. The tell that it was the instrument and not the code: a genuine snap
	# lands on EXACTLY 1.000 (the reduce-motion arm below does), and 0.99 is an
	# interpolated value that had 129 of its 130ms already spent.
	#
	# `Engine.time_scale` is the right instrument because it slows the thing under
	# test without CHANGING it — lengthening the durations for the test would
	# measure a tween the product does not use.
	var was_scale := Engine.time_scale
	Engine.time_scale = 0.03
	var b := GameTheme.make_primary_button("PROBE", PRIMARY, 20)
	add_child(b)
	await get_tree().process_frame
	var plate := b.get_theme_stylebox("normal")
	b.mouse_entered.emit()
	# SAMPLED PER FRAME, NOT ON A WALL CLOCK. The first version read the property
	# 40ms in and reported a flat 0.000, i.e. "NOT INTERPOLATING" — but this tool
	# builds ~15 clipped-polygon plates and renders well under 60fps, so 40ms can
	# be LESS THAN ONE FRAME and a tween has not been stepped even once. That is
	# `reference_settle_until_stable` in another dress: a frame budget is not a
	# time budget, and here the mistake ran the other way round.
	var traj: Array = []
	for _i in range(14):
		await get_tree().process_frame
		traj.append(float(plate.get("hover_t")))
	var moved := false
	for v in traj:
		if float(v) > 0.01 and float(v) < 0.99:
			moved = true
	var done: float = float(traj[traj.size() - 1])
	# THE TWO HALVES ARE MEASURED AT DIFFERENT CLOCKS, and they have to be.
	# `moved` is only observable slowed down; ARRIVAL is only observable at
	# normal speed, because at time_scale 0.03 a 130ms tween needs ~4s of
	# wall-clock and 14 frames of it reads as "never finished" — which is what
	# the verdict line wrongly called NOT INTERPOLATING while printing a
	# perfectly good ramp right above itself. A monotone climb IS the proof of
	# interpolation; completion is a separate question.
	Engine.time_scale = was_scale
	for _i in range(12):
		await get_tree().process_frame
	done = float(plate.get("hover_t"))
	var rising := traj.size() > 1 and float(traj[traj.size() - 1]) > float(traj[0])
	print("   hover_t per frame (time_scale 0.03): ", _fmt(traj))
	print("   intermediate=%s  rising=%s  arrives at %.3f   %s" % [
		str(moved), str(rising), done,
		"DRIVEN" if (moved and rising and done > 0.95)
			else "*** NOT INTERPOLATING ***"])
	# Same stylebox instance in every live state is what made it drivable.
	print("   one instance across states: ",
		b.get_theme_stylebox("normal") == b.get_theme_stylebox("pressed"))
	# And the reduce-motion path: it must still ARRIVE, instantly. A transition
	# that carries state may be held but never dropped.
	if us != null:
		us.set("reduce_motion", true)
	var b2 := GameTheme.make_primary_button("PROBE2", PRIMARY, 20)
	add_child(b2)
	await get_tree().process_frame
	var p2 := b2.get_theme_stylebox("normal")
	b2.mouse_entered.emit()
	await get_tree().process_frame
	print("   reduce_motion: hover_t after one frame=%.3f  %s" % [
		float(p2.get("hover_t")),
		"SNAPPED (correct)" if float(p2.get("hover_t")) > 0.95 else "*** LOST ***"])
	if us != null:
		us.set("reduce_motion", had)
	b.queue_free()
	b2.queue_free()


## Does a Button honour a font shadow? Asked, not assumed.
func _probe_font_shadow() -> void:
	var b := Button.new()
	var names := ThemeDB.get_default_theme().get_color_list("Button")
	print("")
	print("── Button theme colour items: ", names)
	print("   has font_shadow_color: ",
		ThemeDB.get_default_theme().has_color("font_shadow_color", "Button"))
	b.free()


# ── the oracle ─────────────────────────────────────────────────────────────

## Luminance profile crossing a run of the edge, outer -> inner.
func _profile(img: Image, x: int, y0: int, dir: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var y := y0 + dir * i
		if y < 0 or y >= img.get_height() or x < 0 or x >= img.get_width():
			out.append(0.0)
			continue
		out.append(img.get_pixel(x, y).get_luminance())
	return out


func _report(img: Image, tag: String) -> void:
	var r: Rect2 = _rects[tag]
	var x := int((r.position.x + r.size.x * 0.5) * _px)
	var span := int(round(12.0 * _px))
	var lead := int(round(3.0 * _px))
	# Start 3px OUTSIDE the plate so the ground and the drop are in frame.
	var top := _profile(img, x, int(r.position.y * _px) - lead, 1, span)
	var bot := _profile(img, x, int(r.end.y * _px) + lead, -1, span)

	# Clipped to the metal: `lead` px of ground/drop, then the edge's own width,
	# and stop before the face. See `_edge_w` for why this is not the full span.
	var edge_n: int = mini(span, lead + int(ceil(float(_edge_w[tag]) * _px)) + 2)
	var levels: Dictionary = {}
	for i in range(edge_n):
		levels[snappedf(float(top[i]), 0.02)] = true
	var asym := 0.0
	for i in range(edge_n):
		asym = maxf(asym, absf(float(top[i]) - float(bot[i])))

	print("── ", tag)
	print("   top    ", _fmt(top))
	print("   bottom ", _fmt(bot))
	# THE CORRELATION WINDOW IS THE METAL AND NOTHING ELSE. It starts at `lead`
	# (skipping the ground and the drop, which are flat and carry no
	# cross-section) and stops at the metal's own width (not `edge_n`, which
	# carries 2px of slop so the plateau count can see the inner boundary). The
	# first run windowed it loosely and read -0.09 on a molding whose middle
	# seven samples are strongly opposed — the face, four samples of it, was
	# dragging a real signal back toward zero.
	var m0: int = lead
	var m1: int = mini(span, lead + int(ceil(float(_edge_w[tag]) * _px)))
	var rs := "  n/a"
	if m1 - m0 >= 4:
		rs = "%+.2f" % _shoulder_r(top.slice(m0, m1), bot.slice(m0, m1), m1 - m0)
	else:
		# NOT A FAILURE TO MEASURE — IT IS THE MEASUREMENT. A 2px rule is 3
		# samples at this scale, which is fewer than a correlation can use: the
		# stroke has no cross-section to sample, which is the entire claim about
		# it. Reported as n/a rather than as a number, because a guard returning
		# 0.0 prints as a confident finding (the old arm read a perfect +0.00
		# and it was this branch, not a result).
		pass
	var pk := _peak_split(top, bot, m0, mini(span, m1 + 2))
	print("   edge band=%dpx  plateaus=%d  INVERSION=%.3f  SHOULDER r=%s  PEAK SPLIT=%s  FACE TILT=%+.3f" % [
		edge_n, levels.size(), asym, rs, pk, _face_tilt(img, r)])


## Mean luminance of the face's up-left third minus its down-right third, along
## the lamp's own axis. Sampled well inside the molding so the edge cannot
## contribute, and away from the label's centre band so the type cannot either.
func _face_tilt(img: Image, r: Rect2) -> float:
	var inset := 11.0
	var a := _patch(img, Rect2(r.position + Vector2(inset, inset),
		Vector2(r.size.x * 0.22, r.size.y - inset * 2.0)))
	var b := _patch(img, Rect2(
		r.position + Vector2(r.size.x * 0.78 - inset, inset),
		Vector2(r.size.x * 0.22, r.size.y - inset * 2.0)))
	return a - b


func _patch(img: Image, rect: Rect2) -> float:
	var total := 0.0
	var n := 0
	var x0 := int(rect.position.x * _px)
	var y0 := int(rect.position.y * _px)
	var x1 := int(rect.end.x * _px)
	var y1 := int(rect.end.y * _px)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			total += img.get_pixel(x, y).get_luminance()
			n += 1
	return total / maxf(float(n), 1.0)


## Ink lying OUTSIDE the plate but inside its draw rect — the cast shadow. The
## old button and the new one at rest both have one; the PRESSED plaque must
## not, because it is flush. Measured as mean darkening against the bare ground
## in an L-shaped band off the bottom-right (where an up-left lamp throws it).
## THE SIGN IS THE READING, NOT THE MAGNITUDE — and a within-arm delta alone
## hides that, which the first run proved by scoring the two arms almost equal
## (+0.0295 old, +0.0320 new) for opposite reasons. What moved in the old arm is
## its own STROKE getting brighter (its pressed state is handed a brighter
## metal, and `ChartPanelStyle`'s edge toast is drawn `rule_width + 9` px wide
## straddling the path, so ~5px of it lies outside the control and lands in this
## band). What moved in the new arm is a shadow ceasing to exist. Identical
## numbers, unrelated facts.
##
## So report the SIGNED deviation from bare ground. Negative = darker than the
## page = an actual cast shadow. POSITIVE = brighter than the page, which is not
## a shadow at all and is the tell that a stroke is spilling out there.
func _press_drop(img: Image) -> void:
	var ground := GROUND.get_luminance()
	for tag in ["old_primary", "old_primary_press", "new_primary",
			"new_primary_hover", "new_primary_press"]:
		var lum := _under(img, tag)
		var dev := lum - ground
		var verdict := "cast shadow" if dev < -0.008 else (
			"NO shadow (stroke spill)" if dev > 0.008 else "flush — no shadow")
		print("   %-19s band=%.4f  ground=%.4f  dev=%+.4f   %s" % [
			tag, lum, ground, dev, verdict])


## Mean luminance of the band just under the plate — where an up-left lamp
## throws its cast shadow.
func _under(img: Image, tag: String) -> float:
	var r: Rect2 = _rects[tag]
	return _patch(img, Rect2(r.position + Vector2(6, r.size.y + 0.5),
		Vector2(r.size.x - 6, 5.0)))


## THE PEAK SPLIT — where the brightest sample sits on the top run, against
## where it sits on the bottom run, in canvas px of depth.
##
## THIS IS THE HEADLINE, and it is the one statistic here that works at ANY
## stroke width and cannot be faked by noise. PlateFrame's claim is physical and
## positional: a bead lit from up-left catches the lamp on its OUTER shoulder
## along the top run, and along the bottom run the same bead presents its other
## shoulder, so the highlight moves to the INNER edge. So the two runs' peaks
## must sit at opposite depths.
##
## A symmetric stroke — one band, or four stacked bands, it makes no difference —
## presents an identical cross-section on every run by construction, so both
## peaks land at the same depth and the split is 0. No thresholds, no tuning, and
## immune to the sub-pixel AA phase that put a 0.128 "inversion" on a rule
## measuring 0.52 / 0.52 / 0.52 on both runs.
static func _peak_split(top: Array, bot: Array, i0: int, i1: int) -> String:
	if i1 - i0 < 2:
		return "n/a"
	var ti := i0
	var bi := i0
	for i in range(i0, i1):
		if float(top[i]) > float(top[ti]):
			ti = i
		if float(bot[i]) > float(bot[bi]):
			bi = i
	return "%dpx (top@%d bottom@%d)" % [absi(ti - bi), ti - i0, bi - i0]


## THE SHOULDER TEST — Pearson r between the top run's profile and the bottom
## run's, across the metal.
##
## ADDED BECAUSE `INVERSION` HAS A NOISE FLOOR ON A FILLED PLATE, and the first
## run's figures showed it: the old flat-rule button scored 0.128 while its rule
## measured 0.52, 0.52, 0.52 on the top run and 0.51, 0.52, 0.52 on the bottom —
## three pixels of ONE value, identical on opposite runs, which is a flat stroke
## by definition and an inversion of zero. The 0.128 was coming from sub-pixel
## AA phase (the wobbled path lands on a different fraction of a pixel top and
## bottom) plus the fill gradient at the inner boundary. A peak-difference
## statistic cannot tell that apart from real shading.
##
## Correlation can, and needs no threshold tuning. A symmetric stroke presents
## the SAME cross-section on every run, so its two profiles are the same curve
## and r -> +1 however noisy each is. A molding presents opposite shoulders, so
## where one rises the other falls and r goes NEGATIVE. The sign is the whole
## claim of PlateFrame's header, expressed as one number that noise cannot fake:
## noise decorrelates toward 0, it does not reach -1.
static func _shoulder_r(top: Array, bot: Array, n: int) -> float:
	if n < 4:
		return 0.0
	var mt := 0.0
	var mb := 0.0
	for i in range(n):
		mt += float(top[i])
		mb += float(bot[i])
	mt /= float(n)
	mb /= float(n)
	var num := 0.0
	var dt := 0.0
	var db := 0.0
	for i in range(n):
		var a := float(top[i]) - mt
		var b := float(bot[i]) - mb
		num += a * b
		dt += a * a
		db += b * b
	if dt <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(dt * db)


func _fmt(a: Array) -> String:
	var s := ""
	for v in a:
		s += "%.2f " % float(v)
	return s


func _zoom(img: Image, tag: String) -> void:
	var r: Rect2 = _rects[tag]
	# The top-left corner: a run of the top molding, a run of the left molding,
	# the chamfer between them, and a tack if the plate carries one.
	_crop(img, tag + "_corner", (r.position + Vector2(24, 20)) * _px,
		Vector2(74, 50) * _px, 8.0)
	# A span of the BOTTOM run at the same scale — the half of the inversion
	# claim a single corner shot cannot show.
	_crop(img, tag + "_bottom",
		Vector2(r.position.x + r.size.x * 0.5, r.end.y - 8) * _px,
		Vector2(74, 28) * _px, 8.0)


func _crop(img: Image, tag: String, center: Vector2, sz: Vector2,
		zoom: float) -> void:
	var full := Rect2i(Vector2i.ZERO, img.get_size())
	var rr := Rect2i(Vector2i((center - sz * 0.5).round()),
		Vector2i(sz.round())).intersection(full)
	if rr.size.x < 4 or rr.size.y < 4:
		return
	var sub := img.get_region(rr)
	sub.resize(int(rr.size.x * zoom), int(rr.size.y * zoom),
		Image.INTERPOLATE_NEAREST)
	sub.save_png("%s/_button_%s.png" % [OUT_DIR, tag])
	print("SAVED _button_", tag, " ", sub.get_size())
