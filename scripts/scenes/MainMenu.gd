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
const RECRUIT_SCENE = "res://scenes/recruit.tscn"
const WAYSIDE_SCENE = "res://scenes/wayside.tscn"
const COLLECTION_SCENE = "res://scenes/collection.tscn"
const CREDITS_SCENE = "res://scenes/credits.tscn"
const SKIRMISH_SCENE = "res://scenes/net_lobby.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE_PICKER = preload("res://assets/ui/card_back.png")

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
var _title_shimmer_delay_tween: Tween = null
const MENU_MOTION_STEP := 1.0 / 30.0
var _menu_motion_accumulator := 0.0
var _menu_motion_suspended := false
var _subscreen_obscures_motion := false
var _how_to_play_overlay: Control = null

# THE MUSTER's shared panes. `_hero_detail` is THE COLUMN — rebuilt per focused
# lord by _build_muster_roll on every step that draws it. The roster row itself
# stays down to portrait + name + tagline; THE COLUMN carries the loadout.
## The lord's half of the page: an HBox holding the PLATE and the DOSSIER. It was
## a VBox while the two were stacked; the full-page composition stands them side
## by side, and every consumer only ever clears and refills it.
var _hero_detail: Container = null
## The deck's own band on RUN SETUP. It rebuilds with the lord like the dossier
## does, but it lives outside the three columns, so it needs its own handle.
var _hero_deck_rail: VBoxContainer = null
var _hero_cards: Dictionary = {}       # hid -> Button (for selected-state styling)
var _hero_portraits: Dictionary = {}   # hid -> Control (for focus brighten/dim)
var _selected_hero: String = ""
var _run_commit_locked := false
var _picker_commit_locked := false
var _picker_build_generation := 0
## One-way latch on every path that LEAVES the menu scene — see _leave_for.
var _scene_exit_locked := false
# One snapshot per menu rebuild. The title page used to parse the same save JSON
# up to five times to find the recent slot, print its preview, and fill its
# dossier. Every consumer below is read-only; save mutations rebuild the page.
var _slot_summary_cache: Array[Dictionary] = []
# Full-size readable copy of a hovered deck mini (the NetDraft ledger-preview
# behaviour). Child of the menu root; freed on unhover / pane rebuild.
var _deck_preview: Control = null
var _deck_inspect_overlay: Control = null
var _deck_inspect_return_focus: Control = null
var _deck_inspect_generation: int = 0


# Run-setup state. Every choice stays local and reversible until the run
# commits; only then are pending fields handed to RunState and consumed.
var _selected_writ_id: String = ""
var _muster_random_seed: int = 1
# The typed seed lives on the OBJECT, not in the LineEdit. The seed field is
# built on the terms step only, but _pending_run_seed() is read by every step
# (the terms deal off it, the campaign preview reads it, and _begin_run_with
# commits it) — parked in the node it would silently revert to the random seed
# the moment the player stepped away from the field that set it.
var _muster_seed_text: String = ""
var _muster_step: int = 1
var _muster_writ_slate: Array = []
var _muster_writ_buttons: Dictionary = {}
var _muster_writ_row: HBoxContainer = null
var _muster_campaign_label: Label = null
var _muster_gloss_label: Label = null
var _muster_order_term_detail: VBoxContainer = null
var _muster_setup_preset: Dictionary = {}
var _writ_resolution_rng: RandomNumberGenerator = null
var _quick_march_active: bool = false
var _quick_march_stage: int = 1
var _quick_march_roll_generation: int = 0
var _muster_advanced_open: bool = false
var _run_options_overlay: Control = null
var _run_options_return_focus: Control = null
# Hero/doctrine changes rebuild two physical parts of one character sheet. Keep
# their lifetime and reveal joined so a deferred free cannot leave old and new
# cards sharing the same layout frame, and a rapid second choice cannot finish
# the first choice's animation over the new lord.
var _muster_roll_ready := false
var _muster_roll_generation := 0
var _muster_roll_tween: Tween = null
# True only while _show_starting_bonus owns the Menu VBox. It is what makes a
# writ tile a COMMIT rather than a selection, and what keeps the run-setup
# screen's own rebuilds from stamping a seal on a term nobody pressed.
var _bonus_screen_open: bool = false
# Whether the player has actually pressed a term on it. Separate from
# _selected_writ_id, which is never empty by design.
var _bonus_pick_made: bool = false


## `DotLeader` STOOD HERE and was deleted with the dossier rebuild (2026-09-18).
##
## It was the only consumer, and it was measured off the render as pure non-data
## ink: a leader is a connectedness cue for a long traverse in a wide table, and
## this one ran ~250px to reach a ONE-CHARACTER value, four times over. Grouping
## a caption with its figure across that gap is what proximity and a shared right
## edge already do for free. See `_dossier_figure`.


## THE SIGNATURE RULE on a writ — the line a name goes on.
##
## Drawn rather than styled, because the alternative spellings are both wrong:
## a `Panel` with one border draws the other three sides too, and a `draw_line`
## at one alpha is a band of UNIFORM OPACITY, which is the flat-primitive defect
## this pass exists to take off this screen. One `draw_polyline_colors` with
## per-point alpha gives the run a real profile along its length — the nib bites
## harder where it was set down and lightens as it is drawn across, which is what
## a straightedge line in iron-gall ink actually looks like.
##
## Machine-STRAIGHT, unlike the sheet's torn edge, with only a hair of bow: the
## clerk had a straightedge, and a signature rule that wanders reads as a
## scribble rather than as a form.
class SignatureRule extends Control:
	var ink := Color(0.302, 0.224, 0.141, 0.66)
	var seed_text := "sign"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		if size.x <= 16.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_text)
		var ph := rng.randf() * TAU
		var y := size.y - 3.0
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var n := 26
		for i in range(n + 1):
			var t := float(i) / float(n)
			# A hair of bow (under a pixel) plus a slow waver — enough that the
			# eye does not read a ruled CSS border, not enough to read as freehand.
			pts.append(Vector2(lerpf(2.0, size.x - 2.0, t),
				y + sin(t * PI) * -0.7 + sin(t * TAU * 1.5 + ph) * 0.35))
			# The nib is wettest where it lands and runs dry across the sheet; the
			# very ends lift so the stroke has no hard stop.
			var bite: float = (1.0 - t * 0.42) * clampf(sin(t * PI) * 3.2, 0.0, 1.0)
			cols.append(Color(ink.r, ink.g, ink.b, ink.a * bite))
		draw_polyline_colors(pts, cols, 1.5, true)


func _ready() -> void:
	# Standing on the title screen means no skirmish launch is in flight, whatever
	# happened on the way here. Disarming keeps the latch SELF-LIMITING: a launch
	# whose deferred swap was superseded (a BACK press winning the same frame)
	# would otherwise stay armed and make the next campaign fight — CONTINUE, from
	# this very screen — look like an abandoned skirmish and bounce straight back.
	SkirmishState.launch_armed = false
	GameTheme.add_atmosphere(self, "main_menu")
	# Session-stable, not run-stable: the key carries no "run:" prefix, so
	# clear_music_themes leaves it alone and the shell keeps ONE voice from boot
	# to quit — the menu is the game's face and it was rotating three ways every
	# time you backed out of a run. A fresh launch draws again.
	AudioBank.play_music_theme("menu", ["main_menu", "main_menu_b", "main_menu_c"])
	_rebuild_menu()
	_setup_bg_parallax()
	_add_menu_embers()
	# MARCH AGAIN from the game-over screen: skip the menu beat entirely and open
	# THE MUSTER on its last step with the ended run's lord, colours and doctrine
	# already restored — one click from the field. The menu column was built above
	# because _show_hero_select builds into it and bails if it is missing.
	if not RunState.rematch_request.is_empty():
		_start_rematch()
		return


func _unhandled_input(event: InputEvent) -> void:
	if _deck_inspect_overlay != null and is_instance_valid(_deck_inspect_overlay) \
			and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_hide_deck_inspector()


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
	# Restore the muster picks the ended run marched with. A rematch never runs
	# _focus_hero, so these flags would otherwise sit at their declaration
	# default of false and quietly hand back the hero's DEFAULT relic and deck.
	var hero_id := String(req.get("hero", ""))
	var hero_def: Dictionary = HeroDB.HEROES.get(hero_id, {})
	# A pre-mastery rematch may restore only the authored bound doctrine. A4+
	# mastery restores the two axes independently.
	var was_relic := String(req.get("signature_relic", ""))
	var was_deck := String(req.get("deck_variant", ""))
	var alt_relic := String(hero_def.get("relic_alt", ""))
	var wants_alt_relic := alt_relic != "" and was_relic == alt_relic
	var wants_alt_deck := was_deck == "alt"
	_muster_alt_relic = false
	_muster_alt_deck = false
	if _bound_doctrine_unlocked(hero_id):
		if _doctrine_mastery_unlocked(hero_id):
			_muster_alt_relic = wants_alt_relic
			_muster_alt_deck = wants_alt_deck
		elif wants_alt_relic and wants_alt_deck:
			_muster_alt_relic = true
			_muster_alt_deck = true
	# Hand the restored picks to RUN SETUP rather than committing here. Calling
	# _begin_run_with directly skipped the only two things _show_hero_select does
	# that a run cannot start without:
	#
	#   * the SEED. _pending_run_seed falls through to _muster_random_seed, whose
	#     declaration default is 1 and which is randomised nowhere else — so every
	#     MARCH AGAIN on every profile ran seed 1: the same act 1 map, the same
	#     rival deal, the same season, forever.
	#   * the TERMS. _muster_writ_slate is only filled by _refresh_muster_deals, so
	#     `chosen` came back empty and _begin_run_with faded straight to the map. A
	#     rematch silently forfeited the whole starting bonus.
	#
	# Landing on RUN SETUP rather than committing blind is also the honest shape:
	# the bonus is dealt off a NEW seed, so it is not the one the player just
	# marched under and cannot be carried over. One click to START RUN, and the
	# roster is live if they want a different lord.
	_muster_setup_preset = {
		"hero": hero_id,
		"alt_relic": _muster_alt_relic,
		"alt_deck": _muster_alt_deck,
	}
	_show_hero_select(3)


func _rebuild_menu() -> void:
	_set_subscreen_motion_obscured(false)
	_refresh_slot_summary_cache()
	# Wipe the placeholder children from the .tscn so we can build the menu
	# entirely from code with consistent fonts/styles. The Background atmosphere
	# is preserved (it was added by add_atmosphere()).
	#
	# DETACH BEFORE THE DEFERRED FREE, OR THE REBUILT COLUMN LOSES ITS NAME.
	# queue_free() does not remove the node — it schedules a free at the end of
	# the frame — so the outgoing column was still a child named "Menu" when the
	# new one was added below, and add_child resolves that collision by renaming
	# the INCOMING node (to @VBoxContainer@N). Godot never renames it back once
	# the old one is finally freed, so from the first return to this screen
	# onward every `get_node_or_null("Menu")` found nothing.
	#
	# That is nine call sites, and all of them open with `if menu == null: return`
	# — so NEW RUN, LOAD GAME, the muster and the settings return silently did
	# NOTHING on the second press, with no error anywhere. `MenuScrim` and
	# `TitleLabel` are rebuilt here under fixed names too and were lost the same
	# way. remove_child is safe inside the button callback that gets us here (it
	# detaches, it does not free), and it also stops the two columns being drawn
	# on top of each other for the frame between the rebuild and the free.
	for child in get_children():
		var n: String = child.name
		if n == "Background" or n == "Atmosphere":
			continue
		remove_child(child)
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

	# ── Legibility scrim ──
	# The main-menu fire art is bright/busy behind the left column, washing out
	# the epigraph/subtitle/stats. A warm-dark horizontal gradient — opaque at
	# the left edge, clear by mid-screen — seats the text without touching the
	# hero splash on the center-right. Added before the column so it renders
	# behind it (and above the preserved Background/Atmosphere). Warm-black, not
	# pure black, so it stays inside the sepia world.
	var scrim := TextureRect.new()
	scrim.name = "MenuScrim"
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 0.70])
	grad.colors = PackedColorArray([
		Color(0.03, 0.015, 0.0, 0.66),
		Color(0.03, 0.015, 0.0, 0.44),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 256
	gtex.height = 8
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(1, 0)
	scrim.texture = gtex
	add_child(scrim)

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
		"You started this fire long ago. Now the road is waiting for you.",
		17, IVORY)
	epigraph.name = "Epigraph"
	epigraph.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	epigraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epigraph.custom_minimum_size = Vector2(600, 0)
	col.add_child(epigraph)

	# ── Ornament: gilt line with central rosette glyph (a diamond, NOT a triangle).
	# This is the "card-game opening flourish" — it sells the screen as a deck-
	# builder rather than a generic Godot template. Left-flush to match the column.
	col.add_child(_make_ornament_row(260.0, true, true))   # the one glyphed row

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
	# CONTINUE jumps into the most recent save; NEW RUN opens the run-setup
	# screen (hero pick, which now also owns ascension / daily / seed — those
	# used to be three separate top-level menu entries); LOAD GAME appears
	# only when a SECOND slot is filled (with one save, CONTINUE covers it).
	var has_any_save := _any_save_exists()

	# All main-menu buttons share one font size and height. The previous mix of
	# 17/19/20/22/24 sizes felt random; uniform sizing reads like a single menu
	# group (matches Ratropolis / Slay the Spire conventions).
	#
	# THIS COMMENT USED TO CLAIM "visual hierarchy comes from per-button COLOR,
	# not size" and each call below still passes a distinct Color. It was not
	# true and had not been for some time: `_make_menu_button`'s second parameter
	# is named `_bg` precisely because it drives nothing — every item rendered as
	# identical ivory, so CONTINUE and QUIT carried exactly the same weight on
	# the first screen of the game. Hierarchy on this column now comes from the
	# three channels that actually reach the render: the CONTINUE preview line
	# beneath its own button, the press CUE (commit vs select — see
	# `_arm_shell_button`), and order. The colours are left in place only as
	# call-site documentation of intent; do not add a fourth item believing the
	# colour will distinguish it.
	const MENU_FONT := 22
	const MENU_H := 40
	if has_any_save:
		var recent_slot := _most_recent_slot()
		var btn_continue := _make_menu_button("CONTINUE",
			Color(0.32, 0.26, 0.14), MENU_FONT, MENU_H)
		btn_continue.tooltip_text = _continue_preview_line(recent_slot, true)
		btn_continue.pressed.connect(_on_continue_recent)
		# Taking a march back up is a commit, not a browse.
		_set_shell_cue(btn_continue, "commit")
		col.add_child(btn_continue)
		# ONE LINE, INDENTED ONTO THE BUTTON IT DESCRIBES (2026-08-04). Two faults,
		# both measured on the render:
		#   * It printed "Act 1, Province 1 - HP 30/30 - 175g" — the same four facts
		#     the CURRENT RUN dossier prints as ruled figures 1200px to the right.
		#     The dossier is the better telling (captions, leaders, its own accent
		#     per figure), so this one collapses to what the dossier cannot say:
		#     which run Continue would actually resume.
		#   * Its ink began at canvas x 131 while the button labels beside it begin
		#     at 178, so the line describing CONTINUE aligned with the page title
		#     instead of with CONTINUE. The offset is exactly the flame slot; the
		#     lead spacer below is that slot.
		var preview_row := HBoxContainer.new()
		preview_row.add_theme_constant_override("separation", 0)
		var preview_lead := Control.new()
		preview_lead.custom_minimum_size = Vector2(
			MENU_FLAME_SLOT + MENU_FLAME_GAP, 0)
		preview_lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_row.add_child(preview_lead)
		var preview := _make_caption_label(_continue_preview_line(recent_slot), 15,
			Color(0.91, 0.76, 0.48))
		preview.name = "ContinuePreview"
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.custom_minimum_size = Vector2(560, 0)
		preview_row.add_child(preview)
		col.add_child(preview_row)

	# NEW RUN, and it stays NEW RUN (COPY_STYLE §12, the 2026-08-06 plain-language
	# pass). An earlier note here argued for NEW MARCH on the grounds that "the
	# whole opening speaks march"; §12 retired that register from UI chrome and
	# settled the noun — the thing you start is a RUN, on every screen. Do not
	# re-split it.
	#
	# "ASCENSION %d", not "ASC %d" (2026-09-10): the stepper on the run-setup
	# screen, the save-slot lines and the ascension rules readout all spell the
	# word out, so the one place that abbreviated it was the odd one out — and an
	# abbreviation on the FIRST screen of the game is a word a new player has not
	# met yet.
	var begin_label: String = "NEW RUN"
	if MetaState.unlocked_ascension > 0:
		begin_label = "NEW RUN — ASCENSION %d" % _selected_ascension
	var btn_start := _make_menu_button(begin_label,
		Color(0.18, 0.36, 0.18), MENU_FONT, MENU_H)
	btn_start.pressed.connect(_on_new_run)
	_set_shell_cue(btn_start, "commit")
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
		_leave_for(SKIRMISH_SCENE))
	col.add_child(btn_skirmish)

	var btn_gallery := _make_menu_button("COLLECTION",
		Color(0.16, 0.20, 0.32), MENU_FONT, MENU_H)
	btn_gallery.pressed.connect(func():
		_leave_for(COLLECTION_SCENE))
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

	# ── The campaign record ──
	# Bottom ornament, then the player's history — as MATERIAL, not only as a
	# sentence. See _build_campaign_record.
	col.add_child(_make_ornament_row(200.0, true))
	col.add_child(_build_campaign_record())

	# Small "Credits" text link below the stats — kept low-key so it doesn't
	# compete with the primary action buttons, but always accessible. Title Case,
	# not lowercase: the quiet comes from the size and the colour, and a control
	# name in the shell is Title Case everywhere else.
	var credits_btn := Button.new()
	credits_btn.text = "Credits"
	credits_btn.flat = true
	credits_btn.focus_mode = Control.FOCUS_ALL
	credits_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	credits_btn.custom_minimum_size = Vector2(0, 26)
	# `flat` STOPS THE BOX BEING DRAWN, NOT ITS MARGINS BEING SPENT. The default
	# theme's button stylebox still placed this label, so the word sat 4px right
	# of the rail the title, the tagline, the epigraph, both rules and the record
	# line all share — measured off the render at x=115 against their 111. An
	# explicit empty box is the house pairing for `flat` (and the one the
	# flat/stylebox contradiction scan in `_probe_input_reach` expects).
	var credits_empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		credits_btn.add_theme_stylebox_override(st, credits_empty)
	# `flat` STOPS THE BOX BEING DRAWN, NOT ITS MARGINS BEING SPENT. The default
	# theme's button stylebox still placed this label, so the word sat 4px right
	# of the rail the title, the tagline, the epigraph, both rules and the record
	# line all share — measured off the render at x=115 against their 111. An
	# explicit empty box is the house pairing for `flat` (and the one the
	# flat/stylebox contradiction scan in `_probe_input_reach` expects).
	credits_btn.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	credits_btn.add_theme_color_override("font_color", Color(0.74, 0.70, 0.62))
	credits_btn.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	if GameTheme.font_body:
		credits_btn.add_theme_font_override("font", GameTheme.font_body)
	credits_btn.pressed.connect(func():
		_leave_for(CREDITS_SCENE, 0.30))
	col.add_child(credits_btn)

	# Build stamp — a dev-only confirmation that the running code is the latest
	# source (if you DON'T see this line, the editor is running cached scripts:
	# restart, then F5). Debug builds only — exported releases don't ship a
	# work-log line on the title screen.
	if OS.is_debug_build():
		# Stamped from the SOURCE's own modification time, not a hand-typed
		# date. The whole point of this line is to prove the running code is
		# current — a literal string can't do that job, and this one had read
		# "build 2026-07-07 · polish + hardening" for a fortnight while the
		# game moved on underneath it. Nothing left to remember to bump.
		var src := "res://scripts/scenes/MainMenu.gd"
		var mtime := FileAccess.get_modified_time(src)
		var stamp_text := "dev build"
		if mtime > 0:
			stamp_text = "dev build · source %s" % \
				Time.get_datetime_string_from_unix_time(int(mtime)).left(10)
		var build_stamp := GameTheme.make_label(stamp_text, 13,
			Color(0.82, 0.66, 0.32, 0.62))
		build_stamp.name = "BuildStamp"
		build_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(build_stamp)

	_build_command_dossier(has_any_save)

	# Re-arm the title's idle shimmer on every rebuild (the title node is recreated
	# here; ascension changes rebuild without replaying the intro).
	_start_title_shimmer()

	# Boot entrance: the column writes itself in top-to-bottom, once per visit
	# to the menu (rebuilds from the ascension stepper skip it).
	_play_entrance(col)


## One-shot entrance cascade for the menu column: each row fades in and slides
## the last 16px to its resting x, staggered down the column. Runs once —
## _rebuild_menu calls back in here on every ascension change and the cascade
## would read as flicker on the second pass. Reduce Motion skips it whole.
var _entrance_played := false

func _play_entrance(col: Control) -> void:
	if _entrance_played:
		return
	_entrance_played = true
	if DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		return
	# Hide and gate the complete, already-built column BEFORE the first await.
	# The old order painted the finished menu for one frame, then made it vanish
	# and started the cascade — a visible flash on fast boots. Children still
	# occupy their final VBox slots, so this changes only paint and input.
	var entrants: Array[Control] = []
	for child in col.get_children():
		if child is Control:
			var entrant := child as Control
			entrant.modulate.a = 0.0
			entrants.append(entrant)
	var gated_buttons: Array[BaseButton] = []
	for node in col.find_children("*", "", true, false):
		if node is BaseButton and not (node as BaseButton).disabled:
			var button := node as BaseButton
			button.disabled = true
			gated_buttons.append(button)
	# The dossier is a sibling of the menu column, so include it in this SAME
	# entrance timeline. The retired _animate_intro used to start a second set of
	# alpha tweens over every menu row; at Fast/Instant speed those continued
	# after this gate unlocked and dimmed live buttons again.
	var dossier := get_node_or_null("CommandDossier") as Control
	if dossier != null:
		dossier.modulate.a = 0.0
	# Guarantee one PAINTED hidden layout frame. A process-frame await can resume
	# before the first draw on a cold boot and start the tween in that first image.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(col):
		return
	var i := 0
	var timeline := col.create_tween().set_parallel(true)
	var rest_positions: Dictionary = {}
	for c in entrants:
		if not is_instance_valid(c) or c.get_parent() != col:
			continue
		var rest_x := c.position.x
		rest_positions[c.get_instance_id()] = rest_x
		c.position.x = rest_x - 16.0
		var delay := Motion.time(0.05 + i * 0.045)
		timeline.tween_property(c, "modulate:a", 1.0, Motion.time(0.26)) \
			.set_delay(delay).set_ease(Tween.EASE_OUT)
		timeline.tween_property(c, "position:x", rest_x, Motion.time(0.30)) \
			.set_delay(delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		i += 1
	if dossier != null and is_instance_valid(dossier):
		timeline.tween_property(dossier, "modulate:a", 1.0, Motion.time(0.34)) \
			.set_delay(Motion.time(0.18)).set_ease(Tween.EASE_OUT)
	await timeline.finished
	# Tween.finished is emitted before the finished values are necessarily painted.
	# Commit the exact final state first; only then release the controls.
	for c in entrants:
		if is_instance_valid(c) and rest_positions.has(c.get_instance_id()):
			c.modulate.a = 1.0
			c.position.x = float(rest_positions[c.get_instance_id()])
	for button in gated_buttons:
		if is_instance_valid(button):
			button.disabled = false
	if dossier != null and is_instance_valid(dossier):
		dossier.modulate.a = 1.0


# ---------------------------------------------------------------------------
# FACTORIES
# ---------------------------------------------------------------------------

func _make_display_label(text: String, size: int, color: Color) -> Label:
	# Display labels — used for everything in the menu so the typography is
	# unified. Uses font_display (Cinzel SemiBold) so titles look chiseled.
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", maxi(size, GameTheme.MIN_LABEL_SIZE))
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## THE CAPTION FLOOR IS 15, AND IT IS NOT THE READING FLOOR (2026-08-04).
##
## Measured symptom: fifteen call sites hand _make_display_label a 13-16, and
## every one of them renders at 18, because that helper clamps to
## GameTheme.MIN_LABEL_SIZE. Worked example, THE COLUMN's detail pane on step II
## — "OPENER CHANGE" (written 14), "+ Line Marker" (22), "RECRUITMENT BIAS" (14)
## and the bias line (16): four levels of intended hierarchy, three of them
## printed at the identical size, separated only by a 0.617-vs-0.733 luminance
## step. A small-caps eyebrow as large as the body it captions is not an eyebrow,
## it is a second heading.
##
## The clamp itself is right and stays: 18 is the floor for text the player
## READS. But COPY_STYLE §11 licenses 15-17 for captions, and nothing in this
## file could reach that band. This helper is that band, and it is deliberately
## a SEPARATE function rather than a flag on the other one, so the choice of
## register is made at the call site and is greppable.
##
## font_body (not the display Cinzel): the in-tree precedent is the step rail's
## own subtitle, a raw Label at 15 in font_body, and it is the one place in the
## flow where caption-versus-title already reads correctly. Caps-only Cinzel at
## 15 sets very wide and very light — it goes grey before it goes small.
##
## USE FOR: small-caps eyebrows, the CHOSEN marker, fact/metadata lines that
## qualify something larger next to them. NOT for sentences — a sentence is
## reading text and belongs at 18 through _make_display_label.
const CAPTION_MIN_SIZE := 15
const CAPTION_MAX_SIZE := 17

func _make_caption_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size",
		clampi(size, CAPTION_MIN_SIZE, CAPTION_MAX_SIZE))
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## The flame cursor's reserved slot, and the gap after it. Anything that has to
## line up with a menu button's LABEL (rather than with its hit box) must be
## indented by their sum — the flame is packed ahead of the label and holds its
## footprint even while invisible, so the ink starts 40px in.
const MENU_FLAME_SLOT := 28
const MENU_FLAME_GAP := 12
## Resting alpha of a flame on a button that is ALREADY the forward move (the
## primary action tab, TAKE THE FIELD). Every other item ignites from 0 on hover;
## these burn before you reach them, which is the whole hierarchy device. Not
## 1.0 — hover has to have somewhere left to go.
const TAKE_FIELD_FLAME_REST := 0.82
## Diameter of the wax seal pressed into an accepted term. Square by necessity —
## WaxSeal works off `min(size.x, size.y)`, so a 34×26 host draws a 26px seal
## floating in a 34px box. 30 clears the 14px Roman device inside its impression.
const TERM_SEAL := 30
## The bonus sheet's box. 214, grown from 172 (2026-09-17) IN STEP with the type
## inside it — that pairing is the whole point. A taller box alone is the fault
## this const's history keeps recording: 236 was tried on the old wizard's terms
## step and left every tile two-thirds empty, which reads as a missing element
## rather than as breathing room. Here the sheet grew AND its name went 25 -> 29,
## so the tallest term (THE ARSENAL's four lines) now sets ~165px of ink against
## a 214px sheet: a document with a margin, not a box with a hole.
const TERM_TILE_H := 226
## Four tiles across MUSTER_STRIP_WIDTH_FULL at 16 separation: (1516-48)/4.
const TERM_TILE_W := 367.0
## Width of a plated forward action in a nav row. Before the primary treatment
## these were frameless words carrying EXPAND_FILL, so "wide" only meant a wide
## invisible click cell; now the plate is visible and EXPAND_FILL rendered ORDERS
## as a 900px bar. The button measures to this and the row centres it.
const NAV_PRIMARY_W := 340.0

func _make_menu_button(text: String, _bg: Color, font_size: int, height: int,
		with_flame: bool = true) -> Button:
	# Frameless text button (Slay the Spire / Hades style): no box at all — the
	# text *is* the button. On hover the label brightens to gilt, a flame ignites
	# on each side, and the whole label nudges right. The `_bg` param is retained
	# for call-site compatibility but no longer drives a fill. A dark outline
	# keeps the text legible over the busy fire background now that there's no
	# panel behind it.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, height)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
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
	inner.add_theme_constant_override("separation", MENU_FLAME_GAP)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	# Flame cursor only on the full-size action buttons — the small steppers
	# (−/+) and BACK links read better as plain text.
	#
	# `with_flame = false` keeps the button's other hover tells (the label comes up
	# to gilt, the rule fades in, the row slides right) but swaps the 28px flame
	# for a 12px lead, so the LABEL can be lined up with a panel's content column
	# instead of standing 28px out-dented from it. See _build_muster_nav.
	var flames: Array[TextureRect] = []
	if height >= 40:
		if with_flame:
			var flame_l := _make_flame_accent()
			inner.add_child(flame_l)
			flames.append(flame_l)
		else:
			var lead := Control.new()
			lead.custom_minimum_size = Vector2(0, 0)
			lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(lead)

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
	btn.focus_entered.connect(_on_menu_btn_hover.bind(inner, lbl, flames, rule, true))
	btn.focus_exited.connect(_on_menu_btn_hover.bind(inner, lbl, flames, rule, false))
	# The full-size action buttons get the press/hover scale; the small steppers
	# and BACK links (< 40px) do not — a 1.04 lift on a 17px word reads as a
	# wobble rather than as a lift.
	_arm_shell_button(btn, "select", 1.035 if height >= 40 else 1.0)
	return btn


## THE SHELL'S INTERACTION CONTRACT (2026-08-05) — one funnel, every button.
##
## Before this pass a shell button did three things on hover (label → gilt, flame
## fade, +12px slide) and *nothing whatsoever* on press: `_make_menu_button`
## assigns StyleBoxEmpty to all five states including `pressed`, so the click
## that started your run was visually and audibly identical to not clicking. The
## genre-standard shape is hover 1.05 → press 0.95 → release 1.0 inside the
## 100–300ms band; 0.18s was already in band, only the scale and the press were
## missing.
##
## `cue` is the sound the PRESS makes — "select" for an ordinary pick, "commit"
## for the two buttons that spend the next 40 minutes, "back" for retreat. Hover
## always ticks. Both halves are DECORATIVE by the Motion contract (they carry no
## game state), so the scale gates on Reduce Motion; the AUDIO does not, because
## a player who turns motion off has not asked for silence.
## The cue is read from meta at PRESS time, not captured at build time, so a
## caller can promote a button after the fact — `_set_shell_cue(btn, "commit")`
## — without the helper needing a parameter on every one of its call sites.
func _arm_shell_button(btn: Button, cue: String = "select",
		hover_scale: float = 1.0) -> void:
	btn.set_meta("shell_cue", cue)
	# One tick per arrival, whichever way the cursor or the keyboard got here.
	# TAKE THE FIELD mirrors focus into `mouse_entered` so keyboard nav inherits
	# the flame and the grow, which meant BOTH arms below fired for one focus and
	# the paper ticked twice — the stutter UI_CUE_MIX's hover level exists to
	# avoid. Debounce on the frame rather than dropping either arm: the mirror is
	# what gives the keyboard its body language, and every other shell button
	# needs the focus arm as its only tick.
	var hover_tick := func() -> void:
		if btn.disabled:
			return
		var frame := Engine.get_process_frames()
		if int(btn.get_meta("shell_hover_frame", -1)) == frame:
			return
		btn.set_meta("shell_hover_frame", frame)
		AudioBank.play_ui("hover")
	btn.mouse_entered.connect(hover_tick)
	btn.focus_entered.connect(hover_tick)
	btn.pressed.connect(func() -> void:
		if is_instance_valid(btn):
			AudioBank.play_ui(String(btn.get_meta("shell_cue", "select"))))
	if hover_scale <= 1.0:
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	# Scale from the control's own centre. `pivot_offset` has to be re-read at
	# press time, not at build time: these buttons are laid out by a VBox that
	# has not run yet when the helper is called, so a pivot captured here is
	# always Vector2.ZERO and the "grow" reads as a lurch to the right.
	var scale_to := func(target: float, dur: float) -> void:
		if not is_instance_valid(btn):
			return
		btn.pivot_offset = btn.size * 0.5
		var tw := btn.create_tween()
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(target, target), dur)
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			scale_to.call(hover_scale, 0.14))
	btn.mouse_exited.connect(func() -> void: scale_to.call(1.0, 0.14))
	# The press is the shared verb (2026-09-17). This screen hand-rolled the only
	# two button_down/button_up connections in the repo, which is exactly how the
	# rest of the game ended up with none — publish the lift it scales to and let
	# `arm_press` derive the rest pose from it, so retuning the press reaches the
	# title screen too instead of leaving it a dialect.
	btn.set_meta("_motion_hover_lift", hover_scale)


func _set_shell_cue(btn: Button, cue: String) -> void:
	## Promote (or demote) an already-armed button's press cue. "commit" is
	## reserved for the two buttons that spend the next 40 minutes — NEW RUN and
	## START RUN — and "back" for every retreat, so advance and retreat are
	## distinguishable with the screen unread.
	if btn != null and is_instance_valid(btn):
		btn.set_meta("shell_cue", cue)


func _make_secondary_action(text: String, width: float = 220.0,
		height: int = 36) -> Button:
	# Small actions used to borrow the frameless menu treatment. Below 40px that
	# treatment has no flame and no rule, so VIEW DECK and OPTIONAL RULES looked
	# exactly like passive captions at rest. Give secondary actions one quiet,
	# persistent document-tab frame: subordinate to TAKE THE FIELD, but plainly
	# operable before hover.
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, height)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 14)
	if GameTheme.font_display:
		btn.add_theme_font_override("font", GameTheme.font_display)
	btn.add_theme_color_override("font_color", Color(0.84, 0.78, 0.66))
	btn.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	btn.add_theme_color_override("font_focus_color", GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.94, 0.84, 0.60))
	btn.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01, 0.80))
	btn.add_theme_constant_override("outline_size", 3)

	# ── A TAB, NOT A FRAME (2026-09-15) ──
	#
	# The block above explains why these got a box in the first place, and it is
	# still true: at 14px with no flame and no rule, a frameless secondary reads
	# as a passive CAPTION, and a control nobody can see is a control nobody
	# presses. So this is not a strip-the-box change — that would walk straight
	# back into the bug the frame was built to fix.
	#
	# What was wrong is that a FULL border makes a rectangle, and after the
	# frameless pass these were the last rectangles on the page. A single bottom
	# rule keeps the affordance and loses the box: an underlined label is about as
	# universally "operable" as UI gets, and it is the same shape as the section
	# captions' hairline, so the screen keeps one vocabulary of rules instead of
	# gaining a second vocabulary of frames.
	#
	# Built as StyleBoxFlat directly because ChartPanelStyle draws its rule on all
	# four sides. Not a CAST of a kit style — that is the documented panel-kit trap
	# and yields null. Content margins are byte-identical to the framed version so
	# nothing on any of the six call sites shifts by a pixel.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_width_bottom = 1
	normal.border_color = Color(0.56, 0.48, 0.34, 0.80)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.11, 0.070, 0.040, 0.34)
	hover.border_width_bottom = 2
	hover.border_color = GILT_BRIGHT
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.055, 0.035, 0.028, 0.45)
	pressed.border_width_bottom = 2
	pressed.border_color = Color(0.76, 0.59, 0.30)
	for style in [normal, hover, pressed]:
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 5
		style.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	_arm_shell_button(btn, "select", 1.03)
	return btn


func _make_primary_action(text: String, height: int = 46) -> Button:
	## THE FORWARD MOVE (2026-08-05). `_make_secondary_action` shipped as "one
	## quiet, persistent document-tab frame: subordinate to TAKE THE FIELD" — but
	## there was no primary for it to be subordinate TO. Every forward action in
	## the shell (THE BANNER · THE TERMS · ORDERS · SEE YOUR COMPANY · TAKE THE
	## FIELD) was `_make_menu_button`, i.e. the exact frameless ivory text at the
	## exact size as the BACK sitting next to it. Nothing on any of those screens
	## said which way was on.
	##
	## The house answer is not a brighter rectangle — it is the flame. Every menu
	## item in this game ignites a flame on hover; the forward move is the one
	## that is ALREADY BURNING before you reach it. Warm parchment plate, gilt
	## rule, lit flame at rest, and it brightens rather than ignites under the
	## cursor.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, height)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.clip_contents = false

	## THE LOUDEST BUTTON IN THE GAME IS A SOLID NOW (2026-09-17). START RUN and
	## TAKE THE FIELD are the two presses that spend the next forty minutes, and
	## until today they were a flat fill under `ChartPanelStyle`'s four stacked
	## symmetric polylines — the lightning defect, on the one control the whole
	## screen is built to point at. `PlaqueStyle` gives it a molded edge whose
	## light inverts top-to-bottom, a face lit from the same lamp as that edge,
	## a specular sweep, and a press that drives the plate flush into the table.
	##
	## Tacks ON here, unlike the in-run primary: this plate is 340px wide and
	## carries the screen, so it can afford its own mounting hardware — and the
	## title screen's whole language is things pinned to a war table.
	# NO ENGRAVE ON THIS ONE, and the reason is structural rather than a
	# preference. `PlaqueStyle` strikes the word by deriving where `Button` would
	# centre its own text — but this button's word is NOT `Button.text`: it lives
	# in a child `Label` inside an HBox beside the flame (which is also why the
	# input pilot found `Button.text` empty on every MainMenu control). The row is
	# centred as a whole, so the label sits right of centre by half the flame and
	# its gap, and a plate striking the centre would print the shadow beside the
	# letters it belongs to. A stylebox cannot see a sibling's layout, and asking
	# it to would mean re-deriving an HBox's arithmetic in a painter.
	# NO PLATE — same call as the CTA below it. This button's signal is its
	# flame, lit at rest while the rest of the column's flames are dark; that is
	# what "which way is on" was always carried by, and the tab behind it was
	# only ever competing with it.
	var plate := StyleBoxEmpty.new()
	plate.content_margin_left = 16
	plate.content_margin_right = 16
	plate.content_margin_top = 6
	plate.content_margin_bottom = 6
	for which in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(which, plate)

	# Content mirrors _make_menu_button's row so the primary sits on the same
	# baseline grammar as the column it leads: flame slot, then the word.
	var inner := HBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", MENU_FLAME_GAP)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	var flame := _make_flame_accent()
	flame.modulate = Color(1, 1, 1, 0.82)   # LIT AT REST — this is the whole idea
	inner.add_child(flame)

	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.90, 0.70))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	# Engine-placed strike — see `GameTheme.engrave_label` and the `engrave:
	# false` note on this button's plaque above.
	GameTheme.engrave_label(lbl)
	inner.add_child(lbl)

	btn.mouse_entered.connect(_on_primary_hover.bind(flame, lbl, true))
	btn.mouse_exited.connect(_on_primary_hover.bind(flame, lbl, false))
	btn.focus_entered.connect(_on_primary_hover.bind(flame, lbl, true))
	btn.focus_exited.connect(_on_primary_hover.bind(flame, lbl, false))
	_arm_shell_button(btn, "select", 1.03)
	return btn


func _on_primary_hover(flame: TextureRect, lbl: Label, hovering: bool) -> void:
	lbl.add_theme_color_override("font_color",
		GILT_BRIGHT if hovering else Color(0.98, 0.90, 0.70))
	if not is_instance_valid(flame):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Already lit: hover BRIGHTENS rather than igniting. Never reaches 0 —
	# a primary that goes dark on mouse-out has stopped being a primary.
	tw.tween_property(flame, "modulate:a", 1.0 if hovering else 0.82, 0.16)


func _reduce_motion() -> bool:
	return UserSettings != null and UserSettings.reduce_motion


## Used by the save-slot marker further down this file — NOT by the campaign
## record, which carries no ornament any more (see below).
const WaxSeal := preload("res://scripts/ui/painters/WaxSeal.gd")
## The rest of the writ kit, borrowed from the card face for the starting-bonus
## sheets. Preloaded under their own names so those call sites read the same as
## Card2D's own.
const WritLeaf := preload("res://scripts/ui/painters/WritLeaf.gd")
const ParchmentPlate := preload("res://scripts/ui/painters/ParchmentPlate.gd")
const InkCartouche := preload("res://scripts/ui/painters/InkCartouche.gd")
const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")
const InlaidRule := preload("res://scripts/ui/painters/InlaidRule.gd")
## The CURRENT RUN plate's two figures. Both are "a quantity with a known extent
## laid along a track", which is the precondition for a positional encoding —
## see their headers for the Cleveland & McGill argument that replaced four
## dotted-leader rows with two drawn marks.
const RunRoad := preload("res://scripts/ui/painters/RunRoad.gd")
const VigourBand := preload("res://scripts/ui/painters/VigourBand.gd")
const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")
## The same stretch of camp-table wood Combat deals on, the war chart is pinned
## to, and every event minigame plays on. The starting bonus is a signing table;
## it may as well have the table.
const StageTable := preload("res://scripts/ui/painters/StageTable.gd")
## Where the table's far edge falls, as a fraction of canvas height. A FRACTION
## and not a constant: UI Scale divides the logical canvas (at 60% the UI lays
## itself out on 2667x1500), so a pixel offset here would put the horizon in a
## different place at four of the five settings offered — class C32, and
## `_probe_uiscale` is entitled to catch it.
## THE LORD'S PLATE on the bonus screen. Sized by MEASUREMENT, not by eye — see
## the sweep in `tools/_shot_bonus.gd::_plate_sweep` and the numbers in
## `docs/PRESENTATION_METHOD_20260917.md`.
## How far the bonus screen's column is TRANSLATED up from centred, in canvas px.
## Derived from a sweep, not chosen — see `_lift_menu_block`.
## THE BONUS PAGE'S RECT AND ITS LIFT — a single composition, derived from a
## 2D sweep graded on TWO oracles at once. See `_lift_menu_block` for the four
## sweeps that ruled out every other lever.
##
## The rect is deliberately just UNDER the column's own content height (599), so
## the slack spacers are pinned at ~1px and the block is content-tight. That is
## the half a balance score cannot see: pushing this page's 113px of slack below
## the writ row scored a near-perfect bal-H 0.997 and opened a 200px void between
## the gloss and BACK at the same time, because Ngo balance counts the table's dim
## wash as mass. Balance is necessary and is not sufficient on a painted ground.
##
## Measured at rect 600 across the lift (bal-H | tallest empty spacer):
##     lift  76 -> 0.629 | 1px      lift 105 -> 0.980 | 1px
##     lift  90 -> 0.797 | 1px      lift 120 -> 0.762 | 1px
## and for contrast, the same lift with the old slack left in:
##     rect 712 lift 76 -> 0.864 | 76px HOLE
const BONUS_PAGE_H := 600.0
const BONUS_BLOCK_LIFT := 105.0
const BONUS_PLATE_SIZE := Vector2(118, 158)
const BONUS_TABLE_TOP := 0.425

## THE CAMPAIGN RECORD — ONE SENTENCE, NO ORNAMENT (2026-09-14).
##
## The player's lifetime history, under the bottom ornament rule: "Runs N ·
## Wins N · Losses N", plus the best win when there is one.
##
## THIS ROW USED TO CARRY ITS OWN ORNAMENT AND THE ORNAMENT IS GONE ON THE
## OWNER'S CALL — DO NOT PUT IT BACK. The 2026-08-05 pass rendered the record
## TWICE: a rotated `TallyMarks` run scratching one stroke per march, and a row
## of 18px `WaxSeal` impressions, one per victory, above this sentence. The
## reasoning was sound on paper (the game's whole material language is an
## accumulating record, and the player's own record was the one thing rendered
## as plain text) and it did not survive contact with the screen. A card's left
## margin is not a menu footer: turned on its side under the column the tally
## run read as a smear of gold hyphens, and at 18px the seals are three flat
## dark-red dots indistinguishable from a bullet row. An ornament that has to be
## explained is decoration, and decoration under a menu column is clutter.
##
## The sentence was always the part that actually answered the question — and it
## is also the honest path for screen readers and for colourblind players, which
## the marks never were. It is the whole feature now.
func _build_campaign_record() -> Control:
	var stats := _make_display_label(_stats_text(), 17, Color(0.80, 0.75, 0.64))
	stats.name = "CampaignRecord"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return stats


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

	var summary: Dictionary = RunState.get_slot_summary(slot)
	var has_save: bool = summary.get("has_save", false)
	var unreadable: bool = summary.get("unreadable", false)
	var occupied := has_save or unreadable
	# ── STATE RIDES THE KEYLINE, NOT THE FILL (2026-08-05) ──
	# The three slots used to carry three different saturated FILLS — an olive
	# (0.32,0.26,0.14) for a waiting run, a dull red for a damaged one, a warm
	# charcoal for empty. Rendered, that is three unrelated flat rectangles
	# stacked in a list, and the olive one was the single brightest object on the
	# screen: a *list row* out-shouting the title above it. Flat colour fills are
	# also the one thing the house style rules out outright.
	#
	# The kit already solved this and said so in as many words —
	# `GameTheme.make_themed_button`: "Inked-parchment plaque, NOT a flat colour
	# fill — the caller's `bg` becomes the accent keyline, so a button that MEANS
	# something survives as ink while the button stops reading as a generic UI
	# rectangle." Same call here, and the same fix as the 2026-07-19 Shop shelf
	# pass: ONE tile, state in the accent.
	#
	# So every slot is the house dark doc-tile, and the ACCENT says what it is:
	#   gold   — a run waiting for you
	#   ember  — a run this build cannot read
	#   red    — this run is about to be replaced (overwrite mode)
	#   bronze — empty; the quietest row, because it is the least eventful
	# (The 2026-08-03 note about the empty slot's cold green is preserved by
	# construction: no slot carries a hue that isn't on the ember palette.)
	var bg := GameTheme.PARCHMENT
	var accent: Color
	if overwrite_mode and occupied:
		accent = Color(0.82, 0.32, 0.24)
	elif unreadable:
		accent = Color(0.78, 0.40, 0.28)
	elif has_save:
		accent = GILT_BRIGHT
	else:
		accent = Color(0.56, 0.46, 0.30)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	# Reuse the same stylebox treatment as the main menu buttons so the slot
	# rows feel like part of the same family.
	# Ask the kit for each state rather than duplicating — `duplicate() as
	# StyleBoxFlat` on a ChartPanelStyle silently yields null (the documented
	# panel-kit trap), and even the correct `as ChartPanelStyle` cast shares the
	# seed, so all four states would keep one silhouette. Asking again is both
	# safe and per-state.
	var normal := GameTheme.make_panel_style(bg, accent, 2, 5, false)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := GameTheme.make_panel_style(
		Color(0.19, 0.115, 0.058, 0.96), GILT_BRIGHT, 2, 5, true)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	var pressed := GameTheme.make_panel_style(
		Color(0.085, 0.060, 0.042, 0.98), accent, 2, 5, false)
	btn.add_theme_stylebox_override("pressed", pressed)
	# THE UNREADABLE SLOT HAD NO PLATE AT ALL (2026-08-03). An unreadable save
	# disables this button, and `disabled` was the one state with no override —
	# so Godot fell back to the project theme's disabled box, which draws nothing.
	# The audit shot shows the result: SLOT 3's two lines, one of them a full
	# sentence in ember-pink, printed directly onto the painted fire while the
	# two slots above it sat on solid plates. The row the player is least able to
	# act on was the row hardest to read. Same plate, drained of its light.
	var disabled := GameTheme.make_panel_style(
		Color(bg.r * 0.7, bg.g * 0.7, bg.b * 0.7, bg.a),
		Color(accent.r, accent.g, accent.b, 0.42), 2, 5, false)
	btn.add_theme_stylebox_override("disabled", disabled)
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
	if unreadable:
		title_text = "SLOT %d  ·  Run Unavailable" % (slot + 1)
		sub_text = "This save can't be read. Delete it to reuse the slot."
	elif has_save:
		if overwrite_mode:
			title_text = "SLOT %d  ·  Overwrite This Run" % (slot + 1)
		else:
			title_text = "SLOT %d  ·  Continue Run" % (slot + 1)
		var act_floor := "Act %d · Province %d" % [int(summary.act), int(summary.floor)]
		var hp_gold := "HP %d/%d · %dg" % [int(summary.hp), int(summary.max_hp), int(summary.gold)]
		if int(summary.ascension) > 0:
			hp_gold += " · Ascension %d" % int(summary.ascension)
		sub_text = "%s   ·   %s" % [act_floor, hp_gold]
	else:
		title_text = "SLOT %d  ·  Start a New Run" % (slot + 1)
		# "No saved run", not the bare adjective "Empty": an empty state names the
		# thing that is missing, and this line is read directly under a title that
		# says how to fill it (COPY_STYLE §12).
		if MetaState.unlocked_ascension > 0:
			sub_text = "No saved run   ·   Ascension %d" % _selected_ascension
		else:
			sub_text = "No saved run"
	# 22, not 20. The sub-line's call below asks for 14 and RENDERS AT 18 —
	# _make_display_label floors every size at GameTheme.MIN_LABEL_SIZE — so the
	# two lines were 20 over 18 and the slot read as one undifferentiated block
	# of type. The caption cannot be made smaller (18 is the readability floor),
	# so the rank has to come from the title going up.
	# With every plate now the same dark parchment, the state has to reach the
	# INK as well as the keyline or the three rows read as identical. Gold titles
	# a run that is waiting; ember titles one this build cannot read; the empty
	# slot's warm ivory is the quietest of the three, which is correct — it is
	# the row with the least to say.
	var title_ink: Color = accent if (has_save or unreadable) else Color(0.93, 0.88, 0.78)
	var title_lbl := _make_display_label(title_text, 22, title_ink)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(title_lbl)
	var sub_color := Color(0.90, 0.58, 0.48) if unreadable else (
		Color(0.74, 0.70, 0.62) if not has_save else Color(0.90, 0.83, 0.62))
	# Renders at 18 (MIN_LABEL_SIZE), not 14 — see the title note above.
	# The slot's state line is a caption of the slot's own title directly above it,
	# and at the floored 18 the pair read as two titles.
	var sub_lbl := _make_caption_label(sub_text, 15, sub_color)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(sub_lbl)

	if unreadable and not overwrite_mode:
		btn.disabled = true
	elif overwrite_mode or not has_save:
		btn.pressed.connect(_begin_new_in_slot.bind(slot))
	else:
		btn.pressed.connect(_load_slot_into_game.bind(slot))
	# Every path out of this row starts (or resumes) a march — a commit, not a
	# browse. The disabled row is armed too and simply never fires.
	_arm_shell_button(btn, "commit")
	# ── AND THE SAME GUTTER ON THE LEFT (2026-09-03) ──
	# The reserved delete column below fixed the rows against EACH OTHER; it left
	# the block wrong against the COLUMN. Reserving 52px (44 + the HBox's
	# separation) on the right alone means the plates occupy 568 of the screen's
	# 620-wide centred column, flush left — so on a fresh profile, where no slot
	# has a delete button and nothing fills that gutter, all three plates sit
	# 26px left of the centred "LOAD GAME" title above them. Measured off the
	# audit render: title ink centre 800.5, plate centre 773.5.
	# Mirroring the reservation puts the plate back on the screen's axis, and
	# `_show_load_screen` widens the column by the same 52 so the plates keep
	# the width they have today rather than shrinking to pay for it.
	var lead_gap := Control.new()
	lead_gap.custom_minimum_size = Vector2(44, 0)
	lead_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lead_gap)
	row.add_child(btn)

	# Delete button — only meaningful on filled slots, and only in normal load
	# mode (in overwrite mode the whole button is already destructive, so a
	# second delete affordance would just be confusing).
	if occupied and not overwrite_mode:
		var del := Button.new()
		# Plain Latin X — the U+2715 multiplication-x glyph isn't in every
		# display font, so it sometimes rendered as a tofu rectangle here.
		del.text = "X"
		del.custom_minimum_size = Vector2(44, 58)
		del.focus_mode = Control.FOCUS_ALL
		if GameTheme.font_display:
			del.add_theme_font_override("font", GameTheme.font_display)
		del.add_theme_font_size_override("font_size", 18)
		del.add_theme_color_override("font_color", Color(0.92, 0.65, 0.55))
		del.add_theme_color_override("font_hover_color", Color(1.0, 0.40, 0.30))
		# Same plate and same chamfer as the row it sits beside — it was a red
		# FILL at corner 8 against the row's 5, so it read as a loose badge
		# floating off the end of the list rather than as that row's own control.
		del.add_theme_stylebox_override("normal", GameTheme.make_panel_style(
			GameTheme.PARCHMENT, Color(0.62, 0.28, 0.22, 0.80), 2, 5, false))
		var del_hover := GameTheme.make_panel_style(
			Color(0.20, 0.075, 0.060, 0.96), Color(0.95, 0.45, 0.30), 2, 5, true)
		del.add_theme_stylebox_override("hover", del_hover)
		del.add_theme_stylebox_override("focus", del_hover)
		del.add_theme_stylebox_override("pressed", GameTheme.make_panel_style(
			Color(0.10, 0.045, 0.038, 0.98), Color(0.78, 0.36, 0.26), 2, 5, false))
		del.tooltip_text = "Delete this save."
		del.pressed.connect(_on_slot_delete.bind(slot))
		_arm_shell_button(del, "back")
		row.add_child(del)
	else:
		# THE DELETE COLUMN IS RESERVED ON EVERY ROW (2026-08-03), even where no
		# delete exists. The X is a sibling of the plate, so a row that carried
		# one handed 52px (44 + the HBox's 8 separation) of its width to it and a
		# row that did not kept them — three stacked plates with two different
		# right edges, and because each plate centres its own two lines, three
		# different centre axes. On the audit shot SLOT 1's title sat 40px left of
		# SLOT 2's. A list whose rows do not share an axis reads as three widgets.
		var del_gap := Control.new()
		del_gap.custom_minimum_size = Vector2(44, 0)
		del_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(del_gap)
	return row


## `stretch` makes `width` a MINIMUM and lets the rule fill whatever the parent
## gives it. A section divider inside a panel needs that: the muster panels call
## this with `minimum_width - 42`, and a panel that stretches past its minimum
## left the rule at its old length — 658px of rule under a heading in a box
## 1066px wide, stopping 62% of the way across. Only that caller opts in; the
## title column and the load screen want a rule of a chosen length, not a rule
## that grows to the whole column.
func _make_ornament_row(width: float, left_aligned: bool = false,
		glyph: bool = false, stretch: bool = false) -> Control:
	# 2026-07-30 — THE GLYPH IS NOW OPT-IN, AND EXACTLY ONE CALLER TAKES IT.
	#
	# The defence written below is real: this flourish is what stops the title
	# screen looking like a generic Godot template. But it was on TWELVE rows
	# across the menu, the run setup, the hero roster and the writ pick, and
	# a flourish that appears twelve times is wallpaper, not a flourish. Nine of
	# those sat directly under a heading that already announced its own section,
	# so the diamond was restating something the type had said better.
	#
	# The rule now: the glyph marks the TITLE COLUMN and nothing else. Every
	# other row keeps the gilt rule — the grouping was doing honest work — and
	# drops the ornament. Scarcity is what makes the one that survives read as
	# deliberate. (NN/g's aesthetic-and-minimalist heuristic: cut what carries
	# no information so what remains can carry some.)
	# A horizontal gold line broken by a central diamond — the "section break"
	# flourish you see in fantasy books. Previously used the U+25C6 unicode
	# character in a font that doesn't ship that glyph, so it rendered as a
	# tofu rectangle next to the divider lines (which themselves looked boxy
	# because they vertical-stretched to the row height). Now uses an actual
	# diamond.png texture and forces the lines to a fixed thin height.
	# left_aligned: a short lead-in stub + diamond + long trailing line, flushed
	# to the column's left edge (for the left-column menu layout).
	#
	# `width` IS THE ROW'S TOTAL RENDERED WIDTH (2026-09-03). It used to be a
	# loose scale factor — each half was sized `width * 0.45` and the separations
	# and the diamond were then added ON TOP — which happened to come out right
	# for the centred glyphed row (0.9w + 34 ≈ w at w=340) and was wrong
	# everywhere else. The dossier asked for 340 and got 183: a rule that stopped
	# barely past half the panel it was meant to divide, twice, on the title
	# screen. Every caller passes a number it means literally (`minimum_width -
	# 42.0` is the panel's inner width), so the parameter now means that.
	# Gate: `tools/_probe_alignment.gd`, HELPER CONTRACT section.
	const SEP := 10.0
	const DIAMOND := 14.0
	const STUB := 20.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(SEP))
	if stretch:
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif left_aligned:
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Furniture the glyphed row spends before either rule gets any width: the
	# diamond plus the separation on both sides of it.
	var spent: float = DIAMOND + SEP * 2.0 if glyph else 0.0
	var left_w: float = width
	if glyph:
		left_w = STUB if left_aligned else (width - spent) * 0.5

	# ── A DIVIDER IS A LENGTH OF METAL, NOT A BAR OF COLOUR (2026-09-18) ──
	#
	# These were `ColorRect`s: 2px, one flat value, hard ends. Measured on the
	# shipped screen, walking down through the rule under HOW HE FIGHTS, the whole
	# stroke read `0.450 0.448 0.450` between a page at 0.086 — three rows, ONE
	# value, a 5.2x step up and a hard step back. No cross-section at all, which
	# is the flat-`Line2D` defect this project has now fixed for combat FX, for
	# picture frames and for the dossier's tracks, and never for the humble rule.
	# It was also the loudest mark in the left column at THIRTY TIMES its ground,
	# for a thing that carries no information. See `InlaidRule`.
	var left: Control = InlaidRule.make(maxf(2.0, left_w),
		Color(GILT.r, GILT.g, GILT.b, 0.58))
	# On a stretching row the LAST rule takes the slack, so an unglyphed row
	# (which is a single rule) takes it here and a glyphed one takes it below.
	if stretch and not glyph:
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var diamond_tex := GameTheme.tex_icon_diamond
	if not glyph:
		# No ornament: the rule runs unbroken — which means ONE rect, already
		# sized to the full width above. The previous version added a SECOND
		# rect here in the name of "rejoining the two halves", and so re-opened
		# the very 10px hole (the HBox separation still sits between siblings)
		# that this branch exists to close.
		return row
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

	var right: Control = InlaidRule.make(maxf(2.0, width - spent - left_w),
		Color(GILT.r, GILT.g, GILT.b, 0.58))
	if stretch:
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	return row


## ONE SEPARATOR PER JOB (2026-08-04). The opening flow was running five of them
## — ` / `, ` · `, ` — `, ` - ` and `: ` — plus this line's `•`, four of which
## were doing the identical job of joining facts in a list. The house rule from
## here on: `·` joins facts, `—` introduces an appositive or an eyebrow's
## subject. The hyphen-minus was simply a typo for one of the two.
func _stats_text() -> String:
	var text := "Runs %d  ·  Wins %d  ·  Losses %d" % [
		MetaState.total_runs, MetaState.total_victories, MetaState.total_defeats,
	]
	# fastest_victory_floors was tracked from day one but shown nowhere.
	if MetaState.fastest_victory_floors > 0:
		text += "  ·  Best win: %d provinces" % MetaState.fastest_victory_floors
	return text


## The short form is what prints under CONTINUE, where the CURRENT RUN dossier is
## already carrying act / province / health / gold as ruled figures — so it names
## the run instead of restating them. The verbose form is the button's tooltip,
## which has no dossier beside it and so still spells the state out.
func _continue_preview_line(slot: int, verbose: bool = false) -> String:
	if slot < 0:
		return "No run in progress."
	var s := _slot_summary(slot)
	if not bool(s.get("has_save", false)):
		return "No run in progress."
	var asc := ""
	if int(s.get("ascension", 0)) > 0:
		asc = "  ·  Ascension %d" % int(s.get("ascension", 0))
	if not verbose:
		return "Continue from Act %d, Province %d.%s" % [
			int(s.get("act", 1)), int(s.get("floor", 0)), asc]
	return "Resume your saved run: Act %d, Province %d  ·  HP %d/%d  ·  %dg%s" % [
		int(s.get("act", 1)),
		int(s.get("floor", 0)),
		int(s.get("hp", 0)),
		int(s.get("max_hp", 30)),
		int(s.get("gold", 0)),
		asc,
	]


func _remove_command_dossier() -> void:
	var old := get_node_or_null("CommandDossier")
	if old != null:
		# RENAME BEFORE FREEING. `queue_free` is DEFERRED, so the outgoing panel
		# is still in the tree when the replacement is added on the same frame —
		# and Godot then silently renames the NEW node to dodge the collision,
		# after which `get_node_or_null("CommandDossier")` can never find it
		# again and every later rebuild stacks another plate on the pile. In
		# normal play the rebuilds are frames apart so it never bit; it showed
		# up the moment `_shot_dossier` rebuilt the plate six times in a row,
		# with the no-save panel printing a previous run's PURSE row below its
		# own bottom edge.
		old.name = "CommandDossierSpent"
		old.queue_free()


## THE PLATE'S OWN SURFACE — the lamp falling on it, not a flat film.
##
## MEASURED, which is the only reason this class exists. The shipping dossier's
## fill read 0.055 relative luminance against painted ground at 0.046-0.068: a
## WCAG-style ratio of 1.12:1, i.e. THE PANEL WAS THE SAME VALUE AS THE ART
## BEHIND IT and existed only as a gilt outline drawn round nothing. The house
## value ladder recorded on the starting-bonus table (sky 0.06 -> table
## 0.13-0.20 -> paper 0.71) had no middle rung here at all, which is fault (2)
## of reference_dead_space_vs_negative_space: a flat surface with no depth cue
## reads as empty however much is written on it.
##
## Drawn on the KIT'S OWN OCTAGON rather than on a rect. A rectangular grade
## inside a chamfered plate puts a square corner outside the cut one — the same
## two-silhouettes-9px-apart fault the writ tiles paid for.
##
## The lamp is LayerStyle's, so this plate is lit by the same sun as the wax
## seals, the molding round it and the two channels cut into it. Two lit objects
## side by side under different suns is the most reliable way to make a UI look
## assembled rather than designed.
##
## THE COLOUR IS A CONST AND ALL THREE PAINTERS READ IT. The plate, the road cut
## into it and the vigour band cut into it all shade RELATIVE to this surface, so
## a second spelling of it would light two channels for a plate that is no longer
## there — the duplicate-magnitude pathology this codebase has paid for twice
## (NetPlayerState restating relic values; SkirmishBot's own copy of BoardEval).
const DOSSIER_PLATE := Color(0.185, 0.146, 0.110)

class DossierPlate extends Control:
	var plate := DOSSIER_PLATE
	var chamfer := 16.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	## Steps in the directional ramp. Enough that the banding is under a pixel
	## across a 388px plate; they are half-plane intersections, drawn once.
	const GRADE_BANDS := 14

	## The part of `poly` lying beyond `origin` in direction `dir` — the
	## half-plane clip `LayerStyle.shine` uses, pulled out because the ramp needs
	## it fourteen times in each direction.
	##
	## Clipping to the plate's OWN path rather than drawing a rect is what keeps
	## the grade inside the chamfer; a rectangular ramp inside a cut plate puts a
	## square corner outside the cut one.
	static func _beyond(poly: PackedVector2Array, origin: Vector2, dir: Vector2,
			reach: float) -> PackedVector2Array:
		var t := dir.orthogonal() * reach
		var quad := PackedVector2Array([
			origin + t, origin - t,
			origin - t + dir * reach, origin + t + dir * reach])
		var res := Geometry2D.intersect_polygons(poly, quad)
		return res[0] if not res.is_empty() else PackedVector2Array()

	func _draw() -> void:
		if size.x < 40.0 or size.y < 40.0:
			return
		var poly: PackedVector2Array = PlateFrame.path_at(
			Rect2(Vector2.ZERO, size), 0.0, chamfer, 0.0, 0)
		if poly.size() < 3:
			return
		draw_colored_polygon(poly, plate)

		# THE LAMP, AND IT IS NOT `fill_graded`. That helper ramps by SHRINKING
		# the shape, so its bands hug the outline — which is a vignette, correct
		# for a 40px mark and wrong for a 388px plate. MEASURED on the first
		# render: a vertical scanline down the middle read 0.118 for sixty
		# consecutive rows, i.e. dead flat, because every band had already been
		# eaten by the edge long before it reached the face.
		#
		# A directional ramp is what a lamp actually does, so the bands are
		# half-planes pushed across the plate along the kit's light vector
		# (top-left — Sun & Perona, Nature Neuroscience 1, 1998, measured the
		# human light-from-above prior as above and shifted LEFT, which is why
		# LayerStyle pins the azimuth there and every lit object in this game
		# shares it).
		var lv: Vector2 = LayerStyle.light_vec()
		var cen := size * 0.5
		var reach := size.length() * 0.5
		var warm := Color(1.0, 0.86, 0.60)
		for i in range(GRADE_BANDS):
			var d := reach * 0.95 * (float(i) / float(GRADE_BANDS - 1))
			var toward := _beyond(poly, cen + lv * d, lv, reach * 2.5)
			if not toward.is_empty():
				draw_colored_polygon(toward,
					Color(warm.r, warm.g, warm.b, 0.018))
			var away := _beyond(poly, cen - lv * d, -lv, reach * 2.5)
			if not away.is_empty():
				draw_colored_polygon(away, Color(0.0, 0.0, 0.0, 0.024))

		# The wall, last: a plate set inside a molding is slightly recessed, and
		# the rim shadow is what says so. Photoshop's order — an inner shadow
		# under the fill is invisible.
		LayerStyle.inner_shadow(self, poly, 11.0, 0.32, 3)


## THE CURRENT RUN PLATE — "where was I?", answered as a position and not as a
## table of coordinates (rebuilt 2026-09-18).
##
## WHAT WAS WRONG, MEASURED ON THE RENDER rather than judged by eye:
##
##   * THE PANEL WAS A FILM. Fill 0.055 against ground 0.046-0.068 = 1.12:1.
##     See `DossierPlate`.
##   * THE FRAME WAS A FLAT STROKE. Walking inward from the edge, the top run
##     and the bottom run read 0.359 and 0.367 at depth 0 — a difference of
##     0.008. A molding's two opposite runs present opposite shoulders to one
##     lamp and cannot match like that; `PlateFrame` scores 0.33 on the same
##     oracle. One colour all the way round is the flat-primitive defect this
##     project has now named in a lightning bolt, a picture frame and a ring
##     stack, wearing a panel border's hat.
##   * THE INK WAS SPENT ON CHROME. Border and corner tacks 20.8% of the
##     panel's ink, the two ornament rules another 14.5% — 35.3% chrome against
##     7.3% for the four figures a returning player opens the game to read.
##     That is Tufte's data-ink ratio inverted about five to one.
##   * THE DOTTED LEADERS SOLVED A PROBLEM THAT DID NOT EXIST. A leader carries
##     the eye across a long gap in a wide table. Here it ran ~250px to reach a
##     ONE-CHARACTER value, four times, and it is the most office-document
##     device in typography — four of the five horizontal elements on the plate.
##   * EVERY FIGURE WAS TEXT, AND THREE OF THE FOUR HAVE KNOWN EXTENTS.
##     Cleveland & McGill (JASA 79(387), 1984) ranked the elementary perceptual
##     tasks by decoding accuracy and put POSITION ALONG A COMMON SCALE first;
##     reading a numeral is not on the list at all, being symbolic rather than
##     perceptual. So "ACT 1 / PROVINCE 1 / HEALTH 30 / 30" could only be read,
##     never glanced at — and then the reader had to do the arithmetic that
##     turns two of those into "how far through am I".
##
## WHAT IT IS NOW. Act and province are ONE POSITION stated in two units, so
## they became one object: `RunRoad`, the campaign road with the army standard
## planted on it. Health keeps its numeral and gains the length that makes it
## glanceable (`VigourBand`). Gold stays a bare numeral BECAUSE IT HAS NO MAX —
## there is no scale to be positioned on, and inventing one would be a lie about
## the data. The footer stops instructing (the CONTINUE button is 600px to the
## left and already carries its own preview line) and starts carrying the one
## fact only this panel can give: WHEN the run was saved.
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
	# ONE SOURCE FOR THE WIDTH. The panel's box, its padding and the divider
	# rules inside it were three independent numbers (388 / 22 / 340) that had
	# already drifted: the rules were 4px short of the content box, so both of
	# them stopped just before the right-hand edge everything else lined up on.
	const DOSSIER_W := 388.0
	const DOSSIER_PAD := 22.0
	const DOSSIER_INNER := DOSSIER_W - DOSSIER_PAD * 2.0
	panel.offset_left = -(112.0 + DOSSIER_W)
	panel.offset_right = -112.0
	panel.offset_top = 170.0
	# Height comes from the content. It used to be pinned to 350px with an
	# EXPAND_FILL spacer inside, so a two-line dossier printed its footer at
	# the bottom of a mostly-empty box — a hole in the middle of the title
	# screen, parked over the best of the painted art.
	panel.offset_bottom = 170.0
	# THE STYLEBOX NOW OWNS ONLY THE SHADOW AND THE MARGIN. Its fill is handed to
	# `DossierPlate` (which can grade it) and its rule to `PlateFrame` (which can
	# light it); a border colour at zero alpha keeps the 1px content margin the
	# layout was measured against without drawing the stroke that replaced.
	var st := GameTheme.make_panel_style(
		Color(0.0, 0.0, 0.0, 0.30),
		Color(0.70, 0.58, 0.35, 0.0),
		1, 6, true)
	# 3px all round rather than the old 22: the padding moved INSIDE, to a
	# MarginContainer, so the plate painter and the molding can both reach the
	# panel's own edge. A PanelContainer lays every child out to the content
	# rect, so anything left outside these margins simply is not drawn there.
	st.set_content_margin_all(3.0)
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)

	# Child order IS the paint order in a PanelContainer: surface, then content,
	# then the frame over both.
	panel.add_child(DossierPlate.new())

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, int(DOSSIER_PAD) - 3)
	pad.add_theme_constant_override("margin_top", 17)
	pad.add_theme_constant_override("margin_bottom", 17)
	panel.add_child(pad)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(root)

	var s := _slot_summary(_most_recent_slot()) if has_any_save else {}

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header.add_child(_dossier_icon("res://assets/icons/game-icons/flying-flag.svg",
		30.0, GILT_BRIGHT))
	var hstack := VBoxContainer.new()
	hstack.add_theme_constant_override("separation", 0)
	header.add_child(hstack)
	# "GETTING STARTED", not "START HERE" (2026-09-10). START HERE is already the
	# recommended-hero badge on the run-setup roster, so the same two words named
	# two different things one screen apart — the exact one-term-two-concepts fault
	# COPY_STYLE §12 was written against. The badge keeps the phrase (it IS a
	# "start here" pointer at one row among five); this is a panel heading and gets
	# a heading's name.
	var title_text := "CURRENT RUN" if has_any_save else "GETTING STARTED"
	var title := _make_display_label(title_text, 26, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hstack.add_child(title)
	# THE SUBTITLE NAMES THE RUN NOW, instead of restating the panel's own
	# heading. "saved progress" under "CURRENT RUN" is the caption saying what
	# the title just said; which hero and which ascension is the fact that tells
	# a returning player whether this is the run they remember, and nothing else
	# on the screen carried it.
	var sub := _make_caption_label(
		_dossier_run_name(s) if has_any_save else "start a new run",
		15, Color(0.82, 0.74, 0.58))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hstack.add_child(sub)

	# ONE rule, not two. The second one fenced off a footer that is now a single
	# caption line, and a rule above and below a three-item list is furniture
	# bracketing furniture.
	root.add_child(_make_ornament_row(DOSSIER_INNER, true))

	if has_any_save:
		var road := RunRoad.new()
		# 64: the 15px channel, the standard standing 19px proud of it, and a
		# 15px caption row under it — the caption floor drives this, not taste.
		road.custom_minimum_size = Vector2(0, 64)
		road.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		road.plate = DOSSIER_PLATE
		road.cap_font = GameTheme.font_body
		road.configure(int(s.get("act", 1)), int(s.get("floor", 0)),
			CampaignMapGenerator.BOSS_ROW, 3)
		root.add_child(road)

		var band := VigourBand.new()
		band.plate = DOSSIER_PLATE
		band.configure(int(s.get("hp", 0)), int(s.get("max_hp", 30)))
		_dossier_figure(root, "HEALTH", "%d / %d" % [
			int(s.get("hp", 0)), int(s.get("max_hp", 30))],
			Color(0.95, 0.72, 0.62), band)
		_dossier_figure(root, "PURSE", "%dg" % int(s.get("gold", 0)),
			Color(0.95, 0.80, 0.46), null)
	else:
		var pitch := _make_display_label(
			"Choose a hero, build a deck, and fight across three acts.",
			16, IVORY)
		pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		root.add_child(pitch)

	var foot_text := _dossier_saved_when(s) if has_any_save \
		else "Press New Run to begin."
	var foot := _make_caption_label(foot_text, 15, Color(0.70, 0.64, 0.53))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(foot)

	# The molding, LAST so it sits over the plate and the content both.
	# `wobble` 0 and the shimmer instead: a 388px run that meanders reads as sag
	# on an object the eye takes to be milled (the hero plate measured 6px of it
	# before that swap), while the shimmer perturbs the LAMP and keeps the
	# beaten-metal unevenness the wobble was bought for.
	PlateFrame.over(panel, Color(0.72, 0.60, 0.36), {
		"rule_w": 6.0, "chamfer": 16.0, "rebate": 3.0,
		"drop": 1.6, "wobble": 0.0, "shimmer": 0.40})


## "The Raider  ·  Ascension 2" — which run CONTINUE would resume.
func _dossier_run_name(s: Dictionary) -> String:
	var hid := String(s.get("hero", ""))
	var name := "Unknown company"
	if hid != "":
		var hero: Dictionary = HeroDB.get_hero(hid)
		if not hero.is_empty():
			name = String(hero.get("name", hid))
			# FOUR OF THE FIVE HEROES ARE BARE NOUNS ("Raider", "Stalwart") and
			# the fifth already carries its article ("The Kindler"), so an
			# unconditional prefix printed "The The Kindler". Caught by the
			# multi-state shot and by nothing else — every earlier render of this
			# panel used whichever hero happened to be in the save on disk.
			if not name.begins_with("The "):
				name = "The " + name
	if bool(s.get("is_daily_run", false)):
		name += "  ·  Daily March"
	var asc := int(s.get("ascension", 0))
	if asc > 0:
		name += "  ·  Ascension %d" % asc
	return name


## THE ONE FACT ONLY THIS PANEL CAN GIVE. Act, province, health and gold are all
## restated elsewhere on the screen or one click away; when the run was last put
## down is not, and it is what actually answers "is this the run I remember?".
func _dossier_saved_when(s: Dictionary) -> String:
	var t := int(s.get("saved_at", 0))
	if t <= 0:
		return "Saved progress."
	var days := int(floor((Time.get_unix_time_from_system() - float(t)) / 86400.0))
	if days <= 0:
		return "Set down today."
	if days == 1:
		return "Set down yesterday."
	if days < 30:
		return "Set down %d days ago." % days
	var months := int(round(float(days) / 30.0))
	if months < 12:
		return "Set down %d month%s ago." % [months, "" if months == 1 else "s"]
	return "Set down a long while ago."


## One figure on the plate: caption, an optional TRACK carrying the quantity, and
## the numeral.
##
## NO DOTTED LEADER, and its absence is the point rather than a saving. A leader
## is a connectedness cue for a long traverse in a wide table; over ~250px to
## reach a one-character value it is pure non-data ink, and four of them stacked
## read as an invoice. What groups a caption with its own value here is
## PROXIMITY and shared alignment — Gestalt grouping that costs no ink at all
## (Palmer, Cognitive Psychology 24(3), 1992, on common region and its
## relatives) — plus, where there is a track, the track itself.
##
## The numeral holds a fixed width so the figures right-align into a column
## without a container per row: a ragged right edge on a four-line block is the
## thing the alignment gate (C30) exists to catch.
func _dossier_figure(parent: VBoxContainer, caption: String, value: String,
		accent: Color, track: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _make_caption_label(caption, 15, Color(0.76, 0.68, 0.54))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cap.custom_minimum_size = Vector2(66, 0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	if track != null:
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		track.custom_minimum_size = Vector2(0, 22)
		row.add_child(track)
	else:
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
	var val := _make_display_label(value, 19, accent)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(78, 0)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val)
	parent.add_child(row)


func _dossier_icon(path: String, sz: float, tint: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path) as Texture2D
	icon.custom_minimum_size = Vector2(sz, sz)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon



# ---------------------------------------------------------------------------
# INTERACTIONS
# ---------------------------------------------------------------------------

func _refresh_slot_summary_cache() -> void:
	_slot_summary_cache.clear()
	for slot in range(RunState.SAVE_SLOTS):
		_slot_summary_cache.append(RunState.get_slot_summary(slot))


func _slot_summary(slot: int) -> Dictionary:
	if slot >= 0 and slot < _slot_summary_cache.size():
		return _slot_summary_cache[slot]
	# Defensive fallback for helper calls made before the first menu build.
	return RunState.get_slot_summary(slot)


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
		var s := _slot_summary(i)
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


## THE EXIT BUTTON STAYS LIVE THROUGH ITS OWN WIPE.
## fade_out_then_change_scene parents its ink overlay to the TREE ROOT (never to
## the outgoing scene) and only calls change_scene_to_file when the 0.34s tween
## lands — so nothing under the pointer is disabled for the whole transition. A
## second click on SKIRMISH / COLLECTION / credits / a save slot therefore queued
## a SECOND transition, and the scene the first one had just loaded was torn down
## and rebuilt a third of a second later: the lobby dropped a connection attempt
## already in flight, the Collection threw away a gallery build mid-bake, and the
## menu's own music restarted. Every one of these paths ends in a scene change,
## so the latch is one-way by construction; the only caller that can decline to
## leave (_load_slot_into_game, on an unreadable save) hands it back itself.
func _leave_for(scene_path: String, duration: float = 0.34) -> void:
	if _scene_exit_locked:
		return
	_scene_exit_locked = true
	GameTheme.fade_out_then_change_scene(self, scene_path, duration)


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
	# Claim the exit BEFORE the load: a double-click on a slot row used to run
	# load_run twice and queue two transitions, the second re-loading the room the
	# first had already entered.
	if _scene_exit_locked:
		return
	_scene_exit_locked = true
	if not RunState.load_run(slot):
		# Keep corrupt, incompatible, or temporarily unreadable files recoverable.
		# The load screen labels the slot and leaves deletion to an explicit X.
		_scene_exit_locked = false
		_show_load_screen(false)
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
		"treasure", "reliquary", "arsenal": target = TREASURE_SCENE
		"recruit": target = RECRUIT_SCENE
		"wayside": target = WAYSIDE_SCENE
	GameTheme.fade_out_then_change_scene(self, target, 0.45)


func _begin_new_in_slot(slot: int) -> void:
	# Claims `slot` for the upcoming run. clear_save handles the "this slot
	# already had a save" case (callers in overwrite mode have already shown
	# the slot summary, so an extra confirmation here would just be friction).
	RunState.clear_save(slot)
	RunState.active_slot = slot
	if MetaState.total_runs <= 0:
		_show_quick_march()
	else:
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
	# The writ pickers hide this column (they lay themselves out full-screen over
	# the menu background). Every sub-screen comes through here, so unhiding it
	# here is what makes that safe rather than a one-way trip.
	menu.visible = true
	_set_subscreen_scrim(true)
	# ── THE RECT FOLLOWS THE CANVAS (2026-09-14, CLASS C32) ──
	#
	# Every size handed to this function was authored against the 1600×900 design
	# canvas. UI Scale DIVIDES the logical canvas — at 60% the UI lays itself out
	# on 2667×1500 — so a fixed offset pair made every subscreen a shrinking
	# island: `_probe_uiscale` measured run setup covering 98%×93% of the canvas
	# at 100% and **59%×56% at 60%**, while every other shell screen held 99% at
	# all three. The player who picks 60% is asking to fit MORE on screen and was
	# getting the same panel with a wider margin of background around it.
	#
	# Scaling by canvas/design keeps the FRACTION each constant was chosen for,
	# and is exactly a no-op at 100%.
	#
	# READ BEFORE "FIXING" THIS BACK: ProjectSettings is used here as the
	# AUTHORING REFERENCE — the static canvas the callers' numbers were written
	# against — which is the one honest use of it. The 2026-09-03 decorative-frame
	# bug was the opposite mistake: reading ProjectSettings as if it were the
	# RUNTIME canvas. Static reference, live target; never the other way round.
	var canvas: Vector2 = get_viewport_rect().size
	var design := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	if design.x > 0.0 and design.y > 0.0 and canvas.x > 0.0 and canvas.y > 0.0:
		width *= canvas.x / design.x
		height *= canvas.y / design.y
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 0.5
	menu.anchor_bottom = 0.5
	menu.offset_left = -width / 2.0
	menu.offset_right = width / 2.0
	menu.offset_top = -height / 2.0
	menu.offset_bottom = height / 2.0


## The menu's legibility scrim is built for the MAIN menu: a left-edge gradient
## that seats the column and is clear by mid-screen, so the painted hero on the
## centre-right stays unobstructed. Every sub-screen then re-anchors that column
## to the MIDDLE of the canvas — straight over the brightest, busiest part of the
## fire, with nothing but its own panel fills between the text and the flames.
## THE TERMS was the proof: the four tiles are one row, and the leftmost sat on
## warm-black while the rightmost (THE PACT, the one tile that prices itself in
## max HP) was read against open flame, so the same 16px ink was legible at one
## end of the row and washed out at the other.
##
## So a centred screen gets a centred scrim: full-rect and warm-black. It is the
## same node, re-textured — the main menu rebuilds it from scratch in
## _rebuild_menu, so this only flips one way.
##
## ── 2026-08-05: THE GRADIENT RAN THE WRONG WAY, AND ONLY MEASURING SHOWED IT ──
## It was 0.56 at the top rising to 0.78 at the bottom, on the stated reasoning
## that the bottom is "where the fire is". Sampled off the real render
## (`_runstart_menu.png`, whose right half is unscrimmed art), the painting's
## luminance is:
##
##     upper sky      p90 0.047      <- nearly black already
##     fire wall      p90 0.203  max 0.433   <- y 450-800, the MIDDLE
##     lower meadow   p90 0.066      <- nearly black already
##
## The bright band is the middle, not the bottom. So the old ramp put its
## HEAVIEST wash (0.78) over some of the darkest art in the frame and its
## LIGHTEST (0.56) over the darkest — spending the painting everywhere except
## where it needed spending, and leaving the fire wall on ~0.68.
##
## Weighted to the middle instead. Worst-case ivory contrast (against the fire's
## MAX pixel, not its median) goes from 4.6:1 to 5.2:1 — i.e. this is a
## legibility IMPROVEMENT, not a trade — while the top and bottom of the frame
## come back at 10:1 to spare. Numbers for the record:
##
##     band        old a   old contrast     new a   new contrast
##     sky          0.56       12.6:1        0.42       10.8:1
##     fire wall    0.68        4.6:1        0.74        5.2:1
##     meadow       0.78       12.9:1        0.52       10.4:1
##
## If you change these, re-sample the art — do not eyeball it. The whole reason
## the ramp was backwards is that the fire LOOKS brightest at the bottom of the
## composition and measures brightest in the middle.
func _set_subscreen_scrim(on: bool) -> void:
	var scrim := get_node_or_null("MenuScrim") as TextureRect
	if scrim == null:
		return
	var grad := Gradient.new()
	var gtex := GradientTexture2D.new()
	if on:
		grad.offsets = PackedFloat32Array([0.0, 0.30, 0.58, 1.0])
		grad.colors = PackedColorArray([
			Color(0.03, 0.015, 0.0, 0.42),
			Color(0.03, 0.015, 0.0, 0.62),
			Color(0.02, 0.010, 0.0, 0.74),   # the fire wall — the real bright band
			Color(0.02, 0.008, 0.0, 0.52),
		])
		gtex.fill_from = Vector2(0, 0)
		gtex.fill_to = Vector2(0, 1)
		gtex.width = 8
		gtex.height = 256
	else:
		grad.offsets = PackedFloat32Array([0.0, 0.42, 0.70])
		grad.colors = PackedColorArray([
			Color(0.03, 0.015, 0.0, 0.66),
			Color(0.03, 0.015, 0.0, 0.44),
			Color(0.0, 0.0, 0.0, 0.0),
		])
		gtex.fill_from = Vector2(0, 0)
		gtex.fill_to = Vector2(1, 0)
		gtex.width = 256
		gtex.height = 8
	gtex.gradient = grad
	scrim.texture = gtex


## Subscreens reuse the same live Menu VBox. Detach the outgoing composition
## before scheduling its free so old and new rows can never share a layout
## frame, steal a fixed node name, or add dead delay to the incoming reveal.
func _clear_menu_column_now(menu: Node) -> void:
	if menu == null or not is_instance_valid(menu):
		return
	for child in menu.get_children():
		menu.remove_child(child)
		child.queue_free()


func _show_load_screen(overwrite_mode: bool) -> void:
	_set_subscreen_motion_obscured(true)
	# Standalone screen showing all 3 slots with full continue/delete (normal
	# mode) or "begin new run here" (overwrite mode) actions. Replaces the
	# main menu column in place so the background atmosphere persists.
	_remove_command_dossier()
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_clear_menu_column_now(menu)
	# +52 (the 44px delete gutter plus the row's 8px separation) so that the
	# gutter now reserved on BOTH sides of every slot row is paid for by the
	# column rather than out of the plates — see _make_slot_row's lead_gap.
	_center_menu_for_subscreen(672.0)

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

	# BACK sat out-dented under the slot list: `_make_menu_button` puts a 28px
	# flame slot ahead of every label, so the word started 40px left of the
	# plates it belonged under while the row itself began at their left edge.
	# Same structural fault, same fix, as _build_muster_nav's BACK — drop the
	# flame and keep the lead, so the B lands on the list's own column.
	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 17, 44, false)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(_rebuild_menu)
	_set_shell_cue(back, "back")
	# ON THE LIST'S RAIL, WHICH THE SLOT ROWS' NEW LEAD GUTTER MOVED. The plates
	# now start 52px into the column, so a BACK flush to the column would sit
	# out-dented from the very list it belongs under — the same defect the note
	# above describes, reintroduced from the other side. It rides a matching
	# gutter instead of a hardcoded number, so the two cannot drift apart.
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 8)
	var back_gap := Control.new()
	back_gap.custom_minimum_size = Vector2(44, 0)
	back_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_row.add_child(back_gap)
	back_row.add_child(back)
	menu.add_child(back_row)
	_animate_subscreen_reveal(menu)


## `at_step` lets a caller land the player deeper into the flow with everything
## behind them already restored — MARCH AGAIN opens on THE TERMS. It must still
## come through HERE rather than calling _show_muster_step directly, because this
## is the only place that rolls a fresh seed and deals the slate.
## A new profile makes one meaningful choice before play: who leads.
## three-step Muster remains one click away, but its banner, term, seed and
## difficulty controls no longer stand between a first-time player and combat.
func _show_quick_march() -> void:
	_set_subscreen_motion_obscured(true)
	_remove_command_dossier()
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_clear_menu_column_now(menu)
	_hide_deck_preview()
	_hide_deck_inspector()
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_writ_buttons.clear()
	_quick_march_active = true
	_bonus_screen_open = false
	_hide_run_options()
	_muster_step = 1
	_daily_pick = false
	_daily_btn = null
	_seed_edit = null
	_asc_label = null
	_asc_rules_label = null
	_run_commit_locked = false
	_picker_commit_locked = false
	_writ_resolution_rng = null
	_selected_ascension = 0
	_muster_alt_relic = false
	_muster_alt_deck = false
	_muster_random_seed = randi()
	if _muster_random_seed == 0:
		_muster_random_seed = 1
	_muster_seed_text = ""
	_selected_hero = HeroDB.HERO_ORDER[0]
	var first_term := WritDB.get_writ("campaign_chest").duplicate(true)
	_muster_writ_slate = [first_term]
	_selected_writ_id = "campaign_chest"

	_quick_march_stage = 1
	_show_quick_hero_stage()


## Quick March step 1 has one job: choose the person whose play pattern sounds
## appealing. Cards, relics, campaign rules and the commit button live on the
## next screen, so the roster is no longer competing with its own consequences.
func _show_quick_hero_stage() -> void:
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_quick_march_active = true
	_quick_march_stage = 1
	_clear_menu_column_now(menu)
	_hide_deck_preview()
	_hide_deck_inspector()
	_hero_cards.clear()
	_hero_portraits.clear()
	# 700, not 790. The playstyle capsules used to spend ~210px of the right pane
	# saying nine words (see _make_trait_chip); the chips that replaced them spend
	# 36, and handing the difference back to the screen as a bottom margin left
	# the identity pane a third empty under its own text. The height now measures
	# the roster, which is what actually sets it: five host rows plus the pane's
	# heading and rule.
	_center_menu_for_subscreen(1500.0, 700.0)
	menu.add_theme_constant_override("separation", 10)
	var title := _make_display_label("CHOOSE YOUR HERO", 32, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	var intro := _make_display_label(
		"Pick the style you want to learn first. You will review the deck before anything is committed.",
		17, IVORY)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(intro)

	var main_row := HBoxContainer.new()
	main_row.custom_minimum_size = Vector2(0, 470)
	main_row.add_theme_constant_override("separation", 18)
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(main_row)
	var host := _make_muster_section(main_row, "THE FIVE HEROES", 430.0)
	host.add_theme_constant_override("separation", 4)
	for hid in HeroDB.HERO_ORDER:
		var row := _make_muster_host_row(hid)
		host.add_child(row)
		GameTheme.hover_lift(row, 1.012)
	var identity := _make_muster_section(main_row, "HOW THIS HERO FIGHTS", 820.0, true)
	_hero_detail = VBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 10)
	_hero_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Vertical too, on THIS screen only: the pane's height is set by the roster
	# next to it, and without the flag the detail stack keeps its minimum and
	# leaves the surplus as a hole under the portrait. With it, the portrait (the
	# only child that asked to expand) takes the difference.
	_hero_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	identity.add_child(_hero_detail)
	var hero := _selected_hero if HeroDB.has_hero(_selected_hero) else HeroDB.HERO_ORDER[0]
	_selected_hero = ""
	_focus_hero(String(hero), true)
	var hero_focus = _hero_cards.get(String(hero))
	if hero_focus != null and is_instance_valid(hero_focus):
		hero_focus.call_deferred("grab_focus")

	_muster_slack(menu)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	menu.add_child(actions)
	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 17, 48, false)
	back.custom_minimum_size = Vector2(180, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_abandon_muster)
	_set_shell_cue(back, "back")
	actions.add_child(back)
	# This screen builds its own nav rather than calling _build_muster_nav, so it
	# did not inherit the 2026-08-05 primary treatment and SEE YOUR COMPANY was
	# still the same ivory word as the BACK beside it — on the FIRST screen a new
	# profile ever reaches. Same helper, same grammar as every muster step.
	var lead := Control.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(lead)
	var next := _make_primary_action("SEE YOUR DECK", 48)
	next.custom_minimum_size = Vector2(NAV_PRIMARY_W, 48)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_show_quick_company)
	actions.add_child(next)
	var trail := Control.new()
	trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(trail)
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(180, 0)
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(balance)
	_animate_subscreen_reveal(menu)


## Quick March step 2 shows the actual package the selected hero will carry.
## This is the first place the player sees cards, the signature and the final
## commit, because all three answer the same question: "What am I taking?"
func _show_quick_company() -> void:
	var menu := get_node_or_null("Menu")
	if menu == null or not HeroDB.has_hero(_selected_hero):
		return
	_quick_march_active = true
	_quick_march_stage = 2
	_clear_menu_column_now(menu)
	_hide_deck_preview()
	_hide_deck_inspector()
	_hero_cards.clear()
	_hero_portraits.clear()
	# 672, not 720 — and the number is measured, not chosen. The frame carries
	# SIZE_EXPAND_FILL, so it swallows every pixel the rect has spare, and a
	# geometry dump of this screen read: rect 720, frame height 563 against a
	# content minimum of 483. Eighty pixels of nothing INSIDE a bordered pane,
	# all of it pooled below the signature's last line, so the pane's bottom rule
	# printed 80px under the text it was supposed to be enclosing.
	#
	# The stack measures 157 (title 45 + nav 56 + promise 26 + three 10px gaps)
	# plus the frame's 483 = 640. 672 leaves 32, and one wrapped relic rule (+26)
	# still fits without pushing the nav row down.
	_center_menu_for_subscreen(1380.0, 672.0)
	menu.add_theme_constant_override("separation", 10)
	var hero := HeroDB.get_hero(_selected_hero)
	var title := _make_display_label(
		"%s'S STARTING DECK" % String(hero.get("name", _selected_hero)).to_upper(),
		32, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	var company := _make_muster_section(menu, "WHAT YOU START WITH", 1240.0, true)
	_hero_detail = VBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 8)
	_hero_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# NOT vertical, and the attempt is worth recording: handing this stack the
	# frame's surplus does not spread it around the content. BoxContainer splits
	# slack proportionally and then DROPS any expand child whose share lands under
	# its own minimum — the card group's is 216 against the signature row's 81, so
	# it drops out every time and the whole surplus goes to the signature row
	# anyway. Same pixels, same hole, one more flag. The rect above is the fix.
	company.add_child(_hero_detail)
	_build_quick_march_roll(_selected_hero)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	menu.add_child(actions)
	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 17, 48)
	back.custom_minimum_size = Vector2(180, 48)
	back.pressed.connect(_show_quick_hero_stage)
	actions.add_child(back)
	var customize := _make_menu_button(
		"FULL SETUP", Color(0.25, 0.19, 0.15), 17, 48)
	customize.custom_minimum_size = Vector2(240, 48)
	customize.tooltip_text = "Choose the hero, banner, bonus, difficulty, Daily Run or seed."
	customize.pressed.connect(_customize_quick_march)
	actions.add_child(customize)
	var take := _make_begin_button()
	take.name = "QuickMarchTakeField"
	take.custom_minimum_size = Vector2(470, 56)
	take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(take)
	var take_trail := Control.new()
	take_trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(take_trail)
	take.call_deferred("grab_focus")
	var promise := _make_display_label(
		WritDB.muster_copy("subtitle"), 15, Color(0.80, 0.75, 0.65))
	promise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(promise)
	_animate_subscreen_reveal(menu)


func _quick_hero_traits(hid: String) -> Array[String]:
	match hid:
		"raider":
			return ["Move first", "Attack open lanes", "Relocate allies"]
		"stalwart":
			return ["Build a durable line", "Protect the back row", "Win long clashes"]
		"acolyte":
			return ["Use deaths as fuel", "Raise the fallen", "Trade bodies for value"]
		"pyromancer":
			return ["Build Doom", "Burn several enemies", "Finish explosively"]
		"kindler":
			return ["Grow through sacrifice", "Spread fire", "Turn losses into power"]
		_:
			# The fallback arm, for a hero HeroDB gains after this match was
			# written. "Break the hold" needed the setting to decode ("hold" is
			# the docs' word for a fight site, and no screen ever says it) —
			# COPY_STYLE §12 bans a riddle in UI chrome even in a branch nobody
			# has reached yet, because the day it renders is the day nobody is
			# looking at it.
			return ["Build a line", "Read the lanes", "Break the enemy line"]


func _build_quick_hero_identity(hid: String) -> void:
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	_clear_muster_container_now(_hero_detail)
	var hero := HeroDB.get_hero(hid)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_detail.add_child(top)
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	var portrait: Control
	if ResourceLoader.exists(portrait_path):
		var tex := TextureRect.new()
		tex.texture = load(portrait_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait = tex
	else:
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
			Color(0.10, 0.08, 0.09, 0.95), _faction_accent(hid), 2, 4, false))
		var monogram := _make_display_label(
			String(hero.get("name", hid)).left(1), 54, GILT_BRIGHT)
		monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate.add_child(monogram)
		portrait = plate
	# GIVE THE HERO THE PANE (2026-08-05). This was 230 wide inside a ~1250px
	# pane — a narrow vertical strip of commissioned portrait art on the screen
	# whose entire job is to sell the run, with the ~950px beside it holding
	# roughly 280px of copy and a large dark void beneath. Measured on the render
	# it was the single biggest empty region in the shell.
	#
	# 400 is a third of the pane. Every surveyed game makes the chosen character
	# the screen (Hades gives Zagreus the full right half; StS runs a full-bleed
	# Ironclad), and the width costs nothing that was being used: the copy column
	# gets narrower and therefore TALLER, which closes the void from the other
	# side at the same time.
	portrait.custom_minimum_size = Vector2(400, 292)
	# The pane's height is set by the five-name roster beside it, not by this
	# column, so there is always more of it than the copy needs. Spend it on the
	# painting rather than on a hole: KEEP_ASPECT_COVERED means a taller frame
	# just shows more of the same portrait.
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The painting is the star of this screen, so it stands on the page like one:
	# a real plate with a lit fillet, the same furniture a card's art mount wears.
	#
	# THAT SENTENCE WAS ALREADY THE INTENT AND THE CODE COULD NOT DELIVER IT
	# (2026-09-17). A "lit fillet" is a molding — a solid with a cross-section,
	# lit from one side — and what was here was `make_panel_style`'s metal rule,
	# i.e. one `add_polyline` in one colour, which has no cross-section and no
	# light direction available to it at all. The comment is kept because it was
	# right; the border is handed to `PlateFrame` now, which can actually draw it.
	#
	# The PanelContainer stays: it owns the CLIP and the content margins, so the
	# layout does not move. Its own rule is zeroed rather than deleted so those
	# margins survive — a border width of 2 is still spent, it just is not drawn.
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var acc := _faction_accent(hid)
	frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
		Color(0.02, 0.015, 0.012, 0.5), Color(acc.r, acc.g, acc.b, 0.0), 2, 4, true))
	frame.clip_contents = true
	frame.add_child(portrait)
	# Shallow `drop`: the panel CLIPS, so a shadow thrown outside its rect is
	# scissored off and only the inner half would survive — which reads as a
	# smudge on one side rather than as a frame standing off the page.
	#
	# `wobble` is gone rather than tuned (2026-09-18). At 1.0 the crest of the top
	# run measured y=137..143 — six pixels of sag across a 300px run, on an object
	# the eye reads as milled. The beaten-metal unevenness it was bought for now
	# rides `shimmer`, which perturbs the lamp instead of the silhouette.
	_faction_frame(frame, hid, {
		"corner": "mitre", "rule_w": 6.0, "rebate": 3.0,
		"drop": 1.2, "shimmer": 0.40})
	portrait = frame
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(portrait)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 10)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(copy)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	copy.add_child(head)
	var name := _make_display_label(String(hero.get("name", hid)), 30,
		_faction_accent(hid))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	# (RECOMMENDED FIRST HERO used to print here, in this pane's top-right corner
	# — ~1100px from the roster, and only AFTER the hero was already focused.
	# It now rides the roster row itself as START HERE, where the advice is in
	# front of the player before the click rather than confirming one they have
	# made. Printing it in both places was just saying it twice.)
	var tagline := _make_display_label(String(hero.get("tagline", "")), 19,
		Color(0.98, 0.83, 0.58))
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(tagline)
	# DESC_DIM, not IVORY. This is the paragraph UNDER the hero's nameplate, and
	# at full ivory (luminance 0.91) it outshone the 30px name above it — the
	# largest text in the pane was also the faintest. Body ink is 0.74; the
	# accent floor is 0.80, so the heading now leads its own pane.
	var pitch := _make_display_label(String(hero.get("desc", "")), 17,
		GameTheme.DESC_DIM)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size = Vector2(0, 72)
	copy.add_child(pitch)
	copy.add_child(_make_caption_label("PLAYSTYLE", 15,
		Color(0.76, 0.69, 0.56)))
	# THREE SHORT PHRASES, NOT THREE EMPTY PANELS (2026-08-03). These were built
	# out of _make_quick_march_fact — a titled fact plate 58px tall with a 12px
	# margin and a title label — called with an EMPTY title. So each trait got a
	# full-width capsule holding a blank line and three words, and the three of
	# them spent ~210px of the pane's height saying nine words. Rendered, the
	# right-hand pane read as three unfilled fields rather than as a summary.
	#
	# They are a caption list, so they are laid out as one: a single row of tight
	# chips that measure to their own text. Same words, a fifth of the height, and
	# the pane's remaining space goes back to the portrait and the pitch.
	var traits := HBoxContainer.new()
	traits.add_theme_constant_override("separation", 22)
	traits.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	copy.add_child(traits)
	var playstyle_lines := _quick_hero_traits(hid)
	for i in range(playstyle_lines.size()):
		traits.add_child(_make_trait_chip(playstyle_lines[i], i > 0))

	# ── THE SIGNATURE, PRINTED (2026-08-05) ──
	# Below the traits this pane held ~240px of bare plate. Widening the portrait
	# closed most of the void from the left, but a hole under the copy is still a
	# hole — and the honest thing to put in it is not air but the OTHER HALF of
	# what picking a lord hands you. A hero is a deck plus a doctrine relic; this
	# screen was pitching only the deck, and the relic is what makes each of the
	# five actually feel different in the first fight.
	#
	# Step I of THE MUSTER already prints exactly this block (see
	# _build_muster_column's signature row). Printing it here means the first
	# screen a new profile meets answers "what am I taking?" one screen earlier,
	# in the same words it will be answered in later.
	var relic_id := String(hero.get("relic", ""))
	if relic_id != "":
		var relic: Dictionary = RelicDB.get_relic(relic_id)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(spacer)
		var sig_row := HBoxContainer.new()
		sig_row.add_theme_constant_override("separation", 12)
		sig_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		copy.add_child(sig_row)
		var chip := GameTheme.make_relic_chip(relic_id, 50)
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		sig_row.add_child(chip)
		var sig := VBoxContainer.new()
		sig.add_theme_constant_override("separation", 0)
		sig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sig_row.add_child(sig)
		sig.add_child(_make_caption_label("SIGNATURE RELIC", 15, Color(0.76, 0.69, 0.56)))
		sig.add_child(_make_display_label(
			String(relic.get("name", relic_id)), 19, GILT_BRIGHT))
		var relic_desc := _make_display_label(
			String(relic.get("desc", "")), 15, GameTheme.DESC_DIM)
		relic_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		relic_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sig.add_child(relic_desc)

func _customize_quick_march() -> void:
	_muster_setup_preset = {
		"hero": _selected_hero,
		"alt_relic": false,
		"alt_deck": false,
	}
	_quick_march_active = false
	_show_hero_select(1)


func _show_hero_select(at_step: int = 1) -> void:
	_set_subscreen_motion_obscured(true)
	_remove_command_dossier()
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_clear_menu_column_now(menu)
	_hide_deck_preview()
	_hide_deck_inspector()
	_quick_march_active = false
	_bonus_screen_open = false
	_hide_run_options()
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_writ_buttons.clear()
	_selected_hero = ""
	_daily_pick = false
	_daily_btn = null
	_seed_edit = null
	_asc_label = null
	_asc_rules_label = null
	_run_commit_locked = false
	_picker_commit_locked = false
	_writ_resolution_rng = null
	var preset: Dictionary = _muster_setup_preset.duplicate(true)
	_muster_setup_preset.clear()
	_muster_random_seed = randi()
	if _muster_random_seed == 0:
		_muster_random_seed = 1
	_muster_seed_text = ""

	var first_hero := String(preset.get("hero", HeroDB.HERO_ORDER[0]))
	if not HeroDB.has_hero(first_hero):
		first_hero = HeroDB.HERO_ORDER[0]
	_selected_hero = first_hero
	# Set UNCONDITIONALLY, not only when a preset restores them. These two live on
	# the object and _focus_hero is the only other writer, so an abandoned muster
	# used to leave them standing: focus a mastered lord, switch his deck to the
	# alternate, back out to the menu, start a new run — and the next lord marched
	# with HIS alternate deck without the toggle ever being pressed for him.
	_muster_alt_relic = bool(preset.get("alt_relic", false))
	_muster_alt_deck = bool(preset.get("alt_deck", false))
	_normalize_muster_doctrine(first_hero)
	# Deal the terms up front even though they are not drawn until step III:
	# _begin_run_with resolves the chosen tile out of _muster_writ_slate, and a
	# probe (or a player on a fast path) can reach the commit without the terms
	# row ever having been built.
	_refresh_muster_deals()
	_show_muster_step(at_step)


## RUN SETUP is ONE screen with ONE question on it: who leads. `step` is
## ignored and kept only so the probes and shot tools that pass one still
## resolve. Nothing here commits — START RUN hands off to the starting-bonus
## beat, which is the screen that calls _begin_run_with.
func _show_muster_step(step: int) -> void:
	_set_subscreen_motion_obscured(true)
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_muster_step = clampi(step, 1, 4)
	_bonus_screen_open = false
	# The bonus screen's table is a SIBLING of this column, so clearing the
	# column's children does not take it with us. This is the one exit that has
	# to say so out loud — see _set_bonus_table.
	_set_bonus_table(false)
	_hide_run_options()
	_hide_deck_preview()
	_cancel_muster_roll_reveal()
	_muster_roll_ready = false
	_clear_menu_column_now(menu)
	# Every per-step node reference dies with the screen. Consumers all guard
	# with is_instance_valid, but a stale entry in these maps would keep a freed
	# button alive in _focus_hero's sweep.
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_writ_buttons.clear()
	_hero_detail = null
	_muster_writ_row = null
	_muster_campaign_label = null
	_muster_gloss_label = null
	_muster_order_term_detail = null
	_asc_label = null
	_asc_rules_label = null
	_daily_btn = null
	_seed_edit = null

	# ONE RECT, AND THE CHROME IS NAILED TO IT (2026-08-03). The height used to
	# be picked per step against a CENTER-aligned column, so where the title
	# landed was a function of how tall that step's content happened to be —
	# measured, it moved 160px while you walked the flow. Fixed header, fixed
	# commit row at the foot, elastic middle: the slack goes to a `Slack` spacer
	# (see _muster_slack) rather than to the column's centring.
	#
	# 840 centred in 900 leaves a 30px margin each side. It no longer grows with
	# a disclosure, because MORE RUN OPTIONS is a dialog now rather than an
	# inline row that pushed START RUN off the bottom of the canvas.
	# THE PAGE OVERFLOWS ITS RECT, so this number is a CENTRING HINT, not a
	# clamp — and that is the fact two obvious fixes founder on. START RUN's
	# WORD was rendering 3px below the canvas; measured, the column lays out from
	# `(900 - R) / 2` downward once its content is taller than R, so SHRINKING the
	# rect moved the whole page DOWN and made the overrun worse (R=850 gave 6px,
	# R=848 gave 7px). Neither the row's minimum nor the pane's own height moves
	# it either, because the footer rides the bottom of the content stack.
	#
	# The only dial that works is CONTENT, taken off the tallest block on the page
	# (see the portrait plate). Found by _probe_textfit, which reads INK rather
	# than boxes; no other gate sees a clipped commit button.
	# 1560 x 816. WIDER than the old 1540, because the deck rail spans the page
	# and every 20px of width is 2px on each of ten cards.
	#
	# SHORTER because the foot was CLIPPING, and the reason is worth writing
	# down: `_make_begin_button` draws an ornamental plate that overhangs its own
	# 56px box, so budgeting the commit row at its box height puts the plate's
	# bottom edge on the canvas edge. The page now has slack, so the foot rides
	# the RECT's bottom at `(900 + R)/2` — which makes R the only dial that
	# moves it, and 816 leaves the plate ~10px of real margin.
	#
	# (While the page OVERFLOWS its rect this is inverted and shrinking R makes
	# the overrun worse, because the column then lays out from `(900 - R)/2`
	# downward. Check which regime you are in before turning this number.)
	#
	# 864, and BOTH regimes are live at once here, which is why this number was
	# hard to find. At the 1600x900 design canvas the page's 867px of content
	# just OVERFLOWS the rect, so the foot lays out from `(900 - R)/2` downward
	# and R has to be LARGE to pull the whole page up — 792 put the commit label
	# 21px off the bottom, 816 put it 9px off, 864 clears it. At every SMALLER UI
	# Scale the rect grows with the canvas past the content, the slack above the
	# foot takes over, and the page's ink spans the rect the way C32 requires.
	# One number, two behaviours; measure, do not reason about it.
	_center_menu_for_subscreen(MUSTER_PAGE_W, 864.0)
	menu.add_theme_constant_override("separation", 8)
	var title := _make_display_label(WritDB.muster_copy("title"), 31, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	# ONE LINE OF HEAD FURNITURE, NOT FOUR (2026-08-01, held). Every step used to
	# open on a title, a step rail, a per-step instruction and a standing promise
	# — ~170px of canvas before a single decision, and none of it the fine print
	# its sizes suggested: _make_display_label floors at GameTheme.MIN_LABEL_SIZE,
	# so a "16" instruction and a "15" promise both render at 18 and read as
	# loud as each other. The rail went with the wizard (2026-09-14) and the
	# instruction went with the terms row (2026-09-16); what those lines said is
	# said by the two section captions directly beneath them.
	_build_muster_screen(menu)
	_animate_subscreen_reveal(menu)


## RUN SETUP AS A COMPOSED PAGE, NOT THREE STACKED PANES (2026-09-17).
##
## Third pass. The first two fixed real defects — the banner came out, the bonus
## moved to its own screen, the surfaces got materials — and the owner's reading
## was still that the proportions and positioning look wrong. Measured on the
## render, they were, and the faults are compositional rather than per-element:
##
##   A DEAD QUADRANT. The dossier column ended at y~360 and nothing stood under
##   it, so the entire right third below the relic block was bare canvas — the
##   single largest empty region on the page, and the one the eye lands on last
##   and remembers.
##
##   A RAGGED DECK. Ten cards laid 6-then-3 in a middle-width grid gave the page
##   a torn bottom edge in the exact place a composition needs a line.
##
##   THREE COMPETING ALIGNMENTS IN THE FOOT. BACK flush left at the canvas edge,
##   the run controls centred in the middle of nothing, START RUN flush right and
##   clipped by the bottom of the screen. Three anchors, no relationship.
##
## The page is now built as one composition with FOUR HORIZONTAL BANDS, and
## every band spans the full width so the page has edges instead of a silhouette:
##
##   1. TITLE + RULE   the rule is what ties three columns into one page.
##   2. THE BAND       roster | portrait | dossier, all the same height by
##                     construction (the portrait sets it; see MUSTER_BAND_H).
##   3. THE DECK RAIL  ten cards in ONE row, full width. A deck is a rail, not a
##                     grid — and at ten across the tiles are 148 wide, which is
##                     larger than the 6-wide grid managed at the same height.
##   4. THE FOOT       BACK and START RUN on one line, nothing between them.
##
## THE RUN CONTROLS MOVED INTO THE DOSSIER, pinned to its bottom. That is what
## fills the dead quadrant, and it is not a dumping ground: Ascension, Daily Run
## and the seed are facts about THIS RUN, which is exactly what the column they
## now sit in is about. The column reads identity at the top, terms of service at
## the bottom, and the spacer between them is deliberate — two anchors, not a
## hole. It also takes them out of the foot, which is what leaves BACK and START
## RUN alone on a line together.
func _build_muster_screen(menu: VBoxContainer) -> void:
	# The rule under the title. Full width, because its whole job is to say that
	# the three columns beneath it are one page rather than three panels.
	menu.add_child(_make_ornament_row(MUSTER_PAGE_W - 12.0, true, false, true))

	var main_row := HBoxContainer.new()
	main_row.custom_minimum_size = Vector2(0, MUSTER_BAND_H)
	main_row.add_theme_constant_override("separation", 26)
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(main_row)

	# 340, down from 430. The roster holds a portrait, a name and a six-word
	# tagline; at 430 every row carried ~150px of empty width, and the width it
	# was hoarding is the width the lord's own plate wanted.
	var host := _make_muster_section(main_row,
		WritDB.muster_copy("host_head_text"), MUSTER_ROSTER_W)
	host.add_theme_constant_override("separation", 6)
	for hid in HeroDB.HERO_ORDER:
		var row := _make_muster_host_row(hid)
		host.add_child(row)
		GameTheme.hover_lift(row, 1.012)

	# The portrait and the dossier share one section heading, because they are
	# one thing: the lord you have chosen. _hero_detail is the HBox they live in,
	# so _build_muster_roll can rebuild both halves on a focus change.
	var column := _make_muster_section(main_row,
		WritDB.muster_copy("column_head_text"), 700.0, true)
	_hero_detail = HBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 26)
	_hero_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_hero_detail)

	# ── THE RAIL BELONGS TO THE LORD, NOT TO THE PAGE (2026-09-17) ──
	#
	# It used to be its own band across all three columns, parented to `menu`.
	# Measured consequence: the ten tiles carried 29.1% of the page's entire
	# optical weight — the single heaviest object on the screen, above even the
	# portrait — for content that is REFERENCE here and not a decision, since
	# nothing on this screen can change the opener. Worse, its caption ("YOUR
	# STARTING DECK · 10 cards · 30 max HP") sat flush LEFT under the roster,
	# roughly a thousand pixels from the lord whose deck it describes.
	#
	# That last part is the strongest effect in the literature this pass
	# surveyed. The SPATIAL CONTIGUITY principle — keep related words and
	# pictures near each other — carries g = 0.63 across 58 comparisons
	# (n = 2,426), and a full-width band under a three-column page violates it
	# about as directly as a layout can: the deck was adjacent to the roster it
	# has nothing to do with, and remote from the hero it is.
	#
	# Parented to the hero column it becomes the foot of a CHARACTER SHEET —
	# face, rules, army, in one object — which is what the genre's reference
	# points do (StS, Hades) and what `column_head_text` already claims this
	# section is. Three consequences, all of them wanted: the tiles shrink to the
	# column's width so reference stops out-weighing the decision; their ink
	# moves right, which is the direct lever on a page measured at 59.4% / 40.6%
	# left-heavy; and it lands in the empty lower half of the dossier column,
	# which was the largest dead rectangle on the page.
	#
	# It stays a SEPARATE container from _hero_detail, unchanged, because both
	# rebuild on a focus change and _focus_hero clears them independently.
	_hero_deck_rail = VBoxContainer.new()
	_hero_deck_rail.add_theme_constant_override("separation", 6)
	_hero_deck_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_hero_deck_rail)

	var hero := _selected_hero if HeroDB.has_hero(_selected_hero) \
		else HeroDB.HERO_ORDER[0]
	# _focus_hero clears the doctrine toggles, which is right when the player
	# picks a DIFFERENT lord and wrong when a rebuild merely repaints this one.
	_normalize_muster_doctrine(String(hero))
	_selected_hero = ""
	_focus_hero(String(hero), true)
	# The bonus slate is still dealt HERE even though it is shown on the next
	# screen: _begin_run_with resolves the committed term out of
	# _muster_writ_slate, and a probe (or a rematch) can reach the commit without
	# _show_starting_bonus ever having been built.
	_refresh_muster_deals()

	# ── THE SLACK IS A UI-SCALE CONTRACT, NOT PADDING (2026-09-17, CLASS C32) ──
	#
	# It was removed in this pass as dead spacing and _probe_uiscale caught the
	# consequence immediately: run setup's y coverage fell 97% -> 78% at UI Scale
	# 80% and 97% -> 59% at 60%. The mechanism is worth keeping, because it is
	# not obvious and it applies to every centred screen in this shell.
	#
	# `_center_menu_for_subscreen` scales its RECT with the live canvas (at 60%
	# the UI lays out on 2667x1500), but everything INSIDE this page is sized
	# from constants — the band, the plate, the rail's tiles. So the rect grows
	# and the content does not, and the page becomes an island in the middle of a
	# larger canvas: the exact defect C32 was written to catch, in the exact
	# screen that first triggered it.
	#
	# This spacer is what couples them. It expands to whatever the rect has
	# spare, which pushes the foot onto the rect's bottom edge, which makes the
	# page's INK span the rect at every scale. It is safe here and was not before
	# only because the page now fits: an EXPAND_FILL spacer contributes zero once
	# the content is taller than its rect, which is how it came to be read as
	# useless and deleted.
	_muster_slack(menu)
	_build_muster_footer(menu)

	var hero_focus = _hero_cards.get(String(hero))
	if hero_focus != null and is_instance_valid(hero_focus):
		hero_focus.call_deferred("grab_focus")


## BACK · RUN OPTIONS · START RUN, and nothing else. Ascension, Daily Run and
## the seed are MODIFIERS: almost every run takes none of them, so they sit
## behind one word that opens a dialog (see _show_run_options) rather than an
## inline disclosure that grew the page by 44px whenever it was open. BACK is
## the only other exit, and nothing commits here — START RUN opens the starting
## bonus, which is the beat that actually begins the run.
## Ascension · Daily · seed, ON THE PAGE (2026-09-17).
##
## These lived behind a RUN OPTIONS tab that opened a modal. That made sense while
## run setup was carrying the starting-bonus row as well and had no room — but the
## bonus moved to its own page, which left the setup screen with a whole empty
## band and its three run-shaping controls still hidden behind a click. A dialog
## you must open to see whether you are on Ascension 5 is a worse answer than a
## row that simply says so.
##
## DAILY COMES ALONG even though only ascension and the seed were asked for: the
## menu column does not carry Daily Run (see CLAUDE.md's 7-item list), so the tab
## was its ONLY door. Removing the tab without rehoming it would have deleted the
## mode rather than tidied the screen.
##
## Same node identities as the old dialog (`_asc_label`, `_asc_rules_label`,
## `_daily_btn`, `_seed_edit`) so every existing consumer — `_change_ascension`,
## `_update_asc_rules_text`, `_refresh_seed_field_state`, the debounced seed deal
## — keeps working untouched. They are still null-guarded everywhere, which is
## what lets the ascension stepper stay unbuilt below the first win.
func _build_muster_run_controls(menu: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	# LEFT, not centred (2026-09-17). These were centred while they were a band
	# of their own across the foot of the page. They sit inside the lord's
	# dossier now, under a name, a pitch and a relic rule that are all flush
	# left — a centred row in a left-aligned column reads as a different
	# element that wandered in, which is exactly how it photographed.
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 14)
	# SHRINK, not EXPAND. Inside the dossier the row is 830px wide and its three
	# controls total ~500, so EXPAND_FILL spread them across the column with
	# DAILY RUN on the left margin and the seed field against the right edge —
	# two controls that answer each other, as far apart as the page allows.
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.add_child(row)

	# THE LADDER IS NOT DRAWN UNTIL IT HAS A RUNG — unchanged from the dialog, and
	# the reason is if anything stronger inline: a permanently dead "-/+" pair sat
	# among live offers is exactly what no surveyed roguelike ships.
	if MetaState.unlocked_ascension > 0:
		var minus := _make_menu_button("-", Color(0.20, 0.16, 0.14), 17, 38)
		minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		minus.custom_minimum_size = Vector2(40, 38)
		minus.pressed.connect(_change_ascension.bind(-1))
		row.add_child(minus)
		_asc_label = _make_display_label("Ascension %d / %d" % [
			_selected_ascension, MetaState.unlocked_ascension], 17, IVORY)
		_asc_label.custom_minimum_size = Vector2(190, 38)
		_asc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_asc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(_asc_label)
		var plus := _make_menu_button("+", Color(0.20, 0.16, 0.14), 17, 38)
		plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plus.custom_minimum_size = Vector2(40, 38)
		plus.pressed.connect(_change_ascension.bind(1))
		row.add_child(plus)

	var daily_text := _daily_button_text()
	_daily_btn = _make_menu_button(daily_text, Color(0.30, 0.24, 0.34), 15, 38)
	_daily_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_daily_btn.custom_minimum_size = Vector2(
		maxf(238.0, float(daily_text.length()) * 10.0 + 24.0), 38)
	_daily_btn.tooltip_text = _daily_tooltip()
	_daily_btn.disabled = _daily_button_blocked()
	_daily_btn.pressed.connect(_on_daily_button_pressed)
	row.add_child(_daily_btn)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed (optional)"
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_edit.add_theme_font_size_override("font_size", 16)
	_seed_edit.add_theme_color_override("font_color", IVORY)
	_seed_edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.42))
	_seed_edit.custom_minimum_size = Vector2(200, 38)
	if GameTheme.font_display:
		_seed_edit.add_theme_font_override("font", GameTheme.font_display)
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.02, 0.015, 0.01, 0.85)
	well.border_color = Color(0.60, 0.51, 0.34, 0.75)
	well.set_border_width_all(1)
	well.set_corner_radius_all(3)
	well.content_margin_left = 8
	well.content_margin_right = 8
	_seed_edit.add_theme_stylebox_override("normal", well)
	var well_focus := well.duplicate() as StyleBoxFlat
	well_focus.border_color = GILT_BRIGHT
	_seed_edit.add_theme_stylebox_override("focus", well_focus)
	_seed_edit.text = _muster_seed_text
	_refresh_seed_field_state()
	_seed_edit.text_changed.connect(_on_muster_seed_changed)
	row.add_child(_seed_edit)

	# The ascension RULES line under the row it explains. It carries the
	# "Win a run to unlock Ascension levels" promise when the stepper is absent,
	# so it prints whether or not the ladder exists.
	_asc_rules_label = _make_display_label("", 15, Color(0.70, 0.64, 0.53))
	# LEFT, with the column it lives in. Centred, it hung under the middle of a
	# left-flush stack and read as a caption belonging to nothing.
	_asc_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_asc_rules_label.custom_minimum_size = Vector2(MUSTER_PROSE_W, 0)
	_asc_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(_asc_rules_label)
	_update_asc_rules_text()


## The Daily button's label, extracted so the inline row and any future caller
## cannot disagree about what today's ledger says.
func _daily_button_text() -> String:
	var today: Dictionary = MetaState.todays_daily()
	if today.is_empty():
		return "DAILY RUN — ON" if _daily_pick else "DAILY RUN — OFF"
	match String(today.get("result", "")):
		"won":
			return "DAILY RUN — WON TODAY"
		"lost":
			return "DAILY RUN — LOST TODAY"
		_:
			return "CONTINUE DAILY RUN" if _daily_resume_slot(today) >= 0 \
				else "DAILY RUN — ALREADY STARTED"


func _daily_button_blocked() -> bool:
	var today: Dictionary = MetaState.todays_daily()
	if today.is_empty():
		return false
	match String(today.get("result", "")):
		"won", "lost":
			return true
		_:
			return _daily_resume_slot(today) < 0


func _build_muster_footer(menu: VBoxContainer) -> void:
	# (`_build_muster_run_controls(menu)` stood here until 2026-09-17. Ascension,
	# Daily Run and the seed are facts about THIS RUN, so they moved into the
	# lord's dossier column where the rest of the run's facts already are —
	# which is what fills that column's dead lower half AND leaves BACK and
	# START RUN alone on one line instead of sharing the foot with a third,
	# differently-aligned row.)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(row)
	# The FRAMELESS back, matching every other shell screen (the quick march, the
	# load screen, the writ pickers all use this one). It was the boxed
	# `_make_secondary_action`, which left run setup the only screen in the shell
	# whose BACK wore a panel — and after the frameless pass it was one of the
	# last rectangles standing on the page.
	#
	# Pinned, not expanded: _make_menu_button hands every button EXPAND_FILL, and
	# an expanding BACK steals a third of the row and shoves START RUN off centre.
	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 17, 46, false)
	back.custom_minimum_size = Vector2(180, MUSTER_NAV_ROW_H)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_abandon_muster)
	row.add_child(back)
	# THE OPTIONS TAB IS GONE (2026-09-17). It existed to keep three controls off a
	# crowded page; the page is no longer crowded (the starting bonus moved to its
	# own screen), and the tab's own justification was that it had to carry an
	# ACTIVE summary so a player could see they were on Ascension 5 without
	# opening it. A row that shows the controls needs no summary of itself.
	# See _build_muster_run_controls, called above.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var take := _make_begin_button()
	take.name = "MusterTakeField"
	take.custom_minimum_size = Vector2(470, 56)
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(take)
	take.call_deferred("grab_focus")


## THE WHOLE OPENER, AS PICTURES (2026-09-14).
##
## This strip used to be seven baked Card2D faces at DECK_MINI_SCALE 0.62, and it
## was the loudest ink on the screen. Card2D holds rules text at an ABSOLUTE 18px
## floor: _fit_desc_to_box refuses to shrink a glyph and would rather clip the
## card, COPY_STYLE §11 sets that floor, and tools/_probe_text_floor.gd fails the
## build below 14. Scaling the NODE to 0.62 rendered that text at 11.2px — and no
## gate could see it, because the probe reads font-size OVERRIDES and a
## Control.scale is not one. (That blind spot is general: any scaled subtree
## defeats a size-literal check.)
##
## So the biggest element on the run-setup screen was rules text nobody could
## read — decoration wearing the costume of information. The fix is not a bigger
## strip, because seven READABLE faces do not fit in any pane this screen can
## spare. It is the right unit: a card's ART is what the eye actually recognises
## a card by, at roughly a third of the ink. Pictures instead of faces also buy
## the room to show all ELEVEN cards rather than a seven-card sample, so the
## strip now says strictly more than the thing it replaces.
##
## The rules are not gone, they are one gesture away, twice: hovering any tile
## floats the full readable card (_show_deck_preview), and VIEW FULL DECK opens
## the inspector. That is one level of progressive disclosure — the most NN/g's
## guidance allows before users start getting lost between levels.
func _make_opener_art_strip(opener: Array[String],
		strip_w: float = OPENER_STRIP_WIDTH,
		cols_n: int = OPENER_STRIP_COLUMNS) -> Control:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in opener:
		var id := String(cid)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	# FIVE ACROSS, NOT ELEVEN — and the tiles are LANDSCAPE. The first cut laid one
	# rank of portrait tiles at the card's own 3:4, which was wrong twice over:
	# card art ships 3:2 LANDSCAPE (768×512), so covering a portrait tile with it
	# crops to the middle 50% of the painting's width, and the middle of a
	# painting is very often its background. Measured on the rendered strip:
	# eleven tiles of sky, mud and foliage with not one recognisable subject in
	# them — which looks exactly like a broken image loader.
	#
	# Two ranks at the art's OWN aspect crops nothing, and the tile grows from
	# 65×87 to ~148×99, so the thing the player is being shown is the whole
	# picture rather than a core sample of it.
	#
	# 5 × 148, not 6 × 86 (2026-09-16). An opener is TEN cards now (the banner's
	# eleventh went with the banner system) and the pane inherited the width the
	# banner column used to take, so the same two ranks hold the whole deck at
	# nearly twice the size. The card art is the only thing on this screen that
	# says what the run will FEEL like; it should be the biggest thing on it.
	var grid := GridContainer.new()
	grid.columns = maxi(1, cols_n)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var cols: float = float(maxi(1, cols_n))
	var tile_w: float = (strip_w - 8.0 * (cols - 1.0)) / cols
	for id in order:
		grid.add_child(_make_opener_art_tile(String(id), int(counts[id]), tile_w))
	return grid


## One art tile. A Control with the painting inside it and the frame drawn OVER
## it: PanelContainer would inset the art by its own content margins, and
## clip_children is inert on gl_compatibility (so the art cannot be trimmed to a
## rounded plate). STRETCH_KEEP_ASPECT_COVERED does the cropping instead — it
## clips to the node's own rect by definition.
func _make_opener_art_tile(id: String, count: int, w: float) -> Control:
	var data: Dictionary = CardDB.get_card_data(id)
	# The CARD is 3:4; the PAINTING is 3:2, and it is the painting being shown.
	var h: float = w / OPENER_ART_ASPECT
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(w, h)
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var art_path := CardArtAliases.card_art_path(data)
	if art_path != "" and ResourceLoader.exists(art_path):
		# THE CLIP IS ITS OWN NODE, and it has to be. STRETCH_KEEP_ASPECT_COVERED
		# scales the painting until it COVERS the rect and lets the overflow draw
		# past the node — it does not crop by itself, it needs a scissor. Without
		# one the eleven tiles each painted a full-height column straight down the
		# page, over the signature relic and the terms row beneath them.
		#
		# It cannot be `slot.clip_contents`, because slot also carries the ×N
		# chip, which deliberately sits at the tile's own top edge and would be
		# scissored away with the overflow. So the scissor wraps the art alone.
		# (`clip_contents` is a real scissor rect and works on gl_compatibility —
		# it is CanvasItem.clip_children that is inert on this renderer.)
		var art_clip := Control.new()
		art_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(art_clip)
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.texture = load(art_path)
		# EXPAND_IGNORE_SIZE IS LOAD-BEARING. TextureRect's default expand_mode is
		# EXPAND_KEEP_SIZE, under which the node's minimum size is the TEXTURE's
		# full size — 768×512 here — so the anchors never got it down to the tile
		# and stretch_mode had nothing to do. The painting drew at 1:1 and the clip
		# above scissored a 113×75 window out of its TOP-LEFT CORNER, which is why
		# every tile read as sky or mud: it was a core sample at full resolution,
		# not a thumbnail. The art was never the problem.
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(tex)
		# A gentler burn than the portrait's: at 211px wide a strong vignette eats
		# the subject, and the job here is only to stop ten hard-edged rectangles
		# reading as a spreadsheet.
		Sheen.vignette(art_clip, 0.40, 0.45, 0.64)
	# THE BEVEL, over the art and under the frame: a dark lip along the top edge
	# and a warm one along the bottom. It is what makes a tile read as pressed
	# INTO the page rather than printed on it — the difference between a strip of
	# pictures and a rack of objects. One light source, up-left, the same one the
	# pool under the portrait implies.
	Sheen.inset(slot, 0.55)
	# One rule for every tile. The gilt edge used to mark the banner's card as the
	# one the chip column was responsible for; with no banner there is no odd one
	# out, and a deck of equals should look like one.
	#
	# A MOLDING, NOT A 1px RULE (2026-09-17). This was a transparent-bg
	# `ChartPanelStyle`, i.e. its metal rule alone — one `add_polyline` in one
	# colour, which is the flat-`Line2D` defect in a frame's hat (see
	# PlateFrame.gd's header for the full diagnosis). Ten of these in a grid is
	# where it showed worst: ten identical hairlines read as a spreadsheet's cell
	# borders, which is exactly the thing the vignette and the inset bevel were
	# added to fight from the inside.
	#
	# Quieter than the portrait's on purpose — lower `lit_gain`, less wobble.
	# There are ten of them and they frame the supporting act, not the subject.
	# Ten in a row is also where a sagging run showed worst — ten frames each
	# bending a different way is a rack of warped boards. Straight now; the glint
	# carries the variation, and it is seeded per node so no two tiles glint alike.
	#
	# MITRED (2026-09-18), and ten in a row is where the octagon showed worst. A
	# 9px chamfer on a 77px tile takes a visible bite out of every corner, so the
	# strip read as a rack of TOKENS; and because the painting inside is a
	# rectangle, each cut corner needed a near-black wedge painted over it to hide
	# the picture poking out, which is what made the corners look burnt. A mitred
	# corner covers its own picture, so both go away together.
	PlateFrame.over(slot, Color(0.52, 0.44, 0.31, 0.82), {
		"corner": "mitre", "rule_w": 4.2, "rebate": 2.2, "drop": 1.6,
		"lit_gain": 0.62, "shimmer": 0.30, "cornsweet": 2.2})
	## ── ONE BADGE LAYER, AND `_probe_alignment` IS WHY (2026-09-18).
	##
	## The ×N chip sits inset 3px from the tile's top-right corner, which is
	## intent. Added straight to `slot` it becomes a PEER of that node's full-rect
	## siblings — the art clip, the molding, the catcher — and C30 duly reported
	## "3.0px off the top its 3 peers share" on every tile carrying a badge: 9
	## hits in step 4 and 3 in step 3. It was right to. 3px is squarely in the
	## band that gate exists to catch ("zero is intent and forty is intent, three
	## is a slip"), and from the outside a badge inset from a corner is
	## indistinguishable from a full-rect overlay that missed.
	##
	## The fix is structural rather than a waiver: the badge gets its own
	## full-rect layer, so at `slot` level every child is genuinely full-rect and
	## the inset is measured against the layer instead. The gate then has nothing
	## to report because nothing is misaligned, which is the difference between
	## fixing a finding and silencing one.
	##
	## The layer outlived the pair it was built for — the cost gem that shared it
	## was cut on 2026-09-19 — and it is KEPT, because the finding was never about
	## the gem: the ×N chip has always been at y=3 and only escaped the gate on
	## its own because it appears on one tile at a time, too few to form a judged
	## group. Fold it back into `slot` and the hits come back the first time an
	## opener deals two pairs.
	var badges := Control.new()
	badges.set_anchors_preset(Control.PRESET_FULL_RECT)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(badges)
	if count > 1:
		var chip := _make_display_label("×%d" % count, 16, GILT_BRIGHT)
		chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		chip.add_theme_constant_override("outline_size", 6)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badges.add_child(chip)
		chip.size = Vector2(32, 22)
		chip.position = Vector2(w - 34.0, OPENER_BADGE_INSET)
	# Topmost catcher: the tooltip names the card (the tile is a picture, and a
	# picture alone cannot be looked up), and the hover floats the readable face.
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.add_child(catcher)
	var tip := String(data.get("name", id))
	var gloss := _deck_mini_tooltip(id)
	catcher.tooltip_text = gloss if gloss != "" else tip
	catcher.mouse_entered.connect(_show_deck_preview.bind(id, slot))
	catcher.mouse_exited.connect(_hide_deck_preview)

	## ── THE TILE SAYS WHAT THE CARD IS, AND SAYS IT IN WORDS (2026-09-19).
	##
	## Ten paintings tell you what the run will FEEL like and nothing about what
	## is IN it: there was no name and no cost anywhere on the strip, and the
	## only way to identify a card was to hover it one at a time — which the
	## catcher above admits in as many words ("a picture alone cannot be looked
	## up"). The owner asked whether small card faces would be better. They
	## would not: `Card2D` holds rules text at an absolute 18px floor and
	## `_fit_desc_to_box` would rather clip the card than shrink a glyph, so the
	## faces this strip replaced were rendering their rules at 11.2px — under the
	## 14px reading floor, and worse than absent because text that looks readable
	## and is not reads as a defect.
	##
	## The 2026-09-18 pass answered that with a NAME and a COST GEM. The gem is
	## gone again (owner, 2026-09-19: "so ugly"), and the reason it looked wrong
	## is the same one this strip was built on. A tile is a PAINTING in a molding
	## — one warm material, lit up-left, with the frame and the bevel doing the
	## separating. A navy enamel disc is the loudest possible foreign object to
	## park on that: highest chroma on the screen, highest contrast against its
	## own corner of art, and ten of them in a grid form a row of identical blue
	## dots that the eye reads BEFORE any of the pictures. On a card face that
	## gem earns its volume, because cost is the number you play by; on a setup
	## screen nobody plays off this strip, and the cost of every card in it is
	## one hover (the catcher floats the full readable face) or one click (VIEW
	## FULL DECK) away.
	##
	## So the tile carries the name and nothing else. No rules box and no gem,
	## which means nothing on it is illegibly small and nothing on it competes
	## with the art it exists to show.

	## THE NAME IS A RAW LABEL, NOT `_make_display_label`, AND THAT IS DELIBERATE.
	##
	## That helper clamps every size to `GameTheme.MIN_LABEL_SIZE` (18), which is
	## correct for the menu's own typography and wrong here: at 18px Cinzel a
	## 103px tile holds about ten characters, so most card names would wrap to
	## three lines and the strip would be taller than the paintings it captions.
	## 15 is the house CAPTION floor (COPY_STYLE §11: reading >= 18, captions
	## 15-17, nothing worded below 14), so this is inside the contract rather
	## than around it — it is a caption, not reading text.
	##
	## The height is FIXED at two lines whether or not the second is used. A
	## GridContainer row is as tall as its tallest child, so a name that wraps
	## would otherwise make one tile taller and shunt the whole rank — ten tiles
	## of equal height is what stops the strip reading as a ragged edge.
	var nm := Label.new()
	nm.text = String(data.get("name", id))
	if GameTheme.font_display:
		nm.add_theme_font_override("font", GameTheme.font_display)
	nm.add_theme_font_size_override("font_size", OPENER_NAME_SIZE)
	nm.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	nm.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.01, 0.85))
	nm.add_theme_constant_override("outline_size", 3)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	nm.custom_minimum_size = Vector2(w, OPENER_NAME_H)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The art keeps its own tile (frame, bevel, vignette, chip and catcher all
	# belong to the PAINTING), and the caption sits beneath it in the column —
	# rather than growing `slot`, which would put the molding round the words and
	# scissor the caption inside the art's vignette.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_child(slot)
	col.add_child(nm)
	return col


## A stretch of empty height that absorbs whatever the step does not use. Named
## so _animate_subscreen_reveal can skip it: the reveal staggers 45ms per child,
## and spending two of those beats fading in nothing delayed the commit row by a
## tenth of a second for no pixels.
func _muster_slack(parent: Container, stretch: int = 1) -> void:
	var slack := Control.new()
	slack.name = "Slack"
	slack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slack.size_flags_stretch_ratio = float(stretch)
	parent.add_child(slack)


## THE FOOTER HAS A FIXED HEIGHT, WHICH IS WHAT MAKES BACK STAND STILL
## (2026-08-04). The pass that pinned the header shipped a 39px jump at the
## other end and did not notice — measured: the BACK ink band is canvas y
## 809.2–820.8 on steps I, II and III (identical to the pixel) and 770.0–782.5
## on IV. Two causes, both here: `_make_begin_button` is 56 tall against
## `_make_menu_button`'s 46, and the promise line is appended ONLY on the commit
## step. So the one screen where the escape hatch matters is the one screen
## where it is not where the previous three taught you to look.
##
## Both halves are reserved on every step now — the actions row takes the taller
## of the two button heights, and the promise's line box is held open whether or
## not it has words in it.
const MUSTER_NAV_ROW_H := 56
## A roster row on RUN SETUP. See _make_muster_host_row for why it is this tall.
## The page's width, and the three bands measured against it. Written down
## together because the composition only works while they agree: the plate sets
## the band's height, the roster and the dossier are laid out against it, and the
## rail spans the whole width underneath. Changing one in isolation is what
## produced the torn bottom edge this pass fixed.
const MUSTER_PAGE_W := 1560.0
## 420, not 340. At 340 the text column was ~230px wide and every tagline
## wrapped to two lines, which put the second line under the selection rule that
## the focus box draws along the row's bottom edge — the tagline and the
## underline crossing each other on the first control a player ever touches. A
## roster row's copy must fit ONE line: see the tagline's overrun mode below.
const MUSTER_ROSTER_W := 420.0
## 316, and THE CLAIM THIS CONSTANT USED TO MAKE WAS FALSE (2026-09-17).
##
## It read: "this number IS the page's vertical budget: the plate is 3:4, it is
## the tallest thing in the band, and the roster and the dossier are both laid
## out against the height it sets." Measured: the roster is five
## MUSTER_HOST_ROW_H rows at 108 plus four 6px separations = **564**, against the
## plate's 352/0.75 = 469. The roster has been the taller of the two all along,
## so MUSTER_BAND_H is a non-binding minimum and the plate has never set the
## page's height — it has been sitting in a band 95px taller than itself.
##
## That mattered because the false claim was the whole defence of the plate's
## size, and the size is the page's biggest composition problem: the portrait
## carried 31.7% of all optical weight on the screen — the single heaviest object
## — for information the player already has, since the roster row they just
## clicked shows the same face. It is a seductive detail in the strict sense
## (interesting, irrelevant to the decision, competing with it for attention);
## the meta-analytic effect of those on TRANSFER — "could you then act on it",
## which is exactly what a character select is for — is medium.
##
## 316 rather than something smaller because the plate is still the emotional
## payload of a character select and faces capture attention involuntarily; this
## is a 19% cut in area, not a demotion. See docs/PRESENTATION_METHOD_20260917.md.
const MUSTER_PLATE_W := 316.0
## The dossier's prose measure. The column is wider than this on purpose; a
## sentence set to the full column ran 830px, which is roughly twice a
## comfortable measure and made the lord's pitch the longest line on the page.
##
## 560, DOWN FROM 660 (2026-09-17) — and the number is now MEASURED rather than
## judged. At 660 with the pitch set at 16px, the Raider's first line ran
## **88 characters**. Bringhurst's band is 45–75 with the optimum near 66, and
## Baymard measured the failure mode directly: copy past 80 CPL was skipped 41%
## more often than copy at 60–70. The longest run of type on the page was the one
## sentence that explains the lord.
##
## The fix is BOTH terms, because they pull the same way: 560px at the pitch's
## new 18px lands at ~66 CPL — the optimum — and the larger glyph also puts more
## ink per unit area into the block that `tools/measure_screen_aesthetics.py`
## ranked as the FAINTEST content on the page. Narrowing alone would have made
## the right column lighter still, which is the opposite of what this screen
## needs. See docs/PRESENTATION_METHOD_20260917.md §5D.
const MUSTER_PROSE_W := 560.0
## A MINIMUM, and a NON-BINDING one — see MUSTER_PLATE_W for the measurement.
## The roster is the tallest thing in this band (5 x 108 + 4 x 6 = 564) and has
## been since the row height was set, so this floor has never been what decides
## the page's height. Kept as a floor so a hero with a short dossier cannot
## collapse the band, and deliberately NOT re-derived from the plate: tying it
## back to the plate's aspect is what made the old docstring claim something the
## layout does not do.
const MUSTER_BAND_H := 469
## ── THE DOSSIER'S TYPE SCALE AND SPACING SCALE (2026-09-17) ──
##
## The dossier measured FLAT — last of every content block in the squint
## ranking — and it was not a contrast problem: its body copy sits at 10.7:1
## against this ground where WCAG AA asks 4.5, so there was no brightness left
## to buy. It was two structural faults, both measurable.
##
## FAULT 1, THE SCALE COLLAPSED. The block ran 34 / 20 / 18 / 17 / 15 — five
## nominal levels whose adjacent steps are 41% / 10% / 6% / 12%. Perceptible
## hierarchy needs roughly a 20-25% jump between adjacent levels, so everything
## from the relic name down was ONE level wearing four sizes: 17 and 18 are a 6%
## difference and simply read as the same size, which is noise rather than
## hierarchy. Three real levels beat five fake ones, and past three the published
## advice is to switch channels — weight, colour, caps — which this screen
## already does (GILT_BRIGHT on the relic name, letter-spaced caps on captions).
##
## FAULT 2, THE SPACING WAS INVERTED — see `_build_muster_roll`.
##
## Steps here are 1.20 / 1.22 / 1.55. MUSTER_TYPE_READ is also the COPY_STYLE §11
## reading floor, so it cannot go below 18 without a waiver.
const MUSTER_TYPE_CAPTION := 15
const MUSTER_TYPE_READ := 18
const MUSTER_TYPE_NAME := 22
const MUSTER_SEP_LINE := 2
const MUSTER_SEP_INBLOCK := 4
const MUSTER_SEP_BLOCK := 18

## A roster row on RUN SETUP: five of them fill the band beside the plate.
##
## 124, up from 108 (2026-09-17). TWO larger values were measured and rejected:
## 140 ran the roster past the canvas and clipped The Kindler's row, and 130
## still pushed START RUN off the bottom edge. The usable headroom was ~70px,
## not the ~160px the empty band appeared to offer — most of that band was the
## footer's own separation, which is not free space.
##
## Moving the deck rail into the hero column took a 160px full-width band off
## the page and `_muster_slack` turned it straight into a hole (0.0049 mean
## optical weight against a page mean of 0.0555). The slack cannot just be
## deleted — it is the C32 UI-scale contract — so the content has to grow into
## the space. 5x124+24 = 644 puts what there was of it back.
##
## It is also the cheapest weight the DECISION can be given: a roster row is the
## only control on this screen that picks anything, and the roster measured
## 16.6% of the page's ink at squint 0.052 — below the art it sits beside.
const MUSTER_HOST_ROW_H := 124
const MUSTER_NAV_PROMISE_H := 26

func _build_muster_nav(parent: VBoxContainer, back_cb: Callable,
		next_text: String, next_cb: Callable, next_control: Control = null) -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	actions.custom_minimum_size = Vector2(0, MUSTER_NAV_ROW_H)
	parent.add_child(actions)
	# NO FLAME ON THIS ONE, SO ITS WORD LANDS ON THE PANE'S COLUMN (2026-08-04).
	# Measured: BACK's ink began at canvas x 70.8 while the panes above it start
	# their content at x 44.5 — a 26px out-dent, and a near-miss reads worse than
	# an obvious misalignment because the eye keeps re-checking it. The cause is
	# structural: the flame slot (28) plus its gap (12) sits ahead of every menu
	# label, while _make_muster_section indents its content by 12. Dropping the
	# flame and keeping the 12 puts BACK's B at 42 — the pane's own column, to
	# within a glyph's side bearing.
	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 17, 46, false)
	back.custom_minimum_size = Vector2(180, MUSTER_NAV_ROW_H)
	# MEASURE, don't expand. `_make_menu_button` hands every button EXPAND_FILL,
	# which was harmless while the forward action was frameless and expanding
	# too — but with the primary now a fixed-width plate, BACK's expanding cell
	# took a third of the row and pushed the plate ~140px right of canvas centre.
	# Pinned to its 180, BACK is mirrored exactly by the trailing balance dummy.
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(back_cb)
	_set_shell_cue(back, "back")
	actions.add_child(back)
	if next_control != null:
		# The caller's control (TAKE THE FIELD) rides the SAME centring as the
		# built-in primary below — it is a plate now too, so EXPAND_FILL would
		# stretch it the full width of the canvas.
		var cta_lead := Control.new()
		cta_lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cta_lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(cta_lead)
		actions.add_child(next_control)
		var cta_trail := Control.new()
		cta_trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cta_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(cta_trail)
		var cta_balance := Control.new()
		cta_balance.custom_minimum_size = Vector2(180, 0)
		cta_balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(cta_balance)
	else:
		# THE FORWARD MOVE IS PLATED AND ALREADY BURNING (2026-08-05). This was
		# `_make_menu_button` — the same frameless ivory word, at 19px against
		# BACK's 17, standing in the same row. On a render neither read as the
		# way on. The primary is a warm document tab with its flame lit at rest;
		# BACK keeps the frameless treatment, so the pair is now a hierarchy
		# rather than two labels. It is CENTRED in its own expanding cell, which
		# also stops a long step name ("SEE YOUR COMPANY") from drifting the
		# whole row off the pane's column.
		# Centred on the CANVAS, not on the leftover width: expanding spacers
		# either side plus a dummy matching BACK's 180 on the right, or the
		# plate sits visibly right of centre with BACK's cell pushing it.
		var lead := Control.new()
		lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(lead)
		var next := _make_primary_action(next_text, MUSTER_NAV_ROW_H)
		next.custom_minimum_size = Vector2(NAV_PRIMARY_W, MUSTER_NAV_ROW_H)
		next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		next.pressed.connect(next_cb)
		actions.add_child(next)
		var trail := Control.new()
		trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(trail)
		var balance := Control.new()
		balance.custom_minimum_size = Vector2(180, 0)
		balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(balance)
	# Reversibility is visible in BACK and the live step rail. The safety promise
	# is WORDED only beside the actual commit — but its height is reserved on
	# every step, or the commit step's footer grows and lifts BACK off the
	# baseline the other three just taught the player.
	var promise := _make_display_label(
		WritDB.muster_copy("subtitle") if next_control != null else "", 15,
		# ASH (0.62 grey) is the fine-print colour for text that sits on a panel.
		# This line does not — it prints under TAKE THE FIELD, at the foot of the
		# canvas, directly on the brightest flame in the painting. Same reason the
		# main menu's own subtitle was lifted off ASH years ago.
		Color(0.80, 0.75, 0.65))
	promise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	promise.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promise.custom_minimum_size = Vector2(0, MUSTER_NAV_PROMISE_H)
	parent.add_child(promise)


func _make_muster_section(parent: Container, heading: String,
		minimum_width: float, expand: bool = false) -> VBoxContainer:
	# ── FRAMELESS (2026-09-15) ──
	#
	# This built a bordered, FILLED PanelContainer per section. The muster stands
	# three of them side by side above four more bordered term tiles, so the
	# screen was eight boxes and thirty-two corner ornaments, with the painted
	# background visible only in the seams between them. Decoration applied
	# uniformly to everything is noise, not craft — and the house style is
	# frameless: the heading and its rule carry the grouping, `_set_subscreen_scrim`
	# already carries the contrast, and the art stays visible behind the words.
	# A section is A COLUMN OF TYPE, not a box.
	#
	# The heading is also a CAPTION now, not a title. At 18px GILT_BRIGHT it was
	# the same weight as the hero's own name two lines below it, so three section
	# labels competed with the one element on the screen that should lead. Small,
	# dim and letter-spaced, it names the column and then gets out of the way.
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(minimum_width, 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if expand:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	var label := _make_caption_label(heading, 15, Color(0.68, 0.60, 0.47))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(label)
	col.add_child(_make_ornament_row(minimum_width - 18.0, true, false, true))
	return col


func _make_muster_host_row(hid: String) -> Button:
	var hero := HeroDB.get_hero(hid)
	var btn := Button.new()
	# The row stacked a name (18px display, ~24px line) over a tagline AND a
	# pitch (14px, ~19px each) at zero separation — ~62px of text into 64px of
	# usable box after the 3px insets. Every roster row rendered with its third
	# line grazing the boundary, and on the focused hero the selection edge ran
	# straight through the pitch like a strike-through. Ellipsis truncation was
	# catching the horizontal overflow; nothing caught the vertical.
	#
	# Growing the row to fit three lines just moved the problem: it pushed TAKE
	# THE FIELD off the bottom of the screen. The third line is the fix — it is a
	# TRUNCATED DUPLICATE of the hero's desc, which THE COLUMN pane prints in
	# full, unclipped, for whichever hero is focused. The list needs to identify
	# and differentiate; the detail pane explains. Two lines do the first job.
	#
	# 2026-07-31: 400 wide, not 320. Every one of the five taglines was being
	# ellipsised — they run 35-39 characters against a box that held ~33, and the
	# alternate-doctrine taglines reach 42. What the clip ate was always the
	# second clause, which is the differentiating half.
	# 130 tall on RUN SETUP (2026-09-16), against the old 66. The roster is one of
	# two panes on a 744px row now, and five 66px rows left 400px of that column
	# empty under the last lord. A taller row is not padding: it buys a 96×122
	# PORTRAIT in place of a 46×62 thumbnail, which is the difference between a
	# list of names and a rank of people.
	btn.custom_minimum_size = Vector2(400,
		84 if _quick_march_active else MUSTER_HOST_ROW_H)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	row.offset_top = 4
	row.offset_bottom = -4
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	var portrait: Control
	if ResourceLoader.exists(portrait_path):
		var tex := TextureRect.new()
		tex.texture = load(portrait_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait = tex
	else:
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
			Color(0.10, 0.08, 0.09, 0.95), Color(GILT.r, GILT.g, GILT.b, 0.45), 1, 3, false))
		var monogram := _make_display_label(String(hero.get("name", hid)).left(1), 28, GILT_BRIGHT)
		monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate.add_child(monogram)
		portrait = plate
	# THE ROSTER IS FRAMED TOO (2026-09-17). Once the detail plate and the ten
	# deck tiles each carry a molding, five bare cut-out thumbnails beside them
	# become the unfinished part of the screen — the same "sticker on a dark
	# field" read the big plate had, just smaller and five times over.
	#
	# The MOUNT is what goes in `_hero_portraits`, not the art: that map exists
	# for `_focus_hero`/`_preview_hero` to dim an unchosen lord, and a row whose
	# painting dims while its frame stays lit is worse than no frame at all.
	# Modulate on the wrapper carries both.
	var mount := Control.new()
	mount.custom_minimum_size = Vector2(58, 78) if _quick_march_active \
		else Vector2(74, 94)
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(portrait)
	# No tacks at this size — four studs on a 96px thumbnail is hardware the eye
	# has to resolve five times down a list, and the list is not the subject.
	# MITRED, and at 74x94 it matters most: a 7px chamfer is a tenth of the short
	# side off each corner, which turned five portraits into five gemstones.
	_faction_frame(mount, hid, {
		"corner": "mitre", "rule_w": 3.4, "rebate": 1.6, "drop": 1.2,
		"lit_gain": 0.58, "shimmer": 0.22, "cornsweet": 1.8,
		"tacks": false})
	row.add_child(mount)
	_hero_portraits[hid] = mount
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 2)
	# Centred on the taller row too: a 122px portrait beside two lines of text
	# top-flushed leaves the words hanging off the plate's shoulder.
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)
	# THE RECOMMENDATION BELONGS ON THE ROW IT RECOMMENDS (2026-08-05). It used
	# to print only in the detail pane's top-RIGHT corner, ~1100px away from the
	# roster and only once that hero was already focused — so on the screen a
	# first-time player meets first, the advice was somewhere they were not
	# looking, about a choice they had already made. Here it rides the name, in
	# the roster, before the click. The pane keeps its copy for the player who
	# lands on Raider by another route.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(name_row)
	var name_label := _make_display_label(String(hero.get("name", hid)), 22, GILT_BRIGHT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_row.add_child(name_label)
	if _quick_march_active and hid == HeroDB.HERO_ORDER[0]:
		# Only on the first-run screen. In THE MUSTER proper the player has
		# marched before and does not need to be told where to start.
		var star := _make_caption_label("START HERE", 14, Color(0.90, 0.74, 0.44))
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(star)
	# A CAPTION, NOT A SECOND HEADLINE (2026-09-15). This was a display label at
	# Color(0.98, 0.83, 0.58) — a hair off GILT_BRIGHT — and `_make_display_label`
	# floors every size at MIN_LABEL_SIZE, so the "14" rendered at 18. Five
	# taglines therefore sat at near-name brightness and near-name size directly
	# under five names, and the roster read as ten headlines rather than as five
	# heroes. The tagline is the DIFFERENTIATOR and stays; it just stops competing
	# with the word it qualifies.
	var tag := _make_caption_label(String(hero.get("tagline", "")), 15,
		Color(0.72, 0.65, 0.55))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# ONE LINE, CLIPPED IF IT MUST BE — not wrapped. A wrapping tagline pushes
	# its second line into the rule the focus box draws along the row's bottom
	# edge, and the two cross. The full sentence is a tooltip and the dossier
	# prints the lord's whole pitch unclipped the moment he is focused, so
	# nothing is lost; what is bought is a roster that cannot collide with
	# itself whatever an author writes in HeroDB.
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(tag)
	# (The truncated `desc` line lived here — see the row-height note above. It is
	# printed in full by THE COLUMN pane, so the roster keeps the tooltip and
	# drops the ellipsised copy.)
	btn.tooltip_text = String(hero.get("desc", ""))
	# PREVIEW is not SELECTION. Hover and keyboard focus only light the row;
	# `pressed` is the one thing that changes which lord marches. Bound to
	# `mouse_entered`, choosing a lord was a side effect of where the pointer
	# travelled — and since BACK sits directly under this column, reaching for it
	# re-selected every row on the way down and wiped the doctrine toggles with
	# it. See _focus_hero for the full account.
	btn.mouse_entered.connect(_preview_hero.bind(hid, true))
	btn.mouse_exited.connect(_preview_hero.bind(hid, false))
	btn.focus_entered.connect(_preview_hero.bind(hid, true))
	btn.focus_exited.connect(_preview_hero.bind(hid, false))
	btn.pressed.connect(_focus_hero.bind(hid))
	# Choosing a lord is a pick that does not advance — "select", not "commit".
	_arm_shell_button(btn, "select")
	_hero_cards[hid] = btn
	return btn


## Fill the lord's half of the page: the PLATE and the DOSSIER side by side in
## `_hero_detail`, and the DECK RAIL in its own band underneath (2026-09-17).
##
## `compact` still means the old single stack and is left alone — it is what the
## other callers of this function get.
func _build_muster_roll(hid: String, compact: bool = false) -> void:
	if _quick_march_active:
		if _quick_march_stage == 1:
			_build_quick_hero_identity(hid)
		else:
			_build_quick_march_roll(hid)
		return
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	var animate_swap := _muster_roll_ready
	_cancel_muster_roll_reveal()
	var swap_generation := _muster_roll_generation
	_hide_deck_preview()
	_clear_muster_container_now(_hero_detail)
	var hero := HeroDB.get_hero(hid)
	var opener: Array[String] = RunState.opening_deck_for(hid, _muster_alt_deck)
	var pane: VBoxContainer = null

	if compact:
		pane = VBoxContainer.new()
		pane.add_theme_constant_override("separation", 6)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hero_detail.add_child(pane)
	else:
		# ── THE PLATE ──
		# 412×549 at the portrait's own 3:4 (the files are 928×1232), so COVERED
		# crops essentially nothing. It is the tallest thing on the page and it
		# sets the band's height; everything beside it is laid out against that.
		var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
		if ResourceLoader.exists(portrait_path):
			var plate := Control.new()
			plate.custom_minimum_size = Vector2(
				MUSTER_PLATE_W, MUSTER_PLATE_W / 0.75)
			# TOP-ALIGNED, and centring was TRIED AND REVERTED (2026-09-17).
			#
			# The argument for centring was the dead-space rule: the plate is
			# ~145px shorter than the band the roster sets, and SHRINK_BEGIN puts
			# all of that slack under the portrait in one lump. Built it, measured
			# it, and it was worse on both counts.
			#
			# NUMERICALLY: Ngo balance on the HORIZONTAL axis fell 0.843 -> 0.661
			# (top/bottom ink went 45.7/54.3 to 39.8/60.2), because centring is
			# just "move the heaviest object on the page downward".
			#
			# STRUCTURALLY, and this is the real reason: the three columns in this
			# band — roster, plate, dossier — SHARE A TOP EDGE, and that shared
			# edge is doing more work than the slack was costing. Centred, the
			# portrait started 71px below the lord's own name beside it and read
			# as floating. The dead-space rule is about content pinned to the top
			# of a tall rect with NOTHING BELOW IT; here the deck rail is directly
			# below, so the gap separates two bands rather than hanging under one.
			plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var clip := Control.new()
			clip.set_anchors_preset(Control.PRESET_FULL_RECT)
			clip.clip_contents = true
			clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.add_child(clip)
			var face := TextureRect.new()
			face.set_anchors_preset(Control.PRESET_FULL_RECT)
			face.texture = load(portrait_path)
			# EXPAND_IGNORE_SIZE or the node claims the texture's full size as
			# its minimum and the anchors never bring it down.
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clip.add_child(face)
			# The edge burn fuses the painting into its plate instead of leaving
			# a cut-out on a dark field, and drags the cool portraits toward the
			# shell's ember so five lords stop reading as a contact sheet.
			Sheen.vignette(clip, 0.70, 0.55, 0.56)
			# ── THE FRAME. A MOLDING, NOT A RULE (2026-09-18).
			#
			# THIS IS THE ONE PLATE THE MOLDING PASS MISSED, and it is the largest
			# frame in the game. `PlateFrame` was written on 2026-09-17 and adopted
			# by the opener tiles and the roster thumbnails; the muster's own
			# portrait — the subject of the screen — kept a transparent-background
			# `ChartPanelStyle` at border width 2, which is the exact construction
			# that file was written to replace: ONE `canvas_item_add_polyline` in
			# ONE colour, with no cross-section and no light direction available to
			# it, plus the panel kit's flat corner quads for hardware.
			#
			# MEASURED on the shipped screen before the swap, and every number is a
			# symptom of that one cause:
			#   * the top run's crest wandered y=137..143 — SIX PIXELS of sag over a
			#     300px run, from `ChartPanelStyle._plate`'s length-sampled hand-cut
			#     (`seg / 22.0`, GameTheme.gd:613). Deckling is right for paper and
			#     wrong for cast metal, and silhouette position is the channel the
			#     eye is hyperacute in — vernier offsets resolve to 2-5 arcsec.
			#   * crossing the rule gave [0.20 0.47 0.73 0.80 0.69 0.43 0.18], a
			#     symmetric hump with a FLAT 0.805 plateau at its top, identical on
			#     the top and bottom runs. A highlight that does not move with the
			#     shading field is read as pigment rather than as gloss (Anderson &
			#     Kim 2009), which is why it photographed as a cream stripe painted
			#     round the picture.
			#   * at luminance 0.805 / saturation 0.213 it was the PALEST and least
			#     saturated object on the page, against the painting it is supposed
			#     to be holding at 0.240 / 0.444.
			#
			# `rule_w` 5.4 rather than the portrait default 6.0: MUSTER_PLATE_W came
			# down in the composition pass and a 6px molding on a 412px plate starts
			# eating the lord. No `wobble` — the glint rides `shimmer` instead.
			#
			# `corner: "mitre"` (2026-09-18). The moulding was right and the
			# SILHOUETTE was wrong: a chamfered octagon is a token, and no picture
			# frame ever made has cut corners. Measured here before the switch, the
			# cut corner peaked at 1.47x the straight run (0.612 against 0.415) —
			# the loudest mark on the page after the title — because a chamfer's
			# normal and `LayerStyle.LIGHT_A` are BOTH at 45 degrees, so it was the
			# one spot on the frame facing the lamp dead on. `chamfer` goes with it;
			# see `PlateFrame._draw_mitred` for the whole argument.
			_faction_frame(plate, hid, {
				"corner": "mitre", "rule_w": 5.4, "rebate": 3.0,
				"drop": 1.8, "shimmer": 0.40, "cornsweet": 3.0})
			Sheen.plinth(plate, _faction_accent(hid).lerp(
				Color(1.0, 0.56, 0.22), 0.55), 150.0, 0.30)
			Sheen.sheen(plate, GILT_BRIGHT, 0.30)
			_hero_detail.add_child(plate)

		# ── THE DOSSIER (2026-09-17 composition pass) ──
		#
		# Measured before this pass (tools/measure_screen_aesthetics.py): the page
		# carried 60.0% of its optical weight in two blocks that hold no decision
		# — the portrait (31.7%) and the deck strip (28.3%) — while the dossier,
		# which is the ONLY thing that differentiates one lord from another, held
		# 9.9% and ranked FAINTEST of all content in the squint test, below the
		# BACK button. Ngo balance on the vertical axis was 0.633 against a shell
		# median of 0.878: pictures on the left, bare type on the right.
		#
		# What fixed it was the TYPE (see MUSTER_PROSE_W, the pitch's 18 and the
		# relic rule's 17) and taking area off the PORTRAIT (see MUSTER_PLATE_W).
		# Both are subtractive or in-place. Nothing was added to the page.
		#
		# ── A PLINTH WAS TRIED HERE AND IT DOES NOT WORK. DO NOT RE-ADD IT. ──
		#
		# The reasoning for it was good and the result was bad, so both are worth
		# keeping. It was meant as SIGNALLING in the Mayer sense — cueing the block
		# that carries the decision, which is the largest effect in the literature
		# this pass surveyed (meta-analysis of 103 studies, N=12,201: retention
		# g+ = 0.53, transfer g+ = 0.33) — and as a GROUND rather than a box, so
		# it would not violate the 2026-09-15 ruling that stripped this screen's
		# bordered panels ("a section is A COLUMN OF TYPE, not a box").
		#
		# Built, rendered and measured twice. At strength 0.16 it moved the
		# dossier's mean optical weight 0.0443 -> 0.0490 and its squint rank not
		# at all: cosmetic. At 0.32 it became plainly visible and plainly WRONG —
		# a warm blob hanging in open canvas to the right of "Relocate allies",
		# attached to nothing, reading as a lens flare.
		#
		# The cause is a property of the TOOL, not of the tuning, which is why no
		# third strength would have fixed it. `Sheen.plinth` is "the pool a SUBJECT
		# STANDS IN" and its shader centres an ellipse on its target's RECT. This
		# column's rect is ~780x564 while its content is left-flush and ~560x420 —
		# so the pool centred itself in the empty bottom-right and lit the HOLE
		# instead of the type. A tall left-flush column of prose has no standing
		# point for a pool to find. Use the plinth on a plate, a portrait or a
		# tile; never on a column of text.
		#
		# THE BROADER LESSON, and the reason this is longer than the code it
		# replaced: BALANCE WAS A DIAGNOSTIC, NOT A TARGET. The measured 0.633
		# said the composition was picture-left / type-right. It did not licence
		# bolting a light source onto the page until the number moved. See
		# docs/PRESENTATION_METHOD_20260917.md §5 and its negative-results note.
		pane = VBoxContainer.new()
		# ── THE SPACING IS A RATIO, NOT A PADDING (2026-09-17) ──
		#
		# 18, up from 4, and the old value was INVERTED against its own children:
		# this pane is the page's outermost BETWEEN-group container and it was
		# separating at 4, while `prose` — a container of things that belong
		# together — separated at 10. Gestalt proximity is read relatively and
		# pre-verbally: the gap between groups must be visibly LARGER than the gap
		# inside them, or every element clusters with every other element and the
		# grouping disappears. That is most of why the dossier measured flat;
		# it was not a weight problem, it was a grouping problem.
		#
		# The scale used through the dossier is 2 within a line / 4 within a block
		# / 18 between blocks.
		pane.add_theme_constant_override("separation", MUSTER_SEP_BLOCK)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_hero_detail.add_child(pane)
		# The name and its record are ONE unit, so they get their own box at zero
		# separation. Left directly on `pane` they would take the 18px
		# between-block gap and the record would read as a fourth section rather
		# than as a subtitle on the lord's name.
		var ident := VBoxContainer.new()
		ident.add_theme_constant_override("separation", 0)
		pane.add_child(ident)
		# The loudest word on the screen by intent — the page title is chrome,
		# the section captions are labels, the lord is the answer.
		var heading := _make_display_label(String(hero.get("name", hid)), 34,
			_faction_accent(hid))
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		ident.add_child(heading)
		var record := _muster_record_line(hid)
		if record != "":
			var rec_lbl := _make_caption_label(record, MUSTER_TYPE_CAPTION,
				Color(0.72, 0.66, 0.54))
			rec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			ident.add_child(rec_lbl)
		# ── THE PROSE IS CAPPED, THE COLUMN IS NOT ──
		# The dossier is ~830px wide and the lord's pitch is one sentence, so
		# unconstrained it set a single 830px line — far past the measure
		# anything is comfortably read at, and the longest run of type on the
		# page. The COLUMN keeps its width (the run controls at its foot want
		# it); only the prose is held to a readable measure, and what is left is
		# margin against the canvas edge.
		var prose := VBoxContainer.new()
		# BETWEEN-group: this box holds the pitch sentence and, under it, the
		# signature-relic block. Those are two different things, so they take the
		# block gap — not the 10 they used to, which was larger than the gap
		# `pane` was putting between whole sections.
		prose.add_theme_constant_override("separation", MUSTER_SEP_BLOCK)
		prose.custom_minimum_size = Vector2(MUSTER_PROSE_W, 0)
		prose.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		pane.add_child(prose)
		# 18, up from 16 (2026-09-17). Two reasons and both are measured, not
		# taste: it is half of the CPL fix (see MUSTER_PROSE_W), and the dossier
		# measured as the faintest content on the page in the squint ranking —
		# below the BACK button. Note what did NOT fix that: the contrast is
		# already 10.7:1 against this ground (WCAG AA wants 4.5), so there is no
		# brightness left to buy. Squint weight is ink per unit AREA, so the
		# levers are glyph size, grouping and ground — never colour.
		var pitch := _make_display_label(String(hero.get("desc", "")), 18,
			GameTheme.DESC_DIM)
		pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pitch.custom_minimum_size = Vector2(MUSTER_PROSE_W, 0)
		prose.add_child(pitch)
		# The relic is the other half of what choosing a lord hands you; the deck
		# is the rail below. Both belong to him, so both sit in his half.
		_build_muster_doctrine_row(prose, hid, hero, compact)
		# ── HOW HE FIGHTS (2026-09-17) ──
		#
		# The dossier ran out of things to say two fifths of the way down its
		# column and left ~370px of bare canvas under the relic — the largest
		# hole left on the page after the last pass. The answer was not to
		# stretch what was already there: it was to notice that the screen was
		# WITHHOLDING the one thing a character select exists to tell you.
		#
		# `_quick_hero_traits` has held three playstyle phrases per lord since
		# the quick-march screen was built, and RUN SETUP — the screen a
		# returning player actually chooses from — never printed them. So this
		# is not filler; it is content that was already authored, already
		# player-facing, and was only ever shown to first-timers.
		#
		# A VERTICAL list, not the quick screen's horizontal chip row: height is
		# what this column has spare, and three stacked lines read as a dossier
		# entry where three inline chips read as a toolbar.
		var how := VBoxContainer.new()
		how.add_theme_constant_override("separation", MUSTER_SEP_INBLOCK)
		how.custom_minimum_size = Vector2(MUSTER_PROSE_W, 0)
		how.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		pane.add_child(how)
		var how_cap := _make_caption_label("HOW HE FIGHTS", MUSTER_TYPE_CAPTION,
			Color(0.68, 0.61, 0.48))
		how_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		how.add_child(how_cap)
		how.add_child(_make_ornament_row(MUSTER_PROSE_W - 18.0, true, false, true))
		for phrase in _quick_hero_traits(hid):
			var line_row := HBoxContainer.new()
			line_row.add_theme_constant_override("separation", 10)
			how.add_child(line_row)
			# A gilt en-dash rather than a bullet glyph: the shell has no bullet
			# anywhere else, and the road register's own lists use the dash.
			var lead := _make_display_label("—", MUSTER_TYPE_READ, GILT)
			lead.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line_row.add_child(lead)
			var phrase_lbl := _make_display_label(String(phrase),
				MUSTER_TYPE_READ, GameTheme.DESC_DIM)
			phrase_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			line_row.add_child(phrase_lbl)
		# ── THE COLUMN HAS TWO ANCHORS, NOT ONE ──
		# Identity at the top, the run's own terms at the bottom, and this
		# spacer between them. That is what turned the page's largest empty
		# region into margin: the dossier used to stop two fifths of the way
		# down and leave the rest bare.
		var id_tail := Control.new()
		id_tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
		id_tail.custom_minimum_size = Vector2(0, 12)
		id_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pane.add_child(id_tail)
		_build_muster_run_controls(pane)

	# ── THE DECK RAIL ──
	# Rebuilt with the lord, but it lives in its own band across the whole page.
	if compact or _hero_deck_rail == null \
			or not is_instance_valid(_hero_deck_rail):
		_build_muster_deck_block(pane, hero, hid, opener, compact)
	else:
		_clear_muster_container_now(_hero_deck_rail)
		_build_muster_deck_block(_hero_deck_rail, hero, hid, opener, compact)
	_muster_roll_ready = true
	if animate_swap:
		_reveal_muster_roll(hid, swap_generation)


## Clear a live Container synchronously. queue_free() alone leaves its children
## participating in layout until frame end, so the replacement sheet briefly
## contains BOTH decks and visibly shoves the new rail before snapping back.
func _clear_muster_container_now(parent: Container) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Portrait, dossier and opener are one answer to one choice. Reveal the two
## container roots together, with their final geometry already reserved; there
## is no per-card stagger and therefore no moving target under the cursor.
func _reveal_muster_roll(hid: String, generation: int) -> void:
	var detail := _hero_detail
	var rail := _hero_deck_rail
	var roots: Array[Control] = []
	if detail != null and is_instance_valid(detail):
		roots.append(detail)
	if rail != null and is_instance_valid(rail) and rail != detail:
		roots.append(rail)
	if roots.is_empty():
		return
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	for root in roots:
		root.modulate = Color.WHITE if snap else Color(0.76, 0.67, 0.52, 0.0)
	if snap:
		return
	# One layout frame sizes both roots while they are already occupying their
	# final slots. Only paint changes after this point.
	await get_tree().process_frame
	if generation != _muster_roll_generation or not is_inside_tree() \
			or hid != _selected_hero:
		return
	for root in roots:
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
	_muster_roll_tween = create_tween().set_parallel(true)
	_muster_roll_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for root in roots:
		_muster_roll_tween.tween_property(root, "modulate", Color.WHITE,
			Motion.time(0.22))
	# A single lamplight stroke crosses the completed opener. It punctuates the
	# swap without implying that ten independent cards loaded in sequence.
	if rail != null and is_instance_valid(rail):
		Motion.foil_sweep(self, rail,
			_faction_accent(hid).lerp(GILT_BRIGHT, 0.58), Motion.time(0.36))


func _cancel_muster_roll_reveal() -> void:
	_muster_roll_generation += 1
	if _muster_roll_tween != null and _muster_roll_tween.is_valid():
		_muster_roll_tween.kill()
	_muster_roll_tween = null
	if _hero_detail != null and is_instance_valid(_hero_detail):
		_hero_detail.modulate = Color.WHITE
	if _hero_deck_rail != null and is_instance_valid(_hero_deck_rail):
		_hero_deck_rail.modulate = Color.WHITE


## The deck's caption row and its art. Split out because it is built into two
## DIFFERENT parents — the full page gives it a band of its own, and every other
## caller stacks it under the lord.
func _build_muster_deck_block(parent: VBoxContainer, hero: Dictionary,
		hid: String, opener: Array[String], compact: bool) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	# The line and the action share a row: both are short and both are ABOUT the
	# rail below them, so stacking them spends two rows on one caption's ink.
	var roll_row := HBoxContainer.new()
	roll_row.add_theme_constant_override("separation", 18)
	roll_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(roll_row)
	# THE LINE STATES BOTH DENOMINATORS — the deck a Forge term would touch and
	# the max HP a PACT would charge on the next screen. "Lose 6 max HP" against
	# an unstated total is not a price. The compact variant leads with the lord
	# because it is drawn where no heading names him.
	var roll_line := _make_caption_label(
		("%s  ·  %d cards  ·  %d max HP" % [String(hero.get("name", hid)),
			opener.size(), RunState.STARTING_MAX_HP]) if compact
		else ("YOUR STARTING DECK  ·  %d cards  ·  %d max HP" % [
			opener.size(), RunState.STARTING_MAX_HP]),
		16, Color(0.80, 0.73, 0.60))
	roll_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	roll_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roll_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	roll_row.add_child(roll_line)
	# THE ACTION STAYS BESIDE THE WORDS IT ACTS ON (2026-09-17). The caption used
	# to claim EXPAND_FILL, which on a rail spanning the whole page threw VIEW
	# FULL DECK 1,100px to the right of "YOUR STARTING DECK" — at that distance
	# they are two unrelated elements at opposite ends of a line, not a label and
	# its action. The same defect the campaign record had in the old dossier, and
	# the same fix: pack it after, let the spacer take the remainder.
	#
	# 0 width, not a fixed one: the tab treatment underlines the control, and a
	# fixed width leaves bare rule running past the last letter.
	var inspect := _make_secondary_action("VIEW FULL DECK", 0, 34)
	inspect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inspect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspect.tooltip_text = "Open the complete starting deck."
	inspect.pressed.connect(_show_muster_deck_inspector)
	roll_row.add_child(inspect)
	var cap_tail := Control.new()
	cap_tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_row.add_child(cap_tail)
	# ONE ROW, NOT A GRID. Ten cards laid 6-then-3 gave the page a torn bottom
	# edge exactly where a composition needs a line. Across the full page width
	# the rail holds all ten at 148px each — WIDER than the 6-across grid managed,
	# so the cards got bigger and the ragged rank disappeared in the same move.
	var strip := _make_opener_art_strip(opener,
		MUSTER_OPENER_STRIP_W if not compact else OPENER_STRIP_WIDTH,
		MUSTER_RAIL_COLUMNS if not compact else OPENER_STRIP_COLUMNS)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(strip)


func _build_quick_march_roll(hid: String) -> void:
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	_quick_march_roll_generation += 1
	var build_generation := _quick_march_roll_generation
	var live_detail := _hero_detail
	_hide_deck_preview()
	_clear_muster_container_now(_hero_detail)
	var hero := HeroDB.get_hero(hid)

	var opener: Array[String] = RunState.opening_deck_for(hid, false)
	var shown: Array[String] = _representative_opening_cards(opener)
	# ── FOLD THE COPIES BEFORE ANYTHING COUNTS THEM (2026-09-15) ──
	#
	# `_representative_opening_cards` returns its picks WITH MULTIPLICITY — that is
	# deliberate, and it is what makes the ×N chip true on the muster strip. This
	# screen then drew one mini per ARRAY ENTRY with a hardcoded count of 1, so the
	# Raider's two Outriders rendered as two separate cards each stamped "×1"
	# (a chip that says "one copy" beside a second copy of itself), and the row
	# showed FOUR cards under a caption reading THREE DEFINING CARDS.
	#
	# Same counts/order fold `_make_muster_deck_strip` has always used. `want` is a
	# UNIQUE budget, so folding makes the row exactly as long as the caption claims
	# — and the caption is derived from the fold now, so it cannot drift again.
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in shown:
		var id := String(cid)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	# THE CAPTION SITS OVER THE CARDS IT NAMES (2026-08-03). It was flushed to the
	# pane's left edge while the row it labels is centred in a 1216px pane — three
	# minis measure 530, so the words "THREE DEFINING CARDS" ended 343px short of
	# the first card, with nothing in between. On the quick-company shot the label
	# reads as a stray caption and the cards as an unlabelled float.
	#
	# Centred, not left-flushed: the cards are the SUBJECT of this screen and
	# their symmetry is worth keeping (it echoes the centred "<HERO>'S COMPANY"
	# above), so the label moves to them. The lead spacer is the width of the
	# action on the right — without it "centre of the remaining box" is 118px left
	# of the centre of the pane, and the caption would miss the cards the other way.
	const CARD_HEAD_ACTION_W := 235.0
	var card_head := HBoxContainer.new()
	card_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_detail.add_child(card_head)
	var head_lead := Control.new()
	head_lead.custom_minimum_size = Vector2(CARD_HEAD_ACTION_W, 0)
	head_lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_head.add_child(head_lead)
	var card_title := _make_caption_label(
		"%d DEFINING CARDS" % order.size(), 15, Color(0.76, 0.69, 0.56))
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_head.add_child(card_title)
	# "VIEW FULL DECK", the same words the other three call sites use for the same
	# action (COPY_STYLE §12, one term per concept). This one printed the count as
	# well — "VIEW ALL 11 CARDS" — which made one button read as a different
	# control from its three twins; the count is still on screen in the
	# "YOU START WITH" fact directly below.
	var inspect := _make_secondary_action(
		"VIEW FULL DECK", CARD_HEAD_ACTION_W, 36)
	inspect.disabled = true
	inspect.tooltip_text = "Open the complete starting deck."
	inspect.pressed.connect(_show_muster_deck_inspector)
	card_head.add_child(inspect)
	var card_center := CenterContainer.new()
	card_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_row := HBoxContainer.new()
	card_row.name = "QuickMarchCardGroup"
	card_row.set_meta("coordinated_cards_ready", false)
	card_row.add_theme_constant_override("separation", 22)
	var card_slots: Array[Control] = []
	var card_backs: Array[Control] = []
	var card_blockers: Array[Control] = []
	for id in order:
		var stage := _make_deck_inspector_stage(0.72, card_row)
		var slot: Control = stage["slot"]
		var back: Control = stage["back"]
		slot.name = "QuickMarchCardSlot"
		slot.set_meta("coordinated_card_slot", true)
		card_row.add_child(slot)
		card_slots.append(slot)
		card_backs.append(back)
		# Faces contain hover catchers. Keep one transparent shield above each
		# socket until every face has finished its shared turn.
		var blocker := Control.new()
		blocker.name = "LoadingInputShield"
		blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		blocker.z_index = 80
		slot.add_child(blocker)
		card_blockers.append(blocker)
	card_center.add_child(card_row)
	_hero_detail.add_child(card_center)

	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 12)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_detail.add_child(facts)
	facts.add_child(_make_quick_march_fact(
		"YOU START WITH", "%d cards  ·  %d max HP" % [opener.size(),
			RunState.STARTING_MAX_HP], Color(0.76, 0.69, 0.56)))
	# Copper, not the sage (0.72, 0.80, 0.66) this carried until 2026-08-03. The
	# three facts are told apart by their accent, and that one was the only cold
	# hue in the run opening: on the quick-company shot the middle tile's hairline
	# and caption read GREEN between a bone tile and a gilt one, which is the
	# project's #1 recorded art defect (cold ink on the ember palette) printed on
	# the screen a first-time player spends longest reading. Bone / copper / gilt
	# are three distinct warm values and separate the tiles just as well.
	# (A BANNER tile stood here until 2026-09-16, naming the declared colours and
	# the levy card they added. The banner system is gone; the two facts left are
	# the ones a first-time player can act on.)
	facts.add_child(_make_quick_march_fact(
		"YOUR SIGNATURE RELIC", String(RelicDB.get_relic(
			String(hero.get("relic", ""))).get("name", "one relic")),
		Color(0.87, 0.63, 0.39)))
	facts.add_child(_make_quick_march_fact(
		"CAMPAIGN CHEST", "+10 gold after every victory",
		Color(0.94, 0.76, 0.34)))
	_build_muster_doctrine_row(_hero_detail, hid, hero, false)
	_hydrate_quick_march_cards(hid, live_detail, card_row, order, counts,
		card_slots, card_backs, card_blockers, inspect, build_generation)


## Quick March's three cards are one promise, not three independent network
## results. Reserve their complete geometry first, do all expensive work behind
## the connected backs, then publish every face on one beat. This prevents cold
## cache order from becoming visible order or moving the centred row.
func _hydrate_quick_march_cards(hid: String, detail: Container,
		group: HBoxContainer, order: Array[String], counts: Dictionary,
		slots: Array[Control], backs: Array[Control], blockers: Array[Control],
		inspect: Button, generation: int) -> void:
	# ANNOTATED, NOT INFERRED. `weakref()` is declared as returning Variant, so
	# `:=` infers Variant and this project treats that warning as an error — the
	# whole script then fails to load, which takes the title screen down. Every
	# other weakref in the codebase (35 sites) is written `: WeakRef =`; these two
	# were the only `:=` pair, and they were the only ones broken.
	var detail_ref: WeakRef = weakref(detail)
	var group_ref: WeakRef = weakref(group)
	var still_here := func() -> bool:
		# Same reason on the deref: `get_ref()` returns Variant, and `as T` does
		# not hand `:=` a concrete type either.
		var current_detail: Container = detail_ref.get_ref()
		var current_group: HBoxContainer = group_ref.get_ref()
		return generation == _quick_march_roll_generation \
			and is_inside_tree() \
			and _quick_march_active \
			and _quick_march_stage == 2 \
			and _selected_hero == hid \
			and current_detail != null \
			and current_detail == _hero_detail \
			and current_detail.is_inside_tree() \
			and current_group != null \
			and current_group.is_inside_tree()

	# Warm and cold caches enter through the same first painted tableau.
	await get_tree().process_frame
	if not still_here.call():
		return
	await _warm_deck_strip(order, hid, still_here)
	if not still_here.call():
		return

	var faces: Array[Control] = []
	for i in order.size():
		var face := _make_deck_mini(order[i], int(counts[order[i]]), 0.72)
		face.name = "QuickMarchCardFace"
		face.visible = false
		slots[i].add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		faces.append(face)
		# Card2D construction is deliberately spread out, but only behind a
		# complete row of already-positioned backs.
		await get_tree().process_frame
		if not still_here.call():
			return

	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	for face in faces:
		if is_instance_valid(face):
			face.visible = true
	if snap:
		for back in backs:
			if is_instance_valid(back):
				back.queue_free()
		_finish_quick_march_cards(group, blockers, inspect)
		return

	AudioBank.play_sfx("card_draw", 0.04, -6.0)
	for i in faces.size():
		if is_instance_valid(backs[i]) and is_instance_valid(faces[i]):
			Motion.flip_out(backs[i], 0.13)
			Motion.flip_in(faces[i], Motion.time(0.13), 0.17)
	Motion.foil_sweep(self, group,
		_faction_accent(hid).lerp(GILT_BRIGHT, 0.58), Motion.time(0.36))
	await get_tree().create_timer(Motion.time(0.31)).timeout
	if not still_here.call():
		return
	_finish_quick_march_cards(group, blockers, inspect)


func _finish_quick_march_cards(group: HBoxContainer,
		blockers: Array[Control], inspect: Button) -> void:
	for blocker in blockers:
		if is_instance_valid(blocker):
			blocker.queue_free()
	if is_instance_valid(inspect):
		inspect.disabled = false
	if is_instance_valid(group):
		group.set_meta("coordinated_cards_ready", true)


## One playstyle phrase, sized to its own words.
##
## A CAPTION, NOT A CONTROL (2026-08-04). These were bordered, filled,
## EXPAND_FILL equal-width pills — which is exactly what `_make_secondary_action`
## draws elsewhere in this same flow, so "Move first", "Attack open lanes" and
## "Relocate allies" rendered as three buttons directly under a live hero
## portrait on the screen a first-time player meets first. A player WILL click
## one of those, and nothing will happen, which is the worst thing a screen can
## teach in its first five seconds. The list is descriptive, so it is drawn as a
## description: no frame, no fill, no equal widths, each phrase measuring to its
## own words with a gilt separator dot carried by the row's spacing.
##
## Gilt on warm-black rather than the hero's faction colour: the factions are MAP
## washes (grasswake is a teal, lanternhall a slate blue), and cold ink was the
## one thing on this screen that did not belong to the fire.
func _make_trait_chip(text: String, lead_separator: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# The dot goes BETWEEN phrases, never in front of the first one — a leading
	# bullet on a horizontal list reads as a stray mark, not as punctuation.
	if lead_separator:
		var bullet := _make_caption_label("·", 17, Color(0.72, 0.58, 0.34))
		bullet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(bullet)
	var lbl := _make_caption_label(text, 16, Color(0.94, 0.88, 0.72))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return row


func _make_quick_march_fact(title: String, value: String, accent: Color) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 58)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := GameTheme.make_panel_style(
		Color(0.055, 0.038, 0.035, 0.88), accent.darkened(0.28), 1, 4, false)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 1)
	panel.add_child(copy)
	# THE CAPTION AND THE DATUM WERE THE SAME SIZE (2026-08-03). 14 and 15 both
	# floored to MIN_LABEL_SIZE (18), so a tile written as "small label over a
	# value" rendered as two lines of identical type and the eye had to read both
	# to find out which one it wanted. The first fix pushed the value up to 20; the
	# caption now also comes DOWN to a legal 15 through _make_caption_label
	# (2026-08-04), so the pair reads 15-over-20 as written instead of 18-over-20.
	copy.add_child(_make_caption_label(title, 15, accent))
	var body := _make_display_label(value, 20, IVORY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(body)
	return panel


## As much of the opener as the strip can print in ONE rank, in deck order,
## every pick carrying its REAL number of copies.
##
## (It used to lead with the banner's card, which was also the one card its body
## excluded — the caption named a card the strip did not show. Both halves went
## with the banner system, 2026-09-16.)
##
## THE COUNTS WERE ALL LIES (2026-08-04). The result was a unique-id list, and
## _make_muster_deck_strip derives its ×N chips by counting the array it is
## handed — so every chip on every muster strip read "×1", including Outrider,
## which the Raider opens with TWO of. Returning the picks with multiplicity
## makes the chip true without touching the strip.
##
## `want` is a UNIQUE-card budget, not a mini budget: the caller measures how many
## minis its pane can print (see _strip_rank_capacity) and the copies ride along.
func _representative_opening_cards(opener: Array[String],
		want: int = 3) -> Array[String]:
	var order: Array[String] = []
	for cid in opener:
		if order.size() >= maxi(1, want):
			break
		if order.has(cid):
			continue
		order.append(cid)
	var picks: Array[String] = []
	for cid in order:
		for i in range(opener.count(cid)):
			picks.append(cid)
	return picks


## How many minis _make_muster_deck_strip can lay in one rank of `avail` px at the
## full card size. Same arithmetic the strip itself uses, exposed so a caller can
## ASK for that many cards instead of printing three into a pane that measured
## 1070 wide and standing 633px of it empty.
func _strip_rank_capacity(avail: float) -> int:
	const SEP := 9.0
	return maxi(1, int(floor((avail + SEP) / (225.0 * DECK_MINI_SCALE + SEP))))



## This lord's record across every march on the profile (MetaState.hero_stats),
## as one line — or "" for a lord who has never marched.
##
## The empty case is the whole point of the function. "0 won · 0 lost" is not a
## record, it is a row of zeroes on the first screen a new player sees, printed
## five times as they walk the roster; and the unlocks it would sit beside
## (relic_alt at one win, deck_alt at Ascension 4) already carry their own locked
## state. Show the line only once it says something.
##
## Lived in the deleted _build_hero_detail until 2026-08-01 — the run opening had
## no record on it at all between the muster split and this.
func _muster_record_line(hid: String) -> String:
	var hs: Dictionary = MetaState.hero_stats.get(hid, {})
	var wins: int = int(hs.get("wins", 0))
	var losses: int = int(hs.get("losses", 0))
	if wins + losses <= 0:
		return ""
	var line := "%d won · %d lost" % [wins, losses]
	var best: int = int(hs.get("best_asc", -1))
	if best > 0:
		line += " · best win at Ascension %d" % best
	return line


## THE COLUMN, drawn up in as many equal RANKS as the pane will hold — and
## never behind a scrollbar.
##
## The opener is ten minis wide (nine retinue uniques + the banner's card) and a
## mini at DECK_MINI_SCALE is 139.5 across, so at separation 9 one rank measures
## 1471. Step III hands the column the whole menu (1516 usable) and it fits with
## 45px to spare. Steps I and II hang it beside the fixed 430 picker, which
## leaves 1070 — so the two steps where the deck IS the decision were hiding
## 401px of it, near enough three cards, behind a SCROLL_MODE_AUTO bar. Worse,
## the push-front above guarantees the BANNER's card is visible by shoving the
## tail further out of sight, so the strip's own fix was making the clip bite.
##
## Shrinking one rank to fit 1070 was the wrong trade: it needs scale 0.44,
## which renders the card's 18px rules line at 8px — that is the size the strip
## was RAISED from (see the DECK_MINI_SCALE note). So the cards keep their size
## and the column forms up in two ranks of five instead, 688px wide, well inside
## the pane. Step III still measures a single rank and is left untouched.
##
## Even ranks, not a full row and a stub: the pane's other content is a short
## left column, so a ragged 7-then-3 reads as an overflow, while two equal ranks
## read as a column drawn up — and the player can count the deck at a glance.
func _make_muster_deck_strip(deck: Array) -> Control:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in deck:
		var id := String(cid)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += 1
	var sep := 9
	var avail: float = MUSTER_STRIP_WIDTH_FULL if _muster_step == 3 \
		else MUSTER_STRIP_WIDTH_SPLIT
	var n: int = maxi(1, order.size())
	# Full size whenever the pane can print the whole column in one rank; the
	# ranked size only when it cannot. The pane decides the card, not the step.
	var mini_scale: float = DECK_MINI_SCALE
	if float(n) * (225.0 * mini_scale + sep) - sep > avail:
		mini_scale = DECK_MINI_SCALE_RANKS
	var mini_w: float = 225.0 * mini_scale
	var per_rank: int = maxi(1, int(floor((avail + sep) / (mini_w + sep))))
	var ranks: int = maxi(1, int(ceil(float(n) / float(per_rank))))
	var strip := GridContainer.new()
	strip.columns = maxi(1, int(ceil(float(n) / float(ranks))))
	strip.add_theme_constant_override("h_separation", sep)
	# 10, not 9: _make_deck_mini hangs each ×N count chip 6px ABOVE its slot, so
	# the gap between ranks has to clear it or the second rank's chips sit on the
	# first rank's cards.
	strip.add_theme_constant_override("v_separation", 10)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.tree_exiting.connect(_hide_deck_preview)
	for id in order:
		strip.add_child(_make_deck_mini(id, int(counts[id]), mini_scale))
	return strip


func _build_muster_doctrine_row(parent: VBoxContainer, hid: String,
		hero: Dictionary, compact: bool = false) -> void:
	# COMPACT DROPS THIS ENTIRELY, which is what _build_muster_roll's docstring
	# has always claimed and what the code never did. Two separate costs were
	# being paid on step III because of it:
	#
	#   HEIGHT — the signature block (icon + name + wrapped rule) is ~90px, and
	#   step III is the one step whose content already overruns the 900px canvas.
	#   With the column, writ row, gloss, campaign line, settings footer and nav
	#   stacked, TAKE THE FIELD was being laid out BELOW the bottom of the screen:
	#   the commit button of the whole run opening, off-canvas, worse at higher
	#   Ascension because the rules readout grows a line per unlocked tier.
	#
	#   DECISIONS — the doctrine toggles below are step I's choice. Re-rendering
	#   them here put them on screen twice, so THE TERMS carried six decisions for
	#   a returning player: as many as the single screen this flow was split up to
	#   fix. The split is only worth its extra clicks if the load actually leaves.
	#
	# Step III wants the deck as REFERENCE (its terms name specific cards, so the
	# player must not pick from memory — see _build_muster_step_terms). It does not
	# want the lord's identity furniture a second time.
	if compact:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var relic_id := String(hero.get("relic_alt", "")) if _muster_alt_relic \
		else String(hero.get("relic", ""))
	var relic: Dictionary = RelicDB.get_relic(relic_id)
	# The signature relic is HALF of what choosing a lord hands you — the deck is
	# the other half and gets eleven baked cards. It used to be the bare line
	# "SIGNATURE: Marching Spurs" with the rule itself buried in a tooltip, in a
	# panel that had ~100px of empty space under it. Icon, name and rule, printed.
	var chip := GameTheme.make_relic_chip(relic_id, 54)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(chip)
	var sig := VBoxContainer.new()
	sig.add_theme_constant_override("separation", MUSTER_SEP_LINE)
	sig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sig)
	sig.add_child(_make_caption_label("SIGNATURE RELIC", MUSTER_TYPE_CAPTION,
		Color(0.68, 0.61, 0.48)))
	# 22, up from 20. At 20 against the rule's 18 beneath it the step was 11% —
	# under the ~20-25% a reader resolves as a level change, so the relic's NAME
	# and its RULE read as one undifferentiated block.
	sig.add_child(_make_display_label(String(relic.get("name", relic_id)),
		MUSTER_TYPE_NAME, GILT_BRIGHT))
	# 17, up from 15 (2026-09-17). This one sentence is the single most
	# decision-relevant line on the screen — it is what one lord DOES that the
	# next one does not — and it was set two steps below the pitch above it and
	# level with the "SIGNATURE RELIC" caption that merely labels it. A rule
	# printed at caption size reads as a caption.
	var relic_desc := _make_display_label(String(relic.get("desc", "")),
		MUSTER_TYPE_READ, GameTheme.DESC_DIM)
	relic_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	relic_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sig.add_child(relic_desc)
	if not _bound_doctrine_unlocked(hid):
		return
	# THE UNLOCK TOGGLES ARE NOW FRAMED (2026-08-03), because at 32px tall they
	# were not buttons at all to look at. _make_menu_button's frameless treatment
	# only grows its affordances — the flame cursor and the gilt underline — at
	# height >= 40; below that every state is a StyleBoxEmpty and nothing happens
	# until the cursor is already on the word. So on the step-1 shot the two live
	# cross-run unlocks printed as "STANDARD DECK   STANDARD RELIC", two dim
	# 14px phrases floating in the top-right of the signature block, visually
	# identical to the "SIGNATURE" caption two inches to their left. This is the
	# exact case _make_secondary_action was written for (see its header): one
	# quiet, PERSISTENT document-tab frame, subordinate to TAKE THE FIELD but
	# plainly operable before hover. Tooltips because a toggle labelled with its
	# CURRENT state does not say what pressing it does.
	if not _doctrine_mastery_unlocked(hid):
		var alt: Dictionary = hero.get("deck_alt", {})
		var doctrine_name := String(alt.get("name", "Alternate")) \
			if _muster_alt_deck else "Standard Deck"
		var toggle := _make_secondary_action(doctrine_name, 0, 32)
		toggle.tooltip_text = "Switch this hero's starting deck."
		toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
		toggle.pressed.connect(_set_bound_doctrine.bind(hid, not _muster_alt_deck))
		row.add_child(toggle)
		return
	# "ALTERNATE", not "ALT". These two toggles are the only place in the shell
	# that abbreviated a word, and "ALT" beside "STANDARD" reads as a keyboard
	# modifier before it resolves as an adjective (COPY_STYLE §12: no riddles).
	#
	# The widths were 196 to hold the longer word without the FRAME resizing as
	# the label toggles. The tab has no frame to resize, and a fixed width there
	# just leaves ~50px of bare rule past each end of "STANDARD DECK" — so they
	# hug, like the other four secondaries.
	var deck_btn := _make_secondary_action(
		"ALTERNATE DECK" if _muster_alt_deck else "STANDARD DECK", 0, 32)
	deck_btn.tooltip_text = "Switch between this hero's two starting decks."
	deck_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	deck_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	deck_btn.pressed.connect(_toggle_muster_deck.bind(hid))
	row.add_child(deck_btn)
	var relic_btn := _make_secondary_action(
		"ALTERNATE RELIC" if _muster_alt_relic else "STANDARD RELIC", 0, 32)
	relic_btn.tooltip_text = "Switch between this hero's two signature relics."
	relic_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	relic_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	relic_btn.pressed.connect(_toggle_muster_relic.bind(hid))
	row.add_child(relic_btn)


func _toggle_muster_deck(hid: String) -> void:
	if hid != _selected_hero or not _doctrine_mastery_unlocked(hid):
		return
	_muster_alt_deck = not _muster_alt_deck
	_build_muster_roll(hid)


func _toggle_muster_relic(hid: String) -> void:
	if hid != _selected_hero or not _doctrine_mastery_unlocked(hid):
		return
	_muster_alt_relic = not _muster_alt_relic
	_build_muster_roll(hid)


## The footer tab's label, which is also the ONLY place a collapsed dialog can
## report itself. A modifier the player cannot see they enabled is the same
## defect as a modifier they cannot reach, so the summary rides the word that
## opens the dialog.
##
## One term per concept, written the same way: "Daily" was a clipped form of the
## button inside (DAILY RUN), and "custom seed" was the only lower-cased entry
## in a list of three.
func _run_options_tab_text() -> String:
	var active: Array[String] = []
	if _selected_ascension > 0:
		active.append("Ascension %d" % _selected_ascension)
	if _daily_pick:
		active.append("Daily Run")
	if _muster_seed_text.strip_edges() != "":
		active.append("Custom seed")
	if active.is_empty():
		return "RUN OPTIONS"
	return "RUN OPTIONS  ·  %s" % ", ".join(PackedStringArray(active))


func _refresh_run_options_tab() -> void:
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	var tab := menu.find_child("MusterRunOptions", true, false)
	if tab == null or not is_instance_valid(tab):
		return
	var btn := tab as Button
	if btn != null:
		btn.text = _run_options_tab_text()


## THE MARCH'S SESSION SETTINGS — difficulty, today's run, the seed.
##
## A DIALOG, NOT A DISCLOSURE (2026-09-16). This was an inline block that opened
## underneath the commit row and GREW the whole screen rect by 44px to hold
## itself, because the collapsed slack could not absorb three more rows and the
## overflow landed on START RUN — the one control the screen exists to reach.
## Paying permanent layout for a control almost no run uses is the wrong trade;
## a dialog costs nothing when it is shut.
##
## It is modal on purpose. Every control in here changes what START RUN commits,
## and two of them (Daily Run, the seed) contradict each other — settling them
## in one place, then closing, is what makes the footer summary true.
func _show_run_options() -> void:
	var return_focus := get_viewport().gui_get_focus_owner()
	_hide_run_options()
	_run_options_return_focus = return_focus
	_muster_advanced_open = true
	var overlay := Control.new()
	overlay.name = "RunOptions"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 520
	add_child(overlay)
	_run_options_overlay = overlay
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.008, 0.006, 0.008, 0.82)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			AudioBank.play_ui("back")
			_hide_run_options())
	overlay.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := GameTheme.make_panel_style(
		Color(0.035, 0.025, 0.03, 0.98), Color(0.72, 0.60, 0.36, 0.82),
		2, 6, false)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var title := _make_display_label("RUN OPTIONS", 26, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var lead := _make_display_label(
		"Optional. Leave them alone for an ordinary run.", 15,
		Color(0.76, 0.69, 0.56))
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(lead)

	# THE LADDER IS NOT DRAWN UNTIL IT HAS A RUNG. Below the first win, the
	# stepper was a permanently disabled "-" and "+" flanking the words
	# "Ascension 0 / 0" — three dead controls in a dialog a first-time player
	# may well open out of curiosity. Every roguelike surveyed either locks its
	# difficulty ladder behind a win (Slay the Spire needs a full three-act clear
	# before A1 exists; Balatro's stakes unlock per deck), defers it to a prompt
	# after run one, or keeps it in a different mode; not one presents an inert
	# difficulty control beside live offers.
	#
	# The promise still prints — _update_asc_rules_text writes "Win a run to
	# unlock Ascension levels" into the line below — so the ladder is announced
	# without being operable. The label stays null on this path and every
	# consumer already guards with is_instance_valid.
	var asc_unlocked: int = MetaState.unlocked_ascension
	if asc_unlocked > 0:
		var asc_row := HBoxContainer.new()
		asc_row.alignment = BoxContainer.ALIGNMENT_CENTER
		asc_row.add_theme_constant_override("separation", 12)
		content.add_child(asc_row)
		# _make_menu_button hardcodes EXPAND_FILL, so a plain HBox flings its
		# children across the full panel: the "-" lands against the left edge, a
		# hand's width from the number it decrements. Centring needs the children
		# to SHRINK, so every control below re-flags itself.
		var minus := _make_menu_button("-", Color(0.20, 0.16, 0.14), 17, 38)
		minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		minus.custom_minimum_size = Vector2(40, 38)
		minus.pressed.connect(_change_ascension.bind(-1))
		asc_row.add_child(minus)
		_asc_label = _make_display_label("Ascension %d / %d" % [
			_selected_ascension, asc_unlocked], 17, IVORY)
		_asc_label.custom_minimum_size = Vector2(190, 38)
		_asc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_asc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		asc_row.add_child(_asc_label)
		var plus := _make_menu_button("+", Color(0.20, 0.16, 0.14), 17, 38)
		plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plus.custom_minimum_size = Vector2(40, 38)
		plus.pressed.connect(_change_ascension.bind(1))
		asc_row.add_child(plus)

	_asc_rules_label = _make_display_label("", 15, Color(0.70, 0.64, 0.53))
	_asc_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_asc_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_asc_rules_label)
	_update_asc_rules_text()

	# Read the live toggle, not just the ledger: the dialog is rebuilt every time
	# it opens, and a button that reset itself to OFF while _daily_pick stayed
	# true would misreport which seed the run is about to commit.
	# A BLOCKED STATE NAMES THE CAUSE AND THE EFFECT (COPY_STYLE §12). Three of
	# these four labels are on a DISABLED button, and "DAILY RUN — WON" /
	# "— UNAVAILABLE" told the player a fact about the past without ever saying
	# why the control had stopped answering. "TODAY" is the whole cause (one
	# Daily Run per day) and the tooltip carries the effect in a sentence.
	var daily_text := "DAILY RUN — ON" if _daily_pick else "DAILY RUN — OFF"
	var daily_blocked := false
	var today_daily: Dictionary = MetaState.todays_daily()
	if not today_daily.is_empty():
		match String(today_daily.get("result", "")):
			"won":
				daily_text = "DAILY RUN — WON TODAY"
				daily_blocked = true
			"lost":
				daily_text = "DAILY RUN — LOST TODAY"
				daily_blocked = true
			_:
				daily_text = "CONTINUE DAILY RUN" \
					if _daily_resume_slot(today_daily) >= 0 \
					else "DAILY RUN — ALREADY STARTED"
				daily_blocked = _daily_resume_slot(today_daily) < 0
	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 12)
	content.add_child(seed_row)
	_daily_btn = _make_menu_button(daily_text, Color(0.30, 0.24, 0.34), 15, 38)
	_daily_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Measured from the label, not pinned: the blocked states are longer than the
	# ON/OFF pair the old 238 was cut for, and an overrunning label on this row
	# runs straight into the seed field beside it.
	_daily_btn.custom_minimum_size = Vector2(
		maxf(238.0, float(daily_text.length()) * 10.0 + 24.0), 38)
	_daily_btn.tooltip_text = _daily_tooltip()
	_daily_btn.disabled = daily_blocked
	_daily_btn.pressed.connect(_on_daily_button_pressed)
	seed_row.add_child(_daily_btn)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed (optional)"
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_edit.add_theme_font_size_override("font_size", 16)
	_seed_edit.add_theme_color_override("font_color", IVORY)
	_seed_edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.42))
	_seed_edit.custom_minimum_size = Vector2(200, 38)
	if GameTheme.font_display:
		_seed_edit.add_theme_font_override("font", GameTheme.font_display)
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.02, 0.015, 0.01, 0.85)
	well.border_color = Color(0.60, 0.51, 0.34, 0.75)
	well.set_border_width_all(1)
	well.set_corner_radius_all(3)
	well.content_margin_left = 8
	well.content_margin_right = 8
	_seed_edit.add_theme_stylebox_override("normal", well)
	var well_focus := well.duplicate() as StyleBoxFlat
	well_focus.border_color = GILT_BRIGHT
	_seed_edit.add_theme_stylebox_override("focus", well_focus)
	_seed_edit.text = _muster_seed_text
	_refresh_seed_field_state()
	_seed_edit.text_changed.connect(_on_muster_seed_changed)
	seed_row.add_child(_seed_edit)

	var done := _make_menu_button("DONE", Color(0.24, 0.18, 0.14), 18, 48)
	done.name = "RunOptionsDone"
	done.pressed.connect(_hide_run_options)
	content.add_child(done)
	done.call_deferred("grab_focus")


func _hide_run_options() -> void:
	var restore_focus := _run_options_return_focus
	_run_options_return_focus = null
	_muster_advanced_open = false
	if _run_options_overlay != null and is_instance_valid(_run_options_overlay):
		_run_options_overlay.queue_free()
	_run_options_overlay = null
	# The dialog OWNS these three references while it is up. Leaving them
	# pointing at freed nodes is survivable (every consumer guards) but the
	# guard then silently does nothing, which is how a seed typed into a closed
	# dialog stops reaching _refresh_seed_field_state.
	_asc_label = null
	_asc_rules_label = null
	_daily_btn = null
	_seed_edit = null
	_refresh_run_options_tab()
	if restore_focus != null and is_instance_valid(restore_focus):
		restore_focus.call_deferred("grab_focus")


## The seed field's live state, in ONE place so the build path and the Daily Run
## toggle cannot drift apart.
##
## A BLOCKED CONTROL NAMES ITS CAUSE (COPY_STYLE §12). Turning Daily Run on
## greys this field out and stops it accepting text, and nothing anywhere said
## why — a dimmed box beside a lit one is the shape of a bug, not of a rule. The
## tooltip is the only channel a LineEdit has, so it carries the cause and the
## effect while the field is shut.
func _refresh_seed_field_state() -> void:
	if _seed_edit == null or not is_instance_valid(_seed_edit):
		return
	_seed_edit.editable = not _daily_pick
	_seed_edit.modulate = Color(1, 1, 1, 0.45 if _daily_pick else 1.0)
	_seed_edit.tooltip_text = (
		"Seed locked: a Daily Run always uses today's seed. Turn Daily Run off to type your own."
		if _daily_pick else WritDB.muster_copy("seed_tooltip_text"))


## Kept under its old name because the shot harness drives it by name: it is
## the one control on this screen whose open and closed states are both worth a
## frame.
func _toggle_muster_advanced() -> void:
	if _run_options_overlay != null and is_instance_valid(_run_options_overlay):
		_hide_run_options()
	else:
		_show_run_options()


## THE STARTING BONUS IS ITS OWN BEAT, AFTER THE COMMIT (2026-09-16).
##
## It was the fourth thing on the run-setup screen: four 340px tiles under a
## roster, a hero dossier and six banner chips. Wrong place, for a reason that
## has nothing to do with crowding — it is a choice ABOUT THE RUN, not about the
## BUILD, and standing it beside the roster asked the player to weigh a term
## against a lord they had not finished choosing. Slay the Spire, the stated
## model, takes the character pick first and then opens the run on Neow's favour.
##
## So START RUN now lands HERE. The seed is settled, the lord is settled, the
## four tiles have the whole page, and they are the only interactive thing on
## it — which is what earns them the size they could never have in a shared row.
##
## THE TILE IS THE COMMIT. There is no second button. A dedicated screen whose
## tiles are its only controls does not need one, and the run-setup footer
## already spent the page's one big commit; a second would read as a wizard's
## Next. BACK returns to the roster with every pick intact and nothing spent.
func _show_starting_bonus() -> void:
	_set_subscreen_motion_obscured(true)
	_hide_run_options()
	_hide_deck_inspector()
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_muster_step = 3
	_hide_deck_preview()
	_clear_menu_column_now(menu)
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_writ_buttons.clear()
	_hero_detail = null
	_muster_writ_row = null
	_muster_campaign_label = null
	_muster_gloss_label = null
	_muster_order_term_detail = null

	# Same 1540 rect run setup uses, so the page the player just left and the
	# page they arrive on are the same object at the same size — only its
	# contents change. Shorter, because this screen holds one row: 560 centred in
	# 900 gives the tiles a band to sit in rather than 400px of bare canvas under
	# the deepest thing on the page.
	# 640, and the block is composed rather than stretched. A screen carrying one
	# decision IS sparse — and that is fine; what is not fine is sparse content
	# pinned to the top of a tall rect with a hole under it. The rect is sized to
	# what the screen holds so the space left over is MARGIN, distributed evenly
	# around a centred block, which is the whole difference between negative
	# space and dead space.
	# THE SAME PAGE WIDTH AS RUN SETUP (2026-09-17). These two screens are seen
	# back to back, one press apart, and they were 1540 and 1560 — close enough
	# to look like a mistake rather than a change. 712 tall, up from 640: the
	# block was filling roughly two thirds of the canvas with the remainder
	# pooled under BACK, which is the hole-versus-margin distinction again.
	_center_menu_for_subscreen(MUSTER_PAGE_W, BONUS_PAGE_H)
	_lift_menu_block(BONUS_BLOCK_LIFT)
	menu.add_theme_constant_override("separation", 10)
	var title := _make_display_label(
		WritDB.muster_copy("terms_head_text"), 31, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# NAMED so the measurement tools can dump this screen's regions from the real
	# node rects instead of hand-typed coordinates — see _shot_bonus._dump_regions.
	# A region list entered by eye rots the first time a row moves.
	title.name = "BonusTitle"
	menu.add_child(title)
	# THE SCREEN HAS A SUBJECT (2026-09-16). Without the lord on it this page was
	# a title and four boxes on a dark field, with no connection to the screen it
	# came from and nothing for the eye to land on before the decision. He is the
	# reason there IS a favour, so he stands at the head of it: a small plate,
	# lit the same way as the one on run setup, with what he brings beside it.
	menu.add_child(_make_bonus_hero_strip())
	# (The lead line used to stand here as its own centred band. It is a sentence
	# about the lord — the favour is HIS — so it moved into his strip, which is
	# also where the height came from that BONUS_BLOCK_LIFT spends.)
	#
	# ── THE SLACK GOES BELOW THE ROW, NOT ABOVE IT (2026-09-18) ──
	#
	# The column carries 113px of slack between its two spacers, and it used to
	# split 1:2 — 37px pushing the writs DOWN and 76 holding them up. The writs
	# carry 82% of this page's optical weight, so those 37px are spent moving the
	# one thing on the screen that needs to be near the middle away from it.
	#
	# At ratio 0 the whole 113 goes to the spacer under the row, which raises the
	# row by 37px WITHOUT moving the title — the distinction that matters, since
	# the title's clearance from the canvas frame is what bounds
	# BONUS_BLOCK_LIFT. Translating the block buys balance and costs top margin;
	# this buys balance and costs neither.
	_muster_slack(menu, 1)

	# The pick-ONE rule as a caption over the row, in the same small-caps-over-a-
	# hairline uniform every section on the setup screen wears. No tile states
	# that rule, so it cannot simply be dropped.
	var terms := _make_muster_section(menu,
		WritDB.muster_copy("terms_step_desc_text"), MUSTER_STRIP_WIDTH_FULL, true)
	terms.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_muster_writ_row = HBoxContainer.new()
	_muster_writ_row.custom_minimum_size = Vector2(0, TERM_TILE_H)
	_muster_writ_row.add_theme_constant_override("separation", 18)
	_muster_writ_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terms.add_child(_muster_writ_row)

	# The gloss belongs TO the row it defines, and on its left edge — parented
	# into the section so it sits on the caption's own margin, and dimmer than
	# the tiles, because a definition is footnote weight beside the four offers
	# it footnotes.
	_muster_gloss_label = _make_caption_label("", 15, Color(0.62, 0.57, 0.48))
	_muster_gloss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_muster_gloss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_muster_gloss_label.name = "BonusGloss"
	terms.add_child(_muster_gloss_label)

	# NO TILE OPENS SEALED. _refresh_muster_deals keeps _selected_writ_id pointed
	# at a real entry so the commit can never resolve nothing — but on a screen
	# where pressing a tile IS the commit, painting one of them as already chosen
	# would say the choice had been made for you. The seal is reserved for the
	# press (see _refresh_muster_writ_styles, which stamps it on the transition).
	_bonus_screen_open = true
	_bonus_pick_made = false
	_refresh_muster_deals()
	# Staged AFTER the column is populated: it needs Menu's child index to sit
	# under it (see _set_bonus_table).
	_set_bonus_table(true)

	_muster_slack(menu, 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(row)
	var back := _make_menu_button("BACK", Color(0.22, 0.16, 0.14), 17, 46, false)
	back.name = "BonusBack"
	back.custom_minimum_size = Vector2(180, MUSTER_NAV_ROW_H)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_leave_starting_bonus)
	row.add_child(back)
	# The BONUS page's own promise — see WritDB's `bonus_subtitle_text`. The
	# `subtitle` names Start Run, which this screen does not have and which the
	# player pressed to arrive here.
	var promise := _make_display_label(
		WritDB.muster_copy("bonus_subtitle_text"), 15, Color(0.80, 0.75, 0.65))
	promise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	promise.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promise.custom_minimum_size = Vector2(0, MUSTER_NAV_PROMISE_H)
	row.add_child(promise)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(180, 0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tail)

	_animate_subscreen_reveal(menu)
	var first: Variant = null
	for id in _muster_writ_buttons:
		first = _muster_writ_buttons[id]
		break
	if first != null and is_instance_valid(first):
		(first as Control).call_deferred("grab_focus")


## TRANSLATE the centred column up by `px`, without resizing it.
##
## ── WHY THIS IS NOT JUST A TALLER RECT (2026-09-18, measured) ──
##
## The starting bonus measured **bal-H 0.141** against a shell range of
## 0.43-1.00 and quadrants 6.6/5.8/43.8/43.7 — 88% of the page's optical weight
## in the bottom half. The cause was single and specific: the writ row carries
## 82% of that weight and its centre sat **117px below the canvas midline**.
##
## FOUR SWEEPS, three of them negative, and the negatives are the useful part:
##   plate 158->360px   bal-H 0.142 -> 0.056, equilibrium 0.875 -> 0.738.
##                      Growing the HEADER pushes the row further down; the
##                      displacement costs more than the new mass gains.
##   tile 172->290px    bal-H 0.142 -> 0.158 and density 43% -> 46%. Growing the
##                      row keeps it on the same side of the line, and density is
##                      the punished direction.
##   table alpha 1->0.12  bal-H 0.142 -> 0.172. The background was never the
##                      problem; that reading came from overlapping regions.
##   BLOCK LIFT 0->120  bal-H 0.142 -> **0.838**, equilibrium 0.875 -> 0.995,
##                      quadrants 27.5/26.9/22.9/22.7. This is the lever.
##
## And a TALLER RECT cannot substitute, which is worth recording because it is
## the obvious thing to reach for: `_center_menu_for_subscreen`'s own height
## dial swept 640->880 only reached bal-H 0.242, because once the rect exceeds
## the content the `_muster_slack` spacers stop being pinned and EXPAND — the
## block spreads apart (footer 769 -> 889) instead of moving. Translation and
## expansion are different operations and only one of them fixes this.
##
## The lift is bounded by the title hitting the canvas frame, which is why the
## lead line had to move into the lord's strip first: that freed the height this
## spends.
func _lift_menu_block(px: float) -> void:
	if px == 0.0:
		return
	var menu := get_node_or_null("Menu") as Control
	if menu == null:
		return
	menu.offset_top -= px
	menu.offset_bottom -= px



## THE LORD, AT THE HEAD OF HIS OWN FAVOUR.
##
## A centred row: a 118×158 plate lit exactly like the big one on run setup
## (pool, edge burn, standing sheen), his name, and the two numbers the tiles
## below are priced against — the deck a Forge term would touch and the max HP a
## PACT would charge. Not decoration: THE PACT says "Lose 6 max HP" and without
## the denominator beside it, 6 is a number with no scale.
##
## The plate is built here rather than borrowed from _build_muster_roll because
## that one is 282 wide and lives inside a two-column pane; what they share is
## the MATERIAL, which is the part that has to match, and that lives in Sheen.
func _make_bonus_hero_strip() -> Control:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	wrap.add_child(row)
	var hid := _selected_hero if HeroDB.has_hero(_selected_hero) \
		else HeroDB.HERO_ORDER[0]
	var hero := HeroDB.get_hero(hid)
	var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
	if ResourceLoader.exists(portrait_path):
		var plate := Control.new()
		plate.name = "BonusHeroPlate"
		plate.custom_minimum_size = BONUS_PLATE_SIZE
		plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var clip := Control.new()
		clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(clip)
		var face := TextureRect.new()
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.texture = load(portrait_path)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(face)
		# LIGHTER THAN THE BIG PLATE, and the reason is scale rather than taste:
		# the burn is a fraction of the half-diagonal, so the same strength on a
		# 118px plate eats proportionally far more of the subject than on a 282px
		# one. Measured on the Kindler, whose painting is the darkest of the five
		# — at 0.72 his face was inside the burn.
		Sheen.vignette(clip, 0.52, 0.55, 0.64)
		# Same molding as the full pane's plate, scaled to a 118px tile — the
		# width has to come down with the plate or the frame eats the lord.
		_faction_frame(plate, hid, {
			"corner": "mitre", "rule_w": 4.6, "rebate": 2.4,
			"drop": 1.8, "shimmer": 0.30, "cornsweet": 2.4})
		Sheen.plinth(plate, _faction_accent(hid).lerp(
			Color(1.0, 0.56, 0.22), 0.55), 96.0, 0.26)
		Sheen.sheen(plate, GILT_BRIGHT, 0.28)
		row.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var name_label := _make_display_label(
		String(hero.get("name", hid)), 27, _faction_accent(hid))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(name_label)
	var opener: Array[String] = RunState.opening_deck_for(hid, _muster_alt_deck)
	var stat := _make_caption_label("%d cards  ·  %d max HP" % [
		opener.size(), RunState.STARTING_MAX_HP], 16, Color(0.80, 0.73, 0.60))
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(stat)
	# ── THE LEAD LINE JOINS THE LORD (2026-09-18) ──
	#
	# It used to be a third centred band stacked under this strip, and it is a
	# sentence ABOUT him — the favour is his. Beside him it costs the page nothing;
	# under him it cost a band plus two gaps, and this screen measured 117px of
	# its heavy row sitting below the canvas midline with no height to give back.
	#
	# Measured: bal-H 0.142 with the row where it was, 0.617-0.838 with the block
	# translated up, and the translation is only legal if the block gets shorter
	# first — see BONUS_BLOCK_LIFT.
	var lede := _make_caption_label(
		WritDB.muster_copy("terms_screen_desc_text"), 15,
		Color(0.72, 0.66, 0.55))
	lede.name = "BonusLead"
	lede.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.custom_minimum_size = Vector2(432, 0)
	col.add_child(lede)
	return wrap


## ── THE SHEETS LIE ON A TABLE (2026-09-17) ──
##
## This screen's own header has called itself a signing table since it was built,
## and there was no table on it: four sheets of paper floating on a dark field
## with nothing under them. That is the second half of the flatness diagnosis —
## the ink census says this page has no HOLE in it (94% of its rows carry ink),
## so no amount of moving boxes was ever going to answer "it feels empty". What
## it had was surfaces with no depth cue, and the cheapest real cue is to put the
## objects ON something.
##
## FULL-BLEED ACROSS THE LOWER PAGE, which is the shape `StageTable` is built
## for: its edges melt into the scene by its own vignette, so the far edge reads
## as a horizon with the fire still burning above it. A BAND behind the row was
## tried first and is worth recording as the wrong answer — that painter sizes
## its lamplight pool and its vignette ring as fractions of its WIDTH, correct on
## the roughly square stage the minigames deal on and wildly out of scale on a
## 1516x202 strip (the outer pool comes out a 1180x730 ellipse on a 202px band).
## Clipping it fixed the spill and left 15px of visible bleed that was entirely
## the painter's own 16px edge strip, i.e. a table you could not see.
##
## `clip_contents` is still needed here for the same spill reason, and it is a
## real scissor rect on gl_compatibility unlike `CanvasItem.clip_children`.
##
## ONE OWNER. The table is a SIBLING of the Menu column (a Container lays out
## every Control child it has, so a backdrop parented into the column would be
## dealt a slot in the stack and shove the layout), which means nothing frees it
## automatically on the way out. `_rebuild_menu` sweeps every sibling but
## Background/Atmosphere and `_clear_for_picker` sweeps all but those plus
## MenuScrim, so the two exits that matter are covered — but BACK lands on run
## setup via `_show_muster_step`, which only clears the column's children. Hence
## this one function, called with `false` from there.
func _set_bonus_table(on: bool) -> void:
	var old := get_node_or_null("BonusTable")
	if old != null:
		remove_child(old)
		old.queue_free()
	if not on:
		return
	var menu := get_node_or_null("Menu")
	var host := Control.new()
	host.name = "BonusTable"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = true
	host.anchor_left = 0.0
	host.anchor_right = 1.0
	host.anchor_top = BONUS_TABLE_TOP
	host.anchor_bottom = 1.0
	add_child(host)
	# Under the column, over the scrim. The scrim is what seats the page's text
	# against the fire art, and a table drawn beneath it would be dimmed by the
	# very gradient that exists to dim the painting.
	if menu != null:
		move_child(host, menu.get_index())

	# ── THE TABLE IS CANVAS-SIZED AND SHOWN FROM THE WAIST DOWN ──
	#
	# Every feature `StageTable` draws is a fraction of its own WIDTH: the
	# lamplight pool runs to 0.39w and the vignette ring to 0.47w, both squashed
	# in y by a constant. On a 1.78:1 plane that is a pool in the middle of a
	# table; on the 3.17:1 strip this band actually is, the same fractions
	# overflow the height and the whole surface becomes pool — measured, the first
	# render came out a flat tan wash with no wood left in it.
	#
	# So the painter is given the aspect it was authored for (the full canvas) and
	# the band is a WINDOW onto it, which needs no change to a file ten minigames
	# share. The NEGATIVE top anchor is what places it: anchors may sit outside
	# [0,1], so `-T/(1-T)` puts the plane's own top edge exactly on the canvas's
	# top edge whatever the canvas is — the arithmetic stays right under UI Scale,
	# where a pixel offset would not (class C32).
	var table := StageTable.new()
	table.seed_text = "writ-signing-table"
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.anchor_left = 0.0
	table.anchor_right = 1.0
	table.anchor_top = -BONUS_TABLE_TOP / maxf(1.0 - BONUS_TABLE_TOP, 0.01)
	table.anchor_bottom = 1.0
	host.add_child(table)

	# ── THE HORIZON ──
	#
	# The window's own top edge is a hard straight line across the full width, and
	# the wood sits several stops above the scrimmed fire behind it, so the first
	# render had a visible seam reading as the top of a UI panel — the one thing
	# this whole pass is trying to take off the screen. The table's own edge melt
	# cannot help: it is at the PLANE's top edge, which is up behind the lord.
	#
	# A vertical ramp in the page's own warm black, opaque at the seam and clear
	# by the time the sheets start. Physically it is also the right answer rather
	# than a patch: a surface receding away from a single lamp goes dark at its
	# far reach, so the horizon is where the table runs out of light.
	var haze := TextureRect.new()
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.stretch_mode = TextureRect.STRETCH_SCALE
	haze.anchor_left = 0.0
	haze.anchor_right = 1.0
	haze.anchor_top = 0.0
	haze.anchor_bottom = 0.34
	var hg := Gradient.new()
	hg.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	hg.colors = PackedColorArray([
		Color(0.035, 0.018, 0.008, 1.0),
		Color(0.035, 0.018, 0.008, 0.62),
		Color(0.035, 0.018, 0.008, 0.0)])
	var ht := GradientTexture2D.new()
	ht.gradient = hg
	ht.fill_from = Vector2(0, 0)
	ht.fill_to = Vector2(0, 1)
	ht.width = 8
	ht.height = 256
	haze.texture = ht
	host.add_child(haze)

	if not _reduce_motion():
		host.modulate.a = 0.0
		var tw := host.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(host, "modulate:a", 1.0, 0.45)


## BACK off the bonus screen is not BACK off run setup: the lord, the doctrine
## toggles and the seed all survive, so it rebuilds the roster from the live
## state rather than abandoning the whole setup.
func _leave_starting_bonus() -> void:
	_bonus_screen_open = false
	_run_commit_locked = false
	_show_muster_step(1)


## ── THE TERMS ARE WRITS, AND THE SCREEN IS A SIGNING TABLE (2026-09-16) ──
##
## These were dark rounded rectangles with gilt text: four wash-filled boxes on
## a wash-filled page, told apart only by a 1px border on whichever one was
## selected. The owner's reading of the finished screen was that it is "basically
## nothing", and that was accurate about the MATERIAL, not the copy — every term
## was already written, priced and previewed; there was simply no object on the
## page for the eye to believe in.
##
## The game already owns the right object and had been drawing it on every card
## in the deck since v9. A term IS a document: WritDB deals them, the copy calls
## them terms, the accepted one takes a WAX SEAL, and the house card is literally
## an "illuminated writ". So the tile stops being a UI panel and becomes the
## thing it is describing — a cut sheet of parchment on the war table, ink on
## paper, and you press your seal into one of them.
##
## FOUR PAINTERS, ALL ALREADY IN THE KIT, none of them new work:
##   WritLeaf        the cut sheet: a seeded deckled silhouette with its contour
##                   and edge toast drawn along the SAME wobbled path. A
##                   mathematically perfect corner is the one thing real cut
##                   paper never has, and four identical rounded rects is what
##                   made this row read as a form.
##   ParchmentPlate  the aging INSIDE the sheet: mottled sizing, foxing, fibers.
##                   Seeded per term, so no two sheets on the table are twins.
##   InkCartouche    the swallowtail band the slot label sits in.
##   WaxSeal         the mark of acceptance, which was already here and is the
##                   one element of the old tile that survives unchanged.
##
## THE VALUE RULE INVERTS ON THIS TILE AND EVERY COLOUR HAD TO MOVE WITH IT.
## Value is decided by the LOCAL ground: gilt on warm-black is the shell's
## register, and the same gilt on parchment is invisible. So the body is INK, the
## emphasis is the re-inked gold the card faces use (#7a4f10, not the tooltip's
## #e8b547, which washes out on paper), and the pact's warning is a rubric red
## rather than the shell's ember. This is the third time this codebase has paid
## for that rule; it is cheap to remember and expensive to rediscover.
##
## NO SPECULAR HERE, deliberately. The portrait plates next to it wear a
## standing sheen because they are lit metal and glass; paper is not specular,
## and a highlight crawling across a sheet would read as a rendering bug. What
## the sheets get instead is the CANDLE: a warm pool under the one you are
## touching, which is what light on a table actually does.
func _make_muster_writ_tile(entry: Dictionary) -> Button:
	var id := String(entry.get("id", ""))
	var slot := String(entry.get("slot", ""))
	var is_pact := bool(entry.get("is_pact", false))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(TERM_TILE_W, TERM_TILE_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = String(entry.get("desc", ""))
	# The PAPER is the face. Every button state is empty so nothing draws a box
	# behind the sheet — a StyleBox under a deckled leaf puts a perfect rectangle
	# behind an irregular one, which is worse than either alone.
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	# The candle pool, under the sheet and off until it is wanted. Named so
	# _refresh_muster_writ_styles can find it without holding a reference across
	# a rebuild.
	var glow := Sheen.plinth(btn, Color(1.0, 0.62, 0.26), 54.0, 0.34)
	if glow != null:
		glow.name = "WritGlow"
		glow.visible = false

	var leaf := WritLeaf.new()
	leaf.name = "WritPaper"
	leaf.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaf.seed_text = "writ-%s" % id
	# The pact's sheet is older and dirtier than its three free neighbours. It is
	# the one term that charges you, and the paper says so before the words do.
	leaf.paper = Color(0.836, 0.760, 0.626) if is_pact \
		else Color(0.879, 0.822, 0.704)
	leaf.toast = Color(0.318, 0.198, 0.096) if is_pact \
		else Color(0.298, 0.208, 0.110)
	leaf.toast_strength = 1.25 if is_pact else 0.95
	leaf.corner_radius = 7.0
	# ── THE SHEET IS AN OBJECT, NOT AN OUTLINE (2026-09-17) ──
	#
	# These are the first consumers of WritLeaf's lit cross-section. The tile used
	# to wear NINE concentric flat strokes: the leaf's own contour plus its four
	# toast rings, and then FOUR MORE from a transparent-background
	# `ChartPanelStyle` nine pixels in (its contour seam, a 10px "edge toast"
	# band, a metal halo and the crisp rule) — with no fill to cover their inner
	# halves, so every one of them read as a separate hairline. That is the
	# lightning-bolt stack and the picture-frame stroke under a third name.
	#
	# Worse than flat: the panel kit's scorch band is `Color(0.02, 0.012, 0.006)`
	# at half alpha, tuned to sear a DARK plate. Over cream paper a black band at
	# half alpha is a dead neutral GREY, which is why the rim photographed as a
	# bevelled 90s groove rather than as a burnt edge. And the kit's silhouette is
	# a chamfered OCTAGON while the sheet is a deckled rounded rect, so each
	# corner carried a straight 45-degree cut sitting inside a torn paper one.
	#
	# All of it is gone. The sheet's own edge does the whole job: a lit wall on the
	# runs facing the lamp, a stained one on the runs facing away, and a contact
	# shadow onto the table underneath.
	leaf.edge_profile = true
	leaf.edge_w = 7.0
	leaf.lamp = 1.0
	leaf.drop = 3.2
	btn.add_child(leaf)
	var age := ParchmentPlate.new()
	age.name = "WritAge"
	age.set_anchors_preset(Control.PRESET_FULL_RECT)
	# KEEP OFF THE EDGE. Card2D insets this painter by 3px, which is right there
	# because the leaf's flat rings are 1px of contour; here the sheet's lit
	# cross-section owns the outer 8px, and `ParchmentPlate` carries a near-white
	# `lift` wash that was landing straight on top of it. Measured: the shadowed
	# bottom run read 0.83 against a page at 0.77 — brighter than the paper it
	# is supposed to be a shadow on — and the inversion fell to 0.25 because the
	# ageing was repainting the very thing being measured.
	age.offset_left = 9
	age.offset_top = 9
	age.offset_right = -9
	age.offset_bottom = -9
	age.seed_text = "writ-age-%s" % id
	age.strength = 1.20 if is_pact else 0.92
	btn.add_child(age)
	# THE CLERK'S RULE — a hairline box just inside the deckle, the way a ruled
	# document is laid out before anything is written on it. Ink, not gold: a gold
	# keyline on paper is a certificate, and these are field paperwork.
	#
	# It is a plain `StyleBoxFlat` now rather than the panel kit's
	# `make_panel_style`, and the swap is the whole point of this pass. That
	# helper returns a `ChartPanelStyle`, which draws the FURNITURE assembly —
	# contour seam, scorch band, metal halo, crisp rule, corner tacks, chamfered
	# corners — and every one of those is right on a dark plate and wrong on a
	# sheet of paper. A ruled line is the ONE mark on this tile that should be
	# machine-straight and single: the deckle was torn by hand, but the clerk drew
	# this with a straightedge. So: one line, square corners, no assembly.
	var rule := Panel.new()
	rule.name = "WritRule"
	rule.set_anchors_preset(Control.PRESET_FULL_RECT)
	rule.offset_left = 11
	rule.offset_top = 11
	rule.offset_right = -11
	rule.offset_bottom = -11
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_box := StyleBoxFlat.new()
	rule_box.bg_color = Color(0, 0, 0, 0)
	rule_box.draw_center = false
	rule_box.set_border_width_all(1)
	rule_box.border_color = Color(0.302, 0.224, 0.141, 0.42)
	rule_box.set_corner_radius_all(0)
	rule.add_theme_stylebox_override("panel", rule_box)
	btn.add_child(rule)

	var copy := VBoxContainer.new()
	copy.set_anchors_preset(Control.PRESET_FULL_RECT)
	copy.offset_left = 22
	copy.offset_right = -22
	copy.offset_top = 16
	copy.offset_bottom = -16
	copy.add_theme_constant_override("separation", 4)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(copy)

	# THE SLOT BAND. The label used to be a bare caption; on paper it is the
	# document's own heading, and InkCartouche is the swallowtail band the cards
	# print their names in. Same furniture, same screen, one vocabulary.
	var band := Control.new()
	band.custom_minimum_size = Vector2(0, 26)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(band)
	var cart := InkCartouche.new()
	cart.set_anchors_preset(Control.PRESET_FULL_RECT)
	cart.ink = Color(0.208, 0.145, 0.086, 0.92) if not is_pact \
		else Color(0.278, 0.086, 0.071, 0.94)
	band.add_child(cart)
	var slot_label := _make_caption_label("%s — %s" % [
		String(WritDB.SLOT_LABELS.get(slot, "")),
		String(WritDB.SLOT_HINTS.get(slot, ""))], 15,
		Color(1.0, 0.86, 0.62) if not is_pact else Color(1.0, 0.76, 0.66))
	slot_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(slot_label)

	# ── THE ACCEPTED TERM IS SEALED, NOT LABELLED (2026-08-05, kept) ──
	# The one element of the old tile that needed no rework: a wax seal was
	# always the right object, it was simply pressed into a dark panel instead of
	# into paper.
	#
	# IT MOVED TO THE SIGNATURE LINE (2026-09-17), and it fixes a collision the
	# old placement had all along. Pinned 14px down from the sheet's top-right
	# corner it landed squarely ON the slot cartouche — the swallowtail band runs
	# y 16..42 and the 30px mark ran y 14..44 — so the accepted term wore its
	# numeral over its own heading. A top-corner mark is a STAMP; this screen's
	# copy is about signing from end to end ("SIGN TO BEGIN" on every sheet,
	# "Nothing is spent until you sign one." beneath the row), and what goes on a
	# signature line is a SEAL. So it is pressed onto the start of that line,
	# which is also what gives the line something to receive.
	#
	# ANCHORED to the sheet's bottom-left rather than positioned: `fit_tile_height`
	# grows the two tiles whose body wraps, and a mark placed from a constant
	# would sit 20-30px up the page on exactly those two.
	#
	# The word is KEPT as the seal's tooltip and accessible name: a mark nobody
	# can read is a worse affordance than a label, and the copy-lint / text-floor
	# gates are entitled to find the string.
	var chosen_marker := Control.new()
	chosen_marker.name = "TermChosenMarker"
	chosen_marker.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chosen_marker.offset_left = 20.0
	chosen_marker.offset_right = 20.0 + float(TERM_SEAL)
	chosen_marker.offset_top = -float(TERM_SEAL) - 10.0
	chosen_marker.offset_bottom = -10.0
	chosen_marker.tooltip_text = "Your chosen bonus."
	chosen_marker.visible = false
	var seal := WaxSeal.new()
	seal.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The PACT prices itself in max HP; it seals in the same crimson its own band
	# already warns in, so the mark inherits the term's argument instead of
	# contradicting it in gilt.
	seal.wax = Color(0.62, 0.15, 0.12) if is_pact else Color(0.54, 0.13, 0.10)
	seal.seed_text = "term-%s" % String(entry.get("id", slot))
	chosen_marker.add_child(seal)
	# THE SEAL BEARS A DEVICE. WaxSeal draws an IMPRESSION — a sunk dark face
	# with a lit far wall — because on a card that recess holds the stat numeral.
	# Pressed with nothing in it the recess reads as a hole and the mark as a
	# washer. The slots are numbered in Roman on their own bands, so the seal
	# bears the numeral of the term it closed; THE PACT, which deliberately
	# carries no numeral, takes the house diamond.
	var device := Label.new()
	device.text = "◆" if is_pact \
		else String(WritDB.SLOT_LABELS.get(slot, "")).split(" ")[0]
	device.set_anchors_preset(Control.PRESET_FULL_RECT)
	device.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	device.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	device.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		device.add_theme_font_override("font", GameTheme.font_display)
	device.add_theme_font_size_override("font_size", 15)
	device.add_theme_color_override("font_color", Color(1.0, 0.90, 0.76, 0.94))
	chosen_marker.add_child(device)
	btn.add_child(chosen_marker)

	# THE TERM'S NAME, written on the sheet. Ink, not ivory: see the value note
	# in the header. Cinzel at 25 is the document's own hand.
	# 26, NOT 29. At 29 "The Quartermaster's Arsenal" measured ~424px against a
	# ~416px inner sheet, wrapped to two lines, and pushed SIGN TO BEGIN out
	# through the bottom of the paper onto the table. The sheet's height and its
	# type have to grow together and the LONGEST TERM NAME is what caps the type
	# — not the average one, and not the one the seed happened to deal.
	var name_label := _make_display_label(String(entry.get("name", "")), 26,
		Color(0.153, 0.106, 0.063))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(name_label)
	# NO EXPAND_FILL ON THE DESC (2026-08-04, kept). It carried it, so the
	# description absorbed the tile's slack and drove the relic preview onto the
	# floor — a ~50px gap between "Choose 1 of 3 relics." and the three names,
	# which then read as an unlabelled list rather than as that sentence's
	# answer. The question and its answer are adjacent; slack goes to a spacer
	# AFTER the last written line, where empty space is margin.
	var desc := _make_display_label(String(entry.get("desc", "")), 16,
		Color(0.271, 0.196, 0.129))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(desc)
	# THE ARSENAL used to be the one BLIND tile standing beside three transparent
	# ones: "Choose 1 of 3 relics" named no pool, no rarity and no examples, and
	# the plates were not drawn until after the commit. So the player was asked to
	# weigh a known deck surgery against three unnamed relics — not a comparison,
	# a coin flip. The roll is a pure static off a stream derived from a seed that
	# is already fixed at this point, so the answer can simply be shown; naming
	# them here cannot change what _pick_blessing later deals.
	var offer := _writ_arsenal_preview(entry)
	if not offer.is_empty():
		var names: Array[String] = []
		var rules: Array[String] = []
		for rid in offer:
			var relic: Dictionary = RelicDB.get_relic(rid)
			names.append(String(relic.get("name", rid)))
			rules.append("%s — %s" % [relic.get("name", rid), relic.get("desc", "")])
		# THE RE-INKED GOLD (#7a4f10), the same one Card2D uses for keywords on a
		# card face. The tooltip gold washes out on paper; this reads as gilding
		# on a document, which is what it is.
		var offer_label := _make_caption_label(" · ".join(names), 15,
			Color(0.478, 0.310, 0.063))
		offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(offer_label)
		btn.tooltip_text = "\n".join(rules)
	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(tail)
	# ── THE SIGNATURE LINE (2026-09-17) ──
	#
	# The foot of every sheet was ~50px of bare paper with one small right-aligned
	# caption floating in it. On a screen whose whole argument is that these are
	# DOCUMENTS that was the one place the fiction went quiet: a form's dead
	# bottom third is the space a signature block occupies, and this tile's own
	# copy asks for a signature twice over — "SIGN TO BEGIN" on every sheet and
	# "Nothing is spent until you sign one." under the row.
	#
	# So the caption gets the rule it was always describing, and the empty band
	# becomes the place the mark goes. Not decoration for a hole: it is the
	# affordance, and it is what the wax seal comes down ONTO when the term is
	# accepted. The rule is drawn rather than styled — a ruled line is a line, and
	# a Panel with one border would draw the other three sides as well.
	var sign_row := HBoxContainer.new()
	sign_row.add_theme_constant_override("separation", 12)
	sign_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(sign_row)
	var sign_rule := SignatureRule.new()
	sign_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sign_rule.size_flags_vertical = Control.SIZE_SHRINK_END
	sign_rule.custom_minimum_size = Vector2(0, 16)
	sign_rule.ink = Color(0.302, 0.224, 0.141, 0.66)
	sign_rule.seed_text = "writ-sign-%s" % id
	sign_row.add_child(sign_rule)
	# The clerk's line, at the foot of every sheet: what a signed term binds. It
	# is the same sentence on all four, so it is document furniture rather than
	# copy that differentiates — printed small, in the same ink as the rule.
	var foot := _make_caption_label("SIGN TO BEGIN", 14,
		Color(0.353, 0.271, 0.184))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.size_flags_vertical = Control.SIZE_SHRINK_END
	sign_row.add_child(foot)
	# GROW THE SHEET TO ITS OWN TEXT (2026-09-17). TERM_TILE_H is a MINIMUM, but
	# the tile skeleton's inner VBox is anchored FULL_RECT, so the Button's min
	# size never grows with content — and an autowrap Label reports a useless
	# minimum height until layout has settled its width. On the two tiles whose
	# body wraps to a second line AND whose ARSENAL preview wraps its relic list,
	# the stack ran past 172 and "SIGN TO BEGIN" printed straight through the
	# bottom border, landing on the gloss line underneath. Same defect, same fix,
	# as the shop's clipped price line — measure the stack at the known wrap width
	# and grow the button. Called AFTER the last child is parented, because it
	# measures what is actually in the column.
	GameTheme.fit_tile_height(btn, copy)

	btn.pressed.connect(_select_muster_writ.bind(id))
	# THE SHEET ANSWERS THE HAND. A document on a table lifts when you touch it
	# and the candle finds it; both halves are wired here rather than in the
	# screen builder so a tile is complete wherever it is dealt.
	btn.mouse_entered.connect(_light_writ.bind(btn, true))
	btn.mouse_exited.connect(_light_writ.bind(btn, false))
	btn.focus_entered.connect(_light_writ.bind(btn, true))
	btn.focus_exited.connect(_light_writ.bind(btn, false))
	# A term is ACCEPTED, not browsed — it is the one pick on the walk that binds
	# the whole run. It sounds like one.
	_arm_shell_button(btn, "commit")
	return btn


## The candle finding a sheet. Informational half (the lift, which says "this is
## the one under your hand") is a scale tween the kit already gates; the glow is
## decorative and simply fades.
func _light_writ(btn: Control, lit: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var glow := btn.get_node_or_null("WritGlow")
	if glow != null and is_instance_valid(glow):
		var g := glow as Control
		g.visible = true
		var tw := g.create_tween()
		tw.tween_property(g, "modulate:a", 1.0 if lit else 0.0, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _reduce_motion():
		return
	btn.pivot_offset = btn.size * 0.5
	var lift := btn.create_tween()
	lift.tween_property(btn, "scale", Vector2.ONE * (1.022 if lit else 1.0),
		0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The three relics THE ARSENAL will actually offer, resolved BEFORE commit.
##
## Reproducing the resolution roll rather than caching it is deliberate: caching
## would mean two sources of truth for the same three ids, and the one that is
## wrong would be the one printed on a screen that promises nothing is final.
## Three things have to match _pick_blessing's call exactly — the stream seed,
## the hero, and the relics already held, which at that moment is the signature
## alone (start_new_run clears `relics` and appends only it).
func _writ_arsenal_preview(entry: Dictionary) -> Array[String]:
	if String(entry.get("effect", "")) != "arsenal":
		return []
	if not HeroDB.has_hero(_selected_hero):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _pending_run_seed() ^ 0x57524954 ^ 0x5245534F
	var held: Array[String] = []
	var signature := _muster_signature_relic(_selected_hero)
	if signature != "":
		held.append(signature)
	return RelicDB.roll_foundation_relics(
		int(entry.get("value", 3)), held, _selected_hero, rng)


## The relic this lord will ACTUALLY march with, given the doctrine toggles and
## what the profile has authorised. One writer, because two readers now need the
## same answer: the commit, and THE ARSENAL's pre-commit preview — and a preview
## that resolves the signature differently would name three relics the picker
## then does not offer. RunState re-applies the identical gates in start_new_run,
## so this can only ever be a faithful mirror or a bug.
func _muster_signature_relic(hero_id: String) -> String:
	var hero_data := HeroDB.get_hero(hero_id)
	var alt := String(hero_data.get("relic_alt", ""))
	var use_alt := false
	if _bound_doctrine_unlocked(hero_id):
		if _doctrine_mastery_unlocked(hero_id):
			use_alt = _muster_alt_relic
		elif _muster_alt_relic and _muster_alt_deck:
			use_alt = true
	return alt if use_alt and alt != "" else String(hero_data.get("relic", ""))


## Accept a term. On the bonus screen this IS the commit: the seal comes down on
## the tile that was pressed, and the run begins behind it.
##
## The seal is awaited rather than fired-and-forgotten. _refresh_muster_writ_styles
## stamps it on the TRANSITION into chosen, so committing on the same frame would
## start the fade with the stamp still travelling and the player would never see
## which tile they took — the one piece of feedback the whole screen exists to
## give. _run_commit_locked is what keeps a second tile from being pressed inside
## that window.
func _select_muster_writ(id: String) -> void:
	if not _muster_writ_buttons.has(id):
		return
	if _bonus_screen_open and _run_commit_locked:
		return
	_selected_writ_id = id
	_refresh_muster_writ_styles()
	if not _bonus_screen_open:
		return
	if _selected_hero == "":
		return
	_run_commit_locked = true
	_bonus_pick_made = true
	_refresh_muster_writ_styles()
	if UserSettings == null or not UserSettings.reduce_motion:
		await get_tree().create_timer(0.42).timeout
	if not is_inside_tree():
		return
	_bonus_screen_open = false
	_begin_run_with(_selected_hero)


func _refresh_muster_writ_styles() -> void:
	for id in _muster_writ_buttons:
		var btn: Button = _muster_writ_buttons[id]
		if not is_instance_valid(btn):
			continue
		# THE BONUS SCREEN OPENS WITH NOTHING CHOSEN, and that is not the same as
		# nothing SELECTED. _refresh_muster_deals keeps _selected_writ_id pointed
		# at a real entry so the commit can never resolve nothing """ + M + """ but on a
		# screen where pressing a tile IS the commit, painting one of them sealed
		# says the choice was made for you. (The first cut of this screen shipped
		# exactly that: tile I opened wearing the wax.)
		var selected := String(id) == _selected_writ_id \
			and (not _bonus_screen_open or _bonus_pick_made)
		# ── NOTHING TO RESTYLE: THE TILE IS PAPER (2026-09-16) ──
		#
		# This function used to swap four StyleBoxes per tile """ + M + """ a fill and a
		# border for each of normal/pressed/hover/focus """ + M + """ because the tile WAS a
		# StyleBox. It is a WritLeaf now, and the button's own states are all
		# StyleBoxEmpty, so the selected state is expressed in the sheet's own
		# material instead: the seal comes down, the candle stays on it, and the
		# paper lifts a hair. A panel style added back here would draw a perfect
		# rectangle behind a deckled sheet, which is the one thing the painter
		# exists to avoid.
		var glow := btn.get_node_or_null("WritGlow")
		if glow != null and is_instance_valid(glow):
			var g := glow as Control
			g.visible = selected
			g.modulate.a = 1.0 if selected else 0.0
		if not _reduce_motion():
			btn.pivot_offset = btn.size * 0.5
			btn.scale = Vector2.ONE * (1.022 if selected else 1.0)
		# The marker is a WaxSeal host, not a Label """ + M + """ `as Label` would silently
		# yield null here and the accepted term would carry no mark at all.
		var marker := btn.find_child("TermChosenMarker", true, false) as Control
		if marker != null:
			var was_visible: bool = marker.visible
			marker.visible = selected
			# PRESS IT, don't pop it. A seal that appears on frame 1 reads as a
			# badge toggling; a seal that comes down under the stamp reads as an
			# act. Only on the TRANSITION into chosen """ + M + """ repainting the row
			# (which happens on every deal refresh) must not re-stamp a term the
			# player accepted several seconds ago.
			if selected and not was_visible and not _reduce_motion():
				marker.pivot_offset = marker.size * 0.5
				marker.scale = Vector2(1.9, 1.9)
				marker.modulate.a = 0.0
				marker.rotation = -0.42
				var tw := marker.create_tween().set_parallel(true)
				tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(marker, "scale", Vector2.ONE, 0.17)
				tw.tween_property(marker, "rotation", 0.0, 0.17)
				tw.tween_property(marker, "modulate:a", 1.0, 0.10)
				# THE SHEET TAKES THE BLOW. A seal is PRESSED into paper: the
				# stamp lands, the document flinches under it, and the impact kit
				# already owns that grammar (see Motion.impact_frame / the
				# writ_amend five-stage note). Without the recoil the wax simply
				# materialises, which is the badge-toggle read this comment warns
				# about one paragraph up.
				Motion.impact_frame(btn, btn, Vector2(1.012, 0.972),
					Color(1.0, 0.94, 0.84, 0.55))
				Motion.shock_rings(btn, marker.global_position
					+ marker.size * 0.5, Color(0.86, 0.32, 0.22), 0.7)
			elif selected:
				marker.scale = Vector2.ONE
				marker.rotation = 0.0
				marker.modulate.a = 1.0


func _refresh_muster_deals() -> void:
	# Deals the slate as DATA first and paints it only if the row is on screen.
	# _begin_run_with resolves the committed term out of _muster_writ_slate, so
	# the roll cannot be conditional on the terms step having been built — an
	# early-out here used to be safe when there was one screen and is not now.
	var rng := RandomNumberGenerator.new()
	rng.seed = _pending_run_seed() ^ 0x57524954
	_muster_writ_slate = WritDB.roll_slate(rng)
	# Forge is valuable only after the player has learned what a card does in
	# combat. A brand-new profile may still open Customize, but its first slate
	# cannot ask for a permanent card upgrade before that lesson exists.
	if MetaState.total_runs <= 0:
		# THE LOOP MUST RE-DEAL, not just re-read. It used to test the SAME slate 64
		# times and then fall through with the forge still on it, so the guard was
		# inert: THE ROLL has four entries, one of which is the Whetstone Cart (and
		# its pact is a second forge tile), so roughly a quarter of all first-ever
		# musters opened by asking a player who has never seen a card in combat to
		# pick a permanent card upgrade. Re-rolling off the SAME rng keeps the deal
		# deterministic — a given seed still produces one fixed slate.
		for _attempt in range(64):
			var has_forge := false
			for entry in _muster_writ_slate:
				if String(entry.get("effect", "")) == "forge":
					has_forge = true
					break
			if not has_forge:
				break
			_muster_writ_slate = WritDB.roll_slate(rng)
	var still_present := false
	for entry in _muster_writ_slate:
		if String(entry.get("id", "")) == _selected_writ_id:
			still_present = true
	if not still_present:
		_selected_writ_id = String(_muster_writ_slate[0].get("id", "")) \
			if not _muster_writ_slate.is_empty() else ""
	if _muster_gloss_label != null and is_instance_valid(_muster_gloss_label):
		_muster_gloss_label.text = WritDB.gloss_for_slate(_muster_writ_slate)
	if _muster_writ_row == null or not is_instance_valid(_muster_writ_row):
		return
	for child in _muster_writ_row.get_children():
		child.queue_free()
	_muster_writ_buttons.clear()
	for entry in _muster_writ_slate:
		var tile := _make_muster_writ_tile(entry)
		_muster_writ_row.add_child(tile)
		_muster_writ_buttons[String(entry.get("id", ""))] = tile
	_refresh_muster_writ_styles()


func _pending_run_seed() -> int:
	if _daily_pick:
		return RunState.daily_seed()
	var typed := _muster_seed_text.strip_edges().to_lower()
	if typed != "":
		return RunState.seed_from_string(typed)
	return _muster_random_seed


func _refresh_muster_campaign() -> void:
	if _muster_campaign_label == null or not is_instance_valid(_muster_campaign_label) \
			or _selected_hero == "":
		return
	var seed_value := _pending_run_seed()
	var tribes: Array = RunState.preview_season_tribes(seed_value)
	var deal: Dictionary = RunState.preview_rival_deal(_selected_hero, seed_value)
	var rival_names: Array[String] = []
	for hid in deal.get("rival_lords", []):
		rival_names.append(String(HeroDB.get_hero(String(hid)).get("name", hid)))
	var final_id := String(deal.get("finale_rival", ""))
	var final_name := String(HeroDB.get_hero(final_id).get("name", final_id)) \
		if final_id != "" else "unknown"
	_muster_campaign_label.text = "%s\nRival lords: %s. Final boss: %s." % [
		RunState.season_line_for(tribes),
		" · ".join(PackedStringArray(rival_names)), final_name]


## Debounce token — see _on_muster_seed_changed.
var _seed_deal_token: int = 0

func _on_muster_seed_changed(new_text: String) -> void:
	if _daily_pick:
		return
	_muster_seed_text = new_text
	# The campaign line is derived text, not a deal — it can follow every letter.
	_refresh_muster_campaign()
	# THE DEAL IS DEBOUNCED, and that is a correctness fix rather than a
	# performance one. _refresh_muster_deals re-rolls the whole writ slate off
	# _pending_run_seed(), and when the player's chosen term is not in the new
	# deal it silently reassigns _selected_writ_id to slate[0]. Fired on
	# text_changed, typing a seven-character seed re-dealt SEVEN times and could
	# quietly swap a term the player had already chosen for a different one —
	# on the screen whose standing promise is "Nothing is final until you take
	# the field", which the player reasonably reads as "nothing changes without
	# me". Let the field settle, then deal once.
	_seed_deal_token += 1
	var token: int = _seed_deal_token
	await get_tree().create_timer(0.35).timeout
	# Superseded by a later keystroke, or the player left the step / the screen.
	if token != _seed_deal_token or not is_inside_tree():
		return
	# The seed field lives in the run-options dialog, which is a screen EARLIER
	# than the row it re-deals, so there is nothing to repaint here and no step
	# to check: _refresh_muster_deals updates the slate as DATA and paints only
	# if _muster_writ_row happens to be alive. The bonus screen reads the settled
	# slate when it opens, and _on_take_field_pressed flushes any deal still in
	# flight on the way there.
	_refresh_muster_deals()


func _abandon_muster() -> void:
	_hide_deck_inspector()
	_hide_run_options()
	_quick_march_active = false
	_bonus_screen_open = false
	RunState.pending_signature_relic = ""
	RunState.pending_deck_variant = ""
	_muster_setup_preset.clear()
	_selected_writ_id = ""
	_muster_seed_text = ""
	_muster_step = 1
	_muster_writ_slate.clear()
	_rebuild_menu()


func _update_asc_rules_text() -> void:
	if _asc_rules_label == null or not is_instance_valid(_asc_rules_label):
		return
	if _selected_ascension <= 0:
		if MetaState.unlocked_ascension <= 0:
			# Nothing unlocked yet: name the ladder so it is a promise rather than
			# an absence. One line — the footer has no slack.
			#
			# "Take a keep" was wrong. MetaState.record_victory is what raises
			# unlocked_ascension, and that fires on WINNING THE MARCH — taking act
			# one's keep unlocks nothing, so the old line pointed a new player at
			# the wrong milestone in undefined vocabulary.
			_asc_rules_label.text = "No added rules yet. Win a run to unlock Ascension levels."
		else:
			_asc_rules_label.text = "Ascension 0 — no added rules."
		return
	# ONE LINE, ALWAYS. This used to print one rule per unlocked tier, so the
	# readout grew ~23px per Ascension — a VARIABLE-height element inside step
	# III's fixed height budget, on the step that already had the least slack.
	# At A3+ it pushed BACK and TAKE THE FIELD off the bottom of the 900px
	# canvas: the commit control of the entire run opening, unreachable, and
	# only for the players who had earned the most.
	#
	# Trimming neighbours could not fix that — anything saved is a ONE-TIME
	# gain against something that keeps growing. The height has to become
	# constant, so the stack collapses to a count and the rules move to the
	# hover. The stepper beside it is a difficulty CHOICE, not a contract to
	# read line by line, and every other block on this screen already states
	# itself in one line.
	var lines: Array[String] = []
	for tier in range(1, _selected_ascension + 1):
		if tier < RunState.ASCENSION_RULES.size():
			lines.append(RunState.ASCENSION_RULES[tier])
	if lines.is_empty():
		_asc_rules_label.text = "Ascension 0 — no added rules."
		return
	# Both halves of the plural agree. At Ascension 1 this used to read "1 added
	# rule in force. Hover to read them." — the pronoun disagreeing with the count
	# in the same sentence.
	var one := lines.size() == 1
	_asc_rules_label.text = "Ascension %d — %d added rule%s in force. Hover to read %s." \
		% [_selected_ascension, lines.size(), "" if one else "s",
			"it" if one else "them"]
	_asc_rules_label.tooltip_text = "\n".join(lines)
	_asc_rules_label.mouse_filter = Control.MOUSE_FILTER_STOP


## The kingdom's political dye, lifted to a legible-on-dark ink (keeps its hue,
## gains brightness) — used for the focused hero's nameplate accents so each
## lord reads in their faction's colour without leaving the sepia world.
## Raise a colour to a TARGET relative luminance, keeping its hue.
##
## `Color.lightened(a)` is `c + (1 - c) * a` per channel, so it moves luminance
## by roughly `(1 - lum) * a` — passing `target - lum` as the amount lands short
## of the target, and the shortfall grows the darker the colour is. Two menu
## call sites were doing exactly that and both were silently missing their
## floor. Solving `lum + (1 - lum) * a = target` for `a` is the whole fix.
func _lift_to_luminance(c: Color, target: float) -> Color:
	var lum := c.get_luminance()
	if lum >= target or lum >= 1.0:
		return c
	return c.lightened((target - lum) / (1.0 - lum))


## The lord's colour, WARMED AND LIFTED for use as ink (2026-08-03).
##
## The source is HeroDB's faction colour, and that field is documented as a
## "banner/political-wash tint for map skinning" — a flat dye laid under a sepia
## parchment plate, where a teal (grasswake 0.33/0.50/0.55) or a slate blue
## (lanternhall 0.52/0.60/0.78) is doing its job. Used raw as TEXT on the fire it
## does the opposite: the old lerp toward IVORY only desaturated it, so Raider's
## 30px nameplate — the largest word on the hero screen — rendered as a cold
## grey-green sitting on an ember background, the single coldest thing on any
## menu. The house note on the art pass names pervasive cyan/teal as the #1
## defect; this is where the menus were still importing it.
##
## Lerping toward GILT_BRIGHT instead keeps the five lords distinguishable (they
## stay olive / bronze / green-gold / pale gold / ember, in that order) while
## putting every one of them inside the fire's palette, and the value floor stops
## the darkest faction from printing dim.
## A 0.42 lerp DOES NOT CONVERT A TEAL, and 0.46 is not a floor for ink (audit,
## 2026-08-03). Grasswake is (0.33, 0.50, 0.55); at 42% toward gilt it lands on
## (0.611, 0.647, 0.508) — green still dominant, i.e. a sage, which is what
## Raider's 30px nameplate actually rendered as (measured (156,165,130) on the
## frame: an exact match, so the arithmetic here IS what ships). And a 0.46
## luminance floor put every accent heading ~30% DIMMER than the ivory paragraph
## underneath it, so on Quick March the largest text in the pane was also the
## faintest, and the "recommended" badge beside it outranked the hero's name.
##
## Two changes. A cold source (green or blue at or above red) is lerped much
## harder, because half-warming a cold dye just desaturates it. And the floor
## goes to 0.80, which is above DESC_DIM (0.74) — the ink the paragraphs under
## these headings now use — so the heading wins its own pane. The dyes stay
## distinguishable: everflame ember, owed bronze, last_wall bone, grasswake
## warm-olive, lanternhall pale gold.
##
## THAT LAST SENTENCE IS TRUE OF INK AND FALSE OF A MOULDING (2026-09-18). See
## `FACTION_METAL` below. This function is tuned for a WORD ON FIRE, and the
## luminance lift that makes it legible is precisely what a metal cannot
## survive. Do not hand it to `PlateFrame`.
func _faction_accent(hid: String) -> Color:
	var fac := HeroDB.faction_info(HeroDB.get_faction(hid))
	if fac.is_empty():
		return GILT
	var c: Color = fac.get("color", GILT)
	var toward_gilt := 0.62 if (c.g >= c.r or c.b >= c.r) else 0.42
	return _lift_to_luminance(c.lerp(GILT_BRIGHT, toward_gilt), 0.80)


## THE LORD'S COLOUR AS A METAL — what a picture frame is cast from, as opposed
## to what a word is written in (2026-09-18).
##
## THE DEFECT. Five `PlateFrame` call sites on RUN SETUP were handed
## `_faction_accent(hid)` so each kingdom's frames would carry its colour. That
## signal was DEAD. Measured through the real chain — `HeroDB.FACTIONS[x].color`
## -> `_faction_accent` -> `PlateFrame.body_colour` — the five frame bodies came
## out at hue 35.0, 37.5, 37.7, 38.7 and 38.9: a 3.9 DEGREE SPREAD across a teal,
## a slate blue, an olive, a stone grey and an ember. Five frames, one colour.
##
## WHY, AND IT IS TWO COMPOUNDING CAUSES WITH ONE OF THEM DOMINANT.
##
##   1. THIS FUNCTION, AND IT IS THE BIG ONE. It ends in `_lift_to_luminance(
##      ..., 0.80)`, which is right for its own job and fatal for this one: by
##      the time an accent leaves here the five inputs are already crushed to
##      hue 27.6-53.4 at saturation 0.21-0.33 — a 26 degree spread of
##      near-neutral creams, out of an input spread of over 200 degrees. The
##      frame never had a signal to lose.
##   2. `PlateFrame.alloy_mix` at 0.78, which pulls what little survives the
##      rest of the way to the bronze. Real, but secondary — it is finishing
##      off a colour this function had already flattened.
##
## WHY NOT SIMPLY LOWER `alloy_mix`. Measured: even at `alloy_mix` 0.0 — i.e.
## deleting that file's "a frame is made of something" rule outright — the
## spread only reaches 25.8 degrees, and the body saturation falls to 0.21-0.33,
## which is the BONE its header was written to prevent ("a warm colour at S 0.3
## is a warm GREY"). That trade buys a little hue with the whole material. An
## HSV saturation floor is not available either: it was tried, and it amplifies
## whatever hue arrives — here a yellow-green — and produced a CHARTREUSE
## plate. Both are recorded in `PlateFrame`'s own header.
##
## WHAT WORKS IS THE FIX THE CARD SIDE ALREADY SHIPPED, and it says so out loud.
## `Card2D.chart_fillet_cfg`: "0.78 would pull rare gold, silver-blue, pewter
## and bone into one bronze and flatten a gameplay cue. The card's metals are
## already deliberate, separated alloys — UNLIKE THE SHELL'S NEAR-NEUTRAL
## FACTION ACCENTS." That comment is an acknowledgement of this bug, written
## from the other side of it. The card hands its moulding five real metals at
## `alloy_mix` 0.12 and its separation holds. The shell now does the same.
##
## THESE FIVE ARE NOT NEW ART DIRECTION. They are the materials the header just
## above ALREADY PROMISES — "everflame ember, owed bronze, last_wall bone,
## grasswake warm-olive, lanternhall pale gold" — authored as alloys instead of
## as lifted ink, so the promise finally renders. Two departures from that list,
## both forced by measurement rather than taste:
##
##   * `last_wall` is IRON, not bone. As a warm bone it landed 5 degrees from
##     `lanternhall`'s pale gold and was the worst-separated pair on the screen.
##     Stone is cool and the Last Wall is the legion, so iron moves it
##     decisively off gold. It is kept slightly warm rather than a pure
##     blue-grey because the house art note names pervasive cyan/teal as the #1
##     defect — the same note `_faction_accent` above cites.
##   * `grasswake` is a verdigris olive. That is where its teal legitimately
##     goes: verdigris is what bronze DOES, so the kingdom keeps a cool identity
##     without the shell importing a cyan.
##
## Values are authored DARK and inside a narrow band. `body_drop` sinks them
## anyway, and RUN SETUP shows four of these at once — one frame noticeably
## dimmer than its neighbours reads as a rendering fault, not as a kingdom.
##
## MEASURED, and in the two places that answer different questions.
##
##   * As `PlateFrame.body_colour` arithmetic — the metal itself, before the
##     moulding is lit: hue spread 43.5 degrees against 3.9 before, worst-pair
##     OKLab 0.0327 against 0.0006. That is the honest measure of THESE FIVE
##     COLOURS, and it is a 54x separation.
##   * As RENDERED PIXELS on the shipped roster, which is the figure that
##     counts: 27.6 degrees at worst-pair OKLab 0.0146, reading olive 52.5 /
##     stone 39.5 / bronze 35.6 / gold 41.1 / ember 24.9. Lower than the
##     arithmetic because the crest is lerped toward the cream `lit` and the
##     outer edge antialiases into the page — every metal gets washed the same
##     way, so the ORDER and the identities survive intact.
##
## Quote the second number, not the first, when asking whether a player can see
## this. `tools/_probe_frame_molding.gd` check 10 gates the rendered figure, so
## it cannot collapse again in silence — which is how it got here the first
## time, in a comment that recorded the defect and asserted nothing.
const FACTION_METAL := {
	"grasswake": Color(0.56, 0.64, 0.34),    # verdigris — corroded bronze
	"last_wall": Color(0.62, 0.63, 0.62),    # iron — stone, kept off the blue axis
	"owed": Color(0.76, 0.50, 0.17),         # bronze — the furnace altar, the ledger
	"lanternhall": Color(0.88, 0.73, 0.33),  # mirror-gold — the burning mirrors
	"everflame": Color(0.86, 0.33, 0.14),    # ember copper — the liquid fire
}

## Any faction with no authored metal. `PlateFrame`-ish bronze rather than GILT,
## because this value is a BODY and GILT is ink.
const FACTION_METAL_FALLBACK := Color(0.72, 0.60, 0.36)

## How far a faction metal is pulled toward `PlateFrame.alloy`.
##
## NOT the shell default of 0.78, and not the card's 0.12 either. A card shows
## its five fillets one at a time; RUN SETUP shows four frames at once and wants
## them to look like one workshop's output, so it spends more on cohesion. At
## 0.30 the five separate by 43.5 degrees as colours and 27.6 as rendered
## pixels, and every body clears the warm-grey line except `last_wall` — which
## is SUPPOSED to be grey. It is the stone one.
##
## Raising this is the cheapest way to undo the whole change: at the shell
## default of 0.78 the five land back inside 4 degrees of each other.
const FACTION_ALLOY_MIX := 0.30


## The frame config for a faction. STATIC so the gate can read the shipped
## values instead of restating them — see `_probe_frame_molding` check 8 for why
## a gate holding its own copy of the parameters is the exact failure that file
## exists to prevent.
static func faction_frame_cfg(faction_id: String) -> Dictionary:
	return {
		"metal": FACTION_METAL.get(faction_id, FACTION_METAL_FALLBACK),
		"alloy_mix": FACTION_ALLOY_MIX,
	}


## ONE FUNNEL for every faction picture frame on this screen. Four call sites
## each spelling `"alloy_mix": 0.30` is four chances to drift apart; it is also
## why, when a shared gate goes red and ownership is in question, this feature
## can be stubbed out at a single point to prove whether it is the cause.
func _faction_frame(parent: Control, hid: String, opts: Dictionary) -> Control:
	var cfg := faction_frame_cfg(HeroDB.get_faction(hid))
	for k in opts:
		cfg[k] = opts[k]
	var m: Color = cfg["metal"]
	return PlateFrame.over(parent, m, cfg)


## THE COMMIT — the largest instance of the shell's one forward-action shape.
##
## This was frameless, and until 2026-08-05 that was consistent: every forward
## move in the muster was a frameless word. Now steps I-III each carry a plated
## primary tab, so leaving the LAST step frameless taught the player one shape
## three times and then changed it on the one press that matters. It keeps
## everything that made it the climax — 27px Cinzel against the tabs' 19, two
## flames instead of one, its own underline — and puts them on the same plate,
## so the walk reads as one escalating gesture rather than four designs.
## START RUN's plate. `engrave` is OFF for the same structural reason as
## `_make_primary_action`'s: this button's word is not `Button.text` but a Label
## in a VBox beside two flames, so the stylebox cannot know where to strike. It
## gets the engine-placed strike instead (`GameTheme.engrave_label`, on `lbl`
## below), which is the exact half of that pair.
const CTA_PLAQUE := {"tacks": true, "rule_width": 6.0, "chamfer": 11.0,
	"engrave": false}


func _make_begin_button() -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.clip_contents = false
	## THIS IS THE BUTTON THE WHOLE SCREEN POINTS AT, AND IT IS HAND-ROLLED
	## (2026-09-17). Converting `make_primary_button` and `_make_primary_action`
	## to `PlaqueStyle` left START RUN itself untouched, because it is a FOURTH
	## spelling of a plated button living down here with its own styleboxes — so
	## the first in-situ shot of RUN SETUP came back with every other plate
	## rebuilt and the loudest one still flat.
	##
	## That is the exact finding the press-feedback pass recorded in this file's
	## neighbourhood: the four `make_*_button` factories cover ~87 call sites
	## against 92 bare `Button.new()`s, so a factory-side change delivers half a
	## surface, and the missing half is invisible because a button that did not
	## change still looks like a button. Worth remembering before assuming any
	## button treatment here is global.
	##
	## 56px tall, so it can carry tacks and the widest molding in the shell.
	## ── NO PLATE (2026-09-18, owner's call). THE BUTTON WAS ALREADY THERE.
	##
	## This control carries two lit flames, a 238px gilt rule and 27px Cinzel. It
	## did not need a background and never did: the plate was competing with its
	## own contents, and once rebuilt as struck metal it became the single
	## brightest object on RUN SETUP — a screen where the hero plate, the relic
	## chip and every panel are a dark field under a thin gold rule. The owner's
	## instruction was to hide it, which is also the standing preference on file
	## ("no panel/fill; the text IS the button").
	##
	## What signals "press me" here is what always did: the flames burning before
	## you arrive, and the rule under the word. Both already brighten on hover.
	var cta_rest := StyleBoxEmpty.new()
	cta_rest.content_margin_left = 22
	cta_rest.content_margin_right = 22
	cta_rest.content_margin_top = 6
	cta_rest.content_margin_bottom = 6
	for which in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(which, cta_rest)

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

	var lbl := _make_display_label("START RUN", 27, GILT_BRIGHT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	# 5 -> 3, so the strike below is not swallowed by an even halo. A symmetric
	# outline is the one part of a letter that says nothing about where the light
	# is; this word sits on a plate we drew, so it does not need five pixels of
	# it. See `GameTheme.engrave_label`.
	lbl.add_theme_constant_override("outline_size", 3)
	# THE WORD STANDS PROUD OF THE PLATE. Engine-placed, because the word lives
	# in a Label and a Label has a real shadow item — exact by construction,
	# where the stylebox route would have to re-derive this HBox's arithmetic.
	GameTheme.engrave_label(lbl)
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

	# LIT AT REST (2026-08-05). Both flames used to start invisible and ignite on
	# hover — the same tell every other item in the column gives. But this is the
	# button that spends the next forty minutes, and on a cold render it was
	# indistinguishable from the BACK beside it. The commit burns before you
	# reach it; hover takes it the rest of the way to full.
	var flames: Array[TextureRect] = [flame_l, flame_r]
	for f in flames:
		f.modulate = Color(1, 1, 1, TAKE_FIELD_FLAME_REST)
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
			tw.tween_property(f, "modulate:a", TAKE_FIELD_FLAME_REST, 0.18)
		tw.tween_property(rule, "modulate:a", 0.7, 0.18)
		tw.tween_property(inner, "position:x", 0.0, 0.18))
	btn.focus_entered.connect(func() -> void: btn.mouse_entered.emit())
	btn.focus_exited.connect(func() -> void: btn.mouse_exited.emit())
	btn.pressed.connect(_on_take_field_pressed.bind(btn))
	_arm_shell_button(btn, "commit", 1.03)
	return btn


## START RUN does not start the run: it settles the seed and opens the starting
## bonus, which is the beat that commits. Nothing on the setup screen is spent
## here, so BACK off the bonus screen costs the player nothing.
func _on_take_field_pressed(btn: Control) -> void:
	if _run_commit_locked or _selected_hero == "":
		return
	_run_commit_locked = true
	# FLUSH ANY DEBOUNCED SEED DEAL. _on_muster_seed_changed waits 0.35s before
	# re-rolling the slate, so a player who types a seed and immediately presses
	# START RUN would otherwise be shown a slate rolled from the PREVIOUS seed
	# while _pending_run_seed() reports the new one — the run and its opening
	# bonus disagreeing about which seed they came from. Cancelling the pending
	# deal and taking it HERE, one screen before the commit, is what makes the
	# four tiles on the next page the four tiles the seed actually deals.
	if _seed_deal_token > 0:
		_seed_deal_token += 1   # supersede the in-flight timer
		_refresh_muster_deals()
	GameTheme.claim_pop(btn)
	if UserSettings == null or not UserSettings.reduce_motion:
		await get_tree().create_timer(0.12).timeout
	if not is_inside_tree():
		return
	_run_commit_locked = false
	_show_starting_bonus()


# Cross-run muster picks (per focused hero; reset when the focus moves so a
# toggle can never leak onto another lord's run).
var _muster_alt_relic := false
var _muster_alt_deck := false


## The first victory unlocks one authored alternate doctrine: its deck package
## and signature relic travel together. Ascension 4 is mastery, where the two
## axes may finally be mixed independently.
func _bound_doctrine_unlocked(hid: String) -> bool:
	var hero: Dictionary = HeroDB.get_hero(hid)
	return MetaState.hero_wins(hid) >= 1 \
		and not (hero.get("deck_alt", {}) as Dictionary).is_empty() \
		and String(hero.get("relic_alt", "")) != ""


func _doctrine_mastery_unlocked(hid: String) -> bool:
	return _bound_doctrine_unlocked(hid) and MetaState.hero_best_asc(hid) >= 4


## Collapse stale or legacy one-axis picks back to Standard before mastery.
## After A4 both booleans remain independent and represent the four legal mixes.
func _normalize_muster_doctrine(hid: String) -> void:
	if not _bound_doctrine_unlocked(hid):
		_muster_alt_deck = false
		_muster_alt_relic = false
	elif not _doctrine_mastery_unlocked(hid):
		var bound_alt := _muster_alt_deck and _muster_alt_relic
		_muster_alt_deck = bound_alt
		_muster_alt_relic = bound_alt


func _set_bound_doctrine(hid: String, use_alt: bool) -> void:
	_muster_alt_deck = use_alt
	_muster_alt_relic = use_alt
	_build_muster_roll(hid)


# Portrait tints for the three states a roster row can be in. Named because
# _focus_hero and _preview_hero must agree on them exactly — a preview that
# restores to a slightly different resting value leaves a trail of half-lit
# lords behind the cursor.
const HERO_TINT_CHOSEN := Color(1.08, 1.04, 0.98)
const HERO_TINT_UNDER_CURSOR := Color(0.96, 0.93, 0.90)
const HERO_TINT_RESTING := Color(0.78, 0.76, 0.74)


## THE DELIBERATE ACT — this is where a lord is actually CHOSEN, and it is
## reachable only from `pressed` (a click, or Enter/A on the focused row).
##
## It used to be bound to `mouse_entered` as well, which made choosing a lord an
## accident of where the pointer happened to rest. BACK sits at x 0-180 directly
## beneath the roster column at x 0-430: moving the cursor from a top row down to
## BACK swept through every lord under it, selected each in turn, and left the
## run standing on whichever one the pointer crossed last. Worse, the two lines
## below wipe the doctrine toggles — so a returning player who had set ALT DECK,
## then reached for BACK, silently marched under STANDARD DECK with no toggle
## ever having been pressed. Hover now PREVIEWS (see _preview_hero); only a press
## commits.
##
## Spotlight one hero: brighten its portrait, dim the rest, light its gilt
## underline, and repaint the shared detail pane. Pane-only update — never
## rebuilds the cards (which would re-load() portrait textures and flicker).
## `keep_doctrine` is for the ONE caller that is not a change of lord: rebuilding
## step I onto the lord already chosen. Picking a DIFFERENT lord must clear the
## toggles (they name his predecessor's unlocks), but re-entering the step must
## not — so _build_muster_step_host used to save the pair, call this, restore
## them, and then call _build_muster_roll a SECOND time to repaint what the first
## call had just drawn wrong. That cost ten Card2D minis instantiated, freed and
## re-instantiated plus two bake passes on every entry to step I, including every
## back-navigation, on the screen whose whole job is to feel unhurried.
func _focus_hero(hid: String, keep_doctrine: bool = false) -> void:
	if _selected_hero == hid and _hero_detail != null and _hero_detail.get_child_count() > 0:
		return
	if not keep_doctrine:
		_muster_alt_relic = false
		_muster_alt_deck = false
	_selected_hero = hid
	for k in _hero_portraits:
		var p = _hero_portraits[k]
		if is_instance_valid(p):
			p.modulate = HERO_TINT_CHOSEN if k == hid else HERO_TINT_RESTING
	for k in _hero_cards:
		var b = _hero_cards[k]
		if is_instance_valid(b):
			var chosen: bool = k == hid
			var box: StyleBox = _hero_focus_box() if chosen else StyleBoxEmpty.new()
			b.add_theme_stylebox_override("normal", box)
			b.add_theme_stylebox_override("pressed", box)
			# Hover is no longer a COPY of the selection mark. The 3px gilt
			# underline means "this lord marches"; an unchosen row under the
			# cursor gets a bronze hairline instead, so the roster can never show
			# two rows wearing the same badge and let the player guess which one
			# the run is actually standing on.
			b.add_theme_stylebox_override("hover", box if chosen else _hero_hover_box())
			b.add_theme_stylebox_override("focus",
				_hero_selected_focus_box() if chosen else _hero_cursor_box())
	_build_muster_roll(hid)
	_refresh_muster_campaign()


## What hovering (or arrowing onto) a lord is allowed to do: lift his portrait
## out of the dim, and nothing else. No `_selected_hero` write, no doctrine
## reset, and deliberately NO detail-pane repaint — the pane is the record of
## what you have chosen, and a pane that follows the cursor would put a lord's
## deck on screen beside a run that is not his. `_warm_deck_strip` also stands
## its bake down the moment `_selected_hero != hid`, so a previewed strip would
## render half-baked anyway. Correctness over flourish.
func _preview_hero(hid: String, lit: bool) -> void:
	if hid == _selected_hero:
		return
	var port = _hero_portraits.get(hid)
	if port == null or not is_instance_valid(port):
		return
	# The unlit path asks the button whether it still holds keyboard focus, so
	# walking the roster with a controller and then moving the mouse away does
	# not dim the row the stick is standing on.
	var held := lit
	if not held:
		var btn = _hero_cards.get(hid)
		held = btn != null and is_instance_valid(btn) and btn.has_focus()
	port.modulate = HERO_TINT_UNDER_CURSOR if held else HERO_TINT_RESTING


## The hover mark: a bronze hairline at whisper volume, one third the weight of
## _hero_focus_box's gilt underline and with no glow. Same kit, clearly quieter —
## "you could pick this" against "this one marches".
func _hero_hover_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.045)
	sb.border_width_bottom = 1
	sb.border_color = Color(GILT.r, GILT.g, GILT.b, 0.38)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


## Keyboard/controller location. This must read without color and without moving
## selection: a bronze keyline says "A/Enter would choose this"; the selected
## hero keeps the heavier gilt underline from _hero_focus_box.
##
## AND IT WAS HEAVIER THAN THE SELECTION IT MUST NOT OUTRANK (2026-08-04). The
## old note claimed "one third the weight"; measured on a 406x66 roster row, in
## alpha-weighted pixels of ink:
##   selection  = 3px full-gilt underline (1218) + 0.07 wash (1876)      = 3094
##   cursor     = 0.075 wash (2010) + 7px of border at 0.82 (1215)
##                + shadow_size 4 at 0.14 (~4340)                        = 7565
## Two and a half times, and the term that dominates is the shadow — the same
## mechanism _hero_focus_box had to delete a day earlier for the same reason:
## `shadow_size` draws BEHIND a 93%-transparent box, so it reads straight through
## its own fill as a second, larger wash rather than as a glow.
##
## So the shadow goes here too, the wash drops to 0.03, the border becomes an
## even keyline with only the left edge thickened (the caret-in-the-margin
## idiom), and the bronze comes down to 0.62. That lands at ~1471 — 48% of the
## selection mark, which is the relationship the docstring always claimed.
func _hero_cursor_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.03)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(GILT.r, GILT.g, GILT.b, 0.62)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


## THE SELECTION MARK WAS A SOLID GOLD PLATE, AND THE CODE DID NOT SAY SO
## (2026-08-03). Reported symptom: the lord you have chosen is the hardest row on
## the screen to read. Measured on the render, selected row plate = rgb(151,127,69),
## luminance 0.50 — so its own gilt name sat at 2.85:1 and its tagline at 2.7:1,
## against 9.9–14.1:1 for the five rows the player did NOT pick. Selection was
## subtracting legibility. Step II's banner chips shared the box and the fault
## (2.28:1 on the chosen tribe's name, 2.05:1 on its rule).
##
## Nothing in this function looked capable of that — the wash is alpha 0.07. Two
## compounding causes, both invisible at the call site:
##   1. `shadow_size` on a StyleBoxFlat draws the glow BEHIND the box, and this
##      box is 93% transparent, so the shadow reads straight through its own
##      fill. At size 10 on a 66px row it covers the whole row: not a glow, a
##      second fill at alpha 0.28.
##   2. Godot draws the state box AND THEN the `focus` box over it. Both callers
##      hand the selected row this same box for `focus`, so the pair above is
##      composited TWICE.
## Hand-compositing 0.28-shadow + 0.07-fill, twice, over the pane's rgb(19,13,12)
## predicts rgb(149,125,69). The render measures rgb(151,127,69) — the whole
## discrepancy, to 2/255 on every channel.
##
## So the shadow goes. The wash and the 3px gilt underline are the selection
## mark, and a single 0.07 pass leaves the plate at luminance 0.11 and the name
## back at 5.6:1. `_hero_selected_focus_box` below keeps the second draw from
## putting the fill back.
func _hero_focus_box() -> StyleBoxFlat:
	# Frameless-friendly selection: a faint warm wash and a gilt underline — no
	# full rectangle border (the dev dislikes boxy tiles), and no shadow, which
	# on a translucent box is a fill by another name.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.07)
	sb.border_width_bottom = 3
	sb.border_color = GILT_BRIGHT
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


## What the SELECTED row wears in the `focus` slot: the underline alone. Godot
## composites `focus` on top of the state box, so handing it `_hero_focus_box`
## paints that box's wash a second time — which is half of why the plate above
## ran away. The underline is idempotent (it redraws over itself), the fill is
## not. Unselected rows are unaffected: they get `_hero_cursor_box`, whose whole
## job is to be visible against an EMPTY state box.
func _hero_selected_focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_bottom = 3
	sb.border_color = GILT_BRIGHT
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


# ── Deck strip (hero select): the opening ten as REAL cards ─────────────────
# 0.62, not the old 0.36. At 0.36 a 14px rules line renders at ~5px — well under
# the 14px hard floor in COPY_STYLE §11 — so the player could not actually READ
# the deck at the moment they were asked to commit to it. The strip is the
# subject of this screen; it has to be legible without a hover.
const DECK_MINI_SCALE := 0.62

## The second, slightly smaller size the muster strip falls back to when the
## pane forces the column into two ranks (see _make_muster_deck_strip).
##
## Not a guess — a budget. Two ranks cost the screen `2*300*s + 10` where one
## rank cost 202 (186 of card + 16 of scrollbar reserve), and step II is the
## binding case: its content already stands at 701px on a 900px canvas, because
## the banner step prints a rule line under the panes that step I does not.
## Above 0.58 the whole screen runs out of canvas — at 0.62 step II measures
## 881 and lands the title and the nav row within 9px of the screen edges. At
## 0.58 it measures 857 and keeps ~21px of air top and bottom.
##
## The cost is 6.5% off the card: the 18px rules line renders at 10.4px instead
## of 11.2px. That is a hairline against the alternative, which was three of the
## eleven cards not on screen at all.
const DECK_MINI_SCALE_RANKS := 0.58

## THE COLUMN's usable inner width, per step. Both are measured, not guessed.
##
## Steps I and II hang the deck beside the picker: the menu VBox is 1540, the
## picker frame is pinned at 430 (sized for the roster taglines, which ellipsised
## at 350 — see _build_muster_step_host), the row separation is 16, so the column
## frame gets 1094 and its 12px content margins leave 1070.
## Step III gives the column the whole menu: 1540 - the same 24 = 1516.
const MUSTER_STRIP_WIDTH_SPLIT := 1070.0
const MUSTER_STRIP_WIDTH_FULL := 1516.0
## Usable width of THE COLUMN pane on the single-screen muster: the main row's
## 1516 less the roster (430), the banner column (296), two 16px separations and
## the pane's own 24px of margin. The art strip divides this by however many
## DISTINCT cards the opener holds, so it stays one rank at any deck size.
## 550, not 710: the hero portrait takes 216 of THE COLUMN's width plus an 18px
## gutter, and the strip shares the remainder with the name and the pitch. The
## tiles pay for the portrait — 86×58 rather than 113×75 — which is the right
## trade here, because a tile is a REMINDER of a card the player can hover or
## open in full, while the portrait is the only picture of the hero on the page.
const OPENER_STRIP_WIDTH := 550.0
## The strip on RUN SETUP spans the WHOLE hero pane (1540 — the 430 roster — the
## row's 20 separation), because the deck sits under the portrait rather than
## beside it. Five tiles across at 8px separation is (1090-32)/5 = 211 wide and
## 141 tall at the art's own 3:2 — two ranks, the whole opener, and the biggest
## thing on the page after the lord himself.
## 1090 -> 950 (2026-09-17). Six tiles across 1090 are 175x117, and two ranks of
## those still left BACK and START RUN clipped off the bottom once the run
## controls moved onto the page. At 950 the tiles are 152x101 — still the biggest
## thing on the page after the lord, and the whole opener still fits in two ranks.
## 1100, down from 1548 (2026-09-17). The rail moved out of its own full-page
## band and into the hero column — see `_build_muster_screen` for why — so this
## is no longer MUSTER_PAGE_W less its margins but the COLUMN's width:
## 1560 page − 420 roster − 26 separation = 1114, less a little for the section's
## own indent. The tiles shrink with it, which is the point rather than a cost:
## at the old width the opener was the heaviest object on a screen it cannot be
## changed from.
const MUSTER_OPENER_STRIP_W := 1100.0
## Ten across, because an opener is ten cards and a deck is a RAIL, not a grid.
## At this width that is 148px a tile — wider than the six-across grid it
## replaces, so the cards grew and the ragged second rank vanished together.
## 5, i.e. TWO ROWS of five rather than one row of ten (2026-09-17).
##
## Moving the rail into the hero column (see `_build_muster_screen`) took a
## 160px full-width band off the page, and `_muster_slack` turned that straight
## into a hole: the strip below the sheet measured 0.0049 mean optical weight
## against a page mean of 0.0555 — 9% of average over ~15% of the canvas. The
## slack CANNOT simply be removed; it is the C32 UI-scale contract (deleting it
## once dropped run setup's y coverage to 59% at 60% scale), so the content has
## to grow into the space instead.
##
## TWO ROWS OF FIVE WAS TRIED HERE AND OVERSHOT — do not re-try it without
## shrinking the rail's width at the same time. At the column's full 1100 a
## 5-wide grid gives 220px tiles, so two rows plus the caption is ~330px against
## the ~125px one row costs: +205, on a page that was only 160 short. Rendered,
## the second row was clipped by the canvas and BACK / START RUN were pushed off
## it entirely. The slack that looked like room to grow into was less than one
## extra row of art at that tile size.
##
## One row of ten it is, and the hole is closed from the roster's side instead
## (see MUSTER_HOST_ROW_H), which is cheaper because a taller roster row adds
## DECISION weight where a second rail row adds decoration.
const MUSTER_RAIL_COLUMNS := 10
## Card art ships 3:2 landscape (768×512 and 1344×896 throughout
## assets/creatures). The tiles are built at that ratio so COVERED crops nothing.
const OPENER_ART_ASPECT := 1.5
## How far a tile's ×N chip sits in from its corner. (It had a twin — the cost
## gem shared this constant so the two could not drift apart on the top edge
## `_probe_alignment` judges them by. The gem was cut 2026-09-19; the name stays
## plural because the badge LAYER does.)
const OPENER_BADGE_INSET := 3.0
## The caption under an opener tile. 15 is COPY_STYLE §11's caption floor, NOT
## the 18 reading floor — see `_make_opener_art_tile` for why this deliberately
## bypasses `_make_display_label`'s clamp.
const OPENER_NAME_SIZE := 15
## Two lines at 15px plus leading, held FIXED so every tile in the rank is the
## same height whether its name wraps or not.
const OPENER_NAME_H := 38.0
## Two ranks of six holds an 11-card opener (max 10 distinct after duplicates)
## without a third rank appearing for one card.
## SIX, matching the sentence above it (2026-09-17). It read 5 while its own
## comment described "two ranks of six"; six is also what buys back the band the
## run controls now occupy — five tiles across 1090 are 211x141 and two ranks of
## those ran the page past the canvas, taking BACK and START RUN off the bottom.
const OPENER_STRIP_COLUMNS := 6

## Warm every distinct card in one hero's opener in a SINGLE batched pass.
##
## This replaced a per-card `CardTextureCache.bake()` fired from _make_deck_mini.
## That call is a coroutine holding a global `_bake_busy` mutex and costing two
## `await RenderingServer.frame_post_draw` plus a synchronous `get_image()` GPU
## flush; called un-awaited once per card it did not run in parallel, it QUEUED —
## and because _focus_hero is bound to `mouse_entered`, sweeping the cursor down
## the five-lord roster stacked up to 25-40 of them, each about a frame.
##
## `validity` is polled between passes, so a warm whose hero is no longer
## spotlighted stands itself down mid-job instead of finishing work nobody will
## see (the ScenePreload.cancel_deck_warm pattern).
func _warm_deck_strip(deck: Array, hid: String,
		validity: Callable = Callable()) -> void:
	var seen: Dictionary = {}
	var datas: Array = []
	for cid in deck:
		var id: String = String(cid)
		if seen.has(id):
			continue
		seen[id] = true
		datas.append(CardDB.get_card_data(id))
	if datas.is_empty():
		return
	var still_valid := validity
	if not still_valid.is_valid():
		still_valid = func() -> bool:
			return is_inside_tree() and _selected_hero == hid
	await CardTextureCache.bake_many(datas, still_valid)


## `mini_scale` defaults to the full size; the muster strip passes the ranked
## size when its pane cannot hold the column in one rank.
func _make_deck_mini(id: String, count: int, mini_scale: float = DECK_MINI_SCALE) -> Control:
	var w: float = 225.0 * mini_scale
	var h: float = 300.0 * mini_scale
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(w, h)
	var card = CARD_SCENE.instantiate()
	card.card_data = CardDB.get_card_data(id).duplicate(true)
	card.card_id = id
	card.is_on_battlefield = true   # static display — no hand-drag behaviour
	card.live_baked_mode = true
	# No bake call here — the whole strip is warmed in ONE batched, cancellable
	# pass by _warm_deck_strip() before this runs.
	card.scale = Vector2(mini_scale, mini_scale)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	# ×N count chip on the mini's top-right corner — the chip is what makes
	# "five minis" read as "ten cards".
	#
	# ONLY WHEN IT SAYS SOMETHING (2026-09-15). This drew unconditionally, so the
	# full-deck inspector hung "×1" on nine of its ten tiles — the chip announcing
	# the default, nine times, on a panel whose own subtitle already reads "11
	# cards". One copy is what a card tile means; the chip exists for the tile that
	# is an exception, and an exception marked on every tile marks nothing. Same
	# rule the opener art strip is built on.
	# NOT an early return: the hover catcher below is what gives this tile its
	# tooltip and its floating full-size preview, so bailing here would trade nine
	# redundant chips for ten dead cards.
	if count > 1:
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
	catcher.tooltip_text = _deck_mini_tooltip(id)
	return slot


## Float a full-size copy of the hovered deck mini above the strip (NetDraft's
## ledger-preview behaviour). Mouse-transparent so it never eats a click.
## THE GLOSSARY, REACHABLE. Card2D gilds its keywords and hangs a `[hint]` hover
## definition off them, but neither survives on this screen: the mini's topmost
## catcher stops the mouse before the rules text sees it, and the floating
## preview is MOUSE_FILTER_IGNORE by design (it sits over the anchor, so making
## it interactive would fight the hover that spawned it).
##
## So on the first screen of the game, a new player reads Guardian, Swift, Doom,
## Wither, Overrun, Rampage, Thorns and Regenerate on the cards they are being
## asked to choose between, with no way to look any of them up. The catcher is
## already a Control under the cursor; a plain tooltip is the one channel that
## costs nothing and cannot be swallowed.
func _deck_mini_tooltip(id: String) -> String:
	var data: Dictionary = CardDB.get_card_data(id)
	if data.is_empty():
		return ""
	var lines: Array[String] = [String(data.get("name", id))]
	for kw in data.get("keywords", []):
		var entry: Dictionary = KeywordEffects.KEYWORDS.get(String(kw), {})
		if entry.is_empty():
			continue
		lines.append("%s — %s" % [entry.get("display", kw), entry.get("desc", "")])
	# A card whose keywords are all unglossed (on_enter/on_death markers carry no
	# KEYWORDS entry) would leave a bare name repeating the plate under it.
	if lines.size() == 1:
		return ""
	return "\n".join(lines)


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



func _show_muster_deck_inspector() -> void:
	var return_focus := get_viewport().gui_get_focus_owner()
	_hide_deck_inspector()
	_deck_inspect_generation += 1
	var build_generation := _deck_inspect_generation
	_deck_inspect_return_focus = return_focus
	if not HeroDB.has_hero(_selected_hero):
		return
	var opener: Array[String] = RunState.opening_deck_for(
		_selected_hero, _muster_alt_deck)
	var overlay := Control.new()
	overlay.name = "DeckInspector"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 520
	add_child(overlay)
	_deck_inspect_overlay = overlay
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.008, 0.006, 0.008, 0.88)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	veil.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			AudioBank.play_ui("back")
			_hide_deck_inspector())
	overlay.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1240, 760)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := GameTheme.make_panel_style(
		Color(0.035, 0.025, 0.03, 0.98), Color(0.72, 0.60, 0.36, 0.82),
		2, 6, false)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var hero := HeroDB.get_hero(_selected_hero)
	# "·", not "-". Every other joined heading in the opening uses the middot
	# ("SLOT 1 · Continue Run", "11 cards · The Colours adds ..."), and a hyphen
	# between a Title Case name and an ALL CAPS phrase reads for a beat as a
	# compound word — "Raider-FULL" — before it resolves as a separator.
	var title := _make_display_label(
		"%s  ·  FULL STARTING DECK" % String(hero.get("name", _selected_hero)),
		27, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var summary := _make_display_label(
		"%d cards  ·  %d max HP" % [opener.size(), RunState.STARTING_MAX_HP],
		15, Color(0.76, 0.69, 0.56))
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(summary)
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in opener:
		if not counts.has(cid):
			counts[cid] = 0
			order.append(cid)
		counts[cid] += 1
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	var grid_center := CenterContainer.new()
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_center.add_child(grid)
	content.add_child(grid_center)
	# Reserve the complete ledger before any rich Card2D is constructed. The
	# previous path started a batch warm without awaiting it, then immediately
	# built the cards; a cold cache therefore leaked implementation order into
	# the open panel. Fixed sockets keep the two ranks motionless while the work
	# happens behind a single connected set of card backs.
	var slots: Array[Control] = []
	var backs: Array[Control] = []
	for cid in order:
		var stage := _make_deck_inspector_stage(0.72, grid)
		var slot: Control = stage["slot"]
		var back: Control = stage["back"]
		grid.add_child(slot)
		slots.append(slot)
		backs.append(back)
	var close := _make_menu_button(
		"CLOSE", Color(0.24, 0.18, 0.14), 18, 48)
	close.name = "DeckInspectorReturn"
	close.custom_minimum_size = Vector2(300, 48)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_hide_deck_inspector)
	content.add_child(close)
	close.call_deferred("grab_focus")
	_hydrate_deck_inspector(overlay, grid, order, counts, slots, backs,
		build_generation)


func _make_deck_inspector_stage(mini_scale: float,
		group: CanvasItem) -> Dictionary:
	var stage_w := 225.0 * mini_scale
	var stage_h := 300.0 * mini_scale
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(stage_w, stage_h)
	slot.size = Vector2(stage_w, stage_h)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var back := TextureRect.new()
	back.texture = CARD_BACK_TEXTURE_PICKER
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, group)
	slot.add_child(back)
	return {"slot": slot, "back": back}


func _hydrate_deck_inspector(overlay: Control, grid: GridContainer,
		order: Array[String], counts: Dictionary, slots: Array[Control],
		backs: Array[Control], generation: int) -> void:
	# A cache batch may outlive a rapidly closed overlay by a few worker frames.
	# Weak refs let its validity poll observe that cancellation without asking a
	# lambda to resurrect freed Controls (which Godot reports as capture errors).
	var overlay_ref: WeakRef = weakref(overlay)
	var grid_ref: WeakRef = weakref(grid)
	var still_here := func() -> bool:
		var live_overlay := overlay_ref.get_ref() as Control
		var live_grid := grid_ref.get_ref() as GridContainer
		return generation == _deck_inspect_generation \
			and is_inside_tree() \
			and live_overlay != null \
			and live_overlay == _deck_inspect_overlay \
			and live_overlay.is_inside_tree() \
			and live_grid != null \
			and live_grid.is_inside_tree()

	# Guarantee one painted frame of the complete back layout. Warm caches take
	# the same visual route as cold ones instead of flashing straight to faces.
	await get_tree().process_frame
	if not still_here.call():
		return

	var datas: Array = []
	for cid in order:
		datas.append(CardDB.get_card_data(cid))
	await CardTextureCache.bake_many(datas, still_here)
	if not still_here.call():
		return

	var faces: Array[Control] = []
	for i in order.size():
		var face := _make_deck_mini(order[i], int(counts[order[i]]), 0.72)
		face.modulate.a = 0.0
		slots[i].add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		faces.append(face)
		# Spread Card2D construction across frames, but only behind the already
		# complete backs. The player sees one ledger, never its build order.
		await get_tree().process_frame
		if not still_here.call():
			return

	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	for face in faces:
		if is_instance_valid(face):
			face.modulate.a = 1.0
	if snap:
		for back in backs:
			if is_instance_valid(back):
				back.visible = false
				back.queue_free()
		return

	for i in faces.size():
		if is_instance_valid(backs[i]) and is_instance_valid(faces[i]):
			Motion.flip_out(backs[i], 0.13)
			Motion.flip_in(faces[i], Motion.time(0.13), 0.17)
	# One light stroke ties the ten simultaneous turns into a single inspected
	# deck, matching the opener rail rather than reading as ten unrelated loads.
	Motion.foil_sweep(self, grid,
		_faction_accent(_selected_hero).lerp(GILT_BRIGHT, 0.58),
		Motion.time(0.36))


func _hide_deck_inspector() -> void:
	_deck_inspect_generation += 1
	var restore_focus := _deck_inspect_return_focus
	_deck_inspect_return_focus = null
	if _deck_inspect_overlay != null and is_instance_valid(_deck_inspect_overlay):
		var outgoing := _deck_inspect_overlay
		if outgoing.get_parent() != null:
			outgoing.get_parent().remove_child(outgoing)
		outgoing.queue_free()
	_deck_inspect_overlay = null
	if restore_focus != null and is_instance_valid(restore_focus):
		restore_focus.call_deferred("grab_focus")

func _begin_run_with(hero_id: String) -> void:
	var seed_to_use := _pending_run_seed()
	if _daily_pick and not MetaState.todays_daily().is_empty():
		_daily_pick = false
		_run_commit_locked = false
		return

	var hero_data := HeroDB.get_hero(hero_id)
	RunState.pending_signature_relic = ""
	RunState.pending_deck_variant = ""
	# The relic half goes through _muster_signature_relic so THE ARSENAL's
	# preview and this commit cannot disagree about which relic is already held.
	var signature := _muster_signature_relic(hero_id)
	if signature != "" and signature == String(hero_data.get("relic_alt", "")):
		RunState.pending_signature_relic = signature
	if _bound_doctrine_unlocked(hero_id) and _muster_alt_deck:
		if _doctrine_mastery_unlocked(hero_id) or _muster_alt_relic:
			RunState.pending_deck_variant = "alt"

	RunState.start_new_run(hero_id, _selected_ascension, seed_to_use)
	if _daily_pick:
		RunState.is_daily_run = true
		RunState.daily_date = MetaState.today_str()
		RunState.daily_mutator_id = RunState.daily_mutator_id_for_today()

	# The final button commits both halves. Follow-up card/relic pickers happen
	# after this boundary; BACK on THE MUSTER never starts or rolls a run.
	_writ_resolution_rng = RandomNumberGenerator.new()
	_writ_resolution_rng.seed = int(RunState.run_seed) ^ 0x57524954 ^ 0x5245534F
	var chosen: Dictionary = {}
	for entry in _muster_writ_slate:
		if String(entry.get("id", "")) == _selected_writ_id:
			chosen = entry
			break
	if chosen.is_empty() and not _muster_writ_slate.is_empty():
		chosen = _muster_writ_slate[0]
	if chosen.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	_pick_blessing(chosen)


func _change_ascension(delta: int) -> void:
	# Lives on the run-setup (hero select) row now — update the label in place
	# instead of rebuilding the screen (a rebuild would reload every portrait).
	_selected_ascension = clampi(_selected_ascension + delta, 0, MetaState.unlocked_ascension)
	if _asc_label != null and is_instance_valid(_asc_label):
		_asc_label.text = "Ascension %d / %d" % [
			_selected_ascension, MetaState.unlocked_ascension]
	_update_asc_rules_text()


func _on_daily_button_pressed() -> void:
	var today: Dictionary = MetaState.todays_daily()
	if not today.is_empty():
		if String(today.get("result", "")) == "marching":
			var slot := _daily_resume_slot(today)
			if slot >= 0:
				_load_slot_into_game(slot)
		return
	_toggle_daily_pick()


func _daily_resume_slot(record: Dictionary) -> int:
	var date := String(record.get("date", ""))
	var candidates: Array[int] = []
	var preferred := int(record.get("slot", -1))
	if preferred >= 0 and preferred < RunState.SAVE_SLOTS:
		candidates.append(preferred)
	for slot in range(RunState.SAVE_SLOTS):
		if not candidates.has(slot):
			candidates.append(slot)
	for slot in candidates:
		var summary: Dictionary = RunState.get_slot_summary(slot)
		if not bool(summary.get("has_save", false)) \
				or not bool(summary.get("is_daily_run", false)):
			continue
		var saved_date := String(summary.get("daily_date", ""))
		# Empty is the pre-daily_date save shape; the single matching marching
		# ledger is its only possible origin.
		if saved_date == "" or saved_date == date:
			return slot
	return -1


func _toggle_daily_pick() -> void:
	# DAILY RUN locks the run to today's deterministic seed; the free-seed
	# field goes quiet while it's on (the two would fight over the same roll),
	# and _refresh_seed_field_state is what tells the player so.
	_daily_pick = not _daily_pick
	if _seed_edit != null and is_instance_valid(_seed_edit):
		if _daily_pick:
			_seed_edit.text = ""
		_refresh_seed_field_state()
	if _daily_pick:
		_muster_seed_text = ""
	if _daily_btn != null and is_instance_valid(_daily_btn):
		var lbl := _menu_button_label(_daily_btn)
		if lbl != null:
			lbl.text = "DAILY RUN — ON" if _daily_pick else "DAILY RUN — OFF"
	_refresh_muster_deals()
	_refresh_muster_campaign()


func _daily_tooltip() -> String:
	# Today's seed + today's omen + whether the player already marched. The
	# daily is a MODE now, not just a locked seed — the tooltip is where its
	# identity lives without widening the quiet setup row.
	var text := "Today's seed — everyone playing today gets the same map."
	var omen_id: String = RunState.daily_mutator_id_for_today()
	var omen: Dictionary = MutatorDB.get_mutator(omen_id)
	if not omen.is_empty():
		text += "\nToday's Battle Rule: %s — %s" % [
			String(omen.get("name", omen_id)), String(omen.get("desc", ""))]
	var today: Dictionary = MetaState.todays_daily()
	if not today.is_empty():
		# The HERO'S NAME, not its id. MetaState stores the identifier ("raider"),
		# and this line printed it raw — a lower-case code word in the middle of a
		# sentence the player reads.
		var hero_id := String(today.get("hero", ""))
		var hero_name := String(HeroDB.get_hero(hero_id).get("name", hero_id))
		# Every branch here is a BLOCKED or REDIRECTED state, so each names what
		# it stops you doing as well as why (COPY_STYLE §12).
		match String(today.get("result", "")):
			"won":
				text += "\nYou already played today's Daily Run as %s and won." % hero_name
				text += "\nThe next one unlocks tomorrow."
			"lost":
				text += "\nYou already played today's Daily Run as %s and lost." % hero_name
				text += "\nThe next one unlocks tomorrow."
			_:
				text += "\nToday's Daily Run is already under way as %s." % hero_name
				text += ("\nPress to pick it back up." if _daily_resume_slot(today) >= 0
					else "\nIts save is gone, and there is one Daily Run per day."
						+ " The next one unlocks tomorrow.")
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
			_refresh_menu_motion_state()
			return
		elif child.has_method("open"):
			child.open()
			_refresh_menu_motion_state()
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
	# Detach, don't only queue_free: the replacement below is also named
	# "HowToPlayOverlay", so a deferred free leaves both in the tree for a frame
	# and the INCOMING one gets renamed. This lookup would then miss it forever
	# and the third press really would stack a scrim — the exact thing the line
	# above claims to prevent. Same defect as _rebuild_menu's; see the note there.
	var existing := get_node_or_null("HowToPlayOverlay")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	_how_to_play_overlay = GameTheme.make_how_to_play_overlay()
	add_child(_how_to_play_overlay)
	_refresh_menu_motion_state()


# (The HowToPlayOverlay class was removed — both this screen and MapView now call
# the single shared builder GameTheme.make_how_to_play_overlay(), so the primer
# copy can no longer drift between the two.)



func _animate_subscreen_reveal(menu: Control) -> void:
	if menu == null:
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	# Rebuild callers detach their outgoing composition synchronously. Retain the
	# queued-for-deletion guard for callers outside that shared path, so a dying
	# row can never contribute delay to the incoming reveal.
	var tw := create_tween()
	tw.set_parallel(true)
	var delay := 0.0
	for child in menu.get_children():
		if child.is_queued_for_deletion() or child.name == "Slack":
			continue
		child.modulate.a = 0.0
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
	# Stay process-enabled so a live Reduce Motion toggle, the persistent settings
	# overlay, and menu-local sub-screens can pause/resume the cosmetics without
	# requiring the scene to be rebuilt. Transform work itself is capped at 30 Hz.
	set_process(true)
	_refresh_menu_motion_state(true)


func _process(delta: float) -> void:
	_refresh_menu_motion_state()
	if _menu_motion_suspended:
		return
	if _bg_node == null or not is_instance_valid(_bg_node):
		return
	_menu_motion_accumulator += maxf(delta, 0.0)
	var elapsed_steps := floori(_menu_motion_accumulator / MENU_MOTION_STEP)
	if elapsed_steps <= 0:
		return
	# Advance in exact 30 Hz quanta and retain the sub-step remainder. This keeps
	# the animation clock honest at arbitrary frame rates while doing transforms
	# at most about thirty times per second.
	var motion_delta := float(elapsed_steps) * MENU_MOTION_STEP
	_menu_motion_accumulator -= motion_delta
	_kb_time += motion_delta
	# Smooth the cursor toward its target so parallax glides instead of snapping.
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var target := Vector2(
		clampf((m.x / maxf(vp.x, 1.0)) * 2.0 - 1.0, -1.0, 1.0),
		clampf((m.y / maxf(vp.y, 1.0)) * 2.0 - 1.0, -1.0, 1.0))
	_parallax_mouse = _parallax_mouse.lerp(
		target, clampf(motion_delta * 4.0, 0.0, 1.0))
	# Ken Burns: a slow looping breath of position + zoom. Parallax: drift opposite
	# the cursor. Both stay well inside the oversize slack so no edge shows.
	var kb := Vector2(sin(_kb_time * 0.13) * 12.0, cos(_kb_time * 0.10) * 9.0)
	var par := -_parallax_mouse * 24.0
	_bg_node.position = kb + par
	var zoom := _bg_base_scale + sin(_kb_time * 0.08) * 0.012
	_bg_node.scale = Vector2(zoom, zoom)


func _set_subscreen_motion_obscured(obscured: bool) -> void:
	_subscreen_obscures_motion = obscured
	_refresh_menu_motion_state()


func _refresh_menu_motion_state(force: bool = false) -> void:
	var suspended := _should_suspend_menu_motion()
	if not force and suspended == _menu_motion_suspended:
		return
	_menu_motion_suspended = suspended
	# Never carry hidden elapsed time into the first visible update: resuming uses
	# one fresh 30 Hz quantum and continues from the exact pose that was frozen.
	_menu_motion_accumulator = 0.0
	if _title_shimmer_tween != null and _title_shimmer_tween.is_valid():
		if suspended:
			_title_shimmer_tween.pause()
		else:
			_title_shimmer_tween.play()
	_apply_menu_particle_motion_state(suspended)


func _should_suspend_menu_motion() -> bool:
	if UserSettings != null and UserSettings.reduce_motion:
		return true
	if _subscreen_obscures_motion:
		return true
	if _how_to_play_overlay != null and is_instance_valid(_how_to_play_overlay) \
			and _how_to_play_overlay.visible:
		return true
	# SettingsOverlay is persistent under UserSettings. Check the panel's actual
	# visibility rather than only `_is_open`, so its short close fade remains
	# covered and motion resumes only once the menu is unobscured.
	if UserSettings != null:
		for child in UserSettings.get_children():
			if not child.has_method("_open") or not child.has_method("_close"):
				continue
			var panel = child.get("_panel_root")
			if panel is CanvasItem and (panel as CanvasItem).visible:
				return true
	return false


func _apply_menu_particle_motion_state(suspended: bool) -> void:
	for path in ["Atmosphere/AmbientMotes", "Atmosphere/MenuEmbers"]:
		var emitter := get_node_or_null(path) as CPUParticles2D
		if emitter == null:
			continue
		emitter.process_mode = Node.PROCESS_MODE_DISABLED if suspended \
			else Node.PROCESS_MODE_INHERIT


func _add_menu_embers() -> void:
	# Warm embers rising up the burning meadow. Parented to the preserved
	# "Atmosphere" node so menu rebuilds (e.g. ascension changes) don't wipe them.
	if UserSettings != null and (not UserSettings.particles or UserSettings.reduce_motion):
		return
	var host: Node = get_node_or_null("Atmosphere")
	if host == null:
		host = self
	if host.has_node("MenuEmbers"):
		return
	var vp := get_viewport_rect().size
	var embers := CPUParticles2D.new()
	embers.name = "MenuEmbers"
	embers.add_to_group("ambient_particles")
	embers.position = Vector2(vp.x * 0.5, vp.y + 16.0)
	embers.z_index = 6
	# THE MEADOW BURNS WITH YOUR RECORD (2026-08-05). The title screen was byte-
	# identical on march 1 and march 200: one static main_menu.png, and the only
	# thing on the whole screen that answered a player's history was a 17px grey
	# line reading "Marches 24 · Victories 0 · Defeats 24". This is a game about
	# an isle that is on fire and a record that accumulates — the ONE ambient
	# system already running here should be reading that ledger.
	#
	# Deliberately keyed to MARCHES, not victories. A player 30 defeats deep has
	# spent the most time on this screen and earned the most changed version of
	# it; keying to wins would show the least to whoever has seen it most. The
	# curve is a soft sqrt so the early marches each register and the far tail
	# does not turn the menu into a bonfire the text cannot survive.
	var marches: float = float(MetaState.total_runs) if MetaState != null else 0.0
	var burn: float = clampf(sqrt(marches / 40.0), 0.0, 1.0)
	embers.amount = int(round(lerpf(40.0, 96.0, burn)))
	embers.lifetime = 6.5
	embers.preprocess = 5.0   # start with the screen already full of drifting embers
	embers.randomness = 1.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(vp.x * 0.55, 6.0)
	embers.direction = Vector2(0, -1)
	embers.spread = 16.0
	embers.gravity = Vector2(8.0, -18.0)   # rise, with a gentle lateral lean
	# A hotter fire throws its sparks higher and further, so the burn rides the
	# velocity too — otherwise a deep profile just gets a denser field of
	# identical motes, which reads as a particle-count slider rather than as a
	# fire that has been running longer.
	embers.initial_velocity_min = lerpf(16.0, 24.0, burn)
	embers.initial_velocity_max = lerpf(44.0, 70.0, burn)
	embers.scale_amount_min = 1.4
	embers.scale_amount_max = lerpf(3.2, 4.0, burn)
	# Fade in then out over life so embers wink in and burn out rather than pop.
	# The peak also heats: 0.66 green at march 0 → 0.74 deep in, i.e. the sparks
	# go from a settled orange toward a live yellow-white core.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.62, 0.26, 0.0))
	ramp.set_color(1, Color(1.0, 0.40, 0.14, 0.0))
	ramp.add_point(0.18, Color(1.0, lerpf(0.66, 0.74, burn), lerpf(0.32, 0.44, burn),
		lerpf(0.85, 0.95, burn)))
	ramp.add_point(0.7, Color(1.0, 0.46, 0.18, 0.6))
	embers.color_ramp = ramp
	embers.emitting = true
	host.add_child(embers)
	_apply_menu_particle_motion_state(_menu_motion_suspended)


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
	if _title_shimmer_delay_tween != null and _title_shimmer_delay_tween.is_valid():
		_title_shimmer_delay_tween.kill()
	# Let the intro settle, but keep the delay owned by this screen. The old
	# SceneTreeTimer coroutine outlived a menu closed inside this one-second
	# window; a bound tween dies with the menu and rebuilds cancel it explicitly.
	_title_shimmer_delay_tween = create_tween()
	_title_shimmer_delay_tween.tween_interval(1.0)
	_title_shimmer_delay_tween.tween_callback(
		_begin_title_shimmer.bind(weakref(title)))


func _begin_title_shimmer(title_ref: WeakRef) -> void:
	_title_shimmer_delay_tween = null
	var title := title_ref.get_ref() as Label
	if title == null or not is_inside_tree():
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
	if _should_suspend_menu_motion():
		_title_shimmer_tween.pause()


# ---------------------------------------------------------------------------
# WRIT RESOLUTION (the committed term, paid out)
# ---------------------------------------------------------------------------
# The four-slot writ slate is DEALT on step III of THE MUSTER
# (_refresh_muster_deals → _make_muster_writ_tile) and COMMITTED by
# _begin_run_with, which hands the chosen entry straight to _pick_blessing.
# Everything below this line is the payout half: it runs AFTER start_new_run,
# so it has a real deck, relics and purse to touch.
#
# There is no separate war-chest SCREEN any more. It was a fourth full screen
# asking a fifth question after the run had already begun, and its tiles are
# now the terms the player weighed on step III against the column they had just
# built. The old `_show_blessing_select` / `_make_blessing_choice` /
# `_on_blessing_choice_pressed` / `_roll_blessings` set was deleted 2026-08-01;
# only its follow-up pickers survive, because a writ that says "choose 1 card"
# still has to show a grid.
#
# The card-touching writs (forge, transform, enlist, remove) open pick-a-card
# grids instead of hitting a random card — the rest of the game sets an agency
# standard (forge previews, chosen sacrifices) that a random permanent mod on
# screen one was violating. They are built in MainMenu rather than a dedicated
# scene so they reuse the atmosphere/parallax already running behind the menu
# (replace the Menu VBox in place, no scene change).


## The stream every writ RESOLUTION rolls against, as opposed to the stream that
## dealt the slate. Both hang off run_seed, so a Daily March reproduces the four
## tiles AND whatever each tile then offers — an Enlist slate, a Remount result,
## THE ARSENAL's 1-of-3. Those three sites used the global `shuffle()`/`randi()`
## until 2026-07-30, which meant two players on the same seed saw the same four
## tiles and then different consequences, i.e. the reproducibility was cosmetic.
##
## Lazily built so any probe that drives _pick_blessing directly still gets a
## seeded stream instead of a null crash.
func _writ_rng() -> RandomNumberGenerator:
	if _writ_resolution_rng == null:
		_writ_resolution_rng = RandomNumberGenerator.new()
		_writ_resolution_rng.seed = int(RunState.run_seed) ^ 0x57524954 ^ 0x5245534F
	return _writ_resolution_rng


## Clear the screen down to its background for a full-screen writ picker.
##
## The `visible = false` is the load-bearing line and it was MISSING until
## 2026-08-01. The pickers keep the Menu VBox alive (they only free their own
## siblings), and the one place that ever hid it was `_show_blessing_select` —
## a screen the live flow stopped visiting when the writ model landed. So
## TAKE THE FIELD on a Forge term drew the card grid straight over a fully
## visible THE MUSTER: two screens of cards at once, the muster's own eleven
## legible behind the ten the player was being asked to choose from.
## _center_menu_for_subscreen puts it back.
##
## THE SCRIM SURVIVES THIS SWEEP (2026-08-03). It did not, and the pickers were
## the only screens in the whole opening with no seat under them at all: the
## sweep freed every child that was not Menu/Background/Atmosphere, and MenuScrim
## is exactly such a child, so TAKE THE FIELD on a Forge term laid eleven cards
## and a 30px question straight onto the painted fire. Measured on
## `_shot_runstart` frame `writ_forge_picker`: the left third of the grid sat on
## warm-black and the right third on open flame, the same one-row-two-legibilities
## split that _set_subscreen_scrim was written for. Keeping the node and flipping
## it to the centred profile costs one line and covers all three pickers (forge /
## enlist / arsenal), which are full-canvas and therefore need it MORE than the
## centred sub-screens that at least carry their own panel fills.
func _clear_for_picker() -> void:
	_set_subscreen_motion_obscured(true)
	for child in get_children():
		var cname: String = child.name
		if cname == "Menu":
			(child as CanvasItem).visible = false
			continue
		if cname in ["Background", "Atmosphere", "MenuScrim"]:
			continue
		child.queue_free()
	# Full-rect, heaviest at the bottom where the fire is. Every picker adds its
	# title and grid as LATER siblings, so they draw over this by tree order.
	_set_subscreen_scrim(true)
	_picker_commit_locked = false
	_picker_build_generation += 1


## Fisher-Yates against a local stream — Array.shuffle() only ever uses the
## global RNG, so it cannot be used anywhere a roll must be reproducible.
func _seeded_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _pick_blessing(entry: Dictionary) -> void:
	# Resolve one writ. THE PACT bills its price first — the cost is signed
	# before the goods are handed over, which is also the order the tile reads
	# in. Every pact costs the same 6 max HP, so there is exactly one number
	# here and no per-entry pricing logic to drift.
	if bool(entry.get("is_pact", false)):
		RunState.hero_max_hp = maxi(1,
			RunState.hero_max_hp - WritDB.PACT_COST_MAX_HP)
		RunState.hero_hp = mini(RunState.hero_hp, RunState.hero_max_hp)

	var effect := String(entry.get("effect", ""))
	var value: int = int(entry.get("value", 1))
	match effect:
		"forge":
			_writ_forge_step(value, [])
			return
		"remove":
			_blessing_remove_step(value)
			return
		"remount":
			_blessing_transform_step(value)
			return
		"enlist":
			_writ_enlist_step(1, value)
			return
		"enlist2":
			_writ_enlist_step(2, value)
			return
		"arsenal":
			var offered: Array[String] = RelicDB.roll_foundation_relics(
				value, RunState.relics, RunState.current_hero_id, _writ_rng())
			if offered.is_empty():
				GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
				return
			_show_writ_relic_picker("CHOOSE A RELIC", offered,
				func(rid: String) -> void:
					RunState.add_relic(rid)
					GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45))
			return
		"purse":
			RunState.add_relic(String(entry.get("relic", "")))
		"purse2":
			RunState.add_relic(String(entry.get("relic", "")))
			RunState.add_relic(String(entry.get("relic2", "")))
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)


## Forge N cards, one grid at a time. `taken` carries the deck_uids already
## forged this writ so a two-card forge cannot re-offer the card it just
## sharpened — _blessing_upgrade_candidates filters on has_upgrade_path("plus"),
## which only drops a card AFTER the mod lands, so without this the second grid
## would still list the first pick on the same frame.
func _writ_forge_step(remaining: int, taken: Array) -> void:
	var candidates: Array = []
	for i in _blessing_upgrade_candidates():
		if not (int(i) in taken):
			candidates.append(i)
	if remaining <= 0 or candidates.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var suffix: String = "  (%d LEFT)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("CHOOSE A CARD TO FORGE" + suffix, candidates,
		func(i: int) -> void:
			RunState.upgrade_card(i, "plus")
			var next_taken: Array = taken.duplicate()
			next_taken.append(i)
			_writ_forge_step(remaining - 1, next_taken))


## Enlist `picks` cards, each chosen from a fresh slate of `width` uncommons.
func _writ_enlist_step(picks: int, width: int) -> void:
	if picks <= 0:
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var pool: Array = CardDB.cards_of_rarity("uncommon")
	_seeded_shuffle(pool, _writ_rng())
	var offered: Array = pool.slice(0, mini(width, pool.size()))
	if offered.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var suffix: String = "  (%d LEFT)" % picks if picks > 1 else ""
	_show_blessing_offer_picker("CHOOSE A CARD TO ADD" + suffix, offered,
		func(cid: String) -> void:
			RunState.add_card(cid)
			_writ_enlist_step(picks - 1, width))



func _blessing_transform_step(remaining: int) -> void:
	var eligible: Array = []
	for i in RunState.deck.size():
		if not CardDB.is_curse(RunState.deck[i]):
			eligible.append(i)
	if remaining <= 0 or eligible.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var suffix: String = "  (%d LEFT)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("CHOOSE A CARD TO TRANSFORM" + suffix, eligible,
		func(i: int):
			_blessing_transform_at(i)
			_blessing_transform_step(remaining - 1))


# The Remount Line rolls one rarity HIGHER, floored at uncommon. It used to
# roll same-rarity like the in-run Remount Fair, which made the writ a genuine
# step-up for four lords and a PURE LATERAL COIN-FLIP for the Kindler, whose
# opener is all common-rarity — his commons rolled into other commons. The
# in-run Fair keeps its own same-rarity rule; this is the paid opening version.
func _blessing_transform_at(deck_index: int) -> void:
	var old_id: String = RunState.deck[deck_index]
	var rarity: String = String(CardDB.get_card_data(old_id).get("rarity", "common"))
	match rarity:
		"starter", "enemy", "common":
			rarity = "uncommon"
		"uncommon":
			rarity = "rare"
		_:
			rarity = "rare"
	var pool: Array = CardDB.cards_of_rarity(rarity)
	pool.erase(old_id)
	if pool.is_empty():
		pool = CardDB.cards_of_rarity("common")
		pool.erase(old_id)
	RunState.remove_card_at(deck_index)
	RunState.add_card(pool[_writ_rng().randi() % pool.size()])


func _blessing_remove_step(remaining: int) -> void:
	if remaining <= 0 or RunState.deck.size() <= 1:
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE, 0.45)
		return
	var all_idx: Array = []
	for i in RunState.deck.size():
		all_idx.append(i)
	var suffix: String = "  (%d LEFT)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("CHOOSE A CARD TO REMOVE" + suffix, all_idx,
		func(i: int):
			RunState.remove_card_at(i)
			_blessing_remove_step(remaining - 1))






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


## Reserve a picker's complete geometry before any cache wait. The back and
## disabled click-catcher are cheap; the ornate Card2D face is hydrated behind
## them later. Container children are never added during the visible load, so a
## late card cannot recenter the row or push an earlier card into a new column.
func _make_blessing_card_shell(parent: Control, on_pick: Callable,
		picked: Variant, take_to_pack: bool = false) -> Dictionary:
	var wrapper := Control.new()
	wrapper.name = "BlessingCardSlot"
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.set_meta("coordinated_card_slot", true)
	parent.add_child(wrapper)

	var back := TextureRect.new()
	back.name = "LoadingBack"
	back.texture = CARD_BACK_TEXTURE_PICKER
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, parent)
	wrapper.add_child(back)

	var click_btn := Button.new()
	click_btn.name = "CardPickButton"
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_ALL
	click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click_btn.disabled = true
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.pressed.connect(_on_blessing_card_pick_pressed.bind(
		wrapper, on_pick, picked, take_to_pack))
	wrapper.add_child(click_btn)
	GameTheme.hover_lift(wrapper, 1.025)
	return {"wrapper": wrapper, "back": back, "button": click_btn}


## Renderer work may finish one card at a time; presentation never does. Each
## full face is built invisibly inside its already-reserved slot, then the whole
## logical offer turns over on one shared beat. Reduce Motion/headless snaps the
## same group to its final state in one frame.
func _hydrate_blessing_card_group(card_datas: Array[Dictionary], shells: Array,
		picker_alive: Callable, preparing: Label) -> void:
	for i in range(card_datas.size()):
		if not picker_alive.call():
			return
		var data: Dictionary = card_datas[i]
		if not CardTextureCache.has_gallery(data):
			await CardTextureCache.bake_gallery(data, picker_alive)
		if not picker_alive.call():
			return
		var wrapper: Control = shells[i].wrapper
		var card_node = CARD_SCENE_PICKER.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		card_node.gallery_baked_mode = true
		card_node.defer_baked_rules_text = DisplayServer.get_name() != "headless"
		card_node.visible = false
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, 0)
		shells[i]["card"] = card_node
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
			if not picker_alive.call():
				return
			card_node.complete_deferred_baked_rules()
			await RenderingServer.frame_post_draw

	if not picker_alive.call():
		return
	preparing.text = "UNSEALING THE DECK..."
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not snap:
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for shell in shells:
			Motion.flip_out(shell.back as Control, 0.13)
		await get_tree().create_timer(Motion.time(0.13)).timeout
		if not picker_alive.call():
			return
	for shell in shells:
		var card: Control = shell.card
		var back: Control = shell.back
		if snap and is_instance_valid(back):
			back.queue_free()
		card.visible = true
		if not snap:
			Motion.flip_in(card, 0.0, 0.17)
	if not snap:
		await get_tree().create_timer(Motion.time(0.17)).timeout
		if not picker_alive.call():
			return
	for shell in shells:
		(shell.button as Button).disabled = false
	preparing.text = ""


func _show_blessing_card_picker(title_text: String, indices: Array,
		on_pick: Callable) -> void:
	# Full-screen card grid over the menu background — the run-start deck is
	# 10 cards, so this is two rows of five. Same wrapper-plus-transparent-
	# button pattern as the in-run pickers (Event/Rest), so click semantics
	# match everywhere the player picks a card.
	_clear_for_picker()

	var title := _make_display_label(title_text, 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 88
	var preparing := _make_display_label("PREPARING THE DECK...", 16,
		Color(IVORY.r, IVORY.g, IVORY.b, 0.72))
	preparing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preparing.set_anchors_preset(Control.PRESET_TOP_WIDE)
	preparing.offset_top = 82
	preparing.offset_bottom = 108
	preparing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preparing)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	# SIX COLUMNS, AND THE BOX WIDENED TO HOLD THEM — the two halves are one fix
	# and changing either alone just moves the clip. Every one of this picker's
	# three callers (forge / transform / remove) is offered at the muster, where
	# the deck is exactly ELEVEN cards, and the card you have to scroll to find is
	# the one that does not get picked.
	#
	# The arithmetic, because guessing it wrong is how this was clipped twice:
	# the canvas is the 1600x900 project viewport, and a card wrapper is 225x300
	# at h/v separation 20.
	#   5 cols = 1205 wide (fits) but THREE rows = 940 tall against 690 — the last
	#           row sat below the fold behind a scrollbar. The original bug.
	#   6 cols = 1450 wide, which does NOT fit the old 150px insets (1300 usable),
	#           so the sixth card clipped at the right edge instead. Same bug, new
	#           axis.
	# At 64px insets the usable width is 1472, so 1450 fits with 22 to spare, and
	# two rows measure 620 against 690. No scrollbar on either axis.
	#
	# The rank is now PINNED to that 1450 rather than sized to the viewport (see
	# GameTheme.make_picker_rank), which keeps the arithmetic above true even if a
	# scrollbar ever appears — and centres the short second row, which used to sit
	# left-flush with a card-shaped hole beside it.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll.offset_left = 64
	scroll.offset_right = -64
	scroll.offset_top = 110
	scroll.offset_bottom = 800
	add_child(scroll)

	var grid := GameTheme.make_picker_rank(6, 225.0, 20, 20)
	grid.set_meta("coordinated_card_group", true)
	scroll.add_child(grid)

	# The complete two-row spread exists before the first await. Card backs carry
	# the wait without exposing renderer order or changing the rank's geometry.
	var shells: Array = []
	for ei in range(indices.size()):
		shells.append(_make_blessing_card_shell(
			grid, on_pick, int(indices[ei])))

	var build_generation := _picker_build_generation
	var scroll_ref: WeakRef = weakref(scroll)
	var picker_alive := func() -> bool:
		if not is_inside_tree() or build_generation != _picker_build_generation \
				or _picker_commit_locked:
			return false
		var live_scroll = scroll_ref.get_ref()
		return live_scroll != null and is_instance_valid(live_scroll)
	var card_datas: Array[Dictionary] = []
	for deck_index in indices:
		card_datas.append(RunState.get_upgraded_card_data(int(deck_index)))
	await _hydrate_blessing_card_group(
		card_datas, shells, picker_alive, preparing)


func _on_blessing_card_pick_pressed(target: Control, on_pick: Callable,
		picked, take_to_pack: bool = false) -> void:
	if _picker_commit_locked:
		return
	_picker_commit_locked = true
	GameTheme.claim_pop(target)
	if take_to_pack:
		# Only offer cards use this branch. Forge/remove/transform pickers keep
		# their clicked card in place because they mutate or retire that original.
		if target.get_parent() != null:
			for sibling in target.get_parent().get_children():
				if sibling != target and sibling is Control:
					GameTheme.fade_exit(sibling, 0.20)
		if UserSettings == null or not UserSettings.reduce_motion:
			await get_tree().create_timer(0.10).timeout
		if not is_inside_tree():
			return
		var vp := get_viewport_rect().size
		await GameTheme.pocket_away(
			target, Vector2(vp.x * 0.5, vp.y + 30.0), 0.34)
	elif UserSettings == null or not UserSettings.reduce_motion:
		await get_tree().create_timer(0.11).timeout
	if not is_inside_tree():
		return
	on_pick.call(picked)


# The Recruit Tent variant: pick from OFFERED card ids (cards not yet in the
# deck), where _show_blessing_card_picker picks from live deck indices. Same
# grid, same click semantics; the callback receives the card id string.
func _show_blessing_offer_picker(title_text: String, ids: Array,
		on_pick: Callable) -> void:
	_clear_for_picker()

	var title := _make_display_label(title_text, 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 88
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var preparing := _make_display_label("PREPARING THE CARDS...", 16,
		Color(IVORY.r, IVORY.g, IVORY.b, 0.72))
	preparing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preparing.set_anchors_preset(Control.PRESET_TOP_WIDE)
	preparing.offset_top = 92
	preparing.offset_bottom = 120
	preparing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preparing)
	var row := HBoxContainer.new()
	row.set_meta("coordinated_card_group", true)
	row.set_anchors_preset(Control.PRESET_CENTER)
	var total_w: int = ids.size() * 225 + (ids.size() - 1) * 40
	row.offset_left = -total_w / 2
	row.offset_right = total_w / 2
	row.offset_top = -150
	row.offset_bottom = 150
	row.add_theme_constant_override("separation", 40)
	add_child(row)

	# As above: the centered row's width is final before rendering can yield.
	var shells: Array = []
	for ei in range(ids.size()):
		shells.append(_make_blessing_card_shell(
			row, on_pick, String(ids[ei]), true))

	var build_generation := _picker_build_generation
	var row_ref: WeakRef = weakref(row)
	var picker_alive := func() -> bool:
		if not is_inside_tree() or build_generation != _picker_build_generation \
				or _picker_commit_locked:
			return false
		var live_row = row_ref.get_ref()
		return live_row != null and is_instance_valid(live_row)
	var card_datas: Array[Dictionary] = []
	for offered_id in ids:
		card_datas.append(CardDB.get_card_data(String(offered_id)))
	await _hydrate_blessing_card_group(
		card_datas, shells, picker_alive, preparing)


## THE ARSENAL's picker: choose 1 of N relics. Modelled on the card offer
## picker above (same title, same row, same click semantics) but rendering relic
## plates, because a relic has no Card2D. The callback receives the relic id.
##
## Offering a CHOICE here is not just presentation — it is what retires the
## dead-roll problem the old blind "gain a random Combat relic" tile had. The
## Burnt Dispatches needs an exhausted spell and is inert for four of the five
## lords; when it is one of three on screen, nobody is forced to take it.
func _show_writ_relic_picker(title_text: String, ids: Array,
		on_pick: Callable) -> void:
	_clear_for_picker()

	var title := _make_display_label(title_text, 30, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 88
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	var tile_w := 300
	var total_w: int = ids.size() * tile_w + (ids.size() - 1) * 40
	row.offset_left = -total_w / 2
	row.offset_right = total_w / 2
	row.offset_top = -150
	row.offset_bottom = 150
	row.add_theme_constant_override("separation", 40)
	add_child(row)

	var pick_i := 0
	for rid_v in ids:
		var rid := String(rid_v)
		var rd: Dictionary = RelicDB.get_relic(rid)
		var wrapper := PanelContainer.new()
		wrapper.custom_minimum_size = Vector2(tile_w, 250)
		var plate := GameTheme.make_panel_style(
			Color(0.06, 0.045, 0.05, 0.88), Color(0.60, 0.51, 0.34, 0.55), 1, 5, false)
		plate.content_margin_left = 20
		plate.content_margin_right = 20
		plate.content_margin_top = 18
		plate.content_margin_bottom = 18
		wrapper.add_theme_stylebox_override("panel", plate)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(col)

		var icon_path := "res://assets/icons/relics/%s.png" % rid
		if ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.texture = load(icon_path)
			icon.custom_minimum_size = Vector2(72, 72)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(icon)

		var nm := _make_display_label(String(rd.get("name", rid)), 21, GILT_BRIGHT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)

		var body := _make_display_label(String(rd.get("desc", "")), 18,
			GameTheme.DESC_DIM)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(body)

		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_ALL
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_on_blessing_card_pick_pressed.bind(
			wrapper, on_pick, rid))
		wrapper.add_child(click_btn)
		row.add_child(wrapper)
		GameTheme.deal_in(wrapper, 0.08 + pick_i * 0.055)
		GameTheme.hover_lift(wrapper, 1.025)
		pick_i += 1
