extends SceneTree
## Text-overflow / off-canvas audit (2026-06-29).
##
## Boots each player-facing screen headless, lets layout settle, then walks every
## visible Label / Button / LineEdit / RichTextLabel and computes where its TEXT
## actually lands on the 1600×900 design canvas. Flags any text whose on-screen
## extent crosses a canvas edge (off-screen) or whose content overflows its own
## box (clipped). Layout + font metrics are exact headless, so this finds the
## "text runs off the screen" cases without eyeballing screenshots.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_textfit.gd

const TOL := 2.0          # px slack before a crossing counts (rounding noise)
const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]

var RS: Node
var CDB: Node
var RDB: Node
var US: Node
var W := 1600.0
var H := 900.0
var _hits := 0
var _scenes := 0
var _seq := 0
var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	RS  = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	RDB = root.get_node_or_null("RelicDB")
	US  = root.get_node_or_null("UserSettings")
	W = float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600))
	H = float(ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	print("[textfit] canvas = %.0f x %.0f" % [W, H])

	await _audit_simple("main_menu", "res://scenes/main_menu.tscn")
	await _audit_simple("collection", "res://scenes/collection.tscn")
	await _audit_simple("credits", "res://scenes/credits.tscn")

	# Map needs a generated run.
	_new_run("default")
	await _audit_simple("map", "res://scenes/map.tscn")

	# Combat (the HUD is the prime suspect — encounter names, banners).
	await _audit_combat()

	# Reward / Shop / Rest / Treasure / Recruit / Wayside / Event / GameOver.
	_new_run("rich"); RS.current_node_type = "elite"; RS.current_floor = 3
	await _audit_simple("reward(elite)", "res://scenes/reward.tscn")
	_new_run("rich")
	await _audit_simple("shop", "res://scenes/shop.tscn")
	_new_run("default"); RS.hero_hp = 5
	await _audit_simple("rest", "res://scenes/rest.tscn")
	_new_run("rich")
	await _audit_simple("treasure", "res://scenes/treasure.tscn")
	_new_run("default")
	await _audit_simple("recruit", "res://scenes/recruit.tscn")
	for verb in ["drill_yard", "muster_scale", "standard_bearer", "supply_cache"]:
		_new_run("rich")
		RS.current_wayside_id = verb
		await _audit_simple("wayside:%s" % verb, "res://scenes/wayside.tscn")
	# A spread of events — long descriptions + many choices are the classic overflow.
	for ev_id in ["butcher", "the_bone_pit", "woodcutter", "sin_eater", "strangers_hand",
			"dark_altar", "the_chrysalis", "pawnbrokers_window", "thrice_blessed_spring"]:
		_new_run("rich")
		await _audit_event(ev_id)
	_new_run("default"); RS.hero_hp = 0
	await _audit_simple("game_over", "res://scenes/game_over.tscn")

	# Settings overlay (lives on the UserSettings autoload) — text-dense rows.
	await _audit_settings()

	# Hover tooltips: the card detail panel is the same on every screen, built only
	# on hover, and its width is NOT viewport-clamped (only its bottom is). Scan
	# every draftable card's tooltip for off-canvas / overflow.
	await _audit_card_tooltips()

	print("[textfit] ============ SUMMARY ============")
	print("[textfit] screens scanned : %d" % _scenes)
	print("[textfit] off-canvas / overflow text hits : %d" % _hits)
	print("[textfit] DONE")
	quit(0)


func _new_run(kind: String) -> void:
	_seq += 1
	RS.start_new_run(HEROES[_seq % HEROES.size()], 0, 4242 + _seq)
	match kind:
		"rich":
			RS.gold = 800
			RS.hero_hp = RS.hero_max_hp
		"default":
			RS.gold = 150


func _audit_simple(label: String, path: String) -> void:
	var node = load(path).instantiate()
	root.add_child(node)
	for _i in 6:
		await process_frame
	_scan(node, label)
	node.free()


func _audit_event(ev_id: String) -> void:
	var ev = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)
	var EvScript = load("res://scripts/scenes/Event.gd")
	if EvScript.EVENTS.has(ev_id):
		ev._event_id = ev_id
		ev._event_data = EvScript.EVENTS[ev_id]
		ev._current_node = ev._event_data
		if ev.has_method("_show_event"):
			ev._show_event()
		elif ev.has_method("_build_event"):
			ev._build_event()
	for _i in 6:
		await process_frame
	_scan(ev, "event:%s" % ev_id)
	ev.free()


