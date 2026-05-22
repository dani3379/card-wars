extends Control
## MainMenu.gd — title screen. Start a new run, see stats, quit.
##
## Visual goals: every label uses GameTheme's display font (Cinzel-style serif),
## every button has a styled StyleBox with rounded corners and gold border.
## No default-Godot button rectangles, no missing font fallbacks.

const MAP_SCENE = "res://scenes/map.tscn"
const COMBAT_SCENE = "res://scenes/combat.tscn"
const SHOP_SCENE = "res://scenes/shop.tscn"
const REST_SCENE = "res://scenes/rest.tscn"
const EVENT_SCENE = "res://scenes/event.tscn"
const COLLECTION_SCENE = "res://scenes/collection.tscn"
const CREDITS_SCENE = "res://scenes/credits.tscn"

const GILT := Color(0.83, 0.74, 0.54, 1.0)
const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)

# Currently selected ascension tier. -1 means "not initialized yet" — gets
# clamped to MetaState.unlocked_ascension on the first menu build. Survives
# across menu rebuilds (e.g. relic-select → back) so the player doesn't have
# to re-pick their tier every time.
var _selected_ascension: int = -1

# ── Start-screen motion (premium drift) ──────────────────────────────────────
# The background slowly breathes (Ken Burns) and drifts opposite the cursor for a
# parallax depth feel; the title shimmers; warm embers rise up the screen. All
# Tween/CPUParticles2D — no shaders (gl_compatibility-safe).
var _bg_node: TextureRect = null
var _bg_base_scale: float = 1.15           # oversize so drift never reveals edges
var _parallax_mouse: Vector2 = Vector2.ZERO  # smoothed cursor offset, each axis [-1, 1]
var _kb_time: float = 0.0                   # Ken Burns clock
var _title_shimmer_tween: Tween = null


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	AudioBank.play_music("main_menu")
	_rebuild_menu()
	_animate_intro()
	_setup_bg_parallax()
	_add_menu_embers()


