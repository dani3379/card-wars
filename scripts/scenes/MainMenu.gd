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
const TREASURE_SCENE = "res://scenes/treasure.tscn"
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

# Pending seed override for the upcoming run. 0 = roll a fresh seed (normal run).
# Set by _on_daily_run / _on_custom_run so _begin_run_with can hand it to
# RunState.start_new_run. Cleared after start so subsequent new-runs roll
# their own seeds again.
var _pending_seed_override: int = 0

# ── Start-screen motion (premium drift) ──────────────────────────────────────
# The background slowly breathes (Ken Burns) and drifts opposite the cursor for a
# parallax depth feel; the title shimmers; warm embers rise up the screen. All
# Tween/CPUParticles2D — no shaders (gl_compatibility-safe).
var _bg_node: TextureRect = null
var _bg_base_scale: float = 1.15           # oversize so drift never reveals edges
var _parallax_mouse: Vector2 = Vector2.ZERO  # smoothed cursor offset, each axis [-1, 1]
var _kb_time: float = 0.0                   # Ken Burns clock
var _title_shimmer_tween: Tween = null

# Hero-select (cast lineup + shared detail pane). The row brightens the focused
# hero; the pane below shows only that hero's loadout — so each card stays down
# to portrait + name + tagline instead of six stacked text blocks.
var _hero_detail: VBoxContainer = null
var _hero_cards: Dictionary = {}       # hid -> Button (for selected-state styling)
var _hero_portraits: Dictionary = {}   # hid -> Control (for focus brighten/dim)
var _selected_hero: String = ""


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

	# ── Epigraph: the fiction, in the meadow's voice. Deliberately the SAME text
	# as the Steam short description — a buyer and a new player are converted by
	# the same words. Direction C (you are an effigy the burning meadow keeps
	# re-casting); "they always are" lands the roguelike loop as a tonal promise,
	# not a spoiler. Left-flush + autowrapped to the column width.
	var epigraph := _make_display_label(
		"You lit the first flame so long ago you've forgotten it was you. The road remembers. Everything on it is already expecting you — they always are.",
		14, IVORY)
	epigraph.name = "Epigraph"
	epigraph.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	epigraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epigraph.custom_minimum_size = Vector2(560, 0)
	col.add_child(epigraph)

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

	# Daily run — deterministic seed from today's date so every player gets
	# the same map and can compare scores. Same size as other main buttons;
	# hierarchy comes from the muted color, not from shrinking the button.
	var btn_daily := _make_menu_button("DAILY RUN",
		Color(0.30, 0.24, 0.34), MENU_FONT, MENU_H)
	btn_daily.pressed.connect(_on_daily_run)
	col.add_child(btn_daily)

	# Custom seed — opens an input screen for sharing/replaying specific maps.
	var btn_custom := _make_menu_button("CUSTOM SEED",
		Color(0.30, 0.24, 0.34), MENU_FONT, MENU_H)
	btn_custom.pressed.connect(_on_custom_run)
	col.add_child(btn_custom)

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

	var btn_gallery := _make_menu_button("COLLECTION",
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
			title_text = "SLOT %d  ·  Overwrite This Run" % (slot + 1)
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
		"treasure": target = TREASURE_SCENE
	GameTheme.fade_out_then_change_scene(self, target, 0.45)


func _begin_new_in_slot(slot: int) -> void:
	# Claims `slot` for the upcoming run. clear_save handles the "this slot
	# already had a save" case (callers in overwrite mode have already shown
	# the slot summary, so an extra confirmation here would just be friction).
	RunState.clear_save(slot)
	RunState.active_slot = slot
	_show_hero_select()


func _on_slot_delete(slot: int) -> void:
	# Wipes the slot's save and rebuilds the load screen so the row updates.
	RunState.clear_save(slot)
	_show_load_screen(false)


func _center_menu_for_subscreen(width: float = 620.0, height: float = 640.0) -> void:
	# Re-anchor the Menu VBox from the main-menu left column to a screen-
	# centered rect. The main menu wants left-alignment so the painted
	# character splash on the right stays unobstructed, but for sub-screens
	# (LOAD GAME, CHOOSE A STARTING RELIC) the same anchor leaves a narrow
	# UI column floating in dead space — recentering balances the composition.
	# _rebuild_menu() resets the anchors when returning to the main menu, so
	# this only needs to flip one way.
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 0.5
	menu.anchor_bottom = 0.5
	menu.offset_left = -width / 2.0
	menu.offset_right = width / 2.0
	menu.offset_top = -height / 2.0
	menu.offset_bottom = height / 2.0


func _show_load_screen(overwrite_mode: bool) -> void:
	# Standalone screen showing all 3 slots with full continue/delete (normal
	# mode) or "begin new run here" (overwrite mode) actions. Replaces the
	# main menu column in place so the background atmosphere persists.
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	for child in menu.get_children():
		child.queue_free()
	_center_menu_for_subscreen()

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


func _show_hero_select() -> void:
	# Cast-lineup hero pick (StS/Hades pattern): a row of frameless portrait cards
	# over the burning-meadow background. Each card stays down to portrait + name +
	# tagline; hovering a hero spotlights it and fills the shared detail pane below
	# with that hero's lore / loadout / relic. Clicking a card starts the run.
	var menu := get_node_or_null("Menu")
	if menu == null:
		# Fallback: never block starting a run if the menu node is missing.
		RunState.start_new_run()
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	for child in menu.get_children():
		child.queue_free()
	_hero_cards.clear()
	_hero_portraits.clear()
	_selected_hero = ""
	_center_menu_for_subscreen(960.0, 700.0)

	var title := _make_display_label("CHOOSE YOUR HERO", 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	menu.add_child(_make_ornament_row(260.0))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	menu.add_child(spacer)

	# The cast: one frameless portrait card per hero, in a row.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(row)
	for hid in HeroDB.HERO_ORDER:
		row.add_child(_make_hero_card(hid))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	menu.add_child(gap)

	# Shared detail pane — filled for the focused hero only, so the dense loadout
	# text appears once (with room to breathe) instead of on all four cards. A soft
	# dark scrim sits behind it (no hard border) so the small text stays legible
	# over the busy fire background.
	var detail_frame := PanelContainer.new()
	var detail_bg := StyleBoxFlat.new()
	detail_bg.bg_color = Color(0.05, 0.035, 0.045, 0.55)
	detail_bg.set_corner_radius_all(8)
	detail_bg.content_margin_left = 26
	detail_bg.content_margin_right = 26
	detail_bg.content_margin_top = 14
	detail_bg.content_margin_bottom = 14
	detail_frame.add_theme_stylebox_override("panel", detail_bg)
	detail_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail_frame.custom_minimum_size = Vector2(700, 190)
	menu.add_child(detail_frame)
	_hero_detail = VBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 5)
	detail_frame.add_child(_hero_detail)

	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = Vector2(0, 6)
	menu.add_child(back_spacer)

	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 15, 40)
	back.pressed.connect(_rebuild_menu)
	menu.add_child(back)

	# Default the spotlight to the first hero so the pane is never blank.
	_focus_hero(HeroDB.HERO_ORDER[0])