func _audit_combat() -> void:
	_new_run("default")
	# A real act-1 fight with a longish name if possible.
	var enc_id := ""
	var EDB = root.get_node_or_null("EncounterDB")
	if EDB != null:
		for id in EDB.ENCOUNTERS.keys():
			var d: Dictionary = EDB.ENCOUNTERS[id]
			if int(d.get("act", 1)) == 1 and String(d.get("type", "combat")) == "combat":
				enc_id = String(id)
				break
	if enc_id != "":
		RS.current_encounter_id = enc_id
	RS.current_node_type = "combat"
	var node = load("res://scenes/combat.tscn").instantiate()
	root.add_child(node)
	for _i in 30:    # combat _ready awaits the prebake; give it room
		await process_frame
	_scan(node, "combat")
	node.free()


# ── The scan ─────────────────────────────────────────────────────────────────

func _audit_settings() -> void:
	if US == null:
		print("[textfit] settings : (no UserSettings)")
		return
	var ov = null
	for ch in US.get_children():
		if ch.has_method("_open") and "_panel_root" in ch:
			ov = ch
			break
	if ov == null:
		print("[textfit] settings : overlay node not found")
		return
	# Open with a run active (PAUSED state shows the most rows).
	_new_run("rich")
	ov._open()
	for _i in 4:
		await process_frame
	var fit := 1.0
	if ov._panel_root != null:
		fit = ov._panel_root.scale.x
		if fit < 0.999:
			# Panel auto-scaled to fit (small window) → my unscaled text math would be
			# off; note it instead of reporting false hits.
			print("[textfit] settings : panel fit-scaled to %.2f (fits by shrinking, not clipping)" % fit)
		else:
			_scan(ov._panel_root, "settings")
	ov._panel_root.visible = false
	if "_backdrop" in ov and ov._backdrop != null:
		ov._backdrop.visible = false
	ov._is_open = false


func _audit_card_tooltips() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var CardScene = load("res://scenes/card_2d.tscn")
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	var tested := 0
	var bad := 0
	for id in ids:
		var d: Dictionary = CDB.CARD_POOL[id]
		if String(d.get("type", "")) not in ["creature", "spell"]:
			continue
		if String(d.get("rarity", "")) == "enemy" or CDB.is_curse(String(id)):
			continue
		var card = CardScene.instantiate()
		card.card_data = d.duplicate(true)
		card.card_id = String(id)
		host.add_child(card)
		card._is_hovered = true
		if card.has_method("_show_detail_panel"):
			card._show_detail_panel()
		await process_frame
		await process_frame
		var popup = card._detail_popup
		if popup != null and is_instance_valid(popup) and popup.is_visible_in_tree():
			var before := _hits
			_scan(popup, "tooltip:%s" % id, true)
			if _hits > before:
				bad += 1
		tested += 1
		if card.has_method("_hide_detail_panel"):
			card._hide_detail_panel()
		card.free()
		await process_frame
	host.free()
	print("[textfit] card tooltips: %d tested, %d with overflow" % [tested, bad])


func _scan(node: Node, scene: String, quiet: bool = false) -> void:
	_scenes += 1
	var found := 0
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for ch in n.get_children():
			stack.push_back(ch)
		if not (n is Control):
			continue
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		if c.modulate.a < 0.05 or c.self_modulate.a < 0.05:
			continue
		var txt := _text_of(c)
		if txt.strip_edges() == "":
			continue
		var verdict := _check(c, txt)
		if verdict != "":
			found += 1
			_hits += 1
			print("[textfit] %s | %s | \"%s\" | %s" % [
				scene, c.get_class(), _short(txt), verdict])
	if found == 0 and not quiet:
		print("[textfit] %s : ok" % scene)


func _text_of(c: Control) -> String:
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


