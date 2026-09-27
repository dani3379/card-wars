extends SceneTree
## _probe_occlusion.gd — CLASS C28: TEXT THE PLAYER CANNOT READ.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_occlusion.gd
##
## Every existing layout gate asks whether a control is IN THE RIGHT PLACE:
## `_probe_textfit` checks text against its own box and the canvas edge,
## `_probe_boundary_ui` drives screens to their extremes and re-asks the same
## question. Both judge each control ALONE. Neither can see the defect where every
## control is perfectly placed and one of them is drawn ON TOP OF another.
##
## That is the single most-reported category in the automated-GUI-glitch
## literature (OwlEyes / Nighthawk / AG3 all lead with "text overlap" and
## "component occlusion"), and it is the one a player notices instantly, because
## the symptom is not subtle — a sentence is simply not there.
##
## It has happened here twice already:
##   * the veterancy rung modals were parented to `self` at canvas layer 0, so the
##     HUD (12) and the hand (20) painted straight over a modal that was still
##     eating input — z_index cannot reach across a CanvasLayer;
##   * CLAUDE.md carries a layout budget in prose — "at most 4 visible choices per
##     screen (a 5th overlaps the description)" — which is a declared constraint
##     that nothing enforces.
##
## TWO ORACLES, both purely geometric:
##
##   A. OCCLUSION — a worded control covered by an opaque thing that PAINTS LATER.
##   B. TEXT-ON-TEXT — two worded controls sharing the same pixels.
##
## The paint order is the hard part and the reason a naive version of this reports
## nonsense: within a canvas layer it is z_index then tree order, but a CanvasLayer
## in the chain OVERRIDES both — a child at z_index 4096 under layer 0 still draws
## beneath anything on layer 1.

const COVER_HIT := 0.80      # an occluder hiding this much of the text
const TEXT_HIT := 0.35       # two sentences sharing this much of their pixels
const OPAQUE := 0.80
const CURTAIN := 0.90        # covers this much of the canvas = a scrim, not a bug
const SHADOW_PX := 6.0       # a drop-shadow twin sits within this of its subject
const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const SEED := 606061

## KNOWN AND UNFIXED — visible debt, not absolution (the house convention for
## waiver tables). Keyed "state::text-needle"; an entry silences one pair only.
##
## combat+pile: the viewer's title sits at y 40..86 and Combat's phase caption
## occupies y 47..78 at the same screen centre, so "DISCARD PILE (8)" prints
## across "YOUR TURN" / "Round 1 · Set your line". The 0.7 scrim (repaired
## 2026-09-02 — it had never painted) knocks the caption back to a ghost but does
## not remove it, so the two strings still share pixels.
##
## Left for the owner because all three fixes are DESIGN calls, not corrections:
##   (a) hide `_hud_layer` while a full-screen modal is open — what most games do,
##       and the only one that fully solves it, but a hide/show pair that is not
##       symmetric on every close path leaves the player with no HUD, which is far
##       worse than the blemish;
##   (b) move the viewer's title above the caption band (offset_top 40 -> ~4),
##       which clears it by a few px and reads cramped against the screen edge;
##   (c) take the scrim to ~0.92 so the caption truly goes.
const WAIVERS := {
	"combat+pile::DISCARD PILE": "title shares the top band with Combat's phase caption",
}


## Returns the waiver's REASON, or "" if this pair is not waived.
## (It used to return a bool and the caller printed `WAIVERS.values()[0]` — with a
## second waiver added, every waived pair would have been reported under the first
## entry's reason. A waiver table that misattributes its own entries is worse than
## none, because it is read as a record of what is known.)
func _waived(label: String, a: String, b: String) -> String:
	for k in WAIVERS:
		var parts: PackedStringArray = String(k).split("::")
		if parts.size() != 2 or parts[0] != label:
			continue
		if a.find(parts[1]) >= 0 or b.find(parts[1]) >= 0:
			return String(WAIVERS[k])
	return ""

var RS: Node
var US: Node
var EDB: Node
var _started := false
var _done := false
var _hits := 0
var _states := 0
var _canvas := Vector2(1600, 900)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


# ── Paint order ──────────────────────────────────────────────────────────────

## (canvas_layer, z_index, tree_index) — compared left to right. A CanvasLayer
## ancestor dominates z_index, which is why a modal parented to the scene root at
## layer 0 loses to a HUD on layer 12 no matter what z_index it sets.
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


