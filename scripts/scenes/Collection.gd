extends Control
## Collection.gd — the compendium: every card, relic, and potion in the game,
## browsable from the main menu (the Slay-the-Spire model). Four tabs:
##   CARDS   — real Card2D instances baked through the shared CardTextureCache
##             (pixel-identical to a card in hand; hover pops the detail panel).
##   RELICS  — every relic as a readable plaque (the run-HUD chip + name +
##             effect text laid out in the open, nothing hidden behind hover),
##             sectioned by tier with the tier halo as the quality cue.
##   POTIONS — same plaque pattern off PotionDB.
##   HISTORY — every finished run, newest first, read back out of the CSV
##             RunState has been writing since long before anything read it
##             (RunState.read_run_history). The only tab whose contents are the
##             PLAYER's, not the game's, so it is the only one with a real
##             empty state rather than a "this should never happen" one.
## `show_tab(name)` is public so screenshot probes can open a specific tab.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const MENU_SCENE = "res://scenes/main_menu.tscn"

const SECTIONS = [
	{"label": "Starter Creatures", "rarity": "starter", "type": "creature"},
	{"label": "Common Creatures", "rarity": "common", "type": "creature"},
	{"label": "Uncommon Creatures", "rarity": "uncommon", "type": "creature"},
	{"label": "Rare Creatures", "rarity": "rare", "type": "creature"},
	{"label": "Starter Spells", "rarity": "starter", "type": "spell"},
	{"label": "Common Spells", "rarity": "common", "type": "spell"},
	{"label": "Uncommon Spells", "rarity": "uncommon", "type": "spell"},
	{"label": "Rare Spells", "rarity": "rare", "type": "spell"},
	{"label": "Common Armaments", "rarity": "common", "type": "armament"},
	{"label": "Uncommon Armaments", "rarity": "uncommon", "type": "armament"},
	{"label": "Rare Armaments", "rarity": "rare", "type": "armament"},
]

const RELIC_TIERS = [
	{"label": "Signature Relics", "tier": "starting"},
	{"label": "Combat Relics", "tier": "combat"},
	{"label": "Utility Relics", "tier": "utility"},
	{"label": "Boss Relics", "tier": "boss"},
	# Event relics are never rolled into reward pools — they're granted by
	# name from specific events. Without this section they were invisible in
	# the compendium (The Coin, Landed / A Verse of You / Warm Knucklebone /
	# The Sin-Eater's Crust).
	{"label": "Event Relics", "tier": "event"},
]

const TABS = [
	{"id": "cards", "label": "CARDS"},
	{"id": "relics", "label": "RELICS"},
	{"id": "potions", "label": "POTIONS"},
	{"id": "history", "label": "RUN HISTORY"},
]

## Month abbreviations for the run-history stamp. Three letters, English, and
## deliberately hand-rolled: the alternative is dragging a locale library in to
## render a date the game itself wrote two lines of ASCII ago.
const MONTH_ABBR: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

## Row dress per outcome. The WORD does the work — the colour only agrees with
## it (COPY_STYLE §11: colour is never the only channel).
const HISTORY_OUTCOMES := {
	"victory": {"label": "VICTORY", "color": Color(0.98, 0.84, 0.42)},
	"defeat": {"label": "DEFEAT", "color": Color(0.90, 0.42, 0.34)},
	"abandoned": {"label": "ABANDONED", "color": Color(0.66, 0.63, 0.58)},
}

## How many relic names a row prints before it counts the rest.
const HISTORY_RELIC_NAMES_SHOWN: int = 4

const CARD_TILE_SIZE := Vector2(225, 300)
# Indexing still creates every fixed-size slot so the scrollbar is truthful,
# but the ornate ghosts/plaques are non-trivial to construct. At 36 per frame,
# Cards first-presented in 280 ms and both Cards/Relics had ~110 ms settle
# frames; 12 measured at 31 ms first-present and 53/13 ms settle respectively,
# with identical nodes once hydration finishes.
const CARD_PLACEHOLDER_YIELD_EVERY := 12
const CARD_HYDRATE_YIELD_EVERY := 4
const CARD_VIRTUAL_REFRESH := 0.10
const CARD_WARM_MARGIN_SCREENS := 0.35
const CARD_COLD_MARGIN_SCREENS := 0.85
const RELIC_PLACEHOLDER_YIELD_EVERY := 12
const RELIC_HYDRATE_YIELD_EVERY := 2
const RELIC_WARM_MARGIN_SCREENS := 0.35
const RELIC_COLD_MARGIN_SCREENS := 0.85

## One CanvasItem stands in for an unhydrated card. The previous ghost was a
## miniature Control tree (panels, labels and seals) repeated for every card in
## the compendium; even offscreen children still participated in layout and
## invalidation. This paints the same card-shaped hierarchy in one node.
class CollectionCardGhost extends Control:
	var title_text: String = ""
	var rule_lines: Array[String] = []
	var command_cost: int = 0
	var attack: int = 0
	var health: int = 0
	var spell: bool = false
	var accent: Color = Color(0.68, 0.58, 0.38)
	var sheet: Color = Color(0.20, 0.17, 0.13)
	var display_font: Font = null
	var body_font: Font = null


	func configure(card_data: Dictionary, title_font: Font, rules_font: Font,
			rarity_accent: Color, sheet_color: Color) -> void:
		title_text = String(card_data.get(
			"name", card_data.get("id", "")))
		if title_text.length() > 25:
			title_text = title_text.left(24) + "..."
		rule_lines = _wrap_rules(String(card_data.get("desc", "")))
		command_cost = int(card_data.get("cost", 0))
		attack = int(card_data.get("atk", 0))
		health = int(card_data.get("hp", 0))
		spell = String(card_data.get("type", "")) == "spell"
		accent = rarity_accent
		sheet = sheet_color
		display_font = title_font
		body_font = rules_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		queue_redraw()


	func _wrap_rules(text: String) -> Array[String]:
		var lines: Array[String] = []
		var words: PackedStringArray = text.replace("\n", " ").split(" ", false)
		var current: String = ""
		var clipped: bool = false
		for raw_word in words:
			var word: String = String(raw_word)
			var candidate: String = word if current == "" else current + " " + word
			if candidate.length() <= 27:
				current = candidate
				continue
			if current != "":
				lines.append(current)
			if lines.size() >= 3:
				clipped = true
				break
			current = word
		if current != "" and lines.size() < 3:
			lines.append(current)
		elif current != "":
			clipped = true
		if clipped and not lines.is_empty():
			var last: int = lines.size() - 1
			lines[last] = lines[last].left(24).trim_suffix(".") + "..."
		return lines


	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 1.0 or h <= 1.0:
			return
		var cut: float = 12.0
		var card_poly := PackedVector2Array([
			Vector2(cut, 1), Vector2(w - cut, 1),
			Vector2(w - 1, cut), Vector2(w - 1, h - cut),
			Vector2(w - cut, h - 1), Vector2(cut, h - 1),
			Vector2(1, h - cut), Vector2(1, cut),
		])
		draw_colored_polygon(card_poly, sheet)
		var closed := PackedVector2Array(card_poly)
		closed.append(card_poly[0])
		draw_polyline(closed, Color(accent.r, accent.g, accent.b, 0.60),
			2.0, true)

		var ink := Color(0.10, 0.078, 0.058, 1.0)
		var well := Color(0.34, 0.27, 0.19, 0.92)
		draw_rect(Rect2(11, 12, w - 22, 134), ink.lightened(0.05))
		draw_rect(Rect2(11, 12, w - 22, 134),
			Color(accent.r, accent.g, accent.b, 0.34), false, 1.0)
		draw_rect(Rect2(11, 150, w - 22, 30), ink)
		draw_rect(Rect2(13, 184, w - 26, 78), well)

		draw_circle(Vector2(23, 20), 18.0, Color(0.16, 0.24, 0.42))
		if display_font != null:
			draw_string(display_font, Vector2(4, 27), str(command_cost),
				HORIZONTAL_ALIGNMENT_CENTER, 38, 17, Color(0.96, 0.92, 0.78))
			draw_string(display_font, Vector2(16, 173), title_text,
				HORIZONTAL_ALIGNMENT_CENTER, w - 32, 16, Color(0.91, 0.71, 0.28))
		if body_font != null:
			for i in range(rule_lines.size()):
				draw_string(body_font, Vector2(20, 207 + float(i) * 18.0),
					rule_lines[i], HORIZONTAL_ALIGNMENT_CENTER, w - 40, 14,
					Color(0.20, 0.15, 0.10, 0.92))

		if spell:
			if display_font != null:
				draw_string(display_font, Vector2(14, 286), "SPELL",
					HORIZONTAL_ALIGNMENT_CENTER, w - 28, 14,
					Color(0.62, 0.54, 0.42, 0.95))
			return
		draw_circle(Vector2(24, h - 24), 18.0, Color(0.42, 0.33, 0.12))
		draw_circle(Vector2(w - 24, h - 24), 18.0, Color(0.44, 0.14, 0.12))
		if display_font != null:
			draw_string(display_font, Vector2(5, h - 17), str(attack),
				HORIZONTAL_ALIGNMENT_CENTER, 38, 17, Color(0.96, 0.92, 0.78))
			draw_string(display_font, Vector2(w - 43, h - 17), str(health),
				HORIZONTAL_ALIGNMENT_CENTER, 38, 17, Color(0.96, 0.92, 0.78))

