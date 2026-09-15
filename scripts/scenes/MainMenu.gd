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
const MENU_MOTION_STEP := 1.0 / 30.0
var _menu_motion_accumulator := 0.0
var _menu_motion_suspended := false
var _subscreen_obscures_motion := false
var _how_to_play_overlay: Control = null

# THE MUSTER's shared panes. `_hero_detail` is THE COLUMN — rebuilt per focused
# lord by _build_muster_roll on every step that draws it. The roster row itself
# stays down to portrait + name + tagline; THE COLUMN carries the loadout.
var _hero_detail: VBoxContainer = null
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


# One-screen Muster state. Every choice stays local and reversible until TAKE
# THE FIELD; only then are pending fields handed to RunState and consumed.
var _selected_banner_tribe: String = BannerDB.DEFAULT_BANNER
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
var _muster_banner_buttons: Dictionary = {}
var _muster_writ_buttons: Dictionary = {}
var _muster_writ_row: HBoxContainer = null
var _muster_campaign_label: Label = null
var _muster_gloss_label: Label = null
var _muster_order_term_detail: VBoxContainer = null
var _muster_setup_preset: Dictionary = {}
var _writ_resolution_rng: RandomNumberGenerator = null
var _quick_march_active: bool = false
var _quick_march_stage: int = 1
var _muster_advanced_open: bool = false


