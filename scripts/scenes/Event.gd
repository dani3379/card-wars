extends Control
## Event.gd — Random choice encounters (28: 23 from the 2026-07-03 remake +
## 5 added 2026-07-04). The old pool was mostly currency menus (±gold/±HP/
## Curse in different prose); the remake's bar is ONE concept per event, and
## the payoff should touch the BUILD or the FIGHTING, not just re-price
## currencies. The pool runs on reusable engines:
##   risk_loop   — push-your-luck "do it again?" (choir verses)
##   dice_run    — pot-based wager runs (Bone Pit add-mode, Coin That Won't
##                 Land double-or-nothing)
##   roll_table  — committed-action mystery outcomes (forcing the bridge,
##                 marching blind, the King's Measure)
##   pawn_appraisal / stranger_hand / transform / remove / copy / sacrifice
##                 — card-tactile pickers
##   grant_keyword_pick — a chosen creature PERMANENTLY learns a keyword
##                 (the Pensioned Master; rides the wayside grant_kw mod)
##   veteran_swap — remove every copy of one starter, gain that many
##                 uncommons (the Free Company's one-for-one muster)
##   purge_curses — remove ALL Curses at a max-HP price (the Scapegoat)
##   hidden+tell — Rotting Carnival (reading the tell IS the game)
## Some are state-gated (low HP, has-curse, starters, fallen, act, at_war,
## prior visits, deck_count/pawned/veteran-kills). Quick ONE-DECISION roadside
## stops are NOT events — they're the Wayside scene's verbs (Wayside.gd).
##
## 2026-07-04 presentation pass: stakes ledger (top-right HP/gold/potion/deck
## readout, live on every sub-screen), result screens stand gained cards and
## relics up as objects, gambles get a suspense beat + pot props + bust shake,
## card pickers keep the event art behind a mood scrim, outcome lines open
## with scannable glyphs, blue options wear a diamond (shape, not just ink),
## and events can name a `mood` (title/scrim tint) + `ambience` (loop name).

const MAP_SCENE = "res://scenes/map.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

# Nodes that survive across UI rebuilds within a single event (initial choice
# screen → result screen → continue). Modal sub-pickers (remove/butcher) hide
# the art via _set_event_art_visible() so deck cards stay readable.
const PRESERVE_NODES := [
	"Background", "Atmosphere", "EventArt",
	"EventOverlayLeft", "StakesLedger",
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
	# No decorative corner frame here — over the fullscreen illustration the
	# purple hairline box reads as a stray line, not furniture. The vignette
	# and brightness layers still apply.
	GameTheme.add_atmosphere(self, "event", false)
	AudioBank.play_music_random(["event", "event_b", "event_c"])
	_pick_event()
	# Per-event ambience loop ("river", "carnival", "fire_crackle", ...).
	# AudioBank no-ops gracefully when the asset dir doesn't exist yet, and an
	# event WITHOUT the field stops whatever loop the previous scene left
	# running — either way the soundscape is this event's own.
	AudioBank.play_ambience(String(_event_data.get("ambience", "")))
	_ensure_stakes_ledger()
	_build_ui()
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# An event forces a decision, so Esc opens the pause/Settings overlay rather
	# than resolving a choice for the player.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# The road's sounds stay on the road — never bleed a river loop into the map.
	AudioBank.stop_ambience()


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
# Events without a "gate" field are always eligible.
func _event_gate_passes(event_id: String) -> bool:
	var event = EVENTS.get(event_id, {})
	var gate: Dictionary = event.get("gate", {})
	if gate.is_empty():
		return true
	return _event_gate_passes_dict(gate)


# The one gate dispatcher. Gates are simple type+param dicts so adding a new
# gate is one match arm here. Used by event-level gates, "all" sub-gates, and
# per-choice "blue" gates (the verdigris options that only appear when the
# event recognizes something about the player — hero, relics, deck, history).
func _event_gate_passes_dict(gate: Dictionary) -> bool:
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
		"hero_is":
			return RunState.current_hero_id == String(gate.get("value", ""))
		"upgraded_at_least":
			# Cards carrying ANY mod (forge/drill/banner) — "edge-work".
			return RunState.card_upgrades.size() >= int(gate.get("value", 1))
		"starters_at_least":
			var n := 0
			for cid in RunState.deck:
				if CardDB.get_card_data(cid).get("rarity", "") == "starter":
					n += 1
			return n >= int(gate.get("value", 1))
		"potions_full":
			return not RunState.can_add_potion()
		"fallen_at_least":
			# Campaign memory: at least N names on the Roll of the Fallen. Gates
			# the events that pay the player's actual dead (Bell of Names) and
			# blue options that let {fallen} act (White Road walks point).
			return RunState.fallen.size() >= int(gate.get("value", 1))
		"at_war":
			# A Successor Wars rival deal is live. The war events gate on this
			# so legacy runs with no faction never see a room that names one.
			return RunState.get_act_faction() != ""
		"marching_on":
			# The act's kingdom is a specific faction — for blue options that
			# recognize WHOSE country the army is walking through.
			return RunState.get_act_faction() == String(gate.get("value", ""))
		"pawned_at_least":
			# Campaign memory: the Pawnbroker's shelf still holds N+ cards the
			# player sold through her appraisal counter.
			return RunState.pawned_cards.size() >= int(gate.get("value", 1))
		"veteran_kills_at_least":
			# Campaign memory: some soldier still marching carries N+ kills on
			# the writ — gates the blues that greet the player's famous veteran.
			for uid in RunState.deck_uids:
				if RunState.get_kills(uid) >= int(gate.get("value", 1)):
					return true
			return false
		"deck_count_at_least":
			# Build-reading gate on the same counters "scaled" pays out on
			# (spells / creatures / curses / deathrattle / onecost) — keeps a
			# per-spell payoff from rolling for a spell-less deck (no dead
			# rewards, ever).
			return _deck_count(String(gate.get("kind", "deck_size"))) \
				>= int(gate.get("value", 1))
		"all":
			# Compound — every sub-gate must pass. Used by the Fattened
			# Sin-Eater to combine act + seen_all checks.
			for sub in gate.get("gates", []):
				if not _event_gate_passes_dict(sub):
					return false
			return true
	return true


# ── Event moods ───────────────────────────────────────────────────────────
# A one-word `mood` field on an event tints its title ink and the scrim's
# shadow color, so the Rotting Carnival and the Wedding at the Ford read as
# different rooms before a single word is read. Absent field = the default
# arcane purple the screen has always worn.
#   title — the event title's ink
#   ink   — the scrim shader's shadow color (warm/cool variants of near-black)
const MOODS: Dictionary = {
	"bone":      {"title": Color(0.80, 0.78, 0.70), "ink": Color(0.022, 0.026, 0.030)},
	"ember":     {"title": Color(0.87, 0.54, 0.30), "ink": Color(0.050, 0.020, 0.008)},
	"gilt":      {"title": Color(0.91, 0.71, 0.28), "ink": Color(0.045, 0.032, 0.012)},
	"verdigris": {"title": Color(0.55, 0.78, 0.70), "ink": Color(0.014, 0.032, 0.028)},
}


func _mood_title_ink() -> Color:
	var mood: Dictionary = MOODS.get(String(_event_data.get("mood", "")), {})
	return mood.get("title", GameTheme.SPELL_PURPLE)


func _mood_shadow_ink() -> Color:
	var mood: Dictionary = MOODS.get(String(_event_data.get("mood", "")), {})
	return mood.get("ink", Color(0.035, 0.022, 0.016))


# ── The stakes ledger ─────────────────────────────────────────────────────
# Top-right readout of everything an event choice spends: HP, gold, potions,
# deck size. The screen constantly asks "pay 8 HP?" / "-75 gold" — the ledger
# means the player never has to remember the totals from the map. It survives
# every sub-screen rebuild (PRESERVE_NODES) and _refresh_ledger() re-reads
# RunState at each screen build: changed values flash their ink (gold counts
# up/down like coins hitting a table) so the receipt is visible even before
# the result text says it.

var _ledger_values: Dictionary = {}   # row key -> Label
var _ledger_prev: Dictionary = {}     # row key -> last shown int (for flash/count)

const LEDGER_ROWS := [
	{"key": "hp", "icon": "hud_heart"},
	{"key": "gold", "icon": "hud_gold"},
	{"key": "potions", "icon": "hud_potion"},
	{"key": "deck", "icon": "hud_deck"},
]


func _ensure_stakes_ledger() -> void:
	if has_node("StakesLedger"):
		return
	var box := VBoxContainer.new()
	box.name = "StakesLedger"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -230
	box.offset_right = -40
	box.offset_top = 40
	box.offset_bottom = 40 + LEDGER_ROWS.size() * 34
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	for row in LEDGER_ROWS:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_END
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(h)
		var val := Label.new()
		val.add_theme_font_size_override("font_size", 20)
		val.add_theme_color_override("font_color", GameTheme.IVORY)
		val.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		val.add_theme_constant_override("outline_size", 3)
		val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
		val.add_theme_constant_override("shadow_offset_y", 1)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if GameTheme.font_display:
			val.add_theme_font_override("font", GameTheme.font_display)
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(val)
		var icon := TextureRect.new()
		match String(row.icon):
			"hud_heart": icon.texture = GameTheme.tex_hud_heart
			"hud_gold": icon.texture = GameTheme.tex_hud_gold
			"hud_potion": icon.texture = GameTheme.tex_hud_potion
			"hud_deck": icon.texture = GameTheme.tex_hud_deck
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(icon)
		_ledger_values[row.key] = val
	_refresh_ledger(false)


func _ledger_current() -> Dictionary:
	return {
		"hp": RunState.hero_hp,
		"gold": RunState.gold,
		"potions": RunState.potions.size(),
		"deck": RunState.deck.size(),
	}


func _ledger_text(key: String, v: int) -> String:
	match key:
		"hp":
			return "%d/%d" % [v, RunState.hero_max_hp]
		"potions":
			return "%d/%d" % [v, RunState.MAX_POTIONS]
	return str(v)


func _refresh_ledger(animate: bool = true) -> void:
	var ledger = get_node_or_null("StakesLedger")
	if ledger == null:
		return
	# The ledger reads over everything — sub-screens add their own scrims after
	# the preserved nodes, so re-raise it each build.
	ledger.move_to_front()
	var now := _ledger_current()
	for key in _ledger_values:
		var lbl: Label = _ledger_values[key]
		if not is_instance_valid(lbl):
			continue
		var v: int = int(now[key])
		var prev: int = int(_ledger_prev.get(key, v))
		if not animate or prev == v or UserSettings.reduce_motion:
			lbl.text = _ledger_text(key, v)
		elif key == "gold":
			# Coins count onto the table one by one.
			var tw := create_tween()
			tw.tween_method(func(x): lbl.text = _ledger_text(key, int(round(x))),
				float(prev), float(v), clampf(absf(v - prev) * 0.012, 0.25, 0.9))
		else:
			lbl.text = _ledger_text(key, v)
		if animate and prev != v and not UserSettings.reduce_motion:
			var flash: Color = GameTheme.GILT_BRIGHT
			if key == "hp":
				flash = Color(0.55, 0.88, 0.55) if v > prev else Color(0.88, 0.40, 0.32)
			lbl.add_theme_color_override("font_color", flash)
			var back := create_tween()
			back.tween_interval(0.55)
			back.tween_callback(func():
				if is_instance_valid(lbl):
					lbl.add_theme_color_override("font_color", GameTheme.IVORY))
		_ledger_prev[key] = v


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

	# Single-verb rooms: an event with an `auto_effect` IS its picker (the Wet
	# Cards). Apply the modal effect directly — it owns the screen and its own
	# leave path — instead of building a choice screen whose only real option
	# is "open the picker". Art is ensured above so the result screen still
	# shows the plate.
	if _current_node.has("auto_effect"):
		PlayLog.log_event("event_choice", {"event": _event_id, "choice": "auto",
			"effects": [String(_current_node.auto_effect.get("type", ""))]})
		_apply_effect(_current_node.auto_effect)
		return

	# Left-column layout: title → body → choices stack down a fixed-width
	# column anchored to the left edge. The horizontal scrim behind
	# (EventOverlayLeft) pools the column in a darker region; the right
	# ~half of the art stays fully visible. Text and art share the screen
	# instead of competing for the same pixels.
	const COLUMN_LEFT := 80
	const COLUMN_WIDTH := 720

	var title := _make_event_title(_sub_campaign_tokens(_event_data.name))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = COLUMN_LEFT
	title.offset_top = 64
	title.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	title.offset_bottom = 132
	add_child(title)
	if not UserSettings.reduce_motion:
		title.modulate.a = 0.0
		create_tween().tween_property(title, "modulate:a", 1.0, 0.22)

	# Title setting — a gilt hairline with a diamond finial: the cartouche
	# rule that stakes the page before the ink starts.
	var rule := ColorRect.new()
	rule.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.55)
	rule.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rule.offset_left = COLUMN_LEFT + 4
	rule.offset_right = COLUMN_LEFT + 252
	rule.offset_top = 128
	rule.offset_bottom = 130
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	var finial := ColorRect.new()
	finial.color = Color(GameTheme.GILT_BRIGHT.r, GameTheme.GILT_BRIGHT.g,
		GameTheme.GILT_BRIGHT.b, 0.9)
	finial.size = Vector2(7, 7)
	finial.position = Vector2(COLUMN_LEFT - 1, 125.0)
	finial.rotation = PI / 4.0
	finial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(finial)

	# Blue options (per-choice "blue" gate) only exist while the event
	# recognizes something about the player — filter before building the stack.
	var visible_choices: Array = []
	for choice in _current_node.choices:
		if choice.has("blue") and not _event_gate_passes_dict(choice.blue):
			continue
		visible_choices.append(choice)

	# THE READING BLOCK (restructured 2026-07-04): body text and choices are
	# ONE bottom-anchored column, not a paragraph floating at the top with the
	# ladder pinned at the bottom — the old split made every event read as two
	# separate text walls with a dead gap between them. Now the page has three
	# zones: identity top-left (title), art breathing in the middle, and a
	# single reading zone bottom-left. The column is pinned at the bottom and
	# GROWS UPWARD (entries content-fit themselves a frame after ready), so
	# the choices never move once shown.
	var column := VBoxContainer.new()
	column.name = "ChoicesBox"
	column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	column.offset_left = COLUMN_LEFT
	column.offset_right = COLUMN_LEFT + COLUMN_WIDTH
	column.offset_top = -110
	column.offset_bottom = -110
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Inter-entry gap (20) deliberately wider than the intra-entry line gap so
	# the ladder chunks into countable options instead of a run-on of lines.
	column.add_theme_constant_override("separation", 20)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(column)

	# Body text comes from _current_node — at event start that's _event_data,
	# but a branching `follow_up` choice replaces it with a sub-dict so the
	# same _build_ui() call paints whichever stage we're on. The opening
	# letter is illuminated (gilt raised cap) — this is a writ, after all,
	# and it writes itself in (quick typewriter; reduce_motion shows it whole).
	var desc = _make_event_desc(_illuminate_desc(_sub_campaign_tokens(_current_node.desc)))
	column.add_child(desc)
	if not UserSettings.reduce_motion:
		desc.visible_ratio = 0.0
		var reveal := clampf(desc.get_total_character_count() * 0.0032, 0.25, 0.85)
		create_tween().tween_property(desc, "visible_ratio", 1.0, reveal) \
			.set_delay(0.12)

	# A breath between the prose and the first option — the paragraph should
	# sit close enough to read as one document, far enough to end cleanly.
	var breath := Control.new()
	breath.custom_minimum_size = Vector2(0, 8)
	breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(breath)

	# Numerals count only the plain entries — blue options wear the diamond,
	# so giving them a numeral slot left gaps in the count (I, ◆, III, IV).
	var next_numeral := 1
	for choice in visible_choices:
		var ordinal := -1
		if not choice.has("blue"):
			ordinal = next_numeral
			next_numeral += 1
		column.add_child(_make_event_choice(choice, 84, ordinal))

	# The ledger margin — one hairline between the numeral column and the
	# entries' text, running the CHOICES' height (the desc above it sits flush
	# on the page, unruled). It's what makes the stack read as a written
	# column instead of floating lines (and the hover slide visibly carries
	# the entry's text away from it). Aligned once content-fit has settled.
	var margin_line := ColorRect.new()
	margin_line.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.26)
	margin_line.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin_line.offset_left = COLUMN_LEFT + 68
	margin_line.offset_right = COLUMN_LEFT + 69
	margin_line.offset_top = -110
	margin_line.offset_bottom = -102
	margin_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin_line)
	_align_margin_line(margin_line, column)

	_add_hover_whisper()

	# Always-available exit, bottom-RIGHT so it never overlaps the ladder —
	# frameless like everything else on the page (the old parchment-box LEAVE
	# was the last rectangle on the screen).
	var skip_btn := _make_walk_on_button()
	skip_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE))
	add_child(skip_btn)

	_refresh_ledger()


