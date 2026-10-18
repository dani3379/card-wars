extends Control
## Recruit.gd — Successor Wars muster stop. A free, curated 1-of-3 card
## draft (Inscryption model: visiting the site IS the cost — no gold, no new
## currency; CONQUEST_REDESIGN.md §15.1 #2+8). Deck growth lives here now
## that fights pay ground instead of cards. The offer leans toward the
## kingdom being invaded — locals and sellswords join the claim that's
## winning. Fully programmatic UI, same pattern as Shop/Rest/Reward.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const MAP_SCENE = "res://scenes/map.tscn"

# Roll a wide slate, keep the 3 most kingdom-aligned. Explicit card affinities
# lead the "curated faction draft"; the shape heuristics keep the rest of the
# pool legible without requiring every card to carry a faction tag.
const SLATE_SIZE := 8

# What "fits the kingdom" means per faction, read off existing card fields.
const AFFINITY := {
	"grasswake": {"kw": ["swift", "piercing", "overrun"], "cheap": true},
	"last_wall": {"kw": ["armored", "thorns", "guardian", "shield", "last_stand", "formation"], "adj": true},
	"owed": {"kw": ["sacrifice", "lifelink"], "on_death": true},
	"lanternhall": {"kw": ["echo", "retain", "exhaust"], "spell": true},
	"everflame": {"kw": ["doom", "rampage", "lifelink"], "burn": true},
}

# CAUTION: each key here is BOTH the dictionary key AND the caption printed
# over the card (`_assign_choice_roles` also compares against them, and two
# `.get()` calls fall back to "ALL-ROUND PICK"). So a wording change is a
# 6-site coordinated edit, not a copy edit — rename every occurrence in this
# file at once. They were "LOCAL BANNER"/"FIELD ANSWER"/"SELLSWORD" until
# 2026-08-06; "banner" meant three different things at the time (a faction
# choice, a creature's keyword, and this), so the caption named nothing.
const ROLE_TIPS := {
	"KINGDOM MATCH": "Best match for the kingdom's fighting style.",
	"ALL-ROUND PICK": "A broad recruit for the road ahead.",
	"SECOND MATCH": "A second option suited to this kingdom.",
	"FLEXIBLE PICK": "Less local, often more flexible.",
	"EXTRA CHOICE": "Scout's Emblem added a fourth recruit.",
	"RARE CHOICE": "Stardust Vial added a rare recruit."
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
# Stops cards and the horn from committing after the player has chosen Skip.
var _leaving: bool = false
var _ui_build_generation: int = 0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "reward")
	GameTheme.fade_in(self, 0.22)
	_choices = _roll_offer()
	_assign_choice_roles(_choices)
	# _build_ui reserves the complete slate as face-down cards before it starts
	# any asynchronous art/card work. Loading order is therefore never visible.
	await _build_ui(true)
	GameTheme.make_settings_gear(self)
	# Where cards actually enter a deck, so this is where "your deck grows" is
	# taught — not on the post-fight spoils screen, which hands out relics.
	TutorialCoach.teach(self, "recruit_card", _card_nodes)




## PRESENT ONE FRAME, safely on both paths.
##
## `RenderingServer.frame_post_draw` NEVER FIRES under `--headless` — it parks
## the coroutine forever, and enough parked coroutines segfault the exit. Recruit
## had THREE bare awaits on it and no guard, so any headless probe that booted
## this screen suspended on the first card and never reached the rest of `_ready`
## — including the coaching call at the end of it. `Shop.gd` already branches this
## way at its own stagger site; this is the funnel Recruit was missing.
func _present_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw

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
	# Score whenever anything leans the slate — the kingdom OR the season.
	if (faction == "" and RunState.season_tribes.is_empty()) or slate.size() <= offer_size:
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
		"KINGDOM MATCH",
		"SECOND MATCH",
		"FLEXIBLE PICK",
		"EXTRA CHOICE",
	]
	for i in range(ids.size()):
		var label: String = labels[mini(i, labels.size() - 1)]
		if RunState.get_act_faction() == "" and label == "KINGDOM MATCH":
			label = "ALL-ROUND PICK"
		if RunState.has_relic("stardust_vial") and i == ids.size() - 1:
			label = "RARE CHOICE"
		_choice_roles[ids[i]] = label