var _scroll: ScrollContainer
var _content: VBoxContainer
var _plate: PanelContainer
var _loading_overlay: Control = null
var _collection_swap_tween: Tween = null
var _tab_buttons: Dictionary = {}
var _current_tab: String = ""
# Bumped on every tab switch; the async card bake loop checks it after each
# await so switching tabs mid-bake abandons the stale build cleanly.
var _view_gen: int = 0
var _card_jobs: Array[Dictionary] = []
var _card_hydration_gen: int = -1
var _card_virtual_accum := 0.0
var _card_refresh_queued := false
var _relic_jobs: Array[Dictionary] = []
var _relic_hydration_gen: int = -1
var _relic_refresh_queued := false
## One-way latch on the way out — see _leave_to_menu.
var _leaving := false
var _plaque_shader: Shader = null
var _plaque_materials: Dictionary = {}


func _ready() -> void:
	# Lift the crushed backdrop. Two crushers were stacking (the same pair the
	# GameOver page had): the .tscn pins Background.self_modulate to ~0.14
	# brightness, and the "event" mood lays a heavy vignette over that. The
	# result was a near-black void — there is a painted library back there
	# (collection_library.png) and nobody had ever seen it. The trophy room
	# gets a room. Kept well under the cards' own brightness so the collection
	# still reads as the subject.
	var bg := get_node_or_null("Background")
	if bg != null:
		bg.self_modulate = Color(0.40, 0.38, 0.42, 1.0)
	GameTheme.add_atmosphere(self, "event", true, {
		"vignette": 0.42,
		"grad_outer": Color(0.02, 0.015, 0.03, 0.46),
	})

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Left margin bumped 40→80 so the settings gear (top-left, ~62px wide) has
	# room without colliding with the section labels.
	#
	# ── AND THEN BALANCED, 80/40 → 60/60 (2026-09-03) ──
	# Clearing the gear is a real constraint; paying for it out of ONE side is
	# not. An 80/40 split put the whole page — title, tab row and card plate —
	# 20px right of the canvas it sits on, which is a page-wide lean rather than
	# a margin. 60/60 still clears the gear (which ends at x=62 and, at 60, only
	# ever shares a row with the header's invisible spacer) and preserves the
	# content width EXACTLY: 1600-80-40 and 1600-60-60 are both 1480, so the card
	# grid keeps every column it has today.
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	GameTheme.make_settings_gear(self)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	outer.add_child(header)

	# ── BALANCE THE BACK BUTTON (2026-09-03) ──
	# The title EXPANDs and centres its text inside whatever box it is given, and
	# BACK eats 140px (120 + the separation) off the right end of that box — so
	# the screen's title centred 70px left of the page it heads. Measured off the
	# render: "COLLECTION" centred on 749.5 above a panel centred on 819.
	# A mirroring spacer of the button's own width restores the axis; reading the
	# width from the button means the two cannot drift apart.
	var back_btn: Button = GameTheme.make_back_button("BACK", Vector2(120, 40))
	var back_mirror := Control.new()
	back_mirror.custom_minimum_size = Vector2(back_btn.custom_minimum_size.x, 0)
	back_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(back_mirror)

	var title: VBoxContainer = GameTheme.make_screen_title("COLLECTION")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	back_btn.pressed.connect(_leave_to_menu)
	GameTheme.arm_ui_press(back_btn, "back")
	header.add_child(back_btn)

	# Tab row — frameless text, left-aligned; the lit tab is gilt, the rest
	# wait dim. A thin tan rule seats the row (the chart language).
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 26)
	outer.add_child(tab_row)
	for t in TABS:
		var b := Button.new()
		b.flat = true
		b.text = t.label
		b.focus_mode = Control.FOCUS_NONE
		if GameTheme.font_display:
			b.add_theme_font_override("font", GameTheme.font_display)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(show_tab.bind(t.id))
		GameTheme.arm_ui_press(b, "select")
		# The lit-tab bar, parented to the button and pinned to its bottom
		# edge. Hidden until show_tab lights it.
		var mark := ColorRect.new()
		mark.name = "TabMark"
		mark.color = GameTheme.GILT_BRIGHT
		mark.visible = false
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = 0.0
		mark.anchor_right = 1.0
		mark.anchor_top = 1.0
		mark.anchor_bottom = 1.0
		mark.offset_left = 4
		mark.offset_right = -4
		mark.offset_top = -3
		mark.offset_bottom = 0
		b.add_child(mark)
		tab_row.add_child(b)
		_tab_buttons[t.id] = b
	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.50, 0.34, 0.30)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(rule)

	# The shelf the collection is laid out on. The painted library behind this
	# screen is deliberately lit (see _ready above), but it was showing through
	# every gap between tiles, so the cards competed with a tavern for the eye —
	# on the one screen whose entire subject is the cards. An ink plate under the
	# grid answers both at once: the room still frames the screen at the margins
	# and behind the title, and the cards read as paper laid on a dark table.
	# ChartPanelStyle's hand-cut edge and corner tacks keep it a document, not a
	# black box.
	var plate := PanelContainer.new()
	_plate = plate
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var plate_sb: StyleBox = GameTheme.make_panel_style(
		Color(0.055, 0.045, 0.038, 0.88),
		Color(0.60, 0.51, 0.34, 0.50), 2, 8, true)
	plate_sb.content_margin_left = 18
	plate_sb.content_margin_right = 12
	plate_sb.content_margin_top = 16
	plate_sb.content_margin_bottom = 16
	plate.add_theme_stylebox_override("panel", plate_sb)
	outer.add_child(plate)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The full rail, not the hairline: this screen is nothing BUT scrolling —
	# 130+ card tiles down a single column — so the bar is primary navigation
	# here, not the incidental side-list affordance style_thin_scrollbar serves.
	GameTheme.style_rail_scrollbar(_scroll)
	plate.add_child(_scroll)
	_scroll.get_v_scroll_bar().value_changed.connect(
		_on_collection_scroll_changed)
	_scroll.resized.connect(_on_collection_scroll_resized)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_scroll.add_child(_content)

	show_tab("cards")


func _unhandled_input(event: InputEvent) -> void:
	# Esc = the BACK button: return to the main menu.
	if event.is_action_pressed("ui_cancel"):
		_leave_to_menu()
		get_viewport().set_input_as_handled()


## fade_out_then_change_scene hangs its ink overlay off the TREE ROOT and only
## changes the scene when the wipe lands, so BACK and Esc both stay live for the
## whole 0.34s. Two of them queued two transitions and the menu the first had
## already loaded was torn down and rebuilt — with this screen's _exit_tree
## having cleared every card, relic and potion texture in between, so the second
## menu paid the whole cold-cache bill.
func _leave_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	GameTheme.fade_out_then_change_scene(self, MENU_SCENE)


func _exit_tree() -> void:
	# The compendium can touch the entire card/relic/potion library in one visit.
	# None of those textures are needed by the menu we return to, so release the
	# gallery's global strong references instead of carrying hundreds of MiB for
	# the rest of the session. Run/map warmers repopulate the small live set.
	CardTextureCache.clear()
	CardArtAliases.clear_runtime_caches()
	RelicDB.clear_icon_cache()
	PotionDB.clear_icon_cache()
	ScenePreload.invalidate_encounter_art_warm_state()


func show_tab(tab: String) -> void:
	if tab == _current_tab:
		return
	_current_tab = tab
	_view_gen += 1
	_card_jobs.clear()
	_card_hydration_gen = -1
	_relic_jobs.clear()
	_relic_hydration_gen = -1
	_relic_refresh_queued = false
	_card_refresh_queued = false
	_card_virtual_accum = 0.0
	set_process(false)
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var lit: bool = id == tab
		b.add_theme_color_override("font_color",
			GameTheme.GILT_BRIGHT if lit else Color(0.60, 0.53, 0.42))
		# The lit tab also carries a gilt bar seated on the row's rule. Colour
		# alone was doing all the work of saying which shelf you're looking at
		# — and doing it in two tones of the same gold.
		var mark: Control = b.get_node_or_null("TabMark")
		if mark != null:
			mark.visible = lit
	_clear_collection_content_now()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	_show_collection_loading(tab)
	var stage := _make_collection_stage()
	match tab:
		"cards":
			_build_cards(_view_gen, stage)
		"relics":
			_build_relics(_view_gen, stage)
		"potions":
			_build_potions(stage)
			_commit_collection_stage(stage, _view_gen)
		"history":
			_build_history(_view_gen, stage)
		_:
			_abandon_collection_stage(stage)


