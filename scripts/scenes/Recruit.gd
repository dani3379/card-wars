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
	"grasswake": {"kw": ["swift", "ranged", "piercing", "overrun"], "cheap": true},
	"last_wall": {"kw": ["armored", "thorns", "guardian", "shield", "last_stand", "formation"], "adj": true},
	"owed": {"kw": ["sacrifice", "lifelink"], "on_death": true},
	"lanternhall": {"kw": ["echo", "retain", "exhaust"], "spell": true},
	"everflame": {"kw": ["doom", "rampage", "lifelink"], "burn": true},
}

var _choices: Array[String] = []
# Collector's Tome lets the player enlist 2 banners from one muster. Resets
# implicitly on scene unload (a fresh Recruit instance starts at 0).
var _tome_picks: int = 0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "reward")
	_choices = _roll_offer()
	_build_ui()
	GameTheme.make_settings_gear(self)


func _roll_offer() -> Array[String]:
	# The card-offer relics moved here with the draft itself:
	# Busted Crown shrinks the muster to 1, Scout's Emblem widens it to 4,
	# Stardust Vial adds a rare banner on top.
	var offer_size := 3
	if RunState.has_downside("fewer_rewards"):
		offer_size = 1
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
		if rare_pool.size() > 0:
			var picked: String = rare_pool[randi() % rare_pool.size()]
			if not out.has(picked):
				out.append(picked)
	return out


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
	return s


func _build_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
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
	var flavor := "Wanderers seek your banner. Take one into your deck — no charge."
	if faction != "":
		var fname: String = String(HeroDB.faction_info(faction).get("name", ""))
		if fname != "":
			flavor = "Word of your claim spreads through %s. Three banners offer their service — take one, no charge." % fname
	var sub = GameTheme.make_label(flavor, GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)

	if _choices.size() > 0:
		var card_row = HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 30)
		card_row.alignment = BoxContainer.ALIGNMENT_CENTER
		card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(card_row)

		var slot_idx := 0
		for id in _choices:
			var data = CardDB.get_card_data(id)
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 8)
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			card_row.add_child(slot)

			var card = CARD_SCENE.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = id
			card.is_on_battlefield = true
			slot.add_child(card)

			var pick_btn = GameTheme.make_back_button("Enlist", Vector2(120, 36), 16,
				GameTheme.KEYWORD_GOLD)
			pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pick_btn.pressed.connect(_enlist.bind(id))
			slot.add_child(pick_btn)

			_animate_card_reveal(card, pick_btn, slot_idx)
			slot_idx += 1

	var leave_btn = GameTheme.make_back_button("Turn Them Away", Vector2(200, 42))
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(_go_to_map)
	outer.add_child(leave_btn)


func _animate_card_reveal(card: Control, pick_btn: Control, idx: int) -> void:
	# Staggered fan-in, same beat as the Reward screen's reveal.
	card.modulate.a = 0.0
	card.scale = Vector2(0.6, 0.6)
	pick_btn.modulate.a = 0.0
	var delay := 0.18 + float(idx) * 0.16
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.28).set_delay(delay)
	tw.tween_property(card, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	tw.tween_property(pick_btn, "modulate:a", 1.0, 0.24).set_delay(delay + 0.18)


func _enlist(id: String) -> void:
	RunState.add_card(id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Collector's Tome: a second banner may join from the same muster.
	if RunState.has_relic("collectors_tome") and _tome_picks < 1 \
			and _choices.size() > 1:
		_tome_picks += 1
		_choices.erase(id)
		_build_ui()
		return
	_go_to_map()


func _go_to_map() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