func _choice_role_tip(id: String) -> String:
	var role := String(_choice_roles.get(id, "ALL-ROUND PICK"))
	return String(ROLE_TIPS.get(role, "A recruit joining your deck."))


func _affinity(d: Dictionary, faction: String) -> int:
	var s := 0
	# Season winds: the run's dealt tribes lean every muster, in every kingdom.
	# +2 sits between the explicit faction tag (+4) and the terrain accent (+1):
	# the season colors the road without drowning the local banner.
	if RunState.season_tribes.has(String(d.get("ctype", ""))):
		s += 2
	var rules: Dictionary = AFFINITY.get(faction, {})
	if rules.is_empty():
		return s
	var explicit_affinities: Array = d.get("affinities", [])
	if explicit_affinities.has(faction):
		s += 4
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


func _build_ui(stagger_hydration: bool = true) -> void:
	_ui_build_generation += 1
	var build_generation := _ui_build_generation
	var builder_alive := func() -> bool:
		return is_inside_tree() and build_generation == _ui_build_generation
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
	# One centered composition (the Treasure pattern): title, flavor, the
	# three banners, and the walk-away all hang together mid-screen instead
	# of cards floating in a full-height framed void.
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(outer)

	var title = GameTheme.make_screen_title("RECRUIT CAMP",
		GameTheme.GILT_BRIGHT, GameTheme.FONT_HEADER)
	outer.add_child(title)
	GameTheme.deal_in(title, 0.02)

	# The kingdom line sells the conquest fantasy: these are the invaded
	# land's people changing banners, not a shop shelf.
	var faction: String = RunState.get_act_faction()
	var flavor := "Choose one recruit to join your deck. Free."
	if faction != "":
		var fname: String = String(HeroDB.faction_info(faction).get("name", ""))
		if fname != "":
			flavor = "Recruits from %s. Choose one to join your deck." % fname
	var sub = GameTheme.make_label(flavor, GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)
	GameTheme.deal_in(sub, 0.06)

	# Season winds: say WHY the slate leans, so the lean reads as weather,
	# not as a rigged shop.
	var season_text: String = RunState.season_line()
	if season_text != "":
		# Warm bone, not the sage it was (2026-08-05). `g >= r` is the project's
		# cold-ink tell, and on this screen the line rendered as the one cool
		# element over an open-flame backdrop. The 2026-08-03 pass called the
		# muster's copy of this "one of the last two live instances in the
		# opening" and warmed it; this is the same line on the ROAD, outside the
		# opening, and it was missed. Same value the muster's now uses.
		var season = GameTheme.make_label(season_text, GameTheme.FONT_SUBHEADER,
			Color(0.88, 0.83, 0.68))
		season.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(season)
		GameTheme.deal_in(season, 0.09)

	var staged: Array[Dictionary] = []
	if _choices.size() > 0:
		var accent := _muster_accent()
		# Frameless stage — the recruits stand on the scene itself (no cage;
		# the old full-height bordered panel was mostly empty air).
		outer.add_child(_make_spacer(18))
		var card_row = HBoxContainer.new()
		card_row.name = "RecruitCardGroup"
		card_row.set_meta("coordinated_card_group", true)
		card_row.add_theme_constant_override("separation", 34)
		card_row.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(card_row)
		# Reserve the whole centred row as real card backs before any await. Rich
		# faces hydrate behind fixed footprints, so load order cannot resize it.

		for id in _choices:
			var data: Dictionary = CardDB.get_card_data(id)
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 8)
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			slot.tooltip_text = _choice_role_tip(id)
			card_row.add_child(slot)

			var role := String(_choice_roles.get(id, "ALL-ROUND PICK"))
			# 16, the caption band's floor — not 15. This line is the only thing
			# telling the player WHY these three banners are the offer, so it is
			# the second thing they should read, and it was rendering below the
			# size every other caption on every other screen uses. (Audit
			# 2026-07-21.)
			var role_lbl := GameTheme.make_label(role, 16, accent)
			role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			role_lbl.custom_minimum_size = Vector2(210, 0)
			role_lbl.tooltip_text = _choice_role_tip(id)
			slot.add_child(role_lbl)

			var card_wrap := Control.new()
			card_wrap.name = "RecruitCardSlot"
			card_wrap.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H)
			card_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			card_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_wrap.pivot_offset = card_wrap.custom_minimum_size * 0.5
			card_wrap.set_meta("coordinated_card_slot", true)
			# Ground the recruit: a soft pooled contact shadow under the card
			# (children draw over the parent, so the card stands on it).
			card_wrap.draw.connect(_draw_card_shadow.bind(card_wrap))
			slot.add_child(card_wrap)

			var face_host := Control.new()
			face_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_wrap.add_child(face_host)
			face_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var back := _make_loading_card_back(card_row)
			card_wrap.add_child(back)
			back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_card_nodes.append(card_wrap)
			staged.append({
				"id": id, "data": data, "wrap": card_wrap,
				"host": face_host, "back": back,
			})


	# Recruiter's Horn: spend a charge to call up a fresh slate of recruits.
	# Only shown while the relic is held AND charges remain — the button vanishes
	# once the run's pool is spent, so it never dangles as a dead control.
	if _choices.size() > 0 and RunState.has_relic("recruiters_horn") \
			and RunState.muster_rerolls_left > 0:
		var reroll_btn = GameTheme.make_themed_button(
			"Call New Recruits  (%d left)" % RunState.muster_rerolls_left,
			Color(0.20, 0.14, 0.06), Vector2(380, 40), 16)
		reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reroll_btn.tooltip_text = "Recruiter's Horn — replace these three recruits."
		reroll_btn.pressed.connect(_reroll_muster)
		outer.add_child(reroll_btn)
		GameTheme.deal_in(reroll_btn, 0.38)
		GameTheme.hover_lift(reroll_btn, 1.03)

	outer.add_child(_make_spacer(10))
	var leave_btn = GameTheme.make_back_button("Skip", Vector2(200, 42))
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(_on_leave_pressed.bind(leave_btn))
	outer.add_child(leave_btn)
	GameTheme.deal_in(leave_btn, 0.42)
	GameTheme.hover_lift(leave_btn, 1.03)

	if staged.is_empty():
		return
	# Show the complete sleeve row first. Cache warming and ornate face creation
	# remain paced across frames, but every expensive step is hidden behind stable
	# covers instead of being presented as a one-by-one layout mutation.
	await _present_frame()
	if not builder_alive.call():
		return
	await ScenePreload.warm_card_ids(_choices)
	if not builder_alive.call():
		return

	var staged_cards: Array[Control] = []
	var staged_backs: Array[Control] = []
	var staged_rarities: Array[String] = []
	var reduce_motion := UserSettings != null and UserSettings.reduce_motion
	for entry in staged:
		var data: Dictionary = entry["data"]
		var id: String = entry["id"]
		var card_wrap: Control = entry["wrap"]
		var face_host: Control = entry["host"]
		var card = CARD_SCENE.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = id
		card.is_on_battlefield = true
		card.live_baked_mode = true
		card.defer_baked_rules_text = stagger_hydration and not reduce_motion
		card.visible = false
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_recruit_card_input.bind(id, card, card_wrap))
		card.mouse_entered.connect(_on_recruit_card_hover.bind(card_wrap, true))
		card.mouse_exited.connect(_on_recruit_card_hover.bind(card_wrap, false))
		face_host.add_child(card)
		staged_cards.append(card)
		staged_backs.append(entry["back"])
		staged_rarities.append(String(data.get("rarity", "")))
		if stagger_hydration:
			await _present_frame()
			if not builder_alive.call():
				return
			if card.defer_baked_rules_text and is_instance_valid(card):
				card.complete_deferred_baked_rules()
				await _present_frame()
				if not builder_alive.call():
					return

	await _reveal_recruit_group(
		staged_cards, staged_backs, _card_nodes, staged_rarities, builder_alive)


