extends "res://scripts/scenes/MapTerrain.gd"

# ── MAP VIEW — the live map screen ──────────────────────────────────────────
# MapTerrain draws the static campaign plate (Sicily, carved roads, political
# layer); this script layers the game on top: clickable site buttons (hover
# ring + tooltip with encounter/mutator intel), the node → scene flow, the
# top HUD (HP / gold / relics / potions / deck), the deck viewer, per-act
# meta-relic pickers, and the return-to-map save checkpoint.
# The previous parchment-chart implementation is preserved at
# tools/screenshot/MapView_parchment.gd.bak.

const COMBAT_SCENE := "res://scenes/combat.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const REST_SCENE := "res://scenes/rest.tscn"
const EVENT_SCENE := "res://scenes/event.tscn"
const TREASURE_SCENE := "res://scenes/treasure.tscn"
const RECRUIT_SCENE := "res://scenes/recruit.tscn"
const WAYSIDE_SCENE := "res://scenes/wayside.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const CARD_SCENE := preload("res://scenes/card_2d.tscn")

const HIT_R := 26.0           # click radius, normal site chip
const BOSS_HIT := 46.0        # click radius, the keep

# Phase 2.5 — the tooltip's route-planning line per ground type. Keywords
# stay Capitalized (COPY_STYLE §4); the phrasing names what the country
# BREEDS, matching the terrain re-deal in RunState.apply_terrain_redeal.
const TERRAIN_TIPS := {
	"woods": "Wooded road — ambush country. Swift and Piercing favor it.",
	"pass": "High pass — hard going. Armored kits hold passes.",
	"ash": "Ash country — the burn. Doom and fire walk here.",
	"meadow": "Meadow road — open country, lighter resistance.",
}

# Wayside halts advertise their verb on the chart (same contract as
# mutators/terrain: the stop's KIND is route-planning intel, the inside is
# the surprise). Names + one-line tells, keyed by node.wayside_id.
const WAYSIDE_TIPS := {
	"drill_yard": ["The Drill Yard",
		"Drill a creature: +1/+1, then push your luck for more."],
	"muster_scale": ["The Quartermaster's Scales",
		"One trade by weight — sell a card for gold, or buy provisions."],
	"standard_bearer": ["The Standard-Bearer",
		"Move one keyword from one of your creatures to another."],
	"supply_cache": ["The Supply Cache",
		"Crack it open — carry away 1 of 3 spoils."],
}

var _hud_root: Control = null
var _overlay: MapPulseOverlay = null
var _marching := false        # commit march in flight — ignore further clicks
var _site_buttons: Array = []  # MapTipButtons re-seated on every zoom/pan
var _help_button: Control = null  # the "?" How-to-Play affordance (top-left)


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	if RunState.finale_stage == 1:
		# The run was saved at the throne door (the finale isn't a map node) —
		# a resume lands here, and the only way out is through.
		get_tree().change_scene_to_file(COMBAT_SCENE)
		return
	# The chart is the screen the player returns to most — rotate the campaign
	# themes (picker excludes the last-played track; positions resume) so the
	# road never drones on one loop.
	AudioBank.play_music_random(["map", "map_b", "map_c", "map_d"])
	# No atmosphere overlay here: the chart plate carries its own mood, and
	# the menu-style vignette just dims it.
	overlay_handles_standard = true
	await get_tree().process_frame
	build_map()
	_build_node_buttons()
	# The one animated layer over the static 25k-primitive plate: available-
	# site pulses, the player's army standard, Etna embers, the commit march.
	_overlay = MapPulseOverlay.new()
	_overlay.map = self
	add_child(_overlay)
	_build_top_hud()
	GameTheme.make_settings_gear(self)
	# Open leaning over the army's position on the chart — the player can
	# wheel out to the full island (or back in) at any time. The per-open
	# plate bake is in flight for a few frames (longer on the act's first
	# open, which also generates + bakes the geography) — wait it out so
	# the ease glides over a single-quad plate instead of heavy frames.
	if _plate_tex == null and _plate_bake_pending:
		await plate_baked
	# Bake the deck's card textures behind the chart (fire-and-forget on the
	# autoload) so the NEXT fight's _prebake_hand_textures is all cache hits —
	# fights used to open with ~1s of visible bake throttle.
	ScenePreload.warm_run_deck()
	# Open AT the dress crossfade band's low edge (DRESS_ZOOM_LO 1.10) so the
	# keep/region/place-name plaques are legible on arrival. The old 1.45 sat
	# above the band, fading every campaign label to zero until the player
	# happened to wheel out; the next pick, 1.15, clipped the keep plaque
	# mid-word at the east screen edge whenever the pan clamped west (the
	# visible plate is only size.x/zoom wide — 1.10 is the largest zoom that
	# still shows the plaque's right edge at ~kp.x + 170).
	_animate_focus(_player_pos if _has_player else _camp_pos, 1.10)
	# Checkpoint: every return to the map captures post-room state (HP, gold,
	# deck changes, relics earned). Clear the room-in-progress fields first so a
	# later resume lands on the map rather than re-entering the room the player
	# just finished. visit_node still saves on entry, so a quit *during* a room
	# resumes back into that room.
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	await _resolve_meta_pickers()
	RunState.save_run()


func _resolve_meta_pickers() -> void:
	# Bottled Talisman: catch-all bind. Reward/Shop/Treasure bind inline at
	# acquire; this covers Event-granted copies and rebinds if the bound card
	# was later removed. The helper no-ops when a valid binding already exists.
	if RunState.has_relic("bottled_talisman"):
		await GameTheme.bind_bottled_talisman(self)
	# Totem Pole: pick a keyword once per act.
	if RunState.has_relic("totem_pole") and RunState.totem_pole_act != RunState.get_act():
		var kw_opts := [
			{"label": "Thorns", "desc": "Friendlies deal 1 damage back when hit.",
				"color": Color(0.30, 0.45, 0.22)},
			{"label": "Swift", "desc": "Friendlies strike in the pre-combat Swift phase.",
				"color": Color(0.25, 0.40, 0.55)},
			{"label": "Regenerate", "desc": "Friendlies heal 1 HP at the start of each round.",
				"color": Color(0.45, 0.35, 0.20)},
			{"label": "Armored", "desc": "Friendlies take 1 less damage from each hit.",
				"color": Color(0.35, 0.35, 0.42)},
		]
		var kw_vals := ["thorns", "swift", "regenerate", "armored"]
		var pick: int = await GameTheme.show_option_picker(self,
			"Totem Pole — keyword for Act %d" % RunState.get_act(), kw_opts)
		if pick >= 0:
			RunState.totem_pole_keyword = kw_vals[pick]
			RunState.totem_pole_act = RunState.get_act()
	# Bone Hourglass: pick a ramp boon once per act.
	if RunState.has_relic("bone_hourglass") and RunState.bone_hourglass_act != RunState.get_act():
		var ramp_opts := [
			{"label": "Front Line", "desc": "+1 ATK to creatures you place in the front row.",
				"color": Color(0.45, 0.25, 0.20)},
			{"label": "Back Line", "desc": "+1 HP to creatures you place in the back row.",
				"color": Color(0.25, 0.35, 0.45)},
			{"label": "Command Tent", "desc": "+1 max Command while both center lanes are full.",
				"color": Color(0.35, 0.30, 0.50)},
		]
		var ramp_vals := ["front_atk", "back_hp", "mana_center"]
		var pick2: int = await GameTheme.show_option_picker(self,
			"Bone Hourglass — boon for Act %d" % RunState.get_act(), ramp_opts)
		if pick2 >= 0:
			RunState.bone_hourglass_choice = ramp_vals[pick2]
			RunState.bone_hourglass_act = RunState.get_act()


