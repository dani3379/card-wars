extends Control
## Reward.gd — the post-victory SPOILS screen. EVERY fight comes here: the slate
## offers a card (restored 2026-09-20, see `_card_choices`), elites add a relic
## pick and the General's Forge, bosses add a boss relic and the act transition.
## Recruit stops still exist and still draft — this is additive to them.
## Fully programmatic UI, and it does NOT scroll: anything added here has to fit
## 900px, or it pushes Continue off the bottom of the canvas.

const MAP_SCENE = "res://scenes/map.tscn"
const COMBAT_SCENE = "res://scenes/combat.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const CAMPAIGN_STANDARD = preload("res://scripts/ui/painters/CampaignStandard.gd")
const ACT_VICTORY_STRIP = preload("res://scripts/ui/painters/ActVictoryStrip.gd")

# The spoils sheet's own inks. PARCHMENT is the SHOP-SHELF ink and is
# deliberately not used on the spoil tiles — a prize lit the same as a
# merchant's stock is the whole reason this screen read quieter than the
# roadside Reliquary. See _spoil_style.
const SPOIL_FILL := Color(0.155, 0.115, 0.078, 0.96)
const SPOIL_EMBER := Color(1.0, 0.56, 0.20)
# The painting, not the box, is the prize. Two of these out-weigh the single
# find on the Treasure screen, which is the order the road should present them
# in: a General's death pays better than a hole in the ground.
const SPOIL_ICON_PX := 160
const SPOIL_TILE_W := 340.0
## How large a card is drawn on the spoils slate. Below Recruit's full-size face
## because this screen also carries a title, sometimes a relic row, and a
## Continue — and it does not scroll.
const CARD_OFFER_SCALE := 0.78

## THE CARD REWARD, RESTORED 2026-09-20 (owner: "it was supposed to give you a
## card... just put it in").
##
## It was removed on 2026-06-10 by `2e53313` — "Successor Wars slice: recruit
## camps + fights pay ground, not cards" — which moved deck growth onto the new
## `recruit` nodes and had ordinary holds "pay gold inline and return straight to
## the map — no card pick, no interstitial. Pace is the point."
##
## MEASURED CONSEQUENCE (2026-09-20, 77 map stops over 8 pilot runs): a muster is
## offered at 14% of stops and a wagon at 4%, so deck growth ran **+1 to +2 cards
## per run** against a 10-card hero opener, and two runs finished SMALLER than
## they started because Event.gd's card-removal paths outpaced the trickle. The
## ceiling for a complete three-act run, taking every offer, was about 18 cards;
## Slay the Spire offers one after each of ~16 combats and finishes at 25-35.
##
## The recruit camps stay — this is additive. Gold is NOT reduced to pay for it
## (owner: "no compensation"), so fights are worth strictly more than they were.
var _card_choices: Array[String] = []
var _card_taken: bool = false
## Collector's Tome enlists a second card. Ported back with the rest of the
## card-offer relic table, which `2e53313` had moved onto the muster.
var _collectors_tome_picks: int = 0

