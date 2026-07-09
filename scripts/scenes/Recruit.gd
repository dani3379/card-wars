extends Control
## Recruit.gd — Successor Wars muster stop. A free, curated 1-of-3 card
## draft (Inscryption model: visiting the site IS the cost — no gold, no new
## currency; CONQUEST_REDESIGN.md §15.1 #2+8). Deck growth lives here now
## that fights pay ground instead of cards. The offer leans toward the
## kingdom being invaded — locals and sellswords join the claim that's
## winning. Fully programmatic UI, same pattern as Shop/Rest/Reward.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"

# Roll a wide slate, keep the 3 most kingdom-aligned. This delivers the
# "curated faction draft" without per-card faction data — the affinity
# table reads the shape cards already have. A real faction tag pass can
# replace it later without touching this screen's flow.
const SLATE_SIZE := 8

# What "fits the kingdom" means per faction, read off existing card fields.
const AFFINITY := {
	"grasswake": {"kw": ["swift", "piercing", "overrun"], "cheap": true},
	"last_wall": {"kw": ["armored", "thorns", "guardian", "shield", "last_stand", "formation"], "adj": true},
	"owed": {"kw": ["sacrifice", "lifelink"], "on_death": true},
	"lanternhall": {"kw": ["echo", "retain", "exhaust"], "spell": true},
	"everflame": {"kw": ["doom", "rampage", "lifelink"], "burn": true},
}

const ROLE_TIPS := {
	"LOCAL BANNER": "Best match for the kingdom's fighting style.",
	"ROAD BANNER": "A broad recruit for the road ahead.",
	"FIELD ANSWER": "A second-fit pick that answers the current country.",
	"SELLSWORD": "Less local, often more flexible.",
	"EXTRA BANNER": "Scout's Emblem found a fourth name.",
	"STARDUST RARE": "Stardust Vial added a rare recruit."
}

var _choices: Array[String] = []
var _choice_roles: Dictionary = {}
# Collector's Tome lets the player enlist 2 banners from one muster. Resets
# implicitly on scene unload (a fresh Recruit instance starts at 0).
var _tome_picks: int = 0
# Live choice card controls in the current slate (populated by _build_ui) -- the
# reroll flourish sweeps exactly these off the table.
var _card_nodes: Array = []
# Guards the reroll while its sweep animation plays (blocks a double-blow and a
# stray enlist mid-gust).
var _rerolling: bool = false
# Blocks a double-click from enlisting the same card twice while the scene fades.
var _enlist_committing: bool = false


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "reward")
	_choices = _roll_offer()
	_assign_choice_roles(_choices)
	_build_ui()
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay rather than walking away from the
	# free muster on a mis-tap.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _roll_offer() -> Array[String]:
	# The card-offer relics moved here with the draft itself:
	# Busted Crown shrinks the muster to 2, Scout's Emblem widens it to 4,
	# Stardust Vial adds a rare banner on top.
	var offer_size := 3
	if RunState.has_downside("fewer_rewards"):
		offer_size = 2
	elif RunState.has_relic("scouts_emblem"):
		offer_size = 4
	var faction: String = RunState.get_act_faction()
	var slate: Array[String] = CardDB.roll_card_reward(
		RunState.get_act(), false, false, maxi(SLATE_SIZE, offer_size))
	var out: Array[String] = []
	if faction == "" or slate.size() <= offer_size:
		out = slate.slice(0, mini(offer_size, slate.size()))
	else:
		var scored: Array = []
		for id in slate:
			scored.append({"id": id,
				"s": _affinity(CardDB.get_card_data(id), faction), "r": randf()})
		scored.sort_custom(func(a, b):
			return a.s > b.s if a.s != b.s else a.r > b.r)
		for i in offer_size:
			out.append(String(scored[i].id))
	if RunState.has_relic("stardust_vial"):
		var rare_pool: Array[String] = CardDB.get_pool_by_rarity("rare")
		while rare_pool.size() > 0:
			var picked: String = rare_pool.pop_at(randi() % rare_pool.size())
			if not out.has(picked):
				out.append(picked)
				break
	return out


func _assign_choice_roles(ids: Array[String]) -> void:
	_choice_roles.clear()
	var labels: Array[String] = [
		"LOCAL BANNER",
		"FIELD ANSWER",
		"SELLSWORD",
		"EXTRA BANNER",
	]
	for i in range(ids.size()):
		var label: String = labels[mini(i, labels.size() - 1)]
		if RunState.get_act_faction() == "" and label == "LOCAL BANNER":
			label = "ROAD BANNER"
		if RunState.has_relic("stardust_vial") and i == ids.size() - 1:
			label = "STARDUST RARE"
		_choice_roles[ids[i]] = label