## Build tab contents off-tree and commit the whole shelf in one frame. The
## waiting tableau stays stable while work is spread across frames, so later
## sections are never pushed down by cards arriving in batches.
func _make_collection_stage() -> VBoxContainer:
	var stage := VBoxContainer.new()
	stage.name = "CollectionStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 16)
	return stage


func _clear_collection_content_now() -> void:
	if _content == null or not is_instance_valid(_content):
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _abandon_collection_stage(stage: VBoxContainer) -> void:
	if stage != null and is_instance_valid(stage):
		stage.free()


## Five face-down writs share one screen-space lamplight and route. This reads
## as one archive being prepared, not as five independent loading spinners.
func _show_collection_loading(tab: String) -> void:
	_cancel_collection_swap()
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.modulate = Color.WHITE if snap else Color(0.76, 0.67, 0.52, 0.0)
	if snap or _plate == null or not is_instance_valid(_plate):
		return
	var overlay := CenterContainer.new()
	overlay.name = "CollectionLoading"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.z_index = 8
	_plate.add_child(overlay)
	_loading_overlay = overlay

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 18)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(stack)
	var copy: String = String({
		"cards": "LAYING OUT THE CARD LEDGER",
		"relics": "OPENING THE RELIQUARY",
		"potions": "OPENING THE APOTHECARY",
		"history": "TURNING THE CAMPAIGN LEDGER",
	}.get(tab, "OPENING THE ARCHIVE"))
	var caption := _section_label(copy)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)

	var row := HBoxContainer.new()
	row.name = "LoadingWrits"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(row)
	for i in 5:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(82, 110)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		var back := TextureRect.new()
		back.name = "LoadingWrit_%d" % i
		back.texture = CARD_BACK_TEXTURE
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(back)
		Motion.arm_loading_writ(back, row)


## Reparent only the section roots, preserving the original runtime hierarchy.
## All fixed-size placeholders enter the live VBox before its first layout.
func _commit_collection_stage(stage: VBoxContainer, generation: int) -> bool:
	if generation != _view_gen or not is_inside_tree() \
			or stage == null or not is_instance_valid(stage):
		_abandon_collection_stage(stage)
		return false
	_clear_collection_content_now()
	for child in stage.get_children():
		stage.remove_child(child)
		_content.add_child(child)
	stage.free()
	_content.set_meta("collection_stage_generation", generation)
	_reveal_collection_stage(generation)
	return true


func _reveal_collection_stage(generation: int) -> void:
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if snap:
		if _scroll != null and is_instance_valid(_scroll):
			_scroll.modulate = Color.WHITE
		_clear_collection_loading_now()
		return
	await get_tree().process_frame
	if generation != _view_gen or not is_inside_tree() \
			or _scroll == null or not is_instance_valid(_scroll):
		return
	var overlay := _loading_overlay
	_collection_swap_tween = create_tween().set_parallel(true)
	_collection_swap_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_collection_swap_tween.tween_property(_scroll, "modulate", Color.WHITE,
		Motion.time(0.22))
	if overlay != null and is_instance_valid(overlay):
		_collection_swap_tween.tween_property(overlay, "modulate:a", 0.0,
			Motion.time(0.16))
	await get_tree().create_timer(maxf(Motion.time(0.23), 0.01)).timeout
	if generation == _view_gen and overlay == _loading_overlay:
		_clear_collection_loading_now()


func _cancel_collection_swap() -> void:
	if _collection_swap_tween != null and _collection_swap_tween.is_valid():
		_collection_swap_tween.kill()
	_collection_swap_tween = null
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.modulate = Color.WHITE
	_clear_collection_loading_now()


func _clear_collection_loading_now() -> void:
	if _loading_overlay != null and is_instance_valid(_loading_overlay):
		var parent := _loading_overlay.get_parent()
		if parent != null:
			parent.remove_child(_loading_overlay)
		_loading_overlay.queue_free()
	_loading_overlay = null


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", GameTheme.GILT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## What a tab says when it lists nothing (COPY_STYLE §12 — an empty state names
## the thing and says how it fills).
##
## Every tab here builds its shelf by SKIPPING empty sections, so a tab with no
## content at all rendered as a blank plate: no title, no message, nothing to
## tell a player whether they were looking at a bug, a locked feature, or a
## screen still loading. The compendium is not an unlock gallery — it prints the
## whole game whether you have played it or not — so the honest second line says
## what the tab holds AND that an empty one is a fault rather than progress the
## player has yet to make.
func _empty_state(head_text: String, body_text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_section_label(head_text))
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(700, 0)
	if GameTheme.font_body:
		body.add_theme_font_override("font", GameTheme.font_body)
	body.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	body.add_theme_color_override("font_color", Color(0.86, 0.80, 0.70))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	return box


# ── CARDS ────────────────────────────────────────────────────────────────────

func _build_cards(gen: int, stage: VBoxContainer) -> void:
	# Do not instantiate Card2D until its bake exists. Card2D intentionally
	# falls back to the full ornate build when the cache is cold, which made
	# this screen pay the worst possible cost: render every card, wait two
	# frames for every bake, then build the visible card again. Lightweight
	# placeholders make the tab readable immediately; the cache hydrates them
	# into real cards in the background.
	var all_cards: Array[Dictionary] = []
	for id in CardDB.CARD_POOL:
		all_cards.append(CardDB.CARD_POOL[id])

	var jobs: Array[Dictionary] = []
	var placeholders_since_yield := 0
	for section in SECTIONS:
		var section_cards: Array[Dictionary] = []
		for c in all_cards:
			if c.get("rarity", "") == section.rarity and c.get("type", "") == section.type:
				section_cards.append(c)
		if section_cards.is_empty():
			continue

		stage.add_child(_section_label("%s  (%d)" % [section.label, section_cards.size()]))

		var grid := HFlowContainer.new()
		# Gutters measured, not chosen: the plate's padding and the scroll rail
		# eat 41px of the row, and at the old 22px h_separation six 225px writs
		# no longer fit — the grid dropped to five per row and left a card-wide
		# void down the right of the plate. 14 keeps six across with room to
		# spare, and tighter gutters suit a plate anyway: the tiles read as one
		# laid-out sheet instead of floating apart.
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 20)
		stage.add_child(grid)

		section_cards.sort_custom(func(a, b): return a.get("cost", 0) < b.get("cost", 0))

		for card_data in section_cards:
			var placeholder := _make_card_placeholder(card_data)
			grid.add_child(placeholder)
			jobs.append({
				"data": card_data.duplicate(true),
				"grid": grid,
				"node": placeholder,
				"state": "placeholder",
				"busy": false,
				"revealed_once": false,
			})
			placeholders_since_yield += 1
			if placeholders_since_yield >= CARD_PLACEHOLDER_YIELD_EVERY:
				placeholders_since_yield = 0
				await get_tree().process_frame
				if gen != _view_gen or not is_inside_tree():
					_abandon_collection_stage(stage)
					return

	if gen != _view_gen or not is_inside_tree():
		_abandon_collection_stage(stage)
		return
	if jobs.is_empty():
		stage.add_child(_empty_state("No cards to show",
			"This tab lists every card in the game — creatures, spells and"
			+ " armaments. An empty list means the card library failed to load."))
	if not _commit_collection_stage(stage, gen):
		return
	_card_jobs = jobs
	# Containers need one layout pass before global rects are meaningful.
	await get_tree().process_frame
	if gen == _view_gen and is_inside_tree():
		_refresh_card_virtual_window(gen)


func _process(delta: float) -> void:
	if _current_tab != "cards" or _card_jobs.is_empty():
		return
	_card_virtual_accum += delta
	if _card_virtual_accum < CARD_VIRTUAL_REFRESH:
		return
	_card_virtual_accum = fmod(_card_virtual_accum, CARD_VIRTUAL_REFRESH)
	_refresh_card_virtual_window(_view_gen)


func _on_collection_scroll_changed(_value: float) -> void:
	_queue_card_virtual_refresh()
	_queue_relic_virtual_refresh()


func _on_collection_scroll_resized() -> void:
	_queue_card_virtual_refresh()
	_queue_relic_virtual_refresh()