# ═══════════════════ SITE BUTTONS ═══════════════════

func _build_node_buttons() -> void:
	# Invisible round-hover buttons over the chips MapTerrain painted. Button
	# hover styleboxes give the highlight without redrawing the 25k-primitive
	# plate; tooltips carry the encounter + mutator intel.
	for nd in _nodes:
		var is_boss: bool = String(nd.type) == "boss"
		var r: float = BOSS_HIT if is_boss else HIT_R
		var btn := MapTipButton.new()
		btn.view = self
		btn.position = (nd.pos as Vector2) - Vector2(r, r)
		btn.size = Vector2(r * 2.0, r * 2.0)
		btn.flat = true
		btn.tooltip_text = _tip(nd)
		var empty := StyleBoxEmpty.new()
		for sb in ["normal", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(sb, empty)
		if bool(nd.vis) or not bool(nd.avail):
			btn.disabled = true
			btn.add_theme_stylebox_override("hover", empty)
		else:
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var hover := StyleBoxFlat.new()
			hover.bg_color = Color(0.95, 0.78, 0.30, 0.16)
			for pr in ["corner_radius_top_left", "corner_radius_top_right",
					"corner_radius_bottom_left", "corner_radius_bottom_right"]:
				hover.set(pr, int(r))
			btn.add_theme_stylebox_override("hover", hover)
		btn.pressed.connect(_on_node_pressed.bind(int(nd.row), int(nd.col)))
		btn.set_meta("plate_pos", nd.pos as Vector2)
		btn.set_meta("hit_r", r)
		_site_buttons.append(btn)
		add_child(btn)
	_apply_view_to_buttons()


## The plate draws through the view transform; the invisible hit buttons are
## real Controls, so they get re-seated (and re-scaled) to match every time
## the zoom or pan changes.
func _on_view_changed() -> void:
	_apply_view_to_buttons()


func _apply_view_to_buttons() -> void:
	for btn in _site_buttons:
		if not is_instance_valid(btn):
			continue
		var p: Vector2 = btn.get_meta("plate_pos")
		var r: float = btn.get_meta("hit_r")
		btn.scale = Vector2(_view_zoom, _view_zoom)
		btn.position = p * _view_zoom + _view_pan - Vector2(r, r) * _view_zoom


## Ease the view from wherever it is onto a plate point — used on map open so
## returning from a fight reads as picking the chart back up where you stand.
func _animate_focus(world: Vector2, target_zoom: float, duration := 0.55) -> void:
	var z0 := _view_zoom
	var p0 := _view_pan
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var z: float = lerpf(z0, target_zoom, t)
		_set_view(z, p0.lerp(size * 0.5 - world * target_zoom, t)),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _tip(nd: Dictionary) -> String:
	var t: String = String(nd.type)
	var label: String = t.capitalize()
	if t == "elite":
		label = "General"  # player-facing name for the elite band
	if t in ["combat", "elite", "boss"] and String(nd.get("encounter_id", "")) != "":
		var enc: Dictionary = EncounterDB.get_encounter(String(nd.encounter_id))
		if not enc.is_empty():
			label = enc.name
	if t == "elite":
		label += "\nA General holds this ground — break them for a relic."
	if t == "recruit":
		label += "\nFree draft — take 1 of 3 cards."
	if t == "wayside":
		var wid: String = String(nd.get("wayside_id", ""))
		if WAYSIDE_TIPS.has(wid):
			label = "%s\n%s" % [WAYSIDE_TIPS[wid][0], WAYSIDE_TIPS[wid][1]]
	if t == "boss":
		# Rival-lord intel: whose keep this is. The gate progress (break N holds)
		# is NOT repeated here — the standing-order banner carries it at all times.
		var rival: String = RunState.get_act_rival()
		if rival != "" and String(nd.get("encounter_id", "")) == "rival_%s" % rival:
			var title: String = String(HeroDB.faction_info(
				HeroDB.get_faction(rival)).get("lord_title", ""))
			if title != "":
				label += "\n%s" % title
	# Mutator tag — surfaces "Stormy: enemies gain Swift" etc. so the player
	# can route around a fight they don't want without entering it first.
	var mut_id: String = String(nd.get("mutator_id", ""))
	if mut_id != "" and MutatorDB.exists(mut_id):
		var mut: Dictionary = MutatorDB.get_mutator(mut_id)
		label += "\n★ %s: %s" % [mut.get("name", mut_id), mut.get("desc", "")]
	# Phase 2.5 — the ground the hold sits on. The terrain line is the
	# route-planning read: it tells you what KIND of fight the country
	# breeds before you commit to the road.
	var terrain: String = String(nd.get("terrain", ""))
	if t in ["combat", "elite"] and TERRAIN_TIPS.has(terrain):
		label += "\n%s" % TERRAIN_TIPS[terrain]
	elif t == "boss" and terrain == "ash":
		label += "\nThe approach is ash the whole way."
	if bool(nd.get("bridge", false)):
		label += "\nBridge crossing — something waits at the water."
	# Pursuit intel — once 2 holds fall the rival's outriders reach every
	# hold still standing. Mirrors the crimson pennant on the chip.
	if t == "combat" and not bool(nd.get("vis", false)) \
			and RunState.holds_broken_in_act >= 2:
		label += "\nPursuit — extra reinforcement on round 2%s." \
			% (" and 4" if RunState.holds_broken_in_act >= 3 else "")
	return label


func _on_node_pressed(row: int, col: int) -> void:
	if _marching:
		return
	var ok := false
	for n in RunState.get_available_nodes():
		if int(n.row) == row and int(n.col) == col:
			ok = true
			break
	if not ok:
		return
	var dest := Vector2.ZERO
	for nd in _nodes:
		if int(nd.row) == row and int(nd.col) == col:
			dest = nd.pos
			break
	# Capture the march origin before visiting flips availability state.
	var from_p: Vector2 = _player_pos if _has_player else _camp_pos
	_marching = true
	AudioBank.play_sfx("button_click")
	RunState.visit_node(row, col)
	var ntype: String = RunState.current_node_type
	var target := ""
	match ntype:
		"combat", "elite", "boss": target = COMBAT_SCENE
		"shop": target = SHOP_SCENE
		"rest": target = REST_SCENE
		"event": target = EVENT_SCENE
		"treasure": target = TREASURE_SCENE
		"recruit": target = RECRUIT_SCENE
		"wayside": target = WAYSIDE_SCENE
	# The army marches down the carved road to the chosen site, then the
	# scene fades — the commit reads as a move on the campaign map, not a
	# menu click.
	if _overlay != null:
		await _overlay.march_along(road_path_between(from_p, dest))
	if target != "":
		GameTheme.fade_out_then_change_scene(self, target, 0.30)
	else:
		_marching = false


# ═══════════════════ TOP HUD ═══════════════════

func _build_top_hud() -> void:
	const ROW_Y := 18.0
	const ROW_H := 40.0
	const ICON := 40.0
	const GAP := 12.0
	const FONT_SZ := 26
	_hud_root = Control.new()
	_hud_root.name = "HudRoot"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)

	# Ink band under each resource group — the same panel material as the
	# chart's legend and cartouche (one panel style across the screen). The
	# numerals used to float on the lit parchment with only their outlines
	# saving them; on dark ink the ivory figures actually read, and gold ink
	# can be RESERVED for the coin count so "gold = currency" means something.
	var band_l := _place_hud_band()

	# Left group — one 8px rhythm across the corner: gear 14..62, "?" 70..110,
	# band from 118, and every element centred on y=38 (the band's mid-line).
	# MapTerrain's title cartouche below docks to the SAME x=118 rail, so the
	# corner reads as one aligned column instead of four staggered edges.
	var x := 128.0
	_place_painted_icon(GameTheme.tex_hud_heart, Vector2(x, ROW_Y),
		ICON, Color.WHITE)
	_place_centred_label(
		"%d/%d" % [RunState.hero_hp, RunState.hero_max_hp],
		Rect2(x + ICON + GAP, ROW_Y, 130, ROW_H),
		Color(0.94, 0.90, 0.82), FONT_SZ)
	x += ICON + GAP + 145

	const GOLD_ICON := 50.0
	var gold_y: float = ROW_Y - (GOLD_ICON - ICON) * 0.5
	_place_painted_icon(GameTheme.tex_hud_gold, Vector2(x, gold_y),
		GOLD_ICON, Color.WHITE)
	_place_centred_label(str(RunState.gold),
		Rect2(x + GOLD_ICON + GAP, ROW_Y, 90, ROW_H),
		Color(1.0, 0.90, 0.45), FONT_SZ)
	x += GOLD_ICON + GAP + 105
	var band_l_end: float = x - 105 + 62 + 78  # gold numeral end + breath

	if RunState.relics.size() > 0:
		# Clickable since 2026-07-02 — opens the relic roll. The deck always
		# had a viewer; the relic count was a dead "×N" you couldn't inspect
		# anywhere outside combat. Button first (same layering trick as the
		# deck button), icon + label painted on top with mouse_filter IGNORE.
		var rbtn := MapTipButton.new()
		rbtn.view = self
		rbtn.flat = true
		rbtn.position = Vector2(x - 6.0, ROW_Y)
		rbtn.size = Vector2(ICON + 72.0, ROW_H)
		rbtn.tooltip_text = "View your relics"
		rbtn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var rempty := StyleBoxEmpty.new()
		for sb in ["normal", "pressed", "focus", "disabled"]:
			rbtn.add_theme_stylebox_override(sb, rempty)
		var rhover := StyleBoxFlat.new()
		rhover.bg_color = Color(0.95, 0.78, 0.30, 0.15)
		rhover.set_corner_radius_all(8)
		rbtn.add_theme_stylebox_override("hover", rhover)
		rbtn.pressed.connect(_show_relic_viewer)
		_hud_root.add_child(rbtn)
		# Ivory-silver, NOT gold — a trinket beside the coin, not more coinage.
		# +2y: the pendant is 4px smaller than the row icons, so it needs the
		# nudge to share their vertical centre instead of riding high.
		_place_painted_icon(GameTheme.tex_hud_relic, Vector2(x, ROW_Y + 2.0),
			ICON - 4, Color(0.90, 0.87, 0.78))
		_place_centred_label(str(RunState.relics.size()),
			Rect2(x + ICON + 6, ROW_Y, 50, ROW_H),
			Color(0.94, 0.90, 0.82), FONT_SZ)
		band_l_end = x + (ICON - 4) + 6 + 52
	x = maxf(x, band_l_end + 8.0)
	x += _place_hud_text_button(x, ROW_Y - 2.0, ROW_H + 4.0,
		"COMPANY", "Company ledger — veterans, fallen, and keep progress",
		_show_company_ledger, Color(0.86, 0.76, 0.58)) + 8.0
	x += _place_hud_text_button(x, ROW_Y - 2.0, ROW_H + 4.0,
		"WAR COUNCIL", "Rival briefing — kingdom engine and route advice",
		_show_war_council, GameTheme.GILT_BRIGHT) + 8.0
	if RunState.is_lord_gate_open():
		x += _place_hud_text_button(x, ROW_Y - 2.0, ROW_H + 4.0,
			"MARCH ON KEEP", "The keep road is open — challenge the rival lord now",
			_on_march_to_keep_pressed, Color(1.0, 0.82, 0.34)) + 8.0
	band_l_end = maxf(band_l_end, x)
	band_l.position = Vector2(118.0, ROW_Y - 7.0)
	band_l.size = Vector2(band_l_end - 118.0, ROW_H + 14.0)

	# Right group — anchored off the right canvas edge. With canvas_items
	# stretch the coordinate space is the 1600×900 project viewport, not
	# window pixels; hardcoded x past 1600 lands off-canvas and never draws.
	var band_r := _place_hud_band()
	var right_edge: float = size.x - 24.0
	var deck_w: float = _place_deck_button(right_edge, ROW_Y, ICON, ROW_H, FONT_SZ)
	var px: float = right_edge - deck_w - 12.0 - RunState.MAX_POTIONS * (ICON + 4.0)
	band_r.position = Vector2(px - 10.0, ROW_Y - 7.0)
	band_r.size = Vector2(size.x - 14.0 - (px - 10.0), ROW_H + 14.0)
	for i in range(RunState.MAX_POTIONS):
		var pid: String = RunState.potions[i] if i < RunState.potions.size() else ""
		_place_potion_slot(pid, i, Vector2(px, ROW_Y), ICON)
		px += ICON + 4

	# The How-to-Play affordance. (The standing-order chip that used to float
	# here moved into MapTerrain's corner title cartouche — one docked panel
	# instead of a center stack of floating text.) The help button parents to
	# the scene: it must catch clicks the HUD root passes through.
	_place_help_button()


