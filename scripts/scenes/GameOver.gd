extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"


func _ready() -> void:
	GameTheme.add_atmosphere(self, "game_over")
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
		var vcol := Color(0.4, 1.0, 0.5)
		$Title.add_theme_color_override("font_color", vcol)
		$Title.add_theme_color_override("font_outline_color", Color(vcol.r, vcol.g, vcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		$Subtitle.text = "The first flame is extinguished.\nFloors cleared: %d%s" % [
			RunState.current_floor, asc_suffix]
	else:
		$Title.text = "DEFEAT"
		var dcol := Color(1.0, 0.3, 0.3)
		$Title.add_theme_color_override("font_color", dcol)
		$Title.add_theme_color_override("font_outline_color", Color(dcol.r, dcol.g, dcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		$Subtitle.text = "The meadow burned without you.\nFloors reached: %d%s" % [
			RunState.current_floor, asc_suffix]

	$Stats.text = "Total runs %d  •  Victories %d" % [
		MetaState.total_runs, MetaState.total_victories,
	]

	_build_run_summary()

	# Replace the .tscn's plain BackBtn with our themed back button (gold pill,
	# leading ← arrow, display font). Rename + free the original first so the
	# replacement can take the "BackBtn" name immediately (queue_free is deferred,
	# so child-name lookups would otherwise see two nodes for one frame).
	var old_btn: Node = $BackBtn
	old_btn.name = "BackBtn_old"
	old_btn.queue_free()
	var styled := GameTheme.make_back_button("BACK TO MENU", Vector2(240, 50), 19)
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

	_animate_intro()


func _build_run_summary() -> void:
	# Detailed recap of the run that just ended — deck size, gold, relics —
	# the post-mortem read every roguelike player wants. Built as a panel
	# beneath the Stats line so it doesn't fight the headline VICTORY/DEFEAT.
	var panel := PanelContainer.new()
	panel.name = "RunSummaryPanel"
	panel.custom_minimum_size = Vector2(560, 0)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.09, 0.07, 0.92)
	s.border_color = Color(0.83, 0.74, 0.54, 0.85)  # GILT
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_size = 14
	s.shadow_color = Color(0, 0, 0, 0.5)
	panel.add_theme_stylebox_override("panel", s)
	# Center the 560-wide summary panel 100px below screen-center.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = 100
	panel.offset_bottom = 100  # height auto-expands from content
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := _make_summary_label("YOUR RUN", 20, Color(1.0, 0.85, 0.45))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	# Stats row: floor / gold / deck size in a single line of three.
	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 28)
	col.add_child(stats_row)
	stats_row.add_child(_stat_chip("Floor", str(RunState.current_floor)))
	stats_row.add_child(_stat_chip("Gold", str(RunState.gold)))
	stats_row.add_child(_stat_chip("Deck", "%d cards" % RunState.deck.size()))

	# Relics list — if more than 0, render their names as a centered comma list.
	if RunState.relics.size() > 0:
		var sep := ColorRect.new()
		sep.custom_minimum_size = Vector2(420, 1.5)
		sep.color = Color(0.83, 0.74, 0.54, 0.30)
		sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(sep)

		var rel_head := _make_summary_label("RELICS  (%d)" % RunState.relics.size(),
			14, Color(0.83, 0.74, 0.54, 0.85))
		rel_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rel_head)

		var names: Array = []
		for rid in RunState.relics:
			var r = RelicDB.get_relic(rid)
			if r != null and not r.is_empty():
				names.append(r.get("name", rid))
			else:
				names.append(rid)
		var rel_list := _make_summary_label(", ".join(names), 13,
			Color(0.96, 0.92, 0.78, 0.92))
		rel_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rel_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rel_list.custom_minimum_size = Vector2(480, 0)
		col.add_child(rel_list)


func _stat_chip(label: String, value: String) -> VBoxContainer:
	# Pair of stacked labels: small dim label on top, large bright value below.
	# Reads as a "stat plaque" — clearer than "Floor: 8" inline.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	var lbl := _make_summary_label(label, 12, Color(0.62, 0.58, 0.52, 0.92))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	var val := _make_summary_label(value, 22, Color(1.0, 0.85, 0.45))
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