func _queue_card_virtual_refresh() -> void:
	# Card swaps preserve slot geometry, so scroll/resize events are the only
	# steady-state reasons to revisit the full job index. Debounce container
	# chatter into one next-frame refresh instead of polling all cards at 10 Hz.
	if (
		_current_tab != "cards"
		or _card_jobs.is_empty()
		or _card_refresh_queued
	):
		return
	_card_refresh_queued = true
	call_deferred("_flush_card_virtual_refresh", _view_gen)


func _flush_card_virtual_refresh(gen: int) -> void:
	_card_refresh_queued = false
	if _gallery_hydration_valid(gen):
		_refresh_card_virtual_window(gen)


func _queue_relic_virtual_refresh() -> void:
	# Scrollbar changes can arrive several times during one container layout.
	# Collapse them into one deferred refresh, while still reacting on the very
	# next frame to thumb jumps (rather than exposing placeholders for 100 ms).
	if _current_tab != "relics" or _relic_jobs.is_empty() \
			or _relic_refresh_queued:
		return
	_relic_refresh_queued = true
	call_deferred("_flush_relic_virtual_refresh", _view_gen)


func _flush_relic_virtual_refresh(gen: int) -> void:
	_relic_refresh_queued = false
	if _relic_gallery_valid(gen):
		_refresh_relic_virtual_window(gen)


func _card_virtual_rect(margin_screens: float) -> Rect2:
	if _scroll == null or not is_instance_valid(_scroll):
		return Rect2()
	var viewport_rect := _scroll.get_global_rect()
	var margin := viewport_rect.size.y * margin_screens
	return Rect2(
		Vector2(viewport_rect.position.x, viewport_rect.position.y - margin),
		Vector2(viewport_rect.size.x, viewport_rect.size.y + margin * 2.0))


func _card_job_intersects(job: Dictionary, rect: Rect2) -> bool:
	var node: Control = job.get("node", null)
	return node != null and is_instance_valid(node) and node.is_inside_tree() \
		and node.get_global_rect().intersects(rect)


func _refresh_card_virtual_window(gen: int) -> void:
	if gen != _view_gen or _current_tab != "cards" or not is_inside_tree():
		return
	var cold_rect := _card_virtual_rect(CARD_COLD_MARGIN_SCREENS)
	# Once a real card is well beyond the scroll window, put its cheap tile back.
	# This bounds both Card2D nodes and ImageTexture references no matter how far
	# through the 100+ card compendium the player scrolls.
	for i in range(_card_jobs.size()):
		var job: Dictionary = _card_jobs[i]
		if String(job.get("state", "")) != "card" \
				or _card_job_intersects(job, cold_rect):
			continue
		var card: Control = job.get("node", null)
		var grid: HFlowContainer = job.get("grid", null)
		if card == null or grid == null or not is_instance_valid(card) \
				or not is_instance_valid(grid):
			continue
		var insert_at := card.get_index()
		var placeholder := _make_card_placeholder(job.get("data", {}))
		grid.add_child(placeholder)
		grid.move_child(placeholder, insert_at)
		card.queue_free()
		job["node"] = placeholder
		job["state"] = "placeholder"
		job["busy"] = false
		_card_jobs[i] = job
	if _card_hydration_gen != gen:
		_hydrate_visible_card_tiles(gen)


func _gallery_hydration_valid(gen: int) -> bool:
	return gen == _view_gen and _current_tab == "cards" and is_inside_tree()


func _hydrate_visible_card_tiles(gen: int) -> void:
	_card_hydration_gen = gen
	# The dummy renderer never presents gallery textures and may not emit the
	# frame-post-draw signal used by CardTextureCache. Keep headless probes on
	# the immediately-built placeholder model instead of parking a coroutine.
	if DisplayServer.get_name() == "headless":
		_card_hydration_gen = -1
		return
	var hydrated_since_yield := 0
	var staged: Array[Dictionary] = []
	while gen == _view_gen and _current_tab == "cards" and is_inside_tree():
		var warm_rect := _card_virtual_rect(CARD_WARM_MARGIN_SCREENS)
		var job_index := -1
		for i in range(_card_jobs.size()):
			var candidate: Dictionary = _card_jobs[i]
			if String(candidate.get("state", "")) == "placeholder" \
					and not bool(candidate.get("busy", false)) \
					and _card_job_intersects(candidate, warm_rect):
				job_index = i
				break
		if job_index < 0:
			if not staged.is_empty():
				await _commit_card_hydration_batch(staged, gen)
				staged.clear()
			break

		var job: Dictionary = _card_jobs[job_index]
		job["busy"] = true
		_card_jobs[job_index] = job
		var card_data: Dictionary = job.get("data", {})
		var loaded_art := false
		if not CardTextureCache.has_gallery(card_data):
			# Decode on the loader thread, flatten at native gallery resolution,
			# then release the source painting immediately.
			await CardArtAliases.prewarm_card_art(card_data)
			loaded_art = true
			if not _gallery_hydration_valid(gen):
				CardArtAliases.release_card_art(card_data)
				break
		var baked: Texture2D = await CardTextureCache.bake_gallery(
			card_data, _gallery_hydration_valid.bind(gen))
		if loaded_art:
			CardArtAliases.release_card_art(card_data)
		if gen != _view_gen or _current_tab != "cards" or not is_inside_tree():
			break

		job = _card_jobs[job_index]
		if baked == null:
			job["busy"] = false
			_card_jobs[job_index] = job
			continue
		var placeholder: Control = job.get("node", null)
		var grid: HFlowContainer = job.get("grid", null)
		# The user may have scrolled far away while the GPU snapshot completed.
		# Keep the placeholder rather than materializing an already-cold card.
		if placeholder != null and grid != null and is_instance_valid(placeholder) \
				and is_instance_valid(grid) \
				and _card_job_intersects(job,
					_card_virtual_rect(CARD_COLD_MARGIN_SCREENS)):
			# Keep the baked result staged until its whole batch is ready. The
			# placeholder remains the only laid-out child, so no card can reveal
			# early or move a neighbor while later bakes finish.
			staged.append({
				"job_index": job_index,
				"placeholder": placeholder,
				"grid": grid,
				"data": card_data,
			})
		else:
			job["busy"] = false
		_card_jobs[job_index] = job

		hydrated_since_yield += 1
		if hydrated_since_yield >= CARD_HYDRATE_YIELD_EVERY:
			hydrated_since_yield = 0
			if not staged.is_empty():
				await _commit_card_hydration_batch(staged, gen)
				staged.clear()
			else:
				await get_tree().process_frame
	if not staged.is_empty() and _gallery_hydration_valid(gen):
		await _commit_card_hydration_batch(staged, gen)
	_card_hydration_gen = -1 if _card_hydration_gen == gen else _card_hydration_gen


func _commit_card_hydration_batch(staged: Array[Dictionary], gen: int) -> void:
	if staged.is_empty() or not _gallery_hydration_valid(gen):
		return
	var illuminate: Array[Dictionary] = []
	for entry in staged:
		var job_index := int(entry.get("job_index", -1))
		if job_index < 0 or job_index >= _card_jobs.size():
			continue
		var job: Dictionary = _card_jobs[job_index]
		var placeholder: Control = entry.get("placeholder", null)
		var grid: HFlowContainer = entry.get("grid", null)
		if String(job.get("state", "")) != "placeholder" \
				or job.get("node", null) != placeholder \
				or placeholder == null or not is_instance_valid(placeholder) \
				or grid == null or not is_instance_valid(grid) \
				or not _card_job_intersects(job,
					_card_virtual_rect(CARD_COLD_MARGIN_SCREENS)):
			job["busy"] = false
			_card_jobs[job_index] = job
			continue
		var card_data: Dictionary = entry.get("data", {})
		var insert_at := placeholder.get_index()
		var card = CARD_SCENE.instantiate()
		card.card_data = card_data.duplicate(true)
		card.card_id = card_data.get("id", "")
		card.is_on_battlefield = true
		card.static_display = true
		card.live_baked_mode = true
		card.gallery_baked_mode = true
		grid.remove_child(placeholder)
		placeholder.queue_free()
		grid.add_child(card)
		grid.move_child(card, mini(insert_at, grid.get_child_count() - 1))
		job["node"] = card
		job["state"] = "card"
		job["busy"] = false
		if not bool(job.get("revealed_once", false)):
			job["revealed_once"] = true
			illuminate.append({"card": card, "data": card_data})
		_card_jobs[job_index] = job
	# All swaps above happened in one frame. Start every first-reveal sweep from
	# that same frame too; _illuminate performs one shared layout wait internally.
	for entry in illuminate:
		_illuminate(entry.get("card", null), entry.get("data", {}))
	await get_tree().process_frame


