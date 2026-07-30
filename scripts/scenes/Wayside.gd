extends Control
## Wayside.gd — the roadside halts between holds (slice 2 of the road to
## the keep). Three verbs, one per stop, dealt at map gen (node.wayside_id →
## RunState.current_wayside_id):
##   drill_yard      — push-your-luck creature training: +1/+1 per pass
##   standard_bearer — pass one banner keyword from one creature to another
##   supply_cache    — crack the cache open: pick 1 of 3 war-material spoils
## (muster_scale — the quartermaster's scales — was RETIRED from the deal
## 2026-07-02: it was a shop-lite vending stop. Card-selling moved to the
## sutler's buy-back at shops; the handler below stays only so a legacy save
## holding a muster_scale node still resolves.)
## All four are ONE-DECISION stops (the Inscryption cadence: walk in, one
## verb, walk out) — the long-form prose rooms stay in Event.gd. Permanent
## card changes ride the card_upgrades mod STACK via
## RunState.apply_wayside_upgrade — mods compose (a drilled creature can
## also carry a banner and be forged), Inscryption-style. The only caps are
## DRILL_MAX_STACKS and the forge's one "+" per card.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"

# Keywords the Standard-Bearer can lift off one creature and pin on another.
# Deliberately the simple combat banners — anything wired to extra card data
# (Wither N, Doom N, On-Enter/On-Death payloads, Adj. Buff) or that is a COST
# (Sacrifice) stays where it was printed.
const TRANSFERABLE_KW: Array = [
	"swift", "armored", "thorns", "piercing", "regenerate",
	"last_stand", "sniper", "lifelink", "overrun", "formation", "rampage",
	"guardian", "shield",
]

const DRILL_MAX_STACKS: int = 3
const DRILL_FAIL_HP: int = 3

var _verb: String = ""
# Drill Yard state — which deck index is on the yard and how many passes
# it has banked so far (the push-your-luck counter).
var _drill_index: int = -1
var _drill_stacks: int = 0
# Standard-Bearer state — donor index and the keyword being carried.
var _banner_from: int = -1
var _banner_kw: String = ""


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	# Lift the painted background: the scene's Background was crushed to ~0.30
	# self_modulate AND then the atmosphere overlay (event mood, vignette 0.50 +
	# outer-alpha 0.65) stacked on top, leaving the forest art near-black. Raise
	# the node back toward the Shop's 0.5 and soften the atmosphere so the
	# painting actually reads behind the document tiles.
	var bg := get_node_or_null("Background")
	if bg != null:
		bg.self_modulate = Color(0.62, 0.62, 0.60, 1.0)
	GameTheme.add_atmosphere(self, "event", true, {
		"vignette": 0.38,
		"grad_inner": Color(0.08, 0.05, 0.12, 0.16),
		"grad_outer": Color(0.02, 0.01, 0.05, 0.46),
	})
	AudioBank.play_music_random(["event", "event_b", "event_c"])
	_verb = RunState.current_wayside_id
	if _verb == "":
		# Legacy node or direct scene open — the cache is the verb that always
		# pays regardless of deck state.
		_verb = "supply_cache"
	_build()
	GameTheme.fade_in(self, 0.22)
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# A wayside halt asks for one decision, so Esc opens the pause/Settings
	# overlay rather than resolving the verb for the player.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _build() -> void:
	match _verb:
		"drill_yard":
			_build_drill_intro()
		"muster_scale":
			_build_scales()
		"standard_bearer":
			_build_banner_donor()
		"supply_cache":
			_build_cache()
		_:
			_build_cache()


# ── Shared shell ─────────────────────────────────────────────────────────

func _clear_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()