func _make_hero_card(hid: String) -> Button:
	# One frameless portrait card. The clickable Button has empty styleboxes in
	# every state (no boxy rectangle); the focus spotlight + gilt underline are
	# applied in _focus_hero. All children are MOUSE_FILTER_IGNORE so hover/click
	# fall through to the Button.
	var hero := HeroDB.get_hero(hid)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(188, 292)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	# Portrait (or a color-wash fallback if its art isn't painted yet). Stored so
	# _focus_hero can brighten the spotlighted hero and dim the rest.
	var port_size := Vector2(168, 210)
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	if ResourceLoader.exists(portrait_path):
		var portrait := TextureRect.new()
		portrait.texture = load(portrait_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = port_size
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.modulate = Color(0.70, 0.68, 0.66)
		col.add_child(portrait)
		_hero_portraits[hid] = portrait
	else:
		var wash := ColorRect.new()
		wash.custom_minimum_size = port_size
		wash.color = Color(0.16, 0.14, 0.20)
		wash.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wash.modulate = Color(0.70, 0.68, 0.66)
		col.add_child(wash)
		_hero_portraits[hid] = wash

	var name_lbl := _make_display_label(String(hero.get("name", hid)), 22, GILT_BRIGHT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var tag_lbl := _make_display_label(String(hero.get("tagline", "")), 12, Color(0.95, 0.82, 0.55))
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_lbl.custom_minimum_size = Vector2(168, 0)
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tag_lbl)

	btn.mouse_entered.connect(_focus_hero.bind(hid))
	btn.pressed.connect(_begin_run_with.bind(hid))
	_hero_cards[hid] = btn
	return btn


func _focus_hero(hid: String) -> void:
	# Spotlight one hero: brighten its portrait, dim the rest, light its gilt
	# underline, and repaint the shared detail pane. Pane-only update — never
	# rebuilds the cards (which would re-load() portrait textures and flicker).
	if _selected_hero == hid and _hero_detail != null and _hero_detail.get_child_count() > 0:
		return
	_selected_hero = hid
	for k in _hero_portraits:
		var p = _hero_portraits[k]
		if is_instance_valid(p):
			p.modulate = Color(1.08, 1.04, 0.98) if k == hid else Color(0.62, 0.60, 0.60)
	for k in _hero_cards:
		var b = _hero_cards[k]
		if is_instance_valid(b):
			var box: StyleBox = _hero_focus_box() if k == hid else StyleBoxEmpty.new()
			b.add_theme_stylebox_override("normal", box)
			b.add_theme_stylebox_override("hover", box)
			b.add_theme_stylebox_override("pressed", box)
	_build_hero_detail(hid)


func _hero_focus_box() -> StyleBoxFlat:
	# Frameless-friendly selection: a faint warm wash, a gilt underline, and a
	# soft glow — no full rectangle border (the dev dislikes boxy tiles).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.07)
	sb.border_width_bottom = 3
	sb.border_color = GILT_BRIGHT
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.28)
	sb.shadow_size = 10
	return sb


