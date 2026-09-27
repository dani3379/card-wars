extends SceneTree
## _probe_input_reach.gd — CLASS C29: CAN THE PLAYER ACTUALLY CLICK IT?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_input_reach.gd
##
## C18 (silent refusal) covers a control that DECLINES without saying so. This is
## the class underneath it: a control that never hears the click at all. The
## player's report is identical and the most common bug report in existence —
## "the button doesn't work" — but nothing in the tree is wrong. The button is
## visible, enabled, correctly wired, and its `pressed` signal simply never fires
## because something invisible is standing in front of it.
##
## Godot makes this easy to ship. `mouse_filter` defaults to STOP on Control, so a
## transparent full-screen overlay left in the tree — a scrim whose fade-out never
## finished, a click-catcher whose owner was freed, a modal layer that was hidden
## by alpha rather than by `visible` — swallows every click beneath it while
## drawing absolutely nothing. There is no visual symptom to photograph and no
## error to log.
##
## THE ORACLE IS GODOT'S OWN PICKING RULE, re-implemented and run against every
## clickable control on the screen: at that control's own centre, which node would
## actually receive the press? Order is (canvas layer, z_index, tree order), a
## CanvasLayer overriding z; MOUSE_FILTER_IGNORE is transparent to input;
## MOUSE_FILTER_STOP consumes it. If the winner is not the button or something
## inside it, the button is dead.
##
## Deliberately NOT flagged: `disabled` controls (dead on purpose, and they say so
## by greying), and anything scrolled outside its own clipper (a click there would
## miss it in the real game too, which is what scrolling means).

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const SEED := 606061

var RS: Node
var US: Node
var EDB: Node
var _started := false
var _done := false
var _hits := 0
var _states := 0
var _checked := 0
var _canvas := Vector2(1600, 900)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _paint_key(c: CanvasItem, order: Dictionary) -> Vector3:
	var layer := 0
	var walk: Node = c
	while walk != null:
		if walk is CanvasLayer:
			layer = (walk as CanvasLayer).layer
			break
		walk = walk.get_parent()
	var z := c.z_index
	if c.z_as_relative:
		var p: Node = c.get_parent()
		while p is CanvasItem:
			z += (p as CanvasItem).z_index
			if not (p as CanvasItem).z_as_relative:
				break
			p = p.get_parent()
	return Vector3(float(layer), float(z), float(order.get(c.get_instance_id(), 0)))


func _above(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x:
		return a.x > b.x
	if a.y != b.y:
		return a.y > b.y
	return a.z > b.z


func _is_descendant(child: Node, parent: Node) -> bool:
	var w: Node = child
	while w != null:
		if w == parent:
			return true
		w = w.get_parent()
	return false


## The nearest ancestor that clips this control, if any — a control scrolled out
## of its own viewport is not reachable and is not a defect.
func _clipped_away(c: Control, pt: Vector2) -> bool:
	var walk: Node = c.get_parent()
	while walk != null:
		if walk is ScrollContainer or (walk is Control and (walk as Control).clip_contents):
			if not (walk as Control).get_global_rect().has_point(pt):
				return true
		walk = walk.get_parent()
	return false


func _label_of(c: Control) -> String:
	if c is Button:
		var t := (c as Button).text.strip_edges()
		if t != "":
			return t
	var n := String(c.name)
	# An unnamed programmatic button says nothing; borrow the first words inside.
	var stack: Array = [c]
	while not stack.is_empty():
		var x = stack.pop_back()
		for ch in x.get_children():
			stack.push_back(ch)
		if x is Label and (x as Label).text.strip_edges() != "":
			return "%s (\"%s\")" % [n, (x as Label).text.strip_edges().substr(0, 28)]
	return n


## Does this full-screen catcher share its canvas layer with anything the player
## could actually be interacting with? Buttons other than itself, or worded
## controls — either justifies the curtain. Nothing at all means it is a leak.
func _company_on_layer(all: Array, order: Dictionary, catcher: Control,
		ck: Vector3) -> bool:
	for n in all:
		if not (n is Control) or n == catcher:
			continue
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		if _paint_key(c, order).x != ck.x:
			continue
		if c is BaseButton and not (c as BaseButton).disabled:
			return true
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).get_parsed_text()
		elif c is Button:
			t = (c as Button).text
		if t.strip_edges() != "":
			return true
	return false