func _add_header(title_text: String, flavor: String) -> void:
	var title = GameTheme.make_screen_title(title_text,
		GameTheme.GILT_BRIGHT, GameTheme.FONT_TITLE)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 96
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var sub = GameTheme.make_label(flavor, GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_left = 280
	sub.offset_right = -280
	sub.offset_top = 104
	sub.offset_bottom = 170
	add_child(sub)
	GameTheme.deal_in(sub, 0.06)


## A parchment tile choice in the map screen's chart vocabulary — an inked
## document tile (dark ink body + tan rule + small corners + deep shadow), with
## an engraved sigil column, the headline in gilt over a short accent rule, and
## the payload line below. Composition mirrors make_choice_banner so the road's
## stops read like the rest screen's choices, not flat rounded buttons. The whole
## tile is one click target; `enabled = false` renders it dimmed (no dead
## rewards, but no hidden options either). `icon_path` may be "" — falls back to
## an engraved glyph from the headline's first character.
func _make_tile(headline: String, payload: String, on_press: Callable,
		enabled: bool = true, icon_path: String = "") -> Button:
	var btn := Button.new()
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(560, 112)
	# Parchment-variant chart panel: dark ink body, tan rule, ~4px corners, deep
	# shadow — the praised make_choice_banner look, enforced via the shared helper.
	btn.add_theme_stylebox_override("normal",
		GameTheme.make_panel_style(Color(0.055, 0.048, 0.040, 0.96),
			Color(0.60, 0.51, 0.34, 0.90), 1, 4, true, true))
	var hover_style := GameTheme.make_panel_style(Color(0.085, 0.070, 0.052, 0.97),
		GameTheme.GILT_BRIGHT, 1, 4, true, true)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed",
		GameTheme.make_panel_style(Color(0.045, 0.038, 0.032, 0.96),
			Color(0.60, 0.51, 0.34, 0.90), 1, 4, true, true))
	btn.add_theme_stylebox_override("disabled",
		GameTheme.make_panel_style(Color(0.05, 0.045, 0.04, 0.85),
			Color(0.40, 0.34, 0.22, 0.55), 1, 4, true, true))
	if enabled:
		btn.pressed.connect(on_press)
	else:
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.45)

	# Body: HBox = [engraved sigil column | text column], matching make_choice_banner.
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 18
	hbox.offset_right = -18
	hbox.offset_top = 10
	hbox.offset_bottom = -10
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(52, 52)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_box)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		# Engraved-sigil treatment: drop shadow + parchment tint, like the map legend.
		var icon_tex: Texture2D = load(icon_path)
		for layer in range(2):
			var tex := TextureRect.new()
			tex.texture = icon_tex
			tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			if layer == 0:
				for prop in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
					tex.set(prop, 2.0)
				tex.modulate = Color(0, 0, 0, 0.55)
			else:
				tex.modulate = Color(0.82, 0.74, 0.56)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(tex)
	else:
		# Illuminated drop-cap of the headline's first MEANINGFUL letter. Strip a
		# leading article first — otherwise "A banner case" / "A captain's
		# dispatches" / "A freelance's arms" all print the same "A" and it reads
		# as a broken/placeholder icon rather than a flourish.
		var cap_src := headline
		for article in ["The ", "An ", "A "]:
			if cap_src.begins_with(article):
				cap_src = cap_src.substr(article.length())
				break
		var glyph := GameTheme.make_label(cap_src.left(1).to_upper(), 38,
			Color(0.82, 0.74, 0.56), true)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		if GameTheme.font_display:
			glyph.add_theme_font_override("font", GameTheme.font_display)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(glyph)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var head := GameTheme.make_label(headline, 21, GameTheme.KEYWORD_GOLD, true)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	# Short gilt rule under the headline — the chart's ruled furniture.
	var rule := ColorRect.new()
	rule.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.70)
	rule.custom_minimum_size = Vector2(40, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rule)

	if payload != "":
		var body := GameTheme.make_label(payload, 17, GameTheme.IVORY)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(440, 0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(body)
	return btn


## The centered tile stack, kept so the walk-away line can sit under it rather
## than in a screen corner. Null on the sub-screens that build their own layout.
var _tile_stack: Control = null


## Stack tiles down the screen center, below the header band.
func _add_tile_stack(tiles: Array) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	var h: int = tiles.size() * 126
	vbox.offset_left = -290
	vbox.offset_right = 290
	vbox.offset_top = -h / 2 + 40
	vbox.offset_bottom = h / 2 + 40
	add_child(vbox)
	_tile_stack = vbox
	var i := 0
	for t in tiles:
		vbox.add_child(t)
		# Every wayside verb routes through this stack, so all the road's
		# one-decision stops share the entrance + hover language for free.
		GameTheme.deal_in(t, 0.10 + i * 0.07)
		if t is BaseButton and not (t as BaseButton).disabled:
			GameTheme.hover_lift(t, 1.02)
		i += 1


func _add_leave_button(label: String = "March on") -> void:
	var btn = GameTheme.make_back_button(label, Vector2(180, 42))
	# Centered under the tile stack, not pinned to the bottom-left corner. Every
	# sibling stop puts its walk-away directly beneath the choices (the Shop's
	# "Leave the Wagon", Recruit's "Turn Them Away", Treasure's "Take gold
	# instead"); the road's stops were the one place the dismiss sat diagonally
	# across the screen from the thing it dismissed. (Screen audit 2026-07-21.)
	btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	btn.offset_left = -90
	btn.offset_right = 90
	btn.offset_top = 0
	btn.offset_bottom = 42
	btn.pressed.connect(_go_to_map)
	add_child(btn)
	_seat_leave_button.call_deferred(btn)
	GameTheme.deal_in(btn, 0.12)
	GameTheme.hover_lift(btn, 1.04)


## Park the walk-away just below the tile stack once the stack has a real size.
## Falls back to a bottom-centered seat on the sub-screens that have no stack.
func _seat_leave_button(btn: Control) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var y: float = size.y - 96.0
	if _tile_stack != null and is_instance_valid(_tile_stack):
		y = _tile_stack.position.y + _tile_stack.size.y + 34.0
	y = minf(y, size.y - 70.0)
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = size.x * 0.5 - 90.0
	btn.offset_right = size.x * 0.5 + 90.0
	btn.offset_top = y
	btn.offset_bottom = y + 42.0


func _go_to_map() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


## Automation hook — the full-run probe escapes scenes it doesn't drive by
## calling _leave() when no LEAVE/CONTINUE button matches.
func _leave() -> void:
	_go_to_map()


## Closing beat: what happened, then Continue. Same shape as Event's result
## screen so the road's stops all end on the same breath.
func _show_result(text: String) -> void:
	_clear_ui()
	var accent := _result_accent(text)
	var title = GameTheme.make_screen_title(_result_title(), accent,
		GameTheme.FONT_HEADER)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 74
	title.offset_bottom = 138
	add_child(title)
	GameTheme.deal_in(title, 0.02)
	_spawn_result_seal(accent, _result_is_bad(text))

	var lbl := GameTheme.make_label(text, 24, GameTheme.IVORY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -420
	lbl.offset_right = 420
	lbl.offset_top = -96
	lbl.offset_bottom = 72
	add_child(lbl)
	if not (UserSettings != null and UserSettings.reduce_motion):
		lbl.visible_ratio = 0.0
		var reveal := clampf(lbl.get_total_character_count() * 0.004, 0.24, 0.72)
		create_tween().tween_property(lbl, "visible_ratio", 1.0, reveal) \
			.set_delay(0.10)
	GameTheme.deal_in(lbl, 0.08)

	var btn = GameTheme.make_back_button("Continue", Vector2(180, 42), 16,
		GameTheme.KEYWORD_GOLD)
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn.offset_left = -90
	btn.offset_right = 90
	btn.offset_top = -150
	btn.offset_bottom = -108
	btn.pressed.connect(_go_to_map)
	add_child(btn)
	GameTheme.deal_in(btn, 0.24)
	GameTheme.hover_lift(btn, 1.04)


func _result_title() -> String:
	match _verb:
		"drill_yard":
			return "THE DRILL YARD"
		"muster_scale":
			return "THE SCALES"
		"standard_bearer":
			return "THE STANDARD"
		"supply_cache":
			return "THE CACHE"
	return "THE ROAD"


func _result_is_bad(text: String) -> bool:
	var lower := text.to_lower()
	for token in ["lose", "lost", "blade", "empty", "blank", "nothing", "won't"]:
		if lower.find(token) >= 0:
			return true
	return false


func _result_accent(text: String) -> Color:
	if _result_is_bad(text):
		return Color(1.0, 0.38, 0.24)
	var lower := text.to_lower()
	if lower.find("gold") >= 0 or lower.find("healed") >= 0:
		return GameTheme.KEYWORD_GOLD
	if lower.find("command") >= 0 or lower.find("pinned") >= 0 \
			or lower.find("pins") >= 0:
		return Color(0.70, 0.86, 1.0)
	return GameTheme.GILT_BRIGHT


func _spawn_result_seal(accent: Color, bad: bool = false) -> void:
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var vp := get_viewport_rect().size
	var center := Vector2(vp.x * 0.5, vp.y * 0.44)
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = 90
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = Color(accent.r, accent.g, accent.b, 0.65)
	st.set_border_width_all(4)
	st.set_corner_radius_all(600)
	ring.add_theme_stylebox_override("panel", st)
	ring.size = Vector2(44, 44)
	ring.pivot_offset = ring.size * 0.5
	ring.position = center - ring.size * 0.5
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(6.0, 6.0), 0.46) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.46).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)
	if bad:
		var wash := ColorRect.new()
		wash.color = Color(0.55, 0.08, 0.04, 0.20)
		wash.set_anchors_preset(Control.PRESET_FULL_RECT)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wash.z_index = 80
		add_child(wash)
		var wt := wash.create_tween()
		wt.tween_property(wash, "color:a", 0.0, 0.44).set_delay(0.04)
		wt.tween_callback(wash.queue_free)