## The dotted run between a dossier caption and its figure — the leader a
## ledger or a printed dispatch uses to carry the eye across to the number.
## Expands to eat whatever width is left between the two labels.
class DotLeader extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(24, 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var y := size.y * 0.5 + 3.0
		var x := 3.0
		var strokes := PackedVector2Array()
		while x < size.x - 3.0:
			# Batch the tiny ledger dots instead of submitting one circle per mark.
			strokes.append(Vector2(x - 0.55, y))
			strokes.append(Vector2(x + 0.55, y))
			x += 6.0
		if not strokes.is_empty():
			draw_multiline(strokes, Color(0.72, 0.62, 0.42, 0.40), 1.8, true)


func _ready() -> void:
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
	_animate_intro()


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
	# Same restore for the banner: it is a declaration, not an unlock, so there is
	# no gate to check — normalize and carry it. A missing key (an old save-era
	# request) falls back to the default banner rather than to "" so the opener is
	# always exactly 11 cards.
	_selected_banner_tribe = BannerDB.normalize(String(req.get("banner_tribe", "")))
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
	# Hand the restored picks to THE MUSTER and open on the last step, rather than
	# committing here. Calling _begin_run_with directly skipped the only two things
	# _show_hero_select does that a run cannot start without:
	#
	#   * the SEED. _pending_run_seed falls through to _muster_random_seed, whose
	#     declaration default is 1 and which is randomised nowhere else — so every
	#     MARCH AGAIN on every profile ran seed 1: the same act 1 map, the same
	#     rival deal, the same season, forever.
	#   * the TERMS. _muster_writ_slate is only filled by _refresh_muster_deals, so
	#     `chosen` came back empty and _begin_run_with faded straight to the map. A
	#     rematch silently forfeited the whole of step III.
	#
	# Landing on step III rather than committing blind is also the honest shape:
	# the terms are dealt off a NEW seed, so they are not the ones the player just
	# marched under and cannot be carried over. One click, and the rail is live if
	# they want to change lord or colours too.
	_muster_setup_preset = {
		"hero": hero_id,
		"banner_tribe": _selected_banner_tribe,
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
	if UserSettings != null and UserSettings.reduce_motion:
		return
	# One frame so the VBox has laid the children out and rest positions exist.
	await get_tree().process_frame
	if not is_instance_valid(col):
		return
	var i := 0
	for child in col.get_children():
		if not (child is Control):
			continue
		var c := child as Control
		var rest_x := c.position.x
		c.modulate.a = 0.0
		c.position.x = rest_x - 16.0
		var tw := c.create_tween()
		tw.tween_interval(0.05 + i * 0.045)
		tw.tween_property(c, "modulate:a", 1.0, 0.26).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "position:x", rest_x, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		i += 1


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
	btn.button_down.connect(func() -> void: scale_to.call(hover_scale * 0.955, 0.06))
	btn.button_up.connect(func() -> void: scale_to.call(hover_scale, 0.10))


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

	var normal := GameTheme.make_panel_style(
		Color(0.115, 0.062, 0.030, 0.92), Color(0.78, 0.60, 0.30, 0.78),
		2, 5, false)
	var hover := GameTheme.make_panel_style(
		Color(0.20, 0.105, 0.042, 0.97), GILT_BRIGHT, 2, 5, true)
	var pressed := GameTheme.make_panel_style(
		Color(0.085, 0.048, 0.026, 0.98), Color(0.86, 0.68, 0.34),
		2, 5, false)
	for style in [normal, hover, pressed]:
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 6
		style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("pressed", pressed)

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
	lbl.add_theme_constant_override("outline_size", 4)
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

	var summary := RunState.get_slot_summary(slot)
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

	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(maxf(2.0, left_w), 2)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = Color(GILT.r, GILT.g, GILT.b, 0.55)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(maxf(2.0, width - spent - left_w), 2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if stretch:
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.color = Color(GILT.r, GILT.g, GILT.b, 0.55)
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
	var st := GameTheme.make_panel_style(
		Color(0.045, 0.034, 0.027, 0.78),
		Color(0.70, 0.58, 0.35, 0.58),
		1, 6, true)
	st.content_margin_left = DOSSIER_PAD
	st.content_margin_right = DOSSIER_PAD
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
	var sub_text := "saved progress" if has_any_save else "start a new run"
	var sub := _make_caption_label(sub_text, 15,
		Color(0.82, 0.74, 0.58))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hstack.add_child(sub)

	root.add_child(_make_ornament_row(DOSSIER_INNER, true))

	if has_any_save:
		# Ruled figures, not nested boxes: a dispatch prints a value against a
		# dotted leader. The old two-panels-inside-a-panel stack read as UI
		# furniture stacked on UI furniture, and buried the numbers a returning
		# player actually opens the game to see.
		var s := _slot_summary(_most_recent_slot())
		_dossier_row(root, "ACT", str(int(s.get("act", 1))), GILT_BRIGHT)
		_dossier_row(root, "PROVINCE", str(int(s.get("floor", 0))), GILT_BRIGHT)
		_dossier_row(root, "HEALTH", "%d / %d" % [
			int(s.get("hp", 0)), int(s.get("max_hp", 30))],
			Color(0.92, 0.62, 0.52))
		_dossier_row(root, "GOLD", "%dg" % int(s.get("gold", 0)),
			Color(0.92, 0.78, 0.46))
	else:
		var pitch := _make_display_label(
			"Choose a hero, build a deck, and fight across three acts.",
			16, IVORY)
		pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		root.add_child(pitch)

	root.add_child(_make_ornament_row(DOSSIER_INNER, true))

	var foot_text := "Press Continue to resume." if has_any_save \
		else "Press New Run to begin."
	var foot := _make_display_label(foot_text,
		15, Color(0.78, 0.72, 0.60))
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(foot)


## One ruled figure in the dossier: caption left, value right, joined by a
## dotted leader.
func _dossier_row(parent: VBoxContainer, caption: String, value: String,
		accent: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _make_caption_label(caption, 15, Color(0.74, 0.66, 0.52))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(cap)
	row.add_child(DotLeader.new())
	var val := _make_display_label(value, 19, accent)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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


func _show_load_screen(overwrite_mode: bool) -> void:
	_set_subscreen_motion_obscured(true)
	# Standalone screen showing all 3 slots with full continue/delete (normal
	# mode) or "begin new run here" (overwrite mode) actions. Replaces the
	# main menu column in place so the background atmosphere persists.
	_remove_command_dossier()
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	for child in menu.get_children():
		child.queue_free()
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
	for child in menu.get_children():
		child.queue_free()
	_hide_deck_preview()
	_hide_deck_inspector()
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_banner_buttons.clear()
	_muster_writ_buttons.clear()
	_quick_march_active = true
	_muster_advanced_open = false
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
	_selected_banner_tribe = BannerDB.DEFAULT_BANNER
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
	for child in menu.get_children():
		child.queue_free()
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
	for child in menu.get_children():
		child.queue_free()
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
	for child in _hero_detail.get_children():
		child.queue_free()
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
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
		Color(0.02, 0.015, 0.012, 0.5), _faction_accent(hid), 2, 4, true))
	frame.clip_contents = true
	frame.add_child(portrait)
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
		var relic := RelicDB.get_relic(relic_id)
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
		"banner_tribe": _selected_banner_tribe,
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
	for child in menu.get_children():
		child.queue_free()
	_hide_deck_preview()
	_hide_deck_inspector()
	_quick_march_active = false
	_muster_advanced_open = false
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_banner_buttons.clear()
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
	_selected_banner_tribe = BannerDB.normalize(String(
		preset.get("banner_tribe", BannerDB.DEFAULT_BANNER)))
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


## THE MUSTER is four steps, not one screen. They are ordered by dependency:
## the host brings ten cards, the banner adds the eleventh, and the terms are
## weighed against the column those two produced. State lives on the object, so
## stepping back and forth is free and nothing commits until TAKE THE FIELD.
func _show_muster_step(step: int) -> void:
	_set_subscreen_motion_obscured(true)
	var menu := get_node_or_null("Menu")
	if menu == null:
		return
	_muster_step = clampi(step, 1, 4)
	_hide_deck_preview()
	for child in menu.get_children():
		child.queue_free()
	# Every per-step node reference dies with the screen. Consumers all guard
	# with is_instance_valid, but a stale entry in these maps would keep a freed
	# button alive in _focus_hero's sweep.
	_hero_cards.clear()
	_hero_portraits.clear()
	_muster_banner_buttons.clear()
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

	# ONE RECT FOR ALL FOUR STEPS, AND THE CHROME IS NAILED TO IT (2026-08-03).
	# The height used to be picked per step (864 on I/II, 846 on III) against a
	# CENTER-aligned column, so where the title and the step rail LANDED was a
	# function of how tall that step's content happened to be. Measured on the
	# rendered frames: the title sat at y=178 on step I, 158 on II, 318 on III and
	# 258 on IV. The one piece of furniture whose whole job is to say "you are
	# here, and here is the rest of the walk" jumped 160px while you walked it, so
	# every step arrived as a new screen rather than as the next page of one.
	#
	# One rect for everything, and each step hands its slack to a `Slack` spacer
	# (see _muster_slack) instead of to the column's centring. Fixed header, fixed
	# commit row at the foot, elastic middle — so the rail is a rail.
	#
	# 780, not the old 864. Once the steps stop floating, the rect stops being a
	# floor to clear and becomes the actual page: every pixel of it is now real
	# margin somewhere. The tallest step (I, whose two panes ask for 452 plus the
	# head furniture and the nav row) needs ~622, and 780 leaves that step ~90 of
	# growth in the panes while giving THE TERMS — one 196px row on an otherwise
	# empty page — a body band it can sit in the middle of rather than 400px of
	# bare canvas below the deepest thing on screen.
	# 840, not 780. The frameless pass gave the hero a portrait plate and a 30px
	# name, and the extra height pushed START RUN off the bottom of the canvas —
	# the commit button, clipped. 840 centred in 900 leaves a 30px margin each side.
	#
	# MORE RUN OPTIONS opens INLINE on this screen (it had a page to itself while
	# the muster was a wizard), and it adds three rows: the Daily/seed controls,
	# the ascension rules line, and the term gloss above them. That is ~40px more
	# than the collapsed slack can absorb, and the overflow lands on START RUN
	# again. The rect grows with the disclosure rather than reserving the space
	# permanently, so the closed screen — the one nearly every player sees — keeps
	# its margin.
	_center_menu_for_subscreen(1540.0, 884.0 if _muster_advanced_open else 840.0)
	menu.add_theme_constant_override("separation", 8)
	var title := _make_display_label(WritDB.muster_copy("title"), 31, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	# (The four-chip step rail stood here until 2026-09-14. THE MUSTER is one
	# screen now, so there is no walk to narrate — see _build_muster_screen.)
	# TWO LINES OF HEAD FURNITURE, NOT FOUR (2026-08-01). Every step opened on a
	# title, the rail, a per-step instruction and the standing promise — four
	# stacked centred lines, ~170px of the canvas, before a single decision. And
	# they are not the fine print the sizes suggest: _make_display_label floors at
	# GameTheme.MIN_LABEL_SIZE, so the "16" instruction and the "15" promise both
	# render at 18 and read as loud as each other.
	#
	# Both cut lines were saying something already on screen:
	#   STEP I — "Who leads the march, and the company that marches with them" is
	#   a gloss of the two panel headings directly beneath it, THE HOST and THE
	#   COLUMN.
	#   STEP II — "Declare your colours. One of them falls in with you now, and
	#   more of them will find you on the road" is a near-verbatim restatement of
	#   banner_rule_text, which that step prints under its own chips ("Whichever
	#   you raise: one of its own joins your opening deck now, and its kind turns
	#   up more often at every Recruit Camp"). The same sentence twice on one
	#   screen, forty words apart.
	#   STEP III keeps its line: "Accept one term" is the pick-ONE rule of the
	#   row, and no tile states it — the tiles each state their own slot.
	#
	# The promise is not deleted, it MOVES (see _build_muster_nav): it is the
	# sentence that makes BACK and the rail safe to press, so it belongs beside
	# those buttons rather than at the top of a screen whose buttons are at the
	# bottom. Net height is unchanged on step III and one line shorter on I/II,
	# so the reserved rects above still centre honestly.
	#
	# THE INSTRUCTION IS NOT HEAD FURNITURE (2026-08-04). Step III's desc used to
	# be appended HERE, above `_build_muster_step_terms`'s leading slack — measured
	# on the canvas, the rail's hairline ended at y 162.5, "Accept one term." ran
	# 176.7-195.0, and the four tiles it instructs began at 304.2. Fourteen pixels
	# to the rail against a hundred and nine to the row: it read as a subtitle of
	# the rail, which is the one thing on the screen it is not about. It is built
	# inside the step now, below the slack, so it travels with its row.
	_build_muster_screen(menu)
	_animate_subscreen_reveal(menu)


## THE MUSTER IS ONE SCREEN (2026-09-14).
##
## It was four, walked in dependency order: host → banner → terms → review. The
## SPLIT was the defect, not the content. Four decisions do not earn a wizard —
## the form literature puts the break-even at seven-plus steps and calls the
## extra Next clicks pure overhead below that — and the genre's own benchmark
## puts character, ascension and seed on ONE screen with the modifiers in a
## corner. Hick's law counts TOTAL options, not options-per-screen, so spreading
## four choices over four pages reduced nothing; it added three clicks and a rail
## carrying eight strings of navigation chrome.
##
## Two symptoms proved the split was load-bearing waste. Both are gone now
## rather than relocated, which is the test of whether a merge was real:
##
##   THE DECK STRIP WAS BUILT THREE TIMES. Step II's own comment said why: "a
##   chip that says so while the opener is on another screen is a claim the
##   player cannot check." With the banner chips standing beside THE COLUMN, the
##   banner's card lands in the one live strip as you press it.
##
##   STEP IV EXISTED ONLY TO UNDO STEPS I-III. A review page that restates
##   choices the player made ninety seconds ago is the standard tell of an
##   over-split flow — it is the split apologising for itself.
##
## Three panes across the main row, because that is what puts each choice beside
## the thing it changes: the roster picks the lord, THE COLUMN shows what he
## brings, the banner chips add the eleventh card to it. THE TERMS run full width
## beneath (four 340px tiles need 1396 of the 1516 available), and the run
## controls sit in the footer. Measured total: 730 inside the 780 rect.
func _build_muster_screen(menu: VBoxContainer) -> void:
	var main_row := HBoxContainer.new()
	# 416: the deepest pane is THE BANNER — six 64px chips is 384, plus the
	# section's caption and rule (~29). Twenty shorter than the framed version,
	# which had to pay for the panel's content margins as well.
	main_row.custom_minimum_size = Vector2(0, 416)
	main_row.add_theme_constant_override("separation", 16)
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(main_row)

	var host := _make_muster_section(main_row,
		WritDB.muster_copy("host_head_text"), 430.0)
	host.add_theme_constant_override("separation", 4)
	for hid in HeroDB.HERO_ORDER:
		var row := _make_muster_host_row(hid)
		host.add_child(row)
		GameTheme.hover_lift(row, 1.012)

	var column := _make_muster_section(main_row,
		WritDB.muster_copy("column_head_text"), 700.0, true)
	_hero_detail = VBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 6)
	_hero_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_hero_detail)

	# 296: the chips carry their own 270px minimum plus the section's 24px of
	# margin. They keep their full rule line at that width, which is why the
	# banner sits in this row rather than as a strip beneath — six chips laid
	# across the page would have to drop to 244 and ellipsise every verb.
	var banners := _make_muster_section(main_row,
		WritDB.muster_copy("banner_head_text"), 296.0)
	banners.add_theme_constant_override("separation", 2)
	for bid in BannerDB.BANNER_ORDER:
		var chip := _make_muster_banner_chip(bid)
		banners.add_child(chip)
		GameTheme.hover_lift(chip, 1.012)
		_muster_banner_buttons[bid] = chip

	# ── THE FOURTH DECISION WEARS THE SAME UNIFORM AS THE OTHER THREE ──
	#
	# The terms row used to be introduced by a CENTRED SENTENCE with no rule under
	# it, while the three panes above carried left-aligned small-caps captions over
	# a hairline. Two labelling systems on one screen, and the odd one out was the
	# row carrying the single most consequential pick on the page — so it read as
	# an aside rather than as a peer of the hero and the banner. Same caption, same
	# rule, same left edge; the pick-ONE rule rides inside the caption because no
	# tile states it.
	var terms := _make_muster_section(menu,
		WritDB.muster_copy("terms_step_desc_text"), MUSTER_STRIP_WIDTH_FULL, true)
	# _make_muster_section hands every section EXPAND_FILL so it can share a row's
	# height; here it is stacked in the menu's own VBox, where expanding would eat
	# the slack that keeps START RUN off the canvas edge.
	terms.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_muster_writ_row = HBoxContainer.new()
	_muster_writ_row.custom_minimum_size = Vector2(0, 150)
	_muster_writ_row.add_theme_constant_override("separation", 12)
	_muster_writ_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terms.add_child(_muster_writ_row)

	# The gloss belongs TO the row it defines, and on its left edge. It was the
	# last centred prose on an otherwise left-aligned page, floating under a
	# full-width row with nothing to anchor it — the same alignment split that
	# made the terms caption read as an aside, one element further down. Parented
	# into the terms section so it sits on the caption's own margin, and dimmer
	# than the tiles, because a definition is footnote weight beside the four
	# offers it footnotes.
	_muster_gloss_label = _make_caption_label("", 15, Color(0.62, 0.57, 0.48))
	_muster_gloss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_muster_gloss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terms.add_child(_muster_gloss_label)

	var hero := _selected_hero if HeroDB.has_hero(_selected_hero) \
		else HeroDB.HERO_ORDER[0]
	# _focus_hero clears the doctrine toggles, which is right when the player
	# picks a DIFFERENT lord and wrong when a rebuild merely repaints this one.
	_normalize_muster_doctrine(String(hero))
	_selected_hero = ""
	_focus_hero(String(hero), true)
	_refresh_muster_banner_styles()
	_refresh_muster_deals()

	_muster_slack(menu)
	_build_muster_footer(menu)

	var hero_focus = _hero_cards.get(String(hero))
	if hero_focus != null and is_instance_valid(hero_focus):
		hero_focus.call_deferred("grab_focus")


## The run controls and the commit share the footer. Ascension, seed and Daily
## Run are MODIFIERS, not build choices — they stay collapsed behind MORE RUN
## OPTIONS, so the default path from opening this screen to marching is one
## press. BACK is the only other exit and nothing commits until START RUN, which
## is what the rail's travelling promise used to have to explain.
func _build_muster_footer(menu: VBoxContainer) -> void:
	_build_muster_settings(menu)
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
func _make_opener_art_strip(opener: Array[String], banner_card: String) -> Control:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in opener:
		var id := String(cid)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	# The banner's card LEADS, so pressing a banner chip visibly changes the head
	# of the strip instead of shuffling something into the middle of it.
	if banner_card != "" and banner_card in order:
		order.erase(banner_card)
		order.push_front(banner_card)
	# SIX ACROSS, NOT ELEVEN — and the tiles are LANDSCAPE. The first cut laid one
	# rank of portrait tiles at the card's own 3:4, which was wrong twice over:
	# card art ships 3:2 LANDSCAPE (768×512), so covering a portrait tile with it
	# crops to the middle 50% of the painting's width, and the middle of a
	# painting is very often its background. Measured on the rendered strip:
	# eleven tiles of sky, mud and foliage with not one recognisable subject in
	# them — which looks exactly like a broken image loader.
	#
	# Two ranks of six at the art's OWN aspect crops nothing, and the tile grows
	# from 65×87 to ~113×75, so the thing the player is being shown is the whole
	# picture rather than a core sample of it.
	var grid := GridContainer.new()
	grid.columns = OPENER_STRIP_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var cols: float = float(OPENER_STRIP_COLUMNS)
	var tile_w: float = (OPENER_STRIP_WIDTH - 6.0 * (cols - 1.0)) / cols
	for id in order:
		grid.add_child(_make_opener_art_tile(String(id), int(counts[id]),
			tile_w, String(id) == banner_card))
	return grid


## One art tile. A Control with the painting inside it and the frame drawn OVER
## it: PanelContainer would inset the art by its own content margins, and
## clip_children is inert on gl_compatibility (so the art cannot be trimmed to a
## rounded plate). STRETCH_KEEP_ASPECT_COVERED does the cropping instead — it
## clips to the node's own rect by definition.
func _make_opener_art_tile(id: String, count: int, w: float,
		is_banner: bool) -> Control:
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
	# The banner's card wears the gilt edge — the one tile on the strip that the
	# chip column to the right is responsible for.
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
		Color(0, 0, 0, 0.0),
		Color(0.80, 0.62, 0.28, 0.92) if is_banner else Color(0.50, 0.43, 0.31, 0.66),
		2 if is_banner else 1, 3, false))
	slot.add_child(frame)
	if count > 1:
		var chip := _make_display_label("×%d" % count, 15, GILT_BRIGHT)
		chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		chip.add_theme_constant_override("outline_size", 6)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(chip)
		chip.size = Vector2(30, 20)
		chip.position = Vector2(w - 31.0, 2.0)
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
	return slot


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
	btn.custom_minimum_size = Vector2(400, 84 if _quick_march_active else 66)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 5
	row.offset_right = -5
	row.offset_top = 3
	row.offset_bottom = -3
	row.add_theme_constant_override("separation", 8)
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
	portrait.custom_minimum_size = Vector2(58, 78) if _quick_march_active \
		else Vector2(46, 62)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	_hero_portraits[hid] = portrait
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	if _quick_march_active:
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
	var name_label := _make_display_label(String(hero.get("name", hid)), 21, GILT_BRIGHT)
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


