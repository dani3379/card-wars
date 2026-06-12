extends Control
## Wayside.gd — the roadside halts between holds (slice 2 of the road to
## the keep). Four verbs, one per stop, dealt at map gen (node.wayside_id →
## RunState.current_wayside_id):
##   drill_yard      — push-your-luck creature training: +1/+1 per pass
##   muster_scale    — the quartermaster's scales: one trade, by weight
##   standard_bearer — pass one banner keyword from one creature to another
##   supply_cache    — crack the cache open: pick 1 of 3 rolled spoils
## All four are ONE-DECISION stops (the Inscryption cadence: walk in, one
## verb, walk out) — the long-form prose rooms stay in Event.gd. Permanent
## card changes ride the card_upgrades slot via RunState.apply_wayside_upgrade;
## one entry per card is the law, so a drilled creature can't also be forged.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"

# Keywords the Standard-Bearer can lift off one creature and pin on another.
# Deliberately the simple combat banners — anything wired to extra card data
# (Wither N, Doom N, On-Enter/On-Death payloads, Adj. Buff) or that is a COST
# (Sacrifice) stays where it was printed.
const TRANSFERABLE_KW: Array = [
	"swift", "armored", "thorns", "ranged", "piercing", "regenerate",
	"last_stand", "lifelink", "overrun", "formation", "rampage",
	"guardian", "shield",
]

const DRILL_MAX_STACKS: int = 3
const DRILL_FAIL_HP: int = 3

var _verb: String = ""
# Drill Yard state — which deck index is on the yard and how many passes
# it has banked so far (the push-your-luck counter).
var _drill_index: int = -1
var _drill_stacks: int = 0
# Standard-Bearer state — donor index and the keyword being carried.
var _banner_from: int = -1
var _banner_kw: String = ""


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "event")
	AudioBank.play_music("event")
	_verb = RunState.current_wayside_id
	if _verb == "":
		# Legacy node or direct scene open — the cache is the verb that always
		# pays regardless of deck state.
		_verb = "supply_cache"
	_build()
	GameTheme.make_settings_gear(self)


func _build() -> void:
	match _verb:
		"drill_yard":
			_build_drill_intro()
		"muster_scale":
			_build_scales()
		"standard_bearer":
			_build_banner_donor()
		"supply_cache":
			_build_cache()
		_:
			_build_cache()


# ── Shared shell ─────────────────────────────────────────────────────────

func _clear_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()