# ── Card picker grid (Event.gd's picker, compacted) ─────────────────────

func _make_card_grid(title_text: String, count: int = 6) -> GridContainer:
	_clear_ui()
	# Proper header (the verb's name over the instruction), matching every other
	# wayside stop — was a lone 22px label floating at the top.
	_add_header(_result_title(), title_text)

	# Center the grid instead of left-packing it at x=80: a small picker (two
	# banner donors) used to cling to the top-left with the whole screen empty
	# beside it. Columns shrink to the card count so few cards stay centered.
	var cols: int = clampi(count, 1, 6)
	var cell_w := 180  # 225·0.8 — cards scale to fit their cells (see _add_card_to_grid)
	var h_sep := 18
	var grid_w := cols * cell_w + (cols - 1) * h_sep
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size = Vector2(grid_w + 24, 600)  # +24 leaves room for the v-scrollbar
	scroll.position = Vector2((1600.0 - float(grid_w + 24)) * 0.5, 188)
	add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", h_sep)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	return grid


## Card tile with click overlay; optional footer line under the card (the
## scales print each card's selling price there).
func _add_card_to_grid(grid: GridContainer, data: Dictionary,
		callback: Callable, footer: String = "") -> void:
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 4)
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	# 0.8-scale writ fits its cell exactly (225·0.8=180, 300·0.8=240) — full-size
	# cards overflowed the old 210×280 cell and touched their neighbours.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(180, 240)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.pivot_offset = wrapper.custom_minimum_size * 0.5
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	card_node.live_baked_mode = true
	CardTextureCache.bake(data)
	card_node.scale = Vector2(0.8, 0.8)
	wrapper.add_child(card_node)
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.pressed.connect(_on_grid_card_pressed.bind(slot, callback))
	wrapper.add_child(click_btn)
	slot.add_child(wrapper)
	if footer != "":
		var f := GameTheme.make_label(footer, 16, GameTheme.KEYWORD_GOLD)
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(f)
	grid.add_child(slot)
	var idx := grid.get_child_count() - 1
	GameTheme.deal_in(slot, 0.04 + minf(float(idx), 12.0) * 0.025)
	GameTheme.hover_lift(slot, 1.025)