var _relic_choices: Array[String] = []
var _is_elite_reward: bool = false
# The General's Forge (2026-07-06 progression pass): every fallen General
# lets the player temper ONE card — a chosen "+" forge, same path as the
# rest site. Elite risk pays deck power, not just relic luck. (Olympian's
# Mark still upgrades a random extra card on top — additive, still honest.)
var _relic_taken: bool = false
var _forge_done: bool = false
var _forge_card_nodes: Array[Control] = []
var _forge_picking: bool = false
var _march_picking: bool = false
var _spoil_claiming: bool = false
# The screen may remain visible while the ink wipe runs. Keep its exit path
# one-shot so a rapid Continue/Enter cannot advance the campaign twice.
var _leaving: bool = false
var _transition_started: bool = false
var _company_standard_anchor: Control = null
var _ui_generation: int = 0
var _forge_warm_busy: bool = false
var _forge_halo_texture: GradientTexture2D = null


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	# Lift the crushed vignette/gradient so the painted spoils art reads behind
	# the document tiles (the base "reward" mood crushes it near black).
	GameTheme.add_atmosphere(self, "reward", true, {
		"vignette": 0.30,
		"grad_outer": Color(0.03, 0.02, 0.02, 0.42),
	})
	# Reward continues whatever combat music faded out; if no track is loaded,
	# the map track keeps quiet — no separate "reward" music asset needed.
	var node_type = RunState.current_node_type
	_is_elite_reward = (node_type == "elite" or node_type == "boss")
	var is_boss = (node_type == "boss")

	# THE CARD OFFER. Rolled for every fight type — a plain hold pays a card too,
	# which is the whole point of putting this back. The relic table below is the
	# one `2e53313` carried over to the muster; both screens can read it, and
	# RelicDB is the authority for what each one is worth.
	var reward_count := 3
	if RunState.has_downside("fewer_rewards"):
		reward_count = 1                      # Busted Crown
	elif RunState.has_relic("scouts_emblem"):
		reward_count = 4
	_card_choices = CardDB.roll_card_reward(
		RunState.get_act(), node_type == "elite", is_boss, reward_count)
	if _card_choices.size() > reward_count:
		_card_choices = _card_choices.slice(0, reward_count)
	# Stardust Vial: one extra rare on a non-boss screen (a boss already rolls
	# rares, so adding one there would be paying the relic twice).
	if not is_boss and RunState.has_relic("stardust_vial"):
		var rare_pool: Array[String] = CardDB.get_pool_by_rarity("rare")
		if rare_pool.size() > 0:
			var picked: String = rare_pool[randi() % rare_pool.size()]
			if not _card_choices.has(picked):
				_card_choices.append(picked)

	if is_boss:
		_relic_choices = RelicDB.roll_boss_relics(RunState.relics, RunState.current_hero_id)
	elif _is_elite_reward:
		_relic_choices = RelicDB.roll_field_relics(2, RunState.relics,
			RunState.current_hero_id)

	# Olympian's Mark: after every General falls, upgrade one random unforged
	# creature/spell in the deck for free. Applies the same "+" upgrade the
	# rest-site offers, so the relic stays in lockstep with the player-driven
	# forge path instead of carving out a parallel buff.
	if node_type == "elite" and RunState.has_relic("olympians_mark"):
		var candidates: Array[int] = []
		for i in RunState.deck.size():
			if not RunState.has_upgrade_path(i, "plus"):
				var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
				if d.get("type", "") in ["creature", "spell", "armament"] \
						and CardDB.is_upgradeable(RunState.deck[i]):
					candidates.append(i)
		if candidates.size() > 0:
			RunState.upgrade_card(candidates[randi() % candidates.size()], "plus")

	_build_ui()
	GameTheme.fade_in(self, 0.22)
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay instead of skipping the reward on a
	# stray keypress — the "Continue" button is the deliberate way past it.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_ui_generation += 1
	var ui_generation := _ui_generation
	_forge_card_nodes.clear()
	_forge_picking = false
	_spoil_claiming = false
	_company_standard_anchor = null
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	# Center the spoils as one group. The relic row used to be EXPAND_FILL, which
	# soaked all the vertical space and left the tiles floating mid-screen with a
	# long gap down to Continue; now the whole stack sits centered and balanced.
	var outer := VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 26)
	margin.add_child(outer)

	# The spoils belong to the company, not a detached menu. Its standard carries
	# completed-march seals, General ribbons, and mourning cloth into this scene;
	# the chosen relic physically flies back to it below.
	var is_boss := RunState.current_node_type == "boss"
	var faction_id: String = RunState.get_act_faction()
	var faction_info: Dictionary = HeroDB.faction_info(faction_id) \
		if faction_id != "" else {}
	var route_color: Color = _heraldry_ink(
		faction_info.get("color", GameTheme.GILT_BRIGHT))
	var hero_faction: String = HeroDB.get_faction(RunState.current_hero_id)
	var hero_info: Dictionary = HeroDB.faction_info(hero_faction)
	var standard_color: Color = _heraldry_ink(
		hero_info.get("color", GameTheme.GILT_BRIGHT))
	var ceremony_row := HBoxContainer.new()
	ceremony_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ceremony_row.add_theme_constant_override("separation", 18)
	outer.add_child(ceremony_row)

	var standard = CAMPAIGN_STANDARD.new()
	standard.name = "CompanyStandard"
	var completed_acts: int = RunState.current_act_idx + (1 if is_boss else 0)
	standard.configure(completed_acts, RunState.generals_broken_run,
		RunState.fallen.size(), standard_color)
	ceremony_row.add_child(standard)
	_company_standard_anchor = standard
	GameTheme.deal_in(standard, 0.02)

	var title_stack := VBoxContainer.new()
	title_stack.custom_minimum_size = Vector2(790, 0)
	title_stack.add_theme_constant_override("separation", 5)
	ceremony_row.add_child(title_stack)
	var march_names := ["FIRST", "SECOND", "LAST"]
	var title_text := "GENERAL DEFEATED  /  PROVINCE %d" % RunState.current_floor
	if is_boss:
		title_text = "THE %s MARCH  /  KEEP TAKEN" % \
			march_names[clampi(RunState.current_act_idx, 0, 2)]
	var title = GameTheme.make_screen_title(title_text, GameTheme.GILT_BRIGHT,
		GameTheme.FONT_TITLE if not is_boss else GameTheme.FONT_HEADER)
	title_stack.add_child(title)
	GameTheme.deal_in(title, 0.03)

	var subtitle_text := "Take one Combat relic. Then forge one card."
	if is_boss:
		var kingdom: String = String(faction_info.get("name", "The rival kingdom"))
		subtitle_text = "%s is broken.  %d holds  |  %d Generals  |  %d fallen  |  HP %d/%d" % [
			kingdom, RunState.holds_broken_in_act,
			_count_visited_current_act("elite"), RunState.fallen.size(),
			RunState.hero_hp, RunState.hero_max_hp]
	var subtitle := GameTheme.make_label(subtitle_text, 17, GameTheme.DESC_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_stack.add_child(subtitle)
	GameTheme.deal_in(subtitle, 0.08)

	# ── BALANCE THE STANDARD (2026-09-03) ──
	# `ceremony_row` is centred and holds [standard][title_stack], so centring the
	# ROW pushes the TEXT right by the standard's whole width plus the separation.
	# Measured off the render: the divider, both relic tiles and Continue all
	# centre on 800, while this screen's headline and its subtitle centred on
	# 897.5 — the one line the player reads first was the only thing on the
	# screen off its axis.
	# A mirroring spacer puts the stack back on the true centre and leaves the
	# standard where it is. Its width is READ FROM THE STANDARD rather than typed,
	# so the two cannot drift apart if the painter is ever resized.
	var standard_mirror := Control.new()
	standard_mirror.custom_minimum_size = Vector2(standard.custom_minimum_size.x, 0)
	standard_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ceremony_row.add_child(standard_mirror)

	# Boss rewards retain the conquered route long enough to read it. The line
	# inks itself from camp to the lord's seal before the next map is dealt.
	if is_boss:
		var route = ACT_VICTORY_STRIP.new()
		route.name = "ActVictoryRoute"
		route.configure(RunState.get_current_act_map(), route_color)
		route.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		outer.add_child(route)

	# THE CARD OFFER — first, because it is the reward every fight now pays and
	# the relic/forge rows below belong to Generals only.
	if _card_choices.size() > 0 and not _card_taken:
		var card_header := _make_section_header("Add a Card to Your Deck")
		outer.add_child(card_header)
		GameTheme.deal_in(card_header, 0.06)

		var card_row := HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 30)
		card_row.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(card_row)

		var card_i := 0
		for id in _card_choices:
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 8)
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			# Shrink-center for the same reason the relic tiles carry it: an
			# HBox child stretches by default, which renders a card as a
			# full-height column with the face floating in the middle of it.
			slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			card_row.add_child(slot)

			# A SCALED CONTROL STILL RESERVES ITS FULL SIZE, so the card goes in
			# a wrapper whose minimum size is the SCALED footprint. Without the
			# wrapper the row claims 300px of column for a card drawn at 225,
			# and the screen does not scroll — measured: Continue at y=996 on a
			# 900-tall canvas. `Recruit` can afford the full 225x300 because its
			# whole screen is the slate; this one also carries a title, a relic
			# row and a Continue.
			var wrap := Control.new()
			wrap.custom_minimum_size = Vector2(
				Card2D.CARD_W * CARD_OFFER_SCALE, Card2D.CARD_H * CARD_OFFER_SCALE)
			wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(wrap)

			var card := CARD_SCENE.instantiate()
			card.scale = Vector2(CARD_OFFER_SCALE, CARD_OFFER_SCALE)
			card.card_data = CardDB.get_card_data(id).duplicate(true)
			card.card_id = id
			# THE COMPACT TOKEN, NOT THE FULL WRIT, and this is load-bearing.
			# `Reward`'s `outer` is a plain VBox in a margin — there is NO scroll
			# — so anything that overflows goes off the bottom of the canvas.
			# Built with the full face first, and the pilot measured the result
			# immediately: the Continue button landed at y=1158 on a 900-tall
			# canvas and was reported unreachable 46 times in one run. Both the
			# pre-2026-06-10 code here and `Recruit._build_slate` use the compact
			# face for exactly this reason; the hover lift below is how the house
			# lets a player look closer.
			card.is_on_battlefield = true
			wrap.add_child(card)

			# "PICK" / "SKIP", NOT "TAKE" / "TAKE NONE". Labelled the obvious way
			# first and the pilot immediately mis-sorted the screen: "TAKE" is in
			# its ADVANCE vocabulary, so the offer AND the decline both read as
			# "leave this screen" and it pressed whichever won tree order. That
			# is the same trap Treasure's "Take 3 Gold instead" is documented
			# for. The pre-2026-06-10 code used these two words; they are also
			# what Recruit uses, so the shell stays consistent.
			var pick_btn := GameTheme.make_back_button("Pick", Vector2(130, 38),
				16, GameTheme.KEYWORD_GOLD)
			pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pick_btn.pressed.connect(_pick_card.bind(id, slot))
			slot.add_child(pick_btn)

			# Same entrance grammar as the spoil tiles beside it: cards are
			# DEALT (they travel and turn over), relics are SET DOWN.
			GameTheme.deal_in(slot, 0.10 + card_i * 0.07)
			GameTheme.rarity_reveal(card,
				String(CardDB.get_card_data(id).get("rarity", "common")),
				0.10 + card_i * 0.07 + 0.30)
			GameTheme.hover_lift(pick_btn, 1.04, slot)
			card_i += 1

		# Declining is free. The pre-2026-06-10 screen paid 20 gold to skip;
		# that is a separate lever and re-adding it here would be the
		# compensation this change was explicitly told not to make.
		var skip_btn := GameTheme.make_back_button("Skip", Vector2(170, 40))
		skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		skip_btn.pressed.connect(_skip_card)
		outer.add_child(skip_btn)
		GameTheme.deal_in(skip_btn, 0.34)

	# ONE OFFER AT A TIME. A General's screen carries a card slate, two relic
	# tiles (304px each) AND the forge; all three at once does not fit 900px —
	# measured, it pushed Continue to y=1158. The screen already rebuilds after
	# every pick (`_after_spoil_taken`), so the rows queue behind the card
	# instead of stacking with it.
	var card_pending_now: bool = _card_choices.size() > 0 and not _card_taken
	# Relic choices
	if not card_pending_now and _is_elite_reward \
			and _relic_choices.size() > 0 and not _relic_taken:
		# Ruled cartouche subheader (matches Treasure / Event / Recruit).
		var relic_header := _make_section_header("Choose a Relic")
		outer.add_child(relic_header)
		GameTheme.deal_in(relic_header, 0.08)

		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 40)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(relic_row)

		var spoil_tiles: Array[Button] = []
		var relic_i := 0
		for id in _relic_choices:
			var btn := _make_spoil_tile(id)
			# Shrink-center: the row owns the freed vertical space now that
			# the card rack is gone, and HBox children stretch by default —
			# without this the relic panels render as full-height columns.
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.pressed.connect(_pick_relic.bind(id, btn))
			relic_row.add_child(btn)
			spoil_tiles.append(btn)
			var deal_at := 0.10 + relic_i * 0.08
			# SET DOWN, NOT FADED IN (2026-09-10). Spoils are objects: they drop
			# onto the table in front of you and land with weight. `deal_in` grew
			# them from 92% while fading up, which is the motion of a dialog box —
			# and alpha and scale are the two properties an object never changes.
			Motion.drop_item(btn, deal_at)
			# The shine is the pull's own announcement (commons no-op by design).
			# It waits out the drop rather than racing it — it drives `modulate`,
			# and overlapping the two made the rare kiss fight the old entrance
			# fade. The drop no longer touches alpha, but the shine still wants to
			# land on a tile that has stopped moving.
			GameTheme.rarity_reveal(btn, RelicDB.get_relic_rarity(id),
				deal_at + 0.34)
			GameTheme.hover_lift(btn)
			relic_i += 1
		# One offer, one baseline. This used to level the box HEIGHTS only, which
		# is half the rule and left the visible half unfixed: `make_tile_skeleton`
		# centres its inner column, so two equal boxes still centred a two-line
		# rule and a four-line rule separately and put the icons 23px apart.
		# `level_tile_row` levels the heights AND top-aligns the columns.
		GameTheme.level_tile_row(spoil_tiles)

	# The General's Forge — Generals only (bosses hand out the boss tier and
	# an act transition; the forge is the elite ladder's own rung).
	var forge_candidates := _forge_candidates()
	if not card_pending_now and RunState.current_node_type == "elite" \
			and (_relic_taken or _relic_choices.is_empty()) and not _forge_done \
			and forge_candidates.size() > 0:
		var forge_header := _make_section_header(
			"The General's Forge — pick a card to forge")
		outer.add_child(forge_header)
		GameTheme.deal_in(forge_header, 0.18)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 240)
		outer.add_child(scroll)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 14)
		grid.alignment = BoxContainer.ALIGNMENT_CENTER
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		_populate_forge_grid(grid, forge_candidates, ui_generation)

	# THE MOST-REPEATED PRESS IN THE GAME OUTSIDE COMBAT (2026-08-05). A run
	# passes through this screen after every fight — ~21 times — and "Continue"
	# was a frameless `make_back_button`, i.e. the way ON rendered as a caption
	# floating under the reward it concludes. It is the forward move, so it takes
	# the house forward-move plate.
	var skip_btn = GameTheme.make_primary_button("Continue", Vector2(220, 52), 20)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_skip)
	GameTheme.arm_ui_press(skip_btn, "commit")
	outer.add_child(skip_btn)
	GameTheme.deal_in(skip_btn, 0.40)
	GameTheme.hover_lift(skip_btn, 1.04)