func _place_hud_text_button(x: float, y: float, h: float, text: String,
		tip: String, callback: Callable, rest_color: Color) -> float:
	var w: float = maxf(116.0, float(text.length()) * 9.0 + 34.0)
	var btn := MapTipButton.new()
	btn.view = self
	btn.flat = true
	btn.position = Vector2(x, y)
	btn.size = Vector2(w, h)
	btn.text = text
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_display != null:
		btn.add_theme_font_override("font", GameTheme.font_display)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", rest_color)
	btn.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	btn.add_theme_constant_override("outline_size", 4)
	var empty := StyleBoxEmpty.new()
	for sb in ["normal", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(sb, empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.95, 0.78, 0.30, 0.14)
	hover.border_color = Color(1.0, 0.86, 0.36, 0.75)
	hover.border_width_bottom = 2
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(callback)
	_hud_root.add_child(btn)
	return w


func _on_march_to_keep_pressed() -> void:
	if _marching:
		return
	var boss := RunState.get_lord_node()
	if boss.is_empty():
		return
	_on_node_pressed(int(boss.get("row", -1)), int(boss.get("col", -1)))



func _place_help_button() -> void:
	# A small "?" beside the settings gear (top-left), opening the same
	# How-to-Play / glossary reference the main menu offers. The gear sits at
	# x≈14 (48px wide); the "?" tucks in just right of it. Re-created on every
	# _refresh_hud, so drop a stale copy first.
	if _help_button != null and is_instance_valid(_help_button):
		_help_button.queue_free()
	const SZ := 40.0
	var btn := MapTipButton.new()
	btn.view = self
	# y=18 centres the 40px circle on the HUD row's mid-line (y=38) — the
	# 48px gear and the 54px ink bands share it; at the old y=14 the "?"
	# floated 4px high of everything beside it.
	btn.position = Vector2(70.0, 18.0)
	btn.size = Vector2(SZ, SZ)
	btn.text = "?"
	btn.tooltip_text = "How to play — campaign primer and keyword glossary"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameTheme.font_display != null:
		btn.add_theme_font_override("font", GameTheme.font_display)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(0.82, 0.66, 0.30, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.35))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	btn.add_theme_constant_override("outline_size", 4)
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.06, 0.05, 0.04, 0.70)
	circle.border_color = Color(0.60, 0.51, 0.34, 0.70)
	circle.set_border_width_all(1)
	circle.set_corner_radius_all(int(SZ / 2.0))
	btn.add_theme_stylebox_override("normal", circle)
	var circle_h := circle.duplicate() as StyleBoxFlat
	circle_h.bg_color = Color(0.12, 0.10, 0.07, 0.85)
	circle_h.border_color = Color(1.0, 0.88, 0.35, 0.85)
	btn.add_theme_stylebox_override("hover", circle_h)
	btn.add_theme_stylebox_override("pressed", circle)
	btn.add_theme_stylebox_override("focus", circle)
	btn.pressed.connect(_show_how_to_play)
	# The HUD root ignores mouse; this button must catch clicks itself, so it
	# parents to the scene rather than _hud_root.
	add_child(btn)
	_help_button = btn


