extends Control
## NetDeckBuilder — shared base for the four online deck-acquisition screens
## (NetQuick / NetConstructed / NetSealed / NetDraft).
##
## Online Skirmish's combat is mode-agnostic, so a "mode" is just a
## deck-acquisition scene plus a MODE_DEFS entry. Those four scenes had drifted
## into carrying their own verbatim copies of the same palette, scene constants,
## sync flags, and (for the pool-based builders) an identical card-thumbnail
## helper. This base owns that shared surface so the modes can't diverge on it;
## each subclass keeps only its bespoke layout + netcode.
##
## Deliberately thin: it holds data + one stateless helper, NOT _ready or the
## scaffold, so it changes no runtime flow. Subclasses still drive their own
## lifecycle and override _on_add where they accept pool clicks.

# ── Shared scene constants ───────────────────────────────────────────────────
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MAX_COPIES: int = 2           # per-id deck cap (Quick/Constructed; Sealed uses its own)
const THUMB_SCALE: float = 0.46     # pool/deck card-thumbnail scale
const THUMB_SIZE := Vector2(225.0, 300.0) * THUMB_SCALE
const HAND_BACK_CLOSE_SECONDS := 0.13
const HAND_FACE_OPEN_SECONDS := 0.17

# Hover-to-enlarge preview: pool/deck thumbnails are small, so hovering one pops
# the full card beside it (the "window showing the card you hover"). Native card
# size; named _hover_* so it doesn't collide with NetDraft's own bespoke preview.
const HOVER_CARD_SCENE := preload("res://scenes/card_2d.tscn")
const NET_BATCHED_CHART_STYLE := preload("res://scripts/ui/BatchedChartPanelStyle.gd")
const HOVER_PREVIEW_W := 225.0
const HOVER_PREVIEW_H := 300.0

# ── Shared palette (the Skirmish lobby family — NOT GameTheme's; the gilt here
# is warmer at (1.0, 0.85, 0.45) vs GameTheme's (1.0, 0.88, 0.35)). ───────────
const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
# Verdigris + gilt, not web-green + web-blue — see the note on NetLobby's
# matching constants. These are the only cool saturated inks the skirmish
# screens ever reached for, and they broke the sepia world every other screen
# keeps.
const GREEN := Color(0.55, 0.78, 0.70, 1.0)      # verdigris — ready / connected
const RED_WARN := Color(0.90, 0.45, 0.35, 1.0)
const HOST_BLUE := Color(0.86, 0.72, 0.34, 1.0)  # affirmative gilt
const SPELL_BLUE := Color(0.70, 0.88, 1.0, 1.0)

# ── Shared state ─────────────────────────────────────────────────────────────
var _target: int = 20               # SkirmishState.DECK_TARGET (set in each _ready)
var _rng := RandomNumberGenerator.new()
var _local_finished: bool = false
var _remote_finished: bool = false
var _combat_launch_started: bool = false
var _menu_exit_started: bool = false

var _root: VBoxContainer
var _header: Label

# Pool-based builders (Constructed / Sealed) index their clickable pool tiles
# here: id -> {"button": Button, "badge": Label, "card": Card2D}. Unused by the
# Quick/Draft modes, which don't present a browsable pool.
var _pool_rows: Dictionary = {}

# ── Hover preview (shared by the pool-based builders) ─────────────────────────
var _hover_preview: Control = null    # the live enlarged Card2D, or null
var _hover_anchor: Control = null     # the tile it's pinned beside
var _hover_id: String = ""            # card id currently previewed