## The kingdom dyes exist to tell five factions apart on the war table, and two
## of the five (Grasswake's teal, Lanternhall's blue) are cool. On the spoils
## sheet — blood, ash and gilt — a cool banner stops reading as heraldry and
## starts reading as an unpainted placeholder icon. Warm the dye into the
## screen's own ink: enough of it survives to tell the companies apart, but no
## flag can come out bluer than the fire behind it.
func _heraldry_ink(dye: Color) -> Color:
	return dye.lerp(GameTheme.GILT, 0.55)


## Rest / hover / pressed faces of a spoil tile, one lever (0 = rest, 1 = hot).
## The ember bleed is the stylebox's OWN shadow retinted — the kit's hover-glow
## lever — rather than a gradient pasted behind the tile.
func _spoil_style(lift: float) -> StyleBox:
	var s := GameTheme.make_panel_style(
		SPOIL_FILL.lightened(lift * 0.10),
		GameTheme.GILT.lerp(GameTheme.GILT_BRIGHT, lift), 2, 5, true, true)
	s.set("shadow_color", Color(SPOIL_EMBER.r, SPOIL_EMBER.g, SPOIL_EMBER.b,
		0.20 + 0.16 * lift))
	s.set("shadow_size", 16.0 + 8.0 * lift)
	return s