func _scan(node: Node, label: String) -> void:
	_states += 1
	var order := {}
	var all: Array = []
	var idx := 0
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_front()
		if n is CanvasItem:
			order[n.get_instance_id()] = idx
			idx += 1
			all.append(n)
		var kids: Array = n.get_children()
		for k in range(kids.size() - 1, -1, -1):
			stack.push_front(kids[k])

	# Every control that can consume a press, with its rect and paint key.
	var blockers: Array = []
	for n in all:
		if not (n is Control):
			continue
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		if c.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		var r := c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		blockers.append({"n": c, "r": r, "k": _paint_key(c, order)})

	# ── A MODAL IS ALLOWED TO EAT INPUT — a LEAKED CATCHER IS NOT ────────
	#
	# A full-screen STOP control blocks everything beneath it, and that is exactly
	# right while a modal is up: the HUD's END TURN, LOG and gear are SUPPOSED to
	# be unreachable behind the open pile viewer. Judging them reported seven dead
	# controls, all of them correct behaviour.
	#
	# But the same shape with the modal GONE — a click-catcher whose owner was
	# torn down, a scrim whose fade-out never finished — is the nastiest dead-
	# button bug there is: the whole screen stops answering and looks perfectly
	# normal. So the two are told apart by whether the catcher still has anything
	# to catch FOR: a curtain that shares its canvas layer with live interactive
	# or worded content is doing its job; a curtain standing alone is a leak.
	var curtain := -INF
	for n2 in all:
		if not (n2 is Control):
			continue
		var c2: Control = n2
		if not c2.is_visible_in_tree() or c2.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		var r2 := c2.get_global_rect()
		if r2.size.x < _canvas.x * 0.9 or r2.size.y < _canvas.y * 0.9:
			continue
		var k2 := _paint_key(c2, order)
		if _company_on_layer(all, order, c2, k2):
			curtain = maxf(curtain, k2.x)
		else:
			_hits += 1
			print("  HIT   %-26s LEAKED CLICK-CATCHER  %s" % [label, c2.get_class()])
			print("        a full-screen input catcher at %s stands on layer %d"
				% [str(r2), int(k2.x)])
			print("        with NOTHING on that layer to catch for — every control")
			print("        beneath it is dead and the screen looks untouched.")
			print("        path=%s" % str(c2.get_path()))

	var found := 0
	for n in all:
		if not (n is BaseButton):
			continue
		var b: BaseButton = n
		if not b.is_visible_in_tree() or b.disabled:
			continue
		if b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			# A button that ignores the mouse is only reachable by keyboard; that
			# is a deliberate pattern here (painted chips with a sibling catcher),
			# so it is not judged.
			continue
		var br := b.get_global_rect()
		if br.size.x <= 1.0 or br.size.y <= 1.0:
			continue
		var pt := br.get_center()
		if not Rect2(Vector2.ZERO, _canvas).has_point(pt):
			continue                       # off-canvas is _probe_textfit's beat
		if _clipped_away(b, pt):
			continue
		_checked += 1
		var bk := _paint_key(b, order)
		if bk.x < curtain:
			continue          # deliberately curtained by a live modal
		var winner: Dictionary = {}
		for s in blockers:
			if s["n"] == b or _is_descendant(s["n"], b):
				continue
			if not (s["r"] as Rect2).has_point(pt):
				continue
			if not _above(s["k"], bk):
				continue
			if winner.is_empty() or _above(s["k"], winner["k"]):
				winner = s
		if winner.is_empty():
			continue
		found += 1
		_hits += 1
		var w: Control = winner["n"]
		print("  HIT   %-26s DEAD CONTROL  %s" % [label, _label_of(b)])
		print("        press at %s is taken by %s %s" % [
			str(pt), w.get_class(), str(winner["r"])])
		print("        (blocker layer/z/order %s over button %s) path=%s" % [
			str(winner["k"]), str(bk), str(w.get_path())])
	if found == 0:
		print("  ok    %-26s %d clickable" % [label, _checked])


