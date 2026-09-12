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
const BATCHED_CHART_STYLE = preload("res://scripts/ui/BatchedChartPanelStyle.gd")
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
# The recruit standing on the yard. It OUTLIVES _clear_ui (see the explicit
# exclusion there) so the push-your-luck screen rebuilds its header and its
# tiles around the SAME card: each banked pass is then a stamp landing on a
# writ the player has been watching, not a fresh card popping in with bigger
# numbers already printed on it.
var _drill_card: Control = null
# Busy latch for the push screen's tiles. The stamp beat is AWAITED with both
# tiles still on screen and still live, which is the same shape as the three
# await-during-a-live-button bugs found in the 2026-08-07 audit: a second click
# on "Run another pass" would bank a second pass off the same coin flip. The
# latch clears only where the flow continues (a rebuilt push screen has fresh
# tiles); the terminal paths leave it held.
var _drill_busy: bool = false
# Standard-Bearer state — donor index and the keyword being carried.
var _banner_from: int = -1
var _banner_kw: String = ""
# The grid tile the player last clicked (see _on_grid_card_pressed).
var _last_pick_slot: Control = null
# One-pick latch for every card grid — see _on_grid_card_pressed.
var _grid_pick_taken: bool = false
# True only during a pick animation; Continue must not race its deferred callback.
var _grid_pick_pending: bool = false
# Set synchronously when the player walks on, blocking every remaining choice.
var _leaving: bool = false
var _ui_build_generation := 0


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
	_ui_build_generation += 1
	for child in get_children():
		# The drill yard's recruit is the one screen element that persists across
		# a rebuild — it is the thing being changed, so it must not blink out and
		# back between passes. Every drill exit frees it via _drill_dismiss().
		if child == _drill_card and is_instance_valid(_drill_card):
			continue
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


func _make_tile_style(bg: Color, border: Color) -> StyleBox:
	# Three tiles are visible together, so keep their chart construction while
	# batching the face/rim/tacks into one indexed submission (+ one shadow).
	return BATCHED_CHART_STYLE.from_chart(
		GameTheme.make_panel_style(bg, border, 1, 4, true, true))


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
	btn.add_theme_stylebox_override("normal", _make_tile_style(
		Color(0.055, 0.048, 0.040, 0.96), Color(0.60, 0.51, 0.34, 0.90)))
	var hover_style := _make_tile_style(Color(0.085, 0.070, 0.052, 0.97),
		GameTheme.GILT_BRIGHT)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", _make_tile_style(
		Color(0.045, 0.038, 0.032, 0.96), Color(0.60, 0.51, 0.34, 0.90)))
	btn.add_theme_stylebox_override("disabled", _make_tile_style(
		Color(0.05, 0.045, 0.04, 0.85), Color(0.40, 0.34, 0.22, 0.55)))
	if enabled:
		btn.pressed.connect(func() -> void:
			if not _leaving:
				on_press.call())
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
		# leading article first — otherwise "A recruiter's satchel" / "A captain's
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


## `primary` is the caller's declaration of what this button MEANS, and it is not
## inferable from the label. On a picker ("Leave it buried", "March on") it is
## the DECLINE standing beside live choices and must stay quieter than them; on
## a result screen ("Continue") it is the only way on and should carry the
## house forward-move plate. The first cut of the 2026-08-05 pass converted the
## helper wholesale and made the supply cache's walk-away the loudest control on
## a screen whose whole point is the three offers above it — caught on the
## render, which is why every caller now says which it is.
func _add_leave_button(label: String = "Continue", primary: bool = false) -> void:
	var btn: Button
	if primary:
		btn = GameTheme.make_primary_button(label, Vector2(200, 46), 17)
	else:
		btn = GameTheme.make_back_button(label, Vector2(180, 42))
	# Centered under the tile stack, not pinned to the bottom-left corner. Every
	# sibling stop puts its walk-away directly beneath the choices (the Shop's
	# "Leave the Wagon", Recruit's "Skip", Treasure's "Take gold
	# instead"); the road's stops were the one place the dismiss sat diagonally
	# across the screen from the thing it dismissed. (Screen audit 2026-07-21.)
	btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	btn.offset_left = -90
	btn.offset_right = 90
	btn.offset_top = 0
	btn.offset_bottom = 46 if primary else 42
	btn.pressed.connect(_go_to_map)
	GameTheme.arm_ui_press(btn, "commit" if primary else "back")
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
	# Measure the button instead of restating 180x42. `_add_leave_button` also
	# deals a 200x46 primary plate, and a rect narrower/shorter than
	# custom_minimum_size is grown RIGHTWARD and DOWNWARD — so the fixed numbers
	# seated the forward-move variant 10px right of the centre it claims.
	var half_w: float = maxf(btn.custom_minimum_size.x, 180.0) * 0.5
	var seat_h: float = maxf(btn.custom_minimum_size.y, 42.0)
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = size.x * 0.5 - half_w
	btn.offset_right = size.x * 0.5 + half_w
	btn.offset_top = y
	btn.offset_bottom = y + seat_h