## A spoil tile. GameTheme.make_relic_card sizes its icon from the BOX
## (min_size.y * 0.38, capped at 128), a recipe that only balances around a
## ~147px tile — at the sizes a spoils screen asks for, a third of the tile is
## air, and that air is exactly what reads as a flat dark panel. This cuts it
## the other way round: pick the size of the painting first, then let
## fit_tile_height close the box onto it. Mirrored in Treasure._make_spoil_tile
## (the same duplication the two screens already carry for _make_section_header).
func _make_spoil_tile(rid: String) -> Button:
	var r: Dictionary = RelicDB.get_relic(rid)
	var skel: Dictionary = GameTheme.make_tile_skeleton(Vector2(SPOIL_TILE_W, 0), 6)
	var btn: Button = skel.button
	btn.tooltip_text = "%s — %s" % [r.get("name", rid), r.get("desc", "")]
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", _spoil_style(0.0))
	btn.add_theme_stylebox_override("hover", _spoil_style(1.0))
	btn.add_theme_stylebox_override("pressed", _spoil_style(0.45))

	var col: VBoxContainer = skel.col
	# The chip keeps its own StS rich hover (it is the only part of the tile
	# that carries the tier halo), exactly as it did under make_relic_card.
	var chip := GameTheme.make_relic_chip(rid, SPOIL_ICON_PX)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	var name_lbl := GameTheme.make_label(r.get("name", rid), 22,
		GameTheme.KEYWORD_GOLD)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)

	var desc_lbl := GameTheme.make_label(r.get("desc", ""), 18, GameTheme.IVORY)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_lbl)

	GameTheme.fit_tile_height(btn, col)
	return btn


## Yield to a frame that can actually be presented. `frame_post_draw` keeps the
## visible Compatibility-renderer path honest; it never fires under headless,
## where `process_frame` is the safe equivalent used by probes.
func _present_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## Collapse duplicate deck entries before warming. The forge still shows every
## physical card, but two identical writs share one immutable face texture.
func _forge_datas(candidates: Array[int]) -> Array:
	var datas: Array = []
	var seen := {}
	for deck_index in candidates:
		if deck_index < 0 or deck_index >= RunState.deck.size():
			continue
		var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
		if data.is_empty():
			continue
		var key: String = CardTextureCache.cache_key(data)
		if seen.has(key):
			continue
		seen[key] = true
		datas.append(data)
	return datas


## The relic-claim ceremony already owns about half a second of screen time.
## Warm the soon-to-open forge during that motion instead of beginning eleven
## independent one-card jobs after `_build_ui` has blocked the click handler.
func _warm_forge_candidates() -> void:
	if RunState.current_node_type != "elite" or _forge_warm_busy \
			or _forge_done or not is_inside_tree():
		return
	var datas: Array = _forge_datas(_forge_candidates())
	if datas.is_empty():
		return
	_forge_warm_busy = true
	var still_wanted := func() -> bool:
		return is_inside_tree() and not _forge_done
	await CardTextureCache.bake_many(datas, still_wanted)
	_forge_warm_busy = false


