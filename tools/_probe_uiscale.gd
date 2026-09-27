extends SceneTree
## _probe_uiscale.gd — CLASS C32: THE LAYOUT THAT ONLY WORKS AT 100%.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_uiscale.gd
##
## Every layout gate in this repo runs at ONE viewport: the 1600×900 project
## canvas. The player can change that. `SettingsOverlay._add_ui_scale_row` offers
## UI Scale 60–100%, which sets `Window.content_scale_factor`, and under
## `canvas_items` stretch that DIVIDES the logical canvas — at 60% the UI lays
## itself out on 2667×1500, not 1600×900.
##
## Anything positioned from a CONSTANT rather than from the live viewport is
## therefore wrong at four of the five settings the player is offered, and no
## gate could see it. That is not hypothetical: the shell's decorative frame
## (`GameTheme._make_decorative_frame`) placed its corners from
## `ProjectSettings` — a static number — so at 60% it drew 1876×877 inside a
## 2667×1500 canvas and the border sat in the top-left corner with the painted
## background running out from under it on two sides, on every screen with
## atmosphere.
##
## THE ORACLE IS DIFFERENTIAL, which is what makes it need no taste (the C27
## idea, applied to scale). It does not ask "should this screen fill the canvas"
## — some screens are a small centred dialog and should not. It asks whether a
## screen covers the SAME FRACTION of the canvas at every scale. A screen that
## covers 99% at 100% and 70% at 60% has something pinned to a constant, and
## the drop is the measurement. No knowledge of the intended design is needed.

const SCALES := [1.0, 0.8, 0.6]
const DROP_TOL := 0.10        # 10 percentage points of canvas coverage
## How far a REPEAT of the same 1.00 measurement may move before the baseline is
## called unreproducible. Much tighter than DROP_TOL, because re-measuring the
## same screen at the same factor off the same seed should land on the same
## number — but not zero, or jitter would cry LEAK over a real finding.
##
## MEASURED, not guessed, by re-arming both defects and reading the numbers off:
## the coaching leak moves `event` by 1.3pp (92.4% -> 91.1%), and the only other
## thing that moves at all is the credits roll at a steady 0.8pp, which is why
## that one is named in DRIFT_WAIVERS rather than absorbed here. 0.5pp sits under
## the signal and over everything else that was observed to move.
const CONFIRM_TOL := 0.005
const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const SEED := 606061

## KNOWN AND UNFIXED — visible debt, not absolution. Keyed "screen::axis".
## An entry here is VISIBLE DEBT, not absolution.
##
## ── THE CENTRED-CONTENT RESIDUAL (2026-09-19) ────────────────────────────────
##
## These three were found by this gate, diagnosed with the edge reporting added
## the same day, and are waived on a MEASUREMENT rather than a judgement. All
## three show one signature:
##
##   screen      1.00                    0.60
##   net_lobby   top=Panel @14  bot @739  top=Panel @14  bot @1039
##   treasure    top=Panel @14  bot @857  top=Panel @14  bot @1157
##   recruit     top=Panel @14  bot @746  top=Panel @14  bot @1046
##
## The top edge is the SAME node at the SAME y at both scales — a pinned 14px
## margin. The bottom edge moves **exactly +300** on all three, which is HALF the
## canvas growth (900 -> 1500): the signature of content that is CENTRED and whose
## own size does not scale. So the containing rect already follows the canvas
## (net_lobby's flanking plates and centre column were taught to, that same day,
## and its x-axis drop was fixed by it) — what does not follow is the CONTENT
## inside it: fonts, a 225x300 card wrapper, portrait wells.
##
## Closing these therefore means deciding whether a card, a portrait and a font
## should grow with UI Scale. That changes bake sizes and runs straight into
## COPY_STYLE §11's reading floors, so it is a DESIGN call and not a defect to be
## quietly patched by a gate-fixing pass. The three candidate fixes, for whoever
## takes it: (a) bottom-anchor each footer so it tracks the canvas floor,
## (b) scale content metrics with `GameTheme.canvas_scale`, (c) accept the band.
##
## REMOVE THESE ENTRIES the moment any of those lands — the gate is the only thing
## that will notice if a fix half-works.
const WAIVERS := {
	"net_lobby::y": true,
	"treasure::y": true,
	"recruit::y": true,
}

