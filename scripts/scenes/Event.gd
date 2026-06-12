extends Control
## Event.gd — Random choice encounters (~39). The pool is FORMAT-diverse on
## purpose (2026-06-12 remake — "the structure of the old ones was all the
## same"): besides the classic 2-3-trade screens, events run on reusable
## interaction engines:
##   risk_loop   — push-your-luck "do it again?" (spring sips, choir verses,
##                 orchard harvest, woodcutter swings)
##   dice_run    — pot-based wager runs (Bone Pit add-mode, Coin That Won't
##                 Land double-or-nothing)
##   roll_table  — committed-action mystery outcomes (fork roads, drowned
##                 bell, forcing the bridge)
##   pawn_appraisal / stranger_hand / sacrifice / transform / copy / remove
##                 — card-tactile pickers
##   hidden+tell — Three Warm Handles, Rotting Carnival (the tell is the game)
##   follow_up   — multi-stage branches (lantern, calf, answering well)
## Some are state-gated (low HP, has-curse, deck size, act, prior visits).
## Quick ONE-DECISION roadside stops are NOT events — they're the Wayside
## scene's verbs (scripts/scenes/Wayside.gd).

const MAP_SCENE = "res://scenes/map.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

# Nodes that survive across UI rebuilds within a single event (initial choice
# screen → result screen → continue). Modal sub-pickers (remove/butcher) hide
# the art via _set_event_art_visible() so deck cards stay readable.
const PRESERVE_NODES := [
	"Background", "Atmosphere", "EventArt",
	"EventOverlayLeft",
]

var _event_id: String = ""
var _event_data: Dictionary = {}
# Current screen's body: starts as _event_data and gets swapped to a follow_up
# sub-dict when the player picks a branching choice. Multi-stage events read
# desc + choices from this; the top-level event title stays on _event_data.
var _current_node: Dictionary = {}


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "event")
	AudioBank.play_music("event")
	_pick_event()
	_build_ui()
	GameTheme.make_settings_gear(self)


func _pick_event() -> void:
	# Phase 2.5 — at a bridge node the crossing IS the event, the first
	# time. The plate painted the bridge on the road in; the room honors it.
	# Repeat bridges fall through to the normal roll (the gate below keeps
	# the crossing eligible there, competing like any seen event).
	if RunState.current_bridge and EVENTS.has("the_crossing") \
			and not RunState.events_seen.has("the_crossing"):
		_event_id = "the_crossing"
		_event_data = EVENTS[_event_id]
		_current_node = _event_data
		RunState.events_seen.append(_event_id)
		return
	# Two filters in order: (1) gate predicates must pass for the current run
	# state (low-HP, has-curse, deck-size, act, prior-events-seen), (2) prefer
	# unseen events so the player explores the roster before repeating.
	# If everything's filtered out, relax (2) first — relaxing (1) would show
	# events that lie about their preconditions (e.g. Tooth-Witch at full HP).
	var gate_passing: Array = []
	for id in EVENTS:
		if _event_gate_passes(id):
			gate_passing.append(id)
	if gate_passing.is_empty():
		# No gated event qualifies — fall back to every event ignoring gates
		# so we still hand the player *something* (better than silently
		# routing them to the map without an event room).
		gate_passing = EVENTS.keys()
	var unseen: Array = []
	for id in gate_passing:
		if not RunState.events_seen.has(id):
			unseen.append(id)
	var available: Array = unseen if unseen.size() > 0 else gate_passing
	available.shuffle()
	_event_id = available[0]
	_event_data = EVENTS[_event_id]
	_current_node = _event_data
	RunState.events_seen.append(_event_id)


# Returns true if the event's gate (if any) is satisfied by current RunState.
# Events without a "gate" field are always eligible. Gates are encoded as
# simple type+param dicts so adding a new gate is one match arm here, not a
# new function per event.
func _event_gate_passes(event_id: String) -> bool:
	var event = EVENTS.get(event_id, {})
	var gate: Dictionary = event.get("gate", {})
	if gate.is_empty():
		return true
	match gate.get("type", ""):
		"has_curse":
			for cid in RunState.deck:
				if CardDB.is_curse(cid):
					return true
			return false
		"hp_below_pct":
			# value is a 0..1 fraction (0.5 = below half HP)
			var pct: float = float(RunState.hero_hp) / float(maxi(1, RunState.hero_max_hp))
			return pct < float(gate.get("value", 0.5))
		"gold_at_least":
			return RunState.gold >= int(gate.get("value", 0))
		"at_bridge":
			# Phase 2.5 — only rolls where the road in crossed a river.
			return RunState.current_bridge
		"deck_at_least":
			return RunState.deck.size() >= int(gate.get("value", 0))
		"has_nonstarting_relic":
			for rid in RunState.relics:
				var r = RelicDB.get_relic(rid)
				if r.get("tier", "starting") != "starting":
					return true
			return false
		"act_at_least":
			return RunState.get_act() >= int(gate.get("value", 1))
		"seen_all":
			# Recurring NPC chain: every id in gate.events must be in events_seen.
			for needed in gate.get("events", []):
				if not RunState.events_seen.has(needed):
					return false
			return true
		"all":
			# Compound — every sub-gate must pass. Used by Beekeeper Again /
			# Beekeeper Returns to combine act + seen_all checks.
			for sub in gate.get("gates", []):
				if not _event_gate_passes_dict(sub):
					return false
			return true
	return true


# Helper for "all" gate type — re-runs the same dispatch on a sub-gate dict
# without needing a wrapping event entry. Extracted so we don't recurse
# through EVENTS.get() and risk a missing-key warning.
func _event_gate_passes_dict(gate: Dictionary) -> bool:
	match gate.get("type", ""):
		"has_curse":
			for cid in RunState.deck:
				if CardDB.is_curse(cid):
					return true
			return false
		"hp_below_pct":
			var pct: float = float(RunState.hero_hp) / float(maxi(1, RunState.hero_max_hp))
			return pct < float(gate.get("value", 0.5))
		"gold_at_least":
			return RunState.gold >= int(gate.get("value", 0))
		"at_bridge":
			# Phase 2.5 — only rolls where the road in crossed a river.
			return RunState.current_bridge
		"deck_at_least":
			return RunState.deck.size() >= int(gate.get("value", 0))
		"has_nonstarting_relic":
			for rid in RunState.relics:
				var r = RelicDB.get_relic(rid)
				if r.get("tier", "starting") != "starting":
					return true
			return false
		"act_at_least":
			return RunState.get_act() >= int(gate.get("value", 1))
		"seen_all":
			for needed in gate.get("events", []):
				if not RunState.events_seen.has(needed):
					return false
			return true
	return true


func _clear_ui() -> void:
	for child in get_children():
		if not (child.name in PRESERVE_NODES):
			child.queue_free()


func _build_ui() -> void:
	_clear_ui()

	var img_tex := _load_event_image()
	var has_img: bool = img_tex != null
	if has_img:
		_ensure_fullscreen_art(img_tex)
	_set_event_art_visible(true)

	# Left-column layout: title → body → choices stack down a fixed-width
	# column anchored to the left edge. The horizontal scrim behind
	# (EventOverlayLeft) pools the column in a darker region; the right
	# ~half of the art stays fully visible. Text and art share the screen
	# instead of competing for the same pixels.
	const COLUMN_LEFT := 80
	const COLUMN_WIDTH := 620

	var title := _make_event_title(_event_data.name)
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = COLUMN_LEFT
	title.offset_top = 72
	title.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	title.offset_bottom = 132
	add_child(title)

	# Body text comes from _current_node — at event start that's _event_data,
	# but a branching `follow_up` choice replaces it with a sub-dict so the
	# same _build_ui() call paints whichever stage we're on.
	var desc = _make_event_desc(_current_node.desc)
	add_child(desc)

	# Choice column anchored bottom-left. Frameless gem-prefixed entries
	# (Hades / StS dialogue beat-by-beat) — only the column anchor changed
	# from center to left, the cinematic style is preserved.
	var num_choices: int = _current_node.choices.size()
	# Tall enough for three stacked lines: headline + gold outcome + dim flavor.
	# 118 keeps a 3-choice stack (stack_h 378, top y≈412) clear of the desc box
	# (bottom 400) on the 900px viewport, while still absorbing a rare two-line
	# outcome label. Bumping it to 124 made the top choice graze the description.
	var choice_h: int = 118
	var stack_h: int = num_choices * choice_h + (num_choices - 1) * 12
	var choices_vbox := VBoxContainer.new()
	choices_vbox.name = "ChoicesBox"
	choices_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	choices_vbox.offset_left = COLUMN_LEFT
	choices_vbox.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	choices_vbox.offset_top = -(stack_h + 110)
	choices_vbox.offset_bottom = -110
	choices_vbox.add_theme_constant_override("separation", 12)
	choices_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(choices_vbox)

	for choice in _current_node.choices:
		choices_vbox.add_child(_make_event_choice(choice, choice_h))

	var skip_btn = GameTheme.make_back_button("LEAVE", Vector2(140, 40))
	skip_btn.position = Vector2(40, 830)
	skip_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE))
	add_child(skip_btn)


# ── Fullscreen event illustration + readability gradients ────────────────

func _ensure_fullscreen_art(tex: Texture2D) -> void:
	var bg = get_node_or_null("Background")
	if bg:
		bg.visible = false

	if not has_node("EventArt"):
		var art := TextureRect.new()
		art.name = "EventArt"
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# COVERED fills the viewport, cropping overflow so the art bleeds to
		# every edge — no letterboxing on widescreens.
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		move_child(art, 1)  # behind Atmosphere so the vignette still tints corners

	# Left-column scrim: deep dark wash on the left, fading to clear across
	# the middle. Pools the text column in a quiet region while the right
	# ~half of the art stays fully visible. Replaces the older top+bottom
	# vertical pair — that one darkened bands the text rarely sat in (the
	# 3-choice stack landed mid-screen, in fully un-darkened art).
	if not has_node("EventOverlayLeft"):
		var scrim := _make_horizontal_gradient_overlay(0.78, 0.0)
		scrim.name = "EventOverlayLeft"
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(scrim)
		_move_after_atmosphere(scrim)


func _move_after_atmosphere(node: Node) -> void:
	# Place node right after Atmosphere so it darkens art + vignette but stays
	# below the UI labels.
	for i in get_child_count():
		if get_child(i).name == "Atmosphere":
			move_child(node, i + 1)
			return


func _make_horizontal_gradient_overlay(darkness_left: float,
		darkness_right: float) -> ColorRect:
	# Horizontal alpha gradient via tiny canvas-item shader. The smoothstep
	# holds the left ~30% at `darkness_left`, transitions softly across the
	# middle band (UV 0.30 → 0.62), and holds at `darkness_right` past 62%.
	# That leaves the right half of the art untouched while pooling the text
	# column in a quiet darker region — the transition itself is the soft
	# "mask" that separates the two zones without a hard panel edge.
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float darkness_left : hint_range(0.0, 1.0) = 0.0;
uniform float darkness_right : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float t = smoothstep(0.30, 0.62, UV.x);
	float a = mix(darkness_left, darkness_right, t);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
	mat.shader = shader
	mat.set_shader_parameter("darkness_left", darkness_left)
	mat.set_shader_parameter("darkness_right", darkness_right)
	rect.material = mat
	return rect


func _set_event_art_visible(v: bool) -> void:
	for n in ["EventArt", "EventOverlayLeft"]:
		var node = get_node_or_null(n)
		if node:
			node.visible = v


# ── Description label (outlined for readability over art) ────────────────

func _make_event_title(text: String) -> RichTextLabel:
	# Standalone left-aligned title. RichTextLabel + BBCode so event copy can
	# embed [color=#...], [wave], [shake], [pulse] inline — see the "abyss" pop
	# in the design ref. Keeps the same display font + purple tint as the old
	# Label-based version; default_color replaces font_color on RichTextLabel.
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.text = text
	rt.add_theme_font_size_override("normal_font_size", 34)
	rt.add_theme_font_size_override("bold_font_size", 34)
	rt.add_theme_font_size_override("italics_font_size", 34)
	rt.add_theme_color_override("default_color", GameTheme.SPELL_PURPLE)
	rt.add_theme_color_override("font_outline_color",
		Color(GameTheme.SPELL_PURPLE.r, GameTheme.SPELL_PURPLE.g,
			GameTheme.SPELL_PURPLE.b, 0.25))
	rt.add_theme_constant_override("outline_size", 6)
	rt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	rt.add_theme_constant_override("shadow_offset_x", 0)
	rt.add_theme_constant_override("shadow_offset_y", 2)
	rt.add_theme_constant_override("shadow_outline_size", 4)
	if GameTheme.font_display:
		rt.add_theme_font_override("normal_font", GameTheme.font_display)
		rt.add_theme_font_override("bold_font", GameTheme.font_display)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rt


func _make_event_desc(text: String) -> RichTextLabel:
	# RichTextLabel + BBCode so event copy can highlight individual words with
	# inline [color] / [wave] / [shake] / [pulse] tags. Otherwise identical to
	# the old Label: same body font, thin outline + drop shadow combo.
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.text = text
	rt.add_theme_font_size_override("normal_font_size", 22)
	rt.add_theme_font_size_override("bold_font_size", 22)
	rt.add_theme_font_size_override("italics_font_size", 22)
	rt.add_theme_color_override("default_color", GameTheme.IVORY)
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	rt.add_theme_constant_override("outline_size", 3)
	rt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	rt.add_theme_constant_override("shadow_offset_x", 0)
	rt.add_theme_constant_override("shadow_offset_y", 2)
	rt.add_theme_constant_override("shadow_outline_size", 4)
	if GameTheme.font_body:
		rt.add_theme_font_override("normal_font", GameTheme.font_body)
		rt.add_theme_font_override("bold_font", GameTheme.font_body)
	rt.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rt.offset_left = 80
	rt.offset_right = 700
	rt.offset_top = 160
	rt.offset_bottom = 400
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rt


# ── Frameless cinematic choice ───────────────────────────────────────────

func _make_event_choice(choice: Dictionary, height: int) -> Button:
	# choice.label is "Headline\n\nBody text wrapped\nover several lines."
	# The body's hard line breaks were sized for the old rectangle buttons —
	# rejoin into a single paragraph and let autowrap reflow at the new width.
	var headline_text: String
	var body_text: String = ""
	var effect_text: String = ""
	if choice.get("hidden", false):
		# Hidden-info choices (Three Doors): the *effect* is concealed; we
		# replace the headline with "???" and use the `tell` field as the
		# only flavor — a small clue the attentive player can read. No outcome
		# line, on purpose: the mystery IS the mechanic.
		headline_text = "???"
		body_text = String(choice.get("tell", ""))
	else:
		var parts: PackedStringArray = choice.label.split("\n\n", true, 1)
		headline_text = parts[0]
		if parts.size() > 1:
			body_text = parts[1].strip_edges().replace("\n", " ")
		# The mechanical outcome. Branch picks (follow_up, no desc) leave this
		# empty and show only the flavor beat — the payoff is the next screen.
		effect_text = String(choice.get("desc", ""))
	return _make_frameless_choice(headline_text, effect_text, body_text, height,
			_resolve_choice.bind(choice))


func _make_frameless_choice(headline_text: String, effect_text: String,
		body_text: String, height: int, on_press: Callable) -> Button:
	# Returns a transparent Button containing layered visuals — gem ornament
	# on the left, then a stacked column: headline, the mechanical OUTCOME line
	# (gold — what the player actually gets), then a dim flavor beat. The whole
	# strip is the click target; hover shifts the headline to gold and brightens
	# the gem. effect_text is empty for narrative branch picks (follow_up) and
	# for plain Continue/Leave buttons, which then show no outcome line.
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(560, height)
	btn.focus_mode = Control.FOCUS_NONE
	# SIZE_FILL so the button stretches to the column width (used to be
	# SHRINK_CENTER for the old centered VBox); the gem stays glued to
	# the column's left edge instead of floating with the headline.
	btn.size_flags_horizontal = Control.SIZE_FILL

	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, transparent)

	if on_press.is_valid():
		btn.pressed.connect(on_press)

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
	gem.modulate = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.85)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(gem)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var headline := Label.new()
	headline.text = headline_text
	headline.add_theme_font_size_override("font_size", 26)
	headline.add_theme_color_override("font_color", GameTheme.IVORY)
	headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.80))
	headline.add_theme_constant_override("outline_size", 3)
	headline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	headline.add_theme_constant_override("shadow_offset_x", 0)
	headline.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		headline.add_theme_font_override("font", GameTheme.font_display)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(headline)

	# Outcome line — the mechanical payload, rendered in gold so it reads as
	# "this is what happens" distinct from the ivory headline and dim flavor.
	# RichTextLabel so a desc can tint gains/costs inline ([color] tags) when a
	# choice wants to; plain text falls back to the gold default color.
	if not effect_text.is_empty():
		var fx := RichTextLabel.new()
		fx.bbcode_enabled = true
		fx.fit_content = true
		fx.scroll_active = false
		fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fx.text = effect_text
		fx.custom_minimum_size = Vector2(500, 0)
		fx.add_theme_font_size_override("normal_font_size", 17)
		fx.add_theme_font_size_override("bold_font_size", 17)
		fx.add_theme_color_override("default_color", GameTheme.KEYWORD_GOLD)
		fx.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		fx.add_theme_constant_override("outline_size", 3)
		fx.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
		fx.add_theme_constant_override("shadow_offset_y", 1)
		if GameTheme.font_body:
			fx.add_theme_font_override("normal_font", GameTheme.font_body)
			fx.add_theme_font_override("bold_font", GameTheme.font_body)
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(fx)

	if not body_text.is_empty():
		var body := Label.new()
		body.text = body_text
		body.add_theme_font_size_override("font_size", 19)
		body.add_theme_color_override("font_color", GameTheme.DESC_DIM)
		body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.70))
		body.add_theme_constant_override("outline_size", 2)
		body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
		body.add_theme_constant_override("shadow_offset_x", 0)
		body.add_theme_constant_override("shadow_offset_y", 1)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(500, 0)
		if GameTheme.font_body:
			body.add_theme_font_override("font", GameTheme.font_body)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(body)

	btn.mouse_entered.connect(func() -> void:
		gem.modulate = Color(GameTheme.GILT_BRIGHT.r, GameTheme.GILT_BRIGHT.g, GameTheme.GILT_BRIGHT.b, 1.0)
		headline.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD)
	)
	btn.mouse_exited.connect(func() -> void:
		gem.modulate = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.85)
		headline.add_theme_color_override("font_color", GameTheme.IVORY)
	)

	return btn


