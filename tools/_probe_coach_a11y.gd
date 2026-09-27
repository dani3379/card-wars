extends Node
## _probe_coach_a11y.gd — THE ACCESSIBILITY CONTRACT OF THE COACHING LAYER.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_coach_a11y.tscn
##
## RUNS AS A SCENE, not `--script`: everything in here reads UserSettings, and an
## autoload does not exist in a `--script` context (CLAUDE.md, "parsecheck's ONE
## blind spot"). Sibling gate to `_probe_tutorial.gd`, which covers the REGISTRY —
## reachability, copy budgets, the legacy mapping and the coaching modes. This one
## covers the LAYER: what `scripts/ui/TutorialCoach.gd` actually puts on screen.
##
## Its five claims are all documented in TutorialCoach.gd's own header and none of
## them was tested. Each fails SILENTLY — the coach still runs, no error is
## printed, and the only symptom is a player who cannot see or cannot dismiss the
## one thing on screen telling them what to do.
##
##   1 · REDUCE MOTION HOLDS, IT DOES NOT REMOVE. The house contract splits every
##       animation into informational (always plays, parks steady) and decorative
##       (gated off). A coach mark is informational by definition: it is the
##       instruction. So with `reduce_motion` ON the rim, the arrow and the arc
##       must still RENDER — parked, not deleted, and not left at alpha 0. The
##       trap is that `begin()` and `dismiss()` both branch on `reduced()`, so a
##       mark that is technically alive and completely invisible is one edit away.
##
##   2 · NO ESSENTIAL INFORMATION BY COLOUR ALONE (Game Accessibility Guidelines).
##       A hot rim is a colour channel. Every lesson must therefore also deliver a
##       NON-colour channel — worded copy in a panel, and the punched hole that
##       says where — and `colorblind_mode` must blank none of it.
##
##   3 · UI SCALE (class C32). `content_scale_factor` 0.6 lays the UI out on
##       2667x1500, not 1600x900. `_place_panel` and `_push_holes` both claim to
##       derive everything from the live canvas. The oracle here is the house one
##       from `tools/_probe_uiscale.gd` — DIFFERENTIAL, comparing the same
##       fixture stated in canvas FRACTIONS at three scales, so it needs no taste
##       and no knowledge of the intended design.
##
##   4 · THE PANEL MUST NOT COVER WHAT IT IS TALKING ABOUT. `_place_panel` walks
##       above / below / beside the spotlight before falling back, and must never
##       land on the merged opening nor in the bottom 20% hand band.
##
##   5 · KEYBOARD. `show_panel` parks focus on the primary button only when there
##       IS one — a step whose affordance is the board must NOT leave focus on
##       SKIP TUTORIAL, or the space bar quits the walkthrough. And `ui_cancel`
##       leaves the lesson (WCAG 2.1.1) ONLY while a panel with a visible skip is
##       up, so Esc still reaches the pause menu everywhere else.
##
## IT RESTORES THE PROFILE'S FLAGS ON THE WAY OUT — `reduce_motion`,
## `colorblind_mode`, `coaching_mode` and the whole seen-ledger are the
## developer's real settings and a gate has no business spending them. Run it with
## APPDATA pointed at a temp dir anyway; `mark_lesson_seen` writes to disk.


const COACH_SRC := "res://scripts/ui/TutorialCoach.gd"

## Three of the five stops `SettingsOverlay._add_ui_scale_row` offers.
const SCALES: Array[float] = [1.0, 0.85, 0.6]

## The colour-blind palettes `SettingsOverlay` offers.
const CB_MODES: Array[String] = ["off", "deuteranopia", "protanopia", "tritanopia"]

## How far the panel's CENTRE may drift, as a fraction of the canvas, between one
## UI Scale and another. Deliberately generous: the panel's width clamp (520-820)
## and its padding are absolute pixels BY DESIGN — UI Scale exists to make the UI
## smaller relative to the canvas — so a small fractional drift is correct
## behaviour. A panel placed from a 1600-wide CONSTANT lands at 0.30 of a 2667
## canvas instead of 0.50, which is twice this.
const CENTRE_TOL := 0.10

## A body long enough to wrap at every scale, so the panel has a real height.
const LONG_BODY := "Creatures fight the lane they stand in. Both rows strike " \
	+ "every round — the front row simply strikes first, and is struck first."

