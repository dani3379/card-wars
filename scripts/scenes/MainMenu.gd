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
const SKIRMISH_SCENE = "res://scenes/net_lobby.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

const GILT := Color(0.83, 0.74, 0.54, 1.0)
const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)

# Currently selected ascension tier. -1 means "not initialized yet" — gets
# clamped to MetaState.unlocked_ascension on the first menu build. Survives
# across menu rebuilds (e.g. relic-select → back) so the player doesn't have
# to re-pick their tier every time.
var _selected_ascension: int = -1

# Run-setup state (lives on the hero-select screen since the 2026-07-02 menu
# consolidation — DAILY RUN / CUSTOM SEED / the ascension stepper used to be
# top-level menu entries). _daily_pick locks the seed to today's; a non-empty
# seed field hashes to a custom seed; both reset on each fresh setup screen.
var _daily_pick: bool = false
var _daily_btn: Button = null
var _seed_edit: LineEdit = null
var _asc_label: Label = null
# Rule readout under the setup row — lists what the selected ascension actually
# DOES (each tier is a rule, not an HP multiplier; see RunState.ASCENSION_RULES).
var _asc_rules_label: Label = null

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
# Full-size readable copy of a hovered deck mini (the NetDraft ledger-preview
# behaviour). Child of the menu root; freed on unhover / pane rebuild.
var _deck_preview: Control = null


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	AudioBank.play_music_random(["main_menu", "main_menu_b"])
	_rebuild_menu()
	_setup_bg_parallax()
	_add_menu_embers()
	# MARCH AGAIN from the game-over screen: skip the menu beat entirely and
	# restart with the same hero + ascension (fresh seed), straight into the
	# war chest. The menu column was built above so the blessing sub-screen
	# has its usual scaffolding to hide.
	if not RunState.rematch_request.is_empty():
		_start_rematch()
		return
	_animate_intro()


func _start_rematch() -> void:
	var req: Dictionary = RunState.rematch_request
	RunState.rematch_request = {}
	# Reuse the slot the ended run lived in; fall back to any free slot (or
	# slot 0) if state got weird. The ended run's save is already spent.
	var slot: int = RunState.active_slot
	if slot < 0 or slot >= RunState.SAVE_SLOTS:
		slot = _first_empty_slot()
		if slot < 0:
			slot = 0
	RunState.clear_save(slot)
	RunState.active_slot = slot
	_selected_ascension = clampi(int(req.get("ascension", 0)),
		0, MetaState.unlocked_ascension)
	_daily_pick = false
	_begin_run_with(String(req.get("hero", "")))


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
	# Tight separation: the full menu (save + ascension) stacks ~11 buttons plus
	# the title/epigraph/ornaments, which overflowed 900px and pushed Settings/Quit
	# off-screen. 8px keeps it inside the canvas.
	col.add_theme_constant_override("separation", 8)
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
	# Brighter than ASH (0.62 grey washed out over the fire) so the tagline reads.
	var sub := _make_display_label("a lane combat roguelike deckbuilder", 19,
		Color(0.86, 0.80, 0.66))
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
		17, IVORY)
	epigraph.name = "Epigraph"
	epigraph.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	epigraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epigraph.custom_minimum_size = Vector2(600, 0)
	col.add_child(epigraph)

	# ── Ornament: gilt line with central rosette glyph (a diamond, NOT a triangle).
	# This is the "card-game opening flourish" — it sells the screen as a deck-
	# builder rather than a generic Godot template. Left-flush to match the column.
	col.add_child(_make_ornament_row(260.0, true))

	# Spacer pushes the buttons down so the title has breathing room.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)

	# Default the selected ascension to the highest unlocked tier so returning
	# players climb naturally; selector below lets them drop back if they want.
	if _selected_ascension < 0 or _selected_ascension > MetaState.unlocked_ascension:
		_selected_ascension = MetaState.unlocked_ascension

	# ── Primary actions ──
	# 2026-07-02 consolidation: the column carries at most 8 items (was 11+).
	# CONTINUE jumps into the most recent save; NEW MARCH opens the run-setup
	# screen (hero pick, which now also owns ascension / daily / seed — those
	# used to be three separate top-level menu entries); LOAD GAME appears
	# only when a SECOND slot is filled (with one save, CONTINUE covers it).
	var has_any_save := _any_save_exists()

	# All main-menu buttons share font_size=22 and height=50 — visual
	# hierarchy comes from per-button COLOR, not size. The previous mix of
	# 17/19/20/22/24 sizes felt random; uniform sizing reads like a single
	# menu group (matches Ratropolis / Slay the Spire conventions).
	const MENU_FONT := 22
	const MENU_H := 40
	if has_any_save:
		var recent_slot := _most_recent_slot()
		var btn_continue := _make_menu_button("CONTINUE",
			Color(0.32, 0.26, 0.14), MENU_FONT, MENU_H)
		btn_continue.tooltip_text = _continue_preview_line(recent_slot, true)
		btn_continue.pressed.connect(_on_continue_recent)
		col.add_child(btn_continue)
		var preview := _make_display_label(_continue_preview_line(recent_slot), 14,
			Color(0.91, 0.76, 0.48))
		preview.name = "ContinuePreview"
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.custom_minimum_size = Vector2(600, 0)
		col.add_child(preview)

	var begin_label: String = "NEW MARCH"
	if MetaState.unlocked_ascension > 0:
		begin_label = "NEW MARCH — ASC %d" % _selected_ascension
	var btn_start := _make_menu_button(begin_label,
		Color(0.18, 0.36, 0.18), MENU_FONT, MENU_H)
	btn_start.pressed.connect(_on_new_run)
	col.add_child(btn_start)

	if _filled_slot_count() >= 2:
		var btn_load := _make_menu_button("LOAD GAME",
			Color(0.20, 0.28, 0.42), MENU_FONT, MENU_H)
		btn_load.pressed.connect(_on_load_game)
		col.add_child(btn_load)

	# Skirmish — draft-and-fight 1-v-1 (online rooms, LAN, or the practice
	# bot — the lobby carries all three, so no "(ONLINE)" qualifier). See
	# docs/MULTIPLAYER_SKIRMISH_PLAN.md.
	var btn_skirmish := _make_menu_button("SKIRMISH",
		Color(0.20, 0.28, 0.42), MENU_FONT, MENU_H)
	btn_skirmish.pressed.connect(func():
		GameTheme.fade_out_then_change_scene(self, SKIRMISH_SCENE))
	col.add_child(btn_skirmish)

	var btn_gallery := _make_menu_button("COLLECTION",
		Color(0.16, 0.20, 0.32), MENU_FONT, MENU_H)
	btn_gallery.pressed.connect(func():
		GameTheme.fade_out_then_change_scene(self, COLLECTION_SCENE))
	col.add_child(btn_gallery)

	# How to play — the campaign primer + full keyword glossary, reachable
	# without starting a run (all other teaching lives inside combat). Opens an
	# in-place overlay so the menu atmosphere keeps running behind it.
	var btn_help := _make_menu_button("HOW TO PLAY",
		Color(0.20, 0.24, 0.20), MENU_FONT, MENU_H)
	btn_help.pressed.connect(_show_how_to_play)
	col.add_child(btn_help)

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
	var stats := _make_display_label(_stats_text(), 17, Color(0.80, 0.75, 0.64))
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
	credits_btn.custom_minimum_size = Vector2(0, 26)
	credits_btn.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	credits_btn.add_theme_color_override("font_color", Color(0.74, 0.70, 0.62))
	credits_btn.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	if GameTheme.font_body:
		credits_btn.add_theme_font_override("font", GameTheme.font_body)
	credits_btn.pressed.connect(func():
		GameTheme.fade_out_then_change_scene(self, CREDITS_SCENE, 0.30))
	col.add_child(credits_btn)

	# Build stamp — a dev-only confirmation that the running code is the latest
	# source (if you DON'T see this line, the editor is running cached scripts:
	# restart, then F5). Debug builds only — exported releases don't ship a
	# work-log line on the title screen.
	if OS.is_debug_build():
		var build_stamp := GameTheme.make_label(
			"build 2026-07-07 · polish + hardening (map/HUD/cards/saves)", 13,
			Color(0.82, 0.66, 0.32))
		build_stamp.name = "BuildStamp"
		build_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(build_stamp)

	_build_command_dossier(has_any_save)

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
	if height >= 40:
		var flame_l := _make_flame_accent()
		inner.add_child(flame_l)
		flames.append(flame_l)

	var text_stack := VBoxContainer.new()
	text_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	text_stack.add_theme_constant_override("separation", 0)
	text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text_stack)

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
	text_stack.add_child(lbl)

	var rule: ColorRect = null
	if height >= 40:
		rule = ColorRect.new()
		rule.custom_minimum_size = Vector2(maxf(92.0, float(text.length()) * 7.5), 2)
		rule.color = GILT_BRIGHT
		rule.modulate.a = 0.0
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_stack.add_child(rule)

	btn.mouse_entered.connect(_on_menu_btn_hover.bind(inner, lbl, flames, rule, true))
	btn.mouse_exited.connect(_on_menu_btn_hover.bind(inner, lbl, flames, rule, false))
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
		rule: ColorRect, hovering: bool) -> void:
	lbl.add_theme_color_override("font_color", GILT_BRIGHT if hovering else IVORY)
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_a := 1.0 if hovering else 0.0
	for flame in flames:
		tw.tween_property(flame, "modulate:a", target_a, 0.18)
	if rule != null and is_instance_valid(rule):
		tw.tween_property(rule, "modulate:a", 0.88 if hovering else 0.0, 0.18)
	tw.tween_property(inner, "position:x", 12.0 if hovering else 0.0, 0.18)