func _load_event_image() -> Texture2D:
	# Bespoke art (keyed by event id) always wins; an optional "art" field
	# names another event's image as a stand-in, so a new event ships with a
	# fitting plate immediately and upgrades itself the moment a bespoke
	# assets/events/<event_id>.png lands.
	for key in [_event_id, String(_event_data.get("art", ""))]:
		if String(key) == "":
			continue
		for ext in ["png", "jpg"]:
			var p := "res://assets/events/%s.%s" % [key, ext]
			if ResourceLoader.exists(p):
				return load(p)
	return null


## Effect types that own the screen — each one rebuilds the UI into a card
## picker (or similar) that lives until the player commits. _resolve_choice
## must NOT fade to map after applying these; the picker owns the next
## transition. Without this list the fade-tween fires 0.28s after the
## picker opens and the player sees the picker briefly before being
## whisked to the map with no input.
## CONSTRAINT: at most ONE modal effect per choice. Two would have the
## second clobber the first's UI on rebuild. Pair a modal with non-modal
## effects freely (the non-modals apply first as a cost), but never two
## pickers in the same `effects` array.
const MODAL_EFFECTS := [
	"copy_card", "remove_choice", "remove_choice_multi", "remove_choice_filtered",
	"butcher_buff", "mirror_twin_buff",
	"upgrade_choice", "upgrade_choice_multi",
	"stranger_hand_pick", "relic_sacrifice_pick", "sacrifice_pick",
	"transform_choice", "dice_run", "risk_loop", "pawn_appraisal",
]


func _resolve_choice(choice: Dictionary) -> void:
	var effects = choice.get("effects", [])
	var follow_up: Dictionary = choice.get("follow_up", {})

	# A choice with no effects AND no follow-up is the "leave" option — exit
	# straight to the map. A choice with a follow-up always swaps screens,
	# even if its effects array is empty (the second stage IS the payoff).
	if effects.is_empty() and follow_up.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
		return

	# Split effects three ways: copy_card (needs a counted pre-text), other
	# modal pickers (own the next screen, no fade), and plain effects (apply
	# silently and either show_result or fade).
	var copy_count := 0
	var modal_effects: Array = []
	var other_effects: Array = []
	for effect in effects:
		if effect.type == "copy_card":
			copy_count += 1
		elif effect.type in MODAL_EFFECTS:
			modal_effects.append(effect)
		else:
			other_effects.append(effect)
	# Apply all immediate effects first (gold, damage, etc.).
	var result_text := ""
	for effect in other_effects:
		result_text += _apply_effect(effect) + "\n"

	# Multi-stage: swap the current screen to the follow-up sub-dict and
	# rebuild the UI. Stage-1 effects (if any) already landed above; the
	# stage-2 desc + choices read from `_current_node`. We don't show the
	# stage-1 result text — the follow-up flavor IS the transition beat.
	if not follow_up.is_empty():
		_current_node = follow_up
		_build_ui()
		return

	# Start interactive copy picker if any copy_card effects exist.
	if copy_count > 0:
		_start_copy_mode(copy_count, result_text.strip_edges())
		return

	# Other modal pickers: each opens its own UI and handles the post-pick
	# transition via _show_result → Continue button. Return early so we don't
	# fade out from underneath them. Pre-amble result_text from non-modal
	# co-effects is dropped — the visual HP/gold change is the receipt.
	if modal_effects.size() > 0:
		# Carry the non-modal co-effect receipt into the picker's result screen
		# instead of dropping it.
		_pending_pre_text = result_text.strip_edges()
		for effect in modal_effects:
			_apply_effect(effect)
		return

	if result_text.strip_edges().is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
	else:
		_show_result(result_text)


func _apply_effect(effect: Dictionary) -> String:
	match effect.type:
		"heal_full":
			RunState.hero_hp = RunState.hero_max_hp
			return "Healed to full HP!"
		"heal":
			RunState.heal_hero(effect.value)
			return "Healed %d HP." % effect.value
		"damage":
			RunState.damage_hero(effect.value)
			return "Took %d damage." % effect.value
		"gold":
			if effect.value > 0:
				RunState.gain_gold(effect.value)
			else:
				RunState.gold += effect.value  # losses bypass ectoplasm
			if effect.value > 0:
				return "Gained %d gold." % effect.value
			else:
				return "Lost %d gold." % abs(effect.value)
		"remove_cards":
			var count = effect.value
			for i in range(count):
				if RunState.deck.size() > 1:
					var idx = randi() % RunState.deck.size()
					RunState.remove_card_at(idx)
			return "Removed %d card(s)." % count
		"add_rare":
			var rares = CardDB.cards_of_rarity("rare")
			if rares.size() > 0:
				rares.shuffle()
				RunState.add_card(rares[0])
				var data = CardDB.get_card_data(rares[0])
				return "Added %s to deck!" % data.name
			return ""
		"add_curse":
			RunState.add_card(CardDB.random_curse_id())
			return "A Curse was added to your deck."
		"random_relic":
			var choices = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
			if choices.size() > 0:
				RunState.add_relic(choices[0])
				var relic = RelicDB.get_relic(choices[0])
				return "Gained relic: %s" % relic.name
			return "No relics available."
		"upgrade_random":
			var upgradeable: Array = []
			for i in range(RunState.deck.size()):
				if RunState.is_card_upgraded(i):
					continue
				if not CardDB.is_upgradeable(RunState.deck[i]):
					continue
				upgradeable.append(i)
			if upgradeable.size() > 0:
				var idx = upgradeable[randi() % upgradeable.size()]
				RunState.upgrade_card(idx, "plus")
				return "Upgraded a card!"
			return "No cards to upgrade."
		"copy_card":
			# Interactive picker — handled by _resolve_choice → _start_copy_mode.
			# Fallback if reached directly (shouldn't happen).
			_start_copy_mode(1, "")
			return ""
		"remove_choice":
			_start_remove_mode()
			return ""
		"remove_choice_multi":
			_start_multi_remove_mode(effect.value)
			return ""
		"remove_choice_filtered":
			# Picker restricted to a card class (curse / starter). Lets an event
			# honor its fiction ("feed him a curse") instead of opening the whole
			# deck and letting the player remove their best card.
			_start_remove_filtered_mode(String(effect.get("filter", "")))
			return ""
		"wager_gold":
			# The Gambler's coin bet. Pay `stake` up front (the gate keeps the
			# small bet affordable); a coin flip then pays `payout` gross on a
			# win, nothing on a loss. Net win = payout - stake; EV is tuned
			# slightly positive so betting is rational but never safe.
			var stake: int = int(effect.get("stake", 40))
			var payout: int = int(effect.get("payout", 100))
			if RunState.gold < stake:
				return "You haven't the coin to cover that bet."
			RunState.gold -= stake
			if randi() % 2 == 0:
				RunState.gain_gold(payout)
				return "The dice land true — won %d gold!" % payout
			return "The dice turn on you. Lost %d gold." % stake
		"wager_relic_or_curse":
			# The face-down red card: a pure coin flip, no stake. Heads is a
			# relic; tails is `curses` curses. EV ~ neutral — the draw is the
			# whole point.
			var n_curse: int = int(effect.get("curses", 2))
			if randi() % 2 == 0:
				var won = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
				if won.size() > 0:
					RunState.add_relic(won[0])
					return "The card turns up a blessing: %s." % RelicDB.get_relic(won[0]).name
				return "The card turns up blank. Nothing answers."
			for _i in range(n_curse):
				RunState.add_card(CardDB.random_curse_id())
			return "The card turns up a wound. %d Curse(s) settle into your deck." % n_curse
		"debuff_starters":
			# Hero-agnostic: weaken every starter-rarity CREATURE in the deck by
			# 1 HP. The old version hardcoded troll/sprite/naga, so the "downside"
			# silently did nothing for 3 of 4 heroes. Now it reads actual rarity,
			# so the cost lands on whatever starting creatures you brought.
			var weakened := 0
			for i in range(RunState.deck.size()):
				var data = CardDB.get_card_data(RunState.deck[i])
				if data.get("type", "creature") != "creature":
					continue
				if data.get("rarity", "") != "starter":
					continue
				if RunState.is_card_upgraded(i):
					continue
				RunState.upgrade_card(i, "fortify_neg")
				weakened += 1
			if weakened == 0:
				return "Nothing green enough is left to wither."
			return "%d starting creature(s) lose 1 HP." % weakened
		"gain_potion":
			if RunState.add_potion("healing"):
				return "Gained a Healing Potion."
			return "Your potion belt is already full."
		"add_card":
			# Add one random card of the given rarity (default common). Lets an
			# event hand out a non-rare pull without the "always a rare" inflation.
			var rarity := String(effect.get("rarity", "common"))
			var pool = CardDB.cards_of_rarity(rarity)
			if pool.is_empty():
				return ""
			pool.shuffle()
			RunState.add_card(pool[0])
			return "Added %s to your deck." % CardDB.get_card_data(pool[0]).name
		"butcher_buff":
			_start_butcher_mode()
			return ""
		"mirror_twin_buff":
			_start_mirror_twin_mode()
			return ""
		"upgrade_choice":
			_start_upgrade_mode(1)
			return ""
		"upgrade_choice_multi":
			_start_upgrade_mode(effect.value)
			return ""
		"gain_max_hp":
			RunState.hero_max_hp += effect.value
			RunState.hero_hp += effect.value
			return "Gained %d max HP." % effect.value
		"lose_max_hp":
			# Floor at 1 so an unlucky chain of events can't kill you outright.
			var new_max: int = maxi(1, RunState.hero_max_hp - effect.value)
			var actually_lost: int = RunState.hero_max_hp - new_max
			RunState.hero_max_hp = new_max
			RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)
			return "Lost %d max HP." % actually_lost
		"lose_gold_partial":
			# Lose min(value, current gold) — never goes negative. Used by tax
			# events where the cap should hit rich players but the broke player
			# pays only what they have.
			var to_lose: int = mini(effect.value, RunState.gold)
			RunState.gold -= to_lose
			return "Lost %d gold." % to_lose
		"add_rare_n":
			# Add N random rare cards (Beekeeper Returns "+THREE rare cards").
			var rares = CardDB.cards_of_rarity("rare")
			if rares.is_empty():
				return ""
			var n: int = effect.value
			var names: Array = []
			for _i in range(n):
				rares.shuffle()
				RunState.add_card(rares[0])
				names.append(CardDB.get_card_data(rares[0]).name)
			return "Added: %s." % ", ".join(names)
		"add_boss_relic":
			# Boss-tier (rare) relic pool. Used by Three Doors and Old Forge.
			var choices = RelicDB.roll_relic_reward("boss", RunState.relics, RunState.current_hero_id)
			if choices.size() > 0:
				RunState.add_relic(choices[0])
				var relic = RelicDB.get_relic(choices[0])
				return "Gained relic: %s" % relic.name
			# Pool exhausted — fall back to a combat-tier relic so the player
			# never gets nothing from a "guaranteed rare" payoff.
			var fallback = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
			if fallback.size() > 0:
				RunState.add_relic(fallback[0])
				var relic = RelicDB.get_relic(fallback[0])
				return "Gained relic: %s" % relic.name
			return "No relics available."
		"relic_sacrifice_pick":
			# Old Forge: player CHOOSES which non-starting relic to lay on the
			# anvil; it's traded for a boss-tier relic. Choosing (vs the old
			# random destruction) is the whole point — losing your best relic to
			# a coin flip was the worst feel-bad in the event pool.
			_start_relic_sacrifice_mode()
			return ""
		"mark_hand":
			# Marked One: next combat starts with a 2/3 Vanguard in front-left.
			RunState.next_combat_gift_creature = {
				"name": "Marked Vanguard", "atk": 2, "hp": 3, "kw": [],
			}
			return "The mark settles on your hand."
		"mark_heart":
			# Marked One: next combat grants +1 max mana the whole fight.
			RunState.next_combat_mana_bonus = 1
			return "The mark settles over your heart."
		"stranger_hand_pick":
			_start_stranger_hand_mode()
			return ""
		"scaled":
			# Build-scaled payoff: the reward reads YOUR deck, so it reflects the
			# run you actually built ("gold per creature", "heal per spell",
			# "+max HP per curse"). amount = count(kind) * per, optional cap. The
			# "outcome" decides what that amount buys.
			var amt := _deck_count(effect.get("count", "deck_size")) * int(effect.get("per", 1))
			var cap := int(effect.get("cap", 0))
			if cap > 0:
				amt = mini(amt, cap)
			match effect.get("outcome", "gold"):
				"gold":
					if amt > 0:
						RunState.gain_gold(amt)
					return "Gained %d gold." % amt
				"lose_gold":
					# Build-scaled COST (The Ledger). Charge min(amt, gold) so a
					# broke player pays only what they have, never negative -
					# mirroring lose_gold_partial's floor.
					var to_lose_scaled: int = mini(amt, RunState.gold)
					RunState.gold -= to_lose_scaled
					return "Lost %d gold." % to_lose_scaled
				"heal":
					RunState.heal_hero(amt)
					return "Healed %d HP." % amt
				"max_hp":
					RunState.hero_max_hp += amt
					RunState.hero_hp += amt
					return "Gained %d max HP." % amt
				"damage":
					RunState.damage_hero(amt)
					return "Took %d damage." % amt
			return ""
		"gift_creature":
			# General next-combat payoff: start the next fight with a creature in
			# front-left. Reuses the Marked-One hook (Combat reads atk/hp only —
			# kw is stored for save symmetry but not yet honored in combat).
			RunState.next_combat_gift_creature = {
				"name": effect.get("name", "Gift"),
				"atk": int(effect.get("atk", 1)),
				"hp": int(effect.get("hp", 1)),
				"kw": effect.get("kw", []),
			}
			return effect.get("text", "Something will fight beside you.")
		"combat_mana":
			# General next-combat payoff: +N max mana for the whole next fight.
			RunState.next_combat_mana_bonus += int(effect.get("value", 1))
			return effect.get("text", "Power gathers for the fight ahead.")
		"sacrifice_pick":
			_start_sacrifice_mode(effect)
			return ""
		"transform_choice":
			_start_transform_mode(int(effect.get("value", 1)))
			return ""
		"dice_run":
			_start_dice_run(effect)
			return ""
		"risk_loop":
			_start_risk_loop(effect)
			return ""
		"pawn_appraisal":
			_start_appraisal_mode()
			return ""
		"roll_table":
			# Weighted mystery outcome — the choice says WHAT you're risking,
			# the table decides what the road actually does. Entries:
			# {"weight": int, "text": String, "effects": [non-modal effects]}.
			# Keeps one-shot choices from being a printed menu: the player
			# commits to an action, not a price list.
			var outcomes: Array = effect.get("outcomes", [])
			var total := 0
			for o in outcomes:
				total += maxi(1, int(o.get("weight", 1)))
			if total <= 0:
				return ""
			var pick := randi() % total
			for o in outcomes:
				pick -= maxi(1, int(o.get("weight", 1)))
				if pick < 0:
					var receipt := _apply_effect_list(o.get("effects", []))
					return _combine_lines([String(o.get("text", "")), receipt])
			return ""
	return ""


## Apply a list of NON-MODAL effects and join their receipt lines. Used by
## roll_table outcomes and risk_loop steps — never put a picker-type effect
## (MODAL_EFFECTS) in those lists; it would clobber the calling screen.
func _apply_effect_list(effects: Array) -> String:
	var parts: Array = []
	for e in effects:
		var t := _apply_effect(e)
		if t != "":
			parts.append(t)
	return "\n".join(parts)


func _combine_lines(parts: Array) -> String:
	var out: Array = []
	for p in parts:
		if String(p).strip_edges() != "":
			out.append(String(p))
	return "\n".join(out)