func _rebuild_menu() -> void:
	# Wipe the placeholder children from the .tscn so we can build the menu
	# entirely from code with consistent fonts/styles. The Background atmosphere
	# is preserved (it was added by add_atmosphere()).
	for child in get_children():
		var n: String = child.name
		if n == "Background" or n == "Atmosphere":
			continue
		child.queue_free()

	var vp := get_viewport_rect().size
	var col := VBoxContainer.new()
	col.name = "Menu"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	# Left-aligned column (Hades / StS-2 layout): a fixed 610×640 rect pinned to
	# the left edge and vertically centered. The character splash sits center-
	# right, so keeping the menu on the left leaves the hero unobstructed.
	# anchor_left/right = 0 makes the offsets absolute from the left edge.
	col.anchor_left = 0.0
	col.anchor_right = 0.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 110
	col.offset_right = 720
	col.offset_top = -320
	col.offset_bottom = 320
	add_child(col)

	# ── Title ──
	var title := _make_display_label("BURNING MEADOW", 52, GILT_BRIGHT)
	title.name = "TitleLabel"
	title.add_theme_color_override("font_outline_color", Color(0.55, 0.18, 0.05, 0.90))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)

	# ── Subtitle ──
	var sub := _make_display_label("a lane combat roguelike deckbuilder", 17, ASH)
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(sub)

	# ── Ornament: gilt line with central rosette glyph (a diamond, NOT a triangle).
	# This is the "card-game opening flourish" — it sells the screen as a deck-
	# builder rather than a generic Godot template. Left-flush to match the column.
	col.add_child(_make_ornament_row(260.0, true))

	# Spacer pushes the buttons down so the title has breathing room.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 22)
	col.add_child(spacer)

	# Default the selected ascension to the highest unlocked tier so returning
	# players climb naturally; selector below lets them drop back if they want.
	if _selected_ascension < 0 or _selected_ascension > MetaState.unlocked_ascension:
		_selected_ascension = MetaState.unlocked_ascension

	# ── Primary actions ──
	# Familiar 3-button layout: CONTINUE jumps into the most recent save,
	# NEW RUN starts fresh, LOAD GAME opens the multi-slot picker. CONTINUE
	# and LOAD only appear when at least one slot has a save.
	var has_any_save := _any_save_exists()

	# All main-menu buttons share font_size=22 and height=50 — visual
	# hierarchy comes from per-button COLOR, not size. The previous mix of
	# 17/19/20/22/24 sizes felt random; uniform sizing reads like a single
	# menu group (matches Ratropolis / Slay the Spire conventions).
	const MENU_FONT := 22
	const MENU_H := 50
	if has_any_save:
		var btn_continue := _make_menu_button("CONTINUE RUN",
			Color(0.32, 0.26, 0.14), MENU_FONT, MENU_H)
		btn_continue.pressed.connect(_on_continue_recent)
		col.add_child(btn_continue)

	var begin_label: String = "NEW RUN"
	if MetaState.unlocked_ascension > 0:
		begin_label = "NEW RUN — ASC %d" % _selected_ascension
	var btn_start := _make_menu_button(begin_label,
		Color(0.18, 0.36, 0.18), MENU_FONT, MENU_H)
	btn_start.pressed.connect(_on_new_run)
	col.add_child(btn_start)

	if has_any_save:
		var btn_load := _make_menu_button("LOAD GAME",
			Color(0.20, 0.28, 0.42), MENU_FONT, MENU_H)
		btn_load.pressed.connect(_on_load_game)
		col.add_child(btn_load)

	# Ascension selector — only shown once the player has unlocked at least
	# tier 1. Lets them dial difficulty down for lighter runs.
	if MetaState.unlocked_ascension > 0:
		var asc_row := HBoxContainer.new()
		asc_row.alignment = BoxContainer.ALIGNMENT_CENTER
		asc_row.add_theme_constant_override("separation", 14)
		var minus := _make_menu_button("−", Color(0.20, 0.16, 0.14), 18, 36)
		minus.custom_minimum_size = Vector2(48, 36)
		minus.pressed.connect(_change_ascension.bind(-1))
		asc_row.add_child(minus)
		var asc_label := _make_display_label("Ascension %d / %d" % [
			_selected_ascension, MetaState.unlocked_ascension], 16, IVORY)
		asc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		asc_label.custom_minimum_size = Vector2(220, 36)
		asc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		asc_row.add_child(asc_label)
		var plus := _make_menu_button("+", Color(0.20, 0.16, 0.14), 18, 36)
		plus.custom_minimum_size = Vector2(48, 36)
		plus.pressed.connect(_change_ascension.bind(1))
		asc_row.add_child(plus)
		col.add_child(asc_row)

	var btn_gallery := _make_menu_button("CARD GALLERY",
		Color(0.16, 0.20, 0.32), MENU_FONT, MENU_H)
	btn_gallery.pressed.connect(func():
		GameTheme.fade_out_then_change_scene(self, COLLECTION_SCENE))
	col.add_child(btn_gallery)

	var btn_settings := _make_menu_button("SETTINGS",
		Color(0.22, 0.20, 0.18), MENU_FONT, MENU_H)
	btn_settings.pressed.connect(_on_open_settings)
	col.add_child(btn_settings)

	var btn_quit := _make_menu_button("QUIT",
		Color(0.26, 0.16, 0.14), MENU_FONT, MENU_H)
	btn_quit.pressed.connect(_on_quit)
	col.add_child(btn_quit)

	# Bottom decorative line + run stats.
	col.add_child(_make_ornament_row(200.0, true))
	var stats := _make_display_label(_stats_text(), 13, ASH)
	stats.name = "StatsLabel"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(stats)

	# Small "Credits" text link below the stats — kept low-key so it doesn't
	# compete with the primary action buttons, but always accessible.
	var credits_btn := Button.new()
	credits_btn.text = "credits"
	credits_btn.flat = true
	credits_btn.focus_mode = Control.FOCUS_NONE
	credits_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	credits_btn.custom_minimum_size = Vector2(0, 24)
	credits_btn.add_theme_font_size_override("font_size", 12)
	credits_btn.add_theme_color_override("font_color", ASH)
	credits_btn.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	if GameTheme.font_body:
		credits_btn.add_theme_font_override("font", GameTheme.font_body)
	credits_btn.pressed.connect(func():
		GameTheme.fade_out_then_change_scene(self, CREDITS_SCENE, 0.30))
	col.add_child(credits_btn)

	# Re-arm the title's idle shimmer on every rebuild (the title node is recreated
	# here; ascension changes rebuild without replaying the intro).
	_start_title_shimmer()