func _make_muster_banner_chip(bid: String) -> Button:
	var data := BannerDB.get_banner(bid)
	var btn := Button.new()
	# 56, not 48: the chip stacks a name over a one-line rule, and at 48 the
	# selected chip's highlight cut across the rule exactly like the host rows.
	btn.custom_minimum_size = Vector2(270, 64)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var copy := VBoxContainer.new()
	copy.set_anchors_preset(Control.PRESET_FULL_RECT)
	copy.offset_left = 10
	copy.offset_right = -8
	copy.offset_top = 3
	copy.offset_bottom = -3
	copy.add_theme_constant_override("separation", 0)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(copy)
	# THE NAME OUTRANKS ITS OWN RULE (2026-08-03). BannerDB's colours are heraldic
	# dyes — The Works is a flat grey, The Roll a dark brown — and at a 45% wash
	# they landed around 0.62 luminance UNDER a rule line printed in full IVORY.
	# So on every chip the small print was the brightest thing in it and the eye
	# read six rules before it read a single tribe. The dye still carries the
	# identity (the hue survives the wash toward ivory, which is why it is not
	# lerped toward gilt), it just stops losing to its own body text: name up to
	# a floor, rule down to the standard description ink.
	var accent: Color = data.get("color", GILT)
	# 0.86, not 0.74 — and lifted with _lift_to_luminance, not `lightened()`.
	# The first cut of this fix set the floor to 0.74 and the rule line to
	# GameTheme.DESC_DIM, whose luminance is 0.7399. The floor WAS the body text,
	# to three decimals, so the "hierarchy" it bought was a dead tie. And
	# `lightened(a)` is `c + (1-c)*a` per channel, which moves luminance by about
	# `(1-lum)*a` — passing the raw difference as the amount undershoots the
	# target every time, so two of the six tribes still came out UNDER their own
	# small print (The Hunt 0.730, The Coven 0.722, against a 0.741 rule).
	var tint: Color = _lift_to_luminance(accent.lerp(IVORY, 0.62), 0.86)
	var name_label := _make_display_label(String(data.get("name", bid)), 20, tint)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	copy.add_child(name_label)
	# ── ONLY THE RAISED BANNER EXPLAINS ITSELF (2026-09-15) ──
	#
	# All six chips printed their verb at once: six names over six full sentences,
	# in a column 296px wide, when at most ONE of those sentences can be true of
	# the run being built. It was also the third printing of the same fact — the
	# chosen banner's card already leads the deck strip wearing a gilt edge, and
	# the roll line above the strip names it outright.
	#
	# Held on the button and toggled by _refresh_muster_banner_styles, so the
	# column reads as five quiet names and one raised colour with its rule under
	# it. The list reflows deliberately: the selected chip is TALLER, which is the
	# cheapest possible "you are here" and costs no extra ink at all.
	var line := _make_display_label(String(data.get("line_text", "")), 15,
		GameTheme.DESC_DIM)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.name = "BannerRule"
	copy.add_child(line)
	btn.tooltip_text = "%s adds %s to your starting deck." % [
		String(data.get("tribe", bid)),
		String(CardDB.get_card_data(String(data.get("card_id", ""))).get(
			"name", WritDB.muster_copy("banner_card_fallback_text")))]
	btn.pressed.connect(_select_muster_banner.bind(bid))
	_arm_shell_button(btn, "select")
	return btn