func _refresh_hud() -> void:
	if _hud_root != null and is_instance_valid(_hud_root):
		_hud_root.queue_free()
	_hud_root = null
	_build_top_hud()


func _place_potion_slot(pid: String, index: int, top_left: Vector2, sz: float) -> void:
	# Empty slot: shaded placeholder icon, not clickable.
	if pid == "":
		_place_painted_icon(GameTheme.tex_hud_potion, top_left, sz,
			Color(0.45, 0.40, 0.35, 0.45))
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var icon: Texture2D = PotionDB.icon_for(pid)
	# White silhouette kit carries identity via the potion colour; painted art
	# (PNG, once it exists) renders untinted.
	var tint: Color = data.get("color", Color.WHITE) if not data.is_empty() else Color.WHITE
	if PotionDB.is_painted_icon(pid):
		tint = Color.WHITE
	_place_painted_icon(icon, top_left, sz, tint)
	# Invisible button overlay handles clicks + tooltip.
	var btn := MapTipButton.new()
	btn.view = self
	btn.flat = true
	btn.position = top_left
	btn.size = Vector2(sz, sz)
	var usable_in: String = data.get("usable_in", "combat")
	var map_usable: bool = usable_in == "map" or usable_in == "both"
	var label: String = "%s\n%s" % [data.get("name", pid), data.get("desc", "")]
	if not map_usable:
		label += "\nUsable in combat only"
	btn.tooltip_text = label
	if map_usable:
		btn.pressed.connect(func():
			_use_map_potion(index)
		)
	_hud_root.add_child(btn)


func _use_map_potion(index: int) -> void:
	var pid: String = RunState.potions[index] if index < RunState.potions.size() else ""
	if pid == "":
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect: String = data.get("effect", "")
	match effect:
		"heal_hp":
			RunState.consume_potion(index)
			RunState.heal_hero(8)
		_:
			# Combat-only effects shouldn't even be wired up here, but be safe.
			return
	_refresh_hud()


