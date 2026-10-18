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
const CARD_BACK_TEXTURE := preload("res://assets/ui/card_back.png")

const HIT_R := 26.0           # click radius, normal site chip
const BOSS_HIT := 46.0        # click radius, the keep

# Phase 2.5 — the tooltip's route-planning line per ground type. Keywords
# stay Capitalized (COPY_STYLE §4); the phrasing names what the country
# BREEDS, matching the terrain re-deal in RunState.apply_terrain_redeal.
const TERRAIN_TIPS := {
	"woods": "Wooded road — ambush country. Swift and Piercing favor it.",
	"pass": "High pass — hard going. Armored creatures hold passes.",
	"ash": "Ash country — burned ground. Doom and fire walk here.",
	"meadow": "Meadow road — open country, lighter resistance.",
}

# Wayside halts advertise their verb on the chart (same contract as
# mutators/terrain: the stop's KIND is route-planning intel, the inside is
# the surprise). Names + one-line tells, keyed by node.wayside_id.
const WAYSIDE_TIPS := {
	"drill_yard": ["The Drill Yard",
		"Drill a creature: +1/+1, then push your luck for more."],
	"muster_scale": ["The Trading Scales",
		"Make one trade: sell a card for gold, or buy provisions."],
	"standard_bearer": ["The Standard-Bearer",
		"Move one keyword from one of your creatures to another."],
	"supply_cache": ["The Supply Cache",
		"Choose 1 of 3 supplies to carry away."],
}

var _hud_root: Control = null
var _hp_value_label: Label = null
var _potion_use_busy: bool = false
var _overlay: MapPulseOverlay = null
var _marching := false        # commit march in flight — ignore further clicks
var _site_buttons: Array = []  # MapTipButtons re-seated on every zoom/pan
var _help_button: Control = null  # the "?" How-to-Play affordance (top-left)
var _deck_viewer_build_generation := 0
var _opening_ready := false       # final plate/camera settled; map input may begin


func _ready() -> void:
	# The chart is the other doorway into a campaign fight, so it disarms the
	# skirmish launch latch for the same reason the title screen does — see the
	# note there.
	SkirmishState.launch_armed = false
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	if RunState.finale_stage == 1:
		# The run was saved at the throne door (the finale isn't a map node) —
		# a resume lands here, and the only way out is through.
		get_tree().change_scene_to_file(COMBAT_SCENE)
		return
	# This screen deliberately phases its cold terrain build over several calm
	# frames. Tell the shared ink transition not to mistake those yields for a
	# finished screen; the hold is released once the plate and fixed HUD exist.
	GameTheme.hold_scene_reveal(self)
	# THE CHART IS THE SCREEN THE PLAYER RETURNS TO MOST, so it is the one screen
	# that must NOT re-roll (2026-09-14). This used to call play_music_random per
	# act, and because that picker excludes the currently-playing track it was a
	# GUARANTEE of a different song on all ~18 returns an act — the road could
	# never become familiar, and each return paid a crossfade for the privilege.
	# One theme per act, drawn once per run and held. See AudioBank's themes
	# block and docs/MUSIC_SYSTEM_AUDIT_20260914.md §3.
	AudioBank.play_road_theme(RunState.get_act())
	# No atmosphere overlay here: the chart plate carries its own mood, and
	# the menu-style vignette just dims it.
	overlay_handles_standard = true
	GameTheme.fade_in(self, 0.22)
	# RETURN-TO-MAP STATE IS DURABLE BEFORE THE FIRST COSMETIC AWAIT. Room
	# rewards mutate RunState in memory; the map is the checkpoint that commits
	# those mutations and clears the room-resume fields. Keeping this below the
	# cold plate bake/focus glide left a visible half-second window where quitting
	# could replay the completed room or lose its reward.
	_checkpoint_map_return()
	await get_tree().process_frame
	await build_map()
	if not is_inside_tree() or not _map_data_ready:
		if is_inside_tree():
			GameTheme.release_scene_reveal(self)
		return
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
	if not is_inside_tree():
		return
	# THE SITE BUTTONS WENT LIVE AT LINE ~79, i.e. BEFORE that await. On the act's
	# first open the bake runs several frames, and a player who clicks a site in
	# that window commits the march while _ready is still parked. Everything below
	# is "settle onto the chart" work and every line of it is wrong once the army
	# has left: _animate_focus fights the march camera, and — the damaging half —
	# the checkpoint block CLEARS current_node_type / current_encounter_id and then
	# SAVES. visit_node had just written both, so the wipe left Combat booting with
	# an empty encounter id and the save on disk claiming no room was in progress
	# while the site was already struck: quit during that fight and the resume
	# landed back on a spent map with the encounter gone.
	# _marching is only ever set by a commit that unconditionally changes scene, so
	# it is a safe "this open is over" flag. The meta pickers below are all
	# "once per act / until answered" checks and re-offer on the next map open.
	if _marching:
		return
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
	# The chart is now truthful and complete. Lift the ink while the camera makes
	# its one opening glide; site hitboxes remain locked until that glide settles.
	GameTheme.release_scene_reveal(self)
	await _animate_focus(_player_pos if _has_player else _camp_pos, 1.10)
	if not is_inside_tree():
		return
	_set_opening_interactive(true)
	# Frontier reveal: once the focus glide is under way, the roads open —
	# each reachable site lights up in order of distance from the standard,
	# then settles into the idle breathing pulse. "Here are your roads."
	if _overlay != null:
		_overlay.play_frontier_reveal()
	await _resolve_meta_pickers()
	# Picker choices happen after the opening presentation; persist them as a
	# second tiny checkpoint. The room outcome itself was already made durable
	# above, before any build or animation yield.
	RunState.save_run()
	_maybe_coach_the_road()


func _checkpoint_map_return() -> void:
	# Every return to the map captures post-room state (HP, gold, deck changes,
	# relics earned). visit_node still saves these fields on entry, so quitting
	# *during* a room resumes it; reaching this screen clears them immediately.
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	# A Daily attempt begins at the first durable map checkpoint, not while the
	# War Chest is still open. That keeps "marching" records resumable.
	if RunState.is_daily_run:
		MetaState.record_daily_start(RunState.current_hero_id,
			RunState.active_slot, RunState.daily_date)
	RunState.save_run()


## The road's two lessons, taught the first time each one is TRUE rather than
## both on arrival.
##
## "Pick a site" is needed the moment the chart appears. "The keep is shut until
## you have broken enough Holds" is needed the first time the player has broken
## one and can see the count move — teaching it on the empty first map would be
## explaining a number that reads 0 of 2 and means nothing yet. Two panels back
## to back on the same screen is also the fastest way to make someone skip both.
func _maybe_coach_the_road() -> void:
	if _marching:
		return
	# The camera is still gliding in from _animate_focus / play_frontier_reveal
	# (0.55s). Keep the grace period owned by this map: a SceneTreeTimer used
	# to survive a map closed inside the delay and leaked its suspended call.
	var coach_delay := create_tween()
	coach_delay.tween_interval(0.62)
	coach_delay.tween_callback(_show_road_coach)


func _show_road_coach() -> void:
	if not is_inside_tree() or _marching:
		return
	if TutorialCoach.should_teach("map_gate") \
			and not TutorialCoach.should_teach("map_road") \
			and RunState.holds_broken_in_act > 0:
		TutorialCoach.teach(self, "map_gate", _keep_site_targets())
		return
	TutorialCoach.teach(self, "map_road", _open_site_targets())


## The sites the player may actually walk to. A disabled chip is scenery for this
## lesson — lighting the whole chart would say "the map matters", where lighting
## the three live stops says the thing the sentence is about.
func _open_site_targets() -> Array:
	var out: Array = []
	for i in mini(_site_buttons.size(), _nodes.size()):
		var btn: Control = _site_buttons[i]
		if btn == null or not is_instance_valid(btn) or btn.disabled:
			continue
		out.append(btn)
	return out


func _keep_site_targets() -> Array:
	for i in mini(_site_buttons.size(), _nodes.size()):
		if String(_nodes[i].get("type", "")) != "boss":
			continue
		var btn: Control = _site_buttons[i]
		if btn != null and is_instance_valid(btn):
			return [btn]
	return []


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

func _gui_input(event: InputEvent) -> void:
	# Do not let wheel/drag input fight the authored opening camera move.
	if not _opening_ready:
		return
	super(event)


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
		var actionable := bool(nd.avail) and not bool(nd.vis)
		btn.set_meta("map_actionable", actionable)
		# Even actionable sites stay inert while the plate bakes and the opening
		# camera glides. Their final geometry is already reserved, so enabling them
		# later changes no layout and cannot expose a moving hitbox.
		btn.disabled = true
		if not actionable:
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


