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
	"muster_scale": ["The Trading Scales",
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
	# Per-act chart score: each act carries its own anchor over a shared bed,
	# so the campaign darkens musically as the scorch spreads.
	match RunState.get_act():
		2: AudioBank.play_music_random(["map_act2", "map_c", "map_d"])
		3: AudioBank.play_music_random(["map_act3", "map", "map_d"])
		_: AudioBank.play_music_random(["map", "map_b", "map_e"])
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
	GameTheme.fade_in(self, 0.22)
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
	# Frontier reveal: once the focus glide is under way, the roads open —
	# each reachable site lights up in order of distance from the standard,
	# then settles into the idle breathing pulse. "Here are your roads."
	if _overlay != null:
		_overlay.play_frontier_reveal(0.55)
	# Checkpoint: every return to the map captures post-room state (HP, gold,
	# deck changes, relics earned). Clear the room-in-progress fields first so a
	# later resume lands on the map rather than re-entering the room the player
	# just finished. visit_node still saves on entry, so a quit *during* a room
	# resumes back into that room.
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	await _resolve_meta_pickers()
	# A Daily attempt begins at the first durable map checkpoint, not while the
	# War Chest is still open. That keeps "marching" records resumable.
	if RunState.is_daily_run:
		MetaState.record_daily_start(RunState.current_hero_id,
			RunState.active_slot, RunState.daily_date)
	RunState.save_run()


func _resolve_meta_pickers() -> void:
	# Bottled Talisman: catch-all bind. Reward/Shop/Treasure bind inline at
	# acquire; this covers Event-granted copies and rebinds if the bound card
	# was later removed. The helper no-ops when a valid binding already exists.
	if RunState.has_relic("bottled_talisman"):
		await GameTheme.bind_bottled_talisman(self)
	# Articles of War: a one-time tribe commitment. Only tribes currently in the
	# company are offered, so the positive boss relic cannot be chosen blank.
	if RunState.has_relic("articles_of_war") and RunState.articles_of_war_tribe == "":
		var tribe_counts: Dictionary = {}
		for cid in RunState.deck:
			var cd: Dictionary = CardDB.get_card_data(cid)
			if cd.get("type", "") != "creature":
				continue
			var tribe: String = String(cd.get("ctype", ""))
			if tribe != "":
				tribe_counts[tribe] = int(tribe_counts.get(tribe, 0)) + 1
		var tribes: Array = tribe_counts.keys()
		tribes.sort_custom(func(a, b):
			var ac: int = int(tribe_counts[a])
			var bc: int = int(tribe_counts[b])
			return ac > bc if ac != bc else String(a) < String(b))
		var tribe_opts: Array = []
		for tribe in tribes:
			tribe_opts.append({
				"label": String(tribe).capitalize(),
				"desc": "%d creature%s — they cost 1 less, minimum 1." % [
					int(tribe_counts[tribe]), "s" if int(tribe_counts[tribe]) != 1 else ""],
				"color": Color(0.34, 0.24, 0.13),
			})
		if not tribe_opts.is_empty():
			var tribe_pick: int = await GameTheme.show_option_picker(self,
				"The Articles of War — choose a tribe", tribe_opts)
			if tribe_pick >= 0:
				RunState.articles_of_war_tribe = String(tribes[tribe_pick])
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
			btn.mouse_entered.connect(_on_node_hovered.bind(nd, true))
			btn.mouse_exited.connect(_on_node_hovered.bind(nd, false))
		btn.pressed.connect(_on_node_pressed.bind(int(nd.row), int(nd.col)))
		btn.set_meta("plate_pos", nd.pos as Vector2)
		btn.set_meta("hit_r", r)
		_site_buttons.append(btn)
		add_child(btn)
	_apply_view_to_buttons()


func _on_node_hovered(nd: Dictionary, hovered: bool) -> void:
	if _overlay == null or _marching:
		return
	if not hovered:
		_overlay.clear_route_preview()
		return
	if not bool(nd.get("avail", false)) or bool(nd.get("vis", false)):
		_overlay.clear_route_preview()
		return
	if String(nd.get("type", "")) in ["combat", "elite", "boss"]:
		ScenePreload.begin_warm_encounter_art(
			String(nd.get("encounter_id", "")))
	var from_p: Vector2 = _player_pos if _has_player else _camp_pos
	var dest: Vector2 = nd.get("pos", Vector2.ZERO)
	if dest == Vector2.ZERO:
		_overlay.clear_route_preview()
		return
	_overlay.preview_route(road_path_between(from_p, dest), dest,
		_site_label_for_preview(nd))


func _site_label_for_preview(nd: Dictionary) -> String:
	var typ := String(nd.get("type", ""))
	if typ == "elite":
		return "GENERAL"
	if typ == "boss":
		return "KEEP"
	if String(nd.get("setpiece_id", "")) != "":
		return "NAMED ACTION"
	if typ == "combat":
		return "HOLD"
	if typ == "arsenal":
		return "SUPPLY CACHE"
	if typ == "treasure":
		return "RELIC CACHE"
	if typ == "wayside":
		var wid: String = String(nd.get("wayside_id", ""))
		if WAYSIDE_TIPS.has(wid):
			return String(WAYSIDE_TIPS[wid][0]).to_upper()
	return typ.to_upper()


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
	# A NAMED ACTION states its whole bargain on the chart: the ground, the
	# order, the trophy and the TOLL. This is the one node type whose failure
	# costs HP without ending the run, so the price has to be readable from the
	# road — a toll the player only discovers after committing would be a trap,
	# and this game does not set traps for the player.
	var sp_id: String = String(nd.get("setpiece_id", ""))
	if sp_id != "" and SetPieceDB.exists(sp_id):
		var sp: Dictionary = SetPieceDB.get_set_piece(sp_id)
		label = "%s
A NAMED ACTION" % String(sp.get("name", sp_id))
		var ground: Dictionary = sp.get("ground", {})
		if String(ground.get("text", "")) != "":
			label += "
%s: %s" % [String(ground.get("name", "")).capitalize(),
				String(ground.get("text", ""))]
		label += "