func _place_hud_band() -> Panel:
	# The legend/cartouche ink-band material (MapTerrain draws the same colours)
	# as a HUD backing panel. Added BEFORE the group's icons so it renders
	# underneath; caller sets position/size once the group's extent is known.
	var band := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.042, 0.036, 0.86)
	sb.border_color = Color(0.60, 0.51, 0.34, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	band.add_theme_stylebox_override("panel", sb)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(band)
	return band


func _place_painted_icon(tex: Texture2D, top_left: Vector2, sz: float,
		tint: Color) -> void:
	if tex == null:
		return
	_hud_root.add_child(_make_constrained_tex(tex, top_left + Vector2(2, 2), sz,
		Color(0, 0, 0, 0.55)))
	_hud_root.add_child(_make_constrained_tex(tex, top_left, sz, tint))


func _make_constrained_tex(tex: Texture2D, top_left: Vector2, sz: float,
		mod: Color) -> TextureRect:
	var ico := TextureRect.new()
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	ico.texture = tex
	ico.custom_minimum_size = Vector2(sz, sz)
	ico.size = Vector2(sz, sz)
	ico.position = top_left
	ico.modulate = mod
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ico


func _place_centred_label(text: String, rect: Rect2, color: Color,
		font_size: int = 22) -> void:
	var wrap := Control.new()
	wrap.position = rect.position
	wrap.size = rect.size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(wrap)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)


func _place_deck_button(right_edge: float, top_y: float, icon_sz: float,
		row_h: float, font_sz: int) -> float:
	const PADDING := 10.0
	const COUNT_W := 50.0
	var btn_w: float = PADDING + icon_sz + 8 + COUNT_W + PADDING
	var top_left := Vector2(right_edge - btn_w, top_y)
	var btn := MapTipButton.new()
	btn.view = self
	btn.size = Vector2(btn_w, row_h)
	btn.position = top_left
	btn.flat = true
	btn.tooltip_text = "View your deck"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for sb in ["normal", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(sb, empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.95, 0.78, 0.30, 0.15)
	for p in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		hover.set(p, 8)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(_show_deck_viewer)
	_hud_root.add_child(btn)
	_place_painted_icon(GameTheme.tex_hud_deck,
		top_left + Vector2(PADDING, 0), icon_sz,
		Color(0.90, 0.87, 0.78))
	_place_centred_label(str(RunState.deck.size()),
		Rect2(top_left.x + PADDING + icon_sz + 8, top_left.y,
			COUNT_W, row_h),
		Color(0.94, 0.90, 0.82), font_sz)
	return btn_w


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Esc closes an open council / ledger / deck / how-to overlay first; from the
	# bare chart it opens the pause/Settings overlay.
	for nm in ["WarCouncilOverlay", "CompanyLedgerOverlay", "DeckOverlay", "HowToPlayOverlay"]:
		var ov := get_node_or_null(nm)
		if ov != null:
			ov.queue_free()
			get_viewport().set_input_as_handled()
			return
	GameTheme.open_settings_overlay()
	get_viewport().set_input_as_handled()


func _make_map_overlay(name: String, title_text: String,
		accent: Color) -> Dictionary:
	var overlay := ColorRect.new()
	overlay.name = name
	overlay.color = Color(0.025, 0.018, 0.014, 0.94)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.position = Vector2(250, 90)
	panel.size = Vector2(1100, 710)
	var st := GameTheme.make_panel_style(
		Color(0.055, 0.043, 0.034, 0.96),
		Color(accent.r, accent.g, accent.b, 0.62),
		2, 6, true, true)
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 24
	st.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", st)
	overlay.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	var title := GameTheme.make_label(title_text, GameTheme.FONT_HEADER, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	return {"overlay": overlay, "root": root}


func _overlay_label(parent: VBoxContainer, text: String, size: int,
		color: Color) -> Label:
	var lbl := GameTheme.make_label(text, size, color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(1010, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(lbl)
	return lbl


func _terrain_summary() -> String:
	var counts := {}
	for nd in _nodes:
		var typ := String(nd.get("type", ""))
		if bool(nd.get("vis", false)) or typ not in ["combat", "elite"]:
			continue
		var terrain := String(nd.get("terrain", ""))
		if terrain == "":
			continue
		counts[terrain] = int(counts.get(terrain, 0)) + 1
	if counts.is_empty():
		return "Road: scout the holds for terrain and mutator tells before you commit."
	var order := ["meadow", "woods", "pass", "ash"]
	var parts: Array[String] = []
	for t in order:
		if counts.has(t):
			parts.append("%s %d" % [t.capitalize(), int(counts[t])])
	return "Road: " + ", ".join(parts) + "."


func _show_war_council() -> void:
	var faction := RunState.get_act_faction()
	var info: Dictionary = HeroDB.faction_info(faction) if faction != "" else {}
	var accent: Color = info.get("color", GameTheme.GILT_BRIGHT) if not info.is_empty() else GameTheme.GILT_BRIGHT
	var shell := _make_map_overlay("WarCouncilOverlay", "WAR COUNCIL", accent.lerp(Color.WHITE, 0.18))
	var overlay: Control = shell.overlay
	var root: VBoxContainer = shell.root

	var rival := RunState.get_act_rival()
	var hero: Dictionary = HeroDB.get_hero(rival) if rival != "" else {}
	var kingdom := String(info.get("name", "this kingdom"))
	var lord_name := String(hero.get("name", "the rival lord"))
	var title := String(info.get("lord_title", ""))
	var engine := String(info.get("engine", ""))
	var engine_line := String(info.get("engine_line", ""))

	_overlay_label(root, "Act %d - %s" % [RunState.get_act(), kingdom], 24,
		GameTheme.GILT_BRIGHT)
	if title != "":
		_overlay_label(root, "%s, %s" % [lord_name, title], 20,
			Color(0.92, 0.86, 0.70))
	elif lord_name != "":
		_overlay_label(root, lord_name, 20, Color(0.92, 0.86, 0.70))
	if engine != "":
		_overlay_label(root, "%s: %s" % [engine, engine_line], 19,
			Color(0.84, 0.92, 0.96))

	var gate_line := "Keep: break %d more %s to open the road." % [
		maxi(RunState.HOLDS_TO_OPEN_LORD - RunState.holds_broken_in_act, 0),
		"hold" if RunState.HOLDS_TO_OPEN_LORD - RunState.holds_broken_in_act == 1 else "holds"]
	if RunState.is_lord_gate_open():
		gate_line = "Keep: the road is open. You can march on the lord now."
	_overlay_label(root, gate_line, 18, Color(0.96, 0.80, 0.48))
	_overlay_label(root, _terrain_summary(), 18, Color(0.80, 0.76, 0.64))

	var advice := {
		"grasswake": "Plan: cover empty lanes early. Letting them ride through is how the toll starts.",
		"last_wall": "Plan: break adjacent pairs before Formation turns a line into a wall.",
		"owed": "Plan: every death feeds them. Kill engines before you farm small bodies.",
		"lanternhall": "Plan: expect spell tricks and exile pressure. Win with clean, early board claims.",
		"everflame": "Plan: Doom and delayed payoffs punish waiting. End fuses before they pay."
	}
	if advice.has(faction):
		_overlay_label(root, String(advice[faction]), 18, GameTheme.IVORY)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	var close := GameTheme.make_back_button("CLOSE", Vector2(140, 42))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): overlay.queue_free())
	root.add_child(close)


func _company_next_line(kills: int, deck_index: int) -> String:
	if kills < RunState.VETERAN_EPITHET_KILLS:
		return "%d to epithet" % (RunState.VETERAN_EPITHET_KILLS - kills)
	if kills < RunState.VETERAN_RANK_KILLS:
		return "%d to +1/+1" % (RunState.VETERAN_RANK_KILLS - kills)
	if kills < RunState.VETERAN_SCHOOL_KILLS:
		return "%d to war school" % (RunState.VETERAN_SCHOOL_KILLS - kills)
	if RunState.has_upgrade_path(deck_index, "war_school"):
		return "war school complete"
	return "war school ready next fight"


func _show_company_ledger() -> void:
	var shell := _make_map_overlay("CompanyLedgerOverlay", "THE COMPANY",
		GameTheme.GILT_BRIGHT)
	var overlay: Control = shell.overlay
	var root: VBoxContainer = shell.root

	var keep_txt := "Keep road open" if RunState.is_lord_gate_open() \
		else "Holds broken %d/%d" % [RunState.holds_broken_in_act, RunState.HOLDS_TO_OPEN_LORD]
	_overlay_label(root, "%s  -  Fallen on the roll: %d" % [
		keep_txt, RunState.fallen.size()], 19, Color(0.92, 0.86, 0.70))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1010, 520)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	var veterans: Array = []
	for i in range(RunState.deck.size()):
		if i >= RunState.deck_uids.size():
			continue
		var uid := int(RunState.deck_uids[i])
		var kills := RunState.get_kills(uid)
		if kills <= 0:
			continue
		var data := RunState.get_upgraded_card_data(i)
		if data.get("type", "") != "creature":
			continue
		veterans.append({"idx": i, "kills": kills,
			"name": String(data.get("name", RunState.deck[i]))})
	veterans.sort_custom(func(a, b): return int(a.kills) > int(b.kills))

	var vhead := GameTheme.make_label("VETERANS", 22, GameTheme.GILT_BRIGHT)
	list.add_child(vhead)
	if veterans.is_empty():
		_overlay_label(list, "No creature has earned a tally yet.", 17,
			Color(0.72, 0.68, 0.58))
	else:
		for v in veterans.slice(0, mini(veterans.size(), 10)):
			_overlay_label(list, "%s - %d kills - %s" % [
				String(v.name), int(v.kills), _company_next_line(int(v.kills), int(v.idx))],
				17, GameTheme.IVORY)

	var fhead := GameTheme.make_label("ROLL OF THE FALLEN", 22, GameTheme.GILT_BRIGHT)
	list.add_child(fhead)
	if RunState.fallen.is_empty():
		_overlay_label(list, "No names on the roll.", 17, Color(0.72, 0.68, 0.58))
	else:
		var start: int = maxi(RunState.fallen.size() - 8, 0)
		for j in range(RunState.fallen.size() - 1, start - 1, -1):
			var f: Dictionary = RunState.fallen[j]
			_overlay_label(list, "%s - Act %d, %s" % [
				String(f.get("name", "the nameless")),
				int(f.get("act", RunState.get_act())),
				String(f.get("enc", "the road"))], 17, Color(0.82, 0.84, 0.92))

	var close := GameTheme.make_back_button("CLOSE", Vector2(140, 42))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): overlay.queue_free())
	root.add_child(close)


