extends Control
## MainMenu.gd — title screen. Start a new run, see stats, quit.

const MAP_SCENE = "res://scenes/map.tscn"


func _ready() -> void:
	$VBox/TitleLabel.text = "BURNING MEADOW"
	$VBox/Subtitle.text = "a grimoire-deck roguelike"

	$VBox/StartBtn.pressed.connect(_on_start)
	$VBox/QuitBtn.pressed.connect(_on_quit)

	_refresh_stats()


func _refresh_stats() -> void:
	var s := "Runs: %d   Victories: %d   Defeats: %d" % [
		MetaState.total_runs,
		MetaState.total_victories,
		MetaState.total_defeats,
	]
	$VBox/StatsLabel.text = s


func _on_start() -> void:
	RunState.start_new_run()
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_quit() -> void:
	get_tree().quit()
