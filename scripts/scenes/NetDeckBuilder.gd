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

# Hover-to-enlarge preview: pool/deck thumbnails are small, so hovering one pops
# the full card beside it (the "window showing the card you hover"). Native card
# size; named _hover_* so it doesn't collide with NetDraft's own bespoke preview.
const HOVER_CARD_SCENE := preload("res://scenes/card_2d.tscn")
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


# Builds one clickable pool tile from a card id and registers it in _pool_rows.
# Identical across the pool-based modes; clicking routes to the subclass _on_add.
func _build_pool_thumb(id: String) -> Control:
	var d := SkirmishState.skirmish_card_data(id)
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
		NetMatch.leave()
		get_tree().change_scene_to_file(MENU_SCENE)
		get_viewport().set_input_as_handled()


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
#  THE ARSENAL STAGE (2026-07-16) — every net game opens with 3 battle-relic
#  picks and 2 battle-potion picks (1-of-3 each; PASS skips a slate; an offered
#  id never reappears in a later slate). Shared here so all four mode scenes
#  present the identical stage — a self-contained modal overlay, so each mode's
#  own scaffold/flow runs untouched beneath it. Picks land in the LOCAL slot
#  (SkirmishState.local_slot().relics / .potions) and ride each mode's existing
#  "finished" deck handoff to the other peer. Pools: SkirmishState.NET_RELIC_POOL
#  / NET_POTION_POOL (net-safe by construction — see their comments).
#  Rolls use a dedicated RNG (match_seed salted by player index) so the stage
#  never perturbs a mode's own _rng stream.
# ─────────────────────────────────────────────────────────────────────────────
const ARSENAL_RELIC_PICKS := 3
const ARSENAL_POTION_PICKS := 2

var _ars_layer: CanvasLayer = null
var _ars_header: Label = null
var _ars_row: HBoxContainer = null
var _ars_pips: Array = []           # 5 progress diamonds — 3 relic + 2 potion
var _ars_pass_btn: Button = null
var _ars_rng := RandomNumberGenerator.new()
var _ars_relics_left: int = 0
var _ars_potions_left: int = 0
var _ars_seen: Array = []           # every id ever offered — never re-dealt
var _ars_done: Callable = Callable()


func arsenal_active() -> bool:
	return _ars_layer != null


func _begin_arsenal(on_done: Callable = Callable()) -> void:
	_ars_done = on_done
	_ars_relics_left = ARSENAL_RELIC_PICKS
	_ars_potions_left = ARSENAL_POTION_PICKS
	_ars_seen.clear()
	_ars_rng.seed = int(NetMatch.match_seed) ^ (0xA25E * (NetMatch.local_player_index + 1))

	_ars_layer = CanvasLayer.new()
	_ars_layer.layer = 40
	add_child(_ars_layer)

	var scrim := Panel.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.04, 0.03, 0.93)
	scrim.add_theme_stylebox_override("panel", st)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_ars_layer.add_child(scrim)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 60
	col.offset_bottom = -60
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	_ars_layer.add_child(col)

	col.add_child(GameTheme.make_screen_title("ARM YOUR WARBAND", GILT_BRIGHT))
	_ars_header = GameTheme.make_label("", 20, IVORY)
	_ars_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_ars_header)

	# Progress rail: five diamonds — three relic picks, a breath, two draughts.
	# Filled = taken, bright = the pick on the table, dim = still to come.
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 10)
	col.add_child(pip_row)
	_ars_pips.clear()
	for i in range(ARSENAL_RELIC_PICKS + ARSENAL_POTION_PICKS):
		if i == ARSENAL_RELIC_PICKS:
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
		c.queue_free()
	_ars_refresh_pips()
	if _ars_relics_left > 0:
		_ars_header.text = "Choose a battle relic — %d of %d" % [
			ARSENAL_RELIC_PICKS - _ars_relics_left + 1, ARSENAL_RELIC_PICKS]
		_ars_fill_slate(SkirmishState.NET_RELIC_POOL, true)
	elif _ars_potions_left > 0:
		_ars_header.text = "Choose a battle potion — %d of %d" % [
			ARSENAL_POTION_PICKS - _ars_potions_left + 1, ARSENAL_POTION_PICKS]
		_ars_fill_slate(SkirmishState.NET_POTION_POOL, false)
	else:
		_end_arsenal()


func _ars_refresh_pips() -> void:
	var done := (ARSENAL_RELIC_PICKS - _ars_relics_left) \
		+ (ARSENAL_POTION_PICKS - _ars_potions_left)
	for i in _ars_pips.size():
		var pip: Control = _ars_pips[i]
		if not is_instance_valid(pip):
			continue
		var base := GILT_BRIGHT if i < ARSENAL_RELIC_PICKS \
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
	var offered: Array[String] = SkirmishState.deal_unique_cards(pool, 3, _ars_rng, _ars_seen)
	if offered.is_empty():
		# Pool exhausted (tiny custom pools only) — auto-pass the whole category.
		if is_relic:
			_ars_relics_left = 0
		else:
			_ars_potions_left = 0
		_ars_present_round()
		return
	var idx := 0
	var tiles: Array[Button] = []
	for id in offered:
		_ars_seen.append(id)
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

		var foot := GameTheme.make_label("— TAKE IT —", 16, GameTheme.GILT)
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tcol.add_child(foot)

		GameTheme.fit_tile_height(btn, tcol)
		btn.set_meta("ars_id", id)
		btn.set_meta("ars_chip", chip)
		btn.pressed.connect(_on_ars_pick.bind(id, is_relic))
		_ars_row.add_child(btn)
		tiles.append(btn)
		GameTheme.deal_in(btn, 0.05 + float(idx) * 0.08)
		idx += 1

	# Three offerings of different text lengths left a ragged row of mismatched
	# tiles. fit_tile_height is synchronous, so the measured heights are already
	# final here — level them to the tallest so the slate reads as a matched set.
	var tallest := 0.0
	for t in tiles:
		tallest = maxf(tallest, t.custom_minimum_size.y)
	for t in tiles:
		t.custom_minimum_size.y = tallest


## The chips ship with their own rich-hover tooltips — inside a whole-tile
## button that second tooltip fights the tile, so mute the chip subtree.
func _ars_mute_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ars_mute_mouse(c)


func _on_ars_pass() -> void:
	if _ars_layer == null:
		return
	_on_ars_pick("", _ars_relics_left > 0)


func _on_ars_pick(id: String, is_relic: bool) -> void:
	if _ars_layer == null:
		return
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
		if slot != null:
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
	var done := (ARSENAL_RELIC_PICKS - _ars_relics_left) \
		+ (ARSENAL_POTION_PICKS - _ars_potions_left)
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
	if _ars_layer != null:
		_ars_layer.queue_free()
		_ars_layer = null
	if _ars_done.is_valid():
		_ars_done.call()