func _deck_count(kind: String) -> int:
	# Counts something about the player's current build, for "scaled" payoffs.
	# "deck_size"/"relics" are direct; the rest walk the deck and inspect cards.
	match kind:
		"deck_size":
			return RunState.deck.size()
		"relics":
			return RunState.relics.size()
	var n := 0
	for cid in RunState.deck:
		var data := CardDB.get_card_data(cid)
		if data.is_empty():
			continue
		match kind:
			"spells":
				if data.get("type", "") == "spell":
					n += 1
			"creatures":
				if data.get("type", "") == "creature":
					n += 1
			"curses":
				if CardDB.is_curse(cid):
					n += 1
			"onecost":
				if int(data.get("cost", 99)) <= 1 and not CardDB.is_curse(cid):
					n += 1
			"deathrattle":
				if data.get("type", "") == "creature" and not data.get("on_death", {}).is_empty():
					n += 1
	return n


func _show_result(text: String) -> void:
	# Merge any stashed co-effect receipt (set when a modal picker was launched
	# alongside non-modal effects) ahead of the picker's own result line.
	var full := text.strip_edges()
	if _pending_pre_text != "":
		full = (_pending_pre_text + "\n" + full).strip_edges()
		_pending_pre_text = ""
	if full.is_empty():
		return
	_clear_ui()
	# Result keeps the event art behind it — same scene, same beat.
	_set_event_art_visible(true)

	var result_label := Label.new()
	result_label.text = full
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_font_size_override("font_size", 22)
	result_label.add_theme_color_override("font_color", GameTheme.IVORY)
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.80))
	result_label.add_theme_constant_override("outline_size", 3)
	result_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	result_label.add_theme_constant_override("shadow_offset_x", 0)
	result_label.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		result_label.add_theme_font_override("font", GameTheme.font_display)
	result_label.set_anchors_preset(Control.PRESET_CENTER)
	result_label.offset_left = -420
	result_label.offset_right = 420
	result_label.offset_top = -140
	result_label.offset_bottom = 60
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result_label)

	var continue_btn := _make_frameless_choice("Continue", "", "Walk on.", 88,
			func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE))
	continue_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	continue_btn.offset_left = -280
	continue_btn.offset_right = 280
	continue_btn.offset_top = -180
	continue_btn.offset_bottom = -92
	add_child(continue_btn)


func _make_card_picker_grid(title_text: String, title_color: Color) -> GridContainer:
	# Shared helper for card-picker screens (remove, copy, butcher).
	# Returns the GridContainer so callers can add card wrappers to it.
	_clear_ui()
	_set_event_art_visible(false)

	var title = GameTheme.make_label(title_text, 22, title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 30)
	title.size = Vector2(1000, 40)
	add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(80, 80)
	scroll.size = Vector2(1440, 680)
	add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	return grid


func _add_card_to_grid(grid: GridContainer, data: Dictionary, callback: Callable) -> void:
	# Add a Card2D wrapper with click overlay to a picker grid.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(210, 280)
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	wrapper.add_child(card_node)
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.pressed.connect(callback)
	wrapper.add_child(click_btn)
	grid.add_child(wrapper)


func _start_remove_mode() -> void:
	var grid = _make_card_picker_grid("Choose a card to remove", GameTheme.KEYWORD_GOLD)

	# Bind the deck index explicitly. The previous inline `func(): remove_card_at(i)`
	# closed over the loop variable, so every tile clicked removed whichever
	# index `i` ended on — matching the player's "every option does the same
	# thing" complaint about card pickers.
	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_remove_pick.bind(i))


func _on_remove_pick(deck_index: int) -> void:
	RunState.remove_card_at(deck_index)
	_show_result("Card removed.")


func _start_multi_remove_mode(count: int) -> void:
	var grid = _make_card_picker_grid("Choose %d card(s) to remove" % count, GameTheme.BLOOD_RED)

	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_multi_remove_pick.bind(i, count))


var _multi_remove_remaining: int = 0
var _multi_remove_removed: int = 0

func _on_multi_remove_pick(deck_index: int, total: int) -> void:
	if _multi_remove_remaining <= 0:
		_multi_remove_remaining = total
		_multi_remove_removed = 0
	RunState.remove_card_at(deck_index)
	_multi_remove_removed += 1
	_multi_remove_remaining -= 1
	if _multi_remove_remaining <= 0 or RunState.deck.size() <= 1:
		_show_result("Removed %d card(s)." % _multi_remove_removed)
	else:
		_start_multi_remove_mode(_multi_remove_remaining)


# ── Filtered card removal (Sin-Eater family) ─────────────────────────────
# A removal picker restricted to one card class so an event can honor its
# fiction. "Feed him a curse" should only show curses; "feed him a starter"
# only starters. If nothing qualifies, we report it gracefully — any non-modal
# co-effect (gold, relic) has already applied, so the player isn't cheated.

func _start_remove_filtered_mode(filter: String) -> void:
	var matches: Array = []
	for i in range(RunState.deck.size()):
		if _card_matches_filter(RunState.deck[i], filter):
			matches.append(i)
	if matches.is_empty():
		_show_result(_filter_empty_message(filter))
		return
	var grid = _make_card_picker_grid(_filter_prompt(filter), GameTheme.KEYWORD_GOLD)
	for i in matches:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_remove_filtered_pick.bind(i, filter))


func _on_remove_filtered_pick(deck_index: int, filter: String) -> void:
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	RunState.remove_card_at(deck_index)
	_show_result(_filter_removed_message(filter, data.name))


func _card_matches_filter(card_id: String, filter: String) -> bool:
	match filter:
		"curse":
			return CardDB.is_curse(card_id)
		"starter":
			if CardDB.is_curse(card_id):
				return false
			return CardDB.get_card_data(card_id).get("rarity", "") == "starter"
	return true


func _filter_prompt(filter: String) -> String:
	match filter:
		"curse":
			return "Lay a Curse on the table"
		"starter":
			return "Lay a starting card on the table"
	return "Choose a card"


func _filter_empty_message(filter: String) -> String:
	match filter:
		"curse":
			return "You carry no Curse for him to eat."
		"starter":
			return "Nothing green enough is left to give."
	return "Nothing here he'll take."


func _filter_removed_message(filter: String, card_name: String) -> String:
	match filter:
		"curse":
			return "He swallows %s whole. It troubles you no longer." % card_name
		"starter":
			return "He tucks %s under his tongue for later." % card_name
	return "%s is taken." % card_name


var _copy_remaining: int = 0
var _copy_names: Array = []
var _copy_pre_text: String = ""

# When a choice pairs non-modal effects (gold/heal/rare) with a modal picker
# (remove/upgrade/butcher/...), the non-modal result text would otherwise be
# dropped — the picker owns the next screen. We stash it here at launch and
# _show_result prepends it once, so "Removed 2 cards" also reports the rare and
# gold the same choice granted. Cleared the first time a result screen renders.
var _pending_pre_text: String = ""

func _start_copy_mode(count: int, pre_text: String = "") -> void:
	if _copy_remaining <= 0:
		_copy_remaining = count
		_copy_names = []
		_copy_pre_text = pre_text

	var suffix := ""
	if _copy_remaining > 1:
		suffix = " (%d remaining)" % _copy_remaining
	var grid = _make_card_picker_grid("Choose a card to duplicate" + suffix, GameTheme.KEYWORD_GOLD)

	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_copy_pick.bind(i))


func _on_copy_pick(deck_index: int) -> void:
	var card_id = RunState.deck[deck_index]
	var data = CardDB.get_card_data(card_id)
	RunState.add_card(card_id)
	_copy_names.append(data.name)
	_copy_remaining -= 1
	if _copy_remaining <= 0:
		var msg := ""
		if _copy_pre_text != "":
			msg = _copy_pre_text + "\n"
		for n in _copy_names:
			msg += "Duplicated %s.\n" % n
		_show_result(msg.strip_edges())
	else:
		_start_copy_mode(_copy_remaining)


func _start_butcher_mode() -> void:
	var grid = _make_card_picker_grid("Choose a creature for the Butcher (+2 ATK, +Wither 1)", GameTheme.KEYWORD_GOLD)

	# Same closure-capture fix as _start_remove_mode: bind the deck index by
	# value so each tile knows which card it represents at click-time.
	for i in range(RunState.deck.size()):
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "creature") != "creature":
			continue
		_add_card_to_grid(grid, data, _on_butcher_pick.bind(i))


func _on_butcher_pick(deck_index: int) -> void:
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	RunState.upgrade_card(deck_index, "butcher")
	_show_result("The Butcher returns %s with +2 ATK and Wither 1." % data.name)


func _start_mirror_twin_mode() -> void:
	var grid = _make_card_picker_grid("Push a creature through (HP → 1, ATK +4)", GameTheme.SPELL_PURPLE)
	for i in range(RunState.deck.size()):
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "creature") != "creature":
			continue
		if RunState.is_card_upgraded(i):
			continue
		_add_card_to_grid(grid, data, _on_mirror_twin_pick.bind(i))


func _on_mirror_twin_pick(deck_index: int) -> void:
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	RunState.upgrade_card(deck_index, "mirror_twin")
	_show_result("The reflection keeps %s. What returns has 1 HP and is hungrier." % data.name)


# Pick N cards from the deck and apply the standard "sharpen" upgrade. For
# spells that's +2 spell value; for creatures it's +2 ATK. Mirrors the
# remove-multi picker — re-enters itself until count reaches zero or there
# are no upgradeable cards left.
var _upgrade_choice_remaining: int = 0
var _upgrade_choice_names: Array = []

func _start_upgrade_mode(count: int) -> void:
	if _upgrade_choice_remaining <= 0:
		_upgrade_choice_remaining = count
		_upgrade_choice_names = []

	var any_upgradeable := false
	for i in range(RunState.deck.size()):
		if not RunState.is_card_upgraded(i):
			any_upgradeable = true
			break
	if not any_upgradeable:
		var msg := ""
		if _upgrade_choice_names.size() > 0:
			msg = "Upgraded: %s." % ", ".join(_upgrade_choice_names)
		else:
			msg = "Nothing left to upgrade."
		_upgrade_choice_remaining = 0
		_show_result(msg)
		return

	var suffix := ""
	if _upgrade_choice_remaining > 1:
		suffix = " (%d remaining)" % _upgrade_choice_remaining
	var grid = _make_card_picker_grid("Choose a card to upgrade" + suffix, GameTheme.KEYWORD_GOLD)
	for i in range(RunState.deck.size()):
		if RunState.is_card_upgraded(i):
			continue
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_upgrade_choice_pick.bind(i))


func _on_upgrade_choice_pick(deck_index: int) -> void:
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	RunState.upgrade_card(deck_index, "plus")
	_upgrade_choice_names.append(data.name)
	_upgrade_choice_remaining -= 1
	if _upgrade_choice_remaining <= 0:
		_show_result("Upgraded: %s." % ", ".join(_upgrade_choice_names))
	else:
		_start_upgrade_mode(_upgrade_choice_remaining)


# Designer-style choose-from-pool picker. Rolls 3 random rare cards
# (preferring ones not already in the deck so the offering feels new) and
# lays them out horizontally with a fixed cost label below each. Costs are
# fixed across rolls — HP / gold / curse — so the player learns to read
# the row at a glance: "which card do I want, and which currency can I
# afford to spend?" Modeled on StS's Designer In-Spire and the Mind Bloom
# branches, but each card is the choice (not each effect).
func _start_stranger_hand_mode() -> void:
	var rares: Array = CardDB.cards_of_rarity("rare")
	# Prefer rares the player doesn't already own so the deal feels novel.
	# If filtering drops us below 3, fall back to the full pool — better to
	# offer a duplicate than to show fewer than three cards.
	var deck_set: Dictionary = {}
	for cid in RunState.deck:
		deck_set[cid] = true
	var filtered: Array = []
	for rid in rares:
		if not deck_set.has(rid):
			filtered.append(rid)
	var pool: Array = filtered if filtered.size() >= 3 else rares.duplicate()
	pool.shuffle()
	var offered: Array = pool.slice(0, mini(3, pool.size()))

	_clear_ui()
	_set_event_art_visible(false)

	var title = GameTheme.make_label(
		"Three cards lie face-up on the stone. Each is owed.",
		22, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 60)
	title.size = Vector2(1000, 40)
	add_child(title)

	# Fixed per-slot costs. Index aligns with `offered` so the leftmost card
	# always carries the HP cost, etc. — predictable enough that a returning
	# player can plan around the slot without rolling the dice on what costs
	# what.
	var costs: Array = [
		{"kind": "hp", "value": 8, "label": "Pay 8 HP"},
		{"kind": "gold", "value": 80, "label": "Pay 80 gold"},
		{"kind": "curse", "value": 0, "label": "Owe a Curse"},
	]

	# Horizontal row of card+cost columns, centered on the screen. The math
	# below keeps the row symmetric around the center anchor so adding/
	# dropping a card doesn't shove the layout.
	var n: int = offered.size()
	var card_w: int = 220
	var sep: int = 40
	var total_w: int = n * card_w + (n - 1) * sep
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_CENTER)
	hbox.offset_left = -total_w / 2
	hbox.offset_right = total_w / 2
	hbox.offset_top = -200
	hbox.offset_bottom = 180
	hbox.add_theme_constant_override("separation", sep)
	add_child(hbox)

	for i in range(n):
		var card_id: String = offered[i]
		var data = CardDB.get_card_data(card_id)
		var cost: Dictionary = costs[i]

		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(card_w, 380)
		v.add_theme_constant_override("separation", 16)
		hbox.add_child(v)

		# Card tile — same wrapper-plus-transparent-button pattern as
		# _add_card_to_grid so click semantics match the other pickers.
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(card_w, 290)
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		wrapper.add_child(card_node)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_on_stranger_hand_pick.bind(card_id, cost))
		wrapper.add_child(click_btn)
		v.add_child(wrapper)

		var cost_label := Label.new()
		cost_label.text = cost.label
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.add_theme_font_size_override("font_size", 20)
		cost_label.add_theme_color_override("font_color", GameTheme.IVORY)
		cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		cost_label.add_theme_constant_override("outline_size", 3)
		if GameTheme.font_display:
			cost_label.add_theme_font_override("font", GameTheme.font_display)
		v.add_child(cost_label)

	# Leave button below the row — the player can step into the picker,
	# inspect the cards, and back out without paying. Cleaner than forcing
	# a leave decision before they know what's on offer.
	var leave_btn := _make_frameless_choice(
		"Walk on",
		"",
		"The stranger does not look up. The road is still yours.",
		88,
		_on_stranger_hand_leave)
	leave_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	leave_btn.offset_left = -280
	leave_btn.offset_right = 280
	leave_btn.offset_top = -160
	leave_btn.offset_bottom = -72
	add_child(leave_btn)


func _on_stranger_hand_pick(card_id: String, cost: Dictionary) -> void:
	var data = CardDB.get_card_data(card_id)
	var msg := ""
	match cost.kind:
		"hp":
			# Non-lethal: leave the player at 1 HP minimum so an unaware
			# pick can't drop them into a 0-HP combat. Cost is "as much as
			# you can pay, never the last drop."
			var to_lose: int = mini(int(cost.value), RunState.hero_hp - 1)
			to_lose = maxi(0, to_lose)
			RunState.hero_hp -= to_lose
			msg = "Paid %d HP. " % to_lose
		"gold":
			var to_lose_g: int = mini(int(cost.value), RunState.gold)
			RunState.gold -= to_lose_g
			msg = "Paid %d gold. " % to_lose_g
		"curse":
			RunState.add_card(CardDB.random_curse_id())
			msg = "A Curse settles into your deck. "
	RunState.add_card(card_id)
	msg += "Gained %s." % data.name
	_show_result(msg)


func _on_stranger_hand_leave() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


# ── Relic sacrifice picker (Old Forge) ───────────────────────────────────
# Lays the player's NON-starting relics out as tiles and lets them choose
# which one to trade for a boss-tier relic. Starting (hero signature) relics
# are off-limits — they're run-defining. Replaces the old random destruction.

func _start_relic_sacrifice_mode() -> void:
	var non_starting: Array = []
	for rid in RunState.relics:
		var r = RelicDB.get_relic(rid)
		if r.get("tier", "starting") != "starting":
			non_starting.append(rid)
	if non_starting.is_empty():
		_show_result("The smith waves you off — nothing of his make in your bag.")
		return

	_clear_ui()
	_set_event_art_visible(false)

	var title = GameTheme.make_label(
		"Lay one on the anvil. He makes heavy things from light ones.",
		22, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 34)
	title.size = Vector2(1000, 40)
	add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(120, 96)
	scroll.size = Vector2(1360, 660)
	add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	scroll.add_child(grid)

	for rid in non_starting:
		grid.add_child(_make_relic_tile(rid, _on_relic_sacrifice_pick.bind(rid)))

	# The player may inspect their relics and decline — backing out leaves the
	# whole event (same as the Stranger's Hand picker).
	var leave_btn := _make_frameless_choice(
		"Keep them all", "",
		"The forge has no fire. Your hands stop hurting anyway.",
		88, _on_stranger_hand_leave)
	leave_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	leave_btn.offset_left = -280
	leave_btn.offset_right = 280
	leave_btn.offset_top = -150
	leave_btn.offset_bottom = -62
	add_child(leave_btn)


