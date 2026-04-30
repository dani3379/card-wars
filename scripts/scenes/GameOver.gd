extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"


func _ready() -> void:
	MenuAtmosphere.attach_to(self)

	# Title font outline pop.
	$Title.add_theme_constant_override("outline_size", 8)
	$Title.add_theme_color_override("font_outline_color", Color(0.20, 0.05, 0.03, 1.0))

	if RunState.hero_hp > 0:
		$Title.text = "VICTORY"
		$Title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		$Subtitle.text = "The first flame is extinguished.\nFloors cleared: %d" % RunState.current_floor
	else:
		$Title.text = "DEFEAT"
		$Title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		$Subtitle.text = "The meadow burned without you.\nFloors reached: %d" % RunState.current_floor

	var stats := "Total runs: %d   Victories: %d" % [
		MetaState.total_runs, MetaState.total_victories,
	]
	if MetaState.last_unlocked_card != "":
		var unlocked = CardDB.get_card_data(MetaState.last_unlocked_card)
		if not unlocked.is_empty():
			stats += "\n\nNew card unlocked: %s" % unlocked.name
	$Stats.text = stats

	MenuAtmosphere.style_button($BackBtn, true)
	$BackBtn.pressed.connect(_back)


func _back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
