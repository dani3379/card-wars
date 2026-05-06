extends Control
## Rest.gd — Rest node. Choose: heal to full HP, upgrade a card, or remove a card.
## Card upgrade paths: Sharpen (+2 ATK/+2 spell dmg), Fortify (+2 HP/-1 cost),
## Imbue (add keyword or double+exhaust for spells).

const MAP_SCENE = "res://scenes/map.tscn"

enum Mode { CHOOSE, PICK_CARD, PICK_UPGRADE }

var _mode: int = Mode.CHOOSE
var _selected_card_index: int = -1


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	_build_choice_ui()


func _build_choice_ui() -> void:
	_mode = Mode.CHOOSE
	_clear_ui()

	var title = Label.new()
	title.text = "REST SITE"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(600, 40)
	title.size = Vector2(400, 45)
	add_child(title)

	var subtitle = Label.new()
	subtitle.text = "♥ %d / %d" % [RunState.hero_hp, RunState.hero_max_hp]
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(650, 85)
	subtitle.size = Vector2(300, 30)
	add_child(subtitle)

	var row = HBoxContainer.new()
	row.position = Vector2(300, 200)
	row.add_theme_constant_override("separation", 40)
	add_child(row)

	# Heal
	var heal_btn = _make_btn("♨ REST\n\nHeal to full HP\n(%d → %d)" % [
		RunState.hero_hp, RunState.hero_max_hp],
		Color(0.15, 0.40, 0.20), Vector2(250, 200))
	heal_btn.disabled = RunState.hero_hp >= RunState.hero_max_hp
	heal_btn.pressed.connect(_do_heal)
	row.add_child(heal_btn)

	# Upgrade
	var upgrade_btn = _make_btn("⚒ UPGRADE\n\nUpgrade one card\nSharpen / Fortify / Imbue",
		Color(0.40, 0.25, 0.15), Vector2(250, 200))
	var has_upgradeable = false
	for i in range(RunState.deck.size()):
		if not RunState.is_card_upgraded(i):
			has_upgradeable = true
			break
	upgrade_btn.disabled = not has_upgradeable
	upgrade_btn.pressed.connect(_start_upgrade_mode)
	row.add_child(upgrade_btn)

	# Remove
	var remove_btn = _make_btn("✕ REMOVE\n\nRemove one card\nfrom your deck",
		Color(0.45, 0.15, 0.15), Vector2(250, 200))
	remove_btn.disabled = RunState.deck.size() <= 1
	remove_btn.pressed.connect(_start_remove_mode)
	row.add_child(remove_btn)


func _do_heal() -> void:
	RunState.hero_hp = RunState.hero_max_hp
	get_tree().change_scene_to_file(MAP_SCENE)


func _start_upgrade_mode() -> void:
	_mode = Mode.PICK_CARD
	_clear_ui()

	var title = Label.new()
	title.text = "Choose a card to upgrade"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(100, 80)
	scroll.size = Vector2(1400, 680)
	add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for i in range(RunState.deck.size()):
		if RunState.is_card_upgraded(i):
			continue
		var data = CardDB.get_card_data(RunState.deck[i])
		var text: String
		if data.get("type", "creature") == "spell":
			text = "%s\n%dm SPELL\n%s" % [data.name, data.cost, _kw(data)]
		else:
			text = "%s\n%dm %d/%d\n%s" % [data.name, data.cost, data.atk, data.hp, _kw(data)]
		var color = Color(0.15, 0.12, 0.30) if data.type == "spell" else Color(0.20, 0.25, 0.35)
		var btn = _make_btn(text, data.desc, color, Vector2(150, 110))
		btn.pressed.connect(_select_card_for_upgrade.bind(i))
		grid.add_child(btn)

	_add_cancel_btn()