func _make_button_stylebox(bg: Color, border: Color, corner: int) -> GameTheme.ChartPanelStyle:
	# The chart document kit (chamfered plate, metal rule) — shadow off at rest;
	# hover states flip it on retinted as a gilt glow.
	var s: GameTheme.ChartPanelStyle = GameTheme.make_panel_style(bg, border, 2, corner, false)
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
	var hover := normal.duplicate() as GameTheme.ChartPanelStyle
	hover.bg_color = bg.lightened(0.18)
	hover.border_color = GILT_BRIGHT
	hover.shadow = true
	hover.shadow_size = 10
	hover.shadow_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.35)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as GameTheme.ChartPanelStyle
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
		var act_floor := "Act %d · Province %d" % [int(summary.act), int(summary.floor)]
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
	var sub_lbl := _make_display_label(sub_text, 14, Color(0.74, 0.70, 0.62) if not has_save else Color(0.90, 0.83, 0.62))
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
		var del_hover := del_normal.duplicate() as GameTheme.ChartPanelStyle
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

	var diamond_tex := GameTheme.tex_icon_diamond
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
	var text := "Runs %d  •  Victories %d  •  Defeats %d" % [
		MetaState.total_runs, MetaState.total_victories, MetaState.total_defeats,
	]
	# fastest_victory_floors was tracked from day one but shown nowhere.
	if MetaState.fastest_victory_floors > 0:
		text += "  •  Fastest march %d provinces" % MetaState.fastest_victory_floors
	return text


func _continue_preview_line(slot: int, verbose: bool = false) -> String:
	if slot < 0:
		return "No active march."
	var s := RunState.get_slot_summary(slot)
	if not bool(s.get("has_save", false)):
		return "No active march."
	var asc := ""
	if int(s.get("ascension", 0)) > 0:
		asc = " - Asc %d" % int(s.get("ascension", 0))
	var line := "Act %d, Province %d - HP %d/%d - %dg%s" % [
		int(s.get("act", 1)),
		int(s.get("floor", 0)),
		int(s.get("hp", 0)),
		int(s.get("max_hp", 30)),
		int(s.get("gold", 0)),
		asc,
	]
	return "Resume your saved run: " + line if verbose else line


func _remove_command_dossier() -> void:
	var old := get_node_or_null("CommandDossier")
	if old != null:
		old.queue_free()