func _add_header(title_text: String, flavor: String) -> void:
	var title = GameTheme.make_screen_title(title_text,
		GameTheme.GILT_BRIGHT, GameTheme.FONT_TITLE)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 96
	add_child(title)

	var sub = GameTheme.make_label(flavor, GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_left = 280
	sub.offset_right = -280
	sub.offset_top = 104
	sub.offset_bottom = 170
	add_child(sub)


## A parchment tile choice — headline in gold, payload line in ivory. The
## whole panel is the click target; `enabled = false` renders it dimmed with
## the reason it's closed (no dead rewards, but no hidden options either).
func _make_tile(headline: String, payload: String, on_press: Callable,
		enabled: bool = true) -> Button:
	var btn := Button.new()
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(560, 96)
	btn.add_theme_stylebox_override("normal", GameTheme.make_panel_style())
	btn.add_theme_stylebox_override("hover",
		GameTheme.make_panel_style(GameTheme.PARCHMENT, GameTheme.GILT_BRIGHT))
	btn.add_theme_stylebox_override("pressed", GameTheme.make_panel_style())
	btn.add_theme_stylebox_override("disabled", GameTheme.make_panel_style())
	if enabled:
		btn.pressed.connect(on_press)
	else:
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.45)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_right = -20
	vbox.offset_top = 12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var head := GameTheme.make_label(headline, 21, GameTheme.KEYWORD_GOLD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	if payload != "":
		var body := GameTheme.make_label(payload, 15, GameTheme.IVORY)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(520, 0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(body)
	return btn


## Stack tiles down the screen center, below the header band.
func _add_tile_stack(tiles: Array) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	var h: int = tiles.size() * 110
	vbox.offset_left = -290
	vbox.offset_right = 290
	vbox.offset_top = -h / 2 + 40
	vbox.offset_bottom = h / 2 + 40
	add_child(vbox)
	for t in tiles:
		vbox.add_child(t)


func _add_leave_button(label: String = "March on") -> void:
	var btn = GameTheme.make_back_button(label, Vector2(180, 42))
	btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	btn.offset_left = 40
	btn.offset_top = -70
	btn.offset_right = 220
	btn.offset_bottom = -28
	btn.pressed.connect(_go_to_map)
	add_child(btn)


func _go_to_map() -> void:
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


## Automation hook — the full-run probe escapes scenes it doesn't drive by
## calling _leave() when no LEAVE/CONTINUE button matches.
func _leave() -> void:
	_go_to_map()


## Closing beat: what happened, then Continue. Same shape as Event's result
## screen so the road's stops all end on the same breath.
func _show_result(text: String) -> void:
	_clear_ui()
	var lbl := GameTheme.make_label(text, 22, GameTheme.IVORY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -420
	lbl.offset_right = 420
	lbl.offset_top = -120
	lbl.offset_bottom = 40
	add_child(lbl)
	var btn = GameTheme.make_back_button("Continue", Vector2(180, 42), 16,
		GameTheme.KEYWORD_GOLD)
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn.offset_left = -90
	btn.offset_right = 90
	btn.offset_top = -150
	btn.offset_bottom = -108
	btn.pressed.connect(_go_to_map)
	add_child(btn)


# ── Card picker grid (Event.gd's picker, compacted) ─────────────────────

func _make_card_grid(title_text: String) -> GridContainer:
	_clear_ui()
	var title = GameTheme.make_label(title_text, 22, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 30)
	title.size = Vector2(1000, 40)
	add_child(title)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(80, 80)
	scroll.size = Vector2(1440, 660)
	add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	return grid


## Card tile with click overlay; optional footer line under the card (the
## scales print each card's selling price there).
func _add_card_to_grid(grid: GridContainer, data: Dictionary,
		callback: Callable, footer: String = "") -> void:
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 4)
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(210, 280)
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	wrapper.add_child(card_node)
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.pressed.connect(callback)
	wrapper.add_child(click_btn)
	slot.add_child(wrapper)
	if footer != "":
		var f := GameTheme.make_label(footer, 16, GameTheme.KEYWORD_GOLD)
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(f)
	grid.add_child(slot)


# ═══════════════════ DRILL YARD ═══════════════════
# Pick a creature; every completed pass banks +1/+1 (an upgrade-slot entry
# with a stacks counter). After the first free pass, each further pass is a
# coin flip: heads +1/+1 more, tails the yard takes DRILL_FAIL_HP from YOU
# and closes. Stacks already banked always survive — the wager is your
# blood, never the creature's progress.

func _drill_eligible() -> Array:
	var out: Array = []
	for i in range(RunState.deck.size()):
		if RunState.is_card_upgraded(i):
			continue
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "") != "creature":
			continue
		out.append(i)
	return out


func _build_drill_intro() -> void:
	var eligible := _drill_eligible()
	if eligible.is_empty():
		_clear_ui()
		_add_header("THE DRILL YARD",
			"The sergeant looks over your line and finds nothing green enough to teach. He pays you to haul targets for an hour instead.")
		RunState.gain_gold(20)
		_show_drill_consolation()
		return
	var grid = _make_card_grid("The sergeant spits. \"Bring me one. It comes back harder.\" — pick a creature to drill (+1/+1)")
	for i in eligible:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_drill_pick.bind(i))
	_add_leave_button()


func _show_drill_consolation() -> void:
	# Header already painted by the caller; just land the receipt.
	var lbl := GameTheme.make_label("Gained 20 gold.", 22, GameTheme.KEYWORD_GOLD)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -300
	lbl.offset_right = 300
	lbl.offset_top = -20
	lbl.offset_bottom = 30
	add_child(lbl)
	_add_leave_button("Continue")


func _on_drill_pick(deck_index: int) -> void:
	_drill_index = deck_index
	_drill_stacks = 1
	RunState.apply_wayside_upgrade(deck_index,
		{"path": "drill", "stacks": _drill_stacks})
	AudioBank.play_sfx("card_play")
	_build_drill_push()


func _build_drill_push() -> void:
	_clear_ui()
	var data = RunState.get_upgraded_card_data(_drill_index)
	var nm: String = String(data.get("name", "The recruit"))
	_add_header("THE DRILL YARD",
		"%s finishes the pass — +%d/+%d banked so far. The sergeant raises an eyebrow: \"Again?\"" \
		% [nm, _drill_stacks, _drill_stacks])

	# The creature on the yard, current stats showing.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.set_anchors_preset(Control.PRESET_CENTER)
	wrapper.offset_left = -360
	wrapper.offset_right = -135
	wrapper.offset_top = -130
	wrapper.offset_bottom = 170
	var card_node = CARD_SCENE.instantiate()
	card_node.static_display = true
	card_node.card_data = data
	wrapper.add_child(card_node)
	add_child(wrapper)

	var tiles: Array = []
	if _drill_stacks < DRILL_MAX_STACKS:
		tiles.append(_make_tile("Run another pass",
			"Even odds: +1/+1 more — or the yard takes %d HP from you and closes. Banked passes are kept." % DRILL_FAIL_HP,
			_on_drill_again))
	tiles.append(_make_tile("March on",
		"%s keeps +%d/+%d." % [nm, _drill_stacks, _drill_stacks],
		_on_drill_stop))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -40
	vbox.offset_right = 540
	vbox.offset_top = -110
	vbox.offset_bottom = 120
	add_child(vbox)
	for t in tiles:
		vbox.add_child(t)