## Dense net builders repeat the rich chart plate across columns, controls and
## every three-choice Arsenal slate. Preserve its silhouette, colors, margins
## and interaction states while collapsing each face/rim/tack stack into one
## indexed draw submission. This stays local to Skirmish screens; hero panels
## and campaign set pieces keep the full hand-cut detail.
func _flatten_net_chart_styles(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	var converted: Dictionary = {}
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			var control := node as Control
			var slots: Array[StringName] = []
			if control is PanelContainer:
				slots.append(&"panel")
			if control is Button:
				slots.append_array([
					&"normal", &"focus", &"hover", &"pressed", &"disabled"])
			for slot in slots:
				if not control.has_theme_stylebox_override(slot):
					continue
				var source: StyleBox = control.get_theme_stylebox(slot)
				if source is GameTheme.ChartPanelStyle:
					control.add_theme_stylebox_override(
						slot, _net_batched_chart_style(source, converted))
			for meta_key in [&"style_rest", &"style_sel"]:
				if not control.has_meta(meta_key):
					continue
				var meta_style = control.get_meta(meta_key)
				if meta_style is GameTheme.ChartPanelStyle:
					control.set_meta(meta_key,
						_net_batched_chart_style(meta_style, converted))
		for child in node.get_children():
			stack.append(child)


func _net_batched_chart_style(source: StyleBox,
		converted: Dictionary) -> StyleBox:
	var source_id := source.get_instance_id()
	if converted.has(source_id):
		return converted[source_id]
	var batched: StyleBox = NET_BATCHED_CHART_STYLE.from_chart(source)
	converted[source_id] = batched
	return batched


# Builds one clickable pool tile from a card id and registers it in _pool_rows.
# Identical across the pool-based modes; clicking routes to the subclass _on_add.
func _build_pool_thumb(id: String,
		cached_data: Dictionary = {}) -> Control:
	var d: Dictionary = cached_data if not cached_data.is_empty() \
		else SkirmishState.skirmish_card_data(id)
	var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
	var btn := thumb["button"] as Button
	btn.pressed.connect(_on_add.bind(id))
	btn.tooltip_text = String(d.get("name", id))
	_attach_hover_preview(btn, id)
	_pool_rows[id] = {"button": btn, "badge": thumb["badge"], "card": thumb["card"]}
	return thumb["root"]


# Overridden by pool-based subclasses to add the clicked card to the deck. The
# base no-op lets _build_pool_thumb wire its signal uniformly; modes without a
# pool simply never call it.
func _on_add(_id: String) -> void:
	pass


# ── Shared builder-column plate (Constructed / Sealed) ───────────────────────
## One builder column: a house plate with a header band (gilt label + trailing
## hairline) over a thin-scrollbar card flow. Returns {panel, header, col,
## scroll, flow} — `col` is the inner VBox for extra rows under the scroll.
func _make_builder_column(header_text: String, ratio: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	var style := GameTheme.make_panel_style(Color(0.055, 0.048, 0.040, 0.90),
		Color(0.60, 0.51, 0.34, 0.60), 1, 5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	col.add_child(hrow)
	var header := GameTheme.make_label(header_text, 15, GILT_BRIGHT)
	hrow.add_child(header)
	var rule := ColorRect.new()
	rule.color = Color(0.60, 0.51, 0.34, 0.40)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	GameTheme.style_thin_scrollbar(scroll)
	col.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)

	return {"panel": panel, "header": header, "col": col, "scroll": scroll,
		"flow": flow}


## A fixed vacant card footprint for editable warbands. Real cards replace these
## one-for-one, so adding a duplicate never shortens the flow or recentres every
## card around it.
func _make_deck_ghost_slot() -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = THUMB_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.045, 0.035, 0.55)
	sb.border_color = Color(0.52, 0.42, 0.22, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", sb)
	return slot


## Draft-finished messages can make the readiness predicate true more than once.
## Claim it once so two ink covers (or two scene changes) can never race.
func _claim_combat_launch() -> bool:
	if _combat_launch_started or not (_local_finished and _remote_finished):
		return false
	_combat_launch_started = true
	return true


# ── Command-curve strip (Constructed / Sealed) ───────────────────────────────
# The warband column is mostly empty air until the deck fills, and a cost
# histogram is the one readout that actually helps you build — so the empty
# space earns its keep. Bars grow upward from a fixed baseline; the tallest
# bucket sets the scale, so the shape reads at any deck size.
const CURVE_BUCKETS := 7      # costs 0..5, then 6+
const CURVE_BAR_H := 46.0

var _curve_bars: Array = []   # [{bar: CurveBar, count: Label}]


## One histogram bucket, drawn as stacked Command-navy plates — one per card —
## so the count reads in the bar itself and nothing renders as a flat rectangle.
class CurveBar extends Control:
	var count := 0
	var peak := 1

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if count <= 0:
			# Faint baseline tick: the empty bucket is still a station.
			draw_rect(Rect2(0, h - 2, w, 2), Color(0.75, 0.65, 0.45, 0.18))
			return
		var seg_h := (h - 2.0) / float(maxi(peak, 4))
		var gap := 1.0 if seg_h >= 5.0 else 0.0
		for i in count:
			var y_top := h - seg_h * float(i + 1)
			var r := Rect2(1, y_top + gap * 0.5, w - 2, seg_h - gap)
			draw_rect(r, Color(0.13, 0.18, 0.33, 0.95))
			# Lit top edge per plate — stacked ingots, not a fill.
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1),
				Color(0.36, 0.46, 0.68, 0.8))
		# Gilt cap on the whole stack.
		draw_rect(Rect2(0, h - seg_h * float(count) - 1, w, 1),
			Color(0.91, 0.71, 0.28, 0.6))


func _make_curve_strip() -> Control:
	_curve_bars.clear()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)

	root.add_child(GameTheme.make_label("COMMAND CURVE", 12, GameTheme.GILT))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)

	for i in CURVE_BUCKETS:
		var bucket := VBoxContainer.new()
		bucket.add_theme_constant_override("separation", 2)
		bucket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bucket)

		var cnt := GameTheme.make_label("", 11, IVORY)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bucket.add_child(cnt)

		# Fixed-height well; the bar hugs its bottom edge and grows up.
		var well := Control.new()
		well.custom_minimum_size = Vector2(0, CURVE_BAR_H)
		well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bucket.add_child(well)

		var bar := CurveBar.new()
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well.add_child(bar)

		var lbl := GameTheme.make_label(
			"6+" if i == CURVE_BUCKETS - 1 else str(i), 11, ASH)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bucket.add_child(lbl)

		_curve_bars.append({"bar": bar, "count": cnt})
	return root