## THE ILLUMINATION LANDS (2026-09-10).
##
## The gallery hydrates asynchronously: a ghost writ stands in the slot, the real
## Card2D bakes on a worker, and the swap was a HARD CUT — `add_child` next to
## `queue_free`, one frame, no transition. Scrolling the collection was a field of
## cards snapping into existence, and it is the most literal answer there is to
## "the way cards load is a bit weird".
##
## NOT A CROSS-FADE, and this is the one place in this pass where that needed
## arguing. Everywhere else the rule is that objects do not change alpha — but
## here the object does not ARRIVE at all: the ghost and the card are the same
## card in the same slot (identical 225x300 tile, so nothing even reflows), and
## what changes is that it becomes legible. Blurring between two states of one
## thing says "loading"; the fiction says the gold leaf just went on. So the card
## lands at full strength and a specular sweeps it — a positive event rather than
## a soft blur, which is the same snap-and-punctuate the rest of the pass uses.
##
## Tinted by RARITY, so a rare resolving out of the ghosts announces itself in
## the gallery exactly as it does on a reward slate.
func _illuminate(card: Control, card_data: Dictionary) -> void:
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if DisplayServer.get_name() == "headless":
		return
	# One frame, or the band is sized from a card the grid has not laid out yet
	# and photographs as a zero-width sliver.
	await get_tree().process_frame
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	Motion.foil_sweep(card, card,
		GameTheme.rarity_color(String(card_data.get("rarity", "common"))), 0.34)


func _make_card_placeholder(card_data: Dictionary) -> Control:
	var ghost := CollectionCardGhost.new()
	ghost.custom_minimum_size = CARD_TILE_SIZE
	ghost.size = CARD_TILE_SIZE
	ghost.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ghost.configure(card_data, GameTheme.font_display, GameTheme.font_body,
		GameTheme.rarity_color(String(card_data.get("rarity", "common"))),
		GameTheme.PARCHMENT_LIGHT.darkened(0.60))
	return ghost


func _make_card_placeholder_legacy(card_data: Dictionary) -> PanelContainer:
	# A GHOST of the illuminated writ, not a different object. The grid hydrates
	# real Card2D bakes in the background; until one lands, this stands in. The
	# old placeholder was a dark rectangle with a cost chip, a "2 / 3" text line
	# and a flat colour band where the painting goes — it shared NOTHING with the
	# card's silhouette, so a half-hydrated grid read as broken rather than
	# loading (and scrolling fast is exactly when you see them). This mirrors the
	# writ's furniture at the same proportions — art plate, name cartouche, rules
	# well, corner seals — in unlit ink, so a card resolving reads as the page
	# being illuminated. Still cheap: plain Panels and Labels, no seeded painters.
	var rarity := String(card_data.get("rarity", "common"))
	var accent: Color = GameTheme.rarity_color(rarity)
	var is_spell := String(card_data.get("type", "")) == "spell"

	var tile := PanelContainer.new()
	tile.custom_minimum_size = CARD_TILE_SIZE
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The sheet, held back so a hydrated card visibly lights up beside it.
	var sheet: Color = GameTheme.PARCHMENT_LIGHT.darkened(0.60)
	var sb: StyleBox = GameTheme.make_panel_style(sheet,
		Color(accent.r, accent.g, accent.b, 0.60), 2, 6, false)
	sb.set_content_margin_all(0.0)
	tile.add_theme_stylebox_override("panel", sb)

	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(body)

	var ink := Color(0.10, 0.078, 0.058, 1.0)
	var well: Color = GameTheme.PARCHMENT_LIGHT.darkened(0.34)

	# Art plate — the writ mounts the painting big across the top half.
	_ghost_panel(body, Rect2(11, 12, 203, 134), ink.lightened(0.05),
		Color(accent.r, accent.g, accent.b, 0.34), 1)
	# Name cartouche band.
	_ghost_panel(body, Rect2(11, 150, 203, 30), ink, Color(0, 0, 0, 0), 0)
	# Rules well.
	_ghost_panel(body, Rect2(13, 184, 199, 78), well, Color(0, 0, 0, 0), 0)

	var name_lbl := _ghost_label(body, Rect2(16, 154, 193, 22),
		String(card_data.get("name", card_data.get("id", ""))),
		16, GameTheme.GILT, HORIZONTAL_ALIGNMENT_CENTER, true)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_ghost_label(body, Rect2(20, 190, 185, 68),
		String(card_data.get("desc", "")), 14,
		Color(0.20, 0.15, 0.10, 0.92), HORIZONTAL_ALIGNMENT_CENTER, false, true)

	# Cost seal, top-left, riding the card edge exactly as the writ prints it.
	_ghost_seal(body, Rect2(4, 2, 38, 36), Color(0.16, 0.24, 0.42, 1.0),
		str(int(card_data.get("cost", 0))))

	if is_spell:
		# Spells declare a contract instead of stats — the writ's one-line footer.
		_ghost_label(body, Rect2(14, 268, 197, 20), "SPELL", 14,
			Color(0.62, 0.54, 0.42, 0.95), HORIZONTAL_ALIGNMENT_CENTER, true)
	else:
		_ghost_seal(body, Rect2(5, 258, 38, 36), Color(0.42, 0.33, 0.12, 1.0),
			str(int(card_data.get("atk", 0))))
		_ghost_seal(body, Rect2(182, 258, 38, 36), Color(0.44, 0.14, 0.12, 1.0),
			str(int(card_data.get("hp", 0))))
		# No rarity/keyword footer on creatures. The writ prints none — the footer
		# is a casting contract, so spells declare and creatures don't — and the
		# gap between the two stat seals is only ~139px, which clipped strings
		# like "Uncommon / Swift, Piercing, Doom, On Death" by 126px. It was
		# leftover debug furniture from the old placeholder either way.
	return tile


func _ghost_panel(parent: Control, rect: Rect2, bg: Color, border: Color,
		border_w: int = 0) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",
		GameTheme.make_panel_style(bg, border, border_w, 3, false))
	# Geometry AFTER add_child: entering the tree re-applies the node's minimum
	# size and clobbers a size assigned beforehand.
	parent.add_child(p)
	p.position = rect.position
	p.size = rect.size
	return p


