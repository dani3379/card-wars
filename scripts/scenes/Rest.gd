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
##                      Whetstone is live — plus HOLD A WAKE with fallen)
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
const ICON_REFORGE := "res://assets/icons/diamond.png"
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
		"rest":    "The road weighs heavy. Even goblins sleep.",
		"upgrade": "Sharpen the edge. The next fight comes fast.",
		"reforge": "Two strikes ready. Twice the heat.",
		"wake":    "Fast ones first over the wall. Say the name.",
	},
	"stalwart": {
		"rest":    "Plant the shield. Tend the wounds.",
		"upgrade": "A better tool outlasts a sharper one.",
		"reforge": "Forge both blade and breastplate. Endure twice.",
		"wake":    "The line holds because the dead still stand in it.",
	},
	"acolyte": {
		"rest":    "The fire remembers names. Mine. Yours.",
		"upgrade": "Sigils deepen by firelight. Trace another.",
		"reforge": "Twin rites. Twin promises. Twin debts.",
		"wake":    "Death is a door. Tonight we knock from this side.",
	},
	"pyromancer": {
		"rest":    "Even fire needs ash to be born from.",
		"upgrade": "Boil the spell down. Less smoke, more burn.",
		"reforge": "Stoke twice. Two spells, two suns.",
		"wake":    "Nothing burns twice. Almost nothing.",
	},
	"kindler": {
		"rest":    "Bank the coals. Even a fire-tender sleeps.",
		"upgrade": "Feed the forge something that remembers being bright.",
		"reforge": "Two irons in the fire. Tend both.",
		"wake":    "Every fire I've fed is still burning somewhere.",
	},
}
const FLAVOR_FALLBACK := {
	"rest":    "Rest by the fire. Heal what hurt today.",
	"upgrade": "Tend the blade. Tomorrow asks more.",
	"reforge": "Twice-forged. The Whetstone hums.",
	"wake":    "Read a name off the roll. The column remembers.",
}

enum Mode { CHOOSE, PICK_CARD, CONFIRM_UPGRADE }

var _mode: int = Mode.CHOOSE
var _selected_card_index: int = -1
# When Reforge is in flight, _reforge_remaining counts down the upgrades the
# player still gets to apply. 0 = single upgrade (the normal Upgrade path);
# 2 = two upgrades (Whetstone Reforge). Decrements after each pick.
var _reforge_remaining: int = 0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	_accent_rest = GameTheme.HEALTH_GREEN
	_accent_upgrade = GameTheme.KEYWORD_GOLD
	_accent_reforge = GameTheme.FLOOP_BLUE
	_accent_wake = Color(0.64, 0.72, 0.88)   # spectral bone-blue
	_swap_background_for_act()
	GameTheme.add_atmosphere(self, "rest", true, _time_of_day_mood_override())
	GameTheme.fade_in(self, 0.26)
	AudioBank.play_music_random(["rest", "rest_b", "rest_c"])
	# Looping fire crackle — silently no-ops if assets/audio/sfx/fire_crackle/
	# is empty (player will hear only the music until the asset ships).
	AudioBank.play_ambience("fire_crackle")
	_build_campfire_life()
	_build_choice_ui()
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# In the upgrade sub-flow (PICK_CARD / CONFIRM_UPGRADE) Esc backs out one
	# level to the banner picker — same as the Cancel button, Whetstone-safe.
	# From the top (CHOOSE) it opens the pause/Settings overlay.
	if _mode != Mode.CHOOSE:
		_reforge_remaining = 0
		_selected_card_index = -1
		_build_choice_ui()
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

	var title = GameTheme.make_screen_title("MAKE CAMP", GameTheme.GILT_BRIGHT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 26
	title.offset_bottom = 90
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var subtitle = GameTheme.make_label(
		"♥ %d / %d" % [RunState.hero_hp, RunState.hero_max_hp],
		20, GameTheme.IVORY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 96
	subtitle.offset_bottom = 124
	add_child(subtitle)
	GameTheme.deal_in(subtitle, 0.08)

	_add_hero_silhouette()

	# Banner row along the bottom third. HBoxContainer centered horizontally
	# so 3 vs 4 banners both look intentional (Reforge appears only when the
	# Whetstone relic is owned AND not yet used this act).
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 60
	row.offset_right = -60
	row.offset_top = -260
	row.offset_bottom = -90
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
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
	sil.position = Vector2(420, 460)
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
	return sh


func _add_choice_rest(row: HBoxContainer) -> void:
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
		ICON_REST, Vector2(340, 160), disabled_reason)
	_wire_banner(banner, row, _accent_rest, _do_heal)


func _add_choice_upgrade(row: HBoxContainer) -> void:
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
		ICON_UPGRADE, Vector2(340, 160), disabled_reason)
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
func _add_choice_reforge_if_available(row: HBoxContainer) -> void:
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
		ICON_REFORGE, Vector2(340, 160), disabled_reason)
	_wire_banner(banner, row, _accent_reforge, _start_reforge_mode)