func _choice_role_tip(id: String) -> String:
	var role := String(_choice_roles.get(id, "ROAD BANNER"))
	return String(ROLE_TIPS.get(role, "A recruit joining your march."))


func _affinity(d: Dictionary, faction: String) -> int:
	var rules: Dictionary = AFFINITY.get(faction, {})
	if rules.is_empty():
		return 0
	var s := 0
	var kws: Array = d.get("keywords", [])
	for kw in rules.get("kw", []):
		if kws.has(kw):
			s += 2
	if rules.get("cheap", false) and int(d.get("cost", 9)) <= 1:
		s += 1
	if rules.get("adj", false) and d.has("adj_buff"):
		s += 2
	if rules.get("on_death", false) and (d.has("on_death") or kws.has("on_death")):
		s += 2
	if rules.get("spell", false) and String(d.get("type", "")) == "spell":
		s += 2
	if rules.get("burn", false) and String(d.get("type", "")) == "spell":
		var st: String = String(d.get("spell", {}).get("type", ""))
		if st.contains("damage") or st.contains("burn"):
			s += 2
	# Phase 2.5 — the muster leans to the country it camps in. A +1 bump
	# only: faction affinity stays the lead voice, terrain is the accent.
	match RunState.current_terrain:
		"woods":
			for kw in ["swift", "piercing"]:
				if kws.has(kw):
					s += 1
					break
		"pass":
			for kw in ["armored", "thorns", "shield"]:
				if kws.has(kw):
					s += 1
					break
		"ash":
			if kws.has("doom") or kws.has("rampage"):
				s += 1
			elif String(d.get("type", "")) == "spell" \
					and String(d.get("spell", {}).get("type", "")).contains("damage"):
				s += 1
		"meadow":
			if int(d.get("cost", 9)) <= 1:
				s += 1
	return s


func _build_ui() -> void:
	_card_nodes.clear()
	for child in get_children():
		# Keep the reroll sweep overlay alive across the rebuild so the outgoing
		# recruits keep scattering while the new banners march in (it self-frees).
		if child.name != "Background" and child.name != "Atmosphere" \
				and child.name != "RerollSweepFX":
			child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	var title = GameTheme.make_screen_title("THE MUSTER",
		GameTheme.GILT_BRIGHT, GameTheme.FONT_HEADER)
	outer.add_child(title)

	# The kingdom line sells the conquest fantasy: these are the invaded
	# land's people changing banners, not a shop shelf.
	var faction: String = RunState.get_act_faction()
	var flavor := "Wanderers seek your banner. Take one, no charge."
	if faction != "":
		var fname: String = String(HeroDB.faction_info(faction).get("name", ""))
		if fname != "":
			flavor = "Word spreads through %s. Take one banner, no charge." % fname
	var sub = GameTheme.make_label(flavor, GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)

	if _choices.size() > 0:
		var stage := PanelContainer.new()
		stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var accent := _muster_accent()
		var st := GameTheme.make_panel_style(
			Color(0.045, 0.036, 0.030, 0.42),
			Color(accent.r, accent.g, accent.b, 0.46),
			1, 4, true, true)
		st.content_margin_left = 18
		st.content_margin_right = 18
		st.content_margin_top = 18
		st.content_margin_bottom = 18
		stage.add_theme_stylebox_override("panel", st)
		outer.add_child(stage)

		var stage_margin := MarginContainer.new()
		stage_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage_margin.add_theme_constant_override("margin_top", 8)
		stage_margin.add_theme_constant_override("margin_bottom", 8)
		stage.add_child(stage_margin)

		var card_row = HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 30)
		card_row.alignment = BoxContainer.ALIGNMENT_CENTER
		card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stage_margin.add_child(card_row)

		var slot_idx := 0
		for id in _choices:
			var data = CardDB.get_card_data(id)
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 8)
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			slot.tooltip_text = _choice_role_tip(id)
			card_row.add_child(slot)

			var role := String(_choice_roles.get(id, "ROAD BANNER"))
			var role_lbl := GameTheme.make_label(role, 15, accent)
			role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			role_lbl.custom_minimum_size = Vector2(210, 0)
			role_lbl.tooltip_text = _choice_role_tip(id)
			slot.add_child(role_lbl)

			var card_wrap := Control.new()
			card_wrap.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H)
			card_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			card_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_wrap.pivot_offset = card_wrap.custom_minimum_size * 0.5
			slot.add_child(card_wrap)

			var card = CARD_SCENE.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = id
			card.is_on_battlefield = true
			card.live_baked_mode = true
			CardTextureCache.bake(data)
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.gui_input.connect(_on_recruit_card_input.bind(id, card, card_wrap))
			card.mouse_entered.connect(_on_recruit_card_hover.bind(card_wrap, true))
			card.mouse_exited.connect(_on_recruit_card_hover.bind(card_wrap, false))
			card_wrap.add_child(card)
			_card_nodes.append(card_wrap)

			_animate_card_reveal(card_wrap, slot_idx)
			slot_idx += 1

	# Recruiter's Horn: spend a charge to call up a fresh slate of recruits.
	# Only shown while the relic is held AND charges remain — the button vanishes
	# once the run's pool is spent, so it never dangles as a dead control.
	if _choices.size() > 0 and RunState.has_relic("recruiters_horn") \
			and RunState.muster_rerolls_left > 0:
		var reroll_btn = GameTheme.make_themed_button(
			"Sound the Horn — new recruits  (%d left)" % RunState.muster_rerolls_left,
			Color(0.20, 0.14, 0.06), Vector2(380, 40), 16)
		reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reroll_btn.tooltip_text = "Recruiter's Horn — reroll this muster's recruits."
		reroll_btn.pressed.connect(_reroll_muster)
		outer.add_child(reroll_btn)

	var leave_btn = GameTheme.make_back_button("Turn Them Away", Vector2(200, 42))
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(_go_to_map)
	outer.add_child(leave_btn)