# ---------------------------------------------------------------------------
# FACTORIES
# ---------------------------------------------------------------------------

func _make_display_label(text: String, size: int, color: Color) -> Label:
	# Display labels — used for everything in the menu so the typography is
	# unified. Uses font_display (Cinzel SemiBold) so titles look chiseled.
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_menu_button(text: String, _bg: Color, font_size: int, height: int) -> Button:
	# Frameless text button (Slay the Spire / Hades style): no box at all — the
	# text *is* the button. On hover the label brightens to gilt, a flame ignites
	# on each side, and the whole label nudges right. The `_bg` param is retained
	# for call-site compatibility but no longer drives a fill. A dark outline
	# keeps the text legible over the busy fire background now that there's no
	# panel behind it.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, height)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Transparent in every state — kill the default Godot button rectangle.
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)

	# Content lives in a left-packed HBox: a flame "cursor" on the left, then the
	# label. The flame reserves a fixed slot even while invisible, so igniting it
	# never shifts the label — and on hover the whole row slides right a touch.
	var inner := HBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN
	inner.add_theme_constant_override("separation", 12)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	# Flame cursor only on the full-size action buttons — the small steppers
	# (−/+) and BACK links read better as plain text.
	var flames: Array[TextureRect] = []
	if height >= 44:
		var flame_l := _make_flame_accent()
		inner.add_child(flame_l)
		flames.append(flame_l)

	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", IVORY)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 5)
	inner.add_child(lbl)

	btn.mouse_entered.connect(_on_menu_btn_hover.bind(inner, lbl, flames, true))
	btn.mouse_exited.connect(_on_menu_btn_hover.bind(inner, lbl, flames, false))
	return btn


func _make_flame_accent() -> TextureRect:
	# Small flame that fades in to the left of a hovered menu item. Reserves a
	# fixed footprint at all times so toggling its visibility never reflows the
	# label.
	var f := TextureRect.new()
	f.texture = load("res://assets/icons/fire.png") as Texture2D
	f.custom_minimum_size = Vector2(28, 28)
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.modulate = Color(1, 1, 1, 0)  # hidden until hover
	return f


func _on_menu_btn_hover(inner: Control, lbl: Label, flames: Array,
		hovering: bool) -> void:
	lbl.add_theme_color_override("font_color", GILT_BRIGHT if hovering else IVORY)
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_a := 1.0 if hovering else 0.0
	for flame in flames:
		tw.tween_property(flame, "modulate:a", target_a, 0.18)
	tw.tween_property(inner, "position:x", 12.0 if hovering else 0.0, 0.18)