func _set_opening_interactive(enabled: bool) -> void:
	_opening_ready = enabled
	for btn in _site_buttons:
		if btn == null or not is_instance_valid(btn):
			continue
		btn.disabled = not enabled or not bool(btn.get_meta("map_actionable", false))


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
		return "SPECIAL BATTLE"
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
	var target_pan := size * 0.5 - world * target_zoom
	if DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		_set_view(target_zoom, target_pan)
		return
	var z0 := _view_zoom
	var p0 := _view_pan
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var z: float = lerpf(z0, target_zoom, t)
		_set_view(z, p0.lerp(target_pan, t)),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	if is_inside_tree():
		_set_view(target_zoom, target_pan)


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
A SPECIAL BATTLE" % String(sp.get("name", sp_id))
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
	# THE FIGHT'S STANDING RULE — the single biggest determinant of what a hold
	# actually is, and until now the one thing the chart refused to say. A route
	# could bill unavoidable face damage every round, or hand the foe a free body
	# per round, and the only way to learn that was to commit and find out. The
	# named-action arm above states its whole bargain from the road; an ordinary
	# hold gets the same courtesy.
	#
	# Combat and Generals only. The keep is not a route CHOICE (every road ends
	# there), its tooltip already carries the lord's title and the siege brief,
	# and every boss is phased — one line off the phase-1 entry would be a
	# half-truth posted as the law. Combat.gd's plaque is the honest source
	# there, and it rewrites itself on every phase turn.
	if t in ["combat", "elite"] and String(nd.get("encounter_id", "")) != "":
		# Through `get_passive_for`, not off the authored entry: a lineup borrowed
		# two acts UP fights without its standing rule (this pool borrows across
		# acts — see that function), and a tooltip promising a rule the fight does
		# not have is worse than no line at all. Same target act Combat will use.
		var rule: String = String(EncounterDB.get_passive_for(
			String(nd.encounter_id), RunState.get_act()).get("passive_desc", ""))
		if rule != "":
			# Em dash, not a colon: nearly every passive_desc already opens on its
			# own trigger colon ("Start of each round:", "When an enemy dies:"), and
			# "Their rule: Start of each round: ..." stutters.
			label += "\nTheir rule — %s" % rule
	if t == "recruit":
		label = "Recruit Camp\nChoose 1 of 3 cards for free."
	if t == "shop":
		label = "Trader's Wagon\nBuy cards, relics, and potions, or sell one card."
	if t == "rest":
		label = "Make Camp\nHeal, forge a card, or raise a fallen soldier."
	if t == "event":
		label = "Something on the Road\nAn event with several choices."
	if t == "treasure":
		label = "Relic Cache\nReveal one relic. Take it or choose gold."
	if t == "arsenal":
		label = "Supply Cache\nForge a card, take potions, or take gold."
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
	if _marching or not _opening_ready:
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
	# RESOLVE THE DESTINATION BEFORE COMMITTING. visit_node() marks the site
	# visited, bumps current_floor and SAVES — so a node type with no scene
	# mapping used to consume the stop and load nothing, leaving the player on a
	# spent map with nowhere to go and the loss already on disk. The node dict
	# carries its own type, so the refusal can happen while the move is still
	# undone. Every generated type is mapped today; this keeps a future one from
	# eating a run.
	var target := _scene_for_node_type(String(dest_nd.get("type", "")))
	if target == "":
		push_warning("[MapView] no scene for node type '%s' at (%d, %d) — move refused"
			% [String(dest_nd.get("type", "")), row, col])
		return
	_marching = true
	AudioBank.play_sfx("button_click")
	RunState.visit_node(row, col)
	var ntype: String = RunState.current_node_type
	# RunState is the AUTHORITY on what was just entered; the refusal above read
	# the plate's cached node copy (_nodes, rebuilt per plate bake). Both come off
	# the same act map, so re-resolving costs nothing — and it means routing can
	# never follow a stale cache if they ever drift. An unmapped type here keeps
	# the pre-checked target rather than falling through to nothing.
	var committed := _scene_for_node_type(ntype)
	if committed != "":
		target = committed
	if ntype in ["combat", "elite", "boss"]:
		ScenePreload.begin_warm_encounter_art(RunState.current_encounter_id)
	# The army marches down the carved road to the chosen site, then the
	# scene fades — the commit reads as a move on the campaign map, not a
	# menu click.
	if _overlay != null:
		_overlay.clear_route_preview()
		await _overlay.march_along(road_path_between(from_p, dest),
			_site_label_for_preview(dest_nd))
	if ntype in ["combat", "elite", "boss"]:
		await ScenePreload.wait_for_encounter_art(RunState.current_encounter_id)
	# Bloom the signature ink transition from the site the standard reached.
	# The scene handoff now belongs to the committed place, not a fixed corner.
	var screen_dest: Vector2 = dest * _view_zoom + _view_pan
	var origin_uv := Vector2(0.08, 0.10)
	if size.x > 0.0 and size.y > 0.0:
		origin_uv = Vector2(screen_dest.x / size.x, screen_dest.y / size.y)
	GameTheme.fade_out_then_change_scene(self, target, 0.30, origin_uv)


## The map's node-type → scene table. Kept in ONE place because MainMenu owns a
## TWIN table for resuming a saved run (_continue_run), and the two diverging is
## exactly what the refusal in _march_to_node would turn into a dead stop:
## "reliquary" was routed there and NOT here. Any new node type needs both.
func _scene_for_node_type(ntype: String) -> String:
	match ntype:
		"combat", "elite", "boss": return COMBAT_SCENE
		"shop": return SHOP_SCENE
		"rest": return REST_SCENE
		"event": return EVENT_SCENE
		"treasure", "reliquary", "arsenal": return TREASURE_SCENE
		"recruit": return RECRUIT_SCENE
		"wayside": return WAYSIDE_SCENE
	return ""


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
	_hp_value_label = _place_centred_label(
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
		"YOUR ARMY", _company_tip_text(),
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
		remove_child(_hud_root)
		_hud_root.queue_free()
	_hud_root = null
	_hp_value_label = null
	_build_top_hud()


func _place_potion_slot(pid: String, index: int, top_left: Vector2, sz: float) -> void:
	# Empty slot: a dim round socket — the same hairline bronze the combat
	# belt's empty niches wear — with the ghost bottle seated in it. The bare
	# tinted ghost used to read as three dead stains on the dark HUD band;
	# framed, it reads as an empty belt waiting for bottles. Not clickable.
	if pid == "":
		var socket := Panel.new()
		socket.position = top_left
		socket.size = Vector2(sz, sz)
		socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.045, 0.038, 0.030, 0.85)
		st.border_color = Color(0.30, 0.24, 0.14, 0.60)
		st.set_border_width_all(1)
		st.set_corner_radius_all(int(sz) / 2)
		socket.add_theme_stylebox_override("panel", st)
		_hud_root.add_child(socket)
		_place_painted_icon(GameTheme.tex_hud_potion, top_left, sz,
			Color(0.52, 0.46, 0.38, 0.55))
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var icon: Texture2D = PotionDB.icon_for(pid)
	# White silhouette kit carries identity via the potion colour; painted art
	# (PNG, once it exists) renders untinted.
	var tint: Color = data.get("color", Color.WHITE) if not data.is_empty() else Color.WHITE
	if PotionDB.is_painted_icon(pid):
		tint = Color.WHITE
	# Keep the visible bottle and its hit target in one fixed slot. Consumption
	# can now move that physical object toward HP without rebuilding the HUD first.
	var slot := Control.new()
	slot.name = "MapPotionSlot_%d" % index
	slot.position = top_left
	slot.size = Vector2(sz, sz)
	slot.pivot_offset = slot.size * 0.5
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(slot)
	if icon != null:
		slot.add_child(_make_constrained_tex(icon, Vector2(2, 2), sz,
			Color(0, 0, 0, 0.55)))
		slot.add_child(_make_constrained_tex(icon, Vector2.ZERO, sz, tint))
	# Invisible button overlay handles clicks + tooltip inside the same slot.
	var btn := MapTipButton.new()
	btn.view = self
	btn.flat = true
	btn.position = Vector2.ZERO
	btn.size = Vector2(sz, sz)
	var usable_in: String = data.get("usable_in", "combat")
	var map_usable: bool = usable_in == "map" or usable_in == "both"
	var label: String = "%s\n%s" % [data.get("name", pid), data.get("desc", "")]
	if not map_usable:
		label += "\nUsable in combat only"
	btn.tooltip_text = label
	if map_usable:
		btn.pressed.connect(_use_map_potion.bind(index, slot))
	slot.add_child(btn)


func _use_map_potion(index: int, source: Control = null) -> void:
	if _potion_use_busy:
		return
	var pid: String = RunState.potions[index] if index < RunState.potions.size() else ""
	if pid == "":
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect: String = data.get("effect", "")
	if effect != "heal_hp":
		# Combat-only effects shouldn't even be wired up here, but be safe.
		return
	_potion_use_busy = true
	var old_hp: int = RunState.hero_hp
	var hp_destination := Vector2(190.0, 38.0)
	if _hp_value_label != null and is_instance_valid(_hp_value_label):
		hp_destination = _hp_value_label.get_global_rect().get_center()
	match effect:
		"heal_hp":
			RunState.consume_potion(index)
			RunState.heal_hero(8)
	var animate := source != null and is_instance_valid(source) \
		and DisplayServer.get_name() != "headless" \
		and not (UserSettings != null and UserSettings.reduce_motion)
	if animate:
		GameTheme.claim_pop(source)
		if AudioBank != null:
			AudioBank.play_sfx("potion_use")
		await get_tree().create_timer(0.10).timeout
		if not is_inside_tree() or not is_instance_valid(source):
			return
		await GameTheme.pocket_away(source, hp_destination, 0.28)
		if not is_inside_tree():
			return
		Motion.ring(self, hp_destination, Color(0.38, 0.88, 0.48, 0.68))
		var healed := RunState.hero_hp - old_hp
		if healed > 0:
			GameTheme.spawn_floating_text(self, hp_destination + Vector2(0, 18),
				"+%d HP" % healed, Color(0.42, 0.95, 0.52), false)
	_refresh_hud()
	if _hp_value_label != null and is_instance_valid(_hp_value_label):
		GameTheme.pulse_label(_hp_value_label, Color(0.42, 0.95, 0.52))
	_potion_use_busy = false


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
		font_size: int = 22) -> Label:
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
	return lbl


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
			if nm == "DeckOverlay":
				_close_deck_viewer(ov)
			else:
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
		return "Road: hover each hold to read what waits there before you commit."
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
			return "Doctrine waiting: %s chooses a keyword next fight." \
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
		return "No creature has kills yet. Three kills earns a name."
	return "No creatures in your deck yet."


## The Company button's hover read: who you are, what you raised, and what the
## banner is buying you — the whole muster declaration without a click. The
## ledger behind the button carries the same three facts plus the rolls; this
## is the zero-click half, because a fact you must open a panel to find is a
## fact most players never find.
func _company_tip_text() -> String:
	var lines: Array[String] = ["Your Army"]
	var arms_txt := _arms_sentence()
	if arms_txt != "":
		lines.append(arms_txt + ".")
	var season_txt: String = RunState.season_line()
	if season_txt != "":
		lines.append(season_txt)
	lines.append("Shows veterans, the fallen, and keep progress.")
	return "\n".join(lines)


## The run's arms in the PROSE register: "Pyromancer of the Lanternhall".
## MapTerrain's `_own_arms` supplies the facts; the caps cartouche and this
## sentence are the two registers that dress them. "" when there is no live run
## identity. (The ", under the Contract" clause went with the banner system,
## 2026-09-16.)
func _arms_sentence() -> String:
	var arms: Dictionary = _own_arms()
	if arms.is_empty():
		return ""
	var out := String(arms.lord)
	if String(arms.realm) != "":
		out += " of %s" % _lower_article(String(arms.realm))
	return out