# ═══════════════════ DECK VIEWER ═══════════════════

func _show_deck_viewer() -> void:
	var overlay := ColorRect.new()
	overlay.name = "DeckOverlay"
	overlay.color = Color(0.03, 0.02, 0.05, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var title = GameTheme.make_label(
		"YOUR DECK  (%d cards)" % RunState.deck.size(),
		GameTheme.FONT_HEADER, GameTheme.GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 20)
	title.size = Vector2(600, 40)
	overlay.add_child(title)

	var creatures := 0
	var spells := 0
	var rarity_counts := {"starter": 0, "common": 0, "uncommon": 0, "rare": 0}
	for card_id in RunState.deck:
		var cdata = CardDB.get_card_data(card_id)
		if cdata.is_empty():
			continue
		if cdata.get("type", "") == "creature":
			creatures += 1
		else:
			spells += 1
		var r = cdata.get("rarity", "common")
		if rarity_counts.has(r):
			rarity_counts[r] += 1

	var stats_bar := HBoxContainer.new()
	stats_bar.position = Vector2(80, 68)
	stats_bar.size = Vector2(1440, 28)
	stats_bar.add_theme_constant_override("separation", 32)
	overlay.add_child(stats_bar)

	var comp_items = [
		["Creatures: %d" % creatures, Color(0.55, 0.85, 0.55)],
		["Spells: %d" % spells, Color(0.55, 0.70, 0.95)],
		["|", Color(0.4, 0.35, 0.3)],
		["Common: %d" % rarity_counts["common"], Color(0.78, 0.75, 0.68)],
		["Uncommon: %d" % rarity_counts["uncommon"], Color(0.40, 0.75, 0.95)],
		["Rare: %d" % rarity_counts["rare"], Color(0.95, 0.78, 0.25)],
	]
	for item in comp_items:
		var sl = GameTheme.make_label(item[0], GameTheme.FONT_BODY, item[1])
		sl.add_theme_constant_override("outline_size", 3)
		sl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		stats_bar.add_child(sl)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(80, 100)
	scroll.size = Vector2(1440, 690)
	overlay.add_child(scroll)

	var grid := GridContainer.new()
	# 225-wide cards at compact scale (0.483) × 7 cols + 6×18 separation = ~870 px, fits 1440 scroll.
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 22)
	scroll.add_child(grid)

	# Same batched-instantiation approach as the Card Gallery — defers
	# card creation across frames so opening the deck viewer doesn't
	# freeze the main thread. 6 per frame keeps the popup responsive
	# while filling top-down. static_display kills the per-frame costs
	# (pulse, shadows, rare halo) so once spawned the cards are cheap.
	var batch_size := 6
	for batch_start in range(0, RunState.deck.size(), batch_size):
		for k in range(batch_size):
			var i := batch_start + k
			if i >= RunState.deck.size():
				break
			var data = RunState.get_upgraded_card_data(i)
			var card = CARD_SCENE.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = data.get("id", "")
			card.is_on_battlefield = true
			card.static_display = true
			card.live_baked_mode = true
			CardTextureCache.bake(data)
			grid.add_child(card)
		await get_tree().process_frame

	var close_btn = GameTheme.make_back_button("CLOSE", Vector2(140, 40))
	close_btn.position = Vector2(740, 800)
	close_btn.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(close_btn)