## Repaint the curve from a list of card ids (the working deck).
func _refresh_curve(deck_ids: Array) -> void:
	if _curve_bars.is_empty():
		return
	var counts: Array[int] = []
	counts.resize(CURVE_BUCKETS)
	counts.fill(0)
	for raw in deck_ids:
		var c := int(CardDB.get_card_data(String(raw)).get("cost", 0))
		counts[clampi(c, 0, CURVE_BUCKETS - 1)] += 1
	var peak := 1
	for n in counts:
		peak = maxi(peak, n)
	for i in _curve_bars.size():
		var refs: Dictionary = _curve_bars[i]
		var n: int = counts[i]
		var bar: CurveBar = refs.bar
		var grew := false
		if is_instance_valid(bar):
			grew = n > bar.count
			bar.count = n
			bar.peak = peak
			bar.queue_redraw()
		var cl: Label = refs.count
		if is_instance_valid(cl):
			cl.text = str(n) if n > 0 else ""
			# A landing plate flashes its count — the curve answers the click.
			if grew:
				GameTheme.pulse_label(cl)


## Ink-well text field — dark parchment recess with a tan hairline (gilt on
## focus), so text entry sits in the chart language instead of OS chrome.
func _make_ink_field(default_text: String, width: int, placeholder: String) -> LineEdit:
	var f := LineEdit.new()
	f.text = default_text
	f.placeholder_text = placeholder
	f.custom_minimum_size = Vector2(width, 32)
	if GameTheme.font_body:
		f.add_theme_font_override("font", GameTheme.font_body)
	f.add_theme_font_size_override("font_size", 16)
	f.add_theme_color_override("font_color", IVORY)
	f.add_theme_color_override("font_placeholder_color", Color(0.60, 0.55, 0.45, 0.65))
	f.add_theme_color_override("caret_color", GILT_BRIGHT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.015, 0.01, 0.85)
	box.border_color = Color(0.60, 0.51, 0.34, 0.75)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	f.add_theme_stylebox_override("normal", box)
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = GILT_BRIGHT
	f.add_theme_stylebox_override("focus", focus)
	return f


## House chip dressing for an OptionButton (saved-deck picker) — the stock
## grey OS control breaks the plate it sits on.
func _style_option_chip(ob: OptionButton) -> void:
	if GameTheme.font_body:
		ob.add_theme_font_override("font", GameTheme.font_body)
	ob.add_theme_font_size_override("font_size", 16)
	ob.add_theme_color_override("font_color", IVORY)
	ob.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	ob.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.46, 0.6))
	var normal := GameTheme.make_btn_style(
		Color(0.055, 0.048, 0.040, 0.92), Color(0.60, 0.51, 0.34, 0.55), 3)
	var hover := GameTheme.make_btn_style(
		Color(0.075, 0.065, 0.052, 0.95), GILT_BRIGHT, 3)
	ob.add_theme_stylebox_override("normal", normal)
	ob.add_theme_stylebox_override("focus", normal)
	ob.add_theme_stylebox_override("disabled", normal)
	ob.add_theme_stylebox_override("hover", hover)
	ob.add_theme_stylebox_override("pressed", hover)


# ── Shared Esc + settings chrome ─────────────────────────────────────────────
# All four deck screens (Quick / Constructed / Sealed / Draft) inherit this.
# _install_net_chrome() drops the top-left settings gear; each subclass calls it
# from its own _ready (the base deliberately has none). Esc mirrors the BACK
# button: drop the peer connection and return to the menu.
func _install_net_chrome() -> void:
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave_to_menu()
		get_viewport().set_input_as_handled()


## One exit for Esc and every disconnect-state BACK button. Once combat has
## armed its deferred scene swap, leaving is no longer a valid competing route.
func _leave_to_menu(source: Control = null) -> void:
	if _menu_exit_started or _combat_launch_started \
			or SkirmishState.launch_armed:
		return
	_menu_exit_started = true
	if source != null and is_instance_valid(source) and source is BaseButton:
		(source as BaseButton).disabled = true
	NetMatch.leave()
	var can_animate := DisplayServer.get_name() != "headless" \
		and (UserSettings == null or not UserSettings.reduce_motion)
	if can_animate:
		GameTheme.fade_out_then_change_scene(self, MENU_SCENE, 0.30,
			_transition_origin(source, Vector2(0.08, 0.10)))
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _transition_origin(source: Control, fallback: Vector2) -> Vector2:
	if source == null or not is_instance_valid(source):
		return fallback
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return fallback
	var center := source.global_position + source.size * 0.5
	return Vector2(center.x / viewport_size.x, center.y / viewport_size.y)


# ─────────────────────────────────────────────────────────────────────────
#  HOVER PREVIEW
#
#  Wire any thumbnail's hover (its full-rect Button, which keeps emitting
#  mouse_entered even when disabled) to pop a full-size card beside it. Used
#  for both pool tiles (via _build_pool_thumb) and the built-deck tiles (the
#  subclasses call _attach_hover_preview on those Buttons too).
# ─────────────────────────────────────────────────────────────────────────