func _on_grid_card_pressed(slot: Control, callback: Callable) -> void:
	if slot != null and is_instance_valid(slot) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(slot)
		await get_tree().create_timer(0.10).timeout
	callback.call()


# ═══════════════════ DRILL YARD ═══════════════════
# Pick a creature; every completed pass banks +1/+1 (a drill entry in the
# card's mod stack, carrying a TOTAL stacks counter). After the first free
# pass, each further pass is a coin flip: heads +1/+1 more, tails the yard
# takes DRILL_FAIL_HP from YOU and closes. Stacks already banked always
# survive — the wager is your blood, never the creature's progress.
# Inscryption model: a forged or banner-carrying creature can still drill;
# only a creature already drilled to DRILL_MAX_STACKS is done here.

func _drill_eligible() -> Array:
	var out: Array = []
	for i in range(RunState.deck.size()):
		if int(RunState.get_upgrade_entry(i, "drill").get("stacks", 0)) >= DRILL_MAX_STACKS:
			continue
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "") != "creature":
			continue
		out.append(i)
	return out


func _build_drill_intro() -> void:
	var eligible := _drill_eligible()
	if eligible.is_empty():
		_clear_ui()
		_add_header("THE DRILL YARD",
			"Nothing green enough to drill. The sergeant pays you to haul targets instead.")
		RunState.gain_gold(20)
		_show_drill_consolation()
		return
	var grid = _make_card_grid("Pick a creature to drill (+1/+1).", eligible.size())
	for i in eligible:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_drill_pick.bind(i))
	_add_leave_button()


