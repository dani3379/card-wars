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
	if OS.get_environment("BURNING_MEADOW_TEXTFIT_ONLY") == "run_setup":
		await _audit_main_menu_overlays()
		print("[textfit] targeted run-setup hits : %d" % _hits)
		quit(1 if _hits > 0 else 0)
		return

	await _audit_simple("main_menu", "res://scenes/main_menu.tscn")
	await _audit_main_menu_overlays()
	await _audit_simple("net_lobby", "res://scenes/net_lobby.tscn")
	await _audit_simple("net_draft", "res://scenes/net_draft.tscn")
	await _audit_simple("net_constructed", "res://scenes/net_constructed.tscn")
	await _audit_simple("net_quick", "res://scenes/net_quick.tscn")
	await _audit_simple("net_sealed", "res://scenes/net_sealed.tscn")
	await _audit_simple("collection", "res://scenes/collection.tscn")
	await _audit_simple("credits", "res://scenes/credits.tscn")

	# Map needs a generated run.
	_new_run("default")
	await _audit_simple("map", "res://scenes/map.tscn")

	# Combat (the HUD is the prime suspect — encounter names, banners).
	await _audit_all_combats()

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
	# Every event root screen. Nested result text is covered by copy_lint; this
	# catches the title/description/choice composition for the full live pool.
	var EvScript = load("res://scripts/scenes/Event.gd")
	var event_ids: Array = EvScript.EVENTS.keys()
	event_ids.sort()
	for ev_id in event_ids:
		_new_run("rich")
		await _audit_event(String(ev_id))
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
	quit(1 if _hits > 0 else 0)


func _audit_main_menu_overlays() -> void:
	var node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(node)
	for _i in 6:
		await process_frame

	node._show_quick_march()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:quick_hero")
	_expect_focus(node._hero_cards.get(node._selected_hero),
		"main_menu:quick_hero:first_hero")

	node._show_quick_company()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:quick_company")
	_expect_focus_name("QuickMarchTakeField",
		"main_menu:quick_company:take_field")
	node._show_muster_deck_inspector()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:deck_inspector")
	_expect_focus_name("DeckInspectorReturn", "main_menu:deck_inspector:return")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	node._unhandled_input(cancel)
	if node._deck_inspect_overlay != null:
		_hits += 1
		print("[textfit] HIT main_menu:deck_inspector:ui_cancel did not close")
	else:
		print("[textfit] main_menu:deck_inspector:ui_cancel : ok")
	for _i in 2:
		await process_frame
	_expect_focus_name("QuickMarchTakeField",
		"main_menu:deck_inspector:restores_trigger")

	# THE MUSTER is four steps; Terms and Orders are the two variable-height screens.
	# Scan all four, not just the step the entry point lands on.
	node._show_hero_select()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:muster_host")
	_expect_focus(node._hero_cards.get(node._selected_hero),
		"main_menu:muster_host:selected_hero")

	# RUN SETUP is one screen and the bonus is the screen after it (2026-09-16),
	# so there are two surfaces to scan, not four steps.
	node._show_muster_step(1)
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:run_setup")
	_expect_focus_name("MusterTakeField", "main_menu:run_setup:start_run")
	node._show_starting_bonus()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:starting_bonus")
	node._toggle_muster_advanced()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:muster_advanced")
	_expect_focus_name("MusterTakeField",
		"main_menu:muster_advanced:take_field")
	node._selected_ascension = 5
	node._update_asc_rules_text()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:muster_advanced_asc5")
	_expect_focus_name("MusterTakeField",
		"main_menu:muster_advanced_asc5:take_field")
	node._daily_pick = true
	node._muster_seed_text = "confidence-audit"
	node._toggle_muster_advanced()
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:muster_orders_active_rules")
	_expect_focus_name("MusterTakeField",
		"main_menu:muster_orders_active_rules:take_field")


	node._show_how_to_play()
	for _i in 4:
		await process_frame
	var how_to = node.get_node_or_null("HowToPlayOverlay")
	if how_to != null:
		_scan(how_to, "main_menu:how_to_play:first_battle")
		var keyword_tab = how_to.find_child("KeywordsTab", true, false)
		if keyword_tab is Button:
			keyword_tab.pressed.emit()
			for _i in 3:
				await process_frame
			_scan(how_to, "main_menu:how_to_play:keywords")

	# The writ pickers: the only screens MainMenu still lays out AFTER the run has
	# started. Replaces the old THE WAR CHEST scan (2026-08-01 — that screen was
	# deleted; its follow-up card grid is what survived and is what can overflow).
	_new_run("rich")
	node._pick_blessing({"effect": "forge", "value": 1})
	for _i in 8:
		await process_frame
	_scan(node, "main_menu:writ_forge_picker")
	node.free()
	await process_frame


func _expect_focus(expected, label: String) -> void:
	var owner := root.gui_get_focus_owner()
	if expected != null and owner == expected:
		print("[textfit] %s focus : ok" % label)
		return
	_hits += 1
	print("[textfit] HIT %s : expected focus owner, got %s" % [
		label, owner.name if owner != null else "NONE"])