func _make_relic_tile(relic_id: String, on_press: Callable) -> Button:
	# A parchment panel button showing the relic's name (gold) and rules text.
	# Same click semantics as the card tiles, sized for a 3-wide grid.
	var relic = RelicDB.get_relic(relic_id)
	var btn := Button.new()
	# NOT flat — a flat Button skips drawing its normal StyleBox even when
	# overridden, which left these tiles as floating text with no parchment
	# panel behind them. Keep it non-flat so make_panel_style() actually paints.
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(420, 120)
	btn.add_theme_stylebox_override("normal", GameTheme.make_panel_style())
	btn.add_theme_stylebox_override("hover",
		GameTheme.make_panel_style(GameTheme.PARCHMENT, GameTheme.GILT_BRIGHT))
	btn.add_theme_stylebox_override("pressed", GameTheme.make_panel_style())
	btn.pressed.connect(on_press)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_right = -18
	vbox.offset_top = 12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var name_lbl := GameTheme.make_label(relic.get("name", "Relic"), 21, GameTheme.KEYWORD_GOLD)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var desc_lbl := GameTheme.make_label(relic.get("desc", ""), 15, GameTheme.DESC_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(384, 0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	return btn


func _on_relic_sacrifice_pick(relic_id: String) -> void:
	var lost_name = RelicDB.get_relic(relic_id).name
	RunState.relics.erase(relic_id)
	var choices = RelicDB.roll_relic_reward("boss", RunState.relics, RunState.current_hero_id)
	if choices.is_empty():
		choices = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
	if choices.is_empty():
		_show_result("Lost %s. The smith finds nothing worthy to give back." % lost_name)
		return
	RunState.add_relic(choices[0])
	var gained_name = RelicDB.get_relic(choices[0]).name
	_show_result("You lay down %s. He returns %s, heavier." % [lost_name, gained_name])


# ── Sacrifice altar picker (Dark Altar, etc.) ────────────────────────────
# Lay one of YOUR creatures on the altar; the payoff scales with the
# creature's ATK — the stronger the offering, the heavier the return. Routed
# through a modal so the player sees their whole deck and chooses the victim.
# The reward shape ("gold"/"max_hp"/"relic") and rates come from the effect.

var _sacrifice_effect: Dictionary = {}

func _start_sacrifice_mode(effect: Dictionary) -> void:
	_sacrifice_effect = effect
	var creatures: Array = []
	for i in range(RunState.deck.size()):
		var data := CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "") == "creature":
			creatures.append(i)
	if creatures.is_empty():
		_show_result("You have no creature to lay down.")
		return
	var grid = _make_card_picker_grid(
		effect.get("prompt", "Lay one creature on the altar."), GameTheme.BLOOD_RED)
	for i in creatures:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_sacrifice_pick.bind(i))


func _on_sacrifice_pick(deck_index: int) -> void:
	var data = RunState.get_upgraded_card_data(deck_index)
	var atk: int = int(data.get("atk", 0))
	var nm: String = data.get("name", "the creature")
	RunState.remove_card_at(deck_index)
	var base: int = int(_sacrifice_effect.get("base", 0))
	match _sacrifice_effect.get("reward", "gold"):
		"gold":
			var per: int = int(_sacrifice_effect.get("per_atk", 5))
			var amt := base + atk * per
			RunState.gain_gold(amt)
			_show_result("You lay down %s. The altar pays %d gold." % [nm, amt])
		"max_hp":
			var hp_gain := base + int(atk / 2.0)
			RunState.hero_max_hp += hp_gain
			RunState.hero_hp += hp_gain
			_show_result("You lay down %s. You feel %d sturdier." % [nm, hp_gain])
		"relic":
			var choices = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
			if choices.is_empty():
				_show_result("You lay down %s. The altar gives nothing back." % nm)
				return
			RunState.add_relic(choices[0])
			var rname = RelicDB.get_relic(choices[0]).name
			_show_result("You lay down %s. The altar yields %s." % [nm, rname])
		_:
			_show_result("You lay down %s." % nm)


# ── Transform picker (The Chrysalis Fence) ───────────────────────────────
# Choose a card; it leaves the deck and a random card of the same rarity
# takes its slot — the classic StS transform. Curses are excluded (a free
# curse-to-card swap would out-pay every dedicated curse-eater event);
# starters roll into the common pool so the result is always playable.
# Multi-count re-enters itself like the remove/upgrade pickers.

var _transform_remaining: int = 0
var _transform_results: Array = []

func _start_transform_mode(count: int) -> void:
	if _transform_remaining <= 0:
		_transform_remaining = count
		_transform_results = []
	var eligible: Array = []
	for i in range(RunState.deck.size()):
		if not CardDB.is_curse(RunState.deck[i]):
			eligible.append(i)
	if eligible.is_empty():
		_transform_remaining = 0
		_show_result("Nothing you carry is alive enough to change.")
		return
	var suffix := ""
	if _transform_remaining > 1:
		suffix = " (%d remaining)" % _transform_remaining
	var grid = _make_card_picker_grid(
		"Choose a card to feed the silk" + suffix, GameTheme.SPELL_PURPLE)
	for i in eligible:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_transform_pick.bind(i))


func _on_transform_pick(deck_index: int) -> void:
	var old_id: String = RunState.deck[deck_index]
	var old_data = CardDB.get_card_data(old_id)
	var rarity: String = String(old_data.get("rarity", "common"))
	# Starters hatch into commons; everything else keeps its weight class.
	if rarity == "starter" or rarity == "enemy":
		rarity = "common"
	var pool: Array = CardDB.cards_of_rarity(rarity)
	pool.erase(old_id)
	if pool.is_empty():
		pool = CardDB.cards_of_rarity("common")
		pool.erase(old_id)
	RunState.remove_card_at(deck_index)
	var new_id: String = pool[randi() % pool.size()]
	RunState.add_card(new_id)
	_transform_results.append("%s became %s" \
		% [old_data.get("name", "it"), CardDB.get_card_data(new_id).name])
	_transform_remaining -= 1
	if _transform_remaining <= 0:
		_show_result("The silk parts. " + ". ".join(_transform_results) + ".")
	else:
		_start_transform_mode(_transform_remaining)


# ── Pot run (dice_run) — parameterized push-your-luck wager ──────────────
# A real looping mini-game, not a one-shot coin flip: the pot opens at
# `start` gold and every press either grows it or loses the lot; banking
# ends the run and pays the pot. Fully data-driven so different events
# wear it as different games — The Bone Pit (add mode, 1-in-3 bust) and
# The Coin That Won't Land (double-or-nothing, even odds, entry stake).
# Text fields take {pot} / {gain} tokens. Defaults reproduce the Bone Pit.

var _dice_cfg: Dictionary = {}
var _dice_pot: int = 0

func _dice_text(key: String, fallback: String, gain: int = 0) -> String:
	return String(_dice_cfg.get(key, fallback)) \
		.replace("{pot}", str(_dice_pot)).replace("{gain}", str(gain))


func _start_dice_run(effect: Dictionary) -> void:
	_dice_cfg = effect
	_dice_pot = int(effect.get("start", 25))
	var stake: int = int(effect.get("stake", 0))
	if stake > 0:
		if RunState.gold < stake:
			_show_result(_dice_text("broke_text", "You haven't the coin to sit down."))
			return
		RunState.gold -= stake
	_build_dice_screen(_dice_text("open_text",
		"The space in the circle is yours. The pot sits at {pot} gold."))


func _build_dice_screen(beat: String) -> void:
	_clear_ui()
	_set_event_art_visible(true)

	var title := _make_event_title("The pot: [color=#e8b547]%d gold[/color]" % _dice_pot)
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 80
	title.offset_top = 72
	title.offset_right = 700
	title.offset_bottom = 132
	add_child(title)

	var desc = _make_event_desc(beat)
	add_child(desc)

	var choices_vbox := VBoxContainer.new()
	choices_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	choices_vbox.offset_left = 80
	choices_vbox.offset_right = 700
	choices_vbox.offset_top = -(2 * 118 + 12 + 110)
	choices_vbox.offset_bottom = -110
	choices_vbox.add_theme_constant_override("separation", 12)
	add_child(choices_vbox)

	choices_vbox.add_child(_make_frameless_choice(
		_dice_text("roll_label", "Cast the bones"),
		_dice_text("roll_sub", "2 in 3 the pot grows. Skulls lose it all."),
		_dice_text("roll_body", "The knuckles rattle like teeth in a cup."),
		118, _on_dice_roll))
	choices_vbox.add_child(_make_frameless_choice(
		_dice_text("bank_label", "Bank the pot"),
		_dice_text("bank_sub", "Take {pot} gold and leave the circle."),
		_dice_text("bank_body", "The dead nod. Walking away is also a move."),
		118, _on_dice_bank))


func _on_dice_roll() -> void:
	if randf() < float(_dice_cfg.get("bust_pct", 1.0 / 3.0)):
		_dice_pot = 0
		_show_result(_dice_text("bust_text",
			"Skulls. The pot drains back into the pit, coin by coin, and the circle closes over it. The dead do not gloat. Much."))
		return
	var gain: int = 0
	if String(_dice_cfg.get("mode", "add")) == "double":
		gain = _dice_pot
		_dice_pot *= 2
	else:
		gain = randi_range(int(_dice_cfg.get("gain_min", 18)),
			int(_dice_cfg.get("gain_max", 34)))
		_dice_pot += gain
	AudioBank.play_sfx("button_click")
	_build_dice_screen(_dice_text("grow_text",
		"The bones land clean — {gain} more into the pot. The oldest legionary clicks his jaw, which you have learned is applause.", gain))


func _on_dice_bank() -> void:
	RunState.gain_gold(_dice_pot)
	_show_result(_dice_text("bank_text",
		"You bank {pot} gold and stand. A space stays open in the circle behind you. It is always open. That is the other rule."))


# ── Risk loop (risk_loop) — the generic "do it again?" engine ────────────
# The reusable spine for push-your-luck events that aren't about a gold
# pot: drink another sip, sing another verse, pick another fruit, swing
# the axe again. Two modes:
#   "bust" (default): each press rolls the step's `chance` to SUCCEED —
#     success applies the step's effects immediately (you keep what you
#     got) and advances; failure applies `bust.effects` and ends.
#   "jackpot": each press applies the step's effects as a COST, then
#     rolls `chance` to hit the `jackpot` — which applies effects and/or
#     launches a picker modal (e.g. upgrade_choice) and ends; a miss
#     advances to the next step (author the last step at chance 1.0).
# Steps carry their own odds line (`sub`, shown gold on the button) and a
# success beat (`text`). The action hides when the player can't pay the
# step's HP cost — no lethal loops (mirrors the Wet Cards' non-lethal rule).
# AUTHORING LAW: step/bust/jackpot effects must be NON-MODAL (except the
# jackpot's `modal` field, which names the picker to launch).

var _risk_cfg: Dictionary = {}
var _risk_step: int = 0

func _start_risk_loop(effect: Dictionary) -> void:
	_risk_cfg = effect
	_risk_step = 0
	_build_risk_screen(String(effect.get("open_text", _current_node.get("desc", ""))))


func _effects_hp_cost(effects: Array) -> int:
	var dmg := 0
	for e in effects:
		if String(e.get("type", "")) == "damage":
			dmg += int(e.get("value", 0))
	return dmg


func _build_risk_screen(beat: String) -> void:
	_clear_ui()
	_set_event_art_visible(true)

	var title := _make_event_title(_event_data.name)
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 80
	title.offset_top = 72
	title.offset_right = 700
	title.offset_bottom = 132
	add_child(title)

	var steps: Array = _risk_cfg.get("steps", [])
	var can_act: bool = _risk_step < steps.size()
	if can_act:
		# Non-lethal guard: never offer a press the player can't survive.
		var cost := _effects_hp_cost(steps[_risk_step].get("effects", []))
		if cost > 0 and RunState.hero_hp <= cost:
			can_act = false
			beat += "\n\nYou haven't the blood for another."

	var desc = _make_event_desc(beat)
	add_child(desc)

	var n_choices: int = 2 if can_act else 1
	var choices_vbox := VBoxContainer.new()
	choices_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	choices_vbox.offset_left = 80
	choices_vbox.offset_right = 700
	choices_vbox.offset_top = -(n_choices * 118 + (n_choices - 1) * 12 + 110)
	choices_vbox.offset_bottom = -110
	choices_vbox.add_theme_constant_override("separation", 12)
	add_child(choices_vbox)

	if can_act:
		var step: Dictionary = steps[_risk_step]
		choices_vbox.add_child(_make_frameless_choice(
			String(_risk_cfg.get("action", "Press on")),
			String(step.get("sub", "")),
			String(_risk_cfg.get("action_body", "")), 118, _on_risk_action))
	choices_vbox.add_child(_make_frameless_choice(
		String(_risk_cfg.get("leave", "Step away")), "",
		String(_risk_cfg.get("leave_sub", "Keep what you have.")), 118,
		_on_risk_leave))


func _on_risk_action() -> void:
	var steps: Array = _risk_cfg.get("steps", [])
	if _risk_step >= steps.size():
		_on_risk_leave()
		return
	var step: Dictionary = steps[_risk_step]
	var chance := float(step.get("chance", 1.0))
	AudioBank.play_sfx("button_click")
	if String(_risk_cfg.get("mode", "bust")) == "jackpot":
		# The press always costs; the roll decides whether it pays.
		var cost_receipt := _apply_effect_list(step.get("effects", []))
		if randf() < chance:
			var jp: Dictionary = _risk_cfg.get("jackpot", {})
			var jp_receipt := _apply_effect_list(jp.get("effects", []))
			var line := _combine_lines([String(jp.get("text", "")),
				cost_receipt, jp_receipt])
			var modal := String(jp.get("modal", ""))
			if modal == "upgrade_choice":
				_pending_pre_text = line
				_start_upgrade_mode(1)
			elif modal == "remove_choice":
				_pending_pre_text = line
				_start_remove_mode()
			else:
				_show_result(line)
			return
		_risk_step += 1
		if _risk_step >= steps.size():
			_show_result(_combine_lines([
				String(_risk_cfg.get("done_text", "There is nothing more here.")),
				cost_receipt]))
		else:
			_build_risk_screen(_combine_lines([String(step.get("text", "")),
				cost_receipt]))
		return
	# Bust mode: success pays and advances, failure ends the loop.
	if randf() < chance:
		var receipt := _apply_effect_list(step.get("effects", []))
		_risk_step += 1
		if _risk_step >= steps.size():
			_show_result(_combine_lines([receipt,
				String(_risk_cfg.get("done_text", "There is nothing more here."))]))
		else:
			_build_risk_screen(_combine_lines([String(step.get("text", "")), receipt]))
	else:
		var bust: Dictionary = _risk_cfg.get("bust", {})
		var bust_receipt := _apply_effect_list(bust.get("effects", []))
		_show_result(_combine_lines([String(bust.get("text", "The luck turns.")),
			bust_receipt]))


func _on_risk_leave() -> void:
	if _risk_step == 0:
		_show_result(String(_risk_cfg.get("leave_text_early",
			_risk_cfg.get("leave_text", "You let it be."))))
	else:
		_show_result(String(_risk_cfg.get("leave_text", "You step away with what you were given.")))


# ── Appraisal (pawn_appraisal) — the haggling counter ────────────────────
# She pulls a random card from YOUR deck and names a price. Take it, or
# ask her to pull another — her interest (and the multiplier) cools 15%
# each time, three cards shown at most. The pressure is the format: the
# first offer is the best one, and it's never for the card you'd have
# chosen to sell. Curses are never appraised ("she has standards").

var _appr_index: int = -1
var _appr_mult: float = 1.0
var _appr_shown: int = 0

func _start_appraisal_mode() -> void:
	_appr_mult = 1.0
	_appr_shown = 1
	_appr_index = _appraisal_roll(-1)
	if _appr_index < 0:
		_show_result("She glances through your pack once and slides it back under the glass. Nothing in it interests her.")
		return
	_build_appraisal_screen()


func _appraisal_roll(exclude: int) -> int:
	var pool: Array = []
	for i in range(RunState.deck.size()):
		if i == exclude:
			continue
		if CardDB.is_curse(RunState.deck[i]):
			continue
		pool.append(i)
	if pool.is_empty():
		return exclude
	return pool[randi() % pool.size()]


func _appraisal_price(deck_index: int) -> int:
	var data = RunState.get_upgraded_card_data(deck_index)
	var base: int = 30
	match String(data.get("rarity", "common")):
		"starter": base = 15
		"common": base = 30
		"uncommon": base = 50
		"rare": base = 85
	return int(round((base + int(data.get("cost", 0)) * 5) * _appr_mult))