func _make_spacer(h: float) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp


func _draw_card_shadow(card_wrap: Control) -> void:
	# ONE TEXTURED POOL THAT KNOWS THE CARD'S HEIGHT (2026-09-10). This was three
	# stacked `draw_circle` passes "to fake the blur" — the hand-rolled-gradient
	# defect, and worse, a shadow of FIXED size under a card that is now flying in.
	# A contact shadow that does not move while the thing above it does is the one
	# detail that gives away a 2D card as a sprite. `deal_card` writes the height
	# to `deal_lift`; the shadow reads it and spreads, pales and slides away.
	Motion.card_shadow(card_wrap,
		Vector2(Card2D.CARD_W * 0.5, Card2D.CARD_H + 8.0),
		float(card_wrap.get_meta("deal_lift", 0.0)), 96.0,
		card_wrap.get_meta("deal_off", Vector2.ZERO))


func _muster_accent() -> Color:
	var faction := RunState.get_act_faction()
	if faction != "":
		var fac: Dictionary = HeroDB.faction_info(faction)
		if not fac.is_empty():
			var col: Color = fac.get("color", GameTheme.GILT)
			return col.lerp(Color.WHITE, 0.22)
	return GameTheme.GILT


func _animate_card_reveal(card: Control, idx: int, rarity: String = "") -> void:
	# A REAL DEAL (2026-09-10). The three recruits are dealt off to the left, each
	# arcing in and turning face-up as it lands, rather than fading up in place.
	# The stagger ACCELERATES (0.16 → ~0.13 apart) because a dealer speeds up, and
	# the throws alternate side so the slate does not look combed.
	var side: float = -1.0 if idx % 2 == 0 else 1.0
	var at: float = 0.16 + float(idx) * 0.135
	Motion.deal_card(card, at, {
		"from": Vector2(side * 130.0, 340.0),
		"spin": side * 0.44,
		"dur": 0.44,
	})
	# The rarity shine still fires, just timed off the LANDING rather than off a
	# fade that no longer exists — uncommons glint silver, rares erupt in gilt.
	GameTheme.rarity_reveal(card, rarity, at + 0.42)

