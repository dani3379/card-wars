extends Control
## MainMenu.gd — title screen. Start a new run, see stats, quit.

const MAP_SCENE = "res://scenes/map.tscn"


func _ready() -> void:
	MenuAtmosphere.attach_to(self)

	$VBox/TitleLabel.text = "BURNING MEADOW"
	$VBox/TitleLabel.add_theme_color_override(
		"font_outline_color", Color(0.30, 0.10, 0.05, 1.0))
	$VBox/TitleLabel.add_theme_constant_override("outline_size", 8)
	$VBox/Subtitle.text = "a grimoire-deck roguelike"

	MenuAtmosphere.style_button($VBox/StartBtn, true)
	MenuAtmosphere.style_button($VBox/QuitBtn, false)

	$VBox/StartBtn.pressed.connect(_on_start)
	$VBox/QuitBtn.pressed.connect(_on_quit)

	_refresh_stats()


func _refresh_stats() -> void:
	var unlocked := MetaState.unlocked_cards.size()
	var locked_remaining := CardDB.locked_card_ids().size()
	var s := "Runs: %d   Victories: %d   Defeats: %d\nCards unlocked: %d  (still locked: %d)" % [
		MetaState.total_runs,
		MetaState.total_victories,
		MetaState.total_defeats,
		unlocked,
		locked_remaining,
	]
	$VBox/StatsLabel.text = s


func _on_start() -> void:
	RunState.start_new_run()
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_quit() -> void:
	get_tree().quit()