func _build_hero_detail(hid: String) -> void:
	# Fills the shared pane with the focused hero's lore + mechanical pitch + deck
	# composition + starting relic. This is where the text we pulled off the cards
	# now lives — once, with reading room.
	if _hero_detail == null:
		return
	for c in _hero_detail.get_children():
		c.queue_free()
	var hero := HeroDB.get_hero(hid)

	var lore := String(hero.get("lore", ""))
	if lore != "":
		var lore_lbl := _make_display_label(lore, 15, Color(0.82, 0.76, 0.88))
		lore_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hero_detail.add_child(lore_lbl)

	var desc_lbl := _make_display_label(String(hero.get("desc", "")), 14, IVORY)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_detail.add_child(desc_lbl)

	_hero_detail.add_child(_make_ornament_row(300.0, true))

	var deck_lbl := _make_display_label("DECK    " + _summarize_deck(hero.get("deck", [])), 12, Color(0.80, 0.76, 0.64))
	deck_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	deck_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_detail.add_child(deck_lbl)

	var relic_id := String(hero.get("relic", ""))
	if relic_id != "":
		var relic_row := HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 10)
		relic_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		var chip := GameTheme.make_relic_chip(relic_id, 40)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		relic_row.add_child(chip)
		var rcol := VBoxContainer.new()
		rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rcol.add_theme_constant_override("separation", 1)
		relic_row.add_child(rcol)
		var rd := RelicDB.get_relic(relic_id)
		var rname := _make_display_label(String(rd.get("name", relic_id)), 13, GILT_BRIGHT)
		rcol.add_child(rname)
		var rdesc := _make_display_label(String(rd.get("desc", "")), 11, IVORY)
		rdesc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rcol.add_child(rdesc)
		_hero_detail.add_child(relic_row)

	var hint := _make_display_label("Click a hero to begin the run.", 11, ASH)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hero_detail.add_child(hint)