## Pin the margin hairline to the CHOICE ENTRIES' real rect (the reading
## column also holds the desc — the rule belongs to the options only). Two
## frames: one for the entries' content-fit growth (each waits a frame to
## measure wrapped text), one for the auto-growing VBox to re-lay out.
func _align_margin_line(line: ColorRect, ladder: VBoxContainer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not (is_instance_valid(line) and is_instance_valid(ladder)):
		return
	var top_y: float = ladder.get_global_rect().position.y
	for c in ladder.get_children():
		if c is Button:
			top_y = (c as Control).get_global_rect().position.y
			break
	line.set_anchors_preset(Control.PRESET_TOP_LEFT)
	line.offset_left = ladder.get_global_rect().position.x + 68
	line.offset_right = ladder.get_global_rect().position.x + 69
	line.offset_top = top_y - 6
	line.offset_bottom = ladder.get_global_rect().end.y + 8


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
		# The plate breathes — a 16s Ken Burns drift (scale only, from center,
		# COVERED keeps every edge bled). Started once; the art node survives
		# result-screen rebuilds via PRESERVE_NODES so the drift never resets.
		if not UserSettings.reduce_motion:
			art.pivot_offset = Vector2(800, 450)  # 1600x900 canvas center
			var kb := create_tween().set_loops()
			kb.tween_property(art, "scale", Vector2(1.035, 1.035), 16.0) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			kb.tween_property(art, "scale", Vector2.ONE, 16.0) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Left-column scrim: deep dark wash on the left, fading to clear across
	# the middle. Pools the text column in a quiet region while the right
	# ~half of the art stays fully visible. Replaces the older top+bottom
	# vertical pair — that one darkened bands the text rarely sat in (the
	# 3-choice stack landed mid-screen, in fully un-darkened art).
	if not has_node("EventOverlayLeft"):
		# Adaptive depth: a flat wash tuned for midnight paintings loses the
		# text on bright daylight art, and a wash tuned for daylight murders
		# the dark pieces. Sample THIS painting's text column and ink to suit.
		var scrim := _make_horizontal_gradient_overlay(_art_scrim_darkness(tex), 0.0)
		scrim.name = "EventOverlayLeft"
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(scrim)
		_move_after_atmosphere(scrim)


## How deep the left text scrim must run for THIS painting. Reads the art's
## text column (left ~55%, where title / body / choices sit): mean luminance
## sets the base need, local contrast (busy art fights letterforms even at
## mid brightness) adds a smaller kick. Dark calm art keeps the classic 0.62;
## bright or busy art deepens toward 0.85. Any read failure = the old flat wash.
func _art_scrim_darkness(tex: Texture2D) -> float:
	const BASE := 0.62
	if tex == null:
		return BASE
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return BASE
	if img.is_compressed():
		if img.decompress() != OK:
			return BASE
	# Tiny working copy — 48×27 keeps the scan effectively free.
	img.resize(48, 27, Image.INTERPOLATE_BILINEAR)
	var w := 26  # left 55% of 48
	var sum := 0.0
	var sum_sq := 0.0
	var n := 0
	for y in 27:
		for x in w:
			var c := img.get_pixel(x, y)
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += lum
			sum_sq += lum * lum
			n += 1
	var mean := sum / float(n)
	var sdev := sqrt(maxf(sum_sq / float(n) - mean * mean, 0.0))
	return clampf(BASE + (mean - 0.18) * 0.9 + sdev * 0.35, 0.55, 0.85)


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
uniform vec3 shadow_ink = vec3(0.035, 0.022, 0.016);
void fragment() {
	float t = smoothstep(0.30, 0.62, UV.x);
	float a = mix(darkness_left, darkness_right, t);
	// Corner weighting: the ladder's bottom-left pools deepest, the title's
	// top-left gets a lighter wash, and the mid-left stays airiest so the
	// painting breathes between the two text zones.
	a += (1.0 - smoothstep(0.0, 0.55, UV.x)) * 0.18 * smoothstep(0.40, 1.0, UV.y);
	a += (1.0 - smoothstep(0.0, 0.50, UV.x)) * 0.08 * (1.0 - smoothstep(0.0, 0.30, UV.y));
	a = clamp(a, 0.0, 0.92);
	// Warm ink shadow, not black glass — the exact warmth is the event's mood.
	COLOR = vec4(shadow_ink, a);
}
"""
	mat.shader = shader
	mat.set_shader_parameter("darkness_left", darkness_left)
	mat.set_shader_parameter("darkness_right", darkness_right)
	var ink := _mood_shadow_ink()
	mat.set_shader_parameter("shadow_ink", Vector3(ink.r, ink.g, ink.b))
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
	rt.add_theme_font_size_override("normal_font_size", 44)
	rt.add_theme_font_size_override("bold_font_size", 44)
	rt.add_theme_font_size_override("italics_font_size", 44)
	# The mood field picks the title's ink (bone/ember/gilt/verdigris);
	# unmooded events keep the arcane purple.
	var title_ink := _mood_title_ink()
	rt.add_theme_color_override("default_color", title_ink)
	rt.add_theme_color_override("font_outline_color",
		Color(title_ink.r, title_ink.g, title_ink.b, 0.25))
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
	rt.add_theme_font_size_override("normal_font_size", 21)
	rt.add_theme_font_size_override("bold_font_size", 21)
	rt.add_theme_font_size_override("italics_font_size", 21)
	# A touch of air between lines — dense paragraphs over art read as a slab.
	rt.add_theme_constant_override("line_separation", 6)
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
	# Container-ready (2026-07-04): the desc now lives INSIDE the reading
	# column above the choices, not floating at a fixed top-left rect — the
	# caller's VBox owns position and width.
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rt


# ── Frameless cinematic choice ───────────────────────────────────────────

func _make_event_choice(choice: Dictionary, height: int, ordinal: int = -1) -> Button:
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
			_resolve_choice.bind(choice), choice.has("blue"), ordinal)


# Verdigris ink for blue options — the color is the tell that the event SEES
# you (your hero, your relics, your history). Matches RelicDB's "event" tier.
const BLUE_INK := Color(0.47, 0.83, 0.75, 1.0)
const BLUE_INK_BRIGHT := Color(0.66, 0.97, 0.88, 1.0)


# The hover whisper — one shared dim line under the choice stack where a
# hovered choice's flavor beat fades in. Moving the third text line here
# (2026-07-04) halved the resting screen's text mass; the writing survives,
# it just waits for the cursor. Rebuilt per screen (not in PRESERVE_NODES).
var _whisper: Label = null


func _add_hover_whisper(bottom: int = -56) -> void:
	var w := Label.new()
	w.name = "HoverWhisper"
	w.text = ""
	w.add_theme_font_size_override("font_size", 18)
	w.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66, 0.92))
	w.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	w.add_theme_constant_override("outline_size", 3)
	w.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	w.add_theme_constant_override("shadow_offset_y", 1)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body:
		w.add_theme_font_override("font", GameTheme.font_body)
	w.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	w.offset_left = 104
	w.offset_right = 700
	w.offset_top = bottom - 44
	w.offset_bottom = bottom
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(w)
	_whisper = w


func _set_whisper(text: String) -> void:
	if _whisper != null and is_instance_valid(_whisper):
		_whisper.text = text


## The frameless exit: dim ivory "WALK ON —", gold when the cursor asks.
## Anchored bottom-right, clear of the ladder at any resolution.
func _make_walk_on_button() -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, transparent)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = -240
	btn.offset_right = -40
	btn.offset_top = -84
	btn.offset_bottom = -40
	var lbl := Label.new()
	lbl.text = "WALK ON  —"
	lbl.add_theme_font_size_override("font_size", 20)
	var rest := Color(GameTheme.IVORY.r, GameTheme.IVORY.g, GameTheme.IVORY.b, 0.66)
	lbl.add_theme_color_override("font_color", rest)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.80))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	btn.mouse_entered.connect(func() -> void:
		lbl.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD))
	btn.mouse_exited.connect(func() -> void:
		lbl.add_theme_color_override("font_color", rest))
	return btn


# ── Outcome ink (contrast pass, 2026-07-04) ───────────────────────────────
# Costs burn ember-red inside the gold outcome line, so "+55 gold, +1 Curse"
# reads as a gain AND a wound at a glance. Segment-level (split on ";" and
# ","): a segment is a cost when it opens with "-"/"Lose"/"Pay", or when it
# HANDS you a Curse-family card ("+1 Curse", "gain a Wound") — but never when
# it removes one (eating a Curse is the payoff). Hand-authored BBCode
# segments pass through untouched.
const COST_INK := "#e06550"

# Inline devices for the outcome lines — one small glyph opens each segment so
# the ladder scans by SHAPE ("which of these costs blood?") before it's read.
# Painted HUD icons where they exist; the skull is the white silhouette kit.
const GLYPH_GOLD := "[img=16]res://assets/icons/map/hud_gold_painted.png[/img] "
const GLYPH_HP := "[img=16]res://assets/icons/map/hud_heart_painted.png[/img] "
const GLYPH_CURSE := "[img=15]res://assets/icons/skull.png[/img] "
const GLYPH_POTION := "[img=16]res://assets/icons/map/hud_potion_painted.png[/img] "
const GLYPH_RELIC := "[img=16]res://assets/icons/map/hud_relic.png[/img] "
const GLYPH_CARD := "[img=16]res://assets/icons/map/hud_deck.png[/img] "
const GLYPH_COMMAND := "[img=16]res://assets/icons/stats/cost_runestone.png[/img] "


func _ink_outcome(text: String) -> String:
	if text.find("[") >= 0:
		return text
	var big_parts: Array = []
	for half in text.split("; "):
		var parts: Array = []
		for seg in String(half).split(", "):
			parts.append(_ink_segment(String(seg)))
		big_parts.append(", ".join(parts))
	return "; ".join(big_parts)


func _segment_glyph(lower: String, curse_family: bool) -> String:
	if curse_family:
		return GLYPH_CURSE
	if lower.find("gold") >= 0:
		return GLYPH_GOLD
	if lower.find("hp") >= 0 or lower.find("heal") >= 0:
		return GLYPH_HP
	if lower.find("potion") >= 0:
		return GLYPH_POTION
	if lower.find("relic") >= 0:
		return GLYPH_RELIC
	if lower.find("command") >= 0:
		return GLYPH_COMMAND
	if lower.find("card") >= 0 or lower.find("upgrade") >= 0 \
			or lower.find("transform") >= 0 or lower.find("creature") >= 0:
		return GLYPH_CARD
	return ""


func _ink_segment(seg: String) -> String:
	var lower := seg.strip_edges().to_lower()
	var curse_family: bool = lower.find("curse") >= 0 or lower.find("wound") >= 0 \
		or lower.find("debt") >= 0 or lower.find("deserter") >= 0
	var sheds_it: bool = lower.find("remove") >= 0 or lower.find("eat") >= 0 \
		or lower.find("bury") >= 0 or lower.find("purge") >= 0
	var is_cost: bool = lower.begins_with("-") or lower.begins_with("lose ") \
		or lower.begins_with("pay ") or (curse_family and not sheds_it)
	var glyph := _segment_glyph(lower, curse_family and not sheds_it)
	if is_cost:
		return glyph + "[color=%s]%s[/color]" % [COST_INK, seg]
	return glyph + seg


## Illuminate the intro: the first letter becomes a gilt raised capital — the
## writ language's drop cap. Skipped when the text opens with BBCode, a digit
## or punctuation (a quote keeps its own drama).
func _illuminate_desc(text: String) -> String:
	if text.is_empty():
		return text
	var c := text.substr(0, 1)
	if not ((c >= "A" and c <= "Z") or (c >= "a" and c <= "z")):
		return text
	# 29px, not 32 — the inline size jump widens the cap's advance, and past
	# ~30px the first word visibly splits ("T he river").
	return "[font_size=29][color=#e8b547]%s[/color][/font_size]%s" % [c, text.substr(1)]


## Campaign text tokens, applied wherever event prose renders:
##   {fallen}  → the most recent name on the Roll of the Fallen
##                ("the nameless" when the ledger is empty)
##   {kingdom} → the current act's faction display name ("the kingdom" on
##                legacy runs with no rival deal)
##   {lord}    → the current act's rival lord ("the lord" likewise)
## One war event serves all five rivals through these; any event can also
## sing the player's actual dead.
func _sub_campaign_tokens(text: String) -> String:
	if text.find("{") < 0:
		return text
	if text.find("{fallen}") >= 0:
		var fname := "the nameless"
		if not RunState.fallen.is_empty():
			fname = String(RunState.fallen.back().get("name", "the nameless"))
		text = text.replace("{fallen}", fname)
	if text.find("{kingdom}") >= 0:
		var kname := "the kingdom"
		var fac: String = RunState.get_act_faction()
		if fac != "":
			kname = String(HeroDB.faction_info(fac).get("name", "the kingdom"))
		text = text.replace("{kingdom}", kname)
	if text.find("{lord}") >= 0:
		var lname := "the lord"
		var rival: String = RunState.get_act_rival()
		if rival != "":
			lname = String(HeroDB.get_hero(rival).get("name", "the lord"))
		text = text.replace("{lord}", lname)
	if text.find("{pawned}") >= 0:
		# The oldest card on the Pawnbroker's shelf — the one her buy-back offers.
		var pname := "something of yours"
		if not RunState.pawned_cards.is_empty():
			var pdata = CardDB.get_card_data(String(RunState.pawned_cards[0]))
			if not pdata.is_empty():
				pname = String(pdata.name)
		text = text.replace("{pawned}", pname)
	if text.find("{veteran}") >= 0:
		text = text.replace("{veteran}", _veteran_display_name())
	return text


## The most-killed soldier still marching, worn name and all ("Pikeman the
## Grim") — the folded card data carries the epithet from 3 kills up.
func _veteran_display_name() -> String:
	var best_i := -1
	var best_k := 0
	for i in range(mini(RunState.deck.size(), RunState.deck_uids.size())):
		var k: int = RunState.get_kills(RunState.deck_uids[i])
		if k > best_k:
			best_k = k
			best_i = i
	if best_i < 0:
		return "your best soldier"
	return String(RunState.get_upgraded_card_data(best_i).get("name", "your best soldier"))


func _make_frameless_choice(headline_text: String, effect_text: String,
		body_text: String, height: int, on_press: Callable,
		is_blue: bool = false, ordinal: int = -1) -> Button:
	headline_text = _sub_campaign_tokens(headline_text)
	effect_text = _sub_campaign_tokens(effect_text)
	body_text = _sub_campaign_tokens(body_text)
	# Returns a transparent Button containing layered visuals — a gilt roman
	# numeral (main choice screens; engine screens without an ordinal keep the
	# gem) on the left, then TWO lines: the verb headline and the mechanical
	# OUTCOME line (gold — what the player actually gets). The flavor beat is
	# NOT stacked as a third line: it plays through the shared hover whisper,
	# so the resting screen stays lean. Choices WITHOUT an outcome line
	# (hidden tells, Continue/Walk-on buttons) keep their body inline — for
	# the carnival's tells that line IS the game. Hover slides the entry a
	# few pixels right (reduce_motion honored) so the focused option answers.
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(560, height)
	btn.focus_mode = Control.FOCUS_NONE
	# SIZE_FILL so the button stretches to the column width (used to be
	# SHRINK_CENTER for the old centered VBox); the marker stays glued to
	# the column's left edge instead of floating with the headline.
	btn.size_flags_horizontal = Control.SIZE_FILL

	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, transparent)

	if on_press.is_valid():
		btn.pressed.connect(on_press)

	# Hover pool — a soft gradient of the entry's own ink that pools under the
	# hovered option and fades out rightward. Light, not a box: the frameless
	# rule holds, but the focused entry visibly OWNS its strip of the screen.
	var pool_ink: Color = BLUE_INK if is_blue else GameTheme.GILT
	var pool_grad := Gradient.new()
	pool_grad.set_color(0, Color(pool_ink.r, pool_ink.g, pool_ink.b, 0.15))
	pool_grad.set_color(1, Color(pool_ink.r, pool_ink.g, pool_ink.b, 0.0))
	var pool_tex := GradientTexture2D.new()
	pool_tex.gradient = pool_grad
	pool_tex.fill_from = Vector2(0.0, 0.5)
	pool_tex.fill_to = Vector2(0.9, 0.5)
	var glow := TextureRect.new()
	glow.texture = pool_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.modulate.a = 0.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(glow)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 24
	hbox.offset_right = -24
	hbox.add_theme_constant_override("separation", 18)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var gem_rest := Color(BLUE_INK.r, BLUE_INK.g, BLUE_INK.b, 0.95) if is_blue \
		else Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.92)
	var gem_hot := Color(BLUE_INK_BRIGHT.r, BLUE_INK_BRIGHT.g, BLUE_INK_BRIGHT.b, 1.0) if is_blue \
		else Color(GameTheme.GILT_BRIGHT.r, GameTheme.GILT_BRIGHT.g, GameTheme.GILT_BRIGHT.b, 1.0)

	# Entry marker: a gilt roman numeral chunks the ladder into countable
	# options at a glance (I. II. III. — writ furniture, not UI chrome). The
	# engine screens (dice/risk/appraisal, ordinal -1) keep the diamond gem.
	# BLUE options always wear the diamond, never a numeral — the shape (not
	# just the verdigris ink) marks "the event sees you", so the tell survives
	# color-blindness and dim monitors.
	var gem: Control
	if ordinal >= 1 and not is_blue:
		var num := Label.new()
		const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]
		num.text = ROMAN[mini(ordinal, ROMAN.size()) - 1] + "."
		num.add_theme_font_size_override("font_size", 25)
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		num.add_theme_constant_override("outline_size", 3)
		num.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
		num.add_theme_constant_override("shadow_offset_y", 1)
		if GameTheme.font_display:
			num.add_theme_font_override("font", GameTheme.font_display)
		num.custom_minimum_size = Vector2(36, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gem = num
	else:
		var tex_gem := TextureRect.new()
		var diamond_tex := GameTheme.tex_icon_diamond
		if diamond_tex:
			tex_gem.texture = diamond_tex
		# Same 36px gutter the numerals reserve — otherwise diamond entries'
		# headlines start 18px left of the numbered ones and the ladder's text
		# edge zigzags.
		tex_gem.custom_minimum_size = Vector2(36, 18)
		tex_gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem = tex_gem
	gem.modulate = gem_rest
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
	headline.add_theme_font_size_override("font_size", 24)
	var head_rest: Color = BLUE_INK if is_blue else GameTheme.IVORY
	var head_hot: Color = BLUE_INK_BRIGHT if is_blue else GameTheme.KEYWORD_GOLD
	headline.add_theme_color_override("font_color", head_rest)
	headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.80))
	headline.add_theme_constant_override("outline_size", 3)
	headline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	headline.add_theme_constant_override("shadow_offset_x", 0)
	headline.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		headline.add_theme_font_override("font", GameTheme.font_display)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(headline)

	# Underline sweep — a hairline that draws itself beneath the hovered verb.
	var underline := ColorRect.new()
	underline.color = Color(gem_hot.r, gem_hot.g, gem_hot.b, 0.55)
	underline.custom_minimum_size = Vector2(0, 2)
	underline.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(underline)

	# Outcome line — the mechanical payload, rendered in gold so it reads as
	# "this is what happens" distinct from the ivory headline. RichTextLabel
	# so a desc can tint gains/costs inline ([color] tags) when a choice
	# wants to; plain text falls back to the gold default color.
	if not effect_text.is_empty():
		var fx := RichTextLabel.new()
		fx.bbcode_enabled = true
		fx.fit_content = true
		fx.scroll_active = false
		fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fx.text = _ink_outcome(effect_text)
		fx.custom_minimum_size = Vector2(500, 0)
		fx.add_theme_font_size_override("normal_font_size", 19)
		fx.add_theme_font_size_override("bold_font_size", 19)
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
	elif not body_text.is_empty():
		# No outcome line to show (hidden tells, Continue buttons): the body
		# stays inline — it's the only content the entry has.
		var body := Label.new()
		body.text = body_text
		body.add_theme_font_size_override("font_size", 18)
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

	# The flavor beat rides the hover: whisper it under the stack while the
	# cursor rests here (only when an outcome line displaced it from the entry).
	# The focused entry also slides a few pixels right — the physical answer
	# that separates "reading the ladder" from "aiming at an option".
	var whisper_text: String = body_text if not effect_text.is_empty() else ""
	var slide := {"tw": null}
	var slide_to := func(left: float, right: float, pool_a: float, line_w: float) -> void:
		if slide.tw != null:
			slide.tw.kill()
		if UserSettings.reduce_motion:
			hbox.offset_left = left
			hbox.offset_right = right
			glow.modulate.a = pool_a
			underline.custom_minimum_size.x = line_w
			return
		slide.tw = btn.create_tween()
		slide.tw.set_parallel(true)
		slide.tw.tween_property(hbox, "offset_left", left, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		slide.tw.tween_property(hbox, "offset_right", right, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		slide.tw.tween_property(glow, "modulate:a", pool_a, 0.15)
		slide.tw.tween_property(underline, "custom_minimum_size:x", line_w, 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	btn.mouse_entered.connect(func() -> void:
		gem.modulate = gem_hot
		headline.add_theme_color_override("font_color", head_hot)
		if whisper_text != "":
			_set_whisper(whisper_text)
		slide_to.call(36.0, -12.0, 1.0, 168.0)
	)
	btn.mouse_exited.connect(func() -> void:
		gem.modulate = gem_rest
		headline.add_theme_color_override("font_color", head_rest)
		if whisper_text != "":
			_set_whisper("")
		slide_to.call(24.0, -24.0, 0.0, 0.0)
	)

	# Content-fit (2026-07-04): a wrapped outcome line used to overflow the
	# fixed-height rect and bleed into the next entry — the inner hbox is
	# ANCHORED (for the hover slide), so the Button never grew with it.
	# Measure the real text height once autowrap has a width (one frame after
	# ready) and grow the button's minimum to fit; the auto-growing ladder
	# VBox then re-lays out around it.
	btn.ready.connect(func() -> void:
		await btn.get_tree().process_frame
		if not (is_instance_valid(btn) and is_instance_valid(vbox)):
			return
		var need: float = vbox.get_combined_minimum_size().y + 22.0
		if need > btn.custom_minimum_size.y:
			btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, need)
	)

	# Deal the ladder in: entries fade in top-to-bottom with a small stagger
	# whenever they land in a choices column (any VBox — the main screen and
	# the engine screens both). Result-screen buttons parented straight to the
	# root appear instantly. Fade only — position stays container-owned, so
	# the entrance can never fight the hover slide.
	btn.ready.connect(func() -> void:
		if UserSettings.reduce_motion or not (btn.get_parent() is VBoxContainer):
			return
		btn.modulate.a = 0.0
		var tw := btn.create_tween()
		tw.tween_interval(0.05 + btn.get_index() * 0.07)
		tw.tween_property(btn, "modulate:a", 1.0, 0.24)
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
	"remove_choice_all_copies",
	"upgrade_choice", "upgrade_choice_multi",
	"stranger_hand_pick", "relic_sacrifice_pick", "sacrifice_pick",
	"transform_choice", "dice_run", "risk_loop", "pawn_appraisal",
	"grant_keyword_pick", "veteran_swap",
]


func _resolve_choice(choice: Dictionary) -> void:
	# PlayLog: record the player's event decision (effect TYPES only, to stay
	# JSON-safe — choice dicts can carry runtime Callables we must not serialize).
	var _pl_eff: Array = []
	for _e in choice.get("effects", []):
		_pl_eff.append(_e.get("type", "") if _e is Dictionary else str(_e))
	PlayLog.log_event("event_choice", {"event": _event_id,
		"choice": choice.get("headline", choice.get("label", "")), "effects": _pl_eff})

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
			_sting("heal")
			return "Healed to full HP!"
		"heal":
			RunState.heal_hero(effect.value)
			_sting("heal")
			return "Healed %d HP." % effect.value
		"damage":
			RunState.damage_hero(effect.value)
			_sting("hit_hero")
			return "Took %d damage." % effect.value
		"gold":
			if effect.value > 0:
				RunState.gain_gold(effect.value)
				_sting("coin")
				return "Gained %d gold." % effect.value
			else:
				# Floor at 0 — a flat gold cost must never push the player into
				# negative gold (which soft-bricks every later price check). Only
				# charge what they actually have, like lose_gold_partial.
				var lost: int = mini(-effect.value, RunState.gold)
				RunState.gold -= lost  # losses bypass ectoplasm
				_sting("coin", -6.0)
				return "Lost %d gold." % lost
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
				_result_cards.append(data)
				_sting("card_play")
				return "Added %s to deck!" % data.name
			return ""
		"add_curse":
			var rolled_curse := CardDB.random_curse_id()
			RunState.add_card(rolled_curse)
			_result_cards.append(CardDB.get_card_data(rolled_curse))
			_sting("spell_cast", -4.0)
			return "A Curse was added to your deck."
		"add_curse_id":
			# Branded curse — the event names WHICH mark it leaves (a deserter
			# leaves a Deserter's Mark, the ledger leaves a War-Debt). Falls
			# back to the random roll if the id ever goes stale.
			var curse_id := String(effect.get("id", ""))
			if not CardDB.is_curse(curse_id):
				curse_id = CardDB.random_curse_id()
			RunState.add_card(curse_id)
			var curse_data = CardDB.get_card_data(curse_id)
			_result_cards.append(curse_data)
			_sting("spell_cast", -4.0)
			return "%s was added to your deck." % curse_data.name
		"random_relic":
			var choices = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
			if choices.size() > 0:
				RunState.add_relic(choices[0])
				var relic = RelicDB.get_relic(choices[0])
				_result_relics.append(choices[0])
				_sting("card_play")
				return "Gained relic: %s" % relic.name
			return "No relics available."
		"specific_relic":
			# Named event relic (tier "event") — the payoff carries the event's
			# story. Falls back to coin if somehow already carried.
			var rid := String(effect.get("id", ""))
			if rid != "" and not RunState.relics.has(rid):
				RunState.add_relic(rid)
				_result_relics.append(rid)
				_sting("card_play")
				return "Gained relic: %s" % RelicDB.get_relic(rid).name
			RunState.gain_gold(30)
			_sting("coin")
			return "Gained 30 gold."
		"upgrade_random":
			var upgradeable: Array = []
			for i in range(RunState.deck.size()):
				if RunState.has_upgrade_path(i, "plus"):
					continue
				if not CardDB.is_upgradeable(RunState.deck[i]):
					continue
				upgradeable.append(i)
			if upgradeable.size() > 0:
				var idx = upgradeable[randi() % upgradeable.size()]
				RunState.upgrade_card(idx, "plus")
				# Show the card the tent sharpened — the folded data carries
				# the " +" name and the bumped numbers.
				_result_cards.append(RunState.get_upgraded_card_data(idx))
				_sting("card_play")
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
		"remove_choice_all_copies":
			# Blue option (the Last Tinker): pick one card, he keeps the lot.
			_start_remove_all_copies_mode(String(effect.get("filter", "")))
			return ""
		"wager_gold":
			# One-shot coin bet. Pay `stake` up front (the gate keeps the
			# small bet affordable); a coin flip then pays `payout` gross on a
			# win, nothing on a loss. Net win = payout - stake; EV is tuned
			# slightly positive so betting is rational but never safe.
			var stake: int = int(effect.get("stake", 40))
			var payout: int = int(effect.get("payout", 100))
			if RunState.gold < stake:
				return "You haven't the coin to cover that bet."
			RunState.gold -= stake
			_result_suspense = true
			if randi() % 2 == 0:
				RunState.gain_gold(payout)
				_sting("coin")
				return "The dice land true — won %d gold!" % payout
			_sting("hit_hero", -6.0)
			return "The dice turn on you. Lost %d gold." % stake
		"wager_relic_or_curse":
			# The face-down red card: a pure coin flip, no stake. Heads is a
			# relic; tails is `curses` curses. EV ~ neutral — the draw is the
			# whole point.
			var n_curse: int = int(effect.get("curses", 2))
			_result_suspense = true
			if randi() % 2 == 0:
				var won = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
				if won.size() > 0:
					RunState.add_relic(won[0])
					_result_relics.append(won[0])
					_sting("card_play")
					return "The card turns up a blessing: %s." % RelicDB.get_relic(won[0]).name
				return "The card turns up blank. Nothing answers."
			for _i in range(n_curse):
				var flip_curse := CardDB.random_curse_id()
				RunState.add_card(flip_curse)
				_result_cards.append(CardDB.get_card_data(flip_curse))
			_sting("spell_cast", -4.0)
			return "The card turns up a wound. %d Curse(s) settle into your deck." % n_curse
		"gain_potion":
			if RunState.add_potion("healing"):
				return "Gained a Healing Potion."
			return "Your potion belt is already full."
		"sell_potion":
			# Blue option (Pawnbroker): she pays over shop odds for a bottle.
			if RunState.potions.is_empty():
				return "Your belt is empty. She slides the glass shut."
			RunState.potions.pop_back()
			var price: int = int(effect.get("value", 65))
			RunState.gain_gold(price)
			return "She buys a potion off your belt for %d gold." % price
		"add_card":
			# Add one random card of the given rarity (default common). Lets an
			# event hand out a non-rare pull without the "always a rare" inflation.
			var rarity := String(effect.get("rarity", "common"))
			var pool = CardDB.cards_of_rarity(rarity)
			if pool.is_empty():
				return ""
			pool.shuffle()
			RunState.add_card(pool[0])
			_result_cards.append(CardDB.get_card_data(pool[0]))
			_sting("card_play")
			return "Added %s to your deck." % CardDB.get_card_data(pool[0]).name
		"add_card_id":
			# Add a SPECIFIC card by id — story payoffs (the Last Garrison hands
			# you Old Bones by name). Falls back to a random rare if the id ever
			# goes stale, so the event never pays nothing.
			var want_id := String(effect.get("id", ""))
			if CardDB.get_card_data(want_id).is_empty():
				return _apply_effect({"type": "add_rare"})
			RunState.add_card(want_id)
			_result_cards.append(CardDB.get_card_data(want_id))
			_sting("card_play")
			return "%s joins your deck." % CardDB.get_card_data(want_id).name
		"pawn_buyback":
			# The shelf behind the glass (campaign memory): the FIRST card the
			# player ever sold through the appraisal counter comes back — at her
			# keeping fee, and forged, because she kept it better than you did.
			# The blue gate (pawned_at_least + gold_at_least) keeps this branch
			# affordable-only, but guard anyway for direct calls.
			if RunState.pawned_cards.is_empty():
				return "The shelf holds nothing of yours."
			var back_price: int = int(effect.get("price", 60))
			if RunState.gold < back_price:
				return "Your coin does not reach the shelf. She does not haggle."
			var back_id := String(RunState.pawned_cards[0])
			RunState.pawned_cards.remove_at(0)
			if CardDB.get_card_data(back_id).is_empty():
				return "The shelf holds nothing of yours."
			RunState.gold -= back_price
			RunState.add_card(back_id)
			var back_idx: int = RunState.deck.size() - 1
			if CardDB.is_upgradeable(back_id):
				RunState.upgrade_card(back_idx, "plus")
			_result_cards.append(RunState.get_upgraded_card_data(back_idx))
			_sting("coin")
			return "%s comes back across the counter wrapped in the same cloth you sold it in — keener than you left it. She kept it better than you did." \
				% CardDB.get_card_data(back_id).name
		"gain_potion_random":
			# Any potion from the live PotionDB pool (gain_potion is always the
			# plain healing draught; this is the interesting-bottle variant).
			if not RunState.can_add_potion():
				return "Your potion belt is already full."
			var pid: String = PotionDB.roll_random_potion()
			RunState.add_potion(pid)
			return "Gained %s." % PotionDB.get_potion(pid).get("name", "a potion")
		"purge_curses":
			# The Scapegoat: remove EVERY Curse in one rite, priced per head in
			# max HP. Count first, then charge, then remove — floor max HP at 1
			# and never empty the deck (both mirror the other removal paths).
			var curse_idx: Array = []
			for ci in range(RunState.deck.size()):
				if CardDB.is_curse(RunState.deck[ci]):
					curse_idx.append(ci)
			if curse_idx.is_empty():
				return "You carry nothing the goat would recognize."
			var purged := 0
			for ci in range(curse_idx.size() - 1, -1, -1):
				if RunState.deck.size() <= 1:
					break
				RunState.remove_card_at(curse_idx[ci])
				purged += 1
			var hp_price: int = purged * int(effect.get("max_hp_per", 2))
			var new_cap: int = maxi(1, RunState.hero_max_hp - hp_price)
			var paid: int = RunState.hero_max_hp - new_cap
			RunState.hero_max_hp = new_cap
			RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)
			return "The goat carries %d Curse(s) over the boundary stone. Lost %d max HP." % [purged, paid]
		"upgrade_choice":
			_start_upgrade_mode(1)
			return ""
		"upgrade_choice_multi":
			_start_upgrade_mode(effect.value)
			return ""
		"gain_max_hp":
			RunState.hero_max_hp += effect.value
			RunState.hero_hp += effect.value
			_sting("heal")
			return "Gained %d max HP." % effect.value
		"lose_max_hp":
			# Floor at 1 so an unlucky chain of events can't kill you outright.
			var new_max: int = maxi(1, RunState.hero_max_hp - effect.value)
			var actually_lost: int = RunState.hero_max_hp - new_max
			RunState.hero_max_hp = new_max
			RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)
			_sting("hit_hero")
			return "Lost %d max HP." % actually_lost
		"lose_gold_partial":
			# Lose min(value, current gold) — never goes negative. Used by tax
			# events where the cap should hit rich players but the broke player
			# pays only what they have. value 99999 = "ALL your gold" (the
			# Reliquary Cart's all-in).
			var to_lose: int = mini(effect.value, RunState.gold)
			RunState.gold -= to_lose
			_sting("coin", -6.0)
			return "Lost %d gold." % to_lose
		"add_boss_relic":
			# Boss-tier (rare) relic pool. Used by Three Doors and Old Forge.
			var choices = RelicDB.roll_relic_reward("boss", RunState.relics, RunState.current_hero_id)
			if choices.size() > 0:
				RunState.add_relic(choices[0])
				var relic = RelicDB.get_relic(choices[0])
				_result_relics.append(choices[0])
				_sting("card_play")
				return "Gained relic: %s" % relic.name
			# Pool exhausted — fall back to a combat-tier relic so the player
			# never gets nothing from a "guaranteed rare" payoff.
			var fallback = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
			if fallback.size() > 0:
				RunState.add_relic(fallback[0])
				var relic = RelicDB.get_relic(fallback[0])
				_result_relics.append(fallback[0])
				_sting("card_play")
				return "Gained relic: %s" % relic.name
			return "No relics available."
		"relic_sacrifice_pick":
			# Old Forge: player CHOOSES which non-starting relic to lay on the
			# anvil; it's traded for a boss-tier relic. Choosing (vs the old
			# random destruction) is the whole point — losing your best relic to
			# a coin flip was the worst feel-bad in the event pool.
			_start_relic_sacrifice_mode()
			return ""
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
						_sting("coin")
					return "Gained %d gold." % amt
				"lose_gold":
					# Build-scaled COST. Charge min(amt, gold) so a
					# broke player pays only what they have, never negative -
					# mirroring lose_gold_partial's floor.
					var to_lose_scaled: int = mini(amt, RunState.gold)
					RunState.gold -= to_lose_scaled
					_sting("coin", -6.0)
					return "Lost %d gold." % to_lose_scaled
				"heal":
					RunState.heal_hero(amt)
					_sting("heal")
					return "Healed %d HP." % amt
				"max_hp":
					RunState.hero_max_hp += amt
					RunState.hero_hp += amt
					_sting("heal")
					return "Gained %d max HP." % amt
				"damage":
					RunState.damage_hero(amt)
					_sting("hit_hero")
					return "Took %d damage." % amt
			return ""
		"gift_creature":
			# General next-combat payoff: start the next fight with a creature in
			# front-left. Combat honors name AND keywords (2026-07-04) — the
			# Patent Ladder really is Armored. The result page stands the gift up
			# as a card so the player meets their new soldier before the fight.
			RunState.next_combat_gift_creature = {
				"name": effect.get("name", "Gift"),
				"atk": int(effect.get("atk", 1)),
				"hp": int(effect.get("hp", 1)),
				"kw": effect.get("kw", []),
			}
			_result_cards.append({
				"id": "event_gift", "name": effect.get("name", "Gift"),
				"type": "creature", "cost": 0,
				"atk": int(effect.get("atk", 1)), "hp": int(effect.get("hp", 1)),
				"keywords": effect.get("kw", []), "rarity": "enemy",
				"desc": "Stands in your front line when the next fight opens.",
				"is_token": true,
			})
			_sting("card_play")
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
		"grant_keyword_pick":
			_start_grant_keyword_mode(effect)
			return ""
		"veteran_swap":
			_start_veteran_swap_mode()
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
			_result_suspense = true
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
		"fallen":
			# Names on the Roll of the Fallen (the Bell of Names pays them out).
			return RunState.fallen.size()
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


# ── Result payoffs as objects ─────────────────────────────────────────────
# Effect handlers stage what they granted here; the result screen then shows
# the actual things — gained cards stand on the page as real Card2Ds, gained
# relics print as writ plates. StS shows you the card; so do we.
var _result_cards: Array = []    # card DATA dicts (folded where relevant)
var _result_relics: Array = []   # relic ids
# Set by gamble effects (roll_table, coin calls): the result page holds blank
# for a breath before the ink lands — the pause IS the dice rolling.
var _result_suspense: bool = false


func _sting(sound: String, volume_db: float = 0.0) -> void:
	AudioBank.play_sfx(sound, 0.06, volume_db)


func _show_result(text: String) -> void:
	# Merge any stashed co-effect receipt (set when a modal picker was launched
	# alongside non-modal effects) ahead of the picker's own result line.
	var full := text.strip_edges()
	if _pending_pre_text != "":
		full = (_pending_pre_text + "\n" + full).strip_edges()
		_pending_pre_text = ""
	if full.is_empty() and _result_cards.is_empty() and _result_relics.is_empty():
		# Never strand the player on a dead screen with nothing to click — if a
		# result resolves to no text, just walk back to the map.
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
		return
	_clear_ui()
	# Result keeps the event art behind it — same scene, same beat. The receipt
	# is written on the same page as the event (left column, drop cap, ivory
	# ink) instead of the old centered slab that broke the writ metaphor.
	_set_event_art_visible(true)

	# Same reading block as the choice screens: receipt text and the Continue
	# action grouped in one bottom-anchored column, gained objects on the right.
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	column.offset_left = 80
	column.offset_right = 800
	column.offset_top = -110
	column.offset_bottom = -110
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.add_theme_constant_override("separation", 22)
	add_child(column)

	var desc := _make_event_desc(_illuminate_desc(_sub_campaign_tokens(full)))
	column.add_child(desc)

	var delay := 0.0
	if _result_suspense and not UserSettings.reduce_motion:
		delay = 0.7
	_result_suspense = false
	if not UserSettings.reduce_motion:
		desc.visible_ratio = 0.0
		var reveal := clampf(desc.get_total_character_count() * 0.0032, 0.25, 0.9)
		create_tween().tween_property(desc, "visible_ratio", 1.0, reveal) \
			.set_delay(0.10 + delay)

	_show_result_objects(delay)

	column.add_child(_make_frameless_choice("Continue", "", "Walk on.", 88,
			func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE)))

	_refresh_ledger()


## Stand the staged payoffs on the art half of the result page: up to 3 gained
## cards as real Card2Ds (dealt in with a small stagger), relic writs beneath.
func _show_result_objects(delay: float = 0.0) -> void:
	var shown: Array = _result_cards.slice(0, mini(3, _result_cards.size()))
	var extra: int = _result_cards.size() - shown.size()
	var n: int = shown.size()
	if n > 0:
		var card_w := 225
		var sep := 26
		var total_w: int = n * card_w + (n - 1) * sep
		var start_x: float = 1160.0 - total_w / 2.0
		for i in range(n):
			var wrapper := Control.new()
			wrapper.custom_minimum_size = Vector2(225, 300)
			wrapper.position = Vector2(start_x + i * (card_w + sep), 170)
			wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var card_node = CARD_SCENE.instantiate()
			card_node.static_display = true
			card_node.card_data = shown[i]
			card_node.live_baked_mode = true
			CardTextureCache.bake(shown[i])
			wrapper.add_child(card_node)
			add_child(wrapper)
			if not UserSettings.reduce_motion:
				wrapper.modulate.a = 0.0
				wrapper.pivot_offset = Vector2(112, 150)
				wrapper.scale = Vector2(0.92, 0.92)
				var tw := create_tween().set_parallel(true)
				var d := delay + 0.16 + i * 0.10
				tw.tween_property(wrapper, "modulate:a", 1.0, 0.28).set_delay(d)
				tw.tween_property(wrapper, "scale", Vector2.ONE, 0.30).set_delay(d) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if extra > 0:
			var more := Label.new()
			more.text = "…and %d more march behind." % extra
			more.add_theme_font_size_override("font_size", 18)
			more.add_theme_color_override("font_color", GameTheme.DESC_DIM)
			more.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
			more.add_theme_constant_override("outline_size", 3)
			more.position = Vector2(start_x, 482)
			more.size = Vector2(total_w, 28)
			more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			more.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(more)
	# Relic writs — name in gold over the rules line, printed on the page below
	# (or in place of) the cards.
	var ry: float = 520.0 if n > 0 else 260.0
	for rid in _result_relics:
		var relic = RelicDB.get_relic(String(rid))
		if relic.is_empty():
			continue
		var v := VBoxContainer.new()
		v.position = Vector2(940, ry)
		v.size = Vector2(460, 90)
		v.add_theme_constant_override("separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := Label.new()
		nm.text = relic.get("name", "Relic")
		nm.add_theme_font_size_override("font_size", 23)
		nm.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD)
		nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		nm.add_theme_constant_override("outline_size", 3)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if GameTheme.font_display:
			nm.add_theme_font_override("font", GameTheme.font_display)
		v.add_child(nm)
		var dl := Label.new()
		dl.text = relic.get("desc", "")
		dl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
		dl.add_theme_color_override("font_color", GameTheme.IVORY)
		dl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		dl.add_theme_constant_override("outline_size", 3)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(460, 0)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if GameTheme.font_body:
			dl.add_theme_font_override("font", GameTheme.font_body)
		v.add_child(dl)
		add_child(v)
		if not UserSettings.reduce_motion:
			v.modulate.a = 0.0
			create_tween().tween_property(v, "modulate:a", 1.0, 0.3) \
				.set_delay(delay + 0.3)
		ry += 96.0
	_result_cards = []
	_result_relics = []


func _make_card_picker_grid(title_text: String, title_color: Color) -> GridContainer:
	# Shared helper for card-picker screens (remove, copy, butcher).
	# Returns the GridContainer so callers can add card wrappers to it.
	# The event's painting stays under the picker (2026-07-04) — a deep scrim
	# keeps the cards readable, but the Sin-Eater's table and the Remount Fair
	# no longer collapse into the same black room the moment a picker opens.
	_clear_ui()
	_set_event_art_visible(true)
	add_child(_make_picker_scrim())

	var title = GameTheme.make_label(title_text, 26, title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 28)
	title.size = Vector2(1000, 44)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("shadow_offset_y", 2)
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
	_refresh_ledger()
	return grid


## A near-opaque wash in the event's mood ink, laid over the art for the
## card-picker screens — atmosphere without sacrificing card readability.
func _make_picker_scrim() -> ColorRect:
	var scrim := ColorRect.new()
	scrim.name = "PickerScrim"
	var ink := _mood_shadow_ink()
	scrim.color = Color(ink.r, ink.g, ink.b, 0.84)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return scrim


func _add_card_to_grid(grid: GridContainer, data: Dictionary, callback: Callable) -> void:
	# Add a Card2D wrapper with click overlay to a picker grid. The hovered
	# tile lifts slightly toward the cursor — the same "this one answers"
	# physicality the choice ladder's slide gives.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(210, 280)
	wrapper.pivot_offset = Vector2(105, 140)
	var card_node = CARD_SCENE.instantiate()
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
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.pressed.connect(callback)
	if not UserSettings.reduce_motion:
		click_btn.mouse_entered.connect(func() -> void:
			wrapper.z_index = 1
			var tw := wrapper.create_tween()
			tw.tween_property(wrapper, "scale", Vector2(1.05, 1.05), 0.10) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
		click_btn.mouse_exited.connect(func() -> void:
			wrapper.z_index = 0
			var tw := wrapper.create_tween()
			tw.tween_property(wrapper, "scale", Vector2.ONE, 0.10) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
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
	# Never empty the deck — every other removal path keeps a floor of 1 card
	# (multi-remove / all-copies stop at deck.size() <= 1; the shop disables the
	# service). A 1-card deck still builds a 1-tile picker, so guard the commit.
	if RunState.deck.size() <= 1:
		_show_result("That is the last thing you carry. You keep it.")
		return
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
	# Deck floor of 1, same as the other removal paths.
	if RunState.deck.size() <= 1:
		_show_result("That is the last thing you carry. You keep it.")
		return
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


# ── Remove ALL copies (the Last Tinker's blue option) ────────────────────
# Picker over unique qualifying card ids; choosing one removes every copy
# at once. "He takes the lot or none."

func _start_remove_all_copies_mode(filter: String) -> void:
	var unique_ids: Array = []
	for i in range(RunState.deck.size()):
		var cid: String = RunState.deck[i]
		if _card_matches_filter(cid, filter) and not unique_ids.has(cid):
			unique_ids.append(cid)
	if unique_ids.is_empty():
		_show_result(_filter_empty_message(filter))
		return
	var grid = _make_card_picker_grid("Choose a card — he keeps every copy of it", GameTheme.KEYWORD_GOLD)
	for cid in unique_ids:
		_add_card_to_grid(grid, CardDB.get_card_data(cid),
			_on_remove_all_copies_pick.bind(String(cid)))


func _on_remove_all_copies_pick(card_id: String) -> void:
	var nm: String = CardDB.get_card_data(card_id).name
	var removed := 0
	for i in range(RunState.deck.size() - 1, -1, -1):
		if RunState.deck.size() <= 1:
			break
		if RunState.deck[i] == card_id:
			RunState.remove_card_at(i)
			removed += 1
	_show_result("He weighs the matched set once and keeps it. Removed %d × %s." % [removed, nm])


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
	_result_cards.append(data)
	_sting("card_play")
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


# ── Keyword lesson picker (the Pensioned Master) ─────────────────────────
# Pick a creature; it PERMANENTLY gains the effect's keyword via the same
# grant_kw mod entry the Standard-Bearer wayside writes — mods compose, so a
# drilled or forged creature can still take the lesson. Creatures already
# carrying the keyword (from any source) don't show up.

var _grant_kw_effect: Dictionary = {}

func _start_grant_keyword_mode(effect: Dictionary) -> void:
	_grant_kw_effect = effect
	var kw := String(effect.get("keyword", ""))
	if kw == "":
		_show_result("The lesson dissolves into shop-talk. Nothing sticks.")
		return
	var eligible: Array = []
	for i in range(RunState.deck.size()):
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		if data.get("type", "") != "creature":
			continue
		if (data.get("keywords", []) as Array).has(kw):
			continue
		eligible.append(i)
	if eligible.is_empty():
		_show_result("He looks your soldiers over twice and shakes his head. Nobody here can take that lesson.")
		return
	var disp := String(KeywordEffects.KEYWORDS.get(kw, {}).get("display", kw.capitalize()))
	var grid = _make_card_picker_grid(
		String(effect.get("prompt", "Who takes the lesson? (gains %s)" % disp)),
		GameTheme.KEYWORD_GOLD)
	for i in eligible:
		_add_card_to_grid(grid, RunState.get_upgraded_card_data(i),
			_on_grant_keyword_pick.bind(i))


func _on_grant_keyword_pick(deck_index: int) -> void:
	var kw := String(_grant_kw_effect.get("keyword", ""))
	var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	RunState.apply_wayside_upgrade(deck_index, {"path": "grant_kw", "keyword": kw})
	var disp := String(KeywordEffects.KEYWORDS.get(kw, {}).get("display", kw.capitalize()))
	# Show the soldier as they leave the lesson — folded data now carries the
	# new keyword chip.
	_result_cards.append(RunState.get_upgraded_card_data(deck_index))
	_sting("card_play")
	_show_result("%s takes the lesson and keeps it: %s, permanently." \
		% [data.get("name", "The soldier"), disp])


# ── The Free Company's one-for-one muster (veteran_swap) ─────────────────
# Picker over unique STARTER card ids; choosing one removes every copy and
# enlists the same count of random uncommons — the deck keeps its size but
# sheds its greenest identity in one stroke. Replacements are dealt from a
# shuffled pool without repeats ("no two alike") while the pool lasts.

func _start_veteran_swap_mode() -> void:
	var unique_ids: Array = []
	for i in range(RunState.deck.size()):
		var cid: String = RunState.deck[i]
		if CardDB.is_curse(cid):
			continue
		if CardDB.get_card_data(cid).get("rarity", "") != "starter":
			continue
		if not unique_ids.has(cid):
			unique_ids.append(cid)
	if unique_ids.is_empty():
		_show_result("He chalks your column again and comes up empty. \"No levies left. You HAVE been busy.\"")
		return
	var grid = _make_card_picker_grid(
		"Muster out which levy? He takes EVERY copy and matches the count.",
		GameTheme.KEYWORD_GOLD)
	for cid in unique_ids:
		_add_card_to_grid(grid, CardDB.get_card_data(cid),
			_on_veteran_swap_pick.bind(String(cid)))


func _on_veteran_swap_pick(card_id: String) -> void:
	var nm: String = CardDB.get_card_data(card_id).name
	var removed := 0
	for i in range(RunState.deck.size() - 1, -1, -1):
		if RunState.deck.size() <= 1:
			break
		if RunState.deck[i] == card_id:
			RunState.remove_card_at(i)
			removed += 1
	if removed == 0:
		_show_result("That is the last thing you carry. The recruiter waves it off.")
		return
	var pool: Array = CardDB.cards_of_rarity("uncommon")
	pool.shuffle()
	var names: Array = []
	for i in range(mini(removed, pool.size())):
		RunState.add_card(pool[i])
		names.append(CardDB.get_card_data(pool[i]).name)
		_result_cards.append(CardDB.get_card_data(pool[i]))
	_sting("card_play")
	_show_result("%d × %s muster out. In their place march: %s." \
		% [removed, nm, ", ".join(names)])


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
		if not RunState.has_upgrade_path(i, "plus"):
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
		if RunState.has_upgrade_path(i, "plus"):
			continue
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_upgrade_choice_pick.bind(i))


func _on_upgrade_choice_pick(deck_index: int) -> void:
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	RunState.upgrade_card(deck_index, "plus")
	_result_cards.append(RunState.get_upgraded_card_data(deck_index))
	_sting("card_play")
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
	_set_event_art_visible(true)
	add_child(_make_picker_scrim())

	var title = GameTheme.make_label(
		"Three cards lie face-up on the stone. Each is owed.",
		22, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 60)
	title.size = Vector2(1000, 40)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
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
		card_node.live_baked_mode = true
		CardTextureCache.bake(data)
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
	_refresh_ledger()


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
			var owed := CardDB.random_curse_id()
			RunState.add_card(owed)
			_result_cards.append(CardDB.get_card_data(owed))
			msg = "A Curse settles into your deck. "
	RunState.add_card(card_id)
	_result_cards.append(data)
	_sting("card_play")
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

	# Same reading block as every other screen (restyled 2026-07-04 after the
	# defect hunt: the old scrim+scroll version left one entry floating top-left
	# and the decline stranded bottom-center over near-black art). Frameless
	# writ entries — relic name as the verb line, its rules text as the gold
	# outcome (what you're giving up IS the stake) — and "Keep them all" closes
	# the same column. The list scrolls only when the bag is truly heavy.
	var choices_vbox := _build_event_screen(
		"The anvil is patient",
		"Lay one on the anvil. He makes heavy things from light ones — and the trade is final.",
		mini(non_starting.size(), 5) + 1)

	# 96px per entry — the content-fit pass grows a name+rules entry to ~85px,
	# so a tighter estimate leaves the viewport a few pixels short: the last
	# line's descenders clip and a 1-entry-tall scrollbar appears mid-art.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(non_starting.size() * 96, 440))
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_vbox.add_child(scroll)

	var lst := VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.add_theme_constant_override("separation", 10)
	scroll.add_child(lst)

	for rid in non_starting:
		var relic = RelicDB.get_relic(rid)
		lst.add_child(_make_frameless_choice(
			String(relic.get("name", "Relic")),
			String(relic.get("desc", "")),
			"It goes on the anvil.", 66,
			_on_relic_sacrifice_pick.bind(String(rid))))

	# The player may inspect their relics and decline — backing out leaves the
	# whole event (same as the Stranger's Hand picker).
	choices_vbox.add_child(_make_frameless_choice(
		"Keep them all", "",
		"The forge has no fire. Your hands stop hurting anyway.",
		72, _on_stranger_hand_leave))


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
	_result_relics.append(choices[0])
	_sting("card_play")
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
	# Deck floor of 1 — sacrificing your only card would leave an empty deck.
	if RunState.deck.size() <= 1:
		_show_result("It is all you have left to lay down. The altar lets you keep it.")
		return
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
			_result_relics.append(choices[0])
			_sting("card_play")
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
	_result_cards.append(CardDB.get_card_data(new_id))
	_sting("card_play")
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
	_dice_prev_pot = -1
	var stake: int = int(effect.get("stake", 0))
	if stake > 0:
		if RunState.gold < stake:
			_show_result(_dice_text("broke_text", "You haven't the coin to sit down."))
			return
		RunState.gold -= stake
	_build_dice_screen(_dice_text("open_text",
		"The space in the circle is yours. The pot sits at {pot} gold."))


# Shared scaffold for the interactive push-your-luck / appraisal event screens
# (dice run, risk loop, appraisal). Clears the page, shows the art, pins the
# standard top-left title + description, and returns an empty bottom-left VBox
# sized for `n_choices` frameless 84px choice cards. The choices column defaults
# to the 80–700 gutter; appraisal widens its left inset to clear the card it
# stands beside. The interactions stay bespoke — callers fill the returned VBox
# with their own choices.
func _build_event_screen(title_text: String, beat: String, _n_choices: int,
		choices_left: int = 80, choices_right: int = 700) -> VBoxContainer:
	_clear_ui()
	_set_event_art_visible(true)

	var title := _make_event_title(_sub_campaign_tokens(title_text))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 80
	title.offset_top = 72
	title.offset_right = 700
	title.offset_bottom = 132
	add_child(title)

	# One reading block, same as the main screen: the beat text rides INSIDE
	# the bottom-pinned column, directly above the actions. The column grows
	# UPWARD and the actions are its last children, so "Cast the bones" never
	# moves between presses no matter how long the beat runs.
	var choices_vbox := VBoxContainer.new()
	choices_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	choices_vbox.offset_left = choices_left
	choices_vbox.offset_right = choices_right
	choices_vbox.offset_top = -110
	choices_vbox.offset_bottom = -110
	choices_vbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choices_vbox.add_theme_constant_override("separation", 12)
	add_child(choices_vbox)

	var desc = _make_event_desc(beat)
	choices_vbox.add_child(desc)
	var breath := Control.new()
	breath.custom_minimum_size = Vector2(0, 10)
	breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices_vbox.add_child(breath)

	_add_hover_whisper()
	_refresh_ledger()
	return choices_vbox


# The pot's last on-screen value, so a rebuilt dice screen knows whether to
# pulse (the pot just grew) or sit still (first deal of the screen).
var _dice_prev_pot: int = -1


func _build_dice_screen(beat: String) -> void:
	var choices_vbox := _build_event_screen(
		"The pot: [color=#e8b547]%d gold[/color]" % _dice_pot, beat, 2)

	_add_pot_display(_dice_pot > _dice_prev_pot and _dice_prev_pot >= 0)
	_dice_prev_pot = _dice_pot

	choices_vbox.add_child(_make_frameless_choice(
		_dice_text("roll_label", "Cast the bones"),
		_dice_text("roll_sub", "2 in 3 the pot grows. Skulls lose it all."),
		_dice_text("roll_body", "The knuckles rattle like teeth in a cup."),
		84, _on_dice_roll))
	choices_vbox.add_child(_make_frameless_choice(
		_dice_text("bank_label", "Bank the pot"),
		_dice_text("bank_sub", "Take {pot} gold and leave the circle."),
		_dice_text("bank_body", "The dead nod. Walking away is also a move."),
		84, _on_dice_bank))


## The pot as a physical object on the art half of the page: a heap of coin
## icons (the heap grows with the pot) under a big gilt figure. `pulse` scales
## it up-and-settle when the pot just grew. The coin variant ("prop": "coin")
## stands one big coin spinning in place of the heap.
func _add_pot_display(pulse: bool) -> void:
	var root := Control.new()
	root.name = "PotDisplay"
	root.position = Vector2(1020, 300)
	root.size = Vector2(360, 220)
	root.pivot_offset = Vector2(180, 130)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var is_coin: bool = String(_dice_cfg.get("prop", "bones")) == "coin"
	if is_coin:
		# One patient silver-gold piece, spinning on its edge forever.
		var spin := TextureRect.new()
		spin.texture = GameTheme.tex_hud_gold
		spin.custom_minimum_size = Vector2(84, 84)
		spin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spin.position = Vector2(138, 30)
		spin.pivot_offset = Vector2(42, 42)
		spin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(spin)
		if not UserSettings.reduce_motion:
			var tw := spin.create_tween().set_loops()
			tw.tween_property(spin, "scale:x", 0.08, 0.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_property(spin, "scale:x", 1.0, 0.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		# The heap: a compact pyramid pile just above the figure — coins are
		# ADDED row by row as the pot grows, overlapping like a real stack
		# (the old index-hash scatter read as random dots floating on the art).
		var n_coins: int = clampi(3 + _dice_pot / 40, 3, 9)
		const PILE_ROWS := [4, 3, 2]
		var placed := 0
		for row in range(PILE_ROWS.size()):
			var count: int = PILE_ROWS[row]
			for i in range(count):
				if placed >= n_coins:
					break
				var c := TextureRect.new()
				c.texture = GameTheme.tex_hud_gold
				c.custom_minimum_size = Vector2(32, 32)
				c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				# Row r sits 18px higher, its coins centered and half-lapped.
				var cx: float = 180.0 - (count - 1) * 13.0 + i * 26.0 - 16.0
				var cy: float = 88.0 - row * 18.0
				c.position = Vector2(cx + fmod(float(placed) * 7.3, 5.0) - 2.5, cy)
				c.rotation = fmod(float(placed) * 1.1, 0.5) - 0.25
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
				root.add_child(c)
				placed += 1

	var figure := Label.new()
	figure.text = "%d" % _dice_pot
	figure.add_theme_font_size_override("font_size", 44)
	figure.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD)
	figure.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	figure.add_theme_constant_override("outline_size", 5)
	figure.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	figure.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		figure.add_theme_font_override("font", GameTheme.font_display)
	figure.position = Vector2(0, 128)
	figure.size = Vector2(360, 56)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(figure)

	if pulse and not UserSettings.reduce_motion:
		root.scale = Vector2(1.14, 1.14)
		root.create_tween().tween_property(root, "scale", Vector2.ONE, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The cast itself: a few props tumble across the pot area and fade — ivory
## knucklebone chips for the pit, coins for the spinner. Pure tween theater;
## fires on the press, before the result is known, because that IS the throw.
func _toss_props() -> void:
	if UserSettings.reduce_motion:
		return
	var is_coin: bool = String(_dice_cfg.get("prop", "bones")) == "coin"
	for i in range(3):
		var prop: Control
		if is_coin:
			var c := TextureRect.new()
			c.texture = GameTheme.tex_hud_gold
			c.custom_minimum_size = Vector2(26, 26)
			c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			prop = c
		else:
			var p := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.88, 0.85, 0.76)
			sb.border_color = Color(0.25, 0.20, 0.14)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(4)
			p.add_theme_stylebox_override("panel", sb)
			p.custom_minimum_size = Vector2(16, 16)
			prop = p
		prop.position = Vector2(1080 + i * 30, 250)
		prop.pivot_offset = Vector2(8, 8)
		prop.rotation = randf_range(-0.5, 0.5)
		prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(prop)
		var dest := prop.position + Vector2(randf_range(-70, 70), randf_range(90, 150))
		var tw := prop.create_tween().set_parallel(true)
		tw.tween_property(prop, "position", dest, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(prop, "rotation", prop.rotation + randf_range(-3.0, 3.0), 0.45)
		tw.tween_property(prop, "modulate:a", 0.0, 0.30).set_delay(0.30)
		tw.chain().tween_callback(prop.queue_free)


## Losing everything should feel like it: a short table-shake, a red wash over
## the page, and the hit sting. Called AFTER the result screen builds so the
## wash lies over the bust text, not under a rebuild.
func _bust_feedback() -> void:
	_sting("hit_hero")
	if UserSettings.reduce_motion:
		return
	var wash := ColorRect.new()
	wash.color = Color(0.55, 0.10, 0.06, 0.24)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	var wt := wash.create_tween()
	wt.tween_property(wash, "color:a", 0.0, 0.55).set_delay(0.05)
	wt.tween_callback(wash.queue_free)
	var shake := create_tween()
	for off in [Vector2(9, 0), Vector2(-7, 2), Vector2(5, -2), Vector2.ZERO]:
		shake.tween_property(self, "position", off, 0.05)


func _on_dice_roll() -> void:
	_sting("card_play", -4.0)
	_toss_props()
	if randf() < float(_dice_cfg.get("bust_pct", 1.0 / 3.0)):
		_dice_pot = 0
		_dice_prev_pot = -1
		_show_result(_dice_text("bust_text",
			"Skulls. The pot drains back into the pit, coin by coin, and the circle closes over it. The dead do not gloat. Much."))
		_bust_feedback()
		return
	var gain: int = 0
	if String(_dice_cfg.get("mode", "add")) == "double":
		gain = _dice_pot
		_dice_pot *= 2
	else:
		gain = randi_range(int(_dice_cfg.get("gain_min", 18)),
			int(_dice_cfg.get("gain_max", 34)))
		_dice_pot += gain
	_sting("coin")
	_build_dice_screen(_dice_text("grow_text",
		"The bones land clean — {gain} more into the pot. The oldest legionary clicks his jaw, which you have learned is applause.", gain))


func _on_dice_bank() -> void:
	RunState.gain_gold(_dice_pot)
	_sting("coin")
	_dice_prev_pot = -1
	var line := _dice_text("bank_text",
		"You bank {pot} gold and stand. A space stays open in the circle behind you. It is always open. That is the other rule.")
	# Big-pot payoff: banking past the threshold carries the table's own
	# relic away with the gold (event relics — granted by name, never rolled).
	var rid := String(_dice_cfg.get("bank_relic", ""))
	if rid != "" and _dice_pot >= int(_dice_cfg.get("bank_relic_at", 0)) \
			and not RunState.relics.has(rid):
		RunState.add_relic(rid)
		_result_relics.append(rid)
		line += "\n\n" + _dice_text("bank_relic_text",
			"Gained relic: %s." % RelicDB.get_relic(rid).name)
	_show_result(line)


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
	beat = _sub_campaign_tokens(beat)
	var steps: Array = _risk_cfg.get("steps", [])
	var can_act: bool = _risk_step < steps.size()
	if can_act:
		# Non-lethal guard: never offer a press the player can't survive.
		var cost := _effects_hp_cost(steps[_risk_step].get("effects", []))
		if cost > 0 and RunState.hero_hp <= cost:
			can_act = false
			beat += "\n\nYou haven't the blood for another."

	var n_choices: int = 2 if can_act else 1
	var choices_vbox := _build_event_screen(_event_data.name, beat, n_choices)

	if can_act:
		var step: Dictionary = steps[_risk_step]
		choices_vbox.add_child(_make_frameless_choice(
			String(_risk_cfg.get("action", "Press on")),
			String(step.get("sub", "")),
			String(_risk_cfg.get("action_body", "")), 84, _on_risk_action))
	choices_vbox.add_child(_make_frameless_choice(
		String(_risk_cfg.get("leave", "Step away")), "",
		String(_risk_cfg.get("leave_sub", "Keep what you have.")), 84,
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
		_bust_feedback()


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
	var data = RunState.get_upgraded_card_data(_appr_index)
	var price := _appraisal_price(_appr_index)

	var can_another: bool = _appr_shown < 3 and RunState.deck.size() > 1
	var n_choices: int = 3 if can_another else 2
	# Choices sit right of the appraised card (96–321), so widen the left inset.
	var choices_vbox := _build_event_screen(
		"She holds up [color=#e8b547]%s[/color]" % String(data.get("name", "a card")),
		"She turns it over twice behind the smoked glass, taps it once, and names a figure. She does not repeat herself.",
		n_choices, 360, 980)

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
	card_node.live_baked_mode = true
	CardTextureCache.bake(data)
	wrapper.add_child(card_node)
	add_child(wrapper)

	choices_vbox.add_child(_make_frameless_choice("Sell it",
		"Trade %s for %d gold." % [String(data.get("name", "the card")), price],
		"Her hand is already open under the slot.", 84, _on_appraisal_sell))
	if can_another:
		choices_vbox.add_child(_make_frameless_choice("Show her another",
			"She pulls a different card — but her interest cools.",
			"\"As you like. The figure was for THAT one.\"", 84,
			_on_appraisal_another))
	choices_vbox.add_child(_make_frameless_choice("Keep your things", "",
		"She slides the card back without a word.", 84,
		_on_stranger_hand_leave))


func _on_appraisal_sell() -> void:
	# Deck floor of 1 — she won't leave you with nothing to your name.
	if RunState.deck.size() <= 1:
		_show_result("She turns it over once more and slides it back. \"Your last? No. Even I have a line.\"")
		return
	var data = RunState.get_upgraded_card_data(_appr_index)
	var price := _appraisal_price(_appr_index)
	# Campaign memory: the shelf keeps what it buys. A later visit (act 2+)
	# offers this card back through the pawn_buyback blue option.
	RunState.pawned_cards.append(RunState.deck[_appr_index])
	RunState.remove_card_at(_appr_index)
	RunState.gain_gold(price)
	_sting("coin")
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

	# ══════════════════ KEPT — distinct mechanic + distinct fiction ══════════════════

	"pawnbrokers_window": {
		"name": "The Pawnbroker's Window",
		"desc": "Behind smoked glass, the pawnbroker fans her wares. She does not sell — she buys, but only what interests her, and her first figure is always her best.",
		"mood": "gilt",
		"choices": [
			{
				"label": "Slide your pack through the slot\n\nShe pulls out what interests HER.\nIt is never what you would have chosen to sell.",
				"desc": "She names prices for your cards — each refusal cools her offer",
				"effects": [
					{"type": "pawn_appraisal"},
				],
			},
			{
				# Campaign memory: the shelf kept what you sold her (recorded by
				# the appraisal counter). Act 2+, and only when the fee is there —
				# a blue option that can't pay would be a lie.
				"blue": {"type": "all", "gates": [
					{"type": "pawned_at_least", "value": 1},
					{"type": "act_at_least", "value": 2},
					{"type": "gold_at_least", "value": 60},
				]},
				"label": "Ask after the shelf behind the glass\n\n{pawned} sits displayed where she can watch it. \"I knew you'd\nbe back. They always come back. The keeping fee is not negotiable.\"",
				"desc": "-60 gold; {pawned} returns to your deck, sharpened",
				"effects": [
					{"type": "pawn_buyback", "price": 60},
				],
			},
			{
				"blue": {"type": "potions_full"},
				"label": "Set your full belt on the sill\n\nShe holds a bottle to the smoked light and almost smiles.\n\"Liquids keep their word.\" She pays over the odds.",
				"desc": "Sell a potion for 65 gold",
				"effects": [
					{"type": "sell_potion", "value": 65},
				],
			},
			{
				"label": "Buy the unclaimed pledge\n\nSomeone left it here against a debt and never came back.\nShe slides it through the slot without a word about them.",
				"desc": "-75 gold, +random relic",
				"effects": [
					{"type": "gold", "value": -75},
					{"type": "random_relic"},
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
		"desc": "The river runs brown and fast under a bridge of black timber. Three men lean on a chain across the far end. The toll is whatever you look like you can pay.",
		"gate": {"type": "at_bridge"},
		"art": "tollkeeper_bridge",
		"mood": "bone",
		"ambience": "river",
		"choices": [
			{
				"label": "Pay the toll\n\nThey count it twice.\nThe chain comes down.",
				"desc": "-45 gold",
				"effects": [
					{"type": "gold", "value": -45},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "stalwart"},
				"label": "Read the water like a soldier\n\nYou served on rivers like this. There's always a ford,\nalways where the cattle cross. You find it in an hour.",
				"desc": "Ford upstream, free — the river owes soldiers",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The ford is exactly where doctrine says it should be. You cross dry to the boot-tops, and on the far bank you pocket a toll coin some less careful traveller dropped running.",
							"effects": [{"type": "gold", "value": 20}]},
						{"weight": 1,
							"text": "The cattle path crosses at a drowned shrine stone. You touch it mid-river for luck, the way the drovers do, and the cold water takes the road-ache out of your legs.",
							"effects": [{"type": "heal", "value": 4}]},
					]},
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
				# The Tollkeeper's trophy shelf, folded in when her own event was
				# retired — the chain post carries what the crossing has cost others.
				"label": "Pay the other toll\n\nNailed to the chain post: a wedding ring, a fox skull, a child's\ndrawing, a long brown braid. The eldest points at your pack. Once.",
				"desc": "+1 Curse, -1 random card",
				"effects": [
					{"type": "add_curse"},
					{"type": "remove_cards", "value": 1},
				],
			},
		],
	},

	"gravesong_choir": {
		"name": "The Gravesong Choir",
		"desc": "Four hooded singers ring an open grave, humming a tune you almost know — then you do: the verse carries a name. {fallen}. The fifth place in the circle stands empty.",
		"mood": "bone",
		"ambience": "choir",
		"choices": [
			{
				"label": "Take the fifth place and sing\n\nVerse by verse, the soil gives up its grave-gifts.\nVerse by verse, the song learns your voice.",
				"desc": "Each verse earns more gold, then a relic; a miss adds a Curse",
				"effects": [
					{"type": "risk_loop", "mode": "bust",
						"open_text": "You step into the circle. The hum threads itself through your teeth without asking. The grave at the center is empty, and listening.",
						"action": "Sing the next verse",
						"action_body": "The harmony opens a place for you in it.",
						"leave": "Bow out of the circle",
						"leave_sub": "Keep what the soil gave up.",
						"leave_text": "You step back. The choir closes the gap without looking, and the song goes on without your name in it.",
						"leave_text_early": "You do not sing. The fifth place stays open behind you for a long way down the road.",
						"steps": [
							{"chance": 1.0, "sub": "Gain 25 gold — the first verse is welcome.",
								"effects": [{"type": "gold", "value": 25}],
								"text": "The soil stirs. A coin purse surfaces beside your boot like something coming up for air."},
							{"chance": 0.7, "sub": "Gain 35 gold — 3 in 10 the song turns.",
								"effects": [{"type": "gold", "value": 35}],
								"text": "A ring. A chain. A saint's little finger in silver. The choir sings louder, and the grave is not so empty now."},
							{"chance": 0.5, "sub": "The choir's own relic surfaces — even odds the song turns.",
								"effects": [{"type": "specific_relic", "id": "verse_of_you"}],
								"text": "Something works its way up out of the dark, wrapped in a winding-sheet the size of a kerchief: a verse, written in a hand you know, because it is yours."},
						],
						"bust": {"effects": [{"type": "add_curse"}],
							"text": "The song turns on the high note. It walks down your throat, takes a verse of you with it, and lays it in the grave. The choir bows. To you, or to it."},
						"done_text": "The hum fades. The grave is full now, though you never saw anything go in. One singer squeezes your arm — kindly, you decide."},
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

	# ── Recurring NPC: the Sin-Eater pair ──

	"sin_eater": {
		"name": "The Sin-Eater",
		"desc": "A man sits at a long table that should not be here, bread and a knife before him. \"Lay your worst card here,\" he says, not looking up. \"I'll eat it. The price is meat.\"",
		"gate": {"type": "has_curse"},
		"mood": "verdigris",
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
				"desc": "+1 gold",
				"effects": [
					{"type": "gold", "value": 1},
				],
			},
		],
	},

	"fattened_sin_eater": {
		"name": "The Fattened Sin-Eater",
		"desc": "The man from the long table, enormous now, a feast where the bread was. He grins. \"You fed me well. Sit — I've saved you a seat.\"",
		"mood": "verdigris",
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
				"label": "Trade him another Curse\n\nHe takes it gently, lays it on the side of his plate,\nand tears you the heel of the loaf in payment.",
				"desc": "Gain the Sin-Eater's Crust (relic), eat a chosen Curse",
				"effects": [
					{"type": "specific_relic", "id": "sin_eaters_crust"},
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

	# ── Hidden-info: the tells are the game ──

	"rotting_carnival": {
		"name": "The Rotting Carnival",
		"desc": "Three tents, a barker asleep or dead at his post. A sign: PICK ONE. WE ARE NOT RESPONSIBLE FOR WHAT THE TENTS REMEMBER. Listen at the flaps.",
		"mood": "verdigris",
		"ambience": "carnival",
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

	# ── Choose-from-curated-pool (fixed slot costs: HP / gold / Curse) ──

	"strangers_hand": {
		"name": "The Wet Cards",
		"desc": "A stranger deals wet cards face-up onto a flat stone, and looks up only once. \"Each of these is owed to someone. Pay it off — and take what they leave behind.\"",
		"mood": "verdigris",
		"auto_effect": {"type": "stranger_hand_pick"},
		"choices": [],
	},

	# ── Pure gamble (absurd register) ──

	"coin_on_edge": {
		"name": "The Coin That Won't Land",
		"desc": "A silver coin spins in a groove it has worn deep into the road. It does not wobble. It does not slow. A small sign reads: CALL IT.",
		"mood": "gilt",
		"choices": [
			{
				"label": "Put your stake down and call it\n\nDouble or nothing, as many times as your nerve holds.\nThe coin has all day. The coin has all century.",
				"desc": "Stake 25 gold — even odds each call: double the pot, or lose it",
				"effects": [
					{"type": "dice_run", "stake": 25, "start": 40,
						"mode": "double", "bust_pct": 0.5, "prop": "coin",
						"bank_relic": "coin_landed", "bank_relic_at": 160,
						"bank_relic_text": "As you turn to go, the spinning stops. The coin lies flat in your open palm — heads, warm as a struck match — and the groove in the road is empty. Gained relic: The Coin, Landed.",
						"broke_text": "You haven't 25 gold to stake. The coin spins on, unbothered. It has been refused by poorer.",
						"open_text": "You lay your stake in the groove beside the spinning silver. The pot stands at {pot} gold. The coin picks up speed, which should not be possible, and is.",
						"roll_label": "Call it again",
						"roll_sub": "Even odds: the pot doubles — or the coin lands and takes it all.",
						"roll_body": "The coin is enjoying this. You can tell.",
						"bank_label": "Take the pot",
						"bank_sub": "Take {pot} gold and walk.",
						"bank_body": "Some bets are best left spinning.",
						"grow_text": "It blurs, leans, nearly topples — and rights itself, still spinning. The pot stands at {pot} gold. Somewhere behind the sign, something exhales.",
						"bust_text": "The coin falls flat at last. Tails. Stake and pot slide into the worn groove and are gone. The coin stands back up on its edge and resumes spinning.",
						"bank_text": "You bank {pot} gold and step back. The coin spins on, patient. The sign, you notice now, has your handwriting on it."},
				],
			},
			{
				"blue": {"type": "has_nonstarting_relic"},
				"label": "Show the coin what you've already won\n\nYou spread your relics in the dust. The coin slows —\nactually slows. \"A winner,\" the sign rewrites itself. \"No stake.\"",
				"desc": "Free flip: 90 gold on heads, nothing on tails",
				"effects": [
					{"type": "wager_gold", "stake": 0, "payout": 90},
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

	# ── Push-your-luck pot game ──

	"the_bone_pit": {
		"name": "The Bone Pit",
		"desc": "Four dead legionaries cast knucklebones cut from their own hands, still playing for wages the empire never paid. A space opens in the circle.",
		"mood": "bone",
		"choices": [
			{
				"label": "Take the open seat\n\nThe bones are warm.\nThey should not be warm.",
				"desc": "Pot opens at 25 gold — bank any time; skulls take all",
				"effects": [
					{"type": "dice_run", "start": 25,
						"bank_relic": "warm_knucklebone", "bank_relic_at": 75,
						"bank_relic_text": "The eldest legionary stops you at the edge of the circle and presses one of his own knucklebones into your palm. It is warm. It stays warm. Gained relic: Warm Knucklebone."},
				],
			},
			{
				"blue": {"type": "seen_all", "events": ["coin_on_edge"]},
				"label": "Tell them about the coin\n\nFour dead faces turn at once. \"The spinner,\" one clicks.\n\"It owes this table a pot. Sit — your stake is already in.\"",
				"desc": "Pot opens at 50 gold — the dead respect a gambler",
				"effects": [
					{"type": "dice_run", "start": 50,
						"bank_relic": "warm_knucklebone", "bank_relic_at": 75,
						"bank_relic_text": "The eldest legionary stops you at the edge of the circle and presses one of his own knucklebones into your palm. It is warm. It stays warm. Gained relic: Warm Knucklebone."},
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

	# ── War events (gate: at_war; speak through {kingdom}/{lord}) ──

	"the_siege_kitchen": {
		"name": "The Siege Kitchen",
		"desc": "{lord}'s army retreated faster than its field kitchen could pack; the cooks shrugged and kept cooking. In the queue: deserters, farmers, two of your scouts, one bear. Nobody fights in sight of the pot.",
		"gate": {"type": "at_war"},
		"art": "butcher",
		"mood": "ember",
		"ambience": "fire_crackle",
		"choices": [
			{
				"label": "Join the queue\n\nThe stew has been going since the siege of something-or-other\nand has only improved. The bear waits its turn. So do you.",
				"desc": "Heal 9 HP",
				"effects": [
					{"type": "heal", "value": 9},
				],
			},
			{
				"label": "Hire the head cook\n\n\"I feed whoever holds the pot,\" she says, and hands you\nthe pot. It is heavier than a shield and has opinions.",
				"desc": "The Camp Cook (1/5) joins your next fight",
				"effects": [
					{"type": "gift_creature", "name": "Camp Cook", "atk": 1, "hp": 5, "kw": [],
						"text": "The Camp Cook marches with you, ladle shouldered like a poleaxe."},
				],
			},
			{
				"label": "Requisition the salt and the wine\n\nThe cooks let you take it. They also, in full view\nof the queue, write your name in the grease-book.",
				"desc": "+55 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 55},
					{"type": "add_curse"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "kindler"},
				"label": "Tend their fires properly\n\nYou bank the coals the way your trade banks them. The head\ncook watches, nods once, and teaches you the thing with the lid.",
				"desc": "Upgrade a chosen card, free",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ══════════════════ NEW — 2026-07-03 pool remake ══════════════════
	# Design bar: one concept per event, and the payoff should touch the BUILD
	# or the FIGHTING (keywords, whole-deck swaps, specific cards, max-HP
	# stakes, next-fight boons) — not just re-price gold/HP/Curse.

	# ── The keyword teacher (pick a school, pick a soldier) ──

	"the_lame_master": {
		"name": "The Pensioned Master",
		"desc": "An old master-at-arms drills scarecrows on half pay. She reads your soldiers the way a clerk reads a bad ledger. \"One of them. One lesson. My knee decides how long.\"",
		"art": "beekeeper_returns",
		"mood": "ember",
		"choices": [
			{
				"label": "The low guard\n\nShe breaks the stance down to nothing and builds\nit back with the shield on the inside of the bone.",
				"desc": "-4 HP; a chosen creature gains Armored, permanently",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "grant_keyword_pick", "keyword": "armored",
						"prompt": "Who takes the lesson? (gains Armored)"},
				],
			},
			{
				"label": "The first step\n\n\"Wars are lost standing still.\" She teaches the step\nthat lands before the other side has drawn breath.",
				"desc": "-4 HP; a chosen creature gains Swift, permanently",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "grant_keyword_pick", "keyword": "swift",
						"prompt": "Who takes the lesson? (gains Swift)"},
				],
			},
			{
				"label": "The answered blow\n\n\"Make them pay to touch you.\" This lesson\nleaves marks on everyone involved. That is the lesson.",
				"desc": "-4 HP; a chosen creature gains Thorns, permanently",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "grant_keyword_pick", "keyword": "thorns",
						"prompt": "Who takes the lesson? (gains Thorns)"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "stalwart"},
				"label": "Salute her by her old rank\n\nShe straightens an inch past what the knee allows.\nFor one of her own, the bruises are waived.",
				"desc": "A chosen creature gains Armored, free",
				"effects": [
					{"type": "grant_keyword_pick", "keyword": "armored",
						"prompt": "Who takes the lesson? (gains Armored)"},
				],
			},
		],
	},

	# ── The whole-deck swap (levies out, veterans in) ──

	"the_free_company": {
		"name": "The Free Company",
		"desc": "Mercenaries at a cold camp, professionally unimpressed. \"Farmhands,\" the recruiter says. \"I'll trade you soldier for soldier — every copy of a kind, if you can part with them.\"",
		"gate": {"type": "starters_at_least", "value": 2},
		"art": "fork_in_the_long_road",
		"mood": "gilt",
		"choices": [
			{
				# Campaign memory: word of a 6-kill veteran travels between camps.
				"blue": {"type": "veteran_kills_at_least", "value": 6},
				"label": "He asks after {veteran} by name\n\nWord of the notches travels between camps. He does not insult\nyou with an offer — he pays tribute rates for a look at the technique.",
				"desc": "+35 gold",
				"effects": [
					{"type": "gold", "value": 35},
				],
			},
			{
				"label": "Muster out a levy\n\nHe takes every copy of the same green face and sends\nback the same count in scarred ones. No two alike.",
				"desc": "Remove every copy of one starter; gain that many uncommon cards",
				"effects": [
					{"type": "veteran_swap"},
				],
			},
			{
				"label": "Buy one veteran outright\n\nShe names her own price, and it is not negotiable,\nand by the look of her kit she is worth it.",
				"desc": "-65 gold, +1 uncommon card",
				"effects": [
					{"type": "gold", "value": -65},
					{"type": "add_card", "rarity": "uncommon"},
				],
			},
			{
				"label": "Steal their muster-book\n\nEvery name in it is owed by somebody.\nNow the book rides with you. So does the owing.",
				"desc": "+45 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 45},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The Curse outlet with scale (mass purge, priced in flesh) ──

	"the_scapegoat": {
		"name": "The Scapegoat",
		"desc": "A goat stands tethered at the boundary stone, wearing the village's sins on little paper collars. It regards you with professional calm. There is room on its back.",
		"gate": {"type": "has_curse"},
		"art": "two_headed_calf",
		"mood": "verdigris",
		"choices": [
			{
				"label": "Load every sin you carry\n\nThe goat holds your gaze while the paper goes on.\nWhat leaves on its back still leaves through you.",
				"desc": "Remove ALL Curses from your deck; lose 2 max HP for each",
				"effects": [
					{"type": "purge_curses", "max_hp_per": 2},
				],
			},
			{
				"label": "Pay the parish rate\n\nThe priest weighs one sin in his palm, names a figure,\nand ties it on with a little bow. Very professional.",
				"desc": "-25 gold, remove a chosen Curse",
				"effects": [
					{"type": "gold", "value": -25},
					{"type": "remove_choice_filtered", "filter": "curse"},
				],
			},
			{
				"label": "Untie it and take it with you\n\nThe parish is horrified. The goat is delighted.\nIts current load, of course, transfers.",
				"desc": "The Scapegoat (1/4) joins your next fight; +1 Curse",
				"effects": [
					{"type": "gift_creature", "name": "The Scapegoat", "atk": 1, "hp": 4, "kw": [],
						"text": "The goat falls in beside the baggage cart as if promoted."},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The all-in gamble (poverty for power) ──

	"the_reliquary_cart": {
		"name": "The Reliquary Cart",
		"desc": "A chapel on wagon wheels: saints' shin-bones in glass, a coin slot worn smooth. The friar does not preach — he opens the ledger of miracles to the page that matches your purse.",
		"art": "the_answering_well",
		"mood": "gilt",
		"choices": [
			{
				"blue": {"type": "hero_is", "value": "pyromancer"},
				"label": "Let him see your hands\n\nThe friar has read the file on your fires — there IS a file.\nHe blesses your banner unasked, at speed, to stay on your good side.",
				"desc": "+1 max Command next fight, free",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "The blessing is genuine. The hurry in it is also genuine."},
				],
			},
			{
				"blue": {"type": "gold_at_least", "value": 120},
				"label": "Empty the war chest into the slot\n\nThe friar counts by ear. Somewhere past the hundredth coin\nhe stops a saint mid-sentence and takes something down.",
				"desc": "Lose ALL your gold; gain a boss-tier relic",
				"effects": [
					{"type": "lose_gold_partial", "value": 99999},
					{"type": "add_boss_relic"},
				],
			},
			{
				"label": "A soldier's tithe\n\nOne coin for the box, one prayer for the column.\nThe friar blesses your banner at the going rate.",
				"desc": "-25 gold; +1 max Command next fight",
				"effects": [
					{"type": "gold", "value": -25},
					{"type": "combat_mana", "value": 1,
						"text": "The blessing sits on your banner like weather about to break."},
				],
			},
			{
				"label": "Rob the poor-box\n\nIt is nailed, chained, and blessed.\nSo were you, once.",
				"desc": "The box decides — friars fight like mule-drivers",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The chain gives before the friar finishes crossing himself. You leave heavier in coin and lighter in standing — somewhere, a saint has opened a file.",
							"effects": [{"type": "gold", "value": 85}, {"type": "add_curse"}]},
						{"weight": 1,
							"text": "The friar breaks a shin-bone over your head — a RELIC, technically, so it hardly counts as violence. You get a fistful of coins and a week of headaches.",
							"effects": [{"type": "damage", "value": 7}, {"type": "gold", "value": 35}]},
					]},
				],
			},
		],
	},

	# ── The fallen paid forward (campaign-memory payoff) ──

	"the_bell_of_names": {
		"name": "The Bell of Names",
		"desc": "A traveling foundry pours bells from battle-scrap. Names cast into the rim ring longest. The master reads your column once. \"Give me the roll. All of it.\"",
		"gate": {"type": "fallen_at_least", "value": 2},
		"art": "drowned_bell",
		"mood": "ember",
		"choices": [
			{
				"label": "Cast the roll into the rim\n\nName by name — {fallen} last of all — the mould takes them.\nWhat rings for the dead rings a little in the living.",
				"desc": "+1 max HP for each name on your Roll of the Fallen (max +6)",
				"effects": [
					{"type": "scaled", "count": "fallen", "per": 1, "cap": 6, "outcome": "max_hp"},
				],
			},
			{
				"label": "Sell him your battle-scrap\n\nDented, dulled, or done — he pays foundry rates\nand asks nothing the metal wouldn't answer.",
				"desc": "+40 gold",
				"effects": [
					{"type": "gold", "value": 40},
				],
			},
			{
				"label": "Ring the finished bell\n\nThe peal rolls out over the next three fields. Everything\nin them now knows a paid-up army is coming.",
				"desc": "+1 max Command next fight",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "The peal marches ahead of the column and holds the ground for you."},
				],
			},
		],
	},

	# ── The hp-gated heal, with teeth (enemy mercy) ──

	"the_chirurgeon": {
		"name": "The Chirurgeon",
		"desc": "An enemy field hospital, no patients left to lose. The chirurgeon sharpens instruments nobody needs, and brightens at your limp in a way you do not love. \"Sit. Please.\"",
		"gate": {"type": "hp_below_pct", "value": 0.5},
		"art": "tooth_witch",
		"mood": "verdigris",
		"choices": [
			{
				"label": "Lie down on his table\n\nHe is excellent. He is also thorough,\nand he has been bored for a very long time.",
				"desc": "Heal to full, gain a Wound",
				"effects": [
					{"type": "heal_full"},
					{"type": "add_curse_id", "id": "wound"},
				],
			},
			{
				"label": "Buy his kit instead\n\nHe parts with it the way soldiers part with rations —\ngrieving, and counting the coin twice.",
				"desc": "-35 gold, gain 2 random potions",
				"effects": [
					{"type": "gold", "value": -35},
					{"type": "gain_potion_random"},
					{"type": "gain_potion_random"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "acolyte"},
				"label": "Talk shop\n\nYou dressed wounds through a worse war than his. He listens,\ntakes notes, and treats you as a colleague — carefully.",
				"desc": "Heal 9 HP, free",
				"effects": [
					{"type": "heal", "value": 9},
				],
			},
			{
				"label": "Limp on\n\nHe deflates. The cots stay empty. You hear\nthe whetstone resume behind you.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	# ── The clean exhale (life insists, mid-war) ──

	"the_wedding_at_the_ford": {
		"name": "The Wedding at the Ford",
		"desc": "Two half-burned villages are marrying their heirs at the river, mid-war, so SOMEONE owns the mill lawfully by winter. You are the only armed guest — which makes you the guest of honor.",
		"art": "thrice_blessed_spring",
		"mood": "ember",
		"choices": [
			{
				"label": "Stand as witness\n\nYou sign the register under 'sword'. Both mothers\nfeed you personally, in shifts, as a compliment.",
				"desc": "Heal 8 HP, +15 gold",
				"effects": [
					{"type": "heal", "value": 8},
					{"type": "gold", "value": 15},
				],
			},
			{
				"label": "Dance the sword-dance\n\nYou half remember it. The fiddler slows down for you.\nThe river is RIGHT there, and everyone knows it.",
				"desc": "The dance decides — glory or the river",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "You are, briefly, magnificent. The villages pass the hat, the fiddler takes a bow on your behalf, and two separate grandmothers propose.",
							"effects": [{"type": "gold", "value": 35}]},
						{"weight": 1,
							"text": "Into the river, to a standing ovation. The bride fishes you out herself, still in her wedding crown, and presses a bottle on you for your dignity. There is no saving your dignity.",
							"effects": [{"type": "damage", "value": 2}, {"type": "gain_potion"}]},
					]},
				],
			},
			{
				"label": "Leave a soldier's gift\n\nYour second-best knife, laid on the gift table between\nthe butter churn and somebody's heirloom spoons.",
				"desc": "-30 gold; the blessing of two villages: +4 max HP",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "gain_max_hp", "value": 4},
				],
			},
		],
	},

	# ── War comedy: the arms dealer (gate: at_war) ──

	"the_ladder_merchant": {
		"name": "The Ladder-Merchant",
		"desc": "A cart of siege ladders, parked exactly between the armies. \"Patent escalade,\" he says, slapping a rung. \"{lord} bought 6. Between us — I sold him the SHORT ones.\"",
		"gate": {"type": "at_war"},
		# Stand-in: the forge cart — the closest fit for an arms dealer's rig.
		"art": "old_forge",
		"mood": "gilt",
		"choices": [
			{
				"label": "Buy the ladder\n\nIt is, in fairness, an excellent ladder.\nIt takes 2 men to carry and fears nothing.",
				"desc": "-30 gold; the Patent Ladder (0/7, Armored) joins your next fight",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "gift_creature", "name": "Patent Ladder", "atk": 0, "hp": 7,
						"kw": ["armored"],
						"text": "The ladder is lashed to the baggage cart. It will stand in your line next fight, fearing nothing."},
				],
			},
			{
				"label": "Buy the patent itself\n\nFor the right sum he retires on the spot, hands you\nthe bracket, the stamp, and the ledger of who owes what.",
				"desc": "-70 gold, +random relic",
				"effects": [
					{"type": "gold", "value": -70},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Tip him your route\n\nHe pays for marching schedules in good coin\nand sells them onward in better.",
				"desc": "+50 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 50},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The named-card payoff (grim; pays Old Bones by name) ──

	"the_last_garrison": {
		"name": "The Last Garrison",
		"desc": "Five dead men hold a fort for a war that ended before your grandmother. They know. But your banner, if they squint, could be authority.",
		"gate": {"type": "act_at_least", "value": 2},
		"art": "plague_bell",
		"mood": "bone",
		"choices": [
			{
				"label": "Read them the relief order\n\nYou improvise it with full honors. 4 of them march into\nthe hill, at rest. The sergeant, out of habit, falls in with you.",
				"desc": "Gain Old Bones (rare); his long watch follows: +1 Grave-Debt",
				"effects": [
					{"type": "add_card_id", "id": "old_bones"},
					{"type": "add_curse_id", "id": "grave_debt"},
				],
			},
			{
				"label": "Requisition the armory\n\n90 years of stores, and the dead sign the chit\nwithout reading it. Old habits.",
				"desc": "+55 gold, -5 HP",
				"effects": [
					{"type": "gold", "value": 55},
					{"type": "damage", "value": 5},
				],
			},
			{
				"label": "Post them to your keep\n\nYou cannot relieve them. You CAN redeploy them.\nThe paperwork is dubious. The dead don't check.",
				"desc": "A Garrison Shade (2/5, Last Stand) joins your next fight",
				"effects": [
					{"type": "gift_creature", "name": "Garrison Shade", "atk": 2, "hp": 5,
						"kw": ["last_stand"],
						"text": "One of the watch shoulders his pike and falls in, still on duty. He has died before. It didn't take."},
				],
			},
		],
	},

	# ── The transform verb's home (funny livestock register) ──

	"the_remount_fair": {
		"name": "The Remount Fair",
		"desc": "Horse-traders behind the lines, dealing in everything a war sheds — remounts, mules, stranger stock under blankets. A painted board gives the rule: ONE IN, ONE OUT. NO REFUNDS. SOME BITE.",
		"art": "hermit",
		"mood": "ember",
		"choices": [
			{
				"blue": {"type": "hero_is", "value": "raider"},
				"label": "Read the brands\n\nHalf this stock was lifted from somebody, and you can name the\nroads it was lifted on. The dealer drops his price mid-sentence.",
				"desc": "-20 gold, +1 random uncommon card",
				"effects": [
					{"type": "gold", "value": -20},
					{"type": "add_card", "rarity": "uncommon"},
				],
			},
			{
				"label": "Trade one in\n\nYours goes behind the canvas.\nSomething the same weight comes back out.",
				"desc": "Transform a chosen card into a random card of the same rarity",
				"effects": [
					{"type": "transform_choice", "value": 1},
				],
			},
			{
				"label": "Trade a matched pair\n\nThe dealer's eyes light up — pairs move fast.\nOne of the replacements bites you on the way out.",
				"desc": "-4 HP, transform 2 chosen cards",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "transform_choice", "value": 2},
				],
			},
			{
				"label": "Buy from under the blanket\n\nSight unseen, cage included.\nThe blanket moves in a way you elect to ignore.",
				"desc": "-45 gold, +1 random uncommon card",
				"effects": [
					{"type": "gold", "value": -45},
					{"type": "add_card", "rarity": "uncommon"},
				],
			},
		],
	},

	# ── The eerie max-HP wager ──

	"the_kings_measure": {
		"name": "The King's Measure",
		"desc": "A royal surveyor works the dead road, keeping a ledger sealed by a king 4 wars gone. He measures the road. He measures the ruts. He turns, and measures YOU.",
		"art": "marked_one",
		"mood": "bone",
		"choices": [
			{
				"label": "Stand for the measure\n\nThe chain is cold and the entries are binding.\nYou will be exactly as much as the ledger says.",
				"desc": "The ledger decides your size — it is not always flattering",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 3,
							"text": "\"Taller than recorded,\" he says, annoyed at the road, and corrects the entry. You feel the correction take. The extra inch is yours to keep.",
							"effects": [{"type": "gain_max_hp", "value": 4}]},
						{"weight": 2,
							"text": "He measures twice, which is somehow worse. \"The ledger,\" he says, gently, \"is never wrong.\" You are less than you were told, and now it is official.",
							"effects": [{"type": "lose_max_hp", "value": 2}]},
					]},
				],
			},
			{
				"label": "Carry his chain a mile\n\nHonest work for a mad office. He pays in coin\nstruck by a mint that no longer exists.",
				"desc": "-3 HP, +45 gold",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "gold", "value": 45},
				],
			},
			{
				"label": "Ask what he is measuring FOR\n\nHe shows you the ledger's last page.\nYou wish you had not seen the total.",
				"desc": "+1 Curse; the knowing sharpens you: upgrade a chosen card",
				"effects": [
					{"type": "add_curse"},
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ══════════════════ NEW — 2026-07-04 additions ══════════════════
	# One build-reader (the scaled engine pays spells, gated so a deck
	# without the material never rolls it), two act-3 heavyweights (the
	# road before the last keep), and a second hidden+tell room so
	# tell-reading stays a skill past act 1.

	# ── The build-reader: he pays for what your magic did (scaled: spells) ──

	"the_war_poet": {
		"name": "The War-Poet",
		"desc": "A poet follows the war at a professional distance, setting it in rhyme royal. \"Spells,\" he says, pen already moving. \"Nobody pays to hear about pike-drill. Tell me about the [color=#d97a3a]fire[/color].\"",
		"gate": {"type": "deck_count_at_least", "kind": "spells", "value": 2},
		"art": "woodcutter",
		"mood": "gilt",
		"choices": [
			{
				"label": "Sell him the true accounts\n\nEvery working you carry becomes a stanza.\nHe pays by the verse, and verses need material.",
				"desc": "+6 gold per spell in your deck (max 60)",
				"effects": [
					{"type": "scaled", "count": "spells", "per": 6, "cap": 60,
						"outcome": "gold"},
				],
			},
			{
				"label": "Embellish\n\nThe fireball becomes a firestorm. The trick with the rope\nbecomes a hanging. His rates improve. His ear, unfortunately, is good.",
				"desc": "His ear decides — better rates, or a mocking verse",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "He believes every word, or pays as if he does — art is not sworn testimony. The purse he hands over is embarrassingly heavy.",
							"effects": [{"type": "gold", "value": 70}]},
						{"weight": 1,
							"text": "He stops writing mid-line and looks at you with terrible kindness. The verse he composes instead is short, accurate, and about you. By the next camp, everyone knows the chorus.",
							"effects": [{"type": "add_curse_id", "id": "craven"}]},
					]},
				],
			},
			{
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Give him {fallen}\n\nNot the dying — the marching. The bad jokes, the borrowed boots,\nthe name said right. He writes it down like it matters. It does.",
				"desc": "+25 gold, heal 6 HP",
				"effects": [
					{"type": "gold", "value": 25},
					{"type": "heal", "value": 6},
				],
			},
		],
	},

	# ── Act 3: the army lightens for the last climb ──

	"the_ninth_milestone": {
		"name": "The Ninth Milestone",
		"desc": "The ninth milestone from the keep, where armies lighten themselves for the last march — the verge is a hundred years deep in what could not be carried. Whatever you leave here stays left.",
		"gate": {"type": "act_at_least", "value": 3},
		"art": "the_weeping_orchard",
		"mood": "bone",
		"choices": [
			{
				"label": "Bury what you cannot carry\n\nThe verge takes it without comment.\nThe column walks lighter. The hill notices.",
				"desc": "Remove 2 chosen cards",
				"effects": [
					{"type": "remove_choice_multi", "value": 2},
				],
			},
			{
				"label": "Take up what the dead set down\n\nA fine thing, half-buried, still warm somehow.\nWhoever left it left the owing with it.",
				"desc": "+1 random relic, +1 Grave-Debt",
				"effects": [
					{"type": "random_relic"},
					{"type": "add_curse_id", "id": "grave_debt"},
				],
			},
			{
				"label": "Read the milestone\n\nNine miles. After everything, nine miles.\nThe column stands a little straighter for knowing the number.",
				"desc": "+1 max Command next fight",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "Nine miles. The number marches with you, and it weighs nothing."},
				],
			},
		],
	},

	# ── Act 3, at war: one of the five sees the ending coming ──

	"the_turncoat_general": {
		"name": "The Turncoat General",
		"desc": "A man waits at the roadside in {kingdom}'s colors, the insignia unpicked — one of {lord}'s own five. \"You are going to win,\" he says, like weather. \"I would like to be somewhere accounted for when you do.\"",
		"gate": {"type": "all", "gates": [
			{"type": "at_war"},
			{"type": "act_at_least", "value": 3},
		]},
		"art": "mirror_twin",
		"mood": "ember",
		"choices": [
			{
				"label": "Take his sword and his service\n\nHe is very good. That was never the question.\nThe question is what he cost the last army he was good for.",
				"desc": "The Turncoat General (3/6) joins your next fight; +1 War-Debt",
				"effects": [
					{"type": "gift_creature", "name": "Turncoat General", "atk": 3, "hp": 6,
						"kw": [],
						"text": "He falls in at the column's head as if the position had been holding itself for him."},
					{"type": "add_curse_id", "id": "war_debt"},
				],
			},
			{
				"label": "Buy the keep's watchword\n\nHe sells it flat, no ceremony — a word for a purse.\n\"The door opens easier,\" he says, \"when it knows you.\"",
				"desc": "-45 gold; +1 max Command next fight",
				"effects": [
					{"type": "gold", "value": -45},
					{"type": "combat_mana", "value": 1,
						"text": "The watchword sits under your tongue like a key."},
				],
			},
			{
				"label": "Strip him and send him walking\n\nNo sword, no colors, no accounting. What's in his boots\nis yours. What you just made of him follows you instead.",
				"desc": "+50 gold, +1 Deserter's Mark",
				"effects": [
					{"type": "gold", "value": 50},
					{"type": "add_curse_id", "id": "deserters_mark"},
				],
			},
		],
	},

	# ── Hidden-info #2 (act 2+): the tells stay a skill past the carnival ──

	"the_drowned_ferry": {
		"name": "The Drowned Ferry",
		"desc": "A lake where the map insists on a meadow. Three ferrymen wait at three landings, and none names a fare — on this water, you learn the price when you land. Choose your boat.",
		"gate": {"type": "act_at_least", "value": 2},
		"art": "hollow_lantern",
		"mood": "verdigris",
		"choices": [
			{
				"hidden": true,
				"tell": "The first boat rides low, patched with coffin-wood, and the ferryman's hands are raw from bailing something that is not water.",
				"desc": "Hidden",
				"effects": [
					{"type": "add_rare"},
					{"type": "add_curse_id", "id": "grave_debt"},
				],
			},
			{
				"hidden": true,
				"tell": "The second boat is dry as a pulpit and full of birdcages, every door open. The ferryman hums while he waits, and looks extremely well fed.",
				"desc": "Hidden",
				"effects": [
					{"type": "lose_gold_partial", "value": 25},
					{"type": "transform_choice", "value": 1},
				],
			},
			{
				"hidden": true,
				"tell": "The third boat does not sit in the water so much as slightly above it, and the ferryman's pole comes up dry. He is looking at you as if you are late.",
				"desc": "Hidden",
				"effects": [
					{"type": "random_relic"},
					{"type": "damage", "value": 5},
				],
			},
		],
	},

	# ══════════════════ NEW — 2026-07-07 visual-diversity pass ══════════════════
	# These five are designed AROUND the strongest unused paintings (the art is
	# the brief, per the art-sourcing standard): the pool's only golden-daylight
	# canvas, the burning apiary, the blood basin, the cocoon barn, and the
	# glass cat. One concept per event, payoffs touch the build or the fighting.

	# ── The bee-wife (part 1 of 2): the road's one warm afternoon ──

	"the_bee_wife": {
		"name": "The Bee-Wife",
		"desc": "An old woman wheels her hives AWAY from the war, unhurried, through the year's last golden afternoon. She stops beside your column. \"The bees want telling,\" she says. \"News for news. That is the custom.\"",
		"art": "beekeeper_again",
		"mood": "gilt",
		"ambience": "bees",
		"choices": [
			{
				"label": "Buy a wintering skep\n\n\"Mind the lid,\" she says, strapping it shut.\nWhatever knocks it over will wish it had not.",
				"desc": "-25 gold; the Hive Skep (0/5, Thorns) joins your next fight",
				"effects": [
					{"type": "gold", "value": -25},
					{"type": "gift_creature", "name": "Hive Skep", "atk": 0, "hp": 5,
						"kw": ["thorns"],
						"text": "The skep rides the baggage cart, humming to itself in a minor key."},
				],
			},
			{
				# Campaign memory: the old custom — deaths must be told to the bees.
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "Tell the bees your dead\n\nYou say {fallen}'s name into the hive-mouth, the old way.\nThe hum drops for a breath. She waits until it climbs again.",
				"desc": "The custom, paid in full: heal 8 HP, +1 Healing Potion",
				"effects": [
					{"type": "heal", "value": 8},
					{"type": "gain_potion"},
				],
			},
			{
				"label": "Trade her the road's news\n\nWhich bridges stand. Which towns burn. She listens the way\nclerks count, and pays in comb the weight of what you know.",
				"desc": "Heal 7 HP",
				"effects": [
					{"type": "heal", "value": 7},
				],
			},
			{
				"label": "Make off with a comb rack\n\nShe does not chase you. She does not need to.\nEvery bee on this road now files you under WASP.",
				"desc": "+40 gold, +1 Curse",
				"effects": [
					{"type": "gold", "value": 40},
					{"type": "add_curse"},
				],
			},
		],
	},

	# ── The bee-wife (part 2 of 2): the war reached her anyway ──

	"the_burned_apiary": {
		"name": "The Burned Apiary",
		"desc": "The bee-wife's yard, black to the fence line — the war came through on its way to somewhere else. She rakes ash without looking up. Above the plot hangs a homeless roar, waiting to be aimed.",
		"gate": {"type": "all", "gates": [
			{"type": "act_at_least", "value": 2},
			{"type": "seen_all", "events": ["the_bee_wife"]},
		]},
		"art": "beekeeper",
		"mood": "ember",
		"ambience": "fire_crackle",
		"choices": [
			{
				"label": "Take up the swarm\n\n\"They won't winter wild,\" she says. \"They'll war, though.\"\nShe hands you the veil. The roar falls in behind the column.",
				"desc": "The Swarm (3/1, Swift) joins your next fight",
				"effects": [
					{"type": "gift_creature", "name": "The Swarm", "atk": 3, "hp": 1,
						"kw": ["swift"],
						"text": "The Swarm travels above the column like weather with a grudge."},
				],
			},
			{
				"label": "Rake for the queen\n\nOn your knees in the warm ash, parting cinders\nwith the flat of a knife. She works the other end of the row.",
				"desc": "The ash decides what's left",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "The queen turns up alive in a hollow fence post, furious. The bee-wife laughs like a girl and presses the whole cellar's honey on you — no hives left to feed, she says. Eat it marching.",
							"effects": [{"type": "heal", "value": 8}, {"type": "gain_potion"}]},
						{"weight": 1,
							"text": "Wax and char, row after row. She pays you for the hour of your knees anyway, at a lord's rate, out of a jar the fire never found. It matters to her that the work is paid.",
							"effects": [{"type": "gold", "value": 25}]},
					]},
				],
			},
			{
				"label": "Put her name in the column's book\n\nShe cannot hold a pike. She can cook, stitch wounds, and hate\naccurately. The quartermaster's ledger gains a line.",
				"desc": "-30 gold (her wage); +3 max HP",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "gain_max_hp", "value": 3},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "kindler"},
				"label": "Read the burn\n\nYou bank fires for a living. This one was walked in a line,\nwith intent. You say nothing. But you will know their banners.",
				"desc": "+1 max Command next fight",
				"effects": [
					{"type": "combat_mana", "value": 1,
						"text": "You know which company burns like this. The knowing marches with you."},
				],
			},
		],
	},

	# ── The flesh-priced forge (the well converts between flesh and steel) ──

	"the_red_tithe": {
		"name": "The Red Tithe",
		"desc": "A round basin brims red under a red moon, and the overflow runs uphill. The kneeling-stone before it is worn to a polish. The tariff board is blank — the well already knows what you came for.",
		"art": "blood_fountain",
		"mood": "ember",
		"choices": [
			{
				"label": "Dip your blades\n\nEdge by edge, the red takes the years off the steel.\nWhat it takes off you, it keeps.",
				"desc": "-3 max HP; upgrade 2 chosen cards",
				"effects": [
					{"type": "lose_max_hp", "value": 3},
					{"type": "upgrade_choice_multi", "value": 2},
				],
			},
			{
				"label": "Tithe a name from the rolls\n\nThe well takes the name off your muster and pays in vessel.\nSomewhere tonight, a soldier wakes up as somebody else.",
				"desc": "Remove a chosen card; +3 max HP",
				"effects": [
					{"type": "gain_max_hp", "value": 3},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Fill your flask\n\nThe basin only pours what you pour first.\nIt is strict about the order.",
				"desc": "-4 HP, gain a random potion",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "gain_potion_random"},
				],
			},
			{
				"blue": {"type": "hero_is", "value": "acolyte"},
				"label": "Name the rite\n\nYou know this well's church, and it is not a church.\nSpoken to properly, it waives the tithe. Once.",
				"desc": "Upgrade a chosen card, free",
				"effects": [
					{"type": "upgrade_choice"},
				],
			},
		],
	},

	# ── The cocoon barn (act 2+; the gamble is what hatches, never whether) ──

	"the_chrysalis": {
		"name": "The Chrysalis",
		"desc": "A tithe barn hung floor to rafter with pale bundles, each the size of a man and gently creaking. The silk is worth money. The waiting is worth more. One of them is warm.",
		"gate": {"type": "act_at_least", "value": 2},
		"mood": "verdigris",
		"choices": [
			{
				"label": "Cut the warm one down\n\nYou carry it lashed to the cart like a rolled tent.\nBy the next field, something inside has turned to face front.",
				"desc": "It hatches where you fight next — the silk decides what",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 3,
							"text": "It splits at the first horn-call, hungry and on your side. What climbs out folds its wet wings the way a veteran squares a cloak.",
							"effects": [{"type": "gift_creature", "name": "The Hatched",
								"atk": 4, "hp": 2, "kw": ["swift"],
								"text": "The Hatched keeps pace with the column, drying in the wind."}]},
						{"weight": 2,
							"text": "It hatches early, on the road, into something that clearly stopped becoming halfway through. It follows you anyway. It is trying.",
							"effects": [{"type": "gift_creature", "name": "The Half-Made",
								"atk": 1, "hp": 4, "kw": [],
								"text": "The Half-Made carries its own silk like a soldier carries a bedroll."}]},
					]},
				],
			},
			{
				# Campaign memory, at its least comfortable.
				"blue": {"type": "fallen_at_least", "value": 1},
				"label": "One of them says {fallen}'s name\n\nNot loudly. The way a sleeper says a name.\nYou could cut it down. You should not cut it down.",
				"desc": "The Almost (2/4) joins your next fight; +1 Curse",
				"effects": [
					{"type": "gift_creature", "name": "The Almost", "atk": 2, "hp": 4,
						"kw": [],
						"text": "It marches where they used to march. It has the walk almost right."},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Strip the silk\n\nThe empty ones give freely. The full ones give too,\nif you are quick and do not listen.",
				"desc": "+40 gold",
				"effects": [
					{"type": "gold", "value": 40},
				],
			},
		],
	},

	# ── The glass cat (perfect memory sold by the copy) ──

	"the_glass_familiar": {
		"name": "The Glass Familiar",
		"desc": "A cat of clear glass sits on a chapel shelf, grooming a paw it does not need to groom. Where its gaze rests, things double — two candles where one burns. It looks at your deck. It purrs like a finger on a wet glass rim.",
		"art": "glass_familiar",
		"mood": "verdigris",
		"choices": [
			{
				"label": "Let it study a soldier\n\nIt circles the card twice and sits, satisfied.\nSomewhere inside the glass, a second one opens its eyes.",
				"desc": "-45 gold; add a copy of a chosen card to your deck",
				"effects": [
					{"type": "gold", "value": -45},
					{"type": "copy_card"},
				],
			},
			{
				# Campaign memory: it has been watching the column, the way cats do.
				"blue": {"type": "veteran_kills_at_least", "value": 6},
				"label": "It already knows {veteran}\n\nIt has watched the column for miles, the way cats watch.\nThe copy was finished yesterday. It was waiting for you to ask.",
				"desc": "Add a copy of a chosen card, free",
				"effects": [
					{"type": "copy_card"},
				],
			},
			{
				"label": "Tap the glass\n\nYou should not tap the glass.\nEveryone knows you should not tap the glass.",
				"desc": "The glass decides",
				"effects": [
					{"type": "roll_table", "outcomes": [
						{"weight": 2,
							"text": "It rings one pure note, flows off the shelf, and threads between your ankles all the way back to the column. Apparently you are furniture now. Its favorite furniture.",
							"effects": [{"type": "gift_creature", "name": "Glass Cat",
								"atk": 1, "hp": 1, "kw": ["thorns"],
								"text": "The Glass Cat rides the baggage cart, refracting."}]},
						{"weight": 1,
							"text": "A hairline crack climbs one ear. The note it makes now is wrong in a way that follows you out the door and learns your route.",
							"effects": [{"type": "add_curse"}]},
					]},
				],
			},
			{
				"label": "Leave it be\n\nIt was sitting on a coin, the way cats sit on exactly\nwhat you need. It lifts, briefly, so you can take it.",
				"desc": "+15 gold",
				"effects": [
					{"type": "gold", "value": 15},
				],
			},
		],
	},
}
