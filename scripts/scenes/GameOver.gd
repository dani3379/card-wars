extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"


func _ready() -> void:
	GameTheme.add_atmosphere(self, "game_over")

	# Apply display font to title
	if GameTheme.font_display:
		$Title.add_theme_font_override("font", GameTheme.font_display)
	if GameTheme.font_body:
		$Subtitle.add_theme_font_override("font", GameTheme.font_body)
		$Stats.add_theme_font_override("font", GameTheme.font_body)

	if RunState.hero_hp > 0:
		$Title.text = "VICTORY"
		var vcol := Color(0.4, 1.0, 0.5)
		$Title.add_theme_color_override("font_color", vcol)
		$Title.add_theme_color_override("font_outline_color", Color(vcol.r, vcol.g, vcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		$Subtitle.text = "The first flame is extinguished.\nFloors cleared: %d" % RunState.current_floor
	else:
		$Title.text = "DEFEAT"
		var dcol := Color(1.0, 0.3, 0.3)
		$Title.add_theme_color_override("font_color", dcol)
		$Title.add_theme_color_override("font_outline_color", Color(dcol.r, dcol.g, dcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		$Subtitle.text = "The meadow burned without you.\nFloors reached: %d" % RunState.current_floor

	$Stats.text = "Total runs: %d   Victories: %d" % [
		MetaState.total_runs, MetaState.total_victories,
	]

	# Style the back button
	var bg := Color(0.20, 0.15, 0.12)
	var normal := GameTheme.make_btn_style(bg)
	$BackBtn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.18)
	hover.border_color = GameTheme.GILT_BRIGHT
	$BackBtn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	$BackBtn.add_theme_stylebox_override("pressed", pressed)
	$BackBtn.add_theme_color_override("font_color", GameTheme.IVORY)
	$BackBtn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80))
	if GameTheme.font_display:
		$BackBtn.add_theme_font_override("font", GameTheme.font_display)
	$BackBtn.pressed.connect(_back)


func _back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