func _attach_hover_preview(anchor: Control, id: String) -> void:
	anchor.mouse_entered.connect(_show_hover_preview.bind(id, anchor))
	anchor.mouse_exited.connect(_hide_hover_preview.bind(id))


func _show_hover_preview(id: String, anchor: Control) -> void:
	# Disabled buttons still emit mouse_entered in Godot. A loading tile must not
	# leak its expensive full face before the rest of its hand turns with it.
	if anchor == null or bool(anchor.get_meta("card_loading", false)):
		return
	if id == _hover_id and is_instance_valid(_hover_preview):
		return
	_clear_hover_preview()
	_hover_id = id
	_hover_anchor = anchor
	var card := HOVER_CARD_SCENE.instantiate()
	card.card_data = SkirmishState.skirmish_card_data(id)
	card.card_id = id
	card.is_on_battlefield = true       # full card, no drag / hover-lift
	card.live_baked_mode = true
	CardTextureCache.bake(card.card_data)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)                     # sibling above _root; not clipped by scrolls
	_hover_preview = card
	_place_hover_preview()


func _hide_hover_preview(id: String) -> void:
	# Guard on id so moving tile→tile (new enter fires before the old exit) can't
	# tear down the preview that just opened for the tile we moved onto.
	if id == _hover_id:
		_clear_hover_preview()


func _clear_hover_preview() -> void:
	if is_instance_valid(_hover_preview):
		_hover_preview.queue_free()
	_hover_preview = null
	_hover_anchor = null
	_hover_id = ""


# Drop the preview only if it's pinned to a tile inside `container` — called
# before a panel rebuild frees its tiles, so a stale anchor can't linger while
# a preview pinned to the *other* column survives the refresh untouched.
func _clear_hover_preview_under(container: Node) -> void:
	if container != null and is_instance_valid(_hover_anchor) \
			and container.is_ancestor_of(_hover_anchor):
		_clear_hover_preview()


# Pin the enlarged card beside its tile: prefer the right of the tile, flip to
# the left if that overflows, then clamp fully on-screen. `size` is the scene
# root's rect == the 1600×900 canvas (the stretch space tile rects live in).
func _place_hover_preview() -> void:
	if not is_instance_valid(_hover_preview) or not is_instance_valid(_hover_anchor):
		return
	var bounds: Vector2 = size
	var ar: Rect2 = _hover_anchor.get_global_rect()
	var px: float = ar.position.x + ar.size.x + 14.0
	if px + HOVER_PREVIEW_W > bounds.x - 8.0:
		px = ar.position.x - HOVER_PREVIEW_W - 14.0
	var py: float = ar.position.y + (ar.size.y - HOVER_PREVIEW_H) * 0.5
	px = clampf(px, 8.0, maxf(8.0, bounds.x - HOVER_PREVIEW_W - 8.0))
	py = clampf(py, 8.0, maxf(8.0, bounds.y - HOVER_PREVIEW_H - 8.0))
	_hover_preview.position = Vector2(px, py)


# ─────────────────────────────────────────────────────────────────────────────
#  THE ARSENAL STAGE (2026-07-16) — every net game opens with a run of
#  battle-relic picks and a run of battle-potion picks (1-of-3 each; PASS skips a
#  slate; an offered id never reappears in a later slate). HOW MANY of each is
#  the HOST'S LOBBY PICK (2026-09-14), carried on SkirmishState.arsenal_relics /
#  .arsenal_potions and identical for both players — so the stage is read from
#  there at _begin_arsenal, never from a constant. Shared here so all four mode scenes
#  present the identical stage — a self-contained modal overlay, so each mode's
#  own scaffold/flow runs untouched beneath it. Picks land in the LOCAL slot
#  (SkirmishState.local_slot().relics / .potions) and ride each mode's existing
#  "finished" deck handoff to the other peer. Pools: SkirmishState.NET_RELIC_POOL
#  / NET_POTION_POOL (net-safe by construction — see their comments).
#  Rolls use a dedicated RNG (match_seed salted by player index) so the stage
#  never perturbs a mode's own _rng stream.
# ─────────────────────────────────────────────────────────────────────────────
const ARSENAL_TILE_SIZE := Vector2(252, 325)


## A one-node face-down document shown while a rich Arsenal tile is assembled.
## It reserves the exact final footprint, so progressive construction never
## shifts the row. There is deliberately no spinner: these waits are a handful
## of frames, and the document itself communicates what is about to arrive.
class ArsenalSleeve extends Control:
	var accent := Color(0.74, 0.61, 0.34, 0.48)

	func configure(color: Color) -> void:
		accent = color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var outer := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var inner := outer.grow(-7.0)
		draw_rect(outer, Color(0.115, 0.092, 0.063, 0.98))
		draw_rect(outer, accent, false, 1.5)
		draw_rect(inner, Color(0.055, 0.044, 0.034, 0.72), false, 1.0)
		var center := size * 0.5
		var diamond := PackedVector2Array([
			center + Vector2(0, -19), center + Vector2(19, 0),
			center + Vector2(0, 19), center + Vector2(-19, 0)])
		draw_colored_polygon(diamond, Color(accent.r, accent.g, accent.b, 0.16))
		for i in 4:
			draw_line(diamond[i], diamond[(i + 1) % 4], accent, 1.5)
		var ink := Color(accent.r, accent.g, accent.b, 0.18)
		draw_rect(Rect2(30, size.y * 0.72, size.x - 60, 2), ink)
		draw_rect(Rect2(52, size.y * 0.78, size.x - 104, 2), ink)