## "The Lanternhall" → "the Lanternhall". Kingdom names carry their
## article, and folded mid-sentence a capital "The" reads as a typo. The name
## itself is untouched everywhere it stands alone (the caps cartouche, the
## muster screens, GameOver).
func _lower_article(name: String) -> String:
	if name.begins_with("The "):
		return "the " + name.substr(4)
	return name


func _show_company_ledger() -> void:
	var shell := _make_map_overlay("CompanyLedgerOverlay", "YOUR ARMY",
		GameTheme.GILT_BRIGHT)
	var overlay: Control = shell.overlay
	var root: VBoxContainer = shell.root

	# THE ARMS, then what the season is DOING. Run setup asks for a lord and the
	# run then never mentioned him again. The company ledger is the army's own
	# book, so it is where the army's own identity belongs. season_line() is
	# REUSED rather than re-written: one sentence, so the promise made at setup
	# and the promise kept on the road can never drift apart.
	var arms_txt := _arms_sentence()
	if arms_txt != "":
		_overlay_label(root, arms_txt, 22, GameTheme.GILT_BRIGHT)
	var season_txt: String = RunState.season_line()
	if season_txt != "":
		# Warm bone, not sage (2026-08-05). The season line renders in three
		# places — the muster, Recruit, and here — and all three carried the same
		# `g >= r` cold ink. The muster's was warmed on 2026-08-03; these two
		# were missed because the fix was made per-screen rather than per-LINE.
		# The line above it (the kingdom) was already 0.86/0.82/0.70, so on the
		# chart the pair read as two unrelated captions.
		_overlay_label(root, season_txt, 18, Color(0.88, 0.83, 0.68))

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

	# "THE ROLL OF THE FALLEN" — a settled proper noun, and the leading article is
	# part of it. `GameOver.gd` and `Rest.gd` both print it in full; this was the
	# one site that dropped the "THE", which is a one-term-per-concept break
	# (COPY_STYLE §12) on a name the player meets on three separate screens.
	var fhead := GameTheme.make_label("THE ROLL OF THE FALLEN", 22, GameTheme.GILT_BRIGHT)
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

## THE COMMAND CURVE AND THE TRIBE TALLY — the two things the deck viewer showed
## you nothing about.
##
## WHY A CURVE MATTERS MORE HERE THAN IN THE GENRE GENERALLY: Command is FIXED.
## Three a turn, at most two banked, moved only by relics, and there are no
## mana-manipulation cards by design — so you cannot ramp out of a top-heavy
## deck the way you can where energy escalates. The curve is a hard constraint,
## and until now the player was asked to hold it in their head.
##
## WHY TRIBES: six tribes each have a payoff keystone (warden_line, beast_encore,
## reap_on_ally_death, coven_spell, bastion_ramp, defection). "How many Soldiers
## am I actually running" decides whether a keystone rare is a bomb or a blank.
##
## IT COUNTS THE UPGRADED COST, NOT THE PRINTED ONE. The card grid below is built
## from `get_upgraded_card_data(i)` and a Forge can move a card's cost — counting
## `CardDB.get_card_data()` instead would put a histogram two inches above a row
## of cards that disagree with it. (The type/rarity bar above still reads base
## data; that is pre-existing and harmless, since neither of those is forgeable.)
##
## IT SHOWS, IT DOES NOT ADVISE. No "your curve is too high", no good/bad colour
## coding — the house rule is that a tutorial (or a readout) which teaches
## strategy fails. Numbers and bar heights; the reading is the player's.
func _add_deck_curve_row(overlay: Control) -> void:
	var cost_counts := [0, 0, 0, 0, 0, 0]     # 0,1,2,3,4,5+
	var tribe_counts := {}
	var counted := 0
	for i in range(RunState.deck.size()):
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		if data.is_empty() or CardDB.is_curse(String(data.get("id", ""))):
			continue        # a curse has no meaningful cost or tribe
		counted += 1
		cost_counts[clampi(int(data.get("cost", 0)), 0, 5)] += 1
		var tribe := String(data.get("ctype", ""))
		if tribe != "":     # tokens and spells carry none; no phantom 7th tribe
			tribe_counts[tribe] = int(tribe_counts.get(tribe, 0)) + 1

	var band := Control.new()
	band.position = Vector2(80, 100)
	band.size = Vector2(1440, 68)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(band)

	var head := GameTheme.make_label("COMMAND COST", 15, Color(0.72, 0.66, 0.54))
	head.position = Vector2(0, 26)
	head.size = Vector2(130, 20)
	band.add_child(head)

	# Bars are proportional to the FULLEST bucket, so the shape reads even on a
	# ten-card opener. A zero bucket still draws its label and an empty column,
	# because a gap in the curve is information.
	var tallest := 1
	for n in cost_counts:
		tallest = maxi(tallest, int(n))
	for c in range(cost_counts.size()):
		var n: int = cost_counts[c]
		var col := Control.new()
		col.position = Vector2(140 + c * 52, 0)
		col.size = Vector2(46, 68)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(col)

		var count_lbl := GameTheme.make_label(str(n), 15,
			Color(0.92, 0.88, 0.78) if n > 0 else Color(0.46, 0.42, 0.38))
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_lbl.position = Vector2(0, 0)
		count_lbl.size = Vector2(46, 16)
		col.add_child(count_lbl)

		# 34px of travel, not 26. At the smaller height the TALLEST bucket of a
		# 35-card deck still drew a ~26px stub, so the row read as a line of
		# dashes rather than as a curve — shot-caught. The band's own height is
		# unchanged; the room came out of the two caption rows.
		var h: float = 1.0 + 34.0 * (float(n) / float(tallest))
		var bar := ColorRect.new()
		bar.color = Color(0.95, 0.78, 0.34, 0.92 if n > 0 else 0.22)
		bar.position = Vector2(7, 17 + (35.0 - h))
		bar.size = Vector2(32, h)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(bar)

		var cost_lbl := GameTheme.make_label(
			"5+" if c == 5 else str(c), 15, Color(0.72, 0.66, 0.54))
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.position = Vector2(0, 52)
		cost_lbl.size = Vector2(46, 16)
		col.add_child(cost_lbl)

	if tribe_counts.is_empty():
		return
	# Biggest tribe first — the answer to "what am I actually building" should be
	# the first thing read, not an alphabetical hunt.
	var tribes: Array = tribe_counts.keys()
	tribes.sort_custom(func(a, b):
		return int(tribe_counts[a]) > int(tribe_counts[b]))
	var tribe_row := HBoxContainer.new()
	tribe_row.position = Vector2(500, 26)
	tribe_row.size = Vector2(940, 20)
	tribe_row.add_theme_constant_override("separation", 22)
	band.add_child(tribe_row)
	tribe_row.add_child(GameTheme.make_label(
		"TRIBES", 15, Color(0.72, 0.66, 0.54)))
	for tribe in tribes:
		var name_txt := String(tribe).capitalize()
		var chip := GameTheme.make_label(
			"%s: %d" % [name_txt, int(tribe_counts[tribe])], 15,
			Color(0.88, 0.84, 0.74))
		chip.add_theme_constant_override("outline_size", 3)
		chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		tribe_row.add_child(chip)


func _close_deck_viewer(overlay: Control) -> void:
	_deck_viewer_build_generation += 1
	if is_instance_valid(overlay):
		overlay.queue_free()