func _select_muster_banner(bid: String) -> void:
	if not BannerDB.has_banner(bid):
		return
	_selected_banner_tribe = bid
	_refresh_muster_banner_styles()
	# Rebuild THE COLUMN itself rather than a separate summary block. The
	# banner's entire effect is one card joining the opener, and on a single
	# screen the player can watch it land at the head of the live strip — which
	# is the thing the three duplicated deck strips were imitating from two pages
	# away, and the reason they existed at all.
	if _selected_hero != "":
		_build_muster_roll(_selected_hero)
	_refresh_muster_campaign()


func _refresh_muster_banner_styles() -> void:
	for bid in _muster_banner_buttons:
		var btn: Button = _muster_banner_buttons[bid]
		if not is_instance_valid(btn):
			continue
		var selected := String(bid) == _selected_banner_tribe
		# The rule line belongs to the raised banner alone — see the note in
		# _make_muster_banner_chip. The chip shrinks with it, so an unraised
		# colour costs one line of ink instead of two.
		var rule := btn.find_child("BannerRule", true, false) as Label
		if rule != null:
			rule.visible = selected
		btn.custom_minimum_size.y = 64.0 if selected else 38.0
		var style: StyleBox = _hero_focus_box() if selected else StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, style)
		# The selected chip's focus slot carries the underline WITHOUT the wash —
		# see _hero_selected_focus_box; the focus box composites over the state
		# box, so repeating the fill here is what doubled it into a plate.
		btn.add_theme_stylebox_override("focus",
			_hero_selected_focus_box() if selected else _hero_cursor_box())


## `compact` drops the hero heading, the pitch and the signature block and keeps
## only the line and the cards. Step III needs the DECK on screen to price its
## terms, but it does not need a third printing of a lord the player chose two
## screens ago — and it has no vertical room for one.
func _build_muster_roll(hid: String, compact: bool = false) -> void:
	if _quick_march_active:
		if _quick_march_stage == 1:
			_build_quick_hero_identity(hid)
		else:
			_build_quick_march_roll(hid)
		return
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	_hide_deck_preview()
	for child in _hero_detail.get_children():
		child.queue_free()
	var hero := HeroDB.get_hero(hid)
	# Where the roll line and the deck strip land. On the full pane they go in the
	# column BESIDE the portrait, which is what lets the hero plate be tall without
	# pushing anything off the canvas — a portrait stacked ABOVE the text costs its
	# own height twice over. Compact keeps the old single stack.
	var pane: VBoxContainer = _hero_detail
	if not compact:
		# The lord's nameplate, with his CAMPAIGN RECORD hung off the far end of the
		# same row. On the same row on purpose: THE COLUMN's height is spent to the
		# last pixel by the two-rank card strip and the signature block below it, so
		# a record on its own line would have to push something off the canvas. The
		# heading row is the one piece of furniture on this pane with empty space to
		# its right.
		# ── THE HERO GETS A FACE (2026-09-15) ──
		#
		# This pane named the lord in 22px type and showed nothing of him. The
		# only portrait on the screen was the 52px thumbnail in the roster, so on
		# a screen titled RUN SETUP the hero carried less visual weight than one
		# card tile in his own deck — the focal point inverted. Every game in the
		# genre gives the chosen thing presence: Slay the Spire stands the
		# character up, Hades stands the weapon up. A 96px plate beside a 30px
		# name is what makes this pane about a PERSON rather than about a list.
		# Typed BoxContainer, not HBoxContainer: the record line below is appended
		# to `head_row`, and the name column takes that role once it exists so the
		# record sits under the name rather than beside the portrait.
		var head_row: BoxContainer = HBoxContainer.new()
		head_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_row.add_theme_constant_override("separation", 16)
		_hero_detail.add_child(head_row)
		var portrait_path := "res://assets/portraits/hero_portrait_%s.png" % hid
		if ResourceLoader.exists(portrait_path):
			# 180×248, not 96×96. A square thumbnail beside a name is an AVATAR; a
			# tall plate is a PORTRAIT, and that is the difference between a pane
			# that reads as a row in a list and one that reads as the hero you are
			# about to play. It costs no vertical space at all, because everything
			# that used to sit UNDER it now sits to the RIGHT of it.
			# 216×287 is the portrait's OWN 3:4 (the files are 928×1232), so COVERED
			# crops essentially nothing — and the height is chosen to finish level
			# with the deck strip beside it, so the plate spans its whole column
			# instead of stopping half way down and leaving a notch.
			var plate := Control.new()
			plate.custom_minimum_size = Vector2(216, 287)
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
			# EXPAND_IGNORE_SIZE or the node claims the texture's full size as its
			# minimum and the anchors never bring it down — the trap the opener
			# strip was built through.
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clip.add_child(face)
			var edge := Panel.new()
			edge.set_anchors_preset(Control.PRESET_FULL_RECT)
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			edge.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
				Color(0, 0, 0, 0.0), _faction_accent(hid), 1, 3, false))
			plate.add_child(edge)
			head_row.add_child(plate)
		# This is the whole RIGHT-HAND COLUMN, not just the nameplate: the name,
		# the record, the pitch, the roll line and the deck strip all live in it,
		# so the portrait can stand the full height of the pane beside them.
		var name_col := VBoxContainer.new()
		name_col.add_theme_constant_override("separation", 4)
		name_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_row.add_child(name_col)
		# 30, not 22. This is the loudest word on the screen by intent — the page
		# title is chrome, the section captions are labels, the lord is the answer.
		var heading := _make_display_label(String(hero.get("name", hid)), 30,
			_faction_accent(hid))
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_col.add_child(heading)
		head_row = name_col
		pane = name_col
		# (A "RECOMMENDED FIRST HERO" chip stood here until 2026-08-03. It was
		# gated on `_quick_march_active`, and this function returns to the quick
		# builders at its FIRST LINE whenever that flag is set — so the branch was
		# unreachable by construction and had never drawn a pixel. The live chip
		# is in _build_quick_hero_identity, which is the screen it belongs to.
		# Deleting it also settles the head row: it claimed EXPAND_FILL on the
		# same row as the record, which does too, so had it ever fired the two
		# would have split the row and pulled the record off its right edge.)
		# THE RECORD STANDS BESIDE THE NAME IT QUALIFIES (2026-08-04). It used to
		# claim EXPAND_FILL on this row and right-align into it, which on a pane
		# that grew to 1070 put "0 won · 1 lost" 871px from the word "Raider" — at
		# that distance a qualifier is not a qualifier, it is a second, unrelated
		# reading on the far side of the pane. Left-packed after the name with the
		# row's 24px separation, it reads as the appositive it is; the row's
		# remaining width was already empty and stays empty.
		var record := _muster_record_line(hid)
		if record != "":
			var rec_lbl := _make_caption_label(record, 15, Color(0.72, 0.66, 0.54))
			rec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			rec_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rec_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head_row.add_child(rec_lbl)
		var pitch := _make_display_label(String(hero.get("desc", "")), 15,
			GameTheme.DESC_DIM)
		pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pitch.custom_minimum_size = Vector2(0, 36)
		head_row.add_child(pitch)
	var opener: Array[String] = RunState.opening_deck_for(
		hid, _muster_alt_deck, _selected_banner_tribe)
	var banner_card := BannerDB.card_id(_selected_banner_tribe)
	var banner_name := String(CardDB.get_card_data(banner_card).get("name", banner_card))
	# On the terms step the line names the lord and the standing HP instead of the
	# banner's card: THE PACT prices itself at "Lose 6 max HP" and the screen never
	# printed the denominator, so on the first screen a new player ever sees, the
	# one number with a cost attached was 6 out of an unstated total.
	# The line and the action share a row. Both are short and both are ABOUT the
	# strip below them, so stacking them spent two rows of the pane's height on one
	# caption's worth of ink — height the strip now needs.
	var roll_row := HBoxContainer.new()
	roll_row.add_theme_constant_override("separation", 18)
	roll_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_child(roll_row)
	var roll_line := _make_caption_label(
		("%s  ·  %d cards  ·  %d max HP" % [String(hero.get("name", hid)),
			opener.size(), RunState.STARTING_MAX_HP]) if compact
		else ("%d cards  ·  %s adds %s" % [opener.size(),
			BannerDB.display_name(_selected_banner_tribe), banner_name]),
		15, Color(0.76, 0.69, 0.56))
	roll_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	roll_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roll_row.add_child(roll_line)
	# 0, not 218: the tab treatment underlines the control, and a fixed width left
	# ~90px of bare rule running past the last letter. An underline has to be as
	# wide as its word.
	var inspect := _make_secondary_action("VIEW FULL DECK", 0, 34)
	inspect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inspect.tooltip_text = "Open the complete starting deck."
	inspect.pressed.connect(_show_muster_deck_inspector)
	roll_row.add_child(inspect)
	# AS MANY OF THE COLUMN AS THE PANE CAN PRINT, NOT THREE (2026-08-04). The
	# strip was hard-coded to three representative cards, which measured 437px
	# inside a pane measured at 1070 — 633px of a bordered frame holding nothing,
	# and the biggest single contributor to this pane's 68.5% empty ink map. One
	# rank of the full-size card fits SEVEN, so seven is what it asks for, and the
	# height does not move at all: a rank is 186px tall whether it holds three
	# minis or seven. The banner's card leads (see _representative_opening_cards) —
	# display order only, the run's deck is untouched.
	# THE WHOLE OPENER AS ART, not a seven-card sample of baked faces — see
	# _make_opener_art_strip for why the faces had to go (11.2px rules text
	# against an absolute 18px floor that no gate could see).
	pane.add_child(_make_opener_art_strip(opener, banner_card))
	_build_muster_doctrine_row(_hero_detail, hid, hero, compact)