func _stage(kind: String, hero_i: int) -> void:
	seed(SEED)
	RS.start_new_run(HEROES[hero_i % HEROES.size()], 0, SEED)
	RS.gold = 800 if kind == "rich" else 150
	RS.hero_hp = RS.hero_max_hp


func _settle(sec: float = 1.4) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		await create_timer(0.02).timeout
		t += 0.02


func _simple(label: String, path: String, kind: String, hero_i: int) -> void:
	_stage(kind, hero_i)
	var n = load(path).instantiate()
	root.add_child(n)
	await _settle()
	_scan(n, label)
	n.queue_free()
	await process_frame


func _event(ev_id: String, effect: Dictionary = {}) -> void:
	_stage("rich", 1)
	var EvScript = load("res://scripts/scenes/Event.gd")
	var ev = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)
	await process_frame
	ev._clear_ui()
	ev._event_id = ev_id
	ev._event_data = EvScript.EVENTS[ev_id].duplicate(true)
	ev._current_node = ev._event_data
	ev._build_ui()
	await process_frame
	var tag := "event:%s" % ev_id
	if not effect.is_empty():
		ev._apply_effect(effect.duplicate(true))
		tag = "modal:%s" % String(effect.get("type", "?"))
	await _settle(1.8)
	if is_instance_valid(ev):
		_scan(ev, tag)
		ev.queue_free()
	await process_frame


func _modal_states() -> Array:
	var EvScript = load("res://scripts/scenes/Event.gd")
	var modal_types: Array = EvScript.MODAL_EFFECTS
	var out: Array = []
	var seen := {}
	var ids: Array = EvScript.EVENTS.keys()
	ids.sort()
	for ev_id in ids:
		var d: Dictionary = EvScript.EVENTS[ev_id]
		var pools: Array = []
		if d.has("auto_effect"):
			pools.append(d["auto_effect"])
		for ch in d.get("choices", []):
			if ch is Dictionary:
				for e in ch.get("effects", []):
					pools.append(e)
		for e in pools:
			if not (e is Dictionary):
				continue
			var t := String((e as Dictionary).get("type", ""))
			if not modal_types.has(t) or seen.has(t):
				continue
			seen[t] = true
			out.append({"ev": String(ev_id), "effect": e})
	return out


func _combat(enc: String, what: String) -> void:
	_stage("default", 0)
	RS.current_encounter_id = enc
	RS.current_node_type = String(EDB.ENCOUNTERS[enc].get("type", "combat"))
	var cb = load("res://scenes/combat.tscn").instantiate()
	root.add_child(cb)
	await _settle(7.0)
	match what:
		"pile":
			if cb._player_discard_pile.is_empty():
				for i in mini(8, RS.deck.size()):
					cb._player_discard_pile.append(RS.deck[i])
			cb._show_pile_viewer(1)
			await _settle(1.4)
		"closed_pile":
			# THE CLOSE PATH IS THE POINT. A modal that tears down its layer but
			# leaves a click-catcher behind kills every button on the screen and
			# looks completely normal.
			if cb._player_discard_pile.is_empty():
				for i in mini(8, RS.deck.size()):
					cb._player_discard_pile.append(RS.deck[i])
			cb._show_pile_viewer(1)
			await _settle(1.0)
			cb._close_pile_viewer()
			await _settle(1.0)
		"closed_glossary":
			if cb.has_method("_reset_glossary_layer"):
				cb._reset_glossary_layer(0.56)
				await _settle(1.0)
				if cb.has_method("_close_glossary"):
					cb._close_glossary()
				await _settle(1.0)
	if is_instance_valid(cb):
		_scan(cb, "combat:%s" % what)
		cb.queue_free()
	await process_frame


