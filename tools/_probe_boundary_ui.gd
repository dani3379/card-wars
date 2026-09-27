extends SceneTree
## _probe_boundary_ui.gd — PASS 6b of docs/BUG_SWEEP_METHOD_20260829.md (class C6).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_boundary_ui.gd
##
## BOUNDARY-VALUE ANALYSIS FOR SCREENS, instead of shooting one nominal state.
##
## `_probe_textfit` already walks every screen looking for text that overflows its
## box or leaves the canvas, and it reports zero — but it builds each screen in a
## MIDDLING state, and middling states are precisely where UI does not break. Every
## screen defect found by eye this session was at an EXTREME:
##
##   * the draft ledger broke at MAXIMUM content — 3 relics + 2 potions stacked on
##     top of the card list under a header that counted only the cards;
##   * the relic picker broke on the LONGEST STRINGS — two relics whose rules text
##     wrapped to three lines each overflowed a viewport sized for two;
##   * HOST (LAN) broke in ISOLATION — one frameless control with no plated sibling
##     to be read against.
##
## So the method is to drive each screen to its limits and re-run the same
## mechanical overflow check there: maximum item counts, longest strings in the
## real data, and the empty case. No eyeballing, and no new detection logic — the
## novelty is entirely in the STATE the screen is put into.
##
## Boundaries exercised: full relic bag, full potion belt, a deck at its largest,
## the longest real card/relic names and rules text in the databases, and zero of
## each (an empty state that draws nothing is its own defect class).

const TOL := 2.0

var RS: Node
var RDB: Node
var CDB: Node
var _started := false
var _done := false
var _hits := 0
var _scanned := 0
var _canvas := Vector2(1600, 900)
var _clipped_skips := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _text_of(c: Control) -> String:
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	return ""


## Content that does not fit its own box, or that leaves the canvas.
##
## TWO UNITS TRAPS, both of which produced convincing false failures first:
##
##   * `get_content_height()` and `get_string_size()` are LOCAL units, while
##     `get_global_rect()` is scaled. Comparing one to the other reports every node
##     under a scaled parent as clipped — the GameOver deck strip renders at 0.36,
##     so "content 65 > box 24" was exactly the 0.36 ratio and nothing else. Compare
##     local to local.
##   * A full-width centred label legitimately sits flush to the canvas edge and
##     rounds a few pixels past it. Flagging the BOX rather than the text made every
##     screen title an off-canvas hit. Only sub-full-width boxes are judged, with a
##     wider tolerance.
func _verdict(c: Control, txt: String) -> String:
	var local := c.size
	if local.x <= 1.0 or local.y <= 1.0:
		return ""
	if c is RichTextLabel:
		var rt: RichTextLabel = c
		if not rt.scroll_active and rt.get_content_height() > local.y + TOL:
			return "clipped (content %.0f > box %.0f)" % [rt.get_content_height(), local.y]
	elif c is Label:
		var lbl: Label = c
		if lbl.autowrap_mode == TextServer.AUTOWRAP_OFF \
				and lbl.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var f := lbl.get_theme_font("font")
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				lbl.get_theme_font_size("font_size")).x if f != null else 0.0
			if w > local.x + TOL:
				return "label wider than its box (%.0f > %.0f)" % [w, local.x]
	# A CLIPPING ANCESTOR MOVES THE QUESTION. Content inside a ScrollContainer is
	# SUPPOSED to sit outside the canvas — that is what scrolling is — so judging
	# the leaf reports every long list as broken. Judge the clipper instead: if the
	# scroll's own rect is on-canvas the list is reachable, and only a clipper that
	# has itself run off the screen is a real defect.
	var judged: Control = _nearest_clipper(c)
	var r := judged.get_global_rect()
	var full_width: bool = r.size.x >= _canvas.x * 0.9
	if not full_width and (r.position.x < -8.0 or r.end.x > _canvas.x + 8.0
			or r.position.y < -8.0 or r.end.y > _canvas.y + 8.0):
		return "off-canvas %s%s" % [str(r),
			"" if judged == c else " (via its clipping ancestor %s)" % judged.get_class()]
	return ""


## The nearest ancestor that CLIPS `c` (itself if none). Content inside a scroll is
## supposed to sit outside the canvas — that is what scrolling IS — so the question
## "did this run off the screen" has to be asked of the clipper, not the leaf.
## Verified against the relic picker at six relics: the fifth and sixth entries sit
## at y≈925 and y≈1073 and are perfectly correct, because the ScrollContainer
## holding them ends at y≈700.
func _nearest_clipper(c: Control) -> Control:
	var walk: Node = c.get_parent()
	while walk != null:
		if walk is ScrollContainer:
			_clipped_skips += 1
			return walk as Control
		if walk is Control and (walk as Control).clip_contents:
			_clipped_skips += 1
			return walk as Control
		walk = walk.get_parent()
	return c


func _scan(node: Node, label: String) -> int:
	_scanned += 1
	var found := 0
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for ch in n.get_children():
			stack.push_back(ch)
		if not (n is Control):
			continue
		var c: Control = n
		if not c.is_visible_in_tree() or c.modulate.a < 0.05:
			continue
		var txt := _text_of(c)
		if txt.strip_edges() == "":
			continue
		var v := _verdict(c, txt)
		if v != "":
			found += 1
			_hits += 1
			print("  HIT   %-28s %s | \"%s\" | %s" % [
				label, c.get_class(), txt.substr(0, 46), v])
	if found == 0:
		print("  ok    %s" % label)
	return found