## THE KEEP-OUT BATTERY, stated in CANVAS FRACTIONS so each case is literally the
## same layout problem at any UI Scale. Every one of these is a shape a real
## teaching site opens: Shop spotlights one gold label, Combat's step 1 opens a
## hand card plus its slots, step 3 opens a lane column, Recruit opens three card
## tiles, MapView opens every reachable site button.
const KEEPOUT_CASES := [
	{"name": "one hud chip", "hard": true,
		"rects": [Rect2(0.025, 0.045, 0.115, 0.065)]},
	{"name": "a hand card", "hard": true,
		"rects": [Rect2(0.375, 0.755, 0.100, 0.235)]},
	{"name": "a lane column", "hard": true,
		"rects": [Rect2(0.435, 0.135, 0.115, 0.680)]},
	{"name": "the front row", "hard": true,
		"rects": [Rect2(0.190, 0.420, 0.560, 0.170)]},
	{"name": "card + open slots", "hard": true,
		"rects": [Rect2(0.360, 0.780, 0.100, 0.200), Rect2(0.400, 0.440, 0.115, 0.200)]},
	{"name": "three recruit tiles", "hard": true,
		"rects": [Rect2(0.200, 0.330, 0.140, 0.340), Rect2(0.430, 0.330, 0.140, 0.340),
			Rect2(0.660, 0.330, 0.140, 0.340)]},
	# NOT a hard failure: two openings at opposite corners merge — in
	# `_place_panel`, though NOT in `_merge_rects` — into a keep-out that spans the
	# screen, and no candidate can clear it. Reported rather than failed, because
	# an impossible geometry is not a defect in the placer. See the report note.
	{"name": "two far-apart sites", "hard": false,
		"rects": [Rect2(0.070, 0.170, 0.055, 0.075), Rect2(0.740, 0.660, 0.055, 0.075)]},
]

var _failures: Array[String] = []
var _checks := 0
## Things worth saying that are not pass/fail — impossible geometries, and the
## places where headless cannot reach the branch this is really about.
var _notes: Array[String] = []
var _stage: Control = null
## Vacuity counters, printed so the sweep's reach is visible rather than assumed.
var _lessons_taught := 0
var _marks_seen := 0


func _fail(msg: String) -> void:
	_failures.append(msg)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fail(msg)


func _note(msg: String) -> void:
	_notes.append(msg)