## Reserve final geometry before expensive card construction. Every caller puts
## these slots into its Container immediately, then mounts rich cards invisibly
## over the sleeves. The Container therefore lays out its final row/grid once.
func _make_loading_card_slot(slot_size: Vector2 = THUMB_SIZE,
		accent: Color = GameTheme.GILT, group: CanvasItem = null) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = slot_size
	slot.size = slot_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sleeve := ArsenalSleeve.new()
	sleeve.configure(Color(accent.r, accent.g, accent.b, 0.48))
	Motion.arm_loading_writ(sleeve, group)
	slot.add_child(sleeve)
	sleeve.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {"slot": slot, "sleeve": sleeve}


## Rich controls finish layout and texture work behind the sleeve, but never
## become visible individually as their awaits complete.
func _stage_complete_hand_member(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	ctrl.visible = false


## Reveal a fully hydrated set as one hand. Every back closes in the same frame;
## every full face then opens from that shared edge in the same frame. This is
## the native two-node card turn (Motion.flip_out + flip_in), never a fade and
## never a load-order stagger. Parent Containers retain their final geometry.
func _reveal_complete_hand(controls: Array, covers: Array = []) -> void:
	var reduced := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	for raw_ctrl in controls:
		var ctrl: Control = raw_ctrl
		if ctrl != null and is_instance_valid(ctrl):
			ctrl.visible = true
	if reduced:
		_discard_reveal_covers(covers)
		return
	for raw_cover in covers:
		var cover: Control = raw_cover
		if cover != null and is_instance_valid(cover):
			Motion.flip_out(cover, 0.13)
	for raw_ctrl in controls:
		var ctrl: Control = raw_ctrl
		if ctrl != null and is_instance_valid(ctrl):
			Motion.flip_in(ctrl, HAND_BACK_CLOSE_SECONDS, HAND_FACE_OPEN_SECONDS)
	# Keep the hit targets locked through the complete two-half turn. Motion's
	# shell verbs scale each moving half with the animation-speed clock, while the
	# face delay is deliberately literal, so wait for whichever half settles last.
	var settle_seconds := maxf(Motion.time(HAND_BACK_CLOSE_SECONDS),
		HAND_BACK_CLOSE_SECONDS + Motion.time(HAND_FACE_OPEN_SECONDS)) + 0.01
	if get_tree() != null:
		await get_tree().create_timer(settle_seconds).timeout


func _discard_reveal_covers(covers: Array) -> void:
	for raw_cover in covers:
		var cover: Control = raw_cover
		if cover != null and is_instance_valid(cover):
			cover.visible = false
			cover.queue_free()

var _ars_layer: CanvasLayer = null
var _ars_scrim: Panel = null
var _ars_col: VBoxContainer = null
var _ars_header: Label = null
var _ars_row: HBoxContainer = null
var _ars_pips: Array = []           # one progress diamond per pick, relics then potions
var _ars_pass_btn: Button = null
var _ars_rng := RandomNumberGenerator.new()
## This match's arsenal size, frozen at _begin_arsenal from the host's pick.
var _ars_relic_rounds: int = 0
var _ars_potion_rounds: int = 0
var _ars_relics_left: int = 0
var _ars_potions_left: int = 0
## Ids already offered, PER CATEGORY — never re-dealt until the lap turns over
## (SkirmishState.deal_arsenal_slate). One list per pool, not one shared: the lap
## rule reads this SIZE against a pool size, so a shared list would count the
## other category's ids into that arithmetic.
var _ars_seen_relic: Array = []
var _ars_seen_potion: Array = []
var _ars_done: Callable = Callable()
var _ars_slate_generation := 0
var _ars_slate_ready := false


func arsenal_active() -> bool:
	return _ars_layer != null


func arsenal_slate_ready() -> bool:
	return _ars_layer != null and _ars_slate_ready


func _begin_arsenal(on_done: Callable = Callable()) -> void:
	_ars_done = on_done
	# The host's pick, already adopted by both machines at match start. Clamped
	# against the same ceilings the host's loadout authority validates with, so a
	# stage can never deal an item the peer would then be rejected for holding.
	_ars_relic_rounds = clampi(SkirmishState.arsenal_relics, 0,
		SkirmishState.arsenal_relic_max())
	_ars_potion_rounds = clampi(SkirmishState.arsenal_potions, 0,
		SkirmishState.arsenal_potion_max())
	_ars_relics_left = _ars_relic_rounds
	_ars_potions_left = _ars_potion_rounds
	_ars_seen_relic.clear()
	_ars_seen_potion.clear()
	_ars_rng.seed = int(NetMatch.match_seed) ^ (0xA25E * (NetMatch.local_player_index + 1))

	# A host who set BOTH to zero wants a bare-steel duel: build no stage at all,
	# rather than raise a scrim with nothing to ask. The callback is DEFERRED —
	# every caller fires this partway through its own _ready (the draft installs
	# its chrome on the line after), and a synchronous re-entry would run the
	# finish handler over a half-built screen.
	if _ars_relic_rounds <= 0 and _ars_potion_rounds <= 0:
		if _ars_done.is_valid():
			_ars_done.call_deferred()
		return

	_ars_layer = CanvasLayer.new()
	_ars_layer.layer = 40
	add_child(_ars_layer)

	_ars_scrim = Panel.new()
	var scrim := _ars_scrim
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.04, 0.03, 0.93)
	scrim.add_theme_stylebox_override("panel", st)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_ars_layer.add_child(scrim)

	var col := VBoxContainer.new()
	_ars_col = col
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 60
	col.offset_bottom = -60
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	_ars_layer.add_child(col)

	col.add_child(GameTheme.make_screen_title("RELICS & POTIONS", GILT_BRIGHT))
	_ars_header = GameTheme.make_label("", 20, IVORY)
	_ars_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_ars_header)

	# Progress rail: one diamond per pick — the relic run, a breath, the draughts.
	# Filled = taken, bright = the pick on the table, dim = still to come. The rail
	# is built from THIS match's counts, so it reads as the honest length of the
	# stage the host set rather than a fixed five.
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 10)
	col.add_child(pip_row)
	_ars_pips.clear()
	for i in range(_ars_relic_rounds + _ars_potion_rounds):
		# The breath only belongs BETWEEN two runs; with either category at zero a
		# leading/trailing gap would push the whole rail off its own centre line.
		if i == _ars_relic_rounds and _ars_relic_rounds > 0 and _ars_potion_rounds > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(16, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pip_row.add_child(gap)
		var pip: Control
		if GameTheme.tex_icon_diamond != null:
			var tr := TextureRect.new()
			tr.texture = GameTheme.tex_icon_diamond
			tr.custom_minimum_size = Vector2(15, 15)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pip = tr
		else:
			var p := Panel.new()
			p.custom_minimum_size = Vector2(12, 12)
			var ps := StyleBoxFlat.new()
			ps.bg_color = Color.WHITE
			ps.set_corner_radius_all(6)
			p.add_theme_stylebox_override("panel", ps)
			pip = p
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
		_ars_pips.append(pip)

	_ars_row = HBoxContainer.new()
	_ars_row.add_theme_constant_override("separation", 26)
	_ars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_ars_row)

	# The pass action sits under the slate — fighting lighter is a legitimate
	# choice, not an error, but it shouldn't masquerade as a fourth offering.
	_ars_pass_btn = GameTheme.make_back_button("SKIP THESE OPTIONS", Vector2(240, 36), 14, ASH)
	_ars_pass_btn.tooltip_text = "Skip these options and continue with fewer items."
	_ars_pass_btn.pressed.connect(_on_ars_pass)
	col.add_child(_ars_pass_btn)

	_ars_present_round()


