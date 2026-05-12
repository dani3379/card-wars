extends Control
## MainMenu.gd — title screen. Start a new run, see stats, quit.

const MAP_SCENE = "res://scenes/map.tscn"
const COLLECTION_SCENE = "res://scenes/collection.tscn"


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")

	$VBox/TitleLabel.text = "BURNING MEADOW"
	$VBox/TitleLabel.add_theme_color_override("font_outline_color",
		Color(1.0, 0.75, 0.25, 0.20))
	$VBox/TitleLabel.add_theme_constant_override("outline_size", 8)
	$VBox/Subtitle.text = "a lane combat roguelike deckbuilder"

	# Decorative separator below subtitle
	var sep := GameTheme.make_separator(GameTheme.GILT, 120.0)
	$VBox.add_child(sep)
	$VBox.move_child(sep, $VBox/Subtitle.get_index() + 1)

	# Card Gallery button — insert between Start and Quit
	var gallery_btn := Button.new()
	gallery_btn.name = "GalleryBtn"
	gallery_btn.text = "CARD GALLERY"
	gallery_btn.custom_minimum_size = Vector2(0, 44)
	$VBox.add_child(gallery_btn)
	$VBox.move_child(gallery_btn, $VBox/StartBtn.get_index() + 1)

	# Style the buttons so they match the game's visual language
	_style_menu_button($VBox/StartBtn, Color(0.18, 0.30, 0.14), 22)
	_style_menu_button(gallery_btn, Color(0.14, 0.16, 0.26), 18)
	_style_menu_button($VBox/QuitBtn, Color(0.20, 0.15, 0.12), 16)

	$VBox/StartBtn.pressed.connect(_on_start)
	gallery_btn.pressed.connect(func(): get_tree().change_scene_to_file(COLLECTION_SCENE))
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


func _style_menu_button(btn: Button, bg: Color, font_sz: int) -> void:
	var normal := GameTheme.make_btn_style(bg)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.18)
	hover.border_color = GameTheme.GILT_BRIGHT
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", GameTheme.IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80))
	btn.add_theme_font_size_override("font_size", font_sz)


func _on_quit() -> void:
	get_tree().quit()
