extends Control
## Rest.gd — Make Camp scene. Diegetic restyle of the old "REST SITE" UI.
##
## Visual layers (back → front):
##   1. Background     (per-act painted scene; act 2/3 fall back to act 1 if
##                      their assets aren't shipped yet)
##   2. Atmosphere     (vignette + ember particles anchored to the fire, +
##                      optional dusk/night tint via mood_override)
##   3. Hotspot glows  (pulsing radial gradients behind each banner — sells
##                      the diegetic feel without depending on pixel-perfect
##                      alignment to painted regions)
##   4. Hero silhouette (decorative, near the fire — falls back gracefully
##                      if the per-hero silhouette art isn't in assets/ yet)
##   5. Parchment banners (REST / FORGE — swapped for FORGE TWO while the
##                      Whetstone is live — plus RAISE THE DEAD with fallen)
##   6. Title + HP subtitle
##   7. Settings gear + (in pick-card mode only) cancel button
##
## Choices: Heal to full HP, forge a card's "+" version (StS-style — every
## card has one hand-crafted upgrade defined in CardDB.UPGRADES), and — with
## the Whetstone relic, once per act — Reforge to forge TWO cards. Card
## removal is intentionally NOT offered here: it belongs at shops / specific
## events / Toke-style relics, per genre convention (StS rest sites don't
## remove either). Whetstone state is tracked in RunState.whetstone_used_this_act
## and resets in RunState.advance_act().
##
## Upgrade flow (CHOOSE → PICK_CARD → CONFIRM_UPGRADE):
##   1. CHOOSE — banner picker; player taps UPGRADE or REFORGE.
##   2. PICK_CARD — grid of un-upgraded, upgradeable deck cards. Click one.
##   3. CONFIRM_UPGRADE — modal with base + upgraded card side-by-side, a
##      "→" arrow, change summary, and FORGE+ / BACK buttons.
## A REFORGE pick loops back through 2 and 3 a second time; once both picks
## land, Whetstone is marked consumed for the act and the scene fades to map.

const MAP_SCENE = "res://scenes/map.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")

# Per-act background lookup. Act 2 and Act 3 are placeholders — the loader
# falls back to act 1 when they don't exist on disk, so missing assets degrade
# gracefully instead of crashing or showing pink.
const BG_PATHS := {
	1: "res://assets/backgrounds/rest_campfire.png",
	2: "res://assets/backgrounds/rest_campfire_act2.png",
	3: "res://assets/backgrounds/rest_campfire_act3.png",
}
const BG_FALLBACK := "res://assets/backgrounds/rest_campfire.png"

# Hero silhouette path pattern. Same fallback story — uses an existing
# portrait if a hero-specific silhouette hasn't been generated yet.
const HERO_SILHOUETTE_PATTERN := "res://assets/portraits/hero_silhouette_%s.png"
const HERO_SILHOUETTE_FALLBACK := "res://assets/portraits/player_knight.png"

# Banner icons (use existing assets/icons/ entries). Each banner picks one.
const ICON_REST := "res://assets/icons/game-icons/campfire.svg"
const ICON_UPGRADE := "res://assets/icons/sword.png"
# The Whetstone's OWN sigil. This was assets/icons/diamond.png — a generic
# primitive from the pre-art icon set, on a banner whose text literally names
# the relic that grants it. The silhouette SVG is what make_choice_banner wants
# (it tints the glyph to parchment; a painted PNG comes out muddy brown).
const ICON_REFORGE := "res://assets/icons/relics/whetstone.svg"
const ICON_WAKE := "res://assets/icons/game-icons/scroll-unfurled.svg"

# Banner accent colors. Pulled from GameTheme palette where possible so the
# rest screen sits in the same color world as combat HUD parchment.
var _accent_rest: Color
var _accent_upgrade: Color
var _accent_reforge: Color
var _accent_wake: Color

# Per-hero flavor strings keyed by [hero_id][choice_id] → 2 lines that swap
# between the desc text on hover. Choice IDs: rest / upgrade / remove / reforge.
# Trivial to extend — add new heroes or new choices by adding entries here.
const HERO_FLAVOR := {
	"raider": {
		"rest":    "Rest now. The next fight comes soon.",
		"upgrade": "Improve one card for the road ahead.",
		"reforge": "Forge two cards instead of one.",
		"wake":    "Choose one fallen soldier for the next fight.",
	},
	"stalwart": {
		"rest":    "Stop and tend your wounds.",
		"upgrade": "Improve one card for the road ahead.",
		"reforge": "Forge two cards instead of one.",
		"wake":    "Choose one fallen soldier for the next fight.",
	},
	"acolyte": {
		"rest":    "Rest beside the fire and recover.",
		"upgrade": "Improve one card for the road ahead.",
		"reforge": "Forge two cards instead of one.",
		"wake":    "Choose one fallen soldier for the next fight.",
	},
	"pyromancer": {
		"rest":    "Stop for the night and recover.",
		"upgrade": "Improve one card for the road ahead.",
		"reforge": "Forge two cards instead of one.",
		"wake":    "Choose one fallen soldier for the next fight.",
	},
	"kindler": {
		"rest":    "Rest at the fire and recover.",
		"upgrade": "Improve one card for the road ahead.",
		"reforge": "Forge two cards instead of one.",
		"wake":    "Choose one fallen soldier for the next fight.",
	},
}
const FLAVOR_FALLBACK := {
	"rest":    "Rest by the fire and heal.",
	"upgrade": "Improve one card.",
	"reforge": "Forge two cards instead of one.",
	"wake":    "Choose one fallen soldier for the next fight.",
}

enum Mode { CHOOSE, PICK_CARD, CONFIRM_UPGRADE }

var _mode: int = Mode.CHOOSE
var _selected_card_index: int = -1
# When Reforge is in flight, _reforge_remaining counts down the upgrades the
# player still gets to apply. 0 = single upgrade (the normal Upgrade path);
# 2 = two upgrades (Whetstone Reforge). Decrements after each pick.
var _reforge_remaining: int = 0
# Set the moment a forge COMMITS. The camp gives one action, and a landed forge
# is that action — so backing out afterwards leaves for the map instead of
# returning to the banner picker (see _back_out_of_upgrade).
var _forged_this_visit: bool = false
# Latched once the camp is on its way out, so a second click during the fade
# cannot re-run register_rest_visit() (which counts and saves).
var _leaving: bool = false
# True while _do_upgrade is awaiting its forge-strike. The confirm screen's Back
# button and Esc both stay LIVE across that await, and the forge has already been
# written to the deck by then — so backing out mid-strike has to be refused
# rather than allowed to race the resolver to the exit.
var _forge_resolving: bool = false
# Async forge-grid/preview builders yield between cards. Every UI rebuild bumps
# this token so a builder parked on a cache bake or frame boundary cannot add
# stale cards after the player has backed out or opened the confirm screen.
var _ui_build_gen: int = 0

