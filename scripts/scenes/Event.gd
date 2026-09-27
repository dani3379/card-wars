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
##                 uncommons (the Free Company's bounded one-for-one muster)
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
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
# The gamble stage's painters (2026-07-18 "the screen plays the scene" pass —
# see docs/EVENT_PLAY_PITCH_20260718.md). Same-name consts, painter-extraction
# convention.
const KnuckleboneDie = preload("res://scripts/ui/painters/KnuckleboneDie.gd")
const CastPatch = preload("res://scripts/ui/painters/CastPatch.gd")
const TouchGlow = preload("res://scripts/ui/painters/TouchGlow.gd")
const CandleStub = preload("res://scripts/ui/painters/CandleStub.gd")
const EventHelm = preload("res://scripts/ui/painters/EventHelm.gd")
const PaperSlip = preload("res://scripts/ui/painters/PaperSlip.gd")
const BoneStraw = preload("res://scripts/ui/painters/BoneStraw.gd")
const TrinketIcon = preload("res://scripts/ui/painters/TrinketIcon.gd")
const EffectsTray = preload("res://scripts/ui/painters/EffectsTray.gd")
const TrayCloth = preload("res://scripts/ui/painters/TrayCloth.gd")
const PayToken = preload("res://scripts/ui/painters/PayToken.gd")
const PaySack = preload("res://scripts/ui/painters/PaySack.gd")
const TallySlate = preload("res://scripts/ui/painters/TallySlate.gd")
const DerbyBeetle = preload("res://scripts/ui/painters/DerbyBeetle.gd")
const CoinProp = preload("res://scripts/ui/painters/CoinProp.gd")
const ChalkSlate = preload("res://scripts/ui/painters/ChalkSlate.gd")
const FieldCell = preload("res://scripts/ui/painters/FieldCell.gd")
const DrumHead = preload("res://scripts/ui/painters/DrumHead.gd")
const BalanceScale = preload("res://scripts/ui/painters/BalanceScale.gd")
const StrongboxDial = preload("res://scripts/ui/painters/StrongboxDial.gd")
const PowderKeg = preload("res://scripts/ui/painters/PowderKeg.gd")
const WarPip = preload("res://scripts/ui/painters/WarPip.gd")
const PipDie = preload("res://scripts/ui/painters/PipDie.gd")
const FortuneWheel = preload("res://scripts/ui/painters/FortuneWheel.gd")
const EVENT_LAYOUT_STAGE = preload("res://scripts/ui/painters/EventLayoutStage.gd")
const EVENT_CHOICE_DEVICE = preload("res://scripts/ui/painters/EventChoiceDevice.gd")

# Nodes that survive across UI rebuilds within a single event (initial choice
# screen → result screen → continue). Modal sub-pickers (remove/butcher) hide
# the art via _set_event_art_visible() so deck cards stay readable.
const PRESERVE_NODES := [
	"Background", "Atmosphere", "EventArt",
	"EventOverlayLeft", "StakesLedger",
]

var _event_id: String = ""
var _event_data: Dictionary = {}
var _event_image: Texture2D = null
var _event_image_path: String = ""
var _event_art_request_serial: int = 0
var _event_art_loading: bool = false
var _event_art_visible: bool = true
# Offline 48x27 luminance scan of the current event plates. Keeping this tiny
# table avoids a full-texture GPU readback/decompress/resize on the first frame
# of every event; new art safely falls back to the house scrim until calibrated.
const ART_SCRIM_DARKNESS := {
	"res://assets/events/beekeeper.png": 0.6662,
	"res://assets/events/beekeeper_again.png": 0.8500,
	"res://assets/events/beekeeper_returns.png": 0.6793,
	"res://assets/events/blood_fountain.png": 0.7034,
	"res://assets/events/butcher.png": 0.5891,
	"res://assets/events/coin_on_edge.png": 0.7067,
	"res://assets/events/dark_altar.png": 0.7694,
	"res://assets/events/drowned_bell.png": 0.6833,
	"res://assets/events/fattened_sin_eater.png": 0.7229,
	"res://assets/events/fork_in_the_long_road.png": 0.8500,
	"res://assets/events/glass_familiar.png": 0.6618,
	"res://assets/events/gravesong_choir.png": 0.8500,
	"res://assets/events/hermit.png": 0.7038,
	"res://assets/events/hollow_lantern.png": 0.7177,
	"res://assets/events/marked_one.png": 0.7176,
	"res://assets/events/mirror_twin.png": 0.7469,
	"res://assets/events/old_forge.png": 0.6842,
	"res://assets/events/pawnbrokers_window.png": 0.6173,
	"res://assets/events/plague_bell.png": 0.8500,
	"res://assets/events/rotting_carnival.png": 0.7541,
	"res://assets/events/sin_eater.png": 0.6963,
	"res://assets/events/strangers_hand.png": 0.7110,
	"res://assets/events/the_answering_well.png": 0.6257,
	"res://assets/events/the_bone_pit.png": 0.6719,
	"res://assets/events/the_chrysalis.png": 0.6847,
	"res://assets/events/the_crossing.png": 0.6605,
	"res://assets/events/the_weeping_orchard.png": 0.6891,
	"res://assets/events/three_doors.png": 0.6914,
	"res://assets/events/thrice_blessed_spring.png": 0.7413,
	"res://assets/events/tollkeeper_bridge.png": 0.6513,
	"res://assets/events/tooth_witch.png": 0.7214,
	"res://assets/events/two_headed_calf.png": 0.6802,
	"res://assets/events/woodcutter.png": 0.7055,
}
# Current screen's body: starts as _event_data and gets swapped to a follow_up
# sub-dict when the player picks a branching choice. Multi-stage events read
# desc + choices from this; the top-level event title stays on _event_data.
var _current_node: Dictionary = {}
# The folio wash has immutable shader code. Materials remain per Event so mood
# uniforms stay independent, while the compiled program is shared across visits.
static var _horizontal_gradient_shader_cache: Shader = null

var _selected_choice_for_result: Dictionary = {}
var _choice_commit_busy: bool = false
var _art_reaction_tween: Tween = null


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	# No decorative corner frame here — over the fullscreen illustration the
	# purple hairline box reads as a stray line, not furniture. The vignette
	# and brightness layers still apply.
	GameTheme.add_atmosphere(self, "event", false)
	_pick_event()
	# Mood-matched score (after _pick_event so _event_data is live): bone and
	# ember events draw from the dread book, gilt and verdigris from the wry
	# one; unmooded events keep the full original trio.
	match String(_event_data.get("mood", "")):
		"bone", "ember":
			AudioBank.play_music_random(["event", "event_b", "event_dread"])
		"gilt", "verdigris":
			AudioBank.play_music_random(["event_c", "event_wry"])
		_:
			AudioBank.play_music_random(["event", "event_b", "event_c"])
	# Per-event ambience loop ("river", "carnival", "fire_crackle", ...).
	# AudioBank no-ops gracefully when the asset dir doesn't exist yet, and an
	# event WITHOUT the field stops whatever loop the previous scene left
	# running — either way the soundscape is this event's own.
	AudioBank.play_ambience(String(_event_data.get("ambience", "")))
	_ensure_stakes_ledger()
	_build_ui()
	GameTheme.make_settings_gear(self)
	# The decision is usable over the scene's lightweight forest plate before
	# the event painting is even requested. The async hydrator hot-swaps only
	# the background layers; it never rebuilds or disables the choice controls.
	_begin_event_art_hydration()
	# Adaptive supersample scope, same as Combat's: the gamble minigames animate
	# heavy procedural painters (wheel, scale, dice, board) that redraw at the
	# full requested render scale (up to 2x). Without a scope this screen had no
	# auto-relief when a machine couldn't sustain it — only Combat did. Triggers
	# only on sustained slowness and self-clears when this scene leaves the tree.
	var supersample := get_node_or_null("/root/Supersample")
	if supersample != null:
		supersample.begin_adaptive_scope(self)
	_maybe_coach_the_page()


## FIVE LAYOUTS, ONE LESSON. The choice controls live under a different parent
## per presentation (`_event_presentation_layout` picks between the folio and four
## presented dresses), and each builder names its own container — so the lesson
## asks for all five names and takes whichever one this page built. An
## `auto_effect` node builds no choices at all and is skipped: there is nothing to
## decide, and a panel saying "pick a line" over a page with no lines is worse
## than silence.
const COACH_CHOICE_HOSTS: Array[String] = [
	"ChoicesBox", "ChoiceDevices", "ChoiceContracts", "ChoiceSeals"]


func _maybe_coach_the_page() -> void:
	if not TutorialCoach.should_teach("event_choice"):
		return
	# The choice column content-fits a frame after ready and `_align_margin_line`
	# repositions on the second — measure after both.
	for _i in 3:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var targets: Array = []
	for host_name in COACH_CHOICE_HOSTS:
		# RECURSIVE, and `owned = false`: these containers are built in code and
		# parented several levels down inside the page's column, so they are
		# neither direct children nor owned by the scene — `get_node` would miss
		# every one of them and the lesson would silently never fire.
		var host := find_child(host_name, true, false)
		if host == null:
			continue
		for child in host.get_children():
			if child is Button or child is PanelContainer:
				targets.append(child)
		if not targets.is_empty():
			break
	if targets.is_empty():
		return
	TutorialCoach.teach(self, "event_choice", targets)


func _unhandled_input(event: InputEvent) -> void:
	# An event forces a decision, so Esc opens the pause/Settings overlay rather
	# than resolving a choice for the player.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	var supersample := get_node_or_null("/root/Supersample")
	if supersample != null:
		supersample.end_adaptive_scope(self)
	# Invalidate any coroutine still polling the worker request before releasing
	# our strong reference. A completed late request is ignored by its serial.
	_event_art_request_serial += 1
	_event_art_loading = false
	# The road's sounds stay on the road — never bleed a river loop into the map.
	AudioBank.stop_ambience()
	# Event paintings are fullscreen one-scene assets. Do not let the shared
	# threaded loader pin every visited event for the rest of the app session.
	CardArtAliases.release_texture_path(_event_image_path)
	_event_image = null


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
	# Guarded like the bridge path above. Once `unseen` is exhausted this fell
	# through to `gate_passing`, so every repeat re-appended and events_seen
	# became a multiset — any gate that COUNTS rather than tests membership
	# (and the seen_texts story threads) then read wrong.
	if not RunState.events_seen.has(_event_id):
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
		"choice_made":
			return RunState.has_event_choice(String(gate.get("flag", "")))
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
				# HEALTH_GREEN, not a hand-rolled green: the constant carries the
				# retune away from electric #40D959 that this literal undid.
				flash = GameTheme.HEALTH_GREEN if v > prev else Color(0.88, 0.40, 0.32)
			lbl.add_theme_color_override("font_color", flash)
			var back := create_tween()
			back.tween_interval(0.55)
			back.tween_callback(func():
				if is_instance_valid(lbl):
					lbl.add_theme_color_override("font_color", GameTheme.IVORY))
		_ledger_prev[key] = v


func _clear_ui() -> void:
	_ui_build_gen += 1
	_choice_commit_busy = false
	for child in get_children():
		if not (child.name in PRESERVE_NODES):
			# queue_free() retires at frame end. Hide and disarm the outgoing tree
			# now so a modal/result rebuild never presents both screens together.
			if child is CanvasItem:
				child.visible = false
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			child.queue_free()


## `owner` IS DELIBERATELY UNTYPED, and the body explains why: it asks
## `is_instance_valid(owner)`, i.e. it EXPECTS to be handed a node that may
## already be gone. A typed `owner: Node` defeats that check before the body can
## run — GDScript validates the argument's class at the call, a freed object has
## no class to report, and the call errors with "argument 2 (previously freed)
## is not a subclass of the expected argument class".
##
## It matters because every caller reaches here across a suspension: the picker
## drain is entered by `call_deferred` and then loops over `await`s, so the grid
## can be freed by `_clear_ui` between the call being queued and the guard being
## asked. That is the whole question this function exists to answer. Seen live as
## an intermittent error on the event picker's teardown — intermittent because it
## is a race, which is also why one clean run is not evidence it is gone.
func _event_ui_build_is_current(gen: int, owner) -> bool:
	return _ui_build_gen == gen and is_inside_tree() and owner != null \
		and is_instance_valid(owner) and (owner as Node).is_inside_tree()



func _build_ui() -> void:
	_clear_ui()

	# Always provide the left readability pool immediately. Until hydration
	# lands, the event.tscn forest plate remains visible beneath this layer.
	_ensure_event_overlay(_art_scrim_darkness_for_path(_event_image_path))
	if _event_image != null:
		_ensure_fullscreen_art(_event_image)
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

	# Ordinary events now choose a composition from EventDB.  Table/minigame
	# engines and untagged legacy events retain the folio below as a fallback.
	var presentation_layout := _event_presentation_layout()
	if presentation_layout != "folio":
		_build_presented_event(presentation_layout)
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
	GameTheme.deal_in(title)

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
	GameTheme.write_on(desc, 0.12)

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
	skip_btn.pressed.connect(_walk_on_event)
	add_child(skip_btn)

	_refresh_ledger()


# ── Data-driven ordinary-event compositions ───────────────────────────────

func _event_presentation_layout() -> String:
	var presentation: Dictionary = _event_data.get("presentation", {})
	var layout := String(presentation.get("layout", "folio"))
	if layout not in ["character", "confrontation", "location", "bargain", "ritual"]:
		return "folio"
	return layout


func _visible_event_choices() -> Array:
	var visible: Array = []
	for choice in _current_node.get("choices", []):
		if choice.has("blue") and not _event_gate_passes_dict(choice.blue):
			continue
		visible.append(choice)
	return visible


func _event_choice_parts(choice: Dictionary) -> Dictionary:
	var headline := ""
	var body := ""
	var effect := ""
	if choice.get("hidden", false):
		headline = "???"
		body = String(choice.get("tell", ""))
	else:
		var parts: PackedStringArray = String(choice.get("label", "")).split("\n\n", true, 1)
		headline = parts[0] if not parts.is_empty() else "Choose"
		if parts.size() > 1:
			body = parts[1].strip_edges().replace("\n", " ")
		effect = String(choice.get("desc", ""))
	return {
		"headline": _sub_campaign_tokens(headline),
		"body": _sub_campaign_tokens(body),
		"effect": _ink_outcome(_sub_campaign_tokens(effect)) if not effect.is_empty() else "",
	}


func _build_presented_event(layout: String) -> void:
	var old_overlay := get_node_or_null("EventOverlayLeft") as CanvasItem
	if old_overlay:
		old_overlay.visible = false

	var stage = EVENT_LAYOUT_STAGE.new()
	stage.name = "EventLayoutStage"
	add_child(stage)
	stage.configure(layout, _mood_title_ink())

	var title_rect := Rect2(80, 58, 650, 74)
	var desc_rect := Rect2(80, 148, 575, 230)
	var centered := false
	match layout:
		"character":
			# WIDTH 450, NOT 520, AND THE 70px IS THE STAKES LEDGER.
			# The ledger is anchored TOP_RIGHT at x 1370..1560 and is four rows
			# deep (y 40..176) — its last row, the deck count, hangs level with
			# this column's FIRST LINE OF PROSE. At 520 the copy ran to x≈1493 and
			# the deck numeral sits at 1489, so the description read
			# "...abandoned a field kitchen, but 11 [deck]" — the HUD spliced into
			# the middle of the sentence. Verified by shot, 2026-09-02.
			# The arithmetic is not a coincidence: 40 + 3 rows x 34 = 142, and this
			# desc used to start at 146. The column was authored against a
			# THREE-row ledger and the fourth row was added later, in another file,
			# with nothing comparing the two.
			title_rect = Rect2(1000, 58, 450, 72)
			desc_rect = Rect2(1000, 146, 450, 190)
		"location":
			title_rect = Rect2(300, 42, 1000, 76)
			desc_rect = Rect2(350, 116, 900, 116)
			centered = true
		"bargain":
			title_rect = Rect2(80, 52, 850, 76)
			desc_rect = Rect2(80, 140, 830, 138)
		"ritual":
			title_rect = Rect2(300, 40, 1000, 76)
			desc_rect = Rect2(400, 116, 800, 118)
			centered = true

	var title_copy := _sub_campaign_tokens(String(_event_data.get("name", "Event")))
	if centered:
		title_copy = "[center]" + title_copy + "[/center]"
	var title := _make_event_title(title_copy)
	_place_event_control(title, title_rect)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var desc_copy := _illuminate_desc(_sub_campaign_tokens(String(_current_node.get("desc", ""))))
	if centered:
		desc_copy = "[center]" + desc_copy + "[/center]"
	var desc := _make_event_desc(desc_copy)
	_place_event_control(desc, desc_rect)
	add_child(desc)
	GameTheme.write_on(desc, 0.10)
	# The head ink band used to be a guessed constant while the copy rect ran
	# 50px past it, so a three-line paragraph printed its last line below the
	# band on the lit painting with the seam running between lines. Report the
	# copy's real bottom once it has laid out and let the pool cut itself to fit.
	_report_copy_extent(stage, desc, desc_rect)

	if layout == "character":
		_add_character_speaker_plate()
	_add_template_whisper(layout)
	var choices := _visible_event_choices()
	match layout:
		"character":
			_build_character_choices(choices)
		"bargain":
			_build_bargain_choices(choices)
		"ritual":
			_build_ritual_choices(choices)
		_:
			_build_template_choice_row(layout, choices)

	var skip_btn := _make_walk_on_button()
	skip_btn.pressed.connect(_walk_on_event)
	add_child(skip_btn)
	_refresh_ledger()


func _report_copy_extent(stage: Control, desc: RichTextLabel, rect: Rect2) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	await get_tree().process_frame
	if not is_instance_valid(stage) or not is_instance_valid(desc):
		return
	# `write_on` types the copy in, so the label's content height is only honest
	# once it holds the full string; the authored rect bottom is the safe floor.
	stage.copy_bottom = maxf(rect.position.y + desc.get_content_height(),
		rect.position.y + rect.size.y)


## The location rail's stops must mark the choices they belong to. Reported once
## the row has laid out, because the devices are centred in an HBoxContainer and
## their real widths depend on how many there are.
func _report_route_stops(stage: Control, row: Control) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	await get_tree().process_frame
	if not is_instance_valid(stage) or not is_instance_valid(row):
		return
	var stops := PackedFloat32Array()
	for child in row.get_children():
		var device := child as Control
		if device != null:
			stops.append(device.position.x + row.position.x + device.size.x * 0.5)
	stage.route_stops = stops


func _place_event_control(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


func _add_character_speaker_plate() -> void:
	var presentation: Dictionary = _event_data.get("presentation", {})
	var caption := String(presentation.get("speaker", "A ROAD ENCOUNTER")).strip_edges()
	if caption.is_empty():
		return
	var plate := Label.new()
	plate.name = "ConfrontationSpeaker"
	plate.text = caption.to_upper()
	plate.position = Vector2(92, 806)
	plate.size = Vector2(720, 32)
	plate.add_theme_font_size_override("font_size", 16)
	plate.add_theme_color_override("font_color", Color(0.86, 0.72, 0.45, 0.92))
	plate.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.90))
	plate.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_body:
		plate.add_theme_font_override("font", GameTheme.font_body)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)


func _availability_effect_text(effect_text: String, reason: String) -> String:
	if reason.is_empty():
		return effect_text
	var rendered := _ink_outcome(effect_text)
	if not rendered.is_empty():
		rendered += "\n"
	return rendered + "[color=#e06550]Unavailable: %s[/color]" % reason


func _mark_choice_unavailable(button: Button, reason: String) -> void:
	if reason.is_empty():
		return
	button.set_meta("unavailable_reason", reason)
	# Choice devices own their locked look (visible border, reason on its own
	# line). Anything else still takes the plain dim.
	if button.has_method("set_locked"):
		button.set_locked(reason)
		return
	button.disabled = true
	button.tooltip_text = reason
	button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	button.modulate = Color(0.58, 0.58, 0.58, 0.92)


func _make_presented_choice(choice: Dictionary, layout: String, ordinal: int = -1) -> Button:
	var parts := _event_choice_parts(choice)
	var headline := String(parts.headline)
	var unavailable := _choice_unavailable_reason(choice)
	# The reason is NOT folded into the effect string here — set_locked() gives it
	# its own line so it can't overflow a fixed-height tile. Blue's diamond is the
	# device's job too; only the roman numeral is composed here.
	var effect_text := String(parts.effect)
	if layout == "character" and not choice.has("blue") and ordinal > 0:
		var romans := ["I", "II", "III", "IV"]
		headline = "%s.  %s" % [romans[mini(ordinal, romans.size()) - 1], headline]
	var device = EVENT_CHOICE_DEVICE.new()
	device.configure(layout, headline, effect_text,
		String(parts.body), choice.has("blue"), _resolve_choice.bind(choice, device),
		_on_presented_choice_hover, _mood_title_ink())
	_mark_choice_unavailable(device, unavailable)
	return device

func _on_presented_choice_hover(text: String, active: bool) -> void:
	_set_whisper(text)
	for child in get_children():
		if child.has_method("set_attention"):
			child.set_attention(active)
	var art := get_node_or_null("EventArt") as TextureRect
	if art == null or UserSettings.reduce_motion or art.modulate.a < 0.98:
		return
	if _art_reaction_tween != null and _art_reaction_tween.is_running():
		_art_reaction_tween.kill()
	var target := Color(1.055, 1.035, 1.0, art.modulate.a) if active else Color(1, 1, 1, art.modulate.a)
	_art_reaction_tween = create_tween()
	_art_reaction_tween.tween_property(art, "modulate", target, 0.15 if active else 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)



func _build_character_choices(choices: Array) -> void:
	var column := VBoxContainer.new()
	column.name = "ChoiceDevices"
	column.position = Vector2(990, 356)
	column.size = Vector2(530, 410)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var count := maxi(1, choices.size())
	var device_height := 148.0 if count == 1 else (136.0 if count == 2 else
		(116.0 if count == 3 else 92.0))
	var next_ordinal := 1
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var ordinal := -1
		if not choice.has("blue"):
			ordinal = next_ordinal
			next_ordinal += 1
		var device := _make_presented_choice(choice, "character", ordinal)
		device.custom_minimum_size = Vector2(530, device_height)
		column.add_child(device)
		GameTheme.deal_in(device, 0.10 + float(i) * 0.055)


func _build_template_choice_row(layout: String, choices: Array) -> void:
	var row := HBoxContainer.new()
	row.name = "ChoiceDevices"
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 70
	row.offset_right = -70
	row.offset_top = -228
	row.offset_bottom = -88
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var separation := 16 if layout == "confrontation" else 22
	row.add_theme_constant_override("separation", separation)
	add_child(row)
	var count := maxi(1, choices.size())
	var preferred := 620.0 if count == 1 else (520.0 if count == 2 else
		(430.0 if count == 3 else 350.0))
	var device_width := minf(preferred,
		(1460.0 - float(count - 1) * float(separation)) / float(count))
	# Content is top-aligned now (so peers share a headline baseline), which left
	# the old centred heights with a dead band under every one-line answer.
	var device_height := 120.0 if count <= 2 else 112.0
	for i in choices.size():
		var device := _make_presented_choice(choices[i], layout)
		device.custom_minimum_size = Vector2(device_width, device_height)
		device.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_child(device)
		GameTheme.deal_in(device, 0.10 + float(i) * 0.055)
	if layout == "location":
		_report_route_stops(get_node_or_null("EventLayoutStage"), row)

func _build_bargain_choices(choices: Array) -> void:
	# Offers stack as ledger entries down one ruled column, sized to the line they
	# carry. The old shape gave two choices a 820x160 box each to hold a single
	# sentence, so the screen read as two empty crates with the whole right half
	# of the page dead. An account is a list; make it look like one.
	var grid := GridContainer.new()
	grid.name = "ChoiceContracts"
	grid.columns = 1
	var count := maxi(1, choices.size())
	var entry_height := 112.0 if count <= 2 else (100.0 if count == 3 else 92.0)
	var separation := 14
	var stack_height := float(count) * entry_height + float(count - 1) * float(separation)
	# Hang the stack from the ledger's ruled head rather than centring it in the
	# empty field — an account fills from the top.
	grid.position = Vector2(112, 352)
	grid.size = Vector2(830, stack_height)
	var stage := get_node_or_null("EventLayoutStage")
	if stage != null:
		stage.ledger_bottom = grid.position.y + stack_height + 12.0
	grid.add_theme_constant_override("v_separation", separation)
	add_child(grid)
	var device_size := Vector2(818, entry_height)
	for i in choices.size():
		var device := _make_presented_choice(choices[i], "bargain")
		device.custom_minimum_size = device_size
		grid.add_child(device)
		GameTheme.deal_in(device, 0.10 + float(i) * 0.06)

func _build_ritual_choices(choices: Array) -> void:
	var layer := Control.new()
	layer.name = "ChoiceSeals"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(layer)
	var count := maxi(1, choices.size())
	var preferred := 480.0 if count == 1 else (400.0 if count == 2 else
		(350.0 if count == 3 else 310.0))
	var width := minf(preferred,
		(1440.0 - float(count - 1) * 24.0) / float(count))
	var total := float(count) * width + float(count - 1) * 24.0
	var start_x := (1600.0 - total) * 0.5
	var tile_h := 122.0 if count <= 2 else 112.0
	for i in choices.size():
		var device := _make_presented_choice(choices[i], "ritual")
		var x := start_x + float(i) * (width + 24.0)
		# Seated on the seal's near rim rather than nudged by a flat 15px offset
		# — the old version read as three boxes that had failed to line up.
		device.position = Vector2(x, EVENT_LAYOUT_STAGE.seal_rim_y(x + width * 0.5, tile_h))
		device.size = Vector2(width, tile_h)
		layer.add_child(device)
		GameTheme.deal_in(device, 0.10 + float(i) * 0.06)

func _add_template_whisper(layout: String) -> void:
	var rect := Rect2(90, 588, 650, 42)
	match layout:
		"character":
			rect = Rect2(1000, 770, 520, 42)
		"location":
			rect = Rect2(300, 602, 1000, 42)
		"bargain":
			rect = Rect2(100, 296, 860, 42)
		"ritual":
			rect = Rect2(350, 584, 900, 42)
	var whisper := Label.new()
	whisper.name = "HoverWhisper"
	whisper.text = ""
	whisper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	whisper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER \
		if layout in ["location", "ritual"] else HORIZONTAL_ALIGNMENT_LEFT
	whisper.add_theme_font_size_override("font_size", 17)
	whisper.add_theme_color_override("font_color", Color(0.82, 0.78, 0.68, 0.94))
	whisper.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	whisper.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_body:
		whisper.add_theme_font_override("font", GameTheme.font_body)
	_place_event_control(whisper, rect)
	whisper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(whisper)
	_whisper = whisper

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