func _ghost_label(parent: Control, rect: Rect2, text: String, size: int,
		color: Color, align: int, display_font: bool, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wrap mode BEFORE the size is applied. An unwrapped Label's minimum width is
	# its whole text, and minimum size wins over an assigned size — so setting
	# autowrap afterwards left the rules line running out past the card edge.
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.max_lines_visible = 3
	l.clip_text = not wrap
	var f: Font = GameTheme.font_display if display_font else GameTheme.font_body
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Geometry AFTER add_child — a size set before entering the tree is replaced
	# by the node's minimum size, which left autowrap with no width to wrap at
	# (the rules line ran straight out of its well).
	parent.add_child(l)
	l.position = rect.position
	l.size = rect.size
	return l


func _ghost_seal(parent: Control, rect: Rect2, tint: Color, value: String) -> void:
	_ghost_panel(parent, rect, tint, Color(0.86, 0.78, 0.58, 0.55), 1)
	var l := _ghost_label(parent, Rect2(rect.position.x, rect.position.y + 6.0,
		rect.size.x, rect.size.y), value, 17, GameTheme.IVORY,
		HORIZONTAL_ALIGNMENT_CENTER, true)
	l.size.y = rect.size.y


func _make_cost_badge(cost: int, accent: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(30, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs: StyleBox = GameTheme.make_panel_style(
		Color(0.10, 0.075, 0.050, 0.98),
		Color(accent.r, accent.g, accent.b, 0.82), 1, 15, false)
	bs.content_margin_left = 0
	bs.content_margin_right = 0
	bs.content_margin_top = 0
	bs.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", bs)
	var lbl := Label.new()
	lbl.text = str(cost)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge


# ── RELICS ───────────────────────────────────────────────────────────────────

func _build_relics(gen: int, stage: VBoxContainer) -> void:
	# Index the complete collection with cheap, fixed-size ledger slips first.
	# Only plaques near the viewport load an icon and rich hover subtree; scroll
	# events hydrate visible rows immediately and retire distant live nodes.
	# The generation guard makes tab switches and Back safe between yield points.
	var jobs: Array[Dictionary] = []
	var since_yield := 0
	for sec in RELIC_TIERS:
		var ids: Array[String] = RelicDB.get_relics_by_tier(sec.tier)
		if ids.is_empty():
			continue
		ids.sort_custom(func(a, b):
			return String(RelicDB.RELICS[a].get("name", a)) < String(RelicDB.RELICS[b].get("name", b)))
		stage.add_child(_section_label("%s  (%d)" % [sec.label, ids.size()]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		stage.add_child(grid)
		for rid in ids:
			var relic_data: Dictionary = RelicDB.get_relic(rid)
			var accent := RelicDB.get_tier_color(rid)
			var placeholder := _make_relic_placeholder(rid, relic_data, accent)
			grid.add_child(placeholder)
			jobs.append({
				"rid": rid,
				"data": relic_data,
				"accent": accent,
				"grid": grid,
				"node": placeholder,
				"state": "placeholder",
				"busy": false,
				"revealed_once": false,
			})
			since_yield += 1
			if since_yield >= RELIC_PLACEHOLDER_YIELD_EVERY:
				since_yield = 0
				await get_tree().process_frame
				if gen != _view_gen or not is_inside_tree():
					_abandon_collection_stage(stage)
					return
	if gen != _view_gen or not is_inside_tree():
		_abandon_collection_stage(stage)
		return
	if jobs.is_empty():
		stage.add_child(_empty_state("No relics to show",
			"This tab lists every relic in the game, including the ones only"
			+ " events hand out. An empty list means they failed to load."))
	if not _commit_collection_stage(stage, gen):
		return
	_relic_jobs = jobs
	await get_tree().process_frame
	if gen == _view_gen and is_inside_tree():
		_refresh_relic_virtual_window(gen)


func _make_relic_placeholder(rid: String, relic_data: Dictionary,
		accent: Color) -> PanelContainer:
	# A fixed-size ledger slip keeps the complete tier layout stable without
	# loading an offscreen icon or constructing the rich hover subtree.
	var tile := PanelContainer.new()
	tile.name = "RelicPlaceholder_%s" % rid
	tile.custom_minimum_size = Vector2(466, 120)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.045, 0.038, 0.70)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.30)
	style.border_width_left = 2
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	tile.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = String(relic_data.get("name", rid))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if GameTheme.font_display:
		label.add_theme_font_override("font", GameTheme.font_display)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.58, 0.52, 0.43, 0.86))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(label)
	return tile


func _refresh_relic_virtual_window(gen: int) -> void:
	if gen != _view_gen or _current_tab != "relics" or not is_inside_tree():
		return
	var cold_rect := _card_virtual_rect(RELIC_COLD_MARGIN_SCREENS)
	for i in range(_relic_jobs.size()):
		var job: Dictionary = _relic_jobs[i]
		if String(job.get("state", "")) != "plaque" \
				or _card_job_intersects(job, cold_rect):
			continue
		var plaque: Control = job.get("node", null)
		var grid: HFlowContainer = job.get("grid", null)
		if plaque == null or grid == null or not is_instance_valid(plaque) \
				or not is_instance_valid(grid):
			continue
		var insert_at := plaque.get_index()
		var placeholder := _make_relic_placeholder(
			String(job.get("rid", "")), job.get("data", {}),
			job.get("accent", GameTheme.GILT))
		grid.remove_child(plaque)
		plaque.queue_free()
		grid.add_child(placeholder)
		grid.move_child(placeholder, insert_at)
		job["node"] = placeholder
		job["state"] = "placeholder"
		job["busy"] = false
		_relic_jobs[i] = job
	if _relic_hydration_gen != gen:
		_hydrate_visible_relic_plaques(gen)


func _relic_gallery_valid(gen: int) -> bool:
	return gen == _view_gen and _current_tab == "relics" and is_inside_tree()


func _next_relic_placeholder(rect: Rect2) -> int:
	for i in range(_relic_jobs.size()):
		var candidate: Dictionary = _relic_jobs[i]
		if String(candidate.get("state", "")) == "placeholder" \
				and not bool(candidate.get("busy", false)) \
				and _card_job_intersects(candidate, rect):
			return i
	return -1


func _hydrate_visible_relic_plaques(gen: int) -> void:
	_relic_hydration_gen = gen
	var hydrated_since_yield := 0
	var staged: Array[Dictionary] = []
	while _relic_gallery_valid(gen):
		var viewport_rect := _card_virtual_rect(0.0)
		var warm_rect := _card_virtual_rect(RELIC_WARM_MARGIN_SCREENS)
		var job_index := _next_relic_placeholder(viewport_rect)
		if job_index < 0:
			job_index = _next_relic_placeholder(warm_rect)
		if job_index < 0:
			if not staged.is_empty():
				await _commit_relic_hydration_batch(staged, gen)
				staged.clear()
			break

		var job: Dictionary = _relic_jobs[job_index]
		job["busy"] = true
		_relic_jobs[job_index] = job
		var placeholder: Control = job.get("node", null)
		var grid: HFlowContainer = job.get("grid", null)
		if placeholder != null and grid != null \
				and is_instance_valid(placeholder) and is_instance_valid(grid) \
				and _card_job_intersects(job,
					_card_virtual_rect(RELIC_COLD_MARGIN_SCREENS)):
			staged.append({
				"job_index": job_index,
				"placeholder": placeholder,
				"grid": grid,
				"rid": String(job.get("rid", "")),
				"data": job.get("data", {}),
				"accent": job.get("accent", GameTheme.GILT),
			})
		else:
			job["busy"] = false
		_relic_jobs[job_index] = job

		hydrated_since_yield += 1
		if hydrated_since_yield >= RELIC_HYDRATE_YIELD_EVERY:
			hydrated_since_yield = 0
			if not staged.is_empty():
				await _commit_relic_hydration_batch(staged, gen)
				staged.clear()
			else:
				await get_tree().process_frame
	if not staged.is_empty() and _relic_gallery_valid(gen):
		await _commit_relic_hydration_batch(staged, gen)
	_relic_hydration_gen = -1 if _relic_hydration_gen == gen \
		else _relic_hydration_gen


func _commit_relic_hydration_batch(staged: Array[Dictionary], gen: int) -> void:
	if staged.is_empty() or not _relic_gallery_valid(gen):
		return
	var illuminate: Array[Dictionary] = []
	for entry in staged:
		var job_index := int(entry.get("job_index", -1))
		if job_index < 0 or job_index >= _relic_jobs.size():
			continue
		var job: Dictionary = _relic_jobs[job_index]
		var placeholder: Control = entry.get("placeholder", null)
		var grid: HFlowContainer = entry.get("grid", null)
		if String(job.get("state", "")) != "placeholder" \
				or job.get("node", null) != placeholder \
				or placeholder == null or not is_instance_valid(placeholder) \
				or grid == null or not is_instance_valid(grid) \
				or not _card_job_intersects(job,
					_card_virtual_rect(RELIC_COLD_MARGIN_SCREENS)):
			job["busy"] = false
			_relic_jobs[job_index] = job
			continue
		var rid := String(entry.get("rid", ""))
		var relic_data: Dictionary = entry.get("data", {})
		var accent: Color = entry.get("accent", GameTheme.GILT)
		var plaque := _make_plaque(
			GameTheme.make_relic_chip(rid, 56),
			String(relic_data.get("name", rid)),
			String(relic_data.get("desc", "")), accent)
		var insert_at := placeholder.get_index()
		grid.remove_child(placeholder)
		placeholder.queue_free()
		grid.add_child(plaque)
		grid.move_child(plaque, mini(insert_at, grid.get_child_count() - 1))
		job["node"] = plaque
		job["state"] = "plaque"
		job["busy"] = false
		if not bool(job.get("revealed_once", false)):
			job["revealed_once"] = true
			illuminate.append({"plaque": plaque, "accent": accent})
		_relic_jobs[job_index] = job
	await get_tree().process_frame
	if not _relic_gallery_valid(gen) \
			or DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		return
	for entry in illuminate:
		var plaque: Control = entry.get("plaque", null)
		if plaque != null and is_instance_valid(plaque) and plaque.is_inside_tree():
			Motion.foil_sweep(plaque, plaque,
				entry.get("accent", GameTheme.GILT), 0.30)


# ── POTIONS ──────────────────────────────────────────────────────────────────

func _build_potions(stage: VBoxContainer) -> void:
	var ids: Array[String] = PotionDB.all_ids()
	if ids.is_empty():
		stage.add_child(_empty_state("No potions to show",
			"This tab lists every potion in the game. An empty list means they"
			+ " failed to load."))
		return
	stage.add_child(_section_label("Potions  (%d)" % ids.size()))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	stage.add_child(grid)
	for pid in ids:
		var p: Dictionary = PotionDB.get_potion(pid)
		var tint: Color = p.get("color", Color.WHITE)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = PotionDB.icon_for(pid)
		# Silhouette icons carry identity via the potion colour (same tinting
		# the run HUD applies); painted per-potion art renders untinted.
		if not PotionDB.is_painted_icon(pid):
			icon.modulate = tint
		grid.add_child(_make_plaque(icon,
			String(p.get("name", pid)), String(p.get("desc", "")), tint))


# ── RUN HISTORY ──────────────────────────────────────────────────────────────
#
# The data has been on disk the whole time. RunState._append_run_log has written
# one row per finished run since long before this screen existed, and until now
# nothing in the game read a line of it: the single-run chronicle on GameOver is
# shown once and destroyed, and MetaState keeps only totals. This tab is the
# reader's front end.
#
# TWO RULES RUN THROUGH THE WHOLE SECTION, and they are the same rule twice:
# never print a fact the row did not carry. A run logged before a column existed
# has no elapsed time and no relic list, and the honest rendering of that is to
# LEAVE THE CLAUSE OUT — a "0m" or an empty relic line would read as a run that
# was over instantly and carried nothing. Every field is therefore gated on
# RunState.run_history_has() rather than on its value being non-zero.

## Yields on the same schedule the card and relic shelves do — a machine with a
## long ledger builds hundreds of plaques, and the tab should be readable at the
## top while the tail is still going in. `gen` is the tab-switch generation:
## leaving the tab mid-build abandons it rather than filling a freed container.
const HISTORY_YIELD_EVERY: int = 10


func _build_history(gen: int, stage: VBoxContainer) -> void:
	var rows: Array[Dictionary] = RunState.read_run_history()
	if rows.is_empty():
		stage.add_child(_empty_state("No finished runs yet",
			"Every run you finish is written down here: how it ended, which"
			+ " hero carried it, how far it got, what killed it and how long"
			+ " it took. Start a run from the main menu — the entry is added"
			+ " when the run ends, whether you win, lose or abandon it."))
		_commit_collection_stage(stage, gen)
		return
	stage.add_child(_section_label("Finished Runs  (%d)" % rows.size()))
	var summary := _history_summary_line(rows)
	if summary != "":
		var caption := Label.new()
		caption.text = summary
		if GameTheme.font_body:
			caption.add_theme_font_override("font", GameTheme.font_body)
		caption.add_theme_font_size_override("font_size", 17)
		caption.add_theme_color_override("font_color", Color(0.74, 0.68, 0.58))
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(caption)
	var since_yield := 0
	for rec in rows:
		stage.add_child(_history_row(rec))
		since_yield += 1
		if since_yield >= HISTORY_YIELD_EVERY:
			since_yield = 0
			await get_tree().process_frame
			if gen != _view_gen or not is_inside_tree():
				_abandon_collection_stage(stage)
				return
	_commit_collection_stage(stage, gen)


## The band under the section label: the tally, and the figure this screen was
## built to produce. Every design doc in the project quotes a "40-minute run"
## and that number predates the 2026-07-07 act lengthening — nothing has ever
## measured it. The MEDIAN, not the mean: one run left open over lunch would
## drag an average anywhere, and the question being asked is "how long does a
## run take", which is a typical case.
func _history_summary_line(rows: Array[Dictionary]) -> String:
	var wins := 0
	var losses := 0
	var quits := 0
	var lengths: Array[int] = []
	for rec in rows:
		match String(rec.get("result", "")):
			"victory": wins += 1
			"defeat": losses += 1
			"abandoned": quits += 1
		if RunState.run_history_has(rec, "elapsed_seconds"):
			var secs := int(rec.get("elapsed_seconds", 0))
			if secs > 0:
				lengths.append(secs)
	var parts: Array[String] = []
	if wins > 0:
		parts.append(_history_count(wins, "victory", "victories"))
	if losses > 0:
		parts.append(_history_count(losses, "defeat", "defeats"))
	if quits > 0:
		parts.append("%d abandoned" % quits)
	if lengths.size() > 0:
		lengths.sort()
		var median: int = lengths[lengths.size() / 2]
		parts.append("median length %s" % _history_length(median))
	if parts.is_empty():
		return ""
	return "  ·  ".join(parts)


## Plain pluralisation. COPY_STYLE bans "(s)", so the two words are written out.
func _history_count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## "2026-09-12T14:03:05" → "12 Sep 2026, 14:03".
## A stamp that does not match that shape is echoed VERBATIM: a date this
## reader cannot parse is still a date the log wrote, and reformatting a guess
## is worse than showing the raw text.
func _history_when(stamp: String) -> String:
	var date_part := stamp
	var time_part := ""
	var split_at := stamp.find("T")
	if split_at < 0:
		split_at = stamp.find(" ")
	if split_at > 0:
		date_part = stamp.substr(0, split_at)
		time_part = stamp.substr(split_at + 1)
	var ymd := date_part.split("-")
	if ymd.size() != 3:
		return stamp
	for piece in ymd:
		if not String(piece).is_valid_int():
			return stamp
	var month := int(ymd[1])
	if month < 1 or month > 12:
		return stamp
	var out := "%d %s %d" % [int(ymd[2]), MONTH_ABBR[month - 1], int(ymd[0])]
	var hms := time_part.split(":")
	if hms.size() >= 2 and String(hms[0]).is_valid_int() \
			and String(hms[1]).is_valid_int():
		out += ", %02d:%02d" % [int(hms[0]), int(hms[1])]
	return out


func _history_length(secs: int) -> String:
	if secs <= 0:
		return ""
	if secs < 60:
		return "%ds" % secs
	var mins: int = secs / 60
	if mins < 60:
		return "%dm" % mins
	return "%dh %02dm" % [mins / 60, mins % 60]


## One finished run. Full-width plaque: the verdict and who carried it on top,
## the run's numbers under it, then what ended it and the seed to replay it.
func _history_row(rec: Dictionary) -> Control:
	var outcome := String(rec.get("result", ""))
	var dress: Dictionary = HISTORY_OUTCOMES.get(outcome, {})
	# An outcome word this build does not know is printed as it was written
	# rather than mapped onto one we do know.
	var verdict := "UNRECORDED"
	if dress.has("label"):
		verdict = String(dress["label"])
	elif outcome != "":
		verdict = outcome.to_upper()
	var accent: Color = dress.get("color", Color(0.72, 0.68, 0.60))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBox = GameTheme.make_panel_style(
		Color(0.075, 0.062, 0.050, 0.90),
		Color(accent.r, accent.g, accent.b, 0.42), 2, 6, false)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	# ── Line 1: verdict · hero · when ──
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)

	var verdict_lbl := Label.new()
	verdict_lbl.text = verdict
	if GameTheme.font_display:
		verdict_lbl.add_theme_font_override("font", GameTheme.font_display)
	verdict_lbl.add_theme_font_size_override("font_size", 19)
	verdict_lbl.add_theme_color_override("font_color", accent)
	verdict_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(verdict_lbl)

	var who := _history_hero_line(rec)
	if who != "":
		var who_lbl := Label.new()
		who_lbl.text = who
		if GameTheme.font_body:
			who_lbl.add_theme_font_override("font", GameTheme.font_body)
		who_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
		who_lbl.add_theme_color_override("font_color", Color(0.92, 0.87, 0.76))
		who_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(who_lbl)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(spacer)

	var stamp := String(rec.get("ended_at", ""))
	if stamp != "":
		var when_lbl := Label.new()
		when_lbl.text = _history_when(stamp)
		when_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if GameTheme.font_body:
			when_lbl.add_theme_font_override("font", GameTheme.font_body)
		when_lbl.add_theme_font_size_override("font_size", 16)
		when_lbl.add_theme_color_override("font_color", Color(0.66, 0.61, 0.52))
		when_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(when_lbl)

	# ── Line 2: the run's numbers ──
	var facts := _history_facts_line(rec)
	if facts != "":
		var facts_lbl := Label.new()
		facts_lbl.text = facts
		facts_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if GameTheme.font_body:
			facts_lbl.add_theme_font_override("font", GameTheme.font_body)
		facts_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
		facts_lbl.add_theme_color_override("font_color", Color(0.86, 0.80, 0.70))
		facts_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(facts_lbl)

	# ── Line 3: the relics it was carrying (v2 schema only) ──
	var relic_line := _history_relic_line(rec)
	if relic_line != "":
		var relic_lbl := Label.new()
		relic_lbl.text = relic_line
		relic_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if GameTheme.font_body:
			relic_lbl.add_theme_font_override("font", GameTheme.font_body)
		relic_lbl.add_theme_font_size_override("font_size", 17)
		relic_lbl.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
		relic_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(relic_lbl)

	# ── Line 4: what ended it, and the seed ──
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	col.add_child(foot)

	var cause := String(rec.get("cause_of_death", ""))
	# Only a run that DIED has a killer. An abandoned run can carry a stale
	# cause_of_death from a fight the hero survived, and printing it there
	# would tell the player something that did not happen.
	var cause_text := ""
	if cause != "" and outcome == "defeat":
		cause_text = "Killed by %s" % cause
	var cause_lbl := Label.new()
	cause_lbl.text = cause_text
	cause_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body:
		cause_lbl.add_theme_font_override("font", GameTheme.font_body)
	cause_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	cause_lbl.add_theme_color_override("font_color", Color(0.84, 0.62, 0.55))
	cause_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cause_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cause_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(cause_lbl)

	if RunState.run_history_has(rec, "seed"):
		foot.add_child(_history_seed_chip(int(rec.get("seed", 0))))

	return panel