func _check(c: Control, txt: String) -> String:
	var g := c.get_global_rect()
	# Scrollable / clipped content is allowed to extend past the canvas — a
	# forge strip or credits roll below the fold is UI, not a bug. (2026-07-06:
	# this and the local-units fix below cut ~40 false hits per run.)
	var clipped := _in_clipper(c)
	# RichTextLabel: text autowraps to the rect, so horizontal overflow is rare;
	# the real failure is the RECT itself off-canvas, or content taller than the box.
	if c is RichTextLabel:
		var rtl := c as RichTextLabel
		var msgs: Array = []
		if not clipped and (g.position.x < -TOL or g.end.x > W + TOL \
				or g.position.y < -TOL or g.end.y > H + TOL):
			msgs.append("rect off-canvas %s" % _edge(g))
		# Content height is LOCAL units — compare against the local box size,
		# not the (scaled) global rect, or every 0.72×/0.4× card preview
		# false-positives by exactly the scale factor.
		if not rtl.scroll_active and rtl.get_content_height() > c.size.y + 4.0:
			msgs.append("text taller than box (%.0f>%.0f, bottom clipped)" % [rtl.get_content_height(), c.size.y])
		return ", ".join(msgs)

	# Label / Button / LineEdit: compute the text's pixel extent and where it lands.
	var font: Font = c.get_theme_font("font")
	if font == null:
		return ""
	var fs := c.get_theme_font_size("font_size")
	if fs <= 0:
		fs = 16
	var autowrap := false
	if c is Label:
		autowrap = (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var msgs: Array = []
	# Overflow of own box — LOCAL units on both sides (ts is unscaled; c.size
	# is the local rect), so scaled card previews measure the same as at 1×.
	if not autowrap and ts.x > c.size.x + TOL:
		var clip := (c is Label and (c as Label).clip_text)
		msgs.append("text wider than box by %.0fpx%s" % [ts.x - c.size.x, " (clipped)" if clip else ""])
	if _in_clipper(c):
		return ", ".join(msgs)
	# Where the text lands on the CANVAS — global units, so scale the extent.
	# An autowrapped label folds to its rect, so its landing is the rect itself;
	# only unwrapped text can poke past its box onto (or off) the canvas.
	var sc := c.get_global_transform().get_scale()
	var tsg := minf(ts.x * sc.x, g.size.x) if autowrap else ts.x * sc.x
	var halign := HORIZONTAL_ALIGNMENT_LEFT
	if c is Label:
		halign = (c as Label).horizontal_alignment
	elif c is Button:
		halign = (c as Button).alignment
	var tl := g.position.x
	match halign:
		HORIZONTAL_ALIGNMENT_CENTER: tl = g.position.x + (g.size.x - tsg) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:  tl = g.end.x - tsg
	var tr := tl + tsg
	if tl < -TOL:
		msgs.append("off LEFT by %.0fpx" % (-tl))
	if tr > W + TOL:
		msgs.append("off RIGHT by %.0fpx" % (tr - W))
	if g.position.y < -TOL:
		msgs.append("off TOP by %.0fpx" % (-g.position.y))
	if g.end.y > H + TOL:
		msgs.append("off BOTTOM by %.0fpx" % (g.end.y - H))
	return ", ".join(msgs)


## True when any ancestor clips this control's overflow (ScrollContainer or an
## explicit clip_contents) — its content extending past the canvas is scrolling
## UI working as designed, not a layout defect.
func _in_clipper(c: Control) -> bool:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		if n is Control and (n as Control).clip_contents:
			return true
		n = n.get_parent()
	return false


func _edge(g: Rect2) -> String:
	var parts: Array = []
	if g.position.x < -TOL: parts.append("L%.0f" % -g.position.x)
	if g.end.x > W + TOL: parts.append("R%.0f" % (g.end.x - W))
	if g.position.y < -TOL: parts.append("T%.0f" % -g.position.y)
	if g.end.y > H + TOL: parts.append("B%.0f" % (g.end.y - H))
	return "(" + " ".join(parts) + ")"


func _short(s: String) -> String:
	var one := s.replace("\n", " ").strip_edges()
	return one.substr(0, 46) + ("…" if one.length() > 46 else "")
