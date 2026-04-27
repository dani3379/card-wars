extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"


func _ready() -> void:
	var won = MetaState.total_victories > 0 and not RunState.run_active and RunState.hero_hp > 0
	# Cleaner: check if last node was boss and player_hp > 0 at scene change.
	# We rely on hero_hp > 0 as proxy for victory.
	if RunState.hero_hp > 0:
		$Title.text = "VICTORY"
		$Title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		$Subtitle.text = "The first flame is extinguished.\nFloors cleared: %d" % RunState.current_floor
	else:
		$Title.text = "DEFEAT"
		$Title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		$Subtitle.text = "The meadow burned without you.\nFloors reached: %d" % RunState.current_floor

	$Stats.text = "Total runs: %d   Victories: %d" % [
		MetaState.total_runs, MetaState.total_victories,
	]
	$BackBtn.pressed.connect(_back)


func _back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