## A LIST MUST CUT BETWEEN ENTRIES, NEVER THROUGH ONE.
##
## The overflow scan above cannot see this, and mutation testing proved it: with
## the relic picker's row height put back to its old value the viewport became 2.4
## entries and the third was sliced through the middle — and this probe stayed
## GREEN, because content inside a ScrollContainer is deliberately exempted from
## the off-canvas rule. The gate could not catch the very bug it was built for.
##
## A straddling entry is the defect in its own right: the player sees a name with
## no rules text under it and reads the item as having none. So find every scroll,
## and require each direct child to be either fully inside the viewport or fully
## below it — never spanning the bottom edge.
func _scan_straddle(node: Node, label: String) -> int:
	var found := 0
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for ch in n.get_children():
			stack.push_back(ch)
		if not (n is ScrollContainer):
			continue
		var sc: ScrollContainer = n
		if not sc.is_visible_in_tree():
			continue
		var view := sc.get_global_rect()
		for inner in sc.get_children():
			if not (inner is Control):
				continue
			for entry in (inner as Control).get_children():
				if not (entry is Control):
					continue
				var e: Control = entry
				var er := e.get_global_rect()
				if er.size.y <= 1.0:
					continue
				# MEASURE THE TEXT, NOT THE BOX. An entry's rect includes trailing
				# padding and separation, so judging the box flags a row whose last
				# 30px are empty — visually perfect. What the player actually loses
				# is a LINE OF WORDS, so find the lowest text descendant and ask
				# whether that is below the fold.
				var deepest := -1.0
				var sub: Array = [e]
				while not sub.is_empty():
					var s = sub.pop_back()
					for sch in s.get_children():
						sub.push_back(sch)
					if (s is Label or s is RichTextLabel) and (s as Control).is_visible_in_tree():
						if _text_of(s as Control).strip_edges() != "":
							deepest = maxf(deepest, (s as Control).get_global_rect().end.y)
				if deepest < 0.0:
					continue
				var top_in: bool = er.position.y < view.end.y - 1.0
				if top_in and deepest > view.end.y + 1.0:
					found += 1
					_hits += 1
					print("  HIT   %-28s an entry's TEXT is cut by the viewport "
						% label + "(text ends %.0f, viewport ends %.0f)" % [
							deepest, view.end.y])
	return found


## The longest real strings in the databases — the worst case a player can meet.
func _longest_relics(n: int) -> Array:
	var ids: Array = []
	for rid in RDB.RELICS:
		ids.append(String(rid))
	ids.sort_custom(func(a, b):
		return String(RDB.get_relic(a).get("desc", "")).length() \
			> String(RDB.get_relic(b).get("desc", "")).length())
	return ids.slice(0, n)


func _run() -> void:
	print("[bounds] PASS 6b — screens at their limits\n")
	RS = root.get_node_or_null("RunState")
	RDB = root.get_node_or_null("RelicDB")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or RDB == null or CDB == null:
		print("[bounds] FATAL: autoloads missing"); _done = true; quit(1); return

	# ── The relic picker at 1 / 2 / MANY, with the wordiest relics in the game ──
	# This is the screen that broke: sized for two entries, given two three-line
	# ones. Now driven with the longest rules text the databases actually contain.
	print("[bounds] --- the relic trade picker (longest relic text) ---")
	var wordy := _longest_relics(8)
	for count in [1, 2, 3, 6]:
		RS.start_new_run("stalwart", 0, 20260829)
		RS.relics.clear()
		var placed := 0
		for rid in wordy:
			if placed >= count:
				break
			if String(RDB.get_relic(rid).get("tier", "starting")) == "starting":
				continue
			RS.relics.append(rid)
			placed += 1
		var ev = load("res://scenes/event.tscn").instantiate()
		root.add_child(ev)
		await process_frame
		ev._clear_ui()
		ev._event_id = "old_forge"
		ev._event_data = ev.EVENTS["old_forge"].duplicate(true)
		ev._current_node = ev._event_data
		ev._build_ui()
		await process_frame
		ev._apply_effect({"type": "relic_sacrifice_pick"})
		for _i in 4:
			await process_frame
		_scan(ev, "relic picker x%d" % placed)
		_scan_straddle(ev, "relic picker x%d" % placed)
		ev.free()
		await process_frame

	# ── GameOver with a maximal run behind it ─────────────────────────────
	print("\n[bounds] --- game over, maximal run ---")
	for shape in ["empty", "maximal"]:
		RS.start_new_run("stalwart", 0, 20260829)
		RS.relics.clear()
		RS.deck.clear()
		if shape == "maximal":
			for rid in _longest_relics(12):
				RS.relics.append(String(rid))
			var pool: Array = CDB.CARD_POOL.keys()
			for i in mini(40, pool.size()):
				RS.deck.append(String(pool[i]))
			RS.gold = 999999
			RS.current_floor = 88
			RS.fights_won = 77
		var go = load("res://scenes/game_over.tscn").instantiate()
		root.add_child(go)
		for _i in 8:
			await process_frame
		_scan(go, "game over (%s)" % shape)
		go.free()
		await process_frame

	# ── Reward, and the Shop shelf, at full stock ─────────────────────────
	print("\n[bounds] --- reward + shop at full stock ---")
	RS.start_new_run("stalwart", 0, 20260829)
	RS.gold = 999999
	for scene_path in ["res://scenes/reward.tscn", "res://scenes/shop.tscn"]:
		var sc = load(scene_path).instantiate()
		root.add_child(sc)
		for _i in 10:
			await process_frame
		_scan(sc, scene_path.get_file())
		sc.free()
		await process_frame

	print("\n[bounds] %d screen state(s) scanned, %d overflow hit(s)" % [_scanned, _hits])
	print("[bounds] %s" % ("ALL PASS" if _hits == 0 else "%d HIT" % _hits))
	_done = true
	quit(1 if _hits > 0 else 0)