func _ars_present_round() -> void:
	for c in _ars_row.get_children():
		_ars_row.remove_child(c)
		c.queue_free()
	_ars_refresh_pips()
	if _ars_relics_left > 0:
		_ars_header.text = "Choose a battle relic — %d of %d" % [
			_ars_relic_rounds - _ars_relics_left + 1, _ars_relic_rounds]
		_ars_fill_slate(SkirmishState.NET_RELIC_POOL, true)
	elif _ars_potions_left > 0:
		_ars_header.text = "Choose a battle potion — %d of %d" % [
			_ars_potion_rounds - _ars_potions_left + 1, _ars_potion_rounds]
		_ars_fill_slate(SkirmishState.NET_POTION_POOL, false)
	else:
		_end_arsenal()


func _ars_refresh_pips() -> void:
	var done := (_ars_relic_rounds - _ars_relics_left) \
		+ (_ars_potion_rounds - _ars_potions_left)
	for i in _ars_pips.size():
		var pip: Control = _ars_pips[i]
		if not is_instance_valid(pip):
			continue
		var base := GILT_BRIGHT if i < _ars_relic_rounds \
			else Color(0.95, 0.62, 0.35)
		if i < done:
			pip.modulate = base
		elif i == done:
			pip.modulate = IVORY
		else:
			pip.modulate = Color(base.r, base.g, base.b, 0.25)