Order: %s" % SetPieceDB.objective_label(sp_id)
		var sp_trophy: String = String(sp.get("trophy", {}).get("relic", ""))
		if sp_trophy != "":
			label += "
Carry it: %s + %d gold" % [
				String(RelicDB.get_relic(sp_trophy).get("name", sp_trophy)),
				int(sp.get("gold", 0))]
		var sp_toll: int = int(sp.get("toll", 0))
		if sp_toll > 0:
			label += "
Failure: lose %d HP and forfeit the prize." % sp_toll
		return label
	if t == "elite":
		label += "\nA General holds this ground. Win to gain a relic."
	if t == "recruit":
		label = "Recruit Camp\nChoose 1 of 3 cards for free."
	if t == "shop":
		label = "Trader's Wagon\nBuy cards, relics, and potions, or sell one card."
	if t == "rest":
		label = "Make Camp\nHeal, upgrade cards, or hold a wake."
	if t == "event":
		label = "Something on the Road\nAn event with several choices."
	if t == "treasure":
		label = "Relic Cache\nReveal one relic. Take it or choose gold."
	if t == "arsenal":
		label = "Supply Cache\nChoose a card upgrade, potions, or gold."
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
		var siege := EncounterDB.get_siege(String(nd.get("encounter_id", "")))
		if not siege.is_empty():
			label += "\nCapital siege: %s" % String(siege.get(
				"brief", "Break the defenses, then defeat the lord."))
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
	var dest_nd: Dictionary = {}
	for nd in _nodes:
		if int(nd.row) == row and int(nd.col) == col:
			dest = nd.pos
			dest_nd = nd
			break
	# Capture the march origin before visiting flips availability state.
	var from_p: Vector2 = _player_pos if _has_player else _camp_pos
	_marching = true
	AudioBank.play_sfx("button_click")
	RunState.visit_node(row, col)
	var ntype: String = RunState.current_node_type
	if ntype in ["combat", "elite", "boss"]:
		ScenePreload.begin_warm_encounter_art(RunState.current_encounter_id)
	var target := ""
	match ntype:
		"combat", "elite", "boss": target = COMBAT_SCENE
		"shop": target = SHOP_SCENE
		"rest": target = REST_SCENE
		"event": target = EVENT_SCENE
		"treasure", "arsenal": target = TREASURE_SCENE
		"recruit": target = RECRUIT_SCENE
		"wayside": target = WAYSIDE_SCENE
	# The army marches down the carved road to the chosen site, then the
	# scene fades — the commit reads as a move on the campaign map, not a
	# menu click.
	if _overlay != null:
		_overlay.clear_route_preview()
		await _overlay.march_along(road_path_between(from_p, dest),
			_site_label_for_preview(dest_nd))
	if ntype in ["combat", "elite", "boss"]:
		await ScenePreload.wait_for_encounter_art(RunState.current_encounter_id)
	if target != "":
		# Bloom the signature ink transition from the site the standard reached.
		# The scene handoff now belongs to the committed place, not a fixed corner.
		var screen_dest: Vector2 = dest * _view_zoom + _view_pan
		var origin_uv := Vector2(0.08, 0.10)
		if size.x > 0.0 and size.y > 0.0:
			origin_uv = Vector2(screen_dest.x / size.x, screen_dest.y / size.y)
		GameTheme.fade_out_then_change_scene(self, target, 0.30, origin_uv)
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
	# The army's blood is an oxblood wax seal — the same wax that means HP on
	# every card face and the combat plaques, so the icon IS the color code.
	# (Its predecessor, tex_hud_heart, was a glossy valentine heart — the one
	# emoji-register icon on the whole war table.)
	var hp_seal = preload("res://scripts/ui/painters/WaxSeal.gd").new()
	hp_seal.wax = Color(0.51, 0.137, 0.106)
	hp_seal.seed_text = "map_hp"
	hp_seal.position = Vector2(x, ROW_Y)
	hp_seal.size = Vector2(ICON, ICON)
	_hud_root.add_child(hp_seal)
	_place_centred_label(
		"%d/%d" % [RunState.hero_hp, RunState.hero_max_hp],
		Rect2(x + ICON + GAP, ROW_Y, 130, ROW_H),
		Color(0.94, 0.90, 0.82), FONT_SZ)
	x += ICON + GAP + 145

	const GOLD_ICON := 50.0
	var gold_y: float = ROW_Y - (GOLD_ICON - ICON) * 0.5
	# The purse is the Old King's coinage (CoinProp — the event tables' mint),
	# not a flat gilt disc.
	var purse = preload("res://scripts/ui/painters/CoinProp.gd").new()
	purse.seed_text = "map_purse"
	purse.position = Vector2(x, gold_y)
	purse.size = Vector2(GOLD_ICON, GOLD_ICON)
	_hud_root.add_child(purse)
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
	var w: float = maxf(116.0, float(text.length()) * 9.6 + 34.0)
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
	btn.add_theme_font_size_override("font_size", 16)
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

	var gate_line := "Keep: win %d more %s to open the road." % [
		maxi(RunState.HOLDS_TO_OPEN_LORD - RunState.holds_broken_in_act, 0),
		"hold" if RunState.HOLDS_TO_OPEN_LORD - RunState.holds_broken_in_act == 1 else "holds"]
	if RunState.is_lord_gate_open():
		gate_line = "Keep: the road is open. You can challenge the lord now."
	_overlay_label(root, gate_line, 18, Color(0.96, 0.80, 0.48))
	_overlay_label(root, _terrain_summary(), 18, Color(0.80, 0.76, 0.64))

	var advice := {
		"grasswake": "Plan: cover empty lanes early. Their riders punish gaps.",
		"last_wall": "Plan: separate adjacent enemies before Formation strengthens them.",
		"owed": "Plan: enemy deaths trigger many of their effects. Destroy key creatures first.",
		"lanternhall": "Plan: expect spell effects and cards removed from your draw pile. Build your board early.",
		"everflame": "Plan: watch Doom timers and destroy those creatures before they detonate."
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
	# The ladder in reading order: name + school at 3, rank at 6, doctrine at 10.
	# Each rung reports the SOONEST thing still owed, so an unclaimed choice always
	# outranks a distance — an owed pick the player never noticed is the one
	# failure this readout exists to prevent.
	if kills < RunState.veteran_epithet_kills():
		return "%d to a name and a war school" % (
			RunState.veteran_epithet_kills() - kills)
	if not RunState.has_upgrade_path(deck_index, "war_school"):
		return "war school ready next fight"
	if kills < RunState.VETERAN_RANK_KILLS:
		return "%d to +1/+1" % (RunState.VETERAN_RANK_KILLS - kills)
	if kills < RunState.veteran_doctrine_kills():
		return "%d to a doctrine" % (RunState.veteran_doctrine_kills() - kills)
	if RunState.has_upgrade_path(deck_index, "doctrine"):
		return "fully trained"
	return "doctrine ready next fight"


func _company_spotlight_line() -> String:
	var best_name := ""
	var best_kills := -1
	var best_gap := 999
	var best_next := ""
	var saw_creature := false
	for i in range(RunState.deck.size()):
		if i >= RunState.deck_uids.size():
			continue
		var data := RunState.get_upgraded_card_data(i)
		if data.get("type", "") != "creature":
			continue
		saw_creature = true
		var uid := int(RunState.deck_uids[i])
		var kills := RunState.get_kills(uid)
		# An UNCLAIMED choice always takes the spotlight over a countdown, and the
		# doctrine outranks the school because a card holding both owes the later
		# one. Both are checked before any distance is computed.
		if kills >= RunState.veteran_doctrine_kills() \
				and not RunState.has_upgrade_path(i, "doctrine"):
			return "Doctrine waiting: %s specialises next fight." \
				% String(data.get("name", RunState.deck[i]))
		if kills >= RunState.veteran_school_kills() \
				and not RunState.has_upgrade_path(i, "war_school"):
			return "War school waiting: %s chooses Armored, Swift, or Thorns next fight." \
				% String(data.get("name", RunState.deck[i]))
		var gap := 999
		if kills < RunState.veteran_epithet_kills():
			gap = RunState.veteran_epithet_kills() - kills
		elif kills < RunState.VETERAN_RANK_KILLS:
			gap = RunState.VETERAN_RANK_KILLS - kills
		elif kills < RunState.veteran_doctrine_kills():
			gap = RunState.veteran_doctrine_kills() - kills
		else:
			continue
		if kills > 0 and (gap < best_gap or (gap == best_gap and kills > best_kills)):
			best_gap = gap
			best_kills = kills
			best_next = _company_next_line(kills, i)
			best_name = String(data.get("name", RunState.deck[i]))
	if best_name != "":
		return "Next honor: %s - %d kills, %s." % [best_name, best_kills, best_next]
	if saw_creature:
		return "No creature has a tally yet. Three kills earns a name."
	return "No creatures march in this company."


func _show_company_ledger() -> void:
	var shell := _make_map_overlay("CompanyLedgerOverlay", "THE COMPANY",
		GameTheme.GILT_BRIGHT)
	var overlay: Control = shell.overlay
	var root: VBoxContainer = shell.root

	var keep_txt := "Keep road open" if RunState.is_lord_gate_open() \
		else "Holds broken %d/%d" % [RunState.holds_broken_in_act, RunState.HOLDS_TO_OPEN_LORD]
	_overlay_label(root, "%s  -  Fallen on the roll: %d" % [
		keep_txt, RunState.fallen.size()], 19, Color(0.92, 0.86, 0.70))
	_overlay_label(root, _company_spotlight_line(), 18, GameTheme.IVORY)

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

	# Every card lands in exactly one bucket of each row (curses sit outside
	# the type/rarity split) so both breakdowns SUM to the header's card count —
	# a row that silently skips starters or curses reads as a miscount.
	var creatures := 0
	var spells := 0
	var armaments := 0
	var curses := 0
	var rarity_counts := {"starter": 0, "common": 0, "uncommon": 0, "rare": 0}
	for card_id in RunState.deck:
		var cdata = CardDB.get_card_data(card_id)
		if cdata.is_empty():
			continue
		if CardDB.is_curse(card_id):
			curses += 1
			continue
		match String(cdata.get("type", "")):
			"creature": creatures += 1
			"spell": spells += 1
			"armament": armaments += 1
		var r = cdata.get("rarity", "common")
		if rarity_counts.has(r):
			rarity_counts[r] += 1

	var stats_bar := HBoxContainer.new()
	stats_bar.position = Vector2(80, 68)
	stats_bar.size = Vector2(1440, 28)
	stats_bar.add_theme_constant_override("separation", 32)
	overlay.add_child(stats_bar)

	# Card TYPE isn't an identity colour system the way rarity and tribe are, so
	# this pair used to be an ad-hoc web-green and periwinkle sitting beside gilt
	# and ash siblings on the same bar. Bone for creatures, the house spell-blue
	# for spells — the same ink spells already wear on the card face.
	var comp_items = [
		["Creatures: %d" % creatures, Color(0.86, 0.82, 0.72)],
		["Spells: %d" % spells, Color(0.70, 0.86, 1.0)],
	]
	if armaments > 0:
		comp_items.append(["Armaments: %d" % armaments, Color(0.90, 0.68, 0.30)])
	if curses > 0:
		comp_items.append(["Curses: %d" % curses, Color(0.68, 0.56, 0.72)])
	comp_items.append_array([
		["|", Color(0.4, 0.35, 0.3)],
		["Starter: %d" % rarity_counts["starter"], Color(0.62, 0.60, 0.54)],
		["Common: %d" % rarity_counts["common"], Color(0.78, 0.75, 0.68)],
		["Uncommon: %d" % rarity_counts["uncommon"], GameTheme.RARITY_UNCOMMON],
		["Rare: %d" % rarity_counts["rare"], Color(0.95, 0.78, 0.25)],
	])
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
	# Keep the tooltip inside the frame. Site tooltips on the right-hand stops
	# (the keep sits at 0.80·w, and Etna east of it) ran off the right edge and
	# got cut mid-word — the engine's own clamp measures against the real window
	# while this game lays out in a 1600×900 canvas behind a Supersample
	# SubViewport, so the two disagree. Deferred because the panel has no size
	# until it has been laid out once. (Screen audit 2026-07-21.)
	panel.tree_entered.connect(func() -> void:
		_clamp_tooltip_into_view.call_deferred(panel))
	return panel


## Nudge a shown tooltip back inside the viewport. Walks up to the embedded
## popup that owns the panel (Godot parents custom tooltips into one); if the
## tree shape isn't what we expect, this quietly does nothing rather than
## fighting the engine.
func _clamp_tooltip_into_view(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or not panel.is_inside_tree():
		return
	var host: Node = panel.get_parent()
	while host != null and not (host is Window):
		host = host.get_parent()
	if host == null:
		return
	var win := host as Window
	var frame: Vector2i = get_viewport().get_visible_rect().size
	var tip: Vector2i = win.size
	var pos: Vector2i = win.position
	const MARGIN := 8
	pos.x = clampi(pos.x, MARGIN, maxi(MARGIN, frame.x - tip.x - MARGIN))
	pos.y = clampi(pos.y, MARGIN, maxi(MARGIN, frame.y - tip.y - MARGIN))
	if pos != win.position:
		win.position = pos


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
	var _redraw_accum := 0.0
	const REDRAW_STEP := 1.0 / 30.0
	var _march_pts: PackedVector2Array = PackedVector2Array()
	var _march_cum: PackedFloat32Array = PackedFloat32Array()
	var _march_len := 0.0
	var _march_prog := -1.0       # <0 idle · 0..1 marching (stays at 1 after)
	# March dust: puffs dropped under the standard's footfalls, fading as the
	# column moves on. Arrival: a one-shot ground ring when the march lands.
	var _dust: Array = []                 # [{p: Vector2, t0: float}]
	var _dust_last := Vector2.INF
	var _arrive_t := -10.0
	var _arrive_p := Vector2.ZERO
	var _commit_t := -10.0
	var _commit_p := Vector2.ZERO
	var _hover_path: PackedVector2Array = PackedVector2Array()
	var _hover_dest := Vector2.ZERO
	var _hover_label := ""
	var _march_label := ""
	var _hover_t := -10.0
	# Frontier reveal: one-shot light-up of the reachable sites on map open,
	# staggered by distance from the standard. Keyed by node index.
	var _reveal_t := -100.0
	var _reveal_delay: Dictionary = {}

	## Arm the open-of-map flourish: reachable sites flash alight nearest-first,
	## then hand off to the idle breathing rings. No-op under Reduce Motion.
	func play_frontier_reveal(lead_in: float = 0.0) -> void:
		if map == null or (UserSettings != null and UserSettings.reduce_motion):
			return
		var origin: Vector2 = map._player_pos if bool(map._has_player) \
			else (map._camp_pos as Vector2)
		var avail: Array = []
		for i in range(map._nodes.size()):
			var nd = map._nodes[i]
			if bool(nd.avail) and not bool(nd.vis):
				avail.append({"i": i, "d": origin.distance_to(nd.pos)})
		if avail.is_empty():
			return
		avail.sort_custom(func(a, b): return float(a.d) < float(b.d))
		_reveal_delay.clear()
		for k in range(avail.size()):
			_reveal_delay[int(avail[k].i)] = lead_in + float(k) * 0.14
		_reveal_t = _t

	func preview_route(path: PackedVector2Array, dest: Vector2, label: String) -> void:
		if map == null or path.size() < 2:
			clear_route_preview()
			return
		_hover_path = path
		_hover_dest = dest
		_hover_label = label
		_hover_t = _t
		queue_redraw()

	func clear_route_preview() -> void:
		if _hover_path.is_empty() and _hover_label == "":
			return
		_hover_path = PackedVector2Array()
		_hover_dest = Vector2.ZERO
		_hover_label = ""
		_hover_t = -10.0
		queue_redraw()
	# Per-edge arc-length cache for the march glints. _edge_curves is built once at
	# map-gen and is index-stable, so these cumulative-length arrays are constant —
	# built lazily on the first draw and reused, instead of rebuilt every frame.
	var _glint_cum: Array = []            # Array[PackedFloat32Array], parallel to _edges
	var _glint_total: PackedFloat32Array = PackedFloat32Array()
	var _glint_built_for := -1            # edge count the cache was built for

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UserSettings != null and UserSettings.reduce_motion:
			set_process(false)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		# The plate itself is frozen; the live ink animation is deliberately
		# recorded at 30 Hz instead of rebuilding its arcs/puffs every render frame.
		_redraw_accum += delta
		if _redraw_accum >= REDRAW_STEP:
			_redraw_accum = fmod(_redraw_accum, REDRAW_STEP)
			queue_redraw()

	## Walk the standard along a road curve. Awaitable; progress sticks at 1
	## so the banner stays planted at the destination through the scene fade.
	func march_along(path: PackedVector2Array, label: String = "",
			duration := 0.55) -> void:
		_march_pts = path
		_hover_path = PackedVector2Array()
		_hover_label = ""
		_march_label = label
		_march_cum = PackedFloat32Array()
		_march_cum.append(0.0)
		_march_len = 0.0
		for i in range(1, path.size()):
			_march_len += path[i - 1].distance_to(path[i])
			_march_cum.append(_march_len)
		_march_prog = 0.0
		_dust.clear()
		_dust_last = Vector2.INF
		if path.size() > 0:
			_commit_t = _t
			_commit_p = path[0]
		if UserSettings != null and UserSettings.reduce_motion:
			_march_prog = 1.0
			queue_redraw()
			return
		var tw := create_tween()
		tw.tween_property(self, "_march_prog", 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished
		# Arrival beat — the ground ring fires as the fade begins, so the march
		# ENDS somewhere instead of dissolving mid-stride.
		if not (UserSettings != null and UserSettings.reduce_motion):
			_arrive_t = _t
			_arrive_p = _march_pos()

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
		# A committed order stays explicit while the standard moves; hover ink
		# has become an issued road, not vanished feedback.
		if _march_prog >= 0.0 and _march_pts.size() >= 2:
			_draw_committed_route(amber)
		# 0.7 — hovered route preview: the chosen branch brightens before
		# commit, so route-planning feels like reading the chart, not hunting
		# tiny tooltips.
		if _march_prog < 0.0 and _hover_path.size() >= 2:
			_draw_route_preview(amber)
		# 1 — breathing rings on the frontier (quiet during the march).
		if _march_prog < 0.0:
			var pulse := 0.5 + 0.5 * sin(_t * 2.6)
			for ni in range(map._nodes.size()):
				var nd = map._nodes[ni]
				if not bool(nd.avail) or bool(nd.vis):
					continue
				var p: Vector2 = nd.pos
				var is_boss := String(nd.type) == "boss"
				var col := crimson if is_boss else amber
				var rr := (34.0 if is_boss else 24.0) + 3.0 * pulse
				draw_arc(p, rr, 0, TAU, 48,
					Color(col.r, col.g, col.b, 0.10 + 0.24 * pulse), 2.0, true)
				draw_circle(p, rr,
					Color(col.r, col.g, col.b, 0.015 + 0.035 * pulse), true, -1.0, true)
				# Frontier reveal: a one-shot bright ring blooming off the site
				# when the map opens — nearest road first, then the next.
				var rd: float = float(_reveal_delay.get(ni, -1.0))
				if rd >= 0.0 and _reveal_t > -50.0:
					var rk := (_t - _reveal_t - rd) / 0.5
					if rk >= 0.0 and rk < 1.0:
						var rr2 := 10.0 + 42.0 * rk
						draw_arc(p, rr2, 0, TAU, 44,
							Color(col.r, col.g, col.b, 0.55 * (1.0 - rk)), 2.6, true)
						draw_circle(p, 3.6,
							Color(1.0, 0.92, 0.62, 0.55 * (1.0 - rk)), true, -1.0, true)
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
				draw_circle(head, 2.2, Color(1.0, 0.90, 0.60, 0.50 * fade), true, -1.0, true)
		# 2 — ember puffs off Etna's plume, drifting NE on the strait wind.
		var apex: Vector2 = (map._etna_peak as Vector2) + Vector2(0, -42.0)
		for k in range(3):
			var ph := fmod(_t * 0.16 + float(k) / 3.0, 1.0)
			var pp := apex + Vector2(30.0, -38.0) * ph \
				+ Vector2(sin(_t * 0.9 + float(k) * 2.1) * 4.0, 0)
			draw_circle(pp, 3.5 + 9.0 * ph,
				Color(0.75, 0.70, 0.64, (1.0 - ph) * 0.085), true, -1.0, true)
		# 3 — the army standard: walking the road while marching, otherwise
		# planted at the player's latest conquest (or the camp gate).
		var sp: Vector2 = _standard_point()
		var quiet_motion: bool = UserSettings != null and UserSettings.reduce_motion
		# 3.2 — march dust: a puff dropped every few paces, swelling and fading
		# behind the column. The road remembers the army passed.
		if not quiet_motion:
			if _march_prog > 0.0 and _march_prog < 1.0:
				if _dust_last == Vector2.INF or sp.distance_to(_dust_last) >= 13.0:
					_dust.append({"p": sp + Vector2(randf() * 6.0 - 3.0, 3.0), "t0": _t})
					_dust_last = sp
					if _dust.size() > 40:
						_dust.pop_front()
			for d in _dust:
				var age: float = _t - float(d.t0)
				if age > 0.9:
					continue
				var k := age / 0.9
				draw_circle(d.p, 2.6 + 5.5 * k,
					Color(0.72, 0.63, 0.48, 0.16 * (1.0 - k)), true, -1.0, true)
			if _march_prog > 0.0 and _march_prog < 1.0:
				_draw_march_column(amber)
			# 3.3 — arrival ring: one clean ground pulse where the march ends,
			# timed to ride through the scene fade.
			var ak := (_t - _arrive_t) / 0.5
			if ak >= 0.0 and ak < 1.0:
				var ar := 8.0 + 42.0 * ak
				draw_arc(_arrive_p, ar, 0, TAU, 40,
					Color(1.0, 0.86, 0.50, 0.38 * (1.0 - ak)), 2.4, true)
				draw_arc(_arrive_p, ar * 0.62, 0, TAU, 32,
					Color(1.0, 0.92, 0.66, 0.26 * (1.0 - ak)), 1.6, true)
			var ck := (_t - _commit_t) / 0.36
			if ck >= 0.0 and ck < 1.0:
				var cr := 11.0 + 30.0 * ck
				draw_arc(_commit_p, cr, 0, TAU, 36,
					Color(1.0, 0.86, 0.50, 0.30 * (1.0 - ck)), 2.2, true)
				draw_circle(_commit_p, 5.0,
					Color(1.0, 0.82, 0.42, 0.22 * (1.0 - ck)), true, -1.0, true)
		var sway := sin(_t * 2.3)
		if _march_prog >= 0.0 and _march_prog < 1.0:
			sway = sin(_t * 9.0)   # the banner snaps in the wind on the move
		# The lamplight pool — a breathing warm glow under the standard, the
		# one bright focal point on the chart (the "you are the light on this
		# table" read). Stacked discs so the falloff stays soft.
		draw_circle(sp + Vector2(0, 1), 56.0 + 5.0 * sway,
			Color(1.0, 0.80, 0.42, 0.038 + 0.010 * sway), true, -1.0, true)
		draw_circle(sp + Vector2(0, 1), 34.0 + 3.0 * sway,
			Color(1.0, 0.82, 0.46, 0.055), true, -1.0, true)
		draw_circle(sp + Vector2(0, 2), 13.0 + 2.0 * sway,
			Color(amber.r, amber.g, amber.b, 0.07), true, -1.0, true)
		draw_arc(sp, 19.0 + 1.5 * sway, 0, TAU, 40,
			Color(amber.r, amber.g, amber.b, 0.22), 1.4, true)
		draw_circle(sp + Vector2(1, 3), 3.4, Color(0, 0, 0, 0.45), true, -1.0, true)
		draw_line(sp + Vector2(0, 4), sp + Vector2(0, -36),
			Color(0.05, 0.04, 0.03), 2.4, true)
		draw_circle(sp + Vector2(0, -36), 1.8, Color(0.92, 0.78, 0.42), true, -1.0, true)
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
		# The standard accumulates the run instead of resetting visually at every
		# stop. Honors are silhouette; exact counts remain in the War Council.
		for honor_i in range(mini(RunState.generals_broken_run, 5)):
			var hx := 5.0 + float(honor_i) * 4.0
			var hcol := Color(0.66, 0.15, 0.10) if honor_i % 2 == 0 \
				else Color(0.88, 0.61, 0.22)
			draw_colored_polygon(PackedVector2Array([
				sp + Vector2(hx, -21), sp + Vector2(hx + 3.0, -21),
				sp + Vector2(hx + 2.5, -11), sp + Vector2(hx + 1.5, -13),
				sp + Vector2(hx + 0.5, -11)]), hcol)
		if not RunState.fallen.is_empty():
			var cloth_len := minf(15.0 + float(RunState.fallen.size()) * 1.5, 25.0)
			draw_colored_polygon(PackedVector2Array([
				sp + Vector2(1, -21), sp + Vector2(6, -20),
				sp + Vector2(4, -20 + cloth_len), sp + Vector2(1, -17 + cloth_len)]),
				Color(0.045, 0.038, 0.036, 0.96))
		for seal_i in range(clampi(RunState.current_act_idx, 0, 3)):
			var seal_p := sp + Vector2(8.0 + float(seal_i) * 9.0, 2.0)
			draw_circle(seal_p + Vector2(1, 1), 4.2,
				Color(0, 0, 0, 0.28), true, -1.0, true)
			draw_circle(seal_p, 4.2,
				Color(0.52, 0.085, 0.055), true, -1.0, true)
			draw_arc(seal_p, 2.8, 0, TAU, 12,
				Color(0.92, 0.46, 0.22, 0.72), 0.8, true)

	func _draw_route_preview(amber: Color) -> void:
		var age := clampf((_t - _hover_t) / 0.18, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_polyline(_hover_path,
			Color(1.0, 0.86, 0.48, 0.20 + 0.16 * pulse * age),
			13.0, true)
		draw_polyline(_hover_path,
			Color(1.0, 0.92, 0.60, 0.68 * age),
			4.2, true)
		draw_arc(_hover_dest, 32.0 + 4.0 * pulse, 0, TAU, 48,
			Color(1.0, 0.88, 0.50, 0.42 * age), 2.8, true)
		draw_circle(_hover_dest, 6.0,
			Color(amber.r, amber.g, amber.b, 0.24 * age), true, -1.0, true)
		if _hover_label == "" or GameTheme.font_display == null:
			return
		var fsz := 13
		var pad := Vector2(9.0, 5.0)
		var sw := GameTheme.font_display.get_string_size(_hover_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
		# Through the same avoidance as the committed order: the hover label is
		# smaller but it lands in the same place for the same reason, and covering
		# the standard while the player is comparing two legs is worse, not better.
		var plaque := _plaque_rect(_hover_dest, sw.x + pad.x * 2.0, 24.0)
		draw_rect(plaque, Color(0.045, 0.036, 0.026, 0.82 * age), true)
		draw_rect(plaque, Color(1.0, 0.80, 0.36, 0.62 * age), false, 1.2)
		var txt_pos := Vector2(plaque.position.x + pad.x, plaque.position.y + 17.0)
		draw_string_outline(GameTheme.font_display, txt_pos, _hover_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, 3,
			Color(0.02, 0.015, 0.01, 0.88 * age))
		draw_string(GameTheme.font_display, txt_pos, _hover_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
			Color(1.0, 0.90, 0.58, 0.95 * age))


	## The road already carries baked reachability dashes. Commit adds one quiet
	## ruled casing and progressively inks only the part the column has covered,
	## plus a plain-language order at the destination.
	func _draw_committed_route(amber: Color) -> void:
		draw_polyline(_march_pts, Color(0.035, 0.025, 0.016, 0.58), 9.0, true)
		draw_polyline(_march_pts,
			Color(amber.r, amber.g, amber.b, 0.22), 3.4, true)
		var covered := _march_progress_path()
		if covered.size() >= 2:
			draw_polyline(covered, Color(0.03, 0.02, 0.012, 0.82), 7.0, true)
			draw_polyline(covered,
				Color(1.0, 0.88, 0.52, 0.92), 3.8, true)
		var dest: Vector2 = _march_pts[_march_pts.size() - 1]
		# A wax-pin diamond is the non-colour state cue: this is an issued order,
		# not another breathing availability ring.
		draw_colored_polygon(PackedVector2Array([
			dest + Vector2(0, -7), dest + Vector2(7, 0),
			dest + Vector2(0, 7), dest + Vector2(-7, 0)]),
			Color(0.06, 0.04, 0.025, 0.92))
		draw_colored_polygon(PackedVector2Array([
			dest + Vector2(0, -4), dest + Vector2(4, 0),
			dest + Vector2(0, 4), dest + Vector2(-4, 0)]), amber)
		if _march_label != "":
			_draw_operation_plaque(dest, "MARCH TO %s" % _march_label, amber)


	func _march_progress_path() -> PackedVector2Array:
		var out := PackedVector2Array()
		if _march_pts.is_empty():
			return out
		out.append(_march_pts[0])
		if _march_pts.size() < 2 or _march_len <= 0.0:
			return out
		var limit := clampf(_march_prog, 0.0, 1.0) * _march_len
		for i in range(1, _march_pts.size()):
			if _march_cum[i] <= limit:
				out.append(_march_pts[i])
				continue
			var seg := _march_cum[i] - _march_cum[i - 1]
			var local := 0.0 if seg <= 0.0 \
				else (limit - _march_cum[i - 1]) / seg
			out.append(_march_pts[i - 1].lerp(_march_pts[i],
				clampf(local, 0.0, 1.0)))
			break
		return out


	func _march_point_at_distance(distance: float) -> Vector2:
		if _march_pts.is_empty():
			return Vector2.ZERO
		var d := clampf(distance, 0.0, _march_len)
		for i in range(1, _march_pts.size()):
			if d <= _march_cum[i]:
				var seg := _march_cum[i] - _march_cum[i - 1]
				var local := 0.0 if seg <= 0.0 \
					else (d - _march_cum[i - 1]) / seg
				return _march_pts[i - 1].lerp(_march_pts[i], local)
		return _march_pts[_march_pts.size() - 1]


	## Three shield-shaped rank counters trail the standard. Dust says motion;
	## these say an army is moving. They are skipped entirely under Reduce Motion.
	func _draw_march_column(amber: Color) -> void:
		var head_d := clampf(_march_prog, 0.0, 1.0) * _march_len
		for rank_i in range(3):
			var d := head_d - 18.0 - float(rank_i) * 15.0
			if d <= 3.0:
				continue
			var p := _march_point_at_distance(d)
			var behind := _march_point_at_distance(maxf(d - 4.0, 0.0))
			var dir := (p - behind).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			var nrm := dir.orthogonal()
			p += nrm * (3.0 if rank_i % 2 == 0 else -3.0)
			var shield := PackedVector2Array([
				p + dir * 4.2, p + nrm * 3.4,
				p - dir * 3.2 + nrm * 2.2,
				p - dir * 5.0, p - dir * 3.2 - nrm * 2.2,
				p - nrm * 3.4])
			var shadow := PackedVector2Array()
			for q in shield:
				shadow.append(q + Vector2(1.0, 1.2))
			draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.42))
			draw_colored_polygon(shield,
				Color(amber.r, amber.g, amber.b, 0.76))
			var outline := shield.duplicate()
			outline.append(shield[0])
			draw_polyline(outline, Color(0.06, 0.04, 0.025, 0.90), 1.2, true)


	## Where the player's standard is standing right now — the marching position
	## mid-march, the last claimed stop otherwise, the camp gate on a fresh act.
	## Extracted 2026-07-30 because the order plaques have to know: they are drawn
	## at the DESTINATION and the standard is at the ORIGIN, one lane away.
	func _standard_point() -> Vector2:
		if _march_prog >= 0.0:
			return _march_pos()
		if map != null and bool(map._has_player):
			return map._player_pos
		if map != null:
			return (map._camp_pos as Vector2) + Vector2(30, -4)
		return Vector2.ZERO


	## The standard's real footprint: the lamplight pool, the pole running up to
	## sp.y - 36, and the banner cloth hanging to its right. Deliberately a little
	## generous — a plaque grazing the glow still reads as a collision.
	func _standard_keepout() -> Rect2:
		var sp := _standard_point()
		return Rect2(sp.x - 34.0, sp.y - 48.0, 74.0, 64.0)


	## Place a plaque near `dest` without covering the standard.
	##
	## THE BUG THIS FIXES: the plaque sat a fixed 62px above the destination (36
	## below, near the top edge) and was centred on it, up to 250px wide. A leg
	## that climbs or drops one lane puts the origin stop inside that rect — so
	## committing a march regularly stamped "MARCH TO ..." straight over the army
	## standard, hiding the one object on the chart that answers "where am I".
	##
	## Resolution order is deliberate: try the side the layout wants, then the
	## other side, and only then slide sideways. Flipping keeps the plaque tied to
	## its destination; sliding is the last resort because a plaque far from its
	## pin stops reading as that pin's label.
	func _plaque_rect(dest: Vector2, w: float, h: float) -> Rect2:
		var min_x := 36.0
		var max_x: float = float(map.size.x) - w - 36.0
		var px := clampf(dest.x - w * 0.5, min_x, maxf(min_x, max_x))
		# Near the top edge the plaque must hang below or it leaves the sheet.
		var prefer_below: bool = dest.y < float(map.size.y) * 0.30
		var keep := _standard_keepout()
		var candidates: Array[float] = []
		candidates.append(dest.y + 36.0 if prefer_below else dest.y - h - 35.0)
		candidates.append(dest.y - h - 35.0 if prefer_below else dest.y + 36.0)
		for cy in candidates:
			var r := Rect2(px, cy, w, h)
			if not r.intersects(keep):
				return r
		# Both sides blocked (the standard is effectively on top of the pin). Slide
		# the plaque away from the standard along x, still on the preferred side.
		var away: float = keep.position.x + keep.size.x + 12.0 \
			if dest.x >= keep.get_center().x else keep.position.x - w - 12.0
		var slid_y: float = candidates[0]
		return Rect2(clampf(away, min_x, maxf(min_x, max_x)), slid_y, w, h)


	func _draw_operation_plaque(dest: Vector2, text: String, amber: Color) -> void:
		if map == null or GameTheme.font_display == null:
			return
		var fsz := 14
		var sw := GameTheme.font_display.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
		var plaque_w := clampf(sw.x + 38.0, 116.0, 250.0)
		var plaque := _plaque_rect(dest, plaque_w, 27.0)
		draw_rect(plaque, Color(0.035, 0.027, 0.018, 0.94), true)
		draw_rect(plaque, Color(amber.r, amber.g, amber.b, 0.82), false, 1.5)
		var seal_p := plaque.position + Vector2(14.0, plaque.size.y * 0.5)
		draw_circle(seal_p, 6.0, Color(0.08, 0.05, 0.025, 0.96))
		draw_colored_polygon(PackedVector2Array([
			seal_p + Vector2(0, -3.5), seal_p + Vector2(3.5, 0),
			seal_p + Vector2(0, 3.5), seal_p + Vector2(-3.5, 0)]), amber)
		var text_pos := Vector2(plaque.position.x + 27.0,
			plaque.position.y + 19.0)
		draw_string_outline(GameTheme.font_display, text_pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, plaque_w - 32.0, fsz, 3,
			Color(0.0, 0.0, 0.0, 0.92))
		draw_string(GameTheme.font_display, text_pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, plaque_w - 32.0, fsz,
			Color(1.0, 0.91, 0.64, 0.98))