# ═══════════════════ RELIC VIEWER ═══════════════════

## The relic roll — every carried relic as a chip + name + rules row. The
## combat HUD shows the chips with hover tooltips; this is the map-side read
## (the "×N" counter opens it).
func _show_relic_viewer() -> void:
	var overlay := ColorRect.new()
	overlay.name = "RelicOverlay"
	overlay.color = Color(0.03, 0.02, 0.05, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var title = GameTheme.make_label(
		"YOUR RELICS  (%d)" % RunState.relics.size(),
		GameTheme.FONT_HEADER, GameTheme.GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 24)
	title.size = Vector2(600, 40)
	overlay.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(300, 90)
	scroll.size = Vector2(1000, 690)
	overlay.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for rid in RunState.relics:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		list.add_child(row)
		var chip := GameTheme.make_relic_chip(rid, 56)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var rd: Dictionary = RelicDB.get_relic(rid)
		var name_lbl = GameTheme.make_label(String(rd.get("name", rid)), 20,
			GameTheme.GILT_BRIGHT)
		col.add_child(name_lbl)
		var desc_lbl = GameTheme.make_label(String(rd.get("desc", "")), 16,
			GameTheme.IVORY)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(840, 0)
		col.add_child(desc_lbl)

	var close_relics = GameTheme.make_back_button("CLOSE", Vector2(140, 40))
	close_relics.position = Vector2(740, 800)
	close_relics.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(close_relics)


# ═══════════════════ HOW TO PLAY / GLOSSARY ═══════════════════
# Mirror of the main menu's reference, reachable mid-run from the "?" HUD
# affordance. All teaching otherwise lives inside Combat.gd; this lets a player
# look up any keyword (or how the campaign works) from the map. Built in code in
# the chart aesthetic and torn down on close. Self-contained: the keyword list
# is sourced live from KeywordEffects.KEYWORDS so it never drifts from the rules.

func _show_how_to_play() -> void:
	if has_node("HowToPlayOverlay"):
		get_node("HowToPlayOverlay").queue_free()
	add_child(GameTheme.make_how_to_play_overlay())


# (How-To-Play overlay now lives in GameTheme.make_how_to_play_overlay — one
# shared builder for both MapView and MainMenu so the primer copy can't drift.)


# ═══════════════════ PARCHMENT TOOLTIP ═══════════════════

## Chart-styled tooltip: gilt name line + dim body on a dark ink panel with
## a tan rule. Replaces the stock gray tooltip box — the one engine-default
## element that would otherwise sit on the hand-drawn plate.
func _build_map_tooltip(text: String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.048, 0.040, 0.97)
	sb.border_color = Color(0.60, 0.51, 0.34, 0.95)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var lines := text.split("\n")
	var name_lbl := Label.new()
	name_lbl.text = lines[0]
	if GameTheme.font_display != null:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	# Name 20px, body 17px (were 18/16) with a dark outline — the site tooltip
	# is the read-before-you-commit intel and was reported too small.
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.96, 0.84, 0.56))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 4)
	box.add_child(name_lbl)
	if lines.size() > 1:
		var body := Label.new()
		body.text = "\n".join(lines.slice(1))
		if body.text.length() > 36:
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.custom_minimum_size = Vector2(300, 0)
		if GameTheme.font_body != null:
			body.add_theme_font_override("font", GameTheme.font_body)
		body.add_theme_font_size_override("font_size", 18)
		body.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
		body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		body.add_theme_constant_override("outline_size", 3)
		box.add_child(body)
	return panel


## Button whose tooltip renders as the chart-styled panel above.
class MapTipButton extends Button:
	var view = null   # the owning MapView

	func _make_custom_tooltip(for_text: String) -> Object:
		if view != null and for_text != "":
			return view._build_map_tooltip(for_text)
		return null


# ═══════════════════ ANIMATED OVERLAY ═══════════════════