## One offering = one whole-tile doc-card (the Shop shelf recipe: dark
## PARCHMENT, chamfered gilt rule, chip → name → effect → footer) — the whole
## tile is the hit target.
func _ars_fill_slate(pool: Array, is_relic: bool) -> void:
	_ars_slate_generation += 1
	_ars_slate_ready = false
	if _ars_pass_btn != null:
		_ars_pass_btn.disabled = true
	var generation := _ars_slate_generation
	# The shared dealer, lap rule and all — the host rebuilds these very tables
	# from the same function to validate the picks, so the stage must not deal by
	# any other rule. It also appends to the block list, so nothing below does.
	var offered: Array[String] = SkirmishState.deal_arsenal_slate(pool, _ars_rng,
		_ars_seen_relic if is_relic else _ars_seen_potion)
	if offered.is_empty():
		# Pool exhausted (tiny custom pools only) — auto-pass the whole category.
		if is_relic:
			_ars_relics_left = 0
		else:
			_ars_potions_left = 0
		_ars_present_round()
		return
	# Reserve all three destinations immediately. The sleeves match the measured
	# 252x325 final slate, so each rich tile can arrive without reflowing the row.
	var slots: Array[Control] = []
	var sleeves: Array[Control] = []
	var sleeve_accent := GameTheme.GILT if is_relic else Color(0.95, 0.62, 0.35)
	for id in offered:
		var loading := _make_loading_card_slot(ARSENAL_TILE_SIZE, sleeve_accent, _ars_row)
		var slot: Control = loading["slot"]
		_ars_row.add_child(slot)
		slots.append(slot)
		sleeves.append(loading["sleeve"])
	# Present stable sleeves first. Rich tiles hydrate behind them and the complete
	# hand is revealed atomically after every tile is ready.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	var idx := 0
	var tiles: Array[Button] = []
	for id in offered:
		if generation != _ars_slate_generation or _ars_layer == null \
				or idx >= slots.size() or not is_instance_valid(slots[idx]):
			return
		var slot: Control = slots[idx]
		var entry: Dictionary = RelicDB.get_relic(id) if is_relic else PotionDB.get_potion(id)
		var skel := GameTheme.make_tile_skeleton(Vector2(252, 0), 7)
		var btn: Button = skel.button
		btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_stylebox_override("normal",
			GameTheme.make_btn_style(GameTheme.PARCHMENT, GameTheme.GILT, 10))
		btn.add_theme_stylebox_override("hover",
			GameTheme.make_btn_style(GameTheme.PARCHMENT.lightened(0.06),
				GILT_BRIGHT, 10))
		btn.add_theme_stylebox_override("pressed",
			GameTheme.make_btn_style(GameTheme.PARCHMENT.darkened(0.14),
				GameTheme.GILT, 10))
		var tcol: VBoxContainer = skel.col

		var chip: Control = GameTheme.make_relic_chip(id, 84) if is_relic \
			else GameTheme.make_potion_chip(id, 84)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_ars_mute_mouse(chip)
		tcol.add_child(chip)

		var name_lbl := GameTheme.make_label(String(entry.get("name", id)), 19, GILT_BRIGHT)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tcol.add_child(name_lbl)

		var desc_lbl := GameTheme.make_label(String(entry.get("desc", "")), 15, IVORY)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(0, 64)
		tcol.add_child(desc_lbl)

		# ALREADY HELD. Reachable only past the first lap (see
		# SkirmishState.deal_arsenal_slate): once a pool has been dealt through,
		# a later table can re-offer something you already took. Taking it twice
		# would be a duplicate, which validate_loadout_event refuses outright —
		# so the tile SAYS so and is not takeable, rather than spending your pick
		# on nothing. The tile still appears in the dealt table, which is what
		# keeps the host's reconstruction of these offers valid.
		var held: bool = _ars_already_held(id, is_relic)
		var foot := GameTheme.make_label(
			"— ALREADY YOURS —" if held else "— CHOOSE —", 16,
			ASH if held else GameTheme.GILT)
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tcol.add_child(foot)

		GameTheme.fit_tile_height(btn, tcol)
		btn.custom_minimum_size = ARSENAL_TILE_SIZE
		btn.disabled = true
		btn.set_meta("ars_id", id)
		btn.set_meta("ars_chip", chip)
		btn.set_meta("ars_held", held)
		if held:
			btn.modulate = Color(1, 1, 1, 0.45)
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		else:
			btn.pressed.connect(_on_ars_pick.bind(id, is_relic))
		slot.set_meta("ars_id", id)
		slot.set_meta("ars_chip", chip)
		slot.set_meta("ars_button", btn)
		slot.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_stage_complete_hand_member(btn)
		tiles.append(btn)
		_flatten_net_chart_styles(btn)
		idx += 1
		if idx < offered.size():
			if DisplayServer.get_name() == "headless":
				await get_tree().process_frame
			else:
				await RenderingServer.frame_post_draw

	# The slot footprint was final before the first await. Turn all three backs
	# and faces in one render beat, then unlock the choice controls together.
	if generation != _ars_slate_generation or _ars_layer == null:
		return
	_flatten_net_chart_styles(_ars_row)
	await _reveal_complete_hand(tiles, sleeves)
	if generation != _ars_slate_generation or _ars_layer == null:
		return
	for t in tiles:
		# An ALREADY YOURS tile stays disabled — it was never wired to a handler,
		# and a live-looking button that does nothing is the silent-refusal class.
		if t != null and is_instance_valid(t) and not bool(t.get_meta("ars_held", false)):
			t.disabled = false
	_ars_slate_ready = true
	if _ars_pass_btn != null:
		_ars_pass_btn.disabled = false