func _summarize_deck(deck: Array) -> String:
	# "4× Goblin · 2× Brute · 2× Ratling · 2× Fireball" — aggregates the raw
	# 10-card list into a copy-readable composition string. Preserves the first-
	# seen order so the heaviest cards (which the deck leads with) read first.
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in deck:
		var id: String = String(cid)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += 1
	var parts: Array[String] = []
	for id in order:
		var card := CardDB.get_card_data(id)
		var name: String = String(card.get("name", id))
		parts.append("%d× %s" % [int(counts[id]), name])
	return "  ·  ".join(parts)


func _begin_run_with(hero_id: String) -> void:
	# Hand the pending seed override (set by _on_daily_run / _on_custom_run) to
	# start_new_run, then clear it so the next plain NEW RUN rolls fresh again.
	var seed_to_use := _pending_seed_override
	_pending_seed_override = 0
	RunState.start_new_run(hero_id, _selected_ascension, seed_to_use)
	# After the hero is locked in, offer the run's opening blessing — 3 safe
	# tiles (one per reward family) + 1 risky tile (real cost, bigger payoff).
	# Skipping is allowed and routes straight to the map.
	_show_blessing_select()


func _on_daily_run() -> void:
	# Slot allocation mirrors _on_new_run, but with a deterministic seed.
	_pending_seed_override = RunState.daily_seed()
	var empty := _first_empty_slot()
	if empty >= 0:
		_begin_new_in_slot(empty)
	else:
		_show_load_screen(true)


func _on_custom_run() -> void:
	# Opens the seed-input screen. Actual run start happens after the player
	# types a seed and clicks BEGIN (handler: _start_custom_run).
	_show_custom_seed_input()


func _show_custom_seed_input() -> void:
	# Replaces the menu column with a centered text-input form, matching the
	# relic-select pattern. Reuses _center_menu_for_subscreen so it lands in
	# the same visual position as the other sub-screens.
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	for child in menu.get_children():
		child.queue_free()
	_center_menu_for_subscreen()

	var title := _make_display_label("CUSTOM SEED", 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	menu.add_child(_make_ornament_row(220.0))

	var hint := _make_display_label(
		"Type a seed. Same seed → same map.\nShare it with a friend for a head-to-head run.",
		15, ASH)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	menu.add_child(spacer)

	var edit := LineEdit.new()
	edit.name = "SeedInput"
	edit.placeholder_text = "burningmeadow"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 20)
	edit.add_theme_color_override("font_color", IVORY)
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.42))
	edit.custom_minimum_size = Vector2(360, 44)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if GameTheme.font_display:
		edit.add_theme_font_override("font", GameTheme.font_display)
	menu.add_child(edit)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	menu.add_child(spacer2)

	var begin := _make_menu_button("BEGIN", Color(0.18, 0.36, 0.18), 22, 50)
	begin.pressed.connect(func():
		var s: String = edit.text.strip_edges().to_lower()
		if s == "":
			s = "burningmeadow"
		_pending_seed_override = RunState.seed_from_string(s)
		var empty := _first_empty_slot()
		if empty >= 0:
			_begin_new_in_slot(empty)
		else:
			_show_load_screen(true)
	)
	menu.add_child(begin)

	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 15, 40)
	back.pressed.connect(func():
		_pending_seed_override = 0
		_rebuild_menu()
	)
	menu.add_child(back)


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


# ---------------------------------------------------------------------------
# OPENING BLESSING
# ---------------------------------------------------------------------------
# After the hero is picked, the player gets a single opening boon: 3 "safe"
# tiles drawn from the seven reward families (gold, heal, max HP, free relic,
# free potion, free card, free upgrade) plus 1 "risky" tile with a real cost
# and a bigger payoff. SKIP is always available — the run can start cold if
# the player wants the full StS opening.
#
# This is built in MainMenu (rather than a dedicated scene) so it reuses the
# atmosphere/parallax already running behind the menu and shares the hero-
# pick sub-screen pattern (replace the Menu VBox in place, no scene change).