## The single animated layer over the static plate: (1) breathing rings on
## reachable sites (crimson on the keep when the boss road opens), (2) the
## player's army standard — a swallow-tailed banner with a ground glow,
## unmistakable among the small conquered pennants, (3) ember puffs drifting
## NE off Etna, (4) the commit march — the standard walks the carved road to
## the chosen site. The 25k-primitive terrain plate never redraws; this node
## redraws a dozen primitives per frame instead.
class MapPulseOverlay extends Control:
	var map = null                # the MapView (MapTerrain state lives there)
	var _t := 0.0
	var _march_pts: PackedVector2Array = PackedVector2Array()
	var _march_cum: PackedFloat32Array = PackedFloat32Array()
	var _march_len := 0.0
	var _march_prog := -1.0       # <0 idle · 0..1 marching (stays at 1 after)
	# Per-edge arc-length cache for the march glints. _edge_curves is built once at
	# map-gen and is index-stable, so these cumulative-length arrays are constant —
	# built lazily on the first draw and reused, instead of rebuilt every frame.
	var _glint_cum: Array = []            # Array[PackedFloat32Array], parallel to _edges
	var _glint_total: PackedFloat32Array = PackedFloat32Array()
	var _glint_built_for := -1            # edge count the cache was built for

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	## Walk the standard along a road curve. Awaitable; progress sticks at 1
	## so the banner stays planted at the destination through the scene fade.
	func march_along(path: PackedVector2Array, duration := 0.55) -> void:
		_march_pts = path
		_march_cum = PackedFloat32Array()
		_march_cum.append(0.0)
		_march_len = 0.0
		for i in range(1, path.size()):
			_march_len += path[i - 1].distance_to(path[i])
			_march_cum.append(_march_len)
		_march_prog = 0.0
		var tw := create_tween()
		tw.tween_property(self, "_march_prog", 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished

	func _march_pos() -> Vector2:
		if _march_pts.size() < 2 or _march_len <= 0.0:
			return _march_pts[-1] if _march_pts.size() > 0 else Vector2.ZERO
		var d := clampf(_march_prog, 0.0, 1.0) * _march_len
		for i in range(1, _march_pts.size()):
			if d <= _march_cum[i]:
				var seg := _march_cum[i] - _march_cum[i - 1]
				var t := 0.0 if seg <= 0.0 else (d - _march_cum[i - 1]) / seg
				return _march_pts[i - 1].lerp(_march_pts[i], t)
		return _march_pts[-1]

	func _ensure_glint_cache() -> void:
		# Build the per-edge cumulative arc-length arrays once. _edge_curves is
		# fixed for the life of the open map, so rebuild only if the edge count
		# changes (a fresh map open with a different topology).
		if map == null:
			return
		var n: int = map._edges.size()
		if _glint_built_for == n and _glint_cum.size() == n:
			return
		_glint_cum = []
		_glint_total = PackedFloat32Array()
		_glint_total.resize(n)
		for ei in range(n):
			var pts: PackedVector2Array = map._edge_curves[ei] if ei < map._edge_curves.size() \
				else PackedVector2Array()
			var cum := PackedFloat32Array()
			cum.append(0.0)
			var total := 0.0
			for i in range(1, pts.size()):
				total += pts[i - 1].distance_to(pts[i])
				cum.append(total)
			_glint_cum.append(cum)
			_glint_total[ei] = total
		_glint_built_for = n

	func _draw() -> void:
		if map == null:
			return
		# All overlay geometry lives in plate coordinates — ride the same
		# view transform as the terrain so rings, standard, and the march
		# stay glued to their sites at any zoom.
		draw_set_transform(map._view_pan, 0.0,
			Vector2(map._view_zoom, map._view_zoom))
		var amber: Color = map.PLAYER_AMBER
		var crimson: Color = map.CRIMSON
		# 1 — breathing rings on the frontier (quiet during the march).
		if _march_prog < 0.0:
			var pulse := 0.5 + 0.5 * sin(_t * 2.6)
			for nd in map._nodes:
				if not bool(nd.avail) or bool(nd.vis):
					continue
				var p: Vector2 = nd.pos
				var is_boss := String(nd.type) == "boss"
				var col := crimson if is_boss else amber
				var rr := (34.0 if is_boss else 24.0) + 3.0 * pulse
				draw_arc(p, rr, 0, TAU, 48,
					Color(col.r, col.g, col.b, 0.10 + 0.24 * pulse), 2.0, true)
				draw_circle(p, rr,
					Color(col.r, col.g, col.b, 0.015 + 0.035 * pulse))
		# 1.5 — march glints: a short runner sliding camp-side → door along
		# each open leg. Direction without shouting — the baked amber dashes
		# carry the state; this just says "that way". Quiet during the march.
		if _march_prog < 0.0:
			_ensure_glint_cache()
			for ei in range(map._edges.size()):
				var e: Dictionary = map._edges[ei]
				if not bool(e.to_avail):
					continue
				var pts: PackedVector2Array = map._edge_curves[ei]
				if pts.size() < 2:
					continue
				var cum: PackedFloat32Array = _glint_cum[ei]
				var total: float = _glint_total[ei]
				if total < 60.0:
					continue
				var ph := fmod(_t * 0.45 + float(ei) * 0.37, 1.0)
				var run := total - 46.0
				var hd := 20.0 + run * ph
				var head: Vector2 = map._route_arc_point(pts, cum, hd)
				var tail: Vector2 = map._route_arc_point(pts, cum,
					maxf(hd - 14.0, 6.0))
				var fade := sin(ph * PI)
				draw_line(tail, head,
					Color(1.0, 0.86, 0.50, 0.30 * fade), 3.0, true)
				draw_circle(head, 2.2, Color(1.0, 0.90, 0.60, 0.50 * fade))
		# 2 — ember puffs off Etna's plume, drifting NE on the strait wind.
		var apex: Vector2 = (map._etna_peak as Vector2) + Vector2(0, -42.0)
		for k in range(3):
			var ph := fmod(_t * 0.16 + float(k) / 3.0, 1.0)
			var pp := apex + Vector2(30.0, -38.0) * ph \
				+ Vector2(sin(_t * 0.9 + float(k) * 2.1) * 4.0, 0)
			draw_circle(pp, 3.5 + 9.0 * ph,
				Color(0.75, 0.70, 0.64, (1.0 - ph) * 0.085))
		# 3 — the army standard: walking the road while marching, otherwise
		# planted at the player's latest conquest (or the camp gate).
		var sp: Vector2
		if _march_prog >= 0.0:
			sp = _march_pos()
		elif bool(map._has_player):
			sp = map._player_pos
		else:
			sp = (map._camp_pos as Vector2) + Vector2(30, -4)
		var sway := sin(_t * 2.3)
		if _march_prog >= 0.0 and _march_prog < 1.0:
			sway = sin(_t * 9.0)   # the banner snaps in the wind on the move
		# The lamplight pool — a breathing warm glow under the standard, the
		# one bright focal point on the chart (the "you are the light on this
		# table" read). Stacked discs so the falloff stays soft.
		draw_circle(sp + Vector2(0, 1), 56.0 + 5.0 * sway,
			Color(1.0, 0.80, 0.42, 0.038 + 0.010 * sway))
		draw_circle(sp + Vector2(0, 1), 34.0 + 3.0 * sway,
			Color(1.0, 0.82, 0.46, 0.055))
		draw_circle(sp + Vector2(0, 2), 13.0 + 2.0 * sway,
			Color(amber.r, amber.g, amber.b, 0.07))
		draw_arc(sp, 19.0 + 1.5 * sway, 0, TAU, 40,
			Color(amber.r, amber.g, amber.b, 0.22), 1.4, true)
		draw_circle(sp + Vector2(1, 3), 3.4, Color(0, 0, 0, 0.45))
		draw_line(sp + Vector2(0, 4), sp + Vector2(0, -36),
			Color(0.05, 0.04, 0.03), 2.4, true)
		draw_circle(sp + Vector2(0, -36), 1.8, Color(0.92, 0.78, 0.42))
		var tip_x := 26.0 + 2.0 * sway
		var flag := PackedVector2Array([
			sp + Vector2(0, -36),
			sp + Vector2(tip_x, -33.0 + 1.2 * sway),
			sp + Vector2(16, -28.5),
			sp + Vector2(tip_x, -24.0 - 1.2 * sway),
			sp + Vector2(0, -21)])
		draw_colored_polygon(flag, amber)
		var outline := flag.duplicate()
		outline.append(flag[0])
		draw_polyline(outline, Color(0.16, 0.11, 0.05, 0.9), 1.2, true)