func _build_command_dossier(has_any_save: bool) -> void:
	_remove_command_dossier()
	var panel := PanelContainer.new()
	panel.name = "CommandDossier"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 2
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -500.0
	panel.offset_right = -112.0
	panel.offset_top = 170.0
	panel.offset_bottom = 520.0
	var st := GameTheme.make_panel_style(
		Color(0.045, 0.034, 0.027, 0.78),
		Color(0.70, 0.58, 0.35, 0.58),
		1, 6, true)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header.add_child(_dossier_icon("res://assets/icons/game-icons/flying-flag.svg",
		30.0, GILT_BRIGHT))
	var hstack := VBoxContainer.new()
	hstack.add_theme_constant_override("separation", 0)
	header.add_child(hstack)
	var title_text := "CURRENT RUN" if has_any_save else "START HERE"
	var title := _make_display_label(title_text, 26, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hstack.add_child(title)
	var sub_text := "saved progress" if has_any_save else "begin a new campaign"
	var sub := _make_display_label(sub_text, 14,
		Color(0.82, 0.74, 0.58))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hstack.add_child(sub)

	if has_any_save:
		var s := RunState.get_slot_summary(_most_recent_slot())
		root.add_child(_make_dossier_section("CONTINUE",
			"Act %d, Province %d" % [
				int(s.get("act", 1)), int(s.get("floor", 0))],
			Color(0.92, 0.78, 0.46)))
		root.add_child(_make_dossier_section("STATUS",
			"HP %d/%d - Gold %d" % [
				int(s.get("hp", 0)),
				int(s.get("max_hp", 30)),
				int(s.get("gold", 0))],
			Color(0.86, 0.76, 0.58)))
	else:
		root.add_child(_make_dossier_section("NEW MARCH",
			"Choose a hero, build a deck, and fight across 3 acts.",
			Color(0.92, 0.78, 0.46)))
		root.add_child(_make_dossier_section("FIRST STEP",
			"Press NEW MARCH. The next screen explains hero choice.",
			Color(0.86, 0.76, 0.58)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var foot_text := "Press CONTINUE to resume." if has_any_save \
		else "Press NEW MARCH to begin."
	var foot := _make_display_label(foot_text,
		15, Color(0.78, 0.72, 0.60))
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(foot)


func _dossier_icon(path: String, sz: float, tint: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path) as Texture2D
	icon.custom_minimum_size = Vector2(sz, sz)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_dossier_section(title_text: String, body: String, accent: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := GameTheme.make_panel_style(
		Color(0.028, 0.021, 0.016, 0.70),
		Color(accent.r, accent.g, accent.b, 0.40),
		1, 4, false)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", st)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	box.add_child(root)
	var title := _make_display_label(title_text, 14, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(title)
	var lbl := _make_display_label(body, 16, IVORY)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(lbl)
	return box


# ---------------------------------------------------------------------------
# INTERACTIONS
# ---------------------------------------------------------------------------

func _any_save_exists() -> bool:
	for i in range(RunState.SAVE_SLOTS):
		if RunState.has_save(i):
			return true
	return false


func _filled_slot_count() -> int:
	var n := 0
	for i in range(RunState.SAVE_SLOTS):
		if RunState.has_save(i):
			n += 1
	return n


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
	_remove_command_dossier()
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
			"All slots are full — pick one to replace.", 16, Color(0.82, 0.62, 0.55))
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
	_animate_subscreen_reveal(menu)


func _show_hero_select() -> void:
	# Cast-lineup hero pick (StS/Hades pattern): a row of frameless portrait cards
	# over the burning-meadow background. Each card stays down to portrait + name +
	# tagline; hovering a hero spotlights it and fills the shared detail pane below
	# with that hero's lore / loadout / relic. Clicking a card starts the run.
	_remove_command_dossier()
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
	# Fresh setup screen = fresh run options (a stale daily toggle from a
	# previous visit must not silently seed the next run).
	_daily_pick = false
	_daily_btn = null
	_seed_edit = null
	_asc_label = null
	# Master-detail split (StS/Hades pattern): a left roster of the five lords —
	# hover/click to FOCUS, never to commit — beside a war-dossier pane that
	# showcases the focused hero at size: portrait, pitch, the opening deck as
	# real cards, relic, and the run settings living WITH the BEGIN button.
	_center_menu_for_subscreen(1500.0, 850.0)

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 34)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.add_child(main_row)

	# ── Left: the roster ──
	var roster := VBoxContainer.new()
	roster.custom_minimum_size = Vector2(370, 0)
	roster.add_theme_constant_override("separation", 10)
	main_row.add_child(roster)

	var title := _make_display_label("CHOOSE YOUR HERO", 27, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	roster.add_child(title)
	roster.add_child(_make_ornament_row(220.0, true))
	var tgap := Control.new()
	tgap.custom_minimum_size = Vector2(0, 4)
	roster.add_child(tgap)

	for hid in HeroDB.HERO_ORDER:
		roster.add_child(_make_roster_row(hid))

	var rstretch := Control.new()
	rstretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster.add_child(rstretch)

	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 20, 44)
	back.pressed.connect(_rebuild_menu)
	roster.add_child(back)

	# ── Right: the dossier ──
	# Chart kit at whisper volume: soft translucent scrim + faint bronze
	# hairline, so the pane reads as a mounted plate, not a CSS rectangle.
	var detail_frame := PanelContainer.new()
	var detail_bg := GameTheme.make_panel_style(
		Color(0.05, 0.035, 0.045, 0.66), Color(0.60, 0.51, 0.34, 0.38), 1, 6, false)
	detail_bg.content_margin_left = 30
	detail_bg.content_margin_right = 30
	detail_bg.content_margin_top = 22
	detail_bg.content_margin_bottom = 22
	detail_frame.add_theme_stylebox_override("panel", detail_bg)
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_child(detail_frame)

	var dossier := VBoxContainer.new()
	dossier.add_theme_constant_override("separation", 10)
	detail_frame.add_child(dossier)

	_hero_detail = VBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 9)
	_hero_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dossier.add_child(_hero_detail)

	# ── Persistent dossier footer ──
	# The run's "march orders" (ascension / daily / seed) + the primary commit
	# button, grouped WITH the hero they configure. Built ONCE here (never inside
	# _build_hero_detail) so the seed field keeps its text as the spotlight moves,
	# and pinned to the pane's bottom by _hero_detail's vertical expand. This
	# replaces the old orphaned setup row that floated in the dead space below the
	# panes — and the duplicate BACK button that lived down there (the roster keeps
	# the one BACK link).
	_build_dossier_footer(dossier)

	# Default the spotlight to the first hero so the pane is never blank.
	_focus_hero(HeroDB.HERO_ORDER[0])
	_animate_subscreen_reveal(menu)


func _update_asc_rules_text() -> void:
	if _asc_rules_label == null or not is_instance_valid(_asc_rules_label):
		return
	if _selected_ascension <= 0:
		_asc_rules_label.text = "The war as first written — no added rules."
		return
	var lines: Array[String] = []
	for tier in range(1, _selected_ascension + 1):
		if tier < RunState.ASCENSION_RULES.size():
			lines.append(RunState.ASCENSION_RULES[tier])
	_asc_rules_label.text = "\n".join(lines)


## The kingdom's political dye, lifted to a legible-on-dark ink (keeps its hue,
## gains brightness) — used for the focused hero's nameplate accents so each
## lord reads in their faction's colour without leaving the sepia world.
func _faction_accent(hid: String) -> Color:
	var fac := HeroDB.faction_info(HeroDB.get_faction(hid))
	if fac.is_empty():
		return GILT
	var c: Color = fac.get("color", GILT)
	return c.lerp(IVORY, 0.34)


## Persistent footer for the dossier pane: MARCH ORDERS (ascension stepper /
## DAILY MARCH / seed) over the TAKE THE FIELD commit button. Built once so the
## seed LineEdit survives per-focus rebuilds of the detail pane above it.
func _build_dossier_footer(parent: VBoxContainer) -> void:
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	parent.add_child(footer)

	footer.add_child(_make_ornament_row(320.0, true))
	footer.add_child(_make_display_label("MARCH ORDERS", 16, GILT_BRIGHT))

	# One quiet row: ascension stepper (only when a tier is unlocked) · daily
	# toggle · seed field. Left-packed to sit under the left-aligned dossier.
	var setup_row := HBoxContainer.new()
	setup_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	setup_row.add_theme_constant_override("separation", 22)
	footer.add_child(setup_row)

	if MetaState.unlocked_ascension > 0:
		var asc_box := HBoxContainer.new()
		asc_box.alignment = BoxContainer.ALIGNMENT_CENTER
		asc_box.add_theme_constant_override("separation", 10)
		var minus := _make_menu_button("−", Color(0.20, 0.16, 0.14), 18, 36)
		minus.custom_minimum_size = Vector2(40, 36)
		minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		minus.pressed.connect(_change_ascension.bind(-1))
		asc_box.add_child(minus)
		_asc_label = _make_display_label("Ascension %d / %d" % [
			_selected_ascension, MetaState.unlocked_ascension], 16, IVORY)
		_asc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_asc_label.custom_minimum_size = Vector2(168, 36)
		_asc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		asc_box.add_child(_asc_label)
		var plus := _make_menu_button("+", Color(0.20, 0.16, 0.14), 18, 36)
		plus.custom_minimum_size = Vector2(40, 36)
		plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plus.pressed.connect(_change_ascension.bind(1))
		asc_box.add_child(plus)
		setup_row.add_child(asc_box)

	_daily_btn = _make_menu_button("DAILY MARCH: OFF",
		Color(0.30, 0.24, 0.34), 16, 36)
	_daily_btn.custom_minimum_size = Vector2(224, 36)
	_daily_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_daily_btn.tooltip_text = _daily_tooltip()
	_daily_btn.pressed.connect(_toggle_daily_pick)
	setup_row.add_child(_daily_btn)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "seed (optional)"
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_edit.add_theme_font_size_override("font_size", 18)
	_seed_edit.add_theme_color_override("font_color", IVORY)
	_seed_edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.42))
	_seed_edit.custom_minimum_size = Vector2(210, 36)
	_seed_edit.tooltip_text = "Same seed, same map — share one with a friend for a head-to-head march."
	if GameTheme.font_display:
		_seed_edit.add_theme_font_override("font", GameTheme.font_display)
	# Ink-well recess (the NetLobby text-entry convention) — the default OS
	# LineEdit box was the last raw rectangle on the setup screen.
	_seed_edit.add_theme_color_override("caret_color", GILT_BRIGHT)
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.02, 0.015, 0.01, 0.85)
	well.border_color = Color(0.60, 0.51, 0.34, 0.75)
	well.set_border_width_all(1)
	well.set_corner_radius_all(3)
	well.content_margin_left = 10
	well.content_margin_right = 10
	well.content_margin_top = 6
	well.content_margin_bottom = 6
	_seed_edit.add_theme_stylebox_override("normal", well)
	var well_focus := well.duplicate() as StyleBoxFlat
	well_focus.border_color = GILT_BRIGHT
	_seed_edit.add_theme_stylebox_override("focus", well_focus)
	setup_row.add_child(_seed_edit)

	# The ascension RULES readout: the stepper number is meaningless unless the
	# player can see what each tier adds. Cumulative list, dimmed ink, hidden
	# at Ascension 0 and while nothing is unlocked.
	if MetaState.unlocked_ascension > 0:
		_asc_rules_label = _make_display_label("", 15, Color(0.72, 0.64, 0.52))
		_asc_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_asc_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_asc_rules_label.custom_minimum_size = Vector2(560, 0)
		footer.add_child(_asc_rules_label)
		_update_asc_rules_text()

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	footer.add_child(gap)
	footer.add_child(_make_begin_button())