func _show_drill_consolation() -> void:
	# Header already painted by the caller; just land the receipt.
	var lbl := GameTheme.make_label("Gained 20 gold.", 22, GameTheme.KEYWORD_GOLD)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -300
	lbl.offset_right = 300
	lbl.offset_top = -20
	lbl.offset_bottom = 30
	add_child(lbl)
	_add_leave_button("Continue")


func _on_drill_pick(deck_index: int) -> void:
	_drill_index = deck_index
	# A creature drilled at an earlier yard picks up where it left off —
	# the new pass adds to its banked total instead of resetting it.
	_drill_stacks = int(RunState.get_upgrade_entry(deck_index, "drill").get("stacks", 0)) + 1
	RunState.apply_wayside_upgrade(deck_index,
		{"path": "drill", "stacks": _drill_stacks})
	AudioBank.play_sfx("card_play")
	_build_drill_push()


func _build_drill_push() -> void:
	_clear_ui()
	var data = RunState.get_upgraded_card_data(_drill_index)
	var nm: String = String(data.get("name", "The recruit"))
	_add_header("THE DRILL YARD",
		"%s has banked +%d/+%d. Push for more, or march on?" \
		% [nm, _drill_stacks, _drill_stacks])

	# The creature on the yard, current stats showing.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.set_anchors_preset(Control.PRESET_CENTER)
	wrapper.offset_left = -360
	wrapper.offset_right = -135
	wrapper.offset_top = -130
	wrapper.offset_bottom = 170
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	card_node.live_baked_mode = true
	CardTextureCache.bake(data)
	wrapper.add_child(card_node)
	add_child(wrapper)

	var tiles: Array = []
	if _drill_stacks < DRILL_MAX_STACKS:
		tiles.append(_make_tile("Run another pass",
			"Even odds: +1/+1 more, or lose %d HP and the yard closes. Banked passes are kept." % DRILL_FAIL_HP,
			_on_drill_again))
	tiles.append(_make_tile("March on",
		"%s keeps +%d/+%d." % [nm, _drill_stacks, _drill_stacks],
		_on_drill_stop))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -40
	vbox.offset_right = 540
	vbox.offset_top = -110
	vbox.offset_bottom = 120
	add_child(vbox)
	var ti := 0
	for t in tiles:
		vbox.add_child(t)
		GameTheme.deal_in(t, 0.10 + ti * 0.07)
		if t is BaseButton and not (t as BaseButton).disabled:
			GameTheme.hover_lift(t, 1.02)
		ti += 1


func _on_drill_again() -> void:
	if randi() % 2 == 0:
		_drill_stacks += 1
		RunState.apply_wayside_upgrade(_drill_index,
			{"path": "drill", "stacks": _drill_stacks})
		AudioBank.play_sfx("card_play")
		if _drill_stacks >= DRILL_MAX_STACKS:
			var data = RunState.get_upgraded_card_data(_drill_index)
			_show_result("The sergeant calls it: nothing more to teach. %s marches off the yard with +%d/+%d." \
				% [String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])
		else:
			_build_drill_push()
	else:
		# Non-lethal: the yard never takes the last drop.
		var to_lose: int = mini(DRILL_FAIL_HP, RunState.hero_hp - 1)
		RunState.damage_hero(maxi(0, to_lose))
		var data = RunState.get_upgraded_card_data(_drill_index)
		_show_result("A training blade finds you instead — you lose %d HP and the sergeant closes the yard. %s keeps +%d/+%d." \
			% [maxi(0, to_lose), String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])