func _show_blessing_select() -> void:
	var menu := get_node_or_null("Menu")
	if menu == null:
		# If the menu node somehow vanished, never block the run from starting.
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	# Hide the centered Menu VBox used by every other sub-screen — the blessing
	# screen lays itself out as a full-screen event-style composition (title
	# top-left, choices stacked bottom-left) so it reads like the in-run event
	# rooms instead of a boxed picker dialog.
	menu.visible = false

	# Defensive cleanup in case the screen is re-entered.
	for child in get_children():
		var cname: String = child.name
		if cname in ["Background", "Atmosphere", "Menu"]:
			continue
		child.queue_free()

	const COLUMN_LEFT := 110
	const COLUMN_WIDTH := 760

	var title := _make_display_label("AN OPENING BLESSING", 38, GILT_BRIGHT)
	title.name = "BlessingTitle"
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = COLUMN_LEFT
	title.offset_top = 90
	title.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	title.offset_bottom = 90 + 60
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 2)
	add_child(title)

	var ornament := _make_ornament_row(220.0, true)
	ornament.name = "BlessingOrnament"
	ornament.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ornament.offset_left = COLUMN_LEFT
	ornament.offset_top = 154
	ornament.offset_right = COLUMN_LEFT + 260
	ornament.offset_bottom = 174
	add_child(ornament)

	var hint := _make_display_label(
		"The road is long. Take a gift before you begin — three are kind, one demands a price.",
		17, IVORY)
	hint.name = "BlessingHint"
	hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint.offset_left = COLUMN_LEFT
	hint.offset_top = 184
	hint.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	hint.offset_bottom = 184 + 60
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("outline_size", 3)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("shadow_offset_x", 0)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(hint)

	# Frameless gem-prefixed choices, stacked bottom-left like the in-run event
	# screen. Same composition as Event.gd: the choice ladder is the focal point,
	# the description floats above, the skip is tucked beneath.
	var num_choices := 4
	var choice_h := 84
	var stack_h := num_choices * choice_h + (num_choices - 1) * 8
	var choices_vbox := VBoxContainer.new()
	choices_vbox.name = "BlessingChoices"
	choices_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	choices_vbox.offset_left = COLUMN_LEFT
	choices_vbox.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	choices_vbox.offset_top = -(stack_h + 120)
	choices_vbox.offset_bottom = -120
	choices_vbox.add_theme_constant_override("separation", 8)
	add_child(choices_vbox)

	var blessings := _roll_blessings()
	for entry in blessings:
		choices_vbox.add_child(_make_blessing_choice(entry, choice_h))

	var skip := _make_menu_button("SKIP — BEGIN THE RUN",
		Color(0.22, 0.16, 0.14), 16, 40)
	skip.name = "BlessingSkip"
	skip.pressed.connect(_skip_blessing)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skip.offset_left = COLUMN_LEFT
	skip.offset_right = COLUMN_LEFT + 360
	skip.offset_top = -82
	skip.offset_bottom = -36
	add_child(skip)


# Roll the displayed tiles: 3 distinct safe entries + 1 risky entry.
# Each "entry" is a dict {id, name, desc, risky, color, apply: Callable} —
# the actual mutation lives on `apply` so the tile click handler stays one
# line. Some families (free relic / free potion / free card) sample from the
# live DB at apply time so the player can't peek at the exact card before
# committing.
func _roll_blessings() -> Array:
	var safe_pool: Array[String] = [
		"gold", "heal", "max_hp", "relic", "potion", "card", "upgrade",
	]
	safe_pool.shuffle()
	var picked_safe := safe_pool.slice(0, 3)

	var risky_pool: Array[String] = [
		"pact_relic", "cursed_gold", "glass_pact", "devourer",
	]
	var picked_risky: String = risky_pool[randi() % risky_pool.size()]

	var entries: Array = []
	for id in picked_safe:
		entries.append(_blessing_entry(id, false))
	entries.append(_blessing_entry(picked_risky, true))
	# Shuffle so the risky tile isn't always the last cell.
	entries.shuffle()
	return entries