## Primary call-to-action — frameless (no boxy rectangle, per house style): a
## large gilt Cinzel command flanked by flames over a persistent gilt underline
## that brightens on hover. Commits whichever hero is currently spotlighted.
func _make_begin_button() -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())

	var inner := HBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 16)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	var flame_l := _make_flame_accent()
	inner.add_child(flame_l)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(stack)

	var lbl := _make_display_label("TAKE THE FIELD", 27, GILT_BRIGHT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 5)
	stack.add_child(lbl)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(238, 2)
	rule.color = GILT_BRIGHT
	rule.modulate.a = 0.7
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(rule)

	var flame_r := _make_flame_accent()
	inner.add_child(flame_r)

	var flames: Array[TextureRect] = [flame_l, flame_r]
	btn.mouse_entered.connect(func() -> void:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.66))
		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		for f in flames:
			tw.tween_property(f, "modulate:a", 1.0, 0.18)
		tw.tween_property(rule, "modulate:a", 1.0, 0.18)
		tw.tween_property(inner, "position:x", 4.0, 0.18))
	btn.mouse_exited.connect(func() -> void:
		lbl.add_theme_color_override("font_color", GILT_BRIGHT)
		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		for f in flames:
			tw.tween_property(f, "modulate:a", 0.0, 0.18)
		tw.tween_property(rule, "modulate:a", 0.7, 0.18)
		tw.tween_property(inner, "position:x", 0.0, 0.18))
	btn.pressed.connect(func() -> void:
		if _selected_hero != "":
			_begin_run_with(_selected_hero))
	return btn


