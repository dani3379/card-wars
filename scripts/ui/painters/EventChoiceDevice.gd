extends Button
class_name EventChoiceDevice
## Compact, physical choice device used by the four ordinary-event layouts.
## It deliberately avoids the folio's Roman-numeral ladder.

const BLUE_INK := Color(0.47, 0.83, 0.75, 1.0)
const BLUE_BRIGHT := Color(0.66, 0.97, 0.88, 1.0)

const LOCK_INK := Color(0.60, 0.56, 0.50, 1.0)
const LOCK_REASON_INK := Color(0.74, 0.46, 0.38, 1.0)

var _rest_scale := Vector2.ONE
var _accent := Color(0.78, 0.58, 0.24)
var _hover_text := ""
var _hover_callback: Callable
var _hover_rule: ColorRect = null
var _column: VBoxContainer = null
var _headline: Label = null
var _effect: RichTextLabel = null
var _kind := ""


func configure(kind: String, headline_text: String, effect_text: String,
		body_text: String, is_blue: bool, on_press: Callable,
		on_hover: Callable, accent: Color) -> void:
	flat = false
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accent = BLUE_INK if is_blue else accent
	_accent = accent
	_kind = kind
	_hover_text = body_text
	_hover_callback = on_hover
	_build_style(kind, accent)
	_build_copy(kind, headline_text, effect_text, is_blue, accent)
	if on_press.is_valid():
		pressed.connect(on_press)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## Every tile used to be filled with a near-black at 74–82% alpha and then laid
## on an ink band that was ALREADY near-black — so the fill was mathematically a
## no-op. Measured across the ritual family, tile interiors sat 0.3–2.1 L away
## from the bare gutter beside them (contrast ratio ≈1.01): only the 1px border
## existed, and the answers read as wireframes floating on the page rather than
## as objects laid on it. Each fill is now LIGHTER than the band it sits on, and
## carries a drop shadow, so a choice is a thing you could pick up.
func _build_style(kind: String, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.085, 0.070, 0.055, 0.88)
	normal.border_color = Color(color.r, color.g, color.b, 0.56)
	normal.set_border_width_all(1)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 11
	normal.content_margin_bottom = 11
	normal.shadow_color = Color(0, 0, 0, 0.55)
	normal.shadow_size = 7
	normal.shadow_offset = Vector2(0, 3)
	match kind:
		"confrontation":
			normal.bg_color = Color(0.095, 0.072, 0.055, 0.86)
			normal.border_width_left = 4
			normal.corner_radius_top_right = 5
			normal.corner_radius_bottom_right = 5
		"character":
			normal.bg_color = Color(0.092, 0.072, 0.056, 0.86)
			normal.set_border_width_all(0)
			normal.border_width_left = 4
			normal.corner_radius_top_right = 5
			normal.corner_radius_bottom_right = 5
		"location":
			normal.bg_color = Color(0.082, 0.076, 0.066, 0.90)
			normal.border_width_top = 3
			normal.corner_radius_top_left = 22
			normal.corner_radius_top_right = 22
		"bargain":
			# Warmest of the set: a ledger entry is written on paper.
			normal.bg_color = Color(0.118, 0.090, 0.052, 0.92)
			normal.border_width_left = 2
			normal.border_width_right = 2
		"ritual":
			normal.bg_color = Color(0.100, 0.085, 0.110, 0.94)
			normal.set_corner_radius_all(28)
			normal.set_border_width_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(color.r * 0.12, color.g * 0.10,
		color.b * 0.07, 0.92)
	hover.border_color = Color(color.r, color.g, color.b, 0.95)
	var pressed_style := hover.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(color.r * 0.18, color.g * 0.14,
		color.b * 0.09, 0.96)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", hover)


func _build_copy(kind: String, headline_text: String, effect_text: String,
		is_blue: bool, color: Color) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 18
	column.offset_right = -18
	column.offset_top = 9
	column.offset_bottom = -9
	# Top-aligned, not centred. Centring re-centred each tile's column
	# independently, so a two-line answer pushed its headline UP while its
	# one-line neighbour sat low — measured as a 52px ragged cap-top across three
	# sibling buttons, and 79px across four. Peers in a row now share a baseline.
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_column = column

	# No kind label. REPLY/ROAD/TERMS/VOW printed above every answer told the
	# player what they already knew from the stage they were standing on, in the
	# smallest type on the screen — the same noise the card faces shed when the
	# repeated SPELL footer came off. The stage says the kind; the tile says the
	# choice. Blue options keep the diamond, which is the one mark that carries
	# information, and it rides the headline where the eye already is.

	# A short rule establishes the hierarchy at rest, then sweeps wider on
	# hover like fresh ink pulled beneath the headline.
	var centred := kind in ["location", "ritual"]
	var hover_rule := ColorRect.new()
	hover_rule.color = Color(color.r, color.g, color.b, 0.62)
	hover_rule.custom_minimum_size = Vector2(30, 2)
	# The tick must share the headline's axis. Left-flush under a centred
	# headline gave every tile a third alignment to argue with.
	hover_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centred \
		else Control.SIZE_SHRINK_BEGIN
	hover_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hover_rule)
	_hover_rule = hover_rule

	var headline := Label.new()
	headline.text = ("◆  " + headline_text) if is_blue else headline_text
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER \
		if kind in ["location", "ritual"] else HORIZONTAL_ALIGNMENT_LEFT
	headline.add_theme_font_size_override("font_size", 24 if kind == "character" else 22)
	headline.add_theme_color_override("font_color",
		BLUE_BRIGHT if is_blue else GameTheme.IVORY)
	headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	headline.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_display:
		headline.add_theme_font_override("font", GameTheme.font_display)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(headline)
	_headline = headline

	if not effect_text.is_empty():
		var effect := RichTextLabel.new()
		effect.bbcode_enabled = true
		effect.fit_content = true
		effect.scroll_active = false
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Centred kinds must centre the OUTCOME too. Leaving it left-flush under a
		# centred headline gave every tile a third alignment axis to argue with,
		# and it is what orphaned separators onto their own line ("· +1 rare card").
		effect.text = ("[center]" + effect_text + "[/center]") if centred else effect_text
		# 18 everywhere. The outcome is the most decision-relevant string on the
		# page — the price the player is weighing — and at 17 it sat in
		# COPY_STYLE §11's caption register (15–17) instead of reading (>=18).
		effect.add_theme_font_size_override("normal_font_size", 18)
		effect.add_theme_color_override("default_color",
			BLUE_INK if is_blue else GameTheme.KEYWORD_GOLD)
		effect.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
		effect.add_theme_constant_override("outline_size", 2)
		if GameTheme.font_body:
			effect.add_theme_font_override("normal_font", GameTheme.font_body)
		effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(effect)
		_effect = effect