func _on_drill_again() -> void:
	if randi() % 2 == 0:
		_drill_stacks += 1
		RunState.apply_wayside_upgrade(_drill_index,
			{"path": "drill", "stacks": _drill_stacks})
		AudioBank.play_sfx("card_play")
		if _drill_stacks >= DRILL_MAX_STACKS:
			var data = RunState.get_upgraded_card_data(_drill_index)
			_show_result("The sergeant calls it: nothing more to teach. %s marches off the yard with +%d/+%d." \
				% [String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])
		else:
			_build_drill_push()
	else:
		# Non-lethal: the yard never takes the last drop.
		var to_lose: int = mini(DRILL_FAIL_HP, RunState.hero_hp - 1)
		RunState.damage_hero(maxi(0, to_lose))
		var data = RunState.get_upgraded_card_data(_drill_index)
		_show_result("A training blade finds you instead — you lose %d HP and the sergeant closes the yard. %s keeps +%d/+%d." \
			% [maxi(0, to_lose), String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])


func _on_drill_stop() -> void:
	var data = RunState.get_upgraded_card_data(_drill_index)
	_show_result("%s marches off the yard with +%d/+%d." \
		% [String(data.get("name", "The recruit")), _drill_stacks, _drill_stacks])


# ═══════════════════ MUSTER SCALES ═══════════════════
# The quartermaster weighs, he does not haggle. One trade per visit: sell a
# card by weight (gold scales with its Command cost — removal AND coin in
# one stop), or spend coin on provisions.

const SCALE_POTION_COST: int = 25
const SCALE_MEAL_COST: int = 20
const SCALE_MEAL_HEAL: int = 7


func _sell_price(card_id: String) -> int:
	if CardDB.is_curse(card_id):
		# A curse weighs nothing — but he'll still take it off you for scrap.
		return 5
	var data = CardDB.get_card_data(card_id)
	return 15 + 12 * int(data.get("cost", 0))


func _build_scales() -> void:
	_clear_ui()
	_add_header("THE QUARTERMASTER'S SCALES",
		"A folding table, a balance, a strongbox. He weighs, he does not haggle. One trade per caller — the line behind you is imaginary but he respects it.")
	var tiles: Array = []
	tiles.append(_make_tile("Sell a card by weight",
		"Remove a card from your deck. He pays 15 gold + 12 per Command it costs.",
		_build_scales_sell))
	var can_potion: bool = RunState.gold >= SCALE_POTION_COST and RunState.can_add_potion()
	var potion_note: String = "Pay %d gold. Gain a Healing Potion." % SCALE_POTION_COST
	if not RunState.can_add_potion():
		potion_note = "Your potion belt is full."
	elif RunState.gold < SCALE_POTION_COST:
		potion_note = "You haven't the coin (%d gold)." % SCALE_POTION_COST
	tiles.append(_make_tile("Buy a draught off the back shelf", potion_note,
		_on_scales_potion, can_potion))
	var can_meal: bool = RunState.gold >= SCALE_MEAL_COST \
		and RunState.hero_hp < RunState.hero_max_hp
	var meal_note: String = "Pay %d gold. Heal %d HP." % [SCALE_MEAL_COST, SCALE_MEAL_HEAL]
	if RunState.hero_hp >= RunState.hero_max_hp:
		meal_note = "You're not hungry — not a scratch on you."
	elif RunState.gold < SCALE_MEAL_COST:
		meal_note = "You haven't the coin (%d gold)." % SCALE_MEAL_COST
	tiles.append(_make_tile("A hot meal off the cookfire", meal_note,
		_on_scales_meal, can_meal))
	_add_tile_stack(tiles)
	_add_leave_button()


func _build_scales_sell() -> void:
	var grid = _make_card_grid("Lay one on the pan. He pays by weight.")
	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_scales_sell_pick.bind(i),
			"%d gold" % _sell_price(RunState.deck[i]))
	var back = GameTheme.make_back_button("Keep your pack", Vector2(180, 42))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_top = -70
	back.offset_right = 220
	back.offset_bottom = -28
	back.pressed.connect(_build_scales)
	add_child(back)