func _make_roster_row(hid: String) -> Button:
	# Compact hero-list row for the left side of the run setup screen. The old
	# full portrait-card builder still exists below for reference/old layouts, but
	# the current master-detail screen needs five heroes to fit in one column.
	var hero := HeroDB.get_hero(hid)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(350, 92)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 5
	row.offset_bottom = -5
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var port_size := Vector2(62, 82)
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	var portrait: Control = null
	if ResourceLoader.exists(portrait_path):
		var tex := TextureRect.new()
		tex.texture = load(portrait_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.clip_contents = true
		portrait = tex
	else:
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
			Color(0.10, 0.085, 0.11, 0.92),
			Color(GILT.r, GILT.g, GILT.b, 0.45), 1, 4, false))
		var mono := _make_display_label(
			String(hero.get("name", hid)).strip_edges().left(1).to_upper(),
			34, Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.85))
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate.add_child(mono)
		portrait = plate
	portrait.custom_minimum_size = port_size
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	_hero_portraits[hid] = portrait

	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)

	var name_lbl := _make_display_label(String(hero.get("name", hid)), 23, GILT_BRIGHT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	copy.add_child(name_lbl)

	var tag_lbl := _make_display_label(String(hero.get("tagline", "")), 16, Color(1.0, 0.88, 0.62))
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_lbl.custom_minimum_size = Vector2(245, 0)
	copy.add_child(tag_lbl)

	# Hover OR click SELECTS (spotlights) — never commits. Starting the run is the
	# one deliberate act of the TAKE THE FIELD button in the dossier footer, so a
	# player browsing the roster can never trip into a run they didn't mean to.
	btn.mouse_entered.connect(_focus_hero.bind(hid))
	btn.pressed.connect(_focus_hero.bind(hid))
	_hero_cards[hid] = btn
	return btn


func _make_hero_card(hid: String) -> Button:
	# One frameless portrait card. The clickable Button has empty styleboxes in
	# every state (no boxy rectangle); the focus spotlight + gilt underline are
	# applied in _focus_hero. All children are MOUSE_FILTER_IGNORE so hover/click
	# fall through to the Button.
	var hero := HeroDB.get_hero(hid)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(216, 340)
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
	# Box aspect (192/255 = 0.753) is matched to the source art aspect
	# (928×1232 = 0.753) so KEEP_ASPECT_COVERED fills it with ZERO crop — the old
	# 168×210 box shaved ~13px off the top/bottom of every face ("portraits not in
	# frame"). Grown to fill more of the reframed, larger hero-select screen.
	var port_size := Vector2(192, 255)
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	if ResourceLoader.exists(portrait_path):
		var portrait := TextureRect.new()
		portrait.texture = load(portrait_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = port_size
		portrait.clip_contents = true
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Idle portraits stay bright enough to read across a room — the old 0.70
		# wash made all five faces murky. _focus_hero lifts the picked one.
		portrait.modulate = Color(0.88, 0.86, 0.84)
		col.add_child(portrait)
		_hero_portraits[hid] = portrait
	else:
		# No painted portrait yet (e.g. the Kindler) — render an intentional
		# crest plate instead of a bare color block so the card never reads as
		# "broken / missing asset". A framed parchment panel with the hero's
		# monogram + a small "portrait to come" note degrades gracefully and
		# still occupies the exact portrait footprint so the row stays aligned.
		var plate := PanelContainer.new()
		plate.custom_minimum_size = port_size
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pstyle := GameTheme.make_panel_style(
			Color(0.10, 0.085, 0.11, 0.92),
			Color(GILT.r, GILT.g, GILT.b, 0.55), 1, 4, false)
		plate.add_theme_stylebox_override("panel", pstyle)
		var pcol := VBoxContainer.new()
		pcol.alignment = BoxContainer.ALIGNMENT_CENTER
		pcol.add_theme_constant_override("separation", 6)
		pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(pcol)
		var mono := _make_display_label(
			String(hero.get("name", hid)).strip_edges().left(1).to_upper(),
			96, Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.85))
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pcol.add_child(mono)
		var coming := _make_display_label("portrait to come", 15, ASH)
		coming.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pcol.add_child(coming)
		col.add_child(plate)
		plate.modulate = Color(0.88, 0.86, 0.84)
		_hero_portraits[hid] = plate

	var name_lbl := _make_display_label(String(hero.get("name", hid)), 27, GILT_BRIGHT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var tag_lbl := _make_display_label(String(hero.get("tagline", "")), 17, Color(1.0, 0.88, 0.62))
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_lbl.custom_minimum_size = Vector2(192, 0)
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tag_lbl)

	btn.mouse_entered.connect(_focus_hero.bind(hid))
	btn.pressed.connect(_begin_run_with.bind(hid))
	_hero_cards[hid] = btn
	return btn


# Cross-run muster picks (per focused hero; reset when the focus moves so a
# toggle can never leak onto another lord's run).
var _muster_alt_relic := false
var _muster_alt_deck := false


func _focus_hero(hid: String) -> void:
	# Spotlight one hero: brighten its portrait, dim the rest, light its gilt
	# underline, and repaint the shared detail pane. Pane-only update — never
	# rebuilds the cards (which would re-load() portrait textures and flicker).
	if _selected_hero == hid and _hero_detail != null and _hero_detail.get_child_count() > 0:
		return
	_muster_alt_relic = false
	_muster_alt_deck = false
	_selected_hero = hid
	for k in _hero_portraits:
		var p = _hero_portraits[k]
		if is_instance_valid(p):
			p.modulate = Color(1.08, 1.04, 0.98) if k == hid else Color(0.78, 0.76, 0.74)
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
	_hide_deck_preview()
	for c in _hero_detail.get_children():
		c.queue_free()
	var hero := HeroDB.get_hero(hid)

	# Generous wrap width so the now-larger text fills the wide pane instead of
	# rag-wrapping in a narrow column.
	const DETAIL_WRAP := 910.0

	# ── Nameplate: the focused hero at size ──
	# A framed portrait beside the name, tagline, and the KINGDOM this lord rules
	# (Successor Wars identity). Anchors the top of the pane — the old build opened
	# straight into a lore line with no portrait, so ~60% of the pane read as empty
	# void — and carries the per-hero faction colour so each hero feels distinct.
	var accent := _faction_accent(hid)
	var plate := HBoxContainer.new()
	plate.add_theme_constant_override("separation", 22)
	plate.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hero_detail.add_child(plate)

	var port_frame := PanelContainer.new()
	port_frame.custom_minimum_size = Vector2(176, 232)
	port_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	port_frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
		Color(0.08, 0.065, 0.06, 0.90),
		Color(accent.r, accent.g, accent.b, 0.72), 1, 4, false))
	port_frame.clip_contents = true
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	if ResourceLoader.exists(portrait_path):
		var tex := TextureRect.new()
		tex.texture = load(portrait_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.custom_minimum_size = Vector2(174, 230)
		tex.clip_contents = true
		port_frame.add_child(tex)
	else:
		# No painted portrait — a monogram plate keeps the footprint (graceful).
		var mono := _make_display_label(
			String(hero.get("name", hid)).strip_edges().left(1).to_upper(), 92, accent)
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		port_frame.add_child(mono)
	plate.add_child(port_frame)

	var idcol := VBoxContainer.new()
	idcol.add_theme_constant_override("separation", 3)
	idcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.add_child(idcol)

	var name_lbl := _make_display_label(String(hero.get("name", hid)), 42, GILT_BRIGHT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	idcol.add_child(name_lbl)

	var tag_lbl := _make_display_label(String(hero.get("tagline", "")), 20, Color(1.0, 0.88, 0.62))
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	idcol.add_child(tag_lbl)

	# Kingdom band: "The Last Wall  ·  Stone  ·  Formation" under a faction-tinted
	# rule, with the kingdom's one-line engine flavour beneath.
	var fac := HeroDB.faction_info(String(hero.get("faction", "")))
	if not fac.is_empty():
		var ugap := Control.new()
		ugap.custom_minimum_size = Vector2(0, 7)
		idcol.add_child(ugap)
		var underline := ColorRect.new()
		underline.custom_minimum_size = Vector2(300, 2)
		underline.color = Color(accent.r, accent.g, accent.b, 0.85)
		underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idcol.add_child(underline)
		var kgap := Control.new()
		kgap.custom_minimum_size = Vector2(0, 5)
		idcol.add_child(kgap)
		var kingdom := _make_display_label("%s  ·  %s  ·  %s" % [
			String(fac.get("name", "")), String(fac.get("element", "")),
			String(fac.get("engine", ""))], 18, accent)
		kingdom.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		idcol.add_child(kingdom)
		var engine_line := _make_display_label(
			String(fac.get("engine_line", "")), 16, Color(0.78, 0.73, 0.64))
		engine_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		engine_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		engine_line.custom_minimum_size = Vector2(560, 0)
		idcol.add_child(engine_line)

	_hero_detail.add_child(_make_ornament_row(320.0, true))

	var lore := String(hero.get("lore", ""))
	if lore != "":
		var lore_lbl := _make_display_label(lore, 19, Color(0.90, 0.84, 0.96))
		lore_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore_lbl.custom_minimum_size = Vector2(DETAIL_WRAP, 0)
		_hero_detail.add_child(lore_lbl)

	var desc_lbl := _make_display_label(String(hero.get("desc", "")), 18, IVORY)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(DETAIL_WRAP, 0)
	_hero_detail.add_child(desc_lbl)

	_hero_detail.add_child(_make_ornament_row(320.0, true))

	# ── Loadout band: the opening deck as REAL mini cards (left) beside the
	# signature relic (right) — the MP-draft treatment instead of a names-only
	# summary line nobody can picture. Hovering a mini floats the full card.
	# The strip always shows the SELECTED muster (default or unlocked alternate).
	var alt_deck: Dictionary = hero.get("deck_alt", {})
	var deck_unlocked: bool = not alt_deck.is_empty() and MetaState.hero_best_asc(hid) >= 4
	var deck_for_display: Array = hero.get("deck", [])
	if _muster_alt_deck and deck_unlocked:
		deck_for_display = alt_deck.get("deck", deck_for_display)

	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 30)
	band.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hero_detail.add_child(band)

	var deck_col := VBoxContainer.new()
	deck_col.add_theme_constant_override("separation", 5)
	deck_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	band.add_child(deck_col)
	deck_col.add_child(_make_display_label("DECK", 18, GILT_BRIGHT))
	deck_col.add_child(_make_deck_strip(deck_for_display))

	# Muster toggle / locked hint for the alternate deck. Options, not stats:
	# the unlock widens the choice of how this lord starts, never their power.
	if deck_unlocked:
		var std_row := _make_muster_row(
			"The Host of the March — standard muster", not _muster_alt_deck,
			func():
				_muster_alt_deck = false
				_build_hero_detail(hid))
		std_row.custom_minimum_size = Vector2(470.0, 28)
		deck_col.add_child(std_row)
		var alt_row := _make_muster_row(
			"%s — %s" % [String(alt_deck.get("name", "Alternate")),
				String(alt_deck.get("tagline", "alternate muster"))],
			_muster_alt_deck,
			func():
				_muster_alt_deck = true
				_build_hero_detail(hid))
		alt_row.custom_minimum_size = Vector2(470.0, 28)
		deck_col.add_child(alt_row)
	elif not alt_deck.is_empty():
		var deck_lock := _make_display_label(
			"%s — locked. Win a march at Ascension 4 or higher." \
			% String(alt_deck.get("name", "Alternate muster")),
			15, Color(0.62, 0.58, 0.50))
		deck_lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		deck_col.add_child(deck_lock)

	var alt_relic := String(hero.get("relic_alt", ""))
	var relic_unlocked: bool = alt_relic != "" and MetaState.hero_wins(hid) >= 1
	var relic_id := String(hero.get("relic", ""))
	if _muster_alt_relic and relic_unlocked:
		relic_id = alt_relic
	var relic_col := VBoxContainer.new()
	relic_col.add_theme_constant_override("separation", 5)
	relic_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	band.add_child(relic_col)
	if relic_id != "":
		relic_col.add_child(_make_display_label("RELIC", 18, GILT_BRIGHT))
		var relic_row := HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 14)
		relic_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		var chip := GameTheme.make_relic_chip(relic_id, 52)
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		relic_row.add_child(chip)
		var rcol := VBoxContainer.new()
		rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rcol.add_theme_constant_override("separation", 2)
		relic_row.add_child(rcol)
		var rd := RelicDB.get_relic(relic_id)
		var rname := _make_display_label(String(rd.get("name", relic_id)), 19, GILT_BRIGHT)
		rcol.add_child(rname)
		var rdesc := _make_display_label(String(rd.get("desc", "")), 17, IVORY)
		rdesc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rdesc.custom_minimum_size = Vector2(290.0, 0)
		rcol.add_child(rdesc)
		relic_col.add_child(relic_row)

	# Muster toggle / locked hint for the alternate signature relic.
	if relic_unlocked:
		var def_rd := RelicDB.get_relic(String(hero.get("relic", "")))
		var alt_rd := RelicDB.get_relic(alt_relic)
		var sig_row := _make_muster_row(
			"%s — signature" % String(def_rd.get("name", "Signature relic")),
			not _muster_alt_relic,
			func():
				_muster_alt_relic = false
				_build_hero_detail(hid))
		sig_row.custom_minimum_size = Vector2(356.0, 28)
		relic_col.add_child(sig_row)
		var vet_row := _make_muster_row(
			"%s — the veteran's pick" % String(alt_rd.get("name", "Alternate relic")),
			_muster_alt_relic,
			func():
				_muster_alt_relic = true
				_build_hero_detail(hid))
		vet_row.custom_minimum_size = Vector2(356.0, 28)
		relic_col.add_child(vet_row)
	elif alt_relic != "":
		var relic_lock := _make_display_label(
			"Alternate signature relic — locked. Win a march with this lord.",
			15, Color(0.62, 0.58, 0.50))
		relic_lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		relic_lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		relic_lock.custom_minimum_size = Vector2(356.0, 0)
		relic_col.add_child(relic_lock)

	# Campaign ledger line — this hero's record across all runs. Quiet ink;
	# absent entirely until the hero has marched at least once.
	var hs: Dictionary = MetaState.hero_stats.get(hid, {})
	var wins: int = int(hs.get("wins", 0))
	var losses: int = int(hs.get("losses", 0))
	if wins + losses > 0:
		var ledger_text := "Campaigns: %d won · %d lost" % [wins, losses]
		var best: int = int(hs.get("best_asc", -1))
		if best > 0:
			ledger_text += " · highest victory at Ascension %d" % best
		var ledger := _make_display_label(ledger_text, 16, Color(0.76, 0.70, 0.56))
		ledger.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hero_detail.add_child(ledger)
	# (No "click a hero to begin" hint here anymore — the commit is the explicit
	# TAKE THE FIELD button in the persistent dossier footer below.)