func _expect_focus_name(expected_name: String, label: String) -> void:
	var owner := root.gui_get_focus_owner()
	if owner != null and String(owner.name) == expected_name:
		print("[textfit] %s focus : ok" % label)
		return
	_hits += 1
	print("[textfit] HIT %s : expected '%s', got %s" % [
		label, expected_name, String(owner.name) if owner != null else "NONE"])


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


## THIS DRIVER SEATED NOTHING FOR AS LONG AS IT HAS EXISTED (found 2026-09-02).
##
## `Event._ready` calls `_pick_event()`, which ROLLS one out of the pool. Setting
## `_event_id` afterwards and calling `_show_event()` / `_build_event()` did not
## re-seat it, because NEITHER METHOD EXISTS on Event.gd — the `has_method` chain
## fell through in silence and the screen kept whatever the roll had produced. So
## this loop asked for 46 distinct events and scanned the same handful of rolled
## ones over and over: verified by asking for 14 and getting 9 distinct screens,
## none of them the one requested. The pool's per-event text has never been
## measured, only its label said so.
##
## `_probe_boundary_ui` had the working recipe all along — tear the rolled screen
## down with `_clear_ui()`, seat the fields, rebuild with `_build_ui()`.
func _audit_event(ev_id: String) -> void:
	var EvScript = load("res://scripts/scenes/Event.gd")
	if not EvScript.EVENTS.has(ev_id):
		return
	var ev = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)
	await process_frame
	ev._clear_ui()
	ev._event_id = ev_id
	ev._event_data = EvScript.EVENTS[ev_id].duplicate(true)
	ev._current_node = ev._event_data
	ev._build_ui()
	for _i in 6:
		await process_frame
	# Cheap self-check: if the pool's own name is not on the screen the driver has
	# stopped seating again, and every "ok" below would be about another room.
	# EXEMPT the auto_effect rooms — an event with no choices and an `auto_effect`
	# (strangers_hand → the Wet Cards deal) hands straight off to a modal that
	# replaces the page, so its own name is legitimately not on screen.
	var seats: bool = not EvScript.EVENTS[ev_id].has("auto_effect")
	if seats and not _screen_mentions(ev, String(EvScript.EVENTS[ev_id].get("name", ""))):
		_hits += 1
		print("[textfit] HIT event:%s : driver did not seat this event" % ev_id)
	_scan(ev, "event:%s" % ev_id)
	ev.free()


func _screen_mentions(node: Node, needle: String) -> bool:
	if needle.strip_edges() == "":
		return true
	var want := needle.to_lower()
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for ch in n.get_children():
			stack.push_back(ch)
		if n is Control and _text_of(n as Control).to_lower().find(want) >= 0:
			return true
	return false


func _audit_all_combats() -> void:
	var EDB = root.get_node_or_null("EncounterDB")
	if EDB == null:
		print("[textfit] combat : (no EncounterDB)")
		return
	var encounter_ids: Array = EDB.ENCOUNTERS.keys()
	encounter_ids.sort()
	var first := true
	for id_value in encounter_ids:
		var enc_id := String(id_value)
		_new_run("default")
		RS.current_encounter_id = enc_id
		RS.current_node_type = String(EDB.ENCOUNTERS[id_value].get("type", "combat"))
		var node = load("res://scenes/combat.tscn").instantiate()
		root.add_child(node)
		for _i in (30 if first else 12):
			await process_frame
		first = false
		_scan(node, "combat:%s" % enc_id)
		node.free()
		await process_frame

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
		if String(d.get("type", "")) not in ["creature", "spell", "armament"]:
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
			print("[textfit] %s | %s | \"%s\" | %s | path=%s rect=%s" % [
				scene, c.get_class(), _short(txt), verdict,
				str(c.get_path()), str(c.get_global_rect())])
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
	# An overrun-trimmed label/button (TRIM/ELLIPSIS) elides its string to the
	# rect — it never paints past its box, so "wider than box" is a false hit
	# (2026-07-20: the Collection placeholder-tile names). Content hidden behind
	# the ellipsis is a design choice (hover shows the full card), not overflow.
	var elided := false
	if c is Label:
		elided = (c as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
	elif c is Button:
		elided = (c as Button).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var msgs: Array = []
	# Overflow of own box — LOCAL units on both sides (ts is unscaled; c.size
	# is the local rect), so scaled card previews measure the same as at 1×.
	if not autowrap and not elided and ts.x > c.size.x + TOL:
		var clip := (c is Label and (c as Label).clip_text)
		msgs.append("text wider than box by %.0fpx%s" % [ts.x - c.size.x, " (clipped)" if clip else ""])
	if _in_clipper(c):
		return ", ".join(msgs)
	# Where the text lands on the CANVAS — global units, so scale the extent.
	# An autowrapped label folds to its rect, so its landing is the rect itself;
	# only unwrapped text can poke past its box onto (or off) the canvas.
	var sc := c.get_global_transform().get_scale()
	var tsg := minf(ts.x * sc.x, g.size.x) if (autowrap or elided) else ts.x * sc.x
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