func _make_loading_card_back(group: CanvasItem = null) -> TextureRect:
	var back := TextureRect.new()
	back.name = "LoadingBack"
	back.texture = CARD_BACK_TEXTURE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, group)
	return back


func _reveal_recruit_group(cards: Array[Control], backs: Array[Control],
		wraps: Array, rarities: Array[String], validity: Callable) -> void:
	# One muster, one reveal: every back closes on the same frame and every ornate
	# face opens from the same edge. Only child transforms animate; the HBox and
	# exact-size wrappers never change geometry.
	if not validity.call():
		return
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not snap:
		if AudioBank != null:
			AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for back in backs:
			Motion.flip_out(back, 0.13)
		await get_tree().create_timer(maxf(Motion.time(0.13), 0.01)).timeout
		if not validity.call():
			return
	for i in range(cards.size()):
		var card: Control = cards[i]
		var back: Control = backs[i] if i < backs.size() else null
		if snap and is_instance_valid(back):
			back.queue_free()
		if is_instance_valid(card):
			card.visible = true
			if not snap:
				Motion.flip_in(card, 0.0, 0.17)
	if not snap:
		for i in range(wraps.size()):
			GameTheme.rarity_reveal(wraps[i], rarities[i], Motion.time(0.12))
		await get_tree().create_timer(maxf(Motion.time(0.17), 0.01)).timeout
		if not validity.call():
			return
	for card in cards:
		if is_instance_valid(card):
			card.mouse_filter = Control.MOUSE_FILTER_STOP