# A selectable single-line option in the hero detail pane (muster picks).
# Frameless — the selected row reads gilt with a "▸" pip, the other sits dim.
func _make_muster_row(text: String, selected: bool, on_pick: Callable) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	btn.custom_minimum_size = Vector2(910.0, 28)
	var lbl := _make_display_label(
		("★ " if selected else "·  ") + text, 16,
		GILT_BRIGHT if selected else Color(0.78, 0.74, 0.66))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	btn.pressed.connect(on_pick)
	return btn


# ── Deck strip (hero select): the opening ten as REAL cards ─────────────────
const DECK_MINI_SCALE := 0.36

## The hero's opening deck as a row of mini Card2D nodes — one per unique card,
## first-seen order preserved (the deck leads with its heaviest cards), each
## wearing a ×N count chip. Hovering a mini floats a full-size readable copy.
func _make_deck_strip(deck: Array) -> Control:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in deck:
		var id: String = String(cid)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += 1
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	strip.alignment = BoxContainer.ALIGNMENT_BEGIN
	# Any route off this pane (rebuild, screen change) kills a live hover preview.
	strip.tree_exiting.connect(_hide_deck_preview)
	for id in order:
		strip.add_child(_make_deck_mini(id, int(counts[id])))
	return strip


func _make_deck_mini(id: String, count: int) -> Control:
	var w: float = 225.0 * DECK_MINI_SCALE
	var h: float = 300.0 * DECK_MINI_SCALE
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(w, h)
	var card = CARD_SCENE.instantiate()
	card.card_data = CardDB.get_card_data(id).duplicate(true)
	card.card_id = id
	card.is_on_battlefield = true   # static display — no hand-drag behaviour
	card.live_baked_mode = true
	CardTextureCache.bake(card.card_data)
	card.scale = Vector2(DECK_MINI_SCALE, DECK_MINI_SCALE)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	# ×N count chip on the mini's top-right corner — the chip is what makes
	# "five minis" read as "ten cards".
	var chip := _make_display_label("×%d" % count, 15, GILT_BRIGHT)
	chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	chip.add_theme_constant_override("outline_size", 6)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(chip)
	chip.size = Vector2(34, 20)
	chip.position = Vector2(w - 30.0, -6.0)
	# Topmost transparent catcher — Card2D's inner panels would otherwise eat
	# the hover, so the slot itself never sees mouse_entered.
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.add_child(catcher)
	catcher.mouse_entered.connect(_show_deck_preview.bind(id, slot))
	catcher.mouse_exited.connect(_hide_deck_preview)
	return slot


## Float a full-size copy of the hovered deck mini above the strip (NetDraft's
## ledger-preview behaviour). Mouse-transparent so it never eats a click.
func _show_deck_preview(id: String, anchor: Control) -> void:
	_hide_deck_preview()
	var card = CARD_SCENE.instantiate()
	card.card_data = CardDB.get_card_data(id).duplicate(true)
	card.card_id = id
	card.is_on_battlefield = true
	card.live_baked_mode = true
	CardTextureCache.bake(card.card_data)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 140
	add_child(card)
	var r := anchor.get_global_rect()
	var vp := get_viewport_rect().size
	var pos := Vector2(r.get_center().x - 112.5, r.position.y - 312.0)
	pos.x = clampf(pos.x, 8.0, vp.x - 233.0)
	pos.y = clampf(pos.y, 8.0, vp.y - 308.0)
	card.global_position = pos
	_deck_preview = card


func _hide_deck_preview() -> void:
	if _deck_preview != null and is_instance_valid(_deck_preview):
		_deck_preview.queue_free()
	_deck_preview = null


func _begin_run_with(hero_id: String) -> void:
	# Seed comes from the setup row on the hero-select screen: DAILY MARCH
	# locks today's deterministic seed (same map for everyone), a typed seed
	# hashes to a custom one, otherwise 0 = roll fresh.
	var seed_to_use := 0
	if _daily_pick:
		seed_to_use = RunState.daily_seed()
	elif _seed_edit != null and is_instance_valid(_seed_edit):
		var s: String = _seed_edit.text.strip_edges().to_lower()
		if s != "":
			seed_to_use = RunState.seed_from_string(s)
	# Cross-run muster picks — handed to start_new_run via the pending fields
	# (consumed and cleared there). Unlocks re-checked so a stale toggle can
	# never smuggle a locked option into the run.
	var hero_data := HeroDB.get_hero(hero_id)
	RunState.pending_signature_relic = ""
	RunState.pending_deck_variant = ""
	if _muster_alt_relic and MetaState.hero_wins(hero_id) >= 1:
		RunState.pending_signature_relic = String(hero_data.get("relic_alt", ""))
	if _muster_alt_deck and MetaState.hero_best_asc(hero_id) >= 4 \
			and hero_data.has("deck_alt"):
		RunState.pending_deck_variant = "alt"
	RunState.start_new_run(hero_id, _selected_ascension, seed_to_use)
	# Daily March: arm today's omen (run-wide mutator) and stamp the ledger —
	# start_new_run just reset both flags, so this must come after it.
	if _daily_pick:
		RunState.is_daily_run = true
		RunState.daily_mutator_id = RunState.daily_mutator_id_for_today()
		MetaState.record_daily_start(hero_id)
	# After the hero is locked in, offer the run's opening provisioning — 3
	# safe tiles (one per reward family) + 1 risky tile (real cost, bigger
	# payoff). Skipping is allowed and routes straight to the map.
	_show_blessing_select()


func _change_ascension(delta: int) -> void:
	# Lives on the run-setup (hero select) row now — update the label in place
	# instead of rebuilding the screen (a rebuild would reload every portrait).
	_selected_ascension = clampi(_selected_ascension + delta, 0, MetaState.unlocked_ascension)
	if _asc_label != null and is_instance_valid(_asc_label):
		_asc_label.text = "Ascension %d / %d" % [
			_selected_ascension, MetaState.unlocked_ascension]
	_update_asc_rules_text()


func _toggle_daily_pick() -> void:
	# DAILY MARCH locks the run to today's deterministic seed; the free-seed
	# field goes quiet while it's on (the two would fight over the same roll).
	_daily_pick = not _daily_pick
	if _seed_edit != null and is_instance_valid(_seed_edit):
		_seed_edit.editable = not _daily_pick
		_seed_edit.modulate = Color(1, 1, 1, 0.45 if _daily_pick else 1.0)
		if _daily_pick:
			_seed_edit.text = ""
	if _daily_btn != null and is_instance_valid(_daily_btn):
		var lbl := _menu_button_label(_daily_btn)
		if lbl != null:
			lbl.text = "DAILY MARCH: ON" if _daily_pick else "DAILY MARCH: OFF"