func _history_hero_line(rec: Dictionary) -> String:
	var hero_id := String(rec.get("hero", ""))
	if hero_id == "":
		return ""
	# has_hero FIRST: HeroDB.get_hero answers with the DEFAULT hero for an id it
	# does not know, which would put "Stalwart" against a garbled row.
	var name := hero_id
	if HeroDB.has_hero(hero_id):
		name = String(HeroDB.get_hero(hero_id).get("name", hero_id))
	if RunState.run_history_has(rec, "ascension") \
			and int(rec.get("ascension", 0)) > 0:
		name += "  ·  Ascension %d" % int(rec.get("ascension", 0))
	return name


func _history_facts_line(rec: Dictionary) -> String:
	var parts: Array[String] = []
	if RunState.run_history_has(rec, "act"):
		parts.append("Act %d" % int(rec.get("act", 0)))
	if RunState.run_history_has(rec, "floor"):
		parts.append(_history_count(int(rec.get("floor", 0)),
			"province", "provinces"))
	if RunState.run_history_has(rec, "fights_won"):
		parts.append("%s won" % _history_count(int(rec.get("fights_won", 0)),
			"fight", "fights"))
	if RunState.run_history_has(rec, "gold"):
		parts.append("%d gold" % int(rec.get("gold", 0)))
	if RunState.run_history_has(rec, "hp") \
			and RunState.run_history_has(rec, "max_hp"):
		parts.append("%d/%d HP" % [int(rec.get("hp", 0)),
			int(rec.get("max_hp", 0))])
	if RunState.run_history_has(rec, "deck_size"):
		parts.append(_history_count(int(rec.get("deck_size", 0)),
			"card", "cards"))
	if RunState.run_history_has(rec, "elapsed_seconds"):
		var length := _history_length(int(rec.get("elapsed_seconds", 0)))
		if length != "":
			parts.append(length)
	return "  ·  ".join(parts)