## Populate the General's Forge without making one giant UI frame. The final
## tree and pixels match the old synchronous loop: same wrappers, detailed
## Card2D faces, halos, click layer, scale, ordering, and reveal cadence.
func _populate_forge_grid(grid: HBoxContainer, candidates: Array[int],
		generation: int) -> void:
	# Even a fully warm cache used to construct the first ornate card inside the
	# `_build_ui` call. Let the newly rebuilt parchment present first.
	await _present_frame()
	var still_here := func() -> bool:
		return is_inside_tree() and _ui_generation == generation \
			and is_instance_valid(grid) and grid.is_inside_tree() \
			and not _forge_done
	if not still_here.call():
		return

	# Seat the whole row before any cache wait. These are real, final-size card
	# backs, not zero-alpha holes, so the General's offer reads as one facedown
	# hand while the ornate faces hydrate and the centered HBox never reflows.
	var wrappers: Array[Control] = []
	var loading_backs: Array[Control] = []
	for _deck_index in candidates:
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(162, 216)
		wrapper.pivot_offset = wrapper.custom_minimum_size * 0.5
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_add_forge_candidate_halo(wrapper)
		var loading_back := _make_forge_loading_back(wrapper, grid)
		grid.add_child(wrapper)
		wrappers.append(wrapper)
		loading_backs.append(loading_back)
		_forge_card_nodes.append(wrapper)

	# A relic click may already be warming this exact slate during its pocket
	# animation. Wait for that owner rather than enqueueing duplicate batch jobs.
	while _forge_warm_busy:
		await _present_frame()
		if not still_here.call():
			return

	await CardTextureCache.bake_many(_forge_datas(candidates), still_here)
	if not still_here.call():
		return
	# Cold batches resume on their texture-publish frame; warm batches resume
	# synchronously. One common boundary keeps the first live card off both.
	await _present_frame()
	if not still_here.call():
		return

	# One StyleBoxEmpty is immutable here and can back every transparent hit
	# layer. The old loop allocated three resources for every deck card.
	var empty_style := StyleBoxEmpty.new()
	var card_nodes: Array[Control] = []
	var click_buttons: Array[Button] = []
	for candidate_index in range(candidates.size()):
		if not still_here.call():
			return
		var deck_index: int = candidates[candidate_index]
		if deck_index < 0 or deck_index >= RunState.deck.size():
			continue
		var wrapper: Control = wrappers[candidate_index]
		var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		# Split RichText shaping from the rest of Card2D construction. The wrapper
		# remains at alpha zero until both stages are complete, so this is exactly
		# the same detailed face when it is finally dealt.
		card_node.defer_baked_rules_text = true
		card_node.scale = Vector2(0.72, 0.72)
		card_node.visible = false
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, 1)
		card_nodes.append(card_node)

		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.disabled = true
		click_btn.add_theme_stylebox_override("normal", empty_style)
		click_btn.add_theme_stylebox_override("hover", empty_style)
		click_btn.add_theme_stylebox_override("pressed", empty_style)
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.mouse_entered.connect(_on_forge_card_hover.bind(wrapper, true))
		click_btn.mouse_exited.connect(_on_forge_card_hover.bind(wrapper, false))
		click_btn.button_down.connect(_on_forge_card_pressed.bind(wrapper, true))
		click_btn.button_up.connect(_on_forge_card_pressed.bind(wrapper, false))
		click_btn.pressed.connect(_pick_forge_candidate.bind(deck_index, wrapper))
		wrapper.add_child(click_btn)
		click_buttons.append(click_btn)

		await _present_frame()
		if not still_here.call():
			return
		card_node.complete_deferred_baked_rules()
		await _present_frame()
		if not still_here.call():
			return

	# Rendering may be sequential; presentation is not. Close every back on the
	# same frame, then open every completed face on the same frame. No card enters
	# the centered row late and no implementation-order stagger leaks to players.
	var reduced_motion := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if not reduced_motion:
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for loading_back in loading_backs:
			Motion.flip_out(loading_back, 0.13)
		await get_tree().create_timer(Motion.time(0.13)).timeout
		if not still_here.call():
			return
	for candidate_index in range(wrappers.size()):
		var card_node: Control = card_nodes[candidate_index]
		var click_btn: Button = click_buttons[candidate_index]
		if reduced_motion:
			var loading_back = loading_backs[candidate_index]
			if is_instance_valid(loading_back):
				loading_back.queue_free()
		card_node.visible = true
		if not reduced_motion:
			Motion.flip_in(card_node, 0.0, 0.16)
		click_btn.disabled = false


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


func _enable_forge_button_after(button: Button, delay: float,
		generation: int) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree() and _ui_generation == generation \
			and is_instance_valid(button) and button.is_inside_tree() \
			and not _forge_done:
		button.disabled = false