## SCREENS WHOSE MEASUREMENT IS NOT REPRODUCIBLE, exempted from the confirming
## pass only (never from the drop oracle). Same "visible debt" contract.
##
## `credits` ROLLS. `Credits._roll_hold` is 1.2s and `_measure` settles 1.3s, so
## this gate samples the roll 0.1s after it starts moving — and how far it has
## moved by then depends on how many frames fit in that wall-clock window, which
## the FIRST build in a process (cold shaders, cold fonts, cold scene parse) does
## not match. Measured at a dead-steady 98.7% -> 97.9% on a repeat, IDENTICAL
## across two separate runs: deterministic, ~0.8pp, and an artifact of sampling
## something in motion rather than anything wrong with the screen. It is far
## under DROP_TOL, so it has never affected a verdict.
##
## Waived rather than absorbed into a looser CONFIRM_TOL on purpose: the coach
## contamination this guard was built for measures 1.3pp on `event`, so a
## threshold lifted over the 0.8pp roll would be sitting directly under the only
## signal it exists to catch. One named exception beats a threshold tuned until
## nothing fires.
const DRIFT_WAIVERS := {"credits::y": true}

var RS: Node
var US: Node
var _started := false
var _done := false
var _hits := 0
var _leaks := 0
var _canvas := Vector2(1600, 900)
## "<screen>::<canvas.x>" -> {top,bottom,left,right} node descriptions, so a
## finding can name the rect to fix instead of only the screen it is on.
var _edges: Dictionary = {}
var _last_edges: Dictionary = {}


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _settle(sec: float = 1.3) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		await create_timer(0.02).timeout
		t += 0.02


## The fraction of the canvas the screen's INK spans, per axis.
##
## Containers draw nothing and a full-rect backdrop would report 100% for every
## screen at every scale, hiding exactly what this looks for — both are skipped.
## Content scrolled past the viewport edge is clamped rather than counted, so a
## long Collection list does not read as 1700% coverage.
func _coverage(node: Node, canvas: Vector2) -> Vector2:
	var used := Rect2()
	var any := false
	var stack: Array = [node]
	while not stack.is_empty():
		var x = stack.pop_front()
		for c in x.get_children():
			stack.push_back(c)
		if not (x is Control):
			continue
		var c2: Control = x
		if not c2.is_visible_in_tree() or c2 is Container:
			continue
		if c2.get_class() == "Control" and c2.get_script() == null:
			continue
		var r := c2.get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		if r.size.x >= canvas.x * 0.98 and r.size.y >= canvas.y * 0.98:
			continue
		r = r.intersection(Rect2(Vector2.ZERO, canvas))
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		used = r if not any else used.merge(r)
		any = true
	if not any:
		return Vector2.ZERO
	return Vector2(used.size.x / canvas.x, used.size.y / canvas.y)


## WHICH NODES DEFINE THE EXTREMES (2026-09-19).
##
## "y coverage falls 81% -> 68%" names a screen and not a node, and the fix is
## always one specific rect — so acting on a finding meant re-deriving this walk by
## hand every time. Worse, it made the WRONG diagnosis cheap to reach: after the
## flanking plates and centre column of net_lobby were both taught to follow the
## canvas, the residual drop was assumed to be fixed-size CONTENT and nearly
## waived on that reasoning, with nothing measured. Naming the four extreme
## contributors turns each finding into an address.
##
## Mirrors `_coverage`'s filters exactly — if the two ever disagree, this reports
## a node the coverage number did not count.
func _extremes(node: Node, canvas: Vector2) -> Dictionary:
	var best := {"top": null, "bottom": null, "left": null, "right": null}
	var val := {"top": INF, "bottom": -INF, "left": INF, "right": -INF}
	var stack: Array = [node]
	while not stack.is_empty():
		var x = stack.pop_front()
		for c in x.get_children():
			stack.push_back(c)
		if not (x is Control):
			continue
		var c2: Control = x
		if not c2.is_visible_in_tree() or c2 is Container:
			continue
		if c2.get_class() == "Control" and c2.get_script() == null:
			continue
		var r := c2.get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		if r.size.x >= canvas.x * 0.98 and r.size.y >= canvas.y * 0.98:
			continue
		r = r.intersection(Rect2(Vector2.ZERO, canvas))
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.y < val["top"]:
			val["top"] = r.position.y; best["top"] = c2
		if r.end.y > val["bottom"]:
			val["bottom"] = r.end.y; best["bottom"] = c2
		if r.position.x < val["left"]:
			val["left"] = r.position.x; best["left"] = c2
		if r.end.x > val["right"]:
			val["right"] = r.end.x; best["right"] = c2
	var out := {}
	for k in best:
		var n: Control = best[k]
		out[k] = "-" if n == null else "%s(%s) @%.0f" % [
			n.get_class(), n.name, float(val[k])]
	return out