func _show_deck_viewer() -> void:
	_deck_viewer_build_generation += 1
	var build_generation := _deck_viewer_build_generation
	var overlay := ColorRect.new()
	overlay.name = "DeckOverlay"
	overlay.color = Color(0.03, 0.02, 0.05, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var overlay_ref: WeakRef = weakref(overlay)
	var viewer_alive := func() -> bool:
		var live_overlay = overlay_ref.get_ref()
		return is_inside_tree() and build_generation == _deck_viewer_build_generation \
			and live_overlay != null and is_instance_valid(live_overlay) \
			and not live_overlay.is_queued_for_deletion()

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

	_add_deck_curve_row(overlay)

	var scroll := ScrollContainer.new()
	# 175, not 100: the curve/tribe band above takes the intervening 68px. The
	# bottom edge is unchanged at 790, so the grid still clears the canvas.
	scroll.position = Vector2(80, 175)
	scroll.size = Vector2(1440, 615)
	overlay.add_child(scroll)

	var grid := GridContainer.new()
	grid.set_meta("coordinated_card_group", true)
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
	# Reserve the complete final grid before the first await. A late texture or
	# rich-text pass now fills an existing slot instead of changing the container.
	var entries: Array = []
	var card_datas: Array = []
	for i in range(RunState.deck.size()):
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		card_datas.append(data)
		var wrapper := Control.new()
		wrapper.name = "DeckCardSlot"
		wrapper.custom_minimum_size = Vector2(225, 300)
		wrapper.set_meta("coordinated_card_slot", true)
		grid.add_child(wrapper)
		var back := TextureRect.new()
		back.name = "LoadingBack"
		back.texture = CARD_BACK_TEXTURE
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Motion.arm_loading_writ(back, grid)
		wrapper.add_child(back)
		entries.append({"wrapper": wrapper, "back": back})

	# CLOSE is live immediately, even while a cold cache is warming.
	var close_btn = GameTheme.make_back_button("CLOSE", Vector2(140, 40))
	close_btn.name = "DeckCloseButton"
	close_btn.position = Vector2(740, 800)
	close_btn.pressed.connect(_close_deck_viewer.bind(overlay))
	overlay.add_child(close_btn)

	# One batched cache job keeps the old performance win; ornate faces are then
	# built incrementally but stay hidden behind the already-settled backs.
	await CardTextureCache.bake_many(card_datas, viewer_alive)
	if not viewer_alive.call():
		return
	for i in range(entries.size()):
		var data: Dictionary = card_datas[i]
		var wrapper: Control = entries[i].wrapper
		var card = CARD_SCENE.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = data.get("id", "")
		card.is_on_battlefield = true
		card.static_display = true
		card.live_baked_mode = true
		card.defer_baked_rules_text = DisplayServer.get_name() != "headless"
		card.visible = false
		wrapper.add_child(card)
		wrapper.move_child(card, 0)
		entries[i]["card"] = card
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		elif i % 2 == 1 or i == entries.size() - 1:
			await RenderingServer.frame_post_draw
			if not viewer_alive.call():
				return
			for completed_i in range(maxi(0, i - 1), i + 1):
				var completed_card: Control = entries[completed_i].get("card", null)
				if is_instance_valid(completed_card):
					completed_card.complete_deferred_baked_rules()
	if not viewer_alive.call():
		return
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not snap:
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for entry in entries:
			Motion.flip_out(entry.back as Control, 0.13)
		await get_tree().create_timer(Motion.time(0.13)).timeout
		if not viewer_alive.call():
			return
	for entry in entries:
		var card: Control = entry.card
		var back: Control = entry.back
		if snap and is_instance_valid(back):
			back.queue_free()
		card.visible = true
		if not snap:
			Motion.flip_in(card, 0.0, 0.17)


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
	# Detach before the deferred free. The replacement carries the SAME fixed
	# name, and queue_free() leaves the outgoing overlay in the tree until the
	# end of the frame — so add_child renames the incoming one and this lookup
	# misses it from then on, stacking a scrim per press. Same defect as
	# MainMenu._rebuild_menu's; see the note there.
	var existing := get_node_or_null("HowToPlayOverlay")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
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
			# 420, not 300: at 18px the old measure wrapped around 35 characters,
			# under COPY_STYLE §11's 50-80 band, and the tooltip now carries the
			# fight's standing rule as well as the mutator/terrain/pursuit lines —
			# a ~130-character rule became a five-line column. Only long bodies
			# ever reach this branch, so short tips keep their tight box.
			body.custom_minimum_size = Vector2(420, 0)
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
	# column moves on.
	var _dust: Array = []                 # [{p: Vector2, t0: float}]
	var _dust_last := Vector2.INF
	var _hover_path: PackedVector2Array = PackedVector2Array()
	var _hover_dest := Vector2.ZERO
	var _hover_label := ""
	var _march_label := ""
	var _hover_t := -10.0
	# The commit / arrival / frontier-reveal marks used to live here as timestamp
	# + position pairs replayed by `_draw` on every frame for as long as they
	# lasted. They are fired one-shots now (`Motion.ring`), so the state they
	# needed is gone with them.

	# ── THE INK LAYER (2026-09-10) ───────────────────────────────────────
	# Everything else here draws in IMMEDIATE MODE, which is right for the chart's
	# engraved furniture — plaques, the standard, rank shields, wax pins are flat
	# marks a printer would have struck, and flat is what they should be. It is
	# wrong for the ROAD, for the reason the lightning rebuild established one
	# screen over: a `draw_polyline` has UNIFORM OPACITY ACROSS ITS WIDTH, so it is
	# a hard band with no soft edge and no internal structure whatever colour it is
	# given. The committed march was FOUR of them stacked (9px dark, 3.4 amber, 7px
	# dark, 3.8 bright) — precisely the layering that did NOT fix the bolt: piling
	# hard bands makes a thicker hard band with a dimmer hard band behind it.
	#
	# The road is drawn with `Motion.beam_line`'s "ink" profile instead — textured
	# cross-section, dense body, feathered edges. Those are Line2D NODES, which is
	# why they need a host carrying the plate transform: immediate-mode drawing
	# gets `draw_set_transform`, nodes do not.
	#
	# `_fx` sits at z -1 so the ink lands UNDER the overlay's own furniture (the
	# standard walks ON the road rather than beside it) while still clearing the
	# baked plate, which is a whole node up.
	var _fx: Node2D = null
	# slot -> Line2D. Slots: "plan" (the ruled road, not yet travelled) · "dry"
	# (laid and set) · "wet" (still glossy behind the nib) · "rule" (the hovered
	# branch — dry-point, not ink). Kept in a dictionary rather than four typed
	# fields so `_ink_stroke` can own the whole build/update/hide cycle for all of
	# them; a per-field version needs an out-parameter GDScript does not have.
	var _ink_nodes: Dictionary = {}
	# How far behind the pen the ink is still wet, in plate px. This is the whole
	# "setting" read — see `_draw_committed_route`.
	const INK_WET_RUN := 118.0
	# Arc-lengths where the pen rested between strokes, so the blots it left can
	# be drawn once the stroke has actually reached them.
	var _ink_rests: PackedFloat32Array = PackedFloat32Array()
	# The pigment that pooled down the middle of a stroke. Passed as the beam
	# kit's `core` because its DEFAULT IS WHITE and the chart is cream: a
	# white-hot core is the right answer on the combat table and a hole in the
	# page here. See `Motion.beam_material`.
	const INK_CORE := Color(0.11, 0.075, 0.045)

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
		# FIRED ONCE, NOT REDRAWN. These used to be `draw_arc` circles recomputed
		# on every frame of the 30 Hz redraw, keyed off a per-site delay table the
		# draw loop had to consult for all ~7 sites forever after. `Motion.ring`
		# takes the stagger as a `delay` opt, so the whole reveal is scheduled in
		# one pass here and the draw loop stops knowing about it at all.
		#
		# And they are the ERODED ring rather than a clean arc for the reason the
		# ring engine exists: an analytic band is *clean*, and clean is what reads
		# as CG in a hand-painted game. This is a FIRED beat — a road opening — so
		# it gets the hot front too. The breathing availability rings below stay
		# flat arcs deliberately; see the note there.
		for k in range(avail.size()):
			var nd2 = map._nodes[int(avail[k].i)]
			var col: Color = (map.CRIMSON if String(nd2.type) == "boss" \
				else map.PLAYER_AMBER)
			Motion.ring(_fx, nd2.pos, Color(col.r, col.g, col.b, 0.62), {
				"radius": 32.0, "width": 2.8, "duration": 0.5,
				"start_scale": 0.31, "end_scale": 1.62, "width_end": 1.3,
				"delay": lead_in + float(k) * 0.14, "fade_in": 0.07,
			})

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
		_fx = Node2D.new()
		_fx.name = "PlateFX"
		# `show_behind_parent`, NOT `z_index = -1`. That was the first cut and it
		# put the whole ink layer UNDERNEATH THE MAP: the baked plate is a sibling
		# canvas item at z 0 and it is OPAQUE, so anything at z -1 sorts below it
		# and is never seen. The shot showed a road with no ink on it and nothing
		# in the log, because nothing was wrong — it was drawing perfectly, one
		# layer too deep.
		#
		# This flag draws the child before the parent's own `_draw` while keeping
		# it in the parent's z band, which is exactly the slot wanted: above the
		# plate, below the overlay's furniture. The standard then walks ON the
		# road instead of being painted over by it.
		_fx.show_behind_parent = true
		add_child(_fx)
		if UserSettings != null and UserSettings.reduce_motion:
			set_process(false)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		# THE FX HOST TRACKS THE VIEW EVERY FRAME, not at the 30 Hz redraw rate
		# below. Immediate-mode geometry is re-emitted inside `draw_set_transform`
		# whenever `_draw` runs, so it cannot lag; a NODE keeps whatever transform
		# it was last given. Syncing these at 30 Hz while the player drags the
		# chart at 60 leaves the road sliding a frame behind the sites it joins.
		_sync_fx_transform()
		# The plate itself is frozen; the live ink animation is deliberately
		# recorded at 30 Hz instead of rebuilding its arcs/puffs every render frame.
		_redraw_accum += delta
		if _redraw_accum >= REDRAW_STEP:
			_redraw_accum = fmod(_redraw_accum, REDRAW_STEP)
			queue_redraw()

	## Put the node-side FX host into plate coordinates — the same space the
	## immediate-mode block enters via `draw_set_transform` at the top of `_draw`.
	## Called from `_process` AND from `_draw`, because Reduce Motion turns
	## `_process` off entirely and the ink still has to sit on its road there.
	func _sync_fx_transform() -> void:
		if _fx == null or map == null:
			return
		_fx.position = map._view_pan
		var z: float = map._view_zoom
		_fx.scale = Vector2(z, z)

	## Walk the standard along a road curve. Awaitable; progress sticks at 1
	## so the banner stays planted at the destination through the scene fade.
	func march_along(path: PackedVector2Array, label: String = "",
			duration := 0.55) -> void:
		# THE PEN DOES NOT TRACE THE RULED ROAD (2026-09-10, second pass).
		#
		# Everything about the ink was right except the LINE ITSELF, which was a
		# machine-perfect copy of the road's own curve — and that is why it still
		# read as a highlight rather than as something a hand did. It is the
		# lightning's very first decision, missed: a bolt is not a path with a
		# nice profile, it is a path that is IRREGULAR AT SEVERAL SCALES, and the
		# irregularity is most of what makes it look real.
		#
		# So the same generator, `_hand_path` — but this is not the bolt's
		# `_lightning_path` copied over, and the difference is the whole craft of
		# it. Lightning is ANGULAR at five octaves: it wants corners, because a
		# discharge takes the crooked route. A pen has no corners at all. A hand
		# deviates in TWO registers — the arm's slow sweep and the fingers' fine
		# tremor — so this displaces at three levels and then SMOOTHS, which kills
		# every corner while keeping the deviation. Same maths, opposite surface.
		_march_pts = _hand_path(path, path[0].distance_to(path[path.size() - 1]))
		_hover_path = PackedVector2Array()
		_hover_label = ""
		_march_label = label
		_march_cum = PackedFloat32Array()
		_march_cum.append(0.0)
		_march_len = 0.0
		for i in range(1, _march_pts.size()):
			_march_len += _march_pts[i - 1].distance_to(_march_pts[i])
			_march_cum.append(_march_len)
		_march_prog = 0.0
		_dust.clear()
		_dust_last = Vector2.INF
		var quiet: bool = UserSettings != null and UserSettings.reduce_motion
		if path.size() > 0 and not quiet:
			# THE PEN GOES DOWN. Fired once at the origin rather than redrawn from
			# a timestamp on every frame of the redraw loop.
			#
			# GATED ON REDUCE MOTION AT THE CALL SITE. `Motion.ring` self-gates on
			# headless and on a dead host, but NOT on the setting — the ring is
			# decorative under the animation contract and the branch belongs to
			# whoever fires it. Its two siblings below already sat inside that
			# check; this one was written above it and would have fired anyway.
			Motion.ring(_fx, path[0], Color(1.0, 0.86, 0.50, 0.52), {
				"radius": 26.0, "width": 2.6, "duration": 0.36,
				"start_scale": 0.42, "end_scale": 1.58, "width_end": 1.2,
			})
			# SPATTER. A nib struck onto paper throws ink, and this is the one
			# moment on the chart that is allowed to be violent. It is also the
			# SNAP the whole pass was missing: everything else here eases, and a
			# march that begins by easing has no instant you can point at and call
			# the start. Specks, not a puff — the "ink" silhouette is blotted and
			# lopsided, which is what a thrown droplet looks like when it lands.
			Motion.burst(_fx, path[0], "base", {
				"texture": "ink", "z_index": 3,
				"explosiveness": 1.0, "amount": 11, "lifetime": 0.42,
				"direction": Vector2(0, 0), "spread": 180.0,
				"gravity": Vector2(0, 90.0),
				"velocity_min": 26.0, "velocity_max": 96.0,
				"scale_min": 0.9, "scale_max": 2.4,
				"color": Color(0.16, 0.10, 0.055, 0.85),
			})
		if quiet:
			_march_prog = 1.0
			queue_redraw()
			return
		# THE PEN WRITES IN STROKES, NOT ONE GLIDE.
		#
		# This was a single SINE ease across the whole leg, and it is the last
		# place the pass was still just interpolating. The bolt's biggest single
		# decision is that it is THREE DISCHARGES separated far enough in time for
		# the eye to resolve them — one continuous thing, however well drawn, reads
		# as a machine doing a thing rather than a hand doing it.
		#
		# Translated honestly to writing rather than copied: a hand does not cross
		# a page at constant acceleration, it lays a stroke, checks, and lays the
		# next. Three strokes, each with its OWN accelerate-and-settle, separated
		# by a rest you can just perceive. Total duration is unchanged, so nothing
		# downstream (the scene fade, the encounter-art await) shifts.
		_ink_rests = PackedFloat32Array()
		var cuts: Array[float] = [0.38, 0.71, 1.0]
		var rest: float = 0.042
		var stroke_time: float = maxf(duration - rest * 2.0, 0.12) / 3.0
		var tw := create_tween()
		for si in cuts.size():
			if si > 0:
				# The rest between strokes. Ink POOLS where a nib pauses, so the
				# hesitation leaves a mark rather than just a gap in the timing —
				# that blot is the visible half of a beat that would otherwise
				# only be felt.
				_ink_rests.append(cuts[si - 1] * _march_len)
				tw.tween_interval(rest)
			tw.tween_property(self, "_march_prog", cuts[si], stroke_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished
		# THE PEN LIFTS. The bolt's last lesson: an effect that arrives with no
		# mark where it LANDS reads as having passed through rather than hit —
		# which is why the discharge got a strike-point bloom. A march is the same
		# claim about a different verb, so the road ENDS somewhere instead of
		# dissolving mid-stride into the scene fade.
		#
		# Two rings, fast over slow. Not redundancy: with a gradient core that
		# pairing is a TIMING device — the thin one is the contact, the heavy one
		# is the weight arriving behind it.
		if not quiet:
			var ap := _march_pos()
			Motion.ring(_fx, ap, Color(1.0, 0.92, 0.66, 0.46), {
				"radius": 20.0, "width": 1.8, "duration": 0.30,
				"start_scale": 0.30, "end_scale": 1.55, "width_end": 0.9,
			})
			Motion.ring(_fx, ap, Color(1.0, 0.86, 0.50, 0.60), {
				"radius": 31.0, "width": 3.2, "duration": 0.52,
				"start_scale": 0.26, "end_scale": 1.62, "width_end": 1.4,
			})
			# THE FLICK. A pen leaving the page throws forward, not outward — so
			# unlike the spatter at pen-down this one is aimed down the direction
			# of travel, in a narrow cone. Fewer specks and faster: the hand is
			# lifting away, not bearing down.
			var back := _march_point_at_distance(maxf(_march_len - 14.0, 0.0))
			var dir: Vector2 = (ap - back).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			Motion.burst(_fx, ap, "base", {
				"texture": "ink", "z_index": 3,
				"explosiveness": 1.0, "amount": 7, "lifetime": 0.34,
				"direction": dir, "spread": 26.0,
				"gravity": Vector2(0, 130.0),
				"velocity_min": 70.0, "velocity_max": 165.0,
				"scale_min": 0.7, "scale_max": 1.8,
				"color": Color(0.16, 0.10, 0.055, 0.78),
			})

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
		# The node-side ink rides the same view. Synced here as well as in
		# `_process` so it is still correct under Reduce Motion, which turns
		# `_process` off but leaves the chart pannable.
		_sync_fx_transform()
		var amber: Color = map.PLAYER_AMBER
		var crimson: Color = map.CRIMSON
		# A committed order stays explicit while the standard moves; hover ink
		# has become an issued road, not vanished feedback.
		var marching: bool = _march_prog >= 0.0 and _march_pts.size() >= 2
		if marching:
			_draw_committed_route(amber)
		else:
			# Hidden, not freed — see `_ink_stroke`.
			_ink_stroke("plan", PackedVector2Array(), amber, 1.0, 0.0, "")
			_ink_stroke("dry", PackedVector2Array(), amber, 1.0, 0.0, "")
			_ink_stroke("wet", PackedVector2Array(), amber, 1.0, 0.0, "")
			_ink_stroke("gloss", PackedVector2Array(), amber, 1.0, 0.0, "")
		# 0.7 — hovered route preview: the chosen branch brightens before
		# commit, so route-planning feels like reading the chart, not hunting
		# tiny tooltips.
		if _march_prog < 0.0 and _hover_path.size() >= 2:
			_draw_route_preview(amber)
		else:
			_ink_stroke("rule", PackedVector2Array(), amber, 1.0, 0.0, "")
		# 1 — breathing rings on the frontier (quiet during the march).
		#
		# THESE STAY FLAT ARCS, and that is a decision rather than an omission.
		# The reveal, commit and arrival marks above/below became real eroded
		# rings because they are FIRED beats — energy, transient, punctuation, and
		# a clean analytic band is what makes those read as CG. An availability
		# ring is not a beat: it is a UI TELEGRAPH that stands there permanently
		# saying "you may go here", and the ring engine's own note already settles
		# this case — a standing mark gets grit 0 and almost no hot core, at which
		# point it IS a crisp arc and paying a shader quad per site for one is
		# ~7 nodes rebuilt for no visible change. Same reasoning that leaves the
		# combat forecast cross and chevrons flat.
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
		# 1.5 — march glints: a runner sliding camp-side → door along each open
		# leg. Direction without shouting — the baked amber dashes carry the
		# state; this just says "that way". Quiet during the march.
		if _march_prog < 0.0:
			_draw_glints()
		# 2 — Etna's plume, drifting NE on the strait wind.
		_draw_etna_plume()
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
			# 3.3 — the arrival and commit marks are FIRED at their moments now
			# (see `march_along`), not replayed from a timestamp every frame.
		var sway := sin(_t * 2.3)
		if _march_prog >= 0.0 and _march_prog < 1.0:
			sway = sin(_t * 9.0)   # the banner snaps in the wind on the move
		# The lamplight pool — a breathing warm glow under the standard, the
		# one bright focal point on the chart (the "you are the light on this
		# table" read).
		#
		# ONE TEXTURED POOL, NOT THREE STACKED DISCS (2026-09-10). The old comment
		# said "stacked discs so the falloff stays soft", and that is a hand-rolled
		# gradient: three hard-edged circles at 0.038 / 0.055 / 0.07 leave two
		# visible steps in the falloff, on the single brightest thing on the
		# chart. Same rule as everywhere else in this pass — a flat primitive has
		# uniform opacity, so the falloff has to be PAINTED. `particle_tex` paints
		# it, and one draw then replaces the stack.
		#
		# AND IT FLICKERS ON ITS OWN CLOCK. `sway` is the WIND, which is right for
		# the banner above and wrong for a flame — a lamp does not breathe on a
		# clean sine, it gutters. Three harmonics at incommensurate rates never
		# repeat, which is what separates a guttering light from a pulsing UI
		# element. Matching the aliveness to the matter is the whole lesson of the
		# spell-family pass; here it costs one extra line.
		var flick: float = 0.60 * sin(_t * 2.3) + 0.27 * sin(_t * 5.7 + 1.3) \
			+ 0.13 * sin(_t * 11.9 + 2.9)
		var lamp := Motion.particle_tex("fleck")
		var lr: float = 64.0 + 5.0 * flick
		draw_texture_rect(lamp,
			Rect2(sp + Vector2(0, 1) - Vector2(lr, lr * 0.84),
				Vector2(lr * 2.0, lr * 2.0 * 0.84)),
			false, Color(1.0, 0.80, 0.42, 0.125 + 0.030 * flick))
		var lr2: float = 22.0 + 2.4 * flick
		draw_texture_rect(lamp,
			Rect2(sp + Vector2(0, 2) - Vector2(lr2, lr2 * 0.88),
				Vector2(lr2 * 2.0, lr2 * 2.0 * 0.88)),
			false, Color(amber.r, amber.g, amber.b, 0.16 + 0.05 * flick))
		# The ring stays a crisp arc: it is not the glow, it is the MARK that says
		# where the army is standing, and a standing mark wants a hard edge.
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
		# A PLAN IS SCORED; AN ORDER IS INKED. The preview used to be the committed
		# road at lower alpha, which made the difference between "considering this
		# branch" and "the column is on it" a brightness difference — the weakest
		# signal available, and the one that dies first on a bright chart.
		#
		# So the hover takes the same ink PROFILE (it is the same pen) with the gloss
		# off and the pressure flat: a dry-point ruling scored into the sheet before
		# any ink goes down. No taper, no heat, thinner, cooler. The stroke breathes
		# in ALPHA only — that is the "this road is live" feedback, and width would
		# have made a considered line look like a wet one.
		_ink_stroke("rule", _hover_path,
			Color(0.50, 0.35, 0.19, (0.52 + 0.18 * pulse) * age),
			8.5, 0.40, "")
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


	## ETNA IS BURNING AND THE CHART SHOULD SAY SO (2026-09-10).
	##
	## Was three grey `draw_circle` discs at alpha 0.085 drifting NE. At that
	## alpha it is not a subtle effect, it is an absent one — and where it did
	## register it was three dots, on the mountain the game is named after.
	##
	## The two axes, as everywhere else in this pass:
	##
	##   1. A SIGNATURE FORM. Not particles, because this is a CHART: what belongs
	##      on it is the engraved plume an old cartographer would have cut beside a
	##      smoking mountain. So a stack of LOBED CLOSED CONTOURS — the same family
	##      as the deckled coast and the engraved terrain marks already on the
	##      plate — each with a wash body and an ink outline. Closed-but-not-round
	##      is deliberate; it is the topology that reads as billowing rather than
	##      as bubbles, the same call the blight colony made in combat.
	##
	##   2. ITS OWN KIND OF ALIVENESS: CONVECTION AND SHEAR. Every lobe is born at
	##      the vent, RISES, EXPANDS fast then slowly (which is how a thermal
	##      actually grows), ROLLS — its wobble harmonics turn, so the silhouette
	##      churns instead of merely translating — and is bent downwind HARDER the
	##      higher it gets, because the column loses its own momentum and the wind
	##      takes over. Lobes are on offset phases, so the column always holds
	##      several at different ages: the bolt's "several discharges, not one
	##      object" rule, which is what stops a plume reading as a frozen decal.
	##
	## VALUE INVERTS HERE TOO. Smoke over cream paper has to be DARKER than the
	## page — a pale plume on parchment is the same nothing the old one was. The
	## single warm thing is the vent, which is the point: one ember on a dark
	## column, growing per act as the scorch does.
	func _draw_etna_plume() -> void:
		var act: int = clampi(RunState.current_act_idx, 0, 2)
		var vent: Vector2 = (map._etna_peak as Vector2) + Vector2(0, -22.0)
		# A COLUMN NEEDS ENOUGH LOBES TO CLOSE UP. Seven photographed as a string
		# of pearls — evenly spaced discs with daylight between them — because the
		# shear pulls each one sideways as well as up, so the true gap between
		# neighbours is the diagonal, not the rise step. Fourteen at the same rise
		# overlap along that diagonal, and overlap is the whole difference between
		# a column of smoke and a row of bubbles.
		var lobes: int = 14 + act * 4
		var rise: float = 138.0 + float(act) * 32.0
		var shear: float = 46.0 + float(act) * 16.0
		var weight: float = 0.15 + float(act) * 0.04
		# Built first, drawn second, and the two-pass split is the whole reason
		# this stopped looking like a bag of marbles — see the contour pass.
		var built: Array = []
		# A VOLCANO DOES NOT EXHALE AT A CONSTANT RATE. Spacing the lobes evenly
		# around the cycle made a conveyor belt — the same defect the dispatch
		# riders had, and the same one the bolt fixes by being three discharges
		# instead of one. An eruption PUFFS: a cluster of lobes leaves the vent
		# together, then the vent is quiet, then another. So the even slot is
		# WARPED — each third of the lobes is squeezed into the front 44% of its
		# share of the cycle, which leaves three tight groups with real gaps
		# between them and costs nothing but the warp.
		var puffs := 3.0
		for k in range(lobes):
			var slot: float = float(k) / float(lobes)
			var cell: float = floor(slot * puffs)
			var warped: float = (cell + (slot * puffs - cell) * 0.44) / puffs
			var ph := fmod(_t * 0.075 + warped, 1.0)
			# EXPANSION IS FAST THEN SLOW (pow < 1); RISE IS THE OTHER WAY ROUND.
			# A thermal leaves the vent quickly and stalls as it cools, so a
			# linear column is the tell that nothing is being modelled.
			var up := pow(ph, 0.82) * rise
			var r := 7.0 + 33.0 * pow(ph, 0.62)
			# The wind's grip grows with height — a straight lean reads as a
			# painted diagonal, a curve reads as weather.
			var over := shear * pow(ph, 1.55) \
				+ sin(_t * 0.55 + float(k) * 2.3) * 4.0
			# LATERAL SCATTER, widening with height. Without it every lobe sits on
			# one centre line and the column is a tube; a plume is ragged at the
			# edges because the lobes are not stacked, they are tumbling past each
			# other. Deterministic per lobe so nothing crawls between frames.
			var side := (sin(float(k) * 12.9898) * 43758.5453)
			side = (side - floor(side)) * 2.0 - 1.0
			# TURBULENT WANDER, per lobe and on its own clock. Without it every
			# lobe rides one shared curve and the column translates on rails; the
			# roll harmonics churn the OUTLINE but the mass still moves like a
			# train. Two slow terms at different rates and a per-lobe offset mean
			# no two lobes ever drift together.
			var wob := Vector2(
				sin(_t * 0.31 + float(k) * 1.7) * r * 0.17,
				cos(_t * 0.24 + float(k) * 2.3) * r * 0.11)
			var c := vent + Vector2(over + side * r * 0.30, -up) + wob
			# In and out: a lobe must not pop into being at full strength at the
			# vent, and it must be gone before it reaches the top of its run.
			# ^1.9, not ^1.25: the column has to be GONE by the top of its run, not
			# merely dim. A lobe that is still faintly present at ph 0.9 is a big
			# sparse disc with nothing left around it to hide its edges.
			var a: float = weight * smoothstep(0.0, 0.10, ph) * pow(1.0 - ph, 1.9)
			if a <= 0.004:
				continue
			var roll := _t * 0.5 + float(k) * 1.9
			# Squashed HARDER with height: the shear that bends the column also
			# flattens each lobe, so a plume spreads into an anvil rather than
			# staying a stack of balls.
			var squash: float = 0.92 - 0.26 * ph
			built.append({
				"c": c, "r": r, "sq": squash, "a": a, "ph": ph,
				"poly": _puff_poly(c, r, roll, squash),
			})
		# SORT BY PHASE BEFORE ANYTHING READS A NEIGHBOUR. `built` comes out in
		# `k` order and the phase WRAPS inside it (the measured run went
		# 0.77, 0.84, 0.91, 0.06, 0.13, …), so "the lobe three along in the array"
		# was sometimes the one at the top of the column being compared against
		# one still sitting in the vent. Every occlusion test below assumes array
		# adjacency means spatial adjacency; this is what makes that true.
		built.sort_custom(func(x, y): return float(x.ph) < float(y.ph))
		# PASS 1 — the wash, and the alpha here is LOW ON PURPOSE.
		#
		# THE LOBES ALREADY OVERLAP HEAVILY (radius ~28 at a ~10px rise step,
		# measured, not assumed) and the column STILL photographed as a row of
		# marbles. The cause is alpha accumulation: a point near a lobe's centre
		# is covered by more neighbours than a point on its rim, so stacking N
		# translucent fills manufactures a bright core at every centre — it builds
		# exactly the per-lobe structure the overlap was supposed to dissolve.
		# Same family as the lightning stack one level down: piling translucent
		# copies of a shape does not blur it, it embosses it.
		#
		# Kept low so a 3-deep overlap lands around 0.16 — which is also right for
		# what this is, since a real column IS denser down its middle. The READ is
		# carried by the outline below, not by this.
		# …and it is a TEXTURED blob, not a flat polygon, which is the same rule
		# that rebuilt every line in this game one primitive over:
		# `draw_colored_polygon` HAS UNIFORM OPACITY ACROSS ITS AREA. A flat fill
		# is a hard-edged disc however lumpy its outline, so a stack of them is a
		# stack of discs — which is precisely how the column kept photographing.
		# A smoke lobe is dense at its heart and gone at its rim; that has to be
		# painted, and `particle_tex` already paints it.
		#
		# It cannot be done by handing UVs to the polygon: a rim-only polygon
		# triangulates into fans that all TOUCH the rim, so the interpolated UV
		# never reaches the texture's centre and the gradient never appears. The
		# polygon keeps its job as the CONTOUR (where its per-lobe rolling
		# silhouette is the whole point) and the mass is drawn under it.
		#
		# THE COLOUR IS A MID VALUE ON PURPOSE, and it is the third time value had
		# to be re-decided in this one pass. The road ink went DARK because it
		# lies on cream parchment. The plume's contour went PALE because Etna sits
		# in the chart's dark eastern mountains. But the column itself CROSSES
		# BOTH — it is born on black rock and drifts out over open paper — so
		# neither answer works for the whole of it, and a pale plume simply
		# vanished the moment it cleared the range. A mid warm grey lightens
		# against the rock and darkens against the page, which is also exactly
		# what smoke does. Under-exposure was the other half: an amplified frame
		# diff showed a dense, correctly-billowing column that was rendering at
		# roughly a tenth of the contrast needed to see any of it.
		var blob := Motion.particle_tex("fleck")
		for L in built:
			var bc: Vector2 = L.c
			var br: float = float(L.r)
			var bs: float = float(L.sq)
			draw_texture_rect(blob,
				Rect2(bc - Vector2(br, br * bs), Vector2(br * 2.0, br * 2.0 * bs)),
				false, Color(0.53, 0.48, 0.43, float(L.a) * 4.2))
		# PASS 2 — THE ENGRAVED SILHOUETTE. Two things are decided here.
		#
		# WHICH EDGES: the first cut drew a CLOSED contour around every lobe, so
		# every internal edge stayed drawn and the eye counted circles —
		# overlapping fills merge, overlapping OUTLINES do not. What an engraver
		# draws is the outline of the UNION: arcs and hollow C-shapes where one
		# billow passes in front of another, never a ring around each. So each
		# vertex is tested against its neighbours, dropped if it lies inside one,
		# and the surviving stretches drawn as OPEN polylines.
		#
		# WHAT COLOUR: pale ash, not ink — and this is the inversion that was
		# missed twice in one session. The road ink went DARK because it lies on
		# cream parchment; Etna sits in the chart's DARK EASTERN MOUNTAINS, and a
		# dark line there is the same nothing a white core was on the paper. The
		# rule is not "dark on this chart", it is: VALUE IS DECIDED BY THE LOCAL
		# GROUND. Pale is also what smoke actually is against black rock.
		for i in range(built.size()):
			var L: Dictionary = built[i]
			var ph2: float = float(L.ph)
			# Warm ash, not white. At 0.62 near-white the silhouette shouted over
			# its own wash and the plume became a wire outline of a plume.
			var ash := Color(0.80, 0.775, 0.735,
				minf(float(L.a) * 2.4 * (1.0 - ph2 * 0.75), 0.26))
			if ash.a <= 0.012:
				continue
			var run := PackedVector2Array()
			var pts2: PackedVector2Array = L.poly
			for v in pts2.size() + 1:
				var p: Vector2 = pts2[v % pts2.size()]
				# Nothing below the vent lip: the lowest lobe has no neighbour
				# beneath it, so its underside survives every occlusion test and
				# draws a bowl slung under the mountain.
				if p.y > vent.y + 4.0 or _lobe_hidden(p, built, i):
					if run.size() >= 2:
						draw_polyline(run, ash, 1.4, true)
					run = PackedVector2Array()
				else:
					run.append(p)
			if run.size() >= 2:
				draw_polyline(run, ash, 1.4, true)
		# THE VENT IS ALREADY PAINTED ON THE PLATE — an orange mouth with lava
		# streaks. The first cut stacked two more discs on top of it and the
		# result was a fuzzy orange ball sitting over a perfectly good drawing.
		# What the plate cannot do is BREATHE, so that is all that is left here:
		# one small ember pulse on its own slow clock, well inside the painted
		# mouth, deliberately out of step with the player's lamplight so the two
		# never beat together.
		# THE VENT FLARES WHEN A PUFF LEAVES IT, not on a clock of its own. Tying
		# the ember to the same phase that births each cluster is the difference
		# between two things happening near each other and one thing CAUSING the
		# other — and causality is most of what separates an effect you watch from
		# an effect you notice. The flare is sharp (^3.2) and the ember never quite
		# goes out between them.
		var pp: float = fmod(_t * 0.075 * puffs, 1.0)
		var flare: float = pow(1.0 - pp, 3.2)
		draw_circle(vent + Vector2(0, 16.0), 3.6 + 2.6 * flare,
			Color(1.0, 0.66, 0.26,
				(0.22 + 0.34 * flare) * (0.7 + 0.15 * float(act))),
			true, -1.0, true)
		# ASH RIDES THE COLUMN. Smoke alone is one material and reads as one
		# object; specks moving FASTER than the mass that carries them are what
		# say the column is being driven from below rather than drifting. Few and
		# small on purpose — this is punctuation, not a second effect.
		for s in range(6 + act * 2):
			var sp2 := fmod(_t * 0.17 + float(s) * 0.1631, 1.0)
			var sr: float = 1.5 + 1.1 * sin(float(s) * 5.1)
			var sx: float = shear * pow(sp2, 1.55) * 1.25 \
				+ sin(_t * 0.8 + float(s) * 2.7) * 9.0
			draw_circle(vent + Vector2(sx, -pow(sp2, 0.72) * rise * 1.22), sr,
				Color(0.17, 0.14, 0.12, 0.42 * pow(1.0 - sp2, 1.4)),
				true, -1.0, true)

	## Shake the last few points of a stroke and nothing else. The bolt pins BOTH
	## endpoints because both of its ends are anchored to something; a pen has one
	## anchored end (where the stroke began, which has dried) and one live end
	## (the tip, which is in a hand). So the taper runs the other way here: zero
	## movement at the back of the window, full at the nib.
	func _tremble_head(pts: PackedVector2Array, amt: float) -> PackedVector2Array:
		var n := pts.size()
		if n < 3 or amt <= 0.0:
			return pts
		var out := pts.duplicate()
		var span := mini(4, n - 1)
		for k in range(span):
			var i := n - 1 - k
			var w: float = amt * (1.0 - float(k) / float(span))
			out[i] = pts[i] + Vector2(randf_range(-w, w), randf_range(-w, w))
		return out

	## A HAND-DRAWN LINE OVER A RULED ONE.
	##
	## Midpoint displacement (the bolt's generator) at THREE levels rather than
	## five, then two rounds of Chaikin corner-cutting. The smoothing is the whole
	## point of the difference: displacement alone produces a self-similar ZIGZAG,
	## which is a crack or a discharge and is exactly what a nib cannot make. Cut
	## the corners and the same deviation becomes an arm that drifted and fingers
	## that trembled.
	##
	## AMPLITUDE IS A FRACTION OF THE RUN, never a constant — the bolt's second
	## rule. 2.6% of the leg is a few px on a short hop and a visible wander on a
	## long one, which is how a real hand scales too. Any larger and the ink stops
	## agreeing with the road it is marking.
	##
	## Seeded off the leg's own geometry, so the SAME march always draws the same
	## line: a stroke that re-rolled itself every frame would be a scribble, and
	## re-rolling per redraw is the one thing a written line must never do. (The
	## bolt re-rolls precisely BECAUSE a discharge is not a lasting object.)
	func _hand_path(src: PackedVector2Array, run: float) -> PackedVector2Array:
		if src.size() < 2 or run <= 1.0:
			return src
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(int(src[0].x), int(src[src.size() - 1].y)))
		var pts := src.duplicate()
		# 1.4%, not 2.6%. At the larger figure the ink visibly LEFT the road and
		# swung back, and beside a printed dashed road that does not read as a
		# hand, it reads as a registration error. A hand-drawn line over a ruled
		# one deviates by a hair — enough to break the machine-perfect trace and
		# no more. The ink has to keep agreeing with the thing it is marking.
		var amp: float = run * 0.014
		for _lvl in range(3):
			var next := PackedVector2Array([pts[0]])
			for i in range(pts.size() - 1):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var n: Vector2 = (p1 - p0).orthogonal().normalized()
				next.append((p0 + p1) * 0.5 + n * rng.randf_range(-amp, amp))
				next.append(p1)
			pts = next
			amp *= 0.5
		# Chaikin, twice. Endpoints are held: the stroke has to start at the camp
		# and finish on the site, whatever the hand did in between.
		for _s in range(2):
			var sm := PackedVector2Array([pts[0]])
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				sm.append(a.lerp(b, 0.25))
				sm.append(a.lerp(b, 0.75))
			sm.append(pts[pts.size() - 1])
			pts = sm
		# RESAMPLE, or the stroke grows hair. Three displacement levels multiply
		# the point count by 8 and two Chaikin rounds by 4 again — a 30-point road
		# comes out at ~960, most of them separated by well under a pixel. A Line2D
		# with round joints at width 17 turns segments that short into a fringe of
		# overlapping quads along both edges, which photographed as a furry line;
		# and every frame of the march was slicing and rebuilding all of them.
		# Even spacing keeps the shape, kills the fringe, and costs ~40 points.
		return _resample(pts, 7.0)

	## Walk a path and emit a point every `step` units, ends included.
	func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
		if pts.size() < 2 or step <= 0.01:
			return pts
		var out := PackedVector2Array([pts[0]])
		var carry := 0.0
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var seg := a.distance_to(b)
			if seg <= 0.0001:
				continue
			var t := step - carry
			while t <= seg:
				out.append(a.lerp(b, t / seg))
				t += step
			carry = fmod(carry + seg, step)
		out.append(pts[pts.size() - 1])
		return out

	## Is this boundary point buried inside a NEIGHBOURING lobe? Only neighbours
	## are checked (±3 in phase order): they are the only ones close enough to
	## overlap, and an all-pairs test on 18 lobes × 18 vertices every frame buys
	## nothing. Tested in the lobe's own squashed space, at 0.95 of its radius —
	## the boundary itself wobbles ±35%, so a full-radius test eats arcs that are
	## genuinely on the outside of the column.
	func _lobe_hidden(p: Vector2, built: Array, skip: int) -> bool:
		var n := built.size()
		for d in [-3, -2, -1, 1, 2, 3]:
			var j: int = skip + d
			if j < 0 or j >= n:
				continue
			var L: Dictionary = built[j]
			# THE THRESHOLD HERE MUST MATCH THE ONE THAT DECIDED TO DRAW THE LOBE
			# AT ALL. It was set an order of magnitude higher, on the reasonable-
			# sounding grounds that an invisible neighbour should not bite a hole
			# in a visible outline — and the effect was the opposite: the faint
			# lobes at the TOP of the column stopped occluding anything, their
			# outlines closed into complete rings, and the plume grew a chain of
			# hard circles exactly where it was supposed to be dissolving. Anything
			# that is drawn, occludes.
			if float(L.a) <= 0.004:
				continue
			var c: Vector2 = L.c
			var sq: float = maxf(float(L.sq), 0.01)
			var dx: float = p.x - c.x
			var dy: float = (p.y - c.y) / sq
			if Vector2(dx, dy).length() < float(L.r) * 0.95:
				return true
		return false

	## One lobe's silhouette. TWO harmonics, both turning with `roll`: a single
	## one only wobbles, and a wobble that keeps its shape is a jelly. Two at
	## different rates and opposite signs is what makes the contour appear to
	## turn over on itself, which is the whole read of billowing smoke.
	func _puff_poly(c: Vector2, r: float, roll: float,
			squash: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		# 34, NOT 18. The union silhouette is drawn as OPEN runs cut out of these
		# polygons, and a run of four vertices off an 18-gon at radius 30 is a
		# visibly faceted zig-zag — it photographed as crystal, not smoke. A fill
		# hides its own facets; a stroke along the same boundary cannot.
		var n := 34
		for i in range(n):
			var a := TAU * float(i) / float(n)
			var w := 1.0 + 0.23 * sin(a * 3.0 + roll) \
				+ 0.12 * sin(a * 5.0 - roll * 1.7)
			out.append(c + Vector2(cos(a) * r * w, sin(a) * r * w * squash))
		return out

	## THE DISPATCH RIDERS (2026-09-10).
	##
	## Was a 3px `draw_line` from tail to head with a 2.2px disc stuck on the
	## front — a line and a dot, on every open road, permanently. Three things
	## were wrong with it and only one of them was the technique:
	##
	##   1. IT CHORDED ACROSS THE CURVE. Two points cannot follow a bend, so on
	##      every curved leg the runner cut the corner and left the road. Sampled
	##      along the arc now, so it rides what it is meant to be pointing at.
	##   2. IT WAS A CONVEYOR BELT. A linear phase with no gap means the runners
	##      never stop and never start; the eye reads that as machinery, not as
	##      traffic. The bolt's first lesson generalises here — a thing that is
	##      always happening is not happening. Each leg now dispatches a rider,
	##      holds empty for a beat, and dispatches again, with the runs on
	##      per-edge offsets so the roads never fire in unison.
	##   3. IT WAS A FLAT BAND. Textured comet now: narrow tail, bright blunt
	##      head. And the taper does a second job — a symmetrical streak has no
	##      direction, which is the ONE thing this effect exists to say.
	##
	## Core stays WHITE here, unlike the road ink. This is LIGHT running over the
	## chart rather than pigment soaking into it, and a highlight on cream still
	## wants to be brighter than its ground.
	func _draw_glints() -> void:
		_ensure_glint_cache()
		for ei in range(map._edges.size()):
			var slot := "glint_%d" % ei
			var e: Dictionary = map._edges[ei]
			var pts: PackedVector2Array = map._edge_curves[ei]
			var total: float = _glint_total[ei] if ei < _glint_total.size() else 0.0
			if not bool(e.to_avail) or pts.size() < 2 or total < 60.0:
				_ink_stroke(slot, PackedVector2Array(), Color.WHITE, 1.0, 0.0, "")
				continue
			# 0.68 of the cycle is the run, the rest is the road standing empty.
			var raw := fmod(_t * 0.34 + float(ei) * 0.37, 1.0)
			if raw > 0.68:
				_ink_stroke(slot, PackedVector2Array(), Color.WHITE, 1.0, 0.0, "")
				continue
			var k := raw / 0.68
			# Off the mark quickly, easing into the gate — a rider's pace, not a
			# constant one. Smoothstep either end reads as both at once.
			var eased := k * k * (3.0 - 2.0 * k)
			var cum: PackedFloat32Array = _glint_cum[ei]
			var run := total - 46.0
			var hd := 20.0 + run * eased
			var tail_len := 34.0
			var body := PackedVector2Array()
			for s in range(7):
				var d := hd - tail_len * (1.0 - float(s) / 6.0)
				body.append(map._route_arc_point(pts, cum, maxf(d, 4.0)))
			# SNAP ON, THEN DIE — asymmetric, not a sine. A symmetric envelope
			# fades a rider IN as slowly as it fades out, so there is no instant
			# the dispatch can be said to have happened; the bolt's rule is that
			# the hold is the effect and the onset is a snap. Lit inside the first
			# 6% of the run, then decaying the rest of the way, so what trails is
			# a wake rather than a fade.
			var fade: float = clampf(k / 0.06, 0.0, 1.0) * pow(1.0 - k, 0.75)
			# Kind "comet" AND taper "comet" are two different halves: the kind
			# ramps ALPHA along the line (the tail dissolving), the taper ramps
			# WIDTH. Only doing the second leaves a fully opaque thread trailing
			# the head, which reads as a tether rather than a wake.
			_ink_stroke(slot, body,
				Color(1.0, 0.84, 0.44, 0.70 * fade), 10.0, 0.85, "comet",
				Color(1.0, 0.97, 0.86), "comet")

	## Build, update, or hide one ink stroke. `slot` names the stroke; passing a
	## path shorter than two points hides whatever is there rather than freeing it,
	## because these four rebuild constantly (every hover, every march frame) and
	## churning nodes on a 30 Hz redraw is how you get a stutter on a pan.
	##
	## `width` is the FULL painted span, so it is much wider than the hard stroke
	## it replaces — most of the extra is feathered edge that was not being drawn
	## at all. A TAPERED stroke needs a fatter base again (the width curve and the
	## texture's cross-section both multiply down, and the curve only reaches 1.0
	## at one point along the line): the ~4.8x rule from the strike arc.
	func _ink_stroke(slot: String, pts: PackedVector2Array, tint: Color,
			width: float, heat: float, taper: String,
			core: Color = INK_CORE, kind: String = "ink") -> void:
		var ln: Line2D = _ink_nodes.get(slot)
		if pts.size() < 2:
			if is_instance_valid(ln):
				ln.visible = false
			return
		if not is_instance_valid(ln):
			if _fx == null:
				return
			ln = Motion.beam_line(pts, tint, width, kind, heat, taper, core)
			_fx.add_child(ln)
			_ink_nodes[slot] = ln
		ln.visible = true
		ln.points = pts
		ln.width = width
		var mat := ln.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("tint", tint)
			mat.set_shader_parameter("core", core)
			mat.set_shader_parameter("heat", heat)

	## THE ROAD IS WRITTEN, NOT DRAWN (2026-09-10).
	##
	## The old version stacked four flat polylines and called the brightest one the
	## covered part. What it could not say — because a uniform band cannot say
	## anything about itself — is that the road is being LAID DOWN by something,
	## right now, at a particular point.
	##
	## The bolt's two axes, applied here:
	##
	##   1. A SIGNATURE FORM. Not "a line in the road's colour" but a PEN STROKE:
	##      the "ink" cross-section (dense body, edges feathering into the paper
	##      fibres) under the "nib" taper (a firm entry, a pressure belly, and the
	##      widest point at the terminal, where the nib is sitting).
	##
	##   2. ITS OWN KIND OF ALIVENESS, matched to the matter. Lightning flickers,
	##      fire churns, a crack propagates — and ink SETS. The stroke is split at
	##      a fixed distance behind the pen: ahead of that split it is WET, behind
	##      it the ink has dried. Neither half animates on its own; the SPLIT POINT
	##      rides the nib, so the whole road visibly dries from the back as the
	##      column walks it. Copying the bolt's per-frame jitter here would have
	##      been the mistake the fire pass made first — matched to the wrong
	##      matter, a road that buzzes is a rendering fault, not a living one.
	##
	## WET IS DARKER THAN DRY, which is the opposite of the obvious cut and is the
	## way ink actually behaves: a fresh stroke is a pool of pigment, saturated and
	## heavy, and it LIGHTENS as it sets. Building the wet lead as the bright end
	## put the two halves in the wrong order and lost the gloss as well, since on
	## cream paper "glossy" cannot be a brighter body — it has to be a small
	## specular ON a dark mark. Hence the fourth stroke: a thin pale highlight
	## riding the last stretch, which is also where the house contrast rule lands
	## once inverted (the darkest dark AND the brightest bright, both at the nib,
	## which is the one place the eye should go).
	##
	## The unwalked remainder stays underneath as the RULED PLAN: same profile,
	## thin, low, matte. A plan and an order must not look alike.
	func _draw_committed_route(amber: Color) -> void:
		var covered_len: float = clampf(_march_prog, 0.0, 1.0) * _march_len
		var wet_from: float = maxf(covered_len - INK_WET_RUN, 0.0)
		_ink_stroke("plan", _march_pts,
			Color(0.36, 0.26, 0.15, 0.52), 9.5, 0.30, "")
		# THE DRY STROKE IS WIDER THAN THE WET ONE, and the first cut had that
		# backwards (wet 20, dry 12). A nib lays a NARROW, HEAVY BEAD; the paper
		# then drinks it and the mark BLOOMS outward as it sets, ending wider and
		# paler than it was laid. Getting it the wrong way round meant the wet/dry
		# boundary was carried by value alone — now width and value move together
		# and in opposite directions, which is twice the signal for no extra ink.
		#
		# Overlap the dry stroke a few px INTO the wet one. Butted exactly at the
		# split, two feathered strokes leave a visible dip where both edges are
		# falling off at once — the seam reads as a break in the road.
		_ink_stroke("dry", _march_slice(0.0, minf(wet_from + 7.0, covered_len)),
			Color(0.64, 0.43, 0.20, 0.94), 14.0, 0.50, "")
		# THE NIB TREMBLES. The bolt's other half — a channel that is never still
		# for one frame — scoped to the only part of a written line where it is
		# true: laid ink has dried in place and must not crawl, so only the last
		# few points move, and less the further back they sit.
		_ink_stroke("wet", _tremble_head(_march_slice(wet_from, covered_len), 1.5),
			Color(0.44, 0.25, 0.10, 1.0), 13.0, 0.86, "nib")
		# The specular. Core WHITE here and nowhere else on the chart: this stroke
		# IS the highlight, so the kit's default is finally the right one.
		_ink_stroke("gloss",
			_tremble_head(_march_slice(maxf(covered_len - 52.0, 0.0),
				covered_len), 1.5),
			Color(1.0, 0.90, 0.58, 0.74), 5.0, 0.90, "nib",
			Color(1.0, 0.98, 0.90))
		# The blots left where the pen rested between strokes. Drawn only once the
		# ink has actually reached them, and immediate-mode rather than a beam,
		# because a pool of ink is a BLOT — a soft irregular mass, not a stroke —
		# and `particle_tex("ink")` is exactly that silhouette.
		if not _ink_rests.is_empty():
			var blot := Motion.particle_tex("ink")
			for rd in _ink_rests:
				if rd > covered_len:
					continue
				var bp := _march_point_at_distance(rd)
				var brr: float = 8.5
				draw_texture_rect(blot,
					Rect2(bp - Vector2(brr, brr * 0.82),
						Vector2(brr * 2.0, brr * 2.0 * 0.82)),
					false, Color(0.20, 0.125, 0.06, 0.62))
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


	## The sub-path of the march between two arc-lengths, with both ends cut
	## exactly (interpolated into whichever segment they land in) rather than
	## snapped to the nearest vertex. Generalises the old `_march_progress_path`,
	## which was this with `d0` pinned to 0; the ink needs a middle slice too,
	## since the wet lead is a window that travels rather than a prefix that grows.
	##
	## An end cut to the nearest VERTEX would be the cheap version and it is wrong
	## twice over: the road's curves are coarsely sampled, so the nib would jump
	## between vertices instead of gliding, and the wet window would breathe in
	## length as it crossed each one.
	func _march_slice(d0: float, d1: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		if _march_pts.size() < 2 or _march_len <= 0.0:
			return out
		var a := clampf(minf(d0, d1), 0.0, _march_len)
		var b := clampf(maxf(d0, d1), 0.0, _march_len)
		if b - a < 0.5:
			return out
		out.append(_march_point_at_distance(a))
		for i in range(1, _march_pts.size()):
			var d: float = _march_cum[i]
			if d <= a:
				continue
			if d >= b:
				break
			out.append(_march_pts[i])
		out.append(_march_point_at_distance(b))
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