# These resources are immutable. Keep one copy for every Rest visit instead of
# recompiling the same silhouette shader and regenerating one radial texture per
# choice banner on every open.
static var _silhouette_feather_shader_cache: Shader = null
static var _hotspot_glow_texture_cache: Texture2D = null


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	_accent_rest = GameTheme.HEALTH_GREEN
	_accent_upgrade = GameTheme.KEYWORD_GOLD
	# FORGE TWO is the same VERB as FORGE, so it belongs in the same colour
	# family — brighter gilt for "more of it". FLOOP_BLUE put a cold spell-school
	# accent on the one screen made of firelight and parchment.
	_accent_reforge = GameTheme.GILT_BRIGHT
	_accent_wake = Color(0.64, 0.72, 0.88)   # spectral bone-blue
	_swap_background_for_act()
	GameTheme.add_atmosphere(self, "rest", true, _time_of_day_mood_override())
	GameTheme.fade_in(self, 0.26)
	AudioBank.play_music_random(["rest", "rest_b", "rest_c", "rest_d"])
	# Looping fire crackle — silently no-ops if assets/audio/sfx/fire_crackle/
	# is empty (player will hear only the music until the asset ships).
	AudioBank.play_ambience("fire_crackle")
	_build_campfire_life()
	_build_choice_ui()
	GameTheme.make_settings_gear(self)
	_maybe_coach_the_camp()


## THE BANNERS ARE STILL MOVING WHEN `_ready` RETURNS. `_build_choice_ui`'s last
## line calls `_center_camp_column` WITHOUT awaiting it, and that coroutine spends
## two frames before it rewrites the column's offsets — so a spotlight measured
## here would open over the pre-centred rects and then sit there while the banners
## slid out from under it. Three frames clears the shift with one to spare.
func _maybe_coach_the_camp() -> void:
	if not TutorialCoach.should_teach("camp_choice"):
		return
	for _i in 3:
		await get_tree().process_frame
		if not is_inside_tree() or _leaving:
			return
	var row := get_node_or_null("CampChoices")
	var targets: Array = []
	if row != null:
		for banner in row.get_children():
			if banner is Control:
				targets.append(banner)
	# REFUSE TO TEACH WITH NOTHING TO POINT AT. `teach()` stamps a lesson seen the
	# moment it shows a panel, whether or not any target resolved — so if the
	# "CampChoices" lookup above ever goes stale, this would put a panel over an
	# unlit screen and spend the lesson FOREVER on that profile. Caught by
	# mutation (renaming the row left the lesson seen with zero spotlight, and the
	# probe still passed). `Event._maybe_coach_the_page` already guards this way;
	# this is the sibling that was missing it.
	if targets.is_empty():
		return
	TutorialCoach.teach(self, "camp_choice", targets)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# In the upgrade sub-flow (PICK_CARD / CONFIRM_UPGRADE) Esc backs out the same
	# way the Cancel button does. From the top (CHOOSE) it opens pause/Settings.
	if _mode != Mode.CHOOSE:
		_back_out_of_upgrade()
	else:
		GameTheme.open_settings_overlay()
	get_viewport().set_input_as_handled()


# Per-act background swap. The .tscn ships an Act 1 texture; this rebinds the
# Background TextureRect to the right path for the current act, falling back
# gracefully when act 2/3 assets aren't on disk yet.
func _swap_background_for_act() -> void:
	var bg := get_node_or_null("Background") as TextureRect
	if bg == null:
		return
	var act := RunState.get_act()
	var path: String = BG_PATHS.get(act, BG_FALLBACK)
	if not ResourceLoader.exists(path):
		path = BG_FALLBACK
	if ResourceLoader.exists(path):
		bg.texture = load(path)


# First rest in an act = dusk (warm tint, brighter); second = night (cool,
# darker, more stars/embers). Subtle but signals run progress without needing
# new art. Returns {} for visits beyond the second so we don't keep darkening.
func _time_of_day_mood_override() -> Dictionary:
	var idx: int = RunState.rests_visited_in_act
	match idx:
		0:
			# Dusk — leave the warm orange ember palette as-is, but lift the
			# gradient slightly so the painted sky stays visible.
			return {
				"grad_inner": Color(0.14, 0.08, 0.04, 0.05),
				"grad_outer": Color(0.04, 0.02, 0.01, 0.65),
				"vignette": 0.45,
			}
		1:
			# Night — cool the gradient, push the outer alpha so the painting
			# darkens at the edges, and bump particle count for more stars.
			return {
				"grad_inner": Color(0.04, 0.06, 0.10, 0.15),
				"grad_outer": Color(0.01, 0.02, 0.05, 0.85),
				"vignette": 0.62,
				"particle_count": 44,
			}
		_:
			return {}


