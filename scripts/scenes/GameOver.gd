extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"

# Diegetic run-end refrains (Direction C: the player is an effigy the burning
# meadow keeps re-casting). Rotated by total defeat count so the framing shifts
# a little each loop. Hard cap of 3 by design — more reads as content churn, not
# as a refrain the meadow recites.
const DEATH_REFRAINS := [
	"The meadow makes another of you. It always has spares.",
	"You stop here. The road doesn't.",
	"That's one more walk that didn't reach the fire. There will be others.",
]


func _ready() -> void:
	# Lift the crushed background. Two crushers were stacking: the .tscn's
	# Background.self_modulate (≈0.2 brightness) and the "game_over" mood's
	# heavy vignette. Raise the modulate and soften the vignette/gradient so the
	# painted end-of-run art actually reads behind the summary panel.
	var bg := get_node_or_null("Background")
	if bg != null:
		bg.self_modulate = Color(0.46, 0.42, 0.46, 1.0)
	GameTheme.add_atmosphere(self, "game_over", true, {
		"vignette": 0.40,
		"grad_outer": Color(0.02, 0.01, 0.03, 0.50),
	})
	AudioBank.play_music("victory" if RunState.hero_hp > 0 else "defeat")

	# Apply display font to title
	if GameTheme.font_display:
		$Title.add_theme_font_override("font", GameTheme.font_display)
	if GameTheme.font_body:
		$Subtitle.add_theme_font_override("font", GameTheme.font_body)
		$Stats.add_theme_font_override("font", GameTheme.font_body)

	# Ascension suffix is only meaningful if the player actually ran one.
	var asc_suffix: String = ""
	if RunState.current_ascension > 0:
		asc_suffix = "\nAscension %d" % RunState.current_ascension
	if RunState.hero_hp > 0:
		$Title.text = "VICTORY"
		var vcol := Color(1.0, 0.84, 0.38)
		$Title.add_theme_color_override("font_color", vcol)
		$Title.add_theme_color_override("font_outline_color", Color(vcol.r, vcol.g, vcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		# A conquest run ends on the throne — and the throne is the eternal
		# cycle (§15.1 #1): winning makes you the next thing worth marching on.
		if RunState.finale_stage == 1:
			$Subtitle.text = "The throne is yours, and everything it owes.\nFloors cleared: %d%s" % [
				RunState.current_floor, asc_suffix]
		else:
			$Subtitle.text = "The first flame is extinguished.\nFloors cleared: %d%s" % [
				RunState.current_floor, asc_suffix]
	else:
		$Title.text = "DEFEAT"
		var dcol := Color(1.0, 0.3, 0.3)
		$Title.add_theme_color_override("font_color", dcol)
		$Title.add_theme_color_override("font_outline_color", Color(dcol.r, dcol.g, dcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		# "Killed by X" line surfaces the cause-of-death captured by Combat
		# when the player went to 0 HP. Mid-run quits (no death) leave the
		# string empty, so we only append it when it's actually meaningful.
		var death_line: String = ""
		if RunState.cause_of_death != "":
			death_line = "\nFelled by %s" % RunState.cause_of_death
		# Rotate the loop refrain by defeat count. Modulo keeps the index valid
		# even on a mid-run quit (total_defeats may be 0 → index 0).
		var refrain: String = DEATH_REFRAINS[MetaState.total_defeats % DEATH_REFRAINS.size()]
		$Subtitle.text = "%s\nFloors reached: %d%s%s" % [
			refrain, RunState.current_floor, asc_suffix, death_line]

	$Stats.text = "Total Runs %d  •  Victories %d" % [
		MetaState.total_runs, MetaState.total_victories,
	]
	# The .tscn ships this at 14px / dim grey — too faint to read over the lifted
	# background. Bump to a legible gilt caption.
	$Stats.add_theme_font_size_override("font_size", 17)
	$Stats.add_theme_color_override("font_color", Color(0.90, 0.80, 0.52, 1.0))
	$Stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	$Stats.add_theme_constant_override("outline_size", 3)

	_build_run_summary()

	# Replace the .tscn's plain BackBtn with our themed back button (gold pill,
	# leading ← arrow, display font). Rename + free the original first so the
	# replacement can take the "BackBtn" name immediately (queue_free is deferred,
	# so child-name lookups would otherwise see two nodes for one frame).
	var old_btn: Node = $BackBtn
	old_btn.name = "BackBtn_old"
	old_btn.queue_free()
	var styled := GameTheme.make_back_button("BACK TO MENU", Vector2(240, 50))
	styled.name = "BackBtn"
	# Anchor a 240×50 rect to the bottom-center. Manual anchors+offsets avoid
	# the PRESET_CENTER_BOTTOM+position trap that pushed the control off-screen.
	styled.anchor_left = 0.5
	styled.anchor_right = 0.5
	styled.anchor_top = 1.0
	styled.anchor_bottom = 1.0
	styled.offset_left = -120
	styled.offset_right = 120
	styled.offset_top = -150
	styled.offset_bottom = -100
	styled.pressed.connect(_back)
	add_child(styled)
	GameTheme.make_settings_gear(self)

	_animate_intro()


const CARD_SCENE = preload("res://scenes/card_2d.tscn")

# Thumbnail size for deck cards in the summary. Card2D's intrinsic size is
# 225×300; we display at scale = THUMB_W / 225 ≈ 0.4 to fit a deck of 15-25
# cards in 2 rows without colliding with the BackBtn at y≈800. The slot
# Control claims THUMB_SIZE so HFlowContainer lays them out compactly while
# the Card2D child shrinks via `scale`.
const THUMB_W: float = 90.0
const THUMB_H: float = 120.0
const THUMB_SIZE := Vector2(THUMB_W, THUMB_H)
const THUMB_SCALE: float = THUMB_W / 225.0


func _build_run_summary() -> void:
	# Detailed recap of the run that just ended — stats, mutators, relics,
	# and a thumbnail strip of the final deck. Replaces an earlier text-only
	# summary so the post-mortem matches the AAA polish of the in-combat HUD:
	# gilded relic chips instead of a comma list, deduplicated deck thumbnails
	# (with ×N stack badges) instead of "Deck: 12 cards".
	var panel := PanelContainer.new()
	panel.name = "RunSummaryPanel"
	panel.custom_minimum_size = Vector2(1280, 0)
	# Chart-look document plate (dark ink body + tan rule + small corners +
	# shadow) via the shared helper, instead of the old flat rounded rect.
	# make_panel_style returns a StyleBoxFlat, so we add the content margins it
	# doesn't expose afterward.
	var s := GameTheme.make_panel_style(
		Color(0.055, 0.048, 0.040, 0.94), GameTheme.GILT, 1, 4, true)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 16
	s.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", s)
	# Top-anchored at y=315 so it sits under the repositioned Stats label
	# (y≈275-305) with headroom for the BackBtn at y≈800.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -640
	panel.offset_right = 640
	panel.offset_top = 315
	panel.offset_bottom = 315  # height auto-expands from content
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := _make_summary_label("YOUR RUN", 20, Color(1.0, 0.85, 0.45))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	# Stats row: floor / fights won / gold. Deck count moved into the deck
	# strip header below since we now visualize the deck.
	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 28)
	col.add_child(stats_row)
	stats_row.add_child(_stat_chip("Floor", str(RunState.current_floor)))
	stats_row.add_child(_stat_chip("Fights Won", str(RunState.fights_won)))
	stats_row.add_child(_stat_chip("Gold", str(RunState.gold)))

	# Mutators survived — only show the strip if the player actually braved
	# any. Still rendered as text since mutators are conceptual debuffs, not
	# collectible items with art.
	if RunState.mutators_survived.size() > 0:
		_add_separator(col)
		var mhead := _make_summary_label(
			"MUTATORS SURVIVED  (%d)" % RunState.mutators_survived.size(),
			16, Color(0.90, 0.80, 0.56, 1.0))
		mhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(mhead)

		var mnames: Array = []
		for mid in RunState.mutators_survived:
			var m = MutatorDB.get_mutator(mid)
			if not m.is_empty():
				mnames.append(String(m.get("name", mid)))
			else:
				mnames.append(mid)
		var mlist := _make_summary_label(", ".join(mnames), 13,
			Color(1.0, 0.78, 0.42, 0.92))
		mlist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mlist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mlist.custom_minimum_size = Vector2(480, 0)
		col.add_child(mlist)

	# Relics — gilded chips with hover tooltips (name + desc), matching the
	# combat HUD strip. make_relic_chip handles tier-glow + icon/letter
	# fallback for icon-less relics, so this Just Works for every relic.
	if RunState.relics.size() > 0:
		_add_separator(col)
		var rel_head := _make_summary_label("RELICS  (%d)" % RunState.relics.size(),
			16, Color(0.90, 0.80, 0.56, 1.0))
		rel_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rel_head)

		var rel_flow := HFlowContainer.new()
		rel_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		rel_flow.add_theme_constant_override("h_separation", 8)
		rel_flow.add_theme_constant_override("v_separation", 8)
		rel_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(rel_flow)
		for rid in RunState.relics:
			rel_flow.add_child(GameTheme.make_relic_chip(rid, 52))

	# Deck — deduplicated Card2D thumbnails with ×N stack badges. Uses
	# CardTextureCache to cache the heavy v4 layout into a single TextureRect
	# per card; the panel still shows the live numerals + frame instead of a
	# count text. Async (await) because each uncached card needs ~2 frames to
	# bake; cached cards (typical mid-run case) return instantly.
	if RunState.deck.size() > 0:
		_add_separator(col)
		var deck_head := _make_summary_label(
			"DECK  (%d cards)" % RunState.deck.size(),
			16, Color(0.90, 0.80, 0.56, 1.0))
		deck_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(deck_head)

		var deck_flow := HFlowContainer.new()
		deck_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		deck_flow.add_theme_constant_override("h_separation", 10)
		deck_flow.add_theme_constant_override("v_separation", 12)
		deck_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(deck_flow)
		# Build deferred so the panel skeleton renders immediately and the
		# fade-in animation can start while bakes are still in flight.
		_populate_deck_strip(deck_flow)


func _add_separator(col: VBoxContainer) -> void:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(520, 1.5)
	sep.color = Color(0.83, 0.74, 0.54, 0.30)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(sep)


func _populate_deck_strip(parent: HFlowContainer) -> void:
	# Aggregate deck entries by visual identity (id + cost + atk + hp + sorted
	# keywords). Two upgraded Goblins stack; an upgraded + un-upgraded Goblin
	# do not. Order by cost ascending so the strip reads left-to-right cheap
	# to expensive — matches Collection's section ordering.
	var groups: Dictionary = {}   # key → {"data": Dictionary, "count": int}
	var order: Array[String] = []
	for i in RunState.deck.size():
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		if data.is_empty():
			continue
		var key: String = CardTextureCache.cache_key(data)
		if not groups.has(key):
			groups[key] = {"data": data, "count": 0}
			order.append(key)
		groups[key]["count"] += 1
	order.sort_custom(func(a, b):
		return int(groups[a]["data"].get("cost", 0)) < int(groups[b]["data"].get("cost", 0)))

	for key in order:
		var entry: Dictionary = groups[key]
		var slot := _make_deck_thumb(entry["data"], int(entry["count"]))
		if not is_inside_tree():
			return  # scene exited mid-bake
		parent.add_child(slot)
		await get_tree().process_frame


func _make_deck_thumb(card_data: Dictionary, count: int) -> Control:
	# Slot Control claims THUMB_SIZE so HFlowContainer reserves the right
	# footprint; the Card2D child renders at full 225×300 logical size but
	# `scale = THUMB_SCALE` shrinks it visually to fit. clip_contents = true
	# prevents the card's drop shadow from bleeding past the slot rect.
	var slot := Control.new()
	slot.custom_minimum_size = THUMB_SIZE
	slot.size = THUMB_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.clip_contents = false  # tooltip popup needs to extend past the slot

	var card = CARD_SCENE.instantiate()
	card.card_data = card_data.duplicate(true)
	card.card_id = card_data.get("id", "")
	# is_on_battlefield → no drag system, no hover lift. live_baked_mode →
	# uses CardTextureCache's baked texture once warm (cheap), falls back to
	# full layout on cold cache. Pre-baked just below.
	card.is_on_battlefield = true
	card.live_baked_mode = true
	card.scale = Vector2(THUMB_SCALE, THUMB_SCALE)
	card.position = Vector2.ZERO
	slot.add_child(card)
	# Bake in background so the first frame the slot exists, the cache is
	# already warm and Card2D's _build_layout picks the fast path. No await
	# here — the live overlay numerals stay correct even on cache miss.
	CardTextureCache.bake(card_data)

	if count > 1:
		slot.add_child(_make_count_badge(count))
	return slot


func _make_count_badge(n: int) -> Label:
	# Gilt-on-dark numeral chip in the bottom-right corner of a deck thumb,
	# inventory-game style. ×4 sticks ~20px in from the slot edges so the
	# badge sits on the card's parchment, not its frame.
	var badge := Label.new()
	badge.text = "×%d" % n
	badge.add_theme_font_size_override("font_size", 16)
	if GameTheme.font_stat:
		badge.add_theme_font_override("font", GameTheme.font_stat)
	badge.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.04, 0.92)
	bg.border_color = GameTheme.GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		bg.set(k, 1)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		bg.set(k, 4)
	badge.add_theme_stylebox_override("normal", bg)
	# Anchor a small chip to the bottom-right of THUMB_SIZE.
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -34
	badge.offset_right = -4
	badge.offset_top = -22
	badge.offset_bottom = -4
	return badge


func _stat_chip(label: String, value: String) -> VBoxContainer:
	# Pair of stacked labels: small dim label on top, large bright value below.
	# Reads as a "stat plaque" — clearer than "Floor: 8" inline.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	var lbl := _make_summary_label(label, 16, Color(0.84, 0.78, 0.64, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	var val := _make_summary_label(value, 26, Color(1.0, 0.86, 0.46))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(val)
	return box


func _make_summary_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if size >= 18 and GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	elif GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _animate_intro() -> void:
	# Title slams in with a back-eased overshoot; subtitle and stats follow.
	# Victory feels celebratory, defeat feels heavy — same beat, different colors
	# (color is already set above).
	$Title.pivot_offset = $Title.size * 0.5
	$Title.scale = Vector2(0.7, 0.7)
	$Title.modulate.a = 0.0
	$Subtitle.modulate.a = 0.0
	$Stats.modulate.a = 0.0
	$BackBtn.modulate.a = 0.0
	var summary := get_node_or_null("RunSummaryPanel")
	if summary != null:
		summary.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property($Title, "modulate:a", 1.0, 0.50).set_ease(Tween.EASE_OUT)
	tw.tween_property($Title, "scale", Vector2.ONE, 0.65) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property($Subtitle, "modulate:a", 1.0, 0.40).set_delay(0.45)
	tw.tween_property($Stats, "modulate:a", 1.0, 0.35).set_delay(0.65)
	if summary != null:
		tw.tween_property(summary, "modulate:a", 1.0, 0.50).set_delay(0.80)
	tw.tween_property($BackBtn, "modulate:a", 1.0, 0.30).set_delay(1.05)


func _back() -> void:
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)
