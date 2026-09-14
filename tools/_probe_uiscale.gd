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
const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const SEED := 606061

## KNOWN AND UNFIXED — visible debt, not absolution. Keyed "screen::axis".
const WAIVERS := {}

var RS: Node
var US: Node
var _started := false
var _done := false
var _hits := 0
var _canvas := Vector2(1600, 900)


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
		n.queue_free()
	await process_frame
	return cov


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
	for scale in SCALES:
		root.content_scale_factor = float(scale)
		await process_frame
		var canvas: Vector2 = root.get_visible_rect().size
		if scale == 1.0:
			_canvas = canvas
		print("  factor %.2f  canvas %s" % [scale, str(canvas)])
		for row in screens:
			var name := String(row[0])
			var cov: Vector2 = await _measure(String(row[1]), int(row[2]), canvas)
			if scale == 1.0:
				base[name] = cov
				print("    %-12s coverage %3.0f%% x %3.0f%%"
					% [name, cov.x * 100.0, cov.y * 100.0])
				continue
			var b: Vector2 = base.get(name, Vector2.ZERO)
			for axis in ["x", "y"]:
				var bv: float = b.x if axis == "x" else b.y
				var cv: float = cov.x if axis == "x" else cov.y
				var drop: float = bv - cv
				var key := "%s::%s" % [name, axis]
				if drop <= DROP_TOL or WAIVERS.has(key):
					continue
				_hits += 1
				print("  HIT   %-12s factor %.2f: %s coverage falls %.0f%% -> %.0f%%"
					% [name, scale, axis, bv * 100.0, cv * 100.0])
				print("        something on this screen is placed from a CONSTANT")
				print("        rather than from the live viewport, so it does not")
				print("        follow the canvas when UI Scale changes it.")

		# ── Combat and one event, staged rather than loaded flat ──
		for extra in await _extra_states(EDB, canvas):
			var xname := String(extra["name"])
			var xcov: Vector2 = extra["cov"]
			if scale == 1.0:
				base[xname] = xcov
				print("    %-12s coverage %3.0f%% x %3.0f%%"
					% [xname, xcov.x * 100.0, xcov.y * 100.0])
				continue
			var xb: Vector2 = base.get(xname, Vector2.ZERO)
			for axis2 in ["x", "y"]:
				var bv2: float = xb.x if axis2 == "x" else xb.y
				var cv2: float = xcov.x if axis2 == "x" else xcov.y
				if bv2 - cv2 <= DROP_TOL or WAIVERS.has("%s::%s" % [xname, axis2]):
					continue
				_hits += 1
				print("  HIT   %-12s factor %.2f: %s coverage falls %.0f%% -> %.0f%%"
					% [xname, scale, axis2, bv2 * 100.0, cv2 * 100.0])
	root.content_scale_factor = 1.0

	print("\n[uiscale] %d screen(s) x %d scale(s)"
		% [base.size(), SCALES.size()])
	print("[uiscale] %s" % ("EVERY SCALE AGREES" if _hits == 0
		else "%d SCALE-DEPENDENT LAYOUT(S)" % _hits))
	_done = true
	quit(1 if _hits > 0 else 0)