func _draws_above(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x:
		return a.x > b.x
	if a.y != b.y:
		return a.y > b.y
	return a.z > b.z


func _is_related(a: Node, b: Node) -> bool:
	var w: Node = a
	while w != null:
		if w == b:
			return true
		w = w.get_parent()
	w = b
	while w != null:
		if w == a:
			return true
		w = w.get_parent()
	return false


# ── What paints, and how solidly ─────────────────────────────────────────────

func _effective_alpha(c: CanvasItem) -> float:
	var a: float = c.self_modulate.a
	var walk: Node = c
	while walk != null:
		if walk is CanvasItem:
			a *= (walk as CanvasItem).modulate.a
		walk = walk.get_parent()
	return a


## Only things that actually FILL their rect count as occluders. A Container or a
## bare Control paints nothing at all, and treating one as solid — it is an
## ancestor of half the screen — makes every label on every screen a hit.
func _opacity_of(c: Control) -> float:
	var a := _effective_alpha(c)
	if a < 0.05:
		return 0.0
	# ── `show_behind_parent` IS NOT AN OCCLUDER (2026-09-17) ──
	#
	# A CanvasItem with this flag draws BEHIND its parent's subtree, so it cannot
	# paint over content that comes after the parent — but the tree-order model
	# above only knows the child is later in the tree, and scored it as on top.
	#
	# Found the first time this pass was pointed at the menu's own subscreens: it
	# reported "CHOOSE ONE" 100% buried on the starting bonus and "RUN SETUP" /
	# "YOUR HERO" on run setup, all three by a `ColorRect`. Every one of them is a
	# `Sheen.plinth` — the warm pool that goes UNDER a subject so a lit plate
	# stops reading as a cut-out, and whose own header says it uses
	# `show_behind_parent` rather than z_index precisely because the parent is an
	# opaque sibling. Three false positives on the first two screens it reached.
	#
	# This is a correction to the MODEL, not a waiver: the flag is a statement
	# about rendering order, and a backdrop is the opposite of an occluder. Ten
	# nodes in the codebase carry it.
	if c.show_behind_parent:
		return 0.0
	if c is ColorRect:
		return a * (c as ColorRect).color.a
	if c is Panel or c is PanelContainer:
		var sb := c.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			return a * (sb as StyleBoxFlat).bg_color.a
		if sb is StyleBoxTexture:
			return a * 0.9
		return 0.0
	if c is NinePatchRect:
		return a * (0.9 if (c as NinePatchRect).texture != null else 0.0)
	# A Button paints too — and this codebase's full-screen modal scrims ARE
	# Buttons, so leaving the class out made every scrim invisible to the probe
	# and every modal look like it buried the HUD by accident.
	# **`flat` MUST be modelled**: a flat Button skips its stylebox entirely, which
	# is precisely how the pile-viewer and glossary dims came to be built, themed,
	# and never painted. A probe that ignored `flat` would score the broken scrim
	# as solid — agreeing with the code's intent instead of its output.
	if c is Button:
		if (c as Button).flat:
			return 0.0
		var bsb := c.get_theme_stylebox("normal")
		if bsb is StyleBoxFlat:
			return a * (bsb as StyleBoxFlat).bg_color.a
		if bsb is StyleBoxTexture:
			return a * 0.9
		return 0.0
	return 0.0


func _text_of(c: Control) -> String:
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	return ""


func _revealed(c: Control) -> float:
	if c is RichTextLabel:
		return clampf((c as RichTextLabel).visible_ratio, 0.0, 1.0)
	if c is Label:
		var l: Label = c
		if l.visible_characters < 0:
			return 1.0
		return 1.0 if l.text.length() <= 0 else clampf(
			float(l.visible_characters) / float(l.text.length()), 0.0, 1.0)
	return 1.0


func _norm(s: String) -> String:
	var t := s.strip_edges()
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	return t.replace("\n", " ")


## WHERE THE GLYPHS ACTUALLY LAND — not where the box is.
##
## This is the whole difference between a usable oracle and a noise generator. A
## screen title is a full-width Label with CENTER alignment: its BOX spans the
## canvas and its ink occupies the middle third. Comparing boxes reported the
## combat boss banner (a 1600px-wide centred Label) as overlapping every HUD chip
## on the row, and every one of those was a lie.
func _glyph_rect(c: Control, txt: String) -> Rect2:
	var box := c.get_global_rect()
	if c is RichTextLabel:
		# `get_content_width()` is the ink, `size.x` is the box. A one-line title in
		# a 520px column paints ~300px of it, and using the box called that a
		# collision with the HUD 190px to its right.
		# LIMITATION, stated: a [center]-tagged RichTextLabel is measured as if it
		# were left-aligned, so this under-reports rather than over-reports.
		var rtl: RichTextLabel = c
		var h: float = minf(rtl.get_content_height(), c.size.y)
		var cw: float = rtl.get_content_width()
		if cw <= 0.0:
			cw = c.size.x
		var sx: float = 1.0 if c.size.x <= 0.0 else box.size.x / c.size.x
		var sy: float = 1.0 if c.size.y <= 0.0 else box.size.y / c.size.y
		return Rect2(box.position,
			Vector2(maxf(minf(cw, c.size.x) * sx, 1.0), maxf(h * sy, 1.0)))
	var font: Font = c.get_theme_font("font")
	if font == null:
		return box
	var fs := c.get_theme_font_size("font_size")
	if fs <= 0:
		fs = 16
	var halign := HORIZONTAL_ALIGNMENT_LEFT
	var valign := VERTICAL_ALIGNMENT_TOP
	var wrap := false
	if c is Label:
		halign = (c as Label).horizontal_alignment
		valign = (c as Label).vertical_alignment
		wrap = (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	elif c is Button:
		match (c as Button).alignment:
			HORIZONTAL_ALIGNMENT_CENTER: halign = HORIZONTAL_ALIGNMENT_CENTER
			HORIZONTAL_ALIGNMENT_RIGHT: halign = HORIZONTAL_ALIGNMENT_RIGHT
			_: halign = HORIZONTAL_ALIGNMENT_LEFT
		valign = VERTICAL_ALIGNMENT_CENTER
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# AUTOWRAP DOES NOT MEAN FULL WIDTH. A wrapping label whose string fits on one
	# line paints exactly that line and still obeys its alignment; assuming it
	# fills its box put 220px of imaginary ink on the end of every short title and
	# was the reason the event stage read as colliding with the HUD.
	var wrapped: bool = wrap and ts.x > c.size.x
	var w: float = c.size.x if wrapped else minf(ts.x, c.size.x)
	var h: float = c.size.y if wrapped else minf(ts.y, c.size.y)
	var ox := 0.0
	match halign:
		HORIZONTAL_ALIGNMENT_CENTER: ox = (c.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT: ox = c.size.x - w
		HORIZONTAL_ALIGNMENT_FILL: w = c.size.x
	var oy := 0.0
	match valign:
		VERTICAL_ALIGNMENT_CENTER: oy = (c.size.y - h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM: oy = c.size.y - h
	# Scale the local offsets by whatever the ancestor chain applies, so a 0.36×
	# deck strip measures in the same space as everything else.
	var sx: float = 1.0 if c.size.x <= 0.0 else box.size.x / c.size.x
	var sy: float = 1.0 if c.size.y <= 0.0 else box.size.y / c.size.y
	return Rect2(box.position + Vector2(ox * sx, oy * sy),
		Vector2(maxf(w * sx, 1.0), maxf(h * sy, 1.0)))


func _overlap_frac(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	if i.size.x <= 0.0 or i.size.y <= 0.0:
		return 0.0
	var area := a.size.x * a.size.y
	return 0.0 if area <= 0.0 else (i.size.x * i.size.y) / area


# ── The scan ─────────────────────────────────────────────────────────────────

func _scan(node: Node, label: String) -> void:
	_states += 1
	var order := {}
	var all: Array = []
	var idx := 0
	var stack: Array = [node]
	# Depth-first, PARENT BEFORE CHILDREN and children in declaration order —
	# that is the order Godot paints, and a pop_back() stack reverses siblings.
	while not stack.is_empty():
		var n = stack.pop_front()
		if n is CanvasItem:
			order[n.get_instance_id()] = idx
			idx += 1
			all.append(n)
		var kids: Array = n.get_children()
		for k in range(kids.size() - 1, -1, -1):
			stack.push_front(kids[k])

	var words: Array = []      # {node, rect, key, text}
	var solids: Array = []     # {node, rect, key, op}
	for n in all:
		if not (n is Control):
			continue
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		var key := _paint_key(c, order)
		var txt := _norm(_text_of(c))
		if txt.length() >= 3 and _effective_alpha(c) >= 0.9 and _revealed(c) >= 0.9:
			words.append({"n": c, "r": _glyph_rect(c, txt), "k": key, "t": txt})
		var op := _opacity_of(c)
		if op >= OPAQUE:
			solids.append({"n": c, "r": r, "k": key, "op": op})

	# A MODAL IS ALLOWED TO COVER THE SCREEN — that is what a modal is.
	# Find the highest layer carrying a full-canvas opaque backdrop; every worded
	# control BELOW it is deliberately curtained, and judging those reports the
	# whole combat HUD as buried the moment the pile viewer opens (five hits,
	# all correct behaviour). Oracle B still judges across the scrim, because a
	# 0.7 dim REDUCES the HUD without removing it: two strings sharing pixels are
	# still mush when one of them is a ghost.
	# A scrim curtains at a LOWER opacity than it takes to bury text: 0.7 of black
	# hides nothing outright but plainly says "this layer has the screen now". So
	# curtain detection gets its own threshold, and is computed over every visible
	# control rather than the `solids` list (which is filtered at 0.80).
	var curtain_layer := -INF
	for n2 in all:
		if not (n2 is Control) or not (n2 as Control).is_visible_in_tree():
			continue
		var c2: Control = n2
		if _opacity_of(c2) < 0.45:
			continue
		if _overlap_frac(Rect2(Vector2.ZERO, _canvas), c2.get_global_rect()) >= CURTAIN:
			curtain_layer = maxf(curtain_layer, _paint_key(c2, order).x)

	# ── A. a worded control buried under something opaque ─────────────────
	for w in words:
		if (w["k"] as Vector3).x < curtain_layer:
			continue
		for s in solids:
			if _is_related(w["n"], s["n"]):
				continue
			if not _draws_above(s["k"], w["k"]):
				continue
			# A full-screen scrim is a deliberate curtain: the screen beneath a
			# modal is SUPPOSED to be covered. Judging it flags every dialog.
			if _overlap_frac(Rect2(Vector2.ZERO, _canvas), s["r"]) >= CURTAIN:
				continue
			var cover := _overlap_frac(w["r"], s["r"])
			if cover >= COVER_HIT:
				_hits += 1
				print("  HIT   %-30s BURIED  \"%s\"" % [label, w["t"].substr(0, 44)])
				print("        %.0f%% covered by %s %s (layer/z/order %s over %s)" % [
					cover * 100.0, s["n"].get_class(), str(s["r"]),
					str(s["k"]), str(w["k"])])
				break

	# ── B. two sentences printed on the same pixels ───────────────────────
	for i in range(words.size()):
		for j in range(i + 1, words.size()):
			var a: Dictionary = words[i]
			var b: Dictionary = words[j]
			if _is_related(a["n"], b["n"]):
				continue
			# A DROP SHADOW IS A TWIN, NOT A COLLISION. The house idiom prints the
			# same string twice a pixel or two apart; flagging that would bury a
			# real hit under one per styled heading on every screen.
			if a["t"] == b["t"] and \
					a["r"].position.distance_to(b["r"].position) <= SHADOW_PX:
				continue
			var f: float = maxf(_overlap_frac(a["r"], b["r"]), _overlap_frac(b["r"], a["r"]))
			var why := _waived(label, a["t"], b["t"]) if f >= TEXT_HIT else ""
			if why != "":
				print("  WAIVED %-29s %s" % [label, why])
				continue
			if f >= TEXT_HIT:
				_hits += 1
				print("  HIT   %-30s OVERLAP %.0f%%" % [label, f * 100.0])
				print("        \"%s\" %s %s %s" % [a["t"].substr(0, 40), str(a["r"]),
					a["n"].get_class(), a["n"].get_path()])
				print("        \"%s\" %s %s %s" % [b["t"].substr(0, 40), str(b["r"]),
					b["n"].get_class(), b["n"].get_path()])
	# ── C. an authored text box reaching under a persistent HUD ───────────
	#
	# Oracles A and B judge the INK, which is right for finding a bug that is on
	# screen today. This one judges the BOX, because a box is a promise to the
	# person authoring content: "you may fill this." Where that promise overlaps
	# an always-on HUD, the screen is not broken — it is ARMED, and the next
	# slightly-longer name ships the break. Reporting only ink would call that
	# healthy right up until a content edit, which is the worst time to learn it.
	# JUDGE THE LEDGER'S INK, NOT ITS BOX. The ledger is a 190px-wide container
	# holding right-aligned numerals, so its box starts 100px left of anything it
	# actually draws. Measuring the box makes every right-hand column a hit and
	# leaves no way to tell an armed layout from a broken one.
	var hud := node.get_node_or_null("StakesLedger")
	if hud is Control and (hud as Control).is_visible_in_tree():
		# MEASURE THE LEDGER FROM ITS OWN SUBTREE, not from `words`.
		# `words` drops anything under three characters — a sane filter for prose,
		# and it silently deleted the label at the centre of the real bug: the deck
		# count reads "11". With that row missing the ledger's band appeared to
		# stop at y=136, the description starts at y=146, and this check concluded
		# the two could never meet. It reported NOTHING BURIED on a screen that was
		# photographed with the HUD spliced into the middle of a sentence.
		var hud_ink := INF
		var hud_band := Rect2()
		var hstack: Array = [hud]
		while not hstack.is_empty():
			var hn = hstack.pop_back()
			for hc in hn.get_children():
				hstack.push_back(hc)
			if not (hn is Control) or not (hn as Control).is_visible_in_tree():
				continue
			var ht := _norm(_text_of(hn as Control))
			if ht == "" or _effective_alpha(hn as Control) < 0.5:
				continue
			var wr := _glyph_rect(hn as Control, ht)
			if wr.size.x <= 1.0:
				continue
			hud_ink = minf(hud_ink, wr.position.x)
			hud_band = wr if hud_band.size.y <= 0.0 else hud_band.merge(wr)
		if hud_ink < INF:
			for w in words:
				var c: Control = w["n"]
				if c.get_parent() != node:
					continue          # absolutely-placed page furniture only
				var ink: Rect2 = w["r"]
				if ink.position.y > hud_band.end.y or ink.end.y < hud_band.position.y:
					continue          # different vertical band, cannot meet
				var head: float = hud_ink - ink.end.x
				if head < 0.0:
					_hits += 1
					print("  HIT   %-30s RUNS INTO THE HUD  \"%s\"" % [
						label, w["t"].substr(0, 34)])
					print("        ink ends x=%.0f, ledger ink starts x=%.0f "
						% [ink.end.x, hud_ink] + "(%.0f px INTO it)" % -head)
				elif head < 40.0:
					print("  warn  %-30s %.0f px from the HUD  \"%s\"" % [
						label, head, w["t"].substr(0, 30)])
				# The BOX is a promise to whoever authors the next event name.
				var box := c.get_global_rect()
				if box.end.x > hud_ink and head >= 0.0:
					print("        (box reaches x=%.0f, %.0f px past the ledger ink"
						% [box.end.x, box.end.x - hud_ink] + " — armed, not broken)")
	print("  ..    %-30s %d worded, %d opaque" % [label, words.size(), solids.size()])


# ── Driving ──────────────────────────────────────────────────────────────────

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


## A screen MainMenu builds over its own column. Boots the menu, waits for the
## staggered entrance, then calls the opener and scans what it left behind.
##
## The opener is called by NAME and guarded, deliberately: these are private
## functions on a scene script, and a rename should cost this pass one skipped
## state rather than take the whole gate down with a nonexistent-method error.
func _menu_subscreen(label: String, opener: String, via: String = "") -> void:
	_stage("default", 0)
	var n = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(n)
	await _settle()
	if not n.has_method(opener):
		print("  ..    %-30s SKIPPED — no %s()" % [label, opener])
		n.queue_free()
		await process_frame
		return
	# REACH THE SCREEN THE WAY A PLAYER DOES. Calling the opener straight off a
	# fresh title screen is not the same staging: the CURRENT RUN dossier is a
	# sibling of the Menu column that only `_show_hero_select` takes down, so a
	# direct call left it standing over the writ row and this pass reported a
	# perfectly real 48% overlap between "The Campaign Chest" and the dossier's
	# "30 / 30" — a defect of the driver, not of the screen.
	#
	# Fixed HERE rather than by a defensive removal in `_show_starting_bonus`,
	# which would make the gate pass without the staging being right.
	if via != "" and n.has_method(via):
		n.call(via)
		await _settle()
	n.call(opener)
	# Twice: these screens build a column and THEN tween it in, and the reveal is
	# still moving after one settle — a scan mid-tween reports overlaps that the
	# settled layout does not have.
	await _settle()
	await _settle()
	_scan(n, label)
	n.queue_free()
	await process_frame


func _simple(label: String, path: String, kind: String, hero_i: int) -> void:
	_stage(kind, hero_i)
	var n = load(path).instantiate()
	root.add_child(n)
	await _settle()
	_scan(n, label)
	n.queue_free()
	await process_frame


func _event(ev_id: String) -> void:
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
	await _settle()
	_scan(ev, "event:%s" % ev_id)
	ev.queue_free()
	await process_frame


## EVERY MODAL, DRIVEN WITH ITS OWN SHIPPED CONFIG.
##
## Event.gd creates NO CanvasLayer at all: all 26 `MODAL_EFFECTS` — the ten
## minigames and every card/relic picker — are plain children of the Event node,
## sharing a canvas with the stakes ledger and ordered only by tree order. That is
## the arrangement whose failure mode is already on the record here (the veterancy
## rung modals sat at layer 0 under a HUD on 12), and no pixel gate has ever seen
## one of these screens.
##
## The configs are LIFTED FROM EventDB rather than invented. A hand-written config
## tests the shape the probe author imagined; the shipped one tests the game. (The
## content census learned this the expensive way — it built its eligible set from
## the same wrong query it was checking, and agreed with itself.)
func _modal_states() -> Array:
	var EvScript = load("res://scripts/scenes/Event.gd")
	var modal_types: Array = EvScript.MODAL_EFFECTS
	var out: Array = []
	var seen := {}
	var ids: Array = EvScript.EVENTS.keys()
	ids.sort()
	for ev_id in ids:
		var ev_data: Dictionary = EvScript.EVENTS[ev_id]
		var pools: Array = []
		if ev_data.has("auto_effect"):
			pools.append(ev_data["auto_effect"])
		for ch in ev_data.get("choices", []):
			if ch is Dictionary:
				for e in ch.get("effects", []):
					pools.append(e)
		for e in pools:
			if not (e is Dictionary):
				continue
			var t := String((e as Dictionary).get("type", ""))
			if not modal_types.has(t):
				continue
			var sig := "%s|%s" % [t, str(e)]
			if seen.has(sig):
				continue
			seen[sig] = true
			out.append({"ev": String(ev_id), "effect": e, "type": t})
	return out


func _modal(state: Dictionary) -> void:
	_stage("rich", 1)
	var EvScript = load("res://scripts/scenes/Event.gd")
	var ev = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)
	await process_frame
	ev._clear_ui()
	ev._event_id = String(state["ev"])
	ev._event_data = EvScript.EVENTS[state["ev"]].duplicate(true)
	ev._current_node = ev._event_data
	ev._build_ui()
	await process_frame
	ev._apply_effect((state["effect"] as Dictionary).duplicate(true))
	await _settle(1.8)
	if is_instance_valid(ev):
		_scan(ev, "modal:%s" % state["type"])
		ev.queue_free()
	await process_frame


## COMBAT WITH A MODAL OPEN — the state the player is in whenever they ask a
## question mid-fight, and one no pixel gate had ever entered. The board scan
## alone cannot see it: the pile viewer, the glossary and the hover inspector are
## separate CanvasLayers that only exist once opened.
func _combat_modal(enc: String, what: String) -> void:
	_stage("default", 0)
	RS.current_encounter_id = enc
	RS.current_node_type = String(EDB.ENCOUNTERS[enc].get("type", "combat"))
	US.tooltip_delay = 0.0
	var cb = load("res://scenes/combat.tscn").instantiate()
	root.add_child(cb)
	await _settle(7.0)          # let the intro ceremony clear first
	match what:
		"pile":
			if cb._player_discard_pile.is_empty():
				for i in mini(8, RS.deck.size()):
					cb._player_discard_pile.append(RS.deck[i])
			cb._show_pile_viewer(1)
		"glossary":
			if cb.has_method("_reset_glossary_layer"):
				cb._reset_glossary_layer(0.56)
	await _settle(1.6)
	if is_instance_valid(cb):
		_scan(cb, "combat+%s" % what)
		cb.queue_free()
	await process_frame


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or US == null:
		print("[occl] FATAL: autoloads missing"); _done = true; quit(1); return
	US.anim_speed = 3.0
	US.end_turn_warning = false
	_canvas = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	print("[occl] CLASS C28 — occlusion & text-on-text, canvas %s\n" % str(_canvas))
	var only := OS.get_environment("BM_OCCL_ONLY")

	if only == "combat":
		for what in ["pile", "glossary"]:
			await _combat_modal("goblin_scouts", what)
		print("\n[occl] %d screen state(s)" % _states)
		print("[occl] %s" % ("NOTHING BURIED" if _hits == 0 else "%d HIT(S)" % _hits))
		_done = true
		quit(1 if _hits > 0 else 0)
		return

	if only == "event" or only == "modal":
		if only == "event":
			var ids: Array = load("res://scripts/scenes/Event.gd").EVENTS.keys()
			ids.sort()
			for ev_id in ids:
				await _event(String(ev_id))
		else:
			for st in _modal_states():
				await _modal(st)
		print("\n[occl] %d screen state(s)" % _states)
		print("[occl] %s" % ("NOTHING BURIED" if _hits == 0 else "%d HIT(S)" % _hits))
		_done = true
		quit(1 if _hits > 0 else 0)
		return

	await _simple("main_menu", "res://scenes/main_menu.tscn", "default", 0)
	# ── THE MENU'S OWN SUBSCREENS, which `_simple` cannot reach ──
	#
	# `main_menu` above is the title column and nothing else: every screen the
	# shell builds over it — run setup, the STARTING BONUS, the load slots — is a
	# programmatic rebuild of one VBox, so instantiating the scene lands on the
	# column and this pass has never seen any of them. Both C28's siblings had
	# the same hole and it was worth closing in `_probe_alignment` too: a gate is
	# only correct if it can OPEN the screen.
	#
	# The starting bonus earns its place first because it is the one shell screen
	# whose tiles carry stacked internal rows (heading band, name, body, a relic
	# preview, a signature row) plus an absolutely-placed wax seal — exactly the
	# shape that buries its own copy.
	await _menu_subscreen("starting_bonus", "_show_starting_bonus",
		"_show_hero_select")
	await _menu_subscreen("run_setup", "_show_hero_select")
	await _simple("collection", "res://scenes/collection.tscn", "default", 0)
	await _simple("credits", "res://scenes/credits.tscn", "default", 0)
	await _simple("net_lobby", "res://scenes/net_lobby.tscn", "default", 0)
	await _simple("map", "res://scenes/map.tscn", "default", 1)
	await _simple("reward", "res://scenes/reward.tscn", "rich", 1)
	await _simple("shop", "res://scenes/shop.tscn", "rich", 2)
	await _simple("rest", "res://scenes/rest.tscn", "default", 3)
	await _simple("treasure", "res://scenes/treasure.tscn", "rich", 3)
	await _simple("recruit", "res://scenes/recruit.tscn", "default", 4)
	await _simple("game_over", "res://scenes/game_over.tscn", "default", 4)
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
		await _modal(st)

	for enc in ["goblin_scouts", "bandit_camp", "rival_stalwart"]:
		if EDB != null and EDB.ENCOUNTERS.has(enc):
			_stage("default", 0)
			RS.current_encounter_id = enc
			RS.current_node_type = String(EDB.ENCOUNTERS[enc].get("type", "combat"))
			var n = load("res://scenes/combat.tscn").instantiate()
			root.add_child(n)
			# A CEREMONY IS NOT AN OCCLUSION. The boss-intro banner is a full-width
			# plate deliberately laid over the board, so a scan taken while it is
			# still up reports the lane numerals underneath it as buried. Wait the
			# ceremony out — an overlay that is STILL there after this is the real
			# finding, and one that has gone is not a defect at all.
			await _settle(7.0)
			_scan(n, "combat:%s" % enc)
			n.queue_free()
			await process_frame

	print("\n[occl] %d screen state(s)" % _states)
	print("[occl] %s" % ("NOTHING BURIED" if _hits == 0 else "%d HIT(S)" % _hits))
	_done = true
	quit(1 if _hits > 0 else 0)