func _build_quick_march_roll(hid: String) -> void:
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	_hide_deck_preview()
	for child in _hero_detail.get_children():
		child.queue_free()
	var hero := HeroDB.get_hero(hid)

	var opener: Array[String] = RunState.opening_deck_for(
		hid, false, _selected_banner_tribe)
	var banner_card := BannerDB.card_id(_selected_banner_tribe)
	var shown: Array[String] = _representative_opening_cards(opener, banner_card)
	_warm_deck_strip(shown, hid)
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
	inspect.tooltip_text = "Open the complete starting deck."
	inspect.pressed.connect(_show_muster_deck_inspector)
	card_head.add_child(inspect)
	var card_center := CenterContainer.new()
	card_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 22)
	for id in order:
		card_row.add_child(_make_deck_mini(id, int(counts[id]), 0.72))
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
	# The caption is READ OFF the banner, not typed: it used to be the literal
	# "THE COLOURS", which is only the name of BannerDB.DEFAULT_BANNER — correct
	# today by coincidence, and a caption naming the wrong banner the moment the
	# default moves or this screen learns to show another one.
	facts.add_child(_make_quick_march_fact(
		BannerDB.display_name(_selected_banner_tribe).to_upper(),
		"Adds %s to your deck" % String(
			CardDB.get_card_data(banner_card).get("name", "one Soldier")),
		Color(0.87, 0.63, 0.39)))
	facts.add_child(_make_quick_march_fact(
		"CAMPAIGN CHEST", "+10 gold after every victory",
		Color(0.94, 0.76, 0.34)))
	_build_muster_doctrine_row(_hero_detail, hid, hero, false)


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


## As much of the opener as the strip can print in ONE rank, banner card first,
## every pick carrying its REAL number of copies.
##
## THE BANNER'S CARD WAS THE ONE CARD THIS EXCLUDED (2026-08-04). The old body
## `continue`d on `banner_card` and appended it only if the deck could not supply
## three others — so on step I the caption read "11 cards · The Colours adds Line
## Marker" directly above a strip in which Line Marker did not appear, and
## _build_muster_roll's own comment ("The banner's card leads the strip") had been
## describing a behaviour the code undid. It leads now, for real.
##
## THE COUNTS WERE ALL LIES (same pass). The result was a unique-id list, and
## _make_muster_deck_strip derives its ×N chips by counting the array it is
## handed — so every chip on every muster strip read "×1", including Outrider,
## which the Raider opens with TWO of. Returning the picks with multiplicity
## makes the chip true without touching the strip.
##
## `want` is a UNIQUE-card budget, not a mini budget: the caller measures how many
## minis its pane can print (see _strip_rank_capacity) and the copies ride along.
func _representative_opening_cards(opener: Array[String],
		banner_card: String, want: int = 3) -> Array[String]:
	var order: Array[String] = []
	if banner_card != "" and opener.has(banner_card):
		order.append(banner_card)
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
	var relic := RelicDB.get_relic(relic_id)
	# The signature relic is HALF of what choosing a lord hands you — the deck is
	# the other half and gets eleven baked cards. It used to be the bare line
	# "SIGNATURE: Marching Spurs" with the rule itself buried in a tooltip, in a
	# panel that had ~100px of empty space under it. Icon, name and rule, printed.
	var chip := GameTheme.make_relic_chip(relic_id, 54)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(chip)
	var sig := VBoxContainer.new()
	sig.add_theme_constant_override("separation", 0)
	sig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sig)
	sig.add_child(_make_caption_label("SIGNATURE RELIC", 15, Color(0.68, 0.61, 0.48)))
	sig.add_child(_make_display_label(String(relic.get("name", relic_id)), 20, GILT_BRIGHT))
	var relic_desc := _make_display_label(String(relic.get("desc", "")), 15,
		GameTheme.DESC_DIM)
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
		var toggle := _make_secondary_action(doctrine_name, 218, 32)
		toggle.tooltip_text = "Switch this hero's starting deck."
		toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
		toggle.pressed.connect(_set_bound_doctrine.bind(hid, not _muster_alt_deck))
		row.add_child(toggle)
		return
	# "ALTERNATE", not "ALT". These two toggles are the only place in the shell
	# that abbreviated a word, and "ALT" beside "STANDARD" reads as a keyboard
	# modifier before it resolves as an adjective (COPY_STYLE §12: no riddles).
	# Both widths grew to hold the longer word rather than clipping it.
	var deck_btn := _make_secondary_action(
		"ALTERNATE DECK" if _muster_alt_deck else "STANDARD DECK", 196, 32)
	deck_btn.tooltip_text = "Switch between this hero's two starting decks."
	deck_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	deck_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	deck_btn.pressed.connect(_toggle_muster_deck.bind(hid))
	row.add_child(deck_btn)
	var relic_btn := _make_secondary_action(
		"ALTERNATE RELIC" if _muster_alt_relic else "STANDARD RELIC", 196, 32)
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