func _on_scales_sell_pick(deck_index: int) -> void:
	var card_id: String = RunState.deck[deck_index]
	var data = CardDB.get_card_data(card_id)
	var price := _sell_price(card_id)
	RunState.remove_card_at(deck_index)
	RunState.gain_gold(price)
	AudioBank.play_sfx("button_click")
	_show_result("He sets %s on the pan, reads the needle, and counts out %d gold. He does not say goodbye to it. Neither do you." \
		% [String(data.get("name", "the card")), price])


func _on_scales_potion() -> void:
	RunState.gold -= SCALE_POTION_COST
	RunState.add_potion("healing")
	_show_result("Paid %d gold. The draught is the colour of a bruise and smells worse. It will work." % SCALE_POTION_COST)


func _on_scales_meal() -> void:
	RunState.gold -= SCALE_MEAL_COST
	RunState.heal_hero(SCALE_MEAL_HEAL)
	_show_result("Paid %d gold. Healed %d HP. The stew has been simmering since the last war and is better for it." \
		% [SCALE_MEAL_COST, SCALE_MEAL_HEAL])


# ═══════════════════ THE STANDARD-BEARER ═══════════════════
# An old soldier who carries every banner his dead carried. Pick a creature
# to give up one keyword, then pick the creature who takes it. Both ends
# write the card's one upgrade slot, so the trade is applied atomically at
# the final pick — backing out costs nothing.

func _banner_donors() -> Array:
	var out: Array = []
	for i in range(RunState.deck.size()):
		if RunState.is_card_upgraded(i):
			continue
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "") != "creature":
			continue
		if not _transferable_of(data).is_empty():
			out.append(i)
	return out


func _transferable_of(data: Dictionary) -> Array:
	var out: Array = []
	for kw in data.get("keywords", []):
		if TRANSFERABLE_KW.has(kw):
			out.append(kw)
	return out


func _banner_receivers(donor_index: int, kw: String) -> Array:
	var out: Array = []
	for i in range(RunState.deck.size()):
		if i == donor_index or RunState.is_card_upgraded(i):
			continue
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "") != "creature":
			continue
		if data.get("keywords", []).has(kw):
			continue
		out.append(i)
	return out


func _build_banner_donor() -> void:
	var donors := _banner_donors()
	# A donor only counts if SOMEONE can take its banner.
	var valid: Array = []
	for i in donors:
		var data = CardDB.get_card_data(RunState.deck[i])
		for kw in _transferable_of(data):
			if not _banner_receivers(i, kw).is_empty():
				valid.append(i)
				break
	if valid.is_empty():
		_clear_ui()
		_add_header("THE STANDARD-BEARER",
			"He reads your line twice and shakes his head — no banner here can change hands. He shares the road's news and a coin for your trouble.")
		RunState.gain_gold(15)
		var lbl := GameTheme.make_label("Gained 15 gold.", 22, GameTheme.KEYWORD_GOLD)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		lbl.offset_left = -300
		lbl.offset_right = 300
		lbl.offset_top = -20
		lbl.offset_bottom = 30
		add_child(lbl)
		_add_leave_button("Continue")
		return
	var grid = _make_card_grid("\"Every banner I carry was carried first.\" — choose who GIVES UP a keyword")
	for i in valid:
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_banner_donor_pick.bind(i))
	_add_leave_button()


func _on_banner_donor_pick(deck_index: int) -> void:
	_banner_from = deck_index
	var data = CardDB.get_card_data(RunState.deck[deck_index])
	# Only offer keywords that have at least one valid receiver.
	var options: Array = []
	for kw in _transferable_of(data):
		if not _banner_receivers(deck_index, kw).is_empty():
			options.append(kw)
	if options.size() == 1:
		_banner_kw = options[0]
		_build_banner_receiver()
		return
	_clear_ui()
	_add_header("THE STANDARD-BEARER",
		"%s carries more than one banner. Which one passes on?" % String(data.get("name", "The creature")))
	var tiles: Array = []
	for kw in options:
		var info: Dictionary = KeywordEffects.KEYWORDS.get(kw, {})
		tiles.append(_make_tile(String(info.get("display", kw)),
			String(info.get("desc", "")), _on_banner_kw_pick.bind(kw)))
	_add_tile_stack(tiles)
	_add_leave_button()


func _on_banner_kw_pick(kw: String) -> void:
	_banner_kw = kw
	_build_banner_receiver()