func _go_to_map() -> void:
	if _leaving or _grid_pick_pending:
		return
	_leaving = true
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

	var btn = GameTheme.make_primary_button("Continue", Vector2(200, 46), 17)
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# ±100, i.e. half the plate's own 200 — a rect narrower than
	# custom_minimum_size grows rightward, so ±90 sat it 10px off centre.
	btn.offset_left = -100
	btn.offset_right = 100
	btn.offset_top = -150
	btn.offset_bottom = -104
	btn.pressed.connect(_go_to_map)
	GameTheme.arm_ui_press(btn, "commit")
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
	# THROUGH THE ONE RING ENGINE (2026-09-10). This was a Panel wearing a
	# StyleBoxFlat with a transparent background, a 4px border and
	# `set_corner_radius_all(600)` — which is a HARD-EDGED WIREFRAME CIRCLE by
	# another name, scaled 1→6 and faded. Exactly the defect the ring rebuild
	# removed from combat, surviving out here because it is spelled with a
	# StyleBox instead of a Line2D and so matched none of the searches that
	# found the others.
	#
	# (The same idiom on a card is FINE and is left alone: Card2D's keyword
	# device stamps are FILLED discs with a 1px rim — objects, not effects. The
	# tell is the transparent background plus a fat border.)
	Motion.ring(self, center, Color(accent.r, accent.g, accent.b, 0.65), {
		"radius": 22.0, "start_scale": 1.0, "end_scale": 6.0,
		"duration": 0.46, "width": 4.0, "z_index": 90,
		"trans": Tween.TRANS_CUBIC,
		# A result seal is a VERDICT, not a blast: no erosion, no wobble, and
		# the core kept off white so the outcome's own accent survives — the
		# same treatment the keyword pulse and the forecast reticle take.
		# WAKE 1.3, not the 3.2 impact default: `wake` is in THICKNESS units, so
		# on a 22px seal the inner falloff reaches almost to the centre and the
		# ring photographs as a filled bubble. See the same note on Combat's
		# keyword pulse.
		"wake": 1.3,
		"grit": 0.0, "wobble": 0.0, "hot": 0.30, "heat_gain": 0.30,
	})
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
	_grid_pick_taken = false  # a fresh picker re-arms the one-pick latch
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
		callback: Callable, footer: String = "",
		build_generation: int = -1) -> bool:
	if build_generation < 0:
		build_generation = _ui_build_generation
	var grid_ref: WeakRef = weakref(grid)
	var picker_alive := func() -> bool:
		if not is_inside_tree() or _leaving or _grid_pick_taken \
				or build_generation != _ui_build_generation:
			return false
		var live: GridContainer = grid_ref.get_ref() as GridContainer
		return live != null and is_instance_valid(live) \
			and not live.is_queued_for_deletion()
	if not CardTextureCache.has(data) \
			and not CardTextureCache.has_gallery(data):
		await CardArtAliases.prewarm_card_art(data)
		if not picker_alive.call():
			CardArtAliases.release_card_art(data)
			return false
		if not CardTextureCache.has(data):
			await CardTextureCache.bake_gallery(data, picker_alive)
		CardArtAliases.release_card_art(data)
	if not picker_alive.call():
		return false
	var use_gallery := not CardTextureCache.has(data) \
		and CardTextureCache.has_gallery(data)
	var live_grid: GridContainer = grid_ref.get_ref() as GridContainer
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
	card_node.card_id = String(data.get("id", ""))
	card_node.live_baked_mode = true
	card_node.gallery_baked_mode = use_gallery
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
	live_grid.add_child(slot)
	var idx := live_grid.get_child_count() - 1
	GameTheme.deal_in(slot, 0.04 + minf(float(idx), 12.0) * 0.025)
	GameTheme.hover_lift(slot, 1.025)
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	return picker_alive.call()