func _on_recruit_card_input(event: InputEvent, id: String,
		card: Control, card_wrap: Control) -> void:
	if _leaving or _rerolling or not _choices.has(id):
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
		_enlist(id, card_wrap)


func _on_recruit_card_hover(card_wrap: Control, hovered: bool) -> void:
	if card_wrap == null or not is_instance_valid(card_wrap) or _leaving or _rerolling:
		return
	card_wrap.z_index = 2 if hovered else 0
	if UserSettings.reduce_motion:
		return
	var target := Vector2(1.045, 1.045) if hovered else Vector2.ONE
	var tw := card_wrap.create_tween()
	tw.tween_property(card_wrap, "scale", target, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# THE SHADOW LIFTS WITH IT. A hover that only scales says "this is bigger";
	# a hover whose shadow spreads and pales at the same time says "this has come
	# OFF THE TABLE", which is the thing the player is actually being told. It is
	# the same height channel the deal uses, so it costs one tweened meta — and
	# it is what makes the scale read as a lift rather than a zoom.
	tw.parallel().tween_method(func(v: float):
			if is_instance_valid(card_wrap):
				card_wrap.set_meta("deal_lift", v)
				card_wrap.queue_redraw(),
		float(card_wrap.get_meta("deal_lift", 0.0)),
		0.30 if hovered else 0.0, 0.10)


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
	if _leaving or _rerolling or _enlist_committing:
		return
	if not RunState.use_muster_reroll():
		return
	_rerolling = true
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Horn blast: gold call-rings + the current recruits scattering away.
	var sweep_duration := GameTheme.reroll_sweep(self, _card_nodes.duplicate(), GameTheme.GILT_BRIGHT)
	# Keep the old cards inert until their sweep has actually cleared the table.
	await get_tree().create_timer(sweep_duration).timeout
	_choices = _roll_offer()
	_assign_choice_roles(_choices)
	await _build_ui(true)
	_rerolling = false


func _enlist(id: String, card_wrap: Control = null) -> void:
	if _leaving or _rerolling or _enlist_committing:
		return
	_enlist_committing = true
	RunState.add_card(id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# The signing beat: take the complete recruit tile (role + card), let the
	# alternatives bow out, then carry the choice into the player's pack. This
	# is the same acquisition grammar as the Shop instead of a timed disappearance.
	if card_wrap != null and is_instance_valid(card_wrap):
		var take_tile: Control = card_wrap.get_parent() as Control
		if take_tile == null:
			take_tile = card_wrap
		GameTheme.claim_pop(take_tile)
		for other in _card_nodes:
			if other != card_wrap and other is Control and is_instance_valid(other):
				var host: Control = other.get_parent() as Control
				if host == null:
					host = other
				GameTheme.fade_exit(host, 0.22)
		if UserSettings == null or not UserSettings.reduce_motion:
			await get_tree().create_timer(0.10).timeout
		await GameTheme.pocket_away(take_tile, _pack_point(), 0.34)
	# Collector's Tome: a second banner may join from the same muster.
	if RunState.has_relic("collectors_tome") and _tome_picks < 1 \
			and _choices.size() > 1:
		_tome_picks += 1
		_choices.erase(id)
		_assign_choice_roles(_choices)
		await _build_ui(true)
		_enlist_committing = false
		return
	_go_to_map()


func _pack_point() -> Vector2:
	# Shared campaign destination: the same off-table pack used by Shop wares.
	var vp := get_viewport_rect().size
	return Vector2(vp.x * 0.5, vp.y + 30.0)


func _on_leave_pressed(btn: Control) -> void:
	if _leaving or _rerolling or _enlist_committing:
		return
	_leaving = true
	if btn != null and is_instance_valid(btn) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(btn)
		await get_tree().create_timer(0.16).timeout
	if not is_inside_tree():
		return
	_go_to_map()


func _go_to_map() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