## The march's session settings — difficulty, today's run, the seed. They sit on
## the terms step because that is where their consequences are visible: the four
## tiles are dealt off this seed and re-deal live as it is typed, and the road
## lords printed above are previewed from it.
func _build_muster_settings(parent: VBoxContainer) -> void:
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 5)
	parent.add_child(footer)

	# One term per concept, and every item in this list is written the same way:
	# "Daily" was a clipped form of the button 40px below it (DAILY RUN), and
	# "custom seed" was the only lower-cased entry in a list of three.
	var active: Array[String] = []
	if _selected_ascension > 0:
		active.append("Ascension %d" % _selected_ascension)
	if _daily_pick:
		active.append("Daily Run")
	if _muster_seed_text.strip_edges() != "":
		active.append("Custom seed")
	var advanced_text := "MORE RUN OPTIONS — %s" % (
		"HIDE" if _muster_advanced_open else "SHOW")
	if not active.is_empty():
		advanced_text += "  ·  ACTIVE: %s" % ", ".join(PackedStringArray(active))
	# Hug the label. The width used to be picked from whether any run option is
	# active, because the framed version had to reserve room for the longer
	# "· ACTIVE: …" string; the tab sizes itself to whatever it is actually
	# carrying, so the rule ends where the words do in both states.
	var advanced := _make_secondary_action(advanced_text, 0, 38)
	advanced.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	advanced.tooltip_text = "Optional: change difficulty, Daily Run, or the seed."
	advanced.pressed.connect(_toggle_muster_advanced)
	footer.add_child(advanced)
	if not _muster_advanced_open:
		return
	# _make_menu_button hardcodes EXPAND_FILL, so a plain HBox flung these five
	# controls across the full 1540: the "-" landed against the left screen edge,
	# a hand's width from the ascension number it decrements. Centering the row
	# needs the children to SHRINK, so every control below re-flags itself.
	var setup := HBoxContainer.new()
	setup.alignment = BoxContainer.ALIGNMENT_CENTER
	setup.add_theme_constant_override("separation", 12)
	setup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	footer.add_child(setup)
	# THE LADDER IS NOT DRAWN UNTIL IT HAS A RUNG. Below the first win, the
	# stepper was a permanently disabled "-" and "+" flanking the words
	# "Ascension 0 / 0" — three dead controls in the middle of the commit row on
	# the first screen of a player's first run, next to live build choices they
	# are still trying to read. Every roguelike surveyed either locks its
	# difficulty ladder behind a win (Slay the Spire needs a full three-act
	# clear before A1 exists; Balatro's stakes unlock per deck), defers it to a
	# prompt after run one, or keeps it in a different mode; not one presents an
	# inert difficulty control beside a build offer.
	#
	# The promise still prints — _update_asc_rules_text writes "Take a keep to
	# open the next tier" into the line below — so the ladder is announced
	# without being operable. The label stays null on this path and every
	# consumer already guards with is_instance_valid.
	var asc_unlocked: int = MetaState.unlocked_ascension
	if asc_unlocked > 0:
		var minus := _make_menu_button("-", Color(0.20, 0.16, 0.14), 17, 34)
		minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		minus.custom_minimum_size = Vector2(36, 34)
		minus.pressed.connect(_change_ascension.bind(-1))
		setup.add_child(minus)
		_asc_label = _make_display_label("Ascension %d / %d" % [
			_selected_ascension, asc_unlocked], 15, IVORY)
		_asc_label.custom_minimum_size = Vector2(154, 34)
		_asc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_asc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		setup.add_child(_asc_label)
		var plus := _make_menu_button("+", Color(0.20, 0.16, 0.14), 17, 34)
		plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plus.custom_minimum_size = Vector2(36, 34)
		plus.pressed.connect(_change_ascension.bind(1))
		setup.add_child(plus)

	# Read the live toggle, not just the ledger: the settings block is rebuilt
	# every time the player steps back onto the terms, and a button that reset
	# itself to OFF while _daily_pick stayed true would misreport which seed the
	# run is about to commit.
	# A BLOCKED STATE NAMES THE CAUSE AND THE EFFECT (COPY_STYLE §12). Three of
	# these four labels are on a DISABLED button, and "DAILY RUN — WON" /
	# "— UNAVAILABLE" told the player a fact about the past without ever saying
	# why the control had stopped answering. "TODAY" is the whole cause (one Daily
	# Run per day) and the tooltip carries the effect in a sentence.
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
	_daily_btn = _make_menu_button(daily_text, Color(0.30, 0.24, 0.34), 15, 34)
	_daily_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Measured from the label, not pinned: the blocked states are longer than the
	# ON/OFF pair the old 238 was cut for, and an overrunning label on this row
	# runs straight into the seed field beside it.
	_daily_btn.custom_minimum_size = Vector2(
		maxf(238.0, float(daily_text.length()) * 10.0 + 24.0), 34)
	_daily_btn.tooltip_text = _daily_tooltip()
	_daily_btn.disabled = daily_blocked
	_daily_btn.pressed.connect(_on_daily_button_pressed)
	setup.add_child(_daily_btn)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed (optional)"
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_edit.add_theme_font_size_override("font_size", 16)
	_seed_edit.add_theme_color_override("font_color", IVORY)
	_seed_edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.42))
	_seed_edit.custom_minimum_size = Vector2(188, 34)
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
	setup.add_child(_seed_edit)

	_asc_rules_label = _make_display_label("", 14, Color(0.70, 0.64, 0.53))
	_asc_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_asc_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_asc_rules_label)
	_update_asc_rules_text()


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


func _toggle_muster_advanced() -> void:
	_muster_advanced_open = not _muster_advanced_open
	_show_muster_step(4)