func _build_appraisal_screen() -> void:
	_clear_ui()
	_set_event_art_visible(true)

	var data = RunState.get_upgraded_card_data(_appr_index)
	var price := _appraisal_price(_appr_index)

	var title := _make_event_title(
		"She holds up [color=#e8b547]%s[/color]" % String(data.get("name", "a card")))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 80
	title.offset_top = 72
	title.offset_right = 700
	title.offset_bottom = 132
	add_child(title)

	var desc = _make_event_desc(
		"She turns it over twice behind the smoked glass, taps it once, and names a figure. She does not repeat herself.")
	add_child(desc)

	# The card itself, stood on the scrim left of the choices.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	wrapper.offset_left = 96
	wrapper.offset_right = 321
	wrapper.offset_top = -40
	wrapper.offset_bottom = 260
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	wrapper.add_child(card_node)
	add_child(wrapper)

	var can_another: bool = _appr_shown < 3 and RunState.deck.size() > 1
	var n_choices: int = 3 if can_another else 2
	var choices_vbox := VBoxContainer.new()
	choices_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	choices_vbox.offset_left = 360
	choices_vbox.offset_right = 980
	choices_vbox.offset_top = -(n_choices * 118 + (n_choices - 1) * 12 + 110)
	choices_vbox.offset_bottom = -110
	choices_vbox.add_theme_constant_override("separation", 12)
	add_child(choices_vbox)

	choices_vbox.add_child(_make_frameless_choice("Sell it",
		"Trade %s for %d gold." % [String(data.get("name", "the card")), price],
		"Her hand is already open under the slot.", 118, _on_appraisal_sell))
	if can_another:
		choices_vbox.add_child(_make_frameless_choice("Show her another",
			"She pulls a different card — but her interest cools.",
			"\"As you like. The figure was for THAT one.\"", 118,
			_on_appraisal_another))
	choices_vbox.add_child(_make_frameless_choice("Keep your things", "",
		"She slides the card back without a word.", 118,
		_on_stranger_hand_leave))


func _on_appraisal_sell() -> void:
	var data = RunState.get_upgraded_card_data(_appr_index)
	var price := _appraisal_price(_appr_index)
	RunState.remove_card_at(_appr_index)
	RunState.gain_gold(price)
	AudioBank.play_sfx("button_click")
	_show_result("%s goes behind the smoked glass with everything else that mattered to someone once. You count %d gold. She has already stopped looking at you." \
		% [String(data.get("name", "The card")), price])


func _on_appraisal_another() -> void:
	_appr_shown += 1
	_appr_mult *= 0.85
	_appr_index = _appraisal_roll(_appr_index)
	AudioBank.play_sfx("button_click")
	_build_appraisal_screen()


# ── Event definitions ──
#
# Event "name" and "desc" support inline BBCode — _make_event_title and
# _make_event_desc render via RichTextLabel with bbcode_enabled. Use sparingly:
# every event with twitching letters cheapens the ones that should land.
#
#   Static color:    [color=#d97a3a]abyss[/color]
#   Subtle bob:      [wave amp=10 freq=4]ever[/wave]
#   Frantic shake:   [shake rate=18 level=3]doom[/shake]
#   Opacity pulse:   [pulse freq=1.4 color=#ff5500]heart[/pulse]
#
# Stack tags freely: [color=#cc2a2a][wave amp=12 freq=3]abyss[/wave][/color].
# Wave bobs the letters vertically (Hades-style). Shake jitters violently
# (use for dread, panic). Pulse breathes opacity (use for slow menace).
# Stay around 1 emphasis word per paragraph; multiple per beat reads as broken
# rendering. Single quotes and parentheses around tags are NOT required.