func _forge_candidate_halo_texture() -> GradientTexture2D:
	if _forge_halo_texture != null:
		return _forge_halo_texture
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.77, 0.30, 0.20))
	grad.set_color(1, Color(1.0, 0.54, 0.12, 0.0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.56)
	grad_tex.fill_to = Vector2(1.0, 0.56)
	grad_tex.width = 220
	grad_tex.height = 260
	_forge_halo_texture = grad_tex
	return _forge_halo_texture


func _add_forge_candidate_halo(wrapper: Control) -> void:
	var halo := TextureRect.new()
	halo.texture = _forge_candidate_halo_texture()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.z_index = -1
	halo.position = Vector2(-26, -22)
	halo.size = Vector2(214, 260)
	wrapper.add_child(halo)


func _on_forge_card_hover(wrapper: Control, hovered: bool) -> void:
	if wrapper == null or not is_instance_valid(wrapper) or _forge_picking:
		return
	wrapper.z_index = 4 if hovered else 0
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var target := Vector2(1.045, 1.045) if hovered else Vector2.ONE
	var tw := wrapper.create_tween()
	tw.tween_property(wrapper, "scale", target, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_forge_card_pressed(wrapper: Control, pressed: bool) -> void:
	if wrapper == null or not is_instance_valid(wrapper) or _forge_picking:
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var target := Vector2(0.985, 0.985) if pressed else Vector2(1.045, 1.045)
	var tw := wrapper.create_tween()
	tw.tween_property(wrapper, "scale", target, 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _pick_forge_candidate(deck_index: int, wrapper: Control = null) -> void:
	if _forge_picking:
		return
	_forge_picking = true
	# Was a bare `button_click` — the generic dry click that is also standing in
	# for six unrelated gameplay cues (doom tick, bone settle, candle out...).
	# Choosing which card to forge is a shell PICK, so it takes the shell's own
	# select voice; `button_click` goes back to being one sound with one job.
	if AudioBank != null:
		AudioBank.play_ui("select")
	if wrapper != null and is_instance_valid(wrapper) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(wrapper)
		for other in _forge_card_nodes:
			if other != wrapper and other is Control and is_instance_valid(other):
				GameTheme.fade_exit(other, 0.18)
		await get_tree().create_timer(0.20).timeout
	await _show_forge_confirm(deck_index)
	_forge_picking = false


## Back out of the forge confirm and put the slate back the way it was.
## fade_exit only tweens modulate.a — it does NOT free the node or stop it taking
## the mouse. Without this restore, cancelling left the passed-over candidates
## invisible but still hoverable and still clickable, so the player saw one card
## and a row of ghosts (reported as "you can't see the other options if you press
## cancel"). _forge_card_nodes is only rebuilt in _build_ui, so it is still valid
## here. Any future pick→confirm→cancel flow on this screen must call this.
func _restore_forge_slate() -> void:
	for other in _forge_card_nodes:
		if other is Control and is_instance_valid(other):
			other.modulate.a = 1.0
			other.scale = Vector2.ONE
			other.z_index = 0
	_forge_picking = false


## Deck indices eligible for the General's Forge — same filter as the rest
## site and Olympian's Mark: unforged, upgradeable, a real playable card.
func _forge_candidates() -> Array[int]:
	var out: Array[int] = []
	for i in RunState.deck.size():
		if RunState.has_upgrade_path(i, "plus"):
			continue
		if not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
		if d.get("type", "") in ["creature", "spell", "armament"]:
			out.append(i)
	return out


## Before/after confirm — the same clean forge moment the rest site sells:
## current writ, arrow, "+" writ, and a one-line diff. Commit or back out.
func _show_forge_confirm(deck_index: int) -> void:
	var base_data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	var upgraded_data: Dictionary = RunState.preview_plus_upgrade(base_data)
	var generation := _ui_generation
	var still_here := func() -> bool:
		return is_inside_tree() and _ui_generation == generation and not _forge_done
	# The forged face owns a new cache key. Finish that one immutable background
	# before constructing either live overlay, then keep the two ornate Card2D
	# trees on separate presented frames below.
	await CardTextureCache.bake_many([base_data, upgraded_data], still_here)
	if not still_here.call():
		return
	await _present_frame()
	if not still_here.call():
		return

	var dim := ColorRect.new()
	dim.name = "ForgeDim"
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	# Keep the whole sheet hidden while its two full card trees hydrate. It still
	# blocks input, but no half-built card or rules box can flash on screen.
	dim.modulate.a = 0.0

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -400
	col.offset_right = 400
	col.offset_top = -260
	col.offset_bottom = 260
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	dim.add_child(col)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	col.add_child(row)
	var preview_wrappers: Array[Control] = []
	var preview_cards: Array[Control] = []
	var preview_backs: Array[Control] = []
	var preview_arrow: Control = null
	for pair in [[base_data, false], [upgraded_data, true]]:
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		if pair[1]:
			# Named so the forge-strike set-piece can aim at the "+" card.
			wrapper.name = "ForgedPreview"
			_add_forge_preview_halo(wrapper)
		var loading_back := _make_forge_loading_back(wrapper, row)
		row.add_child(wrapper)
		preview_wrappers.append(wrapper)
		preview_backs.append(loading_back)
		if not pair[1]:
			var arrow = GameTheme.make_label("→", 44, GameTheme.GILT_BRIGHT)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
			preview_arrow = arrow

	# Hydrate behind the two already-seated backs. The arrow and both final
	# footprints exist before the first await, so the comparison cannot recenter.
	for pair_index in range(2):
		var pair: Array = [[base_data, false], [upgraded_data, true]][pair_index]
		var wrapper: Control = preview_wrappers[pair_index]
		var loading_back: Control = preview_backs[pair_index]
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = pair[0]
		card_node.live_baked_mode = true
		card_node.defer_baked_rules_text = true
		if pair[1]:
			card_node.modulate = Color(1.06, 1.03, 0.94)
		card_node.visible = false
		wrapper.add_child(card_node)
		wrapper.move_child(card_node, loading_back.get_index())
		preview_cards.append(card_node)
		await _present_frame()
		if not still_here.call():
			dim.queue_free()
			return
		card_node.complete_deferred_baked_rules()
		await _present_frame()
		if not still_here.call():
			dim.queue_free()
			return

	var diff = GameTheme.make_label(
		_forge_change_summary(base_data, upgraded_data), 17, GameTheme.IVORY)
	diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(diff)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 24)
	col.add_child(btns)
	# ONE-SHOT LATCH for the whole sheet. Forge + holds the frame for the length of
	# forge_strike (~0.6s) with the button still live, so a double-click used to
	# stack TWO "plus" entries on one uid — get_upgraded_card_data folds the delta
	# twice (a 0/4 body came out 0/8) — and then hit a freed-instance error on the
	# second pass. Back had the same shape (double _restore_forge_slate). Lambdas
	# capture primitives by VALUE, so the flag rides in an array to stay shared.
	var acted := [false]
	var go = GameTheme.make_themed_button("⚒ Forge +", Color(0.14, 0.10, 0.05),
		Vector2(180, 48), 19)
	go.pressed.connect(func():
		if acted[0]:
			return
		acted[0] = true
		RunState.upgrade_card(deck_index, "plus")
		AudioBank.play_sfx("upgrade_confirm")
		_forge_done = true
		# The strike lands on the "+" card, THEN the sheet closes.
		await GameTheme.forge_strike(self, dim.find_child("ForgedPreview", true, false))
		dim.queue_free()
		_after_spoil_taken()
	)
	btns.add_child(go)
	var back = GameTheme.make_back_button("Back", Vector2(140, 48), 18)
	back.pressed.connect(func():
		if acted[0]:
			return
		acted[0] = true
		dim.queue_free()
		_restore_forge_slate()
	)
	btns.add_child(back)

	# Reveal the common scrim first, then turn both comparison cards together.
	# Their content was built on separate frames, but that renderer detail never
	# becomes a fake left-to-right narrative beat.
	if preview_arrow != null:
		GameTheme.deal_in(preview_arrow, 0.08)
	if UserSettings != null and UserSettings.reduce_motion:
		dim.modulate.a = 1.0
	else:
		dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.16) \
			.set_ease(Tween.EASE_OUT)
	_reveal_reward_preview_group(preview_cards, preview_backs, generation, dim)


func _reveal_reward_preview_group(cards: Array[Control], backs: Array[Control],
		generation: int, owner: Control) -> void:
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if snap:
		for i in range(cards.size()):
			if is_instance_valid(backs[i]):
				backs[i].queue_free()
			if is_instance_valid(cards[i]):
				cards[i].visible = true
		return
	await get_tree().create_timer(Motion.time(0.08)).timeout
	if not is_inside_tree() or _ui_generation != generation \
			or not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	AudioBank.play_sfx("card_draw", 0.04, -6.0)
	for loading_back in backs:
		if is_instance_valid(loading_back):
			Motion.flip_out(loading_back, 0.13)
	await get_tree().create_timer(Motion.time(0.13)).timeout
	if not is_inside_tree() or _ui_generation != generation \
			or not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	for card in cards:
		if is_instance_valid(card):
			card.visible = true
			Motion.flip_in(card, 0.0, 0.16)


func _add_forge_preview_halo(wrapper: Control) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.82, 0.42, 0.42))
	grad.set_color(1, Color(0.95, 0.46, 0.10, 0.0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.width = 320
	grad_tex.height = 360
	var halo := TextureRect.new()
	halo.texture = grad_tex
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.z_index = -1
	halo.position = Vector2(-48, -42)
	halo.size = Vector2(321, 384)
	wrapper.add_child(halo)


func _forge_change_summary(base: Dictionary, upgraded: Dictionary) -> String:
	var parts: Array[String] = []
	if base.get("type", "") == "creature":
		if int(upgraded.get("atk", 0)) != int(base.get("atk", 0)):
			parts.append("ATK %d → %d" % [int(base.get("atk", 0)), int(upgraded.get("atk", 0))])
		if int(upgraded.get("hp", 0)) != int(base.get("hp", 0)):
			parts.append("HP %d → %d" % [int(base.get("hp", 0)), int(upgraded.get("hp", 0))])
	if int(upgraded.get("cost", 0)) != int(base.get("cost", 0)):
		parts.append("Cost %d → %d" % [int(base.get("cost", 0)), int(upgraded.get("cost", 0))])
	if parts.is_empty():
		return "Effect improved — see the upgraded card."
	return "   ·   ".join(parts)


## After a spoil (relic or forge) is consumed: leave if nothing actionable
## remains, otherwise rebuild with the remaining offers.
func _after_spoil_taken() -> void:
	# The card offer counts as pending too, or taking a relic would walk off the
	# screen with the card still unclaimed — the defect the old screen avoided
	# by having only one offer on it.
	var card_pending: bool = _card_choices.size() > 0 and not _card_taken
	var relic_pending: bool = _is_elite_reward \
		and _relic_choices.size() > 0 and not _relic_taken
	var forge_pending: bool = RunState.current_node_type == "elite" \
		and not _forge_done and _forge_candidates().size() > 0
	if card_pending or relic_pending or forge_pending:
		_build_ui()
	else:
		_proceed()


## Take one of the offered cards.
func _pick_card(id: String, tile: Control = null) -> void:
	if _spoil_claiming or _card_taken:
		return
	_spoil_claiming = true
	RunState.add_card(id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	if tile != null and is_instance_valid(tile):
		# A card joins the same company the relics do. The old beat popped the
		# choice, then erased the whole slate during the rebuild; carrying it to
		# the standard makes the state change spatially legible.
		GameTheme.claim_pop(tile)
		if tile.get_parent() != null:
			for sib in tile.get_parent().get_children():
				if sib != tile and sib is Control:
					GameTheme.fade_exit(sib, 0.22)
		await get_tree().create_timer(0.10).timeout
		if _company_standard_anchor != null \
				and is_instance_valid(_company_standard_anchor):
			var target := _company_standard_anchor.global_position \
				+ _company_standard_anchor.size * 0.5
			await GameTheme.pocket_away(tile, target, 0.34)
			GameTheme.punch(_company_standard_anchor, 1.12)
	# COLLECTOR'S TOME enlists a second card. Bosses are exempt — their slate is
	# already the richest in the game, which is the rule the relic shipped with.
	if RunState.has_relic("collectors_tome") and _collectors_tome_picks < 1 \
			and RunState.current_node_type != "boss":
		_collectors_tome_picks += 1
		_card_choices.erase(id)
		_spoil_claiming = false
		if not _card_choices.is_empty():
			_build_ui()
			return
	_card_taken = true
	_spoil_claiming = false
	_after_spoil_taken()


## Decline the whole slate. Free — see the note in `_build_ui`.
func _skip_card() -> void:
	if _spoil_claiming or _card_taken:
		return
	_card_taken = true
	if AudioBank != null:
		AudioBank.play_sfx("ui_back")
	_after_spoil_taken()


func _pick_relic(id: String, tile: Control = null) -> void:
	if _spoil_claiming:
		return
	_spoil_claiming = true
	RunState.add_relic(id)
	_relic_taken = true
	# Use the existing claim/pocket ceremony as cover for the next screen state.
	# Fire-and-forget: `_populate_forge_grid` waits on the ownership flag above.
	_warm_forge_candidates()
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	# The chosen spoil is physically taken: rivals bow out, then the relic dives
	# into the company standard instead of disappearing during a UI rebuild.
	if tile != null and is_instance_valid(tile):
		GameTheme.claim_pop(tile)
		if tile.get_parent() != null:
			for sib in tile.get_parent().get_children():
				if sib != tile and sib is Control:
					GameTheme.fade_exit(sib, 0.22)
		await get_tree().create_timer(0.10).timeout
		if _company_standard_anchor != null \
				and is_instance_valid(_company_standard_anchor):
			var target := _company_standard_anchor.global_position \
				+ _company_standard_anchor.size * 0.5
			await GameTheme.pocket_away(tile, target, 0.34)
			GameTheme.punch(_company_standard_anchor, 1.12)
		else:
			await get_tree().create_timer(0.28).timeout
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	# Don't march off with the General's Forge still hot — the screen stays
	# until every spoil is taken or the player chooses Continue.
	_after_spoil_taken()


func _skip() -> void:
	if _spoil_claiming:
		return
	_proceed()


## After the spoils: a boss victory with more than one kingdom left to invade
## asks the player where the war goes next (Successor Wars player-chosen
## rival order). Everything else marches straight out.
func _proceed() -> void:
	if _leaving:
		return
	_leaving = true
	if RunState.current_node_type == "boss" and not RunState.should_enter_finale():
		var candidates: Array[String] = RunState.get_next_march_candidates()
		if candidates.size() >= 2:
			_show_march_choice(candidates)
			return
	_go_to_map()


func _show_march_choice(candidates: Array[String]) -> void:
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
	outer.add_theme_constant_override("separation", 18)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(outer)

	var title = GameTheme.make_screen_title("THE NEXT MARCH",
		GameTheme.GILT_BRIGHT, GameTheme.FONT_HEADER)
	outer.add_child(title)
	GameTheme.deal_in(title, 0.04)

	var march_header := _make_section_header("Choose which kingdom to invade next.")
	outer.add_child(march_header)
	GameTheme.deal_in(march_header, 0.10)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)

	# Lord tiles (2026-07-02): the campaign's biggest narrative decision used
	# to be two generic text banners — now each living rival stands as a
	# portrait plaque in his faction's color: face, name, title, kingdom, and
	# how his army fights. The provisional finale candidate joins the slate;
	# whichever lord survives the Act 2 choice takes the throne.
	for i in candidates.size():
		var lord: String = candidates[i]
		var tile := _make_lord_tile(lord)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)
		GameTheme.deal_in(tile, 0.12 + i * 0.10)
		GameTheme.hover_lift(tile)


func _make_lord_tile(lord: String) -> Button:
	var faction: String = HeroDB.get_faction(lord)
	var info: Dictionary = HeroDB.faction_info(faction)
	var fcolor: Color = info.get("color", Color(0.60, 0.51, 0.34))
	var hero: Dictionary = HeroDB.get_hero(lord)

	var btn := Button.new()
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	# Fixed footprint — the VBox child is anchored (not size-driving), so the
	# tile must claim its own height: portrait 250 + four text rows + margins.
	btn.custom_minimum_size = Vector2(316, 470)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := GameTheme.make_panel_style(Color(0.055, 0.048, 0.040, 0.96),
		fcolor.lerp(GameTheme.GILT, 0.35), 1, 4, true, true)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := GameTheme.make_panel_style(Color(0.085, 0.070, 0.052, 0.97),
		GameTheme.GILT_BRIGHT, 1, 4, true, true)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(_pick_march.bind(lord, btn))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 16
	col.offset_bottom = -16
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 7)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	# Portrait — the rival lords ARE the five heroes, so their painted
	# portraits serve double duty. Monogram plate fallback if one is missing.
	var port_path := "res://assets/portraits/hero_portrait_%s.png" % lord
	if ResourceLoader.exists(port_path):
		var portrait := TextureRect.new()
		portrait.texture = load(port_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = Vector2(200, 250)
		portrait.clip_contents = true
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.modulate = Color(0.94, 0.91, 0.88)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(portrait)
	else:
		var mono = GameTheme.make_label(
			String(hero.get("name", lord)).strip_edges().left(1).to_upper(),
			84, Color(fcolor.r, fcolor.g, fcolor.b, 0.85))
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.custom_minimum_size = Vector2(200, 250)
		mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(mono)

	var name_lbl = GameTheme.make_label(
		String(hero.get("name", lord)).to_upper(), 23, GameTheme.GILT_BRIGHT, true)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var title_lbl = GameTheme.make_label(String(info.get("lord_title", "")), 15,
		GameTheme.IVORY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_lbl)

	# Faction rule in the kingdom's dye — the tile's heraldry line.
	var rule := ColorRect.new()
	rule.color = Color(fcolor.r, fcolor.g, fcolor.b, 0.85)
	rule.custom_minimum_size = Vector2(120, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var kingdom_lbl = GameTheme.make_label("%s  ·  %s" % [
		String(info.get("name", "")), String(info.get("engine", ""))], 15,
		fcolor.lerp(Color(0.95, 0.92, 0.84), 0.45))
	kingdom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kingdom_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(kingdom_lbl)

	var engine_lbl = GameTheme.make_label(String(info.get("engine_line", "")), 14,
		GameTheme.DESC_DIM)
	engine_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	engine_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	engine_lbl.custom_minimum_size = Vector2(260, 0)
	engine_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(engine_lbl)

	return btn


func _count_visited_current_act(node_type: String) -> int:
	var count := 0
	for row in RunState.get_current_act_map():
		for node in row:
			if bool(node.get("visited", false)) \
					and String(node.get("type", "")) == node_type:
				count += 1
	return count

func _make_section_header(text: String) -> HBoxContainer:
	# A ruled subheader plaque: tan rule — gold caption — tan rule. Echoes the
	# chart furniture (make_screen_title's divider) so the cue reads as a
	# document heading, not a stray label. Mirrors Treasure._make_section_header.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_col := Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.28)
	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(70, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = rule_col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	# Quiet parchment caption, not gold: this is a document subheading, and gold
	# here competes with the screen title. Hierarchy = gold title → dim heading.
	var lbl := GameTheme.make_label(text, 24, GameTheme.DESC_DIM)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(70, 1)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.color = rule_col
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	return row


func _pick_march(lord: String, tile: Control = null) -> void:
	if _march_picking:
		return
	_march_picking = true
	# Choosing the next lord to march on sets the route for the rest of the act —
	# a commit, not a browse, so it seals rather than clicks.
	if AudioBank != null:
		AudioBank.play_ui("commit")
	if tile != null and is_instance_valid(tile) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(tile)
		if tile.get_parent() != null:
			for sib in tile.get_parent().get_children():
				if sib != tile and sib is Control:
					GameTheme.fade_exit(sib, 0.22)
		await get_tree().create_timer(0.34).timeout
	RunState.choose_next_rival(lord)
	_go_to_map()


func _go_to_map() -> void:
	if _transition_started:
		return
	_leaving = true
	_transition_started = true
	# Boss rewards advance the act on their way out. Combat used to do this
	# before queuing the Reward transition, but that wiped current_node_type
	# and made Reward render as a normal fight. Holding the advance until
	# now lets Reward read node_type == "boss" while still putting the player
	# on the next act's map on exit.
	if RunState.current_node_type == "boss":
		# Successor Wars: when the act-3 rival falls, the road leads to the
		# throne, not a fourth map — straight into the amalgam fight.
		if RunState.should_enter_finale():
			RunState.enter_finale()
			GameTheme.fade_out_then_change_scene(self, COMBAT_SCENE)
			return
		RunState.advance_act()
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