func _make_muster_writ_tile(entry: Dictionary) -> Button:
	var id := String(entry.get("id", ""))
	var btn := Button.new()
	# 136, not 116 (2026-07-30). The terms are the single most consequential
	# choice on this screen — they change your deck, your gear, the road, or cost
	# you max HP — and the longest of them (THE PACT) ellipsised mid-clause at
	# "Lose 6 ma...". A term you cannot finish reading is a term you cannot
	# weigh. One more line, and the height to hold it.
	#
	# 2026-07-31: 178 tall on a step of its own. The 3-line clamp below was
	# doing real work at 136 — with the terms now holding the screen alone there
	# is room for the longest term to print whole, so the clamp is gone rather
	# than merely loosened. (236 was the first try and left every tile two-thirds
	# empty, which reads as a missing element rather than as breathing room.)
	#
	# 2026-08-04: 150. 178 was reproducing 236's fault at a smaller scale —
	# measured, tiles I, II and IV hold 117-121px of content inside a 178px tile
	# forced up to 196 by the row, so roughly two fifths of each was empty. The
	# tallest thing the row must hold is THE ARSENAL's four lines (eyebrow 24 +
	# name 29 + desc 24 + offer 20, plus 6 of separation and 14 of margin = 117),
	# and 150 clears that with a real margin rather than a hole.
	btn.custom_minimum_size = Vector2(340, 150)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = String(entry.get("desc", ""))
	var copy := VBoxContainer.new()
	copy.set_anchors_preset(Control.PRESET_FULL_RECT)
	copy.offset_left = 12
	copy.offset_right = -12
	copy.offset_top = 7
	copy.offset_bottom = -7
	copy.add_theme_constant_override("separation", 2)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(copy)
	var slot := String(entry.get("slot", ""))
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	copy.add_child(slot_row)
	var slot_label := _make_caption_label("%s — %s" % [
		String(WritDB.SLOT_LABELS.get(slot, "")),
		String(WritDB.SLOT_HINTS.get(slot, ""))], 15,
		Color(0.88, 0.48, 0.40) if bool(entry.get("is_pact", false)) else GILT)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(slot_label)
	# ── THE ACCEPTED TERM IS SEALED, NOT LABELLED (2026-08-05) ──
	# This was the word "CHOSEN" in 15px gilt in the tile's top-right corner —
	# on the one screen in the game where a wax seal is the literally correct
	# object. These tiles are dealt by WritDB, the copy calls them TERMS, and
	# the game's own cards are "illuminated writs" whose stats are pressed wax.
	# `WaxSeal` has been in scripts/ui/painters/ since the backend restructure
	# and is the house's visual verb for *this is now binding*.
	#
	# ★3 (SIZE) passes with room to spare: a 34px seal on a 340px tile. The
	# word is KEPT as the seal's tooltip and as its accessible name — a mark
	# nobody can read is a worse affordance than a label, and the copy-lint /
	# text-floor gates are entitled to find the string.
	var chosen_marker := Control.new()
	chosen_marker.name = "TermChosenMarker"
	chosen_marker.custom_minimum_size = Vector2(TERM_SEAL, TERM_SEAL)
	chosen_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chosen_marker.tooltip_text = "Your chosen bonus."
	chosen_marker.visible = false
	var seal := WaxSeal.new()
	seal.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The PACT is the tile that prices itself in max HP; it seals in the same
	# crimson its own slot label already warns in, so the mark inherits the
	# tile's argument instead of contradicting it in gilt.
	seal.wax = Color(0.62, 0.15, 0.12) if bool(entry.get("is_pact", false)) \
		else Color(0.54, 0.13, 0.10)
	seal.seed_text = "term-%s" % String(entry.get("id", slot))
	chosen_marker.add_child(seal)
	# THE SEAL BEARS A DEVICE. WaxSeal draws an IMPRESSION — a sunk dark face
	# with a lit far wall — because on a card that recess holds the stat numeral;
	# its own header calls this "the numeral-legibility contract". Pressed with
	# nothing in it, the recess reads as a hole and the whole mark as a washer
	# (caught on the first render of this change). The slots are already numbered
	# in Roman on their own labels, so the seal bears the numeral of the term it
	# closed — and THE PACT, which deliberately carries no numeral, takes the
	# house diamond instead.
	var device := Label.new()
	device.text = "◆" if bool(entry.get("is_pact", false)) \
		else String(WritDB.SLOT_LABELS.get(slot, "")).split(" ")[0]
	device.set_anchors_preset(Control.PRESET_FULL_RECT)
	device.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	device.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	device.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		device.add_theme_font_override("font", GameTheme.font_display)
	device.add_theme_font_size_override("font_size", 14)
	device.add_theme_color_override("font_color", Color(1.0, 0.90, 0.76, 0.94))
	chosen_marker.add_child(device)
	slot_row.add_child(chosen_marker)
	var name_label := _make_display_label(String(entry.get("name", "")), 22, IVORY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	copy.add_child(name_label)
	# NO EXPAND_FILL ON THE DESC (2026-08-04). It carried it, so the description
	# absorbed the whole tile's slack and drove the relic preview down onto the
	# tile floor — a ~50px gap between "Choose 1 of 3 relics." and the three relic
	# names, which then read as an unlabelled list rather than as that sentence's
	# answer. The question and its answer are adjacent now; the slack goes to a
	# spacer AFTER the last written line, where empty space is margin.
	var desc := _make_display_label(String(entry.get("desc", "")), 16, GameTheme.DESC_DIM)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(desc)
	# THE ARSENAL used to be the one BLIND tile standing beside three transparent
	# ones: "Choose 1 of 3 relics" named no pool, no rarity and no examples, and
	# the three plates were not drawn until after TAKE THE FIELD. So the player
	# was asked to weigh a known deck surgery against three unnamed relics — not a
	# comparison, a coin flip. The roll is a pure static off a stream derived from
	# a seed that is already fixed at this point, so the answer can simply be
	# shown; naming them here cannot change what _pick_blessing later deals.
	var offer := _writ_arsenal_preview(entry)
	if not offer.is_empty():
		var names: Array[String] = []
		var rules: Array[String] = []
		for rid in offer:
			var relic: Dictionary = RelicDB.get_relic(rid)
			names.append(String(relic.get("name", rid)))
			rules.append("%s — %s" % [relic.get("name", rid), relic.get("desc", "")])
		# The offer is a caption of the desc above it, and at the floored 18 the
		# three names needed ~385px against a 352px tile — so "Rear Guard Charm"
		# broke and left "Charm" orphaned on a line of its own. At a legal 15 the
		# list measures ~322 and holds one line.
		var offer_label := _make_caption_label(" · ".join(names), 15, GILT)
		offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(offer_label)
		btn.tooltip_text = "\n".join(rules)
	# Whatever the tile does not use falls to the bottom, below the last written
	# line — never between two lines that answer each other.
	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(tail)
	btn.pressed.connect(_select_muster_writ.bind(id))
	# A term is ACCEPTED, not browsed — it is the one pick on the walk that binds
	# the whole run, and it takes a wax seal. It sounds like one.
	_arm_shell_button(btn, "commit")
	return btn


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


func _select_muster_writ(id: String) -> void:
	if not _muster_writ_buttons.has(id):
		return
	_selected_writ_id = id
	_refresh_muster_writ_styles()


func _refresh_muster_writ_styles() -> void:
	for id in _muster_writ_buttons:
		var btn: Button = _muster_writ_buttons[id]
		if not is_instance_valid(btn):
			continue
		var selected := String(id) == _selected_writ_id
		# 0.93, not 0.70. The chosen tile has always been near-opaque; the other
		# three were a 70% wash, and this row is the one element of the Muster
		# that sits low enough on the canvas to be read against open flame. The
		# leftmost term was ink on warm-black and the rightmost was ink on fire —
		# same size, same colour, half the legibility. The unselected border comes
		# up with it, because at 0.38 over a bright frame the tile had no edge.
		var bg: Color = Color(0.17, 0.105, 0.06, 0.97) if selected \
			else Color(0.035, 0.025, 0.03, 0.93)
		# ── ONE CHOSEN TERM, NOT FOUR FRAMED BOXES (2026-09-15) ──
		#
		# The frameless pass took the borders off every section, which left this
		# row as the only framed thing on the screen — four gilt-edged boxes in a
		# line, reading as a form rather than as an offer. The unselected tiles
		# now carry NO rule at all (alpha 0, which also stops ChartPanelStyle
		# drawing its corner marks), so the eye sees one lit term among three
		# quiet ones instead of four equal frames.
		#
		# THE FILL STAYS, and must: this row sits low enough on the canvas to be
		# read against open flame, so the wash is legibility, not decoration. It
		# is the border that was noise, never the background.
		var width: int = 2 if selected else 1
		var normal := GameTheme.make_panel_style(bg,
			GILT_BRIGHT if selected else Color(0.54, 0.46, 0.33, 0.0),
			width, 4, false)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("pressed", normal)
		# Build the hover variant by asking the kit again rather than by
		# `normal.duplicate() as StyleBoxFlat` — make_panel_style returns a
		# ChartPanelStyle, so that cast yielded NULL and every muster screen build
		# threw "Invalid assignment ... on a base object of type 'Nil'", leaving the
		# four tiles with no hover state at all. This is the documented panel-kit
		# trap: never cast a kit style to StyleBoxFlat.
		var hover := GameTheme.make_panel_style(bg, GILT_BRIGHT, width, 4, false)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("focus", hover)
		# The marker is a WaxSeal host now, not a Label — `as Label` would silently
		# yield null here and the accepted term would carry no mark at all.
		var marker := btn.find_child("TermChosenMarker", true, false) as Control
		if marker != null:
			var was_visible: bool = marker.visible
			marker.visible = selected
			# PRESS IT, don't pop it. A seal that appears on frame 1 reads as a
			# badge toggling; a seal that comes down under the stamp reads as an
			# act. Only on the TRANSITION into chosen — repainting the row (which
			# happens on every deal refresh) must not re-stamp a term the player
			# accepted several seconds ago.
			if selected and not was_visible and not _reduce_motion():
				marker.pivot_offset = marker.size * 0.5
				marker.scale = Vector2(1.55, 1.55)
				marker.modulate.a = 0.0
				var tw := marker.create_tween().set_parallel(true)
				tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(marker, "scale", Vector2.ONE, 0.16)
				tw.tween_property(marker, "modulate:a", 1.0, 0.10)
			elif selected:
				marker.scale = Vector2.ONE
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
	var tribes := RunState.preview_season_tribes(seed_value, _selected_banner_tribe)
	var deal := RunState.preview_rival_deal(_selected_hero, seed_value)
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
	if _muster_step == 3:
		if _muster_writ_row == null or not is_instance_valid(_muster_writ_row):
			return
	elif _muster_step == 4:
		if _muster_order_term_detail == null or not is_instance_valid(
				_muster_order_term_detail):
			return
	else:
		return
	var previous_term := _selected_writ_id
	_refresh_muster_deals()
	# If the new seed no longer contains the term the player chose, send them
	# back to the comparison instead of silently replacing it on the review page.
	if _muster_step == 4 and previous_term != _selected_writ_id:
		_show_muster_step(3)


func _abandon_muster() -> void:
	_hide_deck_inspector()
	_quick_march_active = false
	_muster_advanced_open = false
	RunState.pending_signature_relic = ""
	RunState.pending_deck_variant = ""
	RunState.pending_banner_tribe = ""
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
func _faction_accent(hid: String) -> Color:
	var fac := HeroDB.faction_info(HeroDB.get_faction(hid))
	if fac.is_empty():
		return GILT
	var c: Color = fac.get("color", GILT)
	var toward_gilt := 0.62 if (c.g >= c.r or c.b >= c.r) else 0.42
	return _lift_to_luminance(c.lerp(GILT_BRIGHT, toward_gilt), 0.80)


## THE COMMIT — the largest instance of the shell's one forward-action shape.
##
## This was frameless, and until 2026-08-05 that was consistent: every forward
## move in the muster was a frameless word. Now steps I-III each carry a plated
## primary tab, so leaving the LAST step frameless taught the player one shape
## three times and then changed it on the one press that matters. It keeps
## everything that made it the climax — 27px Cinzel against the tabs' 19, two
## flames instead of one, its own underline — and puts them on the same plate,
## so the walk reads as one escalating gesture rather than four designs.
func _make_begin_button() -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.clip_contents = false
	var cta_normal := GameTheme.make_panel_style(
		Color(0.135, 0.072, 0.034, 0.94), Color(0.84, 0.64, 0.32, 0.86),
		2, 6, false)
	var cta_hover := GameTheme.make_panel_style(
		Color(0.235, 0.120, 0.048, 0.98), GILT_BRIGHT, 3, 6, true)
	var cta_pressed := GameTheme.make_panel_style(
		Color(0.095, 0.052, 0.028, 0.98), Color(0.90, 0.72, 0.36), 2, 6, false)
	for style in [cta_normal, cta_hover, cta_pressed]:
		style.content_margin_left = 22
		style.content_margin_right = 22
		style.content_margin_top = 6
		style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", cta_normal)
	btn.add_theme_stylebox_override("hover", cta_hover)
	btn.add_theme_stylebox_override("focus", cta_hover)
	btn.add_theme_stylebox_override("pressed", cta_pressed)

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


func _on_take_field_pressed(btn: Control) -> void:
	if _run_commit_locked or _selected_hero == "" or _selected_writ_id == "":
		return
	_run_commit_locked = true
	# FLUSH ANY DEBOUNCED SEED DEAL. _on_muster_seed_changed waits 0.35s before
	# re-rolling the slate, so a player who types a seed and immediately commits
	# would otherwise march with a slate rolled from the PREVIOUS seed while
	# _pending_run_seed() reports the new one — the run and its opening term
	# disagreeing about which seed they came from. Cancelling the pending deal
	# and taking it now keeps the committed term the one actually on screen.
	if _seed_deal_token > 0:
		_seed_deal_token += 1   # supersede the in-flight timer
		if _muster_step == 4 and _muster_order_term_detail != null \
				and is_instance_valid(_muster_order_term_detail):
			var previous_term := _selected_writ_id
			_refresh_muster_deals()
			if previous_term != _selected_writ_id:
				_run_commit_locked = false
				_show_muster_step(3)
				return
	GameTheme.claim_pop(btn)
	if UserSettings == null or not UserSettings.reduce_motion:
		await get_tree().create_timer(0.12).timeout
	if not is_inside_tree():
		return
	_begin_run_with(_selected_hero)


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
## Card art ships 3:2 landscape (768×512 and 1344×896 throughout
## assets/creatures). The tiles are built at that ratio so COVERED crops nothing.
const OPENER_ART_ASPECT := 1.5
## Two ranks of six holds an 11-card opener (max 10 distinct after duplicates)
## without a third rank appearing for one card.
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
func _warm_deck_strip(deck: Array, hid: String) -> void:
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
	CardTextureCache.bake_many(datas,
		func() -> bool: return is_inside_tree() and _selected_hero == hid)


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
	_deck_inspect_return_focus = return_focus
	if not HeroDB.has_hero(_selected_hero):
		return
	var opener: Array[String] = RunState.opening_deck_for(
		_selected_hero, _muster_alt_deck, _selected_banner_tribe)
	_warm_deck_strip(opener, _selected_hero)
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
		"%d cards  ·  %s adds %s" % [opener.size(),
			BannerDB.display_name(_selected_banner_tribe),
			CardDB.get_card_data(BannerDB.card_id(_selected_banner_tribe)).get(
				"name", "one card")],
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
	for cid in order:
		grid.add_child(_make_deck_mini(cid, int(counts[cid]), 0.72))
	var close := _make_menu_button(
		"CLOSE", Color(0.24, 0.18, 0.14), 18, 48)
	close.name = "DeckInspectorReturn"
	close.custom_minimum_size = Vector2(300, 48)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_hide_deck_inspector)
	content.add_child(close)
	close.call_deferred("grab_focus")