func _make_relic_tile(rid: String) -> Button:
	# A clickable "relic card": gold-trimmed panel with the relic's icon on the
	# left and its name + description stacked on the right. Mirrors the save-slot
	# pattern (empty Button + child container with mouse_filter IGNORE) so the
	# whole tile is one hit target. The icon is loaded by convention from
	# RelicDB.get_relic_icon and tinted gilt; if it isn't imported yet the tile
	# simply renders without the icon column rather than breaking.
	var r := RelicDB.get_relic(rid)
	var bg := Color(0.18, 0.20, 0.32)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 88)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	var normal := _make_button_stylebox(bg, GILT, 8)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.18)
	hover.border_color = GILT_BRIGHT
	hover.shadow_size = 10
	hover.shadow_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.35)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.18)
	pressed.border_color = bg.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon := RelicDB.get_relic_icon(rid)
	if icon != null:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = Vector2(64, 64)
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.modulate = GILT
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 2)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	var name_lbl := _make_display_label(r.get("name", rid), 20, GILT_BRIGHT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(name_lbl)
	var desc_lbl := _make_display_label(r.get("desc", ""), 13, IVORY)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(380, 0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(desc_lbl)

	btn.pressed.connect(_begin_run_with.bind(rid))
	return btn


func _make_button_stylebox(bg: Color, border: Color, corner: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_slot_row(slot: int, overwrite_mode: bool = false) -> Control:
	# Renders one save slot. In normal mode, filled slots continue and empty
	# slots start a new run. In overwrite mode (entered when every slot is
	# full and the player picked NEW RUN), every slot starts a new run, with
	# filled slots showing their summary as a "you're about to lose this run"
	# preview. Filled slots in normal mode also get a small "✕" delete button.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var summary := RunState.get_slot_summary(slot)
	var has_save: bool = summary.get("has_save", false)
	# Overwrite mode tints filled slots red-ish to telegraph the destructive
	# action; normal mode uses the warm gold "continue" treatment.
	var bg: Color
	if overwrite_mode and has_save:
		bg = Color(0.36, 0.18, 0.14)
	elif has_save:
		bg = Color(0.32, 0.26, 0.14)
	else:
		bg = Color(0.16, 0.22, 0.16)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	# Reuse the same stylebox treatment as the main menu buttons so the slot
	# rows feel like part of the same family.
	var normal := _make_button_stylebox(bg, GILT, 8)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.18)
	hover.border_color = GILT_BRIGHT
	hover.shadow_size = 10
	hover.shadow_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.35)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.18)
	pressed.border_color = bg.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)
	# The button's own text stays empty — labels are stacked inside a child
	# VBox so we get a two-line "title / subtitle" treatment without fighting
	# Godot's single-line Button text rendering.
	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)
	var title_text: String
	var sub_text: String
	if has_save:
		if overwrite_mode:
			title_text = "SLOT %d  ·  Overwrite" % (slot + 1)
		else:
			title_text = "SLOT %d  ·  Continue Run" % (slot + 1)
		var act_floor := "Act %d · Floor %d" % [int(summary.act), int(summary.floor)]
		var hp_gold := "HP %d/%d · %dg" % [int(summary.hp), int(summary.max_hp), int(summary.gold)]
		if int(summary.ascension) > 0:
			hp_gold += " · Asc %d" % int(summary.ascension)
		sub_text = "%s   ·   %s" % [act_floor, hp_gold]
	else:
		title_text = "SLOT %d  ·  Begin New Run" % (slot + 1)
		if MetaState.unlocked_ascension > 0:
			sub_text = "Empty   ·   Ascension %d" % _selected_ascension
		else:
			sub_text = "Empty"
	var title_lbl := _make_display_label(title_text, 20, IVORY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(title_lbl)
	var sub_lbl := _make_display_label(sub_text, 12, ASH if not has_save else Color(0.85, 0.78, 0.58))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(sub_lbl)

	if overwrite_mode or not has_save:
		btn.pressed.connect(_begin_new_in_slot.bind(slot))
	else:
		btn.pressed.connect(_load_slot_into_game.bind(slot))
	row.add_child(btn)

	# Delete button — only meaningful on filled slots, and only in normal load
	# mode (in overwrite mode the whole button is already destructive, so a
	# second delete affordance would just be confusing).
	if has_save and not overwrite_mode:
		var del := Button.new()
		# Plain Latin X — the U+2715 multiplication-x glyph isn't in every
		# display font, so it sometimes rendered as a tofu rectangle here.
		del.text = "X"
		del.custom_minimum_size = Vector2(44, 58)
		del.focus_mode = Control.FOCUS_NONE
		if GameTheme.font_display:
			del.add_theme_font_override("font", GameTheme.font_display)
		del.add_theme_font_size_override("font_size", 18)
		del.add_theme_color_override("font_color", Color(0.92, 0.65, 0.55))
		del.add_theme_color_override("font_hover_color", Color(1.0, 0.40, 0.30))
		var del_bg := Color(0.20, 0.10, 0.09)
		var del_normal := _make_button_stylebox(del_bg, Color(0.55, 0.25, 0.20), 8)
		del.add_theme_stylebox_override("normal", del_normal)
		var del_hover := del_normal.duplicate() as StyleBoxFlat
		del_hover.bg_color = del_bg.lightened(0.20)
		del_hover.border_color = Color(0.95, 0.45, 0.30)
		del.add_theme_stylebox_override("hover", del_hover)
		del.pressed.connect(_on_slot_delete.bind(slot))
		row.add_child(del)
	return row


func _make_ornament_row(width: float, left_aligned: bool = false) -> Control:
	# A horizontal gold line broken by a central diamond — the "section break"
	# flourish you see in fantasy books. Previously used the U+25C6 unicode
	# character in a font that doesn't ship that glyph, so it rendered as a
	# tofu rectangle next to the divider lines (which themselves looked boxy
	# because they vertical-stretched to the row height). Now uses an actual
	# diamond.png texture and forces the lines to a fixed thin height.
	# left_aligned: a short lead-in stub + diamond + long trailing line, flushed
	# to the column's left edge (for the left-column menu layout).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if left_aligned:
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(20.0 if left_aligned else width * 0.45, 2)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = Color(GILT.r, GILT.g, GILT.b, 0.55)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	var diamond_tex := load("res://assets/icons/diamond.png") as Texture2D
	if diamond_tex != null:
		var diamond := TextureRect.new()
		diamond.texture = diamond_tex
		diamond.custom_minimum_size = Vector2(14, 14)
		diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		diamond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		diamond.modulate = GILT_BRIGHT
		diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(diamond)
	else:
		# Fallback if the texture is missing: a tiny gold square rotated 45°
		# still reads as a diamond and renders without any font dependency.
		var diamond := ColorRect.new()
		diamond.custom_minimum_size = Vector2(10, 10)
		diamond.rotation = PI / 4
		diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		diamond.color = GILT_BRIGHT
		diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(diamond)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(width * 0.45, 2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.color = Color(GILT.r, GILT.g, GILT.b, 0.55)
	row.add_child(right)
	return row


func _stats_text() -> String:
	return "Runs %d  •  Victories %d  •  Defeats %d" % [
		MetaState.total_runs, MetaState.total_victories, MetaState.total_defeats,
	]


# ---------------------------------------------------------------------------
# INTERACTIONS
# ---------------------------------------------------------------------------

func _any_save_exists() -> bool:
	for i in range(RunState.SAVE_SLOTS):
		if RunState.has_save(i):
			return true
	return false


# Returns the slot index of the most recently-saved run (by saved_at), or -1
# if no slot is filled. CONTINUE RUN uses this so the player's last session
# is always one click away regardless of which slot it lives in.
func _most_recent_slot() -> int:
	var best := -1
	var best_time := -1
	for i in range(RunState.SAVE_SLOTS):
		var s := RunState.get_slot_summary(i)
		if not s.get("has_save", false):
			continue
		var t: int = int(s.get("saved_at", 0))
		if t > best_time:
			best_time = t
			best = i
	return best


func _first_empty_slot() -> int:
	for i in range(RunState.SAVE_SLOTS):
		if not RunState.has_save(i):
			return i
	return -1


func _on_continue_recent() -> void:
	var slot := _most_recent_slot()
	if slot < 0:
		# Shouldn't happen — button only shows when at least one save exists —
		# but fall back gracefully if state changed underneath us.
		_rebuild_menu()
		return
	_load_slot_into_game(slot)


func _on_new_run() -> void:
	var empty := _first_empty_slot()
	if empty >= 0:
		_begin_new_in_slot(empty)
		return
	# Every slot is full — open the load screen in "pick one to overwrite"
	# mode so the player explicitly chooses which run to sacrifice.
	_show_load_screen(true)


func _on_load_game() -> void:
	_show_load_screen(false)


func _load_slot_into_game(slot: int) -> void:
	if not RunState.load_run(slot):
		# Save was corrupt or version-mismatched — wipe and rebuild the menu.
		RunState.clear_save(slot)
		_rebuild_menu()
		return
	# If the save was written while the player was mid-room (visit_node committed
	# them to a node but they quit before reaching the map again), drop them back
	# into that room. Otherwise they'd land on the map and lose the encounter
	# because get_available_nodes() advances past the visited position.
	var target := MAP_SCENE
	match RunState.current_node_type:
		"combat", "elite", "boss": target = COMBAT_SCENE
		"shop": target = SHOP_SCENE
		"rest": target = REST_SCENE
		"event": target = EVENT_SCENE
	GameTheme.fade_out_then_change_scene(self, target, 0.45)


func _begin_new_in_slot(slot: int) -> void:
	# Claims `slot` for the upcoming run. clear_save handles the "this slot
	# already had a save" case (callers in overwrite mode have already shown
	# the slot summary, so an extra confirmation here would just be friction).
	RunState.clear_save(slot)
	RunState.active_slot = slot
	_show_relic_select()


func _on_slot_delete(slot: int) -> void:
	# Wipes the slot's save and rebuilds the load screen so the row updates.
	RunState.clear_save(slot)
	_show_load_screen(false)


func _show_load_screen(overwrite_mode: bool) -> void:
	# Standalone screen showing all 3 slots with full continue/delete (normal
	# mode) or "begin new run here" (overwrite mode) actions. Replaces the
	# main menu column in place so the background atmosphere persists.
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	for child in menu.get_children():
		child.queue_free()

	var title_text := "OVERWRITE A SLOT" if overwrite_mode else "LOAD GAME"
	var title := _make_display_label(title_text, 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	menu.add_child(_make_ornament_row(220.0))

	if overwrite_mode:
		var hint := _make_display_label(
			"All slots are full — pick one to replace.", 13, ASH)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		menu.add_child(hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	menu.add_child(spacer)

	for i in range(RunState.SAVE_SLOTS):
		menu.add_child(_make_slot_row(i, overwrite_mode))

	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = Vector2(0, 8)
	menu.add_child(back_spacer)

	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 15, 40)
	back.pressed.connect(_rebuild_menu)
	menu.add_child(back)


func _show_relic_select() -> void:
	# Design intent: pick 1 of 3 starting relics before the run begins. Rebuilds
	# the menu column in place (reusing the proven VBox + button factory) so the
	# layout stays consistent with the main menu.
	var menu := get_node_or_null("Menu")
	if menu == null:
		# Fallback: never block starting a run if the menu node is missing.
		RunState.start_new_run()
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	for child in menu.get_children():
		child.queue_free()

	var title := _make_display_label("CHOOSE A STARTING RELIC", 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	menu.add_child(_make_ornament_row(220.0))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	menu.add_child(spacer)

	for rid in RelicDB.roll_relic_reward("starting"):
		menu.add_child(_make_relic_tile(rid))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		menu.add_child(gap)

	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 15, 40)
	back.pressed.connect(_rebuild_menu)
	menu.add_child(back)


func _begin_run_with(relic_id: String) -> void:
	RunState.start_new_run(relic_id, _selected_ascension)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)


func _change_ascension(delta: int) -> void:
	_selected_ascension = clampi(_selected_ascension + delta, 0, MetaState.unlocked_ascension)
	_rebuild_menu()


func _on_open_settings() -> void:
	# UserSettings keeps a persistent SettingsOverlay child — find it and open it.
	# Falls back gracefully if not present.
	for child in UserSettings.get_children():
		if child.has_method("_open"):
			child._open()
			return
		elif child.has_method("open"):
			child.open()
			return


func _on_quit() -> void:
	get_tree().quit()


# ---------------------------------------------------------------------------
# INTRO ANIMATION
# ---------------------------------------------------------------------------

func _animate_intro() -> void:
	# Title swells in from 85% scale with a gold pop; subtitle, ornament, then
	# buttons cascade. Final result is the menu "assembling itself" rather than
	# popping in fully formed.
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	for child in menu.get_children():
		child.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	var delay := 0.0
	for child in menu.get_children():
		var d := delay
		tw.tween_property(child, "modulate:a", 1.0, 0.35).set_delay(d)
		if child is Label and child.text.length() > 0 and (child as Label).get_theme_font_size("font_size") >= 50:
			child.pivot_offset = child.size * 0.5
			child.scale = Vector2(0.86, 0.86)
			tw.tween_property(child, "scale", Vector2.ONE, 0.55) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(d)
		delay += 0.07


# ─────────────────────────────────────────────────────────────────────────────
#  START-SCREEN MOTION (premium drift)
# ─────────────────────────────────────────────────────────────────────────────

func _setup_bg_parallax() -> void:
	# Oversize the background a touch and pivot it at centre so it can drift
	# (Ken Burns breath + mouse parallax) without ever exposing an edge. The
	# Background node survives menu rebuilds, so this runs once. _process drives it.
	_bg_node = get_node_or_null("Background") as TextureRect
	if _bg_node == null:
		return
	var vp := get_viewport_rect().size
	_bg_node.pivot_offset = vp * 0.5
	_bg_node.scale = Vector2(_bg_base_scale, _bg_base_scale)
	set_process(true)


func _process(delta: float) -> void:
	if _bg_node == null or not is_instance_valid(_bg_node):
		return
	_kb_time += delta
	# Smooth the cursor toward its target so parallax glides instead of snapping.
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var target := Vector2(
		clampf((m.x / maxf(vp.x, 1.0)) * 2.0 - 1.0, -1.0, 1.0),
		clampf((m.y / maxf(vp.y, 1.0)) * 2.0 - 1.0, -1.0, 1.0))
	_parallax_mouse = _parallax_mouse.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	# Ken Burns: a slow looping breath of position + zoom. Parallax: drift opposite
	# the cursor. Both stay well inside the oversize slack so no edge shows.
	var kb := Vector2(sin(_kb_time * 0.13) * 12.0, cos(_kb_time * 0.10) * 9.0)
	var par := -_parallax_mouse * 24.0
	_bg_node.position = kb + par
	var zoom := _bg_base_scale + sin(_kb_time * 0.08) * 0.012
	_bg_node.scale = Vector2(zoom, zoom)


func _add_menu_embers() -> void:
	# Warm embers rising up the burning meadow. Parented to the preserved
	# "Atmosphere" node so menu rebuilds (e.g. ascension changes) don't wipe them.
	var host: Node = get_node_or_null("Atmosphere")
	if host == null:
		host = self
	if host.has_node("MenuEmbers"):
		return
	var vp := get_viewport_rect().size
	var embers := CPUParticles2D.new()
	embers.name = "MenuEmbers"
	embers.position = Vector2(vp.x * 0.5, vp.y + 16.0)
	embers.z_index = 6
	embers.amount = 40
	embers.lifetime = 6.5
	embers.preprocess = 5.0   # start with the screen already full of drifting embers
	embers.randomness = 1.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(vp.x * 0.55, 6.0)
	embers.direction = Vector2(0, -1)
	embers.spread = 16.0
	embers.gravity = Vector2(8.0, -18.0)   # rise, with a gentle lateral lean
	embers.initial_velocity_min = 16.0
	embers.initial_velocity_max = 44.0
	embers.scale_amount_min = 1.4
	embers.scale_amount_max = 3.2
	# Fade in then out over life so embers wink in and burn out rather than pop.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.62, 0.26, 0.0))
	ramp.set_color(1, Color(1.0, 0.40, 0.14, 0.0))
	ramp.add_point(0.18, Color(1.0, 0.66, 0.32, 0.85))
	ramp.add_point(0.7, Color(1.0, 0.46, 0.18, 0.6))
	embers.color_ramp = ramp
	embers.emitting = true
	host.add_child(embers)


func _start_title_shimmer() -> void:
	# A slow gold glow + breath on the title so it stays alive after the intro pop.
	# Uses modulate + scale (not position) so the VBox layout never fights it.
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	var title := menu.get_node_or_null("TitleLabel") as Label
	if title == null:
		return
	if _title_shimmer_tween != null and _title_shimmer_tween.is_valid():
		_title_shimmer_tween.kill()
	# Let the intro's pop-in settle before the loop captures the resting look.
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(title):
		return
	title.pivot_offset = title.size * 0.5
	var base := title.modulate
	var glow := Color(min(base.r * 1.16, 1.0), min(base.g * 1.10, 1.0), base.b, base.a)
	_title_shimmer_tween = create_tween().set_loops()
	_title_shimmer_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_shimmer_tween.tween_property(title, "modulate", glow, 2.2)
	_title_shimmer_tween.parallel().tween_property(title, "scale", Vector2(1.025, 1.025), 2.2)
	_title_shimmer_tween.tween_property(title, "modulate", base, 2.2)
	_title_shimmer_tween.parallel().tween_property(title, "scale", Vector2.ONE, 2.2)