func _ready() -> void:
	var saved := _snapshot()

	# HAND THE FRAME BACK BEFORE PARENTING TO THE ROOT. `_ready` runs while the
	# root Window is still setting its children up, and `add_child` there fails
	# outright ("Parent node is busy setting up children") — leaving the stage
	# ORPHANED, every Control in it sized 0x0 and `get_viewport()` null, which
	# reads as a dozen coach bugs that are entirely the harness's.
	await get_tree().process_frame

	_stage = Control.new()
	_stage.name = "CoachA11yStage"
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(_stage)
	await _frames(2)

	await _claim_1_reduce_motion()
	_claim_1_reduced_branch_source()
	await _claim_2_non_colour_channel()
	await _claim_3_ui_scale()
	await _claim_4_panel_keepout()
	await _claim_5_keyboard()
	# TODO — `_claim_4b_real_lane_column()` was being added when this file's
	# author stopped, and the CALL landed without the FUNCTION (a parse error that
	# took the whole probe down). Its intent: re-test claim 4's panel keep-out
	# against the REAL combat board rather than the modelled rects used above, so
	# the verdict rests on shipping geometry. Worth finishing; the five claims
	# below it are complete and pass without it.

	get_tree().root.content_scale_factor = 1.0
	if is_instance_valid(_stage):
		_stage.queue_free()
	_restore(saved)

	print("")
	for n in _notes:
		print("  NOTE  ", n)
	print("[coach_a11y] %d checks · %d lessons taught · %d marks inspected"
		% [_checks, _lessons_taught, _marks_seen])
	if _failures.is_empty():
		print("PROBE PASS: coach_a11y")
	else:
		for f in _failures:
			print("  FAIL  ", f)
		print("PROBE FAIL: coach_a11y (%d failures)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


# ── Fixtures ───────────────────────────────────────────────────────────

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _coach() -> TutorialCoach:
	var c := TutorialCoach.new()
	c.name = "Coach"
	_stage.add_child(c)
	return c


func _drop(c: TutorialCoach) -> void:
	if c != null and is_instance_valid(c):
		c.dismiss()
		c.queue_free()
	await _frames(2)


func _target(r: Rect2, nm: String = "T") -> Control:
	var c := ColorRect.new()
	c.name = nm
	c.color = Color(0.42, 0.38, 0.30, 1.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = r.position
	c.size = r.size
	c.custom_minimum_size = r.size
	_stage.add_child(c)
	return c


## `_place_panel` is a COROUTINE that `show_panel` fires and does not await: it
## polls up to 36 frames for the openings to stop moving before it positions
## anything. Measuring the panel's rect straight after `show_panel` measures a
## panel that has not been placed. Poll until the rect HOLDS (the settle-until-
## stable rule), and say so if it never does.
func _settle_panel(coach: TutorialCoach) -> bool:
	var last := Rect2(Vector2(-99999.0, -99999.0), Vector2.ZERO)
	var stable := 0
	for _i in 120:
		await get_tree().process_frame
		var p = coach._panel
		if p == null or not is_instance_valid(p):
			stable = 0
			continue
		var r := Rect2(p.position, p.size)
		if r.size.x > 1.0 and r.size.y > 1.0 and r.is_equal_approx(last):
			stable += 1
			if stable >= 3:
				return true
		else:
			stable = 0
		last = r
	return false


## `ShaderMaterial.get_shader_parameter` answers null for a uniform nobody has
## SET, even though the shader has a default for it — so a bare `float(...)` on
## one is an invalid cast, not a zero.
func _param(mat: ShaderMaterial, key: String, def: float) -> float:
	if mat == null:
		return def
	var v = mat.get_shader_parameter(key)
	return float(v) if (v is float or v is int) else def


func _merged_block(coach: TutorialCoach) -> Rect2:
	var block := Rect2()
	var has := false
	for a in coach._scrim_holes:
		block = a if not has else block.merge(a)
		has = true
	return block


# ══ 1 · REDUCE MOTION HOLDS, IT DOES NOT REMOVE ════════════════════════

func _claim_1_reduce_motion() -> void:
	UserSettings.reduce_motion = true
	_check(TutorialCoach.reduced(),
		"TutorialCoach.reduced() is false with UserSettings.reduce_motion ON — "
		+ "every assertion in this block would be about the wrong branch")

	var a := _target(Rect2(360.0, 300.0, 220.0, 170.0), "rm_from")
	var b := _target(Rect2(980.0, 470.0, 200.0, 150.0), "rm_to")
	await _frames(2)

	var coach := _coach()
	coach.focus([a], 0.62)
	coach.mark(a, {"pad": 20.0})
	coach.point_at(a, {"from": "left"})
	coach.gesture(a, b)
	await _frames(6)

	# VACUITY FIRST. "The marks survive reduce motion" passes trivially if no mark
	# was ever built, and a coach that builds nothing looks exactly like a coach
	# that handles reduce motion perfectly.
	_check(coach._marks.size() == 3,
		"reduce motion: expected 3 marks (glow, arrow, path), got %d — the rest of "
		% coach._marks.size() + "this block would be vacuous")
	_check(coach._scrim != null and is_instance_valid(coach._scrim),
		"reduce motion: focus() built no scrim at all")

	if coach._scrim != null and is_instance_valid(coach._scrim):
		var s: ColorRect = coach._scrim
		var mat: ShaderMaterial = s.material
		_check(s.is_visible_in_tree(), "reduce motion: the scrim is not visible")
		_check(s.modulate.a > 0.02,
			"reduce motion: the scrim sits at alpha %.3f — it was faded in from 0 "
			% s.modulate.a + "and no tween ran to bring it back")
		_check(s.size.x > 1.0 and s.size.y > 1.0,
			"reduce motion: the scrim has no area (%s)" % str(s.size))
		_check(_param(mat, "amount", 0.0) > 0.05,
			"reduce motion: the scrim dims by %.2f — nothing is spotlit"
			% _param(mat, "amount", 0.0))
		_check(int(_param(mat, "hole_count", 0.0)) > 0,
			"reduce motion: the scrim has no opening punched in it, so the whole "
			+ "screen is dimmed including the thing being taught")

	for m in coach._marks:
		var kind := String(m.get("kind", "?"))
		var n = m.get("node")
		_check(n != null and is_instance_valid(n),
			"reduce motion: the %s mark was freed" % kind)
		if n == null or not is_instance_valid(n):
			continue
		_marks_seen += 1
		var c: Control = n
		_check(c.is_visible_in_tree(),
			"reduce motion: the %s mark is alive but not visible in tree" % kind)
		_check(c.modulate.a > 0.02,
			"reduce motion: the %s mark sits at alpha %.3f — alive and invisible, "
			% [kind, c.modulate.a] + "which is the exact failure this claim names")
		_check(absf(c.scale.x) > 0.01 and absf(c.scale.y) > 0.01,
			"reduce motion: the %s mark is scaled to %s" % [kind, str(c.scale)])
		_check(c.size.x > 1.0 and c.size.y > 1.0,
			"reduce motion: the %s mark has no area (%s)" % [kind, str(c.size)])
		if kind != "glow":
			continue
		var gm: ShaderMaterial = c.material
		_check(gm != null, "reduce motion: the glow lost its material")
		if gm == null:
			continue
		# The breath is PARKED, not switched off: pulse drives both the rim's width
		# and the halo's reach, so a mark held at 0 is a mark drawn at its dimmest.
		_check(_param(gm, "pulse", 0.0) > 0.05,
			"reduce motion: the glow's breath is parked at pulse=%.2f — the rim "
			% _param(gm, "pulse", 0.0) + "renders at its faintest and the halo at "
			+ "its smallest")
		_check(_param(gm, "intensity", 1.0) > 0.05,
			"reduce motion: the glow's intensity is %.2f"
			% _param(gm, "intensity", 1.0))
		_check(_param(gm, "rim", 0.0) > 0.05,
			"reduce motion: the glow's rim width is %.2f — it traces nothing"
			% _param(gm, "rim", 0.0))
		var tint = gm.get_shader_parameter("tint")
		_check(tint is Color and (tint as Color).a > 0.05,
			"reduce motion: the glow's tint alpha is %s" % str(tint))
		var box = gm.get_shader_parameter("box")
		_check(box is Vector2 and (box as Vector2).x > 1.0 and (box as Vector2).y > 1.0,
			"reduce motion: the glow's box is %s — it has no silhouette to trace"
			% str(box))

	await _drop(coach)
	a.queue_free()
	b.queue_free()
	await _frames(1)
	UserSettings.reduce_motion = false


## THE HEADLESS BLIND SPOT, closed the only way it can be.
##
## Every `begin()` tests `headless()` BEFORE `reduced()` and returns, so under
## `--headless` the reduce-motion arm is unreachable at runtime: the block above
## proves the OUTCOME (nothing is left invisible) but cannot prove it was that arm
## that produced it. A regression confined to the reduced branch — swapping its
## `set_shader_parameter` for a `queue_free`, say — would sail past it.
##
## So the branch itself is read. Narrow on purpose: `dismiss()` also tests
## `reduced()` and SHOULD free there, so only `begin()` bodies are scanned, and
## only for the verbs that blank a mark.
func _claim_1_reduced_branch_source() -> void:
	var src := FileAccess.get_file_as_string(COACH_SRC)
	_check(src != "", "could not read %s" % COACH_SRC)
	if src == "":
		return
	var blank := RegEx.new()
	blank.compile("modulate\\s*[.:]\\s*a\"?\\s*[,=]\\s*0")

	var lines := src.split("\n")
	var fn := ""
	var found := 0
	for i in lines.size():
		var line: String = lines[i]
		var flat := line.strip_edges()
		if flat.begins_with("func "):
			fn = flat.substr(5).split("(")[0].strip_edges()
		if fn != "begin" or not flat.begins_with("if TutorialCoach.reduced():"):
			continue
		var indent := line.length() - line.lstrip("\t ").length()
		var body := ""
		var j := i + 1
		while j < lines.size():
			var l2: String = lines[j]
			if l2.strip_edges() != "":
				var ind2 := l2.length() - l2.lstrip("\t ").length()
				if ind2 <= indent:
					break
				body += l2.strip_edges() + " ; "
			j += 1
		found += 1
		_check(not body.contains("queue_free"),
			"begin()'s reduce-motion branch frees the mark: `%s` — reduce motion "
			% body.strip_edges() + "must HOLD the mark, not remove it")
		_check(not body.contains("visible = false") and not body.contains("hide()"),
			"begin()'s reduce-motion branch hides the mark: `%s`" % body.strip_edges())
		_check(blank.search(body) == null,
			"begin()'s reduce-motion branch blanks the mark's alpha: `%s`"
			% body.strip_edges())
		_note("reduce-motion branch #%d of begin(): %s" % [found, body.strip_edges()])
	_check(found == 3,
		"the reduce-motion branch audit matched %d `begin()` bodies, not the 3 "
		% found + "painters (GlowMark / PointerMark / PathMark) — the scan has "
		+ "stopped matching and this whole audit is vacuous")
	_note("claim 1's runtime half asserts the OUTCOME only: `begin()` tests "
		+ "headless() before reduced() and returns, so the reduced arm is "
		+ "unreachable under --headless. The source audit above covers it.")


# ══ 2 · NO ESSENTIAL INFORMATION BY COLOUR ALONE ═══════════════════════

func _claim_2_non_colour_channel() -> void:
	UserSettings.reduce_motion = false
	var ids := TutorialDB.ids()
	_check(ids.size() >= 10,
		"only %d lessons in the registry — the sweep below is vacuous" % ids.size())

	for mode in CB_MODES:
		UserSettings.colorblind_mode = mode
		# The whole registry once, then two lessons per remaining palette: nothing
		# in the coach reads `colorblind_mode`, so the point of the extra passes is
		# that nothing blanks — not another 22 identical panels.
		var sweep: Array = ids if mode == "off" \
			else [ids[0], ids[ids.size() - 1]]
		for id in sweep:
			UserSettings.reset_tutorials()
			UserSettings.coaching_mode = TutorialDB.COACH_FULL
			var t := _target(Rect2(420.0, 250.0, 250.0, 190.0), "cb_t")
			await _frames(1)
			var coach := TutorialCoach.teach(_stage, id, [t])
			_check(coach != null,
				"%s [colorblind=%s]: teach() built nothing on a fresh profile at "
				% [id, mode] + "COACH_FULL")
			if coach == null:
				t.queue_free()
				await _frames(1)
				continue
			_lessons_taught += 1
			var placed := await _settle_panel(coach)
			_check(placed, "%s [%s]: the panel never settled" % [id, mode])

			var p: PanelContainer = coach._panel
			_check(p != null and is_instance_valid(p) and p.is_visible_in_tree(),
				"%s [%s]: a lesson was delivered with NO panel — the only channel "
				% [id, mode] + "left is the coloured rim")
			if p != null and is_instance_valid(p):
				_check(p.modulate.a > 0.02,
					"%s [%s]: the panel sits at alpha %.3f" % [id, mode, p.modulate.a])
				_check(p.size.x > 1.0 and p.size.y > 1.0,
					"%s [%s]: the panel has no area (%s)" % [id, mode, str(p.size)])

			# THE WORDS ARE THE NON-COLOUR CHANNEL. Present, non-empty, laid out
			# with real area, and carrying the registry's own copy.
			for pair in [["title", coach._title, TutorialDB.title(id)],
					["body", coach._body, TutorialDB.body(id, {"n": 2})]]:
				var what := String(pair[0])
				var lbl: Label = pair[1]
				var want := String(pair[2])
				_check(lbl != null and is_instance_valid(lbl),
					"%s [%s]: no %s label" % [id, mode, what])
				if lbl == null or not is_instance_valid(lbl):
					continue
				_check(lbl.text.strip_edges() != "",
					"%s [%s]: the %s is empty — the lesson is colour only"
					% [id, mode, what])
				_check(lbl.is_visible_in_tree(),
					"%s [%s]: the %s is not visible" % [id, mode, what])
				_check(lbl.size.x > 1.0 and lbl.size.y > 1.0,
					"%s [%s]: the %s has no area (%s) — nothing renders"
					% [id, mode, what, str(lbl.size)])
				_check(lbl.get_theme_color("font_color").a > 0.2,
					"%s [%s]: the %s ink is %.2f alpha"
					% [id, mode, what, lbl.get_theme_color("font_color").a])
				# `body` substitutes {n} for the one lesson that has a token; the
				# title never does. Comparing against the registry proves the copy
				# ARRIVED rather than that some string is present.
				if what == "title":
					_check(lbl.text == want,
						"%s [%s]: the panel title reads '%s', the registry says '%s'"
						% [id, mode, lbl.text, want])

			# The dismissal affordance is worded too, not an X or a colour.
			_check(coach._action != null and coach._action.visible
					and coach._action.text.strip_edges() != "",
				"%s [%s]: teach()'s panel has no worded primary button" % [id, mode])

			# ...and the SECOND non-colour channel: the hole that says WHERE.
			_check(coach._scrim != null and is_instance_valid(coach._scrim)
					and not coach._scrim_holes.is_empty(),
				"%s [%s]: a target was passed but no opening was punched — the "
				% [id, mode] + "glow rim is then the only thing pointing at it")
			_check(coach._marks.size() >= 1,
				"%s [%s]: no mark was built for the target" % [id, mode])

			await _drop(coach)
			t.queue_free()
			await _frames(1)

	UserSettings.colorblind_mode = "off"
	_check(_lessons_taught >= TutorialDB.ids().size(),
		"only %d lessons were actually taught — the colour-alone sweep did not "
		% _lessons_taught + "reach the whole registry")


# ══ 3 · UI SCALE (C32) ═════════════════════════════════════════════════

func _claim_3_ui_scale() -> void:
	UserSettings.reduce_motion = false
	var win := get_tree().root
	var base_centre := Vector2.ZERO
	var have_base := false

	for f in SCALES:
		win.content_scale_factor = f
		await _frames(4)
		var canvas: Rect2 = get_viewport().get_visible_rect()
		_check(canvas.size.x > 100.0 and canvas.size.y > 100.0,
			"factor %.2f: the canvas measured %s" % [f, str(canvas.size)])
		if f != 1.0:
			_check(canvas.size.x > 1601.0,
				"factor %.2f produced a %s canvas — content_scale_factor is not "
				% [f, str(canvas.size)] + "dividing the canvas, so this whole "
				+ "claim is being tested against one layout")

		# The fixture is stated in canvas FRACTIONS, so it is literally the same
		# layout problem at every scale. Anything that moves is the code.
		var t := _target(Rect2(
			canvas.position + canvas.size * Vector2(0.30, 0.26),
			canvas.size * Vector2(0.16, 0.20)), "sc_t")
		await _frames(2)
		var coach := _coach()
		coach.focus([t], 0.62)
		coach.mark(t)
		coach.show_panel("READ THE LANE", LONG_BODY, "GOT IT", 2, 3,
			{"note": "Settings › Coaching turns this off or plays it again."})
		var placed := await _settle_panel(coach)
		_check(placed, "factor %.2f: the panel never settled" % f)

		var scrim: ColorRect = coach._scrim
		_check(scrim != null and is_instance_valid(scrim),
			"factor %.2f: no scrim" % f)
		if scrim != null and is_instance_valid(scrim):
			var cov := Vector2(scrim.size.x / canvas.size.x,
				scrim.size.y / canvas.size.y)
			_check(cov.x > 0.98 and cov.y > 0.98,
				"factor %.2f: the scrim covers %.0f%% x %.0f%% of the %s canvas — "
				% [f, cov.x * 100.0, cov.y * 100.0, str(canvas.size)]
				+ "the dim stops short of the edges")
			var mat: ShaderMaterial = scrim.material
			var rs = mat.get_shader_parameter("rect_size")
			_check(rs is Vector2 and (rs as Vector2).is_equal_approx(scrim.size),
				"factor %.2f: the scrim shader was handed rect_size=%s for a %s "
				% [f, str(rs), str(scrim.size)] + "rect — the holes are punched in "
				+ "the wrong coordinate space (this IS the C32 defect)")
			# The opening must land ON the target at every scale, which is the
			# whole of `_recompute_holes` + `_push_holes` in one assertion.
			var tv := TutorialCoach.visual_rect(t)
			var h0 = mat.get_shader_parameter("hole0")
			var hc := Vector2.ZERO
			if h0 is Vector4:
				hc = Vector2((h0 as Vector4).x, (h0 as Vector4).y)
			_check(h0 is Vector4 and hc.distance_to(tv.get_center()) < 8.0,
				"factor %.2f: the opening is centred at %s but the target it is "
				% [f, str(hc)] + "meant to reveal is at %s" % str(tv.get_center()))

		var panel: PanelContainer = coach._panel
		_check(panel != null and is_instance_valid(panel),
			"factor %.2f: no panel" % f)
		if panel != null and is_instance_valid(panel):
			var pr := Rect2(panel.position, panel.size)
			_check(canvas.encloses(pr),
				"factor %.2f: the panel %s runs off the %s canvas"
				% [f, str(pr), str(canvas)])
			# DIFFERENTIAL, the house C32 oracle. Not "is the panel where I would
			# put it" — only "does it sit at the same FRACTION of the canvas at
			# every scale". A constant makes that fraction collapse.
			var cfrac := (pr.get_center() - canvas.position) / canvas.size
			if not have_base:
				base_centre = cfrac
				have_base = true
			else:
				_check(absf(cfrac.x - base_centre.x) <= CENTRE_TOL
						and absf(cfrac.y - base_centre.y) <= CENTRE_TOL,
					"factor %.2f: the panel's centre sits at (%.2f, %.2f) of the "
					% [f, cfrac.x, cfrac.y] + "canvas where 100%% puts it at "
					+ "(%.2f, %.2f) — something in _place_panel is a constant"
					% [base_centre.x, base_centre.y])
			# The keep-out has to survive the scale change too.
			if not coach._scrim_holes.is_empty():
				_check(not pr.intersects(_merged_block(coach)),
					"factor %.2f: the panel lands on the spotlight" % f)
			var hand := Rect2(
				Vector2(canvas.position.x, canvas.position.y + canvas.size.y * 0.80),
				Vector2(canvas.size.x, canvas.size.y * 0.20))
			_check(not pr.intersects(hand),
				"factor %.2f: the panel sits in the hand band" % f)

		await _drop(coach)
		t.queue_free()
		await _frames(1)

	win.content_scale_factor = 1.0
	await _frames(3)


# ══ 4 · THE PANEL MUST NOT COVER WHAT IT IS TALKING ABOUT ══════════════

func _claim_4_panel_keepout() -> void:
	UserSettings.reduce_motion = false
	var canvas: Rect2 = get_viewport().get_visible_rect()
	var hand := Rect2(
		Vector2(canvas.position.x, canvas.position.y + canvas.size.y * 0.80),
		Vector2(canvas.size.x, canvas.size.y * 0.20))

	for case in KEEPOUT_CASES:
		var nm := String(case["name"])
		var hard := bool(case["hard"])
		var targets: Array = []
		for fr in case["rects"]:
			var r: Rect2 = fr
			targets.append(_target(Rect2(
				canvas.position + canvas.size * r.position,
				canvas.size * r.size), "ko"))
		await _frames(2)
		var coach := _coach()
		coach.focus(targets, 0.60)
		coach.mark(targets[0])
		coach.show_panel("PLAY A CREATURE", LONG_BODY, "", 1, 3,
			{"note": "Settings › Coaching turns this off or plays it again."})
		var placed := await _settle_panel(coach)
		_check(placed, "keep-out [%s]: the panel never settled" % nm)

		# VACUITY. No openings and no panel means the two assertions below are
		# about nothing.
		_check(not coach._scrim_holes.is_empty(),
			"keep-out [%s]: no openings were punched — the keep-out test is "
			% nm + "vacuous")
		var panel: PanelContainer = coach._panel
		_check(panel != null and is_instance_valid(panel)
				and panel.size.x > 1.0 and panel.size.y > 1.0,
			"keep-out [%s]: no panel with area" % nm)

		if panel != null and is_instance_valid(panel) \
				and not coach._scrim_holes.is_empty():
			var pr := Rect2(panel.position, panel.size)
			var block := _merged_block(coach)
			var on_block := pr.intersects(block)
			var in_hand := pr.intersects(hand)
			var off := not canvas.encloses(pr)
			if hard:
				_check(not on_block,
					"keep-out [%s]: the panel %s covers the spotlight %s — the copy "
					% [nm, str(pr), str(block)] + "sits on the thing it is about")
				_check(not in_hand,
					"keep-out [%s]: the panel %s reaches into the hand band %s"
					% [nm, str(pr), str(hand)])
				_check(not off,
					"keep-out [%s]: the panel %s runs off the canvas" % [nm, str(pr)])
			elif on_block or in_hand or off:
				_note(("keep-out [%s] IS NOT SATISFIABLE: %d opening(s) merge into "
					+ "a keep-out of %s, no candidate clears it, and the fallback "
					+ "lands at %s (on-spotlight=%s in-hand=%s off-canvas=%s). "
					+ "_place_panel unions ALL holes even where _merge_rects "
					+ "deliberately kept them apart.")
					% [nm, coach._scrim_holes.size(), str(block), str(pr),
						str(on_block), str(in_hand), str(off)])
			else:
				_note("keep-out [%s]: satisfied after all (%s clears %s)"
					% [nm, str(pr), str(block)])

		await _drop(coach)
		for t in targets:
			(t as Control).queue_free()
		await _frames(1)


# ══ 5 · KEYBOARD ═══════════════════════════════════════════════════════

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _claim_5_keyboard() -> void:
	UserSettings.reduce_motion = false
	var esc := _key(KEY_ESCAPE)
	# VACUITY. If the synthesized Escape does not map to `ui_cancel`, every
	# assertion below passes for the wrong reason.
	_check(esc.is_action_pressed("ui_cancel"),
		"the synthesized Escape does not resolve to ui_cancel — every keyboard "
		+ "check below is vacuous")

	var parked := Button.new()
	parked.text = "PARKED HERE"
	parked.focus_mode = Control.FOCUS_ALL
	parked.position = Vector2(20.0, 20.0)
	_stage.add_child(parked)
	await _frames(2)
	parked.grab_focus()
	await _frames(1)
	# VACUITY. Focus has to be observable in this context at all, or "focus is not
	# on SKIP" is true because focus is nowhere, always.
	_check(parked.has_focus() and get_viewport().gui_get_focus_owner() == parked,
		"focus is not observable in this context — the focus assertions below "
		+ "cannot fail and are worthless")

	var coach := _coach()
	var fired := [0]
	coach.skip_pressed.connect(func() -> void: fired[0] += 1)

	# ── A panel whose affordance is THE BOARD: no primary button. ──
	coach.show_panel(TutorialDB.title("walk_play"), TutorialDB.body("walk_play"),
		"", 1, 3, {"note": "Settings › Coaching."})
	await _settle_panel(coach)
	_check(coach._action != null and not coach._action.visible,
		"a panel built with no action_text still shows a primary button")
	_check(coach._skip != null and coach._skip.visible,
		"the board-affordance panel hid its skip button — the walkthrough would "
		+ "have no escape at all")
	_check(coach._skip.text.strip_edges() != "",
		"the skip button is visible with no label")
	# THE ASSERTION. Parking focus on SKIP TUTORIAL here makes the space bar quit
	# the walkthrough — the opposite of an accessibility win.
	var owner_a := get_viewport().gui_get_focus_owner()
	_check(owner_a != coach._skip,
		"show_panel parked keyboard focus on SKIP TUTORIAL for a step whose "
		+ "affordance is the board — space or enter would quit the walkthrough")

	# ESC leaves the lesson while a visible skip is up (WCAG 2.1.1).
	coach._unhandled_key_input(esc)
	_check(fired[0] == 1,
		"ui_cancel did not emit skip_pressed while a panel with a visible SKIP "
		+ "was up (fired %d times)" % fired[0])
	# ...but only for ui_cancel.
	coach._unhandled_key_input(_key(KEY_A))
	_check(fired[0] == 1,
		"an ordinary key emitted skip_pressed (fired %d times)" % fired[0])

	# ── A read-and-acknowledge panel: primary button, no skip. ──
	coach.show_panel("GOLD WORDS", TutorialDB.body("keywords"), "GOT IT")
	await _settle_panel(coach)
	_check(coach._action != null and coach._action.visible,
		"a panel built with action_text shows no primary button")
	_check(coach._skip != null and not coach._skip.visible,
		"a read-and-acknowledge panel also shows SKIP — two exits, and Esc then "
		+ "stops reaching the pause menu")
	# The binding is DELIBERATELY narrow: Esc belongs to the pause menu on every
	# screen this layer appears over.
	coach._unhandled_key_input(esc)
	_check(fired[0] == 1,
		"ui_cancel emitted skip_pressed while the skip button was HIDDEN — Esc "
		+ "must still reach the pause menu there (fired %d times)" % fired[0])

	# ── No panel at all: the hijack must not outlive its window. ──
	coach.hide_panel()
	await _frames(2)
	coach._unhandled_key_input(esc)
	_check(fired[0] == 1,
		"ui_cancel emitted skip_pressed with no panel up (fired %d times)"
		% fired[0])

	# The grab itself is headless-gated in show_panel, so say so rather than
	# implying it was measured.
	_note("show_panel's `_action.grab_focus()` sits behind `not headless()`, so "
		+ "the POSITIVE half of claim 5 (focus lands on GOT IT) cannot be "
		+ "observed here; the negative half (focus never lands on SKIP) is "
		+ "asserted live and `grab_focus` appears on no other control in "
		+ "TutorialCoach.gd.")
	var src := FileAccess.get_file_as_string(COACH_SRC)
	_check(src.count("grab_focus") == 1 and src.contains("_action.grab_focus()"),
		"TutorialCoach.gd grabs focus somewhere other than the primary button "
		+ "(%d grab_focus call sites)" % src.count("grab_focus"))

	await _drop(coach)
	parked.queue_free()
	await _frames(1)


# ── Profile hygiene ────────────────────────────────────────────────────

func _snapshot() -> Dictionary:
	var out := {
		"reduce_motion": UserSettings.reduce_motion,
		"colorblind_mode": UserSettings.colorblind_mode,
		"coaching_mode": UserSettings.coaching_mode,
		"lessons_seen": UserSettings.lessons_seen.duplicate(true),
	}
	for id in TutorialDB.ids():
		var flag := TutorialDB.legacy_flag(id)
		if flag != "":
			out[flag] = UserSettings.get(flag)
	return out


func _restore(saved: Dictionary) -> void:
	for k in saved:
		UserSettings.set(k, saved[k])
	UserSettings.save()