func _hide_deck_inspector() -> void:
	var restore_focus := _deck_inspect_return_focus
	_deck_inspect_return_focus = null
	if _deck_inspect_overlay != null and is_instance_valid(_deck_inspect_overlay):
		_deck_inspect_overlay.queue_free()
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
	RunState.pending_banner_tribe = _selected_banner_tribe
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
		var summary := RunState.get_slot_summary(slot)
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
	if UserSettings != null and UserSettings.reduce_motion:
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
	if UserSettings != null and UserSettings.reduce_motion:
		return
	# Skip children the caller just queue_free'd (subscreens rebuild the Menu
	# in place, so the dying column is still in the tree here) — staggering
	# over them added ~0.7s of dead air before the first REAL element faded
	# in, and their tweeners died with them at frame end.
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
			_show_writ_relic_picker("Choose a relic", offered,
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
	var suffix: String = "  (%d left)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("Choose a card to forge" + suffix, candidates,
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
	var suffix: String = "  (%d left)" % picks if picks > 1 else ""
	_show_blessing_offer_picker("Choose a card to add" + suffix, offered,
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
	var suffix: String = "  (%d left)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("Choose a card to transform" + suffix, eligible,
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
	var suffix: String = "  (%d left)" % remaining if remaining > 1 else ""
	_show_blessing_card_picker("Choose a card to remove" + suffix, all_idx,
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
		picked: Variant) -> Dictionary:
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
		wrapper, on_pick, picked))
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
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll.offset_left = 64
	scroll.offset_right = -64
	scroll.offset_top = 110
	scroll.offset_bottom = 800
	add_child(scroll)

	var grid := GridContainer.new()
	grid.set_meta("coordinated_card_group", true)
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	# The complete two-row spread exists before the first await. Card backs carry
	# the wait without exposing renderer order or changing GridContainer geometry.
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
		picked) -> void:
	if _picker_commit_locked:
		return
	_picker_commit_locked = true
	GameTheme.claim_pop(target)
	if UserSettings == null or not UserSettings.reduce_motion:
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
			row, on_pick, String(ids[ei])))

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