func _select_card_for_upgrade(deck_index: int) -> void:
	_selected_card_index = deck_index
	_mode = Mode.PICK_UPGRADE
	_clear_ui()

	var data = CardDB.get_card_data(RunState.deck[deck_index])
	var title = Label.new()
	title.text = "Upgrade: %s" % data.name
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 40)
	title.size = Vector2(600, 40)
	add_child(title)

	var bonus = 3 if RunState.has_relic("blacksmiths_hammer") else 2
	var row = HBoxContainer.new()
	row.position = Vector2(200, 150)
	row.add_theme_constant_override("separation", 40)
	add_child(row)

	# Sharpen
	var sharpen_desc: String
	if data.type == "creature":
		sharpen_desc = "SHARPEN\n\n+%d ATK\n%d/%d → %d/%d" % [
			bonus, data.atk, data.hp, data.atk + bonus, data.hp]
	else:
		var val = data.get("spell", {}).get("value", 0)
		sharpen_desc = "SHARPEN\n\n+%d to damage\n%d → %d" % [bonus, val, val + bonus]
	var sharpen_btn = _make_btn(sharpen_desc, Color(0.55, 0.20, 0.15), Vector2(280, 200))
	sharpen_btn.pressed.connect(_do_upgrade.bind("sharpen"))
	row.add_child(sharpen_btn)

	# Fortify
	var fortify_desc: String
	if data.type == "creature":
		fortify_desc = "FORTIFY\n\n+%d HP\n%d/%d → %d/%d" % [
			bonus, data.atk, data.hp, data.atk, data.hp + bonus]
	else:
		var new_cost = maxi(0, data.cost - 1)
		fortify_desc = "FORTIFY\n\n-1 mana cost\n%dm → %dm" % [data.cost, new_cost]
	var fortify_btn = _make_btn(fortify_desc, Color(0.15, 0.25, 0.55), Vector2(280, 200))
	fortify_btn.pressed.connect(_do_upgrade.bind("fortify"))
	row.add_child(fortify_btn)

	# Imbue
	var imbue_desc: String
	var imbue_keyword := ""
	if data.type == "creature":
		var options = _roll_imbue_keywords(data)
		if options.size() > 0:
			imbue_keyword = options[0]
			var choices_text = "\n".join(options)
			imbue_desc = "IMBUE\n\nAdd keyword:\n%s" % choices_text
		else:
			imbue_desc = "IMBUE\n\n(no keywords\navailable)"
	else:
		imbue_desc = "IMBUE\n\nAdd Retain\nOR double effect\n+ Exhaust"
		imbue_keyword = "retain"

	if data.type == "creature" and _roll_imbue_keywords(data).size() > 0:
		var options = _roll_imbue_keywords(data)
		_build_imbue_choices(options, row)
	elif data.type == "spell":
		_build_spell_imbue_choices(row)
	else:
		var imbue_btn = _make_btn(imbue_desc, Color(0.35, 0.15, 0.50), Vector2(280, 200))
		imbue_btn.disabled = true
		row.add_child(imbue_btn)

	_add_cancel_btn()


func _build_imbue_choices(options: Array, parent: HBoxContainer) -> void:
	for kw in options:
		var display = KeywordEffects.KEYWORDS.get(kw, {}).get("display", kw)
		var desc_text = KeywordEffects.tooltip_for(kw)
		var btn = _make_btn("IMBUE\n\n+ %s\n%s" % [display, desc_text],
			Color(0.35, 0.15, 0.50), Vector2(220, 200))
		btn.pressed.connect(_do_upgrade.bind("imbue", kw))
		parent.add_child(btn)


func _build_spell_imbue_choices(parent: HBoxContainer) -> void:
	var retain_btn = _make_btn("IMBUE\n\n+ Retain\nKeep in hand",
		Color(0.35, 0.15, 0.50), Vector2(220, 200))
	retain_btn.pressed.connect(_do_upgrade.bind("imbue", "retain"))
	parent.add_child(retain_btn)

	var double_btn = _make_btn("IMBUE\n\nDouble effect\n+ Exhaust",
		Color(0.50, 0.15, 0.40), Vector2(220, 200))
	double_btn.pressed.connect(_do_upgrade.bind("imbue", "double_exhaust"))
	parent.add_child(double_btn)


func _roll_imbue_keywords(data: Dictionary) -> Array:
	var possible = ["piercing", "swift", "thorns", "regenerate"]
	var existing = data.get("keywords", [])
	var available: Array = []
	for kw in possible:
		if not existing.has(kw):
			available.append(kw)
	available.shuffle()
	var count = 3 if RunState.has_relic("blacksmiths_hammer") else 2
	return available.slice(0, mini(count, available.size()))


func _do_upgrade(path: String, keyword: String = "") -> void:
	if _selected_card_index < 0:
		return
	RunState.upgrade_card(_selected_card_index, path, keyword)
	get_tree().change_scene_to_file(MAP_SCENE)


func _start_remove_mode() -> void:
	_clear_ui()

	var title = Label.new()
	title.text = "Choose a card to remove"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(100, 80)
	scroll.size = Vector2(1400, 680)
	add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		var text: String
		if data.get("type", "creature") == "spell":
			text = "%s\n%dm SPELL" % [data.name, data.cost]
		else:
			text = "%s\n%dm %d/%d" % [data.name, data.cost, data.atk, data.hp]
		var color = Color(0.15, 0.12, 0.30) if data.type == "spell" else Color(0.20, 0.25, 0.35)
		var btn = _make_btn(text, data.desc, color, Vector2(150, 90))
		btn.pressed.connect(func():
			RunState.remove_card_at(i)
			get_tree().change_scene_to_file(MAP_SCENE)
		)
		grid.add_child(btn)

	_add_cancel_btn()


func _kw(data: Dictionary) -> String:
	if not data.has("keywords") or data.keywords.is_empty():
		return ""
	return ", ".join(data.keywords)


func _make_btn(text: String, color: Color, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = min_size
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.bg_color = color
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn


func _add_cancel_btn() -> void:
	var btn = Button.new()
	btn.text = "Cancel"
	btn.custom_minimum_size = Vector2(120, 36)
	btn.position = Vector2(740, 810)
	btn.pressed.connect(func(): _build_choice_ui())
	add_child(btn)


func _clear_ui() -> void:
	for child in get_children():
		if child.name != "Background":
			child.queue_free()