func _stage(hero_i: int) -> void:
	seed(SEED)
	RS.start_new_run(HEROES[hero_i % HEROES.size()], 0, SEED)
	RS.gold = 800
	RS.hero_hp = RS.hero_max_hp


func _measure(path: String, hero_i: int, canvas: Vector2) -> Vector2:
	_stage(hero_i)
	var n = load(path).instantiate()
	root.add_child(n)
	await _settle()
	var cov := Vector2.ZERO
	if is_instance_valid(n):
		cov = _coverage(n, canvas)
		# Who defined each edge. Handed back through a member because the node is
		# freed on the next line, and the SCREEN NAME this belongs to is only known
		# one frame up in `_sweep`.
		_last_edges = _extremes(n, canvas)
		n.queue_free()
	await process_frame
	return cov


## Measure EVERY state this gate knows about at whatever `content_scale_factor`
## is currently set. One function, so the 1.00 baseline, the comparison scales and
## the confirming re-run are the same code rather than three spellings of it —
## the comparison used to be written twice (once for the flat table, once for the
## staged states), which is two implementations of one judgement with nothing
## keeping them equal.
func _sweep(screens: Array, EDB: Node, canvas: Vector2, announce: bool) -> Dictionary:
	var out := {}
	for row in screens:
		var nm := String(row[0])
		var cov: Vector2 = await _measure(String(row[1]), int(row[2]), canvas)
		out[nm] = cov
		_edges["%s::%.2f" % [nm, canvas.x]] = _last_edges.duplicate()
		if announce:
			print("    %-12s coverage %3.0f%% x %3.0f%%"
				% [nm, cov.x * 100.0, cov.y * 100.0])
	for extra in await _extra_states(EDB, canvas):
		var xnm := String(extra["name"])
		var xcov: Vector2 = extra["cov"]
		out[xnm] = xcov
		if announce:
			print("    %-12s coverage %3.0f%% x %3.0f%%"
				% [xnm, xcov.x * 100.0, xcov.y * 100.0])
	return out


## Every screen whose coverage FELL against the baseline by more than the
## tolerance, as printable lines.
func _findings(base: Dictionary, cov: Dictionary, scale: float) -> Array:
	var out: Array = []
	for nm in cov:
		var b: Vector2 = base.get(nm, Vector2.ZERO)
		var c: Vector2 = cov[nm]
		for axis in ["x", "y"]:
			var bv: float = b.x if axis == "x" else b.y
			var cv: float = c.x if axis == "x" else c.y
			if bv - cv <= DROP_TOL or WAIVERS.has("%s::%s" % [nm, axis]):
				continue
			out.append("%-12s factor %.2f: %s coverage falls %.0f%% -> %.0f%%"
				% [nm, scale, axis, bv * 100.0, cv * 100.0])
			# The address. Without this a finding names a screen and the reader
			# re-derives the walk by hand — which is how the net_lobby residual
			# was nearly waived on an unmeasured guess about fixed-size content.
			var lo := "top" if axis == "y" else "left"
			var hi := "bottom" if axis == "y" else "right"
			var be: Dictionary = _edges.get("%s::%.2f" % [nm, _canvas.x], {})
			var ce: Dictionary = _edges.get(
				"%s::%.2f" % [nm, _canvas.x / scale], {})
			if not be.is_empty() and not ce.is_empty():
				out.append("               1.00 %s=%s  %s=%s"
					% [lo, be.get(lo, "?"), hi, be.get(hi, "?")])
				out.append("               %.2f %s=%s  %s=%s"
					% [scale, lo, ce.get(lo, "?"), hi, ce.get(hi, "?")])
	return out


## How far a repeat of the SAME measurement moved. Anything here means the
## baseline this gate judged everything against is not reproducible.
func _drift(base: Dictionary, again: Dictionary) -> Array:
	var out: Array = []
	for nm in again:
		var b: Vector2 = base.get(nm, Vector2.ZERO)
		var a: Vector2 = again[nm]
		for axis in ["x", "y"]:
			var bv: float = b.x if axis == "x" else b.y
			var av: float = a.x if axis == "x" else a.y
			if absf(bv - av) <= CONFIRM_TOL or DRIFT_WAIVERS.has("%s::%s" % [nm, axis]):
				continue
			out.append("%-12s %s baseline moved %.1f%% -> %.1f%% on a REPEAT at 1.00"
				% [nm, axis, bv * 100.0, av * 100.0])
	return out