# Hold a Wake — campaign-memory banner. Read one name off the Roll of the
# Fallen; its shade stands in your front line for the NEXT fight (the camp
# sits right before the keep, so the wake usually arms the boss fight). The
# banner is HIDDEN with an empty roll (no dead options), and disabled when an
# event has already promised the next fight's opening slot.
func _add_choice_wake_if_available(row: HBoxContainer) -> void:
	if RunState.fallen.is_empty():
		return
	var disabled_reason := ""
	if not RunState.next_combat_gift_creature.is_empty():
		disabled_reason = "The next fight is already spoken for."
	var desc := "%s\n◈ A fallen soldier's shade joins the next fight" % _flavor_for("wake", "")
	var banner = GameTheme.make_choice_banner("HOLD A WAKE", desc, _accent_wake,
		ICON_WAKE, Vector2(340, 160), disabled_reason)
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
		"Speak one name over the fire. The shade stands in your line next fight.",
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
	var where_lbl := GameTheme.make_label(where, 15, GameTheme.DESC_DIM)
	where_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(where_lbl)

	var rise_lbl := GameTheme.make_label("Rises at %d/%d" % [int(cand.atk), int(cand.hp)],
		15, GameTheme.KEYWORD_GOLD)
	rise_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rise_lbl)

	return btn


func _on_wake_tile_pressed(btn: Button, cand: Dictionary) -> void:
	if btn == null or not is_instance_valid(btn):
		return
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
func _wire_banner(banner: Control, row: HBoxContainer, accent: Color, on_click: Callable) -> void:
	var deal_delay := 0.12 + float(row.get_child_count()) * 0.06
	row.add_child(banner)
	var click_btn := banner.get_node("ClickButton") as Button
	if click_btn != null and not click_btn.disabled:
		click_btn.pressed.connect(_on_choice_banner_pressed.bind(banner, click_btn, on_click))
		_wire_hover_motion(click_btn, banner, 1.025)
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