func _daily_tooltip() -> String:
	# Today's seed + today's omen + whether the player already marched. The
	# daily is a MODE now, not just a locked seed — the tooltip is where its
	# identity lives without widening the quiet setup row.
	var text := "Today's seed — everyone who marches today walks the same map."
	var omen_id: String = RunState.daily_mutator_id_for_today()
	var omen: Dictionary = MutatorDB.get_mutator(omen_id)
	if not omen.is_empty():
		text += "\nToday's omen: %s — %s" % [
			String(omen.get("name", omen_id)), String(omen.get("desc", ""))]
	var today: Dictionary = MetaState.todays_daily()
	if not today.is_empty():
		match String(today.get("result", "")):
			"won":
				text += "\nYou marched today and WON (%s)." % String(today.get("hero", ""))
			"lost":
				text += "\nYou marched today and fell (%s)." % String(today.get("hero", ""))
			_:
				text += "\nA march is already underway today (%s)." % String(today.get("hero", ""))
	return text


func _menu_button_label(btn: Button) -> Label:
	# _make_menu_button nests its Label inside an HBox (the Button's own .text
	# stays empty by design) — dig it out for in-place text swaps.
	for c in btn.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Label:
					return cc
	return null


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
# HOW TO PLAY / GLOSSARY OVERLAY
# ---------------------------------------------------------------------------
# A self-contained reference reachable from the main menu (and mirrored on the
# map HUD). Two columns on one parchment sheet: a hand-written "How the
# campaign works" primer on the left, and the full keyword glossary on the
# right — sourced live from KeywordEffects.KEYWORDS so it never drifts from the
# real rules. Built programmatically in the chart aesthetic (dark ink panels,
# gilt headers) and torn down on close; the menu/atmosphere persist behind it.

func _show_how_to_play() -> void:
	# One overlay at a time — re-pressing the button shouldn't stack scrims.
	var existing := get_node_or_null("HowToPlayOverlay")
	if existing != null:
		existing.queue_free()
	add_child(GameTheme.make_how_to_play_overlay())


# (The HowToPlayOverlay class was removed — both this screen and MapView now call
# the single shared builder GameTheme.make_how_to_play_overlay(), so the primer
# copy can no longer drift between the two.)


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
	var dossier := get_node_or_null("CommandDossier")
	if dossier != null:
		dossier.modulate.a = 0.0
		tw.tween_property(dossier, "modulate:a", 1.0, 0.55).set_delay(0.18)


func _animate_subscreen_reveal(menu: Control) -> void:
	if menu == null:
		return
	for child in menu.get_children():
		child.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	var delay := 0.0
	for child in menu.get_children():
		tw.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(delay)
		delay += 0.045


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
# THE WAR CHEST (opening provisioning)
# ---------------------------------------------------------------------------
# After the hero is picked, the player gets a single opening requisition: 3
# "safe" tiles drawn from the seven reward families (gold, heal, max HP, free
# relic, free potion, free card, free upgrade) plus 1 "risky" tile with a real
# cost and a bigger payoff. SKIP is always available — the run can start cold
# if the player wants the full StS opening. Framed as the campaign's war
# chest so the run opener speaks the same Successor Wars register as the map.
#
# The card-touching entries (Whetstone sharpen, Butcher's Kindness, Remount
# trades, Muster Tent recruit, Hollow Levy removals) open pick-a-card grids
# instead of hitting a random card — the rest of the game sets an agency
# standard (forge previews, chosen sacrifices) that a random permanent mod
# on screen one was violating.
#
# This is built in MainMenu (rather than a dedicated scene) so it reuses the
# atmosphere/parallax already running behind the menu and shares the hero-
# pick sub-screen pattern (replace the Menu VBox in place, no scene change).

func _show_blessing_select() -> void:
	_remove_command_dossier()
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

	var title := _make_display_label("THE WAR CHEST", 38, GILT_BRIGHT)
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
		"Every march is provisioned before it moves. Three gifts are honest — one asks a price.",
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

	var skip := _make_menu_button("SKIP — MARCH UNPROVISIONED",
		Color(0.22, 0.16, 0.14), 16, 40)
	skip.name = "BlessingSkip"
	skip.pressed.connect(_skip_blessing)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skip.offset_left = COLUMN_LEFT
	skip.offset_right = COLUMN_LEFT + 360
	skip.offset_top = -82
	skip.offset_bottom = -36
	add_child(skip)


# Roll the displayed tiles: 3 distinct honest entries + 1 priced entry.
# Remade 2026-07-03: the old pool was flat handouts, and two of them (Heal 12 /
# full heal) were DEAD at run start — the march begins at full HP. Every honest
# entry now aims at a run SHAPE (economy / deck quality / bottle-craft / body),
# and every priced entry is a real pact, so the first decision of the run is a
# direction, not a coin pickup.
func _roll_blessings() -> Array:
	var honest_pool: Array[String] = [
		"gold", "upgrade", "transform2", "recruit", "max_hp", "potions", "relic",
	]
	honest_pool.shuffle()
	var picked_honest := honest_pool.slice(0, 3)

	var priced_pool: Array[String] = [
		"black_ledger", "widows_coin", "butchers_kindness", "hollow_levy",
	]
	var picked_priced: String = priced_pool[randi() % priced_pool.size()]

	var entries: Array = []
	for id in picked_honest:
		entries.append(_blessing_entry(id, false))
	entries.append(_blessing_entry(picked_priced, true))
	# Shuffle so the priced tile isn't always the last cell.
	entries.shuffle()
	return entries


func _blessing_entry(id: String, risky: bool) -> Dictionary:
	# Centralised description / tint per blessing. Effects are applied in
	# _apply_blessing (or routed to a picker in _pick_blessing) — keeping
	# render data and effect logic separate so a typo in copy can't
	# accidentally double-pay the player.
	var safe_color := Color(0.18, 0.30, 0.20)   # green-leaning for "honest"
	var risk_color := Color(0.36, 0.18, 0.22)   # deep wine for "priced"
	var color: Color = risk_color if risky else safe_color
	var data := {"id": id, "risky": risky, "color": color}
	match id:
		# ── Honest ──
		"gold":
			data["name"] = "The Paymaster's Advance"
			data["desc"] = "Gain 75 gold."
		"upgrade":
			data["name"] = "The Whetstone Cart"
			data["desc"] = "Choose 1 card. Forge its + version."
		"transform2":
			data["name"] = "The Remount Line"
			data["desc"] = "Choose 2 cards. Each becomes a random card of the same rarity."
		"recruit":
			data["name"] = "The Muster Tent"
			data["desc"] = "Pick 1 of 3 uncommon cards for your deck."
		"max_hp":
			data["name"] = "The Iron Ration"
			data["desc"] = "Gain +7 max HP."
		"potions":
			data["name"] = "The Vivandière's Crate"
			data["desc"] = "Gain 2 random potions."
		"relic":
			data["name"] = "The Vanguard's Trinket"
			data["desc"] = "Gain a random combat relic."
		# ── Priced ──
		"black_ledger":
			data["name"] = "The Black Ledger"
			data["desc"] = "Gain a boss relic. Add 2 Curses to your deck."
		"widows_coin":
			data["name"] = "The Widow's Coin"
			data["desc"] = "Gain 150 gold. Lose 6 max HP."
		"butchers_kindness":
			data["name"] = "The Butcher's Kindness"
			data["desc"] = "Choose 1 creature. It permanently gains +2 ATK and Wither 1."
		"hollow_levy":
			data["name"] = "The Hollow Levy"
			data["desc"] = "Remove 2 chosen cards. Add 1 Curse to your deck."
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
	var diamond_tex := GameTheme.tex_icon_diamond
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
		chip.add_theme_font_size_override("font_size", 16)
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
	body.add_theme_font_size_override("font_size", 18)
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
	var id := String(entry.get("id", ""))
	# The card-touching blessings open a pick-a-card grid — the tile names
	# the effect, the player names the card. Everything else applies and goes.
	match id:
		"upgrade":
			var candidates := _blessing_upgrade_candidates()
			if candidates.is_empty():
				GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
				return
			_show_blessing_card_picker("Sharpen which card?", candidates,
				func(i: int):
					RunState.upgrade_card(i, "plus")
					GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45))
			return
		"butchers_kindness":
			var creatures := _blessing_creature_candidates()
			if creatures.is_empty():
				GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
				return
			_show_blessing_card_picker("Feed which creature?  (+2 ATK, Wither 1)",
				creatures,
				func(i: int):
					RunState.upgrade_card(i, "butcher")
					GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45))
			return
		"transform2":
			_blessing_transform_step(2)
			return
		"recruit":
			var pool: Array = CardDB.cards_of_rarity("uncommon")
			pool.shuffle()
			var offered: Array = pool.slice(0, mini(3, pool.size()))
			if offered.is_empty():
				GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
				return
			_show_blessing_offer_picker("Enlist which recruit?", offered,
				func(cid: String):
					RunState.add_card(cid)
					GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45))
			return
		"hollow_levy":
			# The Curse lands first (the cost is signed before the muster), then
			# the player picks the 2 leavers.
			RunState.add_card(CardDB.random_curse_id())
			_blessing_remove_step(2)
			return
	_apply_blessing(id)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)