func _on_drill_stop() -> void:
	var data = RunState.get_upgraded_card_data(_drill_index)
	_show_result("%s marches off the yard with +%d/+%d." \
		% [String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])


# ═══════════════════ MUSTER SCALES ═══════════════════
# The quartermaster weighs, he does not haggle. One trade per visit: sell a
# card by weight (gold scales with its Command cost — removal AND coin in
# one stop), or spend coin on provisions.

const SCALE_POTION_COST: int = 25
const SCALE_MEAL_COST: int = 20
const SCALE_MEAL_HEAL: int = 7


func _sell_price(card_id: String) -> int:
	if CardDB.is_curse(card_id):
		# A curse weighs nothing — but he'll still take it off you for scrap.
		return 5
	var data = CardDB.get_card_data(card_id)
	return 15 + 12 * int(data.get("cost", 0))


func _build_scales() -> void:
	_clear_ui()
	_add_header("THE TRADING SCALES",
		"Choose one trade.")
	var tiles: Array = []
	tiles.append(_make_tile("Sell a card by weight",
		"Remove a card. He pays 15 gold + 12 per Command it costs.",
		_build_scales_sell))
	var can_potion: bool = RunState.gold >= SCALE_POTION_COST and RunState.can_add_potion()
	var potion_note: String = "Pay %d gold. Gain a Healing Potion." % SCALE_POTION_COST
	if not RunState.can_add_potion():
		potion_note = "Potion belt is full."
	elif RunState.gold < SCALE_POTION_COST:
		potion_note = "Costs %d gold." % SCALE_POTION_COST
	tiles.append(_make_tile("Buy a potion", potion_note,
		_on_scales_potion, can_potion))
	var can_meal: bool = RunState.gold >= SCALE_MEAL_COST \
		and RunState.hero_hp < RunState.hero_max_hp
	var meal_note: String = "Pay %d gold. Heal %d HP." % [SCALE_MEAL_COST, SCALE_MEAL_HEAL]
	if RunState.hero_hp >= RunState.hero_max_hp:
		meal_note = "Already at full health."
	elif RunState.gold < SCALE_MEAL_COST:
		meal_note = "Costs %d gold." % SCALE_MEAL_COST
	tiles.append(_make_tile("A hot meal", meal_note,
		_on_scales_meal, can_meal))
	_add_tile_stack(tiles)
	_add_leave_button()


func _build_scales_sell() -> void:
	var grid = _make_card_grid("Choose one card to sell.",
		RunState.deck.size())
	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_scales_sell_pick.bind(i),
			"%d gold" % _sell_price(RunState.deck[i]))
	var back = GameTheme.make_back_button("Keep your pack", Vector2(180, 42))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_top = -70
	back.offset_right = 220
	back.offset_bottom = -28
	back.pressed.connect(_build_scales)
	add_child(back)


func _on_scales_sell_pick(deck_index: int) -> void:
	# Deck floor of 1 — the quartermaster won't buy your last card off you.
	if RunState.deck.size() <= 1:
		_show_result("He weighs it, then sets it back in your hands. \"Sell me your last? No. March on.\"")
		return
	var card_id: String = RunState.deck[deck_index]
	var data = CardDB.get_card_data(card_id)
	var price := _sell_price(card_id)
	RunState.remove_card_at(deck_index)
	RunState.gain_gold(price)
	AudioBank.play_sfx("button_click")
	_show_result("He weighs %s and counts out %d gold." \
		% [String(data.get("name", "the card")), price])


func _on_scales_potion() -> void:
	# Belt-and-suspenders: the tile is built disabled when unaffordable or the
	# belt is full, but guard the handler too so a stale tile can't push gold
	# negative or charge for a potion the full belt rejects.
	if RunState.gold < SCALE_POTION_COST:
		return
	if not RunState.add_potion("healing"):
		return
	RunState.gold -= SCALE_POTION_COST
	_show_result("Paid %d gold. Gained a Healing Potion." % SCALE_POTION_COST)