## The relic ids the v2 schema added. A row from before the bump has none, and
## says nothing rather than showing an empty list.
func _history_relic_line(rec: Dictionary) -> String:
	var ids: PackedStringArray = rec.get("relic_ids", PackedStringArray())
	if ids.is_empty():
		return ""
	var names: Array[String] = []
	for i in range(mini(ids.size(), HISTORY_RELIC_NAMES_SHOWN)):
		var rid := String(ids[i])
		# Same rule as the hero name: an id RelicDB does not know prints as the
		# id, never as a substituted relic.
		if RelicDB.RELICS.has(rid):
			names.append(String(RelicDB.RELICS[rid].get("name", rid)))
		else:
			names.append(rid)
	var line := "Relics: " + ", ".join(names)
	var rest := ids.size() - HISTORY_RELIC_NAMES_SHOWN
	if rest > 0:
		line += " and %d more" % rest
	return line


## Click-to-copy, in GameOver._add_seed_chip's dress and behaviour: frameless,
## dim, pointing-hand, claim_pop on the press, and the label confirms the copy.
func _history_seed_chip(seed_value: int) -> Button:
	var chip := Button.new()
	chip.name = "SeedChip"
	chip.text = "Seed %d  ·  click to copy" % seed_value
	chip.flat = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_font_size_override("font_size", 16)
	chip.add_theme_color_override("font_color", Color(0.62, 0.56, 0.46, 0.85))
	chip.add_theme_color_override("font_hover_color", Color(0.90, 0.82, 0.60))
	if GameTheme.font_body:
		chip.add_theme_font_override("font", GameTheme.font_body)
	chip.pressed.connect(func() -> void:
		GameTheme.claim_pop(chip)
		DisplayServer.clipboard_set(str(seed_value))
		chip.text = "Seed %d  ·  copied" % seed_value)
	GameTheme.hover_lift(chip, 1.02)
	return chip


# ── Shared plaque tile ───────────────────────────────────────────────────────

func _make_plaque(icon_node: Control, name_text: String, desc_text: String,
		accent: Color) -> Control:
	# Dark-ink tile with an accent left rule (the bark-scrim / map-tooltip
	# language): icon, gilt name, dim effect text — readable without hovering.
	var tile := Control.new()
	# 466, not 478, for the same reason the card gutters tightened: three plaques
	# have to clear the plate's padding and the scroll rail, and at 478 they no
	# longer did — the relic and potion shelves fell to two per row and left half
	# the plate empty. The 120px height keeps three lines of effect text fully
	# inside the tile at the project's minimum readable body size.
	tile.custom_minimum_size = Vector2(466, 120)
	var chrome := ColorRect.new()
	chrome.name = "PlaqueChrome"
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.color = Color.WHITE
	chrome.material = _collection_plaque_material(
		Color(accent.r, accent.g, accent.b, 0.55))
	tile.add_child(chrome)
	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 12)
	inset.add_theme_constant_override("margin_right", 12)
	inset.add_theme_constant_override("margin_top", 4)
	inset.add_theme_constant_override("margin_bottom", 4)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(inset)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	inset.add_child(row)

	icon_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_node)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = name_text
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.max_lines_visible = 3
	desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	desc_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	desc_lbl.add_theme_color_override("font_color", Color(0.90, 0.84, 0.73, 1.0))
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)

	return tile


## Collection-only plaque chrome. The shared ChartPanelStyle is intentionally
## ornate, but its field, four edge bands, and eight tack commands replay for
## every visible list item every frame. This shader preserves that hierarchy in
## one quad. A small cached material per accent keeps tiers and potion colors
## distinct without Compatibility-renderer instance-uniform batching artifacts.
func _collection_plaque_material(accent: Color) -> ShaderMaterial:
	var key := accent.to_html(true)
	if _plaque_materials.has(key):
		return _plaque_materials[key]
	if _plaque_shader == null:
		_plaque_shader = Shader.new()
		_plaque_shader.code = """
shader_type canvas_item;
uniform vec4 accent_color : source_color = vec4(0.60, 0.51, 0.34, 0.55);
const vec2 PLAQUE_SIZE = vec2(466.0, 120.0);
const float CHAMFER = 13.0;

float plaque_sdf(vec2 p, vec2 half_size) {
	vec2 a = abs(p);
	float rect_d = max(a.x - half_size.x, a.y - half_size.y);
	float corner_d = (a.x + a.y
		- (half_size.x + half_size.y - CHAMFER)) * 0.70710678;
	return max(rect_d, corner_d);
}

void fragment() {
	vec2 half_size = PLAQUE_SIZE * 0.5 - vec2(0.75);
	vec2 local = UV * PLAQUE_SIZE - PLAQUE_SIZE * 0.5;
	float d = plaque_sdf(local, half_size);
	float aa = max(fwidth(d), 0.70);
	float plate = 1.0 - smoothstep(-aa, aa, d);

	vec3 base = vec3(0.065, 0.052, 0.042);
	vec3 top_color = mix(base, vec3(0.30, 0.24, 0.16), 0.22);
	vec3 bottom_color = mix(base, vec3(0.0), 0.30);
	vec3 rgb = mix(top_color, bottom_color, UV.y);

	float toast = smoothstep(-10.0 - aa, -5.0 + aa, d) * plate;
	rgb = mix(rgb, vec3(0.02, 0.012, 0.006), toast * 0.50);
	float halo = (1.0 - smoothstep(2.5, 4.5, abs(d))) * plate;
	rgb = mix(rgb, accent_color.rgb, halo * accent_color.a * 0.22);
	float seam = (1.0 - smoothstep(1.4, 2.7, abs(d))) * plate;
	rgb = mix(rgb, vec3(0.04, 0.03, 0.02), seam * 0.82);
	float rule = (1.0 - smoothstep(0.25, 1.15, abs(d))) * plate;
	rgb = mix(rgb, accent_color.rgb, rule * min(accent_color.a * 1.65, 1.0));

	vec2 tack_center = half_size - vec2(CHAMFER * 0.5);
	vec2 tack_delta = abs(local) - tack_center;
	float tack_d = abs(tack_delta.x) + abs(tack_delta.y) - 3.9;
	float tack = 1.0 - smoothstep(-aa, aa, tack_d);
	float tack_edge = 1.0 - smoothstep(0.25, 1.15, abs(tack_d));
	rgb = mix(rgb, accent_color.rgb * 0.55, tack);
	rgb = mix(rgb, min(accent_color.rgb * 1.25, vec3(1.0)), tack_edge);

	float alpha = max(plate * 0.80, tack * accent_color.a);
	COLOR = vec4(rgb, alpha);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _plaque_shader
	material.set_shader_parameter("accent_color", accent)
	_plaque_materials[key] = material
	return material