# Sequential pickers for the multi-step blessings. Each step rebuilds the
# grid from the LIVE deck (indices shift after a removal), and each bottoms
# out on the map transition so the run can never strand on an empty grid.

func _blessing_transform_step(remaining: int) -> void:
	var eligible: Array = []
	for i in RunState.deck.size():
		if not CardDB.is_curse(RunState.deck[i]):
			eligible.append(i)
	if remaining <= 0 or eligible.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var suffix: String = "  (%d left)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("Trade in which card?" + suffix, eligible,
		func(i: int):
			_blessing_transform_at(i)
			_blessing_transform_step(remaining - 1))


# Same transform rule as the in-run Remount Fair (Event.gd): starters and
# enemy-rarity cards hatch into commons, everything else keeps its weight
# class, and the roll never returns the same card.
func _blessing_transform_at(deck_index: int) -> void:
	var old_id: String = RunState.deck[deck_index]
	var rarity: String = String(CardDB.get_card_data(old_id).get("rarity", "common"))
	if rarity == "starter" or rarity == "enemy":
		rarity = "common"
	var pool: Array = CardDB.cards_of_rarity(rarity)
	pool.erase(old_id)
	if pool.is_empty():
		pool = CardDB.cards_of_rarity("common")
		pool.erase(old_id)
	RunState.remove_card_at(deck_index)
	RunState.add_card(pool[randi() % pool.size()])


func _blessing_remove_step(remaining: int) -> void:
	if remaining <= 0 or RunState.deck.size() <= 1:
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var all_idx: Array = []
	for i in RunState.deck.size():
		all_idx.append(i)
	var suffix: String = "  (%d left)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("Muster out which card?" + suffix, all_idx,
		func(i: int):
			RunState.remove_card_at(i)
			_blessing_remove_step(remaining - 1))


func _skip_blessing() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)


func _blessing_upgrade_candidates() -> Array:
	var out: Array = []
	for i in RunState.deck.size():
		if RunState.has_upgrade_path(i, "plus"):
			continue
		if CardDB.is_upgradeable(RunState.deck[i]):
			out.append(i)
	return out


func _blessing_creature_candidates() -> Array:
	var out: Array = []
	for i in RunState.deck.size():
		if CardDB.get_card_data(RunState.deck[i]).get("type", "") == "creature":
			out.append(i)
	return out


const CARD_SCENE_PICKER = preload("res://scenes/card_2d.tscn")

func _show_blessing_card_picker(title_text: String, indices: Array,
		on_pick: Callable) -> void:
	# Full-screen card grid over the menu background — the run-start deck is
	# 10 cards, so this is two rows of five. Same wrapper-plus-transparent-
	# button pattern as the in-run pickers (Event/Rest), so click semantics
	# match everywhere the player picks a card.
	for child in get_children():
		var cname: String = child.name
		if cname in ["Background", "Atmosphere", "Menu"]:
			continue
		child.queue_free()

	var title := _make_display_label(title_text, 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 88
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll.offset_left = 150
	scroll.offset_right = -150
	scroll.offset_top = 110
	scroll.offset_bottom = 800
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	for i in indices:
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		var card_node = CARD_SCENE_PICKER.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		CardTextureCache.bake(data)
		wrapper.add_child(card_node)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(on_pick.bind(int(i)))
		wrapper.add_child(click_btn)
		grid.add_child(wrapper)


# The Muster Tent variant: pick from OFFERED card ids (cards not yet in the
# deck), where _show_blessing_card_picker picks from live deck indices. Same
# grid, same click semantics; the callback receives the card id string.
func _show_blessing_offer_picker(title_text: String, ids: Array,
		on_pick: Callable) -> void:
	for child in get_children():
		var cname: String = child.name
		if cname in ["Background", "Atmosphere", "Menu"]:
			continue
		child.queue_free()

	var title := _make_display_label(title_text, 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 88
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	add_child(title)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	var total_w: int = ids.size() * 225 + (ids.size() - 1) * 40
	row.offset_left = -total_w / 2
	row.offset_right = total_w / 2
	row.offset_top = -150
	row.offset_bottom = 150
	row.add_theme_constant_override("separation", 40)
	add_child(row)

	for cid in ids:
		var data: Dictionary = CardDB.get_card_data(String(cid))
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		var card_node = CARD_SCENE_PICKER.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		CardTextureCache.bake(data)
		wrapper.add_child(card_node)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(on_pick.bind(String(cid)))
		wrapper.add_child(click_btn)
		row.add_child(wrapper)


# Applies the picked blessing's mutation to RunState. Effects sample from the
# live DBs (relics/potions/cards/upgrades) at apply time so the tile copy
# stays evergreen — and so the player can't peek at the exact roll. Every
# branch is intentionally self-contained: no shared "reward bundle" helper,
# because the families don't actually overlap (a card add doesn't compose
# with a relic add for this screen) and inlining is easier to audit.
# ("upgrade", "butchers_kindness", "transform2", "recruit" and "hollow_levy"
# never reach here — _pick_blessing routes them through pickers.)
func _apply_blessing(id: String) -> void:
	match id:
		# ── Honest ──
		"gold":
			RunState.gain_gold(75)
		"max_hp":
			# The march starts at full HP, so the raise carries the heal with it.
			RunState.hero_max_hp += 7
			RunState.hero_hp += 7
		"relic":
			var pool: Array[String] = RelicDB.roll_relic_reward(
				"combat", RunState.relics, RunState.current_hero_id)
			if not pool.is_empty():
				RunState.add_relic(pool[0])
		"potions":
			for _i in 2:
				if RunState.can_add_potion():
					RunState.add_potion(PotionDB.roll_random_potion())
		# ── Priced ──
		"black_ledger":
			# Roll a rare relic from the boss pool — these are the strongest
			# in the game, justifying the Curse tax. Two Curses, not three,
			# because this fires on round 1 with a fresh deck (no upgrades to
			# soak the dilution yet).
			var bosses: Array[String] = RelicDB.roll_boss_relics(
				RunState.relics, RunState.current_hero_id)
			if not bosses.is_empty():
				RunState.add_relic(bosses[0])
			for _i in 2:
				RunState.add_card(CardDB.random_curse_id())
		"widows_coin":
			RunState.gain_gold(150)
			RunState.hero_max_hp = maxi(1, RunState.hero_max_hp - 6)
			RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)