## Does the local player already hold this offering? Only ever true past the
## first lap of a pool (SkirmishState.deal_arsenal_slate).
func _ars_already_held(id: String, is_relic: bool) -> bool:
	var slot := SkirmishState.local_slot()
	if slot == null:
		return false
	return slot.relics.has(id) if is_relic else slot.potions.has(id)


## The chips ship with their own rich-hover tooltips — inside a whole-tile
## button that second tooltip fights the tile, so mute the chip subtree.
func _ars_mute_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ars_mute_mouse(c)


func _on_ars_pass() -> void:
	if _ars_layer == null or not _ars_slate_ready:
		return
	_on_ars_pick("", _ars_relics_left > 0)


func _on_ars_pick(id: String, is_relic: bool) -> void:
	if _ars_layer == null or not _ars_slate_ready:
		return
	# Lock the whole slate on the first accepted press. The final pick can remain
	# on screen for its chip flight, so relying on the next slate build alone left
	# a double-click window that could spend the same choice twice.
	_ars_slate_ready = false
	if _ars_pass_btn != null:
		_ars_pass_btn.disabled = true
	for child in _ars_row.get_children():
		var tile: Button = child.get_meta("ars_button", null) as Button \
				if child is Control else null
		if tile != null and is_instance_valid(tile):
			tile.disabled = true
	if is_relic:
		if _ars_relics_left <= 0:
			return
		_ars_relics_left -= 1
	else:
		if _ars_potions_left <= 0:
			return
		_ars_potions_left -= 1
	var flew := false
	if id != "":
		var slot := SkirmishState.local_slot()
		# Backstop against a DUPLICATE. The held tile is already unclickable, but
		# this path is also reached from _on_ars_pass and from probes/shot tools
		# that call it directly, and a repeated id is refused wholesale by
		# validate_loadout_event — losing the player their entire loadout over a
		# cosmetic slip. The round is still spent: the pick was made.
		if slot != null and not _ars_already_held(id, is_relic):
			if is_relic:
				slot.relics.append(id)
			else:
				slot.potions.append(id)
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
		flew = _ars_fly_pick(id)
	# The final take deserves its landing beat before the overlay folds — hold
	# the close for the flight. Headless / Reduce Motion keep the instant path.
	if flew and _ars_relics_left <= 0 and _ars_potions_left <= 0:
		_ars_close_after_flight()
	else:
		_ars_present_round()


## The take's payoff: the picked chip detaches and dives into the pip it just
## filled. Reparented to the overlay layer FIRST so the slate rebuild can't
## free it mid-flight. Returns whether the flight is actually playing.
func _ars_fly_pick(id: String) -> bool:
	if DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		return false
	var chip: Control = null
	for c in _ars_row.get_children():
		if c is Control and String(c.get_meta("ars_id", "")) == id \
				and not c.is_queued_for_deletion():
			chip = c.get_meta("ars_chip", null)
			break
	var done := (_ars_relic_rounds - _ars_relics_left) \
		+ (_ars_potion_rounds - _ars_potions_left)
	var pip: Control = _ars_pips[done - 1] \
		if done >= 1 and done <= _ars_pips.size() else null
	if chip == null or not is_instance_valid(chip) \
			or pip == null or not is_instance_valid(pip):
		return false
	var gp: Vector2 = chip.global_position
	chip.get_parent().remove_child(chip)
	_ars_layer.add_child(chip)
	chip.global_position = gp
	_ars_flight(chip, pip)
	return true


func _ars_flight(chip: Control, pip: Control) -> void:
	await GameTheme.pocket_away(chip, pip.global_position + pip.size * 0.5, 0.30)
	if is_instance_valid(chip):
		chip.queue_free()
	if is_instance_valid(pip):
		GameTheme.punch(pip, 1.6)


func _ars_close_after_flight() -> void:
	await get_tree().create_timer(0.55).timeout
	if _ars_layer != null:
		_ars_present_round()


func _end_arsenal() -> void:
	_ars_slate_generation += 1
	_ars_slate_ready = false
	var closing_layer := _ars_layer
	var closing_scrim := _ars_scrim
	var closing_col := _ars_col
	_ars_layer = null
	_ars_scrim = null
	_ars_col = null
	if _ars_done.is_valid():
		_ars_done.call()
	if closing_layer == null or not is_instance_valid(closing_layer):
		return
	if DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		closing_layer.queue_free()
		return
	# The picked chip already flies into the progress rail. Complete that motion
	# grammar by drying the document copy first, then lifting the dark scrim to
	# reveal the fully laid-out mode underneath it.
	if closing_col != null and is_instance_valid(closing_col):
		GameTheme.fade_exit(closing_col, 0.16)
	if closing_scrim != null and is_instance_valid(closing_scrim):
		var tw := closing_scrim.create_tween()
		tw.tween_property(closing_scrim, "modulate:a", 0.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.finished.connect(closing_layer.queue_free)
	else:
		closing_layer.queue_free()