func _build_banner_receiver() -> void:
	var info: Dictionary = KeywordEffects.KEYWORDS.get(_banner_kw, {})
	var disp: String = String(info.get("display", _banner_kw))
	var donor = CardDB.get_card_data(RunState.deck[_banner_from])
	var grid = _make_card_grid("%s gives up %s — choose who takes it up" \
		% [String(donor.get("name", "The creature")), disp])
	for i in _banner_receivers(_banner_from, _banner_kw):
		var data = RunState.get_upgraded_card_data(i)
		_add_card_to_grid(grid, data, _on_banner_receiver_pick.bind(i))
	var back = GameTheme.make_back_button("Choose another", Vector2(200, 42))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_top = -70
	back.offset_right = 240
	back.offset_bottom = -28
	back.pressed.connect(_build_banner_donor)
	add_child(back)


func _on_banner_receiver_pick(deck_index: int) -> void:
	var info: Dictionary = KeywordEffects.KEYWORDS.get(_banner_kw, {})
	var disp: String = String(info.get("display", _banner_kw))
	var donor = CardDB.get_card_data(RunState.deck[_banner_from])
	var taker = CardDB.get_card_data(RunState.deck[deck_index])
	# Atomic: both halves land only now, after the full trade is chosen.
	RunState.apply_wayside_upgrade(_banner_from,
		{"path": "strip_kw", "keyword": _banner_kw})
	RunState.apply_wayside_upgrade(deck_index,
		{"path": "grant_kw", "keyword": _banner_kw})
	AudioBank.play_sfx("card_play")
	_show_result("The bearer lifts %s from %s and pins it to %s. \"Carried well,\" he says, to one of them." \
		% [disp, String(donor.get("name", "the giver")),
			String(taker.get("name", "the taker"))])


# ═══════════════════ SUPPLY CACHE ═══════════════════
# A buried strongpoint from a war nobody finished. Three spoils surface,
# you carry one away. Dead rewards are filtered before the roll (no rations
# at full HP, no draught with a full belt) per the no-dead-rewards rule.

func _build_cache() -> void:
	_clear_ui()
	_add_header("THE SUPPLY CACHE",
		"A tarred chest under a cairn of stones — provisions laid down for a column that never came back. You can carry one thing away.")
	var pool: Array = [
		{"id": "purse", "head": "A buried pay-chest", "note": "Gain 45 gold."},
		{"id": "levy", "head": "A levy's kit",
			"note": "Next fight starts with a 2/4 Levy Spearman in your front line."},
		{"id": "dispatches", "head": "A captain's dispatches",
			"note": "+1 max Command next fight."},
		{"id": "banner_case", "head": "A banner case",
			"note": "Add a random common card to your deck."},
	]
	# No dead rewards: situational spoils only enter the roll when usable.
	if RunState.can_add_potion():
		pool.append({"id": "draught", "head": "A healer's draught",
			"note": "Gain a Healing Potion."})
	if RunState.hero_hp < RunState.hero_max_hp:
		pool.append({"id": "rations", "head": "Field rations", "note": "Heal 8 HP."})
	pool.shuffle()
	var offered: Array = pool.slice(0, mini(3, pool.size()))
	var tiles: Array = []
	for spoil in offered:
		tiles.append(_make_tile(String(spoil.head), String(spoil.note),
			_on_cache_take.bind(String(spoil.id))))
	_add_tile_stack(tiles)
	_add_leave_button("Leave it buried")


func _on_cache_take(id: String) -> void:
	AudioBank.play_sfx("button_click")
	match id:
		"purse":
			RunState.gain_gold(45)
			_show_result("The coins are old enough that both kings on them are forgotten. Gained 45 gold.")
		"draught":
			RunState.add_potion("healing")
			_show_result("The wax seal is unbroken. Gained a Healing Potion.")
		"rations":
			RunState.heal_hero(8)
			_show_result("Hard bread, harder cheese, and someone's hoarded wine. Healed 8 HP.")
		"levy":
			RunState.next_combat_gift_creature = {
				"name": "Levy Spearman", "atk": 2, "hp": 4, "kw": [],
			}
			_show_result("Helmet, spear, and a name scratched off the tag. Someone will wear it into the next fight.")
		"dispatches":
			RunState.next_combat_mana_bonus += 1
			_show_result("Orders, maps, and a captain's neat cold handwriting. +1 max Command next fight.")
		"banner_case":
			var pool_c = CardDB.cards_of_rarity("common")
			if pool_c.is_empty():
				_show_result("The case is empty. The moths apologize.")
				return
			pool_c.shuffle()
			RunState.add_card(pool_c[0])
			_show_result("Inside, wrapped in oilcloth: %s joins your deck." \
				% CardDB.get_card_data(pool_c[0]).name)