const EVENTS: Dictionary = {
	"butcher": {
		"name": "The Butcher",
		"desc": "A burly figure sharpens a cleaver. \"Give me a creature. I'll make it stronger... sort of.\"",
		"choices": [
			{
				"label": "Lay one on the block\n\nIt comes back with +2 ATK\nand Wither 1. Use it soon.",
				"desc": "Buff a creature: +2 ATK, Wither 1",
				"effects": [
					{"type": "butcher_buff"},
				],
			},
			{
				"label": "Sell him a creature\n\nHe pays by the pound — the heavier\nthe cut, the heavier the purse.",
				"desc": "Sacrifice a creature for gold (scales with its ATK)",
				"effects": [
					{"type": "sacrifice_pick", "reward": "gold", "base": 20, "per_atk": 6,
						"prompt": "Sell which creature? He pays by the pound."},
				],
			},
			{
				"label": "Buy a slab off the hook\n\nForty coins. It bleeds in your pack\nand stands in your line come the next fight.",
				"desc": "-40 gold; next fight starts with a 3/5 Hooked Slab",
				"effects": [
					{"type": "gold", "value": -40},
					{"type": "gift_creature", "name": "Hooked Slab", "atk": 3, "hp": 5, "kw": [],
						"text": "The slab will stand in your line next fight."},
				],
			},
		],
	},

	"thrice_blessed_spring": {
		"name": "The Thrice-Blessed Spring",
		"desc": "A spring boils with old miracles. The first sip is always free. After that, the spring starts counting.",
		"gate": {"type": "hp_below_pct", "value": 0.75},
		"choices": [
			{
				"label": "Kneel and drink\n\nSip by sip the miracle runs deeper.\nSomewhere past the third sip, so do the dregs.",
				"desc": "Heal sip by sip — push your luck against the dregs",
				"effects": [
					{"type": "risk_loop", "mode": "bust",
						"open_text": "The water is blood-warm and tastes of copper and church bells. The first sip is always free.",
						"action": "Drink again",
						"action_body": "The surface leans toward your mouth.",
						"leave": "Step back from the water",
						"leave_sub": "Keep what the water gave.",
						"leave_text": "You wipe your mouth and stand. Behind you the spring keeps boiling, gently, for the next thirsty thing.",
						"leave_text_early": "You kneel, and look, and do not drink. The spring files that away.",
						"steps": [
							{"chance": 1.0, "sub": "Heal 5 HP — the first sip is safe.",
								"effects": [{"type": "heal", "value": 5}],
								"text": "Warmth spreads through old aches. The spring hums, pleased with itself."},
							{"chance": 0.75, "sub": "Heal 7 HP — but 1 in 4 the dregs rise.",
								"effects": [{"type": "heal", "value": 7}],
								"text": "Deeper. The miracle reaches bones you had given up on. Something at the bottom shifts its weight."},
							{"chance": 0.55, "sub": "Heal 9 HP — the odds are barely yours now.",
								"effects": [{"type": "heal", "value": 9}],
								"text": "The water level does not drop. You understand, mid-swallow, that the spring is drinking too."},
						],
						"bust": {"effects": [{"type": "add_curse"}],
							"text": "The dregs rise to meet your mouth — old, patient, and glad of the company. Something settles into your deck. The spring goes still, satisfied."},
						"done_text": "The boiling quiets. The spring has no more miracles for you today; the surface films over like a closing eye."},
				],
			},
			{
				"label": "Bottle the overflow\n\nWhat spills past the rim is still a miracle.\nJust a portable, deniable one.",
				"desc": "Gain a Healing Potion",
				"effects": [
					{"type": "gain_potion"},
				],
			},
			{
				"label": "Wash your wounds and move on\n\nNo sip, no debt. The water still helps,\nthe way water does.",
				"desc": "Heal 4 HP",
				"effects": [
					{"type": "heal", "value": 4},
				],
			},
		],
	},

	"pawnbrokers_window": {
		"name": "The Pawnbroker's Window",
		"desc": "Behind smoked glass, the pawnbroker fans her wares. She does not sell. She buys — but only what interests her, and the first figure she names is always the best one.",
		"choices": [
			{
				"label": "Slide your pack through the slot\n\nShe pulls out what interests HER.\nIt is never what you would have chosen to sell.",
				"desc": "She appraises cards from your deck — sell, or ask for another (her offers cool)",
				"effects": [
					{"type": "pawn_appraisal"},
				],
			},
			{
				"label": "Trade Coin\n\nLeave 60 gold on the sill.\nUpgrade a card you choose.",
				"desc": "-60 gold, upgrade a chosen card",
				"effects": [
					{"type": "gold", "value": -60},
					{"type": "upgrade_choice"},
				],
			},
			{
				"label": "Trade Future\n\nGain a Curse.\nTake a rare card.",
				"desc": "+1 Curse, +1 rare card",
				"effects": [
					{"type": "add_curse"},
					{"type": "add_rare"},
				],
			},
		],
	},

	"fork_in_the_long_road": {
		"name": "The Fork in the Long Road",
		"desc": "Two paths split the moor. One smells of woodsmoke. The other, of iron. The smell is all the road will tell you in advance.",
		"choices": [
			{
				"label": "The Smoke Road\n\nWoodsmoke means people.\nUsually. You walk it and find out.",
				"desc": "Comfort of some kind waits — the road decides which",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 3,
							"text": "The smoke is an inn, and the inn is real: a hearth, a stew, a bed with one previous owner. You leave coin on the counter and stiffness on the mattress.",
							"effects": [{"type": "gold", "value": -30}, {"type": "heal", "value": 9}]},
						{"weight": 2,
							"text": "The smoke is a tollman's brazier. He names a price for the warm road, and the warm road is worth it — you sleep deep and wake tougher than you've been in years.",
							"effects": [{"type": "gold", "value": -40}, {"type": "gain_max_hp", "value": 4}]},
						{"weight": 1,
							"text": "The smoke is a cold campfire, hours dead, with a purse forgotten beside it. Whoever slept here left in a hurry, in the direction you are not going.",
							"effects": [{"type": "gold", "value": 25}]},
					]},
				],
			},
			{
				"label": "The Iron Road\n\nIron means a fight happened.\nOr is still happening. You walk it and find out.",
				"desc": "Spoils of some kind wait — the road decides whose",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 3,
							"text": "A skirmish, finished this morning by the look of the crows. The dead are nobody's now. Their purses come to you heavier than your conscience.",
							"effects": [{"type": "damage", "value": 6}, {"type": "gold", "value": 75}]},
						{"weight": 2,
							"text": "Among the fallen, an officer — and on the officer, something fine that survived him. Pulling it free costs you a bad moment with something that wasn't quite done dying.",
							"effects": [{"type": "damage", "value": 3}, {"type": "random_relic"}]},
						{"weight": 1,
							"text": "The field is quiet. Too quiet, too tidy — the dead are arranged. You take the coin laid on their eyes and feel the road remember you doing it.",
							"effects": [{"type": "gold", "value": 50}, {"type": "add_curse"}]},
					]},
				],
			},
		],
	},

	"the_crossing": {
		# Phase 2.5 — fires at bridge-flagged nodes (the plate painted the
		# bridge on the road in; this room honors it). First bridge of the
		# run always rolls it (_pick_event override); later bridges compete
		# normally via the at_bridge gate.
		"name": "The Crossing",
		"desc": "The river runs brown and fast under a bridge of black timber. A chain hangs across the far end, and three men who do not introduce themselves lean on it. The toll is whatever you look like you can pay.",
		"gate": {"type": "at_bridge"},
		"art": "tollkeeper_bridge",
		"choices": [
			{
				"label": "Pay the toll\n\nThey count it twice.\nThe chain comes down.",
				"desc": "-45 gold",
				"effects": [
					{"type": "gold", "value": -45},
				],
			},
			{
				"label": "Force the bridge\n\nThree men, one chain, and you.\nSomebody is wrong about how this goes.",
				"desc": "Take the bridge by force — the scrap decides the price",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The chain holds longer than the men do. Not quite long enough. You cross with their toll box under your arm and one of their boot prints on your ribs.",
							"effects": [{"type": "damage", "value": 4}, {"type": "gold", "value": 60}]},
						{"weight": 1,
							"text": "They are better at this than they look — leaning on that chain is what they do all day. You cross, in the end, but the toll box is light and your nose will set crooked.",
							"effects": [{"type": "damage", "value": 9}, {"type": "gold", "value": 15}]},
					]},
				],
			},
			{
				"label": "Ford the river downstream\n\nThe water is patient.\nIt takes something from everyone.",
				"desc": "-3 HP, +1 Curse",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "add_curse"},
				],
			},
		],
	},

	"beekeeper": {
		"name": "The Beekeeper",
		"desc": "She wears no veil. The bees have made a hood of her face, and they move when she speaks. 'I have honey,' she says. 'And other things. The hive remembers everything that has ever stung.'",
		"choices": [
			{
				"label": "Take the honey jar\n\nIt is warm.\nIt is moving.",
				"desc": "+10 HP, +1 Curse",
				"effects": [
					{"type": "heal", "value": 10},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Let them sting you\n\nThe hive shudders.\nSomething is given back.",
				"desc": "-4 HP, upgrade a chosen card",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "upgrade_choice"},
				],
			},
			{
				"label": "Ask what the hive remembers\n\nShe smiles.\nThe bees do not.",
				"desc": "Remove 1 chosen card",
				"effects": [
					{"type": "remove_choice"},
				],
			},
		],
	},

	"burning_cradle": {
		"name": "The Burning Cradle",
		"desc": "A wicker cradle sits in the middle of the path, alight. Nothing is inside it. Nothing has [color=#d97a3a][wave amp=10 freq=4]ever[/wave][/color] been inside it. It rocks anyway.",
		"gate": {"type": "hp_below_pct", "value": 0.75},
		"choices": [
			{
				"label": "Kneel and sing to it\n\nThe flames lean toward your mouth\nlike they know the words. You give them one.",
				"desc": "Heal to full, lose 3 max HP",
				"effects": [
					{"type": "heal_full"},
					{"type": "lose_max_hp", "value": 3},
				],
			},
			{
				"label": "Put it out with your cloak\n\nThe cradle goes cold.\nSo does something in your chest.",
				"desc": "-40 gold, +random relic",
				"effects": [
					{"type": "gold", "value": -40},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Walk past. It is not yours.\n\nYou hear it rocking for an hour after.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"woodcutter": {
		"name": "The Woodcutter",
		"desc": "He has been chopping the same tree for thirty years. The tree has not gotten smaller. He has. 'Swing for me,' he says, 'and I'll teach you the trick of it. Most don't get it the first swing.'",
		"choices": [
			{
				"label": "Take the axe and swing\n\nEvery swing costs you something.\nSomewhere in there, the trick clicks.",
				"desc": "-2 HP a swing until the trick clicks — then upgrade a chosen card",
				"effects": [
					{"type": "risk_loop", "mode": "jackpot",
						"open_text": "The axe is heavier than it looks. Most things are. He steps back into the shade to watch, arms folded, patient as the tree.",
						"action": "Swing again",
						"action_body": "Your shoulders already know this will hurt.",
						"leave": "Hand back the axe",
						"leave_sub": "Some tricks aren't worth the blisters.",
						"leave_text": "He takes the axe without judgment. \"The tree will wait,\" he says. \"It's good at that.\"",
						"leave_text_early": "You leave the axe where it leans. He nods, like that was also a kind of answer.",
						"steps": [
							{"chance": 0.34, "sub": "-2 HP — 1 in 3 the trick clicks.",
								"effects": [{"type": "damage", "value": 2}],
								"text": "The blade skips off the grain. \"Lower,\" he says. \"It's always lower than you think.\""},
							{"chance": 0.5, "sub": "-2 HP — even odds now.",
								"effects": [{"type": "damage", "value": 2}],
								"text": "Closer. The tree rings like a bell, and the sound stays in your wrists. He leans forward, almost interested."},
							{"chance": 1.0, "sub": "-2 HP — this one lands.",
								"effects": [{"type": "damage", "value": 2}],
								"text": ""},
						],
						"jackpot": {"modal": "upgrade_choice",
							"text": "The trick clicks through your arms like a key turning. You see, suddenly, where everything you carry has been heavy in the wrong place."}},
				],
			},
			{
				"label": "Work the tree in his place\n\nHe sits in the shade and counts coins\nhe'd forgotten he owned. Your arms ache for days.",
				"desc": "+40 gold, -3 HP",
				"effects": [
					{"type": "gold", "value": 40},
					{"type": "damage", "value": 3},
				],
			},
			{
				"label": "Tell him the tree is winning\n\nHe nods, takes the dull blade from your\npack, and throws it on the pile. \"Travel lighter.\"",
				"desc": "Remove a chosen card",
				"effects": [
					{"type": "remove_choice"},
				],
			},
		],
	},

	"char_widow": {
		"name": "The Char-Widow's Pyre",
		"desc": "A woman feeds her wedding dress to a fire one inch at a time. She has been doing this since the meadow began to burn. 'Throw something in,' she says without looking up. 'It helps.'",
		"choices": [
			{
				"label": "Throw in a fistful of gold\n\nIt melts.\nShe sighs like a kettle.",
				"desc": "-50 gold, +8 HP",
				"effects": [
					{"type": "gold", "value": -50},
					{"type": "heal", "value": 8},
				],
			},
			{
				"label": "Throw in two of your cards\n\nThey curl, blacken, are gone.\nYou feel lighter.",
				"desc": "Remove 2 chosen cards",
				"effects": [
					{"type": "remove_choice_multi", "value": 2},
				],
			},
			{
				"label": "Throw in your own sleeve\n\nShe finally looks up.\nShe knows you now.",
				"desc": "-5 HP, +random relic",
				"effects": [
					{"type": "damage", "value": 5},
					{"type": "random_relic"},
				],
			},
		],
	},

	"gravesong_choir": {
		"name": "The Gravesong Choir",
		"desc": "Four hooded singers stand around an open grave, humming a tune you almost recognize. One pauses, lifts a finger to her lips, and beckons toward the empty fifth place in the circle.",
		"choices": [
			{
				"label": "Take the fifth place and sing\n\nVerse by verse, the soil gives up its grave-gifts.\nVerse by verse, the song learns your voice.",
				"desc": "Sing verse by verse — grave-gifts surface until the song turns",
				"effects": [
					{"type": "risk_loop", "mode": "bust",
						"open_text": "You step into the circle. The hum threads itself through your teeth without asking. The grave at the center is empty, and listening.",
						"action": "Sing the next verse",
						"action_body": "The harmony opens a place for you in it.",
						"leave": "Bow out of the circle",
						"leave_sub": "Keep what the soil gave up.",
						"leave_text": "You step back. The choir closes the gap without looking, and the song goes on without your name in it. That is the best ending this song has.",
						"leave_text_early": "You do not sing. The fifth place stays open behind you for a long way down the road.",
						"steps": [
							{"chance": 1.0, "sub": "Gain 25 gold — the first verse is welcome.",
								"effects": [{"type": "gold", "value": 25}],
								"text": "The soil stirs. A coin purse surfaces beside your boot like something coming up for air."},
							{"chance": 0.7, "sub": "Gain 35 gold — 3 in 10 the song turns.",
								"effects": [{"type": "gold", "value": 35}],
								"text": "A ring. A chain. A saint's little finger in silver. The choir sings louder, and the grave is not so empty now."},
							{"chance": 0.5, "sub": "A grave-gift surfaces — even odds the song turns.",
								"effects": [{"type": "random_relic"}],
								"text": "Something old and well-made works its way up out of the dark, wrapped in a winding-sheet the size of a kerchief."},
						],
						"bust": {"effects": [{"type": "add_curse"}],
							"text": "The song turns on the high note. It walks down your throat, takes a verse of you with it, and lays it in the grave. The choir bows. To you, or to it."},
						"done_text": "The hum fades. The grave is full now, though you never saw anything go in. The singers file out past you, and one squeezes your arm — kindly, you decide."},
				],
			},
			{
				"label": "Lay 2 cards in the grave\n\nThe choir sings them down.\nThe song takes a little of you with them.",
				"desc": "-6 HP, remove 2 chosen cards, +1 rare card",
				"effects": [
					{"type": "damage", "value": 6},
					{"type": "remove_choice_multi", "value": 2},
					{"type": "add_rare"},
				],
			},
			{
				"label": "Sing along from the road\n\nThe melody finds a card in your deck\nand sharpens it on the harmony.",
				"desc": "Upgrade a chosen card",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	"glass_familiar": {
		"name": "The Glass Familiar",
		"desc": "A small cat of spun glass watches you from a stone pedestal. It tilts its head. 'Make two of me,' it says, 'or one of anything else.'",
		"choices": [
			{
				"label": "Pay 30 gold\n\nDuplicate a card in\nyour deck twice.",
				"desc": "-30 gold, copy a card x2",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "copy_card"},
					{"type": "copy_card"},
				],
			},
			{
				"label": "Trade a memory\n\nLose 5 HP.\nGain a random relic.",
				"desc": "-5 HP, +random relic",
				"effects": [
					{"type": "damage", "value": 5},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Crack off a shard\n\nNo coin, no blood — just a hairline\nfracture that follows you home.",
				"desc": "Copy a card once, +1 Curse",
				"effects": [
					{"type": "copy_card"},
					{"type": "add_curse"},
				],
			},
		],
	},

	"spellwrights_pact": {
		"name": "The Spellwright's Pact",
		"desc": "An old scribe is hunched over a smoldering page. Ink runs upward off the parchment into the air. 'I'll teach you a true word,' he says, 'but the saying of it costs flesh.'",
		"choices": [
			{
				"label": "Sign in blood\n\nThe word costs flesh to learn.\nIt gives back something rare.",
				"desc": "-8 HP, +1 rare card",
				"effects": [
					{"type": "damage", "value": 8},
					{"type": "add_rare"},
				],
			},
			{
				"label": "Speak the word aloud\n\nIt feeds on every spell you carry. The more\nyou know, the more it pays — and the longer it lingers.",
				"desc": "Gold per spell you own (up to 90); +1 Command next fight",
				"effects": [
					{"type": "scaled", "count": "spells", "per": 7, "cap": 90, "outcome": "gold"},
					{"type": "combat_mana", "value": 1, "text": "The true word hums behind your teeth — +1 Command next fight."},
				],
			},
			{
				"label": "Pay for a clean copy\n\nFifty gold for the page, and the\nscribe's hand steadies one of yours.",
				"desc": "-50 gold, upgrade a chosen card",
				"effects": [
					{"type": "gold", "value": -50},
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ── Recurring NPC: The Beekeeper trilogy ──
	# E1 is "beekeeper" above. E2 and E3 are gated on prior visits — the chain
	# rewards players who engaged with her in the early act, and skipping her
	# in Act 1 just means the later beats never fire.

	"beekeeper_again": {
		"name": "The Beekeeper Again",
		"desc": "She is waiting for you at a bend in the road. Three bees ride her shoulder. Two ride her wrist. \"The hive remembers you,\" she says. \"It sang while you slept. Would you like to hear what it learned?\"",
		"gate": {"type": "all", "gates": [
			{"type": "act_at_least", "value": 2},
			{"type": "seen_all", "events": ["beekeeper"]},
		]},
		"choices": [
			{
				"label": "Press your ear to the hive\n\nThe hum gets into your teeth.\nIt teaches you two things you did not want to know.",
				"desc": "-9 HP, upgrade 2 chosen cards",
				"effects": [
					{"type": "damage", "value": 9},
					{"type": "upgrade_choice_multi", "value": 2},
				],
			},
			{
				"label": "Bring her a card to feed the hive\n\nShe drops it in the honey.\nIt comes out heavier and gone.",
				"desc": "Remove 1 chosen card, +70 gold",
				"effects": [
					{"type": "remove_choice"},
					{"type": "gold", "value": 70},
				],
			},
			{
				"label": "Tell her you don't want to know\n\nShe nods. The hive does not.\nSomething small and heavy lands in your pocket.",
				"desc": "+random relic, +1 Curse",
				"effects": [
					{"type": "random_relic"},
					{"type": "add_curse"},
				],
			},
		],
	},

	"beekeeper_returns": {
		"name": "The Beekeeper Returns",
		"desc": "She is at the path's end before you reach it. The bees are gone. She is wearing a veil now. \"I came to settle, child. You took our honey twice.\"",
		"gate": {"type": "all", "gates": [
			{"type": "act_at_least", "value": 3},
			{"type": "seen_all", "events": ["beekeeper", "beekeeper_again"]},
		]},
		"choices": [
			{
				"label": "Pay the toll in gold\n\nShe counts each coin slowly,\nlike she counts the years.",
				"desc": "Up to -200 gold, +1 rare card, +random relic",
				"effects": [
					{"type": "lose_gold_partial", "value": 200},
					{"type": "add_rare"},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Pay the toll in blood\n\nShe takes the offering\nwith both hands.",
				"desc": "-12 HP, +3 rare cards",
				"effects": [
					{"type": "damage", "value": 12},
					{"type": "add_rare_n", "value": 3},
				],
			},
			{
				"label": "Pay the toll in years\n\nThe veil lifts. You do not look.",
				"desc": "-5 max HP, +random relic",
				"effects": [
					{"type": "lose_max_hp", "value": 5},
					{"type": "random_relic"},
				],
			},
		],
	},

	# ── Multi-stage events (follow_up branches) ──

	"hollow_lantern": {
		"name": "The Hollow Lantern",
		"desc": "A paper lantern hangs in midair. No string. No pole. Inside it, a moth the size of your palm thumps against the paper, again and again. It is trying to get out. Or in.",
		"choices": [
			{
				"label": "Tear it open\n\nThe paper comes apart\nlike old skin.",
				"follow_up": {
					"desc": "The moth lands on your sleeve. It is heavier than it looks. It begins to whisper into the cloth at your wrist.",
					"choices": [
						{
							"label": "Listen\n\nIt knows your name\nand uses it kindly.",
							"desc": "+5 HP, upgrade a chosen card",
							"effects": [
								{"type": "heal", "value": 5},
								{"type": "upgrade_choice"},
							],
						},
						{
							"label": "Crush it\n\nIt does not resist.\nIt leaves a smear of light.",
							"desc": "+random relic, +1 Curse",
							"effects": [
								{"type": "random_relic"},
								{"type": "add_curse"},
							],
						},
					],
				},
			},
			{
				"label": "Hold the lantern and walk on\n\nIt comes with you\nlike it was waiting.",
				"follow_up": {
					"desc": "The moth quiets. The paper glows. By dawn the lantern is dark and the moth is gone. The lantern is warm in your hand, like something owed.",
					"choices": [
						{
							"label": "Open it in the morning\n\nSomething small and bright\nfalls into your palm.",
							"desc": "+random relic",
							"effects": [
								{"type": "random_relic"},
							],
						},
						{
							"label": "Throw it into the river\n\nIt floats a long way\nbefore it sinks.",
							"desc": "+75 gold",
							"effects": [
								{"type": "gold", "value": 75},
							],
						},
					],
				},
			},
		],
	},

	"two_headed_calf": {
		"name": "The Two-Headed Calf",
		"desc": "A calf with two heads stands in the road. One head is asleep. The other watches you with the patience of something that has been told to watch. \"Pick a head,\" it says — though you cannot tell which spoke.",
		"choices": [
			{
				"label": "The sleeping head\n\nIt does not stir at your hand.\nNot yet.",
				"follow_up": {
					"desc": "It opens its eyes. They are blue and very shallow. There is nothing behind them. It nuzzles your hand the way a thing that has been told to nuzzle hands nuzzles a hand.",
					"choices": [
						{
							"label": "Take the warmth\n\nYou rest a while in the road.\nSome of its heat stays in your chest.",
							"desc": "+10 HP, +2 max HP",
							"effects": [
								{"type": "heal", "value": 10},
								{"type": "gain_max_hp", "value": 2},
							],
						},
						{
							"label": "Cut a lock of its hair\n\nIt does not flinch.\nNothing in this calf has ever flinched.",
							"desc": "+random relic, +1 Curse",
							"effects": [
								{"type": "random_relic"},
								{"type": "add_curse"},
							],
						},
					],
				},
			},
			{
				"label": "The waking head\n\nIt watches you decide.",
				"follow_up": {
					"desc": "It asks: 'Which card do you regret most?'",
					"choices": [
						{
							"label": "Show it\n\nIt swallows the card whole.\nThe other head is still asleep.",
							"desc": "Remove a chosen card",
							"effects": [
								{"type": "remove_choice"},
							],
						},
						{
							"label": "Lie\n\nIt smiles the way a calf should not,\nand drops a small coin-purse in the road.",
							"desc": "+50 gold, +1 Curse",
							"effects": [
								{"type": "gold", "value": 50},
								{"type": "add_curse"},
							],
						},
					],
				},
			},
			{
				"label": "Walk on. The calf bleats once.\n\nYou do not turn around.",
				"desc": "+20 gold (found in the road later)",
				"effects": [
					{"type": "gold", "value": 20},
				],
			},
		],
	},

	# ── State-gated events ──

	"sin_eater": {
		"name": "The Sin-Eater",
		"desc": "A man sits at a long table that should not be here. Before him: a single piece of bread, and a knife. \"Lay your worst card here,\" he says, not looking up. \"I will eat it. The price is meat.\"",
		"gate": {"type": "has_curse"},
		"choices": [
			{
				"label": "Feed him a Curse\n\nHe swallows it without water.\nThe price, he said, is meat.",
				"desc": "-3 HP, eat a chosen Curse",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Feed him a starter\n\nHe wants it badly enough\nto pay. He tucks it away for later.",
				"desc": "+50 gold, give a chosen starting card",
				"effects": [
					{"type": "gold", "value": 50},
					{"type": "remove_choice_filtered", "filter": "starter"},
				],
			},
			{
				"label": "Bring nothing\n\nHe nods. The knife sits where it sat.",
				"desc": "+1 gold (he flicks one across the table)",
				"effects": [
					{"type": "gold", "value": 1},
				],
			},
		],
	},

	"fattened_sin_eater": {
		"name": "The Fattened Sin-Eater",
		"desc": "He is the man from the long table, except he is enormous now. The bread before him is gone. There is a feast in its place. He grins. \"You fed me well. Sit. I've saved you a seat.\"",
		"gate": {"type": "all", "gates": [
			{"type": "act_at_least", "value": 3},
			{"type": "seen_all", "events": ["sin_eater"]},
		]},
		"choices": [
			{
				"label": "Sit and eat with him\n\nHe carves like he means it.\nThe portion he gives you is his own.",
				"desc": "Heal to full, +2 max HP, -30 gold, remove 1 chosen card",
				"effects": [
					{"type": "heal_full"},
					{"type": "gain_max_hp", "value": 2},
					{"type": "gold", "value": -30},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Trade him another Curse\n\nHe takes it gently and lays it\non the side of his plate.",
				"desc": "+random relic, eat a chosen Curse",
				"effects": [
					{"type": "random_relic"},
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Decline\n\nHe wraps a meal for you to take.\nThe bread is real.",
				"desc": "+60 gold",
				"effects": [
					{"type": "gold", "value": 60},
				],
			},
		],
	},

	"tooth_witch": {
		"name": "The Tooth-Witch",
		"desc": "She has been waiting a long time and is not surprised by you. The road bends toward her chair, not away from it. \"You're bleeding, dear. Sit. I have a remedy. The fee is small — a single tooth.\"",
		"gate": {"type": "hp_below_pct", "value": 0.5},
		"choices": [
			{
				"label": "Sit and bare your jaw\n\nShe is gentler than expected.\nIt is still the worst hour of your day.",
				"desc": "Heal to full, -2 max HP permanently",
				"effects": [
					{"type": "heal_full"},
					{"type": "lose_max_hp", "value": 2},
				],
			},
			{
				"label": "Trade a memory instead\n\nShe takes it with the same forceps.",
				"desc": "Heal to full, remove a random card",
				"effects": [
					{"type": "heal_full"},
					{"type": "remove_cards", "value": 1},
				],
			},
			{
				"label": "Limp on\n\nThe chair creaks. She watches you go.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	# Keyed "hermit" (not "last_tinker") so it loads assets/events/hermit.png —
	# the lone figure with a cart of other people's belongings. Display name is
	# still "The Last Tinker"; the key only drives the art + events_seen lookup.
	"hermit": {
		"name": "The Last Tinker",
		"desc": "A man with no shop sits by a loaded cart, sorting other people's belongings. He looks up when you approach, as if he had been waiting for this specific collection of mistakes. \"You brought too many,\" he says. \"I'll keep what's heaviest.\"",
		"gate": {"type": "deck_at_least", "value": 18},
		"choices": [
			{
				"label": "Set them in front of him\n\nHe weighs each one in his palm.\nHe does not give them back.",
				"desc": "Remove up to 3 chosen cards",
				"effects": [
					{"type": "remove_choice_multi", "value": 3},
				],
			},
			{
				"label": "Let him pick the second\n\nHe always picks the one that hurts.",
				"desc": "-1 chosen card, -1 random card, +random relic",
				"effects": [
					{"type": "remove_choice"},
					{"type": "remove_cards", "value": 1},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Walk on\n\nHe hands you a coin: \"for the burden.\"",
				"desc": "+20 gold",
				"effects": [
					{"type": "gold", "value": 20},
				],
			},
		],
	},

	# ── Atmospheric singles ──

	"drowned_bell": {
		"name": "The Drowned Bell",
		"desc": "A bronze bell sits in the path, half-sunk in mud. Its tongue is missing. Water beads on the metal though there has been no rain in weeks.",
		"choices": [
			{
				"label": "Strike it with your fist\n\nThe sound will carry.\nYou will not get to choose what hears it.",
				"desc": "Something answers the bell — the river decides what",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The tone rolls out flat across the mud, wrong without its tongue, and something answers it: between one blink and the next there is a gift at your feet, and a bruise blooming on the arm that struck.",
							"effects": [{"type": "damage", "value": 5}, {"type": "random_relic"}]},
						{"weight": 2,
							"text": "The bell coughs up river water that was never inside it — and coins with it, old ones, green with the deep, payment from whoever sank it.",
							"effects": [{"type": "gold", "value": 55}]},
						{"weight": 1,
							"text": "Nothing answers. Nothing at all. The silence is the answer, and it follows you up the road and settles into your deck to wait with the patience of drowned things.",
							"effects": [{"type": "add_curse"}, {"type": "gold", "value": 25}]},
					]},
				],
			},
			{
				"label": "Pry it up and take it\n\nThe mud slides off cleaner than it should.\nSomeone has already paid the price for this.",
				"desc": "+60 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 60},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Kneel beside it\n\nWhatever you are listening for,\nyou hear something else. It teaches you.",
				"desc": "Upgrade a chosen card",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	"hanged_mapmaker": {
		"name": "The Hanged Mapmaker",
		"desc": "He hangs from a low branch by his own bootlaces. The map he was making is still in his pocket. The ink is wet.",
		"choices": [
			{
				"label": "Take the map\n\nIt shows a road that wasn't here\nbefore he started drawing it.",
				"desc": "+random relic, +1 Curse",
				"effects": [
					{"type": "random_relic"},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Cut him down and bury him\n\nThe shovel was easier to find\nthan it should have been.",
				"desc": "Remove a chosen card (a burden you set down)",
				"effects": [
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Walk past\n\nA few steps on, his purse is in the road.\nHe must have known where to drop it.",
				"desc": "+10 gold",
				"effects": [
					{"type": "gold", "value": 10},
				],
			},
		],
	},

	"rotting_carnival": {
		"name": "The Rotting Carnival",
		"desc": "Three tents stand in a field. The barker is asleep at his post, or dead at his post; you can't tell, and he won't say. A handwritten sign reads: PICK ONE. WE ARE NOT RESPONSIBLE FOR WHAT THE TENTS REMEMBER. You may listen at the flaps, but the tents only show what they do once you're inside.",
		"choices": [
			{
				"hidden": true,
				"tell": "From the red tent: a thock — thock — thock of blades into wood, and polite applause from no hands at all.",
				"desc": "Hidden",
				"effects": [
					{"type": "upgrade_random"},
					{"type": "damage", "value": 4},
				],
			},
			{
				"hidden": true,
				"tell": "From the yellow tent: incense, shuffled cards, and the slow count of coins that are not being spent.",
				"desc": "Hidden",
				"effects": [
					{"type": "gold", "value": 80},
					{"type": "add_curse"},
				],
			},
			{
				"hidden": true,
				"tell": "The black tent makes no sound and smells of nothing at all. The flap hangs open exactly your width.",
				"desc": "Hidden",
				"effects": [
					{"type": "random_relic"},
					{"type": "remove_cards", "value": 1},
				],
			},
		],
	},

	"empty_wedding": {
		"name": "The Empty Wedding",
		"desc": "A long table is set for fifty. Plates of food, untouched, slowly cooling. At the head, a man in a wedding suit eats alone. He has been doing this since the meadow began to burn. \"Sit,\" he says. \"There's room.\"",
		"gate": {"type": "hp_below_pct", "value": 0.75},
		"choices": [
			{
				"label": "Sit and eat\n\nThe wine is good. The bread is warm.\nThe candles do not burn down. Neither, now, do you.",
				"desc": "Heal to full, +1 Curse",
				"effects": [
					{"type": "heal_full"},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Take a plate for the road\n\nThe plate stays warm in your hand\nthe whole way back to the road.",
				"desc": "+10 HP, +20 gold",
				"effects": [
					{"type": "heal", "value": 10},
					{"type": "gold", "value": 20},
				],
			},
			{
				"label": "Raise his glass to him\n\nHe nods. He hands you a coin\nfrom the bride's empty place.",
				"desc": "+40 gold",
				"effects": [
					{"type": "gold", "value": 40},
				],
			},
		],
	},

	# ── Ritual event (pick-a-card transformation) ──

	"mirror_twin": {
		"name": "The Mirror-Twin",
		"desc": "A still pool. Your reflection is wrong — older, sharper, certain. It points at one of your cards. \"I want that one,\" it says. \"Push it through. I'll send something back.\"",
		"choices": [
			{
				"label": "Push a creature through\n\nThe pool keeps it.\nWhat returns is hungrier.",
				"desc": "Pick a creature: HP → 1, ATK +4",
				"effects": [
					{"type": "mirror_twin_buff"},
				],
			},
			{
				"label": "Push thirty coins through\n\nThe water doesn't ripple.\nSomething heavier comes back out.",
				"desc": "-30 gold, +random relic",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Send a twin to fight\n\nThe surface bulges. Something with your\nshape steps out and walks the road beside you.",
				"desc": "Next fight starts with a 3/3 Reflection",
				"effects": [
					{"type": "gift_creature", "name": "Reflection", "atk": 3, "hp": 3, "kw": [],
						"text": "Your reflection will fight beside you next fight."},
				],
			},
		],
	},

	# ── No-good-choice tax event ──

	"tollkeeper_bridge": {
		"name": "The Tollkeeper",
		"desc": "The bridge is the only way forward. The tollkeeper fills the chair at the far end. Behind her: a wedding ring, a fox skull, a child's drawing of a house, a long brown braid. She does not speak. She does not need to.",
		"choices": [
			{
				"label": "Empty your purse onto her palm\n\nShe counts it slowly.\nShe counts it slowly again.",
				"desc": "-60 gold",
				"effects": [
					{"type": "gold", "value": -60},
				],
			},
			{
				"label": "Hold out your hand\n\nShe takes what she takes.\nShe is not gentle.",
				"desc": "-8 HP",
				"effects": [
					{"type": "damage", "value": 8},
				],
			},
			{
				"label": "Tell her something true\n\nShe nods. You walk on.\nThere is a hole in your sentences now.",
				"desc": "+1 Curse, -1 random card",
				"effects": [
					{"type": "add_curse"},
					{"type": "remove_cards", "value": 1},
				],
			},
		],
	},

	# ── Relic-keyed event ──

	"old_forge": {
		"name": "The Old Forge",
		"desc": "Smoke rises from a forge that has no fire. The smith is bent at the anvil, polishing something old. He looks up. \"You collect. I make. Trade me one. I make heavy things from light ones.\"",
		"gate": {"type": "has_nonstarting_relic"},
		"choices": [
			{
				"label": "Lay one of your things on the anvil\n\nHe pries it open.\nThe pieces inside are not the pieces you'd have guessed.",
				"desc": "Trade a chosen relic for a rare-tier relic",
				"effects": [
					{"type": "relic_sacrifice_pick"},
				],
			},
			{
				"label": "Pay him in coin\n\nHe slides a finished piece across the bench\nwithout looking up.",
				"desc": "-100 gold, +random relic",
				"effects": [
					{"type": "gold", "value": -100},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Let him hammer your blade\n\nHe holds it in the cold coals until they\nremember heat. It comes out keener.",
				"desc": "-3 HP, upgrade a chosen card",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ── Hidden-info event ──

	"three_doors": {
		"name": "The Three Warm Handles",
		"desc": "Three doors stand in a clearing with nothing around them. The handles are warm. They are not warm the same. One pulses.",
		"choices": [
			{
				"hidden": true,
				"tell": "The left door smells faintly of iron.",
				"desc": "Hidden",
				"effects": [
					{"type": "random_relic"},
				],
			},
			{
				"hidden": true,
				"tell": "The middle door is warm to the touch.",
				"desc": "Hidden",
				"effects": [
					{"type": "heal_full"},
					{"type": "gain_max_hp", "value": 5},
				],
			},
			{
				"hidden": true,
				"tell": "The right door hums, just at the edge of hearing.",
				"desc": "Hidden",
				"effects": [
					{"type": "gold", "value": 150},
					{"type": "add_curse"},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── Delayed-payoff event ──

	"marked_one": {
		"name": "The One With Your Face",
		"desc": "Someone is standing in the road. They have your face. They hold out a thumb dark with charcoal. \"Take my mark. It comes due in the next fight. Pick where to wear it.\"",
		"choices": [
			{
				"label": "On the hand\n\nThe smudge crawls under your fingernail.\nIt will be there when you raise your hand to fight.",
				"desc": "Next fight: start with a 2/3 Vanguard in front-left",
				"effects": [
					{"type": "mark_hand"},
				],
			},
			{
				"label": "On the heart\n\nIt sinks in. There is a second heartbeat\nbehind your own, just for a while.",
				"desc": "Next fight: +1 max Command the whole fight",
				"effects": [
					{"type": "mark_heart"},
				],
			},
			{
				"label": "On the blood\n\nThey press the thumb to an open cut. It costs\nyou now and stands huge beside you later.",
				"desc": "-6 HP now; next fight starts with a 4/5 Effigy",
				"effects": [
					{"type": "damage", "value": 6},
					{"type": "gift_creature", "name": "Charcoal Effigy", "atk": 4, "hp": 5, "kw": [],
						"text": "The effigy will rise in your front line next fight."},
				],
			},
		],
	},

	# ── Choose-from-curated-pool event ──
	# StS's Designer In-Spire / Mind Bloom equivalent. Player sees three
	# specific rare cards and picks which one (and which currency to spend).
	# Fixed costs per slot: leftmost always HP, middle always gold, right
	# always curse, so the row reads consistently across visits.

	"strangers_hand": {
		"name": "The Wet Cards",
		"desc": "A stranger sits in the road, dealing cards face-up onto a flat stone. The cards are wet. The stranger looks up only once. \"Each of these is owed to someone. Pay it off — and you take what they leave behind.\"",
		"choices": [
			{
				"label": "Step closer\n\nThe stone is warm.\nSo are the cards.",
				"desc": "Pick from 3 random rares (cost varies)",
				"effects": [
					{"type": "stranger_hand_pick"},
				],
			},
			{
				"label": "Walk past\n\nThe stranger does not look up again.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	# ── Pure-gamble event ──
	# Two independent bets sit on the table (see assets/events/gambler.png): the
	# dice (a gold wager) and a face-down red card (a stake-free relic/curse flip).
	# Both handlers — wager_gold, wager_relic_or_curse — predate this entry.

	"gambler": {
		"name": "The Gambler",
		"desc": "A man sits at a table that wasn't here a breath ago. Dice worn smooth. A fan of cards. One card face-down, red as a wound. He doesn't look up. \"Sit. Everyone plays. The only question is what you set down.\"",
		"choices": [
			{
				"label": "Roll the bones\n\nThe dice are warm.\nThey have been rolled a long, long time.",
				"desc": "Bet 40 gold — even odds to win 100",
				"effects": [
					{"type": "wager_gold", "stake": 40, "payout": 100},
				],
			},
			{
				"label": "Cut the red card\n\nYou do not pay to turn it.\nThat is the part that frightens you.",
				"desc": "Free flip: a relic, or 2 Curses",
				"effects": [
					{"type": "wager_relic_or_curse", "curses": 2},
				],
			},
			{
				"label": "Pocket your coin and go\n\nHe flicks one chip after you.\n\"For the nerve,\" he says, and smiles.",
				"desc": "+5 gold",
				"effects": [
					{"type": "gold", "value": 5},
				],
			},
		],
	},

	# ── Trade / blessing events (art-led) ──
	# Three events built around their illustrations. Each leans on one currency
	# so the row of choices reads cleanly: Collector trades the deck, the Blood
	# Fountain trades flesh, the Mossy Shrine trades a little of everything.

	# Keyed "collector_event" (not "collector") so it loads
	# assets/events/collector_event.png — the reliquary-keeper at his wall of
	# niches. Display name is still "The Collector"; the key only drives the art.
	"collector_event": {
		"name": "The Collector",
		"desc": "A hooded figure tends a wall of little lit niches, each holding a thing that mattered to someone once — a ring, a tooth, a folded note gone brown. At his feet sits an open chest, and a single card lies inside it, face-up, still warm. \"I keep things,\" he says, not turning. \"Show me yours. I always trade up.\"",
		"choices": [
			{
				"label": "Lay a card in his hands\n\nHe turns it over twice, reading something\nprinted on the back that you cannot see.",
				"desc": "Give a chosen card, gain a relic",
				"effects": [
					{"type": "random_relic"},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Take the warm card from the chest\n\nIt is warmer than it should be.\nSomething comes with it that will not let go.",
				"desc": "+1 rare card, +1 Curse",
				"effects": [
					{"type": "add_rare"},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Touch nothing. Keep your things.\n\nHe nods at the wall. \"They all said that,\"\nhe tells the niches. \"Once.\"",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"blood_fountain": {
		"name": "The Blood Fountain",
		"desc": "A ring of stone cherubs weeps into a basin that is not water. By moonlight it looks [color=#8a1010]black[/color]; up close it is red, and warm, and moving very slightly — as if something beneath it were breathing. Rose petals rot on the steps. No voice says drink. The bowl simply waits.",
		"gate": {"type": "hp_below_pct", "value": 0.75},
		"choices": [
			{
				"label": "Drink deeply\n\nIt is thicker than wine and it knows your name.\nYou feel whole. You feel watched.",
				"desc": "Heal to full, +1 Curse",
				"effects": [
					{"type": "heal_full"},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Open a vein and give\n\nThe basin drinks faster than you bleed.\nWhen it stops, something has been left on the rim for you.",
				"desc": "-6 HP, gain a relic",
				"effects": [
					{"type": "damage", "value": 6},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Drink from your cupped hands\n\nA mouthful, no more. Enough to taste.\nNot enough to owe.",
				"desc": "Heal 6 HP",
				"effects": [
					{"type": "heal", "value": 6},
				],
			},
		],
	},

	"mysterious_shrine": {
		"name": "The Mossy Shrine",
		"desc": "A standing stone wears a crown of cold green fire. Someone was here recently — the offering bowls still smoke. The runes spell a language no living mouth remembers, but you understand the shape of the bargain anyway: leave something, take something. The forest holds its breath.",
		"choices": [
			{
				"label": "Press your hand to the runes\n\nThey are ice, and they are teaching.\nYour fingers will ache for a week. You will be better for it.",
				"desc": "-4 HP, upgrade a chosen card",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "upgrade_choice"},
				],
			},
			{
				"label": "Lay a card on the stone\n\nThe green fire takes it without a sound,\nand a weight you'd stopped noticing goes with it.",
				"desc": "Give a chosen card, heal to full",
				"effects": [
					{"type": "heal_full"},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Empty the offering bowls into your bag\n\nThe coins are still warm from other hands.\nSomething in the trees stops breathing, and starts to follow.",
				"desc": "+80 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 80},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── Sacrifice altar (Acolyte payoff) ──
	# The big "feed a creature to the stone" event. Two routes turn a body into
	# permanent value (relic / max HP, scaled to the offering's ATK); the third
	# is a self-blood fallback so the event still pays off with no creature to
	# give. Loads assets/events/dark_altar.png.
	"dark_altar": {
		"name": "The Dark Altar",
		"desc": "A slab of black stone sweats in the dark. Every groove cut into its face runs downhill to a single drain. Something beneath it is patient. Something beneath it is hungry. It does not ask out loud — but you already know the shape of what it wants.",
		"choices": [
			{
				"label": "Offer a creature for power\n\nThe stone drinks it dry and leaves\nsomething hard and humming in the groove.",
				"desc": "Sacrifice a creature; gain a relic",
				"effects": [
					{"type": "sacrifice_pick", "reward": "relic",
						"prompt": "Lay which creature on the altar? The stone wants power."},
				],
			},
			{
				"label": "Offer a creature for life\n\nWhat it takes from the body it pays\nback into yours — the bigger the beast, the more.",
				"desc": "Sacrifice a creature; gain max HP (scales with its ATK)",
				"effects": [
					{"type": "sacrifice_pick", "reward": "max_hp", "base": 3,
						"prompt": "Lay which creature on the altar? The stone offers strength."},
				],
			},
			{
				"label": "Open your own wrist\n\nNo creature, no problem. The groove takes\nblood just as well, and teaches a dark word for it.",
				"desc": "-8 HP, +1 rare card, +1 Curse",
				"effects": [
					{"type": "damage", "value": 8},
					{"type": "add_rare"},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── Travelling smith (upgrade-focused; complements the relic-trading Old Forge) ──
	# Three ways to deal with a smith: coin for two upgrades, blood for one, or
	# melt a dead card down for scrap (removal + gold). Loads
	# assets/events/blacksmith_offer.png.
	"blacksmith_offer": {
		"name": "The Travelling Smith",
		"desc": "His forge is a cart, his anvil a tree stump, his fire something he carries in a clay pot and feeds in secret. \"I don't sell,\" he says, spitting on a blade to read the steam. \"I improve. Bring me what you've got and I'll make it worth carrying.\"",
		"choices": [
			{
				"label": "Pay him to forge\n\nSeventy coins and a long night.\nTwo of your cards come back keener.",
				"desc": "-70 gold, upgrade 2 chosen cards",
				"effects": [
					{"type": "gold", "value": -70},
					{"type": "upgrade_choice_multi", "value": 2},
				],
			},
			{
				"label": "Pump the bellows yourself\n\nNo coin to spare, so you spend\nsweat and skin instead.",
				"desc": "-6 HP, upgrade a chosen card",
				"effects": [
					{"type": "damage", "value": 6},
					{"type": "upgrade_choice"},
				],
			},
			{
				"label": "Give him scrap to melt\n\nHe weighs a card you never play, feeds it\nto the pot, and counts out coin for the metal.",
				"desc": "Remove a chosen card, +40 gold",
				"effects": [
					{"type": "remove_choice"},
					{"type": "gold", "value": 40},
				],
			},
		],
	},

	# ── Comic single (absurd register) ──
	# A stage-fright understudy who has been "playing your part" insists on going
	# on in your place. Pure next-fight gift; the gag is that he is sincerely
	# terrible at it. Ungated — a gift creature is useful at any HP, no dead reward.
	"the_understudy": {
		"name": "The Understudy",
		"desc": "A man in a costume of YOU — same cloak, same scowl, the stitching all wrong — bars the road, trembling. \"I've understudied your part for years,\" he whispers, clutching a script soaked through with notes. \"Let me go on in the next scene. I know all your lines. Most of them. Please.\"",
		"choices": [
			{
				"label": "Let him have the stage\n\nHe weeps with gratitude, fumbles his cloak,\nand marches off the wrong way. He'll find the fight.",
				"desc": "Next fight starts with a 2/6 Understudy in front-left",
				"effects": [
					{"type": "gift_creature", "name": "The Understudy", "atk": 2, "hp": 6, "kw": [],
						"text": "He will throw himself into the next scene, badly."},
				],
			},
			{
				"label": "Coach him for an hour\n\nYou drill the part into him until your throat is raw.\nHe is better for it. You are hoarse for it.",
				"desc": "-4 HP; next fight starts with a 4/7 Understudy",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "gift_creature", "name": "The Understudy", "atk": 4, "hp": 7, "kw": [],
						"text": "He has the lines now. Mostly. He will not let you down. Much."},
				],
			},
			{
				"label": "Buy his script off him\n\nHe surrenders the soaked pages for coin and slinks away.\nThe margins are full of notes in your own hand. You don't remember writing them.",
				"desc": "+45 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 45},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── Grim bargain (currency-of-choice debt) ──
	# A polite ledger-keeper collecting an "old debt" you don't remember owing.
	# Three currencies; the gold cost is build-scaled (per curse you carry), so a
	# clean deck pays little and a cursed deck pays dearly — the debt knows you.
	"the_debt_collector": {
		"name": "The Ledger",
		"desc": "A thin clerk sits at a writing-desk planted in the open road, turning the pages of a ledger longer than he is tall. He runs one inked finger down a column, stops, and looks up — not unkindly. \"Ah. You. There's a balance outstanding from a long way back. I'm only here to settle it. How will you pay?\"",
		"choices": [
			{
				"label": "Pay in coin\n\nHe tallies it against the column.\nThe heavier your ledger, the longer the sum.",
				"desc": "Lose gold (12 per Curse you carry, up to 120)",
				"effects": [
					{"type": "scaled", "count": "curses", "per": 12, "cap": 120, "outcome": "lose_gold"},
				],
			},
			{
				"label": "Pay in blood\n\nHe pricks your thumb, presses it to the page,\nand the ink runs red where you touched it.",
				"desc": "-9 HP, +1 rare card",
				"effects": [
					{"type": "damage", "value": 9},
					{"type": "add_rare"},
				],
			},
			{
				"label": "Sign it over to someone else\n\nHe shrugs, dips his pen, and writes a name in your place.\nYou do not ask whose. The debt does not vanish — it moves.",
				"desc": "Lose a chosen card; gain a random relic",
				"effects": [
					{"type": "random_relic"},
					{"type": "remove_choice"},
				],
			},
		],
	},

	# ── Bleak / horror (face-fruit orchard) ──
	# Trees grow fruit shaped like faces. Heal path gated behind hp_below_pct so a
	# full-HP player never sees a dead "eat to heal" option; the harvest-for-gold
	# path stays live at any HP and carries its own cost (a watching curse).
	"the_weeping_orchard": {
		"name": "The Weeping Orchard",
		"desc": "Rows of pale trees stand in dead air. The fruit hangs heavy and low, and each one has a [color=#c98a3a]face[/color] — eyes shut, mouths slightly open, all of them faintly familiar. As you pass, a few of them begin, very quietly, to cry. The ground beneath is wet, and it is not with rain.",
		"gate": {"type": "hp_below_pct", "value": 0.6},
		"choices": [
			{
				"label": "Eat until you're full\n\nThe fruit is sweet and warm and tastes of someone\nyou loved. You feel it knit you back together. You try not to chew.",
				"desc": "Heal to full; -2 max HP",
				"effects": [
					{"type": "heal_full"},
					{"type": "lose_max_hp", "value": 2},
				],
			},
			{
				"label": "Harvest for market\n\nFruit by fruit, the sack grows heavier.\nFruit by fruit, the orchard pays closer attention.",
				"desc": "Pick fruit by fruit — until something notices",
				"effects": [
					{"type": "risk_loop", "mode": "bust",
						"open_text": "You spread your sack beneath the heaviest tree. The fruit watches you reach. The nearest one has stopped crying, which is somehow worse.",
						"action": "Pick another",
						"action_body": "The branch lowers itself, helpfully.",
						"leave": "Tie the sack and go",
						"leave_sub": "Keep what you've picked.",
						"leave_text": "You shoulder the sack. Behind you the orchard weeps on, softer now, like it's already forgotten which ones you took.",
						"leave_text_early": "You leave the sack empty. A few of the faces smile in their sleep.",
						"steps": [
							{"chance": 1.0, "sub": "Gain 20 gold — the low fruit comes easy.",
								"effects": [{"type": "gold", "value": 20}],
								"text": "It comes off the stem with a sigh. In the sack, it settles like something getting comfortable."},
							{"chance": 0.8, "sub": "Gain 25 gold — 1 in 5 something notices.",
								"effects": [{"type": "gold", "value": 25}],
								"text": "The next one is warmer. Around you, very quietly, the weeping has begun to synchronize."},
							{"chance": 0.6, "sub": "Gain 30 gold — the trees are counting now.",
								"effects": [{"type": "gold", "value": 30}],
								"text": "Heavier still. Somewhere behind you a branch creaks, in the way that floorboards creak under feet."},
							{"chance": 0.4, "sub": "Gain 40 gold — you are pushing it.",
								"effects": [{"type": "gold", "value": 40}],
								"text": "The best fruit hangs highest, of course it does. The whole row is silent now, watching you climb."},
						],
						"bust": {"effects": [{"type": "damage", "value": 5}],
							"text": "A branch closes on your wrist like a hand. The orchard stops weeping all at once, and in the silence you hear how many trees there are. You leave some skin getting loose."},
						"done_text": "The sack will hold no more. The orchard lets you go — generous, the way things are generous when they know where you live."},
				],
			},
			{
				"label": "Bury the one that has your face\n\nYou dig with your hands. It does not struggle.\nThe orchard goes quiet, grateful, and leaves a gift in the dirt.",
				"desc": "-5 HP, +random relic",
				"effects": [
					{"type": "damage", "value": 5},
					{"type": "random_relic"},
				],
			},
		],
	},

	# ── Pure gamble (absurd register) — reuses wager handlers from The Gambler ──
	# A coin spinning on its edge that will not fall. Two independent bets plus a
	# small consolation so leaving is never a fully dead option.
	"coin_on_edge": {
		"name": "The Coin That Won't Land",
		"desc": "A silver coin spins on its edge in the middle of the path. It has been spinning, by the look of the worn groove beneath it, for a very long time. It does not wobble. It does not slow. A small sign, propped against a stone, reads in a neat hand: CALL IT.",
		"choices": [
			{
				"label": "Put your stake down and call it\n\nDouble or nothing, as many times as your nerve holds.\nThe coin has all day. The coin has all century.",
				"desc": "Stake 25 gold — the pot doubles on every call, even odds it all goes",
				"effects": [
					{"type": "dice_run", "stake": 25, "start": 40,
						"mode": "double", "bust_pct": 0.5,
						"broke_text": "You haven't 25 gold to stake. The coin spins on, unbothered. It has been refused by poorer.",
						"open_text": "You lay your stake in the groove beside the spinning silver. The pot stands at {pot} gold. The coin picks up speed, which should not be possible, and is.",
						"roll_label": "Call it again",
						"roll_sub": "Even odds: the pot doubles — or the coin lands and takes it all.",
						"roll_body": "The coin is enjoying this. You can tell.",
						"bank_label": "Take the pot",
						"bank_sub": "Take {pot} gold and walk.",
						"bank_body": "Some bets are best left spinning.",
						"grow_text": "It blurs, leans, nearly topples — and rights itself, still spinning. The pot stands at {pot} gold. Somewhere behind the sign, something exhales.",
						"bust_text": "The coin falls flat at last. Tails. Your stake and the pot slide into the groove it has worn in the road, and are gone. The coin stands back up on its edge and resumes spinning.",
						"bank_text": "You bank {pot} gold and step back. The coin spins on, patient. The sign, you notice now, has your handwriting on it."},
				],
			},
			{
				"label": "Stop it with your finger\n\nNo wager, no warning — just the nerve to touch it.\nWhatever side it shows when it stops, it shows to you.",
				"desc": "Free flip: a relic, or 2 Curses",
				"effects": [
					{"type": "wager_relic_or_curse", "curses": 2},
				],
			},
			{
				"label": "Leave it spinning\n\nYou step around it. A single coin has fallen flat in the dust\nnearby — heads — left by someone who also knew better.",
				"desc": "+10 gold",
				"effects": [
					{"type": "gold", "value": 10},
				],
			},
		],
	},

	# ── War / grim bargain (recruiter for an army that isn't there) ──
	# A sergeant enlisting for a war no one remembers. Trade a creature for back
	# pay (sacrifice_pick → gold, scales with ATK), buy a soldier for the next
	# fight, or take the bounty and a curse. Routes sacrifice through the existing
	# modal, honoring the no-free-sacrifice rule.
	"the_quiet_recruiter": {
		"name": "The Recruiter",
		"desc": "A sergeant in a uniform fifty years out of fashion sits behind a folding table, a muster-roll spread before him and not one other soul in sight. \"Recruiting,\" he says, tapping the empty roll. \"For the campaign. You'll have heard of it.\" You have not. \"No matter. Everyone marches eventually. Sign something over and I'll see you're looked after.\"",
		"choices": [
			{
				"label": "Enlist one of your own\n\nHe enters the name on the roll with great ceremony, then\ncounts out back pay from a strongbox — by the recruit's measure.",
				"desc": "Enlist a creature for gold (scales with its ATK)",
				"effects": [
					{"type": "sacrifice_pick", "reward": "gold", "base": 25, "per_atk": 7,
						"prompt": "Sign which creature onto the roll? He pays by their measure."},
				],
			},
			{
				"label": "Hire a soldier off the roll\n\nFifty coins, and a grey-faced veteran rises from the bench,\nshoulders his pack without a word, and falls in beside you.",
				"desc": "-50 gold; next fight starts with a 3/5 Conscript",
				"effects": [
					{"type": "gold", "value": -50},
					{"type": "gift_creature", "name": "Grey Conscript", "atk": 3, "hp": 5, "kw": [],
						"text": "The conscript will hold the line beside you next fight."},
				],
			},
			{
				"label": "Take the signing bounty and walk\n\nHe presses coin into your hand and stamps the roll anyway.\nYou are on it now. You feel the ink settle somewhere behind your ribs.",
				"desc": "+55 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 55},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── Two-stage branching (folk horror) — answering well ──
	# A well that answers questions you haven't asked. Each branch swaps to a
	# follow_up screen. Deliberately NOT heal-centered, so it stays ungated with
	# no dead reward; every leaf carries a real cost or variance.
	"the_answering_well": {
		"name": "The Answering Well",
		"desc": "An old stone well stands in a clearing, its bucket long rotted from the rope. As you lean over the lip, a voice rises out of the dark below — calm, patient, and pitched exactly like your own. It answers a question you are quite certain you did not ask aloud.",
		"choices": [
			{
				"label": "Ask it something you've always feared to\n\nThe water far below shifts.\nThe voice draws a slow breath it does not have.",
				"follow_up": {
					"desc": "It tells you. It is worse than you guessed, and truer, and the knowing settles into you like cold water into cloth. \"There,\" it says. \"Now you carry it too. Will you keep what I've given, or pour it back?\"",
					"choices": [
						{
							"label": "Keep the knowing\n\nIt sharpens something in you — a lesson\nyou will not be able to unlearn.",
							"desc": "-6 HP, upgrade a chosen card",
							"effects": [
								{"type": "damage", "value": 6},
								{"type": "upgrade_choice"},
							],
						},
						{
							"label": "Pour it back down the well\n\nYou let the answer go. It falls a long way.\nSomething heavy in your pack falls with it.",
							"desc": "Remove a chosen card",
							"effects": [
								{"type": "remove_choice"},
							],
						},
					],
				},
			},
			{
				"label": "Drop a coin and make a wish\n\nIt does not splash. You wait\nfor the sound. It never comes.",
				"follow_up": {
					"desc": "The voice laughs, softly, the way you laugh when no one is meant to hear. \"A wish. How quaint. The well grants — it simply never grants the part you wanted.\" Something rattles up out of the dark and catches on the lip of the stone.",
					"choices": [
						{
							"label": "Take what the well gives\n\nIt is not what you wished for.\nIt is, the voice insists, what you needed.",
							"desc": "+random relic, +1 Curse",
							"effects": [
								{"type": "random_relic"},
								{"type": "add_curse"},
							],
						},
						{
							"label": "Reach deeper for the rest\n\nYour arm goes in to the shoulder.\nThe stone is wet. Something down there is warm.",
							"desc": "-7 HP, +80 gold",
							"effects": [
								{"type": "damage", "value": 7},
								{"type": "gold", "value": 80},
							],
						},
					],
				},
			},
			{
				"label": "Say nothing and walk away\n\nThe voice keeps talking behind you,\nanswering questions, for a long time.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	# ── Transform shrine (new format: card metamorphosis) ──
	# The deck-sculpting verb the pool lacked: not removal, not upgrade —
	# CHANGE. Art borrows the lantern-moth plate until a bespoke cocoon
	# image lands at assets/events/the_chrysalis.png.
	"the_chrysalis": {
		"name": "The Chrysalis Fence",
		"desc": "Someone has strung cocoons along a fence line, each the size of a saddlebag, each gently steaming in the cold. A farmer's sign, repainted many times, reads: ONE IN, ONE OUT. NO PROMISES. The silk nearest you unseams itself a finger's width, politely.",
		"choices": [
			{
				"label": "Feed it a card\n\nThe silk closes over it like a mouth\nthat has been waiting to be a mouth.",
				"desc": "Transform a chosen card into a random card of the same rarity",
				"effects": [
					{"type": "transform_choice", "value": 1},
				],
			},
			{
				"label": "Feed it two, and your hand with them\n\nThe silk tastes you first.\nIt is a fair price for double the change.",
				"desc": "-4 HP, transform 2 chosen cards",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "transform_choice", "value": 2},
				],
			},
			{
				"label": "Cut one down and carry it off\n\nIt hatches in your pack before the next hill.\nBoth halves of it.",
				"desc": "+1 rare card, +1 Curse",
				"effects": [
					{"type": "add_rare"},
					{"type": "add_curse"},
				],
			},
		],
		"art": "hollow_lantern",
	},

	# ── Bridge variant (so repeat crossings aren't always The Crossing) ──
	"the_ferryman": {
		"name": "The Ferryman",
		"desc": "Below the bridge, tied to a post older than the bridge, a flat-bottomed barge waits on a rope line. The ferryman watches the timbers above with open contempt. He remembers when there wasn't a bridge. He is patient. Rivers are on his side.",
		"gate": {"type": "at_bridge"},
		"art": "tollkeeper_bridge",
		"choices": [
			{
				"label": "Pay for the slow water\n\nHe poles you the long way, past the reed beds,\nand you watch the banks like a general. You arrive rested.",
				"desc": "-30 gold; +1 max Command next fight",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "combat_mana", "value": 1,
						"text": "You step off the barge already giving orders — +1 Command next fight."},
				],
			},
			{
				"label": "Work the rope for him\n\nThe current fights you the whole width.\nHe splits the day's tolls without being asked.",
				"desc": "-4 HP, +45 gold",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "gold", "value": 45},
				],
			},
			{
				"label": "Trade him a name for passage\n\nHe writes nothing down. The river\nremembers it for him. It is gone from you by the far bank.",
				"desc": "Remove a chosen card",
				"effects": [
					{"type": "remove_choice"},
				],
			},
		],
	},

	# ── Push-your-luck game (new format: a mini-game that loops) ──
	# dice_run is a real multi-round run, not a one-shot wager — the pot
	# grows 2-in-3 per cast and busts 1-in-3, bank any time. Art borrows the
	# gambler's table until assets/events/the_bone_pit.png exists.
	"the_bone_pit": {
		"name": "The Bone Pit",
		"desc": "Four legionaries, dead these three hundred years, crouch around a shallow pit casting knucklebones cut from their own hands. They have been playing since the empire that owed them wages stopped existing. A space opens in the circle. The rules are short: roll, or bank. The pot is the pot.",
		"art": "gambler",
		"choices": [
			{
				"label": "Take the open seat\n\nThe bones are warm.\nThey should not be warm.",
				"desc": "The pot opens at 25 gold — grow it cast by cast, bank any time, skulls lose it all",
				"effects": [
					{"type": "dice_run", "start": 25},
				],
			},
			{
				"label": "Rob the pot\n\nThey do not stand. They do not speak.\nThey only watch you go, all four, without turning their heads.",
				"desc": "+35 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 35},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Salute the game and pass\n\nThe oldest flicks a coin after you.\n\"For respecting the rules,\" his jaw clicks. \"Few do.\"",
				"desc": "+5 gold",
				"effects": [
					{"type": "gold", "value": 5},
				],
			},
		],
	},
}