func _muster_accent() -> Color:
	var faction := RunState.get_act_faction()
	if faction != "":
		var fac: Dictionary = HeroDB.faction_info(faction)
		if not fac.is_empty():
			var col: Color = fac.get("color", GameTheme.GILT)
			return col.lerp(Color.WHITE, 0.22)
	return GameTheme.GILT


func _animate_card_reveal(card: Control, idx: int) -> void:
	# Staggered fan-in, same beat as the Reward screen's reveal.
	card.modulate.a = 0.0
	card.scale = Vector2(0.6, 0.6)
	var delay := 0.18 + float(idx) * 0.16
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.28).set_delay(delay)
	tw.tween_property(card, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)


func _on_recruit_card_input(event: InputEvent, id: String,
		card: Control, card_wrap: Control) -> void:
	if _rerolling or not _choices.has(id):
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if card != null and is_instance_valid(card):
		card.accept_event()
	if event.pressed:
		_set_recruit_card_pick_pose(card_wrap, true)
	else:
		_set_recruit_card_pick_pose(card_wrap, false)
		_enlist(id)


func _on_recruit_card_hover(card_wrap: Control, hovered: bool) -> void:
	if card_wrap == null or not is_instance_valid(card_wrap) or _rerolling:
		return
	card_wrap.z_index = 2 if hovered else 0
	if UserSettings.reduce_motion:
		return
	var target := Vector2(1.045, 1.045) if hovered else Vector2.ONE
	var tw := card_wrap.create_tween()
	tw.tween_property(card_wrap, "scale", target, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_recruit_card_pick_pose(card_wrap: Control, pressed: bool) -> void:
	if card_wrap == null or not is_instance_valid(card_wrap) or UserSettings.reduce_motion:
		return
	var target := Vector2(0.985, 0.985) if pressed else Vector2(1.045, 1.045)
	var tw := card_wrap.create_tween()
	tw.tween_property(card_wrap, "scale", target, 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Recruiter's Horn reroll: sound the horn, blow the current recruits off the
## table, and call up a fresh slate. Gated on the button's own visibility (relic
## + charges), with use_muster_reroll() as the authoritative spend so a
## double-click can't over-draw the pool; _rerolling blocks re-entry while the
## sweep plays.
func _reroll_muster() -> void:
	if _rerolling:
		return
	if not RunState.use_muster_reroll():
		return
	_rerolling = true
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Horn blast: gold call-rings + the current recruits scattering away.
	GameTheme.reroll_sweep(self, _card_nodes.duplicate(), GameTheme.GILT_BRIGHT)
	# A short beat, then the new banners march in over the tail of the sweep.
	await get_tree().create_timer(0.18).timeout
	_choices = _roll_offer()
	_assign_choice_roles(_choices)
	_build_ui()
	_rerolling = false


func _enlist(id: String) -> void:
	if _rerolling or _enlist_committing:
		return
	_enlist_committing = true
	RunState.add_card(id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Collector's Tome: a second banner may join from the same muster.
	if RunState.has_relic("collectors_tome") and _tome_picks < 1 \
			and _choices.size() > 1:
		_tome_picks += 1
		_choices.erase(id)
		_assign_choice_roles(_choices)
		_enlist_committing = false
		_build_ui()
		return
	_go_to_map()


func _go_to_map() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