func _on_scales_meal() -> void:
	if RunState.gold < SCALE_MEAL_COST:
		return
	RunState.gold -= SCALE_MEAL_COST
	RunState.heal_hero(SCALE_MEAL_HEAL)
	_show_result("Paid %d gold. Healed %d HP." \
		% [SCALE_MEAL_COST, SCALE_MEAL_HEAL])


# ═══════════════════ THE STANDARD-BEARER ═══════════════════
# An old soldier who carries every banner his dead carried. Pick a creature
# to give up one keyword, then pick the creature who takes it. Both ends
# append to the cards' mod stacks; the trade is applied atomically at the
# final pick — backing out costs nothing. Keywords are read from the
# UPGRADED data, so a banner granted at one halt can be passed on at the
# next, and a stripped banner is really gone.

func _banner_donors() -> Array:
	var out: Array = []
	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		if data.get("type", "") != "creature":
			continue
		if not _transferable_of(data).is_empty():
			out.append(i)
	return out


func _transferable_of(data: Dictionary) -> Array:
	var out: Array = []
	for kw in data.get("keywords", []):
		if TRANSFERABLE_KW.has(kw):
			out.append(kw)
	return out


func _banner_receivers(donor_index: int, kw: String) -> Array:
	var out: Array = []
	for i in range(RunState.deck.size()):
		if i == donor_index:
			continue
		var data = RunState.get_upgraded_card_data(i)
		if data.get("type", "") != "creature":
			continue
		if data.get("keywords", []).has(kw):
			continue
		out.append(i)
	return out


func _build_banner_donor() -> void:
	var donors := _banner_donors()
	# A donor only counts if SOMEONE can take its banner.
	var valid: Array = []
	for i in donors:
		var data = RunState.get_upgraded_card_data(i)
		for kw in _transferable_of(data):
			if not _banner_receivers(i, kw).is_empty():
				valid.append(i)
				break
	if valid.is_empty():
		_clear_ui()
		_add_header("THE STANDARD-BEARER",
			"No banner here can change hands. He spares you a coin for the trouble.")
		RunState.gain_gold(15)
		var lbl := GameTheme.make_label("Gained 15 gold.", 22, GameTheme.KEYWORD_GOLD)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		lbl.offset_left = -300
		lbl.offset_right = 300
		lbl.offset_top = -20
		lbl.offset_bottom = 30
		add_child(lbl)
		_add_leave_button("Continue")
		return
	var grid = _make_card_grid("Choose who gives up a keyword.", valid.size())
	for i in valid:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_banner_donor_pick.bind(i))
	_add_leave_button()


func _on_banner_donor_pick(deck_index: int) -> void:
	_banner_from = deck_index
	var data = RunState.get_upgraded_card_data(deck_index)
	# Only offer keywords that have at least one valid receiver.
	var options: Array = []
	for kw in _transferable_of(data):
		if not _banner_receivers(deck_index, kw).is_empty():
			options.append(kw)
	if options.size() == 1:
		_banner_kw = options[0]
		_build_banner_receiver()
		return
	_clear_ui()
	_add_header("THE STANDARD-BEARER",
		"%s carries more than one banner. Which one passes on?" % String(data.get("name", "The creature")))
	var tiles: Array = []
	for kw in options:
		var info: Dictionary = KeywordEffects.KEYWORDS.get(kw, {})
		tiles.append(_make_tile(String(info.get("display", kw)),
			String(info.get("desc", "")), _on_banner_kw_pick.bind(kw)))
	_add_tile_stack(tiles)
	_add_leave_button()


func _on_banner_kw_pick(kw: String) -> void:
	_banner_kw = kw
	_build_banner_receiver()


func _build_banner_receiver() -> void:
	var info: Dictionary = KeywordEffects.KEYWORDS.get(_banner_kw, {})
	var disp: String = String(info.get("display", _banner_kw))
	var donor = CardDB.get_card_data(RunState.deck[_banner_from])
	var receivers := _banner_receivers(_banner_from, _banner_kw)
	var grid = _make_card_grid("%s gives up %s. Choose who takes it." \
		% [String(donor.get("name", "The creature")), disp], receivers.size())
	for i in receivers:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_banner_receiver_pick.bind(i))
	var back = GameTheme.make_back_button("Choose another", Vector2(200, 42))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_top = -70
	back.offset_right = 240
	back.offset_bottom = -28
	back.pressed.connect(_build_banner_donor)
	add_child(back)