func _blessing_entry(id: String, risky: bool) -> Dictionary:
	# Centralised description / tint per blessing. Effects are applied in
	# _apply_blessing — keeping render data and effect logic separate so a
	# typo in copy can't accidentally double-pay the player.
	var safe_color := Color(0.18, 0.30, 0.20)   # green-leaning for "safe"
	var risk_color := Color(0.36, 0.18, 0.22)   # deep wine for "risky"
	var color: Color = risk_color if risky else safe_color
	var data := {"id": id, "risky": risky, "color": color}
	match id:
		# ── Safe ──
		"gold":
			data["name"] = "Heavy Purse"
			data["desc"] = "Gain 60 gold."
		"heal":
			data["name"] = "Healer's Touch"
			data["desc"] = "Heal 12 HP."
		"max_hp":
			data["name"] = "Iron Constitution"
			data["desc"] = "+6 max HP, and heal 6 HP."
		"relic":
			data["name"] = "Wanderer's Trinket"
			data["desc"] = "Gain a random combat relic."
		"potion":
			data["name"] = "Hidden Cache"
			data["desc"] = "Gain a random potion and 20 gold."
		"card":
			data["name"] = "Strange Diagram"
			data["desc"] = "Add a random uncommon card to your deck."
		"upgrade":
			data["name"] = "Travelling Whetstone"
			data["desc"] = "Sharpen a random un-upgraded card in your deck."
		# ── Risky ──
		"pact_relic":
			data["name"] = "Pact of Embers"
			data["desc"] = "Gain a random rare relic — but add 2 curses to your deck."
		"cursed_gold":
			data["name"] = "Cursed Coin Pile"
			data["desc"] = "Gain 150 gold — but lose 6 max HP."
		"glass_pact":
			data["name"] = "Glass Pact"
			data["desc"] = "+10 max HP and full heal — but gain 1 curse."
		"devourer":
			data["name"] = "Devourer's Boon"
			data["desc"] = "A random creature gains +2 ATK and Wither 1 permanently."
		_:
			data["name"] = id
			data["desc"] = ""
	return data


func _make_blessing_choice(entry: Dictionary, height: int) -> Button:
	# Frameless gem-prefixed choice — mirrors the in-run Event.gd choice style
	# (gem on the left, headline + body to its right, no panel chrome). Risky
	# entries get a wine-tinted gem and a "RISKY" chip beside the headline so
	# the player can read the warning without a separate panel color.
	var risky: bool = bool(entry.get("risky", false))
	var name_text: String = String(entry.get("name", ""))
	var desc_text: String = String(entry.get("desc", ""))

	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(560, height)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, transparent)

	btn.pressed.connect(_pick_blessing.bind(entry))

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 24
	hbox.offset_right = -24
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var gem := TextureRect.new()
	var diamond_tex := load("res://assets/icons/diamond.png") as Texture2D
	if diamond_tex:
		gem.texture = diamond_tex
	gem.custom_minimum_size = Vector2(18, 18)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var base_gem_color: Color = (
		Color(0.85, 0.32, 0.30, 0.95) if risky
		else Color(GILT.r, GILT.g, GILT.b, 0.85))
	var hover_gem_color: Color = (
		Color(1.0, 0.50, 0.40, 1.0) if risky
		else Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 1.0))
	gem.modulate = base_gem_color
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(gem)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	# Headline row: name on the left, optional RISKY chip on the right.
	var headline_row := HBoxContainer.new()
	headline_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline_row.add_theme_constant_override("separation", 12)
	headline_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(headline_row)

	var headline := Label.new()
	headline.text = name_text
	headline.add_theme_font_size_override("font_size", 26)
	headline.add_theme_color_override("font_color", IVORY)
	headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.80))
	headline.add_theme_constant_override("outline_size", 3)
	headline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	headline.add_theme_constant_override("shadow_offset_x", 0)
	headline.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		headline.add_theme_font_override("font", GameTheme.font_display)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline_row.add_child(headline)

	if risky:
		var chip := Label.new()
		chip.text = "RISKY"
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_color_override("font_color", Color(1.0, 0.55, 0.42))
		chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		chip.add_theme_constant_override("outline_size", 3)
		if GameTheme.font_display:
			chip.add_theme_font_override("font", GameTheme.font_display)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		headline_row.add_child(chip)

	var body := Label.new()
	body.text = desc_text
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", GameTheme.DESC_DIM)
	body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.70))
	body.add_theme_constant_override("outline_size", 2)
	body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	body.add_theme_constant_override("shadow_offset_x", 0)
	body.add_theme_constant_override("shadow_offset_y", 1)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body:
		body.add_theme_font_override("font", GameTheme.font_body)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)

	btn.mouse_entered.connect(func() -> void:
		gem.modulate = hover_gem_color
		headline.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD)
	)
	btn.mouse_exited.connect(func() -> void:
		gem.modulate = base_gem_color
		headline.add_theme_color_override("font_color", IVORY)
	)

	return btn