func _ensure_fullscreen_art(tex: Texture2D, fade_from_placeholder: bool = false) -> void:
	var bg := get_node_or_null("Background") as CanvasItem
	var art := get_node_or_null("EventArt") as TextureRect
	if art == null:
		art = TextureRect.new()
		art.name = "EventArt"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# COVERED fills the viewport, cropping overflow so the art bleeds to
		# every edge — no letterboxing on widescreens.
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		move_child(art, 1)  # behind Atmosphere so the vignette still tints corners
		# The plate breathes — the kit's 16s Ken Burns drift. Started once; the
		# art node survives result-screen rebuilds via PRESERVE_NODES so the
		# drift never resets.
		GameTheme.ken_burns(art, Vector2(800, 450))  # 1600x900 canvas center
	art.texture = tex
	_apply_event_art_focus(art)

	# The fallback remains underneath during the short hot-swap, avoiding a
	# black frame even when the painting finishes between rendered frames.
	if fade_from_placeholder and not UserSettings.reduce_motion and _event_art_visible:
		art.modulate.a = 0.0
		art.visible = true
		if bg:
			bg.visible = true
		var reveal := create_tween()
		reveal.tween_property(art, "modulate:a", 1.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		reveal.tween_callback(func() -> void:
			if is_instance_valid(bg):
				bg.visible = false)
	else:
		art.modulate.a = 1.0
		art.visible = _event_art_visible
		if bg:
			bg.visible = false

	# Left-column scrim: deep dark wash on the left, fading to clear across
	# the middle. Pools the text column in a quiet region while the right
	# ~half of the art stays fully visible. Replaces the older top+bottom
	# vertical pair — that one darkened bands the text rarely sat in (the
	# 3-choice stack landed mid-screen, in fully un-darkened art).
	_ensure_event_overlay(_art_scrim_darkness(tex))


func _apply_event_art_focus(art: TextureRect) -> void:
	# Optional per-painting crop metadata.  Enlarging the TextureRect slightly
	# gives us safe bleed to move its authored focal point toward the layout's
	# open art field without revealing an edge.
	var presentation: Dictionary = _event_data.get("presentation", {})
	if not presentation.has("focal_uv"):
		return
	var layout := String(presentation.get("layout", "folio"))
	var target := Vector2(0.34, 0.48) if layout == "character" else \
		(Vector2(0.72, 0.47) if layout in ["confrontation", "bargain"] else Vector2(0.50, 0.47))
	var focus: Vector2 = presentation.get("focal_uv", target)
	var zoom := maxf(1.0, float(presentation.get("zoom", 1.035)))
	var bleed := Vector2(800.0 * (zoom - 1.0), 450.0 * (zoom - 1.0))
	var shift := (target - focus) * Vector2(260.0, 150.0)
	# Never move farther than the extra bleed created by zoom; an aggressive
	# authored focal point must not expose a viewport edge.
	shift.x = clampf(shift.x, -bleed.x, bleed.x)
	shift.y = clampf(shift.y, -bleed.y, bleed.y)
	art.offset_left = -bleed.x + shift.x
	art.offset_right = bleed.x + shift.x
	art.offset_top = -bleed.y + shift.y
	art.offset_bottom = bleed.y + shift.y

func _ensure_event_overlay(darkness_left: float) -> void:
	var scrim := get_node_or_null("EventOverlayLeft") as ColorRect
	# Presented layouts paint their own local ink pools. Avoid allocating and
	# compiling a full-screen folio wash merely to keep it hidden on those pages.
	if not _wants_left_scrim():
		if scrim != null:
			scrim.visible = false
		return
	if scrim == null:
		scrim = _make_horizontal_gradient_overlay(darkness_left, 0.0)
		scrim.name = "EventOverlayLeft"
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(scrim)
		_move_after_atmosphere(scrim)
	else:
		var mat := scrim.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("darkness_left", darkness_left)
	scrim.visible = _event_art_visible


## This wash pools ink down the LEFT and pools it deeper at the bottom-left and
## top-left — a shape cut for the folio ladder, whose title and choices live
## exactly there. A presented layout draws its own ink where ITS copy sits, so
## on those the folio wash lands on the painting instead of the text: it dimmed
## the portrait on `character` (whose copy is on the right), and double-darkened
## `bargain`/`confrontation`, which already lay their own slab over the left.
##
## `_build_presented_event` tries to switch it off, but it runs BEFORE the scrim
## exists — `_ready` calls `_build_ui()` first and `_begin_event_art_hydration()`
## (which creates the scrim) second, so that hide was a no-op on first build and
## every presented event shipped with the folio wash on top of it.
func _wants_left_scrim() -> bool:
	return _event_presentation_layout() == "folio"


## How deep the left text scrim must run for this painting. Values are scanned
## offline into ART_SCRIM_DARKNESS so scene entry performs no texture readback.
func _art_scrim_darkness(tex: Texture2D) -> float:
	if tex == null:
		return _art_scrim_darkness_for_path(_event_image_path)
	var path := tex.resource_path
	if path == "":
		path = _event_image_path
	return _art_scrim_darkness_for_path(path)


func _art_scrim_darkness_for_path(path: String) -> float:
	const BASE := 0.62
	return float(ART_SCRIM_DARKNESS.get(path, BASE))


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
	if _horizontal_gradient_shader_cache == null:
		_horizontal_gradient_shader_cache = Shader.new()
		_horizontal_gradient_shader_cache.code = """
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
	mat.shader = _horizontal_gradient_shader_cache
	mat.set_shader_parameter("darkness_left", darkness_left)
	mat.set_shader_parameter("darkness_right", darkness_right)
	var ink := _mood_shadow_ink()
	mat.set_shader_parameter("shadow_ink", Vector3(ink.r, ink.g, ink.b))
	rect.material = mat
	return rect


func _set_event_art_visible(v: bool) -> void:
	_event_art_visible = v
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
	var unavailable := _choice_unavailable_reason(choice)
	effect_text = _availability_effect_text(effect_text, unavailable)
	var button := _make_frameless_choice(headline_text, effect_text, body_text, height,
			Callable(), choice.has("blue"), ordinal)
	button.pressed.connect(_resolve_choice.bind(choice, button))
	_mark_choice_unavailable(button, unavailable)
	return button


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
# Sized 20, not 16. The gold glyph is the CoinProp mint (see GameTheme's
# `gold_mint` note) and its crowned profile only begins to resolve at ~20px —
# below that the stamp mushes to a dark smudge and the coin reads as a plain
# disc. The rest of the row moves with it: they are one set and a 20px coin
# beside a 16px heart reads as a mistake. 20 also sits right against the 18px
# outcome text these open.
const GLYPH_GOLD := "[img=20]res://assets/icons/map/hud_gold_coin.png[/img] "
const GLYPH_HP := "[img=20]res://assets/icons/map/hud_heart_painted.png[/img] "
# The engraved skull, not the flat one from the pre-art icon set — this glyph
# sits inline in result prose beside gilt text, where a solid primitive reads
# as a missing sprite at 19px.
const GLYPH_CURSE := "[img=19]res://assets/icons/game-icons/horned-skull.svg[/img] "
const GLYPH_POTION := "[img=20]res://assets/icons/map/hud_potion_painted.png[/img] "
const GLYPH_RELIC := "[img=20]res://assets/icons/map/hud_relic.png[/img] "
const GLYPH_CARD := "[img=20]res://assets/icons/map/hud_deck.png[/img] "
const GLYPH_COMMAND := "[img=20]res://assets/icons/stats/cost_runestone.png[/img] "


## Words that open a discrete stake rather than continue a prose clause.
## No "sharpen" here: it never OPENS a stake in the pool, it only ever trails as
## prose ("returns to your deck, sharpened"), where a middot reads wrong.
const TERM_VERBS := ["heal", "gain", "remove", "transform", "eat", "give", "add",
	"free", "upgrade", "forge", "lose", "pay", "bury", "purge"]
## The house separator for discrete contract terms — the same middot the card
## faces use for "{contract} · {EXHAUST}".
const OUTCOME_SEP := "[color=#7c6a49]  ·  [/color]"


## True when a comma-separated piece is a stake of the deal, not the tail of a
## sentence. "+1 Curse" and "remove 2 chosen cards" are terms; "kept properly"
## and "then a relic" are prose and keep their comma.
func _is_discrete_term(seg: String) -> bool:
	var lower := seg.strip_edges().to_lower()
	if lower.begins_with("+") or lower.begins_with("-"):
		return true
	for verb in TERM_VERBS:
		if lower.begins_with(verb):
			return true
	return false


## Split one clause on term-separating commas ONLY. Two commas are never
## boundaries: those inside parentheses ("(2/5, Last Stand)" is one creature,
## not two stakes) and any comma past an em dash (everything after the dash is
## flavor, so "grief, kept properly, is a kind of armor" stays one breath).
## Returns [segments, untouched_tail].
func _split_outcome_terms(clause: String) -> Array:
	var dash := clause.find("—")
	var head := clause if dash < 0 else clause.substr(0, dash)
	var tail := "" if dash < 0 else clause.substr(dash)
	var segs: Array = []
	var buf := ""
	var depth := 0
	var i := 0
	while i < head.length():
		var c := head[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth = maxi(0, depth - 1)
		if depth == 0 and c == "," and i + 1 < head.length() and head[i + 1] == " ":
			segs.append(buf)
			buf = ""
			i += 2
			continue
		buf += c
		i += 1
	segs.append(buf)
	return [segs, tail]


## Stakes should read as countable terms, not one run-on string. "+55 gold, +1
## Curse" is two different things happening to the player and the comma made
## them blur; the middot separates them at a glance while prose keeps its commas.
func _ink_outcome(text: String) -> String:
	if text.find("[") >= 0:
		return text
	var big_parts: Array = []
	for half in text.split("; "):
		var split_result := _split_outcome_terms(String(half))
		var segs: Array = split_result[0]
		var tail := String(split_result[1])
		var out := ""
		for i in segs.size():
			var seg := String(segs[i]).strip_edges()
			if seg.is_empty():
				continue
			if out.is_empty():
				out = _ink_segment(seg)
			elif _is_discrete_term(seg):
				out += OUTCOME_SEP + _ink_segment(seg)
			else:
				out += ", " + _ink_segment(seg)
		# strip_edges() above ate the space the head carried before the em dash;
		# put it back or the flavor welds onto the last term ("for free— the river").
		if not tail.is_empty() and not out.is_empty():
			out += " "
		big_parts.append(out + tail)
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


const CHOICE_CONTENT_META := &"_event_choice_content"
const CHOICE_SETTLE_BUSY_META := &"_event_choice_settle_busy"
const CHOICE_READY_META := &"_event_choice_ready"


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
	btn.set_meta(CHOICE_CONTENT_META, vbox)

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
		if btn.disabled:
			return
		gem.modulate = gem_hot
		headline.add_theme_color_override("font_color", head_hot)
		if whisper_text != "":
			_set_whisper(whisper_text)
		slide_to.call(36.0, -12.0, 1.0, 168.0)
	)
	btn.mouse_exited.connect(func() -> void:
		if btn.disabled:
			return
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
		if not is_instance_valid(btn):
			return
		var ladder := btn.get_parent()
		if not (ladder is VBoxContainer):
			return
		btn.modulate.a = 0.0
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.set_meta(CHOICE_READY_META, false)
		ladder.set_meta(CHOICE_READY_META, false)
		if not bool(ladder.get_meta(CHOICE_SETTLE_BUSY_META, false)):
			ladder.set_meta(CHOICE_SETTLE_BUSY_META, true)
			call_deferred("_settle_choice_ladder", ladder)
	)

	# Deal the ladder in: entries fade in top-to-bottom with a small stagger
	# whenever they land in a choices column (any VBox — the main screen and
	# the engine screens both). Result-screen buttons parented straight to the
	# root appear instantly. Fade only — position stays container-owned, so
	# the entrance can never fight the hover slide.

	return btn




func _settle_choice_ladder(ladder) -> void:
	# Wrapped outcome text only knows its real height after the container gives
	# it a width. Settle the complete sibling set while it is invisible, then
	# publish ink and input without any container-owned geometry still moving.
	if not is_instance_valid(ladder) or not (ladder is VBoxContainer):
		return
	var live_ladder := ladder as VBoxContainer
	await get_tree().process_frame
	if not is_instance_valid(live_ladder) or not live_ladder.is_inside_tree():
		return

	var buttons: Array[Button] = []
	for child in live_ladder.get_children():
		if child is Button and child.has_meta(CHOICE_CONTENT_META) \
				and not child.is_queued_for_deletion():
			var button := child as Button
			button.modulate.a = 0.0
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			buttons.append(button)
	if buttons.is_empty():
		live_ladder.set_meta(CHOICE_SETTLE_BUSY_META, false)
		return

	for _pass in range(3):
		var grew := false
		for button in buttons:
			if not is_instance_valid(button):
				continue
			var content = button.get_meta(CHOICE_CONTENT_META, null)
			if not is_instance_valid(content) or not (content is Control):
				continue
			var need: float = (content as Control).get_combined_minimum_size().y + 22.0
			if need > button.custom_minimum_size.y + 0.5:
				button.custom_minimum_size.y = need
				grew = true
		if not grew:
			break
		await get_tree().process_frame
		if not is_instance_valid(live_ladder) or not live_ladder.is_inside_tree():
			return

	live_ladder.set_meta(CHOICE_READY_META, true)
	for button in buttons:
		if is_instance_valid(button):
			button.set_meta(CHOICE_READY_META, true)
			button.mouse_filter = Control.MOUSE_FILTER_STOP
	live_ladder.set_meta(CHOICE_SETTLE_BUSY_META, false)

	# Fade only: the VBox keeps sole ownership of position and size. Reduced
	# motion and headless probes publish the complete settled ladder at once.
	if UserSettings.reduce_motion or DisplayServer.get_name() == "headless":
		for button in buttons:
			if is_instance_valid(button):
				button.modulate.a = 1.0
		return
	var tw := live_ladder.create_tween()
	tw.set_parallel(true)
	for i in range(buttons.size()):
		var button := buttons[i]
		if is_instance_valid(button):
			tw.tween_property(button, "modulate:a", 1.0, 0.24) \
				.set_delay(0.05 + float(i) * 0.07)

func _begin_event_art_hydration() -> void:
	if _event_image != null or _event_art_loading:
		return
	_event_image_path = _resolve_event_image_path()
	if _event_image_path == "":
		return
	# The calibrated wash can update from the path alone; no pixels need to be
	# decoded or read back while the worker is still preparing the painting.
	_ensure_event_overlay(_art_scrim_darkness_for_path(_event_image_path))
	_event_art_request_serial += 1
	var request_serial := _event_art_request_serial
	_event_art_loading = true
	_hydrate_event_art(_event_image_path, request_serial)


func _hydrate_event_art(path: String, request_serial: int) -> void:
	# Guarantee one interactive fallback frame even when ResourceLoader already
	# has the imported texture warm from an earlier visit.
	var tree := get_tree()
	if tree == null:
		_event_art_loading = false
		return
	await tree.process_frame
	if request_serial != _event_art_request_serial or not is_inside_tree():
		return
	var tex := await _load_event_image_threaded(path, request_serial)
	if request_serial != _event_art_request_serial or not is_inside_tree():
		CardArtAliases.release_texture_path(path)
		return
	_event_art_loading = false
	if tex == null:
		return
	_event_image = tex
	# Install background layers only. The live title, choices, follow-up, or
	# picker subtree is deliberately untouched. `_event_art_visible` is honored
	# so a picker that hid the painting during the request stays hidden.
	_ensure_fullscreen_art(tex, true)


func _resolve_event_image_path() -> String:
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
				return p
	return ""


func _load_event_image_threaded(path: String, request_serial: int) -> Texture2D:
	# Strictly worker-backed: unlike the former helper path, a rejected request
	# does not fall back to `load()` on the transition frame. The forest plate is
	# a complete fallback, so a failed painting is harmless and can remain lazy.
	var err := ResourceLoader.load_threaded_request(path, "Texture2D")
	var status := ResourceLoader.load_threaded_get_status(path)
	if err != OK and status != ResourceLoader.THREAD_LOAD_IN_PROGRESS \
			and status != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if request_serial != _event_art_request_serial or not is_inside_tree():
			return null
		var tree := get_tree()
		if tree == null:
			return null
		await tree.process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	return ResourceLoader.load_threaded_get(path) as Texture2D


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
	"grant_keyword_pick", "veteran_swap", "shell_game", "straw_game",
	"sack_game", "wheel_game",
	"tali_game", "field_game", "crown_game", "scale_game",
	"box_game", "deal_game",
]

func _choice_unavailable_reason(choice: Dictionary) -> String:
	var gold_cost := 0
	var hp_cost := 0
	var max_hp_cost := 0
	var potion_rewards := 0
	var effects: Array = choice.get("effects", [])
	for raw_effect in effects:
		if not (raw_effect is Dictionary):
			continue
		var effect: Dictionary = raw_effect
		var kind := String(effect.get("type", ""))
		var value := int(effect.get("value", 0))
		if kind == "gold" and value < 0:
			gold_cost += -value
		if effect.has("stake"):
			gold_cost += maxi(0, int(effect.get("stake", 0)))
		if kind == "pawn_buyback":
			gold_cost += maxi(0, int(effect.get("price", 0)))
		if kind == "damage":
			hp_cost += maxi(0, value)
		elif kind == "lose_max_hp":
			max_hp_cost += maxi(0, value)
		elif kind == "purge_curses":
			var purge_count := _removable_filtered_count("curse")
			if purge_count <= 0:
				return "No removable Curse in your deck."
			max_hp_cost += purge_count * maxi(0, int(effect.get("max_hp_per", 2)))
		elif kind in ["gain_potion", "gain_potion_random"]:
			potion_rewards += 1

	if gold_cost > RunState.gold:
		return "Need %d gold (you have %d)." % [gold_cost, RunState.gold]
	if hp_cost > 0 and RunState.hero_hp <= hp_cost:
		return "Need at least %d HP to pay this safely." % (hp_cost + 1)
	if max_hp_cost > 0 and RunState.hero_max_hp <= max_hp_cost:
		return "Need at least %d max HP to pay this." % (max_hp_cost + 1)
	if potion_rewards > 0:
		var open_slots := 0
		if not RunState.has_downside("no_potions"):
			open_slots = maxi(0, RunState.MAX_POTIONS - RunState.potions.size())
		if open_slots < potion_rewards:
			return "Need an empty potion slot." if potion_rewards == 1 \
				else "Need %d empty potion slots." % potion_rewards

	for raw_effect in effects:
		if raw_effect is Dictionary:
			var target_reason := _effect_target_unavailable_reason(raw_effect)
			if not target_reason.is_empty():
				return target_reason
	return ""


func _removable_filtered_count(filter: String) -> int:
	var matches := 0
	for card_id in RunState.deck:
		if _card_matches_filter(String(card_id), filter):
			matches += 1
	return mini(matches, maxi(0, RunState.deck.size() - 1))


func _effect_target_unavailable_reason(effect: Dictionary) -> String:
	var kind := String(effect.get("type", ""))
	match kind:
		"remove_choice", "remove_choice_multi":
			if RunState.deck.size() <= 1:
				return "No removable card in your deck."
		"remove_choice_filtered", "remove_choice_all_copies":
			if _removable_filtered_count(String(effect.get("filter", ""))) <= 0:
				return "No eligible card to remove."
		"copy_card":
			if RunState.deck.is_empty():
				return "No card to copy."
		"upgrade_choice", "upgrade_choice_multi":
			var can_upgrade := false
			for i in range(RunState.deck.size()):
				if not RunState.has_upgrade_path(i, "plus") \
						and CardDB.is_upgradeable(RunState.deck[i]):
					can_upgrade = true
					break
			if not can_upgrade:
				return "No eligible card to forge."
		"transform_choice":
			var can_transform := false
			for card_id in RunState.deck:
				if not CardDB.is_curse(String(card_id)):
					can_transform = true
					break
			if not can_transform:
				return "No eligible card to transform."
		"grant_keyword_pick":
			var keyword := String(effect.get("keyword", ""))
			var can_learn := false
			for i in range(RunState.deck.size()):
				var data: Dictionary = RunState.get_upgraded_card_data(i)
				if data.get("type", "") == "creature" \
						and not (data.get("keywords", []) as Array).has(keyword):
					can_learn = true
					break
			if keyword.is_empty() or not can_learn:
				return "No soldier can take this lesson."
		"relic_sacrifice_pick":
			var can_trade_relic := false
			for relic_id in RunState.relics:
				if RelicDB.get_relic(relic_id).get("tier", "starting") != "starting":
					can_trade_relic = true
					break
			if not can_trade_relic:
				return "No non-starting relic to trade."
		"sacrifice_pick":
			var can_sacrifice := RunState.deck.size() > 1
			if can_sacrifice:
				can_sacrifice = false
				for card_id in RunState.deck:
					if CardDB.get_card_data(card_id).get("type", "") == "creature":
						can_sacrifice = true
						break
			if not can_sacrifice:
				return "No creature can be sacrificed."
		"veteran_swap":
			var has_starter := false
			for card_id in RunState.deck:
				if not CardDB.is_curse(card_id) \
						and CardDB.get_card_data(card_id).get("rarity", "") == "starter":
					has_starter = true
					break
			if not has_starter:
				return "No starting card can be replaced."
	return ""


func _record_choice_history(choice: Dictionary) -> void:
	for flag in choice.get("record_choices", []):
		RunState.record_event_choice(String(flag))
	var single := String(choice.get("record_choice", ""))
	if not single.is_empty():
		RunState.record_event_choice(single)


func _record_effect_outcome(effect: Dictionary, key: String) -> void:
	var flag := String(effect.get(key, ""))
	if not flag.is_empty():
		RunState.record_event_choice(flag)


func _walk_on_event() -> void:
	if _choice_commit_busy:
		return
	_choice_commit_busy = true
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


## The decision stays legible for one short beat: the chosen docket answers,
## its alternatives recede in place, and only then does the result/picker own
## the page. Alpha/scale only — no container geometry changes during commit.
func _play_choice_commit(source: Control) -> void:
	if source == null or not is_instance_valid(source):
		return
	if source is BaseButton:
		(source as BaseButton).disabled = true
	GameTheme.claim_pop(source)
	var group := source.get_parent()
	if group != null:
		for sibling in group.get_children():
			if sibling == source or not (sibling is BaseButton):
				continue
			(sibling as BaseButton).disabled = true
			GameTheme.fade_exit(sibling as Control, 0.12)
	await get_tree().create_timer(0.12).timeout


func _resolve_choice(choice: Dictionary, source: Control = null) -> void:
	var unavailable := _choice_unavailable_reason(choice)
	if not unavailable.is_empty():
		_refresh_ledger(false)
		return
	if _choice_commit_busy:
		return
	_choice_commit_busy = true
	var animate_commit := source != null and is_instance_valid(source) \
		and DisplayServer.get_name() != "headless" \
		and not (UserSettings != null and UserSettings.reduce_motion)
	if animate_commit:
		await _play_choice_commit(source)
		if not is_inside_tree():
			return
	# Keep the physical decision so the result page can stamp the same writ,
	# road marker, contract, or vow instead of replacing it with generic copy.
	_selected_choice_for_result = choice.duplicate(true)
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
		_record_choice_history(choice)
		_current_node = follow_up
		_build_ui()
		return

	# Start interactive copy picker if any copy_card effects exist.
	if copy_count > 0:
		_start_copy_mode(copy_count, result_text.strip_edges())
		_record_choice_history(choice)
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
		_record_choice_history(choice)
		return

	_record_choice_history(choice)
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
				# Fixed prices are all-or-nothing. The choice preflight protects
				# normal play; the guard below also protects direct/test callers.
				var price: int = -int(effect.value)
				if RunState.gold < price:
					return "Could not pay %d gold." % price
				RunState.gold -= price  # losses bypass ectoplasm
				_sting("coin", -6.0)
				return "Paid %d gold." % price
		"remove_cards":
			var count = effect.value
			# The game picks at random here, so naming the casualties is the whole
			# job — "Removed one card." told the player nothing they could act on.
			var struck: PackedStringArray = []
			for i in range(count):
				if RunState.deck.size() > 1:
					var idx = randi() % RunState.deck.size()
					var gone_r: Dictionary = RunState.get_upgraded_card_data(idx).duplicate(true)
					RunState.remove_card_at(idx)
					_result_lost.append(gone_r)
					struck.append(String(gone_r.get("name", "a card")))
			if struck.is_empty():
				return "Nothing could be spared."
			if struck.size() == 1:
				return "%s is struck from the roll." % struck[0]
			return "%s are struck from the roll." % ", ".join(struck)
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
			var choices = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
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
				# The GAME chose the card here, so showing both halves matters
				# more than anywhere else — otherwise the player is handed a
				# finished card and no idea which of theirs it used to be.
				var before_rand := _note_card_change(idx)
				RunState.upgrade_card(idx, "plus")
				_seal_card_change(before_rand, idx)
				_sting("card_play")
				return "Forged a card!"
			return "No cards to forge."
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
				return "You do not have enough gold for that bet."
			RunState.gold -= stake
			_result_suspense = true
			if randi() % 2 == 0:
				RunState.gain_gold(payout)
				_sting("coin")
				return "Won %d gold." % payout
			_sting("hit_hero", -6.0)
			return "Lost %d gold." % stake
		"wager_relic_or_curse":
			# The face-down red card: a pure coin flip, no stake. Heads is a
			# relic; tails is `curses` curses. EV ~ neutral — the draw is the
			# whole point.
			var n_curse: int = int(effect.get("curses", 2))
			_result_suspense = true
			if randi() % 2 == 0:
				var won = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
				if won.size() > 0:
					RunState.add_relic(won[0])
					_result_relics.append(won[0])
					_sting("card_play")
					return "Gained relic: %s." % RelicDB.get_relic(won[0]).name
				return "Nothing happened."
			for _i in range(n_curse):
				var flip_curse := CardDB.random_curse_id()
				RunState.add_card(flip_curse)
				_result_cards.append(CardDB.get_card_data(flip_curse))
			_sting("spell_cast", -4.0)
			return "Added 1 Curse to your deck." if n_curse == 1 \
				else "Added %d Curses to your deck." % n_curse
		"gain_potion":
			if RunState.add_potion("healing"):
				return "Gained a Healing Potion."
			return "Your potion belt is already full."
		"sell_potion":
			# Blue option (Pawnbroker): she pays over shop odds for a bottle.
			if RunState.potions.is_empty():
				return "Your potion belt is empty."
			RunState.potions.pop_back()
			var price: int = int(effect.get("value", 65))
			RunState.gain_gold(price)
			return "Sold a potion for %d gold." % price
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
				return "You have nothing to buy back."
			var back_price: int = int(effect.get("price", 60))
			if RunState.gold < back_price:
				return "You do not have enough gold."
			var back_id := String(RunState.pawned_cards[0])
			RunState.pawned_cards.remove_at(0)
			if CardDB.get_card_data(back_id).is_empty():
				return "The shelf holds nothing of yours."
			RunState.gold -= back_price
			RunState.add_card(back_id)
			var back_idx: int = RunState.deck.size() - 1
			var before_pawn := _note_card_change(back_idx)
			if CardDB.is_upgradeable(back_id):
				RunState.upgrade_card(back_idx, "plus")
			_seal_card_change(before_pawn, back_idx)
			_sting("coin")
			return "%s was returned and forged." \
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
			# max HP. Validate the full price before removing anything; the deck
			# still keeps its universal one-card floor.
			var curse_idx: Array = []
			for ci in range(RunState.deck.size()):
				if CardDB.is_curse(RunState.deck[ci]):
					curse_idx.append(ci)
			if curse_idx.is_empty():
				return "You have no Curses to remove."
			var removable := mini(curse_idx.size(), maxi(0, RunState.deck.size() - 1))
			if removable <= 0:
				return "You cannot remove your last card."
			var hp_price: int = removable * int(effect.get("max_hp_per", 2))
			if RunState.hero_max_hp <= hp_price:
				return "You cannot pay %d max HP." % hp_price
			var purged := 0
			for ci in range(curse_idx.size() - 1, -1, -1):
				if purged >= removable:
					break
				RunState.remove_card_at(curse_idx[ci])
				purged += 1
			RunState.hero_max_hp -= hp_price
			RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)
			return "Removed 1 Curse. Lost %d max HP." % hp_price \
				if purged == 1 else \
				"Removed %d Curses. Lost %d max HP." % [purged, hp_price]
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
			var fallback = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
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
		"shell_game":
			_start_shell_game(effect)
			return ""
		"straw_game":
			_start_straw_game(effect)
			return ""
		"sack_game":
			_start_sack_game(effect)
			return ""
		"wheel_game":
			_start_wheel_game(effect)
			return ""
		"tali_game":
			_start_tali_game(effect)
			return ""
		"field_game":
			_start_field_game(effect)
			return ""
		"crown_game":
			_start_crown_game(effect)
			return ""
		"scale_game":
			_start_scale_game(effect)
			return ""
		"box_game":
			_start_box_game(effect)
			return ""
		"deal_game":
			_start_deal_game(effect)
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
			_result_lots = true
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


# ── The prize table (2026-07-29) ──────────────────────────────────────────
# THE ONE FUNNEL every minigame resolver pays through. Before this the table
# could only push coins across it: 15 of 17 resolvers had no wire but
# `RunState.gain_gold(<int>)`, and the gambles carry ~40% of the pool's
# branches. Two general arms already existed and each was read at exactly ONE
# site — `win_effects`/`lose_effects` (the straw game) and `bank_relic` (the
# dice run). Both are generalised HERE rather than copy-pasted fifteen times.
#
# `win_effects` / `lose_effects` on a game's config REPLACE that game's
# hardcoded coin payout; the array runs through the normal effect applier, so
# anything an event choice can pay, a game can now pay. With neither key
# present the gold path runs exactly as before, so every untouched event is
# unchanged.
#
# Honored by every surviving resolver, win AND lose side: dice_run,
# shell_game, straw_game, sack_game, wheel_game, tali_game, field_game,
# crown_game, scale_game, box_game, deal_game. On a pot game the BANK button
# pays the tier it stopped on, so gate a terminal prize behind `win_effects_at`
# or `bank_relic_at` — a bare `win_effects` would pay in full at any stop.
#
# Returns the receipt to fold into the resolver's result line (through
# `_combine_lines`) — "" on the gold path, because the caller's own win_text
# already reports the coins.
func _gamble_pay(cfg: Dictionary, win: bool, gold: int,
		coin_sfx: String = "coin") -> String:
	var key := "win_effects" if win else "lose_effects"
	# Pot games: `win_effects_at` is an optional floor so an early stop cannot
	# claim the terminal prize. It reads the pot/tier actually stopped on — the
	# same number `bank_relic_at` reads, so a game's two prize arms gate alike.
	# Under the floor, the pot pays in coin exactly as it always did.
	var gated: bool = win and gold < int(cfg.get("win_effects_at", 0))
	if gated or not cfg.has(key):
		if gold > 0:
			RunState.gain_gold(gold)
			if coin_sfx != "":
				_sting(coin_sfx)
			# A GATED pot reports its own coin: that game's win_text has to read
			# for BOTH branches, so it cannot name a payout itself. Ungated games
			# keep returning "" — their win_text already prints the number.
			if gated:
				return "Gained %d gold." % gold
		return ""
	# A picker prize (grant_keyword_pick / upgrade_choice / transform_choice /
	# remove_choice…) OWNS the screen, and the resolver's trailing _show_result
	# would clobber it — the same one-modal-per-choice constraint _resolve_choice
	# obeys. So the modal is HELD here and launched by _show_result at the exact
	# beat the result page would have appeared; the receipt rides into the
	# picker's own result page through _pending_pre_text. At most one, as always.
	var plain: Array = []
	for e in cfg.get(key, []):
		if e is Dictionary and String(e.get("type", "")) in MODAL_EFFECTS \
				and _gamble_pending_modal.is_empty():
			_gamble_pending_modal = e
		else:
			plain.append(e)
	return _apply_effect_list(plain)


## Would a win of this size still pay in COIN? `win_effects` REPLACES the coin
## payout (see _gamble_pay), so a game whose config carries one must not print
## a gold figure on its own action rows — the Strongbox advertised "Current
## reward: 138 gold" while paying a forge and no coin at all, and the Scale
## advertised a pay it never made. Mirrors _gamble_pay's own gate exactly.
func _gamble_pays_coin(cfg: Dictionary, gold: int) -> bool:
	if not cfg.has("win_effects"):
		return true
	return gold < int(cfg.get("win_effects_at", 0))


# The terminal prize on a push-your-luck pot: stop holding at least N and the
# table's own relic leaves with the gold. The dice-run arm, generalised to the
# four pot games that escalated toward nothing (crown / deal / field / sack).
# Event relics are tier "event" — granted BY NAME, never rolled into a pool.
# Returns the granted relic id, or "" when nothing was granted; the CALLER
# owns the wording so each game's seen_texts overrides still apply.
## A picker prize stashed by _gamble_pay, launched by _show_result. Empty
## otherwise. Never holds more than one — see the constraint on MODAL_EFFECTS.
var _gamble_pending_modal: Dictionary = {}


func _gamble_bank_relic(cfg: Dictionary, pot: int) -> String:
	var rid := String(cfg.get("bank_relic", ""))
	if rid == "" or pot < int(cfg.get("bank_relic_at", 0)):
		return ""
	if RunState.relics.has(rid) or RelicDB.get_relic(rid).is_empty():
		return ""
	RunState.add_relic(rid)
	_result_relics.append(rid)
	_sting("card_play")
	return rid


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
# CHANGED cards, shown as a BEFORE → AFTER pair (2026-07-28). Every path that
# reshapes a card you already own — forge, transform, a keyword taught, a pawned
# card bought back — used to print only the finished article, or in a couple of
# cases only a sentence. The player could not see what the road had actually done
# to their soldier. Each entry: {"before": Dictionary, "after": Dictionary}.
# Push via _note_card_change(), which snapshots BEFORE mutating RunState.
var _result_pairs: Array = []
# Cards STRUCK FROM THE ROLL — removals. Rendered greyed and crossed. Removal was
# the one payoff class that showed nothing at all: "Removed one card." and no
# indication of which, even when the game had chosen at random.
var _result_lost: Array = []
# The picker tile the player last clicked, and a latch for the handlers that
# AWAIT a beat before moving on. The before→after pair above is the RESULT
# page's account of a change; these let the change also land on the card the
# player actually clicked, at the moment they click it.
var _last_pick_tile: Control = null
var _picker_busy: bool = false
# Picker grids populate across rendered frames. A rebuild advances this token so
# an old cache coroutine cannot append cards to a page the player already left.
var _ui_build_gen: int = 0
const PICKER_JOBS_META := &"_event_picker_jobs"
const PICKER_DRAIN_META := &"_event_picker_drain_busy"
const RESULT_CARD_JOBS_META := &"_event_result_card_jobs"
const RESULT_AUX_META := &"_event_result_aux"
const RESULT_STARTED_META := &"_event_result_started_usec"
const RESULT_HYDRATED_META := &"_event_result_hydrated"
const RESULT_READY_META := &"_event_result_ready"


# Set by gamble effects (roll_table, coin calls): the result page holds blank
# for a breath before the ink lands — the pause IS the dice rolling.
var _result_suspense: bool = false
# roll_table additionally: the commit resolves as a DRAWN LOT — an upturned
# helmet of folded slips plays over the result page while the ink waits.
var _result_lots: bool = false


func _sting(sound: String, volume_db: float = 0.0) -> void:
	AudioBank.play_sfx(sound, 0.06, volume_db)


func _show_result(text: String) -> void:
	# A minigame paid a PICKER prize (see `_gamble_pay`): open it here, at the
	# beat the result page would have appeared, and carry this receipt into the
	# picker's own result page. Cleared before dispatch so nothing re-enters.
	if not _gamble_pending_modal.is_empty():
		var modal := _gamble_pending_modal
		_gamble_pending_modal = {}
		_pending_pre_text = _combine_lines([_pending_pre_text, text]).strip_edges()
		_apply_effect(modal)
		return
	# Merge any stashed co-effect receipt (set when a modal picker was launched
	# alongside non-modal effects) ahead of the picker's own result line.
	var full := text.strip_edges()
	if _pending_pre_text != "":
		full = (_pending_pre_text + "\n" + full).strip_edges()
		_pending_pre_text = ""
	# A change pair or a casualty counts as a payoff even with no text: the cards
	# on the page ARE the result.
	var has_objects := not _result_cards.is_empty() or not _result_relics.is_empty() \
		or not _result_pairs.is_empty() or not _result_lost.is_empty()
	if full.is_empty() and not has_objects:
		# Never strand the player on a dead screen with nothing to click — if a
		# result resolves to no text, just walk back to the map.
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
		return
	var had_payoffs := has_objects
	_clear_ui()
	# Result keeps the event art behind it — same scene, same beat. The receipt
	# is written on the same page as the event (left column, drop cap, ivory
	# ink) instead of the old centered slab that broke the writ metaphor.
	_set_event_art_visible(true)

	var delay := _result_presentation_delay()
	var presentation_layout := _event_presentation_layout()
	if presentation_layout != "folio":
		_build_presented_result(full, presentation_layout, delay, had_payoffs)
		return

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

	GameTheme.write_on(desc, 0.10 + delay)

	_spawn_result_seal(full, delay, had_payoffs)
	_show_result_objects(delay)

	column.add_child(_make_frameless_choice("Continue", "", "Walk on.", 88,
			func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE)))

	_refresh_ledger()


func _result_presentation_delay() -> float:
	var delay := 0.0
	if _result_suspense and not UserSettings.reduce_motion:
		delay = 0.7
		if _result_lots:
			# Defer the physical lot until the selected composition has been built,
			# so the slip always lands above its stage rather than behind it.
			delay = 1.7
			call_deferred("_play_lots_draw")
	_result_suspense = false
	_result_lots = false
	return delay


func _build_presented_result(full: String, layout: String, delay: float,
		had_payoffs: bool) -> void:
	var old_overlay := get_node_or_null("EventOverlayLeft") as CanvasItem
	if old_overlay:
		old_overlay.visible = false
	var stage = EVENT_LAYOUT_STAGE.new()
	stage.name = "EventResultStage"
	add_child(stage)
	stage.configure(layout, _result_accent(full, had_payoffs))
	if layout == "character":
		_add_character_speaker_plate()

	var centered := layout in ["location", "ritual"]
	var title_rect := Rect2(80, 58, 650, 74)
	var desc_rect := Rect2(80, 154, 620, 300)
	var continue_rect := Rect2(640, 698, 320, 112)
	var selected_rect := Rect2(80, 642, 500, 126)
	# How far the receipt may rise toward a SHORT outcome line. Default -1 means
	# "don't move": most stages park the receipt on a painted band or arc
	# (confrontation's y=650 rail, ritual's y=634 foot), and floating it up out of
	# that band would read worse than the gap does. Only stages with genuinely
	# empty space between the prose and the receipt opt in — and the floor must
	# clear that stage's own furniture.
	var receipt_floor := -1.0
	match layout:
		"character":
			# Same 450 as the choice page, same reason — see the note there. The
			# result page restates every one of these rects rather than sharing
			# them, so a fix applied to one half leaves the other half broken.
			title_rect = Rect2(1000, 58, 450, 72)
			desc_rect = Rect2(1000, 146, 450, 250)
			selected_rect = Rect2(1000, 444, 520, 126)
			continue_rect = Rect2(1160, 628, 360, 104)
			# The conversation column is empty between the prose and the reply —
			# no horizontal furniture — so let the measured text drive it fully.
			receipt_floor = 232.0
		"location":
			title_rect = Rect2(300, 42, 1000, 76)
			desc_rect = Rect2(270, 126, 820 if had_payoffs else 1060, 230)
			continue_rect = Rect2(870, 704, 360, 108)
			selected_rect = Rect2(250, 664, 500, 126)
		"bargain":
			title_rect = Rect2(80, 52, 850, 76)
			desc_rect = Rect2(80, 150, 760, 280)
			continue_rect = Rect2(680, 698, 340, 112)
			selected_rect = Rect2(80, 548, 540, 142)
			receipt_floor = 352.0   # below the ledger head rules (y=314/322)
		"ritual":
			title_rect = Rect2(300, 40, 1000, 76)
			desc_rect = Rect2(300 if not had_payoffs else 160, 140,
				860 if had_payoffs else 1000, 250)
			continue_rect = Rect2(890, 704, 350, 112)
			selected_rect = Rect2(250, 654, 470, 132)

	var title_copy := _sub_campaign_tokens(String(_event_data.get("name", "Event")))
	if centered:
		title_copy = "[center]" + title_copy + "[/center]"
	var title := _make_event_title(title_copy)
	_place_event_control(title, title_rect)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var desc_copy := _illuminate_desc(_sub_campaign_tokens(full))
	if centered:
		desc_copy = "[center]" + desc_copy + "[/center]"
	var desc := _make_event_desc(desc_copy)
	_place_event_control(desc, desc_rect)
	add_child(desc)
	GameTheme.write_on(desc, 0.10 + delay)

	_spawn_result_seal(full, delay, had_payoffs)
	_show_result_objects(delay)
	var receipt := _add_resolved_choice(layout, full, selected_rect, delay)
	# Short outcomes are the common case — close the hole they leave, where the
	# stage has room for it.
	if receipt_floor > 0.0:
		_tuck_under_desc(desc, receipt, selected_rect.position.y, receipt_floor)

	var continue_btn = EVENT_CHOICE_DEVICE.new()
	continue_btn.configure(layout, "Continue", "", "Walk on.", false,
		func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE),
		Callable(), _result_accent(full, had_payoffs))
	continue_btn.position = continue_rect.position
	continue_btn.size = continue_rect.size
	add_child(continue_btn)
	GameTheme.deal_in(continue_btn, delay + 0.16)
	_refresh_ledger()

## Pull a result-page element up under the outcome prose once the label has
## measured itself. The page reserves a fixed 250-300px band for that prose, but
## most outcomes run one or two lines ("Gained 12 gold."), which stranded the
## receipt hundreds of pixels below the text it belongs to — the layout was cut
## for more words than it usually carries. Moves UP only: a genuinely long
## outcome keeps its authored position, and nothing rises above `min_y`.
func _tuck_under_desc(desc: RichTextLabel, ctrl: Control, authored_y: float,
		min_y: float, gap: float = 30.0) -> void:
	await get_tree().process_frame
	if desc == null or ctrl == null:
		return
	if not is_instance_valid(desc) or not is_instance_valid(ctrl):
		return
	var content := desc.get_content_height()
	if content <= 0.0:
		return
	ctrl.position.y = clampf(desc.position.y + content + gap, min_y, authored_y)


func _add_resolved_choice(layout: String, full: String, rect: Rect2,
		delay: float) -> Control:
	if _selected_choice_for_result.is_empty():
		return null
	var parts := _event_choice_parts(_selected_choice_for_result)
	var device = EVENT_CHOICE_DEVICE.new()
	device.configure(layout, String(parts.headline), String(parts.effect),
		String(parts.body), _selected_choice_for_result.has("blue"),
		Callable(), Callable(), _result_accent(full, false))
	device.position = rect.position
	device.size = rect.size
	add_child(device)
	device.mark_resolved(_result_stamp_word(layout, full), _result_is_bad(full))
	GameTheme.deal_in(device, delay + 0.10)
	return device


func _result_stamp_word(layout: String, full: String) -> String:
	if _result_is_bad(full):
		return {
			"character": "ANSWERED",
			"confrontation": "ANSWERED",
			"location": "PAID",
			"bargain": "COLLECTED",
			"ritual": "BROKEN",
		}.get(layout, "PAID")
	return {
		"character": "ANSWERED",
		"confrontation": "ANSWERED",
		"location": "TAKEN",
		"bargain": "SEALED",
		"ritual": "BOUND",
	}.get(layout, "DONE")

func _result_is_bad(text: String) -> bool:
	var lower := text.to_lower()
	for token in ["lose", "lost", "wound", "curse", "damage", "bust", "nothing",
			"empty", "dies", "dead"]:
		if lower.find(token) >= 0:
			return true
	return false


func _result_accent(text: String, had_payoffs: bool) -> Color:
	if _result_is_bad(text):
		return Color(1.0, 0.38, 0.24)
	var lower := text.to_lower()
	if had_payoffs or lower.find("gained") >= 0 or lower.find("gold") >= 0 \
			or lower.find("healed") >= 0:
		return GameTheme.KEYWORD_GOLD
	if lower.find("max command") >= 0 or lower.find("upgraded") >= 0 \
			or lower.find("forged") >= 0:
		return Color(0.70, 0.86, 1.0)
	return GameTheme.GILT_BRIGHT


func _spawn_result_seal(text: String, delay: float, had_payoffs: bool) -> void:
	# The kit's ring pulse (same device as the reroll flourish and the forge
	# shock ring), stamped once on the art half of the page as the outcome's
	# wax-seal beat.
	if UserSettings.reduce_motion:
		return
	var accent := _result_accent(text, had_payoffs)
	var center_x := 480.0 if _event_presentation_layout() == "character" else 1160.0
	var center := Vector2(center_x, 410 if had_payoffs else 360)
	GameTheme.ring_pulse(self, center,
		Color(accent.r, accent.g, accent.b, 0.58), 50.0, 270.0, 0.48,
		delay + 0.10)


## Snapshot a card's CURRENT folded data so it can be shown as the "before" half
## of a change pair. MUST be called before the RunState mutation — after it, the
## folded data already reads as the "after". Returns the deck index so call sites
## can chain: `var i := _note_card_change(idx)` … mutate … `_seal_card_change(i)`.
func _note_card_change(deck_index: int) -> Dictionary:
	if deck_index < 0 or deck_index >= RunState.deck.size():
		return {}
	return RunState.get_upgraded_card_data(deck_index).duplicate(true)


## Close the pair opened by _note_card_change, reading the post-mutation state.
func _seal_card_change(before: Dictionary, deck_index: int) -> void:
	if before.is_empty() or deck_index < 0 or deck_index >= RunState.deck.size():
		return
	_result_pairs.append({
		"before": before,
		"after": RunState.get_upgraded_card_data(deck_index).duplicate(true),
	})


func _begin_result_card_timeline() -> Control:
	## One stable full-page host owns every physical payoff object. Card backs and
	## final positions exist before the loader yields; cache completion only arms
	## one authored reveal and can never decide which sibling appears first.
	var timeline := Control.new()
	timeline.name = "ResultCardTimeline"
	timeline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.set_meta(RESULT_CARD_JOBS_META, [])
	timeline.set_meta(RESULT_AUX_META, [])
	timeline.set_meta(RESULT_STARTED_META, Time.get_ticks_usec())
	timeline.set_meta(RESULT_HYDRATED_META, false)
	timeline.set_meta(RESULT_READY_META, false)
	add_child(timeline)
	# Staging below is synchronous; the deferred drain sees the complete group.
	call_deferred("_drain_result_card_timeline", timeline, _ui_build_gen)
	return timeline




## Stand the staged payoffs on the art half of the result page: gained cards as
## real Card2Ds (dealt in with a small stagger), CHANGED cards as a before→after
## pair, removed cards struck through, relic writs beneath.
func _show_result_objects(delay: float = 0.0) -> void:
	var timeline := _begin_result_card_timeline()
	_show_result_change_pairs(delay, timeline)
	# A change pair (or a casualty list) owns the stage on its own — it is the
	# whole story of the beat, and no event both forges a card and hands you three
	# others. Falling through would stack the gained-card row on top of it.
	if not _result_pairs.is_empty() or not _result_lost.is_empty():
		_show_result_relic_writs(560.0, delay, timeline)
		_result_cards = []
		_result_relics = []
		_result_pairs = []
		_result_lost = []
		return
	# Cap stays 3. Four 225-wide cards plus separators come to 978px, which
	# centred on either stage anchor runs off the canvas (1649 on the 1600-wide
	# desktop layout, -9 on the character layout). The "…and N more" line below
	# is the honest overflow.
	var shown: Array = _result_cards.slice(0, mini(3, _result_cards.size()))
	var extra: int = _result_cards.size() - shown.size()
	var n: int = shown.size()
	var character_stage := _event_presentation_layout() == "character"
	var art_center_x := 480.0 if character_stage else 1160.0
	if n > 0:
		var card_w := 225
		var sep := 26
		var total_w: int = n * card_w + (n - 1) * sep
		var start_x: float = art_center_x - total_w / 2.0
		for i in range(n):
			_stage_card(shown[i], Vector2(start_x + i * (card_w + sep), 170),
				delay + 0.16 + i * 0.10, 1.0, timeline)
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
			timeline.add_child(more)
			_queue_result_aux(timeline, more, delay + 0.42)
	_show_result_relic_writs(520.0 if n > 0 else 260.0, delay, timeline)
	_result_cards = []
	_result_relics = []
	_result_pairs = []
	_result_lost = []


## Relic writs — name in gold over the rules line, printed on the page below (or
## in place of) the cards. Split out of _show_result_objects so the change-pair
## stage can reuse it.
func _show_result_relic_writs(start_y: float, delay: float,
		timeline: Control) -> void:
	var character_stage := _event_presentation_layout() == "character"
	var relic_x := 250.0 if character_stage else 940.0
	var ry: float = start_y
	for rid in _result_relics:
		var relic = RelicDB.get_relic(String(rid))
		if relic.is_empty():
			continue
		var v := VBoxContainer.new()
		v.position = Vector2(relic_x, ry)
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
		timeline.add_child(v)
		_queue_result_aux(timeline, v, delay + 0.30)
		ry += 96.0


## BEFORE → AFTER, the Slay-the-Spire beat. The card you handed over stands on
## the left, an arrow between, the card you got back on the right — plus a plain
## one-line summary of what actually changed, so the difference is readable
## without the player diffing two stat blocks by eye. Removals ride the same
## stage, greyed and struck, because "which card did I just lose?" is the same
## question. Lifted wholesale from the camp forge (Rest._add_preview_card /
## _add_arrow_glyph / _build_change_summary) so both screens say it the same way.
func _show_result_change_pairs(delay: float, timeline: Control) -> void:
	if _result_pairs.is_empty() and _result_lost.is_empty():
		return
	var character_stage := _event_presentation_layout() == "character"
	var center_x := 480.0 if character_stage else 1160.0
	var y := 150.0
	# Two pairs is the vertical budget: each row is 300px of card plus a caption,
	# and the relic writs still want the foot of the page. No shipped event
	# produces more than two changed cards in one resolution.
	for pair in _result_pairs.slice(0, mini(2, _result_pairs.size())):
		var before: Dictionary = pair.get("before", {})
		var after: Dictionary = pair.get("after", {})
		if before.is_empty() or after.is_empty():
			continue
		_stage_card(before, Vector2(center_x - 268.0, y), delay + 0.16, 0.82, timeline)
		_stage_arrow(Vector2(center_x - 26.0, y + 128.0), delay + 0.30, timeline)
		_stage_card(after, Vector2(center_x + 58.0, y), delay + 0.42, 1.0, timeline)
		var summary := _change_summary_text(before, after)
		if summary != "":
			# +312, not +268: the "after" card renders at full scale from y and is
			# 300 tall, so a caption at +268 sat on top of its own subject.
			_stage_caption(summary, Vector2(center_x - 268.0, y + 312.0), 496.0,
				GameTheme.KEYWORD_GOLD, delay + 0.52, timeline)
		y += 372.0
	for lost in _result_lost.slice(0, mini(2, _result_lost.size())):
		if typeof(lost) != TYPE_DICTIONARY or lost.is_empty():
			continue
		var node := _stage_card(lost, Vector2(center_x - 112.0, y),
			delay + 0.16, 0.82, timeline)
		if node != null:
			node.modulate = Color(0.62, 0.58, 0.54, 0.92)
		_stage_caption("REMOVED FROM YOUR DECK",
			Vector2(center_x - 210.0, y + 258.0), 420.0, GameTheme.DESC_DIM, delay + 0.30, timeline)
		y += 330.0


func _stage_card(data: Dictionary, pos: Vector2, delay: float,
		card_scale: float, timeline: Control) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.size = Vector2(225, 300)
	wrapper.position = pos
	wrapper.scale = Vector2(card_scale, card_scale)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.add_child(wrapper)
	var back := _make_picker_card_back(wrapper, timeline)
	var jobs: Array = timeline.get_meta(RESULT_CARD_JOBS_META, [])
	jobs.append({
		"data": data.duplicate(true),
		"wrapper": wrapper,
		"back": back,
		"delay": delay,
	})
	timeline.set_meta(RESULT_CARD_JOBS_META, jobs)
	return wrapper


func _queue_result_aux(timeline: Control, ctrl: Control, delay: float) -> void:
	if timeline == null or ctrl == null:
		return
	# Layout is final but ink stays withheld until every dependent card is ready.
	ctrl.modulate.a = 0.0
	var aux: Array = timeline.get_meta(RESULT_AUX_META, [])
	aux.append({"control": ctrl, "delay": delay})
	timeline.set_meta(RESULT_AUX_META, aux)


## Hydrate the complete result composition behind its already-seated backs, then
## hand presentation to one timeline. Cache completion never publishes a face.
func _drain_result_card_timeline(timeline, build_gen: int) -> void:
	if not _event_ui_build_is_current(build_gen, timeline):
		return
	var timeline_ref: WeakRef = weakref(timeline)
	var still_here := func() -> bool:
		var live := timeline_ref.get_ref() as Control
		return _event_ui_build_is_current(build_gen, live)

	# One honest painted frame: every final slot/back exists before any rich face.
	await get_tree().process_frame
	if not still_here.call():
		return
	var live_timeline := timeline_ref.get_ref() as Control
	var jobs: Array = live_timeline.get_meta(RESULT_CARD_JOBS_META, [])
	var datas: Array = []
	for job in jobs:
		datas.append((job as Dictionary).get("data", {}))
	var windowed := DisplayServer.get_name() != "headless"
	if windowed and not datas.is_empty():
		await CardTextureCache.bake_many(datas, still_here)
		if not still_here.call():
			return

	# Cached result faces are light enough to construct as one atomic publication
	# batch (at most four). They remain hidden under the full back set while their
	# live name/rules text receives its rendered-frame completion pass.
	var cards: Array[Control] = []
	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var wrapper: Control = job.get("wrapper") as Control
		var data: Dictionary = job.get("data", {})
		if wrapper == null or not is_instance_valid(wrapper):
			continue
		var card_node = CARD_SCENE.instantiate()
		card_node.card_id = String(data.get("id", ""))
		card_node.static_display = true
		card_node.card_data = data.duplicate(true)
		card_node.live_baked_mode = true
		card_node.defer_baked_rules_text = windowed
		card_node.visible = false
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, 0)
		cards.append(card_node)
		job["card"] = card_node
		jobs[i] = job
	live_timeline.set_meta(RESULT_CARD_JOBS_META, jobs)
	if windowed and not cards.is_empty():
		await RenderingServer.frame_post_draw
		if not still_here.call():
			return
		for card in cards:
			if is_instance_valid(card):
				card.complete_deferred_baked_rules()
		await RenderingServer.frame_post_draw
		if not still_here.call():
			return
	live_timeline = timeline_ref.get_ref() as Control
	live_timeline.set_meta(RESULT_HYDRATED_META, true)
	_release_result_card_timeline(live_timeline, jobs,
		live_timeline.get_meta(RESULT_AUX_META, []), build_gen)


func _release_result_card_timeline(timeline: Control, jobs: Array,
		aux: Array, build_gen: int) -> void:
	if not _event_ui_build_is_current(build_gen, timeline):
		return
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	var base_delay := INF
	for job in jobs:
		base_delay = minf(base_delay, float((job as Dictionary).get("delay", 0.0)))
	for item in aux:
		base_delay = minf(base_delay, float((item as Dictionary).get("delay", 0.0)))
	if base_delay == INF:
		base_delay = 0.0
	var started_usec := int(timeline.get_meta(
		RESULT_STARTED_META, Time.get_ticks_usec()))
	var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	# Suspense time doubles as useful preload time. If cold work overruns it, begin
	# immediately but retain the authored offsets for arrows/captions/relic ink.
	var gate := maxf(0.0, base_delay - elapsed)

	if snap:
		for job in jobs:
			var back := (job as Dictionary).get("back") as Control
			var card := (job as Dictionary).get("card") as Control
			if back != null and is_instance_valid(back):
				back.queue_free()
			if card != null and is_instance_valid(card):
				card.visible = true
				card.modulate.a = 1.0
				card.scale = Vector2.ONE
		for item in aux:
			var ctrl := (item as Dictionary).get("control") as Control
			if ctrl != null and is_instance_valid(ctrl):
				ctrl.modulate.a = 1.0
				ctrl.scale = Vector2.ONE
		timeline.set_meta(RESULT_READY_META, true)
		return

	# One coordinated turn: the whole logical card group publishes together. The
	# fixed backs make readiness visible without revealing cache completion order.
	if not jobs.is_empty():
		var sound_tw := timeline.create_tween()
		if gate > 0.0:
			sound_tw.tween_interval(gate)
		sound_tw.tween_callback(func():
			AudioBank.play_sfx("card_draw", 0.04, -6.0))
	for job in jobs:
		var back := (job as Dictionary).get("back") as Control
		var card := (job as Dictionary).get("card") as Control
		if card != null and is_instance_valid(card):
			card.visible = true
			card.modulate.a = 1.0
			Motion.flip_in(card, gate + Motion.time(0.13), 0.17)
		if back != null and is_instance_valid(back):
			var back_ref: WeakRef = weakref(back)
			var back_tw := timeline.create_tween()
			if gate > 0.0:
				back_tw.tween_interval(gate)
			back_tw.tween_callback(func():
				var live_back := back_ref.get_ref() as Control
				if live_back != null:
					Motion.flip_out(live_back, 0.13))

	var finish_at := gate + Motion.time(0.34)
	for item in aux:
		var ctrl := (item as Dictionary).get("control") as Control
		if ctrl == null or not is_instance_valid(ctrl):
			continue
		var at := gate + maxf(0.0,
			float((item as Dictionary).get("delay", base_delay)) - base_delay)
		GameTheme.deal_in(ctrl, at)
		finish_at = maxf(finish_at, at + 0.40)
	var timeline_ref: WeakRef = weakref(timeline)
	var ready_tw := timeline.create_tween()
	ready_tw.tween_interval(maxf(finish_at, 0.001))
	ready_tw.tween_callback(func():
		var live := timeline_ref.get_ref() as Control
		if live != null:
			live.set_meta(RESULT_READY_META, true))


## Result cards are already authored to deal in at staggered times. Use that
## hidden interval to bake and assemble each complete face, so the result text
## appears immediately and no click pays for two or three ornate trees at once.
func _hydrate_appraisal_card(wrapper: Control, data: Dictionary,
		back: Control, build_gen: int) -> void:
	var windowed := DisplayServer.get_name() != "headless"
	if windowed and not CardTextureCache.has(data):
		await CardTextureCache.bake(data)
		if not _event_ui_build_is_current(build_gen, wrapper):
			return
	if not _event_ui_build_is_current(build_gen, wrapper):
		return
	var card_node = CARD_SCENE.instantiate()
	card_node.card_id = String(data.get("id", ""))
	card_node.static_display = true
	card_node.card_data = data.duplicate(true)
	card_node.live_baked_mode = true
	card_node.defer_baked_rules_text = windowed
	card_node.visible = false
	wrapper.add_child(card_node)
	wrapper.move_child(card_node, 0)
	if windowed:
		await RenderingServer.frame_post_draw
		if not _event_ui_build_is_current(build_gen, wrapper):
			return
		card_node.complete_deferred_baked_rules()
		await RenderingServer.frame_post_draw
		if not _event_ui_build_is_current(build_gen, wrapper):
			return
	card_node.visible = true
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if snap:
		if back != null and is_instance_valid(back):
			back.queue_free()
	else:
		Motion.flip_out(back, 0.13)
		Motion.flip_in(card_node, Motion.time(0.13), 0.17)


func _stage_arrow(pos: Vector2, delay: float, timeline: Control) -> void:
	var arrow := GameTheme.make_label("→", 46, GameTheme.KEYWORD_GOLD)
	arrow.position = pos
	arrow.size = Vector2(56, 56)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.add_child(arrow)
	_queue_result_aux(timeline, arrow, delay)


func _stage_caption(text: String, pos: Vector2, width: float, col: Color,
		delay: float, timeline: Control) -> void:
	var lab := GameTheme.make_label(text, GameTheme.MIN_LABEL_SIZE, col)
	lab.position = pos
	lab.size = Vector2(width, 30)
	lab.custom_minimum_size = Vector2(width, 0)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lab.add_theme_constant_override("outline_size", 3)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.add_child(lab)
	_queue_result_aux(timeline, lab, delay)


## One plain line naming what changed between two folded card datas. Deliberately
## not a full diff — the two cards are on screen; this is the caption that stops
## the player hunting for the difference.
func _change_summary_text(before: Dictionary, after: Dictionary) -> String:
	var bits: PackedStringArray = []
	var b_name := String(before.get("name", ""))
	var a_name := String(after.get("name", ""))
	if b_name != a_name and not a_name.begins_with(b_name):
		return "%s became %s." % [b_name, a_name]
	var d_atk: int = int(after.get("atk", 0)) - int(before.get("atk", 0))
	var d_hp: int = int(after.get("hp", 0)) - int(before.get("hp", 0))
	var d_cost: int = int(after.get("cost", 0)) - int(before.get("cost", 0))
	if d_atk != 0 or d_hp != 0:
		bits.append("%+d/%+d" % [d_atk, d_hp])
	if d_cost != 0:
		bits.append("costs %d" % int(after.get("cost", 0)))
	var b_kw: Array = before.get("keywords", [])
	for kw in after.get("keywords", []):
		if kw not in b_kw:
			bits.append(String(KeywordEffects.KEYWORDS.get(kw, {}).get(
				"display", String(kw).capitalize())))
	if bits.is_empty():
		return "%s was reforged." % a_name
	return "%s — %s" % [a_name, ", ".join(bits)]


func _make_card_picker_grid(title_text: String, title_color: Color) -> Container:
	# Shared helper for card-picker screens (remove, copy, butcher).
	# Returns the GridContainer so callers can add card wrappers to it.
	# The event's painting stays under the picker (2026-07-04) — a deep scrim
	# keeps the cards readable, but the Sin-Eater's table and the Remount Fair
	# no longer collapse into the same black room the moment a picker opens.
	_clear_ui()
	_picker_busy = false  # a fresh picker re-arms the awaited-handler latch
	_last_pick_tile = null
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

	# `_add_card_to_grid` reserves 210x280 per tile, so six of them plus five
	# 16px gutters is 1340 — which also re-centres the block inside the 1440
	# viewport it used to sit left-flush in.
	var grid = GameTheme.make_picker_rank(6, 210.0, 16, 16)
	grid.name = "EventCardGrid"
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


func _add_card_to_grid(grid: Container, data: Dictionary, callback: Callable) -> void:
	# Reserve the final footprint synchronously. Callers enqueue an entire slate
	# in one stack frame, so every face-down writ is already seated before the
	# asynchronous texture/card work begins and the GridContainer never grows
	# underneath a visible face.
	if grid == null or not is_instance_valid(grid):
		return
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(210, 280)
	wrapper.pivot_offset = Vector2(105, 140)
	grid.add_child(wrapper)
	var back := _make_picker_card_back(wrapper, grid)
	var jobs: Array = grid.get_meta(PICKER_JOBS_META, [])
	jobs.append({
		"data": data,
		"callback": callback,
		"wrapper": wrapper,
		"back": back,
	})
	grid.set_meta(PICKER_JOBS_META, jobs)
	if bool(grid.get_meta(PICKER_DRAIN_META, false)):
		return
	grid.set_meta(PICKER_DRAIN_META, true)
	# Deferred, not immediate: every picker caller fills its loop synchronously.
	# This lets the drain see the whole offer and turn every completed face on the
	# same beat, even when all cache entries are already warm.
	call_deferred("_drain_card_grid", grid, _ui_build_gen)


func _make_picker_card_back(parent: Control,
		group: CanvasItem = null) -> TextureRect:
	var back := TextureRect.new()
	back.name = "LoadingWrit"
	back.texture = CARD_BACK_TEXTURE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, group)
	parent.add_child(back)
	return back


## `grid` untyped for the same reason the guard's `owner` is: this is entered by
## `call_deferred`, so the grid can be freed between the call being queued and
## the frame it runs on, and a typed parameter would error on the way IN instead
## of letting the first line of the loop decline the work.
func _drain_card_grid(grid, build_gen: int) -> void:
	var reveals: Array = []
	while _event_ui_build_is_current(build_gen, grid):
		var jobs: Array = grid.get_meta(PICKER_JOBS_META, [])
		if jobs.is_empty():
			break
		var job: Dictionary = jobs.pop_front()
		grid.set_meta(PICKER_JOBS_META, jobs)
		var data: Dictionary = job.data
		if DisplayServer.get_name() != "headless" and not CardTextureCache.has(data):
			await CardTextureCache.bake(data)
			if not _event_ui_build_is_current(build_gen, grid):
				return

		var wrapper: Control = job.wrapper
		var back: Control = job.back
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		card_node.defer_baked_rules_text = DisplayServer.get_name() != "headless"
		# Snap mode changes the reveal animation, never the group-ready contract.
		card_node.visible = false
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, 0)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.disabled = true
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_on_picker_tile_pressed.bind(
			wrapper, job.callback as Callable))
		# The kit's hover lift: the invisible catcher hovers, the card wrapper
		# lifts and pops above its overlapping grid neighbors.
		GameTheme.hover_lift(click_btn, 1.05, wrapper, true)
		wrapper.add_child(click_btn)
		reveals.append({"card": card_node, "back": back, "button": click_btn})

		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _event_ui_build_is_current(build_gen, grid):
				return
			card_node.complete_deferred_baked_rules()
			await RenderingServer.frame_post_draw
	if _event_ui_build_is_current(build_gen, grid):
		await _reveal_picker_card_group(reveals, build_gen, grid)
	if is_instance_valid(grid):
		grid.set_meta(PICKER_DRAIN_META, false)


func _reveal_picker_card_group(reveals: Array, build_gen: int,
		grid: Container) -> void:
	if reveals.is_empty():
		return
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not snap:
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for reveal in reveals:
			Motion.flip_out(reveal.back as Control, 0.13)
		await get_tree().create_timer(Motion.time(0.13)).timeout
		if not _event_ui_build_is_current(build_gen, grid):
			return
	for reveal in reveals:
		var back: Control = reveal.back
		var card: Control = reveal.card
		var button: Button = reveal.button
		if snap and is_instance_valid(back):
			back.queue_free()
		if is_instance_valid(card):
			card.visible = true
			if not snap:
				Motion.flip_in(card, 0.0, 0.16)
		if is_instance_valid(button):
			button.disabled = false


## Every picker tile goes through here so a handler can play a beat ON the card
## that was chosen — the callbacks are bound to a deck index, not to the tile.
## `_picker_busy` is claimed only by the handlers that await something; it is
## cleared whenever a fresh picker is built, so the multi-pick pickers (which
## rebuild their grid per pick) are untouched.
func _on_picker_tile_pressed(tile: Control, callback: Callable) -> void:
	if _picker_busy:
		return
	_last_pick_tile = tile
	callback.call()


## Re-bake the clicked tile from POST-mutation data. The picker grid is built
## before the change, so without this the stamp reads "+2 HP" across a card still
## printing its old numbers — the beat would be announcing something the card it
## lands on flatly contradicts. The click catcher is kept (it carries the tile's
## hover lift); only the writ underneath is swapped.
func _refresh_pick_tile(deck_index: int) -> void:
	if _last_pick_tile == null or not is_instance_valid(_last_pick_tile):
		return
	if deck_index < 0 or deck_index >= RunState.deck.size():
		return
	var tile := _last_pick_tile
	var build_gen := _ui_build_gen
	var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	# Keep the old face in place while the new cache key bakes; the mutation's
	# stamp only starts after the complete replacement has landed.
	if DisplayServer.get_name() != "headless" and not CardTextureCache.has(data):
		await CardTextureCache.bake(data)
		if not _event_ui_build_is_current(build_gen, tile) or _last_pick_tile != tile:
			return
	for child in tile.get_children():
		if child is Button:
			continue
		# remove THEN free — queue_free is deferred, so a plain queue_free would
		# leave the stale writ drawn under the new one for a frame.
		tile.remove_child(child)
		child.queue_free()
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	card_node.live_baked_mode = true
	card_node.defer_baked_rules_text = DisplayServer.get_name() != "headless"
	tile.add_child(card_node)
	tile.move_child(card_node, 0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _event_ui_build_is_current(build_gen, tile) or _last_pick_tile != tile:
			return
		card_node.complete_deferred_baked_rules()
		await RenderingServer.frame_post_draw


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
	var gone: Dictionary = RunState.get_upgraded_card_data(deck_index).duplicate(true)
	RunState.remove_card_at(deck_index)
	_result_lost.append(gone)
	_show_result("%s is struck from the roll." % gone.get("name", "The card"))


func _start_multi_remove_mode(count: int) -> void:
	var grid = _make_card_picker_grid("Choose a card to remove" if count == 1
		else "Choose %d cards to remove" % count, GameTheme.BLOOD_RED)

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
		_show_result("Removed one card." if _multi_remove_removed == 1
			else "Removed %d cards." % _multi_remove_removed)
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
			return "You have no starting cards to give."
	return "You have no valid cards."


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
	var grid = _make_card_picker_grid("Choose a card. Every copy will be removed.", GameTheme.KEYWORD_GOLD)
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
	_show_result("Removed %d copies of %s." % [removed, nm])


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
		_show_result("No keyword was selected.")
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
		_show_result("No creature can gain that keyword.")
		return
	var disp := String(KeywordEffects.KEYWORDS.get(kw, {}).get("display", kw.capitalize()))
	var grid = _make_card_picker_grid(
		String(effect.get("prompt", "Choose a creature to teach %s" % disp)),
		GameTheme.KEYWORD_GOLD)
	for i in eligible:
		_add_card_to_grid(grid, RunState.get_upgraded_card_data(i),
			_on_grant_keyword_pick.bind(i))


func _on_grant_keyword_pick(deck_index: int) -> void:
	if _picker_busy:
		return
	_picker_busy = true
	var kw := String(_grant_kw_effect.get("keyword", ""))
	var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	var before := _note_card_change(deck_index)
	RunState.apply_wayside_upgrade(deck_index, {"path": "grant_kw", "keyword": kw})
	var disp := String(KeywordEffects.KEYWORDS.get(kw, {}).get("display", kw.capitalize()))
	# Show the soldier either side of the lesson, so the new keyword chip is
	# something the player SEES arrive rather than a sentence they're told.
	_seal_card_change(before, deck_index)
	_sting("upgrade_confirm")
	# The pair above is the RESULT page's account of the change. Strike it on the
	# card that was actually clicked, first, while the slate is still on screen —
	# otherwise the lesson only ever happens on the next screen.
	await _refresh_pick_tile(deck_index)
	await GameTheme.writ_amend(self, _last_pick_tile, disp.to_upper(),
		GameTheme.KEYWORD_GOLD)
	if not is_inside_tree():
		return
	_show_result("%s permanently gained %s." \
		% [data.get("name", "The soldier"), disp])


# ── The Free Company's one-for-one muster (veteran_swap) ─────────────────
# Picker over unique STARTER card ids; choosing one removes up to two copies and
# enlists the same count of random uncommons — the deck keeps its size but
# keeps a named retinue intact if a future deck restores larger duplicate runs.
# Replacements are dealt without repeats while the uncommon pool lasts.

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
		_show_result("No starting cards are left to trade.")
		return
	var grid = _make_card_picker_grid(
		"Choose a starting card. Up to 2 copies will be removed and replaced.",
		GameTheme.KEYWORD_GOLD)
	for cid in unique_ids:
		_add_card_to_grid(grid, CardDB.get_card_data(cid),
			_on_veteran_swap_pick.bind(String(cid)))


func _on_veteran_swap_pick(card_id: String) -> void:
	var nm: String = CardDB.get_card_data(card_id).name
	var removed := 0
	for i in range(RunState.deck.size() - 1, -1, -1):
		if RunState.deck.size() <= 1 or removed >= 2:
			break
		if RunState.deck[i] == card_id:
			RunState.remove_card_at(i)
			removed += 1
	if removed == 0:
		_show_result("You cannot remove your last card.")
		return
	var pool: Array = CardDB.cards_of_rarity("uncommon")
	pool.shuffle()
	var names: Array = []
	for i in range(mini(removed, pool.size())):
		RunState.add_card(pool[i])
		names.append(CardDB.get_card_data(pool[i]).name)
		_result_cards.append(CardDB.get_card_data(pool[i]))
	_sting("card_play")
	_show_result("Removed %d copies of %s. Added: %s." \
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
		if not RunState.has_upgrade_path(i, "plus") \
				and CardDB.is_upgradeable(RunState.deck[i]):
			any_upgradeable = true
			break
	if not any_upgradeable:
		var msg := ""
		if _upgrade_choice_names.size() > 0:
			msg = "Forged: %s." % ", ".join(_upgrade_choice_names)
		else:
			msg = "Nothing left to forge."
		_upgrade_choice_remaining = 0
		_show_result(msg)
		return

	var suffix := ""
	if _upgrade_choice_remaining > 1:
		suffix = " (%d remaining)" % _upgrade_choice_remaining
	var grid = _make_card_picker_grid("Choose a card to forge" + suffix, GameTheme.KEYWORD_GOLD)
	for i in range(RunState.deck.size()):
		if RunState.has_upgrade_path(i, "plus") or not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_upgrade_choice_pick.bind(i))

func _on_upgrade_choice_pick(deck_index: int) -> void:
	if _picker_busy:
		return
	if deck_index < 0 or deck_index >= RunState.deck.size():
		return
	if RunState.has_upgrade_path(deck_index, "plus") \
		or not CardDB.is_upgradeable(RunState.deck[deck_index]):
		return
	_picker_busy = true
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	var before := _note_card_change(deck_index)
	RunState.upgrade_card(deck_index, "plus")
	_seal_card_change(before, deck_index)
	_sting("upgrade_confirm")
	# The forge lands on the card the player picked, not just in the sentence
	# afterwards. The stamp names the loudest single change — the full diff is
	# the result page's before→after pair.
	await _refresh_pick_tile(deck_index)
	await GameTheme.writ_amend(self, _last_pick_tile,
		_forge_stamp_text(before, RunState.get_upgraded_card_data(deck_index)),
		GameTheme.KEYWORD_GOLD)
	if not is_inside_tree():
		return
	_upgrade_choice_names.append(data.name)
	_upgrade_choice_remaining -= 1
	if _upgrade_choice_remaining <= 0:
		_show_result("Upgraded: %s." % ", ".join(_upgrade_choice_names))
	else:
		# Rebuilding the picker clears _picker_busy for the next pick.
		_start_upgrade_mode(_upgrade_choice_remaining)


## A SHORT delta for the forge stamp. It has to fit across a 210px card, so it
## names the loudest single change rather than the whole diff (which the result
## page's before→after pair already carries in full).
func _forge_stamp_text(before: Dictionary, after: Dictionary) -> String:
	if before.is_empty() or after.is_empty():
		return "FORGED"
	var da: int = int(after.get("atk", 0)) - int(before.get("atk", 0))
	var dh: int = int(after.get("hp", 0)) - int(before.get("hp", 0))
	if da > 0 and dh > 0:
		return "+%d/+%d" % [da, dh]
	if da > 0:
		return "+%d ATK" % da
	if dh > 0:
		return "+%d HP" % dh
	var had: Array = before.get("keywords", [])
	for kw in after.get("keywords", []):
		if not had.has(kw):
			return String(KeywordEffects.KEYWORDS.get(kw, {}) \
				.get("display", String(kw).capitalize())).to_upper()
	if before.has("spell") and after.has("spell"):
		var dv: int = int(after.spell.get("value", 0)) - int(before.spell.get("value", 0))
		if dv > 0:
			return "+%d POWER" % dv
	if int(after.get("cost", 0)) < int(before.get("cost", 0)):
		return "COSTS %d" % int(after.get("cost", 0))
	return "FORGED"

# Designer-style choose-from-pool picker. Rolls 3 random rare cards
# (preferring ones not already in the deck so the offering feels new) and
# lays them out horizontally with a fixed cost label below each. Costs are
# fixed across rolls — HP / gold / curse — so the player learns to read
# the row at a glance: "which card do I want, and which currency can I
# afford to spend?" Modeled on StS's Designer In-Spire and the Mind Bloom
# branches, but each card is the choice (not each effect).
func _start_stranger_hand_mode() -> void:
	_picker_busy = false
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
	var build_gen := _ui_build_gen
	_set_event_art_visible(true)
	add_child(_make_picker_scrim())

	var title = GameTheme.make_label(
		"Choose one rare card and pay its listed cost.",
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
	var card_rows: Array = []
	var hbox := HBoxContainer.new()
	hbox.name = "StrangerHandGroup"
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
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_on_stranger_hand_pick.bind(card_id, cost, v))
		click_btn.disabled = true
		wrapper.add_child(click_btn)
		v.add_child(wrapper)
		var back := TextureRect.new()
		back.name = "WetBack"
		back.texture = CARD_BACK_TEXTURE
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Motion.arm_loading_writ(back, hbox)
		wrapper.add_child(back)

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
		card_rows.append({"wrapper": wrapper, "data": data, "back": back,
			"button": click_btn})

	# Leave button below the row — the player can step into the picker,
	# inspect the cards, and back out without paying. Cleaner than forcing
	# a leave decision before they know what's on offer.
	var leave_btn := _make_frameless_choice(
		"Walk on",
		"",
		"You leave without taking a card.",
		88,
		_on_stranger_hand_leave)
	leave_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	leave_btn.offset_left = -280
	leave_btn.offset_right = 280
	leave_btn.offset_top = -160
	leave_btn.offset_bottom = -72
	add_child(leave_btn)
	_hydrate_stranger_hand_cards(card_rows, build_gen)
	_refresh_ledger()


## Build every shell/card-back immediately, then hydrate the expensive faces in
## order behind them. The authored flip waits until all three complete, so the
## player never sees a partial face and the settled offer is pixel-identical.
func _hydrate_stranger_hand_cards(rows: Array, build_gen: int) -> void:
	# Present the complete three-back hand once even on a warm cache. Hydration
	# remains implementation detail, and Reduce Motion still snaps on reveal.
	await get_tree().process_frame
	if not _event_ui_build_is_current(build_gen, self):
		return
	var flip_rows: Array = []
	for row in rows:
		var wrapper: Control = row.wrapper
		var data: Dictionary = row.data
		var back = row.back
		var click_btn: Button = row.button
		if not _event_ui_build_is_current(build_gen, wrapper):
			return
		if DisplayServer.get_name() != "headless" and not CardTextureCache.has(data):
			await CardTextureCache.bake(data)
			if not _event_ui_build_is_current(build_gen, wrapper):
				return
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		card_node.defer_baked_rules_text = DisplayServer.get_name() != "headless"
		card_node.visible = false
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, 0)
		flip_rows.append([wrapper, card_node, back, click_btn])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _event_ui_build_is_current(build_gen, wrapper):
				return
			card_node.complete_deferred_baked_rules()
			await RenderingServer.frame_post_draw
	if not _event_ui_build_is_current(build_gen, self):
		return
	if not flip_rows.is_empty():
		_play_wet_deal(flip_rows)


## L4's dealing beat: the whole hand turns together. Sequential hydration is a
## renderer concern, not authored drama; showing that work as three separate
## flips made the centered offer look like it was still assembling itself.
func _play_wet_deal(rows: Array) -> void:
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if snap:
		for row in rows:
			if not is_instance_valid(row[0]):
				return
			_wet_flip_show(row[1], row[2], row[3])
		return
	await get_tree().create_timer(0.35).timeout
	AudioBank.play_sfx("card_draw", 0.05, -6.0)
	for row in rows:
		var wrapper = row[0]
		if not is_instance_valid(wrapper):
			return
		wrapper.pivot_offset = wrapper.size * 0.5
		var tw: Tween = wrapper.create_tween()
		tw.tween_property(wrapper, "scale:x", 0.06, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.16).timeout
	for row in rows:
		var wrapper = row[0]
		if not is_instance_valid(wrapper):
			return
		_wet_flip_show(row[1], row[2], row[3])
		wrapper.scale.x = 0.06
		var tw: Tween = wrapper.create_tween()
		tw.tween_property(wrapper, "scale:x", 1.0, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _wet_flip_show(card: Control, back: Control, button: Button) -> void:
	if is_instance_valid(back):
		back.visible = false
		back.queue_free()
	if is_instance_valid(card):
		card.visible = true
	if is_instance_valid(button):
		button.disabled = false


func _on_stranger_hand_pick(card_id: String, cost: Dictionary,
		source: Control = null) -> void:
	if _picker_busy:
		return
	_picker_busy = true
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
	# The chosen rare now has a destination: the persistent deck ledger. Costs
	# and deck size update when it lands, tying the physical take to its receipt.
	if source != null and is_instance_valid(source):
		GameTheme.claim_pop(source)
		if source.get_parent() != null:
			for sibling in source.get_parent().get_children():
				if sibling != source and sibling is Control:
					GameTheme.fade_exit(sibling, 0.22)
		if UserSettings == null or not UserSettings.reduce_motion:
			await get_tree().create_timer(0.10).timeout
		if not is_inside_tree():
			return
		var vp := get_viewport_rect().size
		var target := Vector2(vp.x * 0.5, vp.y + 30.0)
		var deck_label: Control = _ledger_values.get("deck") as Control
		if deck_label != null and is_instance_valid(deck_label):
			target = deck_label.global_position + deck_label.size * 0.5
		await GameTheme.pocket_away(source, target, 0.34)
		_refresh_ledger()
		if deck_label != null and is_instance_valid(deck_label):
			GameTheme.punch(deck_label, 1.12)
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
		_show_result("You have none of the smith's relics.")
		return

	# Same reading block as every other screen (restyled 2026-07-04 after the
	# defect hunt: the old scrim+scroll version left one entry floating top-left
	# and the decline stranded bottom-center over near-black art). Frameless
	# writ entries — relic name as the verb line, its rules text as the gold
	# outcome (what you're giving up IS the stake) — and "Keep them all" closes
	# the same column. The list scrolls only when the bag is truly heavy.
	var choices_vbox := _build_event_screen(
		"The anvil is patient",
		"Choose one of the smith's relics to trade. The trade is permanent.",
		mini(non_starting.size(), 5) + 1)

	# 128px per entry. This was 96, calibrated when the note below was written on
	# a name plus a TWO-line rules block (~85px). Plenty of relics wrap to three:
	# Thief's Gloves ("After a fight: if you took 1-5 face damage, gain 15 gold.
	# If you took 0, start the next fight with +1 Command.") is ~120px on its own,
	# so with two such relics the viewport was shorter than its content and the
	# SECOND entry's rules text was scrolled out of sight — it read as a relic
	# with no description at all, beside one that had it. First seen the day this
	# screen was first rendered: the whole feature had been unreachable, so no
	# screenshot of it had ever existed.
	#
	# THE CAP IS A WHOLE NUMBER OF ENTRIES, and that is the point of rounding it.
	# A flat 440 is 3.4 entries, so a heavy relic bag cut the fourth one straight
	# through the middle: its NAME sat at the bottom of the viewport with its rules
	# text below the fold, which reads as a relic that has no description — the
	# very defect the 128 above was raised to fix, returning at a different count.
	# Rounding down to a whole entry means the list can only ever cut BETWEEN
	# entries, at any bag size, and it follows ENTRY_H automatically if that moves.
	# THE CAP IS MEASURED, NOT ESTIMATED. Two estimates have now been wrong here —
	# 96px (calibrated on a two-line rules block) and 128px (calibrated on typical
	# relics) — and each was found by a different bug report, because an estimate is
	# only ever right for the content it was measured against. The relics with the
	# LONGEST text in the database build ~145px rows, so 3 x 128 sliced the third
	# one's last line off.
	# So the viewport is sized from the entries THEMSELVES once they have laid out
	# (see the deferred pass below): the sum of the first MAX_VISIBLE real heights.
	# That cannot drift with the content, and it keeps the one invariant that
	# matters — a list may cut BETWEEN entries, never through one.
	const MAX_VISIBLE := 3
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 384)   # provisional; re-measured below
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
			"Trade this relic.", 66,
			_on_relic_sacrifice_pick.bind(String(rid))))

	# The player may inspect their relics and decline — backing out leaves the
	# whole event (same as the Stranger's Hand picker).
	choices_vbox.add_child(_make_frameless_choice(
		"Keep them all", "",
		"Keep all relics and leave.",
		72, _on_stranger_hand_leave))

	_fit_relic_scroll.call_deferred(scroll, lst, MAX_VISIBLE)


## Size the relic picker's viewport to a WHOLE number of real entries, once they
## have actually laid out. Deferred because entry heights are not known until the
## container has run: a rules block wraps to two lines or three depending on the
## relic, so no constant can be right for every bag. Summing the real heights is
## the only version of this that cannot drift with the content — and the invariant
## it protects is that the list cuts BETWEEN entries and never through one, which
## is what makes a half-shown relic look like a relic with no rules text.
func _fit_relic_scroll(scroll: ScrollContainer, lst: VBoxContainer,
		max_visible: int) -> void:
	# TWO FRAMES, NOT call_deferred's ONE. A deferred call lands at the end of the
	# same frame, BEFORE the container has laid its children out, so every height
	# reads as zero and the fit silently does nothing — which is exactly what
	# happened: the viewport stayed at its provisional 384 and the wordiest relic
	# in the game still had its last line sliced off. Wait for layout to settle,
	# then measure.
	await get_tree().process_frame
	await get_tree().process_frame
	if scroll == null or not is_instance_valid(scroll) \
			or lst == null or not is_instance_valid(lst):
		return
	var sep: int = lst.get_theme_constant("separation")
	var total := 0.0
	var counted := 0
	for child in lst.get_children():
		if counted >= max_visible or not (child is Control):
			break
		var h: float = (child as Control).size.y
		if h <= 1.0:
			continue
		total += h + (sep if counted > 0 else 0)
		counted += 1
	if counted > 0:
		scroll.custom_minimum_size = Vector2(0, ceilf(total))


func _on_relic_sacrifice_pick(relic_id: String) -> void:
	var lost_name = RelicDB.get_relic(relic_id).name
	RunState.relics.erase(relic_id)
	var choices = RelicDB.roll_relic_reward("boss", RunState.relics, RunState.current_hero_id)
	if choices.is_empty():
		choices = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
	if choices.is_empty():
		_show_result("Lost %s. No replacement relic was available." % lost_name)
		return
	RunState.add_relic(choices[0])
	_result_relics.append(choices[0])
	_sting("card_play")
	var gained_name = RelicDB.get_relic(choices[0]).name
	_show_result("Traded %s for %s." % [lost_name, gained_name])


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
		_show_result("You have no creature to sacrifice.")
		return
	var grid = _make_card_picker_grid(
		effect.get("prompt", "Choose a creature to sacrifice."), GameTheme.BLOOD_RED)
	for i in creatures:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_sacrifice_pick.bind(i))


func _on_sacrifice_pick(deck_index: int) -> void:
	# Deck floor of 1 — sacrificing your only card would leave an empty deck.
	if RunState.deck.size() <= 1:
		_show_result("You cannot sacrifice your last card.")
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
			_show_result("Sacrificed %s. Gained %d gold." % [nm, amt])
		"max_hp":
			var hp_gain := base + int(atk / 2.0)
			RunState.hero_max_hp += hp_gain
			RunState.hero_hp += hp_gain
			_show_result("Sacrificed %s. Gained %d max HP." % [nm, hp_gain])
		"relic":
			var choices = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
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
	# Snapshot the folded original BEFORE it leaves the deck — a transform is the
	# clearest before→after in the game and it used to resolve as a sentence.
	var before_tf: Dictionary = RunState.get_upgraded_card_data(deck_index).duplicate(true)
	RunState.remove_card_at(deck_index)
	var new_id: String = pool[randi() % pool.size()]
	RunState.add_card(new_id)
	_result_pairs.append({
		"before": before_tf,
		"after": CardDB.get_card_data(new_id).duplicate(true),
	})
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

# The road remembers: any gamble cfg may carry `seen_texts` — per-event text
# overrides that wake when the player has met the OTHER half of the story
# this run (the coin knows the pit, the pit knows the coin, the clerk knows
# them both). World-threading as data: no extra choices, no layout cost,
# sparse keys so the variants surface as recognition beats rather than a
# rewritten event. Shared by dice_run and shell_game.
func _seen_text_override(cfg: Dictionary, key: String, raw: String) -> String:
	var variants: Dictionary = cfg.get("seen_texts", {})
	for ev_id in variants:
		if RunState.events_seen.has(String(ev_id)) \
				and (variants[ev_id] as Dictionary).has(key):
			return String(variants[ev_id][key])
	return raw


func _dice_text(key: String, fallback: String, gain: int = 0) -> String:
	var raw := _seen_text_override(_dice_cfg, key,
		String(_dice_cfg.get(key, fallback)))
	return raw.replace("{pot}", str(_dice_pot)).replace("{gain}", str(gain))


func _start_dice_run(effect: Dictionary) -> void:
	_dice_cfg = effect
	_dice_pot = int(effect.get("start", 25))
	_dice_prev_pot = -1
	var stake: int = int(effect.get("stake", 0))
	if stake > 0:
		if RunState.gold < stake:
			_show_result(_dice_text("broke_text", "You do not have enough gold to play."))
			return
		RunState.gold -= stake
	_build_dice_screen(_dice_text("open_text",
		"The pot is {pot} gold. Cast to increase it, or take it now."))


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

# The gamble's physical stage (2026-07-18): live prop references for the beat
# functions. Rebuilt with every _build_dice_screen; the beats animate the
# CURRENT stage, then the ordinary rebuild/result flow takes over.
var _dice_stage_dice: Array = []      # KnuckleboneDie nodes on the current stage
var _dice_stage_heap: Control = null  # the pot heap — the bank button itself
var _dice_stage_coin: Control = null  # the spinner's coin (prop "coin")
var _dice_coin_tween: Tween = null    # the spinner's idle squash loop
var _dice_busy: bool = false          # input lock while a cast beat plays


func _build_dice_screen(beat: String) -> void:
	_dice_busy = false   # every fresh screen unlocks the props
	var choices_vbox := _build_event_screen(
		"The pot: [color=#e8b547]%d gold[/color]" % _dice_pot, beat, 2)

	_add_pot_display(_dice_pot > _dice_prev_pot and _dice_prev_pot >= 0)
	_dice_prev_pot = _dice_pot

	choices_vbox.add_child(_make_frameless_choice(
		_dice_text("roll_label", "Cast the bones"),
		_dice_text("roll_sub", "A safe cast increases the pot. A skull loses it."),
		_dice_text("roll_body", "Cast the bones."),
		84, _on_dice_roll))
	choices_vbox.add_child(_make_frameless_choice(
		_dice_text("bank_label", "Bank the pot"),
		_dice_text("bank_sub", "Take {pot} gold and leave."),
		_dice_text("bank_body", "Take the current pot."),
		84, _on_dice_bank))


## The gamble's physical stage (2026-07-18, replaces the passive pot display —
## docs/EVENT_PLAY_PITCH_20260718.md). Two props share it, and BOTH follow
## bake-then-shade: the outcome resolves before anything here animates.
##   "bones" — the full knucklebone table: a leather CastPatch, four
##   KnuckleboneDie painters resting at your edge (click the bones to cast),
##   and the pot as a coin heap that IS the bank button.
##   "coin"  — the spinner: one patient piece turning on its edge; the coin
##   itself is the CALL button, the pot figure rides below.
## The text choice rows stay in the ladder as accessible duplicates — both
## paths call the same handlers.
func _add_pot_display(pulse: bool) -> void:
	_dice_stage_dice = []
	_dice_stage_heap = null
	_dice_stage_coin = null
	_dice_coin_tween = null
	var root := Control.new()
	root.name = "PotDisplay"
	root.position = Vector2(860, 200)
	root.size = Vector2(560, 460)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var is_coin: bool = String(_dice_cfg.get("prop", "bones")) == "coin"
	if is_coin:
		_build_spinner_stage(root)
	else:
		_build_bone_stage(root)

	var figure := Label.new()
	figure.name = "PotFigure"
	figure.text = "%d" % _dice_pot
	figure.add_theme_font_size_override("font_size", 44)
	figure.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD)
	figure.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	figure.add_theme_constant_override("outline_size", 5)
	figure.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	figure.add_theme_constant_override("shadow_offset_y", 2)
	if GameTheme.font_display:
		figure.add_theme_font_override("font", GameTheme.font_display)
	if is_coin:
		figure.position = Vector2(0, 330)
		figure.size = Vector2(560, 56)
	else:
		# Under the heap, on the patch's high corner — the pot labels itself.
		figure.position = Vector2(330, 214)
		figure.size = Vector2(210, 50)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(figure)

	if pulse and not UserSettings.reduce_motion:
		# The pot just grew: the heap (or coin) takes the weight, not the
		# whole table.
		var puls: Control = _dice_stage_coin if is_coin else _dice_stage_heap
		if puls != null:
			puls.scale = Vector2(1.16, 1.16)
			puls.create_tween().tween_property(puls, "scale", Vector2.ONE, 0.30) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_bone_stage(root: Control) -> void:
	var patch := CastPatch.new()
	patch.seed_text = "patch_" + _event_id
	patch.chalk = "ring"
	patch.position = Vector2(10, 40)
	patch.size = Vector2(540, 360)
	root.add_child(patch)

	# The pot heap on the patch's high corner. The heap IS the bank button —
	# potion-slot pattern: wrapper PASS for the rich-hover tip, transparent
	# PASS button for the click.
	var heap := Control.new()
	heap.name = "PotHeap"
	heap.position = Vector2(360, 78)
	heap.size = Vector2(150, 130)
	heap.pivot_offset = Vector2(75, 65)
	heap.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(heap)
	_dice_stage_heap = heap
	var n_coins: int = clampi(3 + _dice_pot / 25, 3, 9)
	const PILE_ROWS := [4, 3, 2]
	var placed := 0
	for row in range(PILE_ROWS.size()):
		var count: int = PILE_ROWS[row]
		for i in range(count):
			if placed >= n_coins:
				break
			# The Old King's coinage (CoinProp handles the lying squash, edge
			# thickness, and ground pool itself — no node scale/rotation).
			var c := CoinProp.new()
			c.seed_text = "pot_%s_%d" % [_event_id, placed]
			c.lying = true
			c.size = Vector2(32, 32)
			var cx: float = 75.0 - (count - 1) * 13.0 + i * 26.0 - 16.0
			var cy: float = 86.0 - row * 17.0
			c.position = Vector2(cx + fmod(float(placed) * 7.3, 5.0) - 2.5, cy)
			heap.add_child(c)
			placed += 1
	var bank_btn := Button.new()
	# Named so headless harnesses can find the bank action. The heap IS the
	# button, so it carries NO text — tools/_probe_stuck2.gd matches end-of-
	# screen controls by label, and a textless one is invisible to that walk.
	bank_btn.name = "DiceBankBtn"
	bank_btn.flat = true
	bank_btn.focus_mode = Control.FOCUS_NONE
	bank_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	bank_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	bank_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		bank_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	bank_btn.pressed.connect(_on_dice_bank)
	heap.add_child(bank_btn)
	GameTheme.attach_rich_hover(heap, _dice_text("bank_label", "Bank the pot"),
		_dice_text("bank_sub", "Take {pot} gold and leave."),
		"Click the pot to collect it.", GameTheme.KEYWORD_GOLD, 1.07)

	# Four knucklebones resting at your edge of the patch — the cast zone.
	var rests := [
		["kb_a", Vector2(64, 328), -0.28], ["kb_b", Vector2(112, 344), 0.18],
		["kb_c", Vector2(162, 330), 0.42], ["kb_d", Vector2(212, 346), -0.10]]
	for spec in rests:
		var die := KnuckleboneDie.new()
		die.seed_text = String(spec[0])
		die.face = 1 + posmod(hash(spec[0]), 4)
		die.position = spec[1]
		die.size = Vector2(38, 38)
		die.pivot_offset = Vector2(19, 19)
		die.rotation = spec[2]
		root.add_child(die)
		_dice_stage_dice.append(die)
	var cast_zone := Control.new()
	cast_zone.name = "CastZone"
	cast_zone.position = Vector2(44, 302)
	cast_zone.size = Vector2(224, 100)
	cast_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(cast_zone)
	var cast_btn := Button.new()
	cast_btn.flat = true
	cast_btn.focus_mode = Control.FOCUS_NONE
	cast_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	cast_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		cast_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	cast_btn.pressed.connect(_on_dice_roll)
	cast_zone.add_child(cast_btn)
	GameTheme.attach_rich_hover(cast_zone, _dice_text("roll_label", "Cast the bones"),
		_dice_text("roll_sub", "A safe cast increases the pot. A skull loses it."),
		"Click the bones to cast.", KnuckleboneDie.BONE, 1.0)


func _build_spinner_stage(root: Control) -> void:
	# One patient silver-gold piece, spinning on its edge forever. The coin
	# is the CALL button — you touch the thing itself. Walking away is the
	# ladder's bank row: banking never touches the coin, which is the point.
	var wrap := Control.new()
	wrap.name = "SpinnerCoin"
	wrap.position = Vector2(220, 140)
	wrap.size = Vector2(120, 140)
	wrap.pivot_offset = Vector2(60, 70)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(wrap)
	_dice_stage_coin = wrap
	# Ground shadow — the one thing the coin never loses.
	var shade := Panel.new()
	shade.position = Vector2(24, 116)
	shade.size = Vector2(72, 12)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade_st := StyleBoxFlat.new()
	shade_st.bg_color = Color(0, 0, 0, 0.30)
	shade_st.set_corner_radius_all(99)
	shade.add_theme_stylebox_override("panel", shade_st)
	wrap.add_child(shade)
	var spin := CoinProp.new()
	spin.name = "Coin"
	spin.seed_text = "spinner_" + _event_id
	spin.shadow = false
	spin.size = Vector2(96, 96)
	spin.position = Vector2(12, 22)
	spin.pivot_offset = Vector2(48, 48)
	wrap.add_child(spin)
	if not UserSettings.reduce_motion:
		# The turn drives face_t, not scale.x — at the thin moment the coin
		# flashes its milled edge instead of a squashed picture.
		_dice_coin_tween = spin.create_tween().set_loops()
		_dice_coin_tween.tween_property(spin, "face_t", 0.04, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_dice_coin_tween.tween_property(spin, "face_t", 1.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var call_btn := Button.new()
	call_btn.flat = true
	call_btn.focus_mode = Control.FOCUS_NONE
	call_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	call_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	call_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		call_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	call_btn.pressed.connect(_on_dice_roll)
	wrap.add_child(call_btn)
	GameTheme.attach_rich_hover(wrap, _dice_text("roll_label", "Call it"),
		_dice_text("roll_sub", "Win to double the pot. Lose to forfeit it."),
		"Click the coin to call.", GameTheme.KEYWORD_GOLD, 1.05)


## The cast beat (prop "bones"): the resting bones tumble across the patch
## and settle on faces that MATCH the already-resolved outcome — clean pips
## on a win, one or two skulls up on a bust (never all four: even the bad
## news should look like a near thing). Pure theater; Reduce Motion snaps
## the faces and keeps only a reading pause.
func _play_bone_cast(bust: bool) -> void:
	var faces: Array = []
	for i in range(4):
		faces.append({"skull": false, "face": randi_range(1, 4)})
	if bust:
		faces[randi_range(0, 3)]["skull"] = true
		if randf() < 0.5:
			faces[randi_range(0, 3)]["skull"] = true
	AudioBank.play_sfx("bone_cast", 0.06, -2.0)
	if UserSettings.reduce_motion or _dice_stage_dice.size() < 4:
		for i in range(_dice_stage_dice.size()):
			var d = _dice_stage_dice[i]
			d.skull = bool(faces[i]["skull"])
			d.face = int(faces[i]["face"])
			d.queue_redraw()
		await get_tree().create_timer(0.5).timeout
		return
	# The tumble: four independent throws. Each die arcs up with its face
	# TURNING in the air, stamps its true face at first impact, then loses
	# the rest of its energy in decaying hops while the spin dies into a
	# resting angle. Fire-and-forget per die; the shared await below covers
	# the longest throw.
	var lands := [Vector2(140, 190), Vector2(235, 250), Vector2(178, 296),
		Vector2(315, 215)]
	for i in range(4):
		_tumble_die(_dice_stage_dice[i], faces[i],
			lands[i] + Vector2(randf_range(-14, 14), randf_range(-10, 10)),
			0.07 * i, 1.0 if i % 2 == 0 else -1.0)
	await get_tree().create_timer(1.05).timeout
	# Let the throw READ before anything else happens.
	await get_tree().create_timer(0.40).timeout
	if bust:
		# The skulls announce themselves, then the pot drains to the dead.
		for i in range(4):
			if bool(faces[i]["skull"]):
				var d: Control = _dice_stage_dice[i]
				var ft := d.create_tween().set_loops(2)
				ft.tween_property(d, "modulate", Color(1.0, 0.52, 0.42), 0.12)
				ft.tween_property(d, "modulate", Color.WHITE, 0.12)
		await get_tree().create_timer(0.50).timeout
		if _dice_stage_heap != null and is_instance_valid(_dice_stage_heap):
			var ht := _dice_stage_heap.create_tween()
			ht.tween_property(_dice_stage_heap, "position",
				_dice_stage_heap.position + Vector2(150, 34), 0.45) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			ht.parallel().tween_property(_dice_stage_heap, "modulate:a", 0.0, 0.45)
			# The gilt figure is the pot's label — it leaves with the coins.
			var fig := _dice_stage_heap.get_parent().get_node_or_null("PotFigure")
			if fig != null:
				ht.parallel().tween_property(fig, "modulate:a", 0.0, 0.45)
		await get_tree().create_timer(0.50).timeout
	else:
		_fly_coins_to_heap()
		await get_tree().create_timer(0.42).timeout


## One knucklebone's throw: rise, spin, and swell toward the eye — with the
## face turning over mid-air, a die nobody can read yet — then the true face
## stamps at FIRST impact and the energy dies in two shrinking hops as the
## spin settles into a resting angle. The stamped face is the resolved one;
## the tumble only ever LOOKS undecided.
func _tumble_die(die: Control, spec: Dictionary, dest: Vector2,
		delay: float, spin_dir: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(die):
		return
	var mid: Vector2 = die.position.lerp(dest, 0.55) + Vector2(0, -70)
	var final_rot := randf_range(-0.35, 0.35)
	var tw := die.create_tween()
	tw.tween_property(die, "position", mid, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(die, "rotation",
		die.rotation + randf_range(3.4, 5.2) * spin_dir, 0.46)
	tw.parallel().tween_property(die, "scale", Vector2(1.26, 1.26), 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(die, "position", dest, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(die, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Airborne: every look shows another side (the skull included — it IS a
	# face of the die; only the stamped face is the truth).
	for _j in range(4):
		await get_tree().create_timer(0.105).timeout
		if not is_instance_valid(die):
			return
		die.face = randi_range(1, 4)
		die.skull = randf() < 0.18
		die.queue_redraw()
	await get_tree().create_timer(0.05).timeout
	if not is_instance_valid(die):
		return
	# First impact: the true face stamps, the clack lands, the body squashes.
	die.skull = bool(spec["skull"])
	die.face = int(spec["face"])
	die.queue_redraw()
	AudioBank.play_sfx("bone_settle", 0.08, -7.0)
	var sq := die.create_tween()
	sq.tween_property(die, "scale", Vector2(1.24, 0.78), 0.05)
	sq.tween_property(die, "scale", Vector2.ONE, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Two decaying hops; the spin eases into rest on the way down.
	var hop := die.create_tween()
	hop.tween_property(die, "position", dest + Vector2(spin_dir * 7.0, -11.0), 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(die, "position", dest + Vector2(spin_dir * 12.0, 0.0), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.parallel().tween_property(die, "rotation", final_rot, 0.15)
	hop.tween_property(die, "position", dest + Vector2(spin_dir * 16.0, -4.0), 0.08)
	hop.tween_property(die, "position", dest + Vector2(spin_dir * 18.0, 0.0), 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Winnings arrive as objects: three coins arc from the cast into the heap,
## and the heap takes the weight.
func _fly_coins_to_heap() -> void:
	if _dice_stage_heap == null or not is_instance_valid(_dice_stage_heap):
		return
	AudioBank.play_sfx("coin_pour", 0.06)
	var root := _dice_stage_heap.get_parent() as Control
	if root == null:
		return
	var dest: Vector2 = _dice_stage_heap.position + Vector2(60, 70)
	for i in range(3):
		# Airborne pieces: face-on, no ground pool until they join the heap.
		var c := CoinProp.new()
		c.seed_text = "fly_%d_%d" % [randi() % 1000, i]
		c.shadow = false
		c.size = Vector2(26, 26)
		c.position = Vector2(200 + i * 26, 240)
		root.add_child(c)
		var tw := c.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(c, "position",
			dest + Vector2(randf_range(-12, 12), randf_range(-8, 8)), 0.34) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, 0.10)
		tw.tween_callback(c.queue_free)
	var hp := _dice_stage_heap.create_tween()
	hp.tween_interval(0.30)
	hp.tween_property(_dice_stage_heap, "scale", Vector2(1.12, 1.12), 0.08)
	hp.tween_property(_dice_stage_heap, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The spinner's call (prop "coin"): the spin tightens, the coin leans past
## sense — and either rights itself (the pot doubles) or falls flat at last.
## The near-miss wobble is the drama the prose already sells.
func _play_coin_call(bust: bool) -> void:
	_sting("card_play", -4.0)
	var wrap := _dice_stage_coin
	if wrap == null or not is_instance_valid(wrap) or UserSettings.reduce_motion:
		await get_tree().create_timer(0.4).timeout
		if bust:
			AudioBank.play_sfx("coin_fall", 0.04, -2.0)
		return
	var coin: Control = wrap.get_node_or_null("Coin")
	if coin == null:
		await get_tree().create_timer(0.4).timeout
		return
	if _dice_coin_tween != null and _dice_coin_tween.is_valid():
		_dice_coin_tween.kill()
	# The spin tightens…
	var fast := coin.create_tween().set_loops(4)
	fast.tween_property(coin, "face_t", 0.06, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fast.tween_property(coin, "face_t", 1.0, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.82).timeout
	# The spin is nearly a second long and `_clear_ui()` frees the props, so the
	# coin can be gone by the time this resumes — and a call on a freed object
	# aborts the rest of this function silently, leaving the spinner mid-beat with
	# no error. Its sibling `_run_shell_shuffle` already guards this way (on the
	# root); this one did not.
	if not is_instance_valid(coin):
		return
	# …then it leans, each lean deeper than the last.
	var lean := coin.create_tween()
	for a in [0.16, -0.22, 0.30]:
		lean.tween_property(coin, "rotation", a, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await lean.finished
	# Second suspension, same hazard as the first. The `tween_callback` further
	# down already tests `is_instance_valid(coin)`, so the risk was understood —
	# it just was not covered at the point the tween is created.
	if not is_instance_valid(coin):
		return
	if bust:
		# Past the point of no return: it topples through one last half-turn
		# and lands flat — TAILS up (flipped while edge-on, so the swap is
		# never seen), thickness and ground pool on. One hard clack.
		var fall := coin.create_tween()
		fall.tween_property(coin, "rotation", 1.35, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(coin, "face_t", 0.06, 0.16)
		fall.tween_callback(func () -> void:
			if is_instance_valid(coin) and coin is CoinProp:
				coin.tails = true
				coin.lying = true)
		fall.tween_property(coin, "rotation", 0.0, 0.10)
		fall.parallel().tween_property(coin, "face_t", 1.0, 0.10)
		fall.parallel().tween_property(coin, "position:y", coin.position.y + 12, 0.10)
		await fall.finished
		AudioBank.play_sfx("coin_fall", 0.04, -2.0)
		await get_tree().create_timer(0.55).timeout
	else:
		var right := coin.create_tween()
		right.tween_property(coin, "rotation", 0.0, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		right.parallel().tween_property(coin, "face_t", 1.0, 0.20)
		await right.finished
		if not is_instance_valid(coin):
			return
		Motion.burst(self, coin.get_global_position() + coin.size * 0.5, "coin_spark")
		await get_tree().create_timer(0.30).timeout


## Losing everything should feel like it: a short table-shake, a red wash over
## the page, and the hit sting. Called AFTER the result screen builds so the
## wash lies over the bust text, not under a rebuild.
func _bust_feedback() -> void:
	_sting("hit_hero")
	# The table takes the hit through the shared trauma service — it gates on
	# the dedicated screen-shake setting itself, and impulses compound.
	GameTheme.shake_impulse(self, 0.35)
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


## The positive counterpart to _bust_feedback: a warm gold wash + a light
## shake for a game WON, so a payout lands with a flourish instead of just a
## line of text. `pos` (global) optionally spits a coin burst there. Shake
## gates on its own setting; the wash gates on reduce_motion.
func _win_flourish(pos: Vector2 = Vector2.ZERO) -> void:
	GameTheme.shake_impulse(self, 0.16)
	if UserSettings.reduce_motion:
		return
	var wash := ColorRect.new()
	wash.color = Color(0.86, 0.66, 0.28, 0.20)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	var wt := wash.create_tween()
	wt.tween_property(wash, "color:a", 0.0, 0.6).set_delay(0.05)
	wt.tween_callback(wash.queue_free)
	if pos != Vector2.ZERO:
		Motion.burst(self, pos, "coin")


## A consistent entrance for a minigame stage root: it settles in with a
## small fade + scale-from-centre so the table arrives instead of popping.
## Decorative — Reduce Motion just leaves it fully shown.
func _stage_entrance(root: Control) -> void:
	if root == null or not is_instance_valid(root) or UserSettings.reduce_motion:
		return
	root.pivot_offset = root.size * 0.5
	root.modulate.a = 0.0
	root.scale = Vector2(0.965, 0.965)
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.24)
	tw.parallel().tween_property(root, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The rest-state "you may touch this" cue: a TouchGlow ground-ring under a
## clickable stage prop (2026-07-20 legibility pass — the stages mix
## play-by-choice-column and play-by-clicking-props, and clickable props
## looked identical to decorations until hovered). host must be a plain
## Control wrap sized to the prop — NEVER the Button itself (a Control
## child of a Button is never laid out); btn's hover drives the brighten.
func _stage_touchable(host: Control, btn: BaseButton) -> void:
	var g := TouchGlow.new()
	g.position = Vector2(-6, -2)
	g.size = host.size + Vector2(12, 8)
	host.add_child(g)
	host.move_child(g, 0)
	btn.mouse_entered.connect(func():
		if is_instance_valid(g):
			g.hot = true)
	btn.mouse_exited.connect(func():
		if is_instance_valid(g):
			g.hot = false)


## The drawing of lots (docs/EVENT_PLAY_PITCH_20260718.md L3): every
## roll_table commit resolves as a physical draw — an upturned helmet of
## folded slips rises out of the dark, one lot comes up and unfolds, and
## the page's ink lands as it fades. Pure theater OVER the already-built
## result page (the outcome resolved before this runs); Reduce Motion never
## calls it. Fire-and-forget from _show_result.
func _play_lots_draw() -> void:
	var root := Control.new()
	root.name = "LotsBeat"
	root.position = Vector2(1010, 330)
	root.size = Vector2(300, 340)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate.a = 0.0
	add_child(root)
	var helm := EventHelm.new()
	helm.seed_text = "lots_" + _event_id
	helm.dome_up = false
	helm.slips = 4
	helm.position = Vector2(75, 150)
	helm.size = Vector2(150, 120)
	root.add_child(helm)
	var slip := PaperSlip.new()
	slip.seed_text = "lot_" + _event_id
	slip.position = Vector2(80, 130)
	slip.size = Vector2(140, 84)
	slip.pivot_offset = Vector2(70, 42)
	slip.scale = Vector2(0.9, 0.08)
	slip.rotation = 0.10
	root.add_child(slip)
	var t := root.create_tween()
	t.tween_property(root, "modulate:a", 1.0, 0.22)
	await t.finished
	if not is_instance_valid(slip):
		return
	AudioBank.play_sfx("paper_draw", 0.06, -4.0)
	var d := slip.create_tween()
	d.tween_property(slip, "position:y", 34.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	d.tween_property(slip, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	d.parallel().tween_property(slip, "rotation", -0.06, 0.26)
	await d.finished
	await get_tree().create_timer(0.55).timeout
	if not is_instance_valid(root):
		return
	var out := root.create_tween()
	out.tween_property(root, "modulate:a", 0.0, 0.30)
	out.tween_callback(root.queue_free)


func _on_dice_roll() -> void:
	if _dice_busy:
		return
	_dice_busy = true
	# Bake then shade: resolve the whole throw FIRST, then let the props
	# perform the resolved outcome. Nothing about the result rides on the
	# animation — Reduce Motion collapses the beat to a reading pause.
	var bust: bool = randf() < float(_dice_cfg.get("bust_pct", 1.0 / 3.0))
	var gain: int = 0
	if not bust:
		if String(_dice_cfg.get("mode", "add")) == "double":
			gain = _dice_pot
		else:
			gain = randi_range(int(_dice_cfg.get("gain_min", 18)),
				int(_dice_cfg.get("gain_max", 34)))
	if String(_dice_cfg.get("prop", "bones")) == "coin":
		await _play_coin_call(bust)
	else:
		await _play_bone_cast(bust)
	if bust:
		_dice_pot = 0
		_dice_prev_pot = -1
		var bust_receipt := _gamble_pay(_dice_cfg, false, 0)
		_show_result(_combine_lines([_dice_text("bust_text",
			"Skull. You lost the entire pot."), bust_receipt]))
		_bust_feedback()
		return
	if String(_dice_cfg.get("mode", "add")) == "double":
		_dice_pot *= 2
	else:
		_dice_pot += gain
	_sting("coin")
	_build_dice_screen(_dice_text("grow_text",
		"Safe cast. Added {gain} gold to the pot.", gain))


func _on_dice_bank() -> void:
	if _dice_busy:
		return
	_dice_busy = true
	var receipt := _gamble_pay(_dice_cfg, true, _dice_pot)
	# The pot leaves the table the way it should: pocketed toward the ledger
	# that just grew (top-right), not vanished by a screen swap.
	if _dice_stage_heap != null and is_instance_valid(_dice_stage_heap) \
			and not UserSettings.reduce_motion:
		await Motion.pocket_away(_dice_stage_heap, Vector2(1470, 90))
	_dice_prev_pot = -1
	var line := _dice_text("bank_text",
		"Collected {pot} gold.")
	# Big-pot payoff: banking past the threshold carries the table's own
	# relic away with the gold (event relics — granted by name, never rolled).
	var rid := _gamble_bank_relic(_dice_cfg, _dice_pot)
	if rid != "":
		line += "\n\n" + _dice_text("bank_relic_text",
			"Gained relic: %s." % RelicDB.get_relic(rid).name)
	_show_result(_combine_lines([line, receipt]))


# ── The Old Army Game (shell_game) — three helmets, one coin, honest ─────
# The shell game engine (docs/EVENT_PLAY_PITCH_20260718.md XL): the coin
# RIDES ITS HELMET through every swap, so the shuffle is honest by
# construction — tracking it is the whole game, and an attentive player
# genuinely beats the odds. The dented helm is the mercy rule: the coin
# never STARTS under the crease, so it can never end there; losing the
# thread leaves you a coin flip, not a guess of three. Swaps animate as
# front/back crossing arcs at watchable speed (the pitch's "honest speed"
# bar); Reduce Motion swaps snap position-to-position with reading pauses —
# the game stays fair without continuous motion. Config:
#   {stake, payout, swaps, open_text, win_text, lose_text, broke_text,
#    seen_texts} — texts take {stake} / {payout}.

var _shell_cfg: Dictionary = {}
var _shell_helms: Array = []      # helm wrap Controls, by helm index
var _shell_order: Array = []      # order[slot] = helm index
var _shell_prize_helm: int = 1    # the coin rides this helm
var _shell_dent_helm: int = 0     # the tell — never the prize, by rule
var _shell_slots: Array = []      # slot base positions (stage-local)
var _shell_coin: Control = null
var _shell_root: Control = null
var _shell_vbox: VBoxContainer = null
var _shell_busy := true


func _shell_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_shell_cfg, key,
		String(_shell_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_shell_cfg.get("stake", 0)))) \
		.replace("{payout}", str(int(_shell_cfg.get("payout", 0))))


func _start_shell_game(effect: Dictionary) -> void:
	_shell_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_shell_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	_shell_busy = true
	_shell_vbox = _build_event_screen(_event_data.name,
		_shell_text("open_text",
			"Watch the coin under the middle helmet, then follow the shuffle."), 3)
	_build_shell_stage()
	_run_shell_shuffle()


func _build_shell_stage() -> void:
	_shell_helms = []
	_shell_order = [0, 1, 2]
	_shell_slots = [Vector2(42, 186), Vector2(202, 186), Vector2(362, 186)]
	var root := Control.new()
	root.name = "ShellStage"
	root.position = Vector2(860, 210)
	root.size = Vector2(560, 430)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_shell_root = root
	var drum := CastPatch.new()
	drum.seed_text = "drum_" + _event_id
	drum.position = Vector2(10, 60)
	drum.size = Vector2(540, 340)
	root.add_child(drum)
	# The coin — shown once, honestly, then hidden until the reveal. Added
	# before the helms so a lifted helm uncovers it.
	var coin := CoinProp.new()
	coin.seed_text = "shell_" + _event_id
	# CoinProp draws the lying squash, edge thickness, and ground pool itself.
	coin.lying = true
	# The blue seat plays for the clerk's own pay-token — worn smooth.
	coin.worn = int(_shell_cfg.get("stake", 30)) == 0
	coin.size = Vector2(34, 34)
	coin.position = _shell_slots[1] + Vector2(60, 82)
	root.add_child(coin)
	_shell_coin = coin
	# Helms: the coin starts under the MIDDLE one, in plain view; the dent
	# goes to one of the others.
	_shell_prize_helm = 1
	_shell_dent_helm = 0 if randi() % 2 == 0 else 2
	for h in range(3):
		var wrap := Control.new()
		wrap.name = "Helm%d" % h
		wrap.position = _shell_slots[h]
		wrap.size = Vector2(155, 122)
		wrap.pivot_offset = Vector2(77, 100)
		wrap.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(wrap)
		_shell_helms.append(wrap)
		var helm := EventHelm.new()
		helm.seed_text = "helm_%d_%s" % [h, _event_id]
		helm.dome_up = true
		helm.dented = h == _shell_dent_helm
		helm.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(helm)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.pressed.connect(_on_shell_pick.bind(h))
		wrap.add_child(btn)
		GameTheme.attach_rich_hover(wrap, "Lift this helmet",
			"This is the dented helmet." if h == _shell_dent_helm
				else "The coin is under one of the three helmets.",
			"Click to lift", GameTheme.KEYWORD_GOLD, 1.04)


func _run_shell_shuffle() -> void:
	# The show: the prize helm starts lifted over the coin, drops, and the
	# passes begin — quickening as he warms to it.
	var pw: Control = _shell_helms[_shell_prize_helm]
	if not UserSettings.reduce_motion:
		pw.position = _shell_slots[1] + Vector2(0, -56)
		await get_tree().create_timer(0.85).timeout
		if _shell_root == null or not is_instance_valid(_shell_root):
			return
		var drop := pw.create_tween()
		drop.tween_property(pw, "position", _shell_slots[1], 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		drop.tween_property(pw, "scale", Vector2(1.06, 0.94), 0.05)
		drop.tween_property(pw, "scale", Vector2.ONE, 0.10)
		await drop.finished
	else:
		# Reduce Motion still has to SHOW the coin — it is the one honest look
		# the whole game rests on. Snap the helm up, hold it, snap it back.
		pw.position = _shell_slots[1] + Vector2(0, -56)
		await get_tree().create_timer(0.8).timeout
		if _shell_root == null or not is_instance_valid(_shell_root):
			return
		pw.position = _shell_slots[1]
	if _shell_root == null or not is_instance_valid(_shell_root):
		return
	if _shell_coin != null and is_instance_valid(_shell_coin):
		_shell_coin.visible = false
	AudioBank.play_sfx("bone_settle", 0.06, -6.0)
	await get_tree().create_timer(0.25).timeout
	var n: int = int(_shell_cfg.get("swaps", 7))
	for s in range(n):
		if _shell_root == null or not is_instance_valid(_shell_root):
			return
		var a := randi() % 3
		var b := (a + 1 + randi() % 2) % 3
		await _shell_swap(a, b,
			lerpf(0.44, 0.28, float(s) / maxf(1.0, float(n - 1))))
	_shell_busy = false
	_arm_shell_rows()


func _shell_swap(slot_a: int, slot_b: int, dur: float) -> void:
	var ha: Control = _shell_helms[_shell_order[slot_a]]
	var hb: Control = _shell_helms[_shell_order[slot_b]]
	var pa: Vector2 = _shell_slots[slot_a]
	var pb: Vector2 = _shell_slots[slot_b]
	var tmp: int = _shell_order[slot_a]
	_shell_order[slot_a] = _shell_order[slot_b]
	_shell_order[slot_b] = tmp
	AudioBank.play_sfx("helm_slide", 0.08, -8.0)
	if UserSettings.reduce_motion:
		ha.position = pb
		hb.position = pa
		await get_tree().create_timer(maxf(dur, 0.40)).timeout
		return
	# One passes in front (dips toward the player), one behind — the cross
	# reads as hands moving, not a teleport.
	ha.z_index = 1
	hb.z_index = 0
	var ta := ha.create_tween()
	ta.tween_property(ha, "position", pa.lerp(pb, 0.5) + Vector2(0, 16), dur * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ta.tween_property(ha, "position", pb, dur * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tb := hb.create_tween()
	tb.tween_property(hb, "position", pa.lerp(pb, 0.5) + Vector2(0, -14), dur * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tb.tween_property(hb, "position", pa, dur * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Waited out on the TREE, not on `ta.finished`. A tween made by
	# `ha.create_tween()` is bound to `ha`, and a bound tween that dies with its
	# node is KILLED, not finished — `finished` never emits. So leaving the shell
	# game mid-shuffle (the player answers, backs out, or the scene is torn down)
	# parked this coroutine and its caller forever, holding the helm Controls
	# alive; two of the leaked function states behind the 2026-09-03 UI-gate exit
	# crash were exactly this. The tween runs dur*0.5 twice, so the tree timer
	# expires on the same beat, and it fires whether or not `ha` outlives it.
	await get_tree().create_timer(dur + 0.05).timeout


## After the shuffle the ladder gets its accessible duplicates — one row
## per SLOT, same handlers as the helmet clicks.
func _arm_shell_rows() -> void:
	if _shell_vbox == null or not is_instance_valid(_shell_vbox):
		return
	var names := ["Lift the left helmet", "Lift the middle helmet",
		"Lift the right helmet"]
	for slot in range(3):
		var helm_idx: int = _shell_order[slot]
		var sub := ""
		if helm_idx == _shell_dent_helm:
			sub = "This is the dented helmet."
		_shell_vbox.add_child(_make_frameless_choice(names[slot], sub, "",
			64, _on_shell_pick.bind(helm_idx)))


func _show_shell_coin(slot: int) -> void:
	if _shell_coin == null or not is_instance_valid(_shell_coin):
		return
	_shell_coin.position = _shell_slots[slot] + Vector2(60, 82)
	_shell_coin.visible = true


func _on_shell_pick(helm_idx: int) -> void:
	if _shell_busy:
		return
	_shell_busy = true
	var wrap: Control = _shell_helms[helm_idx]
	var win: bool = helm_idx == _shell_prize_helm
	var slot: int = _shell_order.find(helm_idx)
	var rm := UserSettings.reduce_motion
	AudioBank.play_sfx("card_play", 0.05, -4.0)
	# The lift is INFORMATIONAL — the coin sits UNDER the helms in the draw
	# order, so a helm that never rises hides the verdict entirely. Reduce
	# Motion snaps to the lifted end state instead of skipping it.
	if is_instance_valid(wrap):
		if rm:
			wrap.position = _shell_slots[slot] + Vector2(0, -52)
			wrap.rotation = 0.10 if slot < 2 else -0.10
		else:
			var up := wrap.create_tween()
			up.tween_property(wrap, "position",
				_shell_slots[slot] + Vector2(0, -52), 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			up.parallel().tween_property(wrap, "rotation",
				0.10 if slot < 2 else -0.10, 0.22)
			await up.finished
	if win:
		_show_shell_coin(slot)
		_sting("coin")
		if not rm and _shell_root != null and is_instance_valid(_shell_root):
			Motion.burst(self, _shell_root.get_global_position()
				+ _shell_slots[slot] + Vector2(77, 86), "coin_spark")
		await get_tree().create_timer(0.55).timeout
		# Honesty on the house: the other two lift empty before he pays.
		for h in range(3):
			if h != helm_idx and is_instance_valid(_shell_helms[h]):
				var os: int = _shell_order.find(h)
				if rm:
					(_shell_helms[h] as Control).position = \
						_shell_slots[os] + Vector2(0, -40)
					continue
				var ot: Tween = (_shell_helms[h] as Control).create_tween()
				ot.tween_property(_shell_helms[h], "position",
					_shell_slots[os] + Vector2(0, -40), 0.20) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.60).timeout
		var receipt := _gamble_pay(_shell_cfg, true,
			int(_shell_cfg.get("payout", 0)), "coin_pour")
		_win_flourish()
		_show_result(_combine_lines([_shell_text("win_text",
			"Correct. Won {payout} gold."), receipt]))
	else:
		await get_tree().create_timer(0.45).timeout
		# The honest reveal: he lifts the right one himself.
		var pslot: int = _shell_order.find(_shell_prize_helm)
		var pw: Control = _shell_helms[_shell_prize_helm]
		if is_instance_valid(pw):
			if rm:
				pw.position = _shell_slots[pslot] + Vector2(0, -44)
			else:
				var pu := pw.create_tween()
				pu.tween_property(pw, "position",
					_shell_slots[pslot] + Vector2(0, -44), 0.20) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_show_shell_coin(pslot)
		_sting("hit_hero", -4.0)
		await get_tree().create_timer(0.75).timeout
		var lose_receipt := _gamble_pay(_shell_cfg, false, 0)
		_show_result(_combine_lines([_shell_text("lose_text",
			"Wrong helmet. You lost the stake."), lose_receipt]))


# ── The Short Straw (straw_game) — misère Nim against the dead watch ─────
# A real strategy game, honest by construction: every straw is on the
# table, the count prints big, and there is NO roll anywhere. The dead play
# PERFECT misère Nim (take 1–3; the last straw stands the watch), and the
# opening count only ever deals first-player-winnable positions (never
# ≡ 1 mod 4) — so the game is a learnable puzzle: perfect play always
# wins, one blunder and the dead never let you back in. You take from the
# RIGHT end of the row; hovering telegraphs the exact straws a click would
# take. Both sides' spent straws pile at their edge of the plate, so the
# whole history stays readable. Ladder rows (take one/two/three) are the
# accessible duplicates of the same handler. Config:
#   {counts: [..], win_effects: [..], lose_effects: [..],
#    open_text, win_text, lose_text, seen_texts} — texts take {count}.

var _straw_cfg: Dictionary = {}
var _straw_count: int = 0
var _straw_nodes: Array = []      # live straws, left→right
var _straw_taken: int = 0         # retired to either pile (pile jitter seed)
var _straw_root: Control = null
var _straw_figure: Label = null
var _straw_status: Label = null
var _straw_busy := true


func _straw_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_straw_cfg, key,
		String(_straw_cfg.get(key, fallback)))
	return raw.replace("{count}", str(_straw_count))


func _start_straw_game(effect: Dictionary) -> void:
	_straw_cfg = effect
	var counts: Array = effect.get("counts", [12, 14, 15, 16])
	_straw_count = int(counts[randi() % counts.size()])
	_straw_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_straw_text("open_text",
			"There are {count} straws. Take 1, 2, or 3. Whoever takes the last straw loses."), 3)
	_build_straw_stage()
	var row_labels := ["Take one straw", "Take two straws", "Take three straws"]
	for k in range(1, 4):
		vbox.add_child(_make_frameless_choice(row_labels[k - 1], "", "", 56,
			_on_straw_take.bind(k)))
	_straw_busy = false


func _build_straw_stage() -> void:
	_straw_nodes = []
	_straw_taken = 0
	var root := Control.new()
	root.name = "StrawStage"
	root.position = Vector2(860, 210)
	root.size = Vector2(560, 430)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_straw_root = root
	var patch := CastPatch.new()
	patch.seed_text = "watch_" + _event_id
	patch.chalk = "line"
	patch.position = Vector2(10, 60)
	patch.size = Vector2(540, 340)
	root.add_child(patch)
	# The row, centered in the light pool; you draw from the RIGHT end.
	var start_x := 270.0 - float(_straw_count - 1) * 14.0
	for i in range(_straw_count):
		var s := BoneStraw.new()
		s.seed_text = "straw_%d_%s" % [i, _event_id]
		s.size = Vector2(16, 76)
		s.pivot_offset = Vector2(8, 38)
		s.position = Vector2(start_x + float(i) * 28.0 + fmod(float(i) * 3.7, 4.0) - 10.0,
			178.0 + fmod(float(i) * 2.3, 9.0))
		s.rotation = fmod(float(i) * 0.83, 0.16) - 0.08
		root.add_child(s)
		_straw_nodes.append(s)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.offset_left = -6.0
		btn.offset_right = 6.0
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.pressed.connect(_on_straw_clicked.bind(s))
		btn.mouse_entered.connect(_on_straw_hover.bind(s))
		btn.mouse_exited.connect(_clear_straw_lights)
		s.add_child(btn)
	# The honest arithmetic: the count prints big in the plate's far shadow.
	var figure := Label.new()
	figure.text = str(_straw_count)
	figure.add_theme_font_size_override("font_size", 42)
	figure.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	figure.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	figure.add_theme_constant_override("outline_size", 5)
	if GameTheme.font_display:
		figure.add_theme_font_override("font", GameTheme.font_display)
	figure.position = Vector2(350, 78)
	figure.size = Vector2(170, 52)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(figure)
	_straw_figure = figure
	var status := Label.new()
	status.text = "THE LIVING DRAW FIRST"
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
	status.position = Vector2(320, 132)
	status.size = Vector2(230, 24)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	_straw_status = status
	GameTheme.attach_rich_hover(patch, "The drawing",
		"Take 1, 2, or 3 straws. Whoever takes the last straw loses.",
		"Click a straw to take it and every straw to its right.", Color(0.92, 0.88, 0.80), 1.0)


func _on_straw_hover(s: Control) -> void:
	if _straw_busy:
		return
	_clear_straw_lights()
	var j := _straw_nodes.find(s)
	if j < 0:
		return
	var k := _straw_nodes.size() - j
	if k > 3:
		return
	for i in range(j, _straw_nodes.size()):
		_straw_nodes[i].lit = true
		_straw_nodes[i].queue_redraw()


func _clear_straw_lights() -> void:
	for s in _straw_nodes:
		if is_instance_valid(s) and s.lit:
			s.lit = false
			s.queue_redraw()


func _on_straw_clicked(s: Control) -> void:
	var j := _straw_nodes.find(s)
	if j < 0:
		return
	var k := _straw_nodes.size() - j
	if k > 3:
		return
	_on_straw_take(k)


## Perfect misère play: leave the mover a count ≡ 1 (mod 4); from a lost
## position, stall with one straw and wait for the blunder.
func _straw_ai_take() -> int:
	if _straw_count == 1:
		return 1
	var r := (_straw_count - 1) % 4
	return 1 if r == 0 else r


func _retire_straws(k: int, to_dead: bool) -> void:
	var rm := UserSettings.reduce_motion
	AudioBank.play_sfx("bone_settle", 0.08, -6.0)
	for i in range(k):
		if _straw_nodes.is_empty():
			break
		var s = _straw_nodes.pop_back()
		if not is_instance_valid(s):
			continue
		var n := _straw_taken
		_straw_taken += 1
		var dest: Vector2
		var rot: float
		if to_dead:
			dest = Vector2(44.0 + fmod(float(n) * 13.0, 34.0),
				84.0 + fmod(float(n) * 7.0, 20.0))
			rot = -1.45 + fmod(float(n) * 0.37, 0.24)
		else:
			dest = Vector2(420.0 + fmod(float(n) * 13.0, 34.0),
				330.0 + fmod(float(n) * 7.0, 20.0))
			rot = 1.45 - fmod(float(n) * 0.37, 0.24)
		if rm:
			s.position = dest
			s.rotation = rot
		else:
			var tw: Tween = s.create_tween()
			tw.tween_interval(0.07 * i)
			tw.tween_property(s, "position", dest, 0.26) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_property(s, "rotation", rot, 0.26)
	await get_tree().create_timer(0.34 if rm else 0.30 + 0.07 * k).timeout


func _update_straw_hud(caption: String) -> void:
	if _straw_figure != null and is_instance_valid(_straw_figure):
		_straw_figure.text = str(_straw_count)
	if _straw_status != null and is_instance_valid(_straw_status):
		_straw_status.text = caption


func _on_straw_take(k: int) -> void:
	if _straw_busy or _straw_count <= 0:
		return
	k = clampi(k, 1, mini(3, _straw_count))
	_straw_busy = true
	_clear_straw_lights()
	await _retire_straws(k, false)
	_straw_count -= k
	_update_straw_hud("THEIR DRAW")
	if _straw_root == null or not is_instance_valid(_straw_root):
		return
	if _straw_count <= 0:
		await _finish_straw_game(false)
		return
	await get_tree().create_timer(0.65).timeout
	if _straw_root == null or not is_instance_valid(_straw_root):
		return
	var ai_k := _straw_ai_take()
	await _retire_straws(ai_k, true)
	_straw_count -= ai_k
	_update_straw_hud("YOUR DRAW")
	if _straw_count <= 0:
		await _finish_straw_game(true)
		return
	_straw_busy = false


func _finish_straw_game(win: bool) -> void:
	_update_straw_hud("ROUND OVER")
	await get_tree().create_timer(0.55).timeout
	# The arm this whole funnel was generalised FROM (see `_gamble_pay`).
	var receipt := _gamble_pay(_straw_cfg, win, 0)
	if win:
		_sting("coin")
		_win_flourish()
	else:
		_sting("hit_hero", -4.0)
	_show_result(_combine_lines([
		_straw_text("win_text",
			"The corporal takes the last straw. You win.") if win
		else _straw_text("lose_text",
			"You take the last straw. You lose."),
		receipt]))


# ── The Courier's Satchel (sack_game) — the counting game ────────────────
# Informed push-your-luck: draw bone pay-chits (three each of 1–6) from the
# drowned courier's satchel toward the target; the TallySlate chalks what's
# still in the bag after every draw, so the odds are never hidden — only
# unread. Bust over the target loses the stake; stopping pays by tier.
# Bake then shade: each chit comes off the real multiset before it
# animates. Config:
#   {stake, target (13), pay: [[floor, gold] high→low], open_text,
#    win_text, perfect_text, flat_text, bust_text, broke_text, seen_texts}
#   — texts take {stake} / {sum} / {pay} / {target}.

var _sack_cfg: Dictionary = {}
var _sack_bag: Array = []
var _sack_sum := 0
var _sack_drawn := 0
var _sack_root: Control = null
var _sack_slate: Control = null
var _sack_figure: Label = null
var _sack_busy := true


func _sack_text(key: String, fallback: String, pay: int = 0) -> String:
	var raw := _seen_text_override(_sack_cfg, key,
		String(_sack_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_sack_cfg.get("stake", 0)))) \
		.replace("{sum}", str(_sack_sum)).replace("{pay}", str(pay)) \
		.replace("{target}", str(int(_sack_cfg.get("target", 13))))


func _start_sack_game(effect: Dictionary) -> void:
	_sack_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_sack_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	_sack_bag = []
	for v in range(1, 7):
		for _i in range(3):
			_sack_bag.append(v)
	_sack_sum = 0
	_sack_drawn = 0
	_sack_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_sack_text("open_text",
			"Draw cards toward {target}. Stop at any time. Going over loses the stake."), 2)
	_build_sack_stage()
	vbox.add_child(_make_frameless_choice("Draw a token",
		"Draw toward {target}. Do not go over.".replace("{target}",
			str(int(effect.get("target", 13)))),
		"The satchel is colder than the evening is.", 74, _on_sack_draw))
	vbox.add_child(_make_frameless_choice("Stop and take the reward",
		"Stop now. Totals closer to {target} pay more.".replace("{target}",
			str(int(effect.get("target", 13)))),
		"Stop now and take the reward for your total.", 74, _on_sack_stop))
	_sack_busy = false


func _build_sack_stage() -> void:
	var root := Control.new()
	root.name = "SackStage"
	root.position = Vector2(860, 210)
	root.size = Vector2(560, 430)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_sack_root = root
	var patch := CastPatch.new()
	patch.seed_text = "bank_" + _event_id
	patch.position = Vector2(10, 60)
	patch.size = Vector2(540, 340)
	root.add_child(patch)
	var sack := PaySack.new()
	sack.seed_text = "sack_" + _event_id
	sack.position = Vector2(36, 240)
	sack.size = Vector2(150, 144)
	root.add_child(sack)
	var sack_btn := Button.new()
	sack_btn.flat = true
	sack_btn.focus_mode = Control.FOCUS_NONE
	sack_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	sack_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	sack_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		sack_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	sack_btn.pressed.connect(_on_sack_draw)
	var sack_wrap := Control.new()
	sack_wrap.position = sack.position
	sack_wrap.size = sack.size
	sack_wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(sack_wrap)
	sack_wrap.add_child(sack_btn)
	GameTheme.attach_rich_hover(sack_wrap, "The satchel",
		"Draw one card and add it to your total.", "Click to draw",
		Color(0.92, 0.88, 0.80), 1.04)
	var slate := TallySlate.new()
	slate.seed_text = "slate_" + _event_id
	slate.position = Vector2(316, 66)
	slate.size = Vector2(214, 106)
	root.add_child(slate)
	_sack_slate = slate
	var figure := Label.new()
	figure.text = "0"
	figure.add_theme_font_size_override("font_size", 42)
	figure.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	figure.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	figure.add_theme_constant_override("outline_size", 5)
	if GameTheme.font_display:
		figure.add_theme_font_override("font", GameTheme.font_display)
	figure.position = Vector2(46, 78)
	figure.size = Vector2(150, 52)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(figure)
	_sack_figure = figure


func _sack_update_slate() -> void:
	if _sack_slate == null or not is_instance_valid(_sack_slate):
		return
	var counts: Array = [0, 0, 0, 0, 0, 0]
	for v in _sack_bag:
		counts[int(v) - 1] += 1
	_sack_slate.remaining = counts
	_sack_slate.queue_redraw()
	if _sack_figure != null and is_instance_valid(_sack_figure):
		_sack_figure.text = str(_sack_sum)


func _on_sack_draw() -> void:
	if _sack_busy or _sack_bag.is_empty():
		return
	_sack_busy = true
	# Bake: the chit leaves the real multiset before anything moves.
	var v: int = _sack_bag.pop_at(randi() % _sack_bag.size())
	_sack_sum += v
	var tok := PayToken.new()
	tok.seed_text = "chit_%d_%s" % [_sack_drawn, _event_id]
	tok.value = v
	tok.size = Vector2(46, 46)
	tok.pivot_offset = Vector2(23, 23)
	var dest := Vector2(206.0 + float(_sack_drawn % 6) * 54.0,
		184.0 + float(_sack_drawn / 6) * 54.0)
	_sack_drawn += 1
	if _sack_root != null and is_instance_valid(_sack_root):
		_sack_root.add_child(tok)
		if UserSettings.reduce_motion:
			tok.position = dest
			await get_tree().create_timer(0.35).timeout
		else:
			tok.position = Vector2(96, 258)
			tok.scale = Vector2(0.4, 0.4)
			var mid := tok.position.lerp(dest, 0.5) + Vector2(0, -46)
			var tw := tok.create_tween()
			tw.tween_property(tok, "position", mid, 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(tok, "scale", Vector2.ONE, 0.16)
			tw.tween_property(tok, "position", dest, 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(tok, "scale", Vector2(1.18, 0.84), 0.05)
			tw.tween_property(tok, "scale", Vector2.ONE, 0.10) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			await tw.finished
	AudioBank.play_sfx("bone_settle", 0.08, -7.0)
	_sack_update_slate()
	if _sack_sum > int(_sack_cfg.get("target", 13)):
		await get_tree().create_timer(0.55).timeout
		var bust_receipt := _gamble_pay(_sack_cfg, false, 0)
		_show_result(_combine_lines([_sack_text("bust_text",
			"Your total is {sum}, above the target. You lost the stake."),
			bust_receipt]))
		_bust_feedback()
		return
	_sack_busy = false


func _on_sack_stop() -> void:
	if _sack_busy:
		return
	_sack_busy = true
	var pay := 0
	for tier in _sack_cfg.get("pay", [[13, 80], [12, 55], [11, 40], [8, 20]]):
		if _sack_sum >= int(tier[0]):
			pay = int(tier[1])
			break
	if pay > 0:
		var receipt := _gamble_pay(_sack_cfg, true, pay)
		_win_flourish()
		# The satchel's terminal prize: stop holding at least the posted count
		# and the courier's own keepsake rides out with the pay.
		var rid := _gamble_bank_relic(_sack_cfg, pay)
		if rid != "":
			receipt = _combine_lines([receipt,
				_sack_text("bank_relic_text",
					"Gained relic: %s." % RelicDB.get_relic(rid).name, pay)])
		if _sack_sum == int(_sack_cfg.get("target", 13)):
			_show_result(_combine_lines([_sack_text("perfect_text",
				"Exact total: {sum}. Gained {pay} gold.", pay), receipt]))
		else:
			_show_result(_combine_lines([_sack_text("win_text",
				"Stopped at {sum}. Gained {pay} gold.", pay), receipt]))
	else:
		var flat_receipt := _gamble_pay(_sack_cfg, false, 0)
		_show_result(_combine_lines([_sack_text("flat_text",
			"Stopped at {sum}, below the minimum reward. You lost the stake."),
			flat_receipt]))


# ── The Wheel of the Fourth (wheel_game) — back a colour, spin the wheel ──
# Roulette, retold as the sappers' painted fortune-wheel: three runners' colours
# divide the wheel into equal slices, each runner owning as many slices as its
# odds are short (the favourite owns half the wheel; the longshot, one slice).
# HONEST BY CONSTRUCTION: every slice is the SAME size and the winning slice is
# picked UNIFORMLY, so a runner's chance is exactly its share of the wheel —
# which you can read at a glance by counting its colour. Back one, spin, and
# the wheel lands where it lands. Bigger colour = safer = pays less.
#   Config: {stake, runners:[{name,mult,weight,tint,blurb}], open_text,
#            win_text, lose_text, broke_text, seen_texts} — texts take {stake}.

var _wheel_cfg: Dictionary = {}
var _wheel_runners: Array = []
var _wheel_slice_runner: Array = []   # slice index → runner index
var _wheel_stake := 0
var _wheel_bet := -1
var _wheel_busy := true
var _wheel_root: Control = null
var _wheel_rows: VBoxContainer = null
var _wheel_caption: Label = null
var _wheel_result_lbl: Label = null
var _wheel: FortuneWheel = null


func _wheel_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_wheel_cfg, key,
		String(_wheel_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(_wheel_stake))


func _start_wheel_game(effect: Dictionary) -> void:
	_wheel_cfg = effect
	_wheel_stake = int(effect.get("stake", 0))
	if _wheel_stake > 0 and RunState.gold < _wheel_stake:
		_show_result(_wheel_text("broke_text",
			"You need {stake} gold to play."))
		return
	if _wheel_stake > 0:
		RunState.gold -= _wheel_stake
	_wheel_runners = effect.get("runners", [
		{"name": "Old Crown", "mult": 2, "weight": 3, "tint": Color(0.85, 0.68, 0.25)},
		{"name": "Widow's Mite", "mult": 3, "weight": 2, "tint": Color(0.58, 0.52, 0.66)},
		{"name": "Little Fourth", "mult": 5, "weight": 1, "tint": Color(0.80, 0.32, 0.20)},
	])
	_wheel_bet = -1
	_wheel_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_wheel_text("open_text",
			"Choose a color, then spin. More wheel spaces mean a better chance but a smaller reward."), 4)
	_wheel_rows = VBoxContainer.new()
	_wheel_rows.add_theme_constant_override("separation", 12)
	vbox.add_child(_wheel_rows)
	_build_wheel_stage()
	_wheel_busy = false
	_wheel_arm_rows()


func _build_wheel_stage() -> void:
	# Expand each runner into `weight` equal slices, round-robin interleaved so
	# the colours spread around the wheel instead of clustering into big arcs.
	var segments: Array = []
	_wheel_slice_runner = []
	var remaining: Array = []
	for r in _wheel_runners:
		remaining.append(maxi(1, int(r.get("weight", 1))))
	var guard := 0
	while guard < 64:
		var any := false
		for ri in range(_wheel_runners.size()):
			if int(remaining[ri]) > 0:
				any = true
				var r: Dictionary = _wheel_runners[ri]
				segments.append({"tint": r.get("tint", Color(0.8, 0.7, 0.4)),
					"weight": 1.0, "label": String(r.get("name", ""))})
				_wheel_slice_runner.append(ri)
				remaining[ri] = int(remaining[ri]) - 1
		if not any:
			break
		guard += 1
	var root := Control.new()
	root.name = "WheelStage"
	root.position = Vector2(860, 200)
	root.size = Vector2(560, 450)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_wheel_root = root
	var patch := CastPatch.new()
	patch.seed_text = "wheel_" + _event_id
	patch.position = Vector2(10, 56)
	patch.size = Vector2(540, 356)
	root.add_child(patch)
	var caption := Label.new()
	caption.text = "BACK A COLOUR, THEN SPIN"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	caption.position = Vector2(30, 66)
	caption.size = Vector2(500, 24)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_wheel_caption = caption
	var wheel := FortuneWheel.new()
	wheel.seed_text = "wheel_" + _event_id
	wheel.segments = segments
	wheel.position = Vector2(140, 84)
	wheel.size = Vector2(260, 290)
	root.add_child(wheel)
	_wheel = wheel
	var res := Label.new()
	res.add_theme_font_size_override("font_size", 17)
	res.add_theme_color_override("font_color", Color(0.84, 0.78, 0.64))
	res.position = Vector2(30, 380)
	res.size = Vector2(500, 24)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(res)
	_wheel_result_lbl = res
	_stage_entrance(root)
	GameTheme.attach_rich_hover(patch, "The sappers' fortune-wheel",
		"Choose a color, then spin. The number of wheel spaces shows its chance. Smaller sections pay more.",
		"Back a colour, then spin the wheel", Color(0.90, 0.84, 0.68), 1.0)


func _wheel_slices_for(runner_idx: int) -> int:
	var n := 0
	for ri in _wheel_slice_runner:
		if int(ri) == runner_idx:
			n += 1
	return n


func _wheel_arm_rows() -> void:
	if _wheel_rows == null or not is_instance_valid(_wheel_rows):
		return
	_wheel_busy = false
	for ch in _wheel_rows.get_children():
		ch.queue_free()
	var total := _wheel_slice_runner.size()
	for ri in range(_wheel_runners.size()):
		var r: Dictionary = _wheel_runners[ri]
		var slices := _wheel_slices_for(ri)
		_wheel_rows.add_child(_make_frameless_choice(
			"Back %s" % String(r.get("name", "")),
			"Pays %dx; covers %d of %d spaces." % [int(r.get("mult", 2)), slices, total],
			"", 52, _on_wheel_bet.bind(ri)))


func _on_wheel_bet(runner_idx: int) -> void:
	if _wheel_busy:
		return
	_wheel_busy = true
	_wheel_bet = runner_idx
	for ch in _wheel_rows.get_children():
		ch.queue_free()
	var r: Dictionary = _wheel_runners[runner_idx]
	if _wheel_caption != null and is_instance_valid(_wheel_caption):
		_wheel_caption.text = "SPINNING ON THE %s…" % String(r.get("name", "")).to_upper()
	# Bake the result: a uniform slice → weight-proportional runner odds.
	var winner_slice := randi() % maxi(1, _wheel_slice_runner.size())
	await _wheel_spin_to(winner_slice)
	var winner_runner := int(_wheel_slice_runner[winner_slice])
	if _wheel != null and is_instance_valid(_wheel):
		_wheel.highlight_index = winner_slice
	var won := winner_runner == _wheel_bet
	var wname := String(_wheel_runners[winner_runner].get("name", ""))
	if _wheel_result_lbl != null and is_instance_valid(_wheel_result_lbl):
		_wheel_result_lbl.text = "THE WHEEL STOPS ON THE %s" % wname.to_upper()
	await get_tree().create_timer(0.7).timeout
	if won:
		var pay := _wheel_stake * int(_wheel_runners[winner_runner].get("mult", 2))
		var receipt := _gamble_pay(_wheel_cfg, true, pay, "coin_pour")
		if _wheel != null and is_instance_valid(_wheel):
			_win_flourish(_wheel.get_global_position() + _wheel.size * 0.5)
		else:
			_win_flourish()
		_show_result(_combine_lines([_wheel_text("win_text",
			"The wheel landed on %s. Won %d gold." % [wname, pay]), receipt]))
	else:
		_sting("hit_hero", -6.0)
		_bust_feedback()
		var lose_receipt := _gamble_pay(_wheel_cfg, false, 0)
		_show_result(_combine_lines([_wheel_text("lose_text",
			"The wheel landed on %s. You lost the stake." % wname),
			lose_receipt]))


func _wheel_spin_to(winner_slice: int) -> void:
	if _wheel == null or not is_instance_valid(_wheel):
		return
	var target := _wheel.center_angle_of(winner_slice)
	if UserSettings.reduce_motion:
		_wheel.angle = target
		_wheel.queue_redraw()
		await get_tree().create_timer(0.6).timeout
		return
	AudioBank.play_sfx("bone_settle", 0.06, -4.0)
	var start := _wheel.angle
	var final := start + TAU * 4.0
	final += fposmod(target - final, TAU)
	# FortuneWheel.angle has a redraw setter, so tween the property directly.
	var t := _wheel.create_tween()
	t.tween_property(_wheel, "angle", final, 2.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	AudioBank.play_sfx("coin", 0.05, -8.0)


# ── The Burial Fund (tali_game) — the Venus throw, one recast each ───────
# The keep-and-recast game (dice poker's ancestor, played with the real
# Roman tali): both throws land OPEN, the rank table is chalked on a
# slate, and each side gets ONE recast. The skill is the slate itself —
# with four-faced bones the true odds defy poker instinct (four alike is
# the rarest throw; CROSSED PIKES genuinely outrank THE COLUMN — count
# the ways), so reading the table's law beats playing by feel. The
# signifer's recast is a posted drill: he keeps whatever rank is made
# and throws the rest, never chasing. Ties break on total pips; dead
# level is a wash. Winning WITH Venus pays double — the fund can afford
# beauty. Bake-then-shade throughout: every face is decided before its
# tumble. Config:
#   {stake, payout, venus_pay, open_text, win_text, venus_text,
#    lose_text, wash_text, broke_text, seen_texts}
#   — texts take {stake} / {pay} / {yours} / {his}.

const TALI_RANKS := ["THE WALL", "VENUS", "CROSSED PIKES", "THE COLUMN", "THE FILE"]
const TALI_GLYPHS := [[2, 2, 2, 2], [1, 2, 3, 4], [2, 2, 3, 3], [3, 3, 3, 1],
	[2, 2, 1, 4]]

var _tali_cfg: Dictionary = {}
var _tali_mine: Array = []
var _tali_his: Array = []
var _tali_keep: Array = []
var _tali_root: Control = null
var _tali_rows: VBoxContainer = null
var _tali_my_dice: Array = []      # wrap Controls (die child 0), clickable
var _tali_his_dice: Array = []     # bare dice
var _tali_my_caption: Label = null
var _tali_his_caption: Label = null
var _tali_chalk: Label = null
var _tali_busy := true


func _tali_text(key: String, fallback: String, pay: int = 0, yours := "",
		his := "") -> String:
	var raw := _seen_text_override(_tali_cfg, key,
		String(_tali_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_tali_cfg.get("stake", 0)))) \
		.replace("{pay}", str(pay)).replace("{yours}", yours) \
		.replace("{his}", his)


## Rank a four-tali throw. Lower index = higher rank, ordered by what the
## bones actually do: 4 alike (1.6%) > all different (9.4%) > two pair
## (14%) > three alike (18.8%) > one pair (56%).
func _tali_rank(arr: Array) -> Dictionary:
	var counts := [0, 0, 0, 0]
	var pips := 0
	for v in arr:
		counts[int(v) - 1] += 1
		pips += int(v)
	var shape: Array = []
	for n in counts:
		if int(n) > 0:
			shape.append(int(n))
	shape.sort()
	shape.reverse()
	var idx := 4
	if shape == [4]:
		idx = 0
	elif shape == [1, 1, 1, 1]:
		idx = 1
	elif shape == [2, 2]:
		idx = 2
	elif shape == [3, 1]:
		idx = 3
	return {"idx": idx, "name": TALI_RANKS[idx], "pips": pips}


## The drill keep: hold whatever rank is made, throw the rest. Never chase.
func _tali_drill_keep(arr: Array) -> Array:
	var counts := [0, 0, 0, 0]
	for v in arr:
		counts[int(v) - 1] += 1
	var idx := int(_tali_rank(arr)["idx"])
	if idx <= 2:
		return [true, true, true, true]
	# Column or File: keep the multiple, recast the strays.
	var keep_face := 0
	for f in range(4):
		if counts[f] >= 2 and (keep_face == 0 or counts[f] > counts[keep_face - 1]):
			keep_face = f + 1
	var out: Array = []
	for v in arr:
		out.append(int(v) == keep_face)
	return out


func _start_tali_game(effect: Dictionary) -> void:
	_tali_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_tali_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	_tali_mine = []
	_tali_his = []
	for _i in range(4):
		_tali_mine.append(randi_range(1, 4))
		_tali_his.append(randi_range(1, 4))
	_tali_keep = _tali_drill_keep(_tali_mine)
	_tali_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_tali_text("open_text",
			"The opponent rolls openly. Select bones to keep, then reroll the rest once."), 2)
	_tali_rows = VBoxContainer.new()
	_tali_rows.add_theme_constant_override("separation", 12)
	vbox.add_child(_tali_rows)
	_build_tali_stage()
	_tali_run_intro()


func _build_tali_stage() -> void:
	_tali_my_dice = []
	_tali_his_dice = []
	var root := Control.new()
	root.name = "TaliStage"
	root.position = Vector2(860, 210)
	root.size = Vector2(560, 430)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_tali_root = root
	var patch := CastPatch.new()
	patch.seed_text = "fund_" + _event_id
	patch.chalk = "ring"
	patch.position = Vector2(10, 60)
	patch.size = Vector2(540, 340)
	root.add_child(patch)
	# His throw, far side — open from the first.
	for i in range(4):
		var d := KnuckleboneDie.new()
		d.seed_text = "sig_%d_%s" % [i, _event_id]
		d.face = int(_tali_his[i])
		d.size = Vector2(30, 30)
		d.pivot_offset = Vector2(15, 15)
		d.position = Vector2(-40, 120)
		root.add_child(d)
		_tali_his_dice.append(d)
		d.set_meta("dest", Vector2(38.0 + float(i) * 52.0, 124.0))
	var his_cap := Label.new()
	his_cap.text = "HIS THROW"
	his_cap.add_theme_font_size_override("font_size", 15)
	his_cap.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
	his_cap.position = Vector2(30, 90)
	his_cap.size = Vector2(280, 22)
	his_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(his_cap)
	_tali_his_caption = his_cap
	# Your throw, near side — each bone a toggle: standing = kept.
	for i in range(4):
		var wrap := Control.new()
		wrap.position = Vector2(34.0 + float(i) * 58.0, 282.0)
		wrap.size = Vector2(38, 38)
		wrap.pivot_offset = Vector2(19, 19)
		wrap.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(wrap)
		_tali_my_dice.append(wrap)
		var d := KnuckleboneDie.new()
		d.seed_text = "own_%d_%s" % [i, _event_id]
		d.face = int(_tali_mine[i])
		d.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(d)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.pressed.connect(_on_tali_bone.bind(i))
		wrap.add_child(btn)
		GameTheme.attach_rich_hover(wrap, "Keep or recast",
			"Raised bones will be kept. Lowered bones will be rerolled.",
			"Click to toggle", Color(0.92, 0.88, 0.80), 1.04)
	var my_cap := Label.new()
	my_cap.text = "YOURS"
	my_cap.add_theme_font_size_override("font_size", 15)
	my_cap.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
	my_cap.position = Vector2(30, 338)
	my_cap.size = Vector2(300, 22)
	my_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(my_cap)
	_tali_my_caption = my_cap
	# The verdict chalk, center field — empty until the ranks stand.
	var chalk := Label.new()
	chalk.text = ""
	chalk.add_theme_font_size_override("font_size", 24)
	chalk.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	chalk.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	chalk.add_theme_constant_override("outline_size", 5)
	if GameTheme.font_display:
		chalk.add_theme_font_override("font", GameTheme.font_display)
	chalk.position = Vector2(30, 192)
	chalk.size = Vector2(290, 36)
	chalk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chalk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chalk)
	_tali_chalk = chalk
	# The table's law, chalked where both sides can read it.
	var slate := ChalkSlate.new()
	slate.seed_text = "law_" + _event_id
	slate.position = Vector2(334, 72)
	slate.size = Vector2(208, 252)
	root.add_child(slate)
	var head := Label.new()
	head.text = "THE TABLE'S LAW"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.85, 0.86, 0.82, 0.9))
	head.position = Vector2(346, 84)
	head.size = Vector2(184, 18)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	for r in range(5):
		var glyphs: Array = TALI_GLYPHS[r]
		for j in range(4):
			var g := KnuckleboneDie.new()
			g.seed_text = "law_%d_%d_%s" % [r, j, _event_id]
			g.face = int(glyphs[j])
			g.size = Vector2(18, 18)
			g.position = Vector2(346.0 + float(j) * 20.0,
				108.0 + float(r) * 38.0)
			root.add_child(g)
		var rname := Label.new()
		rname.text = TALI_RANKS[r].capitalize()
		rname.add_theme_font_size_override("font_size", 16)
		rname.add_theme_color_override("font_color", Color(0.85, 0.86, 0.82, 0.9))
		rname.position = Vector2(432.0, 109.0 + float(r) * 38.0)
		rname.size = Vector2(104, 18)
		rname.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(rname)
	var pays := Label.new()
	pays.text = "VENUS PAYS DOUBLE"
	pays.add_theme_font_size_override("font_size", 16)
	pays.add_theme_color_override("font_color", Color(0.85, 0.86, 0.82, 0.75))
	pays.position = Vector2(346, 298)
	pays.size = Vector2(184, 16)
	pays.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pays)
	var slate_hover := Control.new()
	slate_hover.position = slate.position
	slate_hover.size = slate.size
	slate_hover.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(slate_hover)
	# The five ranks are TALI_RANKS, and the slate beside this hover prints them
	# by those names — the old line invented a sixth ("High", impossible on four
	# tali: every throw is at least a pair) and renamed two others.
	GameTheme.attach_rich_hover(slate_hover, "The table's law",
		"Hands rank from rarest to commonest: The Wall, Venus, Crossed Pikes, The Column, The File.",
		"Ties use total pips. Exact ties return the stake.",
		Color(0.85, 0.86, 0.82), 1.0)


func _tali_run_intro() -> void:
	var rm := UserSettings.reduce_motion
	AudioBank.play_sfx("bone_cast", 0.06, -4.0)
	if rm:
		for d in _tali_his_dice:
			if is_instance_valid(d):
				d.position = d.get_meta("dest")
		await get_tree().create_timer(0.6).timeout
	else:
		for i in range(_tali_his_dice.size()):
			var d = _tali_his_dice[i]
			if is_instance_valid(d):
				_tumble_die(d, {"face": int(_tali_his[i]), "skull": false},
					d.get_meta("dest"), 0.08 * i, 1.0)
		await get_tree().create_timer(1.2).timeout
	if _tali_root == null or not is_instance_valid(_tali_root):
		return
	_tali_update_captions()
	_tali_mark_keeps()
	_tali_busy = false
	_tali_arm_rows()


func _tali_update_captions() -> void:
	var rh := _tali_rank(_tali_his)
	var rm := _tali_rank(_tali_mine)
	if _tali_his_caption != null and is_instance_valid(_tali_his_caption):
		_tali_his_caption.text = "HIS THROW — %s" % String(rh["name"])
	if _tali_my_caption != null and is_instance_valid(_tali_my_caption):
		var kept := 0
		for k in _tali_keep:
			if k:
				kept += 1
		_tali_my_caption.text = "YOURS — %s · KEEPING %d" % [String(rm["name"]), kept]


func _tali_mark_keeps() -> void:
	for i in range(_tali_my_dice.size()):
		var wrap = _tali_my_dice[i]
		if not is_instance_valid(wrap):
			continue
		var kept: bool = bool(_tali_keep[i])
		wrap.modulate = Color(1.18, 1.14, 1.02) if kept else Color(0.68, 0.66, 0.62)
		wrap.position.y = 276.0 if kept else 288.0


func _on_tali_bone(i: int) -> void:
	if _tali_busy:
		return
	_tali_keep[i] = not bool(_tali_keep[i])
	AudioBank.play_sfx("button_click")
	_tali_mark_keeps()
	_tali_update_captions()
	_tali_arm_rows()


func _tali_arm_rows() -> void:
	if _tali_rows == null or not is_instance_valid(_tali_rows):
		return
	for c in _tali_rows.get_children():
		c.queue_free()
	var kept := 0
	for k in _tali_keep:
		if k:
			kept += 1
	if kept < 4:
		_tali_rows.add_child(_make_frameless_choice("Throw the rest",
			"Keep %d and reroll %d. You have one reroll." % [
				kept, 4 - kept],
			"", 56, _on_tali_throw))
	_tali_rows.add_child(_make_frameless_choice("Stand pat",
		"The throw as it lies: %s." % String(_tali_rank(_tali_mine)["name"]).capitalize(),
		"", 56, _on_tali_stand))


func _on_tali_throw() -> void:
	if _tali_busy:
		return
	_tali_busy = true
	if _tali_rows != null and is_instance_valid(_tali_rows):
		for c in _tali_rows.get_children():
			c.queue_free()
	var rm := UserSettings.reduce_motion
	AudioBank.play_sfx("bone_cast", 0.06, -4.0)
	for i in range(4):
		if bool(_tali_keep[i]):
			continue
		# Bake, then recast the bone in place. The wrap can't ride
		# _tumble_die (that stamps face/skull on its target, and the wrap
		# is a plain Control), so the wrap hops here and the child die
		# flickers-then-stamps on the same clock via _tali_stamp_later.
		_tali_mine[i] = randi_range(1, 4)
		var wrap = _tali_my_dice[i]
		if wrap == null or not is_instance_valid(wrap):
			continue
		var die = wrap.get_child(0)
		if die == null or not is_instance_valid(die):
			continue
		if rm:
			die.face = int(_tali_mine[i])
			die.queue_redraw()
		else:
			var home := Vector2(34.0 + float(i) * 58.0, 276.0)
			wrap.position = home + Vector2(-12, 66)
			var tw: Tween = wrap.create_tween()
			tw.tween_interval(0.08 * i)
			tw.tween_property(wrap, "position", home + Vector2(-4, -30), 0.22) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(wrap, "position", home, 0.20) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(wrap, "scale", Vector2(1.16, 0.84), 0.05)
			tw.tween_property(wrap, "scale", Vector2.ONE, 0.10) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tali_stamp_later(die, int(_tali_mine[i]))
	await get_tree().create_timer(0.6 if rm else 1.15).timeout
	if _tali_root == null or not is_instance_valid(_tali_root):
		return
	# The keep phase is over; the four stand as thrown, uniformly.
	_tali_keep = [true, true, true, true]
	_tali_mark_keeps()
	_tali_update_captions()
	await _tali_his_drill()


func _on_tali_stand() -> void:
	if _tali_busy:
		return
	_tali_busy = true
	if _tali_rows != null and is_instance_valid(_tali_rows):
		for c in _tali_rows.get_children():
			c.queue_free()
	# All four stand as they lie.
	_tali_keep = [true, true, true, true]
	_tali_mark_keeps()
	await _tali_his_drill()


## The recast bone's airborne flicker: every look shows another side, then
## the baked truth stamps with the settle clack.
func _tali_stamp_later(die: Control, truth: int) -> void:
	for _j in range(4):
		await get_tree().create_timer(0.105).timeout
		if not is_instance_valid(die):
			return
		die.face = randi_range(1, 4)
		die.queue_redraw()
	await get_tree().create_timer(0.05).timeout
	if not is_instance_valid(die):
		return
	die.face = truth
	die.queue_redraw()


func _tali_his_drill() -> void:
	var keep := _tali_drill_keep(_tali_his)
	var thrown := 0
	for k in keep:
		if not k:
			thrown += 1
	var rm := UserSettings.reduce_motion
	if thrown == 0:
		if _tali_his_caption != null and is_instance_valid(_tali_his_caption):
			_tali_his_caption.text = "HIS THROW — %s · HE STANDS" \
				% String(_tali_rank(_tali_his)["name"])
		await get_tree().create_timer(0.8).timeout
	else:
		if _tali_his_caption != null and is_instance_valid(_tali_his_caption):
			_tali_his_caption.text = "HE KEEPS %s, THROWS %d" % [
				String(_tali_rank(_tali_his)["name"]), thrown]
		await get_tree().create_timer(0.9).timeout
		if _tali_root == null or not is_instance_valid(_tali_root):
			return
		AudioBank.play_sfx("bone_cast", 0.06, -6.0)
		for i in range(4):
			if bool(keep[i]):
				continue
			_tali_his[i] = randi_range(1, 4)
			var d = _tali_his_dice[i]
			if d == null or not is_instance_valid(d):
				continue
			if rm:
				d.face = int(_tali_his[i])
				d.queue_redraw()
			else:
				d.position += Vector2(-12, -40)
				_tumble_die(d, {"face": int(_tali_his[i]), "skull": false},
					Vector2(38.0 + float(i) * 52.0 - 18.0, 124.0), 0.08 * i, 1.0)
		await get_tree().create_timer(0.6 if rm else 1.25).timeout
	if _tali_root == null or not is_instance_valid(_tali_root):
		return
	await _tali_verdict()


func _tali_verdict() -> void:
	_tali_update_captions()
	var rme := _tali_rank(_tali_mine)
	var rhe := _tali_rank(_tali_his)
	var yours := String(rme["name"]).capitalize()
	var his := String(rhe["name"]).capitalize()
	var win: bool = int(rme["idx"]) < int(rhe["idx"]) \
		or (int(rme["idx"]) == int(rhe["idx"]) and int(rme["pips"]) > int(rhe["pips"]))
	var lose: bool = int(rhe["idx"]) < int(rme["idx"]) \
		or (int(rme["idx"]) == int(rhe["idx"]) and int(rhe["pips"]) > int(rme["pips"]))
	# The winning row answers, bone by bone.
	if not UserSettings.reduce_motion:
		var row: Array = _tali_my_dice if win else _tali_his_dice
		if win or lose:
			for d in row:
				if not is_instance_valid(d):
					continue
				var pu: Tween = d.create_tween()
				pu.tween_property(d, "scale", Vector2(1.28, 1.28), 0.09) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				pu.tween_property(d, "scale", Vector2.ONE, 0.14)
				AudioBank.play_sfx("bone_settle", 0.08, -10.0)
				await get_tree().create_timer(0.14).timeout
				if _tali_root == null or not is_instance_valid(_tali_root):
					return
	if _tali_chalk != null and is_instance_valid(_tali_chalk):
		if win:
			_tali_chalk.text = "%s TAKES THE FUND" % String(rme["name"])
		elif lose:
			_tali_chalk.text = "%s HOLDS" % String(rhe["name"])
		else:
			_tali_chalk.text = "DEAD LEVEL"
	await get_tree().create_timer(1.0).timeout
	if win:
		var venus: bool = int(rme["idx"]) == 1
		var pay: int = int(_tali_cfg.get("venus_pay",
			int(_tali_cfg.get("payout", 0)) * 2)) if venus \
			else int(_tali_cfg.get("payout", 0))
		var receipt := _gamble_pay(_tali_cfg, true, pay, "coin_pour")
		_win_flourish()
		if venus:
			_show_result(_combine_lines([_tali_text("venus_text",
				"Venus beats {his}. Gained {pay} gold.",
				pay, yours, his), receipt]))
		else:
			_show_result(_combine_lines([_tali_text("win_text",
				"{yours} beats {his}. Gained {pay} gold.",
				pay, yours, his), receipt]))
	elif lose:
		_sting("hit_hero", -4.0)
		_bust_feedback()
		var lose_receipt := _gamble_pay(_tali_cfg, false, 0)
		_show_result(_combine_lines([_tali_text("lose_text",
			"{his} beats {yours}. You lost the stake.",
			0, yours, his), lose_receipt]))
	else:
		var stake_refund := int(_tali_cfg.get("stake", 0))
		if stake_refund > 0:
			RunState.gain_gold(stake_refund)
		_show_result(_tali_text("wash_text",
			"{yours} ties {his}. Your stake was returned.",
			0, yours, his))


# ── The Proving Ground (field_game) — the sappers' sand-table exam ───────
# Minesweeper as a one-decision-per-file crossing: five files of raked
# sand, three pinches of powder buried at the deal (NEVER two in one
# file — posted), and every safe step chalks its own count of charges in
# the eight cells around it. The whole game is informed push-your-luck:
# the numbers accrue as you cross, a zero clears every neighbor, and you
# may lift your marker between steps and take the tier your files have
# earned. A charge ends the exam — the stake drowns, the pinch of powder
# is real (posted HP singe), and the honest show flags every remaining
# charge before the page turns. Bake-then-shade: the whole field is laid
# at the deal; the steps only discover it. The blue seat's `scout` flag
# chalks one charge before the first step. Config:
#   {stake, charges: 3, singe: 3, pay: [0,10,25,45,65,90], scout: bool,
#    open_text, win_text, bank_text, bust_text, broke_text, seen_texts}
#   — texts take {stake} / {pay} / {files}.

const FIELD_COLS := 5
const FIELD_ROWS := 3

var _field_cfg: Dictionary = {}
var _field_mines: Array = []       # per column: mined row, or -1
var _field_col := 0                # next file to step (0-based)
var _field_root: Control = null
var _field_rows_box: VBoxContainer = null
var _field_cells: Array = []       # [col][row] wrap Controls
var _field_caption: Label = null
var _field_busy := true


func _field_text(key: String, fallback: String, pay: int = 0) -> String:
	var raw := _seen_text_override(_field_cfg, key,
		String(_field_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_field_cfg.get("stake", 0)))) \
		.replace("{pay}", str(pay)).replace("{files}", str(_field_col))


func _field_mine_at(c: int) -> int:
	if c < 0 or c >= _field_mines.size():
		return -1
	return int(_field_mines[c])


func _field_count(c: int, r: int) -> int:
	var n := 0
	for dc in range(-1, 2):
		var mr := _field_mine_at(c + dc)
		if mr < 0:
			continue
		if dc == 0 and mr == r:
			continue
		if absi(mr - r) <= 1 and not (dc == 0 and mr == r):
			n += 1
	return n


func _start_field_game(effect: Dictionary) -> void:
	_field_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_field_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	# Lay the field: charges in distinct files, never two in one.
	var cols := [0, 1, 2, 3, 4]
	cols.shuffle()
	_field_mines = [-1, -1, -1, -1, -1]
	for i in range(clampi(int(effect.get("charges", 3)), 1, FIELD_COLS)):
		_field_mines[int(cols[i])] = randi() % FIELD_ROWS
	_field_col = 0
	_field_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_field_text("open_text",
			"Choose one cell in each column. A safe cell shows how many charges touch it. Stop after a safe step to collect."), 4)
	_field_rows_box = VBoxContainer.new()
	_field_rows_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_field_rows_box)
	_build_field_stage()
	_field_busy = false
	_field_arm_rows()


func _build_field_stage() -> void:
	_field_cells = []
	var root := Control.new()
	root.name = "FieldStage"
	root.position = Vector2(860, 210)
	root.size = Vector2(560, 430)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_field_root = root
	var patch := CastPatch.new()
	patch.seed_text = "exam_" + _event_id
	patch.position = Vector2(10, 60)
	patch.size = Vector2(540, 340)
	root.add_child(patch)
	# Chalked start and finish lines — the march reads left to right.
	for x in [86.0, 474.0]:
		var line := ColorRect.new()
		line.color = Color(0.88, 0.88, 0.84, 0.30)
		line.position = Vector2(x, 138)
		line.size = Vector2(3, 214)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(line)
	var caption := Label.new()
	caption.text = "COLUMN 1 OF %d - %d CHARGES - ONE PER COLUMN" % [
		FIELD_COLS, clampi(int(_field_cfg.get("charges", 3)), 1, FIELD_COLS)]
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
	caption.position = Vector2(30, 84)
	caption.size = Vector2(500, 24)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_field_caption = caption
	# The pay ledger, chalked at the near edge.
	var pay: Array = _field_cfg.get("pay", [0, 10, 25, 45, 65, 90])
	var ledger := Label.new()
	var parts: Array = []
	for i in range(1, pay.size()):
		parts.append(str(int(pay[i])))
	ledger.text = "FILES PAY: " + " · ".join(parts)
	ledger.add_theme_font_size_override("font_size", 15)
	ledger.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55))
	ledger.position = Vector2(30, 366)
	ledger.size = Vector2(500, 20)
	ledger.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ledger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ledger)
	for c in range(FIELD_COLS):
		var col_cells: Array = []
		for r in range(FIELD_ROWS):
			var wrap := Control.new()
			wrap.position = Vector2(96.0 + float(c) * 74.0,
				142.0 + float(r) * 70.0)
			wrap.size = Vector2(66, 62)
			wrap.pivot_offset = Vector2(33, 31)
			wrap.mouse_filter = Control.MOUSE_FILTER_PASS
			root.add_child(wrap)
			col_cells.append(wrap)
			var cell := FieldCell.new()
			cell.seed_text = "cell_%d_%d_%s" % [c, r, _event_id]
			cell.set_anchors_preset(Control.PRESET_FULL_RECT)
			wrap.add_child(cell)
			var btn := Button.new()
			btn.flat = true
			btn.focus_mode = Control.FOCUS_NONE
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for st in ["normal", "hover", "pressed", "focus"]:
				btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			btn.pressed.connect(_on_field_step.bind(c, r))
			wrap.add_child(btn)
		_field_cells.append(col_cells)
	# The derby crowd's scout: one charge chalked before the first step.
	if bool(_field_cfg.get("scout", false)):
		var mined: Array = []
		for c in range(FIELD_COLS):
			if _field_mine_at(c) >= 0:
				mined.append(c)
		if not mined.is_empty():
			var sc: int = mined[randi() % mined.size()]
			var w = _field_cells[sc][_field_mine_at(sc)]
			if is_instance_valid(w):
				var painter = w.get_child(0)
				painter.flagged = true
				painter.queue_redraw()
	_stage_entrance(root)
	GameTheme.attach_rich_hover(patch, "The sand table",
		"Move one cell per column from left to right. A safe cell shows the number of nearby charges.",
		"Click a cell in the next column.", Color(0.92, 0.88, 0.80), 1.0)


func _field_arm_rows() -> void:
	if _field_rows_box == null or not is_instance_valid(_field_rows_box):
		return
	for c in _field_rows_box.get_children():
		c.queue_free()
	var lanes := ["Step the high path", "Step the center", "Step the low path"]
	for r in range(FIELD_ROWS):
		_field_rows_box.add_child(_make_frameless_choice(lanes[r],
			"File %d of %d." % [_field_col + 1, FIELD_COLS], "", 52,
			_on_field_step.bind(_field_col, r)))
	if _field_col > 0:
		var pay: Array = _field_cfg.get("pay", [0, 10, 25, 45, 65, 90])
		var tier: int = int(pay[clampi(_field_col, 0, pay.size() - 1)])
		_field_rows_box.add_child(_make_frameless_choice("Lift your marker",
			"Take %d gold for %s crossed." % [tier,
				"one file" if _field_col == 1 else "%d files" % _field_col],
			"", 52, _on_field_bank))


func _on_field_step(c: int, r: int) -> void:
	if _field_busy or c != _field_col:
		return
	_field_busy = true
	var wrap = _field_cells[c][r]
	AudioBank.play_sfx("bone_settle", 0.08, -8.0)
	if _field_mine_at(c) == r:
		# The pinch goes off. Bake-then-shade: the ledger settles first.
		var singe: int = int(_field_cfg.get("singe", 3))
		var receipt := _combine_lines([
			_apply_effect_list([{"type": "damage", "value": singe}]),
			_gamble_pay(_field_cfg, false, 0)])
		if is_instance_valid(wrap):
			var painter = wrap.get_child(0)
			painter.state = "blown"
			painter.queue_redraw()
		if not UserSettings.reduce_motion and _field_root != null \
				and is_instance_valid(_field_root):
			Motion.burst(self, _field_root.get_global_position()
				+ wrap.position + Vector2(33, 26), "impact")
		AudioBank.play_sfx("hit_hero", 0.05, -4.0)
		# The honest show: every remaining charge uncovered.
		for cc in range(FIELD_COLS):
			var mr := _field_mine_at(cc)
			if mr < 0 or (cc == c and mr == r):
				continue
			var mw = _field_cells[cc][mr]
			if is_instance_valid(mw):
				var mp = mw.get_child(0)
				if mp.state == "hidden":
					mp.state = "charge"
					mp.queue_redraw()
		if _field_caption != null and is_instance_valid(_field_caption):
			_field_caption.text = "THE FIELD KEEPS THE FEE"
		await get_tree().create_timer(1.5).timeout
		_bust_feedback()
		_show_result(_combine_lines([_field_text("bust_text",
			"You stepped on a charge. You lost the entry fee."), receipt]))
		return
	# Safe: the sand presses flat and the count chalks itself.
	if is_instance_valid(wrap):
		var painter = wrap.get_child(0)
		painter.state = "stepped"
		painter.queue_redraw()
		var num := Label.new()
		num.text = str(_field_count(c, r))
		num.add_theme_font_size_override("font_size", 22)
		num.add_theme_color_override("font_color", Color(0.93, 0.93, 0.89))
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		num.add_theme_constant_override("outline_size", 4)
		if GameTheme.font_display:
			num.add_theme_font_override("font", GameTheme.font_display)
		num.set_anchors_preset(Control.PRESET_FULL_RECT)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(num)
		if not UserSettings.reduce_motion:
			var pu: Tween = wrap.create_tween()
			pu.tween_property(wrap, "scale", Vector2(1.10, 0.92), 0.07)
			pu.tween_property(wrap, "scale", Vector2.ONE, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_field_col += 1
	await get_tree().create_timer(0.55).timeout
	if _field_root == null or not is_instance_valid(_field_root):
		return
	if _field_col >= FIELD_COLS:
		var pay: Array = _field_cfg.get("pay", [0, 10, 25, 45, 65, 90])
		var full: int = int(pay[pay.size() - 1])
		var receipt := _gamble_pay(_field_cfg, true, full, "coin_pour")
		# The exam's terminal prize: cross the whole field and the ground's own
		# commendation rides out with the fee.
		var frid := _gamble_bank_relic(_field_cfg, full)
		if frid != "":
			receipt = _combine_lines([receipt,
				_field_text("bank_relic_text",
					"Gained relic: %s." % RelicDB.get_relic(frid).name, full)])
		_win_flourish()
		if _field_caption != null and is_instance_valid(_field_caption):
			_field_caption.text = "THE FIELD IS CROSSED"
		await get_tree().create_timer(0.7).timeout
		_show_result(_combine_lines([_field_text("win_text",
			"You crossed all five columns safely. Gained {pay} gold.", full),
			receipt]))
		return
	if _field_caption != null and is_instance_valid(_field_caption):
		_field_caption.text = "FILE %d OF %d · THE COUNT IS CHALKED" % [
			_field_col + 1, FIELD_COLS]
	_field_busy = false
	_field_arm_rows()


func _on_field_bank() -> void:
	if _field_busy or _field_col <= 0:
		return
	_field_busy = true
	var pay: Array = _field_cfg.get("pay", [0, 10, 25, 45, 65, 90])
	var tier: int = int(pay[clampi(_field_col, 0, pay.size() - 1)])
	# An early stop earns its TIER, never the whole prize — a pot game's
	# terminal payoff is `bank_relic_at`, which reads the tier it stopped on.
	var receipt := _gamble_pay(_field_cfg, true, tier) if tier > 0 else ""
	var rid := _gamble_bank_relic(_field_cfg, tier)
	if rid != "":
		receipt = _combine_lines([receipt,
			_field_text("bank_relic_text",
				"Gained relic: %s." % RelicDB.get_relic(rid).name, tier)])
	_show_result(_combine_lines([_field_text("bank_text",
		"Stopped after crossing %s. Gained {pay} gold."
		% ("one file" if _field_col == 1 else "{files} files"), tier),
		receipt]))


# ── Crown & Pike (crown_game) — back a mark, cast the three dice ─────────
# Crown-and-Anchor, retold on the Old King's gaming board: six bold marks
# (Crown · Pike · Skull · Banner · Coin · Wheel), each a distinct SILHOUETTE
# and a distinct colour so it can never be mistaken (the fix for the drum
# game's four identical heads IS the game). Back one mark, cast three dice;
# every die that shows your mark multiplies the pot, and you may bank it or
# let it ride for another cast. HONEST BY CONSTRUCTION: three fair d6 rolled
# fresh each cast, the results baked before the tumble is shown, and the
# printed pay-table (·1 hit ×2, ·2 hits ×3, ·triple ×4) is exactly what pays.
#   Config: {stake, open_text, win_text, bust_text, broke_text, seen_texts}
#           — texts take {stake}/{pot}.

var _cap_cfg: Dictionary = {}
var _cap_pot := 0
var _cap_base := 0                  # the original stake, for text
var _cap_mark := -1                 # backed symbol 0..5, -1 none
var _cap_casts := 0
var _cap_busy := true
var _cap_root: Control = null
var _cap_rows: VBoxContainer = null
var _cap_caption: Label = null
var _cap_pot_lbl: Label = null
var _cap_pads: Array = []           # per mark: {"wrap":Control,"ring":Panel}
var _cap_dice: Array = []           # 3 {"die":PipDie,"pip":WarPip}

const CAP_NAMES := ["Crown", "Pike", "Skull", "Banner", "Coin", "Wheel"]
const CAP_TINTS := [
	Color(0.90, 0.74, 0.30),   # Crown  — gold
	Color(0.52, 0.66, 0.84),   # Pike   — steel blue
	Color(0.84, 0.82, 0.74),   # Skull  — bone
	Color(0.82, 0.34, 0.29),   # Banner — crimson
	Color(0.40, 0.72, 0.56),   # Coin   — verdigris
	Color(0.68, 0.53, 0.82),   # Wheel  — violet
]


func _cap_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_cap_cfg, key,
		String(_cap_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_cap_cfg.get("stake", 0)))) \
		.replace("{pot}", str(_cap_pot))


func _start_crown_game(effect: Dictionary) -> void:
	_cap_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_cap_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	_cap_base = maxi(stake, 1)
	_cap_pot = _cap_base
	_cap_mark = -1
	_cap_casts = 0
	_cap_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_cap_text("open_text",
			"Choose one symbol, then roll three dice. Matching dice multiply the pot. No matches lose it."), 4)
	_cap_rows = VBoxContainer.new()
	_cap_rows.add_theme_constant_override("separation", 12)
	vbox.add_child(_cap_rows)
	_build_crown_stage()
	_cap_busy = false


func _build_crown_stage() -> void:
	_cap_pads = []
	_cap_dice = []
	var root := Control.new()
	root.name = "CrownStage"
	root.position = Vector2(860, 200)
	root.size = Vector2(560, 450)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_cap_root = root
	var patch := CastPatch.new()
	patch.seed_text = "crown_" + _event_id
	patch.chalk = "court"
	patch.position = Vector2(10, 56)
	patch.size = Vector2(540, 356)
	root.add_child(patch)
	var caption := Label.new()
	caption.text = "TAP A MARK TO BACK IT"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	caption.position = Vector2(30, 72)
	caption.size = Vector2(500, 24)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_cap_caption = caption
	# The six betting marks, one row across the top of the board.
	for i in range(6):
		var wrap := Control.new()
		wrap.position = Vector2(24.0 + float(i) * 90.0, 104.0)
		wrap.size = Vector2(62, 62)
		wrap.pivot_offset = Vector2(31, 31)
		wrap.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(wrap)
		# Selection ring (hidden until backed).
		var ring := Panel.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0, 0, 0, 0)
		rs.border_color = CAP_TINTS[i]
		rs.set_border_width_all(3)
		rs.set_corner_radius_all(10)
		ring.add_theme_stylebox_override("panel", rs)
		ring.position = Vector2(-6, -6)
		ring.size = Vector2(74, 74)
		ring.visible = false
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(ring)
		var pip := WarPip.new()
		pip.kind = i
		pip.tint = CAP_TINTS[i]
		pip.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(pip)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.pressed.connect(_on_crown_mark.bind(i))
		_stage_touchable(wrap, btn)
		wrap.add_child(btn)
		var nm := Label.new()
		nm.text = CAP_NAMES[i]
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", CAP_TINTS[i])
		nm.position = Vector2(-14, 64)
		nm.size = Vector2(90, 18)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(nm)
		_cap_pads.append({"wrap": wrap, "ring": ring})
	# The three dice, cup-cast in the centre of the board.
	for j in range(3):
		var dwrap := Control.new()
		dwrap.position = Vector2(126.0 + float(j) * 112.0, 208.0)
		dwrap.size = Vector2(84, 84)
		dwrap.pivot_offset = Vector2(42, 42)
		dwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(dwrap)
		var die := PipDie.new()
		die.seed_text = "capdie_%d_%s" % [j, _event_id]
		die.blank = true
		die.set_anchors_preset(Control.PRESET_FULL_RECT)
		dwrap.add_child(die)
		var pip := WarPip.new()
		pip.kind = 0
		pip.visible = false
		# The symbol sits inside the die's inset cell.
		pip.position = Vector2(15, 15)
		pip.size = Vector2(54, 54)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dwrap.add_child(pip)
		_cap_dice.append({"die": die, "pip": pip})
	var pot := Label.new()
	pot.add_theme_font_size_override("font_size", 18)
	pot.add_theme_color_override("font_color", Color(0.86, 0.76, 0.44))
	pot.position = Vector2(30, 306)
	pot.size = Vector2(500, 24)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pot)
	_cap_pot_lbl = pot
	var pay := Label.new()
	pay.text = "MATCHES:  1 = x2    2 = x3    3 = x4"
	pay.add_theme_font_size_override("font_size", 14)
	pay.add_theme_color_override("font_color", Color(0.70, 0.64, 0.52))
	pay.position = Vector2(30, 336)
	pay.size = Vector2(500, 20)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pay)
	_cap_refresh_pot()
	_stage_entrance(root)
	GameTheme.attach_rich_hover(patch, "The Old King's gaming board",
		"Choose a symbol and roll. Matching dice multiply the pot; no matches lose it. After a win, collect or roll again.",
		"Back a mark, then cast the dice", Color(0.90, 0.84, 0.68), 1.0)


func _cap_refresh_pot() -> void:
	if _cap_pot_lbl == null or not is_instance_valid(_cap_pot_lbl):
		return
	if _cap_mark < 0:
		_cap_pot_lbl.text = "POT  %d GOLD  ·  back a mark" % _cap_pot
	else:
		_cap_pot_lbl.text = "POT  %d GOLD  ·  on the %s" % [
			_cap_pot, CAP_NAMES[_cap_mark]]


func _on_crown_mark(i: int) -> void:
	if _cap_busy:
		return
	_cap_mark = i
	for k in range(_cap_pads.size()):
		var ring = _cap_pads[k]["ring"]
		if is_instance_valid(ring):
			ring.visible = (k == i)
	AudioBank.play_sfx("coin", 0.05, -10.0)
	if _cap_caption != null and is_instance_valid(_cap_caption):
		_cap_caption.text = "BACKED THE %s — CAST WHEN READY" % CAP_NAMES[i].to_upper()
	_cap_refresh_pot()
	# The marks stay live after a winning cast, so re-backing here must NOT drop
	# back to the pre-cast row set — that took "Bank the pot" off the board and
	# left a won pot with no exit but another cast. A cast has happened iff we
	# are in the after-win state: a bust ends the game on _show_result.
	_cap_arm_rows(_cap_casts > 0)


func _cap_arm_rows(after_win: bool = false) -> void:
	if _cap_rows == null or not is_instance_valid(_cap_rows):
		return
	_cap_busy = false
	for ch in _cap_rows.get_children():
		ch.queue_free()
	if after_win:
		_cap_rows.add_child(_make_frameless_choice("Bank the pot",
			"Take %d gold off the board and walk." % _cap_pot, "", 52, _on_crown_bank))
		_cap_rows.add_child(_make_frameless_choice("Let it ride",
			"Cast again on the %s. The whole %d rides on it." % [
				CAP_NAMES[_cap_mark], _cap_pot], "", 52, _on_crown_cast))
	elif _cap_mark >= 0:
		_cap_rows.add_child(_make_frameless_choice("Cast the dice",
			"Roll the three dice on the %s." % CAP_NAMES[_cap_mark], "", 52,
			_on_crown_cast))


func _on_crown_cast() -> void:
	if _cap_busy or _cap_mark < 0:
		return
	_cap_busy = true
	_cap_casts += 1
	for ch in _cap_rows.get_children():
		ch.queue_free()
	var results := [randi() % 6, randi() % 6, randi() % 6]
	if _cap_caption != null and is_instance_valid(_cap_caption):
		_cap_caption.text = "CASTING…"
	await _cap_tumble(results)
	var matches := 0
	for j in range(3):
		if results[j] == _cap_mark:
			matches += 1
			var d = _cap_dice[j]["die"]
			if is_instance_valid(d):
				d.lit = true
				d.accent = CAP_TINTS[_cap_mark]
				d.queue_redraw()
	if matches == 0:
		# Bust — the pot is lost.
		if _cap_caption != null and is_instance_valid(_cap_caption):
			_cap_caption.text = "NO %s — THE POT IS LOST" % CAP_NAMES[_cap_mark].to_upper()
		_cap_pot = 0
		_cap_refresh_pot()
		await get_tree().create_timer(0.6).timeout
		_sting("hit_hero", -6.0)
		_bust_feedback()
		var bust_receipt := _gamble_pay(_cap_cfg, false, 0)
		_show_result(_combine_lines([_cap_text("bust_text",
			"No dice matched %s. You lost the pot." % CAP_NAMES[_cap_mark]),
			bust_receipt]))
		return
	# Win — grow the pot.
	_cap_pot *= (1 + matches)
	_pulse_crown_mark()
	_cap_refresh_pot()
	var word: String = ["", "ONE", "TWO", "THREE"][matches]
	if _cap_caption != null and is_instance_valid(_cap_caption):
		_cap_caption.text = "%s %s — POT NOW %d" % [word,
			CAP_NAMES[_cap_mark].to_upper() + ("S" if matches > 1 else ""), _cap_pot]
	_sting("coin" if matches < 3 else "coin_pour", -3.0)
	if matches >= 2:
		_win_flourish()
	await get_tree().create_timer(0.7).timeout
	_cap_arm_rows(true)


func _cap_tumble(results: Array) -> void:
	# Bake-then-shade: results are already decided; this is pure theatre.
	if UserSettings.reduce_motion:
		for j in range(3):
			_cap_land_die(j, int(results[j]))
		await get_tree().create_timer(0.6).timeout
		return
	# Blank the dice and rattle them.
	for entry in _cap_dice:
		entry["die"].blank = true
		entry["die"].lit = false
		entry["die"].queue_redraw()
		entry["pip"].visible = false
	AudioBank.play_sfx("bone_settle", 0.08, -4.0)
	for _r in range(5):
		for entry in _cap_dice:
			var w = entry["die"].get_parent()
			if is_instance_valid(w):
				w.position.y += randf_range(-2.0, 2.0)
		await get_tree().create_timer(0.09).timeout
	# Stagger the landings, left to right.
	for j in range(3):
		_cap_land_die(j, int(results[j]))
		AudioBank.play_sfx("bone_settle", 0.05, -6.0, 1.05)
		await get_tree().create_timer(0.18).timeout


func _cap_land_die(j: int, face: int) -> void:
	if j < 0 or j >= _cap_dice.size():
		return
	var die = _cap_dice[j]["die"]
	var pip = _cap_dice[j]["pip"]
	if is_instance_valid(die):
		die.blank = false
		die.queue_redraw()
	if is_instance_valid(pip):
		pip.kind = face
		pip.tint = CAP_TINTS[face]
		pip.visible = true
		pip.queue_redraw()
	if not UserSettings.reduce_motion and is_instance_valid(die):
		var w = die.get_parent()
		if is_instance_valid(w):
			var tw: Tween = w.create_tween()
			tw.tween_property(w, "scale", Vector2(1.12, 1.12), 0.07)
			tw.tween_property(w, "scale", Vector2.ONE, 0.14) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _pulse_crown_mark() -> void:
	if _cap_mark < 0 or _cap_mark >= _cap_pads.size():
		return
	if UserSettings.reduce_motion:
		return
	var wrap = _cap_pads[_cap_mark]["wrap"]
	if is_instance_valid(wrap):
		var tw: Tween = wrap.create_tween()
		# The house PUNCH: QUAD-out on the way up, BACK-out home. Only the
		# return carried its easing, so the pop itself grew at constant rate —
		# a punch with no impact in it, which is the half a player feels.
		tw.tween_property(wrap, "scale", Vector2(1.18, 1.18), 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(wrap, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_crown_bank() -> void:
	var receipt := _gamble_pay(_cap_cfg, true, _cap_pot) if _cap_pot > 0 else ""
	# Ride the pot past the posted mark and the drummer's own keepsake leaves
	# with it — the terminal prize this pot game never had.
	var rid := _gamble_bank_relic(_cap_cfg, _cap_pot)
	if rid != "":
		receipt = _combine_lines([receipt, _cap_text("bank_relic_text",
			"Gained relic: %s." % RelicDB.get_relic(rid).name)])
	_show_result(_combine_lines([_cap_text("win_text",
		"Collected {pot} gold."), receipt]))


# ── The Quartermaster's Scale (scale_game) — find the false pay-token ─────
# The deductive-weighing puzzle: N pay-tokens, one debased LIGHT by the Old
# King's mint, found on a balance in a fixed number of weighings, then
# named. HONEST BY CONSTRUCTION: the counterfeit is baked at the first
# breath, and every weighing reports the true comparison — the beam tips
# decisively toward the heavier pan (a real balance does, however small the
# difference), and BALANCED means the false coin is off the scale or split
# even. A running weighings-log keeps the deduction in the open. Naming
# correctly pays a base plus a bonus for every weighing you SAVED (a bold
# early call pays more; a wrong call loses the stake).
#   Config: {stake, coins: 9, weighings: 3, base: 30, per_saved: 12,
#            open_text, win_text, poor_text, broke_text, seen_texts}
#            — texts take {stake} / {pay} / {used}.

var _scale_cfg: Dictionary = {}
var _scale_n := 9
var _scale_fake := 0                # baked counterfeit index (the light one)
var _scale_assign: Array = []       # per coin: 0 off, -1 left pan, +1 right
var _scale_used := 0
var _scale_max := 3
var _scale_pay := 0
var _scale_accusing := false
var _scale_root: Control = null
var _scale_rows: VBoxContainer = null
var _scale_beam = null              # BalanceScale painter
var _scale_caption: Label = null
var _scale_log_label: Label = null
var _scale_log: Array = []
var _scale_marks: Array = []        # per-coin L/R/· marker Labels
var _scale_busy := true


func _scale_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_scale_cfg, key,
		String(_scale_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_scale_cfg.get("stake", 0)))) \
		.replace("{pay}", str(_scale_pay)).replace("{used}", str(_scale_used))


func _start_scale_game(effect: Dictionary) -> void:
	_scale_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_scale_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	_scale_n = clampi(int(effect.get("coins", 9)), 3, 12)
	_scale_fake = randi() % _scale_n
	_scale_assign = []
	for _i in range(_scale_n):
		_scale_assign.append(0)
	_scale_used = 0
	_scale_max = int(effect.get("weighings", 3))
	_scale_pay = 0
	_scale_accusing = false
	_scale_log = []
	_scale_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_scale_text("open_text",
			"One coin is lighter. Place coins on both pans and weigh them, then choose the light coin. Fewer weighings pay more."), 4)
	_scale_rows = VBoxContainer.new()
	_scale_rows.add_theme_constant_override("separation", 12)
	vbox.add_child(_scale_rows)
	_build_scale_stage()
	_scale_busy = false
	_scale_arm_rows()


func _build_scale_stage() -> void:
	_scale_marks = []
	var root := Control.new()
	root.name = "ScaleStage"
	root.position = Vector2(860, 200)
	root.size = Vector2(560, 450)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_scale_root = root
	var patch := CastPatch.new()
	patch.seed_text = "scale_" + _event_id
	patch.position = Vector2(10, 56)
	patch.size = Vector2(540, 356)
	root.add_child(patch)
	var caption := Label.new()
	caption.text = "WEIGHING 1 OF %d · SET THE PANS" % _scale_max
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	caption.position = Vector2(30, 78)
	caption.size = Vector2(500, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_scale_caption = caption
	var beam := BalanceScale.new()
	beam.position = Vector2(110, 96)
	beam.size = Vector2(340, 158)
	root.add_child(beam)
	_scale_beam = beam
	# The weighings log — the deduction, kept in the open on the table.
	var log_lbl := Label.new()
	log_lbl.text = ""
	log_lbl.add_theme_font_size_override("font_size", 15)
	log_lbl.add_theme_color_override("font_color", Color(0.74, 0.68, 0.56))
	log_lbl.position = Vector2(30, 250)
	log_lbl.size = Vector2(500, 20)
	log_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_lbl)
	_scale_log_label = log_lbl
	# The pay-token row: click to cycle a coin off → left pan → right pan.
	var step := 490.0 / float(_scale_n)
	for i in range(_scale_n):
		var wrap := Control.new()
		wrap.position = Vector2(30.0 + float(i) * step + (step - 42.0) * 0.5, 286.0)
		wrap.size = Vector2(42, 42)
		wrap.pivot_offset = Vector2(21, 21)
		wrap.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(wrap)
		var coin := CoinProp.new()
		coin.seed_text = "paytoken_%d_%s" % [i, _event_id]
		coin.worn = true
		coin.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(coin)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.pressed.connect(_on_scale_coin.bind(i))
		_stage_touchable(wrap, btn)
		wrap.add_child(btn)
		var mark := Label.new()
		mark.text = "·"
		mark.add_theme_font_size_override("font_size", 15)
		mark.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42))
		mark.position = Vector2(0, 42)
		mark.size = Vector2(42, 18)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(mark)
		_scale_marks.append(mark)
	_stage_entrance(root)
	GameTheme.attach_rich_hover(patch, "The quartermaster's balance",
		"Click a coin to move it: off, left pan, right pan. Then weigh both sides.",
		"Set the pans, then drop the beam", Color(0.90, 0.84, 0.68), 1.0)


func _scale_pan_counts() -> Vector2i:
	var l := 0
	var r := 0
	for a in _scale_assign:
		if a == -1:
			l += 1
		elif a == 1:
			r += 1
	return Vector2i(l, r)


func _scale_refresh_marks() -> void:
	for i in range(_scale_marks.size()):
		var m = _scale_marks[i]
		if not is_instance_valid(m):
			continue
		match int(_scale_assign[i]):
			-1:
				m.text = "◄ L"
				# Gilt, matching the R marker below — a symmetric two-sided device
				# had one side in-palette and one in steel blue.
				m.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
			1:
				m.text = "R ►"
				m.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
			_:
				m.text = "·"
				m.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42))
	if _scale_beam != null and is_instance_valid(_scale_beam):
		var c := _scale_pan_counts()
		_scale_beam.left_n = c.x
		_scale_beam.right_n = c.y
		_scale_beam.settled = false
		_scale_beam.queue_redraw()


func _on_scale_coin(i: int) -> void:
	if _scale_busy:
		return
	if _scale_accusing:
		_scale_accuse(i)
		return
	_scale_assign[i] = -1 if _scale_assign[i] == 0 else (1 if _scale_assign[i] == -1 else 0)
	AudioBank.play_sfx("coin", 0.06, -12.0)
	_scale_refresh_marks()
	# Level the beam while re-setting (the last result has been read).
	if _scale_beam != null and is_instance_valid(_scale_beam) and _scale_beam.tip != 0.0:
		_scale_beam.tip = 0.0
		_scale_beam.queue_redraw()
	# Re-arm so "Drop the beam" appears once both pans hold coins.
	_scale_arm_rows()


func _scale_arm_rows() -> void:
	if _scale_rows == null or not is_instance_valid(_scale_rows):
		return
	for c in _scale_rows.get_children():
		c.queue_free()
	if _scale_accusing:
		_scale_rows.add_child(_make_frameless_choice("Study the coins again",
			"Not yet — back to the balance.", "", 52, _on_scale_cancel_accuse))
		return
	var counts := _scale_pan_counts()
	if _scale_used < _scale_max and counts.x > 0 and counts.y > 0:
		_scale_rows.add_child(_make_frameless_choice("Drop the beam",
			"Weigh %d against %d. Weighing %d of %d." % [
				counts.x, counts.y, _scale_used + 1, _scale_max], "", 52,
			_on_scale_drop))
	var name_sub := "Choose the light coin."
	if _gamble_pays_coin(_scale_cfg, _scale_base_plus_saved()):
		name_sub += " Correct pays %d after %d weighing%s." % [
			_scale_base_plus_saved(), _scale_used,
			"" if _scale_used == 1 else "s"]
	_scale_rows.add_child(_make_frameless_choice("Name the false coin",
		name_sub, "", 52, _on_scale_begin_accuse))


func _scale_base_plus_saved() -> int:
	var base: int = int(_scale_cfg.get("base", 30))
	var per: int = int(_scale_cfg.get("per_saved", 12))
	return base + (_scale_max - _scale_used) * per


func _on_scale_drop() -> void:
	if _scale_busy or _scale_used >= _scale_max:
		return
	var counts := _scale_pan_counts()
	if counts.x <= 0 or counts.y <= 0:
		return
	_scale_busy = true
	# The honest weight: the false token is a shade light.
	var lw := 0.0
	var rw := 0.0
	for i in range(_scale_n):
		var w := 0.90 if i == _scale_fake else 1.0
		if _scale_assign[i] == -1:
			lw += w
		elif _scale_assign[i] == 1:
			rw += w
	var tip := 0.0
	var verdict := "THE BEAM HOLDS LEVEL"
	var glyph := "LEVEL"
	if absf(lw - rw) > 0.001:
		if lw > rw:
			tip = -0.22
			verdict = "THE LEFT PAN SINKS"
			glyph = "L↓"
		else:
			tip = 0.22
			verdict = "THE RIGHT PAN SINKS"
			glyph = "R↓"
	_scale_used += 1
	AudioBank.play_sfx("bone_settle", 0.05, -6.0)
	if _scale_beam != null and is_instance_valid(_scale_beam):
		if UserSettings.reduce_motion:
			_scale_beam.tip = tip
			_scale_beam.settled = true
			_scale_beam.queue_redraw()
		else:
			var b = _scale_beam
			var slam := tip
			var tw: Tween = b.create_tween()
			# Overshoot then settle, like a real beam finding its rest — and
			# the table takes a little of the weight when it bottoms out.
			tw.tween_method(func(v): b.tip = v; b.queue_redraw(),
				0.0, tip * 1.18, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func():
				if absf(slam) > 0.001:
					GameTheme.shake_impulse(self, 0.09))
			tw.tween_method(func(v): b.tip = v; b.queue_redraw(),
				tip * 1.18, tip, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			b.settled = true
	_scale_log.append("W%d %dv%d %s" % [_scale_used, counts.x, counts.y, glyph])
	if _scale_log_label != null and is_instance_valid(_scale_log_label):
		_scale_log_label.text = "   ".join(_scale_log)
	if _scale_caption != null and is_instance_valid(_scale_caption):
		var left := _scale_max - _scale_used
		_scale_caption.text = "%s · %s" % [verdict,
			("NAME IT OR WEIGH %d MORE" % left) if left > 0 else "NO WEIGHINGS LEFT — NAME IT"]
	await get_tree().create_timer(1.0 if UserSettings.reduce_motion else 0.95).timeout
	if _scale_root == null or not is_instance_valid(_scale_root):
		return
	# Clear the pans for the next assignment; the log holds the memory.
	for i in range(_scale_n):
		_scale_assign[i] = 0
	_scale_refresh_marks()
	_scale_busy = false
	if _scale_used >= _scale_max:
		_scale_accusing = true
		if _scale_caption != null and is_instance_valid(_scale_caption):
			_scale_caption.text = "NO WEIGHINGS LEFT · POINT TO THE FALSE COIN"
	_scale_arm_rows()


func _on_scale_begin_accuse() -> void:
	if _scale_busy:
		return
	_scale_accusing = true
	if _scale_caption != null and is_instance_valid(_scale_caption):
		_scale_caption.text = "POINT TO THE FALSE COIN"
	_scale_arm_rows()


func _on_scale_cancel_accuse() -> void:
	if _scale_busy or _scale_used >= _scale_max:
		return
	_scale_accusing = false
	if _scale_caption != null and is_instance_valid(_scale_caption):
		_scale_caption.text = "WEIGHING %d OF %d · SET THE PANS" % [
			_scale_used + 1, _scale_max]
	_scale_arm_rows()


func _scale_accuse(idx: int) -> void:
	if _scale_busy:
		return
	_scale_busy = true
	_scale_accusing = false
	for c in _scale_rows.get_children():
		c.queue_free()
	# Reveal: the named coin lifts, and the true light one is shown worn-bright.
	var correct: bool = idx == _scale_fake
	# Lift the accused token; ring the true counterfeit.
	if idx >= 0 and idx < _scale_marks.size():
		var wrap = _scale_marks[idx].get_parent()
		if is_instance_valid(wrap) and not UserSettings.reduce_motion:
			var pu: Tween = wrap.create_tween()
			pu.tween_property(wrap, "position:y", wrap.position.y - 10.0, 0.14)
	var fake_wrap = _scale_marks[_scale_fake].get_parent()
	if is_instance_valid(fake_wrap):
		_scale_marks[_scale_fake].text = "LIGHT"
		_scale_marks[_scale_fake].add_theme_color_override("font_color",
			Color(0.92, 0.62, 0.30))
		if not UserSettings.reduce_motion and _scale_root != null \
				and is_instance_valid(_scale_root):
			Motion.ring(self, _scale_root.get_global_position()
				+ fake_wrap.position + fake_wrap.size * 0.5,
				Color(0.92, 0.66, 0.34), {"radius": 34.0, "duration": 0.5})
	await get_tree().create_timer(0.9).timeout
	if correct:
		_scale_pay = _scale_base_plus_saved()
		var receipt := _gamble_pay(_scale_cfg, true, _scale_pay,
			"coin_pour" if _scale_used <= 1 else "coin")
		_win_flourish()
		_show_result(_combine_lines([_scale_text("win_text",
			"Correct. Gained {pay} gold."), receipt]))
	else:
		_sting("hit_hero", -6.0)
		_bust_feedback()
		var lose_receipt := _gamble_pay(_scale_cfg, false, 0)
		_show_result(_combine_lines([_scale_text("poor_text",
			"Wrong coin. You lost the stake."), lose_receipt]))


# ── The Fourth's Strongbox (box_game) — crack the lost combination ────────
# The code-breaking puzzle (Mastermind), retold as the Fourth Legion's
# paychest — the strongbox marked IV, sealed a century, its combination
# gone with the paymaster. Four brass wards, each 1..6; work them by
# deduction from honest feedback. HONEST BY CONSTRUCTION: the combination
# is baked at the first turn of a dial, and every attempt reports the exact
# truth — SEATED (right ward, right number) and LOOSE (right number, wrong
# ward). A running ledger keeps every past attempt and its pegs on the
# table. Crack it and you pay the Fourth the wage the King never did.
#   Config: {stake, wards: 4, marks: 6, tries: 7, base, per_saved,
#            open_text, win_text, poor_text, broke_text, seen_texts}
#            — texts take {stake} / {pay} / {tries} / {code}.

const BOX_WARDS := 4
const BOX_MARKS := 6

var _box_cfg: Dictionary = {}
var _box_code: Array = []
var _box_guess: Array = []
var _box_marks := 6
var _box_tries := 0
var _box_max := 7
var _box_pay := 0
var _box_root: Control = null
var _box_rows: VBoxContainer = null
var _box_caption: Label = null
var _box_hist_label: Label = null
var _box_dials: Array = []          # StrongboxDial nodes
var _box_numlabels: Array = []      # numeral Labels
var _box_history: Array = []        # ledger row strings
var _box_busy := true


func _box_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_box_cfg, key,
		String(_box_cfg.get(key, fallback)))
	var code_str := " ".join(_box_code.map(func(v): return str(v)))
	return raw.replace("{stake}", str(int(_box_cfg.get("stake", 0)))) \
		.replace("{pay}", str(_box_pay)).replace("{tries}", str(_box_tries)) \
		.replace("{code}", code_str)


## The pay for cracking it having spent `tries` attempts. Defaults to the tries
## ALREADY spent — the live row must pass `_box_tries + 1`, because the attempt
## it is offering is itself counted before _box_crack reads this.
func _box_tier(tries: int = -1) -> int:
	var spent: int = _box_tries if tries < 0 else tries
	var base: int = int(_box_cfg.get("base", 40))
	var per: int = int(_box_cfg.get("per_saved", 14))
	return base + (_box_max - spent) * per


func _start_box_game(effect: Dictionary) -> void:
	_box_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_box_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	_box_marks = clampi(int(effect.get("marks", BOX_MARKS)), 3, 9)
	_box_code = []
	for _i in range(BOX_WARDS):
		_box_code.append(randi() % _box_marks + 1)
	_box_guess = [1, 1, 1, 1]
	_box_tries = 0
	_box_max = int(effect.get("tries", 7))
	_box_pay = 0
	_box_history = []
	_box_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_box_text("open_text",
			"Set four dials from 1 to 6. Exact means correct number and position. Misplaced means correct number in the wrong position."), 4)
	_box_rows = VBoxContainer.new()
	_box_rows.add_theme_constant_override("separation", 12)
	vbox.add_child(_box_rows)
	_build_box_stage()
	_box_busy = false
	_box_arm_rows()


func _build_box_stage() -> void:
	_box_dials = []
	_box_numlabels = []
	var root := Control.new()
	root.name = "BoxStage"
	root.position = Vector2(860, 200)
	root.size = Vector2(560, 450)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_box_root = root
	var patch := CastPatch.new()
	patch.seed_text = "strongbox_" + _event_id
	patch.position = Vector2(10, 56)
	patch.size = Vector2(540, 356)
	root.add_child(patch)
	var caption := Label.new()
	caption.text = "TRY 1 OF %d · SET THE WARDS" % _box_max
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	caption.position = Vector2(30, 76)
	caption.size = Vector2(500, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_box_caption = caption
	# The iron faceplate, branded IV, with its four wards.
	var plate := ColorRect.new()
	plate.color = Color(0.15, 0.14, 0.13)
	plate.position = Vector2(120, 104)
	plate.size = Vector2(300, 118)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	var bevel := ColorRect.new()
	bevel.color = Color(0.22, 0.20, 0.18)
	bevel.position = Vector2(124, 108)
	bevel.size = Vector2(292, 110)
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bevel)
	for rv in [Vector2(130, 114), Vector2(404, 114), Vector2(130, 206), Vector2(404, 206)]:
		var rivet := ColorRect.new()
		rivet.color = Color(0.34, 0.30, 0.25)
		rivet.position = rv
		rivet.size = Vector2(6, 6)
		rivet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(rivet)
	var brand := Label.new()
	brand.text = "IV"
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", Color(0.52, 0.45, 0.34))
	if GameTheme.font_display:
		brand.add_theme_font_override("font", GameTheme.font_display)
	brand.position = Vector2(120, 190)
	brand.size = Vector2(300, 26)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(brand)
	for i in range(BOX_WARDS):
		var wrap := Control.new()
		wrap.position = Vector2(138.0 + float(i) * 66.0, 118.0)
		wrap.size = Vector2(58, 58)
		wrap.pivot_offset = Vector2(29, 29)
		wrap.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(wrap)
		var dial := StrongboxDial.new()
		dial.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(dial)
		_box_dials.append(dial)
		var num := Label.new()
		num.text = str(_box_guess[i])
		num.add_theme_font_size_override("font_size", 26)
		num.add_theme_color_override("font_color", Color(0.93, 0.84, 0.55))
		if GameTheme.font_display:
			num.add_theme_font_override("font", GameTheme.font_display)
		num.set_anchors_preset(Control.PRESET_FULL_RECT)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(num)
		_box_numlabels.append(num)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.pressed.connect(_on_box_dial.bind(i))
		_stage_touchable(wrap, btn)
		wrap.add_child(btn)
	# The attempt ledger — every past try and its pegs, kept in the open.
	var hist := Label.new()
	hist.text = "● exact   ○ misplaced"
	hist.add_theme_font_size_override("font_size", 15)
	hist.add_theme_color_override("font_color", Color(0.74, 0.68, 0.56))
	hist.position = Vector2(30, 244)
	hist.size = Vector2(500, 160)
	hist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hist.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hist.autowrap_mode = TextServer.AUTOWRAP_OFF
	hist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hist)
	_box_hist_label = hist
	_stage_entrance(root)
	GameTheme.attach_rich_hover(patch, "The paychest, marked IV",
		"Turn each dial, then try the code. Use the Exact and Misplaced counts to solve it.",
		"Turn the wards, then try the combination", Color(0.90, 0.84, 0.68), 1.0)


func _box_arm_rows() -> void:
	if _box_rows == null or not is_instance_valid(_box_rows):
		return
	for c in _box_rows.get_children():
		c.queue_free()
	var guess_str := " · ".join(_box_guess.map(func(v): return str(v)))
	var try_sub := "Code: %s. Attempt %d of %d." % [guess_str,
		_box_tries + 1, _box_max]
	var crack_pay := _box_tier(_box_tries + 1)
	if _gamble_pays_coin(_box_cfg, crack_pay):
		try_sub += " Current reward: %d gold." % crack_pay
	_box_rows.add_child(_make_frameless_choice("Try the combination",
		try_sub, "", 52, _on_box_try))


func _on_box_dial(i: int) -> void:
	if _box_busy:
		return
	_box_guess[i] = _box_guess[i] % _box_marks + 1
	AudioBank.play_sfx("bone_settle", 0.06, -12.0, 1.15)
	if i < _box_numlabels.size() and is_instance_valid(_box_numlabels[i]):
		_box_numlabels[i].text = str(_box_guess[i])
	for k in range(_box_dials.size()):
		if is_instance_valid(_box_dials[k]):
			_box_dials[k].active = (k == i)
			_box_dials[k].queue_redraw()
	if not UserSettings.reduce_motion and i < _box_dials.size():
		var w = _box_dials[i].get_parent()
		if is_instance_valid(w):
			var tw: Tween = w.create_tween()
			tw.tween_property(w, "scale", Vector2(1.12, 1.12), 0.06)
			tw.tween_property(w, "scale", Vector2.ONE, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_box_arm_rows()


func _box_feedback(g: Array) -> Vector2i:
	var seated := 0
	for i in range(BOX_WARDS):
		if int(g[i]) == int(_box_code[i]):
			seated += 1
	var matched := 0
	for s in range(1, _box_marks + 1):
		matched += mini(g.count(s), _box_code.count(s))
	return Vector2i(seated, matched - seated)


func _on_box_try() -> void:
	if _box_busy:
		return
	_box_busy = true
	var fb := _box_feedback(_box_guess)
	_box_tries += 1
	AudioBank.play_sfx("bone_settle", 0.05, -6.0, 0.9)
	var pegs := ""
	for _s in range(fb.x):
		pegs += "●"
	for _l in range(fb.y):
		pegs += "○"
	if pegs == "":
		pegs = "—"
	var guess_str := " ".join(_box_guess.map(func(v): return str(v)))
	_box_history.append("%s    %s" % [guess_str, pegs])
	if _box_hist_label != null and is_instance_valid(_box_hist_label):
		_box_hist_label.text = "● exact   ○ misplaced\n" + "\n".join(_box_history)
	if fb.x >= BOX_WARDS:
		await _box_crack()
		return
	if _box_tries >= _box_max:
		await _box_fail()
		return
	if _box_caption != null and is_instance_valid(_box_caption):
		_box_caption.text = "%d EXACT · %d MISPLACED · TRY %d OF %d" % [
			fb.x, fb.y, _box_tries + 1, _box_max]
	for d in _box_dials:
		if is_instance_valid(d):
			d.active = false
			d.queue_redraw()
	_box_busy = false
	_box_arm_rows()


func _box_crack() -> void:
	_box_pay = _box_tier()
	if _box_caption != null and is_instance_valid(_box_caption):
		_box_caption.text = "THE TUMBLERS FALL · THE FOURTH IS PAID"
	# The tumblers fall one by one — a warm cha-chunk down the wards, left to
	# right, before the lid gives and the coin comes.
	for i in range(_box_dials.size()):
		var d = _box_dials[i]
		if is_instance_valid(d):
			d.locked = true
			d.active = false
			d.queue_redraw()
			AudioBank.play_sfx("bone_settle", 0.03, -5.0, 0.78 + float(i) * 0.09)
			if not UserSettings.reduce_motion:
				var w = d.get_parent()
				if is_instance_valid(w):
					var tw: Tween = w.create_tween()
					tw.tween_property(w, "scale", Vector2(1.16, 1.16), 0.06)
					tw.tween_property(w, "scale", Vector2.ONE, 0.13) \
						.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			await get_tree().create_timer(0.12).timeout
	if _box_root == null or not is_instance_valid(_box_root):
		return
	if not UserSettings.reduce_motion:
		Motion.burst(self, _box_root.get_global_position() + Vector2(270, 160),
			"coin")
		Motion.ring(self, _box_root.get_global_position() + Vector2(270, 160),
			Color(0.95, 0.80, 0.42), {"radius": 60.0, "duration": 0.6})
	var receipt := _gamble_pay(_box_cfg, true, _box_pay, "coin_pour")
	_win_flourish()
	await get_tree().create_timer(0.9).timeout
	_show_result(_combine_lines([_box_text("win_text",
		"Correct code. Gained {pay} gold."), receipt]))


func _box_fail() -> void:
	_sting("hit_hero", -6.0)
	_bust_feedback()
	if _box_caption != null and is_instance_valid(_box_caption):
		_box_caption.text = "THE WARDS SEIZE · THE BOX HOLDS"
	await get_tree().create_timer(0.8).timeout
	var receipt := _gamble_pay(_box_cfg, false, 0)
	_show_result(_combine_lines([_box_text("poor_text",
		"No attempts remain. The code was {code}. You lost the stake."),
		receipt]))


# ── The Dead Man's Deal (deal_game) — call the pay-chits higher or lower ──
# The high-low card climb, dealt by a dead card-sharp of the Fourth from a
# stripped paybook. HONEST BY CONSTRUCTION: one real deck of distinct pay-
# chits (ranks 1..N), shuffled once and drawn WITHOUT replacement, so the
# odds shift as the bag empties and the running count is exact — and it is
# shown in the open (how many still run higher, how many lower), so the call
# is never a guess, only a gamble. Each held call climbs the ladder; bank any
# time, or push. One wrong call and the sharp keeps the stake.
#   Config: {stake, ranks: 13, pay: [..indexed by streak..], open_text,
#            win_text, bank_text, poor_text, broke_text, seen_texts}
#            — texts take {stake}/{pay}/{streak}.

var _deal_cfg: Dictionary = {}
var _deal_deck: Array = []          # shuffled ranks, drawn front→back
var _deal_pos := 0                  # index of the current face-up chit
var _deal_streak := 0
var _deal_pay := 0
var _deal_root: Control = null
var _deal_rows: VBoxContainer = null
var _deal_caption: Label = null
var _deal_odds: Label = null
var _deal_streak_lbl: Label = null
var _deal_chit_num: Label = null    # the big numeral on the current chit
var _deal_chit: CoinProp = null
var _deal_spent: HBoxContainer = null
var _deal_busy := true

const DEAL_LADDER := [0, 6, 14, 26, 42, 64, 92, 130, 180, 246, 332, 446, 600]


func _deal_text(key: String, fallback: String) -> String:
	var raw := _seen_text_override(_deal_cfg, key,
		String(_deal_cfg.get(key, fallback)))
	return raw.replace("{stake}", str(int(_deal_cfg.get("stake", 0)))) \
		.replace("{pay}", str(_deal_pay)).replace("{streak}", str(_deal_streak))


func _deal_tier(streak: int) -> int:
	var pay: Array = _deal_cfg.get("pay", DEAL_LADDER)
	return int(pay[clampi(streak, 0, pay.size() - 1)])


func _deal_current_rank() -> int:
	return int(_deal_deck[_deal_pos])


## Exact odds on the next draw: how many unseen chits beat the current one and
## how many fall under it (no ties — every rank is distinct). This is the whole
## deduction, kept in the open.
func _deal_counts() -> Vector2i:
	var cur := _deal_current_rank()
	var hi := 0
	var lo := 0
	for i in range(_deal_pos + 1, _deal_deck.size()):
		if int(_deal_deck[i]) > cur:
			hi += 1
		else:
			lo += 1
	return Vector2i(hi, lo)


func _start_deal_game(effect: Dictionary) -> void:
	_deal_cfg = effect
	var stake: int = int(effect.get("stake", 0))
	if stake > 0 and RunState.gold < stake:
		_show_result(_deal_text("broke_text",
			"You need {stake} gold to play."))
		return
	if stake > 0:
		RunState.gold -= stake
	var ranks := clampi(int(effect.get("ranks", 13)), 5, 13)
	_deal_deck = []
	for r in range(1, ranks + 1):
		_deal_deck.append(r)
	_deal_deck.shuffle()
	_deal_pos = 0
	_deal_streak = 0
	_deal_pay = 0
	_deal_busy = true
	var vbox := _build_event_screen(_event_data.name,
		_deal_text("open_text",
			"Call whether the next card is higher or lower. Each correct call raises the reward. Stop at any time."), 4)
	_deal_rows = VBoxContainer.new()
	_deal_rows.add_theme_constant_override("separation", 12)
	vbox.add_child(_deal_rows)
	_build_deal_stage()
	_deal_busy = false
	_deal_arm_rows()


func _build_deal_stage() -> void:
	var root := Control.new()
	root.name = "DealStage"
	root.position = Vector2(860, 200)
	root.size = Vector2(560, 450)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_deal_root = root
	var patch := CastPatch.new()
	patch.seed_text = "deal_" + _event_id
	patch.chalk = "ring"
	patch.position = Vector2(10, 56)
	patch.size = Vector2(540, 356)
	root.add_child(patch)
	var caption := Label.new()
	caption.text = "CALL THE NEXT CARD"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	caption.position = Vector2(30, 76)
	caption.size = Vector2(500, 24)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	_deal_caption = caption
	# The odds, chalked in the open — how many chits beat this one, how many
	# fall under it, still in the bag. The whole deduction, never hidden.
	var odds := Label.new()
	odds.add_theme_font_size_override("font_size", 19)
	odds.add_theme_color_override("font_color", Color(0.86, 0.80, 0.66))
	odds.position = Vector2(30, 106)
	odds.size = Vector2(500, 26)
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(odds)
	_deal_odds = odds
	# The big current pay-chit, dead center — the boldest thing on the table.
	var chit_wrap := Control.new()
	chit_wrap.position = Vector2(205, 148)
	chit_wrap.size = Vector2(150, 150)
	chit_wrap.pivot_offset = Vector2(75, 75)
	chit_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chit_wrap)
	var chit := CoinProp.new()
	chit.seed_text = "dealchit_" + _event_id
	chit.worn = true
	chit.set_anchors_preset(Control.PRESET_FULL_RECT)
	chit_wrap.add_child(chit)
	_deal_chit = chit
	var num := Label.new()
	num.add_theme_font_size_override("font_size", 78)
	num.add_theme_color_override("font_color", Color(0.20, 0.13, 0.05))
	if GameTheme.font_display:
		num.add_theme_font_override("font", GameTheme.font_display)
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chit_wrap.add_child(num)
	_deal_chit_num = num
	# The streak / pay-on-the-table line.
	var st := Label.new()
	st.add_theme_font_size_override("font_size", 17)
	st.add_theme_color_override("font_color", Color(0.80, 0.70, 0.44))
	st.position = Vector2(30, 304)
	st.size = Vector2(500, 22)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(st)
	_deal_streak_lbl = st
	# The row of spent chits — what's already been turned, so a counter can
	# read the bag. Runs along the near edge of the cloth.
	var spent := HBoxContainer.new()
	spent.add_theme_constant_override("separation", 4)
	spent.position = Vector2(40, 342)
	spent.size = Vector2(480, 34)
	spent.alignment = BoxContainer.ALIGNMENT_CENTER
	spent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spent)
	_deal_spent = spent
	_deal_refresh()
	_stage_entrance(root)
	GameTheme.attach_rich_hover(patch, "The dead sharp's board",
		"Call higher or lower. The remaining card counts show the exact odds. Stop after a win to collect.",
		"Call higher or lower, then bank or push", Color(0.90, 0.84, 0.68), 1.0)


func _deal_refresh() -> void:
	if _deal_chit_num != null and is_instance_valid(_deal_chit_num):
		_deal_chit_num.text = str(_deal_current_rank())
	var c := _deal_counts()
	if _deal_odds != null and is_instance_valid(_deal_odds):
		if c.x + c.y == 0:
			_deal_odds.text = "NO CARDS LEFT"
		else:
			_deal_odds.text = "HIGHER  %d        LOWER  %d        (of %d still to come)" % [
				c.x, c.y, c.x + c.y]
	if _deal_streak_lbl != null and is_instance_valid(_deal_streak_lbl):
		if _deal_streak <= 0:
			_deal_streak_lbl.text = "Make one correct call to earn a reward."
		else:
			_deal_streak_lbl.text = "%d correct %s in a row - %d gold available." % [
				_deal_streak, "call" if _deal_streak == 1 else "calls", _deal_pay]


func _deal_arm_rows() -> void:
	if _deal_rows == null or not is_instance_valid(_deal_rows):
		return
	_deal_busy = false
	for ch in _deal_rows.get_children():
		ch.queue_free()
	var c := _deal_counts()
	var left := c.x + c.y
	_deal_rows.add_child(_make_frameless_choice("Call higher",
		"Next card is higher in %d of %d cases." % [c.x, left], "", 52,
		_on_deal_higher))
	_deal_rows.add_child(_make_frameless_choice("Call lower",
		"Next card is lower in %d of %d cases." % [c.y, left], "", 52,
		_on_deal_lower))
	if _deal_streak >= 1:
		_deal_rows.add_child(_make_frameless_choice("Take the money",
			"Collect %d gold and leave." % _deal_pay, "", 52,
			_on_deal_bank))


func _on_deal_higher() -> void:
	_deal_call(true)


func _on_deal_lower() -> void:
	_deal_call(false)


func _deal_call(higher: bool) -> void:
	if _deal_busy:
		return
	_deal_busy = true
	var cur := _deal_current_rank()
	var nxt := int(_deal_deck[_deal_pos + 1])
	var correct := (nxt > cur) if higher else (nxt < cur)
	for ch in _deal_rows.get_children():
		ch.queue_free()
	# Push the turned chit into the spent row, then flip up the next.
	_deal_push_spent(cur)
	_deal_pos += 1
	await _deal_flip_to(nxt, correct)
	if not correct:
		if _deal_caption != null and is_instance_valid(_deal_caption):
			_deal_caption.text = "YOU CALLED %s — IT RAN %s" % [
				"HIGHER" if higher else "LOWER",
				"HIGHER" if nxt > cur else "LOWER"]
		await get_tree().create_timer(0.7).timeout
		_sting("hit_hero", -6.0)
		_bust_feedback()
		var poor_receipt := _gamble_pay(_deal_cfg, false, 0)
		_show_result(_combine_lines([_deal_text("poor_text",
			"Wrong call. You lost the stake."), poor_receipt]))
		return
	# Held.
	_deal_streak += 1
	_deal_pay = _deal_tier(_deal_streak)
	_sting("coin", -4.0)
	_deal_refresh()
	# Cleared the whole bag?
	if _deal_pos >= _deal_deck.size() - 1:
		var receipt := _gamble_pay(_deal_cfg, true, _deal_pay, "coin_pour")
		var frid := _gamble_bank_relic(_deal_cfg, _deal_pay)
		if frid != "":
			receipt = _combine_lines([receipt, _deal_text("bank_relic_text",
				"Gained relic: %s." % RelicDB.get_relic(frid).name)])
		if _deal_chit != null and is_instance_valid(_deal_chit):
			_win_flourish(_deal_chit.get_global_position() + _deal_chit.size * 0.5)
		else:
			_win_flourish()
		_show_result(_combine_lines([_deal_text("win_text",
			"You called every remaining card correctly. Gained {pay} gold."),
			receipt]))
		return
	if _deal_caption != null and is_instance_valid(_deal_caption):
		_deal_caption.text = "CALL THE NEXT CARD"
	_deal_arm_rows()


func _deal_push_spent(rank: int) -> void:
	if _deal_spent == null or not is_instance_valid(_deal_spent):
		return
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(30, 30)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := CoinProp.new()
	coin.seed_text = "spent_%d_%d_%s" % [rank, _deal_pos, _event_id]
	coin.worn = true
	coin.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(coin)
	var n := Label.new()
	n.text = str(rank)
	n.add_theme_font_size_override("font_size", 15)
	n.add_theme_color_override("font_color", Color(0.22, 0.15, 0.06))
	if GameTheme.font_display:
		n.add_theme_font_override("font", GameTheme.font_display)
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(n)
	_deal_spent.add_child(wrap)


func _deal_flip_to(nxt: int, correct: bool) -> void:
	if _deal_chit == null or not is_instance_valid(_deal_chit):
		return
	var flash := Color(0.45, 0.72, 0.40) if correct else Color(0.80, 0.32, 0.22)
	if UserSettings.reduce_motion:
		if _deal_chit_num != null and is_instance_valid(_deal_chit_num):
			_deal_chit_num.text = str(nxt)
			_deal_chit_num.add_theme_color_override("font_color", flash.darkened(0.35))
		await get_tree().create_timer(0.5).timeout
		if _deal_chit_num != null and is_instance_valid(_deal_chit_num):
			_deal_chit_num.add_theme_color_override("font_color", Color(0.20, 0.13, 0.05))
		return
	AudioBank.play_sfx("coin", 0.05, -8.0)
	var t := _deal_chit.create_tween()
	t.tween_property(_deal_chit, "face_t", 0.05, 0.13) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_deal_chit_num, "modulate:a", 0.0, 0.11)
	t.tween_callback(func():
		if _deal_chit_num != null and is_instance_valid(_deal_chit_num):
			_deal_chit_num.text = str(nxt))
	t.tween_property(_deal_chit, "face_t", 1.0, 0.17) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_deal_chit_num, "modulate:a", 1.0, 0.15)
	await t.finished
	_deal_ring(flash)
	AudioBank.play_sfx("coin", 0.05, -4.0)
	await get_tree().create_timer(0.26).timeout


func _deal_ring(col: Color) -> void:
	if UserSettings.reduce_motion:
		return
	if _deal_chit == null or not is_instance_valid(_deal_chit):
		return
	Motion.ring(self, _deal_chit.get_global_position() + _deal_chit.size * 0.5,
		col, {"radius": 92.0, "duration": 0.5, "oval": Vector2(1.0, 0.9)})


func _on_deal_bank() -> void:
	# An early stop earns its LADDER TIER, never the whole prize — the
	# terminal payoff on a pot game is `bank_relic_at`, read off that tier.
	var receipt := _gamble_pay(_deal_cfg, true, _deal_pay) if _deal_pay > 0 else ""
	var rid := _gamble_bank_relic(_deal_cfg, _deal_pay)
	if rid != "":
		receipt = _combine_lines([receipt, _deal_text("bank_relic_text",
			"Gained relic: %s." % RelicDB.get_relic(rid).name)])
	_show_result(_combine_lines([_deal_text("bank_text",
		"Collected {pay} gold."), receipt]))


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
	_add_risk_stage(steps.size())


## The Burning Inch (docs/EVENT_PLAY_PITCH_20260718.md L2): the risk ladder's
## spend made physical — a candle stub beside the choices burns visibly down
## with every press, drips piling on the dish, and gutters out on the bust.
## Display only; the odds stay in the step data. The flicker loop is
## decorative (Reduce Motion holds the flame steady).
var _risk_candle: Control = null
var _risk_flick: Tween = null
var _risk_busy := false


func _add_risk_stage(n_steps: int) -> void:
	_risk_busy = false
	if _risk_flick != null and _risk_flick.is_valid():
		_risk_flick.kill()
	_risk_flick = null
	_risk_candle = null
	var root := Control.new()
	root.name = "RiskStage"
	root.position = Vector2(1030, 250)
	root.size = Vector2(280, 400)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var candle := CandleStub.new()
	candle.seed_text = "wick_" + _event_id
	candle.burn = clampf(float(_risk_step) / maxf(1.0, float(n_steps)), 0.0, 1.0)
	candle.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(candle)
	_risk_candle = candle
	if not UserSettings.reduce_motion:
		_risk_flick = candle.create_tween().set_loops()
		_risk_flick.tween_method(_risk_flick_tick, 0.0, 1.0, 0.9)


func _risk_flick_tick(v: float) -> void:
	if _risk_candle == null or not is_instance_valid(_risk_candle):
		return
	_risk_candle.flick = v
	_risk_candle.flame_h = 0.92 + 0.14 * sin(v * TAU * 2.0)
	_risk_candle.queue_redraw()


func _candle_flame_to(v: float) -> void:
	if _risk_candle == null or not is_instance_valid(_risk_candle):
		return
	_risk_candle.flame_h = v
	_risk_candle.queue_redraw()


## The bust: one last flare, then the dark takes the flame — ash where it
## stood. Plays on the CURRENT screen before the result page replaces it.
func _play_candle_gutter() -> void:
	if _risk_candle == null or not is_instance_valid(_risk_candle) \
			or UserSettings.reduce_motion:
		return
	if _risk_flick != null and _risk_flick.is_valid():
		_risk_flick.kill()
	AudioBank.play_sfx("candle_out", 0.05, -4.0)
	var candle := _risk_candle
	var t := candle.create_tween()
	t.tween_method(_candle_flame_to, 1.0, 1.45, 0.14)
	t.tween_method(_candle_flame_to, 1.45, 0.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if is_instance_valid(candle):
		Motion.burst(self, candle.get_global_position()
			+ Vector2(candle.size.x * 0.5, candle.size.y * 0.30), "ash")
	await get_tree().create_timer(0.55).timeout


func _on_risk_action() -> void:
	if _risk_busy:
		return
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
		# Bake then shade: the bust's effects have already landed above —
		# the candle only performs them before the page turns.
		_risk_busy = true
		await _play_candle_gutter()
		_show_result(_combine_lines([String(bust.get("text", "The luck turns.")),
			bust_receipt]))
		_bust_feedback()


func _on_risk_leave() -> void:
	if _risk_busy:
		return
	if _risk_step == 0:
		_show_result(String(_risk_cfg.get("leave_text_early",
			_risk_cfg.get("leave_text", "You let it be."))))
	else:
		_show_result(String(_risk_cfg.get("leave_text", "You step away with what you were given.")))


# ── Appraisal (pawn_appraisal) — the haggling counter ────────────────────
# She names a card out of YOUR deck and offers a price. Take it, or ask her to
# look again — her interest (and the multiplier) cools 15% each time, three
# cards shown at most. Curses are never appraised ("she has standards").
#
# SHE ASKS FOR YOUR BEST (owner's rule, 2026-09-16). She used to pull a card at
# UNIFORM RANDOM, and on a deck that is mostly starters that meant she almost
# always offered to buy your chaff — so the counter was a deck-thinning service
# that also paid you, which is the same defect the shop's buy-back had and was
# removed for on the same day. A pawnbroker with an eye does not want your
# Strike; she wants the rare and she wants the thing you forged.
#
# That inverts the whole decision. Before: "will I take free gold for a card I
# did not want anyway?" — which is not a decision. Now: "what is my best card
# worth to me, in gold, right now?" — which is the trade the shelf behind the
# glass exists to offer, and it is what makes the act-2 buy-back worth wanting.
const APPR_RARITY_WORTH: Dictionary = {
	"starter": 0, "common": 10, "uncommon": 20, "rare": 30,
}
## A forge is worth MORE than one rarity step, deliberately: the owner's rule
## names rarity and forging as equal claims on her interest ("highest rarity or
## one you have updated"), and a card you chose to forge is a card you committed
## to, so a forged common (22) outranking a plain uncommon (20) is the right
## reading of "your best" — it is best BY YOUR OWN REVEALED PREFERENCE.
const APPR_FORGED_WORTH := 12
## What the forge adds to her offer. She is buying the improvement too, so a
## worth model that ranked forged cards up while the PRICE ignored forging would
## have her hunting your best work and paying base-card money for it.
const APPR_FORGED_PRICE := 20
const APPR_MAX_SHOWN := 3

var _appr_index: int = -1
var _appr_mult: float = 1.0
var _appr_shown: int = 0
## Her shortlist: deck indices, best first, computed ONCE on entry. Held rather
## than re-rolled per look because a sale ends the screen, so the deck cannot
## shift underneath it — and because re-ranking each time would keep handing
## back the same top card she was just refused.
var _appr_shortlist: Array[int] = []

func _start_appraisal_mode() -> void:
	_appr_mult = 1.0
	_appr_shown = 1
	_appr_shortlist = _appraisal_shortlist()
	if _appr_shortlist.is_empty():
		_show_result("You have no card she will buy.")
		return
	_appr_index = _appr_shortlist[0]
	_build_appraisal_screen()


## Rank the deck by what she is looking for and keep the top few. Curses are
## excluded outright — she has standards.
func _appraisal_shortlist() -> Array[int]:
	var ranked: Array[int] = []
	for i in range(RunState.deck.size()):
		if not CardDB.is_curse(RunState.deck[i]):
			ranked.append(i)
	# Shuffle BEFORE sorting. `sort_custom` is not stable, and more to the point
	# a deck holds duplicates — two copies of one card tie exactly, so without
	# this she would name the same three deck slots on every visit of every run.
	ranked.shuffle()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return _appraisal_worth(a) > _appraisal_worth(b))
	return ranked.slice(0, mini(APPR_MAX_SHOWN, ranked.size()))


func _appraisal_worth(deck_index: int) -> int:
	var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	var worth: int = int(APPR_RARITY_WORTH.get(
		String(data.get("rarity", "common")), 10))
	if RunState.is_card_upgraded(deck_index):
		worth += APPR_FORGED_WORTH
	# Cost only breaks ties inside a band — it must never outrank a whole
	# rarity step, which is why the bands are spaced 10 and cost tops out at 6.
	return worth + int(data.get("cost", 0))


func _appraisal_price(deck_index: int) -> int:
	var data = RunState.get_upgraded_card_data(deck_index)
	var base: int = 30
	match String(data.get("rarity", "common")):
		"starter": base = 15
		"common": base = 30
		"uncommon": base = 50
		"rare": base = 85
	if RunState.is_card_upgraded(deck_index):
		base += APPR_FORGED_PRICE
	return int(round((base + int(data.get("cost", 0)) * 5) * _appr_mult))


func _build_appraisal_screen() -> void:
	var data = RunState.get_upgraded_card_data(_appr_index)
	var price := _appraisal_price(_appr_index)

	# The shortlist IS the alternate test now — it was built from the whole deck
	# on entry, so "is there another" is just "has she shown them all".
	var can_another: bool = _appr_shown < _appr_shortlist.size()
	var n_choices: int = 3 if can_another else 2
	# Choices sit right of the appraised card (96–321), so widen the left inset.
	var choices_vbox := _build_event_screen(
		"She holds up [color=#e8b547]%s[/color]" % String(data.get("name", "a card")),
		"She asks for your best, and names a price.",
		n_choices, 360, 980)
	var build_gen := _ui_build_gen

	# The card itself, stood on the scrim left of the choices.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.size = Vector2(225, 300)
	wrapper.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	wrapper.offset_left = 96
	wrapper.offset_right = 321
	wrapper.offset_top = -40
	wrapper.offset_bottom = 260
	add_child(wrapper)
	var back := _make_picker_card_back(wrapper, wrapper)
	_hydrate_appraisal_card(wrapper, data, back, build_gen)

	choices_vbox.add_child(_make_frameless_choice("Sell it",
		"Trade %s for %d gold." % [String(data.get("name", "the card")), price],
		"Her hand is already open under the slot.", 84, _on_appraisal_sell))
	if can_another:
		choices_vbox.add_child(_make_frameless_choice("Show her another",
			"Look at a different card.",
			"\"As you like. The figure was for the other one.\"", 84,
			_on_appraisal_another))
	choices_vbox.add_child(_make_frameless_choice("Keep your things", "",
		"She slides the card back without a word.", 84,
		_on_stranger_hand_leave))


func _on_appraisal_sell() -> void:
	# Deck floor of 1 — she won't leave you with nothing to your name.
	if RunState.deck.size() <= 1:
		_show_result("You cannot sell your last card.")
		return
	var data = RunState.get_upgraded_card_data(_appr_index)
	var price := _appraisal_price(_appr_index)
	# Campaign memory: the shelf keeps what it buys. A later visit (act 2+)
	# offers this card back through the pawn_buyback blue option.
	RunState.pawned_cards.append(RunState.deck[_appr_index])
	RunState.remove_card_at(_appr_index)
	RunState.gain_gold(price)
	_sting("coin")
	_show_result("Sold %s for %d gold." \
		% [String(data.get("name", "The card")), price])


func _on_appraisal_another() -> void:
	# Walk DOWN the shortlist — she offered her best first, so each refusal
	# costs twice: a lesser card, and 15% off the figure. The old version rolled
	# a fresh random index, which could hand back a card she had already shown.
	if _appr_shown >= _appr_shortlist.size():
		return
	_appr_index = _appr_shortlist[_appr_shown]
	_appr_shown += 1
	_appr_mult *= 0.85
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

const EventData = preload("res://scripts/data/EventDB.gd")
const EVENTS: Dictionary = EventData.EVENTS