func _on_banner_receiver_pick(deck_index: int) -> void:
	var info: Dictionary = KeywordEffects.KEYWORDS.get(_banner_kw, {})
	var disp: String = String(info.get("display", _banner_kw))
	var donor = CardDB.get_card_data(RunState.deck[_banner_from])
	var taker = CardDB.get_card_data(RunState.deck[deck_index])
	# Atomic: both halves land only now, after the full trade is chosen.
	RunState.apply_wayside_upgrade(_banner_from,
		{"path": "strip_kw", "keyword": _banner_kw})
	RunState.apply_wayside_upgrade(deck_index,
		{"path": "grant_kw", "keyword": _banner_kw})
	AudioBank.play_sfx("card_play")
	_show_result("The bearer lifts %s from %s and pins it to %s." \
		% [disp, String(donor.get("name", "the giver")),
			String(taker.get("name", "the taker"))])


# ═══════════════════ SUPPLY CACHE ═══════════════════
# A buried strongpoint from a war nobody finished. Three spoils surface,
# you carry one away. WAR-MATERIAL ONLY (2026-07-02): gold, heals, and
# potions are sold at every other stop on the road — what a cache pays is
# the war itself: bodies in your line, Command, and paper that turns into
# soldiers. Nothing in this pool is ever a dead reward, so the old
# situational gating went with the rations.

func _build_cache() -> void:
	_clear_ui()
	_add_header("THE SUPPLY CACHE",
		"Choose one supply from the abandoned strongpoint.")
	var pool: Array = [
		{"id": "levy", "head": "A militia kit",
			"note": "Next fight: start with a 2/4 Militia Spearman in front."},
		{"id": "free_lance", "head": "A freelance's arms",
			"note": "Next fight: start with a 3/2 Free Lance in front."},
		{"id": "dispatches", "head": "A captain's dispatches",
			"note": "Next fight: +1 max Command."},
		{"id": "banner_case", "head": "A banner case",
			"note": "Add 1 random common card to your deck."},
		{"id": "commission", "head": "A sealed commission",
			"note": "Add 1 random uncommon card to your deck."},
	]
	pool.shuffle()
	var offered: Array = pool.slice(0, mini(3, pool.size()))
	var tiles: Array = []
	for spoil in offered:
		tiles.append(_make_tile(String(spoil.head), String(spoil.note),
			_on_cache_take.bind(String(spoil.id))))
	_add_tile_stack(tiles)
	_add_leave_button("Leave it buried")


func _on_cache_take(id: String) -> void:
	AudioBank.play_sfx("button_click")
	match id:
		"free_lance":
			RunState.next_combat_gift_creature = {
				"name": "Free Lance", "atk": 3, "hp": 2, "kw": [],
			}
			_show_result("A Free Lance joins your front row in the next fight.")
		"commission":
			var pool_u = CardDB.cards_of_rarity("uncommon")
			if pool_u.is_empty():
				_show_result("The commission is blank. No card was added.")
				return
			pool_u.shuffle()
			RunState.add_card(pool_u[0])
			_show_result("Added %s to your deck." \
				% CardDB.get_card_data(pool_u[0]).name)
		"levy":
			RunState.next_combat_gift_creature = {
				"name": "Militia Spearman", "atk": 2, "hp": 4, "kw": [],
			}
			_show_result("A Militia Spearman joins your front row in the next fight.")
		"dispatches":
			RunState.next_combat_mana_bonus += 1
			_show_result("A captain's orders. +1 max Command next fight.")
		"banner_case":
			var pool_c = CardDB.cards_of_rarity("common")
			if pool_c.is_empty():
				_show_result("The case is empty. The moths apologize.")
				return
			pool_c.shuffle()
			RunState.add_card(pool_c[0])
			_show_result("Inside, wrapped in oilcloth: %s joins your deck." \
				% CardDB.get_card_data(pool_c[0]).name)