## ONE PICK PER GRID. claim_pop holds the frame for 100ms with every tile still
## live, so two clicks queued two callbacks — and the pick handlers re-read the
## state they mutate (_on_drill_pick banks `existing + 1`), so the pair COMPOUNDED:
## one "free pass" banked 2 drill stacks and could push past DRILL_MAX_STACKS.
## The latch clears in _make_card_grid, i.e. whenever a fresh picker is built.
func _on_grid_card_pressed(slot: Control, callback: Callable) -> void:
	if _leaving or _grid_pick_taken or _grid_pick_pending:
		return
	_grid_pick_taken = true
	_grid_pick_pending = true
	# Remembered so a handler can play a beat ON the card that was chosen —
	# the grid callbacks are bound to a deck index, not to the tile.
	_last_pick_slot = slot
	if slot != null and is_instance_valid(slot) \
		and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(slot)
		await get_tree().create_timer(0.10).timeout
	if _leaving or not is_inside_tree():
		_grid_pick_pending = false
		return
	_grid_pick_pending = false
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
			"No creature here can be drilled. The sergeant pays you to haul targets instead.")
		RunState.gain_gold(20)
		_show_drill_consolation()
		return
	var grid = _make_card_grid("Pick a creature to drill (+1/+1).", eligible.size())
	var build_generation := _ui_build_generation
	_add_leave_button()
	for i in eligible:
		var data = RunState.get_upgraded_card_data(i)
		var built: bool = await _add_card_to_grid(grid, data,
			_on_drill_pick.bind(i), "", build_generation)
		if not built:
			return


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
	_add_leave_button("Continue", true)


func _on_drill_pick(deck_index: int) -> void:
	_drill_index = deck_index
	# A creature drilled at an earlier yard picks up where it left off —
	# the new pass adds to its banked total instead of resetting it.
	_drill_stacks = int(RunState.get_upgrade_entry(deck_index, "drill").get("stacks", 0)) + 1
	RunState.apply_wayside_upgrade(deck_index,
		{"path": "drill", "stacks": _drill_stacks})
	AudioBank.play_sfx("upgrade_confirm")
	await _build_drill_push("+1/+1")