func _build_choice_ui() -> void:
	_mode = Mode.CHOOSE
	_clear_ui()

	# Left command column — title, the march's health, the camp actions
	# stacked beneath (Hades/StS scene-screen grammar, and the house
	# left-aligned aesthetic). The old bottom-center banner row squatted
	# directly ON the painted campfire; now the fire, tent, and wagon own
	# the right two-thirds of the screen.
	var title = GameTheme.make_screen_title("MAKE CAMP", GameTheme.GILT_BRIGHT)
	title.anchor_left = 0.0
	title.anchor_right = 0.0
	title.offset_left = 64
	title.offset_right = 464
	title.offset_top = 138
	title.offset_bottom = 210
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var subtitle = GameTheme.make_label(
		"♥ %d / %d" % [RunState.hero_hp, RunState.hero_max_hp],
		20, GameTheme.IVORY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 0.0
	subtitle.offset_left = 64
	subtitle.offset_right = 464
	subtitle.offset_top = 218
	subtitle.offset_bottom = 246
	add_child(subtitle)
	GameTheme.deal_in(subtitle, 0.08)

	_add_hero_silhouette()

	# Banner column down the left edge. Worst case is four banners (REST +
	# FORGE + disabled FORGE TWO + WAKE) — 4×145 + 3×12 = 616px from y 262,
	# which still clears the bottom of the 900px canvas.
	var row := VBoxContainer.new()
	# NAMED so the coach can find the banners. `make_choice_banner` returns an
	# unnamed PanelContainer into a local, and `_clear_ui` rebuilds the column on
	# every mode switch, so a reference captured at build time would be stale by
	# the time anything wanted one — the column is looked up by name instead.
	row.name = "CampChoices"
	row.anchor_left = 0.0
	row.anchor_right = 0.0
	row.offset_left = 64
	row.offset_right = 464
	row.offset_top = 262
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_add_choice_rest(row)
	# The Whetstone UPGRADES the forge (CLAUDE.md: "forge two instead of one"),
	# it doesn't compete with it: an act has exactly one camp, so a live FORGE
	# TWO makes the single FORGE strictly dominated — showing both just adds a
	# banner nobody should click. Plain FORGE returns whenever the double is
	# spent/blocked (used this act, Cracked Anvil, <2 unforged cards).
	if not _reforge_is_live():
		_add_choice_upgrade(row)
	_add_choice_reforge_if_available(row)
	_add_choice_wake_if_available(row)

	_center_camp_column(title, subtitle, row)


## Slide the camp column so title + HP + banners sit centered on the canvas as
## one group. The offsets above are sized for the WORST case (four banners), but
## the common camp shows two — which left the column hugging the upper-left with
## ~350px of dead frame beneath it. (Screen audit 2026-07-21.)
##
## Two frames of wait, not call_deferred: deferred still runs before anchors are
## resolved, so both `size.y` (the scene's own height) and `row.size.y` read 0
## and the centering silently no-ops — which is exactly what the first attempt
## did.
func _center_camp_column(title: Control, subtitle: Control, row: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for c in [title, subtitle, row]:
		if c == null or not is_instance_valid(c):
			return
	if size.y <= 1.0 or row.size.y <= 1.0:
		return
	var group_top: float = title.offset_top
	var group_h: float = (row.offset_top - group_top) + row.size.y
	var delta: float = (size.y - group_h) * 0.5 - group_top
	# Never push the column off the top; a four-banner camp stays where it is.
	if delta <= 1.0:
		return
	for c in [title, subtitle, row]:
		c.offset_top += delta
		c.offset_bottom += delta


func _add_hero_silhouette() -> void:
	var hero_id: String = RunState.current_hero_id
	if hero_id == "":
		hero_id = HeroDB.DEFAULT_HERO
	var specific_path := HERO_SILHOUETTE_PATTERN % hero_id
	var path: String = specific_path if ResourceLoader.exists(specific_path) else HERO_SILHOUETTE_FALLBACK
	if not ResourceLoader.exists(path):
		return
	var sil := TextureRect.new()
	sil.name = "HeroSilhouette"
	sil.texture = load(path)
	sil.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor near the left edge of the fire, sized to look like a seated
	# figure. Slight modulate so the painted background reads through.
	# Shifted right of the old spot so the left banner column owns the left
	# edge and the hero sits between tent and fire.
	sil.position = Vector2(555, 470)
	sil.size = Vector2(220, 280)
	# The vignette paintings are full rectangles with their own night-black
	# ground — composited raw they read as a foreign box over the scene.
	# Feather the edges with a shader so the painting melts into the camp
	# instead of sitting on it (transparent-cutout art would pass unchanged).
	var feather := ShaderMaterial.new()
	feather.shader = _silhouette_feather_shader()
	sil.material = feather
	var has_specific := ResourceLoader.exists(specific_path)
	sil.modulate = Color(0.95, 0.88, 0.78, 0.85 if has_specific else 0.45)
	add_child(sil)
	GameTheme.deal_in(sil, 0.12)


func _silhouette_feather_shader() -> Shader:
	if _silhouette_feather_shader_cache != null:
		return _silhouette_feather_shader_cache
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// Rounded feather: alpha fades to 0 toward every edge of the rect, so a
// rectangular painting composites as a soft vignette. 0.22 = fade band as a
// fraction of the rect on each axis.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 d = min(UV, vec2(1.0) - UV);
	float m = smoothstep(0.0, 0.22, d.x) * smoothstep(0.0, 0.22, d.y);
	c.a *= m;
	COLOR = c;
}
"""
	_silhouette_feather_shader_cache = sh
	return _silhouette_feather_shader_cache


func _add_choice_rest(row: BoxContainer) -> void:
	var disabled_reason := ""
	if RunState.has_downside("no_rest_heal"):
		disabled_reason = "Can't heal at camp (Hairshirt)."
	elif RunState.hero_hp >= RunState.hero_max_hp:
		disabled_reason = "Already at full health."
	# Two-line banner body: hero-flavored line + mechanical readout. Players
	# need the number ("Heal to 25") at a glance; flavor is the personality
	# layer on top. Banner panel is generous enough to wrap both lines cleanly.
	var desc := "%s\n♥ Heal to %d / %d" % [
		_flavor_for("rest", ""), _rest_heal_target(), RunState.hero_max_hp]
	var banner = GameTheme.make_choice_banner("REST", desc, _accent_rest,
		ICON_REST, Vector2(400, 145), disabled_reason)
	_wire_banner(banner, row, _accent_rest, _do_heal)


func _add_choice_upgrade(row: BoxContainer) -> void:
	var disabled_reason := ""
	if RunState.has_downside("no_upgrade"):
		disabled_reason = "Can't forge here (Cracked Anvil)."
	else:
		var any_upgradeable := false
		for i in range(RunState.deck.size()):
			if RunState.has_upgrade_path(i, "plus"):
				continue
			if not CardDB.is_upgradeable(RunState.deck[i]):
				continue
			any_upgradeable = true
			break
		if not any_upgradeable:
			disabled_reason = "Every card already forged."
	var desc := "%s\n⚒ Forge a + version" % _flavor_for("upgrade", "")
	var banner = GameTheme.make_choice_banner("FORGE", desc, _accent_upgrade,
		ICON_UPGRADE, Vector2(400, 145), disabled_reason)
	_wire_banner(banner, row, _accent_upgrade, _start_upgrade_mode)


# True when FORGE TWO is actually clickable — owned, unspent, forging allowed,
# and two picks can land. This is the gate that swaps the plain FORGE banner
# out for the Whetstone version (see the banner build in _ready).
func _reforge_is_live() -> bool:
	if not RunState.has_relic("whetstone"):
		return false
	if RunState.whetstone_used_this_act or RunState.has_downside("no_upgrade"):
		return false
	var upgradeable_count := 0
	for i in range(RunState.deck.size()):
		if RunState.has_upgrade_path(i, "plus"):
			continue
		if not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		upgradeable_count += 1
	return upgradeable_count >= 2


# Whetstone-gated forge banner. Shows whenever the relic is owned; REPLACES the
# plain FORGE banner while live (disabled states show beside FORGE instead, so
# the player reads why the double is off). Lets the player pick TWO cards in
# sequence to upgrade — see _start_reforge_mode for the flow.
func _add_choice_reforge_if_available(row: BoxContainer) -> void:
	if not RunState.has_relic("whetstone"):
		return
	var disabled_reason := ""
	if RunState.whetstone_used_this_act:
		disabled_reason = "Already used this act."
	elif RunState.has_downside("no_upgrade"):
		disabled_reason = "Can't forge here (Cracked Anvil)."
	else:
		var upgradeable_count := 0
		for i in range(RunState.deck.size()):
			if RunState.has_upgrade_path(i, "plus"):
				continue
			if not CardDB.is_upgradeable(RunState.deck[i]):
				continue
			upgradeable_count += 1
		if upgradeable_count < 2:
			disabled_reason = "Need 2+ unforged cards."
	var desc := "%s\n◈ Forge two + versions (Whetstone)" % _flavor_for("reforge", "")
	var banner = GameTheme.make_choice_banner("FORGE TWO", desc, _accent_reforge,
		ICON_REFORGE, Vector2(400, 145), disabled_reason)
	_wire_banner(banner, row, _accent_reforge, _start_reforge_mode)


# Hold a Wake — campaign-memory banner. Read one name off the Roll of the
# Fallen; its shade stands in your front line for the NEXT fight (the camp
# sits right before the keep, so the wake usually arms the boss fight). The
# banner is HIDDEN with an empty roll (no dead options), and disabled when an
# event has already promised the next fight's opening slot.
func _add_choice_wake_if_available(row: BoxContainer) -> void:
	if RunState.fallen.is_empty():
		return
	var disabled_reason := ""
	if not RunState.next_combat_gift_creature.is_empty():
		disabled_reason = "Another creature already joins the next fight."
	var desc := "%s\n◈ A fallen soldier joins your front row in the next fight." % _flavor_for("wake", "")
	var banner = GameTheme.make_choice_banner("RAISE THE DEAD", desc, _accent_wake,
		ICON_WAKE, Vector2(400, 145), disabled_reason)
	_wire_banner(banner, row, _accent_wake, _start_wake_mode)


## The Roll, deduped by soldier: one tile per uid, keeping the LAST fall (the
## most decorated name worn). Shades rise at the soldier's CURRENT folded
## stats while the card still marches (drills and forges honored); a soldier
## since mustered out rises at the printed stats of the card it was.
func _wake_candidates() -> Array:
	var by_uid: Dictionary = {}
	var order: Array = []
	for entry in RunState.fallen:
		var uid: int = int(entry.get("uid", -1))
		if not by_uid.has(uid):
			order.append(uid)
		by_uid[uid] = entry
	var out: Array = []
	for uid in order:
		var entry: Dictionary = by_uid[uid]
		var atk := 1
		var hp := 1
		var idx: int = RunState.deck_uids.find(int(uid))
		var data: Dictionary = {}
		if idx >= 0:
			data = RunState.get_upgraded_card_data(idx)
		else:
			data = CardDB.get_card_data(String(entry.get("id", "")))
		if not data.is_empty():
			atk = maxi(0, int(data.get("atk", 1)))
			hp = maxi(1, int(data.get("hp", 1)))
		out.append({"entry": entry, "atk": atk, "hp": hp})
	return out


func _start_wake_mode() -> void:
	_clear_ui()

	var title = GameTheme.make_label("THE ROLL OF THE FALLEN",
		GameTheme.FONT_HEADER, GameTheme.GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var sub = GameTheme.make_label(
		"Choose a fallen soldier. They join your front row in the next fight.",
		16, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(400, 74)
	sub.size = Vector2(800, 28)
	sub.modulate = Color(1, 1, 1, 0.85)
	add_child(sub)
	GameTheme.deal_in(sub, 0.08)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(430, 120)
	scroll.size = Vector2(740, 660)
	add_child(scroll)
	GameTheme.deal_in(scroll, 0.12)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var wake_idx := 0
	for cand in _wake_candidates():
		var tile := _make_wake_tile(cand)
		list.add_child(tile)
		GameTheme.deal_in(tile, 0.16 + float(wake_idx) * 0.04)
		GameTheme.hover_lift(tile, 1.02)
		wake_idx += 1

	_add_cancel_btn()


func _make_wake_tile(cand: Dictionary) -> Button:
	# A parchment panel row: name (spectral) · where it fell · the stats it
	# rises with. Same panel-button pattern as the event relic tiles.
	var entry: Dictionary = cand.entry
	var btn := Button.new()
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(700, 96)
	btn.add_theme_stylebox_override("normal", GameTheme.make_panel_style())
	btn.add_theme_stylebox_override("hover",
		GameTheme.make_panel_style(GameTheme.PARCHMENT, GameTheme.GILT_BRIGHT))
	btn.add_theme_stylebox_override("pressed", GameTheme.make_panel_style())
	btn.pressed.connect(_on_wake_tile_pressed.bind(btn, cand))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_right = -18
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var name_lbl := GameTheme.make_label(String(entry.get("name", "the nameless")),
		21, _accent_wake)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var where := "Fell at %s — Act %d, round %d" % [
		String(entry.get("enc", "an unnamed field")),
		int(entry.get("act", 1)), int(entry.get("round", 1))]
	var where_lbl := GameTheme.make_label(where, 18, GameTheme.DESC_DIM)
	where_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(where_lbl)

	var rise_lbl := GameTheme.make_label("Joins at %d/%d" % [int(cand.atk), int(cand.hp)],
		15, GameTheme.KEYWORD_GOLD)
	rise_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rise_lbl)

	return btn


func _on_wake_tile_pressed(btn: Button, cand: Dictionary) -> void:
	if btn == null or not is_instance_valid(btn) or _leaving:
		return
	# ONE-SHOT LATCH. The claim hold below is live input: every OTHER name on the
	# Roll stayed clickable through it, and so did Cancel. A second tile inside
	# the window ran _do_wake twice — the second gift overwrote the first and
	# register_rest_visit() was counted twice — while Cancel handed back the
	# banner screen and _do_wake then left for the map anyway. _leaving is never
	# cleared, which is correct: raising a name ends the camp.
	_leaving = true
	btn.disabled = true
	GameTheme.claim_pop(btn)
	await get_tree().create_timer(_claim_hold()).timeout
	if not is_inside_tree():
		return
	_do_wake(cand)


func _do_wake(cand: Dictionary) -> void:
	var entry: Dictionary = cand.entry
	RunState.next_combat_gift_creature = {
		"name": "Shade of %s" % String(entry.get("name", "the nameless")),
		"atk": int(cand.atk),
		"hp": int(cand.hp),
		"kw": [],
	}
	RunState.register_rest_visit()
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


# Shared banner wiring: adds the hotspot glow behind the banner's eventual
# position, parents it to the row, hooks up the click handler, and animates
# the hotspot so it pulses subtly to suggest the painted scene is "alive."
func _wire_banner(banner: Control, row: BoxContainer, accent: Color, on_click: Callable) -> void:
	var deal_delay := 0.12 + float(row.get_child_count()) * 0.06
	row.add_child(banner)
	var click_btn := banner.get_node("ClickButton") as Button
	if click_btn != null and not click_btn.disabled:
		click_btn.pressed.connect(_on_choice_banner_pressed.bind(banner, click_btn, on_click))
		GameTheme.hover_lift(click_btn, 1.025, banner)
	# Hotspot glow — a soft radial gradient tinted by the banner's accent.
	# Parented inside the banner so it follows layout without needing manual
	# coords, but z-indexed below the panel so it bleeds out the edges.
	var glow := _make_hotspot_glow(accent)
	glow.z_as_relative = true
	glow.z_index = -1
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inflate beyond the banner bounds so the glow halos around it.
	glow.offset_left = -36
	glow.offset_right = 36
	glow.offset_top = -36
	glow.offset_bottom = 36
	banner.add_child(glow)
	# Subtle infinite pulse — slow enough not to distract, just enough to
	# read as living firelight reflected on the parchment.
	if UserSettings.reduce_motion:
		glow.modulate.a = 0.42   # steady firelight, no pulse
	else:
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(glow, "modulate:a", 0.34, 1.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glow, "modulate:a", 0.52, 1.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	GameTheme.deal_in(banner, deal_delay)


func _on_choice_banner_pressed(banner: Control, click_btn: Button, on_click: Callable) -> void:
	# THE CAMP GIVES ONE ACTION, so the claim seals the WHOLE row, not just the
	# banner under the cursor. Disabling only `click_btn` left every sibling live
	# through the claim hold below — and REST holds a further 0.6s inside
	# _do_heal before the fade — so a click on FORGE inside that window ran a
	# second camp action over the top of the first (heal applied, then the forge
	# picker built, then _do_heal's fade yanked the player to the map with the
	# forge lost). One camp, one banner: kill them all at the first press.
	if banner != null and is_instance_valid(banner) and banner.get_parent() != null:
		for sib in banner.get_parent().get_children():
			var sib_btn := sib.get_node_or_null("ClickButton") as Button
			if sib_btn != null:
				sib_btn.disabled = true
	if click_btn != null and is_instance_valid(click_btn):
		click_btn.disabled = true
	if banner != null and is_instance_valid(banner):
		GameTheme.claim_pop(banner)
	await get_tree().create_timer(_claim_hold()).timeout
	if not is_inside_tree():
		return
	on_click.call()


func _claim_hold() -> float:
	if UserSettings != null and UserSettings.reduce_motion:
		return 0.01
	return 0.10


func _make_hotspot_glow(accent: Color) -> TextureRect:
	# Procedural radial gradient — opaque accent at center, fading to fully
	# transparent at the edges. Built once per banner; cheap.
	# Center alpha kept low: this sits behind the tile's body text, so a strong
	# amber center washed the warm-white copy into poor contrast. A faint halo
	# reads as firelight without fighting legibility.
	if _hotspot_glow_texture_cache == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 0.26))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var grad_tex := GradientTexture2D.new()
		grad_tex.gradient = grad
		grad_tex.fill = GradientTexture2D.FILL_RADIAL
		grad_tex.fill_from = Vector2(0.5, 0.5)
		grad_tex.fill_to = Vector2(1.0, 0.5)
		grad_tex.width = 320
		grad_tex.height = 200
		_hotspot_glow_texture_cache = grad_tex
	var tr := TextureRect.new()
	tr.texture = _hotspot_glow_texture_cache
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	# Tinting one white radial mask is pixel-equivalent and lets every banner
	# share a single generated texture.
	tr.modulate = Color(accent.r, accent.g, accent.b, 0.85)
	return tr


# Returns the per-hero flavor string for a choice id, falling back to the
# generic fallback dict if the current hero has no entry for that choice.
func _flavor_for(choice_id: String, fallback_desc: String) -> String:
	var hero_id: String = RunState.current_hero_id
	if HERO_FLAVOR.has(hero_id):
		var per_choice: Dictionary = HERO_FLAVOR[hero_id]
		if per_choice.has(choice_id):
			return per_choice[choice_id]
	if FLAVOR_FALLBACK.has(choice_id):
		return FLAVOR_FALLBACK[choice_id]
	return fallback_desc


# ─── Choice handlers ───────────────────────────────────────────────────────

# Where the painted campfire burns in each act's background (fraction of the
# frame; the paintings and the 1600×900 canvas are both 16:9, so fractions map
# straight through). Live sparks + a breathing firelight glow sit ON the
# painted flames instead of floating somewhere generic.
const FIRE_ANCHORS := {
	1: Vector2(0.505, 0.74),
	2: Vector2(0.418, 0.72),
	3: Vector2(0.440, 0.78),
}


func _build_campfire_life() -> void:
	# The camp's one live element: sparks rising off the painted fire and the
	# firelight breathing. Both sit above the atmosphere scrim and below the
	# choice banners (built after this), so they read as part of the painting.
	var vp := get_viewport_rect().size
	var anchor: Vector2 = FIRE_ANCHORS.get(RunState.get_act(), Vector2(0.5, 0.75))
	var fire_pos := Vector2(vp.x * anchor.x, vp.y * anchor.y)

	# Firelight breathing — a soft additive glow over the flames. Kept even
	# under Reduce Motion (steady, no pulse): it's light, not movement.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.62, 0.24, 0.16), Color(1.0, 0.45, 0.15, 0.0)])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.width = 256
	grad_tex.height = 256
	var glow := TextureRect.new()
	glow.name = "CampfireGlow"
	glow.texture = grad_tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = fire_pos - Vector2(260, 240)
	glow.size = Vector2(520, 440)
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	add_child(glow)
	if not (UserSettings != null and UserSettings.reduce_motion):
		# Two-beat flicker loop with uneven timing — firelight, not a metronome.
		var tw := glow.create_tween()
		tw.set_loops()
		tw.tween_property(glow, "modulate:a", 0.72, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glow, "modulate:a", 1.0, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glow, "modulate:a", 0.84, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glow, "modulate:a", 1.0, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Rising sparks — a narrow column off the flame tips (same particle recipe
	# as Combat's ambient embers, scaled to one campfire).
	if UserSettings != null and (not UserSettings.particles or UserSettings.reduce_motion):
		return
	var sparks := CPUParticles2D.new()
	sparks.name = "CampfireSparks"
	sparks.position = fire_pos - Vector2(0, 30)
	sparks.amount = 16
	sparks.lifetime = 2.4
	sparks.preprocess = 2.0
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.emission_rect_extents = Vector2(22.0, 8.0)
	sparks.direction = Vector2(0, -1)
	sparks.spread = 16.0
	sparks.gravity = Vector2(0, -26.0)
	sparks.initial_velocity_min = 22.0
	sparks.initial_velocity_max = 58.0
	sparks.angular_velocity_min = -30.0
	sparks.angular_velocity_max = 30.0
	sparks.scale_amount_min = 1.2
	sparks.scale_amount_max = 2.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.80, 0.36, 0.0))
	ramp.set_color(1, Color(0.85, 0.25, 0.10, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.76, 0.34, 0.9))
	ramp.add_point(0.65, Color(0.95, 0.42, 0.16, 0.5))
	sparks.color_ramp = ramp
	add_child(sparks)


func _rest_heal_target() -> int:
	# A2 "Short rations" — camp rest heals 60% of what's missing (round up)
	# instead of to full. Below A2 the target is always full HP. The banner
	# readout and _do_heal both go through this so the promise matches the heal.
	if not RunState.asc_active(2):
		return RunState.hero_max_hp
	var missing: int = RunState.hero_max_hp - RunState.hero_hp
	return RunState.hero_hp + int(ceil(missing * 0.6))


func _do_heal() -> void:
	var before: int = RunState.hero_hp
	RunState.hero_hp = _rest_heal_target()
	RunState.register_rest_visit()
	# The heal gets a beat before the fade: the figure rises off the fire and
	# a breath of green sparks lifts with it. Without it the biggest single
	# heal in the game was an instant scene change.
	var healed: int = RunState.hero_hp - before
	if healed > 0 and not (UserSettings != null and UserSettings.reduce_motion):
		var vp := get_viewport_rect().size
		GameTheme.spawn_floating_text(self, Vector2(vp.x * 0.5, vp.y * 0.40),
			"+%d HP" % healed, GameTheme.HEALTH_GREEN, true)
		AudioBank.play_sfx("heal")
		# A breath of green motes lifts with the heal (rises like ash, but a
		# softer column — bespoke numbers over the factory's base preset).
		Motion.burst(self, Vector2(vp.x * 0.5, vp.y * 0.52), "base", {
			"z_index": 0, "explosiveness": 0.7, "amount": 22, "lifetime": 1.0,
			"spread": 32.0, "gravity": Vector2(0, -60.0),
			"velocity_min": 40.0, "velocity_max": 110.0,
			"scale_min": 2.0, "scale_max": 4.0,
			"color": Color(0.98, 0.82, 0.42, 0.85),   # forge sparks are gilt, not green
		})
		await get_tree().create_timer(0.6).timeout
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


func _start_upgrade_mode() -> void:
	_reforge_remaining = 0
	_begin_pick_card_for_upgrade()


# Whetstone Reforge entry: queue up 2 upgrades and hand off to the same
# pick-card flow. After each pick resolves (_do_upgrade), the counter is
# checked — if more remain, we loop back into the picker. When it hits 0,
# the relic's per-act payoff is marked spent and we leave the rest screen.
func _start_reforge_mode() -> void:
	_reforge_remaining = 2
	_begin_pick_card_for_upgrade()


func _begin_pick_card_for_upgrade() -> void:
	_mode = Mode.PICK_CARD
	_clear_ui()

	var header_text: String = "Choose a card to forge"
	var build_gen := _ui_build_gen
	if _reforge_remaining > 0:
		header_text = "FORGE TWO — pick %d more card%s" % [
			_reforge_remaining, "" if _reforge_remaining == 1 else "s"]
	var title = GameTheme.make_label(header_text, GameTheme.FONT_HEADER, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var sub = GameTheme.make_label("Click a card to see the exact + version before you forge it", 16, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(500, 74)
	sub.size = Vector2(600, 28)
	sub.modulate = Color(1, 1, 1, 0.85)
	add_child(sub)
	GameTheme.deal_in(sub, 0.08)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(95, 110)
	scroll.size = Vector2(1410, 680)
	add_child(scroll)
	GameTheme.deal_in(scroll, 0.12)

	# 225px tiles, six to a rank. Pinned rather than sized to the viewport: this
	# grid clears its 1410px scroll by only 10px, so a vertical scrollbar on a
	# long deck would otherwise drop the rank to five.
	var grid = GameTheme.make_picker_rank(6, 225.0, 10, 16)
	grid.name = "ForgeCardGrid"
	scroll.add_child(grid)

	# Seat the whole final grid in one stack frame. Rich Card2D faces hydrate
	# behind these real backs, so neither a cold cache nor a long deck can make
	# the centered rows grow underneath the player.
	var entries: Array[Dictionary] = []
	for i in range(RunState.deck.size()):
		# Forge "+" stays once per card; other mods (drill, banners) don't
		# block the forge — Inscryption stacking.
		if RunState.has_upgrade_path(i, "plus"):
			continue
		# Skip cards with no meaningful upgrade (curses). Players never see them
		# offered as upgrade targets, even though they're in the deck.
		if not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		var wrapper := Control.new()
		wrapper.name = "ForgeCardSlot"
		wrapper.custom_minimum_size = Vector2(225, 300)
		wrapper.pivot_offset = wrapper.custom_minimum_size * 0.5
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(wrapper)
		var back := _make_forge_loading_back(wrapper, grid)
		entries.append({
			"deck_index": i,
			"data": data,
			"wrapper": wrapper,
			"back": back,
		})

	_hydrate_forge_card_group(grid, entries, build_gen)
	_add_cancel_btn()


func _hydrate_forge_card_group(grid: Container, entries: Array[Dictionary],
		build_gen: int) -> void:
	if entries.is_empty():
		return
	var grid_ref: WeakRef = weakref(grid)
	var picker_alive := func() -> bool:
		var live_grid: Node = grid_ref.get_ref()
		return _ui_build_is_current(build_gen, Mode.PICK_CARD, live_grid)
	# Always present the complete sleeve grid once before doing any expensive
	# work. Warm-cache and cold-cache openings therefore share the same contract.
	await get_tree().process_frame
	if not picker_alive.call():
		return

	var datas: Array = []
	for entry in entries:
		datas.append(entry.data)
	if DisplayServer.get_name() != "headless":
		await CardTextureCache.bake_many(datas, picker_alive)
		if not picker_alive.call():
			return

	var windowed := DisplayServer.get_name() != "headless"
	var cards: Array[Control] = []
	var backs: Array[Control] = []
	var buttons: Array[Button] = []
	var empty_style := StyleBoxEmpty.new()
	for entry in entries:
		if not picker_alive.call():
			return
		var wrapper: Control = entry.wrapper
		var data: Dictionary = entry.data
		var deck_index: int = entry.deck_index
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		card_node.defer_baked_rules_text = windowed
		card_node.visible = false
		card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, 0)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.disabled = true
		click_btn.add_theme_stylebox_override("normal", empty_style)
		click_btn.add_theme_stylebox_override("hover", empty_style)
		click_btn.add_theme_stylebox_override("pressed", empty_style)
		click_btn.pressed.connect(_on_upgrade_card_pressed.bind(
			wrapper, click_btn, deck_index))
		GameTheme.hover_lift(click_btn, 1.025, wrapper)
		wrapper.add_child(click_btn)
		cards.append(card_node)
		backs.append(entry.back)
		buttons.append(click_btn)
		if windowed:
			await RenderingServer.frame_post_draw
			if not picker_alive.call():
				return
			card_node.complete_deferred_baked_rules()
			await RenderingServer.frame_post_draw
			if not picker_alive.call():
				return

	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not snap:
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for back in backs:
			Motion.flip_out(back, 0.13)
		await get_tree().create_timer(Motion.time(0.13)).timeout
		if not picker_alive.call():
			return
	for index in range(cards.size()):
		var card: Control = cards[index]
		var back: Control = backs[index]
		var button: Button = buttons[index]
		if snap and is_instance_valid(back):
			back.queue_free()
		card.visible = true
		if not snap:
			Motion.flip_in(card, 0.0, 0.16)
		button.disabled = false


func _make_forge_loading_back(parent: Control,
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


func _on_upgrade_card_pressed(wrapper: Control, click_btn: Button, deck_index: int) -> void:
	if _mode != Mode.PICK_CARD:
		return
	if click_btn != null and is_instance_valid(click_btn):
		click_btn.disabled = true
	if wrapper != null and is_instance_valid(wrapper):
		GameTheme.claim_pop(wrapper)
	await get_tree().create_timer(_claim_hold()).timeout
	if not is_inside_tree() or _mode != Mode.PICK_CARD:
		return
	_select_card_for_upgrade(deck_index)


func _select_card_for_upgrade(deck_index: int) -> void:
	if _mode != Mode.PICK_CARD:
		return
	_selected_card_index = deck_index
	_mode = Mode.CONFIRM_UPGRADE
	var build_gen := _ui_build_gen
	# The '+' variant has a distinct cache key and normally has never appeared.
	# Warm it behind the claimed picker so both confirm cards use cached overlays.
	if DisplayServer.get_name() != "headless":
		var upgraded_data: Dictionary = RunState.preview_plus_upgrade(
			RunState.get_upgraded_card_data(deck_index))
		if not CardTextureCache.has(upgraded_data):
			await CardTextureCache.bake(upgraded_data)
		if not _ui_build_is_current(build_gen, Mode.CONFIRM_UPGRADE, self) \
				or _selected_card_index != deck_index:
			return
	_show_confirm_upgrade(deck_index)


# The "+" upgrade confirm screen. Shows the card's current state and its
# upgraded counterpart side-by-side with an arrow between, plus a summary of
# what changed. The player commits with UPGRADE or backs out with CANCEL.
# This is the cinematic moment of the rest site — players see exactly what
# they're getting, no random rolls or path picks, just a clean before/after.
func _show_confirm_upgrade(deck_index: int) -> void:
	_mode = Mode.CONFIRM_UPGRADE
	_clear_ui()

	var build_gen := _ui_build_gen
	# Dim everything behind the modal so the comparison reads cleanly against
	# the painted background.
	var dim := ColorRect.new()
	dim.name = "ModalDim"
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	if UserSettings == null or not UserSettings.reduce_motion:
		dim.modulate.a = 0.0
		var dim_tw := dim.create_tween()
		dim_tw.tween_property(dim, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)

	# Compute current + forged data. The "before" side starts from the card's
	# LIVE modded data (drill stacks, banners included) and the preview lays
	# the plus delta on top via the same code path the live deck uses —
	# RunState._apply_plus_upgrade — so what the player sees here is what
	# they get in combat.
	var base_data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	var upgraded_data: Dictionary = RunState.preview_plus_upgrade(base_data)

	# Header title (gold, large)
	var header_text := "FORGE"
	if _reforge_remaining > 0:
		header_text = "FORGE TWO  ·  %d remaining" % _reforge_remaining
	var title = GameTheme.make_label(header_text, GameTheme.FONT_HEADER + 6, GameTheme.GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 90
	add_child(title)
	GameTheme.deal_in(title, 0.04)

	# Card name strip
	var name_text := "%s  →  %s" % [base_data.name, upgraded_data.name]
	var name_lbl = GameTheme.make_label(name_text, 22, GameTheme.KEYWORD_GOLD)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_lbl.offset_top = 100
	name_lbl.offset_bottom = 130
	add_child(name_lbl)
	GameTheme.deal_in(name_lbl, 0.08)

	# Card comparison row: base | arrow | upgraded. Card2D natural size is
	# 300x400; we render at a comfortable scale so both fit at center.
	var compare_row := HBoxContainer.new()
	compare_row.name = "ForgeCompareRow"
	compare_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compare_row.add_theme_constant_override("separation", 30)
	compare_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(compare_row)
	# Offsets AFTER add_child: setting .position on a parentless Control with
	# center anchors computes offsets against a zero-size rect, which shoved
	# this row to x≈1220 and pushed the "+" card clean off screen.
	compare_row.offset_left = -380
	compare_row.offset_right = 380
	compare_row.offset_top = 150
	compare_row.offset_bottom = 570
	GameTheme.deal_in(compare_row, 0.12)

	# The whole comparison occupies its final geometry immediately. Both ornate
	# faces hydrate behind these shells, then turn together as one proposition.
	var base_preview := _make_preview_card_shell(compare_row, false)
	_add_arrow_glyph(compare_row)
	var upgraded_preview := _make_preview_card_shell(compare_row, true)

	# Change summary below the cards — text bullets of what shifted. Cheap
	# but informative; players who don't read the desc still see at a glance.
	var summary_text := _build_change_summary(base_data, upgraded_data)
	var summary = GameTheme.make_label(summary_text, 16, GameTheme.IVORY)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.set_anchors_preset(Control.PRESET_TOP_WIDE)
	summary.offset_left = 200
	summary.offset_right = -200
	summary.offset_top = 600
	summary.offset_bottom = 700
	add_child(summary)
	GameTheme.deal_in(summary, 0.18)

	# Action buttons — UPGRADE in gold (the affirmative path) and CANCEL in
	# neutral grey. Positioned at bottom-center, well below the cards so
	# clicks can't accidentally fall through onto the comparison area.
	var btn_row := HBoxContainer.new()
	btn_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	btn_row.offset_top = -130
	btn_row.offset_bottom = -60
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 30)
	add_child(btn_row)
	GameTheme.deal_in(btn_row, 0.22)

	var upgrade_btn = GameTheme.make_themed_button("⚒ Forge +", GameTheme.GILT, Vector2(240, 60), 22)
	upgrade_btn.name = "ForgeConfirmButton"
	upgrade_btn.disabled = true
	upgrade_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_btn.pressed.connect(_do_upgrade.bind("plus", ""))
	btn_row.add_child(upgrade_btn)
	GameTheme.hover_lift(upgrade_btn, 1.03)

	var back_btn = GameTheme.make_back_button("Back", Vector2(180, 60), 18)
	back_btn.pressed.connect(_back_to_pick_card)
	btn_row.add_child(back_btn)
	GameTheme.hover_lift(back_btn, 1.03)
	_hydrate_forge_preview_pair([
		{"shell": base_preview, "data": base_data},
		{"shell": upgraded_preview, "data": upgraded_data},
	], upgrade_btn, build_gen, compare_row)


# Reserves one exact preview footprint and its loading back. The upgraded shell
# also owns the gilt halo and stable ForgedPreview name used by the strike beat.
func _make_preview_card_shell(parent: Container,
		is_upgraded_preview: bool) -> Dictionary:
	var wrap := Control.new()
	wrap.name = "ForgedPreview" if is_upgraded_preview else "BasePreview"
	wrap.custom_minimum_size = Vector2(300, 400)
	if is_upgraded_preview:
		# Named so _do_upgrade can aim the forge-strike set-piece at it.
		wrap.name = "ForgedPreview"

	# Green halo behind the upgraded card. Procedural radial gradient, parented
	# at z=-1 so it sits behind the Card2D panel.
	if is_upgraded_preview:
		# Gilt, matching `_accent_upgrade` (KEYWORD_GOLD) which this screen already
		# declares as the forge's colour. The halo was the one place the forge lit
		# up green — its own hero moment contradicting its own accent.
		var grad := Gradient.new()
		grad.set_color(0, Color(0.95, 0.76, 0.30, 0.55))
		grad.set_color(1, Color(0.40, 0.28, 0.08, 0.0))
		var grad_tex := GradientTexture2D.new()
		grad_tex.gradient = grad
		grad_tex.fill = GradientTexture2D.FILL_RADIAL
		grad_tex.fill_from = Vector2(0.5, 0.5)
		grad_tex.fill_to = Vector2(1.0, 0.5)
		grad_tex.width = 320
		grad_tex.height = 200
		var halo := TextureRect.new()
		halo.texture = grad_tex
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.stretch_mode = TextureRect.STRETCH_SCALE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		halo.z_index = -1
		halo.set_anchors_preset(Control.PRESET_FULL_RECT)
		halo.offset_left = -50
		halo.offset_right = 50
		halo.offset_top = -50
		halo.offset_bottom = 50
		wrap.add_child(halo)

	var back := TextureRect.new()
	back.name = "LoadingWrit"
	back.texture = CARD_BACK_TEXTURE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, parent)
	wrap.add_child(back)
	parent.add_child(wrap)
	return {"wrapper": wrap, "back": back}


func _hydrate_forge_preview_pair(entries: Array, upgrade_btn: Button,
		build_gen: int, compare_row: HBoxContainer) -> void:
	var row_ref: WeakRef = weakref(compare_row)
	var still_here := func() -> bool:
		var live_row: Node = row_ref.get_ref()
		return _ui_build_is_current(build_gen, Mode.CONFIRM_UPGRADE, live_row) \
			and _selected_card_index >= 0
	# Present the complete base/back/arrow/back comparison before shaping either
	# face. This is also the warm-cache boundary, so every entry looks identical.
	await get_tree().process_frame
	if not still_here.call():
		return
	var datas: Array = []
	for entry in entries:
		datas.append(entry.data)
	if DisplayServer.get_name() != "headless":
		await CardTextureCache.bake_many(datas, still_here)
		if not still_here.call():
			return

	var windowed := DisplayServer.get_name() != "headless"
	var cards: Array[Control] = []
	for entry in entries:
		if not still_here.call():
			return
		var shell: Dictionary = entry.shell
		var wrapper: Control = shell.wrapper
		var back: Control = shell.back
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = entry.data
		card_node.live_baked_mode = true
		card_node.defer_baked_rules_text = windowed
		card_node.visible = false
		card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, back.get_index())
		cards.append(card_node)
		if windowed:
			await RenderingServer.frame_post_draw
			if not still_here.call():
				return
			card_node.complete_deferred_baked_rules()
			await RenderingServer.frame_post_draw
			if not still_here.call():
				return

	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not snap:
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for entry in entries:
			Motion.flip_out((entry.shell as Dictionary).back, 0.13)
		await get_tree().create_timer(Motion.time(0.13)).timeout
		if not still_here.call():
			return
	for i in range(cards.size()):
		var back: Control = (entries[i].shell as Dictionary).back
		if snap and is_instance_valid(back):
			back.queue_free()
		cards[i].visible = true
		if not snap:
			Motion.flip_in(cards[i], 0.0, 0.16)
	upgrade_btn.disabled = false
	upgrade_btn.mouse_filter = Control.MOUSE_FILTER_STOP


# Big gold "→" arrow between the two cards.
func _add_arrow_glyph(parent: Container) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80, 400)
	var arrow = GameTheme.make_label("→", 80, GameTheme.GILT_BRIGHT)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	spacer.add_child(arrow)
	parent.add_child(spacer)


# Builds a short "Δ this, Δ that" string by diffing base vs upgraded card
# data. Pure presentation — never changes deck state. Empty string if the
# data dicts are identical for some reason (defensive — shouldn't happen).
func _build_change_summary(base: Dictionary, upgraded: Dictionary) -> String:
	var parts: Array[String] = []
	if base.get("type", "") == "creature":
		var base_atk: int = int(base.get("atk", 0))
		var up_atk: int = int(upgraded.get("atk", 0))
		if up_atk != base_atk:
			parts.append("ATK %d → %d" % [base_atk, up_atk])
		var base_hp: int = int(base.get("hp", 0))
		var up_hp: int = int(upgraded.get("hp", 0))
		if up_hp != base_hp:
			parts.append("HP %d → %d" % [base_hp, up_hp])
	var base_cost: int = int(base.get("cost", 0))
	var up_cost: int = int(upgraded.get("cost", 0))
	if up_cost != base_cost:
		parts.append("Cost %d → %d" % [base_cost, up_cost])
	# Spell value bump (for non-custom spells with a numeric value field).
	if base.has("spell") and upgraded.has("spell"):
		var base_v: int = int(base.spell.get("value", 0))
		var up_v: int = int(upgraded.spell.get("value", 0))
		if up_v != base_v:
			parts.append("Power %d → %d" % [base_v, up_v])
	# Keyword diffs.
	var base_kw: Array = base.get("keywords", [])
	var up_kw: Array = upgraded.get("keywords", [])
	var added: Array[String] = []
	var removed: Array[String] = []
	for kw in up_kw:
		if not base_kw.has(kw):
			added.append(String(kw))
	for kw in base_kw:
		if not up_kw.has(kw):
			removed.append(String(kw))
	if not added.is_empty():
		parts.append("+ " + ", ".join(added))
	if not removed.is_empty():
		parts.append("- " + ", ".join(removed))
	if parts.is_empty():
		return "Effect improved — see the upgraded card."
	return "   ·   ".join(parts)


# CANCEL inside CONFIRM_UPGRADE returns to PICK_CARD (not all the way back
# to CHOOSE). _reforge_remaining is preserved so the player doesn't lose
# their Whetstone pick by backing out of the preview.
func _back_to_pick_card() -> void:
	# Live across _do_upgrade's forge-strike await, and by then the forge is
	# already written to the deck — rebuilding the picker under it would leave
	# the resolver to change scenes out from under a screen the player is using.
	if _leaving or _forge_resolving:
		return
	_selected_card_index = -1
	_begin_pick_card_for_upgrade()


func _do_upgrade(path: String, keyword: String = "") -> void:
	if _selected_card_index < 0:
		return
	RunState.upgrade_card(_selected_card_index, path, keyword)
	AudioBank.play_sfx("upgrade_confirm")  # silently no-ops if asset missing
	_selected_card_index = -1
	_forged_this_visit = true
	# THE WHETSTONE IS SPENT ON ITS FIRST STRIKE, NOT ITS SECOND. Marking it only
	# when the SECOND pick landed meant Cancel/Esc after the first left the relic
	# unspent with _reforge_is_live() true again — FORGE TWO could be re-armed
	# without limit, forging the whole deck at one camp. The second pick is driven
	# by _reforge_remaining, not by _reforge_is_live(), so claiming the relic here
	# does not cut the pair short.
	if _reforge_remaining > 0:
		RunState.whetstone_used_this_act = true
	# The strike: the forged card flashes white-hot and anvil sparks fall
	# before the screen moves on — the game's most permanent decision now
	# lands with the hammer instead of an instant scene change.
	_forge_resolving = true
	await GameTheme.forge_strike(self, find_child("ForgedPreview", true, false))
	_forge_resolving = false
	# Something may have left the camp while the hammer was falling (see _leaving)
	# — resuming here would count the visit a second time and fire a second scene
	# change on top of the one already in flight.
	if _leaving:
		return
	# Reforge: loop back to pick-card for the remaining upgrade(s). Decrement
	# BEFORE the check — the upgrade that just resolved counted against the
	# starting "2 picks."
	if _reforge_remaining > 0:
		_reforge_remaining -= 1
		if _reforge_remaining > 0:
			_begin_pick_card_for_upgrade()
			return
	_leaving = true
	RunState.register_rest_visit()
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


# The one back-out for the upgrade sub-flow (Cancel button and Esc both land
# here). Before any forge has landed this is a free "changed my mind" — back to
# the banner picker, Whetstone untouched. AFTER a forge has landed the camp's
# action is spent, so it leaves for the map: returning to CHOOSE there would
# hand out a second camp action (forge one card, then take the heal too).
func _back_out_of_upgrade() -> void:
	if _leaving or _forge_resolving:
		return
	_reforge_remaining = 0
	_selected_card_index = -1
	if _forged_this_visit:
		# register_rest_visit() increments counters and saves, so it must not run
		# twice — the scene lives on through the fade, and Cancel stays clickable.
		_leaving = true
		RunState.register_rest_visit()
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
		return
	_build_choice_ui()


# Cancel button — only shown in the deeper modes (PICK_CARD, CONFIRM_UPGRADE).
func _add_cancel_btn() -> void:
	var btn = GameTheme.make_back_button("Cancel", Vector2(140, 40))
	btn.position = Vector2(740, 810)
	btn.pressed.connect(_back_out_of_upgrade)
	add_child(btn)
	GameTheme.deal_in(btn, 0.24)
	GameTheme.hover_lift(btn, 1.03)


func _clear_ui() -> void:
	_ui_build_gen += 1
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere" \
				and child.name != "CampfireGlow" and child.name != "CampfireSparks":
			# Avoid one frame rendering both outgoing and incoming mode trees.
			remove_child(child)
			child.queue_free()


func _ui_build_is_current(gen: int, wanted_mode: int, owner: Node) -> bool:
	return _ui_build_gen == gen and _mode == wanted_mode and is_inside_tree() \
		and owner != null and is_instance_valid(owner) and owner.is_inside_tree()