## ── A STANDING GUARD FOR THE `flat` CONTRADICTION ────────────────────────────
##
## `Button.flat = true` means "draw no stylebox". Pairing it with a stylebox
## override is therefore always a contradiction — one of the two lines is dead —
## and on 2026-09-02 that shipped as TWO invisible modal scrims in Combat, each
## carrying a fully-specified 0.7 black dim that was never painted.
##
## It is caught here rather than in the pixel probe because it is a source fact,
## costs milliseconds, and covers every screen at once instead of only the ones a
## harness happens to drive. `StyleBoxEmpty` is the legitimate pairing (30 of the
## 32 sites in the codebase): those authors want nothing drawn and `flat` merely
## restates it. A COLOURED box is the bug.
func _scan_flat_contradiction() -> void:
	var files: Array = []
	_gather_gd("res://scripts", files)
	var hits := 0
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var lines: PackedStringArray = f.get_as_text().split("\n")
		f.close()
		for i in lines.size():
			var m := RegEx.create_from_string("([\\w\\.]+)\\.flat\\s*=\\s*true").search(lines[i])
			if m == null:
				continue
			var v := m.get_string(1)
			for j in range(i + 1, mini(i + 14, lines.size())):
				if lines[j].find(v + ".add_theme_stylebox_override") < 0:
					continue
				# StyleBoxEmpty / a var named transparent-ish = deliberate.
				var tail := lines[j]
				if tail.find("StyleBoxEmpty") >= 0 or tail.find("transparent") >= 0 \
						or tail.find("empty") >= 0:
					break
				hits += 1
				_hits += 1
				print("  HIT   %s:%d  `%s.flat = true` cancels the stylebox below it"
					% [path.replace("res://", ""), i + 1, v])
				print("        %s" % lines[j].strip_edges().substr(0, 76))
				break
	if hits == 0:
		print("  ok    flat/stylebox contradiction: none in %d script(s)" % files.size())


func _gather_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_gather_gd(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or US == null:
		print("[reach] FATAL: autoloads missing"); _done = true; quit(1); return
	US.anim_speed = 3.0
	US.end_turn_warning = false
	_canvas = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	print("[reach] CLASS C29 — which node actually receives the press?\n")
	_scan_flat_contradiction()
	print("")

	for row in [
		["main_menu", "res://scenes/main_menu.tscn", "default", 0],
		["collection", "res://scenes/collection.tscn", "default", 0],
		["credits", "res://scenes/credits.tscn", "default", 0],
		["net_lobby", "res://scenes/net_lobby.tscn", "default", 0],
		["map", "res://scenes/map.tscn", "default", 1],
		["reward", "res://scenes/reward.tscn", "rich", 1],
		["shop", "res://scenes/shop.tscn", "rich", 2],
		["rest", "res://scenes/rest.tscn", "default", 3],
		["treasure", "res://scenes/treasure.tscn", "rich", 3],
		["recruit", "res://scenes/recruit.tscn", "default", 4],
		["game_over", "res://scenes/game_over.tscn", "default", 4],
	]:
		await _simple(String(row[0]), String(row[1]), String(row[2]), int(row[3]))

	for verb in ["drill_yard", "standard_bearer", "supply_cache"]:
		_stage("rich", 2)
		RS.current_wayside_id = verb
		var n = load("res://scenes/wayside.tscn").instantiate()
		root.add_child(n)
		await _settle()
		_scan(n, "wayside:%s" % verb)
		n.queue_free()
		await process_frame

	var EvScript = load("res://scripts/scenes/Event.gd")
	var ev_ids: Array = EvScript.EVENTS.keys()
	ev_ids.sort()
	for ev_id in ev_ids:
		await _event(String(ev_id))
	for st in _modal_states():
		await _event(String(st["ev"]), st["effect"])

	if EDB != null:
		for what in ["none", "pile", "closed_pile", "closed_glossary"]:
			await _combat("goblin_scouts", what)

	print("\n[reach] %d screen state(s), %d clickable control(s) hit-tested"
		% [_states, _checked])
	print("[reach] %s" % ("EVERY CONTROL REACHABLE" if _hits == 0
		else "%d DEAD CONTROL(S)" % _hits))
	_done = true
	quit(1 if _hits > 0 else 0)