## Combat and an event, which need staging rather than a bare `instantiate`.
func _extra_states(EDB: Node, canvas: Vector2) -> Array:
	var out: Array = []
	if EDB != null and EDB.ENCOUNTERS.has("goblin_scouts"):
		_stage(0)
		RS.current_encounter_id = "goblin_scouts"
		RS.current_node_type = "combat"
		var cb = load("res://scenes/combat.tscn").instantiate()
		root.add_child(cb)
		await _settle(6.0)
		if is_instance_valid(cb):
			out.append({"name": "combat", "cov": _coverage(cb, canvas)})
			cb.queue_free()
		await _settle(0.3)

	var EvScript = load("res://scripts/scenes/Event.gd")
	var ev_id := "the_bee_wife"
	if EvScript != null and EvScript.EVENTS.has(ev_id):
		_stage(1)
		var ev = load("res://scenes/event.tscn").instantiate()
		root.add_child(ev)
		await process_frame
		ev._clear_ui()
		ev._event_id = ev_id
		ev._event_data = EvScript.EVENTS[ev_id].duplicate(true)
		ev._current_node = ev._event_data
		ev._build_ui()
		await _settle(1.5)
		if is_instance_valid(ev):
			out.append({"name": "event", "cov": _coverage(ev, canvas)})
			ev.queue_free()
		await process_frame

	# ── RUN SETUP, which is a SUBSCREEN and was therefore never measured ──
	#
	# The table in _run() loads `main_menu.tscn` flat, and a flat load only ever
	# shows the TITLE COLUMN. Every screen MainMenu builds programmatically over
	# that background — run setup, the quick march, the writ pickers — was
	# invisible to this gate, so the screen carrying all four run decisions had
	# never been measured at any scale. That is a bad gap for exactly this class:
	# run setup is laid out from width CONSTANTS (roster 430, banner column 296,
	# the rect itself 1540×780), which is the precise shape C32 exists to catch.
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm)
	await _settle(1.4)
	# MEASURE THE PANEL, NOT THE SCENE. Handing _coverage the whole MainMenu reads
	# 99% at every scale and passes — but that number is the DECORATIVE FRAME,
	# which was rebuilt on anchors in 2026-09-03 and already follows the canvas.
	# The frame's ink swamps the subscreen's, so the muster panel could be pinned
	# to any constant at all and the bounding box would not move. That is the
	# sensitivity limit in this file's own header ("catches a layout pinned
	# WHOLESALE, not one piece of it"), and measuring the scene here would have
	# shipped a gate that cannot open.
	if is_instance_valid(mm) and mm.has_method("_show_hero_select"):
		mm.call("_show_hero_select")
		await _settle(1.6)
		var panel: Control = mm.get_node_or_null("Menu")
		if is_instance_valid(panel):
			out.append({"name": "run_setup", "cov": _coverage(panel, canvas)})
	if is_instance_valid(mm):
		mm.queue_free()
	await process_frame
	return out


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	if RS == null or US == null:
		print("[uiscale] FATAL: autoloads missing"); _done = true; quit(1); return
	US.anim_speed = 3.0
	# COACHING OFF, OR THE 1.00 BASELINE MEASURES AN OVERLAY (2026-09-15).
	#
	# A lesson fires the first time its subject is on screen and is then spent for
	# the whole process. SCALES runs 1.0 FIRST, so the baseline row — the one every
	# other scale is judged against — is the only row that ever contains a coaching
	# panel, on shop, recruit, rest, event and combat. That inflates `base` and
	# never `cov`, so `drop = base - cov` grows: a FALSE-POSITIVE source, invisible
	# today only because those screens already saturate the canvas at 97–100% and
	# the panel cannot widen a union that is already full.
	#
	# OFF rather than `reset_tutorials()` per pass, which is the opposite of the
	# call made in `_probe_settings_differential` the same day, and deliberately.
	# That gate's oracle is a text SET, where the panel's words are additive and
	# worth diffing. This one merges ink into a BOUNDING-BOX UNION, where an
	# overlay is a confound rather than content — and the panel's own behaviour at
	# these exact three factors is already gated by `_probe_coach_a11y`. This gate
	# measures the SCREEN; let the dedicated one measure the thing drawn over it.
	US.coaching_mode = TutorialDB.COACH_OFF
	print("[uiscale] CLASS C32 — the layout that only works at 100%\n")

	var screens := [
		["main_menu", "res://scenes/main_menu.tscn", 0],
		["collection", "res://scenes/collection.tscn", 0],
		["credits", "res://scenes/credits.tscn", 0],
		["net_lobby", "res://scenes/net_lobby.tscn", 0],
		["reward", "res://scenes/reward.tscn", 1],
		["shop", "res://scenes/shop.tscn", 2],
		["rest", "res://scenes/rest.tscn", 3],
		["treasure", "res://scenes/treasure.tscn", 3],
		["recruit", "res://scenes/recruit.tscn", 4],
		["game_over", "res://scenes/game_over.tscn", 4],
	]

	# COMBAT AND EVENT ARE THE DENSEST LAYOUTS IN THE GAME and the ones a player
	# spends the most time in front of, so they are worth the extra seconds here.
	# Combat especially: CLAUDE.md's standing rule is that its HUD positions must
	# derive from `size.x`, and this is the only gate that can prove they do.
	var EDB := root.get_node_or_null("EncounterDB")
	var base := {}
	var findings: Array = []
	for scale in SCALES:
		root.content_scale_factor = float(scale)
		await process_frame
		var canvas: Vector2 = root.get_visible_rect().size
		if scale == 1.0:
			_canvas = canvas
		print("  factor %.2f  canvas %s" % [scale, str(canvas)])
		var cov := await _sweep(screens, EDB, canvas, scale == 1.0)
		if scale == 1.0:
			base = cov
			continue
		findings.append_array(_findings(base, cov, float(scale)))

	# ── THE CONFIRMING PASS AT 1.00 ──────────────────────────────────────────
	#
	# Every number above is a comparison against ONE baseline row, measured once,
	# at the first factor in SCALES — and the gate's whole claim is that a drop
	# from it was caused by the SCALE. That rests on an assumption it never
	# checked: that measuring the same screen twice gives the same number.
	# Once-per-process content breaks it. The coaching panel fires on first sight
	# of its subject and is spent for the rest of the run, so before this file
	# turned coaching off, the 1.00 row was the ONLY row that could contain one —
	# inflating `base`, never `cov`, and so inflating every drop measured from it.
	#
	# Coaching is handled now, but the CLASS is not, and the next piece of
	# once-per-process state will land here silently the same way. So on a
	# finding — and only on a finding, because this re-measures all 13 states —
	# the 1.00 sweep is run AGAIN, last instead of first, and must reproduce
	# itself. If it does not, the baseline is not a baseline and the drops below
	# are unsafe to read as layout defects.
	#
	# Both lists are printed either way. A confirming pass that cried LEAK over
	# ordinary measurement noise would otherwise SWALLOW a real finding, which is
	# a worse failure than the one it exists to prevent — so it reframes the
	# findings, it never hides them.
	var drift: Array = []
	if not findings.is_empty():
		root.content_scale_factor = 1.0
		await process_frame
		drift = _drift(base, await _sweep(screens, EDB, root.get_visible_rect().size, false))
	root.content_scale_factor = 1.0

	for d in drift:
		_leaks += 1
		print("  LEAK  %s" % d)
	if not drift.is_empty():
		print("        the 1.00 baseline is ORDER-DEPENDENT, so the finding(s)")
		print("        below are NOT trustworthy as scale defects. Fix the probe.")
	for f in findings:
		_hits += 1
		print("  %s  %s" % ["hit? " if not drift.is_empty() else "HIT  ", f])
	if _hits > 0 and drift.is_empty():
		print("        something on these screens is placed from a CONSTANT")
		print("        rather than from the live viewport, so it does not")
		print("        follow the canvas when UI Scale changes it.")

	print("\n[uiscale] %d screen(s) x %d scale(s)"
		% [base.size(), SCALES.size()])
	if _leaks > 0:
		print("[uiscale] %d ORDER-DEPENDENT baseline measurement(s) — once-per-process "
			% _leaks + "content is leaking across passes; fix the probe, not the product")
	print("[uiscale] %s" % ("EVERY SCALE AGREES" if _hits == 0 and _leaks == 0
		else "%d SCALE-DEPENDENT LAYOUT(S), %d LEAK(S)" % [_hits, _leaks]))
	_done = true
	quit(1 if (_hits > 0 or _leaks > 0) else 0)