func _wire_hover_motion(source: Control, target: Control, lift: float = 1.03) -> void:
	if source == null or target == null:
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	source.mouse_entered.connect(func():
		if not is_instance_valid(target):
			return
		target.pivot_offset = target.size * 0.5
		var tw := target.create_tween()
		tw.tween_property(target, "scale", Vector2(lift, lift), 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	source.mouse_exited.connect(func():
		if not is_instance_valid(target):
			return
		var tw := target.create_tween()
		tw.tween_property(target, "scale", Vector2.ONE, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))


func _make_hotspot_glow(accent: Color) -> TextureRect:
	# Procedural radial gradient — opaque accent at center, fading to fully
	# transparent at the edges. Built once per banner; cheap.
	# Center alpha kept low: this sits behind the tile's body text, so a strong
	# amber center washed the warm-white copy into poor contrast. A faint halo
	# reads as firelight without fighting legibility.
	var grad := Gradient.new()
	grad.set_color(0, Color(accent.r, accent.g, accent.b, 0.26))
	grad.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.width = 320
	grad_tex.height = 200
	var tr := TextureRect.new()
	tr.texture = grad_tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.modulate = Color(1, 1, 1, 0.85)
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
		if UserSettings == null or UserSettings.particles:
			var motes := CPUParticles2D.new()
			motes.position = Vector2(vp.x * 0.5, vp.y * 0.52)
			motes.one_shot = true
			motes.explosiveness = 0.7
			motes.amount = 22
			motes.lifetime = 1.0
			motes.direction = Vector2(0, -1)
			motes.spread = 32.0
			motes.gravity = Vector2(0, -60.0)
			motes.initial_velocity_min = 40.0
			motes.initial_velocity_max = 110.0
			motes.scale_amount_min = 2.0
			motes.scale_amount_max = 4.0
			motes.color = Color(0.55, 0.95, 0.55, 0.85)
			motes.emitting = true
			add_child(motes)
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
	scroll.position = Vector2(100, 110)
	scroll.size = Vector2(1400, 680)
	add_child(scroll)
	GameTheme.deal_in(scroll, 0.12)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)

	var pick_idx := 0
	for i in range(RunState.deck.size()):
		# Forge "+" stays once per card; other mods (drill, banners) don't
		# block the forge — Inscryption stacking.
		if RunState.has_upgrade_path(i, "plus"):
			continue
		# Skip cards with no meaningful upgrade (curses). Players never see them
		# offered as upgrade targets, even though they're in the deck.
		if not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		var data = RunState.get_upgraded_card_data(i)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
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
		click_btn.pressed.connect(_on_upgrade_card_pressed.bind(wrapper, click_btn, i))
		_wire_hover_motion(click_btn, wrapper, 1.025)
		wrapper.add_child(click_btn)
		grid.add_child(wrapper)
		GameTheme.deal_in(wrapper, 0.16 + float(pick_idx) * 0.025)
		pick_idx += 1

	_add_cancel_btn()


func _on_upgrade_card_pressed(wrapper: Control, click_btn: Button, deck_index: int) -> void:
	if click_btn != null and is_instance_valid(click_btn):
		click_btn.disabled = true
	if wrapper != null and is_instance_valid(wrapper):
		GameTheme.claim_pop(wrapper)
	await get_tree().create_timer(_claim_hold()).timeout
	if not is_inside_tree():
		return
	_select_card_for_upgrade(deck_index)


func _select_card_for_upgrade(deck_index: int) -> void:
	_selected_card_index = deck_index
	_show_confirm_upgrade(deck_index)


# The "+" upgrade confirm screen. Shows the card's current state and its
# upgraded counterpart side-by-side with an arrow between, plus a summary of
# what changed. The player commits with UPGRADE or backs out with CANCEL.
# This is the cinematic moment of the rest site — players see exactly what
# they're getting, no random rolls or path picks, just a clean before/after.
func _show_confirm_upgrade(deck_index: int) -> void:
	_mode = Mode.CONFIRM_UPGRADE
	_clear_ui()

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

	_add_preview_card(compare_row, base_data, false)
	_add_arrow_glyph(compare_row)
	_add_preview_card(compare_row, upgraded_data, true)

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
	upgrade_btn.pressed.connect(_do_upgrade.bind("plus", ""))
	btn_row.add_child(upgrade_btn)
	GameTheme.hover_lift(upgrade_btn, 1.03)

	var back_btn = GameTheme.make_back_button("← Back", Vector2(180, 60), 18)
	back_btn.pressed.connect(_back_to_pick_card)
	btn_row.add_child(back_btn)
	GameTheme.hover_lift(back_btn, 1.03)


# Builds a preview Card2D into the comparison row. `is_upgraded_preview`
# adds a green glow behind the card so the upgraded version reads as "the
# good one" without having to label it.
func _add_preview_card(parent: Container, data: Dictionary, is_upgraded_preview: bool) -> void:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(300, 400)
	if is_upgraded_preview:
		# Named so _do_upgrade can aim the forge-strike set-piece at it.
		wrap.name = "ForgedPreview"

	# Green halo behind the upgraded card. Procedural radial gradient, parented
	# at z=-1 so it sits behind the Card2D panel.
	if is_upgraded_preview:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.30, 0.95, 0.40, 0.55))
		grad.set_color(1, Color(0.10, 0.40, 0.15, 0.0))
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

	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	card_node.live_baked_mode = true
	CardTextureCache.bake(data)
	wrap.add_child(card_node)
	parent.add_child(wrap)


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
	_selected_card_index = -1
	_begin_pick_card_for_upgrade()


func _do_upgrade(path: String, keyword: String = "") -> void:
	if _selected_card_index < 0:
		return
	RunState.upgrade_card(_selected_card_index, path, keyword)
	AudioBank.play_sfx("upgrade_confirm")  # silently no-ops if asset missing
	_selected_card_index = -1
	# The strike: the forged card flashes white-hot and anvil sparks fall
	# before the screen moves on — the game's most permanent decision now
	# lands with the hammer instead of an instant scene change.
	await GameTheme.forge_strike(self, find_child("ForgedPreview", true, false))
	# Reforge: loop back to pick-card for the remaining upgrade(s). Decrement
	# BEFORE the check — the upgrade that just resolved counted against the
	# starting "2 picks." When the last pick lands, the relic is consumed.
	if _reforge_remaining > 0:
		_reforge_remaining -= 1
		if _reforge_remaining > 0:
			_begin_pick_card_for_upgrade()
			return
		else:
			RunState.whetstone_used_this_act = true
	RunState.register_rest_visit()
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


# Cancel button — only shown in the deeper modes (PICK_CARD, CONFIRM_UPGRADE).
# Returns the player to the choose-screen without consuming Whetstone. If a
# Reforge was in flight, the in-flight counter is reset so cancelling truly
# backs out instead of leaving 1 upgrade dangling.
func _add_cancel_btn() -> void:
	var btn = GameTheme.make_back_button("Cancel", Vector2(140, 40))
	btn.position = Vector2(740, 810)
	btn.pressed.connect(func():
		_reforge_remaining = 0
		_selected_card_index = -1
		_build_choice_ui()
	)
	add_child(btn)
	GameTheme.deal_in(btn, 0.24)
	GameTheme.hover_lift(btn, 1.03)


func _clear_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere" \
				and child.name != "CampfireGlow" and child.name != "CampfireSparks":
			child.queue_free()