## A refused option must still read as an option. The old treatment dimmed the
## whole Button with `modulate`, which multiplied the border down to roughly a
## third of its alpha — on the round ritual seals the tile simply looked like it
## had failed to draw. A locked tile keeps its full shape and loses its warmth
## instead: cold ink, flatter fill, and the reason on its OWN line in its own
## register rather than appended to the gold outcome string (that concatenation
## is what pushed text out the bottom of the Sin-Eater's seal).
func set_locked(reason: String) -> void:
	disabled = true
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	tooltip_text = reason
	_hover_callback = Callable()

	# Every state is cut from the NORMAL box, never from the theme's own
	# `disabled` box: that default carries no border and no corner radius, so a
	# disabled device used to render as bare floating text with its frame gone —
	# which is what made the Sin-Eater's locked seal look like a draw failure.
	var base := get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	base.bg_color = Color(0.030, 0.028, 0.026, 0.66)
	base.border_color = Color(LOCK_INK.r, LOCK_INK.g, LOCK_INK.b, 0.50)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, base.duplicate() as StyleBoxFlat)

	if _headline != null:
		_headline.add_theme_color_override("font_color", LOCK_INK)
	if _effect != null:
		_effect.add_theme_color_override("default_color",
			Color(LOCK_INK.r, LOCK_INK.g, LOCK_INK.b, 0.78))
		# The outcome carries inline [color] spans (costs run red), and a
		# default_color override cannot reach inside those. Modulate cools the
		# whole line so a refused offer stops shouting its price.
		_effect.modulate = Color(0.80, 0.78, 0.74, 1.0)
	if _hover_rule != null:
		_hover_rule.color = Color(LOCK_INK.r, LOCK_INK.g, LOCK_INK.b, 0.45)

	if reason.is_empty() or _column == null:
		return
	# Caption register (COPY_STYLE §11): the reason is an aside, not the offer.
	# No "Unavailable:" prefix — a tile this cold has already said that.
	var note := Label.new()
	note.text = reason
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = _headline.horizontal_alignment if _headline != null \
		else HORIZONTAL_ALIGNMENT_LEFT
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", LOCK_REASON_INK)
	note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	note.add_theme_constant_override("outline_size", 2)
	if GameTheme.font_body:
		note.add_theme_font_override("font", GameTheme.font_body)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(note)


func _on_mouse_entered() -> void:
	if disabled:
		return
	if _hover_callback.is_valid():
		_hover_callback.call(_hover_text, true)
	if UserSettings.reduce_motion:
		return
	z_index = 4
	pivot_offset = size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.025, 1.025), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color(1.08, 1.05, 0.98, 1.0), 0.10)
	if _hover_rule != null:
		tween.tween_property(_hover_rule, "custom_minimum_size", Vector2(150, 2), 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_mouse_exited() -> void:
	if disabled:
		return
	if _hover_callback.is_valid():
		_hover_callback.call("", false)
	z_index = 0
	if UserSettings.reduce_motion:
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", _rest_scale, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)
	if _hover_rule != null:
		tween.tween_property(_hover_rule, "custom_minimum_size", Vector2(30, 2), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func mark_resolved(stamp_text: String, is_bad: bool = false) -> void:
	# The selected device survives onto the result page as a physical receipt.
	# It no longer accepts input; a tilted ink stamp records the consequence.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_hover_callback = Callable()
	modulate = Color(0.90, 0.88, 0.82, 0.94)
	var stamp := Label.new()
	stamp.name = "OutcomeStamp"
	stamp.text = stamp_text.to_upper()
	stamp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stamp.offset_left = -126
	stamp.offset_right = -12
	stamp.offset_top = 12
	stamp.offset_bottom = 42
	stamp.rotation = -0.075
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.add_theme_font_size_override("font_size", 18)
	var ink := Color(0.95, 0.34, 0.22) if is_bad else _accent
	stamp.add_theme_color_override("font_color", ink)
	stamp.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01, 0.92))
	stamp.add_theme_constant_override("outline_size", 4)
	if GameTheme.font_display:
		stamp.add_theme_font_override("font", GameTheme.font_display)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stamp)