## `stamp` is the change this rebuild is REPORTING ("+1/+1"), stamped onto the
## recruit once the screen has settled. Empty = a silent rebuild.
func _build_drill_push(stamp: String = "") -> void:
	_clear_ui()
	var data = RunState.get_upgraded_card_data(_drill_index)
	var nm: String = String(data.get("name", "The recruit"))
	_add_header("THE DRILL YARD",
		"%s has banked +%d/+%d. Push for more, or march on?" \
		% [nm, _drill_stacks, _drill_stacks])

	# The creature on the yard, current stats showing. The WRAPPER persists
	# across passes (see _drill_card); only the writ inside it is re-baked,
	# so the card holds its place on the yard while its numbers change.
	var fresh := _drill_card == null or not is_instance_valid(_drill_card)
	if fresh:
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		wrapper.set_anchors_preset(Control.PRESET_CENTER)
		wrapper.offset_left = -360
		wrapper.offset_right = -135
		wrapper.offset_top = -130
		wrapper.offset_bottom = 170
		wrapper.pivot_offset = Vector2(112.5, 150.0)
		add_child(wrapper)
		_drill_card = wrapper
		GameTheme.deal_in(wrapper, 0.06)
	else:
		for old in _drill_card.get_children():
			old.queue_free()
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	card_node.live_baked_mode = true
	card_node.gallery_baked_mode = not CardTextureCache.has(data) \
		and CardTextureCache.has_gallery(data)
	_drill_card.add_child(card_node)

	var tiles: Array = []
	if _drill_stacks < DRILL_MAX_STACKS:
		tiles.append(_make_tile("Run another pass",
			"Even odds: +1/+1 more, or lose %d HP and the yard closes. Banked passes are kept." % DRILL_FAIL_HP,
			_on_drill_again))
	tiles.append(_make_tile("Continue",
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

	if stamp != "":
		# A freshly dealt writ gets to land before it is written on.
		if fresh:
			await get_tree().create_timer(0.26).timeout
		await _drill_stamp(stamp)


## Strike the pass onto the recruit standing on the yard. Guarded because the
## beat is awaited: the player can leave (Esc / Continue) while it runs.
func _drill_stamp(text: String) -> void:
	if _leaving or _drill_card == null or not is_instance_valid(_drill_card):
		return
	await GameTheme.writ_amend(self, _drill_card, text, Color(0.98, 0.86, 0.46))


## Every exit from the yard clears the recruit — _clear_ui deliberately spares
## it, so the result screen would otherwise draw its text straight over the card.
func _drill_dismiss() -> void:
	if _drill_card != null and is_instance_valid(_drill_card):
		_drill_card.queue_free()
	_drill_card = null


func _on_drill_again() -> void:
	if _drill_busy or _leaving:
		return
	_drill_busy = true
	if randi() % 2 == 0:
		_drill_stacks += 1
		RunState.apply_wayside_upgrade(_drill_index,
			{"path": "drill", "stacks": _drill_stacks})
		AudioBank.play_sfx("upgrade_confirm")
		if _drill_stacks >= DRILL_MAX_STACKS:
			# The last pass is still a pass: stamp it on the card the player has
			# been watching BEFORE the yard closes and the result page takes over.
			await _drill_stamp("+1/+1")
			if _leaving or not is_inside_tree():
				return
			var data = RunState.get_upgraded_card_data(_drill_index)
			_drill_dismiss()
			_show_result("The sergeant calls it: nothing more to teach. %s marches off the yard with +%d/+%d." \
				% [String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])
		else:
			await _build_drill_push("+1/+1")
			# The rebuild dealt fresh tiles — the yard is open for business again.
			_drill_busy = false
	else:
		# Non-lethal: the yard never takes the last drop.
		var to_lose: int = mini(DRILL_FAIL_HP, RunState.hero_hp - 1)
		RunState.damage_hero(maxi(0, to_lose))
		var data = RunState.get_upgraded_card_data(_drill_index)
		_drill_dismiss()
		_show_result("A training blade finds you instead — you lose %d HP and the sergeant closes the yard. %s keeps +%d/+%d." \
			% [maxi(0, to_lose), String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])


func _on_drill_stop() -> void:
	if _drill_busy or _leaving:
		return
	_drill_busy = true
	var data = RunState.get_upgraded_card_data(_drill_index)
	_drill_dismiss()
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
	tiles.append(_make_tile("Sell a card",
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
	tiles.append(_make_tile("Buy a hot meal", meal_note,
		_on_scales_meal, can_meal))
	_add_tile_stack(tiles)
	_add_leave_button()


func _build_scales_sell() -> void:
	var grid = _make_card_grid("Choose one card to sell.",
		RunState.deck.size())
	var build_generation := _ui_build_generation
	var back = GameTheme.make_back_button("Cancel", Vector2(180, 42))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_top = -70
	back.offset_right = 220
	back.offset_bottom = -28
	back.pressed.connect(_build_scales)
	add_child(back)
	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		var built: bool = await _add_card_to_grid(grid, data,
			_on_scales_sell_pick.bind(i),
			"%d gold" % _sell_price(RunState.deck[i]), build_generation)
		if not built:
			return


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
			"No keyword here can be moved. He pays you a coin for the trouble.")
		RunState.gain_gold(15)
		var lbl := GameTheme.make_label("Gained 15 gold.", 22, GameTheme.KEYWORD_GOLD)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		lbl.offset_left = -300
		lbl.offset_right = 300
		lbl.offset_top = -20
		lbl.offset_bottom = 30
		add_child(lbl)
		_add_leave_button("Continue", true)
		return
	var grid = _make_card_grid("Choose who gives up a keyword.", valid.size())
	var build_generation := _ui_build_generation
	_add_leave_button()
	for i in valid:
		var data = RunState.get_upgraded_card_data(i)
		var built: bool = await _add_card_to_grid(grid, data,
			_on_banner_donor_pick.bind(i), "", build_generation)
		if not built:
			return


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
		"%s carries more than one keyword. Which one moves?" % String(data.get("name", "The creature")))
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
	var build_generation := _ui_build_generation
	var back = GameTheme.make_back_button("Back", Vector2(200, 42))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_top = -70
	back.offset_right = 240
	back.offset_bottom = -28
	back.pressed.connect(_build_banner_donor)
	add_child(back)
	for i in receivers:
		var data = RunState.get_upgraded_card_data(i)
		var built: bool = await _add_card_to_grid(grid, data,
			_on_banner_receiver_pick.bind(i), "", build_generation)
		if not built:
			return


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
	AudioBank.play_sfx("upgrade_confirm")
	# Pin the standard where the player can see it land — on the taker's own
	# writ, while the rest of the slate is still on screen. Without this the
	# whole trade resolved as a sentence on the next page.
	await GameTheme.writ_amend(self, _last_pick_slot, disp.to_upper(),
		GameTheme.KEYWORD_GOLD)
	if _leaving or not is_inside_tree():
		return
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
		{"id": "banner_case", "head": "A recruiter's satchel",
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