func _pick_blessing(entry: Dictionary) -> void:
	_apply_blessing(String(entry.get("id", "")))
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)


func _skip_blessing() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)


# Applies the picked blessing's mutation to RunState. Effects sample from the
# live DBs (relics/potions/cards/upgrades) at apply time so the tile copy
# stays evergreen — and so the player can't peek at the exact roll. Every
# branch is intentionally self-contained: no shared "reward bundle" helper,
# because the families don't actually overlap (a card add doesn't compose
# with a relic add for this screen) and inlining is easier to audit.
func _apply_blessing(id: String) -> void:
	match id:
		# ── Safe ──
		"gold":
			RunState.gain_gold(60)
		"heal":
			RunState.heal_hero(12)
		"max_hp":
			RunState.hero_max_hp += 6
			RunState.heal_hero(6)
		"relic":
			var pool: Array[String] = RelicDB.roll_relic_reward(
				"combat", RunState.relics, RunState.current_hero_id)
			if not pool.is_empty():
				RunState.add_relic(pool[0])
		"potion":
			if RunState.can_add_potion():
				RunState.add_potion(PotionDB.roll_random_potion())
			RunState.gain_gold(20)
		"card":
			var uncommons: Array[String] = CardDB.get_pool_by_rarity("uncommon")
			if not uncommons.is_empty():
				RunState.add_card(uncommons[randi() % uncommons.size()])
		"upgrade":
			# Sharpen a random un-upgraded creature/spell. Mirrors Olympian's
			# Mark's auto-upgrade so we don't open a picker on the menu screen.
			var candidates: Array[int] = []
			for i in RunState.deck.size():
				if RunState.has_upgrade_path(i, "plus"):
					continue
				var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
				if d.get("type", "") in ["creature", "spell"] \
						and CardDB.is_upgradeable(RunState.deck[i]):
					candidates.append(i)
			if not candidates.is_empty():
				RunState.upgrade_card(
					candidates[randi() % candidates.size()], "plus")
		# ── Risky ──
		"pact_relic":
			# Roll a rare relic from the boss pool — these are the strongest
			# in the game, justifying the curse tax. Two curses, not three,
			# because this fires on round 1 with a fresh deck (no upgrades to
			# soak the dilution yet).
			var bosses: Array[String] = RelicDB.roll_boss_relics(
				RunState.relics, RunState.current_hero_id)
			if not bosses.is_empty():
				RunState.add_relic(bosses[0])
			for _i in 2:
				RunState.add_card(CardDB.random_curse_id())
		"cursed_gold":
			RunState.gain_gold(150)
			RunState.hero_max_hp = maxi(1, RunState.hero_max_hp - 6)
			RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)
		"glass_pact":
			RunState.hero_max_hp += 10
			RunState.heal_hero(RunState.hero_max_hp)
			RunState.add_card(CardDB.random_curse_id())
		"devourer":
			# Pick a non-starter creature so the boon lands on a real combat
			# unit, not a 1/1 starter goblin. Falls back to any creature if
			# the deck is starter-only (Pyromancer / Acolyte openers).
			var creature_indices: Array[int] = []
			var starter_indices: Array[int] = []
			for i in RunState.deck.size():
				var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
				if d.get("type", "") != "creature":
					continue
				if d.get("rarity", "") == "starter":
					starter_indices.append(i)
				else:
					creature_indices.append(i)
			var pool: Array[int] = creature_indices if not creature_indices.is_empty() \
				else starter_indices
			if not pool.is_empty():
				RunState.upgrade_card(
					pool[randi() % pool.size()], "butcher")
